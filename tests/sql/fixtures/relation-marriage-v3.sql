-- Trin 5b 2b-ii runde 2 Task 4: data til ark v3's ende-til-ende-test (writer-kontrakt 2). Opdigtede navne.
\set ON_ERROR_STOP on
BEGIN;
\ir relation-5b.sql
\ir relation-2a.sql
DO $marriage_v3_fixture$
DECLARE v_actor uuid:='11000000-0000-0000-0000-0000002b0611'; s jsonb; p jsonb; c jsonb; sp uuid;
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  INSERT INTO person(id,levende,privat,status,visning_navn) VALUES
    (-22601,false,false,'v3','Anna A'),(-22602,false,false,'v3','Bent B'),(-22603,false,false,'v3','Carl C'),
    (-22611,false,false,'v3','Ida Dal');
  s:=pg_temp.f5b_source(-22601);
  p:=pg_temp.f5b_post(-22601,s,'F-1','Anna A. Gift 1890 med Ida komtesse Dal, f. 1801.',
       ARRAY['Anna A.','Gift 1890 med Ida komtesse Dal, f. 1801.'],-22601,v_actor);
  PERFORM pg_temp.f2a_event_for_state((p->>'principal')::uuid);
  PERFORM pg_temp.f5b_claim(-22601,s,'relation.marriage',(p->'clauses'->>1)::uuid,'Gift med Ida komtesse Dal');
  PERFORM pg_temp.f5b_family(-22601,-22611,1);
  p:=pg_temp.f5b_post(-22601,s,'F-2','Bent B. Gift 1890 med Eva von und zu Fik.',
       ARRAY['Bent B.','Gift 1890 med Eva von und zu Fik.'],-22602,v_actor);
  PERFORM pg_temp.f2a_event_for_state((p->>'principal')::uuid);
  PERFORM pg_temp.f5b_claim(-22601,s,'relation.marriage',(p->'clauses'->>1)::uuid,'Gift med Eva von und zu Fik');
  p:=pg_temp.f5b_post(-22601,s,'F-3','Carl C. Gift 1314 med Gro von Hak.',ARRAY['Carl C.','Gift 1314 med Gro von Hak.'],-22603,v_actor);
  PERFORM pg_temp.f2a_event_for_state((p->>'principal')::uuid);
  c:=pg_temp.f5b_claim(-22601,s,'relation.marriage',(p->'clauses'->>1)::uuid,'Gift 1314 med Gro von Hak.');
  sp:=pg_temp.f5b_spouse(-22601,s,p,c,(p->'clauses'->>1)::uuid,'Gro von Hak',1);
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  SET LOCAL ROLE authenticated;
  PERFORM red_afgoer_source_persona(sp,0,'new_person_needed',NULL,'kø',NULL);
  RESET ROLE;
  SET CONSTRAINTS ALL IMMEDIATE;
END $marriage_v3_fixture$;
COMMIT;
