-- =====================================================================

-- ---------- PRIVAT KILDEEVIDENS ----------
-- Ingen API-rolle har direkte adgang. Default privileges gælder for den
-- DDL-ejer, som kører filen; kør derfor deployment med den normale ejerrolle.
revoke all on schema private from public, anon, authenticated;
alter default privileges in schema private
  revoke all on tables from public, anon, authenticated;
alter default privileges in schema private
  revoke all on sequences from public, anon, authenticated;
-- PostgreSQLs implicitte PUBLIC-EXECUTE på nye funktioner er global; et
-- schema-lokalt REVOKE kan ikke fjerne den. Fremtidige funktioner skal derfor
-- altid have en eksplicit, gennemset grant (også hvis private senere får USAGE).
alter default privileges
  revoke execute on functions from public, anon, authenticated, service_role;
alter default privileges in schema private
  revoke execute on functions from public, anon, authenticated;

do $$
declare v_table text;
begin
  foreach v_table in array array[
    'extraction_run','source_rendition','source_record','source_record_occurrence',
    'source_record_anchor_event','source_record_revision_event','source_observation',
    'source_observation_text','source_mention','source_persona','source_persona_mention',
    'interpretation','interpretation_observation','interpretation_promotion_rule',
    'interpretation_promotion_authorization','interpretation_promotion_batch','interpretation_promotion',
    'source_persona_identity','source_persona_identity_event',
    'narrative_record_publication','narrative_publication_event',
    'narrative_legacy_publication'
  ] loop
    if to_regclass(format('private.%I',v_table)) is not null then
      execute format('alter table private.%I enable row level security',v_table);
      execute format('revoke all on table private.%I from public,anon,authenticated',v_table);
    end if;
  end loop;
end $$;
revoke all on all sequences in schema private from public, anon, authenticated;
revoke execute on all functions in schema private from public, anon, authenticated;

-- #152 additive event foundation: service_role has no direct table/helper path.
-- The safe public capability function is explicitly callable, but no writer is
-- granted while the contract remains at version 1.
revoke all on table private.narrative_publication_event,
  private.narrative_legacy_publication
  from public, anon, authenticated, service_role;
revoke all on function private.validate_narrative_publication_event(),
  private.reject_narrative_publication_event_mutation(),
  private.validate_narrative_legacy_publication()
  from public, anon, authenticated, service_role;
revoke all on function public.narrative_record_contract_version()
  from public, anon, authenticated, service_role;
grant execute on function public.narrative_record_contract_version()
  to anon, authenticated, service_role;

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

-- entitet_offentlig: fælles polymorf synligheds-regel for et (type,id)-mål. Erstatter det gentagne
-- "type <> 'person'"-mønster, der var FAIL-OPEN på to måder (Codex-fund F-02c): (1) family-mål blev
-- behandlet som offentligt → levende families vielse-/skilsmisse-fakta + noter lækkede til anon OG
-- authenticated; (2) enhver ukendt/fejlstavet discriminator (type-kolonnerne er fritekst uden CHECK)
-- blev behandlet som offentlig. FAIL-CLOSED ELSE. NB: fact/relation-mål (kun note/text_mention kan
-- pege der) håndteres IKKE her — de skal cascade gennem targetets EGEN RLS (se note/text_mention-
-- policyerne), ikke entitets-gates. SECURITY DEFINER pga. family_offentlig.
-- Står EFTER media_rettigheder_ok fordi media-grenen kalder den (SQL-bodies valideres ved CREATE).
create or replace function public.entitet_offentlig(p_type text, p_id bigint)
returns boolean language sql stable security definer set search_path = public as $$
  select case
    when p_type = 'person' then public.person_offentlig(p_id)
    when p_type = 'family' then public.family_offentlig(p_id)
    -- media: fakta/noter/relationer følger publiceringsgaten (spec §1b, MM-01).
    -- Redaktionen ser fortsat alt via det additive redaktion_read-lag.
    when p_type = 'media' then public.media_rettigheder_ok(p_id)
    -- det faste ikke-PII-entitetssæt (sted/gods/våben/linje/organisation/begivenhed/kilde/arkiv)
    when p_type in ('place','estate','coat_of_arms','slaegt','lineage','organisation',
                    'historical_event','source','repository') then true
    else false  -- ukendt/fejlstavet type → fail-closed
  end;
$$;
revoke all on function public.entitet_offentlig(text, bigint) from public;
grant execute on function public.entitet_offentlig(text, bigint) to anon, authenticated;

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
    'coat_of_arms','slaegt','lineage','lineage_scheme','lineage_scheme_entry',
    'lineage_scheme_entry_lineage','family','historical_event'
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

-- Overgangs-viewet er læsbart, men security_invoker lader fortsat de underliggende
-- person_external_id-politikker afgøre hvilke personkoordinater en klient ser.
GRANT SELECT ON public.person_source_coordinate_legacy TO anon, authenticated;

-- Generelle beskrivelser: publicerede, ikke-private beskrivelser følger deres
-- kanoniske subjekts synlighed. Kildekoblinger forbliver i private schema og
-- må kun læses gennem en senere redaktions-RPC.
GRANT SELECT ON public.entity_description TO anon, authenticated;
ALTER TABLE public.entity_description ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS anon_read ON public.entity_description;
CREATE POLICY anon_read ON public.entity_description FOR SELECT TO anon
  USING (status='published' AND privat=false
         AND public.entitet_offentlig(subjekt_type,subjekt_id));
DROP POLICY IF EXISTS auth_read ON public.entity_description;
CREATE POLICY auth_read ON public.entity_description FOR SELECT TO authenticated
  USING (status='published' AND privat=false
         AND public.entitet_offentlig(subjekt_type,subjekt_id));
DROP POLICY IF EXISTS redaktion_read ON public.entity_description;
CREATE POLICY redaktion_read ON public.entity_description FOR SELECT TO authenticated
  USING ((select public.current_rolle())='redaktion');
ALTER TABLE private.entity_description_source ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE private.entity_description_source FROM PUBLIC,anon,authenticated;

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
-- 2) PERSON: central person_offentlig-gate (afdød, ikke-privat, ikke-staged).
-- =========================================================
grant select on table public.person to anon;
alter table public.person enable row level security;
drop policy if exists anon_read on public.person;
create policy anon_read on public.person for select to anon
  using (public.person_offentlig(id));

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

-- narrative: version 1 preserves the historical privacy/person gate. At
-- version 2 the helper exhaustively gates person/DAA rows by event or ledger.
grant select on table public.narrative to anon;
alter table public.narrative enable row level security;
drop policy if exists anon_read on public.narrative;
create policy anon_read on public.narrative for select to anon
  using (public.person_daa_narrative_publication_allowed(id));

-- haendelse: kun ikke-skjulte projektioner hvis både subjekt og substrat er offentlige.
revoke all on table public.haendelse from public, anon, authenticated;
grant select on table public.haendelse to anon, authenticated;
alter table public.haendelse enable row level security;
drop policy if exists anon_read on public.haendelse;
create policy anon_read on public.haendelse for select to anon
  using (
    feed_status <> 'skjult'
    and public.entitet_offentlig(subjekt_type, subjekt_id)
    and exists (select 1 from public.narrative n where n.id=narrative_id)
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
    'person','person_external_id','family_member','fact','relation','narrative','haendelse','note',
    'assertion','conclusion','citation'
  ] loop
    execute format('grant select on table public.%I to authenticated;', t);
    execute format('drop policy if exists auth_read on public.%I;', t);
  end loop;
end $$;

-- person: samme centrale gate som anon (inkl. K2 staged); redaktion_read nedenfor
-- giver fortsat redaktører adgang til staged/private/levende rækker.
create policy auth_read on public.person for select to authenticated
  using (public.person_offentlig(id));
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
-- narrative uses the same exhaustive, version-aware server predicate as anon.
-- The separate redaktion_read policy below remains additive and unchanged.
create policy auth_read on public.narrative for select to authenticated
  using (public.person_daa_narrative_publication_allowed(id));
create policy auth_read on public.haendelse for select to authenticated
  using (
    feed_status <> 'skjult'
    and public.entitet_offentlig(subjekt_type, subjekt_id)
    and exists (select 1 from public.narrative n where n.id=narrative_id)
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

-- RPC-grants: signature-aware allow-list. A new red_* overload receives no
-- privilege merely because of its name; it must be classified here or in a
-- later, purpose-specific ACL block.
DO $redaction_rpc_allow_list$
DECLARE v_signature text;
BEGIN
  -- Functions are installed before this file on a fresh deployment, so default
  -- privileges alone cannot close an already-created, unclassified overload.
  -- Reset the complete current red_* surface before reopening exact signatures.
  FOR v_signature IN
    SELECT 'public.'||function.oid::regprocedure::text
      FROM pg_proc function
      JOIN pg_namespace namespace ON namespace.oid=function.pronamespace
     WHERE namespace.nspname='public'
       AND function.proname LIKE 'red\_%' ESCAPE '\'
     ORDER BY function.oid
  LOOP
    EXECUTE format(
      'REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated,service_role',
      v_signature
    );
  END LOOP;

  FOREACH v_signature IN ARRAY ARRAY[
    'public.red_activate_1939_v50_batch(uuid,uuid)',
    'public.red_afgoer_source_persona(uuid,integer,text,bigint,text)',
    'public.red_apply_1939_v50_canonical_delta(uuid,text,jsonb)',
    'public.red_apply_1939_v50_name_completion(uuid,text,jsonb)',
    'public.red_apply_1939_v50_person_create(uuid,text,jsonb)',
    'public.red_apply_1939_v50_source_evidence(uuid,text,jsonb)',
    'public.red_apply_reimport_cases(uuid,text,text)',
    'public.red_authorize_1939_v50_cutover(uuid,uuid,timestamptz)',
    'public.red_authorize_1939_v50_name_completion(text,uuid,text,text,jsonb,jsonb)',
    'public.red_authorize_1939_v50_reimport(text,text,text,bigint,jsonb,jsonb,uuid,timestamptz)',
    'public.red_authorize_1939_v50_reversal(uuid,uuid,timestamptz)',
    'public.red_authorize_reimport_case_reversal(uuid,text,uuid,timestamptz)',
    'public.red_authorize_reimport_cases(bigint,text,text,text,text,text,text,text,text,text,text,jsonb,jsonb,uuid,timestamptz)',
    'public.red_begin_1939_v50_name_completion(uuid,text,uuid)',
    'public.red_begin_1939_v50_reimport(uuid,text,text)',
    'public.red_bekraeft_media_upload(bigint,bigint,text)',
    'public.red_decide_interpretation(uuid,integer,text,jsonb)',
    'public.red_decide_source_persona_identity(uuid,bigint,integer,text,jsonb)',
    'public.red_decide_source_persona_placement(uuid,integer,text,jsonb)',
    'public.red_decide_source_record_placement(uuid,integer,text,jsonb)',
    'public.red_edit_oplysning(bigint,text,text,text)',
    'public.red_erstat_media_fil(bigint,text,text,bigint,integer,integer,text,text,jsonb)',
    'public.red_finalize_1939_v50_name_completion(uuid)',
    'public.red_finalize_1939_v50_reimport(uuid)',
    'public.red_fjern_feed_pin(text)',
    'public.red_fjern_ikke_samme_som(bigint)',
    'public.red_fjern_media(bigint)',
    'public.red_fjern_samme_som(bigint)',
    'public.red_flyt_barn(bigint,bigint,bigint,text)',
    'public.red_fortryd_change_set(bigint,boolean)',
    'public.red_genopret_media(bigint)',
    'public.red_ikke_samme_som(bigint,bigint)',
    'public.red_lock_1939_v50_name_completion(text)',
    'public.red_match_personer()',
    'public.red_ocr_historik(text,text,text)',
    'public.red_opdater_media(bigint,text,text,text,text)',
    'public.red_opret_estate(text,text,bigint)',
    'public.red_opret_fakta(text,bigint,text,text,date,date,text,text,text)',
    'public.red_opret_kilde(text,text,text,boolean,smallint)',
    'public.red_opret_media(text,text,text,text,text,text,text,bigint,integer,integer,text,text,text,boolean)',
    'public.red_opret_organisation(text,text)',
    'public.red_opret_person(text,text,boolean,text,text,text)',
    'public.red_opret_story(text,bigint,text,text,bigint,bigint,bigint,bigint,date,date,text,text,boolean)',
    'public.red_opret_union(bigint,bigint,text,integer)',
    'public.red_person_grid()',
    'public.red_person_narrative_publication_history(bigint)',
    'public.red_person_narrative_records(bigint)',
    'public.red_preflight_1939_v50_name_completion(uuid,uuid,text,jsonb)',
    'public.red_authorize_interpretation_promotions(jsonb,text,uuid,timestamp with time zone)',
    'public.red_preview_interpretation_promotions(jsonb)',
    'public.red_preview_reimport_cases(bigint,text,jsonb)',
    'public.red_promote_interpretations_batch(jsonb,text,uuid)',
    'public.red_publicer_narrative_record(bigint,uuid,text,text)',
    'public.red_publicer_personer(bigint[])',
    'public.red_publicer_udgave(bigint)',
    'public.red_rediger_story(bigint,text,text,bigint,bigint,bigint,bigint,date,date,text,text,boolean)',
    'public.red_registrer_media_variant(bigint,text,text,text,bigint,integer,integer)',
    'public.red_relation(text,bigint,text,bigint,text,text)',
    'public.red_ret_ocr_felt(bigint,text,text,text,text,jsonb,text,text)',
    'public.red_reverse_1939_v50_reimport(uuid,uuid)',
    'public.red_reverse_reimport_cases(uuid,uuid)',
    'public.red_saet_portraet(bigint,bigint)',
    'public.red_samme_som(bigint,bigint)',
    'public.red_set_familie_konfidens(bigint,bigint,text,text)',
    'public.red_set_familie_ordinal(bigint,bigint,text,integer)',
    'public.red_set_feed_pin(text,text)',
    'public.red_set_haendelse_status(bigint,text)',
    'public.red_set_koen(bigint,text)',
    'public.red_set_konklusion(bigint)',
    'public.red_set_media_rettigheder(bigint,text,boolean,text,text,text,text)',
    'public.red_set_privat(bigint,boolean)',
    'public.red_set_story_kilder(bigint,jsonb)',
    'public.red_set_story_status(bigint,text)',
    'public.red_slet_familie_link(bigint,bigint,text)',
    'public.red_slet_medierelation_uden_evidens(bigint)',
    'public.red_slet_oplysning(bigint)',
    'public.red_slet_person(bigint)',
    'public.red_slet_person_preview(bigint)',
    'public.red_slet_relation(bigint)',
    'public.red_slet_story(bigint)',
    'public.red_source_persona_detail(uuid)',
    'public.red_source_persona_history(uuid)',
    'public.red_source_persona_queue(text,bigint,uuid,integer)',
    'public.red_suggest(text,text,bigint,text,text,text,jsonb,text)',
    'public.red_tilbagetraek_fakta(bigint)',
    'public.red_tilbagetraek_narrative_record(bigint)',
    'public.red_tilfoej_barn(bigint,bigint,text,text)',
    'public.red_tilfoej_foraeldre_paastand(bigint,bigint,bigint,text,text,text)',
    'public.red_tilfoej_oplysning(bigint,text,date,date,text,text,text)',
    'public.red_tilfoej_partner(bigint,bigint,integer)',
    'public.red_tilfoej_relation(bigint,text,bigint,text,text)',
    'public.red_udrens_media(bigint)',
    'public.red_udrens_media_preview(bigint)',
    'public.red_upload_media(text,text,text,text,text,text,bigint,text,bigint,bigint,integer,integer,text,text,text,boolean)',
    'public.red_upsert_fakta(text,bigint,text,text,date,date,text,text,text)',
    'public.red_upsert_narrativ(text,bigint,text,boolean,bigint,text)',
    'public.red_vaelg_foraeldre(bigint,text)'
  ] LOOP
    IF to_regprocedure(v_signature) IS NULL THEN
      RAISE EXCEPTION 'RLS_REDACTION_RPC_ALLOW_LIST_SIGNATURE_MISSING: %',v_signature;
    END IF;
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated',v_signature);
  END LOOP;
END
$redaction_rpc_allow_list$;

-- #152 Tasks 3-4 remain additive and uncallable until Task 7's atomic cutover.
-- The private kernels are denied alongside every currently installed wrapper.
REVOKE ALL ON FUNCTION
  private.mutate_person_narrative_record(text,bigint,bigint,text,text,boolean,text),
  private.withdraw_legacy_narrative(uuid,text,text),
  private.reverse_narrative_publication_event(uuid,text),
  public.red_upsert_person_narrative_record(bigint,bigint,text,text,boolean,text),
  public.red_publicer_person_narrative_record(bigint,bigint,text,text),
  public.red_revider_publiceret_person_narrative_record(bigint,bigint,text,text,text),
  public.red_revalider_person_narrative_record(bigint,bigint,text,text),
  public.red_kasser_person_narrative_record(bigint,bigint,text,text),
  public.red_tilbagetraek_person_narrative_record(bigint,bigint,text,text),
  public.red_tilbagetraek_legacy_narrative(uuid,text,text),
  public.red_fortryd_person_narrative_publication_event(uuid,text)
  FROM PUBLIC,anon,authenticated,service_role;
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
                           'relation','narrative','haendelse','note','assertion','conclusion','citation','text_mention']
  loop
    execute format('drop policy if exists redaktion_read on public.%I;', t);
    execute format(
      'create policy redaktion_read on public.%I for select to authenticated '
      || 'using ((select public.current_rolle()) = ''redaktion'');', t);
  end loop;
end $$;

-- Levende feed fase 3: stories fail-closer som hændelser/personer. Kladder, private
-- stories og stories om ikke-offentlige subjekter når aldrig publikum.
grant select on table public.story to anon, authenticated;
revoke insert, update, delete, references, trigger, truncate on table public.story from anon, authenticated;
alter table public.story enable row level security;
drop policy if exists anon_read on public.story;
create policy anon_read on public.story for select to anon
  using (status = 'publiceret'
     and coalesce(privat, false) = false
     and public.entitet_offentlig(subjekt_type, subjekt_id));
drop policy if exists auth_read on public.story;
create policy auth_read on public.story for select to authenticated
  using (status = 'publiceret'
     and coalesce(privat, false) = false
     and public.entitet_offentlig(subjekt_type, subjekt_id));
drop policy if exists redaktion_read on public.story;
create policy redaktion_read on public.story for select to authenticated
  using ((select public.current_rolle()) = 'redaktion');

-- story_kilde arver parent-storyens synlighed (EXISTS-cascade).
grant select on table public.story_kilde to anon, authenticated;
revoke insert, update, delete, references, trigger, truncate on table public.story_kilde from anon, authenticated;
alter table public.story_kilde enable row level security;
drop policy if exists anon_read on public.story_kilde;
create policy anon_read on public.story_kilde for select to anon
  using (exists (select 1 from public.story s where s.id = story_id));
drop policy if exists auth_read on public.story_kilde;
create policy auth_read on public.story_kilde for select to authenticated
  using (exists (select 1 from public.story s where s.id = story_id));
drop policy if exists redaktion_read on public.story_kilde;
create policy redaktion_read on public.story_kilde for select to authenticated
  using ((select public.current_rolle()) = 'redaktion');

-- feed_pin er ren kurering uden PII og skal kunne indlæses af hele klientmotoren.
grant select on table public.feed_pin to anon, authenticated;
revoke insert, update, delete, references, trigger, truncate on table public.feed_pin from anon, authenticated;
alter table public.feed_pin enable row level security;
drop policy if exists anon_read on public.feed_pin;
create policy anon_read on public.feed_pin for select to anon using (true);
drop policy if exists auth_read on public.feed_pin;
create policy auth_read on public.feed_pin for select to authenticated using (true);

-- Konflikt-view: læsbar for authenticated (RLS håndhæves af security_invoker på basistabeller).
grant select on public.red_konflikt to authenticated;
grant select on public.red_konflikt to anon;

-- =====================================================================
-- 2026-07-26: Person OCR kvalitetsark — korrektionsjournal
-- Aktuelle beslutninger er kun læsbare for redaktionen. Direkte DML er lukket:
-- Task 4's rolle-gated RPC bliver den eneste skrivevej og change_event bevarer auditsporet.
-- =====================================================================
ALTER TABLE public.import_korrektion ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.import_korrektion FROM anon;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON TABLE public.import_korrektion FROM authenticated;
GRANT SELECT ON TABLE public.import_korrektion TO authenticated;
DROP POLICY IF EXISTS redaktion_read ON public.import_korrektion;
CREATE POLICY redaktion_read ON public.import_korrektion FOR SELECT TO authenticated
  USING ((select public.current_rolle()) = 'redaktion');

-- Grid-RPC'en er den eneste læseoverflade for kvalitetsarket. Den læser som ejer,
-- men dens interne rolle-gate er stadig autoritativ; den delte fingerprint-helper er intern.
REVOKE EXECUTE ON FUNCTION public.ocr_input_fingerprint(text,text,text,jsonb,text)
  FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.red_person_grid() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.red_person_grid() TO authenticated;
REVOKE EXECUTE ON FUNCTION public.red_ret_ocr_felt(bigint,text,text,text,text,jsonb,text,text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.red_ret_ocr_felt(bigint,text,text,text,text,jsonb,text,text)
  TO authenticated;
REVOKE EXECUTE ON FUNCTION public.red_ocr_historik(text,text,text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.red_ocr_historik(text,text,text)
  TO authenticated;

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
GRANT EXECUTE ON FUNCTION hist_for_subjekter(text,bigint[]) TO authenticated;
GRANT EXECUTE ON FUNCTION hist_events(bigint)            TO authenticated;
GRANT EXECUTE ON FUNCTION red_fortryd_change_set(bigint,boolean) TO authenticated;
-- Redaktionel identitets-sammenkædning (samme_som) — spec 2026-07-02.
GRANT EXECUTE ON FUNCTION red_samme_som(bigint,bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION red_fjern_samme_som(bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION red_publicer_udgave(bigint) TO authenticated;

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

-- C3 identitets-UPDATE: prelock-beviset er intern transaktionsstate, ikke API-data.
-- Tabellen har ingen ekstern læse-/skriveflade; alle legitime kald går gennem ejerens
-- SECURITY DEFINER-kæde, og cleanup-triggeren fjerner rækkerne ved transaktionsslut.
ALTER TABLE private.identity_relation_update_prelock ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE private.identity_relation_update_prelock
  FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION
  private.lock_identity_people(bigint[]),
  private.prelock_identity_relation_update(jsonb,jsonb),
  private.cleanup_identity_relation_update_prelock()
  FROM PUBLIC, anon, authenticated;

-- 2026-07-17 (post-cutover advisor-lint): _ensure_foraeldrefamilie_redaktionel er en intern
-- Problem 2-helper tilføjet EFTER F-01 REVOKE-sweepet ovenfor, så den manglede samme REVOKE.
-- Den HAR allerede current_rolle()-guarden (belt-and-suspenders, ikke exploiterbar) — dette er
-- ren konsistens: intern _-helper, ikke API-endpoint. Kaldes kun fra gatede red_*-funktioner.
REVOKE EXECUTE ON FUNCTION _ensure_foraeldrefamilie_redaktionel(bigint, bigint)
  FROM PUBLIC, anon, authenticated;

-- 2026-07-03: udledt slægtsnavn — slaegtsnavn_karantaene er en ren intern log skrevet af
-- regen_person_visning() (ejeren bypasser RLS ved interne kald); ingen redaktør-UI læser den
-- endnu (spec §6, bevidst udskudt) → deny-all, samme mønster som version_pk_registry.
ALTER TABLE slaegtsnavn_karantaene ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON slaegtsnavn_karantaene FROM anon, authenticated;

-- text_mention: dobbelt-gating (M4) — kilde-tekst OG mål synlig.
ALTER TABLE text_mention ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON public.text_mention TO anon, authenticated;
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
  CASE WHEN maal_type='media'
    THEN public.media_synlig_anon(maal_id)
    ELSE public.entitet_offentlig(maal_type, maal_id)
  END
);

-- DAA 1939 v50 production-writer: private journal state is never a client table.
ALTER TABLE private.reimport_1939_authorization ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.reimport_1939_write_batch ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.reimport_1939_write_event ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.reimport_1939_name_completion_result ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.reimport_1939_authorization,private.reimport_1939_write_batch,
  private.reimport_1939_write_event,private.reimport_1939_name_completion_result FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION private.reject_reimport_1939_event_mutation(),
  private.require_reimport_1939_editor(),private.require_reimport_1939_open_batch(uuid),
  private.ensure_reimport_1939_source_evidence(uuid,text,jsonb)
  FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.red_authorize_1939_v50_reimport(text,text,text,bigint,jsonb,jsonb,uuid,timestamptz),
  public.red_begin_1939_v50_reimport(uuid,text,text),
  public.red_apply_1939_v50_source_evidence(uuid,text,jsonb),
  public.red_apply_1939_v50_person_create(uuid,text,jsonb),
  public.red_apply_1939_v50_canonical_delta(uuid,text,jsonb),
  public.red_finalize_1939_v50_reimport(uuid),
  public.red_authorize_1939_v50_reversal(uuid,uuid,timestamptz),
  public.red_reverse_1939_v50_reimport(uuid,uuid),
  public.red_authorize_1939_v50_cutover(uuid,uuid,timestamptz),
  public.red_activate_1939_v50_batch(uuid,uuid)
  FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION private.reimport_1939_canonical_json_text(jsonb),
  private.reimport_1939_canonical_json_sha256(jsonb),
  private.validate_reimport_1939_name_completion(uuid,uuid,text,jsonb),
  public.red_lock_1939_v50_name_completion(text),
  public.red_authorize_1939_v50_name_completion(text,uuid,text,text,jsonb,jsonb),
  public.red_preflight_1939_v50_name_completion(uuid,uuid,text,jsonb),
  public.red_begin_1939_v50_name_completion(uuid,text,uuid),
  public.red_apply_1939_v50_name_completion(uuid,text,jsonb),
  public.red_finalize_1939_v50_name_completion(uuid)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.red_authorize_1939_v50_reimport(text,text,text,bigint,jsonb,jsonb,uuid,timestamptz),
  public.red_authorize_1939_v50_reversal(uuid,uuid,timestamptz),
  public.red_authorize_1939_v50_cutover(uuid,uuid,timestamptz)
  TO service_role;
GRANT EXECUTE ON FUNCTION public.red_begin_1939_v50_reimport(uuid,text,text),
  public.red_apply_1939_v50_source_evidence(uuid,text,jsonb),
  public.red_apply_1939_v50_person_create(uuid,text,jsonb),
  public.red_apply_1939_v50_canonical_delta(uuid,text,jsonb),
  public.red_finalize_1939_v50_reimport(uuid),
  public.red_reverse_1939_v50_reimport(uuid,uuid),
  public.red_activate_1939_v50_batch(uuid,uuid)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.red_lock_1939_v50_name_completion(text),
  public.red_preflight_1939_v50_name_completion(uuid,uuid,text,jsonb),
  public.red_begin_1939_v50_name_completion(uuid,text,uuid),
  public.red_apply_1939_v50_name_completion(uuid,text,jsonb),
  public.red_finalize_1939_v50_name_completion(uuid)
  TO authenticated;

-- C3 apply plan Task 5: generic reimport case ledger. No RPCs exist yet (Task 6
-- builds those against service_role/authenticated); until then the ledger has
-- no direct DML grant to any role -- table owner only.
ALTER TABLE private.reimport_case_authorization ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.reimport_case_batch ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.reimport_case_event ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.reimport_case_authorization,
  private.reimport_case_batch,
  private.reimport_case_event
  FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION private.reject_reimport_case_event_mutation()
  FROM PUBLIC,anon,authenticated;

-- C3 apply plan Task 6: least-privilege ACL for the generic reimport case RPCs.
-- The ledger tables above stay without any direct DML grant; the only way in is
-- through these three SECURITY DEFINER entry points. Two-step principal split:
-- the service-role gateway issues the short-lived authorization, an
-- authenticated redaktion principal consumes it through apply. Both still pass
-- private.require_reimport_1939_editor(), so role membership is the gateway and
-- the JWT subject is the actor. Every privileged helper is private and revoked
-- from every role including service_role.
REVOKE ALL ON FUNCTION private.reimport_case_source_record_state(bigint,text),
  private.reimport_case_narrative_state(bigint,bigint),
  private.reimport_case_binding_state(uuid,bigint),
  private.validate_reimport_case_selection(jsonb),
  private.validate_reimport_case_elements(jsonb,jsonb),
  private.validate_reimport_case_counts(jsonb),
  private.reimport_case_receipt(uuid),
  private.write_reimport_case_narrative(bigint,bigint,bigint,text,boolean,text)
  FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.red_preview_reimport_cases(bigint,text,jsonb),
  public.red_authorize_reimport_cases(bigint,text,text,text,text,text,text,text,text,text,text,jsonb,jsonb,uuid,timestamptz),
  public.red_apply_reimport_cases(uuid,text,text)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.red_preview_reimport_cases(bigint,text,jsonb)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.red_authorize_reimport_cases(bigint,text,text,text,text,text,text,text,text,text,text,jsonb,jsonb,uuid,timestamptz)
  TO service_role;
GRANT EXECUTE ON FUNCTION public.red_apply_reimport_cases(uuid,text,text)
  TO authenticated;

-- ---------- DAA 1939 v50 fase C3: reversal RPCs (Task 7) ----------
-- Same principal split as the apply family: service_role authorises the
-- reversal, authenticated performs it, and the plan oracle stays private to
-- every Supabase role.
REVOKE ALL ON FUNCTION private.reimport_case_reversal_plan(uuid)
  FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.red_authorize_reimport_case_reversal(uuid,text,uuid,timestamptz),
  public.red_reverse_reimport_cases(uuid,uuid)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.red_authorize_reimport_case_reversal(uuid,text,uuid,timestamptz)
  TO service_role;
GRANT EXECUTE ON FUNCTION public.red_reverse_reimport_cases(uuid,uuid)
  TO authenticated;

-- #152 Task 2: the two typed editor reads are authenticated entry points,
-- but perform their own fail-closed redaktion role check. All canonical state
-- projectors remain private even though PostgreSQL grants new functions to
-- PUBLIC by default.
REVOKE ALL ON FUNCTION private.narrative_record_labels(uuid),
  private.narrative_publication_state(bigint,bigint,text),
  private.narrative_record_state(bigint,bigint,text,boolean),
  private.narrative_legacy_publication_state(uuid),
  private.narrative_legacy_state(uuid,boolean)
  FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.red_person_narrative_records(bigint),
  public.red_person_narrative_publication_history(bigint)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.red_person_narrative_records(bigint),
  public.red_person_narrative_publication_history(bigint)
  TO authenticated;

-- #152 Task 5: the RLS helper is a boolean-only SECURITY DEFINER capability;
-- the two public biography RPCs expose no private identifiers or event state.
REVOKE ALL ON TABLE private.narrative_record_publication,
  private.narrative_publication_event,
  private.narrative_legacy_publication
  FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION
  public.person_daa_narrative_publication_allowed(bigint),
  public.public_person_bio_source_versions(bigint[]),
  public.public_person_bio_source_versions_v2(bigint[])
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION
  public.person_daa_narrative_publication_allowed(bigint),
  public.public_person_bio_source_versions(bigint[]),
  public.public_person_bio_source_versions_v2(bigint[])
  TO anon,authenticated;

-- #152 Task 7: one version-aware ACL source of truth is applied after every
-- historical grant block. The cutover kernel calls the same helper atomically.
SELECT private.apply_narrative_record_contract_acl(
  public.narrative_record_contract_version()
);

-- #153 Task 4: the source-scoped adapter has no direct ledger-table access.
ALTER TABLE private.source_scoped_replace_authorization ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.source_scoped_replace_batch ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.source_scoped_replace_event ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.source_scoped_replace_authorization,private.source_scoped_replace_batch,
  private.source_scoped_replace_event FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.red_authorize_source_scoped_replace(text,text,uuid,uuid,jsonb,text,text,timestamptz),
  public.red_apply_source_scoped_replace(uuid,jsonb),public.red_verify_source_scoped_replace(uuid)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.red_authorize_source_scoped_replace(text,text,uuid,uuid,jsonb,text,text,timestamptz),
  public.red_apply_source_scoped_replace(uuid,jsonb),public.red_verify_source_scoped_replace(uuid)
  TO authenticated;

-- #153 Task 4A: V1 is a fail-closed compatibility tombstone.  Revoke after
-- every historical grant block, then deny direct access to all V3 ledgers.
ALTER TABLE private.source_scoped_replace_authorization ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.source_scoped_replace_batch ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.source_scoped_replace_event ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.source_scoped_replace_v3_attestation ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.source_scoped_replace_v3_authorization ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.source_scoped_replace_v3_batch ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.source_scoped_replace_v3_event ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.source_scoped_replace_v3_manifest_artifact ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.source_scoped_evidence_v3_chain ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.source_scoped_evidence_v3_revision ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.source_scoped_evidence_v3_member ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.source_scoped_evidence_v3_publication ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.source_scoped_evidence_v3_chain_event ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.source_scoped_evidence_v3_chain_state ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE private.source_scoped_replace_authorization,
  private.source_scoped_replace_batch,private.source_scoped_replace_event,
  private.source_scoped_replace_v3_attestation,private.source_scoped_replace_v3_authorization,
  private.source_scoped_replace_v3_batch,private.source_scoped_replace_v3_event,
  private.source_scoped_replace_v3_manifest_artifact,private.source_scoped_evidence_v3_chain,
  private.source_scoped_evidence_v3_revision,private.source_scoped_evidence_v3_member,
  private.source_scoped_evidence_v3_publication,private.source_scoped_evidence_v3_chain_event,
  private.source_scoped_evidence_v3_chain_state
  FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.red_authorize_source_scoped_replace(text,text,uuid,uuid,jsonb,text,text,timestamptz),
  public.red_apply_source_scoped_replace(uuid,jsonb),public.red_verify_source_scoped_replace(uuid),
  private.reject_source_scoped_replace_v1_mutation(),
  private.reject_source_scoped_evidence_v3_mutation(),
  private.enforce_source_scoped_evidence_v3_revision_predecessor()
  FROM PUBLIC,anon,authenticated,service_role;

-- #153 Task 4B: deployment registration is a private capability.  The role
-- can execute its single SECURITY DEFINER entry point, but receives no table
-- privileges and no application role inherits it by default.
ALTER TABLE private.source_scoped_evidence_contract_inventory ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.source_scoped_evidence_v3_deployment ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE private.source_scoped_evidence_contract_inventory,
  private.source_scoped_evidence_v3_deployment
  FROM PUBLIC,anon,authenticated,service_role,daa_source_scoped_evidence_deployer,daa_source_scoped_evidence_gateway;
REVOKE INSERT,UPDATE,DELETE ON TABLE public.fact,public.assertion,public.citation
  FROM anon,authenticated,service_role;
REVOKE ALL ON FUNCTION private.register_source_scoped_evidence_v3_deployment(
  uuid,text,text,text,text,text,uuid
) FROM PUBLIC,anon,authenticated,service_role,daa_source_scoped_evidence_gateway;
REVOKE ALL ON SCHEMA private FROM daa_source_scoped_evidence_deployer,daa_source_scoped_evidence_gateway;
GRANT USAGE ON SCHEMA private TO daa_source_scoped_evidence_deployer;
GRANT EXECUTE ON FUNCTION private.register_source_scoped_evidence_v3_deployment(
  uuid,text,text,text,text,text,uuid
) TO daa_source_scoped_evidence_deployer;

-- #153 Task 4B: schema.sql and db-migrations.sql certify this complete
-- boundary atomically.  RLS only confirms that its idempotent ACL pass did
-- not drift the already-certified deployment capability.
DO $source_scoped_evidence_v3_task4b_receipt$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM private.source_scoped_evidence_v3_migration_receipt receipt
     WHERE receipt.contract_version='source-scoped-evidence-v3-task4b-v2'
       AND receipt.contract_sha256=private.source_scoped_evidence_v3_task4b_contract_sha256()
  ) THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_TASK4B_RECEIPT_DRIFT';
  END IF;
END
$source_scoped_evidence_v3_task4b_receipt$;

-- #153 Task 4C: keep the historical gate and add the immutable V3 revision
-- gate.  These default-owner views repeat the public gate explicitly: their
-- callers must never inherit the owner's RLS bypass. Redaktion remains an
-- explicit additive exception above.
CREATE OR REPLACE VIEW public.source_scoped_evidence_visible_fact_ids
  WITH (security_barrier=true) AS
SELECT fact.id FROM public.fact fact
 WHERE public.entitet_offentlig(fact.subjekt_type,fact.subjekt_id)
   AND (NOT EXISTS (SELECT 1 FROM private.source_scoped_evidence_v3_member member
                    WHERE member.member_kind='fact' AND member.fact_id=fact.id)
        OR EXISTS (SELECT 1 FROM private.source_scoped_evidence_v3_member member
                     JOIN private.source_scoped_evidence_v3_revision revision ON revision.id=member.revision_id
                     JOIN private.source_scoped_evidence_v3_chain_state state ON state.chain_id=revision.chain_id
                    WHERE member.member_kind='fact' AND member.fact_id=fact.id
                      AND state.visible_revision_id=revision.id));
CREATE OR REPLACE VIEW public.source_scoped_evidence_visible_assertion_ids
  WITH (security_barrier=true) AS
SELECT assertion.id FROM public.assertion assertion
   WHERE ((assertion.target_type='fact' AND EXISTS (
           SELECT 1 FROM public.source_scoped_evidence_visible_fact_ids visible_fact
            WHERE visible_fact.id=assertion.target_id))
     OR (assertion.target_type='relation' AND EXISTS (
           SELECT 1 FROM public.relation relation WHERE relation.id=assertion.target_id
             AND public.entitet_offentlig(relation.subjekt_type,relation.subjekt_id)
             AND public.entitet_offentlig(relation.objekt_type,relation.objekt_id))))
   AND (NOT EXISTS (SELECT 1 FROM private.source_scoped_evidence_v3_member member
                    WHERE member.member_kind='assertion' AND member.assertion_id=assertion.id)
        OR EXISTS (SELECT 1 FROM private.source_scoped_evidence_v3_member member
                     JOIN private.source_scoped_evidence_v3_revision revision ON revision.id=member.revision_id
                     JOIN private.source_scoped_evidence_v3_chain_state state ON state.chain_id=revision.chain_id
                    WHERE member.member_kind='assertion' AND member.assertion_id=assertion.id
                      AND state.visible_revision_id=revision.id));
CREATE OR REPLACE VIEW public.source_scoped_evidence_visible_citation_ids
  WITH (security_barrier=true) AS
SELECT citation.id FROM public.citation citation
  JOIN public.assertion assertion ON assertion.id=citation.assertion_id
 WHERE EXISTS (
       SELECT 1 FROM public.source_scoped_evidence_visible_assertion_ids visible_assertion
        WHERE visible_assertion.id=citation.assertion_id)
   AND (NOT EXISTS (SELECT 1 FROM private.source_scoped_evidence_v3_member member
                    WHERE member.member_kind='citation' AND member.citation_id=citation.id)
        OR EXISTS (SELECT 1 FROM private.source_scoped_evidence_v3_member member
                     JOIN private.source_scoped_evidence_v3_revision revision ON revision.id=member.revision_id
                     JOIN private.source_scoped_evidence_v3_chain_state state ON state.chain_id=revision.chain_id
                    WHERE member.member_kind='citation' AND member.citation_id=citation.id
                      AND state.visible_revision_id=revision.id));
REVOKE ALL ON TABLE public.source_scoped_evidence_visible_fact_ids,
  public.source_scoped_evidence_visible_assertion_ids,
  public.source_scoped_evidence_visible_citation_ids
  FROM PUBLIC,anon,authenticated,service_role;
GRANT SELECT ON TABLE public.source_scoped_evidence_visible_fact_ids,
  public.source_scoped_evidence_visible_assertion_ids,
  public.source_scoped_evidence_visible_citation_ids TO anon,authenticated;

DROP POLICY IF EXISTS anon_read ON public.fact;
CREATE POLICY anon_read ON public.fact FOR SELECT TO anon
  USING (public.entitet_offentlig(subjekt_type,subjekt_id)
    AND EXISTS (SELECT 1 FROM public.source_scoped_evidence_visible_fact_ids visible WHERE visible.id=fact.id));
DROP POLICY IF EXISTS auth_read ON public.fact;
CREATE POLICY auth_read ON public.fact FOR SELECT TO authenticated
  USING (public.entitet_offentlig(subjekt_type,subjekt_id)
    AND EXISTS (SELECT 1 FROM public.source_scoped_evidence_visible_fact_ids visible WHERE visible.id=fact.id));

DROP POLICY IF EXISTS anon_read ON public.assertion;
CREATE POLICY anon_read ON public.assertion FOR SELECT TO anon
  USING (((target_type='fact' AND EXISTS (SELECT 1 FROM public.fact fact WHERE fact.id=target_id))
       OR (target_type='relation' AND EXISTS (SELECT 1 FROM public.relation relation WHERE relation.id=target_id)))
    AND EXISTS (SELECT 1 FROM public.source_scoped_evidence_visible_assertion_ids visible WHERE visible.id=assertion.id));
DROP POLICY IF EXISTS auth_read ON public.assertion;
CREATE POLICY auth_read ON public.assertion FOR SELECT TO authenticated
  USING (((target_type='fact' AND EXISTS (SELECT 1 FROM public.fact fact WHERE fact.id=target_id))
       OR (target_type='relation' AND EXISTS (SELECT 1 FROM public.relation relation WHERE relation.id=target_id)))
    AND EXISTS (SELECT 1 FROM public.source_scoped_evidence_visible_assertion_ids visible WHERE visible.id=assertion.id));

DROP POLICY IF EXISTS anon_read ON public.citation;
CREATE POLICY anon_read ON public.citation FOR SELECT TO anon
  USING (EXISTS (SELECT 1 FROM public.assertion assertion WHERE assertion.id=citation.assertion_id)
    AND EXISTS (SELECT 1 FROM public.source_scoped_evidence_visible_citation_ids visible WHERE visible.id=citation.id));
DROP POLICY IF EXISTS auth_read ON public.citation;
CREATE POLICY auth_read ON public.citation FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.assertion assertion WHERE assertion.id=citation.assertion_id)
    AND EXISTS (SELECT 1 FROM public.source_scoped_evidence_visible_citation_ids visible WHERE visible.id=citation.id));

-- #153 Task 4C: publication remains a pair of narrowly granted SECURITY
-- DEFINER RPCs.  The ledger and all helpers stay entirely private.
ALTER TABLE private.source_scoped_evidence_publication_v3_authorization ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE private.source_scoped_evidence_publication_v3_authorization
  FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION
  private.enforce_source_scoped_evidence_publication_v3_authorization_mutation(),
  private.source_scoped_evidence_v3_publication_decision_sha256(jsonb),
  private.validate_source_scoped_evidence_v3_publication_decision(uuid,uuid,uuid,text,jsonb),
  private.source_scoped_evidence_v3_publication_consumer_exists(uuid),
  public.red_authorize_source_scoped_evidence_publication_v3(uuid,uuid,uuid,text,jsonb,uuid,timestamptz),
  public.red_publish_source_scoped_evidence_revision_v3(uuid,jsonb)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION
  public.red_authorize_source_scoped_evidence_publication_v3(uuid,uuid,uuid,text,jsonb,uuid,timestamptz),
  public.red_publish_source_scoped_evidence_revision_v3(uuid,jsonb)
  TO authenticated;

-- Task 4C's final public-view and ACL contract exists only after this RLS
-- pass installs the shared public gate.  Bind the immutable receipt here,
-- rather than to schema.sql's deliberately fail-closed fallback views.
INSERT INTO private.source_scoped_evidence_v3_migration_receipt(contract_version,contract_sha256)
VALUES ('source-scoped-evidence-v3-task4c-v5',private.source_scoped_evidence_v3_task4c_contract_sha256())
ON CONFLICT (contract_version) DO NOTHING;
DO $source_scoped_evidence_v3_task4c_receipt$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM private.source_scoped_evidence_v3_migration_receipt receipt
     WHERE receipt.contract_version='source-scoped-evidence-v3-task4c-v5'
       AND receipt.contract_sha256=private.source_scoped_evidence_v3_task4c_contract_sha256()
  ) THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_TASK4C_RECEIPT_DRIFT';
  END IF;
END
$source_scoped_evidence_v3_task4c_receipt$;
