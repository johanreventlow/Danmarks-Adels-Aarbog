\set ON_ERROR_STOP on
-- Driftsbaseline, restore-hash, uberørt-hash og restore-forudsætninger (spec §4.3, §5, §6.1; plan A Task 3).
-- De rå tabeller er append-only: hver variant kører som SAVEPOINT -> ændring -> mål -> \gset -> ROLLBACK TO
-- SAVEPOINT, og værdierne sammenlignes bagefter.
--   0 basis  1 gentagelse  2 writer-profilrække  3 assertion-værdi  4 identitet  5 sekvens
--   6 ikke-kæde-sekvens  11/12 andre sessionsindstillinger inkl. row_security (B11)  14 katalogændringer (B12)  7 ægte afgørelse + binding (eksklusionslistens korrekthed)  8 ny person  9 nyt fact  10 forældreløs række
BEGIN;
\i tests/sql/transfer-fixture.sql
\set src -4700
SELECT pg_temp.transfer_fx(-4700,'a4700000','b4700000') \g /dev/null
SET CONSTRAINTS ALL IMMEDIATE;
\o /dev/null
\i .claude/skills/daa-extract/scripts/transfer_baseline.sql
\o
\o /dev/null
\i .claude/skills/daa-extract/scripts/transfer_restore_hash.sql
\o
\o /dev/null
\i .claude/skills/daa-extract/scripts/transfer_untouched_hash.sql
\o
SELECT current_setting('daa.transfer_baseline') AS b_0, current_setting('daa.restore_hash') AS r_0, current_setting('daa.untouched_hash') AS u_0 \gset
\o /dev/null
\i .claude/skills/daa-extract/scripts/transfer_restore_preconditions.sql
\o
SELECT current_setting('daa.restore_preconditions') AS p_0 \gset
SAVEPOINT x;
\o /dev/null
\i .claude/skills/daa-extract/scripts/transfer_baseline.sql
\o
\o /dev/null
\i .claude/skills/daa-extract/scripts/transfer_restore_hash.sql
\o
\o /dev/null
\i .claude/skills/daa-extract/scripts/transfer_untouched_hash.sql
\o
SELECT current_setting('daa.transfer_baseline') AS b_1, current_setting('daa.restore_hash') AS r_1, current_setting('daa.untouched_hash') AS u_1 \gset
ROLLBACK TO SAVEPOINT x;
SAVEPOINT x;
INSERT INTO private.reimport_writer_profile(source_id,profile_id,profile_version,profile_sha256,writer_config)
  SELECT -4700,'transfer-probe','1.0.0',private.reimport_canonical_json_sha256(c),c
    FROM (SELECT jsonb_build_object('run_key_prefix','tp:','schema_version','tp','extractor_version','tp',
      'rendition_key','tp','rendition_kind','ocr_text','rendition_metadata','{}'::jsonb,
      'observation_extraction_method','tp','citation_label_template','tp side {page_from}') AS c) q;
\o /dev/null
\i .claude/skills/daa-extract/scripts/transfer_baseline.sql
\o
\o /dev/null
\i .claude/skills/daa-extract/scripts/transfer_restore_hash.sql
\o
\o /dev/null
\i .claude/skills/daa-extract/scripts/transfer_untouched_hash.sql
\o
SELECT current_setting('daa.transfer_baseline') AS b_2, current_setting('daa.restore_hash') AS r_2, current_setting('daa.untouched_hash') AS u_2 \gset
ROLLBACK TO SAVEPOINT x;
SAVEPOINT x;
UPDATE assertion SET date_raw='1851' WHERE id=-4711;
\o /dev/null
\i .claude/skills/daa-extract/scripts/transfer_baseline.sql
\o
SELECT current_setting('daa.transfer_baseline') AS b_3 \gset
ROLLBACK TO SAVEPOINT x;
SAVEPOINT x;
SET CONSTRAINTS ALL DEFERRED;
INSERT INTO private.source_persona_identity_event(source_persona_id,canonical_person_id,decision_status,version,evidence,decided_by,decided_by_name,decided_at)
  VALUES ('a4700000-0000-4000-8000-000000000101',NULL,'rejected',2,'{"basis":"b4"}','a4700000-0000-4000-8000-000000000001','b4','2026-01-01T00:00:00Z');
UPDATE private.source_persona_identity SET decision_status='rejected',canonical_person_id=NULL,version=2,evidence='{"basis":"b4"}',decided_by='a4700000-0000-4000-8000-000000000001',decided_by_name='b4',decided_at='2026-01-01T00:00:00Z'
 WHERE source_persona_id='a4700000-0000-4000-8000-000000000101';
SET CONSTRAINTS ALL IMMEDIATE;
\o /dev/null
\i .claude/skills/daa-extract/scripts/transfer_baseline.sql
\o
SELECT current_setting('daa.transfer_baseline') AS b_4 \gset
ROLLBACK TO SAVEPOINT x;
SAVEPOINT x;
SELECT nextval('private.reimport_event_id_seq'::regclass) \g /dev/null
\o /dev/null
\i .claude/skills/daa-extract/scripts/transfer_restore_hash.sql
\o
\o /dev/null
\i .claude/skills/daa-extract/scripts/transfer_untouched_hash.sql
\o
SELECT current_setting('daa.restore_hash') AS r_5, current_setting('daa.untouched_hash') AS u_5 \gset
ROLLBACK TO SAVEPOINT x;
SAVEPOINT x;
SELECT id AS id1 FROM private.interpretation WHERE interpretation_key='b4700000-0000-4000-8000-000000000001' AND version=1 \gset
SET CONSTRAINTS ALL DEFERRED;
SELECT set_config('request.jwt.claim.sub','a4700000-0000-4000-8000-000000000001',true) \g /dev/null
SET LOCAL ROLE authenticated;
SELECT red_decide_interpretation(:'id1',1,'accepted','{"method":"m"}') AS acc \gset
RESET ROLE;
SET CONSTRAINTS ALL IMMEDIATE;
\o /dev/null
\i .claude/skills/daa-extract/scripts/interpretation_promotion_targets.sql
\o
SELECT current_setting('daa.targets_result')::jsonb->'items' AS items \gset
SET LOCAL ROLE authenticated;
SELECT red_preview_interpretation_promotions(:'items'::jsonb)->>'preview_hash' AS ph \gset
SELECT red_promote_interpretations_batch(:'items'::jsonb,:'ph') \g /dev/null
RESET ROLE;
SELECT count(*) AS n_prom_7 FROM private.interpretation_promotion \gset
\o /dev/null
\i .claude/skills/daa-extract/scripts/transfer_baseline.sql
\o
\o /dev/null
\i .claude/skills/daa-extract/scripts/transfer_restore_hash.sql
\o
\o /dev/null
\i .claude/skills/daa-extract/scripts/transfer_untouched_hash.sql
\o
SELECT current_setting('daa.transfer_baseline') AS b_7, current_setting('daa.restore_hash') AS r_7, current_setting('daa.untouched_hash') AS u_7 \gset
ROLLBACK TO SAVEPOINT x;
SAVEPOINT x;
INSERT INTO person(id,levende,privat,status) VALUES (-4799,false,false,'transfer47x');
\o /dev/null
\i .claude/skills/daa-extract/scripts/transfer_baseline.sql
\o
\o /dev/null
\i .claude/skills/daa-extract/scripts/transfer_restore_hash.sql
\o
\o /dev/null
\i .claude/skills/daa-extract/scripts/transfer_untouched_hash.sql
\o
SELECT current_setting('daa.transfer_baseline') AS b_8, current_setting('daa.restore_hash') AS r_8, current_setting('daa.untouched_hash') AS u_8 \gset
ROLLBACK TO SAVEPOINT x;
SAVEPOINT x;
INSERT INTO fact(id,subjekt_type,subjekt_id,faktatype) VALUES (-4798,'person',-4701,'fødsel');
\o /dev/null
\i .claude/skills/daa-extract/scripts/transfer_baseline.sql
\o
SELECT current_setting('daa.transfer_baseline') AS b_9 \gset
ROLLBACK TO SAVEPOINT x;
SAVEPOINT x;
SET LOCAL session_replication_role = replica;
INSERT INTO private.source_persona(id,source_id,persona_key,created_run_id) VALUES ('a4799999-0000-4000-8000-000000000101',-4799,'T-orphan','a4799999-0000-4000-8000-0000000000e1');
SET LOCAL session_replication_role = origin;
\o /dev/null
\i .claude/skills/daa-extract/scripts/transfer_restore_preconditions.sql
\o
SELECT current_setting('daa.restore_preconditions') AS p_10 \gset
ROLLBACK TO SAVEPOINT x;
SAVEPOINT x;
\o /dev/null
\i .claude/skills/daa-extract/scripts/transfer_untouched_hash.sql
\o
SELECT current_setting('daa.untouched_hash') AS u_6a \gset
SELECT nextval(pg_get_serial_sequence('public.person','id')) \g /dev/null
\o /dev/null
\i .claude/skills/daa-extract/scripts/transfer_untouched_hash.sql
\o
SELECT current_setting('daa.untouched_hash') AS u_6 \gset
ROLLBACK TO SAVEPOINT x;
SAVEPOINT x;
SET TimeZone='Europe/Copenhagen'; SET extra_float_digits=3; SET IntervalStyle='postgres'; SET DateStyle='ISO, MDY'; SET search_path='public'; SET row_security=on;
\o /dev/null
\i .claude/skills/daa-extract/scripts/transfer_baseline.sql
\o
SELECT concat_ws('|',current_setting('TimeZone'),current_setting('extra_float_digits'),current_setting('IntervalStyle'),current_setting('DateStyle'),current_setting('search_path'),current_setting('row_security')) AS sb_11 \gset
\o /dev/null
\i .claude/skills/daa-extract/scripts/transfer_restore_hash.sql
\o
SELECT concat_ws('|',current_setting('TimeZone'),current_setting('extra_float_digits'),current_setting('IntervalStyle'),current_setting('DateStyle'),current_setting('search_path'),current_setting('row_security')) AS sr_11 \gset
\o /dev/null
\i .claude/skills/daa-extract/scripts/transfer_untouched_hash.sql
\o
SELECT concat_ws('|',current_setting('TimeZone'),current_setting('extra_float_digits'),current_setting('IntervalStyle'),current_setting('DateStyle'),current_setting('search_path'),current_setting('row_security')) AS su_11 \gset
\o /dev/null
\i .claude/skills/daa-extract/scripts/transfer_restore_preconditions.sql
\o
SELECT current_setting('daa.restore_preconditions') AS p_11, concat_ws('|',current_setting('TimeZone'),current_setting('extra_float_digits'),current_setting('IntervalStyle'),current_setting('DateStyle'),current_setting('search_path'),current_setting('row_security')) AS sp_11 \gset
SELECT current_setting('daa.transfer_baseline') AS b_11, current_setting('daa.restore_hash') AS r_11, current_setting('daa.untouched_hash') AS u_11 \gset
ROLLBACK TO SAVEPOINT x;
SAVEPOINT x;
SET TimeZone='America/New_York'; SET extra_float_digits=-1; SET IntervalStyle='sql_standard'; SET DateStyle='German, DMY'; SET search_path = public, extensions; SET row_security=off;
\o /dev/null
\i .claude/skills/daa-extract/scripts/transfer_baseline.sql
\o
SELECT concat_ws('|',current_setting('TimeZone'),current_setting('extra_float_digits'),current_setting('IntervalStyle'),current_setting('DateStyle'),current_setting('search_path'),current_setting('row_security')) AS sb_12 \gset
\o /dev/null
\i .claude/skills/daa-extract/scripts/transfer_restore_hash.sql
\o
SELECT concat_ws('|',current_setting('TimeZone'),current_setting('extra_float_digits'),current_setting('IntervalStyle'),current_setting('DateStyle'),current_setting('search_path'),current_setting('row_security')) AS sr_12 \gset
\o /dev/null
\i .claude/skills/daa-extract/scripts/transfer_untouched_hash.sql
\o
SELECT concat_ws('|',current_setting('TimeZone'),current_setting('extra_float_digits'),current_setting('IntervalStyle'),current_setting('DateStyle'),current_setting('search_path'),current_setting('row_security')) AS su_12 \gset
\o /dev/null
\i .claude/skills/daa-extract/scripts/transfer_restore_preconditions.sql
\o
SELECT current_setting('daa.restore_preconditions') AS p_12, concat_ws('|',current_setting('TimeZone'),current_setting('extra_float_digits'),current_setting('IntervalStyle'),current_setting('DateStyle'),current_setting('search_path'),current_setting('row_security')) AS sp_12 \gset
SELECT current_setting('daa.transfer_baseline') AS b_12, current_setting('daa.restore_hash') AS r_12, current_setting('daa.untouched_hash') AS u_12 \gset
ROLLBACK TO SAVEPOINT x;
SAVEPOINT x;

\o /dev/null
\i .claude/skills/daa-extract/scripts/transfer_baseline.sql
\o
SELECT concat_ws('|',current_setting('TimeZone'),current_setting('extra_float_digits'),current_setting('IntervalStyle'),current_setting('DateStyle'),current_setting('search_path'),current_setting('row_security')) AS sb_13 \gset
\o /dev/null
\i .claude/skills/daa-extract/scripts/transfer_restore_hash.sql
\o
SELECT concat_ws('|',current_setting('TimeZone'),current_setting('extra_float_digits'),current_setting('IntervalStyle'),current_setting('DateStyle'),current_setting('search_path'),current_setting('row_security')) AS sr_13 \gset
\o /dev/null
\i .claude/skills/daa-extract/scripts/transfer_untouched_hash.sql
\o
SELECT concat_ws('|',current_setting('TimeZone'),current_setting('extra_float_digits'),current_setting('IntervalStyle'),current_setting('DateStyle'),current_setting('search_path'),current_setting('row_security')) AS su_13 \gset
\o /dev/null
\i .claude/skills/daa-extract/scripts/transfer_restore_preconditions.sql
\o
SELECT current_setting('daa.restore_preconditions') AS p_13, concat_ws('|',current_setting('TimeZone'),current_setting('extra_float_digits'),current_setting('IntervalStyle'),current_setting('DateStyle'),current_setting('search_path'),current_setting('row_security')) AS sp_13 \gset
SELECT current_setting('daa.transfer_baseline') AS b_13, current_setting('daa.restore_hash') AS r_13, current_setting('daa.untouched_hash') AS u_13 \gset
ROLLBACK TO SAVEPOINT x;
-- B12: katalogfingeraftrykket (spec §6.1) fanger trigger-, constraint-, RLS- og policyændringer.
SAVEPOINT x;
ALTER TABLE private.clause_disposition DISABLE TRIGGER trg_clause_disposition_validate;
\o /dev/null
\i .claude/skills/daa-extract/scripts/transfer_restore_preconditions.sql
\o
SELECT current_setting('daa.restore_preconditions')::jsonb->>'catalog_sha256' AS c_trg_off \gset
ROLLBACK TO SAVEPOINT x;
SAVEPOINT x;
CREATE TRIGGER transfer47_probe BEFORE UPDATE ON public.person FOR EACH ROW EXECUTE FUNCTION suppress_redundant_updates_trigger();
\o /dev/null
\i .claude/skills/daa-extract/scripts/transfer_restore_preconditions.sql
\o
SELECT current_setting('daa.restore_preconditions')::jsonb->>'catalog_sha256' AS c_trg_new \gset
ROLLBACK TO SAVEPOINT x;
SAVEPOINT x;
ALTER TABLE public.person ADD CONSTRAINT transfer47_probe CHECK (id IS NOT NULL) NOT VALID;
\o /dev/null
\i .claude/skills/daa-extract/scripts/transfer_restore_preconditions.sql
\o
SELECT current_setting('daa.restore_preconditions')::jsonb->>'catalog_sha256' AS c_check \gset
ROLLBACK TO SAVEPOINT x;
SAVEPOINT x;
ALTER TABLE public.person DISABLE ROW LEVEL SECURITY;
\o /dev/null
\i .claude/skills/daa-extract/scripts/transfer_restore_preconditions.sql
\o
SELECT current_setting('daa.restore_preconditions')::jsonb->>'catalog_sha256' AS c_rls_off \gset
ROLLBACK TO SAVEPOINT x;
SAVEPOINT x;
ALTER TABLE public.person FORCE ROW LEVEL SECURITY;
\o /dev/null
\i .claude/skills/daa-extract/scripts/transfer_restore_preconditions.sql
\o
SELECT current_setting('daa.restore_preconditions')::jsonb->>'catalog_sha256' AS c_rls_force \gset
ROLLBACK TO SAVEPOINT x;
SAVEPOINT x;
CREATE POLICY transfer47_probe ON public.person AS PERMISSIVE FOR SELECT TO anon USING (false);
\o /dev/null
\i .claude/skills/daa-extract/scripts/transfer_restore_preconditions.sql
\o
SELECT current_setting('daa.restore_preconditions')::jsonb->>'catalog_sha256' AS c_pol \gset
ROLLBACK TO SAVEPOINT x;
SAVEPOINT x;
CREATE POLICY transfer47_probe ON public.person AS PERMISSIVE FOR SELECT TO authenticated USING (false);
\o /dev/null
\i .claude/skills/daa-extract/scripts/transfer_restore_preconditions.sql
\o
SELECT current_setting('daa.restore_preconditions')::jsonb->>'catalog_sha256' AS c_pol_role \gset
ROLLBACK TO SAVEPOINT x;
SAVEPOINT x;
CREATE POLICY transfer47_probe ON public.person AS PERMISSIVE FOR DELETE TO anon USING (false);
\o /dev/null
\i .claude/skills/daa-extract/scripts/transfer_restore_preconditions.sql
\o
SELECT current_setting('daa.restore_preconditions')::jsonb->>'catalog_sha256' AS c_pol_cmd \gset
ROLLBACK TO SAVEPOINT x;
SAVEPOINT x;
CREATE POLICY transfer47_probe ON public.person AS RESTRICTIVE FOR SELECT TO anon USING (false);
\o /dev/null
\i .claude/skills/daa-extract/scripts/transfer_restore_preconditions.sql
\o
SELECT current_setting('daa.restore_preconditions')::jsonb->>'catalog_sha256' AS c_pol_perm \gset
ROLLBACK TO SAVEPOINT x;
-- mfk: kører samme prædikat som filen igen (fanger kun plumbing-fejl, ikke en forkert definition).
SELECT count(*) AS mfk FROM pg_constraint c JOIN pg_namespace n ON n.oid=c.connamespace WHERE c.contype='f' AND n.nspname IN ('private','public') AND array_length(c.conkey,1)>1 \gset
SELECT set_config('t.b_0',:'b_0',true),
       set_config('t.r_0',:'r_0',true),
       set_config('t.u_0',:'u_0',true),
       set_config('t.b_1',:'b_1',true),
       set_config('t.r_1',:'r_1',true),
       set_config('t.u_1',:'u_1',true),
       set_config('t.b_2',:'b_2',true),
       set_config('t.r_2',:'r_2',true),
       set_config('t.u_2',:'u_2',true),
       set_config('t.b_3',:'b_3',true),
       set_config('t.b_4',:'b_4',true),
       set_config('t.r_5',:'r_5',true),
       set_config('t.u_5',:'u_5',true),
       set_config('t.b_7',:'b_7',true),
       set_config('t.r_7',:'r_7',true),
       set_config('t.u_7',:'u_7',true),
       set_config('t.b_8',:'b_8',true),
       set_config('t.r_8',:'r_8',true),
       set_config('t.u_8',:'u_8',true),
       set_config('t.b_9',:'b_9',true),
       set_config('t.b_11',:'b_11',true),
       set_config('t.r_11',:'r_11',true),
       set_config('t.u_11',:'u_11',true),
       set_config('t.b_12',:'b_12',true),
       set_config('t.r_12',:'r_12',true),
       set_config('t.u_12',:'u_12',true),
       set_config('t.b_13',:'b_13',true),
       set_config('t.r_13',:'r_13',true),
       set_config('t.u_13',:'u_13',true),
       set_config('t.u_6a',:'u_6a',true),
       set_config('t.u_6',:'u_6',true),
       set_config('t.p_0',:'p_0',true),
       set_config('t.p_10',:'p_10',true),
       set_config('t.n7',:'n_prom_7',true),
       set_config('t.p_11',:'p_11',true),
       set_config('t.p_12',:'p_12',true),
       set_config('t.p_13',:'p_13',true),
       set_config('t.mfk',:'mfk',true),
       set_config('t.sb_11',:'sb_11',true),
       set_config('t.sr_11',:'sr_11',true),
       set_config('t.su_11',:'su_11',true),
       set_config('t.sp_11',:'sp_11',true),
       set_config('t.sb_12',:'sb_12',true),
       set_config('t.sr_12',:'sr_12',true),
       set_config('t.su_12',:'su_12',true),
       set_config('t.sp_12',:'sp_12',true),
       set_config('t.sb_13',:'sb_13',true),
       set_config('t.sr_13',:'sr_13',true),
       set_config('t.su_13',:'su_13',true),
       set_config('t.sp_13',:'sp_13',true),
       set_config('t.c_trg_off',:'c_trg_off',true),
       set_config('t.c_trg_new',:'c_trg_new',true),
       set_config('t.c_check',:'c_check',true),
       set_config('t.c_rls_off',:'c_rls_off',true),
       set_config('t.c_rls_force',:'c_rls_force',true),
       set_config('t.c_pol',:'c_pol',true),
       set_config('t.c_pol_role',:'c_pol_role',true),
       set_config('t.c_pol_cmd',:'c_pol_cmd',true),
       set_config('t.c_pol_perm',:'c_pol_perm',true) \g /dev/null
DO $$ DECLARE
  b0 jsonb := current_setting('t.b_0')::jsonb; p0 jsonb := current_setting('t.p_0')::jsonb;
  p10 jsonb := current_setting('t.p_10')::jsonb;
BEGIN
  IF b0->>'canonical_sha256' !~ '^[0-9a-f]{64}$' OR b0->>'clause_set_sha256' !~ '^[0-9a-f]{64}$'
     OR b0->>'schema_sha256' !~ '^[0-9a-f]{64}$' OR (b0->>'n_interpretations_src')::int <> 3 THEN
    RAISE EXCEPTION 'B0: baseline-form %', b0;
  END IF;
  -- B1: gentagelse => samme værdier (deterministisk).
  IF (current_setting('t.b_1')::jsonb - 'n_interpretations_src') IS DISTINCT FROM (b0 - 'n_interpretations_src') OR current_setting('t.r_1') IS DISTINCT FROM current_setting('t.r_0')
     OR current_setting('t.u_1') IS DISTINCT FROM current_setting('t.u_0') THEN RAISE EXCEPTION 'B1: ikke deterministisk'; END IF;
  -- B2: writer-profilrække flytter hverken baseline eller uberørt, men restore-hash.
  IF (current_setting('t.b_2')::jsonb - 'n_interpretations_src') IS DISTINCT FROM (b0 - 'n_interpretations_src') THEN RAISE EXCEPTION 'B2: baseline flyttet af profilrække'; END IF;
  IF current_setting('t.u_2') IS DISTINCT FROM current_setting('t.u_0') THEN RAISE EXCEPTION 'B2: uberørt flyttet af profilrække'; END IF;
  IF current_setting('t.r_2') IS NOT DISTINCT FROM current_setting('t.r_0') THEN RAISE EXCEPTION 'B2: restore-hash fangede ikke profilrækken'; END IF;
  -- B3: ændret assertion-værdi => canonical_sha256 ændres.
  IF current_setting('t.b_3')::jsonb->>'canonical_sha256' IS NOT DISTINCT FROM b0->>'canonical_sha256' THEN RAISE EXCEPTION 'B3: assertion-værdi ikke fanget'; END IF;
  -- B4: ændret identitet => canonical_sha256 ændres.
  IF current_setting('t.b_4')::jsonb->>'canonical_sha256' IS NOT DISTINCT FROM b0->>'canonical_sha256' THEN RAISE EXCEPTION 'B4: identitet ikke fanget'; END IF;
  -- B5: sekvens flytter restore-hash; en ekskluderet kædesekvens flytter ikke uberørt-hashen.
  IF current_setting('t.r_5') IS NOT DISTINCT FROM current_setting('t.r_0') THEN RAISE EXCEPTION 'B5: sekvens ikke fanget i restore-hash'; END IF;
  IF current_setting('t.u_5') IS DISTINCT FROM current_setting('t.u_0') THEN RAISE EXCEPTION 'B5: ekskluderet sekvens flyttede uberørt-hash'; END IF;
  -- B6b: sekvens uden for kæden (person-id) flytter uberørt-hashen.
  IF current_setting('t.u_6') IS NOT DISTINCT FROM current_setting('t.u_6a') THEN RAISE EXCEPTION 'B6b: ikke-kæde-sekvens ikke fanget i uberørt-hash'; END IF;
  -- B7: ægte afgørelse + binding.
  IF current_setting('t.n7')::int <> 1 THEN RAISE EXCEPTION 'B7: binding ikke skrevet (%)', current_setting('t.n7'); END IF;
  IF current_setting('t.u_7') IS DISTINCT FROM current_setting('t.u_0') THEN RAISE EXCEPTION 'B7: afgørelse/binding flyttede uberørt-hash (eksklusionslisten ufuldstændig)'; END IF;
  IF (current_setting('t.b_7')::jsonb - 'n_interpretations_src') IS DISTINCT FROM (b0 - 'n_interpretations_src') THEN RAISE EXCEPTION 'B7: afgørelse/binding flyttede baseline'; END IF;
  IF (current_setting('t.b_7')::jsonb->>'n_interpretations_src')::int <> 3 THEN RAISE EXCEPTION 'B7: forslagstal ændret af afgørelse'; END IF;
  IF current_setting('t.r_7') IS NOT DISTINCT FROM current_setting('t.r_0') THEN RAISE EXCEPTION 'B7: restore-hash fangede ikke afgørelse/binding'; END IF;
  -- B8: ny person uden for kæden flytter uberørt, restore og canonical.
  IF current_setting('t.u_8') IS NOT DISTINCT FROM current_setting('t.u_0') OR current_setting('t.r_8') IS NOT DISTINCT FROM current_setting('t.r_0')
     OR current_setting('t.b_8')::jsonb->>'canonical_sha256' IS NOT DISTINCT FROM b0->>'canonical_sha256' THEN RAISE EXCEPTION 'B8: ny person ikke fanget'; END IF;
  -- B9: nyt fact flytter canonical_sha256.
  IF current_setting('t.b_9')::jsonb->>'canonical_sha256' IS NOT DISTINCT FROM b0->>'canonical_sha256' THEN RAISE EXCEPTION 'B9: fact ikke fanget'; END IF;
  -- B6: 0 forældreløse i fixturen; kataloghash er sha256; flerkolonne-tal findes.
  IF (p0->>'n_orphans_total')::int <> 0 OR p0->'orphans' IS DISTINCT FROM '{}'::jsonb THEN RAISE EXCEPTION 'B6: falsk forældreløs %', p0; END IF;
  IF p0->>'catalog_sha256' !~ '^[0-9a-f]{64}$' OR (p0->>'n_multi_column_fks')::int IS DISTINCT FROM current_setting('t.mfk')::int THEN RAISE EXCEPTION 'B6: katalog %', p0; END IF;
  -- B11: samme hashes uanset sessionens TimeZone, extra_float_digits, IntervalStyle, DateStyle og search_path; kalderens værdier gendannes efter hver \\i.
  IF current_setting('t.b_11')::jsonb IS DISTINCT FROM current_setting('t.b_12')::jsonb OR current_setting('t.r_11') IS DISTINCT FROM current_setting('t.r_12')
     OR current_setting('t.u_11') IS DISTINCT FROM current_setting('t.u_12') OR current_setting('t.p_11')::jsonb IS DISTINCT FROM current_setting('t.p_12')::jsonb THEN
    RAISE EXCEPTION 'B11: hash afhænger af sessionsindstillinger'; END IF;
  IF current_setting('t.b_11')::jsonb IS DISTINCT FROM current_setting('t.b_13')::jsonb OR current_setting('t.r_11') IS DISTINCT FROM current_setting('t.r_13')
     OR current_setting('t.u_11') IS DISTINCT FROM current_setting('t.u_13') OR current_setting('t.p_11')::jsonb IS DISTINCT FROM current_setting('t.p_13')::jsonb THEN
    RAISE EXCEPTION 'B11: hash afhænger af sessionens standardindstillinger (ikke ens med kørsel uden SET; sekvenser rulles ikke tilbage, derfor sammenlignes med variant 13, ikke 0)'; END IF;
  IF current_setting('t.sb_11') <> 'Europe/Copenhagen|3|postgres|ISO, MDY|public|on' OR current_setting('t.sr_11') <> current_setting('t.sb_11')
     OR current_setting('t.su_11') <> current_setting('t.sb_11') OR current_setting('t.sp_11') <> current_setting('t.sb_11') THEN
    RAISE EXCEPTION 'B11: kalderens indstillinger ikke gendannet (a): % / % / % / %', current_setting('t.sb_11'), current_setting('t.sr_11'), current_setting('t.su_11'), current_setting('t.sp_11'); END IF;
  IF current_setting('t.sb_12') <> 'America/New_York|-1|sql_standard|German, DMY|public, extensions|off' OR current_setting('t.sr_12') <> current_setting('t.sb_12')
     OR current_setting('t.su_12') <> current_setting('t.sb_12') OR current_setting('t.sp_12') <> current_setting('t.sb_12') THEN
    RAISE EXCEPTION 'B11: kalderens indstillinger ikke gendannet (b): % / % / % / %', current_setting('t.sb_12'), current_setting('t.sr_12'), current_setting('t.su_12'), current_setting('t.sp_12'); END IF;
  -- B12: hver katalogændring flytter catalog_sha256; policyens rolle, kommando og art tæller hver for sig.
  IF EXISTS (SELECT 1 FROM unnest(ARRAY['c_trg_off','c_trg_new','c_check','c_rls_off','c_rls_force','c_pol']) v
              WHERE current_setting('t.'||v) IS NOT DISTINCT FROM p0->>'catalog_sha256') THEN
    RAISE EXCEPTION 'B12: katalogændring ikke fanget: %', (SELECT string_agg(v, ',') FROM unnest(ARRAY['c_trg_off','c_trg_new','c_check','c_rls_off','c_rls_force','c_pol']) v
              WHERE current_setting('t.'||v) IS NOT DISTINCT FROM p0->>'catalog_sha256'); END IF;
  IF EXISTS (SELECT 1 FROM unnest(ARRAY['c_pol_role','c_pol_cmd','c_pol_perm']) v
              WHERE current_setting('t.'||v) IS NOT DISTINCT FROM current_setting('t.c_pol')) THEN
    RAISE EXCEPTION 'B12: policy-felt ikke fanget: %', (SELECT string_agg(v, ',') FROM unnest(ARRAY['c_pol_role','c_pol_cmd','c_pol_perm']) v
              WHERE current_setting('t.'||v) IS NOT DISTINCT FROM current_setting('t.c_pol')); END IF;
  -- B10: en forældreløs række tælles.
  IF (p10->>'n_orphans_total')::int < 1 THEN RAISE EXCEPTION 'B10: forældreløs ikke talt %', p10; END IF;
  IF p10->>'catalog_sha256' IS DISTINCT FROM p0->>'catalog_sha256' THEN RAISE EXCEPTION 'B10: katalog afhænger af data'; END IF;
END $$;
\echo 'OK: transfer baseline'
ROLLBACK;
