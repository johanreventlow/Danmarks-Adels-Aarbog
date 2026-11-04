\set ON_ERROR_STOP on
-- Trin 6c-2b (spec 2026-11-02 §4.3): normaliser_dato_markoer_v1 og red_normaliser_forslag. Alt syntetisk; rulles tilbage,
-- så filen kan køres flere gange mod samme base.
BEGIN;
-- Kører p_sql som p_role (pg_temp-funktioner kan ikke kaldes af API-rollerne, så rollen skiftes indeni).
CREATE FUNCTION pg_temp.expect_error(p_sql text, p_token text, p_role text DEFAULT 'authenticated') RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    EXECUTE format('SET LOCAL ROLE %I',p_role);
    EXECUTE p_sql;
  EXCEPTION WHEN OTHERS THEN
    RESET ROLE;
    IF SQLERRM IS NULL OR SQLERRM NOT LIKE p_token||'%' THEN
      RAISE EXCEPTION 'NORMALISERING_TEST_WRONG_ERROR: expected % got %', p_token, SQLERRM; END IF; RETURN; END;
  RESET ROLE;
  RAISE EXCEPTION 'NORMALISERING_TEST_NO_ERROR: expected %', p_token;
END $$;

-- 1) Regelfunktionen.
DO $t1$
DECLARE r record;
BEGIN
  FOR r IN SELECT * FROM (VALUES
    (E'f. 12. marts 1702', '12. marts 1702'),
    (E'†  1750', '1750'),
    (E'12. marts\n1702', '12. marts 1702'),
    (E'  f.\n12. marts   1702 ', '12. marts 1702'),
    (E'død 1750', 'død 1750'),
    (E'ff. 1702', 'ff. 1702'),
    (E'1702', '1702'),
    (E'f. f. 1702', 'f. 1702'),
    -- Trin 6c-2b: blanktegn samles med saml_blanktegn_v1 (eksplicit klasse, uafhængig af collation): hårdt mellemrum
    -- efter markøren og inde i datoen, smalt hårdt mellemrum og afsnitsskift.
    (E'f.\u00a012.\u00a0marts 1702', '12. marts 1702'),
    (E'\u2020\u202f1750\u2029', '1750')) v(i,o)
  LOOP
    IF private.normaliser_dato_markoer_v1(r.i) IS DISTINCT FROM r.o THEN
      RAISE EXCEPTION 'NORMALISERING_TEST_REGEL: % gav % (ventede %)',r.i,private.normaliser_dato_markoer_v1(r.i),r.o;
    END IF;
  END LOOP;
  IF (SELECT provolatile FROM pg_proc WHERE oid='private.normaliser_dato_markoer_v1(text)'::regprocedure)<>'i' THEN
    RAISE EXCEPTION 'NORMALISERING_TEST_IMMUTABLE';
  END IF;
END $t1$;

-- 2) Fixtur: kilde, to kørsler, én observation, fem forslag (birth med markør, death uden ændring, name, accepteret, to nøgler).
INSERT INTO auth.users(id,email) VALUES ('a6c20000-0000-4000-8000-000000000001','norm6c2@test.invalid'),
  ('a6c20000-0000-4000-8000-000000000002','laeser6c2@test.invalid');
INSERT INTO profiles(id,rolle,navn,email) VALUES
  ('a6c20000-0000-4000-8000-000000000001','redaktion','Norm 6c2','norm6c2@test.invalid'),
  ('a6c20000-0000-4000-8000-000000000002','medlem','Laeser 6c2','laeser6c2@test.invalid');
INSERT INTO source(id,titel,import_key) VALUES (-96200,'Norm 6c2','verify:norm6c2'),(-96201,'Norm 6c2 anden','verify:norm6c2b');
INSERT INTO private.extraction_run(id,source_id,run_key,schema_version,extractor_version,profile_version,input_sha256,manifest) VALUES
  ('a6c20000-0000-4000-8000-0000000000e1',-96200,'norm6c2-run1','1.0','verify','verify',repeat('9',64),'{}'),
  ('a6c20000-0000-4000-8000-0000000000e5',-96200,'norm6c2-run2','1.0','verify','verify',repeat('7',64),'{}'),
  ('a6c20000-0000-4000-8000-0000000000e6',-96201,'norm6c2-run3','1.0','verify','verify',repeat('6',64),'{}');
INSERT INTO private.source_rendition(id,source_id,rendition_key,rendition_kind,content_sha256,metadata)
  VALUES ('a6c20000-0000-4000-8000-0000000000e2',-96200,'norm6c2-rendition','text_layer',repeat('8',64),'{}');
INSERT INTO private.source_record_occurrence(id,rendition_id,occurrence_key,page_from,page_to,char_from,char_to,
  verbatim_text,physical_fingerprint,structural_fingerprint,extraction_run_id)
  VALUES ('a6c20000-0000-4000-8000-0000000000e3','a6c20000-0000-4000-8000-0000000000e2','norm6c2-occ',1,1,0,4,
          '1702','phys-norm6c2','struct-norm6c2','a6c20000-0000-4000-8000-0000000000e1');
INSERT INTO private.source_observation(id,occurrence_id,observation_kind,page_from,page_to,char_from,char_to,
  verbatim_text,quality_status,extraction_method,extraction_run_id)
  VALUES ('a6c20000-0000-4000-8000-0000000000e4','a6c20000-0000-4000-8000-0000000000e3','name_clause',1,1,0,4,
          '1702','clear','verify','a6c20000-0000-4000-8000-0000000000e1');
-- n: 1 birth 'f. 12. marts 1702' | 2 death '† 1750' | 3 birth '1702' (uændret) | 4 name 'f. Anna' | 5 death 'f. 1800' (accepteres)
-- 6 birth 'død 1750' | 7 death 'f.' (tom efter reglen)
INSERT INTO private.interpretation(id,interpretation_key,version,source_id,interpretation_kind,predicate,value,
  schema_version,derivation_kind,confidence,status,method,model_version,prompt_version,extraction_run_id)
  SELECT ('a6c20000-0000-4000-8000-0000000003'||lpad(n::text,2,'0'))::uuid,
         ('a6c20000-0000-4000-8000-0000000004'||lpad(n::text,2,'0'))::uuid,1,-96200,'property',
         CASE n WHEN 1 THEN 'person.birth' WHEN 2 THEN 'person.death' WHEN 3 THEN 'person.birth' WHEN 4 THEN 'person.name'
                WHEN 5 THEN 'person.death' WHEN 6 THEN 'person.birth' ELSE 'person.death' END,
         to_jsonb(CASE n WHEN 1 THEN E'f. 12. marts\n1702' WHEN 2 THEN '† 1750' WHEN 3 THEN '1702' WHEN 4 THEN 'f. Anna'
                         WHEN 5 THEN 'f. 1800' WHEN 6 THEN 'død 1750' ELSE 'f.' END),
         '1.1','model_inference',0.8,'proposed','model-x','m-1','p-1','a6c20000-0000-4000-8000-0000000000e1'
    FROM generate_series(1,7) n;
INSERT INTO private.interpretation_observation(interpretation_id,observation_id,evidence_role,ordinal)
  SELECT ('a6c20000-0000-4000-8000-0000000003'||lpad(n::text,2,'0'))::uuid,'a6c20000-0000-4000-8000-0000000000e4','supporting',1
    FROM generate_series(1,7) n;
SET CONSTRAINTS private.interpretation_has_observation IMMEDIATE;
SET CONSTRAINTS private.interpretation_has_observation DEFERRED;

-- 3) Uden rolle afvises (ingen aktør, og læser).
SELECT pg_temp.expect_error($q$SELECT red_normaliser_forslag('a6c20000-0000-4000-8000-000000000301',1,'dato-markoer-v1')$q$,'EVIDENCE_ROLE_FORBIDDEN');
SELECT set_config('request.jwt.claim.sub','a6c20000-0000-4000-8000-000000000002',true);
SELECT pg_temp.expect_error($q$SELECT red_normaliser_forslag('a6c20000-0000-4000-8000-000000000301',1,'dato-markoer-v1')$q$,'EVIDENCE_ROLE_FORBIDDEN');
-- anon har ikke EXECUTE.
SELECT pg_temp.expect_error($q$SELECT red_normaliser_forslag('a6c20000-0000-4000-8000-000000000301',1,'dato-markoer-v1')$q$,'permission denied','anon');

-- 4) Fejlkoder som redaktør.
SELECT set_config('request.jwt.claim.sub','a6c20000-0000-4000-8000-000000000001',true);
-- kørsel mangler (GUC ikke sat)
SELECT pg_temp.expect_error($q$SELECT red_normaliser_forslag('a6c20000-0000-4000-8000-000000000301',1,'dato-markoer-v1')$q$,'NORMALISERING_KOERSEL_MANGLER');
-- kørsel hører til en anden kilde
SELECT set_config('daa.extraction_run_id','a6c20000-0000-4000-8000-0000000000e6',true);
SELECT pg_temp.expect_error($q$SELECT red_normaliser_forslag('a6c20000-0000-4000-8000-000000000301',1,'dato-markoer-v1')$q$,'NORMALISERING_KOERSEL_MANGLER');
SELECT set_config('daa.extraction_run_id','a6c20000-0000-4000-8000-0000000000e5',true);
SELECT pg_temp.expect_error($q$SELECT red_normaliser_forslag('a6c20000-0000-4000-8000-000000000301',2,'dato-markoer-v1')$q$,'NORMALISERING_VERSION_KONFLIKT');
SELECT pg_temp.expect_error($q$SELECT red_normaliser_forslag('a6c20000-0000-4000-8000-000000000304',1,'dato-markoer-v1')$q$,'NORMALISERING_PRAEDIKAT_UGYLDIG');
SELECT pg_temp.expect_error($q$SELECT red_normaliser_forslag('a6c20000-0000-4000-8000-000000000301',1,'andet-v1')$q$,'NORMALISERING_REGEL_UKENDT');
SELECT pg_temp.expect_error($q$SELECT red_normaliser_forslag('a6c20000-0000-4000-8000-000000000303',1,'dato-markoer-v1')$q$,'NORMALISERING_UAENDRET');
SELECT pg_temp.expect_error($q$SELECT red_normaliser_forslag('a6c20000-0000-4000-8000-000000000306',1,'dato-markoer-v1')$q$,'NORMALISERING_UAENDRET');
SELECT pg_temp.expect_error($q$SELECT red_normaliser_forslag('a6c20000-0000-4000-8000-000000000307',1,'dato-markoer-v1')$q$,'NORMALISERING_VAERDI_TOM');
-- accepteret forslag
SELECT red_decide_interpretation('a6c20000-0000-4000-8000-000000000305',1,'accepted','{"basis":"norm6c2"}');
RESET ROLE;
SELECT set_config('request.jwt.claim.sub','a6c20000-0000-4000-8000-000000000001',true);
SELECT pg_temp.expect_error(format($q$SELECT red_normaliser_forslag(%L,2,'dato-markoer-v1')$q$,
  (SELECT id FROM private.interpretation WHERE interpretation_key='a6c20000-0000-4000-8000-000000000405' AND version=2)),
  'NORMALISERING_IKKE_PROPOSED');

-- 5) Version 2 af birth-forslaget.
SET LOCAL ROLE authenticated;
CREATE TEMP TABLE norm_result AS
  SELECT red_normaliser_forslag('a6c20000-0000-4000-8000-000000000301',1,'dato-markoer-v1') AS j;
GRANT SELECT ON norm_result TO authenticated;
RESET ROLE;
DO $t5$
DECLARE v1 private.interpretation%ROWTYPE; v2 private.interpretation%ROWTYPE; j jsonb; n int;
BEGIN
  SELECT nr.j INTO j FROM norm_result nr;
  SELECT * INTO v1 FROM private.interpretation WHERE id='a6c20000-0000-4000-8000-000000000301';
  SELECT * INTO v2 FROM private.interpretation WHERE id=(j->>'interpretation_id')::uuid;
  IF v2.version<>2 OR v2.status<>'proposed' OR v2.derivation_kind<>'deterministic'
     OR v2.supersedes_id<>v1.id OR v2.interpretation_key<>v1.interpretation_key OR v2.source_id<>v1.source_id
     OR v2.value<>to_jsonb('12. marts 1702'::text)
     OR v2.method<>'deterministisk-normalisering:dato-markoer-v1'
     OR v2.extraction_run_id<>'a6c20000-0000-4000-8000-0000000000e5'
     OR v2.predicate<>v1.predicate OR v2.interpretation_kind<>v1.interpretation_kind OR v2.confidence<>v1.confidence
     OR v2.schema_version<>v1.schema_version OR v2.model_version IS DISTINCT FROM v1.model_version
     OR v2.prompt_version IS DISTINCT FROM v1.prompt_version OR v2.source_persona_id IS DISTINCT FROM v1.source_persona_id
     OR v2.decided_by IS NOT NULL OR v2.decision_evidence<>'{}'::jsonb THEN
    RAISE EXCEPTION 'NORMALISERING_TEST_V2: %',to_jsonb(v2);
  END IF;
  -- v1 uændret.
  IF v1.value<>to_jsonb(E'f. 12. marts\n1702'::text) OR v1.status<>'proposed' OR v1.method<>'model-x' THEN
    RAISE EXCEPTION 'NORMALISERING_TEST_V1_AENDRET';
  END IF;
  SELECT count(*) INTO n FROM private.interpretation_observation WHERE interpretation_id=v2.id
     AND observation_id='a6c20000-0000-4000-8000-0000000000e4' AND evidence_role='supporting' AND ordinal=1;
  IF n<>1 OR (SELECT count(*) FROM private.interpretation_observation WHERE interpretation_id=v2.id)<>1 THEN
    RAISE EXCEPTION 'NORMALISERING_TEST_LINKS';
  END IF;
  IF (SELECT id FROM private.interpretation_current WHERE interpretation_key=v1.interpretation_key)<>v2.id THEN
    RAISE EXCEPTION 'NORMALISERING_TEST_CURRENT';
  END IF;
  -- Forslaget kan nu ikke normaliseres igen på version 1 (nyere version findes), og version 2 er uændret.
  BEGIN
    PERFORM set_config('request.jwt.claim.sub','a6c20000-0000-4000-8000-000000000001',true);
    SET LOCAL ROLE authenticated;
    PERFORM red_normaliser_forslag(v1.id,1,'dato-markoer-v1');
    RAISE EXCEPTION 'NORMALISERING_TEST_NO_ERROR: genkørsel på v1';
  EXCEPTION WHEN OTHERS THEN
    RESET ROLE;
    IF SQLERRM NOT LIKE 'NORMALISERING_IKKE_PROPOSED%' AND SQLERRM NOT LIKE 'NORMALISERING_VERSION_KONFLIKT%' THEN
      RAISE EXCEPTION 'NORMALISERING_TEST_GENKOERSEL: %',SQLERRM; END IF;
  END;
  IF (SELECT count(*) FROM private.interpretation WHERE interpretation_key=v1.interpretation_key)<>2 THEN
    RAISE EXCEPTION 'NORMALISERING_TEST_ANTAL_VERSIONER';
  END IF;
  -- v2 normaliseret igen: værdien er allerede ren.
  SET LOCAL ROLE authenticated;
  BEGIN
    PERFORM red_normaliser_forslag(v2.id,2,'dato-markoer-v1');
    RAISE EXCEPTION 'NORMALISERING_TEST_NO_ERROR: v2 uændret';
  EXCEPTION WHEN OTHERS THEN
    RESET ROLE;
    IF SQLERRM NOT LIKE 'NORMALISERING_UAENDRET%' THEN RAISE EXCEPTION 'NORMALISERING_TEST_V2_IGEN: %',SQLERRM; END IF;
  END;
END $t5$;

-- 6) Klassifikationen ser version 2's værdi: death '† 1750' (SKRIVEMAADE mod '1750'), birth gør ikke noget uden persona
--    (NO_IDENTITY). Normaliser death-forslaget og kontrollér, at klassifikationens værdi er den normaliserede.
SET LOCAL ROLE authenticated;
SELECT red_normaliser_forslag('a6c20000-0000-4000-8000-000000000302',1,'dato-markoer-v1');
RESET ROLE;
SET LOCAL default_transaction_read_only = on;
\i .claude/skills/daa-extract/scripts/interpretation_control_classification.sql
DO $t6$
DECLARE r jsonb := current_setting('daa.control_result')::jsonb; v2 uuid; v1 uuid:='a6c20000-0000-4000-8000-000000000302';
BEGIN
  SELECT id INTO v2 FROM private.interpretation WHERE interpretation_key='a6c20000-0000-4000-8000-000000000402' AND version=2;
  -- Gældende version er 2; gamle version 1 er ikke med i klassifikationen.
  IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'items') i WHERE i->>'interpretation_id'=v2::text AND (i->>'version')::int=2)
     OR EXISTS (SELECT 1 FROM jsonb_array_elements(r->'items') i WHERE i->>'interpretation_id'=v1::text) THEN
    RAISE EXCEPTION 'NORMALISERING_TEST_KLASSIFIKATION: %',r->'items';
  END IF;
  IF (SELECT ic.value #>> '{}' FROM private.interpretation_current ic WHERE ic.id=v2)<>'1750' THEN
    RAISE EXCEPTION 'NORMALISERING_TEST_KLASSIFIKATION_VAERDI';
  END IF;
END $t6$;
ROLLBACK;
SELECT 'interpretation_normalisering OK' AS result;
