# #152 narrative record key — production cutover runbook

## Authority and stop gate

This is the only production procedure for moving #152 from contract version 1
to 2. It invokes exactly
`private.apply_narrative_record_cutover(text,text,text,text,text,text,uuid,text,text)`.
It is not a production GO or a bulk approval. A written preliminary
project-owner authorization permits only private artifact setup, nonce
generation, the mode-0600 backup and its disposable restore rehearsal, fresh
non-mutating inventory, and offline review. It is not authority for preflight,
apply, recovery, or any production write.

The operator uses the reviewed commit and sets `PGDATABASE`, `PGHOST`,
`PGPORT`, `PGUSER`, and `PGPASSWORD` together. Stop before backup if that
profile is incomplete; the checkout is not clean apart from the preserved
external review file; the contract version is not exactly 1; or a separate
disposable restore target is unavailable. No credential, backup, manifest,
approval, or receipt may be placed in the repository or below a path component
named `work`.

Stop and return the case to the project owner on any drift in artifact bytes,
hashes, candidate or manifest ID sets, counts, direct-reader classification,
database name, system identifier, or contract version. Never use manual SQL to
compensate for a failed gate. Two named local reviewers are required: one
reviews every record and legacy decision; the other independently verifies all
hashes, sets, counts, and database identity.

After that preliminary authorization has produced the backup/restore rehearsal,
fresh artifacts, and both reviews, the final, bound project-owner GO control
record must contain the reviewed release SHA and an unexpired expiry; proof
that the additive schema, migration, RLS, and ACL signatures are
deployed; and proof that the capability-aware web and mobile clients are
deployed before version-2 writer authority is enabled. It must also bind the
fresh artifact database name and system identifier, all six raw SHA-256 values,
the exact record/legacy/hidden ID sets, five inventory quantities, complete
direct-reader classification, both reviewer approvals, project-owner approval,
the already-recorded backup SHA-256, one nonce, and an explicit external
writer-traffic hold owner and control reference. It binds the fresh exported
bytes; it does not rely on invented historical ID sets. The final GO is signed
after all bound evidence exists and before preflight; expired, release-SHA-
drifted, or byte-drifted evidence is invalid.

The numbered sections are grouped by control, not chronology. The required
order is: preliminary authorization; sections 1–2 (backup and disposable
restore rehearsal); sections 3–4 (fresh read-only export and offline review);
final bound GO; then sections 5–6. A rehearsal in section 2 uses its own
disposable artifacts and never substitutes for the fresh production-bound
evidence.

Under the preliminary authorization, establish the private artifact location
and nonce before section 3. Retain these exact values for the final GO and all
later sections; do not recreate them after review.

```bash
set -euo pipefail
umask 077
CUTOVER_DIR="$(mktemp -d /private/tmp/daa-narrative-record-cutover.XXXXXX)"
chmod 700 "$CUTOVER_DIR"
EXPORT_DIR="$CUTOVER_DIR/export"
REVIEW_DIR="$CUTOVER_DIR/review"
mkdir "$EXPORT_DIR" "$REVIEW_DIR"
chmod 700 "$EXPORT_DIR" "$REVIEW_DIR"
CUTOVER_NONCE="$(/usr/bin/python3 -c 'import uuid; print(uuid.uuid4())')"
printf '%s\n' "$CUTOVER_NONCE"
```

## 1. Backup and isolation

Run under the preliminary authorization before fresh production-bound export
and final GO. This creates a mode-0700 location outside the repository;
`umask 077` and the explicit check require the backup to be 0600.

```bash
set -euo pipefail
umask 077
RECEIPT_DIR="$CUTOVER_DIR/receipt"
test -d "$EXPORT_DIR"
test -d "$REVIEW_DIR"
mkdir "$RECEIPT_DIR"
chmod 700 "$RECEIPT_DIR"
git status --short
git diff --check
/opt/homebrew/opt/postgresql@17/bin/psql -X -v ON_ERROR_STOP=1 -Atc \
  "SELECT public.narrative_record_contract_version()"
/opt/homebrew/opt/postgresql@17/bin/pg_dump --format=custom \
  --file="$CUTOVER_DIR/precutover.backup"
chmod 600 "$CUTOVER_DIR/precutover.backup"
stat -f '%Lp %N' "$CUTOVER_DIR/precutover.backup"
shasum -a 256 "$CUTOVER_DIR/precutover.backup"
```

Continue only when the contract is `1`, diff check is empty, and the backup
reports mode `600`. Record its SHA-256 for binding in the later final GO; the
backup is an incident resource, never routine rollback.

## 2. Restore rehearsal

Change all five `PG*` variables to the pre-approved disposable profile, never
the cutover profile. The following commands create an isolated rehearsal
database and restore the backup there.

```bash
set -euo pipefail
test "$PGHOST" = "$REHEARSAL_APPROVED_HOST"
test "$PGPORT" = "$REHEARSAL_APPROVED_PORT"
test "$PGUSER" = "$REHEARSAL_APPROVED_USER"
test "$PGDATABASE" = "$REHEARSAL_APPROVED_MAINTENANCE_DATABASE"
test -n "$PGPASSWORD"
test -n "$REHEARSAL_APPROVED_SYSTEM_IDENTIFIER"
test "$REHEARSAL_APPROVED_SYSTEM_IDENTIFIER" != "$CUTOVER_APPROVED_SYSTEM_IDENTIFIER"
/opt/homebrew/opt/postgresql@17/bin/psql -X -v ON_ERROR_STOP=1 -Atc \
  "SELECT (pg_control_system()).system_identifier::text" | \
  grep -Fx "$REHEARSAL_APPROVED_SYSTEM_IDENTIFIER"
REHEARSAL_DATABASE="daa_narrative_record_rehearsal_$(date +%Y%m%d%H%M%S)"
/opt/homebrew/opt/postgresql@17/bin/createdb \
  --host="$PGHOST" --port="$PGPORT" --username="$PGUSER" \
  "$REHEARSAL_DATABASE"
PGDATABASE="$REHEARSAL_DATABASE" \
  /opt/homebrew/opt/postgresql@17/bin/pg_restore --clean --if-exists \
  --no-owner --dbname="$REHEARSAL_DATABASE" "$CUTOVER_DIR/precutover.backup"
PGDATABASE="$REHEARSAL_DATABASE" \
  /opt/homebrew/opt/postgresql@17/bin/psql -X -v ON_ERROR_STOP=1 -Atc \
  "SELECT current_database(), (pg_control_system()).system_identifier, public.narrative_record_contract_version()"
```

Run the export, review, conversion, and preflight portions of sections 3–5
against that disposable database with a separate mode-0700 artifact directory.
The expected result is
`preflight_rolled_back`, proving the real kernel and exact database rollback.
Any restore, identity, hash, ACL, or version failure blocks production.

## 3. Fresh read-only inventory

Return to the full cutover profile. The exporter owns the repeatable-read,
read-only transaction and shared cutover lock; handwritten extracts are not an
alternative.

```bash
set -euo pipefail
umask 077
Rscript .claude/skills/daa-extract/scripts/export_narrative_record_cutover.R \
  --output-dir "$EXPORT_DIR"
find "$EXPORT_DIR" -maxdepth 1 -type f -exec stat -f '%Lp %N' {} \;
shasum -a 256 "$EXPORT_DIR"/*.json
/usr/bin/python3 - "$EXPORT_DIR/narrative-record-cutover-inventory-v1.json" <<'PY'
import json
import sys
inventory = json.load(open(sys.argv[1], encoding="utf-8"))
print("bindings=", len(inventory["record_candidate_ids"]))
print("grandfathered_legacy=", len(inventory["legacy_candidate_ids"]))
print("accepted_identities=", inventory["accepted_identity_count"])
print("blocked_new_records=", inventory["identity_blocked_record_count"])
print("direct_readers=", len(inventory["classified_direct_readers"]))
print("database_name=", inventory["database"]["database_name"])
print("system_identifier=", inventory["database"]["system_identifier"])
PY
```

Both reviewers independently inspect the SHA-256 values for record candidates,
legacy candidates, and inventory. They also inspect fresh counts for bindings,
grandfathered legacy, accepted identities, blocked new records, and direct
readers. The fresh exact ID sets, counts, reader classifications, and the
`database_name`/`system_identifier` pair are the review evidence. Material
drift between export, review, final GO, and preflight returns to the project
owner; equal counts never approve a drifted set.

## 4. Human review and approval conversion

Build the review surface locally. It is offline and must not become a network
or database client.

```bash
set -euo pipefail
umask 077
/usr/bin/python3 .claude/skills/daa-extract/scripts/build_narrative_record_cutover_review.py \
  --record-candidates "$EXPORT_DIR/narrative-record-baseline-candidates-v1.json" \
  --legacy-candidates "$EXPORT_DIR/narrative-legacy-baseline-candidates-v1.json" \
  --inventory "$EXPORT_DIR/narrative-record-cutover-inventory-v1.json" \
  --output-dir "$REVIEW_DIR"
stat -f '%Lp %N' "$REVIEW_DIR/narrative-record-cutover-review-v1.html"
shasum -a 256 "$REVIEW_DIR/narrative-record-cutover-review-v1.html"
```

Each record decision is `godkend baseline` or `uafklaret`; the latter is a
terminal stop. Each legacy decision is `bevar offentligt som grandfathered`,
`skjul ved cutover`, or `uafklaret`; the latter is again terminal. The local
reviewer saves `narrative-record-cutover-decisions-v1.json` in `$REVIEW_DIR`.
Use the converter and no hand-authored manifest.

```bash
set -euo pipefail
umask 077
/usr/bin/python3 .claude/skills/daa-extract/scripts/convert_narrative_record_cutover_approvals.py \
  --record-candidates "$EXPORT_DIR/narrative-record-baseline-candidates-v1.json" \
  --legacy-candidates "$EXPORT_DIR/narrative-legacy-baseline-candidates-v1.json" \
  --inventory "$EXPORT_DIR/narrative-record-cutover-inventory-v1.json" \
  --decisions "$REVIEW_DIR/narrative-record-cutover-decisions-v1.json" \
  --output-dir "$REVIEW_DIR"
find "$REVIEW_DIR" -maxdepth 1 -type f -exec stat -f '%Lp %N' {} \;
shasum -a 256 "$REVIEW_DIR"/*.json "$REVIEW_DIR"/*.html
```

The converter must produce the record manifest, legacy manifest, and approval.
The record manifest must cover every record candidate. Legacy keep and hide
must be a complete disjoint partition. The reviewers sign only when six raw
artifact hashes, exact sets, five counts, and database identity match their
separate review.

## 5. Drift recheck and exclusive cutover

Read database identity from the hash-reviewed inventory. The values are passed
to both gateway and kernel, which reject an active database that does not
match. One nonce may be used for preflight and then for at most one apply.

```bash
set -euo pipefail
read -r CUTOVER_DATABASE_NAME CUTOVER_SYSTEM_IDENTIFIER < <(
  /usr/bin/python3 - "$EXPORT_DIR/narrative-record-cutover-inventory-v1.json" <<'PY'
import json
import sys
database = json.load(open(sys.argv[1], encoding="utf-8"))["database"]
print(database["database_name"], database["system_identifier"])
PY
)
test -n "$CUTOVER_NONCE"
Rscript .claude/skills/daa-extract/scripts/apply_narrative_record_cutover.R \
  --mode preflight \
  --record-candidates "$EXPORT_DIR/narrative-record-baseline-candidates-v1.json" \
  --legacy-candidates "$EXPORT_DIR/narrative-legacy-baseline-candidates-v1.json" \
  --record-manifest "$REVIEW_DIR/narrative-record-baseline-manifest-v1.json" \
  --legacy-manifest "$REVIEW_DIR/narrative-legacy-baseline-manifest-v1.json" \
  --inventory "$EXPORT_DIR/narrative-record-cutover-inventory-v1.json" \
  --approval "$REVIEW_DIR/narrative-record-cutover-approval-v1.json" \
  --receipt "$RECEIPT_DIR/narrative-record-cutover-receipt-v1.json" \
  --nonce "$CUTOVER_NONCE" \
  --expected-database-name "$CUTOVER_DATABASE_NAME" \
  --expected-system-identifier "$CUTOVER_SYSTEM_IDENTIFIER"
```

`preflight_rolled_back` is the final drift recheck. The kernel obtains the
exclusive `daa-narrative-record-contract` lock, rereads version 1, validates
six raw artifacts, hashes, and exact live ID sets, then rolls back. Any
failure, including `CUTOVER_LEGACY_LIVE_SET_DRIFT`, requires a new export,
review, and project-owner decision.

Only when the signed final control record exists, its release SHA equals the
reviewed checkout SHA, its expiry has not passed, its backup SHA equals the
recorded mode-0600 backup, and preflight still matches its bound artifacts,
execute the identical command with `--mode apply`. Immediately before apply,
the named owner must activate the final-GO external writer-traffic hold and
record that control's reference in the operator log. The hold must block all
application and batch writers that could affect this contract; a shared
read-only database lock is not a substitute. It remains active through
postverify. It changes to version 2 as the last write of one transaction,
writes an append-only receipt, reconnects, and requires exactly one receipt
for nonce, six hashes, and database identity.

```bash
set -euo pipefail
Rscript .claude/skills/daa-extract/scripts/apply_narrative_record_cutover.R \
  --mode apply \
  --record-candidates "$EXPORT_DIR/narrative-record-baseline-candidates-v1.json" \
  --legacy-candidates "$EXPORT_DIR/narrative-legacy-baseline-candidates-v1.json" \
  --record-manifest "$REVIEW_DIR/narrative-record-baseline-manifest-v1.json" \
  --legacy-manifest "$REVIEW_DIR/narrative-legacy-baseline-manifest-v1.json" \
  --inventory "$EXPORT_DIR/narrative-record-cutover-inventory-v1.json" \
  --approval "$REVIEW_DIR/narrative-record-cutover-approval-v1.json" \
  --receipt "$RECEIPT_DIR/narrative-record-cutover-receipt-v1.json" \
  --nonce "$CUTOVER_NONCE" \
  --expected-database-name "$CUTOVER_DATABASE_NAME" \
  --expected-system-identifier "$CUTOVER_SYSTEM_IDENTIFIER"
shasum -a 256 "$RECEIPT_DIR/narrative-record-cutover-receipt-v1.json"
```

## 6. Commit-unknown recovery, postverify, and rollback

For connection loss, unknown commit, or missing local receipt, never run apply
again. Use the same six artifacts, nonce, and identity with `--mode recover`.
Only one exact database receipt with the nonce and six hashes returns
`status=recovered`; every other outcome is `CUTOVER_RECOVERY_REQUIRED` and an
incident.

```bash
set -euo pipefail
Rscript .claude/skills/daa-extract/scripts/apply_narrative_record_cutover.R \
  --mode recover \
  --record-candidates "$EXPORT_DIR/narrative-record-baseline-candidates-v1.json" \
  --legacy-candidates "$EXPORT_DIR/narrative-legacy-baseline-candidates-v1.json" \
  --record-manifest "$REVIEW_DIR/narrative-record-baseline-manifest-v1.json" \
  --legacy-manifest "$REVIEW_DIR/narrative-legacy-baseline-manifest-v1.json" \
  --inventory "$EXPORT_DIR/narrative-record-cutover-inventory-v1.json" \
  --approval "$REVIEW_DIR/narrative-record-cutover-approval-v1.json" \
  --receipt "$RECEIPT_DIR/narrative-record-cutover-receipt-v1.json" \
  --nonce "$CUTOVER_NONCE" \
  --expected-database-name "$CUTOVER_DATABASE_NAME" \
  --expected-system-identifier "$CUTOVER_SYSTEM_IDENTIFIER"
```

After `committed` or `recovered`, the reviewers run new read-only postverify
with the version-controlled verifier. It holds the shared cutover lock for one
read-only repeatable-read observation and fail-closes on contract version,
exact receipt and six hashes, full receipt-bound event rows and change-set
scope, actual ordered public v2 projections (including text, labels,
citations, provenance and hidden-legacy absence), inventory quantities,
direct-reader classification, and the full v2/legacy ACL role matrix.

```bash
set -euo pipefail
Rscript .claude/skills/daa-extract/scripts/verify_narrative_record_cutover_postverify.R \
  --record-candidates "$EXPORT_DIR/narrative-record-baseline-candidates-v1.json" \
  --legacy-candidates "$EXPORT_DIR/narrative-legacy-baseline-candidates-v1.json" \
  --record-manifest "$REVIEW_DIR/narrative-record-baseline-manifest-v1.json" \
  --legacy-manifest "$REVIEW_DIR/narrative-legacy-baseline-manifest-v1.json" \
  --inventory "$EXPORT_DIR/narrative-record-cutover-inventory-v1.json" \
  --approval "$REVIEW_DIR/narrative-record-cutover-approval-v1.json" \
  --nonce "$CUTOVER_NONCE" \
  --expected-database-name "$CUTOVER_DATABASE_NAME" \
  --expected-system-identifier "$CUTOVER_SYSTEM_IDENTIFIER"
```

Before database commit, rollback means database rollback: preflight or
`--mode rollback` must restore the exact before state. After committed cutover,
rollback never means deleting append-only events, editing a receipt, or
opportunistically lowering the version. Keep the external writer-traffic hold
active until postverify returns `postverify_passed`; only then may its named
owner release it and record the release. On postverify failure, preserve the
artifacts and receipt, keep the hold active, and go directly to
containment/incident handling; do not run `recover` as a purported repair. The
project owner then selects
documented containment and a new separately approved migration or recovery
path. Restore from `precutover.backup` requires explicit incident authority;
it is never routine rollback or a way to hide history.

## Finish

Hand the project owner the backup hash, six input hashes, receipt hash,
database identity, preflight/commit/recovery output, and postverify result.
The state is `READY_FOR_PRODUCTION_REVIEW` until a fresh explicit production GO
is given. New bindings and legacy loaders remain frozen by design; this
runbook does not automatically continue to another task.
