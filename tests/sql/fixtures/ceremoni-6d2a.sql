-- Trin 6d-2a Task 6: syntetisk mini-kilde til identitets-ceremonien (tests/sql/test-identitet-ceremoni.sh). Data
-- COMMIT'es, fordi identitet_ceremoni.sql kører sin egen transaktion. Opdigtede personer med negative id'er; aktør
-- a150…150 (redaktion). Kontrakt v1 (som CI's friske schema). Kilden -620100 har:
--   -620101 (K1's objekt) og -620102/-620103 (kandidater for kort K2/K3): hovedpersoner med accepteret kilde-persona,
--     gældende linjemedlemskab og en narrativ hver (side 517/518/519).
--   -620104 (kandidat for K4): person med narrativ, uden persona.
--   -620105 (K1's alias): oversigtsperson med narrativ (side 504), ikke staged; -620106: person med kontekstnarrativ
--     (side 503); -620107: reserve til `A`-svar (person uden narrativ).
--   Tre identitetspersonaer U-2 (identitet unresolved, version 2), U-3 og U-4 (ingen identitetsrække) med hver deres
--   post og primary-mention (oversigtsteksten). Ingen record-placements for dem (som 1939).
\set ON_ERROR_STOP on
BEGIN;
\ir relation-5b.sql
\ir placement-150.sql

-- Kilde med header-kørsel. Uden p_lineage får kilden egen slægt og linje (f150_source); med p_lineage får den et
-- stamtavle-schema, hvis entry 'I' er canonical for den givne linje (en anden udgave af samme slægt).
CREATE OR REPLACE FUNCTION pg_temp.f6d_src(p_source bigint,p_lineage bigint DEFAULT NULL) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_actor uuid:='a1500000-0000-0000-0000-000000000150'; f jsonb; v_slaegt bigint; v_scheme bigint; v_entry bigint;
BEGIN
  IF p_lineage IS NULL THEN
    f:=pg_temp.f150_source(p_source);
  ELSE
    PERFORM pg_temp.f5b_actor(v_actor);
    f:=pg_temp.f5b_source(p_source);
    SELECT slaegt_id INTO v_slaegt FROM public.lineage WHERE id=p_lineage;
    INSERT INTO public.lineage_scheme(slaegt_id,source_id,kind,label) VALUES (v_slaegt,p_source,'stamtavle','6d fixture')
      RETURNING id INTO v_scheme;
    INSERT INTO public.lineage_scheme_entry(scheme_id,slaegt_id,code,label,sort_order)
      VALUES (v_scheme,v_slaegt,'I','I. linje',1) RETURNING id INTO v_entry;
    INSERT INTO public.lineage_scheme_entry_lineage(entry_id,lineage_id,slaegt_id,relation_kind)
      VALUES (v_entry,p_lineage,v_slaegt,'canonical');
    f:=f||jsonb_build_object('source',p_source,'slaegt',v_slaegt,'lineage',p_lineage,'entry',v_entry,'actor',v_actor);
  END IF;
  PERFORM private.write_header_evidence(p_source,(f->>'rend')::uuid,pg_temp.f150_run(),
    jsonb_build_array(pg_temp.f150_h('header_linje',500,'I DEN TESTSKE LINJE')));
  RETURN f;
END $$;

-- Hovedperson-post med accepteret record- og persona-placement på kildens entry 'I'. Returnerer personaen.
CREATE OR REPLACE FUNCTION pg_temp.f6d_place(f jsonb,p_key text,p_person bigint,p_nr int) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE p jsonb; v_obs uuid; v_rp uuid;
BEGIN
  p:=pg_temp.f150_post(f,p_key,p_person,p_nr,1);
  v_obs:=private.header_observation_uuid((f->>'rend')::uuid,'header-2018-20-v1',500);
  v_rp:=private.write_record_placement((p->>'record')::uuid,(f->>'entry')::bigint,
    jsonb_build_object('printed_number',p_nr::text),v_obs,
    jsonb_build_object('rule_version','header-2018-20-v1','header_ids',jsonb_build_object('linje',v_obs)));
  PERFORM private.write_persona_placement((p->>'principal')::uuid,v_rp,(p->>'helpost')::uuid,'{"rule":"test"}');
  RETURN (p->>'principal')::uuid;
END $$;

-- Fremmer kildens egnede items som redaktør (som red_preview/red_promote i test-placement-membership.sql).
CREATE OR REPLACE FUNCTION pg_temp.f6d_promote(f jsonb) RETURNS integer LANGUAGE plpgsql AS $$
DECLARE v jsonb; v_n int;
BEGIN
  PERFORM set_config('request.jwt.claim.sub',f->>'actor',true);
  SET LOCAL ROLE authenticated;
  v:=public.red_preview_placement_memberships((f->>'source')::bigint);
  v_n:=public.red_promote_placement_memberships((f->>'source')::bigint,v->>'preview_sha256');
  RESET ROLE;
  RETURN v_n;
END $$;

CREATE OR REPLACE FUNCTION pg_temp.c6d2_narr(p_person bigint,p_source bigint,p_side text,p_tekst text) RETURNS void
LANGUAGE sql AS $$
  INSERT INTO public.narrative(subjekt_type,subjekt_id,source_id,tekst,side) VALUES ('person',p_person,p_source,p_tekst,p_side);
$$;

DO $fix$
DECLARE f jsonb:=pg_temp.f6d_src(-620100); v_src bigint:=-620100; v_actor uuid:='a1500000-0000-0000-0000-000000000150';
  v_post jsonb; k text; v_p uuid;
BEGIN
  PERFORM pg_temp.f6d_place(f,'I-1',-620101,1);
  PERFORM pg_temp.f6d_place(f,'I-2',-620102,2);
  PERFORM pg_temp.f6d_place(f,'I-3',-620103,3);
  IF pg_temp.f6d_promote(f)<3 THEN RAISE EXCEPTION 'CEREMONI_6D2A_FIXTURE: promotion'; END IF;
  -- f5b_post skriver kun identitetsrækken; til COMMIT skal hændelsen med (som ceremoni-6d1.sql).
  INSERT INTO private.source_persona_identity_event(source_persona_id,canonical_person_id,decision_status,version,evidence,
    decided_by,decided_by_name,decided_at)
  SELECT i.source_persona_id,i.canonical_person_id,i.decision_status,i.version,i.evidence,i.decided_by,i.decided_by_name,i.decided_at
    FROM private.source_persona_identity i JOIN private.source_persona sp ON sp.id=i.source_persona_id WHERE sp.source_id=v_src;
  INSERT INTO public.person(id) VALUES (-620104),(-620105),(-620106),(-620107) ON CONFLICT DO NOTHING;
  UPDATE public.person SET levende=false WHERE id BETWEEN -620107 AND -620101;
  PERFORM pg_temp.c6d2_narr(-620101,v_src,'517','Opdigtet narrativ om K1-objektet.');
  PERFORM pg_temp.c6d2_narr(-620102,v_src,'518','Opdigtet narrativ om K2-kandidaten.');
  PERFORM pg_temp.c6d2_narr(-620103,v_src,'519','Opdigtet narrativ om K3-kandidaten.');
  PERFORM pg_temp.c6d2_narr(-620104,v_src,'520','Opdigtet narrativ om K4-kandidaten.');
  PERFORM pg_temp.c6d2_narr(-620105,v_src,'504','Opdigtet oversigtsomtale af K1-aliaset.');
  PERFORM pg_temp.c6d2_narr(-620106,v_src,'503','Opdigtet kontekst til oversigtsomtalen.');
  FOREACH k IN ARRAY ARRAY['U-2','U-3','U-4'] LOOP
    v_post:=pg_temp.f5b_post(v_src,f,k,'Opdigtet oversigtspost '||k||'.',ARRAY['Opdigtet oversigtspost '||k],NULL,v_actor);
  END LOOP;
  -- U-2: identitet unresolved, version 2 (to hændelser, som en tidligere afgørelse ville have skrevet).
  SELECT id INTO v_p FROM private.source_persona WHERE source_id=v_src AND persona_key='U-2';
  INSERT INTO private.source_persona_identity_event(source_persona_id,canonical_person_id,decision_status,version,evidence,
    decided_by,decided_by_name,decided_at)
    VALUES (v_p,NULL,'unresolved',1,'{"fixture":"6d2a"}',v_actor,'fixture',now()),
           (v_p,NULL,'unresolved',2,'{"fixture":"6d2a"}',v_actor,'fixture',now());
  INSERT INTO private.source_persona_identity(source_persona_id,canonical_person_id,decision_status,version,evidence,
    decided_by,decided_by_name,decided_at)
    VALUES (v_p,NULL,'unresolved',2,'{"fixture":"6d2a"}',v_actor,'fixture',now());
END $fix$;
COMMIT;
