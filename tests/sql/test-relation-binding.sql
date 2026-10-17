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
  -- uden aktør ⇒ afvist (ingen nul-UUID som skaber)
  PERFORM set_config('request.jwt.claim.sub','',true);
  BEGIN
    PERFORM private.append_relation_classification((m->'claim'->>'id')::uuid,'ordinal_afvigelse','{"x":0}');
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: klassifikation uden aktør';
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT;
    IF v_err NOT LIKE 'RELATION_CLASSIFICATION_ACTOR_REQUIRED%' THEN RAISE; END IF;
  END;
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
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

-- ---------- Task 3: maskinel afgørelse af ægteskaber ----------
BEGIN;
\ir fixtures/relation-5b.sql
\ir fixtures/relation-2a.sql
DO $relation_decide$
DECLARE v_actor uuid:='11000000-0000-0000-0000-0000002a0301'; s jsonb; s2 jsonb; m1 jsonb; m2 jsonb; m3 jsonb; o jsonb; pv jsonb; n int; v_err text; v_state1 text;
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  INSERT INTO person(id,levende,privat,status) SELECT g,false,false,'2a' FROM generate_series(-2310,-2301) g;
  s:=pg_temp.f5b_source(-2301);
  s2:=pg_temp.f5b_source(-2302);
  m1:=pg_temp.f2a_marriage(-2301,s,'D-1',-2301,-2302,v_actor,1,1);   -- egnet
  m2:=pg_temp.f2a_marriage(-2301,s,'D-2',-2303,-2304,v_actor,2,1);   -- egnet, ordinal-afvigelse
  m3:=pg_temp.f2a_marriage(-2301,s,'D-3',-2305,-2306,v_actor,1,1,false); -- ingen familie
  o:=pg_temp.f2a_marriage(-2302,s2,'D-4',-2307,-2308,v_actor,1,1);   -- anden kilde
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  SET LOCAL ROLE authenticated;
  pv:=red_preview_relation_decisions(-2301);
  RESET ROLE;
  v_state1:=private.relation_binding_state_sha256((m1->'claim'->>'id')::uuid);   -- proposed-versionens tilstand
  SET LOCAL ROLE authenticated;
  IF (pv->>'count')::int<>2 OR (pv->>'ordinal_deviations')::int<>1 OR pv->>'set_sha256' !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: preview %', pv->>'count';
  END IF;
  -- anden_kilde: kildens hash kan ikke bruges mod en anden kilde
  BEGIN
    PERFORM red_decide_relation_interpretations(-2302,pv->>'set_sha256');
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: anden kilde godtaget';
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT;
    IF v_err NOT LIKE 'RELATION_DECISION_SET_DRIFT%' THEN RAISE; END IF;
  END;
  -- NULL-kilde ⇒ afvist (ville ellers springe kildelåsen over)
  BEGIN
    PERFORM red_decide_relation_interpretations(NULL,repeat('0',64));
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: NULL-kilde godtaget i afgørelsen';
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT;
    IF v_err NOT LIKE 'RELATION_DECISION_INVALID%' THEN RAISE; END IF;
  END;
  BEGIN
    PERFORM red_decide_relation_interpretations(-2301,repeat('0',64));
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: forkert hash godtaget';
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT;
    IF v_err NOT LIKE 'RELATION_DECISION_SET_DRIFT%' THEN RAISE; END IF;
  END;
  n:=red_decide_relation_interpretations(-2301,pv->>'set_sha256');
  RESET ROLE;
  IF n<>2
     OR (SELECT status FROM private.interpretation_current WHERE interpretation_key=(m1->'claim'->>'key')::uuid)<>'accepted'
     OR (SELECT decision_evidence->>'method' FROM private.interpretation_current WHERE interpretation_key=(m1->'claim'->>'key')::uuid)<>'family-structure-v1'
     OR (SELECT status FROM private.interpretation_current WHERE interpretation_key=(m3->'claim'->>'key')::uuid)<>'proposed'
     OR (SELECT status FROM private.interpretation_current WHERE interpretation_key=(o->'claim'->>'key')::uuid)<>'proposed'
     OR (SELECT count(*) FROM private.relation_classification_event WHERE interpretation_key=(m2->'claim'->>'key')::uuid AND classification='ordinal_afvigelse')<>1
     OR (SELECT count(*) FROM private.relation_classification_event WHERE interpretation_key=(m1->'claim'->>'key')::uuid)<>0 THEN
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: afgørelser';
  END IF;
  -- afgørelsens state_sha256 er hashen af den forhåndsviste (proposed) tilstand, som previewet autoriserede
  IF (SELECT decision_evidence->>'state_sha256' FROM private.interpretation_current WHERE interpretation_key=(m1->'claim'->>'key')::uuid)
     IS DISTINCT FROM v_state1 THEN
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: afgørelsens tilstandshash';
  END IF;
  -- anon/ikke-redaktion afvises
  SET LOCAL ROLE anon;
  BEGIN
    PERFORM red_preview_relation_decisions(-2301);
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: anon kunne kalde';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  RESET ROLE;
  RAISE NOTICE 'OK: maskinel afgørelse af ægteskaber';
END $relation_decide$;
ROLLBACK;

-- To sessioner: en samtidig family_member-indsættelse for en part venter på afgørelsens låse.
INSERT INTO person(id,levende,privat,status) VALUES (-2391,false,false,'2a lock') ON CONFLICT (id) DO NOTHING;
CREATE EXTENSION IF NOT EXISTS dblink;
BEGIN;
\ir fixtures/relation-5b.sql
\ir fixtures/relation-2a.sql
DO $relation_decide_lock$
DECLARE v_actor uuid:='11000000-0000-0000-0000-0000002a0391'; s jsonb; m jsonb; pv jsonb; v_err text;
  v_conn text:=format('dbname=%s port=%s host=%s',current_database(),current_setting('port'),
                      split_part(current_setting('unix_socket_directories'),',',1));
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  INSERT INTO person(id,levende,privat,status) VALUES (-2392,false,false,'2a');
  s:=pg_temp.f5b_source(-2391);
  m:=pg_temp.f2a_marriage(-2391,s,'L-1',-2391,-2392,v_actor,1,1);
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  SET LOCAL ROLE authenticated;
  pv:=red_preview_relation_decisions(-2391);
  PERFORM red_decide_relation_interpretations(-2391,pv->>'set_sha256');
  RESET ROLE;
  BEGIN
    PERFORM dblink_connect('l2a',v_conn);
    -- BEGIN i dblink-sessionen: lykkes indsættelsen (manglende lås), rulles den tilbage ved disconnect og
    -- efterlader ingen committede rækker, der ville skjule fejlen (Opus plan-r2 m4).
    PERFORM * FROM dblink('l2a','BEGIN; SET lock_timeout=''300ms''; INSERT INTO family(id,type) VALUES (-2391,''vielse''); '
      ||'INSERT INTO family_member(family_id,person_id,rolle) VALUES (-2391,-2391,''partner''); SELECT ''x''') AS t(x text);
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: indsættelse ventede ikke';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT;
    PERFORM dblink_disconnect('l2a');
    IF v_err NOT LIKE '%lock timeout%' THEN RAISE; END IF;
  END;
  RAISE NOTICE 'OK: afgørelsens låse blokerer familieændringer';
END $relation_decide_lock$;
ROLLBACK;
DELETE FROM person WHERE id=-2391;

-- To sessioner, modsat retning (spec §8, Codex plan-r1 #8): en identitetsgenafgørelse er i gang i den anden
-- session — den holder en skrivelås på ægtefællens personrække (som identitetswriterens lock_family_rows,
-- schema.sql ~8315) — og afgørelsen må vente/fejle lukket med 0 delvise afgørelser. Ægtefællen committes først,
-- så dblink-sessionen kan låse den (mønster: test-identity-decision.sql:186).
INSERT INTO person(id,levende,privat,status) VALUES (-2394,false,false,'2a lock') ON CONFLICT (id) DO NOTHING;
BEGIN;
\ir fixtures/relation-5b.sql
\ir fixtures/relation-2a.sql
DO $relation_decide_lock_identity$
DECLARE v_actor uuid:='11000000-0000-0000-0000-0000002a0393'; s jsonb; m jsonb; pv jsonb; v_state text;
  v_conn text:=format('dbname=%s port=%s host=%s',current_database(),current_setting('port'),
                      split_part(current_setting('unix_socket_directories'),',',1));
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  INSERT INTO person(id,levende,privat,status) VALUES (-2393,false,false,'2a');
  s:=pg_temp.f5b_source(-2393);
  m:=pg_temp.f2a_marriage(-2393,s,'L-2',-2393,-2394,v_actor,1,1);
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  SET LOCAL ROLE authenticated;
  pv:=red_preview_relation_decisions(-2393);
  RESET ROLE;
  PERFORM dblink_connect('l2a_id',v_conn);
  PERFORM dblink_exec('l2a_id','BEGIN');
  -- FOR NO KEY UPDATE, ikke lock_family_rows' FOR UPDATE: hovedsessionens fixture holder allerede FK-låsen
  -- FOR KEY SHARE på -2394, og FOR UPDATE i dblink ville vente på den, mens hovedsessionen venter synkront
  -- på dblink — en uopdagelig hængning (Opus plan-r2 B3). NO KEY UPDATE støder kun sammen med afgørelsens
  -- FOR UPDATE; lock_timeout i dblink-sessionen er et ekstra værn.
  PERFORM * FROM dblink('l2a_id','SET lock_timeout=''5s''; SELECT 1::text FROM person WHERE id=-2394 FOR NO KEY UPDATE') AS t(x text);
  BEGIN
    SET LOCAL ROLE authenticated;
    SET LOCAL lock_timeout='300ms';
    BEGIN
      PERFORM red_decide_relation_interpretations(-2393,pv->>'set_sha256');
    EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_state=RETURNED_SQLSTATE;
    END;
    RESET ROLE;
  EXCEPTION WHEN OTHERS THEN
    PERFORM dblink_exec('l2a_id','ROLLBACK'); PERFORM dblink_disconnect('l2a_id'); RAISE;
  END;
  PERFORM dblink_exec('l2a_id','ROLLBACK'); PERFORM dblink_disconnect('l2a_id');
  IF v_state IS DISTINCT FROM '55P03'
     OR (SELECT status FROM private.interpretation_current WHERE interpretation_key=(m->'claim'->>'key')::uuid)<>'proposed'
     OR EXISTS (SELECT 1 FROM private.relation_classification_event WHERE interpretation_key=(m->'claim'->>'key')::uuid) THEN
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: afgørelsen ventede ikke på identitetsskrivningen eller efterlod delvise writes (%)', v_state;
  END IF;
  RAISE NOTICE 'OK: afgørelsen venter på en samtidig identitetsgenafgørelse';
END $relation_decide_lock_identity$;
ROLLBACK;
DELETE FROM person WHERE id=-2394;

-- ---------- Task 4: binding (structural_family-promotion) ----------
BEGIN;
\ir fixtures/relation-5b.sql
\ir fixtures/relation-2a.sql
DO $relation_promote$
DECLARE v_actor uuid:='11000000-0000-0000-0000-0000002a0401'; s jsonb; s2 jsonb; m jsonb; m3 jsonb; m4 jsonb; o jsonb; par jsonb;
  pv jsonb; items jsonb; items4 jsonb; v_mid uuid; v_pid uuid; v_oid uuid; v_m4 uuid; v_batch uuid; v_batch2 uuid; n int; v_err text; v_fact bigint;
  v_old_hash text;
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  INSERT INTO person(id,levende,privat,status) SELECT g,false,false,'2a' FROM generate_series(-2420,-2401) g;
  s:=pg_temp.f5b_source(-2401);
  s2:=pg_temp.f5b_source(-2402);
  m:=pg_temp.f2a_marriage(-2401,s,'P-1',-2401,-2402,v_actor,1,1);
  par:=pg_temp.f2a_parent(-2401,s,-2403,-2404,NULL,v_actor);
  o:=pg_temp.f2a_marriage(-2402,s2,'P-9',-2409,-2410,v_actor,1,1);   -- anden kilde
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  SET LOCAL ROLE authenticated;
  pv:=red_preview_relation_decisions(-2401);
  PERFORM red_decide_relation_interpretations(-2401,pv->>'set_sha256');
  pv:=red_preview_relation_decisions(-2402);
  PERFORM red_decide_relation_interpretations(-2402,pv->>'set_sha256');
  RESET ROLE;
  m3:=pg_temp.f2a_marriage(-2401,s,'P-3',-2405,-2406,v_actor,1,1,false);   -- forbliver proposed
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  SELECT id INTO v_mid FROM private.interpretation_current WHERE interpretation_key=(m->'claim'->>'key')::uuid;
  SELECT id INTO v_pid FROM private.interpretation_current WHERE interpretation_key=(par->'claim'->>'key')::uuid;
  SELECT id INTO v_oid FROM private.interpretation_current WHERE interpretation_key=(o->'claim'->>'key')::uuid;
  items:=jsonb_build_array(jsonb_build_object('interpretation_id',v_mid::text,'family_id',(m->>'family')::bigint),
                           jsonb_build_object('interpretation_id',v_pid::text,'family_id',(par->>'family')::bigint));
  SET LOCAL ROLE authenticated;
  pv:=red_preview_relation_promotions(-2401,items);
  RESET ROLE;
  IF jsonb_array_length(pv->'items')<>2 OR EXISTS (SELECT 1 FROM jsonb_array_elements(pv->'items') i WHERE NOT (i->>'eligible')::boolean)
     OR pv->>'preview_sha256' !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: preview %', pv;
  END IF;

  -- negative elementer: reason_code i previewet (ikke en rejst fejl)
  SET LOCAL ROLE authenticated;
  IF red_preview_relation_promotions(-2401,jsonb_build_array(jsonb_build_object('interpretation_id',v_mid::text,'family_id',(par->>'family')::bigint)))
       #>>'{items,0,reason_code}' IS DISTINCT FROM 'RELATION_PROMOTION_FAMILY_MISMATCH'
     OR red_preview_relation_promotions(-2401,jsonb_build_array(jsonb_build_object('interpretation_id',m->'claim'->>'id','family_id',(m->>'family')::bigint)))
       #>>'{items,0,reason_code}' IS DISTINCT FROM 'RELATION_PROMOTION_NOT_CURRENT'
     OR red_preview_relation_promotions(-2401,jsonb_build_array(jsonb_build_object('interpretation_id',m3->'claim'->>'id','family_id',(m->>'family')::bigint)))
       #>>'{items,0,reason_code}' IS DISTINCT FROM 'RELATION_PROMOTION_NOT_ACCEPTED'
     OR red_preview_relation_promotions(-2401,jsonb_build_array(items->0,items->0))
       #>>'{items,0,reason_code}' IS DISTINCT FROM 'RELATION_PROMOTION_DUPLICATE_ITEM'
     OR red_preview_relation_promotions(-2401,jsonb_build_array(jsonb_build_object('interpretation_id',v_oid::text,'family_id',(o->>'family')::bigint)))
       #>>'{items,0,reason_code}' IS DISTINCT FROM 'RELATION_PROMOTION_SOURCE_MISMATCH' THEN
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: negative preview-elementer';
  END IF;
  -- forkert form ⇒ undtagelse (også et tomt objekt og et id uden for bigint)
  FOR items4 IN SELECT x FROM (VALUES ('[{"interpretation_id":"x"}]'::jsonb),('[{}]'::jsonb),('[]'::jsonb),(NULL::jsonb),
      (jsonb_build_array(jsonb_build_object('interpretation_id',v_mid::text,'family_id',9999999999999999999::numeric)))) t(x) LOOP
    BEGIN
      PERFORM red_preview_relation_promotions(-2401,items4);
      RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: forkert form godtaget %', items4;
    EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT;
      IF v_err NOT LIKE 'RELATION_PROMOTION_ITEMS_INVALID%' THEN RAISE; END IF;
    END;
  END LOOP;
  -- NULL-kilde ⇒ afvist i både preview og binding (ville ellers slå kildetjek og kildelås fra)
  BEGIN
    PERFORM red_preview_relation_promotions(NULL,items);
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: NULL-kilde godtaget i preview';
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT;
    IF v_err NOT LIKE 'RELATION_PROMOTION_INVALID%' THEN RAISE; END IF;
  END;
  BEGIN
    PERFORM red_promote_relation_interpretations_batch(NULL,items,pv->>'preview_sha256');
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: NULL-kilde godtaget i bindingen';
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT;
    IF v_err NOT LIKE 'RELATION_PROMOTION_INVALID%' THEN RAISE; END IF;
  END;
  -- forældet preview
  BEGIN
    PERFORM red_promote_relation_interpretations_batch(-2401,items,repeat('0',64));
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: forældet preview godtaget';
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT;
    IF v_err NOT LIKE 'RELATION_PROMOTION_PREVIEW_STALE%' THEN RAISE; END IF;
  END;
  -- binding
  v_batch:=red_promote_relation_interpretations_batch(-2401,items,pv->>'preview_sha256');
  RESET ROLE;
  IF v_batch IS NULL
     OR (SELECT count(*) FROM private.interpretation_promotion WHERE batch_id=v_batch AND target_type='family')<>2
     OR EXISTS (SELECT 1 FROM private.interpretation_promotion p WHERE p.batch_id=v_batch
                 AND (p.evidence->>'state_sha256' IS DISTINCT FROM private.relation_binding_state_sha256(p.interpretation_id)
                      OR NOT p.evidence ? 'vielse_fact_id' OR p.evidence->>'promotion_kind'<>'structural_family'
                      OR (p.evidence->>'family_id')::bigint<>p.target_id))
     OR (SELECT items_sha256 FROM private.interpretation_promotion_batch WHERE id=v_batch) !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: bindingerne';
  END IF;
  -- replay: samme kald ⇒ samme batch, ingen nye rækker; andet element-array ⇒ afvist; nyt preview ⇒ allerede bundet
  SET LOCAL ROLE authenticated;
  v_batch2:=red_promote_relation_interpretations_batch(-2401,items,pv->>'preview_sha256');
  RESET ROLE;
  IF v_batch2 IS DISTINCT FROM v_batch
     OR (SELECT count(*) FROM private.interpretation_promotion WHERE target_type='family' AND interpretation_id IN (v_mid,v_pid))<>2 THEN
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: replay';
  END IF;
  SET LOCAL ROLE authenticated;
  BEGIN
    PERFORM red_promote_relation_interpretations_batch(-2401,jsonb_build_array(items->1,items->0),pv->>'preview_sha256');
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: replay med andre elementer godtaget';
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT;
    IF v_err NOT LIKE 'RELATION_PROMOTION_REPLAY_MISMATCH%' THEN RAISE; END IF;
  END;
  -- samme previewhash og elementer under en anden kilde er ikke et replay (kilden indgår i digesten)
  BEGIN
    PERFORM red_promote_relation_interpretations_batch(-2402,items,pv->>'preview_sha256');
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: replay under anden kilde godtaget';
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT;
    IF v_err NOT LIKE 'RELATION_PROMOTION_REPLAY_MISMATCH%' THEN RAISE; END IF;
  END;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(red_preview_relation_promotions(-2401,items)->'items') i
              WHERE i->>'reason_code' IS DISTINCT FROM 'RELATION_PROMOTION_ALREADY_APPLIED') THEN
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: allerede bundet';
  END IF;
  -- den gamle assertion-vej afviser relationsfortolkningen
  IF red_preview_interpretation_promotions(jsonb_build_array(jsonb_build_object('interpretation_id',v_mid::text,
       'target_type','assertion','target_id',1)))#>>'{items,0,reason_code}' IS DISTINCT FROM 'EVIDENCE_PROMOTION_RULE_NOT_ACTIVE' THEN
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: assertion-vejen';
  END IF;
  RESET ROLE;
  -- ét familiemål pr. fortolkning (partielt unikt indeks)
  BEGIN
    INSERT INTO private.interpretation_promotion(interpretation_id,rule_key,rule_version,batch_id,target_type,target_id,evidence,
      promoted_by,promoted_by_name)
    SELECT p.interpretation_id,p.rule_key,p.rule_version,p.batch_id,'family',p.target_id,p.evidence,p.promoted_by,p.promoted_by_name
      FROM private.interpretation_promotion p WHERE p.interpretation_id=v_mid;
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: anden familiebinding godtaget';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;

  -- vielsesfaktummet er en del af det autoriserede preview
  m4:=pg_temp.f2a_marriage(-2401,s,'P-4',-2407,-2408,v_actor,1,1);
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  SET LOCAL ROLE authenticated;
  pv:=red_preview_relation_decisions(-2401);
  PERFORM red_decide_relation_interpretations(-2401,pv->>'set_sha256');
  RESET ROLE;
  SELECT id INTO v_m4 FROM private.interpretation_current WHERE interpretation_key=(m4->'claim'->>'key')::uuid;
  items4:=jsonb_build_array(jsonb_build_object('interpretation_id',v_m4::text,'family_id',(m4->>'family')::bigint));
  SET LOCAL ROLE authenticated;
  pv:=red_preview_relation_promotions(-2401,items4);
  RESET ROLE;
  v_old_hash:=pv->>'preview_sha256';
  IF pv#>>'{items,0,vielse_fact_id}' IS NOT NULL THEN RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: vielse uden faktum'; END IF;
  INSERT INTO fact(subjekt_type,subjekt_id,faktatype) VALUES ('family',(m4->>'family')::bigint,'vielse') RETURNING id INTO v_fact;
  SET LOCAL ROLE authenticated;
  BEGIN
    PERFORM red_promote_relation_interpretations_batch(-2401,items4,v_old_hash);
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: vielsesdrift godtaget';
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT;
    IF v_err NOT LIKE 'RELATION_PROMOTION_PREVIEW_STALE%' THEN RAISE; END IF;
  END;
  pv:=red_preview_relation_promotions(-2401,items4);
  IF (pv#>>'{items,0,vielse_fact_id}')::bigint IS DISTINCT FROM v_fact THEN RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: vielse i preview'; END IF;
  v_batch:=red_promote_relation_interpretations_batch(-2401,items4,pv->>'preview_sha256');
  RESET ROLE;
  IF (SELECT (evidence->>'vielse_fact_id')::bigint FROM private.interpretation_promotion WHERE batch_id=v_batch) IS DISTINCT FROM v_fact THEN
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: vielse i bindingen';
  END IF;
  RAISE NOTICE 'OK: binding af relationer';
END $relation_promote$;
ROLLBACK;

-- To sessioner for bindingen (spec §8). Parterne committes før BEGIN, så dblink-sessionen ser dem;
-- de slettes efter ROLLBACK. (a) en family_member-indsættelse venter på bindingens låse.
INSERT INTO person(id,levende,privat,status) VALUES (-2491,false,false,'2a lock') ON CONFLICT (id) DO NOTHING;
BEGIN;
\ir fixtures/relation-5b.sql
\ir fixtures/relation-2a.sql
DO $relation_promote_lock$
DECLARE v_actor uuid:='11000000-0000-0000-0000-0000002a0491'; s jsonb; m jsonb; pv jsonb; items jsonb; v_id uuid; v_err text;
  v_conn text:=format('dbname=%s port=%s host=%s',current_database(),current_setting('port'),
                      split_part(current_setting('unix_socket_directories'),',',1));
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  INSERT INTO person(id,levende,privat,status) VALUES (-2492,false,false,'2a');
  s:=pg_temp.f5b_source(-2491);
  m:=pg_temp.f2a_marriage(-2491,s,'PL-1',-2491,-2492,v_actor,1,1);
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  SET LOCAL ROLE authenticated;
  pv:=red_preview_relation_decisions(-2491);
  PERFORM red_decide_relation_interpretations(-2491,pv->>'set_sha256');
  RESET ROLE;
  SELECT id INTO v_id FROM private.interpretation_current WHERE interpretation_key=(m->'claim'->>'key')::uuid;
  items:=jsonb_build_array(jsonb_build_object('interpretation_id',v_id::text,'family_id',(m->>'family')::bigint));
  SET LOCAL ROLE authenticated;
  pv:=red_preview_relation_promotions(-2491,items);
  PERFORM red_promote_relation_interpretations_batch(-2491,items,pv->>'preview_sha256');
  RESET ROLE;
  BEGIN
    PERFORM dblink_connect('l2a_p',v_conn);
    PERFORM * FROM dblink('l2a_p','BEGIN; SET lock_timeout=''300ms''; INSERT INTO family(id,type) VALUES (-2491,''vielse''); '
      ||'INSERT INTO family_member(family_id,person_id,rolle) VALUES (-2491,-2491,''partner''); SELECT ''x''') AS t(x text);
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: indsættelse ventede ikke på bindingen';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT;
    PERFORM dblink_disconnect('l2a_p');
    IF v_err NOT LIKE '%lock timeout%' THEN RAISE; END IF;
  END;
  RAISE NOTICE 'OK: bindingens låse blokerer familieændringer';
END $relation_promote_lock$;
ROLLBACK;
DELETE FROM person WHERE id=-2491;

-- (b) en konkurrerende batch holder kildelåsen, (c) en identitetsgenafgørelse holder ægtefællens personrække
-- (FOR NO KEY UPDATE; se Task 3's tilsvarende test). Bindingen fejler lukket med 0 bindinger og 0 batches.
-- Påstanden accepteres her direkte med red_decide_interpretation: red_decide_relation_interpretations tager
-- kildens advisory-lås for resten af hovedtransaktionen, og så ville dblink-sessionen i (b) vente på
-- hovedsessionen, mens den venter synkront på dblink (uopdagelig hængning). lock_timeout i dblink er værn.
INSERT INTO person(id,levende,privat,status) VALUES (-2494,false,false,'2a lock') ON CONFLICT (id) DO NOTHING;
BEGIN;
\ir fixtures/relation-5b.sql
\ir fixtures/relation-2a.sql
DO $relation_promote_lock_wait$
DECLARE v_actor uuid:='11000000-0000-0000-0000-0000002a0493'; s jsonb; m jsonb; pv jsonb; items jsonb; v_id uuid; v_state text;
  v_case text; v_lock text;
  v_conn text:=format('dbname=%s port=%s host=%s',current_database(),current_setting('port'),
                      split_part(current_setting('unix_socket_directories'),',',1));
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  INSERT INTO person(id,levende,privat,status) VALUES (-2493,false,false,'2a');
  s:=pg_temp.f5b_source(-2493);
  m:=pg_temp.f2a_marriage(-2493,s,'PL-2',-2493,-2494,v_actor,1,1);
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  SET LOCAL ROLE authenticated;
  PERFORM red_decide_interpretation((m->'claim'->>'id')::uuid,1,'accepted','{"note":"2a låsetest"}');
  RESET ROLE;
  SELECT id INTO v_id FROM private.interpretation_current WHERE interpretation_key=(m->'claim'->>'key')::uuid;
  items:=jsonb_build_array(jsonb_build_object('interpretation_id',v_id::text,'family_id',(m->>'family')::bigint));
  SET LOCAL ROLE authenticated;
  pv:=red_preview_relation_promotions(-2493,items);
  RESET ROLE;
  FOR v_case,v_lock IN VALUES
    ('konkurrerende batch','SET lock_timeout=''5s''; SELECT pg_advisory_xact_lock(hashtextextended(''daa-identity-candidates:-2493'',0))::text'),
    ('identitetsgenafgørelse','SET lock_timeout=''5s''; SELECT 1::text FROM person WHERE id=-2494 FOR NO KEY UPDATE') LOOP
    v_state:=NULL;
    PERFORM dblink_connect('l2a_w',v_conn);
    PERFORM dblink_exec('l2a_w','BEGIN');
    PERFORM * FROM dblink('l2a_w',v_lock) AS t(x text);
    BEGIN
      SET LOCAL ROLE authenticated;
      SET LOCAL lock_timeout='300ms';
      BEGIN
        PERFORM red_promote_relation_interpretations_batch(-2493,items,pv->>'preview_sha256');
      EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_state=RETURNED_SQLSTATE;
      END;
      RESET ROLE;
      SET LOCAL lock_timeout=0;
    EXCEPTION WHEN OTHERS THEN
      PERFORM dblink_exec('l2a_w','ROLLBACK'); PERFORM dblink_disconnect('l2a_w'); RAISE;
    END;
    PERFORM dblink_exec('l2a_w','ROLLBACK'); PERFORM dblink_disconnect('l2a_w');
    IF v_state IS DISTINCT FROM '55P03'
       OR EXISTS (SELECT 1 FROM private.interpretation_promotion WHERE interpretation_id=v_id)
       OR EXISTS (SELECT 1 FROM private.interpretation_promotion_batch WHERE preview_hash=pv->>'preview_sha256') THEN
      RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: % — ventede ikke eller efterlod delvise writes (%)', v_case, v_state;
    END IF;
  END LOOP;
  RAISE NOTICE 'OK: bindingen venter på konkurrerende batch og identitetsgenafgørelse';
END $relation_promote_lock_wait$;
ROLLBACK;
DELETE FROM person WHERE id=-2494;

-- ---------- 2b-i Task 1: unikhed pr. fortolkning og tilstand (spec §4.1) ----------
BEGIN;
\ir fixtures/relation-5b.sql
\ir fixtures/relation-2a.sql
DO $rebind_unique$
DECLARE v_actor uuid:='11000000-0000-0000-0000-0000002b0101'; s jsonb; m jsonb; pv jsonb; v_mid uuid; v_batch uuid;
  v_row private.interpretation_promotion%ROWTYPE; v_bad jsonb;
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  INSERT INTO person(id,levende,privat,status) SELECT g,false,false,'2bi' FROM generate_series(-21120,-21101) g;
  s:=pg_temp.f5b_source(-21101);
  m:=pg_temp.f2a_marriage(-21101,s,'U-1',-21101,-21102,v_actor,1,1);
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  SET LOCAL ROLE authenticated;
  pv:=red_preview_relation_decisions(-21101);
  PERFORM red_decide_relation_interpretations(-21101,pv->>'set_sha256');
  RESET ROLE;
  SELECT id INTO v_mid FROM private.interpretation_current WHERE interpretation_key=(m->'claim'->>'key')::uuid;
  SET LOCAL ROLE authenticated;
  pv:=red_preview_relation_promotions(-21101,jsonb_build_array(jsonb_build_object('interpretation_id',v_mid::text,'family_id',(m->>'family')::bigint)));
  v_batch:=red_promote_relation_interpretations_batch(-21101,jsonb_build_array(jsonb_build_object('interpretation_id',v_mid::text,'family_id',(m->>'family')::bigint)),pv->>'preview_sha256');
  RESET ROLE;
  SELECT * INTO v_row FROM private.interpretation_promotion WHERE batch_id=v_batch;

  -- CHECK: manglende nøgle, JSON-null, tal og forkert format afvises (spec §4.1; Codex r1 #1)
  FOREACH v_bad IN ARRAY ARRAY[v_row.evidence-'state_sha256', jsonb_set(v_row.evidence,'{state_sha256}','null'),
                               jsonb_set(v_row.evidence,'{state_sha256}','1'), jsonb_set(v_row.evidence,'{state_sha256}','"abc"')] LOOP
    BEGIN
      INSERT INTO private.interpretation_promotion(interpretation_id,rule_key,rule_version,batch_id,target_type,target_id,evidence,promoted_by,promoted_by_name)
      VALUES (v_row.interpretation_id,v_row.rule_key,v_row.rule_version,v_row.batch_id,'family',v_row.target_id,v_bad,v_row.promoted_by,v_row.promoted_by_name);
      RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: familiebinding uden gyldig hash godtaget %', v_bad;
    EXCEPTION WHEN check_violation THEN NULL;
    END;
  END LOOP;
  -- samme fortolkning og familie med en ny tilstand er tilladt (genbinding, spec §4.1; Codex r1 #2)
  INSERT INTO private.interpretation_promotion(interpretation_id,rule_key,rule_version,batch_id,target_type,target_id,evidence,promoted_by,promoted_by_name)
  VALUES (v_row.interpretation_id,v_row.rule_key,v_row.rule_version,v_row.batch_id,'family',v_row.target_id,
          jsonb_set(v_row.evidence,'{state_sha256}',to_jsonb(repeat('e',64))),v_row.promoted_by,v_row.promoted_by_name);
  -- samme tilstand to gange afvises
  BEGIN
    INSERT INTO private.interpretation_promotion(interpretation_id,rule_key,rule_version,batch_id,target_type,target_id,evidence,promoted_by,promoted_by_name)
    VALUES (v_row.interpretation_id,v_row.rule_key,v_row.rule_version,v_row.batch_id,'family',v_row.target_id,
            jsonb_set(v_row.evidence,'{state_sha256}',to_jsonb(repeat('e',64))),v_row.promoted_by,v_row.promoted_by_name);
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: to bindinger med samme tilstand godtaget';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;
  -- kataloget: den hidtidige regel består for ikke-familiemål, og de gamle regler er væk
  IF NOT EXISTS (SELECT 1 FROM pg_index i JOIN pg_class c ON c.oid=i.indexrelid
                  WHERE c.relname='interpretation_promotion_one_target_per_interpretation' AND i.indisunique
                    AND pg_get_expr(i.indpred,i.indrelid) LIKE '%target_type%<>%family%')
     OR EXISTS (SELECT 1 FROM pg_class WHERE relname='interpretation_promotion_one_family_per_interpretation')
     OR EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='private.interpretation_promotion'::regclass AND contype='u') THEN
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: unikhedsreglerne i kataloget';
  END IF;
  RAISE NOTICE 'OK: unikhed pr. fortolkning og tilstand';
END $rebind_unique$;
ROLLBACK;

-- ---------- 2b-i Task 2: genbinding gennem previewet (spec §4.2-§4.4) ----------
BEGIN;
\ir fixtures/relation-5b.sql
\ir fixtures/relation-2a.sql
DO $rebind_preview$
DECLARE v_actor uuid:='11000000-0000-0000-0000-0000002b0201'; s jsonb; m jsonb; par jsonb; pv jsonb; items jsonb; pitems jsonb;
  v_mid uuid; v_pid uuid; v_b1 uuid; v_b2 uuid; v_old uuid; v_new uuid; v_first_state text; n int;
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  INSERT INTO person(id,levende,privat,status) SELECT g,false,false,'2bi' FROM generate_series(-21240,-21201) g;
  s:=pg_temp.f5b_source(-21201);
  m:=pg_temp.f2a_marriage(-21201,s,'R-1',-21201,-21202,v_actor,2,1);         -- bogens nr. 2, familiens 1
  -- forælderbinding: -21210 er forælder til -21203 i familien med -21211 (Review Focus 2: en rettelse af
  -- forælderens partnerrække gør forælderbindingen forældet, og den genbindes)
  par:=pg_temp.f2a_parent(-21201,s,-21203,-21210,-21211,v_actor);
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  SET LOCAL ROLE authenticated;
  pv:=red_preview_relation_decisions(-21201);
  PERFORM red_decide_relation_interpretations(-21201,pv->>'set_sha256');
  RESET ROLE;
  SELECT id INTO v_mid FROM private.interpretation_current WHERE interpretation_key=(m->'claim'->>'key')::uuid;
  SELECT id INTO v_pid FROM private.interpretation_current WHERE interpretation_key=(par->'claim'->>'key')::uuid;
  items:=jsonb_build_array(jsonb_build_object('interpretation_id',v_mid::text,'family_id',(m->>'family')::bigint));
  SET LOCAL ROLE authenticated;
  pv:=red_preview_relation_promotions(-21201,items);
  IF pv#>>'{items,0,supersedes_promotion_id}' IS NOT NULL OR NOT (pv->'items'->0) ? 'supersedes_promotion_id' THEN
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: første binding skal have supersedes=null %', pv;
  END IF;
  v_b1:=red_promote_relation_interpretations_batch(-21201,items,pv->>'preview_sha256');
  RESET ROLE;
  SELECT id,evidence->>'state_sha256' INTO v_old,v_first_state FROM private.interpretation_promotion WHERE batch_id=v_b1;

  -- ret familiens nummer til bogens: kilden skjules (tilstanden er forældet)
  SET LOCAL ROLE authenticated;
  PERFORM red_set_familie_ordinal((m->>'family')::bigint,-21201,'partner',2);
  RESET ROLE;
  PERFORM set_config('app.change_set_id','',true);
  -- frisk sti = kontrakt 1, hvor public_family_sources altid giver 0; synligheden prøves i test-family-sources.sql
  IF private.relation_binding_state_sha256(v_mid) IS NOT DISTINCT FROM v_first_state THEN
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: tilstanden ændrede sig ikke';
  END IF;
  -- preview: egnet, med supersedes = den gamle binding
  SET LOCAL ROLE authenticated;
  pv:=red_preview_relation_promotions(-21201,items);
  IF NOT (pv#>>'{items,0,eligible}')::boolean OR pv#>>'{items,0,supersedes_promotion_id}' IS DISTINCT FROM v_old::text THEN
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: genbindingspreview %', pv;
  END IF;
  v_b2:=red_promote_relation_interpretations_batch(-21201,items,pv->>'preview_sha256');
  RESET ROLE;
  SELECT id INTO v_new FROM private.interpretation_promotion WHERE batch_id=v_b2;
  IF (SELECT count(*) FROM private.interpretation_promotion WHERE interpretation_id=v_mid AND target_type='family')<>2
     OR (SELECT evidence->>'supersedes_promotion_id' FROM private.interpretation_promotion WHERE id=v_new) IS DISTINCT FROM v_old::text
     OR (SELECT evidence->>'state_sha256' FROM private.interpretation_promotion WHERE id=v_old) IS DISTINCT FROM v_first_state THEN
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: genbindingens rækker';
  END IF;
  -- identisk genkald: samme batch, ingen tredje række; nyt preview: ALREADY_APPLIED
  SET LOCAL ROLE authenticated;
  IF red_promote_relation_interpretations_batch(-21201,items,pv->>'preview_sha256') IS DISTINCT FROM v_b2
     OR red_preview_relation_promotions(-21201,items)#>>'{items,0,reason_code}' IS DISTINCT FROM 'RELATION_PROMOTION_ALREADY_APPLIED' THEN
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: genkald efter genbinding';
  END IF;
  RESET ROLE;
  IF (SELECT count(*) FROM private.interpretation_promotion WHERE interpretation_id=v_mid AND target_type='family')<>2 THEN
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: tredje række';
  END IF;
  IF (SELECT evidence->>'state_sha256' FROM private.interpretation_promotion WHERE id=v_new)
       IS DISTINCT FROM private.relation_binding_state_sha256(v_mid) THEN
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: genbindingen passer ikke den nuværende tilstand';
  END IF;

  -- tilbage-rettelse: ordinal tilbage til 1 ⇒ den gamle binding passer igen ⇒ ALREADY_APPLIED, intet skrives
  SET LOCAL ROLE authenticated;
  PERFORM red_set_familie_ordinal((m->>'family')::bigint,-21201,'partner',1);
  PERFORM set_config('app.change_set_id','',true);
  IF red_preview_relation_promotions(-21201,items)#>>'{items,0,reason_code}' IS DISTINCT FROM 'RELATION_PROMOTION_ALREADY_APPLIED' THEN
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: tilbage-rettelse';
  END IF;
  RESET ROLE;

  -- ny identitetsversion til samme person ⇒ genbinding
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  SET LOCAL ROLE authenticated;
  PERFORM red_afgoer_source_persona((m->>'spouse_persona')::uuid,1,'same',-21202,'2b-i test: ny version','{}');
  pv:=red_preview_relation_promotions(-21201,items);
  IF NOT (pv#>>'{items,0,eligible}')::boolean OR pv#>>'{items,0,supersedes_promotion_id}' IS NULL THEN
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: ny identitetsversion %', pv;
  END IF;
  PERFORM red_promote_relation_interpretations_batch(-21201,items,pv->>'preview_sha256');
  RESET ROLE;

  -- forælderbindingen i samme familie (Review Focus 2): bundet, gjort forældet af ordinal-rettelsen, genbundet
  pitems:=jsonb_build_array(jsonb_build_object('interpretation_id',v_pid::text,'family_id',(par->>'family')::bigint));
  SET LOCAL ROLE authenticated;
  pv:=red_preview_relation_promotions(-21201,pitems);
  PERFORM red_promote_relation_interpretations_batch(-21201,pitems,pv->>'preview_sha256');
  PERFORM red_set_familie_ordinal((par->>'family')::bigint,-21210,'partner',3);
  PERFORM set_config('app.change_set_id','',true);
  pv:=red_preview_relation_promotions(-21201,pitems);
  IF NOT (pv#>>'{items,0,eligible}')::boolean OR pv#>>'{items,0,supersedes_promotion_id}' IS NULL THEN
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: foraelder_samme_familie %', pv;
  END IF;
  RESET ROLE;

  -- strukturen flyttet til en anden familie ⇒ REBIND_FAMILY_CHANGED
  DELETE FROM family_member WHERE family_id=(m->>'family')::bigint AND person_id=-21202;
  PERFORM pg_temp.f5b_family(-21201,-21202,1);   -- ny familie med samme par
  items:=jsonb_build_array(jsonb_build_object('interpretation_id',v_mid::text,
        'family_id',(private.relation_binding_state(v_mid)#>>'{family,family_id}')::bigint));   -- som ejer (private)
  SET LOCAL ROLE authenticated;
  pv:=red_preview_relation_promotions(-21201,items);
  RESET ROLE;
  IF pv#>>'{items,0,reason_code}' IS DISTINCT FROM 'RELATION_PROMOTION_REBIND_FAMILY_CHANGED' THEN
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: anden familie %', pv;
  END IF;
  IF (SELECT count(*) FROM private.interpretation_promotion_batch b
       WHERE b.id IN (SELECT batch_id FROM private.interpretation_promotion WHERE interpretation_id=v_mid))<>3 THEN
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: antal batches';
  END IF;
  RAISE NOTICE 'OK: genbinding gennem previewet';
END $rebind_preview$;
ROLLBACK;
