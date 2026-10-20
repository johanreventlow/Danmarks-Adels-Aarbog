-- #244 (spec §7.4): rettelsesskriveren holder postens ægteskabspåstande låst, så en samtidig afvisning af en
-- søskendepåstand (der ville flytte nummeret) må vente. To sessioner via dblink. Opsætningen committes, så testen
-- kører i en ENGANGSBASE (CI: ci5b_2bii_sheet); tabellerne er tilføj-kun og kan ikke ryddes op. Opdigtede navne.
\set ON_ERROR_STOP on
CREATE EXTENSION IF NOT EXISTS dblink;
BEGIN;
\ir fixtures/relation-5b.sql
\ir fixtures/relation-2a.sql
\ir fixtures/marriage-ordinal-244.sql
DO $laas_setup$
DECLARE v_actor uuid:='11000000-0000-0000-0000-000000024461'; s jsonb; m jsonb;
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  INSERT INTO person(id,levende,privat,status) SELECT g,false,false,'244 lås' FROM generate_series(-24463,-24461) g;
  s:=pg_temp.f5b_source(-24461);
  m:=pg_temp.f244_post(-24461,s,'L-1',-24461,-24462,-24463,v_actor,p_third=>true);
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  IF pg_temp.f244_decide_and_bind(-24461,v_actor)<>2 THEN RAISE EXCEPTION 'ORDINAL_244_LOCK_TEST_FAILED: opsætning'; END IF;
END $laas_setup$;
COMMIT;

BEGIN;
DO $laas$
DECLARE v_actor uuid:='11000000-0000-0000-0000-000000024461'; k1 uuid; c3 uuid; v_err text; v_ok text;
  ctx jsonb:=jsonb_build_object('basis','human_sheet','sheet_sha256',repeat('a',64),'rows_sha256',repeat('b',64),'line','1');
  v_conn text:=format('dbname=%s port=%s host=%s',current_database(),current_setting('port'),
                      split_part(current_setting('unix_socket_directories'),',',1));
  v_call text;
BEGIN
  SELECT ic.interpretation_key INTO k1 FROM private.interpretation_current ic
   WHERE ic.source_id=-24461 AND ic.value->>'raw'='Gift 1° m. Bo Beta f. 1800.';
  SELECT ic.id INTO c3 FROM private.interpretation_current ic
   WHERE ic.source_id=-24461 AND ic.value->>'raw'='Gift 3° m. Dy Delta.' AND ic.status='proposed';
  IF k1 IS NULL OR c3 IS NULL THEN RAISE EXCEPTION 'ORDINAL_244_LOCK_TEST_FAILED: opslag'; END IF;
  v_call:=format('BEGIN; SET lock_timeout=''300ms''; SELECT set_config(''request.jwt.claim.sub'',%L,true); '
    'SET LOCAL ROLE authenticated; SELECT red_decide_interpretation(%L::uuid,1,''rejected'',''{"note":"låsetest"}''::jsonb)::text',
    v_actor::text,c3::text);
  PERFORM dblink_connect('l244',v_conn);
  -- Positiv kontrol: uden rettelse lykkes afvisningen i den anden session (og rulles tilbage).
  BEGIN
    SELECT x INTO v_ok FROM dblink('l244',v_call) AS t(x text);
    PERFORM dblink_exec('l244','ROLLBACK');
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT; PERFORM dblink_disconnect('l244');
    RAISE EXCEPTION 'ORDINAL_244_LOCK_TEST_FAILED: positiv kontrol %',v_err;
  END;
  -- Rettelsen i denne session holder låsene; afvisningen i den anden må nu vente (lock timeout).
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  SET LOCAL ROLE authenticated;
  PERFORM red_ret_aegteskabsnummer(k1,1,'låsetest',ctx);
  RESET ROLE;
  BEGIN
    SELECT x INTO v_ok FROM dblink('l244',v_call) AS t(x text);
    PERFORM dblink_exec('l244','ROLLBACK'); PERFORM dblink_disconnect('l244');
    RAISE EXCEPTION 'ORDINAL_244_LOCK_TEST_FAILED: afvisningen ventede ikke';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT;
    BEGIN PERFORM dblink_disconnect('l244'); EXCEPTION WHEN OTHERS THEN NULL; END;
    IF v_err NOT LIKE '%lock timeout%' THEN RAISE; END IF;
  END;
  RAISE NOTICE 'OK: rettelsen låser postens ægteskabspåstande';
END $laas$;
ROLLBACK;
