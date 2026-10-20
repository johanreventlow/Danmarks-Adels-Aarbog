-- Trin 5b 2b-iii (spec 2026-10-20): børnehenvisninger. Kun opdigtede navne. Kører i writer-1939-v50-db.
\set ON_ERROR_STOP on
BEGIN;
DO $child_ref$
DECLARE r jsonb;
BEGIN
  -- interval, slægtled, romertal
  r:=private.relation_child_ref('12 børn: Tolvte slægtled, III, nr. 34-45');
  IF r IS DISTINCT FROM '{"count":12,"sex":null,"uncertain":false,"gen_local":12,"gen_through":null,"section":"III","nr_from":34,"nr_to":45}'::jsonb THEN
    RAISE EXCEPTION 'RELATION_CHILD_TEST_FAILED: interval %',r; END IF;
  -- test_ref_enkelt_nummer: Datter, enkelt nummer ⇒ nr_to=nr_from, køn kvinde
  r:=private.relation_child_ref('Datter: Fjortende slægtled, V, nr. 119');
  IF r->>'count'<>'1' OR r->>'sex'<>'kvinde' OR r->>'nr_from'<>'119' OR r->>'nr_to'<>'119' THEN
    RAISE EXCEPTION 'RELATION_CHILD_TEST_FAILED: enkelt nummer %',r; END IF;
  -- parentes-slægtled, U+2011-bindestreg, intet romertal, punktum
  r:=private.relation_child_ref(E'9 børn: Andet (femtende) slægtled, nr. 1‑8.');
  IF r->>'gen_local'<>'2' OR r->>'gen_through'<>'15' OR r->>'section' IS NOT NULL OR r->>'nr_to'<>'8' THEN
    RAISE EXCEPTION 'RELATION_CHILD_TEST_FAILED: parentes %',r; END IF;
  -- uden henvisning, usikker, sønner
  r:=private.relation_child_ref('3 sønner (?)');
  IF r->>'count'<>'3' OR r->>'sex'<>'mand' OR NOT (r->>'uncertain')::boolean OR r->>'nr_from' IS NOT NULL THEN
    RAISE EXCEPTION 'RELATION_CHILD_TEST_FAILED: usikker %',r; END IF;
  -- æøå uafhængigt af databasens locale (Opus plan-review fund 2)
  IF private.relation_child_ref('2 børn: Første slægtled, I, nr. 1-2')->>'gen_local'<>'1' THEN
    RAISE EXCEPTION 'RELATION_CHILD_TEST_FAILED: første'; END IF;
  IF private.relation_child_ref('17 børn')->>'count'<>'17' THEN RAISE EXCEPTION 'RELATION_CHILD_TEST_FAILED: kun antal'; END IF;
  -- uden for grammatikken ⇒ NULL
  IF private.relation_child_ref('X') IS NOT NULL OR private.relation_child_ref('se nedenfor') IS NOT NULL
     OR private.relation_child_ref('2 børn: Tolvte slægtled, III, nr. 9-3') IS NOT NULL      -- omvendt interval
     OR private.relation_child_ref('2 børn: Hundrede slægtled, III, nr. 1-2') IS NOT NULL   -- ukendt ordenstal
     OR private.relation_child_ref('0 børn') IS NOT NULL
     OR private.relation_child_ref('300 børn: Andet slægtled, I, nr. 1-300') IS NOT NULL    -- urimeligt interval
     OR private.relation_child_ref(NULL) IS NOT NULL THEN
    RAISE EXCEPTION 'RELATION_CHILD_TEST_FAILED: uden for grammatikken'; END IF;
END $child_ref$;
ROLLBACK;
BEGIN;
\ir fixtures/relation-5b.sql
\ir fixtures/relation-2a.sql
\ir fixtures/relation-child.sql
DO $child_rule$
DECLARE v_actor uuid:='11000000-0000-0000-0000-0000002b3001'; f jsonb; k uuid; r jsonb; v_id uuid;
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  f:=pg_temp.fc_setup('3 sønner: Andet slægtled, V, nr. 2-4',v_actor);
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  k:=(f->'claim'->>'key')::uuid; v_id:=(f->'claim'->>'id')::uuid;
  r:=private.relation_child_rule(v_id);
  IF NOT (r->>'ok')::boolean OR (r->>'family_id')::bigint<>(f->>'family')::bigint OR jsonb_array_length(r->'afvigelser')<>0
     OR r->>'flock_digest' !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'RELATION_CHILD_TEST_FAILED: lykkelig regel %',r; END IF;
  -- writer: p_family_id sat ⇒ afvist; unresolved ⇒ afvist; web_detail ⇒ afvist
  IF pg_temp.fc_decide(k,1,'same',(f->>'family')::bigint,pg_temp.fc_ctx(),v_actor)<>'RELATION_DECISION_INVALID'
     OR pg_temp.fc_decide(k,1,'unresolved',NULL,pg_temp.fc_ctx(),v_actor)<>'RELATION_DECISION_INVALID'
     OR pg_temp.fc_decide(k,1,'same',NULL,'{}'::jsonb,v_actor)<>'RELATION_DECISION_INVALID' THEN
    RAISE EXCEPTION 'RELATION_CHILD_TEST_FAILED: writer-validering'; END IF;
  -- same ⇒ accepted, evidens med familie og digest, ingen child-part
  IF pg_temp.fc_decide(k,1,'same',NULL,pg_temp.fc_ctx(),v_actor)<>'OK' THEN RAISE EXCEPTION 'RELATION_CHILD_TEST_FAILED: same'; END IF;
  IF (SELECT status FROM private.interpretation_current WHERE interpretation_key=k)<>'accepted'
     OR (SELECT decision_evidence->>'method' FROM private.interpretation_current WHERE interpretation_key=k)<>'relation-child-v1'
     OR (SELECT (decision_evidence->>'family_id')::bigint FROM private.interpretation_current WHERE interpretation_key=k)<>(f->>'family')::bigint
     OR (SELECT decision_evidence->>'flock_digest' FROM private.interpretation_current WHERE interpretation_key=k)<>r->>'flock_digest'
     OR EXISTS (SELECT 1 FROM private.interpretation_party WHERE interpretation_key=k AND party_role='child') THEN
    RAISE EXCEPTION 'RELATION_CHILD_TEST_FAILED: evidens'; END IF;
END $child_rule$;
ROLLBACK;
BEGIN;
\ir fixtures/relation-5b.sql
\ir fixtures/relation-2a.sql
\ir fixtures/relation-child.sql
DO $child_breaks$
DECLARE v_actor uuid:='11000000-0000-0000-0000-0000002b3001'; r jsonb; k uuid;
BEGIN
  -- H5_nr: interval passer ikke (2-5 mod børn 2-4); writeren håndhæver; rejected virker trods brud
  r:=pg_temp.fc_rule('4 sønner: Andet slægtled, V, nr. 2-5','',v_actor); k:=(r#>>'{_claim,key}')::uuid;
  IF (r->>'ok')::boolean OR NOT (r->'brud') ? 'H5_nr' THEN RAISE EXCEPTION 'RELATION_CHILD_TEST_FAILED: H5_nr %',r; END IF;
  IF pg_temp.fc_decide(k,1,'same',NULL,pg_temp.fc_ctx(),v_actor)<>'RELATION_CHILD_RULE_NOT_MET' THEN
    RAISE EXCEPTION 'RELATION_CHILD_TEST_FAILED: writer håndhæver ikke H5'; END IF;
  IF pg_temp.fc_decide(k,1,'rejected',NULL,pg_temp.fc_ctx(),v_actor)<>'OK' THEN
    RAISE EXCEPTION 'RELATION_CHILD_TEST_FAILED: rejected'; END IF;
END $child_breaks$;
ROLLBACK;
-- Ét brud pr. savepoint (personerne -57xx genbruges). Kolonner: raw, ekstra opsætning, forventet kode i brud.
BEGIN;
\ir fixtures/relation-5b.sql
\ir fixtures/relation-2a.sql
\ir fixtures/relation-child.sql
CREATE TEMP TABLE fc_cases(no int,raw text,sqltext text,code text);
INSERT INTO fc_cases VALUES
 (1,'3 døtre: Andet slægtled, V, nr. 2-4','','H4'),
 (2,'3 sønner: Andet slægtled, III, nr. 2-4','','H5_romertal'),
 (3,'3 sønner: Tredje slægtled, V, nr. 2-4','','H5_slaegtled'),
 (4,'3 sønner: Andet slægtled, V, nr. 2-4','UPDATE family_member SET konfidens=''omstridt'' WHERE person_id=-5702','H3_raekker'),
 (5,'3 sønner: Andet slægtled, V, nr. 2-4',
    'INSERT INTO person(id,levende,privat,status,koen) VALUES (-5706,false,false,''2b3'',''mand''); '
    'INSERT INTO family_member(family_id,person_id,rolle) VALUES (pg_temp.f5b_family(-5701,NULL,2),-5706,''barn'')','H3_familie'),
 (6,'3 sønner: Andet slægtled, V, nr. 2-4','UPDATE person_external_id SET linje=''III'' WHERE person_id=-5704 AND source_id=-5701','H5_linje'),
 (7,'3 sønner: Andet slægtled, V, nr. 2-4','UPDATE person_external_id SET linje=''III'' WHERE person_id=-5704 AND source_id=-5701','H5_nr'),
 (8,'3 sønner','DELETE FROM person_external_id WHERE person_id IN (-5702,-5703,-5704)','H6'),
 (9,'3 sønner: Andet (femtende) slægtled, V, nr. 2-4','','H5_slaegtled_gennem'),
 (10,'3 sønner: Andet slægtled, V, nr. 2-4','UPDATE person_external_id SET slaegtled_lokal=NULL WHERE person_id=-5703','H5_slaegtled'),
 (11,'3 sønner: Andet slægtled, V, nr. 2-4','DELETE FROM person_external_id WHERE person_id=-5701','H1_postnoegle'),
 (12,'se nedenfor','','H2'),
 (13,'Søn: Andet slægtled, V, nr. 2','','H5_nr');
\set QUIET on
SELECT format($f$SAVEPOINT c%1$s;
DO $c$ DECLARE r jsonb; BEGIN
  r:=pg_temp.fc_rule(%2$L,%3$L,'11000000-0000-0000-0000-0000002b3001');
  IF (r->>'ok')::boolean OR NOT (r->'brud') ? %4$L THEN RAISE EXCEPTION 'RELATION_CHILD_TEST_FAILED: brud %1$s %% ', r->'brud'; END IF;
  IF %1$s=11 AND pg_temp.fc_decide((r#>>'{_claim,key}')::uuid,1,'same',NULL,pg_temp.fc_ctx(),'11000000-0000-0000-0000-0000002b3001')<>'RELATION_CHILD_RULE_NOT_MET' THEN
    RAISE EXCEPTION 'RELATION_CHILD_TEST_FAILED: writer håndhæver ikke H1'; END IF;
END $c$;
ROLLBACK TO SAVEPOINT c%1$s;$f$,no,raw,sqltext,code) FROM fc_cases ORDER BY no \gexec
-- afvigelser (A): ok, men vist på kortet
SAVEPOINT a1;
DO $a$ DECLARE r jsonb; BEGIN
  r:=pg_temp.fc_rule('3 sønner (?)','','11000000-0000-0000-0000-0000002b3001');
  IF NOT (r->>'ok')::boolean OR r->'afvigelser' IS DISTINCT FROM '["A3_usikker","A4_uden_henvisning"]'::jsonb THEN
    RAISE EXCEPTION 'RELATION_CHILD_TEST_FAILED: uden henvisning %',r; END IF;
END $a$;
ROLLBACK TO SAVEPOINT a1;
DO $a$ DECLARE r jsonb; BEGIN
  r:=pg_temp.fc_rule('4 sønner: Andet slægtled, V, nr. 2-4','','11000000-0000-0000-0000-0000002b3001');
  IF NOT (r->>'ok')::boolean OR NOT (r->'afvigelser') ?& ARRAY['A1_antal_familie','A2_antal_interval'] THEN
    RAISE EXCEPTION 'RELATION_CHILD_TEST_FAILED: antal %',r; END IF;
END $a$;
ROLLBACK;
-- Task 3: binding, drift og læserens kilde (spec §7-§8).
BEGIN;
\ir fixtures/relation-5b.sql
\ir fixtures/relation-2a.sql
\ir fixtures/relation-child.sql
CREATE OR REPLACE FUNCTION pg_temp.fc_bind(p_src bigint,p_iid uuid,p_fam bigint,p_actor uuid) RETURNS text LANGUAGE plpgsql AS $$
DECLARE items jsonb:=jsonb_build_array(jsonb_build_object('interpretation_id',p_iid::text,'family_id',p_fam)); pv jsonb;
BEGIN
  PERFORM set_config('request.jwt.claim.sub',p_actor::text,true);
  SET LOCAL ROLE authenticated;
  pv:=red_preview_relation_promotions(p_src,items);
  IF NOT (pv->'items'->0->>'eligible')::boolean THEN RESET ROLE; RETURN pv->'items'->0->>'reason_code'; END IF;
  PERFORM red_promote_relation_interpretations_batch(p_src,items,pv->>'preview_sha256');
  RESET ROLE;
  RETURN 'BOUND';
END $$;
CREATE OR REPLACE FUNCTION pg_temp.fc_boern(p_fam bigint) RETURNS integer LANGUAGE plpgsql AS $$
DECLARE n integer;
BEGIN
  SET LOCAL ROLE anon;
  SELECT count(*) INTO n FROM public.public_family_sources(ARRAY[p_fam]) s WHERE s.slags='boern' AND s.counterpart_person_id=-5701;
  RESET ROLE;
  RETURN n;
END $$;
-- Afgjort og publiceret flok: returnerer {fam, iid}.
CREATE OR REPLACE FUNCTION pg_temp.fc_decided(p_actor uuid) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE f jsonb; k uuid; v_iid uuid;
BEGIN
  PERFORM pg_temp.f5b_actor(p_actor);
  f:=pg_temp.fc_setup('3 sønner: Andet slægtled, V, nr. 2-4',p_actor);
  k:=(f->'claim'->>'key')::uuid;
  PERFORM pg_temp.f2a_publish(-5701,f->'source',f->'post',-5701,p_actor,'Ole Alfa. 3 sønner: Andet slægtled, V, nr. 2-4');
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  IF pg_temp.fc_decide(k,1,'same',NULL,pg_temp.fc_ctx(),p_actor)<>'OK' THEN RAISE EXCEPTION 'RELATION_CHILD_TEST_FAILED: afgør'; END IF;
  SELECT id INTO v_iid FROM private.interpretation_current WHERE interpretation_key=k;
  RETURN jsonb_build_object('fam',(f->>'family')::bigint,'iid',v_iid);
END $$;
SAVEPOINT b1;
DO $child_bind$
DECLARE v_actor uuid:='11000000-0000-0000-0000-0000002b3001'; d jsonb; v_fam bigint; v_iid uuid;
BEGIN
  d:=pg_temp.fc_decided(v_actor); v_fam:=(d->>'fam')::bigint; v_iid:=(d->>'iid')::uuid;
  -- Review Focus 2a: barn UDEN egen post tilføjet før binding ⇒ H holder, den aktuelle flok bindes
  INSERT INTO person(id,levende,privat,status,koen) VALUES (-5707,false,false,'2b3','mand');
  INSERT INTO family_member(family_id,person_id,rolle) VALUES (v_fam,-5707,'barn');
  IF pg_temp.fc_bind(-5701,v_iid,v_fam,v_actor)<>'BOUND' THEN RAISE EXCEPTION 'RELATION_CHILD_TEST_FAILED: binding'; END IF;
  IF (private.relation_binding_state(v_iid)->>'counterpart_person_id')::bigint<>-5701
     OR pg_temp.fc_boern(v_fam)<>1 THEN RAISE EXCEPTION 'RELATION_CHILD_TEST_FAILED: synlig boern-kilde'; END IF;
  -- barn tilføjet EFTER binding ⇒ ny tilstand ⇒ usynlig; genbinding bringer den tilbage (H holder)
  INSERT INTO person(id,levende,privat,status,koen) VALUES (-5708,false,false,'2b3','mand');
  INSERT INTO family_member(family_id,person_id,rolle) VALUES (v_fam,-5708,'barn');
  IF pg_temp.fc_boern(v_fam)<>0 THEN RAISE EXCEPTION 'RELATION_CHILD_TEST_FAILED: drift ikke skjult'; END IF;
  IF pg_temp.fc_bind(-5701,v_iid,v_fam,v_actor)<>'BOUND' OR pg_temp.fc_boern(v_fam)<>1 THEN
    RAISE EXCEPTION 'RELATION_CHILD_TEST_FAILED: genbinding'; END IF;
  -- barn med egen post flyttet ud ⇒ H5_nr ⇒ usynlig og genbinding afvist
  DELETE FROM family_member WHERE family_id=v_fam AND person_id=-5704;
  IF private.relation_binding_state(v_iid) IS NOT NULL OR pg_temp.fc_boern(v_fam)<>0
     OR pg_temp.fc_bind(-5701,v_iid,v_fam,v_actor)<>'RELATION_PROMOTION_STRUCTURE_INVALID' THEN
    RAISE EXCEPTION 'RELATION_CHILD_TEST_FAILED: flyttet barn'; END IF;
END $child_bind$;
ROLLBACK TO SAVEPOINT b1;
DO $child_outside$
DECLARE v_actor uuid:='11000000-0000-0000-0000-0000002b3001'; d jsonb; v_fam bigint;
BEGIN
  -- barn MED egen post uden for intervallet tilføjet mellem afgørelse og binding ⇒ afvist
  d:=pg_temp.fc_decided(v_actor); v_fam:=(d->>'fam')::bigint;
  INSERT INTO person(id,levende,privat,status,koen) VALUES (-5709,false,false,'2b3','mand');
  INSERT INTO person_external_id(person_id,source_id,linje,nr,record_key,kuld,slaegtled_lokal) VALUES (-5709,-5701,'V',9,'V-9','V',2);
  INSERT INTO family_member(family_id,person_id,rolle) VALUES (v_fam,-5709,'barn');
  IF pg_temp.fc_bind(-5701,(d->>'iid')::uuid,v_fam,v_actor)<>'RELATION_PROMOTION_STRUCTURE_INVALID' THEN
    RAISE EXCEPTION 'RELATION_CHILD_TEST_FAILED: barn uden for intervallet'; END IF;
END $child_outside$;
ROLLBACK TO SAVEPOINT b1;
DO $child_private$
DECLARE v_actor uuid:='11000000-0000-0000-0000-0000002b3001'; d jsonb; v_fam bigint;
BEGIN
  -- Review Focus 3: et levende medlem skjuler familiens kilde for anon
  d:=pg_temp.fc_decided(v_actor); v_fam:=(d->>'fam')::bigint;
  IF pg_temp.fc_bind(-5701,(d->>'iid')::uuid,v_fam,v_actor)<>'BOUND' OR pg_temp.fc_boern(v_fam)<>1 THEN
    RAISE EXCEPTION 'RELATION_CHILD_TEST_FAILED: binding før levende'; END IF;
  UPDATE person SET levende=true WHERE id=-5703;
  IF pg_temp.fc_boern(v_fam)<>0 THEN RAISE EXCEPTION 'RELATION_CHILD_TEST_FAILED: levende barn lækker kilden'; END IF;
END $child_private$;
ROLLBACK;
\echo RELATION_CHILD_TEST_OK
