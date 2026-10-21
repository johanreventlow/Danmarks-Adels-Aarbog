#!/usr/bin/env bash
# Indholds-id (#151, spec §5.5): opgradering fra prods træ 140a17b (deploy 2026-09-17, ingen 5a/5b-DDL).
# Migrationerne køres to gange; 5a/5b-testene, hovedtesten og db-verify køres på den opgraderede vej. Kun lokalt.
# Brug: bash tests/sql/test-indholds-id-upgrade.sh <db> [<commit>]
set -euo pipefail
db0=${1:?database}; base=${2:-140a17b}; db=$db0
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
for f in schema.sql db-rls.sql db-migrations.sql; do git show "$base:$f" > "$tmp/$f"; done
q() { env -u PGOPTIONS psql -X -q -v ON_ERROR_STOP=1 -d "$db" "$@" >/dev/null 2>>"$tmp/err" || { echo "UPGRADE_FAIL: $*"; grep -m3 -E 'ERROR|FATAL' "$tmp/err"; exit 1; }; }
dropdb --if-exists "$db" >/dev/null 2>&1 || true; createdb "$db"
for f in tests/sql/evidence-promotion-bootstrap.sql "$tmp/schema.sql" "$tmp/db-rls.sql" "$tmp/db-migrations.sql" "$tmp/db-rls.sql" \
         db-migrations.sql db-rls.sql db-migrations.sql db-rls.sql tests/sql/1939-v50-writer-bootstrap.sql; do q -f "$f"; done
q -c 'BEGIN' -f tests/sql/reimport-writer-v2-bootstrap.sql -c 'COMMIT'; q -f db-rls.sql
sed -n '/^-- BEGIN 5a-cutover/,/^-- END 5a-cutover/p' db-migrations.sql > "$tmp/cutover-5a.sql"
q -v cutover="$tmp/cutover-5a.sql" -f tests/sql/test-identity-cutover.sql
for t in test-content-uuid test-identity-decision test-identity-candidates test-identity-control-run test-relation-persona-writer \
         test-relation-persona-v3 test-spouse-exception-projection; do q -f "tests/sql/$t.sql"; done
db="${db0}_v"; dropdb --if-exists "$db" >/dev/null 2>&1 || true; createdb "$db"
for f in tests/sql/evidence-promotion-bootstrap.sql "$tmp/schema.sql" "$tmp/db-rls.sql" "$tmp/db-migrations.sql" "$tmp/db-rls.sql" \
         db-migrations.sql db-rls.sql db-migrations.sql db-rls.sql tests/sql/run-db-verify-disposable.sql; do q -f "$f"; done
bash tests/sql/test-indholds-id-determinism.sh "${db0}_det" "upgrade:$base"
dropdb "$db0"; dropdb "$db"
echo UPGRADE_OK
