#!/usr/bin/env bash
# Godsernes oprydning, fase 1 (#471). Prods deploy-form: blokken `-- BEGIN godser-fase1` … `-- END godser-fase1` sidst
# i db-migrations.sql alene, i ÉN psql-transaktion (-1). Blokken indsætter ordlisten estate_slags (5 vocab-rækker),
# skaber to triggerfunktioner i private med deres triggere (trg_estate_slags på estate, trg_estate_relation_vagt på
# relation) og fem red_*-RPC'er med REVOKE + GRANT til authenticated (db-rls.sql's allow-liste nævner dem også, så hele
# db-rls.sql oveni ændrer intet; den køres ikke i prod-ceremonien, jf. ACCESS EXCLUSIVE-låsene).
# 1) Frisk reference (bootstrap + dblink + schema.sql + db-rls.sql): hele kataloget; verify-enheden er grøn.
# 2) Prod-formet base (2. arg = prods SQL): basens skema + migrationer to gange + rls; postgres' globale standardret til
#    PUBLIC fjernet som i prod (ceremoni 1), og på deploy-basen tilmed en standardret, der giver nye funktioner EXECUTE til
#    klientrollerne (så blokkens REVOKE skal navngive dem). Godser, en afdød og et ejerforhold som i prod (slags NULL).
#    Intet af blokken findes på basen, og verify-enheden er RØD på den.
# 3) Deploy-transaktionen: kataloget efter = frisk; funktionsretterne = frisk og præcis de fem nye retter
#    (red_*:authenticated); kun vocab ændres (+5), godserne og relationerne er uændrede; blokken to gange ændrer intet, og
#    hele db-rls.sql oveni ændrer hverken politikker, ACL eller funktionsretter.
# 4) Enheden er GRØN på den opgraderede base; fuld db-verify på en anden, ens opgraderet base.
# Kun lokalt/CI. Ved succes droppes de tre baser, scriptet selv oprettede (<db>_f, _p, _v); ved fejl står de tilbage.
set -euo pipefail
name=${1:?database}; base=${2:?base-commit}
dbf="${name}_f"; dbp="${name}_p"; dbv="${name}_v"
FRA='-- BEGIN godser-fase1'; TIL='-- END godser-fase1'; N_FN=7; N_TRIG=2; N_VOCAB=5
# regprocedure::text uden public. (search_path), sorteret som facl() (COLLATE "C").
NYE_RETTER='red_flyt_estate_relation(bigint,bigint):authenticated red_hoerer_under(bigint,bigint,text,bigint,text):authenticated red_kopier_ejerforhold(bigint,bigint,text):authenticated red_saet_estate(bigint,text,text):authenticated red_sammenlaeg_estate(bigint,bigint):authenticated'
RPC='red_saet_estate(bigint,text,text) red_flyt_estate_relation(bigint,bigint) red_sammenlaeg_estate(bigint,bigint) red_kopier_ejerforhold(bigint,bigint,text) red_hoerer_under(bigint,bigint,text,bigint,text)'
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
for f in schema.sql db-rls.sql db-migrations.sql; do git show "$base:$f" > "$tmp/base-$f"; done
q() { env -u PGOPTIONS psql -X -q -v ON_ERROR_STOP=1 -d "$1" "${@:2}" >/dev/null; }
a() { env -u PGOPTIONS psql -X -At -v ON_ERROR_STOP=1 -d "$1" -c "$2"; }
fail() { echo "GODSER_FASE1_UPGRADE_FAIL: $1" >&2; exit 1; }

# Deploy-området, som prod-runneren skærer det (skal stå sidst).
awk -v fra="$FRA" -v til="$TIL" '$0==fra {p=1} p{print} $0==til {p=0}' db-migrations.sql > "$tmp/deploy.sql"
[ "$(head -1 "$tmp/deploy.sql")" = "$FRA" ] && [ "$(tail -1 "$tmp/deploy.sql")" = "$TIL" ] \
  || fail "deploy-området $FRA … $TIL mangler i db-migrations.sql"
[ "$(tail -1 db-migrations.sql)" = "$TIL" ] || fail "blokken godser-fase1 skal stå sidst i db-migrations.sql"
# Kun sætninger i kolonne 0 (funktionskroppene er indrykket). Tilladt: CREATE OR REPLACE FUNCTION/TRIGGER, INSERT i
# vocab, REVOKE ALL på blokkens egne funktioner og GRANT EXECUTE til authenticated på de fem RPC'er — intet andet.
tilladt="$tmp/tilladt.txt"; : > "$tilladt"
for f in private.validate_estate_slags\(\) private.validate_estate_relation\(\); do
  echo "REVOKE ALL ON FUNCTION $f FROM PUBLIC,anon,authenticated,service_role;" >> "$tilladt"; done
for f in $RPC; do
  echo "REVOKE ALL ON FUNCTION public.$f FROM PUBLIC,anon,authenticated,service_role;" >> "$tilladt"
  echo "GRANT EXECUTE ON FUNCTION public.$f TO authenticated;" >> "$tilladt"; done
! grep -iE '^(drop|alter|grant|revoke|update |delete from|truncate|create (table|index|unique|policy|view|or replace view))' "$tmp/deploy.sql" \
  | grep -vxF -f "$tilladt" | grep -q . \
  || fail "blokken må hverken droppe, ændre eller give andre retter end REVOKE/GRANT på sine egne funktioner"
[ "$(grep -ciE '^(revoke|grant) ' "$tmp/deploy.sql")" = "$(wc -l < "$tilladt" | tr -d ' ')" ] \
  || fail "blokken skal rumme præcis de $(wc -l < "$tilladt" | tr -d ' ') REVOKE/GRANT-linjer"
! grep -iE '^insert into' "$tmp/deploy.sql" | grep -qviE '^insert into vocab ' || fail "blokken må kun indsætte i vocab"
[ "$(grep -c '^CREATE OR REPLACE FUNCTION' "$tmp/deploy.sql")" = "$N_FN" ] || fail "blokken skal rumme præcis $N_FN funktioner"
[ "$(grep -c '^CREATE OR REPLACE TRIGGER' "$tmp/deploy.sql")" = "$N_TRIG" ] || fail "blokken skal rumme præcis $N_TRIG triggere"
deploy() { env -u PGOPTIONS psql -X -q -1 -v ON_ERROR_STOP=1 -d "$1" -f "$tmp/deploy.sql" 2>&1; }
awk '$0=="-- BEGIN-VERIFY godser-fase1" {p=1} p{print} $0=="-- END-VERIFY godser-fase1" {p=0}' db-verify.sql > "$tmp/v-unit.sql"
[ "$(head -1 "$tmp/v-unit.sql")" = "-- BEGIN-VERIFY godser-fase1" ] && [ "$(tail -1 "$tmp/v-unit.sql")" = "-- END-VERIFY godser-fase1" ] \
  || fail "verify-enheden godser-fase1 mangler i db-verify.sql"

kat() { env -u PGOPTIONS psql -X -Atq -v ON_ERROR_STOP=1 -d "$1" -f tests/sql/inspect-catalog-parity.sql > "$2"; }
# Funktionsretter for anon/authenticated/service_role på public- og private-funktioner.
facl() { a "$1" "SELECT coalesce(string_agg(l, ' ' ORDER BY l COLLATE \"C\"), '') FROM (
  SELECT p.oid::regprocedure::text||':'||r AS l FROM pg_proc p, (VALUES ('anon'),('authenticated'),('service_role')) v(r)
   WHERE p.pronamespace IN ('public'::regnamespace,'private'::regnamespace) AND has_function_privilege(r, p.oid, 'EXECUTE')) s"; }
pol() { a "$1" "SELECT l FROM (SELECT schemaname||'.'||tablename||'|'||policyname||'|'||cmd||'|'||roles::text||'|'||
  coalesce(qual,'')||'|'||coalesce(with_check,'') AS l FROM pg_policies WHERE schemaname IN ('public','private')
  UNION ALL SELECT n.nspname||'.'||c.relname||'|acl|'||coalesce(c.relacl::text,'NULL')||'|'||c.relrowsecurity::text
  FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN ('public','private') AND c.relkind IN ('r','v','m','S')) s
  ORDER BY l COLLATE \"C\""; }
# Rækketal pr. tabel uden for vocab, vocab-tallet og indholdet af estate og relation hver for sig.
data() { env -u PGOPTIONS psql -X -Atq -v ON_ERROR_STOP=1 -d "$1" -c "DO \$d\$ DECLARE r record; n bigint; BEGIN
  CREATE TEMP TABLE IF NOT EXISTS _g471_rt (t text, n bigint); TRUNCATE _g471_rt;
  FOR r IN SELECT c.oid::regclass AS rel FROM pg_class c WHERE c.relnamespace IN ('public'::regnamespace,'private'::regnamespace) AND c.relkind='r' LOOP
    EXECUTE format('SELECT count(*) FROM %s', r.rel) INTO n; INSERT INTO _g471_rt VALUES (r.rel::text, n);
  END LOOP; END \$d\$;
  SELECT md5(string_agg(t||'='||n, ',' ORDER BY t COLLATE \"C\")) FROM _g471_rt WHERE t<>'vocab';
  SELECT n FROM _g471_rt WHERE t='vocab';
  SELECT md5(coalesce(string_agg(id||':'||navn||':'||coalesce(slags,'NULL'), ',' ORDER BY id), '')) FROM public.estate;
  SELECT md5(coalesce(string_agg(id||':'||subjekt_type||subjekt_id||':'||objekt_type||objekt_id||':'||rolle, ',' ORDER BY id), ''))
    FROM public.relation"; }
# Enheden: tom forventning = grøn med alle tre OK-linjer; ellers rød med netop den tekst.
unit() { local out
  if out=$(env -u PGOPTIONS psql -X -v ON_ERROR_STOP=1 -d "$1" -f "$tmp/v-unit.sql" 2>&1); then
    [ -z "$2" ] || { echo "$out" >&2; fail "godser-fase1 er grøn på $1 (forventede: $2)"; }
    [ "$(grep -c 'NOTICE:  OK: godser-fase1 — ' <<<"$out")" = 3 ] || { echo "$out" >&2; fail "godser-fase1: en af de tre OK-linjer mangler"; }
  else
    [ -n "$2" ] || { echo "$out" >&2; fail "godser-fase1 fejlede efter blokken"; }
    grep -qF -- "$2" <<<"$out" || { echo "$out" >&2; fail "godser-fase1 fejlede af en anden grund end: $2"; }
  fi; }
artefakter() { a "$1" "SELECT (SELECT count(*) FROM public.vocab WHERE scheme='estate_slags')||','||
  (SELECT count(*) FROM pg_proc WHERE oid::regprocedure::text IN ('private.validate_estate_slags()','private.validate_estate_relation()',
     'red_saet_estate(bigint,text,text)','red_flyt_estate_relation(bigint,bigint)','red_sammenlaeg_estate(bigint,bigint)',
     'red_kopier_ejerforhold(bigint,bigint,text)','red_hoerer_under(bigint,bigint,text,bigint,text)'))||','||
  (SELECT count(*) FROM pg_trigger WHERE tgname IN ('trg_estate_slags','trg_estate_relation_vagt') AND NOT tgisinternal)"; }
build_start() { createdb "$1"; q "$1" -f tests/sql/evidence-promotion-bootstrap.sql
  q "$1" -c 'CREATE EXTENSION IF NOT EXISTS dblink WITH SCHEMA extensions'; }
# Prods globale række for postgres er {postgres=X} (ceremoni 1); lokalt kører filerne som en anden superbruger, så den
# gøres eksplicit her (i CI en no-op). Godserne som i prod: slags NULL, ét ejerforhold fra en afdød.
build_prod() { build_start "$1"
  for f in base-schema.sql base-db-migrations.sql base-db-migrations.sql base-db-rls.sql; do q "$1" -f "$tmp/$f"; done
  q "$1" -c "ALTER DEFAULT PRIVILEGES FOR ROLE postgres REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC"
  q "$1" -c "INSERT INTO public.estate(id,navn) VALUES (-947101,'Christianssæde med Pederstrup'),(-947102,'Pederstrup'),(-947103,'Wittenberg');
    INSERT INTO public.person(id,levende) VALUES (-947101,false);
    INSERT INTO public.relation(id,subjekt_type,subjekt_id,objekt_type,objekt_id,rolle,periode_raw)
      VALUES (-947101,'person',-947101,'estate',-947101,'ejer','1700-1720')"; }

# 1) Frisk reference.
build_start "$dbf"; q "$dbf" -f schema.sql; q "$dbf" -f db-rls.sql
kat "$dbf" "$tmp/kat-fresh.txt"
facl_fresh=$(facl "$dbf")
[ "$(artefakter "$dbf")" = "$N_VOCAB,$N_FN,$N_TRIG" ] || fail "schema.sql har ikke godser-fase1: $(artefakter "$dbf")"
for r in $NYE_RETTER; do grep -qxF "$r" <<<"$(tr ' ' '\n' <<<"$facl_fresh")" || fail "frisk base giver ikke $r"; done
! tr ' ' '\n' <<<"$facl_fresh" | grep -E '^(red_saet_estate|red_flyt_estate_relation|red_sammenlaeg_estate|red_kopier_ejerforhold|red_hoerer_under)\(.*:(anon|service_role)$|^private\.validate_estate_' | grep -q . \
  || fail "frisk base giver en af blokkens funktioner til anon/service_role, eller en triggerfunktion til en klientrolle"
unit "$dbf" ""

# 2) Prod-formet base; intet af blokken findes, og enheden er rød på den.
build_prod "$dbp"
# Standardrettighed: nye funktioner (alle skemaer), som postgres opretter, får EXECUTE til klientrollerne.
q "$dbp" -c "ALTER DEFAULT PRIVILEGES FOR ROLE postgres GRANT EXECUTE ON FUNCTIONS TO anon, authenticated, service_role"
[ "$(artefakter "$dbp")" = "0,0,0" ] || fail "basen $base har allerede ordlisten, funktionerne eller triggerne: $(artefakter "$dbp")"
unit "$dbp" "VERIFY_FAILED: godser-fase1 — vocab estate_slags ≠ den faste liste"
facl_foer=$(facl "$dbp")
data_foer=$(data "$dbp")

# 3) Deploy-transaktionen, derefter det hele igen.
out=$(deploy "$dbp") || { echo "$out" >&2; fail "deploy-transaktionen fejlede"; }
[ "$(artefakter "$dbp")" = "$N_VOCAB,$N_FN,$N_TRIG" ] || fail "blokken gav ikke ordlisten, funktionerne og triggerne: $(artefakter "$dbp")"
data_efter=$(data "$dbp")
[ "$(sed -n 1p <<<"$data_efter")" = "$(sed -n 1p <<<"$data_foer")" ] || fail "rækketal uden for vocab ændret af blokken"
[ "$(sed -n 2p <<<"$data_efter")" = "$(( $(sed -n 2p <<<"$data_foer") + N_VOCAB ))" ] || fail "vocab fik ikke præcis $N_VOCAB nye rækker"
[ "$(sed -n 3p <<<"$data_efter")" = "$(sed -n 3p <<<"$data_foer")" ] || fail "estate-rækkerne ændret af blokken"
[ "$(sed -n 4p <<<"$data_efter")" = "$(sed -n 4p <<<"$data_foer")" ] || fail "relation-rækkerne ændret af blokken"
kat "$dbp" "$tmp/kat-efter.txt"
bash tests/sql/check-catalog-parity.sh "$tmp/kat-fresh.txt" "$tmp/kat-efter.txt" >/dev/null \
  || { bash tests/sql/check-catalog-parity.sh "$tmp/kat-fresh.txt" "$tmp/kat-efter.txt" || true; fail "kataloget efter blokken ≠ frisk schema.sql"; }
facl_efter=$(facl "$dbp")
nye=$(comm -13 <(tr ' ' '\n' <<<"$facl_foer" | LC_ALL=C sort) <(tr ' ' '\n' <<<"$facl_efter" | LC_ALL=C sort) | paste -sd' ' -)
fjernet=$(comm -23 <(tr ' ' '\n' <<<"$facl_foer" | LC_ALL=C sort) <(tr ' ' '\n' <<<"$facl_efter" | LC_ALL=C sort) | paste -sd' ' -)
[ "$nye" = "$NYE_RETTER" ] && [ -z "$fjernet" ] || fail "blokken skulle give præcis de fem nye retter; nye=[$nye] fjernet=[$fjernet]"
[ "$facl_efter" = "$facl_fresh" ] || { diff <(tr ' ' '\n' <<<"$facl_fresh") <(tr ' ' '\n' <<<"$facl_efter") >&2 || true
  fail "funktionsretterne efter blokken ≠ frisk base"; }
out=$(deploy "$dbp") || { echo "$out" >&2; fail "anden deploy-transaktion fejlede"; }
kat "$dbp" "$tmp/kat-efter2.txt"
cmp -s "$tmp/kat-efter.txt" "$tmp/kat-efter2.txt" || fail "blokken to gange ændrer kataloget"
[ "$(data "$dbp")" = "$data_efter" ] || fail "blokken to gange ændrer data"
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
out=$(env -u PGOPTIONS psql -X -v ON_ERROR_STOP=1 -d "$dbv" -f tests/sql/run-db-verify-disposable.sql 2>&1) \
  || { echo "$out" | grep -E 'ERROR|FEJL' >&2; fail "fuld db-verify fejlede på verify-basen"; }
grep -q "NOTICE:  OK: full db-verify.sql completed" <<<"$out" || fail "fuld db-verify: OK-linjen mangler"
grep -q "NOTICE:  OK: godser-fase1 — red_saet_estate" <<<"$out" || fail "fuld db-verify kørte ikke enheden godser-fase1"
dropdb "$dbf"; dropdb "$dbp"; dropdb "$dbv"
echo GODSER_FASE1_UPGRADE_OK
