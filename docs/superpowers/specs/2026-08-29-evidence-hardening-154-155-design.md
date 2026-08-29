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
  den ikke kan kaldes som `authenticated` før eksplicit grant;
- beviser, at samme funktion kan kaldes efter den eksplicitte grant;
- fejler med funktionsidentiteter, hvis en eksisterende `public.red_*`-funktion
  mangler `EXECUTE` for `authenticated`.

Dette gælder kun redaktionens klient-RPC-navnerum. Offentlige helpers og
service-role-only entry points er ikke implicitte authenticated-RPC'er.

## Evidensintegritet (#155)

De 11 oprindelige append-only evidenstabeller — fra `extraction_run` til
`source_persona_mention` — skal også få en `BEFORE TRUNCATE`-trigger, der
bruger den eksisterende fail-closed fejlkontrakt. Triggeren er eksplicit pr.
tabel og installeres både i clean-slate- og migrationsvejen. En test skal
bevise, at en `TRUNCATE` rulles tilbage og at efterfølgende test-fixtures
fortsat kan indsættes.

Kildeankre skal fastholde forbuddet mod tavs genankring i databasen: en
accepted anchor må ikke flyttes til en anden record alene ved at indsætte en
split-/merge-revision. Den nye trigger validerer den berørte occurrence- og
record-mængde under lås og afviser kun den konflikt, der ville ændre en
eksisterende accepted anchors betydning uden en særskilt anchor-afgørelse.
Almindelige, ikke-konfliktende revision-events og append-only versionering
bevares.

`red_decide_interpretation` må kun afgøre den aktuelle `proposed`-version. Et
forsøg på at afgøre en allerede `accepted`, `rejected`, `unresolved` eller
`superseded` fortolkning skal give en domænefejl og oprette ingen ny version.

JSON-kontrakterne bliver testbare metadata fremfor ukontrolleret dokumentation:
`interpretation-schema.json` udvides til DB'ens tilladte statusværdier, og en
Python-kontrakttest sammenligner den lukkede enum med schema-DDL. Testen
assert'er desuden, at begge schemafiler har det deklarerede JSON-Schema-format
og kan indlæses af den eksisterende test-afhængighed.

## CI og migrationskontrakt

CI's eksisterende PostgreSQL 17-job udvides, frem for at skabe en delvist
overlappende database. Rækkefølgen er:

1. bootstrap af Supabase-shims;
2. `schema.sql` og `db-rls.sql`;
3. `db-migrations.sql` to gange for idempotens;
4. den eksisterende smalle evidenskontrakt;
5. `tests/sql/run-db-verify-disposable.sql` med eksplicitte lokale PG-parametre,
   så dblink bruger samme database.

Den fulde `db-verify`-kørsel må alene ske i servicecontaineren; den må aldrig
ændre production eller en delt lokal database.

## Dokumentation

`docs/database-current-state.md` beskriver, at public `red_*`-funktioner får
eksplicitte grants efter global default revoke. En kort driftspost angiver den
obligatoriske deployrækkefølge og den CI-kontrollerede migrations-/verify-gate.
Ingen prod-tal opdateres, fordi denne opgave ikke udfører en prod-afstemning.

## Acceptkriterier

- En frisk database og en migreret database har samme #154/#155-kontrakter.
- Alle negative SQL-cases fejler med forventede domænefejl, og positive cases
  bevarer tidligere legitim append-only adfærd.
- CI udfører migrerings-idempotens og den komplette disponerbare `db-verify`.
- Fokus- og relevante fulde testpakker er grønne, og ændringen består et
  selvreview og en uafhængig skrivebeskyttet review.
