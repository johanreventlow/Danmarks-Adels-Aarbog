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
  v_newfam bigint; v_ver int; v_key uuid; v_lastb uuid; v_reo uuid; r private.interpretation%ROWTYPE;
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

  -- strukturen flyttet til en anden familie ⇒ DECISION_FAMILY_CHANGED (review trin B, 1d.3b-01: afgørelsens familie
  -- prøves før genbindingens; REBIND_FAMILY_CHANGED rammer herefter kun en binding i en anden familie end afgørelsens)
  DELETE FROM family_member WHERE family_id=(m->>'family')::bigint AND person_id=-21202;
  PERFORM pg_temp.f5b_family(-21201,-21202,1);   -- ny familie med samme par
  items:=jsonb_build_array(jsonb_build_object('interpretation_id',v_mid::text,
        'family_id',(private.relation_binding_state(v_mid)#>>'{family,family_id}')::bigint));   -- som ejer (private)
  SET LOCAL ROLE authenticated;
  pv:=red_preview_relation_promotions(-21201,items);
  RESET ROLE;
  IF pv#>>'{items,0,reason_code}' IS DISTINCT FROM 'RELATION_PROMOTION_DECISION_FAMILY_CHANGED' THEN
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: anden familie %', pv;
  END IF;
  IF (SELECT count(*) FROM private.interpretation_promotion_batch b
       WHERE b.id IN (SELECT batch_id FROM private.interpretation_promotion WHERE interpretation_id=v_mid))<>3 THEN
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: antal batches';
  END IF;
  RAISE NOTICE 'OK: genbinding gennem previewet';

  -- #248 rute A (spec §3.1-§3.2): genåbn → afgør → bind i den nye familie. public_family_sources giver 0 i denne
  -- base (kontrakt 1); »gældende« prøves med læserens definition: gældende version, tilstandens sha og familie.
  v_newfam:=(private.relation_binding_state(v_mid)#>>'{family,family_id}')::bigint;
  SELECT version,interpretation_key INTO v_ver,v_key FROM private.interpretation WHERE id=v_mid;
  SELECT id INTO v_lastb FROM private.interpretation_promotion WHERE interpretation_id=v_mid AND target_type='family'
   ORDER BY promoted_at DESC,id DESC LIMIT 1;
  SELECT count(*) INTO n FROM private.interpretation_promotion WHERE interpretation_id=v_pid;
  SET LOCAL ROLE authenticated;
  v_reo:=red_genaabn_relation_interpretation(v_mid,v_ver,'test: familieskift',
    jsonb_build_object('basis','human_sheet','line',1,'sheet_sha256',repeat('a',64),'rows_sha256',repeat('b',64)));
  RESET ROLE;
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  SELECT * INTO r FROM private.interpretation WHERE id=v_reo;
  IF r.status<>'proposed' OR r.version<>v_ver+1 OR r.supersedes_id<>v_mid OR r.decided_by IS NOT NULL OR r.decision_evidence<>'{}'
     OR v_reo<>private.content_uuid('interpretation-reopen',jsonb_build_object('interpretation_key',v_key,'version',v_ver+1))
     OR (SELECT count(*) FROM private.interpretation_observation WHERE interpretation_id=v_reo)
        <>(SELECT count(*) FROM private.interpretation_observation WHERE interpretation_id=v_mid) THEN
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: genåbnet version %',to_jsonb(r);
  END IF;
  IF (SELECT count(*) FROM private.relation_reopen WHERE to_interpretation_id=v_reo AND from_interpretation_id=v_mid
        AND interpretation_key=v_key AND superseded_promotion_id=v_lastb AND from_family_id=(m->>'family')::bigint
        AND to_family_id=v_newfam AND spouse_source_persona_id=(m->>'spouse_persona')::uuid AND spouse_identity_version=2
        AND context->>'basis'='human_sheet')<>1 THEN
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: relation_reopen';
  END IF;
  SET LOCAL ROLE authenticated;
  pv:=red_preview_relation_decisions(-21201);
  IF (pv->>'count')::int<>1 THEN RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: genåbnet ikke i beslutningsmængden %',pv; END IF;
  PERFORM red_decide_relation_interpretations(-21201,pv->>'set_sha256');
  RESET ROLE;
  SELECT id INTO v_new FROM private.interpretation_current WHERE interpretation_key=v_key;
  items:=jsonb_build_array(jsonb_build_object('interpretation_id',v_new::text,'family_id',v_newfam));
  SET LOCAL ROLE authenticated;
  pv:=red_preview_relation_promotions(-21201,items);
  IF NOT (pv#>>'{items,0,eligible}')::boolean OR pv#>>'{items,0,supersedes_promotion_id}' IS NOT NULL THEN
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: binding efter genåbning %',pv;
  END IF;
  PERFORM red_promote_relation_interpretations_batch(-21201,items,pv->>'preview_sha256');
  RESET ROLE;
  IF (SELECT count(*) FROM private.interpretation_current ic JOIN private.interpretation_promotion x
        ON x.interpretation_id=ic.id AND x.target_type='family'
       WHERE ic.interpretation_key=v_key AND x.target_id=v_newfam
         AND x.evidence->>'state_sha256'=private.reimport_canonical_json_sha256(private.relation_binding_state(ic.id)))<>1
     OR EXISTS (SELECT 1 FROM private.interpretation_current ic JOIN private.interpretation_promotion x
                  ON x.interpretation_id=ic.id AND x.target_type='family'
                 WHERE ic.interpretation_key=v_key AND x.target_id=(m->>'family')::bigint)
     -- forælderbindingen (anden nøgle) er urørt af genåbningen
     OR (SELECT id FROM private.interpretation_current WHERE interpretation_key=(par->'claim'->>'key')::uuid)<>v_pid
     OR (SELECT count(*) FROM private.interpretation_promotion WHERE interpretation_id=v_pid)<>n THEN
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: gældende efter genåbning';
  END IF;
  RAISE NOTICE 'OK: genåbning ved familieskift';
END $rebind_preview$;
ROLLBACK;

-- ---------- #248 rute A (spec §3.3): to ægtefæller i samme post afgjort til samme person ----------
BEGIN;
\ir fixtures/relation-5b.sql
\ir fixtures/relation-2a.sql
DO $dobbeltmaal_menneskevej$
DECLARE v_actor uuid:='11000000-0000-0000-0000-000000248001'; s jsonb; p jsonb; c1 jsonb; c2 jsonb; sp1 uuid; sp2 uuid;
  v_at timestamptz:=clock_timestamp(); v_id1 uuid; v_id2 uuid;
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  INSERT INTO person(id,levende,privat,status) SELECT g,false,false,'248' FROM generate_series(-24810,-24801) g;
  s:=pg_temp.f5b_source(-24801);
  p:=pg_temp.f5b_post(-24801,s,'N-1','Hoved N. g. 1° m. Navnefælle. g. 2° m. Navnefælle.',
     ARRAY['Hoved N.','g. 1° m. Navnefælle.','g. 2° m. Navnefælle.'],-24801,v_actor);
  PERFORM pg_temp.f2a_event_for_state((p->>'principal')::uuid);
  c1:=pg_temp.f5b_claim(-24801,s,'relation.marriage',(p->'clauses'->>1)::uuid,'g. 1° m. Navnefælle.');
  c2:=pg_temp.f5b_claim(-24801,s,'relation.marriage',(p->'clauses'->>2)::uuid,'g. 2° m. Navnefælle.');
  sp1:=pg_temp.f5b_spouse(-24801,s,p,c1,(p->'clauses'->>1)::uuid,'Navnefælle',1);
  sp2:=pg_temp.f5b_spouse(-24801,s,p,c2,(p->'clauses'->>2)::uuid,'Navnefælle',2);
  -- begge ægtefæller accepteret til samme person (#248's mønster); én familie med hovedpersonen
  INSERT INTO private.source_persona_identity_event(source_persona_id,canonical_person_id,decision_status,version,evidence,
    decided_by,decided_by_name,decided_at)
    VALUES (sp1,-24802,'accepted',1,'{"fixture":"248"}',v_actor,'fixture',v_at),(sp2,-24802,'accepted',1,'{"fixture":"248"}',v_actor,'fixture',v_at);
  INSERT INTO private.source_persona_identity(source_persona_id,canonical_person_id,decision_status,version,evidence,
    decided_by,decided_by_name,decided_at)
    VALUES (sp1,-24802,'accepted',1,'{"fixture":"248"}',v_actor,'fixture',v_at),(sp2,-24802,'accepted',1,'{"fixture":"248"}',v_actor,'fixture',v_at);
  PERFORM pg_temp.f5b_family(-24801,-24802,1);
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  v_id1:=(c1->>'id')::uuid; v_id2:=(c2->>'id')::uuid;
  IF private.relation_binding_state(v_id1) IS NOT NULL OR private.relation_binding_state(v_id2) IS NOT NULL THEN
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: dobbeltmål giver en tilstand';
  END IF;
  -- kontrol: den anden ægtefælle afgøres igen til en anden person med egen familie ⇒ begge tilstande findes
  PERFORM pg_temp.f5b_family(-24801,-24803,2);
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  SET LOCAL ROLE authenticated;
  PERFORM red_afgoer_source_persona(sp2,1,'same',-24803,'#248 test: anden person','{}');
  RESET ROLE;
  IF private.relation_binding_state(v_id1) IS NULL OR private.relation_binding_state(v_id2) IS NULL
     OR (private.relation_binding_state(v_id2)->>'counterpart_person_id')::bigint<>-24803 THEN
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: dobbeltmål-kontrol';
  END IF;
  -- kontrol: en ægtefælle i en ANDEN post accepteret til samme person som sp1 er ikke et dobbeltmål
  p:=pg_temp.f5b_post(-24801,s,'N-2','Anden N. g. m. Navnefælle.',ARRAY['Anden N.','g. m. Navnefælle.'],-24804,v_actor);
  PERFORM pg_temp.f2a_event_for_state((p->>'principal')::uuid);
  c2:=pg_temp.f5b_claim(-24801,s,'relation.marriage',(p->'clauses'->>1)::uuid,'g. m. Navnefælle.');
  sp2:=pg_temp.f5b_spouse(-24801,s,p,c2,(p->'clauses'->>1)::uuid,'Navnefælle',1);
  INSERT INTO private.source_persona_identity_event(source_persona_id,canonical_person_id,decision_status,version,evidence,
    decided_by,decided_by_name,decided_at) VALUES (sp2,-24802,'accepted',1,'{"fixture":"248"}',v_actor,'fixture',v_at);
  INSERT INTO private.source_persona_identity(source_persona_id,canonical_person_id,decision_status,version,evidence,
    decided_by,decided_by_name,decided_at) VALUES (sp2,-24802,'accepted',1,'{"fixture":"248"}',v_actor,'fixture',v_at);
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  IF private.relation_binding_state(v_id1) IS NULL
     OR (private.relation_binding_state(v_id1)->>'counterpart_person_id')::bigint<>-24802 THEN
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: anden post ramt af vagten';
  END IF;
  RAISE NOTICE 'OK: dobbeltmål på menneskevejen';
END $dobbeltmaal_menneskevej$;
ROLLBACK;

-- ---------- #248 efter forældelse (6c-3a, spec 2026-11-07-trin6c3-a6b-resten-design.md §4.7 pkt. 2) ----------
-- En rival, hvis ægteskabspåstand er forældet af en kildetekst-revision, er ikke længere et dobbeltmål; en rival med
-- en levende (proposed) påstand er det stadig.
BEGIN;
\ir fixtures/relation-5b.sql
\ir fixtures/relation-2a.sql
DO $dobbeltmaal_foraeldet$
DECLARE v_actor uuid:='11000000-0000-0000-0000-000000248031'; s jsonb; p jsonb; c1 jsonb; c2 jsonb; sp1 uuid; sp2 uuid;
  v_at timestamptz:=clock_timestamp(); v_id1 uuid;
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  INSERT INTO person(id,levende,privat,status) SELECT g,false,false,'248' FROM generate_series(-24880,-24871) g;
  s:=pg_temp.f5b_source(-24871);
  p:=pg_temp.f5b_post(-24871,s,'N-3','Hoved N. g. 1° m. Navnefælle. g. 2° m. Navnefælle.',
     ARRAY['Hoved N.','g. 1° m. Navnefælle.','g. 2° m. Navnefælle.'],-24871,v_actor);
  PERFORM pg_temp.f2a_event_for_state((p->>'principal')::uuid);
  c1:=pg_temp.f5b_claim(-24871,s,'relation.marriage',(p->'clauses'->>1)::uuid,'g. 1° m. Navnefælle.');
  c2:=pg_temp.f5b_claim(-24871,s,'relation.marriage',(p->'clauses'->>2)::uuid,'g. 2° m. Navnefælle.');
  sp1:=pg_temp.f5b_spouse(-24871,s,p,c1,(p->'clauses'->>1)::uuid,'Navnefælle',1);
  sp2:=pg_temp.f5b_spouse(-24871,s,p,c2,(p->'clauses'->>2)::uuid,'Navnefælle',2);
  INSERT INTO private.source_persona_identity_event(source_persona_id,canonical_person_id,decision_status,version,evidence,
    decided_by,decided_by_name,decided_at)
    VALUES (sp1,-24872,'accepted',1,'{"fixture":"248"}',v_actor,'fixture',v_at),(sp2,-24872,'accepted',1,'{"fixture":"248"}',v_actor,'fixture',v_at);
  INSERT INTO private.source_persona_identity(source_persona_id,canonical_person_id,decision_status,version,evidence,
    decided_by,decided_by_name,decided_at)
    VALUES (sp1,-24872,'accepted',1,'{"fixture":"248"}',v_actor,'fixture',v_at),(sp2,-24872,'accepted',1,'{"fixture":"248"}',v_actor,'fixture',v_at);
  PERFORM pg_temp.f5b_family(-24871,-24872,1);
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  v_id1:=(c1->>'id')::uuid;
  -- rivalen sp2 står på en proposed påstand: dobbeltmål som i dag
  IF private.relation_binding_state(v_id1) IS NOT NULL THEN
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: proposed rival giver en tilstand';
  END IF;
  -- revisionen forælder rivalens påstand (som forældelsen i revisions-writeren)
  PERFORM private.supersede_for_text_revision(ARRAY[(c2->>'key')::uuid],v_actor,'fixture','{"fixture":"248"}');
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  IF (SELECT status FROM private.interpretation_current WHERE interpretation_key=(c2->>'key')::uuid)<>'superseded' THEN
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: rivalens påstand er ikke forældet';
  END IF;
  IF private.relation_binding_state(v_id1) IS NULL
     OR (private.relation_binding_state(v_id1)->>'counterpart_person_id')::bigint<>-24872 THEN
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: forældet rival blokerer %',private.relation_binding_state(v_id1);
  END IF;
  RAISE NOTICE 'OK: forældet rival er ikke et dobbeltmål';
END $dobbeltmaal_foraeldet$;
ROLLBACK;

-- ---------- #248 rute A (spec §3.1, §5): genåbningens afvisninger ----------
BEGIN;
\ir fixtures/relation-5b.sql
\ir fixtures/relation-2a.sql
DO $genaabn_negativ$
DECLARE v_actor uuid:='11000000-0000-0000-0000-000000248021'; s jsonb; m jsonb:='{}'; par jsonb; pv jsonb; items jsonb:='[]';
  k text; v_err text; v_case text; v_expect text; v_id uuid; v_ver int; v_ctx jsonb; v_note text; v_n int; v_reo uuid;
  ctx jsonb:=jsonb_build_object('basis','human_sheet','line',1,'sheet_sha256',repeat('a',64),'rows_sha256',repeat('b',64));
  v_occ uuid; v_help uuid;
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  INSERT INTO person(id,levende,privat,status) SELECT g,false,false,'248' FROM generate_series(-24860,-24821) g;
  s:=pg_temp.f5b_source(-24821);
  -- g1 samme familie · g2 flyttet (hovedcasen) · g3 ægtefælle unresolved · g4 aldrig bundet · g5 uafgjort · g6 klausul revideret
  FOREACH k IN ARRAY ARRAY['g1','g2','g3','g4','g5','g6'] LOOP
    m:=m||jsonb_build_object(k,pg_temp.f2a_marriage(-24821,s,'N-'||k,-24820-2*substr(k,2)::int,-24821-2*substr(k,2)::int,
                                                    v_actor,1,1,k<>'g5'));
  END LOOP;
  par:=pg_temp.f2a_parent(-24821,s,-24850,-24851,-24852,v_actor);
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  SET LOCAL ROLE authenticated;
  pv:=red_preview_relation_decisions(-24821);
  PERFORM red_decide_relation_interpretations(-24821,pv->>'set_sha256');
  RESET ROLE;
  FOREACH k IN ARRAY ARRAY['g1','g2','g3','g6'] LOOP
    items:=items||jsonb_build_object('interpretation_id',(SELECT id::text FROM private.interpretation_current
                                                         WHERE interpretation_key=(m->k->'claim'->>'key')::uuid),
                                     'family_id',(m->k->>'family')::bigint);
  END LOOP;
  SET LOCAL ROLE authenticated;
  pv:=red_preview_relation_promotions(-24821,items);
  PERFORM red_promote_relation_interpretations_batch(-24821,items,pv->>'preview_sha256');
  RESET ROLE;
  -- strukturen flyttes til en ny familie for g2, g4 og g6
  FOREACH k IN ARRAY ARRAY['g2','g4','g6'] LOOP
    DELETE FROM family_member WHERE family_id=(m->k->>'family')::bigint AND person_id=-24821-2*substr(k,2)::int;
    PERFORM pg_temp.f5b_family(-24820-2*substr(k,2)::int,-24821-2*substr(k,2)::int,1);
  END LOOP;
  SET LOCAL ROLE authenticated;
  PERFORM red_afgoer_source_persona((m->'g3'->>'spouse_persona')::uuid,1,'unresolved',NULL,'#248 test: uklart','{}');
  RESET ROLE;
  -- g6: klausulsættet revideres (sæt 2 under samme helpost); den kopierede observationslink er ikke længere gældende
  SELECT o.occurrence_id,o.parent_observation_id INTO v_occ,v_help FROM private.source_observation o
   WHERE o.id=(m->'g6'->'post'->'clauses'->>1)::uuid;
  INSERT INTO private.source_observation(occurrence_id,observation_kind,page_from,page_to,char_from,char_to,verbatim_text,
    quality_status,extraction_method,extraction_run_id,parent_observation_id,post_char_from,post_char_to,clause_ordinal,
    clause_classification,clause_flags,clause_set_seq)
    VALUES (v_occ,'clause',10,10,1000,1010,'Anna Alfa.','clear','clause_segment_v1',(s->>'run')::uuid,v_help,0,10,1,
      'record_text','[]'::jsonb,2);
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;

  FOR v_case,v_expect IN SELECT * FROM (VALUES
      ('samme_familie','RELATION_REOPEN_NOT_NEEDED'),('null_tilstand','RELATION_REOPEN_STATE_INVALID'),
      ('ikke_aegteskab','RELATION_REOPEN_NOT_ELIGIBLE'),('proposed','RELATION_REOPEN_NOT_ELIGIBLE'),
      ('ikke_gaeldende','RELATION_REOPEN_NOT_ELIGIBLE'),('forkert_version','RELATION_REOPEN_VERSION_MISMATCH'),
      ('kontekst_basis','RELATION_REOPEN_CONTEXT_INVALID'),('kontekst_ekstra','RELATION_REOPEN_CONTEXT_INVALID'),
      ('kontekst_linje','RELATION_REOPEN_CONTEXT_INVALID'),('kontekst_note','RELATION_REOPEN_CONTEXT_INVALID'),
      ('ukendt','RELATION_REOPEN_NOT_FOUND'),('rolle','EVIDENCE_ROLE_FORBIDDEN'),
      ('ingen_binding','RELATION_REOPEN_BINDING_INVALID'),('revideret_klausul','INTERPRETATION_OBSERVATION_CLAUSE_NOT_CURRENT'),
      ('gentaget','RELATION_REOPEN_NOT_ELIGIBLE')) x(c,e) LOOP
    k:=CASE v_case WHEN 'samme_familie' THEN 'g1' WHEN 'null_tilstand' THEN 'g3' WHEN 'proposed' THEN 'g5'
                   WHEN 'ingen_binding' THEN 'g4' WHEN 'revideret_klausul' THEN 'g6' ELSE 'g2' END;
    SELECT id,version INTO v_id,v_ver FROM private.interpretation_current WHERE interpretation_key=(m->k->'claim'->>'key')::uuid;
    v_ctx:=ctx; v_note:='#248 test';
    IF v_case='ikke_aegteskab' THEN
      SELECT id,version INTO v_id,v_ver FROM private.interpretation_current WHERE interpretation_key=(par->'claim'->>'key')::uuid;
    ELSIF v_case='ikke_gaeldende' THEN v_id:=(m->'g2'->'claim'->>'id')::uuid; v_ver:=1;
    ELSIF v_case='forkert_version' THEN v_ver:=v_ver-1;
    ELSIF v_case='kontekst_basis' THEN v_ctx:=ctx||'{"basis":"web"}';
    ELSIF v_case='kontekst_ekstra' THEN v_ctx:=ctx||'{"x":1}';
    ELSIF v_case='kontekst_linje' THEN v_ctx:=ctx||'{"line":"0"}';
    ELSIF v_case='kontekst_note' THEN v_note:='  ';
    ELSIF v_case='ukendt' THEN v_id:=gen_random_uuid();
    ELSIF v_case='gentaget' THEN
      SET LOCAL ROLE authenticated;
      v_reo:=red_genaabn_relation_interpretation(v_id,v_ver,v_note,v_ctx);   -- første kald lykkes
      RESET ROLE;
    END IF;
    SELECT count(*) INTO v_n FROM private.interpretation WHERE interpretation_key=(m->k->'claim'->>'key')::uuid;
    PERFORM set_config('request.jwt.claim.sub',CASE WHEN v_case='rolle' THEN '' ELSE v_actor::text END,true);
    SET LOCAL ROLE authenticated;
    BEGIN
      PERFORM red_genaabn_relation_interpretation(v_id,v_ver,v_note,v_ctx);
      RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: genaabn_% godtaget',v_case;
    EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT;
      IF v_err NOT LIKE v_expect||'%' THEN RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: genaabn_% gav %',v_case,v_err; END IF;
    END;
    RESET ROLE;
    PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
    IF (SELECT count(*) FROM private.interpretation WHERE interpretation_key=(m->k->'claim'->>'key')::uuid)<>v_n
       OR (v_case<>'gentaget' AND EXISTS (SELECT 1 FROM private.relation_reopen WHERE interpretation_key=(m->k->'claim'->>'key')::uuid)) THEN
      RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: genaabn_% skrev halvt',v_case;
    END IF;
  END LOOP;
  RAISE NOTICE 'OK: genåbning afviser';
END $genaabn_negativ$;
ROLLBACK;

-- ---------- Review trin B (1d.3b-01): førstebinding efter familieskift ----------
-- En accepteret, aldrig bundet relation, hvis struktur er flyttet til en anden familie, må ikke førstebindes til den
-- nye familie: afgørelsen gælder familien i decision_evidence (børnegrenen har samme vagt i relation_binding_state).
-- Uændret familie binder fortsat.
BEGIN;
\ir fixtures/relation-5b.sql
\ir fixtures/relation-2a.sql
DO $decision_family$
DECLARE v_actor uuid:='11000000-0000-0000-0000-0000001d3b01'; s jsonb; m jsonb; m2 jsonb; m3 jsonb; par jsonb; par2 jsonb;
  pv jsonb; items jsonb; v_mid uuid; v_m2 uuid; v_m3 uuid; v_pid uuid; v_p2 uuid; v_fam bigint; v_pfam bigint; v_err text;
  v_batch uuid;
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  INSERT INTO person(id,levende,privat,status) SELECT g,false,false,'1d3b' FROM generate_series(-31340,-31301) g;
  s:=pg_temp.f5b_source(-31301);
  m:=pg_temp.f2a_marriage(-31301,s,'D-1',-31301,-31302,v_actor,1,1);      -- flyttes
  m2:=pg_temp.f2a_marriage(-31301,s,'D-2',-31303,-31304,v_actor,1,1);     -- uændret
  m3:=pg_temp.f2a_marriage(-31301,s,'D-3',-31312,-31313,v_actor,1,1);     -- afgørelse uden family_id
  par:=pg_temp.f2a_parent(-31301,s,-31305,-31306,-31307,v_actor);         -- flyttes
  par2:=pg_temp.f2a_parent(-31301,s,-31309,-31310,-31311,v_actor);        -- uændret
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  SET LOCAL ROLE authenticated;
  pv:=red_preview_relation_decisions(-31301);
  PERFORM red_decide_relation_interpretations(-31301,pv->>'set_sha256');
  RESET ROLE;
  SELECT id INTO v_mid FROM private.interpretation_current WHERE interpretation_key=(m->'claim'->>'key')::uuid;
  SELECT id INTO v_m2 FROM private.interpretation_current WHERE interpretation_key=(m2->'claim'->>'key')::uuid;
  SELECT id INTO v_pid FROM private.interpretation_current WHERE interpretation_key=(par->'claim'->>'key')::uuid;
  SELECT id INTO v_p2 FROM private.interpretation_current WHERE interpretation_key=(par2->'claim'->>'key')::uuid;
  SELECT id INTO v_m3 FROM private.interpretation_current WHERE interpretation_key=(m3->'claim'->>'key')::uuid;
  -- forudsætning: alle fire er accepteret for deres oprindelige familie og aldrig bundet
  IF (SELECT count(*) FROM private.interpretation i
       WHERE (i.id,(i.decision_evidence->>'family_id')::bigint) IN
             ((v_mid,(m->>'family')::bigint),(v_m2,(m2->>'family')::bigint),
              (v_pid,(par->>'family')::bigint),(v_p2,(par2->>'family')::bigint))
         AND i.status='accepted')<>4
     OR EXISTS (SELECT 1 FROM private.interpretation_promotion WHERE interpretation_id IN (v_mid,v_m2,v_pid,v_p2)) THEN
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: decision_family forudsætning';
  END IF;

  -- ægteskabet flyttes: parret i en ny familie (som rute A-testene)
  DELETE FROM family_member WHERE family_id=(m->>'family')::bigint AND person_id=-31302;
  v_fam:=pg_temp.f5b_family(-31301,-31302,1);
  -- forælderen flyttes: barnet i en ny familie med forælderen og en anden partner
  DELETE FROM family_member WHERE family_id=(par->>'family')::bigint AND person_id=-31305 AND rolle='barn';
  v_pfam:=pg_temp.f5b_family(-31306,-31308,2);
  INSERT INTO family_member(family_id,person_id,rolle) VALUES (v_pfam,-31305,'barn');
  IF (private.relation_binding_state(v_mid)#>>'{family,family_id}')::bigint IS DISTINCT FROM v_fam
     OR (private.relation_binding_state(v_pid)#>>'{family,family_id}')::bigint IS DISTINCT FROM v_pfam THEN
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: decision_family flytning % %',
      private.relation_binding_state(v_mid),private.relation_binding_state(v_pid);
  END IF;

  -- førstebinding til den nye familie afvises i previewet for både ægteskab og forælder
  items:=jsonb_build_array(jsonb_build_object('interpretation_id',v_mid::text,'family_id',v_fam),
                           jsonb_build_object('interpretation_id',v_pid::text,'family_id',v_pfam));
  SET LOCAL ROLE authenticated;
  pv:=red_preview_relation_promotions(-31301,items);
  RESET ROLE;
  IF pv#>>'{items,0,reason_code}' IS DISTINCT FROM 'RELATION_PROMOTION_DECISION_FAMILY_CHANGED'
     OR pv#>>'{items,1,reason_code}' IS DISTINCT FROM 'RELATION_PROMOTION_DECISION_FAMILY_CHANGED'
     OR (pv#>>'{items,0,eligible}')::boolean OR (pv#>>'{items,1,eligible}')::boolean THEN
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: decision_family preview %', pv;
  END IF;
  -- og i bindingen (hver for sig, så begge prædikater prøves gennem skrivevejen)
  FOR items IN SELECT jsonb_build_array(x) FROM jsonb_array_elements(items) x LOOP
    SET LOCAL ROLE authenticated;
    pv:=red_preview_relation_promotions(-31301,items);
    BEGIN
      PERFORM red_promote_relation_interpretations_batch(-31301,items,pv->>'preview_sha256');
      RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: decision_family binding godtaget %', items;
    EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT;
      IF v_err NOT LIKE 'RELATION_PROMOTION_DECISION_FAMILY_CHANGED%' THEN RAISE; END IF;
    END;
    RESET ROLE;
  END LOOP;
  IF EXISTS (SELECT 1 FROM private.interpretation_promotion WHERE interpretation_id IN (v_mid,v_pid)) THEN
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: decision_family skrev en binding';
  END IF;

  -- en accepteret relation uden family_id i decision_evidence (familien ikke registreret ved afgørelsen, fx ældre
  -- data) afvises med samme kode, selv om familien er uændret. Den ældre afgørelse simuleres ved at omgå
  -- append-only-triggeren (kun i testen; rulles tilbage).
  SET LOCAL session_replication_role=replica;
  UPDATE private.interpretation SET decision_evidence=decision_evidence-'family_id' WHERE id=v_m3;
  SET LOCAL session_replication_role=origin;
  items:=jsonb_build_array(jsonb_build_object('interpretation_id',v_m3::text,'family_id',(m3->>'family')::bigint));
  SET LOCAL ROLE authenticated;
  pv:=red_preview_relation_promotions(-31301,items);
  RESET ROLE;
  IF (private.relation_binding_state(v_m3)#>>'{family,family_id}')::bigint IS DISTINCT FROM (m3->>'family')::bigint
     OR pv#>>'{items,0,reason_code}' IS DISTINCT FROM 'RELATION_PROMOTION_DECISION_FAMILY_CHANGED' THEN
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: decision_family uden family_id %', pv;
  END IF;

  -- uændret familie binder fortsat (ægteskab og forælder)
  items:=jsonb_build_array(jsonb_build_object('interpretation_id',v_m2::text,'family_id',(m2->>'family')::bigint),
                           jsonb_build_object('interpretation_id',v_p2::text,'family_id',(par2->>'family')::bigint));
  SET LOCAL ROLE authenticated;
  pv:=red_preview_relation_promotions(-31301,items);
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(pv->'items') i WHERE NOT (i->>'eligible')::boolean) THEN
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: decision_family uændret preview %', pv;
  END IF;
  v_batch:=red_promote_relation_interpretations_batch(-31301,items,pv->>'preview_sha256');
  RESET ROLE;
  IF (SELECT count(*) FROM private.interpretation_promotion WHERE batch_id=v_batch AND target_type='family')<>2 THEN
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: decision_family uændret binding';
  END IF;
  RAISE NOTICE 'OK: førstebinding efter familieskift afvist';
END $decision_family$;
ROLLBACK;
