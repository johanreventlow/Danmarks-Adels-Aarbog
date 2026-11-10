#!/usr/bin/env bash
# Trin 6d-2a: opgradering fra main (prods skema før 6d-2a): DDL-blokken løftes; migrationerne køres to gange; de seks
# funktioner har bagefter præcis schema.sql's kroppe (sha256 af pg_get_functiondef, målt på en frisk base bygget her)
# og samme proacl; de to nye testfiler og db-verify er grønne. Kun lokalt/CI. Ved succes droppes de tre baser, scriptet
# selv oprettede (<db>, <db>_f, <db>_v); ved fejl står de tilbage til inspektion.
set -euo pipefail
name=${1:?database}; base=${2:-$(git merge-base origin/main HEAD)}
db="$name"; dbf="${name}_f"; dbv="${name}_v"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
for f in schema.sql db-rls.sql db-migrations.sql; do git show "$base:$f" > "$tmp/$f"; done
q() { env -u PGOPTIONS psql -X -q -v ON_ERROR_STOP=1 -d "$1" "${@:2}" >/dev/null; }
a() { env -u PGOPTIONS psql -X -At -v ON_ERROR_STOP=1 -d "$1" -c "$2"; }
# Funktioner, der findes både før og efter 6d-2a (kroppen ændres).
fns="public.public_person_bio_source_versions_v2(bigint[]) public.public_person_bio_source_versions(bigint[]) public.red_samme_som(bigint,bigint)"
# Nye i 6d-2a (findes ikke i base-versionen): MISSING i den gamle base.
newfns="private.overview_mention_narratives(bigint[]) private.samme_som_data_direction(bigint,bigint) public.red_overview_mentions(bigint[])"
sha() { # sha256 af kroppen + proacl for hver funktion i den angivne base, ét sæt linjer
  for f in $fns $newfns; do a "$1" "SELECT '$f|'||coalesce((SELECT encode(extensions.digest(convert_to(pg_get_functiondef(p.oid),'UTF8'),'sha256'),'hex')||'|'||coalesce(p.proacl::text,'NULL') FROM pg_proc p WHERE p.oid=to_regprocedure('$f')),'MISSING')"; done
}
createdb "$db"; createdb "$dbf"; createdb "$dbv"
# Frisk reference: kun schema.sql + rls (som CI's frisk schema-sti).
for f in tests/sql/evidence-promotion-bootstrap.sql schema.sql db-rls.sql; do q "$dbf" -f "$f"; done
fresh=$(sha "$dbf")
! grep -q MISSING <<<"$fresh" || { echo "FRESH_INVALID: en 6d-2a-funktion mangler i schema.sql" >&2; echo "$fresh" >&2; exit 1; }
# Prods skema: base-versionens skema, rls, migrationer to gange.
for f in tests/sql/evidence-promotion-bootstrap.sql "$tmp/schema.sql" "$tmp/db-rls.sql" "$tmp/db-migrations.sql" "$tmp/db-migrations.sql" "$tmp/db-rls.sql"; do q "$db" -f "$f"; done
old=$(sha "$db")
for f in $newfns; do
  grep -qF "$f|MISSING" <<<"$old" || { echo "UPGRADE_BASE_INVALID: $f findes allerede i $base" >&2; exit 1; }
done
# De gamle kroppe er til stede og adskiller sig fra de nye (ellers beviser opgraderingen intet).
for f in $fns; do
  [ "$(grep -F "$f|" <<<"$old")" != "$(grep -F "$f|" <<<"$fresh")" ] || { echo "UPGRADE_BASE_INVALID: $f er allerede ny i $base" >&2; exit 1; }
done
# Opgradering: de aktuelle migrationer og rls to gange.
for f in db-migrations.sql db-rls.sql db-migrations.sql db-rls.sql; do q "$db" -f "$f"; done
new=$(sha "$db")
[ "$new" = "$fresh" ] || { echo "UPGRADE_BODY_OR_ACL_MISMATCH" >&2; diff <(echo "$fresh") <(echo "$new") >&2 || true; exit 1; }
for t in test-overview-mention test-samme-som-retning; do q "$db" -f "tests/sql/$t.sql"; done
# Selvstændig base til db-verify (som test-6d1-upgrade.sh).
for f in tests/sql/evidence-promotion-bootstrap.sql "$tmp/schema.sql" "$tmp/db-rls.sql" "$tmp/db-migrations.sql" "$tmp/db-migrations.sql" "$tmp/db-rls.sql" \
         db-migrations.sql db-rls.sql db-migrations.sql db-rls.sql tests/sql/run-db-verify-disposable.sql; do q "$dbv" -f "$f"; done
# Oprydning: kun de tre baser, dette kald selv oprettede.
dropdb --if-exists "$db"; dropdb --if-exists "$dbf"; dropdb --if-exists "$dbv"
echo UPGRADE_OK
