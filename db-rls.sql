-- =====================================================================
--  RLS-LAG · offentlig (anon) læseadgang med GDPR-filtrering
--
--  Erstatter den midlertidige permissive dev-RLS (web/dev-rls.sql, "USING true").
--  Håndhæver invariant #8 (CLAUDE.md §3): person.levende styrer synlighed —
--  AFDØDE relativt åbne, LEVENDE kræver samtykke/login. person.privat er manuel
--  skjulning oven på. Personbundne rækker (slægtskab, narrativ, fakta) gates på
--  den refererede persons synlighed.
--
--  ✅  ANVENDT I PROD (anon-tier) siden 2026-06-25 — kørt via work/rls_deploy.R.
--      Verificeret som anon: 893 afdøde synlige, 0 levende lækket, den midlertidige
--      dev_anon_read (USING true) droppet på alle tabeller. Deny-all-RLS på historik-
--      tabellerne kom til med versioneringslaget (2026-06-30). Se docs/changelog.md
--      (2026-06-25 + 2026-06-30) og docs/database-current-state.md for den samlede
--      prod-status. Denne fil forbliver source-of-truth for RLS-definitionen.
--
--  ⚠️  FØR du kører ÆNDRINGER i denne fil mod den LEVENDE base igen:
--        1. Kør mod en KOPI/branch-base (eller lokal prod-kopi) og verificér at app-
--           skiven stadig loader — anon ser kun afdøde/ikke-private; levende presens-
--           medlemmer er USYNLIGE for anon (hensigten). En re-kørsel er skrevet
--           idempotent (drop-if-exists), men verificér mod kopi først.
--        2. Bekræft PostgREST-pagineringen stadig henter forventet antal rækker.
--        3. 'authenticated'-laget (medlem/forsker via profiles + samtykke) er stadig
--           IKKE bygget — kun skitseret i §"FREMTID" nederst. Levende data er indtil
--           da usynlige for alle uden redaktion-rolle.
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

-- media-gating-helpere. SECURITY DEFINER så de ser ALLE afbildet-relationer uden at blive
-- re-filtreret af relation-RLS: et afbildet-link til en LEVENDE person er selv skjult for
-- anon af relation-politikken, så en almindelig EXISTS-subquery i media-politikken ville
-- fail-OPEN (ikke se det skjulte link → vise billedet). Definer-funktionen omgår det.
create or replace function public.media_afbilder_skjult(mid bigint)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  -- True hvis billedet afbilder MINDST ÉN person der ikke er offentlig (levende/privat/ukendt).
  select exists (
    select 1 from public.relation r
    where r.objekt_type = 'media' and r.objekt_id = mid
      and r.subjekt_type = 'person' and r.rolle = 'afbildet'
      and not public.person_offentlig(r.subjekt_id)
  );
$$;

create or replace function public.media_afbilder_privat(mid bigint)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  -- True hvis billedet afbilder MINDST ÉN manuelt privat-markeret person (levende tilladt
  -- for authenticated; kun privat skjules).
  select exists (
    select 1 from public.relation r
    join public.person p on p.id = r.subjekt_id
    where r.objekt_type = 'media' and r.objekt_id = mid
      and r.subjekt_type = 'person' and r.rolle = 'afbildet'
      and coalesce(p.privat, false) = true
  );
$$;

revoke all on function public.media_afbilder_skjult(bigint) from public;
revoke all on function public.media_afbilder_privat(bigint) from public;
grant execute on function public.media_afbilder_skjult(bigint) to anon, authenticated;
grant execute on function public.media_afbilder_privat(bigint) to authenticated;

-- ---------- DROP DEV-LAGET FØRST ----------
-- KRITISK: den midlertidige dev-RLS (web/dev-rls.sql) oprettede politikker
-- 'dev_anon_read' med USING (true). Postgres OR'er permissive politikker for
-- samme rolle+kommando, så hvis disse forbliver, bypasser de hele GDPR-filtret
-- nedenfor (verificeret: anon ser da alle levende). Fjern dem på ALLE tabeller.
do $$
declare r record;
begin
  for r in select schemaname, tablename from pg_policies
           where schemaname='public' and policyname='dev_anon_read'
  loop
    execute format('drop policy if exists dev_anon_read on %I.%I;', r.schemaname, r.tablename);
  end loop;
end $$;

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

-- 'media' har ingen egen levende/privat-kolonne; synligheden afledes af de personer billedet
-- AFBILDER (relation rolle='afbildet' → person), via SECURITY DEFINER-helperne ovenfor.
-- FAIL-CLOSED: et billede er synligt MEDMINDRE det afbilder en ikke-offentlig person.
--   · objekt-fotos uden afbildet-person (segl, gods, våben) → offentlige
--   · portræt af afdød, ikke-privat person → offentligt
--   · ethvert billede der afbilder en levende/privat person → skjult for anon
-- (NOT EXISTS-non-public, ikke EXISTS-public: et gruppebillede med BÅDE en afdød og en
--  levende person skal skjules — ikke vises fordi den afdøde tilfældigvis er offentlig.)
grant select on table public.media to anon, authenticated;
alter table public.media enable row level security;
drop policy if exists anon_read on public.media;
create policy anon_read on public.media for select to anon
  using (not public.media_afbilder_skjult(media.id));
-- authenticated (medlem): levende tilladt, men manuelt privat skjules.
drop policy if exists auth_read on public.media;
create policy auth_read on public.media for select to authenticated
  using (not public.media_afbilder_privat(media.id));
-- redaktion: ser alt (additivt oven på de to ovenfor).
drop policy if exists redaktion_read on public.media;
create policy redaktion_read on public.media for select to authenticated
  using ((select public.current_rolle()) = 'redaktion');

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

-- =========================================================
-- 5) AUTHENTICATED-LAG (medlem/redaktion): logget-ind ser OGSÅ levende.
--    Samtykke-granularitet pr. levende person udskudt (se FREMTID).
-- =========================================================
do $$
declare t text;
begin
  foreach t in array array[
    'person','person_external_id','family_member','fact','relation','narrative','note',
    'assertion','conclusion','citation'
  ] loop
    execute format('grant select on table public.%I to authenticated;', t);
    execute format('drop policy if exists auth_read on public.%I;', t);
  end loop;
end $$;

-- person: alt undtagen manuelt privat.
create policy auth_read on public.person for select to authenticated
  using (coalesce(privat,false) = false);
-- personbundne: synlige hvis personen ikke er privat (levende tilladt for login).
create policy auth_read on public.person_external_id for select to authenticated
  using (exists (select 1 from person p where p.id=person_id and coalesce(p.privat,false)=false));
create policy auth_read on public.family_member for select to authenticated
  using (exists (select 1 from person p where p.id=person_id and coalesce(p.privat,false)=false));
create policy auth_read on public.fact for select to authenticated
  using (subjekt_type <> 'person'
         or exists (select 1 from person p where p.id=subjekt_id and coalesce(p.privat,false)=false));
-- relation: gates på BÅDE person-endpoints (ikke-privat). Cycle 02 H3 — using(true) lækkede
-- private personers relationer (ejerskab/hverv/kanter) til logget-ind medlemmer.
create policy auth_read on public.relation for select to authenticated
  using (
    (subjekt_type <> 'person' or exists (select 1 from person p where p.id=subjekt_id and coalesce(p.privat,false)=false))
    and (objekt_type <> 'person' or exists (select 1 from person p where p.id=objekt_id and coalesce(p.privat,false)=false))
  );
-- narrative/note: eget privat-flag OG (ikke-person ELLER refereret person ikke-privat).
-- Cycle 02 H3 — manglede person-gating (ikke-flagget bio/note om privat person lækkede).
create policy auth_read on public.narrative for select to authenticated
  using (
    coalesce(privat,false)=false
    and (subjekt_type <> 'person' or exists (select 1 from person p where p.id=subjekt_id and coalesce(p.privat,false)=false))
  );
create policy auth_read on public.note for select to authenticated
  using (
    coalesce(privat,false)=false
    and (target_type <> 'person' or exists (select 1 from person p where p.id=target_id and coalesce(p.privat,false)=false))
  );
create policy auth_read on public.assertion for select to authenticated
  using (
    (target_type = 'fact'     and exists (select 1 from public.fact f     where f.id = target_id))
    or (target_type = 'relation' and exists (select 1 from public.relation r where r.id = target_id))
  );
create policy auth_read on public.conclusion for select to authenticated
  using (
    (target_type = 'fact'     and exists (select 1 from public.fact f     where f.id = target_id))
    or (target_type = 'relation' and exists (select 1 from public.relation r where r.id = target_id))
  );
create policy auth_read on public.citation for select to authenticated
  using (exists (select 1 from public.assertion a where a.id = assertion_id));

-- profiles: hver bruger ser kun sin egen række.
grant select on table public.profiles to authenticated;
alter table public.profiles enable row level security;
drop policy if exists self_read on public.profiles;
create policy self_read on public.profiles for select to authenticated using (id = auth.uid());

-- RPC-grants: alle red_*-funktioner kaldbare af authenticated (rolle-tjek er INDE i dem).
do $$
declare fn text;
begin
  for fn in select proname from pg_proc where proname like 'red\_%' escape '\'
  loop execute format('grant execute on function public.%I to authenticated;', fn); end loop;
end $$;
revoke all on function public.current_rolle() from public;   -- hygiejne: ikke kaldbar af anon
grant execute on function public.current_rolle() to authenticated;
-- staging: authenticated læser egne forslag; redaktion læser ALLE (kan tømme køen).
-- Cycle 02 H1 — uden redaktion-read var staging-flowet usynligt for den der skal gennemse det.
grant select on table public.suggestion to authenticated;
alter table public.suggestion enable row level security;
drop policy if exists own_read on public.suggestion;
drop policy if exists redaktion_read_all on public.suggestion;
create policy own_read on public.suggestion for select to authenticated using (forslagsstiller = auth.uid());
create policy redaktion_read_all on public.suggestion for select to authenticated
  using ((select public.current_rolle()) = 'redaktion');  -- (select ...) = én eval pr. statement

-- 5b) REDAKTION-LAG: rolle=redaktion ser OGSÅ private rækker (ellers skjuler auth_read-laget
-- en netop privat-markeret person for redaktøren selv — spec §8b, Codex-review høj).
-- Additiv: hver tabel har nu (anon_read) + (auth_read ikke-privat) + (redaktion_read alt).
do $$
declare t text;
begin
  foreach t in array array['person','person_external_id','family_member','fact',
                           'relation','narrative','note','assertion','conclusion','citation']
  loop
    execute format('drop policy if exists redaktion_read on public.%I;', t);
    execute format(
      'create policy redaktion_read on public.%I for select to authenticated '
      || 'using ((select public.current_rolle()) = ''redaktion'');', t);
  end loop;
end $$;

-- Konflikt-view: læsbar for authenticated (RLS håndhæves af security_invoker på basistabeller).
grant select on public.red_konflikt to authenticated;
grant select on public.red_konflikt to anon;

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
--  drop function if exists public.media_afbilder_skjult(bigint);
--  drop function if exists public.media_afbilder_privat(bigint);
-- =====================================================================


-- =====================================================================
-- 2026-06-30: VERSIONERING + MENTIONS — RLS
-- =====================================================================
-- Historik-tabeller: deny-all for anon/authenticated; al adgang via SECURITY DEFINER-API (B10).
ALTER TABLE change_set   ENABLE ROW LEVEL SECURITY;
ALTER TABLE change_event ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON change_set, change_event FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION hist_for_subjekt(text,bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION hist_events(bigint)            TO authenticated;
GRANT EXECUTE ON FUNCTION red_fortryd_change_set(bigint,boolean) TO authenticated;

-- =====================================================================
-- 2026-07-02: SIKKERHEDSHÆRDNING (review 12) — version_pk_registry (intet RLS,
-- Supabases default-privileges gav anon fuld DML inkl. TRUNCATE — et forgiftet
-- register knækker log_change/fortryd) og _subjekt_synlighed/begin_change_set
-- (rene interne hjælpefunktioner uden egen rolle-gate, PostgREST-kaldbare som
-- hhv. en levende/privat-status-oracle og fri indsættelse i det ellers deny-
-- all'ede change_set). Al legitim adgang sker via SECURITY DEFINER-kæden fra
-- red_*-RPC'erne; ejeren (postgres) bypasser revoke/RLS ved interne kald.
-- OBS: Supabase grantér anon/authenticated EXECUTE DIREKTE (ikke via PUBLIC) via
-- egne ALTER DEFAULT PRIVILEGES — "FROM PUBLIC" alene er dokumenteret utilstrækkeligt
-- i prod (verificeret 2026-07-02: proacl beholdt anon/authenticated efter revoke).
-- Navngiv altid rollerne eksplicit.
-- =====================================================================
ALTER TABLE version_pk_registry ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON version_pk_registry FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION _subjekt_synlighed(text, bigint),
                           begin_change_set(text, text, text, bigint)
  FROM PUBLIC, anon, authenticated;

-- text_mention: dobbelt-gating (M4) — kilde-tekst OG mål synlig.
ALTER TABLE text_mention ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tm_read ON text_mention;
CREATE POLICY tm_read ON text_mention FOR SELECT TO anon, authenticated
USING (
  -- kilde-tekst synlig (person-bundet narrativ/note → personens synlighed; ikke-privat)
  CASE kilde_type
    WHEN 'narrative' THEN EXISTS (SELECT 1 FROM narrative n WHERE n.id=kilde_id
       AND coalesce(n.privat,false)=false
       AND (n.subjekt_type<>'person' OR person_offentlig(n.subjekt_id)))
    WHEN 'note' THEN EXISTS (SELECT 1 FROM note nt WHERE nt.id=kilde_id
       AND coalesce(nt.privat,false)=false
       AND (nt.target_type<>'person' OR person_offentlig(nt.target_id)))
    ELSE false END
  AND
  -- mål synlig (person → person_offentlig; øvrige entiteter offentlige i PoC)
  (maal_type<>'person' OR person_offentlig(maal_id))
);
