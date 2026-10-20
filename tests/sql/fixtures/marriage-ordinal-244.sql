-- #244: fixtures oven på relation-5b.sql og relation-2a.sql. Kaldes som ejer. Opdigtede navne.
-- En post med to ægteskaber. Påstand 1 springer en parentes over (som de 6 i 2018-20) og står derfor ikke ordret
-- i klausulen. Ægtefællepartens nummer gemmes som den gamle funktion gav det (1↔2 byttet); familierne er rigtige.
-- p_k1/p_raw1 styrer påstand 1 (ret_bog bruger »Gift 2° …« i begge, så vinduet findes, og bogen siger 2).
-- p_third: en tredje ægteskabspåstand (uden familie, forbliver proposed) til låsetesten.
-- Posten publiceres (kontrakt 2), så public_family_sources kan vise kilderne (test-family-sources.sql:14).
CREATE OR REPLACE FUNCTION pg_temp.f244_post(p_source bigint,p_src jsonb,p_key text,p_principal bigint,p_s1 bigint,p_s2 bigint,
  p_actor uuid,p_k1 text DEFAULT 'Gift 1° m. Bo Beta (søn af Ole Oma) f. 1800.',p_raw1 text DEFAULT 'Gift 1° m. Bo Beta f. 1800.',
  p_third boolean DEFAULT false) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE p jsonb; c1 jsonb; c2 jsonb; c3 jsonb; v1 uuid; v2 uuid; f1 bigint; f2 bigint; v_at timestamptz:=clock_timestamp();
  v_k2 text:='Gift 2° m. Cia Ceta.'; v_k3 text:='Gift 3° m. Dy Delta.'; v_text text; v_clauses text[];
BEGIN
  v_text:='Anna Alfa. '||p_k1||' '||v_k2||CASE WHEN p_third THEN ' '||v_k3 ELSE '' END;
  v_clauses:=ARRAY['Anna Alfa.',p_k1,v_k2]||CASE WHEN p_third THEN ARRAY[v_k3] ELSE '{}'::text[] END;
  p:=pg_temp.f5b_post(p_source,p_src,p_key,v_text,v_clauses,p_principal,p_actor);
  PERFORM pg_temp.f2a_event_for_state((p->>'principal')::uuid);
  PERFORM pg_temp.f2a_publish(p_source,p_src,p,p_principal,p_actor,v_text);
  c1:=pg_temp.f5b_claim(p_source,p_src,'relation.marriage',(p->'clauses'->>1)::uuid,p_raw1);
  c2:=pg_temp.f5b_claim(p_source,p_src,'relation.marriage',(p->'clauses'->>2)::uuid,v_k2);
  IF p_third THEN c3:=pg_temp.f5b_claim(p_source,p_src,'relation.marriage',(p->'clauses'->>3)::uuid,v_k3); END IF;
  v1:=pg_temp.f5b_spouse(p_source,p_src,p,c1,(p->'clauses'->>1)::uuid,'Bo Beta',2);   -- gammelt fejlnummer
  v2:=pg_temp.f5b_spouse(p_source,p_src,p,c2,(p->'clauses'->>2)::uuid,'Cia Ceta',1);
  INSERT INTO private.source_persona_identity_event(source_persona_id,canonical_person_id,decision_status,version,evidence,
    decided_by,decided_by_name,decided_at)
    VALUES (v1,p_s1,'accepted',1,'{"fixture":"244"}',p_actor,'fixture',v_at),(v2,p_s2,'accepted',1,'{"fixture":"244"}',p_actor,'fixture',v_at);
  INSERT INTO private.source_persona_identity(source_persona_id,canonical_person_id,decision_status,version,evidence,
    decided_by,decided_by_name,decided_at)
    VALUES (v1,p_s1,'accepted',1,'{"fixture":"244"}',p_actor,'fixture',v_at),(v2,p_s2,'accepted',1,'{"fixture":"244"}',p_actor,'fixture',v_at);
  f1:=pg_temp.f5b_family(p_principal,p_s1,1);
  f2:=pg_temp.f5b_family(p_principal,p_s2,2);
  RETURN jsonb_build_object('post',p,'c1',c1,'c2',c2,'c3',c3,'s1',v1,'s2',v2,'f1',f1,'f2',f2);
END $$;

-- Afgør kildens ægteskaber maskinelt (2a) og bind alle egnede (2b-i-vejen) som aktøren. Returnerer antal bindinger.
CREATE OR REPLACE FUNCTION pg_temp.f244_decide_and_bind(p_source bigint,p_actor uuid) RETURNS integer LANGUAGE plpgsql AS $$
DECLARE pv jsonb;
BEGIN
  PERFORM set_config('request.jwt.claim.sub',p_actor::text,true);
  SET LOCAL ROLE authenticated;
  pv:=red_preview_relation_decisions(p_source);
  PERFORM red_decide_relation_interpretations(p_source,pv->>'set_sha256');
  RESET ROLE;
  RETURN pg_temp.f244_bind(p_source,p_actor);
END $$;

-- Bind alle egnede accepterede relationer i kilden (preview → batch). Returnerer antal egnede (0 = intet at binde).
CREATE OR REPLACE FUNCTION pg_temp.f244_bind(p_source bigint,p_actor uuid) RETURNS integer LANGUAGE plpgsql AS $$
DECLARE v_all jsonb; v_pv jsonb; v_items jsonb;
BEGIN
  SELECT coalesce(jsonb_agg(jsonb_build_object('interpretation_id',ic.id::text,
           'family_id',(private.relation_binding_state(ic.id)#>>'{family,family_id}')::bigint) ORDER BY ic.id::text COLLATE "C"),'[]')
    INTO v_all FROM private.interpretation_current ic
   WHERE ic.source_id=p_source AND ic.status='accepted' AND private.relation_binding_state(ic.id) IS NOT NULL;
  IF jsonb_array_length(v_all)=0 THEN RETURN 0; END IF;   -- tom liste giver RELATION_PROMOTION_ITEMS_INVALID
  PERFORM set_config('request.jwt.claim.sub',p_actor::text,true);
  SET LOCAL ROLE authenticated;
  v_pv:=red_preview_relation_promotions(p_source,v_all);
  SELECT coalesce(jsonb_agg(jsonb_build_object('interpretation_id',i->>'interpretation_id','family_id',(i->>'family_id')::bigint)
           ORDER BY i->>'interpretation_id' COLLATE "C"),'[]')
    INTO v_items FROM jsonb_array_elements(v_pv->'items') i WHERE (i->>'eligible')::boolean;
  IF jsonb_array_length(v_items)=0 THEN RESET ROLE; RETURN 0; END IF;
  v_pv:=red_preview_relation_promotions(p_source,v_items);
  PERFORM red_promote_relation_interpretations_batch(p_source,v_items,v_pv->>'preview_sha256');
  RESET ROLE;
  RETURN jsonb_array_length(v_items);
END $$;
