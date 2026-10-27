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
    'interpretation_promotion_batch','interpretation_promotion',
    'source_persona_identity','source_persona_identity_event',
    'source_persona_identity_candidate_run','source_persona_identity_candidate','person_create_receipt','interpretation_party',
    'identity_control_run','identity_control_sample','identity_control_event',
    'identity_control_exclusion','identity_control_parent_card','identity_control_parent_event',
    'relation_classification_event',
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
-- NB: begge grants tages igen i $anon_gate_hardening$ nederst i filen (medie-indkapslingen) —
-- funktionen er kun naaelig gennem media_synlig_anon, som er SECURITY DEFINER.
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
-- (2026-09-20, Codex-fund) To haerdninger, begge no-op paa de aktuelle data (maalt i prod-kopi:
-- 0 blanke stier, 0 medier uden for 'media'-bucketen, 0 varianter med foraelder i anden bucket) —
-- men datamodellen TILLADER begge tilstande, og saa er de ikke afgjorte af data:
--   · blank/whitespace sti -> NULL (fail-closed). Ellers kunne en raekke med storage_path=''
--     autorisere et objekt ved navn '' — skemaet har ingen non-empty-check, og hverken base-
--     eller variant-writeren afviser den.
--   · variantgrenen korrelerer nu med foraelderens bucket. Uden det kunne en variant hvis
--     foraelder ligger i en ANDEN bucket autorisere et ellers foraeldreloest objekt med samme
--     navn i 'media'-bucketen.
create or replace function public.media_id_for_object(p_name text)
returns bigint language sql stable security definer set search_path=public as $$
  select case when nullif(btrim(p_name), '') is null then null else coalesce(
    (select m.id from public.media m where m.bucket = 'media' and m.storage_path = p_name limit 1),
    (select v.media_id from public.media_variant v
       join public.media pm on pm.id = v.media_id
      where pm.bucket = 'media' and v.storage_path = p_name limit 1)
  ) end;
$$;
revoke all on function public.media_id_for_object(text) from public;
grant execute on function public.media_id_for_object(text) to anon, authenticated;
-- NB: begge grants tages igen i $anon_gate_hardening$ nederst i filen (medie-indkapslingen) —
-- funktionen er kun naaelig gennem media_object_synlig_anon, som er SECURITY DEFINER.

-- Komponér de TO ortogonale gating-dimensioner (afbildet + rettigheder) ÉT sted, så media-tabellen
-- og storage.objects deler nøjagtig samme synligheds-regel (ingen split-brain-drift) og objektet kun
-- kortlægges til media ÉN gang pr. række. NULL mid (forældreløst objekt) → fail-closed (rettigheder_ok=false).
-- SECURITY DEFINER (2026-09-19, medie-indkapsling): denne funktion kaldes UDELUKKENDE fra
-- RLS-politikker (media, media_variant, text_mention.tm_read, storage-objekterne via wrapperen
-- nedenfor), og en politik-krop udføres med KALDERENS rettigheder. Som INVOKER tvang den derfor
-- anon til selv at have EXECUTE på media_afbilder_skjult — dvs. et direkte PII-orakel
-- ("afbilder billede N en levende/privat person?"). Som DEFINER kører de indre kald med ejerens
-- rettigheder, og de indre gates kan lukkes helt for anon. Krop og svar er uændrede.
-- Pris: en DEFINER-SQL-funktion kan ikke inlines af planlæggeren — den kaldes pr. række i de fem
-- politikker (målt på engangskopi, tabellerne er små).
create or replace function public.media_synlig_anon(mid bigint)
returns boolean language sql stable security definer set search_path=public as $$
  select not public.media_afbilder_skjult(mid) and public.media_rettigheder_ok(mid);
$$;
-- SECURITY DEFINER af samme grund som media_synlig_anon (2026-09-20): den er INVOKER-kaldt
-- af authenticated, og saa laenge den er det, skal authenticated selv have EXECUTE paa
-- media_rettigheder_ok. Som DEFINER kan den indre gate lukkes helt. Ubrugt i politikker i dag,
-- men bevares til samtykke-modellen — og en ubrugt funktion, der tvinger et grant aabent, er
-- praecis den slags rest, der overlever en oprydning.
create or replace function public.media_synlig_auth(mid bigint)
returns boolean language sql stable security definer set search_path=public as $$
  select not public.media_afbilder_privat(mid) and public.media_rettigheder_ok(mid);
$$;
revoke all on function public.media_synlig_anon(bigint) from public;
revoke all on function public.media_synlig_auth(bigint) from public;
grant execute on function public.media_synlig_anon(bigint) to anon, authenticated;
grant execute on function public.media_synlig_auth(bigint) to authenticated;

-- entitet_offentlig: fælles polymorf synligheds-regel for et (type,id)-mål. Erstatter det gentagne
-- "type <> 'person'"-mønster, der var FAIL-OPEN på to måder (Codex-fund F-02c): (1) family-mål blev
-- behandlet som offentligt → levende families vielse-/skilsmisse-fakta + noter lækkede til anon OG
-- authenticated; (2) enhver ukendt/fejlstavet discriminator (type-kolonnerne er fritekst uden CHECK)
-- blev behandlet som offentlig. FAIL-CLOSED ELSE. NB: fact/relation-mål (kun note/text_mention kan
-- pege der) håndteres IKKE her — de skal cascade gennem targetets EGEN RLS (se note/text_mention-
-- policyerne), ikke entitets-gates. SECURITY DEFINER pga. family_offentlig.
-- Står EFTER media_synlig_anon fordi media-grenen kalder den (SQL-bodies valideres ved CREATE).
-- Blokken blev flyttet hertil 2026-09-20 netop af den grund — den stod før over media-helperne.
create or replace function public.entitet_offentlig(p_type text, p_id bigint)
returns boolean language sql stable security definer set search_path = public as $$
  select case
    when p_type = 'person' then public.person_offentlig(p_id)
    when p_type = 'family' then public.family_offentlig(p_id)
    -- media: fakta/noter/narrativer/relationer/tekst-henvisninger følger mediets EGEN
    -- synlighed — BEGGE dimensioner. MM-01 (2026-08-06) skærpede grenen fra ubetinget true
    -- til media_rettigheder_ok og tog dermed kun rettighedsdimensionen med; GDPR-dimensionen
    -- faldt bort ét lag inde. Et rettighedsfrigivet billede af en LEVENDE person var derfor
    -- selv usynligt for gæster, mens dets fakta (fotograf, kreditlinje, datering ...) var
    -- læsbare. Nu er reglen den samme som for media-rækken selv (invariant 8, fail-closed).
    -- Målt i prod 2026-09-20 før ændringen: 0 af 13 medier var skjulte, så ingen række
    -- skifter synlighed i dag — men klassen var reel.
    -- Redaktionen ser fortsat alt via det additive redaktion_read-lag.
    when p_type = 'media' then public.media_synlig_anon(p_id)
    -- det faste ikke-PII-entitetssæt (sted/gods/våben/linje/organisation/begivenhed/kilde/arkiv)
    when p_type in ('place','estate','coat_of_arms','slaegt','lineage','organisation',
                    'historical_event','source','repository') then true
    else false  -- ukendt/fejlstavet type → fail-closed
  end;
$$;
revoke all on function public.entitet_offentlig(text, bigint) from public;
grant execute on function public.entitet_offentlig(text, bigint) to anon, authenticated;

-- Sti → synlighed i ÉT kald (2026-09-19, medie-indkapsling). Storage-politikkerne kaldte før
-- media_id_for_object DIREKTE i politik-kroppen; et politik-udtryk udføres med kalderens
-- rettigheder, så anon skulle have EXECUTE på den — dvs. et orakel over hvilke storage-stier der
-- overhovedet findes (og hvilket media_id de hører til), uafhængigt af om objektet er synligt.
-- Wrapperen er SECURITY DEFINER, så anon kun behøver rettighed til dette ene indgangspunkt.
-- Regelsættet er uændret: samme media_synlig_anon oven på samme mapping, forældreløs sti → NULL
-- → fail-closed (media_rettigheder_ok(NULL)=false).
create or replace function public.media_object_synlig_anon(p_name text)
returns boolean language sql stable security definer set search_path=public as $$
  select public.media_synlig_anon(public.media_id_for_object(p_name));
$$;
revoke all on function public.media_object_synlig_anon(text) from public;
grant execute on function public.media_object_synlig_anon(text) to anon, authenticated;

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
      bucket_id = 'media' and public.media_object_synlig_anon(name));
    drop policy if exists media_obj_auth on storage.objects;
    create policy media_obj_auth on storage.objects for select to authenticated using (
      bucket_id = 'media' and public.media_object_synlig_anon(name));  -- fail-close (F-02)
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

-- RPC reset + stable editor allow-list. A new red_* overload receives no
-- privilege merely because of its name. Writer-, narrative-version- and
-- superseded C3-signatures stay revoked here and are owned by later
-- purpose-specific ACL blocks, so a non-transactional deploy cannot expose
-- their authorization boundary between blocks.
-- DROP + CREATE, ikke IF NOT EXISTS + TRUNCATE: en efterladt tabel fra en AFBRUDT koersel
-- maa ikke kunne genbruges som om den var frisk. Vagten nederst dropper den igen, saa en
-- senere DELKOERSEL af vagten alene moeder en manglende tabel og fejler fail-closed frem
-- for at doemme paa en stale liste. (Codex-fund 2026-09-20.)
DROP TABLE IF EXISTS pg_temp.red_allow_list;
CREATE TEMP TABLE red_allow_list(signature text PRIMARY KEY) ON COMMIT PRESERVE ROWS;

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
    'public.red_afgoer_relation_interpretation(uuid,integer,text,bigint,text,jsonb)',
    'public.red_afgoer_source_persona(uuid,integer,text,bigint,text,jsonb)',
    'public.red_bekraeft_media_upload(bigint,bigint,text)',
    'public.red_classify_parent_card(uuid,uuid,integer,text,text,jsonb)',
    'public.red_corroborate_family_identities(uuid,text)',
    'public.red_decide_interpretation(uuid,integer,text,jsonb)',
    'public.red_decide_relation_interpretations(bigint,text)',
    'public.red_decide_source_persona_placement(uuid,integer,text,jsonb)',
    'public.red_decide_source_record_placement(uuid,integer,text,jsonb)',
    'public.red_edit_oplysning(bigint,text,text,text)',
    'public.red_erstat_media_fil(bigint,text,text,bigint,integer,integer,text,text,jsonb)',
    'public.red_evaluate_identity_control_run(uuid)',
    'public.red_fjern_feed_pin(text)',
    'public.red_fjern_ikke_samme_som(bigint)',
    'public.red_fjern_media(bigint)',
    'public.red_fjern_samme_som(bigint)',
    'public.red_flyt_barn(bigint,bigint,bigint,text)',
    'public.red_fortryd_change_set(bigint,boolean)',
    'public.red_genopret_media(bigint)',
    'public.red_identity_candidate_input(bigint,jsonb)',
    'public.red_identity_control_sample(uuid)',
    'public.red_register_identity_control_run(uuid,text)',
    'public.red_relation_persona_input(bigint)',
    'public.red_relation_person_create_input(bigint)',
    'public.red_relation_persona_v2_input(bigint)',
    'public.red_relation_persona_v3_input(bigint)',
    'public.red_relation_child_sheet_input(bigint)',
    'public.red_marriage_ordinal_correction_input(bigint)',
    'public.red_ret_aegteskabsnummer(uuid,integer,text,jsonb)',
    'public.red_genaabn_relation_interpretation(uuid,integer,text,jsonb)',
    'public.red_preview_placement_memberships(bigint)',
    'public.red_promote_placement_memberships(bigint,text)',
    'public.red_reverse_placement_membership(bigint,bigint,text)',
    'public.red_relation_disposition_input(bigint)',
    'public.red_ikke_samme_som(bigint,bigint)',
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
    'public.red_preview_interpretation_promotions(jsonb)',
    'public.red_preview_relation_decisions(bigint)',
    'public.red_preview_relation_promotions(bigint,jsonb)',
    'public.red_promote_relation_interpretations_batch(bigint,jsonb,text)',
    'public.red_preview_reimport_cases(bigint,text,jsonb)',
    'public.red_promote_interpretations_batch(jsonb,text)',
    'public.red_publicer_personer(bigint[])',
    'public.red_publicer_udgave(bigint)',
    'public.red_record_identity_candidates(jsonb,jsonb)',
    'public.red_rediger_story(bigint,text,text,bigint,bigint,bigint,bigint,date,date,text,text,boolean)',
    'public.red_registrer_media_variant(bigint,text,text,text,bigint,integer,integer)',
    'public.red_relation(text,bigint,text,bigint,text,text)',
    'public.red_ret_ocr_felt(bigint,text,text,text,text,jsonb,text,text)',
    'public.red_saet_portraet(bigint,bigint)',
    'public.red_samme_som(bigint,bigint)',
    'public.red_seal_identity_control_run(uuid,text,text)',
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
    'public.red_source_persona_queue(text,bigint,uuid,integer,text)',
    'public.red_suggest(text,text,bigint,text,text,text,jsonb,text)',
    'public.red_tilbagetraek_fakta(bigint)',
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
    -- Skriv signaturen til en session-lokal tabel, saa slut-vagten nederst i filen kan
    -- efterproeve den SAMLEDE red_*-flade uden at duplikere denne liste. Duplikering ville
    -- goere selve kontrolmekanismen til en kilde til drift.
    INSERT INTO pg_temp.red_allow_list(signature) VALUES (v_signature);
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
-- Den historiske enkeltrække-RPC mangler v1's persona-/regel-/værdikontrol.
-- Den må derfor ikke blive genåbnet af den generelle redaktions-RPC-grant ovenfor.
revoke execute on function public.red_promote_interpretation(uuid,text,bigint,jsonb)
  from public, anon, authenticated;
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

-- DAA 1939 v50 production-writer may only exist before the #153 rename. Keep
-- its historical ACLs fail-closed when present, but never make current generic
-- fresh installs depend on removed relations or wrappers.
DO $legacy_1939_writer_acl$
DECLARE v_relation text; v_signature text;
BEGIN
  FOREACH v_relation IN ARRAY ARRAY[
    'private.reimport_1939_authorization','private.reimport_1939_write_batch',
    'private.reimport_1939_write_event','private.reimport_1939_name_completion_result'
  ] LOOP
    IF to_regclass(v_relation) IS NOT NULL THEN
      IF (SELECT relkind FROM pg_class WHERE oid=to_regclass(v_relation)) IN ('r','p') THEN
        EXECUTE format('ALTER TABLE %s ENABLE ROW LEVEL SECURITY',v_relation);
      END IF;
      EXECUTE format('REVOKE ALL ON TABLE %s FROM PUBLIC,anon,authenticated,service_role',v_relation);
    END IF;
  END LOOP;
  FOREACH v_signature IN ARRAY ARRAY[
    'private.reject_reimport_1939_event_mutation()',
    'private.require_reimport_1939_editor()',
    'private.require_reimport_1939_open_batch(uuid)',
    'private.ensure_reimport_1939_source_evidence(uuid,text,jsonb)',
    'private.reimport_1939_canonical_json_text(jsonb)',
    'private.reimport_1939_canonical_json_sha256(jsonb)',
    'private.validate_reimport_1939_name_completion(uuid,uuid,text,jsonb)'
  ] LOOP
    IF to_regprocedure(v_signature) IS NOT NULL THEN
      EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated,service_role',v_signature);
    END IF;
  END LOOP;
  FOREACH v_signature IN ARRAY ARRAY[
    'public.red_authorize_1939_v50_reimport(text,text,text,bigint,jsonb,jsonb,uuid,timestamptz)',
    'public.red_authorize_1939_v50_reversal(uuid,uuid,timestamptz)',
    'public.red_authorize_1939_v50_cutover(uuid,uuid,timestamptz)'
  ] LOOP
    IF to_regprocedure(v_signature) IS NOT NULL THEN
      EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated,service_role',v_signature);
      EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role',v_signature);
    END IF;
  END LOOP;
  FOREACH v_signature IN ARRAY ARRAY[
    'public.red_begin_1939_v50_reimport(uuid,text,text)',
    'public.red_apply_1939_v50_source_evidence(uuid,text,jsonb)',
    'public.red_apply_1939_v50_person_create(uuid,text,jsonb)',
    'public.red_apply_1939_v50_canonical_delta(uuid,text,jsonb)',
    'public.red_finalize_1939_v50_reimport(uuid)',
    'public.red_reverse_1939_v50_reimport(uuid,uuid)',
    'public.red_activate_1939_v50_batch(uuid,uuid)',
    'public.red_lock_1939_v50_name_completion(text)',
    'public.red_preflight_1939_v50_name_completion(uuid,uuid,text,jsonb)',
    'public.red_begin_1939_v50_name_completion(uuid,text,uuid)',
    'public.red_apply_1939_v50_name_completion(uuid,text,jsonb)',
    'public.red_finalize_1939_v50_name_completion(uuid)'
  ] LOOP
    IF to_regprocedure(v_signature) IS NOT NULL THEN
      EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated,service_role',v_signature);
      EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated',v_signature);
    END IF;
  END LOOP;
END
$legacy_1939_writer_acl$;

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
DO $legacy_c3_apply_acl_if_not_superseded$
BEGIN
  IF to_regprocedure(
    'public.red_authorize_reimport(text,text,text,bigint,text,text,jsonb,jsonb,uuid,timestamptz)'
  ) IS NULL THEN
    EXECUTE 'GRANT EXECUTE ON FUNCTION public.red_authorize_reimport_cases(bigint,text,text,text,text,text,text,text,text,text,text,jsonb,jsonb,uuid,timestamptz) TO service_role';
    EXECUTE 'GRANT EXECUTE ON FUNCTION public.red_apply_reimport_cases(uuid,text,text) TO authenticated';
  END IF;
END
$legacy_c3_apply_acl_if_not_superseded$;

-- ---------- DAA 1939 v50 fase C3: reversal RPCs (Task 7) ----------
-- Same principal split as the apply family: service_role authorises the
-- reversal, authenticated performs it, and the plan oracle stays private to
-- every Supabase role.
REVOKE ALL ON FUNCTION private.reimport_case_reversal_plan(uuid)
  FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.red_authorize_reimport_case_reversal(uuid,text,uuid,timestamptz),
  public.red_reverse_reimport_cases(uuid,uuid)
  FROM PUBLIC,anon,authenticated,service_role;
DO $legacy_c3_reversal_acl_if_not_superseded$
BEGIN
  IF to_regprocedure(
    'public.red_authorize_reimport(text,text,text,bigint,text,text,jsonb,jsonb,uuid,timestamptz)'
  ) IS NULL THEN
    EXECUTE 'GRANT EXECUTE ON FUNCTION public.red_authorize_reimport_case_reversal(uuid,text,uuid,timestamptz) TO service_role';
    EXECUTE 'GRANT EXECUTE ON FUNCTION public.red_reverse_reimport_cases(uuid,uuid) TO authenticated';
  END IF;
END
$legacy_c3_reversal_acl_if_not_superseded$;

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
-- Trin 5b 2a (#151): kildevisning for bundne familier; tom i kontrakt 1 (gaten er i funktionen).
REVOKE ALL ON FUNCTION public.public_family_sources(bigint[]) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.public_family_sources(bigint[]) TO anon,authenticated;

-- #152 Task 7: one version-aware ACL source of truth is applied after every
-- historical grant block. A fresh #153 schema intentionally lacks legacy
-- public wrappers; its test-only cutover fixture supplies disabled signatures
-- transactionally. Do not make the durable ACL script recreate those wrappers.
DO $narrative_contract_acl_if_complete$
DECLARE v_signature text; v_complete boolean:=true;
BEGIN
  FOREACH v_signature IN ARRAY ARRAY[
    'public.red_begin_1939_v50_reimport(uuid,text,text)',
    'public.red_apply_1939_v50_source_evidence(uuid,text,jsonb)',
    'public.red_apply_1939_v50_person_create(uuid,text,jsonb)',
    'public.red_apply_1939_v50_canonical_delta(uuid,text,jsonb)',
    'public.red_finalize_1939_v50_reimport(uuid)',
    'public.red_reverse_1939_v50_reimport(uuid,uuid)',
    'public.red_activate_1939_v50_batch(uuid,uuid)',
    'public.red_authorize_1939_v50_reimport(text,text,text,bigint,jsonb,jsonb,uuid,timestamptz)',
    'public.red_authorize_1939_v50_reversal(uuid,uuid,timestamptz)',
    'public.red_authorize_1939_v50_cutover(uuid,uuid,timestamptz)'
  ] LOOP
    v_complete:=v_complete AND to_regprocedure(v_signature) IS NOT NULL;
  END LOOP;
  IF v_complete THEN
    PERFORM private.apply_narrative_record_contract_acl(
      public.narrative_record_contract_version()
    );
  END IF;
END
$narrative_contract_acl_if_complete$;

-- #153 generic profile-bound writer: no table/helper capability is exposed.
ALTER TABLE private.reimport_writer_profile ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.reimport_authorization ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.reimport_batch ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.reimport_event ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.reimport_name_completion_result ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.reimport_writer_profile,private.reimport_authorization,
  private.reimport_batch,private.reimport_event,private.reimport_name_completion_result
  FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION private.reject_reimport_writer_mutation(),
  private.require_reimport_writer_editor(),private.require_reimport_open_batch(uuid),
  private.lock_reimport_writer(bigint,text),
  private.validate_reimport_authorization_payload(jsonb,jsonb),
  private.validate_reimport_writer_config(jsonb),
  private.ensure_reimport_source_evidence(uuid,text,jsonb),
  private.validate_reimport_name_completion(uuid,uuid,text,jsonb),
  private.migrate_legacy_narrative_record(uuid,text,jsonb),
  private.write_clause_evidence(uuid,text,jsonb),
  private.deterministic_uuid(text),private.interpretation_proposal_canonical_json_text(jsonb),
  private.interpretation_proposal_canonical_json_sha256(jsonb),private.normalize_interpretation_proposal_value(jsonb),
  private.interpretation_proposal_key_material(bigint,text,text,jsonb,jsonb),
  private.interpretation_proposal_key_material_sha256(bigint,text,text,jsonb,jsonb),
  private.interpretation_proposal_key(bigint,text,text,jsonb,jsonb),
  private.interpretation_proposal_interpretation_receipt(private.interpretation),
  private.interpretation_proposal_link_receipt(private.interpretation_observation),
  private.interpretation_proposal_disposition_receipt(private.clause_disposition),
  private.write_interpretation_proposal(uuid,text,jsonb),
  private.legacy_migration_reversal_state(uuid),
  private.record_reimport_legacy_reversal(uuid,uuid,jsonb)
  FROM PUBLIC,anon,authenticated,service_role;

-- #148 4.1a: trigger-funktioner og privat vokabular er interne.
REVOKE ALL ON FUNCTION private.validate_clause_observation(), private.validate_clause_disposition()
  FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON TABLE private.vocab, private.clause_disposition, private.clause_disposition_current
  FROM PUBLIC,anon,authenticated,service_role;
-- Omsegmentering (spec 2026-09-27): klausulsæt, triggerfunktioner og writer-hjælpere er interne.
REVOKE ALL ON FUNCTION private.validate_clause_set_seq(), private.check_clause_set_density(),
  private.clause_set_sha256(uuid,integer), private.validate_clause_disposition_set(),
  private.validate_interpretation_observation_current_clause(),
  private.clause_write_prepare(uuid,text,jsonb,text), private.clause_write_set(jsonb,jsonb,integer,text),
  private.write_clause_revision(uuid,text,jsonb)
  FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON TABLE private.clause_observation_current FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.red_authorize_reimport(text,text,text,bigint,text,text,jsonb,jsonb,uuid,timestamptz),
  public.red_preflight_reimport_authorization(uuid,text,text),public.red_begin_reimport(uuid,text,text),public.red_apply_reimport_source_evidence(uuid,text,jsonb),
  public.red_apply_reimport_person_create(uuid,text,jsonb),public.red_apply_reimport_legacy_migration(uuid,text,jsonb),
  public.red_apply_reimport_clause_evidence(uuid,text,jsonb),
  public.red_apply_reimport_clause_revision(uuid,text,jsonb),
  public.red_apply_reimport_interpretation_proposal(uuid,text,jsonb),
  public.red_apply_reimport_relation_persona(uuid,text,jsonb),
  public.red_apply_reimport_relation_person_create(uuid,text,jsonb),
  public.red_apply_reimport_relation_disposition(uuid,text,jsonb),
  public.red_finalize_reimport(uuid),public.red_reimport_batch_result(uuid,uuid),
  public.red_authorize_reimport_reversal(uuid,uuid,timestamptz),public.red_reverse_reimport(uuid,uuid),
  public.red_authorize_reimport_cutover(uuid,uuid,timestamptz),public.red_activate_reimport_batch(uuid,uuid),public.red_apply_reimport_canonical_delta(uuid,text,jsonb),
  public.red_lock_reimport_name_completion(text,bigint,text),public.red_authorize_reimport_name_completion(text,uuid,text,text,bigint,text,text,jsonb,jsonb),
  public.red_preflight_reimport_name_completion(uuid,uuid,text,jsonb),public.red_begin_reimport_name_completion(uuid,text,uuid),
  public.red_apply_reimport_name_completion(uuid,text,jsonb),public.red_finalize_reimport_name_completion(uuid)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.red_authorize_reimport(text,text,text,bigint,text,text,jsonb,jsonb,uuid,timestamptz),
  public.red_authorize_reimport_reversal(uuid,uuid,timestamptz),public.red_authorize_reimport_cutover(uuid,uuid,timestamptz),
  public.red_authorize_reimport_name_completion(text,uuid,text,text,bigint,text,text,jsonb,jsonb)
  TO service_role;
GRANT EXECUTE ON FUNCTION public.red_preflight_reimport_authorization(uuid,text,text),public.red_begin_reimport(uuid,text,text),public.red_apply_reimport_source_evidence(uuid,text,jsonb),
  public.red_apply_reimport_person_create(uuid,text,jsonb),public.red_apply_reimport_legacy_migration(uuid,text,jsonb),
  public.red_apply_reimport_clause_evidence(uuid,text,jsonb),
  public.red_apply_reimport_clause_revision(uuid,text,jsonb),
  public.red_apply_reimport_interpretation_proposal(uuid,text,jsonb),
  public.red_apply_reimport_relation_persona(uuid,text,jsonb),
  public.red_apply_reimport_relation_person_create(uuid,text,jsonb),
  public.red_apply_reimport_relation_disposition(uuid,text,jsonb),
  public.red_finalize_reimport(uuid),public.red_reimport_batch_result(uuid,uuid),
  public.red_reverse_reimport(uuid,uuid),public.red_activate_reimport_batch(uuid,uuid),public.red_apply_reimport_canonical_delta(uuid,text,jsonb),
  public.red_lock_reimport_name_completion(text,bigint,text),public.red_preflight_reimport_name_completion(uuid,uuid,text,jsonb),
  public.red_begin_reimport_name_completion(uuid,text,uuid),public.red_apply_reimport_name_completion(uuid,text,jsonb),
  public.red_finalize_reimport_name_completion(uuid)
  TO authenticated;

-- #153 retains the historic 1939 entry points only as pinned compatibility
-- adapters.  The views never expose their generic private base tables.  Reset
-- all facade ACLs here, then let the one #152 version-aware authority apply
-- the exact v2 compatibility split; do not re-grant in a trailing block.
REVOKE ALL ON FUNCTION
  public.red_authorize_1939_v50_reimport(text,text,text,bigint,jsonb,jsonb,uuid,timestamptz),
  public.red_begin_1939_v50_reimport(uuid,text,text),
  public.red_apply_1939_v50_source_evidence(uuid,text,jsonb),
  public.red_apply_1939_v50_person_create(uuid,text,jsonb),
  public.red_apply_1939_v50_canonical_delta(uuid,text,jsonb),
  public.red_finalize_1939_v50_reimport(uuid),
  public.red_authorize_1939_v50_reversal(uuid,uuid,timestamptz),
  public.red_reverse_1939_v50_reimport(uuid,uuid),
  public.red_authorize_1939_v50_cutover(uuid,uuid,timestamptz),
  public.red_activate_1939_v50_batch(uuid,uuid),
  public.red_lock_1939_v50_name_completion(text),
  public.red_authorize_1939_v50_name_completion(text,uuid,text,text,jsonb,jsonb),
  public.red_preflight_1939_v50_name_completion(uuid,uuid,text,jsonb),
  public.red_begin_1939_v50_name_completion(uuid,text,uuid),
  public.red_apply_1939_v50_name_completion(uuid,text,jsonb),
  public.red_finalize_1939_v50_name_completion(uuid)
  FROM PUBLIC,anon,authenticated,service_role;
DO $reimport_1939_v2_facade_acl$
BEGIN
  PERFORM private.apply_narrative_record_contract_acl(
    public.narrative_record_contract_version()
  );
END
$reimport_1939_v2_facade_acl$;

-- ---------------------------------------------------------------------------
-- ANON-HÆRDNING af gate-funktioner (Supabase advisor 0028, 2026-09-19)
--
-- Målt i prod før ændringen:
--   · family_offentlig(fid) svarer FALSE for præcis de familier der rummer en
--     skjult (levende/privat/staged) person — 35 af 682. Kaldbar af anon er den
--     dermed et eksistens-orakel: en uindlogget kan gennemløbe id'er og kortlægge
--     hvilke grene der har levende medlemmer. Identitet lækker ikke, kun eksistens.
--   · media_synlig_auth var kaldbar af anon i prod, skønt den kun gives til
--     authenticated her i filen (Supabase' direkte anon-grant overlever ikke et
--     "revoke ... from public" — rollen SKAL navngives).
--   · De tre hist_*-funktioner havde stadig PUBLIC i deres ACL ("=X/postgres").
--     Rollegaten i kroppen kaster for anon, så de lækker intet, men PUBLIC-grantet
--     er unødigt og er eneste lag ud over gaten.
--
-- Hvorfor det er sikkert (efterprøvet mod prod-katalogen, ikke kun mod filerne):
--   · Ingen RLS-politik kalder nogen af dem (pg_policies: nul træf).
--   · family_offentlig kaldes KUN fra entitet_offentlig, som er SECURITY DEFINER
--     og derfor kører det indre kald med ejerens rettigheder.
--   · media_afbilder_privat kaldes KUN fra media_synlig_auth, som er INVOKER og
--     kun skal kunne kaldes af authenticated — derfor beholder authenticated begge.
--   · Nul kald fra web-/mobil-fladen til nogen af dem.
--
-- MEDIE-INDKAPSLINGEN (2026-09-19, anden omgang): media_afbilder_skjult og
-- media_id_for_object kunne IKKE lukkes med et revoke alene — de blev kaldt fra
-- politik-kroppe gennem media_synlig_anon (INVOKER) og direkte i storage-politikken,
-- og et politik-udtryk udføres med kalderens rettigheder. Et revoke ville derfor
-- have stoppet billedvisningen for gæster (fail-closed).
-- De er nu indkapslet: media_synlig_anon er gjort SECURITY DEFINER, og sti→synlighed
-- går gennem den nye DEFINER-wrapper media_object_synlig_anon(text), som er det
-- eneste anon behøver rettighed til. Derfor står de to i listen nedenfor.
-- Rækkefølgen i denne fil er en forudsætning: definitionerne ovenfor køres FØR dette
-- revoke. Vagten lige under løkken efterprøver det i samme transaktion.
--
-- RETTIGHEDSGATEN (2026-09-20): media_rettigheder_ok lukkes nu ogsaa. Argumentet for at
-- lade den staa — "copyright, ikke PII" — holdt ikke: den svarer true for et
-- rettighedsfrigivet medie OGSAA naar mediet er skjult fordi det afbilder en levende
-- person, og var dermed et eksistens-orakel af samme slags som family_offentlig.
-- Forudsaetningen var to ting, som begge er paa plads nu: media_synlig_auth er gjort
-- DEFINER, og entitet_offentlig's media-gren gater paa media_synlig_anon i stedet for
-- raa rettigheder (den reproducerede ellers orakelet og lod medie-fakta laekke om et
-- GDPR-skjult billede).
--
-- FORVENTET: advisor 0028 vil efter denne ændring flage TO NYE funktioner —
-- media_synlig_anon og media_object_synlig_anon er nu SECURITY DEFINER og
-- anon-kaldbare. Det er hensigten: de er indgangspunkter på linje med
-- entitet_offentlig/person_offentlig. Ingen af dem er et orakel — begge svarer
-- false for både skjult og ikke-eksisterende, og anon kan i forvejen læse
-- nøjagtig det samme gennem media/storage.objects. Luk dem IKKE.
-- ---------------------------------------------------------------------------
DO $anon_gate_hardening$
DECLARE
  v_sig text;
  v_roller text;
BEGIN
  FOREACH v_sig IN ARRAY ARRAY[
    'public.family_offentlig(bigint)|public, anon, authenticated',
    -- (2026-09-20, Codex-fund) Ogsaa fra authenticated. Medlems-politikkerne bruger
    -- media_synlig_anon — medlemstieren ser praecis det samme som anon indtil
    -- samtykkemodellen findes. Saa laenge det er kontrakten, er disse to direkte orakler
    -- OVER det, tieren selv kan se: media_afbilder_privat afsloerer at et medie afbilder en
    -- privatmarkeret person, og media_synlig_auth afsloerer et rettighedsfrigivet medie med
    -- en levende person, som medlemmets egen SELECT-politik skjuler. Ingen levende politik-,
    -- app-, R- eller testforbruger krarver dem. Genindfoer en scoped indgang NAAR
    -- samtykkemodellen bygges — ikke foer.
    'public.media_afbilder_privat(bigint)|public, anon, authenticated',
    'public.media_synlig_auth(bigint)|public, anon, authenticated',
    'public.hist_for_subjekt(text,bigint)|public, anon',
    'public.hist_for_subjekter(text,bigint[])|public, anon',
    'public.hist_events(bigint)|public, anon',
    -- medie-indkapslingen: begge er nu kun nåelige gennem DEFINER-lag
    'public.media_afbilder_skjult(bigint)|public, anon, authenticated',
    'public.media_id_for_object(text)|public, anon, authenticated',
    -- rettighedsgaten (2026-09-20): naaelig gennem media_synlig_anon/auth og
    -- entitet_offentlig, som alle tre er DEFINER
    'public.media_rettigheder_ok(bigint)|public, anon, authenticated'
  ] LOOP
    v_roller := split_part(v_sig, '|', 2);
    v_sig    := split_part(v_sig, '|', 1);

    -- fail-closed: en omdøbt eller fjernet signatur skal stoppe deployet,
    -- ikke lydløst efterlade rettigheden urørt
    IF to_regprocedure(v_sig) IS NULL THEN
      RAISE EXCEPTION 'ANON_GATE_HARDENING_SIGNATURE_MISSING: %', v_sig;
    END IF;

    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM %s', v_sig, v_roller);

    -- readback i samme transaktion: virkede tilbagekaldelsen faktisk?
    IF has_function_privilege('anon', to_regprocedure(v_sig), 'EXECUTE') THEN
      RAISE EXCEPTION 'ANON_GATE_HARDENING_READBACK_FAILED: anon kan stadig kalde %', v_sig;
    END IF;
    -- ... og for de signaturer hvor authenticated OGSAA skal miste adgangen. Uden dette tjek
    -- kunne et senere auth-grant forblive groent (Codex-fund 2026-09-20).
    IF v_roller LIKE '%authenticated%'
       AND has_function_privilege('authenticated', to_regprocedure(v_sig), 'EXECUTE') THEN
      RAISE EXCEPTION 'ANON_GATE_HARDENING_READBACK_FAILED: authenticated kan stadig kalde %', v_sig;
    END IF;
  END LOOP;

  -- authenticated SKAL beholde de tre hist_*, ellers mister redaktionen historik-fladen.
  -- De to media-funktioner stod her indtil 2026-09-20; de er nu ogsaa lukket for
  -- authenticated (se begrundelsen i listen ovenfor).
  FOREACH v_sig IN ARRAY ARRAY[
    'public.hist_for_subjekt(text,bigint)',
    'public.hist_for_subjekter(text,bigint[])',
    'public.hist_events(bigint)'
  ] LOOP
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', v_sig);
    IF NOT has_function_privilege('authenticated', to_regprocedure(v_sig), 'EXECUTE') THEN
      RAISE EXCEPTION 'ANON_GATE_HARDENING_AUTH_LOST: authenticated mistede %', v_sig;
    END IF;
  END LOOP;

  -- Medie-indkapslingens forudsætning, efterprøvet i SAMME transaktion som revoket:
  -- de to netop lukkede funktioner må kun være nåelige gennem DEFINER-lag. Er
  -- media_synlig_anon faldet tilbage til INVOKER (fx en delvis kørsel af en ældre
  -- udgave af denne fil), ville revoket have slukket billedvisningen for gæster —
  -- så stop deployet her i stedet.
  IF NOT (SELECT p.prosecdef FROM pg_proc p WHERE p.oid = 'public.media_synlig_anon(bigint)'::regprocedure) THEN
    RAISE EXCEPTION 'MEDIE_INDKAPSLING_BRUDT: media_synlig_anon er INVOKER — revoket ville slukke billedvisningen';
  END IF;
  -- To adskilte tjek, ikke ét OR: en manglende funktion ville ellers fejle inde i
  -- ::regprocedure-casten (SQL kortslutter ikke OR pålideligt), og deployet ville stoppe
  -- med en uforståelig katalogfejl i stedet for den navngivne årsag.
  IF to_regprocedure('public.media_object_synlig_anon(text)') IS NULL THEN
    RAISE EXCEPTION 'MEDIE_INDKAPSLING_BRUDT: sti-wrapperen media_object_synlig_anon(text) mangler';
  END IF;
  IF NOT (SELECT p.prosecdef FROM pg_proc p WHERE p.oid = 'public.media_object_synlig_anon(text)'::regprocedure) THEN
    RAISE EXCEPTION 'MEDIE_INDKAPSLING_BRUDT: media_object_synlig_anon er INVOKER';
  END IF;
  -- Vagten skal bevise indkapslingen HELE vejen: to korrekte DEFINER-funktioner er ikke nok,
  -- hvis en gammel politik stadig kalder media_id_for_object direkte — saa ville revoket slukke
  -- storage-laesningen, og de oevrige tjek ville passere. (Codex-fund 2026-09-20.)
  IF to_regclass('storage.objects') IS NOT NULL THEN
    IF (SELECT count(*) FROM pg_policies
         WHERE schemaname='storage' AND policyname IN ('media_obj_anon','media_obj_auth')) <> 2 THEN
      RAISE EXCEPTION 'MEDIE_INDKAPSLING_BRUDT: storage-politikkerne media_obj_anon/auth mangler';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_policies
                WHERE schemaname='storage' AND policyname IN ('media_obj_anon','media_obj_auth')
                  AND coalesce(qual,'') NOT LIKE '%media_object_synlig_anon%') THEN
      RAISE EXCEPTION 'MEDIE_INDKAPSLING_BRUDT: en storage-politik kalder ikke sti-wrapperen';
    END IF;
  END IF;

  -- BEGGE roller: anon baerer gaestefladen, authenticated baerer medlemsfladen
  -- (media_obj_auth og text_mention.tm_read kalder de samme to indgange).
  -- Rettighedsgatens indkapsling: alle tre kaldere skal vaere DEFINER, ellers slukker
  -- revoket enten medie-fladen (media_synlig_anon/auth) eller alt medie-tilknyttet
  -- indhold — fakta, noter, narrativer, relationer, tekst-henvisninger (entitet_offentlig).
  FOREACH v_sig IN ARRAY ARRAY[
    'public.media_synlig_auth(bigint)',
    'public.entitet_offentlig(text,bigint)'
  ] LOOP
    IF NOT (SELECT p.prosecdef FROM pg_proc p WHERE p.oid = to_regprocedure(v_sig)) THEN
      RAISE EXCEPTION 'MEDIE_INDKAPSLING_BRUDT: % er INVOKER — revoket ville slukke medie-tilknyttet indhold', v_sig;
    END IF;
  END LOOP;
  IF (SELECT prosrc FROM pg_proc WHERE oid='public.entitet_offentlig(text,bigint)'::regprocedure)
     NOT LIKE '%media_synlig_anon%' THEN
    RAISE EXCEPTION 'MEDIE_INDKAPSLING_BRUDT: entitet_offentlig gater ikke media paa media_synlig_anon';
  END IF;

  FOREACH v_sig IN ARRAY ARRAY[
    'public.media_synlig_anon(bigint)',
    'public.media_object_synlig_anon(text)',
    'public.entitet_offentlig(text,bigint)'
  ] LOOP
    IF NOT has_function_privilege('anon', to_regprocedure(v_sig), 'EXECUTE') THEN
      RAISE EXCEPTION 'MEDIE_INDKAPSLING_BRUDT: anon kan ikke kalde % — gæster mister billeder', v_sig;
    END IF;
    IF NOT has_function_privilege('authenticated', to_regprocedure(v_sig), 'EXECUTE') THEN
      RAISE EXCEPTION 'MEDIE_INDKAPSLING_BRUDT: authenticated kan ikke kalde % — medlemmer mister billeder', v_sig;
    END IF;
  END LOOP;
END
$anon_gate_hardening$;

-- ---------------------------------------------------------------------------
-- SLUT-VAGT: beskriver allow-listen faktisk hele red_*-fladen? (2026-09-20)
--
-- Baggrund: blokken $redaction_rpc_allow_list$ ovenfor laeser som om dens 74 signaturer
-- ER den redaktionelle flade. Det er de ikke. Den nulstiller ganske vist hele red_*-fladen
-- foerst, men 37 signaturer faar bagefter deres grant af senere, formaalsbestemte blokke
-- (1939 v50-writeren, reimport-writeren, #152's narrative-record-flade). Maalt mod prod
-- 2026-09-20: 126 red_* i alt, 111 authenticated-kaldbare, 0 anon-kaldbare — og NUL drift
-- mellem prod og det, denne fil producerer.
--
-- Det er altsaa ikke et hul. Hullet er, at INTET efterproevede summen: blev tallet 112,
-- ville ingen opdage det. Allow-listens egen RAISE fanger kun en OMDOEBT signatur blandt
-- de 74, ikke et nyt grant fra en anden blok.
--
-- Denne vagt lukker det. De 37 staar eksplicit nedenfor, fordi et praefiks-match ville lade
-- en ny red_apply_reimport_* glide igennem ubemaerket — og det er netop den slags, en
-- allow-liste skal fange. Tilfoejes en ny writer-signatur, skal den tilfoejes her OGSAA;
-- fejlbeskeden siger det.
-- ---------------------------------------------------------------------------
DO $redaction_rpc_surface_guard$
DECLARE
  v_uventet text;
  v_mangler text;
  v_anon text;
  v_sr text;
  v_version int;
  v_antal int;
BEGIN
  IF to_regclass('pg_temp.red_allow_list') IS NULL THEN
    RAISE EXCEPTION 'RLS_REDACTION_SURFACE_GUARD_NO_ALLOW_LIST: db-rls.sql skal koeres som HELE fil i én session — allow-listen har ikke koert';
  END IF;

  -- Kontraktversionen skal vaere KENDT. #152's ACL-autoritet anvender forskellige
  -- rolle/signatur-splits pr. version, og repoet kender i dag kun 1 og 2. En ukendt eller
  -- NULL version maa ikke behandles som "ikke v1" — saa ville en fremtidig v3 lydloest faa
  -- v2's forventningsmaengde paatvunget. (Codex-fund 2026-09-20.)
  IF to_regprocedure('public.narrative_record_contract_version()') IS NULL THEN
    RAISE EXCEPTION 'RLS_REDACTION_SURFACE_GUARD_VERSION: narrative_record_contract_version() mangler — kontraktversionen kan ikke afgoeres';
  END IF;
  SELECT public.narrative_record_contract_version() INTO v_version;
  IF v_version IS NULL OR v_version NOT IN (1,2) THEN
    RAISE EXCEPTION 'RLS_REDACTION_SURFACE_GUARD_VERSION: ukendt narrative-kontraktversion % — opdatér vagtens forventningsmaengde foer denne version tages i brug', coalesce(v_version::text,'NULL');
  END IF;

  DROP TABLE IF EXISTS pg_temp.red_surface_expected;
  CREATE TEMP TABLE red_surface_expected(signature text PRIMARY KEY) ON COMMIT PRESERVE ROWS;

  -- (a) allow-listens 74, leveret af blokken selv — aldrig duplikeret her.
  INSERT INTO red_surface_expected(signature) SELECT signature FROM pg_temp.red_allow_list;

  -- (b) 26 writer-signaturer fra senere, formaalsbestemte blokke. Versions-UAFHAENGIGE:
  --     maalt identisk paa en v1- og en v2-base 2026-09-20.
  INSERT INTO red_surface_expected(signature) VALUES
    ('public.red_activate_1939_v50_batch(uuid,uuid)'),
    ('public.red_activate_reimport_batch(uuid,uuid)'),
    ('public.red_apply_1939_v50_canonical_delta(uuid,text,jsonb)'),
    ('public.red_apply_1939_v50_person_create(uuid,text,jsonb)'),
    ('public.red_apply_1939_v50_source_evidence(uuid,text,jsonb)'),
    ('public.red_apply_reimport_canonical_delta(uuid,text,jsonb)'),
    ('public.red_apply_reimport_clause_evidence(uuid,text,jsonb)'),
    ('public.red_apply_reimport_clause_revision(uuid,text,jsonb)'),
    ('public.red_apply_reimport_interpretation_proposal(uuid,text,jsonb)'),
    ('public.red_apply_reimport_relation_persona(uuid,text,jsonb)'),
    ('public.red_apply_reimport_relation_person_create(uuid,text,jsonb)'),
    ('public.red_apply_reimport_relation_disposition(uuid,text,jsonb)'),
    ('public.red_apply_reimport_legacy_migration(uuid,text,jsonb)'),
    ('public.red_apply_reimport_name_completion(uuid,text,jsonb)'),
    ('public.red_apply_reimport_person_create(uuid,text,jsonb)'),
    ('public.red_apply_reimport_source_evidence(uuid,text,jsonb)'),
    ('public.red_begin_1939_v50_reimport(uuid,text,text)'),
    ('public.red_begin_reimport(uuid,text,text)'),
    ('public.red_begin_reimport_name_completion(uuid,text,uuid)'),
    ('public.red_finalize_1939_v50_reimport(uuid)'),
    ('public.red_finalize_reimport(uuid)'),
    ('public.red_finalize_reimport_name_completion(uuid)'),
    ('public.red_lock_reimport_name_completion(text,bigint,text)'),
    ('public.red_preflight_reimport_authorization(uuid,text,text)'),
    ('public.red_preflight_reimport_name_completion(uuid,uuid,text,jsonb)'),
    ('public.red_reimport_batch_result(uuid,uuid)'),
    ('public.red_reverse_1939_v50_reimport(uuid,uuid)'),
    ('public.red_reverse_reimport(uuid,uuid)');

  -- (c) VERSIONSBESTEMT. Maalt 2026-09-20: v1 aabner fire legacy-indgange, v2 aabner 13
  --     andre. En flad liste over begge ville acceptere et v2-grant paa en v1-base og
  --     omvendt — praecis det hul Codex fandt i foerste udgave af denne vagt.
  IF v_version = 1 THEN
    INSERT INTO red_surface_expected(signature) VALUES
      ('public.red_apply_reimport_cases(uuid,text,text)'),
      ('public.red_reverse_reimport_cases(uuid,uuid)'),
      ('public.red_publicer_narrative_record(bigint,uuid,text,text)'),
      ('public.red_tilbagetraek_narrative_record(bigint)');
  ELSE
    INSERT INTO red_surface_expected(signature) VALUES
      ('public.red_apply_1939_v50_name_completion(uuid,text,jsonb)'),
      ('public.red_begin_1939_v50_name_completion(uuid,text,uuid)'),
      ('public.red_finalize_1939_v50_name_completion(uuid)'),
      ('public.red_fortryd_person_narrative_publication_event(uuid,text)'),
      ('public.red_kasser_person_narrative_record(bigint,bigint,text,text)'),
      ('public.red_lock_1939_v50_name_completion(text)'),
      ('public.red_preflight_1939_v50_name_completion(uuid,uuid,text,jsonb)'),
      ('public.red_publicer_person_narrative_record(bigint,bigint,text,text)'),
      ('public.red_revalider_person_narrative_record(bigint,bigint,text,text)'),
      ('public.red_revider_publiceret_person_narrative_record(bigint,bigint,text,text,text)'),
      ('public.red_tilbagetraek_legacy_narrative(uuid,text,text)'),
      ('public.red_tilbagetraek_person_narrative_record(bigint,bigint,text,text)'),
      ('public.red_upsert_person_narrative_record(bigint,bigint,text,text,boolean,text)');
  END IF;

  -- 1) Ingen red_* maa vaere kaldbar af anon.
  SELECT string_agg('public.'||p.oid::regprocedure::text, ', ' ORDER BY p.oid::regprocedure::text)
    INTO v_anon
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname LIKE 'red\_%' ESCAPE '\'
     AND has_function_privilege('anon', p.oid, 'EXECUTE');
  IF v_anon IS NOT NULL THEN
    RAISE EXCEPTION 'RLS_REDACTION_SURFACE_GUARD_ANON: red_*-funktioner er kaldbare af anon: %', v_anon;
  END IF;

  -- 2) Kaldbar uden at vaere forventet.
  SELECT string_agg('public.'||p.oid::regprocedure::text, ', ' ORDER BY p.oid::regprocedure::text)
    INTO v_uventet
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname LIKE 'red\_%' ESCAPE '\'
     AND has_function_privilege('authenticated', p.oid, 'EXECUTE')
     AND NOT EXISTS (SELECT 1 FROM red_surface_expected e
                      WHERE e.signature = 'public.'||p.oid::regprocedure::text);
  IF v_uventet IS NOT NULL THEN
    RAISE EXCEPTION 'RLS_REDACTION_SURFACE_GUARD_UVENTET: % er authenticated-kaldbar(e) uden at staa paa den gennemgaaede flade (kontrakt v%). Tilfoej signaturen til allow-listen ELLER til denne vagts liste — et grant uden en af delene er ikke gennemgaaet.', v_uventet, v_version;
  END IF;

  -- 3) Forventet og EKSISTERENDE, men ikke kaldbar. Uden denne vej ville et bortfaldet
  --    grant give groen vagt og foerst vise sig som driftsstop. Begraenset til signaturer
  --    der faktisk findes, saa en base uden en given writer ikke giver falsk alarm.
  SELECT string_agg(e.signature, ', ' ORDER BY e.signature)
    INTO v_mangler
    FROM red_surface_expected e
   WHERE to_regprocedure(e.signature) IS NOT NULL
     AND NOT has_function_privilege('authenticated', to_regprocedure(e.signature), 'EXECUTE');
  IF v_mangler IS NOT NULL THEN
    RAISE EXCEPTION 'RLS_REDACTION_SURFACE_GUARD_MANGLER: % findes, men er IKKE authenticated-kaldbar(e) (kontrakt v%). Et bortfaldet grant stopper redaktionen.', v_mangler, v_version;
  END IF;

  -- 4) service_role-fladen. Rollen er betroet, men har BYPASSRLS, saa en fejl i dens
  --    capability-flade er stadig sikkerhedsrelevant. Maalt 2026-09-20: 8 i prod/v2, 9 ved v1.
  SELECT string_agg('public.'||p.oid::regprocedure::text, ', ' ORDER BY p.oid::regprocedure::text)
    INTO v_sr
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname LIKE 'red\_%' ESCAPE '\'
     AND has_function_privilege('service_role', p.oid, 'EXECUTE')
     AND 'public.'||p.oid::regprocedure::text NOT IN (
       'public.red_authorize_1939_v50_cutover(uuid,uuid,timestamp with time zone)',
       'public.red_authorize_1939_v50_name_completion(text,uuid,text,text,jsonb,jsonb)',
       'public.red_authorize_1939_v50_reimport(text,text,text,bigint,jsonb,jsonb,uuid,timestamp with time zone)',
       'public.red_authorize_1939_v50_reversal(uuid,uuid,timestamp with time zone)',
       'public.red_authorize_reimport(text,text,text,bigint,text,text,jsonb,jsonb,uuid,timestamp with time zone)',
       'public.red_authorize_reimport_case_reversal(uuid,text,uuid,timestamp with time zone)',
       'public.red_authorize_reimport_cases(bigint,text,text,text,text,text,text,text,text,text,text,jsonb,jsonb,uuid,timestamp with time zone)',
       'public.red_authorize_reimport_cutover(uuid,uuid,timestamp with time zone)',
       'public.red_authorize_reimport_name_completion(text,uuid,text,text,bigint,text,text,jsonb,jsonb)',
       'public.red_authorize_reimport_reversal(uuid,uuid,timestamp with time zone)');
  IF v_sr IS NOT NULL THEN
    RAISE EXCEPTION 'RLS_REDACTION_SURFACE_GUARD_SERVICE_ROLE: % er service_role-kaldbar(e) uden at staa paa autorisations-listen', v_sr;
  END IF;

  SELECT count(*) INTO v_antal
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname LIKE 'red\_%' ESCAPE '\'
     AND has_function_privilege('authenticated', p.oid, 'EXECUTE');
  RAISE NOTICE 'OK: red_*-fladen gennemgaaet — % authenticated-kaldbare, 0 anon-kaldbare, service_role inden for autorisations-listen (narrative-kontrakt v%)', v_antal, v_version;

  DROP TABLE red_surface_expected;
  DROP TABLE pg_temp.red_allow_list;
END
$redaction_rpc_surface_guard$;
