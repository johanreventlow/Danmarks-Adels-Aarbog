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
  -- 2b-ii: family.id er identity (spec §4); eksplicitte id'er ville lade sekvensen halte. Ældre baser
  -- (opgraderingstest før migrationen) har ingen identity og får max+1 som før.
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='family'
              AND column_name='id' AND is_identity='YES') THEN
    INSERT INTO family(type) VALUES ('vielse') RETURNING id INTO v_fam;
  ELSE
    INSERT INTO family(id,type) VALUES ((SELECT coalesce(max(id),0)+1 FROM family),'vielse') RETURNING id INTO v_fam;
  END IF;
  INSERT INTO family_member(family_id,person_id,rolle,ordinal) VALUES (v_fam,p_a,'partner',p_ordinal);
  IF p_b IS NOT NULL THEN
    INSERT INTO family_member(family_id,person_id,rolle,ordinal) VALUES (v_fam,p_b,'partner',p_ordinal);
  END IF;
  RETURN v_fam;
END $$;

CREATE OR REPLACE FUNCTION pg_temp.f5b_profile(p_source bigint) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_cfg jsonb:='{"citation_label_template":"DAA 5b s. {page_from}","extractor_version":"5b","observation_extraction_method":"5b",
  "rendition_key":"5b","rendition_kind":"pdf_text_layer","rendition_metadata":{},"run_key_prefix":"5b","schema_version":"5b"}';
BEGIN
  INSERT INTO private.reimport_writer_profile(source_id,profile_id,profile_version,profile_sha256,writer_config)
    VALUES (p_source,'relation-5b','relation-persona-v1',private.reimport_canonical_json_sha256(v_cfg),v_cfg);
  RETURN jsonb_build_object('profile_id','relation-5b','profile_sha256',private.reimport_canonical_json_sha256(v_cfg));
END $$;

-- Autoriserer og åbner en batch med de givne elementer. Kaldes som EJER (før SET LOCAL ROLE
-- authenticated) med aktørens claim sat — samme mønster som test-reimport-name-completion.sql:104-110.
-- red_authorize_reimport er kun tildelt service_role (schema.sql:4558); som authenticated fejler kaldet.
-- Databaseidentiteten er JSON-strengen, som schema.sql:3096 sammenligner med — ikke current_database().
CREATE OR REPLACE FUNCTION pg_temp.f5b_batch(p_source bigint,p_actor uuid,p_prof jsonb,p_elements jsonb,
  p_counts jsonb DEFAULT NULL) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_manifest text:=private.reimport_canonical_json_sha256(p_elements); v_auth uuid; v_batch uuid;
BEGIN
  IF current_user NOT IN (SELECT rolname FROM pg_roles WHERE rolsuper) THEN RAISE EXCEPTION 'F5B_BATCH_MUST_RUN_AS_OWNER'; END IF;
  PERFORM set_config('request.jwt.claim.sub',p_actor::text,true);
  v_auth:=public.red_authorize_reimport(v_manifest,v_manifest,
    jsonb_build_object('database_name',current_database(),'system_identifier',(pg_control_system()).system_identifier::text)::text,
    p_source,p_prof->>'profile_id',
    p_prof->>'profile_sha256',coalesce(p_counts,jsonb_build_object('person_creates',0,'source_evidence',0,
    'relation_personas',(SELECT count(*) FROM jsonb_object_keys(p_elements)))),p_elements,gen_random_uuid(),clock_timestamp()+interval '1 hour');
  v_batch:=public.red_begin_reimport(v_auth,v_manifest,v_manifest);
  RETURN jsonb_build_object('auth',v_auth,'batch',v_batch);
END $$;

-- En ægtefælle-persona som writeren ville skrive den (mention på klausulen, rolle spouse)
-- plus principal- og spouse-part. Bruges af Task 4-7's tests uden writer-rammen.
CREATE OR REPLACE FUNCTION pg_temp.f5b_spouse(p_source bigint,p_src jsonb,p_post jsonb,p_claim jsonb,p_clause uuid,
  p_name text,p_ordinal int) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_text text; v_from int; v_persona uuid; v_mention uuid; v_ref uuid:=gen_random_uuid();
BEGIN
  SELECT verbatim_text INTO v_text FROM private.source_observation WHERE id=p_clause;
  v_from:=strpos(v_text,p_name)-1;
  INSERT INTO private.source_persona(source_id,persona_key,created_run_id)
    VALUES (p_source,(p_post->>'key')||'#rel-marriage-'||v_from||'-'||p_ordinal,(p_src->>'run')::uuid) RETURNING id INTO v_persona;
  INSERT INTO private.source_mention(observation_id,mention_kind,char_from,char_to,verbatim_text,created_run_id)
    VALUES (p_clause,'person',v_from,v_from+char_length(p_name),p_name,(p_src->>'run')::uuid) RETURNING id INTO v_mention;
  INSERT INTO private.source_persona_mention(persona_id,mention_id,mention_role,ordinal) VALUES (v_persona,v_mention,'spouse',1);
  INSERT INTO private.interpretation_party(interpretation_key,party_role,version,source_persona_id,post_offset,origin,origin_ref)
    VALUES ((p_claim->>'key')::uuid,'principal',1,(p_post->>'principal')::uuid,v_from,'relation_persona',v_ref);
  INSERT INTO private.interpretation_party(interpretation_key,party_role,version,source_persona_id,marriage_ordinal,post_offset,origin,origin_ref)
    VALUES ((p_claim->>'key')::uuid,'spouse',1,v_persona,p_ordinal,v_from,'relation_persona',v_ref);
  RETURN v_persona;
END $$;

-- Payload til relation_persona for en ægteskabspåstand, hvis klausul er præcis raw.
CREATE OR REPLACE FUNCTION pg_temp.f5b_payload(p jsonb,c jsonb,p_clause uuid,p_raw text,p_name text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_co private.source_observation%ROWTYPE; v_from int;
BEGIN
  SELECT * INTO v_co FROM private.source_observation WHERE id=p_clause;
  v_from:=strpos(v_co.verbatim_text,p_raw)-1;
  RETURN jsonb_build_object('birth_raw',NULL,'clause_observation_id',p_clause,'clause_set_seq',1,
    'clause_set_sha256',private.clause_set_sha256(v_co.parent_observation_id,1),'death_raw',NULL,
    'interpretation_key',c->>'key','interpretation_version',1,
    'marriage_ordinal',(SELECT o.marriage_ordinal FROM private.relation_marriage_ordinals(v_co.occurrence_id) o
                         WHERE o.interpretation_key=(c->>'key')::uuid),
    'name_from',v_from+strpos(p_raw,p_name)-1,'name_to',v_from+strpos(p_raw,p_name)-1+char_length(p_name),
    'post_offset',v_co.post_char_from+v_from,'predicate','relation.marriage','profile','relation-persona-2018-20-v1',
    'span_from',v_from,'span_to',v_from+char_length(p_raw));
END $$;

-- Skriver de givne payloads gennem den rigtige writer og finaliserer. Kaldes som ejer: autorisation
-- og begin som ejer (f5b_batch), apply og finalize som authenticated redaktion.
CREATE OR REPLACE FUNCTION pg_temp.f5b_write(p_source bigint,p_actor uuid,p_elements jsonb) RETURNS void LANGUAGE plpgsql AS $$
DECLARE prof jsonb; b jsonb; e record;
BEGIN
  SELECT jsonb_build_object('profile_id',profile_id,'profile_sha256',profile_sha256) INTO prof
    FROM private.reimport_writer_profile WHERE source_id=p_source AND profile_id='relation-5b';
  IF prof IS NULL THEN prof:=pg_temp.f5b_profile(p_source); END IF;
  b:=pg_temp.f5b_batch(p_source,p_actor,prof,p_elements);
  SET LOCAL ROLE authenticated;
  FOR e IN SELECT * FROM jsonb_each(p_elements) LOOP
    PERFORM public.red_apply_reimport_relation_persona((b->>'batch')::uuid,e.key,e.value);
  END LOOP;
  PERFORM public.red_finalize_reimport((b->>'batch')::uuid);
  RESET ROLE;
END $$;

-- Leveår som afklarede fødsels-/dødskonklusioner (spec §23.3: projektionens datagrundlag).
CREATE OR REPLACE FUNCTION pg_temp.f5b_life(p_person bigint,p_born int,p_died int) RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_f bigint; v_a bigint;
BEGIN
  IF p_born IS NOT NULL THEN
    INSERT INTO fact(subjekt_type,subjekt_id,faktatype) VALUES ('person',p_person,'fødsel') RETURNING id INTO v_f;
    INSERT INTO assertion(target_type,target_id,date_min,date_max) VALUES ('fact',v_f,make_date(p_born,1,1),make_date(p_born,12,31)) RETURNING id INTO v_a;
    INSERT INTO conclusion(target_type,target_id,valgt_assertion_id,status) VALUES ('fact',v_f,v_a,'afklaret');
  END IF;
  IF p_died IS NOT NULL THEN
    INSERT INTO fact(subjekt_type,subjekt_id,faktatype) VALUES ('person',p_person,'død') RETURNING id INTO v_f;
    INSERT INTO assertion(target_type,target_id,date_min,date_max) VALUES ('fact',v_f,make_date(p_died,1,1),make_date(p_died,12,31)) RETURNING id INTO v_a;
    INSERT INTO conclusion(target_type,target_id,valgt_assertion_id,status) VALUES ('fact',v_f,v_a,'afklaret');
  END IF;
END $$;
