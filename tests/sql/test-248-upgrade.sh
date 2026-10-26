#!/usr/bin/env bash
# #248 rute A (spec §5): opgradering fra main (prods skema efter #265): genåbnings-blokken løftes; migrationerne
# køres to gange; bindings- og projektionstestene og db-verify skal være grønne bagefter. Kun lokalt.
set -euo pipefail
db=${1:?database}; base=${2:-$(git merge-base origin/main HEAD)}
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
for f in schema.sql db-rls.sql db-migrations.sql; do git show "$base:$f" > "$tmp/$f"; done
q() { env -u PGOPTIONS psql -X -q -v ON_ERROR_STOP=1 -d "$db" "$@" >/dev/null; }
createdb "$db"
for f in tests/sql/evidence-promotion-bootstrap.sql "$tmp/schema.sql" "$tmp/db-rls.sql" "$tmp/db-migrations.sql" "$tmp/db-migrations.sql" "$tmp/db-rls.sql"; do q -f "$f"; done
[ "$(env -u PGOPTIONS psql -X -At -d "$db" -c "SELECT to_regclass('private.relation_reopen') IS NULL")" = "t" ]
for f in db-migrations.sql db-rls.sql db-migrations.sql db-rls.sql; do q -f "$f"; done
[ "$(env -u PGOPTIONS psql -X -At -d "$db" -c "SELECT to_regclass('private.relation_reopen') IS NOT NULL
  AND to_regprocedure('public.red_genaabn_relation_interpretation(uuid,integer,text,jsonb)') IS NOT NULL
  AND has_function_privilege('authenticated','public.red_genaabn_relation_interpretation(uuid,integer,text,jsonb)','EXECUTE')
  AND NOT has_function_privilege('anon','public.red_genaabn_relation_interpretation(uuid,integer,text,jsonb)','EXECUTE')")" = "t" ]
for t in test-relation-binding test-spouse-exception-projection; do q -f "tests/sql/$t.sql"; done
db="${1}_v"; createdb "$db"
for f in tests/sql/evidence-promotion-bootstrap.sql "$tmp/schema.sql" "$tmp/db-rls.sql" "$tmp/db-migrations.sql" "$tmp/db-migrations.sql" "$tmp/db-rls.sql" \
         db-migrations.sql db-rls.sql db-migrations.sql db-rls.sql tests/sql/run-db-verify-disposable.sql; do q -f "$f"; done
echo UPGRADE_OK
