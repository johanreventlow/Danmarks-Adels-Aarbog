-- Trin 5b 2b-i: fixtures oven på relation-5b.sql og relation-2a.sql. Kaldes som ejer.
-- Et ægteskab, hvor ægtefællen er uafgjort (ingen identitetshændelse): hovedpersonens post og identitet,
-- påstanden med ægtefælle-persona og (valgfrit) en kanonisk familie med p_principal og p_spouse som partnere.
CREATE OR REPLACE FUNCTION pg_temp.f2bi_open_marriage(p_source bigint,p_src jsonb,p_key text,p_principal bigint,p_spouse bigint,
  p_actor uuid,p_bookord int DEFAULT 1,p_famord int DEFAULT 1,p_make_family boolean DEFAULT true) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE p jsonb; c jsonb; v_persona uuid; v_fam bigint;
BEGIN
  p:=pg_temp.f5b_post(p_source,p_src,p_key,'Anna Alfa. Gift med Bo Beta.',ARRAY['Anna Alfa.','Gift med Bo Beta.'],p_principal,p_actor);
  PERFORM pg_temp.f2a_event_for_state((p->>'principal')::uuid);
  c:=pg_temp.f5b_claim(p_source,p_src,'relation.marriage',(p->'clauses'->>1)::uuid,'Gift med Bo Beta.');
  v_persona:=pg_temp.f5b_spouse(p_source,p_src,p,c,(p->'clauses'->>1)::uuid,'Bo Beta',p_bookord);
  IF p_make_family THEN v_fam:=pg_temp.f5b_family(p_principal,p_spouse,p_famord); END IF;
  RETURN jsonb_build_object('post',p,'claim',c,'spouse_persona',v_persona,'family',v_fam);
END $$;

-- Én kandidatkørsel (den nyeste for kilden) med rækkerne [{persona, person, rank}].
CREATE OR REPLACE FUNCTION pg_temp.f2bi_candidates(p_source bigint,p_actor uuid,p_rows jsonb) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_run uuid;
BEGIN
  INSERT INTO private.source_persona_identity_candidate_run(source_id,generator_version,config,config_sha256,input_spec,input_sha256,
    candidates_sha256,persona_count,candidate_count,created_by,created_by_name)
  VALUES (p_source,'t','{}',repeat('a',64),'{"mode":"undecided"}',encode(sha256(convert_to(p_rows::text,'UTF8')),'hex'),repeat('c',64),
          (SELECT count(DISTINCT r->>'persona') FROM jsonb_array_elements(p_rows) r),jsonb_array_length(p_rows),p_actor,'t')
  RETURNING id INTO v_run;
  INSERT INTO private.source_persona_identity_candidate(run_id,source_persona_id,candidate_person_id,rank,score,tier,basis)
  SELECT v_run,(r->>'persona')::uuid,(r->>'person')::bigint,(r->>'rank')::int,0.9-0.1*(r->>'rank')::int,'review','{"signals":["name"]}'
    FROM jsonb_array_elements(p_rows) r;
  RETURN v_run;
END $$;
