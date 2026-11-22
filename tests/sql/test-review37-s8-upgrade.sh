#!/usr/bin/env bash
# Review 37 S8 (#397): gæster (anon) læser kun læserens kolonner på story, feed_pin og media; anon og authenticated
# har kun SELECT. Prods deploy-form: KUN DO-blokken $review37_s8_anon_kolonner$ fra db-rls.sql (ikke hele
# db-rls.sql, som tager ACCESS EXCLUSIVE på læsernes tabeller) i én psql-transaktion (-1).
# 1) Frisk reference (bootstrap + dblink + schema.sql + db-rls.sql): tabel- og kolonne-ACL for de tre tabeller + hele
#    kataloget (tests/sql/inspect-catalog-parity.sql).
# 2) Prod-formet base (2. arg; CI pinner prods commit): basens skema + migrationer to gange + rls, derefter prods
#    faktiske tabel-ACL (Supabase-standardrettighederne: anon/authenticated har ALL på media og SELECT+MAINTAIN på
#    story/feed_pin), som et frisk byg ikke giver. Basen skal mangle rettelsen: verify-enheden r37s8 er RØD.
# 3) Deploy-transaktionen: ACL = frisk, katalog-delta = kun de tre tabellers rel-/kolonne-linjer, hele kataloget =
#    frisk, data uændret. Det hele en gang til ændrer intet, og hele db-rls.sql derefter ændrer hverken ACL eller
#    politikker.
# 4) Enheden er GRØN på den opgraderede base; fuld db-verify på en anden, ens opgraderet base.
# Kun lokalt/CI. Ved succes droppes de tre baser, scriptet selv oprettede (<db>_f, _p, _v); ved fejl står de tilbage.
set -euo pipefail
name=${1:?database}; base=${2:?base-commit}
dbf="${name}_f"; dbp="${name}_p"; dbv="${name}_v"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
for f in schema.sql db-rls.sql db-migrations.sql; do git show "$base:$f" > "$tmp/base-$f"; done
q() { env -u PGOPTIONS psql -X -q -v ON_ERROR_STOP=1 -d "$1" "${@:2}" >/dev/null; }
a() { env -u PGOPTIONS psql -X -At -v ON_ERROR_STOP=1 -d "$1" -c "$2"; }
fail() { echo "R37S8_UPGRADE_FAIL: $1" >&2; exit 1; }

# Deploy-området, som prod-runneren skærer det.
awk '$0=="DO $review37_s8_anon_kolonner$" {p=1} p{print} $0=="$review37_s8_anon_kolonner$;" {p=0}' db-rls.sql > "$tmp/rls.sql"
[ "$(head -1 "$tmp/rls.sql")" = 'DO $review37_s8_anon_kolonner$' ] \
  && [ "$(tail -1 "$tmp/rls.sql")" = '$review37_s8_anon_kolonner$;' ] \
  || fail "DO-blokken \$review37_s8_anon_kolonner\$ mangler i db-rls.sql"
! grep -qiwE 'create|drop|alter|policy|function' "$tmp/rls.sql" || fail "DO-blokken må kun rumme REVOKE/GRANT"
deploy() { env -u PGOPTIONS psql -X -q -1 -v ON_ERROR_STOP=1 -d "$1" -f "$tmp/rls.sql" 2>&1; }
awk '$0=="-- BEGIN-VERIFY r37s8" {p=1} p{print} $0=="-- END-VERIFY r37s8" {p=0}' db-verify.sql > "$tmp/v-r37s8.sql"
[ "$(head -1 "$tmp/v-r37s8.sql")" = "-- BEGIN-VERIFY r37s8" ] || fail "verify-enheden r37s8 mangler i db-verify.sql"
# Semantisk ACL (aclexplode, sorteret) for de tre tabeller og deres kolonner — ikke ACL-tekst, som er ordensfølsom.
acl() { a "$1" "SELECT string_agg(l, ' ' ORDER BY l COLLATE \"C\") FROM (
  SELECT c.relname||':'||r.grantee::regrole::text||':'||r.privilege_type AS l
    FROM pg_class c, aclexplode(c.relacl) r
   WHERE c.oid IN ('public.media'::regclass,'public.story'::regclass,'public.feed_pin'::regclass)
     AND r.grantee <> 0 AND r.grantee::regrole::text IN ('anon','authenticated')
  UNION ALL
  SELECT c.relname||'.'||at.attname||':'||r.grantee::regrole::text||':'||r.privilege_type
    FROM pg_attribute at JOIN pg_class c ON c.oid=at.attrelid, aclexplode(at.attacl) r
   WHERE c.oid IN ('public.media'::regclass,'public.story'::regclass,'public.feed_pin'::regclass)
     AND at.attnum > 0 AND NOT at.attisdropped AND r.grantee <> 0
     AND r.grantee::regrole::text IN ('anon','authenticated')) s"; }
pol() { a "$1" "SELECT l FROM (SELECT schemaname||'.'||tablename||'|'||policyname||'|'||cmd||'|'||roles::text||'|'||
  coalesce(qual,'')||'|'||coalesce(with_check,'') AS l FROM pg_policies WHERE schemaname IN ('public','private')
  UNION ALL SELECT n.nspname||'.'||c.relname||'|acl|'||coalesce(c.relacl::text,'NULL')||'|'||c.relrowsecurity::text
  FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN ('public','private') AND c.relkind IN ('r','v','m')) s
  ORDER BY l COLLATE \"C\""; }
kat() { env -u PGOPTIONS psql -X -Atq -v ON_ERROR_STOP=1 -d "$1" -f tests/sql/inspect-catalog-parity.sql > "$2"; }
data() { a "$1" "SELECT string_agg(t||'='||h, ' ' ORDER BY t) FROM (
  SELECT 'media' t, md5(coalesce(string_agg(to_jsonb(x)::text, ',' ORDER BY x.id),'')) h FROM media x
  UNION ALL SELECT 'story', md5(coalesce(string_agg(to_jsonb(x)::text, ',' ORDER BY x.id),'')) FROM story x
  UNION ALL SELECT 'feed_pin', md5(coalesce(string_agg(to_jsonb(x)::text, ',' ORDER BY x.id),'')) FROM feed_pin x
  UNION ALL SELECT 'change_set', count(*)::text FROM change_set) s"; }
# Kør verify-enheden; $2 = forventet fejltekst (rød) eller tom (grøn: OK-NOTICE skal komme).
unit() { local out
  if out=$(env -u PGOPTIONS psql -X -v ON_ERROR_STOP=1 -d "$1" -f "$tmp/v-r37s8.sql" 2>&1); then
    [ -z "$2" ] || { echo "$out" >&2; fail "r37s8 er grøn på basen $base (forventede: $2)"; }
    grep -q "NOTICE:  OK: review37 S8" <<<"$out" || { echo "$out" >&2; fail "r37s8: OK-linjen mangler"; }
  else
    [ -n "$2" ] || { echo "$out" >&2; fail "r37s8 fejlede efter blokken"; }
    grep -qF -- "$2" <<<"$out" || { echo "$out" >&2; fail "r37s8 fejlede af en anden grund end: $2"; }
  fi; }
build_start() { createdb "$1"; q "$1" -f tests/sql/evidence-promotion-bootstrap.sql
  q "$1" -c 'CREATE EXTENSION IF NOT EXISTS dblink WITH SCHEMA extensions'; }

# 1) Frisk reference.
build_start "$dbf"; q "$dbf" -f schema.sql; q "$dbf" -f db-rls.sql
fresh=$(acl "$dbf"); kat "$dbf" "$tmp/kat-fresh.txt"
grep -q 'media.storage_path:anon:SELECT' <<<"$fresh" || fail "referencen mangler anons kolonneret på media.storage_path"
! grep -q 'media:anon:' <<<"$fresh" || fail "referencen giver anon tabelret på media"

# 2) Prod-formet base med prods tabel-ACL; enheden er rød på den.
build_prod() { build_start "$1"
  for f in base-schema.sql base-db-migrations.sql base-db-migrations.sql base-db-rls.sql; do q "$1" -f "$tmp/$f"; done
  q "$1" -c 'GRANT ALL ON TABLE public.media TO anon, authenticated;
             GRANT SELECT, MAINTAIN ON TABLE public.story, public.feed_pin TO anon, authenticated;'; }
build_prod "$dbp"
grep -q 'media:anon:TRUNCATE' <<<"$(acl "$dbp")" || fail "basen har ikke prods tabel-ACL på media"
unit "$dbp" "FEJL: S8 —"
kat "$dbp" "$tmp/kat-foer.txt"
data_foer=$(data "$dbp")

# 3) Deploy-transaktionen, derefter det hele igen.
out=$(deploy "$dbp") || { echo "$out" >&2; fail "deploy-transaktionen fejlede"; }
[ "$(acl "$dbp")" = "$fresh" ] || { diff <(tr ' ' '\n' <<<"$fresh") <(acl "$dbp" | tr ' ' '\n') >&2 || true
  fail "ACL afviger fra frisk efter blokken"; }
[ "$(data "$dbp")" = "$data_foer" ] || fail "data ændret af blokken"
kat "$dbp" "$tmp/kat-efter.txt"
delta=$(LC_ALL=C comm -3 <(LC_ALL=C sort "$tmp/kat-foer.txt") <(LC_ALL=C sort "$tmp/kat-efter.txt") | sed 's/^\t//' \
  | cut -d'|' -f1,2 | LC_ALL=C sort -u)
uden=$(grep -vE '^(rel\|(public\.)?(media|story|feed_pin)|col\|(public\.)?(media|story|feed_pin)\.[a-z0-9_]+)$' <<<"$delta" || true)
[ -z "$uden" ] || { echo "$uden" >&2; fail "katalog-delta rører andet end de tre tabeller"; }
for t in media story feed_pin; do grep -qxE "rel\|(public\.)?$t" <<<"$delta" || fail "katalog-delta mangler rel|$t"; done
bash tests/sql/check-catalog-parity.sh "$tmp/kat-fresh.txt" "$tmp/kat-efter.txt" >/dev/null \
  || { bash tests/sql/check-catalog-parity.sh "$tmp/kat-fresh.txt" "$tmp/kat-efter.txt" || true; fail "kataloget efter blokken ≠ frisk schema.sql"; }
out=$(deploy "$dbp") || { echo "$out" >&2; fail "anden deploy-transaktion fejlede"; }
kat "$dbp" "$tmp/kat-efter2.txt"
cmp -s "$tmp/kat-efter.txt" "$tmp/kat-efter2.txt" || fail "blokken to gange ændrer kataloget"
pol_foer=$(pol "$dbp"); acl_foer=$(acl "$dbp")
[ "$(grep -c '|' <<<"$pol_foer")" -ge 100 ] || fail "politik-snapshottet er tomt"
q "$dbp" -1 -f db-rls.sql
[ "$(acl "$dbp")" = "$acl_foer" ] || fail "hele db-rls.sql oveni ændrer de tre tabellers ACL"
[ "$(pol "$dbp")" = "$pol_foer" ] || { diff <(echo "$pol_foer") <(pol "$dbp") >&2 || true
  fail "hele db-rls.sql oveni ændrer politikker/tabel-ACL (deploy-området er ufuldstændigt)"; }

# 4) Adfærd på den opgraderede base; fuld db-verify på en anden, ens opgraderet base.
unit "$dbp" ""
build_prod "$dbv"
out=$(deploy "$dbv") || { echo "$out" >&2; fail "deploy-transaktionen fejlede på verify-basen"; }
[ "$(acl "$dbv")" = "$fresh" ] || fail "ACL afviger på verify-basen"
q "$dbv" -f tests/sql/run-db-verify-disposable.sql
dropdb "$dbf"; dropdb "$dbp"; dropdb "$dbv"
echo R37S8_UPGRADE_OK
