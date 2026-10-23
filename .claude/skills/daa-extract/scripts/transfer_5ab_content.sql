-- Indholdskontrollens projektion for 5a+5b-overførslen (plan B2 Task 2, spec §6.3). Læse-kun; ingen CREATE.
-- Kun gældende rækker, nøglet på indhold, uden tilfældige id'er, arkhashes og aktør, så en bevisbase og arbejdskørslen kan
-- sammenlignes linje for linje (transfer_5ab_content_check.py). Lag:
--   binding        <interpretation_key>:<target_type>:<target_id>  {rule_key, rule_version, current, superseded_n}
--                  (ikke-overtrufne bindinger; current = bundet til fortolkningens gældende version; superseded_n = antal
--                  bindinger, den selv har overtrumfet — en genbinding som #244's ser dermed anderledes ud end en direkte)
--   ordinal        <interpretation_key>:<party_role>:<persona_key> {marriage_ordinal}          (gældende partversion)
--   identity       <persona_key>                                   {status, person_id}
--   origin         <persona_key>                                   {origin, method, batch}
--   classification <interpretation_key>:<seq>                      {classification}
--   interpretation <interpretation_key>                            {status, predicate}         (gældende version)
--   disposition    <observation_id>                                {disposition}               (gældende version)
--   family_source  <family_id>:<slags>:<kildepost>:<modpart>       rækken, som anon ser den
--   persona        <persona_key>                                   {n_mentions}
-- Udskrift: linjer »<lag>|<nøgle>|<værdi-json>« sorteret COLLATE "C". Nøglerne bærer uuid'er (interpretation_key,
-- observation_id): kalderen skriver dem til en 0600-fil, aldrig til terminalen.
-- Brug: psql -At -v src=<kilde> -f transfer_5ab_content.sql > <fil>
\set ON_ERROR_STOP on
\if :{?src}
\else
DO $$ BEGIN RAISE EXCEPTION 'STEP_USAGE: -v src mangler'; END $$;
\endif
BEGIN READ ONLY;
SET LOCAL search_path TO pg_catalog;
SET LOCAL TimeZone='UTC';
SET LOCAL DateStyle='ISO, MDY';
SET LOCAL IntervalStyle='postgres';
SET LOCAL extra_float_digits=1;
SET LOCAL row_security=off;
-- Familiekilderne som læseren ser dem: familierne er mål for kildens bindinger; kaldet sker som anon.
SELECT coalesce(array_agg(DISTINCT p.target_id ORDER BY p.target_id), '{}')::text AS t5_fam
  FROM private.interpretation_promotion p JOIN private.interpretation i ON i.id=p.interpretation_id
 WHERE i.source_id=:src AND p.target_type='family' \gset
SET LOCAL ROLE anon;
SELECT coalesce(jsonb_agg(to_jsonb(f)), '[]')::text AS t5_famj FROM public.public_family_sources(:'t5_fam'::bigint[]) f \gset
RESET ROLE;
WITH ip AS (SELECT i.id, i.interpretation_key FROM private.interpretation i WHERE i.source_id=:src),
sp AS (SELECT p.id, p.persona_key FROM private.source_persona p WHERE p.source_id=:src),
rows(lag, k, v) AS (
  SELECT 'binding', ip.interpretation_key||':'||p.target_type||':'||p.target_id,
         jsonb_build_object('rule_key', p.rule_key, 'rule_version', p.rule_version,
           'current', EXISTS (SELECT 1 FROM private.interpretation_current cur WHERE cur.id=p.interpretation_id),
           'superseded_n', (SELECT count(*) FROM private.interpretation_promotion o WHERE p.evidence->>'supersedes_promotion_id'=o.id::text))
    FROM private.interpretation_promotion p JOIN ip ON ip.id=p.interpretation_id
   WHERE NOT EXISTS (SELECT 1 FROM private.interpretation_promotion n WHERE n.evidence->>'supersedes_promotion_id'=p.id::text)
  UNION ALL
  SELECT 'ordinal', pc.interpretation_key||':'||pc.party_role||':'||sp.persona_key, jsonb_build_object('marriage_ordinal', pc.marriage_ordinal)
    FROM private.interpretation_party_current pc JOIN sp ON sp.id=pc.source_persona_id
   WHERE pc.interpretation_key IN (SELECT interpretation_key FROM ip)
  UNION ALL
  SELECT 'identity', sp.persona_key, jsonb_build_object('status', i.decision_status, 'person_id', i.canonical_person_id)
    FROM private.source_persona_identity i JOIN sp ON sp.id=i.source_persona_id
  UNION ALL
  SELECT 'origin', sp.persona_key,
         jsonb_build_object('origin', coalesce(i.evidence->>'origin', i.evidence->>'basis', i.evidence->>'authority'),
           'method', i.evidence->>'method', 'batch', i.evidence ? 'batch_id')
    FROM private.source_persona_identity i JOIN sp ON sp.id=i.source_persona_id
  UNION ALL
  SELECT 'classification', e.interpretation_key||':'||e.seq, jsonb_build_object('classification', e.classification)
    FROM private.relation_classification_event e WHERE e.interpretation_key IN (SELECT interpretation_key FROM ip)
  UNION ALL
  SELECT 'interpretation', ic.interpretation_key::text, jsonb_build_object('status', ic.status, 'predicate', ic.predicate)
    FROM private.interpretation_current ic WHERE ic.source_id=:src
  UNION ALL
  SELECT 'disposition', d.observation_id::text, jsonb_build_object('disposition', d.disposition)
    FROM (SELECT DISTINCT ON (cd.observation_id) cd.observation_id, cd.disposition
            FROM private.clause_disposition cd JOIN private.source_observation o ON o.id=cd.observation_id
            JOIN private.source_record_occurrence oc ON oc.id=o.occurrence_id
            JOIN private.source_rendition rd ON rd.id=oc.rendition_id
           WHERE rd.source_id=:src ORDER BY cd.observation_id, cd.version DESC) d
  UNION ALL
  SELECT 'family_source', (x->>'family_id')||':'||(x->>'slags')||':'||coalesce(x->>'source_record_ref','-')||':'||
         coalesce(x->>'counterpart_person_id','-'), x
    FROM jsonb_array_elements(:'t5_famj'::jsonb) x
  UNION ALL
  SELECT 'persona', sp.persona_key, jsonb_build_object('n_mentions',
         (SELECT count(*) FROM private.source_persona_mention m WHERE m.persona_id=sp.id))
    FROM sp
)
SELECT lag||'|'||k||'|'||v::text FROM rows ORDER BY lag COLLATE "C", k COLLATE "C", v::text COLLATE "C";
COMMIT;
