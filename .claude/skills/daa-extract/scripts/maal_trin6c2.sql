-- Læse-kun måling til trin 6c-2's ceremonier (runbook): kun antal, id'er og hashes, ingen navne, værdier eller tekst.
-- Brug: psql -X -At -v ON_ERROR_STOP=1 [-v source_id=3] [-v k1_source_id=1] [-v liste=<fil>] -f maal_trin6c2.sql
--   (\ir finder interpretation_control_classification.sql ved siden af scriptet)
-- Én linje:
--   T6C2_MAAL tilstand=<foer|a|b|c|d> forslag_k=<n> match=<n> skrivemaade=<n> real_diff=<n> accepteret_k=<n>
--     bindinger_k=<n> rettelser=<n> unresolved_fra_kort=<n> k1_bindinger_hash=<sha256>
-- Tilstanden afgøres af fakta i basen, ikke af flag; senere tilstand vinder (d før c før b):
--   foer  public.public_person_facts nævner ikke private.binding_value_matches, eller funktionen findes ikke
--         (6c-2a, vej B, ikke kørt)
--   a     vej B på plads; rettelsesvejen mangler (public.red_ret_paastand, public.red_normaliser_forslag eller
--         tabellen public.paastand_korrektion findes ikke: 6c-2b ikke kørt)
--   b     6c-2b's writere findes. Kort 122 (identitet → unresolved) kan ikke genkendes på navn; den tælles i
--         unresolved_fra_kort og indgår ikke i tilstanden
--   c     en version for kilden med method 'deterministisk-normalisering:dato-markoer-v1' findes (§4.3 kørt)
--   d     anvendt: en aktuel version for kilden med et prædikat, der har en aktiv assertion-regel, er accepted,
--         rejected eller unresolved; eller en assertion-promotion fra kildens fortolkninger findes; eller en
--         levende bogen_har_ret-rettelse på kildens forslag findes. En linjeskift-v1-rettelse (ceremoni 3) giver
--         ikke d. Prædikatfilteret holder kildens øvrige (relations-)fortolkninger ude af tilstanden.
-- Tallene (kildens id fra -v source_id, standard 3; aldrig fast i koden):
--   forslag_k      kildens aktuelle proposed versioner med aktiv assertion-regel = klassifikationens poster
--                  (interpretation_control_classification.sql med daa.control_src = kilden). Aktuelle versioner,
--                  ikke version 1: en §4.3-version erstatter sin version 1 i tallet, så forslag_k er uændret i c
--   match          MATCH + MATCH_SINGLETON (alle 1939-regler er bulk_eligible, så MATCH_SINGLETON er 0 i prod)
--   skrivemaade    SKRIVEMAADE
--   real_diff      REAL_DIFF
--   accepteret_k   kildens aktuelle accepted versioner med aktiv assertion-regel
--   bindinger_k    kildens gældende bindinger (alle måltyper, gyldighed som nedenfor)
--   rettelser      levende rettelser (paastand_korrektion, begge grunde) på forslag fra kilden; en rettelse er død,
--                  når dens change_set er fortrudt (samme prædikat som red_paastand_historik.fortrudt); 0 før 6c-2b
--   unresolved_fra_kort  kildens personas med identitet unresolved og evidence->>'basis'='human_sheet'
--   k1_bindinger_hash    sha256 over kilde k1_source_id's (standard 1, 2018-20) bindinger som linjer
--                  '<promotion-id>:<true|false>' (gyldighed), sorteret på promotion-id som uuid (byteorden, uafhængig
--                  af collation: prod er ICU, lokale baser libc), forbundet med linjeskift; skal være uændret hele vejen
-- Gyldighed som private.text_revision_binding_set: assertion = private.assertion_binding_current; family = aktuel
-- version accepteret og relation_binding_state_sha256 lig den gemte state_sha256; andre måltyper = false.
-- -v liste=<fil>: den nøglede liste over ALLE bindinger (alle kilder) skrives til filen som linjer
--   '<promotion-id>|<kilde>|<t|f>', sorteret som hashen, så en ændret hash kan diffes pr. binding (spec §7).
--   Stien gives uden mellemrum (psql's \o tager variablen uden citationstegn).
-- Gate (efter controllerens afgørelse): findes en påstand med mere end én gældende assertion-binding (alle kilder),
-- stopper målingen med MAAL_FLERE_BINDINGER (kun antallet), før linjen eller listen skrives. Validatoren har under
-- REPEATABLE READ et dokumenteret hul; denne efterkontrol dækker det.
\set QUIET on
\set ON_ERROR_STOP on
\pset format unaligned
\pset tuples_only on
\if :{?source_id} \else \set source_id 3 \endif
\if :{?k1_source_id} \else \set k1_source_id 1 \endif
BEGIN READ ONLY;
SELECT to_regprocedure('private.binding_value_matches(text,jsonb,text,text)') IS NOT NULL
       AND coalesce((SELECT bool_or(position('binding_value_matches' IN p.prosrc)>0)
                       FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                      WHERE n.nspname='public' AND p.proname='public_person_facts'),false) AS vejb,
       to_regprocedure('public.red_ret_paastand(bigint,jsonb,text,uuid,jsonb)') IS NOT NULL
       AND to_regprocedure('public.red_normaliser_forslag(uuid,integer,text)') IS NOT NULL
       AND to_regclass('public.paastand_korrektion') IS NOT NULL AS writere \gset

-- Bindingerne med gyldighed: tal, gate, hash og (valgfrit) listen fra samme mængde.
WITH b AS (
  SELECT p.id, q.source_id, p.target_type, p.target_id,
         (CASE p.target_type
            WHEN 'assertion' THEN private.assertion_binding_current(p.id)
            WHEN 'family' THEN cur.id=p.interpretation_id AND cur.status='accepted'
                               AND private.relation_binding_state_sha256(p.interpretation_id)=p.evidence->>'state_sha256'
            ELSE false
          END) IS TRUE AS gyldig
    FROM private.interpretation_promotion p
    JOIN private.interpretation q ON q.id=p.interpretation_id
    JOIN private.interpretation_current cur ON cur.interpretation_key=q.interpretation_key
)
SELECT (SELECT count(*) FROM (SELECT 1 FROM b WHERE b.target_type='assertion' AND b.gyldig
                               GROUP BY b.target_id HAVING count(*)>1) x) AS flere,
       (SELECT count(*) FROM b WHERE b.source_id=:source_id AND b.gyldig) AS bindinger,
       (SELECT EXISTS (SELECT 1 FROM b WHERE b.source_id=:source_id AND b.target_type='assertion')) AS har_promotion,
       encode(sha256(convert_to(coalesce((SELECT string_agg(b.id::text||':'||b.gyldig::text,E'\n' ORDER BY b.id)
                                            FROM b WHERE b.source_id=:k1_source_id),''),'UTF8')),'hex') AS k1_hash,
       coalesce((SELECT string_agg(b.id::text||'|'||b.source_id::text||'|'||CASE WHEN b.gyldig THEN 't' ELSE 'f' END,
                                   E'\n' ORDER BY b.id) FROM b),'') AS liste \gset m_

SELECT set_config('daa.t6c2_flere',:'m_flere',true) \g /dev/null
DO $gate$
BEGIN
  IF current_setting('daa.t6c2_flere')::bigint>0 THEN
    RAISE EXCEPTION 'MAAL_FLERE_BINDINGER: % påstande har mere end én gældende binding',
      current_setting('daa.t6c2_flere');
  END IF;
END $gate$;

-- Klassifikationen med kildescope; dens JSON (med id'er) skrives ikke ud.
SELECT set_config('daa.control_src',:'source_id',true) \g /dev/null
\o /dev/null
\ir interpretation_control_classification.sql
\o
SELECT coalesce(sum(c.n),0) AS forslag,
       coalesce(sum(c.n) FILTER (WHERE c.class IN ('MATCH','MATCH_SINGLETON')),0) AS match,
       coalesce(sum(c.n) FILTER (WHERE c.class='SKRIVEMAADE'),0) AS skrivemaade,
       coalesce(sum(c.n) FILTER (WHERE c.class='REAL_DIFF'),0) AS real_diff
  FROM (SELECT k.key AS class, k.value::bigint AS n
          FROM jsonb_each(current_setting('daa.control_result')::jsonb->'counts') pr,
               jsonb_each_text(pr.value) k) c \gset m_

SELECT count(*) FILTER (WHERE ic.status='accepted') AS accepteret,
       count(*) FILTER (WHERE ic.status IN ('accepted','rejected','unresolved')) AS afgjort
  FROM private.interpretation_current ic
 WHERE ic.source_id=:source_id
   AND EXISTS (SELECT 1 FROM private.interpretation_promotion_rule_current r
                WHERE r.predicate=ic.predicate AND r.interpretation_kind=ic.interpretation_kind
                  AND r.target_type='assertion' AND r.status='active') \gset m_

SELECT count(*) AS unresolved
  FROM private.source_persona sp
  JOIN private.source_persona_identity i ON i.source_persona_id=sp.id
 WHERE sp.source_id=:source_id AND i.decision_status='unresolved' AND i.evidence->>'basis'='human_sheet' \gset m_

\if :writere
SELECT count(*) AS rettelser,
       count(*) FILTER (WHERE k.grund='bogen_har_ret') AS bogen
  FROM public.paastand_korrektion k
  JOIN private.interpretation q ON q.id=k.interpretation_id
 WHERE q.source_id=:source_id
   AND NOT EXISTS (SELECT 1 FROM public.change_set rv WHERE rv.reverterer_id=k.change_set_id) \gset m_
\else
\set m_rettelser 0
\set m_bogen 0
\endif

SELECT CASE WHEN NOT :'vejb'::boolean THEN 'foer'
            WHEN NOT :'writere'::boolean THEN 'a'
            WHEN :m_afgjort>0 OR :'m_har_promotion'::boolean OR :m_bogen>0 THEN 'd'
            WHEN EXISTS (SELECT 1 FROM private.interpretation q
                          WHERE q.source_id=:source_id
                            AND q.method='deterministisk-normalisering:dato-markoer-v1') THEN 'c'
            ELSE 'b' END AS tilstand \gset m_

\if :{?liste}
\o :liste
SELECT :'m_liste' WHERE :'m_liste'<>'';
\o
\endif

SELECT format('T6C2_MAAL tilstand=%s forslag_k=%s match=%s skrivemaade=%s real_diff=%s accepteret_k=%s bindinger_k=%s '
              'rettelser=%s unresolved_fra_kort=%s k1_bindinger_hash=%s',
              :'m_tilstand',:'m_forslag',:'m_match',:'m_skrivemaade',:'m_real_diff',:'m_accepteret',
              :'m_bindinger',:'m_rettelser',:'m_unresolved',:'m_k1_hash');
ROLLBACK;
