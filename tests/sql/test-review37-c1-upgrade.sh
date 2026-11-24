#!/usr/bin/env bash
# Review 37 ceremoni 1 (#397: Y8, Y10, S6, S9, R37S8-2-3). Prods deploy-form: blokken `-- BEGIN review37-c1` sidst i
# db-migrations.sql PLUS DO-blokken $review37_c1_execute$ fra db-rls.sql (ikke hele db-rls.sql, som tager ACCESS EXCLUSIVE
# på læsernes tabeller), i ÉN psql-transaktion (-1).
# 1) Frisk reference (bootstrap + dblink + schema.sql + db-rls.sql): hele kataloget (tests/sql/inspect-catalog-parity.sql).
# 2) Prod-formet base (2. arg; CI pinner main efter R37S8-2 = prods SQL): basens skema + migrationer to gange + rls, plus
#    Supabase-formen for funktionsretter: EXECUTE givet DIREKTE til anon og authenticated (ikke kun via PUBLIC) på de ni
#    funktioner, blokken fjerner — så blokkens REVOKE skal navngive rollerne. Verify-enheden c1 er RØD på basen.
# 3) Deploy-transaktionen: kataloget efter = frisk, data uændret; det hele en gang til ændrer intet, og hele db-rls.sql
#    oveni ændrer hverken funktionsretter, politikker eller ACL.
# 4) Enheden er GRØN på den opgraderede base; fuld db-verify på en anden, ens opgraderet base.
# Kun lokalt/CI. Ved succes droppes de tre baser, scriptet selv oprettede (<db>_f, _p, _v); ved fejl står de tilbage.
set -euo pipefail
name=${1:?database}; base=${2:?base-commit}
dbf="${name}_f"; dbp="${name}_p"; dbv="${name}_v"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
for f in schema.sql db-rls.sql db-migrations.sql; do git show "$base:$f" > "$tmp/base-$f"; done
q() { env -u PGOPTIONS psql -X -q -v ON_ERROR_STOP=1 -d "$1" "${@:2}" >/dev/null; }
a() { env -u PGOPTIONS psql -X -At -v ON_ERROR_STOP=1 -d "$1" -c "$2"; }
fail() { echo "R37C1_UPGRADE_FAIL: $1" >&2; exit 1; }

# Deploy-området, som prod-runneren skærer det: migrationsblokken (skal stå sidst) + DO-blokken fra db-rls.sql.
awk '$0=="-- BEGIN review37-c1" {p=1} p{print} $0=="-- END review37-c1" {p=0}' db-migrations.sql > "$tmp/blok.sql"
[ "$(head -1 "$tmp/blok.sql")" = '-- BEGIN review37-c1' ] && [ "$(tail -1 "$tmp/blok.sql")" = '-- END review37-c1' ] \
  || fail "blokken review37-c1 mangler i db-migrations.sql"
[ "$(tail -1 db-migrations.sql)" = '-- END review37-c1' ] || fail "blokken review37-c1 skal stå sidst i db-migrations.sql"
awk '$0=="DO $review37_c1_execute$" {p=1} p{print} $0=="$review37_c1_execute$;" {p=0}' db-rls.sql > "$tmp/rls.sql"
[ "$(head -1 "$tmp/rls.sql")" = 'DO $review37_c1_execute$' ] && [ "$(tail -1 "$tmp/rls.sql")" = '$review37_c1_execute$;' ] \
  || fail "DO-blokken \$review37_c1_execute\$ mangler i db-rls.sql"
! grep -qiwE 'create|drop|policy|grant|alter|insert into|update [a-z_.]+ set|delete from' "$tmp/rls.sql" \
  || fail "DO-blokken \$review37_c1_execute\$ må kun rumme REVOKE"
# Kun sætninger i kolonne 0 (funktionskroppen er indrykket og må gerne indeholde INSERT).
! grep -qiE '^(drop|alter table|insert into|update |delete from|truncate)' "$tmp/blok.sql" \
  || fail "migrationsblokken må hverken droppe, ændre tabeller eller skrive data"
cat "$tmp/blok.sql" "$tmp/rls.sql" > "$tmp/deploy.sql"
deploy() { env -u PGOPTIONS psql -X -q -1 -v ON_ERROR_STOP=1 -d "$1" -f "$tmp/deploy.sql" 2>&1; }
awk '$0=="-- BEGIN-VERIFY c1" {p=1} p{print} $0=="-- END-VERIFY c1" {p=0}' db-verify.sql > "$tmp/v-unit.sql"
[ "$(head -1 "$tmp/v-unit.sql")" = "-- BEGIN-VERIFY c1" ] || fail "verify-enheden c1 mangler i db-verify.sql"

kat() { env -u PGOPTIONS psql -X -Atq -v ON_ERROR_STOP=1 -d "$1" -f tests/sql/inspect-catalog-parity.sql > "$2"; }
# Funktionsretter for PUBLIC/anon/authenticated på public-funktioner (katalog-udtrækket bærer ikke funktions-ACL for anon).
facl() { a "$1" "SELECT coalesce(string_agg(l, ' ' ORDER BY l COLLATE \"C\"), '') FROM (
  SELECT p.oid::regprocedure::text||':'||r AS l FROM pg_proc p, (VALUES ('anon'),('authenticated')) v(r)
   WHERE p.pronamespace='public'::regnamespace AND has_function_privilege(r, p.oid, 'EXECUTE')) s"; }
pol() { a "$1" "SELECT l FROM (SELECT schemaname||'.'||tablename||'|'||policyname||'|'||cmd||'|'||roles::text||'|'||
  coalesce(qual,'')||'|'||coalesce(with_check,'') AS l FROM pg_policies WHERE schemaname IN ('public','private')
  UNION ALL SELECT n.nspname||'.'||c.relname||'|acl|'||coalesce(c.relacl::text,'NULL')||'|'||c.relrowsecurity::text
  FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN ('public','private') AND c.relkind IN ('r','v','m','S')) s
  ORDER BY l COLLATE \"C\""; }
data() { a "$1" "DO \$d\$ DECLARE r record; n bigint; BEGIN
  CREATE TEMP TABLE IF NOT EXISTS _c1_rt (t text, n bigint); TRUNCATE _c1_rt;
  FOR r IN SELECT c.oid::regclass AS rel FROM pg_class c WHERE c.relnamespace IN ('public'::regnamespace,'private'::regnamespace) AND c.relkind='r' LOOP
    EXECUTE format('SELECT count(*) FROM %s', r.rel) INTO n; INSERT INTO _c1_rt VALUES (r.rel::text, n);
  END LOOP; END \$d\$; SELECT md5(string_agg(t||'='||n, ',' ORDER BY t)) FROM _c1_rt"; }
unit() { local out
  if out=$(env -u PGOPTIONS psql -X -v ON_ERROR_STOP=1 -d "$1" -f "$tmp/v-unit.sql" 2>&1); then
    [ -z "$2" ] || { echo "$out" >&2; fail "c1 er grøn på basen $base (forventede: $2)"; }
    grep -q "NOTICE:  OK: review37 c1" <<<"$out" || { echo "$out" >&2; fail "c1: OK-linjen mangler"; }
  else
    [ -n "$2" ] || { echo "$out" >&2; fail "c1 fejlede efter blokken"; }
    grep -qF -- "$2" <<<"$out" || { echo "$out" >&2; fail "c1 fejlede af en anden grund end: $2"; }
  fi; }
build_start() { createdb "$1"; q "$1" -f tests/sql/evidence-promotion-bootstrap.sql
  q "$1" -c 'CREATE EXTENSION IF NOT EXISTS dblink WITH SCHEMA extensions'; }
NI="public.log_change(), public.trg_lineage_prevent_cycle(), public.trg_regen_from_assertion(),
  public.trg_regen_from_conclusion(), public.trg_regen_from_external_id(), public.trg_regen_mentions(),
  public.regen_person_visning(bigint), public._regen_mentions_for(text,bigint), public.parse_mentions(text)"

# 1) Frisk reference.
build_start "$dbf"; q "$dbf" -f schema.sql; q "$dbf" -f db-rls.sql
kat "$dbf" "$tmp/kat-fresh.txt"
facl_fresh=$(facl "$dbf")
unit "$dbf" ""

# 2) Prod-formet base; enheden er rød på den.
build_prod() { build_start "$1"
  for f in base-schema.sql base-db-migrations.sql base-db-migrations.sql base-db-rls.sql; do q "$1" -f "$tmp/$f"; done
  q "$1" -c "GRANT EXECUTE ON FUNCTION $NI TO anon, authenticated"; }
build_prod "$dbp"
[ "$(a "$dbp" "SELECT has_function_privilege('anon','public.regen_person_visning(bigint)','EXECUTE')::text")" = true ] \
  || fail "basen giver ikke anon EXECUTE på regen_person_visning"
[ -z "$(a "$dbp" "SELECT to_regclass('public.ix_fact_type_subjekt')")" ] || fail "basen har allerede Y10-indekset"
unit "$dbp" "FEJL: review37 c1 S9 —"
data_foer=$(data "$dbp")

# 3) Deploy-transaktionen, derefter det hele igen.
out=$(deploy "$dbp") || { echo "$out" >&2; fail "deploy-transaktionen fejlede"; }
[ "$(data "$dbp")" = "$data_foer" ] || fail "rækketal ændret af blokken"
kat "$dbp" "$tmp/kat-efter.txt"
bash tests/sql/check-catalog-parity.sh "$tmp/kat-fresh.txt" "$tmp/kat-efter.txt" >/dev/null \
  || { bash tests/sql/check-catalog-parity.sh "$tmp/kat-fresh.txt" "$tmp/kat-efter.txt" || true; fail "kataloget efter blokken ≠ frisk schema.sql"; }
facl_efter=$(facl "$dbp")
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

# 4) Adfærd på den opgraderede base; fuld db-verify på en anden, ens opgraderet base.
unit "$dbp" ""
build_prod "$dbv"
out=$(deploy "$dbv") || { echo "$out" >&2; fail "deploy-transaktionen fejlede på verify-basen"; }
q "$dbv" -f tests/sql/run-db-verify-disposable.sql
dropdb "$dbf"; dropdb "$dbp"; dropdb "$dbv"
echo R37C1_UPGRADE_OK
