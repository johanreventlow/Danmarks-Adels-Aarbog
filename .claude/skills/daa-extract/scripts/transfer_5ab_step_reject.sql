-- 5a+5b-skridt `reject` (sql; plan B1 Task 3a; beviskædens afvis-P.sql). Afviser det gældende relation.marriage, hvor
-- personaen er ægtefælle (party_role='spouse'), via red_decide_interpretation; målet slås op via persona_key, aldrig et
-- hårdkodet id. Præcis ét ægteskab pr. persona, ellers STEP_REJECT_AMBIGUOUS. Evidensen er
-- {basis:'human_sheet_review', sheet_sha256, sheet_line, reason, decided_on, report} (alle påkrævet).
-- capture læser [{persona_key, evidence}] fra :input; replay tager persona_key og evidens fra pakkens items.
-- items = [{persona_key, interpretation_key, version, evidence}].
-- Brug: psql -v src=<kilde> -v mode=capture|replay -v items=<sti> [-v input=<sti>] [-v fault=before_commit]
--       -f transfer_5ab_step_reject.sql
\set t5_step reject
\ir transfer_5ab_step_begin.sql
\if :t5_replay
SELECT current_setting('daa.t5_pack_items') AS t5_spec \gset
\else
\if :{?input}
\set t5_spec `cat :input`
\else
DO $$ BEGIN RAISE EXCEPTION 'STEP_USAGE: -v input mangler i capture'; END $$;
\endif
\endif
SELECT set_config('daa.t5_spec', :'t5_spec', true) \g /dev/null
DO $r$
DECLARE bad text;
BEGIN
  SELECT s->>'persona_key' INTO bad FROM jsonb_array_elements(current_setting('daa.t5_spec')::jsonb) s
   WHERE s->'evidence'->>'basis' IS DISTINCT FROM 'human_sheet_review'
      OR coalesce(s->'evidence'->>'sheet_sha256','') !~ '^[0-9a-f]{64}$'
      OR jsonb_typeof(s->'evidence'->'sheet_line') IS DISTINCT FROM 'number'
      OR nullif(btrim(s->'evidence'->>'reason'),'') IS NULL
      OR nullif(btrim(s->'evidence'->>'decided_on'),'') IS NULL
      OR nullif(btrim(s->'evidence'->>'report'),'') IS NULL
   LIMIT 1;
  IF FOUND THEN RAISE EXCEPTION 'STEP_REJECT_EVIDENCE_INVALID'; END IF;
END $r$;
WITH spec AS (
  SELECT s->>'persona_key' pk, s->'evidence' ev FROM jsonb_array_elements(:'t5_spec'::jsonb) s
), m AS (
  SELECT spec.pk, spec.ev, ic.id, ic.interpretation_key, ic.version
    FROM spec JOIN private.source_persona sp ON sp.source_id=:src AND sp.persona_key=spec.pk
    JOIN private.interpretation_party_current pc ON pc.source_persona_id=sp.id AND pc.party_role='spouse'
    JOIN private.interpretation_current ic ON ic.interpretation_key=pc.interpretation_key AND ic.predicate='relation.marriage'
)
SELECT (SELECT count(*) FROM spec)=(SELECT count(*) FROM m) AND (SELECT count(DISTINCT pk) FROM m)=(SELECT count(*) FROM spec) AS t5_unique,
       (SELECT count(*) FROM spec) AS t5_n,
       set_config('daa.t5_items', coalesce((SELECT jsonb_agg(jsonb_build_object('persona_key', m.pk, 'interpretation_key', m.interpretation_key,
         'version', m.version, 'evidence', m.ev) ORDER BY m.pk COLLATE "C") FROM m), '[]')::text, true) AS t5_i,
       coalesce((SELECT jsonb_agg(jsonb_build_object('id', m.id, 'version', m.version, 'evidence', m.ev)) FROM m), '[]')::text AS t5_targets \gset
\if :t5_unique
\else
DO $$ BEGIN RAISE EXCEPTION 'STEP_REJECT_AMBIGUOUS'; END $$;
\endif
\ir transfer_5ab_step_items.sql
\ir transfer_5ab_step_compare.sql
SET LOCAL ROLE authenticated;
SELECT count(public.red_decide_interpretation((x->>'id')::uuid, (x->>'version')::integer, 'rejected', x->'evidence'))
  FROM jsonb_array_elements(:'t5_targets'::jsonb) x \g /dev/null
RESET ROLE;
\ir transfer_5ab_step_end.sql
