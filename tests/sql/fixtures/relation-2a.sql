-- Trin 5b 2a: fixtures oven på relation-5b.sql. Kaldes som ejer.
-- Identitetsstate og -event skal være konsistente (deferred constraint-triggere identity_state_has_event /
-- identity_event_is_projected, schema.sql ~1822). Testene kører `SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;` efter
-- fixture-opbygningen, så en umulig tilstand fejler i testen og ikke skjules af ROLLBACK (Codex plan-r1 #5).

-- f5b_post skriver kun hovedpersonens state-række; denne helper skriver den matchende event (samme felter).
CREATE OR REPLACE FUNCTION pg_temp.f2a_event_for_state(p_persona uuid) RETURNS void LANGUAGE sql AS $$
  INSERT INTO private.source_persona_identity_event(source_persona_id,canonical_person_id,decision_status,version,evidence,
    decided_by,decided_by_name,decided_at)
  SELECT i.source_persona_id,i.canonical_person_id,i.decision_status,i.version,i.evidence,i.decided_by,i.decided_by_name,i.decided_at
    FROM private.source_persona_identity i
   WHERE i.source_persona_id=p_persona
     AND NOT EXISTS (SELECT 1 FROM private.source_persona_identity_event e
                      WHERE e.source_persona_id=i.source_persona_id AND e.version=i.version);
$$;

-- Et ægteskab: hovedpersonens post, en ægteskabspåstand med ægtefælle-persona og begge identiteter
-- accepteret, og en kanonisk familie med begge som partnere (ordinal p_famord, bogens nummer p_bookord).
CREATE OR REPLACE FUNCTION pg_temp.f2a_marriage(p_source bigint,p_src jsonb,p_key text,p_principal bigint,p_spouse bigint,
  p_actor uuid,p_bookord int DEFAULT 1,p_famord int DEFAULT 1,p_make_family boolean DEFAULT true) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE p jsonb; c jsonb; v_persona uuid; v_fam bigint; v_text text:='Anna Alfa. Gift med Bo Beta.';
  v_at timestamptz:=clock_timestamp();   -- ét tidsstempel: event og state skal være identiske
BEGIN
  p:=pg_temp.f5b_post(p_source,p_src,p_key,v_text,ARRAY['Anna Alfa.','Gift med Bo Beta.'],p_principal,p_actor);
  PERFORM pg_temp.f2a_event_for_state((p->>'principal')::uuid);
  c:=pg_temp.f5b_claim(p_source,p_src,'relation.marriage',(p->'clauses'->>1)::uuid,'Gift med Bo Beta.');
  v_persona:=pg_temp.f5b_spouse(p_source,p_src,p,c,(p->'clauses'->>1)::uuid,'Bo Beta',p_bookord);
  INSERT INTO private.source_persona_identity_event(source_persona_id,canonical_person_id,decision_status,version,evidence,
    decided_by,decided_by_name,decided_at)
    VALUES (v_persona,p_spouse,'accepted',1,'{"fixture":"2a"}',p_actor,'fixture',v_at);
  INSERT INTO private.source_persona_identity(source_persona_id,canonical_person_id,decision_status,version,evidence,
    decided_by,decided_by_name,decided_at)
    VALUES (v_persona,p_spouse,'accepted',1,'{"fixture":"2a"}',p_actor,'fixture',v_at);
  IF p_make_family THEN v_fam:=pg_temp.f5b_family(p_principal,p_spouse,p_famord); END IF;
  RETURN jsonb_build_object('post',p,'claim',c,'spouse_persona',v_persona,'family',v_fam);
END $$;

-- En accepteret forælderpåstand: barnets post, forælderens post, familien (forælder partner, barn barn),
-- påstanden afgjort som i del 1 (principal + parent-part, status accepted gennem red_decide_interpretation).
CREATE OR REPLACE FUNCTION pg_temp.f2a_parent(p_source bigint,p_src jsonb,p_child bigint,p_parent bigint,p_other bigint,p_actor uuid)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE pc jsonb; pp jsonb; c jsonb; v_fam bigint; v_new uuid;
BEGIN
  pp:=pg_temp.f5b_post(p_source,p_src,'PAR-'||p_parent,'Far Alfa.',ARRAY['Far Alfa.'],p_parent,p_actor);
  pc:=pg_temp.f5b_post(p_source,p_src,'BARN-'||p_child,'Barn Alfa. søn af Far.',ARRAY['Barn Alfa.','søn af Far.'],p_child,p_actor);
  PERFORM pg_temp.f2a_event_for_state((pp->>'principal')::uuid);
  PERFORM pg_temp.f2a_event_for_state((pc->>'principal')::uuid);
  v_fam:=pg_temp.f5b_family(p_parent,p_other,1);
  INSERT INTO family_member(family_id,person_id,rolle) VALUES (v_fam,p_child,'barn');
  c:=pg_temp.f5b_claim(p_source,p_src,'relation.parent',(pc->'clauses'->>1)::uuid,'søn af Far.');
  INSERT INTO private.interpretation_party(interpretation_key,party_role,version,source_persona_id,post_offset,origin,origin_ref)
    VALUES ((c->>'key')::uuid,'principal',1,(pc->>'principal')::uuid,11,'relation_persona',gen_random_uuid());
  PERFORM set_config('request.jwt.claim.sub',p_actor::text,true);
  SET LOCAL ROLE authenticated;
  PERFORM red_afgoer_relation_interpretation((c->>'key')::uuid,1,'same',v_fam,'fixture','{}');
  RESET ROLE;
  RETURN jsonb_build_object('child_post',pc,'parent_post',pp,'claim',c,'family',v_fam);
END $$;

-- Publicerer en post (kontrakt 2) gennem de rigtige redaktions-RPC'er. Afprøvet 2026-10-11 i en frisk
-- contract-2-base (ét kald): kræver accepteret record- og persona-placering (principal_member) med helposten
-- som grundlag. Flere kald i samme transaktion kræver nulstillingen af app.change_set_id nedenfor.
CREATE OR REPLACE FUNCTION pg_temp.f2a_publish(p_source bigint,p_src jsonb,p_post jsonb,p_person bigint,p_actor uuid,p_text text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_header uuid; v_rp uuid:=gen_random_uuid(); v_pp uuid:=gen_random_uuid(); h text; r jsonb;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.lineage_scheme WHERE id=p_source) THEN
    INSERT INTO public.slaegt(id,navn,sorteringsnavn,slug) VALUES (p_source,'2a slægt '||p_source,'2a slægt '||p_source,'2a-slaegt'||abs(p_source));
    INSERT INTO public.lineage_scheme(id,slaegt_id,source_id,kind,label) VALUES (p_source,p_source,p_source,'stamtavle','2a scheme');
    INSERT INTO public.lineage_scheme_entry(id,scheme_id,slaegt_id,code,label,sort_order) VALUES (p_source,p_source,p_source,'A','Linje A',1);
  END IF;
  INSERT INTO private.source_observation(occurrence_id,observation_kind,page_from,page_to,char_from,char_to,
    verbatim_text,quality_status,extraction_method,extraction_run_id)
    VALUES ((p_post->>'occ')::uuid,'header',10,10,1000,1004,substr(p_text,1,4),'clear','fixture',(p_src->>'run')::uuid) RETURNING id INTO v_header;
  INSERT INTO private.source_record_placement(id,source_record_id,scheme_entry_id,header_observation_id,initial_status)
    VALUES (v_rp,(p_post->>'record')::uuid,p_source,v_header,'accepted');
  INSERT INTO private.source_record_placement_decision(placement_id,version,decision_status,evidence,decision_origin,decided_by_name)
    VALUES (v_rp,1,'accepted','{"basis":"2a fixture"}','migration','fixture');
  INSERT INTO private.source_persona_placement(id,source_persona_id,record_placement_id,placement_role,basis_observation_id,initial_status)
    VALUES (v_pp,(p_post->>'principal')::uuid,v_rp,'principal_member',(p_post->>'helpost')::uuid,'accepted');
  INSERT INTO private.source_persona_placement_decision(placement_id,version,decision_status,evidence,decision_origin,decided_by_name)
    VALUES (v_pp,1,'accepted','{"basis":"2a fixture"}','migration','fixture');
  h:=private.narrative_record_state(p_person,p_source,p_post->>'key',true)->>'state_sha256';
  PERFORM set_config('request.jwt.claim.sub',p_actor::text,true);
  SET LOCAL ROLE authenticated;
  -- upsert og publicering er hver sin redaktionshandling; change_set-id'et er transaktionslokalt og
  -- bliver stående, så det nulstilles før og efter hver (ellers NARRATIVE_RECORD_FOREIGN_CHANGE_SET ved
  -- næste kald i samme transaktion; schema.sql ~13235, Opus plan-r2 B4).
  PERFORM set_config('app.change_set_id','',true);
  r:=public.red_upsert_person_narrative_record(p_person,p_source,p_post->>'key',p_text,false,h);
  PERFORM set_config('app.change_set_id','',true);
  PERFORM public.red_publicer_person_narrative_record(p_person,p_source,p_post->>'key',r->>'state_sha256');
  PERFORM set_config('app.change_set_id','',true);
  RESET ROLE;
END $$;
