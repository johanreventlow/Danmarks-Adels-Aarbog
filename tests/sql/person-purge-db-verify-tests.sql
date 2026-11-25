-- Task 10: egen kopi af purge-fixturen. Harness leverer de uændrede DO-blokke fra db-verify.sql.
-- Kun disse nye blokke køres her (den fulde disposable-runner køres separat af DB-CI).
-- Direkte kørsel: -v gruppe=db_verify -v purge_verify_sql="$(sed -n
-- '/^-- BEGIN PERSON PURGE TASK 10 CHECKS$/,/^-- END PERSON PURGE TASK 10 CHECKS$/p' db-verify.sql)".
\if :{?purge_verify_sql}
\else
  \echo 'PURGE_TEST_FEJL: purge_verify_sql mangler'
  SELECT 1/0 AS purge_verify_sql_mangler;
\endif
CREATE TEMP TABLE purge_verify_checks(navn text PRIMARY KEY,sql text NOT NULL);
INSERT INTO purge_verify_checks(navn,sql)
SELECT m[2],m[1] FROM regexp_matches(:'purge_verify_sql',
  '(?s)(DO \$(purge_verify_[a-z_]+)\$.*?END \$\2\$;)', 'g') m;
DO $checks$
BEGIN
  IF (SELECT array_agg(navn ORDER BY navn COLLATE "C") FROM purge_verify_checks) IS DISTINCT FROM ARRAY[
    'purge_verify_allocators','purge_verify_book_tables','purge_verify_identity_writers',
    'purge_verify_inventory_hash','purge_verify_lock_order','purge_verify_manifest_empty',
    'purge_verify_manifest_writer','purge_verify_polymorf'] THEN
    RAISE EXCEPTION 'TEST_FAILED db_verify_check_inventory';
  END IF;
END $checks$;

CREATE FUNCTION pg_temp.verify_check(p_navn text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_sql text;
BEGIN
  SELECT sql INTO STRICT v_sql FROM pg_temp.purge_verify_checks WHERE navn=p_navn;
  EXECUTE v_sql;
END $$;
CREATE FUNCTION pg_temp.verify_negative(p_navn text,p_code text,p_mutation text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  -- Opsætning, DDL/DML-mutation OG assert i samme exception-subtransaktion.
  -- Forventet fejl ruller alt tilbage; ingen DISABLE TRIGGER/session_replication_role.
  BEGIN
    EXECUTE p_mutation;
    PERFORM pg_temp.verify_check(p_navn);
    RAISE EXCEPTION USING ERRCODE='ZX010',MESSAGE='TEST_FAILED db_verify_negative_missed: '||p_navn;
  EXCEPTION WHEN raise_exception THEN
    IF split_part(SQLERRM,':',1) IS DISTINCT FROM p_code THEN
      RAISE EXCEPTION 'TEST_FAILED db_verify_negative_wrong_code: % %',p_navn,SQLSTATE;
    END IF;
  END;
  -- Samme assert skal være grøn igen, når den forventede fejl har rullet mutationen tilbage.
  PERFORM pg_temp.verify_check(p_navn);
END $$;
CREATE FUNCTION pg_temp.verify_swap(p_definition text,p_left text,p_right text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN
  IF p_left IS NULL OR p_right IS NULL OR p_left=p_right
     OR strpos(p_definition,p_left)=0 OR strpos(p_definition,p_right)=0 THEN
    RAISE EXCEPTION 'TEST_FAILED db_verify_swap_fixture';
  END IF;
  RETURN replace(replace(replace(p_definition,p_left,'__purge_verify_swap__'),p_right,p_left),
    '__purge_verify_swap__',p_right);
END $$;

SELECT set_config('request.jwt.claim.sub','a2a00000-0000-4000-8000-00000000a001',false) \g /dev/null
-- RIGTIG red_slet_person_helt, som authenticated, med COMMIT så deferred triggere også gennemløbes.
BEGIN;
DO $purge$
DECLARE v_p bigint:=purge_test.id('P'); v_preview jsonb;
BEGIN
  PERFORM purge_test.nyt();
  v_preview:=public.red_slet_person_helt_preview(v_p);
  SET LOCAL ROLE authenticated;
  PERFORM public.red_slet_person_helt(v_p,v_preview->>'sha256');
  RESET ROLE;
  IF EXISTS(SELECT 1 FROM public.person WHERE id=v_p) THEN RAISE EXCEPTION 'TEST_FAILED db_verify_rigtig_purge'; END IF;
END $purge$;
COMMIT;
-- Grøn FØR negative tests. En helt tom manifesttabel og alle bevarede referencer kontrolleres.
DO $green$
DECLARE r record;
BEGIN
  FOR r IN SELECT navn FROM purge_verify_checks ORDER BY navn COLLATE "C" LOOP
    PERFORM pg_temp.verify_check(r.navn);
  END LOOP;
END $green$;
\echo OK db_verify_efter_rigtig_purge

BEGIN;
DO $negative$
DECLARE v_def text; v_mutation text;
BEGIN
  PERFORM pg_temp.verify_negative('purge_verify_manifest_empty','PURGE_MANIFEST_IKKE_TOMT',$mutation$
    INSERT INTO private.person_purge_manifest(xid,backend_pid,person_id,tabel,pk,grund)
    VALUES(pg_current_xact_id(),pg_backend_pid(),0,'person','{"id":0}','egen')
  $mutation$);
  v_def:=pg_get_functiondef('private.person_purge_tilladte_tabeller()'::regprocedure);
  v_mutation:=replace(v_def,'''private.relation_reopen''','''private.source_record''');
  IF v_mutation=v_def THEN RAISE EXCEPTION 'TEST_FAILED db_verify_book_fixture'; END IF;
  PERFORM pg_temp.verify_negative('purge_verify_book_tables','PURGE_TILLADELSESLISTE_BOGTABEL',v_mutation);
  -- En EKSTRA skriver i et andet skema er nok. Funktionen oprettes, men kaldes aldrig.
  PERFORM pg_temp.verify_negative('purge_verify_manifest_writer','PURGE_MANIFEST_SKRIVER',$mutation$
    DO $probe$ BEGIN
      CREATE SCHEMA purge_verify_probe;
      EXECUTE $ddl$CREATE FUNCTION purge_verify_probe.manifest_writer() RETURNS void LANGUAGE sql AS $body$
        INSERT INTO "private"."person_purge_manifest"(xid,backend_pid,person_id,tabel,pk,grund)
        VALUES(pg_current_xact_id(),pg_backend_pid(),0,'person','{"id":0}','egen');
      $body$ $ddl$;
    END $probe$
  $mutation$);
  v_def:=pg_get_functiondef('private.person_purge_inventar()'::regprocedure);
  v_mutation:=replace(v_def,'''S1''','''S1_probe''');
  IF v_mutation=v_def THEN RAISE EXCEPTION 'TEST_FAILED db_verify_hash_fixture'; END IF;
  PERFORM pg_temp.verify_negative('purge_verify_inventory_hash','PURGE_INVENTAR_HASH',v_mutation);
  v_def:=pg_get_functiondef('public.red_slet_person_helt(bigint,text)'::regprocedure);
  PERFORM pg_temp.verify_negative('purge_verify_identity_writers','IDENTITY_WRITER_LOCK_ORDER_DRIFT',
    pg_temp.verify_swap(v_def,'PERFORM pg_advisory_xact_lock(hashtext(''samme_som_mutation''));',
      'PERFORM private.lock_identity_people(v_people);'));
END $negative$;
\echo OK db_verify_manifest_ikke_tomt_negativ
\echo OK db_verify_tilladelsesliste_bogtabel_negativ
\echo OK db_verify_manifest_skriver_hele_kataloget_negativ
\echo OK db_verify_inventar_hash_negativ
\echo OK db_verify_identity_writer_lock_order_negativ

-- Lovlig forældreløs note: note indsættes MENS personen/familien findes, derefter slettes forælderen.
-- Person/family har bevidst ingen forælderhalvdel (Global Constraints). Ingen vagt omgås ved INSERT.
DO $orphan$
DECLARE v_type text;
BEGIN
  FOREACH v_type IN ARRAY ARRAY['person','family'] LOOP
    PERFORM pg_temp.verify_negative('purge_verify_polymorf','POLYMORF_SUBJEKT_FORAELDRELOES',format($mutation$
      DO $probe$ DECLARE v_id bigint; BEGIN
        PERFORM purge_test.nyt();
        INSERT INTO public.%I DEFAULT VALUES RETURNING id INTO v_id;
        INSERT INTO public.note(target_type,target_id,indhold) VALUES(%L,v_id,'Syntetisk');
        DELETE FROM public.%I WHERE id=v_id;
      END $probe$
    $mutation$,v_type,v_type,v_type));
  END LOOP;
END $orphan$;
\echo OK db_verify_foraeldreloes_note_person_family_negativ

-- Fact har en forælderhalvdel. En sen BEFORE DELETE-trigger efter vagten kan lovligt indsætte
-- en relation, mens fact stadig findes, og dermed reproducere Task 8b's 7b-situation uden at slå vagter fra.
CREATE FUNCTION pg_temp.verify_late_fact_relation() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_ARGV[0]='subjekt' THEN
    INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle)
      VALUES('fact',OLD.id,'person',purge_test.id('nabo'),'test');
  ELSE
    INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle)
      VALUES('person',purge_test.id('nabo'),'fact',OLD.id,'test');
  END IF;
  RETURN OLD;
END $$;
DO $ends$
DECLARE v_type text; v_end text;
BEGIN
  FOREACH v_type IN ARRAY ARRAY['fact','media'] LOOP
    FOREACH v_end IN ARRAY ARRAY['subjekt','objekt'] LOOP
      PERFORM pg_temp.verify_negative('purge_verify_polymorf','POLYMORF_SUBJEKT_FORAELDRELOES',format($mutation$
        DO $probe$ DECLARE v_id bigint; BEGIN
          PERFORM purge_test.nyt();
          IF %L='fact' THEN
            INSERT INTO public.fact(subjekt_type,subjekt_id,faktatype)
              VALUES('person',purge_test.id('nabo'),'test') RETURNING id INTO v_id;
            CREATE TRIGGER zz_purge_verify_fact BEFORE DELETE ON public.fact
              FOR EACH ROW EXECUTE FUNCTION pg_temp.verify_late_fact_relation(%L);
            DELETE FROM public.fact WHERE id=v_id;
          ELSE
            INSERT INTO public.media(slags) VALUES('portræt') RETURNING id INTO v_id;
            IF %L='subjekt' THEN
              INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle)
                VALUES('media',v_id,'person',purge_test.id('nabo'),'test');
            ELSE
              INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle)
                VALUES('person',purge_test.id('nabo'),'media',v_id,'test');
            END IF;
            DELETE FROM public.media WHERE id=v_id;
          END IF;
        END $probe$
      $mutation$,v_type,v_end,v_end));
    END LOOP;
  END LOOP;
END $ends$;
\echo OK db_verify_foraeldreloese_fact_media_begge_ender_negativ

-- Samme lovlige sene indsættelse for hver fact/relation-evidenstabel.
CREATE FUNCTION pg_temp.verify_late_evidence() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE format('INSERT INTO public.%I(target_type,target_id) VALUES($1,$2)',TG_ARGV[0])
    USING TG_TABLE_NAME,OLD.id;
  RETURN OLD;
END $$;
DO $evidence$
DECLARE v_type text; v_table text;
BEGIN
  FOREACH v_type IN ARRAY ARRAY['fact','relation'] LOOP
    FOREACH v_table IN ARRAY ARRAY['assertion','conclusion','note'] LOOP
      PERFORM pg_temp.verify_negative('purge_verify_polymorf','POLYMORF_SUBJEKT_FORAELDRELOES',format($mutation$
        DO $probe$ DECLARE v_id bigint; BEGIN
          PERFORM purge_test.nyt();
          IF %L='fact' THEN
            INSERT INTO public.fact(subjekt_type,subjekt_id,faktatype)
              VALUES('person',purge_test.id('nabo'),'test') RETURNING id INTO v_id;
          ELSE
            INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle)
              VALUES('person',purge_test.id('nabo'),'person',purge_test.id('tredje'),'test') RETURNING id INTO v_id;
          END IF;
          CREATE TRIGGER zz_purge_verify_evidence BEFORE DELETE ON public.%I
            FOR EACH ROW EXECUTE FUNCTION pg_temp.verify_late_evidence(%L);
          DELETE FROM public.%I WHERE id=v_id;
        END $probe$
      $mutation$,v_type,v_type,v_table,v_type));
    END LOOP;
  END LOOP;
END $evidence$;
\echo OK db_verify_foraeldreloes_fact_relation_evidens_negativ

-- Simuler en gammel ikke-kanonisk række ved en sidst kørende BEFORE-trigger.
-- De rigtige vagter validerer først det eksisterende mål; kun testtriggeren ændrer casing bagefter.
CREATE FUNCTION pg_temp.verify_legacy_type() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW:=jsonb_populate_record(NEW,jsonb_build_object(TG_ARGV[0],initcap(to_jsonb(NEW)->>TG_ARGV[0])));
  RETURN NEW;
END $$;
DO $types$
DECLARE v_type text; v_end text; v_table text;
BEGIN
  -- Begge fact/media-ender, med et eksisterende mål, så fejlen entydigt er typen.
  FOREACH v_type IN ARRAY ARRAY['fact','media'] LOOP
    FOREACH v_end IN ARRAY ARRAY['subjekt','objekt'] LOOP
      PERFORM pg_temp.verify_negative('purge_verify_polymorf','POLYMORF_TYPE_IKKE_KANONISK',format($mutation$
        DO $probe$ DECLARE v_id bigint; BEGIN
          PERFORM purge_test.nyt();
          IF %L='fact' THEN
            INSERT INTO public.fact(subjekt_type,subjekt_id,faktatype)
              VALUES('person',purge_test.id('nabo'),'test') RETURNING id INTO v_id;
          ELSE INSERT INTO public.media(slags) VALUES('portræt') RETURNING id INTO v_id; END IF;
          CREATE TRIGGER zz_purge_verify_type BEFORE INSERT ON public.relation
            FOR EACH ROW EXECUTE FUNCTION pg_temp.verify_legacy_type(%L);
          IF %L='subjekt' THEN
            INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle)
              VALUES(%L,v_id,'person',purge_test.id('nabo'),'test');
          ELSE
            INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle)
              VALUES('person',purge_test.id('nabo'),%L,v_id,'test');
          END IF;
        END $probe$
      $mutation$,v_type,v_end||'_type',v_end,v_type,v_type));
    END LOOP;
  END LOOP;
  FOREACH v_type IN ARRAY ARRAY['fact','relation'] LOOP
    FOREACH v_table IN ARRAY ARRAY['assertion','conclusion','note'] LOOP
      PERFORM pg_temp.verify_negative('purge_verify_polymorf','POLYMORF_TYPE_IKKE_KANONISK',format($mutation$
        DO $probe$ DECLARE v_id bigint; BEGIN
          PERFORM purge_test.nyt();
          IF %L='fact' THEN
            INSERT INTO public.fact(subjekt_type,subjekt_id,faktatype)
              VALUES('person',purge_test.id('nabo'),'test') RETURNING id INTO v_id;
          ELSE
            INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle)
              VALUES('person',purge_test.id('nabo'),'person',purge_test.id('tredje'),'test') RETURNING id INTO v_id;
          END IF;
          CREATE TRIGGER zz_purge_verify_type BEFORE INSERT ON public.%I
            FOR EACH ROW EXECUTE FUNCTION pg_temp.verify_legacy_type('target_type');
          INSERT INTO public.%I(target_type,target_id) VALUES(%L,v_id);
        END $probe$
      $mutation$,v_type,v_table,v_table,v_type));
    END LOOP;
  END LOOP;
END $types$;
\echo OK db_verify_type_ikke_kanonisk_ender_og_evidens_negativ

-- Prøv ALLE tilstødende positionspar fra den kanoniske vagts egen mønsterliste.
-- Herunder persona/L6b, L6b/samme_som, familie/L11b og L11b/L12.
DO $locks$
DECLARE v_def text; v_check text; v_chunks text[]; r record; i int;
BEGIN
  v_def:=pg_get_functiondef('public.red_slet_person_helt(bigint,text)'::regprocedure);
  SELECT sql INTO STRICT v_check FROM purge_verify_checks WHERE navn='purge_verify_lock_order';
  FOR r IN SELECT m[1] pattern FROM regexp_matches(v_check,'\$re\$(.*?)\$re\$','gs') m LOOP
    v_chunks:=array_append(v_chunks,(regexp_match(v_def,r.pattern,'i'))[1]);
  END LOOP;
  IF cardinality(v_chunks)<>17 OR array_position(v_chunks,NULL) IS NOT NULL THEN
    RAISE EXCEPTION 'TEST_FAILED db_verify_lock_fixture';
  END IF;
  FOR i IN 1..cardinality(v_chunks)-1 LOOP
    PERFORM pg_temp.verify_negative('purge_verify_lock_order','PURGE_LOCK_ORDER',
      pg_temp.verify_swap(v_def,v_chunks[i],v_chunks[i+1]));
  END LOOP;
END $locks$;
\echo OK db_verify_lock_order_16_ombytninger_negativ

DO $allocators$
DECLARE v_def text; v_mutation text; v_expr text;
BEGIN
  -- Nyt navn OG andet skema: ingen håndholdt liste over mulige aktive skrivere.
  FOREACH v_expr IN ARRAY ARRAY['max(id)+1','coalesce(max(id),0)+1','MAX ( "p"."id" ) + 1'] LOOP
    PERFORM pg_temp.verify_negative('purge_verify_allocators','ID_MAX_PLUS_ONE_ALLOCATOR',format($mutation$
      DO $probe$ BEGIN
        CREATE SCHEMA purge_verify_probe;
        EXECUTE $ddl$CREATE FUNCTION purge_verify_probe.allocate_person() RETURNS bigint LANGUAGE plpgsql AS $body$
          DECLARE v_id bigint; BEGIN
            SELECT %s INTO v_id FROM public.person p;
            INSERT INTO public.person(id) VALUES(v_id);
            RETURN v_id;
          END $body$ $ddl$;
      END $probe$
    $mutation$,v_expr));
  END LOOP;
  -- En klassificeret ordinalfunktion får heller ikke lov til at allokere entitets-id'er.
  v_def:=pg_get_functiondef('private.reverse_narrative_publication_event(uuid,text)'::regprocedure);
  v_mutation:=replace(v_def,'max(event.stream_version)','max(event.id)');
  IF v_mutation=v_def THEN RAISE EXCEPTION 'TEST_FAILED db_verify_ordinal_fixture'; END IF;
  PERFORM pg_temp.verify_negative('purge_verify_allocators','ID_MAX_PLUS_ONE_ALLOCATOR',v_mutation);
  -- Den navngivne v1-undtagelse er betinget af afvisningen før id-allokeringen.
  v_def:=pg_get_functiondef('private.write_reimport_case_narrative(bigint,bigint,bigint,text,boolean,text)'::regprocedure);
  v_mutation:=replace(v_def,'IF public.narrative_record_contract_version()>=2 THEN','IF false THEN');
  IF v_mutation=v_def THEN RAISE EXCEPTION 'TEST_FAILED db_verify_legacy_fixture'; END IF;
  PERFORM pg_temp.verify_negative('purge_verify_allocators','ID_MAX_PLUS_ONE_ALLOCATOR',v_mutation);
END $allocators$;
\echo OK db_verify_ny_max_id_plus_one_skriver_negativ
\echo OK db_verify_ordinal_ikke_funktionsfripas_negativ
\echo OK db_verify_v1_gate_negativ
ROLLBACK;

-- Gentag efter ALLE mutationer; en bestået negativ prøve skal efterlade grønne katalog-/datavagter.
DO $green$
DECLARE r record;
BEGIN
  IF to_regnamespace('purge_verify_probe') IS NOT NULL THEN RAISE EXCEPTION 'TEST_FAILED db_verify_probe_rest'; END IF;
  FOR r IN SELECT navn FROM purge_verify_checks ORDER BY navn COLLATE "C" LOOP
    PERFORM pg_temp.verify_check(r.navn);
  END LOOP;
END $green$;
\echo OK db_verify_negative_mutationer_rullet_tilbage
