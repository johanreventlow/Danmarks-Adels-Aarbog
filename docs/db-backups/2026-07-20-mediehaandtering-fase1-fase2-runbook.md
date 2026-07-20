# Prod-deploy runbook: mediehåndtering fase 1 + fase 2

**Formål:** aktivér filsiden (fase 1) og biblioteket (fase 2) i produktionsdatabasen.
Al app-kode er allerede live på web (Vercel deployer automatisk fra `main`) — dette
dokument dækker KUN det udestående database-trin.

**Scope:** kun medie-relaterede ændringer. "Levende feed fase 3" (story/story_kilde/
feed_pin) er en helt urelateret feature, der tilfældigvis ligger lige efter i de samme
filer — den er **bevidst udeladt** her. Kør ikke hele `db-migrations.sql`/`db-rls.sql`
uden at have taget stilling til det separat.

**Risikovurdering:** lavt. Alle ændringer er `CREATE OR REPLACE FUNCTION`,
`CREATE OR REPLACE VIEW`, `DROP FUNCTION IF EXISTS` (efterfulgt af genoprettelse) og
additive RLS-policies/grants. **Ingen `DELETE`, ingen `ALTER TABLE` der fjerner data.**
Den eneste adfærdsændring er en RLS-stramning (§3 nedenfor) — den lukker et hul, den
åbner ikke ét. Ændringerne kan tages tilbage ved at genindsætte de gamle
funktions-/view-definitioner, hvis noget skulle vise sig forkert.

---

## 0. Før du starter

- [ ] Du har adgang til Supabase-projektets dashboard (supabase.com → jeres projekt).
- [ ] Du har afsat ca. 15 minutter uden afbrydelse (trinene skal køres i rækkefølge).
- [ ] Ingen andre redigerer databasen samtidig (single-editor-PoC, jf. `claude.md`).

## 1. Backup (read-only, ingen data ændres af dette trin)

Free-tier har ingen indbygget automatisk backup (`docs/database-current-state.md` §4).
Tag et øjebliksbillede af de berørte tabeller, så du kan sammenligne bagefter:

I Supabase-dashboardet: **SQL Editor** → ny query → kør:

```sql
-- Ren aflæsning, ændrer intet. Kopiér resultatet et sikkert sted (fx en tekstfil),
-- så du har et referencepunkt før ændringen.
select count(*) as antal_media, count(*) filter (where upload_status='klar') as klar,
       count(*) filter (where upload_status='fjernet') as fjernet
from media;

select proname from pg_proc
where proname in ('red_opdater_media','red_genopret_media','red_upload_media')
order by proname;
-- Forventet FØR migrationen: kun 'red_upload_media' (de to andre findes ikke endnu).
```

Hvis I har et Supabase-abonnement med Point-in-Time Recovery (Database → Backups i
dashboardet), er det jeres reelle sikkerhedsnet — tjek at det er slået til.

## 2. Kør migrationsblokken (funktioner + view)

**SQL Editor** → ny query → indsæt HELE blokken nedenfor → **Run**.

```sql
-- ===== Mediehåndtering fase 1 + fase 2 — funktioner og view =====
-- (indhold hentet fra db-migrations.sql linje 2638-2725 på main, 2026-07-20)
```

➡️ Selve SQL-koden ligger i `/tmp/media_migration_scoped.sql` i denne session — jeg
indsætter den i en opfølgende besked, så du kan kopiere den direkte herfra uden at skulle
finde linjenumre i repoet selv.

**Forventet resultat:** "Success. No rows returned." Ingen fejl.

## 3. Kør RLS-tilføjelsen (påkrævet — retter et reelt hul)

**Baggrund (kort):** `text_mention` har hidtil manglet et `GRANT SELECT`, så
`red_doede_links`-viewet reelt har været utilgængeligt for alle — inklusive redaktionen
selv — siden 2026-06-30. Samtidig behandlede databasen omtaler af billeder i tekst som
"altid offentlige" uanset om billedet selv måtte være skjult. Dette trin retter begge dele.

**SQL Editor** → ny query → kør DEL 1:

```sql
-- DEL 1: giv redaktionen fuld læseadgang til text_mention (mangler i dag)
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
```

Kør derefter DEL 2 (leveres i opfølgende besked med fuld SQL):

```sql
-- DEL 2: text_mention grant + korrekt media-synlighed i tm_read-policyen
```

## 4. Verificér

```sql
-- 1) De tre funktioner findes nu alle tre:
select proname from pg_proc
where proname in ('red_opdater_media','red_genopret_media','red_upload_media')
order by proname;

-- 2) Viewet kører uden fejl (kræver redaktør-login i praksis for meningsfuldt resultat,
--    men selve kaldet må ikke fejle med "permission denied"):
select count(*) from red_doede_links;

-- 3) text_mention har nu et grant (forespørgslen må ikke fejle):
select count(*) from text_mention;
```

## 5. Funktionel test i appen

- [ ] Log ind som redaktør på webben → åbn en person med et billede → klik billedet →
      filsiden åbner → redigér titel → Gem → ingen fejl.
- [ ] Åbn "Medier"-fanen i redaktionen → biblioteket viser rækker med kø-chips
      (Rettigheder/Løse/Strandede/Papirkurv) i stedet for tom liste.
- [ ] Upload et upubliceret billede → filside → sæt rettighedsstatus + "Må publiceres" →
      Gem → log ud → billedet er nu synligt for en besøgende.

## 6. Dokumentér

- [ ] Ny changelog-entry: "Mediehåndtering fase 1+2 — LIVE i prod (2026-07-XX)".
- [ ] Opdatér `docs/database-current-state.md` §2 (flyt fase 1/2-afsnittene fra
      "kodeklar, ikke deployet" til §2 "LIVE i prod") og §3 (fjern den forældede
      "media afbildet-gating: deny-all"-linje, hvis den ikke allerede er rettet).

---

## Hvis noget går galt

Alle ændringer i §2-3 er `CREATE OR REPLACE`/additive. For at rulle tilbage: kør den
tilsvarende blok fra `db-migrations.sql`/`db-rls.sql` som den så ud på commit `8cb8b77`
(sidste punkt før fase 1+2) — spørg Claude om at generere den tilbagerulnings-SQL, hvis
det bliver nødvendigt.
