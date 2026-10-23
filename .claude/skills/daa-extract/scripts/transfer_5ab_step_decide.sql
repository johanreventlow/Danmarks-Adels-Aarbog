-- 5a+5b-skridt `decide` (hash_gated; plan B1 Task 3a). Items beregnes som ejer fra private.relation_decision_set(src)
-- (red_preview_relation_decisions fjerner items, schema.sql:16697) og nøgles: fortolkningens nøgle og version,
-- klassifikation, familie, numre og parterne som persona_key. set_sha256 genberegnes i basen (preview som authenticated)
-- og sendes til red_decide_relation_interpretations. 0 items ⇒ intet kald.
-- Brug: psql -v src=<kilde> -v mode=capture|replay -v items=<sti> [-v fault=before_commit] -f transfer_5ab_step_decide.sql
\set t5_step decide
\ir transfer_5ab_step_begin.sql
SELECT set_config('daa.t5_items', coalesce((SELECT jsonb_agg(x ORDER BY x->>'interpretation_key' COLLATE "C") FROM (
  SELECT jsonb_build_object(
    'interpretation_key', it#>>'{state,interpretation,interpretation_key}',
    'version', (it#>>'{state,interpretation,version}')::integer,
    'classification', it->>'classification',
    'family_id', (it#>>'{state,family,family_id}')::bigint,
    'book_ordinal', it#>'{state,book_ordinal}',
    'family_ordinal', it#>'{state,family_ordinal}',
    'parter', (SELECT coalesce(jsonb_agg(jsonb_build_object('party_role', p->>'party_role', 'persona_key', sp.persona_key,
                 'person_id', (p->>'canonical_person_id')::bigint)
               ORDER BY p->>'party_role' COLLATE "C", sp.persona_key COLLATE "C"), '[]')
                 FROM jsonb_array_elements(it#>'{state,parties}') p
                 LEFT JOIN private.source_persona sp ON sp.id=(p->>'source_persona_id')::uuid)) x
    FROM jsonb_array_elements(private.relation_decision_set(:src)->'items') it) s), '[]')::text, true) \g /dev/null
SELECT jsonb_array_length(current_setting('daa.t5_items')::jsonb) AS t5_n \gset
\ir transfer_5ab_step_items.sql
\ir transfer_5ab_step_compare.sql
SELECT :t5_n>0 AS t5_do \gset
\if :t5_do
SET LOCAL ROLE authenticated;
SELECT public.red_preview_relation_decisions(:src)->>'set_sha256' AS t5_set \gset
SELECT public.red_decide_relation_interpretations(:src, :'t5_set') \g /dev/null
RESET ROLE;
\endif
\ir transfer_5ab_step_end.sql
