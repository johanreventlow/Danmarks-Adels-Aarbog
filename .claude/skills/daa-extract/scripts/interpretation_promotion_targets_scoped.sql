-- Målfindingen afgrænset til overførselspakkens accepterede nøgler (spec 2026-10-03 §6.2, review runde 1 m8).
-- Den delte interpretation_promotion_targets.sql er uændret; denne fil filtrerer dens resultat.
-- Køres fra repo-roden (\i er relativ til arbejdsmappen).
-- Obligatorisk input: daa.transfer_scope = JSON-array af interpretation_key. Uden input: STOP.
-- Output: daa.targets_scoped = {"items":[…], "singleton_items":[…], "out_of_scope": n}.
-- out_of_scope tæller mål (items + singletons) for fortolkninger uden for pakken — fx andre kilders
-- accepterede, ubundne forslag. De bliver ikke items; kalderen afgør, om tallet er en fejl.
DO $s$ BEGIN
  IF coalesce(current_setting('daa.transfer_scope', true), '') = '' THEN
    RAISE EXCEPTION 'BIND_SCOPE_REQUIRED';
  END IF;
END $s$;
\i .claude/skills/daa-extract/scripts/interpretation_promotion_targets.sql
WITH t AS (SELECT current_setting('daa.targets_result')::jsonb AS j),
scope AS (SELECT jsonb_array_elements_text(current_setting('daa.transfer_scope')::jsonb) AS k),
tagged AS (
  SELECT g.grp, x.item, i.interpretation_key::text AS k
    FROM t CROSS JOIN LATERAL (VALUES ('items'), ('singleton_items')) g(grp)
    CROSS JOIN LATERAL jsonb_array_elements(t.j -> g.grp) x(item)
    JOIN private.interpretation i ON i.id = (x.item->>'interpretation_id')::uuid
)
SELECT set_config('daa.targets_scoped', jsonb_build_object(
  'items', coalesce((SELECT jsonb_agg(item ORDER BY k COLLATE "C") FROM tagged
                      WHERE grp = 'items' AND k IN (SELECT k FROM scope)), '[]'::jsonb),
  'singleton_items', coalesce((SELECT jsonb_agg(item ORDER BY k COLLATE "C") FROM tagged
                                WHERE grp = 'singleton_items' AND k IN (SELECT k FROM scope)), '[]'::jsonb),
  'out_of_scope', (SELECT count(*) FROM tagged WHERE k NOT IN (SELECT k FROM scope)))::text, false) AS targets_scoped;
