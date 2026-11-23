#!/usr/bin/env bash
# Review 37 D9 + R37B-1 (#397): låserækkefølgen i fortryd og sletning. Prods deploy-form: KUN blokken review37-d9 i
# db-migrations.sql (syv funktioner, alle med samme signatur og returtype) i én psql-transaktion (-1). db-rls.sql
# deployes ikke: blokken ændrer ingen ACL, og hele db-rls.sql oveni må intet ændre (trin 3).
# 1) Frisk reference (bootstrap + dblink + schema.sql + db-rls.sql): kroppe (sha256 af pg_get_functiondef) og ACL for
#    blokkens funktioner + hele kataloget (tests/sql/inspect-catalog-parity.sql).
# 2) Prod-formet base (2. arg; CI pinner b18bd8a8 = prods SQL efter blok 4): basens skema + migrationer to gange + rls.
#    Basen skal mangle rettelsen: to-sessionstesten tests/sql/test-review37-d9-laaseorden.sql er RØD på en kopi.
# 3) Deploy-transaktionen: kroppe/ACL = frisk, katalog-delta = præcis de syv funktioner, hele kataloget = frisk, data
#    uændret. Det hele en gang til ændrer intet, og hele db-rls.sql derefter ændrer hverken kroppe, ACL eller politikker.
# 4) To-sessionstesten er GRØN på den opgraderede base; fuld db-verify på en anden, ens opgraderet base.
# Kun lokalt/CI. Ved succes droppes de fire baser, scriptet selv oprettede (<db>_f, _p, _r, _v); ved fejl står de tilbage.
set -euo pipefail
name=${1:?database}; base=${2:?base-commit}
dbf="${name}_f"; dbp="${name}_p"; dbr="${name}_r"; dbv="${name}_v"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
for f in schema.sql db-rls.sql db-migrations.sql; do git show "$base:$f" > "$tmp/base-$f"; done
q() { env -u PGOPTIONS psql -X -q -v ON_ERROR_STOP=1 -d "$1" "${@:2}" >/dev/null; }
a() { env -u PGOPTIONS psql -X -At -v ON_ERROR_STOP=1 -d "$1" -c "$2"; }
fail() { echo "R37D9_UPGRADE_FAIL: $1" >&2; exit 1; }

# Deploy-området, som prod-runneren skærer det.
awk '$0=="-- BEGIN review37-d9" {p=1} p{print} $0=="-- END review37-d9" {p=0}' db-migrations.sql > "$tmp/blok.sql"
[ "$(head -1 "$tmp/blok.sql")" = "-- BEGIN review37-d9" ] && [ "$(tail -1 "$tmp/blok.sql")" = "-- END review37-d9" ] \
  || fail "blokken review37-d9 mangler eller er ikke afsluttet"
[ "$(tail -1 db-migrations.sql)" = "-- END review37-d9" ] \
  || fail "blokken review37-d9 skal stå sidst i db-migrations.sql (funktionerne defineres flere gange i filen)"
names=$( { grep -ioE '^CREATE OR REPLACE FUNCTION [a-z_.]+\(' "$tmp/blok.sql" || true; } \
  | sed -E 's/.*[Ff][Uu][Nn][Cc][Tt][Ii][Oo][Nn] ([a-z_.]+)\(/\1/; /\./!s/^/public./' | sort -u | tr '\n' ' ')
[ "$names" = "public.red_fjern_ikke_samme_som public.red_fjern_samme_som public.red_fortryd_change_set public.red_slet_familie_link public.red_slet_oplysning public.red_slet_person public.red_slet_relation " ] \
  || fail "forventede præcis syv funktioner i blokken, fandt: $names"
list=$(for n in $names; do printf "'%s'," "$n"; done); list=${list%,}
deploy() { env -u PGOPTIONS psql -X -q -1 -v ON_ERROR_STOP=1 -d "$1" -f "$tmp/blok.sql" 2>&1; }
sha() { a "$1" "SELECT l FROM (SELECT p.oid::regprocedure::text||'|'||encode(extensions.digest(convert_to(pg_get_functiondef(p.oid),'UTF8'),'sha256'),'hex')
  ||'|'||coalesce(p.proacl::text,'NULL') AS l FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname||'.'||p.proname IN ($list)) s ORDER BY l COLLATE \"C\""; }
pol() { a "$1" "SELECT l FROM (SELECT schemaname||'.'||tablename||'|'||policyname||'|'||cmd||'|'||roles::text||'|'||
  coalesce(qual,'')||'|'||coalesce(with_check,'') AS l FROM pg_policies WHERE schemaname IN ('public','private')
  UNION ALL SELECT n.nspname||'.'||c.relname||'|acl|'||coalesce(c.relacl::text,'NULL')||'|'||c.relrowsecurity::text
  FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN ('public','private') AND c.relkind IN ('r','v','m')) s
  ORDER BY l COLLATE \"C\""; }
kat() { env -u PGOPTIONS psql -X -Atq -v ON_ERROR_STOP=1 -d "$1" -f tests/sql/inspect-catalog-parity.sql > "$2"; }
# Data i de tabeller, funktionerne rører (+ change_set-antallet): én md5 pr. tabel over rækkernes jsonb i nøgleorden.
data() { a "$1" "SELECT string_agg(t||'='||h, ' ' ORDER BY t) FROM (
  SELECT 'person' t, md5(coalesce(string_agg(to_jsonb(x)::text, ',' ORDER BY x.id),'')) h FROM person x
  UNION ALL SELECT 'person_lineage_membership', md5(coalesce(string_agg(to_jsonb(x)::text, ',' ORDER BY x.person_id,x.lineage_id),''))
    FROM person_lineage_membership x
  UNION ALL SELECT 'relation', md5(coalesce(string_agg(to_jsonb(x)::text, ',' ORDER BY x.id),'')) FROM relation x
  UNION ALL SELECT 'assertion', md5(coalesce(string_agg(to_jsonb(x)::text, ',' ORDER BY x.id),'')) FROM assertion x
  UNION ALL SELECT 'conclusion', md5(coalesce(string_agg(to_jsonb(x)::text, ',' ORDER BY x.id),'')) FROM conclusion x
  UNION ALL SELECT 'change_set', count(*)::text FROM change_set) s"; }
# To-sessionstesten (committer sin opsætning: kun på en base, der ikke bruges til andet bagefter).
laase() { env -u PGOPTIONS psql -X -v ON_ERROR_STOP=1 -d "$1" -f tests/sql/test-review37-d9-laaseorden.sql 2>&1; }
build_start() { createdb "$1"; q "$1" -f tests/sql/evidence-promotion-bootstrap.sql
  q "$1" -c 'CREATE EXTENSION IF NOT EXISTS dblink WITH SCHEMA extensions'; }

# 1) Frisk reference.
build_start "$dbf"; q "$dbf" -f schema.sql; q "$dbf" -f db-rls.sql
fresh=$(sha "$dbf"); kat "$dbf" "$tmp/kat-fresh.txt"
[ "$(wc -l <<<"$fresh")" -eq 7 ] || fail "referencen mangler funktioner: $names"

# 2) Prod-formet base; to-sessionstesten er rød på en kopi.
build_prod() { build_start "$1"
  for f in base-schema.sql base-db-migrations.sql base-db-migrations.sql base-db-rls.sql; do q "$1" -f "$tmp/$f"; done; }
build_prod "$dbp"
[ "$(a "$dbp" "SELECT position('daa-fortryd-slet' IN pg_get_functiondef('public.red_fortryd_change_set(bigint,boolean)'::regprocedure))=0")" = t ] \
  || fail "basen $base har allerede D9"
[ "$(a "$dbp" "SELECT position('findes ikke' IN pg_get_functiondef('public.red_slet_oplysning(bigint)'::regprocedure))>0")" = t ] \
  || fail "basen $base mangler blok 4 (red_slet_oplysning uden D11)"
[ "$(sha "$dbp")" != "$fresh" ] || fail "basen er allerede byte-ens med schema.sql"
build_prod "$dbr"
rc=0; out=$(laase "$dbr") || rc=$?
[ "$rc" != 0 ] && grep -qF 'D9_TEST_FAILED: (a) deadlock' <<<"$out" \
  || { echo "$out" >&2; fail "to-sessionstesten er ikke rød med deadlock i (a) på basen $base"; }
kat "$dbp" "$tmp/kat-foer.txt"
data_foer=$(data "$dbp")

# 3) Deploy-transaktionen, derefter det hele igen.
out=$(deploy "$dbp") || { echo "$out" >&2; fail "deploy-transaktionen fejlede"; }
[ "$(sha "$dbp")" = "$fresh" ] || { diff <(echo "$fresh") <(sha "$dbp") >&2 || true; fail "kroppe/ACL afviger efter blokken"; }
[ "$(data "$dbp")" = "$data_foer" ] || { diff <(echo "$data_foer" | tr ' ' '\n') <(data "$dbp" | tr ' ' '\n') >&2 || true; fail "data ændret af blokken"; }
kat "$dbp" "$tmp/kat-efter.txt"
delta=$(LC_ALL=C comm -3 <(LC_ALL=C sort "$tmp/kat-foer.txt") <(LC_ALL=C sort "$tmp/kat-efter.txt") | sed 's/^\t//' \
  | cut -d'|' -f1,2 | LC_ALL=C sort -u)
forventet=$(LC_ALL=C sort <<'EOF'
fn|red_fjern_ikke_samme_som(bigint)
fn|red_fjern_samme_som(bigint)
fn|red_fortryd_change_set(bigint,boolean)
fn|red_slet_familie_link(bigint,bigint,text)
fn|red_slet_oplysning(bigint)
fn|red_slet_person(bigint)
fn|red_slet_relation(bigint)
EOF
)
[ "$delta" = "$forventet" ] || { diff <(echo "$forventet") <(echo "$delta") >&2 || true; fail "katalog-delta er ikke de syv forventede funktioner"; }
bash tests/sql/check-catalog-parity.sh "$tmp/kat-fresh.txt" "$tmp/kat-efter.txt" >/dev/null \
  || { bash tests/sql/check-catalog-parity.sh "$tmp/kat-fresh.txt" "$tmp/kat-efter.txt" || true; fail "kataloget efter blokken ≠ frisk schema.sql"; }
out=$(deploy "$dbp") || { echo "$out" >&2; fail "anden deploy-transaktion fejlede"; }
[ "$(sha "$dbp")" = "$fresh" ] || fail "blokken to gange ændrer kroppe/ACL"
kat "$dbp" "$tmp/kat-efter2.txt"
cmp -s "$tmp/kat-efter.txt" "$tmp/kat-efter2.txt" || fail "blokken to gange ændrer kataloget"
[ "$(data "$dbp")" = "$data_foer" ] || fail "blokken to gange ændrer data"
pol_foer=$(pol "$dbp")
[ "$(grep -c '|' <<<"$pol_foer")" -ge 100 ] || fail "politik-snapshottet er tomt"
q "$dbp" -1 -f db-rls.sql
[ "$(sha "$dbp")" = "$fresh" ] || fail "hele db-rls.sql oveni ændrer kroppe/ACL"
[ "$(pol "$dbp")" = "$pol_foer" ] || { diff <(echo "$pol_foer") <(pol "$dbp") >&2 || true
  fail "hele db-rls.sql oveni ændrer politikker/tabel-ACL (deploy-området er ufuldstændigt)"; }

# 4) Fuld db-verify på en anden, ens opgraderet base; derefter to-sessionstesten på den første (den committer data).
build_prod "$dbv"
out=$(deploy "$dbv") || { echo "$out" >&2; fail "deploy-transaktionen fejlede på verify-basen"; }
[ "$(sha "$dbv")" = "$fresh" ] || fail "kroppe/ACL afviger på verify-basen"
q "$dbv" -f tests/sql/run-db-verify-disposable.sql
out=$(laase "$dbp") || { echo "$out" >&2; fail "to-sessionstesten fejlede efter blokken"; }
grep -qF 'PASS test-review37-d9-laaseorden' <<<"$out" || { echo "$out" >&2; fail "to-sessionstesten: PASS-linjen mangler"; }
dropdb "$dbf"; dropdb "$dbp"; dropdb "$dbr"; dropdb "$dbv"
echo R37D9_UPGRADE_OK
