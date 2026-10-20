-- Trin 5b, Task 5: strukturelle kandidater og menneskelig afgørelse af relation.parent (relation.child er del 2).
\set ON_ERROR_STOP on
BEGIN;
\ir fixtures/relation-5b.sql
DO $relation_decision$
DECLARE
  v_actor uuid:='11000000-0000-0000-0000-00000005b501';
  s jsonb; pa jsonb; pc jsonb; cc jsonb; cp jsonb; cr jsonb; v_fam bigint; v_other bigint; v_ver int; v_n int;
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  INSERT INTO person(id,levende,privat,status) VALUES (-5501,false,false,'5b'),(-5502,false,false,'5b'),(-5503,false,false,'5b');
  s:=pg_temp.f5b_source(-5501);
  pa:=pg_temp.f5b_post(-5501,s,'V-1','Anna Alfa. Søn Carl.',ARRAY['Anna Alfa.','Søn Carl.'],-5501,v_actor);
  pc:=pg_temp.f5b_post(-5501,s,'V-2','Carl Alfa. søn af Anna.',ARRAY['Carl Alfa.','søn af Anna.'],-5502,v_actor);
  v_fam:=pg_temp.f5b_family(-5501,-5503,1);
  INSERT INTO family_member(family_id,person_id,rolle) VALUES (v_fam,-5502,'barn');
  v_other:=pg_temp.f5b_family(-5503,NULL,2);
  cc:=pg_temp.f5b_claim(-5501,s,'relation.child',(pa->'clauses'->>1)::uuid,'Søn Carl.');
  cp:=pg_temp.f5b_claim(-5501,s,'relation.parent',(pc->'clauses'->>1)::uuid,'søn af Anna.');
  INSERT INTO private.interpretation_party(interpretation_key,party_role,version,source_persona_id,post_offset,origin,origin_ref)
    VALUES ((cc->>'key')::uuid,'principal',1,(pa->>'principal')::uuid,11,'relation_persona',gen_random_uuid()),
           ((cp->>'key')::uuid,'principal',1,(pc->>'principal')::uuid,11,'relation_persona',gen_random_uuid());

  IF (SELECT array_agg(counterpart_person_id) FROM private.relation_structural_candidates((cc->>'key')::uuid))<>ARRAY[-5502]::bigint[]
     OR (SELECT array_agg(counterpart_person_id) FROM private.relation_structural_candidates((cp->>'key')::uuid))<>ARRAY[-5501]::bigint[] THEN
    RAISE EXCEPTION 'RELATION_DECISION_TEST_FAILED: strukturelle kandidater';
  END IF;

  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  SET LOCAL ROLE authenticated;
  -- 2b-iii: et barn afgøres kun via arket og uden familie-id.
  BEGIN
    PERFORM red_afgoer_relation_interpretation((cc->>'key')::uuid,1,'same',v_fam,'barnet passer','{}');
    RAISE EXCEPTION 'RELATION_DECISION_TEST_FAILED: barn afgjort i del 1';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'RELATION_DECISION_INVALID%' THEN RAISE; END IF;
  END;
  BEGIN
    PERFORM red_afgoer_relation_interpretation((cc->>'key')::uuid,1,'unresolved',NULL,'kan ikke afgøre','{}');
    RAISE EXCEPTION 'RELATION_DECISION_TEST_FAILED: barn U i del 1';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'RELATION_DECISION_INVALID%' THEN RAISE; END IF;
  END;
  -- familie uden for kandidaterne afvises
  BEGIN
    PERFORM red_afgoer_relation_interpretation((cp->>'key')::uuid,1,'same',v_other,'forkert familie','{}');
    RAISE EXCEPTION 'RELATION_DECISION_TEST_FAILED: fremmed familie godtaget';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'RELATION_DECISION_FAMILY_INVALID%' THEN RAISE; END IF;
  END;
  -- forældet version afvises
  BEGIN
    PERFORM red_afgoer_relation_interpretation((cp->>'key')::uuid,2,'same',v_fam,'gammel','{}');
    RAISE EXCEPTION 'RELATION_DECISION_TEST_FAILED: forkert version godtaget';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'EVIDENCE_INTERPRETATION_VERSION_CONFLICT%' THEN RAISE; END IF;
  END;
  v_ver:=red_afgoer_relation_interpretation((cp->>'key')::uuid,1,'same',v_fam,'forælderen passer','{}');
  -- spec §23.4: rejected virker også uden kort (påstanden afvises, ingen part)
  RESET ROLE;
  cr:=pg_temp.f5b_claim(-5501,s,'relation.parent',(pc->'clauses'->>1)::uuid,'søn af Anna.');
  INSERT INTO private.interpretation_party(interpretation_key,party_role,version,source_persona_id,post_offset,origin,origin_ref)
    VALUES ((cr->>'key')::uuid,'principal',1,(pc->>'principal')::uuid,11,'relation_persona',gen_random_uuid());
  SET LOCAL ROLE authenticated;
  PERFORM red_afgoer_relation_interpretation((cr->>'key')::uuid,1,'rejected',NULL,'bogen siger det ikke','{}');
  RESET ROLE;
  IF (SELECT status FROM private.interpretation_current WHERE interpretation_key=(cr->>'key')::uuid)<>'rejected'
     OR EXISTS (SELECT 1 FROM private.interpretation_party_current WHERE interpretation_key=(cr->>'key')::uuid AND party_role='parent') THEN
    RAISE EXCEPTION 'RELATION_DECISION_TEST_FAILED: rejected uden kort';
  END IF;
  IF v_ver<>2 OR (SELECT status FROM private.interpretation_current WHERE interpretation_key=(cp->>'key')::uuid)<>'accepted'
     OR (SELECT decision_evidence->>'family_id' FROM private.interpretation_current WHERE interpretation_key=(cp->>'key')::uuid)<>v_fam::text
     OR NOT EXISTS (SELECT 1 FROM private.interpretation_party_current WHERE interpretation_key=(cp->>'key')::uuid
                     AND party_role='parent' AND source_persona_id=(pa->>'principal')::uuid)
     OR (SELECT status FROM private.interpretation_current WHERE interpretation_key=(cc->>'key')::uuid)<>'proposed'
     OR EXISTS (SELECT 1 FROM private.interpretation_party_current WHERE interpretation_key=(cc->>'key')::uuid AND party_role='child') THEN
    RAISE EXCEPTION 'RELATION_DECISION_TEST_FAILED: afgørelse eller part';
  END IF;
  RAISE NOTICE 'OK: strukturelle kandidater, barn udskudt, familievalg, version, accept med modpart';
END $relation_decision$;

ROLLBACK;

-- Rækkelåsen: en samtidig family_member-indsættelse for personen venter (FK tager KEY SHARE).
-- Personen committes først, så dblink-forbindelsen ser den; den ryddes op til sidst.
INSERT INTO person(id,levende,privat,status) VALUES (-5591,false,false,'5b lock') ON CONFLICT (id) DO NOTHING;
CREATE EXTENSION IF NOT EXISTS dblink;
BEGIN;
DO $relation_lock$
DECLARE v_err text;
  -- Samme forbindelsesstreng som 5a's låsetest (test-identity-decision.sql:184): dblink bruger
  -- serverprocessens libpq-standarder, så port og socket skal angives eksplicit.
  v_conn text:=format('dbname=%s port=%s host=%s',current_database(),current_setting('port'),
                      split_part(current_setting('unix_socket_directories'),',',1));
BEGIN
  PERFORM private.lock_family_rows(ARRAY[-5591]::bigint[]);
  BEGIN
    PERFORM dblink_connect('l5b',v_conn);
    PERFORM * FROM dblink('l5b','SET lock_timeout=''300ms''; INSERT INTO family(id,type) VALUES (-5591,''vielse''); '
      ||'INSERT INTO family_member(family_id,person_id,rolle) VALUES (-5591,-5591,''partner''); SELECT ''x''') AS t(x text);
    RAISE EXCEPTION 'RELATION_DECISION_TEST_FAILED: indsættelse ventede ikke';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT;
    PERFORM dblink_disconnect('l5b');
    IF v_err NOT LIKE '%lock timeout%' THEN RAISE; END IF;
  END;
  RAISE NOTICE 'OK: personlåsen blokerer nye familiemedlemmer';
END $relation_lock$;
ROLLBACK;
DELETE FROM person WHERE id=-5591;

-- ---------- Spec §23.2(b)/§23.4: forældrekort (A/R/F) gennem kontrolkørslen ----------
BEGIN;
\ir fixtures/relation-5b.sql
DO $parent_card$
DECLARE
  v_actor uuid:='11000000-0000-0000-0000-00000005b711';
  s jsonb; pf jsonb; pb jsonb; pr jsonb; k jsonb[]:='{}'; c jsonb; v_in jsonb; v_run uuid; v_ctl uuid; v_fam bigint; v_fam2 bigint;
  v_s text:=repeat('a',64); v_r text:=repeat('b',64); v_ctx jsonb; v_status text; v_ver int; i int;
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  INSERT INTO person(id,levende,privat,status) VALUES (-57111,false,false,'5b'),(-57112,false,false,'5b'),(-57113,false,false,'5b'),(-57114,false,false,'5b');
  s:=pg_temp.f5b_source(-5711);
  pf:=pg_temp.f5b_post(-5711,s,'W-1','Far Alfa.',ARRAY['Far Alfa.'],-57111,v_actor);
  pb:=pg_temp.f5b_post(-5711,s,'W-2','Barn Alfa. søn af Far. søn af Far. søn af Far. søn af Far.',
       ARRAY['Barn Alfa.','søn af Far.','søn af Far.','søn af Far.','søn af Far.'],-57113,v_actor);
  pr:=pg_temp.f5b_post(-5711,s,'W-3','Anden Far.',ARRAY['Anden Far.'],-57114,v_actor);
  v_fam:=pg_temp.f5b_family(-57111,-57112,1);
  INSERT INTO family_member(family_id,person_id,rolle) VALUES (v_fam,-57113,'barn');
  FOR i IN 1..4 LOOP
    c:=pg_temp.f5b_claim(-5711,s,'relation.parent',(pb->'clauses'->>i)::uuid,'søn af Far.');
    INSERT INTO private.interpretation_party(interpretation_key,party_role,version,source_persona_id,post_offset,origin,origin_ref)
      VALUES ((c->>'key')::uuid,'principal',1,(pb->>'principal')::uuid,11+12*(i-1),'relation_persona',gen_random_uuid());
    k:=k||c;
  END LOOP;
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  SET LOCAL ROLE authenticated;
  v_in:=red_identity_candidate_input(-5711,'{"mode":"undecided"}');
  v_run:=red_record_identity_candidates(jsonb_build_object('source_id',-5711,'generator_version','t','config','{}'::jsonb,
    'input_spec','{"mode":"undecided"}'::jsonb,'input_sha256',v_in->>'input_sha256'),'[]'::jsonb);
  v_ctl:=red_register_identity_control_run(v_run);
  RESET ROLE;
  IF (SELECT count(*) FROM private.identity_control_parent_card WHERE control_run_id=v_ctl)<>4
     OR EXISTS (SELECT 1 FROM private.identity_control_parent_card WHERE control_run_id=v_ctl
                 AND (family_id<>v_fam OR counterpart_person_id<>-57111 OR partner_ids<>ARRAY[-57112,-57111]::bigint[]))
     OR EXISTS (SELECT 1 FROM private.identity_control_sample WHERE control_run_id=v_ctl) THEN
    RAISE EXCEPTION 'PARENT_CARD_TEST_FAILED: registrering';
  END IF;
  SET LOCAL ROLE authenticated;
  PERFORM red_seal_identity_control_run(v_ctl,v_s,v_r);
  v_status:=red_evaluate_identity_control_run(v_ctl);
  v_ctx:=jsonb_build_object('basis','human_sheet','sheet_sha256',v_s,'rows_sha256',v_r,'line',3,'control_run_id',v_ctl);
  -- forkert arkhash og klientleveret familie afvises
  BEGIN
    PERFORM red_afgoer_relation_interpretation((k[1]->>'key')::uuid,1,'same',NULL,'A',v_ctx||'{"sheet_sha256":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"}');
    RAISE EXCEPTION 'PARENT_CARD_TEST_FAILED: forkert arkhash';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'PARENT_CARD_CONTEXT_INVALID%' THEN RAISE; END IF;
  END;
  BEGIN
    PERFORM red_afgoer_relation_interpretation((k[1]->>'key')::uuid,1,'same',v_fam,'A',v_ctx);
    RAISE EXCEPTION 'PARENT_CARD_TEST_FAILED: klientens familie';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'PARENT_CARD_CONTEXT_INVALID%' THEN RAISE; END IF;
  END;
  -- A: serveren opløser familien; R: afvist; F: klassifikation uden ændring
  v_ver:=red_afgoer_relation_interpretation((k[1]->>'key')::uuid,1,'same',NULL,'A',v_ctx);
  PERFORM red_afgoer_relation_interpretation((k[2]->>'key')::uuid,1,'rejected',NULL,'R',v_ctx);
  IF red_classify_parent_card(v_ctl,(k[3]->>'key')::uuid,1,'F','F',v_ctx)<>1 THEN RAISE EXCEPTION 'PARENT_CARD_TEST_FAILED: F-seq'; END IF;
  -- ny familie med barnet og en anden hovedperson som partner ⇒ A bliver familie_aendret, intet skrevet
  RESET ROLE;
  v_fam2:=pg_temp.f5b_family(-57114,NULL,1);
  INSERT INTO family_member(family_id,person_id,rolle) VALUES (v_fam2,-57113,'barn');
  SET LOCAL ROLE authenticated;
  IF red_afgoer_relation_interpretation((k[4]->>'key')::uuid,1,'same',NULL,'A',v_ctx)<>0 THEN
    RAISE EXCEPTION 'PARENT_CARD_TEST_FAILED: familie_aendret returnerede ikke 0';
  END IF;
  IF red_evaluate_identity_control_run(v_ctl) IS DISTINCT FROM v_status THEN RAISE EXCEPTION 'PARENT_CARD_TEST_FAILED: status ændret'; END IF;
  RESET ROLE;
  IF v_ver<>2
     OR (SELECT status FROM private.interpretation_current WHERE interpretation_key=(k[1]->>'key')::uuid)<>'accepted'
     OR NOT EXISTS (SELECT 1 FROM private.interpretation_party_current WHERE interpretation_key=(k[1]->>'key')::uuid
                     AND party_role='parent' AND source_persona_id=(pf->>'principal')::uuid)
     OR (SELECT decision_evidence->>'control_run_id' FROM private.interpretation_current WHERE interpretation_key=(k[1]->>'key')::uuid)<>v_ctl::text
     OR (SELECT status FROM private.interpretation_current WHERE interpretation_key=(k[2]->>'key')::uuid)<>'rejected'
     OR EXISTS (SELECT 1 FROM private.interpretation_party_current WHERE interpretation_key=(k[2]->>'key')::uuid AND party_role='parent')
     OR (SELECT status FROM private.interpretation_current WHERE interpretation_key=(k[3]->>'key')::uuid)<>'proposed'
     OR (SELECT status FROM private.interpretation_current WHERE interpretation_key=(k[4]->>'key')::uuid)<>'proposed'
     OR (SELECT array_agg(e.outcome ORDER BY c2.interpretation_key::text) FROM private.identity_control_parent_event e
           JOIN private.identity_control_parent_card c2 ON c2.id=e.card_id WHERE c2.control_run_id=v_ctl)
        IS DISTINCT FROM (SELECT array_agg(o ORDER BY kk) FROM (VALUES ((k[3]->>'key'),'F'),((k[4]->>'key'),'familie_aendret')) t(kk,o)) THEN
    RAISE EXCEPTION 'PARENT_CARD_TEST_FAILED: udfald';
  END IF;
  RAISE NOTICE 'OK: forældrekort — registrering, kontekstkontrol, A/R/F, familie_aendret uden skrivning, status uberørt';
END $parent_card$;
ROLLBACK;
