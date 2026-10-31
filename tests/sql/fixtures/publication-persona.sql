-- Trin 6b, Task 2: fixtures til publication_persona. Kald som ejer, før SET ROLE. Alt er syntetisk.
--
-- pp_source(p_base, p_actor): kilde p_base (negativ), rendition, kørsel, redaktør og to publikationsprofiler
--   (fixture-pub-a, fixture-pub-b; fixture-pub-n er uden persona_key_prefix; samme config som daa-1939-publication-v1, ét writer-lås-par hver).
-- pp_post(p_src, p_key, p_person, p_opts): en helpost 'person' (tegn 100-500) med én mention, en narrativ med publiceret
--   binding og en person med præcis én person_external_id. p_opts: subs (antal underforekomster, 0/2),
--   binding ('published' | 'draft' | 'withdrawn+published'), ext_ids (0 eller 1 person_external_id for kilden; PK (person,kilde) tillader ikke to).
-- pp_payload(p_fx): writerens payload for et pp_post-resultat.

CREATE OR REPLACE FUNCTION pg_temp.pp_source(p_base bigint, p_actor uuid) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_run uuid:=gen_random_uuid(); v_rend uuid; v_cfg jsonb; v_sha text; v_cfg_n jsonb; v_sha_n text;
BEGIN
  INSERT INTO public.source(id,titel,udgave,aar,slags) VALUES (p_base,'Fixture pub '||p_base,'synthetic','1900','DAA-udgave');
  INSERT INTO auth.users(id,email) VALUES (p_actor,p_actor::text||'@6b.invalid') ON CONFLICT DO NOTHING;
  INSERT INTO public.profiles(id,rolle,navn,email) VALUES (p_actor,'redaktion','6b fixture',p_actor::text||'@6b.invalid') ON CONFLICT DO NOTHING;
  INSERT INTO private.extraction_run(id,source_id,run_key,schema_version,extractor_version,profile_version,input_sha256,manifest)
    VALUES (v_run,p_base,'pp-fixture-'||v_run::text,'fixture','fixture','fixture',repeat('1',64),'{}');
  INSERT INTO private.source_rendition(source_id,rendition_key,rendition_kind,content_sha256,metadata)
    VALUES (p_base,'pp-r1','pdf_text_layer',repeat('2',64),'{}') RETURNING id INTO v_rend;
  v_cfg:=jsonb_build_object('citation_label_template','Synthetic side {page_from}','extractor_version','publication-v1',
    'observation_extraction_method','clause_segment_v1','rendition_key','fixture-r1','rendition_kind','pdf_text_layer',
    'rendition_metadata',jsonb_build_object('edition','fixture'),'run_key_prefix','reimport-publication:',
    'schema_version','clause-evidence-manifest-v1','text_form','raw','helpost_observation_kind','person','persona_key_prefix','1939:');
  v_cfg_n:=v_cfg-'persona_key_prefix'; v_sha_n:=private.reimport_canonical_json_sha256(v_cfg_n);
  v_sha:=private.reimport_canonical_json_sha256(v_cfg);
  INSERT INTO private.reimport_writer_profile(source_id,profile_id,profile_version,profile_sha256,writer_config)
    VALUES (p_base,'fixture-pub-a','publication-v1',v_sha,v_cfg),(p_base,'fixture-pub-b','publication-v1',v_sha,v_cfg),
           (p_base,'fixture-pub-n','publication-v1',v_sha_n,v_cfg_n);  -- n: uden persona_key_prefix
  RETURN jsonb_build_object('source',p_base,'run',v_run,'rend',v_rend,'actor',p_actor,'profile_sha256',v_sha,'profile_sha256_n',v_sha_n);
END $$;

CREATE OR REPLACE FUNCTION pg_temp.pp_occ(p_record uuid, p_src jsonb, p_key text, p_from int, p_to int, p_kind text, p_head text DEFAULT '')
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_occ uuid; v_obs uuid; v_text text:=rpad(p_head,p_to-p_from,'x');
BEGIN
  INSERT INTO private.source_record_occurrence(rendition_id,occurrence_key,page_from,page_to,char_from,char_to,verbatim_text,
    physical_fingerprint,structural_fingerprint,extraction_run_id)
  VALUES ((p_src->>'rend')::uuid,p_key,1,1,p_from,p_to,v_text,repeat('3',64),repeat('4',64),(p_src->>'run')::uuid)
  RETURNING id INTO v_occ;
  INSERT INTO private.source_observation(occurrence_id,observation_kind,page_from,page_to,char_from,char_to,verbatim_text,
    quality_status,extraction_method,extraction_run_id)
  VALUES (v_occ,p_kind,1,1,p_from,p_to,v_text,'clear','fixture',(p_src->>'run')::uuid) RETURNING id INTO v_obs;
  INSERT INTO private.source_record_anchor_event(occurrence_id,source_record_id,decision_status,evidence,version,decided_by,decided_by_name)
  VALUES (v_occ,p_record,'accepted','{"fixture":true}'::jsonb,1,gen_random_uuid(),'fixture');
  RETURN v_obs;
END $$;

CREATE OR REPLACE FUNCTION pg_temp.pp_post(p_src jsonb, p_key text, p_person bigint, p_opts jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
  v_source bigint:=(p_src->>'source')::bigint; v_rec uuid; v_obs uuid; v_mention uuid; v_text text:='Fixture Navn '||p_key;
  v_narr bigint; v_binding uuid; v_mode text:=coalesce(p_opts->>'binding','published'); v_subs int:=coalesce((p_opts->>'subs')::int,0);
  v_ext int:=coalesce((p_opts->>'ext_ids')::int,1);
BEGIN
  INSERT INTO public.person(id,levende,privat,status) VALUES (p_person,false,false,'pp');
  IF v_ext>=1 THEN
    INSERT INTO public.person_external_id(person_id,source_id,linje,nr,record_key) VALUES (p_person,v_source,'I',abs(p_person)::int,p_key);
  END IF;
  INSERT INTO private.source_record(source_id,record_key,record_kind,created_run_id) VALUES (v_source,p_key,'person',(p_src->>'run')::uuid)
    RETURNING id INTO v_rec;
  v_obs:=pg_temp.pp_occ(v_rec,p_src,p_key||'-h',100,500,'person',v_text);
  IF v_subs>=2 THEN
    PERFORM pg_temp.pp_occ(v_rec,p_src,p_key||'-s1',120,200,'fact');
    PERFORM pg_temp.pp_occ(v_rec,p_src,p_key||'-s2',300,450,'marriage');
  END IF;
  INSERT INTO private.source_mention(observation_id,mention_kind,char_from,char_to,verbatim_text,created_run_id)
    VALUES (v_obs,'person',0,char_length(v_text),v_text,(p_src->>'run')::uuid) RETURNING id INTO v_mention;
  INSERT INTO public.narrative(subjekt_type,subjekt_id,source_id,side,tekst) VALUES ('person',p_person,v_source,'1','Syntetisk tekst '||p_key)
    RETURNING id INTO v_narr;
  IF v_mode='withdrawn+published' THEN
    INSERT INTO private.narrative_record_publication(narrative_id,source_record_id,record_label,citation_label,status)
      VALUES (v_narr,v_rec,'Fixture '||p_key,'Fixture side 1','withdrawn');
    INSERT INTO public.narrative(subjekt_type,subjekt_id,source_id,side,tekst) VALUES ('person',p_person,v_source,'1','Syntetisk tekst 2 '||p_key)
      RETURNING id INTO v_narr;
  END IF;
  INSERT INTO private.narrative_record_publication(narrative_id,source_record_id,record_label,citation_label,status)
    VALUES (v_narr,v_rec,'Fixture '||p_key,'Fixture side 1',CASE WHEN v_mode='draft' THEN 'draft' ELSE 'published' END)
    RETURNING id INTO v_binding;
  RETURN jsonb_build_object('record_key',p_key,'record',v_rec,'person',p_person,'binding',v_binding,'narrative',v_narr,
    'mention',v_mention,'mention_sha',encode(extensions.digest(v_text,'sha256'),'hex'),'observation',v_obs);
END $$;

CREATE OR REPLACE FUNCTION pg_temp.pp_payload(p_src jsonb, p_fx jsonb) RETURNS jsonb LANGUAGE sql AS $$
  SELECT jsonb_build_object('binding_id',p_fx->>'binding','binding_status','published','mention_id',p_fx->>'mention',
    'mention_text_sha256',p_fx->>'mention_sha','person_id',(p_fx->>'person')::bigint,'persona_key','1939:'||(p_fx->>'record_key'),
    'source_id',(p_src->>'source')::bigint,'source_record_key',p_fx->>'record_key')
$$;

-- Autoriser og åbn en batch for de givne payloads {element_id: payload}. Som service_role/authenticated som ceremonien.
CREATE OR REPLACE FUNCTION pg_temp.pp_begin(p_src jsonb, p_profile text, p_tag text, p_elements jsonb) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE
  v_actor uuid:=(p_src->>'actor')::uuid; v_msha text:=encode(extensions.digest('manifest-pp:'||p_tag,'sha256'),'hex');
  v_psha text:=encode(extensions.digest('preview-pp:'||p_tag,'sha256'),'hex'); v_auth uuid; v_batch uuid;
BEGIN
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  PERFORM set_config('role','service_role',true);
  v_auth:=public.red_authorize_reimport(v_msha,v_psha,
    jsonb_build_object('database_name',current_database(),'system_identifier',(pg_control_system()).system_identifier::text)::text,
    (p_src->>'source')::bigint,p_profile,CASE WHEN p_profile='fixture-pub-n' THEN p_src->>'profile_sha256_n' ELSE p_src->>'profile_sha256' END,
    jsonb_build_object('person_creates',0,'source_evidence',0,'publication_personas',(SELECT count(*) FROM jsonb_object_keys(p_elements))),
    p_elements,gen_random_uuid(),clock_timestamp()+interval '10 minutes');
  PERFORM set_config('role','authenticated',true);
  v_batch:=public.red_begin_reimport(v_auth,v_msha,v_psha);
  RESET role;
  RETURN v_batch;
END $$;

CREATE OR REPLACE FUNCTION pg_temp.pp_apply(p_src jsonb, p_batch uuid, p_element text, p_payload jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_result jsonb;
BEGIN
  PERFORM set_config('request.jwt.claim.sub',p_src->>'actor',true);
  PERFORM set_config('role','authenticated',true);
  v_result:=public.red_apply_reimport_publication_persona(p_batch,p_element,p_payload);
  RESET role;
  RETURN v_result;
EXCEPTION WHEN OTHERS THEN RESET role; RAISE;
END $$;
