# Trin 5a+5b-overførslen, plan B1: værktøj til data-ceremonien — implementeringsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Repo-værktøj, der lader en arbejdskørsel på en restore af D1 producere en genspilbar pakke, som giver
de samme nøglede digests i en anden base (genspilsprøven) og i prod (GO 2).

**Architecture:** (1) Et nøglekort og nøglede digests, der oversætter hver uuid i en hashet række til dens
indholdsnøgle, med en rækketilstand til fejlsøgning og §6.3-kontrollen; (2) skridt-SQL i repoet for de skridt,
beviskæden kun havde som private scripts, med nøglede items i pakken og hashes genberegnet i basen; (3) køens ark og
svaroverførslen fra beviskædens ark; (4) pakkeformatet med skridttyper og tilstand, og et genspil af en minipakke på
tværs af to baser i CI. Plan B2 (privat ceremoni, arbejdskørslen, genspilsprøven på D1, GO 2) bygger på B1, når den er
merget.

**Tech Stack:** PostgreSQL 17 (psql), Python 3 stdlib (pytest), bash-tests i CI-jobbet `writer-1939-v50-db`.

**Spec:** `docs/superpowers/specs/2026-10-21-trin5ab-2018-20-prod-overfoersel-design.md` (§6.2, §6.3, §7, §8, §9, §10).
Roadmap: trin 5 (#150/#151), `docs/evidensbaseret-genimport/roadmap.md`; status: `docs/evidensbaseret-genimport/status.md`,
rækken »DDL-ceremonien for 5a+5b« (`i prod`, 2026-10-22). Kortlægning af kæden: privat `scratchpad/kaede-opskrift.md`
(2026-10-22; afsnit A-H citeres som »kortlægningen §X«).

## Errata mod spec'en

| Spec | Plan B1 | Begrundelse |
| --- | --- | --- |
| §6.2 »5a's afgørelser skal ligge før del 1's kandidatkørsel 2«; »5a's webafgørelse er sit eget skridt«; §6.3-rækken »5a's afgørelser« | Udgår. Kæden starter ved del 1 | `docs/decisions.md` 2026-10-21: 5a's afgørelser overføres ikke. Beviskæden kørte selv del 1 uden 5a (`relationspersonas-5b-del1-bevis.md:28`) |
| §6.3 »Kanonisk delta 0« (mod roden) | Mod D1 | `decisions.md` 2026-10-21 pkt. 2 |
| §7 »Autorisationer: antal `consumed` pr. operation og manifest-hash« | Antal `consumed` pr. operation; manifest-hash kun for `relation_persona` | Dispositionsmanifester bærer tilfældige versions-id'er (`schema.sql:17239`) |
| §7 kolonneliste pr. tabel | Kolonneliste pr. lag (Task 1) **og** uuid-oversættelse via nøglekort af alt, der står tilbage (også i evidens-JSON) | Evidens-JSON bærer id'er i mange former |
| §8 »eksakt filinventar« | Beviskædens private skridt-scripts får repo-versioner med test (Task 3, 4) | Inventaret kan kun bindes til filer, CI tester |
| §6.2 skridttyper | Writer-profilens indsættelse er sit eget `sql`-skridt | `relation_persona_apply.sql:6-10` indsætter profilen før autorisationen; et afbrud derimellem gav ellers `MIXED` |
| Én plan B | B1 (repo, CI) og B2 (privat ceremoni) | B2's tests kan ikke køre i CI |

## Global Constraints

- Scripts printer kun tal, koder og hashes; aldrig navne, kildetekst, noter, uuid'er eller aktør-uuid. `set_config`-kald
  sendes til `\g /dev/null`.
- Filer: kalderen kører med `umask 077` og afviser en eksisterende målfil; psql's `\o` og stdout-omdirigering giver dermed
  0600. Python skriver med `O_EXCL`, 0600.
- Hashede rækker: `to_jsonb(…)::text`, nøglen i rækken, `ORDER BY … COLLATE "C"`; sessionsindstillinger låst som i
  `transfer_table_hashes.sql` (`TimeZone UTC`, `DateStyle 'ISO, MDY'`, `IntervalStyle postgres`, `extra_float_digits 1`,
  `search_path pg_catalog`, `row_security off`).
- Nøglekort, digests, uberørt-hash og værn er læse-kun (`BEGIN READ ONLY`, ingen `CREATE`): prod kører dem under
  `default_transaction_read_only`.
- Ingen digest eller godkendt hash indeholder `current_database()`, `system_identifier` eller et tilfældigt id.
- Skridt-SQL: `\set ON_ERROR_STOP on`, én transaktion pr. fil (`BEGIN … COMMIT`), fejlkrog `\if :{?fault}` (kun test) lige
  før `COMMIT`.
- #153's writer, `red_decide_interpretation` og trin 4's filer ændres ikke. Ingen DDL i B1.
- Python: kun stdlib; køres med `-I`; fejl som `SystemExit("<KODE> …")`.
- CI: pytest-listen i `python`-jobbet, bash-tests i `writer-1939-v50-db`. Hele jobbet køres lokalt før push.
- Commits: Conventional Commits på dansk, ingen Claude-attribution, én pr. task.

## Review Focus

1. **En tilfældig uuid, som nøglekortet ikke kender** (fx et versions-id i en ny evidensform): laget skal afvige mellem to
   baser, og `n_uuid_unmapped` skal være > 0; en pladsholder, der skjuler forskellen, er en fejl.
2. **Samme rang peger på en anden person i den nye kørsel** (kontrollens `R…A`, 2b-i `S`, `M…S`, køens `same <person>`):
   overførslen stopper (`ANSWER_PERSON_MOVED`).
3. **`hash_gated`-skridt, hvor versions-id'et er forskelligt i de to baser:** items slås op via nøgle; afviger basens items
   (også de uegnede med grund) fra pakkens, stopper skridtet før RPC'en.
4. **Writer-skridt afbrudt efter autorisationen:** den efterladte `issued`-autorisation ændrer ingen digest i skridtets lag;
   genkørslen giver udgangsdigesten.
5. **Forskellig collation og tidszone** (ICU `da` + `Pacific/Chatham` mod `C` + UTC): digests, items og skridt-SQL er ens.

---

### Task 1: Nøglekort og nøglede digests

**Files:**
- Create: `.claude/skills/daa-extract/scripts/transfer_5ab_keymap.sql`, `transfer_5ab_digests.sql`
- Test: `tests/sql/test-transfer-5ab-digests.sh`

**Interfaces:**
- `transfer_5ab_keymap.sql -v src=<id>`: stdout-linjer `<uuid>|<nøgle>`, sorteret `COLLATE "C"`, unik på uuid. Tabeller, der
  ikke findes, springes over (`to_regclass` + `\if`), så filen kører på beviskædens ældre baser og på prods træ `b42266e`.
  - Opslagsklasser (unikke nøgler, bruges af svaroverførslen): `persona:<persona_key>`, `fortolkning:<interpretation_key>#<version>`,
    `kandidatkoersel:<input_sha256>:<config_sha256>`, `kandidat:<kørselsnøgle>:<persona_key>:<rank>`,
    `kontrol:<kandidatkørselsnøgle>`, `foraelderkort:<kontrolnøgle>:<interpretation_key>`, `stikproeve:<kontrolnøgle>:<persona_key>`,
    `omtale:<persona_key>:<mention_role>:<ordinal>`, `binding:<interpretation_key>:<target_type>:<target_id>:<rule_key>`,
    `disposition:<observation_id>#<version>`.
  - Gennemstrømningsklasser (fælles med D1/prod): `obs:<uuid>` (klausulobservationer), `profil:<uuid>`, og `d1:<uuid>` for
    primærnøgler i `private.source_record`, `private.source_rendition`, `private.source_mention` (rækker kæden ikke har skrevet) og
    de øvrige uuid-tabeller, kæden ikke skriver i (implementeren lister dem ud fra `kaede-opskrift.md` §B og noterer listen).
  - Mange-til-én-klasser (tilfældige id'er uden indholdsnøgle): `batch`, `autorisation`, `udtraek`, `haendelse`, `bindingsbatch`.
- `transfer_5ab_digests.sql -v src=<id> [-v mode=rows]`: uden `mode` én linje `daa.transfer_5ab_digests=<json>`:
  `{"<lag>": {"n": int, "sha256": hex}, …, "n_uuid_unmapped": int}`; med `mode=rows` linjer `<lag>|<nøgle>|<rækkesha>`
  (til §6.3-kontrollen og fejlsøgning af `MIXED`; kalderen skriver dem til en 0600-fil).
- Lag og kolonner (alt andet i rækken udelades; derefter uuid-oversættelse):

  | Lag | Kilde | Kolonner |
  | --- | --- | --- |
  | `personas` | `source_persona` + `source_persona_mention` | `persona_key`; omtaler `(mention_id, mention_role, ordinal)` sorteret efter oversættelse |
  | `identities` / `identity_events` | `source_persona_identity` / `_event` | `persona_key`, `canonical_person_id`, `decision_status`, `version`, `evidence`, `decided_by`, `decided_by_name` |
  | `candidate_runs` / `candidates` | `…_candidate_run` / `…_candidate` | kørselsnøgle, `generator_version`, `config`, `config_sha256`, `input_spec`, `input_sha256`, `candidates_sha256`, `persona_count`, `candidate_count`, `created_by` / kørselsnøgle, `persona_key`, `candidate_person_id`, `rank`, `score`, `tier`, `basis`, `family_context_sha256` |
  | `control_runs` | `identity_control_run` | kontrolnøgle, populationshashes, `input_list_sha256`, `excluded_sha256`, `k_random`, `cause`, `created_by` |
  | `control_samples` / `control_exclusions` / `control_parent_cards` | tilsvarende tabeller | `persona_key`/`interpretation_key` + alle indholdskolonner (`sample_kind`, `stratum`, versioner, `mapping`, `expected`; `reason`; `family_id`, `counterpart_*`, `partner_ids`) |
  | `control_events` / `control_parent_events` | tilsvarende tabeller | kontrol-/kortnøgle, `seq`, `status`/`outcome`, `note`, `sheet_sha256`, `rows_sha256`, `line`, `reason`, `created_by` |
  | `interpretations` | `interpretation` (kilden, alle prædikater) | `interpretation_key`, `version`, `predicate`, `interpretation_kind`, `value`, `schema_version`, `derivation_kind`, `confidence`, `status`, `method`, `model_version`, `prompt_version`, persona (`source_persona_id`), `supersedes_id`, `decision_evidence`, `decided_by`, `decided_by_name` |
  | `parties` | `interpretation_party` | `interpretation_key`, `party_role`, `version`, persona, `marriage_ordinal`, `post_offset`, `origin` |
  | `classifications` | `relation_classification_event` | `interpretation_key`, `seq`, `interpretation_version`, `classification`, `evidence`, `created_by` |
  | `dispositions` | `clause_disposition` for kildens observationer | `observation_id`, `version`, `disposition`, `decided_by_kind`, `decided_by`, `decided_by_name`, `evidence` (id-arrays oversat **og sorteret** efter oversættelsen) |
  | `writer_profiles` | `reimport_writer_profile` (kilden) | `profile_id`, `profile_version`, `profile_sha256`, `writer_config` |
  | `bindings` | `interpretation_promotion` (kildens fortolkninger) | fortolkningens nøgle, `target_type`, `target_id`, `rule_key`, `rule_version`, `evidence`, `promoted_by` |
  | `family_sources` | `public.public_family_sources(<familier med binding>)` kaldt som `anon` | `(family_id, slags, interpretation_key)` |
  | `authorizations_consumed` / `authorizations_issued` | `reimport_authorization` (kilden) | antal pr. `operation` (+ `manifest_sha256` for `relation_persona`) / antal `issued` (kun rapport) |
  | `counts` | `reimport_batch`, `reimport_event`, `extraction_run`, `interpretation_promotion_batch` | antal pr. operation/profil |

  Evidensnøgler, der udelades (base-bundne): `pack_sha256`, `state_sha256`, `preview_sha256`, `preview_hash`, `set_sha256`,
  `batch_id`, `manifest_sha256`, `supersedes_promotion_id`. Hver tilføjelse er en ruling med begrundelsen »base-bundet«.
- Consumed by: Task 2, 3, 5, 6 og plan B2.

- [ ] **Step 1: Skriv testen** `tests/sql/test-transfer-5ab-digests.sh <prefix>`: byg A og B præcis som
  `test-indholds-id-determinism.sh` (inkl. B's tilfældige forhistorik i kilde −25099) og kør `indholds-id-chain.sql`.
  Asserts (kilde −25001; bindingsassertet på −25002):
  - `dg_same`: digests fra A = fra B for begge kilder, `n_uuid_unmapped = 0`;
  - `dg_ids_differ`: mindst ét `private.interpretation.id` og ét `interpretation_promotion.id` er forskelligt mellem A og B (vagt);
  - `dg_layers_nonempty`: `personas`, `identities`, `candidates`, `control_samples`, `interpretations`, `parties`,
    `classifications` og (−25002) `bindings`, `family_sources` har `n ≥ 1` (vagt);
  - `dg_value`: én ændret `marriage_ordinal` i B ⇒ kun `parties` afviger;
  - `dg_swap`: ombyttet `decision_status` mellem to personas i B ⇒ `identities` afviger;
  - `dg_target`: én binding i B (−25002) med andet `target_id` ⇒ `bindings` afviger;
  - `dg_unmapped`: samme logiske række indsat i A og B med hver sin `gen_random_uuid()` i evidensen ⇒ laget afviger, og
    `n_uuid_unmapped ≥ 1` i begge;
  - `dg_rows`: `mode=rows` i A og B er ens linje for linje, og `dg_value`'s ændring giver præcis én afvigende linje;
  - `dg_readonly`: nøglekort og digests kører under `PGOPTIONS='-c default_transaction_read_only=on'`;
  - `km_old_tree`: nøglekortet kører på en base bygget fra `b42266e` (uden 5b-tabeller) og giver 0 linjer i 5b-klasserne;
  - `km_unique`: nøglekortet er unikt på uuid, og opslagsklasserne er unikke på nøgle.
  Slut: `DG5AB_OK`.
- [ ] **Step 2: Kør** `bash tests/sql/test-transfer-5ab-digests.sh t5abdg` — Expected: FAIL (filerne findes ikke).
- [ ] **Step 3: Implementér** de to filer.
- [ ] **Step 4: Kør** — Expected: `DG5AB_OK`.
- [ ] **Step 5: Commit** `test(151): nøglekort og nøglede digests for 5a+5b-lagene`.

### Task 2: Uberørt-hash, andre kilder og værn

**Files:**
- Create: `.claude/skills/daa-extract/scripts/transfer_5ab_untouched_hash.sql`, `transfer_5ab_guards.sql`
- Modify: `tests/sql/test-transfer-5ab-digests.sh`

**Interfaces:**
- `transfer_5ab_untouched_hash.sql -v src=<id>` ⇒ `daa.transfer_5ab_untouched=<sha>` (som `transfer_untouched_hash.sql`, men
  eksklusionslisten er alle tabeller, kæden skriver i, kortlægningen §B) og `daa.transfer_5ab_other_sources=<sha>` (for hver
  ekskluderet tabel: rækker, hvis kilde ≠ `src`, via `source_id` eller join til `interpretation`/`source_persona`/`source_observation`).
- `transfer_5ab_guards.sql -v src=<id>` ⇒ én linje `daa.transfer_5ab_guards=<json>`: `person_create_elements`
  (`relation_person_create_input(src)`), `ordinal_correction_rows` (`red_marriage_ordinal_correction_input(src)` som ejer),
  `ordinal_book_mismatch` (antal parter, hvor bogens nummer ≠ serverens, `relation_book_ordinal`), `book_ordinal_match`
  (`n_match`/`n_total` for bogens »N°«).
- Consumed by: plan B2 (`VERIFY_OK`, værnene i arbejdskørslen).

- [ ] **Step 1: Udvid testen:** `un_before_after` (i A: kæden ændrer ikke untouched-hashen og ikke `other_sources`, målt før og
  efter i samme base), `un_other_source` (én række i kilde −25099 ændret i B ⇒ kun `other_sources` afviger fra B's før-måling),
  `gd_values` (værnene i A: −25001 `person_create_elements = 0`; −25002 `ordinal_correction_rows ≥ 1` som fixturen er bygget).
- [ ] **Step 2: Kør** — Expected: FAIL på de nye asserts.
- [ ] **Step 3: Implementér.**
- [ ] **Step 4: Kør** — Expected: `DG5AB_OK`.
- [ ] **Step 5: Commit** `test(151): uberørt-hash, andre kilder og værn for 5a+5b-kæden`.

### Task 3: Skridt-SQL i repoet

**Files:**
- Create (`.claude/skills/daa-extract/scripts/`): `transfer_5ab_step_profile.sql`, `transfer_5ab_step_candidates.sql`,
  `transfer_5ab_step_control.sql`, `transfer_5ab_step_corroborate.sql`, `transfer_5ab_step_decide.sql`,
  `transfer_5ab_step_bind.sql`, `transfer_5ab_step_disposition.sql`, `transfer_5ab_step_reject.sql`
- Create: `tests/sql/fixtures/transfer-5ab-chain.sql` (som `indholds-id-chain.sql` trin 1-5 og 7, uden trin 6 og 8)
- Test: `tests/sql/test-transfer-5ab-steps.sh`

**Interfaces:**
- Fælles: `-v src=<id> -v mode=capture|replay -v items=<sti> [-v fault=before_commit]`. Aktøren = første profil med
  `rolle='redaktion'` (`ORDER BY id`). Items beregnes **som ejer** før `SET LOCAL ROLE authenticated`. `capture` skriver de
  nøglede items (`\o :'items'`) og udfører skridtet; `replay` læser `items` (`pg_read_file`), bygger samme items i basen,
  stopper med `STEP_ITEMS_MISMATCH`, hvis de afviger, og kalder RPC'en med hashen **genberegnet i basen**. Udskrift:
  `STEP_OK <skridt> n=<antal> items_sha256=<hex>`; aldrig et uuid.
- Pr. skridt (items sorteret `COLLATE "C"`):
  - `profile` (`sql`): writer-profilerne `relation-persona-2018-20` (v1/v2/v3-konfigurationerne fra `relation_persona_apply.sql`)
    `ON CONFLICT DO NOTHING`; items = `{profile_id, profile_sha256}`.
  - `candidates` (`hash_gated`): kandidatfilen (pakkens input) skrives via `red_record_identity_candidates`; serveren genberegner
    `input_sha256`; items = `{kørselsnøgle, candidates_sha256}`. Erstatter `write-candidates.sql`'s `set_config`-ekko.
  - `control` (`sql`): `red_register_identity_control_run(<seneste kørsel slået op via kørselsnøgle>)`; items =
    `{kontrolnøgle, populationshashes, n_samples, n_parent_cards}`.
  - `corroborate` (`hash_gated`): `corr_set` som `schema.sql:16494-16505`; items = `{persona_key}`; RPC
    `red_corroborate_family_identities(ctl, set_sha256)`.
  - `decide` (`hash_gated`): items fra `private.relation_decision_set(src)->'items'` (som ejer) =
    `{interpretation_key, classification, family_id, book_ordinal, family_ordinal, parter: [{persona_key, person_id}]}`;
    RPC `red_decide_relation_interpretations(src, set_sha256)`, hvor `set_sha256` hentes fra
    `red_preview_relation_decisions(src)` som `authenticated`.
  - `bind` (`hash_gated`): kandidater = accepterede `relation.marriage|parent|child` med bindingstilstand
    (`interpretation_id` via `interpretation_current`); preview som `authenticated`; items = alle preview-items som
    `{interpretation_key, family_id, rule_key, rule_version, eligible, reason_code, supersedes_key}`. Kun `eligible` sendes til
    `red_promote_relation_interpretations_batch` med den genberegnede `preview_sha256`; 0 egnede ⇒ `STEP_OK bind n=0` uden kald.
    `reason_code` ≠ pakkens ⇒ `STEP_ITEMS_MISMATCH` (efter `~/.private/5b-2b-iii/bind-preview.sql` og `bind.sql`).
  - `disposition` (`writer`): manifestet regenereres i basen af `red_relation_disposition_input(src)`; items =
    `{observation_id, disposition, actor_persona_keys, citing_interpretation_keys}` (sorteret efter oversættelsen); ved
    match køres `relation_batch_apply.sql`-forløbet med det regenererede manifest.
  - `reject` (`sql`): items = `{persona_key, interpretation_key, evidence}`; præcis én `relation.marriage` pr. `persona_key`
    via `interpretation_party_current`, ellers `STEP_REJECT_AMBIGUOUS`; evidens =
    `{basis:'human_sheet_review', sheet_sha256:<v3-arkets hash>, sheet_line, reason, decided_on, report}` (alle felter
    påkrævet); RPC `red_decide_interpretation(<id slået op>, <version>, 'rejected', evidens)`.
- Genbruges uændret og står i pakkens inventar: `relation_persona_apply.sql` (`writer`; profilindsættelsen er da no-op),
  `relation_batch_apply.sql`, `sql`-delen af `identity_control_sheet.py`, `spouse_exception_sheet.py`,
  `relation_marriage_sheet.py`, `relation_marriage_sheet_v3.py`, `relation_child_sheet.py`.
- Consumed by: Task 6, plan B2.

- [ ] **Step 1: Skriv fixturen og testen** `tests/sql/test-transfer-5ab-steps.sh <prefix>`: A og B som i Task 1, men med
  `transfer-5ab-chain.sql`. Opsætningsvagter: ≥ 1 decide-item, ≥ 1 egnet bind-item i −25001, ≥ 1 dispositions-item (ellers
  udvides fixturen; ruling). Asserts:
  - `st_capture_replay`: profile, decide, bind, disposition og reject i `capture` på A, `replay` på B med A's items ⇒ ens
    digests (`interpretations`, `classifications`, `bindings`, `dispositions`, `writer_profiles`) og ens `items_sha256`;
  - `st_mismatch`: replay med én item fjernet ⇒ `STEP_ITEMS_MISMATCH`, digests uændrede;
  - `st_rerun`: bind i `replay` to gange ⇒ anden gang `n=0`, 0 nye rækker;
  - `st_fault`: decide med `fault=before_commit` ⇒ fejl, digests = før; derefter uden fejl ⇒ som `st_capture_replay`;
  - `st_writer_issued`: dispositionsskridtet afbrudt efter `red_authorize_reimport` ⇒ digests i skridtets lag = før; fuldt
    skridt bagefter ⇒ som uafbrudt; `authorizations_issued` = 1;
  - `st_reject_ambiguous`: `reject` på en `persona_key` med to ægteskaber ⇒ `STEP_REJECT_AMBIGUOUS`;
  - `st_no_uuid`: ingen udskrift indeholder et uuid.
  Slut: `STEPS5AB_OK`.
- [ ] **Step 2: Kør** `bash tests/sql/test-transfer-5ab-steps.sh t5abst` — Expected: FAIL (filerne findes ikke).
- [ ] **Step 3: Implementér** de otte filer.
- [ ] **Step 4: Kør** — Expected: `STEPS5AB_OK`.
- [ ] **Step 5: Commit** `feat(151): skridt-SQL med nøglede items og hashes genberegnet i basen`.

### Task 4: Køens ark i repoet

**Files:**
- Create: `.claude/skills/daa-extract/scripts/identity_queue_sheet.py`
- Test: `.claude/skills/daa-extract/scripts/test_identity_queue_sheet.py`

**Interfaces:**
- `render --details <koe-detaljer.json> --out <ark>`: én `Q <persona_id> <ver> : _ # ` pr. persona i detaljedumpet (køen =
  kildens `proposed` ægtefællepersonas, samme mængde som SQL'ens `$chk$`), sorteret efter `persona_id`.
- `sql --sheet <ark> --approved-sha256 <h> --details <json> --source <id> --out <sti>`: port af `~/.private/5b-2b-i/koe-apply.py`:
  linjeformat `Q <persona_id> <ver> : same <person_id>|N|X|U # <grund>`, kontekst `{basis:'human_sheet', sheet_sha256,
  rows_sha256, line}`, note i **samme format** `kø 2b-i <sh[:12]> sag <n> — <grund>`, mængdevagt `KOE_ROWS_STALE` (over
  persona-id'er, ikke over detaljedumpets hash), `KOE_COUNT_MISMATCH`. Fejlkoder: `KOE_SHEET_HASH_MISMATCH`, `KOE_LINE_COUNT`,
  `KOE_LINE_INVALID <n>`, `KOE_PERSONA_UNKNOWN <n>`.
- Noten bærer arkets hash; oversatte persona-id'er giver nyt ark, ny note og dermed nyt v3-ark (forventet kaskade, B2's
  §6.3-liste).

- [ ] **Step 1: Skriv tests:** `render` giver én linje pr. persona i sorteret orden; gyldigt ark ⇒ N kald og noten for linje 3 er
  `kø 2b-i <12 hex> sag 3 — <grund>`; forkert hash; forkert antal; ukendt persona; dublet; `same` uden person.
- [ ] **Step 2: Kør** `pytest .claude/skills/daa-extract/scripts/test_identity_queue_sheet.py -q` — Expected: FAIL.
- [ ] **Step 3: Implementér.**
- [ ] **Step 4: Kør** — Expected: grønne.
- [ ] **Step 5: Commit** `feat(151): køens ark i repoet (port af 2b-i's kø-anvendelse)`.

### Task 5: Svaroverførslen

**Files:**
- Create: `.claude/skills/daa-extract/scripts/transfer_answers.py`
- Test: `.claude/skills/daa-extract/scripts/test_transfer_answers.py`

**Interfaces:**
- `transfer --kind <control|spouse|queue|marriage|marriage_v3|child> --old-sheet <ark> --old-rows <json> --old-keymap <tsv>
  --new-sheet <ark> --new-rows <json> --new-keymap <tsv> --expected-dropouts <fil> --out-sheet <sti> --out-report <sti>`.
- Hver svarlinje parses efter værktøjets grammatik; `ref` oversættes gammel uuid → nøgle (opslagsklasse) → ny uuid; nøgle-referencer
  (`interpretation_key`) er uændrede. `spouse` accepterer også den gamle `O <interpretation_id> b/f` (v1) og oversætter id'et via
  `fortolkning:<key>#<ver>` til den nye `O <key> <ver> …`-linje. `control`: kun `R`-linjer overføres; `D` står tomme (`_`).
- Implicitte rang-svar (`R…A`, 2b-i `S`, `M…S`) og `same <person>`: den gamle linjes person slås op i `--old-rows`; i den nye
  linjes kandidater (`--new-rows`) skal samme `person_id` stå på samme plads, ellers `ANSWER_PERSON_MOVED <n>`.
- Stop: `ANSWER_NO_TARGET <n>`, `ANSWER_NO_SOURCE <n>` (bortfaldslisten undtaget), `ANSWER_VERSION_CHANGED <n>`,
  `ANSWER_PERSON_MOVED <n>`, `KEYMAP_DUPLICATE` (dublet på uuid, eller på nøgle i en opslagsklasse).
- Rapporten (0600): pr. linje gammel og ny tekst efter oversættelse til nøgler, også kontekstlinjer (kandidater, familie, nummer,
  klausul), markeret `=`/`~`/`-`/`+`. Stdout kun `ANSWERS_OK kind=… overfoert=… bortfald=… aendret=… report_sha256=…`.

- [ ] **Step 1: Skriv tests** med syntetiske ark, rækkefiler og nøglekort for hver `kind`: entydig overførsel; svar uden mål og
  mål uden svar stopper; forventet bortfald tælles; rang til en anden person stopper; gammel `O`-grammatik oversættes; `control`
  `D` står tom; ændret kontekstlinje markeres `~`; mange-til-én-klasse udløser ikke `KEYMAP_DUPLICATE`, dublet i opslagsklasse
  gør; stdout uden uuid og navn.
- [ ] **Step 2: Kør** `pytest .claude/skills/daa-extract/scripts/test_transfer_answers.py -q` — Expected: FAIL.
- [ ] **Step 3: Implementér.**
- [ ] **Step 4: Kør** — Expected: grønne.
- [ ] **Step 5: Commit** `feat(151): svaroverførsel fra beviskædens ark via nøgler`.

### Task 6: Pakken og et genspil på tværs af to baser

**Files:**
- Create: `.claude/skills/daa-extract/scripts/transfer_steps.py`
- Test: `.claude/skills/daa-extract/scripts/test_transfer_steps.py`
- Modify: `tests/sql/test-transfer-5ab-steps.sh` (genspil af en minipakke)

**Interfaces:**
- Pakke-JSON `transfer-pack-5ab-v1`: `{version, base: {d1_receipt_sha256, restore_hash}, inventory: {sti: sha256},
  steps: [{n, name, type: "sql"|"writer"|"hash_gated", script, vars, inputs: {navn: sha256}, items_sha256, layers: [lag],
  digests_in: {lag: sha}, digests_out: {lag: sha}, seconds}], pack_sha256}`; `pack_sha256` = sha af kanonisk JSON uden feltet.
- `add-step`, `validate` (`PACK_INVALID <felt>`: rækkefølge, `layers` ⊆ Task 1's lag, `authorizations_issued` aldrig i
  `layers`, `items_sha256` påkrævet for alle typer), `classify --pack --n --digests` ⇒ `WRITE` / `ALREADY_APPLIED` /
  `MIXED` (exit 3; kun over skridtets lag), `inventory --pack --root --private` (`INVENTORY_MISMATCH`), `next --pack --done`.
  Ukendte argumenter ⇒ exit 2.
- Genspilsløkken (B2's runner kalder det samme): for hvert skridt `classify` → `WRITE`: kør skridt-SQL i `replay` → mål
  digests → `classify` skal give `ALREADY_APPLIED`, ellers stop.

- [ ] **Step 1: Skriv pytest:** gyldig pakke; ukendt type; ude af rækkefølge; `authorizations_issued` i `layers`; de tre
  tilstande kun over skridtets lag; `pack_sha256` ændres af én item-hash; inventar med ekstra og manglende fil; `next` springer
  `ALREADY_APPLIED` over; ukendt argument exit 2.
- [ ] **Step 2: Udvid `test-transfer-5ab-steps.sh`:** `st_pack_replay` — byg pakken fra A's capture (Task 3's skridt), genspil
  den på en frisk C (bygget som B) via løkken ⇒ hvert skridt `WRITE` → `ALREADY_APPLIED`, og alle digests = A's; anden
  gennemkørsel ⇒ alle `ALREADY_APPLIED` uden skrivning.
- [ ] **Step 3: Kør begge** — Expected: FAIL.
- [ ] **Step 4: Implementér** `transfer_steps.py`.
- [ ] **Step 5: Kør** — Expected: pytest grønne og `STEPS5AB_OK`.
- [ ] **Step 6: Commit** `feat(151): pakkeformat for data-ceremonien og genspil på tværs af baser`.

### Task 7: CI og dokumentation

**Files:**
- Modify: `.github/workflows/ci.yml` (pytest: `test_identity_queue_sheet.py`, `test_transfer_answers.py`, `test_transfer_steps.py`;
  `writer-1939-v50-db`: `test-transfer-5ab-digests.sh ci_dg5ab` og `test-transfer-5ab-steps.sh ci_st5ab` efter
  `test-indholds-id-determinism.sh`)
- Modify: `docs/decisions.md` (plan B delt i B1/B2; errata; skridt-scripts i repoet; profilskridt; dispositionernes manifest-hash),
  `docs/evidensbaseret-genimport/status.md` (række »Værktøj til data-ceremonien (plan B1)«, `isoleret implementeret`),
  `docs/changelog.md`

- [ ] **Step 1:** Tilføj testene; kør pytest-listen og hele `writer-1939-v50-db` lokalt. Expected: `CI_JOB_OK`, og jobbets
  varighed noteret (CI-minutbudget).
- [ ] **Step 2:** Skriv de tre dokumenter.
- [ ] **Step 3: Commit** `docs(151): plan B1 — værktøj til data-ceremonien (CI, beslutning, status)`.

## Til plan B2 (ikke i B1)

- Privat runner (prod-vagter, `--jeg-mener-det`, GO-hashes) om Task 6's løkke; arbejdskørslen; måling af H2 (ægteskabsnumre i
  del 1) og forhistorikken i bevisbaserne (kontrolkørsler, kandidatkørsel 1) før kørslen; listen over forventede forskelle (§6.3,
  inkl. køens note → v3-kaskaden); nøglekortet kørt på hver bevisbase; uafhængigt review af de private scripts før GO 2.
- **H3 (projektejeren 2026-10-22):** kandidatkørsel 1 (top-k 3) genskabes ikke; forventet bortfald i §6.3-listen.

## Revision efter Opus-review (2026-10-22)

GO med rettelser; 9 MAJOR, alle godtaget efter efterprøvning mod koden (`schema.sql:16697` fjerner items i preview;
`:17321` dispositionsevidensens `manifest_sha256`; `relation_persona_apply.sql:6-10` profil før autorisation).

| Fund | Ændring |
| --- | --- |
| M1 decide-items fjernes af preview | Task 3: items som ejer fra `relation_decision_set`, udvidet med familie, numre og parter |
| M2 bind-genkørsel | Task 3: kun egnede sendes; 0 ⇒ `n=0`; alle grunde i items |
| M3 `manifest_sha256` i dispositionsevidens | Task 1: udeladelseslisten; lagvagt `dg_layers_nonempty`, dispositionsvagt i Task 3 |
| M4 fixtures passer ikke | Ny `transfer-5ab-chain.sql`; untouched før/efter i samme base; bindingsassert på −25002 |
| M5 svaroverførslens interface | Task 5: `--old-rows`/`--new-rows`, gammel `O`-grammatik, `KEYMAP_DUPLICATE` kun for opslag; Task 4: `render` |
| M6 profil før autorisation ⇒ `MIXED` | Errata + `profile`-skridt; `validate` forbyder `authorizations_issued` i `layers` |
| M7 bevisbasernes ældre skema | Task 1: tabelvagter, `km_old_tree` |
| M8 ingen nøglet rækkeudskrift | Task 1: `mode=rows`, `dg_rows` |
| M9 genspiller og værn | Task 2: værn-SQL; Task 6: genspilsløkke testet på tværs af baser; runneren i B2 |
| MINOR (kolonneliste, `d1:`-klasse, `dg_unmapped`, `bindingsbatch`, sorterede arrays, notens format, `KOE_ROWS_STALE`, P-evidens, uuid i udskrift, `\o`/0600, dispositionsinput, transaktion og fejlkrog) | Indarbejdet i Global Constraints og Task 1-6 |
