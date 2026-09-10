-- #147 4.2: ét prædikat-navnerum — tabel, FK'er, value_kind-binding, view.
\set ON_ERROR_STOP on
BEGIN;
CREATE FUNCTION pg_temp.expect_error(p_sql text, p_token text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN EXECUTE p_sql; EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE p_token||'%' THEN RAISE EXCEPTION 'PREDICATE_TEST_WRONG_ERROR: expected % got %', p_token, SQLERRM; END IF; RETURN; END;
  RAISE EXCEPTION 'PREDICATE_TEST_NO_ERROR: expected %', p_token;
END $$;

DO $t1_table_and_seed$
DECLARE v_n integer; v_pred text;
BEGIN
  IF to_regclass('private.interpretation_predicate') IS NULL THEN RAISE EXCEPTION 'PREDICATE_TABLE_MISSING'; END IF;
  SELECT count(*) INTO v_n FROM private.interpretation_predicate WHERE status='active' AND introduced_in<>'db-verify-fixture'; IF v_n<>42 THEN RAISE EXCEPTION 'PREDICATE_SEED_COUNT: %', v_n; END IF;
  SELECT count(*) INTO v_n FROM private.interpretation_predicate WHERE introduced_in='db-verify-fixture'; IF v_n<>8 THEN RAISE EXCEPTION 'PREDICATE_FIXTURE_SEED_COUNT: %', v_n; END IF;
  FOREACH v_pred IN ARRAY ARRAY['person.name','person.byname','person.title','person.birth','person.death'] LOOP
    IF NOT EXISTS (SELECT 1 FROM private.interpretation_promotion_rule_line l JOIN private.interpretation_predicate p ON p.predicate=l.predicate WHERE l.predicate=v_pred) THEN
      RAISE EXCEPTION 'PREDICATE_RULE_JOIN_MISSING: %', v_pred; END IF;
  END LOOP;
  SELECT count(*) INTO v_n FROM private.interpretation_predicate_promotable; IF v_n<>5 THEN RAISE EXCEPTION 'PREDICATE_PROMOTABLE_VIEW: %', v_n; END IF;
  -- Reglens value_kind = prædikatets.
  IF EXISTS (SELECT 1 FROM private.interpretation_promotion_rule_current r JOIN private.interpretation_predicate p ON p.predicate=r.predicate WHERE r.value_kind<>p.value_kind) THEN RAISE EXCEPTION 'PREDICATE_VALUE_KIND_DRIFT'; END IF;
  IF EXISTS (SELECT 1 FROM private.interpretation_predicate WHERE category IS NOT NULL AND NOT EXISTS (SELECT 1 FROM private.vocab v WHERE v.scheme='interpretation_category' AND v.code=category)) THEN RAISE EXCEPTION 'PREDICATE_CATEGORY_UNSEEDED'; END IF;
  RAISE NOTICE 't1 table and seed OK';
END $t1_table_and_seed$;

DO $t2_fks_and_binding$
DECLARE v_run uuid := gen_random_uuid();
BEGIN
  -- Gamle extractor-navne findes ikke.
  IF EXISTS (SELECT 1 FROM private.interpretation_predicate WHERE predicate IN ('life_event.birth','title.title','honour.honour')) THEN RAISE EXCEPTION 'PREDICATE_OLD_NAMES_PRESENT'; END IF;
  -- R6: gyldige præmisser, så prædikat-FK'en er den ENESTE ugyldige værdi. Uden dem
  -- fyrer interpretation_source_id_fkey først, og testen ville bevise noget andet.
  INSERT INTO public.source(id,slags,titel,udgave,aar)
  VALUES(-147001,'DAA-udgave','Predicate fixture','synthetic',1900) ON CONFLICT(id) DO NOTHING;
  INSERT INTO private.extraction_run(id,source_id,run_key,schema_version,extractor_version,profile_version,input_sha256,manifest)
  VALUES(v_run,-147001,'predicate-test-'||v_run::text,'fixture','fixture','fixture',repeat('1',64),'{}');

  -- interpretation.predicate → FK: ukendt prædikat.
  PERFORM pg_temp.expect_error(format($q$INSERT INTO private.interpretation(interpretation_key,version,source_id,interpretation_kind,predicate,value,schema_version,derivation_kind,confidence,status,method,extraction_run_id)
    VALUES(gen_random_uuid(),1,-147001,'property','life_event.birth','"1801"','1.1','model_inference',0.5,'proposed','model',%L)$q$, v_run),
    'insert or update on table "interpretation" violates foreign key constraint "interpretation_predicate_fk"');
  -- R4': KENDT prædikat, men forkert udsagnsform. Komposit-FK'en skal bide her — ellers
  -- ville tabellen ikke være eneste sandhed om udsagnsformen, som målet lover.
  PERFORM pg_temp.expect_error(format($q$INSERT INTO private.interpretation(interpretation_key,version,source_id,interpretation_kind,predicate,value,schema_version,derivation_kind,confidence,status,method,extraction_run_id)
    VALUES(gen_random_uuid(),1,-147001,'event','person.name','"Alfa"','1.1','model_inference',0.5,'proposed','model',%L)$q$, v_run),
    'insert or update on table "interpretation" violates foreign key constraint "interpretation_predicate_fk"');
  -- rule_line har bevidst ingen FK (db-verify's syntetiske fixtures), men en regel på et ukendt prædikat afvises.
  INSERT INTO private.interpretation_promotion_rule_line(rule_key,predicate) VALUES('x-v1','person.nonexistent');
  PERFORM pg_temp.expect_error($q$SELECT private.add_interpretation_promotion_rule_version('x-v1','person.nonexistent','property','assertion','navn','text',true,false,true,'active')$q$,'EVIDENCE_PROMOTION_RULE_PREDICATE_UNKNOWN');
  -- Regel for et prædikat med objekt-værdiform afvises (value_kind-binding).
  INSERT INTO private.interpretation_promotion_rule_line(rule_key,predicate) VALUES('event-marriage-test','event.marriage');
  PERFORM pg_temp.expect_error($q$SELECT private.add_interpretation_promotion_rule_version('event-marriage-test','event.marriage','property','assertion','navn','text',true,false,true,'active')$q$,'EVIDENCE_PROMOTION_RULE_VALUE_KIND_MISMATCH');
  -- Regel med forkert value_kind for et text-prædikat afvises.
  INSERT INTO private.interpretation_promotion_rule_line(rule_key,predicate) VALUES('office-test','person.office');
  PERFORM pg_temp.expect_error($q$SELECT private.add_interpretation_promotion_rule_version('office-test','person.office','property','assertion','titel','date_raw',true,false,true,'active')$q$,'EVIDENCE_PROMOTION_RULE_VALUE_KIND_MISMATCH');
  -- R3': en almindelig regel må ikke pege på et fixture-prædikat.
  INSERT INTO private.interpretation_promotion_rule_line(rule_key,predicate) VALUES('scope-test','verify.name');
  PERFORM pg_temp.expect_error($q$SELECT private.add_interpretation_promotion_rule_version('scope-test','verify.name','property','assertion','navn','text',true,false,true,'active')$q$,'EVIDENCE_PROMOTION_RULE_FIXTURE_SCOPE_INVALID');
  -- ... og en verify-regel må ikke pege på et rigtigt prædikat.
  -- rule_line.predicate er UNIQUE, så proben bruger et andet rigtigt prædikat.
  INSERT INTO private.interpretation_promotion_rule_line(rule_key,predicate) VALUES('verify-scope-test','person.rank');
  PERFORM pg_temp.expect_error($q$SELECT private.add_interpretation_promotion_rule_version('verify-scope-test','person.rank','property','assertion','titel','text',true,false,true,'active')$q$,'EVIDENCE_PROMOTION_RULE_FIXTURE_SCOPE_INVALID');
  -- Korrekt value_kind går igennem.
  PERFORM private.add_interpretation_promotion_rule_version('office-test','person.office','property','assertion','titel','text',true,false,true,'active');
  RAISE NOTICE 't2 fks and binding OK';
END $t2_fks_and_binding$;
ROLLBACK;
