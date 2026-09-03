# DAA 1939 v50 Production Writer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development or superpowers:executing-plans to
> implement this plan task-by-task. Use superpowers:test-driven-development for
> every code task and superpowers:verification-before-completion before each
> completion claim. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Luk den resterende 1939-provenance, opret præcis otte nye staged
personer og implementér en atomisk, idempotent production writer for hele
v50-reimporten med ægte rollback-dry-run og særskilt cutover.

**Architecture:** En Python-pipeline klassificerer de 305 parkerede
provenanceobjekter og kompilerer et lukket, deterministisk write-manifest. En
dedikeret PostgreSQL-kontrakt journalfører authorization, batch og hvert write
og eksponerer kun smalle redaktionelle RPC'er. En R-orchestrator validerer de
låste artefakter, åbner én transaktion og bruger samme databasevej til dry-run
og apply. De otte nye `person.id` tildeles af PostgreSQL, mens `record_key` og
det deterministiske source-persona-ID er stabile. Apply efterlader personerne
staged; cutover er en senere, separat autoriseret operation.

**Tech Stack:** Python 3, pytest, JSON Schema-lignende lukkede Python-
validatorer, R, testthat, DBI/RPostgres/jsonlite/digest, PostgreSQL 17,
Supabase/RLS, SQL-kontrakttests og GitHub Actions.

**Design:**
`docs/superpowers/specs/2026-08-17-1939-v50-production-writer-design.md`

**Plan base:** Commit `4a02174` på `feat/evidensbaseret-genimport`. Kontrollér
branch, HEAD og worktree før hver task; hvis basen har flyttet sig, genverificér
alle låste hashes og filinterfaces i stedet for at genbruge dem stiltiende.

## Global Constraints

- `.claude/skills/daa-extract/scripts/load_daa.R` må ikke ændres eller kaldes.
- `record_key`, ikke `(linje,nr)` eller et forudberegnet `person.id`, er den
  stabile 1939-identitet.
- De låste mængder er 543 eksisterende personankre, 8 nye personer, 130
  faktaobjekter, 94 ægteskabsobjekter og 81 relationsobjekter.
- Alle 305 provenanceobjekter skal have præcis én disposition. Production
  apply kræver `unresolved = 0`; `retain_source_only` er et gyldigt slutpunkt.
- Ingen kode må gætte identitet, relation, køn, dato eller anden værdi ud fra
  navn/OCR-lighed alene. Rå tekst, spans og usikkerhed bevares.
- Fravær fra et nyt artefakt er aldrig slettebevis. Kun positivt og eksklusivt
  1939-ejerskab kan autorisere `retire_1939_projection`.
- Apply må ikke ændre redaktionelle data, fremmed kildeevidens eller rækker
  uden for manifestets eksakte delta.
- Dry-run og apply bruger samme RPC'er og samme transaktionsvej. Dry-run
  rollbacker altid.
- Apply opretter præcis otte personer med `staged = true`; den aktiverer dem
  aldrig.
- Planens implementeringsgodkendelse er ikke authorization til live dry-run,
  production apply, reversal eller cutover. Hver live handling kræver en ny,
  eksplicit brugerbeslutning ved den angivne hard gate.
- Realdataartefakter ligger kun under ignoreret
  `work/task25-1939-v50-production-writer/`; credentials må aldrig
  serialiseres.
- Hver task må kun committe de filer, som den deklarerer. Bevar øvrige dirty
  filer urørt.

---

### Task 1: Byg det lukkede provenance-reviewmanifest

**Files:**
- Create: `.claude/skills/daa-extract/scripts/profile_provenance_review_1939_v50_helpers.R`
- Create: `.claude/skills/daa-extract/scripts/profile_provenance_review_1939_v50.R`
- Create: `.claude/skills/daa-extract/scripts/test_profile_provenance_review_1939_v50.R`
- Create: `tests/testthat/test-profile-provenance-review-1939-v50.R`
- Modify: `.claude/skills/daa-extract/scripts/preview_reimport_1939_v50_helpers.R`
- Modify: `.claude/skills/daa-extract/scripts/test_preview_reimport_1939_v50.R`
- Create: `.claude/skills/daa-extract/scripts/build_provenance_review_1939_v50.py`
- Create: `.claude/skills/daa-extract/scripts/test_build_provenance_review_1939_v50.py`
- Generate ignored: `work/task25-1939-v50-production-writer/provenance-database-profiles-v1.json`
- Generate ignored: `work/task25-1939-v50-production-writer/provenance-review-v1.json`
- Generate ignored: `work/task25-1939-v50-production-writer/provenance-review-v1-report.md`

**Interfaces:**
- Consumes: den autoritative import-preview v1, source-persona-materialisering
  v2, remaining-identity-decisions v1, database-preview v3 fix3, v50
  reconciliation, boundary-materialisering, den hashbundne Calamari-tekst og
  et nyt read-only profiludtræk af alle 543 mapped targets med konkrete facts,
  relations-, family-, membership- og family-fact-rækker samt source/editorial
  provenance.
- Produces schema `1939-v50-provenance-review-v1` med præcis 305 subjects i
  stabil `(category, source_record_key, source_order, object_order)`-orden.

- [ ] **Step 1: Skriv RED-test for det read-only 543-profilsudtræk**

  Brug en instrumenteret databasegateway og kræv `BEGIN READ ONLY` før første
  domænequery, `transaction_read_only=on`, præcis de deklarerede
  record-key/person-ID-par og komplette row-level facts, relations, families,
  memberships og family facts med citation/source- og editorial-events.

- [ ] **Step 2: Kør R-RED og implementér det mindste profiludtræk**

  Genbrug den eksisterende identity-profile-queryform og dens eksakte SQL-
  registry; generalisér ikke v1-outputtet. Tilføj kun den manglende lukkede
  `profile_family_facts`-query. Det nye output er
  `1939-v50-provenance-db-profiles-v1`, hashbundet til database-preview fix3 og
  de 543 deklarerede par. Det er altid `review_only` og uden write-authority.

  Run:

  ```bash
  Rscript .claude/skills/daa-extract/scripts/test_profile_provenance_review_1939_v50.R
  ```

- [ ] **Step 3: Kør liveprofilen read-only og dobbeltbyg semantisk**

  Profilér de 543 mapped targets i to nye `BEGIN READ ONLY`-sessioner. Snapshot-
  tid må variere; øvrig semantik og alle row IDs/provenancefelter skal være
  identiske. Manglende family-fact-, citation- eller editorial-kapabilitet
  fejler lukket.

- [ ] **Step 4: Skriv Python-RED-test for eksakt 130/94/81-dækning**

  Byg en lille fixture med fakta, ægteskab og relation og kræv én subject pr.
  inputobjekt, unik `review_subject_id`, raw payload, source-record, span,
  person-/family-targetkandidater og alle write-gates på `NO-GO`.

  ```python
  review = build_provenance_review(**fixture_inputs())
  assert review["counts"] == {
      "facts": 2, "marriages": 1, "relationships": 1, "subjects": 4,
  }
  assert review["decision_gate"] == "NO-GO"
  assert review["database_write_authorized"] is False
  ```

- [ ] **Step 5: Kør fokuseret Python-RED**

  Run:

  ```bash
  cd .claude/skills/daa-extract/scripts
  /usr/bin/python3 -B -m pytest -q test_build_provenance_review_1939_v50.py
  ```

  Expected: collection fejler med `ModuleNotFoundError`, fordi builderen ikke
  findes.

- [ ] **Step 6: Implementér lukket lineage- og subjectvalidering**

  Implementér `build_provenance_review(...) -> dict`. Kræv eksakte inputhashes,
  kendte schema-versioner, 543 entydige existing targets, de otte eksakte
  new-person-keys, fuld source-record-/span-/verbatim-dækning og præcis
  130/94/81 parkerede objekter. Afvis ukendte felter, duplicate IDs, ukendte
  targets og enhver write-authority.

- [ ] **Step 7: Implementér kun evidenspræsentation, ikke afgørelser**

  For hvert subject medtag:

  - raw payload og raw source excerpt;
  - literal span-status;
  - eksisterende canonical mål og positivt source-ejerskab;
  - relevant person-, family- og relationskontekst;
  - eventuelle konkurrerende targets;
  - `proposed_disposition: "unresolved"`.

  Normaliseret tekst må kun være `presentation_only`; den kan ikke autorisere
  en disposition.

- [ ] **Step 8: Tilføj mutations- og determinismetests**

  Afvis mindst: 129/131 facts, 93/95 marriages, 80/82 relations, duplicate
  subject, ændret inputhash, ændret Calamari-substring, forkert target-owner,
  ukendt category, skjult authority, reordering og ekstra felt. Genbyg under to
  `PYTHONHASHSEED`-værdier og kræv byteidentisk JSON.

- [ ] **Step 9: Generér realdatareview eksklusivt og auditér 305/305**

  CLI'en skal kræve alle inputstier og deres forventede SHA-256 eksplicit.
  Skriv ikke output, hvis en eksisterende fil findes. Genbyg til `mktemp -d`,
  brug `cmp`, og kontrollér præcis 305 unikke subjects samt 130/94/81.

- [ ] **Step 10: Commit profiler, builder og tests**

  ```bash
  git add .claude/skills/daa-extract/scripts/profile_provenance_review_1939_v50_helpers.R \
    .claude/skills/daa-extract/scripts/profile_provenance_review_1939_v50.R \
    .claude/skills/daa-extract/scripts/test_profile_provenance_review_1939_v50.R \
    tests/testthat/test-profile-provenance-review-1939-v50.R \
    .claude/skills/daa-extract/scripts/preview_reimport_1939_v50_helpers.R \
    .claude/skills/daa-extract/scripts/test_preview_reimport_1939_v50.R \
    .claude/skills/daa-extract/scripts/build_provenance_review_1939_v50.py \
    .claude/skills/daa-extract/scripts/test_build_provenance_review_1939_v50.py \
    docs/superpowers/plans/2026-08-18-1939-v50-production-writer.md
  git commit -m "feat(1939): build production provenance review"
  ```

---

### Task 2: Review og materialisér alle provenanceafgørelser

**Files:**
- Create: `.claude/skills/daa-extract/scripts/materialize_provenance_decisions_1939_v50.py`
- Create: `.claude/skills/daa-extract/scripts/test_materialize_provenance_decisions_1939_v50.py`
- Generate ignored: `work/task25-1939-v50-production-writer/provenance-proposals-v1.json`
- Generate ignored: `work/task25-1939-v50-production-writer/provenance-decisions-v1.json`
- Generate ignored: `work/task25-1939-v50-production-writer/provenance-decisions-v1-report.md`

**Interfaces:**
- Consumes: Task 1-reviewet, de samme autoritative inputartefakter og et
  komplet forslag/brugersvar.
- Produces schema `1939-v50-provenance-decisions-v1` med præcis én af
  `promote_canonical`, `retain_source_only`, `retire_1939_projection` eller
  `unresolved` pr. subject.

- [ ] **Step 1: Gennemgå i kildeordnede batches**

  Kontrollér literal Calamari, komplette PDF-sider ved tvivl, source persona,
  canonical target og database-preview. Codex kan afgøre entydige tilfælde;
  kun reelle hierarki-, identitets-, target- eller ejerskabstvivl forelægges
  brugeren. Notér OCR-fejl separat uden at rette raw source.

- [ ] **Step 2: Skriv RED-tests for de fire dispositioner**

  Kræv kategori-specifikke payloads:

  - `promote_canonical` kræver target, positiv evidens og promotionregel;
  - `retain_source_only` forbyder canonical operation;
  - `retire_1939_projection` kræver eksisterende række og eksklusivt positivt
    1939-ejerskab;
  - `unresolved` forbyder write fields og holder production gate på `NO-GO`.

- [ ] **Step 3: Kør fokuseret RED og implementér materializeren**

  Run:

  ```bash
  cd .claude/skills/daa-extract/scripts
  /usr/bin/python3 -B -m pytest -q test_materialize_provenance_decisions_1939_v50.py
  ```

  Implementér lukket schema, reviewhash-binding, target-/owner-validering,
  evidenshash pr. række og komplette category counts.

- [ ] **Step 4: Tilføj fail-closed angrebstests**

  Afvis ændret disposition uden nyt reviewbevis, skjult canonical target,
  source-only med write-op, retire uden positivt ejerskab, duplicate target
  mutation, mismatch mellem relationens endepunkter, marriage fact uden
  family-evidens, ukendt promotionregel og mutable counts.

- [ ] **Step 5: Materialisér realdata og stop, hvis `unresolved > 0`**

  Alle 305 subjects skal være til stede. Det er acceptabelt, at en konservativ
  del ender `retain_source_only`. Hvis blot én række er `unresolved`, leveres
  rapporten som checkpoint, og Tasks 3-10 må ikke begynde.

- [ ] **Step 6: Kør GREEN, auditér og commit**

  Genbyg byteidentisk under to hashseeds og kontrollér, at hver canonical
  operation har præcis én positiv provenancekæde.

  ```bash
  git add .claude/skills/daa-extract/scripts/materialize_provenance_decisions_1939_v50.py \
    .claude/skills/daa-extract/scripts/test_materialize_provenance_decisions_1939_v50.py
  git commit -m "feat(1939): materialize production provenance decisions"
  ```

---

### Task 3: Kompilér det deterministiske production write-manifest

**Files:**
- Create: `.claude/skills/daa-extract/scripts/build_production_write_manifest_1939_v50.py`
- Create: `.claude/skills/daa-extract/scripts/test_build_production_write_manifest_1939_v50.py`
- Generate ignored: `work/task25-1939-v50-production-writer/production-write-manifest-v1.json`
- Generate ignored: `work/task25-1939-v50-production-writer/production-write-manifest-v1-report.md`

**Interfaces:**
- Consumes: den eksakte v50-lineage, source-persona v2, de otte
  new-person-beslutninger, Task 2-beslutninger og authoritative database-preview
  v3 fix3.
- Produces schema `1939-v50-production-write-manifest-v1` med
  `production_authorized: false`.

- [ ] **Step 1: Skriv RED-test for hele topniveaukontrakten**

  Kræv eksakte inputhashes, database-/source-identitet, 543 existing anchors,
  otte person creates, source/evidence operations, canonical delta,
  before/after expectations og stabil elementorden.

- [ ] **Step 2: Kør fokuseret RED**

  ```bash
  cd .claude/skills/daa-extract/scripts
  /usr/bin/python3 -B -m pytest -q test_build_production_write_manifest_1939_v50.py
  ```

- [ ] **Step 3: Implementér de otte person-create-elementer**

  Lås de otte `record_key`-værdier fra designspecifikationen. Afled
  `source_persona_id` deterministisk efter den eksisterende UUIDv5-regel, men
  medtag aldrig et numerisk person-ID. Kræv source span, verbatim/hash,
  beslutningshash, mindst én source mention, persona-mention-link, navn,
  narrativ og kun positivt underbyggede øvrige felter. Margrethe-fixturen skal
  bevise, at manglende dato/køn ikke udfyldes.

- [ ] **Step 4: Implementér existing-target- og canonical-delta-kompilering**

  Bind alle 543 ankre og alle Task 2-dispositioner. `retain_source_only` må kun
  skabe private evidensoperationer. `retire_1939_projection` må kun skabe en
  operation for den eksakte positivt ejede række. Sortér operationer efter
  dependency class og stabil element-ID, ikke Python dict/set-order.

- [ ] **Step 5: Tilføj negative universe- og lineage-tests**

  Afvis 7/9 person creates, duplicate record/persona, allerede ejet new key,
  caller-styret person-ID, ændret source text, missing evidence link, canonical
  op uden beslutning, extra operation, count override, unknown field,
  write-authority og enhver input-byte-drift.

- [ ] **Step 6: Generér og dobbeltbyg realdata-manifestet**

  Kræv `unresolved = 0`, genbyg under to separate processer/hashseeds og brug
  `cmp`. Rapportér SHA-256, eksakte operation counts og de otte creates, men
  behold `production_authorized: false` og apply-gate `NO-GO`.

- [ ] **Step 7: Commit compiler og tests**

  ```bash
  git add .claude/skills/daa-extract/scripts/build_production_write_manifest_1939_v50.py \
    .claude/skills/daa-extract/scripts/test_build_production_write_manifest_1939_v50.py
  git commit -m "feat(1939): compile production write manifest"
  ```

---

### Task 4: Etablér databasejournal, authorization og writerrettigheder

**Files:**
- Modify: `schema.sql`
- Modify: `db-migrations.sql`
- Modify: `db-rls.sql`
- Modify: `db-verify.sql`
- Create: `tests/sql/test-1939-v50-production-writer.sql`

**Interfaces:**
- Produces append-only batch-, authorization- og eventmodel samt smalle
  redaktionelle/private RPC'er.
- Reuses eksisterende `private.source_record`, observation, interpretation,
  source-persona, identity og promotion-tabeller; opret ikke parallelle
  evidenstabeller.

- [ ] **Step 1: Skriv en failing PostgreSQL-17-kontrakttest**

  Testen skal først kræve de nye objekter og fejle med
  `REIMPORT_1939_WRITER_CONTRACT_MISSING`. Den skal siden bevise constraints,
  append-only events, one-use authorization, manifesthash-binding og revokes.

- [ ] **Step 2: Kør RED mod en frisk disposable database**

  Bootstrap med den eksisterende
  `tests/sql/evidence-promotion-bootstrap.sql`, anvend `schema.sql` og
  `db-rls.sql`, og kør den nye test via PostgreSQL 17 `psql -v ON_ERROR_STOP=1`.
  Brug aldrig live database til RED/GREEN.

- [ ] **Step 3: Implementér batch- og authorizationmodellen**

  Tilføj navnene efter live-schema-inspektion, konceptuelt:

  - `private.reimport_1939_authorization`;
  - `private.reimport_1939_write_batch`;
  - `private.reimport_1939_write_event`.

  Authorization binder operation, manifesthash, previewhash,
  database/source-identitet, expected counts, principal, nonce og expiry.
  Batch binder authorization og observeret status. Events er append-only og
  bærer manifest-element, source/persona/promotion, operation samt before/after
  hash. Tilføj state-transition- og immutability-triggers.

- [ ] **Step 4: Implementér smalle RPC-grænser**

  Tilføj og test konceptuelt:

  ```text
  red_authorize_1939_v50_reimport(...)
  red_begin_1939_v50_reimport(...)
  red_apply_1939_v50_source_evidence(...)
  red_apply_1939_v50_person_create(...)
  red_apply_1939_v50_canonical_delta(...)
  red_finalize_1939_v50_reimport(...)
  red_authorize_1939_v50_reversal(...)
  red_reverse_1939_v50_reimport(...)
  red_authorize_1939_v50_cutover(...)
  red_activate_1939_v50_batch(...)
  ```

  De endelige signaturer fastlåses i SQL-testen. Funktionerne skal have fast
  `search_path`, validere redaktionel principal, afvise ukendte JSON-felter og
  kun operere på batchens manifest-elementer.

- [ ] **Step 5: Implementér person-create-invariants i databasen**

  Brug `INSERT ... RETURNING id`/database-default. Afvis caller-styret
  person-ID, eksisterende external-ID/record-key, duplicate persona, andet end
  de autoriserede otte keys og `staged <> true`. Kræv, at source-record,
  observation, mention og persona-mention-basis er skrevet og hashverificeret,
  før source-persona-identity indsættes til det returnerede person-ID.
  Journalfør alle afhængige rækker.

- [ ] **Step 6: Implementér ownership-, delta- og finalize-kontrol**

  Lås targets i stabil orden. Canonical update/retire kræver det eksakte
  manifestelement og positivt source-ejerskab. Finalize genberegner counts,
  elementcoverage, referential integrity og eventhashes fra databasen; callerens
  counts er aldrig autoritative.

- [ ] **Step 7: Hærd grants/RLS og negative SQL-tests**

  Revoke direkte tabel- og funktionsadgang fra `PUBLIC`, `anon` og
  `authenticated`. Test forkert principal, udløbet/genbrugt authorization,
  ændret manifesthash, caller-ID, extra key, blandet ejerskab, manglende event,
  forkert state transition og forsøg på direkte DML.

- [ ] **Step 8: Kør GREEN og commit databasekontrakten**

  Kør frisk schema + RLS + både eksisterende evidence-promotion-test og den
  nye writer-test. Kør `db-verify.sql`.

  ```bash
  git add schema.sql db-migrations.sql db-rls.sql db-verify.sql \
    tests/sql/test-1939-v50-production-writer.sql
  git commit -m "feat(1939): define guarded production writer contract"
  ```

---

### Task 5: Implementér R-orchestrator med ægte rollback-dry-run

**Files:**
- Create: `.claude/skills/daa-extract/scripts/apply_reimport_1939_v50_helpers.R`
- Create: `.claude/skills/daa-extract/scripts/apply_reimport_1939_v50.R`
- Create: `.claude/skills/daa-extract/scripts/test_apply_reimport_1939_v50.R`
- Create: `tests/testthat/test-apply-reimport-1939-v50.R`
- Generate ignored: `work/task25-1939-v50-production-writer/production-dry-run-v1.json`
- Generate ignored: `work/task25-1939-v50-production-writer/production-dry-run-v1-report.md`

**Interfaces:**
- CLI requires manifest path/hash, database-preview path/hash, operation mode
  and — kun for apply — en databaseudstedt authorization-envelope.
- `--dry-run` kan ikke modtage eller oprette apply-authorization og rollbacker
  altid efter finalize-verifikation.

- [ ] **Step 1: Skriv DB-fri RED-tests for parser og lukket manifest**

  Kræv eksakt schema, inputhashes, 543/8-univers, `unresolved = 0`, ingen
  authority i manifestet og afvisning af ukendte CLI-flags/count overrides.

- [ ] **Step 2: Skriv fake-gateway RED for transaktionssekvensen**

  En instrumenteret gateway skal observere præcis:

  ```text
  connect -> begin -> advisory lock -> preflight -> begin batch
  -> source evidence -> 8 person creates -> canonical delta
  -> finalize -> rollback (dry-run)
  ```

  Enhver fejl fører til én rollback, nul commit og lukket forbindelse.

- [ ] **Step 3: Kør fokuseret RED**

  ```bash
  Rscript .claude/skills/daa-extract/scripts/test_apply_reimport_1939_v50.R
  ```

- [ ] **Step 4: Implementér validator, gateway og dry-run**

  Brug kun parameteriserede, statisk registrerede SQL/RPC-kald. Start
  transaktionen før domænequeries, sæt timeouts, bekræft databaseidentitet og
  tag edition-specifik advisory lock. Stream manifestelementer i stabil orden,
  opsaml DB-returnerede person-ID-maps, og kør finalize. Dry-run skriver
  rapporten efter rollback.

- [ ] **Step 5: Implementér apply-grenen uden at køre den live**

  Apply kræver exact authorization-envelope, matcher principal/miljø/hash og
  kalder samme interne funktion som dry-run. Kun efter en succesfuld finalize
  må den kalde commit. Log aldrig connection string eller credentials.

- [ ] **Step 6: Tilføj fejl-, idempotens- og credentialtests**

  Injicér fejl efter hvert skriveled. Test changed preview, missing migration,
  authorization replay, batchhash drift, allerede anvendt identisk batch og
  allerede anvendt batch med andre bytes. Scan output for credential literals
  og kendte connection-string-mønstre.

- [ ] **Step 7: Kør GREEN og commit orchestratoren**

  ```bash
  Rscript .claude/skills/daa-extract/scripts/test_apply_reimport_1939_v50.R
  Rscript -e 'testthat::test_file("tests/testthat/test-apply-reimport-1939-v50.R")'
  git add .claude/skills/daa-extract/scripts/apply_reimport_1939_v50_helpers.R \
    .claude/skills/daa-extract/scripts/apply_reimport_1939_v50.R \
    .claude/skills/daa-extract/scripts/test_apply_reimport_1939_v50.R \
    tests/testthat/test-apply-reimport-1939-v50.R
  git commit -m "feat(1939): add atomic production reimport writer"
  ```

---

### Task 6: Bevis writeradfærd i isoleret PostgreSQL 17 og CI

**Files:**
- Create: `tests/sql/1939-v50-writer-bootstrap.sql`
- Create: `tests/integration/test-1939-v50-production-writer.R`
- Modify: `.github/workflows/ci.yml`

**Interfaces:**
- Bootstrapper en isoleret database med schema/RLS, et minimalt men komplet
  v50-fixture og en redaktionel testprincipal.
- Integrationstesten bruger den virkelige R-orchestrator og virkelige RPC'er.

- [ ] **Step 1: Skriv RED-integration for dry-runens nul-delta**

  Tag row-counts og deterministiske row-hashes før kørsel. Kør dry-run gennem
  alle skrivefaser. Efter rollback skal samtlige målte tabeller være identiske,
  inklusive private journal-/evidenstabeller.

- [ ] **Step 2: Implementér det mindste realistiske fixture**

  Medtag eksisterende person, ny staged person, source record/persona,
  promoted fact, source-only evidence, relation, family fact og en beskyttet
  redaktionel række. Brug stabile fixture-UUID'er og databasegenereret
  `person.id`.

- [ ] **Step 3: Test apply, idempotens og exact delta**

  Udsted en testauthorization via den virkelige RPC, kør apply og kræv præcis
  fixturets forventede delta. Genkør identisk batch som `already_applied`; ændr
  én byte og kræv afvisning. Bevis, at den redaktionelle række er uændret.

- [ ] **Step 4: Test race og fejl efter hvert write stage**

  Brug to forbindelser. Den anden writer skal blokere eller afvises af advisory
  lock/state, aldrig interleave. Failpoints skal efterlade nul delvis delta.
  Test også sequence/identity ved en efterfølgende almindelig default-insert.

- [ ] **Step 5: Test staged visibility og reversal**

  Bevis, at de nye staged personer ikke er offentligt synlige. Udsted
  test-reversal, genskab førtilstanden og bevar append-only audit. Cutover
  testes kun på fixture og må aktivere præcis fixturets autoriserede personer.

- [ ] **Step 6: Tilføj PostgreSQL-17 CI-job og commit**

  CI-rækkefølgen er bootstrap -> schema -> RLS -> SQL-contract -> R integration.
  Jobbet må ikke kræve Supabase-secrets.

  ```bash
  git add tests/sql/1939-v50-writer-bootstrap.sql \
    tests/integration/test-1939-v50-production-writer.R .github/workflows/ci.yml
  git commit -m "test(1939): verify production writer on postgres 17"
  ```

---

### Task 7: Dokumentér og verificér den implementerede writer

**Files:**
- Modify: `.claude/skills/daa-extract/SKILL.md`
- Create: `docs/superpowers/reviews/1939-v50-production-writer-readiness.md`

**Interfaces:**
- Documents compile, review, manifest, authorization, dry-run, apply, reversal
  og cutover som særskilte kommandoer og gates.

- [ ] **Step 1: Dokumentér reproducerbar pipeline og hard gates**

  Angiv eksakte artefakter, hashes, commands og fejltilstande. Skriv tydeligt,
  at implementeret writer ikke er production authorization, og at live dry-run
  ikke er read-only på SQL-niveau selv om det rollbacker.

- [ ] **Step 2: Kør alle fokuserede suites frisk**

  Kør Task 1-3 Python-tests, Task 5 R-tests og Task 4/6 SQL/integration på en
  frisk PostgreSQL 17-database. Rapportér kommando, exitkode og testtal.

- [ ] **Step 3: Kør fulde regressionssuites**

  ```bash
  cd .claude/skills/daa-extract/scripts
  /usr/bin/python3 -B -m pytest -q
  cd ../../../..
  Rscript run-tests.R
  git diff --check
  ```

  Hold fokuserede, fulde og live-resultater adskilt.

- [ ] **Step 4: Kør sikkerheds- og artefaktaudits**

  Kontrollér git-ignore for task25, ingen credentials i genererede filer,
  eksakt 8-key universe, nul authority i manifest, SQL grants/revokes,
  deterministiske rebuilds og at `load_daa.R` er byteuændret fra planens base.

- [ ] **Step 5: Uafhængigt review og fixrunder**

  Review skal prioritere manifest-/authorization-bypass, hidden owner,
  partial-commit, race, RLS, sequence, idempotens, reversal og staged
  visibility. Hvert verificeret fund får en reproducerende RED-test før fix.

- [ ] **Step 6: Commit dokumentation**

  ```bash
  git add .claude/skills/daa-extract/SKILL.md \
    docs/superpowers/reviews/1939-v50-production-writer-readiness.md
  git commit -m "docs(1939): document production writer readiness"
  ```

---

### Task 8: Rehearsal mod en kontrolleret databasekopi

**Files:**
- Generate ignored: `work/task25-1939-v50-production-writer/rehearsal-a.json`
- Generate ignored: `work/task25-1939-v50-production-writer/rehearsal-b.json`
- Generate ignored: `work/task25-1939-v50-production-writer/rehearsal-report.md`

**Hard gate:** Stop og indhent udtrykkelig brugerautorisation til den konkrete
databasekopi og operation. Planens godkendelse er ikke tilstrækkelig.

- [ ] **Step 1: Verificér databasekopi og gendannelsesmulighed**

  Bevis database-/projektidentitet, migrationsniveau, isolation fra produktion
  og mulighed for at kassere/genskabe kopien. Log ingen credentials.

- [ ] **Step 2: Kør to uafhængige fulde rehearsals**

  Start hver fra samme verificerede snapshot. Udsted testauthorization, kør
  apply, efterkontrol og reversal. A og B skal have identisk semantik efter
  fjernelse af timestamps og authorization nonces efter en på forhånd
  defineret normalisering. De databasegenererede person-ID'er og hele
  record-key/person-ID-mappingen skal også være identiske, når udgangspunktet er
  samme snapshot; de må ikke normaliseres væk.

- [ ] **Step 3: Auditér hele forventet delta**

  Kræv 543 entydige eksisterende targets, præcis 8 nye staged personer,
  komplette private provenancekæder, nul uventede canonical mutationer, bevaret
  redaktionel/fremmed evidens og nul unresolved.

- [ ] **Step 4: Publicér rehearsal-resultat som GO/NO-GO**

  En mismatch giver `NO-GO` og ny fixrunde. Et grønt rehearsal giver kun
  readiness til at anmode om production apply; det autoriserer den ikke.

---

### Task 9: Staged production apply

**Files:**
- Generate ignored: `work/task25-1939-v50-production-writer/production-authorization.json`
- Generate ignored: `work/task25-1939-v50-production-writer/production-apply.json`
- Generate ignored: `work/task25-1939-v50-production-writer/production-apply-report.md`

**Hard gate:** Stop. Vis brugerens reviewpakke med manifesthash, previewhash,
rehearsalresultat, eksakte counts, databaseidentitet, gendannelsespunkt og
forventet delta. Kør intet mod produktion uden et nyt eksplicit “godkend
production apply”.

- [ ] **Step 1: Opret og verificér gendannelsespunkt**

  Dokumentér reference og verificér, at restore-proceduren er brugbar. Selve
  backup/restore-politikken må ikke antages ud fra lokal kode.

- [ ] **Step 2: Udsted one-use apply-authorization**

  Brug den redaktionelle principal og bind den eksakte database, manifesthash,
  previewhash, counts, nonce og udløb. Reload og verificér envelope før apply.

- [ ] **Step 3: Kør én staged apply**

  Kør uden automatisk retry. Ved fejl: verificér rollback og stop. Ved commit:
  gem batch-ID, database-returneret person-ID-map, observed delta og journalhash.

- [ ] **Step 4: Kør read-only efterkontrol**

  Genbrug preview/profile-vejen og direkte auditqueries. Bevis præcis otte
  staged personer, 543 eksisterende targets, komplette provenancekæder,
  bevaret protected state og nul uventede mutationsnøgler.

- [ ] **Step 5: Forelæg de otte staged personer for manuel kontrol**

  Vis navn, originaltekst, facts, relationer, family placement, usikkerheder og
  provenance. Ingen offentlig aktivering sker i denne task.

---

### Task 10: Særskilt offentlig cutover

**Files:**
- Generate ignored: `work/task25-1939-v50-production-writer/cutover-authorization.json`
- Generate ignored: `work/task25-1939-v50-production-writer/cutover-report.md`

**Hard gate:** Stop igen. Kræv et nyt eksplicit “godkend cutover” efter
brugerens gennemgang af alle otte staged personer og den read-only
efterkontrol.

- [ ] **Step 1: Afvis drift siden apply**

  Genberegn batch-/row-hashes, person-ID-map, visibility-state og canonical
  delta. Enhver drift giver `NO-GO` og ingen activation-authorization.

- [ ] **Step 2: Udsted one-use activate-authorization**

  Bind præcis det committede batch og de otte database-returnerede person-ID'er.
  Authorization må ikke omfatte fakta-, relations- eller identitetsmutationer.

- [ ] **Step 3: Aktivér præcis de otte personer atomisk**

  Kør `red_activate_1939_v50_batch` i én transaktion og verificér actual set før
  commit. Ved mismatch rollbackes alt.

- [ ] **Step 4: Kør offentlig og redaktionel efterkontrol**

  Bevis korrekt visibility/RLS, visningscaches, navigation, relationer og
  provenance. Gem cutoverrapport og journalhash uden credentials.

- [ ] **Step 5: Afsluttende handoff**

  Rapportér manifests, authorizations, batch-ID, hashes, before/after counts,
  testresultater, recovery reference og eventuelle `retain_source_only`-
  dispositioner. Fasen er først færdig, når denne evidens er samlet og ingen
  påkrævet kontrol udestår.
