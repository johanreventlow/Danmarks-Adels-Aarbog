# DAA 1939 v50 — review af de 17 resterende identitetsrecords

Dato: 2026-08-17
Kodegrundlag: `f907cfbb97c9d4487c73217bb2015eaa5eebc11b` før denne dokumentationsændring

## Konklusion

Det hashbundne review, den lukkede beslutningsmaterialisering,
source-persona-materialisering v2 og den read-only database-preview er
reproducerbare og komplette inden for deres afgrænsede formål:

- reviewmanifest: `GO`, 17 subjects og 543 mapped + 23 database-only = 566 profiler;
- beslutninger: `READY`, 8 samme eksisterende, 8 nye personkandidater, 1
  strukturel/summary og 0 uafgjorte;
- source-persona v2: `GO`, 24 v1-rækker bevaret deep-equal og 8 append-only
  personaer, i alt 32;
- live database-preview: read-only kontrol gennemført med 543/543 baselineankre,
  32/32 personamål og 0 target mismatch.

Den faktiske reimport er **NO-GO**. Ingen af de grønne review- eller previewgates
giver canonical-, database-, person-create-, writer-, replay- eller
deployautoritet. `database_write_authorized` og
`canonical_mutations_authorized` er `false` hele vejen.

## Reproducerbar kommandokæde

Kør fra worktree-roden. Output oprettes eksklusivt; brug nye suffikser i stedet
for at overskrive de viste, private filer.

```bash
/usr/bin/python3 -B .claude/skills/daa-extract/scripts/build_remaining_identity_review_1939_v50.py \
  --source-personas=work/task23-1939-v50-source-personas/source-persona-materialization-v1.json \
  --import-preview=work/task21-1939-v50-import-preview/import-preview-v1.json \
  --database-preview=work/task21-1939-v50-import-preview/database-preview-v1.json \
  --database-profiles=work/task22-1939-v50-identity-review/database-profiles-v1.json \
  --clean=/Users/johanreventlow/TypeScript/danmarksadelsaarbog/work_1939_stamtavle/clean_1939_v3.json \
  --boundary-materialization=work/task20-1939-full/boundary-materialization-v3-ditlev.json \
  --calamari=/Users/johanreventlow/TypeScript/danmarksadelsaarbog/work_1939_stamtavle/full_ocr_calamari_r6_clean.txt \
  --output=work/task24-1939-v50-remaining-identities/remaining-identity-review-v1.json \
  --report=work/task24-1939-v50-remaining-identities/remaining-identity-review-v1-report.md \
  --expected-subjects=17 \
  --expected-mapped-profiles=543 \
  --expected-database-only-profiles=23

/usr/bin/python3 -B .claude/skills/daa-extract/scripts/materialize_remaining_identity_decisions_1939_v50.py \
  --review work/task24-1939-v50-remaining-identities/remaining-identity-review-v1.json \
  --proposal work/task24-1939-v50-remaining-identities/remaining-identity-proposals-v1.json \
  --import-preview work/task21-1939-v50-import-preview/import-preview-v1.json \
  --database-preview work/task21-1939-v50-import-preview/database-preview-v1.json \
  --output work/task24-1939-v50-remaining-identities/remaining-identity-decisions-v1.json \
  --report work/task24-1939-v50-remaining-identities/remaining-identity-decisions-v1-report.md \
  --expected-decisions 17

/usr/bin/python3 -B .claude/skills/daa-extract/scripts/materialize_remaining_source_personas_1939_v50.py \
  --source-personas-v1 work/task23-1939-v50-source-personas/source-persona-materialization-v1.json \
  --remaining-decisions work/task24-1939-v50-remaining-identities/remaining-identity-decisions-v1.json \
  --database-preview work/task21-1939-v50-import-preview/database-preview-v1.json \
  --output work/task24-1939-v50-remaining-identities/source-persona-materialization-v2.json \
  --report work/task24-1939-v50-remaining-identities/source-persona-materialization-v2-report.md

Rscript .claude/skills/daa-extract/scripts/preview_reimport_1939_v50.R \
  --input=work/task21-1939-v50-import-preview/import-preview-v1.json \
  --source-personas=work/task24-1939-v50-remaining-identities/source-persona-materialization-v2.json \
  --source-personas-sha256=450e2dae158573131d19333be3cebefe36bf6a5d269c7ff0059e17c5fcafa97c \
  --output=work/task24-1939-v50-remaining-identities/database-preview-v3.json \
  --report=work/task24-1939-v50-remaining-identities/database-preview-v3-report.md \
  --expected-database=postgres \
  --source-edition='DAA 1939'
```

Credentials læses af R-processen fra miljøet/`~/.Renviron`; de må ikke tilføjes
til kommandoer, JSON eller Markdown.

## Kilder og SHA-256

Alle nedenstående bytehashes er genberegnet direkte med `shasum -a 256`.

| Artefakt | SHA-256 |
|---|---|
| source-persona materialization v1 | `07756ef4faf17561cf84095c5abe47919064d72ceecd3e1d9f725281ab0b172d` |
| import-preview v1 | `04f2780b4fc3f63263324cbb5133e07d1eed70018f7ea11212597a26cc196ca5` |
| database-preview v1 | `a00efd43a34358f95f4b0df40695f4abd3b279066bee196e3cbdbd1b87b9e97c` |
| database-profiler v1 | `67398a6f7faadb42e284ac77769c3261f69eacf37ac1c1ebc2ef5da1a76df9f1` |
| clean v3 | `c68ace8bffd8d653c4af0aa24586c5c01c3d1f267efe74d546ddddd964b3551b` |
| boundary-materialization v3 | `73aa0eecb365de35b8e5ca38af87c7b247fbdd7d14e2ece358d86e4680056b4f` |
| Calamari r6 | `020123a3588dacf80705a22fb021ab4f5da97b8de202e8664304ca01f9a6da37` |
| inspiceret 1939-stamtavle-PDF | `cf10e9e52a22297e600e598213f4c40c870ffcc4df86a6e1b09ec1bb1d06904e` |
| remaining review v1 JSON | `5b8d845ad1808cf450497856373e961cd3cf1fbbac23275bfa69adc301f34c1f` |
| remaining review v1 Markdown | `a3673e14ec04dc553c29925384942f15386222155cc791c612686ece4a9f3f66` |
| remaining proposals v1 | `fcf7947b139ca637f2065815c817c8efdd24fda651942aa658d6c95cbc28afae` |
| remaining decisions v1 JSON | `a86b508205ca413f1c7f4af2f747b320f9f77bde7fb686dc10cf343b16565ebe` |
| remaining decisions v1 Markdown | `71cb7d2a48e042dc3c38ca05bc1ad6fda6bee7126e9354c0c6968d3bf89005d8` |
| source-persona v2 JSON | `450e2dae158573131d19333be3cebefe36bf6a5d269c7ff0059e17c5fcafa97c` |
| source-persona v2 Markdown | `461537ee73f2937f2b5de79e38883a4dafb2d48a9e6e1637ca543f996e188397` |
| live v3 final A JSON | `279fcb9969f9a4371d995e97c4fffa55589289bcc34a000c03e2bdca29714e6c` |
| live v3 final A Markdown | `1e1c7dcfec444913b3fb97514e9fe5155e41c38034dff0334abc0d28eb61d16c` |
| live v3 final B JSON | `3ee66ff9d2b914fe8cb07587b5cf02c0e3586beed80f4d29258302476bb0026a` |
| live v3 final B Markdown | `479f602a78dac377a9a4f0fb6ce8681cc7c52f1dfd6bbfe767b91fafe261be2a` |

Live A og B er semantisk identiske efter fjernelse af `snapshot_at`; den låste
semantiske SHA-256 er
`343fb43e8f10476967c5ff981f56380c672fc23234638076ec5c5c97a61925a8`.
Kilde-PDF'en er den u-krypterede 86-siders fil
`/Users/johanreventlow/TypeScript/danmarksadelsaarbog/Dansk Adels Aarbog - Reventlow 1939 stamtavle.pdf`.

## Disposition af alle 17 source records

PDF-side er trykt/source page fra det hashbundne boundary-manifest. Evidensbasis
er dispositionens lukkede, reproducerbare reason; hver række er desuden bundet
til source span, ordret Calamari-tekst, verbatim-hash, review-hash og
evidenshash i forslaget/beslutningsartefaktet.

| # | Source record | PDF-side | Beslutning | Target/person eller owner | Evidensbasis |
|---:|---|---:|---|---|---|
| 1 | `record-e63debca-6fb4-456e-9b11-90a8676d98b8` | 498–499 | `same_existing_person` | `0f45c192-9fc4-4823-abef-00ae175fe297` / person `934` | PDF + Calamari-hierarki + database-only-profil stemmer |
| 2 | `record-c0e8f5ad-1b06-4b7e-aea5-5aaf7738f968` | 499 | `same_existing_person` | `80960791-c231-4bf7-b3e2-74195a48ceb3` / person `935` | PDF + Calamari-hierarki + database-only-profil stemmer |
| 3 | `record-9db9004f-d6a7-4b98-bd0f-f1f90ba770d8` | 499 | `same_existing_person` | `1f075502-0ea9-485c-b508-31a8dce99229` / person `929` | PDF + Calamari-hierarki + database-only-profil stemmer |
| 4 | `record-6fe0fbac-d360-4f26-a531-3e0aa62fcbdb` | 499 | `same_existing_person` | `721fd282-7000-48c5-bd66-66cde44c5da1` / person `930` | PDF + Calamari-hierarki + database-only-profil stemmer |
| 5 | `record-3766faae-ae21-412a-8cfb-745a19ac77f0` | 503 | `new_person_candidate` | — | PDF + Calamari-hierarki viser særskilt person; intet eksisterende anker |
| 6 | `record-4ba8b3b2-a4d4-40e6-b4f9-1a0aaf8b4cfa` | 504 | `structural_or_summary` | owner `record-26a2adfa-5218-46eb-9ec7-4377144697d4` | linjeintroduktion med entydig context owner |
| 7 | `record-7f274857-98d6-4ef8-a186-c71c26d6ccd0` | 504 | `same_existing_person` | `85e9fb68-f2cb-41ed-a6bc-ab45e00915ca` / person `1040` | eksplicit regel: senere fuld person foretrækkes frem for summary-dublet |
| 8 | `record-43d4974a-0532-421d-a3fb-8e7c575a67e7` | 506 | `new_person_candidate` | — | PDF + Calamari-hierarki viser særskilt person; intet eksisterende anker |
| 9 | `record-8f346104-cf3c-465f-bfa3-efb78be436b2` | 506 | `new_person_candidate` | — | PDF + Calamari-hierarki viser særskilt person; intet eksisterende anker |
| 10 | `record-b626f5ff-f2fb-4061-bfce-988dbddec846` | 506 | `new_person_candidate` | — | PDF + Calamari-hierarki viser særskilt person; intet eksisterende anker |
| 11 | `record-80180a6e-2cc6-4968-81ca-004b6662d8ce` | 506 | `new_person_candidate` | — | PDF + Calamari-hierarki viser særskilt person; intet eksisterende anker |
| 12 | `record-a1f4547d-16cc-4110-ad1b-fa3ff1c59a58` | 508 | `new_person_candidate` | — | PDF + Calamari-hierarki viser særskilt person; intet eksisterende anker |
| 13 | `record-89a932c8-7b52-4f5c-9e00-0f2b62ee4422` | 508 | `new_person_candidate` | — | PDF + Calamari-hierarki viser særskilt person; intet eksisterende anker |
| 14 | `record-f7fce8f9-0657-4e6c-877a-58e8777016ff` | 508 | `same_existing_person` | `2f3e2489-4710-4bef-b753-684da5ef18dc` / person `960` | summary + senere mapped fuldprofil stemmer |
| 15 | `record-a86ed385-5a8e-466b-aa60-e6fdfc539277` | 508 | `same_existing_person` | `fd1c45fe-1283-499e-8a86-ab5164a391ae` / person `1121` | eksplicit regel: senere fuld person foretrækkes frem for summary-dublet |
| 16 | `record-a601ad9a-cbe3-4767-bc03-d8b77bf16165` | 508 | `same_existing_person` | `16a59f2f-9ca0-4e05-936d-9b95887d9470` / person `1123` | summary + senere mapped fuldprofil stemmer |
| 17 | `record-c731fc5a-7e4c-45b8-9bfc-d6eba9f62e5d` | 517 | `new_person_candidate` | — | PDF + Calamari-hierarki viser særskilt person; intet eksisterende anker |

De to eksplicitte summary-dubletafgørelser er fuldt bevaret som ikke-autoriserende
proveniens:

- record 7 valgte person `1040` frem for database-only record
  `13a42804-65f5-4b78-8e1a-34463ac2a141` / person `1013`;
- record 15 valgte person `1121` frem for database-only record
  `d636eaa4-1b00-485b-a639-f09ef2437c35` / person `963`.

Begge har `authorized: false`; de udfører ingen merge eller canonical mutation.

## Live read-only database-preview

Begge endelige sessions startede `BEGIN READ ONLY`, rapporterede
`transaction_read_only=on`, brugte kun det eksakte 24-statement SQL-register og
gik gennem den ubetingede rollback/lukning, før de lokale output blev skrevet.

| Kontrol | Resultat |
|---|---:|
| baselineankre matched/missing/collisions | 543 / 0 / 0 |
| source-persona targets matched/mismatch | 32 / 0 |
| new person candidates | 8 |
| structural/summary | 1 |
| unresolved | 0 |
| family rows | 333 |
| komplette family members | 1.002 |
| family facts | 222 |
| family facts citeret til DAA 1939 | 222 |
| canonical mutations authorized | false |

Family facts er 222 source-only, 0 editorial-only, 0 both og 0 neither.
`source_persona_materialization_gate: GO` betyder kun, at 24 deep-preserved + 8
append-only personaer er internt konsistente. Manglende private tabeller gør
den faktiske persona-databasesammenligning unavailable; de 32/32 target checks
er de friske canonical record/person-anchor checks, ikke inserts.

## Gates og resterende blockers

Afgrænsede gates:

- `review_gate: GO` — reviewpakken er komplet og hashbundet;
- beslutningsmaterialisering: `READY` — 17/17 lukkede beslutninger, 0 uafgjorte;
- `source_persona_materialization_gate: GO` — 24 + 8 = 32 og ingen lineage-drift;
- read-only preview: `READY` som diagnostisk snapshot med
  `transaction_read_only=on` og semantisk identiske dobbeltkørsler;
- `dry_run_gate: NO-GO`, `database_gate: NO-GO`, `reimport_gate: NO-GO`.

Det live artefakt bevarer præcis disse blockers:

```text
database_capability_blocker:private.source_record
database_capability_blocker:private.source_persona
unmapped_existing_1939_person_records:23
genuinely_new_person_creation_pending:8
fact_provenance_pending:130
marriage_provenance_pending:94
relationship_provenance_pending:81
production_writer_not_authorized
```

De 23 eksisterende 1939-personrecords uden v50-baseline-mapping er fortsat
synlige og må ikke fortolkes som tomme eller slettes. De otte nye
personkandidater er kun kandidater: personoprettelse kræver en særskilt godkendt
fase. Fact-, marriage- og relationship-proveniens er fortsat uafsluttet.
`load_daa.R` er hverken ændret eller kaldt, og der findes ingen autoriseret
production writer/replay/rollback/cutover-plan.

## Slutverifikation

Task 6 kørte frisk:

```text
cd .claude/skills/daa-extract/scripts && /usr/bin/python3 -B -m pytest -q
1646 passed, 3 skipped in 8.79s; exit 0

cd ../../../.. && Rscript run-tests.R
787 passed, 1 skipped, 0 warnings, 0 failures in 6.7s; exit 0
```

Derudover blev `git diff --check`, exact tracked-scope, Git-ignore,
credential- og canonical-authority-audits kørt før commit. De konkrete resultater
og commit-SHA står i den ignorerede Task 6-rapport.
