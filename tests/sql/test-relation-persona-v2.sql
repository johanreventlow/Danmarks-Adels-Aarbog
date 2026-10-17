-- Trin 5b 2b-ii (#151, spec §5.2 og errata §15.1): ordnet ordvindue, relation_persona profil v2 og v2-input.
\set ON_ERROR_STOP on
BEGIN;
\ir fixtures/relation-5b.sql
\ir fixtures/relation-2a.sql
DO $windows$
BEGIN
  IF (SELECT array_agg(ARRAY[w_from,w_to]) FROM private.relation_ordered_windows('Gift 1. gang 1890 med Bo Beta, f. 1801.','gift med Bo Beta'))
     <> ARRAY[ARRAY[0,29]] THEN RAISE EXCEPTION 'V2_TEST_FAILED: enkelt vindue'; END IF;
  IF (SELECT count(*) FROM private.relation_ordered_windows('Gift med Åse Ø. Gift med Åse Ø.','gift med åse ø'))<>2 THEN
    RAISE EXCEPTION 'V2_TEST_FAILED: to vinduer (ikke entydigt)'; END IF;
  IF (SELECT count(*) FROM private.relation_ordered_windows('Gift med Bo.','gift med Cia'))<>0 THEN
    RAISE EXCEPTION 'V2_TEST_FAILED: intet vindue'; END IF;
  -- Review Focus 1: samme tekst som Python-testen test_window_matches_sql_fixture
  IF (SELECT array_agg(ARRAY[w_from,w_to]) FROM private.relation_ordered_windows('g. 2° m. Søren Ærø-Ødegård, f. 1850.','m. søren ødegård'))
     <> ARRAY[ARRAY[6,26]] THEN RAISE EXCEPTION 'V2_TEST_FAILED: danske bogstaver'; END IF;
  IF (SELECT array_agg(ARRAY[w_from,w_to]) FROM private.relation_ordered_windows('Gift 1975.','Gift 1975.')) <> ARRAY[ARRAY[0,9]] THEN
    RAISE EXCEPTION 'V2_TEST_FAILED: tal som ord'; END IF;
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;   -- udskudte identitetstjek må ikke skjules af ROLLBACK
  RAISE NOTICE 'OK: ordnede vinduer';
END $windows$;

DO $v2_writer$
DECLARE v_actor uuid:='11000000-0000-0000-0000-00000005b2b4'; s jsonb; p jsonb; c jsonb; v_clause uuid; v_in jsonb; e jsonb;
  v_text text:='Gift 1. gang 1890 med Bo Beta, f. 1801.';
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  INSERT INTO person(id,levende,privat,status) VALUES (-5241,false,false,'5b');
  s:=pg_temp.f5b_source(-5241);
  p:=pg_temp.f5b_post(-5241,s,'II-41','Anna Alfa. '||v_text,ARRAY['Anna Alfa.',v_text],-5241,v_actor);
  PERFORM pg_temp.f2a_event_for_state((p->>'principal')::uuid);
  v_clause:=(p->'clauses'->>1)::uuid;
  c:=pg_temp.f5b_claim(-5241,s,'relation.marriage',v_clause,'Gift med Bo Beta.');
  -- v2-input: én række uden persona, med hovedpersonen og (tomme) partnere
  v_in:=private.relation_persona_v2_input(-5241);
  IF v_in->>'contract'<>'relation-persona-v2-input' OR (v_in->>'deceased_cutoff_year')::int<>1906
     OR jsonb_array_length(v_in->'rows')<>1 OR (v_in#>>'{rows,0,principal_person_id}')::bigint<>-5241
     OR jsonb_typeof(v_in#>'{rows,0,principal_partners}')<>'array' THEN
    RAISE EXCEPTION 'V2_TEST_FAILED: v2-input %',v_in;
  END IF;
  e:=jsonb_build_object('birth_raw',NULL,'clause_observation_id',v_clause,'clause_set_seq',1,
    'clause_set_sha256',private.clause_set_sha256((p->>'helpost')::uuid,1),'death_raw',NULL,
    'interpretation_key',c->>'key','interpretation_version',1,'marriage_ordinal',1,
    'name_from',22,'name_to',29,'post_offset',(SELECT post_char_from FROM private.source_observation WHERE id=v_clause),
    'predicate','relation.marriage','profile','relation-persona-2018-20-v2','span_from',0,'span_to',29);
  -- negative: forkert vindue, og samme spænd under v1 (påstanden står ikke ordret)
  BEGIN
    PERFORM pg_temp.f5b_write(-5241,v_actor,jsonb_build_object('relation-persona:'||(c->>'key'),e||'{"span_to":30}'));
    RAISE EXCEPTION 'V2_TEST_FAILED: forkert vindue godtaget';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM NOT LIKE '%RELATION_PERSONA_SPAN_INVALID%' THEN RAISE; END IF; END;
  BEGIN
    PERFORM pg_temp.f5b_write(-5241,v_actor,jsonb_build_object('relation-persona:'||(c->>'key'),e||'{"profile":"relation-persona-2018-20-v1"}'));
    RAISE EXCEPTION 'V2_TEST_FAILED: v1 uden ordret påstand godtaget';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM NOT LIKE '%RELATION_PERSONA_SPAN_INVALID%' THEN RAISE; END IF; END;
  PERFORM pg_temp.f5b_write(-5241,v_actor,jsonb_build_object('relation-persona:'||(c->>'key'),e));
  IF (SELECT sm.verbatim_text FROM private.interpretation_party_current pc
        JOIN private.source_persona_mention spm ON spm.persona_id=pc.source_persona_id AND spm.mention_role='spouse'
        JOIN private.source_mention sm ON sm.id=spm.mention_id
       WHERE pc.interpretation_key=(c->>'key')::uuid AND pc.party_role='spouse') IS DISTINCT FROM 'Bo Beta' THEN
    RAISE EXCEPTION 'V2_TEST_FAILED: ægtefælle-mention';
  END IF;
  IF jsonb_array_length(private.relation_persona_v2_input(-5241)->'rows')<>0 THEN
    RAISE EXCEPTION 'V2_TEST_FAILED: skrevet påstand står stadig i v2-input';
  END IF;
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;   -- udskudte identitetstjek må ikke skjules af ROLLBACK
  RAISE NOTICE 'OK: relation_persona v2 (vindue, negative, input)';
END $v2_writer$;
ROLLBACK;
