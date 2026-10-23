-- 5a+5b-overførslen, plan B1 Task 3b: dumpets side af del 1. Kilde -25101 med 22 poster »Hoved i. g. m. Mage i.«,
-- hver med én ægteskabspåstand og én familie (ordinal 1) med begge partnere. K=20 tilfældige i kontrolstikprøven
-- (schema.sql:16172) ⇒ mindst én egnet persona står tilbage til family_corroboration (som test-family-corroboration.sql).
-- Køres som ejer efter relation-5b.sql i dumpets transaktion; B får rækkerne via kopien.
DO $d1$
DECLARE v_actor uuid:='11000000-0000-0000-0000-000000025001'; s jsonb; p jsonb; i int; v_name text;
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  s:=pg_temp.f5b_source(-25101);
  FOR i IN 1..22 LOOP
    INSERT INTO person(id,levende,privat,status) VALUES (-25200-i*2,false,false,'5b'),(-25200-i*2-1,false,false,'5b');
    v_name:='Mage '||i;
    p:=pg_temp.f5b_post(-25101,s,'G-'||lpad(i::text,2,'0'),'Hoved '||i||'. g. m. '||v_name||'.',
       ARRAY['Hoved '||i||'.','g. m. '||v_name||'.'],-25200-i*2,v_actor);
    PERFORM pg_temp.f2a_event_for_state((p->>'principal')::uuid);   -- f5b_post skriver kun state-rækken
    PERFORM pg_temp.f5b_claim(-25101,s,'relation.marriage',(p->'clauses'->>1)::uuid,'g. m. '||v_name||'.');
    PERFORM pg_temp.f5b_family(-25200-i*2,-25200-i*2-1,1);
  END LOOP;
END $d1$;
