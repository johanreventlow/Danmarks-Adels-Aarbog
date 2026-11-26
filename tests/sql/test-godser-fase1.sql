\set ON_ERROR_STOP on

-- Godsernes oprydning, fase 1 (#471). Kør på en frisk base efter schema.sql, db-rls.sql og db-migrations.sql.
-- Alt rulles tilbage. Senere delopgaver tilføjer deres afsnit FØR den afsluttende OK-linje.

BEGIN;

-- ---------- 1. Ordforrådet estate_slags ----------
DO $t1$
DECLARE v_koder text; v_state text; v_msg text; v_antal bigint;
BEGIN
  SELECT string_agg(v.code, ',' ORDER BY v.code COLLATE "C") INTO v_koder FROM public.vocab v WHERE v.scheme = 'estate_slags';
  IF v_koder IS DISTINCT FROM 'baroni,grevskab,gård,stamhus' THEN
    RAISE EXCEPTION 'GODSER_T1: vocab estate_slags er »%«', v_koder;
  END IF;

  INSERT INTO public.estate(navn, slags) VALUES ('__t1_gaard__', 'gård');
  INSERT INTO public.estate(navn, slags) VALUES ('__t1_null__', NULL);
  UPDATE public.estate SET slags = 'stamhus' WHERE navn = '__t1_gaard__';
  UPDATE public.estate SET slags = NULL WHERE navn = '__t1_gaard__';

  -- Ukendt værdi afvises ved INSERT og UPDATE med 23514 og strengen, klienterne matcher på.
  BEGIN
    INSERT INTO public.estate(navn, slags) VALUES ('__t1_gods__', 'gods');
  EXCEPTION WHEN check_violation THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
  END;
  IF v_state IS DISTINCT FROM '23514' OR strpos(v_msg, 'ESTATE_SLAGS_UKENDT') <> 1 THEN
    RAISE EXCEPTION 'GODSER_T1: INSERT med slags »gods« blev ikke afvist med 23514 ESTATE_SLAGS_UKENDT (%, %)', v_state, v_msg;
  END IF;
  v_state := NULL; v_msg := NULL;
  BEGIN
    UPDATE public.estate SET slags = 'len' WHERE navn = '__t1_gaard__';
  EXCEPTION WHEN check_violation THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
  END;
  IF v_state IS DISTINCT FROM '23514' OR strpos(v_msg, 'ESTATE_SLAGS_UKENDT') <> 1 THEN
    RAISE EXCEPTION 'GODSER_T1: UPDATE til slags »len« blev ikke afvist med 23514 ESTATE_SLAGS_UKENDT (%, %)', v_state, v_msg;
  END IF;

  SELECT count(*) INTO v_antal FROM public.estate WHERE navn LIKE '\_\_t1\_%';
  IF v_antal <> 2 THEN RAISE EXCEPTION 'GODSER_T1: forventede 2 fixture-rækker, fandt %', v_antal; END IF;
END
$t1$;

-- NY AFSNIT TILFØJES HER (før OK-linjen).
ROLLBACK;
\echo OK test-godser-fase1
