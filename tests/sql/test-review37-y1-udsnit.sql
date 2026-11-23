-- Review 37 Y1 + D8 (#397): red_person_grid_udsnit giver præcis de samme rækker som det fulde gitter.
--  (1) Vinduer à 2 i id-orden (keyset til tomt vindue) = red_person_grid() (samme md5, ingen dubletter), og ét vindue à
--      1000 ligeså.
--  (2) Enkeltpersonkald = personens række i det fulde gitter; ukendt person giver 0 rækker.
--  (3) p_antal uden for 1-1000 afvises.
--  (4) anon har ikke EXECUTE; gæst/uden profil/medlem afvises med 'Kun redaktion'.
--  (5) red_ret_ocr_felt (D8) returnerer udsnittets række for den rettede person.
-- Syntetiske personer med negative id'er dækker gitterets grene: ét stabilt anker med kildebelagte fakta, titel,
-- familie og relation; uden anker (display-fallback); to ankre; og en samme_som-kæde, hvor midterpersonen er både
-- alias og kanonisk. Alt rulles tilbage. Planfejlen (generisk plan efter 5 kald) kan ikke ses med så få personer;
-- den vogtes af db-verify.sql (proconfig) og blev målt på en prod-kopi.
-- Forvent: NOTICE "OK: review37 y1 udsnit". Køres i CI mod frisk schema (»Evidens-hardening på frisk schema-sti«).
\set ON_ERROR_STOP on
BEGIN;
\ir fixtures/kalder-matrix.sql
SELECT pg_temp.km_kaldere();

INSERT INTO public.source(id,slags,titel,udgave,aar,import_key) VALUES
  (-93701,'DAA-udgave','Y1-test A','DAA Y1 A',2001,'y1-test-a'),
  (-93702,'DAA-udgave','Y1-test B','DAA Y1 B',2002,'y1-test-b');
INSERT INTO public.person(id,levende,privat,staged,koen) VALUES
  (-937101,false,false,false,'mand'),    -- A: stabilt anker, kildebelagte navn/fødsel/død, titel, familie
  (-937102,false,false,false,'kvinde'),  -- B: stabilt anker, navn; A's partner
  (-937103,false,false,false,NULL),      -- C: intet anker, afklaret navn (display-fallback); barn af A+B
  (-937104,false,false,false,NULL),      -- D: to ankre
  (-937105,false,false,false,NULL),      -- E: alias i kæden E → F → A
  (-937106,false,false,false,NULL);      -- F: både alias og kanonisk
SELECT set_config('app.change_set_id','',false);
INSERT INTO public.person_external_id(person_id,source_id,linje,nr,record_key,slaegtled_lokal) VALUES
  (-937101,-93701,'I',1,'y1-r1',1),
  (-937102,-93701,'I',2,'y1-r2',1),
  (-937104,-93701,'I',4,'y1-r4',2),
  (-937104,-93702,'II',4,'y1-r4b',2);

-- Afklaret faktum med påstand og (valgfri) citation fra p_source.
CREATE FUNCTION pg_temp.y1_fakta(p_person bigint,p_type text,p_tekst text,p_raw text,p_min date,p_max date,
  p_source bigint,p_citat text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_f bigint; v_a bigint;
BEGIN
  INSERT INTO public.fact(subjekt_type,subjekt_id,faktatype) VALUES ('person',p_person,p_type) RETURNING id INTO v_f;
  INSERT INTO public.assertion(target_type,target_id,vaerdi_tekst,date_raw,date_min,date_max,date_qualifier)
    VALUES ('fact',v_f,p_tekst,p_raw,p_min,p_max,CASE WHEN p_raw IS NOT NULL THEN 'exact' END) RETURNING id INTO v_a;
  INSERT INTO public.conclusion(target_type,target_id,valgt_assertion_id,status) VALUES ('fact',v_f,v_a,'afklaret');
  IF p_source IS NOT NULL THEN
    INSERT INTO public.citation(assertion_id,source_id,side,citat_tekst) VALUES (v_a,p_source,'12',p_citat);
  END IF;
END $$;
SELECT pg_temp.y1_fakta(-937101,'navn','Anders Testsen',NULL,NULL,NULL,-93701,'Anders Testsen');
SELECT pg_temp.y1_fakta(-937101,'fødsel',NULL,'1. jan. 1801','1801-01-01','1801-01-01',-93701,'f. 1. jan. 1801');
SELECT pg_temp.y1_fakta(-937101,'død',NULL,'2. feb. 1870','1870-02-02','1870-02-02',-93701,'† 2. feb. 1870');
SELECT pg_temp.y1_fakta(-937101,'titel','Kammerherre',NULL,NULL,NULL,NULL,NULL);
SELECT pg_temp.y1_fakta(-937102,'navn','Bodil Testsen',NULL,NULL,NULL,-93701,'Bodil Testsen?');
SELECT pg_temp.y1_fakta(-937103,'navn','Carl Testsen',NULL,NULL,NULL,NULL,NULL);
SELECT pg_temp.y1_fakta(-937104,'navn','Dorte Testsen',NULL,NULL,NULL,-93701,'Dorte Testsen');
INSERT INTO public.family(id,type) VALUES (-93711,'vielse');
INSERT INTO public.family_member(family_id,person_id,rolle) VALUES
  (-93711,-937101,'partner'),(-93711,-937102,'partner'),(-93711,-937103,'barn');
-- Den inderste kant først (F → A), så kæden E → F → A kan stå (jf. kommentaren i same_as_context).
INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle) VALUES
  ('person',-937106,'person',-937101,'samme_som');
INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle) VALUES
  ('person',-937105,'person',-937106,'samme_som');

-- Fejlteksten fra p_sql kørt som p_kalder (NULL = ingen fejl).
CREATE FUNCTION pg_temp.y1_fejl(p_kalder text,p_sql text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE v_for text:=coalesce(current_setting('request.jwt.claim.sub',true),''); v_msg text;
BEGIN
  BEGIN PERFORM pg_temp.km_antal(p_kalder,p_sql); EXCEPTION WHEN OTHERS THEN v_msg:=SQLERRM; END;
  RESET ROLE;
  PERFORM set_config('request.jwt.claim.sub',v_for,true);
  RETURN v_msg;
END $$;

DO $t$
DECLARE k text; v_msg text; v_fuld text; v_vind text; v_n int; v_nd int; v_efter bigint; v_i int:=0; v_raek jsonb;
  v_ocr jsonb; v_p bigint;
BEGIN
  -- (4) adgang
  IF has_function_privilege('anon','public.red_person_grid_udsnit(bigint,integer,bigint)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.red_person_grid_udsnit(bigint,integer,bigint)','EXECUTE') THEN
    RAISE EXCEPTION 'REVIEW37_Y1_FAILED: forkert EXECUTE-ACL på red_person_grid_udsnit';
  END IF;
  FOREACH k IN ARRAY ARRAY['uden_profil','medlem'] LOOP
    v_msg:=pg_temp.y1_fejl(k,'SELECT * FROM public.red_person_grid_udsnit(NULL,NULL,-937101)');
    IF v_msg IS DISTINCT FROM 'Kun redaktion' THEN
      RAISE EXCEPTION 'REVIEW37_Y1_FAILED: % fik «%» i stedet for «Kun redaktion»',k,coalesce(v_msg,'rækker');
    END IF;
  END LOOP;
  v_msg:=pg_temp.y1_fejl('gaest','SELECT * FROM public.red_person_grid_udsnit(NULL,NULL,-937101)');
  IF v_msg IS NULL OR v_msg NOT LIKE 'permission denied%' THEN
    RAISE EXCEPTION 'REVIEW37_Y1_FAILED: gæst fik «%»',coalesce(v_msg,'rækker');
  END IF;

  -- Resten som redaktion.
  PERFORM set_config('request.jwt.claim.sub','11000000-0000-0000-0000-00000000ca03',true);
  SET LOCAL ROLE authenticated;

  -- (3) grænser
  FOREACH v_n IN ARRAY ARRAY[0,1001,-1] LOOP
    BEGIN
      PERFORM 1 FROM public.red_person_grid_udsnit(NULL,v_n);
      RESET ROLE; RAISE EXCEPTION 'REVIEW37_Y1_FAILED: p_antal=% blev accepteret',v_n;
    EXCEPTION WHEN raise_exception THEN
      IF SQLERRM NOT LIKE 'Udsnittet skal være 1-1000 personer%' THEN RAISE; END IF;
    END;
  END LOOP;

  -- (1) vinduer à 2 til tomt vindue = fuldt gitter
  CREATE TEMP TABLE y1_fuld ON COMMIT DROP AS SELECT g.person_id, to_jsonb(g) AS j FROM public.red_person_grid() g;
  CREATE TEMP TABLE y1_vind(person_id bigint, j jsonb) ON COMMIT DROP;
  LOOP
    v_i:=v_i+1;
    INSERT INTO y1_vind SELECT g.person_id, to_jsonb(g) FROM public.red_person_grid_udsnit(v_efter,2) g;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    EXIT WHEN v_n=0;
    IF v_n>2 THEN RESET ROLE; RAISE EXCEPTION 'REVIEW37_Y1_FAILED: vindue à 2 gav % rækker',v_n; END IF;
    SELECT max(person_id) INTO v_efter FROM y1_vind;
    IF v_i>10000 THEN RESET ROLE; RAISE EXCEPTION 'REVIEW37_Y1_FAILED: vinduerne slutter ikke'; END IF;
  END LOOP;
  SELECT md5(string_agg(j::text,E'\n' ORDER BY person_id)), count(*) INTO v_fuld, v_n FROM y1_fuld;
  SELECT md5(string_agg(j::text,E'\n' ORDER BY person_id)), count(DISTINCT person_id) INTO v_vind, v_nd FROM y1_vind;
  IF v_fuld IS DISTINCT FROM v_vind OR v_nd<>v_n OR (SELECT count(*) FROM y1_vind)<>v_n
     OR (SELECT count(*) FROM y1_fuld WHERE person_id BETWEEN -937106 AND -937101)<>6 THEN
    RESET ROLE; RAISE EXCEPTION 'REVIEW37_Y1_FAILED: vinduer (% distinkte) ≠ fuldt gitter (% rækker)',v_nd,v_n;
  END IF;
  SELECT md5(string_agg(to_jsonb(g)::text,E'\n' ORDER BY g.person_id)) INTO v_vind
    FROM public.red_person_grid_udsnit(NULL,1000) g;
  IF v_n<=1000 AND v_vind IS DISTINCT FROM v_fuld THEN
    RESET ROLE; RAISE EXCEPTION 'REVIEW37_Y1_FAILED: vindue à 1000 ≠ fuldt gitter';
  END IF;

  -- (2) enkeltpersoner = fuldt gitters række; grenene er faktisk ramt
  FOR v_p IN SELECT person_id FROM y1_fuld WHERE person_id BETWEEN -937106 AND -937101 LOOP
    SELECT to_jsonb(g) INTO v_raek FROM public.red_person_grid_udsnit(NULL,NULL,v_p) g;
    IF v_raek IS DISTINCT FROM (SELECT j FROM y1_fuld WHERE person_id=v_p) THEN
      RESET ROLE; RAISE EXCEPTION 'REVIEW37_Y1_FAILED: enkeltkald for % afviger: %',v_p,v_raek;
    END IF;
  END LOOP;
  IF EXISTS (SELECT 1 FROM public.red_person_grid_udsnit(NULL,NULL,-937199)) THEN
    RESET ROLE; RAISE EXCEPTION 'REVIEW37_Y1_FAILED: ukendt person gav en række';
  END IF;
  IF (SELECT j->>'navn' FROM y1_fuld WHERE person_id=-937101) IS DISTINCT FROM 'Anders Testsen'
     OR (SELECT (j->'kan_rettes'->>'navn')::boolean FROM y1_fuld WHERE person_id=-937101) IS NOT TRUE
     OR (SELECT (j->>'antal_titler')::int FROM y1_fuld WHERE person_id=-937101)<>1
     OR (SELECT (j->>'antal_familier')::int FROM y1_fuld WHERE person_id=-937101)<>1
     OR (SELECT j->>'foedsel_min' FROM y1_fuld WHERE person_id=-937101) IS DISTINCT FROM '1801-01-01'
     OR (SELECT j->'qa_koder' FROM y1_fuld WHERE person_id=-937102) IS DISTINCT FROM '["mistænkeligt_ocr_tegn","struktureret_afviger_fra_ocr"]'::jsonb
     OR (SELECT j->>'navn' FROM y1_fuld WHERE person_id=-937103) IS DISTINCT FROM 'Carl Testsen'
     OR (SELECT j->'blokarsager'->>'navn' FROM y1_fuld WHERE person_id=-937103) IS DISTINCT FROM 'ingen_importanker'
     OR (SELECT j->'blokarsager'->>'navn' FROM y1_fuld WHERE person_id=-937104) IS DISTINCT FROM 'flere_importankre'
     OR (SELECT j->>'samme_som_status' FROM y1_fuld WHERE person_id=-937105) IS DISTINCT FROM 'alias'
     OR (SELECT j->>'samme_som_status' FROM y1_fuld WHERE person_id=-937106) IS DISTINCT FROM 'alias'
     OR (SELECT j->>'samme_som_status' FROM y1_fuld WHERE person_id=-937101) IS DISTINCT FROM 'kanonisk' THEN
    RESET ROLE; RAISE EXCEPTION 'REVIEW37_Y1_FAILED: testdata rammer ikke gitterets grene: %',
      (SELECT jsonb_object_agg(person_id,j) FROM y1_fuld WHERE person_id BETWEEN -937106 AND -937101);
  END IF;

  -- (5) D8: OCR-rettelsen returnerer udsnittets række for den rettede person
  v_raek:=(SELECT j FROM y1_fuld WHERE person_id=-937101);
  v_ocr:=public.red_ret_ocr_felt(-937101,v_raek->>'import_key',v_raek->>'record_key','navn',
    v_raek->'input_fingerprint'->>'navn',NULL,'godkendt');
  IF v_ocr->'review_status'->>'navn' IS DISTINCT FROM 'godkendt'
     OR v_ocr IS DISTINCT FROM (SELECT to_jsonb(g) FROM public.red_person_grid_udsnit(NULL,NULL,-937101) g)
     OR v_ocr IS DISTINCT FROM (SELECT to_jsonb(g) FROM public.red_person_grid() g WHERE g.person_id=-937101) THEN
    RESET ROLE; RAISE EXCEPTION 'REVIEW37_Y1_FAILED: red_ret_ocr_felt returnerede %',v_ocr;
  END IF;
  RESET ROLE;
  RAISE NOTICE 'OK: review37 y1 udsnit';
END $t$;
ROLLBACK;
