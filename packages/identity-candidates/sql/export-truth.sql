\set ON_ERROR_STOP on
SET default_transaction_read_only=on;
SELECT coalesce(jsonb_agg(jsonb_build_object('source_persona_id',i.source_persona_id::text,'canonical_person_id',i.canonical_person_id)
       ORDER BY i.source_persona_id),'[]'::jsonb)
  FROM private.source_persona_identity i JOIN private.source_persona p ON p.id=i.source_persona_id
 WHERE p.source_id=:source_id AND i.decision_status='accepted';
