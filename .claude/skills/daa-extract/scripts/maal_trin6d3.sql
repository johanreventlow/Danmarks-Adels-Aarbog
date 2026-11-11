-- Læse-kun måling til trin 6d-3's DDL og dataceremoni (D, O, R): kun antal og hashes, ingen navne eller tekst.
-- Brug: psql -X -At -v ON_ERROR_STOP=1 -v fase=<foer|ddl|d|o|r> -v src=<den nye udgaves kilde> -v k1_src=<kilden, der
--   ikke skrives> -v skjul_person=<person-id> -f maal_trin6d3.sql
-- Alle fire variabler er påkrævede (ingen standardværdier; ingen kilde- eller person-id'er i scriptet). fase sættes af
-- runneren (målingen afleder den ikke) og ekkoes.
-- Én linje:
--   T6D3_MAAL fase=<…> forslag_k3=<m/p/c> bundne_k3=<n> samme_som=<n> dobbelt=<n> privat_1791=<0|1> uden_position=<n>
--     K1_ORD=<md5> K1_BIND=<md5> FAMKILDER=<md5>
--   forslag_k3    src's gældende fortolkninger med status proposed: relation.marriage / relation.parent / relation.child
--   bundne_k3     src's relation.*-fortolkninger, der er bundet (definitionen under bundet)
--   samme_som     antal samme_som-relationer person→person
--   dobbelt       D-kandidater: familier, hvor en p39-person h er partner, h har en samme_som (nogen retning), den anden
--                 partner s findes og har ingen samme_som (nogen retning), og en tvillingfamilie findes: en familie ≠ denne
--                 med en partner t1 ∉ p39, kanonisk(t1)=kanonisk(h), og en anden partner t2 (samme definition som
--                 tvillingmængden i samme_som_kort_ceremoni.sql; p39 = person_external_id med source_id=src)
--   privat_1791   skjul_person's privat-flag (0/1); personen skal findes
--   uden_position src's ægteskaber (relation_marriage_ordinals over occurrences af src's ikke-afviste relation.marriage-
--                 fortolkningers supporting-observation nr. 1), hvis række har post_offset NULL
--   K1_ORD        md5 over relation_marriage_ordinals-rækkerne (occurrence|interpretation_key|nummer|post_offset) for alle
--                 k1_src's ægteskabs-occurrences (samme occurrence-definition som uden_position)
--   K1_BIND       md5 over k1_src's bundne relation.*-fortolkninger (interpretation_key|predicate|familie|version-id|sha)
--   FAMKILDER     md5 over public_family_sources(alle familier med family_offentlig) kaldt som anon
--   bundet        læsergatens definition (public_family_sources' b/ok-CTE, schema.sql) uden family_offentlig: promotion
--                 (structural_family, target_type family) findes, den promoverede version er den aktuelle og accepterede,
--                 og den gemte state_sha256 = reimport_canonical_json_sha256(relation_binding_state(version)), hvis
--                 family_id = promotionens familie. En ikke-NULL relation_binding_state alene betyder kun »kan bindes«.
-- K1_ORD, K1_BIND og FAMKILDER over en tom mængde er en fejl (T6D3_MAAL_TOM <felter>): en md5 af ingenting beviser
-- intet. T6D3_MAAL_ARGS: en variabel mangler eller har forkert form.
\set QUIET on
\set ON_ERROR_STOP on
\if :{?fase} \else \set fase '' \endif
\if :{?src} \else \set src '' \endif
\if :{?k1_src} \else \set k1_src '' \endif
\if :{?skjul_person} \else \set skjul_person '' \endif
BEGIN READ ONLY;
SET LOCAL statement_timeout = '15min';
SELECT :'fase' IN ('foer','ddl','d','o','r') AND :'src' ~ '^-?[0-9]+$' AND :'k1_src' ~ '^-?[0-9]+$'
       AND :'skjul_person' ~ '^-?[0-9]+$' AND :'src'<>:'k1_src' AS args_ok \gset
\if :args_ok
\else
DO $args$ BEGIN RAISE EXCEPTION 'T6D3_MAAL_ARGS'; END $args$;
\endif
SELECT count(*) FILTER (WHERE predicate='relation.marriage') AS m,count(*) FILTER (WHERE predicate='relation.parent') AS p,
       count(*) FILTER (WHERE predicate='relation.child') AS c
  FROM private.interpretation_current WHERE source_id=:src AND status='proposed' \gset forslag_
SELECT count(*) AS samme_som FROM public.relation WHERE rolle='samme_som' AND subjekt_type='person' AND objekt_type='person' \gset m_
SELECT coalesce((SELECT CASE WHEN privat THEN '1' ELSE '0' END FROM public.person WHERE id=:skjul_person),'-') AS privat \gset m_
SELECT :'m_privat'='-' AS mangler \gset
\if :mangler
DO $args$ BEGIN RAISE EXCEPTION 'T6D3_MAAL_ARGS skjul_person findes ikke'; END $args$;
\endif
-- Bundne fortolkninger (læsergatens definition uden family_offentlig).
WITH b AS (
  SELECT cur.source_id,cur.predicate,cur.interpretation_key,p.interpretation_id,p.target_id AS fam,
         p.evidence->>'state_sha256' AS bound_sha,st.st
    FROM private.interpretation_promotion p
    JOIN private.interpretation_promotion_rule r
      ON r.rule_key=p.rule_key AND r.rule_version=p.rule_version AND r.rule_mode='structural_family'
    JOIN private.interpretation q ON q.id=p.interpretation_id
    JOIN private.interpretation_current cur ON cur.interpretation_key=q.interpretation_key
    CROSS JOIN LATERAL (SELECT private.relation_binding_state(p.interpretation_id) AS st) st
   WHERE p.target_type='family' AND cur.id=p.interpretation_id AND cur.status='accepted'
     AND cur.source_id IN (:src,:k1_src) AND cur.predicate LIKE 'relation.%'
), ok AS (
  SELECT b.* FROM b
   WHERE b.st IS NOT NULL
     AND private.reimport_canonical_json_sha256(b.st)=b.bound_sha
     AND (b.st#>>'{family,family_id}')::bigint=b.fam
)
SELECT count(*) FILTER (WHERE source_id=:src) AS bundne_k3,
       count(*) FILTER (WHERE source_id=:k1_src) AS n_k1bind,
       md5(coalesce(string_agg(concat_ws('|',interpretation_key,predicate,fam,interpretation_id,bound_sha),E'\n'
             ORDER BY interpretation_key::text COLLATE "C",interpretation_id::text COLLATE "C") FILTER (WHERE source_id=:k1_src),'')) AS k1_bind
  FROM ok \gset m_
-- Ægteskabsnumre (samme occurrence-definition som relation_marriage_ordinals' egen join).
WITH occ AS (
  SELECT DISTINCT ic.source_id,co.occurrence_id
    FROM private.interpretation_current ic
    JOIN private.interpretation_observation io ON io.interpretation_id=ic.id AND io.evidence_role='supporting' AND io.ordinal=1
    JOIN private.clause_observation_current co ON co.id=io.observation_id
   WHERE ic.predicate='relation.marriage' AND ic.status<>'rejected' AND ic.source_id IN (:src,:k1_src)
), o AS (
  SELECT occ.source_id,occ.occurrence_id,x.interpretation_key,x.marriage_ordinal,x.post_offset
    FROM occ CROSS JOIN LATERAL private.relation_marriage_ordinals(occ.occurrence_id) x
)
SELECT count(*) FILTER (WHERE source_id=:src AND post_offset IS NULL) AS uden_position,
       count(*) FILTER (WHERE source_id=:k1_src) AS n_k1ord,
       md5(coalesce(string_agg(concat_ws('|',occurrence_id,interpretation_key,marriage_ordinal,coalesce(post_offset::text,'-')),E'\n'
             ORDER BY occurrence_id::text COLLATE "C",interpretation_key::text COLLATE "C") FILTER (WHERE source_id=:k1_src),'')) AS k1_ord
  FROM o \gset m_
-- D-kandidater.
WITH kanon AS (
  -- BEGIN kanon (samme tekst i samme_som_kort_ceremoni.sql; test_maal_trin6d3.py låser det)
  WITH RECURSIVE k(start,cur,d) AS (
    SELECT p.id,p.id,0 FROM public.person p
    UNION ALL
    SELECT k.start,ss.objekt_id,k.d+1 FROM k JOIN public.relation ss
        ON ss.rolle='samme_som' AND ss.subjekt_type='person' AND ss.objekt_type='person' AND ss.subjekt_id=k.cur
     WHERE k.d<20)
  SELECT DISTINCT ON (k.start) k.start AS person_id,k.cur AS kanon FROM k ORDER BY k.start,k.d DESC
  -- END kanon
), p39 AS (
  SELECT DISTINCT e.person_id FROM public.person_external_id e WHERE e.source_id=:src AND e.person_id IS NOT NULL
), ssp AS (
  SELECT subjekt_id AS pid FROM public.relation WHERE rolle='samme_som' AND subjekt_type='person' AND objekt_type='person'
  UNION
  SELECT objekt_id FROM public.relation WHERE rolle='samme_som' AND subjekt_type='person' AND objekt_type='person'
)
SELECT count(DISTINCT h.family_id) AS dobbelt
  FROM public.family_member h
  JOIN public.family_member s ON s.family_id=h.family_id AND s.rolle='partner' AND s.person_id<>h.person_id
  JOIN kanon kh ON kh.person_id=h.person_id
 WHERE h.rolle='partner' AND h.person_id IN (SELECT person_id FROM p39)
   AND h.person_id IN (SELECT pid FROM ssp) AND s.person_id NOT IN (SELECT pid FROM ssp)
   AND EXISTS (SELECT 1 FROM public.family_member t1
                 JOIN public.family_member t2 ON t2.family_id=t1.family_id AND t2.rolle='partner' AND t2.person_id<>t1.person_id
                 JOIN kanon k1 ON k1.person_id=t1.person_id
                WHERE t1.rolle='partner' AND t1.family_id<>h.family_id
                  AND t1.person_id NOT IN (SELECT person_id FROM p39) AND k1.kanon=kh.kanon) \gset m_
-- Familiekilder som anon (familielisten beregnes som ejer).
SELECT '{'||coalesce((SELECT string_agg(id::text,',' ORDER BY id) FROM public.family WHERE public.family_offentlig(id)),'')||'}' AS fids \gset
SET LOCAL ROLE anon;
SELECT count(*) AS n_famkilder,md5(coalesce(string_agg(s::text,E'\n' ORDER BY s::text COLLATE "C"),'')) AS famkilder
  FROM public.public_family_sources(:'fids'::bigint[]) s \gset m_
RESET ROLE;
SELECT concat_ws(',',CASE WHEN :m_n_k1ord=0 THEN 'K1_ORD' END,CASE WHEN :m_n_k1bind=0 THEN 'K1_BIND' END,
                 CASE WHEN :m_n_famkilder=0 THEN 'FAMKILDER' END) AS tomme,
       (:m_n_k1ord=0 OR :m_n_k1bind=0 OR :m_n_famkilder=0) AS tom \gset
\if :tom
SELECT set_config('t6d3.tomme',:'tomme',true) \g /dev/null
DO $tom$ BEGIN RAISE EXCEPTION 'T6D3_MAAL_TOM %',current_setting('t6d3.tomme'); END $tom$;
\endif
SELECT format('T6D3_MAAL fase=%s forslag_k3=%s/%s/%s bundne_k3=%s samme_som=%s dobbelt=%s privat_1791=%s uden_position=%s K1_ORD=%s K1_BIND=%s FAMKILDER=%s',
              :'fase',:'forslag_m',:'forslag_p',:'forslag_c',:'m_bundne_k3',:'m_samme_som',:'m_dobbelt',:'m_privat',
              :'m_uden_position',:'m_k1_ord',:'m_k1_bind',:'m_famkilder');
ROLLBACK;
