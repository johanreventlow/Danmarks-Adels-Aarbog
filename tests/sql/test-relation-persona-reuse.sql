-- Trin 6c-3a (spec 2026-11-07-trin6c3-a6b-resten-design.md §4.7 pkt. 1): relation_persona-writeren genbruger en
-- eksisterende ægtefælle-persona som part på en ny nøgle efter en kildetekst-revision, når præcis én persona opfylder
-- reglen (forældet nøgle med grundlaget source_text_revision, samme ægteskabsnummer, samme navn efter
-- saml_blanktegn_v1, ingen ægtefællepart på en levende nøgle). Finalize (verify_relation_persona_receipts) efterprøver
-- genbruget adskilt. Til sidst §4.7 pkt. 3: personaens kontekst efter genbruget. Kræver kontrakt v2
-- (reimport-writer-v2-bootstrap.sql). Alt syntetisk; én transaktion, rulles tilbage.
\set ON_ERROR_STOP on

-- Hovedtransaktionen kører eksplicit READ COMMITTED, som revisions-writeren kræver.
BEGIN ISOLATION LEVEL READ COMMITTED;
\ir fixtures/relation-5b.sql
\ir fixtures/relation-2a.sql
\ir fixtures/source-text-revision.sql
\ir fixtures/relation-persona-reuse-helpers.sql

-- Ægteskabet afgøres (familiestruktur) og bindes: ægtefællens identitet, familien, afgørelse og binding (som t5_post).
CREATE FUNCTION pg_temp.t6_bind(p_source bigint,p_principal bigint,p_spouse_person bigint,p_persona uuid,p_key text,
  p_actor uuid) RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE v_at timestamptz:=clock_timestamp(); v_fam bigint; pv jsonb; items jsonb;
BEGIN
  INSERT INTO private.source_persona_identity_event(source_persona_id,canonical_person_id,decision_status,version,evidence,
    decided_by,decided_by_name,decided_at)
    VALUES (p_persona,p_spouse_person,'accepted',1,'{"fixture":"6c3"}',p_actor,'fixture',v_at);
  INSERT INTO private.source_persona_identity(source_persona_id,canonical_person_id,decision_status,version,evidence,
    decided_by,decided_by_name,decided_at)
    VALUES (p_persona,p_spouse_person,'accepted',1,'{"fixture":"6c3"}',p_actor,'fixture',v_at);
  v_fam:=pg_temp.f5b_family(p_principal,p_spouse_person,1);
  PERFORM set_config('request.jwt.claim.sub',p_actor::text,true);
  SET LOCAL ROLE authenticated;
  pv:=red_preview_relation_decisions(p_source);
  PERFORM red_decide_relation_interpretations(p_source,pv->>'set_sha256');
  RESET ROLE;
  SELECT jsonb_agg(jsonb_build_object('interpretation_id',ic.id::text,'family_id',v_fam)) INTO items
    FROM private.interpretation_current ic WHERE ic.interpretation_key=p_key::uuid AND ic.status='accepted';
  IF items IS NULL THEN RAISE EXCEPTION 'T6_BIND_NOT_ACCEPTED'; END IF;
  SET LOCAL ROLE authenticated;
  pv:=red_preview_relation_promotions(p_source,items);
  PERFORM red_promote_relation_interpretations_batch(p_source,items,pv->>'preview_sha256');
  RESET ROLE;
  IF NOT EXISTS (SELECT 1 FROM private.interpretation_promotion p JOIN private.interpretation q ON q.id=p.interpretation_id
                  WHERE q.interpretation_key=p_key::uuid AND p.target_type='family') THEN
    RAISE EXCEPTION 'T6_BIND_NOT_PROMOTED';
  END IF;
  RETURN v_fam;
END $$;

-- Revisionen af posten til p_new (klausuler p_parts) gennem hele kæden; returnerer klausulerne i det nye sæt. t5_clauses
-- lægger renditionsoffsets inden for helpostens spænd, så den nye tekst må ikke være længere end den gamle.
CREATE FUNCTION pg_temp.t6_revise(p_source bigint,p_post jsonb,p_old text,p_new text,p_parts text[],p_actor uuid,p_nonce text)
RETURNS uuid[] LANGUAGE plpgsql AS $$
DECLARE fx jsonb; r jsonb;
BEGIN
  fx:=jsonb_build_object('source',p_source,'record_key',p_post->>'key','helpost',p_post->>'helpost','text',p_old,
    'actor',p_actor,'profile',pg_temp.t5_profile(p_source));
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  r:=pg_temp.t5_apply(fx,pg_temp.t5_payload(fx,p_new,p_parts),p_nonce);
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  IF jsonb_array_length(r->'superseded_keys')=0 THEN RAISE EXCEPTION 'T6_REVISION_SUPERSEDED_NOTHING'; END IF;
  RETURN ARRAY(SELECT id FROM private.clause_observation_current WHERE parent_observation_id=(p_post->>'helpost')::uuid
                ORDER BY clause_ordinal);
END $$;

CREATE FUNCTION pg_temp.t6_personas(p_source bigint) RETURNS bigint LANGUAGE sql AS $$
  SELECT count(*) FROM private.source_persona WHERE source_id=p_source
$$;

-- test_reuse_name_same_place: ét ægteskab skrevet af writeren, afgjort og bundet; revisionen retter en klausul efter
-- ægteskabet, så navnet står samme sted (samme indholds-id, som før gav unique_violation). Writeren genbruger personaen:
-- antallet af personas og mentions er uændret, parten på den nye nøgle peger på den, kvitteringen har "reused": true og
-- ingen mention_id, og finalize er grøn med uændrede tællingsnøgler.
DO $t$
DECLARE v_actor uuid:='11000000-0000-0000-0000-0000006c3a01'; s jsonb; post jsonb; c jsonb; c2 jsonb; p jsonb; w jsonb;
  v_old text:='Anna Alfa. Gift med Bo Beta. Datter Dora Delta.'; v_new text:='Anna Alfa. Gift med Bo Beta. Datter Dora.';
  v_persona uuid; v_cl uuid[]; v_n bigint; v_mentions bigint; v_old_offset int;
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  INSERT INTO person(id,levende,privat,status) VALUES (-66101,false,false,'6c3'),(-66102,false,false,'6c3');
  s:=pg_temp.f5b_source(-66101);
  post:=pg_temp.f5b_post(-66101,s,'T6-A',v_old,ARRAY['Anna Alfa.','Gift med Bo Beta.','Datter Dora Delta.'],-66101,v_actor);
  PERFORM pg_temp.f2a_event_for_state((post->>'principal')::uuid);
  c:=pg_temp.f5b_claim(-66101,s,'relation.marriage',(post->'clauses'->>1)::uuid,'Gift med Bo Beta.');
  p:=pg_temp.t6_payload((post->'clauses'->>1)::uuid,c->>'key','Gift med Bo Beta.','Bo Beta');
  v_old_offset:=(p->>'post_offset')::int;
  PERFORM pg_temp.t6_write(-66101,v_actor,p);
  v_persona:=pg_temp.t6_spouse(c->>'key');
  IF v_persona IS DISTINCT FROM private.content_uuid('source-persona',jsonb_build_object('source_id',-66101,
       'persona_key','T6-A#rel-marriage-'||v_old_offset||'-'||char_length('Gift med Bo Beta.'))) THEN
    RAISE EXCEPTION 'RELATION_REUSE_TEST_FAILED: fixturens persona har ikke indholds-id';
  END IF;
  PERFORM pg_temp.t6_bind(-66101,-66101,-66102,v_persona,c->>'key',v_actor);
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;

  v_cl:=pg_temp.t6_revise(-66101,post,v_old,v_new,ARRAY['Anna Alfa.','Gift med Bo Beta.','Datter Dora.'],v_actor,'t6-a');
  IF NOT EXISTS (SELECT 1 FROM private.interpretation_current WHERE interpretation_key=(c->>'key')::uuid
                  AND status='superseded' AND decision_evidence->>'basis'='source_text_revision') THEN
    RAISE EXCEPTION 'RELATION_REUSE_TEST_FAILED: den gamle nøgle er ikke forældet';
  END IF;
  c2:=pg_temp.f5b_claim(-66101,s,'relation.marriage',v_cl[2],'Gift med Bo Beta.');
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  p:=pg_temp.t6_payload(v_cl[2],c2->>'key','Gift med Bo Beta.','Bo Beta');
  IF (p->>'post_offset')::int<>v_old_offset OR (p->>'marriage_ordinal')::int<>1 OR (p->>'clause_set_seq')::int<>2 THEN
    RAISE EXCEPTION 'RELATION_REUSE_TEST_FAILED: payloaden %',p;
  END IF;
  v_n:=pg_temp.t6_personas(-66101);
  SELECT count(*) INTO v_mentions FROM private.source_mention sm JOIN private.source_observation o ON o.id=sm.observation_id
   WHERE o.occurrence_id=(post->>'occ')::uuid;
  w:=pg_temp.t6_write(-66101,v_actor,p);
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  IF pg_temp.t6_personas(-66101)<>v_n
     OR (SELECT count(*) FROM private.source_mention sm JOIN private.source_observation o ON o.id=sm.observation_id
          WHERE o.occurrence_id=(post->>'occ')::uuid)<>v_mentions THEN
    RAISE EXCEPTION 'RELATION_REUSE_TEST_FAILED: ny persona eller mention ved genbrug';
  END IF;
  IF pg_temp.t6_spouse(c2->>'key') IS DISTINCT FROM v_persona
     OR (SELECT marriage_ordinal FROM private.interpretation_party_current
          WHERE interpretation_key=(c2->>'key')::uuid AND party_role='spouse')<>1 THEN
    RAISE EXCEPTION 'RELATION_REUSE_TEST_FAILED: parten på den nye nøgle';
  END IF;
  IF w->'receipt'->'reused'<>'true'::jsonb OR w->'receipt'->'mention_id'<>'null'::jsonb
     OR w->'receipt'->>'spouse_source_persona_id'<>v_persona::text THEN
    RAISE EXCEPTION 'RELATION_REUSE_TEST_FAILED: kvitteringen %',w->'receipt';
  END IF;
  IF w->'result'->'relation_results'->0->'derived_counts'<>'{"mentions":0,"parties":2,"spouse_personas":1,"year_interpretations":0}' THEN
    RAISE EXCEPTION 'RELATION_REUSE_TEST_FAILED: resultatkortet %',w->'result';
  END IF;
  IF (SELECT status FROM private.reimport_batch WHERE id=(w->>'batch')::uuid)<>'finalized' THEN
    RAISE EXCEPTION 'RELATION_REUSE_TEST_FAILED: batchen er ikke finaliseret';
  END IF;
  RAISE NOTICE 'OK: test_reuse_name_same_place';
END $t$;

-- test_reuse_name_moved + test_reuse_already_reused: revisionen flytter navnet (andet post_offset, andet indholds-id);
-- writeren genbruger via reglen i stedet for at oprette en dubletpersona. En senere batch på samme klausul finder
-- ingen kandidat, fordi personaen nu er part på en levende nøgle: en ny persona oprettes som før.
DO $t$
DECLARE v_actor uuid:='11000000-0000-0000-0000-0000006c3a02'; s jsonb; post jsonb; c jsonb; c2 jsonb; c3 jsonb; p jsonb; w jsonb;
  v_old text:='Anna Alfa, født 1800. Gift med Bo Beta.'; v_new text:='Anna Alfa, f. 1800. Gift med Bo Beta.';
  v_persona uuid; v_cl uuid[]; v_n bigint; v_old_offset int;
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  INSERT INTO person(id,levende,privat,status) VALUES (-66201,false,false,'6c3');
  s:=pg_temp.f5b_source(-66201);
  post:=pg_temp.f5b_post(-66201,s,'T6-B',v_old,ARRAY['Anna Alfa, født 1800.','Gift med Bo Beta.'],-66201,v_actor);
  PERFORM pg_temp.f2a_event_for_state((post->>'principal')::uuid);
  c:=pg_temp.f5b_claim(-66201,s,'relation.marriage',(post->'clauses'->>1)::uuid,'Gift med Bo Beta.');
  p:=pg_temp.t6_payload((post->'clauses'->>1)::uuid,c->>'key','Gift med Bo Beta.','Bo Beta');
  v_old_offset:=(p->>'post_offset')::int;
  PERFORM pg_temp.t6_write(-66201,v_actor,p);
  v_persona:=pg_temp.t6_spouse(c->>'key');
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;

  v_cl:=pg_temp.t6_revise(-66201,post,v_old,v_new,ARRAY['Anna Alfa, f. 1800.','Gift med Bo Beta.'],v_actor,'t6-b');
  c2:=pg_temp.f5b_claim(-66201,s,'relation.marriage',v_cl[2],'Gift med Bo Beta.');
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  p:=pg_temp.t6_payload(v_cl[2],c2->>'key','Gift med Bo Beta.','Bo Beta');
  IF (p->>'post_offset')::int=v_old_offset THEN RAISE EXCEPTION 'RELATION_REUSE_TEST_FAILED: navnet flyttede ikke'; END IF;
  v_n:=pg_temp.t6_personas(-66201);
  w:=pg_temp.t6_write(-66201,v_actor,p);
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  IF pg_temp.t6_personas(-66201)<>v_n OR pg_temp.t6_spouse(c2->>'key') IS DISTINCT FROM v_persona
     OR w->'receipt'->'reused'<>'true'::jsonb OR w->'receipt'->'mention_id'<>'null'::jsonb THEN
    RAISE EXCEPTION 'RELATION_REUSE_TEST_FAILED: flyttet navn genbrugte ikke %',w->'receipt';
  END IF;
  RAISE NOTICE 'OK: test_reuse_name_moved';

  -- En anden batch på samme klausul (kortere spænd, så den får ægteskabsnummer 1 og navnet er det samme): personaen
  -- er part på den levende nøgle c2 og er ikke kandidat; writeren opretter en ny persona.
  c3:=pg_temp.f5b_claim(-66201,s,'relation.marriage',v_cl[2],'Gift med Bo Beta');
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  p:=pg_temp.t6_payload(v_cl[2],c3->>'key','Gift med Bo Beta','Bo Beta');
  IF (p->>'marriage_ordinal')::int<>1 THEN RAISE EXCEPTION 'RELATION_REUSE_TEST_FAILED: c3-nummer %',p; END IF;
  w:=pg_temp.t6_write(-66201,v_actor,p);
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  IF pg_temp.t6_personas(-66201)<>v_n+1 OR pg_temp.t6_spouse(c3->>'key') IS NOT DISTINCT FROM v_persona
     OR w->'receipt' ? 'reused' OR w->'receipt'->'mention_id'='null'::jsonb THEN
    RAISE EXCEPTION 'RELATION_REUSE_TEST_FAILED: allerede genbrugt persona blev genbrugt igen %',w->'receipt';
  END IF;
  RAISE NOTICE 'OK: test_reuse_already_reused';
END $t$;

-- test_reuse_ambiguous: to forældede ægteskaber med samme nummer og samme navn ⇒ RELATION_PERSONA_REUSE_AMBIGUOUS, og
-- intet er skrevet.
DO $t$
DECLARE v_actor uuid:='11000000-0000-0000-0000-0000006c3a03'; s jsonb; post jsonb; c jsonb; c2 jsonb; p jsonb;
  v_old text:='Anna Alfa. Gift med Bo Beta. g. m. Bo Beta.'; v_new text:='Anna Alfa. Gift med Bo Beta.';
  v_cl uuid[]; v_n bigint; v_err text;
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  INSERT INTO person(id,levende,privat,status) VALUES (-66301,false,false,'6c3');
  s:=pg_temp.f5b_source(-66301);
  post:=pg_temp.f5b_post(-66301,s,'T6-C',v_old,ARRAY['Anna Alfa.','Gift med Bo Beta.','g. m. Bo Beta.'],-66301,v_actor);
  PERFORM pg_temp.f2a_event_for_state((post->>'principal')::uuid);
  c:=pg_temp.f5b_claim(-66301,s,'relation.marriage',(post->'clauses'->>1)::uuid,'Gift med Bo Beta.');
  PERFORM pg_temp.f5b_spouse(-66301,s,post,c,(post->'clauses'->>1)::uuid,'Bo Beta',1);
  c:=pg_temp.f5b_claim(-66301,s,'relation.marriage',(post->'clauses'->>2)::uuid,'g. m. Bo Beta.');
  PERFORM pg_temp.f5b_spouse(-66301,s,post,c,(post->'clauses'->>2)::uuid,'Bo Beta',1);
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  v_cl:=pg_temp.t6_revise(-66301,post,v_old,v_new,ARRAY['Anna Alfa.','Gift med Bo Beta.'],v_actor,'t6-c');
  c2:=pg_temp.f5b_claim(-66301,s,'relation.marriage',v_cl[2],'Gift med Bo Beta.');
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  p:=pg_temp.t6_payload(v_cl[2],c2->>'key','Gift med Bo Beta.','Bo Beta');
  v_n:=pg_temp.t6_personas(-66301);
  BEGIN
    PERFORM pg_temp.t6_write(-66301,v_actor,p);
    v_err:='ingen fejl';
  EXCEPTION WHEN OTHERS THEN v_err:=SQLERRM;
  END;
  IF v_err NOT LIKE 'RELATION_PERSONA_REUSE_AMBIGUOUS%' THEN
    RAISE EXCEPTION 'RELATION_REUSE_TEST_FAILED: tvetydigt genbrug gav %',v_err;
  END IF;
  IF pg_temp.t6_personas(-66301)<>v_n OR pg_temp.t6_spouse(c2->>'key') IS NOT NULL THEN
    RAISE EXCEPTION 'RELATION_REUSE_TEST_FAILED: tvetydigt genbrug efterlod skrivninger';
  END IF;
  RAISE NOTICE 'OK: test_reuse_ambiguous';
END $t$;

-- test_no_revision_unique_violation: uden revision (den gamle nøgle er accepteret og bundet) er personaen ikke kandidat;
-- en ny påstand på samme klausul med samme spænd giver samme indholds-id og unique_violation som før.
DO $t$
DECLARE v_actor uuid:='11000000-0000-0000-0000-0000006c3a04'; s jsonb; post jsonb; c jsonb; c2 jsonb; p jsonb;
  v_text text:='Anna Alfa. Gift med Bo Beta.'; v_persona uuid; v_state text;
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  INSERT INTO person(id,levende,privat,status) VALUES (-66401,false,false,'6c3'),(-66402,false,false,'6c3');
  s:=pg_temp.f5b_source(-66401);
  post:=pg_temp.f5b_post(-66401,s,'T6-D',v_text,ARRAY['Anna Alfa.','Gift med Bo Beta.'],-66401,v_actor);
  PERFORM pg_temp.f2a_event_for_state((post->>'principal')::uuid);
  c:=pg_temp.f5b_claim(-66401,s,'relation.marriage',(post->'clauses'->>1)::uuid,'Gift med Bo Beta.');
  PERFORM pg_temp.t6_write(-66401,v_actor,pg_temp.t6_payload((post->'clauses'->>1)::uuid,c->>'key','Gift med Bo Beta.','Bo Beta'));
  v_persona:=pg_temp.t6_spouse(c->>'key');
  PERFORM pg_temp.t6_bind(-66401,-66401,-66402,v_persona,c->>'key',v_actor);
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  IF (SELECT status FROM private.interpretation_current WHERE interpretation_key=(c->>'key')::uuid)<>'accepted' THEN
    RAISE EXCEPTION 'RELATION_REUSE_TEST_FAILED: den gamle nøgle er ikke accepteret';
  END IF;
  c2:=pg_temp.f5b_claim(-66401,s,'relation.marriage',(post->'clauses'->>1)::uuid,'Gift med Bo Beta.');
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  p:=pg_temp.t6_payload((post->'clauses'->>1)::uuid,c2->>'key','Gift med Bo Beta.','Bo Beta');
  BEGIN
    PERFORM pg_temp.t6_write(-66401,v_actor,p);
    RAISE EXCEPTION 'RELATION_REUSE_TEST_FAILED: ingen unique_violation';
  EXCEPTION WHEN unique_violation THEN v_state:=SQLSTATE;
  END;
  IF v_state<>'23505' OR pg_temp.t6_spouse(c2->>'key') IS NOT NULL THEN
    RAISE EXCEPTION 'RELATION_REUSE_TEST_FAILED: unique_violation-sagen';
  END IF;
  RAISE NOTICE 'OK: test_no_revision_unique_violation';
END $t$;

-- test_different_ordinal_no_reuse: revisionen indsætter et ægteskab før; samme navn får nummer 2, personaen havde 1 ⇒
-- ingen kandidat, ny persona.
DO $t$
DECLARE v_actor uuid:='11000000-0000-0000-0000-0000006c3a05'; s jsonb; post jsonb; c jsonb; kb jsonb; p jsonb; w jsonb;
  v_old text:='Anna Alfa, født i Aarhus 1800. Gift med Bo Beta.'; v_new text:='Anna Alfa. Gift med Cia Ceta. Gift med Bo Beta.';
  v_persona uuid; v_cl uuid[]; v_n bigint;
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  INSERT INTO person(id,levende,privat,status) VALUES (-66501,false,false,'6c3');
  s:=pg_temp.f5b_source(-66501);
  post:=pg_temp.f5b_post(-66501,s,'T6-E',v_old,ARRAY['Anna Alfa, født i Aarhus 1800.','Gift med Bo Beta.'],-66501,v_actor);
  PERFORM pg_temp.f2a_event_for_state((post->>'principal')::uuid);
  c:=pg_temp.f5b_claim(-66501,s,'relation.marriage',(post->'clauses'->>1)::uuid,'Gift med Bo Beta.');
  PERFORM pg_temp.t6_write(-66501,v_actor,pg_temp.t6_payload((post->'clauses'->>1)::uuid,c->>'key','Gift med Bo Beta.','Bo Beta'));
  v_persona:=pg_temp.t6_spouse(c->>'key');
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  v_cl:=pg_temp.t6_revise(-66501,post,v_old,v_new,ARRAY['Anna Alfa.','Gift med Cia Ceta.','Gift med Bo Beta.'],v_actor,'t6-e');
  PERFORM pg_temp.f5b_claim(-66501,s,'relation.marriage',v_cl[2],'Gift med Cia Ceta.');
  kb:=pg_temp.f5b_claim(-66501,s,'relation.marriage',v_cl[3],'Gift med Bo Beta.');
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  p:=pg_temp.t6_payload(v_cl[3],kb->>'key','Gift med Bo Beta.','Bo Beta');
  IF (p->>'marriage_ordinal')::int<>2 THEN RAISE EXCEPTION 'RELATION_REUSE_TEST_FAILED: nummer %',p; END IF;
  v_n:=pg_temp.t6_personas(-66501);
  w:=pg_temp.t6_write(-66501,v_actor,p);
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  IF pg_temp.t6_personas(-66501)<>v_n+1 OR pg_temp.t6_spouse(kb->>'key') IS NOT DISTINCT FROM v_persona
     OR w->'receipt' ? 'reused' THEN
    RAISE EXCEPTION 'RELATION_REUSE_TEST_FAILED: andet nummer genbrugte %',w->'receipt';
  END IF;
  RAISE NOTICE 'OK: test_different_ordinal_no_reuse';
END $t$;

-- test_kun_andet_aegteskab_genfundet: to ægteskaber (Bo Beta nr. 1, Cia Ceta nr. 2) er forældet; kun det andet
-- genfindes og får nummer 1. Navnet afviger fra nr. 1-personaens, og nr. 2-personaen har et andet nummer ⇒ ingen
-- kandidat, ny persona.
DO $t$
DECLARE v_actor uuid:='11000000-0000-0000-0000-0000006c3a06'; s jsonb; post jsonb; c1 jsonb; c2 jsonb; k jsonb; p jsonb; w jsonb;
  v_old text:='Anna Alfa. Gift med Bo Beta. Gift med Cia Ceta.'; v_new text:='Anna Alfa. Gift m. Bo Beta. Gift med Cia Ceta.';
  v_p1 uuid; v_p2 uuid; v_cl uuid[]; v_n bigint;
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  INSERT INTO person(id,levende,privat,status) VALUES (-66601,false,false,'6c3');
  s:=pg_temp.f5b_source(-66601);
  post:=pg_temp.f5b_post(-66601,s,'T6-F',v_old,ARRAY['Anna Alfa.','Gift med Bo Beta.','Gift med Cia Ceta.'],-66601,v_actor);
  PERFORM pg_temp.f2a_event_for_state((post->>'principal')::uuid);
  c1:=pg_temp.f5b_claim(-66601,s,'relation.marriage',(post->'clauses'->>1)::uuid,'Gift med Bo Beta.');
  c2:=pg_temp.f5b_claim(-66601,s,'relation.marriage',(post->'clauses'->>2)::uuid,'Gift med Cia Ceta.');
  PERFORM pg_temp.t6_write(-66601,v_actor,pg_temp.t6_payload((post->'clauses'->>1)::uuid,c1->>'key','Gift med Bo Beta.','Bo Beta'));
  PERFORM pg_temp.t6_write(-66601,v_actor,pg_temp.t6_payload((post->'clauses'->>2)::uuid,c2->>'key','Gift med Cia Ceta.','Cia Ceta'));
  v_p1:=pg_temp.t6_spouse(c1->>'key'); v_p2:=pg_temp.t6_spouse(c2->>'key');
  IF (SELECT array_agg(marriage_ordinal ORDER BY marriage_ordinal) FROM private.interpretation_party_current
       WHERE interpretation_key IN ((c1->>'key')::uuid,(c2->>'key')::uuid) AND party_role='spouse')<>ARRAY[1,2] THEN
    RAISE EXCEPTION 'RELATION_REUSE_TEST_FAILED: fixturens numre';
  END IF;
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  v_cl:=pg_temp.t6_revise(-66601,post,v_old,v_new,ARRAY['Anna Alfa.','Gift m. Bo Beta.','Gift med Cia Ceta.'],v_actor,'t6-f');
  k:=pg_temp.f5b_claim(-66601,s,'relation.marriage',v_cl[3],'Gift med Cia Ceta.');
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  p:=pg_temp.t6_payload(v_cl[3],k->>'key','Gift med Cia Ceta.','Cia Ceta');
  IF (p->>'marriage_ordinal')::int<>1 THEN RAISE EXCEPTION 'RELATION_REUSE_TEST_FAILED: nummer %',p; END IF;
  v_n:=pg_temp.t6_personas(-66601);
  w:=pg_temp.t6_write(-66601,v_actor,p);
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  IF pg_temp.t6_personas(-66601)<>v_n+1 OR pg_temp.t6_spouse(k->>'key') IN (v_p1,v_p2) OR w->'receipt' ? 'reused' THEN
    RAISE EXCEPTION 'RELATION_REUSE_TEST_FAILED: kun andet ægteskab genfundet %',w->'receipt';
  END IF;
  RAISE NOTICE 'OK: test_kun_andet_aegteskab_genfundet';
END $t$;

-- test_finalize_rejects_manipulated_receipt: (a) en kvittering uden genbrug omskrives (med genberegnet hash) til at
-- påstå genbrug ⇒ finalize afviser med RELATION_PERSONA_REUSE_RECEIPT_INVALID; (b) mellem genbrugets apply og finalize
-- får den genbrugte persona en anden ægtefællepart på en levende nøgle ⇒ samme afvisning.
DO $t$
DECLARE v_actor uuid:='11000000-0000-0000-0000-0000006c3a07'; s jsonb; post jsonb; c jsonb; c2 jsonb; cx jsonb; p jsonb; b jsonb;
  r jsonb; v_old text:='Anna Alfa, født 1800. Gift med Bo Beta.'; v_new text:='Anna Alfa, f. 1800. Gift med Bo Beta.';
  v_persona uuid; v_cl uuid[]; v_err text; v_ev bigint;
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  INSERT INTO person(id,levende,privat,status) VALUES (-66701,false,false,'6c3');
  s:=pg_temp.f5b_source(-66701);
  post:=pg_temp.f5b_post(-66701,s,'T6-G',v_old,ARRAY['Anna Alfa, født 1800.','Gift med Bo Beta.'],-66701,v_actor);
  PERFORM pg_temp.f2a_event_for_state((post->>'principal')::uuid);
  c:=pg_temp.f5b_claim(-66701,s,'relation.marriage',(post->'clauses'->>1)::uuid,'Gift med Bo Beta.');
  p:=pg_temp.t6_payload((post->'clauses'->>1)::uuid,c->>'key','Gift med Bo Beta.','Bo Beta');

  -- (a) kvittering uden genbrug påstår genbrug
  BEGIN
    b:=pg_temp.t6_apply(-66701,v_actor,jsonb_build_object('relation-persona:'||(c->>'key'),p));
    SELECT id,payload->'result_receipt' INTO v_ev,r FROM private.reimport_event
     WHERE batch_id=(b->>'batch')::uuid AND operation='relation_persona';
    IF r ? 'reused' THEN RAISE EXCEPTION 'RELATION_REUSE_TEST_FAILED: genbrug uden revision'; END IF;
    r:=r||jsonb_build_object('reused',true,'mention_id',NULL);
    SET LOCAL session_replication_role=replica;
    UPDATE private.reimport_event SET payload=jsonb_set(payload,'{result_receipt}',r),
      after_sha256=private.reimport_canonical_json_sha256(r) WHERE id=v_ev;
    SET LOCAL session_replication_role=origin;
    PERFORM pg_temp.t6_finalize(b);
    v_err:='ingen fejl';
  EXCEPTION WHEN OTHERS THEN v_err:=SQLERRM;
  END;
  IF v_err NOT LIKE 'RELATION_PERSONA_REUSE_RECEIPT_INVALID%' THEN
    RAISE EXCEPTION 'RELATION_REUSE_TEST_FAILED: manipuleret kvittering gav %',v_err;
  END IF;
  RAISE NOTICE 'OK: test_finalize_rejects_manipulated_receipt (falsk genbrug)';

  -- (b) en anden levende anvendelse af den genbrugte persona før finalize
  PERFORM pg_temp.t6_write(-66701,v_actor,p);
  v_persona:=pg_temp.t6_spouse(c->>'key');
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  v_cl:=pg_temp.t6_revise(-66701,post,v_old,v_new,ARRAY['Anna Alfa, f. 1800.','Gift med Bo Beta.'],v_actor,'t6-g');
  c2:=pg_temp.f5b_claim(-66701,s,'relation.marriage',v_cl[2],'Gift med Bo Beta.');
  cx:=pg_temp.f5b_claim(-66701,s,'relation.marriage',v_cl[2],'Bo Beta.');
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  p:=pg_temp.t6_payload(v_cl[2],c2->>'key','Gift med Bo Beta.','Bo Beta');
  BEGIN
    b:=pg_temp.t6_apply(-66701,v_actor,jsonb_build_object('relation-persona:'||(c2->>'key'),p));
    IF pg_temp.t6_spouse(c2->>'key') IS DISTINCT FROM v_persona THEN RAISE EXCEPTION 'RELATION_REUSE_TEST_FAILED: ikke genbrugt'; END IF;
    INSERT INTO private.interpretation_party(interpretation_key,party_role,version,source_persona_id,marriage_ordinal,post_offset,origin,origin_ref)
      VALUES ((cx->>'key')::uuid,'spouse',1,v_persona,1,0,'relation_persona',gen_random_uuid());
    PERFORM pg_temp.t6_finalize(b);
    v_err:='ingen fejl';
  EXCEPTION WHEN OTHERS THEN v_err:=SQLERRM;
  END;
  IF v_err NOT LIKE 'RELATION_PERSONA_REUSE_RECEIPT_INVALID%' THEN
    RAISE EXCEPTION 'RELATION_REUSE_TEST_FAILED: anden levende anvendelse gav %',v_err;
  END IF;
  RAISE NOTICE 'OK: test_finalize_rejects_manipulated_receipt (anden levende anvendelse)';
END $t$;

-- test_reuse_with_year: en v1-payload med ægtefællens fødselsår (som 5b's). Den gamle årfortolkning forældes med
-- revisionen; ved genbrug skriver writeren en ny årfortolkning på den genbrugte persona (ny nøgle, ny kørsel), og
-- finalize er grøn med year_interpretations 1.
DO $t$
DECLARE v_actor uuid:='11000000-0000-0000-0000-0000006c3a08'; s jsonb; post jsonb; c jsonb; c2 jsonb; p jsonb; w jsonb;
  v_old text:='Anna Alfa, født 1800. Gift med Bo Beta, f. 1801.'; v_new text:='Anna Alfa, f. 1800. Gift med Bo Beta, f. 1801.';
  v_persona uuid; v_cl uuid[]; v_n bigint; v_old_year uuid;
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  INSERT INTO person(id,levende,privat,status) VALUES (-66801,false,false,'6c3');
  s:=pg_temp.f5b_source(-66801);
  post:=pg_temp.f5b_post(-66801,s,'T6-H',v_old,ARRAY['Anna Alfa, født 1800.','Gift med Bo Beta, f. 1801.'],-66801,v_actor);
  PERFORM pg_temp.f2a_event_for_state((post->>'principal')::uuid);
  c:=pg_temp.f5b_claim(-66801,s,'relation.marriage',(post->'clauses'->>1)::uuid,'Gift med Bo Beta, f. 1801.');
  w:=pg_temp.t6_write(-66801,v_actor,
    pg_temp.t6_payload((post->'clauses'->>1)::uuid,c->>'key','Gift med Bo Beta, f. 1801.','Bo Beta','1801'));
  v_persona:=pg_temp.t6_spouse(c->>'key');
  v_old_year:=(w->'receipt'->'year_interpretation_ids'->>0)::uuid;
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  v_cl:=pg_temp.t6_revise(-66801,post,v_old,v_new,ARRAY['Anna Alfa, f. 1800.','Gift med Bo Beta, f. 1801.'],v_actor,'t6-h');
  IF (SELECT status FROM private.interpretation_current
       WHERE interpretation_key=(SELECT interpretation_key FROM private.interpretation WHERE id=v_old_year))<>'superseded' THEN
    RAISE EXCEPTION 'RELATION_REUSE_TEST_FAILED: den gamle årfortolkning er ikke forældet';
  END IF;
  c2:=pg_temp.f5b_claim(-66801,s,'relation.marriage',v_cl[2],'Gift med Bo Beta, f. 1801.');
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  p:=pg_temp.t6_payload(v_cl[2],c2->>'key','Gift med Bo Beta, f. 1801.','Bo Beta','1801');
  v_n:=pg_temp.t6_personas(-66801);
  w:=pg_temp.t6_write(-66801,v_actor,p);
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  IF pg_temp.t6_personas(-66801)<>v_n OR pg_temp.t6_spouse(c2->>'key') IS DISTINCT FROM v_persona
     OR w->'receipt'->'reused'<>'true'::jsonb
     OR w->'result'->'relation_results'->0->'derived_counts'<>'{"mentions":0,"parties":2,"spouse_personas":1,"year_interpretations":1}'
     OR NOT EXISTS (SELECT 1 FROM private.interpretation_current i
                     WHERE i.id=(w->'receipt'->'year_interpretation_ids'->>0)::uuid AND i.source_persona_id=v_persona
                       AND i.predicate='person.birth' AND i.value=to_jsonb('1801'::text) AND i.status='proposed')
     OR (SELECT status FROM private.reimport_batch WHERE id=(w->>'batch')::uuid)<>'finalized' THEN
    RAISE EXCEPTION 'RELATION_REUSE_TEST_FAILED: genbrug med år %',w;
  END IF;
  RAISE NOTICE 'OK: test_reuse_with_year';
END $t$;

-- test_reuse_name_blanktegn: navnet i den gamle mention har et linjeskift og et dobbelt mellemrum (som når et navn krydser
-- et sideskift og sidehoved-projektionen ændrer blanktegnene); det nye spænd har enkelte mellemrum. Navnereglen
-- sammenligner efter saml_blanktegn_v1, så personaen genbruges. Uden blanktegnssamlingen var der ingen kandidat.
DO $t$
DECLARE v_actor uuid:='11000000-0000-0000-0000-0000006c3a0b'; s jsonb; post jsonb; c jsonb; c2 jsonb; p jsonb; w jsonb;
  v_old text:=E'Anna Alfa. Gift med Bo\nBo  Beta.'; v_new text:='Anna Alfa. Gift med Bo Bo Beta.';
  v_persona uuid; v_cl uuid[]; v_n bigint;
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  INSERT INTO person(id,levende,privat,status) VALUES (-67201,false,false,'6c3');
  s:=pg_temp.f5b_source(-67201);
  post:=pg_temp.f5b_post(-67201,s,'T6-K',v_old,ARRAY['Anna Alfa.',E'Gift med Bo\nBo  Beta.'],-67201,v_actor);
  PERFORM pg_temp.f2a_event_for_state((post->>'principal')::uuid);
  c:=pg_temp.f5b_claim(-67201,s,'relation.marriage',(post->'clauses'->>1)::uuid,E'Gift med Bo\nBo  Beta.');
  PERFORM pg_temp.t6_write(-67201,v_actor,
    pg_temp.t6_payload((post->'clauses'->>1)::uuid,c->>'key',E'Gift med Bo\nBo  Beta.',E'Bo\nBo  Beta'));
  v_persona:=pg_temp.t6_spouse(c->>'key');
  IF (SELECT sm.verbatim_text FROM private.source_persona_mention spm JOIN private.source_mention sm ON sm.id=spm.mention_id
       WHERE spm.persona_id=v_persona AND spm.mention_role='spouse')<>E'Bo\nBo  Beta' THEN
    RAISE EXCEPTION 'RELATION_REUSE_TEST_FAILED: fixturens mention har ikke de oprindelige blanktegn';
  END IF;
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  v_cl:=pg_temp.t6_revise(-67201,post,v_old,v_new,ARRAY['Anna Alfa.','Gift med Bo Bo Beta.'],v_actor,'t6-k');
  c2:=pg_temp.f5b_claim(-67201,s,'relation.marriage',v_cl[2],'Gift med Bo Bo Beta.');
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  p:=pg_temp.t6_payload(v_cl[2],c2->>'key','Gift med Bo Bo Beta.','Bo Bo Beta');
  v_n:=pg_temp.t6_personas(-67201);
  w:=pg_temp.t6_write(-67201,v_actor,p);
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  IF pg_temp.t6_personas(-67201)<>v_n OR pg_temp.t6_spouse(c2->>'key') IS DISTINCT FROM v_persona
     OR w->'receipt'->'reused' IS DISTINCT FROM 'true'::jsonb OR w->'receipt'->'mention_id'<>'null'::jsonb
     OR (SELECT status FROM private.reimport_batch WHERE id=(w->>'batch')::uuid)<>'finalized' THEN
    RAISE EXCEPTION 'RELATION_REUSE_TEST_FAILED: blanktegn i navnet genbrugte ikke %',w->'receipt';
  END IF;
  RAISE NOTICE 'OK: test_reuse_name_blanktegn';
END $t$;

-- §4.7 pkt. 3 (én part pr. persona): efter genbruget har personaen to ægtefælleparter, én på den forældede nøgle og én
-- på den nye. persona_family_context og spouse_principal_person tæller kun parter på nøgler, der aktuelt er proposed
-- eller accepted, og giver efter genbruget samme resultat som før revisionen. Mellem revisionen og genbruget har
-- personaen ingen levende part og dermed ingen kontekst.
-- test_context_after_reuse_bound: ægteskabet er afgjort og bundet før revisionen (som test_reuse_name_same_place).
DO $t$
DECLARE v_actor uuid:='11000000-0000-0000-0000-0000006c3a09'; s jsonb; post jsonb; c jsonb; c2 jsonb; p jsonb; w jsonb;
  v_old text:='Anna Alfa. Gift med Bo Beta. Datter Dora Delta.'; v_new text:='Anna Alfa. Gift med Bo Beta. Datter Dora.';
  v_persona uuid; v_cl uuid[]; v_fc jsonb; v_hp bigint;
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  INSERT INTO person(id,levende,privat,status) VALUES (-66901,false,false,'6c3'),(-66902,false,false,'6c3');
  s:=pg_temp.f5b_source(-66901);
  post:=pg_temp.f5b_post(-66901,s,'T6-I',v_old,ARRAY['Anna Alfa.','Gift med Bo Beta.','Datter Dora Delta.'],-66901,v_actor);
  PERFORM pg_temp.f2a_event_for_state((post->>'principal')::uuid);
  c:=pg_temp.f5b_claim(-66901,s,'relation.marriage',(post->'clauses'->>1)::uuid,'Gift med Bo Beta.');
  PERFORM pg_temp.t6_write(-66901,v_actor,pg_temp.t6_payload((post->'clauses'->>1)::uuid,c->>'key','Gift med Bo Beta.','Bo Beta'));
  v_persona:=pg_temp.t6_spouse(c->>'key');
  PERFORM pg_temp.t6_bind(-66901,-66901,-66902,v_persona,c->>'key',v_actor);
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  v_fc:=private.persona_family_context(v_persona);
  v_hp:=private.spouse_principal_person(v_persona);
  IF v_fc IS NULL OR v_hp IS DISTINCT FROM -66901 OR jsonb_array_length(v_fc->'families')<>1
     OR (v_fc->>'marriage_ordinal')::int<>1 OR (v_fc->>'spouse_identity_version')::int<>1 THEN
    RAISE EXCEPTION 'RELATION_REUSE_TEST_FAILED: fixturens kontekst før revisionen % %',v_fc,v_hp;
  END IF;

  v_cl:=pg_temp.t6_revise(-66901,post,v_old,v_new,ARRAY['Anna Alfa.','Gift med Bo Beta.','Datter Dora.'],v_actor,'t6-i');
  IF private.persona_family_context(v_persona) IS NOT NULL OR private.spouse_principal_person(v_persona) IS NOT NULL THEN
    RAISE EXCEPTION 'RELATION_REUSE_TEST_FAILED: kontekst fra en forældet part % %',
      private.persona_family_context(v_persona),private.spouse_principal_person(v_persona);
  END IF;
  c2:=pg_temp.f5b_claim(-66901,s,'relation.marriage',v_cl[2],'Gift med Bo Beta.');
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  w:=pg_temp.t6_write(-66901,v_actor,pg_temp.t6_payload(v_cl[2],c2->>'key','Gift med Bo Beta.','Bo Beta'));
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  IF w->'receipt'->'reused' IS DISTINCT FROM 'true'::jsonb OR pg_temp.t6_spouse(c2->>'key') IS DISTINCT FROM v_persona
     OR (SELECT count(*) FROM private.interpretation_party_current
          WHERE source_persona_id=v_persona AND party_role='spouse')<>2 THEN
    RAISE EXCEPTION 'RELATION_REUSE_TEST_FAILED: fixturen genbrugte ikke %',w->'receipt';
  END IF;
  IF private.persona_family_context(v_persona) IS DISTINCT FROM v_fc THEN
    RAISE EXCEPTION 'RELATION_REUSE_TEST_FAILED: persona_family_context efter genbrug % (før %)',
      private.persona_family_context(v_persona),v_fc;
  END IF;
  IF private.spouse_principal_person(v_persona) IS DISTINCT FROM v_hp THEN
    RAISE EXCEPTION 'RELATION_REUSE_TEST_FAILED: spouse_principal_person efter genbrug %',private.spouse_principal_person(v_persona);
  END IF;
  RAISE NOTICE 'OK: test_context_after_reuse_bound';
END $t$;

-- test_context_after_reuse_unbound: ægtefællens identitet er uafgjort, så webkøens detalje udleder en årsag. Efter
-- genbruget er den den samme som før revisionen, ikke context_unavailable.
DO $t$
DECLARE v_actor uuid:='11000000-0000-0000-0000-0000006c3a0a'; s jsonb; post jsonb; c jsonb; c2 jsonb; w jsonb;
  v_old text:='Anna Alfa. Gift med Bo Beta. Datter Dora Delta.'; v_new text:='Anna Alfa. Gift med Bo Beta. Datter Dora.';
  v_persona uuid; v_cl uuid[]; v_fc jsonb; v_hp bigint; d jsonb;
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  INSERT INTO person(id,levende,privat,status) VALUES (-67001,false,false,'6c3'),(-67002,false,false,'6c3');
  s:=pg_temp.f5b_source(-67001);
  post:=pg_temp.f5b_post(-67001,s,'T6-J',v_old,ARRAY['Anna Alfa.','Gift med Bo Beta.','Datter Dora Delta.'],-67001,v_actor);
  PERFORM pg_temp.f2a_event_for_state((post->>'principal')::uuid);
  PERFORM pg_temp.f5b_family(-67001,-67002,1);
  c:=pg_temp.f5b_claim(-67001,s,'relation.marriage',(post->'clauses'->>1)::uuid,'Gift med Bo Beta.');
  PERFORM pg_temp.t6_write(-67001,v_actor,pg_temp.t6_payload((post->'clauses'->>1)::uuid,c->>'key','Gift med Bo Beta.','Bo Beta'));
  v_persona:=pg_temp.t6_spouse(c->>'key');
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  v_fc:=private.persona_family_context(v_persona);
  v_hp:=private.spouse_principal_person(v_persona);
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  SET LOCAL ROLE authenticated;
  d:=red_source_persona_detail(v_persona);
  RESET ROLE;
  IF v_fc IS NULL OR v_hp IS DISTINCT FROM -67001 OR d->>'review_reason' IS DISTINCT FROM 'partner_not_candidate'
     OR (d#>>'{family_context,marriage_ordinal}')::int IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'RELATION_REUSE_TEST_FAILED: fixturens detalje før revisionen % %',v_fc,d;
  END IF;

  v_cl:=pg_temp.t6_revise(-67001,post,v_old,v_new,ARRAY['Anna Alfa.','Gift med Bo Beta.','Datter Dora.'],v_actor,'t6-j');
  c2:=pg_temp.f5b_claim(-67001,s,'relation.marriage',v_cl[2],'Gift med Bo Beta.');
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  w:=pg_temp.t6_write(-67001,v_actor,pg_temp.t6_payload(v_cl[2],c2->>'key','Gift med Bo Beta.','Bo Beta'));
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  IF w->'receipt'->'reused' IS DISTINCT FROM 'true'::jsonb OR pg_temp.t6_spouse(c2->>'key') IS DISTINCT FROM v_persona THEN
    RAISE EXCEPTION 'RELATION_REUSE_TEST_FAILED: fixturen genbrugte ikke %',w->'receipt';
  END IF;
  IF private.persona_family_context(v_persona) IS DISTINCT FROM v_fc
     OR private.spouse_principal_person(v_persona) IS DISTINCT FROM v_hp THEN
    RAISE EXCEPTION 'RELATION_REUSE_TEST_FAILED: kontekst efter genbrug % % (før % %)',
      private.persona_family_context(v_persona),private.spouse_principal_person(v_persona),v_fc,v_hp;
  END IF;
  SET LOCAL ROLE authenticated;
  IF red_source_persona_detail(v_persona)->>'review_reason' IS DISTINCT FROM d->>'review_reason'
     OR red_source_persona_detail(v_persona)->'family_context' IS DISTINCT FROM d->'family_context'
     OR red_source_persona_detail(v_persona)->'principal_partners' IS DISTINCT FROM d->'principal_partners' THEN
    RAISE EXCEPTION 'RELATION_REUSE_TEST_FAILED: detaljen efter genbrug %',red_source_persona_detail(v_persona);
  END IF;
  RESET ROLE;
  RAISE NOTICE 'OK: test_context_after_reuse_unbound';
END $t$;

ROLLBACK;
\echo PASS test-relation-persona-reuse
