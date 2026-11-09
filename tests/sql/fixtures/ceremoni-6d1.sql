-- Trin 6d-1 Task 7: syntetisk mini-kilde til placement-ceremonien (tests/sql/test-placement-ceremoni.sh). Data COMMIT'es,
-- fordi placement_ceremoni.sql kører sin egen transaktion. Opdigtede personer med negative id'er; aktør a6d1…6d1.
--   Kilde -1611 (modpart, »tidligere udgave«): slægt f6d1 med linjerne (-1611,'I') og (-1611,'II'), stamtavle-schema med
--     entries I og II (canonical), én placeret og promoveret hovedperson -161101 (record k1) med publiceret biografi
--     og én person -161102 med kun en legacy-række.
--   Kilde -1610 (kilden, der placeres): stamtavle-schema med den eksisterende entry VI (sort_order 1 som i prod;
--     mappingen flytter den til 3; canonical til linjen (-1610,'VI')), fire records p1-p4 (tegn 1000/2000/3000/4000) med hovedperson-persona og accepteret identitet til
--     -161001..-161004; p1-p3 publiceret, p4 uden biografi. Legacy-rækkernes record_key er p1, x-2, x-3 og NULL (kun p1
--     svarer til recorden, som i 1939). Desuden kortposterne g1-g3, s1-s2 og u1 (tegn 6000-9500, personer -161005..
--     -161010, uden legacy-række og biografi; se manifest-6d1.json). -161001 samme_som -161101 (afklaret) → komponenten bliver corroborated.
--     Helposten har typen `person` som 1939-profilerne (helpost_observation_kind); modpartens har `person_post`.
--   Ledger: modpartens rækker har 5c-1's form (k1 mapped, k2 retained_legacy); kildens har ingen (testen tilføjer
--     5c-1's v1 retained_legacy i et eget scenarie).
-- Bindingerne publiceres som i ceremoni-150.sql med midlertidige placements (fjernes igen med triggerne slået fra i
-- denne transaktion) og revalideres, så udgangspunktet er: bindinger, 0 placements for -1610, 0 stale.
\set ON_ERROR_STOP on
BEGIN;
\ir relation-5b.sql
\ir placement-150.sql

CREATE OR REPLACE FUNCTION pg_temp.c6d1_post(f jsonb,p_key text,p_person bigint,p_char int) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE v_run uuid:=(f->>'run')::uuid; v_rec uuid; v_occ uuid; v_help uuid; v_mention uuid; v_persona uuid; v_hdr uuid;
  v_text text:='Opdigtet Testesen '||p_key||', f. 1600.'; v_actor uuid:=(f->>'actor')::uuid; v_at timestamptz:=now();
BEGIN
  INSERT INTO public.person(id) VALUES (p_person);
  INSERT INTO private.source_record(source_id,record_key,record_kind,created_run_id)
    VALUES ((f->>'source')::bigint,p_key,'person_post',v_run) RETURNING id INTO v_rec;
  INSERT INTO private.source_record_occurrence(rendition_id,occurrence_key,page_from,page_to,char_from,char_to,
    verbatim_text,physical_fingerprint,structural_fingerprint,extraction_run_id)
    VALUES ((f->>'rend')::uuid,'occ-'||p_key,10,10,p_char,p_char+char_length(v_text),v_text,repeat('3',64),repeat('4',64),v_run)
    RETURNING id INTO v_occ;
  INSERT INTO private.source_record_anchor_event(occurrence_id,source_record_id,decision_status,evidence,version,decided_by,decided_by_name)
    VALUES (v_occ,v_rec,'accepted','{"fixture":"6d1"}',1,v_actor,'fixture');
  INSERT INTO private.source_observation(occurrence_id,observation_kind,page_from,page_to,char_from,char_to,
    verbatim_text,quality_status,extraction_method,extraction_run_id)
    VALUES (v_occ,'person',10,10,p_char,p_char+char_length(v_text),v_text,'clear','fixture',v_run) RETURNING id INTO v_help;
  INSERT INTO private.source_mention(observation_id,mention_kind,char_from,char_to,verbatim_text,created_run_id)
    VALUES (v_help,'person_post',0,char_length(v_text),v_text,v_run) RETURNING id INTO v_mention;
  INSERT INTO private.source_persona(source_id,persona_key,created_run_id) VALUES ((f->>'source')::bigint,p_key,v_run)
    RETURNING id INTO v_persona;
  INSERT INTO private.source_persona_mention(persona_id,mention_id,mention_role,ordinal) VALUES (v_persona,v_mention,'primary',1);
  INSERT INTO private.source_persona_identity(source_persona_id,canonical_person_id,decision_status,version,evidence,
    decided_by,decided_by_name,decided_at) VALUES (v_persona,p_person,'accepted',1,'{"fixture":"6d1"}',v_actor,'fixture',v_at);
  INSERT INTO private.source_persona_identity_event(source_persona_id,canonical_person_id,decision_status,version,evidence,
    decided_by,decided_by_name,decided_at) VALUES (v_persona,p_person,'accepted',1,'{"fixture":"6d1"}',v_actor,'fixture',v_at);
  -- Midlertidig placement på den eksisterende entry (fjernes igen nedenfor), så publiceringen har identitet.
  INSERT INTO private.source_observation(occurrence_id,observation_kind,page_from,page_to,char_from,char_to,
    verbatim_text,quality_status,extraction_method,extraction_run_id)
    VALUES (v_occ,'header',10,10,p_char,p_char+4,substr(v_text,1,4),'clear','fixture',v_run) RETURNING id INTO v_hdr;
  INSERT INTO private.source_record_placement(id,source_record_id,scheme_entry_id,header_observation_id,initial_status)
    VALUES (v_rec,v_rec,(f->>'entry')::bigint,v_hdr,'accepted');
  INSERT INTO private.source_record_placement_decision(placement_id,version,decision_status,evidence,decision_origin,decided_by_name)
    VALUES (v_rec,1,'accepted','{"fixture":"6d1 midlertidig"}','migration','fixture');
  INSERT INTO private.source_persona_placement(id,source_persona_id,record_placement_id,placement_role,basis_observation_id,initial_status)
    VALUES (v_persona,v_persona,v_rec,'principal_member',v_help,'accepted');
  INSERT INTO private.source_persona_placement_decision(placement_id,version,decision_status,evidence,decision_origin,decided_by_name)
    VALUES (v_persona,1,'accepted','{"fixture":"6d1 midlertidig"}','migration','fixture');
END $$;

-- Narrativ som redaktør: upsert (draft) og publicering; app.change_set_id ryddes før hvert kald.
CREATE OR REPLACE FUNCTION pg_temp.c6d1_narrativ(p_person bigint,p_source bigint,p_key text) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE h text; r jsonb;
BEGIN
  h:=private.narrative_record_state(p_person,p_source,p_key,true)->>'state_sha256';
  SET LOCAL ROLE authenticated;
  PERFORM set_config('app.change_set_id','',true);
  r:=public.red_upsert_person_narrative_record(p_person,p_source,p_key,'Opdigtet biografi for '||p_key||'.',false,h);
  PERFORM set_config('app.change_set_id','',true);
  PERFORM public.red_publicer_person_narrative_record(p_person,p_source,p_key,r->>'state_sha256');
  PERFORM set_config('app.change_set_id','',true);
  RESET ROLE;
END $$;

CREATE OR REPLACE FUNCTION pg_temp.c6d1_revalider(p_person bigint,p_source bigint,p_key text) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE h text:=private.narrative_record_state(p_person,p_source,p_key,true)->>'state_sha256';
BEGIN
  SET LOCAL ROLE authenticated;
  PERFORM set_config('app.change_set_id','',true);
  PERFORM public.red_revalider_person_narrative_record(p_person,p_source,p_key,h);
  PERFORM set_config('app.change_set_id','',true);
  RESET ROLE;
END $$;

DO $c6d1$
DECLARE v_actor uuid:='a6d10000-0000-0000-0000-0000000006d1'; v_slaegt bigint; l_i bigint; l_ii bigint; l_vi bigint;
  k jsonb; s jsonb; v_scheme bigint; e_i bigint; e_ii bigint; e_vi bigint; q jsonb; v_obs uuid; v_rp uuid; v jsonb;
  v_rel bigint;
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  INSERT INTO public.slaegt(navn,sorteringsnavn,slug,status) VALUES ('6d1 fixture','6d1 fixture','f6d1','active')
    RETURNING id INTO v_slaegt;
  -- Modpartskilden -1611 med to linjer og deres schema.
  k:=pg_temp.f5b_source(-1611);
  INSERT INTO public.lineage(slaegt_id,source_id,kode,canonical_label,navn) VALUES (v_slaegt,-1611,'I','I. linje','6d1 linje I')
    RETURNING id INTO l_i;
  INSERT INTO public.lineage(slaegt_id,source_id,kode,canonical_label,navn) VALUES (v_slaegt,-1611,'II','II. linje','6d1 linje II')
    RETURNING id INTO l_ii;
  INSERT INTO public.lineage_scheme(slaegt_id,source_id,kind,label) VALUES (v_slaegt,-1611,'stamtavle','6d1 modpart')
    RETURNING id INTO v_scheme;
  INSERT INTO public.lineage_scheme_entry(scheme_id,slaegt_id,code,label,sort_order) VALUES (v_scheme,v_slaegt,'I','I. linje',1)
    RETURNING id INTO e_i;
  INSERT INTO public.lineage_scheme_entry(scheme_id,slaegt_id,code,label,sort_order) VALUES (v_scheme,v_slaegt,'II','II. linje',2)
    RETURNING id INTO e_ii;
  INSERT INTO public.lineage_scheme_entry_lineage(entry_id,lineage_id,slaegt_id,relation_kind)
    VALUES (e_i,l_i,v_slaegt,'canonical'),(e_ii,l_ii,v_slaegt,'canonical');
  k:=k||jsonb_build_object('source',-1611,'actor',v_actor,'entry',e_i);
  PERFORM private.write_header_evidence(-1611,(k->>'rend')::uuid,pg_temp.f150_run(),
    jsonb_build_array(pg_temp.f150_h('header_linje',500,'I DEN TESTSKE LINJE')));
  q:=pg_temp.f150_post(k,'k1',-161101,1,1);
  INSERT INTO private.source_persona_identity_event(source_persona_id,canonical_person_id,decision_status,version,evidence,
    decided_by,decided_by_name,decided_at)
  SELECT source_persona_id,canonical_person_id,decision_status,version,evidence,decided_by,decided_by_name,decided_at
    FROM private.source_persona_identity WHERE source_persona_id=(q->>'principal')::uuid;
  v_obs:=private.header_observation_uuid((k->>'rend')::uuid,'header-2018-20-v1',500);
  v_rp:=private.write_record_placement((q->>'record')::uuid,e_i,jsonb_build_object('printed_number','1'),v_obs,
    jsonb_build_object('rule_version','header-2018-20-v1','header_ids',jsonb_build_object('linje',v_obs)));
  PERFORM private.write_persona_placement((q->>'principal')::uuid,v_rp,(q->>'helpost')::uuid,'{"rule":"6d1 fixture"}');
  SET LOCAL ROLE authenticated;
  v:=public.red_preview_placement_memberships(-1611);
  PERFORM public.red_promote_placement_memberships(-1611,v->>'preview_sha256');
  RESET ROLE;
  PERFORM pg_temp.c6d1_narrativ(-161101,-1611,'k1');
  -- En modpartsperson uden placement: læseren viser legacy-koordinaterne (paritetstestens mål).
  INSERT INTO public.person(id) VALUES (-161102);
  INSERT INTO public.person_external_id(person_id,source_id,linje,nr,record_key) VALUES (-161102,-1611,'II',2,'k2');
  PERFORM private.record_legacy_disposition(-161101,-1611,'mapped',v_rp,'{"rule_version":"placement-membership-v1","fixture":"6d1"}');
  PERFORM private.record_legacy_disposition(-161102,-1611,'retained_legacy',NULL,'{"rule_version":"placement-membership-v1","fixture":"6d1"}');

  -- Kilden -1610: schema med den eksisterende entry VI og fire records.
  s:=pg_temp.f5b_source(-1610);
  INSERT INTO public.lineage(slaegt_id,source_id,kode,canonical_label,navn) VALUES (v_slaegt,-1610,'VI','VI. linje','6d1 linje VI')
    RETURNING id INTO l_vi;
  INSERT INTO public.lineage_scheme(slaegt_id,source_id,kind,label) VALUES (v_slaegt,-1610,'stamtavle','6d1 kilde')
    RETURNING id INTO v_scheme;
  INSERT INTO public.lineage_scheme_entry(scheme_id,slaegt_id,code,label,sort_order)
    VALUES (v_scheme,v_slaegt,'VI','VI. Den eksisterende Testlinje',1) RETURNING id INTO e_vi;
  INSERT INTO public.lineage_scheme_entry_lineage(entry_id,lineage_id,slaegt_id,relation_kind)
    VALUES (e_vi,l_vi,v_slaegt,'canonical');
  s:=s||jsonb_build_object('source',-1610,'actor',v_actor,'entry',e_vi);
  PERFORM pg_temp.c6d1_post(s,'p1',-161001,1000);
  PERFORM pg_temp.c6d1_post(s,'p2',-161002,2000);
  PERFORM pg_temp.c6d1_post(s,'p3',-161003,3000);
  PERFORM pg_temp.c6d1_post(s,'p4',-161004,4000);
  -- Kortposterne (runde 2): gruppekort g1-g3 (kuld II mangler i renditionen), strukturkort s1-s2 og en stammegruppe
  -- uden nyt romertal (u1). Ingen legacy-række og ingen biografi, så ledger- og publiceringstallene er uændrede.
  PERFORM pg_temp.c6d1_post(s,'g1',-161005,6000);
  PERFORM pg_temp.c6d1_post(s,'g2',-161006,7000);
  PERFORM pg_temp.c6d1_post(s,'g3',-161007,7500);
  PERFORM pg_temp.c6d1_post(s,'s1',-161008,8000);
  PERFORM pg_temp.c6d1_post(s,'s2',-161009,8500);
  PERFORM pg_temp.c6d1_post(s,'u1',-161010,9500);
  -- p2 har desuden en accepteret under-forekomst med sin egen rod-observation (`fact`) inde i helpostens tegnspænd,
  -- som 1939's fakta-, ægteskabs- og relationsforekomster (generalprøven 9/11: 228 records). Helposten er stadig
  -- forekomsten, hvis eneste top-observation har helpost-typen (private.record_helpost_status).
  WITH r AS (SELECT id FROM private.source_record WHERE source_id=-1610 AND record_key='p2'),
  o AS (INSERT INTO private.source_record_occurrence(rendition_id,occurrence_key,page_from,page_to,char_from,char_to,
          verbatim_text,physical_fingerprint,structural_fingerprint,extraction_run_id)
        VALUES ((s->>'rend')::uuid,'occ-p2-fakta',10,10,2022,2029,'f. 1600',repeat('5',64),repeat('6',64),(s->>'run')::uuid)
        RETURNING id),
  a AS (INSERT INTO private.source_record_anchor_event(occurrence_id,source_record_id,decision_status,evidence,version,decided_by,decided_by_name)
        SELECT o.id,r.id,'accepted','{"fixture":"6d1 underforekomst"}',1,v_actor,'fixture' FROM o,r RETURNING occurrence_id)
  INSERT INTO private.source_observation(occurrence_id,observation_kind,page_from,page_to,char_from,char_to,
    verbatim_text,quality_status,extraction_method,extraction_run_id)
  SELECT occurrence_id,'fact',10,10,2022,2029,'f. 1600','clear','fixture',(s->>'run')::uuid FROM a;
  INSERT INTO public.person_external_id(person_id,source_id,linje,nr,record_key)
    VALUES (-161001,-1610,'I',1,'p1'),(-161002,-1610,'I',1,'x-2'),(-161003,-1610,'II',1,'x-3'),(-161004,-1610,'II',3,NULL);
  PERFORM pg_temp.c6d1_narrativ(-161001,-1610,'p1');
  PERFORM pg_temp.c6d1_narrativ(-161002,-1610,'p2');
  PERFORM pg_temp.c6d1_narrativ(-161003,-1610,'p3');
  -- Fjern de midlertidige placements og header-observationer (kun syntetiske data) og revalidér publiceringerne.
  SET CONSTRAINTS ALL IMMEDIATE;
  SET CONSTRAINTS ALL DEFERRED;
  ALTER TABLE private.source_persona_placement_decision DISABLE TRIGGER USER;
  ALTER TABLE private.source_persona_placement DISABLE TRIGGER USER;
  ALTER TABLE private.source_record_placement_decision DISABLE TRIGGER USER;
  ALTER TABLE private.source_record_placement DISABLE TRIGGER USER;
  ALTER TABLE private.source_observation DISABLE TRIGGER USER;
  DELETE FROM private.source_persona_placement_decision d USING private.source_persona_placement pp, private.source_record r
   WHERE d.placement_id=pp.id AND r.id=pp.record_placement_id AND r.source_id=-1610;
  DELETE FROM private.source_persona_placement pp USING private.source_record r
   WHERE r.id=pp.record_placement_id AND r.source_id=-1610;
  DELETE FROM private.source_record_placement_decision d USING private.source_record r
   WHERE r.id=d.placement_id AND r.source_id=-1610;
  DELETE FROM private.source_record_placement rp USING private.source_record r
   WHERE r.id=rp.source_record_id AND r.source_id=-1610;
  DELETE FROM private.source_observation o USING private.extraction_run er
   WHERE o.extraction_run_id=er.id AND er.source_id=-1610 AND o.observation_kind='header';
  ALTER TABLE private.source_persona_placement_decision ENABLE TRIGGER USER;
  ALTER TABLE private.source_persona_placement ENABLE TRIGGER USER;
  ALTER TABLE private.source_record_placement_decision ENABLE TRIGGER USER;
  ALTER TABLE private.source_record_placement ENABLE TRIGGER USER;
  ALTER TABLE private.source_observation ENABLE TRIGGER USER;
  PERFORM pg_temp.c6d1_revalider(-161001,-1610,'p1');
  PERFORM pg_temp.c6d1_revalider(-161002,-1610,'p2');
  PERFORM pg_temp.c6d1_revalider(-161003,-1610,'p3');
  -- Modparten: -161001 er samme person som -161101 (afklaret).
  INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle)
    VALUES ('person',-161001,'person',-161101,'samme_som') RETURNING id INTO v_rel;
  INSERT INTO public.conclusion(target_type,target_id,status) VALUES ('relation',v_rel,'afklaret');
END $c6d1$;
COMMIT;
\echo CEREMONI6D1_FIXTURE_OK
