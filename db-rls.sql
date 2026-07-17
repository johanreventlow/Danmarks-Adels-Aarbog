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
  -- staged (K2-kuratering): en ny udgaves poster skjules indtil redaktør har matchet dem; NULL =
  -- ikke-staget = synlig (kun loaderen sætter TRUE, så NULL-default er sikkert her). Cascader til
  -- fact/relation/narrative via entitet_offentlig (F-02c) — ét ændringspunkt for hele PII-fladen.
  select exists (
    select 1 from public.person p
    where p.id = pid and p.levende = false
      and coalesce(p.privat, false) = false
      and coalesce(p.staged, false) = false
  );
$$;

revoke all on function public.person_offentlig(bigint) from public;
grant execute on function public.person_offentlig(bigint) to anon, authenticated;

-- family_offentlig: en familie er offentlig KUN hvis INTET medlem er ikke-offentligt (levende/privat).
-- Fail-closed: ét levende/privat medlem → hele familien (og dens fakta/noter/narrativer) skjules.
-- SECURITY DEFINER (som person_offentlig): skal se ALLE family_member-rækker uden at blive re-
-- filtreret af family_member-RLS — ellers ville netop det skjulte levende medlem være usynligt for
-- subqueryen → fail-OPEN. Codex-fund F-02c (2026-07-17).
create or replace function public.family_offentlig(fid bigint)
returns boolean language sql stable security definer set search_path = public as $$
  select not exists (
    select 1 from public.family_member fm
    where fm.family_id = fid and not public.person_offentlig(fm.person_id)
  );
$$;
revoke all on function public.family_offentlig(bigint) from public;
grant execute on function public.family_offentlig(bigint) to anon, authenticated;

-- entitet_offentlig: fælles polymorf synligheds-regel for et (type,id)-mål. Erstatter det gentagne
-- "type <> 'person'"-mønster, der var FAIL-OPEN på to måder (Codex-fund F-02c): (1) family-mål blev
-- behandlet som offentligt → levende families vielse-/skilsmisse-fakta + noter lækkede til anon OG
-- authenticated; (2) enhver ukendt/fejlstavet discriminator (type-kolonnerne er fritekst uden CHECK)
-- blev behandlet som offentlig. FAIL-CLOSED ELSE. NB: fact/relation-mål (kun note/text_mention kan
-- pege der) håndteres IKKE her — de skal cascade gennem targetets EGEN RLS (se note/text_mention-
-- policyerne), ikke entitets-gates. SECURITY DEFINER pga. family_offentlig.
create or replace function public.entitet_offentlig(p_type text, p_id bigint)
returns boolean language sql stable security definer set search_path = public as $$
  select case
    when p_type = 'person' then public.person_offentlig(p_id)
    when p_type = 'family' then public.family_offentlig(p_id)
    -- det faste ikke-PII-entitetssæt (sted/gods/våben/linje/organisation/begivenhed/kilde/media/arkiv)
    when p_type in ('place','estate','coat_of_arms','lineage','organisation',
                    'historical_event','source','media','repository') then true
    else false  -- ukendt/fejlstavet type → fail-closed
  end;
$$;
revoke all on function public.entitet_offentlig(text, bigint) from public;
grant execute on function public.entitet_offentlig(text, bigint) to anon, authenticated;

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

-- rettigheds-gate (mediehåndtering 2026-07-04). ANDEN, ortogonal gating-dimension ved siden af
-- afbildet-gatingen: copyright/publikationsret, uafhængig af GDPR-person-gating. FAIL-CLOSED:
-- kun 'klar' + maa_publiceres=true er offentligt. maa_publiceres er en kontrol-kolonne (som
-- person.privat), ikke et fact — RLS må ikke gå assertion→conclusion pr. billede pr. query.
create or replace function public.media_rettigheder_ok(mid bigint)
returns boolean language sql stable security definer set search_path=public as $$
  select coalesce((select m.maa_publiceres and m.upload_status = 'klar'
                     from public.media m where m.id = mid), false);
$$;
revoke all on function public.media_rettigheder_ok(bigint) from public;
grant execute on function public.media_rettigheder_ok(bigint) to anon, authenticated;

-- Kort et storage-objekt tilbage til dets media-række. Stien er autoritativ:
-- storage.objects.name == media.storage_path (unikt pr. (bucket,storage_path)) FOR 'large'-tieren;
-- for 'thumb'/'medium' (billedstørrelser/lightbox 2026-07-05, Slice B1) ligger stien i stedet i
-- media_variant.storage_path og slås op på DENS media_id. Begge grene rammer aldrig samtidig
-- (storage_path er unik i hver tabel for sig), så rækkefølgen her er ligegyldig for korrekthed —
-- kun for hvilken gren der typisk rammes først. SECURITY DEFINER så den kan læse begge tabeller
-- uafhængigt af kalderens RLS. Forældreløst objekt → NULL → fail-closed i storage-politikkerne
-- nedenfor (media_rettigheder_ok(NULL)=false).
create or replace function public.media_id_for_object(p_name text)
returns bigint language sql stable security definer set search_path=public as $$
  select coalesce(
    (select m.id from public.media m where m.bucket = 'media' and m.storage_path = p_name limit 1),
    (select v.media_id from public.media_variant v where v.storage_path = p_name limit 1)
  );
$$;
revoke all on function public.media_id_for_object(text) from public;
grant execute on function public.media_id_for_object(text) to anon, authenticated;

-- Komponér de TO ortogonale gating-dimensioner (afbildet + rettigheder) ÉT sted, så media-tabellen
-- og storage.objects deler nøjagtig samme synligheds-regel (ingen split-brain-drift) og objektet kun
-- kortlægges til media ÉN gang pr. række. NULL mid (forældreløst objekt) → fail-closed (rettigheder_ok=false).
create or replace function public.media_synlig_anon(mid bigint)
returns boolean language sql stable set search_path=public as $$
  select not public.media_afbilder_skjult(mid) and public.media_rettigheder_ok(mid);
$$;
create or replace function public.media_synlig_auth(mid bigint)
returns boolean language sql stable set search_path=public as $$
  select not public.media_afbilder_privat(mid) and public.media_rettigheder_ok(mid);
$$;
revoke all on function public.media_synlig_anon(bigint) from public;
revoke all on function public.media_synlig_auth(bigint) from public;
grant execute on function public.media_synlig_anon(bigint) to anon, authenticated;
grant execute on function public.media_synlig_auth(bigint) to authenticated;

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
    execute format('grant select on table public.%I to anon, authenticated;', t);
    execute format('alter table public.%I enable row level security;', t);
    execute format('drop policy if exists anon_read on public.%I;', t);
    execute format('create policy anon_read on public.%I for select to anon using (true);', t);
    -- authenticated (medlem/forsker/redaktion): samme offentlige adgang som anon — disse
    -- tabeller har ingen person-PII (se kommentar ovenfor). Uden denne policy mister enhver
    -- logget-ind bruger ALLE rækker (anon's grant gælder ikke for authenticated-rollen),
    -- hvilket viste sig som "#<id>" i stedet for navne i app-laget (gods/hverv/kilde/linje).
    execute format('drop policy if exists auth_read on public.%I;', t);
    execute format('create policy auth_read on public.%I for select to authenticated using (true);', t);
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
-- TO ortogonale gating-dimensioner (begge skal være opfyldt for offentlig visning):
--   (1) afbildet-gating (GDPR/person) — media_afbilder_skjult/privat
--   (2) rettigheds-gating (copyright/publikation) — media_rettigheder_ok
-- Redaktion ser alt (additivt), uanset begge.
grant select on table public.media to anon, authenticated;
alter table public.media enable row level security;
drop policy if exists anon_read on public.media;
create policy anon_read on public.media for select to anon
  using (public.media_synlig_anon(media.id));
-- authenticated (medlem): fail-close som anon (Codex-fund F-02). media_synlig_auth tillod levende
-- (afbilder_privat gater kun privat), så medlem-tier så fotos af levende personer uden samtykke —
-- samme læk som person-laget. Bruger nu media_synlig_anon (skjuler levende via afbilder_skjult).
-- media_synlig_auth/media_afbilder_privat bevares til den fremtidige samtykke-model, men er pt. ubrugt.
drop policy if exists auth_read on public.media;
create policy auth_read on public.media for select to authenticated
  using (public.media_synlig_anon(media.id));
-- redaktion: ser alt (additivt oven på de to ovenfor).
drop policy if exists redaktion_read on public.media;
create policy redaktion_read on public.media for select to authenticated
  using ((select public.current_rolle()) = 'redaktion');

-- media_variant (billedstørrelser/lightbox 2026-07-05, Slice B1): egen tabel, egen RLS — men INGEN
-- selvstændig synligheds-logik. Delegerer 1:1 til media_synlig_anon/auth via media_id, så en
-- variant-række ALDRIG kan være synlig når dens forælder ikke er det (og omvendt). Uden disse
-- policies er tabellen enten helt åben (RLS fra) eller helt usynlig for PostgREST (RLS til, ingen
-- policy) — begge forkerte.
grant select on table public.media_variant to anon, authenticated;
alter table public.media_variant enable row level security;
drop policy if exists anon_read on public.media_variant;
create policy anon_read on public.media_variant for select to anon
  using (public.media_synlig_anon(media_id));
drop policy if exists auth_read on public.media_variant;
create policy auth_read on public.media_variant for select to authenticated
  using (public.media_synlig_anon(media_id));  -- fail-close (F-02), spejler forælder-media
drop policy if exists redaktion_read on public.media_variant;
create policy redaktion_read on public.media_variant for select to authenticated
  using ((select public.current_rolle()) = 'redaktion');

-- ---------- STORAGE-OBJEKTER (mediehåndtering 2026-07-04) ----------
-- ÉN privat bucket 'media' — ingen offentlig bucket. Selve bytes'ene serveres via kortlivede
-- signed URLs (createSignedUrl), mintet på kalderens session, så disse politikker håndhæves på
-- kalderens JWT/rolle. Hvorfor privat: begge gating-dimensioner er DYNAMISKE og tilbagekaldelige
-- (person kan markeres privat; tilladelse kan trækkes; maa_publiceres kan flippe) — en offentlig,
-- cache-bar URL kan ikke tilbagekaldes. Politikkerne spejler media-tabel-stakken 1:1 via
-- objekt→media-mapping. Bucket'en skal oprettes som PRIVAT (Supabase Storage / storage.buckets)
-- før disse politikker har effekt.
do $$ begin
  if exists (select 1 from information_schema.tables
             where table_schema='storage' and table_name='objects') then
    -- SELECT — samme synligheds-regel som media-tabellen (via media_synlig_*), så de to aldrig driver
    -- fra hinanden; objekt→media kortlægges kun ÉN gang pr. række.
    drop policy if exists media_obj_anon on storage.objects;
    create policy media_obj_anon on storage.objects for select to anon using (
      bucket_id = 'media' and public.media_synlig_anon(public.media_id_for_object(name)));
    drop policy if exists media_obj_auth on storage.objects;
    create policy media_obj_auth on storage.objects for select to authenticated using (
      bucket_id = 'media' and public.media_synlig_anon(public.media_id_for_object(name)));  -- fail-close (F-02)
    drop policy if exists media_obj_redaktion on storage.objects;
    create policy media_obj_redaktion on storage.objects for select to authenticated using (
      bucket_id = 'media' and (select public.current_rolle()) = 'redaktion');
    -- WRITE: kun redaktion. Bulk-import bruger service_role (bypasser RLS helt) — se import_media.R.
    drop policy if exists media_obj_write on storage.objects;
    create policy media_obj_write on storage.objects for insert to authenticated
      with check (bucket_id = 'media' and (select public.current_rolle()) = 'redaktion');
    drop policy if exists media_obj_update on storage.objects;
    create policy media_obj_update on storage.objects for update to authenticated
      using (bucket_id = 'media' and (select public.current_rolle()) = 'redaktion')
      with check (bucket_id = 'media' and (select public.current_rolle()) = 'redaktion');
    drop policy if exists media_obj_delete on storage.objects;
    create policy media_obj_delete on storage.objects for delete to authenticated
      using (bucket_id = 'media' and (select public.current_rolle()) = 'redaktion');
  end if;
end $$;

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
  using (public.entitet_offentlig(subjekt_type, subjekt_id));

-- relation: gates på BÅDE subjekt og objekt når de er personer.
grant select on table public.relation to anon;
alter table public.relation enable row level security;
drop policy if exists anon_read on public.relation;
create policy anon_read on public.relation for select to anon
  using (
    public.entitet_offentlig(subjekt_type, subjekt_id)
    and public.entitet_offentlig(objekt_type, objekt_id)
  );

-- narrative: ikke-privat OG (ikke-person ELLER person offentlig).
grant select on table public.narrative to anon;
alter table public.narrative enable row level security;
drop policy if exists anon_read on public.narrative;
create policy anon_read on public.narrative for select to anon
  using (
    coalesce(privat, false) = false
    and public.entitet_offentlig(subjekt_type, subjekt_id)
  );

-- note: ikke-privat OG (ikke-person ELLER person offentlig).
grant select on table public.note to anon;
alter table public.note enable row level security;
drop policy if exists anon_read on public.note;
create policy anon_read on public.note for select to anon
  using (
    coalesce(privat, false) = false
    and case
      -- note på et faktum/relation arver targetets synlighed (cascade gennem dets RLS)
      when target_type = 'fact'     then exists (select 1 from public.fact f     where f.id = target_id)
      when target_type = 'relation' then exists (select 1 from public.relation r where r.id = target_id)
      -- note på en entitet (person/family/sted/…): entitets-reglen, fail-closed på ukendt
      else public.entitet_offentlig(target_type, target_id)
    end
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
-- 5) AUTHENTICATED-LAG (medlem): fail-close til SAMME regel som anon (afdøde synlige,
--    levende skjult). Codex-fund F-02 (2026-07-16): den tidligere auth_read filtrerede kun
--    'privat' → enhver logget-ind bruger så alle ikke-private LEVENDE personer uden samtykke,
--    i strid med invariant #8 (levende kræver samtykke). Medlem-tier må ikke se mere end anon
--    før en egentlig samtykke-/slægts-scope-model findes (se FREMTID nederst + Codex-fund F-05).
--    Redaktion beholder fuld adgang via det additive redaktion_read-lag længere nede.
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

-- person: fail-closed på levende (spejler anon_read; NULL levende skjules).
create policy auth_read on public.person for select to authenticated
  using (levende = false and coalesce(privat, false) = false);
-- personbundne: synlige kun hvis personen er offentlig (afdød + ikke-privat).
create policy auth_read on public.person_external_id for select to authenticated
  using (public.person_offentlig(person_id));
create policy auth_read on public.family_member for select to authenticated
  using (public.person_offentlig(person_id));
create policy auth_read on public.fact for select to authenticated
  using (public.entitet_offentlig(subjekt_type, subjekt_id));
-- relation: gates på BÅDE person-endpoints (offentlig). Cycle 02 H3 — using(true) lækkede
-- private personers relationer (ejerskab/hverv/kanter) til logget-ind medlemmer.
create policy auth_read on public.relation for select to authenticated
  using (
    public.entitet_offentlig(subjekt_type, subjekt_id)
    and public.entitet_offentlig(objekt_type, objekt_id)
  );
-- narrative/note: eget privat-flag OG (ikke-person ELLER refereret person offentlig).
-- Cycle 02 H3 — manglede person-gating (ikke-flagget bio/note om privat person lækkede).
create policy auth_read on public.narrative for select to authenticated
  using (
    coalesce(privat,false)=false
    and public.entitet_offentlig(subjekt_type, subjekt_id)
  );
create policy auth_read on public.note for select to authenticated
  using (
    coalesce(privat,false)=false
    and case
      when target_type = 'fact'     then exists (select 1 from public.fact f     where f.id = target_id)
      when target_type = 'relation' then exists (select 1 from public.relation r where r.id = target_id)
      else public.entitet_offentlig(target_type, target_id)
    end
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

-- bookmark: login-eksklusive, egen-scoped (dual-review 21 N1 — eksplicit grant, RLS er ikke nok;
-- Supabase auto-grant'er default-privilegier til anon/authenticated på nye tabeller).
revoke all on table public.bookmark from anon, public;
grant select, insert, delete on table public.bookmark to authenticated;
-- Prod-fund ved anvendelse (2026-07-06): Supabases pg_default_acl for schema public granter
-- automatisk ALLE tabel-privilegier (inkl. UPDATE/REFERENCES/TRIGGER/TRUNCATE) til authenticated
-- på enhver ny tabel — GRANT ovenfor er additivt og fjerner ikke dette. Revoke eksplicit ned til
-- tilsigtet overflade (kun SELECT/INSERT/DELETE — der findes ingen UPDATE-policy, og TRUNCATE
-- omgår RLS helt). Systemisk på tværs af databasen (bekræftet også på media_variant) — kun
-- rettet for bookmark her, se docs/reviews/22-*.md for det fulde fund.
revoke update, references, trigger, truncate on table public.bookmark from authenticated;

drop policy if exists bookmark_select_own on public.bookmark;
create policy bookmark_select_own on public.bookmark
  for select to authenticated using (user_id = auth.uid());
drop policy if exists bookmark_insert_own on public.bookmark;
create policy bookmark_insert_own on public.bookmark
  for insert to authenticated with check (user_id = auth.uid());
drop policy if exists bookmark_delete_own on public.bookmark;
create policy bookmark_delete_own on public.bookmark
  for delete to authenticated using (user_id = auth.uid());

-- RPC-grants: alle red_*-funktioner kaldbare af authenticated (rolle-tjek er INDE i dem).
do $$
declare fn text;
begin
  for fn in select proname from pg_proc where proname like 'red\_%' escape '\'
  loop execute format('grant execute on function public.%I to authenticated;', fn); end loop;
end $$;
-- "from public" alene revoker ikke anon/authenticated (Supabase grantér dem direkte,
-- jf. 2026-07-02-hærdningen nedenfor) — naevn anon eksplicit så hygiejne-hensigten reelt holder.
revoke all on function public.current_rolle() from public, anon;
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
-- Redaktionel identitets-sammenkædning (samme_som) — spec 2026-07-02.
GRANT EXECUTE ON FUNCTION red_samme_som(bigint,bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION red_fjern_samme_som(bigint) TO authenticated;

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

-- 2026-07-16 (sikkerheds-hærdning, review 30/fable-fund): resten af de interne _-helpers er IKKE
-- API-endpoints. Supabase-default-grants eksponerer ALLE public-funktioner for anon/authenticated via
-- PostgREST → uatoriseret kald af muterende helpers (fx _delete_relation_evidence sletter relations-
-- evidens som EJER, omgår RLS). Kaldes kun fra gatede SECURITY DEFINER red_*-funktioner / red_fortryd
-- (kører som ejer → beholder EXECUTE). _delete_relation_evidence har DESUDEN en current_rolle()-guard
-- (belt-and-suspenders). UNDTAGET _regen_mentions_for: kaldes af en SECURITY INVOKER-trigger som
-- SKRIVEREN → REVOKE ville bryde authenticated-redaktørers narrative/note-skrivninger.
REVOKE EXECUTE ON FUNCTION
  _delete_relation_evidence(bigint),
  _row_pk(text, jsonb),
  _version_pk_where(text, jsonb),
  _version_current_row(text, jsonb),
  _version_upsert_row(text, jsonb),
  _version_delete_row(text, jsonb)
  FROM PUBLIC, anon, authenticated;

-- 2026-07-03: udledt slægtsnavn — slaegtsnavn_karantaene er en ren intern log skrevet af
-- regen_person_visning() (ejeren bypasser RLS ved interne kald); ingen redaktør-UI læser den
-- endnu (spec §6, bevidst udskudt) → deny-all, samme mønster som version_pk_registry.
ALTER TABLE slaegtsnavn_karantaene ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON slaegtsnavn_karantaene FROM anon, authenticated;

-- text_mention: dobbelt-gating (M4) — kilde-tekst OG mål synlig.
ALTER TABLE text_mention ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tm_read ON text_mention;
CREATE POLICY tm_read ON text_mention FOR SELECT TO anon, authenticated
USING (
  -- kilde-tekst synlig (person-bundet narrativ/note → entitetens synlighed; ikke-privat).
  -- F-02c: entitet_offentlig i stedet for "<>'person'" (family-kilder + ukendte typer fail-closer nu).
  CASE kilde_type
    WHEN 'narrative' THEN EXISTS (SELECT 1 FROM narrative n WHERE n.id=kilde_id
       AND coalesce(n.privat,false)=false
       AND public.entitet_offentlig(n.subjekt_type, n.subjekt_id))
    WHEN 'note' THEN EXISTS (SELECT 1 FROM note nt WHERE nt.id=kilde_id
       AND coalesce(nt.privat,false)=false
       AND CASE
         WHEN nt.target_type='fact'     THEN EXISTS (SELECT 1 FROM public.fact f     WHERE f.id=nt.target_id)
         WHEN nt.target_type='relation' THEN EXISTS (SELECT 1 FROM public.relation r WHERE r.id=nt.target_id)
         ELSE public.entitet_offentlig(nt.target_type, nt.target_id)
       END)
    ELSE false END
  AND
  -- mål synlig (F-02c: entitet_offentlig — family-mål + ukendte typer fail-closer nu)
  public.entitet_offentlig(maal_type, maal_id)
);
