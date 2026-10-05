\set ON_ERROR_STOP on
-- Kontrolmodellens klassifikation over `proposed` (decisions 2026-09-27, plan 2026-09-27 Task 1).
-- Fixturen følger test-interpretation-promotion-targets.sql. Den afgørende assert er til sidst:
-- accepteres klassifikationens MATCH-sæt, finder målfindingen præcis de samme id'er.
BEGIN;
INSERT INTO auth.users(id,email) VALUES ('a4600000-0000-4000-8000-000000000001','kontrol46@test.invalid');
INSERT INTO profiles(id,rolle,navn,email) VALUES
  ('a4600000-0000-4000-8000-000000000001','redaktion','Kontrol 46','kontrol46@test.invalid');
INSERT INTO person(id,levende,privat,status)
  SELECT -4600-n,false,false,'kontrol46' FROM generate_series(1,7) n;
INSERT INTO source(id,titel,import_key) VALUES (-4600,'Kontrol 46','verify:kontrol46');
INSERT INTO private.extraction_run(id,source_id,run_key,schema_version,extractor_version,profile_version,input_sha256,manifest)
  VALUES ('a4600000-0000-4000-8000-0000000000e1',-4600,'kontrol46-run','1.0','verify','verify',repeat('9',64),'{}');
INSERT INTO private.source_rendition(id,source_id,rendition_key,rendition_kind,content_sha256,metadata)
  VALUES ('a4600000-0000-4000-8000-0000000000e2',-4600,'kontrol46-rendition','text_layer',repeat('8',64),'{}');
INSERT INTO private.source_record_occurrence(id,rendition_id,occurrence_key,page_from,page_to,char_from,char_to,
  verbatim_text,physical_fingerprint,structural_fingerprint,extraction_run_id)
  VALUES ('a4600000-0000-4000-8000-0000000000e3','a4600000-0000-4000-8000-0000000000e2','kontrol46-occ',1,1,0,4,
          '1850','phys-kontrol46','struct-kontrol46','a4600000-0000-4000-8000-0000000000e1');
INSERT INTO private.source_observation(id,occurrence_id,observation_kind,page_from,page_to,char_from,char_to,
  verbatim_text,quality_status,extraction_method,extraction_run_id)
  VALUES ('a4600000-0000-4000-8000-0000000000e4','a4600000-0000-4000-8000-0000000000e3','name_clause',1,1,0,4,
          '1850','clear','verify','a4600000-0000-4000-8000-0000000000e1');
-- Otte personaer; 1-7 får identitet til -4601..-4607, 8 får ingen.
INSERT INTO private.source_persona(id,source_id,persona_key,created_run_id)
  SELECT ('a4600000-0000-4000-8000-00000000010'||n)::uuid,-4600,'kontrol46-p'||n,'a4600000-0000-4000-8000-0000000000e1'
    FROM generate_series(1,8) n;
INSERT INTO private.source_mention(id,observation_id,mention_kind,char_from,char_to,verbatim_text,created_run_id)
  SELECT ('a4600000-0000-4000-8000-00000000020'||n)::uuid,'a4600000-0000-4000-8000-0000000000e4','person',0,4,'1850',
         'a4600000-0000-4000-8000-0000000000e1' FROM generate_series(1,8) n;
INSERT INTO private.source_persona_mention(persona_id,mention_id,mention_role,ordinal)
  SELECT ('a4600000-0000-4000-8000-00000000010'||n)::uuid,('a4600000-0000-4000-8000-00000000020'||n)::uuid,'principal',1
    FROM generate_series(1,8) n;
-- Kanonisk: -4601 død '1850' + navn; -4602 to død '1851' + titel; -4603 død '1900';
-- -4604 død '1800'; -4605 intet dødsfaktum; -4606 død uden værdi; -4607 død '1760'.
INSERT INTO fact(id,subjekt_type,subjekt_id,faktatype) VALUES
  (-4611,'person',-4601,'død'),(-4612,'person',-4601,'navn'),(-4621,'person',-4602,'død'),
  (-4622,'person',-4602,'død'),(-4623,'person',-4602,'titel'),(-4631,'person',-4603,'død'),
  (-4641,'person',-4604,'død'),(-4661,'person',-4606,'død'),(-4671,'person',-4607,'død');
INSERT INTO assertion(id,target_type,target_id,vaerdi_tekst,calendar,uforanderlig) VALUES
  (-4612,'fact',-4612,'Anna Reventlow','gregoriansk',true),(-4623,'fact',-4623,'Kammerherre','gregoriansk',true),
  (-4661,'fact',-4661,NULL,'gregoriansk',true);
INSERT INTO assertion(id,target_type,target_id,date_raw,calendar,uforanderlig) VALUES
  (-4611,'fact',-4611,'1850','gregoriansk',true),(-4621,'fact',-4621,' 1851 ','gregoriansk',true),
  (-4622,'fact',-4622,'1851','gregoriansk',true),(-4631,'fact',-4631,'1900','gregoriansk',true),
  (-4641,'fact',-4641,'1800','gregoriansk',true),(-4671,'fact',-4671,'1760','gregoriansk',true);
-- Titelreglen i en ny version uden bulk (som i målfindingstesten).
INSERT INTO private.interpretation_promotion_rule(
  rule_key,rule_version,predicate,interpretation_kind,target_type,expected_fact_type,
  value_kind,requires_persona_identity,requires_principal_placement,bulk_eligible,status)
  VALUES ('person-title-v1',2,'person.title','property','assertion','titel','text',true,false,false,'active');
-- Ti forslag (n → persona, prædikat, værdi, forventet klasse):
--  1 p1 death '1850'          MATCH           6 p8 death '1850'         NO_IDENTITY
--  2 p2 death '1851'          AMBIGUOUS       7 p1 office 'amtmand'     (ingen regel: ikke med)
--  3 p3 death '† 1900'        SKRIVEMAADE     8 p2 title 'kammerherre'  MATCH_SINGLETON
--  4 p4 death '1805'          REAL_DIFF       9 p1 name ' anna REVENTLOW' MATCH (tekstgren)
--  5 p5 death '1850'          NO_FACT        10 p7 death '* ca. 1760'   SKRIVEMAADE (samme tal)
-- samt p6 death '1850' mod et faktum uden værdi: NO_FACT (n=11).
INSERT INTO private.interpretation(id,interpretation_key,version,source_id,source_persona_id,interpretation_kind,
  predicate,value,schema_version,derivation_kind,confidence,status,method,extraction_run_id)
  SELECT ('a4600000-0000-4000-8000-0000000003'||lpad(n::text,2,'0'))::uuid,
         ('a4600000-0000-4000-8000-0000000004'||lpad(n::text,2,'0'))::uuid,1,-4600,
         ('a4600000-0000-4000-8000-00000000010'||CASE n WHEN 6 THEN 8 WHEN 7 THEN 1 WHEN 8 THEN 2 WHEN 9 THEN 1
                                                        WHEN 10 THEN 7 WHEN 11 THEN 6 ELSE n END)::uuid,'property',
         CASE n WHEN 7 THEN 'person.office' WHEN 8 THEN 'person.title' WHEN 9 THEN 'person.name' ELSE 'person.death' END,
         to_jsonb(CASE n WHEN 1 THEN '1850' WHEN 2 THEN '1851' WHEN 3 THEN '† 1900' WHEN 4 THEN '1805'
                         WHEN 5 THEN '1850' WHEN 6 THEN '1850' WHEN 7 THEN 'amtmand' WHEN 8 THEN 'kammerherre'
                         WHEN 9 THEN ' anna REVENTLOW' WHEN 10 THEN '* ca. 1760' ELSE '1850' END),
         '1.0','source_statement',1,'proposed','verify','a4600000-0000-4000-8000-0000000000e1'
    FROM generate_series(1,11) n;
INSERT INTO private.interpretation_observation(interpretation_id,observation_id,evidence_role,ordinal)
  SELECT ('a4600000-0000-4000-8000-0000000003'||lpad(n::text,2,'0'))::uuid,'a4600000-0000-4000-8000-0000000000e4','supporting',1
    FROM generate_series(1,11) n;
SET CONSTRAINTS private.interpretation_has_observation IMMEDIATE;
SET CONSTRAINTS private.interpretation_has_observation DEFERRED;
SELECT set_config('request.jwt.claim.sub','a4600000-0000-4000-8000-000000000001',true);
SELECT private.decide_source_persona_identity(('a4600000-0000-4000-8000-00000000010'||n)::uuid,-4600-n,0,'accepted',
         '{"basis":"web_detail","note":"kontrol46"}','human') FROM generate_series(1,7) n;
SET LOCAL ROLE authenticated;
RESET ROLE;
SET LOCAL default_transaction_read_only = on;
\i .claude/skills/daa-extract/scripts/interpretation_control_classification.sql
DO $$
DECLARE r jsonb := current_setting('daa.control_result')::jsonb;
        d jsonb := r->'counts'->'person.death';
        k text;
BEGIN
  FOREACH k IN ARRAY ARRAY['MATCH','AMBIGUOUS','REAL_DIFF','NO_IDENTITY'] LOOP
    IF (d->>k)::int IS DISTINCT FROM 1 THEN RAISE EXCEPTION 'FEJL: % %',k,d; END IF;
  END LOOP;
  IF (d->>'SKRIVEMAADE')::int IS DISTINCT FROM 2 THEN RAISE EXCEPTION 'FEJL: SKRIVEMAADE %',d; END IF;
  IF (d->>'NO_FACT')::int IS DISTINCT FROM 2 THEN RAISE EXCEPTION 'FEJL: NO_FACT %',d; END IF;
  IF (d->>'MATCH_SINGLETON')::int IS DISTINCT FROM 0 OR (d->>'NO_PLACEMENT')::int IS DISTINCT FROM 0
     OR (d->>'UNSUPPORTED_RULE')::int IS DISTINCT FROM 0 THEN RAISE EXCEPTION 'FEJL: 0-fyld %',d; END IF;
  IF r->'counts' ? 'person.office' THEN RAISE EXCEPTION 'FEJL: prædikat uden regel talt med'; END IF;
  IF (r->'counts'->'person.name'->>'MATCH')::int IS DISTINCT FROM 1 THEN RAISE EXCEPTION 'FEJL: tekstgren %',r; END IF;
  IF (r->'counts'->'person.title'->>'MATCH_SINGLETON')::int IS DISTINCT FROM 1 THEN RAISE EXCEPTION 'FEJL: ikke-bulk %',r; END IF;
  IF jsonb_array_length(r->'items') <> 10 THEN RAISE EXCEPTION 'FEJL: items %',jsonb_array_length(r->'items'); END IF;
  -- MATCH bærer målet og versionen; øvrige klasser bærer intet mål.
  IF (SELECT count(*) FROM jsonb_array_elements(r->'items') i
       WHERE i->>'class' IN ('MATCH','MATCH_SINGLETON') AND (i->>'assertion_id') IS NOT NULL
         AND (i->>'version')::int = 1) <> 3 THEN RAISE EXCEPTION 'FEJL: MATCH uden mål %',r->'items'; END IF;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(r->'items') i
              WHERE i->>'class' NOT IN ('MATCH','MATCH_SINGLETON') AND i ? 'assertion_id'
                AND i->>'assertion_id' IS NOT NULL) THEN RAISE EXCEPTION 'FEJL: mål uden MATCH %',r->'items'; END IF;
  IF (SELECT i->>'assertion_id' FROM jsonb_array_elements(r->'items') i
       WHERE i->>'interpretation_id'='a4600000-0000-4000-8000-000000000301') <> '-4611' THEN
    RAISE EXCEPTION 'FEJL: forkert mål %',r->'items';
  END IF;
END $$;
-- Konsistens med målfindingen: accepteres klassifikationens MATCH-sæt (og kun det), er
-- målfindingens MATCH-items præcis de samme (id og mål), og singleton-listen ligeså.
SET LOCAL default_transaction_read_only = off;
SET LOCAL ROLE authenticated;
SELECT red_decide_interpretation((i->>'interpretation_id')::uuid,(i->>'version')::int,'accepted','{"basis":"kontrol46"}')
  FROM jsonb_array_elements(current_setting('daa.control_result')::jsonb->'items') i
 WHERE i->>'class' IN ('MATCH','MATCH_SINGLETON');
RESET ROLE;
SET LOCAL default_transaction_read_only = on;
\i .claude/skills/daa-extract/scripts/interpretation_promotion_targets.sql
DO $$
DECLARE c jsonb := current_setting('daa.control_result')::jsonb;
        t jsonb := current_setting('daa.targets_result')::jsonb;
BEGIN
  -- En accept er en ny version med nyt id; målfindingen ser det nye, klassifikationen så det
  -- gamle. Sammenlign derfor via den accepterede versions `supersedes_id`.
  IF (SELECT jsonb_agg(jsonb_build_array(ni.supersedes_id::text, x->>'target_id') ORDER BY ni.supersedes_id::text)
        FROM jsonb_array_elements(t->'items') x
        JOIN private.interpretation ni ON ni.id = (x->>'interpretation_id')::uuid)
     IS DISTINCT FROM
     (SELECT jsonb_agg(jsonb_build_array(i->>'interpretation_id', i->>'assertion_id') ORDER BY i->>'interpretation_id')
        FROM jsonb_array_elements(c->'items') i WHERE i->>'class'='MATCH') THEN
    RAISE EXCEPTION 'FEJL: klassifikation og målfinding uenige om MATCH: % mod %',c->'items',t->'items';
  END IF;
  IF (SELECT jsonb_agg(jsonb_build_array(ni.supersedes_id::text, x->>'target_id'))
        FROM jsonb_array_elements(t->'singleton_items') x
        JOIN private.interpretation ni ON ni.id = (x->>'interpretation_id')::uuid)
     IS DISTINCT FROM
     (SELECT jsonb_agg(jsonb_build_array(i->>'interpretation_id', i->>'assertion_id'))
        FROM jsonb_array_elements(c->'items') i WHERE i->>'class'='MATCH_SINGLETON') THEN
    RAISE EXCEPTION 'FEJL: klassifikation og målfinding uenige om MATCH_SINGLETON';
  END IF;
END $$;
-- Efter accept er intet af de accepterede længere i klassifikationen (den ser kun på proposed).
\i .claude/skills/daa-extract/scripts/interpretation_control_classification.sql
DO $$
DECLARE r jsonb := current_setting('daa.control_result')::jsonb;
BEGIN
  IF jsonb_array_length(r->'items') <> 7
     OR EXISTS (SELECT 1 FROM jsonb_array_elements(r->'items') i WHERE i->>'class' IN ('MATCH','MATCH_SINGLETON')) THEN
    RAISE EXCEPTION 'FEJL: accepterede stadig klassificeret %',r->'items';
  END IF;
  RAISE NOTICE 'OK: interpretation_control_classification — alle klasser, tekst- og datogren, ikke-bulk, enig med målfindingen, kun proposed';
END $$;
ROLLBACK;
