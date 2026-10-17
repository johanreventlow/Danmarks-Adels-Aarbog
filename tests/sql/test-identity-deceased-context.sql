-- Trin 5b 2b-ii (#151, spec §5.4): deceased-konteksten valideres og gemmes ved new_person_needed.
\set ON_ERROR_STOP on
BEGIN;
\ir fixtures/relation-5b.sql
DO $deceased$
DECLARE v_actor uuid:='11000000-0000-0000-0000-00000005b2b1'; s jsonb; p jsonb; c jsonb; sp uuid; v int;
  h text:=repeat('a',64); ok jsonb; bad jsonb[];
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  INSERT INTO person(id,levende,privat,status) VALUES (-5221,false,false,'5b');
  s:=pg_temp.f5b_source(-5221);
  p:=pg_temp.f5b_post(-5221,s,'II-21','Anna Alfa. Gift 1890 med Bo Beta.',ARRAY['Anna Alfa.','Gift 1890 med Bo Beta.'],-5221,v_actor);
  c:=pg_temp.f5b_claim(-5221,s,'relation.marriage',(p->'clauses'->>1)::uuid,'Gift 1890 med Bo Beta.');
  sp:=pg_temp.f5b_spouse(-5221,s,p,c,(p->'clauses'->>1)::uuid,'Bo Beta',1);
  ok:=jsonb_build_object('basis','human_sheet','sheet_sha256',h,'rows_sha256',h,'line',1,
       'deceased',jsonb_build_object('rule','vielsesaar-120-v1','cutoff_year',1921,'clause_years',jsonb_build_array(1890)));
  bad:=ARRAY[
    ok||jsonb_build_object('deceased',jsonb_build_object('rule','x','cutoff_year',1921,'clause_years',jsonb_build_array(1890))),
    ok||jsonb_build_object('deceased',jsonb_build_object('rule','vielsesaar-120-v1','cutoff_year',1921,'clause_years','[]'::jsonb)),
    ok||jsonb_build_object('deceased',jsonb_build_object('rule','vielsesaar-120-v1','cutoff_year',1921,'clause_years',jsonb_build_array(1950))),
    ok||jsonb_build_object('deceased',jsonb_build_object('rule','vielsesaar-120-v1','cutoff_year',1930,'clause_years',jsonb_build_array(1890))),
    ok||jsonb_build_object('deceased',jsonb_build_object('rule','vielsesaar-120-v1','cutoff_year',1921,'clause_years',jsonb_build_array('1890'))),
    ok||jsonb_build_object('deceased',jsonb_build_object('rule','vielsesaar-120-v1','cutoff_year',1921,'clause_years',jsonb_build_array(1890),'x',1)),
    ok||jsonb_build_object('basis','web_detail')];
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  SET LOCAL ROLE authenticated;
  FOR i IN 1..array_length(bad,1) LOOP
    BEGIN
      PERFORM red_afgoer_source_persona(sp,0,'new_person_needed',NULL,'test',bad[i]);
      RAISE EXCEPTION 'DECEASED_TEST_FAILED: ugyldig % godtaget',i;
    EXCEPTION WHEN raise_exception THEN
      IF SQLERRM LIKE 'DECEASED_TEST_FAILED%' THEN RAISE; END IF;
    END;
  END LOOP;
  BEGIN
    PERFORM red_afgoer_source_persona(sp,0,'same',-5221,'test',ok);
    RAISE EXCEPTION 'DECEASED_TEST_FAILED: deceased på same godtaget';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM LIKE 'DECEASED_TEST_FAILED%' THEN RAISE; END IF; END;
  v:=red_afgoer_source_persona(sp,0,'new_person_needed',NULL,'test',ok);
  RESET ROLE;
  IF (SELECT evidence->'deceased' FROM private.source_persona_identity WHERE source_persona_id=sp) IS DISTINCT FROM ok->'deceased'
     OR (SELECT evidence->>'reason' FROM private.source_persona_identity WHERE source_persona_id=sp)<>'new_person_needed' THEN
    RAISE EXCEPTION 'DECEASED_TEST_FAILED: evidens';
  END IF;
  RAISE NOTICE 'OK: deceased-kontekst valideret og gemt';
END $deceased$;
ROLLBACK;
