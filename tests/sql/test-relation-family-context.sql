-- Trin 5b, Task 4: familiekontekst og family_context_sha256 på kandidatrækken.
\set ON_ERROR_STOP on
BEGIN;
\ir fixtures/relation-5b.sql
DO $relation_family_context$
DECLARE
  v_actor uuid:='11000000-0000-0000-0000-00000005b401';
  s jsonb; p jsonb; c jsonb; v_sp uuid; v_fam bigint; ctx jsonb; v_in jsonb; v_run uuid; v_hash text;
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  INSERT INTO person(id,levende,privat,status,visning_navn) VALUES (-5401,false,false,'5b','Anna Alfa'),(-5402,false,false,'5b','Bo Beta'),
    (-5403,false,false,'5b','Bo Beta');   -- -5403 er en samme_som-dublet af ægtefællen
  s:=pg_temp.f5b_source(-5401);
  p:=pg_temp.f5b_post(-5401,s,'IV-1','Anna Alfa. g. m. Bo Beta, f. 1801.',ARRAY['Anna Alfa.','g. m. Bo Beta, f. 1801.'],-5401,v_actor);
  c:=pg_temp.f5b_claim(-5401,s,'relation.marriage',(p->'clauses'->>1)::uuid,'g. m. Bo Beta, f. 1801.');
  v_sp:=pg_temp.f5b_spouse(-5401,s,p,c,(p->'clauses'->>1)::uuid,'Bo Beta',1);
  v_fam:=pg_temp.f5b_family(-5401,-5402,1);
  INSERT INTO relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle) VALUES ('person',-5402,'person',-5403,'samme_som');

  ctx:=private.persona_family_context(v_sp);
  IF ctx->>'principal_person_id'<>'-5401' OR (ctx->>'marriage_claims_in_post')::int<>1 OR (ctx->>'marriage_ordinal')::int<>1
     OR ctx->'families'->0->'partners'<>'[-5402]'::jsonb OR (ctx->'families'->0->>'family_id')::bigint<>v_fam THEN
    RAISE EXCEPTION 'FAMILY_CONTEXT_TEST_FAILED: %',ctx;
  END IF;
  IF private.persona_family_context((p->>'principal')::uuid) IS NOT NULL THEN
    RAISE EXCEPTION 'FAMILY_CONTEXT_TEST_FAILED: hovedpersonen fik kontekst';
  END IF;

  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  SET LOCAL ROLE authenticated;
  v_in:=red_identity_candidate_input(-5401,'{"mode":"undecided"}');
  IF jsonb_array_length(v_in->'input'->'personas')<>1
     OR v_in->'input'->'personas'->0->'family_context' IS NULL
     OR v_in->'input'->'same_as'<>'[[-5402,-5403]]'::jsonb THEN
    RAISE EXCEPTION 'FAMILY_CONTEXT_TEST_FAILED: input %',v_in->'input'->'same_as';
  END IF;
  v_run:=red_record_identity_candidates(jsonb_build_object('source_id',-5401,'generator_version','t','config','{}'::jsonb,
    'input_spec','{"mode":"undecided"}'::jsonb,'input_sha256',v_in->>'input_sha256'),
    jsonb_build_array(jsonb_build_object('source_persona_id',v_sp,'candidate_person_id',-5402,'rank',1,'score',0.95,'tier','auto',
      'basis','{"signals":["name","family_partner"]}'::jsonb)));
  RESET ROLE;
  SELECT family_context_sha256 INTO v_hash FROM private.source_persona_identity_candidate WHERE run_id=v_run;
  IF v_hash IS DISTINCT FROM private.reimport_canonical_json_sha256(ctx) THEN
    RAISE EXCEPTION 'FAMILY_CONTEXT_TEST_FAILED: hash på kandidatrækken';
  END IF;
  RAISE NOTICE 'OK: familiekontekst, input med same_as og serverberegnet family_context_sha256';
END $relation_family_context$;
ROLLBACK;
