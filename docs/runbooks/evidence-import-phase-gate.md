# Evidensimport: fase-pakke-gate

Denne runbook er den gældende gate for en enkelt evidensfase. Den erstatter
ikke den manglende, uafhængige gammel↔ny-sammenligning: dens formål er at gøre
den konkrete fasetilstand og en afgrænset fem-projektionsafstemning bevisbar.

## Grænse og autorisation

Fase-pakken er:

1. backup med mode `0600` og noteret SHA-256;
2. restore-rehearsal mod den konkrete backup med byte-identiske baselines;
3. hash-låst manifest og menneskelig GO med de eksakte hasher;
4. ét apply; og
5. en efterfølgende læse-kun afstemning af den erklærede, ordnede række af
   fasebidrag mod dens fem dækkede sluttilstandsprojektioner.

Backup, rehearsal, prod-læsning og apply er fire forskellige autorisationer.
Denne runbook autoriserer ingen af dem. `reconcile_evidence_phase_gate.py`
åbner aldrig en database og skriver aldrig til den.

## Fasebidrag

For hver mekanisk bundet fase opretter artefaktauditten ét lille
reconciliation-bidrag i sin private outputmappe. Felterne
`source_manifest_path` og `source_manifest_sha256` binder bidraget til den
tilsvarende `manifest`-artefakt, som allerede er forseglet i
`reconciliation-ledger.json`. Stien er bundle-relativ i ledgeret — den må
aldrig fortolkes relativt til audit-outputmappen. Reconcilerens admission
kontrollerer den eksakte sti/hash-binding mod ledgeret, men genåbner eller
kopierer ikke det originale manifest. Bidraget bruger præcis dette format før
forsegling:

```json
{
  "schema_version": "daa-evidence-phase-reconciliation-manifest-v1",
  "phase_id": "1939-phase-a",
  "source_manifest_path": "phase-a-manifest.json",
  "source_manifest_sha256": "<64 lower-case hex>",
  "source_records": [{"source_id": 3, "record_key": "1939:001"}],
  "source_anchors": [{"source_id": 3, "record_key": "1939:001", "occurrence_key": "1939:001:r6"}],
  "narrative_bindings": [{"source_id": 3, "record_key": "1939:001", "narrative_id": 101}],
  "narrative_sha256": [{"narrative_id": 101, "sha256": "<64 lower-case hex>"}],
  "persons": [{"person_id": 42}],
  "withdrawals": {
    "source_records": [],
    "source_anchors": [],
    "narrative_bindings": [],
    "narrative_sha256": [],
    "persons": []
  }
}
```

Alle fem lister er rækker i den dækkede sluttilstand, ikke tællefelter. En
duplikat i ét bidrag er en blokerende fejl. Mellem faser afgør ledgerets
`sequence` den sidste kendte værdi for samme `narrative_id` eller
`(source_id, record_key)`; identiske, append-only rækker bevares kun én gang.
Det gør fx Task 25 og fase B, der begge berører en narrativ, afstemmelige mod
den endelige værdi. `withdrawals` indeholder kun identiteten fra den forrige
sluttilstand og skal eksplicit fjerne fx en erstattet binding eller udgået
narrativ-hash, før fasens nye rækker lægges på. Dette er et format-eksempel:
operatøren må ikke manuelt forsegle eller konstruere et bidrag med
`reconcile_evidence_phase_gate.py --seal`. Audit-CLI'en forsegler det
auditerede bidrag og dets `reconciliation_content_sha256`. En ændret
originalmanifest kræver en ny audit, ny hash, ny rehearsal og en ny GO;
redigér aldrig en allerede anvendt pakke. Audit-output, bidrag, snapshot og
anden person-/kildeidentificerende data forbliver private og må ikke committes.

Det private `reconciliation-ledger.json` er et obligatorisk, hash-låst
faseledger for den erklærede afstemning. Det låser det præcise input-sæt,
manifestbindingerne og den semantiske rækkefølge; et manglende eller ekstra
CLI-bidrag er teknisk NO-GO. Det kan ikke i sig selv bevise, at inventaret er
historisk komplet, eller at et bidrags fem lister er udledt korrekt fra
originalmanifestet:

Den offentlige reconciler accepterer ikke et brugerudvalgt ledger som denne
generelle skitse. Den validerer den faste historiske rækkefølge Task 25, fase
A, fase B, narrativ-publicering, name-completion, C0, D1 og til sidst C3. C3
skal med, fordi kørslen den 2026-08-29 ændrede source 3-bindinger og
narrativ-hashes efter de øvrige faser. C0-kørslen med `change_set 965` dækkes
af `work/task30-1939-v50-c0-efterkoersel/prod-manifest.json`; den er derfor
ikke en skjult ekstra fase bag `6-c0`.

De historiske apply-filer har ikke de senere
`daa-evidence-phase-receipt-*-v1`-skemaer eller et `schema_version`-felt. De må
derfor kun registreres som hash-låste `apply_record`-artefakter. De kan ikke
promoveres til `mechanically_bound`, og de historiske ledgerfaser hedder
ærligt `afterdocumented_unbound`. Fase B bindes til
`narrative-replacement-manifest-v1.json`, som var det anvendte manifest, ikke
den senere v2. D1 er fortsat `unavailable`. Dermed stopper den offentlige
afstemning som `EVIDENCE_RECONCILIATION_INCOMPLETE`; ingen receipt eller noget
fasebidrag må konstrueres for at omgå dette resultat.

```json
{
  "schema_version": "daa-evidence-phase-artifact-ledger-v2",
  "phases": [{
    "phase_id": "1939-phase-a",
    "sequence": 1,
    "artifacts": [{
      "role": "manifest",
      "path": "phase-a-manifest.json",
      "sha256": "<64 lower-case hex>",
      "schema_version": "1939-v50-phase-a-anchor-manifest-v1",
      "required": true
    }],
    "adapter_id": "<reviewed adapter id>",
    "adapter_sha256": "<64 lower-case hex>",
    "projection_evidence": "mechanically_bound",
    "authorisation_evidence": "contemporaneous_phase_package",
    "contribution_sha256": "<64 lower-case hex>"
  }]
}
```

Et ledger med blot én fase uden `mechanically_bound` `projection_evidence` og
`contribution_sha256` returnerer `EVIDENCE_RECONCILIATION_INCOMPLETE` før
produktionssnapshotet læses eller sammenlignes. Auditoren forsegler ledgeret;
det og alle bidrag forbliver i den private bundle-outputmappe.

## Privat artefaktaudit før prod-snapshot

Før en mulig afstemning skal operatøren selv forfatte det private katalog over
de faktisk beholdte artefakter. Der findes ingen samlet retained bundle på
`/private/retained/1939-v50-evidence-bundle`; den tidligere sti var opdigtet.
De faktiske placeringer er:

- `work/task25-1939-v50-production-writer/` for Task 25, fase A, fase B,
  narrativ-publicering og name-completion;
- `work/task30-1939-v50-c0-efterkoersel/` for C0; og
- `work/task27-1939-v50-c3-apply/` for C3.

Stierne er relative til den oprindelige `evidensbaseret-genimport`-worktree.
C3's beholdte produktionsslutbevis er desuden efterdokumenteret i
`docs/evidensbaseret-genimport/c3-production-apply-2026-08-29.md`. Katalog og
audit-output skal ligge under en ignoreret `.private/`-mappe og må aldrig
committes. Kataloget har schema
`daa-evidence-phase-artifact-catalog-v1` og indeholder alene fase-ID,
positiv unik sekvens, adapter-ID, evidenstilstande, eventuel
database-target-identity-hash og artefaktmetadata (`role`, relativ `path`,
`schema_version`, `required`) — aldrig artefakt-SHA'er, projektionsidentiteter
eller private rækker. `schema_version` er `null` for de uversionerede
apply-records; det er ikke et nyt eller tilbageprojekteret receipt-skema.

Med bundle-specifikke, private stier er den eksakte kørsel:

```bash
/usr/bin/python3 .claude/skills/daa-extract/scripts/run_evidence_phase_artifact_audit_1939_v50.py \
  --bundle-root <repository-root> \
  --catalog <repository-root>/.private/issue-156/artifact-catalog.json \
  --private-output-dir <repository-root>/.private/issue-156/artifact-audit
```

CLI'en afviser symlinks, path-escapes, manglende eller ikke-tomme
outputmapper og eksisterende mål før den overskriver noget. Den hasher de
præcise artefaktbytes og den registrerede projectorkilde, forsegler
`audit-ledger.json`, skriver `audit-summary.json` og skriver kun
fasebidrag for mekanisk bundne faser. Alle private outputfiler oprettes
eksklusivt med mode `0600`.

Historiske huller er fortsat `INCOMPLETE`: de syv efterdokumenterede faser og
D1 giver exitkode `2`, `reconciliation-ledger.json` udelades, og auditten må
ikke opfinde en kvittering, promovere en fase eller skrive et bidrag.
Terminalen er bevidst
begrænset til status, stabile fejltokens, fase-/evidenstilstande, hasher og
optællinger; de eksakte private rækker bliver i bundle-outputtet.

En komplet audit er alene en artifact-admission. Stop her, indtil en separat
autorisation udtrykkeligt tillader det nedenstående read-only
produktionssnapshot; denne kommando åbner ingen database og giver ingen
autorisation til snapshot, apply eller anden produktionshandling.

### Auditor-output, der kan gives direkte til reconciler

Den historiske audit producerer kun `audit-ledger.json` og
`audit-summary.json`. Den producerer ingen contribution-filer og intet
`reconciliation-ledger.json`, fordi de beholdte apply-records er
`afterdocumented_unbound`. `audit-ledger.json` kan gives til reconcilerens
admission for at få det eksplicitte `EVIDENCE_RECONCILIATION_INCOMPLETE`-
resultat; den kan ikke bruges til en datamæssig match-afstemning.

### Syntetisk fail-closed bevis

Den automatiske historiske test bruger kun syntetiske, ikke-identificerende
artefakter med den samme kontrakt som de beholdte filer: uversionerede
apply-records, C0's kombinerede prod-manifest, D1 som `unavailable` og C3 som
sidste fase. Resultatet skal være exitkode `2`, otte ufuldstændige faser,
ingen contributions, intet `reconciliation-ledger.json` og ingen læsning af
noget snapshot.

En separat fixture med navnet `synthetic_capability_only` afprøver kun, at de
seks understøttede adaptere kan forsegle bidrag og et reconciliation-ledger
med helt syntetiske receipts. Den udelader D1 og er ikke historisk evidens,
historisk autorisation eller en GO for snapshot eller apply. Testen muterer
derefter et artefakt efter forseglingen og kræver hash-afvisning før
projektion. Reconcilerens admission afviser fortsat både `afterdocumented_unbound`
og `unavailable` faser, før den validerer et snapshot.

## Læse-kun prod-snapshot

Efter eksplicit autorisation til prod-læsning tages ét snapshot i en `READ
ONLY`-transaktion. Fang kun den kilde og de statusser, som de anmeldte
fasebidrag dækker. For en færdig 1939-kæde med published bindinger er den
minimale struktur. Preflight afbryder, hvis `extensions.digest` ikke findes;
den kvalificerede funktion er nødvendig, fordi prod ikke må afhænge af
sessionens `search_path`:

```sql
BEGIN TRANSACTION READ ONLY ISOLATION LEVEL REPEATABLE READ;

DO $$
BEGIN
  IF to_regprocedure('extensions.digest(bytea,text)') IS NULL THEN
    RAISE EXCEPTION 'EVIDENCE_RECONCILIATION_PGCRYPTO_MISSING';
  END IF;
END
$$;

WITH database_target AS (
  SELECT current_database() AS database_name,
         (pg_control_system()).system_identifier::text AS system_identifier
), source_records AS (
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'source_id', source_id, 'record_key', record_key
  ) ORDER BY record_key), '[]'::jsonb) AS rows
  FROM private.source_record WHERE source_id = 3
), source_anchors AS (
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'source_id', r.source_id, 'record_key', r.record_key,
    'occurrence_key', o.occurrence_key
  ) ORDER BY r.record_key, o.occurrence_key), '[]'::jsonb) AS rows
  FROM private.source_record_anchor_current a
  JOIN private.source_record r ON r.id = a.source_record_id
  JOIN private.source_record_occurrence o ON o.id = a.occurrence_id
  WHERE r.source_id = 3 AND a.decision_status = 'accepted'
), bindings AS (
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'source_id', r.source_id, 'record_key', r.record_key,
    'narrative_id', p.narrative_id
  ) ORDER BY r.record_key, p.narrative_id), '[]'::jsonb) AS rows
  FROM private.narrative_record_publication p
  JOIN private.source_record r ON r.id = p.source_record_id
  WHERE r.source_id = 3 AND p.status = 'published'
), narrative_sha256 AS (
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'narrative_id', n.id,
    'sha256', encode(extensions.digest(convert_to(n.tekst, 'UTF8'), 'sha256'), 'hex')
  ) ORDER BY n.id), '[]'::jsonb) AS rows
  FROM public.narrative n
  JOIN private.narrative_record_publication p ON p.narrative_id = n.id
  JOIN private.source_record r ON r.id = p.source_record_id
  WHERE r.source_id = 3 AND p.status = 'published'
), persons AS (
  SELECT coalesce(jsonb_agg(jsonb_build_object('person_id', person_id) ORDER BY person_id), '[]'::jsonb) AS rows
  FROM (
    SELECT DISTINCT n.subjekt_id AS person_id
    FROM public.narrative n
    JOIN private.narrative_record_publication p ON p.narrative_id = n.id
    JOIN private.source_record r ON r.id = p.source_record_id
    WHERE r.source_id = 3 AND p.status = 'published' AND n.subjekt_type = 'person'
  ) q
)
SELECT jsonb_pretty(jsonb_build_object(
  'schema_version', 'daa-evidence-production-snapshot-v1',
  'database_target_identity', jsonb_build_object(
    'schema_version', 'daa-evidence-production-target-identity-v1',
    'environment', 'production',
    'database_name', database_target.database_name,
    'system_identifier_sha256',
    encode(extensions.digest(convert_to(database_target.system_identifier, 'UTF8'), 'sha256'), 'hex')
  ),
  'source_records', source_records.rows,
  'source_anchors', source_anchors.rows,
  'narrative_bindings', bindings.rows,
  'narrative_sha256', narrative_sha256.rows,
  'persons', persons.rows
))
FROM database_target, source_records, source_anchors, bindings, narrative_sha256, persons;

COMMIT;
```

Gem den returnerede JSON som et lokalt, uforseglet snapshot. `current_database()`
og `pg_control_system().system_identifier` fastlægger capture-databasen;
`database_name` og system-identifikatoren forsegles begge, så to databaser i
samme PostgreSQL-klynge ikke kan forveksles. Det er
den UTF-8-tekstuelle `system_identifier`, der hashes i præcis samme form som i
receipt-kontrakten. Snapshotets `database_target_identity` skal derfor have
samme kanoniske hash som den ene fælles target-hash i alle admitted ledgerfaser;
en anden target-identitet er NO-GO. Forsegl den og
kør derefter admission med det eksakte audit-ledger. Der er ingen
`--phase-manifest`-argumenter, fordi auditten ikke producerede bidrag:

```bash
/usr/bin/python3 .claude/skills/daa-extract/scripts/reconcile_evidence_phase_gate.py \
  --seal prod-source-3.unsealed.json \
  --sealed-output .private/prod-source-3.snapshot.json

/usr/bin/python3 .claude/skills/daa-extract/scripts/reconcile_evidence_phase_gate.py \
  --snapshot .private/prod-source-3.snapshot.json \
  --ledger .private/issue-156/artifact-audit/audit-ledger.json \
  --private-report .private/issue-156/reconcile-report.json
```

Admission returnerer `EVIDENCE_RECONCILIATION_INCOMPLETE` med faser,
optællinger og ledger-hash uden at læse eller sammenligne snapshotrækkerne.
Det er det korrekte slutresultat, når ingen historisk fase er mekanisk bundet;
snapshotet bevares alene som det ene autoriserede, forseglede billede af
source 3 på kørselstidspunktet.

`--sealed-output` skal pege på en ny, ignoreret privat fil. CLI'en opretter
snapshotet eksklusivt med mode `0600`; brug ikke shell-redirection. Terminalen
viser kun en redigeret seal-kvittering med status og content-hash, aldrig
snapshotrækker eller identiteter.

`--private-report` skal pege på en ignoreret, ny fil. CLI'en opretter den med
`O_EXCL` og mode `0600` og overskriver aldrig en eksisterende rapport. Kun
den private rapport indeholder de eksakte drift-rækker; terminalen indeholder
kun status, stabil fejltoken, fase-ID'er, sektionsoptællinger og
artefakthashes.

Snapshot-forespørgslen dækker hele den anmeldte source/status-afgrænsning. Den
må derfor ikke køres som en isoleret kontrol af én ny fase på en allerede
befolket source: ledgeret skal omfatte alle tidligere anvendte bidrag i samme
afgrænsning. Et manglende eller ekstra CLI-bidrag er
`EVIDENCE_RECONCILIATION_LEDGER_MISMATCH`; en ubundet ledgerfase er
`EVIDENCE_RECONCILIATION_INCOMPLETE` før produktionssnapshot-sammenligning.
Man må ikke indsnævre prod-snapshot eller opfinde et bidrag for at få `match`.

Kun et terminalresultat med `status: "match"` og en privat rapport med
`scope: "five-projection-final-state-v1"` er en bestået, afgrænset
afstemning.
`EVIDENCE_RECONCILIATION_DRIFT`, dubletter, manglende lister eller en forkert
SHA er NO-GO: bevar inputs, gennemgå det eksakte difference-sæt kun i den
private rapport, og stop. Aldrig reparér prod for at få en optælling til at
passe.

## Klausul-projektion (udgaveneutral delta-afstemning, spec §11.1)

Gælder `clause_evidence`-kørsler (4.1c). Den afstemmer **én kørsels delta**, ikke
historien: den kender ingen udgave eller fase og afhænger ikke af
`reconcile_evidence_phase_gate.py`, som er låst til 1939/source 3 og ikke er i `main`.
Værktøjet er i `main` (#195): `clause_evidence_projection.psql` med tre SQL-filer og
`compare_clause_evidence_projection.py`.

**Hvad et `match` beviser** (mod den godkendte måldatabase):

1. De fem kildeprojektioner (records, accepterede ankre, narrativbindinger i alle
   statusser, narrativ-hashes, personer) er identiske før og efter.
2. Hele rækker er uændrede i `person`, `fact`, `assertion`, `conclusion`, `narrative`,
   `relation`, `family_member`, `citation`, `person_external_id`, `source_mention`,
   `source_record`, `source_record_occurrence`, `source_record_anchor_event`,
   `narrative_record_publication`, alle ikke-klausul-observationer og andre kilders
   klausuler og dispositioner.
3. Det, rollen `anon` ser gennem RLS i `assertion`, `citation`, `conclusion`, `fact`,
   `family_member`, `narrative`, `person` og `person_external_id`, er uændret.
4. Klausulerne for manifestets records er præcis manifestets (spænd, klassifikation,
   flag, tekst-hash, helpost-hash, startdisposition v1), og hver bærer writerens
   invarianter: samme forekomst, sider og kvalitet som helposten, helposten er rod,
   `extraction_method` slutter på regelversionen, kørslen er bundet til manifestet og
   batchen, dispositionen er maskinel med batchens evidens.
5. Én `finalized` batch med manifestets **genberegnede** hash og writer-profilens id og
   hash, én hændelse pr. record, alle klausuler fra én kørsel, hvis proveniensfelter
   matcher profilen; alle ældre `clause_evidence`-hændelser for kilden er bevaret uændret.
6. Ingen anden klausul i kildens inventar — også under forekomster uden accepteret
   anker — er tilføjet, fjernet eller ændret, målt på hele rækken og hele
   dispositionshistorikken.

**Afstemt delta:** kildens nye klausuler med dispositioner og de nye hændelser, som
ovenfor. **Ikke afstemt** ud over de nævnte felter: `reimport_authorization`,
`reimport_batch` og `extraction_run`.

**Hvad det ikke beviser:** at prod er summen af tidligere faser; tabeller uden for
listerne ovenfor, herunder autorisations-, batch- og kørselsrækkernes øvrige indhold;
RLS/ACL-definitioner (uændret DDL forudsættes).

**Forudsætninger, der hører til 4.1c's egen GO-pakke (ikke denne procedure):**
backup; writer-profilrækken for `daa-2018-20-clause-evidence-v1`, som **ikke findes i
prod** pr. 2026-09-17 — dens indsættelse er en varig prod-skrivning, der skal være et
hash-låst skridt med readback i 4.1c's prod-runbook (endnu ikke skrevet); apply.

**Procedure** (alt mod prod kører i projektejerens shell; sessionen læser kun de private
filer bagefter):

**Målbinding.** Alle psql-kald bruger den eksplicitte forbindelsesstreng `"$DAA_PROD_DSN"`
(Session pooler-DSN'en for DAA-projektet), aldrig omgivende `PG*`-variabler. Projektejeren
verificerer DSN'ens projekt-reference mod Supabase-dashboardet, før preflight køres.
`EXPECTED_TARGET` skrives ind i 4.1c's GO-dokument **før** backup, sammen med
`database_name`, og backup og rehearsal i 4.1c's GO-pakke tages mod samme DSN. Komparatoren
håndhæver derefter, at før- og efter-projektion er taget mod netop den database. Den
tilbageværende tillid hviler på én menneskelig kontrol: at DSN'en er prod.

0. **Læse-kun preflight** (resultatet skrives ind i GO-dokumentet):

   ```bash
   PGOPTIONS='-c default_transaction_read_only=on' psql "$DAA_PROD_DSN" -X -At -v ON_ERROR_STOP=1 \
     -c "SELECT current_database()" \
     -f .claude/skills/daa-extract/scripts/clause_evidence_target_identity.sql \
     -c "SELECT pg_has_role(current_user, 'anon', 'MEMBER')"
   ```

   Linje 1 er `database_name`, linje 2 `EXPECTED_TARGET`. Er linje 3 ikke `t`, kan
   projektionen ikke tage `anon`-hashes mod denne forbindelse — stop.
1. **Redaktionspause** fra før- til efter-projektion. Enhver redigering i vinduet giver
   `CANONICAL_DRIFT`/`ANON_DRIFT` (fail-closed).
2. **Ny run-mappe pr. forsøg; eksisterende mappe afvises, intet overskrives:**

   ```bash
   umask 077; setopt noclobber 2>/dev/null || set -o noclobber
   mkdir -p ~/.private/klausul-projektion-prod && chmod 700 ~/.private/klausul-projektion-prod
   RUN=$(mktemp -d ~/.private/klausul-projektion-prod/run-XXXXXXXX) || { echo "STOP: run-mappe"; exit 1; }
   ```

3. **Før-projektion** (efter profilrækken, før apply):

   ```bash
   DAA_PROJECTION_SQL_DIR=.claude/skills/daa-extract/scripts \
     psql "$DAA_PROD_DSN" -X -At -q -v ON_ERROR_STOP=1 -v source_id=1 \
     -f .claude/skills/daa-extract/scripts/clause_evidence_projection.psql > "$RUN/foer.json"
   ```

4. Apply af 4.1c efter dens egen GO.
5. **Efter-projektion:** samme kommando til `"$RUN/efter.json"`.
6. **Afstemning:**

   ```bash
   /usr/bin/python3 .claude/skills/daa-extract/scripts/compare_clause_evidence_projection.py \
     --manifest ~/.private/<4.1c-manifest>.json --before "$RUN/foer.json" --after "$RUN/efter.json" \
     --expect-target-sha256 <EXPECTED_TARGET fra GO-dokumentet> --report "$RUN/rapport.json"
   shasum -a 256 "$RUN"/*.json
   ```

   `--allow-empty` må **ikke** bruges mod prod.
7. **Bestået** kræver exit 0, `"status": "match"`, `database_target_sha256` =
   `EXPECTED_TARGET`, og at `counts` er lig rehearsalens (`clause-evidence-148-rehearsal.md`,
   afsnit »Klausul-projektion«).
8. **NO-GO** (exit 1): bevar run-mappen urørt, læs kun fejlkoden og den private rapports
   nøgler/feltnavne, og stop. Reparér aldrig prod for at få `match`; vejen tilbage er
   restore (decisions 2026-09-17).

## Hvad denne gate ikke beviser

Et match er **ikke** bevis for `prod = sum af alle historiske manifests`. Den
dækker kun `source_record`, accepted anchors, published narrative-bindinger,
narrativtekst-hash og person-ID'er for den anmeldte afgrænsning. Den dækker
ikke bl.a. DDL, `change_set`/audit, staged D1/D2-data, `same_som`/andre
identitetsrelationer, record-kind/rendition-bytes eller andre publicerede
fakta.

En fuld historisk lukning kræver desuden en autoritativ applied-manifest-ledger
bundet til den faktiske apply-batch samt manifest-specifikke projektorer, som
beviser hver bidragsrække mod originalmanifestet. Indtil de artefakter findes,
er ledgeret kun en hash-låst erklæring om det valgte input-sæt; det må ikke
omtales som bevis for fuldstændighed.

## Historiske undtagelser, der skal efterdokumenteres

Task 25-apply den 2026-08-18 og D1-kørslen med `change_set 955` havde ikke en
beholdt, mekanisk binding mellem den anvendte backup, en restore-rehearsal og
den samtidige menneskelige GO. #156-kørslen den 2026-09-03 forseglede ét
read-only source 3-snapshot med 592 source records, 897 accepted anchors, 563
published bindinger, 563 narrativ-hashes og 563 personer, men admission
stoppede som `EVIDENCE_RECONCILIATION_INCOMPLETE` før rækkeafstemning, fordi
alle apply-records kun er `afterdocumented_unbound` og D1 er `unavailable`.
Kørslen viser derfor den aktuelle optalte datatilstand, men ikke hvilke rækker
der kan tilskrives Task 25 eller D1, og den udleder udtrykkeligt ingen
retroaktiv GO for nogen af dem. Se
`docs/superpowers/reviews/2026-08-22-evidensbaseret-genimport-afvigelsesvurdering.md`
§§5 og 7.11 for den fulde vurdering.
