# 149b legacy-migration: fase-pakke-bidrag med kvittering

**Bidrag:** `legacy-migration-149b`
**Skrevet:** 2026-09-04 (efter rehearsal-rapporten)
**Tilstand:** `afterdocumented` — samme tilstand som 149a's og #156's adaptervej:
kvitteringen er efterdokumenteret fra rehearsal-artefakterne, ikke udstedt af
en gate-runner
**Produktionsautorisation:** nej — `apply_gate = NO-GO`

Dette bidrag registrerer 149b's manifest og det gennemførte lokale bevis i
fase-pakke-ledgeren (spec §7, `docs/decisions.md` 2026-09-03/04). Det er ikke
en produktionskvittering. Kun nøgler, tal og hashes; ingen persondata.

## Kvittering

| Felt | Værdi |
| --- | --- |
| `contribution_id` | `legacy-migration-149b` |
| `state` | `afterdocumented` |
| `source.id` | `1` |
| `source.profile_id` | `daa-2018-20-legacy-migration-v1` |
| `source.profile_version` | `legacy-migration-v1` |
| `source.profile_sha256` | `954f3bb361863af487ab08b6ad6ff972b319db2dd0b38e4031f0146e509d95b4` |
| `manifest.manifest_content_sha256` | `b4baa1aec784d483905e0cb6c0bbd74e4d74de7cc1ec69f76287279b1db0f211` |
| `manifest.manifest_bytes_sha256` | `662f16f37f0fc8e13acc10c465ea38fa1b77ddcecfdecb93e7424ce4ee43aa5b` |
| `preview.preview_sha256` | `774efc5b9ebd37ae6514d5cfddc9d3435746634035f7c9316446a80fc91dceb9` |
| `expected_counts` (manifest, 4 nøgler) | `{"canonical_delta": 0, "legacy_migrations": 587, "person_creates": 0, "source_evidence": 0}` |
| `expected_counts` (preview/autorisation, 3 nøgler — `canonical_delta` fjernet) | `{"legacy_migrations": 587, "person_creates": 0, "source_evidence": 0}` |
| `observed_counts.dispositions` | `{"bound_published": 541, "bound_draft": 46, "unresolved_text": 4, "unresolved_identity": 0}` |
| `observed_counts.legacy_migrations` (operationer i manifestet, = `bound_published + bound_draft`) | `587` |
| `dispositions.unresolved_text_keys` | `["I-133", "II-35", "III-129", "IV-94"]` |
| `authorization.id` (apply, forbrugt) | `26d4ff6a-edf8-4b5c-a9d2-e7eed082ac7e` |
| `authorization.id` (replay, forbrugt) | `b7d53d6d-c74b-4e15-90d5-c2eb5aa3ee93` |
| `batch.batch_id` | `cf32ba22-8229-4c67-bcdd-097305d8bea8` |
| `batch.status` | `finalized` |
| `batch.database_name` | `daa149b_rehearsal_20260904` (engangsbase, persisteres til videre 149b-arbejde, ikke droppet) |
| `batch.system_identifier` | `7680906716015365850` |
| `batch.contract_version` | `2` |
| `backup.kind` | prod-dump + ren restore-skabelon (`daa149b_inv_20260903`, urørt gennem hele kørslen) som gendannelsesbevis |
| `backup.sha256` | `fcfeb22532975d45803b98813e51bdde33b5a79537547b7ce202a28eaf7046b3` (`pre-c0f-20260821-112005.dump`, fuld fra STEP1) |
| `events.draft_created` | `587` |
| `events.published` | `541` |
| `events.legacy_migrated` | `541` |
| `events.baseline` (uændret) | `544` |
| `ledger_after.migrated` | `541` |
| `ledger_after.grandfathered_publication` | `3` |
| `ledger_after.withdrawn` | `0` |
| `identity.source_persona` | `587` |
| `identity.accepted_person_external_id` | `587` |
| `result.bound_published` | `541` |
| `result.bound_draft` | `46` |
| `canonical_delta.rows_changed` | `0` |
| `canonical_delta.aggregate_hashes_identical` | `true` (4 tabeller: `person`, `fact`, `family_member`, `narrative`; målt under `PGTZ=UTC`) |
| `visibility.anon_hashes_identical` | `true` (8 hashes: `assertion`, `citation`, `conclusion`, `fact`, `family_member`, `narrative`, `person`, `person_external_id`) |
| `visibility.public_v2_source_record` | `541` (op fra 0) |
| `visibility.public_v2_legacy_narrative` | `3` (ned fra 544) |
| `replay` | `already_applied` |
| `reversal.single_narrative_available` | `true` — reverse `legacy_migrated` → discard draft → reverse `published`-kæden gendanner eksakt førtilstand for begge streams (transaktion rullet tilbage, ikke committet) |
| `reversal.batch_apply_proven_in` | `tests/integration/test-reimport-legacy-migration.R` (ikke i denne rehearsal) |
| `reversal.batch_dry_run_observed` | `true` — `reversed_elements=587`, `receipts_sha256=33c205ddf1142fd4c187c526dc6d4171f5c471f94ba0cd5941622871ab5ea8b9`, `committed=false` |
| `reversal.red_reverse_reimport_observed_code` | `REIMPORT_WRITER_REVERSAL_INVALID` |
| `production_authorized` | `false` |
| `apply_gate` | `NO-GO` |

## Forudsætninger bidraget hviler på

1. Basen havde 149a's `source_evidence`-kæde allerede anvendt (batch
   `16482e81-212d-4c30-8dc7-c562c16daf77`, `finalized`, 1/591/591/591) og var
   migreret til kontraktversion 2 via #152's cutover — begge forudsætninger
   for at 149b's writer overhovedet kan autoriseres.
2. #153's migrationsguard-rettelse (commit `1ad4da6`, `finalized` som terminal
   for reimport-batches uden personoprettelser) er anvendt på samme base som
   149a, uden hvilken hverken 149a eller 149b kunne migreres mod dette dump.
3. Prod-rækkefølgen er uændret: #152-cutover → #153 (med guard-rettelsen) →
   149a → 149b.
4. Valg A (identitet uden placement-kæde, spec §5) og valg B
   (reversal-designet, spec §8) er PM-rollens egne valg og afventer
   projektejerens eksplicitte kvittering før prod-GO — se
   `docs/decisions.md` 2026-09-03/04.

## Restpunkter

1. **Fase-pakke-gaten kan ikke lukkes af 149b alene**, af samme grund som
   149a's bidrag: `docs/runbooks/evidence-import-phase-gate.md` og
   receipt-skemaerne findes ikke som maskinelt kørende gate endnu (#156
   lukket med restpunkt). Indtil da er tilstanden `afterdocumented`.
2. **De 4 `unresolved_text`-narrativer og de 13 mulige `NOISE_RE`-prosalinjer
   er ikke rettet** — rapporteret i
   [rehearsal-rapporten](legacy-migration-149b-rehearsal.md) og
   [inventeringen](../superpowers/reviews/2026-09-03-2018-20-fase-a-inventering.md)
   måling 8; tekstrettelse for 2018-20 er en separat, endnu utruffet
   beslutning.
3. **Valg A/B afventer kvittering** — se ovenfor; uden den er der intet
   prod-GO for 149b, uanset at rehearsal er grøn.
4. **Batch-reversalens `--apply` er kun bevist syntetisk**, ikke mod denne
   rehearsal-base; en apply-gentagelse ville kræve en ny restore.
5. **Deferred minors** (M-1 til M-7 for Task 5, plus review-fund for Task
   6/7) står i
   `.superpowers/sdd/2026-09-03-2018-20-fase-b-legacy-migration/progress.md`
   — ingen er blokerende for dette bidrag.
