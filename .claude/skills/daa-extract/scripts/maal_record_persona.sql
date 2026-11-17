-- Læse-kun måling til record_persona (persona for en helpost uden tekst): DDL'en (operationen og spærringen) og
-- dataceremonien (record_persona_ceremoni.sql). Kun antal og hashes, ingen id'er, navne eller tekst.
-- Brug: psql -X -At -v ON_ERROR_STOP=1 -v src=<kilde> -v manifest_path=<ceremoniens manifest (JSONL)> -f maal_record_persona.sql
-- Tallene regnes for manifestets poster: hver linje bærer record_key, person_id og mention_id (helpostens mention); andre
-- felter læses ikke. Scriptet nævner ingen kilde, udgave, post eller person; begge -v er påkrævede.
-- Én linje:
--   T_RP_MAAL fase=<foer|ddl|data> personas=<n> identiteter=<n> placements=<n> kladder=<n> eligible=<n>
--     header_violations=<n> synlige_1939=<n> KOORD_2018_20=<md5> KOORD_SRC=<md5> FAKTA=<md5> BIO=<md5>
--   fase               foer  DDL'en er ikke kørt (public.red_apply_reimport_record_persona findes ikke)
--                      ddl   DDL på plads; ceremonien er ikke kørt for manifestet
--                      data  ceremoniens kvittering (change_set 'record_persona_ceremoni' med kilden som subjekt,
--                            summary 'T_RP_OK …') findes, og hver manifestpost har en persona på sin mention
--   personas           manifestposter, hvis mention har en persona i kilden
--   identiteter        manifestposter, hvis persona har en accepteret identitet til linjens person
--   placements         manifestposter med en gældende accepteret record-placement og en accepteret principal_member-
--                      persona-placement for personaen på den
--   kladder            manifestposter med en binding i status draft til en narrativ om linjens person
--   eligible           manifestposter, hvor private.narrative_publication_state(person, kilde, post) er eligible
--                      (accepted_identity før kladden, existing_exact_binding efter)
--   header_violations  private.placement_header_violations(kilde) (hele kilden)
--   synlige_1939       kildens tekster i biografilæseren v2 for alle offentlige personer (som anon); navnet er
--                      kontraktens, tallet gælder -v src
--   KOORD_2018_20      md5 over public_person_source_coordinates()-rækkerne med source_id <> kilden (som maal_trin6d2a.sql)
--   KOORD_SRC          samme over rækkerne med source_id = kilden
--   FAKTA              md5 over public_person_facts + public_family_sources for alle offentlige personer (som anon)
--   BIO                md5 over biografilæseren v2 for de samme personer (som anon)
-- FAKTA-, BIO- og KOORD-udtrykkene er de samme som i maal_trin6d2a.sql og ceremoniens POST-sammenligning
-- (test_maal_record_persona.py holder dem ens). Definitionerne er tal og hashes, ingen forventninger; runneren
-- sammenligner med sine egne.
\set QUIET on
\set ON_ERROR_STOP on
\if :{?src}
\else
DO $$ BEGIN RAISE EXCEPTION 'T_RP_MAAL_ARGS: -v src mangler'; END $$;
\endif
\if :{?manifest_path}
\else
DO $$ BEGIN RAISE EXCEPTION 'T_RP_MAAL_ARGS: -v manifest_path mangler'; END $$;
\endif
\set m `cat -- :'manifest_path'`
BEGIN READ ONLY;
SET LOCAL statement_timeout = '15min';
-- Manifestets poster (record_key, person, mention); en tom eller ugyldig linje stopper målingen.
SELECT coalesce(jsonb_agg(jsonb_build_object('k',x->>'record_key','p',(x->>'person_id')::bigint,'m',(x->>'mention_id')::uuid)
                          ORDER BY o),'[]'::jsonb)::text AS mj,
       count(*) AS n
  FROM (SELECT l::jsonb AS x, o FROM unnest(string_to_array(:'m',E'\n')) WITH ORDINALITY u(l,o) WHERE btrim(l)<>'') y \gset
SELECT :n>0 AS har_poster \gset
\if :har_poster
\else
DO $$ BEGIN RAISE EXCEPTION 'T_RP_MAAL_ARGS: manifestet har ingen poster'; END $$;
\endif
SELECT to_regprocedure('public.red_apply_reimport_record_persona(uuid,text,jsonb)') IS NOT NULL AS ddl,
       EXISTS (SELECT 1 FROM public.change_set WHERE operation='record_persona_ceremoni' AND summary LIKE 'T\_RP\_OK %'
                 AND subjekt_type='source' AND subjekt_id=:src) AS kvit \gset
WITH mf AS (SELECT * FROM jsonb_to_recordset(:'mj'::jsonb) AS t(k text,p bigint,m uuid)),
pe AS (SELECT mf.k,mf.p,sp.id AS persona FROM mf
         JOIN private.source_persona_mention spm ON spm.mention_id=mf.m
         JOIN private.source_persona sp ON sp.id=spm.persona_id AND sp.source_id=:src)
SELECT (SELECT count(DISTINCT k) FROM pe) AS personas,
       (SELECT count(DISTINCT pe.k) FROM pe JOIN private.source_persona_identity i ON i.source_persona_id=pe.persona
         WHERE i.decision_status='accepted' AND i.canonical_person_id=pe.p) AS identiteter,
       (SELECT count(DISTINCT pe.k) FROM pe
          JOIN private.source_persona_placement_current pp ON pp.source_persona_id=pe.persona
           AND pp.decision_status='accepted' AND pp.placement_role='principal_member'
          JOIN private.source_record_placement_current rp ON rp.id=pp.record_placement_id AND rp.decision_status='accepted'
          JOIN private.source_record r ON r.id=rp.source_record_id AND r.source_id=:src AND r.record_key=pe.k) AS placements,
       (SELECT count(DISTINCT mf.k) FROM mf
          JOIN private.source_record r ON r.source_id=:src AND r.record_key=mf.k
          JOIN private.narrative_record_publication b ON b.source_record_id=r.id AND b.status='draft'
          JOIN public.narrative n ON n.id=b.narrative_id AND n.subjekt_type='person' AND n.subjekt_id=mf.p) AS kladder,
       (SELECT count(*) FROM mf
         WHERE private.narrative_publication_state(mf.p,:src,mf.k)#>>'{authority,eligibility_status}'='eligible') AS eligible,
       private.placement_header_violations(:src) AS header_violations \gset m_
SELECT CASE WHEN NOT :'ddl'::boolean THEN 'foer' WHEN :'kvit'::boolean AND :m_personas=:n THEN 'data' ELSE 'ddl' END AS fase \gset
-- De offentlige personer og alle familier (som ejer; selve hashen beregnes som anon).
SELECT '{'||coalesce((SELECT string_agg(id::text,',' ORDER BY id) FROM public.person WHERE public.person_offentlig(id)),'')||'}' AS ids,
       '{'||coalesce((SELECT string_agg(id::text,',' ORDER BY id) FROM public.family),'')||'}' AS fids \gset
SET LOCAL ROLE anon;
SELECT md5(coalesce(string_agg(x,E'\n' ORDER BY x COLLATE "C"),'')) AS fakta
  FROM (SELECT 'f|'||f::text AS x FROM public.public_person_facts(:'ids'::bigint[]) f
        UNION ALL
        SELECT 's|'||s::text FROM public.public_family_sources(:'fids'::bigint[]) s) z \gset
SELECT md5(coalesce(string_agg(b::text,E'\n' ORDER BY b::text COLLATE "C"),'')) AS bio
  FROM public.public_person_bio_source_versions_v2(:'ids'::bigint[]) b \gset
SELECT count(*) AS synlige FROM public.public_person_bio_source_versions_v2(:'ids'::bigint[]) b WHERE b.source_id=:src \gset
RESET ROLE;
-- Koordinat-hash (samme udtryk som maal_trin6d2a.sql og ceremoniens pg_temp.rp_koord).
SELECT md5(coalesce(string_agg(concat_ws('|',quote_nullable(c.person_id),quote_nullable(c.source_id),
         quote_nullable(c.legacy_line_code),quote_nullable(c.printed_number),quote_nullable(c.printed_number_label),
         quote_nullable(c.generation_local),quote_nullable(c.generation_global),quote_nullable(c.kuld_label),
         quote_nullable(c.provenance_kind)),E'\n' ORDER BY c.person_id,c.source_id) FILTER (WHERE c.source_id<>:src),'')) AS k_andre,
       md5(coalesce(string_agg(concat_ws('|',quote_nullable(c.person_id),quote_nullable(c.source_id),
         quote_nullable(c.legacy_line_code),quote_nullable(c.printed_number),quote_nullable(c.printed_number_label),
         quote_nullable(c.generation_local),quote_nullable(c.generation_global),quote_nullable(c.kuld_label),
         quote_nullable(c.provenance_kind)),E'\n' ORDER BY c.person_id,c.source_id) FILTER (WHERE c.source_id=:src),'')) AS k_src
  FROM public.public_person_source_coordinates() c \gset
SELECT format('T_RP_MAAL fase=%s personas=%s identiteter=%s placements=%s kladder=%s eligible=%s header_violations=%s synlige_1939=%s KOORD_2018_20=%s KOORD_SRC=%s FAKTA=%s BIO=%s',
              :'fase',:'m_personas',:'m_identiteter',:'m_placements',:'m_kladder',:'m_eligible',:'m_header_violations',
              :'synlige',:'k_andre',:'k_src',:'fakta',:'bio');
ROLLBACK;
