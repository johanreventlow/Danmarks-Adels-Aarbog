# Fælles opbygning for 5a+5b-overførslens tests (plan B1): to baser A og B som i test-indholds-id-determinism.sh
# (forskellig collation og tidszone; dumpet kun bygget i A og kopieret tabel for tabel til B; tilfældig forhistorik i
# kilde -25099 kun i B). Sources: kaldes med `source tests/sql/lib-transfer-5ab.sh` efter `set -euo pipefail`.
# Forventer: $tmp (mappe), $A, $B. Giver: q, qa, t5_build_ab <dumpfil>…, t5_chain <db> <kædefil>, t5_clone <fra> <til>,
# dgcmp <a> <b> [udeladt-lag,…], dgval <fil> <lag>.
S=.claude/skills/daa-extract/scripts; export PGCLIENTENCODING=UTF8
T5_F=(-f tests/sql/fixtures/relation-5b.sql -f tests/sql/fixtures/relation-2a.sql -f tests/sql/fixtures/marriage-ordinal-244.sql)
q() { env -u PGOPTIONS psql -X -q -v ON_ERROR_STOP=1 -d "$1" "${@:2}" >/dev/null 2>>"$tmp/psql.err" || { grep -m3 -iE 'error|fatal' "$tmp/psql.err"; exit 2; }; }
qa() { env -u PGOPTIONS psql -X -Atq -v ON_ERROR_STOP=1 -d "$1" "${@:2}" 2>>"$tmp/psql.err" || { grep -m3 -iE 'error|fatal' "$tmp/psql.err" >&2; exit 2; }; }
t5_build_db() {
  local db=$1 f
  for f in tests/sql/evidence-promotion-bootstrap.sql schema.sql db-rls.sql tests/sql/1939-v50-writer-bootstrap.sql; do q "$db" -f "$f"; done
  q "$db" -c 'BEGIN' -f tests/sql/reimport-writer-v2-bootstrap.sql -c 'COMMIT'
  q "$db" -f db-rls.sql
}
# t5_build_ab <dumpfil>…: dumpfilerne køres i A i én transaktion med fixturhjælperne og kopieres til B.
t5_build_ab() {
  local d tables t dump=()
  for d in "$@"; do dump+=(-f "$d"); done
  dropdb --if-exists "$A" >/dev/null 2>&1 || true; dropdb --if-exists "$B" >/dev/null 2>&1 || true
  createdb -E UTF8 --template=template0 --locale=C "$A"
  createdb -E UTF8 --template=template0 --locale-provider=icu --icu-locale=da --locale=C "$B"
  q "$A" -c "ALTER DATABASE \"$A\" SET TimeZone='UTC'"; q "$B" -c "ALTER DATABASE \"$B\" SET TimeZone='Pacific/Chatham'"
  t5_build_db "$A"; t5_build_db "$B"
  q "$A" -c 'BEGIN' "${T5_F[@]}" "${dump[@]}" -c 'COMMIT'
  tables=$(qa "$A" -c "SELECT format('%I.%I',n.nspname,c.relname) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE c.relkind='r' AND n.nspname IN ('public','private','auth') ORDER BY 1")
  q "$B" -c "SET session_replication_role=replica" -c "TRUNCATE $(echo $tables | tr ' ' ',') CASCADE"
  for t in $tables; do
    env -u PGOPTIONS psql -X -q -v ON_ERROR_STOP=1 -d "$A" -c "\copy $t TO STDOUT" | \
      env -u PGOPTIONS psql -X -q -v ON_ERROR_STOP=1 -d "$B" -c "SET session_replication_role=replica" -c "\copy $t FROM pstdin" \
      >/dev/null 2>>"$tmp/psql.err" || { echo "T5_SETUP: kopi af $t"; grep -m3 ERROR "$tmp/psql.err"; exit 2; }
  done
  qa "$A" -c "SELECT format('SELECT setval(%L,%s,%L);',format('%I.%I',schemaname,sequencename),coalesce(last_value,1),last_value IS NOT NULL)
    FROM pg_sequences WHERE schemaname IN ('public','private')" | env -u PGOPTIONS psql -X -q -v ON_ERROR_STOP=1 -d "$B" >/dev/null
  q "$B" -c 'BEGIN' -f tests/sql/fixtures/relation-5b.sql -c "SELECT pg_temp.f5b_post(-25099,pg_temp.f5b_source(-25099),'x',
    'Anna Alfa.',ARRAY['Anna Alfa.'],NULL,'11000000-0000-0000-0000-000000025001')" -c 'COMMIT'
}
# t5_chain <db> <kædefil>: kæden afslutter selv med COMMIT (som indholds-id-chain.sql).
t5_chain() { q "$1" -c 'BEGIN' "${T5_F[@]}" -f "$2"; }
# t5_clone <fra> <til>: kopi af en base (ingen forbindelser til <fra> må være åbne).
t5_clone() { dropdb --if-exists "$2" >/dev/null 2>&1 || true; createdb -T "$1" "$2"; }
# dgcmp <a> <b> [udeladt,…]: lagene, hvis n eller sha256 afviger mellem to digest-filer (kommasepareret, sorteret).
dgcmp() {
  python3 -I -c '
import json, sys
a, b = (json.loads(open(p).read().split("=", 1)[1]) for p in sys.argv[1:3])
skip = set(sys.argv[3].split(",")) if len(sys.argv) > 3 else set()
print(",".join(sorted(k for k in set(a) | set(b) if k != "n_uuid_unmapped" and k not in skip and a.get(k) != b.get(k))))' "$@"
}
# dgval <fil> <lag>: lagets n (eller n_uuid_unmapped).
dgval() { python3 -I -c 'import json,sys; j=json.loads(open(sys.argv[1]).read().split("=",1)[1]); k=sys.argv[2]; print(j[k] if k=="n_uuid_unmapped" else j[k]["n"])' "$1" "$2"; }
