# Evidenslag: #154 og #155 — design

## Formål og afgrænsning

Luk de konkrete rettigheds-, integritets- og CI-huller i issue #154 og #155,
uden produktionsadgang, datamigrering eller ændring af den igangværende
narrativmodel i #152. Arbejdet sker på en ny gren fra `main` og skal kunne
køres mod en helt frisk, disponibel PostgreSQL 17-database.

## Beslutning: default privileges (#154)

Den eksisterende globale `ALTER DEFAULT PRIVILEGES ... REVOKE EXECUTE ON
FUNCTIONS` bevares. PostgreSQLs implicitte `PUBLIC EXECUTE` er ikke
schema-lokal; kun en global revoke sikrer, at en ny privat funktion ikke bliver
kaldbare ved et senere `USAGE`-grant. Konsekvensen for `public.red_*` er
bevidst: hver klientvendt RPC skal få sin grant eksplicit.

`db-verify.sql` skal have en katalogbaseret kontrakt, som:

- opretter en syntetisk `public.red_*`-funktion efter RLS-laget og beviser, at
  hverken `anon` eller `authenticated` kan kalde den før eksplicit grant;
- beviser, at samme funktion kan kaldes som `authenticated` efter den
  eksplicitte grant, mens `anon` fortsat nægtes;
- verificerer hver eksisterende `public.red_*`-overload mod en eksplicit,
  versionsstyret rollepolitik: klient-RPC'er har `authenticated` og aldrig
  `PUBLIC`/`anon`; service-role-only autorisationer har alene `service_role`.

Den eksplicitte rollepolitik er testens eneste allowlist og skal opdateres i
samme ændring som en ny `public.red_*`-funktion. Den dækker også
`SECURITY DEFINER`-funktioner: adgangskontrollen må ikke afhænge af funktionens
security-attribut. Testen kontrollerer de faktiske katalog-ACL'er, ikke blot
at en repræsentativ RPC virker. Default-privilege-beviset afgrænses til den
normale deploy-ejer; en anden funktions-ejer kræver sin egen tilsvarende
default-privilege-konfiguration og må ikke fremstilles som dækket af denne
test.

## Evidensintegritet (#155)

De 11 oprindelige append-only evidenstabeller — fra `extraction_run` til
`source_persona_mention` — har allerede `BEFORE UPDATE OR DELETE`-row-triggere.
De får desuden en `BEFORE TRUNCATE`-statement-trigger med den eksisterende
fail-closed fejlkontrakt. Begge triggerklasser installeres eksplicit pr. tabel
i clean-slate- og migrationsvejen. Testen kontrollerer, at alle triggere er
aktiveret, at `TRUNCATE` rulles tilbage, og at efterfølgende test-fixtures
fortsat kan indsættes.

Kildeankre skal fastholde forbuddet mod tavs genankring i databasen: en
accepted anchor forbliver knyttet til sin `source_record_id`; en accepted
split-/merge-/replacement-revision må ikke fungere som en implicit flytning
til successor-recorden. Den nye revision-trigger låser begge records i stabil
orden og afviser en accepted revision, når successor-recorden allerede er
current accepted anchor for en occurrence. Dermed er successor'en ved accept
en ny, endnu uforankret logisk record, sådan som anchor-kontrakten kræver.
Revisionen ændrer aldrig selv anchors. En særskilt, versionskorrekt
anchor-afgørelse — først en ny `rejected` version af den gamle anchor og
derefter en accepted anchor til successor'en — er den eneste
supersessionsvej. Testene beviser både afvisningen og denne eksplicitte
re-anchoring-vej samt bevarer almindelige ikke-konfliktende revision-events.

`red_decide_interpretation` må kun afgøre den aktuelle `proposed`-version. Et
forsøg på at afgøre en allerede `accepted`, `rejected`, `unresolved` eller
`superseded` fortolkning skal give en domænefejl og oprette ingen ny version.
Version-, status- og låseadfærd testes som en tilstandsmaskine, herunder en
dblink-konkurrencetest, så to redaktører ikke begge kan afgøre samme proposal.

JSON-kontrakterne bliver testbare metadata fremfor ukontrolleret dokumentation:
`interpretation-schema.json` udvides til DB'ens tilladte statusværdier, og en
Python-kontrakttest sammenligner den lukkede enum med schema-DDL. Testen
assert'er desuden, at begge schemafiler har det deklarerede JSON-Schema-format
og kan indlæses af den eksisterende test-afhængighed.

## CI og migrationskontrakt

CI's eksisterende PostgreSQL 17-job udvides, frem for at skabe en delvist
overlappende database. Rækkefølgen er:

1. bootstrap af Supabase-shims;
2. en versionsfast migrationsbaseline, der repræsenterer den allerede
   udrullede evidens-model før #154/#155;
3. `db-migrations.sql` to gange på denne baseline og kontraktassertioner mod
   den migrerede database;
4. en separat clean-slate-database med `schema.sql`, `db-rls.sql` og
   `db-migrations.sql` to gange;
5. den eksisterende smalle evidenskontrakt og
   `tests/sql/run-db-verify-disposable.sql` med eksplicitte lokale
   PG-parametre, så dblink bruger samme database.

Den fulde `db-verify`-kørsel må alene ske i servicecontaineren; den må aldrig
ændre production eller en delt lokal database.

## Dokumentation

`docs/database-current-state.md` beskriver, at public `red_*`-funktioner får
eksplicitte grants efter global default revoke, og at DDL og den relevante
rolle-grant skal afvikles som én transactionel deployment. En kort driftspost
angiver den obligatoriske deployrækkefølge og den CI-kontrollerede
migrations-/verify-gate. Ingen prod-tal opdateres, fordi denne opgave ikke
udfører en prod-afstemning.

## Acceptkriterier

- En frisk database og en versionsfast migreret baseline har samme
  #154/#155-kontrakter.
- Alle negative SQL-cases fejler med forventede domænefejl, og positive cases
  bevarer tidligere legitim append-only adfærd.
- CI udfører migrerings-idempotens og den komplette disponerbare `db-verify`.
- Fokus- og relevante fulde testpakker er grønne, og ændringen består et
  selvreview og en uafhængig skrivebeskyttet review.
