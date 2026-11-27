-- Køn for ingifte efter ægteskabsreglen (spec docs/superpowers/specs/2026-11-27-personside-navnevisning-design.md,
-- afsnit »Data: køn for ingifte (prod-skrivning)«).
--
-- Regel: kandidater = person med koen IS NULL og levende IS FALSE (afdøde). Alle kandidatens modparter
-- (partner-rækker i ALLE kandidatens familier, ikke kandidaten selv) samles. Er alle modparter 'mand' -> 'kvinde';
-- er alle 'kvinde' -> 'mand'. Ellers sættes intet: ingen modpart, en modpart med NULL/'ukendt' køn, eller blandede køn.
-- Levende med tomt køn sættes aldrig af reglen (et nutidigt ægteskab kan være mellem to af samme køn); de tælles og
-- listes. Er levende ukendt (NULL), sættes heller intet: udfaldet 'levende_ukendt' (listes). Udfaldet beregnes ÉN gang, før første skrivning (så en kandidat, der er modpart til en anden, ikke ændrer
-- den andens udfald undervejs).
--
-- Skrivevej: red_set_koen(person_id, koen) (kræver current_rolle() = 'redaktion'). Hvert kald kører begin_change_set,
-- som genbruger transaktionens aktive sæt (schema.sql: begin_change_set, `app.change_set_id`) -> ALLE skrivninger
-- lander i ÉT ændringssæt, som kan fortrydes samlet med red_fortryd_change_set(<id>). Sættets id udskrives.
--
-- Output: én jsonb (koen_rapport) med antal og person-id'er (aldrig navne). Redaktørlisten = `ikke_sat`.
--
-- Kørsel via psql (projektejerens shell; aktøren gives som variabel og står aldrig i filen):
--   psql "$DSN" -v redaktoer_uid=<uuid> -f docs/runbooks/2026-11-27-koen-ingifte.sql            -- prøve: ROLLBACK
--   psql "$DSN" -v redaktoer_uid=<uuid> -v skriv=1 -f docs/runbooks/2026-11-27-koen-ingifte.sql -- skriv: COMMIT
-- Kørsel via Supabase MCP execute_sql (returnerer kun rækkerne fra ÉT resultatgivende udsagn; NOTICE returneres ikke):
--   indsæt teksten mellem »BEGIN-MARKØR« og »SLUT-MARKØR«, erstat aktørlinjen (markeret AKTØRLINJE) med
--   SELECT set_config('request.jwt.claim.sub', '<uuid>', true) IS NOT NULL AS aktoer_sat;
--   og tilføj til sidst `ROLLBACK;` (prøve) eller `COMMIT;` (skriv). Rapporten er ÉN jsonb i det sidste SELECT.
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
  WHERE a.rolle = 'partner' AND a.person_id IN (SELECT id FROM person WHERE koen IS NULL)
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
         WHEN p.levende IS NULL THEN 'levende_ukendt'
         WHEN a.kandidat_id IS NULL THEN 'ingen_aegtefaelle'
         WHEN a.n_mand = a.n_modpart THEN 'kvinde'
         WHEN a.n_kvinde = a.n_modpart THEN 'mand'
         WHEN a.n_mand + a.n_kvinde < a.n_modpart THEN 'modpart_ukendt'
         ELSE 'blandet'
       END AS udfald
FROM person p
LEFT JOIN agg a ON a.kandidat_id = p.id
WHERE p.koen IS NULL;

-- Skrivning: ét red_set_koen-kald pr. afdød kandidat med entydigt udfald. Ét navngivet ændringssæt åbnes først
-- (kun hvis der er noget at skrive); red_set_koen genbruger det.
DO $skriv$
DECLARE m record; v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM koen_maal WHERE udfald IN ('kvinde','mand');
  IF v_n > 0 THEN
    PERFORM begin_change_set('red_set_koen', format('Køn for ingifte efter ægteskabsreglen (%s personer)', v_n), NULL, NULL);
    FOR m IN SELECT person_id, udfald FROM koen_maal WHERE udfald IN ('kvinde','mand') ORDER BY person_id LOOP
      PERFORM red_set_koen(m.person_id, m.udfald);
    END LOOP;
  END IF;
END $skriv$;

-- Kontrol: hver person med entydigt udfald har nu præcis det køn; ingen er sat uden for reglen.
DO $kontrol$ DECLARE v_fejl int; v_for_meget int; BEGIN
  SELECT count(*) INTO v_fejl FROM koen_maal m JOIN person p ON p.id = m.person_id
   WHERE m.udfald IN ('kvinde','mand') AND p.koen IS DISTINCT FROM m.udfald;
  SELECT count(*) INTO v_for_meget FROM koen_maal m JOIN person p ON p.id = m.person_id
   WHERE m.udfald NOT IN ('kvinde','mand') AND p.koen IS NOT NULL;
  IF v_fejl <> 0 OR v_for_meget <> 0 THEN
    RAISE EXCEPTION 'KOEN_FEJL: % kandidater uden forventet køn, % uden for reglen sat', v_fejl, v_for_meget;
  END IF;
END $kontrol$;

-- Rapport: ÉN jsonb (kun antal og id'er, aldrig navne). Sidste udsagn før COMMIT/ROLLBACK.
SELECT jsonb_pretty(jsonb_build_object(
  'sat_kvinde', count(*) FILTER (WHERE udfald = 'kvinde'),
  'sat_mand', count(*) FILTER (WHERE udfald = 'mand'),
  'levende_sprunget_over', count(*) FILTER (WHERE udfald = 'levende'),
  'levende_ukendt', count(*) FILTER (WHERE udfald = 'levende_ukendt'),
  'ingen_aegtefaelle', count(*) FILTER (WHERE udfald = 'ingen_aegtefaelle'),
  'modpart_ukendt_koen', count(*) FILTER (WHERE udfald = 'modpart_ukendt'),
  'blandet', count(*) FILTER (WHERE udfald = 'blandet'),
  'change_set_id', nullif(current_setting('app.change_set_id', true), ''),
  'ikke_sat', jsonb_build_object(
    'levende', coalesce(jsonb_agg(person_id ORDER BY person_id) FILTER (WHERE udfald = 'levende'), '[]'),
    'levende_ukendt', coalesce(jsonb_agg(person_id ORDER BY person_id) FILTER (WHERE udfald = 'levende_ukendt'), '[]'),
    'ingen_aegtefaelle', coalesce(jsonb_agg(person_id ORDER BY person_id) FILTER (WHERE udfald = 'ingen_aegtefaelle'), '[]'),
    'modpart_ukendt', coalesce(jsonb_agg(person_id ORDER BY person_id) FILTER (WHERE udfald = 'modpart_ukendt'), '[]'),
    'blandet', coalesce(jsonb_agg(person_id ORDER BY person_id) FILTER (WHERE udfald = 'blandet'), '[]'))
)) AS koen_rapport FROM koen_maal;
-- ===== SLUT-MARKØR (ren SQL) =====

\if :skriv
COMMIT;
\echo 'KOEN: COMMIT'
\else
ROLLBACK;
\echo 'KOEN: ROLLBACK (prøve — kør med -v skriv=1 for at skrive)'
\endif
