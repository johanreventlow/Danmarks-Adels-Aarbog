-- Trin 6b, Task 6: fixtures til publication_identity (ceremoni C). Bygger på publication-persona.sql (indlæses her).
-- Kald som ejer, før SET ROLE. Alt er syntetisk; ingen navne eller posttekst i output.
--
-- pi_world(p_base, p_actor, p_n): kilde p_base, n helposter (record_key 'r<i>', person p_base*1000-i) og en finaliseret
--   B-batch (publication_persona, profil fixture-pub-a). Returnerer {src, b_batch, posts:[pp_post…], personas:[uuid…]}.
-- pi_cand(persona, rep, rank, members): én kandidatrække som generatoren (basis.member_scores).
-- pi_run(world, config, cands[, tag]): kandidatkørsel i list-tilstand over verdenens personas, registreret med
--   red_record_identity_candidates (inputtets hash fra red_identity_candidate_input).
-- pi_payload(world, i, run, outcome, answer[, override]): writerens payload for persona i (1-baseret).
-- pi_begin / pi_apply / pi_finalize: autorisation + begin, apply og finalize som redaktøren.

\i tests/sql/fixtures/publication-persona.sql

CREATE OR REPLACE FUNCTION pg_temp.pi_world(p_base bigint, p_actor uuid, p_n int) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_src jsonb; v_posts jsonb:='[]'::jsonb; v_fx jsonb; v_els jsonb:='{}'::jsonb; v_batch uuid; v_i int; v_personas jsonb;
BEGIN
  v_src:=pg_temp.pp_source(p_base,p_actor);
  FOR v_i IN 1..p_n LOOP
    v_fx:=pg_temp.pp_post(v_src,'r'||v_i,p_base*1000-v_i);
    v_posts:=v_posts||jsonb_build_array(v_fx);
    v_els:=v_els||jsonb_build_object('publication-persona:r'||v_i,pg_temp.pp_payload(v_src,v_fx));
  END LOOP;
  v_batch:=pg_temp.pp_begin(v_src,'fixture-pub-a','B-'||p_base,v_els);
  FOR v_i IN 1..p_n LOOP
    PERFORM pg_temp.pp_apply(v_src,v_batch,'publication-persona:r'||v_i,v_els->('publication-persona:r'||v_i));
  END LOOP;
  PERFORM set_config('request.jwt.claim.sub',v_src->>'actor',true); PERFORM set_config('role','authenticated',true);
  PERFORM public.red_finalize_reimport(v_batch);
  RESET role;
  SELECT jsonb_agg(e.payload->'result_receipt'->>'source_persona_id' ORDER BY (substr(e.source_record_key,2))::int) INTO v_personas
    FROM private.reimport_event e WHERE e.batch_id=v_batch AND e.operation='publication_persona';
  RETURN jsonb_build_object('src',v_src,'b_batch',v_batch,'posts',v_posts,'personas',v_personas);
END $$;

CREATE OR REPLACE FUNCTION pg_temp.pi_persona(p_world jsonb, p_i int) RETURNS uuid LANGUAGE sql AS $$
  SELECT (p_world->'personas'->>(p_i-1))::uuid
$$;
CREATE OR REPLACE FUNCTION pg_temp.pi_post(p_world jsonb, p_i int) RETURNS jsonb LANGUAGE sql AS $$
  SELECT p_world->'posts'->(p_i-1)
$$;

CREATE OR REPLACE FUNCTION pg_temp.pi_ms(p_person bigint, p_score numeric, p_signals text[]) RETURNS jsonb LANGUAGE sql AS $$
  SELECT jsonb_build_object('person_id',p_person,'score_raw',p_score,'signals',to_jsonb(p_signals))
$$;

CREATE OR REPLACE FUNCTION pg_temp.pi_cand(p_persona uuid, p_rep bigint, p_rank int, p_members jsonb) RETURNS jsonb LANGUAGE sql AS $$
  SELECT jsonb_build_object('source_persona_id',p_persona::text,'candidate_person_id',p_rep,'rank',p_rank,
    'score',round(least(1,(SELECT max((e->>'score_raw')::numeric) FROM jsonb_array_elements(p_members) e)),4),'tier','review',
    'basis',jsonb_build_object('signals',jsonb_build_array('name'),'member_scores',p_members))
$$;

CREATE OR REPLACE FUNCTION pg_temp.pi_run(p_world jsonb, p_config jsonb, p_cands jsonb) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_spec jsonb; v_in jsonb; v_run uuid; v_source bigint:=(p_world->'src'->>'source')::bigint;
BEGIN
  SELECT jsonb_build_object('mode','list','persona_ids',jsonb_agg(x ORDER BY x)) INTO v_spec
    FROM jsonb_array_elements_text(p_world->'personas') x;
  PERFORM set_config('request.jwt.claim.sub',p_world->'src'->>'actor',true); PERFORM set_config('role','authenticated',true);
  v_in:=public.red_identity_candidate_input(v_source,v_spec);
  v_run:=public.red_record_identity_candidates(jsonb_build_object('source_id',v_source,'generator_version','t6b','config',p_config,
    'input_spec',v_spec,'input_sha256',v_in->>'input_sha256'),p_cands);
  RESET role;
  RETURN v_run;
EXCEPTION WHEN OTHERS THEN RESET role; RAISE;
END $$;

CREATE OR REPLACE FUNCTION pg_temp.pi_payload(p_world jsonb, p_i int, p_run uuid, p_outcome text, p_answer text,
                                              p_override jsonb DEFAULT '{}'::jsonb) RETURNS jsonb LANGUAGE sql AS $$
  SELECT jsonb_build_object(
    'answer',to_jsonb(p_answer),
    'binding_id',pg_temp.pi_post(p_world,p_i)->>'binding',
    'binding_status','published',
    'candidate_run_id',p_run::text,
    'candidates_sha256',(SELECT r.candidates_sha256 FROM private.source_persona_identity_candidate_run r WHERE r.id=p_run),
    'expected_identity_version',0,
    'outcome',p_outcome,
    'person_id',(pg_temp.pi_post(p_world,p_i)->>'person')::bigint,
    'persona_batch_id',p_world->>'b_batch',
    'rows_sha256',CASE WHEN p_answer IS NULL THEN NULL ELSE repeat('b',64) END,
    'same_as_hint_person_id',NULL,
    'sheet_line',CASE WHEN p_answer IS NULL THEN NULL ELSE to_jsonb(p_i) END,
    'sheet_sha256',CASE WHEN p_answer IS NULL THEN NULL ELSE repeat('a',64) END,
    'source_persona_id',pg_temp.pi_persona(p_world,p_i)::text) || p_override
$$;

CREATE OR REPLACE FUNCTION pg_temp.pi_el(p_payload jsonb) RETURNS text LANGUAGE sql AS $$
  SELECT 'publication-identity:'||(p_payload->>'source_persona_id')
$$;

-- Autoriser og åbn en C-batch for payloads (array); elementid = publication-identity:<persona>, medmindre p_ids gives.
CREATE OR REPLACE FUNCTION pg_temp.pi_begin(p_world jsonb, p_tag text, p_elements jsonb) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE
  v_src jsonb:=p_world->'src'; v_actor uuid:=(p_world->'src'->>'actor')::uuid;
  v_msha text:=encode(extensions.digest('manifest-pi:'||p_tag,'sha256'),'hex');
  v_psha text:=encode(extensions.digest('preview-pi:'||p_tag,'sha256'),'hex'); v_auth uuid; v_batch uuid;
BEGIN
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  PERFORM set_config('role','service_role',true);
  v_auth:=public.red_authorize_reimport(v_msha,v_psha,
    jsonb_build_object('database_name',current_database(),'system_identifier',(pg_control_system()).system_identifier::text)::text,
    (v_src->>'source')::bigint,'fixture-pub-a',v_src->>'profile_sha256',
    jsonb_build_object('person_creates',0,'source_evidence',0,'publication_identities',(SELECT count(*) FROM jsonb_object_keys(p_elements))),
    p_elements,gen_random_uuid(),clock_timestamp()+interval '10 minutes');
  PERFORM set_config('role','authenticated',true);
  v_batch:=public.red_begin_reimport(v_auth,v_msha,v_psha);
  RESET role;
  RETURN v_batch;
EXCEPTION WHEN OTHERS THEN RESET role; RAISE;
END $$;

-- {element: payload} for et array af payloads.
CREATE OR REPLACE FUNCTION pg_temp.pi_elements(p_payloads jsonb) RETURNS jsonb LANGUAGE sql AS $$
  SELECT coalesce(jsonb_object_agg(pg_temp.pi_el(p),p),'{}'::jsonb) FROM jsonb_array_elements(p_payloads) p
$$;

CREATE OR REPLACE FUNCTION pg_temp.pi_apply(p_world jsonb, p_batch uuid, p_element text, p_payload jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_result jsonb;
BEGIN
  PERFORM set_config('request.jwt.claim.sub',p_world->'src'->>'actor',true);
  PERFORM set_config('role','authenticated',true);
  v_result:=public.red_apply_reimport_publication_identity(p_batch,p_element,p_payload);
  RESET role;
  RETURN v_result;
EXCEPTION WHEN OTHERS THEN RESET role; RAISE;
END $$;

CREATE OR REPLACE FUNCTION pg_temp.pi_finalize(p_world jsonb, p_batch uuid) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_result jsonb;
BEGIN
  PERFORM set_config('request.jwt.claim.sub',p_world->'src'->>'actor',true);
  PERFORM set_config('role','authenticated',true);
  v_result:=public.red_finalize_reimport(p_batch);
  RESET role;
  RETURN v_result;
EXCEPTION WHEN OTHERS THEN RESET role; RAISE;
END $$;
