#!/usr/bin/env bash
# Trin 5b 2b-ii (spec §5.3-§6, §10): ægteskabsarket ende til ende i en engangsbase med writer-kontrakt 2.
# Printer kun antal og koder.
set -euo pipefail
db=${1:?database}
actor=11000000-0000-0000-0000-0000002b0601
root=$(mktemp -d); chmod 700 "$root"; trap 'rm -rf "$root"' EXIT
sd=.claude/skills/daa-extract/scripts
pf=.claude/skills/daa-extract/profiles/relation-persona-2018-20.json
q() { env -u PGOPTIONS psql -X -q -v ON_ERROR_STOP=1 -d "$db" "$@"; }
q -f tests/sql/fixtures/relation-marriage-2bii.sql >/dev/null
# Trin 6d-3: relationsprofilerne er data pr. (profil, kilde); testkilden registrerer arkets profil.
q -c "INSERT INTO private.relation_persona_profile(profile,source_id,predicate_forms,text_form)
  VALUES ('relation-persona-2018-20-v2',-22501,'{\"relation.marriage\":\"v2\"}','folded') ON CONFLICT DO NOTHING" >/dev/null
PGCLIENTENCODING=UTF8 env -u PGOPTIONS psql -X -Atq -v ON_ERROR_STOP=1 -v actor="$actor" -v source=-22501 -d "$db" \
  -f $sd/relation_v2_rows.sql > "$root/rows.json"
[ "$(python3 $sd/relation_marriage_sheet.py render --rows "$root/rows.json" --out "$root/ark.txt" --private-root "$root")" = "ARK_OK s=1 d=1 n=0 i=1 u=0" ]
rows_sha=$(shasum -a 256 "$root/rows.json" | cut -d' ' -f1); ark_sha=$(shasum -a 256 "$root/ark.txt" | cut -d' ' -f1)
[ "$(python3 $sd/relation_marriage_sheet.py sql --rows "$root/rows.json" --sheet "$root/ark.txt" --approved-sha256 "$ark_sha" \
     --expect-rows-sha256 "$rows_sha" --manifest-out "$root/m.json" --identity-out "$root/i.sql" --private-root "$root")" \
  = "SQL_OK manifest=2 identitet=2" ]
q -v actor="$actor" -v source_id=-22501 -v manifest_file="$root/m.json" -v profile_file="$pf" -f $sd/relation_persona_apply.sql >/dev/null
# Codex 6d-3 T2: samme profil-id med anden konfiguration eller version afvises (profilrækken er allerede skrevet);
# relation_batch_apply nedenfor genbruger den identiske fil og skal lykkes.
for mut in cfg ver; do
  python3 -I -c 'import json,sys; p=json.load(open(sys.argv[1])); m=sys.argv[3]
if m=="cfg": p["writer_config"]["citation_label_template"]+=" (ændret)"
else: p["profile_version"]+="-ændret"
json.dump(p,open(sys.argv[2],"w"),ensure_ascii=False)' "$pf" "$root/drift-$mut.json" $mut
  if q -v actor="$actor" -v source_id=-22501 -v manifest_file="$root/m.json" -v profile_file="$root/drift-$mut.json" \
       -f $sd/relation_persona_apply.sql >/dev/null 2>"$root/drift.err"; then echo "DRIFT_FAIL $mut godtaget"; exit 1; fi
  grep -q RELATION_PROFILE_FILE_DRIFT "$root/drift.err" || { echo "DRIFT_FAIL $mut: $(head -1 "$root/drift.err")"; exit 1; }
done
q -v actor="$actor" -f "$root/i.sql" >/dev/null
q -At <<SQL | grep -qx 't'
SELECT (SELECT count(*) FROM private.source_persona_identity i JOIN private.source_persona p ON p.id=i.source_persona_id
         WHERE p.source_id=-22501 AND i.decision_status='accepted' AND i.canonical_person_id=-22512
           AND i.evidence->>'sheet_sha256'='$ark_sha')=1
   AND (SELECT count(*) FROM private.source_persona_identity i JOIN private.source_persona p ON p.id=i.source_persona_id
         WHERE p.source_id=-22501 AND i.decision_status='unresolved' AND i.evidence->>'reason'='new_person_needed'
           AND i.evidence#>'{deceased,clause_years}'='[1801,1890]'::jsonb)=1;
SQL
# relation_person_create for D-linjen
q -At -c "SELECT private.relation_person_create_input(-22501)::text" > "$root/pc.json"
q -v actor="$actor" -v source_id=-22501 -v manifest_file="$root/pc.json" -v operation=relation_person_create -v profile_file="$pf" \
  -f $sd/relation_batch_apply.sql >/dev/null
q -At <<SQL | grep -qx 't'
SELECT (SELECT count(*) FROM private.source_persona_identity i JOIN private.source_persona p ON p.id=i.source_persona_id
          JOIN public.person pp ON pp.id=i.canonical_person_id
         WHERE p.source_id=-22501 AND i.decision_status='accepted' AND i.evidence->>'method'='relation-person-create-v1'
           AND pp.staged AND NOT pp.levende AND pp.visning_navn='Bo Beta')=1
   AND (SELECT count(*) FROM public.family_member WHERE person_id=-22501 AND rolle='partner')=1;
SQL
# genkørsel af identitetsscriptet: version 0 er forældet ⇒ fejler, 0 nye hændelser
before=$(q -At -c "SELECT count(*) FROM private.source_persona_identity_event")
if q -v actor="$actor" -f "$root/i.sql" >/dev/null 2>"$root/err"; then echo "FEJL: genkoersel godtaget"; exit 1; fi
grep -q EVIDENCE_IDENTITY_VERSION_CONFLICT "$root/err"
[ "$(q -At -c "SELECT count(*) FROM private.source_persona_identity_event")" = "$before" ]
echo MARRIAGE_SHEET_E2E_OK
