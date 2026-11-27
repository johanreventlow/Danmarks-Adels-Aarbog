-- Skilsmissedatoer fra biografierne (spec docs/superpowers/specs/2026-11-27-personside-navnevisning-design.md,
-- afsnit »Skilsmisse — vises, hvor ægteskabet vises« -> »Datoerne (prod-skrivning)«).
--
-- Kandidater: 'skilsmisse'-fakta på familier, hvis afklarede konklusions valgte påstand har date_min IS NULL (i dag
-- alle med date_raw 'skilt'). Udgaven = source på den valgte påstands citation; den slås op på source.udgave
-- ('DAA 2018-20' / 'DAA 1939'), aldrig på et fast id.
-- Partnere: family_member rolle 'partner'. Kun partnere, der er partner i PRÆCIS ÉN familie med et skilsmisse-fakta, tæller.
-- Tekst: narrative (person, source = udgaven) på de tællende partnere; mønstret
--   (?:skilt|ægteskabet (?:er )?opløst|ægteskabet ophævet)\s+(<dag måned år>|<år>)   (store/små bogstaver ligegyldigt)
-- Fortolkning: »12. okt. 1901« -> date_min = date_max = dagen (måned = de tre første bogstaver: jan feb mar apr maj jun
--   jul aug sep okt nov dec); »1901« -> 1901-01-01..1901-12-31. date_raw = den fundne tekst ordret. Ukendt måned eller
--   ugyldig dag -> udfaldet 'ukendt_maaned'.
-- Skriver kun ved: præcis ÉN distinkt fortolket dato (på tværs af begge partnere), og hvis vielsen har en dato
--   (afklaret valgt påstand), er den nye date_min >= vielsens date_min (ellers 'foer_vielse').
-- Skrivevej: red_upsert_fakta('family', fam, 'skilsmisse', NULL, dmin, dmax, NULL, raw, 'Dansk Adels Aarbog <udgave>, biografien')
--   -> ny påstand + fritekst-citation, og den afklarede konklusion peges om; den gamle »skilt«-påstand bliver stående
--   (invariant 1). Et navngivet ændringssæt åbnes først (kun hvis der skal skrives); alle skrivninger lander i det og
--   kan fortrydes samlet med red_fortryd_change_set(<id>).
-- Ekstra udfald ud over specens: 'flere_fakta' (familien har mere end ét skilsmisse-fakta; red_upsert_fakta ville
--   ramme et vilkårligt) — springes over og listes.
--
-- Output: ÉN jsonb (skilsmisse_rapport) med antal og familie-id'er. ALDRIG datoer, navne eller tekst (nogle
-- biografier handler om levende). Redaktørlisten = ikke_skrevet.
--
-- Kørsel via psql (projektejerens shell; aktøren gives som variabel og står aldrig i filen):
--   psql "$DSN" -v redaktoer_uid=<uuid> -f docs/runbooks/2026-11-27-skilsmissedatoer.sql            -- prøve: ROLLBACK
--   psql "$DSN" -v redaktoer_uid=<uuid> -v skriv=1 -f docs/runbooks/2026-11-27-skilsmissedatoer.sql -- skriv: COMMIT
-- Kørsel via Supabase MCP execute_sql (returnerer kun rækkerne fra ÉT resultatgivende udsagn; NOTICE returneres ikke):
--   indsæt teksten mellem »BEGIN-MARKØR« og »SLUT-MARKØR«, erstat aktørlinjen (markeret AKTØRLINJE) med
--   SELECT set_config('request.jwt.claim.sub', '<uuid>', true) IS NOT NULL AS aktoer_sat;
--   og tilføj til sidst `ROLLBACK;` (prøve) eller `COMMIT;` (skriv). Rapporten er ÉN jsonb i det sidste SELECT.
-- Idempotent: efter en skrivning har familien date_min på den valgte påstand og er ikke længere kandidat -> 0 ved gentagelse.
\set ON_ERROR_STOP on
\if :{?skriv}
\else
  \set skriv false
\endif
\if :{?redaktoer_uid}
\else
  \echo 'SKILSMISSE_FEJL: angiv -v redaktoer_uid=<uuid>'
  SELECT 1/0 AS mangler_redaktoer_uid;
\endif

-- ===== BEGIN-MARKØR (ren SQL herfra) =====
BEGIN;
SELECT set_config('request.jwt.claim.sub', :'redaktoer_uid', true) IS NOT NULL AS aktoer_sat;  -- AKTØRLINJE

DO $aktoer$ BEGIN
  IF current_rolle() <> 'redaktion' THEN
    RAISE EXCEPTION 'SKILSMISSE_FEJL: aktøren har ikke rollen redaktion (rolle: %)', current_rolle();
  END IF;
END $aktoer$;

-- Alle skilsmisse-fakta på familier (også dem uden kandidatstatus: de tæller med i »partner i præcis én skilt familie«).
CREATE TEMP TABLE skil_alle ON COMMIT DROP AS
SELECT f.id AS fact_id, f.subjekt_id AS fam_id,
       count(*) OVER (PARTITION BY f.subjekt_id) AS n_fakta,
       a.id AS paastand_id, a.date_min AS paastand_dmin
FROM fact f
LEFT JOIN conclusion c ON c.target_type = 'fact' AND c.target_id = f.id AND c.status = 'afklaret'
LEFT JOIN assertion a ON a.id = c.valgt_assertion_id
WHERE f.subjekt_type = 'family' AND f.faktatype = 'skilsmisse';

-- Kandidater: afklaret valgt påstand uden date_min.
CREATE TEMP TABLE skil_kand ON COMMIT DROP AS
SELECT * FROM skil_alle WHERE paastand_id IS NOT NULL AND paastand_dmin IS NULL;

-- Hvor mange skilte familier hver partner indgår i.
CREATE TEMP TABLE skil_partner ON COMMIT DROP AS
SELECT fm.family_id AS fam_id, fm.person_id,
       (SELECT count(DISTINCT x.fam_id) FROM skil_alle x
          JOIN family_member y ON y.family_id = x.fam_id AND y.rolle = 'partner'
         WHERE y.person_id = fm.person_id) AS n_skilte
FROM family_member fm
WHERE fm.rolle = 'partner' AND fm.family_id IN (SELECT fam_id FROM skil_kand);

-- Udgaver pr. kandidat: kilden på den valgte påstands citation, kun de to kendte DAA-udgaver (opslag på udgave-teksten).
CREATE TEMP TABLE skil_udgave ON COMMIT DROP AS
SELECT DISTINCT k.fam_id, s.id AS source_id, s.udgave
FROM skil_kand k
JOIN citation ci ON ci.assertion_id = k.paastand_id
JOIN source s ON s.id = ci.source_id AND s.udgave IN ('DAA 2018-20', 'DAA 1939');

-- Fund: hver fundet datotekst (distinkt pr. familie, tekst og udgave). Fortolkningen udfyldes nedenfor.
CREATE TEMP TABLE skil_fund ON COMMIT DROP AS
SELECT row_number() OVER (ORDER BY fam_id, udgave, raw) AS id, fam_id, udgave, raw,
       NULL::date AS dmin, NULL::date AS dmax, false AS gyldig
FROM (
  SELECT DISTINCT p.fam_id, u.udgave, m[1] AS raw
  FROM skil_partner p
  JOIN skil_udgave u ON u.fam_id = p.fam_id
  JOIN narrative n ON n.subjekt_type = 'person' AND n.subjekt_id = p.person_id AND n.source_id = u.source_id
  CROSS JOIN LATERAL regexp_matches(n.tekst,
    '(?:skilt|ægteskabet (?:er )?opløst|ægteskabet ophævet)\s+(\d{1,2}\.?\s*[A-Za-zæøåÆØÅ]+\.?\s+\d{4}|\d{4})', 'gi') AS m
  WHERE p.n_skilte = 1
) t;

DO $fortolk$
DECLARE r record; m text[]; v_md int; v_d date;
BEGIN
  FOR r IN SELECT id, raw FROM skil_fund LOOP
    BEGIN
      IF r.raw ~ '^\d{4}$' THEN
        UPDATE skil_fund SET dmin = make_date(r.raw::int, 1, 1), dmax = make_date(r.raw::int, 12, 31), gyldig = true WHERE id = r.id;
      ELSE
        m := regexp_match(r.raw, '^(\d{1,2})\.?\s*([A-Za-zæøåÆØÅ]+)\.?\s+(\d{4})$');
        IF m IS NOT NULL THEN
          v_md := CASE lower(left(m[2], 3))
            WHEN 'jan' THEN 1 WHEN 'feb' THEN 2 WHEN 'mar' THEN 3 WHEN 'apr' THEN 4 WHEN 'maj' THEN 5 WHEN 'jun' THEN 6
            WHEN 'jul' THEN 7 WHEN 'aug' THEN 8 WHEN 'sep' THEN 9 WHEN 'okt' THEN 10 WHEN 'nov' THEN 11 WHEN 'dec' THEN 12
          END;
          IF v_md IS NOT NULL THEN
            v_d := make_date(m[3]::int, v_md, m[1]::int);
            UPDATE skil_fund SET dmin = v_d, dmax = v_d, gyldig = true WHERE id = r.id;
          END IF;
        END IF;
      END IF;
    EXCEPTION WHEN others THEN
      NULL;  -- ugyldig dag/år: forbliver gyldig = false -> 'ukendt_maaned'
    END;
  END LOOP;
END $fortolk$;

-- Udfald pr. kandidat-familie, beregnet før nogen skrivning.
CREATE TEMP TABLE skil_udfald ON COMMIT DROP AS
WITH agg AS (
  SELECT k.fam_id, k.n_fakta,
    (SELECT count(*) FROM skil_partner p WHERE p.fam_id = k.fam_id) AS n_partner,
    (SELECT count(*) FROM skil_partner p WHERE p.fam_id = k.fam_id AND p.n_skilte = 1) AS n_ok,
    (SELECT count(*) FROM skil_partner p
       JOIN skil_udgave u ON u.fam_id = p.fam_id
       JOIN narrative n ON n.subjekt_type = 'person' AND n.subjekt_id = p.person_id AND n.source_id = u.source_id
      WHERE p.fam_id = k.fam_id AND p.n_skilte = 1) AS n_narr,
    (SELECT count(*) FROM skil_fund f WHERE f.fam_id = k.fam_id) AS n_fund,
    (SELECT count(*) FROM skil_fund f WHERE f.fam_id = k.fam_id AND NOT f.gyldig) AS n_ukendt,
    (SELECT count(DISTINCT (f.dmin, f.dmax)) FROM skil_fund f WHERE f.fam_id = k.fam_id AND f.gyldig) AS n_dist,
    (SELECT min(f.dmin) FROM skil_fund f WHERE f.fam_id = k.fam_id AND f.gyldig) AS dmin,
    (SELECT min(f.dmax) FROM skil_fund f WHERE f.fam_id = k.fam_id AND f.gyldig) AS dmax,
    (SELECT (array_agg(f.raw ORDER BY f.udgave, f.raw))[1] FROM skil_fund f WHERE f.fam_id = k.fam_id AND f.gyldig) AS raw,
    (SELECT (array_agg(f.udgave ORDER BY f.udgave, f.raw))[1] FROM skil_fund f WHERE f.fam_id = k.fam_id AND f.gyldig) AS udgave,
    (SELECT max(va.date_min) FROM fact vf
       JOIN conclusion vc ON vc.target_type = 'fact' AND vc.target_id = vf.id AND vc.status = 'afklaret'
       JOIN assertion va ON va.id = vc.valgt_assertion_id
      WHERE vf.subjekt_type = 'family' AND vf.subjekt_id = k.fam_id AND vf.faktatype = 'vielse') AS vielse_dmin
  FROM skil_kand k
)
SELECT fam_id,
       CASE
         WHEN n_fakta > 1 THEN 'flere_fakta'
         WHEN n_ok = 0 AND n_partner > 0 THEN 'flere_skilte_familier'
         WHEN n_ok = 0 OR n_narr = 0 THEN 'ingen_biografi'
         WHEN n_fund = 0 THEN 'uden_dato'
         WHEN n_ukendt > 0 THEN 'ukendt_maaned'
         WHEN n_dist > 1 THEN 'flertydig'
         WHEN vielse_dmin IS NOT NULL AND dmin < vielse_dmin THEN 'foer_vielse'
         ELSE 'skrevet'
       END AS udfald,
       dmin, dmax, raw,
       'Dansk Adels Aarbog ' || regexp_replace(coalesce(udgave, ''), '^DAA\s+', '') || ', biografien' AS kilde
FROM agg;

-- Skrivning: ét red_upsert_fakta-kald pr. 'skrevet' familie. Ét navngivet ændringssæt åbnes først (kun hvis der er
-- noget at skrive); red_upsert_fakta genbruger det.
DO $skriv$
DECLARE m record; v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM skil_udfald WHERE udfald = 'skrevet';
  IF v_n > 0 THEN
    PERFORM begin_change_set('red_upsert_fakta', format('Skilsmissedatoer fra biografierne (%s familier)', v_n), NULL, NULL);
    FOR m IN SELECT * FROM skil_udfald WHERE udfald = 'skrevet' ORDER BY fam_id LOOP
      PERFORM red_upsert_fakta('family', m.fam_id, 'skilsmisse', NULL, m.dmin, m.dmax, NULL, m.raw, m.kilde);
    END LOOP;
  END IF;
END $skriv$;

-- Kontrol: hver 'skrevet' familie har nu en valgt, afklaret påstand med præcis den fortolkede dato; ingen anden
-- kandidat er rørt (deres valgte påstand har stadig ingen date_min).
DO $kontrol$ DECLARE v_fejl int; v_for_meget int; BEGIN
  SELECT count(*) INTO v_fejl FROM skil_udfald u
   WHERE u.udfald = 'skrevet' AND NOT EXISTS (
     SELECT 1 FROM fact f
       JOIN conclusion c ON c.target_type = 'fact' AND c.target_id = f.id AND c.status = 'afklaret'
       JOIN assertion a ON a.id = c.valgt_assertion_id
      WHERE f.subjekt_type = 'family' AND f.subjekt_id = u.fam_id AND f.faktatype = 'skilsmisse'
        AND a.date_min IS NOT DISTINCT FROM u.dmin AND a.date_max IS NOT DISTINCT FROM u.dmax AND a.date_min IS NOT NULL);
  SELECT count(*) INTO v_for_meget FROM skil_udfald u
   WHERE u.udfald <> 'skrevet' AND EXISTS (
     SELECT 1 FROM fact f
       JOIN conclusion c ON c.target_type = 'fact' AND c.target_id = f.id
       JOIN assertion a ON a.id = c.valgt_assertion_id
      WHERE f.subjekt_type = 'family' AND f.subjekt_id = u.fam_id AND f.faktatype = 'skilsmisse' AND a.date_min IS NOT NULL);
  IF v_fejl <> 0 OR v_for_meget <> 0 THEN
    RAISE EXCEPTION 'SKILSMISSE_FEJL: % skrevne familier uden forventet dato, % uskrevne rørt', v_fejl, v_for_meget;
  END IF;
END $kontrol$;

-- Rapport: ÉN jsonb (kun antal og id'er, aldrig datoer/navne/tekst). Sidste udsagn før COMMIT/ROLLBACK.
SELECT jsonb_pretty(jsonb_build_object(
  'kandidater', count(*),
  'skrevet', count(*) FILTER (WHERE udfald = 'skrevet'),
  'flertydig', count(*) FILTER (WHERE udfald = 'flertydig'),
  'uden_dato', count(*) FILTER (WHERE udfald = 'uden_dato'),
  'ingen_biografi', count(*) FILTER (WHERE udfald = 'ingen_biografi'),
  'flere_skilte_familier', count(*) FILTER (WHERE udfald = 'flere_skilte_familier'),
  'foer_vielse', count(*) FILTER (WHERE udfald = 'foer_vielse'),
  'ukendt_maaned', count(*) FILTER (WHERE udfald = 'ukendt_maaned'),
  'flere_fakta', count(*) FILTER (WHERE udfald = 'flere_fakta'),
  'change_set_id', nullif(current_setting('app.change_set_id', true), ''),
  'skrevet_familier', coalesce(jsonb_agg(fam_id ORDER BY fam_id) FILTER (WHERE udfald = 'skrevet'), '[]'),
  'ikke_skrevet', jsonb_build_object(
    'flertydig', coalesce(jsonb_agg(fam_id ORDER BY fam_id) FILTER (WHERE udfald = 'flertydig'), '[]'),
    'uden_dato', coalesce(jsonb_agg(fam_id ORDER BY fam_id) FILTER (WHERE udfald = 'uden_dato'), '[]'),
    'ingen_biografi', coalesce(jsonb_agg(fam_id ORDER BY fam_id) FILTER (WHERE udfald = 'ingen_biografi'), '[]'),
    'flere_skilte_familier', coalesce(jsonb_agg(fam_id ORDER BY fam_id) FILTER (WHERE udfald = 'flere_skilte_familier'), '[]'),
    'foer_vielse', coalesce(jsonb_agg(fam_id ORDER BY fam_id) FILTER (WHERE udfald = 'foer_vielse'), '[]'),
    'ukendt_maaned', coalesce(jsonb_agg(fam_id ORDER BY fam_id) FILTER (WHERE udfald = 'ukendt_maaned'), '[]'),
    'flere_fakta', coalesce(jsonb_agg(fam_id ORDER BY fam_id) FILTER (WHERE udfald = 'flere_fakta'), '[]'))
)) AS skilsmisse_rapport FROM skil_udfald;
-- ===== SLUT-MARKØR (ren SQL) =====

\if :skriv
COMMIT;
\echo 'SKILSMISSE: COMMIT'
\else
ROLLBACK;
\echo 'SKILSMISSE: ROLLBACK (prøve — kør med -v skriv=1 for at skrive)'
\endif
