#!/usr/bin/env bash
# #244 (spec §6, §9): nummerarket ende til ende i en engangsbase — input → ark → hash → afgørelsesscript → rettelser →
# preview (2 genbindinger). Printer kun antal og koder.
set -euo pipefail
db=${1:?database}
actor=11000000-0000-0000-0000-0000000244e2
root=$(mktemp -d); chmod 700 "$root"; trap 'rm -rf "$root"' EXIT
sd=.claude/skills/daa-extract/scripts
q() { env -u PGOPTIONS psql -X -q -v ON_ERROR_STOP=1 -d "$db" "$@"; }
q -f tests/sql/fixtures/relation-ordinal-e2e.sql >/dev/null
PGCLIENTENCODING=UTF8 env -u PGOPTIONS psql -X -Atq -v ON_ERROR_STOP=1 -v actor="$actor" -v source=-24451 -d "$db" \
  -f $sd/relation_ordinal_rows.sql > "$root/rows.json"
[ "$(python3 $sd/relation_ordinal_sheet.py render --rows "$root/rows.json" --out "$root/ark.txt" --private-root "$root")" \
  = "ARK_OK linjer=2 uden=0" ]
rows_sha=$(shasum -a 256 "$root/rows.json" | cut -d' ' -f1); ark_sha=$(shasum -a 256 "$root/ark.txt" | cut -d' ' -f1)
# Negativ: rettet efter godkendelsen → hash afvist, ingen fil.
sed 's/ : B$/ : U/' "$root/ark.txt" > "$root/ark-neg.txt"
[ "$(python3 $sd/relation_ordinal_sheet.py sql --rows "$root/rows.json" --sheet "$root/ark-neg.txt" --approved-sha256 "$ark_sha" \
     --expect-rows-sha256 "$rows_sha" --decision-out "$root/neg.sql" --private-root "$root" || true)" = "SHEET_HASH_MISMATCH" ]
[ ! -e "$root/neg.sql" ]
# Negativ: R er ikke et gyldigt svar her.
sed 's/ : B$/ : R/' "$root/ark.txt" > "$root/ark-r.txt"; r_sha=$(shasum -a 256 "$root/ark-r.txt" | cut -d' ' -f1)
[ "$(python3 $sd/relation_ordinal_sheet.py sql --rows "$root/rows.json" --sheet "$root/ark-r.txt" --approved-sha256 "$r_sha" \
     --expect-rows-sha256 "$rows_sha" --decision-out "$root/r.sql" --private-root "$root" || true)" = "SHEET_TOKEN_NOT_ALLOWED" ]
[ ! -e "$root/r.sql" ]
[ "$(python3 $sd/relation_ordinal_sheet.py sql --rows "$root/rows.json" --sheet "$root/ark.txt" --approved-sha256 "$ark_sha" \
     --expect-rows-sha256 "$rows_sha" --decision-out "$root/d.sql" --private-root "$root")" = "SQL_OK b=2 u=0" ]
q -v actor="$actor" -f "$root/d.sql" >/dev/null
q -At <<SQL | grep -qx 't'
SELECT (SELECT count(*) FROM private.marriage_ordinal_correction c
         WHERE c.evidence->>'sheet_sha256'='$ark_sha' AND c.family_id IN (SELECT family_id FROM family_member WHERE person_id=-24451))=2;
SQL
q -At -v actor="$actor" <<'SQL' | grep -qx '2'
BEGIN;
SELECT coalesce(jsonb_agg(jsonb_build_object('interpretation_id',ic.id::text,
         'family_id',(private.relation_binding_state(ic.id)#>>'{family,family_id}')::bigint)),'[]')::text AS items
  FROM private.interpretation_current ic WHERE ic.source_id=-24451 AND ic.status='accepted' \gset
SELECT set_config('request.jwt.claim.sub', :'actor', true) \g /dev/null
SET LOCAL ROLE authenticated;
SELECT count(*) FROM jsonb_array_elements(public.red_preview_relation_promotions(-24451,:'items'::jsonb)->'items') i
 WHERE (i->>'eligible')::boolean AND i->>'supersedes_promotion_id' IS NOT NULL;
ROLLBACK;
SQL
echo ORDINAL_SHEET_E2E_OK
