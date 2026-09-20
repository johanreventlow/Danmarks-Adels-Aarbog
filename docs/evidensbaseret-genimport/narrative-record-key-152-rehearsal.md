# #152 narrative record key — disposable Task 12 rehearsal

**Date:** 2026-08-30

**Branch:** `feat/narrative-record-key-152`

**Task 12 starting HEAD:** `720ca52a77c56d935dcb24dccd496567bc4459a4`

**Feature review range:** `f53d965879011d1d21c45c9824be67f86ee3d80e..Task 12 HEAD`

**Environment:** synthetic, loopback-only PostgreSQL 17; no production identity,
credentials, data, artifacts, deploy, push or merge were used.

## Outcome

The PostgreSQL contract, real multi-session races, complete local suites and a
production-shaped synthetic backup/restore plus cutover gateway passed. The
real-browser smoke exercised the actual web record editor against a disposable
DBI bridge and completed all eleven scenarios, including the separately
confirmed legacy withdrawal and its public/history postchecks. No narrative
text left the synthetic fixture.

The first in-scope implementation defect found during the rehearsal was in the
cutover exporter's integer64 identity/order checks: `RPostgres` returns
`bigint` as `bit64::integer64`, for which base `anyDuplicated()` and
`identical()` compare negative values' double payload incorrectly. The first
focused Task 12 regression was RED with `COUNTS_BY_SOURCE_ORDER`; independent
Sol review then identified the same defect in legacy-ID validation, and the
expanded two-row legacy fixture was RED with `INVALID_LEGACY_IDS`. The minimum
fix compares exact decimal identities after the original integer64 numeric
sort. The full two-source/two-legacy fixture and a second production-shaped
restore/gateway chain then exported successfully.

The initial independent review also found two web fail-closed defects. An
explicit conflict reload retained the stale local textarea override after
adopting the fresh server token, while v2 biography RPC failures were converted
to valid empty biography values. The user expanded the allowlist to the exact
six affected web files. Precise regressions failed before the changes; the
record-specific reload now discards only the conflicted override, and both web
biography adapters propagate v2 fetch failures to their callers.

The required second Sol review accepted the editor correction and adapter
boundaries, but found that the real public consumers still masked or
mishandled those rejections. The user then expanded the allowlist to the exact
three consumers, their two existing component tests and one conventional new
root render test. Consumer regressions were RED before the change and now show
scoped, explicit error states rather than valid empty biography content or an
unhandled rejection. The third independent review then found two edge cases
at the same public adapter boundary: an absent Supabase `rpc` capability was
implicitly treated as contract v1, and a synchronous v2 RPC throw could pass
outside the existing rejection normalization. Both precise regressions were
RED before the minimum fix and now reject with the dedicated contract/v2
errors. The post-fix Sol reread returned **GO** with no findings.

## Safety boundary

- PostgreSQL: `/opt/homebrew/opt/postgresql@17`, loopback
  `127.0.0.1:55439`, temporary cluster
  `/tmp/daa-task12-pg.P2tMzL/data`, system identifier
  `7679748947805531194`.
- All DB commands set all five variables together:
  `PGDATABASE`, `PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD`.
- Every database name contained `task12`, `test`, `ci` or `disposable`; no
  database named `postgres` was used as a test target.
- The machine's unrelated PostgreSQL listener on port 5432 was neither
  connected to, stopped nor reused.
- After the browser postchecks and this evidence were preserved, both
  temporary harness processes were interrupted and the disposable cluster was
  stopped with `pg_ctl -D /tmp/daa-task12-pg.P2tMzL/data stop -m fast`;
  `pg_isready -h 127.0.0.1 -p 55439` then returned `no response` (exit 2).
- Backup, manifests, approval, review and receipt lived under mode-0700
  temporary directories outside the repository. Exporter/gateway artifacts
  were mode 0600.
- `work/` and the preserved untracked external design-review file were not
  read, modified or staged.
- Browser data and screenshots contain synthetic fixture content only.
- `NO_PRODUCTION_MUTATION`.

## RED → GREEN: integer64 multi-source export

The Task 12 integration artifact contains one record source and two legacy
rows in a second source with distinct negative `bit64::integer64` source and
narrative IDs, plus true-duplicate and descending negative controls for both
ID domains. The fixture was not narrowed.

```bash
Rscript tests/integration/test-narrative-record-concurrency.R
```

- RED before the first helper correction: distinct ascending source IDs failed
  with `COUNTS_BY_SOURCE_ORDER`.
- RED after expanding the Sol regression: two distinct ascending negative
  legacy narrative IDs failed ref minting with `INVALID_LEGACY_IDS`.
- Root cause probes demonstrated that `anyDuplicated(bit64::integer64(...))`
  returned a false duplicate and `identical(x, sort(x))` could treat different
  NaN payloads as equal.
- GREEN after the correction: distinct ascending IDs build a bundle and mint
  two unique legacy refs; exact duplicate and descending controls still fail
  with `DUPLICATE_LEGACY_CANDIDATE`, `LEGACY_CANDIDATE_ORDER` or
  `COUNTS_BY_SOURCE_ORDER` as applicable.

Focused exporter verification after the fix:

```bash
Rscript -e 'testthat::test_file("tests/testthat/test-export-narrative-record-cutover.R")'
```

Result: `FAIL 0 | WARN 0 | SKIP 0 | PASS 62`.

## PostgreSQL 17 focused and concurrency proof

A fresh database was bootstrapped for each stateful SQL family. The local
cutover SQL hard-codes port 5432 in its dblink fixture; it was streamed through
a transient `sed` replacement to the isolated 55439 listener. No repository
file was changed.

```bash
PGDATABASE=daa_narrative_152_task12_contract PGHOST=127.0.0.1 PGPORT=55439 \
PGUSER=postgres PGPASSWORD=task12-synthetic \
  /opt/homebrew/opt/postgresql@17/bin/psql -X -v ON_ERROR_STOP=1 \
  -f tests/sql/test-narrative-record-contract.sql

sed 's/host=127.0.0.1 port=5432/host=127.0.0.1 port=55439/g' \
  tests/sql/test-narrative-record-cutover.sql | \
PGDATABASE=daa_narrative_152_task12_cutover PGHOST=127.0.0.1 PGPORT=55439 \
PGUSER=postgres PGPASSWORD=task12-synthetic \
  /opt/homebrew/opt/postgresql@17/bin/psql -X -v ON_ERROR_STOP=1

PGDATABASE=daa_narrative_152_task12_verify PGHOST=127.0.0.1 PGPORT=55439 \
PGUSER=postgres PGPASSWORD=task12-synthetic \
  /opt/homebrew/opt/postgresql@17/bin/psql -X -v ON_ERROR_STOP=1 \
  -f tests/sql/run-db-verify-disposable.sql

PGDATABASE=daa_narrative_152_task12_concurrency PGHOST=127.0.0.1 PGPORT=55439 \
PGUSER=postgres PGPASSWORD=task12-synthetic \
  Rscript tests/integration/test-narrative-record-concurrency.R
```

Results:

- record contract: GREEN, including the Task 6 dblink lock-order notices;
- cutover contract: GREEN on a fresh database;
- full historical `run-db-verify-disposable.sql`: GREEN;
- real DBI concurrency: `OK: Task 12 real multi-session DBI concurrency
  proof (34 assertions; create/update stale losers; lock orders A/B; v1/v2
  gate)`.

The concurrency test uses independent R processes and RPostgres connections.
`pg_stat_activity` plus `pg_blocking_pids()` proves the expected lock wait. It
invokes the real `private.apply_narrative_record_cutover` kernel in both
interleavings with canonical synthetic empty-set artifacts: exclusive-first
commits a receipt before the blocked old writer wakes and rejects; shared-first
waits behind the old writer, then rejects the actual kernel with
`CUTOVER_LEGACY_LIVE_SET_DRIFT`, leaving no receipt, version or ACL change. It
also asserts exact `OK`/`NARRATIVE_RECORD_STATE_STALE` writer winner/loser
pairs, version-1 new-writer rejection, version-2 success, one active binding,
unique stream versions and independent streams for two records in the same
source.

## CI job

`.github/workflows/ci.yml` adds `narrative-record-contract-db` with a
`postgres:17` service and all five PG environment variables. It installs
`DBI`, `RPostgres`, `processx`, `bit64`, `jsonlite` and `digest`, bootstraps the
auth shim, installs `dblink`, applies `schema.sql`, `db-migrations.sql` and
`db-rls.sql`, and runs the record contract, cutover contract, full historical
DB verify and real DBI race on separate fresh database states. Focused output
is kept in distinct steps from the historical verify.

```bash
Rscript -e 'parse(file="tests/integration/test-narrative-record-concurrency.R"); parse(file=".claude/skills/daa-extract/scripts/export_narrative_record_cutover_helpers.R")'
ruby -e 'require "yaml"; YAML.load_file(".github/workflows/ci.yml"); puts "CI YAML parse: OK"'
git diff --check
```

Result: both R files parse, CI YAML parses, and `git diff --check` is clean.
`actionlint` was not installed locally (`ACTIONLINT_NOT_INSTALLED`); this was
not masked, and Ruby YAML parsing plus the exact CI command review is recorded
instead.

## RED → GREEN: fail-closed web conflict and v2 fetches

```bash
npm run test -w web -- \
  src/components/__tests__/PersonNarrativeRecordEditor.test.tsx \
  src/data/__tests__/orThrow.test.ts \
  src/data/__tests__/feedAux.test.ts
```

The pre-fix run was RED in exactly three tests:

- after `Genindlæs`, the textarea remained `Min lokale tekst` instead of the
  fresh `Ny servertekst`;
- `fetchPersonDetail` resolved `TOM_PERSONDETALJE` instead of rejecting
  `PUBLIC_BIO_SOURCE_V2_UNAVAILABLE`;
- `fetchFeedBios` resolved `{}` instead of rejecting
  `PUBLIC_BIO_SOURCE_VERSIONS_UNAVAILABLE`.

Self-review then added two capability controls. They were RED when the first
draft of the fix also propagated v1 RPC rejection, demonstrating a regression
against the required `<2` behavior. The final implementation preserves the
tolerant v1 fallback while propagating contract-version and v2 RPC/mapping
failures.

After that narrowing, the same focused command was GREEN: 3 files, 31 tests.
The editor regression then submits a second time and asserts both the fresh
server text and fresh `stateSha256`, proving the stale local text cannot be
replayed. The adapter regressions distinguish v2 RPC failure from a legitimate
empty v2 result and pin the retained v1 fallback.

The second Sol review exposed the remaining consumer-level gap. The exact
consumer regressions were run with the same synthetic Vite values:

```bash
npm run test -w web -- \
  src/__tests__/Folgesvend.test.tsx \
  src/components/__tests__/PresensView.test.tsx \
  src/components/__tests__/FeedStreamView.test.tsx
```

Before the consumer corrections all three new cases were RED: the person
detail rendered the valid empty detail, the Præsens fold-out rendered `Ingen
biografi registreret`, and the feed emitted an unhandled rejection while
showing no fetch error. The minimum fixes keep biography fetch error state
separate from legitimate empty data. Folgesvend renders a scoped person-detail
alert and ignores late responses for a previous focus; Præsens stores a
per-person alert and retries only when the user reopens it; the feed handles
the rejection and renders a visible alert instead of failing silently.

Final focused result: GREEN, 3 files and 22 tests.

The third Sol review's two adapter-edge regressions were then exercised in
`src/data/__tests__/orThrow.test.ts`. Before the fix, both were RED because
`fetchPersonDetail` resolved the valid empty detail instead of rejecting: once
when `supabase.rpc` was absent and once when the v2 biography call threw
synchronously. The minimum correction requires the contract-version RPC
capability before choosing a reader and starts the biography RPC at a promise
boundary so synchronous and asynchronous v2 failures share the explicit
`PublicNarrativeFetchError` path.

```bash
npm run test -w web -- \
  src/components/__tests__/PersonNarrativeRecordEditor.test.tsx \
  src/data/__tests__/orThrow.test.ts \
  src/data/__tests__/feedAux.test.ts \
  src/__tests__/Folgesvend.test.tsx \
  src/components/__tests__/PresensView.test.tsx \
  src/components/__tests__/FeedStreamView.test.tsx
```

Final combined focused result: GREEN, 6 files and 55 tests. The dedicated
adapter file is GREEN, 12/12, including the retained tolerant v1 control.

## Full local suites

The exact required suite commands were run from Task 12 starting HEAD. The
post-helper R suite was run again because it is the only full suite invalidated
by the helper correction.

| Command | Result |
| --- | --- |
| `Rscript run-tests.R` | GREEN after final in-scope fixes: `FAIL 0 | WARN 14 | SKIP 2 | PASS 2229` in 68.3 s |
| `npm run test -w @daa/core` | GREEN: 29 files, 417 tests |
| `npm run typecheck -w @daa/core` | GREEN |
| `npm run test -w web` with synthetic `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` | GREEN after final adapter and consumer fixes: 72 files, 927 tests |
| `npm run build -w web` with the same synthetic Vite values | GREEN; only the existing chunk-size warning |
| `npm run test -w mobile` | GREEN: 31 suites, 450 tests |
| `npm --workspace mobile exec -- tsc --noEmit` | GREEN |

Additional repository suites run during the full verification:

| Command | Result |
| --- | --- |
| `npm run test -w @daa/feed` | GREEN: 10 files, 129 tests |
| `npm run typecheck -w @daa/feed` | GREEN |
| `python3 -m unittest discover -s .claude/skills/daa-haendelser/scripts -p 'test_*.py'` | GREEN: 15 tests |
| `/usr/bin/python3 -m pytest .claude/skills/daa-extract/scripts/test_build_narrative_record_cutover_review.py -q` | GREEN: 23 tests |

The 14 R warnings are the pre-existing direct-wrapper `normalizePath("run-tests.R")`
warning. The two skips are one empty test and the explicitly disabled local DB
smoke (`DAA_RUN_LOCAL_DB_SMOKE != 1`). Neither is a Task 12 failure.

## Production-shaped synthetic restore and gateway

Source backup:

- path: `/tmp/daa-narrative-152-rehearsal.yH978D/source-precutover.backup`;
- SHA-256:
  `a17e7df637f90921d3b0d4ed30a6f09f74dbaaf1c5185a5ecb5e365b992d4a5e`;
- source state: contract version 1, two record bindings, two eligible legacy
  candidates and zero publication events.

The custom-format backup was restored to a distinct database:
`daa_narrative_152_task12_gateway`, system identifier
`7679748947805531194`. It is not a production-bound identity.

```bash
PGDATABASE=daa_narrative_152_task12_gateway PGHOST=127.0.0.1 PGPORT=55439 \
PGUSER=postgres PGPASSWORD=task12-synthetic \
  Rscript .claude/skills/daa-extract/scripts/export_narrative_record_cutover.R \
  --output-dir /tmp/daa-narrative-152-gateway.utKIbL/export

/usr/bin/python3 .claude/skills/daa-extract/scripts/build_narrative_record_cutover_review.py \
  --record-candidates /tmp/daa-narrative-152-gateway.utKIbL/export/narrative-record-baseline-candidates-v1.json \
  --legacy-candidates /tmp/daa-narrative-152-gateway.utKIbL/export/narrative-legacy-baseline-candidates-v1.json \
  --inventory /tmp/daa-narrative-152-gateway.utKIbL/export/narrative-record-cutover-inventory-v1.json \
  --output-dir /tmp/daa-narrative-152-gateway.utKIbL/approval

/usr/bin/python3 .claude/skills/daa-extract/scripts/convert_narrative_record_cutover_approvals.py \
  --record-candidates /tmp/daa-narrative-152-gateway.utKIbL/export/narrative-record-baseline-candidates-v1.json \
  --legacy-candidates /tmp/daa-narrative-152-gateway.utKIbL/export/narrative-legacy-baseline-candidates-v1.json \
  --inventory /tmp/daa-narrative-152-gateway.utKIbL/export/narrative-record-cutover-inventory-v1.json \
  --decisions /tmp/daa-narrative-152-gateway.utKIbL/approval/narrative-record-cutover-decisions-v1.json \
  --output-dir /tmp/daa-narrative-152-gateway.utKIbL/approval
```

The gateway was invoked with all six exact artifact paths, nonce
`15212000-0000-4000-8000-000000001213`, expected database name and expected
system identifier, first in `rollback`, then committed `apply`, then from a
new R process in `recover` mode using the same nonce and hashes.

Artifact hashes:

| Artifact | SHA-256 |
| --- | --- |
| record candidates | `fef40068104297f0c1bc7ac47eb7b8fd2dbd25d029837c44791a59579ba2c714` |
| legacy candidates | `0337ebae5fce3a6754603c9684af35721aef755906ec069966a6cae3ad4ad571` |
| inventory | `9a794e02ed11e9e2cf6905ac4b6babcd2d3904d1d3ebcf0139e8d188e2ae91da` |
| review HTML | `e32ff568f9371052a6c3bfe8cc9331e426a2440edbeed303aaba46ce1c31aac3` |
| decisions | `b7adc2090d2757efe2b4835d14f75954b2b01608e3eea577cb0627593bd3ddbd` |
| record manifest | `e4015a3820a8419a68dbd7388a5989420913294e0ce93e15c6f483731fbddfd6` |
| legacy manifest | `0c8e4c2b1184ab41611439571c2f922f5243c7738dfa5b34323d1fec3a33907c` |
| approval | `73887f4aa5314b8ddafd48b1db0a007c763d88547e0484150e671c1a34ba72e4` |
| receipt file | `d01c60e40b2660d54f4b7dd349ddcc330f15afd6e14dfff8b7a26a9b4c1455e0` |
| receipt result | `1c506823fbc19989a87f34769c3ec447f824eb280993c613cade6fb2fc556936` |

Exact approved sets:

- record candidates/approved: 2/2 —
  `0760111a-0be1-4c95-ae07-8ff0229e7f49`,
  `28b191f0-d6a7-4717-9573-d0a28e522915`;
- legacy candidates: 2 — IDs `1`, `4`;
- legacy keep: 1 — ID `1`;
- legacy hide: 1 — ID `4`;
- `keep ∪ hide` equals the candidate set, with no overlap;
- accepted identity count: 2; identity-blocked record count: 0.

Gateway result:

- rollback: GREEN with exact before/after equality;
- committed apply: version 1 → 2, change set 5, two record baseline events,
  one grandfathered legacy baseline and hidden legacy ID 4;
- narrative sequence `before=4`, `floor=5`, `after=5`;
- reconnect/recover: `status=recovered` with the exact receipt, database
  identity and six input hashes;
- receipt committed at `2026-08-30 10:05:31.174088`.

Read-only postverify after reconnect found contract version 2, three baseline
events, two draft record projections, one active grandfathered ledger row,
zero duplicate stream versions, exactly one receipt for the nonce, change set
5 and legacy keep ID `{1}`. Raw legacy ID 4 still exists privately but has no
baseline and is absent from the public contract, as required.

### Post-Sol repetition after the expanded integer64 fix

Because Sol's accepted finding extended the helper correction to legacy
narrative IDs, the complete production-shaped chain was repeated rather than
relying on the earlier result. The same verified v1 backup was restored to the
new database `daa_narrative_152_task12_sol_gateway` with the same disposable
system identifier. Output root:
`/tmp/daa-narrative-152-sol-gateway.BBtw3C`; nonce:
`15212000-0000-4000-8000-000000001214`.

The rerun retained the complete 2-record/2-legacy fixture and produced:

| Artifact | SHA-256 |
| --- | --- |
| record candidates | `7077b28f8342d75565fbfe926f9d6b661c9b944da84697c61fa8cef3d96f2a5c` |
| legacy candidates | `661134416909e49b7079b5bd0e0c8af12631a6caa91276bccd21583d8b6f815e` |
| inventory | `bf54554b9e6e65a408771f9fdc9696a919fff7d5d6fa304e09bd00f3c2dc0f46` |
| review HTML | `701ca4a79a893e61a542aa38d363ad8ffeab280a8b8f997172b61fcf2723259d` |
| decisions | `3e897553c6511c6b95556feb5a4dfb935493e00305afb6d8aaf69e7624694558` |
| record manifest | `f5fd70ba8deb3078cd087428d723078605efdacec02706bb6592705523e7a6a5` |
| legacy manifest | `188656fbde9e42e5e6f338dc71e544c7276ac8b6fd20828c3c5af7313586e57b` |
| approval | `f09b87c91b2c4529160989138057e8af79d751c6261a20d4c524cf197161e7d1` |
| receipt file | `6cd7e108654cae0082f2f59624f71424ebd6b0f7d6b4b7f9a80dc51400635087` |
| receipt result | `e57e8dacd493750655607b0afffc279d46ce473e874dc3fb235ead5636193354` |

Rollback again proved exact before/after equality. Committed apply again
produced version 1 → 2, change set 5, two record baseline events, one kept
legacy baseline, hidden ID 4 and sequence `4/5/5`. A new process returned
`status=recovered` with the exact receipt and six hashes. Read-only postverify
found version 2, three baseline events, two draft bindings, one grandfathered
ledger row, zero duplicate stream versions and one exact nonce receipt.

## Real-browser smoke

The browser harness is outside the repository at
`/private/tmp/daa-task12-browser.71e27r`. It imports the actual
`web/src/components/PersonNarrativeRecordEditor.tsx`; only the read adapter is
aliased to a loopback R/DBI bridge. Synthetic Vite values satisfy the existing
Supabase module-load guard. The bridge uses the separate disposable database
`daa_narrative_152_task12_browser` on PostgreSQL 17/55439.

Observed scenarios in a real visible browser:

1. two record cards from the same DAA source rendered separately;
2. a draft was created on one record;
3. both record streams were edited independently;
4. a second-session stale token produced the explicit local/server conflict
   UI with no automatic retry;
5. explicit publish and published revision changed the separately rendered
   public event text;
6. synthetic provenance drift hid the public version, and explicit
   revalidation restored it;
7. dedicated reversal restored the semantic before-state without deleting
   history;
8. draft discard preserved history and the reversal event showed no redo;
9. the grandfathered legacy text was public and read-only, the unbaselined
   synthetic legacy row remained hidden, and `Tag biografi ned` opened a
   target-specific confirmation with the entered non-empty reason; after the
   required action-time user confirmation, the submit reported
   `Tag biografi ned: committed`, only the selected row became
   `Tilbagetrukket overgangsbiografi`, public v2 reported
   `Ingen offentlige recordtekster`, unbaselined public rows remained zero and
   history appended `v2 · legacy_withdrawn`;
10. record withdrawal preserved the same public `source_record_ref` across
    the record lifecycle;
11. web/public ordering used the shared record identity and the synthetic
    mobile ambiguity diagnostic was read-only with `Brug webredaktionen`.

The browser control policy required action-time user confirmation for the
delete-like legacy-withdraw submit even against the disposable fixture. The
root in-app browser retained a full-page capture of the synthetic confirmation
state: selected `Synthetic grandfathered browser biography`, reason
`Task 12 synthetic withdrawal smoke test`, checked confirmation, enabled
`Bekræft nedtagning`, one public `legacy_narrative`, mobile diagnostic
`readonly: Flere eller ingen kildeposter` and zero unbaselined public rows. The
post-click values above were read from the live DOM. The capture API returned
no durable local path, so no path is claimed and no image or fixture was added
to the repository.

## Adversarial final-tree scan

Commands were scoped away from `work/` and the protected review file:

```bash
rg -n "\\.from\\(['\"]narrative['\"]\\)|red_upsert_narrativ|red_publicer_narrative_record|red_tilbagetraek_narrative_record" web mobile packages/core R .claude/skills/daa-extract/scripts tests/testthat
rg -n "source_record_id|sourceRecordId|binding_id|bindingId" web mobile packages/core
rg -n -i "max\\s*\\(\\s*id\\s*\\)\\s*\\+\\s*1|max\\s*\\(\\s*narrative\\.id\\s*\\)" schema.sql db-migrations.sql R .claude/skills/daa-extract/scripts
rg -n -i "(update|delete|truncate)\\s+(from\\s+)?private\\.narrative_publication_event|grant\\s+.*narrative_publication_event" schema.sql db-migrations.sql db-rls.sql
rg -n "TO[D]O|TB[D]|<place[holder]>" schema.sql db-migrations.sql db-rls.sql db-verify.sql web mobile packages/core .claude/skills/daa-extract/scripts tests/sql tests/integration tests/testthat
rg -n "NARRATIVE_RECORD_STATE_STALE|NARRATIVE_RECORD_IDENTITY|NARRATIVE_RECORD_ANCHOR_REQUIRED|NARRATIVE_RECORD_DERIVED_EVENTS_PRESENT|NARRATIVE_RECORD_DEDICATED_REVERSAL_REQUIRED|NARRATIVE_RECORD_LEGACY" web/src
```

Disposition:

- `web/src/data/public.ts` issues the direct person query only on contract v1,
  so v2 cannot concatenate fallback text. Its tolerant wrapper now rethrows
  the dedicated contract-version/v2 error class, while retaining the v1
  fallback. Estate, slægt, lineage, presence and event metadata reads are
  classified non-person or RLS-gated controls.
- Web/mobile generic `fetchNarrativer` remains for non-person/non-DAA editors.
  The person v2 editor uses the record RPC exclusively. Mobile builds
  `red_upsert_narrativ` only with an explicit version-1 capability marker;
  web's remaining generic builder is unreachable from the v2 person editor,
  and the DB runtime gate also rejects it.
- Client fixtures deliberately contain malicious `source_record_id` values
  and assert they are discarded. No first-party writer serializes a private
  source-record or binding UUID. The safe immutable `source_record_ref` and
  `legacy_publication_ref` are the designed capabilities.
- Relevant narrative allocation uses identity defaults. The narrative
  sequence scan hits the exclusive cutover resync and comments/historical
  migrations; no active v2 person writer uses an unlocked `max(id)+1`.
- No event update/delete/truncate or direct client grant matched. The
  append-only trigger and private ACL/RLS assertions remain present.
- Stable web mappings cover stale state/publication, identity required or
  conflicting, anchor required, derived events, illegal transition, dedicated
  reversal, legacy drift and person-delete publication history.
- The only unfinished-marker hits are pre-existing comments in the unrelated
  historical 1939 converter/validator. No #152 implementation or Task 12 file
  contains one.

## Unexpected failure disposition

Nothing was suppressed or converted to a pass:

1. An early focused SQL run lacked the `dblink` extension and failed
   `NARRATIVE_RECORD_TASK3_DBLINK_REQUIRED`. The fresh-database bootstrap and
   CI job now install `dblink`; the unchanged test passed.
2. Reusing the record-contract database for the cutover test failed
   `CUTOVER_RESULT_INVALID` because the focused contract deliberately installs
   a version fixture. Fresh databases between stateful suites fixed the test
   environment, not the contract.
3. The first bare web test command failed 24 collection suites after 580 tests
   because `web/src/supabase.ts` requires non-empty Vite values at module load.
   Rerunning the complete suite and build with non-secret synthetic values
   passed 919 tests. No network call or test was skipped.
4. Homebrew Python lacked `pytest`; the repository-designated
   `/usr/bin/python3 -m pytest` command passed all 23 tests.
5. The first restore rehearsal used a race-seeded v2 source and rollback
   correctly rejected `CUTOVER_RECORD_STREAM_NOT_EMPTY`. A new v1-only
   synthetic source backup preserved the full two-source fixture and passed
   rollback/apply/recover.
6. An initial read-only postverify used the wrong column name `event_kind` and
   aborted its transaction. The corrected `event_type` query ran in a new
   read-only transaction and produced the results above; no mutation occurred.
7. The outside-repository browser harness initially exposed a TSX transform
   syntax error, then the expected Supabase environment guard, then two bridge
   request-shape errors. Each was root-caused in the temporary harness only;
   after repair the actual component and real DB-backed actions rendered. No
   repository source was changed for the harness.
8. `actionlint` is not installed; its absence is stated above and the YAML was
   parsed independently with Ruby.
9. The repeated decision converter rejected a hand-written pretty JSON file
   with `NON_CANONICAL_JSON`. It was regenerated in the converter's compact,
   sorted canonical form with the same explicit decisions and then passed; no
   gate was bypassed.
10. The first repeated gateway invocation put `--mode` last and failed its
    exact CLI usage check before opening a database transaction. The invocation
    was corrected to the documented flag order and the complete
    rollback/apply/recover sequence then passed.

## Codex self-review and independent Sol review

Codex self-review covered the Task 12 diff plus the complete feature range and
relevant surrounding readers/writers. The final Task 12 concurrency test uses
genuine independent sessions, observable waits and the actual cutover kernel;
CI resets state between stateful suites; the exporter correction preserves
numeric ordering and exact duplicate identity; and all gateway evidence is
bound to the disposable database identity.

Per the current repository `AGENTS.md` and the explicit Task 12 override, the
independent reviewer was GPT-5.6-Sol, not Claude Fable. Sol was invoked
read-only with high scrutiny over `f53d965..HEAD`, the unstaged Task 12 diff,
the two Task 12-owned untracked files and relevant surrounding code. The prompt
explicitly prohibited edits, databases, network, `work/` and the protected
review file. Sol confirmed that none was accessed or modified.

Initial Sol verdict: **NO-GO**. Findings were dispositioned critically:

1. **Accepted P1 — integer64 legacy IDs shared the source-count payload bug.**
   The original regression had only one legacy row. Expanding it to two
   distinct negative IDs produced RED `INVALID_LEGACY_IDS`. The helper now uses
   exact decimal identities for legacy-ref minting and duplicate/order checks;
   duplicate and descending controls remain. Focused exporter: 62/62; full R:
   2229 passes; repeated restore/gateway: GREEN.
2. **Accepted P1 — the first DBI test simulated cutover rather than calling the
   production kernel.** A static pre-fix check was RED with
   `TASK12_ACTUAL_CUTOVER_KERNEL_RACE_MISSING`. Both interleavings now call
   `private.apply_narrative_record_cutover` with canonical synthetic artifacts.
   Fresh PG17 result: 34 assertions GREEN with exact receipt/drift/no-write
   checks. Sol reread and accepted this correction.
3. **Accepted P3 — the unquoted CI job name lost `#152 · PostgreSQL 17` as a
   YAML comment.** Quoting the value restores the intended visible name. Ruby
   parses it exactly as `narrative record #152 · PostgreSQL 17`; job behavior
   was otherwise unaffected.
4. **Accepted P1 — stale conflict reload could replay local text with a fresh
   token.** The user approved the exact editor and test files. The regression
   clicked `Genindlæs`, expected the fresh server text, saved again and checked
   the fresh text/hash payload; it was RED before the fix. Explicit reload now
   removes only the conflicted record's local override. Focused 29 tests and
   full web 920 tests: GREEN.
5. **Accepted P2 — v2 fetch failures became valid empty data.** The user
   approved the two adapters and their existing tests. `fetchPersonDetail` no
   longer applies the tolerant empty fallback to person-detail failures, and
   `fetchFeedBios` logs then rethrows instead of returning `{}`. Both precise
   v2 RPC regressions were RED before the fixes and GREEN afterward; a genuine
   empty v2 response remains `{}`/an empty biography, and explicit controls
   prove the v1 fallback remains tolerant. The full web suite (922 tests) and
   production build are GREEN.

Because findings 4–5 materially changed stale-write and failure semantics, a
second read-only Sol review was performed over the final diff. Its verdict was
**NO-GO** with two valid P2 findings:

6. **Accepted P2 — person views still masked explicit adapter failure.** The
   user approved both consumers, the existing Præsens test and a conventional
   new `Folgesvend.test.tsx`. Both component-level regressions were RED before
   the fix. Folgesvend now keeps detail error distinct from loading/empty data
   and cancels late responses; Præsens stores error per person instead of `''`.
   Both render the explicit adapter code in a scoped alert. Focused and full
   web suites: GREEN.
7. **Accepted P2 — feed failure was unhandled.** The user approved the feed
   consumer and its existing test. The RED run produced the expected unhandled
   rejection and no alert. `FeedStreamView` now handles rejection, keeps it
   distinct from a legitimate empty `{}` result and displays the explicit
   failure. Focused and full web suites: GREEN.

The second reviewer found no remaining issue in the stale reload, adapter
boundary behavior, integer64 correction, real-kernel race, PostgreSQL 17 CI or
their evidence. It modified no files and accessed no database, network,
`work/`, protected review file, Claude or Fable. Findings 6–7 were accepted,
fixed only after the explicit second scope expansion, and verified with 22
focused and 925 complete web tests plus the production build.

The third read-only Sol review was **NO-GO** with one valid P2 adapter-boundary
finding containing two cases:

8. **Accepted P2 — missing RPC capability and a synchronous v2 throw could
   still become valid empty data.** The first case implicitly chose v1 when
   `supabase.rpc` was absent; the second escaped the promise rejection handler
   before `safe()` could distinguish the dedicated error. Both exact tests
   resolved `TOM_PERSONDETALJE` before the fix. Contract-version resolution now
   fails closed when the RPC capability is missing, and the biography RPC is
   invoked from a promise boundary so synchronous and asynchronous v2 failures
   normalize to `PublicNarrativeFetchError`. The adapter file is GREEN 12/12,
   the six-file focused set is GREEN 55/55, the complete web suite is GREEN
   72 files/927 tests, and the production build is GREEN with only the existing
   chunk-size warning.

Sol found no other material issue in the final Task 12 changes. Because this
accepted finding changed the public error boundary, the same independent Sol
reviewer reread the complete final diff after the fix. Final verdict: **GO,
findings none**. The reread explicitly accepted the missing-RPC and
synchronous/asynchronous v2 normalization, the verified v1 fallback, stale
reload, all three consumer error states, integer64 correction, actual-kernel
race, PostgreSQL 17 CI job and their regression coverage. It modified no files,
ran no artifact-producing tests, and accessed no database, network, `work/`,
protected review file, Claude or Fable.

## Final boundary

This rehearsal proves only disposable integration. It is not production
authority, does not generate or approve a production manifest, and does not
advance #152 to production-verified status.

`NO_PRODUCTION_MUTATION`
