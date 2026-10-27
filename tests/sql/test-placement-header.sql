-- #150 trin 5c-1 (spec 2026-10-26 §4.1): placement-header som strukturel forekomst (sti ii) ved siden af
-- den gamle sti (kind 'header' i postens egen ankrede forekomst), og nærmeste-reglen som helbredsassert.
\set ON_ERROR_STOP on

BEGIN;
\ir fixtures/relation-5b.sql

-- Kilde, post (forekomst ved tegn 1000) og et stamtavle-entry for kilden; en header-kørsel.
CREATE OR REPLACE FUNCTION pg_temp.f150_setup(p_source bigint) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_actor uuid:='a1500000-0000-0000-0000-000000000150'; v_src jsonb; v_post jsonb; v_slaegt bigint;
  v_scheme bigint; v_entry bigint; v_hrun uuid:=gen_random_uuid();
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  v_src:=pg_temp.f5b_source(p_source);
  v_post:=pg_temp.f5b_post(p_source,v_src,'I-1','Anna Testesen, f. 1600.',ARRAY['Anna Testesen'],NULL,v_actor);
  INSERT INTO public.slaegt(navn,sorteringsnavn,slug,status)
    VALUES ('150 fixture '||p_source,'150 fixture '||p_source,'f150-'||abs(p_source),'active') RETURNING id INTO v_slaegt;
  INSERT INTO public.lineage_scheme(slaegt_id,source_id,kind,label) VALUES (v_slaegt,p_source,'stamtavle','150 fixture')
    RETURNING id INTO v_scheme;
  INSERT INTO public.lineage_scheme_entry(scheme_id,slaegt_id,code,label,sort_order)
    VALUES (v_scheme,v_slaegt,'I','I. linje',1) RETURNING id INTO v_entry;
  INSERT INTO private.extraction_run(id,source_id,run_key,schema_version,extractor_version,profile_version,input_sha256,manifest)
    VALUES (v_hrun,p_source,'header-2018-20-v1','fixture','fixture','fixture',repeat('5',64),'{}');
  RETURN jsonb_build_object('src',v_src,'post',v_post,'entry',v_entry,'hrun',v_hrun,'actor',v_actor);
END $$;

-- Én uankret strukturel forekomst med én header-observation (samme kørsel som forekomsten, medmindre p_obs_run).
CREATE OR REPLACE FUNCTION pg_temp.f150_header(p_rend uuid,p_run uuid,p_kind text,p_char_from int,p_text text,
  p_obs_run uuid DEFAULT NULL) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_occ uuid; v_obs uuid;
BEGIN
  INSERT INTO private.source_record_occurrence(rendition_id,occurrence_key,page_from,page_to,char_from,char_to,
    verbatim_text,physical_fingerprint,structural_fingerprint,extraction_run_id)
    VALUES (p_rend,'header:'||p_char_from,10,10,p_char_from,p_char_from+char_length(p_text),p_text,repeat('6',64),
      repeat('7',64),p_run) RETURNING id INTO v_occ;
  INSERT INTO private.source_observation(occurrence_id,observation_kind,page_from,page_to,char_from,char_to,
    verbatim_text,quality_status,extraction_method,extraction_run_id)
    VALUES (v_occ,p_kind,10,10,p_char_from,p_char_from+char_length(p_text),p_text,'clear','header-2018-20-v1',
      coalesce(p_obs_run,p_run)) RETURNING id INTO v_obs;
  RETURN v_obs;
END $$;

CREATE OR REPLACE FUNCTION pg_temp.f150_place(f jsonb,p_header uuid) RETURNS uuid LANGUAGE sql AS $$
  INSERT INTO private.source_record_placement(source_record_id,scheme_entry_id,header_observation_id,initial_status)
    VALUES ((f#>>'{post,record}')::uuid,(f->>'entry')::bigint,p_header,'accepted') RETURNING id;
$$;

CREATE OR REPLACE FUNCTION pg_temp.f150_expect_header_required(f jsonb,p_header uuid,p_case text) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE v_err text;
BEGIN
  BEGIN
    PERFORM pg_temp.f150_place(f,p_header);
    RAISE EXCEPTION 'PLACEMENT_HEADER_TEST_FAILED: % godtaget',p_case;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT;
    IF v_err NOT LIKE 'EVIDENCE_PLACEMENT_HEADER_REQUIRED%' THEN RAISE; END IF;
  END;
END $$;

-- Accepteret v1 (migration) med reglens header-id'er i evidence.
CREATE OR REPLACE FUNCTION pg_temp.f150_accept(p_placement uuid,p_header_ids jsonb) RETURNS void LANGUAGE sql AS $$
  INSERT INTO private.source_record_placement_decision(placement_id,version,decision_status,evidence,decision_origin,decided_by_name)
    VALUES (p_placement,1,'accepted',jsonb_build_object('rule_version','header-2018-20-v1','header_ids',p_header_ids),
      'migration','150 fixture');
$$;

DO $vokabular$
BEGIN
  IF (SELECT count(*) FROM private.vocab WHERE scheme='observation_kind'
       AND code IN ('header_linje','header_slaegtled','header_kuld','header_aegteskab'))<>4 THEN
    RAISE EXCEPTION 'PLACEMENT_HEADER_TEST_FAILED: vokabularkoderne mangler';
  END IF;
END $vokabular$;

DO $sti_ii_ok$
DECLARE f jsonb:=pg_temp.f150_setup(-1501); v_h uuid; v_s uuid; v_p uuid;
BEGIN
  v_h:=pg_temp.f150_header((f#>>'{src,rend}')::uuid,(f->>'hrun')::uuid,'header_linje',500,'I DEN TESTSKE LINJE');
  v_s:=pg_temp.f150_header((f#>>'{src,rend}')::uuid,(f->>'hrun')::uuid,'header_slaegtled',600,'Første slægtled');
  v_p:=pg_temp.f150_place(f,v_h);
  PERFORM pg_temp.f150_accept(v_p,jsonb_build_object('linje',v_h,'slaegtled',v_s));
  IF private.placement_header_violations(-1501)<>0 THEN
    RAISE EXCEPTION 'PLACEMENT_HEADER_TEST_FAILED: korrekt nærmeste-placement talt som brud';
  END IF;
END $sti_ii_ok$;

DO $sti_ii_efter_posten$
DECLARE f jsonb:=pg_temp.f150_setup(-1502);
BEGIN
  PERFORM pg_temp.f150_expect_header_required(f,
    pg_temp.f150_header((f#>>'{src,rend}')::uuid,(f->>'hrun')::uuid,'header_linje',2000,'II DEN SENERE LINJE'),'header efter posten');
END $sti_ii_efter_posten$;

DO $sti_ii_ankret$
DECLARE f jsonb:=pg_temp.f150_setup(-1503); v_h uuid; v_rec uuid;
BEGIN
  v_h:=pg_temp.f150_header((f#>>'{src,rend}')::uuid,(f->>'hrun')::uuid,'header_linje',500,'I DEN TESTSKE LINJE');
  INSERT INTO private.source_record(source_id,record_key,record_kind,created_run_id)
    VALUES (-1503,'I-0','person_post',(f->>'hrun')::uuid) RETURNING id INTO v_rec;
  INSERT INTO private.source_record_anchor_event(occurrence_id,source_record_id,decision_status,evidence,version,decided_by,decided_by_name)
    SELECT o.occurrence_id,v_rec,'accepted','{"fixture":"150"}',1,(f->>'actor')::uuid,'fixture'
      FROM private.source_observation o WHERE o.id=v_h;
  PERFORM pg_temp.f150_expect_header_required(f,v_h,'ankret header-forekomst');
END $sti_ii_ankret$;

DO $sti_ii_anden_rendition$
DECLARE f jsonb:=pg_temp.f150_setup(-1504); v_rend uuid:=gen_random_uuid();
BEGIN
  INSERT INTO private.source_rendition(id,source_id,rendition_key,rendition_kind,content_sha256,metadata)
    VALUES (v_rend,-1504,'150-anden','pdf_text_layer',repeat('8',64),'{}');
  PERFORM pg_temp.f150_expect_header_required(f,
    pg_temp.f150_header(v_rend,(f->>'hrun')::uuid,'header_linje',500,'I DEN TESTSKE LINJE'),'anden rendition');
END $sti_ii_anden_rendition$;

DO $sti_ii_forkert_kind$
DECLARE f jsonb:=pg_temp.f150_setup(-1505);
BEGIN
  PERFORM pg_temp.f150_expect_header_required(f,
    pg_temp.f150_header((f#>>'{src,rend}')::uuid,(f->>'hrun')::uuid,'header_kuld',500,'I'),'header_kuld som linje-header');
END $sti_ii_forkert_kind$;

DO $sti_ii_anden_koersel$
DECLARE f jsonb:=pg_temp.f150_setup(-1506);
BEGIN
  PERFORM pg_temp.f150_expect_header_required(f,
    pg_temp.f150_header((f#>>'{src,rend}')::uuid,(f->>'hrun')::uuid,'header_linje',500,'I DEN TESTSKE LINJE',
      (f#>>'{src,run}')::uuid),'observation fra anden kørsel end forekomsten');
END $sti_ii_anden_koersel$;

DO $sti_i_uaendret$
DECLARE f jsonb:=pg_temp.f150_setup(-1507); v_h uuid;
BEGIN
  INSERT INTO private.source_observation(occurrence_id,observation_kind,page_from,page_to,char_from,char_to,
    verbatim_text,quality_status,extraction_method,extraction_run_id)
    VALUES ((f#>>'{post,occ}')::uuid,'header',10,10,1000,1005,'Anna ','clear','fixture',(f#>>'{src,run}')::uuid)
    RETURNING id INTO v_h;
  PERFORM pg_temp.f150_place(f,v_h);
  -- Den gamle sti uden header_ids i evidence tælles ikke af nærmeste-reglen (den gælder kun sti ii).
  PERFORM pg_temp.f150_accept((SELECT id FROM private.source_record_placement WHERE header_observation_id=v_h),'{}'::jsonb);
  IF private.placement_header_violations(-1507)<>0 THEN
    RAISE EXCEPTION 'PLACEMENT_HEADER_TEST_FAILED: sti i talt af nærmeste-reglen';
  END IF;
END $sti_i_uaendret$;

DO $ikke_naermeste$
DECLARE f jsonb:=pg_temp.f150_setup(-1508); v_old uuid; v_new uuid; v_k uuid; v_s uuid; v_p uuid;
  r uuid:=(f#>>'{src,rend}')::uuid; h uuid:=(f->>'hrun')::uuid;
BEGIN
  v_old:=pg_temp.f150_header(r,h,'header_linje',100,'I DEN ÆLDRE LINJE');
  v_k:=pg_temp.f150_header(r,h,'header_kuld',200,'I');
  v_new:=pg_temp.f150_header(r,h,'header_linje',500,'I DEN NYERE LINJE');
  v_s:=pg_temp.f150_header(r,h,'header_slaegtled',600,'Første slægtled');
  -- Ældre linjeoverskrift med en nyere imellem → ét brud.
  v_p:=pg_temp.f150_place(f,v_old);
  PERFORM pg_temp.f150_accept(v_p,jsonb_build_object('linje',v_old,'slaegtled',v_s));
  IF private.placement_header_violations(-1508)<>1 THEN
    RAISE EXCEPTION 'PLACEMENT_HEADER_TEST_FAILED: ikke-nærmeste linjeoverskrift ikke talt (%)',
      private.placement_header_violations(-1508);
  END IF;
END $ikke_naermeste$;

DO $annulleret_kuld$
DECLARE f jsonb:=pg_temp.f150_setup(-1509); v_l uuid; v_k uuid; v_s uuid; v_p uuid;
  r uuid:=(f#>>'{src,rend}')::uuid; h uuid:=(f->>'hrun')::uuid;
BEGIN
  v_l:=pg_temp.f150_header(r,h,'header_linje',100,'I DEN TESTSKE LINJE');
  v_k:=pg_temp.f150_header(r,h,'header_kuld',200,'I');
  v_s:=pg_temp.f150_header(r,h,'header_slaegtled',600,'Andet slægtled');
  -- Kuld fra før slægtledsoverskriften er annulleret: at citere det er et brud.
  v_p:=pg_temp.f150_place(f,v_l);
  PERFORM pg_temp.f150_accept(v_p,jsonb_build_object('linje',v_l,'slaegtled',v_s,'kuld',v_k));
  IF private.placement_header_violations(-1509)<>1 THEN
    RAISE EXCEPTION 'PLACEMENT_HEADER_TEST_FAILED: annulleret kuld ikke talt';
  END IF;
END $annulleret_kuld$;

DO $udeladt_slaegtled$
DECLARE f jsonb:=pg_temp.f150_setup(-1510); v_l uuid; v_p uuid; r uuid:=(f#>>'{src,rend}')::uuid; h uuid:=(f->>'hrun')::uuid;
BEGIN
  v_l:=pg_temp.f150_header(r,h,'header_linje',100,'I DEN TESTSKE LINJE');
  PERFORM pg_temp.f150_header(r,h,'header_slaegtled',600,'Andet slægtled');
  -- At udelade en observeret slægtledsoverskrift er også et brud (intet opfindes, intet tabes).
  v_p:=pg_temp.f150_place(f,v_l);
  PERFORM pg_temp.f150_accept(v_p,jsonb_build_object('linje',v_l));
  IF private.placement_header_violations(-1510)<>1 THEN
    RAISE EXCEPTION 'PLACEMENT_HEADER_TEST_FAILED: udeladt slægtled ikke talt';
  END IF;
END $udeladt_slaegtled$;

-- Codex r1 #4: en ankret forekomst eller en overskrift, der overlapper posten, er ikke en strukturel overskrift før posten
-- og må ikke regnes som »nærmeste« (en placement, der udelader den, er korrekt).
DO $anker_og_overlap$
DECLARE f jsonb; v_l uuid; v_s uuid; v_p uuid; v_rec uuid; r uuid; h uuid;
BEGIN
  f:=pg_temp.f150_setup(-1511); r:=(f#>>'{src,rend}')::uuid; h:=(f->>'hrun')::uuid;
  v_l:=pg_temp.f150_header(r,h,'header_linje',100,'I DEN TESTSKE LINJE');
  v_s:=pg_temp.f150_header(r,h,'header_slaegtled',600,'Andet slægtled');
  INSERT INTO private.source_record(source_id,record_key,record_kind,created_run_id)
    VALUES (-1511,'I-0','person_post',h) RETURNING id INTO v_rec;
  INSERT INTO private.source_record_anchor_event(occurrence_id,source_record_id,decision_status,evidence,version,decided_by,decided_by_name)
    SELECT o.occurrence_id,v_rec,'accepted','{"fixture":"150"}',1,(f->>'actor')::uuid,'fixture' FROM private.source_observation o WHERE o.id=v_s;
  v_p:=pg_temp.f150_place(f,v_l);
  PERFORM pg_temp.f150_accept(v_p,jsonb_build_object('linje',v_l));
  IF private.placement_header_violations(-1511)<>0 THEN
    RAISE EXCEPTION 'PLACEMENT_HEADER_TEST_FAILED: ankret slægtledsforekomst regnet som nærmeste';
  END IF;
  f:=pg_temp.f150_setup(-1512); r:=(f#>>'{src,rend}')::uuid; h:=(f->>'hrun')::uuid;
  v_l:=pg_temp.f150_header(r,h,'header_linje',100,'I DEN TESTSKE LINJE');
  PERFORM pg_temp.f150_header(r,h,'header_slaegtled',990,'Overlappende slægtled');
  v_p:=pg_temp.f150_place(f,v_l);
  PERFORM pg_temp.f150_accept(v_p,jsonb_build_object('linje',v_l));
  IF private.placement_header_violations(-1512)<>0 THEN
    RAISE EXCEPTION 'PLACEMENT_HEADER_TEST_FAILED: overskrift, der overlapper posten, regnet som nærmeste';
  END IF;
END $anker_og_overlap$;

\echo PLACEMENT_HEADER_TEST_OK
ROLLBACK;
