-- Trin 6c-3a (spec 2026-11-07-trin6c3-a6b-resten-design.md §4.7 pkt. 1): genbruget af en ægtefælle-persona er
-- serialiseret pr. kilde. To relation_persona-batches på samme kilde under forskellige writer-profiler deler ikke
-- lock_reimport_writer-låsen, og finalize ser kun sin egen part; uden kildelåsen før kandidatopslaget kunne begge genbruge
-- samme persona og committe to levende ægtefælleparter.
-- Forløb: session A (dblink) genbruger personaen for en ny påstand (apply og finalize) og holder transaktionen åben.
-- Imens kommer en påstand mere på den samme klausul (kortere spænd, så den nu får ægteskabsnummer 1), og en batch under en
-- anden profil på samme kilde autoriseres for den. Session B (dblink) skal vente på kildelåsen og, efter A's commit, oprette
-- en ny persona. Denne session koordinerer. Opsætningen committes, så testen kører i en ENGANGSBASE (CI: sidst i
-- ci6a_text_revision) og kun én gang pr. base. Kræver kontrakt v2 (reimport-writer-v2-bootstrap.sql). Alt syntetisk.
\set ON_ERROR_STOP on
CREATE EXTENSION IF NOT EXISTS dblink;

-- Opsætning (committes): posten, ægteskabet skrevet af writeren, revisionen der flytter navnet, den nye påstand og
-- batch A for den. Hjælperne i pg_temp lever resten af sessionen.
BEGIN ISOLATION LEVEL READ COMMITTED;
\ir fixtures/relation-5b.sql
\ir fixtures/relation-2a.sql
\ir fixtures/source-text-revision.sql
\ir fixtures/relation-persona-reuse-helpers.sql
CREATE TEMP TABLE t6l_fx(k text PRIMARY KEY, v text NOT NULL) ON COMMIT PRESERVE ROWS;
DO $setup$
DECLARE v_actor uuid:='11000000-0000-0000-0000-0000006c3a0c'; s jsonb; post jsonb; c jsonb; c2 jsonb; p2 jsonb; fx jsonb;
  r jsonb; ba jsonb; v_cl uuid[]; v_persona uuid;
  v_old text:='Anna Alfa, født 1800. Gift med Bo Beta.'; v_new text:='Anna Alfa, f. 1800. Gift med Bo Beta.';
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  INSERT INTO person(id,levende,privat,status) VALUES (-67301,false,false,'6c3 lås');
  s:=pg_temp.f5b_source(-67301);
  post:=pg_temp.f5b_post(-67301,s,'T6-L',v_old,ARRAY['Anna Alfa, født 1800.','Gift med Bo Beta.'],-67301,v_actor);
  PERFORM pg_temp.f2a_event_for_state((post->>'principal')::uuid);
  c:=pg_temp.f5b_claim(-67301,s,'relation.marriage',(post->'clauses'->>1)::uuid,'Gift med Bo Beta.');
  PERFORM pg_temp.t6_write(-67301,v_actor,pg_temp.t6_payload((post->'clauses'->>1)::uuid,c->>'key','Gift med Bo Beta.','Bo Beta'));
  v_persona:=pg_temp.t6_spouse(c->>'key');
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  fx:=jsonb_build_object('source',-67301,'record_key',post->>'key','helpost',post->>'helpost','text',v_old,
    'actor',v_actor,'profile',pg_temp.t5_profile(-67301));
  r:=pg_temp.t5_apply(fx,pg_temp.t5_payload(fx,v_new,ARRAY['Anna Alfa, f. 1800.','Gift med Bo Beta.']),'t6-l');
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  IF jsonb_array_length(r->'superseded_keys')=0 THEN RAISE EXCEPTION 'RELATION_REUSE_LOCK_TEST_FAILED: revisionen'; END IF;
  v_cl:=ARRAY(SELECT id FROM private.clause_observation_current WHERE parent_observation_id=(post->>'helpost')::uuid
               ORDER BY clause_ordinal);
  c2:=pg_temp.f5b_claim(-67301,s,'relation.marriage',v_cl[2],'Gift med Bo Beta.');
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  p2:=pg_temp.t6_payload(v_cl[2],c2->>'key','Gift med Bo Beta.','Bo Beta');
  IF (p2->>'marriage_ordinal')::int<>1 THEN RAISE EXCEPTION 'RELATION_REUSE_LOCK_TEST_FAILED: nummer %',p2; END IF;
  ba:=pg_temp.f5b_batch(-67301,v_actor,
    (SELECT jsonb_build_object('profile_id',profile_id,'profile_sha256',profile_sha256) FROM private.reimport_writer_profile
      WHERE source_id=-67301 AND profile_id='relation-5b'),
    jsonb_build_object('relation-persona:'||(c2->>'key'),p2));
  INSERT INTO t6l_fx(k,v) VALUES ('actor',v_actor::text),('persona',v_persona::text),('src',s::text),('clause',v_cl[2]::text),
    ('key_a',c2->>'key'),('batch_a',ba->>'batch'),('payload_a',p2::text),
    ('conn',format('dbname=%s port=%s host=%s',current_database(),current_setting('port'),
                   split_part(current_setting('unix_socket_directories'),',',1)));
END $setup$;
COMMIT;

CREATE FUNCTION pg_temp.t6l(p_k text) RETURNS text LANGUAGE sql AS $$ SELECT v FROM t6l_fx WHERE k=p_k $$;

-- Session A: genbruger personaen (apply og finalize) og holder transaktionen åben.
DO $a$
DECLARE v_res text;
BEGIN
  PERFORM dblink_connect('t6l_a',pg_temp.t6l('conn'));
  PERFORM dblink_exec('t6l_a','BEGIN ISOLATION LEVEL READ COMMITTED');
  PERFORM * FROM dblink('t6l_a',format('SELECT set_config(''request.jwt.claim.sub'',%L,true)',pg_temp.t6l('actor'))) AS t(x text);
  PERFORM dblink_exec('t6l_a','SET LOCAL ROLE authenticated');
  SELECT x INTO v_res FROM dblink('t6l_a',format(
    'SELECT public.red_apply_reimport_relation_persona(%L::uuid,%L,%L::jsonb)->>''spouse_source_persona_id''',
    pg_temp.t6l('batch_a'),'relation-persona:'||pg_temp.t6l('key_a'),pg_temp.t6l('payload_a'))) AS t(x text);
  IF v_res IS DISTINCT FROM pg_temp.t6l('persona') THEN
    RAISE EXCEPTION 'RELATION_REUSE_LOCK_TEST_FAILED: session A genbrugte ikke personaen (%)',v_res;
  END IF;
  PERFORM * FROM dblink('t6l_a',format('SELECT public.red_finalize_reimport(%L::uuid)::text',pg_temp.t6l('batch_a'))) AS t(x text);
END $a$;

-- Mens A er åben: en påstand mere på klausulen og batch B under en anden profil på samme kilde (committes).
BEGIN ISOLATION LEVEL READ COMMITTED;
DO $mid$
DECLARE c3 jsonb; p3 jsonb; bb jsonb; v_cfg jsonb; v_actor uuid:=pg_temp.t6l('actor')::uuid;
BEGIN
  c3:=pg_temp.f5b_claim(-67301,pg_temp.t6l('src')::jsonb,'relation.marriage',pg_temp.t6l('clause')::uuid,'Gift med Bo Beta');
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  p3:=pg_temp.t6_payload(pg_temp.t6l('clause')::uuid,c3->>'key','Gift med Bo Beta','Bo Beta');
  IF (p3->>'marriage_ordinal')::int<>1 THEN RAISE EXCEPTION 'RELATION_REUSE_LOCK_TEST_FAILED: B-nummer %',p3; END IF;
  SELECT writer_config INTO v_cfg FROM private.reimport_writer_profile WHERE source_id=-67301 AND profile_id='relation-5b';
  INSERT INTO private.reimport_writer_profile(source_id,profile_id,profile_version,profile_sha256,writer_config)
    VALUES (-67301,'relation-5b-b','relation-persona-v1',private.reimport_canonical_json_sha256(v_cfg),v_cfg);
  bb:=pg_temp.f5b_batch(-67301,v_actor,
    jsonb_build_object('profile_id','relation-5b-b','profile_sha256',private.reimport_canonical_json_sha256(v_cfg)),
    jsonb_build_object('relation-persona:'||(c3->>'key'),p3));
  INSERT INTO t6l_fx(k,v) VALUES ('key_b',c3->>'key'),('batch_b',bb->>'batch'),('payload_b',p3::text);
END $mid$;
COMMIT;

-- Session B: starter sin apply og finalize; denne session venter (højst 10 s), til B venter på netop kildelåsen, eller til B er
-- færdig. pg_locks fryses i transaktionen; pg_stat_clear_snapshot giver et nyt øjebliksbillede.
DO $b$
DECLARE v_pid int; v_blocked boolean:=false; v_k bigint:=hashtextextended('daa-relation-persona-spouse:-67301',0); i int;
BEGIN
  PERFORM dblink_connect('t6l_b',pg_temp.t6l('conn'));
  PERFORM dblink_exec('t6l_b','BEGIN ISOLATION LEVEL READ COMMITTED');
  PERFORM * FROM dblink('t6l_b',format('SELECT set_config(''request.jwt.claim.sub'',%L,true)',pg_temp.t6l('actor'))) AS t(x text);
  PERFORM dblink_exec('t6l_b','SET LOCAL ROLE authenticated');
  SELECT x INTO v_pid FROM dblink('t6l_b','SELECT pg_backend_pid()') AS t(x int);
  -- Apply og finalize i ét kald (FROM evalueres før mållisten), som i ceremonien, hvor begin/apply/finalize er én
  -- transaktion: uden låsen ser B's finalize kun sin egen part.
  PERFORM dblink_send_query('t6l_b',format(
    'SELECT public.red_finalize_reimport(%L::uuid)::text '
    'FROM (SELECT public.red_apply_reimport_relation_persona(%L::uuid,%L,%L::jsonb) AS a OFFSET 0) s',
    pg_temp.t6l('batch_b'),pg_temp.t6l('batch_b'),'relation-persona:'||pg_temp.t6l('key_b'),pg_temp.t6l('payload_b')));
  FOR i IN 1..200 LOOP
    PERFORM pg_stat_clear_snapshot();
    IF EXISTS (SELECT 1 FROM pg_locks l
                WHERE l.pid=v_pid AND l.locktype='advisory' AND NOT l.granted AND l.objsubid=1
                  AND l.classid=((v_k>>32)&4294967295)::oid AND l.objid=(v_k&4294967295)::oid) THEN
      v_blocked:=true; EXIT;
    END IF;
    EXIT WHEN dblink_is_busy('t6l_b')=0;
    PERFORM pg_sleep(0.05);
  END LOOP;
  INSERT INTO t6l_fx(k,v) VALUES ('blocked',v_blocked::text);
END $b$;

-- A committer; B's resultat og commit; derefter tilstanden.
DO $end$
DECLARE v_res text; v_err text; v_live bigint; v_spouse_b uuid; v_receipt jsonb;
BEGIN
  PERFORM dblink_exec('t6l_a','COMMIT');
  PERFORM dblink_disconnect('t6l_a');
  BEGIN
    SELECT x INTO v_res FROM dblink_get_result('t6l_b') AS t(x text);
    PERFORM * FROM dblink_get_result('t6l_b') AS t(x text);
    PERFORM dblink_exec('t6l_b','COMMIT');
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT;
  END;
  BEGIN PERFORM dblink_disconnect('t6l_b'); EXCEPTION WHEN OTHERS THEN NULL; END;
  SELECT count(*) INTO v_live FROM private.interpretation_party_current pc
    JOIN private.interpretation_current ic ON ic.interpretation_key=pc.interpretation_key
   WHERE pc.party_role='spouse' AND pc.source_persona_id=pg_temp.t6l('persona')::uuid AND ic.status IN ('proposed','accepted');
  v_spouse_b:=pg_temp.t6_spouse(pg_temp.t6l('key_b'));
  SELECT e.payload->'result_receipt' INTO v_receipt FROM private.reimport_event e
   WHERE e.batch_id=pg_temp.t6l('batch_b')::uuid AND e.operation='relation_persona';
  IF v_live<>1 THEN
    RAISE EXCEPTION 'RELATION_REUSE_LOCK_TEST_FAILED: personaen har % levende ægtefælleparter (B ventede: %, B-fejl: %)',
      v_live,pg_temp.t6l('blocked'),coalesce(v_err,'ingen');
  END IF;
  IF pg_temp.t6l('blocked')<>'true' THEN
    RAISE EXCEPTION 'RELATION_REUSE_LOCK_TEST_FAILED: session B ventede ikke på kildelåsen';
  END IF;
  IF v_err IS NOT NULL OR v_spouse_b IS NULL OR v_spouse_b=pg_temp.t6l('persona')::uuid OR v_receipt ? 'reused'
     OR (SELECT status FROM private.reimport_batch WHERE id=pg_temp.t6l('batch_b')::uuid)<>'finalized' THEN
    RAISE EXCEPTION 'RELATION_REUSE_LOCK_TEST_FAILED: session B efter A''s commit (fejl %, kvittering %)',v_err,v_receipt;
  END IF;
  RAISE NOTICE 'OK: test_reuse_lock (B ventede på kildelåsen og oprettede en ny persona efter A''s commit)';
END $end$;
\echo PASS test-relation-persona-reuse-lock
