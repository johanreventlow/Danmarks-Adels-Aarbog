-- Trin 5b 2b-ii (#151, spec §6): relation_person_create — kun afdød-erklærede nye ægtefæller.
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
         'rule','vielsesaar-120-v1','cutoff_year',1921,'clause_years',to_jsonb(p_years))) END);
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

-- new + negativtest F
DO $rpc_new$
DECLARE v_actor uuid:='11000000-0000-0000-0000-00000005b2b3'; s jsonb; p jsonb; c jsonb; sp uuid; sp2 uuid; m jsonb; r jsonb;
  v_person bigint; n0 jsonb;
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  INSERT INTO person(id,levende,privat,status) VALUES (-5231,false,false,'5b');
  s:=pg_temp.f5b_source(-5231);
  p:=pg_temp.f5b_post(-5231,s,'II-31','Anna Alfa. Gift 1890 med Bo Beta. Gift 1950 med Cia Ceta.',
       ARRAY['Anna Alfa.','Gift 1890 med Bo Beta.','Gift 1950 med Cia Ceta.'],-5231,v_actor);
  PERFORM pg_temp.f2a_event_for_state((p->>'principal')::uuid);
  c:=pg_temp.f5b_claim(-5231,s,'relation.marriage',(p->'clauses'->>1)::uuid,'Gift 1890 med Bo Beta.');
  sp:=pg_temp.f5b_spouse(-5231,s,p,c,(p->'clauses'->>1)::uuid,'Bo Beta',1);
  PERFORM pg_temp.f2bii_npn(v_actor,sp,ARRAY[1890]);
  c:=pg_temp.f5b_claim(-5231,s,'relation.marriage',(p->'clauses'->>2)::uuid,'Gift 1950 med Cia Ceta.');
  sp2:=pg_temp.f5b_spouse(-5231,s,p,c,(p->'clauses'->>2)::uuid,'Cia Ceta',2);
  PERFORM pg_temp.f2bii_npn(v_actor,sp2,NULL);                    -- negativtest F: ingen deceased

  m:=private.relation_person_create_input(-5231);
  IF (m->'expected_counts'->>'relation_person_creates')::int<>1 THEN
    RAISE EXCEPTION 'RPC_TEST_FAILED: populationen skal kun rumme D (fik %)',m->'expected_counts';
  END IF;
  IF (m->'authorized_elements'->('relation-person-create:'||sp)->>'family_mode')<>'new' THEN
    RAISE EXCEPTION 'RPC_TEST_FAILED: hovedpersonen uden familie skal give new';
  END IF;
  n0:=pg_temp.f2bii_counts();
  r:=pg_temp.f2bii_run(-5231,v_actor,m);
  IF pg_temp.f2bii_delta(n0,pg_temp.f2bii_counts())
     <> '{"person":1,"family":1,"fm":2,"fact":1,"assertion":1,"citation":1,"conclusion":1}'::jsonb THEN
    RAISE EXCEPTION 'RPC_TEST_FAILED: delta %',pg_temp.f2bii_delta(n0,pg_temp.f2bii_counts());
  END IF;
  IF r#>'{relation_results,0,derived_counts}'<>'{"persons":1,"new_families":1,"family_members":2}'::jsonb THEN
    RAISE EXCEPTION 'RPC_TEST_FAILED: derived_counts %',r->'relation_results';
  END IF;
  SELECT canonical_person_id INTO v_person FROM private.source_persona_identity
   WHERE source_persona_id=sp AND decision_status='accepted';
  IF v_person IS NULL OR (SELECT staged AND NOT levende AND NOT privat AND visning_navn='Bo Beta' FROM person WHERE id=v_person) IS NOT TRUE THEN
    RAISE EXCEPTION 'RPC_TEST_FAILED: person (staged, ikke levende, ikke privat, afledt navn)';
  END IF;
  IF (SELECT evidence ? 'deceased' AND evidence->>'method'='relation-person-create-v1'
        FROM private.source_persona_identity WHERE source_persona_id=sp) IS NOT TRUE THEN
    RAISE EXCEPTION 'RPC_TEST_FAILED: deceased og metode i identitetsevidensen';
  END IF;
  -- negativtest F: et håndbygget element for kø-personen uden deceased afvises af writeren
  BEGIN
    PERFORM pg_temp.f2bii_run(-5231,v_actor,jsonb_build_object(
      'expected_counts',jsonb_build_object('person_creates',0,'source_evidence',0,'relation_person_creates',1),
      'authorized_elements',jsonb_build_object('relation-person-create:'||sp2,jsonb_build_object(
        'citation_label','II-31, s. 10','family_id',NULL,'family_mode','new','identity_version',1,'marriage_ordinal',2,
        'name_text','Cia Ceta','principal_person_id',-5231,'source_persona_id',sp2::text))));
    RAISE EXCEPTION 'RPC_TEST_FAILED: F godtaget';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM NOT LIKE '%RELATION_PERSON_CREATE_NOT_DECEASED%' THEN RAISE; END IF;
  END;
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;   -- udskudte identitetstjek må ikke skjules af ROLLBACK
  RAISE NOTICE 'OK: relation_person_create new, delta, staged/afdød, F afvist';
END $rpc_new$;

-- existing: hovedpersonens eneste familie har kun hovedpersonen som partner
DO $rpc_existing$
DECLARE v_actor uuid:='11000000-0000-0000-0000-00000005b2b3'; s jsonb; p jsonb; c jsonb; sp uuid; m jsonb; v_fam bigint; n0 jsonb;
BEGIN
  INSERT INTO person(id,levende,privat,status) VALUES (-5232,false,false,'5b');
  s:=pg_temp.f5b_source(-5232);
  p:=pg_temp.f5b_post(-5232,s,'II-32','Anna Alfa. Gift 1890 med Bo Beta.',ARRAY['Anna Alfa.','Gift 1890 med Bo Beta.'],-5232,v_actor);
  PERFORM pg_temp.f2a_event_for_state((p->>'principal')::uuid);
  c:=pg_temp.f5b_claim(-5232,s,'relation.marriage',(p->'clauses'->>1)::uuid,'Gift 1890 med Bo Beta.');
  sp:=pg_temp.f5b_spouse(-5232,s,p,c,(p->'clauses'->>1)::uuid,'Bo Beta',1);
  v_fam:=pg_temp.f5b_family(-5232,NULL,NULL);
  PERFORM pg_temp.f2bii_npn(v_actor,sp,ARRAY[1890]);
  m:=private.relation_person_create_input(-5232);
  IF (m->'authorized_elements'->('relation-person-create:'||sp)->>'family_mode')<>'existing'
     OR (m->'authorized_elements'->('relation-person-create:'||sp)->>'family_id')::bigint<>v_fam THEN
    RAISE EXCEPTION 'RPC_TEST_FAILED: existing forventet';
  END IF;
  n0:=pg_temp.f2bii_counts();
  PERFORM pg_temp.f2bii_run(-5232,v_actor,m);
  IF pg_temp.f2bii_delta(n0,pg_temp.f2bii_counts())
     <> '{"person":1,"family":0,"fm":1,"fact":1,"assertion":1,"citation":1,"conclusion":1}'::jsonb THEN
    RAISE EXCEPTION 'RPC_TEST_FAILED: existing-delta';
  END IF;
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;   -- udskudte identitetstjek må ikke skjules af ROLLBACK
  RAISE NOTICE 'OK: relation_person_create existing';
END $rpc_existing$;

-- Review Focus 4: familieplaceringen drifter mellem manifest og skrivning
DO $rpc_family_drift$
DECLARE v_actor uuid:='11000000-0000-0000-0000-00000005b2b3'; s jsonb; p jsonb; c jsonb; sp uuid; m jsonb;
BEGIN
  INSERT INTO person(id,levende,privat,status) VALUES (-5233,false,false,'5b');
  s:=pg_temp.f5b_source(-5233);
  p:=pg_temp.f5b_post(-5233,s,'II-33','Anna Alfa. Gift 1890 med Bo Beta.',ARRAY['Anna Alfa.','Gift 1890 med Bo Beta.'],-5233,v_actor);
  PERFORM pg_temp.f2a_event_for_state((p->>'principal')::uuid);
  c:=pg_temp.f5b_claim(-5233,s,'relation.marriage',(p->'clauses'->>1)::uuid,'Gift 1890 med Bo Beta.');
  sp:=pg_temp.f5b_spouse(-5233,s,p,c,(p->'clauses'->>1)::uuid,'Bo Beta',1);
  PERFORM pg_temp.f2bii_npn(v_actor,sp,ARRAY[1890]);
  m:=private.relation_person_create_input(-5233);
  PERFORM pg_temp.f5b_family(-5233,NULL,NULL);                     -- en union oprettes i mellemtiden
  BEGIN
    PERFORM pg_temp.f2bii_run(-5233,v_actor,m);
    RAISE EXCEPTION 'RPC_TEST_FAILED: familiedrift godtaget';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM NOT LIKE '%RELATION_PERSON_CREATE_FAMILY_DRIFT%' THEN RAISE; END IF;
  END;
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;   -- udskudte identitetstjek må ikke skjules af ROLLBACK
  RAISE NOTICE 'OK: relation_person_create familiedrift afvist';
END $rpc_family_drift$;

-- Review Focus 3: klausulens årstal passer ikke til afgørelsens
DO $rpc_years_drift$
DECLARE v_actor uuid:='11000000-0000-0000-0000-00000005b2b3'; s jsonb; p jsonb; c jsonb; sp uuid; m jsonb;
BEGIN
  INSERT INTO person(id,levende,privat,status) VALUES (-5234,false,false,'5b');
  s:=pg_temp.f5b_source(-5234);
  p:=pg_temp.f5b_post(-5234,s,'II-34','Anna Alfa. Gift 1890 med Bo Beta.',ARRAY['Anna Alfa.','Gift 1890 med Bo Beta.'],-5234,v_actor);
  PERFORM pg_temp.f2a_event_for_state((p->>'principal')::uuid);
  c:=pg_temp.f5b_claim(-5234,s,'relation.marriage',(p->'clauses'->>1)::uuid,'Gift 1890 med Bo Beta.');
  sp:=pg_temp.f5b_spouse(-5234,s,p,c,(p->'clauses'->>1)::uuid,'Bo Beta',1);
  PERFORM pg_temp.f2bii_npn(v_actor,sp,ARRAY[1889]);
  m:=private.relation_person_create_input(-5234);
  BEGIN
    PERFORM pg_temp.f2bii_run(-5234,v_actor,m);
    RAISE EXCEPTION 'RPC_TEST_FAILED: årsdrift godtaget';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM NOT LIKE '%RELATION_PERSON_CREATE_YEARS_DRIFT%' THEN RAISE; END IF;
  END;
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;   -- udskudte identitetstjek må ikke skjules af ROLLBACK
  RAISE NOTICE 'OK: relation_person_create årsdrift afvist';
END $rpc_years_drift$;
ROLLBACK;
