-- Trin 5a: rækkefil til identitetsarket. Indeholder navne → 0600 under ~/.private/5a/.
SET default_transaction_read_only=on;
-- Indholds-id (#151, spec §4 pkt. 5): samme bytes på tværs af platforme (tidszone, søgesti, collation).
SET TimeZone='UTC';
SET search_path=pg_catalog,public,private,extensions;
WITH latest AS (
  SELECT id FROM private.source_persona_identity_candidate_run WHERE source_id=:source_id
   ORDER BY run_seq DESC LIMIT 1
), personas AS (
  SELECT p.id, p.source_id, p.persona_key, coalesce(i.version,0) AS version
    FROM private.source_persona p LEFT JOIN private.source_persona_identity i ON i.source_persona_id=p.id
   WHERE p.source_id=:source_id
     AND ((:'mode'='undecided' AND (i.source_persona_id IS NULL OR i.decision_status='proposed'))
       OR (:'mode'='list' AND p.id = ANY(string_to_array(:'personas',',')::uuid[])))
)
SELECT coalesce(jsonb_agg(jsonb_build_object(
  'source_persona_id',pe.id::text,'version',pe.version,'source_id',pe.source_id,'persona_key',pe.persona_key,
  'record_key',(SELECT sr.record_key FROM private.source_persona_mention spm
                  JOIN private.source_mention sm ON sm.id=spm.mention_id
                  JOIN private.source_observation so ON so.id=sm.observation_id
                  JOIN private.source_record_anchor_current ac ON ac.occurrence_id=so.occurrence_id AND ac.decision_status='accepted'
                  JOIN private.source_record sr ON sr.id=ac.source_record_id
                 WHERE spm.persona_id=pe.id ORDER BY spm.ordinal LIMIT 1),
  'mention_role',(SELECT spm.mention_role FROM private.source_persona_mention spm WHERE spm.persona_id=pe.id ORDER BY spm.ordinal LIMIT 1),
  'name',(SELECT ic.value #>> '{}' FROM private.interpretation_current ic WHERE ic.source_persona_id=pe.id AND ic.predicate='person.name'
           AND ic.status IN ('accepted','proposed') ORDER BY (ic.status='accepted') DESC, ic.interpretation_key LIMIT 1),
  'name_origin',NULL,
  'interpretations',coalesce((SELECT jsonb_agg(jsonb_build_object('predicate',ic.predicate,'status',ic.status,
       'value_text',CASE jsonb_typeof(ic.value) WHEN 'string' THEN ic.value #>> '{}' ELSE ic.value->>'raw' END) ORDER BY ic.predicate COLLATE "C",ic.interpretation_key)
     FROM private.interpretation_current ic WHERE ic.source_persona_id=pe.id AND ic.status IN ('accepted','proposed')),'[]'::jsonb),
  'run_id',(SELECT id::text FROM latest),
  'candidates',coalesce((SELECT jsonb_agg(jsonb_build_object('candidate_id',c.id::text,'rank',c.rank,'person_id',c.candidate_person_id,
       'person_name',p.visning_navn,'born',p.visning_foedt,'died',p.visning_doed,'score',c.score,'tier',c.tier,
       'signals',c.basis->'signals') ORDER BY c.rank)
     FROM private.source_persona_identity_candidate c JOIN public.person p ON p.id=c.candidate_person_id
     WHERE c.source_persona_id=pe.id AND c.run_id=(SELECT id FROM latest)),'[]'::jsonb)
) ORDER BY pe.id),'[]'::jsonb) FROM personas pe;
