-- Trin 6d-3 Task 6 trin 4: data til forælderarkets kontekst-test. Opdigtede navne; kilde -26101.
-- A: barnet Ib Delta (post V-2) er "Søn af Ole Delta & Eva Delta" og forældrenes familie findes (én kandidat).
-- B: barnet Kai Delta (post V-3) har en klausul uden kandidat (ingen forældrefamilie i DB).
\set ON_ERROR_STOP on
BEGIN;
\ir relation-5b.sql
\ir relation-2a.sql
DO $parent_e2e_fixture$
DECLARE v_actor uuid:='11000000-0000-0000-0000-0000002b3e2f'; s jsonb; p jsonb; c jsonb; f bigint;
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  INSERT INTO person(id,levende,privat,status,koen,visning_navn,visning_foedt,visning_doed) VALUES
    (-26111,false,false,'2b3','mand','Ole Delta','1801','1870'),(-26117,false,false,'2b3','kvinde','Eva Delta','1803','1880'),
    (-26112,false,false,'2b3','mand','Ib Delta','1830','1900'),(-26113,false,false,'2b3','kvinde','Ida Delta','1832',NULL),
    (-26114,false,false,'2b3','mand','Kai Delta','1834',NULL);
  s:=pg_temp.f5b_source(-26101);
  -- Forældrenes post (giver familiens partnere en persona i kilden, så kandidaten findes)
  p:=pg_temp.f5b_post(-26101,s,'V-1','Ole Delta. Gift med Eva Delta.',ARRAY['Ole Delta.','Gift med Eva Delta.'],-26111,v_actor);
  PERFORM pg_temp.f2a_event_for_state((p->>'principal')::uuid);
  p:=pg_temp.f5b_post(-26101,s,'V-2','Ib Delta, f. 1830. Søn af Ole <Delta> & Eva Delta.',
       ARRAY['Ib Delta, f. 1830.','Søn af Ole <Delta> & Eva Delta.'],-26112,v_actor);
  PERFORM pg_temp.f2a_event_for_state((p->>'principal')::uuid);
  c:=pg_temp.f5b_claim(-26101,s,'relation.parent',(p->'clauses'->>1)::uuid,'Søn af Ole <Delta> & Eva Delta.');
  INSERT INTO private.interpretation_party(interpretation_key,party_role,version,source_persona_id,post_offset,origin,origin_ref)
    VALUES ((c->>'key')::uuid,'principal',1,(p->>'principal')::uuid,0,'relation_persona',gen_random_uuid());
  f:=pg_temp.f5b_family(-26111,-26117,1);
  INSERT INTO family_member(family_id,person_id,rolle) VALUES (f,-26112,'barn'),(f,-26113,'barn');
  -- B: ingen kandidat
  p:=pg_temp.f5b_post(-26101,s,'V-3','Kai Delta. Søn af en ukendt.',ARRAY['Kai Delta.','Søn af en ukendt.'],-26114,v_actor);
  PERFORM pg_temp.f2a_event_for_state((p->>'principal')::uuid);
  c:=pg_temp.f5b_claim(-26101,s,'relation.parent',(p->'clauses'->>1)::uuid,'Søn af en ukendt.');
  INSERT INTO private.interpretation_party(interpretation_key,party_role,version,source_persona_id,post_offset,origin,origin_ref)
    VALUES ((c->>'key')::uuid,'principal',1,(p->>'principal')::uuid,0,'relation_persona',gen_random_uuid());
  SET CONSTRAINTS ALL IMMEDIATE;
END $parent_e2e_fixture$;
COMMIT;
