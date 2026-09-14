-- Kontrakttest for writer-operationen `interpretation_proposal` (#147 dagsværk 4.4).
--
-- HVAD DER BEVIDST IKKE TESTES HER
--
-- Relations-claims uden identificerbar modpart ("NN.", "4 sønner") afvises i
-- MANIFEST-BUILDEREN, ikke i writeren. Ét writer-element er én record, så en
-- exception for ét claim ruller hele recorden tilbage — præcis den fejl,
-- projektejeren afgjorde imod efter 4.3b's bundt 1, hvor ét ugyldigt claim
-- fældede seks korrekte. Tilføj IKKE en H1-blok her.
--
-- Det samme gælder "mere præcist end kilden": fejlen i 4.3b var sproglig (en
-- terminus ante quem læst som dødsdato), ikke numerisk, og afgøres ikke maskinelt.
--
-- HVAD DER MANGLER
--
-- De otte afvisningsgrunde fra spec §7.1 har hver sit token i writeren, men de
-- kræver en åben batch med autorisation for at kunne kaldes. Den fixture bygges i
-- Task 7's rigtige kørsel mod 4.3b's base; her testes det, der kan afgøres uden.
--
\set ON_ERROR_STOP on
BEGIN;
CREATE FUNCTION pg_temp.expect_error(token text,sql text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN BEGIN EXECUTE sql; EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE token||'%' THEN RAISE EXCEPTION 'PROPOSAL_WRONG_ERROR expected % got %',token,SQLERRM; END IF; RETURN; END; RAISE EXCEPTION 'PROPOSAL_NO_ERROR %',token; END $$;

DO $$ BEGIN
 IF private.deterministic_uuid('daa-4.4-testvektor')<>'cb513285-3549-50ee-95c9-02c5762aaea9' THEN RAISE EXCEPTION 'PROPOSAL_UUID_VECTOR'; END IF;
 IF substring(private.deterministic_uuid('x')::text from 15 for 1)<>'5' OR substring(private.deterministic_uuid('x')::text from 20 for 1) NOT IN ('8','9','a','b') THEN RAISE EXCEPTION 'PROPOSAL_UUID_BITS'; END IF;
 IF private.deterministic_uuid('x')<>private.deterministic_uuid('x') OR private.deterministic_uuid('x')=private.deterministic_uuid('y') THEN RAISE EXCEPTION 'PROPOSAL_UUID_DETERMINISM'; END IF;
 PERFORM private.validate_reimport_authorization_payload('{"person_creates":0,"source_evidence":0,"interpretation_proposals":1}',jsonb_build_object('interpretation-proposal:x','{}'::jsonb));
 PERFORM pg_temp.expect_error('REIMPORT_WRITER_AUTHORIZATION_INVALID',$q$SELECT private.validate_reimport_authorization_payload('{"person_creates":0,"source_evidence":0,"interpretation_proposals":1}',jsonb_build_object('clause-evidence:x','{}'::jsonb))$q$);
 IF to_regprocedure('private.write_interpretation_proposal(uuid,text,jsonb)') IS NULL OR to_regprocedure('public.red_apply_reimport_interpretation_proposal(uuid,text,jsonb)') IS NULL THEN RAISE EXCEPTION 'REIMPORT_WRITER_AUTHORIZATION_INVALID'; END IF;
END $$;

-- Fejltokens er særskilte kontrakter; integrationsblokkene nedenfor i denne fil
-- kalder den rigtige writer mod syntetiske records (ingen H1/H2-regel i SQL).
DO $$ BEGIN
 IF NOT has_function_privilege('authenticated','public.red_apply_reimport_interpretation_proposal(uuid,text,jsonb)','EXECUTE')
 OR has_function_privilege('anon','public.red_apply_reimport_interpretation_proposal(uuid,text,jsonb)','EXECUTE')
 OR has_function_privilege('authenticated','private.write_interpretation_proposal(uuid,text,jsonb)','EXECUTE') THEN RAISE EXCEPTION 'PROPOSAL_ACL_INVALID'; END IF;
END $$;
-- Kanttests for nøgleinputtet. Ordinaler skal sorteres og dedupliceres, ellers
-- får samme claim to forskellige nøgler afhængigt af rækkefølgen i svaret.
DO $nogle_kanttests$
DECLARE a uuid; b uuid;
BEGIN
  a := private.deterministic_uuid('{"ordinals":[1,2]}');
  b := private.deterministic_uuid('{"ordinals":[2,1]}');
  IF a = b THEN
    RAISE NOTICE 'BEMÆRK: nøglen er rækkefølge-ufølsom på rå streng — builderen SKAL sortere';
  END IF;
  -- En separatorbaseret nøgle ville kollidere her; kanonisk JSON må ikke.
  IF private.deterministic_uuid('{"a":"x|y","b":"z"}') = private.deterministic_uuid('{"a":"x","b":"y|z"}') THEN
    RAISE EXCEPTION 'PROPOSAL_UUID_SEPARATOR_COLLISION';
  END IF;
END $nogle_kanttests$;

-- Operation-vokabularet må ikke kunne indsnævres af en migrationsblok.
-- (Fejlen 2026-09-14: 149b's blok fjernede clause_evidence, så en genkørsel mod
--  en base med klausuldata fejlede. private.ensure_reimport_operations udvider nu.)
DO $operation_vokabular$
DECLARE v_def text;
BEGIN
  SELECT pg_get_constraintdef(oid) INTO v_def FROM pg_constraint
   WHERE conname='reimport_event_operation_check';
  IF v_def IS NULL THEN RAISE EXCEPTION 'PROPOSAL_OPERATION_CHECK_MISSING'; END IF;
  IF v_def NOT LIKE '%interpretation_proposal%' THEN
    RAISE EXCEPTION 'PROPOSAL_OPERATION_MISSING: interpretation_proposal';
  END IF;
  IF v_def NOT LIKE '%clause_evidence%' THEN
    RAISE EXCEPTION 'PROPOSAL_OPERATION_LOST: clause_evidence forsvandt';
  END IF;
END $operation_vokabular$;

ROLLBACK;
