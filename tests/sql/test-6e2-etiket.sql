\set ON_ERROR_STOP on
-- Trin 6e-2 Task 2: postetiket (narrative_record_wanted_labels), linje_kode, tom postdel. Syntetiske negative id'er; alt rulles tilbage.
BEGIN;
INSERT INTO public.source(id,slags,titel,udgave,aar,sidekort) VALUES
  (-6301,'DAA-udgave','etiket-bognoegle','DAA B',1900,NULL),
  (-6302,'DAA-udgave','etiket-uuid','DAA X',1990,'[{"pdf_fra":490,"pdf_til":545,"trykt_fra":1}]');
INSERT INTO public.slaegt(navn,sorteringsnavn,slug,status) VALUES ('6e2 etiket','6e2 etiket','f6e2etiket','active');
INSERT INTO private.extraction_run(id,source_id,run_key,schema_version,extractor_version,profile_version,input_sha256,manifest) VALUES
  ('62000000-0000-4000-8000-000000000001',-6301,'6e2-a','f','f','f',repeat('1',64),'{}'),
  ('62000000-0000-4000-8000-000000000002',-6302,'6e2-b','f','f','f',repeat('1',64),'{}');
INSERT INTO private.source_rendition(id,source_id,rendition_key,rendition_kind,content_sha256,metadata) VALUES
  ('62000000-0000-4000-8000-0000000000a1',-6301,'6e2-r1','pdf_text_layer',repeat('2',64),'{}'),
  ('62000000-0000-4000-8000-0000000000a2',-6302,'6e2-r2','pdf_text_layer',repeat('2',64),'{}');
INSERT INTO public.lineage_scheme(slaegt_id,source_id,kind,label)
  SELECT id,-6301,'stamtavle','6e2 a' FROM public.slaegt WHERE slug='f6e2etiket';
INSERT INTO public.lineage_scheme(slaegt_id,source_id,kind,label)
  SELECT id,-6302,'stamtavle','6e2 b' FROM public.slaegt WHERE slug='f6e2etiket';
INSERT INTO public.lineage_scheme_entry(scheme_id,slaegt_id,code,label,sort_order)
  SELECT s.id,s.slaegt_id,x.code,x.label,x.so FROM public.lineage_scheme s,
   (VALUES ('V','Den grevelige linje af 1673',1),('IV','IV. Den danske grevelige Linje af 1673.',2),
           ('Stamme-x','A. Den holstenske Linje.',3)) x(code,label,so)
   WHERE s.source_id=-6302;
INSERT INTO public.lineage_scheme_entry(scheme_id,slaegt_id,code,label,sort_order)
  SELECT s.id,s.slaegt_id,'V','Den grevelige linje af 1673',1 FROM public.lineage_scheme s WHERE s.source_id=-6301;

-- Hjælper: post med forekomst på PDF-side p_page, og valgfri accepteret placement (entry-kode, trykt nr).
CREATE FUNCTION pg_temp.mk(p_source bigint,p_key text,p_page int,p_entries text[],p_nr text[]) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_rec uuid; v_occ uuid; v_run uuid; v_rend uuid; v_obs uuid; v_pl uuid; i int; v_entry bigint;
BEGIN
  SELECT id INTO v_run FROM private.extraction_run WHERE source_id=p_source;
  SELECT id INTO v_rend FROM private.source_rendition WHERE source_id=p_source;
  INSERT INTO private.source_record(source_id,record_key,record_kind,created_run_id) VALUES (p_source,p_key,'person_post',v_run) RETURNING id INTO v_rec;
  INSERT INTO private.source_record_occurrence(rendition_id,occurrence_key,page_from,page_to,char_from,char_to,verbatim_text,physical_fingerprint,structural_fingerprint,extraction_run_id)
    VALUES (v_rend,'occ-'||p_key,p_page,p_page,100,200,'Opdigtet tekst',repeat('3',64),repeat('4',64),v_run) RETURNING id INTO v_occ;
  INSERT INTO private.source_record_anchor_event(occurrence_id,source_record_id,decision_status,evidence,version,decided_by,decided_by_name)
    VALUES (v_occ,v_rec,'accepted','{"fixture":"6e2"}',1,'62000000-0000-4000-8000-0000000000ff','fixture');
  FOR i IN 1..coalesce(array_length(p_entries,1),0) LOOP
    SELECT e.id INTO v_entry FROM public.lineage_scheme_entry e JOIN public.lineage_scheme s ON s.id=e.scheme_id
      WHERE s.source_id=p_source AND e.code=p_entries[i];
    INSERT INTO private.source_observation(occurrence_id,observation_kind,page_from,page_to,char_from,char_to,verbatim_text,quality_status,extraction_method,extraction_run_id)
      VALUES (v_occ,'header',p_page,p_page,100+i,104+i,'Over','clear','fixture',v_run) RETURNING id INTO v_obs;
    INSERT INTO private.source_record_placement(source_record_id,scheme_entry_id,printed_number,header_observation_id,initial_status)
      VALUES (v_rec,v_entry,p_nr[i],v_obs,'accepted') RETURNING id INTO v_pl;
    INSERT INTO private.source_record_placement_decision(placement_id,version,decision_status,evidence,decision_origin,decided_by_name)
      VALUES (v_pl,1,'accepted','{"fixture":"6e2"}','migration','fixture');
  END LOOP;
  RETURN v_rec;
END $$;

-- linje_kode
DO $t$
BEGIN
  IF private.linje_kode('IV. Den danske grevelige Linje af 1673.','IV') IS DISTINCT FROM 'IV'
     OR private.linje_kode('A. Den holstenske Linje.','Stamme-x') IS DISTINCT FROM 'A'
     OR private.linje_kode('Den grevelige linje af 1673','V') IS DISTINCT FROM 'V'
     OR private.linje_kode('XIV. linje','x') IS DISTINCT FROM 'XIV' THEN
    RAISE EXCEPTION 'TEST_FAILED: linje_kode';
  END IF;
  IF private.record_key_uden_bognoegle('record-62000000-0000-4000-8000-0000000000a1') IS NOT TRUE
     OR private.record_key_uden_bognoegle('V-1') IS NOT FALSE
     OR private.record_key_uden_bognoegle('record-62000000-0000-4000-8000-0000000000A1') IS NOT FALSE
     OR private.record_key_uden_bognoegle('xrecord-62000000-0000-4000-8000-0000000000a1') IS NOT FALSE THEN
    RAISE EXCEPTION 'TEST_FAILED: record_key_uden_bognoegle';
  END IF;
END $t$;

CREATE FUNCTION pg_temp.w(p_rec uuid) RETURNS jsonb LANGUAGE sql AS $$ SELECT private.narrative_record_wanted_labels(p_rec) $$;
DO $t$
DECLARE r uuid; w jsonb;
BEGIN
  r := pg_temp.mk(-6301,'V-1',201,ARRAY['V'],ARRAY['1']);
  w := pg_temp.w(r);
  IF w->>'record_label' IS DISTINCT FROM 'V-1' OR w->>'citation_label' IS DISTINCT FROM 'DAA B, s. 201' THEN
    RAISE EXCEPTION 'TEST_FAILED: bognøgle %', w;
  END IF;
  r := pg_temp.mk(-6302,'record-62000000-0000-4000-8000-000000000101',538,ARRAY['IV'],ARRAY['3']);
  w := pg_temp.w(r);
  IF w->>'record_label' IS DISTINCT FROM 'IV, nr. 3' OR w->>'citation_label' IS DISTINCT FROM 'DAA X, s. 49' THEN
    RAISE EXCEPTION 'TEST_FAILED: uuid IV nr 3 %', w;
  END IF;
  r := pg_temp.mk(-6302,'record-62000000-0000-4000-8000-000000000102',538,ARRAY['Stamme-x'],ARRAY['2']);
  IF pg_temp.w(r)->>'record_label' IS DISTINCT FROM 'A, nr. 2' THEN RAISE EXCEPTION 'TEST_FAILED: stamme A'; END IF;
  r := pg_temp.mk(-6302,'record-62000000-0000-4000-8000-000000000103',538,ARRAY['IV'],ARRAY[NULL]::text[]);
  IF pg_temp.w(r)->>'record_label' IS DISTINCT FROM 'IV' THEN RAISE EXCEPTION 'TEST_FAILED: uden nr'; END IF;
  r := pg_temp.mk(-6302,'record-62000000-0000-4000-8000-000000000104',541,ARRAY[]::text[],ARRAY[]::text[]);
  w := pg_temp.w(r);
  IF w->>'record_label' IS DISTINCT FROM '' OR w->>'citation_label' IS DISTINCT FROM 'DAA X, s. 52' THEN
    RAISE EXCEPTION 'TEST_FAILED: 0 placements %', w;
  END IF;
  -- anker uden for kortet: intervallet udelades
  r := pg_temp.mk(-6302,'record-62000000-0000-4000-8000-000000000105',600,ARRAY[]::text[],ARRAY[]::text[]);
  IF pg_temp.w(r)->>'citation_label' IS DISTINCT FROM 'DAA X' THEN RAISE EXCEPTION 'TEST_FAILED: uden for kort %', pg_temp.w(r); END IF;
  r := pg_temp.mk(-6302,'record-62000000-0000-4000-8000-000000000106',538,ARRAY['IV','V'],ARRAY['1','2']);
  BEGIN
    PERFORM pg_temp.w(r);
    RAISE EXCEPTION 'TEST_FAILED: 2 placements accepteret';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'RECORD_LABEL_PLACEMENTS_AMBIGUOUS' THEN RAISE; END IF;
  END;
  -- narrative_record_labels uden binding bruger reglen; med binding vinder bindingen
  r := (SELECT id FROM private.source_record WHERE record_key='record-62000000-0000-4000-8000-000000000101');
  -- ingen binding + 2 placements: labels giver record_key, wanted kaster
  r := (SELECT id FROM private.source_record WHERE record_key='record-62000000-0000-4000-8000-000000000106');
  IF private.narrative_record_labels(r)->>'record_label' IS DISTINCT FROM 'record-62000000-0000-4000-8000-000000000106' THEN
    RAISE EXCEPTION 'TEST_FAILED: labels ved tvetydighed uden binding %', private.narrative_record_labels(r);
  END IF;
  BEGIN
    PERFORM private.narrative_record_wanted_labels(r);
    RAISE EXCEPTION 'TEST_FAILED: wanted kastede ikke';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'RECORD_LABEL_PLACEMENTS_AMBIGUOUS' THEN RAISE; END IF;
  END;
  -- binding + 2 placements: bindingens etiket, ingen fejl
  INSERT INTO public.person(id) VALUES (-6393);
  INSERT INTO public.narrative(id,subjekt_type,subjekt_id,source_id,tekst,privat) VALUES (-6393,'person',-6393,-6302,'t',false);
  INSERT INTO private.narrative_record_publication(narrative_id,source_record_id,record_label,citation_label,status)
    VALUES (-6393,r,'bundet','DAA X, s. 49','draft');
  IF private.narrative_record_labels(r)->>'record_label' IS DISTINCT FROM 'bundet' THEN
    RAISE EXCEPTION 'TEST_FAILED: binding + 2 placements';
  END IF;
  r := (SELECT id FROM private.source_record WHERE record_key='record-62000000-0000-4000-8000-000000000101');
  IF private.narrative_record_labels(r)->>'record_label' IS DISTINCT FROM 'IV, nr. 3' THEN
    RAISE EXCEPTION 'TEST_FAILED: narrative_record_labels uden binding %', private.narrative_record_labels(r);
  END IF;
END $t$;

-- Binding: 'gammel' vinder; '' accepteres; blanktegn afvises af CHECK.
DO $t$
DECLARE r uuid; v_p int:=-6390;
BEGIN
  INSERT INTO public.person(id) VALUES (-6390),(-6391),(-6392);
  INSERT INTO public.narrative(id,subjekt_type,subjekt_id,source_id,tekst,privat) VALUES
    (-6390,'person',-6390,-6302,'t',false),(-6391,'person',-6391,-6302,'t',false),(-6392,'person',-6392,-6302,'t',false);
  r := (SELECT id FROM private.source_record WHERE record_key='record-62000000-0000-4000-8000-000000000101');
  INSERT INTO private.narrative_record_publication(narrative_id,source_record_id,record_label,citation_label,status)
    VALUES (-6390,r,'gammel','DAA X, s. 49','draft');
  IF private.narrative_record_labels(r)->>'record_label' IS DISTINCT FROM 'gammel' THEN
    RAISE EXCEPTION 'TEST_FAILED: binding tilsidesætter ikke';
  END IF;
  r := (SELECT id FROM private.source_record WHERE record_key='record-62000000-0000-4000-8000-000000000104');
  INSERT INTO private.narrative_record_publication(narrative_id,source_record_id,record_label,citation_label,status)
    VALUES (-6391,r,'','DAA X, s. 52','draft');
  r := (SELECT id FROM private.source_record WHERE record_key='record-62000000-0000-4000-8000-000000000105');
  BEGIN
    INSERT INTO private.narrative_record_publication(narrative_id,source_record_id,record_label,citation_label,status)
      VALUES (-6392,r,'  ','DAA X','draft');
    RAISE EXCEPTION 'TEST_FAILED: blanktegn accepteret';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
END $t$;

-- Validatoren: '' tillades i record_label, blanktegn afvises (struktur: se kald nedenfor).
DO $t$
DECLARE v_def text;
BEGIN
  v_def := pg_get_functiondef('private.validate_reimport_case_elements(jsonb,jsonb)'::regprocedure);
  IF v_def LIKE '%coalesce(btrim(v_payload->>''record_label''),'''')=''''%' THEN
    RAISE EXCEPTION 'TEST_FAILED: validatoren afviser stadig tom record_label';
  END IF;
  IF v_def NOT LIKE '%v_payload->''record_label'')<>''string''%' THEN
    RAISE EXCEPTION 'TEST_FAILED: validatoren mangler ny record_label-regel';
  END IF;
END $t$;
ROLLBACK;
\echo OK: 6e-2 etiket
