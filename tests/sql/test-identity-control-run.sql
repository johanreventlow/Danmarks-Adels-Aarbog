-- Trin 5b, Task 6: kontrolkørslen — serverens udvalg, forsegling, status og stikprøveregler.
\set ON_ERROR_STOP on
BEGIN;
\ir fixtures/relation-5b.sql

-- Én kilde med tre ægtefælle-personas, hver med én familie og én egnet rang-1-kandidat.
CREATE FUNCTION pg_temp.f5b_control_world(p_source bigint,p_actor uuid) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE s jsonb; p jsonb; c jsonb; v_sp uuid; v_ids uuid[]:='{}'; v_in jsonb; v_run uuid; v_cands jsonb:='[]'; i int;
  v_fam bigint; v_fam1 bigint; v_child jsonb;
BEGIN
  s:=pg_temp.f5b_source(p_source);
  FOR i IN 1..3 LOOP
    INSERT INTO person(id,levende,privat,status) VALUES (p_source*10-i*2,false,false,'5b'),(p_source*10-i*2-1,false,false,'5b');
    p:=pg_temp.f5b_post(p_source,s,'C-'||i,'Hoved '||i||'. g. m. Mage '||i||'.'||CASE WHEN i=1 THEN ' Søn To.' ELSE '' END,
       ARRAY['Hoved '||i||'.','g. m. Mage '||i||'.']||CASE WHEN i=1 THEN ARRAY['Søn To.'] ELSE '{}'::text[] END,
       p_source*10-i*2,p_actor);
    c:=pg_temp.f5b_claim(p_source,s,'relation.marriage',(p->'clauses'->>1)::uuid,'g. m. Mage '||i||'.');
    v_sp:=pg_temp.f5b_spouse(p_source,s,p,c,(p->'clauses'->>1)::uuid,'Mage '||i,1);
    v_fam:=pg_temp.f5b_family(p_source*10-i*2,p_source*10-i*2-1,1);
    v_ids:=v_ids||v_sp;
    IF i=1 THEN
      -- Et barn med præcis én strukturel kandidat (post C-2's hovedperson er barn i C-1's familie).
      -- Børn er taget ud af del 1 (errata §22.9): påstanden må hverken komme i populationen eller stikprøven.
      v_child:=pg_temp.f5b_claim(p_source,s,'relation.child',(p->'clauses'->>2)::uuid,'Søn To.');
      INSERT INTO private.interpretation_party(interpretation_key,party_role,version,source_persona_id,post_offset,origin,origin_ref)
        VALUES ((v_child->>'key')::uuid,'principal',1,(p->>'principal')::uuid,23,'relation_persona',gen_random_uuid());
      v_fam1:=v_fam;
    END IF;
  END LOOP;
  INSERT INTO family_member(family_id,person_id,rolle) VALUES (v_fam1,p_source*10-4,'barn');
  PERFORM set_config('request.jwt.claim.sub',p_actor::text,true);
  SET LOCAL ROLE authenticated;
  v_in:=red_identity_candidate_input(p_source,'{"mode":"undecided"}');
  FOR i IN 1..3 LOOP
    v_cands:=v_cands||jsonb_build_array(
      jsonb_build_object('source_persona_id',v_ids[i],'candidate_person_id',p_source*10-i*2-1,'rank',1,'score',0.95,'tier','auto',
        'basis',jsonb_build_object('signals','["name","family_partner"]'::jsonb,'corroboration_eligible',true)),
      jsonb_build_object('source_persona_id',v_ids[i],'candidate_person_id',p_source*10-i*2,'rank',2,'score',0.4,'tier','none',
        'basis','{"signals":["name"],"corroboration_eligible":false}'::jsonb),
      -- rang 3 og 4 (andre posters personer): mappingen må kun rumme rang 1-3
      jsonb_build_object('source_persona_id',v_ids[i],'candidate_person_id',p_source*10-((i%3)+1)*2,'rank',3,'score',0.3,'tier','none',
        'basis','{"signals":["name"],"corroboration_eligible":false}'::jsonb),
      jsonb_build_object('source_persona_id',v_ids[i],'candidate_person_id',p_source*10-((i%3)+1)*2-1,'rank',4,'score',0.2,'tier','none',
        'basis','{"signals":["name"],"corroboration_eligible":false}'::jsonb));
  END LOOP;
  v_run:=red_record_identity_candidates(jsonb_build_object('source_id',p_source,'generator_version','t','config','{}'::jsonb,
    'input_spec','{"mode":"undecided"}'::jsonb,'input_sha256',v_in->>'input_sha256'),v_cands);
  RESET ROLE;
  RETURN jsonb_build_object('run',v_run,'personas',to_jsonb(v_ids),'src',s);
END $$;

-- Afgør én stikprøvesag som på arket (visningsplads → serveren opløser).
CREATE FUNCTION pg_temp.f5b_decide_sample(p_ctl uuid,p_persona uuid,p_pos text,p_sheet text,p_rows text) RETURNS integer LANGUAGE sql AS $$
  SELECT red_afgoer_source_persona(p_persona,0,'same',NULL,'stikprøve',jsonb_build_object('basis','human_sheet',
    'sheet_sha256',p_sheet,'rows_sha256',p_rows,'line',1,'control_run_id',p_ctl,'display_position',p_pos::int));
$$;
GRANT EXECUTE ON FUNCTION pg_temp.f5b_decide_sample(uuid,uuid,text,text,text) TO authenticated;

DO $identity_control_run$
DECLARE
  v_actor uuid:='11000000-0000-0000-0000-00000005b601';
  w jsonb; v_ctl uuid; v_smp jsonb; v_sheet text:=repeat('a',64); v_rows text:=repeat('b',64); v_pos text; v_st text; v_i int;
  v_persona uuid;
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  w:=pg_temp.f5b_control_world(-5601,v_actor);
  IF (SELECT count(*) FROM private.relation_structural_candidates((SELECT interpretation_key FROM private.interpretation_current
        WHERE predicate='relation.child' AND source_id=-5601)))<>1 THEN
    RAISE EXCEPTION 'CONTROL_TEST_FAILED: barnets kandidat mangler';
  END IF;
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  SET LOCAL ROLE authenticated;
  v_ctl:=red_register_identity_control_run((w->>'run')::uuid);
  v_smp:=red_identity_control_sample(v_ctl);
  IF jsonb_array_length(v_smp->'samples')<>3 OR v_smp->'samples'->0->'mapping' IS NULL OR v_smp->'samples'->0 ? 'expected' THEN
    RAISE EXCEPTION 'CONTROL_TEST_FAILED: stikprøve %',jsonb_array_length(v_smp->'samples');
  END IF;
  -- Codex plan-r2 fund 3: et gentaget registreringskald (tabt svar) returnerer samme kørsel og samme stikprøve.
  IF red_register_identity_control_run((w->>'run')::uuid)<>v_ctl OR red_identity_control_sample(v_ctl)<>v_smp THEN
    RAISE EXCEPTION 'CONTROL_TEST_FAILED: registrering ikke idempotent';
  END IF;
  IF red_evaluate_identity_control_run(v_ctl)<>'not_ready' THEN RAISE EXCEPTION 'CONTROL_TEST_FAILED: før forsegling'; END IF;
  PERFORM red_seal_identity_control_run(v_ctl,v_sheet,v_rows);
  BEGIN
    PERFORM red_seal_identity_control_run(v_ctl,v_sheet,v_rows);
    RAISE EXCEPTION 'CONTROL_TEST_FAILED: dobbelt forsegling';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'IDENTITY_CONTROL_RUN_STATE_INVALID%' THEN RAISE; END IF;
  END;
  v_persona:=(v_smp->'samples'->0->>'source_persona_id')::uuid;
  -- klientleveret candidate_id og webkø-basis afvises for en stikprøvesag
  BEGIN
    PERFORM red_afgoer_source_persona(v_persona,0,'same',-56011,'web','{}'::jsonb);
    RAISE EXCEPTION 'CONTROL_TEST_FAILED: web på stikprøve';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'IDENTITY_CONTROL_SAMPLE_CONTEXT_INVALID%' THEN RAISE; END IF;
  END;
  -- de tre stikprøvesager afgøres som kandidat 1 via visningsplads
  FOR v_i IN 0..2 LOOP
    RESET ROLE;   -- opslaget i private kræver ejer; afgørelsen nedenfor sker som redaktør
    SELECT key INTO v_pos FROM jsonb_each_text(v_smp->'samples'->v_i->'mapping') m
     WHERE m.value=(SELECT c.id::text FROM private.source_persona_identity_candidate c
                     WHERE c.run_id=(w->>'run')::uuid AND c.rank=1
                       AND c.source_persona_id=(v_smp->'samples'->v_i->>'source_persona_id')::uuid);
    SET LOCAL ROLE authenticated;
    PERFORM pg_temp.f5b_decide_sample(v_ctl,(v_smp->'samples'->v_i->>'source_persona_id')::uuid,v_pos,v_sheet,v_rows);
    IF v_i<2 AND red_evaluate_identity_control_run(v_ctl)<>'not_ready' THEN RAISE EXCEPTION 'CONTROL_TEST_FAILED: not_ready'; END IF;
  END LOOP;
  IF red_evaluate_identity_control_run(v_ctl)<>'passed' THEN RAISE EXCEPTION 'CONTROL_TEST_FAILED: passed'; END IF;
  -- Codex plan-r2 fund 2: arkets afgørelser ændrer ikke kontrolhashen (spouse_identity_version udelades).
  RESET ROLE;
  IF private.control_input_list_sha256((w->>'run')::uuid) IS DISTINCT FROM
     (SELECT input_list_sha256 FROM private.identity_control_run WHERE id=v_ctl) THEN
    RAISE EXCEPTION 'CONTROL_TEST_FAILED: kontrolhash ændret af arkets afgørelser';
  END IF;
  IF (SELECT count(*) FROM private.identity_control_run WHERE candidate_run_id=(w->>'run')::uuid)<>1 THEN
    RAISE EXCEPTION 'CONTROL_TEST_FAILED: mere end én kontrolkørsel';
  END IF;
  SET LOCAL ROLE authenticated;
  -- seneste status er autoritativ: en senere om-afgørelse af en stikprøvesag gør kørslen failed
  PERFORM red_afgoer_source_persona(v_persona,1,'unresolved',NULL,'fortrudt','{}'::jsonb);
  IF red_evaluate_identity_control_run(v_ctl)<>'failed' THEN RAISE EXCEPTION 'CONTROL_TEST_FAILED: stale efter passed'; END IF;
  IF red_evaluate_identity_control_run(v_ctl)<>'failed' THEN RAISE EXCEPTION 'CONTROL_TEST_FAILED: failed genopstod'; END IF;
  RESET ROLE;
  IF (SELECT array_agg(status ORDER BY seq) FROM private.identity_control_event WHERE control_run_id=v_ctl)<>ARRAY['sealed','passed','failed'] THEN
    RAISE EXCEPTION 'CONTROL_TEST_FAILED: events';
  END IF;
  RAISE NOTICE 'OK: udvalg, idempotent registrering, forsegling, visningsplads, stabil kontrolhash, not_ready → passed → failed, ingen genopstandelse';
END $identity_control_run$;

DO $identity_control_deviation$
DECLARE
  v_actor uuid:='11000000-0000-0000-0000-00000005b602';
  w jsonb; v_ctl uuid; v_smp jsonb; v_sheet text:=repeat('c',64); v_rows text:=repeat('d',64); v_p uuid; v_person bigint; v_in jsonb;
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  w:=pg_temp.f5b_control_world(-5602,v_actor);
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  SET LOCAL ROLE authenticated;
  v_ctl:=red_register_identity_control_run((w->>'run')::uuid);
  v_smp:=red_identity_control_sample(v_ctl);
  PERFORM red_seal_identity_control_run(v_ctl,v_sheet,v_rows);
  -- Review Focus 4: P <id> med rang-1-personens id tæller som afvigelse
  v_p:=(v_smp->'samples'->0->>'source_persona_id')::uuid;
  RESET ROLE;
  SELECT candidate_person_id INTO v_person FROM private.source_persona_identity_candidate
   WHERE run_id=(w->>'run')::uuid AND source_persona_id=v_p AND rank=1;
  SET LOCAL ROLE authenticated;
  BEGIN
    PERFORM red_afgoer_source_persona(v_p,0,'same',v_person,'P-token',jsonb_build_object('basis','human_sheet',
      'sheet_sha256',v_sheet,'rows_sha256',v_rows,'line',1,'control_run_id',v_ctl,'display_position',1));
    RAISE EXCEPTION 'CONTROL_TEST_FAILED: P med visningsplads godtaget';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'IDENTITY_CONTROL_SAMPLE_CONTEXT_INVALID%' THEN RAISE; END IF;
  END;
  PERFORM red_afgoer_source_persona(v_p,0,'same',v_person,'P-token',jsonb_build_object('basis','human_sheet',
    'sheet_sha256',v_sheet,'rows_sha256',v_rows,'line',1,'control_run_id',v_ctl));
  IF red_evaluate_identity_control_run(v_ctl)<>'failed' THEN RAISE EXCEPTION 'CONTROL_TEST_FAILED: P-token bestod'; END IF;
  RESET ROLE;
  -- Codex plan-r1 fund 5: kun pladserne 1-3, selv med fire kandidater
  IF EXISTS (SELECT 1 FROM private.identity_control_sample s, jsonb_object_keys(s.mapping) k
              WHERE s.control_run_id=v_ctl AND s.sample_kind='identity' AND k NOT IN ('1','2','3'))
     OR NOT EXISTS (SELECT 1 FROM private.identity_control_sample s, jsonb_object_keys(s.mapping) k
              WHERE s.control_run_id=v_ctl AND s.sample_kind='identity' AND k='3') THEN
    RAISE EXCEPTION 'CONTROL_TEST_FAILED: mapping uden for 1-3';
  END IF;
  RAISE NOTICE 'OK: P <id> på en stikprøvesag er en afvigelse; mappingen rummer kun pladserne 1-3';
END $identity_control_deviation$;

DO $identity_control_stale_run$
DECLARE
  v_actor uuid:='11000000-0000-0000-0000-00000005b603';
  w jsonb; v_ctl uuid; v_in jsonb;
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  w:=pg_temp.f5b_control_world(-5603,v_actor);
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  SET LOCAL ROLE authenticated;
  v_ctl:=red_register_identity_control_run((w->>'run')::uuid);
  PERFORM red_seal_identity_control_run(v_ctl,repeat('e',64),repeat('f',64));
  -- Review Focus 5: ny kandidatkørsel efter forsegling
  v_in:=red_identity_candidate_input(-5603,'{"mode":"undecided"}');
  PERFORM red_record_identity_candidates(jsonb_build_object('source_id',-5603,'generator_version','t2','config','{"v":2}'::jsonb,
    'input_spec','{"mode":"undecided"}'::jsonb,'input_sha256',v_in->>'input_sha256'),'[]'::jsonb);
  IF red_evaluate_identity_control_run(v_ctl)<>'failed' THEN RAISE EXCEPTION 'CONTROL_TEST_FAILED: forældet kørsel'; END IF;
  RESET ROLE;
  IF (SELECT reason FROM private.identity_control_event WHERE control_run_id=v_ctl ORDER BY seq DESC LIMIT 1)<>'kandidatkoersel_foraeldet' THEN
    RAISE EXCEPTION 'CONTROL_TEST_FAILED: grund';
  END IF;
  RAISE NOTICE 'OK: ny kandidatkørsel gør kontrolkørslen failed';
END $identity_control_stale_run$;

-- Codex plan-r1 fund 2: en stikprøvesag kan ikke afgøres, før kørslen er forseglet.
DO $identity_control_unsealed$
DECLARE
  v_actor uuid:='11000000-0000-0000-0000-00000005b605';
  w jsonb; v_ctl uuid; v_smp jsonb; v_p uuid;
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  w:=pg_temp.f5b_control_world(-5605,v_actor);
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  SET LOCAL ROLE authenticated;
  v_ctl:=red_register_identity_control_run((w->>'run')::uuid);
  v_smp:=red_identity_control_sample(v_ctl);
  v_p:=(v_smp->'samples'->0->>'source_persona_id')::uuid;
  BEGIN
    PERFORM red_afgoer_source_persona(v_p,0,'unresolved',NULL,'web før forsegling','{}'::jsonb);
    RAISE EXCEPTION 'CONTROL_TEST_FAILED: afgjort før forsegling';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'IDENTITY_CONTROL_SAMPLE_NOT_SEALED%' THEN RAISE; END IF;
  END;
  RESET ROLE;
  RAISE NOTICE 'OK: stikprøvesag låst før forsegling';
END $identity_control_unsealed$;

-- Codex plan-r1 fund 1: inputdrift før registrering afvises; ændret input efter forsegling → failed.
DO $identity_control_input_drift$
DECLARE
  v_actor uuid:='11000000-0000-0000-0000-00000005b604';
  w jsonb; v_ctl uuid;
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  w:=pg_temp.f5b_control_world(-5604,v_actor);
  INSERT INTO person(id,levende,privat,status) VALUES (-56049,false,false,'5b drift');   -- ny person efter kørslen
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  SET LOCAL ROLE authenticated;
  BEGIN
    PERFORM red_register_identity_control_run((w->>'run')::uuid);
    RAISE EXCEPTION 'CONTROL_TEST_FAILED: inputdrift godtaget';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'IDENTITY_CONTROL_INPUT_DRIFT%' THEN RAISE; END IF;
  END;
  RESET ROLE;
  DELETE FROM person WHERE id=-56049;
  SET LOCAL ROLE authenticated;
  v_ctl:=red_register_identity_control_run((w->>'run')::uuid);
  PERFORM red_seal_identity_control_run(v_ctl,repeat('1',64),repeat('2',64));
  RESET ROLE;
  INSERT INTO person(id,levende,privat,status) VALUES (-56049,false,false,'5b drift');
  SET LOCAL ROLE authenticated;
  IF red_evaluate_identity_control_run(v_ctl)<>'failed' THEN RAISE EXCEPTION 'CONTROL_TEST_FAILED: ændret input bestod'; END IF;
  RESET ROLE;
  IF (SELECT reason FROM private.identity_control_event WHERE control_run_id=v_ctl ORDER BY seq DESC LIMIT 1)<>'kandidatinput_aendret' THEN
    RAISE EXCEPTION 'CONTROL_TEST_FAILED: grund';
  END IF;
  RAISE NOTICE 'OK: inputdrift før registrering afvist; ændret input efter forsegling gør kørslen failed';
END $identity_control_input_drift$;
ROLLBACK;
