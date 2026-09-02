# Task 5 implementer report

Status: **INCOMPLETE — unit-level implementation is GREEN; the required
existing DBI integration remains RED.** No commit, push, merge, deploy, or
production database was used. `work/` and protected review artifacts were not
read or modified.

## Scope and changed files

Only the Task 5-declared R helpers/CLIs and testthat files were changed:

- Added generic reimport and name-completion helpers and CLIs.
- Reduced the four 1939 files to legacy manifest/flag validation, a pinned
  profile envelope, and delegation to generic helpers. Their source contains
  no `DBI::`, `RPostgres::`, or `red_*1939_v50` call.
- Added generic manifest/gateway testthat coverage and adapted the two legacy
  testthat entry points to assert the pinned profile and absence of direct
  database/legacy-RPC gateways.

The generic helpers validate source/profile/hash identity, SHA/UUID format,
operation/count identity, preflight actor, database identity, read-write
transaction state, and payload count. Their DBI implementations use parameter
binding and idempotent rollback/commit cleanup. The 1939 reimport adapter also
normalizes the historical injected test-gateway protocol into the generic
preflight protocol; production CLI traffic uses the generic DBI gateway.

## TDD evidence

RED (first corrected test path):

```bash
Rscript -e 'testthat::test_file("tests/testthat/test-apply-reimport.R")'
Rscript -e 'testthat::test_file("tests/testthat/test-apply-name-completion.R")'
```

Both failed because the new generic helper files did not exist. An initial
testthat-relative source path was corrected before implementation; the
recorded expected RED was then the missing files at the repository helper
paths.

GREEN:

```bash
Rscript -e 'testthat::test_file("tests/testthat/test-apply-reimport.R")'
Rscript -e 'testthat::test_file("tests/testthat/test-apply-name-completion.R")'
Rscript -e 'testthat::test_file("tests/testthat/test-apply-reimport-1939-v50.R")'
Rscript -e 'testthat::test_file("tests/testthat/test-apply-name-completion-1939-v50.R")'
```

All four files are green (10 + 10 + 6 + 6 passing expectations). R parsing of
all eight helper/CLI files is green, and `git diff --check` is green.

## Local disposable integration attempt

I created only `daa_153_task5_disposable` locally and loaded the CI-equivalent
test fixture/schema/RLS/1939 writer fixture/v2 fixture. The connection used
all five explicit PG variables:

```bash
PGHOST=/tmp PGPORT=5432 PGDATABASE=daa_153_task5_disposable \
PGUSER=johanreventlow PGPASSWORD='' \
Rscript tests/integration/test-1939-v50-production-writer.R
```

The first execution exposed the old injected gateway protocol mismatch and
left partial fixture state; I deleted and recreated precisely that disposable
database, then reran with the adapter normalization. The clean rerun reached
the legacy SQL facade but failed:

```text
REIMPORT_1939_AUTHORIZATION_INVALID
CONTEXT: red_authorize_1939_v50_reimport(...)
```

This is an existing integration fixture/legacy-facade authorization contract
failure after the generic R boundary, not a production or environmental
failure. I did not modify `tests/integration/test-1939-v50-production-writer.R`
because it is outside Task 5's declared allowlist. The required
name-completion DBI integration was therefore not run, to avoid interpreting
or changing an additional undeclared fixture after this unresolved boundary.

## Remaining issue / requested next authority

No GO is justified until the existing R integrations run green against the
disposable v2 database. If repair is desired, authorize inspection and a
narrow modification of `tests/integration/test-1939-v50-production-writer.R`
(and possibly `tests/integration/test-1939-v50-name-completion.R`) so their
hand-built gateways exercise the generic RPC protocol instead of the retired
legacy gateway protocol. No source/schema/production change is currently
requested or made.

## Fix round 1 — generic integration protocol (2026-09-02)

Status: **GREEN.** The authorized narrow integration-test scope was used; no
schema, migration, RLS, production database, `work/`, or protected review
artifact was read or changed. This report will be included in the Task 5
commit, but no push, merge, or deploy was performed.

### Root cause and repair

The production-writer fixture had hand-built gateway and direct setup calls to
`red_authorize_1939_v50_reimport`, followed by a Task 5 generic gateway call
to `red_begin_reimport`. The legacy authorization is intentionally not valid
for generic begin, producing `REIMPORT_1939_AUTHORIZATION_INVALID`.

The fixture now creates its test writer profile and uses only the generic
authorization/begin/apply protocol at the R gateway boundary. Its explicit
legacy name-completion, cutover, and reversal facade assertions remain where
they test the compatibility facade itself. The name-completion integration
likewise uses generic authorization for its generic R gateway boundary while
retaining its explicit legacy permission/reversal facade coverage.

Disposable runs also exposed three real Task 5 generic-helper defects, all
fixed with RED evidence before the corresponding GREEN run:

- RPostgres rejects `params = list()` for parameterless SQL; gateway query and
  execute helpers now omit `params` when empty.
- Generic reimport must project `canonical_delta` out of the SQL writer count
  object, clear the per-record change-set after each person write, and detect
  a finalized generic batch before replaying writes. A unit test covers the
  finalized-batch path.
- The legacy name-completion helper originally shadowed generic validation
  symbols after sourcing its generic helper. Generic validators now have
  distinct names, and the generic preflight preserves the public RPC's
  database identity and caller-provided manifest-byte hash.

### Changed files

Task 5 source/test files:

- `.claude/skills/daa-extract/scripts/apply_reimport_helpers.R`
- `.claude/skills/daa-extract/scripts/apply_reimport.R`
- `.claude/skills/daa-extract/scripts/apply_name_completion_helpers.R`
- `.claude/skills/daa-extract/scripts/apply_name_completion.R`
- `.claude/skills/daa-extract/scripts/apply_reimport_1939_v50_helpers.R`
- `.claude/skills/daa-extract/scripts/apply_reimport_1939_v50.R`
- `.claude/skills/daa-extract/scripts/apply_name_completion_1939_v50_helpers.R`
- `.claude/skills/daa-extract/scripts/apply_name_completion_1939_v50.R`
- `tests/testthat/test-apply-reimport.R`
- `tests/testthat/test-apply-name-completion.R`
- `tests/testthat/test-apply-reimport-1939-v50.R`
- `tests/testthat/test-apply-name-completion-1939-v50.R`

Authorized integration fixtures:

- `tests/integration/test-1939-v50-production-writer.R`
- `tests/integration/test-1939-v50-name-completion.R`

### Commands and results

RED evidence included the thin-adapter test after adding its assertion:

```bash
Rscript -e 'testthat::test_file("tests/testthat/test-apply-reimport-1939-v50.R")'
```

It failed because `legacy_reimport_gateway_adapter` was still present. Removing
that normalizer made the same test GREEN. The first generic integration runs
then recorded the DBI empty-parameter, profile, foreign-change-set, writer
count, replay, and generic-name preflight failures above; each was rerun after
its smallest in-scope fix.

Final Task 5 testthat command (all GREEN):

```bash
for test_file in tests/testthat/test-apply-reimport.R tests/testthat/test-apply-name-completion.R tests/testthat/test-apply-reimport-1939-v50.R tests/testthat/test-apply-name-completion-1939-v50.R; do Rscript -e "testthat::test_file('$test_file')" || exit 1; done
```

The files passed with 14, 10, 8, and 6 expectations respectively. All eight
Task 5 helper/CLI files parsed, `git diff --check` passed, and the static scan
of the four 1939 adapter/CLI files found no `DBI::`, `RPostgres::`, or
`red_*1939_v50` direct calls.

Each integration used the complete explicit disposable environment:

```bash
PGHOST=/tmp PGPORT=5432 PGDATABASE=daa_153_task5_disposable PGUSER=johanreventlow PGPASSWORD='' Rscript tests/integration/test-1939-v50-production-writer.R
PGHOST=/tmp PGPORT=5432 PGDATABASE=daa_153_task5_disposable PGUSER=johanreventlow PGPASSWORD='' Rscript tests/integration/test-1939-v50-name-completion.R
```

Both ended with their respective `PASS DAA 1939 v50 ... PostgreSQL
integration` marker after rebuilding only `daa_153_task5_disposable` from
`tests/sql/evidence-promotion-bootstrap.sql`, `schema.sql`, `db-rls.sql`,
`tests/sql/1939-v50-writer-bootstrap.sql`, and
`tests/sql/reimport-writer-v2-bootstrap.sql`.

### Self-review and remaining concern

The adapters retain legacy manifest/flag validation and supply only the pinned
source/profile/hash envelope; database writes occur in generic helper
gateways via parameter-bound generic public RPCs. The integration fixtures
use synthetic identifiers and local disposable state only; no artifact text,
credentials, production identity, or `work/` content was emitted.

The remaining concern is architectural rather than a current failing test:
generic replay lookup reads the generic private batch/event tables because the
public begin RPC returns only a UUID. This is still profile-bound, local to the
generic gateway, and has explicit replay coverage; adding a public replay
status RPC would remove that read-side coupling in a future, separately scoped
database task.

## Fix round 1 — public generic replay receipt

Root cause: the generic DBI gateway read `private.reimport_batch` after begin
and `private.reimport_event` for replay maps. Those reads contradict the
private-ledger ACL. The initial RED was
`Rscript -e 'testthat::test_file("tests/testthat/test-apply-reimport.R")'`:
the revised finalized-replay test failed `unexpected gateway operation`; the
schema RED was `psql -v ON_ERROR_STOP=1 -f tests/sql/test-reimport-writer.sql`,
which stopped with `REIMPORT_WRITER_RPC_MISSING:
public.red_reimport_batch_result(uuid,uuid)`.

GREEN implementation adds authenticated-only, security-definer
`public.red_reimport_batch_result(uuid,uuid)` in fresh schema and the atomic
migration. It contract-gates before ledger access; validates consumed reimport
authorization/current editor and all profile/source/manifest/preview bindings;
returns only batch id/status/server-side replay flag/person map; and fails
closed for malformed/open/finalized state. The R gateway uses that RPC after
begin, validates the exact response shape, and has no `private.reimport_*`
SQL. The unreachable legacy name-completion executor and its old authorization
and preflight helpers were removed; the retained legacy facade adapter only
converts its pinned manifest to the generic helper.

GREEN commands/results (all five PG variables were set for each database/R
command, using only `daa_153_task5_disposable`):

```bash
Rscript -e 'testthat::test_file("tests/testthat/test-apply-reimport.R")'
for test_file in tests/testthat/test-apply-reimport.R tests/testthat/test-apply-name-completion.R tests/testthat/test-apply-reimport-1939-v50.R tests/testthat/test-apply-name-completion-1939-v50.R; do Rscript -e "testthat::test_file('$test_file')" || exit 1; done
PGHOST=/tmp PGPORT=5432 PGDATABASE=daa_153_task5_disposable PGUSER=johanreventlow PGPASSWORD='' Rscript tests/integration/test-1939-v50-production-writer.R
PGHOST=/tmp PGPORT=5432 PGDATABASE=daa_153_task5_disposable PGUSER=johanreventlow PGPASSWORD='' Rscript tests/integration/test-1939-v50-name-completion.R
```

The unit suite passed 16/10/8/6 expectations; both integrations printed their
`PASS` marker. The production-writer integration records the real emitted DBI
SQL, requires the public result RPC and rejects any private-ledger query. It
uses `service_role` only to authorize, checks authenticated generic begin/result
on an open batch, then proves initial apply and authenticated finalized replay.
Fresh schema SQL writer and clean schema+migration+RLS completed; the new
`db-verify.sql` check printed its `OK` notice. The full verifier later stopped
at its unrelated local `DB_VERIFY_DBLINK_REQUIRED` prerequisite.

Changed files are the Task 5 helpers, schema/migration/RLS/verifier, writer
SQL/catalog/migration tests, the authorized production-writer integration, the
Task 5 reimport unit test, and the controller-amended Task 5 plan. Self-review:
no `work/` or protected artifact was read/changed; no production DB, push,
merge, or deployment occurred; no payload/history is exposed by the new RPC;
all ledger tables remain revoked from anon/authenticated/service_role.

Additional strict-validation RED/GREEN: the malformed two-status response test
first produced `length = 2 in coercion to logical(1)`; after requiring a
single non-missing character status it passes with
`REIMPORT_BATCH_RESULT_INVALID`. The final fresh SQL writer regression also
completed with `ROLLBACK` and no error after loading the disposable bootstrap,
schema, RLS, writer fixture, and `test-reimport-writer.sql`.
