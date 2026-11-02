-- Trin 6c-2 Task 5 (spec §4.2, fallback c): »forkert person« rører hverken narrativ eller fakta. Der er ingen
-- flytte-RPC; en 1939-persona, hvis publicerede post står på den forkerte person X, sættes uafklaret med den
-- EKSISTERENDE red_afgoer_source_persona(…,'unresolved',NULL,…). Testen beviser, at det kun skifter identiteten
-- (version + 1, ny hændelse) og intet andet: narrativ-publikationen er stadig published på X,
-- narrative_record_state(X) er uændret og ikke blokeret, public_person_facts(ARRAY[X]) giver præcis de samme rækker,
-- og klassifikationen (interpretation_control_classification.sql) giver forslaget NO_IDENTITY.
--
-- p_context-KRAV TIL TASK 7 (red_afgoer_source_persona, schema.sql ~10623):
--   * tilladte nøgler er KUN basis, candidate_id, run_id, sheet_sha256, rows_sha256, line, control_run_id,
--     display_position, display_positions, deceased. En nøgle som "ønsket_person_id" afvises med
--     EVIDENCE_IDENTITY_DECISION_INVALID (afprøvet nedenfor). Y (den rette person) kan derfor IKKE ligge i
--     konteksten; den må stå i p_note (som bevares i evidensen).
--   * p_note er påkrævet (ikke tom efter btrim).
--   * for et kortark: {"basis":"human_sheet","sheet_sha256":<64 hex>,"rows_sha256":<64 hex>,"line":<heltal >= 1>};
--     uden basis er standarden web_detail, som ikke kræver andre felter.
--   * p_canonical_person_id SKAL være NULL for unresolved; p_expected_version = personaens aktuelle version.
--   * ingen stikprøvekontekst (control_run_id/display_position(s)) og ingen candidate_id/run_id for en persona, der
--     ikke er i en forseglet kontrolkørsel; ellers IDENTITY_CONTROL_SAMPLE_CONTEXT_INVALID.
--   * personaen må ikke vente på publiceringskontrol (IDENTITY_AWAITING_PUBLICATION_CONTROL), dvs. dens
--     publication_identity-ceremoni C skal være finaliseret, før en kortafgørelse er mulig.
-- AFGRÆNSNING: public_person_facts(ARRAY[X]) forbliver uændret, fordi X's bundne fakta bæres af en ANDEN kilde/persona
-- (verden 1, som 2018-20). Et faktum, der er bundet gennem selve den forkerte persona (dens fortolkning, krav om
-- accepteret identitet), ville miste sin binding, når identiteten bliver unresolved; det er tilsigtet.
-- KONTRAST: en persona MED accepteret placering gør narrativets publiceringsstatus stale_published, når den sættes
-- unresolved. 1939 har ingen placeringer, så det rammer ikke 6c-2, men trin 6d skal vide det (afprøvet i fixturen).
-- Kører i writer-1939-jobbet (kontrakt v2; public_person_facts er tom under v1). Alt syntetisk; én transaktion,
-- rulles tilbage. Fixturerne er de delte fra test-person-facts.sql.
\set ON_ERROR_STOP on
BEGIN;
\ir fixtures/relation-5b.sql
\ir fixtures/relation-2a.sql
\ir fixtures/person-facts.sql

CREATE TEMP TABLE t5(k text PRIMARY KEY, v jsonb);

-- Et fingeraftryk af den lukkede række-mængde, som afgørelsen ikke må røre.
CREATE FUNCTION pg_temp.t5_untouched() RETURNS jsonb LANGUAGE plpgsql AS $$
BEGIN
  RETURN jsonb_build_object(
    'narrative',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.id),'[]') FROM public.narrative x),
    'publication',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.id),'[]') FROM private.narrative_record_publication x),
    'publication_event',(SELECT count(*) FROM private.narrative_publication_event),
    'fact',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.id),'[]') FROM public.fact x),
    'assertion',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.id),'[]') FROM public.assertion x),
    'conclusion',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.target_type,x.target_id),'[]') FROM public.conclusion x),
    'citation',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.id),'[]') FROM public.citation x),
    'promotion',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.id),'[]') FROM private.interpretation_promotion x),
    'interpretation',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.id),'[]') FROM private.interpretation x),
    'placement',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.id),'[]') FROM private.source_persona_placement x),
    'person',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.id),'[]') FROM public.person x),
    'change_set',(SELECT count(*) FROM public.change_set),
    'change_event',(SELECT count(*) FROM public.change_event));
END $$;

-- Fixture: personaen (1939-agtig hovedperson) peger på X med oprindelsen publication_binding; X har et publiceret
-- narrativ bundet til personaens post og et bundet dødsfaktum; et proposed forslag venter på personaen.
DO $setup$
DECLARE
  v_actor uuid:='66200000-0000-4000-8000-000000000001'; w jsonb; w1 jsonb; s2 jsonb; post jsonb; v_persona uuid; v_x bigint:=-6620000;
  v_src2 bigint:=-6620100; v_text text:='Anna Alfa. Død 1850.'; v_binding uuid;
  v_int uuid:=gen_random_uuid(); v_key uuid:=gen_random_uuid(); v_status_placed text; v_hash text;
BEGIN
  -- Verden 1 (som 2018-20): en anden kilde med persona, der binder X's dødsfaktum, og et publiceret narrativ.
  w1:=pg_temp.fpf_bound(v_x,v_actor);
  -- Verden 2 (1939-agtig): egen kilde, post med hovedperson-persona -> X og et publiceret narrativ på X.
  s2:=pg_temp.f5b_source(v_src2);
  UPDATE public.source SET import_key='verify:t5forkert',udgave='DAA t5 1939-agtig' WHERE id=v_src2;
  post:=pg_temp.f5b_post(v_src2,s2,'T5',v_text,ARRAY['Anna Alfa.','Død 1850.'],v_x,v_actor);
  PERFORM pg_temp.f2a_event_for_state((post->>'principal')::uuid);
  PERFORM pg_temp.f2a_publish(v_src2,s2,post,v_x,v_actor,v_text);
  w:=jsonb_build_object('source',v_src2,'record_key','T5','post',post,'src',s2);
  v_persona:=(post->>'principal')::uuid;
  SELECT p.id INTO v_binding FROM private.narrative_record_publication p
    JOIN private.source_record r ON r.id=p.source_record_id WHERE p.status='published' AND r.source_id=v_src2;
  IF v_binding IS NULL THEN RAISE EXCEPTION 'FORKERT_PERSON_TEST_FAILED: fixturen har ingen publiceret binding'; END IF;
  -- identiteten som trin 6b skriver den (§4.3.1): oprindelsen publication_binding bærer autoriteten
  UPDATE private.source_persona_identity SET evidence=jsonb_build_object('authority','narrative_record_publication','binding_id',v_binding)
   WHERE source_persona_id=v_persona;
  -- hændelsestabellen er append-only; fixturen retter version 1's evidens med triggere slået fra i denne ene sætning
  SET LOCAL session_replication_role = replica;
  UPDATE private.source_persona_identity_event SET evidence=jsonb_build_object('authority','narrative_record_publication','binding_id',v_binding)
   WHERE source_persona_id=v_persona AND version=1;
  SET LOCAL session_replication_role = origin;
  -- Kontrast (rulles tilbage i en delstransaktion): en persona MED accepteret placering ændrer narrativets
  -- publiceringsstatus til stale_published, når dens identitet bliver unresolved (provenance mister identiteten).
  -- Det er ikke 1939's tilstand (ingen placeringer; trin 6d opretter dem), men Task 7/6d skal kende det.
  BEGIN
    PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
    SET LOCAL ROLE authenticated;
    PERFORM public.red_afgoer_source_persona(v_persona,1,'unresolved',NULL,'kontrast','{"basis":"web_detail"}'::jsonb);
    RESET ROLE;
    v_status_placed:=private.narrative_record_state(v_x,(w->>'source')::bigint,w->>'record_key',false)->>'publication_status';
    RAISE EXCEPTION 'T5_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    RESET ROLE;
    IF SQLERRM<>'T5_ROLLBACK' THEN RAISE; END IF;
  END;
  IF v_status_placed IS DISTINCT FROM 'stale_published' THEN
    RAISE EXCEPTION 'FORKERT_PERSON_TEST_FAILED: kontrast (med placering) forventede stale_published, fik %',v_status_placed; END IF;
  IF (SELECT version FROM private.source_persona_identity WHERE source_persona_id=v_persona)<>1 THEN
    RAISE EXCEPTION 'FORKERT_PERSON_TEST_FAILED: kontrastforsøget blev ikke rullet tilbage'; END IF;
  -- 1939 har ingen persona-placeringer (målt for kilde 3; trin 6d opretter dem). Fixturen skal publicere gennem
  -- RPC'erne og har derfor placeringer; de fjernes her, så tilstanden ligner 1939 (append-only slået fra i sætningen),
  -- og narrativet revalideres gennem den rigtige RPC, så publiceringstilstanden igen er published uden identiteter.
  SET LOCAL session_replication_role = replica;
  DELETE FROM private.source_persona_placement_decision WHERE placement_id IN
    (SELECT id FROM private.source_persona_placement WHERE source_persona_id=v_persona);
  DELETE FROM private.source_persona_placement WHERE source_persona_id=v_persona;
  SET LOCAL session_replication_role = origin;
  v_hash:=private.narrative_record_state(v_x,(w->>'source')::bigint,w->>'record_key',true)->>'state_sha256';
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  PERFORM set_config('app.change_set_id','',true);
  SET LOCAL ROLE authenticated;
  PERFORM public.red_revalider_person_narrative_record(v_x,(w->>'source')::bigint,w->>'record_key',v_hash);
  PERFORM set_config('app.change_set_id','',true);
  RESET ROLE;
  -- ét proposed forslag på personaen, der citerer en klausul i posten
  INSERT INTO private.interpretation(id,interpretation_key,version,source_id,source_persona_id,interpretation_kind,
    predicate,value,schema_version,derivation_kind,confidence,status,method,extraction_run_id)
    VALUES (v_int,v_key,1,(w->>'source')::bigint,v_persona,'property','person.death',to_jsonb('1850'::text),'1.0',
      'source_statement',1,'proposed','fixture',(s2->>'run')::uuid);
  INSERT INTO private.interpretation_observation(interpretation_id,observation_id,evidence_role,ordinal)
    VALUES (v_int,(w#>>'{post,clauses,0}')::uuid,'supporting',1);
  SET CONSTRAINTS private.interpretation_has_observation IMMEDIATE;
  SET CONSTRAINTS private.interpretation_has_observation DEFERRED;
  IF (SELECT count(*) FROM private.source_persona_identity WHERE source_persona_id=v_persona AND version=1
         AND decision_status='accepted' AND canonical_person_id=v_x)<>1 THEN
    RAISE EXCEPTION 'FORKERT_PERSON_TEST_FAILED: fixture-identitet';
  END IF;
  INSERT INTO t5 VALUES ('w',w),('persona',to_jsonb(v_persona)),('x',to_jsonb(v_x)),('y',w1->'other'),('w1',w1),
    ('proposal',to_jsonb(v_int)),('actor',to_jsonb(v_actor)),('binding',to_jsonb(v_binding));
  RAISE NOTICE 'OK: fixture (persona med publication_binding-identitet, publiceret narrativ, bundet fakta, ét proposed forslag)';
END $setup$;

-- FØR: klassifikationen (read-only, som i test-interpretation-control-classification.sql) og tilstandssnapshots.
SET LOCAL default_transaction_read_only = on;
\i .claude/skills/daa-extract/scripts/interpretation_control_classification.sql
SET LOCAL default_transaction_read_only = off;
DO $before$
DECLARE
  v_prop uuid:=(SELECT (v#>>'{}')::uuid FROM t5 WHERE k='proposal'); w jsonb:=(SELECT v FROM t5 WHERE k='w');
  v_x bigint:=(SELECT (v#>>'{}')::bigint FROM t5 WHERE k='x'); v_class text; v_state jsonb; v_facts jsonb;
BEGIN
  SELECT i->>'class' INTO v_class FROM jsonb_array_elements(current_setting('daa.control_result')::jsonb->'items') i
   WHERE (i->>'interpretation_id')::uuid=v_prop;
  IF v_class NOT IN ('MATCH','MATCH_SINGLETON') THEN
    RAISE EXCEPTION 'FORKERT_PERSON_TEST_FAILED: forslaget skal være et match før afgørelsen, var %',v_class; END IF;
  v_state:=private.narrative_record_state(v_x,(w->>'source')::bigint,w->>'record_key',false);
  IF v_state->>'blocking_reason' IS NOT NULL OR v_state->>'publication_status' IS DISTINCT FROM 'published' THEN
    RAISE EXCEPTION 'FORKERT_PERSON_TEST_FAILED: udgangstilstand %',v_state; END IF;
  SELECT coalesce(jsonb_agg(to_jsonb(f) ORDER BY f.person_id,f.fact_id,f.assertion_id),'[]') INTO v_facts
    FROM public.public_person_facts(ARRAY[v_x]) f;
  IF jsonb_array_length(v_facts)=0 OR NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_facts) f WHERE f->>'record_ref' IS NOT NULL) THEN
    RAISE EXCEPTION 'FORKERT_PERSON_TEST_FAILED: public_person_facts skal give en bundet række før afgørelsen: %',v_facts; END IF;
  INSERT INTO t5 VALUES ('state_before',v_state),('facts_before',v_facts),('untouched_before',pg_temp.t5_untouched()),
    ('identity_events_before',to_jsonb((SELECT count(*) FROM private.source_persona_identity_event))),
    ('other_identities_before',(SELECT coalesce(jsonb_agg(to_jsonb(i) ORDER BY i.source_persona_id),'[]')
        FROM private.source_persona_identity i WHERE i.source_persona_id<>(SELECT (v#>>'{}')::uuid FROM t5 WHERE k='persona'))),
    ('v1_event',(SELECT to_jsonb(e) FROM private.source_persona_identity_event e
        WHERE e.source_persona_id=(SELECT (v#>>'{}')::uuid FROM t5 WHERE k='persona') AND e.version=1));
  RAISE NOTICE 'OK: udgangstilstand (forslag %, bundet fakta, narrativ published)',v_class;
END $before$;

-- Afgørelsen. Hver forsøg i sin egen blok; afviste forsøg efterlader ingenting.
CREATE FUNCTION pg_temp.t5_decide(p_version int, p_ctx jsonb, p_note text DEFAULT 'forkert person, rigtig person er -6620001')
RETURNS text LANGUAGE plpgsql AS $$
DECLARE v_persona uuid:=(SELECT (v#>>'{}')::uuid FROM t5 WHERE k='persona'); v_ret int;
BEGIN
  PERFORM set_config('request.jwt.claim.sub',(SELECT v#>>'{}' FROM t5 WHERE k='actor'),true);
  PERFORM set_config('app.change_set_id','',true);
  SET LOCAL ROLE authenticated;
  v_ret:=public.red_afgoer_source_persona(v_persona,p_version,'unresolved',NULL,p_note,p_ctx);
  RESET ROLE;
  RETURN 'OK:'||v_ret;
EXCEPTION WHEN OTHERS THEN RESET ROLE; RETURN SQLERRM;
END $$;

DO $decide$
DECLARE
  v_persona uuid:=(SELECT (v#>>'{}')::uuid FROM t5 WHERE k='persona'); v_res text;
  v_sheet jsonb:=jsonb_build_object('basis','human_sheet','sheet_sha256',repeat('a',64),'rows_sha256',repeat('b',64),'line','1');
BEGIN
  -- 1) Kontekstkravet: Y kan ikke stå i p_context (brief nævnte "ønsket_person_id"); nøglen afvises.
  v_res:=pg_temp.t5_decide(1,v_sheet||jsonb_build_object('ønsket_person_id',-6620001));
  IF v_res NOT LIKE 'EVIDENCE_IDENTITY_DECISION_INVALID%' THEN
    RAISE EXCEPTION 'FORKERT_PERSON_TEST_FAILED: ønsket_person_id i konteksten skulle afvises, fik %',v_res; END IF;
  -- 2) Stale version: personaen står på version 1; version 0 er forældet.
  v_res:=pg_temp.t5_decide(0,v_sheet);
  IF v_res NOT LIKE 'EVIDENCE_IDENTITY_VERSION_CONFLICT%' THEN
    RAISE EXCEPTION 'FORKERT_PERSON_TEST_FAILED: forældet version skulle afvises, fik %',v_res; END IF;
  -- 3) Tom note og kort uden hashes afvises også (kontekstkravene).
  IF pg_temp.t5_decide(1,v_sheet,'  ') NOT LIKE 'EVIDENCE_IDENTITY_DECISION_INVALID%'
     OR pg_temp.t5_decide(1,'{"basis":"human_sheet"}') NOT LIKE 'EVIDENCE_IDENTITY_DECISION_INVALID%' THEN
    RAISE EXCEPTION 'FORKERT_PERSON_TEST_FAILED: tom note / ark uden hashes skulle afvises'; END IF;
  -- Ingen af de afviste forsøg har ændret noget.
  IF (SELECT version FROM private.source_persona_identity WHERE source_persona_id=v_persona)<>1
     OR (SELECT count(*) FROM private.source_persona_identity_event)<>(SELECT (v#>>'{}')::int FROM t5 WHERE k='identity_events_before') THEN
    RAISE EXCEPTION 'FORKERT_PERSON_TEST_FAILED: et afvist forsøg ændrede identiteten'; END IF;
  -- 4) Den gyldige afgørelse (kortark, forventet version 1) lykkes og returnerer version 2.
  v_res:=pg_temp.t5_decide(1,v_sheet);
  IF v_res<>'OK:2' THEN RAISE EXCEPTION 'FORKERT_PERSON_TEST_FAILED: afgørelsen skulle lykkes med version 2, fik %',v_res; END IF;
  -- 5) Samme version igen er nu forældet.
  v_res:=pg_temp.t5_decide(1,v_sheet);
  IF v_res NOT LIKE 'EVIDENCE_IDENTITY_VERSION_CONFLICT%' THEN
    RAISE EXCEPTION 'FORKERT_PERSON_TEST_FAILED: genbrugt version skulle afvises, fik %',v_res; END IF;
  RAISE NOTICE 'OK: afgørelsen lykkes kun med den aktuelle version; kontekstkravene håndhæves';
END $decide$;

-- EFTER: identiteten og intet andet.
DO $after$
DECLARE
  v_persona uuid:=(SELECT (v#>>'{}')::uuid FROM t5 WHERE k='persona'); v_x bigint:=(SELECT (v#>>'{}')::bigint FROM t5 WHERE k='x');
  w jsonb:=(SELECT v FROM t5 WHERE k='w'); i private.source_persona_identity; e private.source_persona_identity_event;
  v_state jsonb; v_facts jsonb;
BEGIN
  SELECT * INTO i FROM private.source_persona_identity WHERE source_persona_id=v_persona;
  IF i.decision_status<>'unresolved' OR i.canonical_person_id IS NOT NULL OR i.version<>2
     OR i.evidence->>'action'<>'unresolved' OR i.evidence->>'basis'<>'human_sheet'
     OR i.evidence->>'note' NOT LIKE '%-6620001%' OR i.evidence->>'sheet_sha256'<>repeat('a',64)
     OR (i.evidence->>'line')::int<>1 OR i.decided_by IS NULL OR i.decided_at IS NULL THEN
    RAISE EXCEPTION 'FORKERT_PERSON_TEST_FAILED: identiteten efter afgørelsen: %',to_jsonb(i); END IF;
  SELECT * INTO e FROM private.source_persona_identity_event WHERE source_persona_id=v_persona AND version=2;
  IF e.id IS NULL OR e.decision_status<>'unresolved' OR e.canonical_person_id IS NOT NULL OR e.evidence<>i.evidence THEN
    RAISE EXCEPTION 'FORKERT_PERSON_TEST_FAILED: hændelsen for version 2'; END IF;
  IF (SELECT count(*) FROM private.source_persona_identity_event)<>(SELECT (v#>>'{}')::int FROM t5 WHERE k='identity_events_before')+1
     OR (SELECT to_jsonb(x) FROM private.source_persona_identity_event x WHERE x.source_persona_id=v_persona AND x.version=1)
        IS DISTINCT FROM (SELECT v FROM t5 WHERE k='v1_event') THEN
    RAISE EXCEPTION 'FORKERT_PERSON_TEST_FAILED: præcis én ny hændelse, version 1 uændret'; END IF;
  IF (SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.source_persona_id),'[]') FROM private.source_persona_identity x
       WHERE x.source_persona_id<>v_persona) IS DISTINCT FROM (SELECT v FROM t5 WHERE k='other_identities_before') THEN
    RAISE EXCEPTION 'FORKERT_PERSON_TEST_FAILED: en anden persona fik ændret identitet'; END IF;
  -- narrativ-publikationen er stadig published på X
  IF NOT EXISTS (SELECT 1 FROM private.narrative_record_publication p JOIN public.narrative n ON n.id=p.narrative_id
                  WHERE p.status='published' AND n.subjekt_type='person' AND n.subjekt_id=v_x) THEN
    RAISE EXCEPTION 'FORKERT_PERSON_TEST_FAILED: narrativet er ikke længere published på X'; END IF;
  v_state:=private.narrative_record_state(v_x,(w->>'source')::bigint,w->>'record_key',false);
  IF v_state->>'blocking_reason' IS NOT NULL OR v_state IS DISTINCT FROM (SELECT v FROM t5 WHERE k='state_before') THEN
    RAISE EXCEPTION 'FORKERT_PERSON_TEST_FAILED: narrative_record_state(X) ændret/blokeret: %',v_state; END IF;
  -- public_person_facts: hele rækker, begge veje, dubletter talt med
  SELECT coalesce(jsonb_agg(to_jsonb(f) ORDER BY f.person_id,f.fact_id,f.assertion_id),'[]') INTO v_facts
    FROM public.public_person_facts(ARRAY[v_x]) f;
  IF v_facts IS DISTINCT FROM (SELECT v FROM t5 WHERE k='facts_before') THEN
    RAISE EXCEPTION 'FORKERT_PERSON_TEST_FAILED: public_person_facts(ARRAY[X]) ændret: % mod %',v_facts,(SELECT v FROM t5 WHERE k='facts_before'); END IF;
  -- alt andet: narrativ, binding, fakta, påstande, konklusioner, fortolkninger, promotioner, placeringer, personer
  IF pg_temp.t5_untouched() IS DISTINCT FROM (SELECT v FROM t5 WHERE k='untouched_before') THEN
    RAISE EXCEPTION 'FORKERT_PERSON_TEST_FAILED: afgørelsen rørte andet end identiteten'; END IF;
  RAISE NOTICE 'OK: identitet unresolved (v2) + hændelse; narrativ, state, public_person_facts og alt andet uændret';
END $after$;

-- Klassifikationen: forslaget er nu NO_IDENTITY (og kun det er skiftet).
SET LOCAL default_transaction_read_only = on;
\i .claude/skills/daa-extract/scripts/interpretation_control_classification.sql
SET LOCAL default_transaction_read_only = off;
DO $class$
DECLARE v_prop uuid:=(SELECT (v#>>'{}')::uuid FROM t5 WHERE k='proposal'); v_class text;
BEGIN
  SELECT i->>'class' INTO v_class FROM jsonb_array_elements(current_setting('daa.control_result')::jsonb->'items') i
   WHERE (i->>'interpretation_id')::uuid=v_prop;
  IF v_class IS DISTINCT FROM 'NO_IDENTITY' THEN
    RAISE EXCEPTION 'FORKERT_PERSON_TEST_FAILED: forslaget skulle være NO_IDENTITY, var %',v_class; END IF;
  RAISE NOTICE 'OK: forslaget er NO_IDENTITY efter forkert person';
END $class$;
ROLLBACK;
