# 149a source_evidence: fase-pakke-bidrag med kvittering

**Bidrag:** `source-evidence-149a`
**Skrevet:** 2026-09-03 (efter Del B i [rehearsal-rapporten](source-evidence-149a-rehearsal.md))
**Tilstand:** `afterdocumented` — samme tilstand som #156's adaptervej: kvitteringen er
efterdokumenteret fra rehearsal-artefakterne, ikke udstedt af en gate-runner
**Produktionsautorisation:** nej — `apply_gate = NO-GO`

Dette bidrag registrerer 149a's manifest og det gennemførte lokale bevis i
fase-pakke-ledgeren (spec §6, `docs/decisions.md` 2026-09-03). Det er ikke en
produktionskvittering. Kun nøgler, tal og hashes; ingen persondata.

## Kvittering

| Felt | Værdi |
| --- | --- |
| `contribution_id` | `source-evidence-149a` |
| `state` | `afterdocumented` |
| `source.id` | `1` |
| `source.profile_id` | `daa-2018-20-source-evidence-v1` |
| `source.profile_version` | `source-evidence-v1` |
| `source.profile_sha256` | `5919b60384e4b32e26e5308c849e51a6b61722c109edb17e24262c175df676db` |
| `inputs.pdf_sha256` | `3beadfc15e3fa1a4090589af56cd4e95599a9231e8f979dfb60c4e27bbd8252a` |
| `inputs.raw_text_sha256` | `2dd5cf8408943ccc50ac4d89dcbd08ac3b49a90fdabd1ddcbd7b22d218026563` |
| `inputs.segment_digest_sha256` | `eded027e49bbde6857e4c9bcb53b5a3954c1438fc271e26c9b5b4355694df742` |
| `manifest.manifest_content_sha256` | `c7d19c014610b2e824719048e3733607279e55bbe88b96dc99cce4e3d6f83a8e` |
| `manifest.manifest_bytes_sha256` | `db58e4074fd54093959d2cecd2ec33569f5e82f6ff340242610278bb5eae819b` |
| `preview.preview_sha256` | `80709daf0abde8da68548297b4abe620b7a96027e55de5f4bbe71e90f7f0106a` |
| `expected_counts` | `{"person_creates": 0, "source_evidence": 591}` |
| `observed_counts` | `{"person_creates": 0, "source_evidence": 591}` |
| `authorization.id` | `628eb264-7539-4cfa-a96f-816dba0bc0f7` (operation `reimport`, forbrugt) |
| `batch.batch_id` | `a3304ce1-7004-4d01-97d4-83eab2ad84f8` |
| `batch.status` | `finalized` |
| `batch.database_name` | `daa149a_rehearsal2_20260903` (engangsbase, droppet efter bevis) |
| `batch.system_identifier` | `7680906716015365850` |
| `batch.contract_version` | `2` (efter #152-cutover, nonce `15212000-0000-4000-8000-000000003401`) |
| `backup.kind` | prod-dump + ren restore-base som gendannelsesbevis (se restpunkt 2) |
| `backup.sha256` | `fcfeb22532975d45803b98813e51bdde33b5a79537547b7ce202a28eaf7046b3` (`pre-c0f-20260821-112005.dump`) |
| `result.renditions` | `1` |
| `result.source_records` | `591` |
| `result.occurrences` | `591` |
| `result.accepted_anchors` | `591` |
| `canonical_delta.rows_changed` | `0` |
| `canonical_delta.aggregate_hashes_identical` | `true` (5 tabeller: `person`, `fact`, `family_member`, `narrative`, `private.narrative_record_publication`; målt under `PGTZ=UTC`) |
| `visibility.anon_hashes_identical` | `true` (9 hashes mod referencebasen `daa149a_anonref_20260903`) |
| `replay` | `already_applied` (autorisation `0d837b43-28f4-4667-9814-d6bb2992538c`) |
| `reversal.available` | `false` |
| `reversal.observed_code` | `REIMPORT_WRITER_REVERSAL_INVALID` (reversal-autorisation `c7746336-f5db-44c2-a2d0-b420d03d73bd`) |
| `reversal.restore_proof` | `true` (ren restore af samme dump viser 0/0/0/0 for source 1) |
| `reversal.owner_acknowledged` | `true` — projektejeren kvitterede reversal-afvigelsen 2026-09-03 (`docs/decisions.md`, commit `8e9efeb`) |
| `production_authorized` | `false` |
| `apply_gate` | `NO-GO` |

## Forudsætninger bidraget hviler på

1. #152's cutover til kontraktversion 2 er gennemført i den base, batchen kørte i.
2. #153's migrationsguard er rettet, så en `finalized` reimport-batch uden
   personoprettelser regnes som terminal (commit `1ad4da6`); uden rettelsen
   stopper `db-migrations.sql` på 1939 fase A-batchen (`REIMPORT_LEGACY_IN_FLIGHT_MIGRATION_BLOCKED`).
3. Prod-rækkefølgen er uændret: #152-cutover → #153 med guard-rettelsen → 149a.

## Restpunkter

1. **Fase-pakke-gaten kan ikke lukkes af 149a alene.**
   Runbooken `docs/runbooks/evidence-import-phase-gate.md` er nu i repoet (flyttet fra
   PR #165, som blev lukket uden merge 2026-09-06), men receipt-skemaerne
   `daa-evidence-phase-receipt-*-v1` findes ikke som maskinelt kørende gate;
   #156's afstemning endte INCOMPLETE (se
   `evidence-phase-reconciliation-156-2026-09-03.md`). Indtil en generel gate
   findes, er tilstanden
   `afterdocumented`.
2. **Ingen 0600-backup af rehearsal-basen selv.** Del B tog ikke en separat
   backup af `daa149a_rehearsal2_20260903` før apply; gendannelse er bevist
   ved den rene restore `daa149a_dumpbase_20260903` af samme dump. Prod-kørslen
   SKAL tage en 0600-backup med SHA før apply (runbookens §1).
3. **Prod-snapshottet fra #156** (source 3) er ikke afstemt mod dette bidrag;
   bidraget vedrører source 1.
