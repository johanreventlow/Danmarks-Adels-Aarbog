# #153 generalized reimport-writer: disposable rehearsal

**Observed:** 2026-09-02
**Code commit exercised:** `92d71dc45f137abb7048a852eeea20e1594ed42c`
(`test: harden edition catalog gate`)
**Result:** **INCOMPLETE / NO-GO for #153 code-integration evidence.**

This is a bounded local rehearsal, not a production authorization. No
production database, push, merge, deploy or network action was used; no
`work/` or protected review artifact was accessed. Every connection below set
all five local disposable variables together:

```bash
PGHOST=127.0.0.1 PGPORT=55441 PGDATABASE=<named-db> PGUSER=johanreventlow PGPASSWORD=''
```

`dblink` was available in this local PostgreSQL 17 setup. The exact failure
below prevents a green §6 conclusion even though the other listed observations
are green.

## Fresh-install observations

The v1 baseline database was `daa153_t7_freshbase_20260902`. Its setup
completed with exit 0:

```bash
PGHOST=127.0.0.1 PGPORT=55441 PGDATABASE=daa153_t7_freshbase_20260902 PGUSER=johanreventlow PGPASSWORD='' \
  /opt/homebrew/opt/postgresql@17/bin/psql -X -v ON_ERROR_STOP=1 -f tests/sql/evidence-promotion-bootstrap.sql
PGHOST=127.0.0.1 PGPORT=55441 PGDATABASE=daa153_t7_freshbase_20260902 PGUSER=johanreventlow PGPASSWORD='' \
  /opt/homebrew/opt/postgresql@17/bin/psql -X -v ON_ERROR_STOP=1 -c 'CREATE EXTENSION IF NOT EXISTS dblink'
PGHOST=127.0.0.1 PGPORT=55441 PGDATABASE=daa153_t7_freshbase_20260902 PGUSER=johanreventlow PGPASSWORD='' \
  /opt/homebrew/opt/postgresql@17/bin/psql -X -v ON_ERROR_STOP=1 -f schema.sql
PGHOST=127.0.0.1 PGPORT=55441 PGDATABASE=daa153_t7_freshbase_20260902 PGUSER=johanreventlow PGPASSWORD='' \
  /opt/homebrew/opt/postgresql@17/bin/psql -X -v ON_ERROR_STOP=1 -f db-migrations.sql
PGHOST=127.0.0.1 PGPORT=55441 PGDATABASE=daa153_t7_freshbase_20260902 PGUSER=johanreventlow PGPASSWORD='' \
  /opt/homebrew/opt/postgresql@17/bin/psql -X -v ON_ERROR_STOP=1 -f db-rls.sql
```

On that baseline, each of the following returned exit 0 in this order:

```bash
PGHOST=127.0.0.1 PGPORT=55441 PGDATABASE=daa153_t7_freshbase_20260902 PGUSER=johanreventlow PGPASSWORD='' /opt/homebrew/opt/postgresql@17/bin/psql -X -v ON_ERROR_STOP=1 -f tests/sql/test-reimport-writer.sql
PGHOST=127.0.0.1 PGPORT=55441 PGDATABASE=daa153_t7_freshbase_20260902 PGUSER=johanreventlow PGPASSWORD='' /opt/homebrew/opt/postgresql@17/bin/psql -X -v ON_ERROR_STOP=1 -f tests/sql/test-reimport-name-completion.sql
PGHOST=127.0.0.1 PGPORT=55441 PGDATABASE=daa153_t7_freshbase_20260902 PGUSER=johanreventlow PGPASSWORD='' /opt/homebrew/opt/postgresql@17/bin/psql -X -v ON_ERROR_STOP=1 -f tests/sql/test-1939-v50-production-writer.sql
PGHOST=127.0.0.1 PGPORT=55441 PGDATABASE=daa153_t7_freshbase_20260902 PGUSER=johanreventlow PGPASSWORD='' /opt/homebrew/opt/postgresql@17/bin/psql -X -v ON_ERROR_STOP=1 -f tests/sql/test-1939-v50-name-completion.sql
```

The required v2/canonical-catalog run used the separately named fresh database
`daa153_t7_fresh_20260902`. Bootstrap through schema, migrations and RLS, the
following v2 bootstrap, and the repeated `db-rls.sql` each returned exit 0:

```bash
PGHOST=127.0.0.1 PGPORT=55441 PGDATABASE=daa153_t7_fresh_20260902 PGUSER=johanreventlow PGPASSWORD='' /opt/homebrew/opt/postgresql@17/bin/psql -X -v ON_ERROR_STOP=1 -f tests/sql/reimport-writer-v2-bootstrap.sql
PGHOST=127.0.0.1 PGPORT=55441 PGDATABASE=daa153_t7_fresh_20260902 PGUSER=johanreventlow PGPASSWORD='' /opt/homebrew/opt/postgresql@17/bin/psql -X -v ON_ERROR_STOP=1 -f db-rls.sql
PGHOST=127.0.0.1 PGPORT=55441 PGDATABASE=daa153_t7_fresh_20260902 PGUSER=johanreventlow PGPASSWORD='' /opt/homebrew/opt/postgresql@17/bin/psql -X -v ON_ERROR_STOP=1 -f tests/sql/run-db-verify-disposable.sql
PGHOST=127.0.0.1 PGPORT=55441 PGDATABASE=daa153_t7_fresh_20260902 PGUSER=johanreventlow PGPASSWORD='' /opt/homebrew/opt/postgresql@17/bin/psql -X -v ON_ERROR_STOP=1 -f tests/sql/test-reimport-edition-catalog.sql
```

Both final tests returned exit 0; the verifier reported all five `dblink`
concurrency gates executed. It also retained its pre-existing non-#153
`SPRINGER OVER Task 12b (storage.objects...)` skip, so this is not presented
as a no-skip verification of unrelated storage checks. The catalog test must
follow `run-db-verify-disposable.sql`, which defines its assertion helper.

### C3 regression blocker

On the fresh v1 baseline, the real unchanged C3 regression returned **exit 3**:

```bash
PGHOST=127.0.0.1 PGPORT=55441 PGDATABASE=daa153_t7_c3base_20260902 PGUSER=johanreventlow PGPASSWORD='' \
  /opt/homebrew/opt/postgresql@17/bin/psql -X -v ON_ERROR_STOP=1 -f tests/sql/test-1939-v50-c3-apply.sql
```

It passed the catalog checks through Task 6, then stopped at
`tests/sql/test-1939-v50-c3-apply.sql:1725` with:

```text
ERROR: function private.require_reimport_1939_editor() does not exist
CONTEXT: PL/pgSQL function red_preview_reimport_cases(bigint,text,jsonb) line 7
```

`db-migrations.sql` drops that helper at line 11937 while the C3 façade still
calls it at line 9407. This is an observed behavior regression, not a waived
test. At contract v2 the C3 ACL probe was additionally fail-closed, as
expected for the #152 transition; that does not cure the v1 regression above.

## Upgraded-install and catalog parity

The separate upgraded database was `daa153_t7_upgraded_20260902`. It was
bootstrapped, then seeded from the historical schema and a disposable terminal
legacy fixture, and upgraded as follows (each command returned exit 0):

```bash
PGHOST=127.0.0.1 PGPORT=55441 PGDATABASE=daa153_t7_upgraded_20260902 PGUSER=johanreventlow PGPASSWORD='' /opt/homebrew/opt/postgresql@17/bin/psql -X -v ON_ERROR_STOP=1 -f tests/sql/evidence-promotion-bootstrap.sql
git show 2d6aabf:schema.sql | PGHOST=127.0.0.1 PGPORT=55441 PGDATABASE=daa153_t7_upgraded_20260902 PGUSER=johanreventlow PGPASSWORD='' /opt/homebrew/opt/postgresql@17/bin/psql -X -v ON_ERROR_STOP=1
PGHOST=127.0.0.1 PGPORT=55441 PGDATABASE=daa153_t7_upgraded_20260902 PGUSER=johanreventlow PGPASSWORD='' /opt/homebrew/opt/postgresql@17/bin/psql -X -v ON_ERROR_STOP=1 -f /private/tmp/daa153-task7-upgrade-terminal-fixture.sql
PGHOST=127.0.0.1 PGPORT=55441 PGDATABASE=daa153_t7_upgraded_20260902 PGUSER=johanreventlow PGPASSWORD='' /opt/homebrew/opt/postgresql@17/bin/psql -X -v ON_ERROR_STOP=1 -f db-migrations.sql
PGHOST=127.0.0.1 PGPORT=55441 PGDATABASE=daa153_t7_upgraded_20260902 PGUSER=johanreventlow PGPASSWORD='' /opt/homebrew/opt/postgresql@17/bin/psql -X -v ON_ERROR_STOP=1 -f db-rls.sql
PGHOST=127.0.0.1 PGPORT=55441 PGDATABASE=daa153_t7_upgraded_20260902 PGUSER=johanreventlow PGPASSWORD='' /opt/homebrew/opt/postgresql@17/bin/psql -X -v ON_ERROR_STOP=1 -f tests/sql/test-reimport-writer-migration.sql
```

The upgraded generic writer, generic name-completion, both legacy SQL suites,
`run-db-verify-disposable.sql`, and `test-reimport-edition-catalog.sql` each
returned exit 0. Canonical inspection was run separately on the two final
databases and compared byte-for-byte:

```bash
PGHOST=127.0.0.1 PGPORT=55441 PGDATABASE=daa153_t7_fresh_20260902 PGUSER=johanreventlow PGPASSWORD='' /opt/homebrew/opt/postgresql@17/bin/psql -X -At -f tests/sql/inspect-reimport-writer-catalog.sql > /private/tmp/daa153-t7-fresh-catalog.json
PGHOST=127.0.0.1 PGPORT=55441 PGDATABASE=daa153_t7_upgraded_20260902 PGUSER=johanreventlow PGPASSWORD='' /opt/homebrew/opt/postgresql@17/bin/psql -X -At -f tests/sql/inspect-reimport-writer-catalog.sql > /private/tmp/daa153-t7-upgraded-catalog.json
cmp /private/tmp/daa153-t7-fresh-catalog.json /private/tmp/daa153-t7-upgraded-catalog.json
shasum -a 256 /private/tmp/daa153-t7-fresh-catalog.json /private/tmp/daa153-t7-upgraded-catalog.json
```

All four commands returned exit 0. Both files were 27,142 bytes and had SHA-256
`5a7211fd91050e27bdaf4102bad7f36f5a18daeba9058e2591adea42eed66ab1`.

## R and concurrency observations

The generic and legacy unit suites all returned exit 0:

```bash
for test_file in tests/testthat/test-apply-reimport.R tests/testthat/test-apply-name-completion.R tests/testthat/test-apply-reimport-1939-v50.R tests/testthat/test-apply-name-completion-1939-v50.R tests/testthat/test-reimport-writer-source-inventory.R; do Rscript -e "testthat::test_file('$test_file')" || exit 1; done
```

They reported respectively 16, 10, 7, 6 and 105 passing expectations. The
inventory plus catalog gate supports the generic-primary/explicit-legacy
allowlist check. The SQL flows cover the two-profile, same-profile equal-hash,
activation, reversal and cross-profile rejection cases; they also assert v2
event-backed narrative/publication receipts.

On separately clean local databases, both available DBI integrations returned
exit 0:

```bash
PGHOST=127.0.0.1 PGPORT=55441 PGDATABASE=daa153_t7_rprodclean_20260902 PGUSER=johanreventlow PGPASSWORD='' Rscript tests/integration/test-1939-v50-production-writer.R
PGHOST=127.0.0.1 PGPORT=55441 PGDATABASE=daa153_t7_rname_20260902 PGUSER=johanreventlow PGPASSWORD='' Rscript tests/integration/test-1939-v50-name-completion.R
```

The production-writer integration printed `PASS DAA 1939 v50 PostgreSQL
integration` and exercises the approved replay-result RPC
`public.red_reimport_batch_result`: it reads the open result and verifies the
replay result (`already_applied`) through that RPC. The name-completion
integration printed `PASS DAA 1939 v50 name completion PostgreSQL integration`.

`tests/integration/test-reimport-writer.R`, explicitly required by Task 7,
does not exist at this commit. Therefore the requested standalone DBI proof of
two-profile equal-hash separation, rollback cleanup, unauthorised rejection,
and cross-profile reversal/activation cannot be claimed from that named test.
The legacy production R test also initially collided with an already-seeded
profile on `daa153_t7_rprod_20260902`; its clean rerun above is the valid
observation, and the collision is a test-order/setup limitation rather than a
writer pass.

## Self-review against §1 and §6

| Requirement | Observed evidence | Status |
| --- | --- | --- |
| Generic permanent primaries; profile-bound, edition-neutral core | fresh/upgraded generic SQL, catalog gate, source-inventory (105 expectations) | observed green |
| Generic v2 event-backed writer and result-RPC replay | generic SQL v2 receipts; clean DBI production-writer integration and `red_reimport_batch_result` replay | observed green |
| Two profiles, equal hashes, lifecycle and profile isolation | generic SQL writer/name-completion flows, including same-profile and cross-profile reversal checks | observed green at SQL level |
| Exact 1939 transition façades | both legacy SQL suites and two legacy DBI integrations | observed green for writer/name façades |
| Fresh/upgraded installation parity and catalog gate | migration test, two full disposable verifier runs, catalog test, byte-identical catalog | observed green |
| C3 behavior unchanged | reproducible v1 C3 failure: missing private role helper | **failed** |
| Named generic DBI integration demanded by Task 7 | file absent at tested commit | **not run** |
| Boundary preservation | only named local DBs; no production/push/merge/deploy/network; no `work/`/protected artifact access | observed within this rehearsal |

`git diff --check 92d71dc45f137abb7048a852eeea20e1594ed42c..HEAD` returned exit 0
before this documentation-only evidence change. The self-review does **not**
confirm §6 as a whole because C3 is a required invariant and the named generic
DBI integration is missing.

## Required next review and disposition

Before any integration claim, resolve or explicitly reject the C3 helper
regression, add/restore and run the required generic DBI integration, rerun
the affected fresh evidence, then have the controller request one independent
read-only GPT-5.6-Sol review. The reviewer package should inspect the final
diff, `db-migrations.sql:9407` and `:11937`, this rehearsal, the generic SQL
tests, and the R replay-result path. The reviewer must not modify files. This
report itself grants no production authority.

## Corrective round (2026-09-02, commit `3af0986`)

The original red evidence was preserved: the missing generic integration exited
2, and the new upgraded-C3 helper/ACL gate exited 3 with
`C3_APPLY_PRIVATE_HELPER_TRANSITION_DRIFT`. The migration now retains exactly
`private.require_reimport_1939_editor()` and
`private.reimport_1939_canonical_json_sha256(jsonb)` while continuing to
remove the obsolete 1939 writer helpers. The C3 SQL regression now contains
the explicit existence-and-revocation gate.

On the named local disposable upgraded database
`daa153_t7_c3upgraded_20260902`, constructed from `2d6aabf:schema.sql`, the
following all-five-variable migration/RLS commands returned exit 0 before C3:

```bash
env PGHOST=127.0.0.1 PGPORT=55441 PGDATABASE=daa153_t7_c3upgraded_20260902 PGUSER=johanreventlow PGPASSWORD='' /opt/homebrew/opt/postgresql@17/bin/psql -X -v ON_ERROR_STOP=1 -f db-migrations.sql
env PGHOST=127.0.0.1 PGPORT=55441 PGDATABASE=daa153_t7_c3upgraded_20260902 PGUSER=johanreventlow PGPASSWORD='' /opt/homebrew/opt/postgresql@17/bin/psql -X -v ON_ERROR_STOP=1 -f db-rls.sql
```

The updated C3 test passed its new helper/ACL catalog gate and reached the
real preview path, proving the undefined-helper regression is removed. It then
exited 3 at the later existing Task 6 assertion with `permission denied for
schema auth` while executing `auth.uid()` under `service_role`. This is a
separate C3 test/runtime permission blocker; it is not repaired here because
the approved corrective scope is limited to retaining the two private helpers.
Consequently full C3, fresh/upgraded `cmp`, catalog and full concurrency
reruns are still **not green** in this corrective round.

The required generic DBI file now exists. On the named local v2 disposable
database `daa153_t7_corrected2_20260902`, this command returned exit 0:

```bash
env PGHOST=127.0.0.1 PGPORT=55441 PGDATABASE=daa153_t7_corrected2_20260902 PGUSER=johanreventlow PGPASSWORD='' Rscript tests/integration/test-reimport-writer.R
```

It directly exercises generic authorization/begin/finalize, equal-hash
separation for two synthetic source/profile identities, rollback cleanup,
unauthorised rejection and cross-profile reversal/activation rejection. It
checks the v2 event-backed person-create implementation contract, but does
**not** yet execute a successful person-create/name-completion lifecycle.
Thus it does not fully discharge Task 7's required actual narrative-creation
proof. Its output ends `PASS generic reimport writer DBI integration`
(RPostgres emitted non-fatal open-result warnings). This positive partial DBI
observation does not upgrade the overall NO-GO.
