#!/usr/bin/env bash
# Review 37 A2+Y3: prods deploy-form. Prod-runneren udtrækker navngivne blokke; deploy-området er blokkene review37-a2
# og review37-y3 i db-migrations.sql (i den rækkefølge) + DO-blokken $review37_y3_acl$ fra db-rls.sql i ÉN psql-
# transaktion (-1). Ikke hele db-rls.sql: dens DROP/CREATE POLICY tager ACCESS EXCLUSIVE på tabellerne, så gæsternes
# læsninger ville vente under hele transaktionen (projektejeren 2026-11-21). Trin 3 beviser, at hele db-rls.sql oveni
# ikke ændrer noget i kroppe, ACL eller politikker.
# 1) Frisk reference (bootstrap + dblink + schema.sql + db-rls.sql): kroppe (sha256 af pg_get_functiondef) og ACL for
#    alle funktioner, blokkene definerer (alle overloads med samme navn).
# 2) Prod-formet base (2. arg; CI pinner bc3b1c46 = main (#417) med p1p2, OCR-rettelse af kildepåstand, #396, #401 og
#    #415, alle i prod 21/11): basens skema + migrationer to gange + rls. Basen skal mangle hjælperen og feed-RPC'en.
# 3) Kun blokkene + ACL-blokken i én transaktion → kroppe og ACL = 1). Blokkene en gang til er en no-op (samme sha),
#    og hele db-rls.sql derefter ændrer hverken kroppe, ACL eller politikker (deploy-området er komplet).
# 4) Kontrakt- og feedtest på den opgraderede base; db-verify på en anden, ens opgraderet base (som i CI-jobbet:
#    kontrakttesten efterlader tilstand, fx sekvenser, som db-verify's v2-bootstrap ikke tåler).
# Kun lokalt/CI. Ved succes droppes de tre baser, scriptet selv oprettede (<db>_f, <db>_p, <db>_v); ved fejl står de tilbage.
set -euo pipefail
name=${1:?database}; base=${2:?base-commit}
dbf="${name}_f"; dbp="${name}_p"; dbv="${name}_v"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
for f in schema.sql db-rls.sql db-migrations.sql; do git show "$base:$f" > "$tmp/$f"; done
q() { env -u PGOPTIONS psql -X -q -v ON_ERROR_STOP=1 -d "$1" "${@:2}" >/dev/null; }
a() { env -u PGOPTIONS psql -X -At -v ON_ERROR_STOP=1 -d "$1" -c "$2"; }
fail() { echo "A2Y3_UPGRADE_FAIL: $1" >&2; exit 1; }

# Deploy-området, som prod-runneren skærer det.
for b in review37-a2 review37-y3; do
  awk -v b="$b" '$0=="-- BEGIN " b {p=1} p{print} $0=="-- END " b {p=0}' db-migrations.sql > "$tmp/$b.sql"
  [ "$(head -1 "$tmp/$b.sql")" = "-- BEGIN $b" ] && [ "$(tail -1 "$tmp/$b.sql")" = "-- END $b" ] \
    || fail "blokken $b mangler eller er ikke afsluttet"
done
awk '$0=="DO $review37_y3_acl$" {p=1} p{print} $0=="$review37_y3_acl$;" {p=0}' db-rls.sql > "$tmp/acl.sql"
[ "$(head -1 "$tmp/acl.sql")" = 'DO $review37_y3_acl$' ] && [ "$(tail -1 "$tmp/acl.sql")" = '$review37_y3_acl$;' ] \
  || fail "ACL-blokken mangler i db-rls.sql"
cat "$tmp/review37-a2.sql" "$tmp/review37-y3.sql" "$tmp/acl.sql" > "$tmp/blok.sql"
names=$(grep -oE '^CREATE OR REPLACE FUNCTION [a-z_]+\.[a-z0-9_]+' "$tmp/blok.sql" | awk '{print $5}' | sort -u | tr '\n' ' ')
[ -n "$names" ] || fail "ingen funktioner i blokkene"
list=$(for n in $names; do printf "'%s'," "$n"; done); list=${list%,}
sha() { a "$1" "SELECT l FROM (SELECT p.oid::regprocedure::text||'|'||encode(extensions.digest(convert_to(pg_get_functiondef(p.oid),'UTF8'),'sha256'),'hex')
  ||'|'||coalesce(p.proacl::text,'NULL') AS l FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname||'.'||p.proname IN ($list)) s ORDER BY l COLLATE \"C\""; }
# Politikker (navn, kommando, roller, udtryk) og tabel-ACL i public/private: hele db-rls.sql oveni må ikke ændre dem.
pol() { a "$1" "SELECT l FROM (SELECT schemaname||'.'||tablename||'|'||policyname||'|'||cmd||'|'||roles::text||'|'||
  coalesce(qual,'')||'|'||coalesce(with_check,'') AS l FROM pg_policies WHERE schemaname IN ('public','private')
  UNION ALL SELECT n.nspname||'.'||c.relname||'|acl|'||coalesce(c.relacl::text,'NULL')||'|'||c.relrowsecurity::text
  FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN ('public','private') AND c.relkind IN ('r','v','m')) s
  ORDER BY l COLLATE \"C\""; }
build_start() { createdb "$1"; q "$1" -f tests/sql/evidence-promotion-bootstrap.sql
  q "$1" -c 'CREATE EXTENSION IF NOT EXISTS dblink WITH SCHEMA extensions'; }

# 1) Frisk reference.
build_start "$dbf"; q "$dbf" -f schema.sql; q "$dbf" -f db-rls.sql
fresh=$(sha "$dbf")
[ "$(wc -l <<<"$fresh")" -ge "$(wc -w <<<"$names")" ] || fail "referencen mangler funktioner: $names"

# 2) Prod-formet base.
build_prod() { build_start "$1"
  for f in "$tmp/schema.sql" "$tmp/db-migrations.sql" "$tmp/db-migrations.sql" "$tmp/db-rls.sql"; do q "$1" -f "$f"; done; }
build_prod "$dbp"
[ "$(a "$dbp" "SELECT to_regprocedure('private.narrative_har_haendelse(bigint)') IS NULL
  AND to_regprocedure('public.public_haendelse_feed(text,integer,integer)') IS NULL")" = t ] \
  || fail "basen $base har allerede A2/Y3"
[ "$(sha "$dbp")" != "$fresh" ] || fail "basen er allerede byte-ens med schema.sql"

# 3) Kun blokkene + rls i én transaktion, derefter blokkene igen.
q "$dbp" -1 -f "$tmp/blok.sql"
[ "$(sha "$dbp")" = "$fresh" ] || { diff <(echo "$fresh") <(sha "$dbp") >&2 || true; fail "kroppe/ACL afviger efter blokkene"; }
[ "$(a "$dbp" "SELECT count(*) FROM private.feed_cursor_noegle")" = 1 ] || fail "nøgletabellen har ikke præcis én række"
noegle=$(a "$dbp" "SELECT md5(noegle) FROM private.feed_cursor_noegle")
q "$dbp" -1 -f "$tmp/blok.sql"
[ "$(sha "$dbp")" = "$fresh" ] || fail "blokkene to gange ændrer kroppe/ACL"
[ "$(a "$dbp" "SELECT md5(noegle) FROM private.feed_cursor_noegle")" = "$noegle" ] || fail "blokkene to gange skifter nøglen"
pol_foer=$(pol "$dbp")
[ "$(grep -c '|' <<<"$pol_foer")" -ge 100 ] && grep -q '^public\.person|' <<<"$pol_foer" \
  || fail "politik-snapshottet er tomt eller mangler person"
q "$dbp" -1 -f db-rls.sql
[ "$(sha "$dbp")" = "$fresh" ] || fail "hele db-rls.sql oveni ændrer kroppe/ACL (deploy-området er ufuldstændigt)"
[ "$(pol "$dbp")" = "$pol_foer" ] || { diff <(echo "$pol_foer") <(pol "$dbp") >&2 || true
  fail "hele db-rls.sql oveni ændrer politikker/tabel-ACL (deploy-området er ufuldstændigt)"; }

# 4) Adfærd på den opgraderede base.
q "$dbp" -f tests/sql/test-narrative-record-contract.sql
out=$(env -u PGOPTIONS psql -X -v ON_ERROR_STOP=1 -d "$dbp" -f tests/sql/test-haendelse-feed.sql 2>&1) \
  || { echo "$out" >&2; fail "feedtesten fejlede"; }
grep -qx 'OK test-haendelse-feed' <<<"$out" || { echo "$out" >&2; fail "feedtestens OK-linje mangler"; }
build_prod "$dbv"; q "$dbv" -1 -f "$tmp/blok.sql"
[ "$(sha "$dbv")" = "$fresh" ] || fail "kroppe/ACL afviger på verify-basen"
q "$dbv" -f tests/sql/run-db-verify-disposable.sql
dropdb "$dbf"; dropdb "$dbp"; dropdb "$dbv"
echo A2Y3_UPGRADE_OK
