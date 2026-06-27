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
join** (modellen er polymorf: `assertion.target_type/target_id` og `conclusion.target_type/
target_id` peger på `fact` UDEN rigtig FK, så PostgREST nested-select 400'er — derfor flade
kald):

1. `fact?subjekt_type=eq.person&subjekt_id=eq.{id}` → `factIds`, faktatype pr. fact.
2. `assertion?target_type=eq.fact&target_id=in.({factIds})` → værdier + fuzzy-datoer.
3. `conclusion?target_type=eq.fact&target_id=in.({factIds})` → `valgt_assertion_id` pr. fact.
4. `citation?assertion_id=in.({assertionIds})` (+ `source`-opslag) → kilde pr. oplysning.

Samles til:
```ts
type FeltEvidens = {
  felt: string;                 // navn|foedt|doed|titel  (koen særskilt, §4)
  faktatype: string;
  factId: number;
  konklusionAssertionId: number | null;
  oplysninger: {
    assertionId: number;
    vaerdi: string;
    dato?: { min, max, qualifier, raw };
    kilde?: { sourceId, titel, side, citatTekst, forfatter, dato };
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
create or replace view red_konflikt as
select f.subjekt_id   as person_id,
       f.faktatype,
       count(distinct a.vaerdi_tekst) as antal_vaerdier,
       count(*)                       as antal_oplysninger
from fact f
join assertion a
  on a.target_type = 'fact' and a.target_id = f.id
where f.subjekt_type = 'person'
group by f.subjekt_id, f.faktatype
having count(distinct a.vaerdi_tekst) > 1;
```

- "uenig" = **>1 distinkt værdi** (samme værdi fra to kilder = bekræftelse, ikke konflikt).
- Dashboard læser `red_konflikt` direkte (RLS: arver tabel-politikker; tilføj `grant select`
  + read-policy hvis nødvendigt — verificeres mod live-base).
- **Dato-felter:** `vaerdi_tekst` kan være tom for fødsel/død; konflikt på datoer beror på
  `date_raw`. Noteres i planen som forfin-punkt (kan undlade dato-felter fra view'et i v1).

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
- Evidens-note (kun hvis `showAnnotations`).
- **Kerne-fakta** (5 kort: navn/foedt/doed/koen/titel), drevet af `fetchPersonEvidence`:
  - Sammenklappet: feltlabel + konklusionsværdi + kilde + "uenige"-tag + "N oplysn." + chevron.
  - Udfoldet: pr. oplysning — værdi + status (konklusion/oplysning) + kilde + meta;
    handlinger **Gør til konklusion** (`red_set_konklusion`), **✎ redigér**
    (`red_edit_oplysning`), **🗑 slet** (`red_slet_oplysning`). **+ Tilføj oplysning**
    (`red_upsert_fakta`). `koen` → `red_set_koen`.
- **Narrativ · biografi:** `TextInput` (multiline) + kilde-felt → `red_upsert_narrativ`
  (**skrivbar**).
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
- **UI:** lette render-tests (editor-kort folder ud, rolle gater handlinger). Manuel
  funktionstest af login → editor → write (kræver seeded redaktion-profil).

---

## 12. Berørte artefakter

**Nye:**
- `mobile/src/app/redaktion/_layout.tsx`, `(red-tabs)/_layout.tsx`,
  `(red-tabs)/index.tsx`, `(red-tabs)/entiteter.tsx` (stub), `(red-tabs)/konto.tsx`,
  `person/[id].tsx`.
- `mobile/src/data/redaktionRead.ts` (+ test).
- Sheet-komponenter (login, skrive-preview, slet-bekræft) under `mobile/src/components/`.
- `red_konflikt`-view i `db-migrations.sql` + `schema.sql`.

**Ændrede:**
- `mobile/src/data/redaktionWrite.ts` (+ nye `buildRpcCall`-cases, fejl-oversættelse).
- Evt. `mobile/src/theme/tokens.ts` (manglende redaktion-tokens, additivt).
- `mobile/src/store/useStore.ts` (kun hvis UI kræver ny tværgående state — auth/dryRun findes).

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
