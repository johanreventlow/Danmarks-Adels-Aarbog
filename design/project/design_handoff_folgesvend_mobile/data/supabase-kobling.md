# Reventlow-følgesvend · kobling til jeres Supabase-model

Appen er nu **koblet live** på jeres evidens-baserede base og bygger stamtræet ud fra
`person` + `family` + `family_member` (familie-nav med roller), ikke en forælder-kolonne.

## Status
- **Live-data er slået til** i `Reventlow-folgesvend.dc.html`:
  ```js
  SUPABASE = { enabled:true, url:'https://xjnvdhajfyrcytatnzos.supabase.co', anonKey:'sb_publishable_…' };
  ```
  Kun den offentlige anon-/publishable-nøgle — RLS (`web/dev-rls.sql`) styrer læseadgang.
  Den lokale Reventlow-seed bevares som offline-fallback hvis hentningen fejler.
- **Rolle-vokabular bekræftet** mod `web/src/relations.ts`:
  ```js
  SCHEMA = { parentRoles: ['partner'], childRoles: ['barn'] };
  ```
  En person er `'partner'` i sin egen union og `'barn'` i sin fødselsfamilie. Kun `'barn'`
  er blodslægtskab; `adopteret_barn` / `plejebarn` / `stedbarn` kan tilføjes til træet senere.

## Felt-mapping (jeres model → app)
| App | Kilde |
|-----|-------|
| Navn | `person.visning_navn` |
| Leveår | `person.visning_foedt` / `visning_doed` (vises ordret: `* 1640`, `† 1708`, intervaller, floruit) |
| Titel | `person.visning_titel` |
| Biografi | `narrative.tekst` hvor `subjekt_type='person'` (ikke-privat) |
| Forælder ↔ barn | `family_member` grupperet pr. `family_id`; `partner`×`barn` |
| Ægtefæller | de to `partner`-roller i samme `family` |
| Privat | `person.privat` / `narrative.privat` respekteres (skjules) |

Hvert barn har typisk to forælder-kanter (begge partnere). Appen indekserer børn pr. forælder,
så et barn optræder under begge forældre; den første partner bruges som primær linje opad.

## Endnu ikke wired (klar når I vil)
- **Medier**: `media`-tabellen er tom og endnu ikke linket til personer. Loaderen henter den og
  viser billeder automatisk så snart medie-objekter knyttes (forventet via `relation`
  `objekt_type='media'`, rolle fx `afbildet`/`fører våben`). Indtil da vises en tom-tilstand.
- **Fuld evidens**: `fact → conclusion → assertion → citation` kan vises som "blåstemplet værdi
  + alternative påstande" på persondetaljen (`queries.ts` viser opslaget). `citation` er pt. tom.

## Nu wired mod live-data
- **Forside = slægts-portal**: slægts-vælger (Reventlow aktiv; Bardenfleth/Ahlefeldt-Laurvig/Scheel
  som "ikke tilføjet"), live-tællere (personer/linjer/godser), og indgang til alle sektioner.
- **Stamtræ**: `person` + `family` + `family_member` (`partner`/`barn`). **Linje-vælger** (grene I–V)
  filtrerer via `person_external_id.linje` og hopper fokus til linjens stamfader (laveste `nr`).
- **Persondetalje**:
  - **Biografi** fra `narrative` (klampet med "Læs hele biografien").
  - **Embeder, rang & hverv** fra `relation` → `organisation` (med `periode_raw`).
  - **Godser & besiddelser** fra `relation` → `estate` (rolle `ejer`, med periode).
  - **Kilder i Aarbogen** fra `person_external_id` → `source`: trykt værk + "Linje X, nr. N".
  - **Materiale** fra `media` (tom-tilstand indtil medier linkes).
- **Om slægten**: læseskærm til historisk indledning (`narrative subjekt_type='slaegt'` — placeholder indtil data).
- **Godser & ejendomme**: oversigt (169 godser med ejere) + gods-detalje med **ægte ejer-tidslinje** fra `relation`.
- **Slægtens våben**: autoriseret våben + galleri af varianter/segl (`coat_of_arms` + `media` via `relation`-roller).
- **Slægtskab** og **søgning** kører på samme model.

## "Mig"-funktion (brugerens egen plads)
Brugeren kan markere sin egen person i træet via **"Det er mig i slægten"** på persondetaljen.
- Gemmes pt. i `localStorage` (`daa_me_id`) — POC uden login.
- Forsiden viser et **"Din plads i slægten"**-kort; slægtskab har en genvej **"Sæt mig som første person"**.
- I produktion flyttes dette til **`profiles.reventlow_person_id`** (skemaet har feltet), så "mig"
  følger brugerens konto og kan styre medlem/forsker-gaten.

## Bemærkninger
- Person-id er `bigint`; adapteren konverterer til streng internt.
- Slægtskabsfinderen tracer pt. den primære forælder-linje (tilstrækkeligt til søskende/aner og
  de fleste fætter/kusine-tilfælde); fuld to-forælder-LCA kan tilføjes.
- PostgREST returnerer **max 1000 rækker pr. svar** uanset `limit` — appen sideinddeler derfor
  alle hentninger med `offset` (vigtigt: uden dette manglede alle familier/relationer efter de
  første 1000 rækker, så fx nyere personers forældre/ægtefælle/børn ikke blev forbundet).
- For at slå live fra igen: sæt `SUPABASE.enabled = false` (falder tilbage til lokal seed).
