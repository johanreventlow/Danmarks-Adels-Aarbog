-- Trin 6e-2 Task 9: syntetisk mini-kilde til etiket-ceremonien (tests/sql/test-etiket-ceremoni.sh). Data COMMIT'es,
-- fordi etiket_ceremoni.sql kører sin egen transaktion. Opdigtede personer med negative id'er; aktør a6e2…6e2.
--   Kilde -6920 (udgave »DAA T«, intet sidekort): et linjeskema med de otte entries og etiketter, som bogens
--     stamtavle har før 6e-2 (så testen bruger de rigtige filer linjeetiketter_6e2.json og sidekort_1939.json), og fire
--     poster uden bogtrykt nøgle (record-<uuid>), alle med publiceret biografi:
--       r1  IV, nr. 3        PDF-side 538 (s. 49)
--       r2  ingen placement  PDF-side 541 (s. 52); publiceres med en midlertidig placement, som fjernes igen (med
--           triggerne slået fra i denne transaktion), som 6d-1's fixtur gør
--       r3  Stamme-holstenske (rettes til »A. …«), nr. 2  PDF-side 491 (s. 2)
--       r4  III (rettes: »…af Ziesendorf.«), uden nr.     PDF-side 572 (s. 66)
--       r5  staged person, ingen placement, PDF-side 543: publiceret og ikke forældet (som prods to i 1939: en baseline-
--           hændelse skrevet, mens personen var staged, indsættes direkte med replica). Ceremonien springer den over.
--   Kilde -6921 (udgave »DAA M«, modpart med bognøgle): posten V-1 i entry V, nr. 1, PDF-side 45, publiceret biografi
--     og en legacy-række, så andre kilders koordinater og etiketter er målbare.
-- Bindingerne publiceres med 6e-2's skrivere (som allerede giver den nye etiketform); derefter får kilde -6920's
-- bindinger den gamle form (record_label = record_key, citation_label »DAA T side <PDF-side>«) og revalideres, så
-- udgangspunktet er som i prod før ceremonien: record-etiketter i bindingen og den seneste hændelse, 0 stale.
\set ON_ERROR_STOP on
BEGIN;
\ir relation-5b.sql

-- En post med helpost, hovedperson-persona og accepteret identitet; p_entry NULL = ingen placement.
CREATE OR REPLACE FUNCTION pg_temp.e6e2_post(f jsonb,p_key text,p_person bigint,p_char int,p_page int,p_entry bigint,
  p_nr text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_run uuid:=(f->>'run')::uuid; v_rec uuid; v_occ uuid; v_help uuid; v_mention uuid; v_persona uuid; v_hdr uuid;
  v_text text:='Opdigtet Testesen '||p_person||', f. 1600.'; v_actor uuid:=(f->>'actor')::uuid; v_at timestamptz:=now();
BEGIN
  INSERT INTO public.person(id) VALUES (p_person);
  INSERT INTO private.source_record(source_id,record_key,record_kind,created_run_id)
    VALUES ((f->>'source')::bigint,p_key,'person_post',v_run) RETURNING id INTO v_rec;
  INSERT INTO private.source_record_occurrence(rendition_id,occurrence_key,page_from,page_to,char_from,char_to,
    verbatim_text,physical_fingerprint,structural_fingerprint,extraction_run_id)
    VALUES ((f->>'rend')::uuid,'occ-'||p_key,p_page,p_page,p_char,p_char+char_length(v_text),v_text,repeat('3',64),
            repeat('4',64),v_run)
    RETURNING id INTO v_occ;
  INSERT INTO private.source_record_anchor_event(occurrence_id,source_record_id,decision_status,evidence,version,decided_by,decided_by_name)
    VALUES (v_occ,v_rec,'accepted','{"fixture":"6e2"}',1,v_actor,'fixture');
  INSERT INTO private.source_observation(occurrence_id,observation_kind,page_from,page_to,char_from,char_to,
    verbatim_text,quality_status,extraction_method,extraction_run_id)
    VALUES (v_occ,'person',p_page,p_page,p_char,p_char+char_length(v_text),v_text,'clear','fixture',v_run) RETURNING id INTO v_help;
  INSERT INTO private.source_mention(observation_id,mention_kind,char_from,char_to,verbatim_text,created_run_id)
    VALUES (v_help,'person_post',0,char_length(v_text),v_text,v_run) RETURNING id INTO v_mention;
  INSERT INTO private.source_persona(source_id,persona_key,created_run_id) VALUES ((f->>'source')::bigint,p_key,v_run)
    RETURNING id INTO v_persona;
  INSERT INTO private.source_persona_mention(persona_id,mention_id,mention_role,ordinal) VALUES (v_persona,v_mention,'primary',1);
  INSERT INTO private.source_persona_identity(source_persona_id,canonical_person_id,decision_status,version,evidence,
    decided_by,decided_by_name,decided_at) VALUES (v_persona,p_person,'accepted',1,'{"fixture":"6e2"}',v_actor,'fixture',v_at);
  INSERT INTO private.source_persona_identity_event(source_persona_id,canonical_person_id,decision_status,version,evidence,
    decided_by,decided_by_name,decided_at) VALUES (v_persona,p_person,'accepted',1,'{"fixture":"6e2"}',v_actor,'fixture',v_at);
  IF p_entry IS NULL THEN RETURN; END IF;
  INSERT INTO private.source_observation(occurrence_id,observation_kind,page_from,page_to,char_from,char_to,
    verbatim_text,quality_status,extraction_method,extraction_run_id)
    VALUES (v_occ,'header',p_page,p_page,p_char,p_char+4,substr(v_text,1,4),'clear','fixture',v_run) RETURNING id INTO v_hdr;
  INSERT INTO private.source_record_placement(id,source_record_id,scheme_entry_id,header_observation_id,initial_status,printed_number)
    VALUES (v_rec,v_rec,p_entry,v_hdr,'accepted',p_nr);
  INSERT INTO private.source_record_placement_decision(placement_id,version,decision_status,evidence,decision_origin,decided_by_name)
    VALUES (v_rec,1,'accepted','{"fixture":"6e2"}','migration','fixture');
  INSERT INTO private.source_persona_placement(id,source_persona_id,record_placement_id,placement_role,basis_observation_id,initial_status)
    VALUES (v_persona,v_persona,v_rec,'principal_member',v_help,'accepted');
  INSERT INTO private.source_persona_placement_decision(placement_id,version,decision_status,evidence,decision_origin,decided_by_name)
    VALUES (v_persona,1,'accepted','{"fixture":"6e2"}','migration','fixture');
END $$;

-- Narrativ som redaktør: upsert (draft) og publicering; app.change_set_id ryddes før hvert kald.
CREATE OR REPLACE FUNCTION pg_temp.e6e2_narrativ(p_person bigint,p_source bigint,p_key text) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE h text; r jsonb;
BEGIN
  h:=private.narrative_record_state(p_person,p_source,p_key,true)->>'state_sha256';
  SET LOCAL ROLE authenticated;
  PERFORM set_config('app.change_set_id','',true);
  r:=public.red_upsert_person_narrative_record(p_person,p_source,p_key,'Opdigtet biografi for '||p_person||'.',false,h);
  PERFORM set_config('app.change_set_id','',true);
  PERFORM public.red_publicer_person_narrative_record(p_person,p_source,p_key,r->>'state_sha256');
  PERFORM set_config('app.change_set_id','',true);
  RESET ROLE;
END $$;

-- Fjern en posts placements (kun syntetiske data; triggerne slås fra i denne transaktion).
CREATE OR REPLACE FUNCTION pg_temp.e6e2_uden_placement(p_source bigint,p_key text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  ALTER TABLE private.source_persona_placement_decision DISABLE TRIGGER USER;
  ALTER TABLE private.source_persona_placement DISABLE TRIGGER USER;
  ALTER TABLE private.source_record_placement_decision DISABLE TRIGGER USER;
  ALTER TABLE private.source_record_placement DISABLE TRIGGER USER;
  DELETE FROM private.source_persona_placement_decision d USING private.source_persona_placement pp, private.source_record r
   WHERE d.placement_id=pp.id AND r.id=pp.record_placement_id AND r.source_id=p_source AND r.record_key=p_key;
  DELETE FROM private.source_persona_placement pp USING private.source_record r
   WHERE r.id=pp.record_placement_id AND r.source_id=p_source AND r.record_key=p_key;
  DELETE FROM private.source_record_placement_decision d USING private.source_record r
   WHERE r.id=d.placement_id AND r.source_id=p_source AND r.record_key=p_key;
  DELETE FROM private.source_record_placement rp USING private.source_record r
   WHERE r.id=rp.source_record_id AND r.source_id=p_source AND r.record_key=p_key;
  ALTER TABLE private.source_persona_placement_decision ENABLE TRIGGER USER;
  ALTER TABLE private.source_persona_placement ENABLE TRIGGER USER;
  ALTER TABLE private.source_record_placement_decision ENABLE TRIGGER USER;
  ALTER TABLE private.source_record_placement ENABLE TRIGGER USER;
END $$;

-- Bindingen får den gamle etiketform (som i prod før 6e-2) og revalideres.
CREATE OR REPLACE FUNCTION pg_temp.e6e2_gammel(p_person bigint,p_source bigint,p_key text,p_page int) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE h text;
BEGIN
  UPDATE private.narrative_record_publication b SET record_label=p_key, citation_label='DAA T side '||p_page
    FROM private.source_record sr WHERE sr.id=b.source_record_id AND sr.source_id=p_source AND sr.record_key=p_key;
  h:=private.narrative_record_state(p_person,p_source,p_key,true)->>'state_sha256';
  SET LOCAL ROLE authenticated;
  PERFORM set_config('app.change_set_id','',true);
  PERFORM public.red_revalider_person_narrative_record(p_person,p_source,p_key,h);
  PERFORM set_config('app.change_set_id','',true);
  RESET ROLE;
END $$;

-- Personen bliver staged; en hændelse, der matcher den staged tilstand, indsættes direkte (replica), så bindingen er
-- publiceret og ikke forældet (revalideringen afviser en staged person).
CREATE OR REPLACE FUNCTION pg_temp.e6e2_staged(p_person bigint,p_source bigint,p_key text) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE st jsonb;
BEGIN
  UPDATE public.person SET staged=true WHERE id=p_person;
  st:=private.narrative_record_state(p_person,p_source,p_key);
  SET LOCAL session_replication_role=replica;
  INSERT INTO private.narrative_publication_event(change_set_id,stream_ref,stream_version,event_type,binding_id,narrative_id,
    source_id,source_record_id,decision_basis,before_state,after_state,before_state_sha256,after_state_sha256,decided_by,decided_by_name)
  SELECT e.change_set_id,e.stream_ref,e.stream_version+1,'revalidated',e.binding_id,e.narrative_id,e.source_id,e.source_record_id,
         'fixture: staged baseline',e.after_state,st->'publication_state',e.after_state_sha256,st->>'publication_state_sha256',
         e.decided_by,'fixture'
    FROM private.narrative_publication_event e
   WHERE e.binding_id=(st #>> '{publication_state,binding,binding_id}')::uuid
   ORDER BY e.stream_version DESC LIMIT 1;
  SET LOCAL session_replication_role=origin;
END $$;

DO $e6e2$
DECLARE v_actor uuid:='a6e20000-0000-0000-0000-0000000006e2'; v_slaegt bigint; v_scheme bigint; s jsonb; m jsonb;
  e jsonb:='{}'; v_id bigint; r record; k text:='record-6e200000-0000-0000-0000-00000000000';
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  INSERT INTO public.slaegt(navn,sorteringsnavn,slug,status) VALUES ('6e2 fixture','6e2 fixture','f6e2','active')
    RETURNING id INTO v_slaegt;

  -- Kilden -6920 med linjeskemaets otte entries (etiketterne før 6e-2).
  s:=pg_temp.f5b_source(-6920);
  UPDATE public.source SET udgave='DAA T', titel='Testaarbog' WHERE id=-6920;
  INSERT INTO public.lineage_scheme(slaegt_id,source_id,kind,label) VALUES (v_slaegt,-6920,'stamtavle','6e2 kilde')
    RETURNING id INTO v_scheme;
  FOR r IN SELECT * FROM (VALUES
      ('Stamme-holstenske','Den holstenske Linje.',1),
      ('Stamme-ældre-meklenborgske','Den ældre meklenborgske Linje.',2),
      ('I','Den holstenske Linje.',3),
      ('II','II. Linjen Gallentin.',4),
      ('III','III. Den ældre meklenborgske Linje af iesendorf.',5),
      ('IV','IV. Den danske grevelige Linje af 1673.',6),
      ('V','V. Den grevelige Linje af 1767.',7),
      ('VI','Den fyenske Linje',8)) x(code,label,ord) LOOP
    INSERT INTO public.lineage_scheme_entry(scheme_id,slaegt_id,code,label,sort_order)
      VALUES (v_scheme,v_slaegt,r.code,r.label,r.ord) RETURNING id INTO v_id;
    e:=e||jsonb_build_object(r.code,v_id);
  END LOOP;
  s:=s||jsonb_build_object('source',-6920,'actor',v_actor);
  PERFORM pg_temp.e6e2_post(s,k||'1',-692001,1000,538,(e->>'IV')::bigint,'3');
  PERFORM pg_temp.e6e2_post(s,k||'2',-692002,2000,541,(e->>'IV')::bigint,NULL);
  PERFORM pg_temp.e6e2_post(s,k||'3',-692003,3000,491,(e->>'Stamme-holstenske')::bigint,'2');
  PERFORM pg_temp.e6e2_post(s,k||'4',-692004,4000,572,(e->>'III')::bigint,NULL);
  PERFORM pg_temp.e6e2_post(s,k||'5',-692005,5000,543,(e->>'IV')::bigint,NULL);
  PERFORM pg_temp.e6e2_narrativ(-692001,-6920,k||'1');
  PERFORM pg_temp.e6e2_narrativ(-692002,-6920,k||'2');
  PERFORM pg_temp.e6e2_narrativ(-692003,-6920,k||'3');
  PERFORM pg_temp.e6e2_narrativ(-692004,-6920,k||'4');
  PERFORM pg_temp.e6e2_narrativ(-692005,-6920,k||'5');
  SET CONSTRAINTS ALL IMMEDIATE;
  SET CONSTRAINTS ALL DEFERRED;
  PERFORM pg_temp.e6e2_uden_placement(-6920,k||'2');
  PERFORM pg_temp.e6e2_uden_placement(-6920,k||'5');
  PERFORM pg_temp.e6e2_gammel(-692001,-6920,k||'1',538);
  PERFORM pg_temp.e6e2_gammel(-692002,-6920,k||'2',541);
  PERFORM pg_temp.e6e2_gammel(-692003,-6920,k||'3',491);
  PERFORM pg_temp.e6e2_gammel(-692004,-6920,k||'4',572);
  PERFORM pg_temp.e6e2_gammel(-692005,-6920,k||'5',543);
  PERFORM pg_temp.e6e2_staged(-692005,-6920,k||'5');

  -- Modparten -6921 med bognøgle.
  m:=pg_temp.f5b_source(-6921);
  UPDATE public.source SET udgave='DAA M', titel='Modpartsaarbog' WHERE id=-6921;
  INSERT INTO public.lineage_scheme(slaegt_id,source_id,kind,label) VALUES (v_slaegt,-6921,'stamtavle','6e2 modpart')
    RETURNING id INTO v_scheme;
  INSERT INTO public.lineage_scheme_entry(scheme_id,slaegt_id,code,label,sort_order)
    VALUES (v_scheme,v_slaegt,'V','V. Den grevelige linje',1) RETURNING id INTO v_id;
  m:=m||jsonb_build_object('source',-6921,'actor',v_actor);
  PERFORM pg_temp.e6e2_post(m,'V-1',-692101,1000,45,v_id,'1');
  PERFORM pg_temp.e6e2_narrativ(-692101,-6921,'V-1');
  INSERT INTO public.person_external_id(person_id,source_id,linje,nr,record_key) VALUES (-692101,-6921,'V',1,'V-1');
END $e6e2$;
COMMIT;
\echo ETIKET_CEREMONI_FIXTURE_OK
