#!/usr/bin/env bash
# Trin 6d-1: opgradering fra main (prods skema før 6d-1): DDL-blokken løftes; migrationerne køres to gange; de fire
# funktioner har bagefter præcis schema.sql's kroppe (sha256 af pg_get_functiondef, målt på en frisk base bygget her),
# ACL er som aftalt, de fire testfiler og db-verify er grønne. Kun lokalt/CI. Ved succes droppes de tre baser, scriptet
# selv oprettede (<db>, <db>_f, <db>_v); ved fejl står de tilbage til inspektion.
set -euo pipefail
name=${1:?database}; base=${2:-$(git merge-base origin/main HEAD)}
db="$name"; dbf="${name}_f"; dbv="${name}_v"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
for f in schema.sql db-rls.sql db-migrations.sql; do git show "$base:$f" > "$tmp/$f"; done
q() { env -u PGOPTIONS psql -X -q -v ON_ERROR_STOP=1 -d "$1" "${@:2}" >/dev/null; }
a() { env -u PGOPTIONS psql -X -At -v ON_ERROR_STOP=1 -d "$1" -c "$2"; }
fns="private.record_legacy_disposition(bigint,bigint,text,uuid,jsonb) public.red_promote_placement_memberships(bigint,text) public.public_person_source_coordinates()"
sha() { # sha256 af alle kroppe i den angivne base, ét sæt linjer
  for f in $fns; do a "$1" "SELECT '$f|'||encode(extensions.digest(convert_to(pg_get_functiondef('$f'::regprocedure),'UTF8'),'sha256'),'hex')"; done
  a "$1" "SELECT 'private.membership_component_states()|'||coalesce((SELECT encode(extensions.digest(convert_to(pg_get_functiondef(to_regprocedure('private.membership_component_states()')),'UTF8'),'sha256'),'hex') WHERE to_regprocedure('private.membership_component_states()') IS NOT NULL),'MISSING')"
}
createdb "$db"; createdb "$dbf"; createdb "$dbv"
# Frisk reference: kun schema.sql + rls (som CI's frisk schema-sti).
for f in tests/sql/evidence-promotion-bootstrap.sql schema.sql db-rls.sql; do q "$dbf" -f "$f"; done
fresh=$(sha "$dbf")
! grep -q MISSING <<<"$fresh" || { echo "FRESH_INVALID: membership_component_states mangler i schema.sql" >&2; exit 1; }
# Prods skema: base-versionens skema, rls, migrationer to gange.
for f in tests/sql/evidence-promotion-bootstrap.sql "$tmp/schema.sql" "$tmp/db-rls.sql" "$tmp/db-migrations.sql" "$tmp/db-migrations.sql" "$tmp/db-rls.sql"; do q "$db" -f "$f"; done
old=$(sha "$db")
grep -q 'private.membership_component_states()|MISSING' <<<"$old" || { echo "UPGRADE_BASE_INVALID: membership_component_states findes allerede i $base" >&2; exit 1; }
# De gamle kroppe er til stede og adskiller sig fra de nye (ellers beviser opgraderingen intet).
for f in $fns; do
  [ "$(grep -F "$f|" <<<"$old")" != "$(grep -F "$f|" <<<"$fresh")" ] || { echo "UPGRADE_BASE_INVALID: $f er allerede ny i $base" >&2; exit 1; }
done
# Opgradering: de aktuelle migrationer og rls to gange.
for f in db-migrations.sql db-rls.sql db-migrations.sql db-rls.sql; do q "$db" -f "$f"; done
new=$(sha "$db")
[ "$new" = "$fresh" ] || { echo "UPGRADE_BODY_MISMATCH" >&2; diff <(echo "$fresh") <(echo "$new") >&2 || true; exit 1; }
# ACL.
[ "$(a "$db" "SELECT
  NOT has_function_privilege('anon','private.membership_component_states()','EXECUTE')
  AND NOT has_function_privilege('authenticated','private.membership_component_states()','EXECUTE')
  AND NOT has_function_privilege('service_role','private.membership_component_states()','EXECUTE')
  AND has_function_privilege('authenticated','public.red_promote_placement_memberships(bigint,text)','EXECUTE')
  AND NOT has_function_privilege('anon','public.red_promote_placement_memberships(bigint,text)','EXECUTE')")" = "t" ] || { echo "UPGRADE_ACL_MISMATCH" >&2; exit 1; }
for t in test-placement-writer test-placement-membership test-membership-component test-person-source-coordinates; do q "$db" -f "tests/sql/$t.sql"; done
# Selvstændig base til db-verify (som test-150-upgrade.sh).
for f in tests/sql/evidence-promotion-bootstrap.sql "$tmp/schema.sql" "$tmp/db-rls.sql" "$tmp/db-migrations.sql" "$tmp/db-migrations.sql" "$tmp/db-rls.sql" \
         db-migrations.sql db-rls.sql db-migrations.sql db-rls.sql tests/sql/run-db-verify-disposable.sql; do q "$dbv" -f "$f"; done
# Oprydning: kun de tre baser, dette kald selv oprettede.
dropdb --if-exists "$db"; dropdb --if-exists "$dbf"; dropdb --if-exists "$dbv"
echo UPGRADE_OK
