-- #150 trin 5c-1: syntetisk mini-kilde til ceremonitesten (tests/sql/test-150-ceremoni.sh). Data COMMIT'es, fordi
-- fix_150_placement.sql kører sin egen transaktion. Kilde -1550: linje I med tre poster (tegn 1000/2000/3000), I-1 og
-- I-2 publiceret, I-3 som draft (manifestets unresolved). Kilde -1551: én legacy-række (retained_legacy). Opdigtede
-- personer med negative id'er. Aktør a1500000-…-150 (redaktion).
-- Prods bindinger kom fra narrative-cutoveren og står som existing_exact_binding UDEN placement; en ny binding kræver i
-- dag en placement (NARRATIVE_RECORD_IDENTITY_REQUIRED). Fixturen publicerer derfor med midlertidige placements (sti i,
-- kind 'header' i postens forekomst), fjerner dem igen som ejer med append-only-triggerne slået fra i denne
-- transaktion, og revaliderer de publicerede — så udgangspunktet er som i prod: bindinger, 0 placements, 0 stale.
\set ON_ERROR_STOP on
BEGIN;
\ir relation-5b.sql
\ir placement-150.sql

CREATE OR REPLACE FUNCTION pg_temp.c150_post(f jsonb,p_key text,p_person bigint,p_nr int,p_slaegtled int,p_char int)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_run uuid:=(f->>'run')::uuid; v_rec uuid; v_occ uuid; v_help uuid; v_mention uuid; v_persona uuid;
  v_text text:='Opdigtet Testesen nr. '||p_nr||', f. 1600.'; v_actor uuid:=(f->>'actor')::uuid; v_at timestamptz:=now();
BEGIN
  INSERT INTO public.person(id) VALUES (p_person);
  INSERT INTO private.source_record(source_id,record_key,record_kind,created_run_id)
    VALUES ((f->>'source')::bigint,p_key,'person_post',v_run) RETURNING id INTO v_rec;
  INSERT INTO private.source_record_occurrence(rendition_id,occurrence_key,page_from,page_to,char_from,char_to,
    verbatim_text,physical_fingerprint,structural_fingerprint,extraction_run_id)
    VALUES ((f->>'rend')::uuid,'occ-'||p_key,10,10,p_char,p_char+char_length(v_text),v_text,repeat('3',64),repeat('4',64),v_run)
    RETURNING id INTO v_occ;
  INSERT INTO private.source_record_anchor_event(occurrence_id,source_record_id,decision_status,evidence,version,decided_by,decided_by_name)
    VALUES (v_occ,v_rec,'accepted','{"fixture":"150"}',1,v_actor,'fixture');
  INSERT INTO private.source_observation(occurrence_id,observation_kind,page_from,page_to,char_from,char_to,
    verbatim_text,quality_status,extraction_method,extraction_run_id)
    VALUES (v_occ,'person_post',10,10,p_char,p_char+char_length(v_text),v_text,'clear','fixture',v_run) RETURNING id INTO v_help;
  INSERT INTO private.source_mention(observation_id,mention_kind,char_from,char_to,verbatim_text,created_run_id)
    VALUES (v_help,'person_post',0,char_length(v_text),v_text,v_run) RETURNING id INTO v_mention;
  INSERT INTO private.source_persona(source_id,persona_key,created_run_id) VALUES ((f->>'source')::bigint,p_key,v_run)
    RETURNING id INTO v_persona;
  INSERT INTO private.source_persona_mention(persona_id,mention_id,mention_role,ordinal) VALUES (v_persona,v_mention,'primary',1);
  INSERT INTO private.source_persona_identity(source_persona_id,canonical_person_id,decision_status,version,evidence,
    decided_by,decided_by_name,decided_at) VALUES (v_persona,p_person,'accepted',1,'{"fixture":"150"}',v_actor,'fixture',v_at);
  INSERT INTO private.source_persona_identity_event(source_persona_id,canonical_person_id,decision_status,version,evidence,
    decided_by,decided_by_name,decided_at) VALUES (v_persona,p_person,'accepted',1,'{"fixture":"150"}',v_actor,'fixture',v_at);
  INSERT INTO public.person_external_id(person_id,source_id,linje,nr,record_key,slaegtled_lokal)
    VALUES (p_person,(f->>'source')::bigint,'I',p_nr,p_key,p_slaegtled);
  -- Midlertidig placement (fjernes igen nedenfor), så publiceringen har identitet.
  INSERT INTO private.source_observation(occurrence_id,observation_kind,page_from,page_to,char_from,char_to,
    verbatim_text,quality_status,extraction_method,extraction_run_id)
    VALUES (v_occ,'header',10,10,p_char,p_char+4,substr(v_text,1,4),'clear','fixture',v_run) RETURNING id INTO v_mention;
  INSERT INTO private.source_record_placement(id,source_record_id,scheme_entry_id,header_observation_id,initial_status)
    VALUES (v_rec,v_rec,(f->>'entry')::bigint,v_mention,'accepted');
  INSERT INTO private.source_record_placement_decision(placement_id,version,decision_status,evidence,decision_origin,decided_by_name)
    VALUES (v_rec,1,'accepted','{"fixture":"150 midlertidig"}','migration','fixture');
  INSERT INTO private.source_persona_placement(id,source_persona_id,record_placement_id,placement_role,basis_observation_id,initial_status)
    VALUES (v_persona,v_persona,v_rec,'principal_member',v_help,'accepted');
  INSERT INTO private.source_persona_placement_decision(placement_id,version,decision_status,evidence,decision_origin,decided_by_name)
    VALUES (v_persona,1,'accepted','{"fixture":"150 midlertidig"}','migration','fixture');
  RETURN jsonb_build_object('record',v_rec,'principal',v_persona,'key',p_key);
END $$;

-- Narrativ som redaktør: upsert (draft) og evt. publicering; app.change_set_id ryddes før hvert kald.
CREATE OR REPLACE FUNCTION pg_temp.c150_narrativ(p_person bigint,p_source bigint,p_key text,p_publish boolean) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE h text; r jsonb;
BEGIN
  h:=private.narrative_record_state(p_person,p_source,p_key,true)->>'state_sha256';
  SET LOCAL ROLE authenticated;
  PERFORM set_config('app.change_set_id','',true);
  r:=public.red_upsert_person_narrative_record(p_person,p_source,p_key,'Opdigtet biografi for '||p_key||'.',false,h);
  PERFORM set_config('app.change_set_id','',true);
  IF p_publish THEN PERFORM public.red_publicer_person_narrative_record(p_person,p_source,p_key,r->>'state_sha256'); END IF;
  PERFORM set_config('app.change_set_id','',true);
  RESET ROLE;
END $$;

CREATE OR REPLACE FUNCTION pg_temp.c150_uden_persona(f jsonb,p_key text,p_person bigint,p_nr int,p_slaegtled int,p_char int)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_run uuid:=(f->>'run')::uuid; v_rec uuid; v_occ uuid; v_text text:='Opdigtet tekst uden navn nr. '||p_nr||'.';
BEGIN
  INSERT INTO public.person(id) VALUES (p_person);
  INSERT INTO private.source_record(source_id,record_key,record_kind,created_run_id)
    VALUES ((f->>'source')::bigint,p_key,'person_post',v_run) RETURNING id INTO v_rec;
  INSERT INTO private.source_record_occurrence(rendition_id,occurrence_key,page_from,page_to,char_from,char_to,
    verbatim_text,physical_fingerprint,structural_fingerprint,extraction_run_id)
    VALUES ((f->>'rend')::uuid,'occ-'||p_key,10,10,p_char,p_char+char_length(v_text),v_text,repeat('3',64),repeat('4',64),v_run)
    RETURNING id INTO v_occ;
  INSERT INTO private.source_record_anchor_event(occurrence_id,source_record_id,decision_status,evidence,version,decided_by,decided_by_name)
    VALUES (v_occ,v_rec,'accepted','{"fixture":"150"}',1,(f->>'actor')::uuid,'fixture');
  INSERT INTO private.source_observation(occurrence_id,observation_kind,page_from,page_to,char_from,char_to,
    verbatim_text,quality_status,extraction_method,extraction_run_id)
    VALUES (v_occ,'person_post',10,10,p_char,p_char+char_length(v_text),v_text,'clear','fixture',v_run);
  INSERT INTO public.person_external_id(person_id,source_id,linje,nr,record_key,slaegtled_lokal)
    VALUES (p_person,(f->>'source')::bigint,'I',p_nr,p_key,p_slaegtled);
END $$;

CREATE OR REPLACE FUNCTION pg_temp.c150_revalider(p_person bigint,p_source bigint,p_key text) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE h text:=private.narrative_record_state(p_person,p_source,p_key,true)->>'state_sha256';
BEGIN
  SET LOCAL ROLE authenticated;
  PERFORM set_config('app.change_set_id','',true);
  PERFORM public.red_revalider_person_narrative_record(p_person,p_source,p_key,h);
  PERFORM set_config('app.change_set_id','',true);
  RESET ROLE;
END $$;

DO $c150$
DECLARE f jsonb:=pg_temp.f150_source(-1550); g jsonb;
BEGIN
  PERFORM pg_temp.c150_post(f,'I-1',-155001,1,1,1000);
  PERFORM pg_temp.c150_post(f,'I-2',-155002,2,2,2000);
  PERFORM pg_temp.c150_post(f,'I-3',-155003,3,2,3000);
  PERFORM set_config('request.jwt.claim.sub',f->>'actor',true);
  PERFORM pg_temp.c150_narrativ(-155001,-1550,'I-1',true);
  PERFORM pg_temp.c150_narrativ(-155002,-1550,'I-2',true);
  PERFORM pg_temp.c150_narrativ(-155003,-1550,'I-3',false);
  -- Fjern de midlertidige placements (kun syntetiske fixture-data) og revalidér de nu forældede publiceringer.
  SET CONSTRAINTS ALL IMMEDIATE;   -- udskudte placement-tjek kører nu, så ALTER TABLE ikke møder ventende hændelser
  SET CONSTRAINTS ALL DEFERRED;
  ALTER TABLE private.source_persona_placement_decision DISABLE TRIGGER USER;
  ALTER TABLE private.source_persona_placement DISABLE TRIGGER USER;
  ALTER TABLE private.source_record_placement_decision DISABLE TRIGGER USER;
  ALTER TABLE private.source_record_placement DISABLE TRIGGER USER;
  DELETE FROM private.source_persona_placement_decision d USING private.source_persona_placement pp, private.source_record r
   WHERE d.placement_id=pp.id AND pp.id=pp.source_persona_id AND r.id=pp.record_placement_id AND r.source_id=-1550;
  DELETE FROM private.source_persona_placement pp USING private.source_record r
   WHERE r.id=pp.record_placement_id AND r.source_id=-1550;
  DELETE FROM private.source_record_placement_decision d USING private.source_record r
   WHERE r.id=d.placement_id AND r.source_id=-1550;
  DELETE FROM private.source_record_placement rp USING private.source_record r
   WHERE r.id=rp.source_record_id AND r.source_id=-1550;
  ALTER TABLE private.source_persona_placement_decision ENABLE TRIGGER USER;
  ALTER TABLE private.source_persona_placement ENABLE TRIGGER USER;
  ALTER TABLE private.source_record_placement_decision ENABLE TRIGGER USER;
  ALTER TABLE private.source_record_placement ENABLE TRIGGER USER;
  PERFORM pg_temp.c150_revalider(-155001,-1550,'I-1');
  PERFORM pg_temp.c150_revalider(-155002,-1550,'I-2');
  -- I-4: en post uden hovedperson-persona (som prods 4 sidste poster pr. linje): forekomst, anker og helpost, men
  -- ingen mention/persona. Den får record-placement, men hverken persona-placement eller membership.
  PERFORM pg_temp.c150_uden_persona(f,'I-4',-155004,4,2,4000);
  g:=pg_temp.f5b_source(-1551);
  INSERT INTO public.person(id) VALUES (-155101);
  INSERT INTO public.person_external_id(person_id,source_id,linje,nr,record_key) VALUES (-155101,-1551,'1939',1,'I-1');
END $c150$;
COMMIT;
\echo CEREMONI150_FIXTURE_OK
