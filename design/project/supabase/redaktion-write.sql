-- =====================================================================
--  redaktion-write.sql — skrivning fra redaktør-arbejdsbordet
--  Aktiverer: redaktør-login (Supabase Auth) + rolle-styret skrivning.
--    • rolle = 'redaktion'  → skriver DIREKTE til evidens-/data-tabeller
--    • rolle = 'medlem'     → skriver til STAGING (suggestion), som
--                              redaktionen godkender bagefter
--
--  VIGTIGT: kolonnenavnene på fact/conclusion/assertion/citation herunder
--  er ANTAGET ud fra modellen fact→conclusion→assertion→citation.
--  Ret dem så de matcher jeres faktiske skema før I kører scriptet.
--  Alt er idempotent (IF NOT EXISTS / CREATE OR REPLACE) hvor muligt.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1) ROLLER  —  knyt en rolle til hver bruger via profiles
-- ---------------------------------------------------------------------
-- Antager en profiles-tabel (1:1 med auth.users). Tilføjer rolle-kolonne.
create table if not exists public.profiles (
  id                    uuid primary key references auth.users(id) on delete cascade,
  reventlow_person_id   bigint,                    -- "mig" i slægten (jf. README)
  rolle                 text not null default 'medlem'
                          check (rolle in ('medlem','forsker','redaktion')),
  oprettet_at           timestamptz not null default now()
);

-- Opret automatisk en profil-række når en ny bruger registreres.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer as $$
begin
  insert into public.profiles (id) values (new.id)
  on conflict (id) do nothing;
  return new;
end; $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Hjælpefunktion: den aktuelle brugers rolle (eller 'anon').
create or replace function public.app_role()
returns text language sql stable as $$
  select coalesce((select rolle from public.profiles where id = auth.uid()), 'anon');
$$;

create or replace function public.is_redaktion()
returns boolean language sql stable as $$
  select public.app_role() = 'redaktion';
$$;


-- ---------------------------------------------------------------------
-- 2) STAGING  —  forslag fra ikke-redaktører (medlem/forsker)
-- ---------------------------------------------------------------------
create table if not exists public.suggestion (
  id              bigint generated always as identity primary key,
  -- hvad foreslås:
  art             text not null
                    check (art in ('fakta','relation','narrativ','gods','hverv','vaaben','medie','ny_person')),
  subjekt_type    text not null default 'person',   -- person | estate | slaegt | organisation ...
  subjekt_id      bigint,                            -- null ved 'ny_person'
  felt            text,                              -- fx 'foedt' ved art='fakta'
  vaerdi          text,                              -- den foreslåede værdi
  -- kilde (citat):
  kilde_source_id bigint references public.source(id),
  kilde_fritekst  text,                              -- hvis kilden ikke er en source-række endnu
  -- fuldt payload for komplekse arter (relation/narrativ/...):
  payload         jsonb not null default '{}'::jsonb,
  note            text,
  -- workflow:
  status          text not null default 'afventer'
                    check (status in ('afventer','godkendt','afvist')),
  oprettet_af     uuid not null default auth.uid() references auth.users(id),
  oprettet_at     timestamptz not null default now(),
  behandlet_af    uuid references auth.users(id),
  behandlet_at    timestamptz,
  resultat_assertion_id bigint                       -- sættes når et forslag materialiseres
);

create index if not exists suggestion_status_idx  on public.suggestion(status);
create index if not exists suggestion_subjekt_idx on public.suggestion(subjekt_type, subjekt_id);


-- ---------------------------------------------------------------------
-- 3) RLS  —  hvem må læse/skrive hvad
-- ---------------------------------------------------------------------

-- 3a) suggestion: enhver autentificeret må OPRETTE; man ser egne; redaktion ser/behandler alle.
alter table public.suggestion enable row level security;

drop policy if exists suggestion_insert_auth on public.suggestion;
create policy suggestion_insert_auth on public.suggestion
  for insert to authenticated
  with check ( oprettet_af = auth.uid() );

drop policy if exists suggestion_select_own_or_red on public.suggestion;
create policy suggestion_select_own_or_red on public.suggestion
  for select to authenticated
  using ( oprettet_af = auth.uid() or public.is_redaktion() );

drop policy if exists suggestion_update_red on public.suggestion;
create policy suggestion_update_red on public.suggestion
  for update to authenticated
  using ( public.is_redaktion() )
  with check ( public.is_redaktion() );

-- 3b) Evidens-tabeller: kun redaktion må skrive direkte.
--     (Læsning styres fortsat af jeres eksisterende dev-rls.sql.)
--     Gentag mønstret for hver tabel I tillader direkte redaktionel skrivning til.
do $$
declare t text;
begin
  foreach t in array array['assertion','citation','conclusion','narrative','relation','family','family_member','person','estate','organisation','person_external_id','coat_of_arms','media']
  loop
    if to_regclass('public.'||t) is not null then
      execute format('alter table public.%I enable row level security;', t);

      execute format('drop policy if exists %I on public.%I;', t||'_ins_red', t);
      execute format($p$create policy %I on public.%I for insert to authenticated with check ( public.is_redaktion() );$p$, t||'_ins_red', t);

      execute format('drop policy if exists %I on public.%I;', t||'_upd_red', t);
      execute format($p$create policy %I on public.%I for update to authenticated using ( public.is_redaktion() ) with check ( public.is_redaktion() );$p$, t||'_upd_red', t);
    end if;
  end loop;
end $$;


-- ---------------------------------------------------------------------
-- 4) MATERIALISÉR ET FORSLAG  —  redaktionens "godkend"-knap
--     Omdanner et 'fakta'-forslag til assertion + citation og peger
--     fact'ets conclusion på den nye assertion (blåstempling).
--     Kør som SECURITY DEFINER, men gat'et til redaktion.
--     NB: tilpas kolonner (felt/vaerdi/valgt_assertion_id) til jeres skema.
-- ---------------------------------------------------------------------
create or replace function public.godkend_forslag(p_suggestion_id bigint)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  s   public.suggestion;
  a_id bigint;
begin
  if not public.is_redaktion() then
    raise exception 'Kun redaktion kan godkende forslag';
  end if;

  select * into s from public.suggestion where id = p_suggestion_id and status = 'afventer';
  if not found then
    raise exception 'Forslag % findes ikke / er allerede behandlet', p_suggestion_id;
  end if;

  if s.art = 'fakta' then
    -- 1) ny assertion (påstand)
    insert into public.assertion (subjekt_type, subjekt_id, felt, vaerdi, oprettet_af)
    values (s.subjekt_type, s.subjekt_id, s.felt, s.vaerdi, s.oprettet_af)
    returning id into a_id;

    -- 2) citat på påstanden
    insert into public.citation (assertion_id, source_id, lokation, note)
    values (a_id, s.kilde_source_id, s.kilde_fritekst, s.note);

    -- 3) blåstempl: peg conclusion på den nye assertion
    update public.conclusion
       set valgt_assertion_id = a_id, vaerdi = s.vaerdi
     where subjekt_type = s.subjekt_type and subjekt_id = s.subjekt_id and felt = s.felt;
  else
    -- relation/narrativ/gods/hverv/...: håndteres efter payload (udfyldes pr. art)
    raise notice 'Materialisering for art=% er ikke implementeret endnu', s.art;
  end if;

  update public.suggestion
     set status = 'godkendt', behandlet_af = auth.uid(), behandlet_at = now(),
         resultat_assertion_id = a_id
   where id = p_suggestion_id;

  return a_id;
end; $$;

grant execute on function public.godkend_forslag(bigint) to authenticated;


-- ---------------------------------------------------------------------
-- 5) SÅDAN GØR APPEN  (reference — ingen SQL)
-- ---------------------------------------------------------------------
-- Redaktør-login:   POST {SUPABASE_URL}/auth/v1/token?grant_type=password
--                   body { email, password }  → access_token (JWT)
-- Skriv som medlem: POST {URL}/rest/v1/suggestion           (Bearer access_token)
-- Skriv som redaktion (fakta): POST {URL}/rest/v1/assertion + /citation,
--                   PATCH /conclusion?...   (Bearer access_token)
-- Godkend forslag:  POST {URL}/rest/v1/rpc/godkend_forslag  { p_suggestion_id }
-- =====================================================================


-- ---------------------------------------------------------------------
-- 6) REVISIONSLOG  —  udelelig "hvem gjorde hvad" på tværs af tabeller
--     Append-only: kun triggeren skriver (security definer); kun redaktion
--     må læse; ingen update/delete-policy = rækker kan ikke ændres bagefter.
--     Fanger INSERT/UPDATE/DELETE med aktør (fra JWT, kan ikke forfalskes),
--     rolle, gammel→ny værdi og tidspunkt.
-- ---------------------------------------------------------------------
create table if not exists public.audit_log (
  id           bigint generated always as identity primary key,
  tabel        text not null,
  raekke_id    text,
  handling     text not null check (handling in ('INSERT','UPDATE','DELETE')),
  aktoer       uuid,
  aktoer_rolle text,
  gammel       jsonb,
  ny           jsonb,
  tidspunkt    timestamptz not null default now()
);
create index if not exists audit_log_tabel_idx on public.audit_log(tabel, raekke_id);
create index if not exists audit_log_aktoer_idx on public.audit_log(aktoer);

alter table public.audit_log enable row level security;
-- Kun redaktion må læse loggen (bidrager-info er ikke offentlig).
drop policy if exists audit_select_red on public.audit_log;
create policy audit_select_red on public.audit_log
  for select to authenticated using ( public.is_redaktion() );
-- Bevidst INGEN insert/update/delete-policy → kun fn_audit() (security definer) skriver.

create or replace function public.fn_audit()
returns trigger language plpgsql security definer set search_path = public as $$
declare rid text;
begin
  rid := (to_jsonb(coalesce(new, old)) ->> 'id');
  insert into public.audit_log (tabel, raekke_id, handling, aktoer, aktoer_rolle, gammel, ny)
  values (
    tg_table_name, rid, tg_op, auth.uid(), public.app_role(),
    case when tg_op in ('UPDATE','DELETE') then to_jsonb(old) end,
    case when tg_op in ('INSERT','UPDATE') then to_jsonb(new) end
  );
  return coalesce(new, old);
end; $$;

-- Sæt revisions-trigger på alle tabeller hvor proveniens skal fanges.
do $$
declare t text;
begin
  foreach t in array array['assertion','citation','conclusion','suggestion','narrative','relation','family','family_member','person','estate','organisation','person_external_id','coat_of_arms','media']
  loop
    if to_regclass('public.'||t) is not null then
      execute format('drop trigger if exists %I on public.%I;', 'audit_'||t, t);
      execute format('create trigger %I after insert or update or delete on public.%I for each row execute function public.fn_audit();', 'audit_'||t, t);
    end if;
  end loop;
end $$;

-- Praktisk opslag: "hvem bidrog til denne oplysning" (navn + dato + kilde i app'en).
-- Slå aktør-navn op via profiles/auth; kildeangivelse hentes fra citation/source.
-- Eksempel (redaktion-only):
--   select a.id, a.felt, a.vaerdi, a.oprettet_at,
--          pr.id as aktoer, pr.rolle,
--          s.titel as kilde, c.lokation
--     from assertion a
--     left join profiles pr on pr.id = a.oprettet_af
--     left join citation c  on c.assertion_id = a.id
--     left join source s    on s.id = c.source_id
--    where a.subjekt_type='person' and a.subjekt_id = :pid;
-- =====================================================================
