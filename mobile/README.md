# Følgesvend — mobil-app (React Native / Expo)

Mobil-appen til **Danmarks Adels Aarbog-følgesvenden** (PoC: familien Reventlow). Samme
Supabase-backend som `../web/`. To publikummer i én app:

- **Publikum** (anon / medlem): browse personer, slægter, godser, våben — og
  slægtskabsfinderen *"er vi i familie?"*.
- **Redaktør** (login → `redaktion`-rolle): redigér oplysninger gennem en
  dry-run → LIVE-gate, redaktionel ændringshistorik med fortryd, og `[[type:id|tekst]]`-
  hyperlinks i fri-tekst-narrativer.

> **Datamodel & backend-status:** se [`../docs/database-current-state.md`](../docs/database-current-state.md)
> og [`../datamodel-oversigt.md`](../datamodel-oversigt.md). Invarianterne i
> [`../CLAUDE.md`](../CLAUDE.md) §3 (evidens før konklusion, cache-felter regenereres,
> GDPR via `person.levende`) gælder også her.

---

## Kom i gang

```bash
npm install
npm start          # expo start — vælg iOS / Android / web i outputtet
```

Andre scripts (`package.json`):

| Script | Gør |
|---|---|
| `npm start` | Expo dev-server |
| `npm run ios` / `npm run android` | Byg + kør på simulator/emulator/device |
| `npm run web` | Kør som web (react-native-web) |
| `npm run lint` | `expo lint` (ESLint) |
| `npm test` | Jest (rene funktioner, mappere, datalag — ikke render/interaktion) |

---

## Miljøvariabler

Supabase-nøgler er **ikke** hardcoded. Sæt dem i `mobile/.env` (git-ignoreret) med
`EXPO_PUBLIC_`-prefix, så de eksponeres i klient-bundlen:

```
EXPO_PUBLIC_SUPABASE_URL=https://<projekt>.supabase.co
EXPO_PUBLIC_SUPABASE_ANON_KEY=<anon-nøgle>
```

Mangler de, falder appen tilbage på et **offline-seed** (se `src/lib/supabase.ts`) — nyttigt
til UI-arbejde uden netværk, men uden live-data. Brug **anon-nøglen**, ikke service-role:
RLS sørger for at anon kun ser afdøde ikke-private personer (GDPR — se
`database-current-state.md` §2).

---

## Struktur (`src/`)

| Mappe | Indhold |
|---|---|
| `app/` | Expo Router (file-based routing): `(tabs)`, `person/`, `estate(s)`, `redaktion/`, `arms`, `about`. |
| `data/` | Datalag mod Supabase — bl.a. `relationship.ts` (bilineal slægtskabsfinder m. konfidens på stien). |
| `lib/` | `supabase.ts` (klient + offline-seed), `mentions.ts` (`[[type:id\|tekst]]`-token-parser/encoder), auth. |
| `store/` | Zustand-state (redaktion-write-flow m.m.). |
| `components/` | UI, bl.a. `NarrativRenderer` (klikbare hyperlinks) + `MentionPicker` (@-vælger). |
| `theme/` | Typografi/farver. |

---

## Supabase-kontrakt

- **Læsning:** direkte via `@supabase/supabase-js` (PostgREST), gated af RLS. Paginér med
  `.range()` — basen har >1000 rækker (default-loft er 1000).
- **Skrivning (kun redaktør):** går gennem `red_*`-RPC'er (SECURITY DEFINER, rolle-gated),
  aldrig direkte table-writes. Hver skrivning åbner et fortryd-bart `change_set`. Se
  redaktions-flowet i `store/` + `SkrivePreviewSheet` (dry-run → LIVE).

---

## Fejlsøgning

| Symptom | Sandsynlig årsag |
|---|---|
| Ingen data / kun seed-personer | `.env` mangler eller forkert nøgle → offline-seed-fallback. |
| Tom liste selvom base har rækker | RLS: anon ser kun afdøde ikke-private. Log ind som redaktør for at se levende/private. |
| Kun 1000 rækker hentet | Manglende `.range()`-paginering. |
| Skrivning fejler med rolle-fejl | Bruger er ikke `redaktion` i `profiles`. |
| Expo-API opfører sig uventet | Expo v56 har breaking changes — læs `https://docs.expo.dev/versions/v56.0.0/` (jf. `AGENTS.md`). |

---

## Bemærk

Expo **v56** har brud ift. tidligere versioner. Læs de versionerede docs
(`https://docs.expo.dev/versions/v56.0.0/`) før du skriver kode — se `AGENTS.md`.
