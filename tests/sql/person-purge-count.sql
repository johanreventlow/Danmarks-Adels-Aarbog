-- person-purge-count.sql — uafhængig tæller: spor efter én person, pr. sted (S-numre = slettegraf.md).
-- Afledt af docs/superpowers/plans/personsletning/count.sql med tre rettelser (slettegraf »Afgørelser«):
--   1. foer og efter vurderes hver for sig (ikke coalesce(efter,foer)), så en UPDATE der flyttede en nøgle
--      væk fra P stadig findes.
--   2. feed_pin-formaterne fra NY-B: story:<S>, paadennedag:h:<H>, dagensperson:<P> (packages/feed/src/story.ts:108,
--      temporal.ts:100,130) tælles sammen med de øvrige nøgler.
--   3. S46 (identity_control_sample) via kandidat-uuid'er (candidate.id WHERE candidate_person_id=P), ikke regex.
-- Læser IKKE sletningens inventar. KUN count(*); output er rækker (sted, tabel, antal) — aldrig rækkeindhold.
--   psql "$DB" -X -A -F'|' -v pid=123 -f tests/sql/person-purge-count.sql
-- psql-variablen pid interpoleres kun i params-CTE'en (psql interpolerer ikke i citationstegn/DO-blokke).
-- Alle sammenligninger mod jsonb sker som tekst (ingen ::bigint-cast på jsonb), så rækker med
-- uuid-PK (profiles) ikke kan give castfejl.
\set ON_ERROR_STOP on
\set QUIET on
BEGIN TRANSACTION READ ONLY;

WITH RECURSIVE
params AS (SELECT (:pid)::bigint AS pid, (:pid)::bigint::text AS pidt),

-- ---------- levende id-mængder ----------
facts AS MATERIALIZED (
  SELECT f.id FROM public.fact f, params p
   WHERE f.subjekt_type='person' AND f.subjekt_id=p.pid),
rels AS MATERIALIZED (
  SELECT r.id FROM public.relation r, params p
   WHERE (r.subjekt_type='person' AND r.subjekt_id=p.pid)
      OR (r.objekt_type='person'  AND r.objekt_id=p.pid)),
asrt AS MATERIALIZED (
  SELECT a.id FROM public.assertion a
   WHERE (a.target_type='fact'     AND a.target_id IN (SELECT id FROM facts))
      OR (a.target_type='relation' AND a.target_id IN (SELECT id FROM rels))),
narr AS MATERIALIZED (
  SELECT n.id FROM public.narrative n, params p
   WHERE n.subjekt_type='person' AND n.subjekt_id=p.pid),
fams AS MATERIALIZED (
  SELECT DISTINCT fm.family_id AS id FROM public.family_member fm, params p
   WHERE fm.person_id=p.pid),
p_haendelse AS MATERIALIZED (
  SELECT h.id FROM public.haendelse h, params p
   WHERE h.narrative_id IN (SELECT id FROM narr)
      OR (h.subjekt_type='person' AND h.subjekt_id=p.pid)),
p_story AS MATERIALIZED (
  SELECT s.id FROM public.story s, params p
   WHERE s.subjekt_type='person' AND s.subjekt_id=p.pid),
media_ids AS MATERIALIZED (
  SELECT DISTINCT CASE WHEN r.subjekt_type='media' THEN r.subjekt_id ELSE r.objekt_id END AS id
    FROM public.relation r
   WHERE r.id IN (SELECT id FROM rels) AND 'media' IN (r.subjekt_type, r.objekt_type)),
media_excl AS MATERIALIZED (
  SELECT m.id FROM media_ids m
   WHERE NOT EXISTS (SELECT 1 FROM public.relation r
                      WHERE ((r.subjekt_type='media' AND r.subjekt_id=m.id)
                          OR (r.objekt_type='media' AND r.objekt_id=m.id))
                        AND r.id NOT IN (SELECT id FROM rels))
     AND NOT EXISTS (SELECT 1 FROM public.fact f WHERE f.subjekt_type='media' AND f.subjekt_id=m.id)
     AND NOT EXISTS (SELECT 1 FROM public.story s WHERE s.subjekt_type='media' AND s.subjekt_id=m.id)
     AND NOT EXISTS (SELECT 1 FROM public.narrative n WHERE n.subjekt_type='media' AND n.subjekt_id=m.id)
     AND NOT EXISTS (SELECT 1 FROM public.note o WHERE o.target_type='media' AND o.target_id=m.id)
     AND NOT EXISTS (SELECT 1 FROM public.suggestion g WHERE g.subjekt_type='media' AND g.subjekt_id=m.id)
     AND NOT EXISTS (SELECT 1 FROM public.text_mention t WHERE t.maal_type='media' AND t.maal_id=m.id)),
personas AS MATERIALIZED (
  SELECT e.source_persona_id AS id FROM private.source_persona_identity_event e, params p
   WHERE e.canonical_person_id=p.pid
  UNION
  SELECT i.source_persona_id FROM private.source_persona_identity i, params p
   WHERE i.canonical_person_id=p.pid),


-- ---------- historiske id-mængder (lukning over change_event; foer og efter hver for sig) ----------
-- v(j) = (foer),(efter): hver side af eventet vurderes selvstændigt.
hist_facts AS MATERIALIZED (
  SELECT ce.row_pk->>'id' AS idt FROM public.change_event ce, params p
   WHERE ce.tabel='fact'
     AND ((ce.foer ->>'subjekt_type'='person' AND ce.foer ->>'subjekt_id'=p.pidt)
       OR (ce.efter->>'subjekt_type'='person' AND ce.efter->>'subjekt_id'=p.pidt))
  UNION SELECT id::text FROM facts),
hist_rels AS MATERIALIZED (
  SELECT ce.row_pk->>'id' AS idt FROM public.change_event ce, params p
   WHERE ce.tabel='relation'
     AND ((ce.foer ->>'subjekt_type'='person' AND ce.foer ->>'subjekt_id'=p.pidt)
       OR (ce.foer ->>'objekt_type' ='person' AND ce.foer ->>'objekt_id' =p.pidt)
       OR (ce.efter->>'subjekt_type'='person' AND ce.efter->>'subjekt_id'=p.pidt)
       OR (ce.efter->>'objekt_type' ='person' AND ce.efter->>'objekt_id' =p.pidt))
  UNION SELECT id::text FROM rels),
hist_asrt AS MATERIALIZED (
  SELECT ce.row_pk->>'id' AS idt FROM public.change_event ce
   WHERE ce.tabel='assertion'
     AND EXISTS (SELECT 1 FROM (VALUES (ce.foer),(ce.efter)) v(j)
                  WHERE (v.j->>'target_type'='fact'     AND v.j->>'target_id' IN (SELECT idt FROM hist_facts))
                     OR (v.j->>'target_type'='relation' AND v.j->>'target_id' IN (SELECT idt FROM hist_rels)))
  UNION SELECT id::text FROM asrt),
hist_narr AS MATERIALIZED (
  SELECT ce.row_pk->>'id' AS idt FROM public.change_event ce, params p
   WHERE ce.tabel='narrative'
     AND ((ce.foer ->>'subjekt_type'='person' AND ce.foer ->>'subjekt_id'=p.pidt)
       OR (ce.efter->>'subjekt_type'='person' AND ce.efter->>'subjekt_id'=p.pidt))
  UNION SELECT id::text FROM narr),
hist_story AS MATERIALIZED (
  SELECT ce.row_pk->>'id' AS idt FROM public.change_event ce, params p
   WHERE ce.tabel='story'
     AND ((ce.foer ->>'subjekt_type'='person' AND ce.foer ->>'subjekt_id'=p.pidt)
       OR (ce.efter->>'subjekt_type'='person' AND ce.efter->>'subjekt_id'=p.pidt))
  UNION SELECT id::text FROM p_story),
-- (source_id, record_key) for personens external-id'er, levende + historiske (begge sider) → import_key
hist_pei AS MATERIALIZED (
  SELECT pe.source_id::text AS source_idt, pe.record_key FROM public.person_external_id pe, params p
   WHERE pe.person_id=p.pid AND pe.record_key IS NOT NULL
  UNION
  SELECT v.j->>'source_id', v.j->>'record_key'
    FROM public.change_event ce CROSS JOIN LATERAL (VALUES (ce.foer),(ce.efter)) v(j), params p
   WHERE ce.tabel='person_external_id' AND ce.row_pk->>'person_id'=p.pidt
     AND v.j->>'record_key' IS NOT NULL),
p_import_keys AS MATERIALIZED (
  SELECT s.import_key, hp.record_key FROM hist_pei hp JOIN public.source s ON s.id::text=hp.source_idt
   WHERE s.import_key IS NOT NULL),
-- feed_pin-nøgler (NY-B): mønstre med person-id og eksakte nøgler for P's historier/hændelser.
feed_rx AS (
  SELECT '^((portrait|citat|naevnt|dagensperson):' || p.pidt || '|(jubilaeum|embede):' || p.pidt || ':.*'
         || '|slaegt:' || p.pidt || ':[0-9]+|slaegt:[0-9]+:' || p.pidt || ')$' AS rx
    FROM params p),
feed_keys AS MATERIALIZED (
  SELECT 'story:' || idt AS k FROM hist_story
  UNION SELECT 'arkiv:' || id FROM p_haendelse
  UNION SELECT 'paadennedag:h:' || id FROM p_haendelse),

-- ---------- change_event-hits (S54) ----------
ce_hits AS MATERIALIZED (
  SELECT ce.id, ce.change_set_id, ce.tabel, ce.op
    FROM public.change_event ce, params p, feed_rx fx
   WHERE (ce.tabel='person' AND ce.row_pk->>'id'=p.pidt)
      OR (ce.tabel IN ('person_external_id','family_member','person_slaegt_membership','person_lineage_membership')
          AND ce.row_pk->>'person_id'=p.pidt)
      OR (ce.tabel='profiles'
          AND (ce.foer->>'reventlow_person_id'=p.pidt OR ce.efter->>'reventlow_person_id'=p.pidt))
      OR (ce.tabel='fact'      AND ce.row_pk->>'id' IN (SELECT idt FROM hist_facts))
      OR (ce.tabel='relation'  AND ce.row_pk->>'id' IN (SELECT idt FROM hist_rels))
      OR (ce.tabel='assertion' AND ce.row_pk->>'id' IN (SELECT idt FROM hist_asrt))
      OR (ce.tabel='conclusion'
          AND EXISTS (SELECT 1 FROM (VALUES (ce.foer),(ce.efter)) v(j)
                       WHERE (v.j->>'target_type'='fact'     AND v.j->>'target_id' IN (SELECT idt FROM hist_facts))
                          OR (v.j->>'target_type'='relation' AND v.j->>'target_id' IN (SELECT idt FROM hist_rels))))
      OR (ce.tabel='citation'
          AND EXISTS (SELECT 1 FROM (VALUES (ce.foer),(ce.efter)) v(j)
                       WHERE v.j->>'assertion_id' IN (SELECT idt FROM hist_asrt)))
      OR (ce.tabel='note'
          AND EXISTS (SELECT 1 FROM (VALUES (ce.foer),(ce.efter)) v(j)
                       WHERE (v.j->>'target_type'='person'   AND v.j->>'target_id'=p.pidt)
                          OR (v.j->>'target_type'='fact'     AND v.j->>'target_id' IN (SELECT idt FROM hist_facts))
                          OR (v.j->>'target_type'='relation' AND v.j->>'target_id' IN (SELECT idt FROM hist_rels))))
      OR (ce.tabel='narrative' AND ce.row_pk->>'id' IN (SELECT idt FROM hist_narr))
      OR (ce.tabel='story'     AND ce.row_pk->>'id' IN (SELECT idt FROM hist_story))
      OR (ce.tabel='story_kilde'
          AND EXISTS (SELECT 1 FROM (VALUES (ce.foer),(ce.efter)) v(j)
                       WHERE v.j->>'story_id' IN (SELECT idt FROM hist_story)))
      OR (ce.tabel='entity_description'
          AND ((ce.foer ->>'subjekt_type'='person' AND ce.foer ->>'subjekt_id'=p.pidt)
            OR (ce.efter->>'subjekt_type'='person' AND ce.efter->>'subjekt_id'=p.pidt)))
      OR (ce.tabel='feed_pin'
          AND EXISTS (SELECT 1 FROM (VALUES (ce.foer),(ce.efter)) v(j)
                       WHERE v.j->>'kort_noegle' ~ fx.rx
                          OR v.j->>'kort_noegle' IN (SELECT k FROM feed_keys)))
      OR (ce.tabel='import_korrektion'
          AND EXISTS (SELECT 1 FROM (VALUES (ce.foer),(ce.efter)) v(j), p_import_keys k
                       WHERE k.import_key=v.j->>'import_key' AND k.record_key=v.j->>'record_key'))),

hit_sets AS MATERIALIZED (
  SELECT cs.id FROM public.change_set cs, params p
   WHERE cs.subjekt_type='person' AND cs.subjekt_id=p.pid
  UNION SELECT change_set_id FROM ce_hits),
rev_chain(id) AS (
  SELECT cs.id FROM public.change_set cs WHERE cs.reverterer_id IN (SELECT id FROM hit_sets)
  UNION
  SELECT cs.id FROM public.change_set cs JOIN rev_chain rc ON cs.reverterer_id=rc.id),

-- ---------- jsonb-heuristik for private ledgers ----------
-- rx: en nøgle der indeholder "person" med værdien pid (også citeret: "person_id": "123");
--     eller pid som element i et array under en nøgle med "person"/"partner".
-- jsonb::text skriver altid '"nøgle": værdi' og '[1, 2]'. Heuristik: kan give falske negative.
jrx AS (
  SELECT '"[a-z_]*person[a-z_]*": "?' || p.pidt || '"?[],}]'
         || '|"[a-z_]*(person|partner)[a-z_]*": \[[^]]*\m' || p.pidt || '\M' AS rx
    FROM params p),

counts(nr, sted, antal) AS (
  -- Punkt 1: hårde FK'er
  SELECT 'S01','public.person', (SELECT count(*) FROM public.person x, params p WHERE x.id=p.pid)
  UNION ALL SELECT 'S02','public.person_external_id', (SELECT count(*) FROM public.person_external_id x, params p WHERE x.person_id=p.pid)
  UNION ALL SELECT 'S03','public.family_member', (SELECT count(*) FROM public.family_member x, params p WHERE x.person_id=p.pid)
  UNION ALL SELECT 'S04','public.slaegtsnavn_karantaene', (SELECT count(*) FROM public.slaegtsnavn_karantaene x, params p WHERE x.person_id=p.pid)
  UNION ALL SELECT 'S05','public.profiles.reventlow_person_id', (SELECT count(*) FROM public.profiles x, params p WHERE x.reventlow_person_id=p.pid)
  UNION ALL SELECT 'S06','public.bookmark (CASCADE)', (SELECT count(*) FROM public.bookmark x, params p WHERE x.person_id=p.pid)
  UNION ALL SELECT 'S07','public.person_slaegt_membership', (SELECT count(*) FROM public.person_slaegt_membership x, params p WHERE x.person_id=p.pid)
  UNION ALL SELECT 'S08','public.person_lineage_membership', (SELECT count(*) FROM public.person_lineage_membership x, params p WHERE x.person_id=p.pid)
  UNION ALL SELECT 'S09','private.person_create_receipt (CASCADE)', (SELECT count(*) FROM private.person_create_receipt x, params p WHERE x.person_id=p.pid)
  UNION ALL SELECT 'S10','private.source_persona_identity [BLOKERER]', (SELECT count(*) FROM private.source_persona_identity x, params p WHERE x.canonical_person_id=p.pid)
  UNION ALL SELECT 'S11','private.source_persona_identity_event [BLOKERER, append-only]', (SELECT count(*) FROM private.source_persona_identity_event x, params p WHERE x.canonical_person_id=p.pid)
  UNION ALL SELECT 'S12','private.source_persona_identity_candidate [BLOKERER, ikke gatet]', (SELECT count(*) FROM private.source_persona_identity_candidate x, params p WHERE x.candidate_person_id=p.pid)
  -- Punkt 2a: kerne-evidens
  UNION ALL SELECT 'S13','public.fact (subjekt person)', (SELECT count(*) FROM facts)
  UNION ALL SELECT 'S14','public.relation (subjekt/objekt person)', (SELECT count(*) FROM rels)
  UNION ALL SELECT 'S15','public.assertion (på fakta/relationer)', (SELECT count(*) FROM asrt)
  UNION ALL SELECT 'S16','public.conclusion (på fakta/relationer)', (SELECT count(*) FROM public.conclusion c
       WHERE (c.target_type='fact' AND c.target_id IN (SELECT id FROM facts))
          OR (c.target_type='relation' AND c.target_id IN (SELECT id FROM rels)))
  UNION ALL SELECT 'S17','public.citation (på assertions)', (SELECT count(*) FROM public.citation c WHERE c.assertion_id IN (SELECT id FROM asrt))
  UNION ALL SELECT 'S18','public.note (person/fakta/relationer)', (SELECT count(*) FROM public.note o, params p
       WHERE (o.target_type='person' AND o.target_id=p.pid)
          OR (o.target_type='fact' AND o.target_id IN (SELECT id FROM facts))
          OR (o.target_type='relation' AND o.target_id IN (SELECT id FROM rels)))
  UNION ALL SELECT 'S19','public.relation med fact-ende i P''s fakta', (SELECT count(*) FROM public.relation r
       WHERE (r.subjekt_type='fact' AND r.subjekt_id IN (SELECT id FROM facts))
          OR (r.objekt_type='fact' AND r.objekt_id IN (SELECT id FROM facts)))
  UNION ALL SELECT 'S20','public.assertion.objekt person', (SELECT count(*) FROM public.assertion a, params p WHERE a.objekt_type='person' AND a.objekt_id=p.pid)
  -- Punkt 2b: narrativ/publikation/formidling
  UNION ALL SELECT 'S21','public.narrative (subjekt person)', (SELECT count(*) FROM narr)
  UNION ALL SELECT 'S22','private.narrative_record_publication', (SELECT count(*) FROM private.narrative_record_publication b WHERE b.narrative_id IN (SELECT id FROM narr))
  UNION ALL SELECT 'S23','private.narrative_publication_event [BLOKERER, append-only]', (SELECT count(*) FROM private.narrative_publication_event e WHERE e.narrative_id IN (SELECT id FROM narr))
  UNION ALL SELECT 'S23b','andres publication-events/legacy-baselines med P i state (jsonb)', (SELECT
         (SELECT count(*) FROM private.narrative_publication_event e, jrx
           WHERE e.narrative_id NOT IN (SELECT id FROM narr)
             AND (e.before_state::text ~ jrx.rx OR e.after_state::text ~ jrx.rx))
       + (SELECT count(*) FROM private.narrative_legacy_publication l, jrx
           WHERE l.narrative_id NOT IN (SELECT id FROM narr) AND l.baseline_state::text ~ jrx.rx))
  UNION ALL SELECT 'S24','private.narrative_legacy_publication', (SELECT count(*) FROM private.narrative_legacy_publication l WHERE l.narrative_id IN (SELECT id FROM narr))
  UNION ALL SELECT 'S25','public.haendelse under P''s narrativer (CASCADE)', (SELECT count(*) FROM public.haendelse h WHERE h.narrative_id IN (SELECT id FROM narr))
  UNION ALL SELECT 'S26','public.haendelse subjekt P under andres narrativ', (SELECT count(*) FROM public.haendelse h, params p
       WHERE h.subjekt_type='person' AND h.subjekt_id=p.pid AND h.narrative_id NOT IN (SELECT id FROM narr))
  UNION ALL SELECT 'S27','public.haendelse (andres) forankret i P''s fakta/relationer', (SELECT count(*) FROM public.haendelse h
       WHERE (h.fact_id IN (SELECT id FROM facts) OR h.relation_id IN (SELECT id FROM rels))
         AND h.narrative_id NOT IN (SELECT id FROM narr))
  UNION ALL SELECT 'S28','public.text_mention med kilde = P''s narrativ/note', (SELECT count(*) FROM public.text_mention t, params p
       WHERE (t.kilde_type='narrative' AND t.kilde_id IN (SELECT id FROM narr))
          OR (t.kilde_type='note' AND t.kilde_id IN (SELECT o.id FROM public.note o WHERE o.target_type='person' AND o.target_id=p.pid)))
  UNION ALL SELECT 'S29','public.text_mention maal = P (token i andres prosa)', (SELECT count(*) FROM public.text_mention t, params p
       WHERE t.maal_type='person' AND t.maal_id=p.pid
         AND NOT (t.kilde_type='narrative' AND t.kilde_id IN (SELECT id FROM narr)))
  UNION ALL SELECT 'S30','public.story (subjekt person)', (SELECT count(*) FROM p_story)
  UNION ALL SELECT 'S30b','public.story_kilde (CASCADE fra story)', (SELECT count(*) FROM public.story_kilde k WHERE k.story_id IN (SELECT id FROM p_story))
  UNION ALL SELECT 'S31','public.story (andres) forankret i P''s fakta/relationer (SET NULL)', (SELECT count(*) FROM public.story s
       WHERE (s.fact_id IN (SELECT id FROM facts) OR s.relation_id IN (SELECT id FROM rels))
         AND s.id NOT IN (SELECT id FROM p_story))
  UNION ALL SELECT 'S32','public.feed_pin (person-nøgler, dagensperson, story:<S>, arkiv:/paadennedag:h:<H>)', (SELECT count(*) FROM public.feed_pin f, feed_rx fx
       WHERE f.kort_noegle ~ fx.rx
          OR f.kort_noegle IN (SELECT k FROM feed_keys))
  UNION ALL SELECT 'S32b','public.feed_pin forbundet:<P''s familie>', (SELECT count(*) FROM public.feed_pin f
       WHERE f.kort_noegle IN (SELECT 'forbundet:' || id FROM fams))
  UNION ALL SELECT 'S33','public.entity_description (subjekt person)', (SELECT count(*) FROM public.entity_description d, params p WHERE d.subjekt_type='person' AND d.subjekt_id=p.pid)
  UNION ALL SELECT 'S33b','private.entity_description_source (CASCADE)', (SELECT count(*) FROM private.entity_description_source s
       WHERE s.description_id IN (SELECT d.id FROM public.entity_description d, params p WHERE d.subjekt_type='person' AND d.subjekt_id=p.pid))
  UNION ALL SELECT 'S34','public.suggestion (subjekt person)', (SELECT count(*) FROM public.suggestion g, params p WHERE g.subjekt_type='person' AND g.subjekt_id=p.pid)
  -- Punkt 2c: rettelsesjournaler, medier, familier
  UNION ALL SELECT 'S35','public.import_korrektion (via import_key+record_key)', (SELECT count(*) FROM public.import_korrektion ik
       WHERE EXISTS (SELECT 1 FROM p_import_keys k WHERE k.import_key=ik.import_key AND k.record_key=ik.record_key))
  UNION ALL SELECT 'S36','public.paastand_korrektion (levende+historiske assertions)', (SELECT count(*) FROM public.paastand_korrektion k
       WHERE k.assertion_id::text IN (SELECT idt FROM hist_asrt))
  UNION ALL SELECT 'S37','public.media koblet til P (alle)', (SELECT count(*) FROM media_ids)
  UNION ALL SELECT 'S37b','public.media eksklusivt for P', (SELECT count(*) FROM media_excl)
  UNION ALL SELECT 'S37c','storage-objekter for eksklusive medier (media+varianter)', (SELECT
         (SELECT count(*) FROM public.media m WHERE m.id IN (SELECT id FROM media_excl) AND m.storage_path IS NOT NULL)
       + (SELECT count(*) FROM public.media_variant v WHERE v.media_id IN (SELECT id FROM media_excl)))
  UNION ALL SELECT 'S38','public.family hvor P er medlem', (SELECT count(*) FROM fams)
  UNION ALL SELECT 'S38b','public.family hvor P er eneste medlem', (SELECT count(*) FROM fams f, params p
       WHERE NOT EXISTS (SELECT 1 FROM public.family_member fm WHERE fm.family_id=f.id AND fm.person_id<>p.pid))
  UNION ALL SELECT 'S38c','public.fact (subjekt family) på P''s familier', (SELECT count(*) FROM public.fact f WHERE f.subjekt_type='family' AND f.subjekt_id IN (SELECT id FROM fams))
  UNION ALL SELECT 'S38d','public.narrative/note på P''s familier', (SELECT
         (SELECT count(*) FROM public.narrative n WHERE n.subjekt_type='family' AND n.subjekt_id IN (SELECT id FROM fams))
       + (SELECT count(*) FROM public.note o WHERE o.target_type='family' AND o.target_id IN (SELECT id FROM fams)))
  -- Punkt 2d: private ledgers
  UNION ALL SELECT 'S39','private.interpretation_promotion (mål = P-entitet)', (SELECT count(*) FROM private.interpretation_promotion ip, params p
       WHERE (ip.target_type='person' AND ip.target_id=p.pid)
          OR (ip.target_type='fact' AND ip.target_id::text IN (SELECT idt FROM hist_facts))
          OR (ip.target_type='assertion' AND ip.target_id::text IN (SELECT idt FROM hist_asrt))
          OR (ip.target_type='relation' AND ip.target_id::text IN (SELECT idt FROM hist_rels))
          OR (ip.target_type='narrative' AND ip.target_id::text IN (SELECT idt FROM hist_narr))
          OR (ip.target_type='haendelse' AND ip.target_id IN (SELECT id FROM p_haendelse))
          OR (ip.target_type='family' AND ip.target_id IN (SELECT id FROM fams)))
  UNION ALL SELECT 'S40','private.legacy_placement_disposition', (SELECT count(*) FROM private.legacy_placement_disposition d, params p WHERE d.person_id=p.pid)
  UNION ALL SELECT 'S41','private.reimport_event (kolonne eller payload-nøgle)', (SELECT count(*) FROM private.reimport_event e, params p, jrx
       WHERE e.canonical_person_id=p.pid OR e.payload::text ~ jrx.rx)
  UNION ALL SELECT 'S42','private.reimport_name_completion_result', (SELECT count(*) FROM private.reimport_name_completion_result r, params p WHERE r.person_id=p.pid)
  UNION ALL SELECT 'S43','private.reimport_case_event.payload (heuristik)', (SELECT count(*) FROM private.reimport_case_event e, jrx WHERE e.payload::text ~ jrx.rx)
  UNION ALL SELECT 'S44','private.reimport_(case_)authorization.authorized_elements (heuristik)', (SELECT
         (SELECT count(*) FROM private.reimport_authorization a, jrx WHERE a.authorized_elements::text ~ jrx.rx)
       + (SELECT count(*) FROM private.reimport_case_authorization a, jrx WHERE a.authorized_elements::text ~ jrx.rx))
  UNION ALL SELECT 'S45','private.identity_control_parent_card', (SELECT count(*) FROM private.identity_control_parent_card c, params p
       WHERE c.counterpart_person_id=p.pid OR p.pid = ANY(c.partner_ids))
  UNION ALL SELECT 'S46','private.identity_control_sample (mapping/expected via kandidat-uuid for P)', (SELECT count(*) FROM private.identity_control_sample s
       WHERE EXISTS (SELECT 1 FROM private.source_persona_identity_candidate c, params p
                      WHERE c.candidate_person_id=p.pid
                        AND (s.expected = c.id::text
                          OR (jsonb_typeof(s.mapping)='object'
                              AND EXISTS (SELECT 1 FROM jsonb_each_text(s.mapping) m WHERE m.value = c.id::text)))))
  UNION ALL SELECT 'S47','personas koblet via S10/S11 (bog-lag, BEVARES)', (SELECT count(*) FROM personas)
  UNION ALL SELECT 'S48','private.interpretation_promotion familiebindinger på P''s familier (hash bliver stale)', (SELECT count(*) FROM private.interpretation_promotion ip
       WHERE ip.target_type='family' AND ip.target_id IN (SELECT id FROM fams))
  UNION ALL SELECT 'S49','private.relation_reopen/marriage_ordinal_correction på P''s familier', (SELECT
         (SELECT count(*) FROM private.relation_reopen r WHERE r.from_family_id IN (SELECT id FROM fams) OR r.to_family_id IN (SELECT id FROM fams))
       + (SELECT count(*) FROM private.marriage_ordinal_correction m WHERE m.family_id IN (SELECT id FROM fams)))
  UNION ALL SELECT 'S50','private.narrative_record_cutover_receipt.result (heuristik)', (SELECT count(*) FROM private.narrative_record_cutover_receipt r, jrx WHERE r.result::text ~ jrx.rx)
  UNION ALL SELECT 'S51','private.identity_relation_update_prelock (transient)', (SELECT count(*) FROM private.identity_relation_update_prelock x, params p WHERE p.pid = ANY(x.locked_person_ids))
  -- Punkt 3: historik
  UNION ALL SELECT 'S52','public.change_set (subjekt person)', (SELECT count(*) FROM public.change_set cs, params p WHERE cs.subjekt_type='person' AND cs.subjekt_id=p.pid)
  UNION ALL SELECT 'S53','public.change_set summary nævner tallet, P ikke subjekt (heuristik)', (SELECT count(*) FROM public.change_set cs, params p
       WHERE cs.summary ~ ('\m' || p.pidt || '\M')
         AND NOT (coalesce(cs.subjekt_type,'')='person' AND cs.subjekt_id IS NOT DISTINCT FROM p.pid))
  UNION ALL SELECT 'S53b','public.change_set der oprettede P (summary bærer navnet)', (SELECT count(DISTINCT h.change_set_id) FROM ce_hits h WHERE h.tabel='person' AND h.op='INSERT')
  UNION ALL SELECT 'S54','public.change_event om P (alle tabeller)', (SELECT count(*) FROM ce_hits)
  UNION ALL SELECT 'S54b','public.change_set med mindst ét P-event eller P som subjekt', (SELECT count(*) FROM hit_sets)
  UNION ALL SELECT 'S54c','public.change_event i andres narrativer med [[person:P|', (SELECT count(*) FROM public.change_event ce, params p
       WHERE ce.tabel='narrative'
         AND ce.row_pk->>'id' NOT IN (SELECT idt FROM hist_narr)
         AND (position('[[person:' || p.pidt || '|' IN coalesce(ce.foer->>'tekst','')) > 0
           OR position('[[person:' || p.pidt || '|' IN coalesce(ce.efter->>'tekst','')) > 0))
  UNION ALL SELECT 'S55','public.change_set reversal-kæde (rekursiv)', (SELECT count(*) FROM rev_chain)
  UNION ALL SELECT 'S56','FK ind i hit-sæt: narrative_publication_event [append-only]', (SELECT count(*) FROM private.narrative_publication_event e WHERE e.change_set_id IN (SELECT id FROM hit_sets))
  UNION ALL SELECT 'S56b','FK ind i hit-sæt: paastand_korrektion', (SELECT count(*) FROM public.paastand_korrektion k WHERE k.change_set_id IN (SELECT id FROM hit_sets))
  UNION ALL SELECT 'S56c','FK ind i hit-sæt: private.reimport_case_batch', (SELECT count(*) FROM private.reimport_case_batch b WHERE b.change_set_id IN (SELECT id FROM hit_sets))
  UNION ALL SELECT 'S57','change_event i hit-sæt der ikke kan henføres til P', (SELECT count(*) FROM public.change_event ce
       WHERE ce.change_set_id IN (SELECT id FROM hit_sets) AND ce.id NOT IN (SELECT id FROM ce_hits))
  -- S58: øvrige jsonb-kolonner (heuristik)
  UNION ALL SELECT 'S58a','private.interpretation_promotion.evidence', (SELECT count(*) FROM private.interpretation_promotion x, jrx WHERE x.evidence::text ~ jrx.rx)
  UNION ALL SELECT 'S58b','private.interpretation.value/decision_evidence', (SELECT count(*) FROM private.interpretation x, jrx WHERE x.value::text ~ jrx.rx OR x.decision_evidence::text ~ jrx.rx)
  UNION ALL SELECT 'S58c','private.source_persona_identity_candidate.basis', (SELECT count(*) FROM private.source_persona_identity_candidate x, jrx WHERE x.basis::text ~ jrx.rx)
  UNION ALL SELECT 'S58d','private.relation_reopen.context', (SELECT count(*) FROM private.relation_reopen x, jrx WHERE x.context::text ~ jrx.rx)
  UNION ALL SELECT 'S58e','private.text_revision_reconciliation.context', (SELECT count(*) FROM private.text_revision_reconciliation x, jrx WHERE x.context::text ~ jrx.rx)
  UNION ALL SELECT 'S58f','private.relation_classification_event.evidence', (SELECT count(*) FROM private.relation_classification_event x, jrx WHERE x.evidence::text ~ jrx.rx)
  UNION ALL SELECT 'S58g','private.marriage_ordinal_correction.evidence', (SELECT count(*) FROM private.marriage_ordinal_correction x, jrx WHERE x.evidence::text ~ jrx.rx)
  UNION ALL SELECT 'S58h','private.legacy_placement_disposition.evidence', (SELECT count(*) FROM private.legacy_placement_disposition x, jrx WHERE x.evidence::text ~ jrx.rx)
  UNION ALL SELECT 'S58i','private.source_(record|persona)_placement_decision.evidence', (SELECT
         (SELECT count(*) FROM private.source_record_placement_decision x, jrx WHERE x.evidence::text ~ jrx.rx)
       + (SELECT count(*) FROM private.source_persona_placement_decision x, jrx WHERE x.evidence::text ~ jrx.rx))
  UNION ALL SELECT 'S58j','public.suggestion.payload', (SELECT count(*) FROM public.suggestion x, jrx WHERE x.payload::text ~ jrx.rx)
)
SELECT nr AS sted, sted AS tabel, antal FROM counts ORDER BY nr;

ROLLBACK;
