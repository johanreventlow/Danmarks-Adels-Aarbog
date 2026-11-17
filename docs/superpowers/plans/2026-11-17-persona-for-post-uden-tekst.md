# Persona for en helpost uden tekst — Henrik og Iven (1939) — implementeringsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Henriks (934) og Ivens (929) egne 1939-poster får persona, identitet, placement og en upubliceret kladde,
så projektejeren kan rette og publicere teksterne i redaktøren.

**Architecture:**
- **Ny elementoperation** `record_persona` i den fælles reimport-writer (authorize → begin → apply → finalize). Den
  skriver persona og mention for en helpost uden aktiv tekstbinding. Ingen identitet.
- **Én dataceremoni** i én transaktion: personas, identiteter (`red_afgoer_source_persona`, `human_sheet`),
  placements (`write_record_placement`/`write_persona_placement`), ledger, betinget medlemskab og til sidst kladderne
  (`red_upsert_person_narrative_record`). Persona og identitet i samme transaktion lukker identitetsvinduet
  (spec §4.1, Køen).
- **Prod:** én DDL- og én dataceremoni gennem en privat runner efter 6d-2a's mønster.

**Tech Stack:** PostgreSQL 17 (plpgsql, psql), R (samtidighedstest), Python (målescript-test), bash/zsh (runner,
opgraderingstest).

**Spec:** `docs/superpowers/specs/2026-11-17-persona-for-post-uden-tekst-design.md` (godkendt 2026-11-17).

## Roadmap-kobling

Spec §1: trin 6, færdigbevis (a); legacy-afvikling af 6d-2b's tilbagetrækninger. Færdigbevis: Task 6 trin 5 (spec §8).
Review-budget: én Codex-runde (`gpt-6.1-sol`) på spec+plan (Task 0 trin 6), én på diffen (Task 6 trin 1); Opus
afvejer hvert fund.

## Global Constraints

- **Gren:** `feat/record-persona` fra `docs/spec-persona-uden-tekst`. PR'er altid `--draft`. Intet push uden
  projektejerens ja.
- **Prod** røres kun i projektejerens shell med GO (`--jeg-mener-det --go <kode>`); AI'en kører kun mod lokale baser.
  Dump med ekstern `age`-kopi før hver skrivende ceremoni; vinduesvagt; fortryd = restore + `db-rls.sql`.
- **`schema.sql` er source of truth.** `db-migrations.sql` får én ny blok sidst, der begynder med
  `-- ===== record_persona: persona for helpost uden tekst =====`; nye/ændrede funktioner har byte-ens krop i begge
  filer; idempotent (to kørsler). Ældre blokke redigeres ikke.
- **Editionsneutral:** operationens navn, writer, fejlkoder og ceremoni nævner ingen udgave og intet kilde-id.
  Persona-nøglens prefix kommer fra profilens `writer_config->>'persona_key_prefix'`.
- **Afgrænsning (spec §3 pkt. 3):** kun `record-e63debca-6fb4-456e-9b11-90a8676d98b8` → 934 og
  `record-9db9004f-d6a7-4b98-bd0f-f1f90ba770d8` → 929. Claus, Emeke, Volrads 601 og de øvrige 19 helposter uden
  tekst røres ikke.
- **Ingen publicering i ceremonien.** Kladderne er `draft`; projektejeren publicerer selv i redaktøren.
- **Ingen OCR-rettelser i ceremonien.** Kladden er bogpostens `verbatim_text`, foldet, og sidemarkøren fjernet.
- **Indholds-id'er:** manifest og ceremoni refererer record keys, mention-id'er og -hashes, person-id'er og kortarkets
  sha, aldrig id'er oprettet af en ceremoni.
- **Uberørte:** 2018-20's data og koordinater, 6d-1's 528 placements, de 565 synlige 1939-publiceringer (efter
  projektejerens publicering: + 2 − 1, spec §8; 944's omtale bliver oversigtsomtale), 598 og 603 (`withdrawn`),
  `public_person_facts`, `public_family_sources`.
- **Tidsbudget:** intet anon-kald mere end 10 % langsommere end før DDL'en (median af 3, samme base).
- **PII (invariant 8):** 1939-tekst må vises for projektejeren (alle afdøde, memory `work-1939-maa-laeses`). Kort,
  manifest og målinger kun under `~/.private/record-persona/` (0600). Tests bruger opdigtede personer med negative
  id'er. Chat og commits: tal, nøgler, hashes.
- **Miljø:** `env -u PGOPTIONS` foran psql, `env -u NODE_OPTIONS` foran npm. Prods `statement_timeout` er 2 min.
  RPC'er med rollegate kræver `request.jwt.claim.sub` (memory `rpc-rollegate-kraever-jwt-claim-sub`).
- **Implementer-briefs:** ingen kommando på `~/.private`, heller ikke `ls`; drop ikke databaser, list dem.
- **Commits:** atomiske, Conventional Commits på dansk, ingen Claude-attribution; trailer
  `Claude-Session: https://claude.ai/code/session_01VptDx18kYJxFNYtqfmHDvH`.

## Review Focus

1. **Posten får en tekst mellem manifest og ceremoni** (en redaktør opretter en kladde). Writeren skal afvise med
   `RECORD_PERSONA_BINDING_PRESENT`, og ceremonien må intet skrive. Låses af `binding_present` (Task 2) og
   `T_RP_PRE_MANIFEST` (Task 4).
2. **Kortarkets person passer ikke til forudsætningerne** (levende, ingen ekstern nøgle i kilden, findes ikke).
   Afvises før skrivning. Låses af `subject_*`-testene (Task 2).
3. **Ceremonien køres to gange.** Den anden kørsel skal stoppe uden at skrive. Låses af `T_RP_PRE_FASE` (Task 4).
4. **Nogen fortryder `legacy_withdrawn` på 598/603, når personen har (haft) en record-binding i samme kilde.** Afvises
   med `NARRATIVE_LEGACY_RECORD_BINDING_EXISTS` (spec §4.5, bred spærring). Låses af `$to_tekster$` (Task 2) i tre
   forløb.
5. **Medlemskabspromoveringen rammer andre end de to.** Ceremonien stopper uden at skrive (`T_RP_PRE_MEDLEMSKAB`).
   Låses af `$medlemskab_andre$` (Task 4).
6. **Et `N` eller ugyldigt svar i svarfilen.** Hele ceremonien stopper før authorize (`T_RP_PRE_SVAR`); intet skrives.

---

### Task 0: Måling, kortark og Codex-runde (kun lokalt; ingen kode-commits)

Noter, tider, kort og manifest i `~/.private/record-persona/` (0600). Stand-in fra en frisk prod-`dump-kopi`.

**Udført 2026-11-17** (resultat: spec §9.1; noter `~/.private/record-persona/task0-noter.md`; stand-in
`daa5ab_ddl_standin_20261117165851_rp0`, eksperimenter rp1/rp2). Kortark `kort.html`, manifest `kortmanifest.jsonl`
(sha256 `20b4a68d…`), svarfil `kort-svar.txt` (tjek: `python3 -I tjek_svar.py`). **Udestår:** projektejerens kortsvar.

- [x] **Trin 1 (spec §9.1):** 6d-1's regel for entry, overskriftsobservation, `section_path`, slægtled og kuld anvendt
  på de to poster. Afgør, om »Til samme Generation, ikke Brødre, hørte:« er en overskriftsobservation; ellers foreslå
  nærmeste slægtledsoverskrift. Resultat: ét forslag pr. post til kortet.
- [x] **Trin 2 (spec §9.2):** ledgerfunktionens krav (`mapped` for 929/934) og `red_promote_placement_memberships(3,
  …)`'s forhåndsvisning på stand-in'en efter en prøveplacering. Notér, om den rammer præcis 929 og 934 uden fejl.
- [x] **Trin 3 (spec §4.5):** biografilæserne (web v2 og mobilens v1), oversigtsreglen, udgavevælgeren (6e-1),
  `red_person_narrative_records` og publiceringshistorikken med to kilde-3-narrativrækker pr. person. Afgør og notér:
  spærres fortrydelsen af `legacy_withdrawn` (598/603), når personen har en aktiv record-binding i samme kilde, eller
  dokumenteres den? Spærring kræver en ændring i `private.reverse_narrative_publication_event`, som så føjes til
  Task 2's filer. **Afgjort:** bred spærring (spec §4.5), i Task 2.
- [x] **Trin 4 (spec §9.4):** foldningsfunktionen (`private.relation_fold_raw_text` eller 6d-3's profilfoldning) på de
  to `verbatim_text`. Resultatet går på kortet.
- [x] **Trin 5 (spec §9.5):** om `red_source_persona_queue` viser en `record_persona`-persona uden identitet, og om
  profilen `daa-1939-publication-v1` kan bære operationen (`persona_key_prefix` = `1939:`). Ellers seedes en ny
  profilrække i Task 1.
- [x] **Trin 6:** kortark (HTML efter memory `kortark-kraever-kontekst-html`, token-fil efter
  `menneske-gennemgang-token-fil`): pr. post sidebillede, bogtekst, foldet kladde, personens 1939-fakta, linket til
  2018-20, den tilbagetrukne tekst og placementforslaget. Projektejeren svarer J/N pr. linje (identitet) og
  godkender eller retter placementen. Manifest (kanonisk JSON pr. linje: record key, mention-id, mention-tekst-sha,
  person-id, placementværdier, foldet teksts sha) hashes; svarfilen refererer manifestets sha.
- [x] **Trin 7:** Codex-runde (`gpt-6.1-sol`) på spec+plan; Opus afvejer; ret spec/plan efter projektejerens ja.

### Task 1: Registrering af operationen

**Files:**
- Modify: `schema.sql`:
  - `private.ensure_reimport_operations` kaldes med `ARRAY['record_persona']` (mønster fra 6b);
  - `private.validate_reimport_authorization_payload`: `expected_counts`-nøglen `record_personas`, prefixet
    `record-persona:`, tællingen pr. prefix, og den tilladte nøglemængde udvides med én;
  - `public.red_finalize_reimport`: én `CASE`-arm efter mønstret for `publication_persona`;
  - `public.red_reimport_batch_result` (`:5523-5556`): de lukkede lister (tællenøgle, antal nøgler op til 13, prefix
    `record-persona:`, `operation IN (…)`), som 6b udvidede dem;
  - **ingen** ændring af `red_reverse_reimport`: den kræver en aktiveret batch med navnefuldendelses-barn, og
    `red_reverse_reimport_publication` kun `publication_identity`; begge afviser allerede med
    `REIMPORT_WRITER_REVERSAL_INVALID` (spec §4.1);
  - ingen profilrække (Task 0 trin 5: `daa-1939-publication-v1` bærer operationen).
- Modify: `db-migrations.sql` (den nye blok).
- Create: `tests/sql/test-record-persona-registration.sql`.
- Modify: `.github/workflows/ci.yml`: kør testen efter `schema.sql` og efter `db-migrations.sql` (to gange).

**Interfaces:**
- Produces: operationen `record_persona` kan autoriseres med
  `{"person_creates":0,"source_evidence":0,"record_personas":n}` og elementer `record-persona:<record_key>`,
  finaliseres og aflæses med `red_reimport_batch_result`; de generelle fortrydelser afviser den.

- [ ] **Step 1: Skriv testen** (`BEGIN … ROLLBACK`): autorisation med 2 elementer lykkes; én for mange eller forkert
  prefix → `REIMPORT_WRITER_AUTHORIZATION_INVALID`; finalize med 2 events og `record_personas:2` lykkes, med 1
  forventet → `REIMPORT_WRITER_FINALIZE_COUNT_MISMATCH`; `red_reimport_batch_result` på den finaliserede batch giver
  `status='finalized'` og `record_personas=2`; `red_reverse_reimport` og `red_reverse_reimport_publication` på batchen
  → `REIMPORT_WRITER_REVERSAL_INVALID`; eksisterende profilers `profile_sha256` uændrede (hårdkodet fra `main`).
- [ ] **Step 2:** Kør mod `schema.sql`. Forventet: fejl.
- [ ] **Step 3: Implementér.**
- [ ] **Step 4:** Kør mod frisk `schema.sql` og mod `db-migrations.sql` kørt to gange. Forventet: `OK`.
- [ ] **Step 5:** Commit `feat(db): registrér operationen record_persona`.

### Task 2: Writeren `record_persona`

**Files:**
- Modify: `schema.sql`: `private.write_record_persona(p_batch_id uuid, p_element_id text, p_payload jsonb) RETURNS
  jsonb` og `public.red_apply_reimport_record_persona(uuid, text, jsonb) RETURNS jsonb` efter
  `write_publication_persona` (`:18180`); REVOKE/GRANT som `red_apply_reimport_publication_persona`.
- Modify: `schema.sql`: **spærringen (spec §4.5)** i `private.reverse_narrative_publication_event` (`:16412`): for
  `event_type='legacy_withdrawn'`, som selvstændig sætning efter `LOCK TABLE public.change_set` (`:16488`), afvis med
  `NARRATIVE_LEGACY_RECORD_BINDING_EXISTS`, når personen (`v_person_id`) har en narrativ i `v_target.source_id` med en
  række i `private.narrative_record_publication` (enhver status); og en tilsvarende arm i `reversal_blocking_reason` i
  `public.red_person_narrative_publication_history` (`:15836-15842`, 149b-mønstret).
- Modify: `db-verify.sql` (wrapperen i `v_authenticated`-listen), `db-rls.sql` (REVOKE/GRANT og fladevagtens
  `red_surface_expected`, `:1635`), `db-migrations.sql`.
- Create: `tests/sql/test-record-persona.sql`, `tests/integration/test-record-persona-concurrency.R` (mønster
  `test-publication-persona-concurrency.R`).
- Modify: `.github/workflows/ci.yml`.

**Interfaces:**
- Consumes: Task 1; `private.record_helpost_observation(record_id, helpost_kind)`,
  `private.writer_config_helpost_kind`, `private.content_uuid`, `private.reimport_canonical_json_sha256`.
- Produces:
  - payloadens lukkede nøglesæt (sorteret): `mention_id`, `mention_text_sha256`, `person_id`, `persona_key`,
    `sheet_line`, `sheet_sha256`, `source_id`, `source_record_key`. `sheet_sha256` er 64 hex; `sheet_line` ≥ 1;
  - kvittering (returværdi og `reimport_event.payload->'result_receipt'`): `source_persona_id`, `mention_id`,
    `person_id`, `sheet_sha256`; `reimport_event.canonical_person_id` = `person_id`.

Rækkefølge som `write_publication_persona` (spec §4.1), med disse forskelle: trin 4 kræver **0** rækker med status
`draft` eller `published` på posten (ellers `RECORD_PERSONA_BINDING_PRESENT`); personen skal desuden have
`levende IS FALSE` (ellers `RECORD_PERSONA_SUBJECT_INVALID`). Fejlkoder i øvrigt: `RECORD_PERSONA_ISOLATION`,
`RECORD_PERSONA_PAYLOAD_INVALID`, `RECORD_PERSONA_RECORD_MISSING`, `RECORD_PERSONA_MENTION_DRIFT`,
`RECORD_PERSONA_EXISTS`. Ingen identitet, ingen placement.

- [ ] **Step 1: Skriv tests:**
  - `happy_path`: persona med forventet indholds-id og nøgle `<prefix><record_key>`, én `primary`-mention, ingen
    `source_persona_identity`-række, kvitteringen stemmer; `narrative_publication_state` uændret (stadig
    `missing_identity`);
  - `binding_present`: en `draft`-binding, en `published`-binding → `RECORD_PERSONA_BINDING_PRESENT`; kun en
    `withdrawn`-binding → lykkes;
  - `mention_drift`, `helpost_ambiguous` → `RECORD_PERSONA_MENTION_DRIFT` / 6a's kode;
  - `subject_levende`, `subject_no_external_id` (0 rækker i kilden, én i en anden kilde), `subject_missing` →
    `RECORD_PERSONA_SUBJECT_INVALID` (to rækker i samme kilde kan ikke etableres: PK `(person_id, source_id)`);
  - `persona_exists`: en persona med mention i helposten → `RECORD_PERSONA_EXISTS`;
  - `payload_invalid`: manglende `sheet_sha256`, ekstra nøgle, forkert prefix → `RECORD_PERSONA_PAYLOAD_INVALID`;
  - `not_awaiting_control`: `private.persona_awaiting_control(persona)` er `false`, og
    `red_afgoer_source_persona(…,'same',…,{basis:'human_sheet',…})` lykkes bagefter;
  - `full_chain`: authorize → begin → apply → finalize med `record_personas` = 2; replay giver `already_applied`;
  - samtidighed (R): to batches med samme record; den anden fejler med `RECORD_PERSONA_EXISTS`;
  - `$to_tekster$` (spærringen; opdigtet person med `legacy_withdrawn` og en record-post) i tre forløb, alle stoppet
    ved fortrydelsen af legacy med `NARRATIVE_LEGACY_RECORD_BINDING_EXISTS`: (a) kladde → publicér → fortryd legacy;
    (b) kladde → kassér → fortryd legacy; (c) publicér → tilbagetræk → fortryd legacy. Efter hvert: v1 og v2 som anon
    giver én eller nul tekster for kilden; historikkens `reversal_blocking_reason` er sat for legacy-hændelsen. Uden
    record-binding kan legacy stadig fortrydes (kontrol).
- [ ] **Step 2:** Kør. Forventet: fejl.
- [ ] **Step 3: Implementér.**
- [ ] **Step 4:** Kør testene og `db-verify.sql`. Forventet: `OK`.
- [ ] **Step 5:** To commits: `feat(db): writer-operationen record_persona — persona på helpost uden tekst` og
  `feat(db): spær fortrydelse af legacy_withdrawn ved record-binding i samme kilde` (spærringen og `$to_tekster$`).

### Task 3: Opgraderingstest og hele CI lokalt

**Files:** Create `tests/sql/test-record-persona-upgrade.sh` (kopi af `tests/sql/test-6e2-upgrade.sh`).

- [ ] **Step 1:** Byg fra `git merge-base origin/main HEAD` (tjek origin/main for SQL-ændringer før prod, memory
  `parallel-db-aendring-ugyldiggoer-generalproeve`). Base-tjek (som `test-6e2-upgrade.sh:46-52`): basens
  `reimport_event_operation_check` mangler `record_persona`, og wrapperen findes ikke, ellers `UPGRADE_BASE_INVALID`.
  Kør nye `db-migrations.sql` + `db-rls.sql` to gange; assert CHECK-mængden = basens ∪ {`record_persona`}; assert at
  validator, finalize, `red_reimport_batch_result`, writer, wrapper, `reverse_narrative_publication_event` og
  `red_person_narrative_publication_history` har `schema.sql`'s kroppe (`pg_get_functiondef`-sha) og ACL; kør Task
  1-2's testfiler og `run-db-verify-disposable.sql`; også frisk `schema.sql` efterfulgt af migrationen; slut med
  `echo UPGRADE_OK`.
- [ ] **Step 2:** Kør den. Forventet: `UPGRADE_OK`.
- [ ] **Step 3:** Hele CI-jobbet lokalt (alle PostgreSQL-jobs, python, R, node med `tsc --noEmit`); tjek exit-koder
  (memory `koer-hele-ci-jobbet-lokalt`). Forventet: grønt.
- [ ] **Step 4:** Commit `test(db): opgraderingstest for record_persona`.

### Task 4: Dataceremoniens SQL og målescript

**Files:**
- Create: `.claude/skills/daa-extract/scripts/record_persona_ceremoni.sql` (kildeparametriseret; tager manifestet og
  svarene som JSON-filer og deres sha), `maal_record_persona.sql`, `tests/test_maal_record_persona.py`.
- Create: `tests/sql/test-record-persona-ceremoni.sh`.
- Modify: `.github/workflows/ci.yml` (python-jobbets filliste og sql-jobbet).

**Interfaces:**
- Consumes: Task 2's `red_apply_reimport_record_persona` og payload; `red_afgoer_source_persona(persona, 0, 'same',
  person, note, {"basis":"human_sheet","sheet_sha256":…,"rows_sha256":…,"line":…})`;
  `private.write_record_placement(record_id, entry_id, values, header_obs, evidence)`;
  `private.write_persona_placement(persona_id, record_placement_id, basis_obs, evidence)`; ledgerfunktionen fra Task 0
  trin 2; `red_promote_placement_memberships(source_id, preview_sha256)`;
  `red_upsert_person_narrative_record(person, source, record_key, tekst, false, expected_state_sha256)`.
- `maal_record_persona.sql` printer én linje: `T_RP_MAAL fase=<foer|ddl|data> personas=<n> identiteter=<n>
  placements=<n> kladder=<n> eligible=<n> header_violations=<n> synlige_1939=<n> KOORD_2018_20=<md5> KOORD_SRC=<md5>
  FAKTA=<md5> BIO=<md5>`, regnet for de manifest-nævnte record keys (`-v` variabler, ingen nøgler i scriptet).
- Ceremonien: én transaktion; svarfilen skal have præcis én `J` pr. linje i manifestet (ethvert `N`, manglende eller
  dobbelt svar → `T_RP_PRE_SVAR`, før authorize; intet skrives); svarfilens sha → ellers `T_RP_PRE_SHA`; førtilstanden
  efterprøves under lås mod manifestet (mention-sha, ingen binding på posten, ingen persona, legacy-status `withdrawn`
  for 598/603) → ellers `T_RP_PRE_MANIFEST`; allerede kørt → `T_RP_PRE_FASE`. Rækkefølge: authorize/begin/apply/
  finalize (2 elementer) → `LOCK TABLE public.change_set IN ACCESS EXCLUSIVE MODE` → identiteter → placements (værdier
  fra manifestet, spec §4.3; `evidence.basis='human_sheet'`) → ledger (`record_legacy_disposition` → `mapped`) →
  medlemskab (forhåndsvisningens `eligible`-mængde skal være præcis manifestets personer, ellers
  `T_RP_PRE_MEDLEMSKAB` og alt rulles tilbage) → `narrative_publication_state` = `accepted_identity` for begge →
  kladder sidst (tekst = `btrim(relation_fold_raw_text(occurrence).folded)`, sha mod manifestets `foldet_sha256`).
  `app.change_set_id` nulstilles før hvert narrativkald. POST: `eligible=2` (`existing_exact_binding`), `kladder=2`,
  `header_violations=0`, `FAKTA`, `BIO`, `KOORD_2018_20` og `synlige_1939` uændrede (publiceringen sker først senere).
  Kvittering `T_RP_OK personas=2 identiteter=2 placements=2 medlemskab=2 kladder=2` som change_set-/auditpost.

- [ ] **Step 1: Fejlende tests** på en lokal base med opdigtede poster og personer: `J` på begge → kvittering og
  `eligible=2`; et `N` → intet skrevet overhovedet (`T_RP_PRE_SVAR`); manglende/dobbelt svar → `T_RP_PRE_SVAR`;
  forkert svar-sha → `T_RP_PRE_SHA`; en kladde oprettet efter manifestet → `T_RP_PRE_MANIFEST`; gentaget kørsel →
  `T_RP_PRE_FASE`; `$medlemskab_andre$`: forhåndsvisningen rammer en tredje person → `T_RP_PRE_MEDLEMSKAB`, intet
  skrevet; hver skrevet identitet matcher sin manifestlinjes person; målescriptets format (`test_maal_record_persona.py`).
- [ ] **Step 2-4:** Kør (fejl) → implementér → grønne.
- [ ] **Step 5:** Commit `feat(data): dataceremoni og målescript for record_persona`.

### Task 5: Runner, runbook og generalprøve

**Files:**
- Create (privat, aldrig i repoet): `~/.private/5ab-overfoersel/42-record-persona.sh` (+ `42-record-persona-vindue.sql`)
  efter `34-trin6d2a.sh`: `maal`, `anon`, `dump`, `dump-kopi`, `standin`, `go-ddl`, `apply-ddl`, `go-data`,
  `apply-data`, `verify`, `fortryd`.
- Create: `docs/runbooks/record-persona-prod.md`.

- [ ] **Step 1: Runner:** GO binder sha over DDL-blokken, ceremoni-SQL, målescript, manifest, svar, runner og
  vinduesvagt samt commit, og over begge `db-rls.sql`-versioner: basecommits (fortryd-DDL, memory
  `fortryd-ddl-rls-foer-grenen`) og grenens (fortryd-data). Dump + ekstern kopi med efterprøvet sha før hver `apply-*`. Vinduesvagten: præcist tilladt
  write-set pr. ceremoni. `anon` måler tidsbudgettets kald mod baseline (fejl over +10 %).
- [ ] **Step 2: Runbook:** `maal → anon → dump → dump-kopi → go-ddl → apply-ddl → maal → anon → dump → dump-kopi →
  go-data → apply-data → verify → anon`; stoppunkter; fortryd under meldt frys. Efter `verify`: projektejeren retter
  og publicerer kladderne i redaktøren (uden for vinduet).
- [ ] **Step 3: Generalprøve** fra operatørens cwd (memory `oev-fra-operatoerens-cwd`) på en stand-in fra en frisk
  prod-`dump-kopi`: hele rækkefølgen; redaktøren viser begge kladder (`red_person_narrative_records(934)` og
  `(929)`); en simuleret publicering som redaktør giver 1939-teksten i biografilæseren som anon på komponenterne
  934↔2 og 929↔44, 598/603 vises ikke, fortrydelse af deres `legacy_withdrawn` afvises, og 944's omtale udelades som
  oversigtsomtale (synlige 1939 = før + 2 − 1); fortryd-data og fortryd-DDL på en anden stand-in.
- [ ] **Step 4: Negativer:** forkert GO, manglende flag, gentaget `apply-data`, ændret svarfil.
- [ ] **Step 5:** Commit `docs(runbook): record_persona i prod` (runneren committes ikke).

### Task 6: Review, prod og færdigbevis

- [ ] **Step 1:** Codex `gpt-6.1-sol` over hele grenens diff (eksport uden `work*/`, memory
  `codex-soegning-pii-filnavne`); Opus dømmer; ret kun det godkendte efter projektejerens ja; hele CI lokalt igen.
- [ ] **Step 2:** Spørg om push og draft-PR; CI på PR'en grøn.
- [ ] **Step 3:** Prod i projektejerens shell efter runbooken; AI'en læser kvitteringer og mål.
- [ ] **Step 4:** Projektejeren retter og publicerer de to kladder i redaktøren; AI'en måler bagefter som anon
  (spec §8).
- [ ] **Step 5: Færdigbevis** i `docs/evidensbaseret-genimport/status.md` (overskriv snapshot),
  `docs/database-current-state.md` (ny §) og `docs/changelog.md`; `docs/decisions.md`: backlog 1 lukket. Commit
  `docs(record-persona): færdigbevis i prod`.
