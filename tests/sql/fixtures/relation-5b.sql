-- Trin 5b: delte fixtures. Indlæses med \ir fra testfilerne; alt oprettes i den kaldende
-- transaktion og rulles tilbage af testen. Kald dem som ejer, før SET LOCAL ROLE.
CREATE OR REPLACE FUNCTION pg_temp.f5b_actor(p_actor uuid) RETURNS void LANGUAGE sql AS $$
  INSERT INTO auth.users(id,email) VALUES (p_actor,p_actor::text||'@5b.invalid') ON CONFLICT DO NOTHING;
  INSERT INTO profiles(id,rolle,navn,email) VALUES (p_actor,'redaktion','5b fixture',p_actor::text||'@5b.invalid')
    ON CONFLICT DO NOTHING;
$$;

CREATE OR REPLACE FUNCTION pg_temp.f5b_source(p_source bigint) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_run uuid:=gen_random_uuid(); v_rend uuid:=gen_random_uuid();
BEGIN
  INSERT INTO public.source(id,slags,titel,udgave,aar) VALUES (p_source,'DAA-udgave','5b fixture','synthetic',1900);
  INSERT INTO private.extraction_run(id,source_id,run_key,schema_version,extractor_version,profile_version,input_sha256,manifest)
    VALUES (v_run,p_source,'5b-'||v_run::text,'fixture','fixture','fixture',repeat('1',64),'{}');
  INSERT INTO private.source_rendition(id,source_id,rendition_key,rendition_kind,content_sha256,metadata)
    VALUES (v_rend,p_source,'5b-r-'||v_run::text,'pdf_text_layer',repeat('2',64),'{}');
  RETURN jsonb_build_object('run',v_run,'rend',v_rend);
END $$;

-- Én post med helpost, ét klausulsæt og en hovedperson-persona (primary-mention på
-- helposten) med accepteret identitet til p_principal_person (via legacy-lignende
-- ejer-insert: fixturen skriver identitetsrækken direkte som ejer).
CREATE OR REPLACE FUNCTION pg_temp.f5b_post(p_source bigint,p_src jsonb,p_key text,p_text text,
  p_clauses text[],p_principal_person bigint,p_actor uuid) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_run uuid:=(p_src->>'run')::uuid; v_rec uuid; v_occ uuid; v_help uuid; v_persona uuid; v_mention uuid;
  v_clause uuid; v_ids uuid[]:='{}'; v_pos int:=0; v_from int; i int;
BEGIN
  INSERT INTO private.source_record(source_id,record_key,record_kind,created_run_id)
    VALUES (p_source,p_key,'person_post',v_run) RETURNING id INTO v_rec;
  INSERT INTO private.source_record_occurrence(rendition_id,occurrence_key,page_from,page_to,char_from,char_to,
    verbatim_text,physical_fingerprint,structural_fingerprint,extraction_run_id)
    VALUES ((p_src->>'rend')::uuid,'occ-'||p_key,10,10,1000,1000+char_length(p_text),p_text,repeat('3',64),repeat('4',64),v_run)
    RETURNING id INTO v_occ;
  INSERT INTO private.source_record_anchor_event(occurrence_id,source_record_id,decision_status,evidence,version,decided_by,decided_by_name)
    VALUES (v_occ,v_rec,'accepted',jsonb_build_object('fixture','5b'),1,p_actor,'fixture');
  INSERT INTO private.source_observation(occurrence_id,observation_kind,page_from,page_to,char_from,char_to,
    verbatim_text,quality_status,extraction_method,extraction_run_id)
    VALUES (v_occ,'person_post',10,10,1000,1000+char_length(p_text),p_text,'clear','fixture',v_run) RETURNING id INTO v_help;
  FOR i IN 1..cardinality(p_clauses) LOOP
    v_from:=strpos(substr(p_text,v_pos+1),p_clauses[i])+v_pos-1;
    IF v_from<v_pos THEN RAISE EXCEPTION 'F5B_CLAUSE_NOT_IN_TEXT %',i; END IF;
    INSERT INTO private.source_observation(occurrence_id,observation_kind,page_from,page_to,char_from,char_to,
      verbatim_text,quality_status,extraction_method,extraction_run_id,parent_observation_id,post_char_from,
      post_char_to,clause_ordinal,clause_classification,clause_flags,clause_set_seq)
      VALUES (v_occ,'clause',10,10,1000+v_from,1000+v_from+char_length(p_clauses[i]),p_clauses[i],'clear',
        'clause_segment_v1',v_run,v_help,v_from,v_from+char_length(p_clauses[i]),i,'record_text','[]'::jsonb,1)
      RETURNING id INTO v_clause;
    v_ids:=v_ids||v_clause; v_pos:=v_from+char_length(p_clauses[i]);
  END LOOP;
  INSERT INTO private.source_mention(observation_id,mention_kind,char_from,char_to,verbatim_text,created_run_id)
    VALUES (v_help,'person_post',0,char_length(p_text),p_text,v_run) RETURNING id INTO v_mention;
  INSERT INTO private.source_persona(source_id,persona_key,created_run_id) VALUES (p_source,p_key,v_run) RETURNING id INTO v_persona;
  INSERT INTO private.source_persona_mention(persona_id,mention_id,mention_role,ordinal) VALUES (v_persona,v_mention,'primary',1);
  IF p_principal_person IS NOT NULL THEN
    INSERT INTO private.source_persona_identity(source_persona_id,canonical_person_id,decision_status,version,evidence,
      decided_by,decided_by_name,decided_at)
      VALUES (v_persona,p_principal_person,'accepted',1,'{"fixture":"5b"}',p_actor,'fixture',clock_timestamp());
  END IF;
  RETURN jsonb_build_object('record',v_rec,'occ',v_occ,'helpost',v_help,'clauses',to_jsonb(v_ids),'principal',v_persona,'key',p_key);
END $$;

-- En gældende relationspåstand (version 1, proposed) der citerer én klausul.
CREATE OR REPLACE FUNCTION pg_temp.f5b_claim(p_source bigint,p_src jsonb,p_predicate text,p_clause uuid,p_raw text)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_id uuid:=gen_random_uuid(); v_key uuid:=gen_random_uuid();
BEGIN
  INSERT INTO private.interpretation(id,interpretation_key,version,source_id,source_persona_id,interpretation_kind,predicate,
    value,schema_version,derivation_kind,confidence,status,method,extraction_run_id)
    VALUES (v_id,v_key,1,p_source,NULL,'relation',p_predicate,jsonb_build_object('raw',p_raw,'normalized',p_raw),
      'fixture','model_inference',0.9,'proposed','fixture',(p_src->>'run')::uuid);
  INSERT INTO private.interpretation_observation(interpretation_id,observation_id,evidence_role,ordinal)
    VALUES (v_id,p_clause,'supporting',1);
  RETURN jsonb_build_object('id',v_id,'key',v_key);
END $$;

-- En familie med to partnere (ordinal ens for begge, som red_opret_union) eller én.
CREATE OR REPLACE FUNCTION pg_temp.f5b_family(p_a bigint,p_b bigint,p_ordinal int) RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE v_fam bigint;
BEGIN
  INSERT INTO family(id,type) VALUES ((SELECT coalesce(max(id),0)+1 FROM family),'vielse') RETURNING id INTO v_fam;
  INSERT INTO family_member(family_id,person_id,rolle,ordinal) VALUES (v_fam,p_a,'partner',p_ordinal);
  IF p_b IS NOT NULL THEN
    INSERT INTO family_member(family_id,person_id,rolle,ordinal) VALUES (v_fam,p_b,'partner',p_ordinal);
  END IF;
  RETURN v_fam;
END $$;
