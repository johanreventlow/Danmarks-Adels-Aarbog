-- Opfølgning på dubletreglen (decisions 2026-10-25 og 2026-10-26): ret det ene ægteskab fra GO 2. Ægtefællen afgøres
-- igen til familiens post 753 (kandidat nr. 1 og i kontrolarkets dubletmængde `731=753`) med webfladens RPC; derefter
-- afgøres og promoveres netop det ene ægteskab til familie 202, med samme RPC'er som fix_240_aegteskaber.sql.
-- Kontrolstatus: en afgørelse inden for den nævnte dubletmængde er en afklaring (decisions 2026-10-25 punkt 3).
-- Forhåndsbetingelser `FIXDUB_PRE_*`, efterbetingelser `FIXDUB_POST_*`; én transaktion.
-- Brug: psql -X -At -v ON_ERROR_STOP=1 -v actor=<redaktør-uuid> -v src=1 -f fix_go2_dublet.sql
\set QUIET on
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL statement_timeout = '15min';
SELECT set_config('request.jwt.claim.sub', :'actor', true), set_config('fixdub.src', :'src', true) \g /dev/null
SELECT i.source_persona_id AS dub_sp, i.version AS dub_v
  FROM private.source_persona_identity i JOIN private.source_persona p ON p.id=i.source_persona_id
 WHERE p.source_id=:src AND i.decision_status='accepted' AND i.canonical_person_id=731
   AND EXISTS (SELECT 1 FROM private.source_persona_identity_event e WHERE e.source_persona_id=i.source_persona_id
                AND e.evidence->'same_individual_person_ids' @> '[731,753]'::jsonb) \gset
SELECT set_config('fixdub.sp', :'dub_sp', true), set_config('fixdub.v', :'dub_v', true) \g /dev/null

DO $pre$
DECLARE v_sp uuid:=current_setting('fixdub.sp')::uuid; v_src bigint:=current_setting('fixdub.src')::bigint;
BEGIN
  IF public.current_rolle() IS DISTINCT FROM 'redaktion' THEN RAISE EXCEPTION 'FIXDUB_PRE_ROLE'; END IF;
  IF (SELECT count(*) FROM private.source_persona_identity i JOIN private.source_persona p ON p.id=i.source_persona_id
       WHERE p.source_id=v_src AND i.decision_status='accepted'
         AND EXISTS (SELECT 1 FROM private.source_persona_identity_event e WHERE e.source_persona_id=i.source_persona_id
                      AND e.evidence ? 'same_individual_person_ids'))<>1 THEN RAISE EXCEPTION 'FIXDUB_PRE_PERSONA'; END IF;
  IF current_setting('fixdub.v')::integer<>1 THEN RAISE EXCEPTION 'FIXDUB_PRE_VERSION'; END IF;
  -- 753 er kandidat nr. 1 for personaen; 731 og 753 står hver i præcis én familie (179 og 202).
  IF NOT EXISTS (SELECT 1 FROM private.source_persona_identity_candidate c WHERE c.source_persona_id=v_sp
                  AND c.candidate_person_id=753 AND c.rank=1) THEN RAISE EXCEPTION 'FIXDUB_PRE_CANDIDATE'; END IF;
  IF (SELECT array_agg(person_id ORDER BY person_id) FROM family_member WHERE family_id=202 AND rolle='partner') IS DISTINCT FROM ARRAY[294,753]::bigint[]
     OR (SELECT array_agg(person_id ORDER BY person_id) FROM family_member WHERE family_id=179 AND rolle='partner') IS DISTINCT FROM ARRAY[261,731]::bigint[]
     OR (SELECT count(*) FROM family_member WHERE person_id IN (731,753) AND rolle='partner')<>2
    THEN RAISE EXCEPTION 'FIXDUB_PRE_FAMILIES'; END IF;
  -- Personaen indgår kun i ét ægteskab, som ægtefælle, ubundet og uden promotion; hovedpersonen er 294.
  IF (SELECT count(*) FROM private.interpretation_party_current WHERE source_persona_id=v_sp)<>1
     OR (SELECT count(*) FROM private.interpretation_party_current pc JOIN private.interpretation_current ic ON ic.interpretation_key=pc.interpretation_key
          WHERE pc.source_persona_id=v_sp AND pc.party_role='spouse' AND ic.predicate='relation.marriage' AND ic.status='proposed'
            AND private.relation_binding_state(ic.id) IS NULL
            AND NOT EXISTS (SELECT 1 FROM private.interpretation_promotion pr WHERE pr.interpretation_id=ic.id)
            AND EXISTS (SELECT 1 FROM private.interpretation_party_current pp JOIN private.source_persona_identity pi ON pi.source_persona_id=pp.source_persona_id
                         WHERE pp.interpretation_key=ic.interpretation_key AND pp.party_role='principal'
                           AND pi.decision_status='accepted' AND pi.canonical_person_id=294))<>1
    THEN RAISE EXCEPTION 'FIXDUB_PRE_MARRIAGE'; END IF;
  -- Kontrolkørslen er evalueret (ellers tillader den forseglede kørsel kun arkets afgørelser).
  IF (SELECT e.status FROM private.identity_control_event e JOIN private.identity_control_sample s ON s.control_run_id=e.control_run_id
       WHERE s.source_persona_id=v_sp ORDER BY e.seq DESC LIMIT 1) IS DISTINCT FROM 'passed' THEN RAISE EXCEPTION 'FIXDUB_PRE_CONTROL'; END IF;
  IF jsonb_array_length(coalesce(private.relation_decision_set(v_src)->'items','[]'::jsonb))<>0 THEN RAISE EXCEPTION 'FIXDUB_PRE_DECISION_SET'; END IF;
END $pre$;

SET LOCAL ROLE authenticated;
SELECT public.red_afgoer_source_persona(:'dub_sp', :dub_v, 'same', 753,
  'Dubletreglen (decisions 2026-10-25/26): familiens post i kontrolarkets dubletmængde', '{}'::jsonb) AS dub_ny \gset
RESET ROLE;

DO $mid$
DECLARE v_sp uuid:=current_setting('fixdub.sp')::uuid; v_items jsonb;
BEGIN
  IF (SELECT canonical_person_id FROM private.source_persona_identity WHERE source_persona_id=v_sp) IS DISTINCT FROM 753 THEN
    RAISE EXCEPTION 'FIXDUB_MID_IDENTITY'; END IF;
  v_items:=coalesce(private.relation_decision_set(current_setting('fixdub.src')::bigint)->'items','[]'::jsonb);
  IF jsonb_array_length(v_items)<>1 OR (v_items->0#>>'{state,family,family_id}')::bigint IS DISTINCT FROM 202
     OR NOT EXISTS (SELECT 1 FROM private.interpretation_party_current pc WHERE pc.source_persona_id=v_sp
                     AND pc.interpretation_key=(v_items->0#>>'{state,interpretation,interpretation_key}')::uuid)
    THEN RAISE EXCEPTION 'FIXDUB_MID_DECISION_SET'; END IF;
END $mid$;

SET LOCAL ROLE authenticated;
SELECT public.red_preview_relation_decisions(:src)->>'set_sha256' AS dub_set \gset
SELECT public.red_decide_relation_interpretations(:src, :'dub_set') AS dub_decided \gset
RESET ROLE;
SELECT coalesce(jsonb_agg(jsonb_build_object('interpretation_id', ic.id::text,
         'family_id', (private.relation_binding_state(ic.id)#>>'{family,family_id}')::bigint) ORDER BY ic.id::text COLLATE "C"), '[]')::text AS dub_cand
  FROM private.interpretation_current ic
 WHERE ic.source_id=:src AND ic.status='accepted' AND ic.predicate IN ('relation.marriage','relation.parent','relation.child')
   AND private.relation_binding_state(ic.id) IS NOT NULL \gset
SET LOCAL ROLE authenticated;
SELECT public.red_preview_relation_promotions(:src, :'dub_cand'::jsonb)::text AS dub_pv \gset
RESET ROLE;
SELECT coalesce(jsonb_agg(jsonb_build_object('interpretation_id', it->>'interpretation_id', 'family_id', (it->>'family_id')::bigint)
         ORDER BY it->>'interpretation_id' COLLATE "C"), '[]')::text AS dub_elig
  FROM jsonb_array_elements(:'dub_pv'::jsonb->'items') it WHERE (it->>'eligible')::boolean \gset
SELECT set_config('fixdub.decided', :'dub_decided', true), set_config('fixdub.elig', :'dub_elig', true) \g /dev/null
DO $elig$
DECLARE v_sp uuid:=current_setting('fixdub.sp')::uuid; v_elig jsonb:=current_setting('fixdub.elig')::jsonb;
BEGIN
  IF current_setting('fixdub.decided')::integer<>1 THEN RAISE EXCEPTION 'FIXDUB_DECIDED'; END IF;
  IF jsonb_array_length(v_elig)<>1 OR (v_elig->0->>'family_id')::bigint IS DISTINCT FROM 202
     OR NOT EXISTS (SELECT 1 FROM private.interpretation_party_current pc JOIN private.interpretation_current ic ON ic.interpretation_key=pc.interpretation_key
                     WHERE pc.source_persona_id=v_sp AND ic.id=(v_elig->0->>'interpretation_id')::uuid)
    THEN RAISE EXCEPTION 'FIXDUB_ELIGIBLE'; END IF;
END $elig$;
SET LOCAL ROLE authenticated;
SELECT public.red_preview_relation_promotions(:src, :'dub_elig'::jsonb)->>'preview_sha256' AS dub_pv2 \gset
SELECT public.red_promote_relation_interpretations_batch(:src, :'dub_elig'::jsonb, :'dub_pv2') \g /dev/null
RESET ROLE;

DO $post$
DECLARE v_sp uuid:=current_setting('fixdub.sp')::uuid;
BEGIN
  IF (SELECT count(*) FROM private.interpretation_party_current pc JOIN private.interpretation_current ic ON ic.interpretation_key=pc.interpretation_key
        JOIN private.interpretation_promotion pr ON pr.interpretation_id=ic.id AND pr.target_type='family' AND pr.target_id=202
       WHERE pc.source_persona_id=v_sp AND ic.status='accepted')<>1 THEN RAISE EXCEPTION 'FIXDUB_POST_PROMOTED'; END IF;
  IF jsonb_array_length(coalesce(private.relation_decision_set(current_setting('fixdub.src')::bigint)->'items','[]'::jsonb))<>0
    THEN RAISE EXCEPTION 'FIXDUB_POST_DECISION_SET'; END IF;
END $post$;
COMMIT;
\echo DUBLET_GO2_OK identitet=753 decided=:dub_decided promoted=1
