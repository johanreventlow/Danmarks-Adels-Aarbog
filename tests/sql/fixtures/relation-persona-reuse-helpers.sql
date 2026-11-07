-- Trin 6c-3a: delte hjælpere til relation_persona-writeren i testene for genbrug af ægtefælle-persona
-- (test-relation-persona-reuse.sql) og afstemningskvitteringen (test-text-revision-reconciliation.sql). Bygger på
-- fixtures/relation-5b.sql (f5b_profile, f5b_batch), som indlæses først. Kaldes som ejer. Alt er syntetisk.

-- Payload til relation_persona for en ægteskabspåstand, hvis klausul indeholder raw; klausulsættet læses af klausulen
-- (f5b_payload antager sæt 1), ægteskabsnummeret er serverens; p_birth er ægtefællens fødselsår (eller NULL).
CREATE OR REPLACE FUNCTION pg_temp.t6_payload(p_clause uuid,p_key text,p_raw text,p_name text,p_birth text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_co private.source_observation%ROWTYPE; v_from int;
BEGIN
  SELECT * INTO v_co FROM private.source_observation WHERE id=p_clause;
  v_from:=strpos(v_co.verbatim_text,p_raw)-1;
  IF v_from<0 THEN RAISE EXCEPTION 'T6_RAW_NOT_IN_CLAUSE'; END IF;
  RETURN jsonb_build_object('birth_raw',p_birth,'clause_observation_id',p_clause,'clause_set_seq',coalesce(v_co.clause_set_seq,1),
    'clause_set_sha256',private.clause_set_sha256(v_co.parent_observation_id,coalesce(v_co.clause_set_seq,1)),'death_raw',NULL,
    'interpretation_key',p_key,'interpretation_version',1,
    'marriage_ordinal',(SELECT o.marriage_ordinal FROM private.relation_marriage_ordinals(v_co.occurrence_id) o
                         WHERE o.interpretation_key=p_key::uuid),
    'name_from',v_from+strpos(p_raw,p_name)-1,'name_to',v_from+strpos(p_raw,p_name)-1+char_length(p_name),
    'post_offset',v_co.post_char_from+v_from,'predicate','relation.marriage','profile','relation-persona-2018-20-v1',
    'span_from',v_from,'span_to',v_from+char_length(p_raw));
END $$;

-- Autoriserer, åbner og anvender elementerne (ingen finalize). Kaldes som ejer.
CREATE OR REPLACE FUNCTION pg_temp.t6_apply(p_source bigint,p_actor uuid,p_elements jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE prof jsonb; b jsonb; e record;
BEGIN
  SELECT jsonb_build_object('profile_id',profile_id,'profile_sha256',profile_sha256) INTO prof
    FROM private.reimport_writer_profile WHERE source_id=p_source AND profile_id='relation-5b';
  IF prof IS NULL THEN prof:=pg_temp.f5b_profile(p_source); END IF;
  b:=pg_temp.f5b_batch(p_source,p_actor,prof,p_elements);
  SET LOCAL ROLE authenticated;
  FOR e IN SELECT * FROM jsonb_each(p_elements) LOOP
    PERFORM public.red_apply_reimport_relation_persona((b->>'batch')::uuid,e.key,e.value);
  END LOOP;
  RESET ROLE;
  RETURN b;
END $$;

-- Finalize og batch-resultatet som authenticated redaktion.
CREATE OR REPLACE FUNCTION pg_temp.t6_finalize(b jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE r jsonb;
BEGIN
  SET LOCAL ROLE authenticated;
  PERFORM public.red_finalize_reimport((b->>'batch')::uuid);
  r:=public.red_reimport_batch_result((b->>'auth')::uuid,(b->>'batch')::uuid);
  RESET ROLE;
  RETURN r;
END $$;

-- Ét element: anvend og finalisér; returnerer batch, kvittering og resultatkort.
CREATE OR REPLACE FUNCTION pg_temp.t6_write(p_source bigint,p_actor uuid,p_payload jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE b jsonb; v_el text:='relation-persona:'||(p_payload->>'interpretation_key'); r jsonb;
BEGIN
  b:=pg_temp.t6_apply(p_source,p_actor,jsonb_build_object(v_el,p_payload));
  r:=pg_temp.t6_finalize(b);
  RETURN b||jsonb_build_object('result',r,'receipt',
    (SELECT e.payload->'result_receipt' FROM private.reimport_event e
      WHERE e.batch_id=(b->>'batch')::uuid AND e.operation='relation_persona' AND e.element_id=v_el));
END $$;

-- Ægtefællepersonaen som gældende part på nøglen.
CREATE OR REPLACE FUNCTION pg_temp.t6_spouse(p_key text) RETURNS uuid LANGUAGE sql AS $$
  SELECT source_persona_id FROM private.interpretation_party_current WHERE interpretation_key=p_key::uuid AND party_role='spouse'
$$;
