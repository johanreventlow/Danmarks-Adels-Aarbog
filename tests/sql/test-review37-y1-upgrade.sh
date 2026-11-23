#!/usr/bin/env bash
# Review 37 Y1 + D8 (#397): personkontrol-gitteret i udsnit. Prods deploy-form: KUN blokken review37-y1 i
# db-migrations.sql (ny red_person_grid_udsnit med eksplicit ACL; red_person_grid() og red_ret_ocr_felt med samme
# signatur og returtype) i én psql-transaktion (-1). db-rls.sql deployes ikke: blokken bærer selv den nye funktions ACL,
# og hele db-rls.sql oveni må intet ændre (trin 3).
# 1) Frisk reference (bootstrap + dblink + schema.sql + db-rls.sql): kroppe (sha256 af pg_get_functiondef), proconfig og
#    ACL for blokkens funktioner + hele kataloget (tests/sql/inspect-catalog-parity.sql).
# 2) Prod-formet base (2. arg; CI pinner 8bc9acd4 = prods SQL efter D9): basens skema + migrationer to gange + rls.
#    Basen skal mangle udsnittet: tests/sql/test-review37-y1-udsnit.sql er RØD (den ruller tilbage, så samme base kan
#    bruges videre).
# 3) Deploy-transaktionen: kroppe/ACL = frisk, katalog-delta = præcis de tre funktioner, hele kataloget = frisk, data
#    uændret. Det hele en gang til ændrer intet, og hele db-rls.sql derefter ændrer hverken kroppe, ACL eller politikker.
# 4) Udsnitstesten er GRØN på den opgraderede base; fuld db-verify (inkl. plan_cache_mode-vagten) på en anden, ens
#    opgraderet base.
# Kun lokalt/CI. Ved succes droppes de tre baser, scriptet selv oprettede (<db>_f, _p, _v); ved fejl står de tilbage.
set -euo pipefail
name=${1:?database}; base=${2:?base-commit}
dbf="${name}_f"; dbp="${name}_p"; dbv="${name}_v"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
for f in schema.sql db-rls.sql db-migrations.sql; do git show "$base:$f" > "$tmp/base-$f"; done
q() { env -u PGOPTIONS psql -X -q -v ON_ERROR_STOP=1 -d "$1" "${@:2}" >/dev/null; }
a() { env -u PGOPTIONS psql -X -At -v ON_ERROR_STOP=1 -d "$1" -c "$2"; }
fail() { echo "R37Y1_UPGRADE_FAIL: $1" >&2; exit 1; }

# Deploy-området, som prod-runneren skærer det.
awk '$0=="-- BEGIN review37-y1" {p=1} p{print} $0=="-- END review37-y1" {p=0}' db-migrations.sql > "$tmp/blok.sql"
[ "$(head -1 "$tmp/blok.sql")" = "-- BEGIN review37-y1" ] && [ "$(tail -1 "$tmp/blok.sql")" = "-- END review37-y1" ] \
  || fail "blokken review37-y1 mangler eller er ikke afsluttet"
[ "$(tail -1 db-migrations.sql)" = "-- END review37-y1" ] \
  || fail "blokken review37-y1 skal stå sidst i db-migrations.sql (funktionerne defineres flere gange i filen)"
names=$( { grep -ioE '^CREATE OR REPLACE FUNCTION [a-z_.]+\(' "$tmp/blok.sql" || true; } \
  | sed -E 's/.*[Ff][Uu][Nn][Cc][Tt][Ii][Oo][Nn] ([a-z_.]+)\(/\1/; /\./!s/^/public./' | sort -u | tr '\n' ' ')
[ "$names" = "public.red_person_grid public.red_person_grid_udsnit public.red_ret_ocr_felt " ] \
  || fail "forventede præcis tre funktioner i blokken, fandt: $names"
list=$(for n in $names; do printf "'%s'," "$n"; done); list=${list%,}
deploy() { env -u PGOPTIONS psql -X -q -1 -v ON_ERROR_STOP=1 -d "$1" -f "$tmp/blok.sql" 2>&1; }
sha() { a "$1" "SELECT l FROM (SELECT p.oid::regprocedure::text||'|'||encode(extensions.digest(convert_to(pg_get_functiondef(p.oid),'UTF8'),'sha256'),'hex')
  ||'|'||coalesce(p.proconfig::text,'NULL')||'|'||coalesce(p.proacl::text,'NULL') AS l FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname||'.'||p.proname IN ($list)) s ORDER BY l COLLATE \"C\""; }
pol() { a "$1" "SELECT l FROM (SELECT schemaname||'.'||tablename||'|'||policyname||'|'||cmd||'|'||roles::text||'|'||
  coalesce(qual,'')||'|'||coalesce(with_check,'') AS l FROM pg_policies WHERE schemaname IN ('public','private')
  UNION ALL SELECT n.nspname||'.'||c.relname||'|acl|'||coalesce(c.relacl::text,'NULL')||'|'||c.relrowsecurity::text
  FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN ('public','private') AND c.relkind IN ('r','v','m')) s
  ORDER BY l COLLATE \"C\""; }
kat() { env -u PGOPTIONS psql -X -Atq -v ON_ERROR_STOP=1 -d "$1" -f tests/sql/inspect-catalog-parity.sql > "$2"; }
# Data i de tabeller, funktionerne læser eller (red_ret_ocr_felt) skriver, + change_set-antallet.
data() { a "$1" "SELECT string_agg(t||'='||h, ' ' ORDER BY t) FROM (
  SELECT 'person' t, md5(coalesce(string_agg(to_jsonb(x)::text, ',' ORDER BY x.id),'')) h FROM person x
  UNION ALL SELECT 'assertion', md5(coalesce(string_agg(to_jsonb(x)::text, ',' ORDER BY x.id),'')) FROM assertion x
  UNION ALL SELECT 'conclusion', md5(coalesce(string_agg(to_jsonb(x)::text, ',' ORDER BY x.id),'')) FROM conclusion x
  UNION ALL SELECT 'import_korrektion', md5(coalesce(string_agg(to_jsonb(x)::text, ',' ORDER BY x.import_key,x.record_key,x.felt),''))
    FROM import_korrektion x
  UNION ALL SELECT 'change_set', count(*)::text FROM change_set) s"; }
udsnit() { env -u PGOPTIONS psql -X -v ON_ERROR_STOP=1 -d "$1" -f tests/sql/test-review37-y1-udsnit.sql 2>&1; }
build_start() { createdb "$1"; q "$1" -f tests/sql/evidence-promotion-bootstrap.sql
  q "$1" -c 'CREATE EXTENSION IF NOT EXISTS dblink WITH SCHEMA extensions'; }

# 1) Frisk reference.
build_start "$dbf"; q "$dbf" -f schema.sql; q "$dbf" -f db-rls.sql
fresh=$(sha "$dbf"); kat "$dbf" "$tmp/kat-fresh.txt"
[ "$(wc -l <<<"$fresh")" -eq 3 ] || fail "referencen mangler funktioner: $names"
grep -qF 'plan_cache_mode=force_custom_plan' <<<"$fresh" || fail "referencen tvinger ikke custom plan"

# 2) Prod-formet base; udsnitstesten er rød.
build_prod() { build_start "$1"
  for f in base-schema.sql base-db-migrations.sql base-db-migrations.sql base-db-rls.sql; do q "$1" -f "$tmp/$f"; done; }
build_prod "$dbp"
[ "$(a "$dbp" "SELECT to_regprocedure('public.red_person_grid_udsnit(bigint,integer,bigint)') IS NULL")" = t ] \
  || fail "basen $base har allerede Y1"
[ "$(a "$dbp" "SELECT position('daa-fortryd-slet' IN pg_get_functiondef('public.red_fortryd_change_set(bigint,boolean)'::regprocedure))>0")" = t ] \
  || fail "basen $base mangler D9"
rc=0; out=$(udsnit "$dbp") || rc=$?
[ "$rc" != 0 ] && grep -qE 'red_person_grid_udsnit\(bigint, ?integer, ?bigint\)" does not exist|function public\.red_person_grid_udsnit.* does not exist' <<<"$out" \
  || { echo "$out" >&2; fail "udsnitstesten er ikke rød på, at red_person_grid_udsnit mangler, på basen $base"; }
kat "$dbp" "$tmp/kat-foer.txt"
data_foer=$(data "$dbp")

# 3) Deploy-transaktionen, derefter det hele igen.
out=$(deploy "$dbp") || { echo "$out" >&2; fail "deploy-transaktionen fejlede"; }
[ "$(sha "$dbp")" = "$fresh" ] || { diff <(echo "$fresh") <(sha "$dbp") >&2 || true; fail "kroppe/proconfig/ACL afviger efter blokken"; }
[ "$(data "$dbp")" = "$data_foer" ] || { diff <(echo "$data_foer" | tr ' ' '\n') <(data "$dbp" | tr ' ' '\n') >&2 || true; fail "data ændret af blokken"; }
kat "$dbp" "$tmp/kat-efter.txt"
delta=$(LC_ALL=C comm -3 <(LC_ALL=C sort "$tmp/kat-foer.txt") <(LC_ALL=C sort "$tmp/kat-efter.txt") | sed 's/^\t//' \
  | cut -d'|' -f1,2 | LC_ALL=C sort -u)
forventet=$(LC_ALL=C sort <<'EOF'
fn|red_person_grid()
fn|red_person_grid_udsnit(bigint,integer,bigint)
fn|red_ret_ocr_felt(bigint,text,text,text,text,jsonb,text,text)
EOF
)
[ "$delta" = "$forventet" ] || { diff <(echo "$forventet") <(echo "$delta") >&2 || true; fail "katalog-delta er ikke de tre forventede funktioner"; }
bash tests/sql/check-catalog-parity.sh "$tmp/kat-fresh.txt" "$tmp/kat-efter.txt" >/dev/null \
  || { bash tests/sql/check-catalog-parity.sh "$tmp/kat-fresh.txt" "$tmp/kat-efter.txt" || true; fail "kataloget efter blokken ≠ frisk schema.sql"; }
out=$(deploy "$dbp") || { echo "$out" >&2; fail "anden deploy-transaktion fejlede"; }
[ "$(sha "$dbp")" = "$fresh" ] || fail "blokken to gange ændrer kroppe/proconfig/ACL"
kat "$dbp" "$tmp/kat-efter2.txt"
cmp -s "$tmp/kat-efter.txt" "$tmp/kat-efter2.txt" || fail "blokken to gange ændrer kataloget"
[ "$(data "$dbp")" = "$data_foer" ] || fail "blokken to gange ændrer data"
pol_foer=$(pol "$dbp")
[ "$(grep -c '|' <<<"$pol_foer")" -ge 100 ] || fail "politik-snapshottet er tomt"
q "$dbp" -1 -f db-rls.sql
[ "$(sha "$dbp")" = "$fresh" ] || fail "hele db-rls.sql oveni ændrer kroppe/proconfig/ACL"
[ "$(pol "$dbp")" = "$pol_foer" ] || { diff <(echo "$pol_foer") <(pol "$dbp") >&2 || true
  fail "hele db-rls.sql oveni ændrer politikker/tabel-ACL (deploy-området er ufuldstændigt)"; }

# 4) Udsnitstesten grøn på den opgraderede base; fuld db-verify på en anden, ens opgraderet base.
out=$(udsnit "$dbp") || { echo "$out" >&2; fail "udsnitstesten fejlede efter blokken"; }
grep -qF 'OK: review37 y1 udsnit' <<<"$out" || { echo "$out" >&2; fail "udsnitstesten: OK-linjen mangler"; }
build_prod "$dbv"
out=$(deploy "$dbv") || { echo "$out" >&2; fail "deploy-transaktionen fejlede på verify-basen"; }
[ "$(sha "$dbv")" = "$fresh" ] || fail "kroppe/proconfig/ACL afviger på verify-basen"
q "$dbv" -f tests/sql/run-db-verify-disposable.sql
dropdb "$dbf"; dropdb "$dbp"; dropdb "$dbv"
echo R37Y1_UPGRADE_OK
