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

-- ---------- 2. Relationerne hører_under og sammenlagt_i (trg_estate_relation_vagt) ----------
-- Hjælper: kør sætningen og kræv 23514 med koden forrest i fejlteksten.
CREATE FUNCTION pg_temp.g471_afvist(p_sql text, p_kode text, p_hvad text) RETURNS void LANGUAGE plpgsql AS $f$
DECLARE v_state text; v_msg text;
BEGIN
  BEGIN
    EXECUTE p_sql;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
  END;
  IF v_state IS DISTINCT FROM '23514' OR strpos(v_msg, p_kode) <> 1 THEN
    RAISE EXCEPTION 'GODSER_T2: % blev ikke afvist med 23514 % (fik %, %)', p_hvad, p_kode, v_state, v_msg;
  END IF;
END
$f$;

DO $t2$
DECLARE
  g1 bigint; g2 bigint; g3 bigint; m1 bigint; m2 bigint; n1 bigint;
  a bigint; b bigint; c bigint; d bigint; e bigint; f bigint; z bigint;
  p bigint; md bigint; v_hu bigint; v_sam bigint; v_rel bigint; v_ejer bigint; v_antal bigint;
BEGIN
  INSERT INTO public.estate(navn, slags) VALUES ('__t2_g1__','gård') RETURNING id INTO g1;
  INSERT INTO public.estate(navn, slags) VALUES ('__t2_g2__','gård') RETURNING id INTO g2;
  INSERT INTO public.estate(navn, slags) VALUES ('__t2_g3__','gård') RETURNING id INTO g3;
  INSERT INTO public.estate(navn, slags) VALUES ('__t2_m1__','grevskab') RETURNING id INTO m1;
  INSERT INTO public.estate(navn, slags) VALUES ('__t2_m2__','baroni') RETURNING id INTO m2;
  INSERT INTO public.estate(navn, slags) VALUES ('__t2_n1__',NULL) RETURNING id INTO n1;
  INSERT INTO public.estate(navn, slags) VALUES ('__t2_a__','gård') RETURNING id INTO a;
  INSERT INTO public.estate(navn, slags) VALUES ('__t2_b__','gård') RETURNING id INTO b;
  INSERT INTO public.estate(navn, slags) VALUES ('__t2_c__',NULL) RETURNING id INTO c;
  INSERT INTO public.estate(navn, slags) VALUES ('__t2_d__',NULL) RETURNING id INTO d;
  INSERT INTO public.estate(navn, slags) VALUES ('__t2_e__',NULL) RETURNING id INTO e;
  INSERT INTO public.estate(navn, slags) VALUES ('__t2_f__','gård') RETURNING id INTO f;
  INSERT INTO public.estate(navn, slags) VALUES ('__t2_z__',NULL) RETURNING id INTO z;
  INSERT INTO public.person DEFAULT VALUES RETURNING id INTO p;
  INSERT INTO public.media(slags) VALUES ('gods') RETURNING id INTO md;

  -- (a) Lovlig hører_under: gård → grevskab og gård → baroni.
  INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle)
    VALUES ('estate',g1,'estate',m1,'hører_under') RETURNING id INTO v_hu;
  INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle)
    VALUES ('estate',g2,'estate',m2,'hører_under');

  -- (b) Endepunkter: begge skal være estate og findes — også når ingen ende er estate.
  PERFORM pg_temp.g471_afvist(format($s$INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle)
    VALUES ('person',%s,'estate',%s,'hører_under')$s$, p, m1), 'ESTATE_RELATION_ENDEPUNKT', 'hører_under person → gods');
  PERFORM pg_temp.g471_afvist(format($s$INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle)
    VALUES ('estate',%s,'media',%s,'sammenlagt_i')$s$, c, md), 'ESTATE_RELATION_ENDEPUNKT', 'sammenlagt_i gods → media');
  PERFORM pg_temp.g471_afvist(format($s$INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle)
    VALUES ('person',%s,'person',%s,'sammenlagt_i')$s$, p, p), 'ESTATE_RELATION_ENDEPUNKT', 'sammenlagt_i person → person');
  PERFORM pg_temp.g471_afvist(format($s$INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle)
    VALUES ('estate',%s,'estate',-987650001,'hører_under')$s$, g3), 'ESTATE_RELATION_ENDEPUNKT', 'hører_under til et gods, der ikke findes');
  PERFORM pg_temp.g471_afvist(format($s$INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle)
    VALUES ('estate',-987650001,'estate',%s,'sammenlagt_i')$s$, c), 'ESTATE_RELATION_ENDEPUNKT', 'sammenlagt_i fra et gods, der ikke findes');
  -- UPDATE af typen (ikke kun id/rolle) rammes også.
  PERFORM pg_temp.g471_afvist(format($s$UPDATE public.relation SET subjekt_type = 'person', subjekt_id = %s WHERE id = %s$s$, p, v_hu),
    'ESTATE_RELATION_ENDEPUNKT', 'UPDATE af hører_under til en person-ende');

  -- (c) Selvreference.
  PERFORM pg_temp.g471_afvist(format($s$INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle)
    VALUES ('estate',%1$s,'estate',%1$s,'hører_under')$s$, g3), 'ESTATE_RELATION_SELV', 'hører_under til sig selv');
  PERFORM pg_temp.g471_afvist(format($s$INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle)
    VALUES ('estate',%1$s,'estate',%1$s,'sammenlagt_i')$s$, c), 'ESTATE_RELATION_SELV', 'sammenlagt_i i sig selv');

  -- (d) hører_under kræver gård → majorat.
  PERFORM pg_temp.g471_afvist(format($s$INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle)
    VALUES ('estate',%s,'estate',%s,'hører_under')$s$, m1, m2), 'ESTATE_HOERER_UNDER_ART', 'grevskab hører under baroni');
  PERFORM pg_temp.g471_afvist(format($s$INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle)
    VALUES ('estate',%s,'estate',%s,'hører_under')$s$, g3, g2), 'ESTATE_HOERER_UNDER_ART', 'gård hører under gård');
  PERFORM pg_temp.g471_afvist(format($s$INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle)
    VALUES ('estate',%s,'estate',%s,'hører_under')$s$, g3, n1), 'ESTATE_HOERER_UNDER_ART', 'gård hører under gods uden art');
  PERFORM pg_temp.g471_afvist(format($s$INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle)
    VALUES ('estate',%s,'estate',%s,'hører_under')$s$, n1, m1), 'ESTATE_HOERER_UNDER_ART', 'gods uden art hører under grevskab');
  INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle)
    VALUES ('estate',g3,'estate',g2,'nabo_til') RETURNING id INTO v_rel;
  PERFORM pg_temp.g471_afvist(format($s$UPDATE public.relation SET rolle = 'hører_under' WHERE id = %s$s$, v_rel),
    'ESTATE_HOERER_UNDER_ART', 'UPDATE af rolle til hører_under gård → gård');

  -- (e) Lovlig sammenlagt_i: a lægges sammen i b.
  INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle)
    VALUES ('estate',a,'estate',b,'sammenlagt_i') RETURNING id INTO v_sam;
  -- En no-op-UPDATE af alle kolonner og fortrydelsens genskrivning (_version_upsert_row) af den lovlige række går igennem.
  UPDATE public.relation SET subjekt_type = subjekt_type, subjekt_id = subjekt_id, objekt_type = objekt_type,
         objekt_id = objekt_id, rolle = rolle, konfidens = konfidens WHERE id = v_sam;
  PERFORM public._version_upsert_row('relation', (SELECT to_jsonb(r) FROM public.relation r WHERE r.id = v_sam));

  -- (f) Højst én sammenlagt_i pr. række.
  PERFORM pg_temp.g471_afvist(format($s$INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle)
    VALUES ('estate',%s,'estate',%s,'sammenlagt_i')$s$, a, c), 'ESTATE_SAMMENLAGT_TO_GANGE', 'anden sammenlagt_i for samme række');

  -- (g) Ingen kæde: målet er ikke selv sammenlagt, og en række, der har fået andre lagt ind i sig, lægges ikke videre.
  PERFORM pg_temp.g471_afvist(format($s$INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle)
    VALUES ('estate',%s,'estate',%s,'sammenlagt_i')$s$, d, a), 'ESTATE_SAMMENLAGT_KAEDE', 'sammenlagt_i ind i en sammenlagt række');
  PERFORM pg_temp.g471_afvist(format($s$INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle)
    VALUES ('estate',%s,'estate',%s,'sammenlagt_i')$s$, b, c), 'ESTATE_SAMMENLAGT_KAEDE', 'sammenlagt_i af en række, der er mål for en anden');

  -- (h) En række lægges kun sammen, når den ikke har andre koblinger tilbage (de flyttes først; Task 4).
  INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle)
    VALUES ('person',p,'estate',e,'ejer');
  PERFORM pg_temp.g471_afvist(format($s$INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle)
    VALUES ('estate',%s,'estate',%s,'sammenlagt_i')$s$, e, c), 'ESTATE_SAMMENLAGT_HAR_KOBLINGER', 'sammenlagt_i af en række med et ejerforhold');
  PERFORM pg_temp.g471_afvist(format($s$INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle)
    VALUES ('estate',%s,'estate',%s,'sammenlagt_i')$s$, g1, c), 'ESTATE_SAMMENLAGT_HAR_KOBLINGER', 'sammenlagt_i af en gård, der hører under et majorat');

  -- (i) Ingen kobling til en sammenlagt række: ejerforhold, billede, hører_under, og UPDATE der flytter en kobling dertil.
  PERFORM pg_temp.g471_afvist(format($s$INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle)
    VALUES ('person',%s,'estate',%s,'ejer')$s$, p, a), 'ESTATE_ER_SAMMENLAGT', 'ejerforhold til en sammenlagt række');
  PERFORM pg_temp.g471_afvist(format($s$INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle)
    VALUES ('media',%s,'estate',%s,'afbildet')$s$, md, a), 'ESTATE_ER_SAMMENLAGT', 'billede af en sammenlagt række');
  PERFORM pg_temp.g471_afvist(format($s$INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle)
    VALUES ('estate',%s,'estate',%s,'hører_under')$s$, a, m1), 'ESTATE_ER_SAMMENLAGT', 'sammenlagt gård hører under grevskab');
  -- Et billede på c (ikke sammenlagt) og et ejerforhold på c går igennem (eksisterende skriveveje).
  INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle)
    VALUES ('media',md,'estate',c,'afbildet');
  INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle)
    VALUES ('person',p,'estate',c,'ejer') RETURNING id INTO v_ejer;
  PERFORM pg_temp.g471_afvist(format($s$UPDATE public.relation SET objekt_id = %s WHERE id = %s$s$, a, v_ejer),
    'ESTATE_ER_SAMMENLAGT', 'UPDATE der flytter et ejerforhold til en sammenlagt række');
  -- En lovlig UPDATE af rolle til sammenlagt_i: f har ingen andre koblinger end netop denne række.
  INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle)
    VALUES ('estate',f,'estate',c,'nabo_til') RETURNING id INTO v_rel;
  UPDATE public.relation SET rolle = 'sammenlagt_i' WHERE id = v_rel;

  -- (j) Væk fra en sammenlagt række og sletning er altid tilladt (vagten ser kun NEW). En snavset række lægges ind
  -- uden om triggerne og flyttes derefter væk; en anden slettes.
  SET LOCAL session_replication_role = replica;
  INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle)
    VALUES ('person',p,'estate',a,'ejer') RETURNING id INTO v_rel;
  INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle)
    VALUES ('media',md,'estate',a,'afbildet') RETURNING id INTO v_ejer;
  SET LOCAL session_replication_role = origin;
  UPDATE public.relation SET objekt_id = z WHERE id = v_rel;
  DELETE FROM public.relation WHERE id = v_ejer;

  -- (k) Når sammenlagt_i fjernes (fortryd), kan rækken kobles igen.
  DELETE FROM public.relation WHERE id = v_sam;
  INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle)
    VALUES ('person',p,'estate',a,'ejer');

  SELECT count(*) INTO v_antal FROM public.relation r
   WHERE r.rolle IN ('hører_under','sammenlagt_i') AND r.subjekt_type = 'estate'
     AND r.subjekt_id IN (g1,g2,g3,m1,m2,n1,a,b,c,d,e,f,z);
  IF v_antal <> 3 THEN RAISE EXCEPTION 'GODSER_T2: forventede 3 nye relationer (2 hører_under, 1 sammenlagt_i), fandt %', v_antal; END IF;
END
$t2$;

-- NY AFSNIT TILFØJES HER (før OK-linjen).
ROLLBACK;
\echo OK test-godser-fase1
