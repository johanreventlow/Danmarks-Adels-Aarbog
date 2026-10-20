#!/usr/bin/env bash
# #244 (spec §9.1): opgradering fra main (før #244): gammel funktion og unavngivet origin-CHECK løftes; migrationerne
# køres to gange; testfilen og db-verify skal være grønne bagefter. Kun lokalt.
set -euo pipefail
db=${1:?database}; base=${2:-$(git merge-base origin/main HEAD)}
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
for f in schema.sql db-rls.sql db-migrations.sql; do git show "$base:$f" > "$tmp/$f"; done
q() { env -u PGOPTIONS psql -X -q -v ON_ERROR_STOP=1 -d "$db" "$@" >/dev/null; }
createdb "$db"
for f in tests/sql/evidence-promotion-bootstrap.sql "$tmp/schema.sql" "$tmp/db-rls.sql" "$tmp/db-migrations.sql" "$tmp/db-migrations.sql" "$tmp/db-rls.sql"; do q -f "$f"; done
[ "$(env -u PGOPTIONS psql -X -At -d "$db" -c "SELECT count(*) FROM pg_constraint WHERE conname='interpretation_party_origin_check'")" = "1" ]
for f in db-migrations.sql db-rls.sql db-migrations.sql db-rls.sql; do q -f "$f"; done
[ "$(env -u PGOPTIONS psql -X -At -d "$db" -c "SELECT pg_get_constraintdef(oid) LIKE '%ordinal_correction%' FROM pg_constraint WHERE conname='interpretation_party_origin_check'")" = "t" ]
q -f tests/sql/1939-v50-writer-bootstrap.sql
q -c 'BEGIN' -f tests/sql/reimport-writer-v2-bootstrap.sql -c 'COMMIT'
q -f db-rls.sql
q -f tests/sql/test-marriage-ordinal-correction.sql
db="${1}_v"; createdb "$db"
for f in tests/sql/evidence-promotion-bootstrap.sql "$tmp/schema.sql" "$tmp/db-rls.sql" "$tmp/db-migrations.sql" "$tmp/db-migrations.sql" "$tmp/db-rls.sql" \
         db-migrations.sql db-rls.sql db-migrations.sql db-rls.sql tests/sql/run-db-verify-disposable.sql; do q -f "$f"; done
echo UPGRADE_OK
