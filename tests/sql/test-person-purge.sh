#!/usr/bin/env bash
# Fuld personsletning: testharness (Task 2a/2b: skabelon + fixtur; senere tasks tilføjer testgrupper, Task 11 opgradering).
#
# Brug:  bash tests/sql/test-person-purge.sh <præfiks> [<base-commit>]
#   præfiks      navn på engangsbaserne: <præfiks>_tmpl (skabelon) og én kopi pr. testgruppe, <præfiks>_<gruppe>.
#                Scriptet nægter at køre, hvis en base med præfikset allerede findes.
#   base-commit  (valgfri) opgraderingsdelen (Task 11). Uden den køres kun frisk-delen, som slutter med FRISK_OK.
#
# Skabelonen bygges som tests/sql/test-6e2-etiket.sh: evidence-promotion-bootstrap.sql + schema.sql + db-rls.sql, så
# kontrakt v2 (reimport-writer-v2-bootstrap.sql) og til sidst tests/sql/fixtures/person-purge.sql. Hver testgruppe får
# sin egen kopi (createdb -T), så en sletning kan COMMIT'e i sin kopi: udskudte triggere kører ikke ved ROLLBACK (V-4).
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
for f in tests/sql/evidence-promotion-bootstrap.sql schema.sql db-rls.sql; do
  q "$TMPL" -f "$f" || die "byg $f"
done
# Kontrakt v2 (Task 2b): publicerings- og reimport-writerne kræver den (som spike-person-purge-laase.sh).
q "$TMPL" -c 'BEGIN' -f tests/sql/reimport-writer-v2-bootstrap.sql -c 'COMMIT' || die "byg kontrakt v2"
q "$TMPL" -f tests/sql/fixtures/person-purge.sql || die "byg tests/sql/fixtures/person-purge.sql"
# createdb -T kræver, at ingen er forbundet til skabelonen.
a postgres "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='$TMPL' AND pid<>pg_backend_pid()" >/dev/null

# gruppe <navn>: ny kopi af skabelonen; sætter DB.
gruppe() {
  DB="${PFX}_$1"
  createdb -T "$TMPL" "$DB" || die "createdb $DB"; CREATED="$CREATED $DB"
}

# ---------------------------------------------------------------------------------------------------------------------
# Gruppe frisk: fixturen dækker kernestederne (Task 2a) og ledgers/identitet (Task 2b). Tælleren er den uafhængige
# måler fra Task 1.
gruppe frisk
P=$(a "$DB" "SELECT purge_test.id('P')")
[ "${P:-0}" -gt 1000000 ] || die "P mangler eller har id <= 1.000.000"
COUNTS=$(env -u PGOPTIONS psql -X -A -t -F'|' -v ON_ERROR_STOP=1 -d "$DB" -v pid="$P" -f tests/sql/person-purge-count.sql) \
  || die "person-purge-count.sql"
echo "$COUNTS" | awk -F'|' '$NF>0 {print "count " $1 "=" $NF}'
antal() { echo "$COUNTS" | awk -F'|' -v s="$1" '$1==s {print $NF}'; }
# Kernesteder, fixturen skal dække (slettegraf §1a-1d og §1f; ledgers/identitet/publicering er Task 2b).
# (S32b er lagt ind i S32 af T1f/T1g: forbundet:<Fam_del> tælles nu dér.)
for s in S01 S02 S03 S04 S05 S06 S07 S08 S13 S14 S15 S16 S17 S18 S19 S21 S25 S26 S27 S28 S30 S30b S31 S32 \
         S33 S34 S35 S37 S37b S38 S38c S38d S52 S53b S54 S54b S55; do
  [ "$(antal "$s")" -gt 0 ] 2>/dev/null || die "kernestedet $s er ikke dækket ($(antal "$s"))"
done
# Blokeringer må ikke være til stede: P skal kunne slettes.
for s in S20 S29; do
  [ "$(antal "$s")" = 0 ] || die "blokeringsstedet $s er $(antal "$s"), forventet 0"
done
echo "OK fixture_kerne_daekket"

# Task 2b, step 2: fixture_daekker_slettegraf. Hvert sted med handling slet/nulstil/loesn i slettegrafen (§1 og
# »Afgørelser« Q6) skal have antal > 0 i tælleren. Format: sted=tællerlinje[,tællerlinje…] (alle skal være > 0).
DAEKNING="S1=S01 S2=S02 S3=S03,S03b S4=S04 S5=S05 S6=S06 S7=S07 S8=S08 S10=S10 S11a=S11 S11b=S11 S12=S12
  S13=S13 S13b=S13b S14=S14 S14b=S14b S15=S15,S15b S16=S16,S16b S17=S17,S17b S18=S18,S18b S19=S19
  S21=S21,S21b S22=S22 S23=S23 S24=S24 S25=S25 S26=S26 S27=S27 S28=S28 S30=S30,S30b,S30c S31=S31 S32=S32 NY-B=S32
  S33=S33,S33b S34=S34,S34c S35=S35 S36=S36 S37=S37b,S37c S38=S38 S39a=S39 Prom_egen_fam=S39,S48 S40=S40 S41a=S41
  S42=S42 S43a=S43 S45a=S45 M5=M5 S49a=S49 S49b=S49b S52/S53/S55=S52,S53,S53b,S55 S54=S54 S56=S56,S56b"
# Navngiven liste (hver linje godkendt af hovedsessionen): steder, der ikke kan forekomme.
KAN_IKKE_FOREKOMME="S9: person_create_receipt forbruges i den oprettende transaktion (slettegraf S9, R14)"
for par in $DAEKNING; do
  sted=${par%%=*}
  for nr in $(echo "${par#*=}" | tr ',' ' '); do
    [ "$(antal "$nr")" -gt 0 ] 2>/dev/null || die "fixture_daekker_slettegraf: $sted ($nr) er $(antal "$nr")"
  done
done
# Delsteder bag en samlet tæller skal desuden have en repræsentant i facit (purge_test.sted).
for sted in S11a S11b S39a Prom_egen_fam S45a S49a; do
  [ "$(a "$DB" "SELECT count(*) FROM purge_test.sted s JOIN purge_test.forventet f USING (tabel,pk) WHERE s.sted='$sted'")" -gt 0 ] \
    || die "fixture_daekker_slettegraf: delstedet $sted har ingen repræsentant i facit"
done
# S49b: fixturen har to rækker, der hver kun nås ad én vej (Prom_egen hhv. S41a); tælleren skal se begge.
[ "$(antal S49b)" = 2 ] || die "fixture_daekker_slettegraf: S49b er $(antal S49b), forventet 2"
[ "$(antal S09)" = 0 ] || die "fixture_daekker_slettegraf: S9 står på kan_ikke_forekomme, men er $(antal S09)"
echo "kan_ikke_forekomme: $KAN_IKKE_FOREKOMME"
# S46 (bevar_andres): stikprøvens mapping/expected er P's kandidat-uuid; tælleren skal se den.
[ "$(antal S46)" -gt 0 ] 2>/dev/null || die "fixture_daekker_slettegraf: S46 er $(antal S46)"
echo "OK fixture_daekker_slettegraf"
echo "facit: $(a "$DB" "SELECT string_agg(handling||'='||n,' ' ORDER BY handling) FROM (SELECT handling,count(*) n FROM purge_test.forventet GROUP BY 1) x")"

# ---------------------------------------------------------------------------------------------------------------------
# SQL-testgrupperne i tests/sql/test-person-purge.sql, hver i sin egen kopi (de midlertidige tabeller/kolonner i
# katalogvagtens test oprettes og fjernes kun dér).
# Gem KUN tællerens sted/antal i skabelonen til plan_matcher_count. Ingen planfunktion i måleren.
# Kopier af skabelonen kan også køre gruppen direkte med -v gruppe=plan.
q "$TMPL" -c 'CREATE TABLE purge_test.counts(sted text PRIMARY KEY, antal bigint NOT NULL)' || die "opret count-snapshot"
printf '%s\n' "$COUNTS" | awk -F'|' '{print $1 "|" $NF}' | \
  env -u PGOPTIONS psql -X -q -v ON_ERROR_STOP=1 -d "$TMPL" \
    -c "COPY purge_test.counts(sted,antal) FROM STDIN WITH (DELIMITER '|')" || die "gem count-snapshot"
for g in inventar binding plan historik fortrydelse; do
  gruppe "$g"
  ud=$(env -u PGOPTIONS psql -X -q -v ON_ERROR_STOP=1 -d "$DB" -v gruppe="$g" -f tests/sql/test-person-purge.sql 2>&1)
  rc=$?
  printf '%s\n' "$ud" | grep -v NOTICE
  [ "$rc" = 0 ] || die "testgruppen $g fejlede"
done
echo FRISK_OK

# ---------------------------------------------------------------------------------------------------------------------
if [ -n "$BASE_COMMIT" ]; then
  echo "PURGE_FEJL: opgraderingsdelen (base-commit $BASE_COMMIT) er ikke bygget endnu (Task 11)" >&2
  exit 2
fi
