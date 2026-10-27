# Systemkort: dataarbejdet i Danmarks Adels Aarbog

> **Note fra hovedsessionen:** Eksporten er taget før docs-PR #271 (5c-1 i prod 2026-10-27: `database-current-state.md` §13, changelog, `status.md` → `produktionsverificeret`). Kortets »forældet«-bemærkninger om 5c-1 skyldes det tidspunkt og er ikke et fund.

Kortlægning uden vurdering. Genereret fra eksport-træet `scratchpad/eksport` (dato-snapshot: branch `docs/review-trin-1-5`, HEAD `37a7d408`). Alle linjenumre er fra dette eksport-træ.

**Læsevejledning.** Kodefiler er placeret ved navnemønster (se "Forældreløse" for usikre placeringer); en fil står under ÉN enhed. DB-objekter: `s:` = første `CREATE` i `schema.sql`, `m:` = første `CREATE` i `db-migrations.sql` (`-` = ikke fundet som CREATE-linje; kan være oprettet i DO-blok/ALTER). Testfiler har CI-kode i `{..}`: P=python-jobbet, R=r (testthat), N=node, E=evidence-promotion-db, I=interpretation-proposal-db, W=writer-1939-v50-db, C=narrative-record-contract-db, `-`=INGEN CI-kobling. CI kører kun på PR/`workflow_dispatch`. Alle script-stier er `.claude/skills/daa-extract/scripts/` medmindre andet er angivet (daa-haendelser/daa-presens har egne mapper).

**Roadmap (docs/evidensbaseret-genimport/roadmap.md "Styrende rækkefølge")**: 1 #152 -> 2 #153 -> 3 #149 -> 4 #147/#148 -> 5 #150/#151 -> 6 ende-til-ende på begge udgaver -> 7 tredje årbog. Modenhedstilstande: `specificeret` | `isoleret implementeret` | `integreret ende-til-ende` | `produktionsverificeret`.

**Fælles kilder pr. enhed:** `docs/evidensbaseret-genimport/status.md` (modenhed), `docs/database-current-state.md` (prod), `docs/decisions.md` (beslutninger), `docs/changelog.md`. CI-jobs (`.github/workflows/ci.yml`): node :40, r :95, python :124, evidence-promotion-db :144, interpretation-proposal-db :235, writer-1939-v50-db :281, narrative-record-contract-db :536.

## S1 Datamodel og invarianter (forarbejde)

1. **Mål:** De ni invarianter (evidens: påstand/konklusion, generisk relation, alt-er-faktum, envejs-cache, fuzzy datoer, narrativ vs. struktureret, konfidens, GDPR/RLS, kontrolleret vokabular) og skemaet, der bærer dem. `schema.sql` = source of truth; `db-migrations.sql` idempotent mod prod; `db-verify.sql` asserts; `db-rls.sql` politikker.
2. **Specs (0) og planer (0):** (ingen) | planer: (ingen)
3. **Kode (11):**
   schema.sql, db-migrations.sql, db-rls.sql, db-verify.sql, db-verify-media.sql, db-backfill-foraeldrefamilie.sql, db-rollback-fase2.sql, db-rollback-fase3.sql,
   db-rollback-foraeldrefamilie.sql, supabase_load.R, run-tests.R
4. **Databaseobjekter:** `person` (s:125 m:-); `fact` (s:3264 m:-); `relation` (s:3278 m:-); `assertion` (s:3298 m:-); `conclusion` (s:3313 m:-); `family` (s:3240 m:-); `family_member` (s:3245 m:-); `narrative` (s:3351 m:-); `vocab` (s:18 m:17744); `suggestion` (s:3214 m:130); `change_set` (s:8176 m:955); `change_event` (s:8292 m:969); `regen_person_visning` (s:5604 m:147); `enforce_samme_som_invariants` (s:6684 m:1387); `log_change` (s:8353 m:1034); `red_set_konklusion` (s:5865 m:346); `red_relation` (s:6320 m:526); `red_slet_person` (s:6189 m:465); `begin_change_set` (s:8321 m:1000); `red_fortryd_change_set` (s:8468 m:1150)
5. **Tests (0):**
   (ingen)
6. **Bevis:** (ingen *-bevis/*-rehearsal-fil)
7. **Runbooks:** (ingen)
8. **Prod-status/modenhed:** Prod-snapshot i `docs/database-current-state.md` §1 er et snapshot dateret 2026-07-20 (tal opdateret ad hoc til 2026-08-20); ingen modenhedstilstand i status.md (dækker kun genimport). Se også `datamodel-oversigt.md`, `CLAUDE.md` (invariant-listen), `docs/decisions.md`.
9. **Åbne issues:** #132 (fuldtekstsøgning + schema.sql-drift fts), #164 (Supabase-advisors/RPC-ACL-drift)
10. **Noter:** Filer: schema.sql (18.199 l.), db-migrations.sql (26.314 l.), db-rls.sql, db-verify.sql, db-verify-media.sql, db-rollback-fase2/3.sql, db-backfill-foraeldrefamilie.sql, db-rollback-foraeldrefamilie.sql, db-migrations-c3-identity.sql (se S3), supabase_load.R (HISTORISK - bruges aldrig mod prod), run-tests.R (kører kun tests/testthat).

## S2 Første importer: stamtavle, præsensliste, hændelser (forarbejde)

1. **Mål:** Skills `daa-extract` (stamtavle-PDF -> segmentering -> LLM-udtræk -> validering -> R-load), `daa-presens` (præsensliste), `daa-haendelser` (daterede hændelser fra bevarede narrativer til `haendelse`).
2. **Specs (7) og planer (8):** 2026-06-18-auto-eskalering-design.md, 2026-06-18-eager-udtraek-data-strategi-design.md, 2026-07-15-praesensliste-tidsserie-design.md, 2026-07-18-levende-feed-fase1-design.md, 2026-07-22-praesensliste-visning-design.md, 2026-07-24-praesens-navn-foldud-design.md, 2026-07-24-praesensliste-redesign-design.md | planer: 2026-06-18-auto-eskalering.md, 2026-06-18-eager-udtraek-parse-styrkelse.md, 2026-07-02-daa-reimport-fire-etaper.md, 2026-07-18-levende-feed-fase1.md, 2026-07-22-praesensliste-visning.md, 2026-07-24-praesens-navn-foldud.md, 2026-07-24-praesensliste-redesign.md, 2026-07-24-praesensliste-vaaben-data-runbook.md
3. **Kode (19):**
   backfill_slaegtled.R, escalate_merge.py, extract_text.sh, fix_boern_multi_union.R, load_daa.R, load_helpers.R, post_load_fixup.R, replace_dryrun.R, segment.py,
   validate.py, escalate_haendelser.py, export_narratives.R, load_haendelser.R, load_haendelser_helpers.R, validate_haendelser.py, load_presens.R, segment_presens.py,
   validate_presens.py, update-2018-narratives.R
4. **Databaseobjekter:** `haendelse` (s:5468 m:2748); `story` (s:5512 m:3056); `extraction_run` (s:437 m:5438); `person_external_id` (s:141 m:-); `import_korrektion` (s:158 m:3585); `red_upsert_narrativ` (s:6291 m:506); `red_opret_story` (s:6047 m:3113)
5. **Tests (10):**
   test_escalate_merge.py{-}, test_lokator.py{-}, test_segment.py{-}, test_segment_slaegtled.py{-}, test_validate.py{-}, test_escalate_haendelser.py{-},
   test_validate_haendelser.py{-}, test-haendelse-merge.R{R}, test-load-daa.R{R}, test-update-2018-narratives.R{R}
6. **Bevis:** (ingen *-bevis/*-rehearsal-fil)
7. **Runbooks:** (ingen)
8. **Prod-status/modenhed:** Ingen modenhedstilstand i status.md. Historik: `docs/daa-extraction-archetype.md`, `docs/daa-presens-archetype.md`, `docs/levende-feed-fase2-3-runbook.md`; `.claude/skills/daa-*/SKILL.md`. Hændelsesudtræk er (pr. memory/#130) ikke kørt.
9. **Åbne issues:** #130 (kør hændelses-LLM-passet)
10. **Noter:** Load-laget er `load_daa.R`/`load_helpers.R` (append/staged). `post_load_fixup.R`, `backfill_slaegtled.R`, `fix_boern_multi_union.R`, `replace_dryrun.R` er ældre fixups. 5c fryser `backfill_slaegtled.R`/`post_load_fixup.R` som skrivevej (Task 6 LegacyBackfillFreeze).

## S3 1939-sporet: C0-C3 og v50 production-writer (forarbejde)

1. **Mål:** 1939-stamtavlens menneskeverificerede segmentering, source record/occurrence/anker-proveniens, v50 guarded production-writer, navnefuldførelse, narrativerstatning (fase A/B), C0 recordkobling + efterkørsel, D1 publicering, D2 ægtefæller, C3 identitet + recordplacering + atomisk apply/reversal.
2. **Specs (36) og planer (45):** 2026-08-02-evidensbaseret-genimport-og-multislaegt-design.md, 2026-08-03-evidens-promotion-kontrakt-design.md, 2026-08-04-1939-ankerbaseret-rekonstruktion-design.md, 2026-08-04-1939-duplicate-target-integrity-design.md, 2026-08-04-1939-raw-bridge-integrity-design.md, 2026-08-04-source-record-ledger-design.md, 2026-08-05-1939-dual-rendition-evidence-design.md, 2026-08-05-1939-exception-review-queue-design.md, 2026-08-05-1939-human-review-workbook-design.md, 2026-08-05-1939-review-decision-integrity-design.md, 2026-08-05-evidensbaseret-genimport-reviewfund-design.md, 2026-08-06-1939-human-anchor-adapter-design.md, 2026-08-08-graensekontrol-efter-matchning-design.md, 2026-08-10-1939-hulgennemgang-design.md, 2026-08-16-1939-partial-overlap-reconciliation-design.md, 2026-08-16-1939-reconciliation-duplicate-retirement-design.md, 2026-08-16-1939-reconciliation-text-anchor-acceptance-design.md, 2026-08-16-1939-structural-context-records-design.md, 2026-08-17-1939-genuinely-new-source-record-design.md, 2026-08-17-1939-legacy-anchor-repair-design.md, 2026-08-17-1939-ownerless-nonperson-classification-design.md, 2026-08-17-1939-spanless-baseline-adoption-design.md, 2026-08-17-1939-v50-death-year-identity-review-design.md, 2026-08-17-1939-v50-identity-review-design.md, 2026-08-17-1939-v50-import-preview-design.md, 2026-08-17-1939-v50-production-writer-design.md, 2026-08-17-1939-v50-remaining-identity-review-design.md, 2026-08-17-1939-v50-source-persona-materialization-design.md, 2026-08-18-1939-v50-name-completion-design.md, 2026-08-19-1939-v50-fase-c0-record-kobling-design.md, 2026-08-19-1939-v50-fase-d1-publicering-design.md, 2026-08-20-1939-v50-fase-d2-aegtefaeller-design.md, 2026-08-21-1939-v50-fase-c0-efterkoersel-design.md, 2026-08-21-1939-v50-fase-c3-identitet-og-recordplacering-design.md, 2026-08-21-1939-v50-fase-c3-lokal-html-review-design.md, 2026-08-22-1939-v50-fase-c3-apply-design.md | planer: 2026-08-02-evidensbaseret-genimport-og-multislaegt.md, 2026-08-03-evidens-promotion-kontrakt.md, 2026-08-03-offentlige-kilderecord-versioner.md, 2026-08-04-1939-ankerbaseret-rekonstruktion.md, 2026-08-04-1939-duplicate-target-integrity.md, 2026-08-04-1939-raw-bridge-integrity.md, 2026-08-04-source-record-ledger.md, 2026-08-05-1939-dual-rendition-evidence.md, 2026-08-05-1939-exception-review-queue.md, 2026-08-05-1939-review-decision-integrity.md, 2026-08-05-evidensbinding-og-1939-roundtrip.md, 2026-08-05-kildeversioner-same-som-paritet.md, 2026-08-05-placement-identitet-promotion-lineage.md, 2026-08-06-1939-human-anchor-adapter.md, 2026-08-06-1939-review-readable-sources-sidebar.md, 2026-08-08-graensekontrol-fase-1.md, 2026-08-09-graenseflade-spec.md, 2026-08-10-graenseflade-finpudsning.md, 2026-08-10-graenseflade-overdragelse.md, 2026-08-16-1939-reconciliation-duplicate-retirement.md, 2026-08-16-1939-reconciliation-finish.md, 2026-08-16-1939-reconciliation-text-anchor-acceptance.md, 2026-08-16-1939-structural-context-records.md, 2026-08-17-1939-genuinely-new-source-record.md, 2026-08-17-1939-ownerless-nonperson-classification.md, 2026-08-17-1939-spanless-baseline-adoption.md, 2026-08-17-1939-v50-death-year-identity-review.md, 2026-08-17-1939-v50-identity-review.md, 2026-08-17-1939-v50-import-preview.md, 2026-08-17-1939-v50-remaining-identity-review.md, 2026-08-17-1939-v50-source-persona-materialization.md, 2026-08-18-1939-v50-fase-a-kilderegnskab.md, 2026-08-18-1939-v50-fase-b-narrativ-erstatning.md, 2026-08-18-1939-v50-name-completion.md, 2026-08-18-1939-v50-production-writer.md, 2026-08-18-1939-v50-resten-af-genimporten.md, 2026-08-19-1939-v50-fase-c0-record-kobling.md, 2026-08-19-1939-v50-fase-d1-publicering.md, 2026-08-20-1939-v50-fase-d2-aegtefaeller.md, 2026-08-21-1939-v50-fase-c0-efterkoersel.md, 2026-08-21-1939-v50-fase-c3-identitet-og-recordplacering.md, 2026-08-21-1939-v50-fase-c3-lokal-html-review.md, 2026-08-21-c0-efterkoersel-overdragelse.md, 2026-08-22-1939-v50-c3-atomisk-apply.md, 2026-08-22-1939-v50-c3-identitetsinvarianter.md
3. **Kode (110):**
   afstem_lokator.py, afstem_v2.py, amend_structural_context_1939.py, anchor_review_choices_1939.py, apply_c0_followup_1939_v50.R, apply_c0_followup_1939_v50_helpers.R,
   apply_c3_1939_v50.R, apply_c3_1939_v50_helpers.R, apply_d2_spouses_1939_v50.R, apply_d2_spouses_1939_v50_helpers.R, apply_name_completion_1939_v50.R,
   apply_name_completion_1939_v50_helpers.R, apply_narrative_replacement_1939_v50.R, apply_narrative_replacement_1939_v50_helpers.R, apply_phase_a_1939_v50.R,
   apply_phase_a_1939_v50_helpers.R, apply_reconciliation_decisions_1939.py, apply_reimport_1939_v50.R, apply_reimport_1939_v50_helpers.R, audit_1939.py,
   boundary_review_1939_ui.js, boundary_signals_1939.py, boundary_spans_1939.py, boundary_text_1939_ui.js, build_1939_v2.py, build_c0_followup_flags_1939_v50.py,
   build_c0_followup_manifest_1939_v50.py, build_c0_followup_review_1939_v50.py, build_c0_record_linkage_1939_v50.py, build_c3_apply_candidate_1939_v50.py,
   build_c3_html_review_1939_v50.py, build_c3_review_1939_v50.py, build_c3_selection_1939_v50.py, build_death_year_identity_review_1939_v50.py,
   build_identity_review_1939_v50.py, build_mapped_identity_review_1939_v50.py, build_name_completion_manifest_1939_v50.py,
   build_narrative_replacement_manifest_1939_v50.py, build_phase_a_anchor_manifest_1939_v50.py, build_production_write_manifest_1939_v50.py,
   build_provenance_review_1939_v50.py, build_remaining_identity_review_1939_v50.py, c3_export_shared_1939_v50_helpers.R, c3_html_review_test_fixtures.py,
   check_graenseflade_export.py, convert_1939_stamtavle.py, convert_c0_followup_decisions_1939_v50.py, convert_c0_linkage_decisions_1939_v50.py,
   convert_c3_apply_approvals_1939_v50.py, convert_c3_decisions_1939_v50.py, convert_d1_publication_decisions_1939_v50.py, convert_narrative_decisions_1939_v50.py,
   coverage_1939.py, detect_boundary_defects_1939.py, dual_rendition_evidence_1939.py, efterudtraek_1939.py, evidenspas_v2.py, export_c0_followup_selection_1939_v50.R,
   export_c0_followup_selection_1939_v50_helpers.R, export_c0_narrative_state_1939_v50.R, export_c0_narrative_state_1939_v50_helpers.R,
   export_c3_apply_preview_1939_v50.R, export_c3_apply_preview_1939_v50_helpers.R, export_c3_current_state_1939_v50.R, export_c3_current_state_1939_v50_helpers.R,
   export_d1_staged_selection_1939_v50.R, export_d1_staged_selection_1939_v50_helpers.R, export_d2_spouse_selection_1939_v50.R,
   export_d2_spouse_selection_1939_v50_helpers.R, export_narrative_old_sha_1939_v50.R, export_narrative_old_sha_1939_v50_helpers.R, facit_1939.py,
   finalize_c3_apply_manifest_1939_v50.py, human_review_1939_ui.js, identitetsregister.py, make_boundary_review_1939.py, make_boundary_text_1939.py,
   make_human_review_1939.py, match_c0_records_1939_v50.py, materialize_graenseflade_1939.py, materialize_identity_decisions_1939_v50.py,
   materialize_provenance_decisions_1939_v50.py, materialize_remaining_identity_decisions_1939_v50.py, materialize_remaining_source_personas_1939_v50.py,
   materialize_source_personas_1939_v50.py, normalize_narrative_1939_v50.py, omnoegl_lokator.py, prepare_coverage_1939.py, prepare_dual_rendition_evidence_1939.py,
   prepare_reimport_1939_v50.py, prepare_review_queue_1939.py, prepare_source_record_review.py, preview_narrative_publication_1939_v50.R,
   preview_narrative_publication_1939_v50_helpers.R, preview_reimport_1939_v50.R, preview_reimport_1939_v50_helpers.R, profile_identity_review_1939_v50.R,
   profile_identity_review_1939_v50_helpers.R, profile_provenance_review_1939_v50.R, profile_provenance_review_1939_v50_helpers.R, reconcile_source_records_1939.py,
   rendition_occurrences_1939.py, review_choices_1939.py, review_queue_1939.py, review_ui_shared.js, segment_1939.py, source_record_ledger.py,
   verify_boundary_text_browser.mjs, update-1939-narratives.R, db-migrations-c3-identity.sql
4. **Databaseobjekter:** `source_record` (s:467 m:5462); `source_record_occurrence` (s:481 m:5472); `source_record_anchor_event` (s:499 m:5489); `source_observation` (s:548 m:5521); `source_mention` (s:797 m:5554); `source_persona` (s:808 m:5564); `narrative_publication_event` (s:11724 m:11291); `narrative_legacy_publication` (s:11699 m:11266); `identity_mutation_generation` (s:6494 m:4935); `red_authorize_1939_v50_reimport` (s:5236 m:7932); `red_apply_1939_v50_source_evidence` (s:5272 m:7961); `red_apply_1939_v50_person_create` (s:5283 m:7962); `red_apply_1939_v50_canonical_delta` (s:5295 m:7969); `red_apply_1939_v50_name_completion` (s:5381 m:8191); `red_activate_1939_v50_batch` (s:5336 m:7975); `red_reverse_1939_v50_reimport` (s:5320 m:7973); `private.decide_source_persona_identity` (s:8833 m:6487); `decide_source_persona_identity` (s:8833 m:6487); `guard_identity_mutation_snapshot` (s:6508 m:4944); `lock_identity_people` (s:6588 m:4992)
5. **Tests (120):**
   test_afstem_lokator.py{-}, test_afstem_v2.py{-}, test_amend_structural_context_1939.py{-}, test_anchor_review_choices_1939.py{-}, test_apply_c0_followup_1939_v50.R{-},
   test_apply_c3_1939_v50.R{-}, test_apply_d2_spouses_1939_v50.R{-}, test_apply_name_completion_1939_v50.R{-}, test_apply_narrative_replacement_1939_v50.R{-},
   test_apply_phase_a_1939_v50.R{-}, test_apply_reconciliation_decisions_1939.py{-}, test_apply_reimport_1939_v50.R{-}, test_audit_1939.py{-},
   test_boundary_signals_1939.py{-}, test_boundary_spans_1939.py{-}, test_build_1939_v2.py{-}, test_build_c0_followup_flags_1939_v50.py{-},
   test_build_c0_followup_manifest_1939_v50.py{-}, test_build_c0_record_linkage_1939_v50.py{-}, test_build_c3_apply_candidate_1939_v50.py{-},
   test_build_c3_html_review_1939_v50.py{-}, test_build_c3_review_1939_v50.py{-}, test_build_c3_selection_1939_v50.py{-},
   test_build_death_year_identity_review_1939_v50.py{-}, test_build_identity_review_1939_v50.py{-}, test_build_mapped_identity_review_1939_v50.py{-},
   test_build_name_completion_manifest_1939_v50.py{-}, test_build_narrative_replacement_manifest_1939_v50.py{-}, test_build_phase_a_anchor_manifest_1939_v50.py{-},
   test_build_production_write_manifest_1939_v50.py{-}, test_build_provenance_review_1939_v50.py{-}, test_build_remaining_identity_review_1939_v50.py{-},
   test_c0_followup_review_1939_v50.py{-}, test_c3_html_review_browser_1939_v50.mjs{-}, test_convert_1939.py{-}, test_convert_c0_linkage_decisions_1939_v50.py{-},
   test_convert_c3_apply_approvals_1939_v50.py{-}, test_convert_c3_decisions_1939_v50.py{-}, test_convert_d1_publication_decisions_1939_v50.py{-},
   test_convert_narrative_decisions_1939_v50.py{-}, test_coverage_1939.py{-}, test_detect_boundary_defects_1939.py{-}, test_dual_rendition_evidence_1939.py{-},
   test_efterudtraek_1939.py{-}, test_evidenspas_v2.py{-}, test_export_c0_followup_selection_1939_v50.R{-}, test_export_c0_narrative_state_1939_v50.R{-},
   test_export_c3_apply_preview_1939_v50.R{-}, test_export_c3_current_state_1939_v50.R{-}, test_export_d1_staged_selection_1939_v50.R{-},
   test_export_d2_spouse_selection_1939_v50.R{-}, test_export_narrative_old_sha_1939_v50.R{-}, test_finalize_c3_apply_manifest_1939_v50.py{-},
   test_identitetsregister.py{-}, test_make_boundary_review_1939.py{-}, test_make_boundary_text_1939.py{-}, test_make_human_review_1939.py{-},
   test_match_c0_records_1939_v50.py{-}, test_materialize_graenseflade_1939.py{-}, test_materialize_identity_decisions_1939_v50.py{-},
   test_materialize_provenance_decisions_1939_v50.py{-}, test_materialize_remaining_identity_decisions_1939_v50.py{-},
   test_materialize_remaining_source_personas_1939_v50.py{-}, test_materialize_source_personas_1939_v50.py{-}, test_normalize_narrative_1939_v50.py{-},
   test_omnoegl_lokator.py{-}, test_prepare_coverage_1939.py{-}, test_prepare_dual_rendition_evidence_1939.py{-}, test_prepare_reimport_1939_v50.py{-},
   test_prepare_review_queue_1939.py{-}, test_prepare_source_record_review.py{-}, test_preview_narrative_publication_1939_v50.R{-}, test_preview_reimport_1939_v50.R{-},
   test_profile_identity_review_1939_v50.R{-}, test_profile_provenance_review_1939_v50.R{-}, test_reconcile_source_records_1939.py{-},
   test_rendition_occurrences_1939.py{-}, test_review_choices_1939.py{-}, test_review_queue_1939.py{-}, test_segment_1939.py{-}, test_source_record_ledger.py{-},
   1939-v50-writer-bootstrap.sql{W}, inspect-1939-v50-c3-external-acl.sql{-}, inspect-1939-v50-c3-identity-deploy.sql{-}, test-1939-v50-c3-apply.sql{W},
   test-1939-v50-c3-identity-deploy-contract.sql{-}, test-1939-v50-c3-identity-invariants.sql{-}, test-1939-v50-c3-identity-sequence-acl.sql{-},
   test-1939-v50-c3-identity-sequence-drift.sql{-}, test-1939-v50-c3-identity-sequence-monotonic.sql{-}, test-1939-v50-name-completion.sql{W},
   test-1939-v50-production-writer.sql{W}, test-1939-v50-c3-apply.R{W}, test-1939-v50-c3-identity-concurrency.R{-}, test-1939-v50-c3-identity-delete-lock-order.R{-},
   test-1939-v50-c3-identity-delete-protocol.R{-}, test-1939-v50-c3-identity-mvcc.R{-}, test-1939-v50-c3-post-load-lock-order.R{-},
   test-1939-v50-c3-writer-lock-order.R{-}, test-1939-v50-name-completion.R{W}, test-1939-v50-production-writer.R{W}, test-apply-c0-followup-1939-v50.R{R},
   test-apply-c3-1939-v50.R{R}, test-apply-d2-spouses-1939-v50.R{R}, test-apply-name-completion-1939-v50.R{R}, test-apply-narrative-replacement-1939-v50.R{R},
   test-apply-phase-a-1939-v50.R{R}, test-apply-reimport-1939-v50.R{R}, test-export-c0-followup-selection-1939-v50.R{R}, test-export-c0-narrative-state-1939-v50.R{R},
   test-export-c3-apply-preview-1939-v50.R{R}, test-export-c3-current-state-1939-v50.R{R}, test-export-d1-staged-selection-1939-v50.R{R},
   test-export-d2-spouse-selection-1939-v50.R{R}, test-export-narrative-old-sha-1939-v50.R{R}, test-preview-narrative-publication-1939-v50.R{R},
   test-preview-reimport-1939-v50.R{R}, test-profile-identity-review-1939-v50.R{R}, test-profile-provenance-review-1939-v50.R{R}, test-update-1939-narratives.R{R}
6. **Bevis:** c3-production-apply-2026-08-29.md, c3-task9-rehearsal-2026-08-29.md
7. **Runbooks:** (ingen)
8. **Prod-status/modenhed:** C3 (1939 source/rendition og recordproveniens): `produktionsverificeret`; 1939 narrativpublicering og kildebinding: `produktionsverificeret`; C3 atomisk apply: `produktionsverificeret`; C3 reversal: `integreret ende-til-ende` (ikke udført i prod). Tilføjet: 1939-placering (542 af 576 external-id-rækker har pladsholder `linje='1939'`) hører til trin 6.
9. **Åbne issues:** #158 (1939 v50 lukning: C3-apply, 16 [NY], 7 staged, grænsefejl, fortryd af bindinger), #159 (bind C0f-receipt til flags_sha256), #160 (16 [NY]), #161 (7 staged), #162 (narrative grænsekandidater), #163 (16 tomme unioner), #164 (advisors/RPC-ACL)
10. **Noter:** Afgrænsning: filer med `1939`/`c3` i navnet er placeret her uanset hvilken roadmap-funktion de senere genbruges af (fx apply_reimport_1939_v50 = den specialiserede forløber for #153; materialize_*_source_personas_1939_v50 = forløber for 5a). `db-migrations-c3-identity.sql` er selvstændig SQL-fil for C3-identitetslaget. Parkeret efter roadmap: `[NY]`, C1, C2, spor H/M, nye 1939-undtagelsesfaser.

## S4 App-relevante DB-lag (forarbejde): redaktions-RPC, versionering, medier, feed, OCR

1. **Mål:** DB-funktioner/tabeller som web/mobile læser og skriver gennem: `red_*` redaktions-RPC'er med change_set-versionering/fortryd, medie-metadata og -hygiejne, levende feed/story, OCR-kvalitetsark, søgning, samme_som-collapse, bogmærker/profiler.
2. **Specs (34) og planer (35):** 2026-06-24-spor-vej-til-mig-design.md, 2026-06-26-redaktion-skrive-model-auth-design.md, 2026-06-27-redaktion-ui-kerne-skive-design.md, 2026-06-28-plan2a-navigation-person-adgang-design.md, 2026-06-28-plan2b-editor-dybde-design.md, 2026-06-28-plan2c1-entitetslister-design.md, 2026-06-28-plan2c2a-sektion-relationer-design.md, 2026-06-29-plan2c2b-familie-redigering-design.md, 2026-06-29-redaktion-opret-ny-entitet-design.md, 2026-06-30-versionering-og-hyperlinks-design.md, 2026-07-02-redaktionel-samme-som-linking-design.md, 2026-07-02-samme-som-collapse-design.md, 2026-07-03-flere-narrativer-per-person-design.md, 2026-07-03-kolonner-aner-efterkommere-design.md, 2026-07-03-udledt-slaegtsnavn-design.md, 2026-07-03-web-v3-slice1-laesning-bogmaerker-design.md, 2026-07-05-folgesvend-v3-feed-drawer-bogmaerker-design.md, 2026-07-05-generations-browser-v2-design.md, 2026-07-05-generations-reparation-design.md, 2026-07-06-konto-bogmaerker-design.md, 2026-07-13-packages-core-delt-logik-design.md, 2026-07-15-family-member-konkurrerende-relationer-design.md, 2026-07-15-tvaers-udgave-identifikation-design.md, 2026-07-18-levende-feed-fase2-design.md, 2026-07-19-levende-feed-fase3-design.md, 2026-07-19-mediehaandtering-fase1-filside-design.md, 2026-07-19-mediehaandtering-fase2-bibliotek-design.md, 2026-07-20-mediehaandtering-fase3-hygiejne-design.md, 2026-07-21-mediehaandtering-fase4-identitet-design.md, 2026-07-26-levende-feed-sociale-personposter-design.md, 2026-07-26-person-ocr-kvalitetsark-design.md, 2026-07-28-redaktoer-udgavefaner-design.md, 2026-08-01-aegte-links-og-samme-person-design.md, 2026-08-06-medie-metadata-design.md | planer: 2026-06-24-spor-vej-til-mig.md, 2026-06-26-redaktion-skrive-model-auth.md, 2026-06-27-redaktion-ui-kerne-skive.md, 2026-06-28-plan2a-navigation-person-adgang.md, 2026-06-28-plan2b-editor-dybde.md, 2026-06-28-plan2c1-entitetslister.md, 2026-06-28-plan2c2a-sektion-relationer.md, 2026-06-29-plan2c2b-familie-redigering.md, 2026-06-29-redaktion-opret-ny-entitet.md, 2026-06-30-versionering-hyperlinks-app-lag.md, 2026-06-30-versionering-hyperlinks-db-lag.md, 2026-07-02-redaktionel-samme-som-linking.md, 2026-07-02-samme-som-collapse.md, 2026-07-03-flere-narrativer-per-person.md, 2026-07-03-udledt-slaegtsnavn.md, 2026-07-04-mediehaandtering.md, 2026-07-05-billedstoerrelser-artikler-lightbox.md, 2026-07-05-folgesvend-v3-feed-drawer-bogmaerker.md, 2026-07-05-generations-browser-v2.md, 2026-07-05-generations-reparation.md, 2026-07-06-konto-bogmaerker.md, 2026-07-13-packages-core-delt-logik.md, 2026-07-18-en-person-i-soegning-udgave-versioner.md, 2026-07-18-levende-feed-fase2.md, 2026-07-19-levende-feed-fase3.md, 2026-07-19-mediehaandtering-fase1-filside.md, 2026-07-19-mediehaandtering-fase2-bibliotek.md, 2026-07-20-mediehaandtering-fase3-hygiejne.md, 2026-07-20-sammenlign-udgaver-redaktoer-ux.md, 2026-07-22-mediehaandtering-fase4-identitet.md, 2026-07-26-levende-feed-sociale-personposter.md, 2026-07-26-person-ocr-kvalitetsark.md, 2026-07-29-aegtefaelle-forankring.md, 2026-08-01-aegte-links-og-samme-person.md, 2026-08-06-medie-metadata.md
3. **Kode (0):**
   (ingen)
4. **Databaseobjekter:** `red_opret_person` (s:7611 m:849); `red_upsert_fakta` (s:5752 m:298); `red_tilfoej_barn` (s:7145 m:802); `red_flyt_barn` (s:7354 m:1366); `red_tilfoej_partner` (s:7291 m:5365); `red_samme_som` (s:6812 m:1412); `red_match_personer` (s:8685 m:1306); `red_person_grid` (s:199 m:3673); `red_ret_ocr_felt` (s:1970 m:196); `red_ocr_historik` (s:2086 m:250); `red_upload_media` (s:7723 m:1905); `red_udrens_media` (s:8031 m:3465); `red_publicer_udgave` (s:6927 m:2722); `red_suggest` (s:7517 m:551); `hist_for_subjekt` (s:8669 m:1288); `hist_events` (s:8714 m:1335); `public_family_sources` (s:18143 m:21787); `public_person_bio_source_versions_v2` (s:14783 m:15718); `media` (s:66 m:-); `media_variant` (s:100 m:1967); `bookmark` (s:3231 m:2048); `profiles` (s:3206 m:124); `feed_pin` (s:5555 m:3095)
5. **Tests (0):**
   (ingen)
6. **Bevis:** (ingen *-bevis/*-rehearsal-fil)
7. **Runbooks:** 2026-09-20-medie-indkapsling.md, 2026-09-20-medie-rettighedsgate.md, person-ocr-kvalitetsark.md
8. **Prod-status/modenhed:** Ingen modenhedstilstand i status.md (uden for genimport). `docs/database-current-state.md` §3 (kerne, 1939, RLS/GDPR, versionering, medier fase 0-3, OCR-ark, feed) og §7 (union-redigering) er den autoritative prod-beskrivelse.
9. **Åbne issues:** #128 (suggestion-apply læse-/godkend-flade), #131 (geo-enrich til kort-views), #132, #164
10. **Noter:** Web/mobile er UDE af afgrænsning; RPC'er fundet ved grep på `rpc('...')` i web/src, mobile/src, packages (kan misse andre kaldeformer): narrative_record_contract_version, red_person_narrative_records, red_person_narrative_publication_history, public_person_bio_source_versions(_v2), red_source_persona_queue/_detail/_history (5a-webkøen), red_person_grid, red_match_personer, red_ret_ocr_felt, red_ocr_historik, red_udrens_media_preview, red_slet_person_preview, red_registrer_media_variant, red_bekraeft_media_upload, hist_for_subjekt(er), public_family_sources. Medie-runbooks: `2026-09-20-medie-indkapsling`, `2026-09-20-medie-rettighedsgate`.

## S5 Støtte-pipelines og værktøjer (forarbejde)

1. **Mål:** TNG-QA-crosswalk (R/tng-qa), geo-enrich (R/geo-enrich), media-janitor, kalibrering af modeltier, forældrematch og dublet-lister. Sidespor til selve genimporten.
2. **Specs (2) og planer (2):** 2026-06-29-tng-qa-crosswalk-design.md, 2026-07-01-tng-qa-relationel-corroboration-design.md | planer: 2026-06-29-tng-qa-crosswalk.md, 2026-07-01-tng-qa-relationel-corroboration-fase1.md
3. **Kode (31):**
   media-janitor.R, 03-geocode.R, 04-person-corroboration.R, geo_helpers.R, run-geo-enrich.R, .gitkeep, 01-extract-tng.R, 02-pull-ours.R, 03-normalize.R, 04-match.R,
   04b-corroboration.R, 05-review.R, 05b-enrich-queue.R, 05c-review-logic.R, 06-compare.R, 07-report.R, calibrate.R, review-app.R, run-pipeline.R, byg-liste.py,
   foraeldre-daekning.ts, byg-liste.ts, dump-prod.R, effekt.ts, formodet-nye.ts, normaliseret.ts, status.ts, lav-facitark.py, scor.py, uenigheder.py, vaelg-poster.py
4. **Databaseobjekter:** (ingen egne; se øvrige enheder)
5. **Tests (13):**
   helper-source.R{R}, test-compare.R{R}, test-corroboration.R{R}, test-enrich-queue.R{R}, test-extract.R{R}, test-geo-enrich.R{R}, test-match.R{R},
   test-media-janitor.R{R}, test-normalize.R{R}, test-pull.R{R}, test-report.R{R}, test-review-logic.R{R}, test-review.R{R}
6. **Bevis:** (ingen *-bevis/*-rehearsal-fil)
7. **Runbooks:** (ingen)
8. **Prod-status/modenhed:** Ingen modenhedstilstand i status.md. TNG-QA Trin 1-6 "komplet, merged" (memory); geo-enrich ikke kørt (#131).
9. **Åbne issues:** #131 (geo-enrich 6.788 TNG-koordinater)
10. **Noter:** Kodefiler uden SKILL-tilknytning; ikke dækket af CI-jobbet `r`, medmindre testen ligger i tests/testthat (helper-source.R, test-compare/pull/match/... dækker tng-qa).

## Trin 1 (#152): narrativ <-> source record

1. **Mål:** Narrativer knyttes entydigt til konkret source record: editionsneutral record-kontrakt, append-only publication-events, stale-gate, granulær legacy-withdrawal, kontrakt-cutover (version 2).
2. **Specs (1) og planer (2):** 2026-08-29-narrative-source-record-key-design.md | planer: 2026-08-29-narrative-source-record-key-implementation.md, 2026-08-30-narrative-record-key-task-13-correction.md
3. **Kode (7):**
   apply_narrative_record_cutover.R, apply_narrative_record_cutover_helpers.R, build_narrative_record_cutover_review.py, convert_narrative_record_cutover_approvals.py,
   export_narrative_record_cutover.R, export_narrative_record_cutover_helpers.R, verify_narrative_record_cutover_postverify.R
4. **Databaseobjekter:** `narrative_record_publication` (s:3363 m:7834); `narrative_publication_event` (s:11724 m:11291); `narrative_legacy_publication` (s:11699 m:11266); `narrative_record_contract` (s:15053 m:15984); `narrative_record_cutover_receipt` (s:15179 m:16111); `apply_narrative_record_cutover` (s:11980 m:12938); `narrative_publication_state` (s:12685 m:13643); `red_upsert_person_narrative_record` (s:14039 m:14997); `red_publicer_person_narrative_record` (s:14051 m:15009); `red_tilbagetraek_legacy_narrative` (s:14612 m:15552); `red_fortryd_person_narrative_publication_event` (s:14627 m:15567); `person_daa_narrative_publication_allowed` (s:14652 m:15591)
5. **Tests (8):**
   test_build_narrative_record_cutover_review.py{-}, test-narrative-record-contract.sql{C}, test-narrative-record-cutover.sql{C}, test-narrative-record-concurrency.R{C},
   test-apply-narrative-record-cutover.R{R}, test-export-narrative-record-cutover.R{R}, test-narrative-record-source-inventory.R{R},
   test-verify-narrative-record-cutover-postverify.R{R}
6. **Bevis:** narrative-record-key-152-rehearsal.md
7. **Runbooks:** narrative-record-key-cutover.md
8. **Prod-status/modenhed:** `#152 record-nøglede person-narrativer`: `produktionsverificeret` (2026-09-06). Roadmap-trin 1-3 "er `produktionsverificeret` pr. 2026-09-06". Åben blokering: "#152 fortsat blokerer hel-person-sletning for personer med publication-events" (tombstone-/retention-beslutning åben).
9. **Åbne issues:** Ingen åbne (jf. _issues.txt).

## Trin 2 (#153): writer-/batchmekanismer (inkl. #154/#155 evidence-hardening)

1. **Mål:** Permanent, profilbundet reimport-writer (authorize -> begin -> apply -> finalize/reverse, cutover/activate), navnefuldførelse, canonical delta; 1939-journalen konverteret til profil-bundet v2-writer.
2. **Specs (3) og planer (3):** 2026-08-25-evidensbaseret-genimport-styringsgrundlag-design.md, 2026-08-29-evidence-hardening-154-155-design.md, 2026-09-01-generalized-reimport-writer-design.md | planer: 2026-08-25-evidensbaseret-genimport-styringsgrundlag.md, 2026-08-29-evidence-hardening-154-155.md, 2026-09-01-generalized-reimport-writer-implementation.md
3. **Kode (9):**
   apply_name_completion.R, apply_name_completion_helpers.R, apply_reimport.R, apply_reimport_helpers.R, evidence_contract.py, export_reimport_preview.R,
   export_reimport_preview_helpers.R, project_evidence.R, project_evidence_helpers.R
4. **Databaseobjekter:** `reimport_writer_profile` (s:3430 m:11923); `reimport_authorization` (s:3443 m:-); `reimport_batch` (s:3466 m:-); `reimport_event` (s:3488 m:-); `reimport_name_completion_result` (s:3557 m:-); `red_authorize_reimport` (s:3717 m:12082); `red_begin_reimport` (s:3764 m:12083); `red_apply_reimport_person_create` (s:3804 m:12117); `red_finalize_reimport` (s:4611 m:12118); `red_reverse_reimport` (s:4970 m:12120); `red_authorize_reimport_cutover` (s:5168 m:12121); `red_activate_reimport_batch` (s:5183 m:12122); `red_apply_reimport_canonical_delta` (s:4882 m:12878); `red_apply_reimport_name_completion` (s:4923 m:12575); `lock_reimport_writer` (s:3621 m:12045); `validate_reimport_writer_config` (s:3416 m:12858); `validate_evidence_scope` (s:857 m:5605); `reject_evidence_mutation` (s:851 m:5599)
5. **Tests (21):**
   test_evidence_contract.py{P}, test_project_evidence.R{-}, evidence-hardening-pre-migration.sql{E}, evidence-promotion-bootstrap.sql{CEW},
   inspect-reimport-writer-catalog.sql{W}, reimport-writer-coexistence-fixture.sql{W}, reimport-writer-locking-fixture.sql{-}, reimport-writer-v2-bootstrap.sql{W},
   run-db-verify-disposable.sql{CEW}, test-evidence-promotion.sql{E}, test-reimport-edition-catalog.sql{CW}, test-reimport-name-completion.sql{W},
   test-reimport-writer-migration.sql{W}, test-reimport-writer.sql{W}, test-reimport-writer-locking.R{W}, test-reimport-writer.R{W}, test-apply-name-completion.R{R},
   test-apply-reimport.R{R}, test-export-reimport-preview.R{R}, test-project-evidence.R{R}, test-reimport-writer-source-inventory.R{R}
6. **Bevis:** evidence-phase-reconciliation-156-2026-09-03.md, reimport-writer-153-rehearsal.md
7. **Runbooks:** evidence-import-phase-gate.md
8. **Prod-status/modenhed:** "Roadmap-trin 1-3 (#152, #153, #149) er `produktionsverificeret` pr. 2026-09-06" (GO 1: #153 DDL live i prod 2026-09-05; `docs/database-current-state.md` §3 "#152 fase 1, #153 og 149b - DDL LIVE i prod").
9. **Åbne issues:** Ingen åbne (jf. _issues.txt).
10. **Noter:** Styringsgrundlaget (spec 2026-08-25) og evidence-hardening 154/155 (spec/plan 2026-08-29) er placeret her; hardening har ingen egen bevisfil ud over CI-bootstraps (`evidence-hardening-pre-migration.sql`).

## Trin 3 (#149): provenance for 2018-20 (149a kilderegnskab, 149b legacy-migration/narrativ-binding #166)

1. **Mål:** 2018-20 får fase A-ækvivalent provenance: rendition/source record/occurrence/anker for 591 poster (149a) og binding af eksisterende narrativer til records (149b: 541 publicerede, 46 kladder).
2. **Specs (2) og planer (2):** 2026-09-03-2018-20-fase-a-provenance-design.md, 2026-09-03-2018-20-fase-b-legacy-migration-design.md | planer: 2026-09-03-2018-20-fase-a-source-evidence.md, 2026-09-03-2018-20-fase-b-legacy-migration.md
3. **Kode (8):**
   build_legacy_migration_manifest.py, build_source_evidence_manifest.py, build_source_evidence_rendition.py, export_legacy_migration_candidates.R,
   export_legacy_migration_candidates_helpers.R, reimport_profile.py, reverse_reimport_legacy_migration.R, reverse_reimport_legacy_migration_helpers.R
4. **Databaseobjekter:** `reimport_case_batch` (s:8235 m:9253); `reimport_case_event` (s:8261 m:9279); `red_preview_reimport_cases` (s:10273 m:9728); `red_authorize_reimport_cases` (s:10413 m:9868); `red_apply_reimport_cases` (s:10564 m:10019); `red_reverse_reimport_cases` (s:11187 m:10642); `red_authorize_reimport_case_reversal` (s:11101 m:10556); `red_apply_reimport_source_evidence` (s:3791 m:12116); `red_apply_reimport_legacy_migration` (s:4025 m:17226); `migrate_legacy_narrative_record` (s:3841 m:17043); `legacy_migration_reversal_state` (s:5011 m:17589)
5. **Tests (15):**
   test_build_legacy_migration_manifest.py{P}, test_build_source_evidence_manifest.py{P}, test_build_source_evidence_rendition.py{P}, test_reimport_profile.py{P},
   reimport-writer-legacy-empty-fixture.sql{W}, reimport-writer-legacy-invalid-terminal-fixture.sql{W}, reimport-writer-legacy-source-evidence-fixture.sql{W},
   reimport-writer-legacy-terminal-fixture.sql{-}, test-reimport-legacy-migration.sql{W}, test-reimport-legacy-migration.R{W}, test-reimport-legacy-preview.R{W},
   test-reimport-source-evidence.R{W}, test-export-legacy-migration-candidates.R{R}, test-reimport-writer-legacy-migration.R{R},
   test-reverse-reimport-legacy-migration.R{R}
6. **Bevis:** legacy-migration-149b-phase-package-contribution.md, legacy-migration-149b-rehearsal.md, source-evidence-149a-phase-package-contribution.md, source-evidence-149a-rehearsal.md
7. **Runbooks:** legacy-migration-reimport-rehearsal.md, source-evidence-reimport-rehearsal.md
8. **Prod-status/modenhed:** 149a `produktionsverificeret` (2026-09-06); 149b (#166) `produktionsverificeret` (2026-09-06). Restpunkter: fire `unresolved_text`-records (`I-133`, `II-35`, `III-129`, `IV-94`) og 13 mulige `NOISE_RE`-prosalinjer. Profiler: `.claude/skills/daa-extract/references/reimport-profiles/daa-2018-20-{source-evidence,legacy-migration}-v1.json`.
9. **Åbne issues:** Ingen åbne (jf. _issues.txt).

## Trin 4 (#147/#148): fortolkningskæde og klausuler (4.1a-4.5, kontrolmodel, omsegmentering, 2018-20-overførsel)

1. **Mål:** Klausulgranularitet (clause_disposition, clause_set, clause_revision), prædikat-navnerum, extractor-runner (`evidence_runner.py` via Codex/Seatbelt), proposed-ingest, afgørelse (kontrolmodel: kun uoverensstemmelser + stikprøve), binding; hele 2018-20 overført til prod (3.739 forslag, 676 afgørelser, 622 bindinger).
2. **Specs (4) og planer (19):** 2026-09-06-trin4-fortolkningskaede-og-klausulgranularitet-design.md, 2026-09-20-interpretation-proposal-prod-gate-design.md, 2026-09-27-trin4-omsegmentering-og-s4-design.md, 2026-10-03-trin4-2018-20-prod-overfoersel-design.md | planer: 2026-09-06-trin4-4-1a-klausullag-skema.md, 2026-09-06-trin4-4-1b-klausul-segmenter.md, 2026-09-06-trin4-4-1c-clause-evidence-writer.md, 2026-09-06-trin4-4-2-praedikat-vokabular.md, 2026-09-11-trin4-4-3a-runner-og-forbrug.md, 2026-09-12-trin4-4-3b-foerste-kald-mod-rigtige-data.md, 2026-09-13-trin4-4-4-proposed-ingest.md, 2026-09-17-trin4-klausul-projektion.md, 2026-09-21-interpretation-proposal-prod-wrapper.md, 2026-09-21-interpretation-proposal-projection.md, 2026-09-21-interpretation-proposal-reversal.md, 2026-09-23-4-4-prod-wrapper.md, 2026-09-23-trin4-4-5-pilot-afgoerelse-binding.md, 2026-09-27-trin4-kontrolmodel.md, 2026-09-27-trin4-omsegmentering-og-s4.md, 2026-09-28-trin4-genbind-44-pilot-om.md, 2026-10-01-trin4-2018-20-fuld-koersel.md, 2026-10-04-trin4-2018-20-overfoersel-a-pakke.md, 2026-10-04-trin4-2018-20-overfoersel-b-ceremoni.md
3. **Kode (41):**
   build_43b_judgement_sheet.py, build_43b_manifest.py, build_43b_proposal_manifest.py, build_43b_selection.py, build_45_selection.py, build_clause_evidence_manifest.py,
   build_clause_ledger.py, build_eligible_selection.py, check_interpretation_predicates.py, clause_evidence_anon_projection.sql, clause_evidence_projection.psql,
   clause_evidence_projection.sql, clause_evidence_target_identity.sql, clause_ledger.py, clause_segment.py, clause_set.py, compare_clause_evidence_projection.py,
   compare_interpretation_proposal_projection.py, control_model.py, decision_sheet_core.py, decision_sheet_html.js, decision_sheet_html.py, evidence_extract.py,
   evidence_runner.py, export_43b_runner_input.R, export_clause_evidence_preview.R, export_clause_source_texts.R, export_model_eligibility.R,
   interpretation_control_classification.sql, interpretation_control_rows.sql, interpretation_decision_fingerprint.sql, interpretation_decision_sheet.py,
   interpretation_promotion_targets.sql, interpretation_promotion_targets_scoped.sql, interpretation_proposal_anon_projection.sql,
   interpretation_proposal_projection.psql, interpretation_proposal_projection.sql, interpretation_proposal_target_identity.sql, interpretation_transfer_digests.sql,
   run_evidence_43a_rehearsal.py, run_evidence_43b.py
4. **Databaseobjekter:** `clause_disposition` (s:726 m:17892); `clause_set_sha256` (s:15398 m:19455); `check_clause_set_density` (s:15364 m:19421); `write_clause_evidence` (s:4174 m:18199); `red_apply_reimport_clause_evidence` (s:4190 m:18315); `write_clause_revision` (s:4200 m:19880); `red_apply_reimport_clause_revision` (s:4247 m:19927); `interpretation_predicate` (s:1096 m:18339); `interpretation` (s:1193 m:5778); `interpretation_observation` (s:1251 m:5814); `interpretation_party` (s:1265 m:20139); `interpretation_promotion_rule` (s:1377 m:6259); `interpretation_promotion_batch` (s:1405 m:6295); `interpretation_promotion` (s:1531 m:5822); `write_interpretation_proposal` (s:4417 m:19061); `red_apply_reimport_interpretation_proposal` (s:4607 m:19210); `red_decide_interpretation` (s:8722 m:6408); `red_promote_interpretation` (s:8785 m:6464); `red_preview_interpretation_promotions` (s:9739 m:7765); `red_promote_interpretations_batch` (s:9750 m:7775); `validate_interpretation_scope` (s:1696 m:6030)
5. **Tests (30):**
   test_build_43b_proposal_manifest.py{P}, test_build_45_selection.py{P}, test_build_clause_evidence_manifest.py{P}, test_build_clause_ledger.py{P},
   test_build_eligible_selection.py{-}, test_clause_ledger.py{-}, test_clause_readers.py{P}, test_clause_segment.py{P}, test_clause_set.py{P},
   test_compare_clause_evidence_projection.py{P}, test_compare_interpretation_proposal_projection.py{P}, test_control_model.py{P}, test_decision_sheet_html.py{P},
   test_evidence_extract.py{P}, test_evidence_run_manifest.py{P}, test_evidence_runner.py{P}, test_interpretation_decision_sheet.py{P}, test_perturbation.py{-},
   test-clause-evidence-schema.sql{W}, test-clause-evidence-writer.sql{W}, test-clause-revision.sql{W}, test-clause-set.sql{W},
   test-interpretation-control-classification.sql{E}, test-interpretation-predicate.sql{E}, test-interpretation-promotion-targets.sql{E},
   test-interpretation-proposal.sql{W}, transfer-decide-bind.sh{E}, test-reimport-clause-evidence.R{W}, test-reimport-interpretation-proposal.R{-},
   interpretation-proposal-db.sh{I}
6. **Bevis:** 2018-20-fuld-koersel.md, clause-evidence-148-rehearsal.md, genbind-44-pilot-2018-20.md, interpretation-pilot-2018-20.md, interpretation-predicate-147-rehearsal.md, kontrolmodel-koersel-2018-20.md, omsegmentering-rehearsal-2018-20.md, proposal-ingest-147-4-4-projection-rehearsal.md, proposal-ingest-147-4-4-rehearsal.md, proposal-ingest-147-4-4-task0.md, runner-rehearsal-147-4-3a.md, runner-rehearsal-147-4-3b.md, runner-usage-probe-147-4-3a.md
7. **Runbooks:** clause-evidence-prod-apply.md, clause-revision-prod-apply.md, interpretation-proposal-prod-apply.md, transfer-2018-20-prod.md
8. **Prod-status/modenhed:** Ingest og afgørelse: `produktionsverificeret` for 2018-20 (2026-10-05); promotion: kun bindingsdelen `produktionsverificeret` (2026-10-05); Extractor-runner og modelkald: `integreret ende-til-ende` for 2018-20, hovedpersonens persona, i restore (2026-09-26); Klausulgranularitet og coverage: `specificeret` (OBS: række i status.md er forældet - se uklarheder). Trin 4 "afsluttet for 2018-20" 2026-10-05. Omsegmentering i prod 2026-09-28 (`database-current-state.md` §9), skema/writere §8.
9. **Åbne issues:** Ingen åbne (jf. _issues.txt). Restpunkter fra trin 4 (status.md "Næste tilladte arbejde" punkt 2): næste promptversion, 138 navne-assertions med titelord, Codex-kvotefejl.
10. **Noter:** Allowlist/hash-gate for runneren: `sandbox/runner-gate.sb.template`, `references/{evidence-claims-1.0.json,evidence-extract-prompt-1.0.0.md,interpretation-predicates.json,interpretation-schema.json,observation-schema.json}`. Trin 4s overførselspakke (plan A/B 2026-10-04) er placeret her, ikke under 5a/5b-overførslen (xa/xb).

## Trin 5a (#151): én identitetsvej - source persona, kandidater, webkø

1. **Mål:** Privat identitetskerne med strukturel oprindelse og cutover, kandidatgenerator, hash-bundet identitetsark og webkø gennem samme RPC (`red_afgoer_source_persona`).
2. **Specs (1) og planer (1):** 2026-09-24-trin5a-identitetsvej-design.md | planer: 2026-09-24-trin5a-identitetsvej.md
3. **Kode (4):**
   identity_decision_sheet.py, identity_queue_sheet.py, identity_sheet_rows.sql, source_persona.py
4. **Databaseobjekter:** `source_persona` (s:808 m:5564); `source_persona_mention` (s:820 m:5573); `source_persona_identity` (s:1572 m:5835); `source_persona_identity_event` (s:1604 m:5855); `source_persona_identity_candidate_run` (s:1640 m:18579); `source_persona_identity_candidate` (s:1659 m:18598); `decide_source_persona_identity` (s:8833 m:6487); `red_source_persona_queue` (s:8985 m:7221); `red_source_persona_detail` (s:9034 m:7263); `red_source_persona_history` (s:9138 m:7366); `red_afgoer_source_persona` (s:9156 m:7375); `red_record_identity_candidates` (s:9385 m:18695); `identity_candidate_input` (s:9316 m:18626); `insert_person_with_receipt` (s:8823 m:18567); `person_create_receipt` (s:8816 m:18560)
5. **Tests (9):**
   test_identity_decision_sheet.py{P}, test_identity_guard_static.py{P}, test_identity_queue_sheet.py{P}, test_source_persona.py{-}, test-identity-candidates.sql{E},
   test-identity-cutover.sql{E}, test-identity-deceased-context.sql{E}, test-identity-decision.sql{E}, test-identity-detail.sql{E}
6. **Bevis:** identitetsvej-5a-bevis.md
7. **Runbooks:** (ingen)
8. **Prod-status/modenhed:** `produktionsverificeret` for 2018-20 (2026-10-25, GO 2; i restore 5a 2026-10-05, 5b del 1 2026-10-11). Cutover-blok `-- BEGIN 5a-cutover` db-migrations.sql:11-23.
9. **Åbne issues:** #151 (åben: refactor(identitet) én identitetsvej)

## Trin 5b del 1 (#151): relation-personas og maskinel familiebekræftelse (kontrolmodel for ægtefæller)

1. **Mål:** Relation-persona-writer, ægtefællekort (blinde), kontrolkørsel (register/stikprøve/segl/evaluér) og `family_corroboration`.
2. **Specs (1) og planer (2):** 2026-10-06-trin5b-relationspersonas-design.md | planer: 2026-10-06-trin5b-del1-identitet.md, 2026-10-10-trin5b-del1-kontrolkort.md
3. **Kode (5):**
   identity_control_rows.sql, identity_control_sheet.py, relation_persona_apply.sql, relation_persona_extract.py, relation_persona_input.sql
4. **Databaseobjekter:** `identity_control_run` (s:16414 m:20741); `identity_control_sample` (s:16433 m:20755); `identity_control_parent_card` (s:16473 m:20801); `write_relation_persona` (s:15599 m:20297); `red_apply_reimport_relation_persona` (s:15815 m:20467); `red_relation_persona_input` (s:15588 m:20286); `red_register_identity_control_run` (s:16679 m:20997); `red_identity_control_sample` (s:16821 m:21103); `red_seal_identity_control_run` (s:16834 m:21116); `red_evaluate_identity_control_run` (s:16849 m:21131); `red_classify_parent_card` (s:16603 m:20931); `red_corroborate_family_identities` (s:16985 m:21267); `check_family_corroboration` (s:16884 m:21166); `verify_relation_persona_receipts` (s:15825 m:20477)
5. **Tests (7):**
   test_identity_control_sheet.py{P}, test_relation_persona_extract.py{P}, test-family-corroboration.sql{W}, test-family-id-identity.sql{E}, test-family-sources.sql{W},
   test-identity-control-run.sql{E}, test-relation-persona-writer.sql{W}
6. **Bevis:** relationspersonas-5b-del1-bevis.md
7. **Runbooks:** (ingen)
8. **Prod-status/modenhed:** Del 1 `produktionsverificeret` for 2018-20 som del af 5a/5b-rækken (2026-10-25, GO 2; i restore 2026-10-11, merget #237). db-migrations.sql: kontrolkørsel :20740, family_corroboration :21154.
9. **Åbne issues:** #151

## Trin 5b del 2a (#151): relationsbindinger og kildevisning

1. **Mål:** 203 maskinelt afgjorte ægteskaber + 7 forældrepåstande bundet til kanonisk familie (210 bindinger), offentlig `public_family_sources`.
2. **Specs (1) og planer (1):** 2026-10-11-trin5b-2a-binding-design.md | planer: 2026-10-11-trin5b-2a-binding.md
3. **Kode (0):**
   (ingen)
4. **Databaseobjekter:** `relation_binding_state` (s:17041 m:21433); `relation_classification_event` (s:17168 m:21492); `red_preview_relation_decisions` (s:17244 m:21568); `red_decide_relation_interpretations` (s:17255 m:21579); `red_preview_relation_promotions` (s:17506 m:21726); `red_promote_relation_interpretations_batch` (s:17515 m:21735); `red_afgoer_relation_interpretation` (s:16317 m:20645); `persona_family_context` (s:15922 m:20572); `public_family_sources` (s:18143 m:21787)
5. **Tests (5):**
   test-relation-binding-upgrade.sh{-}, test-relation-binding.sql{E}, test-relation-decision.sql{E}, test-relation-family-context.sql{E}, test-relation-party.sql{E}
6. **Bevis:** relationspersonas-5b-2a-bevis.md
7. **Runbooks:** (ingen)
8. **Prod-status/modenhed:** `produktionsverificeret` for 2018-20 (2026-10-25, GO 2; i restore 2026-10-11).
9. **Åbne issues:** #151
10. **Noter:** Ingen script-filer med egen entydig 2a-markering; arbejdet bor i SQL-RPC'er og tests.

## Trin 5b del 2b-i (#151): ægtefælle-undtagelser, kø og genbinding

1. **Mål:** De 31 ægtefæller fra 2a afgjort: 22 via hash-bundet undtagelsesark, 9 via webkø; ordinal-afvigelser klassificeret.
2. **Specs (1) og planer (1):** 2026-10-11-trin5b-2b-i-genbinding-og-aegtefaeller-design.md | planer: 2026-10-12-trin5b-2b-i.md
3. **Kode (2):**
   spouse_exception_rows.sql, spouse_exception_sheet.py
4. **Databaseobjekter:** `spouse_exception_projection` (s:17565 m:21890); `spouse_principal_person` (s:16873 m:21155)
5. **Tests (4):**
   test_spouse_exception_sheet.py{P}, test-spouse-exception-projection.sql{E}, test-spouse-exception-sheet.sh{E}, test-spouse-review-context.sql{E}
6. **Bevis:** relationspersonas-5b-2b-i-bevis.md
7. **Runbooks:** (ingen)
8. **Prod-status/modenhed:** `produktionsverificeret` for 2018-20 (2026-10-25, GO 2; i restore 2026-10-13).
9. **Åbne issues:** #151

## Trin 5b del 2b-ii (#151): nye afdøde ægtefæller, klausul-disposition, navneregel v3

1. **Mål:** Andet gennemløb (profil v2/v3) over ægteskaber uden ægtefælle-persona; navneregel v3 (titler inde i adelsnavne); relation_person_create + disposition.
2. **Specs (1) og planer (2):** 2026-10-17-trin5b-2b-ii-nye-personer-og-disposition-design.md | planer: 2026-10-17-trin5b-2b-ii.md, 2026-10-18-trin5b-2b-ii-runde2-navneregel-v3.md
3. **Kode (7):**
   relation_batch_apply.sql, relation_marriage_sheet.py, relation_marriage_sheet_v3.py, relation_persona_extract_v2.py, relation_persona_extract_v3.py,
   relation_v2_rows.sql, relation_v3_rows.sql
4. **Databaseobjekter:** `relation_person_create_input` (s:17668 m:22466); `write_relation_person_create` (s:17712 m:22510); `red_apply_reimport_relation_person_create` (s:17840 m:22628); `relation_disposition_state` (s:17892 m:22942); `write_relation_disposition` (s:17953 m:23003); `red_apply_reimport_relation_disposition` (s:18002 m:23052); `relation_persona_v2_input` (s:18046 m:22719); `relation_persona_v3_input` (s:18084 m:23416); `relation_title_words` (s:18030 m:23080); `relation_name_has_title` (s:18036 m:23086); `relation_ordered_windows` (s:15483 m:22688)
5. **Tests (12):**
   test_relation_marriage_sheet.py{P}, test_relation_marriage_sheet_v3.py{P}, test_relation_persona_extract_v2.py{P}, test_relation_persona_extract_v3.py{P},
   test-2bii-upgrade.sh{-}, test-relation-disposition.sql{W}, test-relation-marriage-sheet-v3.sh{W}, test-relation-marriage-sheet.sh{W},
   test-relation-person-create-v3.sql{W}, test-relation-person-create.sql{W}, test-relation-persona-v2.sql{W}, test-relation-persona-v3.sql{W}
6. **Bevis:** relationspersonas-5b-2b-ii-bevis.md, relationspersonas-5b-navneregel-v3-bevis.md
7. **Runbooks:** (ingen)
8. **Prod-status/modenhed:** 2b-ii og runde 2 (navneregel v3) begge `produktionsverificeret` for 2018-20 (2026-10-25, GO 2; i restore 2026-10-18 hhv. 2026-10-20).
9. **Åbne issues:** #151

## Trin 5b del 2b-iii (#151): børnehenvisninger

1. **Mål:** De 14 `relation.child` er krydshenvisninger til hele børneflokke; regel `relation-child-v1` binder flokken til forælderens familie.
2. **Specs (1) og planer (1):** 2026-10-20-trin5b-2b-iii-boernehenvisninger-design.md | planer: 2026-10-20-trin5b-2b-iii-boernehenvisninger.md
3. **Kode (2):**
   relation_child_rows.sql, relation_child_sheet.py
4. **Databaseobjekter:** `relation_child_ref` (s:15971 m:23472); `relation_child_rule` (s:16006 m:23507); `decide_relation_child` (s:16100 m:23601); `relation_child_sheet_input` (s:16142 m:23887); `red_relation_child_sheet_input` (s:16161 m:23906)
5. **Tests (3):**
   test_relation_child_sheet.py{P}, test-relation-child-sheet.sh{W}, test-relation-child.sql{W}
6. **Bevis:** relationspersonas-5b-2b-iii-bevis.md
7. **Runbooks:** (ingen)
8. **Prod-status/modenhed:** `produktionsverificeret` for 2018-20 (2026-10-25, GO 2; i restore 2026-10-20). 5c-1-opfølger #270 (V-82..V-92 barn i forælderens slægtled) hører hertil/5c.
9. **Åbne issues:** #151, #270

## #244 (5b): ægteskabsnumre

1. **Mål:** `relation_marriage_ordinals` nummererer efter skriverens ordvindue; værn mod modstrid med bogens »g. N°«; rettelsesvej.
2. **Specs (1) og planer (1):** 2026-10-20-244-aegteskabsnumre-design.md | planer: 2026-10-20-244-aegteskabsnumre.md
3. **Kode (3):**
   ordinals.py, relation_ordinal_rows.sql, relation_ordinal_sheet.py
4. **Databaseobjekter:** `marriage_ordinal_correction` (s:1344 m:24155); `relation_book_ordinal` (s:15538 m:23939); `relation_marriage_ordinals` (s:15517 m:20225); `red_ret_aegteskabsnummer` (s:16172 m:24183); `red_marriage_ordinal_correction_input` (s:16282 m:24293)
5. **Tests (6):**
   test_ordinals.py{-}, test_relation_ordinal_sheet.py{P}, test-244-upgrade.sh{-}, test-marriage-ordinal-correction.sql{W}, test-marriage-ordinal-lock.sql{W},
   test-relation-ordinal-sheet.sh{W}
6. **Bevis:** aegteskabsnumre-244-bevis.md
7. **Runbooks:** (ingen)
8. **Prod-status/modenhed:** Nummereringen: `produktionsverificeret` for 2018-20 (2026-10-25, GO 2). Rettelsesvejen: `isoleret implementeret`.
9. **Åbne issues:** #151 (ingen egen)

## Indholds-id (#151, forudsætning for overførslen)

1. **Mål:** Otte rækkearter får id af indholdet (`private.content_uuid`, kollision fejler lukket) så restore-genspil giver identiske id'er.
2. **Specs (1) og planer (1):** 2026-10-21-trin5ab-indholds-id-design.md | planer: 2026-10-21-trin5ab-indholds-id.md
3. **Kode (0):**
   (ingen)
4. **Databaseobjekter:** `content_uuid` (s:4274 m:24309); `deterministic_uuid` (s:4260 m:19005)
5. **Tests (4):**
   indholds-id-export.sql{-}, test-content-uuid.sql{W}, test-indholds-id-determinism.sh{W}, test-indholds-id-upgrade.sh{-}
6. **Bevis:** (ingen *-bevis/*-rehearsal-fil)
7. **Runbooks:** (ingen)
8. **Prod-status/modenhed:** `i prod` (DDL 2026-10-22, GO 1; data 2026-10-25, GO 2) - OBS: `i prod` er ikke en af de fire tilladte modenhedstilstande i roadmap.
9. **Åbne issues:** #151

## Overførsel plan A (#151): DDL-ceremonien for 5a+5b

1. **Mål:** Fase 0 (frys/preflight), D0 verificeret, rehearsal, DDL, D1 verificeret. Fingeraftryk (katalog, ACL, tabelhashes).
2. **Specs (1) og planer (1):** 2026-10-21-trin5ab-2018-20-prod-overfoersel-design.md | planer: 2026-10-21-trin5ab-overfoersel-a-ddl.md
3. **Kode (3):**
   transfer_acl_fingerprint.sql, transfer_catalog_fingerprint.sql, transfer_ddl.py
4. **Databaseobjekter:** (ingen egne; se øvrige enheder)
5. **Tests (3):**
   test_transfer_ddl.py{P}, inspect-5ab-function-parity.sql{W}, test-transfer-5ab-ddl-upgrade.sh{-}
6. **Bevis:** (ingen *-bevis/*-rehearsal-fil)
7. **Runbooks:** transfer-5ab-ddl-prod.md
8. **Prod-status/modenhed:** `i prod` (DDL, 2026-10-22, GO 1); `docs/database-current-state.md` §10.
9. **Åbne issues:** #151

## Overførsel plan B1 (#151): værktøj til data-ceremonien

1. **Mål:** Nøglekort og nøglede digests over 21 lag, uberørt-hash, skridt-SQL (profil, afgør, bind, disposition, afvis, kandidater, kontrol, korroboration), køens ark.
2. **Specs (0) og planer (1):** (ingen) | planer: 2026-10-22-trin5ab-overfoersel-b1-vaerktoej.md
3. **Kode (21):**
   transfer_5ab_bound_partners.sql, transfer_5ab_content.sql, transfer_5ab_content_check.py, transfer_5ab_control_answers.sql, transfer_5ab_digests.sql,
   transfer_5ab_guards.sql, transfer_5ab_keymap.sql, transfer_5ab_step_begin.sql, transfer_5ab_step_bind.sql, transfer_5ab_step_candidates.sql,
   transfer_5ab_step_compare.sql, transfer_5ab_step_control.sql, transfer_5ab_step_corroborate.sql, transfer_5ab_step_decide.sql, transfer_5ab_step_disposition.sql,
   transfer_5ab_step_end.sql, transfer_5ab_step_items.sql, transfer_5ab_step_profile.sql, transfer_5ab_step_reject.sql, transfer_5ab_untouched_hash.sql,
   transfer_table_hashes.sql
4. **Databaseobjekter:** (ingen egne; se øvrige enheder)
5. **Tests (7):**
   test_transfer_5ab_content_check.py{P}, lib-transfer-5ab.sh{-}, test-transfer-5ab-del1-steps.sh{W}, test-transfer-5ab-digests.sh{W}, test-transfer-5ab-steps.sh{W},
   test-transfer-fingerprint-digests.sql{E}, test-transfer-fingerprints.sh{W}
6. **Bevis:** (ingen *-bevis/*-rehearsal-fil)
7. **Runbooks:** (ingen)
8. **Prod-status/modenhed:** `i prod` (brugt i GO 2, 2026-10-25).
9. **Åbne issues:** #151

## Overførsel plan B2 (#151): data-ceremonien for 5a+5b

1. **Mål:** Pakke (`PACK_OK` 46f5d1e5...), genspilsprøve, GO 2; første forsøg stoppede ved `STATEMENT_TIMEOUT` (prods 2 min), genspil fra skridt 3; `VERIFY_OK`.
2. **Specs (0) og planer (1):** (ingen) | planer: 2026-10-23-trin5ab-overfoersel-b2-ceremoni.md
3. **Kode (8):**
   transfer_answers.py, transfer_baseline.sql, transfer_pack.py, transfer_pack_export.sql, transfer_restore_hash.sql, transfer_restore_preconditions.sql,
   transfer_steps.py, transfer_untouched_hash.sql
4. **Databaseobjekter:** (ingen egne; se øvrige enheder)
5. **Tests (5):**
   test_transfer_answers.py{P}, test_transfer_pack.py{P}, test_transfer_steps.py{P}, test-transfer-baseline.sql{E}, transfer-fixture.sql{-}
6. **Bevis:** (ingen *-bevis/*-rehearsal-fil)
7. **Runbooks:** transfer-5ab-data-prod.md
8. **Prod-status/modenhed:** `i prod` (data, 2026-10-25, GO 2); `docs/database-current-state.md` §11.
9. **Åbne issues:** #151
10. **Noter:** Pakke-fixtures: tests/fixtures/transfer-pack. Privat runner/pakker ligger uden for repo (`~/.private/5ab-overfoersel/`).

## Afbrydelser efter GO 2: dubletreglen, #240 dobbeltfamilier, GO 2-dublet, #248 (skridt 1 + rute A genåbning)

1. **Mål:** Kontrolleret afbrydelse: dubletregel (5b §23.4) rettes før 1939; 5 dobbeltfamilier slås sammen (#240); #248 to navnefælle-ægtefæller afgjort igen, genåbning ved familieskift bygges (`relation_reopen`, `red_genaabn_relation_interpretation`).
2. **Specs (1) og planer (1):** 2026-10-26-248-genaabning-ved-familieskift-design.md | planer: 2026-10-26-248-genaabning-ved-familieskift.md
3. **Kode (10):**
   fix_240_aegteskaber.sql, fix_240_ddl151_fingeraftryk.sql, fix_240_maal.sql, fix_240_saml.sql, fix_248_a_fingeraftryk.sql, fix_248_genaabn.sql, fix_248_identitet.sql,
   fix_248_maal.sql, fix_go2_dublet.sql, fix_go2_dublet_maal.sql
4. **Databaseobjekter:** `relation_reopen` (s:17299 m:25612); `red_genaabn_relation_interpretation` (s:17329 m:25642); `relation_binding_state` (s:17041 m:21433); `control_run_status` (s:16622 m:20950)
5. **Tests (1):**
   test-248-upgrade.sh{-}
6. **Bevis:** (ingen *-bevis/*-rehearsal-fil)
7. **Runbooks:** 248-genaabning-prod.md, fix-240-dobbeltfamilier-prod.md, fix-248-identitet-prod.md
8. **Prod-status/modenhed:** Prod 2026-10-26 (`docs/database-current-state.md` §12 "LIVE i prod"): dubletregel-DDL + #240 + GO 2-dublet + #248 skridt 1 + rute A (GO 248A `d910500c`). status.md header: "Prod 2026-10-26: dubletreglen (DDL) og #240's dobbeltfamilier rettet ... #248 skridt 1 ...". #248 LUKKET (memory). Dubletregel-blok slutter db-migrations.sql:25483; rute A DDL ligger efter.
9. **Åbne issues:** #151 (åben). #248 og #240 ikke længere åbne.
10. **Noter:** Ingen modenhedsrække i status.md (kun header-prosa). Ingen *-bevis.md; bevis = runbooks + decisions.md 2026-10-25/26.

## Trin 5c-1 (#150): placement og membership for 2018-20

1. **Mål:** Header-evidens, placements for kilde 1, ledger pr. legacy-række (`legacy_placement_disposition`), membership-promotion, `slaegt` -> `active`, revalidering. Ingen læser ændres (5c-2 = læserskift, senere).
2. **Specs (1) og planer (1):** 2026-10-26-trin5c-placement-membership-design.md | planer: 2026-10-26-trin5c-placement-membership.md
3. **Kode (6):**
   build_header_manifest.py, fix_150_eksport.sql, fix_150_fingeraftryk.sql, fix_150_maal.sql, fix_150_placement.sql, placement_control_sheet.py
4. **Databaseobjekter:** `source_record_placement` (s:2238 m:6834); `source_persona_placement` (s:2255 m:6848); `source_record_placement_decision` (s:2268 m:6921); `source_persona_placement_decision` (s:2282 m:6934); `legacy_placement_disposition` (s:2703 m:25919); `person_slaegt_membership` (s:2207 m:6736); `person_lineage_membership` (s:2216 m:6744); `write_header_evidence` (s:2760 m:25976); `write_record_placement` (s:2822 m:26038); `write_persona_placement` (s:2863 m:26079); `record_legacy_disposition` (s:2894 m:26110); `red_decide_source_record_placement` (s:2507 m:7114); `red_decide_source_persona_placement` (s:2553 m:7136); `red_preview_placement_memberships` (s:3026 m:26242); `red_promote_placement_memberships` (s:3038 m:26254); `red_reverse_placement_membership` (s:3072 m:26288); `placement_header_violations` (s:2658 m:25874); `membership_state` (s:2940 m:26156)
5. **Tests (7):**
   test_build_header_manifest.py{P}, test_placement_control_sheet.py{P}, test-150-ceremoni.sh{E}, test-150-upgrade.sh{-}, test-placement-header.sql{E},
   test-placement-membership.sql{E}, test-placement-writer.sql{E}
6. **Bevis:** (ingen *-bevis/*-rehearsal-fil)
7. **Runbooks:** 150-placement-prod.md
8. **Prod-status/modenhed:** status.md: "Placement og membership | `isoleret implementeret`" (forældet: 5c-1 er merget som #269, kode i main). Ingen prod-status: runbook beskriver GO 1 (DDL: blok fra db-migrations.sql:25802) og GO 2, men hverken status.md, database-current-state.md eller changelog nævner 5c.
9. **Åbne issues:** #150 (åben: migrér legacy slægtled/medlemskab), #270 (5c-1 opfølgning V-82..V-92)
10. **Noter:** Ingen *-bevis.md endnu. Blokke i db-migrations.sql: header-sti :25823, nærmeste-regel :25870, ledger :25917, membership :26153. Tests i CI: placement-header/writer/membership (E-jobbet) + `test-150-ceremoni.sh`; `test-150-upgrade.sh` kører IKKE i CI.

## Review af trin 1-5 (Fable-review, roadmap-krav før trin 6)

1. **Mål:** Helhedsreview af konsistens og kodekvalitet for trin 1-5 (spec 2026-10-27) - dette systemkort er et input.
2. **Specs (1) og planer (1):** 2026-10-27-review-trin-1-5-design.md | planer: 2026-10-27-review-trin-1-5.md
3. **Kode (0):**
   (ingen)
4. **Databaseobjekter:** (ingen egne; se øvrige enheder)
5. **Tests (0):**
   (ingen)
6. **Bevis:** (ingen *-bevis/*-rehearsal-fil)
7. **Runbooks:** (ingen)
8. **Prod-status/modenhed:** Specificeret/under arbejde (gren `docs/review-trin-1-5`).
9. **Åbne issues:** Ingen.

## Trin 6: kæden ende-til-ende på begge referenceudgaver (kun specificeret)

1. **Mål:** Roadmap: "Kæden køres ende-til-ende på begge referenceudgaver." Omfatter bl.a. 1939-kæden gennem klausul/runner/ingest/identitet/placement (1939 har 542 pladsholder-`linje`, 0 slægtled), og revalidering "når begge udgaver er migreret".
2. **Specs (0) og planer (0):** (ingen) | planer: (ingen)
3. **Kode (0):**
   (ingen)
4. **Databaseobjekter:** (ingen egne; se øvrige enheder)
5. **Tests (0):**
   (ingen)
6. **Bevis:** (ingen *-bevis/*-rehearsal-fil)
7. **Runbooks:** (ingen)
8. **Prod-status/modenhed:** Ingen spec/plan i repo. status.md: kæden "ikke integreret ende-til-ende"; samlet dom "NO-GO som generel leverance". Fastlagt i trin 4-spec §11.4 ("1939's kæde hører til trin 6") og 5c-spec §3/§9 (legacy-kolonner fjernes først i trin 6; 5c-2 læserskift).
9. **Åbne issues:** Ingen.

## Trin 7: tredje årbog (kun specificeret)

1. **Mål:** Roadmap: "En tredje årbog beviser, at kun en lille profil og dokumenterede vokabularudvidelser kræves."
2. **Specs (0) og planer (0):** (ingen) | planer: (ingen)
3. **Kode (0):**
   (ingen)
4. **Databaseobjekter:** (ingen egne; se øvrige enheder)
5. **Tests (0):**
   (ingen)
6. **Bevis:** (ingen *-bevis/*-rehearsal-fil)
7. **Runbooks:** (ingen)
8. **Prod-status/modenhed:** Status.md: "Tredje-årbogsprøve | `specificeret`" - "ikke gennemført". Mål-arkitektur: teknisk-maalarkitektur.md:209.
9. **Åbne issues:** Ingen.

## Oversigtstabel

| enhed | #specs / #planer | #kodefiler | #testfiler | modenhed (kort, se sektionen) |
|---|---|---|---|---|
| S1 Datamodel og invarianter (forarbejde) | 0 / 0 | 11 | 0 | Prod-snapshot i `docs/database-current-state.md` §1 er et snapshot dateret 2026-07-20 (tal opdateret ad hoc ti |
| S2 Første importer: stamtavle, præsensliste, hændelser (forarbe | 7 / 8 | 19 | 10 | Ingen modenhedstilstand i status.md. Historik: `docs/daa-extraction-archetype.md`, `docs/daa-presens-archetype |
| S3 1939-sporet: C0-C3 og v50 production-writer (forarbejde) | 36 / 45 | 110 | 120 | C3 (1939 source/rendition og recordproveniens): `produktionsverificeret`; 1939 narrativpublicering og kildebin |
| S4 App-relevante DB-lag (forarbejde): redaktions-RPC, versioner | 34 / 35 | 0 | 0 | Ingen modenhedstilstand i status.md (uden for genimport). `docs/database-current-state.md` §3 (kerne, 1939, RL |
| S5 Støtte-pipelines og værktøjer (forarbejde) | 2 / 2 | 31 | 13 | Ingen modenhedstilstand i status.md. TNG-QA Trin 1-6 "komplet, merged" (memory); geo-enrich ikke kørt (#131). |
| Trin 1 (#152): narrativ <-> source record | 1 / 2 | 7 | 8 | `#152 record-nøglede person-narrativer`: `produktionsverificeret` (2026-09-06). Roadmap-trin 1-3 "er `produkti |
| Trin 2 (#153): writer-/batchmekanismer (inkl. #154/#155 evidence- | 3 / 3 | 9 | 21 | "Roadmap-trin 1-3 (#152, #153, #149) er `produktionsverificeret` pr. 2026-09-06" (GO 1: #153 DDL live i prod 2 |
| Trin 3 (#149): provenance for 2018-20 (149a kilderegnskab, 149b l | 2 / 2 | 8 | 15 | 149a `produktionsverificeret` (2026-09-06); 149b (#166) `produktionsverificeret` (2026-09-06). Restpunkter: fi |
| Trin 4 (#147/#148): fortolkningskæde og klausuler (4.1a-4.5, kont | 4 / 19 | 41 | 30 | Ingest og afgørelse: `produktionsverificeret` for 2018-20 (2026-10-05); promotion: kun bindingsdelen `produkti |
| Trin 5a (#151): én identitetsvej - source persona, kandidater, we | 1 / 1 | 4 | 9 | `produktionsverificeret` for 2018-20 (2026-10-25, GO 2; i restore 5a 2026-10-05, 5b del 1 2026-10-11). Cutover |
| Trin 5b del 1 (#151): relation-personas og maskinel familiebekræf | 1 / 2 | 5 | 7 | Del 1 `produktionsverificeret` for 2018-20 som del af 5a/5b-rækken (2026-10-25, GO 2; i restore 2026-10-11, me |
| Trin 5b del 2a (#151): relationsbindinger og kildevisning | 1 / 1 | 0 | 5 | `produktionsverificeret` for 2018-20 (2026-10-25, GO 2; i restore 2026-10-11). |
| Trin 5b del 2b-i (#151): ægtefælle-undtagelser, kø og genbinding | 1 / 1 | 2 | 4 | `produktionsverificeret` for 2018-20 (2026-10-25, GO 2; i restore 2026-10-13). |
| Trin 5b del 2b-ii (#151): nye afdøde ægtefæller, klausul-disposit | 1 / 2 | 7 | 12 | 2b-ii og runde 2 (navneregel v3) begge `produktionsverificeret` for 2018-20 (2026-10-25, GO 2; i restore 2026- |
| Trin 5b del 2b-iii (#151): børnehenvisninger | 1 / 1 | 2 | 3 | `produktionsverificeret` for 2018-20 (2026-10-25, GO 2; i restore 2026-10-20). 5c-1-opfølger #270 (V-82..V-92  |
| #244 (5b): ægteskabsnumre | 1 / 1 | 3 | 6 | Nummereringen: `produktionsverificeret` for 2018-20 (2026-10-25, GO 2). Rettelsesvejen: `isoleret implementere |
| Indholds-id (#151, forudsætning for overførslen) | 1 / 1 | 0 | 4 | `i prod` (DDL 2026-10-22, GO 1; data 2026-10-25, GO 2) - OBS: `i prod` er ikke en af de fire tilladte modenhed |
| Overførsel plan A (#151): DDL-ceremonien for 5a+5b | 1 / 1 | 3 | 3 | `i prod` (DDL, 2026-10-22, GO 1); `docs/database-current-state.md` §10. |
| Overførsel plan B1 (#151): værktøj til data-ceremonien | 0 / 1 | 21 | 7 | `i prod` (brugt i GO 2, 2026-10-25). |
| Overførsel plan B2 (#151): data-ceremonien for 5a+5b | 0 / 1 | 8 | 5 | `i prod` (data, 2026-10-25, GO 2); `docs/database-current-state.md` §11. |
| Afbrydelser efter GO 2: dubletreglen, #240 dobbeltfamilier, GO 2-dublet, | 1 / 1 | 10 | 1 | Prod 2026-10-26 (`docs/database-current-state.md` §12 "LIVE i prod"): dubletregel-DDL + #240 + GO 2-dublet + # |
| Trin 5c-1 (#150): placement og membership for 2018-20 | 1 / 1 | 6 | 7 | status.md: "Placement og membership / `isoleret implementeret`" (forældet: 5c-1 er merget som #269, kode i mai |
| Review af trin 1-5 (Fable-review, roadmap-krav før trin 6) | 1 / 1 | 0 | 0 | Specificeret/under arbejde (gren `docs/review-trin-1-5`). |
| Trin 6: kæden ende-til-ende på begge referenceudgaver (kun specif | 0 / 0 | 0 | 0 | Ingen spec/plan i repo. status.md: kæden "ikke integreret ende-til-ende"; samlet dom "NO-GO som generel levera |
| Trin 7: tredje årbog (kun specificeret) | 0 / 0 | 0 | 0 | Status.md: "Tredje-årbogsprøve / `specificeret`" - "ikke gennemført". Mål-arkitektur: teknisk-maalarkitektur.m |

## Forældreløse og usikkert placerede filer

Ingen kode- eller SQL-fil i de optalte mapper (skill-scripts, `tests/sql|integration|testthat|ci`, `R/`, `tools/`, rod-SQL) forblev uden enhed, men placeringen er et navnemønster, ikke en dokumenteret ejer. Svagest funderede placeringer (reviewer bør verificere):

- **Delt mellem trin 4 og 5a/5b-overførslen:** `transfer_baseline.sql`, `transfer_untouched_hash.sql`, `transfer_restore_*.sql`, `transfer_pack*.py/.sql`, `transfer_steps.py`, `transfer_answers.py` ligger under B2; `interpretation_transfer_digests.sql`, `tests/sql/transfer-decide-bind.sh`, `test-transfer-baseline.sql` under trin 4 (2018-20-overførslen plan A/B 2026-10-04) eller B2. Navnene `transfer_*` bruges af begge ceremonier.
- **Tværgående testfixtures:** `tests/sql/evidence-promotion-bootstrap.sql`, `run-db-verify-disposable.sql`, `reimport-writer-v2-bootstrap.sql` bruges af næsten alle DB-jobs (står under trin 2). `tests/sql/inspect-*.sql` og `lib-transfer-5ab.sh` ligeså.
- **1939-navngivne filer der funktionelt er forløbere for generelle trin:** `apply_reimport_1939_v50*`, `apply_name_completion_1939_v50*` (trin 2), `materialize_*source_personas*_1939_v50.py`, `materialize_*identity_decisions*` (5a), `build_source_evidence_*` er derimod generelle (trin 3). Alle `*1939*`/`c3` er samlet under S3.
- **Rod-SQL:** `db-migrations-c3-identity.sql` (S3), `db-backfill-foraeldrefamilie.sql`, `db-rollback-fase2/3.sql`, `db-rollback-foraeldrefamilie.sql` (S1) — ingen entydig spec fundet uden at åbne dem.
- **Ikke enumereret fil for fil (kun mappenavn):** `.claude/skills/daa-extract/references/` (JSON-skemaer, prompts, `reimport-profiles/`), `.claude/skills/daa-extract/scripts/{tests,fixtures,sandbox}/`, `.claude/skills/daa-haendelser/{agents,references}`, `.claude/skills/daa-presens/references`, `tests/fixtures/*` (inkl. `transfer-pack`), `data/` (indhold ikke åbnet), `design/`, `design_handoff_redaktion_mobile/`, `docs/superpowers/reviews/` (25 filer), `docs/reviews/`, `docs/superpowers/handovers/`.
- **Docs uden enhed:** `docs/evidensbaseret-genimport/{vision,roadmap,status,teknisk-maalarkitektur}.md` er styrende, ikke enhedsbundne.
- **Helt udenfor kortet (afgrænsning):** `web/`, `mobile/`, `packages/`.

## Uklarheder og observationer under kortlægning (ingen vurdering)

1. **status.md er ikke ajour for 5c-1 og enkelte rækker.** Rækken "Placement og membership" står som `isoleret implementeret`, mens 5c-1 er merget (#269, git-log) og har runbook (`150-placement-prod.md`) med GO 1/GO 2-trin; hverken status.md, `database-current-state.md` (sidste afsnit er §12/§11 for 2026-10-26/25) eller changelog nævner 5c. Rækken "Klausulgranularitet og coverage" står `specificeret`, mens klausullaget er i prod (§8/§9) og trin 4 er `produktionsverificeret`. Det er uklart, om 5c-1 er i prod (kun runbook + kode findes i eksporten).
2. **Modenhedsvokabularet er ikke ensartet.** Roadmap tillader fire tilstande; status.md bruger også `i prod` (indholds-id, plan A/B1/B2), `produktionsverificeret for 2018-20 (… i restore …)` og delte tilstande (#244: nummering vs. rettelsesvej). #240/GO 2-dublet/#248 har ingen modenhedsrække, kun header-prosa og `database-current-state.md` §12 (nummereret før §11).
3. **Testdækning i CI er ujævn og kun delvist synlig.** 26 filer i `tests/sql|integration` har ingen reference i ci.yml (bl.a. alle `test-*-upgrade.sh` (7), alle C3-identitets-/lock-order-tests, `test-reimport-interpretation-proposal.R`); i skill-mappen kører kun 34 af 112 `test_*.py` i python-jobbet, og alle 19 `test_*.R` samt `.mjs` i skill-mappen er hverken i CI eller i `run-tests.R` (kører kun `tests/testthat`). De fleste ikke-dækkede filer er 1939-sporet og trin 4's ældre builders. Om de køres manuelt/lokalt kan ikke ses i repoet.
4. **Enhedsgrænser mellem plan A/B og trin 4/5a er flydende.** Spec `2026-10-21-trin5ab-2018-20-prod-overfoersel-design.md` dækker både 5a, 5b og overførslen; plan B1/B2 har ingen egen spec/bevisfil — beviset ligger i status.md-tillæg 2026-10-25 og runbooks. Trin 4's overførsel (2026-10-03/04) og 5a+5b-overførslen (2026-10-21..23) deler `transfer_*`-værktøjer.
5. **Tal der ikke er verificeret her:** web/mobil-RPC-listen i S4 er fra et simpelt grep på `rpc('…')`; DB-linjenumre er første CREATE-forekomst (migrationsfilen kan have flere redefinitioner; mange funktioner er `CREATE OR REPLACE` flere steder).

## Læste filer

Helt eller delvist læst (indhold): `docs/evidensbaseret-genimport/roadmap.md` (linje 27-86), `docs/evidensbaseret-genimport/status.md` (hele, linjer afkortet til 400 tegn), `docs/database-current-state.md` (overskrifter + §1 uddrag + §12 linje 532-557), `docs/superpowers/specs/2026-10-26-trin5c-placement-membership-design.md` (linje 1-60 + overskrifter), `docs/runbooks/150-placement-prod.md` (linje 1-12), `_issues.txt`, `.github/workflows/ci.yml` (grep på job-/test-linjer), `tools/foraeldrematch/README.md` og `tools/kalibrering/README.md` (5 linjer), `tests/testthat/{test-extract,test-load-daa,test-haendelse-merge,helper-source}.R` (4 linjer), `run-tests.R`, de første 3 linjer af 17 SQL-filer i skill-scripts (`relation_*.sql`, `identity_*_rows.sql`, `spouse_exception_rows.sql`, `transfer_*.sql`, `interpretation_control_rows.sql`), `evidenspas_v2.py` og `build_eligible_selection.py` (første 12 linjer), `db-migrations.sql` (kun grep-ankre), `docs/decisions.md` (grep).
Kun `ls`/`grep`/filnavne: alle øvrige scripts, tests, specs, planer, bevis-filer, runbooks, `schema.sql`, `db-migrations.sql` (CREATE-linjer), `docs/changelog.md` (grep). Ikke læst: `work*/`, `~/.private/`, dumps, manifester, kontrolark, tokens, `.env*`. Der er ikke kørt databaseforespørgsler eller netværkskald.
