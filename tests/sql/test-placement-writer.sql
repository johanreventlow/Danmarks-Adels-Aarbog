-- #150 trin 5c-1 (spec 2026-10-26 §4.1-§4.3): ledger og private skrivefunktioner for placement.
\set ON_ERROR_STOP on

BEGIN;
\ir fixtures/relation-5b.sql
\ir fixtures/placement-150.sql

DO $genkoersel_idempotent$
DECLARE f jsonb:=pg_temp.f150_source(-1521); p jsonb; v_n int; v_obs uuid; v_rp uuid; v_rp2 uuid; v_pp uuid; v_pp2 uuid;
  v_rows bigint; v_headers jsonb;
BEGIN
  p:=pg_temp.f150_post(f,'I-1',-152101,1,1);
  v_headers:=jsonb_build_array(pg_temp.f150_h('header_linje',500,'I DEN TESTSKE LINJE'),
                               pg_temp.f150_h('header_slaegtled',600,'Første slægtled'));
  v_n:=private.write_header_evidence(-1521,(f->>'rend')::uuid,pg_temp.f150_run(),v_headers);
  IF v_n<>2 THEN RAISE EXCEPTION 'PLACEMENT_WRITER_TEST_FAILED: % overskrifter skrevet',v_n; END IF;
  v_obs:=private.header_observation_uuid((f->>'rend')::uuid,'header-2018-20-v1',500);
  IF (SELECT observation_kind FROM private.source_observation WHERE id=v_obs)<>'header_linje' THEN
    RAISE EXCEPTION 'PLACEMENT_WRITER_TEST_FAILED: header-observationens id er ikke indholds-id''et';
  END IF;
  v_rp:=private.write_record_placement((p->>'record')::uuid,(f->>'entry')::bigint,
    jsonb_build_object('printed_number','1','generation_local',1,'generation_label_raw','Første','section_path',
      jsonb_build_array('header:500','header:600')),v_obs,
    jsonb_build_object('rule_version','header-2018-20-v1','header_ids',jsonb_build_object('linje',v_obs,
      'slaegtled',private.header_observation_uuid((f->>'rend')::uuid,'header-2018-20-v1',600))));
  v_pp:=private.write_persona_placement((p->>'principal')::uuid,v_rp,(p->>'helpost')::uuid,
    jsonb_build_object('rule_version','placement-membership-v1'));
  v_rows:=(SELECT count(*) FROM private.source_record_occurrence)+(SELECT count(*) FROM private.source_observation)
        +(SELECT count(*) FROM private.source_record_placement)+(SELECT count(*) FROM private.source_record_placement_decision)
        +(SELECT count(*) FROM private.source_persona_placement)+(SELECT count(*) FROM private.source_persona_placement_decision)
        +(SELECT count(*) FROM private.extraction_run);
  -- Genkørsel: samme id'er, 0 nye rækker.
  v_n:=private.write_header_evidence(-1521,(f->>'rend')::uuid,pg_temp.f150_run(),v_headers);
  v_rp2:=private.write_record_placement((p->>'record')::uuid,(f->>'entry')::bigint,
    jsonb_build_object('printed_number','1','generation_local',1,'generation_label_raw','Første','section_path',
      jsonb_build_array('header:500','header:600')),v_obs,
    jsonb_build_object('rule_version','header-2018-20-v1','header_ids',jsonb_build_object('linje',v_obs,
      'slaegtled',private.header_observation_uuid((f->>'rend')::uuid,'header-2018-20-v1',600))));
  v_pp2:=private.write_persona_placement((p->>'principal')::uuid,v_rp,(p->>'helpost')::uuid,
    jsonb_build_object('rule_version','placement-membership-v1'));
  IF v_n<>0 OR v_rp2<>v_rp OR v_pp2<>v_pp
     OR v_rows<>(SELECT count(*) FROM private.source_record_occurrence)+(SELECT count(*) FROM private.source_observation)
        +(SELECT count(*) FROM private.source_record_placement)+(SELECT count(*) FROM private.source_record_placement_decision)
        +(SELECT count(*) FROM private.source_persona_placement)+(SELECT count(*) FROM private.source_persona_placement_decision)
        +(SELECT count(*) FROM private.extraction_run) THEN
    RAISE EXCEPTION 'PLACEMENT_WRITER_TEST_FAILED: genkørsel ikke idempotent';
  END IF;
  IF v_rp<>private.content_uuid('record-placement',jsonb_build_object('source_record_id',p->>'record',
       'scheme_entry_id',(f->>'entry')::bigint,'header_rule_version','header-2018-20-v1')) THEN
    RAISE EXCEPTION 'PLACEMENT_WRITER_TEST_FAILED: record-placement bærer ikke indholds-id';
  END IF;
  IF (SELECT decision_status||'/'||decision_origin||'/'||version FROM private.source_record_placement_current WHERE id=v_rp)
       <>'accepted/migration/1'
     OR (SELECT decision_status||'/'||decision_origin FROM private.source_persona_placement_current WHERE id=v_pp)
       <>'accepted/migration'
     OR (SELECT placement_role FROM private.source_persona_placement WHERE id=v_pp)<>'principal_member' THEN
    RAISE EXCEPTION 'PLACEMENT_WRITER_TEST_FAILED: v1 er ikke accepted/migration';
  END IF;
  IF private.placement_header_violations(-1521)<>0 THEN
    RAISE EXCEPTION 'PLACEMENT_WRITER_TEST_FAILED: skrevet placement bryder nærmeste-reglen';
  END IF;
  -- v2-supersede gennem redaktørvejen (persona først, så record).
  PERFORM set_config('request.jwt.claim.sub',f->>'actor',true);
  SET LOCAL ROLE authenticated;
  IF red_decide_source_persona_placement(v_pp,1,'superseded','{"basis":"test"}')<>2
     OR red_decide_source_record_placement(v_rp,1,'superseded','{"basis":"test"}')<>2 THEN
    RAISE EXCEPTION 'PLACEMENT_WRITER_TEST_FAILED: v2-supersede';
  END IF;
  RESET ROLE;
END $genkoersel_idempotent$;

DO $header_drift$
DECLARE f jsonb:=pg_temp.f150_source(-1522); v_err text;
BEGIN
  PERFORM private.write_header_evidence(-1522,(f->>'rend')::uuid,pg_temp.f150_run(),
    jsonb_build_array(pg_temp.f150_h('header_linje',500,'I DEN TESTSKE LINJE')));
  BEGIN
    PERFORM private.write_header_evidence(-1522,(f->>'rend')::uuid,pg_temp.f150_run(),
      jsonb_build_array(pg_temp.f150_h('header_linje',500,'I DEN ÆNDREDE LINJE')));
    RAISE EXCEPTION 'PLACEMENT_WRITER_TEST_FAILED: ændret header-tekst godtaget';
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT;
    IF v_err NOT LIKE 'PLACEMENT_HEADER_DRIFT%' THEN RAISE; END IF;
  END;
END $header_drift$;

DO $disposition$
DECLARE f jsonb:=pg_temp.f150_source(-1523); p jsonb; v_err text; v_v int;
BEGIN
  p:=pg_temp.f150_post(f,'I-1',-152301,1,1);
  -- mapped uden placement → CHECK
  BEGIN
    PERFORM private.record_legacy_disposition(-152301,-1523,'mapped',NULL,'{"basis":"test"}');
    RAISE EXCEPTION 'PLACEMENT_WRITER_TEST_FAILED: mapped uden placement godtaget';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  v_v:=private.record_legacy_disposition(-152301,-1523,'unresolved',NULL,'{"basis":"test"}');
  IF v_v<>1 OR private.record_legacy_disposition(-152301,-1523,'unresolved',NULL,'{"basis":"test"}')<>1
     OR (SELECT count(*) FROM private.legacy_placement_disposition WHERE person_id=-152301)<>1 THEN
    RAISE EXCEPTION 'PLACEMENT_WRITER_TEST_FAILED: uændret disposition gav ny række';
  END IF;
  IF NOT (SELECT is_current FROM private.legacy_placement_disposition_current WHERE person_id=-152301 AND source_id=-1523) THEN
    RAISE EXCEPTION 'PLACEMENT_WRITER_TEST_FAILED: ny disposition ikke gældende';
  END IF;
  UPDATE public.person_external_id SET slaegtled_lokal=2 WHERE person_id=-152301 AND source_id=-1523;
  IF (SELECT is_current FROM private.legacy_placement_disposition_current WHERE person_id=-152301 AND source_id=-1523) THEN
    RAISE EXCEPTION 'PLACEMENT_WRITER_TEST_FAILED: ændret legacy-række efterlod dispositionen gældende';
  END IF;
  -- Ny disposition efter ændringen er version 2 og gældende igen.
  IF private.record_legacy_disposition(-152301,-1523,'unresolved',NULL,'{"basis":"test"}')<>2 THEN
    RAISE EXCEPTION 'PLACEMENT_WRITER_TEST_FAILED: forældet disposition gav ikke ny version';
  END IF;
  BEGIN
    UPDATE private.legacy_placement_disposition SET disposition='retained_legacy' WHERE person_id=-152301;
    RAISE EXCEPTION 'PLACEMENT_WRITER_TEST_FAILED: ledgeren kunne ændres';
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT;
    IF v_err NOT LIKE 'EVIDENCE_APPEND_ONLY%' THEN RAISE; END IF;
  END;
  BEGIN
    PERFORM private.record_legacy_disposition(-999999,-1523,'retained_legacy',NULL,'{"basis":"test"}');
    RAISE EXCEPTION 'PLACEMENT_WRITER_TEST_FAILED: disposition uden legacy-række godtaget';
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT;
    IF v_err NOT LIKE 'PLACEMENT_LEGACY_ROW_MISSING%' THEN RAISE; END IF;
  END;
END $disposition$;

DO $mapped_kraever_egen_placement$
DECLARE f jsonb:=pg_temp.f150_source(-1524); p jsonb; q jsonb; v_obs uuid; v_rp uuid; v_err text;
BEGIN
  p:=pg_temp.f150_post(f,'I-1',-152401,1,1);
  q:=pg_temp.f150_post(f,'I-2',-152402,2,1);
  PERFORM private.write_header_evidence(-1524,(f->>'rend')::uuid,pg_temp.f150_run(),
    jsonb_build_array(pg_temp.f150_h('header_linje',500,'I DEN TESTSKE LINJE')));
  v_obs:=private.header_observation_uuid((f->>'rend')::uuid,'header-2018-20-v1',500);
  v_rp:=private.write_record_placement((p->>'record')::uuid,(f->>'entry')::bigint,'{"printed_number":"1"}',v_obs,
    jsonb_build_object('rule_version','header-2018-20-v1','header_ids',jsonb_build_object('linje',v_obs)));
  IF private.record_legacy_disposition(-152401,-1524,'mapped',v_rp,'{"basis":"test"}')<>1 THEN
    RAISE EXCEPTION 'PLACEMENT_WRITER_TEST_FAILED: mapped med egen placement afvist';
  END IF;
  BEGIN
    PERFORM private.record_legacy_disposition(-152402,-1524,'mapped',v_rp,'{"basis":"test"}');
    RAISE EXCEPTION 'PLACEMENT_WRITER_TEST_FAILED: mapped til en anden posts placement godtaget';
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT;
    IF v_err NOT LIKE 'PLACEMENT_LEGACY_MAPPING_INVALID%' THEN RAISE; END IF;
  END;
END $mapped_kraever_egen_placement$;

-- Trin 6d-1 (afgørelse 1): mapped via identitet. 1939's legacy-nøgler er ikke recordens nøgle; mapped er gyldig, når
-- placementens accepterede principal_member-persona har accepteret identitet til netop legacy-rækkens person.
-- Fælles opsætning: post med legacy-nøgle ≠ record_key og en accepteret record-placement (uden persona-placement).
CREATE OR REPLACE FUNCTION pg_temp.f6d_ledger(p_source bigint,p_person bigint) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE f jsonb:=pg_temp.f150_source(p_source); p jsonb; v_obs uuid; v_rp uuid;
BEGIN
  p:=pg_temp.f150_post(f,'I-1',p_person,1,1);
  UPDATE public.person_external_id SET record_key='legacy-'||abs(p_person) WHERE person_id=p_person AND source_id=p_source;
  PERFORM private.write_header_evidence(p_source,(f->>'rend')::uuid,pg_temp.f150_run(),
    jsonb_build_array(pg_temp.f150_h('header_linje',500,'I DEN TESTSKE LINJE')));
  v_obs:=private.header_observation_uuid((f->>'rend')::uuid,'header-2018-20-v1',500);
  v_rp:=private.write_record_placement((p->>'record')::uuid,(f->>'entry')::bigint,'{"printed_number":"1"}',v_obs,
    jsonb_build_object('rule_version','header-2018-20-v1','header_ids',jsonb_build_object('linje',v_obs)));
  RETURN f||jsonb_build_object('post',p,'rp',v_rp);
END $$;

DO $ledger_via_identitet$
DECLARE f jsonb:=pg_temp.f6d_ledger(-1527,-152701); v_rp uuid; v_err text;
BEGIN
  v_rp:=(f->>'rp')::uuid;
  -- Uden persona-placement er der ingen vej (nøglerne er forskellige).
  BEGIN
    PERFORM private.record_legacy_disposition(-152701,-1527,'mapped',v_rp,'{"basis":"test"}');
    RAISE EXCEPTION 'PLACEMENT_WRITER_TEST_FAILED: mapped uden nøgle og uden persona-placement godtaget';
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT;
    IF v_err NOT LIKE 'PLACEMENT_LEGACY_MAPPING_INVALID%' THEN RAISE; END IF;
  END;
  PERFORM private.write_persona_placement((f#>>'{post,principal}')::uuid,v_rp,(f#>>'{post,helpost}')::uuid,'{"rule":"test"}');
  IF private.record_legacy_disposition(-152701,-1527,'mapped',v_rp,'{"basis":"test"}')<>1
     OR (SELECT disposition||'/'||placement_id::text FROM private.legacy_placement_disposition
          WHERE person_id=-152701 AND source_id=-1527 AND version=1)<>'mapped/'||v_rp::text THEN
    RAISE EXCEPTION 'PLACEMENT_WRITER_TEST_FAILED: mapped via identitet afvist';
  END IF;
  -- Samme person, men legacy-rækken i en anden kilde: placementen hører ikke til den kilde.
  PERFORM pg_temp.f5b_source(-1520);
  INSERT INTO public.person_external_id(person_id,source_id,linje,nr,record_key,slaegtled_lokal)
    VALUES (-152701,-1520,'I',1,'legacy-anden-kilde',1);
  BEGIN
    PERFORM private.record_legacy_disposition(-152701,-1520,'mapped',v_rp,'{"basis":"test"}');
    RAISE EXCEPTION 'PLACEMENT_WRITER_TEST_FAILED: mapped via identitet på tværs af kilder godtaget';
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT;
    IF v_err NOT LIKE 'PLACEMENT_LEGACY_MAPPING_INVALID%' THEN RAISE; END IF;
  END;
END $ledger_via_identitet$;

DO $ledger_anden_person$
DECLARE f jsonb:=pg_temp.f6d_ledger(-1528,-152801); q jsonb; v_rp uuid; v_err text; v_mention uuid; v_sp uuid;
BEGIN
  v_rp:=(f->>'rp')::uuid;
  PERFORM private.write_persona_placement((f#>>'{post,principal}')::uuid,v_rp,(f#>>'{post,helpost}')::uuid,'{"rule":"test"}');
  -- En anden person med egen legacy-række i kilden; placementens persona er identificeret som -152801, ikke -152802.
  q:=pg_temp.f150_post(f,'I-2',-152802,2,1);
  UPDATE public.person_external_id SET record_key='legacy-152802' WHERE person_id=-152802 AND source_id=-1528;
  BEGIN
    PERFORM private.record_legacy_disposition(-152802,-1528,'mapped',v_rp,'{"basis":"test"}');
    RAISE EXCEPTION 'PLACEMENT_WRITER_TEST_FAILED: mapped til en placement for en anden person godtaget';
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT;
    IF v_err NOT LIKE 'PLACEMENT_LEGACY_MAPPING_INVALID%' THEN RAISE; END IF;
  END;
  -- En ikke-principal persona-placement (ægtefælle på samme post) med accepteret identitet til -152802 giver heller
  -- ingen vej (som f150_placed's ægtefælle).
  SELECT mention_id INTO v_mention FROM private.source_persona_mention WHERE persona_id=(f#>>'{post,principal}')::uuid;
  INSERT INTO private.source_persona(source_id,persona_key,created_run_id) VALUES (-1528,'I-1-spouse',(f->>'run')::uuid)
    RETURNING id INTO v_sp;
  INSERT INTO private.source_persona_mention(persona_id,mention_id,mention_role,ordinal) VALUES (v_sp,v_mention,'spouse',1);
  INSERT INTO private.source_persona_identity(source_persona_id,canonical_person_id,decision_status,version,evidence,
    decided_by,decided_by_name,decided_at) VALUES (v_sp,-152802,'accepted',1,'{"fixture":"6d"}',(f->>'actor')::uuid,'fixture',now());
  INSERT INTO private.source_persona_placement(source_persona_id,record_placement_id,placement_role,basis_observation_id,
    initial_status)
    VALUES (v_sp,v_rp,'mentioned_spouse',(f#>>'{post,helpost}')::uuid,'accepted') RETURNING id INTO v_sp;
  INSERT INTO private.source_persona_placement_decision(placement_id,version,decision_status,evidence,decision_origin,
    decided_by_name) VALUES (v_sp,1,'accepted','{"fixture":"6d"}','migration','fixture');
  BEGIN
    PERFORM private.record_legacy_disposition(-152802,-1528,'mapped',v_rp,'{"basis":"test"}');
    RAISE EXCEPTION 'PLACEMENT_WRITER_TEST_FAILED: mapped via en ikke-principal persona-placement godtaget';
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT;
    IF v_err NOT LIKE 'PLACEMENT_LEGACY_MAPPING_INVALID%' THEN RAISE; END IF;
  END;
  IF EXISTS (SELECT 1 FROM private.legacy_placement_disposition WHERE person_id=-152802) THEN
    RAISE EXCEPTION 'PLACEMENT_WRITER_TEST_FAILED: afvist mapping skrev en ledger-række';
  END IF;
END $ledger_anden_person$;

DO $ledger_identitet_ikke_accepteret$
DECLARE f jsonb:=pg_temp.f6d_ledger(-1529,-152901); v_rp uuid; v_pp uuid; v_err text;
BEGIN
  v_rp:=(f->>'rp')::uuid;
  v_pp:=private.write_persona_placement((f#>>'{post,principal}')::uuid,v_rp,(f#>>'{post,helpost}')::uuid,'{"rule":"test"}');
  -- Identiteten afgøres igen som afvist (ejer-skrivning som i membership-testen).
  UPDATE private.source_persona_identity SET decision_status='rejected',canonical_person_id=NULL,version=2
   WHERE source_persona_id=(f#>>'{post,principal}')::uuid;
  BEGIN
    PERFORM private.record_legacy_disposition(-152901,-1529,'mapped',v_rp,'{"basis":"test"}');
    RAISE EXCEPTION 'PLACEMENT_WRITER_TEST_FAILED: mapped via ikke-accepteret identitet godtaget';
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT;
    IF v_err NOT LIKE 'PLACEMENT_LEGACY_MAPPING_INVALID%' THEN RAISE; END IF;
  END;
  -- Identiteten accepteret igen, men persona-placementen er ikke længere gældende accepteret.
  UPDATE private.source_persona_identity SET decision_status='accepted',canonical_person_id=-152901,version=3
   WHERE source_persona_id=(f#>>'{post,principal}')::uuid;
  PERFORM set_config('request.jwt.claim.sub',f->>'actor',true);
  SET LOCAL ROLE authenticated;
  PERFORM red_decide_source_persona_placement(v_pp,1,'superseded','{"basis":"test"}');
  RESET ROLE;
  BEGIN
    PERFORM private.record_legacy_disposition(-152901,-1529,'mapped',v_rp,'{"basis":"test"}');
    RAISE EXCEPTION 'PLACEMENT_WRITER_TEST_FAILED: mapped via afløst persona-placement godtaget';
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT;
    IF v_err NOT LIKE 'PLACEMENT_LEGACY_MAPPING_INVALID%' THEN RAISE; END IF;
  END;
END $ledger_identitet_ikke_accepteret$;

DO $ledger_noegle_uaendret$
DECLARE f jsonb:=pg_temp.f150_source(-1519); p jsonb; v_obs uuid; v_rp uuid;
BEGIN
  -- Den gamle vej: legacy-nøglen = recordens nøgle, ingen persona-placement og identiteten afvist → stadig mapped.
  p:=pg_temp.f150_post(f,'I-1',-151901,1,1);
  UPDATE private.source_persona_identity SET decision_status='rejected',canonical_person_id=NULL,version=2
   WHERE source_persona_id=(p->>'principal')::uuid;
  PERFORM private.write_header_evidence(-1519,(f->>'rend')::uuid,pg_temp.f150_run(),
    jsonb_build_array(pg_temp.f150_h('header_linje',500,'I DEN TESTSKE LINJE')));
  v_obs:=private.header_observation_uuid((f->>'rend')::uuid,'header-2018-20-v1',500);
  v_rp:=private.write_record_placement((p->>'record')::uuid,(f->>'entry')::bigint,'{"printed_number":"1"}',v_obs,
    jsonb_build_object('rule_version','header-2018-20-v1','header_ids',jsonb_build_object('linje',v_obs)));
  IF private.record_legacy_disposition(-151901,-1519,'mapped',v_rp,'{"basis":"test"}')<>1 THEN
    RAISE EXCEPTION 'PLACEMENT_WRITER_TEST_FAILED: nøglevejen virker ikke længere';
  END IF;
END $ledger_noegle_uaendret$;

DO $entry_lineage$
DECLARE f jsonb:=pg_temp.f150_source(-1525); v_l2 bigint; v_err text;
BEGIN
  IF private.lineage_of_entry((f->>'entry')::bigint)<>(f->>'lineage')::bigint THEN
    RAISE EXCEPTION 'PLACEMENT_WRITER_TEST_FAILED: lineage_of_entry';
  END IF;
  INSERT INTO public.lineage(slaegt_id,canonical_label,navn) VALUES ((f->>'slaegt')::bigint,'I b','anden') RETURNING id INTO v_l2;
  INSERT INTO public.lineage_scheme_entry_lineage(entry_id,lineage_id,slaegt_id,relation_kind)
    VALUES ((f->>'entry')::bigint,v_l2,(f->>'slaegt')::bigint,'canonical');
  BEGIN
    PERFORM private.lineage_of_entry((f->>'entry')::bigint);
    RAISE EXCEPTION 'PLACEMENT_WRITER_TEST_FAILED: to canonicals godtaget';
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT;
    IF v_err NOT LIKE 'PLACEMENT_ENTRY_LINEAGE_INVALID%' THEN RAISE; END IF;
  END;
END $entry_lineage$;

DO $acl$
BEGIN
  IF has_table_privilege('anon','private.legacy_placement_disposition','SELECT')
     OR has_table_privilege('authenticated','private.legacy_placement_disposition','SELECT')
     OR has_table_privilege('authenticated','private.legacy_placement_disposition_current','SELECT')
     OR has_function_privilege('authenticated','private.record_legacy_disposition(bigint,bigint,text,uuid,jsonb)','EXECUTE')
     OR has_function_privilege('authenticated','private.write_header_evidence(bigint,uuid,jsonb,jsonb)','EXECUTE')
     OR has_function_privilege('authenticated','private.write_record_placement(uuid,bigint,jsonb,uuid,jsonb)','EXECUTE')
     OR has_function_privilege('authenticated','private.write_persona_placement(uuid,uuid,uuid,jsonb)','EXECUTE')
     OR NOT (SELECT relrowsecurity FROM pg_class WHERE oid='private.legacy_placement_disposition'::regclass) THEN
    RAISE EXCEPTION 'PLACEMENT_WRITER_TEST_FAILED: ledger/skrivefunktioner er API-tilgængelige';
  END IF;
END $acl$;

DO $slaegt_versioneret$
DECLARE f jsonb:=pg_temp.f150_source(-1526); v_cs bigint;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.version_pk_registry WHERE tabel='slaegt') THEN
    RAISE EXCEPTION 'PLACEMENT_WRITER_TEST_FAILED: slaegt ikke i version_pk_registry';
  END IF;
  PERFORM set_config('request.jwt.claim.sub',f->>'actor',true);
  v_cs:=public.begin_change_set('test','slaegt aktiv');
  UPDATE public.slaegt SET status='active' WHERE id=(f->>'slaegt')::bigint;
  PERFORM set_config('app.change_set_id','',true);
  IF (SELECT count(*) FROM public.change_event WHERE change_set_id=v_cs AND tabel='slaegt')<>1 THEN
    RAISE EXCEPTION 'PLACEMENT_WRITER_TEST_FAILED: slaegt-UPDATE gav ikke én change_event';
  END IF;
END $slaegt_versioneret$;

\echo PLACEMENT_WRITER_TEST_OK
ROLLBACK;
