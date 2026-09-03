# Runbook — source_evidence-rehearsal mod en engangs-restore

Manuel procedure for at køre ét hash-låst `source_evidence`-manifest gennem
den generelle genimport-writer (#153) mod en **disponerbar** restore af et
prod-dump. Proceduren er editionsneutral: udgaven kommer fra profil-JSON'en,
dumpet fra `--dump`/`$DUMP_PATH`. Ingen prod-forbindelse, intet push, ingen
merge. Prod-apply er en separat gate.

Alle personhenvisninger i denne runbook er `record_key`, tal og hashes.
Artefakter under `work/` er gitignorerede og må aldrig citeres.

> **Udførelsesstatus 2026-09-03.** Sektion 1-3a er kørt mod
> `pre-c0f-20260821-112005.dump` og stoppede i 3a med
> `REIMPORT_LEGACY_IN_FLIGHT_MIGRATION_BLOCKED` (dumpet er taget umiddelbart
> før C0-efterkørslen og har en in-flight legacy 1939-batch). Sektion 3b-6 er
> **ikke** afprøvet mod ægte data; deres kæde er alene bevist syntetisk i
> `tests/integration/test-reimport-source-evidence.R` og i #152's egen
> rehearsal. `work/task33-149a-rehearsal/REHEARSAL-RESULT.md` har tallene.

---

## 1. Adgangskrav og stopport

- Ingen prod-forbindelse. Alle fem variabler sættes **sammen** mod den
  disponerbare instans, fx:

  ```bash
  export PGHOST=127.0.0.1 PGPORT=55441 PGUSER="$(id -un)" PGPASSWORD='' \
         PGDATABASE=postgres
  ```

- Basenavn: `daa149a_<formål>_<dato>` (fx `daa149a_rehearsal_20260903`).
- `umask 077` for hele sessionen. Alle artefakter og backupfiler skal stå som
  mode 0600; backuppens SHA-256 noteres og gentages i rapporten.
- Stopport: hvis dumpets kontraktversion, dets legacy-ledgertilstand eller
  restore-fejlene afviger fra det forventede nedenfor, STOPPES rehearsal og
  fundet rapporteres. Ingen guard omgås for at komme videre.

```bash
set -euo pipefail
umask 077
DUMP_PATH="${DUMP_PATH:?sæt --dump/DUMP_PATH}"
shasum -a 256 "$DUMP_PATH"
stat -f '%Lp %N' "$DUMP_PATH"
ARTIFACT_DIR="work/task33-149a-rehearsal"
mkdir -p "$ARTIFACT_DIR"
git check-ignore -v "$ARTIFACT_DIR/x"   # skal ramme .gitignore:work/
```

### 1a. Forudsætningstjek på dumpet (afvigelse fra planens §2)

Et dump, hvis legacy 1939-ledger stadig er **in-flight**, kan ikke migreres:
`db-migrations.sql`'s #153-opgraderingsblok fail-closer med
`REIMPORT_LEGACY_IN_FLIGHT_MIGRATION_BLOCKED`, før nogen DDL udføres. Tjek
derfor efter restore (sektion 2), før migrationen køres:

```sql
SELECT
  (SELECT count(*) FROM private.reimport_1939_authorization WHERE status='issued')      AS issued_auth,
  (SELECT count(*) FROM private.reimport_1939_write_batch  WHERE status='open')         AS open_batch,
  (SELECT count(*) FROM private.reimport_1939_write_batch b
      JOIN private.reimport_1939_authorization a ON a.id=b.authorization_id
     WHERE a.operation='reimport' AND b.status='finalized')                             AS finalized_reimport;
```

Forventet `0|0|0`. Enhver anden værdi er en **stopport**: vælg et dump taget
efter at den pågældende legacy-batch er aktiveret eller reverseret i prod.
(Tabellerne findes kun i dumps ældre end #153; på et nyere dump returnerer
`to_regclass('private.reimport_1939_authorization')` NULL, og tjekket springes
over.)

---

## 2. Restore

Samme mønster som §2 i `docs/runbooks/narrative-record-key-cutover.md`.

```bash
set -euo pipefail
umask 077
PG=/opt/homebrew/opt/postgresql@17/bin
REHEARSAL_DATABASE="daa149a_rehearsal_$(date +%Y%m%d%H%M%S)"
$PG/createdb --host="$PGHOST" --port="$PGPORT" --username="$PGUSER" "$REHEARSAL_DATABASE"
PGDATABASE="$REHEARSAL_DATABASE" $PG/pg_restore \
  --clean --if-exists --no-owner \
  --dbname="$REHEARSAL_DATABASE" "$DUMP_PATH" 2>"$ARTIFACT_DIR/restore.err"
grep -c '^pg_restore: error' "$ARTIFACT_DIR/restore.err" || true
PGDATABASE="$REHEARSAL_DATABASE" $PG/psql -X -v ON_ERROR_STOP=1 -Atc \
  "SELECT current_database(), (pg_control_system()).system_identifier"
```

Brug **ikke** `--no-privileges`: uden de restorede GRANTs kan `SET LOCAL ROLE
anon`-kontrollen i sektion 6.3 ikke skelne »uændret« fra »ingen adgang«.
Rollerne `anon`, `authenticated` og `service_role` skal findes i clusteret på
forhånd (`\du`).

Et Supabase-dump restoret mod en Homebrew-instans giver forventeligt exit 1
med præcis de fejl, der stammer fra `supabase_vault` (udvidelsen findes ikke
lokalt, dens `COMMENT` og `vault.secrets`-COPY fejler dermed også). Enhver
anden fejl er en stopport. Notér antal og deres objekter — aldrig deres data.

Kør derefter sektion 1a's forudsætningstjek.

---

## 3. Bring skemaet frem og migrér til kontraktversion 2

**Afvigelse fra planens §3:** planen antager en base, der allerede har
#152-/#153-objekterne. Et dump, der er ældre end #152 (2026-08-29) og #153
(2026-09-01), har dem ikke: `public.narrative_record_contract_version()` og
`private.reimport_writer_profile` findes slet ikke. Derfor kommer der et trin
**før** cutover-kæden.

### 3a. Idempotent skemafremskrivning

```bash
PGDATABASE="$REHEARSAL_DATABASE" $PG/psql -X -v ON_ERROR_STOP=1 -f db-migrations.sql
PGDATABASE="$REHEARSAL_DATABASE" $PG/psql -X -v ON_ERROR_STOP=1 -f db-rls.sql
PGDATABASE="$REHEARSAL_DATABASE" $PG/psql -X -v ON_ERROR_STOP=1 -Atc \
  "SELECT public.narrative_record_contract_version(),
          to_regclass('private.reimport_writer_profile') IS NOT NULL"
```

Forventet `1|t` — kontraktversion 1 og den generiske writer-familie
installeret. Fortsæt kun herfra.

> **En fejlet `db-migrations.sql` efterlader ikke en ren base.** `psql -f` uden
> `-1` committer hver transaktionsblok undervejs, så en fejl midt i filen
> giver en delvist migreret base (nogle migrationer anvendt, resten ikke).
> Genforsøg aldrig oven på den: `dropdb` og restore forfra fra `$DUMP_PATH`.

### 3b. #152's cutover-kæde til kontraktversion 2

Brug den rigtige #152-vej — **ikke** `tests/sql/reimport-writer-v2-bootstrap.sql`,
som fail-closer med `CUTOVER_INVENTORY_LIVE_DRIFT` på en base med rigtige
narrativer (se `.github/workflows/ci.yml`, trinnet »Reimport writer migration
from pre-153 ledger«). Sekvensen er `docs/runbooks/narrative-record-key-cutover.md`
§3-§5, kørt som i `docs/evidensbaseret-genimport/narrative-record-key-152-rehearsal.md`:

```bash
EXPORT_DIR="$ARTIFACT_DIR/cutover-export"; REVIEW_DIR="$ARTIFACT_DIR/cutover-review"
RECEIPT_DIR="$ARTIFACT_DIR/cutover-receipt"; mkdir -p "$EXPORT_DIR" "$REVIEW_DIR" "$RECEIPT_DIR"
Rscript .claude/skills/daa-extract/scripts/export_narrative_record_cutover.R \
  --output-dir "$EXPORT_DIR"
/usr/bin/python3 .claude/skills/daa-extract/scripts/build_narrative_record_cutover_review.py \
  --record-candidates "$EXPORT_DIR/narrative-record-baseline-candidates-v1.json" \
  --legacy-candidates "$EXPORT_DIR/narrative-legacy-baseline-candidates-v1.json" \
  --inventory "$EXPORT_DIR/narrative-record-cutover-inventory-v1.json" \
  --output-dir "$REVIEW_DIR"
```

**Reviewarket i rehearsal.** §4 i #152's runbook forudsætter to navngivne
menneskelige reviewere og et signeret slutkontrolkort. I en rehearsal mod en
engangs-restore substitueres de af én navngiven **»lokal reviewer: rehearsal«**,
og beslutningsfilen `$REVIEW_DIR/narrative-record-cutover-decisions-v1.json`
udfyldes programmatisk: alle record-kandidater `godkend baseline`, alle
legacy-kandidater `bevar offentligt som grandfathered`. Konverteren accepterer
den tomme hide-mængde: den kræver kun `keep ∩ hide = ∅` og
`keep ∪ hide = kandidater` (`convert_narrative_record_cutover_approvals.py:124`)
— verificeret ved kodelæsning, ikke ved kørsel. Generatoren må **kun** røre id-felterne; hverken
review-HTML'en eller kandidat-JSON'erne må læses eller citeres — de indeholder
navne og narrativtekst. Dette er **rehearsal-only** og erstatter aldrig den
menneskelige gate ved en prod-cutover; det samme gælder §5's eksterne
writer-traffic-hold, som ikke findes i en engangs-restore.

```bash
/usr/bin/python3 .claude/skills/daa-extract/scripts/convert_narrative_record_cutover_approvals.py \
  --record-candidates "$EXPORT_DIR/narrative-record-baseline-candidates-v1.json" \
  --legacy-candidates "$EXPORT_DIR/narrative-legacy-baseline-candidates-v1.json" \
  --inventory "$EXPORT_DIR/narrative-record-cutover-inventory-v1.json" \
  --decisions "$REVIEW_DIR/narrative-record-cutover-decisions-v1.json" \
  --output-dir "$REVIEW_DIR"
shasum -a 256 "$EXPORT_DIR"/*.json "$REVIEW_DIR"/*.json "$REVIEW_DIR"/*.html
```

Derefter #152's gateway, først `preflight` (forventet `preflight_rolled_back`),
så `apply`, med de seks artefaktstier, nonce og forventet databaseidentitet fra
inventeringen — nøjagtigt som §5 i cutover-runbooken. Til sidst:

```bash
PGDATABASE="$REHEARSAL_DATABASE" $PG/psql -X -v ON_ERROR_STOP=1 -Atc \
  "SELECT public.narrative_record_contract_version()"     # skal være 2
```

---

## 4. Indsæt writer-profilen

Profilen er append-only (`schema.sql:2533`); en fejlagtig profil kræver et nyt
`profile_id`, ikke en rettelse. `profile_sha256` beregnes af databasen og
sammenholdes med profilindlæserens.

```bash
PROFILE=.claude/skills/daa-extract/references/reimport-profiles/daa-2018-20-source-evidence-v1.json
EXPECTED_PROFILE_SHA="$(/usr/bin/python3 .claude/skills/daa-extract/scripts/reimport_profile.py \
  --profile "$PROFILE" | /usr/bin/python3 -c 'import json,sys;print(json.load(sys.stdin)["profile_sha256"])')"
```

Én `INSERT`, hvor `writer_config` kommer ordret fra profil-JSON'en:

```sql
INSERT INTO private.reimport_writer_profile
  (source_id, profile_id, profile_version, profile_sha256, writer_config)
SELECT :source_id, :'profile_id', :'profile_version',
       private.reimport_canonical_json_sha256(:'writer_config'::jsonb),
       :'writer_config'::jsonb;

SELECT profile_sha256 FROM private.reimport_writer_profile
 WHERE source_id=:source_id AND profile_id=:'profile_id';
```

Assertér at den returnerede værdi er identisk med `$EXPECTED_PROFILE_SHA`.
(CHECK-constrainten `schema.sql:2389` forhindrer i forvejen enhver anden værdi.)

---

## 5. Byg, preview, autorisér, kør

Manifestet må genbruges, hvis det allerede er bygget og verificeret; så
assertér blot dets to hashes. Ellers bygges det forfra:

```bash
python3 .claude/skills/daa-extract/scripts/build_source_evidence_rendition.py \
  --profile "$PROFILE" --pdf "$PDF_PATH" --output-dir "$ARTIFACT_DIR/rendition"
python3 .claude/skills/daa-extract/scripts/build_source_evidence_manifest.py \
  --profile "$PROFILE" \
  --rendition-text "$ARTIFACT_DIR/rendition/rendition.txt" \
  --posts "$ARTIFACT_DIR/rendition/posts.json" \
  --output "$ARTIFACT_DIR/source-evidence-manifest-v1.json"
MANIFEST_BYTES_SHA="$(shasum -a 256 "$ARTIFACT_DIR/source-evidence-manifest-v1.json" | cut -d' ' -f1)"
```

Læse-kun før-billede (åbner `REPEATABLE READ READ ONLY` og ruller altid tilbage):

```bash
Rscript .claude/skills/daa-extract/scripts/export_reimport_preview.R \
  --profile "$PROFILE" \
  --manifest "$ARTIFACT_DIR/source-evidence-manifest-v1.json" \
  --manifest-sha256 "$MANIFEST_BYTES_SHA" \
  --output "$ARTIFACT_DIR/source-evidence-preview-v1.json"
PREVIEW_SHA="$(shasum -a 256 "$ARTIFACT_DIR/source-evidence-preview-v1.json" | cut -d' ' -f1)"
```

Før-billedet skal vise **0** renditions/records/occurrences/ankre for
`source_id`. Er det ikke 0, er baselinen forkert — stop og rapportér tallet.

Tørløb (selv-autoriserer i gatewayen og ruller tilbage):

```bash
Rscript .claude/skills/daa-extract/scripts/apply_reimport.R \
  --manifest "$ARTIFACT_DIR/source-evidence-manifest-v1.json" \
  --manifest-sha256 "$MANIFEST_BYTES_SHA" \
  --preview-sha256 "$PREVIEW_SHA" --dry-run
```

**Aktør og autorisation.** `public.red_authorize_reimport` er GRANTED alene til
`service_role` (`schema.sql:3179`), og alle writer-kald kræver desuden
`private.require_reimport_writer_editor()`: `auth.uid()` sat og
`public.current_rolle() = 'redaktion'`. `red_begin_reimport` kræver
`principal_id = auth.uid()` (`schema.sql:2710`), så **samme** aktør-UUID skal
udstede autorisationen og køre applyet.

```sql
-- aktøren oprettes én gang i rehearsal-basen
INSERT INTO auth.users(id,email) VALUES (:'actor','rehearsal@example.invalid')
  ON CONFLICT (id) DO NOTHING;
INSERT INTO public.profiles(id,email,rolle,navn)
  VALUES (:'actor','rehearsal@example.invalid','redaktion','lokal reviewer: rehearsal')
  ON CONFLICT (id) DO UPDATE SET rolle='redaktion';
```

Autorisationen udstedes i **én** psql-transaktion. `p_expected_counts` og
`p_authorized_elements` tages ordret fra preview-artefaktets
`authorization_request` (manifestets operationer minus `element_id` og
`dependency_class`). Fordi `p_authorized_elements` indeholder `verbatim_text`,
genereres psql-inputfilen af et script — aldrig med `cat`/`echo` i terminalen:

```sql
BEGIN;
SET LOCAL ROLE service_role;
SELECT set_config('request.jwt.claim.sub', :'actor', true);
SELECT public.red_authorize_reimport(
  :'manifest_content_sha256', :'preview_sha256',
  jsonb_build_object('database_name',current_database(),
                     'system_identifier',(pg_control_system()).system_identifier::text)::text,
  :source_id, :'profile_id', :'profile_sha256',
  :'expected_counts'::jsonb, :'authorized_elements'::jsonb,
  gen_random_uuid(), clock_timestamp() + interval '15 minutes');
COMMIT;
```

Gem det returnerede UUID som `$ARTIFACT_DIR/authorization-v1.json`
(`{"id":"<uuid>"}`), og kør applyet som samme aktør:

```bash
DAA_REIMPORT_ACTOR_ID="$ACTOR_UUID" \
Rscript .claude/skills/daa-extract/scripts/apply_reimport.R \
  --manifest "$ARTIFACT_DIR/source-evidence-manifest-v1.json" \
  --manifest-sha256 "$MANIFEST_BYTES_SHA" \
  --preview-sha256 "$PREVIEW_SHA" --apply \
  --authorization "$ARTIFACT_DIR/authorization-v1.json"
```

---

## 6. Verifikation

Alt nedenfor er tal og hashes; intet skrives ud i klartekst.

1. **Fire antal** for `source_id`: 1 rendition, N source records, N occurrences
   og N accepterede ankre, hvor N = manifestets `expected_counts.source_evidence`.

   ```sql
   SELECT
     (SELECT count(*) FROM private.source_rendition WHERE source_id=:source_id)          AS renditions,
     (SELECT count(*) FROM private.source_record    WHERE source_id=:source_id)          AS records,
     (SELECT count(*) FROM private.source_record_occurrence o
        JOIN private.source_rendition r ON r.id=o.rendition_id
       WHERE r.source_id=:source_id)                                                     AS occurrences,
     (SELECT count(*) FROM private.source_record_anchor_event a
        JOIN private.source_record sr ON sr.id=a.source_record_id
       WHERE sr.source_id=:source_id AND a.decision_status='accepted')                   AS anchors;
   ```

2. **Nul kanonisk delta.** Aggregat-hash før og efter skal være identisk for
   `public.person`, `public.fact`, `public.family_member`, `public.narrative`
   og `private.narrative_record_publication`:

   ```sql
   SELECT coalesce(encode(sha256(convert_to(
            string_agg(row_text, chr(10) ORDER BY row_text),'UTF8')),'hex'),'empty')
     FROM (SELECT t::text AS row_text FROM public.person t) s;
   ```

3. **Læserfladen uændret.** Samme aggregat-hash inde i en transaktion med
   `SET LOCAL ROLE anon` for `person`, `person_external_id`, `narrative`,
   `fact`, `assertion`, `conclusion`, `citation`, `family_member`, samt
   `public.public_person_bio_source_versions_v2` for de berørte `person_id`'er.

4. **Replay.** En ny autorisation med samme manifest/preview og et gentaget
   apply skal give `already_applied` og uændret aggregat-hash.

5. **Reversal fail-closer.** `red_authorize_reimport_reversal` lykkes på en
   `finalized` batch, men `red_reverse_reimport` skal afvise med
   `REIMPORT_WRITER_REVERSAL_INVALID` (batchen er ikke `activated` og har intet
   `name_completion`-barnebatch). Det er et fail-closed-bevis, ikke et
   gendannelsesbevis — jf. dokumenteret afvigelse 4 i planen.

6. **Gendannelse.** Drop rehearsal-basen, restore igen fra `$DUMP_PATH` og
   assertér 0 renditions, 0 records, 0 occurrences og 0 ankre for `source_id`.
   Evidenslaget har ingen sletningsvej; en øvet restore er gendannelsesbeviset.

Rapportér pr. trin: exit/status, alle hashes (backup, profil, manifest bytes +
indhold, preview, batch-id), de fire antal, aggregat-hash-lighed pr. tabel,
anon-lighed, replay-status, reversal-token og restore-beviset.
