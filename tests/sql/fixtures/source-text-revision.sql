-- Trin 6a, Task 5: fixtures til kildetekst-revisionen (source_text_revision). Bygger på fixtures/relation-5b.sql og
-- relation-2a.sql (indlæses først). Kald som ejer, før SET LOCAL ROLE. Alt er syntetisk.
--
-- t5_post: en 2018-20-lignende post 'Anna Alfa. Gift med Bo Beta.' i egen kilde p_base med
--   - et ægteskab (nøgle på klausul 2, ægtefælle-persona med mention på klausul 2), afgjort og bundet til familien;
--   - en dødspåstand på klausul 1, afgjort accepted og (hvis p_promote_death) bundet til en assertion;
--   - et ikke-afgjort forslag på klausul 1 (proposed, ingen binding);
--   - (hvis p_publish) en publiceret narrativ for posten. Placementens overskrift ligger i sin egen uankrede
--     forekomst før posten (sti ii), så helpost-reglen ser præcis én top-observation i postens forekomst.
-- Personer: p_base (hovedperson) og p_base-1 (ægtefælle).

-- Revisionsprofilen for fixture-kilden, samme form som seedet daa-2018-20-source-text-revision-v1.
CREATE OR REPLACE FUNCTION pg_temp.t5_profile(p_source bigint) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_cfg jsonb:='{"citation_label_template":"Synthetic side {page_from}","extractor_version":"source-text-revision-v1",
  "helpost_observation_kind":"person_post","observation_extraction_method":"clause_segment_v1","rendition_key":"fixture-r1",
  "rendition_kind":"pdf_text_layer","rendition_metadata":{"edition":"fixture"},"run_key_prefix":"reimport-source-text-revision:",
  "schema_version":"source-text-revision-manifest-v1","text_form":"folded_projection@page_header"}';
BEGIN
  INSERT INTO private.reimport_writer_profile(source_id,profile_id,profile_version,profile_sha256,writer_config)
    VALUES (p_source,'t5-source-text-revision','source-text-revision-v1',private.reimport_canonical_json_sha256(v_cfg),v_cfg)
    ON CONFLICT DO NOTHING;
  RETURN jsonb_build_object('profile_id','t5-source-text-revision','profile_sha256',private.reimport_canonical_json_sha256(v_cfg));
END $$;

CREATE OR REPLACE FUNCTION pg_temp.t5_publish(p_source bigint,p_src jsonb,p_post jsonb,p_person bigint,p_actor uuid,p_text text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_hocc uuid; v_header uuid; v_rp uuid:=gen_random_uuid(); v_pp uuid:=gen_random_uuid(); h text; r jsonb;
BEGIN
  INSERT INTO public.slaegt(id,navn,sorteringsnavn,slug) VALUES (p_source,'t5 slægt '||p_source,'t5 slægt '||p_source,'t5-slaegt'||abs(p_source));
  INSERT INTO public.lineage_scheme(id,slaegt_id,source_id,kind,label) VALUES (p_source,p_source,p_source,'stamtavle','t5 scheme');
  INSERT INTO public.lineage_scheme_entry(id,scheme_id,slaegt_id,code,label,sort_order) VALUES (p_source,p_source,p_source,'A','Linje A',1);
  INSERT INTO private.source_record_occurrence(rendition_id,occurrence_key,page_from,page_to,char_from,char_to,
    verbatim_text,physical_fingerprint,structural_fingerprint,extraction_run_id)
    VALUES ((p_src->>'rend')::uuid,'hdr-'||(p_post->>'key'),10,10,990,994,'LINJ',repeat('5',64),repeat('6',64),(p_src->>'run')::uuid)
    RETURNING id INTO v_hocc;
  INSERT INTO private.source_observation(occurrence_id,observation_kind,page_from,page_to,char_from,char_to,
    verbatim_text,quality_status,extraction_method,extraction_run_id)
    VALUES (v_hocc,'header_linje',10,10,990,994,'LINJ','clear','fixture',(p_src->>'run')::uuid) RETURNING id INTO v_header;
  INSERT INTO private.source_record_placement(id,source_record_id,scheme_entry_id,header_observation_id,initial_status)
    VALUES (v_rp,(p_post->>'record')::uuid,p_source,v_header,'accepted');
  INSERT INTO private.source_record_placement_decision(placement_id,version,decision_status,evidence,decision_origin,decided_by_name)
    VALUES (v_rp,1,'accepted','{"basis":"t5 fixture"}','migration','fixture');
  INSERT INTO private.source_persona_placement(id,source_persona_id,record_placement_id,placement_role,basis_observation_id,initial_status)
    VALUES (v_pp,(p_post->>'principal')::uuid,v_rp,'principal_member',(p_post->>'helpost')::uuid,'accepted');
  INSERT INTO private.source_persona_placement_decision(placement_id,version,decision_status,evidence,decision_origin,decided_by_name)
    VALUES (v_pp,1,'accepted','{"basis":"t5 fixture"}','migration','fixture');
  h:=private.narrative_record_state(p_person,p_source,p_post->>'key',true)->>'state_sha256';
  PERFORM set_config('request.jwt.claim.sub',p_actor::text,true);
  SET LOCAL ROLE authenticated;
  PERFORM set_config('app.change_set_id','',true);
  r:=public.red_upsert_person_narrative_record(p_person,p_source,p_post->>'key',p_text,false,h);
  PERFORM set_config('app.change_set_id','',true);
  PERFORM public.red_publicer_person_narrative_record(p_person,p_source,p_post->>'key',r->>'state_sha256');
  PERFORM set_config('app.change_set_id','',true);
  RESET ROLE;
END $$;

CREATE OR REPLACE FUNCTION pg_temp.t5_post(p_base bigint,p_actor uuid,p_publish boolean DEFAULT true,
  p_promote_death boolean DEFAULT true) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE s jsonb; m jsonb; pv jsonb; items jsonb; v_fact bigint; v_assert bigint; v_text text:='Anna Alfa. Gift med Bo Beta.';
  v_int uuid:=gen_random_uuid(); v_key uuid:=gen_random_uuid(); v_prom uuid; v_fprom uuid; c jsonb; prof jsonb;
BEGIN
  PERFORM pg_temp.f5b_actor(p_actor);
  INSERT INTO person(id,levende,privat,status) VALUES (p_base,false,false,'t5'),(p_base-1,false,false,'t5');
  s:=pg_temp.f5b_source(p_base);
  m:=pg_temp.f2a_marriage(p_base,s,'T5-'||abs(p_base),p_base,p_base-1,p_actor,1,1);
  IF p_publish THEN PERFORM pg_temp.t5_publish(p_base,s,m->'post',p_base,p_actor,v_text); END IF;
  -- ægteskabet: afgør og bind til familien
  PERFORM set_config('request.jwt.claim.sub',p_actor::text,true);
  SET LOCAL ROLE authenticated;
  pv:=red_preview_relation_decisions(p_base);
  PERFORM red_decide_relation_interpretations(p_base,pv->>'set_sha256');
  RESET ROLE;
  SELECT jsonb_agg(jsonb_build_object('interpretation_id',ic.id::text,'family_id',(m->>'family')::bigint)) INTO items
    FROM private.interpretation_current ic WHERE ic.interpretation_key=(m->'claim'->>'key')::uuid;
  SET LOCAL ROLE authenticated;
  pv:=red_preview_relation_promotions(p_base,items);
  PERFORM red_promote_relation_interpretations_batch(p_base,items,pv->>'preview_sha256');
  RESET ROLE;
  SELECT p.id INTO v_fprom FROM private.interpretation_promotion p JOIN private.interpretation q ON q.id=p.interpretation_id
   WHERE q.interpretation_key=(m->'claim'->>'key')::uuid AND p.target_type='family';
  -- død: accepted og evt. bundet til en assertion
  INSERT INTO fact(subjekt_type,subjekt_id,faktatype) VALUES ('person',p_base,'død') RETURNING id INTO v_fact;
  INSERT INTO assertion(target_type,target_id,date_raw,calendar,uforanderlig) VALUES ('fact',v_fact,'1850','gregoriansk',true)
    RETURNING id INTO v_assert;
  INSERT INTO conclusion(target_type,target_id,valgt_assertion_id,status) VALUES ('fact',v_fact,v_assert,'afklaret');
  INSERT INTO private.interpretation(id,interpretation_key,version,source_id,source_persona_id,interpretation_kind,
    predicate,value,schema_version,derivation_kind,confidence,status,method,extraction_run_id)
    VALUES (v_int,v_key,1,p_base,(m->'post'->>'principal')::uuid,'property','person.death',to_jsonb('1850'::text),'1.0',
      'source_statement',1,'proposed','fixture',(s->>'run')::uuid);
  INSERT INTO private.interpretation_observation(interpretation_id,observation_id,evidence_role,ordinal)
    VALUES (v_int,(m->'post'->'clauses'->>0)::uuid,'supporting',1);
  PERFORM set_config('app.change_set_id','',true);
  SET LOCAL ROLE authenticated;
  PERFORM public.red_decide_interpretation(v_int,1,'accepted','{"basis":"t5 fixture"}');
  RESET ROLE;
  SELECT ic.id INTO v_int FROM private.interpretation_current ic WHERE ic.interpretation_key=v_key;
  items:=jsonb_build_array(jsonb_build_object('interpretation_id',v_int::text,'target_type','assertion','target_id',v_assert));
  IF p_promote_death THEN
    SET LOCAL ROLE authenticated;
    pv:=public.red_preview_interpretation_promotions(items);
    PERFORM public.red_promote_interpretations_batch(items,pv->>'preview_hash');
    PERFORM set_config('app.change_set_id','',true);
    RESET ROLE;
    SELECT id INTO v_prom FROM private.interpretation_promotion WHERE interpretation_id=v_int AND target_type='assertion';
  END IF;
  -- et ikke-afgjort forslag
  c:=pg_temp.f5b_claim(p_base,s,'relation.marriage',(m->'post'->'clauses'->>0)::uuid,'Anna Alfa.');
  prof:=pg_temp.t5_profile(p_base);
  RETURN jsonb_build_object('source',p_base,'person',p_base,'spouse',p_base-1,'src',s,'post',m->'post',
    'record_key',m->'post'->>'key','helpost',m->'post'->>'helpost','text',v_text,'actor',p_actor,'profile',prof,
    'marriage_key',m->'claim'->>'key','family',m->>'family','family_promotion',v_fprom,'spouse_persona',m->>'spouse_persona',
    'death_key',v_key,'death_interpretation',v_int,'assertion',v_assert,'assertion_promotion',v_prom,
    'death_items',items,'proposed_key',c->>'key');
END $$;

-- Den forventede afhængigheds- og bindingsmængde målt nu (som manifestets preflight ville måle den).
CREATE OR REPLACE FUNCTION pg_temp.t5_expected(p_helpost uuid) RETURNS jsonb LANGUAGE sql AS $$
  WITH d AS (SELECT * FROM private.text_revision_dependents(p_helpost))
  SELECT jsonb_build_object(
    'keys',coalesce((SELECT jsonb_agg(d.interpretation_key::text ORDER BY d.interpretation_key) FROM d),'[]'::jsonb),
    'bindings',coalesce((SELECT jsonb_agg(jsonb_build_object('promotion_id',b.promotion_id::text,'target_type',b.target_type)
                                 ORDER BY b.promotion_id)
                           FROM private.text_revision_binding_set(ARRAY(SELECT d.interpretation_key FROM d)) b),'[]'::jsonb))
$$;

-- Klausuler for en ny tekst, skåret ved de givne delstrenge (i rækkefølge). Renditionsoffsets ligger inde i
-- helpostens spænd 1000..1000+len(basis) og er lige så lange som klausulen (monotone).
CREATE OR REPLACE FUNCTION pg_temp.t5_clauses(p_text text,p_parts text[]) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_pos int:=0; v_from int; v_out jsonb:='[]'; i int;
BEGIN
  FOR i IN 1..cardinality(p_parts) LOOP
    v_from:=strpos(substr(p_text,v_pos+1),p_parts[i])+v_pos-1;
    IF v_from<v_pos THEN RAISE EXCEPTION 'T5_CLAUSE_NOT_IN_TEXT %',i; END IF;
    v_out:=v_out||jsonb_build_array(jsonb_build_object('ordinal',i,'char_from',v_from,'char_to',v_from+char_length(p_parts[i]),
      'rendition_char_from',1000+v_from,'rendition_char_to',1000+v_from+char_length(p_parts[i]),'classification','record_text',
      'flags','[]'::jsonb,'verbatim_sha256',encode(extensions.digest(p_parts[i],'sha256'),'hex')));
    v_pos:=v_from+char_length(p_parts[i]);
  END LOOP;
  RETURN v_out;
END $$;

-- Revisionspayload for fixturen: basisteksten → p_new (klausuler p_parts) mod det aktuelle sæt; forventede mængder
-- målt nu, medmindre p_expected gives.
CREATE OR REPLACE FUNCTION pg_temp.t5_payload(fx jsonb,p_new text,p_parts text[],p_expected jsonb DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_help uuid:=(fx->>'helpost')::uuid; v_seq int; v_cur text; e jsonb;
BEGIN
  SELECT max(coalesce(clause_set_seq,1)) INTO v_seq FROM private.source_observation WHERE parent_observation_id=v_help;
  SELECT verbatim_text INTO v_cur FROM private.helpost_text_current(v_help);
  e:=coalesce(p_expected,pg_temp.t5_expected(v_help));
  RETURN jsonb_build_object('source_record_key',fx->>'record_key','rendition_content_sha256',repeat('2',64),
    'projection_rule','folded_projection@page_header',
    'before_text_sha256',encode(extensions.digest(v_cur,'sha256'),'hex'),
    'verbatim_text',p_new,'after_text_sha256',encode(extensions.digest(p_new,'sha256'),'hex'),
    'replaces_clause_set_seq',v_seq,'replaces_clause_set_sha256',private.clause_set_sha256(v_help,v_seq),
    'clause_rules_version','clause-rules-fixture-v1','segmenter_version','clause_segment.py@fixture',
    'ledger_sha256',repeat('d',64),'gap_charset',jsonb_build_array(' '),'clauses',pg_temp.t5_clauses(p_new,p_parts),
    'expected_superseded_keys',e->'keys','expected_binding_loss',e->'bindings');
END $$;

-- Hele kæden: autorisation (service_role) → preflight → begin → apply → finalize (authenticated redaktion).
-- p_apply_twice: apply samme element en gang til før finalize og returnér fejlen i 'second_apply_error'.
CREATE OR REPLACE FUNCTION pg_temp.t5_apply(fx jsonb,p_payload jsonb,p_nonce text,p_apply_twice boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_msha text:=encode(extensions.digest('t5:'||p_nonce,'sha256'),'hex'); v_psha text:=repeat('7',64);
  v_element text:='source-text-revision:'||(fx->>'record_key'); v_auth uuid; v_batch uuid; v_pre jsonb; v_res jsonb; v_fin jsonb;
  v_err text;
BEGIN
  PERFORM set_config('request.jwt.claim.sub',fx->>'actor',true);
  PERFORM set_config('role','service_role',true);
  v_auth:=public.red_authorize_reimport(v_msha,v_psha,
    jsonb_build_object('database_name',current_database(),'system_identifier',(pg_control_system()).system_identifier::text)::text,
    (fx->>'source')::bigint,fx->'profile'->>'profile_id',fx->'profile'->>'profile_sha256',
    '{"person_creates":0,"source_evidence":0,"source_text_revision":1}'::jsonb,jsonb_build_object(v_element,p_payload),
    gen_random_uuid(),clock_timestamp()+interval '5 minutes');
  PERFORM set_config('role','authenticated',true);
  v_pre:=public.red_preflight_reimport_authorization(v_auth,v_msha,v_psha);
  v_batch:=public.red_begin_reimport(v_auth,v_msha,v_psha);
  v_res:=public.red_apply_reimport_source_text_revision(v_batch,v_element,p_payload);
  IF p_apply_twice THEN
    BEGIN
      PERFORM public.red_apply_reimport_source_text_revision(v_batch,v_element,p_payload);
      v_err:='ingen fejl';
    EXCEPTION WHEN OTHERS THEN v_err:=SQLERRM;
    END;
  END IF;
  v_fin:=public.red_finalize_reimport(v_batch);
  RESET role;
  RETURN v_res||jsonb_build_object('batch_id',v_batch,'authorization_id',v_auth,'preflight',v_pre,'finalize',v_fin,
    'second_apply_error',v_err);
END $$;

-- t5_child_post (Codex I1, rækkefølge 5 i concurrency-testen): en accepteret relation.parent på barnets post
-- 'Barn Alfa. søn af Far.' (klausul 2), bundet til forældrefamilien (forælder p_base-1 partner, barn p_base). Bagefter
-- fjernes barnets barn-række, så bindingen er p.t. ugyldig: relation_binding_state kræver barnet som barn i præcis én
-- familie med forælderen som partner. red_tilfoej_barn genindsætter den samme række (ordinal og konfidens NULL), så
-- bindingens tilstand og hash bliver gyldige igen. Revisionen gælder barnets post. Personer: p_base (barn),
-- p_base-1 (forælder) og p_base-2 (anden partner).
CREATE OR REPLACE FUNCTION pg_temp.t5_child_post(p_base bigint,p_actor uuid) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE s jsonb; par jsonb; items jsonb; pv jsonb; v_int uuid; v_prom uuid; prof jsonb;
BEGIN
  PERFORM pg_temp.f5b_actor(p_actor);
  INSERT INTO person(id,levende,privat,status) VALUES (p_base,false,false,'t5'),(p_base-1,false,false,'t5'),(p_base-2,false,false,'t5');
  s:=pg_temp.f5b_source(p_base);
  par:=pg_temp.f2a_parent(p_base,s,p_base,p_base-1,p_base-2,p_actor);
  SELECT ic.id INTO v_int FROM private.interpretation_current ic WHERE ic.interpretation_key=(par->'claim'->>'key')::uuid;
  items:=jsonb_build_array(jsonb_build_object('interpretation_id',v_int::text,'family_id',(par->>'family')::bigint));
  PERFORM set_config('request.jwt.claim.sub',p_actor::text,true);
  SET LOCAL ROLE authenticated;
  pv:=red_preview_relation_promotions(p_base,items);
  PERFORM red_promote_relation_interpretations_batch(p_base,items,pv->>'preview_sha256');
  RESET ROLE;
  SELECT p.id INTO v_prom FROM private.interpretation_promotion p
   WHERE p.interpretation_id=v_int AND p.target_type='family';
  IF v_prom IS NULL THEN RAISE EXCEPTION 'T5_CHILD_POST_NOT_PROMOTED'; END IF;
  PERFORM set_config('app.change_set_id','',true);
  DELETE FROM family_member WHERE family_id=(par->>'family')::bigint AND person_id=p_base AND rolle='barn';
  prof:=pg_temp.t5_profile(p_base);
  RETURN jsonb_build_object('source',p_base,'child',p_base,'parent',p_base-1,'src',s,'post',par->'child_post',
    'record_key',par->'child_post'->>'key','helpost',par->'child_post'->>'helpost','text','Barn Alfa. søn af Far.',
    'actor',p_actor,'profile',prof,'parent_key',par->'claim'->>'key','parent_interpretation',v_int,
    'family',par->>'family','family_promotion',v_prom);
END $$;
