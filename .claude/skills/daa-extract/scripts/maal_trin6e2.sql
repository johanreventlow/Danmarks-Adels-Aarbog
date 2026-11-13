-- Læse-kun måling til trin 6e-2's DDL og dataceremoni (etiket_ceremoni.sql): kun antal og hashes, ingen id'er, navne
-- eller tekst. Brug: psql -X -At -v ON_ERROR_STOP=1 [-v src=3] -f maal_trin6e2.sql
-- Én linje:
--   T6E2_MAAL fase=<foer|ddl|data> KOORD_ANDRE=<md5> ETIKETTER_ANDRE=<md5> BINDINGER_RECORD=<n> SPRUNGET=<n>
--     UDEN_PLACEMENT=<n> STALE=<n> BIO_OFFENTLIGE=<n> FAKTA_BUNDNE=<n> FAMILIEKILDER=<md5> SKEMA_ETIKETTER=<md5>
--   fase              foer  6e-2-DDL'en er ikke kørt (en af markørerne nedenfor mangler)
--                     ddl   DDL på plads, kildens sidekort er NULL (ceremonien ikke kørt)
--                     data  DDL på plads og kildens sidekort er sat (ceremonien kørt)
--   KOORD_ANDRE       md5 over public_person_source_coordinates()'s ni gamle kolonner for source_id <> kilden
--                     (ROW(...)::text, linjeskift, sorteret efter person og kilde). Uændret i alle faser.
--   ETIKETTER_ANDRE   md5 over binding_id|record_label|citation_label for bindinger på andre kilders records, sorteret
--                     efter binding_id. Uændret i alle faser.
--   BINDINGER_RECORD  kildens publicerede bindinger med record_label ~ '^record-', hvis person er offentlig efter
--                     publiceringspolitikken (person_publication_allowed; samme udtryk som ceremonien)
--                     (= ceremoniens expect_bindinger i fase ddl; 0 efter data)
--   SPRUNGET          samme, men ikke-offentlig person (staged/levende/privat): ceremonien springer dem over
--                     (= expect_sprunget; uændret efter data)
--   UDEN_PLACEMENT    af BINDINGER_RECORD uden accepteret placement (= expect_tomme i fase ddl; 0 efter data)
--   STALE             stale_published i hele basen (alle kilder). 0 i alle faser.
--   BIO_OFFENTLIGE    rækker i public_person_bio_source_versions_v2 for alle offentlige personer, kaldt som anon.
--                     Uændret i alle faser (ceremoniens expect_bio_offentlige).
--   FAKTA_BUNDNE      rækker i public_person_facts for alle offentlige personer med record_ref, kaldt som anon.
--                     Uændret i alle faser (ceremoniens expect_fakta_bundne).
--   FAMILIEKILDER     md5 over public_family_sources (alle offentlige familier) som anon. Ændres ved data med vilje
--                     (bindingernes etiketter); uændret fra foer til ddl.
--   SKEMA_ETIKETTER   md5 over kildens linjeskema-entries (code|label, sorteret efter code). Ændres ved data med vilje.
-- Runneren stopper, hvis KOORD_ANDRE eller ETIKETTER_ANDRE i fase ddl eller data afviger fra fase foer. Hash-udtrykkene
-- er tegn for tegn de samme som i etiket_ceremoni.sql (test_maal_trin6e2.py tjekker det), så ceremoniens
-- efterbetingelse kan sammenlignes med fase foer. DDL-markørerne er de samme som ceremoniens ETK_PRE_DDL.
\set QUIET on
\set ON_ERROR_STOP on
\if :{?src} \else \set src 3 \endif
BEGIN READ ONLY;
SET LOCAL statement_timeout = '15min';
SELECT to_regprocedure('public.source_trykt_side(bigint,text)') IS NOT NULL
   AND to_regprocedure('private.narrative_record_wanted_labels(uuid)') IS NOT NULL
   AND to_regprocedure('private.record_key_uden_bognoegle(text)') IS NOT NULL
   AND EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid='public.source'::regclass AND attname='sidekort' AND NOT attisdropped)
   AND coalesce((SELECT position('''''' IN pg_get_constraintdef(oid))>0 FROM pg_constraint
                  WHERE conrelid='private.narrative_record_publication'::regclass
                    AND conname='narrative_record_publication_record_label_check'),false)
   AND coalesce(position('printed_page' IN
                  pg_get_function_result(to_regprocedure('public.public_person_source_coordinates()')))>0,false)
       AS ddl \gset
\if :ddl
SELECT CASE WHEN (SELECT sidekort FROM public.source WHERE id=:src) IS NULL THEN 'ddl' ELSE 'data' END AS fase \gset
\else
\set fase foer
\endif
-- Andre kilders koordinater (ni gamle kolonner; samme udtryk som etiket_ceremoni.sql).
SELECT md5(coalesce(string_agg(ROW(c.person_id,c.source_id,c.legacy_line_code,c.printed_number,c.printed_number_label,
         c.generation_local,c.generation_global,c.kuld_label,c.provenance_kind)::text,E'\n' ORDER BY c.person_id,c.source_id),''))
         AS koord_andre
  FROM public.public_person_source_coordinates() c WHERE c.source_id<>:src \gset
-- Andre kilders bindingsetiketter (samme udtryk som etiket_ceremoni.sql).
SELECT md5(coalesce(string_agg(concat_ws('|',b.id,b.record_label,b.citation_label),E'\n' ORDER BY b.id),''))
         AS etiketter_andre
  FROM private.narrative_record_publication b
  JOIN private.source_record sr ON sr.id=b.source_record_id AND sr.source_id<>:src \gset
SELECT count(*) FILTER (WHERE x.offentlig) AS bindinger_record, count(*) FILTER (WHERE NOT x.offentlig) AS sprunget,
       count(*) FILTER (WHERE x.offentlig AND NOT EXISTS (SELECT 1 FROM private.source_record_placement_current pc
                                           WHERE pc.source_record_id=x.source_record_id AND pc.decision_status='accepted'))
         AS uden_placement
  FROM (SELECT b.source_record_id,
               coalesce((s #>> '{publication_state,publication_policy,person_publication_allowed}')::boolean,false) AS offentlig
          FROM private.narrative_record_publication b
          JOIN private.source_record sr ON sr.id=b.source_record_id AND sr.source_id=:src
          JOIN public.narrative n ON n.id=b.narrative_id AND n.subjekt_type='person',
               LATERAL private.narrative_record_state(n.subjekt_id, sr.source_id, sr.record_key) s
         WHERE b.status='published' AND b.record_label ~ '^record-') x \gset
SELECT count(*) FILTER (WHERE s->>'publication_status'='stale_published') AS stale
  FROM private.narrative_record_publication b
  JOIN private.source_record sr ON sr.id=b.source_record_id
  JOIN public.narrative n ON n.id=b.narrative_id AND n.subjekt_type='person',
       LATERAL private.narrative_record_state(n.subjekt_id, sr.source_id, sr.record_key) s \gset
SELECT md5(coalesce(string_agg(e.code||'|'||e.label,E'\n' ORDER BY e.code COLLATE "C"),'')) AS skema_etiketter
  FROM public.lineage_scheme s JOIN public.lineage_scheme_entry e ON e.scheme_id=s.id
 WHERE s.source_id=:src \gset
-- Læserne som anon (person- og familielisten beregnes som ejer).
SELECT '{'||coalesce((SELECT string_agg(id::text,',' ORDER BY id) FROM public.person WHERE public.person_offentlig(id)),'')||'}' AS ids,
       '{'||coalesce((SELECT string_agg(id::text,',' ORDER BY id) FROM public.family WHERE public.family_offentlig(id)),'')||'}' AS fids \gset
SET LOCAL ROLE anon;
SELECT count(*) AS bio_offentlige FROM public.public_person_bio_source_versions_v2(:'ids'::bigint[]) \gset
SELECT count(*) AS fakta_bundne FROM public.public_person_facts(:'ids'::bigint[]) WHERE record_ref IS NOT NULL \gset
SELECT md5(coalesce(string_agg(s::text,E'\n' ORDER BY s::text COLLATE "C"),'')) AS familiekilder
  FROM public.public_family_sources(:'fids'::bigint[]) s \gset
RESET ROLE;
SELECT format('T6E2_MAAL fase=%s KOORD_ANDRE=%s ETIKETTER_ANDRE=%s BINDINGER_RECORD=%s SPRUNGET=%s UDEN_PLACEMENT=%s STALE=%s BIO_OFFENTLIGE=%s FAKTA_BUNDNE=%s FAMILIEKILDER=%s SKEMA_ETIKETTER=%s',
              :'fase',:'koord_andre',:'etiketter_andre',:'bindinger_record',:'sprunget',:'uden_placement',:'stale',:'bio_offentlige',
              :'fakta_bundne',:'familiekilder',:'skema_etiketter');
ROLLBACK;
