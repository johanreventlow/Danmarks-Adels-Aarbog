# DAA 1939 v50 name completion — production readiness

Dato: 2026-08-18. Commit under review: `22021cc` plus name-completion
implementation range `69f45b3..22021cc`.

## Verdict and stop gate

**GO for preparing a future, explicitly authorized, single production
name-completion apply.** There is no unresolved P0/P1 or concrete contract
mismatch in the tested scope.

This is **not** an apply authorization and **not** a cutover authorization.
Task 7 created no production authorization, called no production writer and
performed no cutover. Before any future write, a new local production backup
must be created, verified and named with exact path, SHA-256 and mode in a new
user approval. Cutover remains a later, separately reviewed operation.

## Locked production boundary

- Database: `postgres`; cluster system identifier
  `7642734024280108049`.
- Original finalized batch:
  `560c39f8-5c87-4c0d-a768-025d97fa2974`.
- Original consumed authorization:
  `1086cce9-f713-4bf3-9d8f-41ab19094bf0`.
- Original manifest byte SHA-256:
  `8417b6deeaf32b3cf39a4f2995a06211f8368172dfa97a188e03c6f7ef379a1f`.
- Original manifest content SHA-256:
  `8c6a9f56af7f1e75e1b961f561cc2118478ac4d9e08f838c9e5279938c545f03`.
- Original journal: exactly 305 `source_evidence` and 8 `person_create`
  events; no original canonical delta.
- Task 6 read-only audit: eight persons 1846–1853 remain staged, with null
  name caches, zero name facts and zero cutover authorizations.

The original production manifest was re-hashed during Task 7 and remains
byte-identical at the locked SHA-256 above.

## Locked completion artifact

- `name-completion-manifest-v1.json` byte SHA-256:
  `4ea983b8ea7c630d1b24487b58b7e000902d2a5202bdf397a630270f4ed48ea3`.
- Embedded content SHA-256:
  `e3cd22807839a7f1425ca266ea18cd841007f179bc1f4093a2d05519611706be`.
- Post-apply audit SHA-256:
  `f8455f54379619e9dfdfc71d03128f2cc51f3f184260d415113655339c049cba`.
- Original apply artifact SHA-256:
  `4c36bc0088189d60aee85cc6bc058adc4244032204ffb0125312aa7467eb1d72`.
- Manifest flags: `production_authorized=false`,
  `cutover_authorized=false`.

An exclusive rebuild from the three locked inputs was byte-identical (`cmp`
exit 0). A separate cross-artifact `jq -e` audit returned `true`: all eight
element IDs, persons, record keys and personas are unique, and each operation's
person ID, name, page, source span, verbatim text/hash and persona match the
original person-create row, committed apply map and read-only post-apply audit.

| Person | Source record | Page | Authorized name |
|---:|---|---:|---|
| 1846 | `record-3766faae-ae21-412a-8cfb-745a19ac77f0` | 503 | Ditlev |
| 1847 | `record-43d4974a-0532-421d-a3fb-8e7c575a67e7` | 506 | Gerhard (Gherardus de Reventlow) |
| 1848 | `record-80180a6e-2cc6-4968-81ca-004b6662d8ce` | 506 | Henning |
| 1849 | `record-89a932c8-7b52-4f5c-9e00-0f2b62ee4422` | 508 | Henning Reventlow |
| 1850 | `record-8f346104-cf3c-465f-bfa3-efb78be436b2` | 506 | Iven (Ywanus de Reuentlo) |
| 1851 | `record-a1f4547d-16cc-4110-ad1b-fa3ff1c59a58` | 508 | Henning |
| 1852 | `record-b626f5ff-f2fb-4061-bfce-988dbddec846` | 506 | Henrik |
| 1853 | `record-c731fc5a-7e4c-45b8-9bfc-d6eba9f62e5d` | 517 | Margrethe |

## Expected production delta

Exactly one child name-completion authorization/batch may be consumed and
finalized. It must create exactly 8 name facts, 8 immutable selected
assertions, 8 source-3 citations, 8 conclusions, 8 append-only result links
and 8 append-only `canonical_delta` events. The conclusion trigger derives the
eight exact `visning_navn` values above. All eight persons remain
`staged=true`.

Expected zero delta: person creation, activation, external IDs, relations,
families, family members and non-name canonical facts. The original batch,
authorization, 313 events and source/provenance rows remain immutable.

## Fresh full-suite evidence

Python, from `.claude/skills/daa-extract/scripts`:

```text
/usr/bin/python3 -m pytest -q
1710 passed, 3 skipped in 9.42s
```

R, from repository root:

```text
Rscript run-tests.R
[ FAIL 0 | WARN 1 | SKIP 2 | PASS 811 ]
```

The one warning is transparent and non-blocking: while the name-completion
wrapper ran under `run-tests.R`, its sourced direct script attempted
`normalizePath("run-tests.R")` and warned that the relative path did not exist
from the temporary working directory. The wrapper was executed and counted;
the same run printed `PASS 63 assertions`, and the independent real DBI test
below passed. No name-completion test was skipped.

## Fresh PostgreSQL 17 evidence

All tests used local PostgreSQL `17.10` with system identifier
`7657242220770903427`, distinct from production. Disposable databases:

- `daa1939_name_completion_task7_schema_20260818`
- `daa1939_name_completion_task7_migration_20260818`
- `daa1939_name_completion_task7_writer_20260818`
- `daa1939_name_completion_task7_integration_20260818`

Schema path commands:

```text
createdb daa1939_name_completion_task7_schema_20260818
psql -X -v ON_ERROR_STOP=1 -d <db> -f tests/sql/evidence-promotion-bootstrap.sql
psql -X -v ON_ERROR_STOP=1 -d <db> -f schema.sql
psql -X -v ON_ERROR_STOP=1 -d <db> -f db-rls.sql
psql -X -v ON_ERROR_STOP=1 -d <db> -f tests/sql/1939-v50-writer-bootstrap.sql
psql -X -v ON_ERROR_STOP=1 -d <db> -f tests/sql/test-1939-v50-name-completion.sql
```

Result: exit 0, five `DO` blocks. The notice cancelling the deliberately
blocked dblink mutation is expected by the two-session lock test.

Append-only migration path commands:

```text
git show 312eaa4:schema.sql > /tmp/daa1939_task7_baseline_312eaa4_schema.sql
tail -n +7362 db-migrations.sql > /tmp/daa1939_task7_name_completion_increment.sql
psql -X -v ON_ERROR_STOP=1 -d <migration-db> -f <baseline-schema>
psql -X -v ON_ERROR_STOP=1 -d <migration-db> -f <completion-increment>
psql -X -v ON_ERROR_STOP=1 -d <migration-db> -f <completion-increment>
psql -X -v ON_ERROR_STOP=1 -d <migration-db> -f db-rls.sql
psql -X -v ON_ERROR_STOP=1 -d <migration-db> -f tests/sql/1939-v50-writer-bootstrap.sql
psql -X -v ON_ERROR_STOP=1 -d <migration-db> -f tests/sql/test-1939-v50-name-completion.sql
```

Result: both migration applications and the five-block contract passed.
Schema/migration parity covered eleven relevant function definitions plus
ACLs and the complete result-table contract:

- function/ACL SHA-256:
  `798d78320e981081bd82476794277b780d43719fdf678708b42adf5e6463ab69`
  on both paths;
- result-table SHA-256:
  `9fe08e06d86c7b92b08deb5e88eb7bcae545c4701bc9dc1f7f07ea9f149abf46`
  on both paths.

Isolated original writer regression:

```text
psql -X -v ON_ERROR_STOP=1 -d <writer-db> -f tests/sql/test-1939-v50-production-writer.sql
DO
DO
DO
DO
```

Real DBI workflow:

```text
PGHOST=/tmp PGPORT=5432 PGUSER=johanreventlow PGPASSWORD= \
  PGDATABASE=daa1939_name_completion_task7_integration_20260818 \
  Rscript tests/integration/test-1939-v50-name-completion.R
PASS DAA 1939 v50 name completion PostgreSQL integration
```

The DBI driver emitted only its expected cancellation warnings while closing
the deliberately blocked contention query. The test proved CLI actor wiring,
dry-run zero persistence, rollback after elements 1–8 and finalize, practical
lock timeout, exact apply/result map, replay rejection, RLS, and reversal.

## Security and compliance audit

Fresh catalog audit result:

```text
relevant SECURITY DEFINER functions: 11
non-SECURITY-DEFINER: 0
missing pg_catalog-first fixed search_path: 0
PUBLIC/anon EXECUTE grants: 0
forbidden authenticated EXECUTE on private helpers/authorize RPC: 0
private result table RLS: true
private result table policies: 0
private result table exposed ACL entries: 0
```

The public R API is exactly
`execute_name_completion(manifest, manifest_sha256, mode, gateway,
authorization)`; the CLI accepts only manifest, hash, mode, output and apply
authorization. There is no count, binding or database override. SQL accepts a
count object only at authorization and compares it to the literal closed 8/8
contract.

Credential scans over the Task 1–6 code and five real artifacts found no
credential URI, JWT literal, Supabase secret, literal password, service-role
key or API key. Environment-variable references are not credential values.
No `*cutover*` artifact exists, the only earlier production authorization
artifact is operation `reimport`, and the completion manifest keeps both
authorization flags false.

The SQL contract freshly proved wrong actor, expiry, authorization reuse,
source/person/persona/page/text/payload drift, existing name fact, missing
source link, non-staged state, ninth element and partial finalize all fail
closed. It also proved cutover rejection before completion and under citation,
conclusion, fact, cache, missing identity, result and event drift, with zero
partial activation. Reversal validates the owned child chain before deletion,
preserves append-only results/events and fails with zero deletion on drift.

## Restore/rehearsal evidence

Permanent pre-original-apply recovery point, freshly re-hashed in Task 7:

- `/Users/johanreventlow/Backups/danmarksadelsaarbog/daa-production-before-1939-v50-2026-08-18.dump`
- mode `0600`; 3,656,690 bytes
- SHA-256 `634eef826b22b3443ac265b4bbbded31d3917be4fcbf7193e7172e7643b66032`

Current staged-state Task 6 snapshot, freshly re-hashed in Task 7:

- `/Users/johanreventlow/Backups/danmarksadelsaarbog/daa-production-staged-after-1939-v50-task6-2026-08-18.dump`
- mode `0600`; 4,514,944 bytes
- SHA-256 `40f0565dd3920922bec32327739f5ab56d04314520a484ee0c49aba443db76e9`

Task 6 A/B dry-run result maps are identical; each returned eight results and
persisted zero completion rows. Both full outer-transaction rehearsals created
exactly 8 facts/assertions/citations/conclusions/results/events, kept all eight
persons staged with exact caches, then reversed and rolled back to byte-equal
protected baselines. Their normalized semantic SHA-256 is
`2bac30f9da3c00a0bbae82266a82010faf58ca24d45830b5f83d731e42723fc5`.

These backups remain recovery evidence. Because the future production write
does not occur in Task 7, a **new immediate pre-apply backup** is still required
and must be re-hashed and mode-checked before authorization.

## Concrete concern

The sole observed concern is the non-failing `normalizePath("run-tests.R")`
warning described above. It did not skip or prevent the 63-assertion contract,
the SQL contracts or the real DBI workflow. Per the small-project scope, it is
recorded rather than expanded into unrelated wrapper cleanup.

## Required future approval

Only after a new immediate backup exists may a future approval name all of:

1. production database `postgres` / system identifier
   `7642734024280108049`;
2. the new backup's exact absolute path, mode `0600`, byte count and SHA-256;
3. `db-migrations.sql` SHA-256
   `5a9f7dee27d0d2ffb0d089a28d930dfb34b5d14588d600a077f3c6977422e276`;
4. `db-rls.sql` SHA-256
   `356d7990b3db2cbf3b7091287f1fd18b193e99e66244d328bf5052a19444610a`;
5. completion manifest byte SHA-256
   `4ea983b8ea7c630d1b24487b58b7e000902d2a5202bdf397a630270f4ed48ea3`;
6. exactly one `name_completion` authorization and apply for the eight listed
   operations, with no retry and no cutover.

Until such approval is given, production apply remains **NO-GO**. Cutover is
outside this approval and remains **NO-GO**.
