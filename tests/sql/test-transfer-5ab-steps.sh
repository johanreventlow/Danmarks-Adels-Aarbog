#!/usr/bin/env bash
# 5a+5b-overførslen, plan B1 Task 3a: skridt-SQL for afgørelse, binding, disposition og afvisning. Hvert skridt køres i
# capture på A og i replay på B med A's items; B har tilfældige id'er, hvor A har andre (fortolkninger, bindinger, og
# afvisningens mål er givet et andet id i B), så items skal slås op via nøgler og hashes genberegnes i basen.
# Brug: bash tests/sql/test-transfer-5ab-steps.sh <prefix>
set -euo pipefail
pre=${1:?prefix}; A=${pre}_a; B=${pre}_b; C=${pre}_c; M=${pre}_m
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT; chmod 700 "$tmp"; umask 077
source tests/sql/lib-transfer-5ab.sh
fail() { echo "STEPS5AB_FAIL: $*"; exit 1; }
uuid_re='[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
# Aktøren angives altid eksplicit (fixturens redaktør); skridtene vælger den aldrig selv.
ACTOR=11000000-0000-0000-0000-000000025001
dg() { qa "$1" -v src=-25001 -f $S/transfer_5ab_digests.sql; }
uh() { qa "$1" -v src=-25001 -f $S/transfer_5ab_untouched_hash.sql; }
# step <db> <skridt> <mode> <items> [-v …]: stdout (én STEP_OK-linje) gemmes også i all.out; stderr i step.err.
step() {
  local db=$1 name=$2 mode=$3 items=$4; shift 4
  env -u PGOPTIONS psql -X -q -v ON_ERROR_STOP=1 -d "$db" -v src=-25001 -v actor="${STEP_ACTOR-$ACTOR}" -v mode="$mode" -v items="$items" "$@" \
    -f $S/transfer_5ab_step_$name.sql 2>"$tmp/step.err" | tee -a "$tmp/all.out"
}
# step_fails <kode> <db> <skridt> <mode> <items> […]: skridtet skal fejle med netop den kode.
step_fails() {
  local code=$1; shift
  if step "$@" >/dev/null; then fail "$code: skridtet $2 lykkedes"; fi
  grep -q "$code" "$tmp/step.err" || fail "$code: fejlede af anden grund: $(grep -m1 -iE 'error|fatal' "$tmp/step.err")"
}
field() { sed -nE "s/.* $1=([^ ]+).*/\1/p" <<<"$2"; }

t5_build_ab tests/sql/fixtures/indholds-id-dump.sql tests/sql/fixtures/transfer-5ab-dispositions-dump.sql
# Afvisningens mål (Fie Fots ægteskab, v1 fra dumpet) får et andet id i B: samme logiske version, forskelligt id, som
# mellem en bevisbase og D1. Alle fremmednøgler til fortolkningens id flyttes med.
q "$B" -c "SET session_replication_role=replica" -c "DO \$\$ DECLARE v_old uuid; v_new uuid:=gen_random_uuid(); r record; BEGIN
  SELECT id INTO STRICT v_old FROM private.interpretation WHERE source_id=-25001 AND predicate='relation.marriage' AND value->>'raw' LIKE '%Fie Fot%';
  FOR r IN SELECT format('%I.%I', n.nspname, c.relname) t, a.attname col FROM pg_constraint k
             JOIN pg_class c ON c.oid=k.conrelid JOIN pg_namespace n ON n.oid=c.relnamespace
             JOIN pg_attribute a ON a.attrelid=k.conrelid AND a.attnum=k.conkey[1]
            WHERE k.contype='f' AND k.confrelid='private.interpretation'::regclass LOOP
    EXECUTE format('UPDATE %s SET %I=\$1 WHERE %I=\$2', r.t, r.col, r.col) USING v_new, v_old;
  END LOOP;
  UPDATE private.interpretation SET id=v_new WHERE id=v_old;
END \$\$"
t5_chain "$A" tests/sql/fixtures/transfer-5ab-chain.sql; t5_chain "$B" tests/sql/fixtures/transfer-5ab-chain.sql
# st_actor_required: uden aktør, med en ukendt og med en ikke-redaktør stopper skridtet, før det skriver noget.
dg "$A" > "$tmp/pre.dg"
if env -u PGOPTIONS psql -X -q -v ON_ERROR_STOP=1 -d "$A" -v src=-25001 -v mode=capture -v items="$tmp/x.items" \
     -f $S/transfer_5ab_step_profile.sql >/dev/null 2>"$tmp/step.err"; then fail "st_actor_required: uden aktør lykkedes"; fi
grep -q 'STEP_USAGE: -v actor mangler' "$tmp/step.err" || fail "st_actor_required: $(grep -m1 -i error "$tmp/step.err")"
q "$A" -c "INSERT INTO auth.users(id,email) VALUES ('11000000-0000-0000-0000-0000000250ff','laeser@5b.invalid')" \
       -c "INSERT INTO public.profiles(id,rolle,navn,email) VALUES ('11000000-0000-0000-0000-0000000250ff','medlem','Medlem','laeser@5b.invalid')"
for bad in 11000000-0000-0000-0000-0000000250ee 11000000-0000-0000-0000-0000000250ff; do
  STEP_ACTOR=$bad; if step "$A" profile capture "$tmp/x.items" >/dev/null; then fail "st_actor_required: $bad godtaget"; fi
  grep -q STEP_ACTOR_INVALID "$tmp/step.err" || fail "st_actor_required: $(grep -m1 -i error "$tmp/step.err")"
done; unset STEP_ACTOR
q "$A" -c "DELETE FROM public.profiles WHERE id='11000000-0000-0000-0000-0000000250ff'" -c "DELETE FROM auth.users WHERE id='11000000-0000-0000-0000-0000000250ff'"
dg "$A" > "$tmp/post.dg"; [ -z "$(dgcmp "$tmp/pre.dg" "$tmp/post.dg")" ] || fail "st_actor_required: digests ændret"
echo "st_actor_required OK"
dg "$A" > "$tmp/a0.dg"; dg "$B" > "$tmp/b0.dg"; uh "$A" > "$tmp/a0.uh"
[ -z "$(dgcmp "$tmp/a0.dg" "$tmp/b0.dg")" ] || fail "opsætning: A og B afviger før skridtene: $(dgcmp "$tmp/a0.dg" "$tmp/b0.dg")"
# C: en frisk kopi af B før skridtene, til genspillet af pakken (Task 6).
t5_clone "$B" "$C"
TS() { env -u NODE_OPTIONS python3 -I $S/transfer_steps.py "$@"; }
PACK=$tmp/pack.json
TS init --pack "$PACK" --d1-receipt-sha256 "$(shasum -a 256 "$tmp/a0.dg" | cut -c1-64)" --restore-hash "$(shasum -a 256 "$tmp/a0.uh" | cut -c1-64)" >/dev/null
fie="SELECT sp.persona_key FROM private.source_persona sp JOIN private.source_persona_mention spm ON spm.persona_id=sp.id
  JOIN private.source_mention sm ON sm.id=spm.mention_id WHERE sm.verbatim_text='Fie Fot' AND spm.mention_role='spouse'"
pk=$(qa "$A" -c "$fie"); [ -n "$pk" ] || fail "opsætning: ingen persona for Fie Fot"
python3 -I -c 'import json,sys; json.dump([{"persona_key":sys.argv[1],"evidence":{"basis":"human_sheet_review","sheet_sha256":"f"*64,
  "sheet_line":13,"reason":"test","decided_on":"2026-10-22","report":"test"}}], open(sys.argv[2],"w"))' "$pk" "$tmp/reject-input.json"

# check <skridt> <før> <efter> <lag,…> <n> <min-n>: skridtets lag ændrede sig, og n er mindst det forventede.
check() {
  local d; d=$(dgcmp "$2" "$3")
  [ -n "$d" ] || fail "st_capture_replay $1: ingen digest ændret"
  for l in ${4//,/ }; do case ",$d," in *",$l,"*) ;; *) fail "st_capture_replay $1: laget $l uændret (ændret: $d)";; esac; done
  [ "$5" -ge "$6" ] || fail "st_capture_replay $1: n=$5 < $6"
}
prev_a=$tmp/a0.dg; prev_b=$tmp/b0.dg
for s in profile:writer_profiles:1 decide:interpretations,classifications:1 bind:bindings:1 \
         disposition:dispositions:1 reject:interpretations:1; do
  name=${s%%:*}; rest=${s#*:}; layers=${rest%%:*}; min=${rest##*:}
  extra=(); [ "$name" = disposition ] && extra=(-v manifest="$tmp/$name-a.manifest")
  [ "$name" = reject ] && extra=(-v input="$tmp/reject-input.json")
  oa=$(step "$A" $name capture "$tmp/$name.items" ${extra[@]+"${extra[@]}"}) || fail "capture $name: $(grep -m1 -iE 'error|fatal' "$tmp/step.err")"
  [[ "$oa" =~ ^STEP_OK\ $name\ n=[0-9]+\ items_sha256=[0-9a-f]{64}$ ]] || fail "capture $name: udskrift '$oa'"
  dg "$A" > "$tmp/a-$name.dg"; check "$name" "$prev_a" "$tmp/a-$name.dg" "$layers" "$(field n "$oa")" "$min"
  bextra=(); [ "$name" = disposition ] && bextra=(-v manifest="$tmp/$name-b.manifest")
  case $name in
    decide)
      # st_mismatch: én item fjernet ⇒ stop før RPC'en, digests uændrede (på en kopi af B).
      python3 -I -c 'import json,sys; j=json.load(open(sys.argv[1])); json.dump(j[1:], open(sys.argv[2],"w"))' \
        "$tmp/decide.items" "$tmp/decide-short.items"
      t5_clone "$B" "$M"; step_fails STEP_ITEMS_MISMATCH "$M" decide replay "$tmp/decide-short.items"
      dg "$M" > "$tmp/m.dg"; dropdb "$M"; [ -z "$(dgcmp "$prev_b" "$tmp/m.dg")" ] || fail "st_mismatch: digests ændret"
      echo "st_mismatch OK"
      # st_fault: fejl lige før COMMIT ⇒ intet skrevet; derefter uden fejl (nedenfor).
      step_fails STEP_FAULT "$B" decide replay "$tmp/decide.items" -v fault=before_commit
      dg "$B" > "$tmp/bf.dg"; [ -z "$(dgcmp "$prev_b" "$tmp/bf.dg")" ] || fail "st_fault: digests ændret"
      echo "st_fault OK";;
    disposition)
      # st_writer_issued: afbrudt efter autorisationen ⇒ skridtets lag uændret, én issued-autorisation efterladt.
      step_fails STEP_FAULT "$B" disposition replay "$tmp/disposition.items" -v manifest="$tmp/disposition-f.manifest" -v fault=after_authorize
      dg "$B" > "$tmp/bw.dg"; d=$(dgcmp "$prev_b" "$tmp/bw.dg")
      [ "$d" = authorizations_issued ] || fail "st_writer_issued: '$d'"
      [ "$(dgval "$tmp/bw.dg" authorizations_issued)" = 1 ] || fail "st_writer_issued: ikke én issued"
      echo "st_writer_issued OK";;
    reject)
      # st_reject_ids_differ (vagt): målets gældende id er forskelligt i A og B.
      iq="SELECT ic.id FROM private.interpretation_current ic WHERE ic.source_id=-25001 AND ic.predicate='relation.marriage'
            AND ic.value->>'raw' LIKE '%Fie Fot%'"
      [ "$(qa "$A" -c "$iq")" != "$(qa "$B" -c "$iq")" ] || fail "st_reject_ids_differ: samme id i A og B"
      echo "st_reject_ids_differ OK"
      # st_reject_ambiguous: personaen er ægtefælle i to ægteskaber ⇒ stop.
      t5_clone "$B" "$M"
      q "$M" -c "SET session_replication_role=replica" -c "INSERT INTO private.interpretation_party(interpretation_key,party_role,version,
          source_persona_id,marriage_ordinal,origin,origin_ref) SELECT ic.interpretation_key,'spouse',99,sp.id,1,'relation_persona',gen_random_uuid() FROM private.interpretation_current ic,
          private.source_persona sp WHERE sp.source_id=-25001 AND sp.persona_key='$pk' AND ic.source_id=-25001
          AND ic.predicate='relation.marriage' AND ic.value->>'raw' NOT LIKE '%Fie Fot%' ORDER BY ic.interpretation_key LIMIT 1"
      step_fails STEP_REJECT_AMBIGUOUS "$M" reject replay "$tmp/reject.items"; dropdb "$M"
      echo "st_reject_ambiguous OK";;
  esac
  ob=$(step "$B" $name replay "$tmp/$name.items" ${bextra[@]+"${bextra[@]}"}) || fail "replay $name: $(grep -m1 -iE 'error|fatal' "$tmp/step.err")"
  [ "$(field items_sha256 "$oa")" = "$(field items_sha256 "$ob")" ] || fail "st_capture_replay $name: items_sha256 afviger"
  [ "$(field n "$oa")" = "$(field n "$ob")" ] || fail "st_capture_replay $name: n afviger ($oa / $ob)"
  dg "$B" > "$tmp/b-$name.dg"
  d=$(dgcmp "$tmp/a-$name.dg" "$tmp/b-$name.dg" authorizations_issued); [ -z "$d" ] || fail "st_capture_replay $name: A og B afviger: $d"
  if [ "$name" = decide ]; then
    # st_actor_explicit: afgørelsens nye versioner bærer netop den angivne aktør, i begge baser.
    for db in "$A" "$B"; do
      [ "$(qa "$db" -c "SELECT count(*) FILTER (WHERE decided_by IS DISTINCT FROM '$ACTOR') || ':' || count(*) FROM private.interpretation
           WHERE source_id=-25001 AND version>1 AND predicate='relation.marriage'")" = "0:$(field n "$oa")" ] || fail "st_actor_explicit: $db"
    done
    echo "st_actor_explicit OK"
  fi
  if [ "$name" = bind ]; then
    # st_rerun: bind igen ⇒ alle pakkens egnede er nu ALREADY_APPLIED ⇒ n=0 uden kald.
    np=$(qa "$B" -c "SELECT count(*) FROM private.interpretation_promotion")
    or=$(step "$B" bind replay "$tmp/bind.items") || fail "st_rerun: $(grep -m1 -iE 'error|fatal' "$tmp/step.err")"
    [[ "$or" =~ ^STEP_OK\ bind\ n=0\ already_applied=[1-9][0-9]*\ items_sha256= ]] || fail "st_rerun: '$or'"
    [ "$(qa "$B" -c "SELECT count(*) FROM private.interpretation_promotion")" = "$np" ] || fail "st_rerun: nye bindinger"
    echo "st_rerun OK"
  fi
  # Pakken: skridtet med A's items-hash, lag og digests før/efter.
  case $name in profile) ty=sql; pl=writer_profiles;; decide) ty=hash_gated; pl=interpretations,classifications;;
    bind) ty=hash_gated; pl=bindings;; disposition) ty=writer; pl=dispositions,authorizations_consumed;; reject) ty=sql; pl=interpretations;; esac
  inp='{}'; [ "$name" = reject ] && inp="{\"reject-input\":\"$(shasum -a 256 "$tmp/reject-input.json" | cut -c1-64)\"}"
  TS add-step --pack "$PACK" --name $name --type $ty --script repo:$S/transfer_5ab_step_$name.sql --vars '{"src":-25001}' --inputs "$inp" \
    --items-sha256 "$(field items_sha256 "$oa")" --layers $pl --count "$(field n "$oa")" --digests-in "$prev_a" \
    --digests-out "$tmp/a-$name.dg" --seconds 0 >/dev/null || fail "add-step $name"
  prev_a=$tmp/a-$name.dg; prev_b=$tmp/b-$name.dg
  echo "st_capture_replay $name OK ($oa)" | sed -E 's/ items_sha256=[0-9a-f]+//'
done
# st_pack_replay: pakken genspilles på C via løkken classify → replay → classify. Efter bind »glemmes« logføringen (afbrud
# mellem COMMIT og loggen): classify giver da ALREADY_APPLIED uden skrivning. Til sidst er intet skridt tilbage.
TS validate --pack "$PACK" | grep -q '^PACK_OK steps=5 ' || fail "st_pack_replay: pakken er ugyldig"
# st_inventory: skridt-scripts og alt, de trækker ind med \ir, skal være bundet i inventaret; én manglende fil afvises.
mkdir "$tmp/priv"
iv=$(TS inventory --pack "$PACK" --root . --private "$tmp/priv" 2>&1) && fail "st_inventory: tomt inventar godtaget"
[[ "$iv" == "INVENTORY_MISMATCH repo:$S/transfer_5ab_step_profile.sql" ]] || fail "st_inventory: '$iv'"
for f in $S/transfer_5ab_step_{profile,decide,bind,disposition,reject,begin,items,compare,end}.sql $S/relation_batch_apply.sql; do
  TS inventory-add --pack "$PACK" --root . --private "$tmp/priv" --key "repo:$f" >/dev/null || fail "st_inventory: $f"; done
[ "$(TS inventory --pack "$PACK" --root . --private "$tmp/priv")" = "INVENTORY_OK n=10" ] || fail "st_inventory: bundet inventar"
echo "st_inventory OK"
done_list=
for k in 1 2 3 4 5; do
  name=$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["steps"][int(sys.argv[2])-1]["name"])' "$PACK" $k)
  [ "$(TS next --pack "$PACK" --done "$done_list")" = "NEXT n=$k name=$name" ] || fail "st_pack_replay: next før skridt $k"
  dg "$C" > "$tmp/c.dg"; st=$(TS classify --pack "$PACK" --n $k --digests "$tmp/c.dg") || true
  [ "$st" = WRITE ] || fail "st_pack_replay: skridt $k ($name) er $st før"
  cx=(); [ "$name" = disposition ] && cx=(-v manifest="$tmp/$name-c.manifest")
  oc=$(step "$C" $name replay "$tmp/$name.items" ${cx[@]+"${cx[@]}"}) || fail "st_pack_replay: $name: $(grep -m1 -iE 'error|fatal' "$tmp/step.err")"
  want=$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["steps"][int(sys.argv[2])-1]["items_sha256"])' "$PACK" $k)
  [ "$(field items_sha256 "$oc")" = "$want" ] || fail "st_pack_replay: items_sha256 for $name"
  dg "$C" > "$tmp/c.dg"; st=$(TS classify --pack "$PACK" --n $k --digests "$tmp/c.dg") || true
  [ "$st" = ALREADY_APPLIED ] || fail "st_pack_replay: skridt $k ($name) er $st efter"
  if [ "$name" = bind ]; then
    np=$(qa "$C" -c "SELECT count(*) FROM private.interpretation_promotion")
    st=$(TS classify --pack "$PACK" --n $k --digests "$tmp/c.dg") || true
    [ "$st" = ALREADY_APPLIED ] && [ "$(qa "$C" -c "SELECT count(*) FROM private.interpretation_promotion")" = "$np" ] \
      || fail "st_pack_replay: genoptagelse efter afbrud"
  fi
  done_list=${done_list:+$done_list,}$k
done
[ "$(TS next --pack "$PACK" --done "$done_list")" = NEXT_NONE ] || fail "st_pack_replay: skridt tilbage"
d=$(dgcmp "$tmp/a-reject.dg" "$tmp/c.dg" authorizations_issued); [ -z "$d" ] || fail "st_pack_replay: C afviger fra A: $d"
grep -Eq "$uuid_re" "$PACK" && fail "st_pack_replay: uuid i pakken"
echo "st_pack_replay OK"
# Uberørt-hashen er uændret af alle skridtene (de skriver kun i kædens tabeller).
uh "$A" > "$tmp/a1.uh"; cmp -s "$tmp/a0.uh" "$tmp/a1.uh" || fail "uberørt-hashen ændret af skridtene"
echo "st_untouched OK"
# st_no_uuid: ingen udskrift indeholder et uuid.
grep -Eq "$uuid_re" "$tmp/all.out" && fail "st_no_uuid: uuid i udskriften"
[ "$(grep -c '^STEP_OK ' "$tmp/all.out")" -ge 11 ] || fail "st_no_uuid: for få STEP_OK-linjer"
echo "st_no_uuid OK"
dropdb "$A"; dropdb "$B"; dropdb "$C"; echo STEPS5AB_OK
