-- #248 skridt 1 (decisions 2026-10-26): to ægtefæller i 2018-20 blev på GO 2's ægtefælleark (ark 9, 6ff659f4…) afgjort
-- `same` til en navnefælle — ægtefællen i det andet ægteskab i samme post. Projektejeren har afgjort begge mod bogen
-- (GO 248, ark 1556cec6…, svar F): ægtefællen er partneren i hovedpersonens ubundne familie (kandidat nr. 2).
--   Sag 1: Iwan Reventlow (94), 4°: ægtefælle 624 → 625; ægteskabet er bundet til familie 64, hører til familie 65.
--   Sag 2: Abel Reventlow (286), 2°: ægtefælle 744 → 745; ægteskabet er bundet til familie 193, hører til familie 194.
-- Skridtet afgør kun ægtefællerne igen med webfladens RPC. Den gamle binding holder derved op med at gælde, så
-- kildeteksten forsvinder fra den forkerte familie; bindingen til den rigtige familie kræver genåbning (rute A, #248)
-- og sker ikke her. Søskendeægteskaberne (3° på familie 64, 1° på familie 193) må ikke røres.
-- Forhåndsbetingelser `FIX248_PRE_*`, efterbetingelser `FIX248_POST_*`; én transaktion.
-- Brug: psql -X -At -v ON_ERROR_STOP=1 -v actor=<redaktør-uuid> -v src=1 -f fix_248_identitet.sql
\set QUIET on
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL statement_timeout = '15min';
SELECT set_config('request.jwt.claim.sub', :'actor', true), set_config('fix248.src', :'src', true) \g /dev/null

CREATE TEMP TABLE fix248 ON COMMIT DROP AS
SELECT * FROM (VALUES
  (1, '613f3d20-863c-5109-936b-95c91233c7a6'::uuid, '5e2c4e89-763c-5804-9587-230d09f6d4f9'::uuid, 94::bigint, 624::bigint, 625::bigint,
      64::bigint, 65::bigint, '664fdafb-266e-566f-b7cb-fc302778d6cb'::uuid, '0c785da9-3323-5f35-9e16-51dff01517f1'::uuid),
  (2, '7f9e119d-3c84-5c2f-9d5f-81e2e67a6893'::uuid, '07a3dfe2-ec4d-55ca-aa7d-66691b6b05b6'::uuid, 286::bigint, 744::bigint, 745::bigint,
      193::bigint, 194::bigint, '7bed0127-6980-554b-9aa8-77b2c56ec645'::uuid, '1db74c8b-33f4-501c-95f5-5382c37c3399'::uuid)
) v(linje, ik, sp, pp, bp, up, fid, ufid, cand_id, soeskende_ik);

-- Antal gældende bindinger (bundet tilstand = nuværende) og offentlige kilderækker for en familie.
CREATE FUNCTION pg_temp.gaeldende(p_ik uuid) RETURNS bigint LANGUAGE sql STABLE AS $f$
  SELECT count(*) FROM private.interpretation_current ic JOIN private.interpretation_promotion x
      ON x.interpretation_id=ic.id AND x.target_type='family'
   WHERE ic.interpretation_key=p_ik
     AND x.evidence->>'state_sha256'=private.reimport_canonical_json_sha256(private.relation_binding_state(ic.id)) $f$;
CREATE FUNCTION pg_temp.kilder(p_fam bigint, p_person bigint) RETURNS bigint LANGUAGE sql STABLE AS $f$
  SELECT count(*) FROM public.public_family_sources(ARRAY[p_fam]) s WHERE s.counterpart_person_id=p_person $f$;

DO $pre$
DECLARE r record; v_src bigint:=current_setting('fix248.src')::bigint;
BEGIN
  IF public.current_rolle() IS DISTINCT FROM 'redaktion' THEN RAISE EXCEPTION 'FIX248_PRE_ROLE'; END IF;
  IF jsonb_array_length(coalesce(private.relation_decision_set(v_src)->'items','[]'::jsonb))<>0 THEN RAISE EXCEPTION 'FIX248_PRE_DECISION_SET'; END IF;
  FOR r IN SELECT * FROM fix248 ORDER BY linje LOOP
    -- Identiteten er GO 2's afgørelse (version 1, ark 9) til den forkerte navnefælle.
    IF NOT EXISTS (SELECT 1 FROM private.source_persona_identity i JOIN private.source_persona p ON p.id=i.source_persona_id
                    WHERE i.source_persona_id=r.sp AND p.source_id=v_src AND i.version=1 AND i.decision_status='accepted'
                      AND i.canonical_person_id=r.bp AND left(i.evidence->>'sheet_sha256',8)='6ff659f4') THEN
      RAISE EXCEPTION 'FIX248_PRE_IDENTITY linje %', r.linje; END IF;
    -- Den rigtige er kandidat nr. 2 i den gældende kandidatkørsel; personaen er ikke i en kontrolstikprøve.
    IF NOT EXISTS (SELECT 1 FROM private.source_persona_identity_candidate c
                    WHERE c.id=r.cand_id AND c.source_persona_id=r.sp AND c.candidate_person_id=r.up AND c.rank=2
                      AND c.run_id=(SELECT id FROM private.source_persona_identity_candidate_run WHERE source_id=v_src ORDER BY run_seq DESC LIMIT 1)) THEN
      RAISE EXCEPTION 'FIX248_PRE_CANDIDATE linje %', r.linje; END IF;
    IF EXISTS (SELECT 1 FROM private.identity_control_sample WHERE source_persona_id=r.sp) THEN RAISE EXCEPTION 'FIX248_PRE_CONTROL linje %', r.linje; END IF;
    -- Familierne: hovedpersonen med den forkerte hhv. den rigtige ægtefælle.
    IF (SELECT array_agg(person_id ORDER BY person_id) FROM public.family_member WHERE family_id=r.fid AND rolle='partner') IS DISTINCT FROM ARRAY[least(r.pp,r.bp),greatest(r.pp,r.bp)]
       OR (SELECT array_agg(person_id ORDER BY person_id) FROM public.family_member WHERE family_id=r.ufid AND rolle='partner') IS DISTINCT FROM ARRAY[least(r.pp,r.up),greatest(r.pp,r.up)]
      THEN RAISE EXCEPTION 'FIX248_PRE_FAMILIES linje %', r.linje; END IF;
    -- Ægteskabet: accepteret, tilstand på den forkerte familie, én gældende binding; søskendeægteskabet ligeså.
    IF (SELECT (private.relation_binding_state(ic.id)#>>'{family,family_id}')::bigint FROM private.interpretation_current ic
         WHERE ic.interpretation_key=r.ik AND ic.status='accepted' AND ic.predicate='relation.marriage') IS DISTINCT FROM r.fid
       OR pg_temp.gaeldende(r.ik)<>1 THEN RAISE EXCEPTION 'FIX248_PRE_MARRIAGE linje %', r.linje; END IF;
    IF (SELECT (private.relation_binding_state(ic.id)#>>'{family,family_id}')::bigint FROM private.interpretation_current ic
         WHERE ic.interpretation_key=r.soeskende_ik AND ic.status='accepted') IS DISTINCT FROM r.fid
       OR pg_temp.gaeldende(r.soeskende_ik)<>1 THEN RAISE EXCEPTION 'FIX248_PRE_SIBLING linje %', r.linje; END IF;
    -- Læseren viser i dag begge ægteskabers kildetekst på den forkerte familie, ingen på den rigtige.
    IF pg_temp.kilder(r.fid, r.bp)<>2 OR pg_temp.kilder(r.ufid, r.up)<>0 THEN RAISE EXCEPTION 'FIX248_PRE_SOURCES linje %', r.linje; END IF;
  END LOOP;
END $pre$;

SET LOCAL ROLE authenticated;
SELECT public.red_afgoer_source_persona('5e2c4e89-763c-5804-9587-230d09f6d4f9'::uuid, 1, 'same', 625,
  '#248: navnefælle; bogens 4° er datter af Nicolaus til Rastorf, † 1594 (DAA 1930, II, 105) — GO 248',
  jsonb_build_object('basis','human_sheet','line',1,
    'sheet_sha256','1556cec66746b767a26c1b95135e37d2880303cfaa6dc123d283ee6135e9d764',
    'rows_sha256','e43be6b471a9caccf05af3ff6f48da4f311386f35b12a1a8c326db849e540c32',
    'candidate_id','664fdafb-266e-566f-b7cb-fc302778d6cb','run_id','2f229043-fab8-5c7e-b43f-ecce7464fe58')) \g /dev/null
SELECT public.red_afgoer_source_persona('07a3dfe2-ec4d-55ca-aa7d-66691b6b05b6'::uuid, 1, 'same', 745,
  '#248: navnefælle; bogens 2° er Hans von Rantzau til Putlos, * ca. 1685, † 1744 (DAA 1930, II, 120) — GO 248',
  jsonb_build_object('basis','human_sheet','line',2,
    'sheet_sha256','1556cec66746b767a26c1b95135e37d2880303cfaa6dc123d283ee6135e9d764',
    'rows_sha256','e43be6b471a9caccf05af3ff6f48da4f311386f35b12a1a8c326db849e540c32',
    'candidate_id','7bed0127-6980-554b-9aa8-77b2c56ec645','run_id','2f229043-fab8-5c7e-b43f-ecce7464fe58')) \g /dev/null
RESET ROLE;

DO $post$
DECLARE r record; v_src bigint:=current_setting('fix248.src')::bigint;
BEGIN
  FOR r IN SELECT * FROM fix248 ORDER BY linje LOOP
    IF NOT EXISTS (SELECT 1 FROM private.source_persona_identity i
                    WHERE i.source_persona_id=r.sp AND i.version=2 AND i.decision_status='accepted' AND i.canonical_person_id=r.up
                      AND i.evidence->>'sheet_sha256'='1556cec66746b767a26c1b95135e37d2880303cfaa6dc123d283ee6135e9d764'
                      AND (i.evidence->>'line')::int=r.linje AND (i.evidence->>'candidate_rank')::int=2) THEN
      RAISE EXCEPTION 'FIX248_POST_IDENTITY linje %', r.linje; END IF;
    IF (SELECT (private.relation_binding_state(ic.id)#>>'{family,family_id}')::bigint FROM private.interpretation_current ic
         WHERE ic.interpretation_key=r.ik AND ic.status='accepted') IS DISTINCT FROM r.ufid
       OR pg_temp.gaeldende(r.ik)<>0 THEN RAISE EXCEPTION 'FIX248_POST_MARRIAGE linje %', r.linje; END IF;
    IF (SELECT (private.relation_binding_state(ic.id)#>>'{family,family_id}')::bigint FROM private.interpretation_current ic
         WHERE ic.interpretation_key=r.soeskende_ik AND ic.status='accepted') IS DISTINCT FROM r.fid
       OR pg_temp.gaeldende(r.soeskende_ik)<>1 THEN RAISE EXCEPTION 'FIX248_POST_SIBLING linje %', r.linje; END IF;
    IF pg_temp.kilder(r.fid, r.bp)<>1 OR pg_temp.kilder(r.ufid, r.up)<>0 THEN RAISE EXCEPTION 'FIX248_POST_SOURCES linje %', r.linje; END IF;
  END LOOP;
  IF jsonb_array_length(coalesce(private.relation_decision_set(v_src)->'items','[]'::jsonb))<>0 THEN RAISE EXCEPTION 'FIX248_POST_DECISION_SET'; END IF;
END $post$;
COMMIT;
\echo FIX248_IDENTITET_OK identiteter=2 bindinger_ophoert=2 soeskende_uroert=2
