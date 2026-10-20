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

-- Bognummeret: samme liste som tests/fixtures/relation-book-ordinal.json (Python-siden); hold dem ens.
BEGIN;
DO $book_ordinal$
DECLARE r record;
BEGIN
  FOR r IN SELECT * FROM (VALUES ('g. 1° m. Anna Alfa',1),('Gift 2° m. Bo Beta',2),('GIFT 3º m. Cia Ceta',3),
      ('  g.  12 ° m. Dan Delta',12),('g.1°m. Eva Epsilon',1),(E'\tgift\t4°',4),('m. Fie Fi (g. 1° m. Gro Gamma)',NULL),
      ('Søn: g. 1° m. Hans',NULL),('g. m. Ib Iota',NULL),('gift 1 m. Jo Jota',NULL),('g. 1234° m. Kim Kappa',NULL),('',NULL)) v(raw,expect)
  LOOP
    IF private.relation_book_ordinal(r.raw) IS DISTINCT FROM r.expect THEN
      RAISE EXCEPTION 'ORDINAL_244_TEST_FAILED: bognummer %',r.raw;
    END IF;
  END LOOP;
  IF private.relation_book_ordinal(NULL) IS NOT NULL THEN RAISE EXCEPTION 'ORDINAL_244_TEST_FAILED: NULL'; END IF;
  RAISE NOTICE 'OK: bognummer';
END $book_ordinal$;
ROLLBACK;

-- Værnet i write_relation_persona (spec §5): bogen siger 2°, serverens nummer er 1 (eneste ægteskab) → afvist.
BEGIN;
\ir fixtures/relation-5b.sql
DO $vaern$
DECLARE v_actor uuid:='11000000-0000-0000-0000-000000024411'; s jsonb; p jsonb; c jsonb; e jsonb; v_err text;
  v_raw text:='g. 2° m. Bo Beta, f. 1801.';
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  INSERT INTO person(id,levende,privat,status) VALUES (-24411,false,false,'244');
  s:=pg_temp.f5b_source(-24411);
  p:=pg_temp.f5b_post(-24411,s,'V-1','Anna Alfa, f. 1800. '||v_raw,ARRAY['Anna Alfa, f. 1800.',v_raw],-24411,v_actor);
  c:=pg_temp.f5b_claim(-24411,s,'relation.marriage',(p->'clauses'->>1)::uuid,v_raw);
  e:=pg_temp.f5b_payload(p,c,(p->'clauses'->>1)::uuid,v_raw,'Bo Beta');
  IF (e->>'marriage_ordinal')::int IS DISTINCT FROM 1 THEN RAISE EXCEPTION 'ORDINAL_244_TEST_FAILED: værn-fixture %',e->>'marriage_ordinal'; END IF;
  BEGIN
    PERFORM pg_temp.f5b_write(-24411,v_actor,jsonb_build_object('relation-persona:'||(c->>'key'),e));
    RAISE EXCEPTION 'ORDINAL_244_TEST_FAILED: værn sprang over';
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT;
    IF v_err NOT LIKE 'REIMPORT_WRITER_RELATION_PERSONA_ORDINAL_BOOK_MISMATCH%' THEN RAISE; END IF;
  END;
  RAISE NOTICE 'OK: værn i skriveren';
END $vaern$;
ROLLBACK;
