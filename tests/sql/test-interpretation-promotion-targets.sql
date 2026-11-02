\set ON_ERROR_STOP on
BEGIN;
-- Trin 6c-2 Task 6: kanonisk sha af målfindingens output. En accept giver en ny version med et tilfældigt id, og items
-- sorteres på id; hvert element får derfor sin nøgles version 1-id (fixturens faste id), og items/singleton_items
-- sorteres på det. Resten af outputtet (tællinger, mål, typer) indgår byte for byte (jsonb's kanoniske tekst).
CREATE FUNCTION pg_temp.t6_kanon_sha(p text) RETURNS text LANGUAGE sql AS $f$
  WITH j AS (SELECT p::jsonb AS j),
  m AS (SELECT i.id, v1.id AS v1 FROM private.interpretation i
          JOIN private.interpretation v1 ON v1.interpretation_key=i.interpretation_key AND v1.version=1),
  arr AS (
    SELECT g.k, coalesce((
      SELECT jsonb_agg(jsonb_set(x,'{interpretation_id}',to_jsonb(coalesce(m.v1::text,x->>'interpretation_id')))
                       ORDER BY coalesce(m.v1::text,x->>'interpretation_id'))
        FROM jsonb_array_elements(j.j->g.k) x LEFT JOIN m ON m.id=(x->>'interpretation_id')::uuid),'[]'::jsonb) AS a
      FROM j, (VALUES ('items'),('singleton_items')) g(k))
  SELECT encode(sha256(convert_to((j.j || (SELECT jsonb_object_agg(k,a) FROM arr))::text,'UTF8')),'hex') FROM j
$f$;
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
-- Trin 6c-2 Task 6: efter hver kørsel er outputtet byte-ens med main's fil (sha beregnet med `git show main:<fil>` på
-- samme fixtur), både uden daa.control_src og med kildescope på fixturens eneste kilde (-4500).
DO $$ BEGIN
  IF pg_temp.t6_kanon_sha(current_setting('daa.targets_result')) <> '57b7d2af3504caef6c346f16f155b9932ff3b78e2d0de09bdbec45effc9d6d4d' THEN
    RAISE EXCEPTION 'FEJL: målfindingen (første kørsel) er ikke byte-ens med main: %',
      pg_temp.t6_kanon_sha(current_setting('daa.targets_result'));
  END IF;
END $$;
SELECT set_config('daa.control_src','-4500',true) \g /dev/null
\o /dev/null
\i .claude/skills/daa-extract/scripts/interpretation_promotion_targets.sql
\o
SELECT set_config('daa.control_src','',true) \g /dev/null
DO $$ BEGIN
  IF pg_temp.t6_kanon_sha(current_setting('daa.targets_result')) <> '57b7d2af3504caef6c346f16f155b9932ff3b78e2d0de09bdbec45effc9d6d4d' THEN
    RAISE EXCEPTION 'FEJL: målfindingen (første kørsel) med kildescope på fixturens eneste kilde er ikke byte-ens med main: %',
      pg_temp.t6_kanon_sha(current_setting('daa.targets_result'));
  END IF;
END $$;
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
DO $$ BEGIN
  IF pg_temp.t6_kanon_sha(current_setting('daa.targets_result')) <> '4fada55a2313ff7d2c6b184265836e4cbd117e155d7b90306c2178a562727373' THEN
    RAISE EXCEPTION 'FEJL: målfindingen (genkørsel) er ikke byte-ens med main: %',
      pg_temp.t6_kanon_sha(current_setting('daa.targets_result'));
  END IF;
END $$;
SELECT set_config('daa.control_src','-4500',true) \g /dev/null
\o /dev/null
\i .claude/skills/daa-extract/scripts/interpretation_promotion_targets.sql
\o
SELECT set_config('daa.control_src','',true) \g /dev/null
DO $$ BEGIN
  IF pg_temp.t6_kanon_sha(current_setting('daa.targets_result')) <> '4fada55a2313ff7d2c6b184265836e4cbd117e155d7b90306c2178a562727373' THEN
    RAISE EXCEPTION 'FEJL: målfindingen (genkørsel) med kildescope på fixturens eneste kilde er ikke byte-ens med main: %',
      pg_temp.t6_kanon_sha(current_setting('daa.targets_result'));
  END IF;
END $$;
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
DO $$ BEGIN
  IF pg_temp.t6_kanon_sha(current_setting('daa.targets_result')) <> '7f44e386d4b9ba5f310d011a963ca33f8d71d93fd7d37761215bbb02aa62febf' THEN
    RAISE EXCEPTION 'FEJL: målfindingen (andet mål) er ikke byte-ens med main: %',
      pg_temp.t6_kanon_sha(current_setting('daa.targets_result'));
  END IF;
END $$;
SELECT set_config('daa.control_src','-4500',true) \g /dev/null
\o /dev/null
\i .claude/skills/daa-extract/scripts/interpretation_promotion_targets.sql
\o
SELECT set_config('daa.control_src','',true) \g /dev/null
DO $$ BEGIN
  IF pg_temp.t6_kanon_sha(current_setting('daa.targets_result')) <> '7f44e386d4b9ba5f310d011a963ca33f8d71d93fd7d37761215bbb02aa62febf' THEN
    RAISE EXCEPTION 'FEJL: målfindingen (andet mål) med kildescope på fixturens eneste kilde er ikke byte-ens med main: %',
      pg_temp.t6_kanon_sha(current_setting('daa.targets_result'));
  END IF;
END $$;
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

-- ======================================================================================================================
-- Trin 6c-2 Task 6: kildescope (daa.control_src), ALREADY_BOUND_OTHER og TARGET_SHARED i målfindingen. Med kildescope
-- (v2) leverer målfindingen intet, som RPC'en afviser med ALREADY_BOUND_OTHER; uden kildescope (v1) beregnes
-- TARGET_SHARED ikke, og RPC'en afviser et batch med delte mål atomisk (valg A, 2026-11-02).
-- Syntetisk fixtur med kilde A = -4550 og B = -4559.
-- Personer: X -4551 død '1850' (-4561); Y -4552 '1851' (-4562); Z -4553 '1852' (-4563); W -4554 '1853' (-4564);
-- U -4555 '1854' (-4565); flytmål -4556 uden fakta; T -4558 '1855' (-4568).
-- Accepterede forslag (n → kilde, persona, værdi, forventet udfald med kildescope; uden kildescope er TARGET_SHARED MATCH):
--   01 A pa1→X '1850'  TARGET_SHARED (02 fra en anden kilde, samme påstand)
--   02 B pb1→X '1850'  TARGET_SHARED
--   03 A pa2→Y '1851'  MATCH
--   05 A pa3→Z '1852'  ALREADY_BOUND_OTHER (11 har en gyldig binding på -4563)
--   06 A pa4→W '1853'  MATCH (12's binding på -4564 er ugyldig, efter pb3 er flyttet)
--   07 A pa5→U '1854' og 08 A pa5→U ' 1854'  TARGET_SHARED (to nøgler, samme persona)
--   09 B pb4→T '1855'  MATCH
--   11 B pb2→Z '1852'  bundet → ALREADY_PROMOTED;  12 B pb3→W '1853'  bundet, pb3 flyttet → NO_MATCH
-- ======================================================================================================================
BEGIN;
INSERT INTO auth.users(id,email) VALUES ('a4550000-0000-4000-8000-000000000001','kildescope45@test.invalid');
INSERT INTO profiles(id,rolle,navn,email) VALUES
  ('a4550000-0000-4000-8000-000000000001','redaktion','Kildescope 45','kildescope45@test.invalid');
INSERT INTO person(id,levende,privat,status) SELECT -4550-n,false,false,'kildescope45' FROM generate_series(1,8) n;
INSERT INTO source(id,titel,import_key) VALUES (-4550,'Kildescope A','verify:kildescope45a'),
                                              (-4559,'Kildescope B','verify:kildescope45b');
INSERT INTO private.extraction_run(id,source_id,run_key,schema_version,extractor_version,profile_version,input_sha256,manifest)
  SELECT ('a4550000-0000-4000-8000-0000000000'||k||'1')::uuid,s,'kildescope45-run-'||k,'1.0','verify','verify',repeat('9',64),'{}'
    FROM (VALUES ('a',-4550),('b',-4559)) v(k,s);
INSERT INTO private.source_rendition(id,source_id,rendition_key,rendition_kind,content_sha256,metadata)
  SELECT ('a4550000-0000-4000-8000-0000000000'||k||'2')::uuid,s,'kildescope45-rendition-'||k,'text_layer',repeat('8',64),'{}'
    FROM (VALUES ('a',-4550),('b',-4559)) v(k,s);
INSERT INTO private.source_record_occurrence(id,rendition_id,occurrence_key,page_from,page_to,char_from,char_to,
  verbatim_text,physical_fingerprint,structural_fingerprint,extraction_run_id)
  SELECT ('a4550000-0000-4000-8000-0000000000'||k||'3')::uuid,('a4550000-0000-4000-8000-0000000000'||k||'2')::uuid,
         'kildescope45-occ-'||k,1,1,0,4,'1850','phys-kildescope45-'||k,'struct-kildescope45-'||k,
         ('a4550000-0000-4000-8000-0000000000'||k||'1')::uuid
    FROM (VALUES ('a'),('b')) v(k);
INSERT INTO private.source_observation(id,occurrence_id,observation_kind,page_from,page_to,char_from,char_to,
  verbatim_text,quality_status,extraction_method,extraction_run_id)
  SELECT ('a4550000-0000-4000-8000-0000000000'||k||'4')::uuid,('a4550000-0000-4000-8000-0000000000'||k||'3')::uuid,
         'name_clause',1,1,0,4,'1850','clear','verify',('a4550000-0000-4000-8000-0000000000'||k||'1')::uuid
    FROM (VALUES ('a'),('b')) v(k);
CREATE TEMP TABLE ks45_persona(p text, k text, s bigint, pid bigint) ON COMMIT DROP;
INSERT INTO ks45_persona VALUES ('a1','a',-4550,-4551),('a2','a',-4550,-4552),('a3','a',-4550,-4553),('a4','a',-4550,-4554),
                                ('a5','a',-4550,-4555),('b1','b',-4559,-4551),('b2','b',-4559,-4553),('b3','b',-4559,-4554),
                                ('b4','b',-4559,-4558);
INSERT INTO private.source_persona(id,source_id,persona_key,created_run_id)
  SELECT ('a4550000-0000-4000-8000-0000000001'||p)::uuid,s,'kildescope45-'||p,('a4550000-0000-4000-8000-0000000000'||k||'1')::uuid
    FROM ks45_persona;
INSERT INTO private.source_mention(id,observation_id,mention_kind,char_from,char_to,verbatim_text,created_run_id)
  SELECT ('a4550000-0000-4000-8000-0000000002'||p)::uuid,('a4550000-0000-4000-8000-0000000000'||k||'4')::uuid,'person',0,4,'1850',
         ('a4550000-0000-4000-8000-0000000000'||k||'1')::uuid FROM ks45_persona;
INSERT INTO private.source_persona_mention(persona_id,mention_id,mention_role,ordinal)
  SELECT ('a4550000-0000-4000-8000-0000000001'||p)::uuid,('a4550000-0000-4000-8000-0000000002'||p)::uuid,'principal',1
    FROM ks45_persona;
INSERT INTO fact(id,subjekt_type,subjekt_id,faktatype) VALUES
  (-4561,'person',-4551,'død'),(-4562,'person',-4552,'død'),(-4563,'person',-4553,'død'),(-4564,'person',-4554,'død'),
  (-4565,'person',-4555,'død'),(-4568,'person',-4558,'død');
INSERT INTO assertion(id,target_type,target_id,date_raw,calendar,uforanderlig) VALUES
  (-4561,'fact',-4561,'1850','gregoriansk',true),(-4562,'fact',-4562,'1851','gregoriansk',true),
  (-4563,'fact',-4563,'1852','gregoriansk',true),(-4564,'fact',-4564,'1853','gregoriansk',true),
  (-4565,'fact',-4565,'1854','gregoriansk',true),(-4568,'fact',-4568,'1855','gregoriansk',true);
INSERT INTO private.interpretation(id,interpretation_key,version,source_id,source_persona_id,interpretation_kind,
  predicate,value,schema_version,derivation_kind,confidence,status,method,extraction_run_id)
  SELECT ('a4550000-0000-4000-8000-0000000003'||n)::uuid,('a4550000-0000-4000-8000-0000000004'||n)::uuid,1,
         CASE WHEN p LIKE 'b%' THEN -4559 ELSE -4550 END,('a4550000-0000-4000-8000-0000000001'||p)::uuid,'property',
         'person.death',to_jsonb(v),'1.0','source_statement',1,'proposed','verify',
         ('a4550000-0000-4000-8000-0000000000'||left(p,1)||'1')::uuid
    FROM (VALUES ('01','a1','1850'),('02','b1','1850'),('03','a2','1851'),('05','a3','1852'),('06','a4','1853'),
                 ('07','a5','1854'),('08','a5',' 1854'),('09','b4','1855'),('11','b2','1852'),('12','b3','1853')) v(n,p,v);
INSERT INTO private.interpretation_observation(interpretation_id,observation_id,evidence_role,ordinal)
  SELECT i.id,('a4550000-0000-4000-8000-0000000000'||CASE WHEN i.source_id=-4559 THEN 'b' ELSE 'a' END||'4')::uuid,'supporting',1
    FROM private.interpretation i WHERE i.id::text LIKE 'a4550000-%';
SET CONSTRAINTS private.interpretation_has_observation IMMEDIATE;
SET CONSTRAINTS private.interpretation_has_observation DEFERRED;
SELECT set_config('request.jwt.claim.sub','a4550000-0000-4000-8000-000000000001',true);
SELECT private.decide_source_persona_identity(('a4550000-0000-4000-8000-0000000001'||p)::uuid,pid,0,'accepted',
         '{"basis":"web_detail","note":"kildescope45"}','human') FROM ks45_persona;
SET LOCAL ROLE authenticated;
-- 11 og 12 bindes først; derefter flyttes pb3, så 12's binding ikke længere er gyldig.
SELECT red_decide_interpretation(('a4550000-0000-4000-8000-0000000003'||n)::uuid,1,'accepted','{"basis":"kildescope45"}')
  FROM (VALUES ('11'),('12')) v(n);
RESET ROLE;
SELECT set_config('t6.items',(
  SELECT jsonb_agg(jsonb_build_object('interpretation_id',ic.id,'target_type','assertion','target_id',t) ORDER BY t)
    FROM (VALUES ('a4550000-0000-4000-8000-000000000411'::uuid,-4563),('a4550000-0000-4000-8000-000000000412'::uuid,-4564)) v(k,t)
    JOIN private.interpretation_current ic ON ic.interpretation_key=v.k)::text,true) \g /dev/null
SET LOCAL ROLE authenticated;
DO $$
DECLARE items jsonb := current_setting('t6.items')::jsonb;
        p jsonb;
BEGIN
  p := red_preview_interpretation_promotions(items);
  PERFORM red_promote_interpretations_batch(items,p->>'preview_hash');
END $$;
RESET ROLE;
SELECT private.decide_source_persona_identity('a4550000-0000-4000-8000-0000000001b3'::uuid,-4556,1,'accepted',
         '{"basis":"web_detail","note":"kildescope45 flyt"}','human');
SET LOCAL ROLE authenticated;
SELECT red_decide_interpretation(('a4550000-0000-4000-8000-0000000003'||n)::uuid,1,'accepted','{"basis":"kildescope45"}')
  FROM (VALUES ('01'),('02'),('03'),('05'),('06'),('07'),('08'),('09')) v(n);
RESET ROLE;
-- Hjælpetabel: nøglens to sidste cifre → aktuel version.
CREATE TEMP TABLE ks45_cur ON COMMIT DROP AS
  SELECT right(interpretation_key::text,2) AS n, id FROM private.interpretation_current WHERE interpretation_key::text LIKE 'a4550000-%';
-- Uden kildescope (v1-vejen): TARGET_SHARED beregnes ikke; 01+02 og 07+08 leveres som MATCH. ALREADY_BOUND_OTHER
-- leveres aldrig. RPC'en er værnet: et batch med to nøgler mod samme påstand afvises atomisk med ALREADY_BOUND_OTHER.
SET LOCAL default_transaction_read_only = on;
\o /dev/null
\i .claude/skills/daa-extract/scripts/interpretation_promotion_targets.sql
\o
DO $$
DECLARE r jsonb := current_setting('daa.targets_result')::jsonb;
        d jsonb := r->'counts'->'person.death';
BEGIN
  IF (SELECT jsonb_agg(jsonb_build_array(c.n, x->>'target_id') ORDER BY c.n)
        FROM jsonb_array_elements(r->'items') x JOIN ks45_cur c ON c.id=(x->>'interpretation_id')::uuid)
     IS DISTINCT FROM '[["01","-4561"],["02","-4561"],["03","-4562"],["06","-4564"],["07","-4565"],["08","-4565"],["09","-4568"]]'::jsonb THEN
    RAISE EXCEPTION 'FEJL: items uden kildescope %',r->'items';
  END IF;
  IF d ? 'TARGET_SHARED' OR (d->>'ALREADY_BOUND_OTHER')::int IS DISTINCT FROM 1
     OR (d->>'ALREADY_PROMOTED')::int IS DISTINCT FROM 1 OR (d->>'NO_MATCH')::int IS DISTINCT FROM 1
     OR (d->>'MATCH')::int IS DISTINCT FROM 7 THEN
    RAISE EXCEPTION 'FEJL: tællinger uden kildescope %',d;
  END IF;
END $$;
SET LOCAL default_transaction_read_only = off;
SELECT set_config('t6.cur',(SELECT jsonb_object_agg(n,id) FROM ks45_cur)::text,true) \g /dev/null
SET LOCAL ROLE authenticated;
DO $$
DECLARE cur jsonb := current_setting('t6.cur')::jsonb;
        p jsonb := red_preview_interpretation_promotions(current_setting('daa.targets_result')::jsonb->'items');
BEGIN
  -- Det uscopede batch afvises: præcis de fire delte elementer med ALREADY_BOUND_OTHER, så batchen skriver intet.
  IF (SELECT jsonb_agg(i->>'target_id' ORDER BY i->>'target_id', i->>'interpretation_id') FROM jsonb_array_elements(p->'items') i
       WHERE i->>'reason_code'='ALREADY_BOUND_OTHER') IS DISTINCT FROM '["-4561","-4561","-4565","-4565"]'::jsonb
     OR EXISTS (SELECT 1 FROM jsonb_array_elements(p->'items') i
                 WHERE i->>'target_id' NOT IN ('-4561','-4565') AND (i->>'eligible')::boolean IS NOT TRUE) THEN
    RAISE EXCEPTION 'FEJL: RPC-værnet mod delte mål uden kildescope %',p;
  END IF;
  p := red_preview_interpretation_promotions(jsonb_build_array(
         jsonb_build_object('interpretation_id',cur->'05','target_type','assertion','target_id',-4563)));
  IF p->'items'->0->>'reason_code' IS DISTINCT FROM 'ALREADY_BOUND_OTHER' THEN RAISE EXCEPTION 'FEJL: 05 %',p; END IF;
END $$;
RESET ROLE;
-- Kildescope A og B (v2-vejen): TARGET_SHARED på tværs af kilder; for hver kilde leverer målfindingen intet for de
-- delte påstande, og RPC'en godkender alt, den leverer.
SET LOCAL default_transaction_read_only = on;
SELECT set_config('daa.control_src','-4550',true) \g /dev/null
\o /dev/null
\i .claude/skills/daa-extract/scripts/interpretation_promotion_targets.sql
\o
DO $$
DECLARE r jsonb := current_setting('daa.targets_result')::jsonb;
        d jsonb := r->'counts'->'person.death';
BEGIN
  IF (SELECT jsonb_agg(c.n ORDER BY c.n) FROM jsonb_array_elements(r->'items') x JOIN ks45_cur c ON c.id=(x->>'interpretation_id')::uuid)
     IS DISTINCT FROM '["03","06"]'::jsonb
     OR (d->>'TARGET_SHARED')::int IS DISTINCT FROM 3 OR (d->>'ALREADY_BOUND_OTHER')::int IS DISTINCT FROM 1
     OR (d->>'ALREADY_PROMOTED')::int IS DISTINCT FROM 0 THEN
    RAISE EXCEPTION 'FEJL: kildescope A %',r;
  END IF;
END $$;
SET LOCAL default_transaction_read_only = off;
SET LOCAL ROLE authenticated;
DO $$
DECLARE items jsonb := current_setting('daa.targets_result')::jsonb->'items';
        p jsonb := red_preview_interpretation_promotions(items);
BEGIN
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(p->'items') i WHERE (i->>'eligible')::boolean IS NOT TRUE) THEN
    RAISE EXCEPTION 'FEJL: RPC afviser et leveret element (kildescope A) %',p;
  END IF;
  PERFORM red_promote_interpretations_batch(items,p->>'preview_hash');
END $$;
RESET ROLE;
SET LOCAL default_transaction_read_only = on;
SELECT set_config('daa.control_src','-4559',true) \g /dev/null
\o /dev/null
\i .claude/skills/daa-extract/scripts/interpretation_promotion_targets.sql
\o
DO $$
DECLARE r jsonb := current_setting('daa.targets_result')::jsonb;
        d jsonb := r->'counts'->'person.death';
BEGIN
  IF (SELECT jsonb_agg(c.n ORDER BY c.n) FROM jsonb_array_elements(r->'items') x JOIN ks45_cur c ON c.id=(x->>'interpretation_id')::uuid)
     IS DISTINCT FROM '["09"]'::jsonb
     OR (d->>'TARGET_SHARED')::int IS DISTINCT FROM 1 OR d ? 'ALREADY_BOUND_OTHER'
     OR (d->>'ALREADY_PROMOTED')::int IS DISTINCT FROM 1 OR (d->>'NO_MATCH')::int IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'FEJL: kildescope B %',r;
  END IF;
END $$;
SET LOCAL default_transaction_read_only = off;
SET LOCAL ROLE authenticated;
DO $$
DECLARE items jsonb := current_setting('daa.targets_result')::jsonb->'items';
        p jsonb := red_preview_interpretation_promotions(items);
BEGIN
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(p->'items') i WHERE (i->>'eligible')::boolean IS NOT TRUE) THEN
    RAISE EXCEPTION 'FEJL: RPC afviser et leveret element (kildescope B) %',p;
  END IF;
  PERFORM red_promote_interpretations_batch(items,p->>'preview_hash');
END $$;
RESET ROLE;
-- Genkørsel med hvert kildescope efter binding: ingen nye items; de delte påstande er stadig TARGET_SHARED.
SET LOCAL default_transaction_read_only = on;
SELECT set_config('daa.control_src','-4550',true) \g /dev/null
\o /dev/null
\i .claude/skills/daa-extract/scripts/interpretation_promotion_targets.sql
\o
DO $$
DECLARE r jsonb := current_setting('daa.targets_result')::jsonb;
BEGIN
  IF jsonb_array_length(r->'items') <> 0 OR (r->'counts'->'person.death'->>'ALREADY_PROMOTED')::int IS DISTINCT FROM 2
     OR (r->'counts'->'person.death'->>'TARGET_SHARED')::int IS DISTINCT FROM 3 THEN
    RAISE EXCEPTION 'FEJL: genkørsel A efter binding %',r;
  END IF;
END $$;
SELECT set_config('daa.control_src','-4559',true) \g /dev/null
\o /dev/null
\i .claude/skills/daa-extract/scripts/interpretation_promotion_targets.sql
\o
SELECT set_config('daa.control_src','',true) \g /dev/null
DO $$
DECLARE r jsonb := current_setting('daa.targets_result')::jsonb;
BEGIN
  IF jsonb_array_length(r->'items') <> 0 OR (r->'counts'->'person.death'->>'ALREADY_PROMOTED')::int IS DISTINCT FROM 2
     OR (r->'counts'->'person.death'->>'TARGET_SHARED')::int IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'FEJL: genkørsel B efter binding %',r;
  END IF;
  RAISE NOTICE 'OK: interpretation_promotion_targets — kildescope, ALREADY_BOUND_OTHER, TARGET_SHARED kun med kildescope, RPC-værnet uden';
END $$;
ROLLBACK;
