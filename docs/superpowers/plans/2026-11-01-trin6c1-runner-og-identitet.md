# Trin 6c-1: runneren på 1939 og 1939's identiteter — implementeringsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 1939's tilladte poster (~500) har `proposed` forslag i prod fra runneren med prompt 1.1.0, og 6b's ceremoni
C har givet 1939's personas en identitet.

**Architecture:**
- **Basen (PR 1):** forslagswriteren vælger helposten med 6a's helpost-regel i stedet for »præcis én forankring«.
- **Scripts (PR 2):** kvotefejlen i runneren; prompt 1.1.0 og profilen `daa-1939-v2`; runner-input og
  eligibility-ledger med helpost-reglen, personaen gennem den primære mention og politikken `exclusion-1939-v1`;
  målingen `maal_trin6c1.sql`.
- **Kørsel (lokalt):** sandbox-gate på den installerede codex-cli, pilot på 30 poster, fuld kørsel og ingest i en
  stand-in, derefter 6b's ceremoni C øvet på samme stand-in.
- **Prod:** ceremoni A (DDL) og B (forslag) fra projektejerens shell, derefter 6b's ceremoni C (6b-planens Task 16).

**Tech Stack:** PostgreSQL 17 / plpgsql (`schema.sql`, `db-migrations.sql`, `db-verify.sql`), psql-tests i
`tests/sql/`, R (`tests/integration/`), Python 3 + pytest (`.claude/skills/daa-extract/scripts/`), codex-cli bag
Seatbelt, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-11-01-trin6c1-runner-og-identitet-design.md`. Læs §2-§7 før hver task. 6b's
spec §4.3 og plan Task 15-16 (`docs/superpowers/plans/2026-10-31-trin6b-identitet.md`) gælder for C.

## Global Constraints

- `schema.sql` er source of truth. Hver DB-ændring står i `schema.sql` og som en idempotent blok i `db-migrations.sql`,
  der kan køres to gange. Blokken hedder `-- ===== trin 6c-1: forslagswriteren følger helpost-reglen =====` og ligger
  sidst i filen.
- Ingen editionsnavngivne funktioner, tabeller eller operationer. Editionsdata kun i profiler, politikker og manifester.
- 2018-20 er byte-uændret: dens eligibility-ledger, runner-input, forslagsnøgler og kvitteringer. Bevises med
  regressionstests mod en 2018-20-fixture og på stand-in'en.
- Navne (præcis tekst):
  - prompt: `evidence-extract-prompt-1.1.0.md`;
  - profil: `daa-1939-v2` (version `1.4.0`, `edition` `1939`, `model_id` `gpt-5.6-terra`); `daa-1939-v1` bevares;
  - politik: `exclusion-1939-v1`; 2018-20's er fortsat `exclusion-2018-20-v1`;
  - årsagskoder i ledgeren for 1939: `no_published_persona`, `principal_living`, `same_as_partner_living`,
    `relative_living`, `text_year_ge_1915`;
  - måling: `T6C1_MAAL tilstand=<foer|a|b|c> forslag_k3=… poster_k3=… identiteter_k3=… afventer=… k1_forslag_hash=…`.
- Fejlkoder (præcis tekst): eksport `EXPORT_HELPOST_NOT_UNIQUE`, `EXPORT_PRIMARY_PERSONA_NOT_UNIQUE`,
  `EXPORT_POLICY_UNKNOWN`; writerens helpost-fejl er 6a's `RECORD_HELPOST_AMBIGUOUS` /
  `RECORD_HELPOST_SUBOCCURRENCE_OUTSIDE` uændret.
- Tekstreglen: `exclusion-1939-v1` udelukker en post, hvis helpostens gældende tekst indeholder et årstal
  `1[6-9][0-9]{2}` med værdi ≥ 1915 (spec §4.3 pkt. 4).
- Persondata:
  - Intet script eller output i repoet viser posttekst, claim-værdier eller navne; kun antal, nøgler og hashes.
  - Runner-input, cache, forslagsmanifest og C's ark ligger kun under `~/.private/6c1/` (0700/0600); ingen agent læser
    dem. `work*/` bruges ikke. Codex- og søgekommandoer udelukker `work*/` og `~/.private` i selve kommandoen.
  - Kun `eligible` poster sendes til en model, og kun gennem `run_evidence_43b.py` bag Seatbelt-profilen efter en grøn
    `gate-access-test.sh`.
- Prod: kun fra projektejerens shell med `--jeg-mener-det` og GO-kode. Prods `statement_timeout` er 2 min; stand-ins
  øves med `ALTER DATABASE … SET statement_timeout='2min'`, ICU-locale og `ANALYZE` efter restore. Prod-tid anslås fra
  stand-in med 27× for writer- og RPC-kald og 3× for én stor læsning (`database-current-state.md` §18).
- Commits: Conventional Commits med dansk beskrivelse, uden Claude-attribution, med `Claude-Session`-linjen. Ét commit
  pr. task. Ingen push uden projektejerens ja; PR'er som draft.
- Lokal verifikation før push: hele det berørte CI-job (pg-jobbene, r, python), ikke kun egne testfiler.

## Review Focus

1. **En 2018-20-post med én forankring:** writer og eksport giver præcis samme nøgler, kvitteringer, input-sha og
   ledger-række som før. Testes i Task 1 og Task 4.
2. **En helpost med flere forankringer, hvor den primære mention ikke er i den første forankring:** eksporten og
   writeren finder samme helpost og samme persona, uanset rækkefølge. Testes i Task 1 og Task 4.
3. **En codex-kvotefejl uden `error.type` midt i et bundt:** næste record sendes ikke; bundtet stopper som
   `quota_exhausted`. En `turn.failed` uden kvotetekst forbliver `unknown`. Testes i Task 2.
4. **Et årstal som del af et længere tal eller en sidehenvisning** (fx `s. 1923`): tæller som årstal og udelukker
   (fail-closed). Testes i Task 5.
5. **`levende` ændres i prod mellem dumpet og B:** B's genberegnede ledger afviger fra manifestets, og B skriver intet.
   Testes i Task 9 step 4.

---

## PR 1 — database (gren `feat/trin6c1-db` fra `docs/trin6c1-spec`)

### Task 1: Forslagswriteren følger helpost-reglen

**Files:**
- Modify: `schema.sql` `private.write_interpretation_proposal` (ca. linje 4966-5010): erstat kravet om én accepteret
  forankring og én topobservation med `private.record_helpost_observation(v_record.id, 'person')`; brug den returnerede
  observation som `v_parent`. Lås som i dag (`FOR UPDATE` på recorden og helposten).
- Modify: `db-migrations.sql`: blokken fra Global Constraints med funktionen.
- Modify: `tests/sql/test-interpretation-proposal.sql`: nye tilfælde.
- Modify: `tests/sql/test-interpretation-proposal-rerun.sql`: 2018-20-genafspilningen giver samme nøgler.

**Interfaces:**
- Consumes: `private.record_helpost_observation(uuid, text)` (`schema.sql:901`).
- Produces: writeren accepterer 1939's helposter med 2-5 forankringer; signatur og kvittering uændrede.

- [ ] **Step 1: Test** (`BEGIN … ROLLBACK`, fixture med én record og tre forankringer, hvor helposten er i den anden):
  forslaget skrives, `interpretation_observation` peger på den anden forankrings klausuler, og nøglen er lig
  `private.interpretation_proposal_key(...)` for samme input. En record, hvor helpost-reglen giver `ambiguous`, giver
  `RECORD_HELPOST_AMBIGUOUS`. En 2018-20-fixture med én forankring giver byte-ens kvittering med før-ændringen
  (hardkodet sha taget fra `main`).
- [ ] **Step 2:** Kør mod en base med `schema.sql` fra `main`. Forventet: `REIMPORT_WRITER_CLAUSE_FOREIGN_POST`.
- [ ] **Step 3:** Implementér i `schema.sql` og `db-migrations.sql`.
- [ ] **Step 4:** Kør de to testfiler mod frisk `schema.sql` og mod `db-migrations.sql` kørt to gange, og hele
  `interpretation-proposal-db`-jobbet (`bash tests/ci/interpretation-proposal-db.sh schema-rls-migrations` og
  `schema-migrations-rls`). Forventet: OK.
- [ ] **Step 5:** Commit `feat(db): forslagswriteren vælger helposten med helpost-reglen`.

## PR 2 — scripts (gren `feat/trin6c1-scripts` fra `feat/trin6c1-db`)

### Task 2: Runneren kender codex' kvotefejl

**Files:**
- Modify: `.claude/skills/daa-extract/scripts/evidence_runner.py` `classify_failure` (linje 450-460).
- Create: `.claude/skills/daa-extract/scripts/fixtures/failure-quota-no-type.jsonl` (kun en `turn.failed` med
  `error.message`, ingen kildetekst).
- Modify: `.claude/skills/daa-extract/scripts/test_evidence_runner.py`.

**Interfaces:**
- Produces: `classify_failure(jsonl, *, exit_code, timed_out=False) -> str` giver `quota_exhausted` for en
  `turn.failed`, hvis `error` mangler `type` (eller hele `error` er en streng), og meddelelsen indeholder
  `usage limit` (case-insensitiv). `RUNNER_CONTRACT_VERSION` → `evidence-runner-1.4`; cache-nøglefelterne for 1.4 er
  1.3's.

- [ ] **Step 1: Test:** `test_quota_without_type_is_quota_exhausted` (fixturen → `quota_exhausted`);
  `test_failed_without_type_or_quota_text_is_unknown`; `test_run_evidence_stops_bundle_on_quota_without_type` (to
  records, første giver fixturen → anden sendes ikke).
- [ ] **Step 2:** Kør `python3 -m pytest .claude/skills/daa-extract/scripts/test_evidence_runner.py -q`. Forventet: 3 FAIL.
- [ ] **Step 3:** Implementér; opdatér `CACHE_KEY_FIELDS_BY_CONTRACT` med 1.4.
- [ ] **Step 4:** Hele python-jobbets filliste (`ci.yml:156`). Forventet: PASS.
- [ ] **Step 5:** Commit `fix(runner): codex' kvotefejl uden fejltype stopper bundtet`.

### Task 3: Prompt 1.1.0 og profilen `daa-1939-v2`

**Files:**
- Create: `.claude/skills/daa-extract/references/evidence-extract-prompt-1.1.0.md` (kopi af 1.0.0 + to regler).
- Modify: `.claude/skills/daa-extract/references/extraction-profiles.json`: profil `daa-1939-v2`.
- Modify: `.claude/skills/daa-extract/scripts/test_evidence_extract.py`.

**Interfaces:**
- Produces: `evidence_extract.load_profile("daa-1939-v2")` med `prompt_file`, `prompt_sha256`, `model_id`
  `gpt-5.6-terra`, samme skemaer som `daa-2018-20-v2`.

- [ ] **Step 1:** Skriv de to regler i prompten (spec §4.2 pkt. 1), udgaveneutralt:
  - `person.name` indeholder kun navne; titler (»greve«, »komtesse«, »friherreinde« m.fl.) er `person.title`, og
    »til <gods>« er ikke en del af navnet;
  - »var †[dato], da …« (eller tilsvarende bisætning) angiver en død for den nævnte person, ikke for hovedpersonen.
  Resten af 1.0.0 er byte-uændret (test: diff mod 1.0.0 er kun de to tilføjede afsnit).
- [ ] **Step 2: Test:** profilen indlæses, `resolve_prompt` accepterer sha'en, `daa-1939-v1` og `daa-2018-20-v2` er
  uændrede (hardkodede sha'er fra `main`).
- [ ] **Step 3-4:** Implementér → kør python-jobbet. Forventet: PASS.
- [ ] **Step 5:** Commit `feat(runner): prompt 1.1.0 og 1939-profilen daa-1939-v2`.

### Task 4: Runner-inputtet følger helpost-reglen og den primære mention

**Files:**
- Modify: `.claude/skills/daa-extract/scripts/export_43b_runner_input.R` (posts-forespørgslen `:48-70`, klausulerne
  `:72-84`).
- Modify: `tests/integration/test-reimport-source-text-revision.R` eller Create:
  `tests/integration/test-export-runner-input-helpost.R` (fixture med flere forankringer); tilføj i `ci.yml`s r-job.

**Interfaces:**
- Produces: `runner-input-v1.json` uændret skema; pr. record helposten fra `private.record_helpost_observation(sr.id,
  'person')` og `persona_id` fra helpostens `primary`-mention. En record uden én helpost → `EXPORT_HELPOST_NOT_UNIQUE`;
  flere primære personas → `EXPORT_PRIMARY_PERSONA_NOT_UNIQUE`. En record uden persona får tom `persona_id` som i dag.

- [ ] **Step 1: Test:** fixturen med tre forankringer giver én record med den rigtige helposts tekst og klausuler,
  uafhængigt af `ORDER BY` (kør med to rækkefølger); `persona_id` er personaen med nøgle `'1939:' || record_key`;
  2018-20-fixturen giver byte-ens fil med `main`'s (hardkodet sha).
- [ ] **Step 2-4:** Kør (FAIL) → implementér → kør hele r-jobbet (`Rscript run-tests.R`). Forventet: PASS.
- [ ] **Step 5:** Commit `fix(scripts): runner-input vælger helpost og persona som writeren`.

### Task 5: Eligibility-politikken `exclusion-1939-v1`

**Files:**
- Modify: `.claude/skills/daa-extract/scripts/export_model_eligibility.R`: ny påkrævet `--policy`
  (`exclusion-2018-20-v1` | `exclusion-1939-v1`; andet → `EXPORT_POLICY_UNKNOWN`). 2018-20's forespørgsel er uændret.
  1939's: hovedperson gennem `private.publication_persona_binding` for helpostens primære persona; regel 2-3 over
  bindingspersonen og dens afklarede `samme_som`-partnere (`relation.rolle='samme_som'`, begge retninger); tekstreglen
  fra Global Constraints; `input_sha` over helpostens gældende tekst (helpost-reglen, som Task 4).
- Create: `tests/integration/test-export-model-eligibility-1939.R`; tilføj i r-jobbet.

**Interfaces:**
- Produces: `eligibility-ledger-v1.json` med `policy_version`, `rules_script_sha256` og pr. record `status` og
  `reasons` (årsagskoderne fra Global Constraints). Kun nøgler, koder og hashes.

- [ ] **Step 1: Test** (fixture med en 1939-record for hver regel + én tilladt): hver regel giver præcis sin årsag;
  `s. 1923` udelukker; `1914` alene udelukker ikke; en post uden published binding giver `no_published_persona`;
  `--policy exclusion-2018-20-v1` mod 2018-20-fixturen giver byte-ens ledger med `main`'s; ukendt politik giver
  `EXPORT_POLICY_UNKNOWN`.
- [ ] **Step 2-4:** FAIL → implementér → hele r-jobbet. Forventet: PASS.
- [ ] **Step 5:** Commit `feat(scripts): eligibility-politik for 1939 (exclusion-1939-v1)`.

### Task 6: Målingen `maal_trin6c1.sql`

**Files:**
- Create: `.claude/skills/daa-extract/scripts/maal_trin6c1.sql` (læse-kun).
- Create: `.claude/skills/daa-extract/scripts/test_maal_trin6c1.py` (mod lokal fixturebase); tilføj i `ci.yml:156`.

**Interfaces:**
- Produces: én linje med formatet fra Global Constraints. `tilstand`: `foer` (`prosrc` for
  `private.write_interpretation_proposal` nævner ikke `record_helpost_observation`), `a` (nævner den; 0 kilde
  3-forslag), `b` (kilde 3-forslag, ingen `publication_identity`-batch), `c` (finaliseret C).
  `k1_forslag_hash` = `interpretation_transfer_digests.sql`'s forslagsdigest for kilde 1.

- [ ] **Step 1-4:** Test (`foer` → `a` → `b` på fixturen; hash stabil over to kørsler) → implementér → python-jobbet.
- [ ] **Step 5:** Commit `feat(scripts): måling for trin 6c-1`.

## Kørsel og øvelse (lokalt; stand-in = kopi af `_6bm` eller frisk prod-dump)

### Task 7: Sandbox-gaten på den installerede codex-cli

- [ ] **Step 1:** Notér `codex --version` og at `gpt-5.6-terra` står i `~/.codex/models_cache.json`. Mangler modellen:
  stop (spec §4.2 pkt. 3).
- [ ] **Step 2:** `gate-access-test.sh` med den udfyldte profil. Forventet: alle `naegtet`-linjer nægtet, psql nægtet,
  codex-kaldet lykkes. Fejler codex-kaldet, tilføjes kun den sti, der måles nødvendig, i
  `runner-gate.sb.template` med en kommentar om versionen; commit `fix(sandbox): …` med målingen.
- [ ] **Step 3:** Kanarien uden gate viser `command_execution`; med gate fældes recorden som `tool_use`.

### Task 8: Pilot, fuld kørsel og ingest i stand-in'en

Under `~/.private/6c1/` (0700). Stand-in: `createdb -T daa5ab_ddl_standin_20261101101631_6bm` + PR 1's
`db-migrations.sql` og `db-rls.sql`, ICU, 2 min, `ANALYZE`.

- [ ] **Step 1:** Ledger (`--policy exclusion-1939-v1`) og runner-input for kilde 3. Forventet ca. 500 `eligible` /
  63 `excluded` (spec §2.3); afviger det med mere end 5, stop og forklar.
- [ ] **Step 2: Pilot:** `build_43b_selection.py --count 30` (seed i manifestet), `build_43b_manifest.py --profile-id
  daa-1939-v2`, `run_evidence_43b.py`. Gaten (spec §4.5 pkt. 1) rapporteres med tal i
  `docs/evidensbaseret-genimport/runner-1939-pilot.md` (ingen claim-værdier). Fejler gaten: stop; prompt eller profil
  rettes i en ny task, før noget ingestes.
- [ ] **Step 3: Fuld kørsel:** `build_eligible_selection.py` over alle `eligible`, bundter som 2018-20; pilotens svar
  kommer fra cachen. Kvotestop → vent og genoptag samme bundt; vedvarende fejl på én post → reservemanifest uden
  posten, talt.
- [ ] **Step 4: Ingest:** `build_43b_proposal_manifest.py --profile daa-1939-v2 --cache-key current`; skriv
  forventningen (elementer, claims pr. prædikat og rolle, citerede klausuler) før kørslen; dry-run → apply gennem
  R-gatewayen (mønster `~/.private/2018-20-overfoersel/04-proposal-apply-prod.R`); `db-verify.sql` på en engangskopi;
  kanonisk delta 0; `maal` → `b`; `k1_forslag_hash` uændret.
- [ ] **Step 5:** Rapporten udvides til `runner-1939-koersel.md` (dækning, forbrug, regnskab, tal pr. prædikat).
  Commit `docs(trin6c1): runnerens kørsel af 1939 i stand-in`.

### Task 9: Øvelse af 6b's ceremoni C og de parkerede punkter

6b-planens Task 15 på stand-in'en fra Task 8, med disse tilføjelser:

- [ ] **Step 1: Mål** `red_publication_control`, `red_publication_control_details`, C's første `enig`-element og
  finalize (6b-runbooken linje 441-445). Omregn med 27×. Er et kald over 60 s anslået i prod: optimér i en DB-task på
  PR 1-grenen (samme blok), øv igen. Ellers notér tallene; ingen ændring.
- [ ] **Step 2:** Kortantal fordelt på udfald, inklusive de udelukkede posters personas (spec §4.7 pkt. 4), og antal
  sager, hvor partnerreglen afgør (`partner_hoejere`). Notér `OUTCOME_MISSING`-tilfældet (spec §4.7 pkt. 5).
- [ ] **Step 3: Stop for projektejeren:** forelæg spec §8 pkt. 1 og, hvis kortene er over 90, pkt. 2, med tallene.
  Afgørelserne skrives i specens §8 og i `docs/decisions.md`; ændrer de kode (partnerreglen), er det en DB-task på
  PR 1-grenen med test, før øvelsen køres igen.
- [ ] **Step 4: Driftprøve for B:** sæt `levende=true` på én slægtning i en engangskopi efter dumpet; B's
  genberegning af ledgeren afviger, og intet skrives.
- [ ] **Step 5:** Øvelsesark (alle `U` som teknisk prøve, eller projektejerens øvelse), apply + finalize, fortrydelse
  og genkørsel som 6b Task 15 step 3-4.

### Task 10: Runbook og private runner

**Files:**
- Create: `docs/runbooks/trin6c1-prod.md` (mønster `trin6b-prod.md`: forløb, varighed med de målte faktorer,
  stoppunkter, fortrydelse pr. fase efter spec §6, 6b-B's lukkede vindue).
- Create (privat): `~/.private/5ab-overfoersel/27-trin6c1.sh` (`maal`, `go-a`, `dump`, `apply-a`, `manifest-b`, `go-b`,
  `apply-b`) og `27-trin6c1-b.R` (genberegn ledger og klausulsæt, dry-run, authorize, apply, digest) via
  `lib.zsh`/`koer.zsh`. `apply-b` stopper, hvis `~/.private/6b/fortryd-b-*.igang` findes. GO for B binder
  forslagsmanifestets, ledgerens og runner-manifestets hash.

- [ ] **Step 1:** Frisk stand-in fra seneste prod-dump; A → `maal` `a`; B med manifestet fra Task 8 → `b`; digest lig
  Task 8's; replay `already_applied`. Notér varigheder.
- [ ] **Step 2:** Fortrydelse af B: restore af B-dumpet (taget i tilstand `a`) → `a`; B igen → `b`.
- [ ] **Step 3:** Commit `docs(runbooks): trin 6c-1 ceremoni A og B`.

## Prod

### Task 11: Codex-diffreview, prod A og B

- [ ] **Step 1:** Codex-runde på diffen af PR 1 + PR 2 (`gpt-6.1-sol`, read-only, `--glob '!work*/**'`); Opus afvejer.
  B13's anden og sidste runde.
- [ ] **Step 2:** Projektejerens ja → push og draft-PR'er; PR 1 før PR 2. Slutøvelse (Task 10 step 1) på `main`.
- [ ] **Step 3:** A og B i prod fra projektejerens shell; `NOTIFY pgrst`; projektejeren læser Security Advisor
  (forventet: ingen nye fund, A ændrer kun en funktion).
- [ ] **Step 4:** `status.md` (1939 »Extractor-runner« og »Forslag« i prod), `database-current-state.md`, `changelog.md`.
  Commit `docs(trin6c1): 1939's forslag i prod`.

### Task 12: Prod C og status

- [ ] **Step 1:** 6b-planens Task 16 med afgørelserne fra Task 9 step 3 og `--details` på manifestet.
- [ ] **Step 2:** `status.md`: 1939 »Identitet (identiteter)« → `produktionsverificeret` med dato; tjeklisten fra spec
  §7; `database-current-state.md`; `changelog.md`. Commit `docs(status): 1939's identiteter i prod (6b C, 6c-1)`.

---

## Reviewlog

*(tom)*
