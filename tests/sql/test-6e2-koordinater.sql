\set ON_ERROR_STOP on
-- Trin 6e-2 Task 3: koordinat-RPC'en. Kildegaten på (entry, slægtled, kuld, trykt nr.) med NULL som ens, postens trykte
-- startside (printed_page) for poster uden bogtrykt nøgle, og den mængdebaserede afledning af gældende medlemskab
-- (private.membership_current_set) = membership_is_current for hvert medlemskab. Syntetiske negative id'er; alt rulles
-- tilbage. Kald fixture-hjælperne som ejer.
BEGIN;
\ir fixtures/relation-5b.sql
\ir fixtures/placement-150.sql
\ir fixtures/relation-2a.sql
\ir fixtures/kalder-matrix.sql

-- Kilde med entry 'I' (canonical linje), header-kørsel og valgfrit sidekort.
CREATE FUNCTION pg_temp.k_src(p_source bigint,p_kort jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE f jsonb:=pg_temp.f150_source(p_source);
BEGIN
  UPDATE public.source SET sidekort=p_kort WHERE id=p_source;
  PERFORM private.write_header_evidence(p_source,(f->>'rend')::uuid,pg_temp.f150_run(),
    jsonb_build_array(pg_temp.f150_h('header_linje',500,'I DEN TESTSKE LINJE')));
  RETURN f;
END $$;

-- Medlemskab som promotionen skriver det (tilstand + state_sha256 på linje- og slægtsmedlemskab).
CREATE FUNCTION pg_temp.k_member(p_person bigint,p_pp uuid) RETURNS void LANGUAGE plpgsql AS $$
DECLARE v jsonb:=private.membership_state(p_pp); v_sha text;
BEGIN
  IF v IS NULL THEN RAISE EXCEPTION 'K_FIXTURE: ingen membership_state'; END IF;
  v_sha:=private.reimport_canonical_json_sha256(v);
  INSERT INTO public.person_lineage_membership(person_id,lineage_id,role,source_basis)
    VALUES (p_person,(v->>'lineage_id')::bigint,'member',v||jsonb_build_object('state_sha256',v_sha));
  INSERT INTO public.person_slaegt_membership(person_id,slaegt_id,membership_kind,source_basis)
    VALUES (p_person,(v->>'slaegt_id')::bigint,'agnatic',v||jsonb_build_object('state_sha256',v_sha));
END $$;

-- Hovedperson-post (som f5b_post, men forekomsten på PDF-side p_page; forekomster er tilføj-kun) med persona og
-- accepteret identitet til p_person. Uden legacy-række.
CREATE FUNCTION pg_temp.k_raw(f jsonb,p_key text,p_person bigint,p_page int) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_run uuid:=(f->>'run')::uuid; v_src bigint:=(f->>'source')::bigint; v_rec uuid; v_occ uuid; v_help uuid;
  v_persona uuid; v_mention uuid; v_text text:='Opdigtet Testesen, f. 1600.';
BEGIN
  INSERT INTO public.person(id) VALUES (p_person) ON CONFLICT DO NOTHING;
  INSERT INTO private.source_record(source_id,record_key,record_kind,created_run_id)
    VALUES (v_src,p_key,'person_post',v_run) RETURNING id INTO v_rec;
  INSERT INTO private.source_record_occurrence(rendition_id,occurrence_key,page_from,page_to,char_from,char_to,
    verbatim_text,physical_fingerprint,structural_fingerprint,extraction_run_id)
    VALUES ((f->>'rend')::uuid,'occ-'||p_key,p_page,p_page,1000,1000+char_length(v_text),v_text,repeat('3',64),repeat('4',64),v_run)
    RETURNING id INTO v_occ;
  INSERT INTO private.source_record_anchor_event(occurrence_id,source_record_id,decision_status,evidence,version,decided_by,decided_by_name)
    VALUES (v_occ,v_rec,'accepted','{"fixture":"6e2"}',1,(f->>'actor')::uuid,'fixture');
  INSERT INTO private.source_observation(occurrence_id,observation_kind,page_from,page_to,char_from,char_to,
    verbatim_text,quality_status,extraction_method,extraction_run_id)
    VALUES (v_occ,'person_post',p_page,p_page,1000,1000+char_length(v_text),v_text,'clear','fixture',v_run) RETURNING id INTO v_help;
  INSERT INTO private.source_mention(observation_id,mention_kind,char_from,char_to,verbatim_text,created_run_id)
    VALUES (v_help,'person_post',0,char_length(v_text),v_text,v_run) RETURNING id INTO v_mention;
  INSERT INTO private.source_persona(source_id,persona_key,created_run_id) VALUES (v_src,p_key,v_run) RETURNING id INTO v_persona;
  INSERT INTO private.source_persona_mention(persona_id,mention_id,mention_role,ordinal) VALUES (v_persona,v_mention,'primary',1);
  INSERT INTO private.source_persona_identity(source_persona_id,canonical_person_id,decision_status,version,evidence,
    decided_by,decided_by_name,decided_at)
    VALUES (v_persona,p_person,'accepted',1,'{"fixture":"6e2"}',(f->>'actor')::uuid,'fixture',clock_timestamp());
  RETURN jsonb_build_object('record',v_rec,'occ',v_occ,'helpost',v_help,'principal',v_persona,'key',p_key);
END $$;

-- Post uden placement med legacy-række (linje 'I', nr p_legacy).
CREATE FUNCTION pg_temp.k_plain(f jsonb,p_key text,p_person bigint,p_legacy int,p_page int) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE p jsonb:=pg_temp.k_raw(f,p_key,p_person,p_page);
BEGIN
  INSERT INTO public.person_external_id(person_id,source_id,linje,nr,record_key,slaegtled_lokal)
    VALUES (p_person,(f->>'source')::bigint,'I',p_legacy,p_key,1);
  RETURN p;
END $$;

-- Som k_plain plus record- og persona-placement på entry 'I' (slægtled, kuld, trykt nr.) og, når p_member, et
-- gældende medlemskab.
CREATE FUNCTION pg_temp.k_post(f jsonb,p_key text,p_person bigint,p_legacy int,p_page int,p_gen int,p_kuld text,
  p_nr text,p_member boolean) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE p jsonb:=pg_temp.k_plain(f,p_key,p_person,p_legacy,p_page); v_obs uuid; v_rp uuid; v_pp uuid;
BEGIN
  v_obs:=private.header_observation_uuid((f->>'rend')::uuid,'header-2018-20-v1',500);
  v_rp:=private.write_record_placement((p->>'record')::uuid,(f->>'entry')::bigint,
    jsonb_strip_nulls(jsonb_build_object('printed_number',p_nr,'generation_local',p_gen,'kuld_label',p_kuld)),v_obs,
    jsonb_build_object('rule_version','header-2018-20-v1','header_ids',jsonb_build_object('linje',v_obs)));
  v_pp:=private.write_persona_placement((p->>'principal')::uuid,v_rp,(p->>'helpost')::uuid,'{"rule":"test"}');
  IF p_member THEN PERFORM pg_temp.k_member(p_person,v_pp); END IF;
  RETURN p||jsonb_build_object('rp',v_rp,'pp',v_pp,'lineage',f->'lineage');
END $$;

-- Narrativ for personen i kilden med binding til posten (status p_status), privat eller ej.
CREATE FUNCTION pg_temp.k_bind(p_person bigint,p_source bigint,p_record uuid,p_status text,p_privat boolean)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_n bigint;
BEGIN
  INSERT INTO public.narrative(subjekt_type,subjekt_id,source_id,tekst,privat)
    VALUES ('person',p_person,p_source,'Opdigtet tekst',p_privat) RETURNING id INTO v_n;
  INSERT INTO private.narrative_record_publication(narrative_id,source_record_id,record_label,citation_label,status)
    VALUES (v_n,p_record,'','Opdigtet kilde',p_status);
END $$;

-- Én persons række i kilden, som anon uden uid (gæst; redaktøren ser også ikke-offentlige, jf.
-- fixtures/kalder-matrix.sql). Uid'en sættes tilbage.
CREATE FUNCTION pg_temp.k_row(p_person bigint,p_source bigint) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE r jsonb; n int; v_for text:=coalesce(current_setting('request.jwt.claim.sub',true),'');
BEGIN
  PERFORM set_config('request.jwt.claim.sub','',true);
  SET LOCAL ROLE anon;
  SELECT count(*),min(to_jsonb(c)::text)::jsonb INTO n,r FROM public.public_person_source_coordinates() c
   WHERE c.person_id=p_person AND c.source_id=p_source;
  RESET ROLE;
  PERFORM set_config('request.jwt.claim.sub',v_for,true);
  IF n<>1 THEN RAISE EXCEPTION 'KOORDINATER_TEST_FAILED: % i % har % rækker',p_person,p_source,n; END IF;
  RETURN r;
END $$;

-- Kontrakt: returkolonnerne i fast orden, printed_page sidst; anon/authenticated må kalde RPC'en, ikke mængdefunktionen.
DO $kontrakt$
BEGIN
  IF (SELECT array_to_string(p.proargnames,',') FROM pg_proc p WHERE p.oid='public.public_person_source_coordinates()'::regprocedure)
     IS DISTINCT FROM 'person_id,source_id,legacy_line_code,printed_number,printed_number_label,generation_local,generation_global,kuld_label,provenance_kind,printed_page' THEN
    RAISE EXCEPTION 'KOORDINATER_TEST_FAILED: returkolonner';
  END IF;
  IF to_regprocedure('private.membership_current_set()') IS NULL THEN
    RAISE EXCEPTION 'KOORDINATER_TEST_FAILED: private.membership_current_set() mangler';
  END IF;
  IF NOT has_function_privilege('anon','public.public_person_source_coordinates()','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.public_person_source_coordinates()','EXECUTE')
     OR has_function_privilege('anon','private.membership_current_set()','EXECUTE')
     OR has_function_privilege('authenticated','private.membership_current_set()','EXECUTE')
     OR has_function_privilege('service_role','private.membership_current_set()','EXECUTE') THEN
    RAISE EXCEPTION 'KOORDINATER_TEST_FAILED: ACL';
  END IF;
  RAISE NOTICE 'OK: kontrakt';
END $kontrakt$;

DO $gate$
DECLARE fa jsonb; fb jsonb; fc jsonb; p jsonb; q jsonb; r jsonb; v_occ uuid;
BEGIN
  -- Kilde A med sidekort (PDF 490-545 = s. 1-56).
  fa:=pg_temp.k_src(-6401,'[{"pdf_fra":490,"pdf_til":545,"trykt_fra":1}]');
  -- To kuld i samme entry og slægtled, begge nr. 1 ⇒ entydige på (entry, slægtled, kuld, nr.) ⇒ placement.
  PERFORM pg_temp.k_post(fa,'record-64010000-0000-4000-8000-000000000001',-640101,11,538,3,'I','1',true);
  PERFORM pg_temp.k_post(fa,'record-64010000-0000-4000-8000-000000000002',-640102,12,541,3,'II','1',true);
  -- Én unummereret alene i sin gruppe ⇒ placement med NULL nr.
  PERFORM pg_temp.k_post(fa,'record-64010000-0000-4000-8000-000000000003',-640103,13,539,1,NULL,NULL,true);
  -- Legacy-række uden binding ⇒ printed_page NULL.
  PERFORM pg_temp.k_plain(fa,'record-64010000-0000-4000-8000-000000000004',-640104,14,540);
  -- Legacy-række med publiceret binding til en post uden bognøgle (PDF 540) ⇒ s. 51.
  p:=pg_temp.k_plain(fa,'record-64010000-0000-4000-8000-000000000005',-640105,15,540);
  PERFORM pg_temp.k_bind(-640105,-6401,(p->>'record')::uuid,'published',false);
  -- Kladdebinding og privat narrativ tæller ikke ⇒ NULL.
  p:=pg_temp.k_plain(fa,'record-64010000-0000-4000-8000-000000000006',-640106,16,540);
  PERFORM pg_temp.k_bind(-640106,-6401,(p->>'record')::uuid,'draft',false);
  p:=pg_temp.k_plain(fa,'record-64010000-0000-4000-8000-000000000007',-640107,17,540);
  PERFORM pg_temp.k_bind(-640107,-6401,(p->>'record')::uuid,'published',true);
  -- To publicerede bindinger for samme (person, kilde): den mindste PDF-side over begge poster (PDF 538 ⇒ s. 49).
  p:=pg_temp.k_plain(fa,'record-64010000-0000-4000-8000-000000000008',-640108,18,543);
  PERFORM pg_temp.k_bind(-640108,-6401,(p->>'record')::uuid,'published',false);
  q:=pg_temp.k_raw(fa,'record-64010000-0000-4000-8000-000000000009',-640108,538);
  PERFORM pg_temp.k_bind(-640108,-6401,(q->>'record')::uuid,'published',false);
  -- Gældende placement uden legacy-række (PDF 545 ⇒ s. 56) tabes ikke.
  PERFORM pg_temp.k_post(fa,'record-64010000-0000-4000-8000-000000000010',-640110,20,545,4,NULL,'7',true);
  DELETE FROM public.person_external_id WHERE person_id=-640110 AND source_id=-6401;
  -- Kun gældende ankre tæller: et anker på PDF 538, der er accepteret (v1) og siden afvist (v2), flytter ikke
  -- startsiden fra postens andet anker på PDF 541 (s. 52).
  p:=pg_temp.k_plain(fa,'record-64010000-0000-4000-8000-000000000011',-640111,21,541);
  INSERT INTO private.source_record_occurrence(rendition_id,occurrence_key,page_from,page_to,char_from,char_to,
    verbatim_text,physical_fingerprint,structural_fingerprint,extraction_run_id)
    VALUES ((fa->>'rend')::uuid,'occ-ekstra-11',538,538,2000,2020,'Opdigtet ekstra',repeat('3',64),repeat('4',64),
      (fa->>'run')::uuid) RETURNING id INTO v_occ;
  INSERT INTO private.source_record_anchor_event(occurrence_id,source_record_id,decision_status,evidence,version,decided_by,decided_by_name)
    VALUES (v_occ,(p->>'record')::uuid,'accepted','{"fixture":"6e2"}',1,(fa->>'actor')::uuid,'fixture'),
           (v_occ,(p->>'record')::uuid,'rejected','{"fixture":"6e2"}',2,(fa->>'actor')::uuid,'fixture');
  PERFORM pg_temp.k_bind(-640111,-6401,(p->>'record')::uuid,'published',false);

  r:=pg_temp.k_row(-640101,-6401);
  IF r->>'provenance_kind'<>'placement' OR r->>'legacy_line_code'<>'I' OR (r->>'printed_number')::int<>1
     OR r->>'printed_number_label'<>'1' OR r->>'kuld_label'<>'I' OR (r->>'generation_local')::int<>3
     OR r->>'printed_page' IS DISTINCT FROM '49' THEN
    RAISE EXCEPTION 'KOORDINATER_TEST_FAILED: kuld I nr. 1 %',r;
  END IF;
  r:=pg_temp.k_row(-640102,-6401);
  IF r->>'provenance_kind'<>'placement' OR r->>'printed_number_label'<>'1' OR r->>'kuld_label'<>'II'
     OR r->>'printed_page' IS DISTINCT FROM '52' THEN
    RAISE EXCEPTION 'KOORDINATER_TEST_FAILED: kuld II nr. 1 %',r;
  END IF;
  r:=pg_temp.k_row(-640103,-6401);
  IF r->>'provenance_kind'<>'placement' OR r->'printed_number'<>'null'::jsonb OR r->'printed_number_label'<>'null'::jsonb
     OR (r->>'generation_local')::int<>1 OR r->>'printed_page' IS DISTINCT FROM '50' THEN
    RAISE EXCEPTION 'KOORDINATER_TEST_FAILED: unummereret alene %',r;
  END IF;
  r:=pg_temp.k_row(-640104,-6401);
  IF r->>'provenance_kind'<>'legacy_external_id' OR (r->>'printed_number')::int<>14 OR r->'printed_page'<>'null'::jsonb THEN
    RAISE EXCEPTION 'KOORDINATER_TEST_FAILED: legacy uden binding %',r;
  END IF;
  r:=pg_temp.k_row(-640105,-6401);
  IF r->>'provenance_kind'<>'legacy_external_id' OR r->>'legacy_line_code'<>'I' OR (r->>'printed_number')::int<>15
     OR r->>'printed_page' IS DISTINCT FROM '51' THEN
    RAISE EXCEPTION 'KOORDINATER_TEST_FAILED: legacy med binding %',r;
  END IF;
  IF pg_temp.k_row(-640106,-6401)->'printed_page'<>'null'::jsonb OR pg_temp.k_row(-640107,-6401)->'printed_page'<>'null'::jsonb THEN
    RAISE EXCEPTION 'KOORDINATER_TEST_FAILED: kladde/privat binding gav side';
  END IF;
  r:=pg_temp.k_row(-640110,-6401);
  IF r->>'provenance_kind'<>'placement' OR r->>'printed_number_label'<>'7' OR r->>'printed_page' IS DISTINCT FROM '56' THEN
    RAISE EXCEPTION 'KOORDINATER_TEST_FAILED: placement uden legacy-række %',r;
  END IF;
  IF pg_temp.k_row(-640111,-6401)->>'printed_page' IS DISTINCT FROM '52' THEN
    RAISE EXCEPTION 'KOORDINATER_TEST_FAILED: afvist anker talte %',pg_temp.k_row(-640111,-6401);
  END IF;
  IF pg_temp.k_row(-640108,-6401)->>'printed_page' IS DISTINCT FROM '49' THEN
    RAISE EXCEPTION 'KOORDINATER_TEST_FAILED: to bindinger %',pg_temp.k_row(-640108,-6401);
  END IF;

  -- Kilde B uden sidekort: record-post ⇒ page_from uændret; bognøgle ⇒ NULL (også for legacy-række med binding).
  fb:=pg_temp.k_src(-6402,NULL);
  PERFORM pg_temp.k_post(fb,'record-64020000-0000-4000-8000-000000000001',-640201,1,538,2,NULL,'1',true);
  PERFORM pg_temp.k_post(fb,'V-1',-640202,2,538,2,NULL,'2',true);
  p:=pg_temp.k_plain(fb,'V-3',-640203,3,540);
  PERFORM pg_temp.k_bind(-640203,-6402,(p->>'record')::uuid,'published',false);
  r:=pg_temp.k_row(-640201,-6402);
  IF r->>'provenance_kind'<>'placement' OR r->>'printed_page' IS DISTINCT FROM '538' THEN
    RAISE EXCEPTION 'KOORDINATER_TEST_FAILED: uden kort %',r;
  END IF;
  r:=pg_temp.k_row(-640202,-6402);
  IF r->>'provenance_kind'<>'placement' OR r->>'printed_number_label'<>'2' OR r->'printed_page'<>'null'::jsonb THEN
    RAISE EXCEPTION 'KOORDINATER_TEST_FAILED: bognøgle placement %',r;
  END IF;
  r:=pg_temp.k_row(-640203,-6402);
  IF r->>'provenance_kind'<>'legacy_external_id' OR r->'printed_page'<>'null'::jsonb THEN
    RAISE EXCEPTION 'KOORDINATER_TEST_FAILED: bognøgle legacy %',r;
  END IF;

  -- Kilde C: to rækker med ens nøgle (entry, slægtled 2, uden kuld, nr. 4) ⇒ hele kilden legacy, også nr. 5;
  -- legacy-rækken med binding får stadig startsiden.
  fc:=pg_temp.k_src(-6403,NULL);
  p:=pg_temp.k_post(fc,'record-64030000-0000-4000-8000-000000000001',-640301,41,538,2,NULL,'4',true);
  PERFORM pg_temp.k_post(fc,'record-64030000-0000-4000-8000-000000000002',-640302,42,539,2,NULL,'4',true);
  PERFORM pg_temp.k_post(fc,'record-64030000-0000-4000-8000-000000000003',-640303,43,540,2,NULL,'5',true);
  PERFORM pg_temp.k_bind(-640301,-6403,(p->>'record')::uuid,'published',false);
  r:=pg_temp.k_row(-640301,-6403);
  IF r->>'provenance_kind'<>'legacy_external_id' OR (r->>'printed_number')::int<>41 OR r->>'printed_page' IS DISTINCT FROM '538' THEN
    RAISE EXCEPTION 'KOORDINATER_TEST_FAILED: ens nøgle (1) %',r;
  END IF;
  IF pg_temp.k_row(-640302,-6403)->>'provenance_kind'<>'legacy_external_id'
     OR pg_temp.k_row(-640303,-6403)->>'provenance_kind'<>'legacy_external_id'
     OR pg_temp.k_row(-640303,-6403)->'printed_page'<>'null'::jsonb THEN
    RAISE EXCEPTION 'KOORDINATER_TEST_FAILED: ens nøgle ⇒ hele kilden legacy';
  END IF;
  RAISE NOTICE 'OK: kildegate og printed_page';
END $gate$;

-- Ækvivalens: mængdefunktionen = membership_is_current for hvert medlemskab, også når hvert led i reglen fejler.
DO $aekvivalens$
DECLARE fe jsonb; e jsonb; v_lin bigint; v_n int; v_diff int; v_cur int;
BEGIN
  fe:=pg_temp.k_src(-6405,NULL); v_lin:=(fe->>'lineage')::bigint;
  -- e1 gældende.
  PERFORM pg_temp.k_post(fe,'E-1',-640501,1,10,1,NULL,'1',true);
  -- e2 ændret state_sha256 på linjemedlemskabet.
  PERFORM pg_temp.k_post(fe,'E-2',-640502,2,10,1,NULL,'2',true);
  UPDATE public.person_lineage_membership SET source_basis=jsonb_set(source_basis,'{state_sha256}',to_jsonb(repeat('0',64)))
   WHERE person_id=-640502;
  -- e3 ny identitetsversion (samme person).
  e:=pg_temp.k_post(fe,'E-3',-640503,3,10,1,NULL,'3',true);
  PERFORM set_config('request.jwt.claim.sub',fe->>'actor',true);
  PERFORM pg_temp.f2a_event_for_state((e->>'principal')::uuid);
  SELECT version INTO v_n FROM private.source_persona_identity WHERE source_persona_id=(e->>'principal')::uuid;
  PERFORM private.decide_source_persona_identity((e->>'principal')::uuid,-640503,v_n,'accepted',
    '{"basis":"web_detail","note":"6e2 ny version"}','human');
  -- e4 persona-placement afløst.
  e:=pg_temp.k_post(fe,'E-4',-640504,4,10,1,NULL,'4',true);
  INSERT INTO private.source_persona_placement_decision(placement_id,version,decision_status,evidence,decision_origin,decided_by,decided_by_name)
    VALUES ((e->>'pp')::uuid,2,'superseded','{"fixture":"6e2"}','redaction',(fe->>'actor')::uuid,'fixture');
  -- e5 record-placement afløst.
  e:=pg_temp.k_post(fe,'E-5',-640505,5,10,1,NULL,'5',true);
  INSERT INTO private.source_record_placement_decision(placement_id,version,decision_status,evidence,decision_origin,decided_by,decided_by_name)
    VALUES ((e->>'rp')::uuid,2,'superseded','{"fixture":"6e2"}','redaction',(fe->>'actor')::uuid,'fixture');
  -- e6 slægtsmedlemskabets hash afviger.
  PERFORM pg_temp.k_post(fe,'E-6',-640506,6,10,1,NULL,'6',true);
  UPDATE public.person_slaegt_membership SET source_basis=jsonb_set(source_basis,'{state_sha256}',to_jsonb(repeat('0',64)))
   WHERE person_id=-640506;
  -- e7 uden state_sha256 (membership_is_current giver NULL); e8 uden persona_placement_id.
  PERFORM pg_temp.k_post(fe,'E-7',-640507,7,10,1,NULL,'7',true);
  UPDATE public.person_lineage_membership SET source_basis=source_basis-'state_sha256' WHERE person_id=-640507;
  PERFORM pg_temp.k_post(fe,'E-8',-640508,8,10,1,NULL,'8',true);
  UPDATE public.person_lineage_membership SET source_basis='{}'::jsonb WHERE person_id=-640508;
  -- e9 e1's tilstand lagt på en anden person.
  INSERT INTO public.person(id) VALUES (-640509);
  INSERT INTO public.person_lineage_membership(person_id,lineage_id,role,source_basis)
    SELECT -640509,lineage_id,'member',source_basis FROM public.person_lineage_membership WHERE person_id=-640501;
  INSERT INTO public.person_slaegt_membership(person_id,slaegt_id,membership_kind,source_basis)
    SELECT -640509,slaegt_id,'agnatic',source_basis FROM public.person_slaegt_membership WHERE person_id=-640501;

  SELECT count(*) INTO v_diff FROM (
    (SELECT m.person_id,m.lineage_id FROM public.person_lineage_membership m
      WHERE private.membership_is_current(m.person_id,m.lineage_id) IS TRUE
     EXCEPT SELECT s.person_id,s.lineage_id FROM private.membership_current_set() s)
    UNION ALL
    (SELECT s.person_id,s.lineage_id FROM private.membership_current_set() s
     EXCEPT SELECT m.person_id,m.lineage_id FROM public.person_lineage_membership m
      WHERE private.membership_is_current(m.person_id,m.lineage_id) IS TRUE)) d;
  SELECT count(*) INTO v_cur FROM private.membership_current_set() s WHERE s.person_id BETWEEN -640599 AND -640500;
  IF v_diff<>0 OR v_cur<>1
     OR (SELECT count(*) FROM private.membership_current_set())<>(SELECT count(*) FROM private.membership_current_set() s2
          JOIN public.person_lineage_membership m USING (person_id,lineage_id)) THEN
    RAISE EXCEPTION 'KOORDINATER_TEST_FAILED: ækvivalens diff=% gældende_e=%',v_diff,v_cur;
  END IF;
  -- Mængden indeholder hvert par én gang.
  IF (SELECT count(*)-count(DISTINCT (s.person_id,s.lineage_id)) FROM private.membership_current_set() s)<>0 THEN
    RAISE EXCEPTION 'KOORDINATER_TEST_FAILED: dubletter i mængden';
  END IF;
  RAISE NOTICE 'OK: ækvivalens (% gældende i alt)',(SELECT count(*) FROM private.membership_current_set());
END $aekvivalens$;

-- Redaktøren ser levende (decisions 2026-11-13) sammen med 6e-2's trykte side: for en levende, privat eller staged
-- person ser kun redaktionen koordinatrækken, og den bærer printed_page — både placement-rækken (postens anker) og
-- legacy-rækken (publiceret binding på personens ikke-private narrativ). Gæst, uid uden profil og medlem ser 0.
DO $redaktoer$
DECLARE f jsonb; p jsonb;
  q_pl text:='SELECT * FROM public.public_person_source_coordinates() WHERE person_id=-648101 AND source_id=-6481
              AND provenance_kind=''placement'' AND printed_page=''49''';
  q_lg text:='SELECT * FROM public.public_person_source_coordinates() WHERE person_id=-648102 AND source_id=-6481
              AND provenance_kind=''legacy_external_id'' AND printed_page=''51''';
BEGIN
  PERFORM pg_temp.km_kaldere();
  f:=pg_temp.k_src(-6481,'[{"pdf_fra":490,"pdf_til":545,"trykt_fra":1}]');
  PERFORM pg_temp.k_post(f,'record-64810000-0000-4000-8000-000000000001',-648101,1,538,1,NULL,'1',true);
  p:=pg_temp.k_plain(f,'record-64810000-0000-4000-8000-000000000002',-648102,2,540);
  PERFORM pg_temp.k_bind(-648102,-6481,(p->>'record')::uuid,'published',false);
  PERFORM pg_temp.km_forvent('trykt side afdød, placement',q_pl,1,1);
  PERFORM pg_temp.km_forvent('trykt side afdød, legacy',q_lg,1,1);
  UPDATE public.person SET levende=true WHERE id IN (-648101,-648102);
  PERFORM pg_temp.km_forvent('trykt side levende, placement',q_pl,0,1);
  PERFORM pg_temp.km_forvent('trykt side levende, legacy',q_lg,0,1);
  UPDATE public.person SET levende=false,privat=true WHERE id IN (-648101,-648102);
  PERFORM pg_temp.km_forvent('trykt side privat, placement',q_pl,0,1);
  PERFORM pg_temp.km_forvent('trykt side privat, legacy',q_lg,0,1);
  UPDATE public.person SET privat=false,staged=true WHERE id IN (-648101,-648102);
  PERFORM pg_temp.km_forvent('trykt side staged, placement',q_pl,0,1);
  PERFORM pg_temp.km_forvent('trykt side staged, legacy',q_lg,0,1);
  UPDATE public.person SET staged=false WHERE id IN (-648101,-648102);
  RAISE NOTICE 'OK: redaktøren ser levende med trykt side';
END $redaktoer$;

-- Total orden og entydighed over hele RPC'en som anon uden uid (gæst).
DO $orden$
DECLARE v_dup int; v_order int;
BEGIN
  PERFORM set_config('request.jwt.claim.sub','',true);
  SET LOCAL ROLE anon;
  SELECT count(*)-count(DISTINCT (r.person_id,r.source_id)) INTO v_dup FROM public.public_person_source_coordinates() r;
  SELECT count(*) INTO v_order FROM (
    SELECT r.person_id,r.source_id,lag(r.person_id) OVER () AS pp,lag(r.source_id) OVER () AS ps
      FROM public.public_person_source_coordinates() r) x
   WHERE (x.pp,x.ps) > (x.person_id,x.source_id);
  RESET ROLE;
  IF v_dup<>0 OR v_order<>0 THEN RAISE EXCEPTION 'KOORDINATER_TEST_FAILED: orden dup=% bagud=%',v_dup,v_order; END IF;
  RAISE NOTICE 'OK: orden';
END $orden$;
ROLLBACK;
