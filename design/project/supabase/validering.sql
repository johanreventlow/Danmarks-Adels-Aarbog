-- =====================================================================
--  validering.sql — samlet datakvalitets-rapport for Adelsårbog-udtræk
--  Kør HELE filen i Supabase SQL Editor efter hvert nyt udtræk.
--  Den øverste forespørgsel giver ÉN rapport-tabel (tjek · alvor · antal).
--  Antal > 0 på en KRITISK linje = skal rettes før udgivelse.
--  Diagnose-forespørgslerne nederst viser de konkrete rækker.
-- =====================================================================

-- ---------- SAMLET RAPPORT --------------------------------------------
with rapport as (
  select '1a · barn i flere familier'            as tjek, 'KRITISK'  as alvor,
    (select count(*) from (
       select person_id from family_member where rolle='barn'
       group by person_id having count(*) > 1) x)                     as antal
  union all
  select '1b · familie uden forælder', 'KRITISK',
    (select count(*) from family f
     where not exists (select 1 from family_member m
                       where m.family_id=f.id and m.rolle='partner'))
  union all
  select '1c · person uden for træet (hverken barn/partner)', 'ADVARSEL',
    (select count(*) from person p
     where not exists (select 1 from family_member m where m.person_id=p.id))
  union all
  select '1d · familie med kun én partner', 'GENNEMSE',
    (select count(*) from (
       select family_id from family_member where rolle='partner'
       group by family_id having count(*) = 1) x)
  union all
  select '2a · flergifte personer (gennemse børnefordeling)', 'GENNEMSE',
    (select count(*) from (
       select person_id from family_member where rolle='partner'
       group by person_id having count(*) > 1) x)
  union all
  select '3a · person uden navn', 'KRITISK',
    (select count(*) from person where visning_navn is null or btrim(visning_navn)='')
  union all
  select '3b · mulige dubletter (navn + fødsel)', 'GENNEMSE',
    (select count(*) from (
       select 1 from person
       group by visning_navn, visning_foedt having count(*) > 1) x)
  union all
  select '4a · person uden linje/bogreference', 'ADVARSEL',
    (select count(*) from person p
     where not exists (select 1 from person_external_id e where e.person_id=p.id))
  union all
  select '5a · bogreference peger på manglende source', 'ADVARSEL',
    (select count(*) from person_external_id e
     left join source s on s.id=e.source_id
     where e.source_id is not null and s.id is null)
  union all
  select '5c · relation peger på manglende gods', 'ADVARSEL',
    (select count(*) from relation r
     left join estate e on r.objekt_type='estate' and e.id=r.objekt_id
     where r.objekt_type='estate' and e.id is null)
)
select tjek, alvor, antal,
       case when antal = 0 then 'OK' else 'SE EFTER' end as status
from rapport
order by case alvor when 'KRITISK' then 1 when 'ADVARSEL' then 2 else 3 end, tjek;


-- =====================================================================
--  DIAGNOSE — kør den relevante blok når rapporten viser antal > 0
-- =====================================================================

-- 1a · hvilke børn ligger i flere familier?
-- select person_id, count(*) from family_member where rolle='barn'
-- group by person_id having count(*) > 1;

-- 1b · hvilke familier mangler forælder?
-- select f.id from family f where not exists
--   (select 1 from family_member m where m.family_id=f.id and m.rolle='partner');

-- 2a · flergifte personer med antal børn pr. ægteskab (Conrad-typen)
-- select m.person_id, p.visning_navn, m.family_id,
--   (select count(*) from family_member c
--      where c.family_id=m.family_id and c.rolle='barn') as antal_boern
-- from family_member m join person p on p.id=m.person_id
-- where m.rolle='partner' and m.person_id in (
--   select person_id from family_member where rolle='partner'
--   group by person_id having count(*) > 1)
-- order by m.person_id, m.family_id;

-- 1e · cyklus (person der er sin egen ane) — tungere, kør på kopi ved stor base
-- with recursive opad as (
--   select b.person_id as start_id, par.person_id as ane_id, 1 as dybde
--   from family_member b
--   join family_member par on par.family_id=b.family_id and par.rolle='partner'
--   where b.rolle='barn'
--   union all
--   select o.start_id, par.person_id, o.dybde+1
--   from opad o
--   join family_member b on b.person_id=o.ane_id and b.rolle='barn'
--   join family_member par on par.family_id=b.family_id and par.rolle='partner'
--   where o.dybde < 60
-- )
-- select distinct start_id from opad where start_id = ane_id;

-- 3b · mulige dubletter
-- select visning_navn, visning_foedt, count(*), array_agg(id)
-- from person group by visning_navn, visning_foedt
-- having count(*) > 1 order by 3 desc;

-- 6 · nøgletal
-- select
--   (select count(*) from person) as personer,
--   (select count(*) from family) as familier,
--   (select count(*) from family_member where rolle='barn') as barn_kanter,
--   (select count(*) from family_member where rolle='partner') as partner_kanter,
--   (select count(distinct linje) from person_external_id) as linjer,
--   (select count(*) from relation where objekt_type='estate') as gods_relationer,
--   (select count(*) from media) as medier,
--   (select count(*) from coat_of_arms) as vaaben;
