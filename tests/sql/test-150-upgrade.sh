#!/usr/bin/env bash
# #150 trin 5c-1 (spec §7): opgradering fra main (prods skema efter #248): placement-blokken løftes; migrationerne
# køres to gange; de tre nye testfiler, bindingstesten og db-verify skal være grønne bagefter. Kun lokalt.
set -euo pipefail
db=${1:?database}; base=${2:-$(git merge-base origin/main HEAD)}
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
for f in schema.sql db-rls.sql db-migrations.sql; do git show "$base:$f" > "$tmp/$f"; done
q() { env -u PGOPTIONS psql -X -q -v ON_ERROR_STOP=1 -d "$db" "$@" >/dev/null; }
createdb "$db"
for f in tests/sql/evidence-promotion-bootstrap.sql "$tmp/schema.sql" "$tmp/db-rls.sql" "$tmp/db-migrations.sql" "$tmp/db-migrations.sql" "$tmp/db-rls.sql"; do q -f "$f"; done
[ "$(env -u PGOPTIONS psql -X -At -d "$db" -c "SELECT to_regclass('private.legacy_placement_disposition') IS NULL")" = "t" ]
for f in db-migrations.sql db-rls.sql db-migrations.sql db-rls.sql; do q -f "$f"; done
[ "$(env -u PGOPTIONS psql -X -At -d "$db" -c "SELECT to_regclass('private.legacy_placement_disposition') IS NOT NULL
  AND to_regprocedure('private.placement_header_violations(bigint)') IS NOT NULL
  AND to_regprocedure('private.write_header_evidence(bigint,uuid,jsonb,jsonb)') IS NOT NULL
  AND (SELECT count(*) FROM private.vocab WHERE scheme='observation_kind' AND code LIKE 'header\_%')=4
  AND EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='public.slaegt'::regclass AND tgname='trg_log_slaegt')
  AND position('header_linje' IN pg_get_functiondef('private.validate_source_record_placement()'::regprocedure))>0
  AND has_function_privilege('authenticated','public.red_promote_placement_memberships(bigint,text)','EXECUTE')
  AND NOT has_function_privilege('anon','public.red_promote_placement_memberships(bigint,text)','EXECUTE')")" = "t" ]
for t in test-placement-header test-placement-writer test-placement-membership; do q -f "tests/sql/$t.sql"; done
PGOPTIONS='-c search_path=public,extensions' psql -X -q -v ON_ERROR_STOP=1 -d "$db" -f tests/sql/test-relation-binding.sql >/dev/null
db="${1}_v"; createdb "$db"
for f in tests/sql/evidence-promotion-bootstrap.sql "$tmp/schema.sql" "$tmp/db-rls.sql" "$tmp/db-migrations.sql" "$tmp/db-migrations.sql" "$tmp/db-rls.sql" \
         db-migrations.sql db-rls.sql db-migrations.sql db-rls.sql tests/sql/run-db-verify-disposable.sql; do q -f "$f"; done
echo UPGRADE_OK
