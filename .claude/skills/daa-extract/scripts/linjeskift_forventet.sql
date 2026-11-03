-- Fælles psql-snippet (\ir) til linjeskift-v1: pr. par (påstand, forslag) den forventede tilstand, som red_ret_paastand
-- sammenligner i p_forventet, en sha256 over hele listen, og datogrænserne, som rettelsen ikke må røre. Bruges af
-- linjeskift_kandidater.sql (GO-pakken) og af ceremoni 3's runner (drift-vagt før og grænsemåling efter rettelserne),
-- så udtrykkene kun står ét sted.
-- Ind:  GUC daa.linjeskift_par = '<assertion_id>:<interpretation_id>' kommasepareret (som
--       daa.linjeskift_kandidat_par fra linjeskift_kandidat_par.sql); tom = ingen.
-- Ud (transaktionslokale GUC'er; intet skrives ud):
--   daa.linjeskift_forventet          jsonb-array [{"assertion_id":…,"interpretation_id":…,"forventet":{…}}, …],
--                                     sorteret på assertion_id som bigint. "forventet" har præcis red_ret_paastand's
--                                     seks nøgler og gives uændret som p_forventet: fact_id, faktatype, vaerdi_tekst,
--                                     date_raw, valgt_assertion_id (konklusionens; null uden), citation_sources
--                                     (distinkte citerende source_id'er, stigende, som jsonb-array).
--   daa.linjeskift_forventet_sha256   sha256 (hex) over arrayets jsonb-tekst (UTF-8): binder parret og de seks nøgler.
--   daa.linjeskift_graenser_udfyldt   antal påstande med date_min eller date_max udfyldt.
--   daa.linjeskift_graenser_sha256    sha256 over jsonb-arrayet [[assertion_id,date_min,date_max,date_qualifier], …]
--                                     sorteret på assertion_id; datoer i jsonb's ISO-form (uafhængig af DateStyle).
--                                     Skal være ens før og efter rettelserne (spec §4.4 pkt. 4: grænserne røres ikke).
-- jsonb's tekstform er deterministisk (nøgleorden fastlagt af jsonb), og rækkefølgen er numerisk: uafhængig af
-- collation. Et par uden påstand på et personfaktum giver ingen række (listen og sha'en ændres, så vagten slår til).
-- Indeholder værdier (date_raw); de forlader kun basen, hvis kalderen selv skriver GUC'en ud. Det gør ingen af de to.
SELECT set_config('daa.linjeskift_forventet',x.liste::text,true),
       set_config('daa.linjeskift_forventet_sha256',encode(sha256(convert_to(x.liste::text,'UTF8')),'hex'),true),
       set_config('daa.linjeskift_graenser_udfyldt',x.udfyldt::text,true),
       set_config('daa.linjeskift_graenser_sha256',encode(sha256(convert_to(x.graenser::text,'UTF8')),'hex'),true)
  FROM (
    SELECT coalesce(jsonb_agg(jsonb_build_object(
             'assertion_id',a.id,
             'interpretation_id',par.interpretation_id,
             'forventet',jsonb_build_object(
               'fact_id',f.id,
               'faktatype',f.faktatype,
               'vaerdi_tekst',a.vaerdi_tekst,
               'date_raw',a.date_raw,
               'valgt_assertion_id',c.valgt_assertion_id,
               'citation_sources',(SELECT coalesce(jsonb_agg(s.source_id ORDER BY s.source_id),'[]'::jsonb)
                                     FROM (SELECT DISTINCT ci.source_id FROM public.citation ci
                                            WHERE ci.assertion_id=a.id) s)))
             ORDER BY a.id),'[]'::jsonb) AS liste,
           count(*) FILTER (WHERE a.date_min IS NOT NULL OR a.date_max IS NOT NULL) AS udfyldt,
           coalesce(jsonb_agg(jsonb_build_array(a.id,a.date_min,a.date_max,a.date_qualifier) ORDER BY a.id),
                    '[]'::jsonb) AS graenser
      FROM (SELECT split_part(p,':',1)::bigint AS assertion_id, split_part(p,':',2)::uuid AS interpretation_id
              FROM unnest(string_to_array(nullif(current_setting('daa.linjeskift_par'),''),',')) p) par
      JOIN public.assertion a ON a.id=par.assertion_id
      JOIN public.fact f ON f.id=a.target_id AND a.target_type='fact' AND f.subjekt_type='person'
      LEFT JOIN public.conclusion c ON c.target_type='fact' AND c.target_id=f.id
  ) x \g /dev/null
