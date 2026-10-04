\set ON_ERROR_STOP on
-- Overførslens fingeraftryk og digests (spec 2026-10-03 §4.2, §5; plan A Task 1-2).
-- Restore og prod har samme kilde-id og samme nøgler, men forskellige uuid'er. Hver variant
-- bygges derfor som kilde -4700 med nøgler b4700000, kun med eget uuid-præfiks og det varierede
-- felt, måles og rulles tilbage (SAVEPOINT). Fingeraftrykkene sammenlignes variant mod variant.
BEGIN;
\i tests/sql/transfer-fixture.sql
\set src -4700
SAVEPOINT v;
SELECT pg_temp.transfer_fx(-4700,'a4700000','b4700000') \g /dev/null
SET CONSTRAINTS ALL IMMEDIATE;
\i .claude/skills/daa-extract/scripts/interpretation_decision_fingerprint.sql
SELECT current_setting('daa.fingerprints') AS fp_a \gset
ROLLBACK TO SAVEPOINT v;
SAVEPOINT v;
SELECT pg_temp.transfer_fx(-4700,'a4701000','b4700000') \g /dev/null
SET CONSTRAINTS ALL IMMEDIATE;
\i .claude/skills/daa-extract/scripts/interpretation_decision_fingerprint.sql
SELECT current_setting('daa.fingerprints') AS fp_b \gset
ROLLBACK TO SAVEPOINT v;
SAVEPOINT v;
SELECT pg_temp.transfer_fx(-4700,'a4702000','b4700000','Anna død 1851') \g /dev/null
SET CONSTRAINTS ALL IMMEDIATE;
\i .claude/skills/daa-extract/scripts/interpretation_decision_fingerprint.sql
SELECT current_setting('daa.fingerprints') AS fp_c \gset
ROLLBACK TO SAVEPOINT v;
SAVEPOINT v;
SELECT pg_temp.transfer_fx(-4700,'a4703000','b4700000','Anna død 1850',true) \g /dev/null
SET CONSTRAINTS ALL IMMEDIATE;
\i .claude/skills/daa-extract/scripts/interpretation_decision_fingerprint.sql
SELECT current_setting('daa.fingerprints') AS fp_d \gset
ROLLBACK TO SAVEPOINT v;
SAVEPOINT v;
SELECT pg_temp.transfer_fx(-4700,'a4704000','b4700000','Anna død 1850',false,'Anne') \g /dev/null
SET CONSTRAINTS ALL IMMEDIATE;
\i .claude/skills/daa-extract/scripts/interpretation_decision_fingerprint.sql
SELECT current_setting('daa.fingerprints') AS fp_e \gset
ROLLBACK TO SAVEPOINT v;
SELECT set_config('t.a',:'fp_a',true), set_config('t.b',:'fp_b',true), set_config('t.c',:'fp_c',true),
       set_config('t.d',:'fp_d',true), set_config('t.e',:'fp_e',true) \g /dev/null
DO $$ DECLARE
  a jsonb := current_setting('t.a')::jsonb; b jsonb := current_setting('t.b')::jsonb;
  c jsonb := current_setting('t.c')::jsonb; d jsonb := current_setting('t.d')::jsonb;
  e jsonb := current_setting('t.e')::jsonb;
  k1 text := 'b4700000-0000-4000-8000-000000000001'; k2 text := 'b4700000-0000-4000-8000-000000000002';
  k3 text := 'b4700000-0000-4000-8000-000000000003';
BEGIN
  -- Sanity: 3 nøgler, alle værdier sha256-hex.
  IF (SELECT count(*) FROM jsonb_object_keys(a)) <> 3 THEN RAISE EXCEPTION 'F0: forventede 3 nøgler'; END IF;
  IF EXISTS (SELECT 1 FROM jsonb_each_text(a) WHERE value !~ '^[0-9a-f]{64}$') THEN RAISE EXCEPTION 'F0: ikke sha256-hex'; END IF;
  -- F1: samme indhold, andre uuid'er => identiske kort.
  IF a IS DISTINCT FROM b THEN RAISE EXCEPTION 'F1: fingeraftryk afhænger af id''er'; END IF;
  -- F2: ændret klausultekst => k1 og k2 (citerer klausul 1) ændres, k3 uændret.
  IF c->>k1 = a->>k1 OR c->>k2 = a->>k2 THEN RAISE EXCEPTION 'F2: tekst ikke bundet'; END IF;
  IF c->>k3 <> a->>k3 THEN RAISE EXCEPTION 'F2: urelateret nøgle ændret'; END IF;
  -- F3: byttede ordinaler => alle tre citerede klausuler har ny ordinal.
  IF d->>k1 = a->>k1 OR d->>k2 = a->>k2 OR d->>k3 = a->>k3 THEN RAISE EXCEPTION 'F3: ordinal ikke bundet'; END IF;
  -- F4: ændret værdi => kun k2.
  IF e->>k2 = a->>k2 THEN RAISE EXCEPTION 'F4: værdi ikke bundet'; END IF;
  IF e->>k1 <> a->>k1 OR e->>k3 <> a->>k3 THEN RAISE EXCEPTION 'F4: urelateret nøgle ændret'; END IF;
END $$;
\echo 'OK: transfer fingerprint'
ROLLBACK;
