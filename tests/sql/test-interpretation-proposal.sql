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

-- Receipt-/nøglekontrakterne er testbare uden den fulde, syntetiske apply-
-- fixture (den etableres som en del af integrationskørslen).  Det holder de
-- bytefølsomme helpers røde, indtil den levende writer kan bygge receiptet.
DO $proposal_receipt_helper_contract$
DECLARE
  v_value jsonb := '{"nested":[true,null],"tekst":"Æ\\n😀"}'::jsonb;
  v_cited jsonb := '[{"ordinal":2,"verbatim_sha256":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"},{"ordinal":1,"verbatim_sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}]'::jsonb;
  v_inline text;
BEGIN
  IF to_regprocedure('private.interpretation_proposal_canonical_json_text(jsonb)') IS NULL
     OR to_regprocedure('private.interpretation_proposal_canonical_json_sha256(jsonb)') IS NULL
     OR to_regprocedure('private.interpretation_proposal_key_material(bigint,text,text,jsonb,jsonb)') IS NULL
     OR to_regprocedure('private.interpretation_proposal_key_material_sha256(bigint,text,text,jsonb,jsonb)') IS NULL
     OR to_regprocedure('private.interpretation_proposal_key(bigint,text,text,jsonb,jsonb)') IS NULL THEN
    RAISE EXCEPTION 'PROPOSAL_RESULT_RECEIPT_INVALID';
  END IF;
  IF private.interpretation_proposal_canonical_json_text(v_value)
       <> '{"nested":[true,null],"tekst":"Æ\\n😀"}'
     OR private.interpretation_proposal_canonical_json_text('[-0,1e0,1.0,-9223372036854775808,9223372036854775807]'::jsonb)
       <> '[0,1,1,-9223372036854775808,9223372036854775807]'
     OR private.interpretation_proposal_canonical_json_sha256(v_value)
       <> encode(extensions.digest(convert_to('{"nested":[true,null],"tekst":"Æ\\n😀"}','UTF8'),'sha256'),'hex') THEN
    RAISE EXCEPTION 'PROPOSAL_RESULT_RECEIPT_INVALID';
  END IF;
  PERFORM pg_temp.expect_error('REIMPORT_WRITER_INTERPRETATION_VALUE_NUMERIC_INVALID',
    $q$SELECT private.interpretation_proposal_canonical_json_text('1.5'::jsonb)$q$);
  PERFORM pg_temp.expect_error('REIMPORT_WRITER_INTERPRETATION_VALUE_NUMERIC_INVALID',
    $q$SELECT private.interpretation_proposal_canonical_json_text('9223372036854775808'::jsonb)$q$);
  SELECT jsonb_build_object(
      'key_version',1,'source_id',3,'record_key','record-1','predicate','person.name',
      'ordinals',jsonb_agg(DISTINCT (c->>'ordinal')::integer ORDER BY (c->>'ordinal')::integer),
      'value_sha256',encode(extensions.digest(convert_to(v_value::text,'UTF8'),'sha256'),'hex')
    )::text
    INTO v_inline
    FROM jsonb_array_elements(v_cited) c;
  IF private.interpretation_proposal_key_material(3,'record-1','person.name',v_cited,v_value)
       IS DISTINCT FROM v_inline
     OR private.interpretation_proposal_key_material_sha256(3,'record-1','person.name',v_cited,v_value)
       <> encode(extensions.digest(convert_to(v_inline,'UTF8'),'sha256'),'hex')
     OR private.interpretation_proposal_key(3,'record-1','person.name',v_cited,v_value)
       <> private.deterministic_uuid(v_inline) THEN
    RAISE EXCEPTION 'PROPOSAL_RESULT_RECEIPT_INVALID';
  END IF;
END $proposal_receipt_helper_contract$;

-- test_key_v1_unchanged (trin 6a, spec §4.4 pkt. 6): en kendt v1-vektor er fastlåst. Samme vektor måles før og
-- efter migrationen i tests/sql/test-proposal-key-v1-upgrade.sh (prods skema → aktuelle migrationer).
DO $key_v1_unchanged$
DECLARE v_cited jsonb := '[{"ordinal":2,"verbatim_sha256":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"},{"ordinal":1,"verbatim_sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},{"ordinal":2,"verbatim_sha256":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}]';
BEGIN
  IF private.interpretation_proposal_key(3,'record-1','person.name',v_cited,'"Anna Alfa"'::jsonb)
       <> '501f645f-62b6-5ad6-84a9-38173cb1a9fd'::uuid
     OR private.interpretation_proposal_key_material(3,'record-1','person.name',v_cited,'"Anna Alfa"'::jsonb)
       <> '{"ordinals": [1, 2], "predicate": "person.name", "source_id": 3, "record_key": "record-1", "key_version": 1, "value_sha256": "'
          ||encode(extensions.digest(convert_to('"Anna Alfa"','UTF8'),'sha256'),'hex')||'"}' THEN
    RAISE EXCEPTION 'PROPOSAL_KEY_V1_CHANGED';
  END IF;
END $key_v1_unchanged$;

-- key_version 2 (trin 6a, spec §4.4 pkt. 6; Codex F5): som v1 med key_version 2 og helpostens tekstversionsnummer.
-- Tekstvejen B → C → B giver tre forskellige nøgler (v1 uden version, v2 med version 1 og 2); nøglen er deterministisk
-- og uafhængig af citaternes rækkefølge og hashes; en manglende version afvises.
DO $key_v2$
DECLARE v_cited jsonb := '[{"ordinal":2,"verbatim_sha256":"b"},{"ordinal":1,"verbatim_sha256":"a"}]';
  v_value jsonb := '"Anna Alfa"'; k_b uuid; k_c uuid; k_b2 uuid;
BEGIN
  IF to_regprocedure('private.interpretation_proposal_key_material_v2(bigint,text,text,jsonb,jsonb,integer)') IS NULL THEN
    RAISE EXCEPTION 'PROPOSAL_KEY_V2_MISSING';
  END IF;
  IF has_function_privilege('authenticated','private.interpretation_proposal_key_material_v2(bigint,text,text,jsonb,jsonb,integer)','EXECUTE')
     OR has_function_privilege('anon','private.interpretation_proposal_key_material_v2(bigint,text,text,jsonb,jsonb,integer)','EXECUTE')
     OR has_function_privilege('service_role','private.interpretation_proposal_key_material_v2(bigint,text,text,jsonb,jsonb,integer)','EXECUTE') THEN
    RAISE EXCEPTION 'PROPOSAL_KEY_V2_ACL_INVALID';
  END IF;
  IF private.interpretation_proposal_key_material_v2(3,'record-1','person.name',v_cited,v_value,7)::jsonb
       <> private.interpretation_proposal_key_material(3,'record-1','person.name',v_cited,v_value)::jsonb
          ||'{"key_version":2,"text_version":7}'::jsonb
     OR private.interpretation_proposal_key_material_v2(3,'record-1','person.name',v_cited,v_value,7)
       <> private.interpretation_proposal_key_material_v2(3,'record-1','person.name',
            '[{"ordinal":1,"verbatim_sha256":"x"},{"ordinal":2,"verbatim_sha256":"y"},{"ordinal":1,"verbatim_sha256":"z"}]',v_value,7) THEN
    RAISE EXCEPTION 'PROPOSAL_KEY_V2_MATERIAL_INVALID: %',private.interpretation_proposal_key_material_v2(3,'record-1','person.name',v_cited,v_value,7);
  END IF;
  k_b := private.interpretation_proposal_key(3,'record-1','person.name',v_cited,v_value);
  k_c := private.deterministic_uuid(private.interpretation_proposal_key_material_v2(3,'record-1','person.name',v_cited,v_value,1));
  k_b2 := private.deterministic_uuid(private.interpretation_proposal_key_material_v2(3,'record-1','person.name',v_cited,v_value,2));
  IF k_b=k_c OR k_c=k_b2 OR k_b=k_b2
     OR k_c<>private.deterministic_uuid(private.interpretation_proposal_key_material_v2(3,'record-1','person.name',v_cited,v_value,1)) THEN
    RAISE EXCEPTION 'PROPOSAL_KEY_V2_B_C_B_COLLISION';
  END IF;
  PERFORM pg_temp.expect_error('REIMPORT_WRITER_INTERPRETATION_KEY_VERSION_INVALID',
    $q$SELECT private.interpretation_proposal_key_material_v2(3,'record-1','person.name','[{"ordinal":1}]','"x"',NULL)$q$);
  PERFORM pg_temp.expect_error('REIMPORT_WRITER_INTERPRETATION_KEY_VERSION_INVALID',
    $q$SELECT private.interpretation_proposal_key_material_v2(3,'record-1','person.name','[{"ordinal":1}]','"x"',0)$q$);
END $key_v2$;

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

-- SQL↔Python golden vectors (review I7). Samme konstanter pinnes i
-- test_compare_interpretation_proposal_projection.py::test_sql_python_golden_vectors.
DO $golden_vectors$
DECLARE v record;
BEGIN
  FOR v IN SELECT * FROM (VALUES
    (convert_from('\x7b22636f6d706f736564223a22c3a5222c226465636f6d706f736564223a2261cc8a227d'::bytea,'UTF8'),
     convert_from('\x7b22636f6d706f736564223a22c3a5222c226465636f6d706f736564223a2261cc8a227d'::bytea,'UTF8'),
     '79d313486ba5f3595e187ee1468b7371307aabb9d0e010f04ffa0a21e8f66b98'),
    ('{"q":"\"","b":"\\","ctl":"\b\t\n\f\r\u0001\u001f","astral":"😀"}',
     '{"astral":"😀","b":"\\","ctl":"\b\t\n\f\r\u0001\u001f","q":"\""}',
     'a2c3d9789f87d11efa220282937d757adfb14e0266f8b4367d04d9b067dc8320'),
    ('[9223372036854775807,-9223372036854775808,0,true,false,null]',
     '[9223372036854775807,-9223372036854775808,0,true,false,null]',
     'de9f96b75b08cb3b032d8c5ff12350e1cd281b929f81ca5b6512cbec0ddc4ef3'),
    ('{"z":{"b":1,"a":[{"y":2,"x":1}]},"A":"Æ"}',
     '{"A":"Æ","z":{"a":[{"x":1,"y":2}],"b":1}}',
     'f3147aad416985003f3f114ea73dfc477e589e6640755cd314df38cc74fee826')
  ) AS t(input, canonical, sha) LOOP
    IF private.interpretation_proposal_canonical_json_text(v.input::jsonb) IS DISTINCT FROM v.canonical
       OR private.interpretation_proposal_canonical_json_sha256(v.input::jsonb) IS DISTINCT FROM v.sha THEN
      RAISE EXCEPTION 'PROPOSAL_GOLDEN_VECTOR_MISMATCH: %', v.sha;
    END IF;
  END LOOP;
END $golden_vectors$;

-- Receipt-hjælperne giver byte-identisk JSON under forskellige sessions-tidszoner (review I7).
DO $receipt_timezone$
DECLARE
  v_link private.interpretation_observation := ROW('11111111-1111-4111-8111-111111111111',
    '22222222-2222-4222-8222-222222222222','supporting',1,'2026-01-01 12:00:00.123456+02')::private.interpretation_observation;
  v_utc text; v_ny text;
BEGIN
  PERFORM set_config('TimeZone','UTC',true);
  v_utc := private.interpretation_proposal_canonical_json_text(private.interpretation_proposal_link_receipt(v_link));
  PERFORM set_config('TimeZone','America/New_York',true);
  v_ny := private.interpretation_proposal_canonical_json_text(private.interpretation_proposal_link_receipt(v_link));
  IF v_utc IS DISTINCT FROM v_ny OR v_utc NOT LIKE '%"created_at":"2026-01-01T10:00:00.123456Z"%' THEN
    RAISE EXCEPTION 'PROPOSAL_RECEIPT_TIMEZONE_DRIFT';
  END IF;
END $receipt_timezone$;

ROLLBACK;
