#!/usr/bin/env bash
# Linjernes adelsnavn (plan docs/superpowers/plans/2026-11-26-linjernes-adelsnavn.md). Prods deploy-form: blokken
# `-- ===== adelsnavn-faktatype =====` … `-- END adelsnavn-faktatype` sidst i db-migrations.sql alene (kun vocab-data,
# ingen ACL-ændringer, så ingen db-rls-DO-blok), i ÉN psql-transaktion (-1).
# 1) Frisk reference (bootstrap + dblink + schema.sql + db-rls.sql): hele kataloget; vocab-rækken findes.
# 2) Prod-formet base (2. arg = prods SQL): basens skema + migrationer to gange + rls. Tænder: rækken mangler på basen.
# 3) Deploy-transaktionen: kataloget efter = frisk; kun vocab ændres (+1); funktionsretter uændrede; det hele en gang
#    til ændrer intet, og hele db-rls.sql oveni ændrer hverken politikker, ACL eller funktionsretter.
# 4) Fuld db-verify på en anden, ens opgraderet base (OK: adelsnavn-faktatype).
# Kun lokalt/CI. Ved succes droppes de tre baser, scriptet selv oprettede (<db>_f, _p, _v); ved fejl står de tilbage.
set -euo pipefail
name=${1:?database}; base=${2:?base-commit}
dbf="${name}_f"; dbp="${name}_p"; dbv="${name}_v"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
for f in schema.sql db-rls.sql db-migrations.sql; do git show "$base:$f" > "$tmp/base-$f"; done
q() { env -u PGOPTIONS psql -X -q -v ON_ERROR_STOP=1 -d "$1" "${@:2}" >/dev/null; }
a() { env -u PGOPTIONS psql -X -At -v ON_ERROR_STOP=1 -d "$1" -c "$2"; }
fail() { echo "ADELSNAVN_UPGRADE_FAIL: $1" >&2; exit 1; }

# Deploy-området, som prod-runneren skærer det: migrationsblokken (skal stå sidst).
awk '$0=="-- ===== adelsnavn-faktatype =====" {p=1} p{print} $0=="-- END adelsnavn-faktatype" {p=0}' db-migrations.sql > "$tmp/deploy.sql"
[ "$(head -1 "$tmp/deploy.sql")" = '-- ===== adelsnavn-faktatype =====' ] && [ "$(tail -1 "$tmp/deploy.sql")" = '-- END adelsnavn-faktatype' ] \
  || fail "blokken adelsnavn-faktatype mangler i db-migrations.sql"
[ "$(tail -1 db-migrations.sql)" = '-- END adelsnavn-faktatype' ] || fail "blokken adelsnavn-faktatype skal stå sidst i db-migrations.sql"
# Kun vocab-data: ingen DDL, rettigheder eller skrivning uden for vocab.
! grep -qiE '^(drop|alter|grant|revoke|update |delete from|truncate|create )' "$tmp/deploy.sql" \
  || fail "blokken må kun indsætte i vocab"
[ "$(grep -ciE '^insert into' "$tmp/deploy.sql")" = 1 ] && grep -qE '^INSERT INTO vocab ' "$tmp/deploy.sql" \
  || fail "blokken skal rumme præcis én INSERT INTO vocab"

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
# Rækketal pr. tabel undtagen vocab (vocab tælles for sig).
data() { a "$1" "DO \$d\$ DECLARE r record; n bigint; BEGIN
  CREATE TEMP TABLE IF NOT EXISTS _adelsnavn_rt (t text, n bigint); TRUNCATE _adelsnavn_rt;
  FOR r IN SELECT c.oid::regclass AS rel FROM pg_class c WHERE c.relnamespace IN ('public'::regnamespace,'private'::regnamespace)
             AND c.relkind='r' AND c.oid <> 'public.vocab'::regclass LOOP
    EXECUTE format('SELECT count(*) FROM %s', r.rel) INTO n; INSERT INTO _adelsnavn_rt VALUES (r.rel::text, n);
  END LOOP; END \$d\$; SELECT md5(string_agg(t||'='||n, ',' ORDER BY t)) FROM _adelsnavn_rt"; }
vocab_n() { a "$1" "SELECT count(*) FROM vocab"; }
har() { a "$1" "SELECT EXISTS (SELECT 1 FROM vocab WHERE scheme='faktatype' AND code='adelsnavn')"; }
build_start() { createdb "$1"; q "$1" -f tests/sql/evidence-promotion-bootstrap.sql
  q "$1" -c 'CREATE EXTENSION IF NOT EXISTS dblink WITH SCHEMA extensions'; }

# 1) Frisk reference.
build_start "$dbf"; q "$dbf" -f schema.sql; q "$dbf" -f db-rls.sql
kat "$dbf" "$tmp/kat-fresh.txt"
facl_fresh=$(facl "$dbf")
[ "$(har "$dbf")" = "t" ] || fail "schema.sql mangler vocab-rækken (faktatype, adelsnavn)"
# 2) Prod-formet base. Prods globale række for postgres er {postgres=X} (db-rls.sql kørt som postgres); lokalt kører
# filen som en anden superbruger, så den gøres eksplicit her (i CI en no-op).
build_prod() { build_start "$1"
  for f in base-schema.sql base-db-migrations.sql base-db-migrations.sql base-db-rls.sql; do q "$1" -f "$tmp/$f"; done
  q "$1" -c "ALTER DEFAULT PRIVILEGES FOR ROLE postgres REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC"; }
build_prod "$dbp"
[ "$(har "$dbp")" = "f" ] || fail "basen $base har allerede adelsnavn"
facl_foer=$(facl "$dbp"); data_foer=$(data "$dbp"); vocab_foer=$(vocab_n "$dbp")
# 3) Deploy-transaktionen, derefter det hele igen.
out=$(deploy "$dbp") || { echo "$out" >&2; fail "deploy-transaktionen fejlede"; }
[ "$(har "$dbp")" = "t" ] || fail "blokken gav ikke vocab-rækken"
[ "$(vocab_n "$dbp")" = "$((vocab_foer + 1))" ] || fail "vocab ændret med andet end +1: $vocab_foer → $(vocab_n "$dbp")"
[ "$(data "$dbp")" = "$data_foer" ] || fail "rækketal uden for vocab ændret af blokken"
kat "$dbp" "$tmp/kat-efter.txt"
bash tests/sql/check-catalog-parity.sh "$tmp/kat-fresh.txt" "$tmp/kat-efter.txt" >/dev/null \
  || { bash tests/sql/check-catalog-parity.sh "$tmp/kat-fresh.txt" "$tmp/kat-efter.txt" || true; fail "kataloget efter blokken ≠ frisk schema.sql"; }
facl_efter=$(facl "$dbp")
[ "$facl_efter" = "$facl_foer" ] || fail "blokken ændrede funktionsretter"
[ "$facl_efter" = "$facl_fresh" ] || { diff <(tr ' ' '\n' <<<"$facl_fresh") <(tr ' ' '\n' <<<"$facl_efter") >&2 || true
  fail "funktionsretterne efter blokken ≠ frisk base"; }
out=$(deploy "$dbp") || { echo "$out" >&2; fail "anden deploy-transaktion fejlede"; }
[ "$(vocab_n "$dbp")" = "$((vocab_foer + 1))" ] || fail "blokken to gange tilføjer mere end én række"
kat "$dbp" "$tmp/kat-efter2.txt"
cmp -s "$tmp/kat-efter.txt" "$tmp/kat-efter2.txt" || fail "blokken to gange ændrer kataloget"
pol_foer=$(pol "$dbp")
[ "$(grep -c '|' <<<"$pol_foer")" -ge 100 ] || fail "politik-snapshottet er tomt"
q "$dbp" -1 -f db-rls.sql
[ "$(pol "$dbp")" = "$pol_foer" ] || fail "hele db-rls.sql oveni ændrer politikker/ACL"
[ "$(facl "$dbp")" = "$facl_efter" ] || fail "hele db-rls.sql oveni ændrer funktionsretterne"
# 4) Fuld db-verify på en anden, ens opgraderet base.
build_prod "$dbv"
out=$(deploy "$dbv") || { echo "$out" >&2; fail "deploy-transaktionen fejlede på verify-basen"; }
q "$dbv" -f tests/sql/run-db-verify-disposable.sql
dropdb "$dbf"; dropdb "$dbp"; dropdb "$dbv"
echo ADELSNAVN_UPGRADE_OK
