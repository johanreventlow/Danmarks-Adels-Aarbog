#!/usr/bin/env bash
# Trin 6d-3 Task 7: D- og O-ceremonien (samme_som_kort_ceremoni.sql, privat_kort_ceremoni.sql) ende-til-ende på en
# syntetisk mini-kilde (fixtures/ceremoni-6d3.sql). Manifest og svarfil bygges af en lille Python-hjælper som kanonisk
# JSON + "\n" (samme form som det private kortværktøj); kortenes tekst-sha beregnes i Python af fixturens tekster, så
# SQL'ens genberegning efterprøves uafhængigt. Negative scenarier skriver intet og køres på basen selv eller på
# skabelonkopier (når de kræver en ændret base). Scriptet dropper aldrig databaser.
# Brug: bash tests/sql/test-samme-som-kort-ceremoni.sh <basenavn>   (opretter <basenavn> og <basenavn>_go/_alias/_tekst/_tvilling)
set -euo pipefail
db=${1:?database}
S=.claude/skills/daa-extract/scripts
F=tests/sql/fixtures
tmp=$(mktemp -d "/tmp/${db}.XXXXXX"); [ -n "${KEEP_TMP:-}" ] || trap 'rm -rf "$tmp"' EXIT
q() { env -u PGOPTIONS psql -X -q -v ON_ERROR_STOP=1 "$@"; }
v() { env -u PGOPTIONS psql -X -At -v ON_ERROR_STOP=1 -d "$1" -c "$2"; }
fail() { echo "SAMME_SOM_KORT_CEREMONI_TEST_FAILED: $*" >&2; exit 1; }
sha() { shasum -a 256 "$1" | cut -c1-64; }
ACTOR=a1500000-0000-0000-0000-000000000150
FAMILIER=-6321,-6322

createdb "$db"
for f in tests/sql/evidence-promotion-bootstrap.sql schema.sql db-rls.sql; do
  q -d "$db" -f "$f" >/dev/null 2>&1 || fail "opsætning: $f"; done
(cd $F && q -d "$db" -f ceremoni-6d3.sql >/dev/null 2>&1) || fail "opsætning: fixtures/ceremoni-6d3.sql"

# kort.py manifest <ud> [variant]  |  kort.py svar <manifest> <ud> <D01> <D02> <O1> [manifest_sha]
cat > "$tmp/kort.py" <<'PY'
import hashlib, json, sys

def canon(o):
    return json.dumps(o, ensure_ascii=False, sort_keys=True, separators=(",", ":"))

def tsha(o):
    return hashlib.sha256(canon(o).encode("utf-8")).hexdigest()

def write(path, o):
    with open(path, "w", encoding="utf-8", newline="") as fh:
        fh.write(canon(o) + "\n")

# Fixturens tekster (fixtures/ceremoni-6d3.sql), ordret.
D01_TEKST = {"klausuler": ["Gift med Åse Ørsted, datter af »Bo«."],
             "narrativ": 'Opdigtet biografi om hovedperson Ét – født på Ærø.\nAnden linje med "citat" og \\.'}
D02_TEKST = {"klausuler": ['g. 2° m. Else "Lille" Bøg\\Hansen.'], "narrativ": None}
O1_TEKST = {"narrativ": "Opdigtet levn (22 tegn)."}

def d(kort, fid, h, hk, alias, objekter, tekst):
    return {"kort": kort, "handling": "samme_som", "family_id_1939": fid, "hovedperson_id": h, "hovedperson_kanonisk": hk,
            "alias_person_id": alias, "mulige_objekter": objekter,
            "forventet_foer": {"alias_samme_som": False, "tvilling_aegtefaeller": objekter},
            "tekst_sha256": tsha(tekst), "svar_tilladt": ["I"] + [f"S {o}" for o in objekter]}

def manifest():
    return {"contract": "trin6d3-kortmanifest-v1", "source_id": -630100,
            "tekst_sha_definition": "sha256 af kanonisk JSON {klausuler, narrativ} — æøå",
            "kort": [d("D01", -6301, -630101, -630201, -630111, [-630216], D01_TEKST),
                     d("D02", -6302, -630102, -630202, -630112, [-630215, -630213], D02_TEKST),
                     {"kort": "O1", "handling": "privat", "person_id": -630150, "forventet_foer": {"privat": False},
                      "tekst_sha256": tsha(O1_TEKST), "svar_tilladt": ["B", "P"]}]}

cmd = sys.argv[1]
if cmd == "manifest":
    write(sys.argv[2], manifest())
elif cmd == "svar":
    msha = sys.argv[7] if len(sys.argv) > 7 else hashlib.sha256(open(sys.argv[2], "rb").read()).hexdigest()
    svar = {k: a for k, a in zip(("D01", "D02", "O1"), sys.argv[4:7]) if a != "-"}
    write(sys.argv[3], {"contract": "trin6d3-kortsvar-v1", "manifest_sha256": msha, "svar": svar,
                        "ompraeget_fra": "test"})
elif cmd == "paritet":
    # Kanonisk JSON: Python-siden af paritetstjekket (SQL-siden er private.reimport_canonical_json_sha256).
    print(tsha(json.loads(sys.argv[2])))
PY
py() { python3 -I "$tmp/kort.py" "$@"; }

# ---- Kanonisk JSON-paritet: SQL-sha = Python-sha for et vanskeligt objekt (non-ASCII, null, escapes, non-BMP) ----
PAR='{"narrativ":null,"klausuler":["Æble ø å °","\"citat\" \\ back","linje\nskift\ttab","kontrol \u0001 og \u001f","ls   ps  ","non-BMP 😀",""],"tal":-630216,"tom":[],"obj":{"z":true,"a":false,"m":null}}'
SQLSHA=$(printf '%s\n' '\encoding UTF8' "SELECT private.reimport_canonical_json_sha256(:'p'::jsonb);" \
  | env -u PGOPTIONS psql -X -At -v ON_ERROR_STOP=1 -d "$db" -v p="$PAR")
PYSHA=$(py paritet "$PAR")
[ "$SQLSHA" = "$PYSHA" ] || fail "kanonisk JSON-paritet: SQL $SQLSHA ≠ Python $PYSHA"

py manifest "$tmp/m.json"
py svar "$tmp/m.json" "$tmp/go.json" "S -630216" "I" "P"
famd5() { v "$1" "SELECT md5(coalesce(string_agg(concat_ws('|',fm.family_id,fm.person_id,fm.rolle,
                    coalesce(fm.ordinal::text,'-'),coalesce(fm.konfidens,'-')),E'\n'
                    ORDER BY fm.family_id,fm.person_id,fm.rolle COLLATE \"C\"),''))
                  FROM public.family_member fm WHERE fm.family_id=ANY('{$FAMILIER}'::bigint[])"; }
FMD5=$(famd5 "$db")

# d <base> <mærke>  /  o <base> <mærke>: overstyr med MF= SV= MSHA= SSHA= (og FAM= FMD5X= for O) foran.
d() {
  local mf=${MF:-$tmp/m.json} sv=${SV:-$tmp/go.json}
  env -u PGOPTIONS psql -X -At -v ON_ERROR_STOP=1 -d "$1" -v actor=$ACTOR \
    -v manifest_path="$mf" -v manifest_sha="${MSHA:-$(sha "$mf")}" -v svar_path="$sv" -v svar_sha="${SSHA:-$(sha "$sv")}" \
    -f $S/samme_som_kort_ceremoni.sql > "$tmp/$2.out" 2>&1
}
o() {
  local mf=${MF:-$tmp/m.json} sv=${SV:-$tmp/go.json}
  env -u PGOPTIONS psql -X -At -v ON_ERROR_STOP=1 -d "$1" -v actor=$ACTOR \
    -v manifest_path="$mf" -v manifest_sha="${MSHA:-$(sha "$mf")}" -v svar_path="$sv" -v svar_sha="${SSHA:-$(sha "$sv")}" \
    -v skjul_person=-630160 -v familier="${FAM:-$FAMILIER}" -v familie_md5="${FMD5X:-$FMD5}" \
    -f $S/privat_kort_ceremoni.sql > "$tmp/$2.out" 2>&1
}
kode() { grep -o 'T6D3_[A-Z_0-9]*' "$tmp/$1.out" | head -1; }
state() { v "$1" "SELECT (SELECT count(*) FROM public.relation WHERE rolle='samme_som')||'/'||(SELECT count(*) FROM public.change_set)||'/'||
  (SELECT count(*) FROM public.change_event)||'/'||(SELECT count(*) FROM public.person WHERE privat)"; }
nej() {  # nej <d|o> <base> <mærke> <kode>: afvist med koden, intet skrevet
  local fn=$1 b=$2 t=$3 c=$4 s0; s0=$(state "$b")
  if $fn "$b" "$t"; then fail "$t: godtaget, forventede $c"; fi
  grep -q "$c" "$tmp/$t.out" || fail "$t: forventede $c, fik $(kode "$t") $(grep -m1 ERROR "$tmp/$t.out" || true)"
  [ "$(state "$b")" = "$s0" ] || fail "$t: afvisningen skrev"
}
for c in go alias tekst tvilling; do createdb -T "$db" "${db}_$c"; done
S0=$(state "$db")

# ---- Negative scenarier på basen ----
MSHA=$(printf '0%.0s' {1..64}) nej d "$db" fejl-manifest-sha T6D3_PRE_SHA
SSHA=$(printf '0%.0s' {1..64}) nej d "$db" fejl-svar-sha T6D3_PRE_SHA
py svar "$tmp/m.json" "$tmp/fremmed.json" "S -630216" "I" "P" "$(printf '1%.0s' {1..64})"
SV="$tmp/fremmed.json" nej d "$db" svar-andet-manifest T6D3_PRE_SHA
py svar "$tmp/m.json" "$tmp/uden.json" "S -630216" "I" "-"
SV="$tmp/uden.json" nej d "$db" svar-mangler T6D3_PRE_SVAR
py svar "$tmp/m.json" "$tmp/udenfor.json" "S -630215" "I" "P"
SV="$tmp/udenfor.json" nej d "$db" svar-uden-for-tilladt T6D3_PRE_SVAR
python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1],encoding="utf-8")); d["svar"]["D09"]="I"
open(sys.argv[2],"w",encoding="utf-8").write(json.dumps(d,ensure_ascii=False)+"\n")' "$tmp/go.json" "$tmp/ekstra.json"
SV="$tmp/ekstra.json" nej d "$db" svar-ukendt-kort T6D3_PRE_SVAR
nej o "$db" o-foer-d T6D3_PRE_FASE
[ "$(state "$db")" = "$S0" ] || fail "basen er ændret af de negative scenarier"

# ---- Drift mellem kort og ceremoni: intet skrevet for NOGET kort ----
# Aliaset har fået en samme_som (her mod et af de mulige objekter) → D01 afvises.
q -d "${db}_alias" -c "INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle) VALUES ('person',-630111,'person',-630216,'samme_som')" >/dev/null
nej d "${db}_alias" alias T6D3_PRE_MANIFEST
grep -q 'kort D01 (alias)' "$tmp/alias.out" || fail "alias: årsag $(grep -m1 ERROR "$tmp/alias.out")"
# D02's klausul (ægteskab nr. 2) har ændret tekst → D02 afvises, og D01's S skrives heller ikke.
q -d "${db}_tekst" -c "SET session_replication_role=replica" \
  -c "UPDATE private.source_observation SET verbatim_text=replace(verbatim_text,'Lille','Store') WHERE verbatim_text LIKE 'g. 2° m. Else%'" >/dev/null
nej d "${db}_tekst" tekst T6D3_PRE_MANIFEST
grep -q 'kort D02 (tekst)' "$tmp/tekst.out" || fail "tekst: årsag $(grep -m1 ERROR "$tmp/tekst.out")"
! grep -q 'D01' "$tmp/tekst.out" || fail "tekst: D01 nævnt"
[ "$(v "${db}_tekst" "SELECT count(*) FROM public.relation WHERE rolle='samme_som' AND subjekt_id=-630111")" = 0 ] || fail "tekst: D01 skrevet"
# D02's tvilling har fået en ekstra ægtefælle → D02 afvises.
q -d "${db}_tvilling" -c "INSERT INTO public.person(id,levende,privat) VALUES (-630214,false,false)" \
  -c "INSERT INTO public.family(id,type) VALUES (-6314,'vielse')" \
  -c "INSERT INTO public.family_member(family_id,person_id,rolle,ordinal) VALUES (-6314,-630202,'partner',3),(-6314,-630214,'partner',3)" >/dev/null
nej d "${db}_tvilling" tvilling T6D3_PRE_MANIFEST
grep -q 'kort D02 (tvilling)' "$tmp/tvilling.out" || fail "tvilling: årsag $(grep -m1 ERROR "$tmp/tvilling.out")"

# ---- D: S → link med 1939-ægtefællen som alias; I → intet ----
d "${db}_go" go || fail "go: $(kode go) $(grep -m1 ERROR "$tmp/go.out" || true)"
[ "$(wc -l < "$tmp/go.out" | tr -d ' ')" = 2 ] || fail "go: uddata $(cat "$tmp/go.out")"
grep -Eqx 'T6D3_D_PAR kort=D01 relation=[0-9]+ alias=-630111 objekt=-630216 retning=alias_objekt foer=0 change_set=[0-9]+' "$tmp/go.out" \
  || fail "go: parlinje $(head -1 "$tmp/go.out")"
[ "$(tail -1 "$tmp/go.out")" = 'T6D3_D_OK links=1 ingen=1' ] || fail "go: OK-linje $(tail -1 "$tmp/go.out")"
REL=$(sed -n 's/.* relation=\([0-9]*\) .*/\1/p' "$tmp/go.out"); CS=$(sed -n 's/.* change_set=\([0-9]*\)$/\1/p' "$tmp/go.out")
[ "$(v "${db}_go" "SELECT subjekt_id||'>'||objekt_id FROM public.relation WHERE id=$REL AND rolle='samme_som'")" = "-630111>-630216" ] \
  || fail "go: retning"
[ "$(v "${db}_go" "SELECT operation FROM public.change_set WHERE id=$CS")" = red_samme_som ] || fail "go: parrets change_set"
[ "$(v "${db}_go" "SELECT count(*) FROM public.relation WHERE rolle='samme_som' AND (subjekt_id=-630112 OR objekt_id=-630112)")" = 0 ] \
  || fail "go: I skrev"
[ "$(v "${db}_go" "SELECT count(*) FROM public.change_set WHERE operation='samme_som_kort_ceremoni' AND subjekt_type='source' AND subjekt_id=-630100")" = 2 ] \
  || fail "go: kvitteringer"
[ "$(v "${db}_go" "SELECT count(*) FROM public.change_event e JOIN public.change_set c ON c.id=e.change_set_id WHERE c.operation='samme_som_kort_ceremoni'")" = 0 ] \
  || fail "go: kvitteringen har hændelser"
nej d "${db}_go" go-igen T6D3_PRE_FASE

# ---- O: skjult person og O1 (P) sat privat; familierne skjult; genkørsel stoppes ----
FMD5X=$(printf '0%.0s' {1..32}) nej o "${db}_go" o-familie-md5 T6D3_PRE_MANIFEST
grep -q "familier (beregnet $FMD5)" "$tmp/o-familie-md5.out" || fail "o-familie-md5: årsag"
o "${db}_go" o || fail "o: $(kode o) $(grep -m1 ERROR "$tmp/o.out" || true)"
[ "$(cat "$tmp/o.out")" = 'T6D3_O_OK privat=2' ] || fail "o: uddata $(cat "$tmp/o.out")"
[ "$(v "${db}_go" "SELECT string_agg(id::text,',' ORDER BY id) FROM public.person WHERE privat")" = "-630160,-630150" ] || fail "o: privat"
[ "$(v "${db}_go" "SELECT bool_or(public.family_offentlig(f)) FROM unnest('{$FAMILIER}'::bigint[]) f")" = f ] || fail "o: familie offentlig"
[ "$(v "${db}_go" "SELECT public.family_offentlig(-6301)")" = t ] || fail "o: anden familie skjult"
nej o "${db}_go" o-igen T6D3_PRE_FASE
echo SAMME_SOM_KORT_CEREMONI_TEST_OK
