# Fase 0a — målinger (helhedsreview trin 1-5)

> Mekaniske tal fra en ren eksport af repoet (`git archive` af `docs/review-trin-1-5` @ `37a7d408`, dvs. `main` `8ac893c5` + spec og plan,
> 2.170 sporede filer, ingen `work*`-mapper). Ingen vurdering: tallene er input til fase 1. Scripts:
> scratchpad `maal/maal.py`. Docs-PR #271 (5c-1 i prod) var ikke merget, da eksporten blev taget.

## 1. Funktioner i `schema.sql` mod `db-migrations.sql`

`schema.sql` er source of truth og bruges af CI til friske baser. Prod opdateres via de idempotente blokke i
`db-migrations.sql`. Migrationsfilen *skal* gentage definitioner, så antal i sig selv er ikke et fund. Det, der
tæller, er om **den sidste definition** i hver fil er den samme.

| Mål | Tal |
|---|---|
| Funktionsnøgler (navn + argumenttyper) i `schema.sql` / definitioner | 349 / 356 |
| Funktionsnøgler i `db-migrations.sql` / definitioner | 361 / 511 |
| Nøgler i begge | 349 |
| Kun i migrationsfilen | 12 (fx gamle signaturer, der droppes senere; tillæg B) |
| Sidste definition rå identisk | 220 |
| Identisk efter normalisering (kommentarer og whitespace, inkl. omkring tegnsætning; `CREATE` = `CREATE OR REPLACE`) | 315 |
| **Divergerende efter normalisering** | **34** (tillæg A) |

Lighed for de 34: 13 ≥ 0,98, 20 mellem 0,90 og 0,98, 1 under 0,90. Stikprøver:

- **`private.narrative_record_state`** (lighed 0,995): migrationens definition har et ekstra join-filter
  `JOIN public.source source ON source.id=narrative.source_id AND source.slags='DAA-udgave'`, som skemaets
  definition ikke har. Senest ændret i migrationsfilen 2026-09-04 (`93d7fbe5`, 149b).
- **`public.red_opret_kilde`**: skemaet tildeler id med `coalesce(max(id),0)+1` (2026-06-30); migrationsfilen
  bruger `RETURNING id` siden 2026-07-03 (`5ee6bc87`).
- **`public.red_decide_source_record_placement`** (0,888): to håndskrevne udgaver — migrationen bruger `$1..$4` og
  andre variabelnavne og er ikke genereret fra skemaet. Ser ud til samme adfærd; ikke efterprøvet.
- **`private.ocr_fingerprint`**: forskel kun i whitespace omkring tegnsætning (fanges af normaliseringen).

Konsekvens at vurdere i fase 1b: hvor den sidste definition divergerer, tester CI (bygget fra skemaet) en anden
funktion end den, prod har fået fra migrationerne.

Begrænsninger: funktioner skabt inde i `DO`-blokke med `EXECUTE` er ikke talt; overloads nøgles på argumenttyper
(6 navne har to signaturer).

## 2. Versionsfiler side om side

»v50« i 1939-filnavne er udgavens profilnavn, ikke en filversion (par af `.py`/`.R` med samme stamme). Ægte
versionsfiler:

- `relation_persona_extract.py`, `_v2.py`, `_v3.py` — alle tre refereres fra kode (6/6/5 filer).
- `relation_marriage_sheet.py` og `_v3.py` — begge refereres.
- `relation_v2_rows.sql`, `relation_v3_rows.sql`; `afstem_v2.py`, `build_1939_v2.py`, `evidenspas_v2.py` (uden v1).

## 3. Tests og CI

| Mål | Tal |
|---|---|
| Testfiler i dataarbejdet (`.py`, `.R`, `.sql`, `.sh`) | 310 |
| Kørt af CI (nævnt i `ci.yml`, transitivt via scripts CI kalder, `unittest discover` i `daa-haendelser`, `tests/testthat`) | 200 |
| **Ikke kørt af CI** | **110**: 88 i `daa-extract/scripts`, 13 i `tests/sql`, 8 i `tests/integration`, 1 fixture |

Python-jobbet kører `daa-extract`'s tests via en fast pytest-liste, ikke `discover`; nye testfiler kommer kun med,
hvis nogen tilføjer dem. De 71 Python-testfiler uden for CI er kørt lokalt i den rene eksport (tomt miljø, ingen
database): **68 grønne, 2 røde** (`test_build_c3_html_review_1939_v50.py` 9 fejl, `test_convert_c3_decisions_1939_v50.py`
2 fejl), 1 springer over (`test_evidenspas_v2.py`). R-, SQL- og shell-tests uden for CI er ikke kørt (kræver database).

## 4. Kandidater til død kode

38 ikke-test-filer refereres hverken fra kode, CI eller scripts (27 i `daa-extract/scripts`, resten i `R/`,
`daa-presens`, `tests/sql`, roden). 35 af dem nævnes i docs (runbooks/specs), så de er sandsynligvis
engangsværktøjer, der blev kørt manuelt. 3 nævnes intet sted (166 linjer). Liste i tillæg F.

## 5. Størrelse (linjer, dataarbejdet)

`daa-extract/scripts` 112.813 · rodfiler (SQL m.m.) 59.224 · `tests/` 38.421 · `R/` 3.167 · `daa-haendelser` 956 ·
`daa-presens` 419.

## Tillæg
### A. De 34 divergerende funktioner (sidste definition; lighed efter normalisering)

| lighed | funktion | schema.sql | db-migrations.sql |
|---|---|---|---|
| 0.888 | `public.red_decide_source_record_placement(uuid,integer,text,jsonb)` | 2507 | 7114 |
| 0.911 | `private.propose_source_persona_placement(uuid,uuid,text,uuid,jsonb,text)` | 2487 | 7102 |
| 0.915 | `public.red_decide_source_persona_placement(uuid,integer,text,jsonb)` | 2553 | 7136 |
| 0.918 | `private.propose_source_record_placement(uuid,bigint,uuid,jsonb,text)` | 2467 | 7090 |
| 0.922 | `public.red_ret_ocr_felt(bigint,text,text,text,text,jsonb,text,text)` | 1970 | 3892 |
| 0.924 | `public.red_opret_organisation(text,text)` | 7661 | 4360 |
| 0.932 | `public.red_opret_estate(text,text,bigint)` | 7637 | 4280 |
| 0.940 | `public.red_opret_kilde(text,text,text,boolean,smallint)` | 7649 | 4322 |
| 0.948 | `private.validate_placement_decision()` | 2393 | 7037 |
| 0.957 | `public.red_set_story_kilder(bigint,jsonb)` | 6129 | 4802 |
| 0.959 | `public.begin_change_set(text,text,text,bigint)` | 8321 | 4078 |
| 0.968 | `public.red_opret_person(text,text,boolean,text,text,text)` | 7611 | 4371 |
| 0.969 | `public.red_set_feed_pin(text,text)` | 6154 | 4523 |
| 0.970 | `public._ensure_foraeldrefamilie_redaktionel(bigint,bigint)` | 7037 | 4046 |
| 0.970 | `public.red_opret_fakta(text,bigint,text,text,date,date,text,text,text)` | 5833 | 4291 |
| 0.970 | `private.require_reimport_1939_editor()` | 3507 | 7931 |
| 0.972 | `public.red_registrer_media_variant(bigint,text,text,text,bigint,int,int)` | 7831 | 4437 |
| 0.973 | `public.log_change()` | 8353 | 4101 |
| 0.974 | `public.red_opret_media(text,text,text,text,text,text,text,bigint,int,int,text,text,text,boolean)` | 7677 | 4333 |
| 0.977 | `public.red_upsert_fakta(text,bigint,text,text,date,date,text,text,text)` | 5752 | 4690 |
| 0.978 | `public.red_ocr_historik(text,text,text)` | 2086 | 3910 |
| 0.981 | `public.red_tilfoej_oplysning(bigint,text,date,date,text,text,text)` | 5803 | 4641 |
| 0.981 | `public.red_opret_story(text,bigint,text,text,bigint,bigint,bigint,bigint,date,date,text,text,boolean)` | 6047 | 4396 |
| 0.982 | `private.require_reimport_open_batch(uuid)` | 3603 | 12081 |
| 0.987 | `public.red_tilfoej_foraeldre_paastand(bigint,bigint,bigint,text,text,text)` | 7390 | 4562 |
| 0.987 | `public.red_edit_oplysning(bigint,text,text,text)` | 5890 | 4131 |
| 0.989 | `private.normalize_interpretation_proposal_value(jsonb)` | 4327 | 19034 |
| 0.990 | `private.require_reimport_writer_editor()` | 3595 | 12080 |
| 0.992 | `private.assert_interpretation_has_observation()` | 1744 | 6072 |
| 0.994 | `private.validate_evidence_scope()` | 857 | 5605 |
| 0.995 | `private.narrative_record_state(bigint,bigint,text,boolean)` | 12993 | 13951 |
| 0.998 | `private.assert_identity_state_event_consistency()` | 1831 | 6148 |
| 0.998 | `private.validate_interpretation_promotion()` | 1756 | 6081 |
| 0.999 | `private.validate_interpretation_promotion_items(jsonb,boolean)` | 9502 | 7548 |

### B. Kun i db-migrations.sql (12)

- `private.add_interpretation_promotion_rule_version(text,text,text,text,text,text,boolean,boolean,boolean,text)`
- `private.ensure_reimport_1939_source_evidence(uuid,text,jsonb)`
- `private.ensure_reimport_operations(text[])`
- `private.reject_reimport_1939_event_mutation()`
- `private.require_reimport_1939_open_batch(uuid)`
- `private.validate_reimport_1939_name_completion(uuid,uuid,text,jsonb)`
- `public.entitet_offentlig(text,bigint)`
- `public.red_authorize_reimport_name_completion(text,uuid,text,text,jsonb,jsonb)`
- `public.red_lock_reimport_name_completion(text)`
- `public.red_opret_kilde(text,text,text,boolean)`
- `public.red_upload_media(text,text,text,text,bigint,text,bigint,bigint,int,int,text,text,text,boolean)`
- `public.red_upsert_narrativ(text,bigint,text,boolean)`

### C. Mest gentagne definitioner i db-migrations.sql

- `public.red_finalize_reimport(uuid)`: 7 gange
- `private.validate_reimport_authorization_payload(jsonb,jsonb)`: 6 gange
- `public.red_reimport_batch_result(uuid,uuid)`: 6 gange
- `private.write_relation_persona(uuid,text,jsonb)`: 5 gange
- `public.red_relation(text,bigint,text,bigint,text,text)`: 4 gange
- `public.red_tilfoej_barn(bigint,bigint,text,text)`: 4 gange
- `public.red_reverse_1939_v50_reimport(uuid,uuid)`: 4 gange
- `public.red_activate_1939_v50_batch(uuid,uuid)`: 4 gange
- `private.relation_binding_state(uuid)`: 4 gange
- `public.regen_person_visning(bigint)`: 3 gange
- `public.red_upsert_fakta(text,bigint,text,text,date,date,text,text,text)`: 3 gange
- `public.red_slet_person(bigint)`: 3 gange
- `public.red_tilfoej_oplysning(bigint,text,date,date,text,text,text)`: 3 gange
- `public.red_opret_fakta(text,bigint,text,text,date,date,text,text,text)`: 3 gange
- `public.red_fortryd_change_set(bigint,boolean)`: 3 gange

### D. Testfiler, der ikke køres af CI (110)

- `.claude/skills/daa-extract/scripts/test_afstem_lokator.py`
- `.claude/skills/daa-extract/scripts/test_afstem_v2.py`
- `.claude/skills/daa-extract/scripts/test_amend_structural_context_1939.py`
- `.claude/skills/daa-extract/scripts/test_anchor_review_choices_1939.py`
- `.claude/skills/daa-extract/scripts/test_apply_c0_followup_1939_v50.R`
- `.claude/skills/daa-extract/scripts/test_apply_c3_1939_v50.R`
- `.claude/skills/daa-extract/scripts/test_apply_name_completion_1939_v50.R`
- `.claude/skills/daa-extract/scripts/test_apply_narrative_replacement_1939_v50.R`
- `.claude/skills/daa-extract/scripts/test_apply_phase_a_1939_v50.R`
- `.claude/skills/daa-extract/scripts/test_apply_reconciliation_decisions_1939.py`
- `.claude/skills/daa-extract/scripts/test_apply_reimport_1939_v50.R`
- `.claude/skills/daa-extract/scripts/test_audit_1939.py`
- `.claude/skills/daa-extract/scripts/test_boundary_signals_1939.py`
- `.claude/skills/daa-extract/scripts/test_boundary_spans_1939.py`
- `.claude/skills/daa-extract/scripts/test_build_1939_v2.py`
- `.claude/skills/daa-extract/scripts/test_build_c0_followup_flags_1939_v50.py`
- `.claude/skills/daa-extract/scripts/test_build_c0_followup_manifest_1939_v50.py`
- `.claude/skills/daa-extract/scripts/test_build_c0_record_linkage_1939_v50.py`
- `.claude/skills/daa-extract/scripts/test_build_c3_apply_candidate_1939_v50.py`
- `.claude/skills/daa-extract/scripts/test_build_c3_html_review_1939_v50.py`
- `.claude/skills/daa-extract/scripts/test_build_c3_review_1939_v50.py`
- `.claude/skills/daa-extract/scripts/test_build_c3_selection_1939_v50.py`
- `.claude/skills/daa-extract/scripts/test_build_death_year_identity_review_1939_v50.py`
- `.claude/skills/daa-extract/scripts/test_build_eligible_selection.py`
- `.claude/skills/daa-extract/scripts/test_build_identity_review_1939_v50.py`
- `.claude/skills/daa-extract/scripts/test_build_mapped_identity_review_1939_v50.py`
- `.claude/skills/daa-extract/scripts/test_build_name_completion_manifest_1939_v50.py`
- `.claude/skills/daa-extract/scripts/test_build_narrative_record_cutover_review.py`
- `.claude/skills/daa-extract/scripts/test_build_narrative_replacement_manifest_1939_v50.py`
- `.claude/skills/daa-extract/scripts/test_build_phase_a_anchor_manifest_1939_v50.py`
- `.claude/skills/daa-extract/scripts/test_build_production_write_manifest_1939_v50.py`
- `.claude/skills/daa-extract/scripts/test_build_provenance_review_1939_v50.py`
- `.claude/skills/daa-extract/scripts/test_build_remaining_identity_review_1939_v50.py`
- `.claude/skills/daa-extract/scripts/test_c0_followup_review_1939_v50.py`
- `.claude/skills/daa-extract/scripts/test_clause_ledger.py`
- `.claude/skills/daa-extract/scripts/test_convert_1939.py`
- `.claude/skills/daa-extract/scripts/test_convert_c0_linkage_decisions_1939_v50.py`
- `.claude/skills/daa-extract/scripts/test_convert_c3_apply_approvals_1939_v50.py`
- `.claude/skills/daa-extract/scripts/test_convert_c3_decisions_1939_v50.py`
- `.claude/skills/daa-extract/scripts/test_convert_d1_publication_decisions_1939_v50.py`
- `.claude/skills/daa-extract/scripts/test_convert_narrative_decisions_1939_v50.py`
- `.claude/skills/daa-extract/scripts/test_coverage_1939.py`
- `.claude/skills/daa-extract/scripts/test_detect_boundary_defects_1939.py`
- `.claude/skills/daa-extract/scripts/test_dual_rendition_evidence_1939.py`
- `.claude/skills/daa-extract/scripts/test_efterudtraek_1939.py`
- `.claude/skills/daa-extract/scripts/test_escalate_merge.py`
- `.claude/skills/daa-extract/scripts/test_evidenspas_v2.py`
- `.claude/skills/daa-extract/scripts/test_export_c0_followup_selection_1939_v50.R`
- `.claude/skills/daa-extract/scripts/test_export_c0_narrative_state_1939_v50.R`
- `.claude/skills/daa-extract/scripts/test_export_c3_apply_preview_1939_v50.R`
- `.claude/skills/daa-extract/scripts/test_export_c3_current_state_1939_v50.R`
- `.claude/skills/daa-extract/scripts/test_export_d1_staged_selection_1939_v50.R`
- `.claude/skills/daa-extract/scripts/test_export_narrative_old_sha_1939_v50.R`
- `.claude/skills/daa-extract/scripts/test_finalize_c3_apply_manifest_1939_v50.py`
- `.claude/skills/daa-extract/scripts/test_identitetsregister.py`
- `.claude/skills/daa-extract/scripts/test_lokator.py`
- `.claude/skills/daa-extract/scripts/test_make_boundary_review_1939.py`
- `.claude/skills/daa-extract/scripts/test_make_human_review_1939.py`
- `.claude/skills/daa-extract/scripts/test_match_c0_records_1939_v50.py`
- `.claude/skills/daa-extract/scripts/test_materialize_graenseflade_1939.py`
- `.claude/skills/daa-extract/scripts/test_materialize_identity_decisions_1939_v50.py`
- `.claude/skills/daa-extract/scripts/test_materialize_provenance_decisions_1939_v50.py`
- `.claude/skills/daa-extract/scripts/test_materialize_remaining_identity_decisions_1939_v50.py`
- `.claude/skills/daa-extract/scripts/test_materialize_remaining_source_personas_1939_v50.py`
- `.claude/skills/daa-extract/scripts/test_materialize_source_personas_1939_v50.py`
- `.claude/skills/daa-extract/scripts/test_normalize_narrative_1939_v50.py`
- `.claude/skills/daa-extract/scripts/test_omnoegl_lokator.py`
- `.claude/skills/daa-extract/scripts/test_ordinals.py`
- `.claude/skills/daa-extract/scripts/test_perturbation.py`
- `.claude/skills/daa-extract/scripts/test_prepare_coverage_1939.py`
- `.claude/skills/daa-extract/scripts/test_prepare_dual_rendition_evidence_1939.py`
- `.claude/skills/daa-extract/scripts/test_prepare_reimport_1939_v50.py`
- `.claude/skills/daa-extract/scripts/test_prepare_review_queue_1939.py`
- `.claude/skills/daa-extract/scripts/test_prepare_source_record_review.py`
- `.claude/skills/daa-extract/scripts/test_preview_narrative_publication_1939_v50.R`
- `.claude/skills/daa-extract/scripts/test_preview_reimport_1939_v50.R`
- `.claude/skills/daa-extract/scripts/test_profile_identity_review_1939_v50.R`
- `.claude/skills/daa-extract/scripts/test_profile_provenance_review_1939_v50.R`
- `.claude/skills/daa-extract/scripts/test_project_evidence.R`
- `.claude/skills/daa-extract/scripts/test_reconcile_source_records_1939.py`
- `.claude/skills/daa-extract/scripts/test_rendition_occurrences_1939.py`
- `.claude/skills/daa-extract/scripts/test_review_choices_1939.py`
- `.claude/skills/daa-extract/scripts/test_review_queue_1939.py`
- `.claude/skills/daa-extract/scripts/test_segment.py`
- `.claude/skills/daa-extract/scripts/test_segment_1939.py`
- `.claude/skills/daa-extract/scripts/test_segment_slaegtled.py`
- `.claude/skills/daa-extract/scripts/test_source_persona.py`
- `.claude/skills/daa-extract/scripts/test_source_record_ledger.py`
- `tests/integration/test-1939-v50-c3-apply.R`
- `tests/integration/test-1939-v50-c3-identity-concurrency.R`
- `tests/integration/test-1939-v50-c3-identity-delete-lock-order.R`
- `tests/integration/test-1939-v50-c3-identity-delete-protocol.R`
- `tests/integration/test-1939-v50-c3-identity-mvcc.R`
- `tests/integration/test-1939-v50-c3-post-load-lock-order.R`
- `tests/integration/test-1939-v50-c3-writer-lock-order.R`
- `tests/integration/test-reimport-writer.R`
- `tests/sql/fixtures/upgrade-2bi-rebind.sql`
- `tests/sql/inspect-1939-v50-c3-external-acl.sql`
- `tests/sql/inspect-1939-v50-c3-identity-deploy.sql`
- `tests/sql/test-1939-v50-c3-identity-deploy-contract.sql`
- `tests/sql/test-1939-v50-c3-identity-invariants.sql`
- `tests/sql/test-1939-v50-c3-identity-sequence-acl.sql`
- `tests/sql/test-1939-v50-c3-identity-sequence-drift.sql`
- `tests/sql/test-1939-v50-c3-identity-sequence-monotonic.sql`
- `tests/sql/test-244-upgrade.sh`
- `tests/sql/test-2bii-upgrade.sh`
- `tests/sql/test-content-uuid.sql`
- `tests/sql/test-relation-disposition.sql`
- `tests/sql/test-relation-person-create-v3.sql`
- `tests/sql/test-relation-persona-v3.sql`

### E. Python-tests uden for CI, kørt lokalt i den rene eksport (71)

- FEJL    test_build_c3_html_review_1939_v50.py | 9 failed, 86 passed in 1.30s
- FEJL    test_convert_c3_decisions_1939_v50.py | 2 failed, 62 passed in 1.08s
- INGEN   test_evidenspas_v2.py | 1 skipped in 0.07s
- (68 øvrige: grønne)

### F. Kandidater til død kode (ikke-test-filer uden reference fra kode/CI; tal = referencer fra docs)

- `.claude/skills/daa-extract/scripts/apply_d2_spouses_1939_v50.R` (146 l, docs-ref 2)
- `.claude/skills/daa-extract/scripts/apply_name_completion.R` (28 l, docs-ref 2)
- `.claude/skills/daa-extract/scripts/apply_reimport.R` (25 l, docs-ref 10)
- `.claude/skills/daa-extract/scripts/check_graenseflade_export.py` (205 l, docs-ref 3)
- `.claude/skills/daa-extract/scripts/export_c0_followup_selection_1939_v50.R` (67 l, docs-ref 1)
- `.claude/skills/daa-extract/scripts/export_c0_narrative_state_1939_v50.R` (88 l, docs-ref 2)
- `.claude/skills/daa-extract/scripts/export_d1_staged_selection_1939_v50.R` (170 l, docs-ref 2)
- `.claude/skills/daa-extract/scripts/export_d2_spouse_selection_1939_v50.R` (129 l, docs-ref 2)
- `.claude/skills/daa-extract/scripts/export_legacy_migration_candidates.R` (54 l, docs-ref 5)
- `.claude/skills/daa-extract/scripts/export_narrative_record_cutover.R` (51 l, docs-ref 6)
- `.claude/skills/daa-extract/scripts/export_reimport_preview.R` (57 l, docs-ref 7)
- `.claude/skills/daa-extract/scripts/fix_150_fingeraftryk.sql` (30 l, docs-ref 2)
- `.claude/skills/daa-extract/scripts/fix_240_ddl151_fingeraftryk.sql` (9 l, docs-ref 1)
- `.claude/skills/daa-extract/scripts/fix_240_maal.sql` (65 l, docs-ref 2)
- `.claude/skills/daa-extract/scripts/fix_248_a_fingeraftryk.sql` (17 l, docs-ref 3)
- `.claude/skills/daa-extract/scripts/fix_boern_multi_union.R` (185 l, docs-ref 3)
- `.claude/skills/daa-extract/scripts/fix_go2_dublet.sql` (108 l, docs-ref 3)
- `.claude/skills/daa-extract/scripts/fix_go2_dublet_maal.sql` (34 l, docs-ref 0)
- `.claude/skills/daa-extract/scripts/preview_reimport_1939_v50.R` (86 l, docs-ref 5)
- `.claude/skills/daa-extract/scripts/replace_dryrun.R` (173 l, docs-ref 2)
- `.claude/skills/daa-extract/scripts/reverse_reimport_legacy_migration.R` (20 l, docs-ref 4)
- `.claude/skills/daa-extract/scripts/run_evidence_43a_rehearsal.py` (211 l, docs-ref 1)
- `.claude/skills/daa-extract/scripts/transfer_5ab_step_candidates.sql` (31 l, docs-ref 2)
- `.claude/skills/daa-extract/scripts/transfer_5ab_step_control.sql` (44 l, docs-ref 2)
- `.claude/skills/daa-extract/scripts/transfer_5ab_step_corroborate.sql` (51 l, docs-ref 2)
- `.claude/skills/daa-extract/scripts/transfer_5ab_step_disposition.sql` (55 l, docs-ref 2)
- `.claude/skills/daa-extract/scripts/transfer_5ab_step_reject.sql` (64 l, docs-ref 2)
- `.claude/skills/daa-haendelser/scripts/export_narratives.R` (60 l, docs-ref 3)
- `.claude/skills/daa-presens/scripts/segment_presens.py` (88 l, docs-ref 2)
- `.claude/skills/daa-presens/scripts/validate_presens.py` (107 l, docs-ref 2)
- `R/geo-enrich/03-geocode.R` (67 l, docs-ref 3)
- `R/geo-enrich/04-person-corroboration.R` (79 l, docs-ref 0)
- `R/tng-qa/05b-enrich-queue.R` (59 l, docs-ref 1)
- `R/tng-qa/06-compare.R` (187 l, docs-ref 6)
- `db-rollback-fase2.sql` (157 l, docs-ref 2)
- `db-rollback-foraeldrefamilie.sql` (104 l, docs-ref 2)
- `db-verify-media.sql` (575 l, docs-ref 14)
- `tests/sql/inspect-1939-v50-c3-external-acl.sql` (53 l, docs-ref 0)
