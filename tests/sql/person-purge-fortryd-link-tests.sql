-- Task 9: egen databasekopi, kun syntetiske data og testnavne i output.
SELECT set_config('request.jwt.claim.sub','a2a00000-0000-4000-8000-00000000a001',false) \g /dev/null
CREATE FUNCTION pg_temp.link_assert(p_ok boolean,p_test text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_ok IS DISTINCT FROM true THEN RAISE EXCEPTION 'TEST_FAILED %',p_test; END IF; END $$;
-- Alle permanente tabeller, inkl. audit, omtaleindeks og private manifests, uden undtagelser.
-- Sekvensforbrug rulles ikke tilbage af PostgreSQL og er bevidst ikke en del af rækkehashen.
CREATE FUNCTION pg_temp.link_hash() RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE r record; v_hash text; v_result jsonb:='{}';
BEGIN
  FOR r IN SELECT n.nspname,c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname IN ('public','private') AND c.relkind IN ('r','p') AND NOT c.relispartition LOOP
    EXECUTE format($q$SELECT encode(extensions.digest(convert_to(coalesce(
      string_agg(to_jsonb(t)::text,E'\n' ORDER BY to_jsonb(t)::text COLLATE "C"),''),'UTF8'),'sha256'),'hex')
      FROM %I.%I t$q$,r.nspname,r.relname) INTO v_hash;
    v_result:=v_result||jsonb_build_object(r.nspname||'.'||r.relname,v_hash);
  END LOOP;
  RETURN v_result;
END $$;
CREATE FUNCTION pg_temp.link_afvis(p_cs bigint,p_force boolean,p_error text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_before jsonb:=pg_temp.link_hash(); v_error text;
BEGIN
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM public.red_fortryd_change_set(p_cs,p_force);
    RESET ROLE;
  EXCEPTION WHEN raise_exception THEN v_error:=SQLERRM;
  END;
  PERFORM pg_temp.link_assert(v_error IS NOT DISTINCT FROM p_error,'fortryd_fejlkode');
  PERFORM pg_temp.link_assert(pg_temp.link_hash() IS NOT DISTINCT FROM v_before,'fortryd_afvist_uaendret');
END $$;

-- Opret en uafhængig højeste række i hver af de otte tabeller, slet den helt,
-- indsæt igen gennem DEFAULT (ingen setval/max+1), og kræv et strengt større id.
BEGIN;
DO $id$
DECLARE r record; v_first bigint; v_next bigint; v_max bigint; v_fact bigint;
BEGIN
  PERFORM purge_test.nyt();
  INSERT INTO public.fact(subjekt_type,subjekt_id,faktatype)
    VALUES ('person',purge_test.id('tredje'),'titel') RETURNING id INTO v_fact;
  FOR r IN SELECT * FROM (VALUES
    ('person','DEFAULT VALUES'),
    ('narrative',format('(subjekt_type,subjekt_id,tekst) VALUES (''person'',%s,''Id-test'')',purge_test.id('tredje'))),
    ('fact',format('(subjekt_type,subjekt_id,faktatype) VALUES (''person'',%s,''titel'')',purge_test.id('tredje'))),
    ('relation',format('(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle) VALUES (''person'',%s,''person'',%s,''test'')',purge_test.id('tredje'),purge_test.id('nabo'))),
    ('assertion',format('(target_type,target_id,vaerdi_tekst) VALUES (''fact'',%s,''Id-test'')',v_fact)),
    ('family','(type) VALUES (''test'')'),
    ('media','(titel) VALUES (''Id-test'')'),
    ('change_set','(operation,summary) VALUES (''test'',''Id-test'')')
  ) x(tabel,indsats) LOOP
    EXECUTE format('INSERT INTO public.%I %s RETURNING id',r.tabel,r.indsats) INTO v_first;
    EXECUTE format('SELECT max(id) FROM public.%I',r.tabel) INTO v_max;
    PERFORM pg_temp.link_assert(v_first=v_max,'id_genbruges_ikke_hoejeste_'||r.tabel);
    EXECUTE format('DELETE FROM public.%I WHERE id=$1',r.tabel) USING v_first;
    EXECUTE format('INSERT INTO public.%I %s RETURNING id',r.tabel,r.indsats) INTO v_next;
    PERFORM pg_temp.link_assert(v_next>v_first,'id_genbruges_ikke_'||r.tabel);
    EXECUTE format('DELETE FROM public.%I WHERE id=$1',r.tabel) USING v_next;
  END LOOP;
END $id$;
ROLLBACK;
\echo OK id_genbruges_ikke_8_tabeller

-- Rigtig fuld sletning med COMMIT/deferred checks; K2 bevarer tredjes notehistorik.
BEGIN;
DO $purge$
DECLARE v_p bigint:=purge_test.id('P'); v_preview jsonb;
BEGIN
  PERFORM purge_test.nyt();
  v_preview:=public.red_slet_person_helt_preview(v_p);
  SET LOCAL ROLE authenticated;
  PERFORM public.red_slet_person_helt(v_p,v_preview->>'sha256');
  RESET ROLE;
  PERFORM pg_temp.link_assert(NOT EXISTS(SELECT 1 FROM public.person WHERE id=v_p),'fortryd_rigtig_purge');
END $purge$;
COMMIT;
BEGIN;
SELECT pg_temp.link_afvis(purge_test.id('saet_note_tredje_link_i_foer'),false,
  'FORTRYD_DOED_LINK: person '||purge_test.id('P'));
SELECT pg_temp.link_afvis(purge_test.id('saet_note_tredje_link_i_foer'),true,
  'FORTRYD_DOED_LINK: person '||purge_test.id('P'));
ROLLBACK;
\echo OK fortryd_doed_link

-- Alle fem kolonner og alle tre måltyper, både med og uden force.
-- Rigtige UPDATE-events på ubundne tekster; ingen fabrikerede snapshots.
BEGIN;
DO $matrix$
DECLARE r record; v_typ text; v_id bigint; v_cs bigint; v_target bigint; v_text text;
BEGIN
  FOREACH v_typ IN ARRAY ARRAY['person','family','media'] LOOP
    -- Sekvens-id og efterfølgende DELETE giver et sikkert fraværende mål.
    PERFORM purge_test.nyt();
    EXECUTE format('INSERT INTO public.%I DEFAULT VALUES RETURNING id',v_typ) INTO v_target;
    EXECUTE format('DELETE FROM public.%I WHERE id=$1',v_typ) USING v_target;
    FOR r IN SELECT * FROM (VALUES ('narrative','tekst'),('note','indhold'),
      ('story','titel'),('story','tekst'),('entity_description','tekst')) x(tabel,kolonne) LOOP
      PERFORM purge_test.nyt();
      v_text:=format('Se [[%s:%s|Syntetisk]].',v_typ,v_target);
      CASE r.tabel
        WHEN 'note' THEN INSERT INTO public.note(target_type,target_id,indhold)
          VALUES ('person',purge_test.id('tredje'),v_text) RETURNING id INTO v_id;
        WHEN 'narrative' THEN INSERT INTO public.narrative(subjekt_type,subjekt_id,tekst)
          VALUES ('person',purge_test.id('tredje'),v_text) RETURNING id INTO v_id;
        WHEN 'story' THEN INSERT INTO public.story(subjekt_type,subjekt_id,titel,tekst)
          VALUES ('person',purge_test.id('tredje'),CASE WHEN r.kolonne='titel' THEN v_text ELSE 'Arkiv' END,
            CASE WHEN r.kolonne='tekst' THEN v_text ELSE 'Arkiv' END) RETURNING id INTO v_id;
        WHEN 'entity_description' THEN INSERT INTO public.entity_description(subjekt_type,subjekt_id,kind,tekst)
          VALUES ('person',purge_test.id('tredje'),'overview',v_text) RETURNING id INTO v_id;
      END CASE;
      v_cs:=public.begin_change_set('link_test','Syntetisk');
      EXECUTE format('UPDATE public.%I SET %I=''Arkiv'' WHERE id=$1',r.tabel,r.kolonne) USING v_id;
      PERFORM purge_test.nyt();
      PERFORM pg_temp.link_afvis(v_cs,false,format('FORTRYD_DOED_LINK: %s %s',v_typ,v_target));
      PERFORM pg_temp.link_afvis(v_cs,true,format('FORTRYD_DOED_LINK: %s %s',v_typ,v_target));
    END LOOP;
  END LOOP;
END $matrix$;
ROLLBACK;
\echo OK fortryd_doed_link_alle_kolonner_og_maal

-- Noten genindsættes FØR personen under inversen. Notens subjekt er tredje,
-- så eksistensvagten for subjektet påvirker ikke prøven af linkets sene kontrol.
BEGIN;
DO $genskab$
DECLARE v_p bigint; v_note bigint; v_cs bigint; v_text text;
BEGIN
  PERFORM purge_test.nyt();
  INSERT INTO public.person DEFAULT VALUES RETURNING id INTO v_p;
  v_text:=format('Se [[person:%s|Syntetisk]].',v_p);
  INSERT INTO public.note(target_type,target_id,indhold) VALUES ('person',purge_test.id('tredje'),v_text) RETURNING id INTO v_note;
  v_cs:=public.begin_change_set('link_test','Syntetisk');
  DELETE FROM public.person WHERE id=v_p;
  DELETE FROM public.note WHERE id=v_note;
  PERFORM purge_test.nyt();
  SET LOCAL ROLE authenticated;
  PERFORM public.red_fortryd_change_set(v_cs);
  RESET ROLE;
  PERFORM pg_temp.link_assert(EXISTS(SELECT 1 FROM public.person WHERE id=v_p)
    AND EXISTS(SELECT 1 FROM public.note WHERE id=v_note AND indhold=v_text),'fortryd_link_til_genskabt_person');
  SET CONSTRAINTS ALL IMMEDIATE;
END $genskab$;
ROLLBACK;
\echo OK fortryd_link_til_genskabt_person

BEGIN;
DO $eksisterende$
DECLARE v_id bigint; v_cs bigint; v_text text; v_force boolean;
BEGIN
  FOREACH v_force IN ARRAY ARRAY[false,true] LOOP
    PERFORM purge_test.nyt();
    v_text:=format('Se [[person:%s|Syntetisk]].',purge_test.id('P'));
    INSERT INTO public.note(target_type,target_id,indhold,privat)
      VALUES ('person',purge_test.id('tredje'),v_text,false) RETURNING id INTO v_id;
    v_cs:=public.begin_change_set('link_test','Syntetisk');
    UPDATE public.note SET privat=true WHERE id=v_id;
    PERFORM purge_test.nyt();
    SET LOCAL ROLE authenticated;
    PERFORM public.red_fortryd_change_set(v_cs,v_force);
    RESET ROLE;
    PERFORM pg_temp.link_assert(EXISTS(SELECT 1 FROM public.note WHERE id=v_id AND indhold=v_text AND NOT privat),
      'fortryd_eksisterende_doedt_link_afviser_ikke');
  END LOOP;
END $eksisterende$;
ROLLBACK;
\echo OK fortryd_eksisterende_doedt_link_afviser_ikke

-- Flere events på samme række: et midlertidigt dødt link i inversen indgår
-- ikke i sluttilstanden. Dette beviser også, at kontrollen ligger EFTER løkken.
BEGIN;
DO $mellemtrin$
DECLARE v_id bigint; v_cs bigint;
BEGIN
  PERFORM purge_test.nyt();
  INSERT INTO public.note(target_type,target_id,indhold)
    VALUES ('person',purge_test.id('tredje'),'Arkiv') RETURNING id INTO v_id;
  v_cs:=public.begin_change_set('link_test','Syntetisk');
  UPDATE public.note SET indhold=format('Se [[person:%s|Syntetisk]].',purge_test.id('P')) WHERE id=v_id;
  UPDATE public.note SET indhold='Rettet' WHERE id=v_id;
  PERFORM purge_test.nyt();
  SET LOCAL ROLE authenticated;
  PERFORM public.red_fortryd_change_set(v_cs);
  RESET ROLE;
  PERFORM pg_temp.link_assert(EXISTS(SELECT 1 FROM public.note WHERE id=v_id AND indhold='Arkiv'),
    'fortryd_mellemtrin_doedt_link_afviser_ikke');
END $mellemtrin$;
ROLLBACK;
\echo OK fortryd_mellemtrin_doedt_link_afviser_ikke

-- Review P2: kun KLIKBARE tokens tæller (læserens parseNarrativ). Et uafsluttet hoved eller et hoved inde i en
-- label er ikke et link: (1) gør fortrydelsen et af dem klikbart, er linket NYT og afvises; (2) genskaber
-- fortrydelsen kun et uafsluttet hoved, indføres intet link.
BEGIN;
DO $klikbar$
DECLARE v_id bigint; v_cs bigint; v_p bigint:=purge_test.id('P'); v_t bigint:=purge_test.id('tredje');
  v_fuld text; v_nu text; v_force boolean;
BEGIN
  v_fuld:=format('Se [[person:%s|Navn]].',v_p);
  FOREACH v_nu IN ARRAY ARRAY[format('Se [[person:%s|ufuldendt',v_p),
                              format('[[person:%s|navn [[person:%s|x]] rest',v_t,v_p)] LOOP
    FOREACH v_force IN ARRAY ARRAY[false,true] LOOP
      PERFORM purge_test.nyt();
      INSERT INTO public.note(target_type,target_id,indhold) VALUES ('person',v_t,v_fuld) RETURNING id INTO v_id;
      v_cs:=public.begin_change_set('link_test','Syntetisk');
      UPDATE public.note SET indhold=v_nu WHERE id=v_id;
      PERFORM purge_test.nyt();
      PERFORM pg_temp.link_afvis(v_cs,v_force,format('FORTRYD_DOED_LINK: person %s',v_p));
    END LOOP;
  END LOOP;
  -- (2) et uafsluttet hoved genskabes: intet klikbart link, fortrydelsen lykkes.
  PERFORM purge_test.nyt();
  INSERT INTO public.note(target_type,target_id,indhold)
    VALUES ('person',v_t,format('Se [[person:%s|ufuldendt',v_p)) RETURNING id INTO v_id;
  v_cs:=public.begin_change_set('link_test','Syntetisk');
  UPDATE public.note SET indhold='Rettet' WHERE id=v_id;
  PERFORM purge_test.nyt();
  SET LOCAL ROLE authenticated;
  PERFORM public.red_fortryd_change_set(v_cs);
  RESET ROLE;
  PERFORM pg_temp.link_assert(EXISTS(SELECT 1 FROM public.note WHERE id=v_id AND indhold=format('Se [[person:%s|ufuldendt',v_p)),
    'fortryd_uafsluttet_hoved_er_intet_link');
END $klikbar$;
ROLLBACK;
\echo OK fortryd_kun_klikbare_links_taeller

-- ALTER COLUMN DROP IDENTITY fjerner sekvenstilknytningen rigtigt. En tvungen
-- exception ruller HELE DDL-subtransaktionen tilbage; ingen kataloghacks/mock af pg_get_serial_sequence.
BEGIN;
DO $sekvens$
DECLARE v_cs bigint; v_seq text:=pg_get_serial_sequence('public.change_set','id'); v_before jsonb;
BEGIN
  PERFORM purge_test.nyt();
  v_cs:=public.begin_change_set('link_test','Syntetisk');
  PERFORM purge_test.nyt();
  v_before:=pg_temp.link_hash();
  BEGIN
    ALTER TABLE public.change_set ALTER COLUMN id DROP IDENTITY;
    PERFORM pg_temp.link_assert(pg_get_serial_sequence('public.change_set','id') IS NULL,'sequence_missing_simuleret');
    PERFORM pg_temp.link_afvis(v_cs,false,'CHANGE_SET_SEQUENCE_MISSING');
    PERFORM pg_temp.link_afvis(v_cs,true,'CHANGE_SET_SEQUENCE_MISSING');
    RAISE EXCEPTION SQLSTATE 'ZX009' USING MESSAGE='rollback_sequence_probe';
  EXCEPTION WHEN SQLSTATE 'ZX009' THEN NULL;
  END;
  PERFORM pg_temp.link_assert(pg_get_serial_sequence('public.change_set','id') IS NOT DISTINCT FROM v_seq
    AND pg_temp.link_hash() IS NOT DISTINCT FROM v_before,'sequence_missing_rollback');
END $sekvens$;
ROLLBACK;
\echo OK fortryd_change_set_sequence_missing
