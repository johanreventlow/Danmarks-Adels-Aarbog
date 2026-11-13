-- Læse-kun måling til trin 6d-1's DDL og dataceremoni (placement_ceremoni.sql): kun antal og hashes, ingen id'er,
-- navne eller tekst. Brug: psql -X -At -v ON_ERROR_STOP=1 [-v src=3] -f maal_trin6d1.sql
-- Én linje:
--   T6D1_MAAL fase=<foer|ddl|data> entries=<n> placements=<n> persona=<n> ledger_mapped=<n> ledger_retained=<n>
--     memberships=<n> published=<n> stale=<n> corroborated=<n|na> conflict=<n|na> KOORD_2018_20=<md5> KOORD_SRC=<md5>
--   fase           foer  6d-1-DDL'en er ikke kørt (en af markørerne nedenfor mangler)
--                  ddl   DDL på plads, ingen record-placement for kilden
--                  data  DDL på plads og kildens record-placements findes (ceremonien kørt)
--   entries        kildens stamtavle-entries
--   placements     kildens gældende accepterede record-placements; persona = deres principal_member-persona-placements
--   ledger_*       kildens gældende ledger-rækker (legacy_placement_disposition_current) pr. disposition
--   memberships    linjemedlemskaber med source_basis.source_id = kilden
--   published/stale kildens bindinger (narrative_record_publication → source_record) slået op via recordens nøgle
--   corroborated/conflict komponenttilstande (membership_component_states; na før DDL'en)
--   KOORD_2018_20  md5 over public_person_source_coordinates()-rækkerne med source_id <> kilden i fast orden
--   KOORD_SRC      samme over rækkerne med source_id = kilden
-- Runneren stopper, hvis KOORD_2018_20 i fase ddl eller data afviger fra fase foer. Hash-udtrykket er det samme som
-- i placement_ceremoni.sql (pg_temp.plc_koord), så ceremoniens efterbetingelse kan sammenlignes med fase foer.
-- Markørerne for DDL'en er de samme som ceremoniens PLC_PRE_DDL.
\set QUIET on
\set ON_ERROR_STOP on
\if :{?src} \else \set src 3 \endif
BEGIN READ ONLY;
SET LOCAL statement_timeout = '15min';
SELECT coalesce(position('i.canonical_person_id=p_person_id' IN
                  (SELECT prosrc FROM pg_proc WHERE oid=to_regprocedure('private.record_legacy_disposition(bigint,bigint,text,uuid,jsonb)')))>0,false)
   AND to_regprocedure('private.membership_component_states()') IS NOT NULL
   -- Kildegaten (6d-1; 6e-2 udvidede nøglen og fjernede NULL-filteret, så markøren er gatens fælles del).
   AND coalesce(position('count(DISTINCT (d.scheme_entry_id,' IN
                  (SELECT prosrc FROM pg_proc WHERE oid=to_regprocedure('public.public_person_source_coordinates()')))>0,false)
   AND coalesce(position('PLACEMENT_MEMBERSHIP_FOREIGN_SOURCE' IN
                  (SELECT prosrc FROM pg_proc WHERE oid=to_regprocedure('public.red_promote_placement_memberships(bigint,text)')))>0,false)
       AS ddl \gset
SELECT
  (SELECT count(*) FROM public.lineage_scheme s JOIN public.lineage_scheme_entry e ON e.scheme_id=s.id
    WHERE s.source_id=:src AND s.kind='stamtavle') AS entries,
  (SELECT count(*) FROM private.source_record_placement_current pc JOIN private.source_record r ON r.id=pc.source_record_id
    WHERE r.source_id=:src AND pc.decision_status='accepted') AS placements,
  (SELECT count(*) FROM private.source_persona_placement_current pc
     JOIN private.source_record_placement_current rp ON rp.id=pc.record_placement_id AND rp.decision_status='accepted'
     JOIN private.source_record r ON r.id=rp.source_record_id
    WHERE r.source_id=:src AND pc.decision_status='accepted' AND pc.placement_role='principal_member') AS persona,
  (SELECT count(*) FROM private.legacy_placement_disposition_current
    WHERE source_id=:src AND is_current AND disposition='mapped') AS ledger_mapped,
  (SELECT count(*) FROM private.legacy_placement_disposition_current
    WHERE source_id=:src AND is_current AND disposition='retained_legacy') AS ledger_retained,
  (SELECT count(*) FROM public.person_lineage_membership WHERE source_basis->>'source_id'=:'src') AS memberships \gset m_
SELECT count(*) FILTER (WHERE s->>'publication_status'='published') AS published,
       count(*) FILTER (WHERE s->>'publication_status'='stale_published') AS stale
  FROM private.narrative_record_publication b
  JOIN private.source_record sr ON sr.id=b.source_record_id AND sr.source_id=:src
  JOIN public.narrative n ON n.id=b.narrative_id AND n.subjekt_type='person',
       LATERAL private.narrative_record_state(n.subjekt_id, sr.source_id, sr.record_key) s \gset m_
\if :ddl
SELECT count(*) FILTER (WHERE state='corroborated') AS corroborated, count(*) FILTER (WHERE state='conflict') AS conflict
  FROM private.membership_component_states() \gset m_
\else
\set m_corroborated na
\set m_conflict na
\endif
-- Koordinat-hash (samme udtryk som pg_temp.plc_koord i placement_ceremoni.sql).
SELECT md5(coalesce(string_agg(concat_ws('|',quote_nullable(c.person_id),quote_nullable(c.source_id),
         quote_nullable(c.legacy_line_code),quote_nullable(c.printed_number),quote_nullable(c.printed_number_label),
         quote_nullable(c.generation_local),quote_nullable(c.generation_global),quote_nullable(c.kuld_label),
         quote_nullable(c.provenance_kind)),E'\n' ORDER BY c.person_id,c.source_id) FILTER (WHERE c.source_id<>:src),'')) AS k_andre,
       md5(coalesce(string_agg(concat_ws('|',quote_nullable(c.person_id),quote_nullable(c.source_id),
         quote_nullable(c.legacy_line_code),quote_nullable(c.printed_number),quote_nullable(c.printed_number_label),
         quote_nullable(c.generation_local),quote_nullable(c.generation_global),quote_nullable(c.kuld_label),
         quote_nullable(c.provenance_kind)),E'\n' ORDER BY c.person_id,c.source_id) FILTER (WHERE c.source_id=:src),'')) AS k_src
  FROM public.public_person_source_coordinates() c \gset
SELECT CASE WHEN NOT :'ddl'::boolean THEN 'foer' WHEN :m_placements>0 THEN 'data' ELSE 'ddl' END AS fase \gset
SELECT format('T6D1_MAAL fase=%s entries=%s placements=%s persona=%s ledger_mapped=%s ledger_retained=%s memberships=%s published=%s stale=%s corroborated=%s conflict=%s KOORD_2018_20=%s KOORD_SRC=%s',
              :'fase',:'m_entries',:'m_placements',:'m_persona',:'m_ledger_mapped',:'m_ledger_retained',:'m_memberships',
              :'m_published',:'m_stale',:'m_corroborated',:'m_conflict',:'k_andre',:'k_src');
ROLLBACK;
