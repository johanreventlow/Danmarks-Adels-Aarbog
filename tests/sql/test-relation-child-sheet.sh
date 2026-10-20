#!/usr/bin/env bash
# Trin 5b 2b-iii (spec 2026-10-20 §6, §9): børnearket ende til ende i en engangsbase med writer-kontrakt 2 —
# projektion → ark → hash → afgørelsesscript → afgørelser → preview. Printer kun antal og koder.
set -euo pipefail
db=${1:?database}
actor=11000000-0000-0000-0000-0000002b3e2e
root=$(mktemp -d); chmod 700 "$root"; trap 'rm -rf "$root"' EXIT
sd=.claude/skills/daa-extract/scripts
q() { env -u PGOPTIONS psql -X -q -v ON_ERROR_STOP=1 -d "$db" "$@"; }
q -f tests/sql/fixtures/relation-child-e2e.sql >/dev/null
PGCLIENTENCODING=UTF8 env -u PGOPTIONS psql -X -Atq -v ON_ERROR_STOP=1 -v actor="$actor" -v source=-22701 -d "$db" \
  -f $sd/relation_child_rows.sql > "$root/rows.json"
[ "$(python3 $sd/relation_child_sheet.py render --rows "$root/rows.json" --out "$root/ark.txt" --private-root "$root")" \
  = "ARK_OK passer=1 kort=1 uden=1" ]
rows_sha=$(shasum -a 256 "$root/rows.json" | cut -d' ' -f1); ark_sha=$(shasum -a 256 "$root/ark.txt" | cut -d' ' -f1)
[ "$(python3 $sd/relation_child_sheet.py sql --rows "$root/rows.json" --sheet "$root/ark.txt" --approved-sha256 "$ark_sha" \
     --expect-rows-sha256 "$rows_sha" --decision-out "$root/d.sql" --private-root "$root")" = "SQL_OK b=2 r=0 u=0" ]
# Negativ: et ukendt token afvises, og afgørelsesfilen skrives ikke.
sed 's/ : B$/ : S/' "$root/ark.txt" > "$root/ark-neg.txt"; neg_sha=$(shasum -a 256 "$root/ark-neg.txt" | cut -d' ' -f1)
[ "$(python3 $sd/relation_child_sheet.py sql --rows "$root/rows.json" --sheet "$root/ark-neg.txt" --approved-sha256 "$neg_sha" \
     --expect-rows-sha256 "$rows_sha" --decision-out "$root/neg.sql" --private-root "$root" || true)" = "SHEET_TOKEN_NOT_ALLOWED" ]
[ ! -e "$root/neg.sql" ]
q -v actor="$actor" -f "$root/d.sql" >/dev/null
q -At -v actor="$actor" <<SQL | grep -qx 't'
SELECT (SELECT count(*) FROM private.interpretation_current WHERE source_id=-22701 AND predicate='relation.child'
         AND status='accepted' AND decision_evidence->>'method'='relation-child-v1'
         AND decision_evidence->>'sheet_sha256'='$ark_sha')=2
   AND (SELECT count(*) FROM private.interpretation_current WHERE source_id=-22701 AND predicate='relation.child'
         AND status='proposed')=1;
SQL
q -At -v actor="$actor" <<'SQL' | grep -qx '2'
BEGIN;
SELECT coalesce(jsonb_agg(jsonb_build_object('interpretation_id',ic.id::text,
         'family_id',(private.relation_binding_state(ic.id)#>>'{family,family_id}')::bigint)),'[]')::text AS items
  FROM private.interpretation_current ic WHERE ic.source_id=-22701 AND ic.status='accepted' \gset
SELECT set_config('request.jwt.claim.sub', :'actor', true) \g /dev/null
SET LOCAL ROLE authenticated;
SELECT count(*) FROM jsonb_array_elements(public.red_preview_relation_promotions(-22701,:'items'::jsonb)->'items') i
 WHERE (i->>'eligible')::boolean;
ROLLBACK;
SQL
echo CHILD_SHEET_E2E_OK
