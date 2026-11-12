#!/usr/bin/env bash
# Trin 6c-2 Task 7: kontrolværktøjet v2 ende-til-ende på en syntetisk fixtur.
# Eksport med kildescope → plan → tomt ark → udfyldt ark → sql → psql → verify-sql → psql, og de afviste veje:
# P <person> der ikke findes, P <personaens nuværende person> og PERSONA_HAR_PROMOTIONER (SQL-sidens værn, før
# identitetskaldet), B uden entydigt mål og SAMPLE_FAILED (værktøjet skriver ingen SQL), og saboterede ceremonier
# (verifikationen før COMMIT og rettelsesmålet i bindingen afviser; intet committes). En note med ', \, $v$ og :actor
# går byte-ens gennem psql.
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
-- p4 har også navnet fra den anden kilde (samme faktum, databasens gamle værdi): rettelsens mål er stadig -47542, og
-- efter rettelsen skal bindingen ramme -47542, ikke -47543.
INSERT INTO assertion(id,target_type,target_id,vaerdi_tekst,calendar,uforanderlig) VALUES
  (-47543,'fact',-47542,'Dorthe Testlow','gregoriansk',true);
INSERT INTO citation(assertion_id,source_id) VALUES (-47543,-4749);
-- Og et længere navn fra den anden kilde, som indeholder forslaget 'Dorte Testlow' (slutreview fix C): det er ikke
-- rettelsens mål, så navn_forkortes vurderes mod -47542 alene og er falsk (som red_ret_paastand's port).
INSERT INTO assertion(id,target_type,target_id,vaerdi_tekst,calendar,uforanderlig) VALUES
  (-47544,'fact',-47542,'Dorte Testlow til Testholm','gregoriansk',true);
INSERT INTO citation(assertion_id,source_id) VALUES (-47544,-4749);
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
      p*) sed -i.bak "s/^P $(pid "${k#p}") \([0-9]*\) : _\$/P $(pid "${k#p}") \1 : $v/" "$dst" ;;
      *)  sed -i.bak "s/^F $(iid "$k") \([0-9]*\) : _\$/F $(iid "$k") \1 : $v/" "$dst" ;;
    esac
  done
  sed -i.bak 's/^\(P [^ ]* [0-9]*\) : _$/\1 : -/' "$dst"   # personas uden svar: rigtig person
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
               "citation_sources": [-4750]},
               "graenser": {"date_min": None, "date_max": None, "date_qualifier": None}}, m42
assert rows[sys.argv[4]]["rettelse_maal"] is None   # citeret af to kilder: intet entydigt mål
assert rows["c4750000-0000-4000-8000-000000000381"]["navn_forkortes"] is True   # forkorter sit eget mål
assert rows[sys.argv[3]]["navn_forkortes"] is False   # målet forkortes ikke; den anden kildes længere navn tæller ikke
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

fill "$T/plan/tomt.txt" "$T/ark.txt" "11=B" "42=B # bogen" 51=D 61=B 72=D 81=V 91=D "p7=P -4760"
# Noten på 81 har ', \, $v$ og :actor; den skal stå byte-ens i evidensen efter psql.
"$PY" - "$T/ark.txt" "$(iid 81)" <<'PY'
import sys
path, i = sys.argv[1], sys.argv[2]
note = "it's a \\ back $v$ dollar :actor colon"
lines = open(path, encoding="utf-8").read().split("\n")
n = [k for k, x in enumerate(lines) if x.startswith(f"F {i} ") and x.endswith(" : V")]
assert len(n) == 1
lines[n[0]] += f" # {note}"
open(path, "w", encoding="utf-8").write("\n".join(lines))
PY
SHA=$(sha "$T/ark.txt")
cm sql --plan-dir "$T/plan" --sheet "$T/ark.txt" --approved-sha256 "$SHA" --out "$T/ud.sql" > "$T/sqlok.txt"
grep -q "datorettelser_graenser_aendret=1 " "$T/sqlok.txt" || die "datorettelser_graenser_aendret"
cm verify-sql --plan-dir "$T/plan" --sheet "$T/ark.txt" --approved-sha256 "$SHA" --out "$T/verify.sql" >/dev/null
q -d "$MAIN" -v actor="$A" -f "$T/ud.sql" > "$T/out.txt" 2> "$T/err.txt"
grep -q "CONTROL_V2_VERIFY_OK bundet=6 p_personas=1" "$T/err.txt" || die "verifikationen i transaktionen"
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
  -- Noten med ', \, $v$ og :actor er byte-ens efter psql.
  IF (SELECT decision_evidence->>'note' FROM private.interpretation_current
       WHERE interpretation_key='c4750000-0000-4000-8000-000000000481')
     IS DISTINCT FROM $q$it's a \ back $v$ dollar :actor colon$q$ THEN
    RAISE EXCEPTION 'FEJL: noten er ikke byte-ens';
  END IF;
  -- Det rettede navn er bundet til den rettede påstand, ikke til den anden kildes påstand på samme faktum.
  IF (SELECT array_agg(p.target_id) FROM private.interpretation_promotion p JOIN private.interpretation i
        ON i.id=p.interpretation_id WHERE i.interpretation_key='c4750000-0000-4000-8000-000000000442'
       AND private.assertion_binding_current(p.id)) IS DISTINCT FROM ARRAY[-47542::bigint] THEN
    RAISE EXCEPTION 'FEJL: rettelsens binding';
  END IF;
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
# Saboterede ceremonier (rulles tilbage): verifikationen før COMMIT forventer ét bundet forslag for lidt, og
# rettelsesmålet i bindingsporten peger på den anden kildes påstand.
fill "$T/plan2/tomt.txt" "$T/ark.txt" 11=B 42=B 51=D 61=B 72=D 81=V 91=D
"$PY" - "$S" "$T/plan2" "$T/ark.txt" "$T/s1.sql" "$T/s2.sql" <<'PY'
import hashlib, sys
from pathlib import Path
sys.path.insert(0, sys.argv[1])
import control_model_v2 as v2
plan, meta = v2._load_plan(Path(sys.argv[2]))
data = Path(sys.argv[3]).read_bytes()
a = v2.apply_plan_v2(plan, data.decode("utf-8"), sheet_sha256=hashlib.sha256(data).hexdigest(), hashes=meta)
sql = v2.sql_v2(plan, a)
blok = v2._verify_do(plan, a)
assert sql.count(blok) == 1 and len(a["rettelser"]) == 2
Path(sys.argv[4]).write_text(sql.replace(blok, v2._verify_do(plan, dict(a, rettelser=a["rettelser"][1:]))))
kort = v2._lit(v2._rettelse_map(a))
assert sql.count(kort) == 1 and "-47542" in kort
Path(sys.argv[5]).write_text(sql.replace(kort, kort.replace("-47542", "-47543")))
PY
expect_sql_error "$NEG" "$T/s1.sql" "CONTROL_V2_PROMOTION_MISMATCH"
expect_sql_error "$NEG" "$T/s2.sql" "CONTROL_V2_RETTELSE_MAAL_MISMATCH"
q -d "$NEG" -A -t -c "SELECT (SELECT count(*) FROM private.interpretation_current WHERE source_id=-4750 AND status<>'proposed')
                      || ' ' || (SELECT count(*) FROM paastand_korrektion) || ' ' || (SELECT vaerdi_tekst FROM assertion WHERE id=-47542)
                      || ' ' || (SELECT decision_status FROM private.source_persona_identity
                                  WHERE source_persona_id='c4750000-0000-4000-8000-000000000107')" \
  | grep -qx "0 0 Dorthe Testlow accepted" || die "en saboteret ceremoni efterlod ændringer"
echo "OK: saboterede ceremonier — verifikationen før COMMIT og rettelsesmålet afviser; intet committet"
# En plan, hvis kilde ikke er forslagenes og personaernes (plan.json's source_id er ikke hash-bundet): kildeværnet
# afviser før første skrivning.
rm -rf "$T/plan2k"; cp -R "$T/plan2" "$T/plan2k"
"$PY" - "$T/plan2k/plan.json" <<'PY'
import json, sys
meta = json.load(open(sys.argv[1])); meta["source_id"] = -4749
json.dump(meta, open(sys.argv[1], "w"))
PY
cm sql --plan-dir "$T/plan2k" --sheet "$T/ark.txt" --approved-sha256 "$(sha "$T/ark.txt")" --out "$T/k1.sql" >/dev/null
expect_sql_error "$NEG" "$T/k1.sql" "PLAN_KILDE_AFVIGER kilde=-4749 forslag=[1-9][0-9]* personas=[1-9][0-9]*"
q -d "$NEG" -A -t -c "SELECT (SELECT count(*) FROM private.interpretation_current WHERE source_id=-4750 AND status<>'proposed')
                      || ' ' || (SELECT count(*) FROM paastand_korrektion) || ' ' || (SELECT vaerdi_tekst FROM assertion WHERE id=-47542)
                      || ' ' || (SELECT decision_status FROM private.source_persona_identity
                                  WHERE source_persona_id='c4750000-0000-4000-8000-000000000107')" \
  | grep -qx "0 0 Dorthe Testlow accepted" || die "kildeværnet efterlod ændringer"
echo "OK: kildeværnet — en plan med en anden kilde afvises med PLAN_KILDE_AFVIGER; intet skrevet"
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

# ---------------------------------------------------------------------------------------------------------------------
# 3. 2018-20-formen (plan 2026-11-12 Task 4): --predikater person.birth,person.death og --kun-stikproeve. Fixturen får
# to titel-MATCH oveni (22 p2 'kammerjunker', 32 p3 'hofjægermester' = databasens påstand). Kun datoerne planlægges;
# arket bærer kun stikprøven (11); REAL_DIFF/SKRIVEMAADE (51, 61, 91) og alle titler/navne står proposed og ubundne.
cat > "$T/titler.sql" <<'SQL'
BEGIN;
INSERT INTO fact(id,subjekt_type,subjekt_id,faktatype) VALUES (-47522,'person',-4752,'titel'),(-47532,'person',-4753,'titel');
INSERT INTO assertion(id,target_type,target_id,vaerdi_tekst,calendar,uforanderlig) VALUES
  (-47522,'fact',-47522,'kammerjunker','gregoriansk',true),(-47532,'fact',-47532,'hofjægermester','gregoriansk',true);
INSERT INTO conclusion(target_type,target_id,valgt_assertion_id) VALUES ('fact',-47522,-47522),('fact',-47532,-47532);
INSERT INTO citation(assertion_id,source_id) VALUES (-47522,-4750),(-47532,-4750);
INSERT INTO private.interpretation(id,interpretation_key,version,source_id,source_persona_id,interpretation_kind,
  predicate,value,schema_version,derivation_kind,confidence,status,method,extraction_run_id)
  SELECT ('c4750000-0000-4000-8000-0000000003'||nn)::uuid,('c4750000-0000-4000-8000-0000000004'||nn)::uuid,1,-4750,
         ('c4750000-0000-4000-8000-00000000010'||left(nn,1))::uuid,'property','person.title',to_jsonb(v),'1.0',
         'source_statement',1,'proposed','verify','c4750000-0000-4000-8000-0000000000a1'
    FROM (VALUES ('22','kammerjunker'),('32','hofjægermester')) v(nn,v);
INSERT INTO private.interpretation_observation(interpretation_id,observation_id,evidence_role,ordinal)
  VALUES ('c4750000-0000-4000-8000-000000000322','c4750000-0000-4000-8000-0000000000a4','supporting',1),
         ('c4750000-0000-4000-8000-000000000332','c4750000-0000-4000-8000-0000000000a4','supporting',1);
COMMIT;
SQL
newdb; PRD=$DB
q -d "$PRD" -f "$T/fixture.sql" >/dev/null
q -d "$PRD" -f "$T/titler.sql" >/dev/null
export_json "$PRD" "$T/k4.json" "$T/r4.json"
"$PY" - "$T/k4.json" <<'PY' || die "titlerne er ikke MATCH uden prædikatscope"
import json, sys
items = {i["interpretation_id"][-3:]: i for i in json.load(open(sys.argv[1]))["items"]}
assert all(items[n]["class"] == "MATCH" and items[n]["predicate"] == "person.title" for n in ("322", "332")), items
PY
rm -rf "$T/plan4"
cm plan --classification "$T/k4.json" --rows "$T/r4.json" --source-id "$SRC" --strata-ubekraeftet 1 --strata-oevrige 0 \
   --kun-stikproeve --predikater person.birth,person.death --out-dir "$T/plan4" > "$T/plan4.txt"
grep -q " ark_felter=1 personas=1 praedikater=person.birth,person.death udeladt=3$" "$T/plan4.txt" \
  || die "planen med flagene: $(head -1 "$T/plan4.txt" | grep -o 'ark_felter=.*')"
"$PY" - "$T/plan4/plan.json" <<'PY' || die "planen med flagene"
import json, sys
m = json.load(open(sys.argv[1]))
k = lambda ids: sorted(i[-2:] for i in ids)
assert m["kun_stikproeve"] is True and m["predikater"] == ["person.birth", "person.death"]
assert k(m["sample_ids"]) == ["11"] and k(x[0] for x in m["match"]) == ["11", "21", "31", "41", "71"]
assert k(m["real_diff_ids"]) == ["51", "91"] and k(m["skrivemaade_ids"]) == ["61"]
assert k(m["universe_ids"]) == ["11", "21", "31", "41", "51", "61", "71", "91"]
PY
cm ark --plan-dir "$T/plan4" --out "$T/plan4/tomt.txt" >/dev/null
[ "$(grep -c '^F ' "$T/plan4/tomt.txt")" = 1 ] || die "arket bærer mere end stikprøven"
fill "$T/plan4/tomt.txt" "$T/ark4.txt" 11=B
SHA=$(sha "$T/ark4.txt")
# Prædikatværnet i databasen: en plan.json med et smallere scope (kun død) end planens forslag (61 er en fødsel)
# afvises før første skrivning.
rm -rf "$T/plan4p"; cp -R "$T/plan4" "$T/plan4p"
"$PY" - "$T/plan4p/plan.json" <<'PY'
import json, sys
meta = json.load(open(sys.argv[1])); meta["predikater"] = ["person.death"]
json.dump(meta, open(sys.argv[1], "w"))
PY
cm sql --plan-dir "$T/plan4p" --sheet "$T/ark4.txt" --approved-sha256 "$SHA" --out "$T/p1.sql" >/dev/null
expect_sql_error "$PRD" "$T/p1.sql" "PLAN_PRAEDIKAT_AFVIGER forslag=1"
q -d "$PRD" -A -t -c "SELECT count(*) FROM private.interpretation_current WHERE source_id=-4750 AND status<>'proposed'" \
  | grep -qx "0" || die "prædikatværnet efterlod ændringer"
echo "OK: prædikatværnet — en plan med et smallere scope end sine forslag afvises; intet skrevet"
cm sql --plan-dir "$T/plan4" --sheet "$T/ark4.txt" --approved-sha256 "$SHA" --out "$T/ud4.sql" >/dev/null
cm verify-sql --plan-dir "$T/plan4" --sheet "$T/ark4.txt" --approved-sha256 "$SHA" --out "$T/verify4.sql" >/dev/null
q -d "$PRD" -v actor="$A" -f "$T/ud4.sql" > "$T/out.txt" 2> "$T/err.txt"
grep -q "CONTROL_V2_VERIFY_OK bundet=5 p_personas=0 udeladt_proposed=3" "$T/err.txt" || die "verifikationen (flag)"
grep -q "CONTROL_V2_OK unresolved=0 rettelser=0 afgoerelser=0 stikproeve=1 maskine=4 bundet=5" "$T/out.txt" \
  || die "ceremonien (flag): $(grep -o 'CONTROL_V2_OK.*' "$T/out.txt")"
q -d "$PRD" -f "$T/verify4.sql" 2>&1 | grep -q "CONTROL_V2_VERIFY_OK bundet=5 p_personas=0 udeladt_proposed=3" \
  || die "verify-sql (flag)"
cat > "$T/check4.sql" <<'SQL'
DO $$
DECLARE n int; b text[];
BEGIN
  -- Titlerne (to MATCH og en REAL_DIFF), navnene og de udeladte datoer: proposed og ubundne.
  SELECT count(*) INTO n FROM private.interpretation_current ic
   WHERE ic.interpretation_key::text IN ('c4750000-0000-4000-8000-000000000422','c4750000-0000-4000-8000-000000000432',
           'c4750000-0000-4000-8000-000000000472','c4750000-0000-4000-8000-000000000442',
           'c4750000-0000-4000-8000-000000000481','c4750000-0000-4000-8000-000000000451',
           'c4750000-0000-4000-8000-000000000461','c4750000-0000-4000-8000-000000000491')
     AND ic.status = 'proposed'
     AND NOT EXISTS (SELECT 1 FROM private.interpretation_promotion p JOIN private.interpretation i
                      ON i.id = p.interpretation_id WHERE i.interpretation_key = ic.interpretation_key);
  IF n <> 8 THEN RAISE EXCEPTION 'FEJL: urørte %', n; END IF;
  IF EXISTS (SELECT 1 FROM paastand_korrektion) THEN RAISE EXCEPTION 'FEJL: rettelser'; END IF;
  -- Bindingerne: præcis de fem dødsfald (stikprøven 11 + maskinen 21, 31, 41, 71).
  SELECT array_agg(right(i.interpretation_key::text, 2) ORDER BY i.interpretation_key) INTO b
    FROM private.interpretation_promotion p JOIN private.interpretation i ON i.id = p.interpretation_id
   WHERE i.source_id = -4750 AND private.assertion_binding_current(p.id);
  IF b IS DISTINCT FROM ARRAY['11','21','31','41','71'] THEN RAISE EXCEPTION 'FEJL: bindinger %', b; END IF;
  RAISE NOTICE 'OK: kun stikprøven — titler og udeladte urørte';
END $$;
SQL
q -d "$PRD" -f "$T/check4.sql" 2>&1 | grep -q "OK: kun stikprøven" || { q -d "$PRD" -f "$T/check4.sql"; die "tilstand (flag)"; }
echo "OK: --kun-stikproeve --predikater — 1 stikprøve + 4 maskine bundet; 2 titel-MATCH og 3 udeladte proposed og ubundne"
