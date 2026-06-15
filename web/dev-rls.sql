-- =====================================================================
--  MIDLERTIDIG DEV-LÆSEADGANG for anon-rollen (PoC, app-skive)
--
--  ⚠️  KUN TIL UDVIKLING. Dette giver enhver med anon-nøglen fuld
--      SELECT på de listede tabeller — INGEN levende/afdød-filtrering,
--      INGEN medlem/forsker-skel. Erstattes af det rigtige RLS-lag
--      (CLAUDE.md §6 trin 3) FØR andet end PoC-data lægges i basen.
--
--  Kør i Supabase: SQL Editor -> indsæt -> Run.
--  Rul tilbage med teardown-blokken nederst.
-- =====================================================================

-- Tabeller app-skiven læser. Tilføj flere efterhånden som UI'et vokser.
do $$
declare t text;
begin
  foreach t in array array[
    'person', 'fact', 'assertion', 'conclusion'
  ] loop
    -- 1) PostgREST tilgår basen som rollen 'anon' -> kræver SELECT-grant.
    execute format('grant select on table public.%I to anon;', t);

    -- 2) Aktivér RLS, så adgang styres af politikker (ikke kun grants).
    execute format('alter table public.%I enable row level security;', t);

    -- 3) Midlertidig: tillad al læsning. (USING true = ingen filtrering.)
    execute format('drop policy if exists dev_anon_read on public.%I;', t);
    execute format(
      'create policy dev_anon_read on public.%I for select to anon using (true);', t
    );
  end loop;
end $$;

-- =====================================================================
--  TEARDOWN (kør for at fjerne den midlertidige adgang igen):
--
--  do $$
--  declare t text;
--  begin
--    foreach t in array array['person','fact','assertion','conclusion'] loop
--      execute format('drop policy if exists dev_anon_read on public.%I;', t);
--      execute format('revoke select on table public.%I from anon;', t);
--    end loop;
--  end $$;
-- =====================================================================
