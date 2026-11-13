#!/usr/bin/env bash
# Trin 6e-2 Task 1: sidekort og omregning PDF-side -> trykt side.
# 1) Frisk base (bootstrap + schema.sql + db-rls.sql): omregningstabel, CHECK, side_trykt(citation), anon-adgang.
# 2) Opgradering fra HEAD's skema (valgfrit 2. arg = base-commit, default merge-base med origin/main): migrationen to gange
#    ændrer intet (et udfyldt kort nulstilles ikke), og funktionskroppene er byte-ens med schema.sql.
# Kun lokalt/CI. Ved succes droppes de to baser, scriptet selv oprettede (<db>, <db>_u); ved fejl står de tilbage.
set -euo pipefail
name=${1:?database}; base=${2:-$(git merge-base origin/main HEAD)}
db="$name"; dbu="${name}_u"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
for f in schema.sql db-rls.sql db-migrations.sql; do git show "$base:$f" > "$tmp/$f"; done
q() { env -u PGOPTIONS psql -X -q -v ON_ERROR_STOP=1 -d "$1" "${@:2}" >/dev/null; }
a() { env -u PGOPTIONS psql -X -At -v ON_ERROR_STOP=1 -d "$1" -c "$2"; }
createdb "$db"; createdb "$dbu"
for f in tests/sql/evidence-promotion-bootstrap.sql schema.sql db-rls.sql; do q "$db" -f "$f"; done
env -u PGOPTIONS psql -X -q -v ON_ERROR_STOP=1 -d "$db" -f tests/sql/test-6e2-sidekort.sql >/dev/null
echo FRISK_OK
# Opgradering: base-skemaet (uden sidekort), så nuværende migration to gange.
for f in tests/sql/evidence-promotion-bootstrap.sql "$tmp/schema.sql" "$tmp/db-rls.sql" "$tmp/db-migrations.sql"; do q "$dbu" -f "$f"; done
[ "$(a "$dbu" "SELECT count(*) FROM information_schema.columns WHERE table_schema='public' AND table_name='source' AND column_name='sidekort'")" = "0" ] \
  || { echo "UPGRADE_BASE_INVALID: sidekort findes allerede i $base" >&2; exit 1; }
q "$dbu" -f db-migrations.sql
q "$dbu" -c "INSERT INTO public.source(id,titel) VALUES(-6201,'sidekort-opgradering')" \
         -c "UPDATE public.source SET sidekort='[{\"pdf_fra\":10,\"pdf_til\":20,\"trykt_fra\":1}]' WHERE id=-6201"
q "$dbu" -f db-migrations.sql -f db-rls.sql -f db-migrations.sql
[ "$(a "$dbu" "SELECT sidekort::text FROM public.source WHERE id=-6201")" = '[{"pdf_fra": 10, "pdf_til": 20, "trykt_fra": 1}]' ] \
  || { echo "UPGRADE_SIDEKORT_NULSTILLET" >&2; exit 1; }
[ "$(a "$dbu" "SELECT public.source_trykt_side(-6201,'12')")" = "3" ] || { echo "UPGRADE_OMREGNING" >&2; exit 1; }
sha() { for f in 'private.sidekort_gyldigt(jsonb)' 'public.source_trykt_side(bigint,text)' 'public.side_trykt(public.citation)' 'public.public_person_facts(bigint[])'; do
  a "$1" "SELECT '$f|'||encode(extensions.digest(convert_to(pg_get_functiondef(to_regprocedure('$f')),'UTF8'),'sha256'),'hex')||'|'||coalesce((SELECT proacl::text FROM pg_proc WHERE oid=to_regprocedure('$f')),'NULL')"; done; }
[ "$(sha "$db")" = "$(sha "$dbu")" ] || { echo "UPGRADE_BODY_OR_ACL_MISMATCH" >&2; diff <(sha "$db") <(sha "$dbu") >&2 || true; exit 1; }
dropdb --if-exists "$db"; dropdb --if-exists "$dbu"
echo UPGRADE_OK
