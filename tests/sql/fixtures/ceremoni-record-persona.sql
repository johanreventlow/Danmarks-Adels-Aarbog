-- Dataceremonien for record_persona (tests/sql/test-record-persona-ceremoni.sh): syntetisk mini-kilde. Data COMMIT'es,
-- fordi record_persona_ceremoni.sql kører sin egen transaktion. Opdigtede personer med negative id'er; aktør
-- a6400000-…-6400 (redaktion). Kræver kontrakt v2 (reimport-writer-v2-bootstrap.sql) som writeren.
--   Kilde -6400 (profil fixture-pub-a fra publication-persona.sql: persona_key_prefix og helpost-slags `person`):
--     overskrifter i header-kørslen 'rp-header-v1' (ikke-ankrede forekomster i renditionen): linje (tegn 0),
--     slægtled (tegn 20) og kuld (tegn 600).
--     rpc-a (tegn 100) og rpc-b (tegn 700): helposter uden persona, uden binding og uden placement, hver med én mention
--       og rå OCR-tekst (orddeling ved linjeskift og sidemarkør). Personerne -640001/-640002 er afdøde, offentlige, har
--       én person_external_id i kilden (gammel nøgle legacy-a/-b), en tilbagetrukket legacy-narrativ, v1
--       retained_legacy i ledgeren og en samme_som-kant til aliaset -640011/-640012.
--     rpc-c (tegn 1100): en placeret og promoveret hovedperson (-640003) med persona, identitet og medlemskab; giver
--       forhåndsvisningen et `already_current`-item, som ceremonien skal tåle.
--   Kilde -6401 (en anden udgave): person -640101 med en legacy-række, så KOORD_2018_20 har indhold.
\set ON_ERROR_STOP on
BEGIN;
\ir publication-persona.sql

-- En helpost med én mention (hele forekomstteksten). Returnerer record, observation, forekomst og mention.
CREATE OR REPLACE FUNCTION pg_temp.rpc_post(f jsonb,p_key text,p_char int,p_text text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_run uuid:=(f->>'run')::uuid; v_rec uuid; v_occ uuid; v_obs uuid; v_mention uuid;
  v_to int:=p_char+char_length(p_text);
BEGIN
  INSERT INTO private.source_record(source_id,record_key,record_kind,created_run_id)
    VALUES ((f->>'source')::bigint,p_key,'person',v_run) RETURNING id INTO v_rec;
  INSERT INTO private.source_record_occurrence(rendition_id,occurrence_key,page_from,page_to,char_from,char_to,
    verbatim_text,physical_fingerprint,structural_fingerprint,extraction_run_id)
    VALUES ((f->>'rend')::uuid,'occ-'||p_key,9,10,p_char,v_to,p_text,repeat('3',64),repeat('4',64),v_run)
    RETURNING id INTO v_occ;
  INSERT INTO private.source_record_anchor_event(occurrence_id,source_record_id,decision_status,evidence,version,decided_by,decided_by_name)
    VALUES (v_occ,v_rec,'accepted','{"fixture":"rpc"}',1,(f->>'actor')::uuid,'fixture');
  INSERT INTO private.source_observation(occurrence_id,observation_kind,page_from,page_to,char_from,char_to,
    verbatim_text,quality_status,extraction_method,extraction_run_id)
    VALUES (v_occ,'person',9,10,p_char,v_to,p_text,'clear','fixture',v_run) RETURNING id INTO v_obs;
  INSERT INTO private.source_mention(observation_id,mention_kind,char_from,char_to,verbatim_text,created_run_id)
    VALUES (v_obs,'person',0,char_length(p_text),p_text,v_run) RETURNING id INTO v_mention;
  RETURN jsonb_build_object('record',v_rec,'occ',v_occ,'observation',v_obs,'mention',v_mention);
END $$;

-- En person med gammel legacy-nøgle, tilbagetrukket legacy-narrativ (gennem RPC'en) og alias (samme_som).
CREATE OR REPLACE FUNCTION pg_temp.rpc_person(f jsonb,p_person bigint,p_alias bigint,p_legacy_key text) RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE v_source bigint:=(f->>'source')::bigint; v_narr bigint; v_ref uuid:=gen_random_uuid(); v_state jsonb; v_sha text;
BEGIN
  INSERT INTO public.person(id,levende,privat,status) VALUES (p_person,false,false,'rpc'),(p_alias,false,false,'rpc');
  INSERT INTO public.person_external_id(person_id,source_id,linje,nr,record_key) VALUES (p_person,v_source,'H',abs(p_person)::int,p_legacy_key);
  INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle) VALUES ('person',p_person,'person',p_alias,'samme_som');
  IF NOT EXISTS (SELECT 1 FROM public.change_set) THEN
    INSERT INTO public.change_set(actor_navn,actor_rolle,operation,summary,subjekt_synlighed)
    VALUES ('fixture','system','fixture','fixture','offentlig');
  END IF;
  INSERT INTO public.narrative(subjekt_type,subjekt_id,source_id,side,tekst,privat)
    VALUES ('person',p_person,v_source,'9','Opdigtet forkert legacy-tekst for '||p_person,false) RETURNING id INTO v_narr;
  v_state:=private.narrative_legacy_candidate_publication_state(v_narr,v_source,v_ref);
  v_sha:=encode(extensions.digest(v_state::text,'sha256'),'hex');
  INSERT INTO private.narrative_legacy_publication(legacy_publication_ref,narrative_id,source_id,baseline_state,baseline_sha256,status)
    VALUES (v_ref,v_narr,v_source,v_state,v_sha,'grandfathered_publication');
  INSERT INTO private.narrative_publication_event(change_set_id,stream_ref,stream_version,event_type,narrative_id,source_id,
    legacy_publication_ref,decision_basis,before_state,after_state,before_state_sha256,after_state_sha256,decided_by_name)
  VALUES ((SELECT max(id) FROM public.change_set),v_ref,1,'baseline',v_narr,v_source,v_ref,'fixture',v_state,v_state,v_sha,v_sha,'fixture');
  UPDATE private.narrative_legacy_publication SET latest_event_id=(SELECT id FROM private.narrative_publication_event WHERE stream_ref=v_ref)
   WHERE legacy_publication_ref=v_ref;
  v_sha:=private.narrative_legacy_state(v_ref,false)->>'state_sha256';
  PERFORM set_config('request.jwt.claim.sub',f->>'actor',true);
  SET LOCAL ROLE authenticated;
  PERFORM set_config('app.change_set_id','',true);
  PERFORM public.red_tilbagetraek_legacy_narrative(v_ref,v_sha,'fixture: teksten var en andens');
  PERFORM set_config('app.change_set_id','',true);
  RESET ROLE;
  PERFORM private.record_legacy_disposition(p_person,v_source,'retained_legacy',NULL,'{"fixture":"rpc v1"}');
  RETURN v_narr;
END $$;

DO $rpc$
DECLARE f jsonb; v_src bigint:=-6400; v_slaegt bigint; v_lineage bigint; v_scheme bigint; v_entry bigint;
  v_run jsonb:=jsonb_build_object('run_key','rp-header-v1','schema_version','header-manifest-v1',
    'extractor_version','fixture','profile_version','rp-header-v1','input_sha256',repeat('9',64),
    'manifest',jsonb_build_object('manifest_sha256',repeat('a',64)));
  v_c jsonb; v_persona uuid; v_rp uuid; v_hl uuid; v_hs uuid; v_hk uuid; v_pv jsonb;
BEGIN
  f:=pg_temp.pp_source(v_src,'a6400000-0000-0000-0000-000000006400');
  INSERT INTO public.slaegt(navn,sorteringsnavn,slug,status) VALUES ('rpc fixture','rpc fixture','frpc','active')
    RETURNING id INTO v_slaegt;
  INSERT INTO public.lineage(slaegt_id,source_id,kode,canonical_label,navn) VALUES (v_slaegt,v_src,'H','H. linje','rpc linje H')
    RETURNING id INTO v_lineage;
  INSERT INTO public.lineage_scheme(slaegt_id,source_id,kind,label) VALUES (v_slaegt,v_src,'stamtavle','rpc kilde')
    RETURNING id INTO v_scheme;
  INSERT INTO public.lineage_scheme_entry(scheme_id,slaegt_id,code,label,sort_order) VALUES (v_scheme,v_slaegt,'H','Den opdigtede Linje.',1)
    RETURNING id INTO v_entry;
  INSERT INTO public.lineage_scheme_entry_lineage(entry_id,lineage_id,slaegt_id,relation_kind) VALUES (v_entry,v_lineage,v_slaegt,'canonical');
  -- Overskrifterne (strukturelle, ikke-ankrede forekomster i kildens rendition).
  PERFORM private.write_header_evidence(v_src,(f->>'rend')::uuid,v_run,jsonb_build_array(
    jsonb_build_object('element_id','header:0','kind','header_linje','page_from',9,'page_to',9,'char_from',0,'char_to',18,
      'verbatim_text','Den opdigtede Linje','verbatim_sha256',encode(extensions.digest('Den opdigtede Linje','sha256'),'hex')),
    jsonb_build_object('element_id','header:20','kind','header_slaegtled','page_from',9,'page_to',9,'char_from',20,'char_to',24,
      'verbatim_text','III.','verbatim_sha256',encode(extensions.digest('III.','sha256'),'hex')),
    jsonb_build_object('element_id','header:600','kind','header_kuld','page_from',10,'page_to',10,'char_from',600,'char_to',619,
      'verbatim_text','Hr. Opdigtets Søn:','verbatim_sha256',encode(extensions.digest('Hr. Opdigtets Søn:','sha256'),'hex'))));
  v_hl:=private.header_observation_uuid((f->>'rend')::uuid,'rp-header-v1',0);
  v_hs:=private.header_observation_uuid((f->>'rend')::uuid,'rp-header-v1',20);
  v_hk:=private.header_observation_uuid((f->>'rend')::uuid,'rp-header-v1',600);

  -- De to helposter uden tekst (rå OCR: orddeling ved linjeskift og en sidemarkør midt i posten).
  PERFORM pg_temp.rpc_post(f,'rpc-a',100,E'Opdigtet Henrik Testesen, f. 1600, Ritmester ved Re-\ngimentet, d. 1650 paa\n### PAGE 0004 ###\nGaarden.');
  PERFORM pg_temp.rpc_post(f,'rpc-b',700,E'Opdigtet Iven Testesen, f. 1610, Kap-\ntajn, d. 1660.');
  PERFORM pg_temp.rpc_person(f,-640001,-640011,'legacy-a');
  PERFORM pg_temp.rpc_person(f,-640002,-640012,'legacy-b');

  -- rpc-c: placeret og promoveret hovedperson (already_current i forhåndsvisningen).
  v_c:=pg_temp.rpc_post(f,'rpc-c',1100,'Opdigtet Claus Testesen, f. 1620.');
  INSERT INTO public.person(id,levende,privat,status) VALUES (-640003,false,false,'rpc');
  INSERT INTO public.person_external_id(person_id,source_id,linje,nr,record_key) VALUES (-640003,v_src,'H',3,'legacy-c');
  INSERT INTO private.source_persona(source_id,persona_key,created_run_id) VALUES (v_src,'fixture:rpc-c',(f->>'run')::uuid)
    RETURNING id INTO v_persona;
  INSERT INTO private.source_persona_mention(persona_id,mention_id,mention_role,ordinal) VALUES (v_persona,(v_c->>'mention')::uuid,'primary',1);
  INSERT INTO private.source_persona_identity(source_persona_id,canonical_person_id,decision_status,version,evidence,
    decided_by,decided_by_name,decided_at) VALUES (v_persona,-640003,'accepted',1,'{"fixture":"rpc"}',(f->>'actor')::uuid,'fixture',now());
  INSERT INTO private.source_persona_identity_event(source_persona_id,canonical_person_id,decision_status,version,evidence,
    decided_by,decided_by_name,decided_at) VALUES (v_persona,-640003,'accepted',1,'{"fixture":"rpc"}',(f->>'actor')::uuid,'fixture',now());
  v_rp:=private.write_record_placement((v_c->>'record')::uuid,v_entry,
    jsonb_build_object('generation_local',3,'generation_label_raw','III','kuld_label','Hr-Opdigtets-Søn',
      'section_path',jsonb_build_array('header:0','header:20','header:600')),v_hl,
    jsonb_build_object('rule_version','rp-header-v1','header_ids',jsonb_build_object('linje',v_hl,'slaegtled',v_hs,'kuld',v_hk),
      'basis','machine','decided_by_name','fixture'));
  PERFORM private.write_persona_placement(v_persona,v_rp,(v_c->>'observation')::uuid,
    jsonb_build_object('rule_version','placement-membership-v1','record_placement_id',v_rp,'decided_by_name','fixture'));
  PERFORM private.record_legacy_disposition(-640003,v_src,'mapped',v_rp,'{"fixture":"rpc v1"}');
  PERFORM set_config('request.jwt.claim.sub',f->>'actor',true);
  SET LOCAL ROLE authenticated;
  v_pv:=public.red_preview_placement_memberships(v_src);
  PERFORM set_config('app.change_set_id','',true);
  IF public.red_promote_placement_memberships(v_src,v_pv->>'preview_sha256')<>1 THEN RAISE EXCEPTION 'RPC_FIXTURE_PROMOTE'; END IF;
  PERFORM set_config('app.change_set_id','',true);
  RESET ROLE;
  IF private.placement_header_violations(v_src)<>0 THEN RAISE EXCEPTION 'RPC_FIXTURE_HEADERS'; END IF;

  -- Den anden udgave.
  INSERT INTO public.source(id,titel,udgave,aar,slags) VALUES (-6401,'Fixture rpc anden','synthetic','2018','DAA-udgave');
  INSERT INTO public.person(id,levende,privat,status) VALUES (-640101,false,false,'rpc');
  INSERT INTO public.person_external_id(person_id,source_id,linje,nr,record_key) VALUES (-640101,-6401,'I',1,'b1');
END $rpc$;
COMMIT;
