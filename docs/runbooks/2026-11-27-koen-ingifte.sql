-- Køn for ingifte efter ægteskabsreglen (spec docs/superpowers/specs/2026-11-27-personside-navnevisning-design.md,
-- afsnit »Data: køn for ingifte (prod-skrivning)«).
--
-- Regel: kandidater = person med koen IS NULL og levende IS NOT TRUE (afdøde). Alle kandidatens modparter
-- (partner-rækker i ALLE kandidatens familier, ikke kandidaten selv) samles. Er alle modparter 'mand' -> 'kvinde';
-- er alle 'kvinde' -> 'mand'. Ellers sættes intet: ingen modpart, en modpart med NULL/'ukendt' køn, eller blandede køn.
-- Levende med tomt køn sættes aldrig af reglen (et nutidigt ægteskab kan være mellem to af samme køn); de tælles og
-- listes. Udfaldet beregnes ÉN gang, før første skrivning (så en kandidat, der er modpart til en anden, ikke ændrer
-- den andens udfald undervejs).
--
-- Skrivevej: red_set_koen(person_id, koen) (kræver current_rolle() = 'redaktion'). Hvert kald kører begin_change_set,
-- som genbruger transaktionens aktive sæt (schema.sql: begin_change_set, `app.change_set_id`) -> ALLE skrivninger
-- lander i ÉT ændringssæt, som kan fortrydes samlet med red_fortryd_change_set(<id>). Sættets id udskrives.
--
-- Output: kun antal og person-id'er (aldrig navne). Redaktørlisten = id'erne under »IKKE_SAT«.
--
-- Kørsel via psql (projektejerens shell; aktøren gives som variabel og står aldrig i filen):
--   psql "$DSN" -v redaktoer_uid=<uuid> -f docs/runbooks/2026-11-27-koen-ingifte.sql            -- prøve: ROLLBACK
--   psql "$DSN" -v redaktoer_uid=<uuid> -v skriv=1 -f docs/runbooks/2026-11-27-koen-ingifte.sql -- skriv: COMMIT
-- Kørsel via Supabase MCP execute_sql (ingen psql-meta-kommandoer): indsæt teksten mellem »BEGIN-MARKØR« og
-- »SLUT-MARKØR«; erstat aktørlinjen (markeret AKTØRLINJE) med
--   SELECT set_config('request.jwt.claim.sub', '<uuid>', true) IS NOT NULL AS aktoer_sat;
-- og slut med ROLLBACK (prøve) eller COMMIT (skriv) i stedet for den psql-betingede blok i bunden.
-- Idempotent: efter en skrivning er kandidaterne ikke længere NULL, så en gentagelse sætter 0.
\set ON_ERROR_STOP on
\if :{?skriv}
\else
  \set skriv false
\endif
\if :{?redaktoer_uid}
\else
  \echo 'KOEN_FEJL: angiv -v redaktoer_uid=<uuid>'
  SELECT 1/0 AS mangler_redaktoer_uid;
\endif

-- ===== BEGIN-MARKØR (ren SQL herfra) =====
BEGIN;
SELECT set_config('request.jwt.claim.sub', :'redaktoer_uid', true) IS NOT NULL AS aktoer_sat;  -- AKTØRLINJE

DO $aktoer$ BEGIN
  IF current_rolle() <> 'redaktion' THEN
    RAISE EXCEPTION 'KOEN_FEJL: aktøren har ikke rollen redaktion (rolle: %)', current_rolle();
  END IF;
END $aktoer$;

-- Udfald pr. person med tomt køn (afdøde og levende), beregnet før nogen skrivning.
CREATE TEMP TABLE koen_maal ON COMMIT DROP AS
WITH modpart AS (
  SELECT DISTINCT a.person_id AS kandidat_id, b.person_id AS modpart_id
  FROM family_member a
  JOIN family_member b ON b.family_id = a.family_id AND b.rolle = 'partner' AND b.person_id <> a.person_id
  WHERE a.rolle = 'partner'
), agg AS (
  SELECT m.kandidat_id,
         count(*) AS n_modpart,
         count(*) FILTER (WHERE p.koen = 'mand') AS n_mand,
         count(*) FILTER (WHERE p.koen = 'kvinde') AS n_kvinde
  FROM modpart m JOIN person p ON p.id = m.modpart_id
  GROUP BY m.kandidat_id
)
SELECT p.id AS person_id,
       CASE
         WHEN p.levende IS TRUE THEN 'levende'
         WHEN a.kandidat_id IS NULL THEN 'ingen_aegtefaelle'
         WHEN a.n_mand = a.n_modpart THEN 'kvinde'
         WHEN a.n_kvinde = a.n_modpart THEN 'mand'
         WHEN a.n_mand + a.n_kvinde < a.n_modpart THEN 'modpart_ukendt'
         ELSE 'blandet'
       END AS udfald
FROM person p
LEFT JOIN agg a ON a.kandidat_id = p.id
WHERE p.koen IS NULL;

-- Før skrivning (alle tal er antal personer med tomt køn).
SELECT udfald, count(*) AS antal FROM koen_maal GROUP BY udfald ORDER BY udfald;

-- Skrivning: ét red_set_koen-kald pr. afdød kandidat med entydigt udfald; alle i ét ændringssæt.
DO $skriv$
DECLARE m record; v_n int := 0;
BEGIN
  FOR m IN SELECT person_id, udfald FROM koen_maal WHERE udfald IN ('kvinde','mand') ORDER BY person_id LOOP
    PERFORM red_set_koen(m.person_id, m.udfald);
    v_n := v_n + 1;
  END LOOP;
  RAISE NOTICE 'KOEN_SKREVET: % personer', v_n;
END $skriv$;

-- Resultat (antal pr. udfald i kategorierne fra specen) og ændringssættet.
SELECT
  count(*) FILTER (WHERE udfald = 'kvinde')            AS sat_kvinde,
  count(*) FILTER (WHERE udfald = 'mand')              AS sat_mand,
  count(*) FILTER (WHERE udfald = 'levende')           AS levende_sprunget_over,
  count(*) FILTER (WHERE udfald = 'ingen_aegtefaelle') AS ingen_aegtefaelle,
  count(*) FILTER (WHERE udfald = 'modpart_ukendt')    AS modpart_ukendt_koen,
  count(*) FILTER (WHERE udfald = 'blandet')           AS blandet
FROM koen_maal;
SELECT nullif(current_setting('app.change_set_id', true), '') AS aendringssaet_id;

-- Redaktørlisten: id'er (ingen navne) på dem, der ikke blev sat.
SELECT 'IKKE_SAT' AS liste, udfald, person_id FROM koen_maal
WHERE udfald NOT IN ('kvinde','mand') ORDER BY udfald, person_id;

-- Kontrol: hver person med entydigt udfald har nu præcis det køn; ingen er sat uden for reglen.
DO $kontrol$ DECLARE v_fejl int; v_for_meget int; BEGIN
  SELECT count(*) INTO v_fejl FROM koen_maal m JOIN person p ON p.id = m.person_id
   WHERE m.udfald IN ('kvinde','mand') AND p.koen IS DISTINCT FROM m.udfald;
  SELECT count(*) INTO v_for_meget FROM koen_maal m JOIN person p ON p.id = m.person_id
   WHERE m.udfald NOT IN ('kvinde','mand') AND p.koen IS NOT NULL;
  IF v_fejl <> 0 OR v_for_meget <> 0 THEN
    RAISE EXCEPTION 'KOEN_FEJL: % kandidater uden forventet køn, % uden for reglen sat', v_fejl, v_for_meget;
  END IF;
  RAISE NOTICE 'KOEN_OK: alle kandidater med entydigt udfald er sat, ingen andre er rørt';
END $kontrol$;
-- ===== SLUT-MARKØR (ren SQL) =====

\if :skriv
COMMIT;
\echo 'KOEN: COMMIT'
\else
ROLLBACK;
\echo 'KOEN: ROLLBACK (prøve — kør med -v skriv=1 for at skrive)'
\endif
