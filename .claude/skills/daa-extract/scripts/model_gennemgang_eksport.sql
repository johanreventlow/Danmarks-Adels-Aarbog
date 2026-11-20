-- Læse-kun eksport til model_gennemgang.py (trin 6m del 1, Task 2): pr. post i kilden narrativet (med state_sha256
-- til revisionsvejen), et eventuelt legacy-narrativ, bogens placering (posttekst og sider) og alle aktuelle forslag.
-- Variabel: :src (kilde-id). Kørsel: psql -qAtX -v ON_ERROR_STOP=1 -v src=3 -f <denne> > eksport.json
-- Ét JSON-dokument ud. Rummer navne og bogtekst: skriv kun til en 0600-fil under ~/.private; læs aldrig, tæl.
-- narrative_record_state kaldes med p_lock=false: med true tager den FOR UPDATE og LOCK TABLE public.change_set,
-- hvilket en læse-kun transaktion afviser (spec-planens Codex #1; læse-RPC'en red_person_narrative_records gør ens).
-- REPEATABLE READ: ét øjebliksbillede for hele eksporten, så tekst og state_sha256 hører sammen (review Codex 3).
BEGIN;
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY;
WITH rec AS (
  SELECT r.id, r.record_key FROM private.source_record r WHERE r.source_id = :src),
occ AS (
  -- Postens forekomster: accepterede ankre.
  SELECT DISTINCT rec.id AS rid, o.id, o.rendition_id, o.page_from, o.page_to, o.char_from, o.char_to
    FROM rec JOIN private.source_record_anchor_current a ON a.source_record_id = rec.id AND a.decision_status = 'accepted'
    JOIN private.source_record_occurrence o ON o.id = a.occurrence_id),
plac AS (
  -- Samme form som persona_kort_kontekst.sql's plac (persona_kort.vindue syr stykkerne sammen).
  SELECT occ.rid, min(occ.page_from) AS side, min(occ.char_from) AS pos,
         jsonb_agg(jsonb_build_object('side_fra', occ.page_from, 'side_til', occ.page_to, 'fra', occ.char_from,
           'til', occ.char_to, 'rendition_id', occ.rendition_id,
           'stykker', (SELECT coalesce(jsonb_agg(jsonb_build_object('f', o2.char_from, 't', o2.verbatim_text)
                                                 ORDER BY o2.char_from), '[]')
                         FROM private.source_record_occurrence o2
                        WHERE o2.rendition_id = occ.rendition_id
                          AND o2.char_to > occ.char_from - 2000 AND o2.char_from < occ.char_to + 800))
                   ORDER BY occ.char_from) AS j
    FROM occ GROUP BY occ.rid),
bind AS (
  -- Aktiv record-binding (unikt indeks: højst én draft/published pr. post).
  SELECT b.source_record_id AS rid, n.id AS narrative_id, n.subjekt_id AS person_id, n.tekst
    FROM private.narrative_record_publication b JOIN public.narrative n ON n.id = b.narrative_id
    JOIN rec ON rec.id = b.source_record_id
   WHERE b.status IN ('draft', 'published') AND n.subjekt_type = 'person'),
tilstand AS (
  SELECT bind.*, private.narrative_record_state(bind.person_id, :src, rec.record_key, false) AS st
    FROM bind JOIN rec ON rec.id = bind.rid),
post_person AS (
  -- Personerne bag postens primære mentions (6b's personas med accepteret identitet).
  SELECT DISTINCT rec.id AS rid, spi.canonical_person_id AS person_id
    FROM rec JOIN private.source_record_anchor_current a ON a.source_record_id = rec.id AND a.decision_status = 'accepted'
    JOIN private.source_observation so ON so.occurrence_id = a.occurrence_id
    JOIN private.source_mention sm ON sm.observation_id = so.id
    JOIN private.source_persona_mention spm ON spm.mention_id = sm.id AND spm.mention_role = 'primary'
    JOIN private.source_persona_identity spi ON spi.source_persona_id = spm.persona_id
                                            AND spi.decision_status = 'accepted'
   WHERE spi.canonical_person_id IS NOT NULL),
ubundne AS (
  -- Kildens personnarrativer uden aktiv record-binding; legacy_ref fra legacy-grenen, hvis den findes.
  SELECT n.id AS narrative_id, n.subjekt_id AS person_id, n.tekst, l.legacy_publication_ref AS legacy_ref
    FROM public.narrative n
    LEFT JOIN private.narrative_legacy_publication l ON l.narrative_id = n.id AND l.status <> 'migrated'
   WHERE n.source_id = :src AND n.subjekt_type = 'person'
     AND NOT EXISTS (SELECT 1 FROM private.narrative_record_publication b
                      WHERE b.narrative_id = n.id AND b.status IN ('draft', 'published'))),
legacy_post AS (
  -- Et ubundet narrativ knyttes til en post, kun hvis dets person står bag præcis én post.
  SELECT u.narrative_id, min(pp.rid::text)::uuid AS rid, count(DISTINCT pp.rid) AS antal
    FROM ubundne u LEFT JOIN post_person pp ON pp.person_id = u.person_id
   GROUP BY u.narrative_id),
ic AS (
  SELECT i.* FROM private.interpretation_current i WHERE i.source_id = :src),
ic_post AS (
  -- Forslagets post: via dets observationer; ellers via personaens primære mention.
  SELECT ic.id, coalesce(
      (SELECT min(rec.record_key) FROM private.interpretation_observation io
         JOIN private.source_observation so ON so.id = io.observation_id
         JOIN private.source_record_anchor_current a ON a.occurrence_id = so.occurrence_id
                                                    AND a.decision_status = 'accepted'
         JOIN rec ON rec.id = a.source_record_id
        WHERE io.interpretation_id = ic.id),
      (SELECT min(rec.record_key) FROM private.source_persona_mention spm
         JOIN private.source_mention sm ON sm.id = spm.mention_id
         JOIN private.source_observation so ON so.id = sm.observation_id
         JOIN private.source_record_anchor_current a ON a.occurrence_id = so.occurrence_id
                                                    AND a.decision_status = 'accepted'
         JOIN rec ON rec.id = a.source_record_id
        WHERE spm.persona_id = ic.source_persona_id AND spm.mention_role = 'primary')) AS record_key,
    (SELECT count(DISTINCT a.source_record_id) FROM private.interpretation_observation io
       JOIN private.source_observation so ON so.id = io.observation_id
       JOIN private.source_record_anchor_current a ON a.occurrence_id = so.occurrence_id
                                                  AND a.decision_status = 'accepted'
       JOIN rec ON rec.id = a.source_record_id
      WHERE io.interpretation_id = ic.id) AS antal_poster
    FROM ic),
forslag AS (
  SELECT ip.record_key,
         jsonb_agg(jsonb_build_object('interpretation_id', ic.id, 'version', ic.version, 'predicate', ic.predicate,
                   'value_text', CASE jsonb_typeof(ic.value) WHEN 'string' THEN ic.value #>> '{}'
                                                            ELSE ic.value->>'raw' END,
                   'status', ic.status, 'persona_id', ic.source_persona_id, 'person_id', spi.canonical_person_id)
                   ORDER BY ic.predicate, ic.id) AS j
    FROM ic JOIN ic_post ip ON ip.id = ic.id
    LEFT JOIN private.source_persona_identity spi ON spi.source_persona_id = ic.source_persona_id
                                                 AND spi.decision_status = 'accepted'
   WHERE ip.record_key IS NOT NULL
   GROUP BY ip.record_key),
person_ids AS (
  SELECT person_id FROM bind UNION SELECT person_id FROM ubundne UNION SELECT person_id FROM post_person
  UNION SELECT spi.canonical_person_id FROM ic JOIN private.source_persona_identity spi
                                             ON spi.source_persona_id = ic.source_persona_id
                                            AND spi.decision_status = 'accepted'),
poster AS (
  SELECT rec.record_key, pl.side, pl.pos,
         jsonb_build_object(
           'record_key', rec.record_key,
           'narrativ', CASE WHEN t.rid IS NULL THEN NULL ELSE jsonb_build_object(
               'person_id', t.person_id, 'narrative_id', t.narrative_id, 'tekst', t.tekst,
               'status', t.st->>'publication_status', 'blokeret', t.st->>'blocking_reason',
               'tilladte', coalesce(t.st->'allowed_actions', '[]'::jsonb), 'state_sha256', t.st->>'state_sha256') END,
           'legacy', (SELECT jsonb_build_object('person_id', u.person_id, 'legacy_ref', u.legacy_ref,
                                                'narrative_id', u.narrative_id, 'tekst', u.tekst)
                        FROM ubundne u JOIN legacy_post lp ON lp.narrative_id = u.narrative_id
                       WHERE lp.rid = rec.id AND lp.antal = 1 AND t.rid IS NULL
                       ORDER BY u.narrative_id LIMIT 1),
           'placering', coalesce(pl.j, '[]'::jsonb),
           'forslag', coalesce(f.j, '[]'::jsonb)) AS j
    FROM rec LEFT JOIN plac pl ON pl.rid = rec.id LEFT JOIN tilstand t ON t.rid = rec.id
    LEFT JOIN forslag f ON f.record_key = rec.record_key)
SELECT jsonb_build_object(
  'udgave', (SELECT nullif(btrim(concat_ws(' ', coalesce(nullif(btrim(s.udgave), ''), s.titel), s.aar)), '')
               FROM public.source s WHERE s.id = :src),
  'source_id', :src,
  -- Udgavebinding (review 37, E7): model_gennemgang.py afviser en eksport, hvis import_key ikke er tilladt.
  'import_key', (SELECT s.import_key FROM public.source s WHERE s.id = :src),
  'poster', (SELECT coalesce(jsonb_agg(p.j ORDER BY p.side NULLS LAST, p.pos NULLS LAST, p.record_key), '[]')
               FROM poster p),
  'personer', (SELECT coalesce(jsonb_object_agg(x.id::text, jsonb_build_object(
                   'navn', coalesce(nullif(btrim(x.visning_fuldt_navn), ''), x.visning_navn),
                   'fuldt_navn', nullif(btrim(x.visning_fuldt_navn), ''), 'foedt', x.visning_foedt,
                   'doed', x.visning_doed, 'titel', x.visning_titel)), '{}')
                 FROM public.person x WHERE x.id IN (SELECT person_id FROM person_ids WHERE person_id IS NOT NULL)),
  -- Kontroltal (Task 0/Task 2): hvert forslag og hvert ubundet narrativ skal kunne gøres op.
  'taelling', jsonb_build_object(
    'forslag', (SELECT count(*) FROM ic),
    'forslag_uden_post', (SELECT count(*) FROM ic_post WHERE record_key IS NULL),
    'forslag_flere_poster', (SELECT count(*) FROM ic_post WHERE antal_poster > 1),
    'narrativer_bundne', (SELECT count(*) FROM bind),
    'narrativer_ubundne', (SELECT count(*) FROM ubundne),
    'ubundne_med_legacy_ref', (SELECT count(*) FROM ubundne WHERE legacy_ref IS NOT NULL),
    'ubundne_paa_en_post', (SELECT count(*) FROM legacy_post WHERE antal = 1),
    'poster_uden_placering', (SELECT count(*) FROM rec WHERE NOT EXISTS (SELECT 1 FROM plac WHERE plac.rid = rec.id))),
  'forslag_uden_post', (SELECT coalesce(jsonb_agg(ip.id ORDER BY ip.id), '[]') FROM ic_post ip
                          WHERE ip.record_key IS NULL),
  'legacy_uden_post', (SELECT coalesce(jsonb_agg(jsonb_build_object('person_id', u.person_id,
                          'legacy_ref', u.legacy_ref, 'narrative_id', u.narrative_id, 'poster', lp.antal)
                          ORDER BY u.narrative_id), '[]')
                         FROM ubundne u JOIN legacy_post lp ON lp.narrative_id = u.narrative_id WHERE lp.antal <> 1)
)::text;
ROLLBACK;
