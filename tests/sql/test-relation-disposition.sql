-- Trin 5b 2b-ii (#151, spec §8): relation_disposition — afventer_identitet → fortolkning_foreslaaet pr. aktør.
\set ON_ERROR_STOP on
BEGIN;
-- Aktørernes identitetsrækker skal være låst FOR SHARE af writeren (review 2026-10-18, Important 2).
CREATE EXTENSION IF NOT EXISTS pgrowlocks;
\ir fixtures/relation-5b.sql
\ir fixtures/relation-2a.sql
-- maskinel disposition v1 = afventer_identitet på en klausul
CREATE OR REPLACE FUNCTION pg_temp.f2bii_await(p_clause uuid) RETURNS void LANGUAGE sql AS $$
  INSERT INTO private.clause_disposition(observation_id,version,disposition,decided_by_kind,evidence)
  VALUES (p_clause,1,'afventer_identitet','machine',jsonb_build_object('batch_id',gen_random_uuid(),'manifest_sha256',repeat('d',64)));
$$;
-- ægtefællens identitet sat direkte som ejer (state + event)
CREATE OR REPLACE FUNCTION pg_temp.f2bii_ident(p_persona uuid,p_status text,p_person bigint,p_actor uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO private.source_persona_identity(source_persona_id,canonical_person_id,decision_status,version,evidence,
    decided_by,decided_by_name,decided_at)
    VALUES (p_persona,p_person,p_status,1,'{"fixture":"2bii"}',p_actor,'fixture',clock_timestamp());
  PERFORM pg_temp.f2a_event_for_state(p_persona);
END $$;
-- et aktørforslag om en anden end hovedpersonen: ingen persona (som ingestens persona_role='other')
CREATE OR REPLACE FUNCTION pg_temp.f2bii_other(p_source bigint,p_src jsonb,p_clause uuid) RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_id uuid:=gen_random_uuid();
BEGIN
  INSERT INTO private.interpretation(id,interpretation_key,version,source_id,source_persona_id,interpretation_kind,predicate,
    value,schema_version,derivation_kind,confidence,status,method,extraction_run_id)
    VALUES (v_id,gen_random_uuid(),1,p_source,NULL,'property','person.birth',to_jsonb('1850'::text),
      'fixture','model_inference',0.9,'proposed','fixture',(p_src->>'run')::uuid);
  INSERT INTO private.interpretation_observation(interpretation_id,observation_id,evidence_role,ordinal) VALUES (v_id,p_clause,'supporting',1);
END $$;
CREATE OR REPLACE FUNCTION pg_temp.f2bii_disp(p_source bigint,p_actor uuid,p_manifest jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE b jsonb; r jsonb; prof jsonb;
BEGIN
  SELECT jsonb_build_object('profile_id',profile_id,'profile_sha256',profile_sha256) INTO prof
    FROM private.reimport_writer_profile WHERE source_id=p_source AND profile_id='relation-5b';
  IF prof IS NULL THEN prof:=pg_temp.f5b_profile(p_source); END IF;
  b:=pg_temp.f5b_batch(p_source,p_actor,prof,p_manifest->'authorized_elements',p_manifest->'expected_counts');
  SET LOCAL ROLE authenticated;
  PERFORM red_apply_reimport_relation_disposition((b->>'batch')::uuid,e.key,e.value) FROM jsonb_each(p_manifest->'authorized_elements') e;
  PERFORM red_finalize_reimport((b->>'batch')::uuid);
  r:=red_reimport_batch_result((b->>'auth')::uuid,(b->>'batch')::uuid);
  RESET ROLE;
  RETURN r;
END $$;

DO $disposition$
DECLARE v_actor uuid:='11000000-0000-0000-0000-00000005b2b6'; s jsonb; p jsonb; c jsonb; k uuid[]; sp uuid; sp1 uuid; m jsonb; r jsonb;
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  INSERT INTO person(id,levende,privat,status) VALUES (-5261,false,false,'5b'),(-52611,false,false,'5b');
  s:=pg_temp.f5b_source(-5261);
  p:=pg_temp.f5b_post(-5261,s,'II-61','Anna Alfa. Gift med Bo Beta. Gift med Cia Ceta. Gift med Dan Delta. Gift med Eva Epsilon.',
       ARRAY['Anna Alfa.','Gift med Bo Beta.','Gift med Cia Ceta.','Gift med Dan Delta.','Gift med Eva Epsilon.'],-5261,v_actor);
  PERFORM pg_temp.f2a_event_for_state((p->>'principal')::uuid);
  SELECT array_agg(x::uuid ORDER BY o) INTO k FROM jsonb_array_elements_text(p->'clauses') WITH ORDINALITY AS t(x,o);
  -- K1 (k[2]): ægtefælle accepteret ⇒ med
  c:=pg_temp.f5b_claim(-5261,s,'relation.marriage',k[2],'Gift med Bo Beta.');
  sp:=pg_temp.f5b_spouse(-5261,s,p,c,k[2],'Bo Beta',1); PERFORM pg_temp.f2bii_ident(sp,'accepted',-52611,v_actor); sp1:=sp;
  -- K2 (k[3]): som K1 + et aktørforslag uden persona ⇒ ikke med (§8.2 pkt. 2)
  c:=pg_temp.f5b_claim(-5261,s,'relation.marriage',k[3],'Gift med Cia Ceta.');
  sp:=pg_temp.f5b_spouse(-5261,s,p,c,k[3],'Cia Ceta',2); PERFORM pg_temp.f2bii_ident(sp,'accepted',-52611,v_actor);
  PERFORM pg_temp.f2bii_other(-5261,s,k[3]);
  -- K3 (k[4]): ægtefælle uafklaret ⇒ ikke med (§8.2 pkt. 3)
  c:=pg_temp.f5b_claim(-5261,s,'relation.marriage',k[4],'Gift med Dan Delta.');
  sp:=pg_temp.f5b_spouse(-5261,s,p,c,k[4],'Dan Delta',3); PERFORM pg_temp.f2bii_ident(sp,'unresolved',NULL,v_actor);
  -- K4 (k[5]): som K1, men en menneskelig disposition ovenpå ⇒ ikke med (§8.2 pkt. 1)
  c:=pg_temp.f5b_claim(-5261,s,'relation.marriage',k[5],'Gift med Eva Epsilon.');
  sp:=pg_temp.f5b_spouse(-5261,s,p,c,k[5],'Eva Epsilon',4); PERFORM pg_temp.f2bii_ident(sp,'accepted',-52611,v_actor);
  PERFORM pg_temp.f2bii_await(k[2]); PERFORM pg_temp.f2bii_await(k[3]); PERFORM pg_temp.f2bii_await(k[4]); PERFORM pg_temp.f2bii_await(k[5]);
  INSERT INTO private.clause_disposition(observation_id,version,disposition,decided_by_kind,decided_by,decided_by_name,decided_at,evidence)
    VALUES (k[5],2,'kraever_menneske','human',v_actor,'fixture',clock_timestamp(),'{"note":"test"}');

  m:=private.relation_disposition_input(-5261);
  IF (SELECT array_agg(x) FROM jsonb_object_keys(m->'authorized_elements') x)<>ARRAY['relation-disposition:'||k[2]] THEN
    RAISE EXCEPTION 'DISP_TEST_FAILED: kun K1 er egnet (fik %)',m->'expected_counts';
  END IF;
  r:=pg_temp.f2bii_disp(-5261,v_actor,m);
  IF (SELECT disposition||'/'||version||'/'||(evidence->>'rule') FROM private.clause_disposition_current WHERE observation_id=k[2])
     <> 'fortolkning_foreslaaet/2/identity-per-actor-v1' THEN
    RAISE EXCEPTION 'DISP_TEST_FAILED: K1 skiftede ikke';
  END IF;
  IF r#>'{relation_results,0,derived_counts}'<>'{"dispositions":1}'::jsonb THEN RAISE EXCEPTION 'DISP_TEST_FAILED: derived %',r; END IF;
  IF NOT EXISTS (SELECT 1 FROM pgrowlocks('private.source_persona_identity') l
                   JOIN private.source_persona_identity i ON i.ctid=l.locked_row
                  WHERE i.source_persona_id=sp1 AND 'For Share'=ANY(l.modes)) THEN
    RAISE EXCEPTION 'DISP_TEST_FAILED: aktørens identitet ikke låst FOR SHARE';
  END IF;
  IF (SELECT count(*) FROM private.clause_disposition_current WHERE observation_id IN (k[3],k[4],k[5])
        AND disposition='fortolkning_foreslaaet')<>0 THEN RAISE EXCEPTION 'DISP_TEST_FAILED: andre ændret'; END IF;
  IF (private.relation_disposition_input(-5261)->'expected_counts'->>'relation_dispositions')::int<>0 THEN
    RAISE EXCEPTION 'DISP_TEST_FAILED: genkørsel ikke tom';
  END IF;
  -- negativtest D: håndbygget element for K4 (menneskelig disposition ovenpå)
  BEGIN
    PERFORM pg_temp.f2bii_disp(-5261,v_actor,jsonb_build_object(
      'expected_counts',jsonb_build_object('person_creates',0,'source_evidence',0,'relation_dispositions',1),
      'authorized_elements',jsonb_build_object('relation-disposition:'||k[5],jsonb_build_object(
        'actor_persona_ids','[]'::jsonb,'citing_interpretation_ids','[]'::jsonb,'from_disposition_version',2,'observation_id',k[5]::text))));
    RAISE EXCEPTION 'DISP_TEST_FAILED: D godtaget';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM NOT LIKE '%RELATION_DISPOSITION_NOT_ELIGIBLE%' THEN RAISE; END IF; END;
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  RAISE NOTICE 'OK: relation_disposition pr. aktør (K1 med; K2-K4 ikke; genkørsel tom; D afvist)';
END $disposition$;

-- negativtest E (Review Focus 5): et aktørforslag uden persona kommer til efter manifestet
DO $disposition_e$
DECLARE v_actor uuid:='11000000-0000-0000-0000-00000005b2b6'; s jsonb; p jsonb; c jsonb; v_k uuid; sp uuid; m jsonb;
BEGIN
  INSERT INTO person(id,levende,privat,status) VALUES (-5262,false,false,'5b');
  s:=pg_temp.f5b_source(-5262);
  p:=pg_temp.f5b_post(-5262,s,'II-62','Anna Alfa. Gift med Bo Beta.',ARRAY['Anna Alfa.','Gift med Bo Beta.'],-5262,v_actor);
  PERFORM pg_temp.f2a_event_for_state((p->>'principal')::uuid);
  v_k:=(p->'clauses'->>1)::uuid;
  c:=pg_temp.f5b_claim(-5262,s,'relation.marriage',v_k,'Gift med Bo Beta.');
  sp:=pg_temp.f5b_spouse(-5262,s,p,c,v_k,'Bo Beta',1); PERFORM pg_temp.f2bii_ident(sp,'accepted',-52611,v_actor);
  PERFORM pg_temp.f2bii_await(v_k);
  m:=private.relation_disposition_input(-5262);
  PERFORM pg_temp.f2bii_other(-5262,s,v_k);
  BEGIN
    PERFORM pg_temp.f2bii_disp(-5262,v_actor,m);
    RAISE EXCEPTION 'DISP_TEST_FAILED: E godtaget';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM NOT LIKE '%RELATION_DISPOSITION_NOT_ELIGIBLE%' THEN RAISE; END IF; END;
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  RAISE NOTICE 'OK: relation_disposition E afvist';
END $disposition_e$;
ROLLBACK;
