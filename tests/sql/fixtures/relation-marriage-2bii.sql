-- Trin 5b 2b-ii Task 5: data til ægteskabsarkets ende-til-ende-test. Committes i en engangsbase med
-- writer-kontrakt 2. Tre parkerede ægteskaber uden persona: D (gift 1890), S (partneren findes), I (intet navn).
\set ON_ERROR_STOP on
BEGIN;
\ir relation-5b.sql
\ir relation-2a.sql
DO $marriage_sheet_fixture$
DECLARE v_actor uuid:='11000000-0000-0000-0000-0000002b0601'; s jsonb; p jsonb;
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  INSERT INTO person(id,levende,privat,status,visning_navn) VALUES
    (-22501,false,false,'2bii','Anna A'),(-22502,false,false,'2bii','Bent B'),(-22503,false,false,'2bii','Carl C'),
    (-22512,false,false,'2bii','Cia Carla Ceta');
  s:=pg_temp.f5b_source(-22501);
  p:=pg_temp.f5b_post(-22501,s,'E-1','Anna A. Gift 1. gang 1890 med Bo Beta, f. 1801.',
       ARRAY['Anna A.','Gift 1. gang 1890 med Bo Beta, f. 1801.'],-22501,v_actor);
  PERFORM pg_temp.f2a_event_for_state((p->>'principal')::uuid);
  PERFORM pg_temp.f5b_claim(-22501,s,'relation.marriage',(p->'clauses'->>1)::uuid,'Gift med Bo Beta');
  p:=pg_temp.f5b_post(-22501,s,'E-2','Bent B. Gift 1890 med Cia Ceta.',ARRAY['Bent B.','Gift 1890 med Cia Ceta.'],-22502,v_actor);
  PERFORM pg_temp.f2a_event_for_state((p->>'principal')::uuid);
  PERFORM pg_temp.f5b_claim(-22501,s,'relation.marriage',(p->'clauses'->>1)::uuid,'Gift med Cia Ceta');
  PERFORM pg_temp.f5b_family(-22502,-22512,1);
  p:=pg_temp.f5b_post(-22501,s,'E-3','Carl C. Gift 1975.',ARRAY['Carl C.','Gift 1975.'],-22503,v_actor);
  PERFORM pg_temp.f2a_event_for_state((p->>'principal')::uuid);
  PERFORM pg_temp.f5b_claim(-22501,s,'relation.marriage',(p->'clauses'->>1)::uuid,'Gift 1975.');
  SET CONSTRAINTS ALL IMMEDIATE;
END $marriage_sheet_fixture$;
COMMIT;
