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
-- Trin 6c-2 Task 6: uden daa.control_src er outputtet byte-ens med main's fil på denne fixtur (sha'en er beregnet med
-- `git show main:<fil>` på samme fixtur); med kildescope på fixturens eneste kilde er det også byte-ens.
DO $$ BEGIN
  IF encode(sha256(convert_to(current_setting('daa.control_result'),'UTF8')),'hex')
     <> 'daf29e2cbf644878bd8df679437c769bbd07323f3f4512a5582151f985ac21b7' THEN
    RAISE EXCEPTION 'FEJL: klassifikationen uden kildescope er ikke byte-ens med main: %',
      encode(sha256(convert_to(current_setting('daa.control_result'),'UTF8')),'hex');
  END IF;
END $$;
SELECT set_config('daa.control_src','-4600',true) \g /dev/null
\o /dev/null
\i .claude/skills/daa-extract/scripts/interpretation_control_classification.sql
\o
SELECT set_config('daa.control_src','',true) \g /dev/null
DO $$ BEGIN
  IF encode(sha256(convert_to(current_setting('daa.control_result'),'UTF8')),'hex')
     <> 'daf29e2cbf644878bd8df679437c769bbd07323f3f4512a5582151f985ac21b7' THEN
    RAISE EXCEPTION 'FEJL: klassifikationen med kildescope på fixturens eneste kilde er ikke byte-ens med main: %',
      encode(sha256(convert_to(current_setting('daa.control_result'),'UTF8')),'hex');
  END IF;
END $$;
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

-- ======================================================================================================================
-- Trin 6c-2 Task 6: kildescope (daa.control_src), ALREADY_BOUND_OTHER, TARGET_SHARED og rækkeeksportens nye felter.
-- Syntetisk fixtur med to kilder: A = -4650 og B = -4659. Personer:
--   X -4651 død '1850' (-4661), navn 'Anna Testlow' (-4667); Y -4652 død '1851' (-4662);
--   Z -4653 død '1852' (-4663), bundet gyldigt af B's nøgle 11;
--   W -4654 død '1853' (-4664), bundet af B's nøgle 12, hvis persona derefter flyttes til -4656 (bindingen bliver ugyldig);
--   V -4655 navn 'Anna Testlow til Testholm' (-4665) og 'Bent Testlow' (-4668); -4656 flytmål uden fakta.
-- Forslag (n → kilde, persona, prædikat, værdi, forventet klasse):
--   01 A pa1 death '1850'   TARGET_SHARED (02 matcher samme påstand fra en anden kilde)
--   02 B pb1 death '1850'   TARGET_SHARED
--   03 A pa2 death '1851'   TARGET_SHARED (04: anden nøgle, samme persona)
--   04 A pa2 death ' 1851 ' TARGET_SHARED
--   05 A pa3 death '1852'   ALREADY_BOUND_OTHER (11 har en gyldig binding på -4663)
--   06 A pa4 death '1853'   MATCH (12's binding på -4664 er ikke længere gyldig)
--   07 A pa5 name 'Anna Testlow'   REAL_DIFF, navn_forkortes = true (forkorter det ene af V's navne, ikke det andet)
--   08 A pa1 name 'Anne Testlow'   REAL_DIFF, navn_forkortes = false
--   09 A pa6 name 'Carl Testlow'   NO_IDENTITY, navn_forkortes = NULL (ingen identitet)
--   10 A pa2 name 'Dorte Testlow'  NO_FACT, navn_forkortes = NULL (Y har ingen navnepåstand)
--   11 B pb2 death '1852', 12 B pb3 death '1853': accepteres og bindes før klassifikationen (ikke proposed).
-- ======================================================================================================================
BEGIN;
INSERT INTO auth.users(id,email) VALUES ('a4650000-0000-4000-8000-000000000001','kildescope46@test.invalid');
INSERT INTO profiles(id,rolle,navn,email) VALUES
  ('a4650000-0000-4000-8000-000000000001','redaktion','Kildescope 46','kildescope46@test.invalid');
INSERT INTO person(id,levende,privat,status) SELECT -4650-n,false,false,'kildescope46' FROM generate_series(1,6) n;
INSERT INTO source(id,titel,import_key) VALUES (-4650,'Kildescope A','verify:kildescope46a'),
                                              (-4659,'Kildescope B','verify:kildescope46b');
-- Pr. kilde (k = a|b): kørsel k1, rendition k2, forekomst k3, observation k4, post k5 med accepteret anker.
INSERT INTO private.extraction_run(id,source_id,run_key,schema_version,extractor_version,profile_version,input_sha256,manifest)
  SELECT ('a4650000-0000-4000-8000-0000000000'||k||'1')::uuid,s,'kildescope46-run-'||k,'1.0','verify','verify',repeat('9',64),'{}'
    FROM (VALUES ('a',-4650),('b',-4659)) v(k,s);
INSERT INTO private.source_rendition(id,source_id,rendition_key,rendition_kind,content_sha256,metadata)
  SELECT ('a4650000-0000-4000-8000-0000000000'||k||'2')::uuid,s,'kildescope46-rendition-'||k,'text_layer',repeat('8',64),'{}'
    FROM (VALUES ('a',-4650),('b',-4659)) v(k,s);
INSERT INTO private.source_record_occurrence(id,rendition_id,occurrence_key,page_from,page_to,char_from,char_to,
  verbatim_text,physical_fingerprint,structural_fingerprint,extraction_run_id)
  SELECT ('a4650000-0000-4000-8000-0000000000'||k||'3')::uuid,('a4650000-0000-4000-8000-0000000000'||k||'2')::uuid,
         'kildescope46-occ-'||k,1,1,0,4,'1850','phys-kildescope46-'||k,'struct-kildescope46-'||k,
         ('a4650000-0000-4000-8000-0000000000'||k||'1')::uuid
    FROM (VALUES ('a'),('b')) v(k);
INSERT INTO private.source_observation(id,occurrence_id,observation_kind,page_from,page_to,char_from,char_to,
  verbatim_text,quality_status,extraction_method,extraction_run_id)
  SELECT ('a4650000-0000-4000-8000-0000000000'||k||'4')::uuid,('a4650000-0000-4000-8000-0000000000'||k||'3')::uuid,
         'name_clause',1,1,0,4,'1850','clear','verify',('a4650000-0000-4000-8000-0000000000'||k||'1')::uuid
    FROM (VALUES ('a'),('b')) v(k);
INSERT INTO private.source_record(id,source_id,record_key,record_kind,created_run_id)
  SELECT ('a4650000-0000-4000-8000-0000000000'||k||'5')::uuid,s,'KS-'||k,'person_entry',
         ('a4650000-0000-4000-8000-0000000000'||k||'1')::uuid
    FROM (VALUES ('a',-4650),('b',-4659)) v(k,s);
INSERT INTO private.source_record_anchor_event(occurrence_id,source_record_id,decision_status,evidence,version,decided_by,decided_by_name)
  SELECT ('a4650000-0000-4000-8000-0000000000'||k||'3')::uuid,('a4650000-0000-4000-8000-0000000000'||k||'5')::uuid,
         'accepted','{"basis":"kildescope46"}',1,'a4650000-0000-4000-8000-000000000001','fixture'
    FROM (VALUES ('a'),('b')) v(k);
-- Personaer: A pa1..pa6 (…01a1..01a6; pa6 uden identitet), B pb1..pb3 (…01b1..01b3), hver med sin mention.
CREATE TEMP TABLE ks_persona(p text, k text, s bigint) ON COMMIT DROP;
INSERT INTO ks_persona VALUES ('a1','a',-4650),('a2','a',-4650),('a3','a',-4650),('a4','a',-4650),('a5','a',-4650),
                              ('a6','a',-4650),('b1','b',-4659),('b2','b',-4659),('b3','b',-4659);
INSERT INTO private.source_persona(id,source_id,persona_key,created_run_id)
  SELECT ('a4650000-0000-4000-8000-0000000001'||p)::uuid,s,'kildescope46-'||p,('a4650000-0000-4000-8000-0000000000'||k||'1')::uuid
    FROM ks_persona;
INSERT INTO private.source_mention(id,observation_id,mention_kind,char_from,char_to,verbatim_text,created_run_id)
  SELECT ('a4650000-0000-4000-8000-0000000002'||p)::uuid,('a4650000-0000-4000-8000-0000000000'||k||'4')::uuid,'person',0,4,'1850',
         ('a4650000-0000-4000-8000-0000000000'||k||'1')::uuid FROM ks_persona;
INSERT INTO private.source_persona_mention(persona_id,mention_id,mention_role,ordinal)
  SELECT ('a4650000-0000-4000-8000-0000000001'||p)::uuid,('a4650000-0000-4000-8000-0000000002'||p)::uuid,'principal',1
    FROM ks_persona;
INSERT INTO fact(id,subjekt_type,subjekt_id,faktatype) VALUES
  (-4661,'person',-4651,'død'),(-4667,'person',-4651,'navn'),(-4662,'person',-4652,'død'),(-4663,'person',-4653,'død'),
  (-4664,'person',-4654,'død'),(-4665,'person',-4655,'navn'),(-4668,'person',-4655,'navn');
INSERT INTO assertion(id,target_type,target_id,vaerdi_tekst,calendar,uforanderlig) VALUES
  (-4667,'fact',-4667,'Anna Testlow','gregoriansk',true),(-4665,'fact',-4665,'Anna Testlow til Testholm','gregoriansk',true),
  (-4668,'fact',-4668,'Bent Testlow','gregoriansk',true);
INSERT INTO assertion(id,target_type,target_id,date_raw,calendar,uforanderlig) VALUES
  (-4661,'fact',-4661,'1850','gregoriansk',true),(-4662,'fact',-4662,'1851','gregoriansk',true),
  (-4663,'fact',-4663,'1852','gregoriansk',true),(-4664,'fact',-4664,'1853','gregoriansk',true);
-- Identiteter for pa1..pa5 og pb1 med generatorens udfald i evidensen (som retning 2 skriver dem).
INSERT INTO private.source_persona_identity_event(source_persona_id,canonical_person_id,decision_status,version,evidence,
                                                  decided_by,decided_by_name,decided_at)
  SELECT ('a4650000-0000-4000-8000-0000000001'||p)::uuid,pid,'accepted',1,jsonb_build_object('basis','fixture','outcome',o),
         'a4650000-0000-4000-8000-000000000001','fixture',now()
    FROM (VALUES ('a1',-4651,'svag'),('a2',-4652,'ingen_kandidat'),('a3',-4653,'enig'),('a4',-4654,'enig'),
                 ('a5',-4655,'enig'),('b1',-4651,'enig')) v(p,pid,o);
INSERT INTO private.source_persona_identity(source_persona_id,canonical_person_id,decision_status,version,evidence,
                                            decided_by,decided_by_name,decided_at)
  SELECT source_persona_id,canonical_person_id,decision_status,version,evidence,decided_by,decided_by_name,decided_at
    FROM private.source_persona_identity_event
   WHERE source_persona_id::text LIKE 'a4650000-%';
INSERT INTO private.interpretation(id,interpretation_key,version,source_id,source_persona_id,interpretation_kind,
  predicate,value,schema_version,derivation_kind,confidence,status,method,extraction_run_id)
  SELECT ('a4650000-0000-4000-8000-0000000003'||n)::uuid,('a4650000-0000-4000-8000-0000000004'||n)::uuid,1,
         CASE WHEN p LIKE 'b%' THEN -4659 ELSE -4650 END,('a4650000-0000-4000-8000-0000000001'||p)::uuid,'property',
         pred,to_jsonb(v),'1.0','source_statement',1,'proposed','verify',
         ('a4650000-0000-4000-8000-0000000000'||left(p,1)||'1')::uuid
    FROM (VALUES ('01','a1','person.death','1850'),('02','b1','person.death','1850'),('03','a2','person.death','1851'),
                 ('04','a2','person.death',' 1851 '),('05','a3','person.death','1852'),('06','a4','person.death','1853'),
                 ('07','a5','person.name','Anna Testlow'),('08','a1','person.name','Anne Testlow'),
                 ('09','a6','person.name','Carl Testlow'),('10','a2','person.name','Dorte Testlow'),
                 ('11','b2','person.death','1852'),('12','b3','person.death','1853')) v(n,p,pred,v);
INSERT INTO private.interpretation_observation(interpretation_id,observation_id,evidence_role,ordinal)
  SELECT i.id,('a4650000-0000-4000-8000-0000000000'||CASE WHEN i.source_id=-4659 THEN 'b' ELSE 'a' END||'4')::uuid,'supporting',1
    FROM private.interpretation i WHERE i.id::text LIKE 'a4650000-%';
SET CONSTRAINTS private.interpretation_has_observation IMMEDIATE;
SET CONSTRAINTS private.interpretation_has_observation DEFERRED;
-- B's nøgler 11 og 12 bindes: pb2 → Z, pb3 → W; derefter flyttes pb3 til -4656, så 12's binding ikke længere er gyldig.
SELECT set_config('request.jwt.claim.sub','a4650000-0000-4000-8000-000000000001',true);
SELECT private.decide_source_persona_identity(('a4650000-0000-4000-8000-0000000001'||p)::uuid,pid,0,'accepted',
         '{"basis":"web_detail","note":"kildescope46"}','human')
  FROM (VALUES ('b2',-4653),('b3',-4654)) v(p,pid);
SET LOCAL ROLE authenticated;
SELECT red_decide_interpretation(('a4650000-0000-4000-8000-0000000003'||n)::uuid,1,'accepted','{"basis":"kildescope46"}')
  FROM (VALUES ('11'),('12')) v(n);
RESET ROLE;
SELECT set_config('t6.items',(
  SELECT jsonb_agg(jsonb_build_object('interpretation_id',ic.id,'target_type','assertion','target_id',t) ORDER BY t)
    FROM (VALUES ('a4650000-0000-4000-8000-000000000411'::uuid,-4663),('a4650000-0000-4000-8000-000000000412'::uuid,-4664)) v(k,t)
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
SELECT private.decide_source_persona_identity('a4650000-0000-4000-8000-0000000001b3'::uuid,-4656,1,'accepted',
         '{"basis":"web_detail","note":"kildescope46 flyt"}','human');
SET LOCAL default_transaction_read_only = on;
-- Uden kildescope: begge kilder, og de nye udfald.
\o /dev/null
\i .claude/skills/daa-extract/scripts/interpretation_control_classification.sql
\o
DO $$
DECLARE r jsonb := current_setting('daa.control_result')::jsonb;
        want jsonb := '{"a4650000-0000-4000-8000-000000000301":"TARGET_SHARED","a4650000-0000-4000-8000-000000000302":"TARGET_SHARED",
                        "a4650000-0000-4000-8000-000000000303":"TARGET_SHARED","a4650000-0000-4000-8000-000000000304":"TARGET_SHARED",
                        "a4650000-0000-4000-8000-000000000305":"ALREADY_BOUND_OTHER","a4650000-0000-4000-8000-000000000306":"MATCH",
                        "a4650000-0000-4000-8000-000000000307":"REAL_DIFF","a4650000-0000-4000-8000-000000000308":"REAL_DIFF",
                        "a4650000-0000-4000-8000-000000000309":"NO_IDENTITY","a4650000-0000-4000-8000-000000000310":"NO_FACT"}';
        got jsonb := (SELECT jsonb_object_agg(i->>'interpretation_id',i->>'class') FROM jsonb_array_elements(r->'items') i);
BEGIN
  IF got IS DISTINCT FROM want THEN RAISE EXCEPTION 'FEJL: klasser uden kildescope %',got; END IF;
  IF (r->'counts'->'person.death'->>'TARGET_SHARED')::int IS DISTINCT FROM 4
     OR (r->'counts'->'person.death'->>'ALREADY_BOUND_OTHER')::int IS DISTINCT FROM 1
     OR (r->'counts'->'person.death'->>'MATCH')::int IS DISTINCT FROM 1
     OR (r->'counts'->'person.name'->>'TARGET_SHARED')::int IS DISTINCT FROM 0 THEN
    RAISE EXCEPTION 'FEJL: tællinger uden kildescope %',r->'counts';
  END IF;
  -- De nye klasser bærer intet mål; MATCH bærer sit (rivalens ugyldige binding spærrer ikke).
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(r->'items') i
              WHERE i->>'class' IN ('TARGET_SHARED','ALREADY_BOUND_OTHER') AND i->>'assertion_id' IS NOT NULL)
     OR (SELECT i->>'assertion_id' FROM jsonb_array_elements(r->'items') i
          WHERE i->>'interpretation_id'='a4650000-0000-4000-8000-000000000306') IS DISTINCT FROM '-4664' THEN
    RAISE EXCEPTION 'FEJL: mål på nye klasser %',r->'items';
  END IF;
END $$;
-- Kildescope A: kun A's forslag; TARGET_SHARED gælder fortsat på tværs af kilder.
SELECT set_config('daa.control_src','-4650',true) \g /dev/null
\o /dev/null
\i .claude/skills/daa-extract/scripts/interpretation_control_classification.sql
\o
DO $$
DECLARE r jsonb := current_setting('daa.control_result')::jsonb;
BEGIN
  IF (SELECT array_agg(i->>'interpretation_id' ORDER BY i->>'interpretation_id') FROM jsonb_array_elements(r->'items') i)
     IS DISTINCT FROM ARRAY['a4650000-0000-4000-8000-000000000301','a4650000-0000-4000-8000-000000000303',
                            'a4650000-0000-4000-8000-000000000304','a4650000-0000-4000-8000-000000000305',
                            'a4650000-0000-4000-8000-000000000306','a4650000-0000-4000-8000-000000000307',
                            'a4650000-0000-4000-8000-000000000308','a4650000-0000-4000-8000-000000000309',
                            'a4650000-0000-4000-8000-000000000310'] THEN
    RAISE EXCEPTION 'FEJL: kildescope A %',r->'items';
  END IF;
  IF (r->'counts'->'person.death'->>'TARGET_SHARED')::int IS DISTINCT FROM 3
     OR (r->'counts'->'person.death'->>'ALREADY_BOUND_OTHER')::int IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'FEJL: tællinger med kildescope A %',r->'counts';
  END IF;
  IF (SELECT i->>'class' FROM jsonb_array_elements(r->'items') i
       WHERE i->>'interpretation_id'='a4650000-0000-4000-8000-000000000301') IS DISTINCT FROM 'TARGET_SHARED' THEN
    RAISE EXCEPTION 'FEJL: 01 ikke TARGET_SHARED med kildescope A %',r->'items';
  END IF;
END $$;
-- Kildescope B: kun B's forslag (02); prædikater uden forslag i kilden tælles ikke, og et nyt udfald uden forekomst
-- i scopet optræder ikke som nøgle (de nye udfald 0-fyldes kun, når de forekommer).
SELECT set_config('daa.control_src','-4659',true) \g /dev/null
\o /dev/null
\i .claude/skills/daa-extract/scripts/interpretation_control_classification.sql
\o
DO $$
DECLARE r jsonb := current_setting('daa.control_result')::jsonb;
BEGIN
  IF jsonb_array_length(r->'items') <> 1
     OR r->'items'->0->>'interpretation_id' <> 'a4650000-0000-4000-8000-000000000302'
     OR r->'items'->0->>'class' <> 'TARGET_SHARED' THEN
    RAISE EXCEPTION 'FEJL: kildescope B %',r->'items';
  END IF;
  IF r->'counts' ? 'person.name' OR r->'counts'->'person.death' ? 'ALREADY_BOUND_OTHER'
     OR (r->'counts'->'person.death'->>'TARGET_SHARED')::int IS DISTINCT FROM 1
     OR (r->'counts'->'person.death'->>'MATCH')::int IS DISTINCT FROM 0 THEN
    RAISE EXCEPTION 'FEJL: tællinger med kildescope B %',r->'counts';
  END IF;
END $$;
-- Rækkeeksporten med kildescope A: kun A's rækker og de fire nye felter.
SELECT set_config('daa.control_src','-4650',true) \g /dev/null
\i tests/sql/lib-read-control-rows.sql
DO $$
DECLARE r jsonb := current_setting('t6.rows')::jsonb;
        x jsonb;
BEGIN
  IF jsonb_array_length(r) <> 9 OR EXISTS (SELECT 1 FROM jsonb_array_elements(r) e WHERE e->>'record_key' <> 'KS-a') THEN
    RAISE EXCEPTION 'FEJL: rækker med kildescope A: %',jsonb_array_length(r);
  END IF;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(r) e
              WHERE NOT e ?& ARRAY['identity_outcome','persona_id','identity_version','navn_forkortes']) THEN
    RAISE EXCEPTION 'FEJL: nye felter mangler';
  END IF;
  SELECT e INTO x FROM jsonb_array_elements(r) e WHERE e->>'interpretation_id'='a4650000-0000-4000-8000-000000000301';
  IF x->>'identity_outcome' IS DISTINCT FROM 'svag' OR x->>'persona_id' IS DISTINCT FROM 'a4650000-0000-4000-8000-0000000001a1'
     OR (x->>'identity_version')::int IS DISTINCT FROM 1 OR x->'navn_forkortes' IS DISTINCT FROM 'false'::jsonb THEN
    RAISE EXCEPTION 'FEJL: række 01 %',x - 'cited';
  END IF;
  SELECT e INTO x FROM jsonb_array_elements(r) e WHERE e->>'interpretation_id'='a4650000-0000-4000-8000-000000000303';
  IF x->>'identity_outcome' IS DISTINCT FROM 'ingen_kandidat' THEN RAISE EXCEPTION 'FEJL: række 03 %',x - 'cited'; END IF;
  -- navn_forkortes: forslaget er en ægte delstreng af et af databasens navne (titel/gods ville forsvinde). Det gælder,
  -- selv om personens andet navn ikke forkortes (07: sand over V's to navne).
  SELECT e INTO x FROM jsonb_array_elements(r) e WHERE e->>'interpretation_id'='a4650000-0000-4000-8000-000000000307';
  IF x->'navn_forkortes' IS DISTINCT FROM 'true'::jsonb THEN RAISE EXCEPTION 'FEJL: række 07 %',x - 'cited'; END IF;
  SELECT e INTO x FROM jsonb_array_elements(r) e WHERE e->>'interpretation_id'='a4650000-0000-4000-8000-000000000308';
  IF x->'navn_forkortes' IS DISTINCT FROM 'false'::jsonb THEN RAISE EXCEPTION 'FEJL: række 08 %',x - 'cited'; END IF;
  -- NULL-vejen: ingen identitet (09; også uden udfald og version) og ingen navnepåstand (10).
  SELECT e INTO x FROM jsonb_array_elements(r) e WHERE e->>'interpretation_id'='a4650000-0000-4000-8000-000000000309';
  IF x->'navn_forkortes' IS DISTINCT FROM 'null'::jsonb OR x->'identity_outcome' IS DISTINCT FROM 'null'::jsonb
     OR x->'identity_version' IS DISTINCT FROM 'null'::jsonb
     OR x->>'persona_id' IS DISTINCT FROM 'a4650000-0000-4000-8000-0000000001a6' THEN
    RAISE EXCEPTION 'FEJL: række 09 %',x - 'cited';
  END IF;
  SELECT e INTO x FROM jsonb_array_elements(r) e WHERE e->>'interpretation_id'='a4650000-0000-4000-8000-000000000310';
  IF x->'navn_forkortes' IS DISTINCT FROM 'null'::jsonb OR x->>'identity_outcome' IS DISTINCT FROM 'ingen_kandidat' THEN
    RAISE EXCEPTION 'FEJL: række 10 %',x - 'cited';
  END IF;
END $$;
-- Rækkeeksporten uden kildescope: begge kilder, ingen nye felter, byte-ens med main's fil på samme fixtur.
SELECT set_config('daa.control_src','',true) \g /dev/null
\i tests/sql/lib-read-control-rows.sql
DO $$
DECLARE r jsonb := current_setting('t6.rows')::jsonb;
BEGIN
  IF jsonb_array_length(r) <> 10
     OR EXISTS (SELECT 1 FROM jsonb_array_elements(r) e
                 WHERE e ?| ARRAY['identity_outcome','persona_id','identity_version','navn_forkortes']) THEN
    RAISE EXCEPTION 'FEJL: rækker uden kildescope %',jsonb_array_length(r);
  END IF;
  IF encode(sha256(convert_to(current_setting('t6.rows'),'UTF8')),'hex') <> 'a2b8a1d903665bdb8e7d85fdc001b33f945be758f66b6aeed90589fbb1837de4' THEN
    RAISE EXCEPTION 'FEJL: rækkeeksporten uden kildescope er ikke byte-ens med main: %',
      encode(sha256(convert_to(current_setting('t6.rows'),'UTF8')),'hex');
  END IF;
END $$;
-- Accepteret rival (fix-runde 1): kun 02 (kilde B) accepteres. Med kildescope A tæller den accepterede rival med, så 01
-- er TARGET_SHARED, som målfindingen vil sige efter accept; uden kildescope er 01 MATCH som i dag (v1).
SET LOCAL default_transaction_read_only = off;
SET LOCAL ROLE authenticated;
SELECT red_decide_interpretation('a4650000-0000-4000-8000-000000000302'::uuid,1,'accepted','{"basis":"kildescope46"}');
RESET ROLE;
SET LOCAL default_transaction_read_only = on;
SELECT set_config('daa.control_src','-4650',true) \g /dev/null
\o /dev/null
\i .claude/skills/daa-extract/scripts/interpretation_control_classification.sql
\o
SELECT set_config('daa.control_src','',true) \g /dev/null
DO $$ BEGIN
  IF (SELECT i->>'class' FROM jsonb_array_elements(current_setting('daa.control_result')::jsonb->'items') i
       WHERE i->>'interpretation_id'='a4650000-0000-4000-8000-000000000301') IS DISTINCT FROM 'TARGET_SHARED' THEN
    RAISE EXCEPTION 'FEJL: 01 med accepteret rival og kildescope A %',current_setting('daa.control_result');
  END IF;
END $$;
\o /dev/null
\i .claude/skills/daa-extract/scripts/interpretation_control_classification.sql
\o
DO $$ BEGIN
  IF (SELECT i->>'class'||' '||(i->>'assertion_id') FROM jsonb_array_elements(current_setting('daa.control_result')::jsonb->'items') i
       WHERE i->>'interpretation_id'='a4650000-0000-4000-8000-000000000301') IS DISTINCT FROM 'MATCH -4661' THEN
    RAISE EXCEPTION 'FEJL: 01 med accepteret rival uden kildescope %',current_setting('daa.control_result');
  END IF;
END $$;
-- Klassifikationens MATCH godkendes af RPC'en (efter accept), og dens nye klasser afvises af den med ALREADY_BOUND_OTHER.
SET LOCAL default_transaction_read_only = off;
SET LOCAL ROLE authenticated;
SELECT red_decide_interpretation(('a4650000-0000-4000-8000-0000000003'||n)::uuid,1,'accepted','{"basis":"kildescope46"}')
  FROM (VALUES ('01'),('05'),('06')) v(n);
RESET ROLE;
SELECT set_config('t6.cur',(SELECT jsonb_object_agg(right(interpretation_key::text,2),id)
                              FROM private.interpretation_current WHERE interpretation_key::text LIKE 'a4650000-%')::text,true) \g /dev/null
-- Målfindingen med kildescope på hver af de to kilder: intet element for den delte påstand -4661 (01 i A, 02 i B),
-- mens A's MATCH (06 → -4664) leveres.
SELECT set_config('daa.control_src','-4650',true) \g /dev/null
\o /dev/null
\i .claude/skills/daa-extract/scripts/interpretation_promotion_targets.sql
\o
DO $$
DECLARE r jsonb := current_setting('daa.targets_result')::jsonb;
BEGIN
  IF (SELECT jsonb_agg(x->>'target_id' ORDER BY x->>'target_id') FROM jsonb_array_elements(r->'items') x)
     IS DISTINCT FROM '["-4664"]'::jsonb OR (r->'counts'->'person.death'->>'TARGET_SHARED')::int IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'FEJL: målfinding med kildescope A %',r;
  END IF;
END $$;
SELECT set_config('daa.control_src','-4659',true) \g /dev/null
\o /dev/null
\i .claude/skills/daa-extract/scripts/interpretation_promotion_targets.sql
\o
SELECT set_config('daa.control_src','',true) \g /dev/null
DO $$
DECLARE r jsonb := current_setting('daa.targets_result')::jsonb;
BEGIN
  IF jsonb_array_length(r->'items') <> 0 OR (r->'counts'->'person.death'->>'TARGET_SHARED')::int IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'FEJL: målfinding med kildescope B %',r;
  END IF;
END $$;
SET LOCAL ROLE authenticated;
DO $$
DECLARE cur jsonb := current_setting('t6.cur')::jsonb;
        p jsonb;
BEGIN
  p := red_preview_interpretation_promotions(jsonb_build_array(
         jsonb_build_object('interpretation_id',cur->'06','target_type','assertion','target_id',-4664)));
  IF (p->'items'->0->>'eligible')::boolean IS NOT TRUE THEN RAISE EXCEPTION 'FEJL: RPC afviser MATCH %',p; END IF;
  p := red_preview_interpretation_promotions(jsonb_build_array(
         jsonb_build_object('interpretation_id',cur->'05','target_type','assertion','target_id',-4663)));
  IF p->'items'->0->>'reason_code' IS DISTINCT FROM 'ALREADY_BOUND_OTHER' THEN
    RAISE EXCEPTION 'FEJL: RPC og klassifikation uenige om ALREADY_BOUND_OTHER %',p;
  END IF;
  p := red_preview_interpretation_promotions(jsonb_build_array(
         jsonb_build_object('interpretation_id',cur->'01','target_type','assertion','target_id',-4661),
         jsonb_build_object('interpretation_id',cur->'02','target_type','assertion','target_id',-4661)));
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(p->'items') i WHERE i->>'reason_code' IS DISTINCT FROM 'ALREADY_BOUND_OTHER') THEN
    RAISE EXCEPTION 'FEJL: RPC og klassifikation uenige om TARGET_SHARED %',p;
  END IF;
  RAISE NOTICE 'OK: interpretation_control_classification — kildescope, ALREADY_BOUND_OTHER, TARGET_SHARED, rækkernes nye felter';
END $$;
RESET ROLE;
ROLLBACK;

-- Rækkeeksporten på overførselsfixturen med to kilder: byte-ens med main uden kildescope, kun -4700's rækker med.
BEGIN;
\i tests/sql/transfer-fixture.sql
SELECT pg_temp.transfer_fx(-4700,'a4700000','b4700000') \g /dev/null
SELECT pg_temp.transfer_fx(-4800,'a4800000','b4800000') \g /dev/null
\i tests/sql/lib-read-control-rows.sql
DO $$ BEGIN
  IF jsonb_array_length(current_setting('t6.rows')::jsonb) <> 6
     OR encode(sha256(convert_to(current_setting('t6.rows'),'UTF8')),'hex') <> 'b54f3b39cf5dc9f9237a9252cd134bc33dbd77e142b89d42385d5b682c348533' THEN
    RAISE EXCEPTION 'FEJL: rækkeeksporten på overførselsfixturen er ikke byte-ens med main: % rækker, %',
      jsonb_array_length(current_setting('t6.rows')::jsonb),
      encode(sha256(convert_to(current_setting('t6.rows'),'UTF8')),'hex');
  END IF;
END $$;
SELECT set_config('daa.control_src','-4700',true) \g /dev/null
\i tests/sql/lib-read-control-rows.sql
DO $$
DECLARE r jsonb := current_setting('t6.rows')::jsonb;
BEGIN
  IF jsonb_array_length(r) <> 3
     OR EXISTS (SELECT 1 FROM jsonb_array_elements(r) e WHERE e->>'interpretation_id' NOT LIKE 'a4700000-%')
     OR (SELECT count(*) FROM jsonb_array_elements(r) e WHERE e->>'persona_id' IS NULL) <> 1 THEN
    RAISE EXCEPTION 'FEJL: kildescope -4700 på overførselsfixturen %',jsonb_array_length(r);
  END IF;
  RAISE NOTICE 'OK: interpretation_control_rows — byte-ens med main uden kildescope, kildescope på overførselsfixturen';
END $$;
ROLLBACK;
