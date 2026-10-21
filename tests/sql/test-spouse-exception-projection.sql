-- Trin 5b 2b-i Task 3 (spec §5.1, §5.4): arkets projektion og ordinal_beholdt.
\set ON_ERROR_STOP on
BEGIN;
\ir fixtures/relation-5b.sql
\ir fixtures/relation-2a.sql
\ir fixtures/relation-2bi.sql
DO $spouse_projection$
DECLARE v_actor uuid:='11000000-0000-0000-0000-0000002b0301'; s jsonb; a jsonb; b jsonb; c jsonb; d jsonb; o jsonb; pv jsonb;
  v_run uuid; v_proj jsonb; v_oid uuid; v_err text; v_unres uuid;
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  INSERT INTO person(id,levende,privat,status,visning_navn) SELECT g,false,false,'2bi','P'||abs(g) FROM generate_series(-21340,-21301) g;
  s:=pg_temp.f5b_source(-21301);
  -- a: uafgjort ægtefælle, kandidat nr. 1 = partneren ⇒ i s_rows
  a:=pg_temp.f2bi_open_marriage(-21301,s,'S-1',-21301,-21302,v_actor,1,1);
  -- b: uafgjort ægtefælle, kandidat nr. 1 er ikke partneren ⇒ ikke i s_rows
  b:=pg_temp.f2bi_open_marriage(-21301,s,'S-2',-21303,-21304,v_actor,1,1);
  -- d: uafgjort, men afgjort unresolved i køen ⇒ ikke i s_rows (Review Focus 5, test unresolved_udelades)
  d:=pg_temp.f2bi_open_marriage(-21301,s,'S-3',-21305,-21306,v_actor,1,1);
  -- o: accepteret og bundet med ordinal-afvigelse ⇒ i o_rows
  o:=pg_temp.f2a_marriage(-21301,s,'O-1',-21307,-21308,v_actor,2,1);
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  SET LOCAL ROLE authenticated;
  pv:=red_preview_relation_decisions(-21301);       -- kun o er egnet (a/b/d har uafgjort ægtefælle)
  PERFORM red_decide_relation_interpretations(-21301,pv->>'set_sha256');
  PERFORM red_afgoer_source_persona((d->>'spouse_persona')::uuid,0,'unresolved',NULL,'test','{}');
  RESET ROLE;
  v_run:=pg_temp.f2bi_candidates(-21301,v_actor,jsonb_build_array(
    jsonb_build_object('persona',a->>'spouse_persona','person',-21302,'rank',1),
    jsonb_build_object('persona',a->>'spouse_persona','person',-21321,'rank',2),
    jsonb_build_object('persona',b->>'spouse_persona','person',-21320,'rank',1),
    jsonb_build_object('persona',d->>'spouse_persona','person',-21306,'rank',1)));

  v_proj:=private.spouse_exception_projection(-21301);
  -- Indholds-id (#151, spec §4 pkt. 1): v2 nøgler O-rækken på fortolkningsnøgle og version, uden tilfældigt
  -- afgørelsesversions-id og uden tilstandshash (ligheden tjekkes fortsat i projektionen).
  IF v_proj->>'contract'<>'spouse-exception-rows-v2'
     OR v_proj#>>'{o_rows,0,interpretation_key}' IS DISTINCT FROM o->'claim'->>'key'
     OR (v_proj#>>'{o_rows,0,interpretation_version}')::int IS DISTINCT FROM
        (SELECT version FROM private.interpretation_current WHERE interpretation_key=(o->'claim'->>'key')::uuid)
     OR v_proj->'o_rows'->0 ? 'interpretation_id' OR v_proj->'o_rows'->0 ? 'state_sha256' THEN
    RAISE EXCEPTION 'SPOUSE_PROJECTION_TEST_FAILED: v2-kontrakt %', v_proj->'o_rows';
  END IF;
  IF jsonb_array_length(v_proj->'s_rows')<>1
     OR v_proj#>>'{s_rows,0,source_persona_id}'<>a->>'spouse_persona'
     OR (v_proj#>>'{s_rows,0,candidate_count}')::int<>2 OR (v_proj#>>'{s_rows,0,identity_version}')::int<>0
     OR (v_proj#>>'{s_rows,0,family_id}')::bigint<>(a->>'family')::bigint
     OR jsonb_array_length(v_proj->'o_rows')<>1 OR (v_proj#>>'{o_rows,0,book_ordinal}')::int<>2
     OR (v_proj#>>'{o_rows,0,family_ordinal}')::int<>1 THEN
    RAISE EXCEPTION 'SPOUSE_PROJECTION_TEST_FAILED: %', v_proj;
  END IF;
  -- deterministisk: to kald giver samme tekst
  IF private.spouse_exception_projection(-21301)::text<>v_proj::text THEN RAISE EXCEPTION 'SPOUSE_PROJECTION_TEST_FAILED: ikke deterministisk'; END IF;

  -- ordinal_beholdt godtages og fjerner rækken fra o_rows (gældende klassifikation er den seneste)
  SELECT id INTO v_oid FROM private.interpretation_current WHERE interpretation_key=(o->'claim'->>'key')::uuid;
  PERFORM private.append_relation_classification(v_oid,'ordinal_beholdt','{"line":1,"note":"test"}');
  IF jsonb_array_length(private.spouse_exception_projection(-21301)->'o_rows')<>0 THEN
    RAISE EXCEPTION 'SPOUSE_PROJECTION_TEST_FAILED: beholdt ordinal stadig i o_rows';
  END IF;
  -- en historisk afvigelse, hvis tilstand er ændret, kommer ikke med (Codex r2 #7)
  PERFORM private.append_relation_classification(v_oid,'ordinal_afvigelse','{"line":1,"note":"test"}');
  IF jsonb_array_length(private.spouse_exception_projection(-21301)->'o_rows')<>1 THEN RAISE EXCEPTION 'SPOUSE_PROJECTION_TEST_FAILED: gældende afvigelse'; END IF;
  UPDATE family_member SET konfidens='sandsynlig' WHERE family_id=(o->>'family')::bigint AND person_id=-21307 AND rolle='partner';
  IF jsonb_array_length(private.spouse_exception_projection(-21301)->'o_rows')<>0 THEN
    RAISE EXCEPTION 'SPOUSE_PROJECTION_TEST_FAILED: historisk afvigelse genoplivet';
  END IF;
  -- en ukendt klassifikation afvises stadig
  BEGIN
    PERFORM private.append_relation_classification(v_oid,'ordinal_noget','{"line":1}');
    RAISE EXCEPTION 'SPOUSE_PROJECTION_TEST_FAILED: ukendt klassifikation godtaget';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  -- kontrolstikprøve ⇒ fejl
  INSERT INTO private.identity_control_run(source_id,candidate_run_id,identity_population_sha256,relation_population_sha256,
    input_list_sha256,k_random,created_by)
    VALUES (-21301,v_run,repeat('a',64),repeat('b',64),repeat('c',64),1,v_actor);
  INSERT INTO private.identity_control_sample(control_run_id,sample_kind,stratum,source_persona_id,identity_version,mapping,expected)
    SELECT id,'identity','single_family',(a->>'spouse_persona')::uuid,0,
           jsonb_build_object('1',(SELECT c.id::text FROM private.source_persona_identity_candidate c WHERE c.run_id=v_run AND c.rank=1
                                     AND c.source_persona_id=(a->>'spouse_persona')::uuid)),'1'
      FROM private.identity_control_run WHERE source_id=-21301;
  BEGIN
    PERFORM private.spouse_exception_projection(-21301);
    RAISE EXCEPTION 'SPOUSE_PROJECTION_TEST_FAILED: kontrolstikprøve godtaget';
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT;
    IF v_err NOT LIKE 'SPOUSE_SHEET_CONTROL_SAMPLE%' THEN RAISE; END IF;
  END;
  -- ingen grants
  IF has_function_privilege('authenticated','private.spouse_exception_projection(bigint)','EXECUTE')
     OR has_function_privilege('anon','private.spouse_exception_projection(bigint)','EXECUTE')
     OR has_function_privilege('service_role','private.spouse_exception_projection(bigint)','EXECUTE') THEN
    RAISE EXCEPTION 'SPOUSE_PROJECTION_TEST_FAILED: grants';
  END IF;
  RAISE NOTICE 'OK: arkets projektion';
END $spouse_projection$;
ROLLBACK;
