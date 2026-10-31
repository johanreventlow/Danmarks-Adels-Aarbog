-- Trin 6b Task 7: fortrydelse af en publication_identity-batch (ceremoni C, spec §6). Kræver kontrakt v2 som
-- test-publication-identity.sql, hvis fixtures genbruges. Alt syntetisk; én transaktion, rulles tilbage. Ingen navne eller
-- posttekst i output.
\set ON_ERROR_STOP on
\i tests/sql/fixtures/publication-identity.sql
BEGIN;

CREATE FUNCTION pg_temp.expect(p_case text, p_got text, p_token text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF p_got IS NULL OR p_got NOT LIKE p_token||'%' THEN
    RAISE EXCEPTION 'PUBLICATION_REVERSAL_TEST_FAILED: % forventede % fik %',p_case,p_token,p_got; END IF;
END $$;

-- Autorisation som redaktøren (service_role-funktionen kræver redaktør-claim) for en batch.
CREATE FUNCTION pg_temp.pr_auth(p_world jsonb, p_batch uuid) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_id uuid;
BEGIN
  PERFORM set_config('request.jwt.claim.sub',p_world->'src'->>'actor',true);
  PERFORM set_config('role','service_role',true);
  v_id:=public.red_authorize_reimport_reversal(p_batch,gen_random_uuid(),clock_timestamp()+interval '10 minutes');
  RESET role;
  RETURN v_id;
EXCEPTION WHEN OTHERS THEN RESET role; RAISE;
END $$;

CREATE FUNCTION pg_temp.pr_reverse(p_world jsonb, p_batch uuid, p_auth uuid) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_res jsonb;
BEGIN
  PERFORM set_config('request.jwt.claim.sub',p_world->'src'->>'actor',true);
  PERFORM set_config('role','authenticated',true);
  v_res:=public.red_reverse_reimport_publication(p_batch,p_auth);
  RESET role;
  RETURN v_res;
EXCEPTION WHEN OTHERS THEN RESET role; RAISE;
END $$;

CREATE FUNCTION pg_temp.pr_try(p_world jsonb, p_batch uuid, p_auth uuid) RETURNS text LANGUAGE plpgsql AS $$
BEGIN
  PERFORM pg_temp.pr_reverse(p_world,p_batch,p_auth);
  RETURN 'OK';
EXCEPTION WHEN OTHERS THEN RETURN SQLERRM;
END $$;

-- Kandidatkørslen for en verden (svag, ét kandidatmedlem uden årstal); verden med kørslens id i nøglen 'run'. Inputtet
-- rummer alle personer i basen (red_match_personer), så kørslerne registreres, efter at alle verdener og staged-markeringer
-- findes; ellers giver finalize PUBLICATION_IDENTITY_INPUT_DRIFT.
CREATE FUNCTION pg_temp.pr_run(w jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_c jsonb:='[]'::jsonb; v_i int; v_base bigint:=(w->'src'->>'source')::bigint;
BEGIN
  FOR v_i IN 1..jsonb_array_length(w->'personas') LOOP
    v_c:=v_c||pg_temp.pi_cand(pg_temp.pi_persona(w,v_i),v_base*1000-v_i,1,
                              jsonb_build_array(pg_temp.pi_ms(v_base*1000-v_i,0.95,ARRAY['name'])));
  END LOOP;
  RETURN w||jsonb_build_object('run',pg_temp.pi_run(w,'{"topK":10,"autoCutoff":0.9,"controlMargin":0.05}',v_c));
END $$;

-- En finaliseret C-batch over de givne personas (svag, S), alle mod verdenens kørsel. Codex 6B-01: finalize kræver hele
-- B-batchens kontrolmængde, så personas uden for [from,to] skal være staged (disposition) eller have en identitet.
CREATE FUNCTION pg_temp.pr_c(p_world jsonb, p_tag text, p_from int, p_to int) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_payloads jsonb:='[]'::jsonb; v_i int; v_p jsonb; v_batch uuid; v_run uuid:=(p_world->>'run')::uuid;
BEGIN
  FOR v_i IN p_from..p_to LOOP
    v_payloads:=v_payloads||jsonb_build_array(pg_temp.pi_payload(p_world,v_i,v_run,'svag','S'));
  END LOOP;
  v_batch:=pg_temp.pi_begin(p_world,p_tag,pg_temp.pi_elements(v_payloads));
  FOR v_i IN p_from..p_to LOOP
    v_p:=v_payloads->(v_i-p_from);
    PERFORM pg_temp.pi_apply(p_world,v_batch,pg_temp.pi_el(v_p),v_p);
  END LOOP;
  PERFORM pg_temp.pi_finalize(p_world,v_batch);
  RETURN v_batch;
END $$;

-- 0) Fladen: kun authenticated; hverken anon eller service_role.
DO $surface$
BEGIN
  IF to_regprocedure('public.red_reverse_reimport_publication(uuid,uuid)') IS NULL THEN
    RAISE EXCEPTION 'PUBLICATION_REVERSAL_TEST_FAILED: funktionen mangler'; END IF;
  IF has_function_privilege('anon','public.red_reverse_reimport_publication(uuid,uuid)','EXECUTE')
     OR has_function_privilege('service_role','public.red_reverse_reimport_publication(uuid,uuid)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.red_reverse_reimport_publication(uuid,uuid)','EXECUTE') THEN
    RAISE EXCEPTION 'PUBLICATION_REVERSAL_TEST_FAILED: rettigheder'; END IF;
  RAISE NOTICE 'OK: funktionsfladen';
END $surface$;

-- 1) Verdener, én pr. scenarie (Codex 6B-01: hver C dækker hele sin B-batch): fortrydelse (4 personas, den 4. staged),
--    versionsdrift (2), manglende kvittering (1), to C-batches til afvisningerne (1 + 1) og en åben batch (1).
CREATE TEMP TABLE t7(k text PRIMARY KEY, v jsonb);
DO $world$
DECLARE v_k text;
BEGIN
  INSERT INTO t7 VALUES ('happy',pg_temp.pi_world(-6710,'11000000-0000-0000-0000-00000006b710',4)),
    ('drift',pg_temp.pi_world(-6711,'11000000-0000-0000-0000-00000006b710',2)),
    ('receipt',pg_temp.pi_world(-6712,'11000000-0000-0000-0000-00000006b710',1)),
    ('x1',pg_temp.pi_world(-6713,'11000000-0000-0000-0000-00000006b710',1)),
    ('x2',pg_temp.pi_world(-6714,'11000000-0000-0000-0000-00000006b710',1)),
    ('open',pg_temp.pi_world(-6715,'11000000-0000-0000-0000-00000006b710',1));
  UPDATE public.person SET staged=true WHERE id=-6710004;
  FOR v_k IN SELECT k FROM t7 LOOP
    UPDATE t7 SET v=pg_temp.pr_run(v) WHERE k=v_k;
  END LOOP;
  RAISE NOTICE 'OK: verdener (fortrydelse, drift, kvittering, afvisninger)';
END $world$;

-- 2) Fortrydelse af C: identiteterne bliver superseded, version 2; ingen venter; batch og autorisation; ny fortrydelse afvises.
DO $happy$
DECLARE
  w jsonb:=(SELECT v FROM t7 WHERE k='happy');
  v_batch uuid; v_a1 uuid; v_a2 uuid; v_res jsonb; v_i int; v_id private.source_persona_identity%ROWTYPE; v_ev private.reimport_event%ROWTYPE;
BEGIN
  v_batch:=pg_temp.pr_c(w,'rev-ok',1,3);
  -- C er finaliseret: personaerne venter ikke, heller ikke den staged (4), som C frigiver uden identitet
  IF EXISTS (SELECT 1 FROM generate_series(1,4) i WHERE private.persona_awaiting_control(pg_temp.pi_persona(w,i))) THEN
    RAISE EXCEPTION 'PUBLICATION_REVERSAL_TEST_FAILED: venter før fortrydelse'; END IF;
  v_a1:=pg_temp.pr_auth(w,v_batch); v_a2:=pg_temp.pr_auth(w,v_batch);
  v_res:=pg_temp.pr_reverse(w,v_batch,v_a1);
  IF v_res->>'status'<>'reversed' OR (v_res->>'reversed_identities')::int<>3
     OR (SELECT status FROM private.reimport_batch WHERE id=v_batch)<>'reversed'
     OR (SELECT status FROM private.reimport_authorization WHERE id=v_a1)<>'consumed' THEN
    RAISE EXCEPTION 'PUBLICATION_REVERSAL_TEST_FAILED: resultat %',v_res; END IF;
  FOR v_i IN 1..3 LOOP
    SELECT * INTO v_id FROM private.source_persona_identity WHERE source_persona_id=pg_temp.pi_persona(w,v_i);
    IF v_id.version<>2 OR v_id.decision_status<>'superseded' OR v_id.canonical_person_id IS NOT NULL
       OR v_id.evidence->>'reversed_batch_id'<>v_batch::text THEN
      RAISE EXCEPTION 'PUBLICATION_REVERSAL_TEST_FAILED: identitet % (%,%)',v_i,v_id.version,v_id.decision_status; END IF;
    -- personaen har en identitetsrække og venter derfor ikke på kontrol (batchen er reversed og tæller ikke som frigivelse)
    IF private.persona_awaiting_control(pg_temp.pi_persona(w,v_i)) THEN
      RAISE EXCEPTION 'PUBLICATION_REVERSAL_TEST_FAILED: % venter efter fortrydelse',v_i; END IF;
  END LOOP;
  -- den staged persona uden for batchen er urørt (ingen identitet) og venter igen, da den fortrudte C ikke frigiver
  IF EXISTS (SELECT 1 FROM private.source_persona_identity WHERE source_persona_id=pg_temp.pi_persona(w,4))
     OR NOT private.persona_awaiting_control(pg_temp.pi_persona(w,4)) THEN
    RAISE EXCEPTION 'PUBLICATION_REVERSAL_TEST_FAILED: urørt persona'; END IF;
  -- reversal-hændelsen
  SELECT * INTO v_ev FROM private.reimport_event WHERE batch_id=v_batch AND operation='reversal';
  IF v_ev.id IS NULL OR v_ev.element_id<>'publication-identity-reversal:'||v_a1::text
     OR (SELECT count(*) FROM private.reimport_event WHERE batch_id=v_batch AND operation='publication_identity')<>3 THEN
    RAISE EXCEPTION 'PUBLICATION_REVERSAL_TEST_FAILED: reversal-hændelse'; END IF;
  -- en anden fortrydelse af samme batch (anden, allerede udstedt autorisation)
  PERFORM pg_temp.expect('anden fortrydelse',pg_temp.pr_try(w,v_batch,v_a2),'REIMPORT_WRITER_REVERSAL_INVALID');
  -- og den forbrugte autorisation
  PERFORM pg_temp.expect('forbrugt autorisation',pg_temp.pr_try(w,v_batch,v_a1),'REIMPORT_WRITER_REVERSAL_INVALID');
  RAISE NOTICE 'OK: fortrydelse af C (superseded, version 2, ingen venter, anden fortrydelse afvist)';
END $happy$;

-- 3) Versionsdrift: en senere menneskelig afgørelse på den persona, kernen/versionsvagten rammer SIDST i id-orden,
--    så resten af løkken allerede har kørt og skal rulles tilbage.
DO $drift$
DECLARE
  w jsonb:=(SELECT v FROM t7 WHERE k='drift');
  v_batch uuid; v_a uuid; v_last uuid; v_first uuid; v_last_i int; v_res text;
BEGIN
  v_batch:=pg_temp.pr_c(w,'rev-drift',1,2);
  v_last:=greatest(pg_temp.pi_persona(w,1),pg_temp.pi_persona(w,2)); v_first:=least(pg_temp.pi_persona(w,1),pg_temp.pi_persona(w,2));
  v_last_i:=CASE WHEN v_last=pg_temp.pi_persona(w,1) THEN 1 ELSE 2 END;
  v_a:=pg_temp.pr_auth(w,v_batch);
  -- menneskelig afgørelse efter C (version 1 → 2)
  PERFORM set_config('request.jwt.claim.sub',w->'src'->>'actor',true);
  PERFORM private.decide_source_persona_identity(v_last,-6711000-v_last_i,1,'accepted','{"basis":"web_detail","note":"t"}','human');
  PERFORM pg_temp.expect('versionsdrift',pg_temp.pr_try(w,v_batch,v_a),'PUBLICATION_REVERSAL_VERSION_DRIFT');
  -- intet er ændret: den første persona er stadig version 1 accepted, batchen finalized, autorisationen udstedt
  IF (SELECT version FROM private.source_persona_identity WHERE source_persona_id=v_first)<>1
     OR (SELECT decision_status FROM private.source_persona_identity WHERE source_persona_id=v_first)<>'accepted'
     OR (SELECT version FROM private.source_persona_identity WHERE source_persona_id=v_last)<>2
     OR (SELECT decision_status FROM private.source_persona_identity WHERE source_persona_id=v_last)<>'accepted'
     OR (SELECT status FROM private.reimport_batch WHERE id=v_batch)<>'finalized'
     OR (SELECT status FROM private.reimport_authorization WHERE id=v_a)<>'issued'
     OR EXISTS (SELECT 1 FROM private.reimport_event WHERE batch_id=v_batch AND operation='reversal') THEN
    RAISE EXCEPTION 'PUBLICATION_REVERSAL_TEST_FAILED: versionsdrift efterlod skrivning'; END IF;
  RAISE NOTICE 'OK: versionsdrift afviser hele fortrydelsen uden skrivning';
END $drift$;

-- 3b) Manglende kvittering: en publication_identity-hændelse uden identity_version giver den tilsigtede
--     REVERSAL_INVALID (ikke VERSION_DRIFT), og intet skrives.
DO $receipt$
DECLARE
  w jsonb:=(SELECT v FROM t7 WHERE k='receipt');
  v_batch uuid; v_a uuid;
BEGIN
  v_batch:=pg_temp.pr_c(w,'rev-receipt',1,1);
  v_a:=pg_temp.pr_auth(w,v_batch);
  SET LOCAL session_replication_role=replica;
  UPDATE private.reimport_event SET payload=jsonb_set(payload,'{result_receipt}',(payload->'result_receipt')-'identity_version')
   WHERE batch_id=v_batch AND operation='publication_identity';
  SET LOCAL session_replication_role=origin;
  PERFORM pg_temp.expect('manglende kvittering',pg_temp.pr_try(w,v_batch,v_a),'REIMPORT_WRITER_REVERSAL_INVALID');
  IF (SELECT status FROM private.reimport_batch WHERE id=v_batch)<>'finalized'
     OR (SELECT version FROM private.source_persona_identity WHERE source_persona_id=pg_temp.pi_persona(w,1))<>1 THEN
    RAISE EXCEPTION 'PUBLICATION_REVERSAL_TEST_FAILED: manglende kvittering efterlod skrivning'; END IF;
  RAISE NOTICE 'OK: manglende kvittering giver REVERSAL_INVALID';
END $receipt$;

-- 4) Afvisninger: en B-batch, en fremmed autorisation, en åben batch, en udløbet autorisation.
DO $reject$
DECLARE
  w jsonb:=(SELECT v FROM t7 WHERE k='x1'); w2 jsonb:=(SELECT v FROM t7 WHERE k='x2'); wo jsonb:=(SELECT v FROM t7 WHERE k='open');
  v_b uuid:=(w->>'b_batch')::uuid; v_c uuid; v_other uuid; v_ab uuid; v_ac uuid; v_p jsonb; v_open uuid; v_n bigint;
BEGIN
  -- B-batchen er finalized, så den kan autoriseres, men har kun publication_persona-hændelser
  v_ab:=pg_temp.pr_auth(w,v_b);
  v_n:=(SELECT count(*) FROM private.reimport_event WHERE batch_id=v_b);
  PERFORM pg_temp.expect('B-batch',pg_temp.pr_try(w,v_b,v_ab),'REIMPORT_WRITER_REVERSAL_INVALID');
  -- Persona 1 hører til SAMME B-batch og er ikke rørt endnu: afvisningen må ikke have ændret B-batchens hændelser eller
  -- forbrugt autorisationen.
  IF (SELECT status FROM private.reimport_batch WHERE id=v_b)<>'finalized'
     OR NOT EXISTS (SELECT 1 FROM private.reimport_event e WHERE e.batch_id=v_b AND e.operation='publication_persona'
                     AND e.payload->'result_receipt'->>'source_persona_id'=pg_temp.pi_persona(w,1)::text)
     OR (SELECT count(*) FROM private.reimport_event WHERE batch_id=v_b)<>v_n
     OR EXISTS (SELECT 1 FROM private.reimport_event e WHERE e.batch_id=v_b AND e.operation<>'publication_persona')
     OR (SELECT status FROM private.reimport_authorization WHERE id=v_ab)<>'issued' THEN
    RAISE EXCEPTION 'PUBLICATION_REVERSAL_TEST_FAILED: B-afvisningen skrev'; END IF;

  -- autorisation for en anden batch
  v_c:=pg_temp.pr_c(w,'rev-x1',1,1); v_other:=pg_temp.pr_c(w2,'rev-x2',1,1);
  v_ac:=pg_temp.pr_auth(w2,v_other);
  PERFORM pg_temp.expect('fremmed autorisation',pg_temp.pr_try(w,v_c,v_ac),'REIMPORT_WRITER_REVERSAL_INVALID');
  -- ukendt batch
  PERFORM pg_temp.expect('ukendt batch',pg_temp.pr_try(w,gen_random_uuid(),v_ac),'REIMPORT_WRITER_REVERSAL_INVALID');
  -- ukendt autorisation
  PERFORM pg_temp.expect('ukendt autorisation',pg_temp.pr_try(w,v_c,gen_random_uuid()),'REIMPORT_WRITER_REVERSAL_INVALID');
  -- åben batch kan ikke autoriseres (red_authorize_reimport_reversal kræver finalized/activated)
  v_p:=pg_temp.pi_payload(wo,1,(wo->>'run')::uuid,'svag','S');
  v_open:=pg_temp.pi_begin(wo,'rev-open',jsonb_build_object(pg_temp.pi_el(v_p),v_p));
  BEGIN
    PERFORM pg_temp.pr_auth(wo,v_open);
    RAISE EXCEPTION 'PUBLICATION_REVERSAL_TEST_FAILED: åben batch autoriseret';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM<>'REIMPORT_WRITER_REVERSAL_INVALID' THEN RAISE; END IF;
  END;
  -- udløbet autorisation
  v_ac:=pg_temp.pr_auth(w,v_c);
  UPDATE private.reimport_authorization SET expires_at=clock_timestamp()-interval '1 second' WHERE id=v_ac;
  PERFORM pg_temp.expect('udløbet',pg_temp.pr_try(w,v_c,v_ac),'REIMPORT_WRITER_REVERSAL_INVALID');
  IF (SELECT status FROM private.reimport_batch WHERE id=v_c)<>'finalized'
     OR EXISTS (SELECT 1 FROM private.source_persona_identity i WHERE i.source_persona_id=pg_temp.pi_persona(w,1) AND i.version<>1) THEN
    RAISE EXCEPTION 'PUBLICATION_REVERSAL_TEST_FAILED: afvisning efterlod skrivning'; END IF;
  RAISE NOTICE 'OK: afvisninger (B-batch, fremmed og ukendt autorisation, åben batch, udløbet)';
END $reject$;

ROLLBACK;
