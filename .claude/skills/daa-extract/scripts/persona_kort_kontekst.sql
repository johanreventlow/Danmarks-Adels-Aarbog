-- Læse-kun kontekst til persona_kort.py (trin 6c-2 Task 8): pr. persona identiteten, den identificerede persons
-- visningsværdier og slægt, personaens forslag (til læse-kun-felterne) og bogens placering (til posttekst og side).
-- Udvidelse af 6c-1 C's kontekst (~/.private/5ab-overfoersel/c-kort/kontekst.sql), nu pr. persona.
-- Variabel: :'personas' (komma-liste af source_persona.id, fra `persona_kort.py kontekst-ids`).
-- Kørsel: psql -qAtX -v ON_ERROR_STOP=1 -v personas="$(persona_kort.py kontekst-ids --plan-dir D)" -f <denne> > kontekst.json
-- Ét JSON-dokument ud. Rummer navne og bogtekst om personer: skriv kun til en 0600-fil under ~/.private; læs aldrig, tæl.
BEGIN;
SET TRANSACTION READ ONLY;
WITH pp AS (SELECT DISTINCT unnest(string_to_array(:'personas', ','))::uuid AS id),
ident AS (
  SELECT pp.id, spi.canonical_person_id AS person_id, spi.evidence->>'outcome' AS udfald,
         spi.decision_status AS status, spi.version
    FROM pp LEFT JOIN private.source_persona_identity spi ON spi.source_persona_id = pp.id),
pers AS (
  SELECT p.id, coalesce(nullif(btrim(p.visning_fuldt_navn),''), p.visning_navn) AS navn,
         nullif(btrim(p.visning_fuldt_navn),'') AS fuldt_navn, p.visning_foedt AS foedt, p.visning_doed AS doed,
         p.visning_titel AS titel, p.koen, coalesce(p.levende,false) AS levende
    FROM public.person p),
kort_person AS (SELECT jsonb_build_object('navn',x.navn,'foedt',x.foedt,'doed',x.doed) AS j, x.id FROM pers x),
foraeldre AS (
  SELECT i.id AS pid, jsonb_agg(DISTINCT kp.j) AS j
    FROM ident i JOIN public.family_member c ON c.person_id = i.person_id AND c.rolle <> 'partner'
    JOIN public.family_member m ON m.family_id = c.family_id AND m.rolle = 'partner'
    JOIN kort_person kp ON kp.id = m.person_id
   GROUP BY i.id),
partnere AS (
  SELECT i.id AS pid, jsonb_agg(DISTINCT kp.j) AS j
    FROM ident i JOIN public.family_member s ON s.person_id = i.person_id AND s.rolle = 'partner'
    JOIN public.family_member m ON m.family_id = s.family_id AND m.rolle = 'partner' AND m.person_id <> s.person_id
    JOIN kort_person kp ON kp.id = m.person_id
   GROUP BY i.id),
boern AS (
  SELECT i.id AS pid, jsonb_agg(DISTINCT kp.j) AS j
    FROM ident i JOIN public.family_member s ON s.person_id = i.person_id AND s.rolle = 'partner'
    JOIN public.family_member m ON m.family_id = s.family_id AND m.rolle <> 'partner'
    JOIN kort_person kp ON kp.id = m.person_id
   GROUP BY i.id),
forslag AS (
  -- Alle åbne forslag for personaen (svarfelter og læse-kun-kontekst); kortværktøjet vælger ud fra planen.
  SELECT ic.source_persona_id AS pid,
         jsonb_agg(jsonb_build_object('interpretation_id', ic.id, 'version', ic.version, 'predicate', ic.predicate,
                   'value_text', CASE jsonb_typeof(ic.value) WHEN 'string' THEN ic.value #>> '{}' ELSE ic.value->>'raw' END)
                   ORDER BY ic.predicate, ic.id) AS j
    FROM private.interpretation_current ic JOIN pp ON pp.id = ic.source_persona_id
   WHERE ic.status = 'proposed'
   GROUP BY ic.source_persona_id),
occ AS (
  -- Postens forekomst(er): observationerne bag personaens forslag → deres forekomst med anker til en post.
  SELECT DISTINCT ic.source_persona_id AS pid, o.id, o.rendition_id, o.page_from, o.page_to, o.char_from, o.char_to,
         sr.record_key
    FROM private.interpretation_current ic JOIN pp ON pp.id = ic.source_persona_id
    JOIN private.interpretation_observation io ON io.interpretation_id = ic.id
    JOIN private.source_observation so ON so.id = io.observation_id
    JOIN private.source_record_occurrence o ON o.id = so.occurrence_id
    JOIN private.source_record_anchor_current a ON a.occurrence_id = o.id AND a.decision_status = 'accepted'
    JOIN private.source_record sr ON sr.id = a.source_record_id
   WHERE ic.status = 'proposed'),
plac AS (
  SELECT occ.pid, min(occ.record_key) AS record_key,
         jsonb_agg(jsonb_build_object('side_fra', occ.page_from, 'side_til', occ.page_to, 'fra', occ.char_from,
           'til', occ.char_to,
           -- Renditionens stykker i vinduet (2000 tegn før, 800 efter); persona_kort.py syr dem sammen.
           'stykker', (SELECT coalesce(jsonb_agg(jsonb_build_object('f', o2.char_from, 't', o2.verbatim_text)
                                                 ORDER BY o2.char_from), '[]')
                         FROM private.source_record_occurrence o2
                        WHERE o2.rendition_id = occ.rendition_id
                          AND o2.char_to > occ.char_from - 2000 AND o2.char_from < occ.char_to + 800))
                   ORDER BY occ.char_from) AS j
    FROM occ GROUP BY occ.pid)
SELECT jsonb_build_object('personas', coalesce(jsonb_object_agg(i.id::text, jsonb_build_object(
    'identitet', jsonb_build_object('person_id', i.person_id, 'udfald', i.udfald, 'status', i.status),
    'person', CASE WHEN x.id IS NULL THEN '{}'::jsonb ELSE jsonb_build_object(
        'navn', x.navn, 'fuldt_navn', x.fuldt_navn, 'foedt', x.foedt, 'doed', x.doed, 'titel', x.titel, 'koen', x.koen,
        'levende', x.levende, 'foraeldre', coalesce(f.j,'[]'), 'partnere', coalesce(pa.j,'[]'),
        'boern', coalesce(b.j,'[]')) END,
    'forslag', coalesce(fo.j, '[]'),
    'post', jsonb_build_object('record_key', pl.record_key, 'placering', coalesce(pl.j, '[]')))), '{}'::jsonb))::text
  FROM ident i LEFT JOIN pers x ON x.id = i.person_id LEFT JOIN foraeldre f ON f.pid = i.id
  LEFT JOIN partnere pa ON pa.pid = i.id LEFT JOIN boern b ON b.pid = i.id LEFT JOIN forslag fo ON fo.pid = i.id
  LEFT JOIN plac pl ON pl.pid = i.id;
ROLLBACK;
