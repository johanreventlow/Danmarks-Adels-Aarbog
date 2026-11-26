#!/usr/bin/env bash
# Review 37 ceremoni 4 (#397 R37P11-2: red_set_levende). Prods deploy-form: blokkene fra `-- BEGIN review37-r37p11-2`
# til den sidste blok i db-migrations.sql alene, i ÉN psql-transaktion (-1). Blokken skaber én ny funktion og giver
# authenticated EXECUTE på den (REVOKE + GRANT i blokken; db-rls.sql's allow-liste nævner den også).
# 1) Frisk reference (bootstrap + dblink + schema.sql + db-rls.sql): hele kataloget (tests/sql/inspect-catalog-parity.sql).
# 2) Prod-formet base (2. arg; CI pinner main efter ceremoni 3 = prods SQL): basens skema + migrationer to gange + rls.
#    Funktionen findes ikke på basen (tænder: tjekket nedenfor er RØDT på basen).
# 3) Deploy-transaktionen: kataloget efter = frisk, funktionsretterne = frisk og præcis én ny ret
#    (red_set_levende:authenticated), data uændret; blokken to gange ændrer intet, og hele db-rls.sql oveni ændrer
#    hverken funktionsretter, politikker eller ACL.
# 4) Fuld db-verify på en anden, ens opgraderet base (verify-enheden r37p11-2 tester adfærden).
# Kun lokalt/CI. Ved succes droppes de tre baser, scriptet selv oprettede (<db>_f, _p, _v); ved fejl står de tilbage.
set -euo pipefail
name=${1:?database}; base=${2:?base-commit}
dbf="${name}_f"; dbp="${name}_p"; dbv="${name}_v"
FRA='-- BEGIN review37-r37p11-2'; TIL='-- END review37-r37p11-2'; N_FN=1
NY_RET='red_set_levende(bigint,boolean):authenticated'  # regprocedure::text uden public. (search_path)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
for f in schema.sql db-rls.sql db-migrations.sql; do git show "$base:$f" > "$tmp/base-$f"; done
q() { env -u PGOPTIONS psql -X -q -v ON_ERROR_STOP=1 -d "$1" "${@:2}" >/dev/null; }
a() { env -u PGOPTIONS psql -X -At -v ON_ERROR_STOP=1 -d "$1" -c "$2"; }
fail() { echo "R37C4_UPGRADE_FAIL: $1" >&2; exit 1; }

# Deploy-området, som prod-runneren skærer det (skal stå sidst).
awk -v fra="$FRA" -v til="$TIL" '$0==fra {p=1} p{print} $0==til {p=0}' db-migrations.sql > "$tmp/deploy.sql"
[ "$(head -1 "$tmp/deploy.sql")" = "$FRA" ] && [ "$(tail -1 "$tmp/deploy.sql")" = "$TIL" ] \
  || fail "deploy-området $FRA … $TIL mangler i db-migrations.sql"
[ "$(tail -1 db-migrations.sql)" = "$TIL" ] || fail "deploy-området skal stå sidst i db-migrations.sql"
# Kun sætninger i kolonne 0 (funktionskroppene er indrykket): funktioner og retterne på den nye funktion.
! grep -iE '^(drop|alter|grant|revoke|insert into|update |delete from|truncate|create (table|index|policy))' "$tmp/deploy.sql" \
  | grep -vxF -e 'REVOKE ALL ON FUNCTION public.red_set_levende(bigint,boolean) FROM PUBLIC,anon,authenticated,service_role;' \
              -e 'GRANT EXECUTE ON FUNCTION public.red_set_levende(bigint,boolean) TO authenticated;' | grep -q . \
  || fail "deploy-området må kun rumme CREATE OR REPLACE FUNCTION og red_set_levende's REVOKE/GRANT"
[ "$(grep -c '^CREATE OR REPLACE FUNCTION' "$tmp/deploy.sql")" = "$N_FN" ] || fail "deploy-området skal rumme præcis $N_FN funktion(er)"
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
  CREATE TEMP TABLE IF NOT EXISTS _r37c4_rt (t text, n bigint); TRUNCATE _r37c4_rt;
  FOR r IN SELECT c.oid::regclass AS rel FROM pg_class c WHERE c.relnamespace IN ('public'::regnamespace,'private'::regnamespace) AND c.relkind='r' LOOP
    EXECUTE format('SELECT count(*) FROM %s', r.rel) INTO n; INSERT INTO _r37c4_rt VALUES (r.rel::text, n);
  END LOOP; END \$d\$; SELECT md5(string_agg(t||'='||n, ',' ORDER BY t)) FROM _r37c4_rt"; }
# Tænder: »gammel« på basen (funktionen findes ikke), »ny« efter blokken.
kroppe() { a "$1" "SELECT CASE WHEN to_regprocedure('public.red_set_levende(bigint,boolean)') IS NOT NULL THEN 'ny' ELSE 'gammel' END"; }
build_start() { createdb "$1"; q "$1" -f tests/sql/evidence-promotion-bootstrap.sql
  q "$1" -c 'CREATE EXTENSION IF NOT EXISTS dblink WITH SCHEMA extensions'; }

# 1) Frisk reference.
build_start "$dbf"; q "$dbf" -f schema.sql; q "$dbf" -f db-rls.sql
kat "$dbf" "$tmp/kat-fresh.txt"
facl_fresh=$(facl "$dbf")
[ "$(kroppe "$dbf")" = "ny" ] || fail "schema.sql har ikke ceremoni 4's funktion: $(kroppe "$dbf")"
grep -qwF "$NY_RET" <<<"$(tr ' ' '\n' <<<"$facl_fresh")" || fail "frisk base giver ikke $NY_RET"
! tr ' ' '\n' <<<"$facl_fresh" | grep -q '^red_set_levende(bigint,boolean):\(anon\|service_role\)$' \
  || fail "frisk base giver red_set_levende til anon eller service_role"

# 2) Prod-formet base (efter ceremoni 3). Prods globale række for postgres er {postgres=X} (db-rls.sql kørt som
# postgres); lokalt kører filen som en anden superbruger, så den gøres eksplicit her (i CI en no-op).
build_prod() { build_start "$1"
  for f in base-schema.sql base-db-migrations.sql base-db-migrations.sql base-db-rls.sql; do q "$1" -f "$tmp/$f"; done
  q "$1" -c "ALTER DEFAULT PRIVILEGES FOR ROLE postgres REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC"; }
build_prod "$dbp"
[ "$(kroppe "$dbp")" = "gammel" ] || fail "basen $base har allerede ceremoni 4: $(kroppe "$dbp")"
facl_foer=$(facl "$dbp")
data_foer=$(data "$dbp")

# 3) Deploy-transaktionen, derefter det hele igen.
out=$(deploy "$dbp") || { echo "$out" >&2; fail "deploy-transaktionen fejlede"; }
[ "$(kroppe "$dbp")" = "ny" ] || fail "blokken gav ikke den nye funktion: $(kroppe "$dbp")"
[ "$(data "$dbp")" = "$data_foer" ] || fail "rækketal ændret af blokken"
kat "$dbp" "$tmp/kat-efter.txt"
bash tests/sql/check-catalog-parity.sh "$tmp/kat-fresh.txt" "$tmp/kat-efter.txt" >/dev/null \
  || { bash tests/sql/check-catalog-parity.sh "$tmp/kat-fresh.txt" "$tmp/kat-efter.txt" || true; fail "kataloget efter blokken ≠ frisk schema.sql"; }
facl_efter=$(facl "$dbp")
nye=$(comm -13 <(tr ' ' '\n' <<<"$facl_foer" | LC_ALL=C sort) <(tr ' ' '\n' <<<"$facl_efter" | LC_ALL=C sort) | paste -sd' ' -)
fjernet=$(comm -23 <(tr ' ' '\n' <<<"$facl_foer" | LC_ALL=C sort) <(tr ' ' '\n' <<<"$facl_efter" | LC_ALL=C sort) | paste -sd' ' -)
[ "$nye" = "$NY_RET" ] && [ -z "$fjernet" ] || fail "blokken skulle give præcis én ny ret ($NY_RET); nye=[$nye] fjernet=[$fjernet]"
[ "$facl_efter" = "$facl_fresh" ] || { diff <(tr ' ' '\n' <<<"$facl_fresh") <(tr ' ' '\n' <<<"$facl_efter") >&2 || true
  fail "funktionsretterne efter blokken ≠ frisk base"; }
out=$(deploy "$dbp") || { echo "$out" >&2; fail "anden deploy-transaktion fejlede"; }
kat "$dbp" "$tmp/kat-efter2.txt"
cmp -s "$tmp/kat-efter.txt" "$tmp/kat-efter2.txt" || fail "blokken to gange ændrer kataloget"
[ "$(facl "$dbp")" = "$facl_efter" ] || fail "blokken to gange ændrer funktionsretterne"
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
echo R37C4_UPGRADE_OK
