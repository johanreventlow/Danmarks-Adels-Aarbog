-- Trin 5b, Task 2: relationsinput og writer-operationen relation_persona (contract v2).
\set ON_ERROR_STOP on
BEGIN;
\ir fixtures/relation-5b.sql

DO $relation_persona_writer$
DECLARE
  v_actor uuid:='11000000-0000-0000-0000-00000005b201';
  s jsonb; p jsonb; prof jsonb; cm jsonb; cm2 jsonb; cc jsonb; b jsonb; r jsonb; v_in jsonb; e jsonb; e2 jsonb; ec jsonb;
  v_clause uuid; v_text text; v_raw text:='g. m. Bo Beta, f. 1801, d. 1870.'; v_raw2 text:='g. 2° m. Cia Ceta.';
  v_state text;
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  INSERT INTO person(id,levende,privat,status) VALUES (-5201,false,false,'5b');
  s:=pg_temp.f5b_source(-5201);
  v_text:='Anna Alfa, f. 1800. '||v_raw||' '||v_raw2||' Datter Dora.';
  p:=pg_temp.f5b_post(-5201,s,'II-7',v_text,ARRAY['Anna Alfa, f. 1800.',v_raw||' '||v_raw2,'Datter Dora.'],-5201,v_actor);
  v_clause:=(p->'clauses'->>1)::uuid;
  cm:=pg_temp.f5b_claim(-5201,s,'relation.marriage',v_clause,v_raw);
  cm2:=pg_temp.f5b_claim(-5201,s,'relation.marriage',v_clause,v_raw2);
  cc:=pg_temp.f5b_claim(-5201,s,'relation.child',(p->'clauses'->>2)::uuid,'Datter Dora.');
  prof:=pg_temp.f5b_profile(-5201);

  -- input: tre påstande, serverens ægteskabsnummer 1 og 2 i tekstrækkefølge
  v_in:=private.relation_persona_input(-5201);
  IF jsonb_array_length(v_in)<>3 THEN RAISE EXCEPTION 'RELATION_WRITER_TEST_FAILED: input %',jsonb_array_length(v_in); END IF;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_in) x WHERE (x->>'principal_ok')::boolean IS DISTINCT FROM true) THEN
    RAISE EXCEPTION 'RELATION_WRITER_TEST_FAILED: principal_ok';
  END IF;
  IF (SELECT array_agg(o.marriage_ordinal ORDER BY o.post_offset) FROM private.relation_marriage_ordinals((p->>'occ')::uuid) o)<>ARRAY[1,2] THEN
    RAISE EXCEPTION 'RELATION_WRITER_TEST_FAILED: ægteskabsnumre';
  END IF;

  e:=jsonb_build_object('birth_raw','1801','clause_observation_id',v_clause,'clause_set_seq',1,
    'clause_set_sha256',private.clause_set_sha256((p->>'helpost')::uuid,1),'death_raw','1870',
    'interpretation_key',cm->>'key','interpretation_version',1,'marriage_ordinal',1,
    'name_from',6,'name_to',13,'post_offset',strpos(v_text,v_raw)-1,'predicate','relation.marriage',
    'profile','relation-persona-2018-20-v1','span_from',0,'span_to',char_length(v_raw));
  ec:=jsonb_build_object('birth_raw',NULL,'clause_observation_id',(p->'clauses'->>2)::uuid,'clause_set_seq',1,
    'clause_set_sha256',private.clause_set_sha256((p->>'helpost')::uuid,1),'death_raw',NULL,
    'interpretation_key',cc->>'key','interpretation_version',1,'marriage_ordinal',NULL,'name_from',NULL,'name_to',NULL,
    'post_offset',strpos(v_text,'Datter Dora.')-1,'predicate','relation.child','profile','relation-persona-2018-20-v1',
    'span_from',0,'span_to',char_length('Datter Dora.'));

  b:=pg_temp.f5b_batch(-5201,v_actor,prof,jsonb_build_object('relation-persona:'||(cm->>'key'),e,'relation-persona:'||(cc->>'key'),ec));
  SET LOCAL ROLE authenticated;
  -- ikke-autoriseret payload (ændret ordinal) afvises
  BEGIN
    PERFORM public.red_apply_reimport_relation_persona((b->>'batch')::uuid,'relation-persona:'||(cm->>'key'),e||'{"marriage_ordinal":2}');
    RAISE EXCEPTION 'RELATION_WRITER_TEST_FAILED: uautoriseret payload';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'REIMPORT_WRITER_ELEMENT_NOT_AUTHORIZED%' THEN RAISE; END IF;
  END;
  r:=public.red_apply_reimport_relation_persona((b->>'batch')::uuid,'relation-persona:'||(cm->>'key'),e);
  PERFORM public.red_apply_reimport_relation_persona((b->>'batch')::uuid,'relation-persona:'||(cc->>'key'),ec);
  PERFORM public.red_finalize_reimport((b->>'batch')::uuid);
  r:=public.red_reimport_batch_result((b->>'auth')::uuid,(b->>'batch')::uuid);
  RESET ROLE;
  IF r->'person_id_map' IS NULL OR jsonb_array_length(r->'relation_results')<>1
     OR r->'relation_results'->0->'derived_counts'<>'{"mentions":1,"parties":3,"spouse_personas":1,"year_interpretations":2}' THEN
    RAISE EXCEPTION 'RELATION_WRITER_TEST_FAILED: batch_result %',r;
  END IF;
  -- Idempotens (spec §5.2, Codex plan-r1 fund 3): samme payload igen → writer-rammens replay returnerer
  -- den finaliserede batch; intet nyt skrives.
  IF (pg_temp.f5b_batch(-5201,v_actor,prof,jsonb_build_object('relation-persona:'||(cm->>'key'),e,'relation-persona:'||(cc->>'key'),ec))->>'batch')
     IS DISTINCT FROM b->>'batch'
     OR (SELECT count(*) FROM private.source_persona WHERE source_id=-5201 AND persona_key LIKE '%#rel-marriage-%')<>1 THEN
    RAISE EXCEPTION 'RELATION_WRITER_TEST_FAILED: replay';
  END IF;
  -- persona, mention og parter
  IF NOT EXISTS (SELECT 1 FROM private.source_persona WHERE persona_key='II-7#rel-marriage-'||(strpos(v_text,v_raw)-1)||'-'||char_length(v_raw))
     OR (SELECT count(*) FROM private.interpretation_party_current WHERE interpretation_key IN ((cm->>'key')::uuid,(cc->>'key')::uuid))<>3 THEN
    RAISE EXCEPTION 'RELATION_WRITER_TEST_FAILED: rækker mangler';
  END IF;
  -- påstanden er nu ude af input; ny batch for samme påstand afvises
  IF jsonb_array_length(private.relation_persona_input(-5201))<>1 THEN RAISE EXCEPTION 'RELATION_WRITER_TEST_FAILED: input efter'; END IF;
  -- forkert ordinal for 2. ægteskab afvises af serveren
  -- 'g. 2° m. ' er 9 tegn: navnet ligger på (len(v_raw)+1)+9 .. +17 i klausulen; kun ordinal er forkert.
  e2:=e||jsonb_build_object('interpretation_key',cm2->>'key','marriage_ordinal',1,
     'name_from',char_length(v_raw)+1+9,'name_to',char_length(v_raw)+1+17,'birth_raw',NULL,'death_raw',NULL,
     'post_offset',strpos(v_text,v_raw2)-1,'span_from',char_length(v_raw)+1,'span_to',char_length(v_raw)+1+char_length(v_raw2));
  b:=pg_temp.f5b_batch(-5201,v_actor,prof,jsonb_build_object('relation-persona:'||(cm2->>'key'),e2));
  SET LOCAL ROLE authenticated;
  BEGIN
    PERFORM public.red_apply_reimport_relation_persona((b->>'batch')::uuid,'relation-persona:'||(cm2->>'key'),e2);
    RAISE EXCEPTION 'RELATION_WRITER_TEST_FAILED: forkert ordinal godtaget';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'REIMPORT_WRITER_RELATION_PERSONA_SPAN_INVALID%' THEN RAISE; END IF;
  END;
  RESET ROLE;
  RAISE NOTICE 'OK: input, serverens ægteskabsnummer, writer, receipt, finalize og resultatkort';
END $relation_persona_writer$;

-- Spændregler: ikke-ordret, tvetydigt og hovedperson uden accepteret identitet.
DO $relation_persona_negative$
DECLARE
  v_actor uuid:='11000000-0000-0000-0000-00000005b202';
  s jsonb; p jsonb; prof jsonb; c jsonb; b jsonb; e jsonb; v_text text:='Bent Bravo. g. m. Ea Echo. g. m. Ea Echo.';
  v_case text;
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  s:=pg_temp.f5b_source(-5202);
  p:=pg_temp.f5b_post(-5202,s,'III-1',v_text,ARRAY['Bent Bravo.','g. m. Ea Echo. g. m. Ea Echo.'],NULL,v_actor);
  c:=pg_temp.f5b_claim(-5202,s,'relation.marriage',(p->'clauses'->>1)::uuid,'g. m. Ea Echo.');
  prof:=pg_temp.f5b_profile(-5202);
  -- hovedpersonen har ingen accepteret identitet: inputtet siger det, så udtrækket kan parkere
  IF (private.relation_persona_input(-5202)->0->>'principal_ok')::boolean IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'RELATION_WRITER_TEST_FAILED: principal_ok';
  END IF;
  e:=jsonb_build_object('birth_raw',NULL,'clause_observation_id',p->'clauses'->>1,'clause_set_seq',1,
    'clause_set_sha256',private.clause_set_sha256((p->>'helpost')::uuid,1),'death_raw',NULL,
    'interpretation_key',c->>'key','interpretation_version',1,'marriage_ordinal',1,'name_from',5,'name_to',13,
    'post_offset',12,'predicate','relation.marriage','profile','relation-persona-2018-20-v1','span_from',0,'span_to',14);
  b:=pg_temp.f5b_batch(-5202,v_actor,prof,jsonb_build_object('relation-persona:'||(c->>'key'),e));
  SET LOCAL ROLE authenticated;
  BEGIN
    PERFORM public.red_apply_reimport_relation_persona((b->>'batch')::uuid,'relation-persona:'||(c->>'key'),e);
    RAISE EXCEPTION 'RELATION_WRITER_TEST_FAILED: tvetydigt spænd godtaget';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'REIMPORT_WRITER_RELATION_PERSONA_SPAN_INVALID%' THEN RAISE; END IF;
  END;
  RESET ROLE;
  RAISE NOTICE 'OK: tvetydigt spænd afvises';
END $relation_persona_negative$;
ROLLBACK;
