-- Trin 5a, Task 4: kandidater, kollisioner og kø-filter.
DO $identity_detail$
DECLARE
  v_actor uuid := '11000000-0000-0000-0000-000000005a04';
  v_run uuid := '22000000-0000-0000-0000-000000005a04';
  v_obs uuid := '66000000-0000-0000-0000-000000005a04';
  v_p1 uuid := '88000000-0000-0000-0000-000000005a41';
  v_p2 uuid := '88000000-0000-0000-0000-000000005a42';
  v_old uuid; v_new uuid; v_detail jsonb; v_n int; v_tier text;
BEGIN
  BEGIN
    INSERT INTO auth.users(id,email) VALUES (v_actor,'5a-detail@test.invalid');
    INSERT INTO profiles(id,rolle,navn,email) VALUES (v_actor,'redaktion','5a detail','5a-detail@test.invalid');
    INSERT INTO person(id,levende,privat,status) VALUES (-987655041,false,false,'5a');
    INSERT INTO source(id,titel,import_key) VALUES (-987655041,'5a E','verify:5a:e');
    INSERT INTO private.extraction_run(id,source_id,run_key,schema_version,extractor_version,profile_version,input_sha256,manifest)
      VALUES (v_run,-987655041,'5a-run-e','1.0','verify','verify',repeat('9',64),'{}');
    INSERT INTO private.source_rendition(id,source_id,rendition_key,rendition_kind,content_sha256,metadata)
      VALUES ('33000000-0000-0000-0000-000000005a04',-987655041,'5a-rend-e','text_layer',repeat('8',64),'{}');
    INSERT INTO private.source_record_occurrence(id,rendition_id,occurrence_key,page_from,page_to,char_from,char_to,
      verbatim_text,physical_fingerprint,structural_fingerprint,extraction_run_id)
      VALUES ('55000000-0000-0000-0000-000000005a04','33000000-0000-0000-0000-000000005a04','5a-occ-e',1,1,0,9,'Anna Test','p5ae','s5ae',v_run);
    INSERT INTO private.source_observation(id,occurrence_id,observation_kind,page_from,page_to,char_from,char_to,
      verbatim_text,quality_status,extraction_method,extraction_run_id)
      VALUES (v_obs,'55000000-0000-0000-0000-000000005a04','name_clause',1,1,0,9,'Anna Test','clear','verify',v_run);
    INSERT INTO private.source_persona(id,source_id,persona_key,created_run_id) VALUES (v_p1,-987655041,'5a-e1',v_run),(v_p2,-987655041,'5a-e2',v_run);
    INSERT INTO private.source_mention(id,observation_id,mention_kind,char_from,char_to,verbatim_text,created_run_id)
      VALUES ('70000000-0000-0000-0000-000000005a41',v_obs,'person',0,9,'Anna Test',v_run),
             ('70000000-0000-0000-0000-000000005a42',v_obs,'person',0,9,'Anna Test',v_run);
    INSERT INTO private.source_persona_mention(persona_id,mention_id,mention_role,ordinal)
      VALUES (v_p1,'70000000-0000-0000-0000-000000005a41','principal',1),(v_p2,'70000000-0000-0000-0000-000000005a42','principal',1);
    -- to kørsler: den gamle skal ignoreres
    -- tredje persona, accepteret til en person, der KUN er kandidat i den gamle kørsel
    INSERT INTO person(id,levende,privat,status) VALUES (-987655042,false,false,'5a');
    INSERT INTO private.source_persona(id,source_id,persona_key,created_run_id) VALUES ('88000000-0000-0000-0000-000000005a43',-987655041,'5a-e3',v_run);
    INSERT INTO private.source_mention(id,observation_id,mention_kind,char_from,char_to,verbatim_text,created_run_id)
      VALUES ('70000000-0000-0000-0000-000000005a43',v_obs,'person',0,9,'Anna Test',v_run);
    INSERT INTO private.source_persona_mention(persona_id,mention_id,mention_role,ordinal)
      VALUES ('88000000-0000-0000-0000-000000005a43','70000000-0000-0000-0000-000000005a43','principal',1);
    -- to kørsler (gældende = højeste run_seq = den sidst indsatte): den gamle skal ignoreres
    INSERT INTO private.source_persona_identity_candidate_run(source_id,generator_version,config,config_sha256,input_spec,input_sha256,candidates_sha256,persona_count,candidate_count,created_by,created_by_name)
      VALUES (-987655041,'t','{}',repeat('a',64),'{"mode":"undecided"}',repeat('1',64),repeat('c',64),1,2,v_actor,'t') RETURNING id INTO v_old;
    INSERT INTO private.source_persona_identity_candidate(run_id,source_persona_id,candidate_person_id,rank,score,tier,basis)
      VALUES (v_old,v_p1,-987655041,1,0.5,'none','{"signals":["name"]}'),(v_old,v_p1,-987655042,2,0.4,'none','{"signals":["name"]}');
    INSERT INTO private.source_persona_identity_candidate_run(source_id,generator_version,config,config_sha256,input_spec,input_sha256,candidates_sha256,persona_count,candidate_count,created_by,created_by_name)
      VALUES (-987655041,'t','{}',repeat('a',64),'{"mode":"undecided"}',repeat('2',64),repeat('c',64),1,1,v_actor,'t') RETURNING id INTO v_new;
    INSERT INTO private.source_persona_identity_candidate(run_id,source_persona_id,candidate_person_id,rank,score,tier,basis)
      VALUES (v_new,v_p1,-987655041,1,0.95,'auto','{"signals":["name","birth"]}');

    PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
    SET LOCAL ROLE authenticated;
    -- persona 2 er allerede accepteret til kandidatpersonen → kollision for persona 1
    PERFORM red_afgoer_source_persona(v_p2,0,'same',-987655041,'samme','{}');
    PERFORM red_afgoer_source_persona('88000000-0000-0000-0000-000000005a43',0,'same',-987655042,'gammel kandidat','{}');
    v_detail := red_source_persona_detail(v_p1);
    IF jsonb_typeof(v_detail->'candidates') IS DISTINCT FROM 'array' OR jsonb_typeof(v_detail->'collisions') IS DISTINCT FROM 'array' THEN
      RAISE EXCEPTION 'IDENTITY_DETAIL_TEST_FAILED: candidates/collisions mangler (%)',v_detail;
    END IF;
    IF jsonb_array_length(v_detail->'candidates') IS DISTINCT FROM 1 OR (v_detail->'candidates'->0->>'run_id')<>v_new::text
       OR (v_detail->'candidates'->0->>'tier')<>'auto' OR NOT (v_detail->'candidates'->0 ? 'person_name')
       OR (v_detail->'candidates'->0->>'person_id')::bigint<>-987655041 THEN
      RAISE EXCEPTION 'IDENTITY_DETAIL_TEST_FAILED: kandidater fra forkert kørsel (%)',v_detail->'candidates';
    END IF;
    -- kun kollisionen fra den gældende kørsel (5a-e2); 5a-e3's person er kun kandidat i den gamle
    IF jsonb_array_length(v_detail->'collisions') IS DISTINCT FROM 1 OR (v_detail->'collisions'->0->>'persona_key')<>'5a-e2' THEN
      RAISE EXCEPTION 'IDENTITY_DETAIL_TEST_FAILED: forkerte kollisioner (%)',v_detail->'collisions';
    END IF;
    SELECT best_tier INTO v_tier FROM red_source_persona_queue('proposed',-987655041,NULL,50) WHERE source_persona_id=v_p1;
    IF v_tier IS DISTINCT FROM 'auto' THEN RAISE EXCEPTION 'IDENTITY_DETAIL_TEST_FAILED: best_tier %',v_tier; END IF;
    PERFORM red_afgoer_source_persona(v_p1,0,'new_person_needed',NULL,'ny','{}');
    SELECT count(*) INTO v_n FROM red_source_persona_queue('new_person_needed',-987655041,NULL,50);
    IF v_n<>1 THEN RAISE EXCEPTION 'IDENTITY_DETAIL_TEST_FAILED: new_person_needed-filter gav %',v_n; END IF;
    RESET ROLE;
    RAISE EXCEPTION 'ROLLBACK_5A_DETAIL';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM='ROLLBACK_5A_DETAIL' THEN RAISE NOTICE 'OK: detalje viser seneste kørsels kandidater og kollisioner; kø har best_tier og ny-person-filter';
    ELSE RAISE; END IF;
  END;
END $identity_detail$;

-- Trin 5b, Task 9: rollefilter, familiekontekst og kandidaternes titler/familie.
BEGIN;
\ir fixtures/relation-5b.sql
DO $identity_detail_5b$
DECLARE v_actor uuid:='11000000-0000-0000-0000-00000005b901'; s jsonb; p jsonb; c jsonb; v_sp uuid; v_in jsonb; v_run uuid; d jsonb; q record;
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  INSERT INTO person(id,levende,privat,status,visning_navn) VALUES (-5901,false,false,'5b','Hoved'),(-5902,false,false,'5b','Mage');
  INSERT INTO fact(id,subjekt_type,subjekt_id,faktatype) VALUES (-5902,'person',-5902,'titel');
  INSERT INTO assertion(id,target_type,target_id,vaerdi_tekst) VALUES (-5902,'fact',-5902,'kammerherre');
  INSERT INTO conclusion(target_type,target_id,valgt_assertion_id) VALUES ('fact',-5902,-5902);
  s:=pg_temp.f5b_source(-5901);
  p:=pg_temp.f5b_post(-5901,s,'IX-1','Hoved. g. m. Mage.',ARRAY['Hoved.','g. m. Mage.'],-5901,v_actor);
  c:=pg_temp.f5b_claim(-5901,s,'relation.marriage',(p->'clauses'->>1)::uuid,'g. m. Mage.');
  v_sp:=pg_temp.f5b_spouse(-5901,s,p,c,(p->'clauses'->>1)::uuid,'Mage',1);
  PERFORM pg_temp.f5b_family(-5901,-5902,1);
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  SET LOCAL ROLE authenticated;
  v_in:=red_identity_candidate_input(-5901,'{"mode":"undecided"}');
  v_run:=red_record_identity_candidates(jsonb_build_object('source_id',-5901,'generator_version','t','config','{}'::jsonb,
    'input_spec','{"mode":"undecided"}'::jsonb,'input_sha256',v_in->>'input_sha256'),
    jsonb_build_array(jsonb_build_object('source_persona_id',v_sp,'candidate_person_id',-5902,'rank',1,'score',0.9,'tier','review',
      'basis','{"signals":["name","family_partner"]}'::jsonb)));
  d:=red_source_persona_detail(v_sp);
  SELECT * INTO q FROM red_source_persona_queue(NULL,-5901,NULL,50,'spouse');
  RESET ROLE;
  IF d->'family_context'->>'principal_record_key'<>'IX-1' OR (d->'family_context'->>'marriage_ordinal')::int<>1
     OR d->'candidates'->0->'titles'<>'["kammerherre"]'::jsonb OR (d->'candidates'->0->>'family_id') IS NULL
     OR q.mention_role<>'spouse' OR q.source_persona_id<>v_sp THEN
    RAISE EXCEPTION 'IDENTITY_DETAIL_TEST_FAILED: 5b-felter %',d->'family_context';
  END IF;
  RAISE NOTICE 'OK: rollefilter, familiekontekst og kandidaternes titler/familie';
END $identity_detail_5b$;
ROLLBACK;
