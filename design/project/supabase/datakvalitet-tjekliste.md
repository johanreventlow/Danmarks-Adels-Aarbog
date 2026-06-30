# Datakvalitets-tjekliste — udtræk til Adelsårbog-følgesvenden

Kørbare checks til validering af et nyt udtræk i Supabase (SQL Editor).
Bygget på den evidens-baserede model: `person`, `family`, `family_member` (roller
`partner`/`barn`), `relation`, `person_external_id`, `source`, `narrative`, `media`,
`coat_of_arms`. **Et check der returnerer rækker = noget at se nærmere på.**

Alle tre POC-fejl vi fandt undervejs er dækket: ① barn i flere familier (gav flettede
forældre), ② børn lagt under forkert/kun ét ægteskab (Conrad-fejlen), ③ paginering (hører
til klienten, ikke data).

---

## 1 · Slægtskabs-integritet (vigtigst)

**1a. Barn registreret i FLERE familier** — genealogisk umuligt; gav i POC'en flettede forældre.
```sql
select person_id, count(*) as antal_familier
from family_member
where rolle = 'barn'
group by person_id
having count(*) > 1;
```

**1b. Familie uden nogen forælder (partner)** — børn der hænger i luften.
```sql
select f.id as family_id
from family f
where not exists (
  select 1 from family_member m where m.family_id = f.id and m.rolle = 'partner'
);
```

**1c. Person der hverken er barn eller partner noget sted** — løsrevet fra træet.
```sql
select p.id, p.visning_navn
from person p
where not exists (select 1 from family_member m where m.person_id = p.id);
```

**1d. Familie med kun ÉN partner** — mulig manglende ægtefælle (gennemse).
```sql
select m.family_id, count(*) as antal_partnere
from family_member m
where m.rolle = 'partner'
group by m.family_id
having count(*) = 1;
```

**1e. Person der er sin egen ane (cyklus)** — bryder træet. Rekursivt tjek:
```sql
with recursive opad as (
  select fm_barn.person_id as start_id, fm_par.person_id as ane_id, 1 as dybde
  from family_member fm_barn
  join family_member fm_par
    on fm_par.family_id = fm_barn.family_id and fm_par.rolle = 'partner'
  where fm_barn.rolle = 'barn'
  union all
  select o.start_id, fm_par.person_id, o.dybde + 1
  from opad o
  join family_member fm_barn
    on fm_barn.person_id = o.ane_id and fm_barn.rolle = 'barn'
  join family_member fm_par
    on fm_par.family_id = fm_barn.family_id and fm_par.rolle = 'partner'
  where o.dybde < 60
)
select distinct start_id from opad where start_id = ane_id;
```

---

## 2 · Ægteskaber & børnefordeling (Conrad-fejlen)

**2a. Personer med flere ægteskaber + antal børn pr. ægteskab.**
Gennemse manuelt: et ægteskab med `0 børn` *kan* være korrekt (barnløst) eller en fejl,
hvor børnene fejlagtigt ligger under det andet ægteskab.
```sql
select m.person_id, p.visning_navn, m.family_id,
       (select count(*) from family_member c
          where c.family_id = m.family_id and c.rolle = 'barn') as antal_boern
from family_member m
join person p on p.id = m.person_id
where m.rolle = 'partner'
  and m.person_id in (
    select person_id from family_member where rolle = 'partner'
    group by person_id having count(*) > 1
  )
order by m.person_id, m.family_id;
```

**2b. Samme to personer som partnere i flere familier** — dublet-ægteskab.
```sql
select string_agg(person_id::text, ',' order by person_id) as par, count(distinct family_id)
from family_member
where rolle = 'partner'
group by family_id
having count(*) = 2
-- gruppér efter par i et ydre lag hvis nødvendigt
;
```

---

## 3 · Personer

**3a. Person uden navn.**
```sql
select id from person where visning_navn is null or btrim(visning_navn) = '';
```

**3b. Mulige dubletter — samme navn + samme fødsel.**
```sql
select visning_navn, visning_foedt, count(*) as antal, array_agg(id) as ids
from person
group by visning_navn, visning_foedt
having count(*) > 1
order by antal desc;
```

**3c. Barn født før en forælder (leveår-sanity).** Kræver at årstal kan parses; gennemse output.
```sql
select c.person_id as barn, c.visning_foedt as barn_foedt,
       pa.person_id as foraelder, pa.visning_foedt as for_foedt
from (
  select fm.person_id, fm.family_id, p.visning_foedt
  from family_member fm join person p on p.id = fm.person_id
  where fm.rolle = 'barn'
) c
join (
  select fm.person_id, fm.family_id, p.visning_foedt
  from family_member fm join person p on p.id = fm.person_id
  where fm.rolle = 'partner'
) pa on pa.family_id = c.family_id
where (substring(c.visning_foedt from '\d{3,4}'))::int
    < (substring(pa.visning_foedt from '\d{3,4}'))::int;
```

---

## 4 · Linjer & bogreference

**4a. Person uden `person_external_id`** — ingen linje/bogreference (vises ikke i linje-filteret).
```sql
select p.id, p.visning_navn
from person p
where not exists (select 1 from person_external_id e where e.person_id = p.id);
```

**4b. Linje-fordeling** — bør være I–V uden tomme/ukendte værdier.
```sql
select linje, count(*) from person_external_id group by linje order by linje;
```

**4c. Stamfader pr. linje** (laveste `nr`) — bekræft at hver linje har en rod.
```sql
select distinct on (linje) linje, nr, person_id
from person_external_id
where linje is not null
order by linje, nr asc;
```

---

## 5 · Kilder, medier & relationer

**5a. Kilde-henvisning der peger på en ikke-eksisterende `source`.**
```sql
select e.* from person_external_id e
left join source s on s.id = e.source_id
where e.source_id is not null and s.id is null;
```

**5b. Medie uden tilknytning til en person** (når medier kobles via `relation`):
```sql
select m.id, m.titel
from media m
where not exists (
  select 1 from relation r
  where r.objekt_type = 'media' and r.objekt_id = m.id
);
```

**5c. Relation der peger på et ikke-eksisterende gods/organisation.**
```sql
select r.* from relation r
left join estate e on r.objekt_type = 'estate' and e.id = r.objekt_id
where r.objekt_type = 'estate' and e.id is null;
```

---

## 6 · Hurtigt overblik (nøgletal)

Kør for at se at udtrækket er komplet og ligner forventningen:
```sql
select
  (select count(*) from person)                                   as personer,
  (select count(*) from family)                                   as familier,
  (select count(*) from family_member where rolle='barn')         as barn_kanter,
  (select count(*) from family_member where rolle='partner')      as partner_kanter,
  (select count(distinct linje) from person_external_id)          as linjer,
  (select count(*) from relation where objekt_type='estate')      as gods_relationer,
  (select count(*) from media)                                    as medier,
  (select count(*) from coat_of_arms)                             as vaaben;
```

---

### Prioritering
1. **Check 1a + 1b + 1e** — bryder selve træet. Skal være tomme.
2. **Check 2a** — gennemgå alle flergifte personer (Conrad-typen) manuelt.
3. **Check 3b + 4a** — dubletter og manglende linje-tilknytning.
4. Resten er finpudsning før udgivelse.
