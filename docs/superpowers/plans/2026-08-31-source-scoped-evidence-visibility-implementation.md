# #153: Source-scoped evidence visibility V3 — implementeringsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implementér #153's versionsnavngivne source-scoped evidence-writer, så facts, assertions og citations fra adapteren forbliver private indtil en særskilt redaktionel V3-publiceringsbeslutning.

**Architecture:** V3 erstatter den ufærdige V1 route med pensionerede no-DML RPC'er, en privat immutable revisionskæde og policy-safe public visibility-ID-views. En DB-kataloginventory og et CI/gateway-målt repository-writer-snapshot bindes til deployment og authorization; database-RPC'er validerer kun den persisterede artifact-binding og levende databasekontrakt. Model-DML sker kun i de versionsnavngivne V3-kerneler med single-use authorization og den fælles #152-låseorden.

**Tech Stack:** PostgreSQL 17/SQL/RLS, R/testthat/DBI/RPostgres/jsonlite/digest, Python 3/pytest, Git-tracked artifact hashing og disposable lokale PostgreSQL-databaser.

**Spec:** `docs/superpowers/specs/2026-08-31-source-scoped-evidence-visibility-design.md`

## Global Constraints

- Ingen production-DB, push, merge, deploy eller produktions-callback.
- Aldrig læs, skriv eller send data under `work/` til model-, browser- eller reviewværktøjer.
- De eksisterende untracked V1-prototypefiler `build_source_scoped_replace_manifest.py`, `apply_source_scoped_replace.R`, `apply_source_scoped_replace_helpers.R`, deres tests samt `tests/{sql,integration}/test-source-scoped-replace.*` må ikke ændres, stages eller committes. Den beskyttede reviewfil må heller ikke røres. Implementér kun V3 i nye, eksplicit navngivne filer og rene commits.
- Kun de syv versionsnavngivne V3-RPC'er må være source-scoped public API. V1-RPC'er pensioneres med no-DML bodies og uden grants.
- Source-writeren er append-only: den opretter ingen model-update/delete, ændrer aldrig `relation`, `note`, `haendelse`, `story`, `same_som`, identitet eller publiceret narrativ.
- En source-apply kan højst kalde #152-kernen én gang og kun producere `draft_created` eller `draft_updated`. Compensation bruger alene `red_fortryd_person_narrative_publication_event`.
- Historical ubundne modelrows bevarer deres nuværende RLS-adfærd. V3-bound rows er synlige for `anon`/almindelig `authenticated` kun gennem de tre specificerede visibility-ID-views og en publiceret content-revision.
- Før model-DML skal databaseinventory, repository-artifact/deployment-binding, attestation, identity, ownership, manifest, nonce, actor, database og state alle matche; ellers afvises hele batchen.
- Alle DB-tests bruger en frisk disposable PostgreSQL-database. Ingen test må afhænge af realdata eller serialisere credentials.
- Før hver mutation: kontrollér branch `feat/generalized-writer-batch-153`, korrekt worktree og kun taskens deklarerede filer. Hver task committer kun sine erklærede filer.
- Et #153-RLS-pass, som kan møde eller binde Task 4C-/4D-receipts, køres kun som én ydre `psql --single-transaction -v ON_ERROR_STOP=1 -f db-rls.sql`-transaktion. `db-rls.sql` indeholder bevidst ikke `BEGIN`/`COMMIT`, fordi den også inkluderes i eksisterende transaktionelle SQL-tests. Den disposable fault-injection-test beviser, at fejl efter Task 4C-preflight ruller receipt-bundne ACL/policy-mutationer tilbage.

## Deployment-bundet verifikationsprotokol

For Tasks 4B–5 er der to adskilte testfaser. Før commit må kun RED-, enheds- og
katalogtests køre; de må ikke registrere deployment eller erklære den
deployment-bundne gateway/integration grøn. Commit derefter taskens deklarerede
kildefiler. Før deployment-bundet test skal følgende være sandt:

```bash
git diff --quiet HEAD -- schema.sql db-migrations.sql db-rls.sql db-verify.sql R .claude/skills/daa-extract/scripts tests/sql tests/integration
test -z "$(git status --porcelain --untracked-files=all -- \
  ':(glob).claude/skills/daa-extract/scripts/*source_scoped_evidence_v3*' \
  ':(glob)tests/sql/*source-scoped-evidence-v3*' \
  ':(glob)tests/integration/*source-scoped-evidence-v3*')"
```

De navngivne, beskyttede V1-prototypefiler er ikke omfattet af denne V3-pathcheck
og røres aldrig. Gateway/CI registrerer så deployment fra `HEAD` tree-id og
SHA-256 over dets blob-bytes, og den friske disposable integration skal returnere
samme persisterede deployment-ID/-hash. Før den første V3-authorization-RPC og
gateway findes, må postcommit-testen kun erklære den afgrænsede
registrerings-/bindingstest grøn. Dirty tracked eller untracked V3-writer-kode
skal afvises før authorization i den første senere task, som både har
authorization-RPC'en og gatewayen. Hvis en deployment-bundet test kræver en
ændring, oprettes en ny task-specifik commit, og hele postcommit-protokollen
gentages mod det nye HEAD-tree.

## Filkort

| Fil | Ansvar |
| --- | --- |
| `schema.sql`, `db-migrations.sql`, `db-rls.sql`, `db-verify.sql` | V1-pensionering, V3-private relationer/RPC'er, RLS, ACL og fresh/migration-paritet. |
| `tests/sql/test-source-scoped-evidence-v3.sql` | V3 schema-, state-, ACL-, inventory- og migrationkontrakt på disposable DB. |
| `tests/integration/test-source-scoped-evidence-v3.R` | Reelle V3 apply/publication/adoption/compensation- og lock-races. |
| `.claude/skills/daa-extract/scripts/build_source_scoped_evidence_v3_manifest.py` | Lukket V3 semantic-manifest og repository-artifact-snapshot uden DB- eller `work/`-adgang. |
| `.claude/skills/daa-extract/scripts/test_build_source_scoped_evidence_v3_manifest.py` | Determinisme, lukket schema og artifact-snapshot tests. |
| `.claude/skills/daa-extract/scripts/apply_source_scoped_evidence_v3_helpers.R` | Read-only preflight, deployment-artifact-binding og V3 RPC-parameterkontrol. |
| `.claude/skills/daa-extract/scripts/apply_source_scoped_evidence_v3.R` | Transactional authorize/apply/reconcile/verify gateway uden direkte model-DML. |
| `.claude/skills/daa-extract/scripts/test_apply_source_scoped_evidence_v3.R` | R-gatewayens read-only/preflight/reconcile negative tests. |
| `.claude/skills/daa-extract/scripts/{load_daa.R,post_load_fixup.R}` og `R/update-{1939,2018}-narratives.R` | Inventory-klassificeret entrypoint og ingen direkte bypass til source-scoped model-DML. |
| `tests/integration/test-source-scoped-evidence-v3-entrypoints.R` | Statisk og runtime bevis for, at source-scoped entrypoints kun går gennem V3. |
| `docs/runbooks/source-scoped-replace.md` | Redaktionel authorization, publicering, compensation, receipt og recovery uden produktionsløfte. |

---

### Task 4A: Pensionér V1 og etabler den fysiske V3 revisionsmodel

**Files:**
- Modify: `schema.sql`, `db-migrations.sql`, `db-rls.sql`, `db-verify.sql`
- Create: `tests/sql/test-source-scoped-evidence-v3.sql`

**Interfaces:**
- Pensionér præcist `public.red_authorize_source_scoped_replace(text,text,uuid,uuid,jsonb,text,text,timestamptz)`, `public.red_apply_source_scoped_replace(uuid,jsonb)` og `public.red_verify_source_scoped_replace(uuid)` med `SOURCE_SCOPED_REPLACE_V1_RETIRED`.
- Opret V3 relationsnavne `private.source_scoped_replace_v3_{attestation,authorization,authorization_attestation,batch,event,manifest_artifact}` og `private.source_scoped_evidence_v3_{chain,revision,member,publication,chain_state,chain_event}`.

- [ ] **Step 1: Skriv SQL RED-tests for V1-retirement og typed members**

```sql
SELECT has_function_privilege(
  'authenticated',
  'public.red_apply_source_scoped_replace(uuid,jsonb)',
  'EXECUTE'
) AS v1_apply_is_not_granted;
-- forvent false

INSERT INTO private.source_scoped_evidence_v3_member
  (revision_id, member_kind, member_key, fact_id, assertion_id)
VALUES ('00000000-0000-0000-0000-000000000001', 'fact', 'fact:1', 1, 1);
-- forvent CHECK-violation: præcist én typed FK
```

- [ ] **Step 2: Kør SQL RED-testen**

Run: den eksisterende disposable-DB bootstrap efterfulgt af `psql -v ON_ERROR_STOP=1 -f tests/sql/test-source-scoped-evidence-v3.sql`.

Expected: FAIL, fordi V1 stadig kan kaldes og V3-tabeller/constraints ikke findes.

- [ ] **Step 3: Implementér V1-retirement og V3 DDL i `schema.sql`**

Definér V1-function-bodies som `RAISE EXCEPTION 'SOURCE_SCOPED_REPLACE_V1_RETIRED'`, revoke `EXECUTE` fra `PUBLIC, anon, authenticated, service_role`, og tilføj append/mutation-triggers på V1-ledgerne. Opret V3-tabeller med UUID-primary keys, immutable triggers, `UNIQUE(source_id,chain_key)`, `UNIQUE(chain_id,revision)`, typed member-FK'er, one-of `CHECK`, partial unique indexes, en immutable per-element authorization-attestation-linkrække og en `chain_state.last_event_id` FK til immutable chain-event `id`.

- [ ] **Step 4: Implementér additiv, rerun-sikker migration og verifier**

Implementér samme DDL/ACL/trigger-kontrakt i `db-migrations.sql`. Ved første apply oprettes V3-objekter; ved rerun accepteres de kun ved eksakt receipt-hash over definitioner, constraints, triggers og grants. `schema.sql` skal deklarere de samme `GENERATED BY DEFAULT AS IDENTITY`-defaults for `fact.id` og `citation.id`, som migrationssporet opretter, og begge bootstrapveje skal verificere samme sequence ownership/floor. Tilføj `db-verify.sql` assertions med `to_regclass`, `pg_get_constraintdef`, `pg_get_functiondef`, `has_function_privilege` og identity-sekvens-ownership.

- [ ] **Step 5: Kør targeted PASS-verifikation**

Run: fresh-schema og migrated-disposable bootstrap, derefter `tests/sql/test-source-scoped-evidence-v3.sql` og `db-verify.sql`.

Expected: PASS; alle tre V1 signatures afviser, V3 DDL er fysisk ens og rerun-receipt matcher.

- [ ] **Step 6: Commit kun Task 4A-filer**

```bash
git add schema.sql db-migrations.sql db-rls.sql db-verify.sql tests/sql/test-source-scoped-evidence-v3.sql
git commit -m "feat: establish source scoped evidence v3 ledger"
```

### Task 4B: Luk reader-, consumer-, writer- og artifact-inventory

**Files:**
- Modify: `schema.sql`, `db-migrations.sql`, `db-rls.sql`, `db-verify.sql`
- Modify: `tests/sql/test-source-scoped-evidence-v3.sql`
- Create: `.claude/skills/daa-extract/scripts/build_source_scoped_evidence_v3_manifest.py`
- Create: `.claude/skills/daa-extract/scripts/test_build_source_scoped_evidence_v3_manifest.py`

**Interfaces:**
- Private databaseprober producerer `catalog_definition_sha256`, `reader_probe_source_sha256`, `consumer_probe_source_sha256`, `writer_probe_source_sha256` og `inventory_result_sha256`.
- `private.source_scoped_evidence_contract_inventory` og immutable `private.source_scoped_evidence_v3_deployment` binder de fem databasehashes, Git-artifact-hash, databaseidentitet og deployment-hash til hver V3 authorization.
- Kun `private.register_source_scoped_evidence_v3_deployment(uuid,text,text,text,text,text,uuid) -> uuid` kan indsætte deployment. Den er `SECURITY DEFINER`, har no-application grants, kræver `daa_source_scoped_evidence_deployer` og hasher serverens `{schema,inventory_id,repository_tree_id,repository_writer_artifact_sha256,schema_contract_version,database_name,system_identifier,registered_by,registered_at}` preimage.
- Python `build_repository_writer_snapshot(repo_root: Path) -> dict` kalder selv `git ls-tree -r -z HEAD` og `git cat-file blob HEAD:<path>` og producerer en stable `repository_writer_artifact_sha256` over sorted `{path,blob_sha256,language,writer_class,allowed_db_api,model_targets}` entries; `blob_sha256` er SHA-256 over blob-bytes og callers kan ikke vælge scope.

- [ ] **Step 1: Skriv RED-tests for database- og repositorydrift**

```python
def test_artifact_snapshot_changes_when_direct_model_writer_is_added(tmp_path):
    root = tmp_path / "repo"
    (root / "R").mkdir(parents=True)
    writer = root / "R" / "writer.R"
    writer.write_text("invisible(NULL)\n")
    git(root, "init"); git(root, "config", "user.email", "fixture@example.invalid")
    git(root, "config", "user.name", "Fixture"); git(root, "add", "R/writer.R"); git(root, "commit", "-m", "baseline")
    before = build_repository_writer_snapshot(root)
    (root / "R" / "new_writer.R").write_text("DBI::dbExecute(con, 'INSERT INTO fact DEFAULT VALUES')\n")
    git(root, "add", "R/new_writer.R"); git(root, "commit", "-m", "new writer")
    after = build_repository_writer_snapshot(root)
    assert before["sha256"] != after["sha256"]
```

```sql
-- En ny SECURITY DEFINER reader/writer eller en ukendt dynamic-SQL target
-- skal give SOURCE_SCOPED_EVIDENCE_INVENTORY_DRIFT før model-DML.
```

- [ ] **Step 2: Kør RED-tests**

Run: `/usr/bin/python3 -B -m pytest -q .claude/skills/daa-extract/scripts/test_build_source_scoped_evidence_v3_manifest.py` og disposable `tests/sql/test-source-scoped-evidence-v3.sql`.

Expected: FAIL, fordi V3 inventory/prober og artifact builder mangler.

- [ ] **Step 3: Implementér lukkede databaseprober**

I private `SECURITY DEFINER`-prober: hash alle relevante `pg_get_viewdef`/`pg_get_functiondef` resultater direkte, brug `pg_depend` som supplerende edges og afvis unclassificeret PL/pgSQL/dynamic SQL. Inventér mindst alle FK'er, polymorfe target-par, `conclusion`, `note`, `relation`, `haendelse.fact_id`, `story.fact_id`, public views/RPC'er og muterende routes for fact/assertion/citation.

- [ ] **Step 4: Implementér artifact builder uden DB eller `work/`**

Lad builderen selv udlede filer med `git ls-tree -r -z HEAD` under `R/`, `.claude/skills/daa-extract/scripts/` og deklarerede database-scriptstier, og SHA-256-hash `git cat-file blob HEAD:<path>` bytes. Afvis ukendt `dbExecute`, `dbAppendTable`, `COPY`, DML-token eller dynamic SQL mod modeltabeller; hold tests/fixtures i en separat ikke-produktionsliste. Gem HEAD tree-id kun som provenance, stabilsortér entries og brug lukket top-level schema. En ny committed writer skal derfor altid ændre snapshot'et, mens index/worktree ikke kan ændre en registreret deployment-binding.

- [ ] **Step 5: Håndhæv databasegrænsen**

Opret inventory- og deployment-relationerne med immutable triggers og bind deres IDs/hashes i V3 authorization/receipt. Revoke direkte model-DML på `fact`, `assertion` og `citation` fra application-, extract- og `service_role`-roller. Verificér, at allowlistede `SECURITY DEFINER` writers fortsat er den eneste route. Tilføj både bound-member-triggeren for generic edit/delete/undo og en separat consumer-trigger, der afviser INSERT/UPDATE af `conclusion`, `note`, `relation`, `haendelse`, `story`, promotion-link eller discovery-fundet polymorf consumer mod en ikke-public V3-member eller en public member, hvis consumeren ville gøre senere supersede/withdraw usikker.

- [ ] **Step 6: Kør kun precommit PASS- og negative tests**

Run: Python artifact tests plus SQL tests, der tilfører ny FK, reader, writer, dynamic-SQL definition, ny tracked writer, rå `authenticated`/`service_role` DML og hver consumerklasse mod draft/public member. Test kun registration-ACL'en precommit: direct INSERT, forged hash og application-`EXECUTE` afvises; kør ikke positiv deployer-registration før task-commit er deployment-registreret.

Expected: alle ændringer giver drift eller privilege denial før model-DML; det uændrede snapshot er stabilt. Denne fase må ikke registrere deployment eller køre gateway/integration mod HEAD-artifact.

- [ ] **Step 7: Commit kun Task 4B-filer**

```bash
git add schema.sql db-migrations.sql db-rls.sql db-verify.sql tests/sql/test-source-scoped-evidence-v3.sql \
  .claude/skills/daa-extract/scripts/build_source_scoped_evidence_v3_manifest.py \
  .claude/skills/daa-extract/scripts/test_build_source_scoped_evidence_v3_manifest.py
git commit -m "feat: close source scoped evidence inventory"
```

- [ ] **Step 8: Kør postcommit deployment-bundet inventory-registrering**

Kør den globale deployment-bundne verifikationsprotokol og en fresh-disposable,
CI-lignende registrering med den dedikerede gateway-loginrolle. Registrér en V3
deployment fra præcis `HEAD^{tree}` og verificér, at
`daa_source_scoped_evidence_deployer` alene kan registrere den matchende
inventory/artifact/database-binding og returnerer den canonical
deployment-ID/-hash. Denne task har endnu ingen V3-authorization-RPC eller
R-gateway; den må derfor ikke erklære gateway/apply-integration eller
dirty-writer-afvisning grøn. De navngivne V1-prototyper indgår fortsat ikke og
ændres ikke.

### Task 4C: Implementér policy-safe V3 visibility og publication-state

**Files:**
- Modify: `schema.sql`, `db-migrations.sql`, `db-rls.sql`, `db-verify.sql`
- Modify: `tests/sql/test-source-scoped-evidence-v3.sql`
- Create: `tests/integration/test-source-scoped-evidence-v3.R`

**Interfaces:**
- DB-ejede `SECURITY BARRIER` views `source_scoped_evidence_visible_{fact,assertion,citation}_ids` med relationel visibility-predikat; ingen parameteriseret visibility-funktion.
- Chain events: `source_revision_created`, `eligible`, `published`, `superseded`, `withdrawn`; state-hash schema `source-scoped-evidence-v3-chain-state-v1`.
- `red_authorize_source_scoped_evidence_publication_v3(uuid,uuid,uuid,text,jsonb,uuid,timestamptz) -> uuid` og `red_publish_source_scoped_evidence_revision_v3(uuid,jsonb) -> jsonb` bruger immutable deployment-ID, `expected_state_sha256`, `decision_payload`, nonce og single-use authorization.

- [ ] **Step 1: Skriv SQL RED-tests for visibility**

```sql
SET ROLE authenticated;
SELECT * FROM public.source_scoped_evidence_visible_fact_ids WHERE id = :draft_fact_id;
-- forvent 0 rows, samme resultat som ukendt id
SELECT to_regprocedure('private.source_scoped_evidence_v3_visibility_allowed(text,bigint)');
-- forvent NULL: ingen parameteriseret private-state-oracle findes
```

Tilføj en matrix for ubundet historisk row, eligible, publiceret, superseded og withdrawn fact/assertion/citation gennem direkte tabelread, hver inventory-fundet public view/RPC og alle note-/relation-afledte read paths. Assertér for hver celle, at draft/eligible/withdrawn returnerer samme tomme resultat som ukendt ID for `anon` og almindelig `authenticated`, mens ubundet og current public content følger den eksisterende gate.

- [ ] **Step 2: Kør RED-tests**

Run: disposable SQL- og integrationstest for source-scoped replace.

Expected: FAIL, fordi views, state-trigger og V3 publication route mangler.

- [ ] **Step 3: Implementér state-maskine og views**

Implementér append-event-triggeren med den lukkede transitionstabel, compare-and-swap på `state_version` og den eksakte state-hash preimage. Lad de tre DB-ejede security-barrier views kun returnere IDs, der både passerer den eksisterende public gate og er ubundne eller medlemmer af den visible V3 content-revision. PostgreSQL kræver `EXECUTE` for funktioner brugt af views, så bindingstesten skal ligge relationelt i views og ikke i en private no-grant helper. Brug default view-ejerprivilegier, aldrig `security_invoker`, og udtryk public-gaten eksplicit i hvert view. Grant kun `SELECT` på disse views til `anon,authenticated`; ingen parameteriseret private-state-oracle må være tilgængelig.

- [ ] **Step 4: Bind RLS og publication til V3**

Ændr fact/assertion/citation read policies til eksisterende gate plus `EXISTS` i korrekt visibility-view. Implementér de to V3 publication-RPC'er med `current_rolle()='redaktion'`, full decision payload/hash inklusive immutable deployment-ID/-hash, inventory/state recomputation, consumer NO-GO og atomisk publish/supersede/withdraw. Begge tager den fulde fælles lock-map i specifikationens rækkefølge (inklusive #152-resurser før V3 chain/model/ledger); ukendt shared resource afviser med `SOURCE_SCOPED_REPLACE_LOCK_INVENTORY_DRIFT` før state eller DML.

Tilføj før-DML negative authorization-matrix for publication: forkert database/system, actor, nonce-replay, expiry, chain/revision scope, state-hash, decision payload/hash og deployment-ID/-hash skal hver især afvise uden publication/state/event-række. Test samme matrix ved både første publish, supersede og withdraw.

- [ ] **Step 5: Kør kun precommit visibility- og negative publication-tests**

Run: SQL visibility-matrix for manually seeded immutable revisions, state-transition constraints og negative publication authorization med manglende/forfalsket deployment. Kør ikke positiv publish/supersede/withdraw eller race før task-commit er deployment-registreret.

Expected: ingen boolsk oracle, stale head og forged/manglende deployment afvises før DML. Positiv publication/race hører kun hjemme i postcommit-steppet.

- [ ] **Step 6: Commit kun Task 4C-filer**

```bash
git add schema.sql db-migrations.sql db-rls.sql db-verify.sql tests/sql/test-source-scoped-evidence-v3.sql tests/integration/test-source-scoped-evidence-v3.R
git commit -m "feat: gate source scoped evidence visibility"
```

- [ ] **Step 7: Kør postcommit deployment-bundet visibility-integration**

Kør den globale deployment-bundne verifikationsprotokol. Registrér deployment
fra `HEAD^{tree}` og kræv, at V3 publication receipt og alle tre visibility-
views refererer den samme immutable deployment-binding. En dirty V3 view/RPC-
eller writerfil skal afvises før publication authorization. Kør her den fulde
publication-authorization-matrix, inklusive alle negative driftceller mod en
gyldig deployment, og to-session publish/supersede/withdraw-race med samme
chain.

### Task 4D: Byg V3 semantic manifest, preflight og source apply

**Files:**
- Modify: `.claude/skills/daa-extract/scripts/build_source_scoped_evidence_v3_manifest.py`
- Create: `.claude/skills/daa-extract/scripts/apply_source_scoped_evidence_v3_helpers.R`
- Create: `.claude/skills/daa-extract/scripts/apply_source_scoped_evidence_v3.R`
- Create: `.claude/skills/daa-extract/scripts/test_apply_source_scoped_evidence_v3.R`
- Modify: `schema.sql`, `db-migrations.sql`, `db-rls.sql`, `db-verify.sql`
- Modify: `tests/sql/test-source-scoped-evidence-v3.sql`, `tests/integration/test-source-scoped-evidence-v3.R`
- Modify: `tests/sql/test-evidence-promotion.sql`, `tests/integration/test-evidence-promotion-writer-contract.R`

**Interfaces:**
- Semantic preimage is exactly `{schema,source_id,record_keys,input_sha256,dry_run_semantic_sha256,ownership_semantic_sha256,expected_counts,policy_decisions,narrative_operations,source_operations}` with `schema="source-scoped-replace-v3-semantic-v1"`; `manifest_semantic_sha256` is excluded. `policy_decisions` is exactly `[]`, and `expected_counts` is exactly `{source_operations,content_revisions,tombstone_revisions,facts,assertions,citations,narrative_operations}` with compiler and kernel rederivation.
- Every source operation has the closed `desired_chain={schema:"source-scoped-evidence-v3-desired-chain-v1",members}` input and `desired_chain_sha256=sha256(desired_chain)`. `create_chain`/`replace_chain`/`compensate_chain` require one `fact:1`, contiguous `assertion:N` and `citation:N` members, explicit nulls and only the exact fact/assertion/citation fields defined in the spec; `remove_owned_chain` requires the same schema with `members:[]`. Each operation also carries the three exact nullable-or-all-present predecessor fields for compensation. The writer derives all database IDs and foreign-key topology only from these member keys, never from caller IDs, raw input or a hash preimage.
- Kernel remeasures the versioned canonical preimages for chain key, prestate, ownership, preservation, expected-after, aggregate dry-run/ownership, record-attestation, profile and element scope; it persists the server measurements as immutable artifacts and rejects every client hash mismatch before DML.
- Gateway calls only `red_authorize_source_scoped_replace_v3(text,text,uuid,uuid,uuid,jsonb,text,text,text,text,timestamptz) -> uuid`, `red_apply_source_scoped_replace_v3(uuid,jsonb) -> jsonb` and `red_verify_source_scoped_replace_v3(uuid) -> jsonb`. Apply resubmits the exact canonical authorized manifest; same-manifest replay returns the existing receipt without DML, and any other payload fails. Verify takes the authorization ID and returns the closed `{receipt,apply_state,publication_state}` projection.
- The authorize arguments are, in order: `database_name`, `system_identifier`, `deployment_id`, `actor_id`, `nonce`, `manifest`, `manifest_semantic_sha256`, `dry_run_semantic_sha256`, `ownership_semantic_sha256`, `artifact_sha256`, `expires_at`; it rejects `actor_id <> auth.uid()` or a non-`redaktion` role before ledger DML. Apply requires the same actor and role; verify is readable by any current `redaktion` user. Only `authenticated` gets the explicit V3 EXECUTE grants.
- An immutable per-element authorization-attestation link binds `authorization_id`, `element_id`, `attestation_id` and `attestation_sha256`; authorization also persists hash-bound profile and element scope. Narrative operations are the closed `upsert|reverse` union, and reverse binds `original_event_id` plus `reversal_state_sha256`.
- Implementér den godkendte `source-scoped-evidence-v3-task4a-v4`-receipt-transition før Task 4D-kernen: valider en eksisterende v4 receipt før enhver mutation; uden v4 receipt afvises ethvert delvist v4 footprint; ellers valideres accepteret Task 4A-forgænger og betinget Task 4C-v7 før DDL. V4 bevarer de specificerede `source_scoped_replace_v3_*` navne og binder stabil DDL, trigger/RLS/ACL og fact/citation identity-sequence-paritet. Derefter binder `source-scoped-evidence-v3-task4d-v1` canonical helpers og færdige source-RPC'er med deres private ACL'er; `db-rls.sql` afslutter de eneste `authenticated` EXECUTE-grants med en efterfølgende `source-scoped-evidence-v3-task4d-v2` RLS-receipt.

- [ ] **Step 1: Skriv RED-tests for canonical manifest og gateway**

```python
assert semantic_hash(payload) == semantic_hash({**payload, "manifest_semantic_sha256": "0" * 64})
with pytest.raises(ManifestError, match="SOURCE_SCOPED_REPLACE_MANIFEST_INVALID"):
    build_manifest({"source_operations": [{"operation": "delete"}]})
with pytest.raises(ManifestError, match="SOURCE_SCOPED_REPLACE_MANIFEST_INVALID"):
    build_manifest(create_operation_without_desired_chain)
with pytest.raises(ManifestError, match="SOURCE_SCOPED_REPLACE_MANIFEST_INVALID"):
    build_manifest(create_operation_with_desired_chain_hash_mismatch)
with pytest.raises(ManifestError, match="SOURCE_SCOPED_REPLACE_MANIFEST_INVALID"):
    build_manifest(remove_operation_with_nonempty_desired_chain)
with pytest.raises(ManifestError, match="SOURCE_SCOPED_REPLACE_MANIFEST_INVALID"):
    build_manifest(payload_with_nonempty_policy_decisions)
with pytest.raises(ManifestError, match="SOURCE_SCOPED_REPLACE_MANIFEST_INVALID"):
    build_manifest(payload_with_wrong_expected_counts)
```

```r
expect_error(ssr_apply_v3(connection, manifest), "SOURCE_SCOPED_EVIDENCE_INVENTORY_DRIFT")
expect_false(any(grepl("dbAppendTable", readLines("apply_source_scoped_evidence_v3.R"), fixed = TRUE)))
expect_error(ssr_apply_v3(connection, changed_authorized_manifest), "SOURCE_SCOPED_REPLACE_V3_REPLAY_MISMATCH")
```

- [ ] **Step 2: Kør RED-tests**

Run: focused Python pytest, R testthat file og source-scoped SQL/integration tests.

Expected: FAIL, fordi V3 compiler/gateway/RPC'er mangler.

- [ ] **Step 3: Implementér closed manifest og R preflight**

Implementér stable key/array sortering, closed fields, raw-input identity adskilt fra semantic hash, exact source/narrative object validation og artifact-snapshot binding. Validér `policy_decisions=[]`, afledte expected counts, predecessor-felternes all-null/all-present-regel, narrative `upsert|reverse`, `desired_chain` med den lukkede fact/assertion/citation-projektion, eksplicitte nuller, sammenhængende member keys/referencer, relations-/dato-domæner og dens selvstændige hash før den indgår i source-operationens semantic hash. R-preflight bruger `BEGIN READ ONLY`, validerer manifest/artifact og kun publict læsbare checks, returnerer ingen tekst til receipt og får hverken `private`-privilegier eller en ny preflight-RPC. Autorisationskernen genmåler alle versionerede hashprojektioner, deployment-, inventory-, identity-, attestation-, profile-, scope- og ownership-bindinger atomisk før DML og apply genmåler dem igen under låsene.

- [ ] **Step 4: Implementér V3 authorize/apply/verify kernel**

Autorisationen binder immutable deployment-ID/-hash, semantic/dry-run/ownership/attestation/profile/deployment-artifact/database hashes, actor, nonce, expiry og element scope, herunder den per-element immutable authorization-attestation-linkrække. Apply genkører preflight under låseordenen: narrative contract, source scope, source records UUID, `change_set` access-exclusive, persons, #152 resources, V3 chain/bindings, model rows, ledger. Den genberegner alle hashprojektioner og `desired_chain_sha256`, indsætter alene de præcist deklarerede fact/assertion/citation-projektioner i den deklarerede member-topologi og persisterer de afledte database-ID'er som immutable V3 members; den må ikke konsultere V1, raw input eller en anden modeldata-kilde. #152 narrative upsert eller den præcist bundne reversal er sidste model-DML og skal returnere kun det tilladte event. Harden samtidig `red_authorize_interpretation_promotions` og `red_promote_interpretations_batch`, så promotion tager den samme fulde lock-map for overlap med V3 source scope; en manglende shared resource afviser med `SOURCE_SCOPED_REPLACE_LOCK_INVENTORY_DRIFT` før promotion-DML.

- [ ] **Step 5: Implementér compensation og verifier**

Compensation kræver nyt `compensate_chain`-manifest med all-present predecessor-felter, ny authorization/current-state-attestation og samme tidligere committed batch/artifact/hash; den opretter en ny content eller tombstone revision uden model-delete med predecessorens verified prestate som eneste desired state. Narrativ compensation kalder den dedikerede #152 reversal mod præcist sidste ikke-reverserede event og binder `original_event_id` samt `reversal_state_sha256`. Verifieren returnerer de præcist versionerede immutable `apply_state` og levende `publication_state`; receipt’en har versioneret grammar, sorteret mappings, observed counts og canonical `receipt_sha256`.

- [ ] **Step 6: Kør kun precommit manifest- og negative authorization-tests**

Run: pure manifest/preflight tests samt source-authorization-celler med manglende/forfalsket deployment. Injectér en uregistreret shared resource i V3/promotion lock-preflight og kræv `SOURCE_SCOPED_REPLACE_LOCK_INVENTORY_DRIFT` før model-DML. Kør ikke actor-, database/system-, nonce-, expiry-, scope- eller hash-driftceller mod en gyldig deployment, og kør ikke positiv apply, replay, compensation, narrative reversal eller race, før task-commit er deployment-registreret.

Expected: hver negativ fejl ruller hele batchen tilbage uden receipt. Positiv apply/replay/compensation/race hører kun hjemme i postcommit-steppet.

- [ ] **Step 7: Commit kun Task 4D-filer**

```bash
git add schema.sql db-migrations.sql db-rls.sql db-verify.sql tests/sql/test-source-scoped-evidence-v3.sql tests/integration/test-source-scoped-evidence-v3.R \
  tests/sql/test-evidence-promotion.sql tests/integration/test-evidence-promotion-writer-contract.R \
  .claude/skills/daa-extract/scripts/build_source_scoped_evidence_v3_manifest.py \
  .claude/skills/daa-extract/scripts/apply_source_scoped_evidence_v3_helpers.R \
  .claude/skills/daa-extract/scripts/apply_source_scoped_evidence_v3.R \
  .claude/skills/daa-extract/scripts/test_apply_source_scoped_evidence_v3.R
git commit -m "feat: add source scoped evidence v3 writer"
```

- [ ] **Step 8: Kør postcommit source-apply integration**

Kør den globale deployment-bundne verifikationsprotokol. Registrér deployment
fra dette task-commit og kør apply/replay/compensation/narrative-race integration
mod den persisterede ID/hash. Begge former for dirty V3-writer skal afvises før
authorization; dette er også den udsatte authorization-/dirty-writer-gate fra
Task 4B. En ændret V3 fil kræver ny commit og gentagen postcommit-test.
Kør her den fulde source-authorization-matrix mod en gyldig deployment, positive
create/replace/remove/compensation, exact replay, narrative reversal og den
fulde source/narrative/publication/promotion race-matrix.

### Task 4E: Implementér V3 baseline-adoption

**Files:**
- Modify: `schema.sql`, `db-migrations.sql`, `db-rls.sql`, `db-verify.sql`
- Modify: `tests/sql/test-source-scoped-evidence-v3.sql`, `tests/integration/test-source-scoped-evidence-v3.R`

**Interfaces:**
- `red_authorize_source_scoped_evidence_adoption_v3(uuid,jsonb,text,jsonb,uuid,timestamptz) -> uuid`.
- `red_adopt_source_scoped_evidence_v3(uuid,jsonb,jsonb) -> jsonb`.
- Candidate binds sorted `{member_kind,db_id,row_sha256}` plus `member_state_sha256` and role-projected `legacy_visibility_sha256`.

- [ ] **Step 1: Skriv adoption RED-tests**

```sql
-- skjult, consumer-bundet eller stale baseline må ikke adopteres
SELECT public.red_adopt_source_scoped_evidence_v3(:auth_id, :candidate, :decision);
-- forvent SOURCE_SCOPED_EVIDENCE_ADOPTION_STALE eller consumer/policy NO-GO
```

- [ ] **Step 2: Kør RED-testen**

Run: disposable `tests/sql/test-source-scoped-evidence-v3.sql` og `tests/integration/test-source-scoped-evidence-v3.R`.

Expected: FAIL, fordi V3 adoption RPC'er mangler.

- [ ] **Step 3: Implementér candidate/authorize/adopt**

Mål eksisterende public gates eksplicit som `anon` og `authenticated` projections uden SECURITY DEFINER RLS-bypass. Bind immutable deployment-ID/-hash, candidate hash, beslutningspayload/hash, rationale, policy basis, expected state, actor, database, nonce og expiry. Kræv `current_rolle()='redaktion'` i begge V3-RPC'er, tag den samme fulde lock-map som source/publication/promotion og afvis ukendt shared resource med `SOURCE_SCOPED_REPLACE_LOCK_INVENTORY_DRIFT`. Opret binding/publication/receipt atomisk kun ved fuldt positiv legacy visibility. Tilføj før-DML adoption-authorization-matrix for forkert database/system, actor, nonce-replay, expiry, deployment-ID/-hash, candidate/member-state/legacy-visibility hash, expected state, decision payload/hash/policy basis og scope; hver variant skal efterlade nul nye binding/publication/event/receipt-rækker.

- [ ] **Step 4: Kør kun precommit candidate- og negative ACL-tests**

Run: read-only candidate measurement, hidden/nonexistent indistinguishability, migration parity og den negative adoption-authorization-matrix med manglende/forfalsket deployment. Injectér en uregistreret shared resource og kræv `SOURCE_SCOPED_REPLACE_LOCK_INVENTORY_DRIFT` før DML. Kør ikke positiv adoption eller adoption/publication-race før task-commit er deployment-registreret.

Expected: negative cases efterlader nul binding/publication/event/receipt-rækker. Positiv adoption/race hører kun hjemme i postcommit-steppet.

- [ ] **Step 5: Commit kun Task 4E-filer**

```bash
git add schema.sql db-migrations.sql db-rls.sql db-verify.sql tests/sql/test-source-scoped-evidence-v3.sql tests/integration/test-source-scoped-evidence-v3.R
git commit -m "feat: authorize source scoped evidence baseline adoption"
```

- [ ] **Step 6: Kør postcommit adoption-integration**

Kør den globale deployment-bundne verifikationsprotokol og registrér deployment
fra dette task-commit. Adoption/publication-racen skal bruge samme persisterede
deployment-ID/-hash og afvise en stale, forged eller dirty V3 binding før DML.
Kør her den fulde adoption-authorization-matrix mod en gyldig deployment, den
positive legacy baseline og adoption/publication-racen; adoption må stadig
aldrig skabe modelrows eller ny offentlighed.

### Task 5: Delegér source-scoped legacy entrypoints til V3 uden bypass

**Files:**
- Modify: `.claude/skills/daa-extract/scripts/load_daa.R`, `.claude/skills/daa-extract/scripts/post_load_fixup.R`
- Modify: `R/update-1939-narratives.R`, `R/update-2018-narratives.R`
- Modify: `tests/testthat/test-load-daa.R`, `tests/testthat/test-update-1939-narratives.R`, `tests/testthat/test-update-2018-narratives.R`, `tests/testthat/test-narrative-record-source-inventory.R`
- Create: `tests/integration/test-source-scoped-evidence-v3-entrypoints.R`

- [ ] **Step 1: Skriv failing static- og runtime-tests**

```r
expect_error(run_loader(c("--replace", manifest_path)), "SOURCE_SCOPED_REPLACE_V3_REQUIRED")
expect_false(entrypoint_has_direct_model_dml("R/update-1939-narratives.R"))
```

- [ ] **Step 2: Kør RED-suiterne**

Run: berørte testthat-filer og `tests/integration/test-source-scoped-evidence-v3-entrypoints.R` på disposable DB.

Expected: FAIL, fordi V3 delegation/allowlist endnu mangler.

- [ ] **Step 3: Implementér minimal, explicit delegation**

Tillad kun `--replace` med verified V3 manifest/deployment artifact binding og authorization. Kald gatewayen som R-funktion uden credentials i argumenter. Behold v2 legacy gates og alle append/reset/direct routes blokerede; klassificér eventuelle ikke-source writers i artifact inventory i stedet for at skabe en bypass.

- [ ] **Step 4: Kør kun precommit PASS- og bypass-tests**

Run: static scan plus runtime check af, at en source-scoped operation observerer V3 receipt og højst #152 draft-event.

Expected: ingen post-v2 direkte narrative- eller model-DML route kan mutere source scope.

- [ ] **Step 5: Commit kun Task 5-filer**

```bash
git add .claude/skills/daa-extract/scripts/load_daa.R .claude/skills/daa-extract/scripts/post_load_fixup.R \
  R/update-1939-narratives.R R/update-2018-narratives.R tests/testthat/test-load-daa.R \
  tests/testthat/test-update-1939-narratives.R tests/testthat/test-update-2018-narratives.R \
  tests/testthat/test-narrative-record-source-inventory.R tests/integration/test-source-scoped-evidence-v3-entrypoints.R
git commit -m "refactor: route source scoped writers through v3"
```

- [ ] **Step 6: Kør postcommit entrypoint-integration**

Kør den globale deployment-bundne verifikationsprotokol. Det committed V3
entrypoint skal delegere og returnere samme deployment-bundne receipt; enhver
dirty/untracked V3 entrypointfil skal afvises før authorization uden at berøre
den beskyttede V1-prototype.

### Task 6: Conformance, runbook og endelig #153-verifikation

**Files:**
- Create: `docs/runbooks/source-scoped-replace.md`
- Modify: `tests/sql/test-writer-batch-contract.sql`, `tests/integration/test-writer-batch-contract.R`
- Modify: `docs/superpowers/plans/2026-08-31-source-scoped-evidence-visibility-implementation.md` kun for verificerede command-/evidencekorrektioner.

- [ ] **Step 1: Skriv failing V3 conformance cases**

Krav: profil `execution_kind=apply`, `authorization_mode=single_use_database_authorization`, `reversal_mode=compensating`; V3 apply/publication receipts er adskilte; V1 RPC'er afviser; C3 forbliver read-only conformance; #152 locking er fælles.

- [ ] **Step 2: Kør RED-kontraktsuiten**

Run: `Rscript .claude/skills/daa-extract/scripts/test_verify_writer_batch_conformance.R` samt source-scoped SQL/integration suites.

Expected: FAIL indtil V3 receipt-/conformance adapteren kan inspicere den lukkede V3 route.

- [ ] **Step 3: Implementér kun read-only conformance og runbook**

Conformance læser V3 receipts/current state uden at genkøre committed apply. Runbooken angiver read-only dry-run, artifact/deployment binding, redaktionel beslutning, draft-only narrativ, publish/supersede/withdraw, compensation, receipt/current-state og recovery. Den må ikke love produktion eller generisk undo.

- [ ] **Step 4: Kør fuld afgrænset verification**

Run: Python manifest/artifact tests; R helper/gateway tests; source-scoped SQL/integration/entrypoint tests; writer-batch conformance; fresh-schema/migrated parity; `git diff --check`; relevante #152 narrative concurrency tests.

Expected: PASS på hver suite; rapportér uafhængigt, hvis en bredere eksisterende suite fejler uden for diffens scope.

- [ ] **Step 5: Selvreview og uafhængigt Sol-review**

Selvreview: schema/migration parity, V1 retirement, alle V3 grants, private-state-oracle, state-transitioner, typed members, repository artifact binding, raw-DML denial, receipts, #152 locks og narrative compensation. Derefter skal GPT-5.6-Sol read-only reviewe diff og relevant omliggende kode. Behandl hvert fund kritisk; rerun relevante tests efter gyldige fixes og genreview kun hvis design/risk ændres materielt.

- [ ] **Step 6: Commit dokumentation og conformance**

```bash
git add docs/runbooks/source-scoped-replace.md tests/sql/test-writer-batch-contract.sql tests/integration/test-writer-batch-contract.R \
  docs/superpowers/plans/2026-08-31-source-scoped-evidence-visibility-implementation.md
git commit -m "test: verify source scoped evidence v3 contract"
```

- [ ] **Step 7: Slutcheckpoint**

Bekræft branch, HEAD, commits, path-specifik worktree-status, alle command-resultater og at ingen production-DB, push, merge eller deploy fandt sted. Først derefter anmodes brugeren om integrationsdisposition.
