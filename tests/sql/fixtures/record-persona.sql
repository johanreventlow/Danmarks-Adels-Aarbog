-- Fixtures til record_persona (persona for en helpost uden aktiv tekstbinding). Kald som ejer, før SET ROLE. Alt er
-- syntetisk. Indlæses EFTER tests/sql/fixtures/publication-persona.sql: kilden (pp_source) og forekomsterne (pp_occ)
-- genbruges derfra; profilerne fixture-pub-a/-b bærer persona_key_prefix og helpost-slags, fixture-pub-n er uden prefix.
--
-- rp_post(p_src, p_key, p_person, p_opts): en helpost 'person' (tegn 100-500) med én mention og en afdød person med
--   præcis én person_external_id for kilden. Ingen narrativ og ingen binding, medmindre p_opts siger andet:
--   binding ('none' | 'draft' | 'published' | 'withdrawn'), subs (0/2 underforekomster), ext_ids (0/1 for kilden),
--   ext_other (true: en person_external_id i en anden kilde, p_opts->>'ext_other' er kildens id), levende (true/false).
-- rp_payload(p_src, p_fx): writerens payload for et rp_post-resultat (kortarkets sha og linje er syntetiske).
-- rp_begin(p_src, p_profile, p_tag, p_elements): autoriser og åbn en batch med record_personas = antal elementer.
-- rp_apply(p_src, p_batch, p_element, p_payload): red_apply_reimport_record_persona som redaktøren.

CREATE OR REPLACE FUNCTION pg_temp.rp_post(p_src jsonb, p_key text, p_person bigint, p_opts jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
  v_source bigint:=(p_src->>'source')::bigint; v_rec uuid; v_obs uuid; v_mention uuid; v_text text:='Fixture Navn '||p_key;
  v_narr bigint; v_binding uuid; v_mode text:=coalesce(p_opts->>'binding','none'); v_subs int:=coalesce((p_opts->>'subs')::int,0);
  v_ext int:=coalesce((p_opts->>'ext_ids')::int,1);
BEGIN
  INSERT INTO public.person(id,levende,privat,status) VALUES (p_person,coalesce((p_opts->>'levende')::boolean,false),false,'rp');
  IF v_ext>=1 THEN
    INSERT INTO public.person_external_id(person_id,source_id,linje,nr,record_key) VALUES (p_person,v_source,'I',abs(p_person)::int,p_key);
  END IF;
  IF p_opts ? 'ext_other' THEN
    INSERT INTO public.person_external_id(person_id,source_id,linje,nr,record_key)
      VALUES (p_person,(p_opts->>'ext_other')::bigint,'I',abs(p_person)::int,p_key);
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
  IF v_mode<>'none' THEN
    INSERT INTO public.narrative(subjekt_type,subjekt_id,source_id,side,tekst) VALUES ('person',p_person,v_source,'1','Syntetisk tekst '||p_key)
      RETURNING id INTO v_narr;
    INSERT INTO private.narrative_record_publication(narrative_id,source_record_id,record_label,citation_label,status)
      VALUES (v_narr,v_rec,'Fixture '||p_key,'Fixture side 1',v_mode) RETURNING id INTO v_binding;
  END IF;
  RETURN jsonb_build_object('record_key',p_key,'record',v_rec,'person',p_person,'binding',v_binding,'narrative',v_narr,
    'mention',v_mention,'mention_sha',encode(extensions.digest(v_text,'sha256'),'hex'),'observation',v_obs,'occ',
    (SELECT occurrence_id FROM private.source_observation WHERE id=v_obs));
END $$;

CREATE OR REPLACE FUNCTION pg_temp.rp_payload(p_src jsonb, p_fx jsonb) RETURNS jsonb LANGUAGE sql AS $$
  SELECT jsonb_build_object('mention_id',p_fx->>'mention','mention_text_sha256',p_fx->>'mention_sha',
    'person_id',(p_fx->>'person')::bigint,'persona_key','1939:'||(p_fx->>'record_key'),
    'sheet_line',1,'sheet_sha256',encode(extensions.digest('rp-sheet','sha256'),'hex'),
    'source_id',(p_src->>'source')::bigint,'source_record_key',p_fx->>'record_key')
$$;

CREATE OR REPLACE FUNCTION pg_temp.rp_begin(p_src jsonb, p_profile text, p_tag text, p_elements jsonb) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE
  v_actor uuid:=(p_src->>'actor')::uuid; v_msha text:=encode(extensions.digest('manifest-rp:'||p_tag,'sha256'),'hex');
  v_psha text:=encode(extensions.digest('preview-rp:'||p_tag,'sha256'),'hex'); v_auth uuid; v_batch uuid;
BEGIN
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  PERFORM set_config('role','service_role',true);
  v_auth:=public.red_authorize_reimport(v_msha,v_psha,
    jsonb_build_object('database_name',current_database(),'system_identifier',(pg_control_system()).system_identifier::text)::text,
    (p_src->>'source')::bigint,p_profile,CASE WHEN p_profile='fixture-pub-n' THEN p_src->>'profile_sha256_n' ELSE p_src->>'profile_sha256' END,
    jsonb_build_object('person_creates',0,'source_evidence',0,'record_personas',(SELECT count(*) FROM jsonb_object_keys(p_elements))),
    p_elements,gen_random_uuid(),clock_timestamp()+interval '10 minutes');
  PERFORM set_config('role','authenticated',true);
  v_batch:=public.red_begin_reimport(v_auth,v_msha,v_psha);
  RESET role;
  RETURN v_batch;
EXCEPTION WHEN OTHERS THEN RESET role; RAISE;
END $$;

CREATE OR REPLACE FUNCTION pg_temp.rp_apply(p_src jsonb, p_batch uuid, p_element text, p_payload jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_result jsonb;
BEGIN
  PERFORM set_config('request.jwt.claim.sub',p_src->>'actor',true);
  PERFORM set_config('role','authenticated',true);
  v_result:=public.red_apply_reimport_record_persona(p_batch,p_element,p_payload);
  RESET role;
  RETURN v_result;
EXCEPTION WHEN OTHERS THEN RESET role; RAISE;
END $$;
