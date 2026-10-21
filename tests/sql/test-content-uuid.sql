\set ON_ERROR_STOP on
-- Indholds-id (#151, spec 2026-10-21-trin5ab-indholds-id-design.md §3): private.content_uuid afleder id af art + naturlig nøgle.
BEGIN;
DO $cu$
DECLARE a uuid; b uuid; v_err text;
BEGIN
  a:=private.content_uuid('source-persona',jsonb_build_object('source_id',1,'persona_key','K'));
  b:=private.content_uuid('source-persona',jsonb_build_object('persona_key','K','source_id',1));
  IF a IS DISTINCT FROM b THEN RAISE EXCEPTION 'CONTENT_UUID_TEST_FAILED: nøgleorden'; END IF;
  IF a<>private.deterministic_uuid('{"kind": "source-persona", "source_id": 1, "key_version": 1, "persona_key": "K"}') THEN
    RAISE EXCEPTION 'CONTENT_UUID_TEST_FAILED: afledning'; END IF;
  IF a=private.content_uuid('source-mention',jsonb_build_object('source_id',1,'persona_key','K')) THEN
    RAISE EXCEPTION 'CONTENT_UUID_TEST_FAILED: art'; END IF;
  IF a=private.content_uuid('source-persona',jsonb_build_object('source_id',1,'persona_key','L')) THEN
    RAISE EXCEPTION 'CONTENT_UUID_TEST_FAILED: nøgle'; END IF;
  BEGIN PERFORM private.content_uuid('x',jsonb_build_object('kind','y')); RAISE EXCEPTION 'CONTENT_UUID_TEST_FAILED: kind';
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT;
    IF v_err NOT LIKE 'CONTENT_UUID_KEY_INVALID%' THEN RAISE; END IF; END;
  IF has_function_privilege('anon','private.content_uuid(text,jsonb)','EXECUTE')
     OR has_function_privilege('authenticated','private.content_uuid(text,jsonb)','EXECUTE') THEN
    RAISE EXCEPTION 'CONTENT_UUID_TEST_FAILED: rettigheder'; END IF;
  RAISE NOTICE 'OK: content_uuid';
END $cu$;
ROLLBACK;
