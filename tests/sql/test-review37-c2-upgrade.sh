#!/usr/bin/env bash
# Review 37 ceremoni 2 (#397: P3, P9, P10, R37P11-3). Prods deploy-form: blokken `-- BEGIN review37-c2` sidst i
# db-migrations.sql alene (ingen ACL-ændringer, så ingen db-rls-DO-blok), i ÉN psql-transaktion (-1).
# 1) Frisk reference (bootstrap + dblink + schema.sql + db-rls.sql): hele kataloget (tests/sql/inspect-catalog-parity.sql).
# 2) Prod-formet base (2. arg; CI pinner main efter ceremoni 1 = prods SQL): basens skema + migrationer to gange + rls.
#    De tre funktioner har deres gamle kroppe på basen (tænder: tjekket nedenfor er RØDT på basen).
# 3) Deploy-transaktionen: kataloget efter = frisk, funktionsretterne uændrede, data uændret; blokken to gange ændrer
#    intet, og hele db-rls.sql oveni ændrer hverken funktionsretter, politikker eller ACL.
# 4) Fuld db-verify på en anden, ens opgraderet base. Adfærden testes i tests/sql/test-person-purge.sh (review37_c2)
#    og tests/sql/test-person-purge-concurrent.sh (r37p11_3_gruppelaas).
# Kun lokalt/CI. Ved succes droppes de tre baser, scriptet selv oprettede (<db>_f, _p, _v); ved fejl står de tilbage.
set -euo pipefail
name=${1:?database}; base=${2:?base-commit}
dbf="${name}_f"; dbp="${name}_p"; dbv="${name}_v"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
for f in schema.sql db-rls.sql db-migrations.sql; do git show "$base:$f" > "$tmp/base-$f"; done
q() { env -u PGOPTIONS psql -X -q -v ON_ERROR_STOP=1 -d "$1" "${@:2}" >/dev/null; }
a() { env -u PGOPTIONS psql -X -At -v ON_ERROR_STOP=1 -d "$1" -c "$2"; }
fail() { echo "R37C2_UPGRADE_FAIL: $1" >&2; exit 1; }

# Deploy-området, som prod-runneren skærer det: migrationsblokken (skal stå sidst).
awk '$0=="-- BEGIN review37-c2" {p=1} p{print} $0=="-- END review37-c2" {p=0}' db-migrations.sql > "$tmp/deploy.sql"
[ "$(head -1 "$tmp/deploy.sql")" = '-- BEGIN review37-c2' ] && [ "$(tail -1 "$tmp/deploy.sql")" = '-- END review37-c2' ] \
  || fail "blokken review37-c2 mangler i db-migrations.sql"
[ "$(tail -1 db-migrations.sql)" = '-- END review37-c2' ] || fail "blokken review37-c2 skal stå sidst i db-migrations.sql"
# Kun sætninger i kolonne 0 (funktionskroppene er indrykket og må gerne indeholde INSERT/DELETE).
! grep -qiE '^(drop|alter|grant|revoke|insert into|update |delete from|truncate|create (table|index|policy))' "$tmp/deploy.sql" \
  || fail "migrationsblokken må kun rumme CREATE OR REPLACE FUNCTION"
[ "$(grep -c '^CREATE OR REPLACE FUNCTION' "$tmp/deploy.sql")" = 3 ] || fail "migrationsblokken skal rumme præcis tre funktioner"
deploy() { env -u PGOPTIONS psql -X -q -1 -v ON_ERROR_STOP=1 -d "$1" -f "$tmp/deploy.sql" 2>&1; }

kat() { env -u PGOPTIONS psql -X -Atq -v ON_ERROR_STOP=1 -d "$1" -f tests/sql/inspect-catalog-parity.sql > "$2"; }
facl() { a "$1" "SELECT coalesce(string_agg(l, ' ' ORDER BY l COLLATE \"C\"), '') FROM (
  SELECT p.oid::regprocedure::text||':'||r AS l FROM pg_proc p, (VALUES ('anon'),('authenticated'),('service_role')) v(r)
   WHERE p.pronamespace IN ('public'::regnamespace,'private'::regnamespace) AND has_function_privilege(r, p.oid, 'EXECUTE')) s"; }
pol() { a "$1" "SELECT l FROM (SELECT schemaname||'.'||tablename||'|'||policyname||'|'||cmd||'|'||roles::text||'|'||
  coalesce(qual,'')||'|'||coalesce(with_check,'') AS l FROM pg_policies WHERE schemaname IN ('public','private')
  UNION ALL SELECT n.nspname||'.'||c.relname||'|acl|'||coalesce(c.relacl::text,'NULL')||'|'||c.relrowsecurity::text
  FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN ('public','private') AND c.relkind IN ('r','v','m','S')) s
  ORDER BY l COLLATE \"C\""; }
data() { a "$1" "DO \$d\$ DECLARE r record; n bigint; BEGIN
  CREATE TEMP TABLE IF NOT EXISTS _c2_rt (t text, n bigint); TRUNCATE _c2_rt;
  FOR r IN SELECT c.oid::regclass AS rel FROM pg_class c WHERE c.relnamespace IN ('public'::regnamespace,'private'::regnamespace) AND c.relkind='r' LOOP
    EXECUTE format('SELECT count(*) FROM %s', r.rel) INTO n; INSERT INTO _c2_rt VALUES (r.rel::text, n);
  END LOOP; END \$d\$; SELECT md5(string_agg(t||'='||n, ',' ORDER BY t)) FROM _c2_rt"; }
# Tænder: »gammel,gammel,gammel« på basen, »ny,ny,ny« efter blokken (P9, P10, R37P11-3).
kroppe() { a "$1" "SELECT concat_ws(',',
  CASE WHEN position(\$q\$set_config('statement_timeout'\$q\$ IN pg_get_functiondef('public.red_slet_person_helt(bigint,text)'::regprocedure))>0 THEN 'gammel' ELSE 'ny' END,
  CASE WHEN position('kun_id' IN pg_get_functiondef('private.person_purge_kontrol(bigint,jsonb)'::regprocedure))>0 THEN 'ny' ELSE 'gammel' END,
  CASE WHEN position('WITH RECURSIVE grp(pid)' IN pg_get_functiondef('public.red_slet_person(bigint)'::regprocedure))>0 THEN 'ny' ELSE 'gammel' END)"; }
build_start() { createdb "$1"; q "$1" -f tests/sql/evidence-promotion-bootstrap.sql
  q "$1" -c 'CREATE EXTENSION IF NOT EXISTS dblink WITH SCHEMA extensions'; }

# 1) Frisk reference.
build_start "$dbf"; q "$dbf" -f schema.sql; q "$dbf" -f db-rls.sql
kat "$dbf" "$tmp/kat-fresh.txt"
facl_fresh=$(facl "$dbf")
[ "$(kroppe "$dbf")" = "ny,ny,ny" ] || fail "schema.sql har ikke ceremoni 2's kroppe: $(kroppe "$dbf")"

# 2) Prod-formet base (efter ceremoni 1). Prods globale række for postgres er {postgres=X} (db-rls.sql kørt som
# postgres); lokalt kører filen som en anden superbruger, så den gøres eksplicit her (i CI en no-op).
build_prod() { build_start "$1"
  for f in base-schema.sql base-db-migrations.sql base-db-migrations.sql base-db-rls.sql; do q "$1" -f "$tmp/$f"; done
  q "$1" -c "ALTER DEFAULT PRIVILEGES FOR ROLE postgres REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC"; }
build_prod "$dbp"
[ "$(kroppe "$dbp")" = "gammel,gammel,gammel" ] || fail "basen $base har allerede (dele af) ceremoni 2: $(kroppe "$dbp")"
facl_foer=$(facl "$dbp")
data_foer=$(data "$dbp")

# 3) Deploy-transaktionen, derefter det hele igen.
out=$(deploy "$dbp") || { echo "$out" >&2; fail "deploy-transaktionen fejlede"; }
[ "$(kroppe "$dbp")" = "ny,ny,ny" ] || fail "blokken gav ikke de nye kroppe: $(kroppe "$dbp")"
[ "$(data "$dbp")" = "$data_foer" ] || fail "rækketal ændret af blokken"
kat "$dbp" "$tmp/kat-efter.txt"
bash tests/sql/check-catalog-parity.sh "$tmp/kat-fresh.txt" "$tmp/kat-efter.txt" >/dev/null \
  || { bash tests/sql/check-catalog-parity.sh "$tmp/kat-fresh.txt" "$tmp/kat-efter.txt" || true; fail "kataloget efter blokken ≠ frisk schema.sql"; }
facl_efter=$(facl "$dbp")
[ "$facl_efter" = "$facl_foer" ] || { diff <(tr ' ' '\n' <<<"$facl_foer") <(tr ' ' '\n' <<<"$facl_efter") >&2 || true
  fail "blokken ændrede funktionsretter"; }
[ "$facl_efter" = "$facl_fresh" ] || { diff <(tr ' ' '\n' <<<"$facl_fresh") <(tr ' ' '\n' <<<"$facl_efter") >&2 || true
  fail "funktionsretterne efter blokken ≠ frisk base"; }
out=$(deploy "$dbp") || { echo "$out" >&2; fail "anden deploy-transaktion fejlede"; }
kat "$dbp" "$tmp/kat-efter2.txt"
cmp -s "$tmp/kat-efter.txt" "$tmp/kat-efter2.txt" || fail "blokken to gange ændrer kataloget"
pol_foer=$(pol "$dbp")
[ "$(grep -c '|' <<<"$pol_foer")" -ge 100 ] || fail "politik-snapshottet er tomt"
q "$dbp" -1 -f db-rls.sql
[ "$(pol "$dbp")" = "$pol_foer" ] || fail "hele db-rls.sql oveni ændrer politikker/ACL (deploy-området er ufuldstændigt)"
[ "$(facl "$dbp")" = "$facl_efter" ] || fail "hele db-rls.sql oveni ændrer funktionsretterne"

# 4) Fuld db-verify på en anden, ens opgraderet base.
build_prod "$dbv"
out=$(deploy "$dbv") || { echo "$out" >&2; fail "deploy-transaktionen fejlede på verify-basen"; }
q "$dbv" -f tests/sql/run-db-verify-disposable.sql
dropdb "$dbf"; dropdb "$dbp"; dropdb "$dbv"
echo R37C2_UPGRADE_OK
