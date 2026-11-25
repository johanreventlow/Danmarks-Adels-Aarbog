#!/usr/bin/env bash
# Task 11: real RPC + real fixture; test-only trigger/helper hooks, never spike skeleton.
# Usage: bash tests/sql/test-person-purge-concurrent.sh <unused-prefix>
# Logs remain in a mktemp dir under $PURGE_LOG_DIR, else $RUNNER_TEMP (CI), else $TMPDIR (never /tmp);
# only scenario names, codes and numbers on stdout.
# Default: keep DBs. PURGE_DROP_DBS=1 drops only successful creations in this invocation.
set -euo pipefail
cd "$(dirname "$0")/../.."
pfx=${1:?prefix}; [[ $pfx =~ ^[a-z][a-z0-9_]{0,35}$ ]] || exit 2
out=$(mktemp -d "${PURGE_LOG_DIR:-${RUNNER_TEMP:-${TMPDIR:?TMPDIR mangler}}}/purge11.XXXXXX"); created=(); jobs=(); n=0; DB=''; scen='build'
# EXIT-trappen arver omdirigeringen fra den kommando, der fejlede (fx >/dev/null): skriv udfaldet til en gemt stdout.
exec 3>&1
cleanup() {
  rc=$?
  if [ -n "$DB" ]; then
    psql -XAtq -d "$DB" -c "SELECT pg_cancel_backend(pid) FROM pg_stat_activity WHERE datname=current_database() AND application_name LIKE 'purge11_%' AND pid<>pg_backend_pid()" >/dev/null 2>&1 || true
  fi
  for pid in ${jobs[@]+"${jobs[@]}"}; do wait "$pid" 2>/dev/null || true; done
  if [ "${PURGE_DROP_DBS:-0}" = 1 ]; then
    for db in ${created[@]+"${created[@]}"}; do dropdb "$db" >/dev/null 2>&1 || true; done
  fi
  [ "$rc" = 0 ] || printf '%s\nSAMTIDIG_FEJL\n' "$scen" >&3
  exit "$rc"
}
trap cleanup EXIT
q() { psql -Xq -v ON_ERROR_STOP=1 -d "$1" "${@:2}" >/dev/null 2>>"$out/build.log"; }
a() { psql -XAtq -v ON_ERROR_STOP=1 -d "$DB" -c "$1" 2>>"$out/build.log"; }
actor="SELECT set_config('request.jwt.claim.sub','a2a00000-0000-4000-8000-00000000a001',false);"
base="${pfx}_base"
createdb "$base"; created+=("$base")
for f in tests/sql/evidence-promotion-bootstrap.sql schema.sql db-rls.sql; do q "$base" -f "$f"; done
q "$base" -c BEGIN -f tests/sql/reimport-writer-v2-bootstrap.sql -c COMMIT
q "$base" -f tests/sql/fixtures/person-purge.sql
q "$base" -f tests/sql/person-purge-concurrent-hooks.sql
new() {
  scen=$1; n=$((n+1)); DB="${pfx}_$n"; jobs=()
  createdb -T "$base" "$DB"; created+=("$DB")
  personas=$(a "SELECT coalesce(jsonb_agg(source_persona_id),'[]'::jsonb) FROM private.source_persona_identity WHERE canonical_person_id=purge_test.id('P') AND decision_status='accepted'")
  families=$(a "SELECT coalesce(jsonb_agg(DISTINCT family_id),'[]'::jsonb) FROM family_member WHERE person_id=purge_test.id('P')")
  sha=$(a "$actor SELECT red_slet_person_helt_preview(purge_test.id('P'))->>'sha256';" | tail -1)
  s="SELECT red_slet_person_helt(purge_test.id('P'),'$sha');"
}
start() {
  local name=$1
  printf '%s\n%s\n' "$actor" "$2" > "$out/$scen-$name.sql"
  ( if psql -Xq -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -d "$DB" \
    -c "SET application_name='purge11_$name'; SET statement_timeout='20s'; SET deadlock_timeout='200ms';" \
    -f "$out/$scen-$name.sql" >"$out/$scen-$name.log" 2>&1; then
      printf '0'; else printf '%s' "$?"; fi ) >"$out/$scen-$name.rc" &
  jobs+=("$!")
}
# Positive evidence of blocker identity AND expected lock type/relation, not elapsed time.
observe() {
  local w=$1 b=$2 typ=$3 rel=${4:-} k
  for k in {1..60}; do
    if [ "$(a "SELECT count(*) FROM pg_stat_activity w JOIN pg_stat_activity b
      ON b.pid=ANY(pg_blocking_pids(w.pid)) WHERE w.datname=current_database()
      AND b.datname=current_database() AND w.application_name='purge11_$w' AND b.application_name='purge11_$b'
      AND EXISTS(SELECT 1 FROM pg_locks l WHERE l.pid=w.pid AND NOT l.granted AND ('$typ'='any' OR l.locktype='$typ'))
      AND ('$rel'='' OR EXISTS(SELECT 1 FROM pg_locks l WHERE l.pid=w.pid AND l.relation=to_regclass('$rel')
        AND (NOT l.granted OR l.locktype='tuple')));")" = 1 ]; then return; fi
    sleep 0.05
  done
  return 1
}
hold() {
  start H "BEGIN; SELECT pg_advisory_xact_lock(911011); SELECT pg_sleep(20); ROLLBACK;"
  for k in {1..60}; do
    [ "$(a "SELECT count(*) FROM pg_stat_activity WHERE datname=current_database() AND application_name='purge11_H' AND wait_event='PgSleep'")" = 1 ] && return
    sleep 0.05
  done
  return 1
}
release() { a "SELECT pg_cancel_backend(pid) FROM pg_stat_activity WHERE datname=current_database() AND application_name='purge11_H'" >/dev/null; }
finish() { for pid in ${jobs[@]+"${jobs[@]}"}; do wait "$pid" || true; done; }
# Første fejlmeddelelse (kun kode/sted, ingen data) til rapportlinjen og R41-bindingen.
msg() { sed -nE 's/.*ERROR:  [A-Z0-9]{5}: ([A-Z_]+(: [A-Za-z0-9_]+)?).*/\1/p' "$out/$scen-$1.log" | head -1; }
code() {
  local c
  c=$(sed -nE 's/.*ERROR:  ([A-Z0-9]{5}):.*/\1/p' "$out/$scen-$1.log" | head -1)
  if [ ! -f "$out/$scen-$1.rc" ]; then echo XXXXX
  elif [ -n "$c" ]; then echo "$c"; elif [ "$(cat "$out/$scen-$1.rc")" != 0 ]; then echo XXXXX
  elif grep -qE 'ERROR|FATAL|psql: error:' "$out/$scen-$1.log"; then echo XXXXX; else echo 00000; fi
}
expect() {
  local c; c=$(code "$1")
  [[ "|$2|" == *"|$c|"* ]] || return 1
  if [ "$c" = P0001 ]; then grep -Eq "$3" "$out/$scen-$1.log"; fi
}
retry_gone() {
  if [ "$(a 'SELECT purge_test.gone()')" != t ]; then
    a "$actor SELECT red_slet_person_helt(purge_test.id('P'),red_slet_person_helt_preview(purge_test.id('P'))->>'sha256');" >/dev/null
  fi
  [ "$(a 'SELECT purge_test.gone()')" = t ]
  psql -XAtq -v ON_ERROR_STOP=1 -d "$DB" -v pid="$(a "SELECT purge_test.id('P')")" \
    -v purge_assert_nul=1 -v purge_count_personas="$personas" -v purge_count_families="$families" \
    -f tests/sql/person-purge-count.sql >/dev/null 2>>"$out/build.log"
}
# ONLY=<regex> kører kun de scenarier, hvis navn matcher (lokal fejlfinding).
skip() { [ -n "${ONLY:-}" ] && ! [[ $1 =~ $ONLY ]]; }
# Port pr. scenarie: skriveren (inkl. opsætning) skal lykkes ALENE før samtidigheden. Ellers kan en ren
# valideringsfejl i et forkert kald passere som et »lukket« udfald i S-først-retningen.
preflight() {
  printf '%s\nBEGIN;\n%s\nSET CONSTRAINTS ALL IMMEDIATE;\nROLLBACK;\n' "$actor" "$w" > "$out/$scen-pre.sql"
  if ! psql -Xq -v ON_ERROR_STOP=1 -d "$DB" -f "$out/$scen-pre.sql" >"$out/$scen-pre.log" 2>&1; then
    echo "PREFLIGHT_FEJL $scen: $(sed -nE 's/.*ERROR:  ([A-Z0-9_]+).*/\1/p' "$out/$scen-pre.log" | head -1)" >&3
    return 1
  fi
}
report() { printf '%s|%s|%s|1|%s\n' "$scen" "$(code S)" "$(code W)" "$(msg S)"; }
# W first: keep the completed writer uncommitted behind H's advisory gate.
wf() {
  preflight
  hold
  start W "BEGIN; $w SELECT pg_advisory_xact_lock(911011); COMMIT;"
  observe W H advisory
  start S "$s"
  observe S W "$1" "${2:-}"
  release; finish
}
# S first: completed purge held uncommitted, or an explicit test-only hook.
sf() {
  preflight
  hold
  if [ "${1:-AFTER}" = AFTER ]; then
    start S "BEGIN; $s SELECT pg_advisory_xact_lock(911011); COMMIT;"
  else start S "BEGIN; SET LOCAL purge_test.pause='$1'; $s COMMIT;"; fi
  observe S H advisory
  start W "$w"
  observe W S "${2:-transactionid}" "${3:-}"
  release; finish
}
closed='PURGE_PREVIEW_AENDRET|PURGE_LOCKSET_DRIFT|PURGE_FINDES_IKKE|PURGE_BLOKERET'
# (a)
if ! skip a_same; then
new a_same; w=$s; sf AFTER advisory
expect S 00000 ''; expect W P0001 'PURGE_FINDES_IKKE|PURGE_PREVIEW_AENDRET'; retry_gone; report
fi
# (f), (g), parent assertion and R33. Both directions must actually wait.
for kind in f_fact g_assert g_note g_parent pin; do
  for order in w s; do
    if skip "${kind}_${order}"; then continue; fi
    new "${kind}_${order}"
    case $kind in
      f_fact) w="SET purge_test.pause='FACT_NEW'; SELECT red_upsert_fakta('person',purge_test.id('P'),'dåb','purge11');"; rel=person ;;
      g_assert) w="SELECT red_tilfoej_oplysning(purge_test.id('fakta_tilnavn'),'purge11');"; rel=fact ;;
      g_note) w="INSERT INTO note(target_type,target_id,indhold) VALUES('fact',purge_test.id('fakta_tilnavn'),'purge11');"; rel=fact ;;
      g_parent) w="SELECT red_tilfoej_foraeldre_paastand(purge_test.id('tredje'),purge_test.id('fam_del'));"; rel=family ;;
      pin) w="SELECT red_set_feed_pin('portrait:'||purge_test.id('P'),'skjul');"; rel=person ;;
    esac
    if [ "$order" = w ]; then
      wf transactionid "$rel"
      expect W 00000 ''
      expect S P0001 "$closed|FACT_HAR_EVIDENS"
    else
      sf AFTER transactionid "$rel"
      expect S 00000 ''
      expect W P0001 'POLYMORF_SUBJEKT_FINDES_IKKE|POLYMORF_OBJEKT_FINDES_IKKE|RELATION_EVIDENCE_TARGET|FEED_PIN|findes ikke'
    fi
    if [ "$kind:$order" = g_parent:w ]; then
      # Den committede forældrepåstand er en anden redaktørs påstand på P's familie: sletningen blokeres nu (ikke
      # »prøv igen«), P findes, og intet er ændret af forsøget.
      before=$(a 'SELECT purge_test.hash()')
      [ "$(a "$actor SELECT count(*) FROM jsonb_array_elements(red_slet_person_helt_preview(purge_test.id('P'))->'blokeringer') b WHERE b->>'art'='anden_paastand'" | tail -1)" -ge 1 ]
      ! psql -XAtq -v ON_ERROR_STOP=1 -d "$DB" -c "$actor SELECT red_slet_person_helt(purge_test.id('P'),red_slet_person_helt_preview(purge_test.id('P'))->>'sha256');" >/dev/null 2>"$out/$scen-retry.err"
      grep -q 'PURGE_BLOKERET: anden_paastand' "$out/$scen-retry.err"
      [ "$(a "SELECT count(*) FROM person WHERE id=purge_test.id('P')")" = 1 ]
      [ "$(a 'SELECT count(*) FROM private.person_purge_manifest')" = 0 ]
      [ "$(a 'SELECT purge_test.hash()')" = "$before" ]
    else retry_gone; fi
    report
  done
done
# (b)-(d), (c) also exercises the public entry to mutate_person_narrative_record.
for kind in b_identity c_publish d_candidates j_reverse; do
  for order in w s; do
    if skip "${kind}_${order}"; then continue; fi
    new "${kind}_${order}"
    case $kind in
      b_identity) w="SELECT red_afgoer_source_persona(purge_test.u('X1'),1,'different',NULL,'purge11');" ;;
      # Fixturens record er stale_published (bevidst tekstdrift): kun tilbagetrækning er tilladt. Den går ad samme
      # mutate_person_narrative_record-vej (source_record-lås) som revision.
      c_publish) w="SELECT red_tilbagetraek_person_narrative_record(purge_test.id('P'),purge_test.id('kilde_a'),'PURGE-P',private.narrative_record_state(purge_test.id('P'),purge_test.id('kilde_a'),'PURGE-P',false)->>'state_sha256');" ;;
      d_candidates) w="SELECT red_record_identity_candidates(jsonb_build_object('source_id',purge_test.id('kilde_a'),'generator_version','purge11','input_spec','{\"mode\":\"undecided\"}'::jsonb,'input_sha256',red_identity_candidate_input(purge_test.id('kilde_a'),'{\"mode\":\"undecided\"}')->>'input_sha256','config','{}'::jsonb),'[]'::jsonb);" ;;
      # Opsætning i kopien: en publiceret hændelse kan ikke fortrydes efter tekstdrift, og fortrydelse af en
      # tilbagetrækning kræver, at P må publiceres. Derfor P offentlig + tilbagetrækning (committet), og skriveren
      # fortryder tilbagetrækningen. Previewets hash genberegnes efter opsætningen.
      j_reverse)
        q "$DB" -c "UPDATE person SET privat=false WHERE id=purge_test.id('P')"
        # Offentlig P: vielsen på fam_keep bliver stående (review 37 P1+P2), så den er ikke i facit i denne kopi.
        q "$DB" -c "DELETE FROM purge_test.forventet WHERE tabel='fact' AND pk=jsonb_build_object('id',purge_test.id('fakta_vielse_keep'))"
        a "$actor SELECT red_tilbagetraek_person_narrative_record(purge_test.id('P'),purge_test.id('kilde_a'),'PURGE-P',private.narrative_record_state(purge_test.id('P'),purge_test.id('kilde_a'),'PURGE-P',false)->>'state_sha256');" >/dev/null
        sha=$(a "$actor SELECT red_slet_person_helt_preview(purge_test.id('P'))->>'sha256'" | tail -1)
        s="SELECT red_slet_person_helt(purge_test.id('P'),'$sha');"
        w="SELECT red_fortryd_person_narrative_publication_event((private.narrative_record_state(purge_test.id('P'),purge_test.id('kilde_a'),'PURGE-P',false)->>'latest_event_id')::uuid,private.narrative_record_state(purge_test.id('P'),purge_test.id('kilde_a'),'PURGE-P',false)->>'state_sha256');" ;;
    esac
    if [ "$order" = w ]; then
      if [[ $kind = c_publish || $kind = j_reverse ]]; then wf transactionid private.source_record; else wf advisory; fi
      expect W 00000 ''; expect S '00000|P0001' "$closed"
    else
      if [[ $kind = c_publish || $kind = j_reverse ]]; then
        preflight
        start H "BEGIN; SELECT pg_advisory_xact_lock(hashtext('samme_som_mutation')); SELECT pg_sleep(20); ROLLBACK;"
        for k in {1..60}; do
          [ "$(a "SELECT count(*) FROM pg_stat_activity WHERE datname=current_database() AND application_name='purge11_H' AND wait_event='PgSleep'")" = 1 ] && break
          sleep 0.05
        done
        start S "$s"; observe S H advisory
        start W "$w"; observe W S transactionid private.source_record
        release; finish
      else sf L7 advisory; fi
      expect S 00000 ''; expect W '00000|P0001' 'IDENTITY_|PERSONA_|NARRATIVE_|PUBLICATION_|findes ikke'; fi
    retry_gone; report
  done
done
# (i) D-1: writers stopped BEFORE begin_change_set takes its RowExclusiveLock.
for kind in ocr paastand membership medie; do
  for order in w s; do
    if skip "i_${kind}_${order}"; then continue; fi
    new "i_${kind}_${order}"
    case $kind in
      ocr)
        # A different person in the SAME source, with an unambiguous OCR anchor.
        # Fixturens tredje person har sin egen record (PURGE-T) i samme kilde som P.
        w="SELECT red_ret_ocr_felt(purge_test.id('tredje'),'purge-test:kilde-a','PURGE-T','koen',private.ocr_fingerprint('purge-test:kilde-a','PURGE-T','koen',private.ocr_importeret('koen',(SELECT koen FROM person WHERE id=purge_test.id('tredje')),NULL,NULL,NULL,NULL,NULL,NULL),NULL),'{\"value\":\"ukendt\"}');" ;;
      paastand)
        # Ny version n+1 af den bundne tilnavn-fortolkning med rettet værdi (»bogen har ret«). Kun denne påstand har
        # den krævede kildecitation; en ny fortolkningsnøgle ville bryde den gældende binding (PAASTAND_BINDING_BRYDES).
        q "$DB" -c "CREATE TABLE purge_test.i_prop(id uuid,old uuid); WITH src AS (
          SELECT i.* FROM private.interpretation_current i JOIN paastand_korrektion k ON k.interpretation_id=i.id
          WHERE k.assertion_id=purge_test.id('assertion_tilnavn') LIMIT 1), ins AS (
          INSERT INTO private.interpretation SELECT (jsonb_populate_record(NULL::private.interpretation,to_jsonb(src)||
            jsonb_build_object('id',gen_random_uuid(),'version',src.version+1,'supersedes_id',src.id,'status','proposed','value','purge11-paastand','decided_by',NULL,'decided_by_name',NULL,'decided_at',NULL))).*
          FROM src RETURNING id,supersedes_id)
          INSERT INTO purge_test.i_prop SELECT id,supersedes_id FROM ins;
          INSERT INTO private.interpretation_observation(interpretation_id,observation_id,evidence_role,ordinal)
          SELECT p.id,o.observation_id,o.evidence_role,o.ordinal FROM purge_test.i_prop p
          JOIN private.interpretation_observation o ON o.interpretation_id=p.old"
        w="SELECT red_ret_paastand(a.id,jsonb_build_object('fact_id',f.id,'faktatype',f.faktatype,'vaerdi_tekst',a.vaerdi_tekst,'date_raw',a.date_raw,'valgt_assertion_id',c.valgt_assertion_id,'citation_sources',(SELECT jsonb_agg(DISTINCT source_id ORDER BY source_id) FROM citation WHERE assertion_id=a.id)),'bogen_har_ret',(SELECT id FROM purge_test.i_prop)) FROM assertion a JOIN fact f ON f.id=a.target_id JOIN conclusion c ON c.target_type='fact' AND c.target_id=f.id WHERE a.id=purge_test.id('assertion_tilnavn');" ;;
      membership)
        q "$DB" -c "UPDATE person_lineage_membership SET source_basis=jsonb_build_object('rule_version','placement-membership-v1','slaegt_id',purge_test.id('slaegt'),'persona_placement_id','purge11') WHERE person_id=purge_test.id('P') AND lineage_id=purge_test.id('linje_a')"
        w="SELECT red_reverse_placement_membership(purge_test.id('P'),purge_test.id('linje_a'),'purge11');" ;;
      medie) w="SELECT red_slet_medierelation_uden_evidens((SELECT id FROM relation WHERE subjekt_type='person' AND subjekt_id=purge_test.id('P') AND objekt_type='media' AND objekt_id=purge_test.id('medie_delt') AND rolle='afbildet'));" ;;
    esac
    sha=$(a "$actor SELECT red_slet_person_helt_preview(purge_test.id('P'))->>'sha256'" | tail -1)
    s="SELECT red_slet_person_helt(purge_test.id('P'),'$sha');"
    if [ "$order" = w ]; then
      cs_max=$(a 'SELECT coalesce(max(id),0) FROM change_set')
      preflight; hold; start W "BEGIN; SET LOCAL purge_test.pause_cs='on'; $w COMMIT;"
      observe W H advisory; start S "$s"; observe S W transactionid
      release; finish
      # R41: W åbner sit change_set (om P) EFTER sletningens plan (D-1-skrivere låser rækken før sættet, og L8 er
      # ROW EXCLUSIVE). Slutkontrollen fanger det nye sæt: PURGE_REST på change_set-stedet, lukket og uden 40P01.
      # Kun for de skrivere, hvor det er observeret, og kun når W's nye sæt er det eneste nye sæt i P's historik.
      expect W 00000 ''
      case $kind in
        membership) expect S '00000|P0001' "$closed|PURGE_REST: S52\$" ;;
        medie) expect S '00000|P0001' "$closed|PURGE_REST: S53\$" ;;
        *) expect S '00000|P0001' "$closed" ;;
      esac
      if [[ "$(msg S)" = PURGE_REST:* ]]; then
        [ "$(a "SELECT count(*) FROM change_set WHERE id>$cs_max")" = 1 ]
        [ "$(a "SELECT count(*) FROM private.person_purge_historik(purge_test.id('P')) WHERE tabel='change_set' AND (pk->>'id')::bigint>$cs_max")" = 1 ]
        [ "$(a 'SELECT count(*) FROM private.person_purge_manifest')" = 0 ]
      fi
    else
      sf AFTER transactionid
      expect S 00000 ''; expect W '00000|P0001' 'OCR_|PAASTAND_|PLACEMENT_|relation|Relation|findes ikke'
    fi
    retry_gone; report
  done
done
# (e) K5 sets from real writers. S53 with force exercises change_set -> same_som.
for form in fakta medie pin; do
  for order in w s; do
    if skip "e_${form}_${order}"; then continue; fi
    new "e_${form}_${order}"
    if [ "$form" = fakta ]; then
      make="SELECT red_upsert_fakta('person',purge_test.id('P'),'erhverv','purge11'); SELECT red_upsert_fakta('person',purge_test.id('tredje'),'erhverv','purge11');"
    elif [ "$form" = pin ]; then
      make="SELECT red_set_feed_pin('portrait:'||purge_test.id('P'),'skjul'); SELECT red_upsert_fakta('person',purge_test.id('tredje'),'erhverv','purge11');"
    else
      make="SELECT red_slet_medierelation_uden_evidens((SELECT id FROM relation WHERE subjekt_type='person' AND subjekt_id=purge_test.id('P') AND objekt_type='media' AND objekt_id=purge_test.id('medie_delt') AND rolle='afbildet'));"
    fi
    cs=$(a "$actor BEGIN; $make SELECT current_setting('app.change_set_id'); COMMIT;" | tail -1)
    [ "$(a "SELECT count(*) FROM private.person_purge_historik(purge_test.id('P')) WHERE tabel='change_set' AND pk->>'id'='$cs'")" = "$([ "$form" = medie ] && echo 1 || echo 0)" ]
    sha=$(a "$actor SELECT red_slet_person_helt_preview(purge_test.id('P'))->>'sha256'" | tail -1)
    s="SELECT red_slet_person_helt(purge_test.id('P'),'$sha');"
    w="SELECT red_fortryd_change_set($cs,true);"
    if [ "$order" = w ]; then wf transactionid; expect W 00000 ''; expect S '00000|P0001' "$closed"
    else sf AFTER transactionid; expect S 00000 ''; expect W '00000|P0001' 'change_set|FORTRYD|PURGE|findes ikke'; fi
    retry_gone; report
  done
done
# Media sharing/variant writer before purge: FK/guard KEY SHARE blocks L11b.
for kind in link variant; do
  for order in w s; do
    if skip "media_${kind}_${order}"; then continue; fi
    new "media_${kind}_${order}"
    if [ "$kind" = link ]; then
      w="SELECT red_relation('person',purge_test.id('tredje'),'media',purge_test.id('medie_eksklusiv'),'afbildet');"
    else
      # Existing fixture has thumb; use medium after removing that cache entry in this copy.
      q "$DB" -c "DELETE FROM media_variant WHERE media_id=purge_test.id('medie_eksklusiv') AND tier='medium'"
      w="INSERT INTO media_variant(media_id,tier,storage_path) VALUES(purge_test.id('medie_eksklusiv'),'medium','purge11/medium');"
      sha=$(a "$actor SELECT red_slet_person_helt_preview(purge_test.id('P'))->>'sha256'" | tail -1)
      s="SELECT red_slet_person_helt(purge_test.id('P'),'$sha');"
    fi
    if [ "$order" = w ]; then
      wf transactionid media; expect W 00000 ''; expect S P0001 "$closed"
      [ "$(a "SELECT count(*) FROM media WHERE id=purge_test.id('medie_eksklusiv')")" = 1 ]
    else
      sf AFTER transactionid media; expect S 00000 ''; expect W 'P0001|23503' 'POLYMORF_SUBJEKT_FINDES_IKKE'
    fi
    retry_gone
    if [ "$kind:$order" = link:w ]; then [ "$(a "SELECT count(*) FROM media WHERE id=purge_test.id('medie_eksklusiv')")" = 1 ]; fi
    report
  done
done
# R39: other principal's current spouse promotion must survive; or writer rolls back.
for order in w s; do
  if skip "r39_${order}"; then continue; fi
  new "r39_${order}"
  q "$DB" -c 'CREATE TABLE purge_test.r39(id uuid,sha text)'
  w="\\i tests/sql/person-purge-concurrent-r39.sql"
  preflight
  hold
  if [ "$order" = w ]; then
    start W "BEGIN;
$w
SELECT pg_advisory_xact_lock(911011); COMMIT;"
    observe W H advisory; start S "$s"; observe S W any
    release; finish
    expect W 00000 ''; expect S P0001 "$closed"
    [ "$(a "SELECT count(*) FROM purge_test.r39 r JOIN private.interpretation_promotion p USING(id) WHERE r.sha=private.relation_binding_state_sha256(p.interpretation_id)")" = 1 ]
    [ "$(a "SELECT count(*) FROM person WHERE id=purge_test.id('P')")" = 1 ]
    [ "$(a 'SELECT count(*) FROM private.person_purge_manifest')" = 0 ]
    # Den første afvisning kan skyldes drift; R39 selv bevises af et nyt forsøg efter W's commit.
    before=$(a 'SELECT purge_test.hash()')
    ! psql -XAtq -v ON_ERROR_STOP=1 -d "$DB" -c "$actor SELECT red_slet_person_helt(purge_test.id('P'),red_slet_person_helt_preview(purge_test.id('P'))->>'sha256');" >/dev/null 2>"$out/$scen-retry.err"
    grep -q 'PURGE_BLOKERET: anden_promotion' "$out/$scen-retry.err"
    [ "$(a 'SELECT purge_test.hash()')" = "$before" ]
    [ "$(a "SELECT count(*) FROM purge_test.r39 r JOIN private.interpretation_promotion p USING(id) WHERE r.sha=private.relation_binding_state_sha256(p.interpretation_id)")" = 1 ]
  else
    start S "BEGIN; SET LOCAL purge_test.pause='L10'; $s COMMIT;"; observe S H advisory
    start W "BEGIN;
$w
COMMIT;"
    observe W S any; release; finish
    expect S 00000 ''; expect W 'P0001|23503' 'IDENTITY_|PERSONA_|POLYMORF_|RELATION_|findes ikke'
    [ "$(a 'SELECT count(*) FROM purge_test.r39')" = 0 ]; retry_gone
  fi
  report
done
# R42 (projektejeren 17/11): FK-inversion family -> person. red_tilfoej_barn's INSERT lader RI tage family KEY SHARE
# før person KEY SHARE; sletningen tager person (L10) før familie (L11). Sletning først: præcis én af de to får
# 40P01 (lukket, »prøv igen«), den anden committer, og ingen rest. Skriver først: lukket afvisning. Samme klasse som
# kommentaren ved private.lock_family_rows (partner). Rettelse (person-først-trigger) står i backloggen.
for order in s w; do
  if skip "k_plejebarn_${order}"; then continue; fi
  new "k_plejebarn_${order}"
  # Opsætning: P er i forvejen barn i en ny familie uden partnere (cyklus-guarden afviser familier med P's efterkommere).
  q "$DB" -c "CREATE TABLE purge_test.k(fid bigint); WITH f AS (INSERT INTO family(type) VALUES('ugift union') RETURNING id)
    INSERT INTO purge_test.k SELECT id FROM f; INSERT INTO family_member(family_id,person_id,rolle)
    SELECT fid,purge_test.id('P'),'barn' FROM purge_test.k"
  personas=$(a "SELECT coalesce(jsonb_agg(source_persona_id),'[]'::jsonb) FROM private.source_persona_identity WHERE canonical_person_id=purge_test.id('P') AND decision_status='accepted'")
  families=$(a "SELECT coalesce(jsonb_agg(DISTINCT family_id),'[]'::jsonb) FROM family_member WHERE person_id=purge_test.id('P')")
  sha=$(a "$actor SELECT red_slet_person_helt_preview(purge_test.id('P'))->>'sha256'" | tail -1)
  s="SELECT red_slet_person_helt(purge_test.id('P'),'$sha');"
  w="SELECT red_tilfoej_barn((SELECT fid FROM purge_test.k),purge_test.id('P'),'plejebarn');"
  preflight
  if [ "$order" = s ]; then
    hold; start S "BEGIN; SET LOCAL purge_test.pause='L10'; $s COMMIT;"; observe S H advisory
    start W "$w"; observe W S transactionid person
    release; finish
    c_s=$(code S); c_w=$(code W)
    [[ "$c_s:$c_w" = 40P01:00000 || "$c_s:$c_w" = 00000:40P01 ]]
    if [ "$c_s" = 40P01 ]; then [ "$(a 'SELECT count(*) FROM private.person_purge_manifest')" = 0 ]; fi
  else
    hold; start W "BEGIN; $w SELECT pg_advisory_xact_lock(911011); COMMIT;"; observe W H advisory
    start S "$s"; observe S W transactionid
    release; finish
    expect W 00000 ''; expect S P0001 "$closed"
  fi
  retry_gone; report
done
# (h) Full public/private table fingerprint, not only P's existence.
if ! skip h_timeout; then
new h_timeout
before=$(a 'SELECT purge_test.hash()')
start W "BEGIN; SELECT 1 FROM person WHERE id=purge_test.id('P') FOR UPDATE; SELECT pg_sleep(10); ROLLBACK;"
for k in {1..60}; do
  [ "$(a "SELECT count(*) FROM pg_stat_activity WHERE datname=current_database() AND application_name='purge11_W' AND wait_event='PgSleep'")" = 1 ] && break
  sleep 0.05
done
start S "$s"; observe S W transactionid person; finish
expect S 55P03 ''; expect W 00000 ''; [ "$(a 'SELECT purge_test.hash()')" = "$before" ]; report
fi
# R37: real existing name, S paused after L10. Exactly one 40P01, the other commits.
if ! skip r37_name; then
new r37_name
w="SELECT red_upsert_fakta('person',purge_test.id('P'),'navn','purge11-r37');"
preflight
hold; start S "BEGIN; SET LOCAL purge_test.pause='L10'; $s COMMIT;"; observe S H advisory
start W "$w"; observe W S transactionid person
release; finish
c_s=$(code S); c_w=$(code W)
[[ "$c_s:$c_w" = 40P01:00000 || "$c_s:$c_w" = 00000:40P01 ]]
if [ "$c_s" = 40P01 ]; then
  [ "$(a 'SELECT count(*) FROM private.person_purge_manifest')" = 0 ]
else
  [ "$(a "SELECT count(*) FROM assertion WHERE vaerdi_tekst='purge11-r37'")" = 0 ]
fi
retry_gone; report
fi
# Review 37 R37P11-3 (ceremoni 2): den fortrydelige sletning låser hele samme_som-gruppen. X og Y er offentlige og
# samme_som. W gør Y privat og holder rækkelåsen; S (red_slet_person(X)) skal vente på W og bagefter afvise med
# samme_som_skjult, fordi gruppen nu er skjult. Før rettelsen låste S kun X og slettede på et forældet billede.
if ! skip r37p11_3_gruppelaas; then
new r37p11_3_gruppelaas
a "$actor DO \$c2\$ DECLARE x bigint; y bigint; BEGIN
  PERFORM purge_test.nyt(); x:=red_opret_person('Testperson Gruppe X','mand',false,'1801','1870',NULL);
  PERFORM purge_test.nyt(); y:=red_opret_person('Testperson Gruppe Y','mand',false,'1801','1870',NULL);
  PERFORM purge_test.nyt(); PERFORM red_set_privat(x,false);
  PERFORM purge_test.nyt(); PERFORM red_set_privat(y,false);
  PERFORM purge_test.nyt(); PERFORM red_samme_som(x,y);
  PERFORM purge_test.gem('c2_x',x); PERFORM purge_test.gem('c2_y',y); END \$c2\$;" >/dev/null
[ "$(a "SELECT public.person_offentlig(purge_test.id('c2_x')) AND public.person_offentlig(purge_test.id('c2_y'))")" = t ]
start W "BEGIN; UPDATE person SET privat=true WHERE id=purge_test.id('c2_y'); SELECT pg_sleep(2); COMMIT;"
for k in {1..60}; do
  [ "$(a "SELECT count(*) FROM pg_stat_activity WHERE datname=current_database() AND application_name='purge11_W' AND wait_event='PgSleep'")" = 1 ] && break
  sleep 0.05
done
start S "SELECT red_slet_person(purge_test.id('c2_x'));"; observe S W transactionid person; finish
expect W 00000 ''; expect S P0001 'SLET_KRAEVER_SLET_HELT: samme_som_skjult'
[ "$(a "SELECT count(*) FROM person WHERE id=purge_test.id('c2_x')")" = 1 ]
report
fi
# Review 37 R37P11-3 (ceremoni 2): »Slet helt« af P mod den fortrydelige sletning af P's samme_som-nabo, som nu låser
# hele gruppen (inkl. P). Begge veje skal vente på samme_som-låsen og ende uden dødlås. P og naboen gøres offentlige,
# så den fortrydelige sletning kan lykkes alene (preflight); P's hash hentes igen efter ændringen.
for dir in wf sf; do
  if skip "r37p11_3_purge_$dir"; then continue; fi
  new "r37p11_3_purge_$dir"
  a "$actor DO \$c2\$ BEGIN PERFORM purge_test.nyt(); PERFORM red_set_privat(purge_test.id('P'),false);
    PERFORM purge_test.nyt(); PERFORM red_set_privat(purge_test.id('nabo'),false); END \$c2\$;" >/dev/null
  sha=$(a "$actor SELECT red_slet_person_helt_preview(purge_test.id('P'))->>'sha256';" | tail -1)
  s="SELECT red_slet_person_helt(purge_test.id('P'),'$sha');"
  w="SELECT red_slet_person(purge_test.id('nabo'));"
  if [ "$dir" = wf ]; then
    wf advisory
    expect W 00000 ''; expect S '00000|P0001' "$closed"
  else
    sf AFTER advisory
    expect S 00000 ''; expect W 00000 ''
  fi
  # Ikke retry_gone: purge_test.gone() forudsætter fixturens private P (fam_keep's indhold slettes kun for en
  # ikke-offentlig P). Her er P offentlig, så tjekket er: P og P's relationer er væk, også efter en lukket S.
  if [ "$(a "SELECT count(*) FROM person WHERE id=purge_test.id('P')")" = 1 ]; then
    a "$actor SELECT red_slet_person_helt(purge_test.id('P'),red_slet_person_helt_preview(purge_test.id('P'))->>'sha256');" >/dev/null
  fi
  [ "$(a "SELECT count(*) FROM person WHERE id=purge_test.id('P')")" = 0 ]
  [ "$(a "SELECT count(*) FROM relation WHERE (subjekt_type='person' AND subjekt_id=purge_test.id('P')) OR (objekt_type='person' AND objekt_id=purge_test.id('P'))")" = 0 ]
  report
done
printf 'SAMTIDIG_OK\n'
