-- #147 4.4: contract test for deterministic key and proposal writer.
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
ROLLBACK;
