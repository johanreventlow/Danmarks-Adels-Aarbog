-- #244 Task 4: data til nummerarkets ende-til-ende-test. Opdigtede navne. To ægteskaber i én post, afgjort og bundet
-- med det gamle fejlnummer gemt (1↔2), som de 4 i 2018-20.
\set ON_ERROR_STOP on
BEGIN;
\ir relation-5b.sql
\ir relation-2a.sql
\ir marriage-ordinal-244.sql
DO $ordinal_e2e_fixture$
DECLARE v_actor uuid:='11000000-0000-0000-0000-0000000244e2'; s jsonb; m jsonb;
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  INSERT INTO person(id,levende,privat,status,visning_navn,visning_foedt) VALUES
    (-24451,false,false,'244','Anna Alfa','1770'),(-24452,false,false,'244','Bo Beta','1768'),(-24453,false,false,'244','Cia Ceta','1775');
  s:=pg_temp.f5b_source(-24451);
  m:=pg_temp.f244_post(-24451,s,'E-1',-24451,-24452,-24453,v_actor);
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  IF pg_temp.f244_decide_and_bind(-24451,v_actor)<>2 THEN RAISE EXCEPTION 'ORDINAL_E2E_FIXTURE_FAILED'; END IF;
END $ordinal_e2e_fixture$;
COMMIT;
