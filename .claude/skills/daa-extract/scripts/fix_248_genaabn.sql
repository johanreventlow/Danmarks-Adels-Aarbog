-- #248 rute A (decisions 2026-10-26, spec 2026-10-26-248-genaabning-ved-familieskift-design.md), efter skridt 1
-- (fix_248_identitet.sql) og genåbnings-blokkens DDL: de to ægteskaber, hvis ægtefælle GO 248 afgjorde igen, står
-- `accepted` for den forkerte familie uden gældende binding. De genåbnes med red_genaabn_relation_interpretation
-- (GO 248's arkkontekst), afgøres med red_decide_relation_interpretations og bindes til den rigtige familie med
-- red_promote_relation_interpretations_batch — samme RPC'er som overførslen, i én transaktion og kun når beslutnings-
-- og promotionsmængden er netop de to.
--   Sag 1: person 94, 4°: afgjort for familie 64, bindes til familie 65.
--   Sag 2: person 286, 2°: afgjort for familie 193, bindes til familie 194.
-- Søskendeægteskaberne (3° på familie 64, 1° på familie 193) må ikke røres.
-- Forhåndsbetingelser `FIX248A_PRE_*`, efterbetingelser `FIX248A_POST_*`; én transaktion.
-- Brug: psql -X -At -v ON_ERROR_STOP=1 -v actor=<redaktør-uuid> -v src=1 -f fix_248_genaabn.sql
\set QUIET on
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL statement_timeout = '15min';
SELECT set_config('request.jwt.claim.sub', :'actor', true), set_config('fix248.src', :'src', true) \g /dev/null

-- version = den accepterede versions nummer efter skridt 1; gammel_id/gammel_binding udfyldes af forhåndsbetingelserne.
CREATE TEMP TABLE fix248 ON COMMIT DROP AS
SELECT *, NULL::uuid gammel_id, NULL::uuid gammel_binding FROM (VALUES
  (1, '613f3d20-863c-5109-936b-95c91233c7a6'::uuid, '5e2c4e89-763c-5804-9587-230d09f6d4f9'::uuid, 94::bigint, 624::bigint, 625::bigint,
      64::bigint, 65::bigint, '0c785da9-3323-5f35-9e16-51dff01517f1'::uuid, 2),
  (2, '7f9e119d-3c84-5c2f-9d5f-81e2e67a6893'::uuid, '07a3dfe2-ec4d-55ca-aa7d-66691b6b05b6'::uuid, 286::bigint, 744::bigint, 745::bigint,
      193::bigint, 194::bigint, '1db74c8b-33f4-501c-95f5-5382c37c3399'::uuid, 2)
) v(linje, ik, sp, pp, bp, up, fid, ufid, soeskende_ik, version);

-- Antal gældende bindinger (bundet tilstand = nuværende), evt. kun til én familie, og offentlige kilderækker for en familie.
CREATE FUNCTION pg_temp.gaeldende(p_ik uuid, p_fam bigint DEFAULT NULL) RETURNS bigint LANGUAGE sql STABLE AS $f$
  SELECT count(*) FROM private.interpretation_current ic JOIN private.interpretation_promotion x
      ON x.interpretation_id=ic.id AND x.target_type='family'
   WHERE ic.interpretation_key=p_ik AND (p_fam IS NULL OR x.target_id=p_fam)
     AND x.evidence->>'state_sha256'=private.reimport_canonical_json_sha256(private.relation_binding_state(ic.id)) $f$;
CREATE FUNCTION pg_temp.kilder(p_fam bigint, p_person bigint) RETURNS bigint LANGUAGE sql STABLE AS $f$
  SELECT count(*) FROM public.public_family_sources(ARRAY[p_fam]) s WHERE s.counterpart_person_id=p_person $f$;
CREATE FUNCTION pg_temp.tilstand_fam(p_ik uuid) RETURNS bigint LANGUAGE sql STABLE AS $f$
  SELECT (private.relation_binding_state(ic.id)#>>'{family,family_id}')::bigint FROM private.interpretation_current ic
   WHERE ic.interpretation_key=p_ik AND ic.status='accepted' $f$;

DO $pre$
DECLARE r record; v_src bigint:=current_setting('fix248.src')::bigint; v_ic private.interpretation_current%ROWTYPE;
  v_last uuid; v_last_fam bigint;
BEGIN
  IF public.current_rolle() IS DISTINCT FROM 'redaktion' THEN RAISE EXCEPTION 'FIX248A_PRE_ROLE'; END IF;
  IF to_regprocedure('public.red_genaabn_relation_interpretation(uuid,integer,text,jsonb)') IS NULL
     OR to_regclass('private.relation_reopen') IS NULL THEN RAISE EXCEPTION 'FIX248A_PRE_DDL'; END IF;
  IF jsonb_array_length(coalesce(private.relation_decision_set(v_src)->'items','[]'::jsonb))<>0 THEN RAISE EXCEPTION 'FIX248A_PRE_DECISION_SET'; END IF;
  FOR r IN SELECT * FROM fix248 ORDER BY linje LOOP
    -- Skridt 1 er sket: ægtefællen er afgjort til den rigtige (version 2).
    IF NOT EXISTS (SELECT 1 FROM private.source_persona_identity i
                    WHERE i.source_persona_id=r.sp AND i.version=2 AND i.decision_status='accepted' AND i.canonical_person_id=r.up
                      AND i.evidence->>'sheet_sha256'='1556cec66746b767a26c1b95135e37d2880303cfaa6dc123d283ee6135e9d764'
                      AND (i.evidence->>'line')::int=r.linje AND (i.evidence->>'candidate_rank')::int=2) THEN
      RAISE EXCEPTION 'FIX248A_PRE_IDENTITY linje %', r.linje; END IF;
    -- Familierne: hovedpersonen med den forkerte hhv. den rigtige ægtefælle (som skridt 1). Sammen med tilstandens
    -- familie (nedenfor) binder det både hovedperson og ægtefælle.
    IF (SELECT array_agg(person_id ORDER BY person_id) FROM public.family_member WHERE family_id=r.fid AND rolle='partner') IS DISTINCT FROM ARRAY[least(r.pp,r.bp),greatest(r.pp,r.bp)]
       OR (SELECT array_agg(person_id ORDER BY person_id) FROM public.family_member WHERE family_id=r.ufid AND rolle='partner') IS DISTINCT FROM ARRAY[least(r.pp,r.up),greatest(r.pp,r.up)]
      THEN RAISE EXCEPTION 'FIX248A_PRE_FAMILIES linje %', r.linje; END IF;
    -- Ægteskabet: gældende version accepteret med familiestrukturen for den forkerte familie.
    SELECT * INTO v_ic FROM private.interpretation_current ic WHERE ic.interpretation_key=r.ik;
    IF v_ic.id IS NULL OR v_ic.source_id<>v_src OR v_ic.predicate<>'relation.marriage' OR v_ic.status<>'accepted'
       OR v_ic.version<>r.version OR v_ic.decision_evidence->>'method' IS DISTINCT FROM 'family-structure-v1'
       OR (v_ic.decision_evidence->>'family_id')::bigint IS DISTINCT FROM r.fid THEN
      RAISE EXCEPTION 'FIX248A_PRE_MARRIAGE linje %', r.linje; END IF;
    -- Tilstanden peger på den rigtige familie; ingen gældende binding; seneste binding er til den forkerte.
    IF pg_temp.tilstand_fam(r.ik) IS DISTINCT FROM r.ufid OR pg_temp.gaeldende(r.ik)<>0 THEN
      RAISE EXCEPTION 'FIX248A_PRE_STATE linje %', r.linje; END IF;
    SELECT p.id,p.target_id INTO v_last,v_last_fam FROM private.interpretation_promotion p
     WHERE p.interpretation_id=v_ic.id AND p.target_type='family' ORDER BY p.promoted_at DESC,p.id DESC LIMIT 1;
    IF v_last IS NULL OR v_last_fam IS DISTINCT FROM r.fid THEN RAISE EXCEPTION 'FIX248A_PRE_BINDING linje %', r.linje; END IF;
    IF EXISTS (SELECT 1 FROM private.relation_reopen WHERE interpretation_key=r.ik) THEN RAISE EXCEPTION 'FIX248A_PRE_REOPENED linje %', r.linje; END IF;
    -- Søskendeægteskabet er bundet til den forkerte familie og bliver der.
    IF pg_temp.tilstand_fam(r.soeskende_ik) IS DISTINCT FROM r.fid OR pg_temp.gaeldende(r.soeskende_ik, r.fid)<>1 THEN
      RAISE EXCEPTION 'FIX248A_PRE_SIBLING linje %', r.linje; END IF;
    IF pg_temp.kilder(r.fid, r.bp)<>1 OR pg_temp.kilder(r.ufid, r.up)<>0 THEN RAISE EXCEPTION 'FIX248A_PRE_SOURCES linje %', r.linje; END IF;
    UPDATE fix248 SET gammel_id=v_ic.id, gammel_binding=v_last WHERE linje=r.linje;
  END LOOP;
END $pre$;

-- Genåbning: én ny proposed-version pr. ægteskab, med GO 248's ark som kontekst.
SELECT max(gammel_id::text) FILTER (WHERE linje=1) AS g1, max(gammel_id::text) FILTER (WHERE linje=2) AS g2 FROM fix248 \gset
SET LOCAL ROLE authenticated;
SELECT public.red_genaabn_relation_interpretation(:'g1'::uuid, 2,
  '#248 rute A: ægtefællen afgjort igen (GO 248); genåbnet for familie 65',
  jsonb_build_object('basis','human_sheet','line',1,
    'sheet_sha256','1556cec66746b767a26c1b95135e37d2880303cfaa6dc123d283ee6135e9d764',
    'rows_sha256','e43be6b471a9caccf05af3ff6f48da4f311386f35b12a1a8c326db849e540c32')) AS n1 \gset
SELECT public.red_genaabn_relation_interpretation(:'g2'::uuid, 2,
  '#248 rute A: ægtefællen afgjort igen (GO 248); genåbnet for familie 194',
  jsonb_build_object('basis','human_sheet','line',2,
    'sheet_sha256','1556cec66746b767a26c1b95135e37d2880303cfaa6dc123d283ee6135e9d764',
    'rows_sha256','e43be6b471a9caccf05af3ff6f48da4f311386f35b12a1a8c326db849e540c32')) AS n2 \gset
RESET ROLE;
SELECT set_config('fix248.n1', :'n1', true), set_config('fix248.n2', :'n2', true) \g /dev/null

-- Beslutningsmængden skal være netop de to, hver i den rigtige familie.
DO $mid1$
DECLARE v_items jsonb:=coalesce(private.relation_decision_set(current_setting('fix248.src')::bigint)->'items','[]'::jsonb);
BEGIN
  IF (SELECT count(*) FROM fix248 f JOIN private.interpretation_current ic ON ic.interpretation_key=f.ik
       WHERE ic.status='proposed' AND ic.version=f.version+1 AND ic.supersedes_id=f.gammel_id
         AND ic.id=current_setting('fix248.n'||f.linje)::uuid)<>2 THEN RAISE EXCEPTION 'FIX248A_MID_REOPENED'; END IF;
  IF jsonb_array_length(v_items)<>2
     OR EXISTS (SELECT 1 FROM jsonb_array_elements(v_items) it
                 WHERE NOT EXISTS (SELECT 1 FROM fix248 f
                                    WHERE f.ik=(it#>>'{state,interpretation,interpretation_key}')::uuid
                                      AND f.ufid=(it#>>'{state,family,family_id}')::bigint))
    THEN RAISE EXCEPTION 'FIX248A_MID_DECISION_SET'; END IF;
END $mid1$;

SET LOCAL ROLE authenticated;
SELECT public.red_preview_relation_decisions(:src)->>'set_sha256' AS g_set \gset
SELECT public.red_decide_relation_interpretations(:src, :'g_set') AS g_decided \gset
RESET ROLE;

-- Promotion: netop de to, hver til den rigtige familie; begge egnede og uden at erstatte en binding.
SELECT jsonb_agg(jsonb_build_object('interpretation_id', ic.id::text, 'family_id', f.ufid) ORDER BY ic.id::text COLLATE "C")::text AS g_items
  FROM fix248 f JOIN private.interpretation_current ic ON ic.interpretation_key=f.ik \gset
SET LOCAL ROLE authenticated;
SELECT public.red_preview_relation_promotions(:src, :'g_items'::jsonb)::text AS g_pv \gset
RESET ROLE;
SELECT set_config('fix248.decided', :'g_decided', true), set_config('fix248.pv', :'g_pv', true) \g /dev/null
DO $mid2$
DECLARE v_pv jsonb:=current_setting('fix248.pv')::jsonb;
BEGIN
  IF current_setting('fix248.decided')::integer<>2 THEN RAISE EXCEPTION 'FIX248A_MID_DECIDED'; END IF;
  IF (SELECT count(*) FROM fix248 f JOIN private.interpretation_current ic ON ic.interpretation_key=f.ik
       WHERE ic.status='accepted' AND ic.version=f.version+2 AND ic.supersedes_id=current_setting('fix248.n'||f.linje)::uuid
         AND ic.decision_evidence->>'method'='family-structure-v1' AND (ic.decision_evidence->>'family_id')::bigint=f.ufid)<>2
    THEN RAISE EXCEPTION 'FIX248A_MID_NOT_ACCEPTED'; END IF;
  IF jsonb_array_length(v_pv->'items')<>2
     OR EXISTS (SELECT 1 FROM jsonb_array_elements(v_pv->'items') it
                 WHERE NOT (it->>'eligible')::boolean OR it->>'supersedes_promotion_id' IS NOT NULL)
    THEN RAISE EXCEPTION 'FIX248A_MID_ELIGIBLE'; END IF;
END $mid2$;
SET LOCAL ROLE authenticated;
SELECT public.red_promote_relation_interpretations_batch(:src, :'g_items'::jsonb, :'g_pv'::jsonb->>'preview_sha256') \g /dev/null
RESET ROLE;

DO $post$
DECLARE r record; v_src bigint:=current_setting('fix248.src')::bigint;
BEGIN
  FOR r IN SELECT * FROM fix248 ORDER BY linje LOOP
    IF pg_temp.tilstand_fam(r.ik) IS DISTINCT FROM r.ufid OR pg_temp.gaeldende(r.ik)<>1 OR pg_temp.gaeldende(r.ik, r.ufid)<>1 THEN
      RAISE EXCEPTION 'FIX248A_POST_MARRIAGE linje %', r.linje; END IF;
    IF pg_temp.tilstand_fam(r.soeskende_ik) IS DISTINCT FROM r.fid OR pg_temp.gaeldende(r.soeskende_ik, r.fid)<>1 THEN
      RAISE EXCEPTION 'FIX248A_POST_SIBLING linje %', r.linje; END IF;
    IF pg_temp.kilder(r.fid, r.bp)<>1 OR pg_temp.kilder(r.ufid, r.up)<>1 THEN RAISE EXCEPTION 'FIX248A_POST_SOURCES linje %', r.linje; END IF;
    -- Proveniensen: én genåbning pr. ægteskab, der peger på den gamle binding og de to familier.
    IF (SELECT count(*) FROM private.relation_reopen o
         WHERE o.interpretation_key=r.ik AND o.from_interpretation_id=r.gammel_id AND o.superseded_promotion_id=r.gammel_binding
           AND o.to_interpretation_id=current_setting('fix248.n'||r.linje)::uuid AND o.from_family_id=r.fid AND o.to_family_id=r.ufid
           AND o.spouse_source_persona_id=r.sp AND o.spouse_identity_version=2)<>1
       OR (SELECT count(*) FROM private.relation_reopen o WHERE o.interpretation_key=r.ik)<>1 THEN
      RAISE EXCEPTION 'FIX248A_POST_REOPEN linje %', r.linje; END IF;
    -- 4° og 2° afviger ikke længere fra familiens ordinal: den nye afgørelse får ingen klassifikation.
    IF EXISTS (SELECT 1 FROM private.relation_classification_event e JOIN private.interpretation_current ic ON ic.id=e.interpretation_id
                WHERE ic.interpretation_key=r.ik) THEN RAISE EXCEPTION 'FIX248A_POST_CLASSIFICATION linje %', r.linje; END IF;
  END LOOP;
  IF jsonb_array_length(coalesce(private.relation_decision_set(v_src)->'items','[]'::jsonb))<>0 THEN RAISE EXCEPTION 'FIX248A_POST_DECISION_SET'; END IF;
END $post$;
COMMIT;
\echo FIX248A_GENAABN_OK genaabnet=2 afgjort=:g_decided bundet=2
