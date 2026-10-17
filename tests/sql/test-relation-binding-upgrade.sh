#!/usr/bin/env bash
# Trin 5b 2b-i (#151, spec §10): opgradering fra 2a's head med eksisterende familiebindinger; genbinding og
# ordinal_beholdt efter opgraderingen; derefter migrationerne to gange mere. Kun lokalt.
set -euo pipefail
db=${1:?database}; base=${2:-31008f5}
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
for f in schema.sql db-rls.sql db-migrations.sql; do git show "$base:$f" > "$tmp/$f"; done
q() { env -u PGOPTIONS psql -X -q -v ON_ERROR_STOP=1 -d "$db" "$@" >/dev/null; }
createdb "$db"
for f in tests/sql/evidence-promotion-bootstrap.sql "$tmp/schema.sql" "$tmp/db-rls.sql" "$tmp/db-migrations.sql" "$tmp/db-migrations.sql" "$tmp/db-rls.sql"; do q -f "$f"; done
q -f tests/sql/fixtures/spouse-exception-2bi.sql
for f in db-migrations.sql db-rls.sql; do q -f "$f"; done
q -f tests/sql/fixtures/upgrade-2bi-rebind.sql      # ret O1 → preview v2 → bind; ordinal_beholdt på O2 (committet)
for f in db-migrations.sql db-rls.sql db-migrations.sql db-rls.sql; do q -f "$f"; done
for t in test-relation-binding test-spouse-exception-projection test-evidence-promotion test-interpretation-predicate; do q -f "tests/sql/$t.sql"; done
# run-db-verify-disposable laver selv et kontrakt-2-cutover og afviser en base med committede data
# (CUTOVER_INVENTORY_LIVE_DRIFT); db-verify køres derfor i en søsterbase med samme opgraderingssti uden fixtures.
db="${1}_v"; createdb "$db"
for f in tests/sql/evidence-promotion-bootstrap.sql "$tmp/schema.sql" "$tmp/db-rls.sql" "$tmp/db-migrations.sql" "$tmp/db-migrations.sql" "$tmp/db-rls.sql" \
         db-migrations.sql db-rls.sql db-migrations.sql db-rls.sql tests/sql/run-db-verify-disposable.sql; do q -f "$f"; done
echo UPGRADE_OK
