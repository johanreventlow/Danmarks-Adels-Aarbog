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
-- ===== Task 2: de tre digests (D1-D6) =====
-- D1 a/b: ingen afgørelser; b permuteret. D3 c/d/e: afgørelser. D6 f/g: pack_sha256.
SAVEPOINT v;
SELECT pg_temp.transfer_fx(-4700,'a4710000','b4700000') \g /dev/null
SET CONSTRAINTS ALL IMMEDIATE;
\o /dev/null
\i .claude/skills/daa-extract/scripts/interpretation_transfer_digests.sql
\o
SELECT current_setting('daa.transfer_digests') AS dg_a \gset
ROLLBACK TO SAVEPOINT v;
SAVEPOINT v;
SELECT pg_temp.transfer_fx(-4700,'a4711000','b4700000','Anna død 1850',false,'Anna',true) \g /dev/null
SET CONSTRAINTS ALL IMMEDIATE;
\o /dev/null
\i .claude/skills/daa-extract/scripts/interpretation_transfer_digests.sql
\o
SELECT current_setting('daa.transfer_digests') AS dg_b \gset
ROLLBACK TO SAVEPOINT v;
-- D2 (kommentar): dispositions-evidence (batch_id) er udeladt af digestet; D1 bestod trods ens batch_id pr. variant.
SAVEPOINT v;
SELECT pg_temp.transfer_fx(-4700,'a4712000','b4700000') \g /dev/null
SET CONSTRAINTS ALL IMMEDIATE;
SELECT (SELECT id FROM private.interpretation WHERE interpretation_key='b4700000-0000-4000-8000-000000000001' AND version=1) AS id1,
       (SELECT id FROM private.interpretation WHERE interpretation_key='b4700000-0000-4000-8000-000000000002' AND version=1) AS id2 \gset
SET CONSTRAINTS ALL DEFERRED;
SELECT set_config('request.jwt.claim.sub','a4700000-0000-4000-8000-000000000001',true) \g /dev/null
SET LOCAL ROLE authenticated;
SELECT red_decide_interpretation(:'id1',1,'accepted','{"method":"m"}') \g /dev/null
SELECT red_decide_interpretation(:'id2',1,'rejected','{"method":"m"}') \g /dev/null
RESET ROLE;
SET CONSTRAINTS ALL IMMEDIATE;
\o /dev/null
\i .claude/skills/daa-extract/scripts/interpretation_transfer_digests.sql
\o
SELECT current_setting('daa.transfer_digests') AS dg_c \gset
ROLLBACK TO SAVEPOINT v;
SAVEPOINT v;
SELECT pg_temp.transfer_fx(-4700,'a4713000','b4700000','Anna død 1850',false,'Anna',true) \g /dev/null
SET CONSTRAINTS ALL IMMEDIATE;
SELECT (SELECT id FROM private.interpretation WHERE interpretation_key='b4700000-0000-4000-8000-000000000001' AND version=1) AS id1,
       (SELECT id FROM private.interpretation WHERE interpretation_key='b4700000-0000-4000-8000-000000000002' AND version=1) AS id2 \gset
SET CONSTRAINTS ALL DEFERRED;
SELECT set_config('request.jwt.claim.sub','a4700000-0000-4000-8000-000000000001',true) \g /dev/null
SET LOCAL ROLE authenticated;
SELECT red_decide_interpretation(:'id1',1,'accepted','{"method":"m"}') \g /dev/null
SELECT red_decide_interpretation(:'id2',1,'rejected','{"method":"m"}') \g /dev/null
RESET ROLE;
SET CONSTRAINTS ALL IMMEDIATE;
\o /dev/null
\i .claude/skills/daa-extract/scripts/interpretation_transfer_digests.sql
\o
SELECT current_setting('daa.transfer_digests') AS dg_d \gset
ROLLBACK TO SAVEPOINT v;
SAVEPOINT v;
SELECT pg_temp.transfer_fx(-4700,'a4714000','b4700000') \g /dev/null
SET CONSTRAINTS ALL IMMEDIATE;
SELECT (SELECT id FROM private.interpretation WHERE interpretation_key='b4700000-0000-4000-8000-000000000001' AND version=1) AS id1,
       (SELECT id FROM private.interpretation WHERE interpretation_key='b4700000-0000-4000-8000-000000000002' AND version=1) AS id2 \gset
SET CONSTRAINTS ALL DEFERRED;
SELECT set_config('request.jwt.claim.sub','a4700000-0000-4000-8000-000000000001',true) \g /dev/null
SET LOCAL ROLE authenticated;
SELECT red_decide_interpretation(:'id1',1,'rejected','{"method":"m"}') \g /dev/null
SELECT red_decide_interpretation(:'id2',1,'accepted','{"method":"m"}') \g /dev/null
RESET ROLE;
SET CONSTRAINTS ALL IMMEDIATE;
\o /dev/null
\i .claude/skills/daa-extract/scripts/interpretation_transfer_digests.sql
\o
SELECT current_setting('daa.transfer_digests') AS dg_e \gset
ROLLBACK TO SAVEPOINT v;
SAVEPOINT v;
SELECT pg_temp.transfer_fx(-4700,'a4715000','b4700000') \g /dev/null
SET CONSTRAINTS ALL IMMEDIATE;
SELECT (SELECT id FROM private.interpretation WHERE interpretation_key='b4700000-0000-4000-8000-000000000001' AND version=1) AS id1,
       (SELECT id FROM private.interpretation WHERE interpretation_key='b4700000-0000-4000-8000-000000000002' AND version=1) AS id2 \gset
SET CONSTRAINTS ALL DEFERRED;
SELECT set_config('request.jwt.claim.sub','a4700000-0000-4000-8000-000000000001',true) \g /dev/null
SET LOCAL ROLE authenticated;
SELECT red_decide_interpretation(:'id1',1,'accepted','{"method":"m"}') \g /dev/null
RESET ROLE;
SET CONSTRAINTS ALL IMMEDIATE;
\o /dev/null
\i .claude/skills/daa-extract/scripts/interpretation_transfer_digests.sql
\o
SELECT current_setting('daa.transfer_digests') AS dg_f \gset
ROLLBACK TO SAVEPOINT v;
SAVEPOINT v;
SELECT pg_temp.transfer_fx(-4700,'a4716000','b4700000','Anna død 1850',false,'Anna',true) \g /dev/null
SET CONSTRAINTS ALL IMMEDIATE;
SELECT (SELECT id FROM private.interpretation WHERE interpretation_key='b4700000-0000-4000-8000-000000000001' AND version=1) AS id1,
       (SELECT id FROM private.interpretation WHERE interpretation_key='b4700000-0000-4000-8000-000000000002' AND version=1) AS id2 \gset
SET CONSTRAINTS ALL DEFERRED;
SELECT set_config('request.jwt.claim.sub','a4700000-0000-4000-8000-000000000001',true) \g /dev/null
SET LOCAL ROLE authenticated;
SELECT red_decide_interpretation(:'id1',1,'accepted','{"method":"m","pack_sha256":"x"}') \g /dev/null
RESET ROLE;
SET CONSTRAINTS ALL IMMEDIATE;
\o /dev/null
\i .claude/skills/daa-extract/scripts/interpretation_transfer_digests.sql
\o
SELECT current_setting('daa.transfer_digests') AS dg_g \gset
ROLLBACK TO SAVEPOINT v;
SAVEPOINT v;
SELECT pg_temp.transfer_fx(-4700,'a4718000','b4700000') \g /dev/null
SET CONSTRAINTS ALL IMMEDIATE;
SELECT (SELECT id FROM private.interpretation WHERE interpretation_key='b4700000-0000-4000-8000-000000000001' AND version=1) AS id1,
       (SELECT id FROM private.interpretation WHERE interpretation_key='b4700000-0000-4000-8000-000000000002' AND version=1) AS id2 \gset
SET CONSTRAINTS ALL DEFERRED;
SELECT set_config('request.jwt.claim.sub','a4700000-0000-4000-8000-000000000001',true) \g /dev/null
SET LOCAL ROLE authenticated;
SELECT red_decide_interpretation(:'id1',1,'accepted','{"method":"m2"}') \g /dev/null
RESET ROLE;
SET CONSTRAINTS ALL IMMEDIATE;
\o /dev/null
\i .claude/skills/daa-extract/scripts/interpretation_transfer_digests.sql
\o
SELECT current_setting('daa.transfer_digests') AS dg_i \gset
ROLLBACK TO SAVEPOINT v;
SAVEPOINT v;
SELECT pg_temp.transfer_fx(-4700,'a4719000','b4700000','Anna død 1850',false,'Anne') \g /dev/null
SET CONSTRAINTS ALL IMMEDIATE;
\o /dev/null
\i .claude/skills/daa-extract/scripts/interpretation_transfer_digests.sql
\o
SELECT current_setting('daa.transfer_digests') AS dg_h \gset
ROLLBACK TO SAVEPOINT v;
-- D5: klassifikationen i basisvarianten (senere tasks afhænger af den).
SAVEPOINT v;
SELECT pg_temp.transfer_fx(-4700,'a4717000','b4700000') \g /dev/null
SET CONSTRAINTS ALL IMMEDIATE;
\o /dev/null
\i .claude/skills/daa-extract/scripts/interpretation_control_classification.sql
\o
SELECT (SELECT jsonb_object_agg(i.interpretation_key::text, x->>'class')
          FROM jsonb_array_elements(current_setting('daa.control_result')::jsonb->'items') x
          JOIN private.interpretation i ON i.id=(x->>'interpretation_id')::uuid) AS cls,
       (SELECT (x->>'assertion_id') FROM jsonb_array_elements(current_setting('daa.control_result')::jsonb->'items') x JOIN private.interpretation i ON i.id=(x->>'interpretation_id')::uuid WHERE i.interpretation_key='b4700000-0000-4000-8000-000000000001') AS k1a \gset
ROLLBACK TO SAVEPOINT v;
SELECT set_config('t.cls',:'cls',true), set_config('t.k1a',:'k1a',true) \g /dev/null
SELECT set_config('t.dg_a',:'dg_a',true), set_config('t.dg_b',:'dg_b',true), set_config('t.dg_c',:'dg_c',true),
       set_config('t.dg_d',:'dg_d',true), set_config('t.dg_e',:'dg_e',true), set_config('t.dg_f',:'dg_f',true),
       set_config('t.dg_g',:'dg_g',true), set_config('t.dg_h',:'dg_h',true), set_config('t.dg_i',:'dg_i',true) \g /dev/null
DO $$ DECLARE
  a jsonb := current_setting('t.dg_a')::jsonb; b jsonb := current_setting('t.dg_b')::jsonb;
  c jsonb := current_setting('t.dg_c')::jsonb; d jsonb := current_setting('t.dg_d')::jsonb;
  e jsonb := current_setting('t.dg_e')::jsonb; f jsonb := current_setting('t.dg_f')::jsonb;
  g jsonb := current_setting('t.dg_g')::jsonb; h jsonb := current_setting('t.dg_h')::jsonb; ii jsonb := current_setting('t.dg_i')::jsonb; cls jsonb := current_setting('t.cls')::jsonb;
  empty text := 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
BEGIN
  -- D1: samme indhold, andre id'er og permuteret id-rækkefølge => identiske digests og antal.
  IF a IS DISTINCT FROM b THEN RAISE EXCEPTION 'D1: digests afhænger af id''er (% vs %)', a, b; END IF;
  IF (a->>'n_interpretations')::int <> 3 OR (a->>'n_decided')::int <> 0 OR (a->>'n_bindings')::int <> 0 THEN
    RAISE EXCEPTION 'D1: antal %', a;
  END IF;
  IF a->>'decision_digest' <> empty OR a->>'binding_digest' <> empty THEN
    RAISE EXCEPTION 'D1: tomme lag forventet sha256 af tom streng, fik %', a;
  END IF;
  IF a->'decided_by_method_status' IS DISTINCT FROM '{}'::jsonb THEN RAISE EXCEPTION 'D1: fordeling %', a; END IF;
  -- D3: samme afgørelser, permuteret => ens; ombyttet status => kun decision_digest ændres.
  IF c->>'proposal_digest' <> a->>'proposal_digest' OR d->>'proposal_digest' <> a->>'proposal_digest'
     OR e->>'proposal_digest' <> a->>'proposal_digest' THEN RAISE EXCEPTION 'D3: forslag ændret af afgørelse'; END IF;
  IF c->'decided_by_method_status' IS DISTINCT FROM d->'decided_by_method_status'
     OR c->>'decision_digest' IS DISTINCT FROM d->>'decision_digest' THEN RAISE EXCEPTION 'D3: afgørelser id-afhængige'; END IF;
  IF (c->>'n_decided')::int <> 2 OR c->'decided_by_method_status' IS DISTINCT FROM '{"m|accepted":1,"m|rejected":1}'::jsonb THEN
    RAISE EXCEPTION 'D3: fordeling %', c;
  END IF;
  IF e->>'decision_digest' = c->>'decision_digest' THEN RAISE EXCEPTION 'D3: ombyttet status ikke fanget'; END IF;
  IF c->>'decision_digest' = empty THEN RAISE EXCEPTION 'D3: tomt afgørelseslag'; END IF;
  -- D6: pack_sha256 i evidensen tæller ikke med.
  IF f->>'decision_digest' IS DISTINCT FROM g->>'decision_digest' THEN RAISE EXCEPTION 'D6: pack_sha256 tæller med'; END IF;
  -- D7: indholdsfølsomhed. Ændret værdi => forslag ændres, tomme lag uændret.
  IF h->>'proposal_digest' = a->>'proposal_digest' THEN RAISE EXCEPTION 'D7: proposal_digest ufølsom for værdi'; END IF;
  IF h->>'decision_digest' <> empty OR h->>'binding_digest' <> empty THEN RAISE EXCEPTION 'D7: tomme lag ændret %', h; END IF;
  -- D8: anden metode i evidensen => anden decision_digest og fordeling.
  IF ii->>'decision_digest' = f->>'decision_digest' THEN RAISE EXCEPTION 'D8: decision_digest ufølsom for evidens'; END IF;
  IF ii->'decided_by_method_status' IS DISTINCT FROM '{"m2|accepted":1}'::jsonb THEN RAISE EXCEPTION 'D8: fordeling %', ii; END IF;
  -- D5: klassifikation.
  IF current_setting('t.k1a') <> '-4711' THEN RAISE EXCEPTION 'D5: k1 mål forventet -4711, fik %', current_setting('t.k1a'); END IF;
  IF cls->>'b4700000-0000-4000-8000-000000000001' IS DISTINCT FROM 'MATCH' THEN RAISE EXCEPTION 'D5: k1 forventet MATCH, fik %', cls; END IF;
  IF cls->>'b4700000-0000-4000-8000-000000000002' IS DISTINCT FROM 'REAL_DIFF' THEN RAISE EXCEPTION 'D5: k2 forventet REAL_DIFF, fik %', cls; END IF;
  IF cls ? 'b4700000-0000-4000-8000-000000000003' THEN RAISE EXCEPTION 'D5: k3 forventet fraværende, fik %', cls; END IF;
END $$;
\echo 'OK: transfer digests'
ROLLBACK;
