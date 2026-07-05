# Følgesvend v3 — forsidefeed, menu-drawer & bogmærker

**Dato:** 2026-07-05
**Design-kilde:** `Reventlow-folgesvend-v3.dc.html` (Claude Design-projekt `0d84324f…`)
**Mål:** mobil-appen (`mobile/`, RN/Expo) bringes op til v3-designet. Fokus er de tre reelt
nye elementer + en afgrænset visuel afstemning af de øvrige skærme.

---

## 1. Baggrund & afgrænsning

Mobil-appens token-system (`theme/tokens.ts`) og de fleste skærme (Om, Våben, Godser,
Godsdetalje, Stamtræ A/B/C, Person, Slægtskab, Søg, Konto) findes allerede og matcher
stort set v3. Det **nye** i v3 er:

1. **Forsidefeed** — hjemmeskærmen bliver et redaktionelt feed af 9 korttyper (i dag: en
   v2 "slægts-portal" med hero + nummereret 01–08 udforsk-liste).
2. **Menu-drawer** — venstre slide-in med slægt-header, nav-liste og konto-footer. Den
   nummererede 01–08-liste **flytter fra forside-kroppen ind i drawer'en**.
3. **Bogmærker** — findes i `web/` (person-kun, localStorage) men ikke i `mobile/`. Ny
   AsyncStorage-baseret lagring + skærm + gem-toggle på forsidens person-kort.

**Ikke i scope / bevidst udeladt:**
- Ingen backend-/DB-ændringer i nogen skive. Feedet er ren læsning ovenpå den eksisterende
  model.
- Ingen ændring af `buildModel` eller slægtskabs-motoren.
- Redaktionelt kurateret feed (DB-tabel + redaktør-UI) er **udskudt** — se hybrid-beslutning §3.
- Fuld 1:1-genimplementering af eksisterende skærme. Skive 5 er en *afgrænset* sweep, ikke
  en genopbygning.

**Beslutninger truffet i brainstorm (2026-07-05):**
- Scope = "det nye + visuel afstemning".
- Feed-kilde = **hybrid**: auto-genereret nu, med et interface en redaktionel kilde kan føde senere.
- Bogmærker = **kun personer**, spejler web-kontrakten, men AsyncStorage.
- Citat-kort = **auto-uddrag** af første markante sætning (beholdes trods risiko for kluntethed).
- Jubilæum-tærskel = **runde jubilæer** (100/150/200… år siden).

---

## 2. Skæring (5 skiver)

| # | Skive | Nye/ændrede filer | Grænse/test |
|---|---|---|---|
| 1 | Feed-datamodel | `data/buildFeed.ts` (+ typer i `data/types.ts`) | Ren funktion; unit-testet; ingen UI |
| 2 | Forside-feed | `app/(tabs)/index.tsx` (omskrevet), `components/feed/*` | Rendrer `buildFeed`-output; snapshot af kort |
| 3 | Menu-drawer | `components/MenuDrawer.tsx`, wiring i hjem | Nav + konto-footer |
| 4 | Bogmærker | `lib/bookmarks.ts`, `app/bogmaerker.tsx`, hook | Port af web-test-suite |
| 5 | Visuel afstemning | Punktrettelser i eksisterende skærme | Kun klare v3-afvigelser |

Skiverne bygges i rækkefølge. 1 er en forudsætning for 2; 4 kobler ind i 2 (gem-ikon på kort).
Hver skive holder `tsc` + eksisterende jest grøn.

---

## 3. Skive 1 — Feed-datamodel (`data/buildFeed.ts`)

### 3.1 Signatur

```ts
export type FeedCard =
  | { kind: 'portrait'; id: string; personId: string; name: string; years: string;
      initials: string; title: string | null; bio: string; kicker: string }
  | { kind: 'citat'; id: string; personId: string; quote: string; source: string; kicker: string }
  | { kind: 'gods'; id: string; estateId: string; navn: string; meta: string;
      ownerDots: number; kicker: string }
  | { kind: 'forbundet'; id: string; aName: string; bName: string; aInit: string;
      bInit: string; marBottom: string; kicker: string }
  | { kind: 'slaegt'; id: string; aName: string; bName: string; rel: string;
      foot: string; onOpenRoute: string; kicker: string }
  | { kind: 'embede'; id: string; personId: string; label: string; name: string;
      period: string; init: string; kicker: string }
  | { kind: 'jubilaeum'; id: string; personId: string; num: number; name: string;
      sub: string; kicker: string }
  | { kind: 'vaaben'; id: string; armsId: string; blazon: string; foot: string; kicker: string }
  | { kind: 'samle'; id: string; count: number; tail: string; kicker: string };

export interface FeedOptions {
  meId: string | null;
  focusId: string | null;
  today: number; // årstal (fx 2026) — injiceres for determinisme/test
  overrides?: FeedOverride[]; // tom nu; editorial-krog (hybrid-beslutning)
}
export type FeedOverride = { pin?: string[]; hide?: string[] }; // fremtidig redaktionel styring

export function buildFeed(model: Model, aux: Aux, opts: FeedOptions): FeedCard[];
```

`id` er kortets stabile nøgle (fx `portrait:<personId>`, `gods:<estateId>`, `jubilaeum:<personId>:<num>`),
brugt både som React-key og som seed for rækkefølgen. `personId` findes kun på bogmærkbare kort.

### 3.2 Udledning pr. korttype

Alle kilder findes allerede i `Model`/`Aux` (verificeret i `data/types.ts`):

| kind | Kilde | Regel |
|---|---|---|
| `portrait` | `model.persons` med ikke-tom `bio` | navn, `years`, `title`, initialer (1. bogstav i navn), bio (klampes til 5 linjer i UI) |
| `citat` | `model.persons` med bio | første markante sætning (se §3.3); kilde = personens navn + evt. år |
| `gods` | `aux.godsListe` | navn, meta (`slags` + ejer-antal), `ownerDots` = `min(ownerCount, 7)` |
| `forbundet` | `model.indexes.unionById` (unions m. begge ægtefæller) | de to ægtefællenavne + initialer; `marBottom` = evt. vielsestekst/fallback |
| `slaegt` | `relationship.ts` mellem `meId ?? focusId` og en markant person | to navne + relationstekst; `onOpenRoute` = `/relate` |
| `embede` | `aux.officesBy` (person → `OfficeRef`) | label, personnavn, periode, initial |
| `jubilaeum` | personer m. `born`/`died` og runde år vs. `today` | `num` = `today − år` når `num % 50 === 0 && num ≥ 100`; anledning i `sub` |
| `vaaben` | `aux.vaabenListe` | blasonering (fallback-tekst hvis tom), fod-tekst |
| `samle` | rest-entiteter for tynde til eget kort | tæller + register-pointer |

Kort hvis kilde er tom udelades helt (fx intet `slaegt`-kort uden `meId`/`focusId`; intet
`vaaben`-kort hvis `vaabenListe` er tom). Tom model → tom liste (ingen crash).

### 3.3 Citat-uddrag

Ren hjælper `firstQuotableSentence(bio: string): string | null`: split på sætnings-endelser,
vælg første sætning der er 40–180 tegn (undgå for korte fragmenter/for lange løb), trim.
Returnér `null` hvis intet passer → intet citat-kort for den person.

### 3.4 Determinisme & rækkefølge

- **Ingen** `Math.random`/`Date.now`. `today` injiceres via `FeedOptions`.
- Kort samles pr. type, hver type sorteres stabilt (efter `id`), og typerne **interleaves** i
  en fast prioritetsrytme (fx portrait, gods, forbundet, portrait, citat, embede, jubilaeum,
  vaaben, slaegt, samle) via en ren `interleave()`-hjælper. Samme input → samme output.
- Hele listen returneres (ingen paginering i PoC). "Henter flere blade"-footeren i UI er dekorativ.

### 3.5 Editorial-ready (hybrid)

`overrides` er tom nu. Kontrakten er defineret så en senere redaktionel tabel kan føde
pin/hide/rækkefølge uden at røre udledningen (`buildFeed` anvender `overrides` sidst i pipelinen).

### 3.6 Test (`data/__tests__/buildFeed.test.ts`)

- Hver korttype udledes fra minimal fixture.
- Determinisme: samme input → identisk output (dyb lighed) over to kald.
- Jubilæum: injiceret `today`, verificér tærskel (99 år → intet; 100/150/200 → kort).
- Tom model/aux → `[]`.
- `firstQuotableSentence`: korte/lange/tomme input.

---

## 4. Skive 2 — Forside-feed (`app/(tabs)/index.tsx`)

### 4.1 Struktur (top → bund)

1. **Top-bar** (`components/HomeTopBar.tsx`): hamburger (åbner drawer), kompakt brand
   (DAF-logo + "Reventlow") der fader ind på scroll, bogmærke-ikon m. badge (`savedCount`).
2. **Kollapsende hero**: DAF-logo, kicker "Danmarks Adels Aarbog", "Slægten <navn>",
   bordeaux-regel, 3 tællere (personer/linjer/godser fra `counts`), "skift slægt ▾".
3. **Feed**: `FlatList` over `buildFeed`-output; ét komponent pr. `kind` i `components/feed/`.
4. **Footer**: dekorativ "Henter flere blade fra slægten".

Brand-på-scroll og hero-kollaps drives af `Animated`/scroll-offset (RN), ikke DOM-tricks.
`FlatList` bruges for genbrug/perf; hero + footer som `ListHeaderComponent`/`ListFooterComponent`.

### 4.2 Kort-komponenter (`components/feed/`)

Ét fil pr. korttype, hver tager sit `FeedCard`-variant + callbacks
(`onOpen`, `onSave`, `bookmarked`). Gem-ikonet rendres **iff kortet har et `personId`**
(`portrait`, `citat`, `embede`, `jubilaeum`) — gem gemmer den kanoniske person (matcher
person-kun-lagring, §6). Kort uden `personId` (`gods`, `forbundet`, `slaegt`, `vaaben`,
`samle`) udelader gem-ikonet. Styling fra `tokens.ts` —
ingen nye farver/fonte. Genbrug eksisterende `InitialBadge`, `StripedPlaceholder`,
`Typography`-primitiver hvor de passer.

### 4.3 Data-flow

Hjem læser `model`, `aux`, `meId`, `focusId` fra store → `buildFeed(model, aux, { meId, focusId,
today: <indeværende år> })`. `today` hentes ét sted (hjælper der læser årstal; injicerbar i test).
Tap på kort → `router.push` til person/gods/arms/relate. Gem-tap → `useBookmarks.toggle`.

### 4.4 Test

`buildFeed` er allerede dækket (skive 1). UI: snapshot/interaktions-test er valgfrit
(RN-render i jest er tungt her); primær verifikation er `tsc` + iOS-simulator (jf. projektets
mønster). Dokumentér hvad der er testet vs. simulator-verificeret.

---

## 5. Skive 3 — Menu-drawer (`components/MenuDrawer.tsx`)

Venstre slide-in via `Modal` (transparent) + `Animated.View` (`translateX`) + scrim
(`onPress` lukker). Bredde ~314px. Indhold:

- **Header**: crest-ring (`CrestRing`) + "Slægt / <navn>" + "Skift slægt ▾" (åbner `SlaegtPicker`).
- **Nav-liste**: den nummererede 01–08 (Stamtræ, Om slægten, Godser & ejendomme, Slægtens kort,
  Slægtens våben, Er vi i familie?, Søg, Konto) + **Bogmærker** som ekstra punkt. Hvert punkt:
  kursiv gyldent nummer, titel, undertekst, `›`. Tap → `router.push` + luk drawer.
- **Konto-footer**: logget ind → navn/initialer + log ud; ellers "Log ind"-knap
  (genbruger eksisterende auth-flow/`konto`-rute).

Bund-tabbaren beholdes uændret; drawer'en er en additiv "udforsk"-flade. Den gamle
01–08-liste **fjernes** fra `index.tsx`.

---

## 6. Skive 4 — Bogmærker

### 6.1 Lager (`lib/bookmarks.ts`)

Port af `web/src/data/bookmarks.ts`, med `@react-native-async-storage/async-storage` i stedet
for `localStorage`:
- Nøgle `daa_bookmarks`; array af **kanoniske person-id'er**, nyeste-først.
- `createLocalBookmarkStore()`: `list()/has()/toggle()` — nu async (AsyncStorage er async).
- `canonicalize()` + newest-first-dedup: uændret logik fra web.
- Skrivefejl sluges (ikke-kritisk PoC).

### 6.2 Hook (`useBookmarks(canon)`)

Spejler web-hook'en, men initial state loades i en effect (AsyncStorage er async — den ene
reelle afvigelse fra web's synkrone `useState`-init). Re-normaliserer gennem `canon()` ved
mount + når `canon`-mappet skifter identitet (recollapse). Eksponerer `{ ids: Set, has, toggle }`.
`canon` = `store.canonicalId` fra Zustand.

### 6.3 Skærm (`app/bogmaerker.tsx`)

Person-rækker (`InitialBadge` + navn + år) fra bogmærke-id'erne mappet gennem `model.byId`.
Tap → `/person/<id>`. Tom-tilstand når intet gemt. Rutes til fra drawer + top-bar-ikon.

### 6.4 Badge

Top-bar-bogmærke-ikonet viser `savedCount` (antal gemte) når > 0.

### 6.5 Test (`lib/__tests__/bookmarks.test.ts`)

Port af web's `bookmarks.test.ts` mod en AsyncStorage-mock (jest): toggle, canonicalisering,
dedup, nyeste-først, tom-tilstand.

---

## 7. Skive 5 — Visuel afstemning (afgrænset)

Gennemgå eksisterende skærme mod v3-designet og ret **kun klare, små afvigelser** (fx
top-bar-titelfont, tilbageknap-stil, afstande, kicker-casing). Alt der kræver reel
genopbygning **flages** i changelog/decisions frem for at blive lavet her. Skærme i sweep:
about, estates, estate/[id], arms, tree (A/B/C), person/[id], search, relate.

---

## 8. Risici & modforanstaltninger

- **Citat-kluntethed**: auto-uddrag kan ramme skævt. Modforanstaltning: streng
  længde-/sætnings-heuristik (§3.3) + `null`-fallback (intet kort frem for dårligt kort).
- **Feed-tomhed på tynd data**: hver korttype er valgfri; tom model → tom liste. Hero + footer
  vises altid, så skærmen er aldrig helt blank.
- **AsyncStorage-async vs. web-sync**: eneste kontrakt-afvigelse; isoleret til hook'ens init-effect.
- **Drawer + tabbar-overlap**: bevidst — drawer er additiv; ingen dublet-navigation fjernes.

## 9. Succeskriterier

- `buildFeed` dækket af unit-tests; determinisme bevist.
- Bogmærke-lager porteret + testet mod AsyncStorage-mock.
- `tsc` + hele eksisterende jest-suite (264+) grøn.
- Forside rendrer feed + top-bar + hero; drawer åbner/navigerer; bogmærker gemmes/vises.
- iOS-simulator-verifikation mod prod-data (jf. projektets etablerede mønster).
- Ingen backend-/model-ændringer.
