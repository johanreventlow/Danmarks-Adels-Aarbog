-- Trin 5b 2b-i Task 6 (spec §6.2): partnerkontekst og årsag i webkøens detalje.
\set ON_ERROR_STOP on
BEGIN;
\ir fixtures/relation-5b.sql
\ir fixtures/relation-2a.sql
\ir fixtures/relation-2bi.sql
DO $spouse_review_context$
DECLARE v_actor uuid:='11000000-0000-0000-0000-0000002b0601'; s jsonb; nf jsonb; pc jsonb; np jsonb; dn jsonb; d jsonb; v_err text;
  cu jsonb; cc jsonb; v_cu uuid; v_m uuid;
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  INSERT INTO person(id,levende,privat,status,visning_navn) SELECT g,false,false,'2bi','P'||abs(g) FROM generate_series(-21640,-21601) g;
  s:=pg_temp.f5b_source(-21601);
  nf:=pg_temp.f2bi_open_marriage(-21601,s,'C-1',-21601,-21602,v_actor,1,1,false);   -- ingen familie
  pc:=pg_temp.f2bi_open_marriage(-21601,s,'C-2',-21603,-21604,v_actor,1,1);         -- kandidat 1 = partner
  np:=pg_temp.f2bi_open_marriage(-21601,s,'C-3',-21605,-21606,v_actor,1,2);         -- kandidat 1 ≠ partner
  dn:=pg_temp.f2bi_open_marriage(-21601,s,'C-4',-21607,-21608,v_actor,1,1);         -- afgøres unresolved
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  PERFORM pg_temp.f2bi_candidates(-21601,v_actor,jsonb_build_array(
    jsonb_build_object('persona',pc->>'spouse_persona','person',-21604,'rank',1),
    jsonb_build_object('persona',np->>'spouse_persona','person',-21620,'rank',1)));
  -- context_unavailable: en ægtefælle-persona, hvis påstand ingen hovedperson-part har ⇒ persona_family_context er NULL
  cu:=pg_temp.f5b_post(-21601,s,'C-5','Anna Alfa. Gift med Bo Beta.',ARRAY['Anna Alfa.','Gift med Bo Beta.'],-21609,v_actor);
  PERFORM pg_temp.f2a_event_for_state((cu->>'principal')::uuid);
  cc:=pg_temp.f5b_claim(-21601,s,'relation.marriage',(cu->'clauses'->>1)::uuid,'Gift med Bo Beta.');
  INSERT INTO private.source_persona(source_id,persona_key,created_run_id)
    VALUES (-21601,'C-5#rel-marriage-cu',(s->>'run')::uuid) RETURNING id INTO v_cu;
  INSERT INTO private.source_mention(observation_id,mention_kind,char_from,char_to,verbatim_text,created_run_id)
    VALUES ((cu->'clauses'->>1)::uuid,'person',9,16,'Bo Beta',(s->>'run')::uuid) RETURNING id INTO v_m;
  INSERT INTO private.source_persona_mention(persona_id,mention_id,mention_role,ordinal) VALUES (v_cu,v_m,'spouse',1);
  INSERT INTO private.interpretation_party(interpretation_key,party_role,version,source_persona_id,marriage_ordinal,post_offset,origin,origin_ref)
    VALUES ((cc->>'key')::uuid,'spouse',1,v_cu,1,9,'relation_persona',gen_random_uuid());
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  SET LOCAL ROLE authenticated;
  PERFORM red_afgoer_source_persona((dn->>'spouse_persona')::uuid,0,'unresolved',NULL,'test','{}');
  d:=red_source_persona_detail(v_cu);
  IF d->>'review_reason' IS DISTINCT FROM 'context_unavailable' OR d->'principal_partners'<>'[]'::jsonb THEN
    RAISE EXCEPTION 'SPOUSE_REVIEW_CONTEXT_TEST_FAILED: uden kontekst %', d; END IF;
  d:=red_source_persona_detail((nf->>'spouse_persona')::uuid);
  IF d->>'review_reason' IS DISTINCT FROM 'principal_no_family' OR d->'principal_partners'<>'[]'::jsonb THEN
    RAISE EXCEPTION 'SPOUSE_REVIEW_CONTEXT_TEST_FAILED: ingen familie %', d; END IF;
  d:=red_source_persona_detail((pc->>'spouse_persona')::uuid);
  IF d->>'review_reason' IS DISTINCT FROM 'partner_is_candidate' THEN RAISE EXCEPTION 'SPOUSE_REVIEW_CONTEXT_TEST_FAILED: kandidat %', d; END IF;
  d:=red_source_persona_detail((np->>'spouse_persona')::uuid);
  IF d->>'review_reason' IS DISTINCT FROM 'partner_not_candidate' OR jsonb_array_length(d->'principal_partners')<>1
     OR (d#>>'{principal_partners,0,person_id}')::bigint<>-21606 OR (d#>>'{principal_partners,0,family_id}')::bigint<>(np->>'family')::bigint
     OR (d#>>'{principal_partners,0,ordinal}')::int<>2 THEN
    RAISE EXCEPTION 'SPOUSE_REVIEW_CONTEXT_TEST_FAILED: ikke kandidat %', d; END IF;
  d:=red_source_persona_detail((dn->>'spouse_persona')::uuid);                       -- afgjort_null (Review Focus 5)
  IF d ? 'review_reason' IS NOT TRUE OR jsonb_typeof(d->'review_reason')<>'null' THEN RAISE EXCEPTION 'SPOUSE_REVIEW_CONTEXT_TEST_FAILED: afgjort %', d; END IF;
  d:=red_source_persona_detail((np->'post'->>'principal')::uuid);                    -- hovedperson-persona
  IF d->'principal_partners'<>'[]'::jsonb OR jsonb_typeof(d->'review_reason')<>'null' THEN RAISE EXCEPTION 'SPOUSE_REVIEW_CONTEXT_TEST_FAILED: hovedperson %', d; END IF;
  RESET ROLE;
  SET LOCAL ROLE anon;
  BEGIN
    PERFORM red_source_persona_detail((np->>'spouse_persona')::uuid);
    RAISE EXCEPTION 'SPOUSE_REVIEW_CONTEXT_TEST_FAILED: anon godtaget';
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT;
    IF v_err NOT LIKE 'EVIDENCE_ROLE_FORBIDDEN%' AND v_err NOT LIKE 'permission denied%' THEN RAISE; END IF;
  END;
  RESET ROLE;
  RAISE NOTICE 'OK: partnerkontekst og årsag';
END $spouse_review_context$;
ROLLBACK;
