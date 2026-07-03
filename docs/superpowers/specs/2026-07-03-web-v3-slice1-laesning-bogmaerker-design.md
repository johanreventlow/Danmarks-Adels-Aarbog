# Design: Følgesvend web v3 — Slice 1 (læse-paritet + bogmærker)

**Dato:** 2026-07-03
**Branch:** `feat/web-v3-slice1` (fra `main`)
**Kilde-design:** `Reventlow-web-v3.dc.html` (Claude Design-projekt `Danmarks Adels Aarbog app`)
**Status:** Design — afventer review (Codex) + implementeringsplan

---

## 1. Baggrund og afgrænsning

`web/src/Folgesvend.tsx` er allerede en port af **v2**-designet: header-nav, sidebar-browse
(stats · søg · sortér · alfabet-hop · linje-chips), Stamtræ (variant A "Fokus" + variant B
"Kolonner"), Slægtskab ("Er vi i familie?"), Godser + gods-detalje, Våben, Om slægten, og et
højre detalje-panel med proveniens/bio/NarrativRenderer/"mig"-koncept.

**v3** lægger fire ting ovenpå v2:

| Bucket | Indhold | Backend | Slice |
|---|---|---|---|
| **A. Læse-forbedringer** | `ctx`-sidebar-sektion, slægt-vælger-modal (`isSlaegtPicking`) | Ingen | **1** |
| **B. Bogmærker** | quick-bogmærker (sidebar) + fuld `isBookmarks`-visning + toggle-ikoner | localStorage nu | **1** |
| **C. Auth/konto** | log ind/ud, konto-avatar + menu | `auth.ts` findes | 2 (egen spec) |
| **D. Redigeringstilstand** | inline felt-editering, banner, "Gennemse & indsend" | `red_*`-RPC'er / `Redaktion.tsx` | 2 (egen spec) |

**Denne spec dækker kun Slice 1 (A + B).** Bucket C+D er bevidst udskudt: D er det tidligere
noterede "item 9 (inline-redigering, afventer arkitektur-beslutning)" og kolliderer med den
**eksisterende separate `Redaktion.tsx`-app**. Beslutning truffet 2026-07-03: den offentlige
app forbliver **read-only** i denne omgang; login + redigering bliver sin egen spec.

### Afklaret ved layout-inspektion af design-filen
- **Højre detalje-panel bevares** i v3 (ét `border-left`/392px-panel). `isReadingDetail` er
  ikke et nyt center-view — det er *læse-tilstanden* af det eksisterende højre-panel (modstykket
  til `isEditing`). Read-only ⇒ det svarer til det nuværende `DetailPanel`. **Ingen
  layout-ændring i Slice 1.**
- Bogmærker er i designet knyttet til `acct` (logget ind). Uden auth i Slice 1 backer vi dem med
  **anonymt localStorage** (som `meId`-mønstret). "Din konto · {navn}"-linjen i bogmærke-visningens
  header **udelades**; titlen forbliver "Mine bogmærker".

---

## 2. Mål og ikke-mål

**Mål (Slice 1):**
1. Bogmærke en person og finde bogmærkede personer hurtigt igen (sidebar-quick + fuld visning).
2. Kontekst-quicknav (`ctx`) øverst i sidebaren for den person der er i fokus.
3. Slægt-vælger-modal (kosmetisk, fremadskuende) på "Reventlow ▾"-chippen.
4. Visuel paritet med v3 for de flader Slice 1 dækker.

**Ikke-mål (→ Slice 2 / senere):**
- Login, konto-avatar/-menu, logud.
- Redigeringstilstand, inline-editering, "Gennemse & indsend"-pipeline.
- Multi-slægt-*data* (kun Reventlow findes; vælgeren er 1-punkt + "flere kommer").
- Cross-device-persistens af bogmærker (kræver auth + Supabase-tabel — Slice 2).

---

## 3. Arkitektur og komponenter

### 3.1 Bogmærke-lager — `web/src/data/bookmarks.ts` (nyt)

En **localStorage-adapter** (PoC) bag et lille modul-interface. Spejler `meId`-mønstret (kanoniske
id'er, localStorage).

> **Swappable-nuance (revideret efter Codex-review):** vi lover *ikke* at en Supabase-tabel senere
> kan skiftes ind bag det samme *synkrone* interface uden UI-ændringer. En bruger-scoped,
> persisteret bogmærke-backend er iboende **asynkron** (loading/error/mutation-latency) og kræver
> auth-scope — det designes som en **async repository-kontrakt i Slice 2**. Slice 1 holder blot al
> localStorage-adgang bag ét modul (`bookmarks.ts`), så kaldere importerer fra ét sted; det er
> grænsen for løftet nu.

```ts
export interface BookmarkStore {
  list(): string[];                 // kanoniske person-id'er, seneste-tilføjet-først
  has(id: string): boolean;
  toggle(id: string): string[];     // returnerer ny liste (så kaldere kan opdatere state)
}

// localStorage-impl (PoC). Nøgle: 'daa_bookmarks'. Værdi: JSON string[].
export function createLocalBookmarkStore(): BookmarkStore { ... }

// React-hook — kilde til sandhed i UI'et.
export function useBookmarks(canon: (id: string) => string): {
  ids: Set<string>;                 // til O(1) has()-opslag i render
  has(id: string): boolean;
  toggle(id: string): void;
};
```

**Invarianter:**
- Alle gemte id'er er **kanoniske** (samme_som-collapse-aware): `toggle`/`has` resolver gennem
  `canon()` *før* opslag/skrivning, så et bogmærke på et alias og på den kanoniske person er
  samme bogmærke. Konsistent med hvordan `meId` håndteres i `Folgesvend.tsx`.
- **Re-normalisering ved model-load/recollapse (Codex SHOULD-FIX):** `canonicalIdById` indlæses
  *asynkront efter mount* (`Folgesvend.tsx:63`) og kan ændres ved en senere recollapse. Derfor
  re-normaliserer `useBookmarks` **hele** den gemte liste gennem `canon()` når canon-mappet bliver
  tilgængeligt eller ændrer identitet (via `useEffect` på canon-map-referencen). Dedup med
  **"nyeste vinder"** (bevar seneste-først-rækkefølge), og **persistér** den migrerede liste
  tilbage til localStorage. Det forhindrer at et alias-id og dets kanoniske id ligger dobbelt eller
  giver forkert antal/rækkefølge.
- Defensiv JSON-parse (korrupt/manglende værdi → tom liste). SSR-guard (`typeof window`).
- `toggle` er **involutiv** (to identiske kald genskaber starttilstanden), ikke idempotent;
  lagringen er dedupliceret (Set-baseret) så samme kanoniske id aldrig optræder to gange.

**Test (`web/src/data/__tests__/bookmarks.test.ts`):**
- toggle tilføjer/fjerner; `has` afspejler tilstand.
- kanonisk dedup: `toggle(alias)` efterfulgt af `has(canonical)` → true.
- persistens: skriv → nyt store-instans læser samme liste.
- korrupt localStorage → tom liste (ingen throw).

### 3.2 Bogmærke-liste-bygger — `web/src/data/bookmarks.ts` (samme fil)

Ren funktion til den fulde bogmærke-visning (sortérbar), så logikken er testbar uden komponent:

```ts
export type BookmarkSort = 'linje' | 'navn';
export function buildBookmarkList(
  ids: string[],
  model: Model,
  sort: BookmarkSort,
): { linje: string | null; navn: string; people: ModelPerson[] }[];
```

- `sort='navn'`: én gruppe (`linje=null`), personer sorteret A–Å via **`compareDanish`** fra
  `web/src/lib/collation.ts` (samme collator som `browse.ts` bruger — `import { compareDanish } from
  '../lib/collation'`). *Ikke* en `data/collation.ts` (findes ikke — Codex-korrektion).
- `sort='linje'`: **`lineage.byPerson` er `Record<string, string[]>`** — en person kan høre til
  *flere* linjer, og der findes **ingen primær-markør** (Codex-korrektion). Vi opfinder ikke en
  falsk "primær": personen placeres deterministisk i gruppen for sin **første** linje-kode
  (`byPerson[id][0]`) — dette er ren display-placering, ikke en påstand om primaritet. Gruppe-navn
  fra `model.lineage.navn[kode]`; personer uden nogen linje-kode i en "Uden linje"-gruppe sidst.
  Grupper sorteres efter linje-kode; personer inden for en gruppe efter `compareDanish`.
- Ukendte/forældede id'er (person slettet / ikke i `model.byId`) filtreres bort (defensivt).

**Test:** begge sorteringer; **multi-lineage-person** lander i én deterministisk gruppe (første
kode); person-uden-linje → "Uden linje"; ukendt-id-filtrering; Æ/Ø/Å-sortering via `compareDanish`.

### 3.3 UI i `Folgesvend.tsx` + nye komponentfiler

`Folgesvend.tsx` er allerede ~905 linjer. **Nye store dele lægges i egne filer** frem for at
oppuste den; små wiring-dele bor i `Folgesvend.tsx`.

- **`web/src/components/BookmarksView.tsx` (nyt)** — den fulde `isBookmarks`-center-visning:
  header ("Mine bogmærker" + antal-label + sortér-segment Linje/A–Å), grupperet liste, række →
  `onPick(id)`, fjern-knap pr. række. Props: `{ model, ids, sort, setSort, onPick, onRemove }`.
  **BLOCKER-fix (Codex):** en bogmærke-række må ikke bare sætte `focusId` — detalje-panelet vises
  kun i `tree`/`relate` (`Folgesvend.tsx:284`), så et klik fra `bookmarks`-mode ville være visuelt
  resultatløst. `onPick` wires derfor i `Folgesvend.tsx` til **atomisk `navigateTo(id)` +
  `setMode('tree')`** (samme mønster som `EstatesView`'s `onPickOwner`, `Folgesvend.tsx:278`).
- **`web/src/components/SlaegtPicker.tsx` (nyt)** — `isSlaegtPicking`-modal-overlay: fixed
  backdrop + panel øverst-højre, slægt-liste (Reventlow markeret aktiv) + "flere slægter kommer"-note.
  Props: `{ open, slaegter, activeId, onClose, onPick }`. Kun Reventlow i listen nu.
- **`Folgesvend.tsx` (redigering):**
  - **`ctx`-sektion** i sidebaren (se §3.4).
  - **`bmQuick`-sektion** i sidebaren: vises kun når `ids.size > 0`; top 3 (seneste-først) med
    initial-badge + navn + år + fjern-flag; "Se alle (N)" når >3 → `setMode('bookmarks')`.
  - **Bogmærke-toggle-ikon** (flag-SVG fra designet, udfyldt/omrids efter `has(id)`) på:
    Stamtræ variant A søskende-kort, variant B kort, og detalje-panelets titel-række.
    → deles som lille `<BookmarkFlag active onClick />`-primitive i `Folgesvend.tsx`.
    **Klik-bobling (Codex):** flaget sidder *inde i* et klikbart kort (kortet har egen `onClick` →
    navigation). Flag-`onClick` skal `e.stopPropagation()` så bogmærkning ikke *også* trigger
    kort-navigation. Testes eksplicit.
  - **`mode`-udvidelse:** `'bookmarks'` tilføjes center-switch'en; ryddes ikke af andre modes.
  - **Slægt-chip** gøres klikbar → åbner `SlaegtPicker`.

### 3.4 `ctx` — kontekst-quicknav (sidebar)

**Semantik (fastlagt her for at undgå tvetydighed):** `ctx` vises **kun i `tree`-mode** med
`focusId` sat, og viser en kompakt "I fokus"-sektion øverst i sidebaren.

> **Codex SHOULD-FIX — hvorfor kun `tree`:** i `relate`-mode ændrer person-valg kun `relA`/`relB`,
> *ikke* `focusId` (`Folgesvend.tsx:147`). En `focusId`-baseret "I fokus" ville derfor vise en
> forældet person, der ikke matcher relations-emnerne. Vi begrænser `ctx` til `tree`, hvor
> `focusId` *er* den valgte person. (Relate har sine egne A/B-kort som kontekst.)

- **label:** `I fokus`
- **items** (i rækkefølge, kun dem der findes):
  1. Fokus-personen selv — kicker `VALGT`, cirkel-badge (initialer), `onTap` = ingen-op (ankeret).
  2. Hver forælder — kicker `FORÆLDER`, cirkel-badge (initialer), `onTap` = `navigateTo(parent)`.
     Forældre hentes fra `model.indexes.parentsByChild[focusId]` (samme kilde som detalje-panelet).
  3. Linje(r) — **for hver** kode i `model.lineage.byPerson[focusId]` (0..n; ingen falsk "primær"):
     kicker `LINJE`, **afrundet-firkant**-badge (linje-kode), navn fra `lineage.navn[kode]`,
     `onTap` = `pickLinje(kode, headId)` hvor `headId = lineage.list.find(e => e.linje === kode)
     ?.headId` (headId bor i `LinjeEntry`/`list`, ikke i `byPerson` — Codex-korrektion). Multi-
     lineage-person → flere LINJE-rækker.

Det mixede badge-form (cirkel for person, afrundet firkant for linje) matcher designets
varierende `c.radius`. `ctx` skjules i alle andre modes (relate/godser/våben/om/bogmærker).

> `ctx` er den mest fortolkede del af Slice 1 (design-filen fastlægger ikke datakilden eksplicit).
> Ovenstående er en bevidst, faithful produktbeslutning; kan justeres i review.

### 3.5 Data / henter

Ingen nye Supabase-kald. Alt bygger på den allerede indlæste `model` (`byId`, `indexes`,
`lineage`, `canonicalIdById`) + localStorage. Ingen nye RLS/backend-flader.

---

## 4. Tilstand (React)

Ny state i `Folgesvend.tsx`:
- `bookmarks` via `useBookmarks(canon)` → `{ ids, has, toggle }`.
- `bmSort: BookmarkSort` (`'linje' | 'navn'`, default `'linje'` jf. designets første segment).
- `slaegtOpen: boolean` (slægt-picker-modal).
- `mode` udvides med `'bookmarks'`.

`focusId`, `meId`, `canon`, `navigateTo`, `pickLinje` genbruges uændret.

---

## 5. Fejlhåndtering og edge cases

- **Korrupt/utilgængelig localStorage:** fallback til tom liste; toggle no-op'er hellere end at
  throw'e (bogmærker er ikke-kritisk PoC-funktion).
- **Bogmærket person forsvinder** (samme_som-recollapse eller data-reload): `buildBookmarkList`
  filtrerer ukendte id'er; `ids` beholder dem i localStorage (harmløst — de dukker op igen hvis
  personen kommer tilbage).
- **Alias vs. kanonisk:** al toggle/has går gennem `canon()` → ét bogmærke pr. reel person.
- **Tom bogmærke-visning:** venlig tom-tilstand ("Ingen bogmærker endnu — tryk flaget på en person").
- **Slægt-picker med kun 1 slægt:** Reventlow vist som aktiv; ingen skift-handling ud over at
  lukke; "flere slægter kommer"-note gør 1-punkts-listen forståelig.

---

## 6. Test-plan

| Niveau | Hvad | Fil |
|---|---|---|
| Enhed | `bookmarks` store: toggle(involutiv)/has/persistens/kanonisk-dedup/korrupt-parse/**throwing localStorage** | `data/__tests__/bookmarks.test.ts` |
| Enhed | **Re-normalisering:** `[alias, canonical]` i lager → hook efter canon-load dedup'er til én; canonical-skift migrerer + persisterer | samme fil |
| Enhed | `buildBookmarkList`: begge sorteringer, **multi-lineage → én deterministisk gruppe**, uden-linje-gruppe, ukendt-id-filter, Æ/Ø/Å | samme fil |
| Komponent | `BookmarksView`: render af grupper, fjern-knap kalder `onRemove` | `components/__tests__/BookmarksView.test.tsx` |
| Komponent | **`BookmarkFlag` klik-bobling:** klik på flag i klikbart kort kalder `toggle`, *ikke* kort-nav (`stopPropagation`) | `Folgesvend`-nær test / BookmarksView |
| Komponent | **`SlaegtPicker`-lukning:** backdrop-klik + Escape lukker; `onPick` på aktiv slægt | `components/__tests__/SlaegtPicker.test.tsx` |
| Integration | **bookmark→tree-nav:** klik en bogmærke-række i `bookmarks`-mode → `mode='tree'` + `focusId` sat (detalje-panel synligt) | komponent/integration |
| Regression | `tsc` + hele web-suiten grøn | `npm run build` + `vitest` |
| Manuel | toggle-flag → bmQuick opdaterer → "Se alle" → sortér → fjern; slægt-chip → modal (Escape/backdrop); ctx-hop i tree | browser |

Risiko-baseret: bogmærke-lager + re-normalisering + liste-bygger er kritiske (data-korrekthed,
async canon-timing) → fuld enheds-dækning. Klik-bobling og navigation er de subtile UI-fælder →
integration/komponent-test. `ctx`/picker-præsentation → komponent-/manuel-verifikation.

---

## 7. Filer

**Nye:**
- `web/src/data/bookmarks.ts` — store-interface + localStorage-impl + `useBookmarks` + `buildBookmarkList`
- `web/src/data/__tests__/bookmarks.test.ts`
- `web/src/components/BookmarksView.tsx`
- `web/src/components/SlaegtPicker.tsx`
- `web/src/components/__tests__/BookmarksView.test.tsx`

**Redigeret:**
- `web/src/Folgesvend.tsx` — ctx-sektion, bmQuick-sektion, bogmærke-flag-primitive + wiring på
  kort/detalje, `bookmarks`-mode i center-switch, klikbar slægt-chip.

**Urørt:** `schema.sql` (ucommittet orphan-ændring — ikke del af v3), datamodel, `Redaktion.tsx`,
alle backend/RLS-flader, `buildModel`/`relationship`/`tree`-motoren.

---

## 8. Åbne spørgsmål til bruger-review

1. **`ctx`-semantik** (§3.4) — *besluttet efter Codex-review*: tree-only "I fokus" = fokus-person +
   forælder(e) + linje(r). Bekræft venligst, eller sig til hvis du hellere vil have nære relationer
   inkl. ægtefælle/børn eller "senest set".
2. **Bogmærke-visningens indgang:** designet ruter via konto-menuen; uden auth bruger vi
   bmQuick "Se alle". Er det tilstrækkeligt, eller ønskes også et top-nav-punkt "Bogmærker"?
3. **Default bogmærke-sortering:** designet viser "Linje" som første segment → default `'linje'`.
   OK?

## 9. Codex-review — resultat

Spec'en blev dual-reviewet af Codex (2026-07-03). 1 BLOCKER + 7 SHOULD-FIX + 1 NIT, **alle
accepteret og indarbejdet** (tre faktuelle codebase-korrektioner verificeret mod koden først):
- **BLOCKER** bookmark-række-nav → `navigateTo + setMode('tree')` (§3.3).
- Collation: `compareDanish` fra `../lib/collation`, ikke `data/collation.ts` (§3.2).
- `lineage.byPerson` er `string[]` uden primær-markør → deterministisk første-kode-placering, ingen
  falsk primær; `headId` fra `list` (§3.2, §3.4).
- Async re-normalisering af lager ved canon-load/recollapse (§3.1).
- Swappable-løfte nedtonet til localStorage-adapter; async Supabase-repo → Slice 2 (§3.1).
- `ctx` begrænset til `tree` (stale i relate) (§3.4).
- Klik-bobling: flag `stopPropagation` (§3.3); udvidet test-plan (§6).
- NIT: "involutiv", ikke "idempotent" (§3.1).
