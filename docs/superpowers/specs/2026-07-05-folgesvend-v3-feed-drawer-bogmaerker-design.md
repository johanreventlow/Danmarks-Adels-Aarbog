# Følgesvend v3 — forsidefeed, menu-drawer & bogmærker

> **Status (2026-07-18):** §3 (feed-datamodellen: `buildFeed`, `FEED_CAPS`, fast
> `interleave`-rytme, `{meId,focusId,today}`-signaturen) er **afløst** af
> `docs/superpowers/specs/2026-07-18-levende-feed-fase1-design.md` (seeded pool → score →
> rytme-motor i `@daa/feed`, ægte uendelig scroll, web-feed). `mobile/src/data/buildFeed.ts`/
> `feedHash.ts` er slettet. §4 (forside-UI-struktur: top-bar, hero, `FlatList`), §5
> (menu-drawer) og §6 (bogmærker) er fortsat gældende historik/kontekst for det der findes i
> koden i dag.

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
  | { kind: 'slaegt'; id: string; aId: string; bId: string; aName: string; bName: string;
      rel: string; foot: string; kicker: string }
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

Alle kilder er **empirisk verificeret** i `data/types.ts` / `data/load.ts` / `data/relationship.ts`
(dual-review 20, DS1–DS4). `AppPerson.title` og `.bio` er ikke-nullable `string` (tom = "ingen"),
så "person med bio" = `p.bio.trim() !== ''`, og `hasTitle = p.title !== ''`.

| kind | Kilde | Regel |
|---|---|---|
| `portrait` | `model.persons` med `bio.trim()!==''`, i portræt-partitionen (§3.3a) | navn, `years`, `title` (nullable→`title||null`), initialer (1. bogstav), bio (UI klamper 5 linjer) |
| `citat` | `model.persons` med bio, i citat-partitionen (§3.3a) + `firstQuotableSentence!==null` | citat (§3.3b); kilde = personnavn + evt. år |
| `gods` | `aux.godsListe` | navn, meta (`slags` + ejer-antal), `ownerDots` = `min(ownerCount, 7)` |
| `forbundet` | `model.indexes.unionById`, kun unions m. `p2!==null` OG begge i `byId` | navne fra `model.byId[p1].name`/`[p2].name` (IKKE `p2_name`/`year` — begge `null` fra loader, dual-review NEW1); `marBottom` = `year? 'gift '+year : 'gift'` |
| `slaegt` | KUN når `meId` og `focusId` begge sat og distinkte | `aId=meId`, `bId=focusId`; `computeRelationship(model,aId,bId)` → skip hvis `found===false`, ellers `rel=result.label` (dual-review DS4/NEW2) |
| `embede` | `aux.officesBy` (person → `OfficeRef`) | label, personnavn, periode, initial |
| `jubilaeum` | personer m. `born`/`died` og runde år vs. `today` | `num = today − år` når `num % 50 === 0 && num ≥ 100`; anledning i `sub` |
| `vaaben` | `aux.vaabenListe` | blasonering (fallback-tekst hvis tom), fod-tekst |
| `samle` | rest-entiteter for tynde til eget kort | tæller + register-pointer |

Kort hvis kilde er tom udelades helt (intet `slaegt`-kort uden `meId`+`focusId`; intet
`vaaben`-kort hvis `vaabenListe` er tom). Tom model → tom liste (ingen crash).

**Volumen-loft (dual-review C).** Hver type sorteres stabilt efter `id` og trunkeres til et
loft FØR interleave, så listen ikke eksploderer på tæt data:

```ts
const FEED_CAPS = { portrait: 12, citat: 4, gods: Infinity, forbundet: 6,
                    embede: 6, jubilaeum: 6, vaaben: Infinity, slaegt: 1, samle: 1 };
```

Udvælgelse = de første N efter stabil id-sort (deterministisk).

### 3.3a Portrait/citat-partition (dual-review B)

Portrait og citat trækker fra samme bio-population, men en person må **aldrig** optræde som
begge. Bio-personerne partitioneres deterministisk: `isCitatSlot(id) = stableHash(id) % 4 === 0`
(≈25% citat-kandidater). En person i citat-slot bliver KUN et citat-kort hvis
`firstQuotableSentence !== null`; ellers falder personen HELT ud (bliver ikke portræt — det ville
genindføre overlap). Alle øvrige bio-personer bliver portrætter. Partitionerne er dermed disjunkte.
`stableHash` er en ren, deterministisk streng-hash (fx FNV-1a) — genbruges også til interleave-seed.

### 3.3b Citat-uddrag

Ren hjælper `firstQuotableSentence(bio: string): string | null`: split på sætnings-endelser,
vælg første sætning der er 40–180 tegn (undgå for korte fragmenter/for lange løb), trim.
Returnér `null` hvis intet passer → personen får intet kort (jf. §3.3a).

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
- **Portrait/citat disjunkt** (§3.3a): ingen person optræder som begge; citat-slot uden
  brugbar sætning falder helt ud (bliver ikke portræt).
- **Forbundet**: kun unions m. `p2!==null` og begge personer i `byId`; `marBottom`-fallback = "gift".
- **Slaegt**: intet kort uden både `meId` og `focusId`; `found===false` → intet kort; kort bærer `aId/bId`.
- **Caps**: type med >loft-elementer trunkeres til `FEED_CAPS` (§3.2).
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
Tap på kort → `router.push` til person/gods/arms. **`slaegt`-kort** (dual-review NEW2): `onOpen`
sætter `setRelA(card.aId)` + `setRelB(card.bId)` i store FØR `router.push('/relate')`, så
slægtskabs-skærmen læser de rigtige slots. Gem-tap → `useBookmarks.toggle(card.personId)`.

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

**Vigtig kontrakt-forskel (dual-review BM1).** Web-storet er *synkront*: `useState(() =>
store.list())` sync-init, sync `has()`/`toggle()`. AsyncStorage er async, så porten er IKKE
"kun en init-effekt" — den kræver et async **lager** + et synkront **hook-state-API** (så
render kan kalde `has()` sync) + race-sikker mutation. Det designes eksplicit her.

### 6.1 Lager (`lib/bookmarks.ts`)

Async repository over `@react-native-async-storage/async-storage`:
- Nøgle `daa_bookmarks`; array af **kanoniske person-id'er**, nyeste-først.
- `createLocalBookmarkStore()`: `list(): Promise<string[]>` og `toggle(id): Promise<string[]>`
  (ingen `has()` — render læser fra hook-state, ikke lageret).
- `canonicalize()` + newest-first-dedup: ren logik porteret 1:1 fra web (uændret).
- Skrivefejl sluges (ikke-kritisk PoC).

### 6.2 Hook (`useBookmarks(canonicalIdById)`)

- **Render-sandhed synkron:** hook'en holder `idsList: string[]` i `useState` og eksponerer
  `ids: Set` (memoiseret) + `has(id) = ids.has(canon(id))` — sync, som web.
- **Hydrering:** initial `list()` loades i en `useEffect` (tom ved allerførste render → badge
  kan gå 0→N ved mount; acceptabelt for PoC).
- **Dep = mappet, ikke funktionen (dual-review BM2/D):** hook'en tager `canonicalIdById`
  (`Record<string,string>` fra store) og udleder en memoiseret `canon`. Re-normalisering køres
  når *mappet* skifter identitet (recollapse). Den stabile Zustand-`canonicalId`-funktion ville
  ALDRIG signalere recollapse — derfor mappet.
- **Race-sikker toggle:** `toggle` opdaterer `idsList` optimistisk (funktionel `setState`) og
  persisterer async; seneste-skrivning-vinder (skrivninger serialiseres, eller stale writes
  ignoreres via en write-generation-tæller), så hurtige toggles ikke taber/dublerer bogmærker.

### 6.3 Skærm (`app/bogmaerker.tsx`)

Person-rækker (`InitialBadge` + navn + år) fra bogmærke-id'erne mappet gennem `model.byId`.
Tap → `/person/<id>`. Tom-tilstand når intet gemt. Rutes til fra drawer + top-bar-ikon.

### 6.4 Badge

Top-bar-bogmærke-ikonet viser `savedCount` (antal gemte) når > 0.

### 6.5 Test (`lib/__tests__/bookmarks.test.ts`)

Port af web's `bookmarks.test.ts` mod en AsyncStorage-mock (jest): toggle, canonicalisering,
dedup, nyeste-først, tom-tilstand. **PLUS async/race-cases (dual-review NEW3):**
- forsinket `list()`-read (hydrering) → hook opdaterer state når promise resolver.
- `canonicalIdById`-map skifter under hydrering → re-normalisering køres.
- hurtige på-hinanden toggles → ingen tabte/dublerede bogmærker (seneste-vinder).
- afvist AsyncStorage-skrivning → UI crasher ikke, state forbliver konsistent.
- unmount under in-flight write → ingen setState-efter-unmount.

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
- **AsyncStorage-async vs. web-sync** (dual-review BM1): ikke bare en init-effekt — kræver
  async-lager + synkront hook-state-API (`has()` i render) + race-sikker toggle. Isoleret til
  `lib/bookmarks.ts` + hook'en; dækket af dedikerede async/race-tests (§6.5).
- **Drawer + tabbar-overlap**: bevidst — drawer er additiv; ingen dublet-navigation fjernes.

## 9. Succeskriterier

- `buildFeed` dækket af unit-tests; determinisme bevist.
- Bogmærke-lager porteret + testet mod AsyncStorage-mock.
- `tsc` + hele eksisterende jest-suite (264+) grøn.
- Forside rendrer feed + top-bar + hero; drawer åbner/navigerer; bogmærker gemmes/vises.
- iOS-simulator-verifikation mod prod-data (jf. projektets etablerede mønster).
- Ingen backend-/model-ændringer.
