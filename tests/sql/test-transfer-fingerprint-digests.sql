\set ON_ERROR_STOP on
-- Overførslens fingeraftryk og digests (spec 2026-10-03 §4.2, §5; plan A Task 1-2).
-- Rå tabeller er append-only, og interpretation_key er globalt unik: varianter er ekstra
-- kilder fra pg_temp.transfer_fx med egne nøgler. Fingeraftrykket sammenlignes derfor med
-- en forventning, der bygges af de logiske felter alene (nøgle, post, prædikat, værdi,
-- klausuler) — uden nogen id'er.
BEGIN;
\i tests/sql/transfer-fixture.sql

-- Forventet fingeraftryk for én nøgle.
CREATE FUNCTION pg_temp.exp_fp(p_key text, p_pred text, p_val text, p_clauses jsonb) RETURNS text
LANGUAGE sql AS $$
  SELECT encode(extensions.digest(convert_to(private.interpretation_proposal_canonical_json_text(
    jsonb_build_object('fp_version',1,'interpretation_key',p_key,'record_key','T-1','predicate',p_pred,
      'value_sha256',private.interpretation_proposal_canonical_json_sha256(to_jsonb(p_val)),
      'clauses',p_clauses)),'UTF8'),'sha256'),'hex')
$$;
CREATE FUNCTION pg_temp.h(p_t text) RETURNS text LANGUAGE sql AS
  $$ SELECT encode(extensions.digest(convert_to(p_t,'UTF8'),'sha256'),'hex') $$;
-- Forventet kort {nøgle: fingeraftryk} for en kilde bygget med transfer_fx(…, p_kp, p_c1, p_swap, p_name).
CREATE FUNCTION pg_temp.exp_map(p_kp text, p_c1 text, p_swap boolean, p_name text) RETURNS jsonb
LANGUAGE sql AS $$
  SELECT jsonb_build_object(
    p_kp||'-0000-4000-8000-000000000001', pg_temp.exp_fp(p_kp||'-0000-4000-8000-000000000001','person.death','1850',
        jsonb_build_array(jsonb_build_array(CASE WHEN p_swap THEN 2 ELSE 1 END, pg_temp.h(p_c1)))),
    p_kp||'-0000-4000-8000-000000000002', pg_temp.exp_fp(p_kp||'-0000-4000-8000-000000000002','person.name',p_name,
        jsonb_build_array(jsonb_build_array(CASE WHEN p_swap THEN 2 ELSE 1 END, pg_temp.h(p_c1)))),
    p_kp||'-0000-4000-8000-000000000003', pg_temp.exp_fp(p_kp||'-0000-4000-8000-000000000003','mention.place','Kbh',
        jsonb_build_array(jsonb_build_array(CASE WHEN p_swap THEN 1 ELSE 2 END, pg_temp.h('i Kbh')))))
$$;

SET LOCAL default_transaction_read_only = on;
-- (F1) To kilder med samme logiske indhold, men forskellige uuid'er: fingeraftrykket følger
-- kun de logiske felter, og begge kilder giver præcis det forventede kort.
\set src -4700
\i .claude/skills/daa-extract/scripts/interpretation_decision_fingerprint.sql
DO $$ BEGIN
  IF current_setting('daa.fingerprints')::jsonb IS DISTINCT FROM pg_temp.exp_map('b4700000','Anna død 1850',false,'Anna') THEN
    RAISE EXCEPTION 'F1: kilde -4700 afviger fra forventet (%)', current_setting('daa.fingerprints');
  END IF;
  IF (SELECT count(*) FROM jsonb_object_keys(current_setting('daa.fingerprints')::jsonb)) <> 3 THEN
    RAISE EXCEPTION 'F1: forventede 3 nøgler';
  END IF;
END $$;
\set src -4701
\i .claude/skills/daa-extract/scripts/interpretation_decision_fingerprint.sql
DO $$ BEGIN
  IF current_setting('daa.fingerprints')::jsonb IS DISTINCT FROM pg_temp.exp_map('b4701000','Anna død 1850',false,'Anna') THEN
    RAISE EXCEPTION 'F1: kilde -4701 afviger fra forventet (%)', current_setting('daa.fingerprints');
  END IF;
END $$;

SET LOCAL default_transaction_read_only = off;
-- (F2) Ændret klausultekst, (F3) byttede ordinaler, (F4) ændret værdi — hver som egen kilde.
SELECT pg_temp.transfer_fx(-4702,'a4702000','b4702000','Anna død 1851') \g /dev/null
SELECT pg_temp.transfer_fx(-4703,'a4703000','b4703000','Anna død 1850',true) \g /dev/null
SELECT pg_temp.transfer_fx(-4704,'a4704000','b4704000','Anna død 1850',false,'Anne') \g /dev/null
SET CONSTRAINTS ALL IMMEDIATE;
SET LOCAL default_transaction_read_only = on;

\set src -4702
\i .claude/skills/daa-extract/scripts/interpretation_decision_fingerprint.sql
DO $$ DECLARE a jsonb := current_setting('daa.fingerprints')::jsonb;
  base jsonb := pg_temp.exp_map('b4702000','Anna død 1850',false,'Anna'); k text := 'b4702000-0000-4000-8000-00000000000';
BEGIN
  IF a IS DISTINCT FROM pg_temp.exp_map('b4702000','Anna død 1851',false,'Anna') THEN RAISE EXCEPTION 'F2: afviger fra forventet'; END IF;
  IF a->>(k||'1') = base->>(k||'1') OR a->>(k||'2') = base->>(k||'2') THEN RAISE EXCEPTION 'F2: tekst ikke bundet'; END IF;
  IF a->>(k||'3') <> base->>(k||'3') THEN RAISE EXCEPTION 'F2: urelateret nøgle ændret'; END IF;
END $$;

\set src -4703
\i .claude/skills/daa-extract/scripts/interpretation_decision_fingerprint.sql
DO $$ DECLARE a jsonb := current_setting('daa.fingerprints')::jsonb;
  base jsonb := pg_temp.exp_map('b4703000','Anna død 1850',false,'Anna'); k text := 'b4703000-0000-4000-8000-00000000000';
BEGIN
  IF a IS DISTINCT FROM pg_temp.exp_map('b4703000','Anna død 1850',true,'Anna') THEN RAISE EXCEPTION 'F3: afviger fra forventet'; END IF;
  IF a->>(k||'3') = base->>(k||'3') THEN RAISE EXCEPTION 'F3: ordinal ikke bundet'; END IF;
END $$;

\set src -4704
\i .claude/skills/daa-extract/scripts/interpretation_decision_fingerprint.sql
DO $$ DECLARE a jsonb := current_setting('daa.fingerprints')::jsonb;
  base jsonb := pg_temp.exp_map('b4704000','Anna død 1850',false,'Anna'); k text := 'b4704000-0000-4000-8000-00000000000';
BEGIN
  IF a IS DISTINCT FROM pg_temp.exp_map('b4704000','Anna død 1850',false,'Anne') THEN RAISE EXCEPTION 'F4: afviger fra forventet'; END IF;
  IF a->>(k||'2') = base->>(k||'2') THEN RAISE EXCEPTION 'F4: værdi ikke bundet'; END IF;
  IF a->>(k||'1') <> base->>(k||'1') OR a->>(k||'3') <> base->>(k||'3') THEN RAISE EXCEPTION 'F4: urelateret nøgle ændret'; END IF;
END $$;
\echo 'OK: transfer fingerprint'
ROLLBACK;
