-- Fælles fixture for overførselstestene (plan A, Task 1). Kaldes inden for BEGIN … ROLLBACK.
-- Opretter de delte rækker (bruger, person, fakta, assertions) og funktionen pg_temp.transfer_fx,
-- som bygger ÉN kilde. Restore og prod har samme kilde-id og samme deterministiske
-- interpretation_key'er, men forskellige tilfældige uuid'er; testene efterligner det med
-- varianter: SAVEPOINT → transfer_fx(-4700, <uuid-præfiks>, 'b4700000', <variant>) → mål →
-- ROLLBACK TO SAVEPOINT. Varianter deler kilde-id og nøgler og adskiller sig kun i uuid-præfiks
-- og det varierede felt. Tre forslag pr. kilde:
--   k1 person.death '1850' (persona T-1, citerer BEGGE klausuler, linkordinal 1 → klausul 2,
--      linkordinal 2 → klausul 1) → MATCH mod assertion -4711
--   k2 person.name  'Anna' (persona T-1, citerer klausul 1) → REAL_DIFF (assertion 'Anne')
--   k3 mention.place 'Kbh' (ingen persona, citerer klausul 2) → ingen regel
-- (Fixturen har ingen placement-rækker; 'principal' er ikke modelleret her.)
-- Persona/record-nøgle 'T-1' peger på person -4701. De rå tabeller er append-only.
INSERT INTO auth.users(id,email) VALUES ('a4700000-0000-4000-8000-000000000001','transfer47@test.invalid');
INSERT INTO profiles(id,rolle,navn,email) VALUES
  ('a4700000-0000-4000-8000-000000000001','redaktion','Transfer 47','transfer47@test.invalid');
INSERT INTO person(id,levende,privat,status) VALUES (-4701,false,false,'transfer47');
INSERT INTO fact(id,subjekt_type,subjekt_id,faktatype) VALUES (-4711,'person',-4701,'død'),(-4712,'person',-4701,'navn');
INSERT INTO assertion(id,target_type,target_id,date_raw,calendar,uforanderlig) VALUES (-4711,'fact',-4711,'1850','gregoriansk',true);
INSERT INTO assertion(id,target_type,target_id,vaerdi_tekst,calendar,uforanderlig) VALUES (-4712,'fact',-4712,'Anne','gregoriansk',true);

-- Bygger én kilde. p_s = source id, p_pre = 8-tegns uuid-præfiks (a47xx000),
-- p_kp = 8-tegns præfiks for interpretation_key'erne (key er globalt unik pr. version i
-- skemaet, så to kilder i samme base kan ikke dele nøgler), p_c1 = tekst i klausul 1 (klausul 2 er altid 'i Kbh'), p_swap = byt klausulernes ordinaler,
-- p_name = værdien af person.name-forslaget, p_permute = byt uuid-suffikser på klausuler og
-- k1/k2 (id-rækkefølgen vendes, logikken er uændret), p_record_key = postens nøgle,
-- p_anchor = false udelader ankeret (ingen accepteret post).
CREATE FUNCTION pg_temp.transfer_fx(p_s bigint, p_pre text, p_kp text, p_c1 text DEFAULT 'Anna død 1850',
                                    p_swap boolean DEFAULT false, p_name text DEFAULT 'Anna',
                                    p_permute boolean DEFAULT false, p_record_key text DEFAULT 'T-1',
                                    p_anchor boolean DEFAULT true) RETURNS void
LANGUAGE plpgsql AS $fx$
DECLARE pre text := p_pre; s bigint := p_s; v_text text := p_c1||' i Kbh'; v_n1 int := char_length(p_c1);
        v_len int := char_length(p_c1||' i Kbh');
        c1 text := CASE WHEN p_permute THEN 'c2' ELSE 'c1' END; c2 text := CASE WHEN p_permute THEN 'c1' ELSE 'c2' END;
        i1 text := CASE WHEN p_permute THEN '302' ELSE '301' END; i2 text := CASE WHEN p_permute THEN '301' ELSE '302' END;
BEGIN
  INSERT INTO source(id,titel,import_key) VALUES (s,'Transfer '||s,'verify:transfer'||s);
  INSERT INTO private.extraction_run(id,source_id,run_key,schema_version,extractor_version,profile_version,input_sha256,manifest)
    VALUES ((pre||'-0000-4000-8000-0000000000e1')::uuid,s,'transfer-run'||s,'1.0','verify','verify',repeat('9',64),'{}');
  INSERT INTO private.source_rendition(id,source_id,rendition_key,rendition_kind,content_sha256,metadata)
    VALUES ((pre||'-0000-4000-8000-0000000000e2')::uuid,s,'transfer-rendition','text_layer',repeat('8',64),'{}');
  INSERT INTO private.source_record_occurrence(id,rendition_id,occurrence_key,page_from,page_to,char_from,char_to,
    verbatim_text,physical_fingerprint,structural_fingerprint,extraction_run_id)
    VALUES ((pre||'-0000-4000-8000-0000000000e3')::uuid,(pre||'-0000-4000-8000-0000000000e2')::uuid,'transfer-occ',1,1,0,v_len,
            v_text,'phys-t','struct-t',(pre||'-0000-4000-8000-0000000000e1')::uuid);
  INSERT INTO private.source_record(id,source_id,record_key,record_kind,created_run_id)
    VALUES ((pre||'-0000-4000-8000-0000000000e5')::uuid,s,p_record_key,'person_entry',(pre||'-0000-4000-8000-0000000000e1')::uuid);
  IF p_anchor THEN
    INSERT INTO private.source_record_anchor_event(occurrence_id,source_record_id,decision_status,evidence,version,decided_by,decided_by_name)
      VALUES ((pre||'-0000-4000-8000-0000000000e3')::uuid,(pre||'-0000-4000-8000-0000000000e5')::uuid,'accepted',
              '{"basis":"transfer-fixture"}',1,'a4700000-0000-4000-8000-000000000001','fixture');
  END IF;
  -- Helpost + to klausuler (sæt 1; ordinal 1 og 2, evt. byttet).
  INSERT INTO private.source_observation(id,occurrence_id,observation_kind,page_from,page_to,char_from,char_to,
    verbatim_text,quality_status,extraction_method,extraction_run_id)
    VALUES ((pre||'-0000-4000-8000-0000000000c0')::uuid,(pre||'-0000-4000-8000-0000000000e3')::uuid,'person_post',1,1,0,v_len,
            v_text,'clear','verify',(pre||'-0000-4000-8000-0000000000e1')::uuid);
  INSERT INTO private.source_observation(id,occurrence_id,observation_kind,page_from,page_to,char_from,char_to,
    verbatim_text,quality_status,extraction_method,extraction_run_id,parent_observation_id,post_char_from,post_char_to,
    clause_ordinal,clause_classification,clause_flags,clause_set_seq)
    VALUES ((pre||'-0000-4000-8000-0000000000'||c1)::uuid,(pre||'-0000-4000-8000-0000000000e3')::uuid,'clause',1,1,0,v_n1,
            p_c1,'clear','clause_segment_v1',(pre||'-0000-4000-8000-0000000000e1')::uuid,
            (pre||'-0000-4000-8000-0000000000c0')::uuid,0,v_n1,CASE WHEN p_swap THEN 2 ELSE 1 END,'record_text','[]',1),
           ((pre||'-0000-4000-8000-0000000000'||c2)::uuid,(pre||'-0000-4000-8000-0000000000e3')::uuid,'clause',1,1,v_n1+1,v_len,
            'i Kbh','clear','clause_segment_v1',(pre||'-0000-4000-8000-0000000000e1')::uuid,
            (pre||'-0000-4000-8000-0000000000c0')::uuid,v_n1+1,v_len,CASE WHEN p_swap THEN 1 ELSE 2 END,'record_text','[]',1);
  INSERT INTO private.source_persona(id,source_id,persona_key,created_run_id)
    VALUES ((pre||'-0000-4000-8000-000000000101')::uuid,s,'T-1',(pre||'-0000-4000-8000-0000000000e1')::uuid);
  INSERT INTO private.source_persona_identity_event(source_persona_id,canonical_person_id,decision_status,version,evidence,
                                                    decided_by,decided_by_name,decided_at)
    VALUES ((pre||'-0000-4000-8000-000000000101')::uuid,-4701,'accepted',1,'{"basis":"fixture"}',
            'a4700000-0000-4000-8000-000000000001','fixture',now());
  INSERT INTO private.source_persona_identity(source_persona_id,canonical_person_id,decision_status,version,evidence,
                                              decided_by,decided_by_name,decided_at)
    VALUES ((pre||'-0000-4000-8000-000000000101')::uuid,-4701,'accepted',1,'{"basis":"fixture"}',
            'a4700000-0000-4000-8000-000000000001','fixture',now());
  INSERT INTO private.interpretation(id,interpretation_key,version,source_id,source_persona_id,interpretation_kind,
    predicate,value,schema_version,derivation_kind,confidence,status,method,extraction_run_id)
  VALUES
    ((pre||'-0000-4000-8000-000000000'||i1)::uuid,(p_kp||'-0000-4000-8000-000000000001')::uuid,1,s,(pre||'-0000-4000-8000-000000000101')::uuid,
     'property','person.death',to_jsonb('1850'::text),'1.0','source_statement',1,'proposed','verify',(pre||'-0000-4000-8000-0000000000e1')::uuid),
    ((pre||'-0000-4000-8000-000000000'||i2)::uuid,(p_kp||'-0000-4000-8000-000000000002')::uuid,1,s,(pre||'-0000-4000-8000-000000000101')::uuid,
     'property','person.name',to_jsonb(p_name),'1.0','source_statement',1,'proposed','verify',(pre||'-0000-4000-8000-0000000000e1')::uuid),
    ((pre||'-0000-4000-8000-000000000303')::uuid,(p_kp||'-0000-4000-8000-000000000003')::uuid,1,s,NULL,
     'mention','mention.place',to_jsonb('Kbh'::text),'1.0','source_statement',1,'proposed','verify',(pre||'-0000-4000-8000-0000000000e1')::uuid);
  INSERT INTO private.interpretation_observation(interpretation_id,observation_id,evidence_role,ordinal) VALUES
    ((pre||'-0000-4000-8000-000000000'||i1)::uuid,(pre||'-0000-4000-8000-0000000000'||c2)::uuid,'supporting',1),
    ((pre||'-0000-4000-8000-000000000'||i1)::uuid,(pre||'-0000-4000-8000-0000000000'||c1)::uuid,'supporting',2),
    ((pre||'-0000-4000-8000-000000000'||i2)::uuid,(pre||'-0000-4000-8000-0000000000'||c1)::uuid,'supporting',1),
    ((pre||'-0000-4000-8000-000000000303')::uuid,(pre||'-0000-4000-8000-0000000000'||c2)::uuid,'supporting',1);
  INSERT INTO private.clause_disposition(observation_id,version,disposition,decided_by_kind,evidence)
    VALUES ((pre||'-0000-4000-8000-0000000000'||c1)::uuid,1,'fortolkning_foreslaaet','machine',
            jsonb_build_object('batch_id',pre||'-0000-4000-8000-0000000000e1','manifest_sha256',repeat('7',64))),
           ((pre||'-0000-4000-8000-0000000000'||c2)::uuid,1,'fortolkning_foreslaaet','machine',
            jsonb_build_object('batch_id',pre||'-0000-4000-8000-0000000000e1','manifest_sha256',repeat('7',64)));
END $fx$;
