-- Trin 5b 2b-ii runde 2 (spec §17.7): relation_persona profil v3 og v3-input. Opdigtede navne.
\set ON_ERROR_STOP on
BEGIN;
\ir fixtures/relation-5b.sql
\ir fixtures/relation-2a.sql
DO $v3_title$
BEGIN
  IF NOT private.relation_name_has_title('Ida komtesse Dal') OR NOT private.relation_name_has_title('Ida Rigsgrevinde Dal')
     OR NOT private.relation_name_has_title('Ida lensbaronesse Dal') OR private.relation_name_has_title('Eva von und zu Fik')
     OR private.relation_name_has_title('Ida Grevskab') THEN
    RAISE EXCEPTION 'V3_TEST_FAILED: titeltjek';
  END IF;
  RAISE NOTICE 'OK: titelliste';
END $v3_title$;

DO $v3_writer$
DECLARE v_actor uuid:='11000000-0000-0000-0000-00000005b3a1'; s jsonb; p jsonb; c jsonb; v_clause uuid; v_in jsonb; e jsonb;
  v_text text:='Gift 1890 med Ida komtesse Dal, f. 1801.'; sp uuid; v_ev jsonb;
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  INSERT INTO person(id,levende,privat,status) VALUES (-5341,false,false,'5b'),(-5342,false,false,'5b');
  s:=pg_temp.f5b_source(-5341);
  p:=pg_temp.f5b_post(-5341,s,'II-41','Anna Alfa. '||v_text,ARRAY['Anna Alfa.',v_text],-5341,v_actor);
  PERFORM pg_temp.f2a_event_for_state((p->>'principal')::uuid);
  v_clause:=(p->'clauses'->>1)::uuid;
  c:=pg_temp.f5b_claim(-5341,s,'relation.marriage',v_clause,'Gift med Ida komtesse Dal');
  -- P-kandidat: en anden post, ægtefælle-persona afgjort new_person_needed uden deceased (som 2b-i's kø)
  p:=pg_temp.f5b_post(-5341,s,'II-42','Bent B. Gift 1314 med Gro von Hak.',ARRAY['Bent B.','Gift 1314 med Gro von Hak.'],-5342,v_actor);
  PERFORM pg_temp.f2a_event_for_state((p->>'principal')::uuid);
  sp:=pg_temp.f5b_spouse(-5341,s,p,pg_temp.f5b_claim(-5341,s,'relation.marriage',(p->'clauses'->>1)::uuid,'Gift 1314 med Gro von Hak.'),
        (p->'clauses'->>1)::uuid,'Gro von Hak',1);
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  SET LOCAL ROLE authenticated;
  PERFORM red_afgoer_source_persona(sp,0,'new_person_needed',NULL,'kø',NULL);
  RESET ROLE;
  v_in:=private.relation_persona_v3_input(-5341);
  IF v_in->>'contract'<>'relation-persona-v3-input' OR jsonb_array_length(v_in->'rows')<>1
     OR v_in#>>'{rows,0,post_text}'<>'Anna Alfa. '||v_text OR jsonb_array_length(v_in->'redecide_rows')<>1
     OR v_in#>>'{redecide_rows,0,source_persona_id}'<>sp::text OR (v_in#>>'{redecide_rows,0,identity_version}')::int<>1
     OR v_in#>>'{redecide_rows,0,clause_text}'<>'Gift 1314 med Gro von Hak.' OR v_in#>>'{redecide_rows,0,name_text}'<>'Gro von Hak'
     OR (v_in#>>'{redecide_rows,0,clause_is_current}')::boolean IS NOT TRUE OR v_in#>>'{redecide_rows,0,previous,basis}'<>'web_detail'
     OR (v_in#>>'{redecide_rows,0,principal_person_id}')::bigint<>-5342 THEN
    RAISE EXCEPTION 'V3_TEST_FAILED: v3-input %',v_in;
  END IF;
  e:=jsonb_build_object('birth_raw',NULL,'clause_observation_id',v_clause,'clause_set_seq',1,
    'clause_set_sha256',private.clause_set_sha256((SELECT parent_observation_id FROM private.source_observation WHERE id=v_clause),1),
    'death_raw',NULL,'interpretation_key',c->>'key','interpretation_version',1,'marriage_ordinal',1,
    'name_from',14,'name_to',30,'post_offset',(SELECT post_char_from FROM private.source_observation WHERE id=v_clause),
    'predicate','relation.marriage','profile','relation-persona-2018-20-v3','span_from',0,'span_to',30);
  BEGIN   -- v3 uden proveniensnøgler afvises
    PERFORM pg_temp.f5b_write(-5341,v_actor,jsonb_build_object('relation-persona:'||(c->>'key'),e));
    RAISE EXCEPTION 'V3_TEST_FAILED: v3 uden name_basis godtaget';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM NOT LIKE '%RELATION_PERSONA_INVALID%' THEN RAISE; END IF; END;
  BEGIN   -- ukendt name_basis afvises
    PERFORM pg_temp.f5b_write(-5341,v_actor,jsonb_build_object('relation-persona:'||(c->>'key'),
      e||'{"name_basis":"model","sheet_line":1}'||jsonb_build_object('sheet_sha256',repeat('b',64))));
    RAISE EXCEPTION 'V3_TEST_FAILED: name_basis model godtaget';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM NOT LIKE '%RELATION_PERSONA_INVALID%' THEN RAISE; END IF; END;
  e:=e||'{"name_basis":"sheet","sheet_line":1}'||jsonb_build_object('sheet_sha256',repeat('b',64));
  PERFORM pg_temp.f5b_write(-5341,v_actor,jsonb_build_object('relation-persona:'||(c->>'key'),e));
  SELECT payload INTO v_ev FROM private.reimport_event WHERE element_id='relation-persona:'||(c->>'key');
  IF v_ev->>'sheet_sha256'<>repeat('b',64) OR v_ev->>'name_basis'<>'sheet' OR (v_ev->>'sheet_line')::int<>1 THEN
    RAISE EXCEPTION 'V3_TEST_FAILED: proveniens i hændelsen %',v_ev;
  END IF;
  IF (SELECT sm.verbatim_text FROM private.interpretation_party_current pc
        JOIN private.source_persona_mention spm ON spm.persona_id=pc.source_persona_id AND spm.mention_role='spouse'
        JOIN private.source_mention sm ON sm.id=spm.mention_id
       WHERE pc.interpretation_key=(c->>'key')::uuid AND pc.party_role='spouse') IS DISTINCT FROM 'Ida komtesse Dal' THEN
    RAISE EXCEPTION 'V3_TEST_FAILED: ægtefælle-mention';
  END IF;
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  RAISE NOTICE 'OK: relation_persona v3 (proveniens, afvisninger, v3-input)';
END $v3_writer$;
ROLLBACK;
