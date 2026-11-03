-- Fælles psql-snippet (\ir) til linjeskift-v1: den forventede tilstand pr. påstand, som red_ret_paastand sammenligner
-- i p_forventet, og en sha256 over hele listen. Bruges af linjeskift_kandidater.sql (GO-pakken) og af ceremoni 3's
-- runner (drift-vagt i skrive-transaktionen), så udtrykket kun står ét sted.
-- Ind:  GUC daa.linjeskift_ider = påstands-id'er, kommasepareret (tom = ingen).
-- Ud (transaktionslokale GUC'er; intet skrives ud):
--   daa.linjeskift_forventet         jsonb-array [{"assertion_id":<id>,"forventet":{…}}, …] sorteret på assertion_id
--                                    som bigint. forventet har præcis red_ret_paastand's seks nøgler: fact_id,
--                                    faktatype, vaerdi_tekst, date_raw, valgt_assertion_id (konklusionens; null uden),
--                                    citation_sources (distinkte citerende source_id'er, stigende, som jsonb-array).
--   daa.linjeskift_forventet_sha256  sha256 (hex) over arrayets jsonb-tekst (UTF-8). jsonb's tekstform er deterministisk
--                                    (nøgleorden fastlagt af jsonb), og rækkefølgen er numerisk: uafhængig af collation.
-- Et id uden påstand på et personfaktum giver ingen række (listen og sha'en ændres, så vagten slår til).
-- Indeholder værdier (date_raw); de forlader kun basen, hvis kalderen selv skriver GUC'en ud. Det gør ingen af de to.
SELECT set_config('daa.linjeskift_forventet',x.liste::text,true),
       set_config('daa.linjeskift_forventet_sha256',encode(sha256(convert_to(x.liste::text,'UTF8')),'hex'),true)
  FROM (
    SELECT coalesce(jsonb_agg(jsonb_build_object(
             'assertion_id',a.id,
             'forventet',jsonb_build_object(
               'fact_id',f.id,
               'faktatype',f.faktatype,
               'vaerdi_tekst',a.vaerdi_tekst,
               'date_raw',a.date_raw,
               'valgt_assertion_id',c.valgt_assertion_id,
               'citation_sources',(SELECT coalesce(jsonb_agg(s.source_id ORDER BY s.source_id),'[]'::jsonb)
                                     FROM (SELECT DISTINCT ci.source_id FROM public.citation ci
                                            WHERE ci.assertion_id=a.id) s)))
             ORDER BY a.id),'[]'::jsonb) AS liste
      FROM public.assertion a
      JOIN public.fact f ON f.id=a.target_id AND a.target_type='fact' AND f.subjekt_type='person'
      LEFT JOIN public.conclusion c ON c.target_type='fact' AND c.target_id=f.id
     WHERE a.id=ANY(string_to_array(nullif(current_setting('daa.linjeskift_ider'),''),',')::bigint[])
  ) x \g /dev/null
