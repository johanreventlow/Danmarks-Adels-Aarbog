#!/usr/bin/env bash
# Plan A Task 5 (#147): byg en overførselspakke af fixturen i en »restore«-base og genafspil den
# genererede 07 (afgørelser) og 08 (bindinger) i en separat »prod«-base. interpretation_key er globalt
# unik pr. version, så restore og prod kan ikke stå i samme base: begge oprettes som kopier
# (createdb -T) af $PGDATABASE, som SKAL være en ren base bygget med CI-opskriften (bootstrap + schema +
# rls + migrations). Scriptet sletter kun de baser, det selv har oprettet (${PGDATABASE}_*), aldrig
# $PGDATABASE. TRANSFER_KEEP_DBS=1 beholder dem til fejlsøgning.
# bash 3.2-kompatibelt (macOS) — CI-billedet har ikke zsh.
# Printer kun tilstande, fejlkoder, tal og hashes; aldrig SQL-kroppe, evidens eller aktør-id.
set -euo pipefail
umask 077
cd "$(dirname "$0")/../.."
: "${PGDATABASE:?PGDATABASE skal pege på en ren base bygget med CI-opskriften}"
BASE="$PGDATABASE"
S=.claude/skills/daa-extract/scripts
A=a4700000-0000-4000-8000-000000000001      # redaktionsprofilen i fixturen
A_WRONG=a4700000-0000-4000-8000-000000000002
SRC=-4700
K1=b4700000-0000-4000-8000-000000000001
K3=b4700000-0000-4000-8000-000000000003
T=$(mktemp -d)
CREATED=""

cleanup() {
  local rc=$?
  if [ "${TRANSFER_KEEP_DBS:-0}" != 1 ]; then
    for db in $CREATED; do dropdb --if-exists "$db" || true; done
  elif [ -n "$CREATED" ]; then
    echo "beholdt:$CREATED"
  fi
  rm -rf "$T"
  exit $rc
}
trap cleanup EXIT

die() { echo "FEJL: $*" >&2; exit 1; }
q() { psql -X -q -v ON_ERROR_STOP=1 "$@"; }
tp() { python3 "$S/transfer_pack.py" "$@"; }

# newdb <suffiks>: ny engangskopi af den rene base; navnet lægges i DB (ingen subshell, så CREATED holder).
newdb() {
  DB="${BASE}_$1"
  createdb -T "$BASE" "$DB"
  CREATED="$CREATED $DB"
}

# fixture <db> <SQL efter fixturen> [psql-variabler …]: fixturen committes i én transaktion.
fixture() {
  local db="$1" extra="$2"; shift 2
  { echo "BEGIN;"; echo "\\i tests/sql/transfer-fixture.sql"; echo "$extra"; echo "COMMIT;"; } > "$T/fx.sql"
  q -d "$db" "$@" -f "$T/fx.sql" >/dev/null
}

# readguc <db> <repo-fil> <guc> <ud-fil>: læse-kun kørsel; kun GUC'ens JSON skrives (0600) til filen.
readguc() {
  { echo "BEGIN READ ONLY;"; echo "\\o /dev/null"; echo "\\i $2"; echo "\\o";
    echo "SELECT current_setting('$3');"; echo "ROLLBACK;"; } > "$T/rd.sql"
  q -A -t -v src=$SRC -d "$1" -f "$T/rd.sql" > "$4"
}

# state <db>: tilstanden (spec §5) af kilden i basen målt mod den ægte pakke.
state() {
  readguc "$1" "$S/interpretation_transfer_digests.sql" daa.transfer_digests "$T/st.json"
  tp state --digests "$T/st.json" --pack-manifest "$T/pack/pack-manifest.json"
}

expect_state() { local got; got=$(state "$1"); [ "$got" = "$2" ] || die "$3: tilstand $got, forventet $2"; }

# decide_direct <db> <nøgleprefiks> <k2 også: 1/0>: afgørelser som restoren traf dem (direkte RPC).
decide_direct() {
  cat > "$T/dd.sql" <<'SQL'
BEGIN;
SELECT id AS id1 FROM private.interpretation WHERE interpretation_key=(:'kp'||'-0000-4000-8000-000000000001')::uuid AND version=1 \gset
SELECT id AS id2 FROM private.interpretation WHERE interpretation_key=(:'kp'||'-0000-4000-8000-000000000002')::uuid AND version=1 \gset
SELECT set_config('request.jwt.claim.sub', :'actor', true) \g /dev/null
SET LOCAL ROLE authenticated;
SELECT red_decide_interpretation(:'id1',1,'accepted','{"method":"machine-corroboration-v1","assertion_id":-4711}') \g /dev/null
\if :with_k2
SELECT red_decide_interpretation(:'id2',1,'rejected','{"method":"human-sheet-kontrol-v1","line":1,"note":""}') \g /dev/null
\endif
RESET ROLE;
COMMIT;
SQL
  q -d "$1" -v kp="$2" -v with_k2="$3" -v actor=$A -f "$T/dd.sql"
}

# expect_fail <db> <kode> <sql-fil> [aktør]: første ERROR skal være koden.
expect_fail() {
  local db="$1" code="$2" file="$3" actor="${4:-$A}" first
  if q -d "$db" -v src=$SRC -v actor="$actor" -f "$file" >"$T/out" 2>"$T/err"; then die "$code slap igennem"; fi
  first=$(grep -m1 -o 'ERROR: .*' "$T/err" | cut -c1-120 || true)
  echo "$first" | grep -Eq "^ERROR: +${code}([^A-Z_]|\$)" || die "forventede $code, fik: ${first:-ingen ERROR}"
  echo "  ok: $code"
}

# tamper <tilstand> <ny pakkemappe>: én ændring i pakken, derefter genforseglet med transfer_pack's egne
# funktioner (decisions_keyed_sha256 og pack_sha256), så kun SQL-vagterne kan fange den.
tamper() {
  python3 - "$T/pack" "$2" "$1" "$S" <<'PY'
import json, os, sys
src, dst, mode, scripts = sys.argv[1:]
sys.path.insert(0, scripts)
import transfer_pack as tp
dec = json.loads(open(f"{src}/decisions-keyed.json", encoding="utf-8").read())
man = json.loads(open(f"{src}/pack-manifest.json", encoding="utf-8").read())
if mode == "fp":
    dec[0]["decision_fingerprint"] = "0" * 64
elif mode == "dup":
    dec.append(dict(dec[0]))
elif mode == "evidence":
    dec[1]["evidence"]["line"] = 2
elif mode == "scope":
    man["accepted_keys"] = sorted(man["accepted_keys"] + ["b4700000-0000-4000-8000-000000000003"])
elif mode == "nbind":
    man["digests"]["n_bindings"] += 1
elif mode == "bdigest":
    man["digests"]["binding_digest"] = "0" * 64
else:
    raise SystemExit("ukendt tamper " + mode)
text = tp.canonical(dec)
man["decisions_keyed_sha256"] = tp.sha256_text(text)
man["pack_sha256"] = tp.pack_sha256(man)
os.mkdir(dst, 0o700)
tp._write_private(__import__("pathlib").Path(dst) / "decisions-keyed.json", text)
tp._write_private(__import__("pathlib").Path(dst) / "pack-manifest.json", tp.canonical(man) + "\n")
PY
}

# gen <pakkemappe> <decide-sql|bind-sql> <ud-fil>
gen() { tp "$2" --pack-dir "$1" --out "$3" >/dev/null; }

# ---------------------------------------------------------------- »Restore«
newdb r; R=$DB
fixture "$R" "SELECT pg_temp.transfer_fx($SRC,'a4701000','b4700000') \\g /dev/null"
# Klassifikationen tages FØR afgørelserne, som i den ægte kørsel (spec §4.1 errata).
readguc "$R" "$S/interpretation_control_classification.sql" daa.control_result "$T/cls.json"
decide_direct "$R" b4700000 1
# Binding med den scopede målfinding (scope = de accepterede).
cat > "$T/rb.sql" <<'SQL'
BEGIN;
SELECT set_config('daa.transfer_scope', :'scope', true) \g /dev/null
\o /dev/null
\i .claude/skills/daa-extract/scripts/interpretation_promotion_targets_scoped.sql
\o
SELECT set_config('request.jwt.claim.sub', :'actor', true) \g /dev/null
SET LOCAL ROLE authenticated;
DO $b$ DECLARE items jsonb := current_setting('daa.targets_scoped')::jsonb->'items';
               p jsonb := red_preview_interpretation_promotions(items);
BEGIN PERFORM red_promote_interpretations_batch(items, p->>'preview_hash'); END $b$;
RESET ROLE;
COMMIT;
SQL
q -d "$R" -v scope="[\"$K1\"]" -v actor=$A -f "$T/rb.sql"
readguc "$R" "$S/transfer_pack_export.sql" daa.pack_export "$T/export.json"
readguc "$R" "$S/interpretation_decision_fingerprint.sql" daa.fingerprints "$T/fp.json"
readguc "$R" "$S/interpretation_decision_fingerprint.sql" daa.fingerprint_record_check "$T/rc.json"
readguc "$R" "$S/interpretation_transfer_digests.sql" daa.transfer_digests "$T/dg.json"
readguc "$R" "$S/transfer_baseline.sql" daa.transfer_baseline "$T/bl.json"
echo '{"dump_sha256":"fixture","state":"fixture","kanonisk_md5":"fixture"}' > "$T/receipt.json"
mkdir -m 700 "$T/pack"
tp build --export "$T/export.json" --fingerprints "$T/fp.json" --digests "$T/dg.json" --baseline "$T/bl.json" \
  --record-check "$T/rc.json" --classification "$T/cls.json" --dump-receipt "$T/receipt.json" \
  --manifest-content-sha256 fixture --ledger-sha256 fixture --out-dir "$T/pack"
tp decide-sql --pack-dir "$T/pack" --out "$T/07.sql"
tp bind-sql --pack-dir "$T/pack" --out "$T/08.sql"
PACK=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["pack_sha256"])' "$T/pack/pack-manifest.json")
expect_state "$R" COMPLETE "restoren mod sin egen pakke"

# Pakker med én genforseglet ændring.
for m in fp dup evidence scope nbind bdigest; do tamper "$m" "$T/pack_$m"; done
gen "$T/pack_fp" decide-sql "$T/07_fp.sql"
gen "$T/pack_dup" decide-sql "$T/07_dup.sql"
gen "$T/pack_evidence" decide-sql "$T/07_evidence.sql"
gen "$T/pack_scope" bind-sql "$T/08_scope.sql"
gen "$T/pack_nbind" bind-sql "$T/08_nbind.sql"
gen "$T/pack_bdigest" bind-sql "$T/08_bdigest.sql"

# ---------------------------------------------------------------- »Prod«
# Samme kilde-id og nøgler, andre uuid'er. Kilde -4800 er en anden kilde i prod med en accepteret,
# promoverbar fortolkning: den må hverken forstyrre præmissen i 07 eller blive bundet af 08.
newdb p; P=$DB
fixture "$P" "SELECT pg_temp.transfer_fx($SRC,'a4700000','b4700000') \\g /dev/null
SELECT pg_temp.transfer_fx(-4800,'a4800000','b4800000') \\g /dev/null"
decide_direct "$P" b4800000 0
expect_state "$P" PROPOSED "prod før 07"

echo "07-vagter i PROPOSED (hver fejl ruller tilbage; tilstanden er stadig PROPOSED):"
expect_fail "$P" TRANSFER_STATE_NOT_DECIDED "$T/08.sql"
expect_fail "$P" DECISION_FINGERPRINT_MISMATCH "$T/07_fp.sql"
expect_fail "$P" "DECISION_KEY_UNRESOLVED duplicate" "$T/07_dup.sql"
expect_fail "$P" TRANSFER_ACTOR_MISMATCH "$T/07.sql" "$A_WRONG"
expect_fail "$P" DECISION_DIGEST_MISMATCH "$T/07_evidence.sql"
expect_state "$P" PROPOSED "efter 07-vagterne"

q -d "$P" -v src=$SRC -v actor=$A -f "$T/07.sql" > "$T/out07"
[ "$(cat "$T/out07")" = "TRANSFER_07_OK afgørelser=2" ] || die "07: uventet stdout"
echo "07: $(cat "$T/out07")"
expect_state "$P" DECIDED "prod efter 07"
n=$(q -A -t -d "$P" -c "SELECT count(*) FROM private.interpretation_current WHERE source_id=$SRC AND decision_evidence->>'pack_sha256'='$PACK'")
[ "$n" = 2 ] || die "07: pack_sha256 i $n af 2 evidenser"

# 07 igen: tilstandsvagten stopper; intet ændret (digests og alle rækker for kilden).
rows="SELECT count(*)||'|'||md5(coalesce(string_agg(to_jsonb(i)::text, E'\n' ORDER BY i.id),'')) FROM private.interpretation i WHERE source_id=$SRC"
readguc "$P" "$S/interpretation_transfer_digests.sql" daa.transfer_digests "$T/before.json"
before_rows=$(q -A -t -d "$P" -c "$rows")
expect_fail "$P" TRANSFER_STATE_NOT_PROPOSED "$T/07.sql"
readguc "$P" "$S/interpretation_transfer_digests.sql" daa.transfer_digests "$T/after.json"
cmp -s "$T/before.json" "$T/after.json" || die "07 igen: digests ændret"
[ "$(q -A -t -d "$P" -c "$rows")" = "$before_rows" ] || die "07 igen: rækker ændret"

echo "08-vagter i DECIDED (tilstanden er stadig DECIDED):"
expect_fail "$P" "BIND_SCOPE_DRIFT accepted" "$T/08_scope.sql"
expect_fail "$P" "BIND_SCOPE_DRIFT items=1" "$T/08_nbind.sql"
expect_fail "$P" TRANSFER_ACTOR_MISMATCH "$T/08.sql" "$A_WRONG"
expect_fail "$P" BINDING_DIGEST_MISMATCH "$T/08_bdigest.sql"
expect_state "$P" DECIDED "efter 08-vagterne"

q -d "$P" -v src=$SRC -v actor=$A -f "$T/08.sql" > "$T/out08" 2> "$T/err08"
[ "$(cat "$T/out08")" = "TRANSFER_08_OK bindinger=1" ] || die "08: uventet stdout"
grep -q "TRANSFER_08 items=1 uden_for_pakken=1" "$T/err08" || die "08: kilde -4800's mål ikke talt som uden for pakken"
echo "08: $(cat "$T/out08") (1 mål uden for pakken sprunget over)"
n=$(q -A -t -d "$P" -c "SELECT count(*) FROM private.interpretation_promotion p JOIN private.interpretation i ON i.id=p.interpretation_id WHERE i.source_id=-4800")
[ "$n" = 0 ] || die "08 bandt $n uden for pakken"
expect_fail "$P" TRANSFER_STATE_NOT_DECIDED "$T/08.sql"
readguc "$P" "$S/interpretation_transfer_digests.sql" daa.transfer_digests "$T/prod-digests.json"
[ "$(tp state --digests "$T/prod-digests.json" --pack-manifest "$T/pack/pack-manifest.json")" = COMPLETE ] \
  || die "prod er ikke COMPLETE"
echo "prod: COMPLETE"

# Målfindingen uden scope stopper.
{ echo "BEGIN;"; echo "\\i $S/interpretation_promotion_targets_scoped.sql"; echo "ROLLBACK;"; } > "$T/noscope.sql"
expect_fail "$P" BIND_SCOPE_REQUIRED "$T/noscope.sql"

# ---------------------------------------------------------------- Prod-varianter (egen base hver)
echo "Prod-varianter:"
newdb neg_death; N=$DB
fixture "$N" "SELECT pg_temp.transfer_fx($SRC,'a4700000','b4700000') \\g /dev/null" -v fx_death=1851
expect_fail "$N" MACHINE_PREMISE_DRIFT "$T/07.sql"          # maskinel nøgle, hvis assertion er ændret
expect_state "$N" PROPOSED "neg_death"
newdb neg_name; N=$DB
fixture "$N" "SELECT pg_temp.transfer_fx($SRC,'a4700000','b4700000') \\g /dev/null" -v fx_name=Anna
expect_fail "$N" MACHINE_PREMISE_DRIFT "$T/07.sql"          # REAL_DIFF-nøgle, der er blevet MATCH
expect_state "$N" PROPOSED "neg_name"
newdb neg_clause_text; N=$DB
fixture "$N" "SELECT pg_temp.transfer_fx($SRC,'a4700000','b4700000','Anna død 1849') \\g /dev/null"
expect_fail "$N" TRANSFER_STATE_NOT_PROPOSED "$T/07.sql"    # klausulteksten indgår i proposal_digest
expect_state "$N" MIXED "neg_clause_text"
newdb neg_clause_set; N=$DB
fixture "$N" "SELECT pg_temp.transfer_fx($SRC,'a4700000','b4700000') \\g /dev/null
INSERT INTO private.source_record(id,source_id,record_key,record_kind,created_run_id)
  VALUES ('a4700000-0000-4000-8000-0000000000e6',$SRC,'T-2','person_entry','a4700000-0000-4000-8000-0000000000e1');"
expect_fail "$N" CLAUSE_SET_DRIFT "$T/07.sql"               # ny post uden klausuler ('none')
expect_state "$N" PROPOSED "neg_clause_set"

echo "OK: transfer decide/bind"
