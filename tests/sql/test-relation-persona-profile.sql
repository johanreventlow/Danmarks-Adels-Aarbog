-- Trin 6d-3 (spec §5.1.1, plan Task 2): relationspersona-writerens profiler er data i private.relation_persona_profile.
-- Writeren vælger gren efter profilens form for (profil, batchens kilde, prædikat) og afviser
-- RELATION_PERSONA_PROFILE_INVALID uden række eller uden form. Opdigtede personer og kilder med negative id'er:
-- -5401 står for en kilde med 2018-20-profilerne (f5b_profile), -5402 for en kilde med 1939-profilens former.
\set ON_ERROR_STOP on
BEGIN;
\ir fixtures/relation-5b.sql
\ir fixtures/relation-2a.sql

-- Tabellens form: ukendt prædikat, ukendt form og ukendt tekstform afvises af tabellen selv.
DO $profil_tabel$
BEGIN
  BEGIN
    INSERT INTO private.relation_persona_profile(profile,source_id,predicate_forms,text_form)
      VALUES ('t6d3-x',-5409,'{"relation.marriage":"v9"}','folded');
    RAISE EXCEPTION 'PROFILE_TEST_FAILED: form v9 godtaget';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN
    INSERT INTO private.relation_persona_profile(profile,source_id,predicate_forms,text_form)
      VALUES ('t6d3-x',-5409,'{"relation.sibling":"v1"}','folded');
    RAISE EXCEPTION 'PROFILE_TEST_FAILED: prædikat relation.sibling godtaget';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN
    INSERT INTO private.relation_persona_profile(profile,source_id,predicate_forms,text_form)
      VALUES ('t6d3-x',-5409,'{}','folded');
    RAISE EXCEPTION 'PROFILE_TEST_FAILED: tom profil godtaget';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN
    INSERT INTO private.relation_persona_profile(profile,source_id,predicate_forms,text_form)
      VALUES ('t6d3-x',-5409,'{"relation.marriage":"v1"}','ocr');
    RAISE EXCEPTION 'PROFILE_TEST_FAILED: tekstform ocr godtaget';
  EXCEPTION WHEN check_violation THEN NULL; END;
  IF has_table_privilege('anon','private.relation_persona_profile','SELECT')
     OR has_table_privilege('authenticated','private.relation_persona_profile','SELECT')
     OR has_table_privilege('service_role','private.relation_persona_profile','SELECT')
     OR NOT (SELECT relrowsecurity FROM pg_class WHERE oid='private.relation_persona_profile'::regclass) THEN
    RAISE EXCEPTION 'PROFILE_TEST_FAILED: tabellen er ikke privat';
  END IF;
  RAISE NOTICE 'OK: profiltabellens form og adgang';
END $profil_tabel$;

-- Seeds: står en seed-række i basen, har den netop de aftalte former. At rækkerne findes, når kilden fandtes ved
-- migrationen, prøves i test-reimport-profile-seeds.sql og db-verify.sql (en kilde indsat efter schema.sql uden
-- migration får ingen seeds, som writer-profilernes seeds).
DO $profil_seeds$
DECLARE r record;
BEGIN
  FOR r IN SELECT * FROM (VALUES
      ('relation-persona-2018-20-v1',1::bigint,'{"relation.marriage":"v1","relation.child":"v1","relation.parent":"v1"}'::jsonb,'folded'),
      ('relation-persona-2018-20-v2',1::bigint,'{"relation.marriage":"v2"}'::jsonb,'folded'),
      ('relation-persona-2018-20-v3',1::bigint,'{"relation.marriage":"v3"}'::jsonb,'folded'),
      ('relation-persona-1939-v1',3::bigint,'{"relation.marriage":"v3","relation.parent":"v1"}'::jsonb,'raw')) v(profile,source_id,forms,text_form)
  LOOP
    IF EXISTS (SELECT 1 FROM private.relation_persona_profile pp WHERE pp.profile=r.profile AND pp.source_id=r.source_id
                  AND (pp.predicate_forms<>r.forms OR pp.text_form<>r.text_form)) THEN
      RAISE EXCEPTION 'PROFILE_TEST_FAILED: seed % for kilde %',r.profile,r.source_id;
    END IF;
  END LOOP;
  RAISE NOTICE 'OK: seeds (ingen drift)';
END $profil_seeds$;

DO $profil_writer$
DECLARE
  v_actor uuid:='11000000-0000-0000-0000-00000006d321';
  s1 jsonb; s3 jsonb; p jsonb; p3 jsonb; cm jsonb; cm3 jsonb; cc3 jsonb; cp3 jsonb; e jsonb; ep jsonb; ec jsonb; em jsonb;
  v_text text; v_raw text:='g. m. Bo Beta.'; v_text3 text; v_parent text:='Søn af Carl Ceta.'; v_child text:='Datter Dora.';
  v_ev jsonb;
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  INSERT INTO person(id,levende,privat,status) VALUES (-5401,false,false,'6d3'),(-5402,false,false,'6d3');
  -- Kilde -5401: en 2018-20-lignende kilde (f5b_profile registrerer v1/v2/v3).
  s1:=pg_temp.f5b_source(-5401);
  v_text:='Anna Alfa, f. 1800. '||v_raw;
  p:=pg_temp.f5b_post(-5401,s1,'I-1',v_text,ARRAY['Anna Alfa, f. 1800.',v_raw],-5401,v_actor);
  PERFORM pg_temp.f2a_event_for_state((p->>'principal')::uuid);
  cm:=pg_temp.f5b_claim(-5401,s1,'relation.marriage',(p->'clauses'->>1)::uuid,v_raw);
  PERFORM pg_temp.f5b_profile(-5401);
  e:=pg_temp.f5b_payload(p,cm,(p->'clauses'->>1)::uuid,v_raw,'Bo Beta');
  -- Kilde -5402: en 1939-lignende kilde med 1939-profilens former (ægteskab v3, forælder v1; tekstform raw).
  s3:=pg_temp.f5b_source(-5402);
  INSERT INTO private.relation_persona_profile(profile,source_id,predicate_forms,text_form)
    VALUES ('relation-persona-1939-v1',-5402,'{"relation.marriage":"v3","relation.parent":"v1"}','raw');
  v_text3:='Erik Eta, f. 1810. '||v_parent||' '||v_child||' '||v_raw;
  p3:=pg_temp.f5b_post(-5402,s3,'I-2',v_text3,ARRAY['Erik Eta, f. 1810.',v_parent,v_child,v_raw],-5402,v_actor);
  PERFORM pg_temp.f2a_event_for_state((p3->>'principal')::uuid);
  cp3:=pg_temp.f5b_claim(-5402,s3,'relation.parent',(p3->'clauses'->>1)::uuid,v_parent);
  cc3:=pg_temp.f5b_claim(-5402,s3,'relation.child',(p3->'clauses'->>2)::uuid,v_child);
  cm3:=pg_temp.f5b_claim(-5402,s3,'relation.marriage',(p3->'clauses'->>3)::uuid,v_raw);
  -- v1-payload for et ikke-ægteskab (intet navn, ingen år, intet nummer).
  ep:=jsonb_build_object('birth_raw',NULL,'clause_observation_id',(p3->'clauses'->>1)::uuid,'clause_set_seq',1,
    'clause_set_sha256',private.clause_set_sha256((p3->>'helpost')::uuid,1),'death_raw',NULL,
    'interpretation_key',cp3->>'key','interpretation_version',1,'marriage_ordinal',NULL,'name_from',NULL,'name_to',NULL,
    'post_offset',strpos(v_text3,v_parent)-1,'predicate','relation.parent','profile','relation-persona-1939-v1',
    'span_from',0,'span_to',char_length(v_parent));
  ec:=ep||jsonb_build_object('clause_observation_id',(p3->'clauses'->>2)::uuid,'interpretation_key',cc3->>'key',
    'post_offset',strpos(v_text3,v_child)-1,'predicate','relation.child','span_to',char_length(v_child));

  -- $profil_ukendt$: en profil uden række afvises.
  BEGIN
    PERFORM pg_temp.f5b_write(-5401,v_actor,jsonb_build_object('relation-persona:'||(cm->>'key'),
      e||'{"profile":"relation-persona-ukendt-v1"}'));
    RAISE EXCEPTION 'PROFILE_TEST_FAILED: ukendt profil godtaget';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM NOT LIKE '%RELATION_PERSONA_PROFILE_INVALID%' THEN RAISE; END IF;
  END;
  RAISE NOTICE 'OK: $profil_ukendt$';

  -- $profil_forkert_kilde$: 1939-profilen findes, men ikke for batchens kilde (-5401).
  BEGIN
    PERFORM pg_temp.f5b_write(-5401,v_actor,jsonb_build_object('relation-persona:'||(cm->>'key'),
      e||'{"profile":"relation-persona-1939-v1"}'));
    RAISE EXCEPTION 'PROFILE_TEST_FAILED: 1939-profil på anden kilde godtaget';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM NOT LIKE '%RELATION_PERSONA_PROFILE_INVALID%' THEN RAISE; END IF;
  END;
  RAISE NOTICE 'OK: $profil_forkert_kilde$';

  -- $praedikat_uden_form$: relation.child står ikke i 1939-profilen.
  BEGIN
    PERFORM pg_temp.f5b_write(-5402,v_actor,jsonb_build_object('relation-persona:'||(cc3->>'key'),ec));
    RAISE EXCEPTION 'PROFILE_TEST_FAILED: relation.child på 1939-profil godtaget';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM NOT LIKE '%RELATION_PERSONA_PROFILE_INVALID%' THEN RAISE; END IF;
  END;
  RAISE NOTICE 'OK: $praedikat_uden_form$';

  -- Formen, ikke navnet, styrer nøglesættet: et ægteskab under 1939-profilen er v3 og kræver arkets proveniens.
  em:=pg_temp.f5b_payload(p3,cm3,(p3->'clauses'->>3)::uuid,v_raw,'Bo Beta')||'{"profile":"relation-persona-1939-v1"}';
  BEGIN
    PERFORM pg_temp.f5b_write(-5402,v_actor,jsonb_build_object('relation-persona:'||(cm3->>'key'),em));
    RAISE EXCEPTION 'PROFILE_TEST_FAILED: v3-form uden proveniens godtaget';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM NOT LIKE '%REIMPORT_WRITER_RELATION_PERSONA_INVALID%' THEN RAISE; END IF;
  END;
  RAISE NOTICE 'OK: v3-formen kræver proveniens under 1939-profilen';

  -- $parent_v1_form_1939$: forælderen med v1's payloadform skrives under 1939-profilen.
  PERFORM pg_temp.f5b_write(-5402,v_actor,jsonb_build_object('relation-persona:'||(cp3->>'key'),ep));
  SELECT payload INTO v_ev FROM private.reimport_event WHERE element_id='relation-persona:'||(cp3->>'key');
  IF v_ev->>'profile' IS DISTINCT FROM 'relation-persona-1939-v1'
     OR NOT EXISTS (SELECT 1 FROM private.interpretation_party_current pc
                     WHERE pc.interpretation_key=(cp3->>'key')::uuid AND pc.party_role='principal'
                       AND pc.source_persona_id=(p3->>'principal')::uuid)
     OR EXISTS (SELECT 1 FROM private.interpretation_party_current pc
                 WHERE pc.interpretation_key=(cp3->>'key')::uuid AND pc.party_role='spouse') THEN
    RAISE EXCEPTION 'PROFILE_TEST_FAILED: forælder under 1939-profilen %',v_ev;
  END IF;
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  RAISE NOTICE 'OK: $parent_v1_form_1939$';

  -- 2018-20-profilen på sin egen kilde skrives som før (v1-formen, ordret spænd).
  PERFORM pg_temp.f5b_write(-5401,v_actor,jsonb_build_object('relation-persona:'||(cm->>'key'),e));
  IF NOT EXISTS (SELECT 1 FROM private.interpretation_party_current pc
                  WHERE pc.interpretation_key=(cm->>'key')::uuid AND pc.party_role='spouse') THEN
    RAISE EXCEPTION 'PROFILE_TEST_FAILED: 2018-20-v1 på egen kilde';
  END IF;
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  RAISE NOTICE 'OK: 2018-20-v1 uændret på egen kilde';
END $profil_writer$;

-- Writeren bærer ingen profilnavne; den slår op i tabellen.
DO $profil_krop$
DECLARE v_def text:=pg_get_functiondef('private.write_relation_persona(uuid,text,jsonb)'::regprocedure);
BEGIN
  IF position('relation_persona_profile' IN v_def)=0 OR position('RELATION_PERSONA_PROFILE_INVALID' IN v_def)=0
     OR v_def ~ 'relation-persona-(2018-20|1939)' OR v_def ~ '''(1939|2018-20)''' THEN
    RAISE EXCEPTION 'PROFILE_TEST_FAILED: writerens krop';
  END IF;
  RAISE NOTICE 'OK: writeren slår profilen op';
END $profil_krop$;
ROLLBACK;
