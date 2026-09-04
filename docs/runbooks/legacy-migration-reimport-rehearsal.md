# Runbook — legacy-migration-rehearsal (149b, issue #166) mod en engangs-restore

Manuel procedure for at køre ét hash-låst `legacy_migration`-manifest gennem
den generelle genimport-writer (#153/149b) mod en **disponerbar** restore af
et prod-dump, som allerede har fået 149a's `source_evidence` anvendt. Proceduren
er editionsneutral: udgaven kommer fra profil-JSON'en. Ingen prod-forbindelse,
intet push, ingen merge. Prod-apply er en separat gate (§7).

Alle personhenvisninger i denne runbook er `record_key`, tal, id'er og hashes.
Rå narrativtekst og forekomsttekst ("`legacy-migration-texts-v1.json`") læses
**aldrig** — de bruges kun lokalt af normaliseringstrinnet i bygger-scriptet.
Artefakter under `work/` er gitignorerede og må aldrig citeres; enhver
`--output-dir` med en `work`-sti-komponent afvises af eksporten
(`OUTPUT_WORK_PATH`). Alle artefaktmapper er mode `0700`, alle filer deri
mode `0600` (`umask 077` i hver shell — hvert Bash-kald er en frisk shell,
så `umask` og `PGTZ=UTC` skal sættes i **hver** kommando).

> **Udførelsesstatus 2026-09-04.** Hele kæden (trin 1-3) er kørt ende-til-ende
> mod en restore af `pre-c0f-20260821-112005.dump` migreret til kontraktversion 2
> med 149a anvendt. Alle forventede tal og hashes ramt; ingen stopporte udløst.
> Kilde: intern rehearsal-rapport (rapportens id `149b-rehearsal-20260904`),
> gengivet i [`legacy-migration-149b-rehearsal.md`](../evidensbaseret-genimport/legacy-migration-149b-rehearsal.md).

---

## 1. Adgangskrav og stopport

- Ingen prod-forbindelse. Basen fra trin 1 (149a's henvisning nedenfor) er
  forudsætningen for dette dokuments trin 2-3 — ikke en frisk restore.
- Basenavn: `daa149b_<formål>_<dato>`.
- `umask 077` for hele sessionen; `PGTZ=UTC` for **alle** SQL-sessioner (også
  R- og psql-kald) — uden det ser et rent apply ud som drift i
  aggregat-hash-sammenligningerne (149a-fælde, gælder identisk her).
- Persondata: eksportens `--output-dir` skal ligge under en 0700-mappe uden
  `work`-sti-komponent (fx `$CLAUDE_JOB_DIR/tmp/…`); scriptet afviser stier med
  `work` (`OUTPUT_WORK_PATH`) og relative stier (`OUTPUT_DIR_NOT_ABSOLUTE`). Den
  rå tekstfil (`legacy-migration-texts-v1.json`, mode 0600) læses kun af
  bygger-scriptets normaliseringstrin — aldrig af et menneske eller en model.
- Stopport: enhver afvigelse fra de forventede tal/hashes i §5 er **stop**,
  ikke justering — manifestet er hash-låst, og en afvigelse betyder enten
  drift siden manifestet blev bygget eller en fejl i kæden.

---

## 2. Trin 1 — Restore + migrationer + cutover + 149a

Følg `docs/runbooks/source-evidence-reimport-rehearsal.md` §2-§6 **ordret** —
dette dokument kopierer ikke de trin. Basen efter trin 1 skal opfylde:

| Måling | Forventet |
|---|---|
| `narrative_record_contract_version()` | **2** (efter §3b-cutoveret) |
| Ledger `narrative_legacy_publication`, source 1, status `grandfathered_publication` | **544** (ingen andre statusser) |
| 149a-apply for source 1: rendition\|records\|occurrences\|accepterede ankre | **1\|591\|591\|591** |
| 149a-batch | `finalized`, `profile_id=daa-2018-20-source-evidence-v1` |

Notér alle hashes fra trin 1 i rapporten (§3 nedenfor): backup-SHA, profil-SHA,
manifest indhold/bytes, preview-SHA, batch-id, `database_identity`.
`PGTZ=UTC` i alle sessioner, også dem der udelukkende hører til trin 1.

**149a's fælder gælder uændret her** (gentaget fra
`source-evidence-reimport-rehearsal.md` §6, ikke omskrevet):
1. Aggregat-hashes er tidszoneafhængige — `PGTZ=UTC` overalt.
2. `red_reverse_reimport` er GRANTED `authenticated`, ikke `service_role`.
3. #152-kæden kræver kvitteringsfilnavnet `narrative-record-cutover-receipt-v1.json`
   og afviser stier med en `work`-komponent.
4. `apply_reimport.R` kræver `DAA_REIMPORT_ACTOR_ID` også i dry-run.

---

## 3. Trin 2 — 149b: eksport, byg, preview, dry-run, autorisation, apply

Alle kommandoer forudsætter `$REHEARSAL_DATABASE` fra trin 1, `$ACTOR_UUID`
(samme redaktionsaktør som trin 1 genbruger — **ikke** en ny), og
`$ART` = en 0700-artefaktmappe uden `work`-sti (fx
`$CLAUDE_JOB_DIR/tmp/<mappe>/`).

### 3.1 Eksport af kandidater (læse-kun)

```bash
umask 077
PGTZ=UTC Rscript .claude/skills/daa-extract/scripts/export_legacy_migration_candidates.R \
  --source-id 1 --output-dir "$ART/export"
```

Forventet stdout: `{"candidates": 591, "already_bound": 0}`. Skriver
`legacy-migration-candidates-v1.json` (uden tekst) og en separat 0600
`legacy-migration-texts-v1.json` (rå tekst — læses kun af bygger-scriptet,
aldrig af et menneske). Aggregér fordelingerne **programmatisk** fra
kandidatfilen, aldrig ved at åbne tekstfilen:

| Felt | Forventet fordeling |
|---|---|
| `persons_for_record_key` | 1 → 591 (ingen kollisioner) |
| `external_ids_for_person` | 1 → 591 |
| `narratives_for_person` | 1 → 591 |
| `already_bound` | `false` → 591 |
| `legacy_status` | `grandfathered_publication` → 544, `null` → 47 |
| `person_levende` | `false` → 544, `true` → 47 |

### 3.2 Manifest (Python, kun hashes)

Kør fra `.claude/skills/daa-extract/scripts/`-mappen (så `reimport_profile` og
`normalize_narrative_1939_v50` importeres), med **149a's rendition genbrugt**
som corpus (samme rå tekst, samme `raw_text_sha256`):

```bash
cd .claude/skills/daa-extract/scripts
umask 077
/usr/bin/python3 build_legacy_migration_manifest.py \
  --profile <legacy-profil> \
  --candidates "$ART/export/legacy-migration-candidates-v1.json" \
  --texts "$ART/export/legacy-migration-texts-v1.json" \
  --rendition-text "$ART/rendition/rendition.txt" \
  --output "$ART/legacy-migration-manifest-v1.json"
```

Assertér **før** autorisation:

| Måling | Forventet |
|---|---|
| `operations` (kun `bound_*`) | **587** |
| `dispositions` (alle 591) | 591 |
| `bound_published` | **541** |
| `bound_draft` | **46** |
| `unresolved_text` | **4** |
| `unresolved_identity` | **0** |
| `unresolved_text`-nøgler | præcis `I-133`, `II-35`, `III-129`, `IV-94` |
| `dependency_class` (alle 587) | `legacy_migration` |
| `expected_counts` (manifestet) | `{canonical_delta:0, legacy_migrations:587, person_creates:0, source_evidence:0}` |

**Stopregel:** enhver afvigelse fra disse tal, eller `unresolved_*`-nøgler der
ikke er nøjagtig disse fire, er stop — se §5.

### 3.3 Writer-profil (append-only, egen række)

```sql
-- indsæt IKKE i 149a's profilrække — legacy-migration har sin egen profile_id
INSERT INTO private.reimport_writer_profile
  (source_id, profile_id, profile_version, profile_sha256, writer_config)
SELECT 1, 'daa-2018-20-legacy-migration-v1', 'legacy-migration-v1',
       private.reimport_canonical_json_sha256(:'writer_config'::jsonb),
       :'writer_config'::jsonb;
```

`writer_config` hentes **frisk** fra legacy-profilens egen JSON-fil — **aldrig**
fra trin 1's `writer_config.json` (den er `source-evidence`-konfigurationen med
`extractor_version: source-evidence-v1`, `run_key_prefix:
reimport-source-evidence:`; genbrug giver forkert `profile_sha256`, se §6 fælde
4). `reimport_profile.py`'s CLI-output indeholder **ikke** `writer_config` (kun
`expected_counts`, `profile_id`, `profile_sha256`, `profile_version`,
`source_id`) — konfigurationen tages ordret fra profil-JSON-filen selv.

### 3.4 Preview (læse-kun, `REPEATABLE READ READ ONLY`, ruller altid tilbage)

```bash
PGTZ=UTC Rscript .claude/skills/daa-extract/scripts/export_reimport_preview.R \
  --profile <legacy-profil> \
  --manifest "$ART/legacy-migration-manifest-v1.json" \
  --manifest-sha256 "$MANIFEST_BYTES_SHA" \
  --output "$ART/legacy-migration-preview-v1.json"
```

Assertér:

| Felt | Forventet |
|---|---|
| `narrative_record_contract_version` | 2 |
| `expected_counts` (3 nøgler — helperen fjerner `canonical_delta`) | `{legacy_migrations:587, person_creates:0, source_evidence:0}` |
| `before_counts` (149a's evidenslag, uændret) | `source_rendition:1, source_record:591, source_record_occurrence:591, source_record_anchor_accepted:591` |
| `legacy_before_counts` | `grandfathered:544, migrated:0, withdrawn:0, bound_published:0, bound_draft:0, personas:0, identities:0, narratives:591` |
| `record_key_coverage` | manifest 587 / `person_external_id` 591 / kun-i-manifest 0 / kun-i-pei **4** (= de fire `unresolved_text`) |
| `canonical_baseline_sha256` (5 tabeller) | identisk med trin 1's efter-billede |
| `database_write_authorized` / `production_authorized` | `false` / `false` |

`preview_legacy_ledger_coverage` skal passere uden
`PREVIEW_LEGACY_LEDGER_INCONSISTENT` (alle 541 `bound_published` matcher en
`grandfathered_publication`-ledgerrække; ingen af de 46 `bound_draft` har en
ledgerrække). **Bemærk:** scriptets stdout-felt hedder `source_evidence` også
for et legacy-manifest — det er blot `length(manifest$operations)` (587), en
etiket-artefakt, ikke en `source_evidence`-operation (§6 fælde 5).

### 3.5 Dry-run

```bash
PGTZ=UTC DAA_REIMPORT_ACTOR_ID="$ACTOR_UUID" \
Rscript .claude/skills/daa-extract/scripts/apply_reimport.R \
  --manifest "$ART/legacy-migration-manifest-v1.json" \
  --manifest-sha256 "$MANIFEST_BYTES_SHA" \
  --preview-sha256 "$PREVIEW_SHA" --dry-run
```

Forventet: exit 0, `status="finalized"`, `committed=false`. Før/efter-billede
skal være **byte-identisk** (diff tom) — dry-run skriver intet.

### 3.6 Autorisation + apply

`p_expected_counts` og `p_authorized_elements` genereres **altid** af et
script til en 0600 SQL-fil — aldrig `echo`/`cat` i terminalen, fordi
`p_authorized_elements` (indirekte, via afledte felter) kan bære
tekstnære værdier. Samme mønster som 149a's `generate_authorize_sql.py`, ny
instans for legacy-elementerne.

```sql
BEGIN;
SET LOCAL ROLE service_role;
SELECT set_config('request.jwt.claim.sub', :'actor', true);
SELECT public.red_authorize_reimport(
  :'manifest_content_sha256', :'preview_sha256',
  jsonb_build_object('database_name',current_database(),
                     'system_identifier',(pg_control_system()).system_identifier::text)::text,
  1, 'daa-2018-20-legacy-migration-v1', :'profile_sha256',
  :'expected_counts'::jsonb,      -- {legacy_migrations:587, person_creates:0, source_evidence:0} — canonical_delta FJERNET
  :'authorized_elements'::jsonb,  -- JSONB-OBJEKT nøglet på element_id, IKKE et array
  gen_random_uuid(), clock_timestamp() + interval '15 minutes');
COMMIT;
```

```bash
PGTZ=UTC DAA_REIMPORT_ACTOR_ID="$ACTOR_UUID" \
Rscript .claude/skills/daa-extract/scripts/apply_reimport.R \
  --manifest "$ART/legacy-migration-manifest-v1.json" \
  --manifest-sha256 "$MANIFEST_BYTES_SHA" \
  --preview-sha256 "$PREVIEW_SHA" --apply \
  --authorization "$ART/authorization-lm-v1.json"
```

Forventet: exit 0, `status="finalized"`, `committed=true`, ny batch
(`profile_id=daa-2018-20-legacy-migration-v1`), status `finalized`.

---

## 4. Trin 3 — verifikation

Alt nedenfor er tal og hashes; intet skrives ud i klartekst. `PGTZ=UTC` i alle
forespørgsler.

### 4.1 Tal (source 1, før → efter)

| Måling | Før | Efter |
|---|---|---|
| `source_persona` | 0 | **587** |
| accepterede identiteter (`authority='person_external_id'`) | 0 | **587** |
| bindinger `published` | 0 | **541** |
| bindinger `draft` | 0 | **46** |
| ledger `migrated` | 0 | **541** |
| ledger `grandfathered_publication` | 544 | **3** |
| ledger `withdrawn` | 0 | **0** |
| `narrative_publication_event` `draft_created` | 0 | **587** |
| `narrative_publication_event` `published` | 0 | **541** |
| `narrative_publication_event` `legacy_migrated` | 0 | **541** |
| `narrative_publication_event` `baseline` | 544 | 544 (uændret) |
| `reimport_event` `legacy_migration` | 0 | **587** |
| batches for source 1 | 1 | **2** |

### 4.2 Hash-neutralitet

| Tabel | Før = efter? |
|---|---|
| `person`, `fact`, `family_member`, `narrative` (superuser, aggregat) | **JA** |
| `narrative`-kerne `(id,tekst,privat,side)` for alle 591 | **JA** |
| `narrative_record_publication` | NEJ (forventet — nye bindinger skrevet) |
| `narrative_legacy_publication` | NEJ (forventet — status ændret 544→3) |
| `anon`: `assertion`, `citation`, `conclusion`, `fact`, `family_member`, `narrative`, `person`, `person_external_id` (8 tabeller) | **JA for alle 8** |

Kun `narrative_record_publication` og `narrative_legacy_publication` (begge
`private`) må ændre sig. Enhver anden ændring er stop.

### 4.3 Offentlig flade (v1 + v2)

| Funktion | Før | Efter |
|---|---|---|
| `public_person_bio_source_versions_v2` — `legacy_narrative`, source 1 | 544 | **3** |
| `public_person_bio_source_versions_v2` — `source_record`, source 1 | 0 | **541** |
| `public_person_bio_source_versions` (v1-navn), samme felter | samme mønster | samme mønster |
| v2/v1-rækker for de 47 levende blandt de 591 | 0 | **0** (uændret — draft-bindinger forbliver skjult) |

Hver bundet biografi vises **præcis én gang** — aldrig som både
`source_record` og `legacy_narrative`.

### 4.4 Per-nøgle-kontrol af de fire `unresolved_text`

| `record_key` | `levende` | ledger efter | offentlig flade |
|---|---|---|---|
| `I-133`, `II-35`, `III-129` | false | `grandfathered_publication` (uændret) | `legacy_narrative` (uændret) |
| `IV-94` | **true** | ingen ledgerrække (som før) | ingen rækker (som før) |

De tre ikke-levende `unresolved_text` forbliver `grandfathered_publication` —
det er den korrekte, ikke-migrerede tilstand, ikke et fund.

### 4.5 Redaktørflade

`red_person_narrative_records` (rolle `authenticated` +
`request.jwt.claim.sub`): et migreret narrativ har præcis én række
(`provenance_kind='source_record'`, `publication_status='published'` eller
`'draft'`, `eligibility_status='eligible'`, autoritet
`existing_exact_binding`), **ingen** `grandfathered_legacy`-række. Over alle
591: `source_record/published`=541, `source_record/draft`=46,
`grandfathered_legacy/published`=3, `IV-94` giver ingen rækker (590 rækker i
alt).

### 4.6 Replay

Ny autorisation, samme manifest/preview, gentaget apply:
`status="already_applied"`, `committed=true`, ingen ny batch, alle tal og
hashes uændrede.

### 4.7 Reversal

**Ét narrativ** (`I-1` eller det første publicerede i manifestet), kørt i en
transaktion der **rulles tilbage** (så batchen forbliver intakt til
batch-dry-run):

| Trin | Kald | Forventet |
|---|---|---|
| (a) | `red_fortryd_person_narrative_publication_event(legacy_migrated)` mens bindingen er aktiv | afvist `NARRATIVE_LEGACY_MIGRATION_BINDING_ACTIVE` |
| (b) | `red_fortryd_person_narrative_publication_event(published)` | binding → `draft` |
| (c) | `red_kasser_person_narrative_record(...)` | binding → `withdrawn` |
| (d) | `red_fortryd_person_narrative_publication_event(legacy_migrated)` | ledger → `grandfathered_publication` igen |
| gate | `person_daa_narrative_publication_allowed` | `true` igen |
| flade | v2/v1 for personen | 1 × `legacy_narrative`, 0 × `source_record` |

`ROLLBACK` efter (d). Kør som superuser med `request.jwt.claim.sub` sat —
`private.narrative_legacy_state`/`narrative_record_state` er revoked for
`authenticated`. Nulstil `app.change_set_id` mellem **hvert** redaktionelt
RPC-kald i kæden (samme mønster som SQL-testen) — den efterlades ikke tom
automatisk.

**Batch-status og replay efter en fuld batch-fortrydelse (gælder `--apply`, ikke
dry-run):** batchen forbliver `finalized`. Den autoritative markør for »fortrudt«
er reversal-hændelsen, ikke batch-status:

```sql
SELECT count(*) FROM private.reimport_event
 WHERE batch_id = :batch AND operation = 'reversal';   -- >0 = batchen er fortrudt
-- element_id er 'legacy-migration-reversal:<authorization_id>'
```

Konsekvens, som operatøren SKAL kende: kører man samme manifest igen efter en
fortrydelse, svarer `apply_reimport.R` fortsat `already_applied`, fordi
`red_begin_reimport`'s replay-opslag filtrerer på `status='finalized'` og finder
den fortrudte batch. **`already_applied` betyder derfor ikke »data er stadig
anvendt«.** Tjek altid reversal-markøren ovenfor, før konklusionen drages. (At
statussen ikke ændres er bevidst: `reversed` er reserveret til
`red_reverse_reimport`, og en statusændring ville lade manifestet åbne en ny
batch, der først dør på `LEGACY_MIGRATION_ALREADY_BOUND`.)

**Batch-reversal — kun dry-run i rehearsal:**

```bash
PGTZ=UTC DAA_REIMPORT_ACTOR_ID="$ACTOR_UUID" \
Rscript .claude/skills/daa-extract/scripts/reverse_reimport_legacy_migration.R \
  --batch-id "$BATCH_ID" --authorization "$REVERSAL_AUTH_ID" --dry-run
```

Reversal-autorisation udstedes som `service_role` via
`public.red_authorize_reimport_reversal`. Forventet dry-run-resultat: `mode:
dry-run`, `reversed_elements: 587`, alle `element_ids` med præfiks
`legacy-migration:`, `committed: false`. Efter dry-run: autorisationen stadig
`issued`, ingen `reversal`-events, tal/hashes uændrede. **`--apply` køres ikke
i rehearsal** — basen skal persistere med batchen anvendt til videre arbejde;
den fulde apply-vej er bevist i `tests/integration/test-reimport-legacy-migration.R`.

`red_reverse_reimport` kaldt som `authenticated`-aktøren på samme
batch/autorisation afvises med `REIMPORT_WRITER_REVERSAL_INVALID` (batchen er
`finalized`, ikke `activated`, og har intet `name_completion`-barn) —
fail-closed-bevis, ikke gendannelsesbevis.

---

## 5. Stopregler

- **De eksakte forventede tal er 541 `bound_published` / 46 `bound_draft` / 4
  `unresolved_text` / 0 `unresolved_identity`.** Enhver afvigelse fra disse
  fire tal er stop, ikke justering.
- **De fire `unresolved_text`-nøgler skal være præcis** `I-133`, `II-35`,
  `III-129`, `IV-94`. En anden mængde (selv af samme størrelse) er stop.
- **Stopgrænsen** (spec §4): `unresolved_*` > 10 % af 591 (≥ 60) stopper fasen
  før prod. Forventet 4/591 = 0,7 %, langt under grænsen.
- **Inkonsistens er stop, ikke disposition:** et narrativ der er publicerbart
  men mangler i ledgeren, eller er i ledgeren som `withdrawn`/`migrated`, gør
  hele manifestet ugyldigt (`LEGACY_MIGRATION_LEDGER_INCONSISTENT`). Det
  betyder drift siden manifestet blev bygget og kræver menneskelig afgørelse —
  aldrig en automatisk retry.
- Enhver afvigelse i `expected_counts`, `manifest_content_sha256`,
  `manifest_bytes_sha256`, `profile_sha256` eller `preview_sha256` fra de
  hash-låste værdier i rapporten er stop.

---

## 6. Fælder (begge trin)

### Trin 1 (149a, gentaget her for samlet overblik — se `source-evidence-reimport-rehearsal.md` for detaljer)

1. `build_source_evidence_rendition.py --output-dir` kræver at mappen **ikke**
   findes på forhånd — et forudgående `mkdir -p` fejler med
   `SOURCE_EVIDENCE_OUTPUT_EXISTS`. Lad scriptet selv oprette mappen.
2. `p_expected_counts` accepterer **aldrig** `canonical_delta` — kun
   `person_creates`, `source_evidence`, `legacy_migrations` (2-3 af dem).
   Nøglen fjernes altid før autorisation, strukturelt, ikke betinget.
3. `p_authorized_elements` er et **JSONB-objekt** nøglet på `element_id` (fx
   `source-evidence:I-1` / `legacy-migration:I-1`), **ikke** et array.
4. `red_authorize_reimport`-inputtet indeholder tekstnære felter — genereres
   altid til en mode-0600 SQL-fil af et script, aldrig via terminal-`echo`/`cat`.
5. `red_reverse_reimport` er GRANTED til `authenticated`, **ikke**
   `service_role` — reversal-afvisningen kaldes som redaktionsaktøren.

### Trin 2-3 (149b, nye fælder fundet 2026-09-04)

6. **Occurrence-join går via `rendition_id`.**
   `private.source_record_occurrence` har ingen `source_record_id`-kolonne;
   joinet til `source_id` går `source_record_occurrence.rendition_id →
   private.source_rendition.source_id` (som runbook §6.1 allerede viser for
   149a — glem det ikke, når man skriver en ny forespørgsel til 149b).
7. **`private.reimport_batch` har ingen `operation`-kolonne.** Batches for en
   kørsel findes på `source_id` + `profile_id`, ikke på operation.
8. **`reimport_profile.py`'s CLI-output indeholder ikke `writer_config`** —
   kun `expected_counts`, `profile_id`, `profile_sha256`, `profile_version`,
   `source_id`. `writer_config` skal altid tages ordret fra profil-JSON-filen.
9. **Genbrug aldrig 149a's `writer_config.json`** til legacy-profilen — det er
   source-evidence-konfigurationen (`extractor_version: source-evidence-v1`)
   og giver et forkert `profile_sha256` for legacy-profilen.
10. **Previewets stdout-etiket `source_evidence`** rummer for et
    legacy-manifest blot `length(manifest$operations)` (587) — ikke en
    `source_evidence`-operation. Letforvekslelig, ikke en fejl.
11. **Private state-funktioner er revoked for `authenticated`.**
    `private.narrative_legacy_state`/`narrative_record_state` kræver
    superuser + `request.jwt.claim.sub` sat — enkelt-narrativ-reversalens
    `state_sha256` hentes derfor som superuser, ikke som redaktionsaktøren.
12. **`app.change_set_id` nulstilles ikke automatisk mellem RPC-kald** i
    reversal-kæden — sæt `set_config('app.change_set_id','',true)` mellem
    **hvert** redaktionelt kald (samme mønster som SQL-testen).
13. **`PGTZ=UTC` i hver eneste shell** — hvert Bash-kald er en frisk shell;
    `umask 077` sammen med den.

---

## 7. Prod

Prod-apply er en separat gate og kræver alt følgende — ingen af disse punkter
kan erstattes af rehearsal-beviset alene.

**Prod-rækkefølge (uændret siden 149a):**

1. **#152-cutover** (kontraktversion 1 → 2) med frisk production-inventory og
   det eksterne writer-traffic hold fra
   [`narrative-record-key-cutover.md`](narrative-record-key-cutover.md).
2. **#153 med guard-rettelsen** (`REIMPORT_LEGACY_IN_FLIGHT_MIGRATION_BLOCKED`-
   undtagelsen for `finalized` batches uden personoprettelser) — SKAL indgå i
   #153's prod-migration; prod har den samme 1939 fase A-batch som blokerede
   rehearsal-forsøget uden rettelsen.
3. **149a** (source_evidence for source 1) anvendt og verificeret i prod.
4. **149b** (denne runbook) — kan først køres, når 1-3 er verificeret i prod,
   ikke kun i rehearsal.

**Fase-pakke-gaten** (spec §7): 0600-backup med SHA-256, restore-rehearsal,
hash-låst manifest, projektejer-GO, ét apply, replay `already_applied`,
reversal bevist (mindst per-narrativ + batch-dry-run, som i §4.7). Writer-
traffic skal holdes eksternt under prod-apply, fordi 541 offentlige
publiceringer skifter form i samme transaktion-serie.

**Valg A/B kræver kvittering.** Spec §5 (valg A: identitet uden
placement-kæde) og spec §8 (valg B: reversal-designet) er PM-rollens egne
valg og kræver projektejerens eksplicitte kvittering, **før** prod-GO gives —
ikke kun før implementering. Se `docs/decisions.md`, 149b-posten.

**Neutralitetstællingen skal måles i prod før 149b-apply, ikke antages:**

```sql
SELECT count(*) FROM private.narrative_record_publication b
  JOIN private.narrative_legacy_publication l ON l.narrative_id = b.narrative_id
 WHERE b.status = 'withdrawn' AND l.status = 'grandfathered_publication';
-- forventet 0 — se §6 fund fra 149b's læsefunktionsrettelse (spec §8)
```

En værdi forskellig fra 0 betyder, at et allerede fortrudt/omkonstrueret
narrativ i prod ville kollidere med 149b's antagelse om at kombinationen
"withdrawn binding ∧ grandfathered ledger" først opstår med 149b selv — stop
og eskalér, kør ikke apply.
