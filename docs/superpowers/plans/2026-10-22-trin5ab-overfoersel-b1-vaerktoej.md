# Trin 5a+5b-overførslen, plan B1: værktøj til data-ceremonien — implementeringsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Repo-værktøj, der lader en arbejdskørsel på en restore af D1 producere en genspilbar pakke, som giver
de samme nøglede digests i en anden base (genspilsprøven) og i prod (GO 2).

**Architecture:** Fire dele, alle læse-kun eller databasefri undtagen skridt-SQL'en: (1) en nøglekortfil og
nøglede digests, der oversætter hver uuid i en hashet række til dens indholdsnøgle; (2) skridt-SQL i repoet for de
skridt, beviskæden kun havde som private scripts (afgør, bind, kontrolkørsel, bekræftelse, kø, P-afvisning,
dispositioner); (3) `transfer_answers.py`, der overfører projektejerens svar fra beviskædens ark til de regenererede
via nøgler; (4) `transfer_steps.py`, pakkeformatet med skridttyper og tilstandsklassifikation. Plan B2 (privat
ceremoni, arbejdskørslen, genspilsprøven, GO 2) bygger på B1, når den er merget.

**Tech Stack:** PostgreSQL 17 (psql-scripts, read-only digests), Python 3 stdlib (pytest), bash-tests i CI-jobbet
`writer-1939-v50-db`.

**Spec:** `docs/superpowers/specs/2026-10-21-trin5ab-2018-20-prod-overfoersel-design.md` (§6.2, §6.3, §7, §8, §10).
Roadmap: trin 5 (#150/#151), `docs/evidensbaseret-genimport/roadmap.md` (aktivt mål); status:
`docs/evidensbaseret-genimport/status.md`, rækken »DDL-ceremonien for 5a+5b« (`i prod`, 2026-10-22).
Kortlægning af kæden (privat, ikke i git): `scratchpad/kaede-opskrift.md` (2026-10-22).

## Errata mod spec'en

| Spec | Plan B1 | Begrundelse |
| --- | --- | --- |
| §6.2 »5a's afgørelser skal ligge før del 1's kandidatkørsel 2«; »5a's webafgørelse er sit eget skridt«; §6.3-rækken »5a's afgørelser« | Udgår. Kæden starter ved del 1 | `docs/decisions.md` 2026-10-21: 5a's 31 afgørelser overføres ikke. Beviskæden kørte selv del 1 uden 5a (`relationspersonas-5b-del1-bevis.md:28`), så arbejdskørslen reproducerer kæden |
| §6.3 »Kanonisk delta 0« (mod roden) | Mod D1 | `decisions.md` 2026-10-21 pkt. 2 |
| §7 »Autorisationer: antal `consumed` pr. operation og manifest-hash« | Antal `consumed` pr. operation; manifest-hash kun for `relation_persona` | Dispositionsmanifester bærer tilfældige versions-id'er (`citing_interpretation_ids`, `schema.sql:17239`), så deres hash er base-afhængig |
| §8 »eksakt filinventar« | Beviskædens private skridt-scripts (`decide.sql`, `bind-preview.sql`, `bind.sql`, `koe-apply.py`, `afvis-P.sql`, kontrolregistrering, bekræftelseshash) får repo-versioner med test | Inventaret kan kun bindes til filer, CI tester |
| §7 »Udelader id'er« pr. digest (kolonneliste) | Generisk: hver uuid i rækkens tekst oversættes via nøglekortet; uoversatte tælles | Evidens-JSON bærer id'er i mange former; en kolonneliste ville overse dem. To-base-testen er porten |
| Én plan B | B1 (repo, CI) og B2 (privat ceremoni) | B2's tests kan ikke køre i CI; B1 merges og reviewes for sig |

## Global Constraints

- Scripts printer kun tal, koder og hashes; aldrig navne, kildetekst, noter eller aktør-uuid (`set_config`-ekko filtreres).
- Filer, scripts skriver, oprettes `0600` med `O_EXCL`.
- Hashede rækker: `to_jsonb(…)::text`, nøglen i rækken, `ORDER BY … COLLATE "C"`; sessionsindstillinger låst som i
  `transfer_table_hashes.sql` (`TimeZone UTC`, `DateStyle 'ISO, MDY'`, `IntervalStyle postgres`, `extra_float_digits 1`,
  `search_path pg_catalog`, `row_security off`).
- Digest- og nøglekortfiler er læse-kun (`BEGIN READ ONLY`); ingen `CREATE`, heller ikke midlertidige tabeller (prod kører
  dem under `default_transaction_read_only`).
- Ingen digest eller godkendt hash indeholder `current_database()`, `system_identifier` eller et tilfældigt id.
- #153's writer, `red_decide_interpretation` og trin 4's filer ændres ikke. Ingen DDL i B1.
- Python: kun stdlib; `-I`; fejl som `SystemExit("<KODE> …")` med versal-kode.
- Tests i CI: pytest-listen i `python`-jobbet og bash-tests i `writer-1939-v50-db` (`.github/workflows/ci.yml`). Hele jobbet
  køres lokalt før push (memory: kør hele CI-jobbet lokalt).
- Commits: Conventional Commits på dansk, ingen Claude-attribution, én pr. task.

## Review Focus

1. **En tilfældig uuid i evidens, som nøglekortet ikke kender** (fx et versions-id i en ny evidensform): digesten skal afvige
   mellem to baser og testen fejle med antal uoversatte, ikke give et grønt, men forkert digest.
2. **Samme rang peger på en anden person i den nye kørsel** (kontrolarkets R-linjer, køens `same <person>`): overførslen skal
   stoppe, ikke overføre rangen.
3. **`hash_gated`-skridt, hvor versions-id'et er forskelligt i de to baser:** items slås op via `interpretation_key` ved
   kørsel; afviger de forventede items fra basens preview, stopper skridtet før RPC'en.
4. **Writer-skridt afbrudt efter autorisationen:** den efterladte `issued`-autorisation må ikke ændre digests; genkørslen giver
   pakkens udgangsdigest.
5. **Forskellig collation og tidszone i to baser** (ICU `da` + `Pacific/Chatham` mod `C` + UTC): digests og skridt-SQL er ens.

---

### Task 1: Nøglekort og nøglede digests

**Files:**
- Create: `.claude/skills/daa-extract/scripts/transfer_5ab_keymap.sql`
- Create: `.claude/skills/daa-extract/scripts/transfer_5ab_digests.sql`
- Test: `tests/sql/test-transfer-5ab-digests.sh`

**Interfaces:**
- Produces: `transfer_5ab_keymap.sql` (`-v src=<id>`): linjer `<uuid>|<nøgle>`, sorteret `COLLATE "C"`, unik på uuid.
  Nøgler: `persona:<persona_key>`; `fortolkning:<interpretation_key>#<version>`;
  `kandidatkoersel:<input_sha256>:<config_sha256>`; `kandidat:<kørselsnøgle>:<persona_key>:<rank>`;
  `kontrol:<kandidatkørselsnøgle>`; `foraelderkort:<kontrolnøgle>:<interpretation_key>`;
  `stikproeve:<kontrolnøgle>:<persona_key>`; `omtale:<persona_key>:<mention_role>:<ordinal>`; `obs:<uuid>` (klausulobservationer,
  fælles med prod); `profil:<uuid>` (profiler, fælles); `binding:<interpretation_key>:<target_type>:<target_id>`;
  `bindingsbatch:<items_sha256>`; `disposition:<observation_id>#<version>`; `batch`, `autorisation`, `udtraek`, `haendelse`
  (uden løbenummer: deres id'er er tilfældige og uden indholdsnøgle).
- Produces: `transfer_5ab_digests.sql` (`-v src=<id>`): én linje `daa.transfer_5ab_digests=<json>` med
  `{"<lag>": {"n": int, "sha256": hex}, …, "n_uuid_unmapped": int}`. Lag: `personas`, `identities`, `identity_events`,
  `candidate_runs`, `candidates`, `control_runs`, `control_samples`, `control_exclusions`, `control_parent_cards`,
  `control_events`, `control_parent_events`, `interpretations`, `parties`, `classifications`, `dispositions`,
  `writer_profiles`, `bindings`, `family_sources`, `authorizations_consumed`, `authorizations_issued`, `counts`.
  `family_sources` = rækkerne `(family_id, slags, interpretation_key)` fra `public.public_family_sources(<alle familier med
  en binding>)` kaldt som `anon` (spec §7 »anon«); privilegiematricen er plan A's `P|m`-linjer og genbruges.
- Consumed by: Task 6 (`classify`) og plan B2.

Rækketekst pr. lag: `to_jsonb` af rækken **minus** id-kolonner og tidsstempler (spec §7's udelad-kolonne), derefter hver
uuid i teksten erstattet med sin nøgle fra nøglekortet (samme CTE i begge filer, kopieret, ikke `\ir`). Uoversatte uuid'er
bevares og tælles i `n_uuid_unmapped`. Evidensnøgler, der udelades (base-bundne hashes): `pack_sha256`, `state_sha256`,
`preview_sha256`, `preview_hash`, `set_sha256`, `batch_id`, `supersedes_promotion_id`. Hver tilføjelse til listen er en
ruling i ledgeren med begrundelsen »base-bundet«, aldrig »indhold«. `authorizations_*` og `counts` er antal pr. operation
(manifest-hash kun for `relation_persona`).

- [ ] **Step 1: Skriv testen** `tests/sql/test-transfer-5ab-digests.sh <prefix>`. Byg A og B som
  `tests/sql/test-indholds-id-determinism.sh` (A: `--locale=C` + UTC; B: ICU `da` + `Pacific/Chatham`; dump- og kædefixtures
  `indholds-id-dump.sql`, `indholds-id-chain.sql`). Asserts:
  - `dg_same`: digests-JSON fra A = fra B, og `n_uuid_unmapped = 0` i begge;
  - `dg_ids_differ`: mindst ét versions-id (`private.interpretation.id`) er forskelligt mellem A og B (vagt: ellers beviser
    `dg_same` intet);
  - `dg_value`: én ændret `marriage_ordinal` i B ⇒ kun `parties` afviger;
  - `dg_swap`: ombyttet `decision_status` mellem to personas i B ⇒ `identities` afviger;
  - `dg_target`: én binding med andet `target_id` i B ⇒ `bindings` afviger;
  - `dg_unmapped`: en indsat evidens med `gen_random_uuid()` i B ⇒ `n_uuid_unmapped ≥ 1`;
  - `dg_readonly`: begge filer kører under `PGOPTIONS='-c default_transaction_read_only=on'`.
  Slut: `DG5AB_OK`.
- [ ] **Step 2: Kør den.** Run: `bash tests/sql/test-transfer-5ab-digests.sh t5abdg` — Expected: FAIL (filerne findes ikke).
- [ ] **Step 3: Implementér** de to SQL-filer.
- [ ] **Step 4: Kør igen.** Expected: `DG5AB_OK`.
- [ ] **Step 5: Commit** `test(151): nøglekort og nøglede digests for 5a+5b-lagene`.

### Task 2: Uberørt-hash og andre kilders rækker

**Files:**
- Create: `.claude/skills/daa-extract/scripts/transfer_5ab_untouched_hash.sql`
- Modify: `tests/sql/test-transfer-5ab-digests.sh` (to asserts)

**Interfaces:**
- Produces: `-v src=<id>` ⇒ `daa.transfer_5ab_untouched=<sha>` (som `transfer_untouched_hash.sql`, men eksklusionslisten er
  alle tabeller, kæden skriver i: kortlægningens tabeller pr. skridt, `kaede-opskrift.md` §B) og
  `daa.transfer_5ab_other_sources=<sha>` (for hver ekskluderet tabel: rækker, hvis kilde ≠ `src`, via `source_id` eller join
  til `interpretation`/`source_persona`/`source_observation`).
- Consumed by: plan B2 (`VERIFY_OK`).

- [ ] **Step 1: Udvid testen:** `un_chain_excluded` (kæden i A og B ⇒ ens untouched-hash, og lig hashen før kæden i samme
  base) og `un_other_source` (én rad for en anden kilde ændret i B ⇒ kun `other_sources` afviger).
- [ ] **Step 2: Kør** — Expected: FAIL på de to nye asserts.
- [ ] **Step 3: Implementér.**
- [ ] **Step 4: Kør** — Expected: `DG5AB_OK`.
- [ ] **Step 5: Commit** `test(151): uberørt-hash og andre kilders rækker for 5a+5b-kæden`.

### Task 3: Skridt-SQL i repoet (afgør, bind, kontrol, bekræftelse, P-afvisning, dispositioner)

**Files:**
- Create (`.claude/skills/daa-extract/scripts/`): `transfer_5ab_step_decide.sql`, `transfer_5ab_step_bind.sql`,
  `transfer_5ab_step_control.sql`, `transfer_5ab_step_corroborate.sql`, `transfer_5ab_step_reject.sql`,
  `transfer_5ab_step_disposition.sql`
- Test: `tests/sql/test-transfer-5ab-steps.sh`

**Interfaces:**
- Hver fil: `-v src=<id> -v mode=capture|replay -v items=<sti>`. Aktøren = første profil med `rolle='redaktion'`
  (`ORDER BY id`), som beviskædens scripts. `capture` skriver de nøglede items til `items` (0600, `\o`) og udfører skridtet;
  `replay` læser `items`, bygger samme items i basen, stopper med `STEP_ITEMS_MISMATCH`, hvis de afviger, og kalder ellers
  RPC'en med en hash, der er **genberegnet i basen**. Udskrift: `STEP_OK <skridt> n=<antal> items_sha256=<hex>`.
- Items (nøglede, sorteret `COLLATE "C"`):
  - decide: `{interpretation_key, classification}` fra `red_preview_relation_decisions(src)`; RPC `red_decide_relation_interpretations(src, set_sha256)`.
  - bind: `{interpretation_key, family_id, rule_key, rule_version, supersedes_key|null}` for accepterede
    `relation.marriage|parent|child` med bindingstilstand og egnet preview; `interpretation_id` slås op via
    `interpretation_current` ved kørsel; RPC `red_promote_relation_interpretations_batch(src, items, preview_sha256)`
    (efter `private/5b-2b-iii/bind-preview.sql` og `bind.sql`).
  - control: `{candidate_run_key}` = `input_sha256:config_sha256` for den seneste kandidatkørsel; RPC
    `red_register_identity_control_run(run_id)`; udskriver også kontrolkørslens id (deterministisk).
  - corroborate: `{persona_key}` for `corr_set` (`schema.sql:16494-16505`); RPC `red_corroborate_family_identities(ctl, set_sha256)`.
  - reject: `{persona_key, evidence}` (evidens-JSON fra en fil); fortolkningen slås op via `interpretation_party_current`
    (`persona_key` → persona-id → `relation.marriage`); RPC `red_decide_interpretation(id, version, 'rejected', evidence)`
    (efter `private/5b-navneregel-v3/afvis-P.sql`, men uden hårdkodet id).
  - disposition: manifestet regenereres i basen af `red_relation_disposition_input(src)`; items =
    `{observation_id, disposition, actor_persona_keys, citing_interpretation_keys}`; derefter `relation_batch_apply.sql`
    med det regenererede manifest.
- Genbruges uændret (ingen ny fil): `packages/identity-candidates/sql/write-candidates.sql` (`hash_gated`, serveren
  genberegner `input_sha256`), `relation_persona_apply.sql` og `relation_batch_apply.sql` (`writer`), og `sql`-delen af
  `identity_control_sheet.py`, `spouse_exception_sheet.py`, `relation_marriage_sheet.py`, `relation_marriage_sheet_v3.py` og
  `relation_child_sheet.py` (`sql`). De står i pakkens inventar (Task 6).
- Consumed by: Task 6 (skridttyper) og plan B2.

- [ ] **Step 1: Skriv testen** `tests/sql/test-transfer-5ab-steps.sh <prefix>`: A og B som i Task 1, fixtures op til 2a's
  afgørelse. Asserts:
  - `st_capture_replay`: decide og bind i `capture` på A, i `replay` på B med A's items ⇒ ens `transfer_5ab_digests`
    (lagene `interpretations`, `classifications`, `bindings`) og ens `items_sha256`;
  - `st_mismatch`: B med én item fjernet fra filen ⇒ `STEP_ITEMS_MISMATCH`, og digests uændrede (intet skrevet);
  - `st_rerun`: bind i `replay` to gange ⇒ anden gang samme batch (RPC'ens replay), 0 nye rækker;
  - `st_reject_by_key`: reject via `persona_key` i to baser ⇒ ens `interpretations`;
  - `st_writer_issued`: dispositionsskridtet afbrudt efter `red_authorize_reimport` (kun autorisationen kørt), derefter fuldt
    skridt ⇒ `authorizations_consumed` og `dispositions` som en uafbrudt kørsel; `authorizations_issued` = 1.
  Slut: `STEPS5AB_OK`.
- [ ] **Step 2: Kør** — Expected: FAIL (filerne findes ikke).
- [ ] **Step 3: Implementér** de seks filer.
- [ ] **Step 4: Kør** — Expected: `STEPS5AB_OK`.
- [ ] **Step 5: Commit** `feat(151): skridt-SQL med nøglede items og hashes genberegnet i basen`.

### Task 4: Køens ark i repoet

**Files:**
- Create: `.claude/skills/daa-extract/scripts/identity_queue_sheet.py`
- Test: `.claude/skills/daa-extract/scripts/test_identity_queue_sheet.py`

**Interfaces:**
- `sql --sheet <koe.txt> --approved-sha256 <h> --details <koe-detaljer.json> --source <id> --out <sti>`: port af
  `~/.private/5b-2b-i/koe-apply.py` med samme linjeformat `Q <persona_id> <ver> : same <person_id>|N|X|U # <grund>`, samme
  kontekst `{basis:'human_sheet', sheet_sha256, rows_sha256, line}` og **byte-samme note** `kø 2b-i <sh[:12]> sag <n> — <grund>`
  (v3-rækkens `previous.note` bærer den). Fejlkoder: `KOE_SHEET_HASH_MISMATCH`, `KOE_LINE_COUNT`, `KOE_LINE_INVALID <n>`,
  `KOE_PERSONA_UNKNOWN <n>`; i SQL'en `KOE_ROWS_STALE`, `KOE_COUNT_MISMATCH`.
- Consumed by: plan B2 (2b-i's kø).

- [ ] **Step 1: Skriv tests:** gyldigt ark ⇒ SQL med N kald og den præcise note; forkert hash; forkert antal; ukendt persona;
  dublet; `same` uden person; noten for linje 3 er byte-lig `kø 2b-i <12 hex> sag 3 — <grund>`.
- [ ] **Step 2: Kør** `pytest .claude/skills/daa-extract/scripts/test_identity_queue_sheet.py -q` — Expected: FAIL (modul mangler).
- [ ] **Step 3: Implementér.**
- [ ] **Step 4: Kør** — Expected: alle grønne.
- [ ] **Step 5: Commit** `feat(151): køens ark i repoet (port af 2b-i's kø-anvendelse)`.

### Task 5: Svaroverførslen

**Files:**
- Create: `.claude/skills/daa-extract/scripts/transfer_answers.py`
- Test: `.claude/skills/daa-extract/scripts/test_transfer_answers.py`

**Interfaces:**
- `transfer --kind <control|spouse|queue|marriage|marriage_v3|child> --old-sheet <ark> --old-keymap <tsv> --new-sheet <ark>
  --new-keymap <tsv> --expected-dropouts <fil> --out-sheet <sti> --out-report <sti>`. Nøglekort = Task 1's linjer.
- Hver svarlinje (`<kind> <ref> <ver> : <svar>`) parses efter værktøjets grammatik; `ref` oversættes gammel uuid → nøgle →
  ny uuid (nøgle-referencer som `interpretation_key` er uændrede). Svaret skrives ind i det nye ark på linjen med samme nøgle.
  `control`: kun `R`-linjer overføres; `D`-linjer er en ny blind stikprøve og står tomme (`_`).
- Stop (`SystemExit`): `ANSWER_NO_TARGET <n>` (svar uden ny linje, ikke på bortfaldslisten), `ANSWER_NO_SOURCE <n>` (ny linje
  uden svar), `ANSWER_VERSION_CHANGED <n>`, `ANSWER_PERSON_MOVED <n>` (`same <person>` eller rang, hvor den gamle persons
  `person_id` ikke står på samme plads i den nye linjes kandidatliste), `KEYMAP_DUPLICATE`.
- Rapporten (0600): pr. linje gammel og ny tekst efter oversættelse til nøgler (også kontekstlinjer: kandidater, familie,
  nummer, klausul), markeret `=`/`~`/`-`/`+`; stdout kun `ANSWERS_OK kind=… overfoert=… bortfald=… aendret=… report_sha256=…`.
- Consumed by: plan B2 (projektejerens forskelsvisning).

- [ ] **Step 1: Skriv tests** med syntetiske ark for hver `kind`: entydig overførsel; svar uden mål stopper; mål uden svar
  stopper; forventet bortfald går igennem og tælles; oversat rang til en anden person stopper (`ANSWER_PERSON_MOVED`);
  `control`-`D` står tom; rapporten markerer en ændret kontekstlinje med `~`; nøglekort med dublet stopper; stdout indeholder
  ingen uuid eller navn.
- [ ] **Step 2: Kør** `pytest .claude/skills/daa-extract/scripts/test_transfer_answers.py -q` — Expected: FAIL.
- [ ] **Step 3: Implementér.**
- [ ] **Step 4: Kør** — Expected: alle grønne.
- [ ] **Step 5: Commit** `feat(151): svaroverførsel fra beviskædens ark via nøgler`.

### Task 6: Pakken (skridttyper og tilstand)

**Files:**
- Create: `.claude/skills/daa-extract/scripts/transfer_steps.py`
- Test: `.claude/skills/daa-extract/scripts/test_transfer_steps.py`

**Interfaces:**
- Pakke-JSON `transfer-pack-5ab-v1`: `{version, base: {d1_receipt_sha256, restore_hash}, inventory: {sti: sha256},
  steps: [{n, name, type: "sql"|"writer"|"hash_gated", script, vars, inputs: {navn: sha256}, items_sha256|null,
  layers: [lag], digests_in: {lag: sha}, digests_out: {lag: sha}, seconds}], pack_sha256}`; `pack_sha256` = sha af kanonisk
  JSON uden feltet (som `transfer_pack.py`'s `pack_sha256`).
- `add-step --pack <fil> --step <json>` (tilføjer, n = næste), `validate --pack` (`PACK_INVALID <felt>`, skridt i rækkefølge,
  `layers` ⊆ Task 1's lag, `writer` kræver `inputs.manifest`), `classify --pack --n <n> --digests <json>` ⇒ `WRITE` (lagene =
  `digests_in`), `ALREADY_APPLIED` (= `digests_out`), ellers `MIXED` (exit 3), `inventory --pack --root <repo> --private <dir>`
  (mængden af filer og deres hashes = pakkens; `INVENTORY_MISMATCH`), `next --pack --done <fil>` (første skridt uden
  `ALREADY_APPLIED`/`DONE`-markør). Ukendte argumenter ⇒ exit 2.
- Consumed by: plan B2 (arbejdskørslen skriver pakken; genspilleren læser den).

- [ ] **Step 1: Skriv tests:** gyldig pakke; ukendt skridttype; skridt ude af rækkefølge; `classify` i de tre tilstande og kun
  over skridtets lag; `pack_sha256` ændres af én ændret item-hash; inventar med en ekstra og en manglende fil; `next` springer
  `ALREADY_APPLIED` over; ukendt argument exit 2.
- [ ] **Step 2: Kør** `pytest .claude/skills/daa-extract/scripts/test_transfer_steps.py -q` — Expected: FAIL.
- [ ] **Step 3: Implementér.**
- [ ] **Step 4: Kør** — Expected: alle grønne.
- [ ] **Step 5: Commit** `feat(151): pakkeformat for data-ceremonien med skridttyper og tilstand`.

### Task 7: CI og dokumentation

**Files:**
- Modify: `.github/workflows/ci.yml` (pytest-listen: `test_identity_queue_sheet.py`, `test_transfer_answers.py`,
  `test_transfer_steps.py`; `writer-1939-v50-db`: `bash tests/sql/test-transfer-5ab-digests.sh ci_dg5ab` og
  `bash tests/sql/test-transfer-5ab-steps.sh ci_st5ab` efter `test-indholds-id-determinism.sh`)
- Modify: `docs/decisions.md` (ny post: plan B delt i B1/B2; errata-tabellen ovenfor; skridt-scripts i repoet; dispositionernes
  manifest-hash er base-afhængig), `docs/evidensbaseret-genimport/status.md` (ny række »Værktøj til data-ceremonien (plan B1)«,
  `isoleret implementeret`), `docs/changelog.md`

- [ ] **Step 1:** Tilføj testene til `ci.yml`; kør `python`-jobbets pytest-liste og hele `writer-1939-v50-db` lokalt
  (`.superpowers/sdd/<plan>/ci/run_job.py`-mønstret fra plan A). Expected: `CI_JOB_OK`.
- [ ] **Step 2:** Skriv de tre dokumenter.
- [ ] **Step 3: Commit** `docs(151): plan B1 — værktøj til data-ceremonien (CI, beslutning, status)`.

## Åbne spørgsmål til projektejeren (afgøres før plan B2, ikke før B1)

- **H3 — kandidatkørsel 1 (top-k 3).** Beviskædens del 1-base har to kandidatkørsler; kun den seneste (top-k 10) styrer
  noget. Anbefaling: genskab den ikke i prod (forventet bortfald i §6.3-listen).
- **H2 — rigtige ægteskabsnumre fra start** kan gøre 2 »søstre« egnede til maskinel bekræftelse i del 1 og ændre del 1's, 2a's og
  2b-i's tal (ikke de 253 bindingspar). Måles nøglet i bevisbaserne i B2's første task, før arbejdskørslen.
