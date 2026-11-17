#!/usr/bin/env bash
# record_persona (persona for helpost uden tekst): opgradering fra prods skema gennem hele db-migrations.sql.
# 1) Frisk reference (bootstrap + schema.sql + db-rls.sql): kroppe (sha256 af pg_get_functiondef) og ACL for de syv
#    funktioner, operationen rører, og CHECK-mængden på private.reimport_event.operation.
# 2) Base (2. arg; CI pinner f37b294a): basens skema + migrationer to gange, så hele den aktuelle db-migrations.sql to
#    gange (med rls imellem) → CHECK-mængden er basens ∪ {record_persona} (mængdesammenligning, ikke antal), og de syv
#    funktioner har præcis schema.sql's kroppe og ACL. Task 1-2's testfiler og writer-bootstrappen køres på den opgraderede base.
# 3) Frisk schema.sql + hele migrationen én gang: resultatet er stadig byte-ens med 1).
# 4) db-verify på en selvstændig opgraderet base.
# Hvorfor f37b294a og ikke merge-base med origin/main: prods installerede SQL er #363 (2026-11-15). origin/main indeholder
# bl.a. fuld personsletning (#369/#377), som ikke er i prod; en base derfra ville gøre opgraderingen mere end prods.
# Basen skal mangle record_persona i CHECK'en og wrapperen, ellers UPGRADE_BASE_INVALID.
# Kun lokalt/CI. Ved succes droppes de fire baser, scriptet selv oprettede (<db>_f, <db>_u, <db>_s, <db>_v); ved fejl står
# de tilbage til inspektion.
set -euo pipefail
name=${1:?database}; base=${2:-$(git merge-base origin/main HEAD)}
dbf="${name}_f"; dbu="${name}_u"; dbs="${name}_s"; dbv="${name}_v"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
for f in schema.sql db-rls.sql db-migrations.sql; do git show "$base:$f" > "$tmp/$f"; done
q() { env -u PGOPTIONS psql -X -q -v ON_ERROR_STOP=1 -d "$1" "${@:2}" >/dev/null; }
a() { env -u PGOPTIONS psql -X -At -v ON_ERROR_STOP=1 -d "$1" -c "$2"; }
fns="private.validate_reimport_authorization_payload(jsonb,jsonb) public.red_finalize_reimport(uuid)
  public.red_reimport_batch_result(uuid,uuid) private.write_record_persona(uuid,text,jsonb)
  public.red_apply_reimport_record_persona(uuid,text,jsonb) private.reverse_narrative_publication_event(uuid,text)
  public.red_person_narrative_publication_history(bigint)"
sha() { for f in $fns; do
  a "$1" "SELECT '$f|'||coalesce((SELECT encode(extensions.digest(convert_to(pg_get_functiondef(p.oid),'UTF8'),'sha256'),'hex')||'|'||coalesce(p.proacl::text,'NULL') FROM pg_proc p WHERE p.oid=to_regprocedure('$f')),'MISSING')"; done; }
# Operationsmængden i CHECK'en, sorteret (C-locale) og uden afhængighed af konstruktionens rækkefølge/format.
ops() { a "$1" "SELECT o FROM (SELECT unnest(string_to_array(substring(pg_get_constraintdef(c.oid) FROM '\{([^}]*)\}'),',')) AS o
  FROM pg_constraint c WHERE c.conrelid='private.reimport_event'::regclass AND c.conname='reimport_event_operation_check') s ORDER BY o COLLATE \"C\""; }
# Task 1-2's tests kræver kontrakt v2; writer-bootstrappen (som i writer-jobbet og test-6e2-upgrade.sh) lægges på efter sha-sammenligningen.
tests() { q "$1" -f tests/sql/1939-v50-writer-bootstrap.sql
  q "$1" -c 'BEGIN' -f tests/sql/reimport-writer-v2-bootstrap.sql -c 'COMMIT'
  # psql \quit/NOTICE-testene kan slutte stille: kræv hver testfils sidste OK-linje, ikke kun exit-koden.
  for pair in "test-record-persona-registration|OK: profile hashes" "test-record-persona|OK: SERIALIZABLE afvises"; do
    t=${pair%%|*}; ok=${pair#*|}
    out=$(env -u PGOPTIONS psql -X -q -v ON_ERROR_STOP=1 -d "$1" -f "tests/sql/$t.sql" 2>&1) || { echo "$out" >&2; echo "TEST_FAILED: $t" >&2; exit 1; }
    grep -qF "$ok" <<<"$out" || { echo "$out" >&2; echo "TEST_OK_LINE_MISSING: $t" >&2; exit 1; }
  done; }
createdb "$dbf"; createdb "$dbu"; createdb "$dbs"; createdb "$dbv"

# 1) Frisk reference.
for f in tests/sql/evidence-promotion-bootstrap.sql schema.sql db-rls.sql; do q "$dbf" -f "$f"; done
fresh=$(sha "$dbf"); fresh_ops=$(ops "$dbf")
! grep -q MISSING <<<"$fresh" || { echo "FRESH_INVALID: en funktion mangler i schema.sql" >&2; echo "$fresh" >&2; exit 1; }
grep -qx record_persona <<<"$fresh_ops" || { echo "FRESH_INVALID: record_persona mangler i CHECK'en i schema.sql" >&2; exit 1; }

# 2) Prods skema → hele migrationen to gange.
for f in tests/sql/evidence-promotion-bootstrap.sql "$tmp/schema.sql" "$tmp/db-rls.sql" "$tmp/db-migrations.sql" "$tmp/db-migrations.sql" "$tmp/db-rls.sql"; do q "$dbu" -f "$f"; done
base_ops=$(ops "$dbu")
! grep -qx record_persona <<<"$base_ops" || { echo "UPGRADE_BASE_INVALID: $base har allerede record_persona i CHECK'en" >&2; exit 1; }
[ "$(a "$dbu" "SELECT to_regprocedure('public.red_apply_reimport_record_persona(uuid,text,jsonb)') IS NULL")" = "t" ] \
  || { echo "UPGRADE_BASE_INVALID: wrapperen findes allerede i $base" >&2; exit 1; }
old=$(sha "$dbu")
[ "$old" != "$fresh" ] || { echo "UPGRADE_BASE_INVALID: basen er allerede byte-ens med schema.sql" >&2; exit 1; }
for f in db-migrations.sql db-rls.sql db-migrations.sql db-rls.sql; do q "$dbu" -f "$f"; done
new=$(sha "$dbu")
[ "$new" = "$fresh" ] || { echo "UPGRADE_BODY_OR_ACL_MISMATCH" >&2; diff <(echo "$fresh") <(echo "$new") >&2 || true; exit 1; }
expected_ops=$( { echo "$base_ops"; echo record_persona; } | LC_ALL=C sort -u)
[ "$(ops "$dbu")" = "$expected_ops" ] || { echo "UPGRADE_OPERATION_SET_MISMATCH" >&2; diff <(echo "$expected_ops") <(ops "$dbu") >&2 || true; exit 1; }
[ "$(ops "$dbu")" = "$fresh_ops" ] || { echo "UPGRADE_OPERATION_SET_NOT_FRESH" >&2; exit 1; }
tests "$dbu"
echo UPGRADE_OK

# 3) Frisk schema.sql + hele migrationen én gang.
for f in tests/sql/evidence-promotion-bootstrap.sql schema.sql db-rls.sql db-migrations.sql db-rls.sql; do q "$dbs" -f "$f"; done
[ "$(sha "$dbs")" = "$fresh" ] || { echo "FRESH_PLUS_MIGRATION_MISMATCH" >&2; diff <(echo "$fresh") <(sha "$dbs") >&2 || true; exit 1; }
[ "$(ops "$dbs")" = "$fresh_ops" ] || { echo "FRESH_PLUS_MIGRATION_OPERATION_SET" >&2; exit 1; }
tests "$dbs"
echo FRESH_PLUS_MIGRATION_OK

# 4) db-verify på en opgraderet base.
for f in tests/sql/evidence-promotion-bootstrap.sql "$tmp/schema.sql" "$tmp/db-rls.sql" "$tmp/db-migrations.sql" "$tmp/db-rls.sql" \
         db-migrations.sql db-rls.sql db-migrations.sql db-rls.sql tests/sql/run-db-verify-disposable.sql; do q "$dbv" -f "$f"; done
echo VERIFY_OK

dropdb --if-exists "$dbf"; dropdb --if-exists "$dbu"; dropdb --if-exists "$dbs"; dropdb --if-exists "$dbv"
echo UPGRADE_RECORD_PERSONA_OK
