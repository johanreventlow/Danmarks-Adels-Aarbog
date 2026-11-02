#!/usr/bin/env bash
# Trin 6c-2 Task 7: kontrolværktøjet v2 ende-til-ende på en syntetisk fixtur.
# Eksport med kildescope → plan → tomt ark → udfyldt ark → sql → psql → verify-sql → psql, og de afviste veje:
# P <person> der ikke findes, P <personaens nuværende person> og PERSONA_HAR_PROMOTIONER (SQL-sidens værn, før
# identitetskaldet), B uden entydigt mål og SAMPLE_FAILED (værktøjet skriver ingen SQL).
# $PGDATABASE SKAL være en ren base bygget med CI-opskriften (bootstrap + schema + rls + migrations + rls). Scriptet
# opretter kopier ${PGDATABASE}_v2<løbenr>_<pid> og sletter kun dem, det selv har oprettet i denne kørsel
# (CONTROL_V2_KEEP_DBS=1 beholder dem). Det sletter aldrig en base, det ikke selv har oprettet.
# bash 3.2-kompatibelt (macOS). Printer kun tilstande, fejlkoder og tal; fixturen er syntetisk.
set -euo pipefail
umask 077
cd "$(dirname "$0")/../.."
: "${PGDATABASE:?PGDATABASE skal pege på en ren base bygget med CI-opskriften}"
BASE="$PGDATABASE"
PY="${DAA_PYTHON:-python3}"
S=.claude/skills/daa-extract/scripts
A=c4750000-0000-4000-8000-000000000001      # redaktionsprofilen i fixturen
SRC=-4750
T=$(mktemp -d)
CREATED=""
N=0

cleanup() {
  local rc=$?
  if [ "${CONTROL_V2_KEEP_DBS:-0}" != 1 ]; then
    for db in $CREATED; do dropdb "$db" || true; done
  elif [ -n "$CREATED" ]; then
    echo "beholdt:$CREATED"
  fi
  rm -rf "$T"
  exit $rc
}
trap cleanup EXIT

die() { echo "FEJL: $*" >&2; exit 1; }
q() { psql -X -q -v ON_ERROR_STOP=1 "$@"; }
cm() { "$PY" "$S/control_model_v2.py" "$@"; }

# newdb: ny engangskopi af den rene base (navnet er unikt for kørslen; en eksisterende base røres ikke).
newdb() {
  N=$((N + 1))
  DB="${BASE}_v2${N}_$$"
  createdb -T "$BASE" "$DB"
  CREATED="$CREATED $DB"
}

iid() { echo "c4750000-0000-4000-8000-0000000003$1"; }
pid() { echo "c4750000-0000-4000-8000-00000000010$1"; }

cat > "$T/fixture.sql" <<'SQL'
BEGIN;
-- Kilde S = -4750 og en anden kilde -4749 (kun som medciterende). Personas 1-9 → personer -4751..-4759; -4760 er
-- P-målet uden fakta. Forslag (NN → persona, prædikat, værdi mod databasen, klasse):
--   11 p1 død 1850 = 1850 MATCH (svag)             51 p5 død 1860 ≠ 1861 REAL_DIFF
--   21 p2 død 1851 = 1851 MATCH                     61 p6 fødsel '12. marts 1702' ~ '12 marts 1702' SKRIVEMAADE
--   31 p3 død 1852 = 1852 MATCH                     71 p7 død 1870 = 1870 MATCH;  72 p7 titel kammerherre ≠ REAL_DIFF
--   41 p4 død 1853 = 1853 MATCH                     81 p8 navn 'Hans Testlow' ⊂ 'Hans Testlow til Testholm' REAL_DIFF
--   42 p4 navn 'Dorte Testlow' ≠ 'Dorthe Testlow'   91 p9 død 1881 ≠ 1880 (påstanden citeres også af -4749) REAL_DIFF
INSERT INTO auth.users(id,email) VALUES ('c4750000-0000-4000-8000-000000000001','kontrolv2@test.invalid');
INSERT INTO profiles(id,rolle,navn,email) VALUES
  ('c4750000-0000-4000-8000-000000000001','redaktion','Kontrol v2','kontrolv2@test.invalid');
INSERT INTO person(id,levende,privat,status) SELECT -4750-n,false,false,'kontrolv2' FROM generate_series(1,10) n;
INSERT INTO source(id,titel,import_key) VALUES (-4750,'Kontrol v2','verify:kontrolv2'),
                                              (-4749,'Kontrol v2 anden','verify:kontrolv2b');
INSERT INTO private.extraction_run(id,source_id,run_key,schema_version,extractor_version,profile_version,input_sha256,manifest)
  VALUES ('c4750000-0000-4000-8000-0000000000a1',-4750,'kontrolv2-run','1.0','verify','verify',repeat('9',64),'{}');
INSERT INTO private.source_rendition(id,source_id,rendition_key,rendition_kind,content_sha256,metadata)
  VALUES ('c4750000-0000-4000-8000-0000000000a2',-4750,'kontrolv2-rendition','text_layer',repeat('8',64),'{}');
INSERT INTO private.source_record_occurrence(id,rendition_id,occurrence_key,page_from,page_to,char_from,char_to,
  verbatim_text,physical_fingerprint,structural_fingerprint,extraction_run_id)
  VALUES ('c4750000-0000-4000-8000-0000000000a3','c4750000-0000-4000-8000-0000000000a2','kontrolv2-occ',1,1,0,4,'1850',
          'phys-kontrolv2','struct-kontrolv2','c4750000-0000-4000-8000-0000000000a1');
INSERT INTO private.source_observation(id,occurrence_id,observation_kind,page_from,page_to,char_from,char_to,
  verbatim_text,quality_status,extraction_method,extraction_run_id)
  VALUES ('c4750000-0000-4000-8000-0000000000a4','c4750000-0000-4000-8000-0000000000a3','name_clause',1,1,0,4,'1850',
          'clear','verify','c4750000-0000-4000-8000-0000000000a1');
INSERT INTO private.source_record(id,source_id,record_key,record_kind,created_run_id)
  VALUES ('c4750000-0000-4000-8000-0000000000a5',-4750,'KV2','person_entry','c4750000-0000-4000-8000-0000000000a1');
INSERT INTO private.source_record_anchor_event(occurrence_id,source_record_id,decision_status,evidence,version,decided_by,decided_by_name)
  VALUES ('c4750000-0000-4000-8000-0000000000a3','c4750000-0000-4000-8000-0000000000a5','accepted','{"basis":"kontrolv2"}',1,
          'c4750000-0000-4000-8000-000000000001','fixture');
INSERT INTO private.source_persona(id,source_id,persona_key,created_run_id)
  SELECT ('c4750000-0000-4000-8000-00000000010'||n)::uuid,-4750,'kontrolv2-'||n,'c4750000-0000-4000-8000-0000000000a1'
    FROM generate_series(1,9) n;
INSERT INTO private.source_mention(id,observation_id,mention_kind,char_from,char_to,verbatim_text,created_run_id)
  SELECT ('c4750000-0000-4000-8000-00000000020'||n)::uuid,'c4750000-0000-4000-8000-0000000000a4','person',0,4,'1850',
         'c4750000-0000-4000-8000-0000000000a1' FROM generate_series(1,9) n;
INSERT INTO private.source_persona_mention(persona_id,mention_id,mention_role,ordinal)
  SELECT ('c4750000-0000-4000-8000-00000000010'||n)::uuid,('c4750000-0000-4000-8000-00000000020'||n)::uuid,'principal',1
    FROM generate_series(1,9) n;
INSERT INTO private.source_persona_identity_event(source_persona_id,canonical_person_id,decision_status,version,evidence,
                                                  decided_by,decided_by_name,decided_at)
  SELECT ('c4750000-0000-4000-8000-00000000010'||n)::uuid,-4750-n,'accepted',1,
         jsonb_build_object('basis','fixture','outcome',CASE WHEN n=1 THEN 'svag' ELSE 'enig' END),
         'c4750000-0000-4000-8000-000000000001','fixture',now()
    FROM generate_series(1,9) n;
INSERT INTO private.source_persona_identity(source_persona_id,canonical_person_id,decision_status,version,evidence,
                                            decided_by,decided_by_name,decided_at)
  SELECT source_persona_id,canonical_person_id,decision_status,version,evidence,decided_by,decided_by_name,decided_at
    FROM private.source_persona_identity_event WHERE source_persona_id::text LIKE 'c4750000-%';
INSERT INTO fact(id,subjekt_type,subjekt_id,faktatype) VALUES
  (-47511,'person',-4751,'død'),(-47521,'person',-4752,'død'),(-47531,'person',-4753,'død'),(-47541,'person',-4754,'død'),
  (-47542,'person',-4754,'navn'),(-47551,'person',-4755,'død'),(-47561,'person',-4756,'fødsel'),
  (-47571,'person',-4757,'død'),(-47572,'person',-4757,'titel'),(-47581,'person',-4758,'navn'),(-47591,'person',-4759,'død');
INSERT INTO assertion(id,target_type,target_id,vaerdi_tekst,calendar,uforanderlig) VALUES
  (-47542,'fact',-47542,'Dorthe Testlow','gregoriansk',true),(-47572,'fact',-47572,'hofjægermester','gregoriansk',true),
  (-47581,'fact',-47581,'Hans Testlow til Testholm','gregoriansk',true);
INSERT INTO assertion(id,target_type,target_id,date_raw,date_min,date_max,calendar,uforanderlig) VALUES
  (-47511,'fact',-47511,'1850','1850-01-01','1850-12-31','gregoriansk',true),
  (-47521,'fact',-47521,'1851','1851-01-01','1851-12-31','gregoriansk',true),
  (-47531,'fact',-47531,'1852','1852-01-01','1852-12-31','gregoriansk',true),
  (-47541,'fact',-47541,'1853','1853-01-01','1853-12-31','gregoriansk',true),
  (-47551,'fact',-47551,'1861','1861-01-01','1861-12-31','gregoriansk',true),
  (-47561,'fact',-47561,'12 marts 1702','1702-01-01','1702-12-31','gregoriansk',true),
  (-47571,'fact',-47571,'1870','1870-01-01','1870-12-31','gregoriansk',true),
  (-47591,'fact',-47591,'1880','1880-01-01','1880-12-31','gregoriansk',true);
INSERT INTO conclusion(target_type,target_id,valgt_assertion_id)
  SELECT 'fact',id,id FROM fact WHERE id BETWEEN -47591 AND -47511;
INSERT INTO citation(assertion_id,source_id)
  SELECT id,-4750 FROM assertion WHERE id BETWEEN -47591 AND -47511;
INSERT INTO citation(assertion_id,source_id) VALUES (-47591,-4749);
INSERT INTO private.interpretation(id,interpretation_key,version,source_id,source_persona_id,interpretation_kind,
  predicate,value,schema_version,derivation_kind,confidence,status,method,extraction_run_id)
  SELECT ('c4750000-0000-4000-8000-0000000003'||nn)::uuid,('c4750000-0000-4000-8000-0000000004'||nn)::uuid,1,-4750,
         ('c4750000-0000-4000-8000-00000000010'||left(nn,1))::uuid,'property',pred,to_jsonb(v),'1.0','source_statement',1,
         'proposed','verify','c4750000-0000-4000-8000-0000000000a1'
    FROM (VALUES ('11','person.death','1850'),('21','person.death','1851'),('31','person.death','1852'),
                 ('41','person.death','1853'),('42','person.name','Dorte Testlow'),('51','person.death','1860'),
                 ('61','person.birth','12. marts 1702'),('71','person.death','1870'),('72','person.title','kammerherre'),
                 ('81','person.name','Hans Testlow'),('91','person.death','1881')) v(nn,pred,v);
INSERT INTO private.interpretation_observation(interpretation_id,observation_id,evidence_role,ordinal)
  SELECT id,'c4750000-0000-4000-8000-0000000000a4','supporting',1
    FROM private.interpretation WHERE id::text LIKE 'c4750000-%';
COMMIT;
SQL

# export <db> <ud-klassifikation> <ud-rækker>: læse-kun, med kildescope.
export_json() {
  { echo "BEGIN READ ONLY;"; echo "SELECT set_config('daa.control_src','$SRC',true) \\g /dev/null";
    echo "\\o /dev/null"; echo "\\i $S/interpretation_control_classification.sql"; echo "\\o";
    echo "SELECT current_setting('daa.control_result');"; echo "ROLLBACK;"; } > "$T/k.sql"
  q -A -t -d "$1" -f "$T/k.sql" > "$2"
  { echo "BEGIN READ ONLY;"; echo "SELECT set_config('daa.control_src','$SRC',true) \\g /dev/null";
    echo "\\i $S/interpretation_control_rows.sql"; echo "ROLLBACK;"; } > "$T/r.sql"
  q -A -t -d "$1" -f "$T/r.sql" > "$3"
}

# fill <ark> <ud> <tok-par …>: "NN=TOK" sætter F-linjen for forslag NN, "pN=TOK" P-linjen for persona N.
fill() {
  local src="$1" dst="$2"; shift 2
  cp "$src" "$dst"
  for kv in "$@"; do
    local k="${kv%%=*}" v="${kv#*=}"
    case "$k" in
      p*) sed -i.bak "s/^P $(pid "${k#p}") \([0-9]*\) : -\$/P $(pid "${k#p}") \1 : $v/" "$dst" ;;
      *)  sed -i.bak "s/^F $(iid "$k") \([0-9]*\) : _\$/F $(iid "$k") \1 : $v/" "$dst" ;;
    esac
  done
  rm -f "$dst.bak"
}
sha() { "$PY" -c 'import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$1"; }

# plan_in <db> <mappe>: eksport + plan (stratum 1: 1, øvrige: 0 — deterministisk stikprøve = forslag 11) + tomt ark.
plan_in() {
  export_json "$1" "$T/k.json" "$T/r.json"
  rm -rf "$2"
  cm plan --classification "$T/k.json" --rows "$T/r.json" --source-id "$SRC" \
     --strata-ubekraeftet 1 --strata-oevrige 0 --out-dir "$2" >/dev/null
  cm ark --plan-dir "$2" --out "$2/tomt.txt" >/dev/null
}

expect_sql_error() {   # <db> <sql-fil> <kode>
  if q -d "$1" -v actor="$A" -f "$2" >"$T/out.txt" 2>"$T/err.txt"; then die "$3 forventet, men SQL'en lykkedes"; fi
  grep -q "$3" "$T/err.txt" || die "$3 forventet; fik $(grep -o 'ERROR: *[A-Z_]*' "$T/err.txt" | head -1)"
}

# ---------------------------------------------------------------------------------------------------------------------
# 1. Hovedvejen.
newdb; MAIN=$DB
q -d "$MAIN" -f "$T/fixture.sql" >/dev/null
plan_in "$MAIN" "$T/plan"
"$PY" - "$T/plan/plan.json" "$T/plan/rows-kontrol.json" "$(iid 42)" "$(iid 91)" <<'PY' || die "planen"
import json, sys
meta = json.load(open(sys.argv[1])); rows = {r["interpretation_id"]: r for r in json.load(open(sys.argv[2]))}
assert meta["sample_ids"] == ["c4750000-0000-4000-8000-000000000311"], meta["sample_ids"]
assert meta["strata"]["ubekraeftet"]["trukket"] == 1 and meta["strata"]["opfyldt_fra_andet"] == 0
assert meta["counts"]["MATCH"] == 5 and meta["counts"]["REAL_DIFF"] == 5 and meta["counts"]["SKRIVEMAADE"] == 1
m42 = rows[sys.argv[3]]["rettelse_maal"]
assert m42 == {"assertion_id": -47542, "forventet": {"fact_id": -47542, "faktatype": "navn",
               "vaerdi_tekst": "Dorthe Testlow", "date_raw": None, "valgt_assertion_id": -47542,
               "citation_sources": [-4750]}}, m42
assert rows[sys.argv[4]]["rettelse_maal"] is None   # citeret af to kilder: intet entydigt mål
assert rows["c4750000-0000-4000-8000-000000000381"]["navn_forkortes"] is True
PY
echo "OK: plan — stikprøve, klasser og rettelse_maal (entydigt / delt citation)"

# B uden entydigt mål afvises af værktøjet; intet skrives.
fill "$T/plan/tomt.txt" "$T/ark.txt" 11=B 42=B 51=D 61=B 72=D 81=V 91=B
{ cm sql --plan-dir "$T/plan" --sheet "$T/ark.txt" --approved-sha256 "$(sha "$T/ark.txt")" --out "$T/x.sql" || true; } \
  | grep -q "SHEET_V2_LINE_INVALID" || die "B uden entydigt mål"
[ ! -e "$T/x.sql" ] || die "SQL skrevet trods afvisning"
# B på et navn, der forkortes, afvises af værktøjet.
fill "$T/plan/tomt.txt" "$T/ark.txt" 11=B 42=B 51=D 61=B 72=D 81=B 91=D
{ cm sql --plan-dir "$T/plan" --sheet "$T/ark.txt" --approved-sha256 "$(sha "$T/ark.txt")" --out "$T/x.sql" || true; } \
  | grep -q "SHEET_V2_LINE_INVALID" || die "B på navn_forkortes"
# SAMPLE_FAILED: D på stikprøvefeltet — ingen SQL.
fill "$T/plan/tomt.txt" "$T/ark.txt" 11=D 42=B 51=D 61=B 72=D 81=V 91=D
{ cm sql --plan-dir "$T/plan" --sheet "$T/ark.txt" --approved-sha256 "$(sha "$T/ark.txt")" --out "$T/x.sql" || true; } \
  | grep -q "SAMPLE_FAILED" || die "SAMPLE_FAILED"
[ ! -e "$T/x.sql" ] || die "SQL skrevet trods SAMPLE_FAILED"
echo "OK: værktøjet afviser B uden mål, B på navn_forkortes og en fejlet stikprøve uden at skrive SQL"

fill "$T/plan/tomt.txt" "$T/ark.txt" "11=B" "42=B # bogen" 51=D 61=B 72=D "81=V # usikker" 91=D "p7=P -4760"
SHA=$(sha "$T/ark.txt")
cm sql --plan-dir "$T/plan" --sheet "$T/ark.txt" --approved-sha256 "$SHA" --out "$T/ud.sql" >/dev/null
cm verify-sql --plan-dir "$T/plan" --sheet "$T/ark.txt" --approved-sha256 "$SHA" --out "$T/verify.sql" >/dev/null
q -d "$MAIN" -v actor="$A" -f "$T/ud.sql" > "$T/out.txt"
grep -q "CONTROL_V2_OK unresolved=1 rettelser=2 afgoerelser=5 stikproeve=1 maskine=3 bundet=6" "$T/out.txt" \
  || die "ceremonien: $(grep -o 'CONTROL_V2_OK.*' "$T/out.txt")"
q -d "$MAIN" -f "$T/verify.sql" 2>&1 | grep -q "CONTROL_V2_VERIFY_OK bundet=6 p_personas=1" || die "verify-sql"
cat > "$T/check.sql" <<'SQL'
DO $$
DECLARE n int; x record;
BEGIN
  -- Rettelserne: samme påstands-id, ny værdi = forslagets, hver i sit eget change_set.
  IF (SELECT vaerdi_tekst FROM assertion WHERE id=-47542) IS DISTINCT FROM 'Dorte Testlow' THEN RAISE EXCEPTION 'FEJL: navn'; END IF;
  SELECT date_raw,date_min,date_max,date_qualifier INTO x FROM assertion WHERE id=-47561;
  IF x.date_raw IS DISTINCT FROM '12. marts 1702' OR x.date_min IS DISTINCT FROM '1702-03-12'::date
     OR x.date_max IS DISTINCT FROM '1702-03-12'::date OR x.date_qualifier IS NOT NULL THEN RAISE EXCEPTION 'FEJL: dato %',x; END IF;
  SELECT count(*) INTO n FROM paastand_korrektion WHERE assertion_id IN (-47542,-47561) AND grund='bogen_har_ret';
  IF n<>2 THEN RAISE EXCEPTION 'FEJL: korrektioner %',n; END IF;
  IF (SELECT count(DISTINCT change_set_id) FROM paastand_korrektion WHERE assertion_id IN (-47542,-47561))<>2 THEN
    RAISE EXCEPTION 'FEJL: rettelserne deler change_set'; END IF;
  -- Afgørelserne.
  IF (SELECT status||' '||(decision_evidence->>'grund') FROM private.interpretation_current
       WHERE interpretation_key='c4750000-0000-4000-8000-000000000451') IS DISTINCT FROM 'rejected database_har_ret'
     OR (SELECT status FROM private.interpretation_current WHERE interpretation_key='c4750000-0000-4000-8000-000000000481')
        IS DISTINCT FROM 'unresolved'
     OR (SELECT status FROM private.interpretation_current WHERE interpretation_key='c4750000-0000-4000-8000-000000000491')
        IS DISTINCT FROM 'rejected' THEN
    RAISE EXCEPTION 'FEJL: afgørelser';
  END IF;
  IF (SELECT decision_evidence->>'method' FROM private.interpretation_current
       WHERE interpretation_key='c4750000-0000-4000-8000-000000000421') IS DISTINCT FROM 'machine-corroboration-v2'
     OR (SELECT decision_evidence->>'method' FROM private.interpretation_current
          WHERE interpretation_key='c4750000-0000-4000-8000-000000000411') IS DISTINCT FROM 'human-sheet-kontrol-v2' THEN
    RAISE EXCEPTION 'FEJL: metoder';
  END IF;
  -- P: identiteten er uafklaret med den faste note og kortkvitteringen; personaens forslag er urørte.
  SELECT decision_status,evidence INTO x FROM private.source_persona_identity
   WHERE source_persona_id='c4750000-0000-4000-8000-000000000107';
  IF x.decision_status<>'unresolved' OR x.evidence->>'note' IS DISTINCT FROM 'ønsket_person_id=-4760; grund=forkert person'
     OR x.evidence->>'basis' IS DISTINCT FROM 'human_sheet' OR x.evidence->>'line' IS NULL THEN
    RAISE EXCEPTION 'FEJL: P %',x;
  END IF;
  IF EXISTS (SELECT 1 FROM private.interpretation_current WHERE source_persona_id='c4750000-0000-4000-8000-000000000107'
              AND status<>'proposed') THEN RAISE EXCEPTION 'FEJL: P-personaens forslag er afgjort'; END IF;
  -- Bindingerne: præcis de seks.
  SELECT count(*) INTO n FROM private.interpretation_promotion p JOIN private.interpretation i ON i.id=p.interpretation_id
   WHERE i.source_id=-4750 AND private.assertion_binding_current(p.id);
  IF n<>6 THEN RAISE EXCEPTION 'FEJL: bindinger %',n; END IF;
  RAISE NOTICE 'OK: kontrolværktøjet v2 — P, rettelser, afgørelser, stikprøve, maskine og binding';
END $$;
SQL
q -d "$MAIN" -f "$T/check.sql" 2>&1 | grep -q "OK: kontrolværktøjet v2" || { q -d "$MAIN" -f "$T/check.sql"; die "tilstand"; }
echo "OK: hovedvejen — CONTROL_V2_OK og CONTROL_V2_VERIFY_OK, 2 rettelser i hvert sit change_set, 6 bindinger"

# Samme SQL igen: afvises (versionerne er brugt), intet ændres.
expect_sql_error "$MAIN" "$T/ud.sql" "ERROR"
echo "OK: genkørsel afvises"

# ---------------------------------------------------------------------------------------------------------------------
# 2. Værnene før identitetskaldet (rulles tilbage; personaen forbliver accepteret).
newdb; NEG=$DB
q -d "$NEG" -f "$T/fixture.sql" >/dev/null
plan_in "$NEG" "$T/plan2"
fill "$T/plan2/tomt.txt" "$T/ark.txt" 11=B 42=D 51=D 61=D 72=D 81=V 91=D "p7=P -99999"
cm sql --plan-dir "$T/plan2" --sheet "$T/ark.txt" --approved-sha256 "$(sha "$T/ark.txt")" --out "$T/n1.sql" >/dev/null
expect_sql_error "$NEG" "$T/n1.sql" "SHEET_V2_LINE_INVALID line=[0-9]* person=-99999 findes ikke"
fill "$T/plan2/tomt.txt" "$T/ark.txt" 11=B 42=D 51=D 61=D 72=D 81=V 91=D "p7=P -4757"
cm sql --plan-dir "$T/plan2" --sheet "$T/ark.txt" --approved-sha256 "$(sha "$T/ark.txt")" --out "$T/n2.sql" >/dev/null
expect_sql_error "$NEG" "$T/n2.sql" "SHEET_V2_LINE_INVALID line=[0-9]* person=-4757 er personaens nuværende"
# Persona 7's MATCH (71) accepteres og bindes uden for kontrollen; P på personaen afvises derefter.
cat > "$T/bind71.sql" <<'SQL'
BEGIN;
SELECT set_config('request.jwt.claim.sub', :'actor', true) \g /dev/null
SET LOCAL ROLE authenticated;
SELECT red_decide_interpretation('c4750000-0000-4000-8000-000000000371',1,'accepted','{"basis":"kontrolv2"}') \g /dev/null
RESET ROLE;
SELECT set_config('t7.items', jsonb_build_array(jsonb_build_object('interpretation_id',
    (SELECT id FROM private.interpretation_current WHERE interpretation_key='c4750000-0000-4000-8000-000000000471'),
    'target_type','assertion','target_id',-47571))::text, true) \g /dev/null
SET LOCAL ROLE authenticated;
DO $$ DECLARE items jsonb := current_setting('t7.items')::jsonb; p jsonb; BEGIN
  p := red_preview_interpretation_promotions(items);
  PERFORM red_promote_interpretations_batch(items,p->>'preview_hash');
END $$;
COMMIT;
SQL
q -d "$NEG" -v actor="$A" -f "$T/bind71.sql" >/dev/null 2>&1 || die "fixturens binding af 71"
plan_in "$NEG" "$T/plan3"
fill "$T/plan3/tomt.txt" "$T/ark.txt" 11=B 42=D 51=D 61=D 72=D 81=V 91=D "p7=P"
cm sql --plan-dir "$T/plan3" --sheet "$T/ark.txt" --approved-sha256 "$(sha "$T/ark.txt")" --out "$T/n3.sql" >/dev/null
expect_sql_error "$NEG" "$T/n3.sql" "PERSONA_HAR_PROMOTIONER"
q -d "$NEG" -A -t -c "SELECT decision_status||' '||version FROM private.source_persona_identity
                      WHERE source_persona_id='c4750000-0000-4000-8000-000000000107'" | grep -qx "accepted 1" \
  || die "personaen blev ændret trods afvisning"
q -d "$NEG" -A -t -c "SELECT count(*) FROM private.interpretation_current WHERE source_id=-4750 AND status<>'proposed'" \
  | grep -qx "1" || die "afgørelser skrevet trods afvisning"
echo "OK: værnene — ukendt person, nuværende person og PERSONA_HAR_PROMOTIONER afvises før identitetskaldet; intet skrevet"
