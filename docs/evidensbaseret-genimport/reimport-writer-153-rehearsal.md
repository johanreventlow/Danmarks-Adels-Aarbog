# #153 generalized reimport-writer: disposable rehearsal

**Observed:** 2026-09-02
**Code commits exercised:** `92d71dc`, `3af0986`, `13cf3a4`, `ab7b92e`, and
`b5dd0da` (catalog allowlist)
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
updates. This is still local code-integration evidence only, not production
authority or a replacement for the remaining Task 8 migration/parity and
independent-review steps.
