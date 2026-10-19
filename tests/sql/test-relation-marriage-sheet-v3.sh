#!/usr/bin/env bash
# Trin 5b 2b-ii runde 2 (spec §17.6-§17.9): ægteskabsark v3 ende til ende i en engangsbase med writer-kontrakt 2 —
# navneregel v3 (titel inde i navnet, partikelkæde) og en P-linje, der genafgør en new_person_needed med dødsoplysning.
# Printer kun antal og koder.
set -euo pipefail
db=${1:?database}
actor=11000000-0000-0000-0000-0000002b0611
root=$(mktemp -d); chmod 700 "$root"; trap 'rm -rf "$root"' EXIT
sd=.claude/skills/daa-extract/scripts
q() { env -u PGOPTIONS psql -X -q -v ON_ERROR_STOP=1 -d "$db" "$@"; }
q -f tests/sql/fixtures/relation-marriage-v3.sql >/dev/null
PGCLIENTENCODING=UTF8 env -u PGOPTIONS psql -X -Atq -v ON_ERROR_STOP=1 -v actor="$actor" -v source=-22601 -d "$db" \
  -f $sd/relation_v3_rows.sql > "$root/rows.json"
[ "$(python3 $sd/relation_marriage_sheet_v3.py render --rows "$root/rows.json" --out "$root/ark.txt" --private-root "$root")" \
  = "ARK_OK s=1 d=1 n=0 i=0 u=0 p_d=1 p_n=0 p_u=0" ]
rows_sha=$(shasum -a 256 "$root/rows.json" | cut -d' ' -f1); ark_sha=$(shasum -a 256 "$root/ark.txt" | cut -d' ' -f1)
[ "$(python3 $sd/relation_marriage_sheet_v3.py sql --rows "$root/rows.json" --sheet "$root/ark.txt" --approved-sha256 "$ark_sha" \
     --expect-rows-sha256 "$rows_sha" --manifest-out "$root/m.json" --identity-out "$root/i.sql" --private-root "$root")" \
  = "SQL_OK manifest=2 identitet=3" ]
q -v actor="$actor" -v source_id=-22601 -v manifest_file="$root/m.json" -f $sd/relation_persona_apply.sql >/dev/null
q -v actor="$actor" -f "$root/i.sql" >/dev/null
q -At <<SQL | grep -qx 't'
SELECT (SELECT count(*) FROM private.source_persona_identity i JOIN private.source_persona p ON p.id=i.source_persona_id
         WHERE p.source_id=-22601 AND i.decision_status='accepted' AND i.canonical_person_id=-22611
           AND i.evidence->>'sheet_sha256'='$ark_sha')=1
   AND (SELECT count(*) FROM private.reimport_event WHERE element_id LIKE 'relation-persona:%'
         AND payload->>'sheet_sha256'='$ark_sha' AND payload->>'profile'='relation-persona-2018-20-v3')=2
   AND (SELECT count(*) FROM private.source_persona_identity i JOIN private.source_persona p ON p.id=i.source_persona_id
         WHERE p.source_id=-22601 AND i.decision_status='unresolved' AND i.version=2
           AND i.evidence#>'{deceased,clause_years}'='[1314]'::jsonb AND i.evidence->>'sheet_sha256'='$ark_sha')=1;
SQL
# relation_person_create for D-linjen og P-linjen
q -At -c "SELECT private.relation_person_create_input(-22601)::text" > "$root/pc.json"
[ "$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["authorized_elements"]))' "$root/pc.json")" = 2 ]
q -v actor="$actor" -v source_id=-22601 -v manifest_file="$root/pc.json" -v operation=relation_person_create \
  -f $sd/relation_batch_apply.sql >/dev/null
q -At <<SQL | grep -qx 't'
SELECT (SELECT count(*) FROM private.source_persona_identity i JOIN private.source_persona p ON p.id=i.source_persona_id
          JOIN public.person pp ON pp.id=i.canonical_person_id
         WHERE p.source_id=-22601 AND i.decision_status='accepted' AND i.evidence->>'method'='relation-person-create-v1'
           AND pp.staged AND NOT pp.levende AND pp.visning_navn IN ('Eva von und zu Fik','Gro von Hak'))=2;
SQL
# genkørsel af identitetsscriptet: version 0 er forældet ⇒ fejler, 0 nye hændelser
before=$(q -At -c "SELECT count(*) FROM private.source_persona_identity_event")
if q -v actor="$actor" -f "$root/i.sql" >/dev/null 2>"$root/err"; then echo "FEJL: genkoersel godtaget"; exit 1; fi
grep -q EVIDENCE_IDENTITY_VERSION_CONFLICT "$root/err"
# genkørslen stopper ved første M-linje; P-linjens versionslås prøves for sig
sp=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["redecide_rows"][0]["source_persona_id"])' "$root/rows.json")
ctx="{\"basis\":\"human_sheet\",\"deceased\":{\"clause_years\":[1314],\"cutoff_year\":1906,\"rule\":\"aarstal-120-v1\"},\"line\":3,\"rows_sha256\":\"$rows_sha\",\"sheet_sha256\":\"$ark_sha\"}"
if q >/dev/null 2>"$root/err" <<SQL; then echo "FEJL: P-linje genkoersel godtaget"; exit 1; fi
BEGIN;
SELECT set_config('request.jwt.claim.sub','$actor',true) IS NOT NULL \g /dev/null
SET LOCAL ROLE authenticated;
SELECT red_afgoer_source_persona('$sp'::uuid,1,'new_person_needed',NULL,'genkoersel','$ctx'::jsonb) \g /dev/null
COMMIT;
SQL
grep -q EVIDENCE_IDENTITY_VERSION_CONFLICT "$root/err"
[ "$(q -At -c "SELECT count(*) FROM private.source_persona_identity_event")" = "$before" ]
echo MARRIAGE_SHEET_V3_E2E_OK
