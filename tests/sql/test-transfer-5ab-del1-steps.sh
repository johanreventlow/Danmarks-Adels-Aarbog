#!/usr/bin/env bash
# 5a+5b-overførslen, plan B1 Task 3b: skridt-SQL for del 1 (kandidater, kontrol, korroboration). Capture på A, replay på B
# med A's items og samme kandidatfil (pakkens input); mellem kontrol og korroboration står arkets afgørelser (her en
# deterministisk stedfortræder for identity_control_sheet.py's SQL, kørt ens i begge baser).
# Brug: bash tests/sql/test-transfer-5ab-del1-steps.sh <prefix>
set -euo pipefail
pre=${1:?prefix}; A=${pre}_a; B=${pre}_b; M=${pre}_m
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT; chmod 700 "$tmp"; umask 077
source tests/sql/lib-transfer-5ab.sh
fail() { echo "DEL1STEPS5AB_FAIL: $*"; exit 1; }
uuid_re='[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
# Aktøren angives altid eksplicit (fixturens redaktør); skridtene vælger den aldrig selv.
ACTOR=11000000-0000-0000-0000-000000025001
dg() { qa "$1" -v src=-25101 -f $S/transfer_5ab_digests.sql; }
step() {
  local db=$1 name=$2 mode=$3 items=$4; shift 4
  env -u PGOPTIONS psql -X -q -v ON_ERROR_STOP=1 -d "$db" -v src=-25101 -v actor="${STEP_ACTOR-$ACTOR}" -v mode="$mode" -v items="$items" "$@" \
    -f $S/transfer_5ab_step_$name.sql 2>"$tmp/step.err" | tee -a "$tmp/all.out"
}
field() { sed -nE "s/.* $1=([^ ]+).*/\1/p" <<<"$2"; }

t5_build_ab tests/sql/fixtures/transfer-5ab-del1-dump.sql
t5_chain "$A" tests/sql/fixtures/transfer-5ab-del1.sql; t5_chain "$B" tests/sql/fixtures/transfer-5ab-del1.sql
# Kandidatfilen (generatorens output; pakkens input): rang 1 = posternes rigtige partner, egnet til bekræftelse.
qa "$A" -c "SELECT set_config('request.jwt.claim.sub','$ACTOR',false)" \
  -c "WITH i AS (SELECT private.identity_candidate_input(-25101,'{\"mode\":\"undecided\"}') j)
  SELECT jsonb_build_object('run',jsonb_build_object('source_id',-25101,'generator_version','test','config','{\"k\":1}'::jsonb,
      'input_spec','{\"mode\":\"undecided\"}'::jsonb,'input_sha256',private.reimport_canonical_json_sha256(i.j)),
    'candidates',(SELECT jsonb_agg(jsonb_build_object('source_persona_id',pe->>'source_persona_id',
        'candidate_person_id',-25200-2*substring(sp.persona_key from '^G-([0-9]+)')::int-1,'rank',1,'score',0.95,'tier','auto',
        'basis',jsonb_build_object('signals',jsonb_build_array('name','family_partner'),'corroboration_eligible',true))
      ORDER BY pe->>'source_persona_id' COLLATE \"C\")
      FROM jsonb_array_elements(i.j->'personas') pe JOIN private.source_persona sp ON sp.id=(pe->>'source_persona_id')::uuid))::text FROM i" \
  | tail -1 > "$tmp/cand.json"
[ "$(python3 -I -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["candidates"]))' "$tmp/cand.json")" = 22 ] \
  || fail "opsætning: ikke 22 kandidater"
# Arkets stedfortræder: forsegl, afgør hver stikprøve som rang 1 (via visningspladsen), evaluér.
cat > "$tmp/sheet.sql" <<'SQL'
\set ON_ERROR_STOP on
BEGIN;
SELECT set_config('request.jwt.claim.sub','11000000-0000-0000-0000-000000025001',true) \g /dev/null
DO $$ DECLARE v_ctl uuid; v_run uuid; v_smp jsonb; v_pos text; i int; BEGIN
  SELECT c.id,c.candidate_run_id INTO STRICT v_ctl,v_run FROM private.identity_control_run c WHERE c.source_id=-25101;
  SET LOCAL ROLE authenticated;
  v_smp:=red_identity_control_sample(v_ctl);
  PERFORM red_seal_identity_control_run(v_ctl,repeat('a',64),repeat('b',64));
  FOR i IN 0..jsonb_array_length(v_smp->'samples')-1 LOOP
    RESET ROLE;
    SELECT key INTO STRICT v_pos FROM jsonb_each_text(v_smp->'samples'->i->'mapping') m
     WHERE m.value=(SELECT c3.id::text FROM private.source_persona_identity_candidate c3 WHERE c3.run_id=v_run AND c3.rank=1
                      AND c3.source_persona_id=(v_smp->'samples'->i->>'source_persona_id')::uuid);
    SET LOCAL ROLE authenticated;
    PERFORM red_afgoer_source_persona((v_smp->'samples'->i->>'source_persona_id')::uuid,0,'same',NULL,'stikprøve',
      jsonb_build_object('basis','human_sheet','sheet_sha256',repeat('a',64),'rows_sha256',repeat('b',64),'line',i+1,
        'control_run_id',v_ctl,'display_position',v_pos::int));
  END LOOP;
  IF red_evaluate_identity_control_run(v_ctl)<>'passed' THEN RAISE EXCEPTION 'T5_SHEET: ikke bestået'; END IF;
  RESET ROLE;
END $$;
COMMIT;
SQL

prev_a=$tmp/a0.dg; prev_b=$tmp/b0.dg; dg "$A" > "$prev_a"; dg "$B" > "$prev_b"
[ -z "$(dgcmp "$prev_a" "$prev_b")" ] || fail "opsætning: A og B afviger før skridtene: $(dgcmp "$prev_a" "$prev_b")"
for s in candidates:candidate_runs,candidates:22 control:control_runs,control_samples:20 corroborate:identities,identity_events:1; do
  name=${s%%:*}; rest=${s#*:}; layers=${rest%%:*}; min=${rest##*:}
  extra=(); [ "$name" = candidates ] && extra=(-v input="$tmp/cand.json")
  oa=$(step "$A" $name capture "$tmp/$name.items" ${extra[@]+"${extra[@]}"}) || fail "capture $name: $(grep -m1 -iE 'error|fatal' "$tmp/step.err")"
  [[ "$oa" =~ ^STEP_OK\ $name\ n=[0-9]+\ items_sha256=[0-9a-f]{64}$ ]] || fail "capture $name: udskrift '$oa'"
  [ "$(field n "$oa")" -ge "$min" ] || fail "d1_capture_replay $name: n=$(field n "$oa") < $min"
  dg "$A" > "$tmp/a-$name.dg"; d=$(dgcmp "$prev_a" "$tmp/a-$name.dg")
  for l in ${layers//,/ }; do case ",$d," in *",$l,"*) ;; *) fail "d1_capture_replay $name: laget $l uændret (ændret: $d)";; esac; done
  if [ "$name" = candidates ]; then
    # d1_mismatch: replay med én kandidat ændret ⇒ stop før RPC'en, digests uændrede (på en kopi af B).
    python3 -I -c 'import json,sys; j=json.load(open(sys.argv[1])); j["candidates"][0]["score"]=0.5; json.dump(j, open(sys.argv[2],"w"))' \
      "$tmp/cand.json" "$tmp/cand-bad.json"
    t5_clone "$B" "$M"
    if step "$M" candidates replay "$tmp/candidates.items" -v input="$tmp/cand-bad.json" >/dev/null; then fail "d1_mismatch: lykkedes"; fi
    grep -q STEP_ITEMS_MISMATCH "$tmp/step.err" || fail "d1_mismatch: anden fejl: $(grep -m1 -iE 'error|fatal' "$tmp/step.err")"
    dg "$M" > "$tmp/m.dg"; dropdb "$M"; [ -z "$(dgcmp "$prev_b" "$tmp/m.dg")" ] || fail "d1_mismatch: digests ændret"
    echo "d1_mismatch OK"
  fi
  ob=$(step "$B" $name replay "$tmp/$name.items" ${extra[@]+"${extra[@]}"}) || fail "replay $name: $(grep -m1 -iE 'error|fatal' "$tmp/step.err")"
  [ "$(field items_sha256 "$oa")" = "$(field items_sha256 "$ob")" ] || fail "d1_capture_replay $name: items_sha256 afviger"
  [ "$(field n "$oa")" = "$(field n "$ob")" ] || fail "d1_capture_replay $name: n afviger ($oa / $ob)"
  dg "$B" > "$tmp/b-$name.dg"; d=$(dgcmp "$tmp/a-$name.dg" "$tmp/b-$name.dg"); [ -z "$d" ] || fail "d1_capture_replay $name: A og B afviger: $d"
  prev_a=$tmp/a-$name.dg; prev_b=$tmp/b-$name.dg
  if [ "$name" = control ]; then
    q "$A" -f "$tmp/sheet.sql"; q "$B" -f "$tmp/sheet.sql"
    dg "$A" > "$tmp/a-sheet.dg"; dg "$B" > "$tmp/b-sheet.dg"
    [ -z "$(dgcmp "$tmp/a-sheet.dg" "$tmp/b-sheet.dg")" ] || fail "arkets stedfortræder: A og B afviger"
    prev_a=$tmp/a-sheet.dg; prev_b=$tmp/b-sheet.dg
  fi
  echo "d1_capture_replay $name OK ($oa)" | sed -E 's/ items_sha256=[0-9a-f]+//'
done
# d1_ids_content (vagt): kandidat- og kontrolkørslens id'er er indholds-id'er (#251) og derfor ens i A og B; overførslen
# hviler alligevel på nøglerne, så ældre bevisbaser (tilfældige id'er) virker.
for t in source_persona_identity_candidate_run identity_control_run; do
  [ "$(qa "$A" -c "SELECT string_agg(id::text,',' ORDER BY id) FROM private.$t WHERE source_id=-25101")" = \
    "$(qa "$B" -c "SELECT string_agg(id::text,',' ORDER BY id) FROM private.$t WHERE source_id=-25101")" ] || fail "d1_ids_content: $t"
done
echo "d1_ids_content OK"
grep -Eq "$uuid_re" "$tmp/all.out" && fail "d1_no_uuid: uuid i udskriften"
[ "$(grep -c '^STEP_OK ' "$tmp/all.out")" -ge 6 ] || fail "d1_no_uuid: for få STEP_OK-linjer"
echo "d1_no_uuid OK"
dropdb "$A"; dropdb "$B"; echo DEL1STEPS5AB_OK
