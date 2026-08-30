# #153: Live-kort over writer-/batchadaptere

**Dato:** 2026-08-30  
**Formål:** Read-only grundlag for #153 før implementeringsændringer.

## Fælles fund

- Narrative-contract version 2 er den første fælles gate for narrative-capable writers. Historiske C3- og 1939-writers afviser efter gaten med `NARRATIVE_RECORD_LEGACY_WRITER_DISABLED`.
- Direkte legacy-loader/updatere afviser efter version 2 med `NARRATIVE_RECORD_LOADER_MIGRATION_REQUIRED`.
- Den fælles #152-kernel er `private.mutate_person_narrative_record`; dens `upsert` producerer kun `draft_created` eller `draft_updated`, mens publicering/revision/withdrawal er særskilte operationer.
- Ingen eksisterende permanent, editionsneutral source-scoped authorization/batch/event-ledger findes. Den skal være adapterejet under `private`, ikke en fælles journal.

## Adapterkort

| Adapter | Levende state/RPC | Receipt/postverify | Adgang og låse | Eksisterende bevis |
| --- | --- | --- | --- | --- |
| C3 | `private.reimport_case_authorization/_batch/_event`; `red_authorize_reimport_cases`, `red_apply_reimport_cases`, `red_authorize_reimport_case_reversal`, `red_reverse_reimport_cases` | `private.reimport_case_receipt`, `private.reimport_case_reversal_plan` | v2 gate før C3-lock; C3 tager derefter persons, source records, narratives/bindings og relations i stabil rækkefølge | `tests/sql/test-1939-v50-c3-apply.sql`, `tests/integration/test-1939-v50-c3-apply.R`, `tests/integration/test-1939-v50-c3-writer-lock-order.R` |
| Evidens-promotion | `private.interpretation_promotion_rule/_batch/_promotion`; `red_preview_interpretation_promotions(jsonb)`, `red_promote_interpretations_batch(jsonb,text)` | Ingen terminal batchstatus eller receipt endnu; preview hash findes | Redaktionsrolle; private tabeller med RLS/revokes; validator låser fortolkninger i UUID-orden | `tests/sql/test-evidence-promotion.sql`, `tests/sql/evidence-promotion-bootstrap.sql` |
| Narrative-cutover | `private.apply_narrative_record_cutover(...)`, `private.narrative_record_contract`, `private.narrative_record_cutover_receipt` | Append-only nonce-receipt og `verify_narrative_record_cutover_postverify.R`; recovery er den rigtige replayvej | Eksklusiv `daa-narrative-record-contract` advisory lock før tables; kernel låser publications, legacy ledger/events, narrative/change_set og source evidence | `tests/sql/test-narrative-record-cutover.sql`, `tests/integration/test-narrative-record-concurrency.R`, `tests/testthat/test-verify-narrative-record-cutover-postverify.R` |
| Source-scoped replace | `load_daa.R --replace` og `replace_dryrun.R` er legacy/source-materiale; ingen v2-kompatibel DB writer | Ingen #153-receipt endnu; `replace_dryrun.R` er session-read-only | Legacy loader tager #152 shared gate og afviser v2 før write; #153 skal derefter tage source scope, people, records, narratives/bindings og egen ledger | `tests/testthat/test-load-daa.R`, `tests/testthat/test-update-1939-narratives.R`, `tests/testthat/test-update-2018-narratives.R`, `tests/integration/test-1939-v50-c3-writer-lock-order.R` |

## Lock- og dependency-konklusion

1. Cutover ejer den eksklusive narrative-contract gate; narrative-capable normale writers tager den shared og genlæser version.
2. C3 må ikke genåbnes: dens v2-gate er korrekt historisk conformance, ikke en migrationsskabelon.
3. Source replace skal bruge #152's `private.mutate_person_narrative_record('upsert',...)` for narrativeeffekt. Den må ikke opdatere `public.narrative` eller `private.narrative_record_publication` direkte.
4. Promotion deler person-/source-identitetsforudsætninger, men ikke narrative projection. #153 skal derfor dokumentere en fælles, cykelfri lock-prefix før adapterens lokale låse og bevise den med tværadapterræs.
5. Cutover, source replace og promotion skal have separate receipts/current-state-verifiers; en fælles canonical helper er tilladt, en fælles eventtabel er ikke.

## Task-1 GO

Kortet dækker alle fire adaptere, deres levende schema/RPC/RLS-/receiptflader, eksisterende tests og de nye dependencies. Implementering kan fortsætte til Task 2, men kun efter den eksplicitte plan-godkendelse og med dette kort opdateret, hvis levende interfaces afviger.

