-- #240 (decisions 2026-10-26), efter fix_240_saml.sql: afgør og bind de 7 ægteskaber fra kilden, som sammenlægningen
-- gjorde bindbare. Samme RPC'er som overførslens decide- og bind-skridt (transfer_5ab_step_decide.sql og
-- transfer_5ab_step_bind.sql), men i én transaktion og kun når beslutnings- og promotionsmængden er netop de 7
-- (FIX240_AEG_*). Efter dette skridt kan fix_240_saml.sql's change_set ikke længere fortrydes alene.
-- Brug: psql -X -At -v ON_ERROR_STOP=1 -v actor=<redaktør-uuid> -v src=1 -f fix_240_aegteskaber.sql
\set QUIET on
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL statement_timeout = '15min';
SELECT set_config('request.jwt.claim.sub', :'actor', true), set_config('fix240.src', :'src', true) \g /dev/null
CREATE TEMP TABLE fix240_par(n int, fuld bigint, tom bigint, a bigint, b bigint) ON COMMIT DROP;
INSERT INTO fix240_par VALUES (1,188,11,16,278),(2,282,256,373,425),(3,354,363,544,560),(4,361,371,558,575),(5,377,372,577,587);
-- De 7: ægteskabstolkninger fra kilden, hvor begge parter er identificeret til et af parrene.
CREATE TEMP TABLE fix240_aeg ON COMMIT DROP AS
SELECT DISTINCT ic.id, ic.interpretation_key, p.fuld
  FROM private.interpretation_current ic
  JOIN private.interpretation_party_current p1 ON p1.interpretation_key=ic.interpretation_key
  JOIN private.source_persona_identity i1 ON i1.source_persona_id=p1.source_persona_id AND i1.decision_status='accepted'
  JOIN private.interpretation_party_current p2 ON p2.interpretation_key=ic.interpretation_key AND p2.party_role<>p1.party_role
  JOIN private.source_persona_identity i2 ON i2.source_persona_id=p2.source_persona_id AND i2.decision_status='accepted'
  JOIN fix240_par p ON (i1.canonical_person_id,i2.canonical_person_id)=(p.a,p.b)
 WHERE ic.source_id=:src AND ic.predicate='relation.marriage';

DO $pre$
DECLARE v_items jsonb;
BEGIN
  IF public.current_rolle() IS DISTINCT FROM 'redaktion' THEN RAISE EXCEPTION 'FIX240_AEG_ROLE'; END IF;
  IF EXISTS (SELECT 1 FROM family WHERE id IN (SELECT tom FROM fix240_par)) THEN RAISE EXCEPTION 'FIX240_AEG_NOT_MERGED'; END IF;
  IF (SELECT count(*) FROM fix240_aeg)<>7
     OR EXISTS (SELECT 1 FROM fix240_aeg a JOIN private.interpretation_current ic ON ic.id=a.id WHERE ic.status<>'proposed')
    THEN RAISE EXCEPTION 'FIX240_AEG_SET'; END IF;
  -- Beslutningsmængden skal være netop de 7, hver i parrets samlede familie.
  v_items:=coalesce(private.relation_decision_set(current_setting('fix240.src')::bigint)->'items','[]'::jsonb);
  IF jsonb_array_length(v_items)<>7
     OR EXISTS (SELECT 1 FROM jsonb_array_elements(v_items) it
                 WHERE NOT EXISTS (SELECT 1 FROM fix240_aeg a
                                    WHERE a.interpretation_key=(it#>>'{state,interpretation,interpretation_key}')::uuid
                                      AND a.fuld=(it#>>'{state,family,family_id}')::bigint))
    THEN RAISE EXCEPTION 'FIX240_AEG_DECISION_SET'; END IF;
END $pre$;

SET LOCAL ROLE authenticated;
SELECT public.red_preview_relation_decisions(:src)->>'set_sha256' AS aeg_set \gset
SELECT public.red_decide_relation_interpretations(:src, :'aeg_set') AS aeg_decided \gset
RESET ROLE;

-- Promotion: kandidater som i bind-skridtet; de egnede skal være netop de 7, hver til parrets samlede familie.
SELECT coalesce(jsonb_agg(jsonb_build_object('interpretation_id', ic.id::text,
         'family_id', (private.relation_binding_state(ic.id)#>>'{family,family_id}')::bigint) ORDER BY ic.id::text COLLATE "C"), '[]')::text AS aeg_cand
  FROM private.interpretation_current ic
 WHERE ic.source_id=:src AND ic.status='accepted' AND ic.predicate IN ('relation.marriage','relation.parent','relation.child')
   AND private.relation_binding_state(ic.id) IS NOT NULL \gset
SET LOCAL ROLE authenticated;
SELECT public.red_preview_relation_promotions(:src, :'aeg_cand'::jsonb)::text AS aeg_pv \gset
RESET ROLE;
SELECT coalesce(jsonb_agg(jsonb_build_object('interpretation_id', it->>'interpretation_id', 'family_id', (it->>'family_id')::bigint)
         ORDER BY it->>'interpretation_id' COLLATE "C"), '[]')::text AS aeg_elig
  FROM jsonb_array_elements(:'aeg_pv'::jsonb->'items') it WHERE (it->>'eligible')::boolean \gset
SELECT set_config('fix240.decided', :'aeg_decided', true), set_config('fix240.elig', :'aeg_elig', true) \g /dev/null
DO $mid$
DECLARE v_elig jsonb:=current_setting('fix240.elig')::jsonb;
BEGIN
  IF current_setting('fix240.decided')::integer<>7 THEN RAISE EXCEPTION 'FIX240_AEG_DECIDED'; END IF;
  IF (SELECT count(*) FROM fix240_aeg a JOIN private.interpretation_current ic ON ic.interpretation_key=a.interpretation_key
       WHERE ic.status='accepted')<>7 THEN RAISE EXCEPTION 'FIX240_AEG_NOT_ACCEPTED'; END IF;
  IF jsonb_array_length(v_elig)<>7
     OR EXISTS (SELECT 1 FROM jsonb_array_elements(v_elig) it
                 WHERE NOT EXISTS (SELECT 1 FROM fix240_aeg a JOIN private.interpretation_current ic ON ic.interpretation_key=a.interpretation_key
                                    WHERE ic.id=(it->>'interpretation_id')::uuid AND a.fuld=(it->>'family_id')::bigint))
    THEN RAISE EXCEPTION 'FIX240_AEG_ELIGIBLE'; END IF;
END $mid$;
SET LOCAL ROLE authenticated;
SELECT public.red_preview_relation_promotions(:src, :'aeg_elig'::jsonb)->>'preview_sha256' AS aeg_pv2 \gset
SELECT public.red_promote_relation_interpretations_batch(:src, :'aeg_elig'::jsonb, :'aeg_pv2') \g /dev/null
RESET ROLE;

DO $post$
BEGIN
  IF (SELECT count(*) FROM fix240_aeg a
        JOIN private.interpretation_current ic ON ic.interpretation_key=a.interpretation_key AND ic.status='accepted'
        JOIN private.interpretation_promotion pr ON pr.interpretation_id=ic.id AND pr.target_type='family' AND pr.target_id=a.fuld)<>7
    THEN RAISE EXCEPTION 'FIX240_AEG_POST_PROMOTED'; END IF;
  IF jsonb_array_length(coalesce(private.relation_decision_set(current_setting('fix240.src')::bigint)->'items','[]'::jsonb))<>0
    THEN RAISE EXCEPTION 'FIX240_AEG_POST_DECISION_SET'; END IF;
END $post$;
COMMIT;
\echo AEGTESKABER_240_OK decided=:aeg_decided promoted=7
