-- Trin 5b 2b-iii Task 4: data til børnearkets ende-til-ende-test (writer-kontrakt 2). Opdigtede navne.
-- A: passer helt · B: kort (A3/A4, uden henvisning) · C: to partnerfamilier med børn (H3, ikke på arket).
\set ON_ERROR_STOP on
BEGIN;
\ir relation-5b.sql
\ir relation-2a.sql
DO $child_e2e_fixture$
DECLARE v_actor uuid:='11000000-0000-0000-0000-0000002b3e2e'; s jsonb; p jsonb; c jsonb; f bigint;
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  INSERT INTO person(id,levende,privat,status,koen,visning_navn,visning_foedt) VALUES
    (-22711,false,false,'2b3','mand','Ole Alfa','1801'),(-22717,false,false,'2b3','kvinde','Eva Alfa','1803'),
    (-22712,false,false,'2b3','mand','Ib Alfa','1830'),(-22713,false,false,'2b3','mand','Bo Alfa','1832'),
    (-22714,false,false,'2b3','mand','Per Alfa','1834'),
    (-22721,false,false,'2b3','mand','Jon Beta','1801'),(-22725,false,false,'2b3','kvinde','Kit Beta','1802'),
    (-22722,false,false,'2b3','kvinde','Ane Beta','1830'),(-22723,false,false,'2b3','mand','Kai Beta','1831'),
    (-22724,false,false,'2b3','kvinde','Lis Beta','1833'),
    (-22731,false,false,'2b3','mand','Max Gamma','1801'),(-22732,false,false,'2b3','mand','Tom Gamma','1830'),
    (-22733,false,false,'2b3','kvinde','Mia Gamma','1840');
  s:=pg_temp.f5b_source(-22701);
  INSERT INTO person_external_id(person_id,source_id,linje,nr,record_key,kuld,slaegtled_lokal) VALUES
    (-22711,-22701,'V',1,'V-1','V',1),(-22712,-22701,'V',2,'V-2','V',2),(-22713,-22701,'V',3,'V-3','V',2),
    (-22714,-22701,'V',4,'V-4','V',2),(-22721,-22701,'V',11,'V-11','V',1),(-22722,-22701,'V',12,'V-12','V',2),
    (-22731,-22701,'V',21,'V-21','V',1);
  -- A: passer helt
  p:=pg_temp.f5b_post(-22701,s,'V-1','Ole Alfa. 3 sønner: Andet slægtled, V, nr. 2-4.',
       ARRAY['Ole Alfa.','3 sønner: Andet slægtled, V, nr. 2-4.'],-22711,v_actor);
  PERFORM pg_temp.f2a_event_for_state((p->>'principal')::uuid);
  c:=pg_temp.f5b_claim(-22701,s,'relation.child',(p->'clauses'->>1)::uuid,'3 sønner: Andet slægtled, V, nr. 2-4.');
  INSERT INTO private.interpretation_party(interpretation_key,party_role,version,source_persona_id,post_offset,origin,origin_ref)
    VALUES ((c->>'key')::uuid,'principal',1,(p->>'principal')::uuid,0,'relation_persona',gen_random_uuid());
  f:=pg_temp.f5b_family(-22711,-22717,1);
  INSERT INTO family_member(family_id,person_id,rolle) VALUES (f,-22712,'barn'),(f,-22713,'barn'),(f,-22714,'barn');
  -- B: uden henvisning og usikker (kort)
  p:=pg_temp.f5b_post(-22701,s,'V-11','Jon Beta. 3 børn (?)',ARRAY['Jon Beta.','3 børn (?)'],-22721,v_actor);
  PERFORM pg_temp.f2a_event_for_state((p->>'principal')::uuid);
  c:=pg_temp.f5b_claim(-22701,s,'relation.child',(p->'clauses'->>1)::uuid,'3 børn (?)');
  INSERT INTO private.interpretation_party(interpretation_key,party_role,version,source_persona_id,post_offset,origin,origin_ref)
    VALUES ((c->>'key')::uuid,'principal',1,(p->>'principal')::uuid,0,'relation_persona',gen_random_uuid());
  f:=pg_temp.f5b_family(-22721,-22725,1);
  INSERT INTO family_member(family_id,person_id,rolle) VALUES (f,-22722,'barn'),(f,-22723,'barn'),(f,-22724,'barn');
  -- C: to partnerfamilier med børn (H3)
  p:=pg_temp.f5b_post(-22701,s,'V-21','Max Gamma. 2 børn',ARRAY['Max Gamma.','2 børn'],-22731,v_actor);
  PERFORM pg_temp.f2a_event_for_state((p->>'principal')::uuid);
  c:=pg_temp.f5b_claim(-22701,s,'relation.child',(p->'clauses'->>1)::uuid,'2 børn');
  INSERT INTO private.interpretation_party(interpretation_key,party_role,version,source_persona_id,post_offset,origin,origin_ref)
    VALUES ((c->>'key')::uuid,'principal',1,(p->>'principal')::uuid,0,'relation_persona',gen_random_uuid());
  f:=pg_temp.f5b_family(-22731,NULL,1);
  INSERT INTO family_member(family_id,person_id,rolle) VALUES (f,-22732,'barn');
  f:=pg_temp.f5b_family(-22731,NULL,2);
  INSERT INTO family_member(family_id,person_id,rolle) VALUES (f,-22733,'barn');
  SET CONSTRAINTS ALL IMMEDIATE;
END $child_e2e_fixture$;
COMMIT;
