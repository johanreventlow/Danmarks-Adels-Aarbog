#!/usr/bin/env bash
# Trin 6e-2 Task 3: koordinat-RPC'ens signaturændring (printed_page sidst) gennem hele db-migrations.sql.
# 1) Frisk reference (bootstrap + schema.sql + db-rls.sql): kroppe og ACL for RPC'en og mængdefunktionen.
# 2) Base med den gamle signatur (base-commit'ens skema + migrationer, 2. arg, default merge-base med origin/main): hele
#    den aktuelle db-migrations.sql to gange (med rls imellem) → ny signatur, byte-ens kroppe og samme ACL som 1), anon kan
#    kalde, og koordinattestene er grønne.
# 3) Frisk schema.sql (ny signatur) + hele db-migrations.sql én gang: de ældre blokkes CREATE OR REPLACE med gammel
#    returtype må ikke fejle, og resultatet er stadig byte-ens med 1).
# 4) db-verify på en selvstændig opgraderet base.
# Prod står på #342 (redaktionen ser levende, decisions 2026-11-13; CI's base er ac194bfd): basen skal have redaktør-
# grenen i koordinat-, fakta- og familiekilde-RPC'en; efter migrationen bærer 6e-2's kroppe den videre (sha = frisk
# schema.sql), og #342's kaldermatrix (gæst, uid uden profil, medlem, redaktion) i koordinat-, fakta- og
# familiekildetestene er grøn på den opgraderede base.
# Kun lokalt/CI. Ved succes droppes de fire baser, scriptet selv oprettede (<db>_f, <db>_u, <db>_s, <db>_v); ved fejl står
# de tilbage til inspektion.
set -euo pipefail
name=${1:?database}; base=${2:-$(git merge-base origin/main HEAD)}
dbf="${name}_f"; dbu="${name}_u"; dbs="${name}_s"; dbv="${name}_v"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
for f in schema.sql db-rls.sql db-migrations.sql; do git show "$base:$f" > "$tmp/$f"; done
q() { env -u PGOPTIONS psql -X -q -v ON_ERROR_STOP=1 -d "$1" "${@:2}" >/dev/null; }
a() { env -u PGOPTIONS psql -X -At -v ON_ERROR_STOP=1 -d "$1" -c "$2"; }
fns="public.public_person_source_coordinates() private.membership_current_set() private.membership_is_current(bigint,bigint)
  public.public_person_facts(bigint[]) public.public_family_sources(bigint[])"
# Antal af de tre læse-RPC'er bag personsiden, der har #342's redaktør-gren.
red_gren() { a "$1" "SELECT count(*) FROM unnest(ARRAY['public.public_person_source_coordinates()',
    'public.public_person_facts(bigint[])','public.public_family_sources(bigint[])']) f
  WHERE strpos(pg_get_functiondef(to_regprocedure(f)),'v_red boolean:=public.current_rolle()=''redaktion''')>0"; }
sha() { for f in $fns; do
  a "$1" "SELECT '$f|'||coalesce((SELECT encode(extensions.digest(convert_to(pg_get_functiondef(p.oid),'UTF8'),'sha256'),'hex')||'|'||coalesce(p.proacl::text,'NULL')||'|'||pg_get_function_result(p.oid) FROM pg_proc p WHERE p.oid=to_regprocedure('$f')),'MISSING')"; done; }
anon_kald() { a "$1" "SET ROLE anon; SELECT count(*)>=0 FROM public.public_person_source_coordinates();" | grep -qx t; }
# Fakta- og familiekildetestene publicerer gennem kontrakt v2's skrivere; writer-bootstrappen (som i writer-jobbet og
# test-etiket-ceremoni.sh) lægges på efter sha-sammenligningen.
tests() { for t in test-6e2-koordinater test-person-source-coordinates; do q "$1" -f "tests/sql/$t.sql"; done
  q "$1" -f tests/sql/1939-v50-writer-bootstrap.sql
  q "$1" -c 'BEGIN' -f tests/sql/reimport-writer-v2-bootstrap.sql -c 'COMMIT'
  for t in test-person-facts test-family-sources; do q "$1" -f "tests/sql/$t.sql"; done; }
createdb "$dbf"; createdb "$dbu"; createdb "$dbs"; createdb "$dbv"

# 1) Frisk reference.
for f in tests/sql/evidence-promotion-bootstrap.sql schema.sql db-rls.sql; do q "$dbf" -f "$f"; done
fresh=$(sha "$dbf")
! grep -q MISSING <<<"$fresh" || { echo "FRESH_INVALID: en funktion mangler i schema.sql" >&2; echo "$fresh" >&2; exit 1; }

# 2) Gammel signatur → hele migrationen to gange.
for f in tests/sql/evidence-promotion-bootstrap.sql "$tmp/schema.sql" "$tmp/db-rls.sql" "$tmp/db-migrations.sql"; do q "$dbu" -f "$f"; done
[ "$(a "$dbu" "SELECT 'printed_page'=ANY(proargnames) FROM pg_proc WHERE oid='public.public_person_source_coordinates()'::regprocedure")" = "f" ] \
  || { echo "UPGRADE_BASE_INVALID: $base har allerede den nye signatur" >&2; exit 1; }
[ "$(a "$dbu" "SELECT to_regprocedure('private.membership_current_set()') IS NULL")" = "t" ] \
  || { echo "UPGRADE_BASE_INVALID: membership_current_set findes allerede i $base" >&2; exit 1; }
[ "$(red_gren "$dbu")" = "3" ] \
  || { echo "UPGRADE_BASE_INVALID: $base mangler #342's redaktør-gren (prods tilstand)" >&2; exit 1; }
old_acl=$(a "$dbu" "SELECT proacl::text FROM pg_proc WHERE oid='public.public_person_source_coordinates()'::regprocedure")
for f in db-migrations.sql db-rls.sql db-migrations.sql db-rls.sql; do q "$dbu" -f "$f"; done
new=$(sha "$dbu")
[ "$new" = "$fresh" ] || { echo "UPGRADE_BODY_OR_ACL_MISMATCH" >&2; diff <(echo "$fresh") <(echo "$new") >&2 || true; exit 1; }
[ "$(a "$dbu" "SELECT proacl::text FROM pg_proc WHERE oid='public.public_person_source_coordinates()'::regprocedure")" = "$old_acl" ] \
  || { echo "UPGRADE_ACL_CHANGED: $old_acl" >&2; exit 1; }
anon_kald "$dbu" || { echo "UPGRADE_ANON_CALL" >&2; exit 1; }
[ "$(red_gren "$dbu")" = "3" ] || { echo "UPGRADE_REDAKTOER_GREN_TABT" >&2; exit 1; }
tests "$dbu"
echo UPGRADE_OK

# 3) Frisk schema.sql (ny signatur) + hele migrationen én gang.
for f in tests/sql/evidence-promotion-bootstrap.sql schema.sql db-rls.sql db-migrations.sql db-rls.sql; do q "$dbs" -f "$f"; done
[ "$(sha "$dbs")" = "$fresh" ] || { echo "FRESH_PLUS_MIGRATION_MISMATCH" >&2; diff <(echo "$fresh") <(sha "$dbs") >&2 || true; exit 1; }
anon_kald "$dbs" || { echo "FRESH_PLUS_MIGRATION_ANON_CALL" >&2; exit 1; }
tests "$dbs"
echo FRESH_PLUS_MIGRATION_OK

# 4) db-verify på en opgraderet base.
for f in tests/sql/evidence-promotion-bootstrap.sql "$tmp/schema.sql" "$tmp/db-rls.sql" "$tmp/db-migrations.sql" "$tmp/db-rls.sql" \
         db-migrations.sql db-rls.sql db-migrations.sql db-rls.sql tests/sql/run-db-verify-disposable.sql; do q "$dbv" -f "$f"; done
echo VERIFY_OK

dropdb --if-exists "$dbf"; dropdb --if-exists "$dbu"; dropdb --if-exists "$dbs"; dropdb --if-exists "$dbv"
echo UPGRADE_6E2_KOORDINATER_OK
