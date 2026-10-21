#!/usr/bin/env bash
# Indholds-id (#151, spec §5.1): samme kæde i to baser med forskellig collation, tidszone og tilfældig
# forhistorik skal give byte-identiske id'er, stikprøver, rækkefiler og ark-SQL. Ingen pg_dump (CI-klient 16).
# Brug: bash tests/sql/test-indholds-id-determinism.sh <prefix> [fresh|upgrade:<commit>]
set -euo pipefail
pre=${1:?prefix}; build=${2:-fresh}; A=${pre}_a; B=${pre}_b
S=.claude/skills/daa-extract/scripts; export PGCLIENTENCODING=UTF8
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/priv/A" "$tmp/priv/B" "$tmp/out/A" "$tmp/out/B"; chmod 700 "$tmp/priv" "$tmp/priv/A" "$tmp/priv/B"
q() { env -u PGOPTIONS psql -X -q -v ON_ERROR_STOP=1 -d "$1" "${@:2}" >/dev/null 2>>"$tmp/psql.err" || { grep -m3 -E 'ERROR|FATAL' "$tmp/psql.err"; exit 2; }; }
qa() { env -u PGOPTIONS psql -X -Atq -v ON_ERROR_STOP=1 -d "$1" "${@:2}" 2>>"$tmp/psql.err" || { grep -m3 -E 'ERROR|FATAL' "$tmp/psql.err" >&2; exit 2; }; }
dropdb --if-exists "$A" >/dev/null 2>&1 || true; dropdb --if-exists "$B" >/dev/null 2>&1 || true
createdb -E UTF8 --template=template0 --locale=C "$A"
createdb -E UTF8 --template=template0 --locale-provider=icu --icu-locale=da --locale=C "$B"
q "$A" -c "ALTER DATABASE \"$A\" SET TimeZone='UTC'"; q "$B" -c "ALTER DATABASE \"$B\" SET TimeZone='Pacific/Chatham'"
writer_boot() {
  q "$1" -f tests/sql/1939-v50-writer-bootstrap.sql
  q "$1" -c 'BEGIN' -f tests/sql/reimport-writer-v2-bootstrap.sql -c 'COMMIT'
  q "$1" -f db-rls.sql
}
build_db() {
  local db=$1
  if [ "$build" = fresh ]; then
    for f in tests/sql/evidence-promotion-bootstrap.sql schema.sql db-rls.sql; do q "$db" -f "$f"; done
  else
    local base=${build#upgrade:} t; t=$(mktemp -d)
    for f in schema.sql db-rls.sql db-migrations.sql; do git show "$base:$f" > "$t/$f"; done
    for f in tests/sql/evidence-promotion-bootstrap.sql "$t/schema.sql" "$t/db-rls.sql" "$t/db-migrations.sql" "$t/db-rls.sql" \
             db-migrations.sql db-rls.sql db-migrations.sql db-rls.sql; do q "$db" -f "$f"; done
    rm -rf "$t"
  fi
  writer_boot "$db"
}
build_db "$A"; build_db "$B"
# Dumpet: kun i A, i én transaktion med fixturhjælperne; kopieres tabel for tabel til B.
F=(-f tests/sql/fixtures/relation-5b.sql -f tests/sql/fixtures/relation-2a.sql -f tests/sql/fixtures/marriage-ordinal-244.sql)
q "$A" -c 'BEGIN' "${F[@]}" -f tests/sql/fixtures/indholds-id-dump.sql -c 'COMMIT'
tables=$(qa "$A" -c "SELECT format('%I.%I',n.nspname,c.relname) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE c.relkind='r' AND n.nspname IN ('public','private','auth') ORDER BY 1")
q "$B" -c "SET session_replication_role=replica" -c "TRUNCATE $(echo $tables | tr ' ' ',') CASCADE"
for t in $tables; do
  env -u PGOPTIONS psql -X -q -v ON_ERROR_STOP=1 -d "$A" -c "\copy $t TO STDOUT" | \
    env -u PGOPTIONS psql -X -q -v ON_ERROR_STOP=1 -d "$B" -c "SET session_replication_role=replica" -c "\copy $t FROM pstdin" \
    >/dev/null 2>>"$tmp/psql.err" || { echo "DETERMINISM_SETUP: kopi af $t"; grep -m3 ERROR "$tmp/psql.err"; exit 2; }
done
qa "$A" -c "SELECT format('SELECT setval(%L,%s,%L);',format('%I.%I',schemaname,sequencename),coalesce(last_value,1),last_value IS NOT NULL)
  FROM pg_sequences WHERE schemaname IN ('public','private')" | env -u PGOPTIONS psql -X -q -v ON_ERROR_STOP=1 -d "$B" >/dev/null
# Tilfældig forhistorik kun i B: en anden kilde med en post (tilfældige id'er, fremskudte sekvenser).
q "$B" -c 'BEGIN' -f tests/sql/fixtures/relation-5b.sql -c "SELECT pg_temp.f5b_post(-25099,pg_temp.f5b_source(-25099),'x',
  'Anna Alfa.',ARRAY['Anna Alfa.'],NULL,'11000000-0000-0000-0000-000000025001')" -c 'COMMIT'
for side in A B; do
  db=$([ $side = A ] && echo "$A" || echo "$B"); d=$tmp/out/$side; P=$tmp/priv/$side
  q "$db" -c 'BEGIN' "${F[@]}" -f tests/sql/fixtures/indholds-id-chain.sql
  qa "$db" -f tests/sql/indholds-id-export.sql > "$d/ids.txt"
  ctl=$(qa "$db" -c "SELECT id FROM private.identity_control_run WHERE source_id=-25001")
  qa "$db" -v source_id=-25001 -v mode=undecided -v personas= -f $S/identity_sheet_rows.sql > "$P/identity-rows.json"
  qa "$db" -v control_run_id="$ctl" -f $S/identity_control_rows.sql > "$P/control-rows.json"
  qa "$db" -v source=-25001 -f $S/spouse_exception_rows.sql > "$P/spouse-rows.json"
  # De øvrige ark i spec §4 (v2, v3, børn, ægteskabsnumre); nummerarket har sin egen kilde (#244-verdenen).
  for r in relation_v2_rows relation_v3_rows relation_child_rows; do
    qa "$db" -v source=-25001 -v actor=11000000-0000-0000-0000-000000025001 -f $S/$r.sql > "$d/$r.json"; done
  qa "$db" -v source=-25002 -v actor=11000000-0000-0000-0000-000000025001 -f $S/relation_ordinal_rows.sql > "$d/relation_ordinal_rows.json"
  env -u NODE_OPTIONS python3 $S/spouse_exception_sheet.py render --rows "$P/spouse-rows.json" --out "$P/spouse-ark.txt" --private-root "$tmp/priv" >/dev/null
  sh=$(shasum -a 256 "$P/spouse-ark.txt" | cut -c1-64); rh=$(shasum -a 256 "$P/spouse-rows.json" | cut -c1-64)
  env -u NODE_OPTIONS python3 $S/spouse_exception_sheet.py sql --rows "$P/spouse-rows.json" --sheet "$P/spouse-ark.txt" \
    --approved-sha256 "$sh" --expect-rows-sha256 "$rh" --source -25001 --out "$P/spouse.sql" --private-root "$tmp/priv" >/dev/null
  cp "$P"/identity-rows.json "$P"/control-rows.json "$P"/spouse-rows.json "$P"/spouse-ark.txt "$P"/spouse.sql "$d/"
done
grep -q '^parent-card|' "$tmp/out/A/ids.txt" || { echo 'DETERMINISM_SETUP: intet forældrekort'; exit 2; }
[ "$(grep -c '^candidate-run|' "$tmp/out/A/ids.txt")" = 2 ] || { echo 'DETERMINISM_SETUP: ikke 2 kandidatkørsler'; exit 2; }
grep -q '^sample|' "$tmp/out/A/ids.txt" || { echo 'DETERMINISM_SETUP: tom stikprøve'; exit 2; }
grep -q '"o_rows": \[{' "$tmp/out/A/spouse-rows.json" || { echo 'DETERMINISM_SETUP: ingen O-række'; exit 2; }
for r in relation_v2_rows relation_v3_rows relation_child_rows relation_ordinal_rows; do
  grep -q '"rows": \[{' "$tmp/out/A/$r.json" || { echo "DETERMINISM_SETUP: tom $r"; exit 2; }; done
grep -q '"redecide_rows": \[{' "$tmp/out/A/relation_v3_rows.json" || { echo 'DETERMINISM_SETUP: ingen v3-genafgørelse'; exit 2; }
grep -q '"record_key"' "$tmp/out/A/identity-rows.json" && grep -q '"record_key"' "$tmp/out/A/control-rows.json" \
  || { echo 'DETERMINISM_SETUP: tomme identitets- eller kontrolrækker'; exit 2; }
diffs=$(cd "$tmp/out" && for f in $(ls A); do cmp -s "A/$f" "B/$f" || echo "$f"; done | tr '\n' ' ')
if [ -n "$diffs" ]; then
  echo "DETERMINISM_DIFF: $diffs"
  diff "$tmp/out/A/ids.txt" "$tmp/out/B/ids.txt" | grep '^[<>]' | cut -c3- | cut -d'|' -f1 | sort | uniq -c | sed 's/^/  /'
  dropdb "$A"; dropdb "$B"; exit 1
fi
dropdb "$A"; dropdb "$B"; echo DETERMINISM_OK
