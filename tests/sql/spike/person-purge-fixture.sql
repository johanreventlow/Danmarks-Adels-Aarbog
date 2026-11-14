-- Task 0 låse-spike: syntetisk fixtur for de tvungne interleavings. KUN engangsbaser. Kræver kontrakt v2
-- (tests/sql/reimport-writer-v2-bootstrap.sql) og person-purge-skelet.sql. Alle navne er syntetiske.
-- Negative id'er er bevidst valgt her (spiket bruger ikke parse_mentions); Task 2a bygger den rigtige fixtur med
-- positive id'er via skriverne.
--   P  = -9101  hovedpersonen: fakta med påstand/citat/konklusion (kilde S), note, medierelation, membership fra en
--               placement, persona X_P placeret i record P-REC med accepteret identitet → P, forslag til red_ret_paastand
--   Q  = -9102  en anden person i samme kilde (OCR-rettelse på Q, D-1)
--   L  = -9103  en »let« person uden ledger (kan slettes helt af skelettet; Task 11 f/g)
--   Z           en uafgjort persona i S (red_afgoer_source_persona / red_record_identity_candidates)
\set ON_ERROR_STOP on
BEGIN;
DO $spike_fixture$
DECLARE
  v_actor uuid := 'c0000000-0000-4000-8000-00000000a001';
  v_run uuid := 'c0000000-0000-4000-8000-0000000000a1';
  v_rend uuid := 'c0000000-0000-4000-8000-0000000000a2';
  v_s bigint := -9001;
  v_rec uuid; v_occ uuid; v_obs uuid; v_men uuid; v_xp uuid; v_rpl uuid; v_ppl uuid;
  v_z uuid; v_zmen uuid; v_fact bigint; v_a bigint; v_int uuid; k text; pid bigint;
BEGIN
  INSERT INTO auth.users(id,email) VALUES (v_actor,'spike-purge@test.invalid');
  INSERT INTO public.profiles(id,rolle,navn,email) VALUES (v_actor,'redaktion','Spike redaktør','spike-purge@test.invalid');
  INSERT INTO public.person(id,levende,privat,staged,visning_navn) VALUES
    (-9101,false,false,false,'Testperson Purge'),(-9102,false,false,false,'Testperson Anden'),
    (-9103,false,false,false,'Testperson Let');
  INSERT INTO public.source(id,slags,titel,udgave,aar,import_key)
    VALUES (v_s,'DAA-udgave','Spike kilde','Spike syntetisk',1939,'spike:purge');
  INSERT INTO public.person_external_id(person_id,source_id,record_key) VALUES
    (-9101,v_s,'P-REC'),(-9102,v_s,'Q-REC'),(-9103,v_s,'L-REC');
  INSERT INTO private.extraction_run(id,source_id,run_key,schema_version,extractor_version,profile_version,input_sha256,manifest)
    VALUES (v_run,v_s,'spike-run','1','spike','spike',repeat('1',64),'{}');
  INSERT INTO private.source_rendition(id,source_id,rendition_key,rendition_kind,content_sha256,metadata)
    VALUES (v_rend,v_s,'spike-rendition','text_layer',repeat('2',64),'{}');
  INSERT INTO public.slaegt(id,navn,sorteringsnavn,slug) VALUES (-9001,'Spike slægt','Spike slægt','spike-slaegt');
  INSERT INTO public.lineage_scheme(id,slaegt_id,source_id,kind,label) VALUES (-9001,-9001,v_s,'stamtavle','Spike skema');
  INSERT INTO public.lineage_scheme_entry(id,scheme_id,slaegt_id,code,label,sort_order)
    VALUES (-9001,-9001,-9001,'A','Linje A',1);
  INSERT INTO public.lineage(id,source_id,kode,navn,slaegt_id) VALUES (-9001,v_s,'A','Spike linje',-9001);

  -- Fakta med påstand, citat (kilde S) og afklaret konklusion: navn for P, Q, L; titel og fødsel for P.
  FOREACH k IN ARRAY ARRAY['-9101:navn:Testperson Purge','-9102:navn:Testperson Anden','-9103:navn:Testperson Let',
                           '-9101:titel:Kammerherre','-9101:fødsel:'] LOOP
    pid := split_part(k,':',1)::bigint;
    INSERT INTO public.fact(subjekt_type,subjekt_id,faktatype) VALUES ('person',pid,split_part(k,':',2)) RETURNING id INTO v_fact;
    IF split_part(k,':',2)='fødsel' THEN
      INSERT INTO public.assertion(target_type,target_id,date_raw,date_min,date_max,calendar,uforanderlig)
        VALUES ('fact',v_fact,'1700','1700-01-01','1700-12-31','gregoriansk',true) RETURNING id INTO v_a;
    ELSE
      INSERT INTO public.assertion(target_type,target_id,vaerdi_tekst,calendar,uforanderlig)
        VALUES ('fact',v_fact,split_part(k,':',3),'gregoriansk',true) RETURNING id INTO v_a;
    END IF;
    INSERT INTO public.citation(assertion_id,source_id,citat_tekst,side) VALUES (v_a,v_s,'spike','1');
    INSERT INTO public.conclusion(target_type,target_id,valgt_assertion_id,status) VALUES ('fact',v_fact,v_a,'afklaret');
  END LOOP;
  INSERT INTO public.note(target_type,target_id,indhold) VALUES ('person',-9101,'Spike note'),('person',-9103,'Spike note');

  -- Medie og evidensfri afbildning (red_slet_medierelation_uden_evidens).
  INSERT INTO public.media(id,slags,titel) VALUES (-9001,'foto','Spike medie');
  INSERT INTO public.relation(subjekt_type,subjekt_id,rolle,objekt_type,objekt_id)
    VALUES ('person',-9101,'afbildet','media',-9001);

  -- Record P-REC med placeret persona X_P (accepteret → P); formen fra test-narrative-record-concurrency.R seed_record.
  INSERT INTO private.source_record(source_id,record_key,record_kind,created_run_id)
    VALUES (v_s,'P-REC','person',v_run) RETURNING id INTO v_rec;
  INSERT INTO private.source_record_occurrence(rendition_id,occurrence_key,page_from,page_to,char_from,char_to,
    verbatim_text,physical_fingerprint,structural_fingerprint,extraction_run_id)
    VALUES (v_rend,'P-REC',4,4,0,20,'Spike forekomst','spike-phys','spike-struct',v_run) RETURNING id INTO v_occ;
  INSERT INTO private.source_record_anchor_event(occurrence_id,source_record_id,decision_status,evidence,version,
    decided_by,decided_by_name)
    VALUES (v_occ,v_rec,'accepted',jsonb_build_object('basis','spike'),1,v_actor,'Spike');
  INSERT INTO private.source_observation(occurrence_id,observation_kind,page_from,page_to,char_from,char_to,
    verbatim_text,quality_status,extraction_method,extraction_run_id)
    VALUES (v_occ,'header',4,4,0,20,'Spike observation','clear','spike',v_run) RETURNING id INTO v_obs;
  INSERT INTO private.source_persona(source_id,persona_key,created_run_id) VALUES (v_s,'spike-xp',v_run) RETURNING id INTO v_xp;
  INSERT INTO private.source_mention(observation_id,mention_kind,char_from,char_to,verbatim_text,created_run_id)
    VALUES (v_obs,'person_name',0,5,'Spike',v_run) RETURNING id INTO v_men;
  INSERT INTO private.source_persona_mention(persona_id,mention_id,mention_role,ordinal) VALUES (v_xp,v_men,'primary',1);
  INSERT INTO private.source_record_placement(source_record_id,scheme_entry_id,header_observation_id,initial_status)
    VALUES (v_rec,-9001,v_obs,'accepted') RETURNING id INTO v_rpl;
  INSERT INTO private.source_record_placement_decision(placement_id,version,decision_status,evidence,decision_origin,decided_by_name)
    VALUES (v_rpl,1,'accepted',jsonb_build_object('basis','spike'),'migration','Spike');
  INSERT INTO private.source_persona_placement(source_persona_id,record_placement_id,placement_role,basis_observation_id,initial_status)
    VALUES (v_xp,v_rpl,'principal_member',v_obs,'accepted') RETURNING id INTO v_ppl;
  INSERT INTO private.source_persona_placement_decision(placement_id,version,decision_status,evidence,decision_origin,decided_by_name)
    VALUES (v_ppl,1,'accepted',jsonb_build_object('basis','spike'),'migration','Spike');
  INSERT INTO private.source_persona_identity_event(source_persona_id,canonical_person_id,decision_status,version,evidence,
    decided_by,decided_by_name,decided_at)
    VALUES (v_xp,-9101,'accepted',1,jsonb_build_object('basis','spike'),v_actor,'Spike',transaction_timestamp());
  INSERT INTO private.source_persona_identity(source_persona_id,canonical_person_id,decision_status,version,evidence,
    decided_by,decided_by_name,decided_at)
    VALUES (v_xp,-9101,'accepted',1,jsonb_build_object('basis','spike'),v_actor,'Spike',transaction_timestamp());

  -- Membership fra placementen (red_reverse_placement_membership).
  INSERT INTO public.person_slaegt_membership(person_id,slaegt_id,membership_kind,source_basis)
    VALUES (-9101,-9001,'agnatic',jsonb_build_object('rule_version','placement-membership-v1','slaegt_id',-9001,
            'persona_placement_id',v_ppl));
  INSERT INTO public.person_lineage_membership(person_id,lineage_id,role,source_basis)
    VALUES (-9101,-9001,'member',jsonb_build_object('rule_version','placement-membership-v1','slaegt_id',-9001,
            'persona_placement_id',v_ppl));

  -- Forslag fra X_P til P's titel (red_ret_paastand, grund bogen_har_ret).
  INSERT INTO private.interpretation(id,interpretation_key,version,source_id,source_persona_id,interpretation_kind,
    predicate,value,schema_version,derivation_kind,confidence,status,method,extraction_run_id)
    VALUES ('c0000000-0000-4000-8000-0000000000b1','c0000000-0000-4000-8000-0000000000b2',1,v_s,v_xp,'property',
      'person.title',to_jsonb('Overhofmarskal'::text),'1.0','source_statement',1,'proposed','spike',v_run);
  INSERT INTO private.interpretation_observation(interpretation_id,observation_id,evidence_role,ordinal)
    VALUES ('c0000000-0000-4000-8000-0000000000b1',v_obs,'supporting',1);

  -- Uafgjort persona Z i S.
  INSERT INTO private.source_persona(id,source_id,persona_key,created_run_id)
    VALUES ('c0000000-0000-4000-8000-0000000000c1',v_s,'spike-z',v_run) RETURNING id INTO v_z;
  INSERT INTO private.source_mention(observation_id,mention_kind,char_from,char_to,verbatim_text,created_run_id)
    VALUES (v_obs,'person',0,5,'Spike',v_run) RETURNING id INTO v_zmen;
  INSERT INTO private.source_persona_mention(persona_id,mention_id,mention_role,ordinal) VALUES (v_z,v_zmen,'primary',1);
END $spike_fixture$;
COMMIT;
