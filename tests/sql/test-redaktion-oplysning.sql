-- Review-handling trin B (plan docs/superpowers/plans/2026-10-27-review-trin-b-ddl.md): redaktørens skrivevej for
-- oplysninger og læsecachen. Hver blok kører i sin egen transaktion og rulles tilbage.
\set ON_ERROR_STOP on

-- ---------- T2 (1d.1-03): red_edit_oplysning ompeger kun konklusionen, når den rettede oplysning var valgt ----------
BEGIN;
DO $edit_oplysning$
DECLARE v_actor uuid:='11000000-0000-0000-0000-0000001d1031'; v_fact bigint; v_fact2 bigint; a1 bigint; a2 bigint;
  r jsonb; n1 bigint; n2 bigint; n3 bigint; v_valgt bigint;
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

  -- (a) en IKKE-valgt oplysning rettes: ny påstand, men konklusionen bliver på den valgte
  PERFORM set_config('app.change_set_id','',true);
  r:=red_edit_oplysning(a2,NULL,'1702?',NULL);
  n2:=(r->>'ny_assertion_id')::bigint;
  SELECT valgt_assertion_id INTO v_valgt FROM conclusion WHERE target_type='fact' AND target_id=v_fact;
  IF v_valgt IS DISTINCT FROM a1 THEN
    RAISE EXCEPTION 'REDAKTION_OPLYSNING_TEST_FAILED: ikke-valgt rettelse ompegede konklusionen (% i stedet for %)',v_valgt,a1;
  END IF;
  IF (SELECT date_certainty FROM assertion WHERE id=n2) IS DISTINCT FROM 'ambiguous'
     OR (SELECT date_raw FROM assertion WHERE id=n2) IS DISTINCT FROM '1702?' THEN
    RAISE EXCEPTION 'REDAKTION_OPLYSNING_TEST_FAILED: date_certainty ikke kopieret (ikke-valgt)';
  END IF;

  -- (b) den VALGTE oplysning rettes: konklusionen følger med til den nye påstand
  PERFORM set_config('app.change_set_id','',true);
  r:=red_edit_oplysning(a1,NULL,'1701?',NULL);
  n1:=(r->>'ny_assertion_id')::bigint;
  SELECT valgt_assertion_id INTO v_valgt FROM conclusion WHERE target_type='fact' AND target_id=v_fact;
  IF v_valgt IS DISTINCT FROM n1 THEN
    RAISE EXCEPTION 'REDAKTION_OPLYSNING_TEST_FAILED: valgt rettelse flyttede ikke konklusionen (% i stedet for %)',v_valgt,n1;
  END IF;
  IF (SELECT date_certainty FROM assertion WHERE id=n1) IS DISTINCT FROM 'uncertain' THEN
    RAISE EXCEPTION 'REDAKTION_OPLYSNING_TEST_FAILED: date_certainty ikke kopieret (valgt)';
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
  RAISE NOTICE 'OK: red_edit_oplysning ompeger kun den valgte og kopierer date_certainty';
END $edit_oplysning$;
ROLLBACK;
