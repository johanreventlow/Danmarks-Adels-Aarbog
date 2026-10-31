-- Læse-kun manifest til trin 6b's ceremoni B: personas for bundne helposter (writer-operationen publication_persona).
-- Kun id'er, nøgler og hashes; ingen posttekst eller navne (mention-teksten indgår kun som SHA-256).
-- Brug: psql -X -At -v ON_ERROR_STOP=1 [-v source_id=3] [-v profile_id=daa-1939-publication-v1] -f publication_persona_manifest.sql
-- Output: præcis én linje JSON:
--   {"elements":{"publication-persona:<record_key>":payload,…},   (rækkefølge COLLATE "C")
--    "expected_counts":{"person_creates":0,"source_evidence":0,"publication_personas":n},
--    "dispositions":[{"record_key":…,"label":…} | {"person_id":…,"label":…},…]}
-- Persona-nøglens prefix og helpost-slagsen læses fra profilens writer_config, ikke hårdkodet.
-- Etiketter (spec §4.6):
--   allerede_persona        recorden har allerede en persona (nøgle eller mention i helposten); ingen element
--   ingen_helpost           recorden har ingen helpost (record_helpost_status = none)
--   ingen_postbinding       helpost, men ingen publiceret binding; også de [NY]-poster: [NY]-klassifikationen findes ikke
--                           i basen (kun i C0's beslutningsdokument), så opret_benet/c3_uafklaret kan ikke forespørges
--   staged_ikke_offentlig   elementets person er staged; får persona i B, etiketten gælder C
--   ingen_bundet_narrativ   kildens person (person_external_id) uden publiceret narrativbinding
--   helpost_uegnet / binding_uegnet   skulle skrives, men opfylder ikke writerens forudsætninger; SKAL være 0
--                           (writeren ville afvise dem), og de er aldrig elementer
\set QUIET on
\set ON_ERROR_STOP on
\if :{?source_id} \else \set source_id 3 \endif
\if :{?profile_id} \else \set profile_id daa-1939-publication-v1 \endif
BEGIN READ ONLY;
-- Fejl højlydt (division med nul, exit ≠ 0) hvis profilen/kilden ikke findes eller profilen mangler persona_key_prefix,
-- i stedet for et tomt, gyldigt manifest.
SELECT 1/(SELECT count(*) FROM private.reimport_writer_profile
           WHERE source_id=:source_id AND profile_id=:'profile_id'
             AND coalesce(writer_config->>'persona_key_prefix','')<>'') AS ok \gset chk_
WITH prof AS (
  SELECT writer_config->>'persona_key_prefix' AS pfx, private.writer_config_helpost_kind(writer_config) AS kind
    FROM private.reimport_writer_profile
   WHERE source_id=:source_id AND profile_id=:'profile_id'
), rec AS (
  SELECT r.id, r.record_key, h.status, h.observation_id
    FROM private.source_record r, prof,
         LATERAL private.record_helpost_status(r.id, prof.kind) h
   WHERE r.source_id=:source_id
), cls AS (
  SELECT rec.*,
         (SELECT count(*) FROM private.narrative_record_publication b WHERE b.source_record_id=rec.id AND b.status='published') AS n_bind,
         EXISTS (SELECT 1 FROM private.source_persona p, prof
                  WHERE p.source_id=:source_id AND p.persona_key=prof.pfx||rec.record_key)
         OR (rec.observation_id IS NOT NULL AND EXISTS (
               SELECT 1 FROM private.source_persona_mention spm
                 JOIN private.source_mention sm ON sm.id=spm.mention_id
                WHERE sm.observation_id=rec.observation_id)) AS has_persona
    FROM rec
), cand AS (
  SELECT c.record_key, c.id AS record_id, c.status, c.n_bind, c.has_persona, c.observation_id,
         b.id AS binding_id, n.subjekt_id AS person_id, n.subjekt_type, n.source_id AS narr_source,
         (SELECT count(*) FROM private.source_mention sm WHERE sm.observation_id=c.observation_id) AS n_mention,
         (SELECT count(*) FROM public.person_external_id e WHERE e.person_id=n.subjekt_id AND e.source_id=:source_id) AS n_ext,
         coalesce((SELECT p.staged FROM public.person p WHERE p.id=n.subjekt_id),false) AS staged
    FROM cls c
    LEFT JOIN private.narrative_record_publication b ON b.source_record_id=c.id AND b.status='published' AND c.n_bind=1
    LEFT JOIN public.narrative n ON n.id=b.narrative_id
), kl AS (
  SELECT cand.*,
    CASE
      WHEN status='none' THEN 'ingen_helpost'
      WHEN status<>'ok' THEN 'helpost_uegnet'
      WHEN has_persona THEN 'allerede_persona'
      WHEN n_bind=0 THEN 'ingen_postbinding'
      WHEN n_bind=1 AND n_mention=1 AND subjekt_type='person' AND narr_source IS NOT DISTINCT FROM :source_id AND n_ext=1
        THEN 'element'
      ELSE 'binding_uegnet'
    END AS label
    FROM cand
), el AS (
  SELECT kl.record_key,
         jsonb_build_object('binding_id',kl.binding_id,'binding_status','published','mention_id',m.id,
           'mention_text_sha256',encode(extensions.digest(m.verbatim_text,'sha256'),'hex'),
           'person_id',kl.person_id,'persona_key',prof.pfx||kl.record_key,'source_id',:source_id::bigint,
           'source_record_key',kl.record_key) AS payload
    FROM kl CROSS JOIN prof
    JOIN private.source_mention m ON m.observation_id=kl.observation_id
   WHERE kl.label='element'
), disp AS (
  SELECT 1 AS grp, kl.label, kl.record_key AS k, jsonb_build_object('record_key',kl.record_key,'label',kl.label) AS d
    FROM kl WHERE kl.label<>'element'
  UNION ALL
  SELECT 1, 'staged_ikke_offentlig', kl.record_key, jsonb_build_object('record_key',kl.record_key,'label','staged_ikke_offentlig')
    FROM kl WHERE kl.label='element' AND kl.staged
  UNION ALL
  SELECT 2, 'ingen_bundet_narrativ', lpad(e.person_id::text,20,'0'), jsonb_build_object('person_id',e.person_id,'label','ingen_bundet_narrativ')
    FROM public.person_external_id e
   WHERE e.source_id=:source_id
     AND NOT EXISTS (SELECT 1 FROM public.narrative n JOIN private.narrative_record_publication b ON b.narrative_id=n.id
                      WHERE n.subjekt_type='person' AND n.subjekt_id=e.person_id AND b.status='published')
)
SELECT '{"elements":{'||coalesce((SELECT string_agg(to_json('publication-persona:'||record_key)::text||':'||payload::text,','
                                                      ORDER BY record_key COLLATE "C") FROM el),'')||
       '},"expected_counts":'||jsonb_build_object('person_creates',0,'source_evidence',0,
                                  'publication_personas',(SELECT count(*) FROM el))::text||
       ',"dispositions":['||coalesce((SELECT string_agg(d::text,',' ORDER BY grp, label COLLATE "C", k COLLATE "C") FROM disp),'')||']}';
ROLLBACK;
