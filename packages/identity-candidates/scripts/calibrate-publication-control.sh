#!/usr/bin/env bash
# Trin 6b (spec §4.3 pkt. 7, plan Task 10 og Task 15 step 2): hele kalibreringen af publiceringskontrollens controlMargin
# på en DEDIKERET KALIBRERINGSBASE — gitterets hovedkørsler, negativkontrollen, målingen, 5a-sammenligningen og
# årstalsdækningen. Udskriver kun antal og hashes; alle data (id'er, input med navne, kandidater) skrives til --dir
# (mappe 0700, filer 0600), som ingen agent læser.
#
# Negativkontrollen INDSÆTTER kørsler direkte i kørselstabellerne (calibration-negative-insert.sql). Det må aldrig ske i
# prod eller i en ceremoni-stand-in: en ekstra kørsel med samme config gør den rigtige kørsel forældet for
# publication_identity. Kør derfor på en kopi (createdb -T <stand-in> <navn>_cal), aldrig på originalen.
#
# Brug:
#   calibrate-publication-control.sh --db <base> --source <n> [--facit authority:person_external_id|binding]
#     [--dir <mappe>] [--margins "0.02 0.05 0.08 0.10 0.15 0.20"] [--top-k 5] [--bound-source <n>]
#     [--steps main,negative,measure,compare,years] [--jeg-ved-det-er-en-kalibreringsbase]
# Basen skal være lokal (socket eller localhost) og have et navn, der ender på _cal eller rummer _cal_, medmindre
# --jeg-ved-det-er-en-kalibreringsbase er givet. Standard for --dir: ~/.private/kalibrering/<base>.
set -euo pipefail

PKG="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(cd "$PKG/../.." && pwd)"
SQL="$PKG/sql"
TSX="$ROOT/node_modules/.bin/tsx"

DB=""; SOURCE=""; FACIT="authority:person_external_id"; DIR=""; MARGINS="0.02 0.05 0.08 0.10 0.15 0.20"; TOPK=5
BOUND=""; STEPS="main,negative,measure,compare,years"; FORCE_CAL=0
die() { echo "FEJL: $*" >&2; exit 2; }
while [ $# -gt 0 ]; do
  case "$1" in
    --db) DB="${2:-}"; shift 2 ;;
    --source) SOURCE="${2:-}"; shift 2 ;;
    --facit) FACIT="${2:-}"; shift 2 ;;
    --dir) DIR="${2:-}"; shift 2 ;;
    --margins) MARGINS="${2:-}"; shift 2 ;;
    --top-k) TOPK="${2:-}"; shift 2 ;;
    --bound-source) BOUND="${2:-}"; shift 2 ;;
    --steps) STEPS="${2:-}"; shift 2 ;;
    --jeg-ved-det-er-en-kalibreringsbase) FORCE_CAL=1; shift ;;
    *) die "ukendt argument: $1" ;;
  esac
done
[ -n "$DB" ] && [ -n "$SOURCE" ] || die "--db og --source er påkrævet"
[[ "$DB" =~ ^[A-Za-z0-9_]+$ ]] || die "--db skal være et rent basenavn (ingen forbindelsesstreng)"
[[ "$SOURCE" =~ ^[0-9]+$ ]] || die "--source skal være et heltal"
BOUND="${BOUND:-$SOURCE}"; [[ "$BOUND" =~ ^[0-9]+$ ]] || die "--bound-source skal være et heltal"
[[ "$FACIT" =~ ^(authority:[a-z_]+|binding)$ ]] || die "--facit skal være authority:<autoritet> eller binding"
[[ "$TOPK" =~ ^[0-9]+$ ]] && [ "$TOPK" -ge 2 ] || die "--top-k skal være ≥ 2"
for m in $MARGINS; do [[ "$m" =~ ^0\.[0-9]+$ ]] || die "ugyldig gitterværdi: $m"; done
case "${PGHOST:-}" in ""|/*|localhost|127.0.0.1) ;; *) die "PGHOST peger ikke på en lokal server" ;; esac
unset PGDATABASE PGSERVICE
if [ "$FORCE_CAL" -ne 1 ] && ! [[ "$DB" =~ _cal$ || "$DB" =~ _cal_ ]]; then
  die "$DB ligner ikke en kalibreringsbase (navn med _cal); brug en kopi eller --jeg-ved-det-er-en-kalibreringsbase"
fi
[ "$(psql -X -At -d postgres -c "select count(*) from pg_database where datname='$DB'")" = 1 ] || die "basen $DB findes ikke lokalt"

DIR="${DIR:-$HOME/.private/kalibrering/$DB}"
umask 077; mkdir -p "$DIR/neg"; chmod 700 "$DIR" "$DIR/neg"
P() { psql -X -q -At -v ON_ERROR_STOP=1 -d "$DB" "$@"; }
step() { [[ ",$STEPS," == *",$1,"* ]]; }
gen() { "$TSX" "$PKG/src/cli.ts" generate "$@"; }

# Redaktør-aktør til red_*-RPC'erne; uuid'et skrives kun til filen, aldrig til terminalen.
[ -s "$DIR/actor.txt" ] || P -c "select id from public.profiles where rolle='redaktion' order by id limit 1" > "$DIR/actor.txt"
grep -qE '^[0-9a-f-]{36}$' "$DIR/actor.txt" || die "ingen redaktør-aktør i basen"
ACTOR="$(cat "$DIR/actor.txt")"

if step main; then
  P -v source_id="$SOURCE" -v facit="$FACIT" -f "$SQL/export-calibration-truth.sql" > "$DIR/facit.json"
  echo "FACIT personas=$(jq length "$DIR/facit.json") facit=$FACIT"
  PERSONAS="$(jq -r 'map(.source_persona_id)|join(",")' "$DIR/facit.json")"
  [ -n "$PERSONAS" ] || die "facit er tomt"
  P -v source_id="$SOURCE" -v actor="$ACTOR" -v mode=list -v personas="$PERSONAS" -v year_fallback=date_raw-v1 \
    -f "$PKG/sql/export-input.sql" > "$DIR/input-fb.json" 2> "$DIR/input-fb.err"
  P -v source_id="$SOURCE" -v actor="$ACTOR" -v mode=list -v personas="$PERSONAS" \
    -f "$PKG/sql/export-input.sql" > "$DIR/input-nofb.json" 2> "$DIR/input-nofb.err"
  for f in fb nofb; do
    jq -e '.input_sha256|test("^[0-9a-f]{64}$")' "$DIR/input-$f.json" > /dev/null || die "input-$f.json er ikke gyldig"
    echo "INPUT $f input_sha256=$(jq -r .input_sha256 "$DIR/input-$f.json") same_as=$(jq '.input.same_as|length' "$DIR/input-$f.json") date_raw=$(jq '[.input.persons.assertions[]|select(.date_origin=="date_raw")]|length' "$DIR/input-$f.json")"
  done
  for m in $MARGINS; do
    gen --input "$DIR/input-fb.json" --source-id "$SOURCE" --top-k "$TOPK" --control-margin "$m" --out "$DIR/cand-$m.json"
    psql -X -At -v ON_ERROR_STOP=1 -d "$DB" -v actor="$ACTOR" -v cand_file="$DIR/cand-$m.json" \
      -f "$SQL/write-candidates.sql" > "$DIR/reg-$m.log" 2>&1 || die "registrering af $m fejlede (se $DIR/reg-$m.log)"
  done
  gen --input "$DIR/input-nofb.json" --source-id "$SOURCE" --top-k "$TOPK" --out "$DIR/cand-nofb.json"
fi
MAIN="$(jq -r .input_sha256 "$DIR/input-fb.json")"

if step negative; then
  P -v source_id="$SOURCE" -v input_sha256="$MAIN" -v facit="$FACIT" -f "$SQL/calibration-negative-pairs.sql" > "$DIR/pairs.json"
  rm -f "$DIR"/neg/input-b*.json
  "$TSX" "$PKG/src/calibration-cli.ts" split --input "$DIR/input-fb.json" --pairs "$DIR/pairs.json" --out-dir "$DIR/neg"
  for NI in "$DIR"/neg/input-b??.json; do
    b="$(basename "$NI" .json)"; b="${b#input-}"
    H="$(P -v input_file="$DIR/neg/input-$b.inner.json" -f "$SQL/calibration-input-hash.sql")"
    [[ "$H" =~ ^[0-9a-f]{64}$ ]] || die "hash for $b mangler"
    jq --arg h "$H" '.input_sha256=$h' "$NI" > "$NI.tmp" && mv "$NI.tmp" "$NI" && rm -f "$DIR/neg/input-$b.inner.json"
    for m in $MARGINS; do
      gen --input "$NI" --source-id "$SOURCE" --top-k "$TOPK" --control-margin "$m" --out "$DIR/neg/cand-$b-$m.json" \
        >> "$DIR/neg/generate.log"
      P -v kalibreringsbase=ja -v actor="$ACTOR" -v cand_file="$DIR/neg/cand-$b-$m.json" \
        -f "$SQL/calibration-negative-insert.sql" >> "$DIR/neg/insert.log" 2>&1 || die "indsættelse af $b/$m fejlede"
    done
  done
  echo "NEGATIVE kopier=$(ls "$DIR"/neg/input-b??.json | wc -l | tr -d ' ') koersler=$(ls "$DIR"/neg/cand-b??-*.json | wc -l | tr -d ' ')"
fi

if step measure; then
  P -F ' | ' -v source_id="$SOURCE" -v input_sha256="$MAIN" -v facit="$FACIT" \
    -f "$SQL/calibrate-publication-control.sql" > "$DIR/kalibrering.out"
  echo "MEASURE cm | personas | rigtige | kf_par | forkerte | forkerte_personas | neg_koersler | neg_par | neg_forkerte | neg_par_flere_koersler | neg_klynge_rang1_auto | neg_uberoert | facit_udfald | kf_fordeling"
  cat "$DIR/kalibrering.out"   # kun antal (se SQL-headeren)
fi

if step compare; then
  first="${MARGINS%% *}"
  for f in "cand-nofb" "cand-$first"; do
    echo "COMPARE $f $("$TSX" "$PKG/src/cli.ts" calibrate --candidates "$DIR/$f.json" --truth "$DIR/facit.json")"
    echo "COMPARE $f $("$TSX" "$PKG/src/calibration-cli.ts" cluster-calibrate --candidates "$DIR/$f.json" --truth "$DIR/facit.json")"
  done
  echo "COMPARE candidates_sha256 pr. gitterværdi: $(for m in $MARGINS; do jq -c .candidates "$DIR/cand-$m.json" | shasum -a 256 | cut -c1-12; done | sort -u | wc -l | tr -d ' ') forskellige"
fi

if step years; then
  P -v source_id="$BOUND" -f "$SQL/export-bound-persons.sql" > "$DIR/bundne.json"
  echo "YEARS bundne_personer=$(jq length "$DIR/bundne.json") kilde=$BOUND"
  for f in nofb fb; do
    echo "YEARS $f $("$TSX" "$PKG/src/calibration-cli.ts" years --input "$DIR/input-$f.json" --persons "$DIR/bundne.json")"
  done
fi
find "$DIR" -type f -exec chmod 600 {} +
