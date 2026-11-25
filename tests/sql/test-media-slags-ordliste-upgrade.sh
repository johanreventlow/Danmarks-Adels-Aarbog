#!/usr/bin/env bash
# Billedtype som kontrolleret ordliste (spec docs/superpowers/specs/2026-11-25-media-slags-ordliste-design.md). Prods
# deploy-form: blokken `-- BEGIN media-slags-ordliste` sidst i db-migrations.sql alene, i ÉN psql-transaktion (-1), efter
# dataflytningen (R/media-slags-flytning.R).
# 1) Frisk reference (bootstrap + dblink + schema.sql + db-rls.sql): hele kataloget; verify-enheden er grøn.
# 2) Prod-formet base (2. arg = prods SQL): basens skema + migrationer to gange + rls, plus en global standardrettighed,
#    der giver nye funktioner EXECUTE til klientrollerne (så blokkens REVOKE skal navngive dem). Medier med gyldige
#    koder. Verify-enheden er RØD på basen.
# 3) Vagten: en base med en gammel værdi, NULL og en ukendt værdi afvises med antallet, og intet af blokken står tilbage.
# 4) Deploy-transaktionen: kataloget efter = frisk; kun vocab ændres (+6); det hele en gang til ændrer intet, og hele
#    db-rls.sql oveni ændrer hverken politikker, ACL eller funktionsretter.
# 5) Enheden er GRØN på den opgraderede base; fuld db-verify på en anden, ens opgraderet base.
# Kun lokalt/CI. Ved succes droppes de baser, scriptet selv oprettede (<db>_f, _p, _n, _v); ved fejl står de tilbage.
set -euo pipefail
name=${1:?database}; base=${2:?base-commit}
dbf="${name}_f"; dbp="${name}_p"; dbn="${name}_n"; dbv="${name}_v"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
for f in schema.sql db-rls.sql db-migrations.sql; do git show "$base:$f" > "$tmp/base-$f"; done
q() { env -u PGOPTIONS psql -X -q -v ON_ERROR_STOP=1 -d "$1" "${@:2}" >/dev/null; }
a() { env -u PGOPTIONS psql -X -At -v ON_ERROR_STOP=1 -d "$1" -c "$2"; }
fail() { echo "MEDIA_SLAGS_UPGRADE_FAIL: $1" >&2; exit 1; }

# Deploy-området, som prod-runneren skærer det: migrationsblokken (skal stå sidst).
awk '$0=="-- BEGIN media-slags-ordliste" {p=1} p{print} $0=="-- END media-slags-ordliste" {p=0}' db-migrations.sql > "$tmp/deploy.sql"
[ "$(head -1 "$tmp/deploy.sql")" = '-- BEGIN media-slags-ordliste' ] && [ "$(tail -1 "$tmp/deploy.sql")" = '-- END media-slags-ordliste' ] \
  || fail "blokken media-slags-ordliste mangler i db-migrations.sql"
[ "$(tail -1 db-migrations.sql)" = '-- END media-slags-ordliste' ] || fail "blokken media-slags-ordliste skal stå sidst i db-migrations.sql"
# Kun sætninger i kolonne 0 (funktionskroppen er indrykket). Ingen DROP/ALTER/GRANT/skrivning; INSERT kun i vocab.
! grep -qiE '^(drop|alter|grant|update |delete from|truncate)' "$tmp/deploy.sql" \
  || fail "blokken må hverken droppe, ændre, give rettigheder eller skrive andet end vocab"
! grep -iE '^insert into' "$tmp/deploy.sql" | grep -qviE '^insert into vocab ' || fail "blokken må kun indsætte i vocab"
deploy() { env -u PGOPTIONS psql -X -q -1 -v ON_ERROR_STOP=1 -d "$1" -f "$tmp/deploy.sql" 2>&1; }
awk '$0=="-- BEGIN-VERIFY media-slags" {p=1} p{print} $0=="-- END-VERIFY media-slags" {p=0}' db-verify.sql > "$tmp/v-unit.sql"
[ "$(head -1 "$tmp/v-unit.sql")" = "-- BEGIN-VERIFY media-slags" ] || fail "verify-enheden media-slags mangler i db-verify.sql"

kat() { env -u PGOPTIONS psql -X -Atq -v ON_ERROR_STOP=1 -d "$1" -f tests/sql/inspect-catalog-parity.sql > "$2"; }
# Funktionsretter for PUBLIC/anon/authenticated/service_role på public- og private-funktioner.
facl() { a "$1" "SELECT coalesce(string_agg(l, ' ' ORDER BY l COLLATE \"C\"), '') FROM (
  SELECT p.oid::regprocedure::text||':'||r AS l FROM pg_proc p, (VALUES ('anon'),('authenticated'),('service_role')) v(r)
   WHERE p.pronamespace IN ('public'::regnamespace,'private'::regnamespace) AND has_function_privilege(r, p.oid, 'EXECUTE')) s"; }
pol() { a "$1" "SELECT l FROM (SELECT schemaname||'.'||tablename||'|'||policyname||'|'||cmd||'|'||roles::text||'|'||
  coalesce(qual,'')||'|'||coalesce(with_check,'') AS l FROM pg_policies WHERE schemaname IN ('public','private')
  UNION ALL SELECT n.nspname||'.'||c.relname||'|acl|'||coalesce(c.relacl::text,'NULL')||'|'||c.relrowsecurity::text
  FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN ('public','private') AND c.relkind IN ('r','v','m','S')) s
  ORDER BY l COLLATE \"C\""; }
# Rækketal pr. tabel uden for vocab, vocab-tallet og media-indholdet (id, slags) hver for sig.
data() { env -u PGOPTIONS psql -X -Atq -v ON_ERROR_STOP=1 -d "$1" -c "DO \$d\$ DECLARE r record; n bigint; BEGIN
  CREATE TEMP TABLE IF NOT EXISTS _ms_rt (t text, n bigint); TRUNCATE _ms_rt;
  FOR r IN SELECT c.oid::regclass AS rel FROM pg_class c WHERE c.relnamespace IN ('public'::regnamespace,'private'::regnamespace) AND c.relkind='r' LOOP
    EXECUTE format('SELECT count(*) FROM %s', r.rel) INTO n; INSERT INTO _ms_rt VALUES (r.rel::text, n);
  END LOOP; END \$d\$;
  SELECT md5(string_agg(t||'='||n, ',' ORDER BY t COLLATE \"C\")) FROM _ms_rt WHERE t<>'vocab';
  SELECT n FROM _ms_rt WHERE t='vocab';
  SELECT md5(coalesce(string_agg(id||':'||coalesce(slags,'NULL'), ',' ORDER BY id), '')) FROM public.media"; }
unit() { local out
  if out=$(env -u PGOPTIONS psql -X -v ON_ERROR_STOP=1 -d "$1" -f "$tmp/v-unit.sql" 2>&1); then
    [ -z "$2" ] || { echo "$out" >&2; fail "media-slags er grøn på $1 (forventede: $2)"; }
    grep -q "NOTICE:  OK: media-slags" <<<"$out" || { echo "$out" >&2; fail "media-slags: OK-linjen mangler"; }
  else
    [ -n "$2" ] || { echo "$out" >&2; fail "media-slags fejlede efter blokken"; }
    grep -qF -- "$2" <<<"$out" || { echo "$out" >&2; fail "media-slags fejlede af en anden grund end: $2"; }
  fi; }
build_start() { createdb "$1"; q "$1" -f tests/sql/evidence-promotion-bootstrap.sql
  q "$1" -c 'CREATE EXTENSION IF NOT EXISTS dblink WITH SCHEMA extensions'; }
build_prod() { build_start "$1"
  for f in base-schema.sql base-db-migrations.sql base-db-migrations.sql base-db-rls.sql; do q "$1" -f "$tmp/$f"; done; }
# Medier uden om RPC'erne (ingen change_set → ingen logning); 'portræt' og 'våben' er gyldige efter dataflytningen.
seed() { q "$1" -c "INSERT INTO public.media(id,slags,titel) VALUES $2"; }
artefakter() { a "$1" "SELECT (SELECT count(*) FROM public.vocab WHERE scheme='media_slags')||','||
  (to_regprocedure('private.validate_media_slags()') IS NOT NULL)::text||','||
  (SELECT count(*) FROM pg_trigger WHERE tgrelid='public.media'::regclass AND tgname='trg_media_slags')"; }

# 1) Frisk reference.
build_start "$dbf"; q "$dbf" -f schema.sql; q "$dbf" -f db-rls.sql
kat "$dbf" "$tmp/kat-fresh.txt"
facl_fresh=$(facl "$dbf")
unit "$dbf" ""

# 2) Prod-formet base; enheden er rød på den.
build_prod "$dbp"
# Standardrettighed: nye funktioner (alle skemaer), som postgres opretter, får EXECUTE til klientrollerne.
q "$dbp" -c "ALTER DEFAULT PRIVILEGES FOR ROLE postgres GRANT EXECUTE ON FUNCTIONS TO anon, authenticated, service_role"
seed "$dbp" "(-962501,'portræt','a'),(-962502,'våben','b'),(-962503,'segl','c')"
[ "$(artefakter "$dbp")" = "0,false,0" ] || fail "basen $base har allerede ordlisten, funktionen eller triggeren"
unit "$dbp" "VERIFY_FAILED: media-slags — vocab media_slags ≠ den faste liste"
data_foer=$(data "$dbp")

# 3) Vagten: gamle/ukendte/NULL-værdier stopper blokken, og intet står tilbage (én transaktion).
build_prod "$dbn"
seed "$dbn" "(-962511,'portræt','ok'),(-962512,'maleri','gammel'),(-962513,NULL,'tom'),(-962514,'tegning','ukendt')"
if out=$(deploy "$dbn"); then fail "blokken accepterede en base med gamle/ukendte værdier"; fi
grep -qF 'MEDIA_SLAGS_DATA: 3 media-rækker har en billedtype uden for ordlisten' <<<"$out" \
  || { echo "$out" >&2; fail "vagten fejlede af en anden grund"; }
[ "$(artefakter "$dbn")" = "0,false,0" ] || fail "den afviste blok efterlod vocab-rækker, funktion eller trigger"
[ "$(a "$dbn" "SELECT string_agg(coalesce(slags,'NULL'), ',' ORDER BY id) FROM public.media WHERE id BETWEEN -962514 AND -962511")" \
  = "tegning,NULL,maleri,portræt" ] || fail "den afviste blok ændrede media"

# 4) Deploy-transaktionen, derefter det hele igen.
out=$(deploy "$dbp") || { echo "$out" >&2; fail "deploy-transaktionen fejlede"; }
data_efter=$(data "$dbp")
[ "$(sed -n 1p <<<"$data_efter")" = "$(sed -n 1p <<<"$data_foer")" ] || fail "rækketal uden for vocab ændret af blokken"
[ "$(sed -n 2p <<<"$data_efter")" = "$(( $(sed -n 2p <<<"$data_foer") + 6 ))" ] || fail "vocab fik ikke præcis 6 nye rækker"
[ "$(sed -n 3p <<<"$data_efter")" = "$(sed -n 3p <<<"$data_foer")" ] || fail "media-rækkerne ændret af blokken"
kat "$dbp" "$tmp/kat-efter.txt"
bash tests/sql/check-catalog-parity.sh "$tmp/kat-fresh.txt" "$tmp/kat-efter.txt" >/dev/null \
  || { bash tests/sql/check-catalog-parity.sh "$tmp/kat-fresh.txt" "$tmp/kat-efter.txt" || true; fail "kataloget efter blokken ≠ frisk schema.sql"; }
facl_efter=$(facl "$dbp")
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
[ "$(pol "$dbp")" = "$pol_foer" ] || fail "hele db-rls.sql oveni ændrer politikker/ACL"
[ "$(facl "$dbp")" = "$facl_efter" ] || fail "hele db-rls.sql oveni ændrer funktionsretterne"

# 5) Adfærd på den opgraderede base; fuld db-verify på en anden, ens opgraderet base.
unit "$dbp" ""
build_prod "$dbv"
out=$(deploy "$dbv") || { echo "$out" >&2; fail "deploy-transaktionen fejlede på verify-basen"; }
out=$(env -u PGOPTIONS psql -X -v ON_ERROR_STOP=1 -d "$dbv" -f tests/sql/run-db-verify-disposable.sql 2>&1) \
  || { echo "$out" | grep -E 'ERROR|FEJL' >&2; fail "fuld db-verify fejlede på verify-basen"; }
grep -q "NOTICE:  OK: full db-verify.sql completed" <<<"$out" || fail "fuld db-verify: OK-linjen mangler"
dropdb "$dbf"; dropdb "$dbp"; dropdb "$dbn"; dropdb "$dbv"
echo MEDIA_SLAGS_UPGRADE_OK
