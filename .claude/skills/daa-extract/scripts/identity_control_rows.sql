-- Trin 5b, spec §23: rækkefil til kontrolarket. Indeholder navne og bogens tekst → 0600 under ~/.private/5b/.
-- Ægtefællekort (blinde): hovedperson, klausulen ordret med ægtefællens navnespænd, de viste kandidater i
-- serverens mapping med leveår, titler, egen post og forældre. Forældrekort: hovedperson, klausul og
-- familiens partnere med modparten markeret. Ingen score, rang eller familiemarkør på ægtefællekortene.
\set ON_ERROR_STOP on
SET default_transaction_read_only=on;
BEGIN;
WITH ctl AS (SELECT * FROM private.identity_control_run WHERE id=:'control_run_id'::uuid),
pv AS (
  SELECT p.id,coalesce(p.visning_fuldt_navn,p.visning_navn) AS name,p.visning_foedt AS born,p.visning_doed AS died,
    coalesce((SELECT jsonb_agg(DISTINCT a.vaerdi_tekst) FROM fact f JOIN conclusion k ON k.target_type='fact' AND k.target_id=f.id
               JOIN assertion a ON a.id=k.valgt_assertion_id WHERE f.subjekt_type='person' AND f.subjekt_id=p.id AND f.faktatype='titel'),'[]'::jsonb) AS titles,
    (SELECT sr.record_key FROM private.source_persona_identity i
       JOIN private.source_persona_mention spm ON spm.persona_id=i.source_persona_id AND spm.mention_role='primary'
       JOIN private.source_mention sm ON sm.id=spm.mention_id
       JOIN private.source_observation o ON o.id=sm.observation_id AND o.parent_observation_id IS NULL
       JOIN private.source_record_anchor_current ac ON ac.occurrence_id=o.occurrence_id AND ac.decision_status='accepted'
       JOIN private.source_record sr ON sr.id=ac.source_record_id
      WHERE i.canonical_person_id=p.id AND i.decision_status='accepted' ORDER BY sr.record_key LIMIT 1) AS own_post_key,
    coalesce((SELECT jsonb_agg(jsonb_build_object('name',coalesce(pp.visning_fuldt_navn,pp.visning_navn),'born',pp.visning_foedt,
               'died',pp.visning_doed) ORDER BY pp.id)
       FROM family_member fb JOIN family_member fp ON fp.family_id=fb.family_id AND fp.rolle='partner'
       JOIN person pp ON pp.id=fp.person_id WHERE fb.person_id=p.id AND fb.rolle='barn'),'[]'::jsonb) AS parents
    FROM person p),
clause AS (  -- påstandens støttende observation (ordinal 1, append-only) og dens post
  SELECT ic.interpretation_key,o.id AS observation_id,o.verbatim_text AS text,o.page_from,o.page_to,sr.record_key
    FROM private.interpretation_current ic
    JOIN private.interpretation_observation io ON io.interpretation_id=ic.id AND io.ordinal=1
    JOIN private.source_observation o ON o.id=io.observation_id
    JOIN private.source_record_anchor_current ac ON ac.occurrence_id=o.occurrence_id AND ac.decision_status='accepted'
    JOIN private.source_record sr ON sr.id=ac.source_record_id),
idc AS (
  SELECT s.*,pc.marriage_ordinal,cl.observation_id,cl.text,cl.page_from,cl.page_to,cl.record_key,
         -- writeren lægger ægtefællens mention på klausulen med offsets relative til klausulens tekst
         (SELECT jsonb_build_array(sm.char_from,sm.char_to)
            FROM private.source_persona_mention spm JOIN private.source_mention sm ON sm.id=spm.mention_id
           WHERE spm.persona_id=s.source_persona_id AND spm.mention_role='spouse' AND sm.observation_id=cl.observation_id) AS span,
         private.spouse_principal_person(s.source_persona_id) AS hp
    FROM private.identity_control_sample s
    JOIN private.interpretation_party_current pc ON pc.source_persona_id=s.source_persona_id AND pc.party_role='spouse'
    JOIN clause cl ON cl.interpretation_key=pc.interpretation_key
   WHERE s.control_run_id=(SELECT id FROM ctl) AND s.sample_kind='identity'),
prc AS (
  SELECT pcard.*,cl.observation_id,cl.text,cl.page_from,cl.page_to,cl.record_key,
         (SELECT i.canonical_person_id FROM private.interpretation_party_current pr
            JOIN private.source_persona_identity i ON i.source_persona_id=pr.source_persona_id AND i.decision_status='accepted'
           WHERE pr.interpretation_key=pcard.interpretation_key AND pr.party_role='principal') AS hp
    FROM private.identity_control_parent_card pcard JOIN clause cl ON cl.interpretation_key=pcard.interpretation_key
   WHERE pcard.control_run_id=(SELECT id FROM ctl))
SELECT jsonb_build_object('control_run_id',(SELECT id FROM ctl),'candidate_run_id',(SELECT candidate_run_id FROM ctl),
  'k_random',(SELECT k_random FROM ctl),'items',coalesce((SELECT jsonb_agg(item) FROM (
    SELECT jsonb_build_object('kind','identity','stratum',x.stratum,'source_persona_id',x.source_persona_id,'version',x.identity_version,
      'record_key',x.record_key,'pages',CASE WHEN x.page_from=x.page_to THEN x.page_from::text ELSE x.page_from||'–'||x.page_to END,
      'principal',(SELECT jsonb_build_object('name',pv.name,'born',pv.born,'died',pv.died) FROM pv WHERE pv.id=x.hp),
      'marriage_ordinal',x.marriage_ordinal,'observation_id',x.observation_id,
      'text_sha256',encode(extensions.digest(convert_to(x.text,'UTF8'),'sha256'),'hex'),'text',x.text,'span',x.span,
      'display',(SELECT jsonb_agg(jsonb_build_object('position',m.key::int,'candidate_id',c.id,'name',pv.name,'born',pv.born,
                  'died',pv.died,'titles',pv.titles,'own_post_key',pv.own_post_key,'parents',pv.parents) ORDER BY m.key::int)
                 FROM jsonb_each_text(x.mapping) m JOIN private.source_persona_identity_candidate c ON c.id=m.value::uuid
                 JOIN pv ON pv.id=c.candidate_person_id)) AS item
      FROM idc x
    UNION ALL
    SELECT jsonb_build_object('kind','parent','interpretation_key',y.interpretation_key,'version',y.interpretation_version,
      'record_key',y.record_key,'pages',CASE WHEN y.page_from=y.page_to THEN y.page_from::text ELSE y.page_from||'–'||y.page_to END,
      'principal',(SELECT jsonb_build_object('name',pv.name,'born',pv.born,'died',pv.died) FROM pv WHERE pv.id=y.hp),
      'observation_id',y.observation_id,'text_sha256',encode(extensions.digest(convert_to(y.text,'UTF8'),'sha256'),'hex'),
      'text',y.text,'family_id',y.family_id,
      'partners',(SELECT jsonb_agg(jsonb_build_object('name',pv.name,'born',pv.born,'died',pv.died,'own_post_key',pv.own_post_key,
                    'counterpart',pv.id=y.counterpart_person_id) ORDER BY pv.id) FROM pv WHERE pv.id=ANY(y.partner_ids)))
      FROM prc y) items),'[]'::jsonb));
COMMIT;
