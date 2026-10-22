-- 5a+5b-skridt `bind` (hash_gated; plan B1 Task 3a). Kandidater = accepterede relation.marriage|parent|child med
-- bindingstilstand. Forløb (f244_bind, marriage-ordinal-244.sql): preview over alle → nøglede items (alle, også uegnede
-- med grund) → de egnede → nyt preview over de egnede → promote med det nye previews hash (promote regner previewet om
-- over p_items og stopper ved første uegnede, schema.sql:16878-16882). 0 egnede ⇒ intet kald (tom liste giver
-- RELATION_PROMOTION_ITEMS_INVALID). Replay: ens items ⇒ skriv; er hver af pakkens egnede nu ALREADY_APPLIED og resten
-- ens ⇒ n=0 already_applied=<k> uden kald; ellers STEP_ITEMS_MISMATCH.
-- Brug: psql -v src=<kilde> -v mode=capture|replay -v items=<sti> [-v fault=before_commit] -f transfer_5ab_step_bind.sql
\set t5_step bind
\ir transfer_5ab_step_begin.sql
SELECT coalesce(jsonb_agg(jsonb_build_object('interpretation_id', ic.id::text,
         'family_id', (private.relation_binding_state(ic.id)#>>'{family,family_id}')::bigint) ORDER BY ic.id::text COLLATE "C"), '[]')::text AS t5_cand
  FROM private.interpretation_current ic
 WHERE ic.source_id=:src AND ic.status='accepted' AND ic.predicate IN ('relation.marriage','relation.parent','relation.child')
   AND private.relation_binding_state(ic.id) IS NOT NULL \gset
SELECT jsonb_array_length(:'t5_cand'::jsonb)>0 AS t5_any \gset
\set t5_pv '{"items":[]}'
\if :t5_any
SET LOCAL ROLE authenticated;
SELECT public.red_preview_relation_promotions(:src, :'t5_cand'::jsonb)::text AS t5_pv \gset
RESET ROLE;
\endif
SELECT set_config('daa.t5_items', coalesce((SELECT jsonb_agg(x ORDER BY x->>'interpretation_key' COLLATE "C", (x->>'family_id')::bigint) FROM (
  SELECT jsonb_build_object('interpretation_key', i.interpretation_key, 'version', i.version, 'family_id', (it->>'family_id')::bigint,
    'rule_key', it->>'rule_key', 'rule_version', (it->>'rule_version')::integer, 'eligible', (it->>'eligible')::boolean,
    'reason_code', it->>'reason_code',
    'supersedes_key', (SELECT si.interpretation_key||'#'||si.version||':'||sp.target_type||':'||sp.target_id||':'||sp.rule_key||':'||sp.rule_version
                         FROM private.interpretation_promotion sp JOIN private.interpretation si ON si.id=sp.interpretation_id
                        WHERE sp.id=(it->>'supersedes_promotion_id')::uuid)) x
    FROM jsonb_array_elements(:'t5_pv'::jsonb->'items') it JOIN private.interpretation i ON i.id=(it->>'interpretation_id')::uuid) s),
  '[]')::text, true) \g /dev/null
\ir transfer_5ab_step_items.sql
SELECT set_config('daa.t5_bind_mode', 'write', true) \g /dev/null
\if :t5_replay
DO $c$
DECLARE base jsonb:=current_setting('daa.t5_items')::jsonb; pack jsonb:=current_setting('daa.t5_pack_items')::jsonb; applied jsonb;
BEGIN
  IF base IS NOT DISTINCT FROM pack THEN RETURN; END IF;
  SELECT coalesce(jsonb_agg(CASE WHEN (x->>'eligible')::boolean
           THEN x||'{"eligible":false,"reason_code":"RELATION_PROMOTION_ALREADY_APPLIED"}'::jsonb ELSE x END
           ORDER BY o), '[]') INTO applied FROM jsonb_array_elements(pack) WITH ORDINALITY e(x,o);
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(pack) x WHERE (x->>'eligible')::boolean) AND base=applied THEN
    PERFORM set_config('daa.t5_bind_mode', 'rerun', true);
  ELSE
    RAISE EXCEPTION 'STEP_ITEMS_MISMATCH bind';
  END IF;
END $c$;
\endif
SELECT coalesce(jsonb_agg(jsonb_build_object('interpretation_id', it->>'interpretation_id', 'family_id', (it->>'family_id')::bigint)
         ORDER BY it->>'interpretation_id' COLLATE "C"), '[]')::text AS t5_elig
  FROM jsonb_array_elements(:'t5_pv'::jsonb->'items') it WHERE (it->>'eligible')::boolean \gset
SELECT current_setting('daa.t5_bind_mode')='write' AND jsonb_array_length(:'t5_elig'::jsonb)>0 AS t5_do,
       CASE WHEN current_setting('daa.t5_bind_mode')='write' THEN jsonb_array_length(:'t5_elig'::jsonb) ELSE 0 END AS t5_n,
       CASE WHEN current_setting('daa.t5_bind_mode')='rerun'
            THEN ' already_applied='||(SELECT count(*) FROM jsonb_array_elements(current_setting('daa.t5_pack_items')::jsonb) x
                                         WHERE (x->>'eligible')::boolean) ELSE '' END AS t5_extra \gset
\if :t5_do
SET LOCAL ROLE authenticated;
SELECT public.red_preview_relation_promotions(:src, :'t5_elig'::jsonb)->>'preview_sha256' AS t5_pv2 \gset
SELECT public.red_promote_relation_interpretations_batch(:src, :'t5_elig'::jsonb, :'t5_pv2') \g /dev/null
RESET ROLE;
\endif
\ir transfer_5ab_step_end.sql
