#!/usr/bin/env bash
# Review 37 S3 (#397): en familie uden medlemmer er ikke offentlig. Prods deploy-form: KUN DO-blokken
# $review37_s3_tom_familie$ fra db-rls.sql (family_offentlig; ikke hele db-rls.sql, som tager ACCESS EXCLUSIVE på
# læsernes tabeller) i én psql-transaktion (-1).
# 1) Frisk reference (bootstrap + dblink + schema.sql + db-rls.sql): krop (sha256) og ACL for family_offentlig + hele
#    kataloget (tests/sql/inspect-catalog-parity.sql).
# 2) Prod-formet base (2. arg; CI pinner 7a20b51e = prods SQL efter blok 3): basens skema + migrationer to gange + rls.
#    Basen skal mangle rettelsen: verify-enhederne r37s3 og r37b3-gate og kaldermatricen
#    tests/sql/test-review37-b3-gate.sql er RØDE med deres egen forventede fejl.
# 3) Deploy-transaktionen: krop/ACL = frisk, katalog-delta = præcis family_offentlig, hele kataloget = frisk, data
#    uændret. Det hele en gang til ændrer intet, og hele db-rls.sql derefter ændrer hverken kroppe, ACL eller politikker.
# 4) Enhederne og matricen er GRØNNE på den opgraderede base; fuld db-verify på en anden, ens opgraderet base.
# Kun lokalt/CI. Ved succes droppes de tre baser, scriptet selv oprettede (<db>_f, _p, _v); ved fejl står de tilbage.
set -euo pipefail
name=${1:?database}; base=${2:?base-commit}
dbf="${name}_f"; dbp="${name}_p"; dbv="${name}_v"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
for f in schema.sql db-rls.sql db-migrations.sql; do git show "$base:$f" > "$tmp/base-$f"; done
q() { env -u PGOPTIONS psql -X -q -v ON_ERROR_STOP=1 -d "$1" "${@:2}" >/dev/null; }
a() { env -u PGOPTIONS psql -X -At -v ON_ERROR_STOP=1 -d "$1" -c "$2"; }
fail() { echo "R37S3_UPGRADE_FAIL: $1" >&2; exit 1; }

# Deploy-området, som prod-runneren skærer det.
awk '$0=="DO $review37_s3_tom_familie$" {p=1} p{print} $0=="$review37_s3_tom_familie$;" {p=0}' db-rls.sql > "$tmp/rls.sql"
[ "$(head -1 "$tmp/rls.sql")" = 'DO $review37_s3_tom_familie$' ] && [ "$(tail -1 "$tmp/rls.sql")" = '$review37_s3_tom_familie$;' ] \
  || fail "DO-blokken \$review37_s3_tom_familie\$ mangler i db-rls.sql"
[ "$(grep -ciE '^create or replace function' "$tmp/rls.sql")" -eq 1 ] || fail "DO-blokken skal rumme præcis én funktion"
deploy() { env -u PGOPTIONS psql -X -q -1 -v ON_ERROR_STOP=1 -d "$1" -f "$tmp/rls.sql" 2>&1; }
for u in r37s3 r37b3-gate; do
  awk -v u="$u" '$0=="-- BEGIN-VERIFY " u {p=1} p{print} $0=="-- END-VERIFY " u {p=0}' db-verify.sql > "$tmp/v-$u.sql"
  [ "$(head -1 "$tmp/v-$u.sql")" = "-- BEGIN-VERIFY $u" ] || fail "verify-enheden $u mangler i db-verify.sql"
done
sha() { a "$1" "SELECT p.oid::regprocedure::text||'|'||encode(extensions.digest(convert_to(pg_get_functiondef(p.oid),'UTF8'),'sha256'),'hex')
  ||'|'||coalesce(p.proacl::text,'NULL') FROM pg_proc p WHERE p.oid='public.family_offentlig(bigint)'::regprocedure"; }
pol() { a "$1" "SELECT l FROM (SELECT schemaname||'.'||tablename||'|'||policyname||'|'||cmd||'|'||roles::text||'|'||
  coalesce(qual,'')||'|'||coalesce(with_check,'') AS l FROM pg_policies WHERE schemaname IN ('public','private')
  UNION ALL SELECT n.nspname||'.'||c.relname||'|acl|'||coalesce(c.relacl::text,'NULL')||'|'||c.relrowsecurity::text
  FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN ('public','private') AND c.relkind IN ('r','v','m')) s
  ORDER BY l COLLATE \"C\""; }
kat() { env -u PGOPTIONS psql -X -Atq -v ON_ERROR_STOP=1 -d "$1" -f tests/sql/inspect-catalog-parity.sql > "$2"; }
data() { a "$1" "SELECT string_agg(t||'='||h, ' ' ORDER BY t) FROM (
  SELECT 'family' t, md5(coalesce(string_agg(to_jsonb(x)::text, ',' ORDER BY x.id),'')) h FROM family x
  UNION ALL SELECT 'family_member', md5(coalesce(string_agg(to_jsonb(x)::text, ',' ORDER BY x.family_id,x.person_id,x.rolle),''))
    FROM family_member x
  UNION ALL SELECT 'person', md5(coalesce(string_agg(to_jsonb(x)::text, ',' ORDER BY x.id),'')) FROM person x
  UNION ALL SELECT 'change_set', count(*)::text FROM change_set) s"; }
# Kør en verify-enhed; $3 = forventet fejltekst (rød) eller tom (grøn: OK-NOTICE skal komme).
unit() { local out
  if out=$(env -u PGOPTIONS psql -X -v ON_ERROR_STOP=1 -d "$1" -f "$tmp/v-$2.sql" 2>&1); then
    [ -z "$3" ] || { echo "$out" >&2; fail "$2 er grøn på basen $base (forventede: $3)"; }
    grep -q "NOTICE:  OK: review37 " <<<"$out" || { echo "$out" >&2; fail "$2: OK-linjen mangler"; }
  else
    [ -n "$3" ] || { echo "$out" >&2; fail "$2 fejlede efter blokken"; }
    grep -qF -- "$3" <<<"$out" || { echo "$out" >&2; fail "$2 fejlede af en anden grund end: $3"; }
  fi; }
matrix() { local out
  if out=$(env -u PGOPTIONS psql -X -v ON_ERROR_STOP=1 -d "$1" -f tests/sql/test-review37-b3-gate.sql 2>&1); then
    [ -z "$2" ] || { echo "$out" >&2; fail "kaldermatricen er grøn på basen $base (forventede: $2)"; }
    grep -q "NOTICE:  OK: review37 b3 gate" <<<"$out" || { echo "$out" >&2; fail "kaldermatricen: OK-linjen mangler"; }
  else
    [ -n "$2" ] || { echo "$out" >&2; fail "kaldermatricen fejlede efter blokken"; }
    grep -qF -- "$2" <<<"$out" || { echo "$out" >&2; fail "kaldermatricen fejlede af en anden grund end: $2"; }
  fi; }
build_start() { createdb "$1"; q "$1" -f tests/sql/evidence-promotion-bootstrap.sql
  q "$1" -c 'CREATE EXTENSION IF NOT EXISTS dblink WITH SCHEMA extensions'; }

# 1) Frisk reference.
build_start "$dbf"; q "$dbf" -f schema.sql; q "$dbf" -f db-rls.sql
fresh=$(sha "$dbf"); kat "$dbf" "$tmp/kat-fresh.txt"
[ -n "$fresh" ] || fail "referencen mangler family_offentlig"

# 2) Prod-formet base; enhederne og matricen er røde på den.
build_prod() { build_start "$1"
  for f in base-schema.sql base-db-migrations.sql base-db-migrations.sql base-db-rls.sql; do q "$1" -f "$tmp/$f"; done; }
build_prod "$dbp"
[ "$(a "$dbp" "SELECT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='relation_afbildet_kanonisk')")" = t ] \
  || fail "basen $base mangler blok 3"
[ "$(sha "$dbp")" != "$fresh" ] || fail "basen har allerede rettelsen (family_offentlig byte-ens med db-rls.sql)"
unit "$dbp" r37s3 "FEJL: S3 — en familie uden medlemmer er offentlig"
unit "$dbp" r37b3-gate "FEJL: gate — S3: billedet af en medlemsløs familie er ikke skjult"
matrix "$dbp" "KALDER_MATRIX_FAILED: billede medlemsloes_familie_S3 som gaest"
kat "$dbp" "$tmp/kat-foer.txt"
data_foer=$(data "$dbp")

# 3) Deploy-transaktionen, derefter det hele igen.
out=$(deploy "$dbp") || { echo "$out" >&2; fail "deploy-transaktionen fejlede"; }
[ "$(sha "$dbp")" = "$fresh" ] || { diff <(echo "$fresh") <(sha "$dbp") >&2 || true; fail "krop/ACL afviger efter blokken"; }
[ "$(data "$dbp")" = "$data_foer" ] || fail "data ændret af blokken"
kat "$dbp" "$tmp/kat-efter.txt"
delta=$(LC_ALL=C comm -3 <(LC_ALL=C sort "$tmp/kat-foer.txt") <(LC_ALL=C sort "$tmp/kat-efter.txt") | sed 's/^\t//' \
  | cut -d'|' -f1,2 | LC_ALL=C sort -u)
[ "$delta" = "fn|family_offentlig(bigint)" ] || { echo "$delta" >&2; fail "katalog-delta er ikke præcis family_offentlig"; }
bash tests/sql/check-catalog-parity.sh "$tmp/kat-fresh.txt" "$tmp/kat-efter.txt" >/dev/null \
  || { bash tests/sql/check-catalog-parity.sh "$tmp/kat-fresh.txt" "$tmp/kat-efter.txt" || true; fail "kataloget efter blokken ≠ frisk schema.sql"; }
out=$(deploy "$dbp") || { echo "$out" >&2; fail "anden deploy-transaktion fejlede"; }
kat "$dbp" "$tmp/kat-efter2.txt"
cmp -s "$tmp/kat-efter.txt" "$tmp/kat-efter2.txt" || fail "blokken to gange ændrer kataloget"
pol_foer=$(pol "$dbp")
[ "$(grep -c '|' <<<"$pol_foer")" -ge 100 ] || fail "politik-snapshottet er tomt"
q "$dbp" -1 -f db-rls.sql
[ "$(sha "$dbp")" = "$fresh" ] || fail "hele db-rls.sql oveni ændrer krop/ACL"
[ "$(pol "$dbp")" = "$pol_foer" ] || { diff <(echo "$pol_foer") <(pol "$dbp") >&2 || true
  fail "hele db-rls.sql oveni ændrer politikker/tabel-ACL (deploy-området er ufuldstændigt)"; }

# 4) Adfærd på den opgraderede base; fuld db-verify på en anden, ens opgraderet base.
for u in r37s3 r37b3-gate; do unit "$dbp" "$u" ""; done
matrix "$dbp" ""
build_prod "$dbv"
out=$(deploy "$dbv") || { echo "$out" >&2; fail "deploy-transaktionen fejlede på verify-basen"; }
[ "$(sha "$dbv")" = "$fresh" ] || fail "krop/ACL afviger på verify-basen"
q "$dbv" -f tests/sql/run-db-verify-disposable.sql
dropdb "$dbf"; dropdb "$dbp"; dropdb "$dbv"
echo R37S3_UPGRADE_OK
