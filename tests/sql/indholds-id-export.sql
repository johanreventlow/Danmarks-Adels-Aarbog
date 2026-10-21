-- Indholds-id (#151, spec §5.1): læse-kun eksport af de 8 arters id'er og stikprøven for hovedtesten.
\set ON_ERROR_STOP on
SET default_transaction_read_only=on;
SET TimeZone='UTC';
SELECT 'source-persona|'||persona_key||'|'||id FROM private.source_persona WHERE source_id=-25001 ORDER BY persona_key COLLATE "C";
SELECT l FROM (SELECT ('source-mention|'||sp.persona_key||'|'||spm.mention_role||'|'||spm.ordinal||'|'||spm.mention_id
 ) AS l FROM private.source_persona_mention spm JOIN private.source_persona sp ON sp.id=spm.persona_id
 WHERE sp.source_id=-25001) x ORDER BY l COLLATE "C";
SELECT l FROM (SELECT ('identity-event|'||sp.persona_key||'|'||e.version||'|'||e.id) AS l FROM private.source_persona_identity_event e
  JOIN private.source_persona sp ON sp.id=e.source_persona_id WHERE sp.source_id=-25001) x ORDER BY l COLLATE "C";
SELECT l FROM (SELECT ('candidate-run|'||input_sha256||'|'||config_sha256||'|'||id) AS l FROM private.source_persona_identity_candidate_run
 WHERE source_id=-25001) x ORDER BY l COLLATE "C";
SELECT l FROM (SELECT ('candidate|'||sp.persona_key||'|'||c.candidate_person_id||'|'||c.rank||'|'||c.id
 ) AS l FROM private.source_persona_identity_candidate c JOIN private.source_persona sp ON sp.id=c.source_persona_id
 WHERE sp.source_id=-25001) x ORDER BY l COLLATE "C";
SELECT 'control-run|'||r.candidate_run_id||'|'||r.id FROM private.identity_control_run r WHERE r.source_id=-25001;
SELECT l FROM (SELECT ('sample|'||sp.persona_key||'|'||s.stratum||'|'||s.id||'|'||s.mapping::text||'|'||s.expected
 ) AS l FROM private.identity_control_sample s JOIN private.source_persona sp ON sp.id=s.source_persona_id
  JOIN private.identity_control_run r ON r.id=s.control_run_id WHERE r.source_id=-25001) x ORDER BY l COLLATE "C";
SELECT l FROM (SELECT ('parent-card|'||pc.interpretation_key||'|'||pc.id) AS l FROM private.identity_control_parent_card pc
  JOIN private.identity_control_run r ON r.id=pc.control_run_id WHERE r.source_id=-25001) x ORDER BY l COLLATE "C";
SELECT 'antal|'||(SELECT count(*) FROM private.identity_control_parent_card)||'|'||
       (SELECT count(*) FROM private.identity_control_sample)||'|'||(SELECT count(*) FROM private.source_persona_identity_candidate_run WHERE source_id=-25001);
