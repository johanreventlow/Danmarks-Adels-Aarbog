-- Review-handling trin B (plan docs/superpowers/plans/2026-10-27-review-trin-b-ddl.md): redaktørens skrivevej for
-- oplysninger og læsecachen. Hver blok kører i sin egen transaktion og rulles tilbage.
\set ON_ERROR_STOP on

-- ---------- T2 (1d.1-03): red_edit_oplysning ompeger kun konklusionen, når den rettede oplysning var valgt ----------
BEGIN;
DO $edit_oplysning$
DECLARE v_actor uuid:='11000000-0000-0000-0000-0000001d1031'; v_fact bigint; v_fact2 bigint; a1 bigint; a2 bigint;
  r jsonb; n1 bigint; n2 bigint; n3 bigint; n4 bigint; v_valgt bigint;
BEGIN
  INSERT INTO auth.users(id,email) VALUES (v_actor,'trinb-t2@example.invalid');
  INSERT INTO profiles(id,rolle,navn,email) VALUES (v_actor,'redaktion','trin B','trinb-t2@example.invalid');
  INSERT INTO person(id,levende,privat) VALUES (-41001,false,false);
  INSERT INTO fact(subjekt_type,subjekt_id,faktatype) VALUES ('person',-41001,'fødsel') RETURNING id INTO v_fact;
  INSERT INTO assertion(target_type,target_id,vaerdi_tekst,date_raw,date_certainty,uforanderlig)
    VALUES ('fact',v_fact,NULL,'1701','uncertain',true) RETURNING id INTO a1;
  INSERT INTO assertion(target_type,target_id,vaerdi_tekst,date_raw,date_certainty,uforanderlig)
    VALUES ('fact',v_fact,NULL,'1702','ambiguous',true) RETURNING id INTO a2;
  INSERT INTO conclusion(target_type,target_id,valgt_assertion_id,status) VALUES ('fact',v_fact,a1,'afklaret');
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  SET LOCAL ROLE authenticated;

  -- (a) en IKKE-valgt oplysning rettes (ny datotekst): ny påstand, men konklusionen bliver på den valgte, og
  --     date_certainty arves ikke, fordi datoteksten er ændret
  PERFORM set_config('app.change_set_id','',true);
  r:=red_edit_oplysning(a2,NULL,'1702?',NULL);
  n2:=(r->>'ny_assertion_id')::bigint;
  SELECT valgt_assertion_id INTO v_valgt FROM conclusion WHERE target_type='fact' AND target_id=v_fact;
  IF v_valgt IS DISTINCT FROM a1 THEN
    RAISE EXCEPTION 'REDAKTION_OPLYSNING_TEST_FAILED: ikke-valgt rettelse ompegede konklusionen (% i stedet for %)',v_valgt,a1;
  END IF;
  IF (SELECT date_certainty FROM assertion WHERE id=n2) IS NOT NULL
     OR (SELECT date_raw FROM assertion WHERE id=n2) IS DISTINCT FROM '1702?' THEN
    RAISE EXCEPTION 'REDAKTION_OPLYSNING_TEST_FAILED: date_certainty arvet trods ændret datotekst';
  END IF;

  -- (b) den VALGTE oplysning rettes med uændret datotekst (som web sender): konklusionen følger med, og
  --     date_certainty arves
  PERFORM set_config('app.change_set_id','',true);
  r:=red_edit_oplysning(a1,NULL,'1701',NULL);
  n1:=(r->>'ny_assertion_id')::bigint;
  SELECT valgt_assertion_id INTO v_valgt FROM conclusion WHERE target_type='fact' AND target_id=v_fact;
  IF v_valgt IS DISTINCT FROM n1 THEN
    RAISE EXCEPTION 'REDAKTION_OPLYSNING_TEST_FAILED: valgt rettelse flyttede ikke konklusionen (% i stedet for %)',v_valgt,n1;
  END IF;
  IF (SELECT date_certainty FROM assertion WHERE id=n1) IS DISTINCT FROM 'uncertain' THEN
    RAISE EXCEPTION 'REDAKTION_OPLYSNING_TEST_FAILED: date_certainty ikke arvet ved uændret datotekst';
  END IF;
  -- uden datotekst (p_date_raw NULL) er teksten også uændret: arves
  PERFORM set_config('app.change_set_id','',true);
  n4:=(red_edit_oplysning(n1,'kilde siger 1701',NULL,NULL)->>'ny_assertion_id')::bigint;
  IF (SELECT date_certainty FROM assertion WHERE id=n4) IS DISTINCT FROM 'uncertain'
     OR (SELECT date_raw FROM assertion WHERE id=n4) IS DISTINCT FROM '1701' THEN
    RAISE EXCEPTION 'REDAKTION_OPLYSNING_TEST_FAILED: date_certainty ikke arvet uden datotekst';
  END IF;
  -- de gamle påstande er urørte (append)
  IF (SELECT count(*) FROM assertion WHERE id IN (a1,a2) AND date_raw IN ('1701','1702'))<>2 THEN
    RAISE EXCEPTION 'REDAKTION_OPLYSNING_TEST_FAILED: gamle påstande ændret';
  END IF;

  -- (c) et faktum uden konklusion får én, der peger på den nye påstand
  RESET ROLE;
  INSERT INTO fact(subjekt_type,subjekt_id,faktatype) VALUES ('person',-41001,'titel') RETURNING id INTO v_fact2;
  INSERT INTO assertion(target_type,target_id,vaerdi_tekst,uforanderlig) VALUES ('fact',v_fact2,'kammerjunker',true) RETURNING id INTO a1;
  SET LOCAL ROLE authenticated;
  PERFORM set_config('app.change_set_id','',true);
  n3:=(red_edit_oplysning(a1,'kammerherre',NULL,NULL)->>'ny_assertion_id')::bigint;
  IF (SELECT valgt_assertion_id FROM conclusion WHERE target_type='fact' AND target_id=v_fact2) IS DISTINCT FROM n3 THEN
    RAISE EXCEPTION 'REDAKTION_OPLYSNING_TEST_FAILED: konklusion ikke oprettet for faktum uden konklusion';
  END IF;
  RESET ROLE;
  RAISE NOTICE 'OK: red_edit_oplysning ompeger kun den valgte og arver date_certainty kun ved uændret datotekst';
END $edit_oplysning$;
ROLLBACK;

-- ---------- T3 (1d.1-02): red_slet_oplysning sletter kun redaktørens egne påstande ----------
BEGIN;
DO $slet_oplysning$
DECLARE v_actor uuid:='11000000-0000-0000-0000-0000001d1021'; v_fact bigint; a_imp bigint; a_null bigint; a_egen bigint;
  a_egen2 bigint; v_err text; n_cs bigint;
BEGIN
  INSERT INTO auth.users(id,email) VALUES (v_actor,'trinb-t3@example.invalid');
  INSERT INTO profiles(id,rolle,navn,email) VALUES (v_actor,'redaktion','trin B','trinb-t3@example.invalid');
  INSERT INTO person(id,levende,privat) VALUES (-41002,false,false);
  INSERT INTO fact(subjekt_type,subjekt_id,faktatype) VALUES ('person',-41002,'titel') RETURNING id INTO v_fact;
  INSERT INTO assertion(target_type,target_id,vaerdi_tekst,uforanderlig) VALUES ('fact',v_fact,'importeret',true) RETURNING id INTO a_imp;
  INSERT INTO citation(assertion_id,source_id,citat_tekst) VALUES (a_imp,NULL,'kilde');
  INSERT INTO assertion(target_type,target_id,vaerdi_tekst,uforanderlig) VALUES ('fact',v_fact,'uden markering',NULL) RETURNING id INTO a_null;
  INSERT INTO assertion(target_type,target_id,vaerdi_tekst,uforanderlig) VALUES ('fact',v_fact,'egen',false) RETURNING id INTO a_egen;
  INSERT INTO assertion(target_type,target_id,vaerdi_tekst,uforanderlig) VALUES ('fact',v_fact,'egen 2',false) RETURNING id INTO a_egen2;
  INSERT INTO conclusion(target_type,target_id,valgt_assertion_id,status) VALUES ('fact',v_fact,a_egen,'afklaret');
  SELECT count(*) INTO n_cs FROM change_set;
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  SET LOCAL ROLE authenticated;

  -- (a) importeret kildepåstand (uforanderlig=true) og en umarkeret (NULL, kolonnens default er sand) afvises
  FOREACH a_egen2 IN ARRAY ARRAY[a_imp,a_null] LOOP
    PERFORM set_config('app.change_set_id','',true);
    BEGIN
      PERFORM red_slet_oplysning(a_egen2);
      RAISE EXCEPTION 'REDAKTION_OPLYSNING_TEST_FAILED: uforanderlig påstand % slettet',a_egen2;
    EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT;
      IF v_err NOT LIKE 'Kildepåstande slettes ikke%' THEN RAISE; END IF;
    END;
  END LOOP;
  RESET ROLE;
  IF (SELECT count(*) FROM assertion WHERE id IN (a_imp,a_null))<>2
     OR NOT EXISTS (SELECT 1 FROM citation WHERE assertion_id=a_imp)
     OR (SELECT count(*) FROM change_set)<>n_cs THEN
    RAISE EXCEPTION 'REDAKTION_OPLYSNING_TEST_FAILED: afvist sletning efterlod spor';
  END IF;

  -- (b) redaktørens egen (uforanderlig=false) kan fortsat slettes; var den valgt, ompeges konklusionen
  SELECT id INTO a_egen2 FROM assertion WHERE target_type='fact' AND target_id=v_fact AND vaerdi_tekst='egen 2';
  SET LOCAL ROLE authenticated;
  PERFORM set_config('app.change_set_id','',true);
  PERFORM red_slet_oplysning(a_egen);
  RESET ROLE;
  IF EXISTS (SELECT 1 FROM assertion WHERE id=a_egen)
     OR (SELECT valgt_assertion_id FROM conclusion WHERE target_type='fact' AND target_id=v_fact) IS NULL THEN
    RAISE EXCEPTION 'REDAKTION_OPLYSNING_TEST_FAILED: egen påstand ikke slettet';
  END IF;
  RAISE NOTICE 'OK: red_slet_oplysning afviser kildepåstande og sletter redaktørens egne';
END $slet_oplysning$;
ROLLBACK;

-- ---------- T4 (1d.1-04): læsecachen bygger kun på afklarede konklusioner ----------
BEGIN;
DO $cache_status$
DECLARE f_a bigint; f_b bigint; f_f bigint; a bigint;
BEGIN
  INSERT INTO person(id,levende,privat) VALUES (-41004,false,false);
  -- to navne-faktaer: det afklarede »Aaa« og et forældet »Zzz« (max() ville vælge Zzz)
  INSERT INTO fact(subjekt_type,subjekt_id,faktatype) VALUES ('person',-41004,'navn') RETURNING id INTO f_a;
  INSERT INTO assertion(target_type,target_id,vaerdi_tekst) VALUES ('fact',f_a,'Aaa') RETURNING id INTO a;
  INSERT INTO conclusion(target_type,target_id,valgt_assertion_id,status) VALUES ('fact',f_a,a,'afklaret');
  INSERT INTO fact(subjekt_type,subjekt_id,faktatype) VALUES ('person',-41004,'navn') RETURNING id INTO f_b;
  INSERT INTO assertion(target_type,target_id,vaerdi_tekst) VALUES ('fact',f_b,'Zzz') RETURNING id INTO a;
  INSERT INTO conclusion(target_type,target_id,valgt_assertion_id,status) VALUES ('fact',f_b,a,'forældet');
  -- en omstridt fødsel indgår heller ikke
  INSERT INTO fact(subjekt_type,subjekt_id,faktatype) VALUES ('person',-41004,'fødsel') RETURNING id INTO f_f;
  INSERT INTO assertion(target_type,target_id,date_raw) VALUES ('fact',f_f,'1650') RETURNING id INTO a;
  INSERT INTO conclusion(target_type,target_id,valgt_assertion_id,status) VALUES ('fact',f_f,a,'omstridt');
  PERFORM regen_person_visning(-41004);
  IF (SELECT visning_navn FROM person WHERE id=-41004) IS DISTINCT FROM 'Aaa'
     OR (SELECT visning_foedt FROM person WHERE id=-41004) IS NOT NULL THEN
    RAISE EXCEPTION 'REDAKTION_OPLYSNING_TEST_FAILED: cachen bruger ikke-afklarede konklusioner (navn %, født %)',
      (SELECT visning_navn FROM person WHERE id=-41004),(SELECT visning_foedt FROM person WHERE id=-41004);
  END IF;
  -- trækkes det afklarede navn tilbage (status ≠ afklaret), forsvinder det fra cachen
  UPDATE conclusion SET status='omstridt' WHERE target_type='fact' AND target_id=f_a;
  PERFORM regen_person_visning(-41004);
  IF (SELECT visning_navn FROM person WHERE id=-41004) IS NOT NULL THEN
    RAISE EXCEPTION 'REDAKTION_OPLYSNING_TEST_FAILED: tilbagetrukket navn står i cachen';
  END IF;
  RAISE NOTICE 'OK: regen_person_visning bruger kun afklarede konklusioner';
END $cache_status$;
ROLLBACK;
