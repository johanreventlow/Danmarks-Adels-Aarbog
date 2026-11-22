#!/usr/bin/env bash
# Review 37 blok 2 (#397: D1 + D12-delen, D3, D5's RPC-del): prods deploy-form. Deploy-området er blokken review37-b2 i
# db-migrations.sql, omgivet af backfillens før-billede og kontrol (tests/sql/review37-b2-backfill-foer.sql og
# tests/sql/review37-b2-backfill.sql) i ÉN psql-transaktion (-1). Ingen db-rls.sql-del (ingen politikker eller
# tabel-ACL ændres); trin 3 beviser, at hele db-rls.sql oveni ikke ændrer noget.
# 1) Frisk reference (bootstrap + dblink + schema.sql + db-rls.sql): kroppe (sha256 af pg_get_functiondef) og ACL for
#    blokkens funktioner + hele kataloget (tests/sql/inspect-catalog-parity.sql).
# 2) Prod-formet base (2. arg; CI pinner 974a6773 = blok 1's head, #434 — prods skema, når blok 1 er anvendt): basens
#    skema + migrationer to gange + rls, og en fast fixtur af personer (medlemskab uden linjekode, linjekode, begge,
#    karantæne, navn med slægtsnavnet som suffiks, flere afklarede navne/dødsfald, medlemskab uden navn, founder).
#    Basen skal mangle rettelserne, og hver verify-enhed (BEGIN-VERIFY r37b2-* i db-verify.sql) skal være RØD på den
#    med sin egen forventede fejl.
# 3) Før-billede + blokken + backfill i én transaktion: backfillens kontrol kræver præcis 1 ændret person (fixturens
#    medlemskab uden linjekode får efternavnet) og intet andet; kroppe/ACL = 1), katalog-delta = præcis de forventede
#    objekter, og hele kataloget = 1). Det hele en gang til ændrer intet (0 personer), og hele db-rls.sql derefter
#    ændrer hverken kroppe, ACL eller politikker.
# 4) Verify-enhederne er GRØNNE på den opgraderede base; fuld db-verify på en anden, ens opgraderet base (uden fixtur).
# Kun lokalt/CI. Ved succes droppes de tre baser, scriptet selv oprettede (<db>_f, <db>_p, <db>_v); ved fejl står de tilbage.
set -euo pipefail
name=${1:?database}; base=${2:?base-commit}
dbf="${name}_f"; dbp="${name}_p"; dbv="${name}_v"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
for f in schema.sql db-rls.sql db-migrations.sql; do git show "$base:$f" > "$tmp/base-$f"; done
q() { env -u PGOPTIONS psql -X -q -v ON_ERROR_STOP=1 -d "$1" "${@:2}" >/dev/null; }
a() { env -u PGOPTIONS psql -X -At -v ON_ERROR_STOP=1 -d "$1" -c "$2"; }
fail() { echo "R37B2_UPGRADE_FAIL: $1" >&2; exit 1; }

# Deploy-området, som prod-runneren skærer det.
awk '$0=="-- BEGIN review37-b2" {p=1} p{print} $0=="-- END review37-b2" {p=0}' db-migrations.sql > "$tmp/blok.sql"
[ "$(head -1 "$tmp/blok.sql")" = "-- BEGIN review37-b2" ] && [ "$(tail -1 "$tmp/blok.sql")" = "-- END review37-b2" ] \
  || fail "blokken review37-b2 mangler eller er ikke afsluttet"
names=$(grep -oE '^CREATE OR REPLACE FUNCTION [a-z_]+\.[a-z0-9_]+' "$tmp/blok.sql" | awk '{print $5}' | sort -u | tr '\n' ' ')
[ "$(wc -w <<<"$names")" -eq 7 ] || fail "forventede 7 funktioner i blokken, fandt: $names"
list=$(for n in $names; do printf "'%s'," "$n"; done); list=${list%,}
# Deploy-transaktionen: før-billede, blok, backfill + kontrol. $2 = forventet antal ændrede personer.
deploy() { env -u PGOPTIONS psql -X -q -1 -v ON_ERROR_STOP=1 -v forventet="$2" -d "$1" \
  -f tests/sql/review37-b2-backfill-foer.sql -f "$tmp/blok.sql" -f tests/sql/review37-b2-backfill.sql 2>&1; }
# Verify-enhederne (selvforsynende DO-blokke i db-verify.sql).
for u in d1 d3 d5; do
  awk -v u="$u" '$0=="-- BEGIN-VERIFY r37b2-" u {p=1} p{print} $0=="-- END-VERIFY r37b2-" u {p=0}' db-verify.sql > "$tmp/v-$u.sql"
  [ "$(head -1 "$tmp/v-$u.sql")" = "-- BEGIN-VERIFY r37b2-$u" ] || fail "verify-enheden r37b2-$u mangler i db-verify.sql"
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
# visning_* + karantæne for alle personer (fixturens tilstand).
cache() { a "$1" "SELECT l FROM (SELECT id::text||'|'||concat_ws('|',coalesce(visning_navn,'-'),coalesce(visning_foedt,'-'),
  coalesce(visning_doed,'-'),coalesce(visning_titel,'-'),coalesce(visning_efternavn,'-'),coalesce(visning_fuldt_navn,'-'),
  coalesce(visning_floruit,'-'))||'|k='||coalesce((SELECT n_distinct::text FROM slaegtsnavn_karantaene k
  WHERE k.person_id=p.id),'-') AS l FROM person p) s ORDER BY l COLLATE \"C\""; }
# Kør en verify-enhed; $3 = forventet fejltekst (rød) eller tom (grøn: OK-NOTICE skal komme).
unit() { local out
  if out=$(env -u PGOPTIONS psql -X -v ON_ERROR_STOP=1 -d "$1" -f "$tmp/v-$2.sql" 2>&1); then
    [ -z "$3" ] || { echo "$out" >&2; fail "r37b2-$2 er grøn på basen $base (forventede: $3)"; }
    grep -q "NOTICE:  OK: review37 " <<<"$out" || { echo "$out" >&2; fail "r37b2-$2: OK-linjen mangler"; }
  else
    [ -n "$3" ] || { echo "$out" >&2; fail "r37b2-$2 fejlede efter blokken"; }
    grep -qF -- "$3" <<<"$out" || { echo "$out" >&2; fail "r37b2-$2 fejlede af en anden grund end: $3"; }
  fi; }
build_start() { createdb "$1"; q "$1" -f tests/sql/evidence-promotion-bootstrap.sql
  q "$1" -c 'CREATE EXTENSION IF NOT EXISTS dblink WITH SCHEMA extensions'; }

# 1) Frisk reference.
build_start "$dbf"; q "$dbf" -f schema.sql; q "$dbf" -f db-rls.sql
fresh=$(sha "$dbf"); kat "$dbf" "$tmp/kat-fresh.txt"
[ "$(wc -l <<<"$fresh")" -eq 7 ] || fail "referencen mangler funktioner: $names"

# 2) Prod-formet base med fixtur, og enhederne er røde på den.
build_prod() { build_start "$1"
  for f in base-schema.sql base-db-migrations.sql base-db-migrations.sql base-db-rls.sql; do q "$1" -f "$tmp/$f"; done; }
build_prod "$dbp"
[ "$(a "$dbp" "SELECT to_regprocedure('private.person_visnings_fakt(bigint,text)') IS NULL
  AND NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='trg_lineage_membership_regen')")" = t ] \
  || fail "basen $base har allerede blok 2"
[ "$(a "$dbp" "SELECT to_regclass('public.ix_bookmark_person_id') IS NOT NULL")" = t ] || fail "basen $base mangler blok 1"
[ "$(sha "$dbp")" != "$fresh" ] || fail "basen er allerede byte-ens med schema.sql"
q "$dbp" <<'SQL'
DO $fixtur$
BEGIN
  PERFORM set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
  INSERT INTO auth.users(id,email) VALUES ('00000000-0000-0000-0000-000000000001','r37b2@test.invalid') ON CONFLICT (id) DO NOTHING;
  INSERT INTO profiles(id,rolle,email) VALUES ('00000000-0000-0000-0000-000000000001','redaktion','t@x')
    ON CONFLICT (id) DO UPDATE SET rolle='redaktion';
  INSERT INTO source(id,slags,titel,import_key) VALUES
    (-937501,'test','r37b2 opgradering','r37b2-u1'),(-937502,'test','r37b2 opgradering 2','r37b2-u2');
  INSERT INTO lineage(id,source_id,kode,navn,slaegtsnavn,parent_lineage_id) VALUES
    (-937511,-937501,'R37U1','U-linje 1','Ufix',NULL),(-937512,-937501,'R37U2','U-linje 2','Ufixto',NULL),
    (-937513,-937501,'R37U3','U-gren',NULL,-937511),(-937514,-937502,'R37U4','U-anden kilde','Uandet',NULL);
  INSERT INTO person(id,levende,privat) SELECT g,false,false FROM generate_series(-937528,-937521) g;
  PERFORM red_upsert_fakta('person',-937521,'navn','Anna');          -- A: medlemskab af grenen, ingen linjekode
  PERFORM red_upsert_fakta('person',-937522,'navn','Bent');          -- B: kun linjekode
  PERFORM red_upsert_fakta('person',-937523,'navn','Carl');          -- C: linjekode + medlemskab, samme linje
  PERFORM red_upsert_fakta('person',-937524,'navn','Dorte Ufixto');  -- D: medlemskab, navnet slutter på slægtsnavnet
  PERFORM red_upsert_fakta('person',-937525,'navn','Erik');          -- E: karantæne (to linjekoder) + medlemskab
  PERFORM red_opret_fakta('person',-937526,'navn','Frederik');       -- F: to navne og to dødsfald, bogens første
  PERFORM red_opret_fakta('person',-937526,'navn','Frands');         --    er også den alfabetisk største / daterede
  PERFORM red_opret_fakta('person',-937526,'død','ung');
  PERFORM red_opret_fakta('person',-937526,'død','1859', p_date_raw => '1859');
  PERFORM red_upsert_fakta('person',-937528,'navn','Hans');          -- H: founder, ikke member; G: medlemskab, intet navn
  PERFORM set_config('app.change_set_id','',true);
  INSERT INTO person_external_id(person_id,source_id,linje,nr) VALUES
    (-937522,-937501,'R37U1',1),(-937523,-937501,'R37U1',2),(-937525,-937501,'R37U1',3),(-937525,-937502,'R37U4',1);
  INSERT INTO person_lineage_membership(person_id,lineage_id,role) VALUES
    (-937521,-937513,'member'),(-937523,-937511,'member'),(-937524,-937512,'member'),(-937525,-937511,'member'),
    (-937527,-937511,'member'),(-937528,-937512,'founder');
END $fixtur$;
SQL
[ "$(a "$dbp" "SELECT count(*) FROM slaegtsnavn_karantaene WHERE person_id=-937525 AND n_distinct=2")" = 1 ] \
  || fail "fixturens karantæne-person mangler"
unit "$dbp" d1 "FEJL: D1 — medlemskab gav intet slægtsnavn"
unit "$dbp" d3 "FEJL: D3 — visningen viser ikke det første navn i bogens orden"
unit "$dbp" d5 "FEJL: D5 — red_upsert_fakta accepterede et omvendt datointerval"
kat "$dbp" "$tmp/kat-foer.txt"
cache_foer=$(cache "$dbp")

# 3) Deploy-transaktionen, derefter det hele igen.
out=$(deploy "$dbp" 1) || { echo "$out" >&2; fail "deploy-transaktionen fejlede"; }
grep -q "NOTICE:  OK: review37 b2 backfill — 1 personer" <<<"$out" || { echo "$out" >&2; fail "backfillens OK-linje mangler"; }
delta_cache=$(LC_ALL=C comm -3 <(echo "$cache_foer") <(cache "$dbp") | sed 's/^\t//')
forventet_cache=$(LC_ALL=C sort <<'EOF'
-937521|Anna|-|-|-|-|Anna|-|k=-
-937521|Anna|-|-|-|Ufix|Anna Ufix|-|k=-
EOF
)
[ "$(LC_ALL=C sort <<<"$delta_cache")" = "$forventet_cache" ] \
  || { diff <(echo "$forventet_cache") <(LC_ALL=C sort <<<"$delta_cache") >&2 || true; fail "cache-delta er ikke kun A's efternavn"; }
[ "$(sha "$dbp")" = "$fresh" ] || { diff <(echo "$fresh") <(sha "$dbp") >&2 || true; fail "kroppe/ACL afviger efter blokken"; }
kat "$dbp" "$tmp/kat-efter.txt"
delta=$(LC_ALL=C comm -3 <(LC_ALL=C sort "$tmp/kat-foer.txt") <(LC_ALL=C sort "$tmp/kat-efter.txt") | sed 's/^\t//' \
  | cut -d'|' -f1,2 | LC_ALL=C sort -u)
forventet=$(LC_ALL=C sort <<'EOF'
fn|private.person_visnings_fakt(bigint,text)
fn|red_opret_fakta(text,bigint,text,text,date,date,text,text,text)
fn|red_tilfoej_oplysning(bigint,text,date,date,text,text,text)
fn|red_upsert_fakta(text,bigint,text,text,date,date,text,text,text)
fn|regen_person_visning(bigint)
fn|trg_regen_from_lineage()
fn|trg_regen_from_lineage_membership()
trg|lineage.trg_lineage_regen
trg|person_lineage_membership.trg_lineage_membership_regen
EOF
)
[ "$delta" = "$forventet" ] || { diff <(echo "$forventet") <(echo "$delta") >&2 || true; fail "katalog-delta er ikke de 9 forventede objekter"; }
bash tests/sql/check-catalog-parity.sh "$tmp/kat-fresh.txt" "$tmp/kat-efter.txt" >/dev/null \
  || { bash tests/sql/check-catalog-parity.sh "$tmp/kat-fresh.txt" "$tmp/kat-efter.txt" || true; fail "kataloget efter blokken ≠ frisk schema.sql"; }
cache_efter=$(cache "$dbp")
out=$(deploy "$dbp" 0) || { echo "$out" >&2; fail "anden deploy-transaktion fejlede"; }
[ "$(sha "$dbp")" = "$fresh" ] || fail "blokken to gange ændrer kroppe/ACL"
kat "$dbp" "$tmp/kat-efter2.txt"
cmp -s "$tmp/kat-efter.txt" "$tmp/kat-efter2.txt" || fail "blokken to gange ændrer kataloget"
[ "$(cache "$dbp")" = "$cache_efter" ] || fail "blokken to gange ændrer visningscachen"
pol_foer=$(pol "$dbp")
[ "$(grep -c '|' <<<"$pol_foer")" -ge 100 ] || fail "politik-snapshottet er tomt"
q "$dbp" -1 -f db-rls.sql
[ "$(sha "$dbp")" = "$fresh" ] || fail "hele db-rls.sql oveni ændrer kroppe/ACL (deploy-området er ufuldstændigt)"
[ "$(pol "$dbp")" = "$pol_foer" ] || { diff <(echo "$pol_foer") <(pol "$dbp") >&2 || true
  fail "hele db-rls.sql oveni ændrer politikker/tabel-ACL (deploy-området er ufuldstændigt)"; }

# 4) Adfærd på den opgraderede base; fuld db-verify på en anden, ens opgraderet base.
for u in d1 d3 d5; do unit "$dbp" "$u" ""; done
build_prod "$dbv"
out=$(deploy "$dbv" 0) || { echo "$out" >&2; fail "deploy-transaktionen fejlede på verify-basen"; }
[ "$(sha "$dbv")" = "$fresh" ] || fail "kroppe/ACL afviger på verify-basen"
q "$dbv" -f tests/sql/run-db-verify-disposable.sql
dropdb "$dbf"; dropdb "$dbp"; dropdb "$dbv"
echo R37B2_UPGRADE_OK
