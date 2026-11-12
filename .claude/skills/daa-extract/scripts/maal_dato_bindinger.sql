-- Læse-kun måling til 2018-20's datobindinger (spec 2026-11-12 §4.2): kun antal og hashes, ingen værdier, navne eller tekst.
-- Brug: psql -X -At -v ON_ERROR_STOP=1 -v source_id=<k> -f maal_dato_bindinger.sql
--   (\ir finder interpretation_control_classification.sql ved siden af scriptet; kilden gives altid eksplicit)
-- Én linje:
--   DATO_MAAL tilstand=<foer|ddl|n|k> versioner_v2=<n> match=<n> real_diff=<n> skrivemaade=<n> accepteret_v2=<n>
--     bundet_v2=<n> post_foedsel=<n> post_doed=<n> alle_bindinger=<n> alle_bindinger_hash=<sha256>
-- Tilstanden afgøres af fakta i basen, ikke af flag:
--   foer  private.normaliser_dato_markoer_v2 findes ikke (DDL ikke kørt)
--   ddl   funktionen findes, men kilden har ingen række (nogen version) med method 'deterministisk-normalisering:dato-markoer-v2'
--   n     v2-rækker findes, men ingen aktuel version med methoden er accepted
--   k     mindst én aktuel v2-version er accepted (en afgørelse kopierer method, så den accepterede version bærer den)
-- Tal (kilden fra -v source_id):
--   versioner_v2   alle kildens rækker i private.interpretation med v2's method (alle versioner og status)
--   match          MATCH + MATCH_SINGLETON, kun for person.birth og person.death. Klassifikationen
--   real_diff      REAL_DIFF   (interpretation_control_classification.sql med daa.control_src = kilden) dækker alle
--   skrivemaade    SKRIVEMAADE aktive assertion-regler for kilden (fx person.title); de tælles ikke her
--   accepteret_v2  aktuelle v2-versioner med status accepted
--   bundet_v2      gældende assertion-bindinger på en aktuel accepteret v2-version af kilden
--   post_foedsel / post_doed  rækker i public_person_facts(alle personer) med kildens source_id, faktatypen fødsel/død
--                  og record_label IS NOT NULL (det, læseren viser)
--   alle_bindinger / alle_bindinger_hash  antal og sha256 over de sorterede linjer '<assertion_id>:<interpretation_key>'
--                  for ALLE gyldige assertion-bindinger på tværs af kilder, sorteret på (assertion_id, nøgle som uuid; byteorden,
--                  uafhængig af collation), forbundet med linjeskift. Før og efter sammenlignes listerne nøglet i runneren.
-- Gyldigheden er private.assertion_binding_current's FROM...WHERE skrevet mængdebaseret (ét join for alle bindinger i stedet
-- for ét kald pr. binding: kaldet koster ca. 130 ms i prod). Låst mod drift i test_maal_dato_bindinger.py: (a) funktionens
-- FROM...WHERE (uden 'p.id=p_promotion_id AND', whitespace normaliseret) i schema.sql og i den seneste definition i
-- db-migrations.sql skal stå ordret i CTE'en m_b her; (b) en fixture med én binding pr. ugyldighedsgren giver samme antal og
-- hash som et kald til funktionen pr. promotion.
-- -v liste=1: efter DATO_MAAL-linjen skrives de sorterede '<assertion_id>:<interpretation_key>'-linjer (kun id'er), fra
--   samme CTE som hashen (hashen er sha256 over netop disse linjer); uden -v liste er outputtet præcis én linje.
-- versioner_v2 tæller ALLE rækker i private.interpretation for kilden med v2's method (alle versioner, alle status);
-- ddl = ingen sådan række; n = rækker findes, men ingen AKTUEL version med methoden er accepted; k = mindst én aktuel er accepted.
\set QUIET on
\set ON_ERROR_STOP on
\pset format unaligned
\pset tuples_only on
\if :{?source_id} \else \echo MAAL_SOURCE_ID_MANGLER
\quit 3
\endif
BEGIN READ ONLY;
SELECT to_regprocedure('private.normaliser_dato_markoer_v2(text,text)') IS NOT NULL AS ddl \gset

-- Klassifikationen med kildescope; dens JSON (med id'er) skrives ikke ud. Kun birth/death tælles.
SELECT set_config('daa.control_src',:'source_id',true) \g /dev/null
\o /dev/null
\ir interpretation_control_classification.sql
\o
SELECT coalesce(sum(c.n) FILTER (WHERE c.class IN ('MATCH','MATCH_SINGLETON')),0) AS match,
       coalesce(sum(c.n) FILTER (WHERE c.class='REAL_DIFF'),0) AS real_diff,
       coalesce(sum(c.n) FILTER (WHERE c.class='SKRIVEMAADE'),0) AS skrivemaade
  FROM (SELECT k.key AS class, k.value::bigint AS n
          FROM jsonb_each(current_setting('daa.control_result')::jsonb->'counts') pr,
               jsonb_each_text(pr.value) k
         WHERE pr.key IN ('person.birth','person.death')) c \gset m_

-- Gyldige assertion-bindinger (alle kilder): assertion_binding_current for alle promotions på én gang. Hashen beregnes bagefter
-- over den samme liste, så der kun er én kopi af reglen.
WITH m_b AS (
SELECT p.id AS promotion_id, p.target_id AS assertion_id, q.interpretation_key, q.source_id, cur.method
  FROM private.interpretation_promotion p
  JOIN private.interpretation q ON q.id=p.interpretation_id
  JOIN private.interpretation_current cur
    ON cur.interpretation_key=q.interpretation_key AND cur.id=p.interpretation_id AND cur.status='accepted'
  JOIN private.interpretation_promotion_rule r ON r.rule_key=p.rule_key AND r.rule_version=p.rule_version
  JOIN public.assertion a ON a.id=p.target_id AND a.target_type='fact'
  JOIN public.fact f ON f.id=a.target_id
  LEFT JOIN private.source_persona_identity i
    ON i.source_persona_id=cur.source_persona_id AND i.decision_status='accepted'
 WHERE p.target_type='assertion'
   AND f.faktatype=r.expected_fact_type
   AND (NOT r.requires_persona_identity
        OR (i.canonical_person_id IS NOT NULL AND f.subjekt_type='person' AND f.subjekt_id=i.canonical_person_id))
   AND private.binding_value_matches(r.value_kind,cur.value,a.vaerdi_tekst,a.date_raw)
)
SELECT count(*) AS alle,
       coalesce(string_agg(b.assertion_id::text||':'||b.interpretation_key::text,E'\n'
                           ORDER BY b.assertion_id,b.interpretation_key),'') AS liste,
       count(*) FILTER (WHERE b.source_id=:source_id
                          AND b.method='deterministisk-normalisering:dato-markoer-v2') AS bundet
  FROM m_b b \gset m_
SELECT encode(sha256(convert_to(:'m_liste','UTF8')),'hex') AS hash \gset m_

SELECT (SELECT count(*) FROM private.interpretation q
         WHERE q.source_id=:source_id AND q.method='deterministisk-normalisering:dato-markoer-v2') AS versioner,
       (SELECT count(*) FROM private.interpretation_current ic
         WHERE ic.source_id=:source_id AND ic.method='deterministisk-normalisering:dato-markoer-v2'
           AND ic.status='accepted') AS accepteret \gset m_

SELECT count(*) FILTER (WHERE f.faktatype='fødsel') AS foedsel,
       count(*) FILTER (WHERE f.faktatype='død') AS doed
  FROM public.public_person_facts(ARRAY(SELECT id FROM public.person)) f
 WHERE f.source_id=:source_id AND f.record_label IS NOT NULL \gset m_

SELECT CASE WHEN NOT :'ddl'::boolean THEN 'foer'
            WHEN :m_versioner=0 THEN 'ddl'
            WHEN :m_accepteret=0 THEN 'n'
            ELSE 'k' END AS tilstand \gset m_

SELECT format('DATO_MAAL tilstand=%s versioner_v2=%s match=%s real_diff=%s skrivemaade=%s accepteret_v2=%s bundet_v2=%s '
              'post_foedsel=%s post_doed=%s alle_bindinger=%s alle_bindinger_hash=%s',
              :'m_tilstand',:'m_versioner',:'m_match',:'m_real_diff',:'m_skrivemaade',:'m_accepteret',:'m_bundet',
              :'m_foedsel',:'m_doed',:'m_alle',:'m_hash');
\if :{?liste} \else \set liste '' \endif
SELECT :'liste'='1' AS har_liste \gset
\if :har_liste
SELECT :'m_liste' WHERE :'m_liste'<>'';
\endif
ROLLBACK;
