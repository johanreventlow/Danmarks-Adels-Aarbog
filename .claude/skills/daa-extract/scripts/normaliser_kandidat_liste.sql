-- Fælles psql-snippet (\ir): kildens datoforslag, som normaliseringsreglen (dato-markoer-v1 eller -v2) ændrer (spec 2026-11-02 §4.3). Bruges af
-- normaliser_kandidater.sql (GO-pakken) og af ceremoni 3's runner (i skrive-transaktionen kræves en identisk liste og
-- sha), så afgrænsningen kun står ét sted. Runnerkontrakten står i normaliser_kandidater.sql's header.
-- Kræver 6c-2b (private.normaliser_dato_markoer_v1) og, for v2, private.normaliser_dato_markoer_v2.
-- Afgrænsningen spejler red_normaliser_forslag's porte: aktuel version (interpretation_current) for kilden, status
-- proposed, prædikat person.birth eller person.death (de eneste, RPC'en tager; andre giver
-- NORMALISERING_PRAEDIKAT_UGYLDIG), strengværdi, og reglen ændrer værdien. Værditeksten læses som RPC'en: value #>> '{}'.
-- Ind:  GUC daa.normaliser_kilde = kildens id (fra kalderens -v source_id; aldrig fast i koden).
--       GUC daa.normaliser_regel = 'dato-markoer-v1' | 'dato-markoer-v2' (valgfri; udeladt eller tom = v1, så ældre
--       kald er uændrede; andet giver NORMALISER_REGEL_UKENDT). Snippet'et efterlader den opløste regel i GUC'en.
-- Ud (transaktionslokale GUC'er; intet skrives ud):
--   daa.normaliser_kandidater         '<interpretation_id>:<version>' kommasepareret, stigende på interpretation_id
--                                     (uuid-orden); tom streng uden kandidater.
--   daa.normaliser_kandidater_sha256  sha256 (hex) over daa.normaliser_kandidater som UTF-8 (tom liste: sha256 af '').
--   daa.normaliser_antal              antal kandidater.
--   daa.normaliser_tomme              kandidater, hvis værdi bliver tom efter reglen (RPC'en: NORMALISERING_VAERDI_TOM).
DO $regel$
DECLARE r text := coalesce(nullif(current_setting('daa.normaliser_regel', true), ''), 'dato-markoer-v1');
BEGIN
  IF r NOT IN ('dato-markoer-v1','dato-markoer-v2') THEN
    RAISE EXCEPTION 'NORMALISER_REGEL_UKENDT: %', r;
  END IF;
  PERFORM set_config('daa.normaliser_regel', r, true);
END $regel$;
WITH kandidat AS (
  SELECT ic.id, ic.version, n.v = '' AS tom
    FROM private.interpretation_current ic
   CROSS JOIN LATERAL (SELECT CASE current_setting('daa.normaliser_regel')
                                WHEN 'dato-markoer-v2' THEN private.normaliser_dato_markoer_v2(ic.value #>> '{}', ic.predicate)
                                ELSE private.normaliser_dato_markoer_v1(ic.value #>> '{}')
                              END AS v) n
   WHERE ic.source_id = current_setting('daa.normaliser_kilde')::bigint
     AND ic.status = 'proposed'
     AND ic.predicate IN ('person.birth','person.death')
     AND jsonb_typeof(ic.value) = 'string'
     AND n.v IS DISTINCT FROM ic.value #>> '{}'
), liste AS (
  SELECT coalesce(string_agg(k.id::text||':'||k.version::text, ',' ORDER BY k.id), '') AS l,
         count(*) AS n, count(*) FILTER (WHERE k.tom) AS tomme
    FROM kandidat k
)
SELECT set_config('daa.normaliser_kandidater', l, true),
       set_config('daa.normaliser_kandidater_sha256', encode(sha256(convert_to(l,'UTF8')),'hex'), true),
       set_config('daa.normaliser_antal', n::text, true),
       set_config('daa.normaliser_tomme', tomme::text, true)
  FROM liste \g /dev/null
