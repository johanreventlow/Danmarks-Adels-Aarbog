#!/usr/bin/env bash
# Lokal prøve af docs/runbooks/2026-11-27-koen-ingifte.sql på en frisk, syntetisk base (ikke koblet til CI).
# Bygger base (bootstrap + dblink + schema.sql + db-rls.sql + redaktør fra kalder-matrix), indsætter syntetiske personer,
# kører runbooken uden og med skriv, og afprøver red_fortryd_change_set. Basen droppes ved succes (kun den egne).
set -euo pipefail
cd "$(dirname "$0")/../.."
# Kun lokalt: afvis fjern vært (basen oprettes og droppes).
case "${PGHOST:-}" in ""|localhost|127.0.0.1|/*) ;; *) echo "KOEN_TEST: afviser ikke-lokal PGHOST" >&2; exit 2;; esac
tmpd=$(mktemp -d); trap 'rm -rf "$tmpd"' EXIT
db="navnevisning_koen_$$_$RANDOM"
uid=11000000-0000-0000-0000-00000000ca03
q() { env -u PGOPTIONS psql -X -q -v ON_ERROR_STOP=1 -d "$db" "$@" 2>/dev/null; }
a() { env -u PGOPTIONS psql -X -At -v ON_ERROR_STOP=1 -d "$db" -c "$1"; }
fail() { echo "KOEN_TEST_FAIL: $1 (base $db står tilbage)" >&2; exit 1; }
createdb "$db"
q -f tests/sql/evidence-promotion-bootstrap.sql >/dev/null
q -c 'CREATE EXTENSION IF NOT EXISTS dblink WITH SCHEMA extensions' >/dev/null
q -f schema.sql >/dev/null; q -f db-rls.sql >/dev/null
# Redaktør-fixture: km_kaldere er en pg_temp-funktion, så den oprettes og kaldes i samme session.
{ cat tests/sql/fixtures/kalder-matrix.sql; echo "SELECT pg_temp.km_kaldere();"; } | q >/dev/null
# Syntetiske personer: 1 afdød hustru (gift m. mand), 2 mand, 3 levende uden køn (gift m. mand), 4 afdød m. to familier
# (mand + kvinde), 5 kvinde, 6 afdød uden ægtefælle, 7 afdød gift m. person uden køn (8).
q <<'SQL'
INSERT INTO person(id,levende,koen) VALUES (9001,false,NULL),(9002,false,'mand'),(9003,true,NULL),(9004,false,NULL),
  (9005,false,'kvinde'),(9006,false,NULL),(9007,false,NULL),(9008,false,NULL),(9010,false,'mand');
INSERT INTO family(id) VALUES (9101),(9102),(9103),(9104),(9105);
INSERT INTO family_member(family_id,person_id,rolle) VALUES
  (9101,9001,'partner'),(9101,9002,'partner'),
  (9102,9003,'partner'),(9102,9010,'partner'),
  (9103,9004,'partner'),(9103,9002,'partner'),
  (9104,9004,'partner'),(9104,9005,'partner'),
  (9105,9007,'partner'),(9105,9008,'partner');
SQL
snap() { a "SELECT string_agg(id||'='||coalesce(koen,'-'), ',' ORDER BY id) FROM person WHERE id BETWEEN 9001 AND 9010"; }
fore=$(snap)
run() { env -u PGOPTIONS psql -X -v ON_ERROR_STOP=1 -d "$db" -v redaktoer_uid=$uid "$@" -f docs/runbooks/2026-11-27-koen-ingifte.sql; }
# Uden skriv: ROLLBACK, intet ændret.
run > $tmpd/koen-proeve 2>&1 || { cat $tmpd/koen-proeve; fail "prøvekørsel fejlede"; }
grep -q 'KOEN: ROLLBACK' $tmpd/koen-proeve || fail "prøven rullede ikke tilbage"
[ "$(snap)" = "$fore" ] || fail "prøven ændrede data"
# Uden uid: stopper.
if env -u PGOPTIONS psql -X -v ON_ERROR_STOP=1 -d "$db" -f docs/runbooks/2026-11-27-koen-ingifte.sql >/dev/null 2>&1; then fail "uden uid skulle stoppe"; fi
# Med skriv.
run -v skriv=1 > $tmpd/koen-skriv 2>&1 || { cat $tmpd/koen-skriv; fail "skrivekørsel fejlede"; }
grep -q 'KOEN: COMMIT' $tmpd/koen-skriv || fail "ikke committet"
efter=$(snap)
exp="9001=kvinde,9002=mand,9003=-,9004=-,9005=kvinde,9006=-,9007=-,9008=-,9010=mand"
[ "$efter" = "$exp" ] || fail "forventede $exp, fik $efter"
cs=$(a "SELECT max(id) FROM change_set WHERE operation='red_set_koen'")
[ "$(a "SELECT count(*) FROM change_set WHERE operation='red_set_koen'")" = 1 ] || fail "forventede ét ændringssæt"
# Idempotent: ny kørsel sætter 0 (kandidat 9001 er ikke længere NULL).
run -v skriv=1 > $tmpd/koen-igen 2>&1; grep -q '"sat_kvinde": 0' $tmpd/koen-igen || fail "gentagelse skulle sætte 0"
# Fortryd.
a "SET request.jwt.claim.sub='$uid'; SELECT red_fortryd_change_set($cs)" >/dev/null 2>&1 \
  || q -c "SELECT set_config('request.jwt.claim.sub','$uid',false)" -c "SELECT red_fortryd_change_set($cs)" >/dev/null
[ "$(snap)" = "$fore" ] || fail "fortryd gendannede ikke NULL: $(snap)"
rep=$(tr -d ' \n+' < $tmpd/koen-skriv)
for k in '"sat_kvinde":1' '"sat_mand":0' '"levende_sprunget_over":1' '"ingen_aegtefaelle":1' '"modpart_ukendt_koen":2' '"blandet":1' \
  '"levende":[9003]' '"blandet":[9004]' '"ingen_aegtefaelle":[9006]' '"modpart_ukendt":[9007,9008]'; do
  case "$rep" in *"$k"*) ;; *) fail "rapporten mangler $k";; esac
done
[ "$(a "SELECT summary FROM change_set WHERE id=$cs")" = "Køn for ingifte efter ægteskabsreglen (1 personer)" ] || fail "forkert ændringssæt-label"
echo "KOEN_TEST_OK: prøve uændret; skriv satte 9001=kvinde, 9003/9004 på listen; fortryd gendannede NULL"
dropdb "$db"
