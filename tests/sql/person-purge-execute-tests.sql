-- Task 8b. Hver gruppe køres i egen databasekopi. Ingen rækkeindhold i output.
CREATE FUNCTION pg_temp.purge_assert(p_ok boolean,p_test text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_ok IS DISTINCT FROM true THEN RAISE EXCEPTION 'TEST_FAILED %',p_test; END IF; END $$;
CREATE FUNCTION pg_temp.purge_afvis(p_sql text,p_error text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_ok boolean:=false;
BEGIN
  BEGIN EXECUTE p_sql;
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM NOT LIKE p_error||'%' THEN RAISE; END IF;
    v_ok:=true;
  END;
  PERFORM pg_temp.purge_assert(v_ok,p_error);
END $$;
SELECT set_config('request.jwt.claim.sub','a2a00000-0000-4000-8000-00000000a001',false) \g /dev/null

\if :g_purge
-- Tællerens egne før-mængder: identitet/medlemskab findes ikke længere efter COMMIT.
SELECT coalesce((SELECT jsonb_agg(source_persona_id) FROM private.source_persona_identity
  WHERE canonical_person_id=purge_test.id('P') AND decision_status='accepted'),'[]'::jsonb) AS purge_count_personas,
  coalesce((SELECT jsonb_agg(DISTINCT family_id) FROM public.family_member
    WHERE person_id=purge_test.id('P')),'[]'::jsonb) AS purge_count_families \gset
-- Den uafhængige facitliste, suppleret med de NYE rækker som fixturen dokumenterer.
-- Dette er undtagelse 1 (facit), aldrig plan/manifest; undtagelse 2 er naboernes visning_*.
CREATE TEMP TABLE purge_facit AS SELECT tabel,pk FROM purge_test.forventet;
INSERT INTO purge_facit
SELECT 'private.source_persona_identity',jsonb_build_object('source_persona_id',purge_test.u(x))
FROM (VALUES('X1'),('X2')) v(x);
INSERT INTO purge_facit
SELECT 'private.source_persona_identity_event',jsonb_build_object('id',private.content_uuid('identity-event',
  jsonb_build_object('source_persona_id',purge_test.u(x),'version',n)))
FROM (VALUES('X1',2),('X2',4)) v(x,n);
INSERT INTO purge_facit
SELECT 'private.person_purge_udbakke',jsonb_build_object('bucket',m.bucket,'sti',m.storage_path)
FROM public.media m WHERE m.id=purge_test.id('medie_eksklusiv')
UNION SELECT 'private.person_purge_udbakke',jsonb_build_object('bucket',m.bucket,'sti',v.storage_path)
FROM public.media_variant v JOIN public.media m ON m.id=v.media_id WHERE m.id=purge_test.id('medie_eksklusiv');
-- R35: L7's guard_identity_mutation_snapshot tæller op ved enhver identitetsmutation.
-- Tabellen rummer ingen persondata. Kun singleton-rækken må ændres; generation +1 og
-- de navngivne metadata guard_transaction_id/guard_backend_pid efterprøves særskilt.
INSERT INTO purge_facit VALUES('private.identity_mutation_generation','{"singleton":true}');
CREATE TEMP TABLE purge_generation_before AS SELECT * FROM private.identity_mutation_generation;
CREATE FUNCTION pg_temp.purge_hash() RETURNS TABLE(tabel text,sha256 text) LANGUAGE plpgsql AS $$
DECLARE r record; v_sql text; v_strip text;
BEGIN
  FOR r IN SELECT n.nspname,c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname IN ('public','private') AND c.relkind IN ('r','p') AND NOT c.relispartition
    ORDER BY n.nspname COLLATE "C",c.relname COLLATE "C" LOOP
    tabel:=CASE WHEN r.nspname='public' THEN r.relname ELSE r.nspname||'.'||r.relname END;
    v_strip:='ARRAY[]::text[]';
    IF tabel='person' THEN
      SELECT 'ARRAY['||coalesce(string_agg(quote_literal(attname),','),'')||']::text[]' INTO v_strip
      FROM pg_attribute WHERE attrelid='public.person'::regclass AND attname LIKE 'visning\_%' ESCAPE '\' AND NOT attisdropped;
    END IF;
    v_sql:=format($q$SELECT encode(extensions.digest(convert_to(coalesce(string_agg(j::text,E'\n' ORDER BY j::text COLLATE "C"),''),'UTF8'),'sha256'),'hex')
      FROM (SELECT CASE WHEN %L='person' AND t.id=ANY($2) THEN to_jsonb(t)-%s ELSE to_jsonb(t) END j
      FROM %I.%I t WHERE NOT EXISTS (SELECT 1 FROM pg_temp.purge_facit f WHERE f.tabel=$1 AND to_jsonb(t) @> f.pk)) s$q$,
      tabel,v_strip,r.nspname,r.relname);
    -- t.id findes ikke på alle tabeller: byg CASE kun for person.
    IF tabel<>'person' THEN
      v_sql:=format($q$SELECT encode(extensions.digest(convert_to(coalesce(string_agg(j::text,E'\n' ORDER BY j::text COLLATE "C"),''),'UTF8'),'sha256'),'hex')
        FROM (SELECT to_jsonb(t) j FROM %I.%I t WHERE NOT EXISTS (
          SELECT 1 FROM pg_temp.purge_facit f WHERE f.tabel=$1 AND to_jsonb(t) @> f.pk)) s$q$,r.nspname,r.relname);
    END IF;
    EXECUTE v_sql INTO sha256 USING tabel,ARRAY[purge_test.id('nabo'),purge_test.id('aegtefaelle'),purge_test.id('anden_partner'),purge_test.id('barn')];
    RETURN NEXT;
  END LOOP;
END $$;
CREATE TEMP TABLE purge_updates(tabel text,pk jsonb,foer jsonb);
DO $t$
DECLARE r record; v_row jsonb;
BEGIN
  FOR r IN SELECT * FROM purge_test.forventet WHERE handling IN ('nulstil','loesn') LOOP
    EXECUTE format('SELECT to_jsonb(t) FROM public.%I t WHERE to_jsonb(t) @> $1',r.tabel) INTO STRICT v_row USING r.pk;
    INSERT INTO purge_updates VALUES(r.tabel,r.pk,v_row);
  END LOOP;
END $t$;
CREATE TEMP TABLE purge_before AS SELECT * FROM pg_temp.purge_hash();
CREATE TEMP TABLE purge_preview AS SELECT public.red_slet_person_helt_preview(purge_test.id('P')) j;
CREATE TEMP TABLE purge_history AS SELECT 'change_set' tabel,id FROM public.change_set
UNION ALL SELECT 'change_event',id FROM public.change_event;
CREATE TEMP TABLE purge_y AS SELECT * FROM private.source_persona_identity_event
WHERE source_persona_id=purge_test.u('Y') AND canonical_person_id IS DISTINCT FROM purge_test.id('P');
CREATE TEMP TABLE purge_q6 AS SELECT private.relation_binding_state(interpretation_id) state,interpretation_id
FROM private.interpretation_promotion WHERE id=purge_test.u('prom_egen_fam');
-- L6b: en testkrog på L7-guardens generation-UPDATE ser sætlåsens xmax,
-- altså lige efter L6b og før de senere låsetrin og enhver change_set-skrivning.
-- pg_locks viser normalt IKKE uncontended tuple locks; xmax gør testen deterministisk uden dblink/timing.
CREATE TEMP TABLE purge_lock_probe(n int);
CREATE FUNCTION pg_temp.purge_lock_probe() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_n int;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_temp.purge_lock_probe) THEN
    SELECT count(*) INTO v_n FROM public.change_set cs JOIN purge_test.forventet f
      ON f.tabel='change_set' AND f.pk=jsonb_build_object('id',cs.id)
      WHERE cs.reverterer_id IS NULL AND cs.subjekt_type IS DISTINCT FROM 'person';
    PERFORM pg_temp.purge_assert(v_n>0,'purge_l6b_fixture_S53');
    PERFORM pg_temp.purge_assert(NOT EXISTS (
      SELECT 1 FROM public.change_set cs JOIN purge_test.forventet f
        ON f.tabel='change_set' AND f.pk=jsonb_build_object('id',cs.id)
      WHERE cs.xmax::text<>pg_current_xact_id()::text),'purge_l6b_laaser_saet');
    INSERT INTO pg_temp.purge_lock_probe VALUES(v_n);
  END IF;
  RETURN NEW;
END $$;
CREATE FUNCTION pg_temp.purge_media_lock_probe() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_temp.purge_lock_probe WHERE n=-11) THEN
    PERFORM pg_temp.purge_assert(EXISTS(SELECT 1 FROM public.media
      WHERE id=purge_test.id('medie_eksklusiv') AND xmax::text=pg_current_xact_id()::text),'purge_l11b_laaser_medier');
    INSERT INTO pg_temp.purge_lock_probe VALUES(-11);
  END IF;
  RETURN NEW;
END $$;
BEGIN;
CREATE TRIGGER purge_media_lock_probe BEFORE INSERT ON private.person_purge_manifest
FOR EACH ROW EXECUTE FUNCTION pg_temp.purge_media_lock_probe();
CREATE TRIGGER purge_lock_probe BEFORE UPDATE ON private.identity_mutation_generation
FOR EACH ROW EXECUTE FUNCTION pg_temp.purge_lock_probe();
CREATE TEMP TABLE purge_result(j jsonb);
DO $t$
DECLARE v_hash text:=(SELECT j->>'sha256' FROM purge_preview); v_p bigint:=purge_test.id('P'); v_result jsonb;
BEGIN
  SET LOCAL ROLE authenticated;
  v_result:=public.red_slet_person_helt(v_p,v_hash);
  RESET ROLE;
  INSERT INTO purge_result VALUES(v_result);
END $t$;
DO $t$ BEGIN
  PERFORM pg_temp.purge_assert((SELECT guard_transaction_id=pg_current_xact_id() AND guard_backend_pid=pg_backend_pid()
    FROM private.identity_mutation_generation WHERE singleton),'purge_generation_metadata_R35');
END $t$;
DROP TRIGGER purge_lock_probe ON private.identity_mutation_generation;
DROP TRIGGER purge_media_lock_probe ON private.person_purge_manifest;
COMMIT;
DO $t$
DECLARE v text; r record; v_exists boolean; v_n int; v_efter jsonb; v_cols text[];
BEGIN
  PERFORM pg_temp.purge_assert((SELECT count(*) FROM purge_lock_probe WHERE n<>-11)=1,'purge_l6b_laaser_saet');
  SELECT prosrc INTO v FROM pg_proc WHERE oid='public.red_slet_person_helt(bigint,text)'::regprocedure;
  PERFORM pg_temp.purge_assert(strpos(v,'-- L6')<strpos(v,'-- L6b') AND strpos(v,'-- L6b')<strpos(v,'-- L7')
    AND position('FROM public.change_set' IN substring(v FROM strpos(v,'-- L6b') FOR strpos(v,'-- L7')-strpos(v,'-- L6b')))>0
    AND position('ORDER BY id FOR UPDATE' IN substring(v FROM strpos(v,'-- L6b') FOR strpos(v,'-- L7')-strpos(v,'-- L6b')))>0,
    'purge_l6b_orden');
  PERFORM pg_temp.purge_assert(EXISTS(SELECT 1 FROM purge_lock_probe WHERE n=-11),'purge_l11b_laaser_medier');
  PERFORM pg_temp.purge_assert(strpos(v,'-- L11')<strpos(v,'-- L11b') AND strpos(v,'-- L11b')<strpos(v,'-- L12')
    AND position('FROM public.media' IN substring(v FROM strpos(v,'-- L11b') FOR strpos(v,'-- L12')-strpos(v,'-- L11b')))>0
    AND position('ORDER BY id FOR UPDATE' IN substring(v FROM strpos(v,'-- L11b') FOR strpos(v,'-- L12')-strpos(v,'-- L11b')))>0
    AND position('NOT v_medier_nu <@ v_medier' IN v)>0,'purge_l11b_orden_og_drift');
  PERFORM pg_temp.purge_assert(NOT EXISTS(SELECT 1 FROM public.person WHERE id=purge_test.id('P')),'purge_count_nul_person');
  FOR r IN SELECT * FROM purge_test.forventet WHERE handling='slet' LOOP
    EXECUTE format('SELECT EXISTS(SELECT 1 FROM %s t WHERE to_jsonb(t) @> $1)',
      CASE WHEN r.tabel LIKE 'private.%' THEN r.tabel ELSE 'public.'||r.tabel END) INTO v_exists USING r.pk;
    PERFORM pg_temp.purge_assert(NOT v_exists,'purge_count_nul_facit_'||r.tabel);
  END LOOP;
  FOR r IN SELECT * FROM purge_updates LOOP
    EXECUTE format('SELECT to_jsonb(t) FROM public.%I t WHERE to_jsonb(t) @> $1',r.tabel) INTO STRICT v_efter USING r.pk;
    v_cols:=CASE r.tabel WHEN 'profiles' THEN ARRAY['reventlow_person_id'] WHEN 'haendelse' THEN ARRAY['fact_id','relation_id']
      WHEN 'story' THEN ARRAY['fact_id','relation_id','haendelse_id'] END;
    PERFORM pg_temp.purge_assert(v_cols IS NOT NULL AND r.foer-v_cols=v_efter-v_cols,'purge_andre_uaendrede_kolonner');
    PERFORM pg_temp.purge_assert(NOT EXISTS(SELECT 1 FROM unnest(v_cols) c WHERE v_efter->c IS DISTINCT FROM 'null'::jsonb),
      'purge_count_nul_nulstil_loesn');
  END LOOP;
  PERFORM pg_temp.purge_assert(NOT EXISTS(SELECT 1 FROM private.person_purge_manifest),'purge_manifest_tomt');
  PERFORM pg_temp.purge_assert((SELECT count(*) FROM private.identity_mutation_generation)=1
    AND (SELECT g.generation=b.generation+1 AND g.guard_transaction_id IS NOT NULL AND g.guard_backend_pid=pg_backend_pid()
      AND to_jsonb(g)-ARRAY['generation','guard_transaction_id','guard_backend_pid']=to_jsonb(b)-ARRAY['generation','guard_transaction_id','guard_backend_pid']
      FROM private.identity_mutation_generation g JOIN purge_generation_before b USING(singleton)),'purge_generation_R35');
  PERFORM pg_temp.purge_assert(NOT EXISTS(
    (SELECT * FROM purge_before EXCEPT SELECT * FROM pg_temp.purge_hash())
    UNION ALL (SELECT * FROM pg_temp.purge_hash() EXCEPT SELECT * FROM purge_before)),'purge_andre_uaendrede');
  PERFORM pg_temp.purge_assert(NOT EXISTS(
    (SELECT 'change_set',id FROM public.change_set UNION ALL SELECT 'change_event',id FROM public.change_event)
    EXCEPT SELECT * FROM purge_history),'purge_ingen_ny_historik');
  PERFORM pg_temp.purge_assert(NOT EXISTS(
    (SELECT * FROM purge_y EXCEPT SELECT * FROM private.source_persona_identity_event)
    UNION ALL (SELECT * FROM private.source_persona_identity_event WHERE source_persona_id=purge_test.u('Y')
      EXCEPT SELECT * FROM purge_y)),'purge_andres_identitetsevent');
  SELECT count(*) INTO v_n FROM private.source_persona_identity i WHERE i.source_persona_id IN (purge_test.u('X1'),purge_test.u('X2'))
    AND i.canonical_person_id IS NULL AND i.decision_status='rejected' AND i.evidence='{"reason":"not_a_person"}'::jsonb
    AND i.version=CASE WHEN i.source_persona_id=purge_test.u('X1') THEN 2 ELSE 4 END
    AND (SELECT count(*) FROM private.source_persona_identity_event e WHERE e.source_persona_id=i.source_persona_id
      AND e.version=i.version AND e.evidence=i.evidence AND e.canonical_person_id IS NULL AND e.decision_status=i.decision_status)=1
    AND (SELECT count(*) FROM private.source_persona_identity_event e WHERE e.source_persona_id=i.source_persona_id)=1;
  PERFORM pg_temp.purge_assert(v_n=2,'purge_persona_ikke_en_person');
  PERFORM pg_temp.purge_assert(NOT EXISTS(SELECT 1 FROM private.interpretation_promotion WHERE id=purge_test.u('prom_egen_fam'))
    AND EXISTS(SELECT 1 FROM public.family WHERE id=purge_test.id('fam_keep'))
    AND (SELECT private.relation_binding_state(interpretation_id) IS NULL FROM purge_q6),'purge_q6_binding');
  -- Restlisten er rækkepræcis også for historik: K2 (andres note/narrativ), K3 (delt medie),
  -- K5 (bogtekst på bevaret families vielse). Andre events må ikke bære navnet.
  PERFORM pg_temp.purge_assert(NOT EXISTS(SELECT 1 FROM public.change_event e
    WHERE (position('Testperson Purge' IN coalesce(e.foer::text,''))>0 OR position('Testperson Purge' IN coalesce(e.efter::text,''))>0)
      AND NOT (
        (e.tabel IN ('note','narrative') AND NOT EXISTS(SELECT 1 FROM purge_test.forventet f
          WHERE f.tabel=e.tabel AND f.pk=e.row_pk AND f.handling='slet'))
        OR (e.tabel='media' AND e.row_pk=jsonb_build_object('id',purge_test.id('medie_delt')))
        OR (e.tabel='assertion' AND EXISTS(SELECT 1 FROM public.assertion a JOIN public.fact f ON a.target_type='fact' AND a.target_id=f.id
          WHERE e.row_pk=jsonb_build_object('id',a.id) AND f.subjekt_type='family' AND f.faktatype='vielse'
            AND f.subjekt_id=purge_test.id('fam_keep')))
        OR (e.tabel='citation' AND EXISTS(SELECT 1 FROM public.citation c JOIN public.assertion a ON a.id=c.assertion_id
          JOIN public.fact f ON a.target_type='fact' AND a.target_id=f.id
          WHERE e.row_pk=jsonb_build_object('id',c.id) AND f.subjekt_type='family' AND f.faktatype='vielse'
            AND f.subjekt_id=purge_test.id('fam_keep')))
      )),'purge_historik_navn_vaek_events');
  PERFORM pg_temp.purge_assert(EXISTS(SELECT 1 FROM public.media WHERE id=purge_test.id('medie_delt'))
    AND EXISTS(SELECT 1 FROM public.change_set WHERE id=purge_test.id('saet_medie_delt')),'purge_delt_medie');
  PERFORM pg_temp.purge_assert((SELECT j->>'slettet' FROM purge_result)=purge_test.id('P')::text
    AND (SELECT (j->>'personas_afvist')::int FROM purge_result)=2
    AND (SELECT (j->>'storage_antal')::int FROM purge_result)=(SELECT count(*) FROM private.person_purge_udbakke),'purge_retur');
END $t$;
\echo OK purge_count_nul_facit
\echo OK purge_manifest_tomt
\echo OK purge_andre_uaendrede
\echo OK purge_ingen_ny_historik
\echo OK purge_andres_identitetsevent
\echo OK purge_persona_ikke_en_person
\echo OK purge_q6_binding
\echo OK purge_delt_medie
\echo OK purge_retur
\echo OK purge_l6b_laaser_saet
\echo OK purge_l11b_laaser_medier
\echo OK purge_l11b_orden_og_drift
-- Alle polymorfe skrivere prøves mod den RIGTIGT slettede person/familie.
DO $t$
DECLARE r record; v_narr bigint; v_fact bigint;
BEGIN
  SELECT min(id) INTO v_narr FROM public.narrative;
  SELECT min(id) INTO v_fact FROM public.fact;
  FOR r IN SELECT * FROM (VALUES ('person',purge_test.id('P')),('family',purge_test.id('fam_del'))) x(typ,id) LOOP
    PERFORM pg_temp.purge_afvis(format('SELECT public.red_upsert_fakta(%L,%s,%L,%L)',r.typ,r.id,'test','test'),'POLYMORF_SUBJEKT_FINDES_IKKE');
    PERFORM pg_temp.purge_afvis(format('INSERT INTO public.note(target_type,target_id) VALUES(%L,%s)',r.typ,r.id),'POLYMORF_SUBJEKT_FINDES_IKKE');
    PERFORM pg_temp.purge_afvis(format('INSERT INTO public.story(subjekt_type,subjekt_id,tekst) VALUES(%L,%s,%L)',r.typ,r.id,'test'),'POLYMORF_SUBJEKT_FINDES_IKKE');
    PERFORM pg_temp.purge_afvis(format('INSERT INTO public.suggestion(subjekt_type,subjekt_id) VALUES(%L,%s)',r.typ,r.id),'POLYMORF_SUBJEKT_FINDES_IKKE');
    PERFORM pg_temp.purge_afvis(format('INSERT INTO public.haendelse(subjekt_type,subjekt_id,narrative_id,noegle,klausul) VALUES(%L,%s,%s,%L,%L)',r.typ,r.id,v_narr,'test','test'),'POLYMORF_SUBJEKT_FINDES_IKKE');
    PERFORM pg_temp.purge_afvis(format('INSERT INTO public.assertion(target_type,target_id,objekt_type,objekt_id) VALUES(%L,%s,%L,%s)','fact',v_fact,r.typ,r.id),'POLYMORF_SUBJEKT_FINDES_IKKE');
  END LOOP;
  PERFORM pg_temp.purge_afvis(format('INSERT INTO public.assertion(target_type,target_id) VALUES(%L,%s)','fact',purge_test.id('fakta_titel')),'POLYMORF_SUBJEKT_FINDES_IKKE');
END $t$;
\echo OK purge_eksistensvagt_efter_sletning
-- Fortryd må fejle lukket ELLER lykkes uden nogen genskabelse af slettede rækker.
DO $t$
DECLARE v_cs bigint; v_force boolean; r record; v_exists boolean;
BEGIN
  FOREACH v_cs IN ARRAY ARRAY[purge_test.id('faelles_saet'),purge_test.id('saet_tidligere_slettet')] LOOP
    FOREACH v_force IN ARRAY ARRAY[false,true] LOOP
      BEGIN
        PERFORM purge_test.nyt();
        PERFORM public.red_fortryd_change_set(v_cs,v_force);
        FOR r IN SELECT * FROM purge_test.forventet WHERE handling='slet' LOOP
          EXECUTE format('SELECT EXISTS(SELECT 1 FROM %s t WHERE to_jsonb(t) @> $1)',
            CASE WHEN r.tabel LIKE 'private.%' THEN r.tabel ELSE 'public.'||r.tabel END) INTO v_exists USING r.pk;
          PERFORM pg_temp.purge_assert(NOT v_exists,'purge_fortryd_bevaret');
        END LOOP;
        RAISE SQLSTATE 'P9001'; -- rollback også en vellykket fortrydelse
      EXCEPTION WHEN SQLSTATE 'P9001' THEN NULL;
        WHEN raise_exception THEN
          IF SQLERRM LIKE 'TEST_FAILED%' THEN RAISE; END IF;
        WHEN integrity_constraint_violation THEN NULL; -- en lukket inverse ruller subtransaktionen tilbage
      END;
    END LOOP;
  END LOOP;
END $t$;
\echo OK purge_fortryd_bevaret
SELECT purge_test.id('P') AS pid \gset
-- Målernes normale output undertrykkes; fejl afbryder stadig testen.
\set purge_assert_nul true
\o /dev/null
\ir person-purge-count.sql
\set mode fixture
\set navn 'Testperson Purge'
\ir person-purge-rest.sql
\o
\echo OK purge_count_nul
\echo OK purge_rest_kun_tilladt
\echo OK purge_historik_navn_vaek
\endif

\if :g_purge_ekstra
BEGIN;
DO $t$
DECLARE v_hash text;
BEGIN
  SELECT public.red_slet_person_helt_preview(purge_test.id('P'))->>'sha256' INTO v_hash;
  PERFORM pg_temp.purge_afvis(format('SELECT public.red_slet_person_helt(%s,%L)',purge_test.id('P'),repeat('0',64)),'PURGE_PREVIEW_AENDRET');
  INSERT INTO public.note(target_type,target_id,indhold) VALUES('person',purge_test.id('P'),'hash probe');
  PERFORM pg_temp.purge_afvis(format('SELECT public.red_slet_person_helt(%s,%L)',purge_test.id('P'),v_hash),'PURGE_PREVIEW_AENDRET');
  PERFORM set_config('app.change_set_id','123',true);
  PERFORM pg_temp.purge_afvis(format('SELECT public.red_slet_person_helt(%s,%L)',purge_test.id('P'),v_hash),'PURGE_FREMMED_CHANGE_SET');
  PERFORM purge_test.nyt();
  PERFORM pg_temp.purge_afvis('SELECT public.red_slet_person_helt(9223372036854775807,NULL)','PURGE_FINDES_IKKE');
  PERFORM set_config('request.jwt.claim.sub','',true);
  PERFORM set_config('app.change_set_id','123',true);
  PERFORM pg_temp.purge_afvis(format('SELECT public.red_slet_person_helt(%s,NULL)',purge_test.id('P')),'Kun redaktion');
  PERFORM pg_temp.purge_afvis('SELECT public.red_slet_person_helt(9223372036854775807,NULL)','Kun redaktion');
END $t$;
ROLLBACK;
\echo OK purge_hash_aendret
\echo OK purge_fremmed_saet
\echo OK purge_findes_ikke
\echo OK purge_rollegate_foerst
BEGIN;
INSERT INTO public.note(target_type,target_id,indhold) VALUES('person',purge_test.id('tredje'),
  '[[person:'||purge_test.id('P')||'|Testperson Purge]]');
DO $t$
BEGIN
  PERFORM pg_temp.purge_afvis(format('SELECT public.red_slet_person_helt(%s,%L)',purge_test.id('P'),
    public.red_slet_person_helt_preview(purge_test.id('P'))->>'sha256'),'PURGE_BLOKERET: link_i_tekst');
END $t$;
ROLLBACK;
\echo OK purge_blokeret
-- Et sent fact på P indføres efter fact-fasen, men FØR personens DELETE.
-- En anden session ville vente på personlåsen; testkrogen kører bevidst i samme session.
BEGIN;
CREATE FUNCTION pg_temp.purge_rest_probe() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.id=purge_test.id('P') THEN
    INSERT INTO public.fact(subjekt_type,subjekt_id,faktatype) VALUES('person',OLD.id,'purge_rest_probe');
  END IF;
  RETURN OLD;
END $$;
CREATE TRIGGER purge_rest_probe BEFORE DELETE ON public.person FOR EACH ROW EXECUTE FUNCTION pg_temp.purge_rest_probe();
DO $t$
BEGIN
  PERFORM pg_temp.purge_afvis(format('SELECT public.red_slet_person_helt(%s,%L)',purge_test.id('P'),
    public.red_slet_person_helt_preview(purge_test.id('P'))->>'sha256'),'PURGE_REST:');
  PERFORM pg_temp.purge_assert(EXISTS(SELECT 1 FROM public.person WHERE id=purge_test.id('P'))
    AND NOT EXISTS(SELECT 1 FROM private.person_purge_manifest),'purge_slutkontrol_atomisk');
END $t$;
ROLLBACK;
\echo OK purge_slutkontrol
-- Kun 7b kan fange denne række: vagten har kontrolleret fact, og målet lever endnu
-- ved INSERT. Efter fact/person/historik er slettet, kan EFTER-plan(P) ikke nå noten.
-- Mutation uden 7b: RPC'en lykkes; purge_afvis nedenfor fejler. Ingen trigger deaktiveres.
BEGIN;
CREATE FUNCTION pg_temp.purge_7b_probe() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.id=purge_test.id('fakta_titel') THEN
    INSERT INTO public.note(target_type,target_id,indhold) VALUES('fact',OLD.id,'sen note uden person-token');
  END IF;
  RETURN OLD;
END $$;
CREATE TRIGGER zz_purge_7b_probe BEFORE DELETE ON public.fact
FOR EACH ROW EXECUTE FUNCTION pg_temp.purge_7b_probe();
-- Sidste DML-statement: P/fact/historik er slettet; wrapperen kan ikke finde noten.
CREATE FUNCTION pg_temp.purge_7b_unreachable() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  PERFORM pg_temp.purge_assert(NOT EXISTS(SELECT 1 FROM public.person WHERE id=purge_test.id('P'))
    AND NOT EXISTS(SELECT 1 FROM public.fact WHERE id=purge_test.id('fakta_titel'))
    AND EXISTS(SELECT 1 FROM public.note WHERE target_type='fact' AND target_id=purge_test.id('fakta_titel')),
    'purge_7b_sen_note');
  PERFORM pg_temp.purge_assert(NOT EXISTS(SELECT 1 FROM private.person_purge_plan(purge_test.id('P')) p
    JOIN public.note n ON p.tabel='note' AND p.pk=jsonb_build_object('id',n.id)
    WHERE n.target_type='fact' AND n.target_id=purge_test.id('fakta_titel')),'purge_7b_plan_kan_ikke_finde_note');
  RETURN NULL;
END $$;
CREATE TRIGGER purge_7b_unreachable AFTER DELETE ON public.change_set
FOR EACH STATEMENT EXECUTE FUNCTION pg_temp.purge_7b_unreachable();
DO $t$
BEGIN
  PERFORM pg_temp.purge_assert(EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.fact'::regclass
    AND tgname='trg_fact_evidence_delete' AND tgname::text COLLATE "C" < 'zz_purge_7b_probe'), 'purge_7b_triggerorden');
  PERFORM pg_temp.purge_afvis(format('SELECT public.red_slet_person_helt(%s,%L)',purge_test.id('P'),
    public.red_slet_person_helt_preview(purge_test.id('P'))->>'sha256'),'PURGE_REST: S18');
  PERFORM pg_temp.purge_assert(EXISTS(SELECT 1 FROM public.person WHERE id=purge_test.id('P'))
    AND NOT EXISTS(SELECT 1 FROM public.note WHERE indhold='sen note uden person-token')
    AND NOT EXISTS(SELECT 1 FROM private.person_purge_manifest),'purge_7b_atomisk');
END $t$;
ROLLBACK;
\echo OK purge_slutkontrol_7b_sen_note

-- Media-id'er er også med i 7b's slettede mål. Alle tre FK-løse tabeller prøves.
BEGIN;
CREATE TEMP TABLE purge_media_probe_kind(kind text);
CREATE FUNCTION pg_temp.purge_7b_media_probe() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_kind text:=(SELECT kind FROM pg_temp.purge_media_probe_kind);
BEGIN
  IF OLD.id=purge_test.id('medie_eksklusiv') THEN
    IF v_kind='note' THEN
      INSERT INTO public.note(target_type,target_id,indhold) VALUES('media',OLD.id,'sen media-note');
    ELSIF v_kind='relation' THEN
      INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle)
        VALUES('person',purge_test.id('nabo'),'media',OLD.id,'test');
    ELSE
      INSERT INTO public.entity_description(subjekt_type,subjekt_id,kind,tekst)
        VALUES('media',OLD.id,'caption','sen mediebeskrivelse');
    END IF;
  END IF;
  RETURN OLD;
END $$;
CREATE TRIGGER purge_7b_media_probe BEFORE DELETE ON public.media
FOR EACH ROW EXECUTE FUNCTION pg_temp.purge_7b_media_probe();
DO $t$
DECLARE v_kind text;
BEGIN
  FOREACH v_kind IN ARRAY ARRAY['note','relation','entity_description'] LOOP
    DELETE FROM purge_media_probe_kind;
    INSERT INTO purge_media_probe_kind VALUES(v_kind);
    PERFORM pg_temp.purge_afvis(format('SELECT public.red_slet_person_helt(%s,%L)',purge_test.id('P'),
      public.red_slet_person_helt_preview(purge_test.id('P'))->>'sha256'),'PURGE_REST:');
    PERFORM pg_temp.purge_assert(EXISTS(SELECT 1 FROM public.media WHERE id=purge_test.id('medie_eksklusiv'))
      AND NOT EXISTS(SELECT 1 FROM private.person_purge_manifest),'purge_7b_media_atomisk');
  END LOOP;
END $t$;
ROLLBACK;
\echo OK purge_slutkontrol_7b_media_ender

-- Story-link indføres efter L13, uden polymorf ende til P. Kun EFTER-planens blokér fanger det.
BEGIN;
CREATE FUNCTION pg_temp.purge_late_story_probe() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.id=purge_test.id('P') THEN
    INSERT INTO public.story(subjekt_type,subjekt_id,tekst)
      VALUES('person',purge_test.id('nabo'),'[[person:'||OLD.id||'|sen reference]]');
  END IF;
  RETURN OLD;
END $$;
CREATE TRIGGER purge_late_story_probe BEFORE DELETE ON public.person
FOR EACH ROW EXECUTE FUNCTION pg_temp.purge_late_story_probe();
DO $t$
BEGIN
  PERFORM pg_temp.purge_afvis(format('SELECT public.red_slet_person_helt(%s,%L)',purge_test.id('P'),
    public.red_slet_person_helt_preview(purge_test.id('P'))->>'sha256'),'PURGE_BLOKERET: link_i_tekst');
  PERFORM pg_temp.purge_assert(EXISTS(SELECT 1 FROM public.person WHERE id=purge_test.id('P'))
    AND NOT EXISTS(SELECT 1 FROM public.story WHERE tekst LIKE '%sen reference%')
    AND NOT EXISTS(SELECT 1 FROM private.person_purge_manifest),'purge_sent_story_link_atomisk');
END $t$;
ROLLBACK;
\echo OK purge_sent_story_link_blokerer
\endif
