#!/usr/bin/env bash
# R40. Same bootstrap/schema/migrations/RLS sequence as the CI upgrade harnesses.
# Only databases successfully created by THIS invocation can be dropped; opt-in only.
set -euo pipefail
cd "$(dirname "$0")/../.."
pfx=${1:?prefix}; base=${2:-f9f2cd9c}
[[ $pfx =~ ^[a-z][a-z0-9_]{0,48}$ ]] || exit 2
out=$(mktemp -d "${PURGE_LOG_DIR:-${RUNNER_TEMP:-${TMPDIR:?TMPDIR mangler}}}/purge11up.XXXXXX"); created=()
exec 3>&1
cleanup() {
  rc=$?
  if [ "${PURGE_DROP_DBS:-0}" = 1 ]; then
    for db in ${created[@]+"${created[@]}"}; do dropdb "$db" >/dev/null 2>&1 || true; done
  fi
  [ "$rc" = 0 ] || echo UPGRADE_FEJL >&3
  exit "$rc"
}
trap cleanup EXIT
q() { psql -Xq -v ON_ERROR_STOP=1 -d "$1" "${@:2}" > /dev/null 2>>"$out/build.log"; }
for f in tests/sql/evidence-promotion-bootstrap.sql schema.sql db-migrations.sql db-rls.sql; do
  git show "$base:$f" > "$out/$(basename "$f")"
done
for db in "${pfx}_f" "${pfx}_o" "${pfx}_u"; do
  createdb "$db"; created+=("$db")
done
for f in tests/sql/evidence-promotion-bootstrap.sql schema.sql db-rls.sql; do q "${pfx}_f" -f "$f"; done
# Frisk base fra base-commit (uden migrationer): afgrænser »nye og ændrede« funktioner. Funktioner, hvis migrationskrop
# allerede før base-commit afveg fra schema.sql (fx whitespace), er ikke ændret af denne gren og ligger uden for omfanget.
for f in evidence-promotion-bootstrap.sql schema.sql db-rls.sql; do q "${pfx}_o" -f "$out/$f"; done
for f in evidence-promotion-bootstrap.sql schema.sql db-migrations.sql db-rls.sql; do q "${pfx}_u" -f "$out/$f"; done
snapshot() {
  psql -XAtq -v ON_ERROR_STOP=1 -d "$1" -c "
    SELECT jsonb_build_object('key',n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')',
      'def',pg_get_functiondef(p.oid),'acl',p.proacl::text)::text
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname IN ('public','private') AND p.prokind IN ('f','p')
      AND NOT EXISTS(SELECT 1 FROM pg_depend d WHERE d.classid='pg_proc'::regclass
        AND d.objid=p.oid AND d.deptype='e') ORDER BY n.nspname,p.proname,pg_get_function_identity_arguments(p.oid);" > "$2"
}
snapshot "${pfx}_f" "$out/fresh.jsonl"
snapshot "${pfx}_o" "$out/old.jsonl"
snapshot "${pfx}_u" "$out/base.jsonl"
for pass in 1 2; do
  q "${pfx}_u" -f db-migrations.sql
  q "${pfx}_u" -f db-rls.sql
  snapshot "${pfx}_u" "$out/upgrade$pass.jsonl"
done
python3 - "$out" <<'PY'
import json, pathlib, sys
p=pathlib.Path(sys.argv[1])
def read(name):
    return {x['key']:x for x in map(json.loads,(p/name).read_text().splitlines())}
o,f=read('old.jsonl'),read('fresh.jsonl')
# Nye og ændrede funktioner siden base-commit (krop eller ACL i schema.sql + db-rls.sql).
changed={k for k in o.keys()|f.keys() if o.get(k)!=f.get(k)}
assert changed, 'empty upgrade scope'
print(f'UPGRADE_SCOPE {len(changed)}')
for name in ['upgrade1.jsonl','upgrade2.jsonl']:
    u=read(name)
    bad=[k for k in sorted(changed) if u.get(k)!=f.get(k)]
    # Print identities only, never function source or row contents.
    if bad:
        print('\n'.join(bad),file=sys.stderr)
        raise SystemExit(1)
assert read('upgrade1.jsonl')==read('upgrade2.jsonl'), 'non-idempotent function catalog'
# Uden for omfanget må migrationen intet have ændret: ellers har grenen ændret en migrationskrop uden schema.sql.
b,u1=read('base.jsonl'),read('upgrade1.jsonl')
drift=[k for k in sorted((b.keys()|u1.keys())-changed) if b.get(k)!=u1.get(k)]
if drift:
    print('UDENFOR_OMFANG_AENDRET', *drift, sep='\n', file=sys.stderr)
    raise SystemExit(1)
print('UPGRADE_SCOPE_NAVNE', *sorted(changed), sep='\n', file=sys.stderr)
print('UPGRADE_OK')
PY
