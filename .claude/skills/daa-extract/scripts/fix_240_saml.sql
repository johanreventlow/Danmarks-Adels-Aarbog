-- #240 (decisions 2026-10-26): læg hvert af de 5 par sammen i familien med børn. Ét change_set, én transaktion.
--   * den tomme families noter flyttes til familien med børn (indlæserens kildenoter bevares);
--   * den tomme families vielsespåstand (med sit citat: den anden ægtefælles post) flyttes til familiens vielse som
--     endnu et belæg; den valgte påstand i familiens konklusion er uændret. Påstanden slettes ikke (invariant 1);
--   * den tomme families konklusion og (nu påstandsløse) vielsesfaktum, partnerrækker og familie slettes.
-- Forhåndsbetingelserne stopper ved enhver afvigelse fra målingen (FIX240_PRE_*); efterbetingelserne tjekker
-- resultatet og change_event-antallet (FIX240_POST_*). Fortrydes med red_fortryd_change_set(<cs>) — men kun før
-- fix_240_aegteskaber.sql har afgjort ægteskaberne mod den samlede familie.
-- Brug: psql -X -At -v ON_ERROR_STOP=1 -v actor=<redaktør-uuid> -v src=1 -f fix_240_saml.sql
\set QUIET on
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL statement_timeout = '15min';
SELECT set_config('request.jwt.claim.sub', :'actor', true), set_config('fix240.src', :'src', true) \g /dev/null
CREATE TEMP TABLE fix240_par(n int, fuld bigint, tom bigint, a bigint, b bigint) ON COMMIT DROP;
INSERT INTO fix240_par VALUES (1,188,11,16,278),(2,282,256,373,425),(3,354,363,544,560),(4,361,371,558,575),(5,377,372,577,587);
-- Vielse-fakta: tom → fuld (par 2-5; par 1 har ingen).
CREATE TEMP TABLE fix240_fakta ON COMMIT DROP AS
SELECT p.n, tf.id AS tom_fakta, ff.id AS fuld_fakta
  FROM fix240_par p
  JOIN fact tf ON tf.subjekt_type='family' AND tf.subjekt_id=p.tom
  LEFT JOIN fact ff ON ff.subjekt_type='family' AND ff.subjekt_id=p.fuld AND ff.faktatype='vielse';

DO $pre$
DECLARE r record; v_status text; v_reason text;
BEGIN
  IF public.current_rolle() IS DISTINCT FROM 'redaktion' THEN RAISE EXCEPTION 'FIX240_PRE_ROLE'; END IF;
  FOR r IN SELECT * FROM fix240_par LOOP
    IF (SELECT count(*) FROM family WHERE id IN (r.fuld,r.tom))<>2 THEN RAISE EXCEPTION 'FIX240_PRE_FAMILY'; END IF;
    IF (SELECT array_agg(person_id ORDER BY person_id) FROM family_member WHERE family_id=r.fuld AND rolle='partner')
         IS DISTINCT FROM ARRAY[r.a,r.b]
       OR (SELECT array_agg(person_id ORDER BY person_id) FROM family_member WHERE family_id=r.tom AND rolle='partner')
         IS DISTINCT FROM ARRAY[r.a,r.b] THEN RAISE EXCEPTION 'FIX240_PRE_PARTNERS'; END IF;
    IF EXISTS (SELECT 1 FROM family_member WHERE family_id=r.tom AND rolle<>'partner') THEN RAISE EXCEPTION 'FIX240_PRE_CHILDREN'; END IF;
    IF EXISTS (SELECT 1 FROM family_member WHERE family_id IN (r.fuld,r.tom) AND rolle='partner' AND ordinal IS DISTINCT FROM 1)
      THEN RAISE EXCEPTION 'FIX240_PRE_ORDINAL'; END IF;
    IF (SELECT count(*) FROM family_member WHERE person_id IN (r.a,r.b) AND rolle='partner')<>4 THEN RAISE EXCEPTION 'FIX240_PRE_OTHER_UNIONS'; END IF;
    IF EXISTS (SELECT 1 FROM assertion WHERE (objekt_type='family' AND objekt_id=r.tom) OR (target_type='family' AND target_id=r.tom))
       OR EXISTS (SELECT 1 FROM conclusion WHERE target_type='family' AND target_id=r.tom)
       OR EXISTS (SELECT 1 FROM relation WHERE (subjekt_type='family' AND subjekt_id=r.tom) OR (objekt_type='family' AND objekt_id=r.tom))
       OR EXISTS (SELECT 1 FROM narrative WHERE subjekt_type='family' AND subjekt_id=r.tom)
       OR EXISTS (SELECT 1 FROM haendelse WHERE subjekt_type='family' AND subjekt_id=r.tom)
       OR EXISTS (SELECT 1 FROM story WHERE subjekt_type='family' AND subjekt_id=r.tom)
       OR EXISTS (SELECT 1 FROM suggestion WHERE subjekt_type='family' AND subjekt_id=r.tom)
       OR EXISTS (SELECT 1 FROM entity_description WHERE subjekt_type='family' AND subjekt_id=r.tom)
       OR EXISTS (SELECT 1 FROM private.interpretation_promotion WHERE target_type='family' AND target_id=r.tom)
       OR EXISTS (SELECT 1 FROM private.identity_control_parent_card WHERE family_id=r.tom)
       OR EXISTS (SELECT 1 FROM private.marriage_ordinal_correction WHERE family_id=r.tom)
      THEN RAISE EXCEPTION 'FIX240_PRE_REFERENCES'; END IF;
  END LOOP;
  IF (SELECT count(*) FROM fix240_fakta)<>4 OR EXISTS (SELECT 1 FROM fix240_fakta WHERE fuld_fakta IS NULL OR n=1)
     OR EXISTS (SELECT 1 FROM fix240_fakta x JOIN fact f ON f.id=x.tom_fakta WHERE f.faktatype<>'vielse')
    THEN RAISE EXCEPTION 'FIX240_PRE_FACTS'; END IF;
  -- Hvert vielsesfaktum (begge sider) har præcis én påstand med ét citat og en afklaret konklusion på den påstand.
  IF EXISTS (SELECT 1 FROM fix240_fakta x, LATERAL (VALUES (x.tom_fakta),(x.fuld_fakta)) v(f)
              WHERE (SELECT count(*) FROM assertion WHERE target_type='fact' AND target_id=v.f)<>1
                 OR (SELECT count(*) FROM citation c JOIN assertion a ON a.id=c.assertion_id WHERE a.target_type='fact' AND a.target_id=v.f)<>1
                 OR NOT EXISTS (SELECT 1 FROM conclusion c JOIN assertion a ON a.id=c.valgt_assertion_id
                                 WHERE c.target_type='fact' AND c.target_id=v.f AND c.status='afklaret' AND a.target_id=v.f))
    THEN RAISE EXCEPTION 'FIX240_PRE_EVIDENCE'; END IF;
  IF EXISTS (SELECT 1 FROM haendelse WHERE fact_id IN (SELECT tom_fakta FROM fix240_fakta))
     OR EXISTS (SELECT 1 FROM story WHERE fact_id IN (SELECT tom_fakta FROM fix240_fakta))
     OR EXISTS (SELECT 1 FROM note WHERE target_type='fact' AND target_id IN (SELECT tom_fakta FROM fix240_fakta))
     OR EXISTS (SELECT 1 FROM relation WHERE (subjekt_type='fact' AND subjekt_id IN (SELECT tom_fakta FROM fix240_fakta))
                                          OR (objekt_type='fact' AND objekt_id IN (SELECT tom_fakta FROM fix240_fakta)))
    THEN RAISE EXCEPTION 'FIX240_PRE_FACT_REFERENCES'; END IF;
  IF (SELECT count(*) FROM note WHERE target_type='family' AND target_id IN (SELECT tom FROM fix240_par))<>6 THEN
    RAISE EXCEPTION 'FIX240_PRE_NOTES'; END IF;
  FOR r IN SELECT id FROM private.identity_control_run WHERE source_id=current_setting('fix240.src')::bigint LOOP
    SELECT s.status,s.reason INTO v_status,v_reason FROM private.control_run_status(r.id) s;
    IF v_status IS DISTINCT FROM 'passed' THEN RAISE EXCEPTION 'FIX240_PRE_CONTROL_STATUS'; END IF;
  END LOOP;
END $pre$;

SELECT begin_change_set('fix_240_saml_dobbeltfamilier',
  '#240: 5 par samlet i familien med børn (noter og vielsespåstande flyttet, tomme familier fjernet)', NULL, NULL) AS cs \gset
CREATE TEMP TABLE fix240_valgt ON COMMIT DROP AS
SELECT x.fuld_fakta, c.valgt_assertion_id FROM fix240_fakta x JOIN conclusion c ON c.target_type='fact' AND c.target_id=x.fuld_fakta;

UPDATE note SET target_id=p.fuld FROM fix240_par p WHERE note.target_type='family' AND note.target_id=p.tom;
UPDATE assertion SET target_id=x.fuld_fakta FROM fix240_fakta x WHERE assertion.target_type='fact' AND assertion.target_id=x.tom_fakta;
DELETE FROM conclusion WHERE target_type='fact' AND target_id IN (SELECT tom_fakta FROM fix240_fakta);
DELETE FROM fact WHERE id IN (SELECT tom_fakta FROM fix240_fakta);
DELETE FROM family_member WHERE family_id IN (SELECT tom FROM fix240_par);
DELETE FROM family WHERE id IN (SELECT tom FROM fix240_par);

DO $post$
BEGIN
  IF EXISTS (SELECT 1 FROM family WHERE id IN (SELECT tom FROM fix240_par))
     OR EXISTS (SELECT 1 FROM family_member WHERE family_id IN (SELECT tom FROM fix240_par))
     OR EXISTS (SELECT 1 FROM fact WHERE id IN (SELECT tom_fakta FROM fix240_fakta)) THEN RAISE EXCEPTION 'FIX240_POST_LEFTOVER'; END IF;
  IF EXISTS (SELECT 1 FROM fix240_par p WHERE (SELECT count(*) FROM family_member WHERE person_id IN (p.a,p.b) AND rolle='partner')<>2) THEN
    RAISE EXCEPTION 'FIX240_POST_UNIONS'; END IF;
  IF EXISTS (SELECT 1 FROM fix240_fakta x
              WHERE (SELECT count(*) FROM fact WHERE subjekt_type='family' AND subjekt_id=(SELECT fuld FROM fix240_par p WHERE p.n=x.n) AND faktatype='vielse')<>1
                 OR (SELECT count(*) FROM assertion WHERE target_type='fact' AND target_id=x.fuld_fakta)<>2
                 OR (SELECT count(*) FROM citation c JOIN assertion a ON a.id=c.assertion_id WHERE a.target_type='fact' AND a.target_id=x.fuld_fakta)<>2) THEN
    RAISE EXCEPTION 'FIX240_POST_EVIDENCE'; END IF;
  IF EXISTS (SELECT 1 FROM fix240_valgt v JOIN conclusion c ON c.target_type='fact' AND c.target_id=v.fuld_fakta
              WHERE c.valgt_assertion_id IS DISTINCT FROM v.valgt_assertion_id OR c.status<>'afklaret')
     OR (SELECT count(*) FROM fix240_valgt)<>4 THEN RAISE EXCEPTION 'FIX240_POST_CONCLUSION'; END IF;
  IF (SELECT count(*) FROM note WHERE target_type='family' AND target_id IN (SELECT fuld FROM fix240_par))<>12 THEN
    RAISE EXCEPTION 'FIX240_POST_NOTES'; END IF;
  -- 6 noter + 4 påstande + 4 konklusioner + 4 fakta + 10 partnerrækker + 5 familier.
  IF (SELECT count(*) FROM change_event WHERE change_set_id=current_setting('app.change_set_id')::bigint)<>33 THEN
    RAISE EXCEPTION 'FIX240_POST_EVENTS'; END IF;
END $post$;
COMMIT;
\echo SAML_240_OK cs=:cs
