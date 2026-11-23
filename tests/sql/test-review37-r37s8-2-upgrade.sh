#!/usr/bin/env bash
# Review 37 R37S8-2 (#397): anon og authenticated har kun læseret på public-tabeller/-views, ingen ret på
# public-sekvenserne, og ejerens standardrettigheder i public giver ikke længere skriveret/sekvensret til nye objekter.
# Prods deploy-form: KUN DO-blokken $review37_r37s8_2_skriveret$ fra db-rls.sql (ikke hele db-rls.sql, som tager
# ACCESS EXCLUSIVE på læsernes tabeller) i én psql-transaktion (-1).
# 1) Frisk reference (bootstrap + dblink + schema.sql + db-rls.sql): hele kataloget (tests/sql/inspect-catalog-parity.sql,
#    som bærer ACL for PUBLIC/anon/authenticated/service_role på alle relationer og sekvenser).
# 2) Prod-formet base (2. arg; CI pinner prods commit): basens skema + migrationer to gange + rls, derefter
#    Supabase-standardrettighederne, som et frisk byg ikke giver: alle ikke-SELECT-tabelretter til anon og authenticated
#    på hver public-tabel og -view (et overmål af prods ~30 tabeller + 4 views; SELECT seedes IKKE, så S8's kolonneret
#    og tabeller uden klientadgang står som i prod), SELECT/UPDATE/USAGE på hver public-sekvens, og samme standarder i
#    pg_default_acl. Verify-enheden r37s8-2 er RØD på basen.
# 3) Deploy-transaktionen: katalog-delta = kun rel-linjer i public, hele kataloget = frisk, standardrettighederne uden
#    skrive-/sekvensret, rækketal uændret. Det hele en gang til ændrer intet, og hele db-rls.sql derefter ændrer hverken
#    ACL, standardrettigheder eller politikker.
# 4) Enheden er GRØN på den opgraderede base; fuld db-verify på en anden, ens opgraderet base.
# Kun lokalt/CI. Ved succes droppes de tre baser, scriptet selv oprettede (<db>_f, _p, _v); ved fejl står de tilbage.
set -euo pipefail
name=${1:?database}; base=${2:?base-commit}
dbf="${name}_f"; dbp="${name}_p"; dbv="${name}_v"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
for f in schema.sql db-rls.sql db-migrations.sql; do git show "$base:$f" > "$tmp/base-$f"; done
q() { env -u PGOPTIONS psql -X -q -v ON_ERROR_STOP=1 -d "$1" "${@:2}" >/dev/null; }
a() { env -u PGOPTIONS psql -X -At -v ON_ERROR_STOP=1 -d "$1" -c "$2"; }
fail() { echo "R37S8_2_UPGRADE_FAIL: $1" >&2; exit 1; }

# Deploy-området, som prod-runneren skærer det.
awk '$0=="DO $review37_r37s8_2_skriveret$" {p=1} p{print} $0=="$review37_r37s8_2_skriveret$;" {p=0}' db-rls.sql > "$tmp/rls.sql"
[ "$(head -1 "$tmp/rls.sql")" = 'DO $review37_r37s8_2_skriveret$' ] \
  && [ "$(tail -1 "$tmp/rls.sql")" = '$review37_r37s8_2_skriveret$;' ] \
  || fail "DO-blokken \$review37_r37s8_2_skriveret\$ mangler i db-rls.sql"
[ "$(tail -1 db-rls.sql)" = '$review37_r37s8_2_skriveret$;' ] \
  || fail "blokken skal stå sidst i db-rls.sql (den skal se alle tabeller, filen opretter)"
! grep -qiwE 'create|drop|policy|function|insert into|update [a-z_.]+ set|delete from' "$tmp/rls.sql" \
  || fail "DO-blokken må kun rumme REVOKE/GRANT/ALTER DEFAULT PRIVILEGES"
[ "$(grep -ciE '\balter\b' "$tmp/rls.sql")" = "$(grep -ciE '\balter default privileges in schema public\b' "$tmp/rls.sql")" ] \
  || fail "DO-blokken må kun bruge ALTER til ALTER DEFAULT PRIVILEGES IN SCHEMA public"
deploy() { env -u PGOPTIONS psql -X -q -1 -v ON_ERROR_STOP=1 -d "$1" -f "$tmp/rls.sql" 2>&1; }
awk '$0=="-- BEGIN-VERIFY r37s8-2" {p=1} p{print} $0=="-- END-VERIFY r37s8-2" {p=0}' db-verify.sql > "$tmp/v-unit.sql"
[ "$(head -1 "$tmp/v-unit.sql")" = "-- BEGIN-VERIFY r37s8-2" ] || fail "verify-enheden r37s8-2 mangler i db-verify.sql"

# Ejerens standardrettigheder i public for anon/authenticated/PUBLIC, én linje pr. ret (alle typer, også SELECT).
dacl() { a "$1" "SELECT coalesce(string_agg(l, ' ' ORDER BY l COLLATE \"C\"), '') FROM (
  SELECT d.defaclobjtype::text||':'||CASE WHEN x.grantee = 0 THEN 'PUBLIC' ELSE x.grantee::regrole::text END||':'||x.privilege_type AS l
    FROM pg_default_acl d, aclexplode(d.defaclacl) x
   WHERE d.defaclrole = current_user::regrole AND d.defaclnamespace IN (0, 'public'::regnamespace)
     AND x.grantee IN (0, 'anon'::regrole, 'authenticated'::regrole)) s"; }
pol() { a "$1" "SELECT l FROM (SELECT schemaname||'.'||tablename||'|'||policyname||'|'||cmd||'|'||roles::text||'|'||
  coalesce(qual,'')||'|'||coalesce(with_check,'') AS l FROM pg_policies WHERE schemaname IN ('public','private')
  UNION ALL SELECT n.nspname||'.'||c.relname||'|acl|'||coalesce(c.relacl::text,'NULL')||'|'||c.relrowsecurity::text
  FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN ('public','private') AND c.relkind IN ('r','v','m','S')) s
  ORDER BY l COLLATE \"C\""; }
kat() { env -u PGOPTIONS psql -X -Atq -v ON_ERROR_STOP=1 -d "$1" -f tests/sql/inspect-catalog-parity.sql > "$2"; }
# Rækketal pr. public-tabel (blokken rører ingen data; count(*) som ejeren, der bypasser RLS).
data() { a "$1" "DO \$d\$ DECLARE r record; n bigint; BEGIN
  CREATE TEMP TABLE IF NOT EXISTS _r37_rt (t text, n bigint); TRUNCATE _r37_rt;
  FOR r IN SELECT c.oid::regclass AS rel FROM pg_class c WHERE c.relnamespace='public'::regnamespace AND c.relkind='r' LOOP
    EXECUTE format('SELECT count(*) FROM %s', r.rel) INTO n; INSERT INTO _r37_rt VALUES (r.rel::text, n);
  END LOOP; END \$d\$; SELECT md5(string_agg(t||'='||n, ',' ORDER BY t)) FROM _r37_rt"; }
# Kør verify-enheden; $2 = forventet fejltekst (rød) eller tom (grøn: OK-NOTICE skal komme).
unit() { local out
  if out=$(env -u PGOPTIONS psql -X -v ON_ERROR_STOP=1 -d "$1" -f "$tmp/v-unit.sql" 2>&1); then
    [ -z "$2" ] || { echo "$out" >&2; fail "r37s8-2 er grøn på basen $base (forventede: $2)"; }
    grep -q "NOTICE:  OK: review37 R37S8-2" <<<"$out" || { echo "$out" >&2; fail "r37s8-2: OK-linjen mangler"; }
  else
    [ -n "$2" ] || { echo "$out" >&2; fail "r37s8-2 fejlede efter blokken"; }
    grep -qF -- "$2" <<<"$out" || { echo "$out" >&2; fail "r37s8-2 fejlede af en anden grund end: $2"; }
  fi; }
build_start() { createdb "$1"; q "$1" -f tests/sql/evidence-promotion-bootstrap.sql
  q "$1" -c 'CREATE EXTENSION IF NOT EXISTS dblink WITH SCHEMA extensions'; }

# 1) Frisk reference.
build_start "$dbf"; q "$dbf" -f schema.sql; q "$dbf" -f db-rls.sql
kat "$dbf" "$tmp/kat-fresh.txt"
grep -q '^rel|bookmark|' "$tmp/kat-fresh.txt" || fail "referencens katalog mangler bookmark"
[ "$(a "$dbf" "SELECT has_table_privilege('anon','public.person','TRUNCATE')::text")" = false ] \
  || fail "referencen giver anon TRUNCATE på person"

# 2) Prod-formet base med Supabase-standardrettighederne; enheden er rød på den.
build_prod() { build_start "$1"
  for f in base-schema.sql base-db-migrations.sql base-db-migrations.sql base-db-rls.sql; do q "$1" -f "$tmp/$f"; done
  q "$1" -c "DO \$s\$ DECLARE r record; BEGIN
    FOR r IN SELECT c.oid::regclass AS rel FROM pg_class c
              WHERE c.relnamespace='public'::regnamespace AND c.relkind IN ('r','p','v','m','f') LOOP
      EXECUTE format('GRANT INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ON TABLE %s TO anon, authenticated', r.rel);
    END LOOP;
    FOR r IN SELECT c.oid::regclass AS rel FROM pg_class c WHERE c.relnamespace='public'::regnamespace AND c.relkind='S' LOOP
      EXECUTE format('GRANT SELECT, UPDATE, USAGE ON SEQUENCE %s TO anon, authenticated', r.rel);
    END LOOP;
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO anon, authenticated;
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, UPDATE, USAGE ON SEQUENCES TO anon, authenticated;
  END \$s\$"; }
build_prod "$dbp"
[ "$(a "$dbp" "SELECT (has_table_privilege('anon','public.media_variant','TRUNCATE')
   AND has_table_privilege('authenticated','public.story_kilde','MAINTAIN')
   AND has_sequence_privilege('anon','public.person_id_seq','UPDATE'))::text")" = true ] \
  || fail "basen har ikke prods standardrettigheder"
grep -q 'r:anon:TRUNCATE' <<<"$(dacl "$dbp")" || fail "basen har ikke prods standardrettigheder i pg_default_acl"
unit "$dbp" "FEJL: R37S8-2 —"
kat "$dbp" "$tmp/kat-foer.txt"
data_foer=$(data "$dbp")

# 3) Deploy-transaktionen, derefter det hele igen.
out=$(deploy "$dbp") || { echo "$out" >&2; fail "deploy-transaktionen fejlede"; }
[ "$(data "$dbp")" = "$data_foer" ] || fail "rækketal ændret af blokken"
kat "$dbp" "$tmp/kat-efter.txt"
delta=$(LC_ALL=C comm -3 <(LC_ALL=C sort "$tmp/kat-foer.txt") <(LC_ALL=C sort "$tmp/kat-efter.txt") | sed 's/^\t//' \
  | cut -d'|' -f1,2 | LC_ALL=C sort -u)
[ -n "$delta" ] || fail "blokken ændrede intet i kataloget"
# Udtrækket skriver public-objekter uden skemapræfiks (private.* med).
uden=$(grep -vE '^rel\|[a-z0-9_]+$' <<<"$delta" || true)
[ -z "$uden" ] || { echo "$uden" >&2; fail "katalog-delta rører andet end rel-linjer i public"; }
for o in media_variant person person_id_seq red_konflikt story_kilde bookmark; do
  grep -qx "rel|$o" <<<"$delta" || fail "katalog-delta mangler rel|$o"
done
bash tests/sql/check-catalog-parity.sh "$tmp/kat-fresh.txt" "$tmp/kat-efter.txt" >/dev/null \
  || { bash tests/sql/check-catalog-parity.sh "$tmp/kat-fresh.txt" "$tmp/kat-efter.txt" || true; fail "kataloget efter blokken ≠ frisk schema.sql"; }
dacl_efter=$(dacl "$dbp")
! grep -qE '(^| )(r:[a-zA-Z]+:(INSERT|UPDATE|DELETE|TRUNCATE|REFERENCES|TRIGGER|MAINTAIN)|S:)' <<<"$dacl_efter" \
  || fail "standardrettighederne giver stadig skrive-/sekvensret: $dacl_efter"
grep -q 'r:anon:SELECT' <<<"$dacl_efter" || fail "standard-SELECT på nye tabeller forsvandt (skal bevares): $dacl_efter"
out=$(deploy "$dbp") || { echo "$out" >&2; fail "anden deploy-transaktion fejlede"; }
kat "$dbp" "$tmp/kat-efter2.txt"
cmp -s "$tmp/kat-efter.txt" "$tmp/kat-efter2.txt" || fail "blokken to gange ændrer kataloget"
[ "$(dacl "$dbp")" = "$dacl_efter" ] || fail "blokken to gange ændrer standardrettighederne"
pol_foer=$(pol "$dbp")
[ "$(grep -c '|' <<<"$pol_foer")" -ge 100 ] || fail "politik-snapshottet er tomt"
q "$dbp" -1 -f db-rls.sql
[ "$(pol "$dbp")" = "$pol_foer" ] || { diff <(echo "$pol_foer") <(pol "$dbp") >&2 || true
  fail "hele db-rls.sql oveni ændrer politikker/ACL (deploy-området er ufuldstændigt)"; }
[ "$(dacl "$dbp")" = "$dacl_efter" ] || fail "hele db-rls.sql oveni ændrer standardrettighederne"

# 4) Adfærd på den opgraderede base; fuld db-verify på en anden, ens opgraderet base.
unit "$dbp" ""
# En ny tabel efter blokken arver kun SELECT (standard), ingen skriveret; en ny sekvens ingen ret.
a "$dbp" "CREATE TABLE public._r37s8_2_ny (id bigserial PRIMARY KEY)" >/dev/null
[ "$(a "$dbp" "SELECT (has_table_privilege('anon','public._r37s8_2_ny','SELECT')
   AND NOT has_table_privilege('anon','public._r37s8_2_ny','INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER,MAINTAIN')
   AND NOT has_table_privilege('authenticated','public._r37s8_2_ny','INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER,MAINTAIN')
   AND NOT has_sequence_privilege('anon','public._r37s8_2_ny_id_seq','SELECT,UPDATE,USAGE'))::text")" = true ] \
  || fail "en ny tabel/sekvens efter blokken arver stadig skrive-/sekvensret"
a "$dbp" "DROP TABLE public._r37s8_2_ny" >/dev/null
build_prod "$dbv"
out=$(deploy "$dbv") || { echo "$out" >&2; fail "deploy-transaktionen fejlede på verify-basen"; }
q "$dbv" -f tests/sql/run-db-verify-disposable.sql
dropdb "$dbf"; dropdb "$dbp"; dropdb "$dbv"
echo R37S8_2_UPGRADE_OK
