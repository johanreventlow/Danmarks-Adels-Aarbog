# Redaktions-UI — vertikal kerne-skive (design/spec)

**Dato:** 2026-06-27
**Status:** Godkendt design — klar til implementeringsplan
**Branch:** `feat/folgesvend-mobile`
**Forudsætning:** Skrive-model + auth-DB-laget er IMPLEMENTERET og **deployet live**
(verificeret 2026-06-27, se §0). Bygger ovenpå
`docs/superpowers/specs/2026-06-26-redaktion-skrive-model-auth-design.md`.

Denne spec dækker **UI-skærmene** (spec 2026-06-26 §13 non-goal) som en **vertikal
kerne-skive**: dashboard + person-editor (kernen) + konto + de tre kritiske sheets.
Entitetslister, generisk record-editor og opret-flow er udskudt til plan 2.

---

## 0. Verificeret udgangspunkt (live-base, 2026-06-27)

REST-probe mod produktions-Supabase bekræfter at DB-laget fra spec 2026-06-26 ER deployet:

- `profiles` + `suggestion` eksisterer (200, ikke PGRST205).
- `current_rolle()` → `"medlem"` for anon.
- Evidens-tabeller `fact`/`assertion`/`conclusion`/`citation` læsbare (rigtige rækker, ikke seed).
- `red_set_koen(p_person_id, p_koen)` med korrekte params → `P0001 "Kun redaktion"`
  = rolle-gating LIVE. Hele `red_*`-RPC-suiten deployet.

**Konsekvens:** plan 1 kan være ægte end-to-end (rigtigt login + rigtige RPC-writes),
ikke kun dry-run/seed-fallback. **Forbehold:** ingen `redaktion`-profil er seedet endnu
(auth.users + `profiles.rolle='redaktion'`); uden den er kun dry-run + medlem-staging
(`red_suggest`) testbart for happy-path-writes. Manuelt dashboard-step — noteres i planen.

---

## 1. Besluttede valg (denne spec)

| Beslutning | Valg | Note |
|---|---|---|
| Plan 1-omfang | **Vertikal kerne-skive** | Dashboard + person-editor + konto + 3 sheets. |
| Navigation | **Native `(red-tabs)` Tabs-gruppe** | Konsistent m. publikums-`(tabs)`. "Tilføj"-fane intercepter → sheet. |
| Editor-dybde | **Kerne-fakta + narrativ skrivbar; relationer/sektioner read-only** | Familie/godser/hverv/kilder/våben vises, men redigering udskudt til plan 2. |
| Konflikt-kø | **Lille DB-view (`red_konflikt`) + UI-kø** | Telefonen henter ikke 925 personers evidens; "uenig" = >1 *distinkt værdi*. |

---

## 2. Navigation

Nyt segment under `mobile/src/app/`, parallelt med urørt publikums-`(tabs)`:

```
src/app/
  (tabs)/                    publikum (urørt)
  redaktion/
    _layout.tsx              Stack, headerShown:false
    (red-tabs)/
      _layout.tsx            Tabs (Oversigt · Entiteter · Tilføj · Konto)
      index.tsx              dashboard
      entiteter.tsx          STUB (plan 2) — tom-tilstand "kommer snart"
      konto.tsx              login / dry-run / vis-forklaringer / logout
    person/[id].tsx          push UDEN for tabs (fuld editor-skærm)
```

- **"Tilføj"-fane:** `screenListeners.tabPress` → `e.preventDefault()` → åbner opret-sheet.
  Plan 1: sheet er stub ("kommer snart"); opret-flowet selv = plan 2.
- **Tab-bar-styling:** native `Tabs` med tilpasset `tabBarStyle`/`tabBarActiveTintColor`
  mod prototypens mørke look (tokens i §8). Glyph-ikoner via `@expo/vector-icons` (Ionicons)
  eller Unicode-tekst (handoff §Assets).
- **Indgang publikum → redaktion:** udskudt/skjult i PoC; `redaktion/`-ruten nås direkte.

---

## 3. Data — evidens-læsning (nyt lag)

Det eksisterende `data/load.ts` henter kun det **flade cache** (`person.visning_*`, `koen`,
`privat`) + strukturtabeller. Evidens-laget (`fact`/`assertion`/`conclusion`/`citation`)
læses IKKE i dag. Person-editoren ER en evidens-visning → nyt read-lag kræves.

**Ny fil `mobile/src/data/redaktionRead.ts`:**

`fetchPersonEvidence(personId): Promise<PersonEvidence>` — **N separate queries + klient-side
join.** Kun de **polymorfe fact-links** blokerer nesting: `assertion.target_type/target_id` og
`conclusion.target_type/target_id` peger på `fact` UDEN rigtig FK, så et nested-select fra
`fact` ned i assertion 400'er. `citation → source` HAR derimod rigtige FK'er og kan nested-
selectes. Derfor:

1. `fact?subjekt_type=eq.person&subjekt_id=eq.{id}` → `factIds`, faktatype pr. fact.
2. `assertion?target_type=eq.fact&target_id=in.({factIds})` → værdier + fuzzy-datoer.
3. `conclusion?target_type=eq.fact&target_id=in.({factIds})` → `valgt_assertion_id` pr. fact.
4. `citation?assertion_id=in.({assertionIds})&select=*,source(slags,titel,udgave)` → kilder
   pr. oplysning (nested source via FK). **Bemærk:** én assertion kan have FLERE citations
   (ingen `UNIQUE(assertion_id)`), så kilder modelleres som liste, ikke ét felt.

Samles til (kolonner matcher faktisk schema — `citation` har `side, citat_tekst, citat_dato`;
`source` har `slags, titel, udgave`; der findes INGEN `forfatter`-kolonne):
```ts
type Kilde = {
  sourceId: number | null;
  sourceTitel?: string;       // source.titel
  side?: string;              // citation.side
  citatTekst?: string;        // citation.citat_tekst
  citatDato?: string;         // citation.citat_dato
};
type FeltEvidens = {
  felt: string;                 // navn|foedt|doed|titel  (koen særskilt, §4)
  faktatype: string;
  factId: number;
  konklusionAssertionId: number | null;
  oplysninger: {
    assertionId: number;
    vaerdi: string;
    dato?: { min, max, qualifier, raw };
    kilder: Kilde[];            // 0..n citations pr. assertion
    erKonklusion: boolean;
  }[];
  uenig: boolean;               // >1 distinkt værdi
};
type PersonEvidence = { felter: Record<string, FeltEvidens>; koen: string | null };
```

`koen` læses fra `person.koen` (arbejdsværdi, ikke et fact — datamodel §2). Header bruger
allerede-loadede `person.visning_*` fra model; evidens hentes kun on-demand når editor åbnes.

---

## 4. Felt → faktatype (genbrug fra skrive-laget)

Samme map som `redaktionWrite.ts FELT_FAKTATYPE`:

| UI-felt | Model |
|---|---|
| `navn`  | `fact.faktatype='navn'` → assertion.vaerdi_tekst |
| `foedt` | `fact.faktatype='fødsel'` → assertion (dato-felter) |
| `doed`  | `fact.faktatype='død'` → assertion (dato-felter) |
| `titel` | `fact.faktatype='titel'` → assertion.vaerdi_tekst |
| `koen`  | **IKKE et fact** — direkte `person.koen` → `red_set_koen` |

---

## 5. Konflikt-kø — lille additiv DB

Nyt view i `db-migrations.sql` (idempotent) + `schema.sql` (source of truth):

```sql
create or replace view red_konflikt
  with (security_invoker = true) as          -- KRITISK: ellers kører viewet som ejer
select f.subjekt_id   as person_id,          -- og omgår RLS → lækker private personers facts
       f.faktatype,
       count(distinct a.vaerdi_tekst) as antal_vaerdier,
       count(*)                       as antal_oplysninger
from fact f
join assertion a
  on a.target_type = 'fact' and a.target_id = f.id
where f.subjekt_type = 'person'
  and f.faktatype in ('navn','titel')        -- v1: kun tekst-felter (se dato-note)
group by f.subjekt_id, f.faktatype
having count(distinct a.vaerdi_tekst) > 1;
```

- "uenig" = **>1 distinkt værdi** (samme værdi fra to kilder = bekræftelse, ikke konflikt).
- **`security_invoker = true` er obligatorisk** (Codex-review, høj): et alm. PostgreSQL-view
  kører ellers med ejer-rettigheder og **omgår RLS** på `fact`/`assertion` → lækker private
  personers konflikter. Med `security_invoker` arver viewet kalderens RLS. Verificér eksplicit
  at private personer IKKE returneres. `grant select on red_konflikt to authenticated`.
- **Dato-felter (fødsel/død) udeladt af konflikt-kø i plan 1** (Codex-review, medium):
  `vaerdi_tekst` er typisk tom for dato-fakta, så `distinct vaerdi_tekst` ville give 0 og misse
  reelle dato-konflikter — værre end at udelade dem ærligt. Plan 1 lover derfor kun konflikt-
  detektion på `navn`/`titel`. Dato-konflikt (kanonisk sammenligning af `date_min/max/raw`)
  = plan 2. §6.2-editoren viser stadig flere dato-oplysninger pr. person; kun dashboard-køen
  er afgrænset.

---

## 6. Skærme (plan 1)

### 6.1 Dashboard — `redaktion/(red-tabs)/index.tsx`
- Hero (mono-kicker + serif-titel "Redaktion").
- Rolle/skrivemode-kort: avatar + e-mail + rolle (logget ind) / "Log ind for at redigere"
  (ikke logget ind, → login-sheet); divider; **dry-run-toggle** (LIVE rød / Dry-run lys).
- **"Til gennemsyn"-kø:** rækker fra `red_konflikt` (person-navn + felt-tag + "uenige kilder")
  → tap åbner `person/[id]` med det felt foldet ud.
- Entitets-grid: tællere fra model (person/familie/godser/kilder/…); tap → stub-liste (plan 2).

### 6.2 Person-editor — `redaktion/person/[id].tsx` ★
- Header: avatar + navn (`visning_navn`) + meta-chips (år, køn, id).
- Handlinger: **Privat**-toggle (`red_set_privat`) + **Slet**-knap (→ slet-sheet).
  **RLS-afhængighed (Codex-review, høj):** den nuværende `auth_read`-policy på `person`/`fact`
  skjuler private rækker for ALLE authenticated — også redaktøren. Sætter redaktøren
  `privat=true`, forsvinder personen ved næste re-fetch og kan ikke ophæves via UI. Plan 1
  SKAL derfor tilføje en redaktion-specifik read-policy (`current_rolle()='redaktion'` ser også
  private person/personbundne rækker) i `db-rls.sql`. Se §8b.
- Evidens-note (kun hvis `showAnnotations`).
- **Kerne-fakta** (5 kort: navn/foedt/doed/koen/titel), drevet af `fetchPersonEvidence`:
  - Sammenklappet: feltlabel + konklusionsværdi + kilde + "uenige"-tag + "N oplysn." + chevron.
  - Udfoldet: pr. oplysning — værdi + status (konklusion/oplysning) + kilde + meta;
    handlinger **Gør til konklusion** (`red_set_konklusion`), **✎ redigér**
    (`red_edit_oplysning`), **🗑 slet** (`red_slet_oplysning`). **+ Tilføj oplysning**
    (`red_upsert_fakta`). `koen` → `red_set_koen`.
- **Narrativ · biografi:** `TextInput` (multiline) → `red_upsert_narrativ` (**skrivbar**).
  **Kilde-felt udeladt i plan 1** (Codex-review, medium): `red_upsert_narrativ` tager kun
  `(subjekt_type, subjekt_id, tekst, privat)` — ingen `source_id`/`side`, selvom `narrative`-
  tabellen har dem. Et kilde-felt ville blive tabt stille. Plan 1 redigerer kun teksten; kilde-
  binding på narrativ kræver RPC-udvidelse (`source_id`/`side`) → plan 2.
- **Familie & relationer** + **sektioner** (hverv/godser/kilder/våben): **read-only display**
  fra eksisterende model-selectors; redigering = plan 2.

### 6.3 Konto — `redaktion/(red-tabs)/konto.tsx`
- Logget ind: profil-kort (avatar + e-mail + rolle), to toggles (dry-run, vis-forklaringer),
  Log ud (`signOut`).
- Ikke logget ind: mørkt promo-kort + "Log ind"-knap (→ login-sheet) + forklarings-toggle.

---

## 7. Sheets (plan 1)

Modal/overlay-komponenter (slide-op). Plan 1 leverer de tre kritiske:

- **Login:** e-mail + adgangskode + fejltekst + "Log ind". Bruger `lib/auth.ts signIn`
  (`supabase.auth.signInWithPassword` + `profiles`-opslag; session persisteres via
  AsyncStorage). Efter login: `hydrateAuth` opdaterer Zustand-slice.
- **Skrive-preview:** dry-run viser `{fn, args}` pr. kald (genbrug `describeCall`); LIVE
  kalder RPC'en (`submitChange`) og viser resultat / fejltekst.
- **Slet-bekræft:** relations-advarsel (hvilke kanter brydes) + acknowledge-checkbox →
  låser rød "Slet endeligt"-knap op → `red_slet_person`.
  **Komplet cascade-advarsel (Codex-review, høj):** `red_slet_person` sletter relationer hvor
  personen er subjekt **ELLER** objekt, men `load.ts` henter kun `subjekt_type='person'`-
  relationer → modellen kender ikke INDGÅENDE kanter, så advarslen underrapporterer destruktive
  konsekvenser. Plan 1 SKAL hente begge retninger til advarslen — enten via en udvidet
  relations-fetch (subjekt OR objekt) eller en dry-run-RPC der returnerer den fulde cascade-
  liste. Sidstnævnte er mest robust (matcher RPC'ens faktiske slette-logik 1:1).

**Opret-sheet** (fra "Tilføj"-fane) = stub i plan 1.

---

## 8. Write-wiring — udvid `data/redaktionWrite.ts`

RPC'erne er deployet live; kun TS-laget er create-only nu (`buildRpcCall` mapper kun
`koen/fakta/narrativ/relation`). Tilføj `buildRpcCall`-cases:

| `art` / handling | RPC | Rolle |
|---|---|---|
| redigér oplysning | `red_edit_oplysning(assertion_id, vaerdi, kilde…)` | redaktion |
| slet oplysning | `red_slet_oplysning(assertion_id)` | redaktion |
| gør til konklusion | `red_set_konklusion(assertion_id)` | redaktion |
| sæt privat | `red_set_privat(person_id, privat)` | redaktion |
| slet person | `red_slet_person(person_id)` | redaktion |
| (medlem alt) | `red_suggest(...)` | medlem → staging |

Rolle (`store.rolle`) styrer hvilke handlinger UI viser: `medlem` ser kun forslag-flow.

---

## 8b. DB-ændringer påkrævet i plan 1 (ikke kun UI)

Codex-review afslørede at plan 1 IKKE er rent UI — tre små, additive DB-ændringer kræves
(idempotent i `db-migrations.sql`/`db-rls.sql`; `schema.sql` opdateres som source of truth):

1. **`red_konflikt`-view** med `security_invoker = true` + `grant select … to authenticated`
   (§5). Uden security_invoker = GDPR-læk af private personers konflikter.
2. **Redaktion-read-policy** på `person` + personbundne tabeller (`fact`, `person_external_id`,
   `family_member`, `narrative`, `note`, `relation`, `assertion`, `conclusion`, `citation`):
   `current_rolle()='redaktion'` ser også private rækker. Ellers låser privat-toggle redaktøren
   ude (§6.2). Gates på `current_rolle()`, ikke `using(true)` — bevarer medlem-GDPR-laget.
3. **Cascade-preview** for sletning: enten udvidet relations-fetch (subjekt OR objekt) i
   read-laget, eller en `red_slet_person_preview(person_id)`-RPC (read-only, returnerer antal/
   liste af berørte relationer/facts) der spejler `red_slet_person`-logikken (§7).

Disse verificeres mod live-basen (samme REST-probe-metode som §0).

## 9. Tværgående

- **Dry-run** global (Zustand, findes): top-bar-chip + dashboard-kort + konto, samme state.
  Dry-run → preview-sheet viser `{fn,args}`, udfører ikke. LIVE → `submitChange`.
- **Fejlhåndtering:** PostgREST/Postgres-fejl → dansk tekst i preview-sheet.
  `P0001 "Kun redaktion"` → "Kræver redaktør-rettigheder". Oversættelses-helper i submit-laget.
- **Cache:** `person.visning_*` regenereres af DB-trigger (spec 2026-06-26 §7); efter en write
  re-fetcher editoren personens evidens + opdaterer header (model-felter eller targeted re-load).

---

## 10. Design-tokens (matcher `theme/tokens.ts`)

Genbrug eksisterende tokens. Redaktion-specifikke (handoff §Design tokens):
bordeaux `#881A33`; paper `#f4efe6`; kort `#fbf8f1`; mørkt kort `#2a211c`;
konklusion-grøn `#1f5b3a` / flade `#eaf3ec`; fejl/slet `#8a2b2b`; LIVE-rød `#c0392b`;
konflikt-flade `#f2dede`; guld `#b9a06a`/`#e7c98f`. Fonte: Cormorant (serif/værdier),
Hanken Grotesk (UI), JetBrains Mono (kickers/labels/kode). Verificér mod `tokens.ts`;
tilføj kun manglende redaktion-tokens additivt.

---

## 11. Test

- **jest:** `fetchPersonEvidence`-join (fact→assertion→conclusion→citation samling, konflikt-
  flag = >1 distinkt værdi); nye `buildRpcCall`-cases (edit/slet/konklusion/privat/slet-person);
  dry-run-preview-generering; fejl-oversættelse (P0001 → dansk).
- **DB:** `red_konflikt`-view verificeres mod live-base (returnerer forventede konflikt-rader;
  grant/RLS-læsbar for authenticated).
- **DB (RLS/sikkerhed):** test at `red_konflikt` med `security_invoker` IKKE returnerer private
  personer (anon/medlem); at redaktion-read-policy giver redaktør adgang til privat-markeret
  person efter `red_set_privat`. Verificeres mod live-base.
- **UI:** lette render-tests (editor-kort folder ud, rolle gater handlinger) **forudsætter en
  RN-testing-afhængighed** (`@testing-library/react-native` + `react-test-renderer`, React-19-
  kompatibel) — findes IKKE i `package.json` i dag (Codex-review, lav). Plan 1: enten tilføj
  afhængigheden (noteres i §12) ELLER nedprioritér render-tests til logik-only jest + manuel
  funktionstest. Manuel: login → editor → write (kræver seeded redaktion-profil).

---

## 12. Berørte artefakter

**Nye:**
- `mobile/src/app/redaktion/_layout.tsx`, `(red-tabs)/_layout.tsx`,
  `(red-tabs)/index.tsx`, `(red-tabs)/entiteter.tsx` (stub), `(red-tabs)/konto.tsx`,
  `person/[id].tsx`.
- `mobile/src/data/redaktionRead.ts` (+ test).
- Sheet-komponenter (login, skrive-preview, slet-bekræft) under `mobile/src/components/`.

**Ændrede:**
- `mobile/src/data/redaktionWrite.ts` (+ nye `buildRpcCall`-cases, fejl-oversættelse).
- Evt. `mobile/src/theme/tokens.ts` (manglende redaktion-tokens, additivt).
- `mobile/src/store/useStore.ts` (kun hvis UI kræver ny tværgående state — auth/dryRun findes).
- `mobile/package.json` (kun hvis render-tests vælges: RN-testing-dep, §11).

**DB-ændringer (§8b — additivt, idempotent):**
- `db-migrations.sql` + `schema.sql`: `red_konflikt`-view (`security_invoker`); evt.
  `red_slet_person_preview`-RPC.
- `db-rls.sql`: redaktion-read-policy (private rækker synlige for `current_rolle()='redaktion'`)
  på person + personbundne tabeller; `grant select on red_konflikt`.

---

## 13. Scope / non-goals

**I scope (plan 1):** `(red-tabs)`-navigation; evidens-read-lag; dashboard m. konflikt-kø;
person-editor (kerne-fakta + narrativ skrivbar, resten read-only); konto; login/skrive-preview/
slet-sheets; write-wiring af edit/slet/konklusion/privat/slet-person; `red_konflikt`-view.

**Non-goals (plan 2, additivt):**
- Entitetslister (`[entity]/index.tsx`).
- Generisk record-editor (`record/[entity]/[id].tsx`) + 9 entitets-feltskemaer.
- Opret-ny-flow (sheet er stub i plan 1).
- Redigering af relationer + sektioner (hverv/godser/kilder/våben).
- Publikum → redaktion-indgang i UI.
- Seedet redaktion-profil-flow (manuelt dashboard-step i PoC).
