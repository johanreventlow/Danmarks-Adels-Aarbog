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

-- ---------- 4. Sammenlæg godser (red_sammenlaeg_estate) og fortrydelsen ----------
-- Øjebliksbillede af alle relationer med en estate-ende i p_ids, deres citationer og godsrækkerne selv.
CREATE FUNCTION pg_temp.g471_snap(p_ids bigint[]) RETURNS jsonb LANGUAGE sql AS $f$
  WITH r AS (SELECT * FROM public.relation r
              WHERE (r.subjekt_type = 'estate' AND r.subjekt_id = ANY(p_ids))
                 OR (r.objekt_type = 'estate' AND r.objekt_id = ANY(p_ids)))
  SELECT jsonb_build_object(
    'relation', (SELECT jsonb_agg(to_jsonb(r) ORDER BY r.id) FROM r),
    'citation', (SELECT jsonb_agg(to_jsonb(c) ORDER BY c.id) FROM public.citation c
                   JOIN public.assertion a ON a.id = c.assertion_id JOIN r ON a.target_type = 'relation' AND a.target_id = r.id),
    'estate',   (SELECT jsonb_agg(to_jsonb(e) ORDER BY e.id) FROM public.estate e WHERE e.id = ANY(p_ids)));
$f$;

-- Kald red_sammenlaeg_estate som redaktion; returnér resultatet og ændringssættets id.
CREATE FUNCTION pg_temp.g471_sammenlaeg(p_fra bigint, p_til bigint, OUT res jsonb, OUT cs bigint) LANGUAGE plpgsql AS $f$
BEGIN
  cs := pg_temp.g471_som('redaktion',
    format('SELECT set_config(%L, public.red_sammenlaeg_estate(%s, %s)::text, true)', 'g471.res', p_fra, p_til));
  res := current_setting('g471.res')::jsonb;
END
$f$;

DO $t4$
DECLARE
  f bigint := 987650401; t bigint; m bigint; t2 bigint; x bigint; y bigint; mf bigint; mt bigint; g bigint;
  p1 bigint; p2 bigint; p3 bigint; p_lok bigint := 987650401; md1 bigint; md2 bigint; src bigint; nar bigint;
  r_f1 bigint; r_f2 bigint; r_t1 bigint; r_t2 bigint; r_afb bigint; r_hu bigint; r_x bigint; r_slet bigint;
  a bigint; c_f1 bigint; c_f1b bigint; c_f2 bigint; c_t1 bigint;
  v_foer jsonb; v_efter jsonb; v_res jsonb; v_cs bigint; v_cs_slet bigint; v_antal bigint; v_flyt_sets bigint; k text;
BEGIN
  INSERT INTO public.source(slags, titel) VALUES ('bog', '__t4_kilde__') RETURNING id INTO src;
  INSERT INTO public.estate(id, navn, slags) VALUES (f, '__t4_Wittenberg (dublet)__', 'gård');
  INSERT INTO public.estate(navn, slags) VALUES ('__t4_Wittenberg__', 'gård') RETURNING id INTO t;
  INSERT INTO public.estate(navn, slags) VALUES ('__t4_majorat__', 'grevskab') RETURNING id INTO m;
  INSERT INTO public.person DEFAULT VALUES RETURNING id INTO p1;
  INSERT INTO public.person DEFAULT VALUES RETURNING id INTO p2;
  INSERT INTO public.person DEFAULT VALUES RETURNING id INTO p3;
  INSERT INTO public.media(slags) VALUES ('gods') RETURNING id INTO md1;
  INSERT INTO public.media(slags) VALUES ('gods') RETURNING id INTO md2;

  -- To ejerforhold på hver række; p1 ejer begge (Review Focus 4). Ét billede på fra; fra hører under et majorat.
  INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle,periode_raw)
    VALUES ('person',p1,'estate',f,'ejer','1700-1720') RETURNING id INTO r_f1;
  INSERT INTO public.assertion(target_type,target_id,vaerdi_tekst) VALUES ('relation',r_f1,'ejer') RETURNING id INTO a;
  INSERT INTO public.citation(assertion_id,source_id,side) VALUES (a,src,'12') RETURNING id INTO c_f1;
  INSERT INTO public.citation(assertion_id,source_id,side,citat_tekst) VALUES (a,src,'12','bogens ordlyd') RETURNING id INTO c_f1b;
  INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle)
    VALUES ('person',p2,'estate',f,'ejer') RETURNING id INTO r_f2;
  INSERT INTO public.assertion(target_type,target_id,vaerdi_tekst) VALUES ('relation',r_f2,'ejer') RETURNING id INTO a;
  INSERT INTO public.citation(assertion_id,source_id) VALUES (a,src) RETURNING id INTO c_f2;
  INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle,periode_raw)
    VALUES ('person',p1,'estate',t,'ejer','1720-1740') RETURNING id INTO r_t1;
  INSERT INTO public.assertion(target_type,target_id,vaerdi_tekst) VALUES ('relation',r_t1,'ejer') RETURNING id INTO a;
  INSERT INTO public.citation(assertion_id,source_id) VALUES (a,src) RETURNING id INTO c_t1;
  INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle)
    VALUES ('person',p3,'estate',t,'ejer') RETURNING id INTO r_t2;
  INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle)
    VALUES ('media',md1,'estate',f,'afbildet') RETURNING id INTO r_afb;
  INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle)
    VALUES ('estate',f,'estate',m,'hører_under') RETURNING id INTO r_hu;
  -- Lokkemad: en person med samme id som fra-godset har et narrativ, et faktum og en note — det er ikke godsets koblinger.
  INSERT INTO public.person(id) VALUES (p_lok);
  INSERT INTO public.narrative(subjekt_type,subjekt_id,tekst) VALUES ('person',p_lok,'__t4_lok__');
  INSERT INTO public.fact(subjekt_type,subjekt_id,faktatype) VALUES ('person',p_lok,'erhverv');
  INSERT INTO public.note(target_type,target_id,indhold) VALUES ('person',p_lok,'__t4_lok__');

  -- (0) Kun redaktionen.
  PERFORM pg_temp.g471_afvist_som('gaest', format('SELECT public.red_sammenlaeg_estate(%s, %s)', f, t),
    '42501', NULL, 'red_sammenlaeg_estate');
  FOREACH k IN ARRAY ARRAY['uden_profil','medlem'] LOOP
    PERFORM pg_temp.g471_afvist_som(k, format('SELECT public.red_sammenlaeg_estate(%s, %s)', f, t),
      'P0001', 'Kun redaktion', 'red_sammenlaeg_estate');
  END LOOP;

  -- (a) Sammenlæg fra i til: alt flyttes med samme id, fra har kun sammenlagt_i tilbage; ét ændringssæt.
  v_foer := pg_temp.g471_snap(ARRAY[f,t,m]);
  SELECT count(*) INTO v_flyt_sets FROM public.change_set WHERE operation = 'red_flyt_estate_relation';
  SELECT res, cs INTO v_res, v_cs FROM pg_temp.g471_sammenlaeg(f, t);
  IF v_res IS DISTINCT FROM '{"flyttet_ejer": 2, "flyttet_afbildet": 1, "flyttet_hoerer_under": 1}'::jsonb THEN
    RAISE EXCEPTION 'GODSER_T4: red_sammenlaeg_estate returnerede %', v_res;
  END IF;
  SELECT count(*) INTO v_antal FROM public.relation WHERE objekt_type = 'estate' AND objekt_id = t AND rolle = 'ejer';
  IF v_antal <> 4 THEN RAISE EXCEPTION 'GODSER_T4: til har % ejerforhold, ventede 4', v_antal; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.relation WHERE id = r_afb AND objekt_id = t AND subjekt_id = md1)
     OR NOT EXISTS (SELECT 1 FROM public.relation WHERE id = r_hu AND subjekt_id = t AND objekt_id = m AND rolle = 'hører_under')
     OR NOT EXISTS (SELECT 1 FROM public.relation WHERE id = r_f1 AND objekt_id = t)
     OR NOT EXISTS (SELECT 1 FROM public.relation WHERE id = r_f2 AND objekt_id = t) THEN
    RAISE EXCEPTION 'GODSER_T4: ejerforhold, billede eller hører_under blev ikke flyttet til til med samme id';
  END IF;
  SELECT count(*) INTO v_antal FROM public.relation
   WHERE (subjekt_type = 'estate' AND subjekt_id = f) OR (objekt_type = 'estate' AND objekt_id = f);
  IF v_antal <> 1 OR NOT EXISTS (SELECT 1 FROM public.relation WHERE subjekt_type = 'estate' AND subjekt_id = f
                                    AND objekt_type = 'estate' AND objekt_id = t AND rolle = 'sammenlagt_i') THEN
    RAISE EXCEPTION 'GODSER_T4: fra har % relationer tilbage, ventede kun sammenlagt_i til til', v_antal;
  END IF;
  IF (SELECT citat_tekst FROM public.citation WHERE id = c_f1) IS DISTINCT FROM '__t4_Wittenberg (dublet)__'
     OR (SELECT citat_tekst FROM public.citation WHERE id = c_f2) IS DISTINCT FROM '__t4_Wittenberg (dublet)__'
     OR (SELECT citat_tekst FROM public.citation WHERE id = c_f1b) IS DISTINCT FROM 'bogens ordlyd'
     OR (SELECT citat_tekst FROM public.citation WHERE id = c_t1) IS NOT NULL THEN
    RAISE EXCEPTION 'GODSER_T4: citaterne er forkerte efter sammenlægningen';
  END IF;
  IF v_cs IS NULL OR NOT EXISTS (SELECT 1 FROM public.change_set cs WHERE cs.id = v_cs
                                    AND cs.operation = 'red_sammenlaeg_estate' AND cs.subjekt_type = 'estate' AND cs.subjekt_id = t) THEN
    RAISE EXCEPTION 'GODSER_T4: red_sammenlaeg_estate åbnede ikke sit eget ændringssæt (estate, %)', t;
  END IF;
  IF (SELECT count(*) FROM public.change_set WHERE operation = 'red_flyt_estate_relation') <> v_flyt_sets THEN
    RAISE EXCEPTION 'GODSER_T4: flytningerne åbnede egne ændringssæt i stedet for at bruge sammenlægningens';
  END IF;
  IF (SELECT navn FROM public.estate WHERE id = f) <> '__t4_Wittenberg (dublet)__' THEN
    RAISE EXCEPTION 'GODSER_T4: den sammenlagte række blev ikke liggende med sit navn';
  END IF;

  -- (b) Samme ejer på begge rækker bliver to ejerforhold (ingen deduplikering; Review Focus 4).
  SELECT count(*) INTO v_antal FROM public.relation
   WHERE subjekt_type = 'person' AND subjekt_id = p1 AND objekt_type = 'estate' AND objekt_id = t AND rolle = 'ejer';
  IF v_antal <> 2 THEN RAISE EXCEPTION 'GODSER_T4: p1 har % ejerforhold til til, ventede 2', v_antal; END IF;

  -- (c) Fortryd giver præcis tilstanden før: relationer tilbage på fra, ingen sammenlagt_i, citat_tekst NULL igen.
  PERFORM pg_temp.g471_som('redaktion', format('SELECT public.red_fortryd_change_set(%s)', v_cs));
  v_efter := pg_temp.g471_snap(ARRAY[f,t,m]);
  IF v_efter IS DISTINCT FROM v_foer THEN
    RAISE EXCEPTION 'GODSER_T4: fortryd af sammenlægningen gav ikke tilstanden før: før % efter %', v_foer, v_efter;
  END IF;
  IF EXISTS (SELECT 1 FROM public.relation WHERE rolle = 'sammenlagt_i' AND subjekt_type = 'estate' AND subjekt_id = f) THEN
    RAISE EXCEPTION 'GODSER_T4: sammenlagt_i står tilbage efter fortryd';
  END IF;

  -- (d) Afvisninger: ind i en sammenlagt række, en sammenlagt række, en række der er mål for en sammenlægning,
  -- i sig selv, gods der ikke findes; billede af samme medie på begge rækker. Intet ændres.
  INSERT INTO public.estate(navn, slags) VALUES ('__t4_x__', 'gård') RETURNING id INTO x;
  INSERT INTO public.estate(navn, slags) VALUES ('__t4_y__', 'gård') RETURNING id INTO y;
  INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle) VALUES ('estate',x,'estate',y,'sammenlagt_i');
  PERFORM pg_temp.g471_afvist_som('redaktion', format('SELECT public.red_sammenlaeg_estate(%s, %s)', f, x),
    '23514', 'ESTATE_ER_SAMMENLAGT', 'sammenlægning ind i en sammenlagt række');
  PERFORM pg_temp.g471_afvist_som('redaktion', format('SELECT public.red_sammenlaeg_estate(%s, %s)', x, t),
    '23514', 'ESTATE_ER_SAMMENLAGT', 'sammenlægning af en sammenlagt række');
  PERFORM pg_temp.g471_afvist_som('redaktion', format('SELECT public.red_sammenlaeg_estate(%s, %s)', y, t),
    '23514', 'ESTATE_SAMMENLAGT_KAEDE', 'sammenlægning af en række, der er mål for en sammenlægning');
  PERFORM pg_temp.g471_afvist_som('redaktion', format('SELECT public.red_sammenlaeg_estate(%s, %s)', f, f),
    '23514', 'ESTATE_RELATION_SELV', 'sammenlægning i sig selv');
  PERFORM pg_temp.g471_afvist_som('redaktion', format('SELECT public.red_sammenlaeg_estate(%s, -987650001)', f),
    'P0002', 'ESTATE_FINDES_IKKE', 'sammenlægning i et gods, der ikke findes');
  PERFORM pg_temp.g471_afvist_som('redaktion', format('SELECT public.red_sammenlaeg_estate(-987650001, %s)', t),
    'P0002', 'ESTATE_FINDES_IKKE', 'sammenlægning af et gods, der ikke findes');
  PERFORM pg_temp.g471_afvist_som('redaktion', format('SELECT public.red_sammenlaeg_estate(NULL, %s)', t),
    'P0002', 'ESTATE_FINDES_IKKE', 'sammenlægning af NULL');
  INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle) VALUES ('media',md1,'estate',t,'afbildet') RETURNING id INTO r_x;
  PERFORM pg_temp.g471_afvist_som('redaktion', format('SELECT public.red_sammenlaeg_estate(%s, %s)', f, t),
    '23505', 'ESTATE_BILLEDE_PAA_BEGGE', 'sammenlægning, hvor samme billede er på begge rækker');
  DELETE FROM public.relation WHERE id = r_x;
  IF pg_temp.g471_snap(ARRAY[f,t,m]) IS DISTINCT FROM v_foer THEN
    RAISE EXCEPTION 'GODSER_T4: en afvist sammenlægning efterlod ændringer';
  END IF;

  -- (e) Andre koblinger end ejer/afbildet/hører_under afvises, før noget flyttes (ESTATE_HAR_ANDRE_KOBLINGER).
  INSERT INTO public.estate(navn, slags) VALUES ('__t4_t2__', 'gård') RETURNING id INTO t2;
  FOREACH k IN ARRAY ARRAY['narrative','fact','note','entity_description','text_mention','forpagter','ejer_som_subjekt','haendelse'] LOOP
    INSERT INTO public.estate(navn, slags) VALUES ('__t4_kobling_' || k || '__', 'gård') RETURNING id INTO x;
    INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle) VALUES ('person',p2,'estate',x,'ejer') RETURNING id INTO r_x;
    CASE k
      WHEN 'narrative' THEN INSERT INTO public.narrative(subjekt_type,subjekt_id,tekst) VALUES ('estate',x,'__t4_godsets narrativ__');
      WHEN 'fact' THEN INSERT INTO public.fact(subjekt_type,subjekt_id,faktatype) VALUES ('estate',x,'opført');
      WHEN 'note' THEN INSERT INTO public.note(target_type,target_id,indhold) VALUES ('estate',x,'__t4_note__');
      WHEN 'entity_description' THEN
        INSERT INTO public.entity_description(subjekt_type,subjekt_id,kind,tekst) VALUES ('estate',x,'overview','__t4_beskrivelse__');
      WHEN 'text_mention' THEN
        INSERT INTO public.narrative(subjekt_type,subjekt_id,tekst) VALUES ('person',p2,'__t4_nævner godset__') RETURNING id INTO nar;
        INSERT INTO public.text_mention(kilde_type,kilde_id,maal_type,maal_id) VALUES ('narrative',nar,'estate',x);
      WHEN 'forpagter' THEN
        INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle) VALUES ('person',p2,'estate',x,'forpagter');
      WHEN 'ejer_som_subjekt' THEN
        INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle) VALUES ('estate',x,'estate',t2,'ejer');
      WHEN 'haendelse' THEN
        INSERT INTO public.narrative(subjekt_type,subjekt_id,tekst) VALUES ('person',p2,'__t4_h__') RETURNING id INTO nar;
        INSERT INTO public.haendelse(subjekt_type,subjekt_id,narrative_id,noegle,klausul) VALUES ('estate',x,nar,'__t4_h__','brændte');
    END CASE;
    PERFORM pg_temp.g471_afvist_som('redaktion', format('SELECT public.red_sammenlaeg_estate(%s, %s)', x, t2),
      '23514', 'ESTATE_HAR_ANDRE_KOBLINGER', 'sammenlægning af et gods med ' || k);
    IF (SELECT objekt_id FROM public.relation WHERE id = r_x) <> x
       OR EXISTS (SELECT 1 FROM public.relation WHERE rolle = 'sammenlagt_i' AND subjekt_type = 'estate' AND subjekt_id = x) THEN
      RAISE EXCEPTION 'GODSER_T4: en afvist sammenlægning (%) flyttede noget', k;
    END IF;
  END LOOP;

  -- (g) Majorat i majorat: gårde under fra kommer under til; fortryd giver dem tilbage. Forkert art afvises af vagten.
  INSERT INTO public.estate(navn, slags) VALUES ('__t4_mf__', 'grevskab') RETURNING id INTO mf;
  INSERT INTO public.estate(navn, slags) VALUES ('__t4_mt__', 'baroni') RETURNING id INTO mt;
  INSERT INTO public.estate(navn, slags) VALUES ('__t4_g__', 'gård') RETURNING id INTO g;
  INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle) VALUES ('estate',g,'estate',mf,'hører_under') RETURNING id INTO r_x;
  v_foer := pg_temp.g471_snap(ARRAY[mf,mt,g]);
  SELECT res, cs INTO v_res, v_cs FROM pg_temp.g471_sammenlaeg(mf, mt);
  IF v_res IS DISTINCT FROM '{"flyttet_ejer": 0, "flyttet_afbildet": 0, "flyttet_hoerer_under": 1}'::jsonb
     OR NOT EXISTS (SELECT 1 FROM public.relation WHERE id = r_x AND subjekt_id = g AND objekt_id = mt) THEN
    RAISE EXCEPTION 'GODSER_T4: gården kom ikke under det overlevende majorat (%)', v_res;
  END IF;
  PERFORM pg_temp.g471_som('redaktion', format('SELECT public.red_fortryd_change_set(%s)', v_cs));
  IF pg_temp.g471_snap(ARRAY[mf,mt,g]) IS DISTINCT FROM v_foer THEN
    RAISE EXCEPTION 'GODSER_T4: fortryd af majoratets sammenlægning gav ikke tilstanden før';
  END IF;
  PERFORM pg_temp.g471_afvist_som('redaktion', format('SELECT public.red_sammenlaeg_estate(%s, %s)', mf, t2),
    '23514', 'ESTATE_HOERER_UNDER_ART', 'sammenlægning af et majorat med gårde ind i en gård');
  PERFORM pg_temp.g471_afvist_som('redaktion', format('SELECT public.red_sammenlaeg_estate(%s, %s)', mf, g),
    '23514', 'ESTATE_RELATION_SELV', 'sammenlægning af et majorat ind i en af sine egne gårde');
  IF pg_temp.g471_snap(ARRAY[mf,mt,g]) IS DISTINCT FROM v_foer THEN
    RAISE EXCEPTION 'GODSER_T4: en afvist sammenlægning (forkert art) efterlod ændringer';
  END IF;

  -- (f) Fortryd af en gammel sletning af et ejerforhold, hvis gods siden er lagt sammen, afvises af vagten, frem for
  -- at genskabe et ejerforhold til en skjult række.
  INSERT INTO public.estate(navn, slags) VALUES ('__t4_slettet_fra__', 'gård') RETURNING id INTO x;
  INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle) VALUES ('person',p3,'estate',x,'ejer') RETURNING id INTO r_slet;
  INSERT INTO public.assertion(target_type,target_id,vaerdi_tekst) VALUES ('relation',r_slet,'ejer') RETURNING id INTO a;
  INSERT INTO public.citation(assertion_id,source_id) VALUES (a,src);
  v_cs_slet := pg_temp.g471_som('redaktion', format('SELECT public.red_slet_relation(%s)', r_slet));
  IF v_cs_slet IS NULL OR EXISTS (SELECT 1 FROM public.relation WHERE id = r_slet) THEN
    RAISE EXCEPTION 'GODSER_T4: red_slet_relation slettede ikke ejerforholdet';
  END IF;
  SELECT res, cs INTO v_res, v_cs FROM pg_temp.g471_sammenlaeg(x, t2);
  PERFORM pg_temp.g471_afvist_som('redaktion', format('SELECT public.red_fortryd_change_set(%s)', v_cs_slet),
    '23514', 'ESTATE_ER_SAMMENLAGT', 'fortryd af en sletning af et ejerforhold til en sammenlagt række');
  IF EXISTS (SELECT 1 FROM public.relation WHERE id = r_slet)
     OR EXISTS (SELECT 1 FROM public.change_set WHERE reverterer_id = v_cs_slet) THEN
    RAISE EXCEPTION 'GODSER_T4: den afviste fortrydelse genskabte ejerforholdet % eller blev registreret', r_slet;
  END IF;
END
$t4$;

-- ---------- 5. Ejerforhold til hver gård i en godsmasse (red_kopier_ejerforhold) og »hører under« (red_hoerer_under) ----------
-- Kald p_expr (et udtryk, der giver et bigint) som redaktion; returnér værdien og ændringssættets id (NULL = intet sæt).
CREATE FUNCTION pg_temp.g471_kald(p_expr text, OUT id bigint, OUT cs bigint) LANGUAGE plpgsql AS $f$
BEGIN
  cs := pg_temp.g471_som('redaktion', format('SELECT set_config(%L, (%s)::text, true)', 'g471.id', p_expr));
  id := nullif(current_setting('g471.id'), '')::bigint;
END
$f$;

-- En relation med al dens evidens (påstande, konklusioner, citationer), som jsonb; NULL-felter, når intet findes.
CREATE FUNCTION pg_temp.g471_evidens(p_rel bigint) RETURNS jsonb LANGUAGE sql AS $f$
  SELECT jsonb_build_object(
    'relation',   (SELECT to_jsonb(r) FROM public.relation r WHERE r.id = p_rel),
    'assertion',  (SELECT jsonb_agg(to_jsonb(a) ORDER BY a.id) FROM public.assertion a
                    WHERE a.target_type = 'relation' AND a.target_id = p_rel),
    'conclusion', (SELECT jsonb_agg(to_jsonb(c) ORDER BY c.id) FROM public.conclusion c
                    WHERE c.target_type = 'relation' AND c.target_id = p_rel),
    'citation',   (SELECT jsonb_agg(to_jsonb(c) ORDER BY c.id) FROM public.citation c
                    JOIN public.assertion a ON a.id = c.assertion_id
                   WHERE a.target_type = 'relation' AND a.target_id = p_rel));
$f$;

-- Kræv præcis én påstand (værdi, datotekst, uforanderlig), én afklaret konklusion med den valgt og én citation.
CREATE FUNCTION pg_temp.g471_kraev_evidens(p_rel bigint, p_vaerdi text, p_date_raw text, p_source bigint,
                                           p_kvalitet text, p_side text, p_citat text, p_hvad text)
RETURNS void LANGUAGE plpgsql AS $f$
DECLARE v_a public.assertion; v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM public.assertion a WHERE a.target_type = 'relation' AND a.target_id = p_rel;
  IF v_n <> 1 THEN RAISE EXCEPTION 'GODSER_T5: % har % påstande, ventede 1', p_hvad, v_n; END IF;
  SELECT * INTO v_a FROM public.assertion a WHERE a.target_type = 'relation' AND a.target_id = p_rel;
  IF v_a.vaerdi_tekst IS DISTINCT FROM p_vaerdi OR v_a.date_raw IS DISTINCT FROM p_date_raw
     OR v_a.uforanderlig IS DISTINCT FROM true OR v_a.objekt_type IS NOT NULL THEN
    RAISE EXCEPTION 'GODSER_T5: %: påstanden er forkert (%)', p_hvad, to_jsonb(v_a);
  END IF;
  SELECT count(*) INTO v_n FROM public.conclusion c WHERE c.target_type = 'relation' AND c.target_id = p_rel;
  IF v_n <> 1 OR NOT EXISTS (SELECT 1 FROM public.conclusion c WHERE c.target_type = 'relation' AND c.target_id = p_rel
                                AND c.status = 'afklaret' AND c.valgt_assertion_id = v_a.id) THEN
    RAISE EXCEPTION 'GODSER_T5: %: ventede én afklaret konklusion med påstanden valgt (% konklusioner)', p_hvad, v_n;
  END IF;
  SELECT count(*) INTO v_n FROM public.citation c WHERE c.assertion_id = v_a.id;
  IF v_n <> 1 OR NOT EXISTS (SELECT 1 FROM public.citation c WHERE c.assertion_id = v_a.id
                                AND c.source_id IS NOT DISTINCT FROM p_source AND c.kvalitet IS NOT DISTINCT FROM p_kvalitet
                                AND c.side IS NOT DISTINCT FROM p_side AND c.citat_tekst IS NOT DISTINCT FROM p_citat) THEN
    RAISE EXCEPTION 'GODSER_T5: %: ventede én citation (kilde %, %, side %, »%«); fandt %', p_hvad, p_source, p_kvalitet,
      p_side, p_citat, (SELECT jsonb_agg(to_jsonb(c)) FROM public.citation c WHERE c.assertion_id = v_a.id);
  END IF;
END
$f$;

DO $t5$
DECLARE
  src bigint; src2 bigint; ex bigint; ey bigint; ez bigint; es bigint; ek bigint; p bigint; p2 bigint; md bigint;
  g1 bigint; g2 bigint; m1 bigint; n1 bigint; gs bigint;
  r_src bigint := 987650501; r_null bigint; r_ingen bigint; r_to bigint; r_to2 bigint; r_fp bigint; r_afb bigint; r_estsub bigint;
  a bigint; f_lok bigint; a_lok bigint; v_k bigint; v_kn bigint; v_h bigint; v_hn bigint; v_id bigint; v_cs bigint; v_cs_k bigint;
  v_cs_h bigint; v_sets bigint; v_rel bigint; v_ass bigint; v_cit bigint; v_kon bigint; v_src_foer jsonb; v_rel_row public.relation;
  v_ny public.relation; k text; p3 bigint; r_ekstra bigint; r_status bigint; r_valg bigint; r_ukonkl bigint;
  r_ed1 bigint; r_ed2 bigint; r_cit bigint; v_e1 bigint; v_e2 bigint; v_hs2 bigint; c_cit bigint; c_ed1 bigint;
BEGIN
  INSERT INTO public.source(slags, titel) VALUES ('bog', '__t5_kilde__') RETURNING id INTO src;
  INSERT INTO public.source(slags, titel) VALUES ('bog', '__t5_lokkekilde__') RETURNING id INTO src2;
  INSERT INTO public.estate(navn, slags) VALUES ('__t5_Christianssæde__', 'gård') RETURNING id INTO ex;
  INSERT INTO public.estate(navn, slags) VALUES ('__t5_Aalstrup__', 'gård') RETURNING id INTO ey;
  INSERT INTO public.estate(navn, slags) VALUES ('__t5_Frihedsminde__', NULL) RETURNING id INTO ez;
  INSERT INTO public.estate(navn, slags) VALUES ('__t5_sammenlagt__', 'gård') RETURNING id INTO es;
  INSERT INTO public.estate(navn, slags) VALUES ('__t5_ejer-gods__', NULL) RETURNING id INTO ek;
  INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle) VALUES ('estate',es,'estate',ez,'sammenlagt_i');
  INSERT INTO public.person DEFAULT VALUES RETURNING id INTO p;
  INSERT INTO public.person DEFAULT VALUES RETURNING id INTO p2;
  INSERT INTO public.media(slags) VALUES ('gods') RETURNING id INTO md;

  -- Kilden som importens ejerforhold: én uforanderlig påstand, én afklaret konklusion, én primær citation med side.
  INSERT INTO public.relation(id,subjekt_type,subjekt_id,objekt_type,objekt_id,rolle,periode_raw,erhvervelsesmaade,
                              start_min,start_max,end_min,end_max,period_type,konfidens)
    VALUES (r_src,'person',p,'estate',ex,'ejer','1700-1720','født/arvet',
            '1700-01-01','1700-12-31','1720-01-01','1720-12-31','closed','sikker');
  INSERT INTO public.assertion(target_type,target_id,vaerdi_tekst,date_min,date_max,date_qualifier,date_raw,uforanderlig)
    VALUES ('relation',r_src,'ejer','1700-01-01','1720-12-31','between','1700-1720',true) RETURNING id INTO a;
  INSERT INTO public.conclusion(target_type,target_id,valgt_assertion_id,status,blaastemplet_af)
    VALUES ('relation',r_src,a,'afklaret','__t5_udgave__');
  INSERT INTO public.citation(assertion_id,source_id,side,kvalitet) VALUES (a,src,'42','primær');
  -- Lokkemad: et faktum med samme id som kilden, med egen påstand, konklusion og citation (kun target_type adskiller).
  INSERT INTO public.fact(id,subjekt_type,subjekt_id,faktatype) VALUES (r_src,'person',p,'erhverv') RETURNING id INTO f_lok;
  INSERT INTO public.assertion(target_type,target_id,vaerdi_tekst) VALUES ('fact',f_lok,'godsejer') RETURNING id INTO a_lok;
  INSERT INTO public.conclusion(target_type,target_id,valgt_assertion_id,status) VALUES ('fact',f_lok,a_lok,'afklaret');
  INSERT INTO public.citation(assertion_id,source_id,kvalitet,citat_tekst) VALUES (a_lok,src2,'sekundær','lokkemad');
  -- Et ejerforhold uden periode (NULL), med sekundær citation uden side.
  INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle) VALUES ('person',p2,'estate',ex,'ejer')
    RETURNING id INTO r_null;
  INSERT INTO public.assertion(target_type,target_id,vaerdi_tekst,uforanderlig) VALUES ('relation',r_null,'ejer',true) RETURNING id INTO a;
  INSERT INTO public.conclusion(target_type,target_id,valgt_assertion_id,status) VALUES ('relation',r_null,a,'afklaret');
  INSERT INTO public.citation(assertion_id,source_id,kvalitet) VALUES (a,src,'sekundær');
  -- Uklar kilde: ingen citation; to citationer på én påstand; to påstande med hver sin citation.
  INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle,periode_raw) VALUES ('person',p,'estate',ex,'ejer','1730')
    RETURNING id INTO r_ingen;
  INSERT INTO public.assertion(target_type,target_id,vaerdi_tekst) VALUES ('relation',r_ingen,'ejer');
  INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle,periode_raw) VALUES ('person',p,'estate',ex,'ejer','1740')
    RETURNING id INTO r_to;
  INSERT INTO public.assertion(target_type,target_id,vaerdi_tekst) VALUES ('relation',r_to,'ejer') RETURNING id INTO a;
  INSERT INTO public.citation(assertion_id,source_id,kvalitet) VALUES (a,src,'primær'), (a,src2,'primær');
  INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle,periode_raw) VALUES ('person',p,'estate',ex,'ejer','1750')
    RETURNING id INTO r_to2;
  INSERT INTO public.assertion(target_type,target_id,vaerdi_tekst) VALUES ('relation',r_to2,'ejer') RETURNING id INTO a;
  INSERT INTO public.citation(assertion_id,source_id,kvalitet) VALUES (a,src,'primær');
  INSERT INTO public.assertion(target_type,target_id,vaerdi_tekst) VALUES ('relation',r_to2,'ejer') RETURNING id INTO a;
  INSERT INTO public.citation(assertion_id,source_id,kvalitet) VALUES (a,src2,'primær');
  -- Forkerte kilder: en forpagter, et billede og et »ejerforhold« med et gods som ejer.
  INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle) VALUES ('person',p,'estate',ex,'forpagter')
    RETURNING id INTO r_fp;
  INSERT INTO public.assertion(target_type,target_id,vaerdi_tekst) VALUES ('relation',r_fp,'forpagter') RETURNING id INTO a;
  INSERT INTO public.citation(assertion_id,source_id,kvalitet) VALUES (a,src,'primær');
  INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle) VALUES ('media',md,'estate',ex,'afbildet')
    RETURNING id INTO r_afb;
  INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle) VALUES ('estate',ek,'estate',ex,'ejer')
    RETURNING id INTO r_estsub;
  INSERT INTO public.assertion(target_type,target_id,vaerdi_tekst) VALUES ('relation',r_estsub,'ejer') RETURNING id INTO a;
  INSERT INTO public.citation(assertion_id,source_id,kvalitet) VALUES (a,src,'primær');
  -- Uklar kilde ud over citationerne (hver med præcis én citation): en ekstra påstand uden citation; en konklusion, der
  -- er tilbagetrukket; en konklusion, der vælger en anden påstand; ingen konklusion.
  INSERT INTO public.person DEFAULT VALUES RETURNING id INTO p3;
  INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle,periode_raw) VALUES ('person',p3,'estate',ex,'ejer','1801')
    RETURNING id INTO r_ekstra;
  INSERT INTO public.assertion(target_type,target_id,vaerdi_tekst) VALUES ('relation',r_ekstra,'ejer') RETURNING id INTO a;
  INSERT INTO public.citation(assertion_id,source_id,kvalitet) VALUES (a,src,'primær');
  INSERT INTO public.conclusion(target_type,target_id,valgt_assertion_id,status) VALUES ('relation',r_ekstra,a,'afklaret');
  INSERT INTO public.assertion(target_type,target_id,vaerdi_tekst) VALUES ('relation',r_ekstra,'ejer');
  INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle,periode_raw) VALUES ('person',p3,'estate',ex,'ejer','1802')
    RETURNING id INTO r_status;
  INSERT INTO public.assertion(target_type,target_id,vaerdi_tekst) VALUES ('relation',r_status,'ejer') RETURNING id INTO a;
  INSERT INTO public.citation(assertion_id,source_id,kvalitet) VALUES (a,src,'primær');
  INSERT INTO public.conclusion(target_type,target_id,valgt_assertion_id,status) VALUES ('relation',r_status,a,'tilbagetrukket');
  INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle,periode_raw) VALUES ('person',p3,'estate',ex,'ejer','1803')
    RETURNING id INTO r_valg;
  INSERT INTO public.assertion(target_type,target_id,vaerdi_tekst) VALUES ('relation',r_valg,'ejer') RETURNING id INTO a;
  INSERT INTO public.citation(assertion_id,source_id,kvalitet) VALUES (a,src,'primær');
  INSERT INTO public.conclusion(target_type,target_id,valgt_assertion_id,status) VALUES ('relation',r_valg,NULL,'afklaret');
  INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle,periode_raw) VALUES ('person',p3,'estate',ex,'ejer','1804')
    RETURNING id INTO r_ukonkl;
  INSERT INTO public.assertion(target_type,target_id,vaerdi_tekst) VALUES ('relation',r_ukonkl,'ejer') RETURNING id INTO a;
  INSERT INTO public.citation(assertion_id,source_id,kvalitet) VALUES (a,src,'primær');
  -- Samme ejer fra to udgaver med samme periode (afgørelse 4A), og et ejerforhold, hvis citation har bogens ordlyd.
  INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle,periode_raw) VALUES ('person',p3,'estate',ex,'ejer','1810')
    RETURNING id INTO r_ed1;
  INSERT INTO public.assertion(target_type,target_id,vaerdi_tekst) VALUES ('relation',r_ed1,'ejer') RETURNING id INTO a;
  INSERT INTO public.citation(assertion_id,source_id,kvalitet) VALUES (a,src,'primær') RETURNING id INTO c_ed1;
  INSERT INTO public.conclusion(target_type,target_id,valgt_assertion_id,status) VALUES ('relation',r_ed1,a,'afklaret');
  INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle,periode_raw) VALUES ('person',p3,'estate',ex,'ejer','1810')
    RETURNING id INTO r_ed2;
  INSERT INTO public.assertion(target_type,target_id,vaerdi_tekst) VALUES ('relation',r_ed2,'ejer') RETURNING id INTO a;
  INSERT INTO public.citation(assertion_id,source_id,kvalitet) VALUES (a,src2,'primær');
  INSERT INTO public.conclusion(target_type,target_id,valgt_assertion_id,status) VALUES ('relation',r_ed2,a,'afklaret');
  INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle,periode_raw) VALUES ('person',p3,'estate',ex,'ejer','1820')
    RETURNING id INTO r_cit;
  INSERT INTO public.assertion(target_type,target_id,vaerdi_tekst) VALUES ('relation',r_cit,'ejer') RETURNING id INTO a;
  INSERT INTO public.citation(assertion_id,source_id,kvalitet,citat_tekst) VALUES (a,src,'primær','__t5_bogens ordlyd__') RETURNING id INTO c_cit;
  INSERT INTO public.conclusion(target_type,target_id,valgt_assertion_id,status) VALUES ('relation',r_cit,a,'afklaret');

  -- (0) Kun redaktionen.
  PERFORM pg_temp.g471_afvist_som('gaest', format('SELECT public.red_kopier_ejerforhold(%s, %s, %L)', r_src, ey, 'c'),
    '42501', NULL, 'red_kopier_ejerforhold');
  FOREACH k IN ARRAY ARRAY['uden_profil','medlem'] LOOP
    PERFORM pg_temp.g471_afvist_som(k, format('SELECT public.red_kopier_ejerforhold(%s, %s, %L)', r_src, ey, 'c'),
      'P0001', 'Kun redaktion', 'red_kopier_ejerforhold');
  END LOOP;

  -- (a) Kopien: ny relation person → til med kildens periode, én påstand, én afklaret konklusion og én citation med
  -- kildens kilde, kvalitet og side og bogens fulde formulering som citat. Kilden får samme citat (dens var NULL);
  -- ellers er den urørt.
  v_src_foer := pg_temp.g471_evidens(r_src);
  SELECT id, cs INTO v_k, v_cs_k FROM pg_temp.g471_kald(
    format('public.red_kopier_ejerforhold(%s, %s, %L)', r_src, ey, '__t5_Christianssæde med Aalstrup og Frihedsminde__'));
  IF v_k IS NULL OR v_k = r_src THEN RAISE EXCEPTION 'GODSER_T5: kopien gav id % (kilde %)', v_k, r_src; END IF;
  SELECT * INTO v_ny FROM public.relation WHERE id = v_k;
  SELECT * INTO v_rel_row FROM public.relation WHERE id = r_src;
  IF v_ny.subjekt_type <> 'person' OR v_ny.subjekt_id <> p OR v_ny.objekt_type <> 'estate' OR v_ny.objekt_id <> ey
     OR v_ny.rolle <> 'ejer' OR v_ny.periode_raw IS DISTINCT FROM '1700-1720'
     OR (to_jsonb(v_ny) - ARRAY['id','objekt_id']) IS DISTINCT FROM (to_jsonb(v_rel_row) - ARRAY['id','objekt_id']) THEN
    RAISE EXCEPTION 'GODSER_T5: kopien er ikke kildens ejerforhold flyttet til til: % (kilde %)', to_jsonb(v_ny), to_jsonb(v_rel_row);
  END IF;
  PERFORM pg_temp.g471_kraev_evidens(v_k, 'ejer', '1700-1720', src, 'primær', '42',
    '__t5_Christianssæde med Aalstrup og Frihedsminde__', 'kopien');
  IF NOT EXISTS (SELECT 1 FROM public.assertion a WHERE a.target_type = 'relation' AND a.target_id = v_k
                    AND a.date_min = '1700-01-01' AND a.date_max = '1720-12-31' AND a.date_qualifier = 'between') THEN
    RAISE EXCEPTION 'GODSER_T5: kopiens påstand har ikke kildens datering';
  END IF;
  IF v_cs_k IS NULL OR NOT EXISTS (SELECT 1 FROM public.change_set cs WHERE cs.id = v_cs_k AND cs.operation = 'red_kopier_ejerforhold'
                                      AND cs.subjekt_type = 'estate' AND cs.subjekt_id = ey) THEN
    RAISE EXCEPTION 'GODSER_T5: red_kopier_ejerforhold åbnede ikke sit eget ændringssæt (estate, %)', ey;
  END IF;
  IF (pg_temp.g471_evidens(r_src) - 'citation') IS DISTINCT FROM (v_src_foer - 'citation')
     OR pg_temp.g471_evidens(r_src)->'citation'
        IS DISTINCT FROM jsonb_build_array((v_src_foer->'citation'->0)
                           || jsonb_build_object('citat_tekst', '__t5_Christianssæde med Aalstrup og Frihedsminde__')) THEN
    RAISE EXCEPTION 'GODSER_T5: kopieringen gav ikke kilden bogens formulering som citat (eller ændrede andet): %',
      pg_temp.g471_evidens(r_src);
  END IF;

  -- (b) Idempotent på (person, til, rolle, periode): samme id, intet nyt sæt, intet nyt — også med et andet citat.
  SELECT count(*) INTO v_sets FROM public.change_set;
  SELECT count(*) INTO v_rel FROM public.relation;
  SELECT count(*) INTO v_ass FROM public.assertion;
  SELECT count(*) INTO v_kon FROM public.conclusion;
  SELECT count(*) INTO v_cit FROM public.citation;
  FOREACH k IN ARRAY ARRAY['__t5_Christianssæde med Aalstrup og Frihedsminde__', '__t5_andet citat__'] LOOP
    SELECT id, cs INTO v_id, v_cs FROM pg_temp.g471_kald(format('public.red_kopier_ejerforhold(%s, %s, %L)', r_src, ey, k));
    IF v_id IS DISTINCT FROM v_k OR v_cs IS NOT NULL THEN
      RAISE EXCEPTION 'GODSER_T5: gentaget kopi gav id % og sæt % (ventede % og intet sæt)', v_id, v_cs, v_k;
    END IF;
  END LOOP;

  -- (c) Kilde uden periode (NULL): to kald giver samme id (NULL er lig NULL i nøglen); kildens kvalitet følger med.
  SELECT id INTO v_kn FROM pg_temp.g471_kald(format('public.red_kopier_ejerforhold(%s, %s, %L)', r_null, ey, '__t5_uden periode__'));
  SELECT id, cs INTO v_id, v_cs FROM pg_temp.g471_kald(format('public.red_kopier_ejerforhold(%s, %s, %L)', r_null, ey, '__t5_uden periode__'));
  IF v_kn IS NULL OR v_id IS DISTINCT FROM v_kn OR v_cs IS NOT NULL THEN
    RAISE EXCEPTION 'GODSER_T5: kopi uden periode var ikke idempotent (% og %, sæt %)', v_kn, v_id, v_cs;
  END IF;
  IF (SELECT count(*) FROM public.relation WHERE subjekt_type = 'person' AND subjekt_id = p2 AND objekt_type = 'estate'
        AND objekt_id = ey AND rolle = 'ejer') <> 1 THEN
    RAISE EXCEPTION 'GODSER_T5: kopi uden periode gav mere end ét ejerforhold';
  END IF;
  PERFORM pg_temp.g471_kraev_evidens(v_kn, 'ejer', NULL, src, 'sekundær', NULL, '__t5_uden periode__', 'kopien uden periode');
  v_sets := v_sets + 1; v_rel := v_rel + 1; v_ass := v_ass + 1; v_kon := v_kon + 1; v_cit := v_cit + 1;

  -- (d) Afvisninger, før noget skrives.
  FOREACH v_id IN ARRAY ARRAY[r_ingen, r_to, r_to2, r_ekstra, r_status, r_valg, r_ukonkl] LOOP
    PERFORM pg_temp.g471_afvist_som('redaktion', format('SELECT public.red_kopier_ejerforhold(%s, %s, %L)', v_id, ey, 'c'),
      '23514', 'EJERFORHOLD_KILDE_UKLAR', format('kopi af et uklart ejerforhold (%s)',
        CASE v_id WHEN r_ingen THEN 'ingen citation' WHEN r_to THEN 'to citationer' WHEN r_to2 THEN 'to påstande med citation'
                  WHEN r_ekstra THEN 'ekstra påstand uden citation' WHEN r_status THEN 'tilbagetrukket konklusion'
                  WHEN r_valg THEN 'konklusionen vælger ikke påstanden' ELSE 'ingen konklusion' END));
  END LOOP;
  FOREACH v_id IN ARRAY ARRAY[r_fp, r_afb, r_estsub] LOOP
    PERFORM pg_temp.g471_afvist_som('redaktion', format('SELECT public.red_kopier_ejerforhold(%s, %s, %L)', v_id, ey, 'c'),
      '23514', 'EJERFORHOLD_KILDE_ROLLE', 'kopi af en relation, der ikke er et ejerforhold person → gods');
  END LOOP;
  PERFORM pg_temp.g471_afvist_som('redaktion', format('SELECT public.red_kopier_ejerforhold(-987650001, %s, %L)', ey, 'c'),
    'P0002', 'RELATION_FINDES_IKKE', 'kopi af en relation, der ikke findes');
  PERFORM pg_temp.g471_afvist_som('redaktion', format('SELECT public.red_kopier_ejerforhold(NULL, %s, %L)', ey, 'c'),
    'P0002', 'RELATION_FINDES_IKKE', 'kopi af NULL');
  PERFORM pg_temp.g471_afvist_som('redaktion', format('SELECT public.red_kopier_ejerforhold(%s, -987650001, %L)', r_src, 'c'),
    'P0002', 'ESTATE_FINDES_IKKE', 'kopi til et gods, der ikke findes');
  PERFORM pg_temp.g471_afvist_som('redaktion', format('SELECT public.red_kopier_ejerforhold(%s, NULL, %L)', r_src, 'c'),
    'P0002', 'ESTATE_FINDES_IKKE', 'kopi til NULL');
  PERFORM pg_temp.g471_afvist_som('redaktion', format('SELECT public.red_kopier_ejerforhold(%s, %s, %L)', r_src, es, 'c'),
    '23514', 'ESTATE_ER_SAMMENLAGT', 'kopi til en sammenlagt række');
  PERFORM pg_temp.g471_afvist_som('redaktion', format('SELECT public.red_kopier_ejerforhold(%s, %s, %L)', r_src, ez, '  '),
    '22023', 'ESTATE_CITAT_TOMT', 'kopi med tomt citat');
  PERFORM pg_temp.g471_afvist_som('redaktion', format('SELECT public.red_kopier_ejerforhold(%s, %s, NULL)', r_src, ez),
    '22023', 'ESTATE_CITAT_TOMT', 'kopi uden citat');
  -- Kopi til kildens eget gods: nøglen rammer kilden selv, så den returneres uden ændringssæt.
  SELECT id, cs INTO v_id, v_cs FROM pg_temp.g471_kald(format('public.red_kopier_ejerforhold(%s, %s, %L)', r_src, ex, 'c'));
  IF v_id IS DISTINCT FROM r_src OR v_cs IS NOT NULL THEN
    RAISE EXCEPTION 'GODSER_T5: kopi til kildens eget gods gav % og sæt % (ventede kilden og intet sæt)', v_id, v_cs;
  END IF;
  IF (SELECT count(*) FROM public.change_set) <> v_sets OR (SELECT count(*) FROM public.relation) <> v_rel
     OR (SELECT count(*) FROM public.assertion) <> v_ass OR (SELECT count(*) FROM public.conclusion) <> v_kon
     OR (SELECT count(*) FROM public.citation) <> v_cit THEN
    RAISE EXCEPTION 'GODSER_T5: gentagne eller afviste kopier skrev noget';
  END IF;

  -- (e) Fortryd: kopien og dens påstand, konklusion og citation er væk; kilden er som før; en ny kopi er mulig.
  SELECT a2.id INTO a FROM public.assertion a2 WHERE a2.target_type = 'relation' AND a2.target_id = v_k;
  PERFORM pg_temp.g471_som('redaktion', format('SELECT public.red_fortryd_change_set(%s)', v_cs_k));
  IF pg_temp.g471_evidens(v_k) IS DISTINCT FROM jsonb_build_object('relation', NULL, 'assertion', NULL, 'conclusion', NULL, 'citation', NULL)
     OR EXISTS (SELECT 1 FROM public.citation c WHERE c.assertion_id = a) THEN
    RAISE EXCEPTION 'GODSER_T5: fortryd af kopien efterlod %', pg_temp.g471_evidens(v_k);
  END IF;
  IF pg_temp.g471_evidens(r_src) IS DISTINCT FROM v_src_foer THEN
    RAISE EXCEPTION 'GODSER_T5: fortryd af kopien ændrede kilden';
  END IF;
  SELECT id INTO v_id FROM pg_temp.g471_kald(format('public.red_kopier_ejerforhold(%s, %s, %L)', r_src, ey, 'c'));
  IF v_id IS NULL OR v_id = v_k THEN RAISE EXCEPTION 'GODSER_T5: ny kopi efter fortryd gav %', v_id; END IF;

  -- (f) Samme ejer fra to udgaver (samme periode, hver sin kilde) til samme gård: to ejerforhold, hver med sin kilde;
  -- gentaget kald med samme kilde giver det eksisterende id.
  SELECT id INTO v_e1 FROM pg_temp.g471_kald(format('public.red_kopier_ejerforhold(%s, %s, %L)', r_ed1, ey, '__t5_udgave 1__'));
  SELECT id INTO v_e2 FROM pg_temp.g471_kald(format('public.red_kopier_ejerforhold(%s, %s, %L)', r_ed2, ey, '__t5_udgave 2__'));
  IF v_e1 IS NULL OR v_e2 IS NULL OR v_e1 = v_e2 THEN
    RAISE EXCEPTION 'GODSER_T5: to udgavers ejerforhold gav ikke to kopier (% og %)', v_e1, v_e2;
  END IF;
  PERFORM pg_temp.g471_kraev_evidens(v_e1, 'ejer', NULL, src, 'primær', NULL, '__t5_udgave 1__', 'kopien fra udgave 1');
  PERFORM pg_temp.g471_kraev_evidens(v_e2, 'ejer', NULL, src2, 'primær', NULL, '__t5_udgave 2__', 'kopien fra udgave 2');
  FOREACH k IN ARRAY ARRAY['1','2'] LOOP
    SELECT id, cs INTO v_id, v_cs FROM pg_temp.g471_kald(format('public.red_kopier_ejerforhold(%s, %s, %L)',
      CASE k WHEN '1' THEN r_ed1 ELSE r_ed2 END, ey, 'igen'));
    IF v_id IS DISTINCT FROM (CASE k WHEN '1' THEN v_e1 ELSE v_e2 END) OR v_cs IS NOT NULL THEN
      RAISE EXCEPTION 'GODSER_T5: gentaget kopi fra udgave % gav % og sæt %', k, v_id, v_cs;
    END IF;
  END LOOP;
  IF (SELECT count(*) FROM public.relation WHERE subjekt_type = 'person' AND subjekt_id = p3 AND objekt_type = 'estate'
        AND objekt_id = ey AND rolle = 'ejer') <> 2 THEN
    RAISE EXCEPTION 'GODSER_T5: to udgavers ejerforhold gav ikke præcis to ejerforhold på gården';
  END IF;
  IF (SELECT citat_tekst FROM public.citation WHERE id = c_ed1) IS DISTINCT FROM '__t5_udgave 1__' THEN
    RAISE EXCEPTION 'GODSER_T5: kildens citation fik ikke citatet fra det første kald';
  END IF;
  -- En kilde, hvis citation allerede har bogens ordlyd, beholder den; kopien får p_citat.
  SELECT id INTO v_id FROM pg_temp.g471_kald(format('public.red_kopier_ejerforhold(%s, %s, %L)', r_cit, ey, '__t5_godsmassen__'));
  IF (SELECT citat_tekst FROM public.citation WHERE id = c_cit) IS DISTINCT FROM '__t5_bogens ordlyd__' THEN
    RAISE EXCEPTION 'GODSER_T5: kopieringen overskrev kildens eksisterende citat';
  END IF;
  PERFORM pg_temp.g471_kraev_evidens(v_id, 'ejer', NULL, src, 'primær', NULL, '__t5_godsmassen__', 'kopien af et citeret ejerforhold');

  -- ===== red_hoerer_under =====
  INSERT INTO public.estate(navn, slags) VALUES ('__t5_g1__', 'gård') RETURNING id INTO g1;
  INSERT INTO public.estate(navn, slags) VALUES ('__t5_g2__', 'gård') RETURNING id INTO g2;
  INSERT INTO public.estate(navn, slags) VALUES ('__t5_Grevskabet__', 'grevskab') RETURNING id INTO m1;
  INSERT INTO public.estate(navn, slags) VALUES ('__t5_uden art__', NULL) RETURNING id INTO n1;
  INSERT INTO public.estate(navn, slags) VALUES ('__t5_gs__', 'gård') RETURNING id INTO gs;
  INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle) VALUES ('estate',gs,'estate',g2,'sammenlagt_i');

  -- (0) Kun redaktionen.
  PERFORM pg_temp.g471_afvist_som('gaest', format('SELECT public.red_hoerer_under(%s, %s, NULL, %s, %L)', g1, m1, src, 'c'),
    '42501', NULL, 'red_hoerer_under');
  FOREACH k IN ARRAY ARRAY['uden_profil','medlem'] LOOP
    PERFORM pg_temp.g471_afvist_som(k, format('SELECT public.red_hoerer_under(%s, %s, NULL, %s, %L)', g1, m1, src, 'c'),
      'P0001', 'Kun redaktion', 'red_hoerer_under');
  END LOOP;

  -- (a) gård → majorat med periode, påstand, afklaret konklusion og citation med kilde og citat.
  SELECT id, cs INTO v_h, v_cs_h FROM pg_temp.g471_kald(
    format('public.red_hoerer_under(%s, %s, %L, %s, %L)', g1, m1, '1729-1924', src, '__t5_under grevskabet__'));
  IF NOT EXISTS (SELECT 1 FROM public.relation r WHERE r.id = v_h AND r.subjekt_type = 'estate' AND r.subjekt_id = g1
                    AND r.objekt_type = 'estate' AND r.objekt_id = m1 AND r.rolle = 'hører_under' AND r.periode_raw = '1729-1924') THEN
    RAISE EXCEPTION 'GODSER_T5: red_hoerer_under gav ikke relationen gård → majorat (%)', pg_temp.g471_evidens(v_h);
  END IF;
  PERFORM pg_temp.g471_kraev_evidens(v_h, 'hører_under', '1729-1924', src, 'primær', NULL, '__t5_under grevskabet__', 'hører under');
  IF v_cs_h IS NULL OR NOT EXISTS (SELECT 1 FROM public.change_set cs WHERE cs.id = v_cs_h AND cs.operation = 'red_hoerer_under'
                                      AND cs.subjekt_type = 'estate' AND cs.subjekt_id = g1) THEN
    RAISE EXCEPTION 'GODSER_T5: red_hoerer_under åbnede ikke sit eget ændringssæt (estate, %)', g1;
  END IF;

  -- (b) Idempotent på (gård, majorat, periode), også med mellemrum om perioden.
  SELECT count(*) INTO v_sets FROM public.change_set;
  SELECT count(*) INTO v_rel FROM public.relation;
  FOREACH k IN ARRAY ARRAY['1729-1924', ' 1729-1924 '] LOOP
    SELECT id, cs INTO v_id, v_cs FROM pg_temp.g471_kald(format('public.red_hoerer_under(%s, %s, %L, %s, %L)', g1, m1, k, src, 'x'));
    IF v_id IS DISTINCT FROM v_h OR v_cs IS NOT NULL THEN
      RAISE EXCEPTION 'GODSER_T5: gentaget hører under (»%«) gav % og sæt % (ventede % og intet sæt)', k, v_id, v_cs, v_h;
    END IF;
  END LOOP;
  -- (c) Uden periode: NULL og tom tekst er samme nøgle.
  SELECT id INTO v_hn FROM pg_temp.g471_kald(format('public.red_hoerer_under(%s, %s, NULL, %s, %L)', g2, m1, src, '__t5_uden periode__'));
  FOREACH k IN ARRAY ARRAY['NULL', quote_literal('')] LOOP
    SELECT id, cs INTO v_id, v_cs FROM pg_temp.g471_kald(format('public.red_hoerer_under(%s, %s, %s, %s, %L)', g2, m1, k, src, 'x'));
    IF v_hn IS NULL OR v_id IS DISTINCT FROM v_hn OR v_cs IS NOT NULL THEN
      RAISE EXCEPTION 'GODSER_T5: hører under uden periode (%) var ikke idempotent (% og %, sæt %)', k, v_hn, v_id, v_cs;
    END IF;
  END LOOP;
  PERFORM pg_temp.g471_kraev_evidens(v_hn, 'hører_under', NULL, src, 'primær', NULL, '__t5_uden periode__', 'hører under uden periode');
  -- Samme gård, majorat og periode fra en anden kilde: en ny relation med sin egen kilde; gentaget kald giver den igen.
  SELECT id INTO v_hs2 FROM pg_temp.g471_kald(format('public.red_hoerer_under(%s, %s, %L, %s, %L)', g1, m1, '1729-1924', src2, '__t5_anden udgave__'));
  SELECT id, cs INTO v_id, v_cs FROM pg_temp.g471_kald(format('public.red_hoerer_under(%s, %s, %L, %s, %L)', g1, m1, '1729-1924', src2, 'x'));
  IF v_hs2 IS NULL OR v_hs2 = v_h OR v_id IS DISTINCT FROM v_hs2 OR v_cs IS NOT NULL THEN
    RAISE EXCEPTION 'GODSER_T5: hører under fra en anden kilde gav % (første %), gentaget % og sæt %', v_hs2, v_h, v_id, v_cs;
  END IF;
  PERFORM pg_temp.g471_kraev_evidens(v_hs2, 'hører_under', '1729-1924', src2, 'primær', NULL, '__t5_anden udgave__', 'hører under fra anden kilde');
  v_sets := v_sets + 2; v_rel := v_rel + 2;

  -- (d) Afvisninger.
  PERFORM pg_temp.g471_afvist_som('redaktion', format('SELECT public.red_hoerer_under(%s, %s, NULL, %s, %L)', n1, m1, src, 'c'),
    '23514', 'ESTATE_HOERER_UNDER_ART', 'hører under fra en række uden slags gård');
  PERFORM pg_temp.g471_afvist_som('redaktion', format('SELECT public.red_hoerer_under(%s, %s, NULL, %s, %L)', g1, g2, src, 'c'),
    '23514', 'ESTATE_HOERER_UNDER_ART', 'hører under en gård');
  PERFORM pg_temp.g471_afvist_som('redaktion', format('SELECT public.red_hoerer_under(%s, %s, NULL, %s, %L)', m1, m1, src, 'c'),
    '23514', 'ESTATE_RELATION_SELV', 'hører under sig selv');
  PERFORM pg_temp.g471_afvist_som('redaktion', format('SELECT public.red_hoerer_under(%s, %s, NULL, %s, %L)', gs, m1, src, 'c'),
    '23514', 'ESTATE_ER_SAMMENLAGT', 'hører under fra en sammenlagt række');
  PERFORM pg_temp.g471_afvist_som('redaktion', format('SELECT public.red_hoerer_under(-987650001, %s, NULL, %s, %L)', m1, src, 'c'),
    'P0002', 'ESTATE_FINDES_IKKE', 'hører under fra en gård, der ikke findes');
  PERFORM pg_temp.g471_afvist_som('redaktion', format('SELECT public.red_hoerer_under(%s, NULL, NULL, %s, %L)', g1, src, 'c'),
    'P0002', 'ESTATE_FINDES_IKKE', 'hører under NULL');
  PERFORM pg_temp.g471_afvist_som('redaktion', format('SELECT public.red_hoerer_under(%s, %s, %L, -987650001, %L)', g1, m1, '1800', 'c'),
    'P0002', 'KILDE_FINDES_IKKE', 'hører under med en kilde, der ikke findes');
  PERFORM pg_temp.g471_afvist_som('redaktion', format('SELECT public.red_hoerer_under(%s, %s, %L, NULL, %L)', g1, m1, '1800', 'c'),
    'P0002', 'KILDE_FINDES_IKKE', 'hører under uden kilde');
  PERFORM pg_temp.g471_afvist_som('redaktion', format('SELECT public.red_hoerer_under(%s, %s, %L, %s, %L)', g1, m1, '1800', src, ''),
    '22023', 'ESTATE_CITAT_TOMT', 'hører under med tomt citat');
  IF (SELECT count(*) FROM public.change_set) <> v_sets OR (SELECT count(*) FROM public.relation) <> v_rel THEN
    RAISE EXCEPTION 'GODSER_T5: gentagne eller afviste hører under skrev noget';
  END IF;

  -- (e) Fortryd: relationen og dens påstand, konklusion og citation er væk.
  SELECT a2.id INTO a FROM public.assertion a2 WHERE a2.target_type = 'relation' AND a2.target_id = v_h;
  PERFORM pg_temp.g471_som('redaktion', format('SELECT public.red_fortryd_change_set(%s)', v_cs_h));
  IF pg_temp.g471_evidens(v_h) IS DISTINCT FROM jsonb_build_object('relation', NULL, 'assertion', NULL, 'conclusion', NULL, 'citation', NULL)
     OR EXISTS (SELECT 1 FROM public.citation c WHERE c.assertion_id = a) THEN
    RAISE EXCEPTION 'GODSER_T5: fortryd af hører under efterlod %', pg_temp.g471_evidens(v_h);
  END IF;
END
$t5$;

-- NY AFSNIT TILFØJES HER (før OK-linjen).
ROLLBACK;
\echo OK test-godser-fase1
