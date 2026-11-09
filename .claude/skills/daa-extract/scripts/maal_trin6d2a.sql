-- Læse-kun måling til trin 6d-2a's DDL (oversigtsreglen, data-styret samme_som-retning) og dataceremoni
-- (identitet_ceremoni.sql): kun antal og hashes, ingen id'er, navne eller tekst.
-- Brug: psql -X -At -v ON_ERROR_STOP=1 [-v src=3] -v par_a=<person> -v par_b=<person> -f maal_trin6d2a.sql
-- Én linje:
--   T6D2A_MAAL fase=<foer|ddl|data> regel=<n|na> synlige_anon=<n|na> bio_oversigt=<n|na> kanter_par=<0|1> unresolved=<n>
--     uden_identitet=<n> KOORD_2018_20=<md5> KOORD_SRC=<md5> FAKTA=<md5> BIO=<md5>
--   fase               foer  DDL'en er ikke kørt (private.overview_mention_narratives findes ikke)
--                      ddl   DDL på plads, ceremoniens kvittering findes ikke
--                      data  ceremoniens kvittering (change_set 'identitet_ceremoni', summary 'T6D2A_OK …') findes;
--                            den skrives også ved fire N, så fasen siger »ceremonien er kørt«, ikke »der er skrevet«
--   regel              antal rækker reglen private.overview_mention_narratives giver for alle personer (na i foer)
--   synlige_anon       hvor mange af reglens narrativer anon stadig kan læse direkte (SELECT … FROM public.narrative som anon;
--                      narrativ-RLS er bevidst uændret, så tallet er ikke 0)
--   bio_oversigt       hvor mange af reglens narrativer biografilæseren v2 stadig leverer som anon (skal være 0 efter DDL)
--   kanter_par         antal samme_som-kanter mellem par_a og par_b, begge retninger (0 eller 1)
--   unresolved         kildens personas, hvis identitet er unresolved
--   uden_identitet     kildens personas uden identitetsrække
--   KOORD_2018_20      md5 over public_person_source_coordinates()-rækkerne med source_id <> kilden (som maal_trin6d1.sql)
--   KOORD_SRC          samme over rækkerne med source_id = kilden
--   FAKTA              md5 over public_person_facts + public_family_sources for alle offentlige personer (som anon)
--   BIO                md5 over biografilæseren v2 for de samme personer (som anon)
-- Definitionerne er tal og hashes, ingen forventninger; runneren sammenligner med sine egne -v expect_*.
-- par_a og par_b er påkrævede (uden dem fejler psql); ingen person-id'er står i scriptet. FAKTA/BIO-udtrykkene er de
-- samme som i identitet_ceremoni.sql (pg_temp.t6_fakta), så ceremoniens POST-sammenligning svarer til denne måling.
\set QUIET on
\set ON_ERROR_STOP on
\if :{?src} \else \set src 3 \endif
BEGIN READ ONLY;
SET LOCAL statement_timeout = '15min';
SELECT to_regprocedure('private.overview_mention_narratives(bigint[])') IS NOT NULL AS ddl,
       EXISTS (SELECT 1 FROM public.change_set WHERE operation='identitet_ceremoni' AND summary LIKE 'T6D2A\_OK %'
                 AND subjekt_type='source' AND subjekt_id=:src) AS kvit \gset
SELECT CASE WHEN NOT :'ddl'::boolean THEN 'foer' WHEN :'kvit'::boolean THEN 'data' ELSE 'ddl' END AS fase \gset
SELECT count(*) FILTER (WHERE i.decision_status='unresolved') AS unresolved,
       count(*) FILTER (WHERE i.source_persona_id IS NULL) AS uden_identitet
  FROM private.source_persona sp
  LEFT JOIN private.source_persona_identity i ON i.source_persona_id=sp.id
 WHERE sp.source_id=:src \gset m_
SELECT count(*) AS kanter_par FROM public.relation
 WHERE rolle='samme_som' AND subjekt_type='person' AND objekt_type='person'
   AND ((subjekt_id=:par_a AND objekt_id=:par_b) OR (subjekt_id=:par_b AND objekt_id=:par_a)) \gset m_
-- De offentlige personer og alle familier (som ejer; selve hashen beregnes som anon).
SELECT '{'||coalesce((SELECT string_agg(id::text,',' ORDER BY id) FROM public.person WHERE public.person_offentlig(id)),'')||'}' AS ids,
       '{'||coalesce((SELECT string_agg(id::text,',' ORDER BY id) FROM public.family),'')||'}' AS fids \gset
\if :ddl
-- Reglens rækker (som ejer); teksterne bæres kun i en psql-variabel, aldrig i uddata.
SELECT count(*) AS regel,
       coalesce(jsonb_agg(jsonb_build_object('p',o.person_id,'n',o.narrative_id,'s',o.source_id,'t',n.tekst)),'[]'::jsonb) AS rj
  FROM private.overview_mention_narratives(ARRAY(SELECT id FROM public.person)) o
  JOIN public.narrative n ON n.id=o.narrative_id \gset m_
SET LOCAL ROLE anon;
SELECT count(*) FILTER (WHERE EXISTS (SELECT 1 FROM public.public_person_bio_source_versions_v2(ARRAY[r.p]) b
                                        WHERE b.source_id=r.s AND b.narrative_text=r.t)) AS bio,
       count(*) FILTER (WHERE EXISTS (SELECT 1 FROM public.narrative nn WHERE nn.id=r.n)) AS anon
  FROM jsonb_to_recordset(:'m_rj'::jsonb) r(p bigint,n bigint,s bigint,t text) \gset m_
RESET ROLE;
\else
\set m_regel na
\set m_bio na
\set m_anon na
\endif
SET LOCAL ROLE anon;
SELECT md5(coalesce(string_agg(x,E'\n' ORDER BY x COLLATE "C"),'')) AS fakta
  FROM (SELECT 'f|'||f::text AS x FROM public.public_person_facts(:'ids'::bigint[]) f
        UNION ALL
        SELECT 's|'||s::text FROM public.public_family_sources(:'fids'::bigint[]) s) z \gset
SELECT md5(coalesce(string_agg(b::text,E'\n' ORDER BY b::text COLLATE "C"),'')) AS bio
  FROM public.public_person_bio_source_versions_v2(:'ids'::bigint[]) b \gset
RESET ROLE;
-- Koordinat-hash (samme udtryk som maal_trin6d1.sql og pg_temp.plc_koord i placement_ceremoni.sql).
SELECT md5(coalesce(string_agg(concat_ws('|',quote_nullable(c.person_id),quote_nullable(c.source_id),
         quote_nullable(c.legacy_line_code),quote_nullable(c.printed_number),quote_nullable(c.printed_number_label),
         quote_nullable(c.generation_local),quote_nullable(c.generation_global),quote_nullable(c.kuld_label),
         quote_nullable(c.provenance_kind)),E'\n' ORDER BY c.person_id,c.source_id) FILTER (WHERE c.source_id<>:src),'')) AS k_andre,
       md5(coalesce(string_agg(concat_ws('|',quote_nullable(c.person_id),quote_nullable(c.source_id),
         quote_nullable(c.legacy_line_code),quote_nullable(c.printed_number),quote_nullable(c.printed_number_label),
         quote_nullable(c.generation_local),quote_nullable(c.generation_global),quote_nullable(c.kuld_label),
         quote_nullable(c.provenance_kind)),E'\n' ORDER BY c.person_id,c.source_id) FILTER (WHERE c.source_id=:src),'')) AS k_src
  FROM public.public_person_source_coordinates() c \gset
SELECT format('T6D2A_MAAL fase=%s regel=%s synlige_anon=%s bio_oversigt=%s kanter_par=%s unresolved=%s uden_identitet=%s KOORD_2018_20=%s KOORD_SRC=%s FAKTA=%s BIO=%s',
              :'fase',:'m_regel',:'m_anon',:'m_bio',:'m_kanter_par',:'m_unresolved',:'m_uden_identitet',:'k_andre',:'k_src',:'fakta',:'bio');
ROLLBACK;
