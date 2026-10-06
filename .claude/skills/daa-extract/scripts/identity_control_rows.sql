-- Trin 5b: rækkefil til kontrolarket. Indeholder navne → 0600 under ~/.private/5b/.
\set ON_ERROR_STOP on
SET default_transaction_read_only=on;
BEGIN;
SELECT set_config('request.jwt.claim.sub', :'actor', true) IS NOT NULL AS ok \g /dev/null
SET LOCAL ROLE authenticated;
SELECT red_identity_control_sample(:'control_run_id'::uuid) AS smp \gset
RESET ROLE;
WITH ctl AS (SELECT * FROM private.identity_control_run WHERE id=:'control_run_id'::uuid),
smp AS (SELECT * FROM jsonb_to_recordset((:'smp'::jsonb)->'samples')
          AS x(sample_id uuid,sample_kind text,stratum text,source_persona_id uuid,interpretation_key uuid,
               interpretation_version int,identity_version int,mapping jsonb)),
person_view AS (
  SELECT p.id,p.visning_navn,p.visning_foedt,p.visning_doed,
    coalesce((SELECT jsonb_agg(DISTINCT a.vaerdi_tekst) FROM fact f JOIN conclusion k ON k.target_type='fact' AND k.target_id=f.id
               JOIN assertion a ON a.id=k.valgt_assertion_id WHERE f.subjekt_type='person' AND f.subjekt_id=p.id AND f.faktatype='titel'),'[]'::jsonb) AS titles,
    (SELECT sr.record_key FROM private.source_persona_identity i
       JOIN private.source_persona_mention spm ON spm.persona_id=i.source_persona_id AND spm.mention_role='primary'
       JOIN private.source_mention sm ON sm.id=spm.mention_id
       JOIN private.source_observation o ON o.id=sm.observation_id AND o.parent_observation_id IS NULL
       JOIN private.source_record_anchor_current ac ON ac.occurrence_id=o.occurrence_id AND ac.decision_status='accepted'
       JOIN private.source_record sr ON sr.id=ac.source_record_id
      WHERE i.canonical_person_id=p.id AND i.decision_status='accepted' ORDER BY sr.record_key LIMIT 1) AS own_post_key
    FROM person p),
spouse AS (
  SELECT sp.id AS pid,coalesce(i.version,0) AS version,pc.interpretation_key,pc.marriage_ordinal,
         (SELECT sm.verbatim_text FROM private.source_persona_mention spm JOIN private.source_mention sm ON sm.id=spm.mention_id
           WHERE spm.persona_id=sp.id AND spm.mention_role='spouse') AS name,
         (SELECT sr.record_key FROM private.interpretation_current ic
            JOIN private.interpretation_observation io ON io.interpretation_id=ic.id AND io.ordinal=1
            JOIN private.source_observation o ON o.id=io.observation_id
            JOIN private.source_record_anchor_current ac ON ac.occurrence_id=o.occurrence_id AND ac.decision_status='accepted'
            JOIN private.source_record sr ON sr.id=ac.source_record_id WHERE ic.interpretation_key=pc.interpretation_key) AS record_key
    FROM private.interpretation_party_current pc
    JOIN private.source_persona sp ON sp.id=pc.source_persona_id
    LEFT JOIN private.source_persona_identity i ON i.source_persona_id=sp.id
   WHERE pc.party_role='spouse' AND sp.source_id=(SELECT source_id FROM ctl)
     AND (i.source_persona_id IS NULL OR i.decision_status='proposed')),
id_items AS (
  SELECT s.*,
    (SELECT x.mapping FROM smp x WHERE x.source_persona_id=s.pid) AS mapping,
    (SELECT x.identity_version FROM smp x WHERE x.source_persona_id=s.pid) AS sample_version,
    (SELECT c.basis FROM private.source_persona_identity_candidate c WHERE c.run_id=(SELECT candidate_run_id FROM ctl)
      AND c.source_persona_id=s.pid AND c.rank=1) AS top_basis
    FROM spouse s),
rel AS (
  SELECT ic.interpretation_key,ic.version,ic.predicate,
         (SELECT x.mapping FROM smp x WHERE x.interpretation_key=ic.interpretation_key) AS mapping,
         (SELECT sr.record_key FROM private.interpretation_observation io JOIN private.source_observation o ON o.id=io.observation_id
            JOIN private.source_record_anchor_current ac ON ac.occurrence_id=o.occurrence_id AND ac.decision_status='accepted'
            JOIN private.source_record sr ON sr.id=ac.source_record_id WHERE io.interpretation_id=ic.id AND io.ordinal=1) AS record_key
    FROM private.interpretation_current ic
   WHERE ic.source_id=(SELECT source_id FROM ctl) AND ic.predicate IN ('relation.child','relation.parent') AND ic.status='proposed'
     AND EXISTS (SELECT 1 FROM private.interpretation_party_current pc WHERE pc.interpretation_key=ic.interpretation_key AND pc.party_role='principal'))
SELECT jsonb_build_object('control_run_id',(SELECT id FROM ctl),'candidate_run_id',(SELECT candidate_run_id FROM ctl),'items',
  coalesce((SELECT jsonb_agg(item) FROM (
    -- identitet: stikprøve (blind) og uoverensstemmelser (ikke-egnede); egnede uden for stikprøven er maskinens
    SELECT CASE WHEN it.mapping IS NOT NULL THEN jsonb_build_object('kind','identity','sample',true,'source_persona_id',it.pid,
             'version',it.sample_version,'record_key',it.record_key,'principal_record_key',it.record_key,'marriage_ordinal',it.marriage_ordinal,
             'name',it.name,'display',(SELECT jsonb_agg(jsonb_build_object('position',m.key::int,'candidate_id',c.id,'person_id',pv.id,
                'person_name',pv.visning_navn,'born',pv.visning_foedt,'died',pv.visning_doed,'titles',pv.titles,'own_post_key',pv.own_post_key)
                ORDER BY m.key::int) FROM jsonb_each_text(it.mapping) m
                JOIN private.source_persona_identity_candidate c ON c.id=m.value::uuid JOIN person_view pv ON pv.id=c.candidate_person_id))
           ELSE jsonb_build_object('kind','identity','sample',false,'source_persona_id',it.pid,'version',it.version,
             'record_key',it.record_key,'principal_record_key',it.record_key,'marriage_ordinal',it.marriage_ordinal,'name',it.name,
             'reason',coalesce(it.top_basis->>'eligibility_reason','ingen_kandidat'),'run_id',(SELECT candidate_run_id FROM ctl),
             'candidates',coalesce((SELECT jsonb_agg(jsonb_build_object('rank',c.rank,'candidate_id',c.id,'person_id',pv.id,
                'person_name',pv.visning_navn,'born',pv.visning_foedt,'died',pv.visning_doed,'titles',pv.titles,'own_post_key',pv.own_post_key,
                'score',c.score,'tier',c.tier,'signals',c.basis->'signals',
                'family_id',(SELECT fm.family_id FROM family_member fm JOIN family_member fp ON fp.family_id=fm.family_id
                              AND fp.person_id=(private.persona_family_context(it.pid)->>'principal_person_id')::bigint
                              WHERE fm.person_id=c.candidate_person_id AND fm.rolle='partner' LIMIT 1),
                'ordinal',(SELECT fp.ordinal FROM family_member fm JOIN family_member fp ON fp.family_id=fm.family_id
                              AND fp.person_id=(private.persona_family_context(it.pid)->>'principal_person_id')::bigint
                              WHERE fm.person_id=c.candidate_person_id AND fm.rolle='partner' LIMIT 1)) ORDER BY c.rank)
                FROM private.source_persona_identity_candidate c JOIN person_view pv ON pv.id=c.candidate_person_id
                WHERE c.run_id=(SELECT candidate_run_id FROM ctl) AND c.source_persona_id=it.pid),'[]'::jsonb)) END AS item
      FROM id_items it
     WHERE it.mapping IS NOT NULL OR coalesce((it.top_basis->>'corroboration_eligible')::boolean,false) IS FALSE
    UNION ALL
    -- relation: stikprøve (serverens mapping) og uoverensstemmelser (≠ 1 kandidat)
    SELECT jsonb_build_object('kind','relation','sample',r.mapping IS NOT NULL,'interpretation_key',r.interpretation_key,
             'version',r.version,'record_key',r.record_key,'predicate',r.predicate,
             'families',coalesce((SELECT jsonb_agg(jsonb_build_object('position',q.pos,'family_id',q.family_id,
                 'counterpart_name',pv.visning_navn,'counterpart_post_key',pv.own_post_key) ORDER BY q.pos)
               FROM (SELECT sc.*,row_number() OVER (ORDER BY sc.family_id,sc.counterpart_person_id) AS pos
                       FROM private.relation_structural_candidates(r.interpretation_key) sc) q
               JOIN person_view pv ON pv.id=q.counterpart_person_id WHERE q.pos<=3),'[]'::jsonb))
      FROM rel r
     WHERE r.mapping IS NOT NULL
        OR (SELECT count(*) FROM private.relation_structural_candidates(r.interpretation_key))<>1
  ) items),'[]'::jsonb));
COMMIT;
