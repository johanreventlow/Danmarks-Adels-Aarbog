#!/usr/bin/env bash
# Lokal prøve af docs/runbooks/2026-11-27-skilsmissedatoer.sql på en frisk, syntetisk base (ikke koblet til CI).
# Bygger base (bootstrap + dblink + schema.sql + db-rls.sql + redaktør fra kalder-matrix), indsætter syntetiske familier
# og biografier, kører runbooken uden og med skriv, og afprøver red_fortryd_change_set. Basen droppes ved succes (kun den egne).
set -euo pipefail
cd "$(dirname "$0")/../.."
# Kun lokalt: afvis fjern vært (basen oprettes og droppes).
case "${PGHOST:-}" in ""|localhost|127.0.0.1|/*) ;; *) echo "SKIL_TEST: afviser ikke-lokal PGHOST" >&2; exit 2;; esac
tmpd=$(mktemp -d); trap 'rm -rf "$tmpd"' EXIT
db="navnevisning_skil_$$_$RANDOM"
uid=11000000-0000-0000-0000-00000000ca03
q() { env -u PGOPTIONS psql -X -q -v ON_ERROR_STOP=1 -d "$db" "$@" 2>/dev/null; }
a() { env -u PGOPTIONS psql -X -At -v ON_ERROR_STOP=1 -d "$db" -c "$1"; }
fail() { echo "SKIL_TEST_FAIL: $1 (base $db står tilbage)" >&2; exit 1; }
createdb "$db"
q -f tests/sql/evidence-promotion-bootstrap.sql >/dev/null
q -c 'CREATE EXTENSION IF NOT EXISTS dblink WITH SCHEMA extensions' >/dev/null
q -f schema.sql >/dev/null; q -f db-rls.sql >/dev/null
{ cat tests/sql/fixtures/kalder-matrix.sql; echo "SELECT pg_temp.km_kaldere();"; } | q >/dev/null
# Udgaverne (indsættes, hvis skemaet ikke så dem).
q -c "INSERT INTO source(slags,udgave) SELECT 'DAA-udgave', u FROM (VALUES ('DAA 2018-20'),('DAA 1939')) v(u)
      WHERE NOT EXISTS (SELECT 1 FROM source s WHERE s.udgave = v.u)"
# Syntetiske familier. Hver: skilsmisse-fakta (valgt påstand date_raw 'skilt', ingen date_min, citation til udgaven),
# to partnere, evt. vielse, evt. biografi (tekst, kilde) på partner 1.
#  A 9301 (2018-20): vielse 1890-05-03, bio »skilt 12. okt. 1901« -> skrevet; partner 2 har en 1939-narrativ (forkert kilde,
#    skal ignoreres)
#  B 9302 (1939): bio »Ægteskabet opløst 1921« -> skrevet (hele året)
#  C 9303 (2018-20): to forskellige datoer -> flertydig
#  D 9304 (2018-20): vielse 1950-01-01, skilt 4. maj 1940 -> foer_vielse
#  E 9305 (2018-20): ingen biografi
#  F 9306 + 9307 (2018-20): samme to partnere (9211, 9212) i begge -> flere_skilte_familier (begge)
#  G 9308 (1939): »Ægteskabet  er opløst 7 Mar. 1920« (dobbelt mellemrum, dag uden punktum) -> skrevet 1920-03-07
#  H 9309 (2018-20): »Fraskilt 9. juni 1774« (fuldt månedsnavn) -> skrevet 1774-06-09
#  I 9310 (2018-20): »skilt 1774, gift 2. gang 1776« -> skrevet 1774 (hele året; »gift« er ikke et fund)
#  J 9311 (2018-20): »Adskilt 1920« -> uden_dato (»skilt« midt i et ord tæller ikke)
#  K 9312 (2018-20): partner 1 har også et andet ægteskab (familie 9399, uden skilsmisse); biografien nævner det andet
#    ægteskabs daterede skilsmisse -> flere_aegteskaber (ikke skrevet)
#  L 9313 (2018-20): vielse 1900-06-01, »skilt 1900« (rent år i vielsens år) -> skrevet 1900 (ikke foer_vielse)
#  M 9314 (2018-20): »skilt 31. feb. 1900« (ugyldig dag) -> ukendt_maaned
q <<'SQL'
CREATE TEMP TABLE spec(fam int, udg text, p1 int, p2 int, vielse date, bio text, bio_udg text);
INSERT INTO spec VALUES
 (9301,'DAA 2018-20',9201,9202,'1890-05-03','Gift 3. maj 1890 med X, skilt 12. okt. 1901.','DAA 2018-20'),
 (9302,'DAA 1939',9203,9204,NULL,'Ægteskabet opløst 1921.','DAA 1939'),
 (9303,'DAA 2018-20',9205,9206,NULL,'Skilt 3. marts 1950; ægteskabet ophævet 1951.','DAA 2018-20'),
 (9304,'DAA 2018-20',9207,9208,'1950-01-01','Gift 1950, skilt 4. maj 1940.','DAA 2018-20'),
 (9305,'DAA 2018-20',9209,9210,NULL,NULL,NULL),
 (9306,'DAA 2018-20',9211,9212,NULL,'Skilt 1. jan. 1990.','DAA 2018-20'),
 (9307,'DAA 2018-20',9211,9212,NULL,NULL,NULL),
 (9308,'DAA 1939',9213,9214,NULL,'Ægteskabet  er opløst 7 Mar. 1920.','DAA 1939'),
 (9309,'DAA 2018-20',9215,9216,NULL,'Fraskilt 9. juni 1774.','DAA 2018-20'),
 (9310,'DAA 2018-20',9217,9218,NULL,'Gift 1770 med X, skilt 1774, gift 2. gang 1776 med Y.','DAA 2018-20'),
 (9311,'DAA 2018-20',9219,9220,NULL,'Adskilt 1920.','DAA 2018-20'),
 (9312,'DAA 2018-20',9221,9222,NULL,'Skilt; gift 2. gang med Y, der var skilt 5. maj 1930.','DAA 2018-20'),
 (9313,'DAA 2018-20',9223,9224,'1900-06-01','Gift 1. juni 1900 med X, skilt 1900.','DAA 2018-20'),
 (9314,'DAA 2018-20',9225,9226,NULL,'Skilt 31. feb. 1900.','DAA 2018-20');
INSERT INTO person(id,levende,koen) SELECT DISTINCT p, false, NULL FROM (SELECT p1 p FROM spec UNION SELECT p2 FROM spec) x;
INSERT INTO family(id) SELECT fam FROM spec;
INSERT INTO family_member(family_id,person_id,rolle) SELECT fam,p1,'partner' FROM spec UNION ALL SELECT fam,p2,'partner' FROM spec;
-- K's partner 1 (9221) har også et andet, ikke-skilt ægteskab med 9299.
INSERT INTO person(id,levende,koen) VALUES (9299,false,NULL);
INSERT INTO family(id) VALUES (9399);
INSERT INTO family_member(family_id,person_id,rolle) VALUES (9399,9221,'partner'),(9399,9299,'partner');
DO $d$ DECLARE s record; v_f bigint; v_a bigint; v_src bigint; BEGIN
  FOR s IN SELECT * FROM spec ORDER BY fam LOOP
    SELECT id INTO v_src FROM source WHERE udgave = s.udg ORDER BY id LIMIT 1;
    INSERT INTO fact(subjekt_type,subjekt_id,faktatype) VALUES ('family',s.fam,'skilsmisse') RETURNING id INTO v_f;
    INSERT INTO assertion(target_type,target_id,date_raw) VALUES ('fact',v_f,'skilt') RETURNING id INTO v_a;
    INSERT INTO citation(assertion_id,source_id) VALUES (v_a,v_src);
    INSERT INTO conclusion(target_type,target_id,valgt_assertion_id,status) VALUES ('fact',v_f,v_a,'afklaret');
    IF s.vielse IS NOT NULL THEN
      INSERT INTO fact(subjekt_type,subjekt_id,faktatype) VALUES ('family',s.fam,'vielse') RETURNING id INTO v_f;
      INSERT INTO assertion(target_type,target_id,date_min,date_max) VALUES ('fact',v_f,s.vielse,s.vielse) RETURNING id INTO v_a;
      INSERT INTO conclusion(target_type,target_id,valgt_assertion_id,status) VALUES ('fact',v_f,v_a,'afklaret');
    END IF;
    IF s.bio IS NOT NULL THEN
      INSERT INTO narrative(subjekt_type,subjekt_id,source_id,tekst)
        VALUES ('person',s.p1,(SELECT id FROM source WHERE udgave = s.bio_udg ORDER BY id LIMIT 1),s.bio);
    END IF;
  END LOOP;
  -- Forkert kilde: A's partner 2 har en 1939-narrativ med en anden dato; den må ikke tælle for en 2018-20-familie.
  INSERT INTO narrative(subjekt_type,subjekt_id,source_id,tekst)
    VALUES ('person',9202,(SELECT id FROM source WHERE udgave='DAA 1939' ORDER BY id LIMIT 1),'Skilt 9. sep. 1999.');
END $d$;
SQL
snap() { a "SELECT string_agg(f.subjekt_id||':'||c.valgt_assertion_id||':'||coalesce(a.date_min::text,'-'), ',' ORDER BY f.subjekt_id)
  FROM fact f JOIN conclusion c ON c.target_type='fact' AND c.target_id=f.id JOIN assertion a ON a.id=c.valgt_assertion_id
  WHERE f.faktatype='skilsmisse' AND f.subjekt_id BETWEEN 9301 AND 9314"; }
fore=$(snap)
antal_pa=$(a "SELECT count(*) FROM assertion")
run() { env -u PGOPTIONS psql -X -v ON_ERROR_STOP=1 -d "$db" -v redaktoer_uid=$uid "$@" -f docs/runbooks/2026-11-27-skilsmissedatoer.sql; }
# Uden skriv: ROLLBACK, intet ændret.
run > $tmpd/proeve 2>&1 || { cat $tmpd/proeve; fail "prøvekørsel fejlede"; }
grep -q 'SKILSMISSE: ROLLBACK' $tmpd/proeve || fail "prøven rullede ikke tilbage"
[ "$(snap)" = "$fore" ] || fail "prøven ændrede data"
[ "$(a "SELECT count(*) FROM assertion")" = "$antal_pa" ] || fail "prøven efterlod påstande"
# Uden uid: stopper.
if env -u PGOPTIONS psql -X -v ON_ERROR_STOP=1 -d "$db" -f docs/runbooks/2026-11-27-skilsmissedatoer.sql >/dev/null 2>&1; then fail "uden uid skulle stoppe"; fi
# Med skriv.
run -v skriv=1 > $tmpd/skriv 2>&1 || { cat $tmpd/skriv; fail "skrivekørsel fejlede"; }
grep -q 'SKILSMISSE: COMMIT' $tmpd/skriv || fail "ikke committet"
dato() { a "SELECT a.date_min||'..'||a.date_max||'|'||a.date_raw FROM fact f JOIN conclusion c ON c.target_type='fact' AND c.target_id=f.id
  JOIN assertion a ON a.id=c.valgt_assertion_id WHERE f.faktatype='skilsmisse' AND f.subjekt_id=$1"; }
[ "$(dato 9301)" = "1901-10-12..1901-10-12|12. okt. 1901" ] || fail "A forkert: $(dato 9301)"
[ "$(dato 9302)" = "1921-01-01..1921-12-31|1921" ] || fail "B forkert: $(dato 9302)"
[ "$(dato 9308)" = "1920-03-07..1920-03-07|7 Mar. 1920" ] || fail "G forkert: $(dato 9308)"
[ "$(dato 9309)" = "1774-06-09..1774-06-09|9. juni 1774" ] || fail "H forkert: $(dato 9309)"
[ "$(dato 9310)" = "1774-01-01..1774-12-31|1774" ] || fail "I forkert: $(dato 9310)"
[ "$(dato 9313)" = "1900-01-01..1900-12-31|1900" ] || fail "L forkert: $(dato 9313)"
for f in 9303 9304 9305 9306 9307 9311 9312 9314; do
  [ "$(a "SELECT a.date_min IS NULL FROM fact f JOIN conclusion c ON c.target_type='fact' AND c.target_id=f.id JOIN assertion a ON a.id=c.valgt_assertion_id WHERE f.faktatype='skilsmisse' AND f.subjekt_id=$f")" = t ] || fail "familie $f skulle ikke være skrevet"
done
# Den gamle påstand findes stadig (invariant 1) for A og B.
[ "$(a "SELECT count(*) FROM assertion a JOIN fact f ON a.target_type='fact' AND a.target_id=f.id WHERE f.faktatype='skilsmisse' AND f.subjekt_id IN (9301,9302) AND a.date_raw='skilt' AND a.date_min IS NULL")" = 2 ] || fail "gamle påstande mangler"
[ "$(a "SELECT count(*) FROM change_set WHERE operation='red_upsert_fakta'")" = 1 ] || fail "forventede ét ændringssæt"
cs=$(a "SELECT max(id) FROM change_set WHERE operation='red_upsert_fakta'")
[ "$(a "SELECT summary FROM change_set WHERE id=$cs")" = "Skilsmissedatoer fra biografierne (6 familier)" ] || fail "forkert ændringssæt-label"
efter=$(snap)
# Idempotent: ny kørsel skriver 0 (A og B er ikke længere kandidater).
run -v skriv=1 > $tmpd/igen 2>&1 || { cat $tmpd/igen; fail "gentagelsen fejlede"; }
grep -q '"skrevet": 0' $tmpd/igen || fail "gentagelse skulle skrive 0"
[ "$(snap)" = "$efter" ] || fail "gentagelsen ændrede data"
[ "$(a "SELECT count(*) FROM change_set WHERE operation='red_upsert_fakta'")" = 1 ] || fail "gentagelsen åbnede et ændringssæt"
# Fortryd: gendanner den gamle valgte påstand.
q -c "SELECT set_config('request.jwt.claim.sub','$uid',false)" -c "SELECT red_fortryd_change_set($cs)" >/dev/null
[ "$(snap)" = "$fore" ] || fail "fortryd gendannede ikke de gamle valgte påstande: $(snap)"
# Rapporten (fra skrivekørslen): kun antal og id'er.
rep=$(tr -d ' \n+' < $tmpd/skriv)
for k in '"kandidater":14' '"skrevet":6' '"flertydig":1' '"uden_dato":1' '"ingen_biografi":1' '"flere_skilte_familier":2' \
  '"flere_aegteskaber":1' '"foer_vielse":1' '"ukendt_maaned":1' '"flere_fakta":0' \
  '"skrevet_familier":[9301,9302,9308,9309,9310,9313]' '"flertydig":[9303]' '"uden_dato":[9311]' '"ingen_biografi":[9305]' \
  '"flere_skilte_familier":[9306,9307]' '"flere_aegteskaber":[9312]' '"foer_vielse":[9304]' '"ukendt_maaned":[9314]'; do
  case "$rep" in *"$k"*) ;; *) fail "rapporten mangler $k";; esac
done
case "$rep" in *1901*|*1921*|*1920*|*1774*|*1900*|*1930*|*okt.*|*Jan.*|*august*) fail "rapporten lækker dato/tekst";; esac
echo "SKIL_TEST_OK: prøve uændret; skriv satte A, B, G, H, I og L; 6+2 på listen; gentagelse 0; fortryd gendannede"
dropdb "$db"
