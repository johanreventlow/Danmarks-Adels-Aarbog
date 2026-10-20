-- #244 (spec 2026-10-20): ægteskabsnummer efter vinduet, bognummer, værn, rettelsesskriver og genbinding.
-- Opdigtede navne. Kører i writer_1939 som ejer. Hver blok i sin egen transaktion (fixturer committes aldrig).
\set ON_ERROR_STOP on
BEGIN;
\ir fixtures/relation-5b.sql
\ir fixtures/relation-2a.sql
\ir fixtures/marriage-ordinal-244.sql
DO $ordinals_vindue$
DECLARE v_actor uuid:='11000000-0000-0000-0000-000000024401'; s jsonb; m jsonb; c jsonb; p jsonb; v_ord int[];
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  INSERT INTO person(id,levende,privat,status) SELECT g,false,false,'244' FROM generate_series(-24409,-24401) g;
  s:=pg_temp.f5b_source(-24401);
  m:=pg_temp.f244_post(-24401,s,'O-1',-24401,-24402,-24403,v_actor);
  -- ordinals_parentes: påstand 1 (springer parentesen over) er nr. 1, påstand 2 er nr. 2
  SELECT array_agg(o.marriage_ordinal ORDER BY o.interpretation_key=(m->'c1'->>'key')::uuid DESC) INTO v_ord
    FROM private.relation_marriage_ordinals((m->'post'->>'occ')::uuid) o;
  IF v_ord IS DISTINCT FROM ARRAY[1,2] THEN RAISE EXCEPTION 'ORDINAL_244_TEST_FAILED: parentes %',v_ord; END IF;
  IF (SELECT o.post_offset FROM private.relation_marriage_ordinals((m->'post'->>'occ')::uuid) o
       WHERE o.interpretation_key=(m->'c1'->>'key')::uuid) IS DISTINCT FROM
     (SELECT post_char_from FROM private.source_observation WHERE id=(m->'post'->'clauses'->>1)::uuid) THEN
    RAISE EXCEPTION 'ORDINAL_244_TEST_FAILED: position';
  END IF;
  -- ordinals_uden_vindue: en påstand uden ordvindue i en post med to ægteskaber → NULL, sorteret sidst
  p:=pg_temp.f5b_post(-24401,s,'O-2','Eva Epsilon. Gift 1° m. Ib Iota. Gift 2° m. Jo Jota.',
       ARRAY['Eva Epsilon.','Gift 1° m. Ib Iota.','Gift 2° m. Jo Jota.'],-24404,v_actor);
  c:=pg_temp.f5b_claim(-24401,s,'relation.marriage',(p->'clauses'->>1)::uuid,'Gift m. Xu Xa.');
  PERFORM pg_temp.f5b_claim(-24401,s,'relation.marriage',(p->'clauses'->>2)::uuid,'Gift 2° m. Jo Jota.');
  IF (SELECT array_agg(o.post_offset IS NULL ORDER BY o.marriage_ordinal) FROM private.relation_marriage_ordinals((p->>'occ')::uuid) o)
     IS DISTINCT FROM ARRAY[false,true] THEN
    RAISE EXCEPTION 'ORDINAL_244_TEST_FAILED: uden vindue';
  END IF;
  -- ordinals_null_raw: NULL-raw giver NULL-position (STRICT), ikke fejl. interpretation er tilføj-kun, så en ny post.
  p:=pg_temp.f5b_post(-24401,s,'O-3','Fie Fi. Gift m. Gro Gamma.',ARRAY['Fie Fi.','Gift m. Gro Gamma.'],-24405,v_actor);
  PERFORM pg_temp.f5b_claim(-24401,s,'relation.marriage',(p->'clauses'->>1)::uuid,NULL);
  IF (SELECT o.post_offset FROM private.relation_marriage_ordinals((p->>'occ')::uuid) o) IS NOT NULL THEN
    RAISE EXCEPTION 'ORDINAL_244_TEST_FAILED: NULL-raw';
  END IF;
  RAISE NOTICE 'OK: ægteskabsnummer efter vinduet';
END $ordinals_vindue$;
ROLLBACK;
