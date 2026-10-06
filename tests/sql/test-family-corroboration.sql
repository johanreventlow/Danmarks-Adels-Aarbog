-- Trin 5b, Task 8: family_corroboration — kernens egne efterprøvelser og bekræftelses-RPC'en.
\set ON_ERROR_STOP on
BEGIN;
\ir fixtures/relation-5b.sql

DO $family_corroboration$
DECLARE
  v_actor uuid:='11000000-0000-0000-0000-00000005b801';
  s jsonb; p jsonb; c jsonb; c2 jsonb; v_el jsonb:='{}'; i int; v_in jsonb; v_run uuid; v_cands jsonb:='[]'; v_ctl uuid;
  v_smp jsonb; v_pos text; v_set text; v_n int; v_sp uuid; v_fam bigint; v_defect jsonb:='{}'; v_name text; v_err text;
  v_cand uuid; v_ev jsonb; v_good uuid[]:='{}';
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  s:=pg_temp.f5b_source(-5801);
  -- 11 gode poster: én ægteskabspåstand, én familie (ordinal 1) med præcis én partner.
  FOR i IN 1..11 LOOP
    INSERT INTO person(id,levende,privat,status) VALUES (-58000-i*2,false,false,'5b'),(-58000-i*2-1,false,false,'5b');
    v_name:='Mage '||i;
    p:=pg_temp.f5b_post(-5801,s,'G-'||lpad(i::text,2,'0'),'Hoved '||i||'. g. m. '||v_name||'.',
       ARRAY['Hoved '||i||'.','g. m. '||v_name||'.'],-58000-i*2,v_actor);
    c:=pg_temp.f5b_claim(-5801,s,'relation.marriage',(p->'clauses'->>1)::uuid,'g. m. '||v_name||'.');
    PERFORM pg_temp.f5b_family(-58000-i*2,-58000-i*2-1,1);
    v_el:=v_el||jsonb_build_object('relation-persona:'||(c->>'key'),
      pg_temp.f5b_payload(p,c,(p->'clauses'->>1)::uuid,'g. m. '||v_name||'.',v_name));
  END LOOP;
  -- Defekter (Review Focus 1-3 + struktur): hver sin post.
  INSERT INTO person(id,levende,privat,status) VALUES
    (-58101,false,false,'5b'),(-58102,false,false,'5b'),   -- D1 hovedperson skifter identitet
    (-58111,false,false,'5b'),(-58112,false,false,'5b'),   -- D2 count_mismatch m. parkeret påstand
    (-58121,false,false,'5b'),(-58122,false,false,'5b'),   -- D3 to ægteskaber, samme partner
    (-58131,false,false,'5b'),(-58132,false,false,'5b'),   -- D4 omstridt
    (-58141,false,false,'5b'),(-58142,false,false,'5b'),(-58143,false,false,'5b'), -- D5 NULL-ordinal, to familier
    (-58151,false,false,'5b'),(-58152,false,false,'5b');   -- D6 familiekontekst ændret efter kørslen
  p:=pg_temp.f5b_post(-5801,s,'D-1','Hoved D1. g. m. Dea.',ARRAY['Hoved D1.','g. m. Dea.'],-58101,v_actor);
  c:=pg_temp.f5b_claim(-5801,s,'relation.marriage',(p->'clauses'->>1)::uuid,'g. m. Dea.');
  PERFORM pg_temp.f5b_family(-58101,-58102,1);
  v_el:=v_el||jsonb_build_object('relation-persona:'||(c->>'key'),pg_temp.f5b_payload(p,c,(p->'clauses'->>1)::uuid,'g. m. Dea.','Dea'));
  v_defect:=v_defect||jsonb_build_object('D1',jsonb_build_object('claim',c->>'key','post',p,'partner',-58102));
  p:=pg_temp.f5b_post(-5801,s,'D-2','Hoved D2. g. m. Deb. Gift igen m. ??',ARRAY['Hoved D2.','g. m. Deb.','Gift igen m. ??'],-58111,v_actor);
  c:=pg_temp.f5b_claim(-5801,s,'relation.marriage',(p->'clauses'->>1)::uuid,'g. m. Deb.');
  PERFORM pg_temp.f5b_claim(-5801,s,'relation.marriage',(p->'clauses'->>2)::uuid,'Gift igen m. ??');   -- parkeres (intet navn)
  PERFORM pg_temp.f5b_family(-58111,-58112,1);
  v_el:=v_el||jsonb_build_object('relation-persona:'||(c->>'key'),pg_temp.f5b_payload(p,c,(p->'clauses'->>1)::uuid,'g. m. Deb.','Deb'));
  v_defect:=v_defect||jsonb_build_object('D2',jsonb_build_object('claim',c->>'key','partner',-58112));
  p:=pg_temp.f5b_post(-5801,s,'D-3','Hoved D3. g. 1° m. Dec. g. 2° m. Dec.',ARRAY['Hoved D3.','g. 1° m. Dec.','g. 2° m. Dec.'],-58121,v_actor);
  c:=pg_temp.f5b_claim(-5801,s,'relation.marriage',(p->'clauses'->>1)::uuid,'g. 1° m. Dec.');
  c2:=pg_temp.f5b_claim(-5801,s,'relation.marriage',(p->'clauses'->>2)::uuid,'g. 2° m. Dec.');
  PERFORM pg_temp.f5b_family(-58121,-58122,1); PERFORM pg_temp.f5b_family(-58121,-58122,2);
  v_el:=v_el||jsonb_build_object('relation-persona:'||(c->>'key'),pg_temp.f5b_payload(p,c,(p->'clauses'->>1)::uuid,'g. 1° m. Dec.','Dec'),
                                 'relation-persona:'||(c2->>'key'),pg_temp.f5b_payload(p,c2,(p->'clauses'->>2)::uuid,'g. 2° m. Dec.','Dec'));
  v_defect:=v_defect||jsonb_build_object('D3a',jsonb_build_object('claim',c->>'key','partner',-58122),
                                         'D3b',jsonb_build_object('claim',c2->>'key','partner',-58122));
  p:=pg_temp.f5b_post(-5801,s,'D-4','Hoved D4. g. m. Ded.',ARRAY['Hoved D4.','g. m. Ded.'],-58131,v_actor);
  c:=pg_temp.f5b_claim(-5801,s,'relation.marriage',(p->'clauses'->>1)::uuid,'g. m. Ded.');
  v_fam:=pg_temp.f5b_family(-58131,-58132,1); UPDATE family_member SET konfidens='omstridt' WHERE family_id=v_fam AND person_id=-58132;
  v_el:=v_el||jsonb_build_object('relation-persona:'||(c->>'key'),pg_temp.f5b_payload(p,c,(p->'clauses'->>1)::uuid,'g. m. Ded.','Ded'));
  v_defect:=v_defect||jsonb_build_object('D4',jsonb_build_object('claim',c->>'key','partner',-58132));
  p:=pg_temp.f5b_post(-5801,s,'D-5','Hoved D5. g. m. Dee. g. m. Def.',ARRAY['Hoved D5.','g. m. Dee.','g. m. Def.'],-58141,v_actor);
  c:=pg_temp.f5b_claim(-5801,s,'relation.marriage',(p->'clauses'->>1)::uuid,'g. m. Dee.');
  PERFORM pg_temp.f5b_claim(-5801,s,'relation.marriage',(p->'clauses'->>2)::uuid,'g. m. Def.');
  PERFORM pg_temp.f5b_family(-58141,-58142,NULL); PERFORM pg_temp.f5b_family(-58141,-58143,2);
  v_el:=v_el||jsonb_build_object('relation-persona:'||(c->>'key'),pg_temp.f5b_payload(p,c,(p->'clauses'->>1)::uuid,'g. m. Dee.','Dee'));
  v_defect:=v_defect||jsonb_build_object('D5',jsonb_build_object('claim',c->>'key','partner',-58142));
  p:=pg_temp.f5b_post(-5801,s,'D-6','Hoved D6. g. m. Deg.',ARRAY['Hoved D6.','g. m. Deg.'],-58151,v_actor);
  c:=pg_temp.f5b_claim(-5801,s,'relation.marriage',(p->'clauses'->>1)::uuid,'g. m. Deg.');
  v_fam:=pg_temp.f5b_family(-58151,-58152,1);
  v_el:=v_el||jsonb_build_object('relation-persona:'||(c->>'key'),pg_temp.f5b_payload(p,c,(p->'clauses'->>1)::uuid,'g. m. Deg.','Deg'));
  v_defect:=v_defect||jsonb_build_object('D6',jsonb_build_object('claim',c->>'key','partner',-58152,'family',v_fam));

  PERFORM pg_temp.f5b_write(-5801,v_actor,v_el);

  -- Kandidatkørsel: de 11 gode er egnede; defekterne markeres ikke-egnede (uden for populationen)
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  SET LOCAL ROLE authenticated;
  v_in:=red_identity_candidate_input(-5801,'{"mode":"undecided"}');
  RESET ROLE;
  SELECT coalesce(jsonb_agg(jsonb_build_object('source_persona_id',pc.source_persona_id,'candidate_person_id',
           (SELECT o.person_id FROM family_member o JOIN family_member me ON me.family_id=o.family_id AND me.rolle='partner'
              AND me.person_id=(private.persona_family_context(pc.source_persona_id)->>'principal_person_id')::bigint
             WHERE o.rolle='partner' AND o.person_id<>me.person_id ORDER BY o.family_id LIMIT 1),
           'rank',1,'score',0.95,'tier','auto',
           'basis',jsonb_build_object('signals','["name","family_partner"]'::jsonb,
             'corroboration_eligible',(SELECT sr.record_key LIKE 'G-%' FROM private.interpretation_observation io
               JOIN private.interpretation_current ic ON ic.id=io.interpretation_id JOIN private.source_observation o ON o.id=io.observation_id
               JOIN private.source_record_anchor_current ac ON ac.occurrence_id=o.occurrence_id AND ac.decision_status='accepted'
               JOIN private.source_record sr ON sr.id=ac.source_record_id WHERE ic.interpretation_key=pc.interpretation_key LIMIT 1)))),'[]')
    INTO v_cands FROM private.interpretation_party_current pc JOIN private.source_persona sp ON sp.id=pc.source_persona_id
   WHERE pc.party_role='spouse' AND sp.source_id=-5801;
  SET LOCAL ROLE authenticated;
  v_run:=red_record_identity_candidates(jsonb_build_object('source_id',-5801,'generator_version','t','config','{}'::jsonb,
    'input_spec','{"mode":"undecided"}'::jsonb,'input_sha256',v_in->>'input_sha256'),v_cands);
  v_ctl:=red_register_identity_control_run(v_run);
  -- ikke bestået endnu → RPC'en afviser (not_ready) uden at skrive
  BEGIN
    PERFORM red_corroborate_family_identities(v_ctl,repeat('0',64));
    RAISE EXCEPTION 'CORROBORATION_TEST_FAILED: not_ready godtaget';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'IDENTITY_CONTROL_NOT_PASSED%' THEN RAISE; END IF;
  END;
  v_smp:=red_identity_control_sample(v_ctl);
  IF jsonb_array_length(v_smp->'samples')<>10 THEN RAISE EXCEPTION 'CORROBORATION_TEST_FAILED: stikprøve %',jsonb_array_length(v_smp->'samples'); END IF;
  PERFORM red_seal_identity_control_run(v_ctl,repeat('a',64),repeat('b',64));
  FOR i IN 0..9 LOOP
    RESET ROLE;   -- opslaget i private kræver ejer; afgørelsen nedenfor sker som redaktør
    SELECT key INTO v_pos FROM jsonb_each_text(v_smp->'samples'->i->'mapping') m
     WHERE m.value=(SELECT c3.id::text FROM private.source_persona_identity_candidate c3 WHERE c3.run_id=v_run AND c3.rank=1
                      AND c3.source_persona_id=(v_smp->'samples'->i->>'source_persona_id')::uuid);
    SET LOCAL ROLE authenticated;
    PERFORM red_afgoer_source_persona((v_smp->'samples'->i->>'source_persona_id')::uuid,0,'same',NULL,'stikprøve',
      jsonb_build_object('basis','human_sheet','sheet_sha256',repeat('a',64),'rows_sha256',repeat('b',64),'line',i+1,
        'control_run_id',v_ctl,'display_position',v_pos::int));
  END LOOP;
  IF red_evaluate_identity_control_run(v_ctl)<>'passed' THEN RAISE EXCEPTION 'CORROBORATION_TEST_FAILED: ikke bestået'; END IF;

  -- mængde-drift afvises uden skrivning
  BEGIN
    PERFORM red_corroborate_family_identities(v_ctl,repeat('0',64));
    RAISE EXCEPTION 'CORROBORATION_TEST_FAILED: drift godtaget';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'IDENTITY_CORROBORATION_SET_DRIFT%' THEN RAISE; END IF;
  END;
  RESET ROLE;
  SELECT private.reimport_canonical_json_sha256(jsonb_agg(c3.source_persona_id::text ORDER BY c3.source_persona_id::text COLLATE "C"))
    INTO v_set FROM private.source_persona_identity_candidate c3
    LEFT JOIN private.source_persona_identity i3 ON i3.source_persona_id=c3.source_persona_id
   WHERE c3.run_id=v_run AND c3.rank=1 AND (c3.basis->>'corroboration_eligible')::boolean
     AND i3.source_persona_id IS NULL
     AND NOT EXISTS (SELECT 1 FROM private.identity_control_sample x WHERE x.control_run_id=v_ctl AND x.source_persona_id=c3.source_persona_id);
  SET LOCAL ROLE authenticated;
  v_n:=red_corroborate_family_identities(v_ctl,v_set);
  IF v_n<>1 THEN RAISE EXCEPTION 'CORROBORATION_TEST_FAILED: % accepteret',v_n; END IF;
  RESET ROLE;

  -- Defekterne: kernen kaldes direkte (ejer, med redaktør-aktør), hver skal afvises med sin kode.
  UPDATE private.source_persona_identity SET decision_status='unresolved',canonical_person_id=NULL
   WHERE source_persona_id=((v_defect->'D1'->'post')->>'principal')::uuid;   -- ejer-mutation: simulerer ny afgørelse
  UPDATE family_member SET konfidens='sikker' WHERE family_id=(v_defect->'D6'->>'family')::bigint AND person_id=-58152;
  -- D3a afgøres menneskeligt først, så D3b rammer dobbelt mål
  SELECT pc.source_persona_id INTO v_sp FROM private.interpretation_party_current pc
   WHERE pc.interpretation_key=(v_defect->'D3a'->>'claim')::uuid AND pc.party_role='spouse';
  SET LOCAL ROLE authenticated;
  PERFORM red_afgoer_source_persona(v_sp,0,'same',-58122,'menneske','{}'::jsonb);
  RESET ROLE;
  FOR v_name,v_err IN SELECT * FROM (VALUES ('D1','FAMILY_CORROBORATION_PRINCIPAL_NOT_ACCEPTED'),('D2','FAMILY_CORROBORATION_COUNT_MISMATCH'),
      ('D3b','FAMILY_CORROBORATION_DOUBLE_TARGET'),('D4','FAMILY_CORROBORATION_KONFIDENS'),('D5','FAMILY_CORROBORATION_ORDINAL_NULL'),
      ('D6','FAMILY_CORROBORATION_CANDIDATE_INVALID')) t LOOP
    SELECT pc.source_persona_id INTO v_sp FROM private.interpretation_party_current pc
     WHERE pc.interpretation_key=(v_defect->v_name->>'claim')::uuid AND pc.party_role='spouse';
    SELECT id INTO v_cand FROM private.source_persona_identity_candidate WHERE run_id=v_run AND source_persona_id=v_sp AND rank=1;
    v_ev:=jsonb_build_object('basis','family_corroboration','method','family-corroboration-v1','run_id',v_run,'candidate_id',v_cand,
      'family_id',0,'ordinal',1,'control_run_id',v_ctl,'family_context_sha256',repeat('0',64));
    BEGIN
      PERFORM private.decide_source_persona_identity(v_sp,(v_defect->v_name->>'partner')::bigint,0,'accepted',v_ev,'family_corroboration');
      RAISE EXCEPTION 'CORROBORATION_TEST_FAILED: % godtaget',v_name;
    EXCEPTION WHEN OTHERS THEN
      IF SQLERRM NOT LIKE v_err||'%' THEN RAISE EXCEPTION 'CORROBORATION_TEST_FAILED: % gav %',v_name,SQLERRM; END IF;
    END;
  END LOOP;
  -- direkte kald fra klientrolle er umuligt
  SET LOCAL ROLE authenticated;
  BEGIN
    PERFORM private.decide_source_persona_identity(v_sp,-58152,0,'accepted',v_ev,'family_corroboration');
    RAISE EXCEPTION 'CORROBORATION_TEST_FAILED: kernen kaldbar';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  RESET ROLE;
  RAISE NOTICE 'OK: not_ready, drift, ét maskinelt accept, seks defekter afvist med egen kode, kernen privat';
END $family_corroboration$;
ROLLBACK;
