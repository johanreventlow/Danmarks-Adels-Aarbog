#!/usr/bin/env bash
# 5a+5b-overførslen plan A Task 1: katalog- og ACL-fingeraftryk og tabelhashes. To uafhængige baser fra HEAD
# med Supabases default privileges emuleret før byggeriet; derefter én ændring ad gangen i base b.
# Brug: bash tests/sql/test-transfer-fingerprints.sh <prefix>
set -euo pipefail
pre=${1:?prefix}; A=${pre}_a; B=${pre}_b
S=.claude/skills/daa-extract/scripts; export PGCLIENTENCODING=UTF8
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
fail() { echo "FP_TEST_FAIL: $1"; exit 1; }
q() { env -u PGOPTIONS psql -X -q -v ON_ERROR_STOP=1 -d "$1" "${@:2}" >/dev/null 2>>"$tmp/psql.err" || { grep -m3 -E 'ERROR|FATAL' "$tmp/psql.err"; exit 2; }; }
qa() { env -u PGOPTIONS psql -X -Atq -v ON_ERROR_STOP=1 -d "$1" "${@:2}" 2>>"$tmp/psql.err" || { grep -m3 -E 'ERROR|FATAL' "$tmp/psql.err" >&2; exit 2; }; }
build() {
  dropdb --if-exists "$1" >/dev/null 2>&1 || true; createdb "$1"
  q "$1" -f tests/sql/evidence-promotion-bootstrap.sql
  q "$1" -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO anon, authenticated, service_role" \
         -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO anon, authenticated, service_role" \
         -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO anon, authenticated, service_role"
  q "$1" -f schema.sql; q "$1" -f db-rls.sql
}
# digest <db> <fil> <del> [ekstra psql-args] -> sha
digest() { qa "$1" "${@:4}" -v mode=digest -f "$S/$2" | awk -v d="$3" '$1==d {print $2}'; }
lines() { qa "$1" "${@:3}" -f "$S/$2"; }
snap() { # db -> "katP katL aclP aclL tabeller"
  echo "$(digest "$1" transfer_catalog_fingerprint.sql portable) $(digest "$1" transfer_catalog_fingerprint.sql local)" \
       "$(digest "$1" transfer_acl_fingerprint.sql portable) $(digest "$1" transfer_acl_fingerprint.sql local)" \
       "$(lines "$1" transfer_table_hashes.sql -v omit=created_at,changed_at | shasum -a 256 | cut -c1-64)"
}
field() { echo "$1" | awk -v i="$2" '{print $i}'; }
# expect <navn> <før> <efter> <felter der skal ændre sig, fx "1"> (resten skal være uændrede)
expect() {
  local n=$1 b=$2 a=$3 ch=" $4 " i
  for i in 1 2 3 4 5; do
    if [[ "$ch" == *" $i "* ]]; then [ "$(field "$b" $i)" != "$(field "$a" $i)" ] || fail "$n (felt $i uændret)"
    else [ "$(field "$b" $i)" = "$(field "$a" $i)" ] || fail "$n (felt $i ændret)"; fi
  done
}
build "$A"; build "$B"
sa=$(snap "$A"); sb=$(snap "$B")
for i in 1 2 3 4 5; do [ "$(field "$sa" $i)" != "" ] || fail "tomt felt $i"; done
expect fp_same_content "$sa" "$sb" ""
# Friske byggerier deler ikke tidsstempler; uden omit skal netop de tabeller med created_at/changed_at afvige.
[ "$( { diff <(lines "$A" transfer_table_hashes.sql) <(lines "$B" transfer_table_hashes.sql) || true; } | grep -c '^<')" -gt 0 ] \
  || fail "fp_same_content (omit gør ingen forskel: tidsstempler fanges ikke)"
# fp_lines_digest: bash-sha af delens linjer = digest-tilstanden.
for f in transfer_catalog_fingerprint.sql transfer_acl_fingerprint.sql; do
  for d in P L; do
    want=$(digest "$A" "$f" "$([ $d = P ] && echo portable || echo local)")
    got=$(printf '%s' "$(lines "$A" "$f" | grep "^$d|" || true)" | shasum -a 256 | cut -c1-64)
    [ "$want" = "$got" ] || fail "fp_lines_digest ($f $d)"
  done
done
fn=$(qa "$B" -c "SELECT p.oid::regprocedure FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace JOIN pg_language l ON l.oid=p.prolang
  WHERE n.nspname='private' AND l.lanname='plpgsql' AND p.prokind='f' ORDER BY p.proname COLLATE \"C\", 1::text LIMIT 1")
s0=$(snap "$B")
q "$B" -c "DO \$x\$ BEGIN EXECUTE regexp_replace(pg_get_functiondef('$fn'::regprocedure), '\\\$function\\\$', E'\$function\$\\n-- t5ab'); END \$x\$"
s1=$(snap "$B"); expect fp_function_body "$s0" "$s1" "1"
q "$B" -c "ALTER TABLE public.person ADD COLUMN t5ab_x int"
s2=$(snap "$B"); expect fp_column "$s1" "$s2" "1"
q "$B" -c "ALTER TABLE private.source_persona DISABLE ROW LEVEL SECURITY"
s3=$(snap "$B"); expect fp_rls "$s2" "$s3" "1"
v=$(qa "$B" -c "SELECT c.oid::regclass FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE c.relkind='v'
  AND n.nspname IN ('public','private') AND c.reloptions::text LIKE '%security_invoker%' ORDER BY 1::text LIMIT 1")
[ -n "$v" ] || fail "fp_view_option (intet view med security_invoker)"
q "$B" -c "ALTER VIEW $v SET (security_invoker=false)"
s4=$(snap "$B"); expect fp_view_option "$s3" "$s4" "1"
q "$B" -c "GRANT SELECT ON private.source_persona TO anon"
s5=$(snap "$B"); expect fp_grant "$s4" "$s5" "3"
pf=$(qa "$B" -c "SELECT p.oid::regprocedure FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='private' AND p.prokind='f' AND NOT has_function_privilege('service_role',p.oid,'EXECUTE') ORDER BY 1::text LIMIT 1")
q "$B" -c "GRANT EXECUTE ON FUNCTION $pf TO service_role"
s6=$(snap "$B"); expect fp_service_role "$s5" "$s6" "3"
q "$B" -c "ALTER DEFAULT PRIVILEGES IN SCHEMA private GRANT SELECT ON TABLES TO anon"
s7=$(snap "$B"); expect fp_default_acl_is_local "$s6" "$s7" "4"
q "$B" -c "CREATE SCHEMA t5ab_x" -c "CREATE TABLE t5ab_x.t(i int)"
s8=$(snap "$B"); expect fp_other_schema_is_local "$s7" "$s8" "2"
t0=$(lines "$B" transfer_table_hashes.sql)
q "$B" -c "INSERT INTO public.person(id,levende,privat,status) VALUES (-990001,false,false,'5b')" \
       -c "SELECT nextval(pg_get_serial_sequence('public.person','id'))"
s9=$(snap "$B"); expect fp_no_data "$s8" "$s9" "5"
t1=$(lines "$B" transfer_table_hashes.sql)
d=$(diff <(echo "$t0") <(echo "$t1") || true)
[ "$(echo "$d" | grep -c '^>')" = 1 ] && echo "$d" | grep -q '^> public.person=' || fail "fp_no_data (andre tabelhashes end public.person ændret)"
dropdb "$A"; dropdb "$B"; echo FP_OK
