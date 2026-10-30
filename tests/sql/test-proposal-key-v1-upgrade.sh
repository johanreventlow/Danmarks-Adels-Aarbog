#!/usr/bin/env bash
# Trin 6a, Task 6 (spec §4.4 pkt. 6): forslagsnøglens version 1 er uændret gennem opgraderingen fra prods skema.
# Basen bygges som prod (skema, rls, migrationer to gange fra $base, som standard e09f11dd = main før 6a), v1-nøglen
# og v1-funktionernes kroppe måles, de aktuelle migrationer køres to gange, og målingen skal være byte-ens og lig den
# fastlåste vektor. Bagefter køres nøgle- og genkørselstestene på den opgraderede base. Bruges i CI (writer-jobbet).
set -euo pipefail
db=${1:?database}; base=${2:-e09f11dd}
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
for f in schema.sql db-rls.sql db-migrations.sql; do git show "$base:$f" > "$tmp/$f"; done
q() { env -u PGOPTIONS psql -X -q -v ON_ERROR_STOP=1 -d "$db" "$@" >/dev/null; }
a() { env -u PGOPTIONS psql -X -At -v ON_ERROR_STOP=1 -d "$db" "$@"; }
# Kendt input: samme vektor som test_key_v1_unchanged i test-interpretation-proposal.sql.
probe=$(cat <<'SQL'
SELECT concat_ws('|',
  private.interpretation_proposal_key(3,'record-1','person.name',
    '[{"ordinal":2,"verbatim_sha256":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"},{"ordinal":1,"verbatim_sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},{"ordinal":2,"verbatim_sha256":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}]'::jsonb,
    '"Anna Alfa"'::jsonb)::text,
  private.interpretation_proposal_key_material_sha256(3,'record-1','person.name',
    '[{"ordinal":2,"verbatim_sha256":"b"},{"ordinal":1,"verbatim_sha256":"a"}]'::jsonb,'"Anna Alfa"'::jsonb),
  (SELECT string_agg(p.oid::regprocedure::text||'='||md5(pg_get_functiondef(p.oid)),',' ORDER BY p.oid::regprocedure::text)
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='private' AND p.proname IN ('interpretation_proposal_key_material','interpretation_proposal_key_material_sha256',
                                                'interpretation_proposal_key','deterministic_uuid')))
SQL
)
createdb "$db"
for f in tests/sql/evidence-promotion-bootstrap.sql "$tmp/schema.sql" "$tmp/db-rls.sql" "$tmp/db-migrations.sql" "$tmp/db-migrations.sql" "$tmp/db-rls.sql"; do q -f "$f"; done
[ "$(a -c "SELECT to_regprocedure('private.interpretation_proposal_key_material_v2(bigint,text,text,jsonb,jsonb,integer)') IS NULL")" = "t" ] \
  || { echo "UPGRADE_BASE_INVALID: v2 findes allerede i basen fra $base" >&2; exit 1; }
before=$(a -c "$probe")
for f in db-migrations.sql db-migrations.sql db-rls.sql; do q -f "$f"; done
after=$(a -c "$probe")
[ "$before" = "$after" ] || { printf 'PROPOSAL_KEY_V1_UPGRADE_DRIFT\n før:   %s\n efter: %s\n' "$before" "$after" >&2; exit 1; }
[ "${after%%|*}" = "501f645f-62b6-5ad6-84a9-38173cb1a9fd" ] \
  || { echo "PROPOSAL_KEY_V1_VECTOR_DRIFT: ${after%%|*}" >&2; exit 1; }
[ "$(a -c "SELECT to_regprocedure('private.interpretation_proposal_key_material_v2(bigint,text,text,jsonb,jsonb,integer)') IS NOT NULL
  AND NOT has_function_privilege('authenticated','private.interpretation_proposal_key_material_v2(bigint,text,text,jsonb,jsonb,integer)','EXECUTE')")" = "t" ]
q -f tests/sql/test-interpretation-proposal.sql
# Genkørselskontrakten på den opgraderede base (som CI's migrationssti: 1939- og v2-bootstrap, så rls).
q -f tests/sql/1939-v50-writer-bootstrap.sql
q -c 'BEGIN' -f tests/sql/reimport-writer-v2-bootstrap.sql -c 'COMMIT'
q -f db-rls.sql
q -f tests/sql/test-interpretation-proposal-rerun.sql
q -f tests/sql/test-clause-revision.sql
echo "PROPOSAL_KEY_V1_UPGRADE_OK $before"
