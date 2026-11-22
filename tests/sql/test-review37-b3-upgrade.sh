#!/usr/bin/env bash
# Review 37 blok 3 (#397: S4, D5a, D5b): prods deploy-form. Deploy-området er, i ÉN psql-transaktion (-1):
#   tests/sql/review37-b3-foer.sql (før-kontrol, kun læsning) → DO-blokken $review37_b3_media_gate$ fra db-rls.sql
#   (billed-gaten; ikke hele db-rls.sql, som tager ACCESS EXCLUSIVE på læsernes tabeller) → blokken review37-b3 i
#   db-migrations.sql (funktioner først, tabel-CHECK'erne til sidst).
# 1) Frisk reference (bootstrap + dblink + schema.sql + db-rls.sql): kroppe (sha256 af pg_get_functiondef) og ACL for
#    blokkens og gatens funktioner + hele kataloget (tests/sql/inspect-catalog-parity.sql).
# 2) Prod-formet base (2. arg; CI pinner c356e838 = prods SQL efter blok 2): basens skema + migrationer to gange + rls og
#    en fast fixtur af gyldige rækker (billeder af familier, daterede påstande/relationer/hændelser/historier,
#    medlemskaber, konklusioner). Basen skal mangle blok 3, og hver verify-enhed (BEGIN-VERIFY r37b3-* i db-verify.sql)
#    samt kaldermatricen tests/sql/test-review37-b3-gate.sql skal være RØD på den med sin egen forventede fejl.
# 3) Deploy-transaktionen: før-kontrollen er grøn, kroppe/ACL = frisk, katalog-delta = præcis de forventede objekter,
#    hele kataloget = frisk, og data er uændret. Det hele en gang til ændrer intet, og hele db-rls.sql derefter ændrer
#    hverken kroppe, ACL eller politikker. En kopi med én ulovlig række stopper i før-kontrollen uden at ændre noget,
#    og en kopi med en constraint af samme navn, men anden definition, stopper i blokken.
# 4) Verify-enhederne og kaldermatricen er GRØNNE på den opgraderede base; fuld db-verify på en anden, ens opgraderet
#    base (uden fixtur).
# Kun lokalt/CI. Ved succes droppes de baser, scriptet selv oprettede (<db>_f, _p, _v, _x, _y); ved fejl står de tilbage.
set -euo pipefail
name=${1:?database}; base=${2:?base-commit}
dbf="${name}_f"; dbp="${name}_p"; dbv="${name}_v"; dbx="${name}_x"; dby="${name}_y"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
for f in schema.sql db-rls.sql db-migrations.sql; do git show "$base:$f" > "$tmp/base-$f"; done
q() { env -u PGOPTIONS psql -X -q -v ON_ERROR_STOP=1 -d "$1" "${@:2}" >/dev/null; }
a() { env -u PGOPTIONS psql -X -At -v ON_ERROR_STOP=1 -d "$1" -c "$2"; }
fail() { echo "R37B3_UPGRADE_FAIL: $1" >&2; exit 1; }

# Deploy-området, som prod-runneren skærer det.
awk '$0=="-- BEGIN review37-b3" {p=1} p{print} $0=="-- END review37-b3" {p=0}' db-migrations.sql > "$tmp/blok.sql"
[ "$(head -1 "$tmp/blok.sql")" = "-- BEGIN review37-b3" ] && [ "$(tail -1 "$tmp/blok.sql")" = "-- END review37-b3" ] \
  || fail "blokken review37-b3 mangler eller er ikke afsluttet"
awk '$0=="DO $review37_b3_media_gate$" {p=1} p{print} $0=="$review37_b3_media_gate$;" {p=0}' db-rls.sql > "$tmp/rls.sql"
[ "$(head -1 "$tmp/rls.sql")" = 'DO $review37_b3_media_gate$' ] && [ "$(tail -1 "$tmp/rls.sql")" = '$review37_b3_media_gate$;' ] \
  || fail "DO-blokken \$review37_b3_media_gate\$ mangler i db-rls.sql"
names=$( { cat "$tmp/blok.sql" "$tmp/rls.sql" | grep -ioE '^CREATE OR REPLACE FUNCTION [a-z_.]+\(' || true; } \
  | sed -E 's/.*[Ff][Uu][Nn][Cc][Tt][Ii][Oo][Nn] ([a-z_.]+)\(/\1/; /\./!s/^/public./' | sort -u | tr '\n' ' ')
[ "$(wc -w <<<"$names")" -eq 12 ] || fail "forventede 12 funktioner i deploy-området, fandt: $names"
list=$(for n in $names; do printf "'%s'," "$n"; done); list=${list%,}
deploy() { env -u PGOPTIONS psql -X -q -1 -v ON_ERROR_STOP=1 -d "$1" \
  -f tests/sql/review37-b3-foer.sql -f "$tmp/rls.sql" -f "$tmp/blok.sql" 2>&1; }
for u in s4 gate d5a d5b; do
  awk -v u="$u" '$0=="-- BEGIN-VERIFY r37b3-" u {p=1} p{print} $0=="-- END-VERIFY r37b3-" u {p=0}' db-verify.sql > "$tmp/v-$u.sql"
  [ "$(head -1 "$tmp/v-$u.sql")" = "-- BEGIN-VERIFY r37b3-$u" ] || fail "verify-enheden r37b3-$u mangler i db-verify.sql"
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
# Data i de berørte tabeller (+ person/media/family): én md5 pr. tabel over rækkernes jsonb i id-/nøgleorden.
data() { a "$1" "SELECT string_agg(t||'='||h, ' ' ORDER BY t) FROM (
  SELECT 'assertion' t, md5(coalesce(string_agg(to_jsonb(x)::text, ',' ORDER BY x.id),'')) h FROM assertion x
  UNION ALL SELECT 'conclusion', md5(coalesce(string_agg(to_jsonb(x)::text, ',' ORDER BY x.id),'')) FROM conclusion x
  UNION ALL SELECT 'relation', md5(coalesce(string_agg(to_jsonb(x)::text, ',' ORDER BY x.id),'')) FROM relation x
  UNION ALL SELECT 'haendelse', md5(coalesce(string_agg(to_jsonb(x)::text, ',' ORDER BY x.id),'')) FROM haendelse x
  UNION ALL SELECT 'story', md5(coalesce(string_agg(to_jsonb(x)::text, ',' ORDER BY x.id),'')) FROM story x
  UNION ALL SELECT 'family_member', md5(coalesce(string_agg(to_jsonb(x)::text, ',' ORDER BY x.family_id,x.person_id,x.rolle),''))
    FROM family_member x
  UNION ALL SELECT 'person', md5(coalesce(string_agg(to_jsonb(x)::text, ',' ORDER BY x.id),'')) FROM person x
  UNION ALL SELECT 'media', md5(coalesce(string_agg(to_jsonb(x)::text, ',' ORDER BY x.id),'')) FROM media x
  UNION ALL SELECT 'family', md5(coalesce(string_agg(to_jsonb(x)::text, ',' ORDER BY x.id),'')) FROM family x
  UNION ALL SELECT 'change_set', count(*)::text FROM change_set) s"; }
# Kør en verify-enhed; $3 = forventet fejltekst (rød) eller tom (grøn: OK-NOTICE skal komme).
unit() { local out
  if out=$(env -u PGOPTIONS psql -X -v ON_ERROR_STOP=1 -d "$1" -f "$tmp/v-$2.sql" 2>&1); then
    [ -z "$3" ] || { echo "$out" >&2; fail "r37b3-$2 er grøn på basen $base (forventede: $3)"; }
    grep -q "NOTICE:  OK: review37 " <<<"$out" || { echo "$out" >&2; fail "r37b3-$2: OK-linjen mangler"; }
  else
    [ -n "$3" ] || { echo "$out" >&2; fail "r37b3-$2 fejlede efter blokken"; }
    grep -qF -- "$3" <<<"$out" || { echo "$out" >&2; fail "r37b3-$2 fejlede af en anden grund end: $3"; }
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
[ "$(wc -l <<<"$fresh")" -eq 12 ] || fail "referencen mangler funktioner: $names"

# 2) Prod-formet base med fixtur; enhederne og matricen er røde på den.
build_prod() { build_start "$1"
  for f in base-schema.sql base-db-migrations.sql base-db-migrations.sql base-db-rls.sql; do q "$1" -f "$tmp/$f"; done; }
build_prod "$dbp"
[ "$(a "$dbp" "SELECT NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='relation_afbildet_kanonisk')
  AND to_regprocedure('private.kraev_gyldig_datering(date,date,text)') IS NULL
  AND position('family' IN pg_get_functiondef('public.media_afbilder_skjult(bigint)'::regprocedure))=0")" = t ] \
  || fail "basen $base har allerede blok 3"
[ "$(a "$dbp" "SELECT to_regprocedure('private.person_visnings_fakt(bigint,text)') IS NOT NULL")" = t ] \
  || fail "basen $base mangler blok 2"
[ "$(sha "$dbp")" != "$fresh" ] || fail "basen er allerede byte-ens med schema.sql"
q "$dbp" <<'SQL'
DO $fixtur$
BEGIN
  PERFORM set_config('app.change_set_id','',true);
  INSERT INTO person(id,levende,privat) VALUES (-938501,true,false),(-938502,false,false),(-938503,false,false);
  INSERT INTO family(id,type) VALUES (-938511,'vielse'),(-938512,'vielse');
  INSERT INTO family_member(family_id,person_id,rolle,konfidens) VALUES
    (-938511,-938501,'partner',NULL),(-938511,-938502,'partner','sikker'),
    (-938512,-938502,'partner',NULL),(-938512,-938503,'barn','formodet');
  INSERT INTO media(id,maa_publiceres,upload_status) VALUES (-938521,true,'klar'),(-938522,true,'klar');
  INSERT INTO relation(id,subjekt_type,subjekt_id,objekt_type,objekt_id,rolle,start_min,start_max,end_min,end_max,konfidens) VALUES
    (-938531,'media',-938521,'family',-938511,'afbildet',NULL,NULL,NULL,NULL,NULL),
    (-938532,'person',-938502,'media',-938522,'afbildet',NULL,NULL,NULL,NULL,NULL),
    (-938533,'person',-938502,'estate',-938541,'ejer','1850-01-01','1855-12-31','1840-01-01','1870-12-31','omstridt');
  INSERT INTO fact(id,subjekt_type,subjekt_id,faktatype) VALUES (-938551,'person',-938502,'fødsel');
  INSERT INTO assertion(id,target_type,target_id,date_raw,date_min,date_max,date_qualifier) VALUES
    (-938561,'fact',-938551,'1820','1820-01-01','1820-12-31','between');
  INSERT INTO conclusion(id,target_type,target_id,valgt_assertion_id,status) VALUES (-938571,'fact',-938551,-938561,'afklaret');
  INSERT INTO narrative(id,subjekt_type,subjekt_id,tekst) VALUES (-938581,'person',-938502,'Syntetisk');
  INSERT INTO haendelse(id,subjekt_type,subjekt_id,narrative_id,noegle,klausul,date_min,date_max,date_qualifier) VALUES
    (-938591,'person',-938502,-938581,'r37b3u','x','1830-01-01','1830-12-31','about');
  PERFORM set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
  INSERT INTO story(id,subjekt_type,subjekt_id,tekst,date_min,date_max,date_qualifier) VALUES
    (-938595,'person',-938502,'Syntetisk','1840-01-01','1840-12-31','floruit');
END $fixtur$;
SQL
[ "$(a "$dbp" "SELECT public.media_synlig_anon(-938521)")" = t ] || fail "fixturen: basen skjuler allerede familiens billede"
unit "$dbp" s4 "FEJL: S4 — relation accepterede rollen «Afbildet»"
unit "$dbp" gate "FEJL: gate — billedet af en familie med et levende medlem er ikke skjult"
unit "$dbp" d5a "FEJL: D5a — assertion accepterede et omvendt datointerval"
unit "$dbp" d5b "FEJL: D5b — family_member.rolle accepterede den ukendte værdi «svigerbarn»"
matrix "$dbp" "KALDER_MATRIX_FAILED: billede levende_medlem som gaest"
kat "$dbp" "$tmp/kat-foer.txt"
data_foer=$(data "$dbp")

# 3a) Fejlveje på kopier: en ulovlig række stopper i før-kontrollen; en fremmed definition stopper i blokken.
a postgres "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='$dbp' AND pid<>pg_backend_pid()" >/dev/null
createdb -T "$dbp" "$dbx"; createdb -T "$dbp" "$dby"
q "$dbx" -c "SET app.change_set_id=''" -c "INSERT INTO relation(id,subjekt_type,subjekt_id,objekt_type,objekt_id,rolle)
  VALUES (-938599,'media',-938522,'fact',-938551,'afbildet')"
out=$(deploy "$dbx") && { echo "$out" >&2; fail "deploy accepterede en base med media → fact som afbildet"; }
grep -qF 'R37B3_FOER_OVERTRAEDELSER: {"relation_afbildet_kanonisk": 1}' <<<"$out" || { echo "$out" >&2; fail "før-kontrollen navngav ikke overtrædelsen"; }
[ "$(a "$dbx" "SELECT count(*) FROM pg_constraint WHERE conname='relation_afbildet_kanonisk'")" = 0 ] \
  || fail "en afvist deploy efterlod constraints"
q "$dby" -c "ALTER TABLE public.story ADD CONSTRAINT story_dato_orden CHECK (date_min < date_max)"
out=$(deploy "$dby") && { echo "$out" >&2; fail "blokken accepterede en fremmed story_dato_orden"; }
grep -qF 'R37B3_CONSTRAINT_AFVIGER: story.story_dato_orden' <<<"$out" || { echo "$out" >&2; fail "blokken navngav ikke den fremmede constraint"; }
dropdb "$dbx"; dropdb "$dby"

# 3b) Deploy-transaktionen, derefter det hele igen.
out=$(deploy "$dbp") || { echo "$out" >&2; fail "deploy-transaktionen fejlede"; }
grep -q "NOTICE:  OK: review37 b3 før-kontrol — 0 overtrædelser i 12 constraints" <<<"$out" \
  || { echo "$out" >&2; fail "før-kontrollens OK-linje mangler"; }
[ "$(sha "$dbp")" = "$fresh" ] || { diff <(echo "$fresh") <(sha "$dbp") >&2 || true; fail "kroppe/ACL afviger efter blokken"; }
[ "$(data "$dbp")" = "$data_foer" ] || { diff <(echo "$data_foer" | tr ' ' '\n') <(data "$dbp" | tr ' ' '\n') >&2 || true; fail "data ændret af blokken"; }
kat "$dbp" "$tmp/kat-efter.txt"
delta=$(LC_ALL=C comm -3 <(LC_ALL=C sort "$tmp/kat-foer.txt") <(LC_ALL=C sort "$tmp/kat-efter.txt") | sed 's/^\t//' \
  | cut -d'|' -f1,2 | LC_ALL=C sort -u)
forventet=$(LC_ALL=C sort <<'EOF'
con|assertion.assertion_date_qualifier_chk
con|assertion.assertion_dato_orden
con|conclusion.conclusion_status_chk
con|family_member.family_member_konfidens_chk
con|family_member.family_member_rolle_chk
con|haendelse.haendelse_date_qualifier_chk
con|haendelse.haendelse_dato_orden
con|relation.relation_afbildet_kanonisk
con|relation.relation_konfidens_chk
con|relation.relation_periode_orden
con|story.story_date_qualifier_chk
con|story.story_dato_orden
fn|media_afbilder_privat(bigint)
fn|media_afbilder_skjult(bigint)
fn|private.kraev_gyldig_datering(date,date,text)
fn|private.person_purge_plan_fra_historik(bigint,jsonb)
fn|red_opret_fakta(text,bigint,text,text,date,date,text,text,text)
fn|red_opret_story(text,bigint,text,text,bigint,bigint,bigint,bigint,date,date,text,text,boolean)
fn|red_rediger_story(bigint,text,text,bigint,bigint,bigint,bigint,date,date,text,text,boolean)
fn|red_relation(text,bigint,text,bigint,text,text)
fn|red_ret_ocr_felt(bigint,text,text,text,text,jsonb,text,text)
fn|red_tilfoej_oplysning(bigint,text,date,date,text,text,text)
fn|red_tilfoej_relation(bigint,text,bigint,text,text)
fn|red_upsert_fakta(text,bigint,text,text,date,date,text,text,text)
EOF
)
[ "$delta" = "$forventet" ] || { diff <(echo "$forventet") <(echo "$delta") >&2 || true; fail "katalog-delta er ikke de 24 forventede objekter"; }
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
[ "$(sha "$dbp")" = "$fresh" ] || fail "hele db-rls.sql oveni ændrer kroppe/ACL (deploy-området er ufuldstændigt)"
[ "$(pol "$dbp")" = "$pol_foer" ] || { diff <(echo "$pol_foer") <(pol "$dbp") >&2 || true
  fail "hele db-rls.sql oveni ændrer politikker/tabel-ACL (deploy-området er ufuldstændigt)"; }

# 4) Adfærd på den opgraderede base; fuld db-verify på en anden, ens opgraderet base.
[ "$(a "$dbp" "SELECT public.media_synlig_anon(-938521)")" = f ] || fail "familiens billede er stadig synligt efter blokken"
for u in s4 gate d5a d5b; do unit "$dbp" "$u" ""; done
matrix "$dbp" ""
build_prod "$dbv"
out=$(deploy "$dbv") || { echo "$out" >&2; fail "deploy-transaktionen fejlede på verify-basen"; }
[ "$(sha "$dbv")" = "$fresh" ] || fail "kroppe/ACL afviger på verify-basen"
q "$dbv" -f tests/sql/run-db-verify-disposable.sql
dropdb "$dbf"; dropdb "$dbp"; dropdb "$dbv"
echo R37B3_UPGRADE_OK
