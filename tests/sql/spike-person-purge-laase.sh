#!/usr/bin/env bash
# Task 0 (fuld personsletning): låse-spike med tvungne interleavings.
#
# Brug:  bash tests/sql/spike-person-purge-laase.sh [præfiks] [scenarie ...]
#   præfiks   navn på engangsbaserne (default spike_purge_ci_<pid>); scriptet opretter <præfiks>_base og én kopi pr.
#             scenarie (<præfiks>_<n>) og sletter KUN dem, det selv har oprettet i denne kørsel
#             (SPIKE_KEEP_DBS=1 beholder dem). Det rører aldrig en base, det ikke selv har oprettet.
#   scenarie  et eller flere scenarienavne (se SCENARIER nederst); default alle.
# Output: én linje pr. scenarie i $SPIKE_OUT/resultat.tsv (default en mappe under mktemp) og på stdout; sessionernes
# fulde psql-output (VERBOSITY=verbose, så SQLSTATE står der) i $SPIKE_OUT/<scenarie>/. Kun syntetiske data.
#
# Mekanik: hver session er en baggrunds-psql med sit eget application_name. En observatør poller pg_blocking_pids og
# logger, hvem der venter på hvem, og på hvilken lås. Pauser:
#   - skelettet: opt.pause_after (pg_sleep i transaktionen, mens låsene holdes) eller en tredje session, der holder
#     samme_som_mutation (stopper skelettet ved L7, dvs. mellem L6 og L8);
#   - skriveren: et testinstrument i begin_change_set (kun i spikens base) venter på advisory-nøglen spike_pause_cs,
#     når sessionen har spike.pause_cs=on. Så står skriveren præcis mellem sine rækkelåse og sin første lås på
#     change_set (delta-review D-1's vindue). En tredje session holder nøglen og annulleres for at slippe den.
set -uo pipefail
cd "$(dirname "$0")/../.."
umask 077
PFX=${1:-spike_purge_ci_$$}; [ $# -gt 0 ] && shift
OUT=${SPIKE_OUT:-$(mktemp -d)}; mkdir -p "$OUT"
BASE="${PFX}_base"
ACTOR=c0000000-0000-4000-8000-00000000a001
CREATED=""; N=0
RES="$OUT/resultat.tsv"; : > "$RES"

cleanup() {
  local rc=$?
  for p in $(jobs -p); do kill "$p" 2>/dev/null || true; done
  if [ "${SPIKE_KEEP_DBS:-0}" != 1 ]; then
    for db in $CREATED; do dropdb "$db" >/dev/null 2>&1 || true; done
  else
    echo "beholdt:$CREATED"
  fi
  exit $rc
}
trap cleanup EXIT

q()  { env -u PGOPTIONS psql -X -q -v ON_ERROR_STOP=1 -d "$1" "${@:2}" >/dev/null 2>>"$OUT/build.log" || { tail -5 "$OUT/build.log" >&2; return 1; }; }
a()  { env -u PGOPTIONS psql -X -At -v ON_ERROR_STOP=1 -d "$1" -c "$2"; }
die() { echo "SPIKE_FEJL: $*" >&2; exit 1; }

for db in "$BASE"; do
  [ -z "$(a postgres "SELECT 1 FROM pg_database WHERE datname='$db'")" ] || die "basen $db findes allerede; vælg et andet præfiks"
done

# ---------------------------------------------------------------------------------------------------------------------
# Basen: CI-opskriften (bootstrap + schema + migrations + rls) + kontrakt v2 + skelet + fixtur + publiceret narrativ.
build_base() {
  createdb "$BASE" || die "createdb $BASE"; CREATED="$CREATED $BASE"
  for f in tests/sql/evidence-promotion-bootstrap.sql schema.sql db-migrations.sql db-rls.sql; do q "$BASE" -f "$f" || die "byg $f"; done
  q "$BASE" -c 'BEGIN' -f tests/sql/reimport-writer-v2-bootstrap.sql -c 'COMMIT' || die v2
  q "$BASE" -f tests/sql/spike/person-purge-skelet.sql || die skelet
  q "$BASE" -f tests/sql/spike/person-purge-fixture.sql || die fixtur
  # Testinstrument: pausepunkt først i begin_change_set (identisk krop ellers; schema.sql l. 9339).
  q "$BASE" <<'SQL' || die pausekrog
CREATE OR REPLACE FUNCTION begin_change_set(
  p_operation text, p_summary text, p_subjekt_type text DEFAULT NULL, p_subjekt_id bigint DEFAULT NULL)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_existing text; v_id bigint; v_uid uuid; v_navn text; v_rolle text;
BEGIN
  IF current_setting('spike.pause_cs', true) = 'on' THEN          -- SPIKE-instrument
    PERFORM pg_advisory_xact_lock(hashtext('spike_pause_cs'));
  END IF;
  v_existing := current_setting('app.change_set_id', true);
  IF v_existing IS NOT NULL AND v_existing <> '' THEN
    RETURN v_existing::bigint;
  END IF;
  v_uid := auth.uid();
  SELECT coalesce(p.navn, p.email, v_uid::text), p.rolle INTO v_navn, v_rolle
    FROM profiles p WHERE p.id = v_uid;
  v_navn  := coalesce(v_navn, 'ukendt');
  v_rolle := coalesce(v_rolle, 'medlem');
    INSERT INTO change_set(actor_id, actor_navn, actor_rolle, operation, summary,
                         subjekt_type, subjekt_id, subjekt_synlighed)
    VALUES (v_uid, v_navn, v_rolle, p_operation, p_summary,
            p_subjekt_type, p_subjekt_id, _subjekt_synlighed(p_subjekt_type, p_subjekt_id)) RETURNING id INTO v_id;
  PERFORM set_config('app.change_set_id', v_id::text, true);
  PERFORM set_config('app.change_seq', '0', true);
  RETURN v_id;
END $$;
SQL
  # P's narrativ på P-REC: kladde og publicering gennem de rigtige skrivere.
  q "$BASE" <<SQL || die narrativ
SELECT set_config('request.jwt.claim.sub','$ACTOR',false);
SELECT public.red_upsert_person_narrative_record(-9101,-9001,'P-REC','Spike biografi om Testperson Purge.',false,
  private.narrative_record_state(-9101,-9001,'P-REC',false)->>'state_sha256');
SELECT public.red_publicer_person_narrative_record(-9101,-9001,'P-REC',
  private.narrative_record_state(-9101,-9001,'P-REC',false)->>'state_sha256');
SQL
  # Vagterne skal være de spike-udgaver, der faktisk ligger i basen (db-migrations.sql genskaber de gamle kroppe).
  local m; m=$(a "$BASE" "SELECT count(*) FROM pg_proc WHERE oid IN ('public.enforce_relation_evidence_target()'::regprocedure,
    'public.validate_entity_description_subject()'::regprocedure,'private.validate_polymorf_subjekt_findes()'::regprocedure,
    'private.guard_fact_evidence_delete()'::regprocedure) AND prosrc LIKE '%SPIKE_PERSON_PURGE_VAGT_V1%'")
  [ "$m" = 4 ] || die "vagtmarkør mangler i basen ($m/4)"
  [ "$(a "$BASE" "SELECT public.narrative_record_contract_version()")" = 2 ] || die "kontrakt v2 mangler"
  [ "$(a "$BASE" "SELECT count(*) FROM private.narrative_publication_event WHERE event_type='published'")" = 1 ] \
    || die "publiceringshændelsen mangler"
}

newdb() { N=$((N+1)); DB="${PFX}_$N"; createdb -T "$BASE" "$DB" || die "createdb $DB"; CREATED="$CREATED $DB"; }

# ---------------------------------------------------------------------------------------------------------------------
# Sessioner og observation.
SCEN=""; declare -a PIDS_NAMES=()
start() {  # start <navn> <sql>: baggrunds-psql med application_name=<navn>
  local name=$1 sql=$2 f="$OUT/$SCEN/$1.sql"
  { echo "SELECT set_config('request.jwt.claim.sub','$ACTOR',false) \\g /dev/null"; printf '%s\n' "$sql"; } > "$f"
  PGAPPNAME="spike_$name" env -u PGOPTIONS psql -X -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -d "$DB" -f "$f" \
    > "$OUT/$SCEN/$name.out" 2>&1 &
  eval "PID_$name=$!"
}
pid_of() { a "$DB" "SELECT pid FROM pg_stat_activity WHERE application_name='spike_$1' AND datname='$DB' LIMIT 1"; }
# vent_paa <navn> <tilstand> [sek]: tilstand = laas (venter på en lås) | sover (pg_sleep) | faerdig (findes ikke længere)
vent_paa() {
  local name=$1 st=$2 max=${3:-8} i=0 sqlcond
  case $st in
    laas)    sqlcond="cardinality(pg_blocking_pids(pid))>0" ;;
    sover)   sqlcond="wait_event='PgSleep'" ;;
    faerdig) sqlcond="false" ;;
  esac
  while [ $i -lt $((max*10)) ]; do
    if [ "$st" = faerdig ]; then
      [ -z "$(pid_of "$name")" ] && return 0
    else
      [ "$(a "$DB" "SELECT count(*) FROM pg_stat_activity WHERE application_name='spike_$name' AND datname='$DB' AND $sqlcond")" = 1 ] \
        && return 0
    fi
    sleep 0.1; i=$((i+1))
  done
  return 1
}
# hvem <navn>: "<navn> venter på <andre> (<locktype> <mode> <objekt>)"
hvem() {
  a "$DB" "SELECT replace(w.application_name,'spike_','')||' venter på '||
      coalesce((SELECT string_agg(replace(b.application_name,'spike_',''),',') FROM pg_stat_activity b
                 WHERE b.pid=ANY(pg_blocking_pids(w.pid))),'?')||' ('||
      coalesce((SELECT string_agg(l.locktype||' '||l.mode||coalesce(' '||l.relation::regclass::text,'')
                                 ||CASE WHEN l.locktype='advisory' THEN ' '||l.objid ELSE '' END,'; ')
                  FROM pg_locks l WHERE l.pid=w.pid AND NOT l.granted),'?')||
      -- En rækkeventer holder tuple-låsen på den række, den venter på: den viser tabellen.
      coalesce((SELECT ' række i '||string_agg(DISTINCT l.relation::regclass::text,',') FROM pg_locks l
                 WHERE l.pid=w.pid AND l.granted AND l.locktype='tuple'),'')||')'
    FROM pg_stat_activity w WHERE w.application_name='spike_$1' AND w.datname='$DB'"
}
OBS=""
observer() {  # observer <navn> [sek]: vent til <navn> venter på en lås, og log hvem
  if vent_paa "$1" laas "${2:-8}"; then OBS="$OBS$(hvem "$1"); "; return 0; fi
  OBS="$OBS$1 ventede ikke; "; return 1
}
slip() {  # slip <navn>: annullér en holder-session (dens transaktion ruller tilbage, låsen slippes)
  a "$DB" "SELECT pg_cancel_backend(pid) FROM pg_stat_activity WHERE application_name='spike_$1' AND datname='$DB'" >/dev/null
}
udfald() {  # udfald <navn>: OK eller SQLSTATE: første fejltekst
  local f="$OUT/$SCEN/$1.out" e
  e=$(grep -m1 -E '^(psql:[^ ]+: )?ERROR:' "$f" | sed -E 's/^psql:[^ ]+: //; s/^ERROR: +//' | cut -c1-110)
  [ -n "$e" ] && echo "$e" || echo OK
}
vent_alle() { wait 2>/dev/null || true; }
holder_sql() { echo "BEGIN; $1; SELECT pg_sleep(30); COMMIT;"; }
skelet() { echo "SELECT spike.red_slet_person_helt_skelet($1,'$2'::jsonb);"; }
efter() {  # tilstand bagefter (kun tal)
  a "$DB" "SELECT 'P='||(SELECT count(*) FROM person WHERE id=-9101)||' L='||(SELECT count(*) FROM person WHERE id=-9103)
    ||' fakta(P)='||(SELECT count(*) FROM fact WHERE subjekt_type='person' AND subjekt_id=-9101)
    ||' fakta(L)='||(SELECT count(*) FROM fact WHERE subjekt_type='person' AND subjekt_id=-9103)
    ||' forældreløse_påstande='||(SELECT count(*) FROM assertion a WHERE a.target_type='fact'
                                   AND NOT EXISTS (SELECT 1 FROM fact f WHERE f.id=a.target_id))
    ||' forældreløse_fakta='||(SELECT count(*) FROM fact f WHERE f.subjekt_type='person'
                                   AND NOT EXISTS (SELECT 1 FROM person p WHERE p.id=f.subjekt_id))
    ||' forældreløse_noter='||(SELECT count(*) FROM note n WHERE (n.target_type='fact' AND NOT EXISTS
                                   (SELECT 1 FROM fact f WHERE f.id=n.target_id)) OR (n.target_type='person' AND NOT EXISTS
                                   (SELECT 1 FROM person p WHERE p.id=n.target_id)))"
}
rapport() {  # rapport <scenarie> <beskrivelse>
  local line
  line=$(printf '%s\t%s\t%s\t%s\t%s\t%s' "$SCEN" "$1" "skelet: $(udfald S)" "skriver: $(udfald W)" "$OBS" "$(efter)")
  echo "$line" | tee -a "$RES"
}
ny() { SCEN=$1; OBS=""; mkdir -p "$OUT/$SCEN"; newdb; }

# ---------------------------------------------------------------------------------------------------------------------
# Skrivernes SQL (P=-9101, Q=-9102 i samme kilde, L=-9103 let).
w_ocr_q() { cat <<'SQL'
SELECT red_ret_ocr_felt(-9102,'spike:purge','Q-REC','navn',
  private.ocr_fingerprint('spike:purge','Q-REC','navn',
    private.ocr_importeret('navn','Testperson Anden',NULL,NULL,NULL,NULL,'gregoriansk',NULL),'spike'),
  '{"value":"Testperson Anden rettet"}');
SQL
}
w_paastand() { cat <<'SQL'
SELECT red_ret_paastand(a.id, jsonb_build_object('fact_id',f.id,'faktatype',f.faktatype,'vaerdi_tekst',a.vaerdi_tekst,
  'date_raw',a.date_raw,'valgt_assertion_id',c.valgt_assertion_id,'citation_sources',jsonb_build_array(-9001)),
  'bogen_har_ret','c0000000-0000-4000-8000-0000000000b1')
  FROM assertion a JOIN fact f ON f.id=a.target_id JOIN conclusion c ON c.target_type='fact' AND c.target_id=f.id
 WHERE f.subjekt_type='person' AND f.subjekt_id=-9101 AND f.faktatype='titel';
SQL
}
w_membership() { echo "SELECT red_reverse_placement_membership(-9101,-9001,'spike');"; }
w_medie() { echo "SELECT red_slet_medierelation_uden_evidens((SELECT id FROM relation WHERE rolle='afbildet' AND subjekt_type='person' AND subjekt_id=-9101));"; }
w_revider() { echo "SELECT public.red_revider_publiceret_person_narrative_record(-9101,-9001,'P-REC','Spike biografi revideret.',
  private.narrative_record_state(-9101,-9001,'P-REC',false)->>'state_sha256');"; }
w_fortryd() { echo "SELECT public.red_fortryd_person_narrative_publication_event(
  (SELECT id FROM private.narrative_publication_event WHERE event_type='published'),
  private.narrative_record_state(-9101,-9001,'P-REC',false)->>'state_sha256');"; }
w_upsert_l() { echo "SELECT red_upsert_fakta('person',-9103,'erhverv','Spike erhverv');"; }
w_tilfoej_l() { echo "SELECT red_tilfoej_oplysning((SELECT id FROM fact WHERE subjekt_type='person' AND subjekt_id=-9103 AND faktatype='navn'),'Spike ny påstand');"; }
w_note_l() { echo "INSERT INTO note(target_type,target_id,indhold) SELECT 'fact',id,'Spike note på faktum' FROM fact WHERE subjekt_type='person' AND subjekt_id=-9103 AND faktatype='navn';"; }
w_afgoer() { echo "SELECT red_afgoer_source_persona('c0000000-0000-4000-8000-0000000000c1',0,'same',-9101,'spike');"; }
w_kandidat() { cat <<'SQL'
SELECT red_record_identity_candidates(jsonb_build_object('source_id',-9001,'generator_version','spike',
  'input_spec','{"mode":"undecided"}'::jsonb,
  'input_sha256',red_identity_candidate_input(-9001,'{"mode":"undecided"}')->>'input_sha256','config','{"topK":1}'::jsonb),
  jsonb_build_array(jsonb_build_object('source_persona_id','c0000000-0000-4000-8000-0000000000c1',
    'candidate_person_id',-9101,'rank',1,'score',0.9,'tier','review','basis','{"signals":["name"]}'::jsonb)));
SQL
}

# ---------------------------------------------------------------------------------------------------------------------
# Scenarie-skabeloner.
# D-1, skriveren først: W tager sine rækker og står ved begin_change_set (holder H har spike_pause_cs); S kører til den
# venter på W; H slippes. l8 = 'ROW EXCLUSIVE' (planen) eller 'SHARE ROW EXCLUSIVE' (positiv kontrol, v2.1).
d1_w_foerst() {  # <skriverfunktion> <l8> <beskrivelse>
  ny "$4"
  start H "$(holder_sql "SELECT pg_advisory_xact_lock(hashtext('spike_pause_cs'))")"; vent_paa H sover
  start W "SET spike.pause_cs='on';
$($1)"
  observer W
  start S "$(skelet -9101 "{\"l8_mode\":\"$2\"}")"
  observer S
  slip H; vent_alle; rapport "$3"
}
# D-1, skelettet først: S holder L1-L8 (sover efter L8); W starter og kører så langt det kan; S fortsætter.
d1_s_foerst() {  # <skriverfunktion> <beskrivelse> <navn>
  ny "$3"
  start S "$(skelet -9101 '{"pause_after":"L8","pause_s":3}')"; vent_paa S sover
  start W "$($1)"
  observer W 4 || true
  vent_alle; rapport "$2"
}
# D-2, skelettet først: H holder samme_som_mutation, så S står ved L7 (mellem L6 og L8); W starter; H slippes.
d2_s_foerst() {  # <skriverfunktion> <l5b> <beskrivelse> <navn>
  ny "$4"
  start H "$(holder_sql "SELECT pg_advisory_xact_lock(hashtext('samme_som_mutation'))")"; vent_paa H sover
  start S "$(skelet -9101 "{\"l5b\":$2}")"
  observer S
  start W "$($1)"
  observer W
  slip H; vent_alle; rapport "$3"
}
# D-2, skriveren først: H holder P's narrativrække, så W står efter record → change_set ACCESS EXCLUSIVE → person,
# men før personaen; S starter; H slippes.
d2_w_foerst() {  # <skriverfunktion> <l5b> <beskrivelse> <navn>
  ny "$4"
  start H "$(holder_sql "SELECT 1 FROM narrative WHERE subjekt_type='person' AND subjekt_id=-9101 FOR UPDATE")"
  vent_paa H sover
  start W "$($1)"
  observer W
  start S "$(skelet -9101 "{\"l5b\":$2}")"
  observer S
  slip H; vent_alle; rapport "$3"
}
# Hele skriveren først, ucommittet (holder alle sine låse i 3 s); S starter og venter; W committer.
w_foerst_hel() {  # <skriverfunktion> <person> <skelet-opt> <beskrivelse> <navn>
  ny "$5"
  start W "BEGIN;
$($1)
SELECT pg_sleep(3);
COMMIT;"
  vent_paa W sover || OBS="${OBS}W nåede ikke pg_sleep; "
  start S "$(skelet "$2" "$3")"
  observer S 6 || true
  vent_alle; rapport "$4"
}
# Skelettet først, ucommittet efter sletningen (sover 3 s); W starter og venter; S committer.
s_foerst_hel() {  # <skriverfunktion> <person> <skelet-opt> <beskrivelse> <navn>
  ny "$5"
  start S "$(skelet "$2" "$3")"
  vent_paa S sover || OBS="${OBS}S nåede ikke pg_sleep; "
  start W "$($1)"
  observer W 6 || true
  vent_alle; rapport "$4"
}

# ---------------------------------------------------------------------------------------------------------------------
SCENARIER="d1_ocr d1_paastand d1_membership d1_medie d2_revider d2_fortryd f_upsert g_tilfoej g_note afgoer kandidat h_timeout"
[ $# -gt 0 ] && SCENARIER="$*"
build_base
echo "base=$BASE ud=$OUT"
for s in $SCENARIER; do
  case $s in
    d1_ocr|d1_paastand|d1_membership|d1_medie)
      w=w_${s#d1_}; [ "$s" = d1_ocr ] && w=w_ocr_q
      d1_w_foerst $w 'ROW EXCLUSIVE'       "D-1 ${s#d1_}: skriver først, L8 ROW EXCLUSIVE"            "${s}_w_foerst"
      d1_w_foerst $w 'SHARE ROW EXCLUSIVE' "D-1 ${s#d1_}: skriver først, L8 SHARE ROW EXCLUSIVE (kontrol)" "${s}_w_foerst_sre"
      d1_s_foerst $w                       "D-1 ${s#d1_}: skelet først (holder L1-L8)"                 "${s}_s_foerst" ;;
    d2_revider|d2_fortryd)
      w=w_${s#d2_}
      d2_s_foerst $w true  "D-2 ${s#d2_}: skelet først, stoppet ved L7, med L5b"           "${s}_s_foerst"
      d2_s_foerst $w false "D-2 ${s#d2_}: skelet først, stoppet ved L7, UDEN L5b (kontrol)" "${s}_s_foerst_uden_l5b"
      d2_w_foerst $w true  "D-2 ${s#d2_}: skriver først (record+AE+person), med L5b"       "${s}_w_foerst"
      d2_w_foerst $w false "D-2 ${s#d2_}: skriver først, UDEN L5b (kontrol)"                "${s}_w_foerst_uden_l5b" ;;
    f_upsert)
      w_foerst_hel w_upsert_l -9103 '{"slet_person":true}' "Task 11 (f) red_upsert_fakta(L): skriver først" f_w_foerst
      s_foerst_hel w_upsert_l -9103 '{"slet_person":true,"pause_after":"DELETE","pause_s":3}' \
        "Task 11 (f) red_upsert_fakta(L): skelet først" f_s_foerst ;;
    g_tilfoej)
      w_foerst_hel w_tilfoej_l -9103 '{"slet_person":true}' "Task 11 (g) red_tilfoej_oplysning(L's faktum): skriver først" g_w_foerst
      s_foerst_hel w_tilfoej_l -9103 '{"slet_person":true,"pause_after":"DELETE","pause_s":3}' \
        "Task 11 (g) red_tilfoej_oplysning(L's faktum): skelet først" g_s_foerst ;;
    g_note)
      w_foerst_hel w_note_l -9103 '{"slet_person":true}' "Task 11 (g) note på L's faktum (uden change_set): skriver først" gn_w_foerst
      s_foerst_hel w_note_l -9103 '{"slet_person":true,"pause_after":"DELETE","pause_s":3}' \
        "Task 11 (g) note på L's faktum (uden change_set): skelet først" gn_s_foerst ;;
    afgoer)
      w_foerst_hel w_afgoer -9101 '{}' "red_afgoer_source_persona(Z same P): skriver først" afgoer_w_foerst
      s_foerst_hel w_afgoer -9101 '{"pause_after":"DELETE","pause_s":3}' "red_afgoer_source_persona(Z same P): skelet først" afgoer_s_foerst ;;
    kandidat)
      w_foerst_hel w_kandidat -9101 '{}' "red_record_identity_candidates(S, Z→P): skriver først" kandidat_w_foerst
      s_foerst_hel w_kandidat -9101 '{"pause_after":"DELETE","pause_s":3}' "red_record_identity_candidates(S, Z→P): skelet først" kandidat_s_foerst ;;
    h_timeout)
      ny h_timeout
      start W "$(holder_sql "SELECT 1 FROM person WHERE id=-9101 FOR UPDATE")"; vent_paa W sover
      start S "$(skelet -9101 '{}')"; observer S
      vent_paa S faerdig 12 || true
      slip W; vent_alle; rapport "(h) en anden session holder P FOR UPDATE: lock_timeout 5 s" ;;
    *) die "ukendt scenarie $s" ;;
  esac
done
echo "SPIKE_FAERDIG resultat=$RES"
