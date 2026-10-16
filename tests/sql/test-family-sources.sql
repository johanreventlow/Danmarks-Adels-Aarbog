-- Trin 5b 2a, Task 5: public_family_sources (kontrakt 2). Kører i writer-1939-v50-db.
\set ON_ERROR_STOP on
BEGIN;
\ir fixtures/relation-5b.sql
\ir fixtures/relation-2a.sql

-- Ét bundet og publiceret ægteskab i egen kilde p_base: personer p_base (hovedperson) og p_base-1 (ægtefælle).
CREATE OR REPLACE FUNCTION pg_temp.f2a_bound(p_base bigint,p_actor uuid) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE s jsonb; m jsonb; pv jsonb; items jsonb;
BEGIN
  INSERT INTO person(id,levende,privat,status) VALUES (p_base,false,false,'2a'),(p_base-1,false,false,'2a');
  s:=pg_temp.f5b_source(p_base);
  m:=pg_temp.f2a_marriage(p_base,s,'B'||p_base,p_base,p_base-1,p_actor,1,1);
  PERFORM pg_temp.f2a_publish(p_base,s,m->'post',p_base,p_actor,'Anna Alfa. Gift med Bo Beta.');
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
  RETURN m||jsonb_build_object('source',s);
END $$;

-- Antal synlige rækker for familien som anon.
CREATE OR REPLACE FUNCTION pg_temp.f2a_visible(p_fam bigint) RETURNS integer LANGUAGE plpgsql AS $$
DECLARE n integer;
BEGIN
  SET LOCAL ROLE anon;
  SELECT count(*) INTO n FROM public.public_family_sources(ARRAY[p_fam]);
  RESET ROLE;
  RETURN n;
END $$;

DO $family_sources$
DECLARE v_actor uuid:='11000000-0000-0000-0000-0000002a0501'; m jsonb; par jsonb; pv jsonb; items jsonb; n int; r record;
  v_fam bigint; v_pfam bigint; v_par2 jsonb; v_v2 uuid; v_sha text; v_ref uuid;
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);

  -- (1) lykkelig sti: ægteskab + forælder
  m:=pg_temp.f2a_bound(-2502,v_actor);
  v_fam:=(m->>'family')::bigint;
  INSERT INTO person(id,levende,privat,status) VALUES (-2506,false,false,'2a'),(-2507,false,false,'2a'),(-2508,false,false,'2a');
  par:=pg_temp.f2a_parent(-2502,m->'source',-2506,-2507,-2508,v_actor);
  PERFORM pg_temp.f2a_publish(-2502,m->'source',par->'child_post',-2506,v_actor,'Barn Alfa. søn af Far.');
  v_pfam:=(par->>'family')::bigint;
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  SELECT jsonb_agg(jsonb_build_object('interpretation_id',ic.id::text,'family_id',v_pfam)) INTO items
    FROM private.interpretation_current ic WHERE ic.interpretation_key=(par->'claim'->>'key')::uuid;
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  SET LOCAL ROLE authenticated;
  pv:=red_preview_relation_promotions(-2502,items);
  PERFORM red_promote_relation_interpretations_batch(-2502,items,pv->>'preview_sha256');
  RESET ROLE;
  SELECT public_ref INTO v_ref FROM private.source_record WHERE id=(m->'post'->>'record')::uuid;
  SET LOCAL ROLE anon;
  SELECT count(*) INTO n FROM public.public_family_sources(ARRAY[v_fam,v_pfam]);
  IF n<>2 THEN RAISE EXCEPTION 'FAMILY_SOURCES_TEST_FAILED: % rækker', n; END IF;
  SELECT * INTO r FROM public.public_family_sources(ARRAY[v_fam]);
  -- r2-M1: fødselsfamilien har to forældre (-2507, -2508), men kun påstanden om -2507 er bundet ⇒ præcis én række
  IF r.slags<>'aegteskab' OR r.source_record_ref IS DISTINCT FROM v_ref OR v_ref IS NULL
     OR nullif(r.record_label,'') IS NULL OR nullif(r.source_label,'') IS NULL OR r.counterpart_person_id<>-2503
     OR (SELECT count(*) FROM public.public_family_sources(ARRAY[v_pfam]))<>1
     OR (SELECT slags FROM public.public_family_sources(ARRAY[v_pfam]))<>'foraelder'
     OR (SELECT counterpart_person_id FROM public.public_family_sources(ARRAY[v_pfam]))<>-2507 THEN
    RAISE EXCEPTION 'FAMILY_SOURCES_TEST_FAILED: lykkelig sti';
  END IF;
  RESET ROLE;

  -- (2) kontrakt 1 (Codex plan-r1 #13): samme gyldige binding, kontrakten midlertidigt 1 ⇒ 0 rækker
  CREATE OR REPLACE FUNCTION public.narrative_record_contract_version() RETURNS integer
    LANGUAGE sql STABLE SECURITY INVOKER SET search_path=pg_catalog AS $c$ SELECT 1 $c$;
  IF pg_temp.f2a_visible(v_fam)<>0 THEN RAISE EXCEPTION 'FAMILY_SOURCES_TEST_FAILED: kontrakt 1'; END IF;
  CREATE OR REPLACE FUNCTION public.narrative_record_contract_version() RETURNS integer
    LANGUAGE sql STABLE SECURITY INVOKER SET search_path=pg_catalog AS $c$ SELECT 2 $c$;
  IF pg_temp.f2a_visible(v_fam)<>1 THEN RAISE EXCEPTION 'FAMILY_SOURCES_TEST_FAILED: kontrakt 2 tilbage'; END IF;

  -- (3) levende barn i familien
  m:=pg_temp.f2a_bound(-2512,v_actor); SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  IF pg_temp.f2a_visible((m->>'family')::bigint)<>1 THEN RAISE EXCEPTION 'FAMILY_SOURCES_TEST_FAILED: (3) ikke synlig før'; END IF;
  INSERT INTO person(id,levende,privat,status) VALUES (-2519,true,false,'2a');
  INSERT INTO family_member(family_id,person_id,rolle) VALUES ((m->>'family')::bigint,-2519,'barn');
  IF pg_temp.f2a_visible((m->>'family')::bigint)<>0 THEN RAISE EXCEPTION 'FAMILY_SOURCES_TEST_FAILED: levende barn'; END IF;

  -- (4) staged ægtefælle
  m:=pg_temp.f2a_bound(-2522,v_actor); SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  IF pg_temp.f2a_visible((m->>'family')::bigint)<>1 THEN RAISE EXCEPTION 'FAMILY_SOURCES_TEST_FAILED: (4) ikke synlig før'; END IF;
  UPDATE person SET staged=true WHERE id=-2523;   -- ægtefællen = p_base-1
  IF pg_temp.f2a_visible((m->>'family')::bigint)<>0 THEN RAISE EXCEPTION 'FAMILY_SOURCES_TEST_FAILED: staged'; END IF;

  -- (5) ny identitetsversion gennem identitetswriteren (samme person, version 2)
  m:=pg_temp.f2a_bound(-2532,v_actor); SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  IF pg_temp.f2a_visible((m->>'family')::bigint)<>1 THEN RAISE EXCEPTION 'FAMILY_SOURCES_TEST_FAILED: (5) ikke synlig før'; END IF;
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  PERFORM private.decide_source_persona_identity((m->>'spouse_persona')::uuid,-2533,1,'accepted',
    '{"basis":"web_detail","note":"2a ny version"}','human');
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  IF pg_temp.f2a_visible((m->>'family')::bigint)<>0 THEN RAISE EXCEPTION 'FAMILY_SOURCES_TEST_FAILED: ny identitetsversion'; END IF;

  -- (6) upubliceret post (tilbagetrukket gennem redaktions-RPC'en)
  m:=pg_temp.f2a_bound(-2542,v_actor); SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  IF pg_temp.f2a_visible((m->>'family')::bigint)<>1 THEN RAISE EXCEPTION 'FAMILY_SOURCES_TEST_FAILED: (6) ikke synlig før'; END IF;
  v_sha:=private.narrative_record_state(-2542,-2542,m->'post'->>'key',true)->>'state_sha256';
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  SET LOCAL ROLE authenticated;
  PERFORM set_config('app.change_set_id','',true);
  PERFORM public.red_tilbagetraek_person_narrative_record(-2542,-2542,m->'post'->>'key',v_sha);
  RESET ROLE;
  IF pg_temp.f2a_visible((m->>'family')::bigint)<>0 THEN RAISE EXCEPTION 'FAMILY_SOURCES_TEST_FAILED: upubliceret'; END IF;

  -- (7) afvist påstand: ingen writer laver en ny version af en accepteret påstand i dag, så den skrives som ejer
  -- (version 2, samme nøgle, med sin supporting-observation); afviser triggerne en direkte 'rejected'-version,
  -- skrives version 2 som 'proposed' og afgøres 'rejected' gennem red_decide_interpretation.
  m:=pg_temp.f2a_bound(-2552,v_actor); SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  IF pg_temp.f2a_visible((m->>'family')::bigint)<>1 THEN RAISE EXCEPTION 'FAMILY_SOURCES_TEST_FAILED: (7) ikke synlig før'; END IF;
  v_v2:=gen_random_uuid();
  INSERT INTO private.interpretation(id,interpretation_key,version,supersedes_id,source_id,source_persona_id,interpretation_kind,predicate,
    value,schema_version,derivation_kind,confidence,status,method,extraction_run_id)
  SELECT v_v2,ic.interpretation_key,ic.version+1,ic.id,ic.source_id,ic.source_persona_id,ic.interpretation_kind,ic.predicate,
         ic.value,ic.schema_version,ic.derivation_kind,ic.confidence,'proposed',ic.method,ic.extraction_run_id
    FROM private.interpretation_current ic WHERE ic.interpretation_key=(m->'claim'->>'key')::uuid;
  INSERT INTO private.interpretation_observation(interpretation_id,observation_id,evidence_role,ordinal)
    SELECT v_v2,io.observation_id,io.evidence_role,io.ordinal FROM private.interpretation_observation io
     WHERE io.interpretation_id=(m->'claim'->>'id')::uuid;
  SELECT version INTO n FROM private.interpretation WHERE id=v_v2;
  SET LOCAL ROLE authenticated;
  PERFORM red_decide_interpretation(v_v2,n,'rejected','{"note":"2a afvist"}');
  RESET ROLE;
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  IF pg_temp.f2a_visible((m->>'family')::bigint)<>0 THEN RAISE EXCEPTION 'FAMILY_SOURCES_TEST_FAILED: afvist påstand'; END IF;

  -- (8) to supporting-observationer på den bundne version ⇒ 0 (r2-M6)
  m:=pg_temp.f2a_bound(-2562,v_actor); SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  IF pg_temp.f2a_visible((m->>'family')::bigint)<>1 THEN RAISE EXCEPTION 'FAMILY_SOURCES_TEST_FAILED: (8) ikke synlig før'; END IF;
  INSERT INTO private.interpretation_observation(interpretation_id,observation_id,evidence_role,ordinal)
    SELECT ic.id,(m->'post'->'clauses'->>0)::uuid,'supporting',2
      FROM private.interpretation_current ic WHERE ic.interpretation_key=(m->'claim'->>'key')::uuid;
  IF pg_temp.f2a_visible((m->>'family')::bigint)<>0 THEN RAISE EXCEPTION 'FAMILY_SOURCES_TEST_FAILED: to observationer'; END IF;

  -- (9) narrativet markeret privat: kun publiceringsgaten (person_daa_narrative_publication_allowed) fanger det;
  -- bindingen, posten og familien er ellers uændrede (mutationsbevis for den gate)
  m:=pg_temp.f2a_bound(-2572,v_actor); SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  IF pg_temp.f2a_visible((m->>'family')::bigint)<>1 THEN RAISE EXCEPTION 'FAMILY_SOURCES_TEST_FAILED: (9) ikke synlig før'; END IF;
  UPDATE public.narrative SET privat=true
   WHERE id=(SELECT narrative_id FROM private.narrative_record_publication
              WHERE source_record_id=(m->'post'->>'record')::uuid AND status='published');
  IF NOT FOUND THEN RAISE EXCEPTION 'FAMILY_SOURCES_TEST_FAILED: (9) intet narrativ'; END IF;
  IF pg_temp.f2a_visible((m->>'family')::bigint)<>0 THEN RAISE EXCEPTION 'FAMILY_SOURCES_TEST_FAILED: privat narrativ'; END IF;

  RAISE NOTICE 'OK: public_family_sources og gaten';
END $family_sources$;
ROLLBACK;
