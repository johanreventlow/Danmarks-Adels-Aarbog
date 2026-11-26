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
  p bigint; md bigint; v_hu bigint; v_sam bigint; v_rel bigint; v_ejer bigint; v_antal bigint; v_gemt jsonb;
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

  -- (j2) Fortrydelsens genindsættelse (_version_upsert_row, INSERT … ON CONFLICT-grenen) af et slettet ejerforhold til en
  -- række, der siden er lagt sammen, afvises (Task 4 (f)).
  INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle)
    VALUES ('person',p,'estate',d,'ejer') RETURNING id INTO v_rel;
  SELECT to_jsonb(r) INTO v_gemt FROM public.relation r WHERE r.id = v_rel;
  DELETE FROM public.relation WHERE id = v_rel;
  INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle)
    VALUES ('estate',d,'estate',c,'sammenlagt_i');
  PERFORM pg_temp.g471_afvist(format($s$SELECT public._version_upsert_row('relation', %L::jsonb)$s$, v_gemt::text),
    'ESTATE_ER_SAMMENLAGT', 'fortrydelsens genindsættelse af et ejerforhold til en sammenlagt række');
  IF EXISTS (SELECT 1 FROM public.relation r WHERE r.id = v_rel) THEN
    RAISE EXCEPTION 'GODSER_T2: det afviste ejerforhold % blev genindsat', v_rel;
  END IF;
  DELETE FROM public.relation WHERE subjekt_type = 'estate' AND subjekt_id = d AND rolle = 'sammenlagt_i';

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

-- ---------- 3. Omdøb gods og flyt ejerforhold/billede (red_saet_estate, red_flyt_estate_relation) ----------
-- Kalderne (anon, authenticated uden profil, medlem, redaktion) fra den fælles fixture.
\ir fixtures/kalder-matrix.sql
SELECT pg_temp.km_kaldere();

-- Kør p_sql som p_kalder (rolle OG uid, som kalder-matrix) i et frisk ændringssæt; returnér sættets id (NULL = intet sæt).
-- Fejler sætningen, rulles rolle og uid tilbage med undertransaktionen hos kalderen (g471_afvist/g471_afvist_som).
CREATE FUNCTION pg_temp.g471_som(p_kalder text, p_sql text) RETURNS bigint LANGUAGE plpgsql AS $f$
DECLARE v_uid text; v_cs text;
BEGIN
  v_uid := CASE p_kalder WHEN 'gaest' THEN ''
                         WHEN 'uden_profil' THEN '11000000-0000-0000-0000-00000000ca01'
                         WHEN 'medlem' THEN '11000000-0000-0000-0000-00000000ca02'
                         WHEN 'redaktion' THEN '11000000-0000-0000-0000-00000000ca03' END;
  PERFORM set_config('app.change_set_id', '', true);
  PERFORM set_config('request.jwt.claim.sub', v_uid, true);
  EXECUTE format('SET LOCAL ROLE %I', CASE WHEN p_kalder = 'gaest' THEN 'anon' ELSE 'authenticated' END);
  EXECUTE p_sql;
  RESET ROLE;
  PERFORM set_config('request.jwt.claim.sub', '', true);
  v_cs := nullif(current_setting('app.change_set_id', true), '');
  PERFORM set_config('app.change_set_id', '', true);
  RETURN v_cs::bigint;
END
$f$;

-- Kræv en bestemt SQLSTATE og (valgfrit) en tekst forrest i fejlen, når p_sql køres som p_kalder.
CREATE FUNCTION pg_temp.g471_afvist_som(p_kalder text, p_sql text, p_state text, p_kode text, p_hvad text)
RETURNS void LANGUAGE plpgsql AS $f$
DECLARE v_state text; v_msg text;
BEGIN
  BEGIN
    PERFORM pg_temp.g471_som(p_kalder, p_sql);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
  END;
  IF v_state IS DISTINCT FROM p_state OR (p_kode IS NOT NULL AND strpos(v_msg, p_kode) <> 1) THEN
    RAISE EXCEPTION 'GODSER_T3: % som % blev ikke afvist med % % (fik %, %)', p_hvad, p_kalder, p_state, p_kode, v_state, v_msg;
  END IF;
  IF current_user <> session_user THEN
    RAISE EXCEPTION 'GODSER_T3: rollen blev ikke nulstillet efter %', p_hvad;
  END IF;
END
$f$;

DO $t3$
DECLARE
  e1 bigint; e2 bigint; e3 bigint; es bigint; eg bigint; em bigint; ex bigint;
  p bigint; md bigint; src bigint; f_lok bigint; nar bigint; hd bigint;
  r1 bigint; r2 bigint; r_fp bigint; r_afb bigint; r_samme bigint; r_flyt bigint; r_hu bigint;
  a1 bigint; a2 bigint; a_fp bigint; a_lok bigint; a_flyt bigint;
  c1 bigint; c1b bigint; c2 bigint; c_fp bigint; c_lok bigint; c_flyt bigint;
  v_cs bigint; v_antal bigint; v_txt text; v_slags text; k text;
BEGIN
  INSERT INTO public.source(slags, titel) VALUES ('bog', '__t3_kilde__') RETURNING id INTO src;
  INSERT INTO public.estate(navn, slags) VALUES ('__t3_Christianssæde (med Pederstrup)__', NULL) RETURNING id INTO e1;
  INSERT INTO public.estate(navn, slags) VALUES ('__t3_Wittenberg__', 'gård') RETURNING id INTO e2;
  INSERT INTO public.estate(navn, slags) VALUES ('__t3_Wittenberg (dublet)__', 'gård') RETURNING id INTO e3;
  INSERT INTO public.estate(navn, slags) VALUES ('__t3_sammenlagt__', NULL) RETURNING id INTO es;
  INSERT INTO public.estate(navn, slags) VALUES ('__t3_gaard__', 'gård') RETURNING id INTO eg;
  INSERT INTO public.estate(navn, slags) VALUES ('__t3_majorat__', 'grevskab') RETURNING id INTO em;
  INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle)
    VALUES ('estate',es,'estate',e2,'sammenlagt_i');
  INSERT INTO public.person DEFAULT VALUES RETURNING id INTO p;
  INSERT INTO public.media(slags) VALUES ('gods') RETURNING id INTO md;

  -- To ejerforhold på e1: r1 med én citation uden citat og én med bogens egen ordlyd; r2 med én uden citat.
  INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle,periode_raw)
    VALUES ('person',p,'estate',e1,'ejer','1700-1720') RETURNING id INTO r1;
  INSERT INTO public.assertion(target_type,target_id,vaerdi_tekst) VALUES ('relation',r1,'ejer') RETURNING id INTO a1;
  INSERT INTO public.citation(assertion_id,source_id,side) VALUES (a1,src,'12') RETURNING id INTO c1;
  INSERT INTO public.citation(assertion_id,source_id,side,citat_tekst) VALUES (a1,src,'12','bogens ordlyd') RETURNING id INTO c1b;
  INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle)
    VALUES ('person',p,'estate',e1,'ejer') RETURNING id INTO r2;
  INSERT INTO public.assertion(target_type,target_id,vaerdi_tekst) VALUES ('relation',r2,'ejer') RETURNING id INTO a2;
  INSERT INTO public.citation(assertion_id,source_id) VALUES (a2,src) RETURNING id INTO c2;
  -- Lokkemad: en anden rolle på samme gods og en faktum-påstand med samme target_id som et ejerforhold.
  INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle)
    VALUES ('person',p,'estate',e1,'forpagter') RETURNING id INTO r_fp;
  INSERT INTO public.assertion(target_type,target_id,vaerdi_tekst) VALUES ('relation',r_fp,'forpagter') RETURNING id INTO a_fp;
  INSERT INTO public.citation(assertion_id,source_id) VALUES (a_fp,src) RETURNING id INTO c_fp;
  INSERT INTO public.relation(id,subjekt_type,subjekt_id,objekt_type,objekt_id,rolle)
    VALUES (987650301,'person',p,'estate',e1,'ejer');
  INSERT INTO public.fact(id,subjekt_type,subjekt_id,faktatype) VALUES (987650301,'person',p,'erhverv') RETURNING id INTO f_lok;
  INSERT INTO public.assertion(target_type,target_id,vaerdi_tekst) VALUES ('fact',f_lok,'godsejer') RETURNING id INTO a_lok;
  INSERT INTO public.citation(assertion_id,source_id) VALUES (a_lok,src) RETURNING id INTO c_lok;

  -- (a) Kun redaktionen: anon har ingen EXECUTE; authenticated uden redaktionsprofil afvises af rollegaten.
  PERFORM pg_temp.g471_afvist_som('gaest', format('SELECT public.red_saet_estate(%s, %L, NULL)', e1, 'X'),
    '42501', NULL, 'red_saet_estate');
  PERFORM pg_temp.g471_afvist_som('gaest', format('SELECT public.red_flyt_estate_relation(%s, %s)', r1, e2),
    '42501', NULL, 'red_flyt_estate_relation');
  FOREACH k IN ARRAY ARRAY['uden_profil','medlem'] LOOP
    PERFORM pg_temp.g471_afvist_som(k, format('SELECT public.red_saet_estate(%s, %L, NULL)', e1, 'X'),
      'P0001', 'Kun redaktion', 'red_saet_estate');
    PERFORM pg_temp.g471_afvist_som(k, format('SELECT public.red_flyt_estate_relation(%s, %s)', r1, e2),
      'P0001', 'Kun redaktion', 'red_flyt_estate_relation');
  END LOOP;
  IF (SELECT navn FROM public.estate WHERE id = e1) <> '__t3_Christianssæde (med Pederstrup)__'
     OR (SELECT objekt_id FROM public.relation WHERE id = r1) <> e1 THEN
    RAISE EXCEPTION 'GODSER_T3: et afvist kald ændrede data';
  END IF;

  -- (b) Omdøbning: bogens navneform lægges på ejerforholdenes citationer uden citat; alt andet er urørt.
  v_cs := pg_temp.g471_som('redaktion', format('SELECT public.red_saet_estate(%s, %L, %L)', e1, '__t3_Grevskabet Christianssæde__', 'grevskab'));
  SELECT navn, slags INTO v_txt, v_slags FROM public.estate WHERE id = e1;
  IF v_txt <> '__t3_Grevskabet Christianssæde__' OR v_slags IS DISTINCT FROM 'grevskab' THEN
    RAISE EXCEPTION 'GODSER_T3: red_saet_estate gav navn »%«, slags »%«', v_txt, v_slags;
  END IF;
  IF (SELECT citat_tekst FROM public.citation WHERE id = c1) IS DISTINCT FROM '__t3_Christianssæde (med Pederstrup)__'
     OR (SELECT citat_tekst FROM public.citation WHERE id = c2) IS DISTINCT FROM '__t3_Christianssæde (med Pederstrup)__' THEN
    RAISE EXCEPTION 'GODSER_T3: omdøbningen satte ikke det gamle navn som citat på ejerforholdenes citationer';
  END IF;
  IF (SELECT citat_tekst FROM public.citation WHERE id = c1b) IS DISTINCT FROM 'bogens ordlyd' THEN
    RAISE EXCEPTION 'GODSER_T3: omdøbningen overskrev en citation, der allerede havde et citat';
  END IF;
  IF (SELECT citat_tekst FROM public.citation WHERE id = c_fp) IS NOT NULL
     OR (SELECT citat_tekst FROM public.citation WHERE id = c_lok) IS NOT NULL THEN
    RAISE EXCEPTION 'GODSER_T3: omdøbningen rørte en citation, der ikke hører til et ejerforhold på godset';
  END IF;
  IF v_cs IS NULL OR NOT EXISTS (SELECT 1 FROM public.change_set cs WHERE cs.id = v_cs AND cs.operation = 'red_saet_estate'
                                    AND cs.subjekt_type = 'estate' AND cs.subjekt_id = e1) THEN
    RAISE EXCEPTION 'GODSER_T3: red_saet_estate åbnede ikke sit eget ændringssæt (estate, %)', e1;
  END IF;
  SELECT count(*) INTO v_antal FROM public.change_event ce WHERE ce.change_set_id = v_cs AND ce.tabel = 'citation';
  IF v_antal <> 2 THEN RAISE EXCEPTION 'GODSER_T3: forventede 2 citation-hændelser i sættet, fandt %', v_antal; END IF;

  -- (c) Fortryd af omdøbningen giver navn, art og citat_tekst NULL tilbage.
  PERFORM pg_temp.g471_som('redaktion', format('SELECT public.red_fortryd_change_set(%s)', v_cs));
  IF (SELECT navn FROM public.estate WHERE id = e1) <> '__t3_Christianssæde (med Pederstrup)__'
     OR (SELECT slags FROM public.estate WHERE id = e1) IS NOT NULL
     OR (SELECT citat_tekst FROM public.citation WHERE id = c1) IS NOT NULL
     OR (SELECT citat_tekst FROM public.citation WHERE id = c2) IS NOT NULL
     OR (SELECT citat_tekst FROM public.citation WHERE id = c1b) IS DISTINCT FROM 'bogens ordlyd' THEN
    RAISE EXCEPTION 'GODSER_T3: fortryd af omdøbningen gav ikke tilstanden før';
  END IF;

  -- (d) Kun art: intet citat sættes, når navnet er uændret; uændret navn og art åbner intet sæt.
  v_cs := pg_temp.g471_som('redaktion', format('SELECT public.red_saet_estate(%s, %L, %L)', e1, '__t3_Christianssæde (med Pederstrup)__', 'baroni'));
  IF (SELECT slags FROM public.estate WHERE id = e1) IS DISTINCT FROM 'baroni'
     OR (SELECT citat_tekst FROM public.citation WHERE id = c1) IS NOT NULL THEN
    RAISE EXCEPTION 'GODSER_T3: ændring af kun arten satte et citat eller ændrede ikke arten';
  END IF;
  v_cs := pg_temp.g471_som('redaktion', format('SELECT public.red_saet_estate(%s, %L, %L)', e1, '__t3_Christianssæde (med Pederstrup)__', 'baroni'));
  IF v_cs IS NOT NULL THEN RAISE EXCEPTION 'GODSER_T3: et kald uden ændring åbnede ændringssæt %', v_cs; END IF;
  -- Mellemrum efter det gamle navn er ingen omdøbning: intet sæt, intet citat (og et citat er altid uden mellemrum).
  UPDATE public.estate SET navn = '__t3_Christianssæde (med Pederstrup)__  ' WHERE id = e1;
  v_cs := pg_temp.g471_som('redaktion', format('SELECT public.red_saet_estate(%s, %L, %L)', e1, '__t3_Christianssæde (med Pederstrup)__', 'baroni'));
  IF v_cs IS NOT NULL OR (SELECT citat_tekst FROM public.citation WHERE id = c1) IS NOT NULL THEN
    RAISE EXCEPTION 'GODSER_T3: et gammelt navn med mellemrum til sidst blev behandlet som en omdøbning (sæt %)', v_cs;
  END IF;
  v_cs := pg_temp.g471_som('redaktion', format('SELECT public.red_saet_estate(%s, %L, %L)', e1, '__t3_Ny__', 'baroni'));
  IF (SELECT citat_tekst FROM public.citation WHERE id = c1) IS DISTINCT FROM '__t3_Christianssæde (med Pederstrup)__' THEN
    RAISE EXCEPTION 'GODSER_T3: citatet fik ikke det gamle navn uden mellemrum (fik »%«)', (SELECT citat_tekst FROM public.citation WHERE id = c1);
  END IF;
  PERFORM pg_temp.g471_som('redaktion', format('SELECT public.red_fortryd_change_set(%s)', v_cs));
  UPDATE public.estate SET navn = '__t3_Christianssæde (med Pederstrup)__' WHERE id = e1;

  -- (e) Afvisninger: tomt navn, ukendt art, sammenlagt række, gods der ikke findes.
  PERFORM pg_temp.g471_afvist_som('redaktion', format('SELECT public.red_saet_estate(%s, %L, NULL)', e1, '  '),
    '22023', 'ESTATE_NAVN_TOMT', 'red_saet_estate med tomt navn');
  PERFORM pg_temp.g471_afvist_som('redaktion', format('SELECT public.red_saet_estate(%s, %L, %L)', e1, 'Y', 'len'),
    '23514', 'ESTATE_SLAGS_UKENDT', 'red_saet_estate med ukendt art');
  PERFORM pg_temp.g471_afvist_som('redaktion', format('SELECT public.red_saet_estate(%s, %L, NULL)', es, 'Y'),
    '23514', 'ESTATE_ER_SAMMENLAGT', 'red_saet_estate på en sammenlagt række');
  PERFORM pg_temp.g471_afvist_som('redaktion', 'SELECT public.red_saet_estate(-987650001, ''Y'', NULL)',
    'P0002', 'ESTATE_FINDES_IKKE', 'red_saet_estate på et gods, der ikke findes');

  -- (f) Arten kan ikke ændres, så en eksisterende hører_under bliver ugyldig (trg_estate_slags; også direkte UPDATE).
  INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle)
    VALUES ('estate',eg,'estate',em,'hører_under') RETURNING id INTO r_hu;
  PERFORM pg_temp.g471_afvist(format('UPDATE public.estate SET slags = NULL WHERE id = %s', eg),
    'ESTATE_HOERER_UNDER_ART', 'gård med hører_under mister sin art');
  PERFORM pg_temp.g471_afvist(format('UPDATE public.estate SET slags = %L WHERE id = %s', 'stamhus', eg),
    'ESTATE_HOERER_UNDER_ART', 'gård med hører_under bliver et stamhus');
  PERFORM pg_temp.g471_afvist(format('UPDATE public.estate SET slags = %L WHERE id = %s', 'gård', em),
    'ESTATE_HOERER_UNDER_ART', 'majorat med gårde under sig bliver en gård');
  PERFORM pg_temp.g471_afvist(format('UPDATE public.estate SET slags = NULL WHERE id = %s', em),
    'ESTATE_HOERER_UNDER_ART', 'majorat med gårde under sig mister sin art');
  PERFORM pg_temp.g471_afvist_som('redaktion', format('SELECT public.red_saet_estate(%s, %L, NULL)', eg, '__t3_gaard__'),
    '23514', 'ESTATE_HOERER_UNDER_ART', 'red_saet_estate fjerner arten fra en gård under et majorat');
  -- Lovligt: et majorat skifter mellem majoratsformer, en gård omdøbes, og en no-op-UPDATE af slags.
  UPDATE public.estate SET slags = 'baroni' WHERE id = em;
  UPDATE public.estate SET slags = slags WHERE id = eg;
  PERFORM pg_temp.g471_som('redaktion', format('SELECT public.red_saet_estate(%s, %L, %L)', eg, '__t3_gaard omdøbt__', 'gård'));
  -- Uden hører_under er arten fri igen.
  DELETE FROM public.relation WHERE id = r_hu;
  UPDATE public.estate SET slags = NULL WHERE id = eg;

  -- (g) Flyt et ejerforhold: samme relation-id, hændelsens relation_id og citationen følger med; citat = fra-godsets navn.
  INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle)
    VALUES ('person',p,'estate',e3,'ejer') RETURNING id INTO r_flyt;
  INSERT INTO public.assertion(target_type,target_id,vaerdi_tekst) VALUES ('relation',r_flyt,'ejer') RETURNING id INTO a_flyt;
  INSERT INTO public.citation(assertion_id,source_id,side) VALUES (a_flyt,src,'7') RETURNING id INTO c_flyt;
  INSERT INTO public.narrative(subjekt_type,subjekt_id,tekst) VALUES ('person',p,'__t3_narrativ__') RETURNING id INTO nar;
  INSERT INTO public.haendelse(subjekt_type,subjekt_id,narrative_id,noegle,klausul,relation_id)
    VALUES ('person',p,nar,'__t3_h__','købte godset',r_flyt) RETURNING id INTO hd;
  v_cs := pg_temp.g471_som('redaktion', format('SELECT public.red_flyt_estate_relation(%s, %s)', r_flyt, e2));
  IF NOT EXISTS (SELECT 1 FROM public.relation r WHERE r.id = r_flyt AND r.objekt_type = 'estate' AND r.objekt_id = e2
                    AND r.subjekt_type = 'person' AND r.subjekt_id = p AND r.rolle = 'ejer') THEN
    RAISE EXCEPTION 'GODSER_T3: ejerforholdet % blev ikke flyttet til gods % med samme id', r_flyt, e2;
  END IF;
  IF (SELECT relation_id FROM public.haendelse WHERE id = hd) IS DISTINCT FROM r_flyt THEN
    RAISE EXCEPTION 'GODSER_T3: hændelsens relation_id fulgte ikke med';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.citation c JOIN public.assertion a ON a.id = c.assertion_id
                  WHERE c.id = c_flyt AND a.id = a_flyt AND a.target_type = 'relation' AND a.target_id = r_flyt
                    AND c.source_id = src AND c.side = '7' AND c.citat_tekst = '__t3_Wittenberg (dublet)__') THEN
    RAISE EXCEPTION 'GODSER_T3: citationen fulgte ikke med, eller fra-godsets navn blev ikke sat som citat';
  END IF;
  IF v_cs IS NULL OR NOT EXISTS (SELECT 1 FROM public.change_set cs WHERE cs.id = v_cs
                                    AND cs.operation = 'red_flyt_estate_relation'
                                    AND cs.subjekt_type = 'estate' AND cs.subjekt_id = e2) THEN
    RAISE EXCEPTION 'GODSER_T3: red_flyt_estate_relation åbnede ikke sit eget ændringssæt (estate, %)', e2;
  END IF;
  -- Fortryd: ejerforholdet tilbage på fra-godset og citat_tekst NULL igen.
  PERFORM pg_temp.g471_som('redaktion', format('SELECT public.red_fortryd_change_set(%s)', v_cs));
  IF (SELECT objekt_id FROM public.relation WHERE id = r_flyt) <> e3
     OR (SELECT citat_tekst FROM public.citation WHERE id = c_flyt) IS NOT NULL THEN
    RAISE EXCEPTION 'GODSER_T3: fortryd af flytningen gav ikke tilstanden før';
  END IF;
  -- Flyt til samme gods er en no-op uden ændringssæt.
  v_cs := pg_temp.g471_som('redaktion', format('SELECT public.red_flyt_estate_relation(%s, %s)', r_flyt, e3));
  IF v_cs IS NOT NULL THEN RAISE EXCEPTION 'GODSER_T3: flyt til samme gods åbnede ændringssæt %', v_cs; END IF;

  -- (h) Flyt et billede (afbildet): virker, intet citat at sætte.
  INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle)
    VALUES ('media',md,'estate',e3,'afbildet') RETURNING id INTO r_afb;
  PERFORM pg_temp.g471_som('redaktion', format('SELECT public.red_flyt_estate_relation(%s, %s)', r_afb, e2));
  IF NOT EXISTS (SELECT 1 FROM public.relation r WHERE r.id = r_afb AND r.objekt_id = e2 AND r.subjekt_type = 'media'
                    AND r.subjekt_id = md AND r.rolle = 'afbildet') THEN
    RAISE EXCEPTION 'GODSER_T3: billedet % blev ikke flyttet til gods %', r_afb, e2;
  END IF;

  -- (i) Afvisninger: anden rolle, ikke-estate-objekt, relation/gods der ikke findes, flyt til en sammenlagt række.
  INSERT INTO public.person DEFAULT VALUES RETURNING id INTO ex;
  INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle)
    VALUES ('person',ex,'person',p,'samme_som') RETURNING id INTO r_samme;
  PERFORM pg_temp.g471_afvist_som('redaktion', format('SELECT public.red_flyt_estate_relation(%s, %s)', r_samme, e2),
    '23514', 'ESTATE_FLYT_ROLLE', 'flyt af samme_som');
  PERFORM pg_temp.g471_afvist_som('redaktion', format('SELECT public.red_flyt_estate_relation(%s, %s)', r_fp, e2),
    '23514', 'ESTATE_FLYT_ROLLE', 'flyt af forpagter');
  PERFORM pg_temp.g471_afvist_som('redaktion', format('SELECT public.red_flyt_estate_relation(-987650001, %s)', e2),
    'P0002', 'RELATION_FINDES_IKKE', 'flyt af en relation, der ikke findes');
  PERFORM pg_temp.g471_afvist_som('redaktion', format('SELECT public.red_flyt_estate_relation(%s, -987650001)', r_flyt),
    'P0002', 'ESTATE_FINDES_IKKE', 'flyt til et gods, der ikke findes');
  PERFORM pg_temp.g471_afvist_som('redaktion', format('SELECT public.red_flyt_estate_relation(%s, %s)', r_flyt, es),
    '23514', 'ESTATE_ER_SAMMENLAGT', 'flyt til en sammenlagt række');
  IF (SELECT objekt_id FROM public.relation WHERE id = r_flyt) <> e3
     OR (SELECT citat_tekst FROM public.citation WHERE id = c_flyt) IS NOT NULL THEN
    RAISE EXCEPTION 'GODSER_T3: en afvist flytning efterlod ændringer';
  END IF;
END
$t3$;

-- NY AFSNIT TILFØJES HER (før OK-linjen).
ROLLBACK;
\echo OK test-godser-fase1
