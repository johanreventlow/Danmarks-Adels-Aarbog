#!/usr/bin/env bash
# Fuld personsletning: testharness (Task 2a: skabelon + fixtur; senere tasks tilføjer testgrupper, Task 11 opgradering).
#
# Brug:  bash tests/sql/test-person-purge.sh <præfiks> [<base-commit>]
#   præfiks      navn på engangsbaserne: <præfiks>_tmpl (skabelon) og én kopi pr. testgruppe, <præfiks>_<gruppe>.
#                Scriptet nægter at køre, hvis en base med præfikset allerede findes.
#   base-commit  (valgfri) opgraderingsdelen (Task 11). Uden den køres kun frisk-delen, som slutter med FRISK_OK.
#
# Skabelonen bygges som tests/sql/test-6e2-etiket.sh: evidence-promotion-bootstrap.sql + schema.sql + db-rls.sql, og
# derefter tests/sql/fixtures/person-purge.sql. Hver testgruppe får sin egen kopi (createdb -T), så en sletning kan
# COMMIT'e i sin kopi: udskudte triggere kører ikke ved ROLLBACK (V-4).
#
# Baserne BEHOLDES som standard. PURGE_DROP_DBS=1 sletter de baser, scriptet selv har oprettet i denne kørsel (og kun
# dem; alle bærer præfikset). Scriptet rører aldrig en base, det ikke selv har oprettet.
# Output: kun tal, stednavne og tabelnavne (ingen rækkeindhold).
set -uo pipefail
cd "$(dirname "$0")/../.."
PFX=${1:?brug: test-person-purge.sh <præfiks> [<base-commit>]}
BASE_COMMIT=${2:-}
[[ $PFX =~ ^[a-z][a-z0-9_]{0,40}$ ]] || { echo "PURGE_FEJL: ugyldigt præfiks '$PFX'" >&2; exit 1; }
TMPL="${PFX}_tmpl"
LOG=$(mktemp -d)/build.log
CREATED=""

cleanup() {
  local rc=$?
  if [ "${PURGE_DROP_DBS:-0}" = 1 ]; then
    for db in $CREATED; do dropdb "$db" >/dev/null 2>&1 || true; done
  elif [ -n "$CREATED" ]; then
    echo "beholdt:$CREATED"
  fi
  exit $rc
}
trap cleanup EXIT

die() { echo "PURGE_FEJL: $*" >&2; exit 1; }
q() { env -u PGOPTIONS psql -X -q -v ON_ERROR_STOP=1 -d "$1" "${@:2}" >/dev/null 2>>"$LOG" \
        || { grep -v NOTICE "$LOG" | tail -5 >&2; return 1; }; }
a() { env -u PGOPTIONS psql -X -At -v ON_ERROR_STOP=1 -d "$1" -c "$2"; }

# Præfikset må ikke være i brug (så scriptet aldrig bygger oven på eller kopierer en fremmed base).
[ -z "$(a postgres "SELECT 1 FROM pg_database WHERE datname='$TMPL' OR datname LIKE '$(printf '%s' "$PFX" | sed 's/_/\\_/g')\_%' LIMIT 1")" ] \
  || die "en base med præfikset $PFX findes allerede; vælg et andet præfiks"

# ---------------------------------------------------------------------------------------------------------------------
# Skabelonen.
createdb "$TMPL" || die "createdb $TMPL"; CREATED="$CREATED $TMPL"
for f in tests/sql/evidence-promotion-bootstrap.sql schema.sql db-rls.sql tests/sql/fixtures/person-purge.sql; do
  q "$TMPL" -f "$f" || die "byg $f"
done
# createdb -T kræver, at ingen er forbundet til skabelonen.
a postgres "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='$TMPL' AND pid<>pg_backend_pid()" >/dev/null

# gruppe <navn>: ny kopi af skabelonen; sætter DB.
gruppe() {
  DB="${PFX}_$1"
  createdb -T "$TMPL" "$DB" || die "createdb $DB"; CREATED="$CREATED $DB"
}

# ---------------------------------------------------------------------------------------------------------------------
# Gruppe frisk: fixturen dækker kernestederne (Task 2a). Tælleren er den uafhængige måler fra Task 1.
gruppe frisk
P=$(a "$DB" "SELECT purge_test.id('P')")
[ "${P:-0}" -gt 1000000 ] || die "P mangler eller har id <= 1.000.000"
COUNTS=$(env -u PGOPTIONS psql -X -A -t -F'|' -v ON_ERROR_STOP=1 -d "$DB" -v pid="$P" -f tests/sql/person-purge-count.sql) \
  || die "person-purge-count.sql"
echo "$COUNTS" | awk -F'|' '$NF>0 {print "count " $1 "=" $NF}'
antal() { echo "$COUNTS" | awk -F'|' -v s="$1" '$1==s {print $NF}'; }
# Kernesteder, fixturen skal dække (slettegraf §1a-1d og §1f; ledgers/identitet/publicering er Task 2b).
for s in S01 S02 S03 S04 S05 S06 S07 S08 S13 S14 S15 S16 S17 S18 S19 S21 S25 S26 S27 S28 S30 S30b S31 S32 S32b \
         S33 S34 S35 S37 S37b S38 S38c S38d S52 S53b S54 S54b S55; do
  [ "$(antal "$s")" -gt 0 ] 2>/dev/null || die "kernestedet $s er ikke dækket ($(antal "$s"))"
done
# Blokeringer må ikke være til stede: P skal kunne slettes.
for s in S20 S29; do
  [ "$(antal "$s")" = 0 ] || die "blokeringsstedet $s er $(antal "$s"), forventet 0"
done
echo "OK fixture_kerne_daekket"
echo "facit: $(a "$DB" "SELECT string_agg(handling||'='||n,' ' ORDER BY handling) FROM (SELECT handling,count(*) n FROM purge_test.forventet GROUP BY 1) x")"
echo FRISK_OK

# ---------------------------------------------------------------------------------------------------------------------
if [ -n "$BASE_COMMIT" ]; then
  echo "PURGE_FEJL: opgraderingsdelen (base-commit $BASE_COMMIT) er ikke bygget endnu (Task 11)" >&2
  exit 2
fi
