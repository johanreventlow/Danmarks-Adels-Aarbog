-- =====================================================================
--  RLS-LAG · offentlig (anon) læseadgang med GDPR-filtrering
--
--  Erstatter den midlertidige permissive dev-RLS (web/dev-rls.sql, "USING true").
--  Håndhæver invariant #8 (CLAUDE.md §3): person.levende styrer synlighed —
--  AFDØDE relativt åbne, LEVENDE kræver samtykke/login. person.privat er manuel
--  skjulning oven på. Personbundne rækker (slægtskab, narrativ, fakta) gates på
--  den refererede persons synlighed.
--
--  ⚠️  IKKE ANVENDT ENDNU. Dette er et review-artefakt. FØR det køres mod den
--      LEVENDE Supabase-base:
--        1. Kør mod en KOPI/branch-base og verificér at app-skiven stadig loader
--           (den vil herefter kun se afdøde/ikke-private personer via anon-nøglen —
--           levende presens-medlemmer bliver USYNLIGE for anon, hvilket er hensigten).
--        2. Bekræft PostgREST-pagineringen stadig henter forventet antal rækker.
--        3. Et fremtidigt 'authenticated'-lag (medlem/forsker via profiles +
--           samtykke) tilføjer adgang til levende — se §"FREMTID" nederst.
--      Kør i Supabase: SQL Editor -> indsæt -> Run. Teardown nederst.
-- =====================================================================

-- ---------- HJÆLPEFUNKTION ----------
-- SECURITY DEFINER: kører med ejer-rettigheder og omgår RLS internt, så den kan
-- afgøre en persons synlighed uden at trigge person-politikken rekursivt.
create or replace function public.person_offentlig(pid bigint)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  -- FAIL-CLOSED på levende: 'levende = false' udelukker også NULL (NULL = false → NULL → ej true),
  -- så en person hvor levende aldrig blev sat ikke lækker. privat: NULL behandles som ikke-privat.
  select exists (
    select 1 from public.person p
    where p.id = pid and p.levende = false and coalesce(p.privat, false) = false
  );
$$;

revoke all on function public.person_offentlig(bigint) from public;
grant execute on function public.person_offentlig(bigint) to anon, authenticated;

do $$
declare t text;
begin
  -- =========================================================
  -- 1) REFERENCE-TABELLER uden person-PII → offentlige (USING true).
  --    (Slægtskabs-PII gates via person-tabellerne nedenfor; selve familie-/
  --     kilde-/sted-rækkerne er ikke personfølsomme.)
  -- =========================================================
  foreach t in array array[
    'vocab','repository','source','place','organisation','estate',
    'coat_of_arms','lineage','family','historical_event'
  ] loop
    execute format('grant select on table public.%I to anon;', t);
    execute format('alter table public.%I enable row level security;', t);
    execute format('drop policy if exists anon_read on public.%I;', t);
    execute format('create policy anon_read on public.%I for select to anon using (true);', t);
  end loop;
end $$;

-- 'media' er BEVIDST udeladt af den offentlige liste: den kan holde billeder af LEVENDE
-- personer, men har ingen levende/privat-kolonne (linkes via relation 'afbildet' → person).
-- RLS aktiveres uden anon-politik (deny-all) indtil afbildet-gating er skrevet. Tabellen er
-- tom nu, så app'en påvirkes ikke (media-hentning returnerer 0 rækker = nuværende tilstand).
alter table public.media enable row level security;
drop policy if exists anon_read on public.media;
-- TODO: create policy anon_read on public.media for select to anon
--   using (exists (select 1 from public.relation r
--                  where r.objekt_type='media' and r.objekt_id=media.id and r.rolle='afbildet'
--                        and public.person_offentlig(r.subjekt_id)));

-- =========================================================
-- 2) PERSON: kun afdøde, ikke-private.
-- =========================================================
grant select on table public.person to anon;
alter table public.person enable row level security;
drop policy if exists anon_read on public.person;
create policy anon_read on public.person for select to anon
  using (levende = false and coalesce(privat, false) = false);  -- fail-closed: NULL levende skjules

-- =========================================================
-- 3) PERSONBUNDNE TABELLER: synlige kun hvis den refererede person er offentlig.
-- =========================================================
grant select on table public.person_external_id to anon;
alter table public.person_external_id enable row level security;
drop policy if exists anon_read on public.person_external_id;
create policy anon_read on public.person_external_id for select to anon
  using (public.person_offentlig(person_id));

grant select on table public.family_member to anon;
alter table public.family_member enable row level security;
drop policy if exists anon_read on public.family_member;
create policy anon_read on public.family_member for select to anon
  using (public.person_offentlig(person_id));

-- fact: facta om ikke-personer (sted/gods/våben) er offentlige; person-fakta gates.
grant select on table public.fact to anon;
alter table public.fact enable row level security;
drop policy if exists anon_read on public.fact;
create policy anon_read on public.fact for select to anon
  using (subjekt_type <> 'person' or public.person_offentlig(subjekt_id));

-- relation: gates på BÅDE subjekt og objekt når de er personer.
grant select on table public.relation to anon;
alter table public.relation enable row level security;
drop policy if exists anon_read on public.relation;
create policy anon_read on public.relation for select to anon
  using (
    (subjekt_type <> 'person' or public.person_offentlig(subjekt_id))
    and (objekt_type <> 'person' or public.person_offentlig(objekt_id))
  );

-- narrative: ikke-privat OG (ikke-person ELLER person offentlig).
grant select on table public.narrative to anon;
alter table public.narrative enable row level security;
drop policy if exists anon_read on public.narrative;
create policy anon_read on public.narrative for select to anon
  using (
    coalesce(privat, false) = false
    and (subjekt_type <> 'person' or public.person_offentlig(subjekt_id))
  );

-- note: ikke-privat OG (ikke-person ELLER person offentlig).
grant select on table public.note to anon;
alter table public.note enable row level security;
drop policy if exists anon_read on public.note;
create policy anon_read on public.note for select to anon
  using (
    coalesce(privat, false) = false
    and (target_type <> 'person' or public.person_offentlig(target_id))
  );

-- =========================================================
-- 4) EVIDENS-TABELLER (assertion/conclusion/citation): gates på deres target
--    (fact/relation), som igen gates på person ovenfor. RLS på fact/relation
--    filtrerer EXISTS-subquery'en, så en påstand kun er synlig hvis dens
--    underliggende faktum/relation er synligt.
-- =========================================================
grant select on table public.assertion to anon;
alter table public.assertion enable row level security;
drop policy if exists anon_read on public.assertion;
create policy anon_read on public.assertion for select to anon
  using (
    (target_type = 'fact'     and exists (select 1 from public.fact f     where f.id = target_id))
    or (target_type = 'relation' and exists (select 1 from public.relation r where r.id = target_id))
  );

grant select on table public.conclusion to anon;
alter table public.conclusion enable row level security;
drop policy if exists anon_read on public.conclusion;
create policy anon_read on public.conclusion for select to anon
  using (
    (target_type = 'fact'     and exists (select 1 from public.fact f     where f.id = target_id))
    or (target_type = 'relation' and exists (select 1 from public.relation r where r.id = target_id))
  );

grant select on table public.citation to anon;
alter table public.citation enable row level security;
drop policy if exists anon_read on public.citation;
create policy anon_read on public.citation for select to anon
  using (exists (select 1 from public.assertion a where a.id = assertion_id));

-- =====================================================================
--  FREMTID · 'authenticated'-lag (medlem/forsker) — SKITSE, ikke aktiv.
--
--  Når login + profiles.reventlow_person_id er på plads, tilføjes politikker for
--  rollen 'authenticated' der giver bredere adgang (fx levende slægtninge inden
--  for samtykke). Mønster:
--
--    grant select on table public.person to authenticated;
--    create policy member_read on public.person for select to authenticated
--      using (
--        coalesce(privat,false) = false
--        -- afdøde: åbne; levende: kun med samtykke-flag eller egen-relation
--        and (coalesce(levende,false) = false or samtykke_offentlig = true)
--      );
--
--  Forsker-tier (historisk arkiv) vs. medlem-tier (levende netværk) skelnes via
--  en rolle-claim/JWT eller en profiles.tier-kolonne. Designes når auth bygges.
-- =====================================================================

-- =====================================================================
--  TEARDOWN (fjern RLS-laget igen — fald tilbage til dev-adgang eller lukket):
--
--  do $$
--  declare t text;
--  begin
--    foreach t in array array[
--      'vocab','repository','source','place','organisation','estate','coat_of_arms',
--      'lineage','family','historical_event','media','person','person_external_id',
--      'family_member','fact','relation','narrative','note','assertion','conclusion','citation'
--    ] loop
--      execute format('drop policy if exists anon_read on public.%I;', t);
--      -- valgfrit: execute format('revoke select on table public.%I from anon;', t);
--    end loop;
--  end $$;
--  drop function if exists public.person_offentlig(bigint);
-- =====================================================================
