# #153 generalized reimport-writer: disposable rehearsal

**Observed:** 2026-09-02
**Code commits exercised:** Task 7/8 evidence through `b5dd0da`, Task 9 through
`120b953`, and Task 10 through `09a2bf6`
**Result:** **OBSERVED GREEN for #153 code-integration evidence.**

This is bounded local-disposable evidence, not a production authorization. No
production database, push, merge, deploy, or network action was used, and no
`work/` or protected review artifact was accessed. Every PostgreSQL command
used all five variables together:

```bash
env PGHOST=127.0.0.1 PGPORT=55441 PGDATABASE=<named-db> PGUSER=johanreventlow PGPASSWORD='' <command>
```

Local PostgreSQL 17 had `dblink` available. The `RPostgres` integrations emit
their known non-fatal open-result-close warnings, but all commands below exited
0.

## Installation and C3 contract tracks

The v1 C3 databases deliberately stop after schema, migrations, and RLS. This
is required because the #152 version-aware C3 ACL contract fail-closes its
public writer calls under v2; it is not an ACL or C3-model change.

| Track | Named database | Setup and verification | Exit |
| --- | --- | --- | --- |
| fresh v1 C3 | `daa153_t7_freshv1c3_20260902` | bootstrap; `CREATE EXTENSION dblink`; `schema.sql`; `db-migrations.sql`; `db-rls.sql`; asserted `narrative_record_contract_version()=1`; `test-1939-v50-c3-apply.sql` | 0 |
| upgraded v1 C3 | `daa153_t7_upgv1c3_20260902` | bootstrap; `git show 2d6aabf:schema.sql`; `/private/tmp/daa153-task7-upgrade-terminal-fixture.sql`; current migrations/RLS; asserted contract 1; full C3 test | 0 |
| fresh v2 writer | `daa153_t7_freshv2full_20260902` | bootstrap/schema/migrations/RLS, writer SQL fixtures, v2 writer flow, legacy facade, catalog and complete verifier | 0 |
| upgraded v2 writer | `daa153_t7_upgv2_20260902` | bootstrap; historic `2d6aabf` schema plus terminal fixture; current migrations/RLS; migration parity, writer/legacy/catalog/verifier | 0 |

The C3 commands were:

```bash
env PGHOST=127.0.0.1 PGPORT=55441 PGDATABASE=daa153_t7_freshv1c3_20260902 PGUSER=johanreventlow PGPASSWORD='' \
  /opt/homebrew/opt/postgresql@17/bin/psql -X -v ON_ERROR_STOP=1 -f tests/sql/test-1939-v50-c3-apply.sql
env PGHOST=127.0.0.1 PGPORT=55441 PGDATABASE=daa153_t7_upgv1c3_20260902 PGUSER=johanreventlow PGPASSWORD='' \
  /opt/homebrew/opt/postgresql@17/bin/psql -X -v ON_ERROR_STOP=1 -f tests/sql/test-1939-v50-c3-apply.sql
```

Both full regressions exited 0. They include the upgraded-current-migration
gate for the two C3 helpers, prove both remain private/revoked, and exercise
the actual public preview/authorize/apply/reversal paths. The test's direct
`auth.uid()` assertion is made only before role switching; service and
authenticated role behavior is proven through the existing public positive and
negative calls.

On each v2 database, a separate in-transaction probe asserted contract 2,
authenticated has no `red_apply_reimport_cases` execute privilege, service has
no `red_authorize_reimport_cases` execute privilege, and each attempted call
raises `insufficient_privilege`. The fresh and upgraded probes both exited 0:

```text
OK: Task7 fresh v2 C3 writer ACL is fail-closed
OK: Task7 fresh v2 C3 apply execution denied
OK: Task7 fresh v2 C3 authorize execution denied
OK: Task7 upgraded v2 C3 writer ACL is fail-closed
OK: Task7 upgraded v2 C3 apply execution denied
OK: Task7 upgraded v2 C3 authorize execution denied
```

The following exact probe was rerun after the final catalog correction and
exited 0 for both named v2 databases:

```bash
for task_db in daa153_t7_freshv2full_20260902 daa153_t7_upgv2_20260902; do
  env PGHOST=127.0.0.1 PGPORT=55441 PGDATABASE=$task_db PGUSER=johanreventlow PGPASSWORD='' \
    /opt/homebrew/opt/postgresql@17/bin/psql -X -v ON_ERROR_STOP=1 -c "BEGIN; DO \$probe\$ BEGIN IF public.narrative_record_contract_version()<>2 THEN RAISE EXCEPTION 'TASK7_V2_CONTRACT_INVALID'; END IF; IF has_function_privilege('authenticated','public.red_apply_reimport_cases(uuid,text,text)','EXECUTE') OR has_function_privilege('service_role','public.red_authorize_reimport_cases(bigint,text,text,text,text,text,text,text,text,text,text,jsonb,jsonb,uuid,timestamp with time zone)','EXECUTE') THEN RAISE EXCEPTION 'TASK7_C3_ACL_OPEN'; END IF; EXECUTE 'SET LOCAL ROLE authenticated'; BEGIN PERFORM public.red_apply_reimport_cases(gen_random_uuid(),repeat('a',64),repeat('b',64)); RAISE EXCEPTION 'TASK7_AUTHENTICATED_APPLY_WAS_ALLOWED'; EXCEPTION WHEN insufficient_privilege THEN NULL; END; EXECUTE 'RESET ROLE'; EXECUTE 'SET LOCAL ROLE service_role'; BEGIN PERFORM public.red_authorize_reimport_cases(1,'c3','apply',repeat('a',64),repeat('b',64),repeat('c',64),repeat('d',64),repeat('e',64),repeat('f',64),current_database(),'x','{}'::jsonb,'{}'::jsonb,gen_random_uuid(),clock_timestamp()+interval '1 minute'); RAISE EXCEPTION 'TASK7_SERVICE_AUTHORIZE_WAS_ALLOWED'; EXCEPTION WHEN insufficient_privilege THEN NULL; END; EXECUTE 'RESET ROLE'; RAISE NOTICE 'OK: Task7 v2 C3 public surface fail-closed'; END \$probe\$; ROLLBACK;"
done
```

## Generic, legacy, migration, and catalog evidence

On both named v2 databases, the following full SQL groups exited 0. The
upgraded database uses the same commands after its historical-schema/migration
setup; its generic migration assertion is included first.

```bash
env PGHOST=127.0.0.1 PGPORT=55441 PGDATABASE=daa153_t7_freshv2full_20260902 PGUSER=johanreventlow PGPASSWORD='' \
  /opt/homebrew/opt/postgresql@17/bin/psql -X -v ON_ERROR_STOP=1 \
  -f tests/sql/test-reimport-writer.sql \
  -f tests/sql/test-reimport-name-completion.sql \
  -f tests/sql/test-1939-v50-production-writer.sql \
  -f tests/sql/test-1939-v50-name-completion.sql \
  -f tests/sql/run-db-verify-disposable.sql \
  -f tests/sql/test-reimport-edition-catalog.sql

env PGHOST=127.0.0.1 PGPORT=55441 PGDATABASE=daa153_t7_upgv2_20260902 PGUSER=johanreventlow PGPASSWORD='' \
  /opt/homebrew/opt/postgresql@17/bin/psql -X -v ON_ERROR_STOP=1 \
  -f tests/sql/test-reimport-writer-migration.sql \
  -f tests/sql/test-reimport-writer.sql \
  -f tests/sql/test-reimport-name-completion.sql \
  -f tests/sql/test-1939-v50-production-writer.sql \
  -f tests/sql/test-1939-v50-name-completion.sql \
  -f tests/sql/run-db-verify-disposable.sql \
  -f tests/sql/test-reimport-edition-catalog.sql
```

The complete verifier reported `OK: all five dblink concurrency gates
executed` on each v2 database. Its pre-existing, unrelated Task 12b
`storage.objects` and forældre-backfill skips remain environmental limitations
outside #153 and are not counted as #153 coverage.

The deliberate ordering is important and was observed on both v2 tracks: each
top-level generic SQL test starts from contract 1, proves the generic writer's
v1 gate, and then invokes `\ir reimport-writer-v2-bootstrap.sql` inside its
own `BEGIN`/`COMMIT` transaction. Therefore it must not be preceded by a
separate bootstrap. The two top-level commands above are the exact invocations
of that bootstrap for fresh and upgraded writer/name flows; invoking the
bootstrap file alone in autocommit is invalid because its temporary fixture
tables are `ON COMMIT DROP`. For isolated DBI fixture databases where an
explicit bootstrap was required, the successful form was:

```bash
env PGHOST=127.0.0.1 PGPORT=55441 PGDATABASE=daa153_t7_rlegacy2_20260902 PGUSER=johanreventlow PGPASSWORD='' \
  /opt/homebrew/opt/postgresql@17/bin/psql -X -v ON_ERROR_STOP=1 -c 'BEGIN' \
  -f tests/sql/reimport-writer-v2-bootstrap.sql -c 'COMMIT' -f db-rls.sql
```

The exact catalog commands exited 0 and `cmp` found no difference:

```bash
env PGHOST=127.0.0.1 PGPORT=55441 PGDATABASE=daa153_t7_freshv2full_20260902 PGUSER=johanreventlow PGPASSWORD='' \
  /opt/homebrew/opt/postgresql@17/bin/psql -X -At -o /private/tmp/daa153-t7-freshv2final-catalog.json -f tests/sql/inspect-reimport-writer-catalog.sql
env PGHOST=127.0.0.1 PGPORT=55441 PGDATABASE=daa153_t7_upgv2_20260902 PGUSER=johanreventlow PGPASSWORD='' \
  /opt/homebrew/opt/postgresql@17/bin/psql -X -At -o /private/tmp/daa153-t7-upgv2final-catalog.json -f tests/sql/inspect-reimport-writer-catalog.sql
cmp /private/tmp/daa153-t7-freshv2final-catalog.json /private/tmp/daa153-t7-upgv2final-catalog.json
shasum -a 256 /private/tmp/daa153-t7-freshv2final-catalog.json /private/tmp/daa153-t7-upgv2final-catalog.json
```

Each file is 27,598 bytes with SHA-256
`93d690680d712be95e419e4530cfb6c6f5e3a5271a9d45d0944637e2a3be200e`.
The approved catalog correction allowlists only
`private.require_reimport_1939_editor()` and
`private.reimport_1939_canonical_json_sha256(jsonb)`, whose unqualified
serialized names are required by the verifier's `pg_catalog, public, private`
search path. The catalog negatives remain green; no other edition object was
allowlisted.

## DBI and R evidence

The required generic DBI integration ran against the fresh v2 database:

```bash
env PGHOST=127.0.0.1 PGPORT=55441 PGDATABASE=daa153_t7_freshv2full_20260902 PGUSER=johanreventlow PGPASSWORD='' \
  Rscript tests/integration/test-reimport-writer.R
```

It exited 0 with `PASS generic reimport writer DBI integration`. It actually
calls generic `red_apply_reimport_person_create` and verifies its v2
event-backed narrative/publication receipt; creates distinct profiles with an
equal hash; verifies a rolled-back authorization/batch leaves no ledger/domain
rows; rejects an unauthorized caller; and rejects reversal and activation that
cross profile identity. Its synthetic placement proposal and decision evidence
is deterministic and non-empty (`{"fixture":"task7-v2"}`), so no placement
gate was weakened.

The two compatibility integrations used isolated prepared databases and both
exited 0:

```bash
env PGHOST=127.0.0.1 PGPORT=55441 PGDATABASE=daa153_t7_rlegacy2_20260902 PGUSER=johanreventlow PGPASSWORD='' Rscript tests/integration/test-1939-v50-production-writer.R
env PGHOST=127.0.0.1 PGPORT=55441 PGDATABASE=daa153_t7_rname2_20260902 PGUSER=johanreventlow PGPASSWORD='' Rscript tests/integration/test-1939-v50-name-completion.R
```

They printed respectively `PASS DAA 1939 v50 PostgreSQL integration` and
`PASS DAA 1939 v50 name completion PostgreSQL integration`. The production
writer integration exercises the approved `public.red_reimport_batch_result`
replay-result RPC, including an `already_applied` result.

Focused generic and compatibility testthat suites also exited 0:

```bash
for test_file in tests/testthat/test-apply-reimport.R tests/testthat/test-apply-name-completion.R tests/testthat/test-apply-reimport-1939-v50.R tests/testthat/test-apply-name-completion-1939-v50.R tests/testthat/test-reimport-writer-source-inventory.R; do Rscript -e "testthat::test_file('$test_file')" || exit 1; done
```

They reported 16, 10, 7, 6, and 105 passing expectations respectively.

## Self-review against design §§1 and 6

| Requirement | Current observed evidence | Result |
| --- | --- | --- |
| Generic permanent primaries, profile identity, and v2 event-backed mutations | fresh/upgraded generic SQL, generic DBI person creation, source-inventory suite | green |
| Equal-hash profile separation, rollback, authorization and lifecycle identity gates | generic SQL/name and actual generic DBI assertions | green |
| Exact one-version 1939 transition facade and replay receipt | legacy SQL and both legacy DBI integrations; replay-result RPC asserted | green |
| Fresh/upgraded parity, migration preservation, catalog/allowlist gate | upgraded migration fixture, two full verifier/catalog runs, byte-identical catalog | green |
| C3 remains unchanged rather than folded into generic writer | full fresh/upgraded v1 C3; private/revoked helpers; v2 fail-closed probes | green |
| Local-only / no protected-input boundary | named local databases only; no production/network/push/merge/deploy; no `work/` read | green within this rehearsal |

`git diff --check 92d71dc45f137abb7048a852eeea20e1594ed42c..b5dd0da` and the
pending documentation diff both exited 0. The review found no remaining
source-specific generic writer primary: the only retained 1939 helper names
are the exact C3 compatibility aliases, private and revoked. This record does
not replace the controller-owned independent read-only Sol review and is not a
production GO.

## Task 8 correction evidence (2026-09-02)

Task 8 seals the profile hash against the canonical writer configuration,
binds generic gateway authorization to the full server identity, validates
authorized count/element envelopes before issuing authorization, and replaces
the cooperative global name-completion mutex with a transaction-scoped
`source_id + profile_id` writer lock. The compatibility adapters now derive
the 1939 profile hash from the same canonical configuration; the verified hash
is `25349caff16f2c13002a4950e80fe8697ffcf49e196dbcd9d1550919caf52fd3`.

The following additional named local disposable databases exited 0; every
command used the five-variable environment shown above.

| Database | Observed verification |
| --- | --- |
| `daa153_t8_final_20260902` | Fresh v2 generic DBI writer integration: full database/system identity, canonical profile hash, malformed count/element rejection, same-hash changed-element replay drift and event-backed person creation. |
| `daa153_t8_lock_20260902` | Real multi-connection source/profile lock proof: same profile cannot acquire the advisory lock while a writer transaction holds it; a different profile can. |
| `daa153_t8_legacy2_20260902` | Clean ordered compatibility DBI sequence: `PASS DAA 1939 v50 PostgreSQL integration` and `PASS DAA 1939 v50 name completion PostgreSQL integration`. |
| `daa153_t8_sql2_20260902` | Fresh generic writer SQL, generic name-completion SQL, legacy production-writer SQL and legacy name-completion SQL suites. Each exited 0. |

Focused R gateway tests also exited 0 for generic reimport, generic
name-completion, and both compatibility adapters. The new negative cases
reject a server authorization preflight cloned to another system identifier,
and prevent `begin` after rejection. `git diff --check` exited 0 after these
updates.

Task 8 Step 4's terminal-upgrade and parity proof was then rerun from a clean
pre-#153 schema at `2d6aabf` in the named local database
`daa153_t8v_upg_v2b_20260902`. Its historical source batch is `reversed`; its
consumed name-completion child is `finalized`; and its child result points back
to that source batch. With
`app.reimport_writer_atomicity_test_failpoint=on`, the migration failed only
with `REIMPORT_WRITER_ATOMICITY_TEST_FAILURE`; the rollback assertion then
passed before the actual migration and RLS application. The post-upgrade
terminal migration assertion, generic and legacy SQL suites, catalog
negatives, and complete disposable verifier all exited 0. The verifier again
reported `OK: all five dblink concurrency gates executed`.

The migration correction is limited to the private coexistence fallback in
`db-migrations.sql`: it dynamically dispatches old-physical-table statements
only when such a table exists. This avoids PL/pgSQL resolving a table that the
terminal rename path has already moved to its generic primary. It changes
neither the C3 model nor any C3 ACL. The CI terminal fixture now matches its
own assertion: authorization `...103` is a consumed `name_completion` child
and batch `...105` is `finalized`, with source batch `...102` reversed.

Fresh/upgraded v2 catalog receipts, including `pg_get_functiondef` body
digests, were byte-identical:

```text
31,504 bytes
SHA-256 5f38e10575d52d22b3aef41b5f82e90f4b920afc369bdd5931f52cf2f0cbe269
```

Fresh v1 (`daa153_t8v_fresh_v1_c3_20260902`) and upgraded v1
(`daa153_t8v_upg_v1_c3_20260902`) both passed the full C3 SQL regression after
the migration-only correction. Fresh/upgraded v2 probes confirmed that C3's
public writer surface remains fail-closed. The dedicated compatibility DBI
fixtures `daa153_t8v_legacy_prod_20260902` and
`daa153_t8v_legacy_name_20260902` respectively printed `PASS DAA 1939 v50
PostgreSQL integration` and `PASS DAA 1939 v50 name completion PostgreSQL
integration`. Focused R gateway suites passed with 20, 14, 7, 6, and 188
expectations. This remains local code-integration evidence only, not
production authority; the independent Task 8 Sol re-review remains required.

### Task 8 terminal-topology correction (latest observed evidence)

This subsection supersedes the earlier status-only terminal description above.
The migration now accepts only an activated reimport source with exactly one
finalized name-completion child, or a reversed source with exactly one reversed
child. It verifies the old authorization, batch, event and result linkage
before renaming any ledger relation.

The RED case was `daa153_t8_empty_red_bootstrap_20260902`: bootstrap plus
exact `2d6aabf:schema.sql`, source 3, and all four physical v1 ledger tables
empty. The prior migration stopped with
`REIMPORT_WRITER_LEGACY_SOURCE_IDENTITY_INVALID`. The narrow correction permits
only this zero-authorization legacy ledger. It does not relax a nonempty
ledger: `daa153_t8_identity_wrong_source_green_20260902` and
`daa153_t8_identity_multi_source_green_20260902` both rejected with that same
identity error and retained `private.reimport_1939_authorization` as a physical
table.

The real v1 history proof used
`daa153_t8_terminal_green3_20260902`: pre-#153 RPCs created two independent
eight-row chains, one activated/finalized and one reversed/reversed, each with
eight `person_create` events, eight `canonical_delta` events and eight retained
name-completion results. The migration failpoint produced only
`REIMPORT_WRITER_ATOMICITY_TEST_FAILURE`; the rollback assertion, normal
migration, post-migration terminal assertions and full v1 C3 regression then
all exited 0. Four malformed terminal fixtures (orphan child, finalized child
under reversed source, broken result and ambiguous child) were rejected before
DDL with `REIMPORT_LEGACY_IN_FLIGHT_MIGRATION_BLOCKED`.

The separate clean upgraded-v2 baseline was
`daa153_t8_empty_green2_20260902`: exact `2d6aabf` schema, source 3 and empty
physical ledger, current migration/RLS, then the existing truthful v2 bootstrap.
Generic writer/name-completion/legacy SQL, full disposable `db-verify.sql`
(including all five `dblink` gates), edition catalog and generic R/DBI writer
integration all exited 0. Its effective catalog receipt was byte-identical to
the separate clean-fresh v2 database `daa153_t8_cleanv2_20260902`: 31,504
bytes and SHA-256
`4e3bf726292c6d4be08ca6c6bf9d01a4d3fed36a6ad254b8169f5a60bfdcb437`.

The real eight-row historical database deliberately remains a v1-only
migration/C3 track. Applying the existing #152 v2 bootstrap there correctly
stops with `CUTOVER_INVENTORY_LIVE_DRIFT`; this is not candidate, cutover or
approval evidence. Focused v2 C3 public-surface probes passed fail-closed on
both clean v2 baselines. No #152 inventory/cutover/C3 policy, production data,
network service, protected review artifact or `work/` content was changed or
accessed.

## Task 9 and Task 10 final correction evidence

Task 9 completed the generic RPC, server-bound source/profile identity,
closed profile configuration, cross-profile concurrency and terminal
source-record integrity work through `120b953`. The first integrated Sol
review then correctly rejected its private `max(id)+1` allocation premise:
that lock did not coordinate ordinary default writers and reversal could make
an append-only result ID reusable. Task 10 replaced that premise with shared
identity/default allocation and added exact same-source provenance checks,
typed page evidence, order-independent R count comparison, and the missing
preflight ACL.

The bounded implementation commits are `396bf68`, `67859d4`, `a2b3664`,
`7489b64`, and `09a2bf6`. Focused RED evidence covered reordered R
expected-count keys, invalid page evidence reaching the gateway/SQL
authorization, retained result-ID reuse after reversal, acceptance of the JSON
string `\"1\"` as a page, upgraded migration referencing preflight before
creation, and locale-dependent catalog receipt ordering.

All corresponding GREEN checks passed. Final fresh-v2
`daa153_sol2_freshv2_20260902a` and clean upgraded-v2
`daa153_sol2_upgv2_20260902a` both had contract version 2. Before
`db-rls.sql`, the fresh schema and upgraded migration each exposed preflight
only to its owner and `authenticated` (`anon=false`,
`authenticated=true`, `service_role=false`). The complete name-completion
SQL suite, including the numeric-string case, exited 0 on both databases.

Historical terminal-v1 `daa153_sol2_terminal_20260902a` retained contract
version 1. Its failpoint migration exited 3 with
`REIMPORT_WRITER_ATOMICITY_TEST_FAILURE`; rollback assertion, normal
migration, RLS and terminal migration suite then exited 0. The separate
`source_record_wrong` fixture was rejected before DDL with
`REIMPORT_LEGACY_IN_FLIGHT_MIGRATION_BLOCKED` and retained its physical
legacy ledger. These are local disposable checks, not production authority.

Fresh/upgraded effective catalog receipts were raw-byte-identical without
post-processing: 33,466 bytes and SHA-256
`e72f65f6d764c32ee0e217d4425b40f40eae70b1721503313934afd310f6eeeb`.
Final focused R checks passed with 34 expectations for name completion and 200
for source inventory. The generic R writer suite, ordinary-writer/two-profile
concurrency, reversal non-reuse, same-source provenance negatives, full
disposable `db-verify.sql` (all five dblink gates), core tests (29 files, 417
tests), core typecheck, web tests (72 files, 927 tests), and web build were
green. One first full web run hit a timing failure in an unchanged feed-media
test; the isolated test passed 8/8 and the complete rerun passed 927/927.

The independent read-only Sol review at `7489b64` marked the original
allocation, reversal, provenance, R key-order and citation findings addressed,
and confirmed the upgraded ACL ordering fix. It returned NO-GO only for fresh
immediate ACL, numeric-string acceptance, catalog ordering and durable
evidence. Commit `09a2bf6` closes those code/harness findings, and the checks
above are their observed rerun. These follow-ups do not alter the reviewed
design or risk profile, so the repository cost-discipline rule does not require
another model-to-model review loop.

This closes the local #153 implementation and review gate only. It does not
authorize a production database change, deployment, merge or push.

## Tasks 11–14 correction-round evidence (2026-09-03)

The owner-approved correction round is implemented through `df2d8ac`. Task 11
adds exact parent-person coverage at authorization, finalize, activation and
reversal; binds cutover authorization to the target batch identity, manifest
and preview; and establishes the observed lifecycle hierarchy as global v2
contract lock, unlocked source/profile discovery, profile advisory lock, then
post-lock mutable-row reads with tuple-drift rejection. The PostgreSQL-kernel
three-connection suite exercised begin/replay, batch result, reversal
authorization, name-completion finalize and activation. It also forced
discovery-tuple drift and proved that no authorization or batch state was
consumed on rejection.

Task 12 keeps the generic boundary strict while adapting only the pinned 1939
facade: the historic database-name string becomes canonical database identity,
the exact zero-valued `canonical_delta` count is removed, and the exact
three-field legacy name-completion token is enriched only inside the legacy R
adapter. Both legacy SQL and DBI paths passed without widening the generic
authorizer or generic R token contract.

Task 13 replaces coexistence `setval` with transactional `ALTER SEQUENCE ...
RESTART WITH`, makes the database CI job fetch the pinned historical commit and
verify it with `git cat-file` before `git show`, and replaces mutable line-range
inventory with unique semantic anchors and multiplicity-sensitive expected
rows. The adjacent #152 narrative inventory was updated only to recognize the
new thin facade and generic mutation owner. The sourced cutover verifier now
locates its own file through `sys.frames()` and retains direct-`Rscript`
fallback; this makes the repository's official `Rscript run-tests.R` runner
truthful without changing cutover semantics.

### Complete local disposable database gate

Every database below was local on `127.0.0.1:55441`, used
`PGUSER=johanreventlow` and `PGPASSWORD=''`, and reported PostgreSQL system
identifier `7680906716015365850`. No Supabase MCP or production endpoint was
used.

| Database | Observed result |
| --- | --- |
| `daa153_t14_freshv2_20260903c` | Fresh schema, migrations/RLS, generic and legacy writer/name suites, disposable `db-verify` and edition catalog all exited 0; contract v2. |
| `daa153_t14_upgv2_20260903e` | Exact `2d6aabf:schema.sql`, empty legacy fixture, migration/RLS and the same complete v2 gate all exited 0; contract v2. |
| `daa153_t14_terminal_20260903c` | Real activated/finalized and reversed/reversed historical chains; late failpoint and exact rollback proof, normal migration/RLS, terminal assertion and full C3 all passed; contract v1. Its attempted v2 bootstrap failed closed with `CUTOVER_INVENTORY_LIVE_DRIFT` as required. |
| `daa153_t14_coexist_20260903c` | Coexisting legacy and generic shells retained exact relation, sequence and contents state after the late failpoint; successful migration then allocated a default event ID above all migrated IDs; contract v1. |
| `daa153_t14_freshv1c3_20260903c` | Fresh v1 full C3 regression passed; contract v1. |

Fresh and clean-upgraded v2 catalog receipts were byte-identical: 33,466
bytes, SHA-256
`16704827d59af5012a2ab70940e549a9f7d679f44deaf4703bdad115438f9a0c`;
`cmp` exited 0. The eight negative migration fixtures also exited 0 as tests:
issued, open and finalized histories failed with
`REIMPORT_LEGACY_IN_FLIGHT_MIGRATION_BLOCKED`; orphan, wrong-status child,
broken result, ambiguous child and wrong source-record topology failed with the
same topology token; wrong-source and multi-source identities failed with
`REIMPORT_WRITER_LEGACY_SOURCE_IDENTITY_INVALID`. Each rejection retained the
legacy authorization relation as a physical table.

Two setup deviations were diagnosed rather than treated as product evidence:
one earlier upgraded-v2 rehearsal applied the terminal assertion to the empty
fixture, and one earlier shell loop created a disposable database with a
literal variable name. Correctly orchestrated, newly named runs above passed.
An initial legacy DBI fixture omitted the required v2 bootstrap and correctly
failed closed; the corrected fixture passed.

### Gateway and application gate

The following local DBI integrations exited 0:

- generic writer on `daa153_t14_rwriter_20260903`;
- 1939 production writer on `daa153_t14_rlegacy2_20260903`;
- 1939 name completion on `daa153_t14_rname_20260903`;
- generic writer concurrency on `daa153_t14_rlock_20260903`; and
- C3/global-lock ordering on `daa1939_t14_c3lock_20260903`, including all 12
  scenarios and their power controls.

The five focused R suites for generic/legacy reimport, generic/legacy name
completion and writer inventory passed. The adjacent #152 narrative inventory
passed 1,482 expectations and the #153 inventory passed 230. The official full
R runner exited 0 with
`[ FAIL 0 | WARN 14 | SKIP 1 | PASS 2773 ]`; the single skip is the explicit
local-DB smoke condition in `test-load-daa.R`, and the warnings are known
runner-path/stringi diagnostics rather than failed assertions. A separate,
non-official direct `testthat::test_dir` invocation exposed a pre-existing
preview wrapper assumption about `--file`; it is outside this correction and
does not affect the green repository runner.

`npm run test -w @daa/core` passed 29 files and 417 tests, and
`npm run typecheck -w @daa/core` exited 0. With test-only dummy Vite variables,
`npm run test -w web` passed 72 files and 927 tests, and `npm run build -w web`
exited 0 with only the existing chunk-size warning. `git diff --check
2d6aabf..df2d8ac` exited 0.

### Codex self-review

The complete `2d6aabf..df2d8ac` range was reviewed against the issue mission,
design §§1–6, all correction findings and the task-ledger rulings. The review
found the permanent mechanism remains generic and profile-bound; the retained
`_1939` objects are the explicit one-version facade/C3 allowlist; the generic
v2 mutation contract is not weakened; every corrected authorization,
concurrency, migration and inventory boundary has a negative test; and fresh
and upgrade definitions converge by byte-comparable catalog evidence. No new
actionable finding was identified. The final independent read-only Sol xhigh
review remains the only incomplete Task 14 gate at this checkpoint.

This evidence is local code-integration evidence only. It is not production
authorization and involved no production database change, network service,
push, merge, deploy, Fable, protected review artifact or `work/` access.
