-- Trin 5b 2b-ii runde 2 (#151, spec §17.5/§17.7): relation_person_create afviser titelord, afløst klausul og afløst fortolkning.
\set ON_ERROR_STOP on
BEGIN;
\ir fixtures/relation-5b.sql
\ir fixtures/relation-2a.sql
CREATE OR REPLACE FUNCTION pg_temp.f2bii_npn(p_actor uuid,p_sp uuid,p_years int[]) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub',p_actor::text,true);
  SET LOCAL ROLE authenticated;
  PERFORM red_afgoer_source_persona(p_sp,0,'new_person_needed',NULL,'test',
    jsonb_build_object('basis','human_sheet','sheet_sha256',repeat('a',64),'rows_sha256',repeat('a',64),'line',1)
    || CASE WHEN p_years IS NULL THEN '{}'::jsonb ELSE jsonb_build_object('deceased',jsonb_build_object(
         'rule','aarstal-120-v1','cutoff_year',1906,'clause_years',to_jsonb(p_years))) END);
  RESET ROLE;
END $$;
CREATE OR REPLACE FUNCTION pg_temp.f2bii_run(p_source bigint,p_actor uuid,p_manifest jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE b jsonb; r jsonb; prof jsonb;
BEGIN
  SELECT jsonb_build_object('profile_id',profile_id,'profile_sha256',profile_sha256) INTO prof
    FROM private.reimport_writer_profile WHERE source_id=p_source AND profile_id='relation-5b';
  IF prof IS NULL THEN prof:=pg_temp.f5b_profile(p_source); END IF;
  b:=pg_temp.f5b_batch(p_source,p_actor,prof,p_manifest->'authorized_elements',p_manifest->'expected_counts');
  SET LOCAL ROLE authenticated;
  PERFORM red_apply_reimport_relation_person_create((b->>'batch')::uuid,e.key,e.value) FROM jsonb_each(p_manifest->'authorized_elements') e;
  PERFORM red_finalize_reimport((b->>'batch')::uuid);
  r:=red_reimport_batch_result((b->>'auth')::uuid,(b->>'batch')::uuid);
  RESET ROLE;
  RETURN r;
END $$;
CREATE OR REPLACE FUNCTION pg_temp.f2bii_counts() RETURNS jsonb LANGUAGE sql AS $$
  SELECT jsonb_build_object('person',(SELECT count(*) FROM person),'family',(SELECT count(*) FROM family),
    'fm',(SELECT count(*) FROM family_member),'fact',(SELECT count(*) FROM fact),'assertion',(SELECT count(*) FROM assertion),
    'citation',(SELECT count(*) FROM citation),'conclusion',(SELECT count(*) FROM conclusion))
$$;
CREATE OR REPLACE FUNCTION pg_temp.f2bii_delta(a jsonb,b jsonb) RETURNS jsonb LANGUAGE sql AS $$
  SELECT jsonb_object_agg(k,(b->>k)::int-(a->>k)::int) FROM jsonb_object_keys(b) k
$$;

-- titelord i navnet ⇒ afvist, 0 delta
DO $v3_title_reject$
DECLARE v_actor uuid:='11000000-0000-0000-0000-00000005b3b1'; s jsonb; p jsonb; c jsonb; sp uuid; m jsonb; n0 jsonb;
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  INSERT INTO person(id,levende,privat,status) VALUES (-5351,false,false,'5b');
  s:=pg_temp.f5b_source(-5351);
  p:=pg_temp.f5b_post(-5351,s,'II-51','Anna Alfa. Gift 1890 med Ida komtesse Dal.',ARRAY['Anna Alfa.','Gift 1890 med Ida komtesse Dal.'],-5351,v_actor);
  PERFORM pg_temp.f2a_event_for_state((p->>'principal')::uuid);
  c:=pg_temp.f5b_claim(-5351,s,'relation.marriage',(p->'clauses'->>1)::uuid,'Gift 1890 med Ida komtesse Dal.');
  sp:=pg_temp.f5b_spouse(-5351,s,p,c,(p->'clauses'->>1)::uuid,'Ida komtesse Dal',1);
  PERFORM pg_temp.f2bii_npn(v_actor,sp,ARRAY[1890]);
  m:=private.relation_person_create_input(-5351);
  n0:=pg_temp.f2bii_counts();
  BEGIN
    PERFORM pg_temp.f2bii_run(-5351,v_actor,m);
    RAISE EXCEPTION 'RPC3_TEST_FAILED: titel godtaget';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM NOT LIKE '%RELATION_PERSON_CREATE_NAME_TITLE%' THEN RAISE; END IF; END;
  IF pg_temp.f2bii_delta(n0,pg_temp.f2bii_counts())<>'{"person":0,"family":0,"fm":0,"fact":0,"assertion":0,"citation":0,"conclusion":0}'::jsonb THEN
    RAISE EXCEPTION 'RPC3_TEST_FAILED: delta ved titel';
  END IF;
  RAISE NOTICE 'OK: titelord afvist';
END $v3_title_reject$;

-- afløst klausul ⇒ afvist
DO $v3_clause_stale$
DECLARE v_actor uuid:='11000000-0000-0000-0000-00000005b3b1'; s jsonb; p jsonb; c jsonb; sp uuid; m jsonb; v_clause uuid;
BEGIN
  INSERT INTO person(id,levende,privat,status) VALUES (-5352,false,false,'5b');
  s:=pg_temp.f5b_source(-5352);
  p:=pg_temp.f5b_post(-5352,s,'II-52','Anna Alfa. Gift 1890 med Bo Beta.',ARRAY['Anna Alfa.','Gift 1890 med Bo Beta.'],-5352,v_actor);
  PERFORM pg_temp.f2a_event_for_state((p->>'principal')::uuid);
  v_clause:=(p->'clauses'->>1)::uuid;
  c:=pg_temp.f5b_claim(-5352,s,'relation.marriage',v_clause,'Gift 1890 med Bo Beta.');
  sp:=pg_temp.f5b_spouse(-5352,s,p,c,v_clause,'Bo Beta',1);
  PERFORM pg_temp.f2bii_npn(v_actor,sp,ARRAY[1890]);
  m:=private.relation_person_create_input(-5352);
  -- et nyere klausulsæt for samme post gør klausulen ikke-aktuel
  INSERT INTO private.source_observation(occurrence_id,observation_kind,page_from,page_to,char_from,char_to,verbatim_text,
      quality_status,extraction_method,extraction_run_id,parent_observation_id,post_char_from,post_char_to,clause_ordinal,
      clause_classification,clause_flags,clause_set_seq)
    SELECT occurrence_id,observation_kind,page_from,page_to,char_from,char_to,verbatim_text,quality_status,extraction_method,
           extraction_run_id,parent_observation_id,post_char_from,post_char_to,clause_ordinal,clause_classification,clause_flags,2
      FROM private.source_observation WHERE parent_observation_id=(SELECT parent_observation_id FROM private.source_observation WHERE id=v_clause)
       AND observation_kind='clause';
  BEGIN
    PERFORM pg_temp.f2bii_run(-5352,v_actor,m);
    RAISE EXCEPTION 'RPC3_TEST_FAILED: afløst klausul godtaget';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM NOT LIKE '%RELATION_PERSON_CREATE_CLAUSE_STALE%' THEN RAISE; END IF; END;
  RAISE NOTICE 'OK: afløst klausul afvist';
END $v3_clause_stale$;

-- afløst fortolkning ⇒ afvist
DO $v3_interp_stale$
DECLARE v_actor uuid:='11000000-0000-0000-0000-00000005b3b1'; s jsonb; p jsonb; c jsonb; sp uuid; m jsonb; v_cur private.interpretation%ROWTYPE;
BEGIN
  INSERT INTO person(id,levende,privat,status) VALUES (-5353,false,false,'5b');
  s:=pg_temp.f5b_source(-5353);
  p:=pg_temp.f5b_post(-5353,s,'II-53','Anna Alfa. Gift 1890 med Bo Beta.',ARRAY['Anna Alfa.','Gift 1890 med Bo Beta.'],-5353,v_actor);
  PERFORM pg_temp.f2a_event_for_state((p->>'principal')::uuid);
  c:=pg_temp.f5b_claim(-5353,s,'relation.marriage',(p->'clauses'->>1)::uuid,'Gift 1890 med Bo Beta.');
  sp:=pg_temp.f5b_spouse(-5353,s,p,c,(p->'clauses'->>1)::uuid,'Bo Beta',1);
  PERFORM pg_temp.f2bii_npn(v_actor,sp,ARRAY[1890]);
  m:=private.relation_person_create_input(-5353);
  SELECT * INTO v_cur FROM private.interpretation_current WHERE interpretation_key=(c->>'key')::uuid;
  INSERT INTO private.interpretation(id,interpretation_key,version,source_id,source_persona_id,interpretation_kind,predicate,
      value,schema_version,derivation_kind,confidence,status,method,extraction_run_id,supersedes_id,
      decided_by,decided_by_name,decided_at,decision_evidence)
    VALUES (gen_random_uuid(),v_cur.interpretation_key,v_cur.version+1,v_cur.source_id,v_cur.source_persona_id,
      v_cur.interpretation_kind,v_cur.predicate,v_cur.value,v_cur.schema_version,v_cur.derivation_kind,v_cur.confidence,
      'superseded',v_cur.method,v_cur.extraction_run_id,v_cur.id,v_actor,'fixture',clock_timestamp(),'{"fixture":"v3"}');
  BEGIN
    PERFORM pg_temp.f2bii_run(-5353,v_actor,m);
    RAISE EXCEPTION 'RPC3_TEST_FAILED: afløst fortolkning godtaget';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM NOT LIKE '%RELATION_PERSON_CREATE_INTERPRETATION_STALE%' THEN RAISE; END IF; END;
  RAISE NOTICE 'OK: afløst fortolkning afvist';
END $v3_interp_stale$;
ROLLBACK;
