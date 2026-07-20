# Prod-runbook: mediehåndtering fase 3 — hygiejne

> **Status: IKKE UDFØRT.** Dette dokument er et gated håndoff; ingen database-,
> Storage-, web- eller mobilændring er udført i produktion som del af fase 3.

## Scope og stopbetingelser

Fase 1+2 og `db-rls.sql` er allerede live. Deploy derfor **kun** den navngivne blok
`mediehaandtering_fase3_hygiejne` fra `db-migrations.sql` — ikke hele migrationsfilen,
som også indeholder uafhængige funktioner. Blokken starter ved sin daterede overskrift
og slutter efter `red_relation`-definitionen, umiddelbart før overskriften for levende
feed fase 3.

Stop uden ændringer hvis:

- der ikke foreligger en frisk, gendannelig backup af de berørte tabeller;
- en eksisterende `afbildet`-dublet bærer assertion, conclusion eller note og derfor
  får `relation_afbildet_uidx` til at fejle;
- den udtrukne SQL-blok ikke er byte-for-byte afstemt med den godkendte commit;
- brugeren ikke eksplicit har godkendt prod-vinduet.

## 1. Backup og preflight

1. Lås commit og projekt-id; bekræft at målet er produktion og at ingen anden redaktør
   skriver samtidigt.
2. Tag en read-only, gendannelig backup af mindst `media`, `relation`, `assertion`,
   `conclusion`, `note`, `haendelse`, `change_set` og `change_event`. Gem checksum,
   rækkeantal og restore-kommando uden credentials i deployloggen.
3. Registrér før-tilstanden: antal `media` med/uden `created_at`, identiske
   `afbildet`-grupper samt eventuel evidens på hver højere relations-id. Afgør
   evidensbærende grupper manuelt; migrationen må ikke bruges til at slette evidens.
4. Rehearsal den præcise scoped blok mod en lokal restore. Kør blokken to gange og
   bekræft at historiske media-rækker beholder `created_at IS NULL`, mens nye får
   default, og at fresh-/migrationsoverfladen er identisk.

## 2. Scoped database-deploy

Kør alene `mediehaandtering_fase3_hygiejne` i én atomisk transaktion. Blokken:

- tilføjer `media.created_at` i to trin;
- fjerner kun evidensfri, identiske `afbildet`-dubletter;
- opretter `relation_afbildet_uidx` på
  `(subjekt_type, subjekt_id, objekt_type, objekt_id) WHERE rolle='afbildet'`;
- erstatter den eksisterende `red_relation`-signatur med constraint-specifik
  håndtering af netop dette index.

`db-rls.sql` skal ikke deployes for fase 3; filen er uændret. Der må heller ikke køres
nogen migration eller omdøbning af gamle Storage-stier.

## 3. Database-verifikation før app-deploy

1. Kør hele `db-verify-media.sql`.
2. Kør Task 1-blokkene i `db-verify.sql`: media fase 1/3 upload- og relationsasserts
   samt kontrollen af at fremmede unique constraints genkastes uændret.
3. Assertér direkte i kataloget:
   - `media.created_at` er NULL-bar `timestamptz` med default `now()`;
   - `relation_afbildet_uidx` har præcis fire nøglekolonner og partial-predikatet;
   - `red_relation(text,bigint,text,bigint,text,text)` er den forventede definition.
4. Kør Supabase security advisors (`get_advisors(security)`). Sammenlign med den kendte
   baseline; nye fund stopper deployet, mens kendte SECURITY DEFINER-/deny-all-mønstre
   dokumenteres uden at blive kaldt nye regressionsfund.

## 4. App-deploy og røgtest

Deploy web fra den godkendte commit. Byg og distribuér nye mobile dev-/release-builds:
`expo-crypto` er et nyt native SDK 56-modul, så en JavaScript-only opdatering er ikke
tilstrækkelig.

Kør derefter med en redaktørkonto:

- samme webfil to gange → preflight → tilknyt eksisterende;
- afbrudt upload → færdiggør uden ny række eller nyt objekt;
- samme motiv fra web og mobil → to rækker som kendt genkoder-begrænsning → begge i
  "Mulige dubletter" → blød flet flytter relationer og parkerer kopien;
- HEIC på web giver fortsat den eksplicitte mobile-henvisning.

## 5. Janitor — separat destruktiv gate

Første prod-kørsel er **kun rapport**:

```bash
Rscript R/media-janitor.R
```

Gem CSV'en, kontrollér at rækker med ukendt alder eller evidens aldrig er sletbare, og
gennemgå rapporten med brugeren. Kør hverken `--slet` eller `--backfill-sha` uden en ny,
eksplicit godkendelse baseret på den konkrete rapport. Ved en senere godkendt
`--slet`-kørsel er standardfristen 7 dage; tag en ny backup og gem både før-rapporten
og resultaterne. En Storage-fejl efter DB-commit behandles som et eksplicit retry-fund,
ikke som skjult succes.

## 6. Lukning

Dokumentér commit, backup, SQL-checksum, assert-output, advisor-diff, app-build-id'er og
janitorrapport. Opdatér først `docs/database-current-state.md` fra "ikke live" til
"live", når alle godkendte prod-trin faktisk er udført og verificeret.
