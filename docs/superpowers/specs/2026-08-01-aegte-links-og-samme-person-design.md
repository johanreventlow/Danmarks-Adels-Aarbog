# Ægte links i web-fladen + tydeligere "Samme person"

**Dato:** 2026-08-01 · **Branch:** `feat/aegte-links` (worktree, brancet fra `origin/main`)

## Problem

To ting, fundet ved brug af redaktør-fladen:

1. **"Samme person" er utydelig.** Identitets-linkene i personeditoren (`web/src/Redaktion.tsx:1863-1867`)
   viser modpartens navn uden årstal og med meta-teksten `denne foldes ind i` / `foldes ind i denne`.
   Man kan ikke se hvilken post der er den kanoniske, og navnet kan ikke klikkes — modsat familie-
   rækkerne lige ovenfor, der sender `onOpen` til `linkRow`.

2. **Næsten ingen links er ægte links.** Al navigation i web-fladen er `<div onClick>` / `<span onClick>`.
   Det betyder ingen højreklik → "åbn i nyt vindue", ingen cmd/ctrl-klik, ingen midterklik, ingen
   tastaturfokus. To elementer *ligner* links (`web/src/Folgesvend.tsx:429`, `web/src/Redaktion.tsx:2065`)
   men kalder `preventDefault()` ubetinget, så cmd-klik dør også der.

## Forudsætning (verificeret)

Ægte `<a href>` virker kun hvis en ny-fane-åbning — en frisk HTTP GET på stien — serveres af appen.
`web/vercel.json` har SPA-rewrite `/(.*) → /index.html`, og `web/src/router.ts` er path-baseret
(ikke hash). Verificeret, ingen deploy-ændring nødvendig i denne omgang.

## Design

### 1. Delt `Link`-primitiv

Ny fil `web/src/Link.tsx` — placeret ved siden af `router.ts` fordi den er routing-infrastruktur.
Ikke i `components/primitives.tsx`, som er dokumenteret Følgesvend-scoped og ikke importeres af
`Redaktion.tsx`.

```tsx
<Link href="/person/42" onNavigate={() => navigateTree('42')} style={…}>Navn</Link>
```

Renderer et `<a href>`. `onClick` falder igennem til browserens egen adfærd når:

- `e.defaultPrevented` (en indre handler har allerede taget klikket)
- `e.button !== 0` (ikke venstreklik)
- `e.metaKey || e.ctrlKey || e.shiftKey || e.altKey`

Ellers `e.preventDefault()` og derefter `onNavigate?.() ?? navigate(href)`.

Højreklik (`contextmenu`) og midterklik (`auxclick`) kræver ingen kode: de fyrer aldrig Reacts
`onClick`, og virker i det øjeblik elementet har et `href`.

`onNavigate` er nødvendig for ikke at bryde eksisterende adfærd. Flere kaldesteder gør mere end at
skifte URL:

- `Folgesvend.navigateTree` sætter `prevFocusId` og pusher history-state
- `Folgesvend.focusOnly` navigerer bevidst **ikke** (Slægtskab-fanen bevarer sit mode)
- `Folgesvend.driftFocus` bruger `replace` frem for `push`
- `Redaktion.tsx:2065` kalder `afslut()` før navigationen

Alle beholder deres handler og får modifier-klik oveni.

### 2. Hvor ankeret sidder

- **Rene kort** (`PersonCard`, søgetræffere) → hele kortet bliver anker.
- **Rækker med indlejrede knapper** → **kun navnet**. Interaktivt indhold inde i `<a>` er ugyldig
  HTML og knækker de indlejrede handlers. Gælder `linkRow` (indeholder ✕, konfidens-chips, ↑↓,
  `flyt→`), bogmærke-rækker og `DetailPanel`s børne-rækker.

### 3. Konverteringsliste

**Redaktion:**
- `linkRow` (`Redaktion.tsx:1769`) får en `href`-parameter ved siden af `onOpen`
- familie-navne: partnere (1795), forældre (1841), børn (1823/1831)
- samme_person-rækker (1863)
- record-listen (browse-visningen)
- `components/OcrKildepanel.tsx:280` ("åbn person")
- `Redaktion.tsx:2065` (allerede et `<a>`, men ubetinget `preventDefault`)

**Følgesvend:**
- `Folgesvend.tsx:429` ("Redaktion ↗", samme ubetingede `preventDefault`)
- `components/primitives.tsx` `PersonCard` + `HomeView`
- `components/TreeView.tsx` (noder), `components/TreeSearch.tsx` (træffere)
- `components/BookmarksView.tsx`
- `components/DetailPanel.tsx` (forældre 111, ægtefælle 170, børn 181)
- `components/NarrativRenderer.tsx` (person-links i prosa)
- `components/EstatesView.tsx` (godser + ejere)

**Bevidst urørt:**
- `components/PresensView.tsx:301/307` — `href="#linje-…"` er in-page-ankre; at sende dem gennem
  `navigate()` ville pushe et fragment som en path.
- `mobile/` (React Native har ingen `<a>`; uden for scope).

**Sti-hjælpere:** Følgesvend-komponenter behøver ikke en ny prop pr. kaldested — person-stien er
altid `/person/<id>`, og `Folgesvend`s path-sync-effekt kanoniserer alias-id'er ved indlæsning
(`navigate(…, { replace: true })`). En `personPath(id)`-helper ved siden af `pathForMode` i
`data/nav.ts` er nok.

### 4. "Samme person"-tydeliggørelse

`Redaktion.tsx:1863-1867` genbruger ordforrådet fra bekræftelsesdialogen `renderSammeSomConfirm`
(2128-2131: *KANONISK (beholdes)* / *FOLDES IND I OVENSTÅENDE*) i stedet for at opfinde et nyt:

`SammeSomLink.retning` er klassificeret **set fra den redigerede person** (`mapSammeSomLinks`,
`data/redaktionRead.ts:711-719`): `'alias'` = den redigerede er subjekt og peger på en kanonisk;
`'kanonisk'` = andre peger på den redigerede. Etiketten i rækken beskriver derimod **modparten**,
hvis navn står der — derfor byttes rollen om:

| `l.retning` | modpartens rolle | række-etiket | undertekst |
|---|---|---|---|
| `'alias'` | kanonisk | `KANONISK · <navn> (år)` | `den post du redigerer foldes ind i denne` |
| `'kanonisk'` | alias | `ALIAS · <navn> (år)` | `foldes ind i den post du redigerer` |

Eksempel:

```
KANONISK · Christian Detlev Reventlow (1671–1738)
den post du redigerer foldes ind i denne
```

Navnet linker til `/redaktion/person/<l.modpartId>` — **rå id, ikke kanoniseret**. Redaktøren
arbejder i skrive-id-rummet (`loadModel({ collapse: false })`, Redaktion.tsx:350-352); en
kanonisering her ville sende brugeren til en anden post end den rækken navngiver.

Årstal hentes fra `persons` (`fetchRedaktionPersoner()`, ikke linje-scopet), som allerede slår
navnet op på linje 1864.

## Antagelser

- Web only. `mobile/` røres ikke.
- Samme fane som default. Intet tvunget `target="_blank"` — brugeren vælger selv via modifier/højreklik.
- Ingen ændring i selve navigationsadfærden ved almindeligt venstreklik: samme mål, samme state,
  samme history-semantik (push vs. replace) som i dag.

## Test

- `web/src/__tests__/Link.test.tsx` i stil med det eksisterende `__tests__/router.test.ts`:
  - almindeligt venstreklik → `preventDefault` kaldt, `window.location.pathname` skifter
  - cmd-/ctrl-/shift-/alt-klik → hverken `preventDefault` eller navigation (browseren får klikket)
  - `button !== 0` → samme
  - `onNavigate` kaldes i stedet for `navigate(href)` når den er sat
  - elementet har et reelt `href`-attribut (det er det højreklik-menuen læser)
- Redaktion-suiten: samme_person-rækken renderer `<a href="/redaktion/person/…">` med rå modpart-id
- Eksisterende suiter skal blive grønne uændret — konverteringen må ikke ændre klik-adfærd.

## Konflikt-hensyn

En parallel session har `web/src/Redaktion.tsx` modificeret på `feat/union-redigering`. Dette
arbejde brancher fra `origin/main` i et separat worktree, og Redaktion-diffen holdes kirurgisk:
`linkRow`s signatur, de navngivne kaldesteder og samme_person-blokken. Ingen drive-by-konvertering
af filens øvrige `<span onClick>`.
