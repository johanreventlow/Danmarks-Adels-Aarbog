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

-- Rettelsesskriveren (spec §7) og genbindingen (spec §8): kontekst, version, gyldig rettelse, gentagelse, input,
-- synlighed før/imellem/efter, genbinding med supersedes og familiekorroborationen (§7.5).
BEGIN;
\ir fixtures/relation-5b.sql
\ir fixtures/relation-2a.sql
\ir fixtures/marriage-ordinal-244.sql
DO $ret$
DECLARE v_actor uuid:='11000000-0000-0000-0000-000000024421'; s jsonb; m jsonb; v_in jsonb; v_err text; n int;
  ctx jsonb:=jsonb_build_object('basis','human_sheet','sheet_sha256',repeat('a',64),'rows_sha256',repeat('b',64),'line','1');
  k1 uuid; k2 uuid; v int;
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  INSERT INTO person(id,levende,privat,status) SELECT g,false,false,'244' FROM generate_series(-24429,-24421) g;
  s:=pg_temp.f5b_source(-24421);
  m:=pg_temp.f244_post(-24421,s,'R-1',-24421,-24422,-24423,v_actor);
  k1:=(m->'c1'->>'key')::uuid; k2:=(m->'c2'->>'key')::uuid;
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  n:=pg_temp.f244_decide_and_bind(-24421,v_actor);
  IF n<>2 THEN RAISE EXCEPTION 'ORDINAL_244_TEST_FAILED: fixture bandt %',n; END IF;
  -- før rettelsen: begge synlige og ALREADY_APPLIED (spec §9.1)
  IF (SELECT count(*) FROM public.public_family_sources(ARRAY[(m->>'f1')::bigint,(m->>'f2')::bigint]) x WHERE x.slags='aegteskab')<>2 THEN
    RAISE EXCEPTION 'ORDINAL_244_TEST_FAILED: synlig før';
  END IF;
  IF pg_temp.f244_bind(-24421,v_actor)<>0 THEN RAISE EXCEPTION 'ORDINAL_244_TEST_FAILED: før-preview ikke ALREADY_APPLIED'; END IF;
  -- input: begge påstande, gemt ≠ nyt
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  SET LOCAL ROLE authenticated;
  v_in:=red_marriage_ordinal_correction_input(-24421);
  IF jsonb_array_length(v_in->'rows')<>2 OR v_in->>'contract'<>'relation-ordinal-sheet-input-v1'
     OR (SELECT count(*) FROM jsonb_array_elements(v_in->'rows') r
          WHERE (r->>'stored_ordinal')::int<>(r->>'new_ordinal')::int AND (r->>'new_ordinal')::int=(r->>'family_ordinal')::int
            AND (r->>'book_ordinal')::int=(r->>'new_ordinal')::int)<>2 THEN
    RAISE EXCEPTION 'ORDINAL_244_TEST_FAILED: input %',v_in;
  END IF;
  -- ret_kontekst: ukendt nøgle, forkert basis, tom note
  BEGIN PERFORM red_ret_aegteskabsnummer(k1,1,'n',ctx||'{"x":1}'); RAISE EXCEPTION 'ORDINAL_244_TEST_FAILED: ukendt nøgle';
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT;
    IF v_err NOT LIKE 'MARRIAGE_ORDINAL_CORRECTION_CONTEXT_INVALID%' THEN RAISE; END IF; END;
  BEGIN PERFORM red_ret_aegteskabsnummer(k1,1,'n',ctx||'{"basis":"web_detail"}'); RAISE EXCEPTION 'ORDINAL_244_TEST_FAILED: basis';
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT;
    IF v_err NOT LIKE 'MARRIAGE_ORDINAL_CORRECTION_CONTEXT_INVALID%' THEN RAISE; END IF; END;
  BEGIN PERFORM red_ret_aegteskabsnummer(k1,1,' ',ctx); RAISE EXCEPTION 'ORDINAL_244_TEST_FAILED: note';
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT;
    IF v_err NOT LIKE 'MARRIAGE_ORDINAL_CORRECTION_CONTEXT_INVALID%' THEN RAISE; END IF; END;
  -- ret_version
  BEGIN PERFORM red_ret_aegteskabsnummer(k1,2,'n',ctx); RAISE EXCEPTION 'ORDINAL_244_TEST_FAILED: version';
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT;
    IF v_err NOT LIKE 'MARRIAGE_ORDINAL_CORRECTION_VERSION_MISMATCH%' THEN RAISE; END IF; END;
  -- gyldig rettelse af begge
  v:=red_ret_aegteskabsnummer(k1,1,'n',ctx);
  PERFORM red_ret_aegteskabsnummer(k2,1,'n',ctx||'{"line":"2"}');
  RESET ROLE;
  IF v<>2 OR (SELECT marriage_ordinal FROM private.interpretation_party_current WHERE interpretation_key=k1 AND party_role='spouse')<>1
     OR (SELECT origin FROM private.interpretation_party_current WHERE interpretation_key=k1 AND party_role='spouse')<>'ordinal_correction'
     OR (SELECT count(*) FROM private.marriage_ordinal_correction WHERE interpretation_key IN (k1,k2))<>2
     OR (SELECT post_offset FROM private.interpretation_party WHERE interpretation_key=k1 AND party_role='spouse' AND version=2)
        IS DISTINCT FROM (SELECT post_offset FROM private.interpretation_party WHERE interpretation_key=k1 AND party_role='spouse' AND version=1)
     OR (SELECT array_agg(ordinal ORDER BY family_id) FROM family_member WHERE person_id=-24421 AND rolle='partner')<>ARRAY[1,2] THEN
    RAISE EXCEPTION 'ORDINAL_244_TEST_FAILED: rettelse';
  END IF;
  -- tilføj-kun (spec §7.1): med de 2 rigtige rettelsesrækker afviser triggerne UPDATE/DELETE/TRUNCATE, også for ejeren
  BEGIN UPDATE private.marriage_ordinal_correction SET family_id=family_id WHERE interpretation_key IN (k1,k2);
    RAISE EXCEPTION 'ORDINAL_244_TEST_FAILED: UPDATE godtaget';
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT;
    IF v_err NOT LIKE 'EVIDENCE_APPEND_ONLY%' THEN RAISE; END IF; END;
  BEGIN DELETE FROM private.marriage_ordinal_correction WHERE interpretation_key IN (k1,k2);
    RAISE EXCEPTION 'ORDINAL_244_TEST_FAILED: DELETE godtaget';
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT;
    IF v_err NOT LIKE 'EVIDENCE_APPEND_ONLY%' THEN RAISE; END IF; END;
  BEGIN TRUNCATE private.marriage_ordinal_correction;
    RAISE EXCEPTION 'ORDINAL_244_TEST_FAILED: TRUNCATE godtaget';
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT;
    IF v_err NOT LIKE 'EVIDENCE_APPEND_ONLY%' THEN RAISE; END IF; END;
  IF (SELECT count(*) FROM private.marriage_ordinal_correction WHERE interpretation_key IN (k1,k2))<>2 THEN
    RAISE EXCEPTION 'ORDINAL_244_TEST_FAILED: tilføj-kun rækker';
  END IF;
  -- ret_gentaget: samme linje igen → version; ret_ikke_noedvendig: med den nye version → NOT_NEEDED
  SET LOCAL ROLE authenticated;
  BEGIN PERFORM red_ret_aegteskabsnummer(k1,1,'n',ctx); RAISE EXCEPTION 'ORDINAL_244_TEST_FAILED: gentaget';
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT;
    IF v_err NOT LIKE 'MARRIAGE_ORDINAL_CORRECTION_VERSION_MISMATCH%' THEN RAISE; END IF; END;
  BEGIN PERFORM red_ret_aegteskabsnummer(k1,2,'n',ctx); RAISE EXCEPTION 'ORDINAL_244_TEST_FAILED: ikke nødvendig';
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT;
    IF v_err NOT LIKE 'MARRIAGE_ORDINAL_CORRECTION_NOT_NEEDED%' THEN RAISE; END IF; END;
  IF jsonb_array_length(red_marriage_ordinal_correction_input(-24421)->'rows')<>0 THEN
    RAISE EXCEPTION 'ORDINAL_244_TEST_FAILED: input efter';
  END IF;
  RESET ROLE;
  -- imellem: kilderne skjult (tilstanden er ny); genbinding: begge egnede med supersedes, derefter synlige igen
  IF (SELECT count(*) FROM public.public_family_sources(ARRAY[(m->>'f1')::bigint,(m->>'f2')::bigint]) x WHERE x.slags='aegteskab')<>0 THEN
    RAISE EXCEPTION 'ORDINAL_244_TEST_FAILED: hul';
  END IF;
  n:=pg_temp.f244_bind(-24421,v_actor);
  IF n<>2 OR (SELECT count(*) FROM private.interpretation_promotion WHERE target_type='family'
               AND interpretation_id IN (SELECT id FROM private.interpretation_current WHERE interpretation_key IN (k1,k2))
               AND evidence->>'supersedes_promotion_id' IS NOT NULL)<>2
     OR (SELECT count(*) FROM public.public_family_sources(ARRAY[(m->>'f1')::bigint,(m->>'f2')::bigint]) x WHERE x.slags='aegteskab')<>2 THEN
    RAISE EXCEPTION 'ORDINAL_244_TEST_FAILED: genbinding';
  END IF;
  IF pg_temp.f244_bind(-24421,v_actor)<>0 THEN RAISE EXCEPTION 'ORDINAL_244_TEST_FAILED: genkørsel'; END IF;
  -- familiekorroboration (spec §7.5): vejen er stadig lukket for den rettede ægtefælle. Som ejer (funktionen er
  -- REVOKE'et fra authenticated), med gyldig basis, så proveniens-tjekket (a) nås. Fixturens origin_ref er tilfældig,
  -- så (a) afviser også før rettelsen; testen viser kun »stadig lukket« og skelner på partens origin.
  BEGIN
    PERFORM private.check_family_corroboration((m->>'s1')::uuid,-24422,0,'accepted',
      '{"basis":"family_corroboration","method":"family-corroboration-v1"}'::jsonb);
    RAISE EXCEPTION 'ORDINAL_244_TEST_FAILED: korroboration';
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT;
    IF v_err NOT LIKE 'FAMILY_CORROBORATION_PROVENANCE_INVALID%' THEN RAISE; END IF;
  END;
  RAISE NOTICE 'OK: rettelse og genbinding';
END $ret$;
ROLLBACK;

-- Rettelsesskriverens afvisninger uden for hovedvejen: familie forkert/NULL, bogen modsiger, ikke bundet, rolle.
BEGIN;
\ir fixtures/relation-5b.sql
\ir fixtures/relation-2a.sql
\ir fixtures/marriage-ordinal-244.sql
DO $ret_fejl$
DECLARE v_actor uuid:='11000000-0000-0000-0000-000000024431'; s jsonb; m jsonb; v_err text; k uuid; src bigint; i int;
  ctx jsonb:=jsonb_build_object('basis','human_sheet','sheet_sha256',repeat('a',64),'rows_sha256',repeat('b',64),'line','1');
  v_case text; v_expect text;
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  INSERT INTO person(id,levende,privat,status) SELECT g,false,false,'244' FROM generate_series(-24459,-24431) g;
  FOR i,v_case,v_expect IN SELECT * FROM (VALUES (1,'familie_forkert','MARRIAGE_ORDINAL_CORRECTION_FAMILY_MISMATCH'),
      (2,'familie_null','MARRIAGE_ORDINAL_CORRECTION_FAMILY_MISMATCH'),(3,'bog','MARRIAGE_ORDINAL_CORRECTION_BOOK_MISMATCH'),
      (4,'ikke_bundet','MARRIAGE_ORDINAL_CORRECTION_NOT_BOUND'),(5,'rolle','EVIDENCE_ROLE_FORBIDDEN')) x(i,c,e) LOOP
    src:=-24430-i;
    s:=pg_temp.f5b_source(src);
    IF v_case='bog' THEN
      m:=pg_temp.f244_post(src,s,'F-'||i,-24430-3*i,-24431-3*i,-24432-3*i,v_actor,
           'Gift 2° m. Bo Beta (søn af Ole Oma) f. 1800.','Gift 2° m. Bo Beta f. 1800.');
    ELSE
      m:=pg_temp.f244_post(src,s,'F-'||i,-24430-3*i,-24431-3*i,-24432-3*i,v_actor);
    END IF;
    k:=(m->'c1'->>'key')::uuid;
    SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
    IF v_case<>'ikke_bundet' AND pg_temp.f244_decide_and_bind(src,v_actor)<>2 THEN
      RAISE EXCEPTION 'ORDINAL_244_TEST_FAILED: % fixture',v_case;
    END IF;
    IF v_case='familie_forkert' THEN
      UPDATE family_member SET ordinal=3 WHERE family_id=(m->>'f1')::bigint AND person_id=-24430-3*i AND rolle='partner';
    ELSIF v_case='familie_null' THEN
      UPDATE family_member SET ordinal=NULL WHERE family_id=(m->>'f1')::bigint AND person_id=-24430-3*i AND rolle='partner';
    END IF;
    PERFORM set_config('request.jwt.claim.sub',CASE WHEN v_case='rolle' THEN '' ELSE v_actor::text END,true);
    SET LOCAL ROLE authenticated;
    BEGIN
      PERFORM red_ret_aegteskabsnummer(k,1,'n',ctx);
      RAISE EXCEPTION 'ORDINAL_244_TEST_FAILED: % godtaget',v_case;
    EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT;
      IF v_err NOT LIKE v_expect||'%' THEN RAISE EXCEPTION 'ORDINAL_244_TEST_FAILED: % gav %',v_case,v_err; END IF;
    END;
    RESET ROLE;
  END LOOP;
  RAISE NOTICE 'OK: rettelsens afvisninger';
END $ret_fejl$;
ROLLBACK;

-- Rettigheder og origin-constraint (spec §7.1-§7.3, §9.1). Tilføj-kun testes i $ret$ med rigtige rækker.
BEGIN;
DO $ret_adgang$
DECLARE r text; f text; v_err text;
BEGIN
  FOREACH f IN ARRAY ARRAY['public.red_ret_aegteskabsnummer(uuid,integer,text,jsonb)','public.red_marriage_ordinal_correction_input(bigint)'] LOOP
    IF has_function_privilege('anon',f,'EXECUTE') OR has_function_privilege('service_role',f,'EXECUTE')
       OR NOT has_function_privilege('authenticated',f,'EXECUTE') THEN
      RAISE EXCEPTION 'ORDINAL_244_TEST_FAILED: rettigheder %',f;
    END IF;
  END LOOP;
  FOREACH r IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
    IF has_function_privilege(r,'private.marriage_ordinal_correction_input(bigint)','EXECUTE')
       OR has_function_privilege(r,'private.relation_book_ordinal(text)','EXECUTE')
       OR has_table_privilege(r,'private.marriage_ordinal_correction','SELECT,INSERT,UPDATE,DELETE') THEN
      RAISE EXCEPTION 'ORDINAL_244_TEST_FAILED: privat adgang %',r;
    END IF;
  END LOOP;
  BEGIN UPDATE private.marriage_ordinal_correction SET family_id=family_id; 
  EXCEPTION WHEN OTHERS THEN RAISE EXCEPTION 'ORDINAL_244_TEST_FAILED: tom UPDATE fejlede';
  END;
  -- origin-constraint: en ukendt oprindelse afvises
  IF pg_get_constraintdef((SELECT oid FROM pg_constraint WHERE conname='interpretation_party_origin_check'
       AND conrelid='private.interpretation_party'::regclass)) NOT LIKE '%ordinal_correction%' THEN
    RAISE EXCEPTION 'ORDINAL_244_TEST_FAILED: constraint';
  END IF;
  RAISE NOTICE 'OK: adgang og constraint';
END $ret_adgang$;
ROLLBACK;
