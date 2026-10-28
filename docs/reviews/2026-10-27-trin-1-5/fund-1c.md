# Spor 1c — Python/R-kvalitet og tests (fund)

Alle stier er relative til `EKS`. Tests er kørt lokalt i EKS uden net og uden database (Python 3.9 fra Xcode,
`PYTHONDONTWRITEBYTECODE=1`; R med `Rscript --vanilla` og `R_ENVIRON_USER=/dev/null`, så `~/.Renviron` ikke blev læst).

## 1. Sammendrag

- P1: `load_presens.R --reset` er en uvagtet `TRUNCATE … CASCADE` mod prod, og flaget står i SKILL.md (1c-01).
- De 2 røde Python-tests skyldes miljøet (`rg`/`node` mangler på PATH), ikke koden. Ingen skipif, ingen i CI (1c-03).
- De 2 R-tests uden testthat-wrapper er røde: forældede efter #153 og erstattet. Slet dem (1c-04).
- Kernen har ingen direkte CI-dækning: CI kalder 0/30 funktioner i `validate.py`, 1/25 i `segment.py` (1c-02).
- Fase 0's 110 er forkert begge veje: 15/17 R + 4 SQL kører i CI; der står 73 Python-tests uden for, ikke 71 (1c-06).
- `db-migrations-c3-identity.sql` ville rulle #152-vagterne tilbage. Kendt fra review 35 S6, stadig ikke lukket (1c-05).
- Trin 2-5's tests er ægte adfærdstests med syntetiske data. Problemet er, hvad der kører, ikke kvaliteten.
- Overbygning: 64 % af `daa-extract/scripts` er 1939/C3-engangskode blandet med den levende pipeline (1c-07).
- relation_persona_extract v1/v2/v3 er levende, låste profiler (skemaet accepterer alle tre). Behold dem (1c-10).

## 2. Fund

### 1c-01 · Præsens-load (forarbejde S2) · Alvor: P1
- **Sted:** `.claude/skills/daa-presens/scripts/load_presens.R:19-23`, `:139-141`; `.claude/skills/daa-presens/SKILL.md:85-90`
- **Påstand:** Præsensloaderen kan tømme hele prod-modellen med ét flag. Der er ingen vagt, og ukendte argumenter
  afvises ikke.
- **Evidens:** `RESET <- "--reset" %in% argv` (l. 23), derefter
  `if (RESET) { … ex(paste0("TRUNCATE ", paste(model_tables, collapse=", "), " CASCADE;")) }` (l. 140-141). Tabellerne
  omfatter `person`, `narrative`, `source` m.fl. (l. 58-60), og `CASCADE` rammer alt, der har en fremmednøgle til dem.
  Login kommer fra `SUPABASE_*` (l. 46-51), dvs. prod. Til sammenligning afviser `load_daa.R:311-326` en RESET, hvis
  der findes redaktionelle change_sets (kræver `--force-reset`). Den har også en streng argumentparser
  (`load_helpers.R:68ff`) og et sslmode-værn (`load_daa.R:100-104`). `supabase_load.R` blev pensioneret netop for
  »RESET uden guards« (`supabase_load.R:2-4`). SKILL.md:89-90 anbefaler `--reset` »kun hvis du vil starte forfra«.
- **Konsekvens:** En fejlskrevet kommando sletter trin 1-5's evidenslag i prod. Det gælder source records,
  publication-events, personas og bindinger. Free-tier har ingen backup. Loaderen skriver desuden uden om hele
  writer-/batchmekanismen (trin 2) og uden import-key, gate eller manifest. Det er en konkurrerende skrivevej, som ikke
  er frosset, i modsætning til `backfill_slaegtled.R:82-89` (LegacyBackfillFreeze).
- **Forslag:** Fjern `--reset` helt. Hvis det skal bevares, så genbrug `load_daa.R`'s guard plus `--jeg-mener-det`,
  og afvis ukendte argumenter. Frys præsensloaderen som skrivevej, indtil præsenslister går gennem den generelle
  writer (trin 6/7), og notér det i SKILL.md.
- **Sikkerhed:** verificeret for flaget og TRUNCATE-kæden (filen er læst fuldt, ikke kørt). CASCADE's rækkevidde ind i
  `private`-tabellerne er sandsynlig, ikke efterprøvet mod `schema.sql`. Alene `person`/`source`/`narrative` bærer P1.

### 1c-02 · CI-dækning af importens kerne · Alvor: P2
- **Sted:** `.github/workflows/ci.yml:142` (fast pytest-liste); `.claude/skills/daa-extract/scripts/test_validate.py`;
  `packages/core/src/__tests__/ocrKvalitet.test.ts:11-12`; `.claude/skills/daa-extract/scripts/build_legacy_migration_manifest.py:7`
- **Påstand:** De moduler, som levende og generel kode bygger på, har grønne tests, men de kører ikke i CI. Årsagen er,
  at Python-jobbet bruger en håndskrevet filliste i stedet for `discover`.
- **Evidens:** En funktions-tracer over CI's 39 testfiler (1.137 tests) gav: `validate.py` 0/30 funktioner kaldt,
  `segment.py` 1/25, `normalize_narrative_1939_v50.py` 4/7 og `clause_ledger.py` 3/7. Kun `derive_date_info` i
  `validate.py` rammes indirekte via daa-haendelsers `unittest discover`
  (`daa-haendelser/scripts/validate_haendelser.py:125`). `ocrKvalitet.test.ts:11-12` erklærer et tværsproget
  paritetskrav: »samme fixture bestås af TypeScript (her) og Python (test_validate.py)«. Kun TS-halvdelen kører.
  `build_legacy_migration_manifest.py` (trin 3, i CI) importerer `normalize_narrative_v1`, men normaliseringens egne 31
  tests er ikke i CI. Den CI-kørte test (`test_build_legacy_migration_manifest.py`) har intet tilfælde, hvor to
  forskelligt formaterede tekster normaliseres til ens.
- **Konsekvens:** En regression i segmentering, validering eller `narrative_norm_v1` bliver ikke fanget af CI. Det er
  netop de led, trin 6 (begge udgaver ende-til-ende) og trin 7 (tredje årbog) genbruger. Hver ny testfil falder
  stiltiende uden for CI, medmindre nogen husker at tilføje den til linje 142.
- **Forslag:** Tilføj mindst `test_validate.py`, `test_lokator.py`, `test_segment.py`, `test_segment_slaegtled.py`,
  `test_ordinals.py`, `test_clause_ledger.py`, `test_normalize_narrative_1939_v50.py`, `test_escalate_merge.py`,
  `test_build_narrative_record_cutover_review.py` (trin 1), `test_build_eligible_selection.py` (trin 4's »alle
  eligible«-udvalg) og `test_source_record_ledger.py`. Det koster få sekunder (alle kører under 0,3 s). På sigt: skift
  til `discover` med en eksplicit udelukkelsesliste for 1939-engangstests.
- **Sikkerhed:** verificeret (målt og kørt).

### 1c-03 · De »2 røde« Python-tests · Alvor: P3
- **Sted:** `.claude/skills/daa-extract/scripts/test_convert_c3_decisions_1939_v50.py:55-79`;
  `.claude/skills/daa-extract/scripts/test_build_c3_html_review_1939_v50.py:386-392` (også `:468`, `:545`, `:682`, `:1108`)
- **Påstand:** Begge fejl skyldes miljøet. Koden er i orden.
- **Evidens:** `subprocess.run(["rg", "-n", NO_WRITER_PATTERN, …])` gav `FileNotFoundError: 'rg'`. I dette miljø findes
  `rg` kun som shell-funktion, og subprocess ser den ikke. Med en `rg`-shim på PATH: 64 passed.
  `subprocess.run(["node", str(runnable)], check=True, …)`: med `PATH=/usr/bin:/bin` fejler de samme 9 tests, med
  `node` på PATH bliver det 95 passed. Fase 0's tomme miljø havde altså hverken `rg` eller `node`. Samme mønster findes i
  CI's egen liste: lokalt fejler 3 af 1.140 CI-tests (`test_clause_readers.py` ×2,
  `test_compare_clause_evidence_projection.py` ×1), fordi de kræver en git-checkout (`git ls-files`), og eksporten er
  ikke en git-mappe. I CI er de grønne.
- **Konsekvens:** Ingen fejl i produktkoden. Testene erklærer ikke deres afhængigheder, så et manglende værktøj ligner
  en regression. C3-»no-writer«-revisionen er en sikkerhedspåstand, og den håndhæves ingen steder.
- **Forslag:** `pytest.mark.skipif(shutil.which("rg") is None, …)` og tilsvarende for `node`. Alternativt: erstat
  `rg`-kaldet med Pythons `re` over filerne, så testen er selvbærende.
- **Sikkerhed:** verificeret (kørt begge veje).

### 1c-04 · Forældede R-tests uden for CI · Alvor: P2
- **Sted:** `.claude/skills/daa-extract/scripts/test_apply_reimport_1939_v50.R:24-28`;
  `.claude/skills/daa-extract/scripts/test_apply_name_completion_1939_v50.R:1-7`;
  `.claude/skills/daa-extract/scripts/apply_reimport_helpers.R:182-193`
- **Påstand:** De to eneste R-tests i skill-mappen uden testthat-wrapper er røde. Fase 0 opdagede det ikke, fordi den
  ikke kørte R.
- **Evidens:** `Rscript --vanilla test_apply_reimport_1939_v50.R` gav `Fejl: REIMPORT_DATABASE_PROFILE_MISMATCH`. Testens
  `fake_gateway` returnerer `invisible(NULL)` for `preflight`, men 1939-adapteren delegerer nu til den generelle
  `execute_reimport`. Den kræver en preflight med `database_identity`, `actor_id` m.fl. (`apply_reimport_helpers.R:182-192`).
  `test_apply_name_completion_1939_v50.R` gav `subscript out of bounds` inde i `execute_name_completion_generic`
  (samme årsag). Begge adaptere er stadig dækket i CI af `tests/testthat/test-apply-reimport-1939-v50.R`,
  `tests/testthat/test-apply-name-completion-1939-v50.R` og `tests/integration/test-1939-v50-{production-writer,name-completion}.R`.
  Planerne angiver de røde filer som verifikationskommando
  (`docs/superpowers/plans/2026-08-18-1939-v50-production-writer.md:475`, `…-name-completion.md:183`).
- **Konsekvens:** Den, der følger planens verifikation, får rødt og kan tro, at writeren er i stykker. Det er død vægt,
  som ser ud som dækning.
- **Forslag:** Slet begge filer. Testthat- og integrationsversionerne dækker samme adapter.
- **Sikkerhed:** verificeret (kørt; årsag fundet i koden).

### 1c-05 · Forældet C3-deployartefakt og C3-identitetssuiten · Alvor: P2
- **Sted:** `db-migrations-c3-identity.sql:1-5`; `tests/sql/inspect-1939-v50-c3-identity-deploy.sql`;
  `tests/sql/test-1939-v50-c3-identity-deploy-contract.sql:1-40`; `docs/reviews/35-helhedsreview-genimport-2026-09-25.md:459-463`
- **Påstand:** Filen hævder at være et byte-ens spejl af `schema.sql`, men den er forældet. Den kontrol, der skulle
  fange netop det, kører ingen steder.
- **Evidens:** Hovedet siger »Function bodies are the bounded deploy mirror of current schema.sql; the checked-in
  inspect-1939-v50-c3-identity-deploy.sql serializer enforces byte-exact endpoint parity«. Jeg sammenlignede de 28
  funktionskroppe (whitespace-normaliseret): 3 afviger fra `schema.sql` (`red_slet_person`, `red_fortryd_change_set`,
  `red_apply_1939_v50_name_completion`). `red_slet_person` mangler #152-låsen og
  `RAISE EXCEPTION 'PERSON_HAR_NARRATIVE_PUBLICATION_HISTORY'`. `red_fortryd_change_set` mangler
  publication-event-routingen. Filen har ingen fail-closed-vagt mod genanvendelse, og ingen runbook nævner den. Hele
  C3-identitetssuiten (5 SQL-tests, 6 integrationstests, 2 inspect-filer) bruger `\ir ../../db-migrations-c3-identity.sql`
  og kører ikke i CI. Review 35 (S6) anbefalede for en måned siden at markere eller arkivere filen.
- **Konsekvens:** Bliver filen kørt (»Apply to the pre-feature database state«), forsvinder #152's sletnings- og
  fortrydelsesværn stille. Det er latent (kræver en menneskelig fejl), men konsekvensen er et datatab, der ikke kan
  fortrydes.
- **Forslag:** Sæt en `DO $$ … RAISE EXCEPTION 'HISTORISK' $$` øverst, eller flyt filen og dens suite til et arkiv.
  C3-invarianterne (i `schema.sql`) kan i stedet testes mod frisk schema i et eksisterende CI-job.
- **Sikkerhed:** verificeret (sammenligningsscript kørt; kroppe diffet).

### 1c-06 · Fase 0's CI-dækningstal · Alvor: P2 (reviewets bevisgrundlag)
- **Sted:** `docs/reviews/2026-10-27-trin-1-5/maalinger.md:55` og tillæg D (`:146-257`); `systemkort.md:527`;
  `tests/ci/interpretation-proposal-db.sh:88`, `:102`;
  `.github/workflows/ci.yml:504`; `tests/testthat/test-apply-c3-1939-v50.R:1-7`
- **Påstand:** »110 ikke kørt af CI« er forkert i begge retninger, og systemkortets »alle 19 `test_*.R` … hverken i CI
  eller i `run-tests.R`« er forkert.
- **Evidens:** 15 af de 17 R-tests på D-listen sources af `tests/testthat/test-*.R`-wrappere (fx `source("test_apply_c3_1939_v50.R")`)
  og kører altså i CI's r-job. Kun 2 står reelt udenfor (1c-04). De to d2-filer var ikke på D-listen. `ci.yml:504` kører `test-relation-disposition`, `test-relation-persona-v3`,
  `test-relation-person-create-v3` og `test-content-uuid` via `for t in …; do psql … tests/sql/$t.sql`, og fase 0's
  tekstsøgning så ikke variablen. Systemkortet nævner også `test-reimport-interpretation-proposal.R` som »ingen
  reference i ci.yml«, men den kører via `tests/ci/interpretation-proposal-db.sh:88,102`, som CI kalder (`ci.yml:266`). Omvendt blev `test_validate.py` talt som dækket, fordi en TS-kommentar nævner den
  (`ocrKvalitet.test.ts:12`). `test_make_boundary_text_1939.py` står slet ikke på listen. Korrigeret: ca. 92 testfiler
  uden for CI (73 Python, 2 R i skill-mappen, ca. 17 i `tests/sql`+`tests/integration` ekskl. fixtures).
- **Konsekvens:** Andre spor, der bygger på 0a/0c, overvurderer R-hullet og undervurderer Python-hullet i kernen.
- **Forslag:** Ret tallene i fase 1-syntesen. Mål fremover dækning ved at køre, ikke ved at søge efter tekst.
- **Sikkerhed:** verificeret.

### 1c-07 · Organisering: 1939-engangskode blandet med levende pipeline · Alvor: P2
- **Sted:** `.claude/skills/daa-extract/scripts/` (fladt, ca. 387 filer); `maalinger.md:68-71`
- **Påstand:** Det meste af skill-mappen er historisk engangskode for én udgave, og intet i strukturen skiller den fra
  den levende, generelle kode.
- **Evidens:** 172 filnavne med `1939`/`c3_` udgør 74.698 af 116.372 linjer (64 %). Testene: 36.464 af 50.309 linjer
  hører til 1939. Fase 0's død-detektor (tillæg F) ser kun kode- og CI-referencer og kalder derfor levende CLI'er døde,
  fx `apply_reimport.R` (den generelle writer-CLI, brugt i `docs/runbooks/source-evidence-reimport-rehearsal.md` og
  `legacy-migration-reimport-rehearsal.md`) samt `segment_presens.py` og `validate_presens.py` (trin ② og ④ i
  `daa-presens/SKILL.md:34-36`).
- **Konsekvens:** Det er svært at se, hvad trin 6/7 må bygge videre på. Generelle kontrakter gemmer sig bag
  1939-navne (1c-08), og hver ny agent eller reviewer skal genkortlægge mappen.
- **Forslag:** Flyt den afsluttede 1939 v50/C0-C3/D1/D2-kæde (builders, materializers, convertere, apply-R'er og deres
  tests) til `archive/1939-v50/` med en README. Bevar kun de moduler, som levende kode importerer
  (`normalize_narrative_1939_v50`, `segment_1939` via `convert_1939_stamtavle`, `apply_reimport_1939_v50_helpers.R`,
  så længe CI's integrationstest bruger den).
- **Sikkerhed:** verificeret (optalt); arkivforslaget er en vurdering.

### 1c-08 · Generel kontrakt bag udgavenavn · Alvor: P3
- **Sted:** `.claude/skills/daa-extract/scripts/build_legacy_migration_manifest.py:7`
- **Påstand:** `narrative_norm_v1` er en udgaveneutral kontrakt, men den bor i et modul med navnet
  `normalize_narrative_1939_v50`.
- **Evidens:** `from normalize_narrative_1939_v50 import normalize_narrative_v1` i trin 3's generelle 2018-20-bygger.
  Modulet bruges også af `build_c3_apply_candidate`, `build_c0_followup_flags` m.fl.
- **Konsekvens:** Det signalerer »engangskode« for noget, der er obligatorisk (jf. memory om normalisering før
  record-kobling) og som trin 6/7 skal genbruge.
- **Forslag:** Omdøb til `narrative_norm_v1.py` (behold evt. et lille shim-modul) og læg testen i CI (1c-02).
- **Sikkerhed:** verificeret.

### 1c-09 · Tests der kun springer over · Alvor: P3
- **Sted:** `.claude/skills/daa-extract/scripts/test_evidenspas_v2.py:10-29`;
  `.claude/skills/daa-extract/scripts/test_build_name_completion_manifest_1939_v50.py:22-41`, `:76-83`
- **Påstand:** To testfiler melder grønt uden at teste adfærd i et rent miljø.
- **Evidens:** `test_evidenspas_v2.py` springer over på modulniveau, hvis registeret i `work_1939_stamtavle` mangler,
  og igen hvis passet allerede er anvendt (»engangs-pas … 2026-07-31«). Den kan altså aldrig køre igen.
  `test_build_name_completion_manifest_1939_v50.py`: 2 passed, 31 skipped. De to, der kører, tester kun selve
  skip-mekanismen (`assert "1 skipped" in result.stdout`).
- **Konsekvens:** Det ser ud som dækning, men er det ikke (jf. »SPRINGER OVER er ikke dækning«). `evidenspas_v2.py`
  (451 l.) er reelt død kode.
- **Forslag:** Slet `test_evidenspas_v2.py` og `evidenspas_v2.py`, eller arkivér dem (1c-07). Flyt name-completion-
  manifestets 31 artefakttests til en eksplicit »kræver privat artefakt«-markering, der rapporteres som ikke kørt, ikke
  som grøn.
- **Sikkerhed:** verificeret (kørt).

### 1c-10 · Versionsfilerne relation_persona_extract v1/v2/v3 · Alvor: P3 (dom: behold)
- **Sted:** `.claude/skills/daa-extract/scripts/relation_persona_extract.py:15-16`, `relation_persona_extract_v2.py:10-12`,
  `relation_persona_extract_v3.py:9-13`, `transfer_answers.py:125-136`; `schema.sql:15630-15637`, `:15682`
- **Påstand:** Alle tre er levende og må ikke slettes. Den eneste lugt er navngivningen og en kopieret titelløkke.
- **Evidens:** Hver fil er en låst profil (`relation-persona-2018-20-v1/v2/v3`), og skemaet accepterer stadig alle tre
  profiler. v2 importerer konstanter fra v1, og v3 importerer fra v1 og v2. `transfer_answers.py` vælger v2 eller v3
  pr. arktype (`PROPOSE = {"marriage": _propose_v2, "marriage_v3": _propose_v3}`). v1's CLI genererer del 1-manifestet,
  og v1-profilen er skrevet til data. v3's `_name` (l. 78-113) kopierer ca. 15 linjers titeloverspringning fra v2's
  `_name` (l. 61-98). Det samme gælder `relation_marriage_sheet.py`/`_v3.py`: begge kaldes af `tests/sql/*.sh` i CI.
- **Konsekvens:** Ingen fejl. Kopien er lille og bevidst, fordi profilen skal være reproducerbar.
- **Forslag:** Behold dem. Overvej én modul-docstring, der forklarer »vN = profilversion i data, ikke filversion«.
- **Sikkerhed:** verificeret.

### 1c-11 · Duplikerede kanoniserings- og hash-hjælpere · Alvor: P3
- **Sted:** fx `clause_segment.py:24-25`, `source_record_ledger.py:22-23`, `transfer_pack.py:29-30`,
  `build_production_write_manifest_1939_v50.py:38-39`, `control_model.py:61-62` (i alt ca. 20 kopier af
  kanoniserings-JSON og 21 filer med egne sha256-hjælpere)
- **Påstand:** Samme kanoniske JSON-form (`ensure_ascii=False, sort_keys=True, separators=(",", ":")`) er kopieret ca. 20
  gange.
- **Evidens:** Søgning på `^def (_canonical|canonical_sha|_canonical_digest|canonical_bytes)`. Alle kopier jeg så, er
  identiske. `build_eligible_selection.py:89` udelader `ensure_ascii=False`, men hasher kun ASCII-nøgler, så det er
  harmløst.
- **Konsekvens:** Teoretisk drift, hvis én kopi ændres. Lav risiko ved projektets skala. Normalisering på tværs af
  skills er derimod ikke kopieret: `validate.py:50 norm` (dato/OCR), `daa-presens/scripts/validate_presens.py:23 ocr_norm`
  (aggressiv OCR-støj, kun til advisory) og `daa-haendelser/scripts/validate_haendelser.py:46 normaliser_klausul`
  (klausulnøgle) har hver sit formål. daa-haendelser genbruger `validate.derive_date_info` i stedet for at kopiere. Kun
  `narrative_norm_v1` er kontraktbundet (1c-08).
- **Forslag:** Ét `canonical.py` til nye moduler. Lad være med at omskrive de låste 1939-moduler.
- **Sikkerhed:** verificeret (stikprøve af 12).

### 1c-12 · Python↔SQL-tvillinger kun delvist låst · Alvor: P3
- **Sted:** `.claude/skills/daa-extract/scripts/relation_persona_extract_v2.py:14-17`;
  `test_relation_persona_extract_v3.py:231-247`; `tests/sql/test-relation-persona-v2.sql:14`
- **Påstand:** Nogle regler findes både i Python og SQL. Nogle af dem er låst af en paritetstest, andre kun af en
  kommentar eller af håndkopierede literaler.
- **Evidens:** Titelordene og bogens ægteskabsnummer er låst af en ægte paritetstest: regex over `schema.sql` og en
  fælles fixture (`tests/fixtures/relation-book-ordinal.json`). Det er godt. `YEAR` og `WORD` har kun kommentaren
  »= SQL-tvillingen i write_relation_person_create«. Ordvinduet testes med »samme tekst som Python-testen«, kopieret ind
  i begge testfiler.
- **Konsekvens:** Ændres årstalsreglen i den ene ende, kan arkets forslag (Python) og serverens accept (SQL) skilles,
  uden at nogen test reagerer.
- **Forslag:** Flyt vindue- og årstalseksemplerne til en fælles JSON-fixture, som begge sider læser (samme mønster som
  `relation-book-ordinal.json`).
- **Sikkerhed:** verificeret for titelord, bognummer og vindue; sandsynlig for YEAR (ingen paritetstest fundet ved søgning).

### 1c-13 · Opgraderingsscripts: copy-paste og døde efter merge · Alvor: P3
- **Sted:** `tests/sql/test-150-upgrade.sh:1-26`, `tests/sql/test-248-upgrade.sh:1-21` (+ `test-244`, `-2bii`,
  `-indholds-id`, `-relation-binding`, `-transfer-5ab-ddl-upgrade.sh`)
- **Påstand:** Syv næsten ens scripts tester opgradering mod `git merge-base origin/main HEAD` og er erklæret »Kun
  lokalt«.
- **Evidens:** Linje 5-12 er ens på tværs af filerne. Efter merge peger base på et commit, der allerede indeholder
  featuren, så forudsætningstjekket (fx `to_regclass('private.relation_reopen') IS NULL`) fejler. CI dækker kun en
  generel opgraderingssti fra `2d6aabf` (`ci.yml:320-370`) og den kumulative migrationssti (`ci.yml:171-187`).
- **Konsekvens:** Bevidst PR-tids-værktøj, men efter merge er det død vægt. Opgradering fra prods aktuelle skema testes
  kun, hvis udvikleren husker at køre scriptet lokalt.
- **Forslag:** Ét parametriseret `test-upgrade.sh <base> <forudsætning> <tests…>`. Slet de enkelte filer, når featuren
  er i prod.
- **Sikkerhed:** verificeret.

### 1c-14 · Død kodeblok i klausul-segmenteringen · Alvor: P3
- **Sted:** `.claude/skills/daa-extract/scripts/clause_segment.py:188-190`
- **Påstand:** En `if …: pass` med kommentaren »opslug layout-spannet mellem de to« gør ingenting.
- **Evidens:** Blokken har ingen sideeffekt. Oprydningen sker faktisk senere (l. 196-211).
- **Konsekvens:** Den vildleder læseren i et modul, der er bærende for trin 4.
- **Forslag:** Fjern blokken.
- **Sikkerhed:** verificeret.

### 1c-15 · `supabase_load.R` i roden · Alvor: P3
- **Sted:** `supabase_load.R:2-5`
- **Påstand:** Filen er ikke længere farlig, men den er død vægt.
- **Evidens:** `stop("supabase_load.R er retired …")` på linje 5 stopper både `Rscript` og `source()`, før der oprettes
  forbindelse. Resten (l. 6-218) indeholder stadig `RESET <- TRUE` og `TRUNCATE` (l. 115). Det kan kun ramme nogen, der
  kopierer udsnit.
- **Konsekvens:** Minimal. Den forvirrer kun (CLAUDE.md skal advare om den).
- **Forslag:** Slet den. Git-historikken bevarer den. Fjern samtidig advarslen i CLAUDE.md.
- **Sikkerhed:** verificeret.

### 1c-16 · Writer-manifestets validering vokser pr. klasse · Alvor: P3
- **Sted:** `.claude/skills/daa-extract/scripts/apply_reimport_helpers.R:36-92`, `:175-180`, `:281-304`, `:380-411`
- **Påstand:** Hver ny `dependency_class` kræver en kopieret blok på fire-fem steder.
- **Evidens:** Linje 61-92 er fire næsten ens blokke (legacy_migration, clause_evidence, clause_revision,
  interpretation_proposal). Tilladte kombinationer er hårdkodet (l. 38-43), og dispatch og gateway er én gren pr. klasse.
- **Konsekvens:** Det er vedligeholdelsesgæld, men koden er korrekt, fail-closed og ensartet. Ved projektets skala er
  det acceptabelt.
- **Forslag:** En tabel `class -> count_name -> rpc` ved næste nye klasse. Ikke før.
- **Sikkerhed:** verificeret (filen er læst fuldt).

### Stikprøve af død-kandidater (tillæg F)

| Fil | Dom | Begrundelse |
|---|---|---|
| `daa-extract/scripts/apply_reimport.R` | **levende** | Den generelle writer-CLI. Brugt i 2 runbooks og har en strikt argumentparser (l. 2-8). CLI'en selv har ingen test. |
| `daa-presens/scripts/segment_presens.py`, `validate_presens.py` | **levende** | Trin ② og ④ i `daa-presens/SKILL.md:34-36`. Ingen tests overhovedet. |
| `daa-extract/scripts/fix_go2_dublet_maal.sql` | engangs, bevidst | Læsemåling til en afsluttet prod-rettelse (l. 1-7, `BEGIN READ ONLY`). Arkivér. |
| `daa-extract/scripts/replace_dryrun.R` | historisk | Read-only rapport fra #123 (l. 1-8). Arkivér. |
| `daa-extract/scripts/run_evidence_43a_rehearsal.py` | historisk | Engangskørsel af dagsværk 4.3a (l. 1-8). Arkivér. |
| `R/geo-enrich/04-person-corroboration.R` | sandsynligvis død | Docs-ref 0. Geo-enrich er aldrig kørt (#131). |
| `tests/sql/inspect-1939-v50-c3-external-acl.sql` | død | Hører til C3-suiten, der ikke køres (1c-05). |
| `daa-extract/scripts/evidenspas_v2.py` (ikke på F-listen) | **død** | Kun importeret af en test, der altid springer over (1c-09). |

## 3. Dom pr. område

| Område | Dom | Begrundelse |
|---|---|---|
| Forarbejde: stamtavle-import (`segment.py`, `validate.py`, `load_daa.R`) | **hul** | Grønne, omfattende tests og en velbevogtet loader, men 0/30 og 1/25 funktioner dækket af CI (1c-02). |
| Forarbejde: præsensliste (`daa-presens`) | **bør laves om** | Ingen tests. Loaderen har en uvagtet `--reset` og en skrivevej uden om writeren (1c-01). |
| Forarbejde: hændelser (`daa-haendelser`) | solidt | Lille, CI kører `discover`, og den genbruger `validate.derive_date_info` i stedet for at kopiere. |
| Forarbejde: 1939 v50 / C0-C3 / D1-D2 | **solidt men overbygget** | Fail-closed og grundigt testet, men 64 % af skill-mappen er engangskode i levende træ. Forældede filer: C3-deploy og røde R-tests (1c-04/05/07). |
| Trin 1 (#152) | solidt | R-adaptere og SQL-kontrakter i CI. Kun review-byggerens Python-test står uden for CI. |
| Trin 2 (#153 writer) | solidt | `apply_reimport_helpers.R` er stram, fail-closed og testet via fakes og ægte DB i CI. Validatoren vokser pr. klasse (1c-16). |
| Trin 3 (#149) | solidt, med et hul | Byggeren er godt testet, men normaliseringskontrakten bag 1939-navn har ingen CI-test (1c-02/08). |
| Trin 4 (#147/#148) | solidt | `clause_segment` har ægte adfærdstests med regressionsvagter pr. profilversion. Én død blok (1c-14). |
| Trin 5a/5b + overførsel | solidt | Navneregel v3 har stærke syntetiske adfærdstests og ægte paritetstest for titelord. Delvist ulåste tvillinger (1c-12). Statiske kaldtællings-tests kompenserer for den kumulative migrationsfil. |
| Trin 5c-1 (#150) | solidt (let undersøgt) | `test_build_header_manifest.py`, `test_placement_control_sheet.py` og placement-SQL'en er i CI. Opgraderingen er kun lokal (1c-13). |
| CI som helhed for dataarbejdet | **hul** | DB-jobbene er grundige. Python-jobbet er en håndliste uden kerne-modulerne, og CI-dækningen er målt forkert (1c-02/06). |

## 4. Læst fuldt (21 filer + sektioner; loft 40)

Hele filer:
1. `…/scratchpad/f1/_faelles.md`
2. `…/scratchpad/f1/1c/brief.md`
3. `.github/workflows/ci.yml`
4. `run-tests.R`
5. `.claude/skills/daa-extract/scripts/relation_persona_extract.py`
6. `.claude/skills/daa-extract/scripts/relation_persona_extract_v2.py`
7. `.claude/skills/daa-extract/scripts/relation_persona_extract_v3.py`
8. `.claude/skills/daa-presens/scripts/load_presens.R`
9. `.claude/skills/daa-extract/scripts/apply_reimport_helpers.R`
10. `.claude/skills/daa-extract/scripts/clause_segment.py`
11. `.claude/skills/daa-extract/scripts/test_clause_segment.py`
12. `.claude/skills/daa-extract/scripts/test_relation_persona_extract_v3.py`
13. `.claude/skills/daa-extract/scripts/build_legacy_migration_manifest.py`
14. `.claude/skills/daa-extract/scripts/test_build_legacy_migration_manifest.py`
15. `.claude/skills/daa-extract/scripts/test_apply_reimport_1939_v50.R`
16. `tests/sql/test-150-upgrade.sh`
17. `tests/sql/test-248-upgrade.sh`
18. `_maal/py-ikke-ci-resultat.txt`
19. `tests/testthat/test-apply-c3-1939-v50.R`
20. `tests/testthat/test-project-evidence.R`
21. `tests/testthat/test-export-c3-apply-preview-1939-v50.R`

Sektioner:
- `docs/reviews/2026-10-27-trin-1-5/maalinger.md` l. 1-6, 40-73, 146-305
- `systemkort.md` l. 1-60, 153-170, 481-534
- `apply_reimport_1939_v50_helpers.R` l. 1-80
- `test_build_c3_html_review_1939_v50.py` l. 367-420
- `test_convert_c3_decisions_1939_v50.py` l. 55-100
- `test_build_name_completion_manifest_1939_v50.py` l. 20-90
- `test_evidenspas_v2.py` l. 1-60
- `test_identity_guard_static.py` l. 1-60
- `transfer_answers.py` l. 100-150
- `db-migrations-c3-identity.sql` l. 1-66 + halen
- `supabase_load.R` l. 1-30
- `load_presens`-søsterens `load_daa.R` (grep l. 6-104, 311-331)
- `daa-presens/SKILL.md` l. 80-100
- `validate_presens.py` l. 1-35
- `validate_haendelser.py` l. 18-51
- review 35 l. 455-470

Vigtigste søgninger og målinger:
- Dækning: hver fil i tillæg D søgt i `tests/testthat`, `tests/ci` og `ci.yml`, og i shell-scripts, som CI kalder.
- Hvem importerer hvert testede moduls kode: import-graf over skill-scripts.
- Funktionsdækning: tracer over CI's Python-liste (`f1/1c/fncov.py`).
- Funktionsparitet: `db-migrations-c3-identity.sql` mod `schema.sql`/`db-migrations.sql` (`f1/1c/cmpfn.py`, `dfn.py`).
- Kopier af kanoniserings- og hash-hjælpere: `^def (_canonical|canonical_sha|…)`.
- Linjeoptælling af 1939/C3-filer.
- Opslag på `supabase_load`, `db-migrations-c3-identity`, `apply_reimport.R` og `LegacyBackfillFreeze`.

Kørt:
- De to røde Python-tests med og uden `rg`/`node`.
- `test_validate.py` og `test_make_boundary_text_1939.py`: 131 og 53 grønne.
- Hele CI's Python-liste lokalt: 1.137 grønne, 3 miljøfejl pga. manglende git-checkout.
- De to R-tests uden wrapper: begge røde.

## 5. Hvad jeg ikke nåede

- Jeg kørte hverken `run-tests.R` (testthat) eller nogen SQL-, shell- eller integrationstest. De kræver R-pakker eller en
  database, og briefet forbyder DB-kørsel. R-dommen bygger på de to kørte standalone-filer og på læsning.
- `validate.py` (1.042 l.), `segment.py` (1.057 l.) og `load_daa.R` (1.093 l.) er kun læst i udsnit. Jeg har ikke
  vurderet kvaliteten af deres indre logik, kun deres dækning.
- Trin 5c-1-modulerne (`build_header_manifest.py`, `placement_control_sheet`) og overførselsværktøjerne
  (`transfer_steps.py`, `transfer_pack.py`) er kun bekræftet som CI-dækkede, ikke læst.
- `daa-presens` (`segment_presens.py`, `validate_presens.py`) er kun skimmet. Jeg har ikke fulgt `load_presens.R`'s
  vej mod de nyere DB-triggere/gates (fx om writer-gates i prod allerede blokerer direkte INSERT). Det kunne mildne
  1c-01's append-del, men ikke `--reset`.
- Tværsproget duplikering mod TS (`packages/core`) er kun berørt via OCR-dato-paritet.
- Jeg har ikke undersøgt de 34 divergerende funktioner mellem `schema.sql` og `db-migrations.sql` (tillæg A). Det
  hører til DB-sporet. Jeg så kun, at flere C3-relevante funktioner har en anden sidste definition i
  `db-migrations.sql` end i `schema.sql`.
