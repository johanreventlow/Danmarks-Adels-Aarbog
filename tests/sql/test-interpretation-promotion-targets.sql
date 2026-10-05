\set ON_ERROR_STOP on
BEGIN;
INSERT INTO auth.users(id,email) VALUES ('a4500000-0000-4000-8000-000000000001','targets45@test.invalid');
INSERT INTO profiles(id,rolle,navn,email) VALUES
  ('a4500000-0000-4000-8000-000000000001','redaktion','Targets 45','targets45@test.invalid');
INSERT INTO person(id,levende,privat,status) VALUES
  (-4501,false,false,'targets45'),(-4502,false,false,'targets45'),(-4503,false,false,'targets45'),
  (-4504,false,false,'targets45');
INSERT INTO source(id,titel,import_key) VALUES (-4500,'Targets 45','verify:targets45');
INSERT INTO private.extraction_run(id,source_id,run_key,schema_version,extractor_version,profile_version,input_sha256,manifest)
  VALUES ('a4500000-0000-4000-8000-0000000000e1',-4500,'targets45-run','1.0','verify','verify',repeat('9',64),'{}');
INSERT INTO private.source_rendition(id,source_id,rendition_key,rendition_kind,content_sha256,metadata)
  VALUES ('a4500000-0000-4000-8000-0000000000e2',-4500,'targets45-rendition','text_layer',repeat('8',64),'{}');
INSERT INTO private.source_record_occurrence(id,rendition_id,occurrence_key,page_from,page_to,char_from,char_to,
  verbatim_text,physical_fingerprint,structural_fingerprint,extraction_run_id)
  VALUES ('a4500000-0000-4000-8000-0000000000e3','a4500000-0000-4000-8000-0000000000e2','targets45-occ',1,1,0,4,
          '1850','phys-targets45','struct-targets45','a4500000-0000-4000-8000-0000000000e1');
INSERT INTO private.source_observation(id,occurrence_id,observation_kind,page_from,page_to,char_from,char_to,
  verbatim_text,quality_status,extraction_method,extraction_run_id)
  VALUES ('a4500000-0000-4000-8000-0000000000e4','a4500000-0000-4000-8000-0000000000e3','name_clause',1,1,0,4,
          '1850','clear','verify','a4500000-0000-4000-8000-0000000000e1');
-- Fire personaer (1-3 får identitet til -4501..-4503; 4 får ingen), hver med sin mention.
INSERT INTO private.source_persona(id,source_id,persona_key,created_run_id)
  SELECT ('a4500000-0000-4000-8000-00000000010'||n)::uuid,-4500,'targets45-p'||n,'a4500000-0000-4000-8000-0000000000e1'
    FROM generate_series(1,4) n;
INSERT INTO private.source_mention(id,observation_id,mention_kind,char_from,char_to,verbatim_text,created_run_id)
  SELECT ('a4500000-0000-4000-8000-00000000020'||n)::uuid,'a4500000-0000-4000-8000-0000000000e4','person',0,4,'1850',
         'a4500000-0000-4000-8000-0000000000e1' FROM generate_series(1,4) n;
INSERT INTO private.source_persona_mention(persona_id,mention_id,mention_role,ordinal)
  SELECT ('a4500000-0000-4000-8000-00000000010'||n)::uuid,('a4500000-0000-4000-8000-00000000020'||n)::uuid,'principal',1
    FROM generate_series(1,4) n;
-- Kanonisk: -4501 én død '1850' (MATCH); -4502 to død '1851' (AMBIGUOUS) og én titel
-- (MATCH_SINGLETON under en ikke-bulk-regel); -4503 død '1900' (NO_MATCH mod '1901');
-- -4504 død '1850' — bruges først, når persona 1's identitet flyttes (promotion til andet mål).
INSERT INTO fact(id,subjekt_type,subjekt_id,faktatype) VALUES
  (-4511,'person',-4501,'død'),(-4512,'person',-4501,'navn'),(-4521,'person',-4502,'død'),(-4522,'person',-4502,'død'),
  (-4523,'person',-4502,'titel'),(-4531,'person',-4503,'død'),(-4541,'person',-4504,'død');
INSERT INTO assertion(id,target_type,target_id,vaerdi_tekst,calendar,uforanderlig) VALUES
  (-4512,'fact',-4512,'Anna Reventlow','gregoriansk',true),(-4523,'fact',-4523,'Kammerherre','gregoriansk',true);
INSERT INTO assertion(id,target_type,target_id,date_raw,calendar,uforanderlig) VALUES
  (-4511,'fact',-4511,'1850','gregoriansk',true),(-4521,'fact',-4521,' 1851 ','gregoriansk',true),
  (-4522,'fact',-4522,'1851','gregoriansk',true),(-4531,'fact',-4531,'1900','gregoriansk',true),
  (-4541,'fact',-4541,'1850','gregoriansk',true);
-- Titelreglen i en ny version uden bulk: RPC'en godkender den kun i et kald med ét item.
INSERT INTO private.interpretation_promotion_rule(
  rule_key,rule_version,predicate,interpretation_kind,target_type,expected_fact_type,
  value_kind,requires_persona_identity,requires_principal_placement,bulk_eligible,status)
  VALUES ('person-title-v1',2,'person.title','property','assertion','titel','text',true,false,false,'active');
-- Syv forslag: fire person.death (værdi pr. persona), én person.office og én person.name
-- (tekstgren) på persona 1, og én person.title på persona 2.
INSERT INTO private.interpretation(id,interpretation_key,version,source_id,source_persona_id,interpretation_kind,
  predicate,value,schema_version,derivation_kind,confidence,status,method,extraction_run_id)
  SELECT ('a4500000-0000-4000-8000-00000000030'||n)::uuid,('a4500000-0000-4000-8000-00000000040'||n)::uuid,1,-4500,
         ('a4500000-0000-4000-8000-00000000010'||CASE WHEN n=7 THEN 2 WHEN n>=5 THEN 1 ELSE n END)::uuid,'property',
         CASE n WHEN 5 THEN 'person.office' WHEN 6 THEN 'person.name' WHEN 7 THEN 'person.title' ELSE 'person.death' END,
         to_jsonb(CASE n WHEN 1 THEN '1850' WHEN 2 THEN '1851' WHEN 3 THEN '1901' WHEN 4 THEN '1852'
                         WHEN 5 THEN 'amtmand' WHEN 6 THEN ' anna REVENTLOW' ELSE 'kammerherre' END),
         '1.0','source_statement',1,'proposed','verify','a4500000-0000-4000-8000-0000000000e1'
    FROM generate_series(1,7) n;
INSERT INTO private.interpretation_observation(interpretation_id,observation_id,evidence_role,ordinal)
  SELECT ('a4500000-0000-4000-8000-00000000030'||n)::uuid,'a4500000-0000-4000-8000-0000000000e4','supporting',1
    FROM generate_series(1,7) n;
SET CONSTRAINTS private.interpretation_has_observation IMMEDIATE;
SET CONSTRAINTS private.interpretation_has_observation DEFERRED;
SELECT set_config('request.jwt.claim.sub','a4500000-0000-4000-8000-000000000001',true);
SELECT private.decide_source_persona_identity(('a4500000-0000-4000-8000-00000000010'||n)::uuid,-4500-n,0,'accepted',
         '{"basis":"web_detail","note":"targets45"}','human') FROM generate_series(1,3) n;
SET LOCAL ROLE authenticated;
SELECT red_decide_interpretation(('a4500000-0000-4000-8000-00000000030'||n)::uuid,1,'accepted','{"basis":"targets45"}')
  FROM generate_series(1,7) n;
RESET ROLE;
SET LOCAL default_transaction_read_only = on;
\i .claude/skills/daa-extract/scripts/interpretation_promotion_targets.sql
DO $$
DECLARE r jsonb := current_setting('daa.targets_result')::jsonb;
BEGIN
  IF (r->'counts'->'person.death'->>'MATCH')::int IS DISTINCT FROM 1 THEN RAISE EXCEPTION 'FEJL: MATCH %',r; END IF;
  IF (r->'counts'->'person.death'->>'AMBIGUOUS')::int IS DISTINCT FROM 1 THEN RAISE EXCEPTION 'FEJL: AMBIGUOUS %',r; END IF;
  IF (r->'counts'->'person.death'->>'NO_MATCH')::int IS DISTINCT FROM 1 THEN RAISE EXCEPTION 'FEJL: NO_MATCH %',r; END IF;
  IF (r->'counts'->'person.death'->>'NO_IDENTITY')::int IS DISTINCT FROM 1 THEN RAISE EXCEPTION 'FEJL: NO_IDENTITY %',r; END IF;
  IF r->'counts' ? 'person.office' THEN RAISE EXCEPTION 'FEJL: prædikat uden regel talt med'; END IF;
  IF (r->'counts'->'person.name'->>'MATCH')::int IS DISTINCT FROM 1 THEN RAISE EXCEPTION 'FEJL: tekstgren %',r; END IF;
  IF (r->'counts'->'person.name'->>'AMBIGUOUS')::int IS DISTINCT FROM 0 THEN RAISE EXCEPTION 'FEJL: 0-fyld %',r; END IF;
  IF jsonb_array_length(r->'items') <> 2 THEN RAISE EXCEPTION 'FEJL: items %',r->'items'; END IF;
  IF (r->'counts'->'person.title'->>'MATCH_SINGLETON')::int IS DISTINCT FROM 1
     OR jsonb_array_length(r->'singleton_items') <> 1 THEN RAISE EXCEPTION 'FEJL: ikke-bulk %',r; END IF;
END $$;
-- Forespørgsel og RPC skal være enige om hvert MATCH.
SET LOCAL default_transaction_read_only = off;
SET LOCAL ROLE authenticated;
DO $$
DECLARE p jsonb := red_preview_interpretation_promotions(current_setting('daa.targets_result')::jsonb->'items');
BEGIN
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(p->'items') i WHERE (i->>'eligible')::boolean IS NOT TRUE) THEN
    RAISE EXCEPTION 'FEJL: RPC afviser et MATCH: %',p;
  END IF;
  PERFORM red_promote_interpretations_batch(current_setting('daa.targets_result')::jsonb->'items',
                                            p->>'preview_hash');
  -- Ikke-bulk: RPC'en godkender målet i et kald med netop ét item.
  p := red_preview_interpretation_promotions(current_setting('daa.targets_result')::jsonb->'singleton_items');
  IF (p->'items'->0->>'eligible')::boolean IS NOT TRUE THEN
    RAISE EXCEPTION 'FEJL: RPC afviser et MATCH_SINGLETON: %',p;
  END IF;
  PERFORM red_promote_interpretations_batch(current_setting('daa.targets_result')::jsonb->'singleton_items',
                                            p->>'preview_hash');
END $$;
-- Genkørsel efter binding: de bundne er ALREADY_PROMOTED, ikke MATCH.
RESET ROLE;
SET LOCAL default_transaction_read_only = on;
\i .claude/skills/daa-extract/scripts/interpretation_promotion_targets.sql
DO $$
DECLARE r jsonb := current_setting('daa.targets_result')::jsonb;
BEGIN
  IF jsonb_array_length(r->'items') <> 0
     OR (r->'counts'->'person.death'->>'ALREADY_PROMOTED')::int IS DISTINCT FROM 1
     OR (r->'counts'->'person.name'->>'ALREADY_PROMOTED')::int IS DISTINCT FROM 1
     OR (r->'counts'->'person.title'->>'ALREADY_PROMOTED')::int IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'FEJL: genkørsel %',r;
  END IF;
END $$;
-- Promotion til ET ANDET mål: persona 1 flyttes til -4504, hvis død '1850' er -4541.
-- RPC'en afviser kun den eksakte (fortolkning, mål)-triple, så -4541 er et gyldigt MATCH.
SET LOCAL default_transaction_read_only = off;
SELECT private.decide_source_persona_identity('a4500000-0000-4000-8000-000000000101'::uuid,-4504,1,'accepted',
         '{"basis":"web_detail","note":"targets45 flyt"}','human');
SET LOCAL ROLE authenticated;
RESET ROLE;
SET LOCAL default_transaction_read_only = on;
\i .claude/skills/daa-extract/scripts/interpretation_promotion_targets.sql
SET LOCAL default_transaction_read_only = off;
SET LOCAL ROLE authenticated;
DO $$
DECLARE r jsonb := current_setting('daa.targets_result')::jsonb;
        p jsonb;
BEGIN
  IF (r->'counts'->'person.death'->>'MATCH')::int IS DISTINCT FROM 1
     OR jsonb_array_length(r->'items') <> 1
     OR (r->'items'->0->>'target_id')::bigint <> -4541 THEN
    RAISE EXCEPTION 'FEJL: promotion til andet mål skjult %',r;
  END IF;
  p := red_preview_interpretation_promotions(r->'items');
  IF (p->'items'->0->>'eligible')::boolean IS NOT TRUE THEN
    RAISE EXCEPTION 'FEJL: RPC afviser målet efter flytning: %',p;
  END IF;
  RAISE NOTICE 'OK: interpretation_promotion_targets — alle udfald, tekst- og datogren, ikke-bulk, enig med RPC begge veje, genkørsel, andet mål';
END $$;
ROLLBACK;
