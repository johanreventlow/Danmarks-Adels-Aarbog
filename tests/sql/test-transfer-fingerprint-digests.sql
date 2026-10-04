\set ON_ERROR_STOP on
-- Overførslens fingeraftryk og digests (spec 2026-10-03 §4.2, §5; plan A Task 1-2).
-- Restore og prod har samme kilde-id og samme nøgler, men forskellige uuid'er. Hver variant
-- bygges som kilde -4700 med nøgler b4700000, kun med eget uuid-præfiks og det varierede
-- felt, måles og rulles tilbage (SAVEPOINT). Fingeraftrykkene sammenlignes variant mod variant.
--   a basis  b permuterede uuid-suffikser (id-rækkefølgen vendt)  c klausultekst  d ordinaler
--   e værdi  f postnøgle  g intet anker
BEGIN;
\i tests/sql/transfer-fixture.sql
\set src -4700
SAVEPOINT v;
SELECT pg_temp.transfer_fx(-4700,'a4700000','b4700000') \g /dev/null
SET CONSTRAINTS ALL IMMEDIATE;
\o /dev/null
\i .claude/skills/daa-extract/scripts/interpretation_decision_fingerprint.sql
\o
SELECT current_setting('daa.fingerprints') AS fp_a, current_setting('daa.fingerprint_record_check') AS rc_a \gset
ROLLBACK TO SAVEPOINT v;
SAVEPOINT v;
SELECT pg_temp.transfer_fx(-4700,'a4701000','b4700000','Anna død 1850',false,'Anna',true) \g /dev/null
SET CONSTRAINTS ALL IMMEDIATE;
\o /dev/null
\i .claude/skills/daa-extract/scripts/interpretation_decision_fingerprint.sql
\o
SELECT current_setting('daa.fingerprints') AS fp_b, current_setting('daa.fingerprint_record_check') AS rc_b \gset
ROLLBACK TO SAVEPOINT v;
SAVEPOINT v;
SELECT pg_temp.transfer_fx(-4700,'a4702000','b4700000','Anna død 1851') \g /dev/null
SET CONSTRAINTS ALL IMMEDIATE;
\o /dev/null
\i .claude/skills/daa-extract/scripts/interpretation_decision_fingerprint.sql
\o
SELECT current_setting('daa.fingerprints') AS fp_c, current_setting('daa.fingerprint_record_check') AS rc_c \gset
ROLLBACK TO SAVEPOINT v;
SAVEPOINT v;
SELECT pg_temp.transfer_fx(-4700,'a4703000','b4700000','Anna død 1850',true) \g /dev/null
SET CONSTRAINTS ALL IMMEDIATE;
\o /dev/null
\i .claude/skills/daa-extract/scripts/interpretation_decision_fingerprint.sql
\o
SELECT current_setting('daa.fingerprints') AS fp_d, current_setting('daa.fingerprint_record_check') AS rc_d \gset
ROLLBACK TO SAVEPOINT v;
SAVEPOINT v;
SELECT pg_temp.transfer_fx(-4700,'a4704000','b4700000','Anna død 1850',false,'Anne') \g /dev/null
SET CONSTRAINTS ALL IMMEDIATE;
\o /dev/null
\i .claude/skills/daa-extract/scripts/interpretation_decision_fingerprint.sql
\o
SELECT current_setting('daa.fingerprints') AS fp_e, current_setting('daa.fingerprint_record_check') AS rc_e \gset
ROLLBACK TO SAVEPOINT v;
SAVEPOINT v;
SELECT pg_temp.transfer_fx(-4700,'a4705000','b4700000','Anna død 1850',false,'Anna',false,'T-2') \g /dev/null
SET CONSTRAINTS ALL IMMEDIATE;
\o /dev/null
\i .claude/skills/daa-extract/scripts/interpretation_decision_fingerprint.sql
\o
SELECT current_setting('daa.fingerprints') AS fp_f, current_setting('daa.fingerprint_record_check') AS rc_f \gset
ROLLBACK TO SAVEPOINT v;
SAVEPOINT v;
SELECT pg_temp.transfer_fx(-4700,'a4706000','b4700000','Anna død 1850',false,'Anna',false,'T-1',false) \g /dev/null
SET CONSTRAINTS ALL IMMEDIATE;
\o /dev/null
\i .claude/skills/daa-extract/scripts/interpretation_decision_fingerprint.sql
\o
SELECT current_setting('daa.fingerprints') AS fp_g, current_setting('daa.fingerprint_record_check') AS rc_g \gset
ROLLBACK TO SAVEPOINT v;
SELECT set_config('t.a',:'fp_a',true), set_config('t.b',:'fp_b',true), set_config('t.c',:'fp_c',true),
       set_config('t.d',:'fp_d',true), set_config('t.e',:'fp_e',true), set_config('t.f',:'fp_f',true),
       set_config('t.g',:'fp_g',true), set_config('t.rca',:'rc_a',true), set_config('t.rcb',:'rc_b',true),
       set_config('t.rcf',:'rc_f',true), set_config('t.rcg',:'rc_g',true) \g /dev/null
DO $$ DECLARE
  a jsonb := current_setting('t.a')::jsonb; b jsonb := current_setting('t.b')::jsonb;
  c jsonb := current_setting('t.c')::jsonb; d jsonb := current_setting('t.d')::jsonb;
  e jsonb := current_setting('t.e')::jsonb; f jsonb := current_setting('t.f')::jsonb;
  g jsonb := current_setting('t.g')::jsonb;
  k1 text := 'b4700000-0000-4000-8000-000000000001'; k2 text := 'b4700000-0000-4000-8000-000000000002';
  k3 text := 'b4700000-0000-4000-8000-000000000003';
  m jsonb;
BEGIN
  -- Sanity: 3 nøgler, alle værdier sha256-hex, samme nøglesæt i alle varianter.
  IF (SELECT count(*) FROM jsonb_object_keys(a)) <> 3 THEN RAISE EXCEPTION 'F0: forventede 3 nøgler'; END IF;
  IF EXISTS (SELECT 1 FROM jsonb_each_text(a) WHERE value !~ '^[0-9a-f]{64}$') THEN RAISE EXCEPTION 'F0: ikke sha256-hex'; END IF;
  FOREACH m IN ARRAY ARRAY[b,c,d,e,f,g] LOOP
    IF ARRAY(SELECT jsonb_object_keys(m) ORDER BY 1) IS DISTINCT FROM ARRAY(SELECT jsonb_object_keys(a) ORDER BY 1) THEN
      RAISE EXCEPTION 'F0: nøglesæt afviger';
    END IF;
  END LOOP;
  -- F1: samme indhold, andre uuid'er og vendt id-rækkefølge => identiske kort.
  IF a IS DISTINCT FROM b THEN RAISE EXCEPTION 'F1: fingeraftryk afhænger af id''er eller id-rækkefølge'; END IF;
  -- F2: ændret klausultekst => k1 og k2 ændres, k3 uændret.
  IF c->>k1 IS NOT DISTINCT FROM a->>k1 OR c->>k2 IS NOT DISTINCT FROM a->>k2 THEN RAISE EXCEPTION 'F2: tekst ikke bundet'; END IF;
  IF c->>k3 IS DISTINCT FROM a->>k3 THEN RAISE EXCEPTION 'F2: urelateret nøgle ændret'; END IF;
  -- F3: byttede klausulordinaler => alle tre citerer en klausul med ny ordinal.
  IF d->>k1 IS NOT DISTINCT FROM a->>k1 OR d->>k2 IS NOT DISTINCT FROM a->>k2
     OR d->>k3 IS NOT DISTINCT FROM a->>k3 THEN RAISE EXCEPTION 'F3: ordinal ikke bundet'; END IF;
  -- F4: ændret værdi => kun k2.
  IF e->>k2 IS NOT DISTINCT FROM a->>k2 THEN RAISE EXCEPTION 'F4: værdi ikke bundet'; END IF;
  IF e->>k1 IS DISTINCT FROM a->>k1 OR e->>k3 IS DISTINCT FROM a->>k3 THEN RAISE EXCEPTION 'F4: urelateret nøgle ændret'; END IF;
  -- F5: anden postnøgle => alle tre ændres.
  IF f->>k1 IS NOT DISTINCT FROM a->>k1 OR f->>k2 IS NOT DISTINCT FROM a->>k2
     OR f->>k3 IS NOT DISTINCT FROM a->>k3 THEN RAISE EXCEPTION 'F5: postnøgle ikke bundet'; END IF;
  -- F6: record_check. Basis og permuteret: 0/0; intet anker: 3 uden post.
  IF current_setting('t.rca')::jsonb IS DISTINCT FROM '{"n_no_record":0,"n_multi_record":0}'::jsonb
     OR current_setting('t.rcb')::jsonb IS DISTINCT FROM '{"n_no_record":0,"n_multi_record":0}'::jsonb
     OR current_setting('t.rcf')::jsonb IS DISTINCT FROM '{"n_no_record":0,"n_multi_record":0}'::jsonb THEN
    RAISE EXCEPTION 'F6: record_check forventet 0/0';
  END IF;
  IF current_setting('t.rcg')::jsonb IS DISTINCT FROM '{"n_no_record":3,"n_multi_record":0}'::jsonb THEN
    RAISE EXCEPTION 'F6: uden anker forventet n_no_record=3, fik %', current_setting('t.rcg');
  END IF;
END $$;
\echo 'OK: transfer fingerprint'
ROLLBACK;
