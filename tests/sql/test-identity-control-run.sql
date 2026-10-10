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
-- ---------- Spec §23: kontrolkørsel v2 (navnefæller, udelukkelse, projektion, fordeling) ----------
-- Seks hovedposter (hovedperson 1700-1760), hver med én ægtefælle M_i som eneste partner og rang 1:
--   1: M1 1705-1770, ingen andre                  → single_family
--   2: M2 + N2 (samme visningsnavn, 1710-1780)    → navnefaelle, mapping 2 pladser
--   3: M3 død 1363                                 → udelukket rang1_tidsumulig
--   4: M4 + N4a/b/c (samme navn)                   → udelukket navnefaeller_over_3
--   5: M5 uden datoer + X5 død 1363 (andet navn)   → single_family, X5 ikke i mappingen
--   6: M6 + N6 (samme visningsnavn i andet case/mellemrum, fuldt navn NULL) + Q6 (andet navn, fuldt NULL)
--                                                  → navnefaelle via visning_navn alene; Q6 som udfyldning
CREATE FUNCTION pg_temp.f5b_world_v2(p_source bigint,p_actor uuid) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE s jsonb; p jsonb; c jsonb; v_ids uuid[]:='{}'; v_in jsonb; v_run uuid; v_cands jsonb:='[]'; i int; h bigint; m bigint;
  x bigint:=p_source*100; v_extra jsonb;
BEGIN
  s:=pg_temp.f5b_source(p_source);
  FOR i IN 1..6 LOOP
    h:=p_source*10-i*2; m:=h-1;
    INSERT INTO person(id,levende,privat,status) VALUES (h,false,false,'5b'),(m,false,false,'5b');
    p:=pg_temp.f5b_post(p_source,s,'V-'||i,'Hoved '||i||'. g. m. Mage '||i||'.',ARRAY['Hoved '||i||'.','g. m. Mage '||i||'.'],h,p_actor);
    c:=pg_temp.f5b_claim(p_source,s,'relation.marriage',(p->'clauses'->>1)::uuid,'g. m. Mage '||i||'.');
    v_ids:=v_ids||pg_temp.f5b_spouse(p_source,s,p,c,(p->'clauses'->>1)::uuid,'Mage '||i,1);
    PERFORM pg_temp.f5b_family(h,m,1);
    PERFORM pg_temp.f5b_life(h,1700,1760);
  END LOOP;
  INSERT INTO person(id,levende,privat,status) SELECT x-k,false,false,'5b' FROM generate_series(1,7) k;
  PERFORM pg_temp.f5b_life(p_source*10-1*2-1,1705,1770);   -- M1
  PERFORM pg_temp.f5b_life(p_source*10-2*2-1,1705,1770);   -- M2
  PERFORM pg_temp.f5b_life(x-1,1710,1780);                 -- N2
  PERFORM pg_temp.f5b_life(p_source*10-3*2-1,NULL,1363);   -- M3
  PERFORM pg_temp.f5b_life(p_source*10-4*2-1,1705,1770);   -- M4
  PERFORM pg_temp.f5b_life(x-5,NULL,1363);                 -- X5
  -- visningsnavne til sidst (fakta kan regenerere cachen)
  FOR i IN 1..6 LOOP
    UPDATE person SET visning_navn='Mage '||i,visning_fuldt_navn='Mage '||i||' Berg' WHERE id=p_source*10-i*2-1;
  END LOOP;
  UPDATE person SET visning_navn='Mage 2',visning_fuldt_navn='Mage 2 Berg' WHERE id=x-1;
  UPDATE person SET visning_navn='Mage 4',visning_fuldt_navn='Mage 4 Berg' WHERE id IN (x-2,x-3,x-4);
  UPDATE person SET visning_navn='Anden Fem',visning_fuldt_navn='Anden Fem Berg' WHERE id=x-5;
  UPDATE person SET visning_fuldt_navn=NULL WHERE id=p_source*10-6*2-1;
  UPDATE person SET visning_navn=' mage 6',visning_fuldt_navn=NULL WHERE id=x-6;
  UPDATE person SET visning_navn='Anden Seks',visning_fuldt_navn=NULL WHERE id=x-7;
  PERFORM set_config('request.jwt.claim.sub',p_actor::text,true);
  SET LOCAL ROLE authenticated;
  v_in:=red_identity_candidate_input(p_source,'{"mode":"undecided"}');
  FOR i IN 1..6 LOOP
    v_cands:=v_cands||jsonb_build_array(jsonb_build_object('source_persona_id',v_ids[i],'candidate_person_id',p_source*10-i*2-1,
      'rank',1,'score',0.95,'tier','auto','basis',jsonb_build_object('signals','["name","family_partner"]'::jsonb,'corroboration_eligible',true)));
    v_extra:=CASE i WHEN 2 THEN jsonb_build_array(x-1) WHEN 4 THEN jsonb_build_array(x-2,x-3,x-4) WHEN 5 THEN jsonb_build_array(x-5)
                    WHEN 6 THEN jsonb_build_array(x-6,x-7) ELSE '[]'::jsonb END;
    v_cands:=v_cands||coalesce((SELECT jsonb_agg(jsonb_build_object('source_persona_id',v_ids[i],'candidate_person_id',e::bigint,
      'rank',o+1,'score',0.5,'tier','none','basis','{"signals":["name"],"corroboration_eligible":false}'::jsonb) ORDER BY o)
      FROM jsonb_array_elements_text(v_extra) WITH ORDINALITY t(e,o)),'[]'::jsonb);
  END LOOP;
  v_run:=red_record_identity_candidates(jsonb_build_object('source_id',p_source,'generator_version','t','config','{"topK":10}'::jsonb,
    'input_spec','{"mode":"undecided"}'::jsonb,'input_sha256',v_in->>'input_sha256'),v_cands);
  RESET ROLE;
  RETURN jsonb_build_object('run',v_run,'personas',to_jsonb(v_ids),'x',x);
END $$;

DO $control_v2$
DECLARE
  v_actor uuid:='11000000-0000-0000-0000-00000005b701';
  w jsonb; v_ctl uuid; v_p uuid[]; x bigint; v_s text:=repeat('a',64); v_r text:=repeat('b',64); smp record; v_pos text;
  v_ctx jsonb; v_fam bigint; v_ord int; v_cid uuid; v_empty text;
BEGIN
  -- ren fordeling og projektion
  IF private.control_allocate('{"single_family":150,"multi_family":42}',20)<>'{"single_family":16,"multi_family":4}'::jsonb
     OR private.control_allocate('{"a":1,"b":100}',3)<>'{"a":1,"b":2}'::jsonb
     OR private.control_allocate('{"a":2,"b":1}',20)<>'{"a":2,"b":1}'::jsonb
     OR private.control_allocate('{"single_family":5,"multi_family":5}',3)<>'{"multi_family":2,"single_family":1}'::jsonb
     OR private.control_allocate('{}',20)<>'{}'::jsonb THEN
    RAISE EXCEPTION 'CONTROL_V2_TEST_FAILED: fordeling';
  END IF;
  PERFORM pg_temp.f5b_actor(v_actor);
  w:=pg_temp.f5b_world_v2(-5701,v_actor);
  v_p:=ARRAY(SELECT jsonb_array_elements_text(w->'personas')::uuid); x:=(w->>'x')::bigint;
  IF private.candidate_impossible(-57012,-57013) OR NOT private.candidate_impossible(-57012,x-5)
     OR private.candidate_impossible(-57021,x-5) THEN     -- M5 (uden datoer) som hovedperson: intet fjernes
    RAISE EXCEPTION 'CONTROL_V2_TEST_FAILED: candidate_impossible';
  END IF;
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  SET LOCAL ROLE authenticated;
  v_ctl:=red_register_identity_control_run((w->>'run')::uuid);
  RESET ROLE;
  IF (SELECT count(*) FROM private.identity_control_sample WHERE control_run_id=v_ctl)<>4
     OR (SELECT stratum FROM private.identity_control_sample WHERE control_run_id=v_ctl AND source_persona_id=v_p[2])<>'navnefaelle'
     OR (SELECT stratum FROM private.identity_control_sample WHERE control_run_id=v_ctl AND source_persona_id=v_p[6])<>'navnefaelle'
     OR (SELECT stratum FROM private.identity_control_sample WHERE control_run_id=v_ctl AND source_persona_id=v_p[1])<>'single_family'
     OR (SELECT count(*) FROM jsonb_object_keys((SELECT mapping FROM private.identity_control_sample WHERE control_run_id=v_ctl AND source_persona_id=v_p[2])))<>2
     OR (SELECT count(*) FROM jsonb_object_keys((SELECT mapping FROM private.identity_control_sample WHERE control_run_id=v_ctl AND source_persona_id=v_p[6])))<>3
     OR (SELECT count(*) FROM jsonb_object_keys((SELECT mapping FROM private.identity_control_sample WHERE control_run_id=v_ctl AND source_persona_id=v_p[5])))<>1
     OR (SELECT reason FROM private.identity_control_exclusion WHERE control_run_id=v_ctl AND source_persona_id=v_p[3]) IS DISTINCT FROM 'rang1_tidsumulig'
     OR (SELECT reason FROM private.identity_control_exclusion WHERE control_run_id=v_ctl AND source_persona_id=v_p[4]) IS DISTINCT FROM 'navnefaeller_over_3'
     OR (SELECT k_random FROM private.identity_control_run WHERE id=v_ctl)<>20
     OR (SELECT excluded_sha256 FROM private.identity_control_run WHERE id=v_ctl) IS NULL
     OR EXISTS (SELECT 1 FROM private.identity_control_sample s, jsonb_each_text(s.mapping) m
                  JOIN private.source_persona_identity_candidate c ON c.id=m.value::uuid
                 WHERE s.control_run_id=v_ctl AND c.candidate_person_id=x-5) THEN
    RAISE EXCEPTION 'CONTROL_V2_TEST_FAILED: udvalg/udelukkelse/projektion';
  END IF;
  -- korrekte afgørelser af de fire stikprøvesager ⇒ passed; bekræftelsen finder 0 (resten er udelukket)
  SET LOCAL ROLE authenticated;
  PERFORM red_seal_identity_control_run(v_ctl,v_s,v_r);
  RESET ROLE;
  FOR smp IN SELECT s.* FROM private.identity_control_sample s WHERE s.control_run_id=v_ctl ORDER BY s.id LOOP
    SELECT m.key INTO v_pos FROM jsonb_each_text(smp.mapping) m WHERE m.value=smp.expected;
    SET LOCAL ROLE authenticated;
    PERFORM pg_temp.f5b_decide_sample(v_ctl,smp.source_persona_id,v_pos,v_s,v_r);
    RESET ROLE;
  END LOOP;
  v_empty:=private.reimport_canonical_json_sha256('[]'::jsonb);   -- som ejer: private er lukket for authenticated
  SET LOCAL ROLE authenticated;
  IF red_evaluate_identity_control_run(v_ctl)<>'passed' THEN RAISE EXCEPTION 'CONTROL_V2_TEST_FAILED: passed'; END IF;
  IF red_corroborate_family_identities(v_ctl,v_empty)<>0 THEN
    RAISE EXCEPTION 'CONTROL_V2_TEST_FAILED: bekræftelse tog udelukkede';
  END IF;
  RESET ROLE;
  RAISE NOTICE 'OK: v2 — fordeling, projektion, navnefæller (også uden fuldt navn), udelukkelse, passed, bekræftelsen springer udelukkede over';
END $control_v2$;
-- Spec §23.4 (errata 2026-10-10): `1=2` — to visningspladser er samme individ (dublet i basen). Kortet tæller som
-- enighed, når maskinens kandidat er blandt de nævnte; identiteten bindes til laveste plads; dubletten gemmes.
CREATE FUNCTION pg_temp.f5b_decide_same(p_ctl uuid,p_persona uuid,p_pos jsonb,p_sheet text,p_rows text,p_first int DEFAULT NULL)
RETURNS integer LANGUAGE sql AS $$
  SELECT red_afgoer_source_persona(p_persona,0,'same',NULL,'dublet',jsonb_build_object('basis','human_sheet',
    'sheet_sha256',p_sheet,'rows_sha256',p_rows,'line',1,'control_run_id',p_ctl,
    'display_position',coalesce(p_first,(p_pos->>0)::int),'display_positions',p_pos));
$$;
GRANT EXECUTE ON FUNCTION pg_temp.f5b_decide_same(uuid,uuid,jsonb,text,text,int) TO authenticated;

DO $same_individual$
DECLARE
  v_actor uuid:='11000000-0000-0000-0000-00000005b606';
  w jsonb; v_ctl uuid; v_smp jsonb; v_sheet text:=repeat('a',64); v_rows text:=repeat('b',64);
  v_pe int; v_po int; v_p uuid; v_i int; v_bad jsonb; v_first int; v_ev jsonb; v_person bigint;
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  -- Verden A: kort 0 besvares `pe=po` (maskinens plads + en anden), de øvrige normalt ⇒ passed.
  w:=pg_temp.f5b_control_world(-5606,v_actor);
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  SET LOCAL ROLE authenticated;
  v_ctl:=red_register_identity_control_run((w->>'run')::uuid);
  v_smp:=red_identity_control_sample(v_ctl);
  PERFORM red_seal_identity_control_run(v_ctl,v_sheet,v_rows);
  RESET ROLE;
  FOR v_i IN 0..2 LOOP
    v_p:=(v_smp->'samples'->v_i->>'source_persona_id')::uuid;
    SELECT m.key::int INTO v_pe FROM private.identity_control_sample s, jsonb_each_text(s.mapping) m
     WHERE s.control_run_id=v_ctl AND s.source_persona_id=v_p AND m.value=s.expected;
    IF v_i=0 THEN
      v_po:=CASE WHEN v_pe=3 THEN 1 ELSE 3 END;
      -- ugyldige former afvises: én plads, dubletter, usorteret, display_position≠laveste, plads uden for mappingen
      SET LOCAL ROLE authenticated;
      FOREACH v_bad IN ARRAY ARRAY[jsonb_build_array(least(v_pe,v_po)),jsonb_build_array(v_pe,v_pe),
          jsonb_build_array(greatest(v_pe,v_po),least(v_pe,v_po)),'[1,4]'::jsonb,'["1","2"]'::jsonb,'{}'::jsonb] LOOP
        BEGIN
          PERFORM pg_temp.f5b_decide_same(v_ctl,v_p,v_bad,v_sheet,v_rows,least(v_pe,v_po));
          RAISE EXCEPTION 'CONTROL_TEST_FAILED: ugyldig dublet % godtaget',v_bad;
        EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'IDENTITY_CONTROL_SAMPLE_CONTEXT_INVALID%' THEN RAISE; END IF;
        END;
      END LOOP;
      BEGIN
        PERFORM pg_temp.f5b_decide_same(v_ctl,v_p,jsonb_build_array(least(v_pe,v_po),greatest(v_pe,v_po)),v_sheet,v_rows,greatest(v_pe,v_po));
        RAISE EXCEPTION 'CONTROL_TEST_FAILED: display_position ikke laveste godtaget';
      EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'IDENTITY_CONTROL_SAMPLE_CONTEXT_INVALID%' THEN RAISE; END IF;
      END;
      PERFORM pg_temp.f5b_decide_same(v_ctl,v_p,jsonb_build_array(least(v_pe,v_po),greatest(v_pe,v_po)),v_sheet,v_rows);
      RESET ROLE;
      SELECT i.evidence,i.canonical_person_id INTO v_ev,v_person FROM private.source_persona_identity i WHERE i.source_persona_id=v_p;
      IF v_ev->'display_positions'<>jsonb_build_array(least(v_pe,v_po),greatest(v_pe,v_po))
         OR (v_ev->>'display_position')::int<>least(v_pe,v_po)
         OR jsonb_array_length(v_ev->'same_individual_person_ids')<>2
         OR v_person<>(SELECT c.candidate_person_id FROM private.identity_control_sample s
                         JOIN private.source_persona_identity_candidate c ON c.id=(s.mapping->>least(v_pe,v_po)::text)::uuid
                        WHERE s.control_run_id=v_ctl AND s.source_persona_id=v_p) THEN
        RAISE EXCEPTION 'CONTROL_TEST_FAILED: dublet-evidens %',v_ev;
      END IF;
    ELSE
      SET LOCAL ROLE authenticated;
      PERFORM pg_temp.f5b_decide_sample(v_ctl,v_p,v_pe::text,v_sheet,v_rows);
      RESET ROLE;
    END IF;
  END LOOP;
  SET LOCAL ROLE authenticated;
  IF red_evaluate_identity_control_run(v_ctl)<>'passed' THEN RAISE EXCEPTION 'CONTROL_TEST_FAILED: dublet med maskinens plads bestod ikke'; END IF;
  -- dublet-feltet er kun for forseglede stikprøvesager
  BEGIN
    PERFORM red_afgoer_source_persona(gen_random_uuid(),0,'same',1,'web','{"display_positions":[1,2]}'::jsonb);
    RAISE EXCEPTION 'CONTROL_TEST_FAILED: dublet uden kontrolkørsel';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'IDENTITY_CONTROL_SAMPLE_CONTEXT_INVALID%' AND SQLERRM NOT LIKE 'EVIDENCE_PERSONA_BASIS_REQUIRED%' THEN RAISE; END IF;
  END;
  RESET ROLE;

  -- Verden B: kort 0 besvares med to pladser UDEN maskinens ⇒ afvigelse.
  w:=pg_temp.f5b_control_world(-5607,v_actor);
  SET LOCAL ROLE authenticated;
  v_ctl:=red_register_identity_control_run((w->>'run')::uuid);
  v_smp:=red_identity_control_sample(v_ctl);
  PERFORM red_seal_identity_control_run(v_ctl,v_sheet,v_rows);
  RESET ROLE;
  v_p:=(v_smp->'samples'->0->>'source_persona_id')::uuid;
  SELECT m.key::int INTO v_pe FROM private.identity_control_sample s, jsonb_each_text(s.mapping) m
   WHERE s.control_run_id=v_ctl AND s.source_persona_id=v_p AND m.value=s.expected;
  SELECT jsonb_agg(k ORDER BY k) INTO v_bad FROM unnest(ARRAY[1,2,3]) k WHERE k<>v_pe;
  SET LOCAL ROLE authenticated;
  PERFORM pg_temp.f5b_decide_same(v_ctl,v_p,v_bad,v_sheet,v_rows);
  IF red_evaluate_identity_control_run(v_ctl)<>'failed' THEN RAISE EXCEPTION 'CONTROL_TEST_FAILED: dublet uden maskinens plads bestod'; END IF;
  RESET ROLE;
  RAISE NOTICE 'OK: 1=2 — enighed når maskinens plads er nævnt, binding til laveste plads, dublet i evidensen, ugyldige former afvist, afvigelse ellers';
END $same_individual$;

ROLLBACK;
