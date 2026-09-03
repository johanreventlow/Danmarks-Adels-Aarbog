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

For hver anvendt originalmanifest oprettes et lille reconciliation-bidrag ved
siden af den hash-låste pakke i den ignorerede fase-mappe. Feltet
`source_manifest_sha256` binder bidraget til de rå bytes i den originale,
hash-låste pakke; controlleren kontrollerer den binding. Bidraget bruger præcis
dette format før forsegling:

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
narrativ-hash, før fasens nye rækker lægges på. Før review forsegles filen uden
at skrive til produktion:

```bash
/usr/bin/python3 .claude/skills/daa-extract/scripts/reconcile_evidence_phase_gate.py \
  --seal phase-a-contribution.unsealed.json > phase-a-contribution.json
```

Forseglingen beregner `reconciliation_content_sha256` over kanonisk JSON. En
ændret originalmanifest kræver et nyt bidrag, ny hash, ny rehearsal og en ny
GO; redigér aldrig en allerede anvendt pakke. Commit højst en datafri
GO-kvittering med fase-ID og SHA'er — ikke bidraget, snapshot eller anden
person-/kildeidentificerende data.

GO-kvitteringen er et obligatorisk, hash-låst faseledger for den erklærede
afstemning. Den låser det præcise input-sæt og den semantiske rækkefølge; et
manglende eller ekstra CLI-bidrag er teknisk NO-GO. Den kan ikke i sig selv
bevise, at inventaret er historisk komplet, eller at et bidrags fem lister er
udledt korrekt fra originalmanifestet:

```json
{
  "schema_version": "daa-evidence-phase-artifact-ledger-v2",
  "phases": [{
    "phase_id": "1939-phase-a",
    "sequence": 1,
    "artifacts": [{
      "role": "contribution",
      "path": "phase-a-contribution.json",
      "sha256": "<64 lower-case hex>",
      "schema_version": "daa-evidence-phase-reconciliation-manifest-v1",
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
produktionssnapshotet læses eller sammenlignes. Forsegl og commit den
datafri ledger med den validerede fase-ledger-proces; brug aldrig
`reconcile_evidence_phase_gate.py --seal` til ledgeret.

## Privat artefaktaudit før prod-snapshot

Før en mulig afstemning skal operatøren køre den datafri artefaktaudit mod den
ignorerede, retained bundle. Både kataloget og outputmappen lever kun i denne
private bundle; de må aldrig committes, kopieres til terminaloutput eller
erstattes af artefakter fra repositoryet. Kataloget har schema
`daa-evidence-phase-artifact-catalog-v1` og indeholder alene fase-ID,
positiv unik sekvens, adapter-ID, evidenstilstande, eventuel
database-target-identity-hash og artefaktmetadata (`role`, relativ `path`,
`schema_version`, `required`) — aldrig artefakt-SHA'er, projektionsidentiteter
eller private rækker.

Med bundle-specifikke, private stier er den eksakte kørsel:

```bash
/usr/bin/python3 .claude/skills/daa-extract/scripts/run_evidence_phase_artifact_audit_1939_v50.py \
  --bundle-root /private/retained/1939-v50-evidence-bundle \
  --catalog /private/retained/1939-v50-evidence-bundle/artifact-catalog.json \
  --private-output-dir /private/retained/1939-v50-evidence-bundle/private-artifact-audit
```

CLI'en afviser symlinks, path-escapes, manglende eller ikke-tomme
outputmapper og eksisterende mål før den overskriver noget. Den hasher de
præcise artefaktbytes og den registrerede projectorkilde, forsegler
`audit-ledger.json`, skriver `audit-summary.json` og skriver kun
fasebidrag for mekanisk bundne faser. Alle private outputfiler oprettes
eksklusivt med mode `0600`.

Historiske huller er fortsat `INCOMPLETE`: hvis blot én fase ikke er mekanisk
bundet, er exitkoden `2`, `reconciliation-ledger.json` udelades, og auditten
må ikke opfinde en kvittering eller promovere fasen. Terminalen er bevidst
begrænset til status, stabile fejltokens, fase-/evidenstilstande, hasher og
optællinger; de eksakte private rækker bliver i bundle-outputtet.

En komplet audit er alene en artifact-admission. Stop her, indtil en separat
autorisation udtrykkeligt tillader det nedenstående read-only
produktionssnapshot; denne kommando åbner ingen database og giver ingen
autorisation til snapshot, apply eller anden produktionshandling.

### Syntetisk fail-closed bevis

Den automatiske ende-til-ende-test bruger kun syntetiske manifest-, receipt-
og target-identiteter. Den første, historisk formede fixture kører Task 25,
fase A, fase B, narrativ-publicering, name-completion, C0 og D1 i denne
rækkefølge. Task 25, fase B og C0 har bundne syntetiske receipts, mens fase A,
narrativ-publicering og name-completion er ubundne; D1 er `unavailable`.
Resultatet skal være exitkode `2`, ingen `reconciliation-ledger.json` og ingen
læsning af noget snapshot.

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

WITH source_records AS (
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
  'source_records', source_records.rows,
  'source_anchors', source_anchors.rows,
  'narrative_bindings', bindings.rows,
  'narrative_sha256', narrative_sha256.rows,
  'persons', persons.rows
))
FROM source_records, source_anchors, bindings, narrative_sha256, persons;

COMMIT;
```

Gem den returnerede JSON som et lokalt, uforseglet snapshot. Forsegl den og
kør afstemningen med alle fasebidrag som eksplicitte argumenter:

```bash
/usr/bin/python3 .claude/skills/daa-extract/scripts/reconcile_evidence_phase_gate.py \
  --seal prod-source-3.unsealed.json > prod-source-3.snapshot.json

/usr/bin/python3 .claude/skills/daa-extract/scripts/reconcile_evidence_phase_gate.py \
  --snapshot prod-source-3.snapshot.json \
  --ledger applied-phase-ledger.json \
  --phase-manifest task25-contribution.json \
  --phase-manifest phase-a-contribution.json \
  --phase-manifest phase-b-contribution.json \
  --private-report .private/reconcile-drift.json
```

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

To allerede udførte prod-skrivninger var ikke dækket af en committet GO-pakke
efter denne model:

- Task 25-apply den 2026-08-18, inklusive deploy af det private evidenslag.
  Readiness-dokumentet registrerede NO-GO, mens changelog registrerer apply;
  den efterfølgende pakke skal derfor eksplicit markere denne mangel i stedet
  for at udlede en GO retroaktivt.
- Fase D1 den 2026-08-19 (`change_set 955`), hvor 68 personer blev publiceret.
  Den oprindelige kørsel var ikke bundet til en committet fase-pakke.

Afstemningen kan vise den nuværende datatilstand og dens manglende eller
ekstra identiteter. Den kan ikke skabe den samtidige backup, rehearsal eller
godkendelse, som de to historiske skrivninger manglede. Se
`docs/superpowers/reviews/2026-08-22-evidensbaseret-genimport-afvigelsesvurdering.md`
§§5 og 7.11 for den fulde vurdering.
