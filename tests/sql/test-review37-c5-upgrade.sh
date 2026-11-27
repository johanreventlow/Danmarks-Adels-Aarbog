#!/usr/bin/env bash
# Review 37 ceremoni 5 (#397 R37S8-1: redaktionens interne mediefelter via rolle-gatede RPC'er; R37B-3: familie- og
# stedbilleder i blød flet). Prods deploy-form er TO navngivne blokke sidst i db-migrations.sql, hver i sin egen
# psql-transaktion (-1) og på hver sin dag:
#   A `-- BEGIN review37-c5a` … `-- END review37-c5a` (additiv): ny krop for red_slet_medierelation_uden_evidens (samme
#     signatur og ACL) + red_media_interne_felter og red_media_efter_sha (kun authenticated får EXECUTE).
#   B `-- BEGIN review37-c5b` … `-- END review37-c5b` (sidst): authenticated mister tabelretten på media og får PRÆCIS
#     gæsternes kolonneliste. Køres først, når den nye klient er deployet; hele db-rls.sql må ikke køres mellem A og B
#     (filen har B's slutform).
# 1) Frisk reference (bootstrap + dblink + schema.sql + db-rls.sql): hele kataloget (tests/sql/inspect-catalog-parity.sql).
# 2) Prod-formet base (2. arg; CI pinner prods SQL): basens skema + migrationer to gange + rls. Ingen af ændringerne
#    findes på basen (tænder: tjekket nedenfor er RØDT på basen), og den gamle klients læsning virker.
# 3) Blok A: præcis to nye funktionsretter, data uændret, kataloget = frisk på nær media's ACL (16 nøgler: tabellen og
#    dens 15 læserkolonner), og den gamle klients direkte læsning af original_filnavn/sha256 virker STADIG; RPC'erne virker
#    for redaktøren. Blok A to gange ændrer intet.
# 4) Blok B: kataloget og funktionsretterne = frisk, den gamle klients læsning afvises (42501) for redaktøren, mens
#    læserens kolonner virker; B to gange og A+B igen ændrer intet; hele db-rls.sql oveni ændrer hverken politikker,
#    tabel-/kolonne-ACL eller funktionsretter; kaldermatricen (tests/sql/test-review37-c5-kaldere.sql) er grøn.
# 5) Fuld db-verify på en anden, ens opgraderet base (verify-enhederne r37s8 og r37c5a).
# Kun lokalt/CI. Ved succes droppes de tre baser, scriptet selv oprettede (<db>_f, _p, _v); ved fejl står de tilbage.
set -euo pipefail
name=${1:?database}; base=${2:?base-commit}
dbf="${name}_f"; dbp="${name}_p"; dbv="${name}_v"
NYE_RETTER='red_media_efter_sha(text):authenticated red_media_interne_felter(bigint[]):authenticated'  # sorteret (C)
MEDIA_KOL='id slags titel kunstner datering bucket storage_path mime_type byte_size bredde hoejde upload_status maa_publiceres rettigheder_status created_at'
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
for f in schema.sql db-rls.sql db-migrations.sql; do git show "$base:$f" > "$tmp/base-$f"; done
q() { env -u PGOPTIONS psql -X -q -v ON_ERROR_STOP=1 -d "$1" "${@:2}" >/dev/null; }
a() { env -u PGOPTIONS psql -X -At -v ON_ERROR_STOP=1 -d "$1" -c "$2"; }
fail() { echo "R37C5_UPGRADE_FAIL: $1" >&2; exit 1; }

# Deploy-områderne, som prod-runneren skærer dem: A står lige før B, og B står sidst.
skaer() { awk -v fra="-- BEGIN $1" -v til="-- END $1" '$0==fra {p=1} p{print} $0==til {p=0}' db-migrations.sql > "$2"
  [ "$(head -1 "$2")" = "-- BEGIN $1" ] && [ "$(tail -1 "$2")" = "-- END $1" ] || fail "deploy-området $1 mangler i db-migrations.sql"; }
skaer review37-c5a "$tmp/a.sql"; skaer review37-c5b "$tmp/b.sql"
[ "$(tail -1 db-migrations.sql)" = '-- END review37-c5b' ] || fail "blok B skal stå sidst i db-migrations.sql"
cmp -s <(awk '$0=="-- BEGIN review37-c5a" {p=1} p' db-migrations.sql | grep -v '^$') <(cat "$tmp/a.sql" "$tmp/b.sql" | grep -v '^$') \
  || fail "blok A skal stå lige før blok B (og intet efter B)"
# A: kun sætninger i kolonne 0 (funktionskroppene er indrykket): tre funktioner og de nye funktioners REVOKE/GRANT.
! grep -iE '^(drop|alter|grant|revoke|insert into|update |delete from|truncate|do |create (table|index|policy|view))' "$tmp/a.sql" \
  | grep -vxF -e 'REVOKE ALL ON FUNCTION public.red_media_interne_felter(bigint[]) FROM PUBLIC,anon,authenticated,service_role;' \
              -e 'GRANT EXECUTE ON FUNCTION public.red_media_interne_felter(bigint[]) TO authenticated;' \
              -e 'REVOKE ALL ON FUNCTION public.red_media_efter_sha(text) FROM PUBLIC,anon,authenticated,service_role;' \
              -e 'GRANT EXECUTE ON FUNCTION public.red_media_efter_sha(text) TO authenticated;' | grep -q . \
  || fail "blok A må kun rumme CREATE OR REPLACE FUNCTION og de nye funktioners REVOKE/GRANT"
[ "$(grep -c '^CREATE OR REPLACE FUNCTION' "$tmp/a.sql")" = 3 ] || fail "blok A skal rumme præcis 3 funktioner"
# B: kun én DO-blok, der alene revoker/granter på public.media.
[ "$(grep -v '^--' "$tmp/b.sql" | grep -v '^ ' | paste -sd'|' -)" = 'DO $review37_c5b_media_kolonner$|BEGIN|END|$review37_c5b_media_kolonner$;' ] \
  || fail "blok B skal være præcis én DO-blok"
[ "$(grep '^  [A-Z]' "$tmp/b.sql" | grep -vc -e '^  REVOKE ALL ON TABLE public.media FROM ' -e '^  GRANT SELECT (')" = 0 ] \
  && [ "$(grep -c 'ON TABLE public.media TO anon, authenticated;' "$tmp/b.sql")" = 1 ] \
  || fail "blok B må kun revoke/grante på public.media"
deploy() { env -u PGOPTIONS psql -X -q -1 -v ON_ERROR_STOP=1 -d "$1" -f "$2" 2>&1; }

kat() { env -u PGOPTIONS psql -X -Atq -v ON_ERROR_STOP=1 -d "$1" -f tests/sql/inspect-catalog-parity.sql > "$2"; }
facl() { a "$1" "SELECT coalesce(string_agg(l, ' ' ORDER BY l COLLATE \"C\"), '') FROM (
  SELECT p.oid::regprocedure::text||':'||r AS l FROM pg_proc p, (VALUES ('anon'),('authenticated'),('service_role')) v(r)
   WHERE p.pronamespace IN ('public'::regnamespace,'private'::regnamespace) AND has_function_privilege(r, p.oid, 'EXECUTE')) s"; }
# Politikker + tabel-ACL (som c4) + kolonne-ACL (blok B ændrer attacl).
pol() { a "$1" "SELECT l FROM (SELECT schemaname||'.'||tablename||'|'||policyname||'|'||cmd||'|'||roles::text||'|'||
  coalesce(qual,'')||'|'||coalesce(with_check,'') AS l FROM pg_policies WHERE schemaname IN ('public','private')
  UNION ALL SELECT n.nspname||'.'||c.relname||'|acl|'||coalesce(c.relacl::text,'NULL')||'|'||c.relrowsecurity::text
  FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN ('public','private') AND c.relkind IN ('r','v','m','S')
  UNION ALL SELECT n.nspname||'.'||c.relname||'.'||at.attname||'|attacl|'||at.attacl::text
  FROM pg_attribute at JOIN pg_class c ON c.oid=at.attrelid JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname IN ('public','private') AND at.attnum>0 AND NOT at.attisdropped AND at.attacl IS NOT NULL) s
  ORDER BY l COLLATE \"C\""; }
data() { a "$1" "DO \$d\$ DECLARE r record; n bigint; BEGIN
  CREATE TEMP TABLE IF NOT EXISTS _r37c5_rt (t text, n bigint); TRUNCATE _r37c5_rt;
  FOR r IN SELECT c.oid::regclass AS rel FROM pg_class c WHERE c.relnamespace IN ('public'::regnamespace,'private'::regnamespace) AND c.relkind='r' LOOP
    EXECUTE format('SELECT count(*) FROM %s', r.rel) INTO n; INSERT INTO _r37c5_rt VALUES (r.rel::text, n);
  END LOOP; END \$d\$; SELECT md5(string_agg(t||'='||n, ',' ORDER BY t)) FROM _r37c5_rt"; }
# Tænder: »gammel« på basen, »a« efter blok A (RPC'erne + family/place i kroppen), »ny« efter B (+ ingen tabelret).
kroppe() { a "$1" "SELECT CASE WHEN n=0 AND NOT tabel THEN 'blandet' WHEN n=0 THEN 'gammel' WHEN n=3 AND tabel THEN 'a'
    WHEN n=3 THEN 'ny' ELSE 'blandet' END FROM (SELECT
  (to_regprocedure('public.red_media_interne_felter(bigint[])') IS NOT NULL)::int
  + (to_regprocedure('public.red_media_efter_sha(text)') IS NOT NULL)::int
  + (position('''lineage'',''family'',''place''' IN pg_get_functiondef('public.red_slet_medierelation_uden_evidens(bigint)'::regprocedure))>0)::int AS n,
  has_table_privilege('authenticated','public.media','SELECT') AS tabel) s"; }
# Den gamle klients læsning (som authenticated med en redaktørprofil): OK eller SQLSTATE. Rulles tilbage.
redaktoer() { env -u PGOPTIONS psql -X -At -v ON_ERROR_STOP=1 -d "$1" -c "BEGIN;
  INSERT INTO auth.users(id,email) VALUES ('11000000-0000-0000-0000-00000000c5c5','c5@test.invalid') ON CONFLICT DO NOTHING;
  INSERT INTO profiles(id,rolle,email) VALUES ('11000000-0000-0000-0000-00000000c5c5','redaktion','c5@test.invalid')
    ON CONFLICT (id) DO UPDATE SET rolle='redaktion';
  SELECT set_config('request.jwt.claim.sub','11000000-0000-0000-0000-00000000c5c5',true);
  SET LOCAL ROLE authenticated;
  DO \$t\$ BEGIN
    BEGIN PERFORM count(*) FROM ($2) x; RAISE NOTICE 'R37C5_SVAR:OK';
    EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'R37C5_SVAR:%', SQLSTATE; END;
  END \$t\$;
  ROLLBACK;" 2>&1 | sed -n 's/.*R37C5_SVAR:\(.*\)$/\1/p'; }
GAMMEL="SELECT id,original_filnavn,sha256 FROM public.media WHERE sha256 IS DISTINCT FROM 'x'"
LAESER="SELECT id,titel,storage_path,upload_status,byte_size FROM public.media"
RPC="SELECT * FROM public.red_media_interne_felter(ARRAY[1]::bigint[]) UNION ALL SELECT id,titel,storage_path FROM public.red_media_efter_sha(repeat('ab',32))"
build_start() { createdb "$1"; q "$1" -f tests/sql/evidence-promotion-bootstrap.sql
  q "$1" -c 'CREATE EXTENSION IF NOT EXISTS dblink WITH SCHEMA extensions'; }

# 1) Frisk reference.
build_start "$dbf"; q "$dbf" -f schema.sql; q "$dbf" -f db-rls.sql
kat "$dbf" "$tmp/kat-fresh.txt"
facl_fresh=$(facl "$dbf")
pol_fresh_media=$(pol "$dbf" | grep '^public\.media[.|]')
[ "$(kroppe "$dbf")" = "ny" ] || fail "schema.sql + db-rls.sql har ikke ceremoni 5's slutform: $(kroppe "$dbf")"
for k in $MEDIA_KOL; do grep -qE "^public\.media\.$k\|attacl\|\{anon=r/[^,]*,authenticated=r/[^,}]*\}\$" <<<"$pol_fresh_media" \
  || fail "frisk base: media.$k har ikke præcis anon+authenticated SELECT"; done
[ "$(grep -c '|attacl|' <<<"$pol_fresh_media")" = 15 ] || fail "frisk base: media skal have kolonneret på præcis 15 kolonner"
! grep -q '^public\.media\.\(original_filnavn\|sha256\)|attacl|' <<<"$pol_fresh_media" || fail "frisk base giver kolonneret på original_filnavn/sha256"
for r in $NYE_RETTER; do grep -qxF "$r" <<<"$(tr ' ' '\n' <<<"$facl_fresh")" || fail "frisk base giver ikke $r"; done
! tr ' ' '\n' <<<"$facl_fresh" | grep -q '^red_media_\(interne_felter(bigint\[\])\|efter_sha(text)\):\(anon\|service_role\)$' \
  || fail "frisk base giver de nye RPC'er til anon eller service_role"

# 2) Prod-formet base. Prods globale række for postgres er {postgres=X} (db-rls.sql kørt som postgres); lokalt kører
# filen som en anden superbruger, så den gøres eksplicit her (i CI en no-op).
build_prod() { build_start "$1"
  for f in base-schema.sql base-db-migrations.sql base-db-migrations.sql base-db-rls.sql; do q "$1" -f "$tmp/$f"; done
  q "$1" -c "ALTER DEFAULT PRIVILEGES FOR ROLE postgres REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC"; }
build_prod "$dbp"
[ "$(kroppe "$dbp")" = "gammel" ] || fail "basen $base har allerede (dele af) ceremoni 5: $(kroppe "$dbp")"
[ "$(redaktoer "$dbp" "$GAMMEL")" = OK ] || fail "den gamle klients læsning virker ikke på basen (testen har ingen tænder)"
facl_foer=$(facl "$dbp")
data_foer=$(data "$dbp")

# 3) Blok A.
out=$(deploy "$dbp" "$tmp/a.sql") || { echo "$out" >&2; fail "blok A fejlede"; }
[ "$(kroppe "$dbp")" = "a" ] || fail "blok A gav ikke A-formen: $(kroppe "$dbp")"
[ "$(data "$dbp")" = "$data_foer" ] || fail "rækketal ændret af blok A"
facl_a=$(facl "$dbp")
nye=$(comm -13 <(tr ' ' '\n' <<<"$facl_foer" | LC_ALL=C sort) <(tr ' ' '\n' <<<"$facl_a" | LC_ALL=C sort) | paste -sd' ' -)
fjernet=$(comm -23 <(tr ' ' '\n' <<<"$facl_foer" | LC_ALL=C sort) <(tr ' ' '\n' <<<"$facl_a" | LC_ALL=C sort) | paste -sd' ' -)
[ "$nye" = "$NYE_RETTER" ] && [ -z "$fjernet" ] || fail "blok A skulle give præcis to nye retter ($NYE_RETTER); nye=[$nye] fjernet=[$fjernet]"
[ "$facl_a" = "$facl_fresh" ] || { diff <(tr ' ' '\n' <<<"$facl_fresh") <(tr ' ' '\n' <<<"$facl_a") >&2 || true
  fail "funktionsretterne efter blok A ≠ frisk base"; }
# Kataloget = frisk på nær media's ACL: tabellen (authenticated har stadig tabelret) og de 15 læserkolonner.
{ echo 'rel|media'; for k in $MEDIA_KOL; do echo "col|media.$k"; done; } > "$tmp/undt-a.txt"
kat "$dbp" "$tmp/kat-a.txt"
bash tests/sql/check-catalog-parity.sh "$tmp/kat-fresh.txt" "$tmp/kat-a.txt" "$tmp/undt-a.txt" >/dev/null \
  || { bash tests/sql/check-catalog-parity.sh "$tmp/kat-fresh.txt" "$tmp/kat-a.txt" "$tmp/undt-a.txt" || true
       fail "kataloget efter blok A ≠ frisk schema.sql på mere end media's ACL"; }
[ "$(redaktoer "$dbp" "$GAMMEL")" = OK ] || fail "efter blok A virker den gamle klients læsning ikke længere"
[ "$(redaktoer "$dbp" "$RPC")" = OK ] || fail "efter blok A virker RPC'erne ikke for redaktøren"
out=$(deploy "$dbp" "$tmp/a.sql") || { echo "$out" >&2; fail "blok A anden gang fejlede"; }
kat "$dbp" "$tmp/kat-a2.txt"
cmp -s "$tmp/kat-a.txt" "$tmp/kat-a2.txt" || fail "blok A to gange ændrer kataloget"
[ "$(facl "$dbp")" = "$facl_a" ] || fail "blok A to gange ændrer funktionsretterne"

# 4) Blok B.
out=$(deploy "$dbp" "$tmp/b.sql") || { echo "$out" >&2; fail "blok B fejlede"; }
[ "$(kroppe "$dbp")" = "ny" ] || fail "blok B gav ikke slutformen: $(kroppe "$dbp")"
[ "$(data "$dbp")" = "$data_foer" ] || fail "rækketal ændret af blok B"
kat "$dbp" "$tmp/kat-b.txt"
bash tests/sql/check-catalog-parity.sh "$tmp/kat-fresh.txt" "$tmp/kat-b.txt" >/dev/null \
  || { bash tests/sql/check-catalog-parity.sh "$tmp/kat-fresh.txt" "$tmp/kat-b.txt" || true; fail "kataloget efter blok B ≠ frisk schema.sql"; }
[ "$(facl "$dbp")" = "$facl_fresh" ] || fail "funktionsretterne efter blok B ≠ frisk base"
[ "$(pol "$dbp" | grep '^public\.media[.|]')" = "$pol_fresh_media" ] || fail "media's tabel-/kolonne-ACL efter blok B ≠ frisk base (tekst)"
[ "$(redaktoer "$dbp" "$GAMMEL")" = 42501 ] || fail "efter blok B læser redaktøren stadig original_filnavn/sha256 direkte"
[ "$(redaktoer "$dbp" "$LAESER")" = OK ] || fail "efter blok B kan redaktøren ikke læse læserens kolonner"
[ "$(redaktoer "$dbp" "$RPC")" = OK ] || fail "efter blok B virker RPC'erne ikke for redaktøren"
for blk in b a b; do out=$(deploy "$dbp" "$tmp/$blk.sql") || { echo "$out" >&2; fail "blok $blk igen fejlede"; }; done
kat "$dbp" "$tmp/kat-b2.txt"
cmp -s "$tmp/kat-b.txt" "$tmp/kat-b2.txt" || fail "blokkene igen (B, A, B) ændrer kataloget"
[ "$(facl "$dbp")" = "$facl_fresh" ] || fail "blokkene igen ændrer funktionsretterne"
pol_foer=$(pol "$dbp")
[ "$(grep -c '|' <<<"$pol_foer")" -ge 100 ] || fail "politik-snapshottet er tomt"
q "$dbp" -1 -f db-rls.sql
[ "$(pol "$dbp")" = "$pol_foer" ] || fail "hele db-rls.sql oveni ændrer politikker/ACL (deploy-områderne er ufuldstændige)"
[ "$(facl "$dbp")" = "$facl_fresh" ] || fail "hele db-rls.sql oveni ændrer funktionsretterne"
out=$(env -u PGOPTIONS psql -X -v ON_ERROR_STOP=1 -d "$dbp" -f tests/sql/test-review37-c5-kaldere.sql 2>&1) \
  && grep -q 'OK: review37 c5 kaldere' <<<"$out" || { echo "$out" >&2; fail "kaldermatricen fejlede efter blok B"; }

# 5) Fuld db-verify på en anden, ens opgraderet base.
build_prod "$dbv"
for blk in a b; do out=$(deploy "$dbv" "$tmp/$blk.sql") || { echo "$out" >&2; fail "blok $blk fejlede på verify-basen"; }; done
q "$dbv" -f tests/sql/run-db-verify-disposable.sql
dropdb "$dbf"; dropdb "$dbp"; dropdb "$dbv"
echo R37C5_UPGRADE_OK
