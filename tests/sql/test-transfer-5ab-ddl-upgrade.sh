#!/usr/bin/env bash
# 5a+5b-overførslen plan A Task 3 (kun lokalt, som test-indholds-id-upgrade.sh): HEAD's DDL fra prods træ
# b42266e med Supabases default privileges emuleret. Idempotens, fire afbrudspunkter (åbne rettigheder),
# RLS, datadelta (I8), db-verify, fortrydelsens DROP-liste og andre skemaer. Apply = step_ddl's procedure.
# Brug: bash tests/sql/test-transfer-5ab-ddl-upgrade.sh <prefix> [<commit>]   (KEEP_REMOVAL=<sti> gemmer nye relationer)
set -euo pipefail
pre=${1:?prefix}; base=${2:-b42266e}; P=${pre}_p
S=.claude/skills/daa-extract/scripts; ALLOW=.claude/skills/daa-extract/references/transfer-5ab-ddl-allowed-data-delta.txt
export PGCLIENTENCODING=UTF8
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
PY=(env -u NODE_OPTIONS -u PYTHONPATH python3 -I)
fail() { echo "DDL_TEST_FAIL: $1"; exit 1; }
q() { env -u PGOPTIONS psql -X -q -v ON_ERROR_STOP=1 -d "$1" "${@:2}" >/dev/null 2>>"$tmp/psql.err" || { grep -m3 -E 'ERROR|FATAL' "$tmp/psql.err"; exit 2; }; }
qa() { env -u PGOPTIONS psql -X -Atq -v ON_ERROR_STOP=1 -d "$1" "${@:2}" 2>>"$tmp/psql.err" || { grep -m3 -E 'ERROR|FATAL' "$tmp/psql.err" >&2; exit 2; }; }
# step_ddl's apply-procedure (plan A Task 3 Produces); $2=skip-rls springer db-rls.sql over
apply() {
  PGOPTIONS='-c lock_timeout=10s' psql -X -q -v ON_ERROR_STOP=1 -d "$1" -f "${3:-db-migrations.sql}" >/dev/null 2>>"$tmp/apply.err" \
    || { grep -m3 -E 'ERROR|FATAL' "$tmp/apply.err"; fail "apply ($1)"; }
  [ "${2:-}" = skip-rls ] && return 0
  PGOPTIONS='-c lock_timeout=10s' psql -X -q -v ON_ERROR_STOP=1 --single-transaction -d "$1" -f db-rls.sql >/dev/null 2>>"$tmp/apply.err" \
    || { grep -m3 -E 'ERROR|FATAL' "$tmp/apply.err"; fail "db-rls ($1)"; }
  psql -X -q -v ON_ERROR_STOP=1 -d "$1" -c "NOTIFY pgrst, 'reload schema'" >/dev/null
  if grep -q '^psql:.*WARNING' "$tmp/apply.err"; then grep -m3 WARNING "$tmp/apply.err"; fail "WARNING fra apply ($1)"; fi
}
dig() { qa "$1" -v mode=digest -f "$S/$2" | awk -v d="$3" '$1==d {print $2}'; }
fa() { echo "$(dig "$1" transfer_catalog_fingerprint.sql portable)/$(dig "$1" transfer_acl_fingerprint.sql portable)"; }
fresh() { dropdb --if-exists "$1" >/dev/null 2>&1 || true; createdb -T "$P" "$1"; }
digests4() { qa "$1" -v src=1 -f "$S/interpretation_transfer_digests.sql" | tail -1; }

# Skabelonen: prods træ med default privileges emuleret før byggeriet.
for f in schema.sql db-rls.sql db-migrations.sql; do git show "$base:$f" > "$tmp/$f"; done
dropdb --if-exists "$P" >/dev/null 2>&1 || true; createdb "$P"
q "$P" -f tests/sql/evidence-promotion-bootstrap.sql
q "$P" -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO anon, authenticated, service_role" \
       -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO anon, authenticated, service_role" \
       -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO anon, authenticated, service_role"
for f in "$tmp/schema.sql" "$tmp/db-rls.sql" "$tmp/db-migrations.sql" "$tmp/db-rls.sql"; do q "$P" -f "$f"; done
qa "$P" -f "$S/transfer_catalog_fingerprint.sql" > "$tmp/p-cat.txt"
qa "$P" -f "$S/transfer_acl_fingerprint.sql" > "$tmp/p-acl.txt"
qa "$P" -f "$S/transfer_table_hashes.sql" > "$tmp/p-tab.txt"
D4P=$(digests4 "$P")

# full_apply + IDEMPOTENT
U=${pre}_u; fresh "$U"; apply "$U"; F1A1=$(fa "$U")
qa "$U" -f "$S/transfer_acl_fingerprint.sql" > "$tmp/u-acl.txt"
apply "$U"; [ "$(fa "$U")" = "$F1A1" ] || fail "IDEMPOTENT"

# interrupt_<punkt>: åbne rettigheder ved afbruddet, derefter fuld apply ⇒ F1/A1
i=0
for pt in after-153-commit in-5a-cutover in-function-window before-rls; do
  i=$((i+1)); I=${pre}_i$i; fresh "$I"
  if [ "$pt" = before-rls ]; then apply "$I" skip-rls
  else "${PY[@]}" "$S/transfer_ddl.py" prefix --migrations db-migrations.sql --point "$pt" --out "$tmp/prefix.sql" >/dev/null
       apply "$I" skip-rls "$tmp/prefix.sql"; fi
  qa "$I" -f "$S/transfer_acl_fingerprint.sql" | grep '^P|m|anon|.*|1$' > "$tmp/i-open.txt" || true
  open_exec=$(grep -cvxF -f "$tmp/u-acl.txt" "$tmp/i-open.txt" || true)
  norls=$(qa "$I" -c "SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='private' AND c.relkind IN ('r','p') AND NOT c.relrowsecurity")
  echo "INTERRUPT point=$pt open_exec=$open_exec private_without_rls=$norls"
  if [ "$pt" = in-function-window ] && [ "$open_exec" -lt 1 ]; then fail "interrupt_$pt (punktet ligger ikke i et funktionsvindue)"; fi
  apply "$I"; [ "$(fa "$I")" = "$F1A1" ] || fail "interrupt_$pt (ikke F1/A1 efter genkørsel)"
  dropdb "$I"
done

# rls_after_apply
[ "$(qa "$U" -c "SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='private' AND c.relkind IN ('r','p') AND NOT c.relrowsecurity")" = 0 ] \
  || fail rls_after_apply

# data_delta (I8)
[ "$(digests4 "$U")" = "$D4P" ] || fail "data_delta (trin 4's digests ændret)"
qa "$U" -f "$S/transfer_table_hashes.sql" > "$tmp/u-tab.txt"
"${PY[@]}" "$S/transfer_ddl.py" data-delta --before "$tmp/p-tab.txt" --after "$tmp/u-tab.txt" --allow "$ALLOW" || fail "data_delta"

# db_verify i en kopi (den seeder). db-verify's egen default-ACL-probe forudsætter lukkede default privileges;
# prods skema-lokale »postgres|public|f|anon« (målt i restoren) holder den ikke, så emuleringen rulles tilbage i
# kopien. Vinduerne, hvor nye funktioner er åbne, måles i stedet af open_exec ovenfor.
V=${pre}_v; dropdb --if-exists "$V" >/dev/null 2>&1 || true; createdb -T "$U" "$V"
q "$V" -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON TABLES FROM anon, authenticated, service_role" \
       -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON SEQUENCES FROM anon, authenticated, service_role" \
       -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM anon, authenticated, service_role"
q "$V" -f tests/sql/run-db-verify-disposable.sql; dropdb "$V"

# other_schemas_untouched
qa "$U" -f "$S/transfer_catalog_fingerprint.sql" > "$tmp/u-cat.txt"
cmp -s <(grep '^L|' "$tmp/p-cat.txt") <(grep '^L|' "$tmp/u-cat.txt") || fail other_schemas_untouched

# removal_restores_identity_set
out=$("${PY[@]}" "$S/transfer_ddl.py" removal-sql --before "$tmp/p-cat.txt" --after "$tmp/u-cat.txt" --out "$tmp/drop.sql")
echo "$out"
grep -qx 'DROP TABLE IF EXISTS private.identity_control_run CASCADE;' "$tmp/drop.sql" || fail "removal (mangler private.identity_control_run)"
grep -qx 'DROP ROUTINE IF EXISTS public.red_register_identity_control_run(uuid,text) CASCADE;' "$tmp/drop.sql" \
  || fail "removal (mangler public.red_register_identity_control_run)"
if [ -n "${KEEP_REMOVAL:-}" ]; then
  sed -n 's/^DROP TABLE IF EXISTS \(.*\) CASCADE;$/\1/p' "$tmp/drop.sql" | LC_ALL=C sort > "$KEEP_REMOVAL"; fi
q "$U" -f "$tmp/drop.sql"
qa "$U" -f "$S/transfer_catalog_fingerprint.sql" > "$tmp/r-cat.txt"
"${PY[@]}" - "$tmp/p-cat.txt" "$tmp/u-cat.txt" "$tmp/r-cat.txt" <<'EOPY' || fail removal_restores_identity_set
import sys
def ids(p, keep=None):
    out = {}
    for l in open(p, encoding="utf-8").read().splitlines():
        f = l.split("|")
        if f[0] == "P":
            out[(f[1], f[2])] = f[4]
    return out
p, u, r = (ids(x) for x in sys.argv[1:])
new = set(u) - set(p)
new_rel = {i for k, i in new if k == "r"}
# Hvad må blive tilbage efter fjernelsen: underarter på eksisterende relationer og kolonne-ejede sekvenser.
may_remain = {(k, i) for k, i in new if (k in "ckitp" and ".".join(i.split(".", 2)[:2]) not in new_rel)
              or (k == "s" and u[(k, i)] == "1")}
missing = set(p) - set(r); removed_by_ddl = set(p) - set(u)
extra = set(r) - set(p)
if missing != removed_by_ddl: raise SystemExit("IDENTITY_MISSING %d %d" % (len(missing), len(removed_by_ddl)))
if not extra <= may_remain: raise SystemExit("IDENTITY_EXTRA %d" % len(extra - may_remain))
print("REMOVAL_IDENTITY_OK removed_by_ddl=%d remaining_on_existing=%d" % (len(removed_by_ddl), len(extra)))
EOPY
dropdb "$U"; dropdb "$P"; echo DDL_UPGRADE_SYNTH_OK
