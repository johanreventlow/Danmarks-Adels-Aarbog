-- =====================================================================
-- Problem 2 — ENGANGS-BACKFILL af forældre-evidens (Fase 4 cutover)
-- =====================================================================
-- Gør de eksisterende 'barn'-rækker (DAA 2018-20-loadet) evidens-eksplicitte: ét slot +
-- assertion (objekt=familie) + citation (source=DAA 2018-20) + afklaret conclusion pr. barn-række
-- uden slot. Set-baseret, idempotent (NOT EXISTS), fail-closed.
--
-- BEVIDST ADSKILT fra db-migrations.sql (review 30): dette er en DELIBERAT engangs-datahandling,
-- ikke en del af den idempotente skema-afstemning. Kør FØRST efter db-migrations.sql er anvendt
-- (kræver assertion.objekt_type/objekt_id + EXCLUDE) OG efter single-edition er bekræftet.
--
-- KØR KUN mod en base hvor ALLE 'barn'-rækker stammer fra DAA 2018-20 (prod / ren single-edition-
-- kopi). Nedenstående prætjek ABORTER hvis en anden udgaves barn-række detekteres — men bekræft
-- ALLIGEVEL manuelt (source-listen) før kørsel mod prod (ingen backup).
DO $$
DECLARE v_src bigint;
BEGIN
  SELECT id INTO STRICT v_src FROM source WHERE udgave = 'DAA 2018-20';  -- 0 el. 2+ → abort (fail-closed)

  -- Multi-edition-detektion (review 30/DB-L3, lukker tidligere fail-open): en barn-række fra en
  -- ANDEN udgave bærer et person_external_id fra dén udgaves source. Findes ét → multi-edition → ABORT
  -- (ellers fejl-citerede backfillen andre udgavers rækker til DAA 2018-20). Best-effort: personer
  -- uden external_id ignoreres (ingen falsk-abort), men mindst én fremmed-udgave-række stopper kørslen.
  IF EXISTS (
    SELECT 1 FROM family_member fm
    JOIN person_external_id pe ON pe.person_id = fm.person_id
    JOIN source s ON s.id = pe.source_id
    WHERE fm.rolle='barn' AND s.udgave IS DISTINCT FROM 'DAA 2018-20'
  ) THEN
    RAISE EXCEPTION 'Backfill afbrudt: barn-rækker med kilde <> ''DAA 2018-20'' fundet -> multi-edition base. Kør KUN mod verificeret single-edition prod/kopi.';
  END IF;

  -- 1) slots for barn-rækker uden slot
  INSERT INTO fact(id, subjekt_type, subjekt_id, faktatype)
  SELECT (SELECT coalesce(max(id),0) FROM fact) + row_number() OVER (ORDER BY d.person_id),
         'person', d.person_id, 'forældrefamilie'
  FROM (SELECT DISTINCT person_id FROM family_member WHERE rolle='barn') d
  WHERE NOT EXISTS (SELECT 1 FROM fact f
    WHERE f.subjekt_type='person' AND f.subjekt_id=d.person_id AND f.faktatype='forældrefamilie');

  -- 2) én assertion pr. slot (objekt = barn-rækkens family_id)
  INSERT INTO assertion(id, target_type, target_id, vaerdi_tekst, objekt_type, objekt_id, uforanderlig)
  SELECT (SELECT coalesce(max(id),0) FROM assertion) + row_number() OVER (ORDER BY f.id),
         'fact', f.id, 'barn', 'family', fm.family_id, true
  FROM fact f
  JOIN family_member fm ON fm.person_id=f.subjekt_id AND fm.rolle='barn'
  WHERE f.subjekt_type='person' AND f.faktatype='forældrefamilie'
    AND NOT EXISTS (SELECT 1 FROM assertion a WHERE a.target_type='fact' AND a.target_id=f.id);

  -- 3) citation (source=DAA 2018-20) pr. slot-assertion uden citation
  INSERT INTO citation(id, assertion_id, source_id, side, citat_tekst, kvalitet)
  SELECT (SELECT coalesce(max(id),0) FROM citation) + row_number() OVER (ORDER BY a.id),
         a.id, v_src, NULL,
         '(bagudkonverteret: slægtskab loadet fra DAA 2018-20 uden per-række-citat)', 'primær'
  FROM assertion a
  JOIN fact f ON f.id=a.target_id AND a.target_type='fact'
  WHERE f.subjekt_type='person' AND f.faktatype='forældrefamilie' AND a.objekt_type='family'
    AND NOT EXISTS (SELECT 1 FROM citation c WHERE c.assertion_id=a.id);

  -- 4) afklaret conclusion pr. slot uden conclusion (valgt = slot-assertionen)
  INSERT INTO conclusion(id, target_type, target_id, valgt_assertion_id, status, blaastemplet_af, blaastemplet_naar)
  SELECT (SELECT coalesce(max(id),0) FROM conclusion) + row_number() OVER (ORDER BY f.id),
         'fact', f.id, a.id, 'afklaret', 'DAA 2018-20 (backfill af forældre-evidens)', current_date
  FROM fact f
  JOIN assertion a ON a.target_type='fact' AND a.target_id=f.id AND a.objekt_type='family'
  WHERE f.subjekt_type='person' AND f.faktatype='forældrefamilie'
    AND NOT EXISTS (SELECT 1 FROM conclusion c WHERE c.target_type='fact' AND c.target_id=f.id);

  RAISE NOTICE 'Backfill færdig: forældre-evidens for alle DAA 2018-20 barn-rækker.';
END $$;
