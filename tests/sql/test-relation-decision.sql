-- Trin 5b, Task 5: strukturelle kandidater og menneskelig afgørelse af relation.parent (relation.child er del 2).
\set ON_ERROR_STOP on
BEGIN;
\ir fixtures/relation-5b.sql
DO $relation_decision$
DECLARE
  v_actor uuid:='11000000-0000-0000-0000-00000005b501';
  s jsonb; pa jsonb; pc jsonb; cc jsonb; cp jsonb; v_fam bigint; v_other bigint; v_ver int; v_n int;
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
  -- Børn er taget ud af del 1 (errata §22.9): både 'same' og 'unresolved' afvises.
  BEGIN
    PERFORM red_afgoer_relation_interpretation((cc->>'key')::uuid,1,'same',v_fam,'barnet passer','{}');
    RAISE EXCEPTION 'RELATION_DECISION_TEST_FAILED: barn afgjort i del 1';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'RELATION_CHILD_DEFERRED%' THEN RAISE; END IF;
  END;
  BEGIN
    PERFORM red_afgoer_relation_interpretation((cc->>'key')::uuid,1,'unresolved',NULL,'kan ikke afgøre','{}');
    RAISE EXCEPTION 'RELATION_DECISION_TEST_FAILED: barn U i del 1';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'RELATION_CHILD_DEFERRED%' THEN RAISE; END IF;
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
  RESET ROLE;
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
