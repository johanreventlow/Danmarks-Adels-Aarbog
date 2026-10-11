-- Trin 5b del 2a (spec 2026-10-11): regeltype, tilstand, afgørelse og binding.
\set ON_ERROR_STOP on

-- ---------- Task 1: regeltypen structural_family ----------
BEGIN;
DO $rule_mode$
DECLARE v_err text;
BEGIN
  IF (SELECT attnotnull FROM pg_attribute WHERE attrelid='private.interpretation_promotion_rule'::regclass
       AND attname='expected_fact_type') THEN
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: expected_fact_type er stadig NOT NULL';
  END IF;
  IF (SELECT count(*) FROM private.interpretation_promotion_rule_current
       WHERE rule_key IN ('relation-marriage-v1','relation-parent-v1') AND rule_mode='structural_family'
         AND status='active' AND target_type='family' AND expected_fact_type IS NULL)<>2 THEN
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: relationsregler mangler';
  END IF;
  -- structural_family med assertion-mål afvises af CHECK'en
  BEGIN
    INSERT INTO private.interpretation_promotion_rule(rule_key,rule_version,predicate,interpretation_kind,target_type,
      expected_fact_type,value_kind,requires_persona_identity,requires_principal_placement,bulk_eligible,status,rule_mode)
    VALUES ('relation-marriage-v1',99,'relation.marriage','relation','assertion',NULL,'relation',false,false,true,'active','structural_family');
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: forkert mål godtaget';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  -- text_assertion uden faktatype afvises
  BEGIN
    INSERT INTO private.interpretation_promotion_rule(rule_key,rule_version,predicate,interpretation_kind,target_type,
      expected_fact_type,value_kind,requires_persona_identity,requires_principal_placement,bulk_eligible,status,rule_mode)
    VALUES ('person-name-v1',99,'person.name','property','assertion',NULL,'text',true,false,true,'active','text_assertion');
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: assertion-regel uden faktatype godtaget';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  -- Triggeren er sit eget kontraktled (Codex plan-r1 #7): rækker der PASSERER mode-CHECK'en,
  -- men har et prædikat af forkert værdiart, afvises af triggeren med dens egen kode.
  BEGIN
    INSERT INTO private.interpretation_promotion_rule(rule_key,rule_version,predicate,interpretation_kind,target_type,
      expected_fact_type,value_kind,requires_persona_identity,requires_principal_placement,bulk_eligible,status,rule_mode)
    VALUES ('relation-marriage-v1',98,'relation.marriage','property','assertion','navn','text',true,false,true,'active','text_assertion');
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: relation som tekstregel godtaget af triggeren';
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT;
    IF v_err NOT LIKE 'EVIDENCE_PROMOTION_RULE_VALUE_KIND_MISMATCH%' THEN RAISE; END IF;
  END;
  BEGIN
    INSERT INTO private.interpretation_promotion_rule(rule_key,rule_version,predicate,interpretation_kind,target_type,
      expected_fact_type,value_kind,requires_persona_identity,requires_principal_placement,bulk_eligible,status,rule_mode)
    VALUES ('person-name-v1',98,'person.name','relation','family',NULL,'relation',false,false,true,'active','structural_family');
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: tekstprædikat som strukturregel godtaget af triggeren';
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT;
    IF v_err NOT LIKE 'EVIDENCE_PROMOTION_RULE_VALUE_KIND_MISMATCH%' THEN RAISE; END IF;
  END;
  -- versionsfunktionen: relation kun i structural_family
  BEGIN
    PERFORM private.add_interpretation_promotion_rule_version('relation-marriage-v1','relation.marriage','relation','family',
      NULL,'relation',false,false,true,'active');   -- default text_assertion
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: relation som text_assertion godtaget';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT;
    IF v_err NOT LIKE 'EVIDENCE_PROMOTION_RULE_VALUE_KIND_MISMATCH%' AND v_err NOT LIKE '%interpretation_promotion_rule_mode_check%' THEN RAISE; END IF;
  END;
  IF private.add_interpretation_promotion_rule_version('relation-marriage-v1','relation.marriage','relation','family',
       NULL,'relation',false,false,true,'active','structural_family')<>2 THEN
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: ny structural_family-version';
  END IF;
  -- assertion-vejen ser aldrig relationsregler
  IF EXISTS (SELECT 1 FROM private.interpretation_predicate_promotable WHERE predicate LIKE 'relation.%') THEN
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: relationsregel i promotable';
  END IF;
  IF to_regprocedure('private.add_interpretation_promotion_rule_version(text,text,text,text,text,text,boolean,boolean,boolean,text)') IS NOT NULL THEN
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: gammel overload findes';
  END IF;
  RAISE NOTICE 'OK: regeltype structural_family';
END $rule_mode$;
ROLLBACK;

-- ---------- Task 2: bindingens tilstand ----------
BEGIN;
\ir fixtures/relation-5b.sql
\ir fixtures/relation-2a.sql
DO $binding_state$
DECLARE v_actor uuid:='11000000-0000-0000-0000-0000002a0201'; s jsonb; m jsonb; m2 jsonb; par jsonb; st jsonb; h1 text; v_err text;
  v_fam2 bigint;
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  INSERT INTO person(id,levende,privat,status) VALUES
    (-2201,false,false,'2a'),(-2202,false,false,'2a'),(-2203,false,false,'2a'),(-2204,false,false,'2a'),
    (-2205,false,false,'2a'),(-2206,false,false,'2a'),(-2207,false,false,'2a');
  s:=pg_temp.f5b_source(-2201);
  m:=pg_temp.f2a_marriage(-2201,s,'M-1',-2201,-2202,v_actor,2,1);
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;   -- fixturen skal være en mulig, committbar tilstand
  st:=private.relation_binding_state((m->'claim'->>'id')::uuid);
  IF st IS NULL OR st->>'contract'<>'relation-binding-state-v1' OR (st->'family'->>'family_id')::bigint<>(m->>'family')::bigint
     OR jsonb_array_length(st->'family'->'rows')<>2 OR (st->>'book_ordinal')::int<>2 OR (st->>'family_ordinal')::int<>1
     OR jsonb_array_length(st->'parties')<>2 OR st ? 'rule' OR (st->>'counterpart_person_id')::bigint<>-2202 THEN
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: tilstand %', st IS NULL;
  END IF;
  h1:=private.relation_binding_state_sha256((m->'claim'->>'id')::uuid);
  -- barn_uden_for_struktur: et nyt barn ændrer ikke tilstanden
  INSERT INTO family_member(family_id,person_id,rolle) VALUES ((m->>'family')::bigint,-2203,'barn');
  IF private.relation_binding_state_sha256((m->'claim'->>'id')::uuid) IS DISTINCT FROM h1 THEN
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: barn ændrede tilstanden';
  END IF;
  -- omstridt på en bærende række ⇒ NULL
  UPDATE family_member SET konfidens='omstridt' WHERE family_id=(m->>'family')::bigint AND person_id=-2202;
  IF private.relation_binding_state((m->'claim'->>'id')::uuid) IS NOT NULL THEN
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: omstridt godtaget';
  END IF;
  UPDATE family_member SET konfidens=NULL WHERE family_id=(m->>'family')::bigint AND person_id=-2202;
  -- to familier med samme par ⇒ NULL; bagefter fjernes den ekstra familie igen, så klassifikationsdelen
  -- nedenfor arbejder på en entydig struktur (Codex plan-r1 #1)
  v_fam2:=pg_temp.f5b_family(-2201,-2202,2);
  IF private.relation_binding_state((m->'claim'->>'id')::uuid) IS NOT NULL THEN
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: flere familier godtaget';
  END IF;
  DELETE FROM family_member WHERE family_id=v_fam2;
  DELETE FROM family WHERE id=v_fam2;
  IF private.relation_binding_state_sha256((m->'claim'->>'id')::uuid) IS DISTINCT FROM h1 THEN
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: tilstanden vendte ikke tilbage efter oprydning';
  END IF;
  -- ingen familie ⇒ NULL
  m2:=pg_temp.f2a_marriage(-2201,s,'M-2',-2204,-2205,v_actor,1,1,false);
  IF private.relation_binding_state((m2->'claim'->>'id')::uuid) IS NOT NULL THEN
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: ingen familie godtaget';
  END IF;
  -- forælder: principal er barn, forælderen partner
  par:=pg_temp.f2a_parent(-2201,s,-2206,-2207,NULL,v_actor);
  st:=private.relation_binding_state((SELECT id FROM private.interpretation_current WHERE interpretation_key=(par->'claim'->>'key')::uuid));
  IF st IS NULL OR st->'interpretation'->>'status'<>'accepted' OR (st->'family'->>'family_id')::bigint<>(par->>'family')::bigint
     OR (st->>'counterpart_person_id')::bigint<>-2207 THEN
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: forældertilstand';
  END IF;
  -- klassifikation: append-only med fortløbende seq
  -- Hvert kald i sin egen sætning: en underforespørgsel i samme IF-udtryk ser ikke rækkerne, som
  -- funktionskald i samme sætning indsætter (ét snapshot pr. sætning).
  IF private.append_relation_classification((m->'claim'->>'id')::uuid,'ordinal_afvigelse','{"x":1}')<>1 THEN
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: første seq';
  END IF;
  IF private.append_relation_classification((m->'claim'->>'id')::uuid,'ordinal_afvigelse','{"x":2}')<>2 THEN
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: anden seq';
  END IF;
  IF (SELECT count(*) FROM private.relation_classification_event
          WHERE interpretation_key=(m->'claim'->>'key')::uuid AND interpretation_id=(m->'claim'->>'id')::uuid
            AND interpretation_version=1 AND state_sha256 ~ '^[0-9a-f]{64}$')<>2 THEN
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: klassifikationens seq og versionsbinding';
  END IF;
  -- en ikke-gældende version kan ikke klassificeres
  BEGIN
    PERFORM private.append_relation_classification(gen_random_uuid(),'ordinal_afvigelse','{"x":4}');
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: ukendt fortolkning';
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT;
    IF v_err NOT LIKE 'RELATION_CLASSIFICATION_NOT_CURRENT%' THEN RAISE; END IF;
  END;
  BEGIN
    UPDATE private.relation_classification_event SET evidence='{"y":1}' WHERE interpretation_key=(m->'claim'->>'key')::uuid;
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: klassifikation kunne ændres';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT;
    IF v_err LIKE 'RELATION_BINDING_TEST_FAILED%' THEN RAISE; END IF;
  END;
  BEGIN
    PERFORM private.append_relation_classification((m->'claim'->>'id')::uuid,'noget_andet','{"x":3}');
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: ukendt klassifikation';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  RAISE NOTICE 'OK: bindingens tilstand og klassifikationer';
END $binding_state$;
ROLLBACK;
