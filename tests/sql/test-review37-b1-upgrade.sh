#!/usr/bin/env bash
# Review 37 blok 1 (#397: D2, D7, S2, Y9): prods deploy-form. Deploy-området er blokken review37-b1 i db-migrations.sql
# + DO-blokken $review37_b1_bookmark$ fra db-rls.sql i ÉN psql-transaktion (-1). Ikke hele db-rls.sql: dens DROP/CREATE
# POLICY tager ACCESS EXCLUSIVE på læsetabellerne. Trin 3 beviser, at hele db-rls.sql oveni ikke ændrer noget.
# 1) Frisk reference (bootstrap + dblink + schema.sql + db-rls.sql): kroppe (sha256 af pg_get_functiondef) og ACL for
#    blokkens funktioner + hele kataloget (tests/sql/inspect-catalog-parity.sql).
# 2) Prod-formet base (2. arg; CI pinner 82dfd0d2 = main efter A2+Y3, #130 og #430 — prods DDL 22/11): basens skema +
#    migrationer to gange + rls. Basen skal mangle rettelserne, og hver af de fire verify-enheder (BEGIN-VERIFY
#    r37b1-* i db-verify.sql) skal være RØD på den med sin egen forventede fejl.
# 3) Kun blokkene i én transaktion → kroppe/ACL = 1), katalog-delta = præcis de forventede objekter, og hele
#    kataloget = 1). Blokkene en gang til er en no-op, og hele db-rls.sql derefter ændrer hverken kroppe, ACL eller
#    politikker.
# 4) De fire verify-enheder er GRØNNE på den opgraderede base; fuld db-verify på en anden, ens opgraderet base.
# Kun lokalt/CI. Ved succes droppes de tre baser, scriptet selv oprettede (<db>_f, <db>_p, <db>_v); ved fejl står de tilbage.
set -euo pipefail
name=${1:?database}; base=${2:?base-commit}
dbf="${name}_f"; dbp="${name}_p"; dbv="${name}_v"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
for f in schema.sql db-rls.sql db-migrations.sql; do git show "$base:$f" > "$tmp/base-$f"; done
q() { env -u PGOPTIONS psql -X -q -v ON_ERROR_STOP=1 -d "$1" "${@:2}" >/dev/null; }
a() { env -u PGOPTIONS psql -X -At -v ON_ERROR_STOP=1 -d "$1" -c "$2"; }
fail() { echo "R37B1_UPGRADE_FAIL: $1" >&2; exit 1; }

# Deploy-området, som prod-runneren skærer det.
awk '$0=="-- BEGIN review37-b1" {p=1} p{print} $0=="-- END review37-b1" {p=0}' db-migrations.sql > "$tmp/b1.sql"
[ "$(head -1 "$tmp/b1.sql")" = "-- BEGIN review37-b1" ] && [ "$(tail -1 "$tmp/b1.sql")" = "-- END review37-b1" ] \
  || fail "blokken review37-b1 mangler eller er ikke afsluttet"
awk '$0=="DO $review37_b1_bookmark$" {p=1} p{print} $0=="$review37_b1_bookmark$;" {p=0}' db-rls.sql > "$tmp/rls.sql"
[ "$(head -1 "$tmp/rls.sql")" = 'DO $review37_b1_bookmark$' ] && [ "$(tail -1 "$tmp/rls.sql")" = '$review37_b1_bookmark$;' ] \
  || fail "DO-blokken \$review37_b1_bookmark\$ mangler i db-rls.sql"
cat "$tmp/b1.sql" "$tmp/rls.sql" > "$tmp/blok.sql"
names=$(grep -oE '^CREATE OR REPLACE FUNCTION [a-z_]+\.[a-z0-9_]+' "$tmp/blok.sql" | awk '{print $5}' | sort -u | tr '\n' ' ')
[ "$(wc -w <<<"$names")" -eq 3 ] || fail "forventede 3 funktioner i blokken, fandt: $names"
list=$(for n in $names; do printf "'%s'," "$n"; done); list=${list%,}
# Verify-enhederne (selvforsynende DO-blokke i db-verify.sql).
for u in d2 d7 s2 y9; do
  awk -v u="$u" '$0=="-- BEGIN-VERIFY r37b1-" u {p=1} p{print} $0=="-- END-VERIFY r37b1-" u {p=0}' db-verify.sql > "$tmp/v-$u.sql"
  [ "$(head -1 "$tmp/v-$u.sql")" = "-- BEGIN-VERIFY r37b1-$u" ] || fail "verify-enheden r37b1-$u mangler i db-verify.sql"
done
sha() { a "$1" "SELECT l FROM (SELECT p.oid::regprocedure::text||'|'||encode(extensions.digest(convert_to(pg_get_functiondef(p.oid),'UTF8'),'sha256'),'hex')
  ||'|'||coalesce(p.proacl::text,'NULL') AS l FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname||'.'||p.proname IN ($list)) s ORDER BY l COLLATE \"C\""; }
pol() { a "$1" "SELECT l FROM (SELECT schemaname||'.'||tablename||'|'||policyname||'|'||cmd||'|'||roles::text||'|'||
  coalesce(qual,'')||'|'||coalesce(with_check,'') AS l FROM pg_policies WHERE schemaname IN ('public','private')
  UNION ALL SELECT n.nspname||'.'||c.relname||'|acl|'||coalesce(c.relacl::text,'NULL')||'|'||c.relrowsecurity::text
  FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN ('public','private') AND c.relkind IN ('r','v','m')) s
  ORDER BY l COLLATE \"C\""; }
kat() { env -u PGOPTIONS psql -X -Atq -v ON_ERROR_STOP=1 -d "$1" -f tests/sql/inspect-catalog-parity.sql > "$2"; }
# Kør en verify-enhed; $3 = forventet fejltekst (rød) eller tom (grøn: OK-NOTICE skal komme).
unit() { local out
  if out=$(env -u PGOPTIONS psql -X -v ON_ERROR_STOP=1 -d "$1" -f "$tmp/v-$2.sql" 2>&1); then
    [ -z "$3" ] || { echo "$out" >&2; fail "r37b1-$2 er grøn på basen $base (forventede: $3)"; }
    grep -q "NOTICE:  OK: review37 " <<<"$out" || { echo "$out" >&2; fail "r37b1-$2: OK-linjen mangler"; }
  else
    [ -n "$3" ] || { echo "$out" >&2; fail "r37b1-$2 fejlede efter blokken"; }
    grep -qF -- "$3" <<<"$out" || { echo "$out" >&2; fail "r37b1-$2 fejlede af en anden grund end: $3"; }
  fi; }
build_start() { createdb "$1"; q "$1" -f tests/sql/evidence-promotion-bootstrap.sql
  q "$1" -c 'CREATE EXTENSION IF NOT EXISTS dblink WITH SCHEMA extensions'; }

# 1) Frisk reference.
build_start "$dbf"; q "$dbf" -f schema.sql; q "$dbf" -f db-rls.sql
fresh=$(sha "$dbf"); kat "$dbf" "$tmp/kat-fresh.txt"
[ "$(wc -l <<<"$fresh")" -eq 3 ] || fail "referencen mangler funktioner: $names"

# 2) Prod-formet base, og de fire enheder er røde på den.
build_prod() { build_start "$1"
  for f in base-schema.sql base-db-migrations.sql base-db-migrations.sql base-db-rls.sql; do q "$1" -f "$tmp/$f"; done; }
build_prod "$dbp"
[ "$(a "$dbp" "SELECT to_regclass('public.ix_bookmark_person_id') IS NULL
  AND NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='bookmark' AND policyname='bookmark_insert_own'
                  AND with_check LIKE '%person_offentlig%')")" = t ] || fail "basen $base har allerede blok 1"
[ "$(sha "$dbp")" != "$fresh" ] || fail "basen er allerede byte-ens med schema.sql"
unit "$dbp" d2 "nyere ændring rører"
unit "$dbp" d7 "FEJL: D7 — red_publicer_udgave åbnede intet ændringssæt"
unit "$dbp" s2 "FEJL: S2 — medlem bogmærkede levende person"
unit "$dbp" y9 "FEJL: Y9 — FK-indeks mangler"
kat "$dbp" "$tmp/kat-foer.txt"

# 3) Kun blokkene i én transaktion, derefter blokkene igen.
q "$dbp" -1 -f "$tmp/blok.sql"
[ "$(sha "$dbp")" = "$fresh" ] || { diff <(echo "$fresh") <(sha "$dbp") >&2 || true; fail "kroppe/ACL afviger efter blokkene"; }
kat "$dbp" "$tmp/kat-efter.txt"
delta=$(LC_ALL=C comm -3 <(LC_ALL=C sort "$tmp/kat-foer.txt") <(LC_ALL=C sort "$tmp/kat-efter.txt") | sed 's/^\t//' \
  | cut -d'|' -f1,2 | LC_ALL=C sort -u)
forventet=$(LC_ALL=C sort <<'EOF'
fn|_version_upsert_row(text,jsonb)
fn|red_fortryd_change_set(bigint,boolean)
fn|red_publicer_udgave(bigint)
idx|ix_bookmark_person_id
idx|ix_haendelse_fact_id
idx|ix_haendelse_relation_id
idx|ix_story_fact_id
idx|ix_story_historical_event_id
idx|ix_story_relation_id
pol|bookmark.bookmark_insert_own
EOF
)
[ "$delta" = "$forventet" ] || { diff <(echo "$forventet") <(echo "$delta") >&2 || true; fail "katalog-delta er ikke de 10 forventede objekter"; }
bash tests/sql/check-catalog-parity.sh "$tmp/kat-fresh.txt" "$tmp/kat-efter.txt" >/dev/null \
  || { bash tests/sql/check-catalog-parity.sh "$tmp/kat-fresh.txt" "$tmp/kat-efter.txt" || true; fail "kataloget efter blokkene ≠ frisk schema.sql"; }
q "$dbp" -1 -f "$tmp/blok.sql"
[ "$(sha "$dbp")" = "$fresh" ] || fail "blokkene to gange ændrer kroppe/ACL"
kat "$dbp" "$tmp/kat-efter2.txt"
cmp -s "$tmp/kat-efter.txt" "$tmp/kat-efter2.txt" || fail "blokkene to gange ændrer kataloget"
pol_foer=$(pol "$dbp")
[ "$(grep -c '|' <<<"$pol_foer")" -ge 100 ] && grep -q '^public\.bookmark|bookmark_insert_own|' <<<"$pol_foer" \
  || fail "politik-snapshottet er tomt eller mangler bookmark_insert_own"
q "$dbp" -1 -f db-rls.sql
[ "$(sha "$dbp")" = "$fresh" ] || fail "hele db-rls.sql oveni ændrer kroppe/ACL (deploy-området er ufuldstændigt)"
[ "$(pol "$dbp")" = "$pol_foer" ] || { diff <(echo "$pol_foer") <(pol "$dbp") >&2 || true
  fail "hele db-rls.sql oveni ændrer politikker/tabel-ACL (deploy-området er ufuldstændigt)"; }

# 4) Adfærd på den opgraderede base; fuld db-verify på en anden, ens opgraderet base.
for u in d2 d7 s2 y9; do unit "$dbp" "$u" ""; done
build_prod "$dbv"; q "$dbv" -1 -f "$tmp/blok.sql"
[ "$(sha "$dbv")" = "$fresh" ] || fail "kroppe/ACL afviger på verify-basen"
q "$dbv" -f tests/sql/run-db-verify-disposable.sql
dropdb "$dbf"; dropdb "$dbp"; dropdb "$dbv"
echo R37B1_UPGRADE_OK
