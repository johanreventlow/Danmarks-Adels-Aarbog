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
