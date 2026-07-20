# Prod-deploy runbook: mediehåndtering fase 1 + fase 2

**Formål:** aktivér filsiden (fase 1) og biblioteket (fase 2) i produktionsdatabasen.
Al app-kode er allerede live på web (Vercel deployer automatisk fra `main`) — dette
dokument dækker det udestående database-trin.

**Historik (2026-07-20):** dette dokument beskrev oprindeligt et *udklip* af kun de
medie-relaterede blokke fra `db-migrations.sql`/`db-rls.sql`, for bevidst at undgå at
tage den urelaterede "levende feed fase 3" med (story/story_kilde/feed_pin). Det udklip
ramte en skjult afhængighed: en fælles RLS-rutine (`redaktion_read`-policyen for 12
tabeller, kun én af dem — `text_mention` — er medie-relateret) refererer `haendelse`,
en tabel der viste sig OGSÅ ikke at eksistere i prod endnu ("det levende feed"s eget
DB-lag er heller aldrig deployet, selvom dets app-kode allerede kører live). Udklippet
fejlede derfor med `relation "public.haendelse" does not exist`. **Ingen data blev
ændret** — hele blokken kørte som én transaktion og blev rullet helt tilbage ved fejlen.

**Korrigeret fremgangsmåde:** kør de to filer i deres FULDE længde i stedet for udklip.
Begge filer er dokumenteret og verificeret som idempotente/additive (kun `CREATE OR
REPLACE`, `CREATE TABLE/INDEX IF NOT EXISTS`, `GRANT`, `DROP POLICY IF EXISTS` +
genoprettelse) — alle forekomster af `DELETE`/`TRUNCATE` i filerne sidder INDE I
funktions-definitioner (kører kun når en redaktør senere kalder den specifikke RPC,
ikke når migrationsfilen selv køres). At køre hele filerne er derfor både sikrere
(ingen flere skjulte afhængigheds-overraskelser) og tilfældigvis en bonus: det bringer
også "det levende feed"s DB-lag i sync med dets allerede-live app-kode.

---

## 0. Før du starter

- [ ] Du har adgang til Supabase-projektets dashboard (supabase.com → jeres projekt).
- [ ] Du har afsat ca. 15 minutter uden afbrydelse.
- [ ] Ingen andre redigerer databasen samtidig (single-editor-PoC, jf. `claude.md`).

## 1. Backup-tjek (read-only, ingen data ændres af dette trin)

Free-tier har ingen indbygget automatisk backup (`docs/database-current-state.md` §4).
I Supabase-dashboardet: **SQL Editor** → ny query → kør, og gem resultatet et sikkert sted:

```sql
select count(*) as antal_media, count(*) filter (where upload_status='klar') as klar,
       count(*) filter (where upload_status='fjernet') as fjernet
from media;

select proname from pg_proc
where proname in ('red_opdater_media','red_genopret_media','red_upload_media')
order by proname;
-- Forventet FØR migrationen: kun 'red_upload_media'.

select to_regclass('public.haendelse') as haendelse_findes;
-- Forventet FØR migrationen: NULL (tabellen findes ikke endnu).
```

Hvis I har et Supabase-abonnement med Point-in-Time Recovery (Database → Backups i
dashboardet), er det jeres reelle sikkerhedsnet — tjek at det er slået til.

## 2. Kør HELE `db-migrations.sql`

Åbn filen i rå tekst, marker alt, kopiér:
https://raw.githubusercontent.com/johanreventlow/Danmarks-Adels-Aarbog/main/db-migrations.sql

**SQL Editor** → ny query → indsæt HELE filens indhold → **Run**. Filen er lang
(~2900 linjer på commit-tidspunktet) — det er forventet og tager et øjeblik.

**Forventet resultat:** "Success. No rows returned." Ingen fejl.

## 3. Kør HELE `db-rls.sql`

Samme fremgangsmåde med:
https://raw.githubusercontent.com/johanreventlow/Danmarks-Adels-Aarbog/main/db-rls.sql

**SQL Editor** → ny query → indsæt HELE filens indhold → **Run**.

**Forventet resultat:** "Success. No rows returned." Ingen fejl. (Denne fil har allerede
kørt i prod én gang før, 2026-06-25 — den er testet idempotent.)

## 4. Verificér

```sql
-- 1) De tre medie-funktioner findes nu alle tre:
select proname from pg_proc
where proname in ('red_opdater_media','red_genopret_media','red_upload_media')
order by proname;

-- 2) Viewet kører uden fejl:
select count(*) from red_doede_links;

-- 3) text_mention har nu et grant (må ikke fejle):
select count(*) from text_mention;

-- 4) Den tidligere manglende tabel findes nu:
select count(*) from haendelse;
```

Ingen af de fire forespørgsler må returnere en fejl.

## 5. Funktionel test i appen

- [ ] Log ind som redaktør på webben → åbn en person med et billede → klik billedet →
      filsiden åbner → redigér titel → Gem → ingen fejl.
- [ ] Åbn "Medier"-fanen i redaktionen → biblioteket viser rækker med kø-chips
      (Rettigheder/Løse/Strandede/Papirkurv) i stedet for tom liste.
- [ ] Upload et upubliceret billede → filside → sæt rettighedsstatus + "Må publiceres" →
      Gem → log ud → billedet er nu synligt for en besøgende.
- [ ] (Bonus fra det udvidede scope) Tjek forsiden/feedet på webben — "det levende
      feed"s hændelsesbaserede kort bør nu også fungere, hvis de tidligere fejlede
      stille pga. den manglende `haendelse`-tabel.

## 6. Dokumentér

- [ ] Ny changelog-entry: "Mediehåndtering fase 1+2 — LIVE i prod (2026-07-XX)". Nævn
      også at "det levende feed"s DB-lag blev bragt i sync som del af samme kørsel.
- [ ] Opdatér `docs/database-current-state.md` §2 (flyt fase 1/2-afsnittene fra
      "kodeklar, ikke deployet" til §2 "LIVE i prod") og §3 (fjern den forældede
      "media afbildet-gating: deny-all"-linje).

---

## Hvis noget går galt

Begge filer er `CREATE OR REPLACE`/additive og har allerede kørt tidligere i projektets
historie uden data-tab. Skulle en bestemt funktion/policy alligevel opføre sig forkert
efter kørslen, kan netop DEN genoprettes til sin tidligere definition — spørg Claude om
at finde og generere tilbagerulnings-SQL for det specifikke objekt, fremfor at forsøge
at rulle hele filerne tilbage.
