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

-- Kandidatkørslen for en verden (uenig: verdenens konkurrent, person p_base*1000-999, scorer højere end bindingspersonen,
-- så personaerne er kort med S/F/U og oprindelsen human; delspec 6c-1 §4.8); verden med kørslens id i nøglen 'run'.
-- Inputtet rummer alle personer i basen (red_match_personer), så kørslerne registreres, efter at alle verdener,
-- konkurrenter og staged-markeringer findes; ellers giver finalize PUBLICATION_IDENTITY_INPUT_DRIFT.
CREATE FUNCTION pg_temp.pr_run(w jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_c jsonb:='[]'::jsonb; v_i int; v_base bigint:=(w->'src'->>'source')::bigint;
BEGIN
  FOR v_i IN 1..jsonb_array_length(w->'personas') LOOP
    v_c:=v_c||pg_temp.pi_cand(pg_temp.pi_persona(w,v_i),v_base*1000-999,1,
                              jsonb_build_array(pg_temp.pi_ms(v_base*1000-999,0.99,ARRAY['name'])))
            ||pg_temp.pi_cand(pg_temp.pi_persona(w,v_i),v_base*1000-v_i,2,
                              jsonb_build_array(pg_temp.pi_ms(v_base*1000-v_i,0.95,ARRAY['name'])));
  END LOOP;
  RETURN w||jsonb_build_object('run',pg_temp.pi_run(w,'{"topK":10,"autoCutoff":0.9,"controlMargin":0.05}',v_c));
END $$;

-- En finaliseret C-batch over de givne personas (uenig, S), alle mod verdenens kørsel. Codex 6B-01: finalize kræver hele
-- B-batchens kontrolmængde, så personas uden for [from,to] skal være staged (disposition) eller have en identitet.
CREATE FUNCTION pg_temp.pr_c(p_world jsonb, p_tag text, p_from int, p_to int) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_payloads jsonb:='[]'::jsonb; v_i int; v_p jsonb; v_batch uuid; v_run uuid:=(p_world->>'run')::uuid;
BEGIN
  FOR v_i IN p_from..p_to LOOP
    v_payloads:=v_payloads||jsonb_build_array(pg_temp.pi_payload(p_world,v_i,v_run,'uenig','S'));
  END LOOP;
  v_batch:=pg_temp.pi_begin(p_world,p_tag,pg_temp.pi_elements(v_payloads));
  FOR v_i IN p_from..p_to LOOP
    v_p:=v_payloads->(v_i-p_from);
    PERFORM pg_temp.pi_apply(p_world,v_batch,pg_temp.pi_el(v_p),v_p);
  END LOOP;
  PERFORM pg_temp.pi_finalize(p_world,v_batch);
  RETURN v_batch;
END $$;

-- Trin 6b opfølgning (I2): en C-batch med blandede elementer; items er [{i, outcome, answer, v[, o]}] (v = forventet
-- identitetsversion, o = payload-override). Elementerne skrives i items' rækkefølge, og batchen finaliseres.
CREATE FUNCTION pg_temp.pr_cx(p_world jsonb, p_tag text, p_items jsonb) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_payloads jsonb:='[]'::jsonb; v_it jsonb; v_p jsonb; v_batch uuid; v_run uuid:=(p_world->>'run')::uuid;
BEGIN
  FOR v_it IN SELECT x FROM jsonb_array_elements(p_items) x LOOP
    v_payloads:=v_payloads||jsonb_build_array(pg_temp.pi_payload(p_world,(v_it->>'i')::int,v_run,v_it->>'outcome',v_it->>'answer',
      jsonb_build_object('expected_identity_version',coalesce((v_it->>'v')::int,0))||coalesce(v_it->'o','{}'::jsonb)));
  END LOOP;
  v_batch:=pg_temp.pi_begin(p_world,p_tag,pg_temp.pi_elements(v_payloads));
  FOR v_p IN SELECT x FROM jsonb_array_elements(v_payloads) x LOOP
    PERFORM pg_temp.pi_apply(p_world,v_batch,pg_temp.pi_el(v_p),v_p);
  END LOOP;
  PERFORM pg_temp.pi_finalize(p_world,v_batch);
  RETURN v_batch;
END $$;

-- Som pr_cx, men fejlen returneres som tekst, og alt rulles tilbage (undertransaktion).
CREATE FUNCTION pg_temp.pr_cx_try(p_world jsonb, p_tag text, p_items jsonb) RETURNS text LANGUAGE plpgsql AS $$
BEGIN
  PERFORM pg_temp.pr_cx(p_world,p_tag,p_items);
  RAISE EXCEPTION 'PR_CX_OK';
EXCEPTION WHEN OTHERS THEN
  RETURN CASE WHEN SQLERRM='PR_CX_OK' THEN 'OK' ELSE SQLERRM END;
END $$;

CREATE FUNCTION pg_temp.pr_ctl(p_world jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v jsonb;
BEGIN
  PERFORM set_config('request.jwt.claim.sub',p_world->'src'->>'actor',true); PERFORM set_config('role','authenticated',true);
  v:=public.red_publication_control((p_world->>'run')::uuid);
  RESET role; RETURN v;
EXCEPTION WHEN OTHERS THEN RESET role; RAISE;
END $$;

CREATE FUNCTION pg_temp.pr_ctl_e(p_ctl jsonb, p_persona uuid) RETURNS jsonb LANGUAGE sql AS $$
  SELECT e FROM jsonb_array_elements(p_ctl->'personas') e WHERE e->>'source_persona_id'=p_persona::text
$$;

-- Webkøens to veje som redaktøren: personaen i køen (alle statusser) og en afgørelse med den aktuelle version.
CREATE FUNCTION pg_temp.pr_in_queue(p_world jsonb, p_persona uuid) RETURNS boolean LANGUAGE plpgsql AS $$
DECLARE v boolean;
BEGIN
  PERFORM set_config('request.jwt.claim.sub',p_world->'src'->>'actor',true); PERFORM set_config('role','authenticated',true);
  SELECT EXISTS (SELECT 1 FROM public.red_source_persona_queue(NULL,(p_world->'src'->>'source')::bigint,NULL,100,NULL) q
                  WHERE q.source_persona_id=p_persona) INTO v;
  RESET role; RETURN v;
EXCEPTION WHEN OTHERS THEN RESET role; RAISE;
END $$;

CREATE FUNCTION pg_temp.pr_afgoer(p_world jsonb, p_persona uuid, p_person bigint) RETURNS text LANGUAGE plpgsql AS $$
DECLARE v_version int:=coalesce((SELECT i.version FROM private.source_persona_identity i WHERE i.source_persona_id=p_persona),0);
BEGIN
  PERFORM set_config('request.jwt.claim.sub',p_world->'src'->>'actor',true); PERFORM set_config('role','authenticated',true);
  PERFORM public.red_afgoer_source_persona(p_persona,v_version,'same',p_person,'synt note','{}'::jsonb);
  RESET role; RETURN 'OK';
EXCEPTION WHEN OTHERS THEN RESET role; RETURN SQLERRM;
END $$;

-- Kandidatkørsel, hvor persona 1..p_enig er enige (eget medlem med fødselsår, ingen konkurrent) og resten uenige
-- (verdenens konkurrent scorer højere; kort, delspec 6c-1 §4.8).
CREATE FUNCTION pg_temp.pr_run_mixed(w jsonb, p_enig int) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_c jsonb:='[]'::jsonb; v_i int; v_base bigint:=(w->'src'->>'source')::bigint;
BEGIN
  FOR v_i IN 1..jsonb_array_length(w->'personas') LOOP
    IF v_i<=p_enig THEN
      v_c:=v_c||pg_temp.pi_cand(pg_temp.pi_persona(w,v_i),v_base*1000-v_i,1,
                                jsonb_build_array(pg_temp.pi_ms(v_base*1000-v_i,0.95,ARRAY['name','birth'])));
    ELSE
      v_c:=v_c||pg_temp.pi_cand(pg_temp.pi_persona(w,v_i),v_base*1000-999,1,
                                jsonb_build_array(pg_temp.pi_ms(v_base*1000-999,0.99,ARRAY['name'])))
              ||pg_temp.pi_cand(pg_temp.pi_persona(w,v_i),v_base*1000-v_i,2,
                                jsonb_build_array(pg_temp.pi_ms(v_base*1000-v_i,0.95,ARRAY['name'])));
    END IF;
  END LOOP;
  RETURN w||jsonb_build_object('run',pg_temp.pi_run(w,'{"topK":10,"autoCutoff":0.9,"controlMargin":0.05}',v_c));
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
--    versionsdrift (2), manglende kvittering (1), to C-batches til afvisningerne (1 + 1), en åben batch (1), og (trin 6b
--    opfølgning, I2) genkørsel (3), menneske efter fortrydelse (2) og fremmed superseded (2, hver i sin B-batch).
CREATE TEMP TABLE t7(k text PRIMARY KEY, v jsonb);
DO $world$
DECLARE v_k text;
BEGIN
  INSERT INTO t7 VALUES ('happy',pg_temp.pi_world(-6710,'11000000-0000-0000-0000-00000006b710',4)),
    ('drift',pg_temp.pi_world(-6711,'11000000-0000-0000-0000-00000006b710',2)),
    ('receipt',pg_temp.pi_world(-6712,'11000000-0000-0000-0000-00000006b710',1)),
    ('x1',pg_temp.pi_world(-6713,'11000000-0000-0000-0000-00000006b710',1)),
    ('x2',pg_temp.pi_world(-6714,'11000000-0000-0000-0000-00000006b710',1)),
    ('open',pg_temp.pi_world(-6715,'11000000-0000-0000-0000-00000006b710',1)),
    -- trin 6b opfølgning (I2): genkørsel (persona 1 enig, 2-3 uenige), menneske efter fortrydelse, fremmed superseded
    ('rerun',pg_temp.pi_world(-6716,'11000000-0000-0000-0000-00000006b710',3)),
    ('human',pg_temp.pi_world(-6717,'11000000-0000-0000-0000-00000006b710',2)),
    ('other',pg_temp.pi_world_split(-6718,'11000000-0000-0000-0000-00000006b710',2));
  UPDATE public.person SET staged=true WHERE id=-6710004;
  -- verdenernes konkurrenter (pr_run/pr_run_mixed), før kørslerne registreres
  INSERT INTO public.person(id,levende,privat,status) SELECT (v->'src'->>'source')::bigint*1000-999,false,false,'pr' FROM t7;
  FOR v_k IN SELECT k FROM t7 WHERE k<>'rerun' LOOP
    UPDATE t7 SET v=pg_temp.pr_run(v) WHERE k=v_k;
  END LOOP;
  UPDATE t7 SET v=pg_temp.pr_run_mixed(v,1) WHERE k='rerun';
  RAISE NOTICE 'OK: verdener (fortrydelse, drift, kvittering, afvisninger)';
END $world$;

-- 2) Fortrydelse af C: identiteterne bliver superseded, version 2, og er fortrudte publikationsidentiteter; personaerne venter
--    igen på kontrol (trin 6b opfølgning, I2: genkørsel frem for webkø); batch og autorisation; ny fortrydelse afvises.
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
    -- en fortrudt publikationsidentitet tæller som ingen identitet, og den fortrudte batch frigiver ikke: personaen venter
    -- igen (skjult i køen, spærret for red_afgoer)
    IF NOT private.publication_identity_reverted(pg_temp.pi_persona(w,v_i))
       OR NOT private.persona_awaiting_control(pg_temp.pi_persona(w,v_i)) THEN
      RAISE EXCEPTION 'PUBLICATION_REVERSAL_TEST_FAILED: % venter ikke igen efter fortrydelse',v_i; END IF;
    IF pg_temp.pr_in_queue(w,pg_temp.pi_persona(w,v_i)) THEN
      RAISE EXCEPTION 'PUBLICATION_REVERSAL_TEST_FAILED: % står i webkøen efter fortrydelse',v_i; END IF;
    PERFORM pg_temp.expect('afgørelse efter fortrydelse',pg_temp.pr_afgoer(w,pg_temp.pi_persona(w,v_i),-6710000-v_i),
                           'IDENTITY_AWAITING_PUBLICATION_CONTROL');
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
  RAISE NOTICE 'OK: fortrydelse af C (superseded, version 2, venter igen, skjult i køen, anden fortrydelse afvist)';
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
  v_p:=pg_temp.pi_payload(wo,1,(wo->>'run')::uuid,'uenig','S');
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

-- 5) Trin 6b opfølgning (I2): C → fortryd → personaerne venter igen → ny C med den aktuelle version → finalize; og en
--    dobbelt fortrydelse med genkørsel. Persona 1 er enig og i stikprøven (oprindelsen publication_binding, kernens vagt);
--    2 og 3 er uenige med S/F/U (human, writerens vagt).
DO $rerun$
DECLARE
  w jsonb:=(SELECT v FROM t7 WHERE k='rerun');
  v_c1 uuid; v_c2 uuid; v_c3 uuid; v_ctl jsonb; v_e jsonb; v_i int; v_id private.source_persona_identity%ROWTYPE;
  v_items0 jsonb; v_items jsonb;
BEGIN
  v_items0:='[{"i":1,"outcome":"enig","answer":"S","v":0},{"i":2,"outcome":"uenig","answer":"S","v":0},
              {"i":3,"outcome":"uenig","answer":"F","v":0}]';
  -- stikprøven før C: persona 1 (den eneste enige)
  v_ctl:=pg_temp.pr_ctl(w);
  IF NOT (pg_temp.pr_ctl_e(v_ctl,pg_temp.pi_persona(w,1))->>'in_sample')::boolean THEN
    RAISE EXCEPTION 'PUBLICATION_REVERSAL_TEST_FAILED: stikprøven før C'; END IF;
  v_c1:=pg_temp.pr_cx(w,'rerun-c1',v_items0);
  IF (SELECT payload->'result_receipt'->>'origin' FROM private.reimport_event
       WHERE batch_id=v_c1 AND payload->>'source_persona_id'=pg_temp.pi_persona(w,1)::text)<>'publication_binding' THEN
    RAISE EXCEPTION 'PUBLICATION_REVERSAL_TEST_FAILED: C1 skrev ikke publication_binding'; END IF;
  -- efter C (ikke fortrudt): ingen fortrudt identitet, ingen venter, og en ny C kan ikke skrive oven på C1's identiteter
  IF EXISTS (SELECT 1 FROM generate_series(1,3) i WHERE private.publication_identity_reverted(pg_temp.pi_persona(w,i))
                                                     OR private.persona_awaiting_control(pg_temp.pi_persona(w,i))) THEN
    RAISE EXCEPTION 'PUBLICATION_REVERSAL_TEST_FAILED: efter C1'; END IF;
  PERFORM pg_temp.expect('C oven på en finaliseret C',pg_temp.pr_cx_try(w,'rerun-x1',
    '[{"i":2,"outcome":"uenig","answer":"S","v":1}]'),'EVIDENCE_IDENTITY_VERSION_CONFLICT');

  PERFORM pg_temp.pr_reverse(w,v_c1,pg_temp.pr_auth(w,v_c1));
  -- efter fortrydelsen: version 2, fortrudt, venter; kontrollen viser den aktuelle version, identity_reverted og samme stikprøve
  v_ctl:=pg_temp.pr_ctl(w);
  FOR v_i IN 1..3 LOOP
    v_e:=pg_temp.pr_ctl_e(v_ctl,pg_temp.pi_persona(w,v_i));
    IF (v_e->>'identity_version')::int<>2 OR v_e->'identity_reverted'<>'true'::jsonb
       OR NOT private.persona_awaiting_control(pg_temp.pi_persona(w,v_i))
       OR (v_e->>'in_sample')::boolean<>(v_i=1) THEN
      RAISE EXCEPTION 'PUBLICATION_REVERSAL_TEST_FAILED: kontrol efter fortrydelse %',v_e; END IF;
  END LOOP;
  -- en ny C med version 0 møder kernens versionskonflikt; en C, der udelader en fortrudt persona, giver SET_MISMATCH;
  -- en enig uden stikprøvesvar giver SAMPLE_MISMATCH (stikprøven er den samme som før)
  PERFORM pg_temp.expect('genkørsel med version 0',pg_temp.pr_cx_try(w,'rerun-x2',v_items0),'EVIDENCE_IDENTITY_VERSION_CONFLICT');
  PERFORM pg_temp.expect('genkørsel uden persona 3',pg_temp.pr_cx_try(w,'rerun-x3',
    '[{"i":1,"outcome":"enig","answer":"S","v":2},{"i":2,"outcome":"uenig","answer":"S","v":2}]'),'PUBLICATION_IDENTITY_SET_MISMATCH');
  PERFORM pg_temp.expect('genkørsel uden stikprøvesvar',pg_temp.pr_cx_try(w,'rerun-x4',
    '[{"i":1,"outcome":"enig","answer":null,"v":2},{"i":2,"outcome":"uenig","answer":"S","v":2},{"i":3,"outcome":"uenig","answer":"S","v":2}]'),
    'PUBLICATION_IDENTITY_SAMPLE_MISMATCH');
  PERFORM pg_temp.expect('genkørsel med forkert version',pg_temp.pr_cx_try(w,'rerun-x5',
    '[{"i":1,"outcome":"enig","answer":"S","v":1},{"i":2,"outcome":"uenig","answer":"S","v":2},{"i":3,"outcome":"uenig","answer":"S","v":2}]'),
    'EVIDENCE_IDENTITY_VERSION_CONFLICT');
  IF EXISTS (SELECT 1 FROM generate_series(1,3) i JOIN private.source_persona_identity x ON x.source_persona_id=pg_temp.pi_persona(w,i)
              WHERE x.version<>2) THEN
    RAISE EXCEPTION 'PUBLICATION_REVERSAL_TEST_FAILED: afviste genkørsler skrev'; END IF;

  -- genkørslen: samme kandidatkørsel, version 2
  v_c2:=pg_temp.pr_cx(w,'rerun-c2','[{"i":1,"outcome":"enig","answer":"S","v":2},{"i":2,"outcome":"uenig","answer":"S","v":2},
                                     {"i":3,"outcome":"uenig","answer":"U","v":2}]');
  FOR v_i IN 1..3 LOOP
    SELECT * INTO v_id FROM private.source_persona_identity WHERE source_persona_id=pg_temp.pi_persona(w,v_i);
    IF v_id.version<>3 OR v_id.decision_status<>(CASE WHEN v_i=3 THEN 'unresolved' ELSE 'accepted' END)
       OR v_id.evidence->>'reimport_batch_id'<>v_c2::text
       OR private.publication_identity_reverted(pg_temp.pi_persona(w,v_i))
       OR private.persona_awaiting_control(pg_temp.pi_persona(w,v_i)) THEN
      RAISE EXCEPTION 'PUBLICATION_REVERSAL_TEST_FAILED: genkørsel persona % (%,%)',v_i,v_id.version,v_id.decision_status; END IF;
  END LOOP;
  IF (SELECT payload->'result_receipt'->>'origin' FROM private.reimport_event
       WHERE batch_id=v_c2 AND payload->>'source_persona_id'=pg_temp.pi_persona(w,1)::text)<>'publication_binding'
     OR (SELECT status FROM private.reimport_batch WHERE id=v_c2)<>'finalized' THEN
    RAISE EXCEPTION 'PUBLICATION_REVERSAL_TEST_FAILED: genkørslens oprindelse/status'; END IF;

  -- dobbelt fortrydelse: C2 fortrydes (version 4), og C3 skriver med version 4
  PERFORM pg_temp.pr_reverse(w,v_c2,pg_temp.pr_auth(w,v_c2));
  IF EXISTS (SELECT 1 FROM generate_series(1,3) i JOIN private.source_persona_identity x ON x.source_persona_id=pg_temp.pi_persona(w,i)
              WHERE x.version<>4 OR x.decision_status<>'superseded' OR x.evidence->>'reversed_batch_id'<>v_c2::text
                 OR NOT private.publication_identity_reverted(x.source_persona_id)
                 OR NOT private.persona_awaiting_control(x.source_persona_id)) THEN
    RAISE EXCEPTION 'PUBLICATION_REVERSAL_TEST_FAILED: anden fortrydelse'; END IF;
  -- den allerede fortrudte C1 kan ikke autoriseres til en ny fortrydelse
  BEGIN
    PERFORM pg_temp.pr_auth(w,v_c1);
    RAISE EXCEPTION 'PUBLICATION_REVERSAL_TEST_FAILED: fortrudt C1 autoriseret igen';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM<>'REIMPORT_WRITER_REVERSAL_INVALID' THEN RAISE; END IF;
  END;
  PERFORM pg_temp.expect('tredje kørsel med version 2',pg_temp.pr_cx_try(w,'rerun-x6',
    '[{"i":1,"outcome":"enig","answer":"S","v":2},{"i":2,"outcome":"uenig","answer":"S","v":2},{"i":3,"outcome":"uenig","answer":"S","v":2}]'),
    'EVIDENCE_IDENTITY_VERSION_CONFLICT');
  v_c3:=pg_temp.pr_cx(w,'rerun-c3','[{"i":1,"outcome":"enig","answer":"S","v":4},{"i":2,"outcome":"uenig","answer":"S","v":4},
                                     {"i":3,"outcome":"uenig","answer":"S","v":4}]');
  IF EXISTS (SELECT 1 FROM generate_series(1,3) i JOIN private.source_persona_identity x ON x.source_persona_id=pg_temp.pi_persona(w,i)
              WHERE x.version<>5 OR x.decision_status<>'accepted' OR private.persona_awaiting_control(x.source_persona_id))
     OR (SELECT status FROM private.reimport_batch WHERE id=v_c3)<>'finalized'
     OR (SELECT count(*) FROM private.source_persona_identity_event e
          WHERE e.source_persona_id=pg_temp.pi_persona(w,1))<>5 THEN
    RAISE EXCEPTION 'PUBLICATION_REVERSAL_TEST_FAILED: tredje kørsel'; END IF;
  -- kernens reversal-oprindelse direkte med den finaliserede (ikke fortrudte) C3 som reversed_batch_id: C3 navngiver
  -- personaen, og kvitteringsversionen passer, men batchen er ikke fortrudt → ikke en fortrudt publikationsidentitet
  PERFORM set_config('request.jwt.claim.sub',w->'src'->>'actor',true);
  PERFORM private.decide_source_persona_identity(pg_temp.pi_persona(w,2),NULL,5,'superseded',
    jsonb_build_object('reversed_batch_id',v_c3,'profile_sha256',w->'src'->>'profile_sha256'),'reversal');
  IF private.publication_identity_reverted(pg_temp.pi_persona(w,2)) OR private.persona_awaiting_control(pg_temp.pi_persona(w,2)) THEN
    RAISE EXCEPTION 'PUBLICATION_REVERSAL_TEST_FAILED: superseded mod en finaliseret C regnet som fortrudt'; END IF;
  RAISE NOTICE 'OK: C → fortryd → venter igen → ny C med version 2 → finalize; dobbelt fortrydelse og genkørsel med version 4';
END $rerun$;

-- 6) Menneskelig afgørelse efter fortrydelsen (her direkte i kernen; webkøen er spærret, mens personaen venter): personaen
--    er ikke længere en fortrudt publikationsidentitet. C afviser den med versionskonflikt (både med den forrige og den
--    aktuelle version) og kan udelade den; finalize kræver den ikke.
DO $human$
DECLARE
  w jsonb:=(SELECT v FROM t7 WHERE k='human');
  v_c1 uuid; v_c2 uuid; v_p1 uuid:=pg_temp.pi_persona(w,1); v_p2 uuid:=pg_temp.pi_persona(w,2); v_e jsonb;
BEGIN
  v_c1:=pg_temp.pr_c(w,'human-c1',1,2);
  PERFORM pg_temp.pr_reverse(w,v_c1,pg_temp.pr_auth(w,v_c1));
  PERFORM set_config('request.jwt.claim.sub',w->'src'->>'actor',true);
  PERFORM private.decide_source_persona_identity(v_p1,-6717001,2,'accepted','{"basis":"web_detail","note":"t"}','human');
  v_e:=pg_temp.pr_ctl_e(pg_temp.pr_ctl(w),v_p1);
  IF private.publication_identity_reverted(v_p1) OR private.persona_awaiting_control(v_p1)
     OR (v_e->>'identity_version')::int<>3 OR v_e->'identity_reverted'<>'false'::jsonb
     OR NOT private.publication_identity_reverted(v_p2) OR NOT private.persona_awaiting_control(v_p2) THEN
    RAISE EXCEPTION 'PUBLICATION_REVERSAL_TEST_FAILED: tilstand efter menneskelig afgørelse %',v_e; END IF;
  PERFORM pg_temp.expect('menneske, forrige version',pg_temp.pr_cx_try(w,'human-x1',
    '[{"i":1,"outcome":"uenig","answer":"S","v":2},{"i":2,"outcome":"uenig","answer":"S","v":2}]'),'EVIDENCE_IDENTITY_VERSION_CONFLICT');
  PERFORM pg_temp.expect('menneske, aktuel version',pg_temp.pr_cx_try(w,'human-x2',
    '[{"i":1,"outcome":"uenig","answer":"S","v":3},{"i":2,"outcome":"uenig","answer":"S","v":2}]'),'EVIDENCE_IDENTITY_VERSION_CONFLICT');
  PERFORM pg_temp.expect('menneske, version 0',pg_temp.pr_cx_try(w,'human-x3',
    '[{"i":1,"outcome":"uenig","answer":"S","v":0},{"i":2,"outcome":"uenig","answer":"S","v":2}]'),'EVIDENCE_IDENTITY_VERSION_CONFLICT');
  -- en senere reversal-oprindelse direkte i kernen med den fortrudte C1 som reversed_batch_id (version 4): batchen er fortrudt
  -- og navngiver personaen, men den seneste overgang er ikke fortrydelsen af C1's identitet (C1 skrev version 1, ikke 3)
  PERFORM private.decide_source_persona_identity(v_p1,NULL,3,'superseded',
    jsonb_build_object('reversed_batch_id',v_c1,'profile_sha256',w->'src'->>'profile_sha256'),'reversal');
  IF private.publication_identity_reverted(v_p1) OR private.persona_awaiting_control(v_p1) THEN
    RAISE EXCEPTION 'PUBLICATION_REVERSAL_TEST_FAILED: senere superseded mod C1 regnet som fortrudt'; END IF;
  PERFORM pg_temp.expect('senere superseded mod C1',pg_temp.pr_cx_try(w,'human-x4',
    '[{"i":1,"outcome":"uenig","answer":"S","v":4},{"i":2,"outcome":"uenig","answer":"S","v":2}]'),'EVIDENCE_IDENTITY_VERSION_CONFLICT');
  v_c2:=pg_temp.pr_cx(w,'human-c2','[{"i":2,"outcome":"uenig","answer":"S","v":2}]');
  IF (SELECT version FROM private.source_persona_identity WHERE source_persona_id=v_p1)<>4
     OR (SELECT decision_status FROM private.source_persona_identity WHERE source_persona_id=v_p1)<>'superseded'
     OR (SELECT version FROM private.source_persona_identity WHERE source_persona_id=v_p2)<>3
     OR private.persona_awaiting_control(v_p1) OR private.persona_awaiting_control(v_p2) THEN
    RAISE EXCEPTION 'PUBLICATION_REVERSAL_TEST_FAILED: C uden den menneskeligt afgjorte persona'; END IF;
  RAISE NOTICE 'OK: menneskelig afgørelse efter fortrydelse → C afviser den (versionskonflikt) og kan udelade den';
END $human$;

-- 7) En superseded identitet, der ikke er en fortrudt publikationsidentitet: kernens reversal-oprindelse med en
--    reversed_batch_id, der peger på en ægte fortrudt C-batch, som ikke navngiver personaen (persona 2), og en med en
--    opdigtet batch (persona 2 i en anden B-batch end persona 1). C og kernens publication_binding afviser begge.
DO $other$
DECLARE
  w jsonb:=(SELECT v FROM t7 WHERE k='other');
  v_c1 uuid; v_p1 uuid:=pg_temp.pi_persona(w,1); v_p2 uuid:=pg_temp.pi_persona(w,2); v_res text; v_b2 jsonb;
BEGIN
  v_b2:=jsonb_build_object('persona_batch_id',w->'b_batches'->>1);
  v_c1:=pg_temp.pr_cx(w,'other-c1',jsonb_build_array(jsonb_build_object('i',1,'outcome','uenig','answer','S','v',0,
                                                       'o',jsonb_build_object('persona_batch_id',w->'b_batches'->>0))));
  PERFORM pg_temp.pr_reverse(w,v_c1,pg_temp.pr_auth(w,v_c1));
  IF NOT private.publication_identity_reverted(v_p1) THEN
    RAISE EXCEPTION 'PUBLICATION_REVERSAL_TEST_FAILED: persona 1 ikke fortrudt'; END IF;
  PERFORM set_config('request.jwt.claim.sub',w->'src'->>'actor',true);
  -- persona 2: human (v1), derefter reversal med den ægte fortrudte C-batch som reversed_batch_id (v2)
  PERFORM private.decide_source_persona_identity(v_p2,-6718002,0,'accepted','{"basis":"web_detail","note":"t"}','human');
  PERFORM private.decide_source_persona_identity(v_p2,NULL,1,'superseded',
    jsonb_build_object('reversed_batch_id',v_c1,'profile_sha256',w->'src'->>'profile_sha256'),'reversal');
  IF private.publication_identity_reverted(v_p2) OR private.persona_awaiting_control(v_p2) THEN
    RAISE EXCEPTION 'PUBLICATION_REVERSAL_TEST_FAILED: fremmed superseded regnet som fortrudt'; END IF;
  PERFORM pg_temp.expect('fremmed superseded i C',pg_temp.pr_cx_try(w,'other-x1',
    jsonb_build_array(jsonb_build_object('i',2,'outcome','uenig','answer','S','v',2,'o',v_b2))),'EVIDENCE_IDENTITY_VERSION_CONFLICT');
  BEGIN
    PERFORM private.decide_source_persona_identity(v_p2,-6718002,2,'accepted',
      jsonb_build_object('authority','narrative_record_publication','binding_id',pg_temp.pi_post(w,2)->>'binding'),'publication_binding');
    v_res:='OK';
  EXCEPTION WHEN OTHERS THEN v_res:=SQLERRM; END;
  PERFORM pg_temp.expect('kernen, fremmed superseded',v_res,'PUBLICATION_BINDING_ORIGIN_INVALID');
  -- opdigtet batch-id (findes ikke) og B-batchens id (ikke reversed, ingen publication_identity-hændelse)
  PERFORM private.decide_source_persona_identity(v_p2,NULL,2,'superseded',
    jsonb_build_object('reversed_batch_id',gen_random_uuid(),'profile_sha256',w->'src'->>'profile_sha256'),'reversal');
  PERFORM private.decide_source_persona_identity(v_p2,NULL,3,'superseded',
    jsonb_build_object('reversed_batch_id',w->'b_batches'->>1,'profile_sha256',w->'src'->>'profile_sha256'),'reversal');
  IF private.publication_identity_reverted(v_p2) THEN
    RAISE EXCEPTION 'PUBLICATION_REVERSAL_TEST_FAILED: opdigtet/B-batch regnet som fortrudt'; END IF;
  PERFORM pg_temp.expect('B-batch som reversed_batch_id',pg_temp.pr_cx_try(w,'other-x2',
    jsonb_build_array(jsonb_build_object('i',2,'outcome','uenig','answer','S','v',4,'o',v_b2))),'EVIDENCE_IDENTITY_VERSION_CONFLICT');
  -- persona 1 (ægte fortrudt) kan derimod skrives igen gennem kernen direkte, med den aktuelle version
  BEGIN
    PERFORM private.decide_source_persona_identity(v_p1,-6718001,2,'accepted',
      jsonb_build_object('authority','narrative_record_publication','binding_id',pg_temp.pi_post(w,1)->>'binding'),'publication_binding');
    v_res:='OK';
    RAISE EXCEPTION 'RULLES_TILBAGE';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'RULLES_TILBAGE' THEN v_res:=SQLERRM; END IF; END;
  PERFORM pg_temp.expect('kernen, fortrudt',v_res,'OK');
  RAISE NOTICE 'OK: ikke-fortrudt superseded (fremmed C-batch, opdigtet, B-batch) afvises af C og kernen; fortrudt godtages';
END $other$;

ROLLBACK;
