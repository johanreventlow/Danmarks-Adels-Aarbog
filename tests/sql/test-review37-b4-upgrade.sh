#!/usr/bin/env bash
# Review 37 blok 4 (#397): konklusion og ændringssæt i redaktionens RPC'er — D4 (red_set_konklusion gør konklusionen
# gyldig), D10 (en ny forældre-påstand på et tilbagetrukket slot er ikke en konflikt) og D11 (ukendt id giver en ærlig
# fejl i red_set_koen, red_set_privat og red_slet_oplysning). Prods deploy-form: KUN blokken review37-b4 i
# db-migrations.sql (fem funktioner, alle med samme signatur og returtype) i én psql-transaktion (-1). db-rls.sql
# deployes ikke: blokken ændrer ingen ACL, og hele db-rls.sql oveni må intet ændre (trin 3).
# 1) Frisk reference (bootstrap + dblink + schema.sql + db-rls.sql): kroppe (sha256 af pg_get_functiondef) og ACL for
#    blokkens funktioner + hele kataloget (tests/sql/inspect-catalog-parity.sql).
# 2) Prod-formet base (2. arg; CI pinner 526a769a = prods SQL efter P11): basens skema + migrationer to gange + rls og en
#    lille fixtur med en tilbagetrukket konklusion. Basen skal mangle rettelserne: verify-enhederne r37d4, r37d10 og
#    r37d11 er RØDE med deres egen forventede fejl.
# 3) Deploy-transaktionen: kroppe/ACL = frisk, katalog-delta = præcis de fem funktioner, hele kataloget = frisk, data
#    uændret. Det hele en gang til ændrer intet, og hele db-rls.sql derefter ændrer hverken kroppe, ACL eller politikker.
# 4) Enhederne er GRØNNE på den opgraderede base; fuld db-verify på en anden, ens opgraderet base.
# Kun lokalt/CI. Ved succes droppes de tre baser, scriptet selv oprettede (<db>_f, _p, _v); ved fejl står de tilbage.
set -euo pipefail
name=${1:?database}; base=${2:?base-commit}
dbf="${name}_f"; dbp="${name}_p"; dbv="${name}_v"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
for f in schema.sql db-rls.sql db-migrations.sql; do git show "$base:$f" > "$tmp/base-$f"; done
q() { env -u PGOPTIONS psql -X -q -v ON_ERROR_STOP=1 -d "$1" "${@:2}" >/dev/null; }
a() { env -u PGOPTIONS psql -X -At -v ON_ERROR_STOP=1 -d "$1" -c "$2"; }
fail() { echo "R37B4_UPGRADE_FAIL: $1" >&2; exit 1; }

# Deploy-området, som prod-runneren skærer det.
awk '$0=="-- BEGIN review37-b4" {p=1} p{print} $0=="-- END review37-b4" {p=0}' db-migrations.sql > "$tmp/blok.sql"
[ "$(head -1 "$tmp/blok.sql")" = "-- BEGIN review37-b4" ] && [ "$(tail -1 "$tmp/blok.sql")" = "-- END review37-b4" ] \
  || fail "blokken review37-b4 mangler eller er ikke afsluttet"
[ "$(tail -1 db-migrations.sql)" = "-- END review37-b4" ] \
  || fail "blokken review37-b4 skal stå sidst i db-migrations.sql (funktionerne defineres flere gange i filen)"
names=$( { grep -ioE '^CREATE OR REPLACE FUNCTION [a-z_.]+\(' "$tmp/blok.sql" || true; } \
  | sed -E 's/.*[Ff][Uu][Nn][Cc][Tt][Ii][Oo][Nn] ([a-z_.]+)\(/\1/; /\./!s/^/public./' | sort -u | tr '\n' ' ')
[ "$names" = "public.red_set_koen public.red_set_konklusion public.red_set_privat public.red_slet_oplysning public.red_tilfoej_foraeldre_paastand " ] \
  || fail "forventede præcis fem funktioner i blokken, fandt: $names"
list=$(for n in $names; do printf "'%s'," "$n"; done); list=${list%,}
deploy() { env -u PGOPTIONS psql -X -q -1 -v ON_ERROR_STOP=1 -d "$1" -f "$tmp/blok.sql" 2>&1; }
for u in r37d4 r37d10 r37d11; do
  awk -v u="$u" '$0=="-- BEGIN-VERIFY "u {p=1} p{print} $0=="-- END-VERIFY "u {p=0}' db-verify.sql > "$tmp/v-$u.sql"
  [ "$(head -1 "$tmp/v-$u.sql")" = "-- BEGIN-VERIFY $u" ] || fail "verify-enheden $u mangler i db-verify.sql"
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
# Data i de tabeller, funktionerne rører (+ change_set-antallet): én md5 pr. tabel over rækkernes jsonb i nøgleorden.
data() { a "$1" "SELECT string_agg(t||'='||h, ' ' ORDER BY t) FROM (
  SELECT 'person' t, md5(coalesce(string_agg(to_jsonb(x)::text, ',' ORDER BY x.id),'')) h FROM person x
  UNION ALL SELECT 'family_member', md5(coalesce(string_agg(to_jsonb(x)::text, ',' ORDER BY x.family_id,x.person_id,x.rolle),''))
    FROM family_member x
  UNION ALL SELECT 'fact', md5(coalesce(string_agg(to_jsonb(x)::text, ',' ORDER BY x.id),'')) FROM fact x
  UNION ALL SELECT 'assertion', md5(coalesce(string_agg(to_jsonb(x)::text, ',' ORDER BY x.id),'')) FROM assertion x
  UNION ALL SELECT 'conclusion', md5(coalesce(string_agg(to_jsonb(x)::text, ',' ORDER BY x.id),'')) FROM conclusion x
  UNION ALL SELECT 'change_set', count(*)::text FROM change_set) s"; }
# Bedøm en kørsel: $1 = exit-kode, $2 = output, $3 = navn, $4 = forventet fejltekst (rød) eller tom (grøn: OK-NOTICE $5
# skal komme).
bedoem() {
  if [ "$1" = 0 ]; then
    [ -z "$4" ] || { echo "$2" >&2; fail "$3 er grøn på basen $base (forventede: $4)"; }
    grep -qF "NOTICE:  $5" <<<"$2" || { echo "$2" >&2; fail "$3: OK-linjen mangler"; }
  else
    [ -n "$4" ] || { echo "$2" >&2; fail "$3 fejlede efter blokken"; }
    grep -qF -- "$4" <<<"$2" || { echo "$2" >&2; fail "$3 fejlede af en anden grund end: $4"; }
  fi; }
unit() { local out rc=0
  out=$(env -u PGOPTIONS psql -X -v ON_ERROR_STOP=1 -d "$1" -f "$tmp/v-$2.sql" 2>&1) || rc=$?
  bedoem "$rc" "$out" "$2" "$3" "$4"; }
units() {
  if [ "$2" = rod ]; then
    unit "$1" r37d4  "FEJL: D4 — valg på en tilbagetrukket konklusion: status tilbagetrukket" ""
    unit "$1" r37d10 "FEJL: D10 — påstand på tilbagetrukket slot uden projektion: konflikt true, status omstridt" ""
    unit "$1" r37d11 "FEJL: D11 — koen med ukendt id gav «(succes)»" ""
  else
    unit "$1" r37d4  "" "OK: review37 D4 "
    unit "$1" r37d10 "" "OK: review37 D10 "
    unit "$1" r37d11 "" "OK: review37 D11 "
  fi; }
build_start() { createdb "$1"; q "$1" -f tests/sql/evidence-promotion-bootstrap.sql
  q "$1" -c 'CREATE EXTENSION IF NOT EXISTS dblink WITH SCHEMA extensions'; }

# 1) Frisk reference.
build_start "$dbf"; q "$dbf" -f schema.sql; q "$dbf" -f db-rls.sql
fresh=$(sha "$dbf"); kat "$dbf" "$tmp/kat-fresh.txt"
[ "$(wc -l <<<"$fresh")" -eq 5 ] || fail "referencen mangler funktioner: $names"

# 2) Prod-formet base med fixtur; enhederne er røde på den.
build_prod() { build_start "$1"
  for f in base-schema.sql base-db-migrations.sql base-db-migrations.sql base-db-rls.sql; do q "$1" -f "$tmp/$f"; done; }
build_prod "$dbp"
[ "$(a "$dbp" "SELECT position('status = ''afklaret''' IN pg_get_functiondef('public.red_set_konklusion(bigint)'::regprocedure))=0
  AND position('findes ikke' IN pg_get_functiondef('public.red_set_koen(bigint,text)'::regprocedure))=0")" = t ] \
  || fail "basen $base har allerede blok 4"
[ "$(a "$dbp" "SELECT to_regprocedure('public.red_slettede_personer(integer)') IS NOT NULL")" = t ] \
  || fail "basen $base mangler P11 (red_slettede_personer)"
[ "$(sha "$dbp")" != "$fresh" ] || fail "basen er allerede byte-ens med schema.sql"
# Fixtur: et faktum med en tilbagetrukket konklusion og et forældre-slot med en afklaret (blokken må ikke røre dem).
q "$dbp" <<'SQL'
DO $fixtur$
BEGIN
  PERFORM set_config('app.change_set_id','',true);
  INSERT INTO person(id,levende,privat) VALUES (-938401,false,false),(-938402,false,false);
  INSERT INTO fact(id,subjekt_type,subjekt_id,faktatype) VALUES (-938421,'person',-938401,'titel');
  INSERT INTO assertion(id,target_type,target_id,vaerdi_tekst,uforanderlig) VALUES (-938431,'fact',-938421,'Fixtur B4',false);
  INSERT INTO conclusion(target_type,target_id,valgt_assertion_id,status) VALUES ('fact',-938421,-938431,'tilbagetrukket');
END $fixtur$;
SQL
units "$dbp" rod
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
fn|red_set_koen(bigint,text)
fn|red_set_konklusion(bigint)
fn|red_set_privat(bigint,boolean)
fn|red_slet_oplysning(bigint)
fn|red_tilfoej_foraeldre_paastand(bigint,bigint,bigint,text,text,text)
EOF
)
[ "$delta" = "$forventet" ] || { diff <(echo "$forventet") <(echo "$delta") >&2 || true; fail "katalog-delta er ikke de fem forventede funktioner"; }
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

# 4) Adfærd på den opgraderede base; fuld db-verify på en anden, ens opgraderet base.
units "$dbp" groen
build_prod "$dbv"
out=$(deploy "$dbv") || { echo "$out" >&2; fail "deploy-transaktionen fejlede på verify-basen"; }
[ "$(sha "$dbv")" = "$fresh" ] || fail "kroppe/ACL afviger på verify-basen"
q "$dbv" -f tests/sql/run-db-verify-disposable.sql
dropdb "$dbf"; dropdb "$dbp"; dropdb "$dbv"
echo R37B4_UPGRADE_OK
