-- Task 4c / Q3: læsende prædikater til Task 7 og talmåling. Kør som ejer med -v pid=<id>.
-- Kun antal udskrives. Ingen autorisation udstedes, ingen writer kaldes, ingen rækkelåse tages.
-- Autorisation/rolle/nonce er eksekveringens adgangskrav, ikke en egenskab ved en kørsels fortrydelighed.
\set ON_ERROR_STOP on
\set QUIET on
WITH
p AS (SELECT (:pid)::bigint AS id),
plan AS MATERIALIZED (SELECT q.* FROM p CROSS JOIN LATERAL private.person_purge_plan(p.id) q),
children AS MATERIALIZED (
  SELECT b.id AS parent_id,c.* FROM private.reimport_batch b
    JOIN private.reimport_authorization ca ON ca.operation='name_completion'
      AND ca.source_id=b.source_id AND ca.profile_id=b.profile_id AND ca.profile_sha256=b.profile_sha256
      AND ca.authorized_elements->'source_batch_id'=to_jsonb(b.id)
    JOIN private.reimport_batch c ON c.authorization_id=ca.id AND c.status='finalized'),
-- Kun gyldige parent/child-par; ingen »status alene«-genvej.
generic_header AS MATERIALIZED (
  SELECT b.id,b.source_id,c.id AS child_id FROM private.reimport_batch b JOIN children c ON c.parent_id=b.id
   WHERE public.narrative_record_contract_version()=2 AND b.status='activated'
     AND (SELECT count(*) FROM children cc WHERE cc.parent_id=b.id)=1
     AND c.expected_counts=c.observed_counts
     AND (SELECT count(*) FROM private.reimport_name_completion_result r WHERE r.batch_id=c.id)=(c.expected_counts->>'name_completions')::bigint
     AND (SELECT count(*) FROM private.reimport_event e WHERE e.batch_id=c.id AND e.operation='canonical_delta')=(c.expected_counts->>'operations')::bigint
     AND NOT EXISTS (SELECT 1 FROM private.reimport_event e WHERE e.batch_id=b.id AND e.operation='person_create'
       AND NOT EXISTS (SELECT 1 FROM private.reimport_name_completion_result r JOIN private.reimport_event ce
         ON ce.batch_id=r.batch_id AND ce.element_id=r.element_id AND ce.operation='canonical_delta'
         WHERE r.batch_id=c.id AND r.person_id=e.canonical_person_id
           AND ce.payload->>'source_person_create_element_id'=e.element_id AND ce.source_record_key=e.source_record_key))
     AND NOT EXISTS (SELECT 1 FROM private.reimport_name_completion_result r JOIN private.reimport_event ce
       ON ce.batch_id=r.batch_id AND ce.element_id=r.element_id AND ce.operation='canonical_delta'
       WHERE r.batch_id=c.id AND NOT EXISTS (SELECT 1 FROM private.reimport_event e
         WHERE e.batch_id=b.id AND e.operation='person_create' AND e.element_id=ce.payload->>'source_person_create_element_id'
           AND e.canonical_person_id=r.person_id AND e.source_record_key=ce.source_record_key))),
generic_rows AS MATERIALIZED (
  SELECT b.id AS batch_id,r.id AS result_id,r.person_id,r.source_persona_id,ev.id AS publication_event_id,
         ev.narrative_id,r.source_record_id,r.fact_id,r.assertion_id,r.citation_id,r.conclusion_id,
    (e.id IS NOT NULL AND r.result_sha256=private.reimport_canonical_json_sha256(jsonb_build_object(
       'fact_id',r.fact_id,'assertion_id',r.assertion_id,'citation_id',r.citation_id,'conclusion_id',r.conclusion_id))
     AND e.payload->>'event_id' IS NOT NULL AND jsonb_typeof(receipt.j)='object'
     AND receipt.j->>'source_person_create_event_id'=e.payload->>'event_id'
     AND receipt.j->>'source_record_key'=e.source_record_key AND receipt.j->>'state_sha256' ~ '^[0-9a-f]{64}$'
     AND i.version IS NOT NULL AND ev.id IS NOT NULL
     -- Aktiveringswriteren skriver upsert på den eksisterende kladde => draft_updated. Den inverse tilstand
     -- er draft, så red_kasser_person_narrative_record kan følge efter reverseringen (§5933-sporet).
     AND ev.event_type='draft_updated' AND ev.before_state#>>'{binding,status}'='draft'
     AND ev.before_state_sha256=encode(extensions.digest(ev.before_state::text,'sha256'),'hex')
     AND ev.after_state_sha256=encode(extensions.digest(ev.after_state::text,'sha256'),'hex')
     AND NOT EXISTS (SELECT 1 FROM private.narrative_publication_event later
       WHERE later.stream_ref=ev.stream_ref AND (later.stream_version>ev.stream_version OR later.reversed_event_id=ev.id))
     AND CASE WHEN sr.id IS NOT NULL AND e.id IS NOT NULL THEN
       private.narrative_record_state(r.person_id,b.source_id,e.source_record_key,false)->>'state_sha256'=receipt.j->>'state_sha256'
       AND private.narrative_record_state(r.person_id,b.source_id,e.source_record_key,false)->>'latest_event_id'=ev.id::text
       AND private.narrative_record_state(r.person_id,b.source_id,e.source_record_key,false)->'publication_state'=ev.after_state
       AND private.narrative_record_state(r.person_id,b.source_id,e.source_record_key,false)->>'publication_state_sha256'=ev.after_state_sha256
       ELSE false END) IS TRUE AS ready
  FROM generic_header b JOIN private.reimport_name_completion_result r ON r.batch_id=b.child_id
  LEFT JOIN private.source_record sr ON sr.id=r.source_record_id AND sr.source_id=b.source_id
  LEFT JOIN private.reimport_event e ON e.batch_id=b.id AND e.operation='person_create'
    AND e.canonical_person_id=r.person_id AND e.source_record_key=sr.record_key
  LEFT JOIN LATERAL (SELECT ac.payload FROM private.reimport_event ac WHERE ac.batch_id=b.id AND ac.operation='activation'
    ORDER BY ac.id DESC LIMIT 1) activation ON true
  CROSS JOIN LATERAL (SELECT activation.payload->'post_activation_receipts'->r.person_id::text AS j) receipt
  LEFT JOIN private.narrative_publication_event ev ON ev.id::text=receipt.j->>'event_id'
  LEFT JOIN private.source_persona_identity i ON i.source_persona_id=r.source_persona_id),
generic_ready AS MATERIALIZED (
  SELECT b.id,b.child_id FROM generic_header b
   WHERE (SELECT jsonb_typeof(ac.payload->'post_activation_receipts') FROM private.reimport_event ac
      WHERE ac.batch_id=b.id AND ac.operation='activation' ORDER BY ac.id DESC LIMIT 1)='object'
     AND NOT EXISTS (SELECT 1 FROM generic_rows r WHERE r.batch_id=b.id AND NOT r.ready)),
generic_lost AS MATERIALIZED (
  SELECT b.id FROM generic_ready b WHERE EXISTS (
    SELECT 1 FROM plan q WHERE q.handling IN ('slet','nulstil','loesn') AND (
      (q.tabel='private.reimport_event' AND EXISTS (SELECT 1 FROM private.reimport_event e
        WHERE q.pk=jsonb_build_object('id',e.id) AND e.batch_id IN (b.id,b.child_id)))
      OR (q.tabel='private.reimport_name_completion_result' AND EXISTS (SELECT 1 FROM generic_rows r
        WHERE r.batch_id=b.id AND q.pk=jsonb_build_object('id',r.result_id)))
      OR (q.tabel='private.narrative_publication_event' AND EXISTS (SELECT 1 FROM generic_rows r
        WHERE r.batch_id=b.id AND q.pk=jsonb_build_object('id',r.publication_event_id)))
      OR (q.tabel='narrative' AND EXISTS (SELECT 1 FROM generic_rows r
        WHERE r.batch_id=b.id AND q.pk=jsonb_build_object('id',r.narrative_id)))
      -- Receiptet hasher også afledt tilstand: fx has_haendelse ændres, når den sidste S26-hændelse
      -- under en ANDENS narrativ fjernes. Advar konservativt for enhver berørt hændelse i strømmen,
      -- også loesn (S27); kræv ikke bevis for at netop den sidste hændelse forsvinder.
      OR (q.tabel='haendelse' AND EXISTS (SELECT 1 FROM generic_rows r JOIN public.haendelse h
        ON h.narrative_id=r.narrative_id WHERE r.batch_id=b.id AND q.pk=jsonb_build_object('id',h.id)))
      OR (q.tabel='person' AND EXISTS (SELECT 1 FROM generic_rows r
        WHERE r.batch_id=b.id AND q.pk=jsonb_build_object('id',r.person_id)))
      OR (q.tabel IN ('fact','assertion','citation','conclusion') AND EXISTS (SELECT 1 FROM generic_rows r
        WHERE r.batch_id=b.id AND q.pk=jsonb_build_object('id',CASE q.tabel
          WHEN 'fact' THEN r.fact_id WHEN 'assertion' THEN r.assertion_id
          WHEN 'citation' THEN r.citation_id WHEN 'conclusion' THEN r.conclusion_id END)))
      -- Hele recordens binding-/eventhistorik og alle placerede identiteter indgår i state,
      -- ikke kun receiptets eget event eller resultatpersonaen. Også historiske placeringer
      -- medtages som konservativ overmængde; bogens record/placement/anker-rækker slettes ikke.
      OR (q.tabel='private.narrative_record_publication' AND EXISTS (SELECT 1 FROM generic_rows r
        JOIN private.narrative_record_publication np ON np.source_record_id=r.source_record_id
        WHERE r.batch_id=b.id AND q.pk=jsonb_build_object('id',np.id)))
      OR (q.tabel='private.narrative_publication_event' AND EXISTS (SELECT 1 FROM generic_rows r
        JOIN private.narrative_publication_event np ON np.source_record_id=r.source_record_id
        WHERE r.batch_id=b.id AND q.pk=jsonb_build_object('id',np.id)))
      OR (q.tabel='private.source_persona_identity' AND EXISTS (SELECT 1 FROM generic_rows r
        WHERE r.batch_id=b.id AND (q.pk->>'source_persona_id'=r.source_persona_id::text
          OR EXISTS (SELECT 1 FROM private.source_record_placement rp
            JOIN private.source_persona_placement pp ON pp.record_placement_id=rp.id
            WHERE rp.source_record_id=r.source_record_id AND pp.source_persona_id::text=q.pk->>'source_persona_id'))))))),
publication_ready AS MATERIALIZED (
  SELECT b.id FROM private.reimport_batch b WHERE public.narrative_record_contract_version()=2 AND b.status='finalized'
    AND EXISTS (SELECT 1 FROM private.reimport_event e WHERE e.batch_id=b.id AND e.operation='publication_identity')
    AND NOT EXISTS (SELECT 1 FROM private.reimport_event e LEFT JOIN private.source_persona_identity i
      ON i.source_persona_id::text=e.payload->>'source_persona_id' WHERE e.batch_id=b.id AND (
        e.operation IS DISTINCT FROM 'publication_identity'
        OR jsonb_typeof(e.payload#>'{result_receipt,identity_version}') IS DISTINCT FROM 'number'
        OR i.version IS DISTINCT FROM (e.payload#>>'{result_receipt,identity_version}')::integer))),
publication_lost AS MATERIALIZED (
  SELECT b.id FROM publication_ready b WHERE
    -- Konservativ Q3-advarsel, indtil hovedsessionen afklarer semantikken: også tab af ét C-element
    -- medtages, selv om RPC'en stadig kan fortryde de øvrige personer uden oprindelig elementtælling.
    EXISTS (SELECT 1 FROM private.reimport_event e WHERE e.batch_id=b.id AND EXISTS (
      SELECT 1 FROM plan q WHERE q.tabel='private.reimport_event' AND q.handling='slet' AND q.pk=jsonb_build_object('id',e.id)))
    OR EXISTS (SELECT 1 FROM private.reimport_event e WHERE e.batch_id=b.id
      AND NOT EXISTS (SELECT 1 FROM plan q WHERE q.tabel='private.reimport_event' AND q.handling='slet' AND q.pk=jsonb_build_object('id',e.id))
      AND EXISTS (SELECT 1 FROM plan q WHERE q.tabel='private.source_persona_identity' AND q.handling='slet'
        AND q.pk->>'source_persona_id'=e.payload->>'source_persona_id')))
SELECT (SELECT count(*) FROM generic_ready) AS reimport_kan_nu,
       (SELECT count(*) FROM generic_lost) AS reimport_mistes,
       (SELECT count(*) FROM generic_ready) AS wrapper_kan_nu,
       (SELECT count(*) FROM generic_lost) AS wrapper_mistes,
       0::bigint AS cases_kan_nu, 0::bigint AS cases_mistes,
       (SELECT count(*) FROM publication_ready) AS publication_kan_nu,
       (SELECT count(*) FROM publication_lost) AS publication_mistes
-- Testen forbruger PRÆCIS samme CTE'er og asserterer både antal og batchmængder.
-- UUID'er sendes kun til sessionsvariabler, aldrig til almindeligt måleoutput.
\if :{?purge_reversal_assert}
       ,jsonb_build_object(
         'generic_ready',coalesce((SELECT jsonb_agg(id ORDER BY id) FROM generic_ready),'[]'::jsonb),
         'generic_lost',coalesce((SELECT jsonb_agg(id ORDER BY id) FROM generic_lost),'[]'::jsonb),
         'publication_ready',coalesce((SELECT jsonb_agg(id ORDER BY id) FROM publication_ready),'[]'::jsonb),
         'publication_lost',coalesce((SELECT jsonb_agg(id ORDER BY id) FROM publication_lost),'[]'::jsonb)) AS batches
\gset reversal_
\else
;
\endif
