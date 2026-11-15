# Webredesign fase 9: mobil web — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Personside, søgning, »Er vi i familie?« og delte links læses godt på en telefon (390 px): sidehovedet fylder én række, personsidens handlinger står ved navnet, felter zoomer ikke, og delte links har en titel og kan deles med telefonens egen deleknap.

**Architecture:** Responsivt web i `web/` (ikke `mobile/`). Smal skærm = `useSmalSkaerm()` (`web/src/useSmalSkaerm.ts`, `(max-width: 720px)`), som stamtræ, søgning og slægtskab allerede bruger. Smalle grene renderes i React (ikke CSS `order`, som bryder tab-rækkefølgen); de få ting inline-stil ikke kan (felternes skriftstørrelse), ligger i `web/src/base.css`. Ingen nye afhængigheder.

**Tech Stack:** React 18 + TypeScript, Vite, vitest + Testing Library (jsdom), Playwright-designtour (`web/scripts/designtour/`).

**Spec:** `docs/design/2026-11-12-webredesign-overdragelse.md` — fase 9 (l. 44), »Tværgående krav« (l. 150-160); tegningerne `project/Mobil-Person.dc.html`, `Mobil-Hovedside.dc.html`, `Slaegtskab-Mobil.dc.html` på canvas »Aarbogen – web redesign« (https://claude.ai/artifact/AodEDRH5DMkuMVRybHWuGd). Omfanget nedenfor er Claudes valg (projektejeren sprang spørgsmålene over 2026-11-15).

## Omfang (målt før-tilstand: `tmp/designtour/fase9-foer/`, designtour-commit f82a3780)

Målt ved 390 px: **intet stikker ud** på nogen af de 37 mobiltrin — accept-kravet »uden vandret scroll« er opfyldt i forvejen. Det, der ikke læses godt:

1. Sidehovedet er tre rækker (≈220 px af 844) og står fast over den rullende side; »Det er mig«-monogrammet brækker ned på en fjerde række.
2. Personsidens handlinger (Vis i stamtræet, Find slægtskab, Kopiér link, Det er mig) og en ≈430 px tom portrætboks står nederst, efter hele bogarket. Familie og embeder har en 140 px etiketspalte, så navnene brækker over tre linjer.
3. »Er vi i familie?«: de valgte personer skæres af midt i datoen (»Otto Reventlow (ca. 1660–24. juni 1700 i Rend«).
4. Felter under 16 px (iPhone zoomer ind ved fokus): sidehovedets søgefelt 14 px, slægtsmenuens 15 px, søgefiltrene fra/til 14 px, sortér 14 px, login 14 px.
5. Delte links: siden hedder altid »DAA-følgesvend · Reventlow (PoC)« (ingen `document.title` pr. side), og »Kopiér link« kan kun kopiere.

**Udenfor (sagt til projektejeren):** bundfaner, »Min plads«, »Indtast kode« og »LOGGET IND« fra `Slaegtskab-Mobil` (afhænger af ubyggede/blokerede dele; tegningens eneste krav, »Det er mig« først, er bygget). Link-forhåndsvisning (Open Graph pr. person) kræver servergengivelse. Slægtsbjælken, stamtræet og hovedsiden er ikke fase 9's sider og røres ikke. Fase 8's udestående (Min plads/præsens, tre småting fra #353) → backlog.

## Global Constraints

- Kun tokens fra `web/src/theme.ts` / `@daa/theme`; ingen tekst under 11 px; `gold` aldrig som tekstfarve (`goldInk`).
- Rigtige `<button>`/`<a href>`; alt kan bruges med tastatur; `aria-expanded` på knapper, der åbner noget; Esc lukker og sender fokus tilbage til knappen; klik udenfor lukker; ingen hover-åbning.
- Bred skærm (> 720 px) må ikke ændre sig — eksisterende tests og designtour-trin `a-*`/`b-*`/`c-*` er facit.
- Berøringsflader ≥ 44 px på smal skærm.
- Smal gren testes ved at mocke `useSmalSkaerm`, som `web/src/components/__tests__/RelateView.test.tsx:9-10` gør (`vi.hoisted` + `vi.mock('../../useSmalSkaerm', …)`); jsdom regnes ellers bred.
- Commits: Conventional Commits på dansk, ingen Claude-attribution og ingen Claude-Session-linje.
- Verifikationsgate pr. task: `npm run test -w daa-folgesvend-web` (eller den berørte testfil) + `npx tsc -b web` (som `build` gør); sidste task kører også `npm run build -w daa-folgesvend-web` og mobil `tsc` + jest er urørt (rør ikke `mobile/`).

## Review Focus

1. Mobilmenuen er åben, og læseren går tilbage med browserens tilbage-knap eller følger et link i menuen → menuen skal lukke (Task 4 tester `sti`-skift).
2. Vinduet vendes fra smal til bred (iPad-rotation), mens mobilmenuen er åben → ingen forældreløs åben tilstand; den brede navigation vises normalt (Task 4).
3. Læseren afbryder telefonens delemenu → ingen fejltekst og ingen kopiering bag om ryggen (`AbortError`, Task 2).
4. Personen har intet portræt på smal skærm → ingen tom portrætboks øverst eller nederst (Task 5).
5. 320 px (iPhone SE/mini med stor tekst): sidehovedets række med navn, monogram og menuknap må ikke stikke ud (Task 7 tilføjer 320 px-trin).

---

### Task 1: Felter ≥ 16 px og synlig højde på telefoner

**Files:**
- Modify: `web/src/base.css`
- Modify: `web/src/Folgesvend.tsx:482` (skallens `height: '100vh'`)

**Interfaces:** Produces intet til andre tasks.

- [ ] **Step 1:** Tilføj i `web/src/base.css` en regel for smal skærm, samme grænse som `SMAL_SKAERM`:
  `@media (max-width: 720px){input:not([type=checkbox]):not([type=radio]),select,textarea{font-size:16px!important}}` med en kommentar om iPhone-zoom (`!important` er nødvendigt, fordi felterne har inline `fontSize`).
- [ ] **Step 2:** Skift skallens højde i `Folgesvend.tsx:482` fra `'100vh'` til `'100dvh'` med en kort kommentar: på iPhone er `100vh` højere end det synlige vindue, så bunden gemmes under browserens værktøjslinje. (`Redaktion.tsx` røres ikke.)
- [ ] **Step 3:** Verificér med designtouren (dev-server på 5173 fra denne worktree): `cd web && node scripts/designtour/tour.mjs d-mobile`
  Expected: ingen linje indeholder `felt < 16 px`.
- [ ] **Step 4:** `npm run test -w daa-folgesvend-web` → PASS (uændret antal; før: 1221 bestået / 20 sprunget over). Commit `base.css` + `Folgesvend.tsx`:
  `fix(web): felter på 16 px og dvh-højde på smal skærm`

### Task 2: Del-link og sidetitler

**Files:**
- Create: `web/src/data/delLink.ts`, `web/src/data/sidetitel.ts`
- Test: `web/src/data/__tests__/delLink.test.ts`, `web/src/data/__tests__/sidetitel.test.ts`
- Modify: `web/src/Folgesvend.tsx` (én `useEffect` der sætter `document.title`), `web/index.html` (`<title>Danmarks Adels Aarbog</title>`)

**Interfaces:**
- Produces: `export type DelUdfald = 'delt' | 'kopieret' | 'afbrudt' | 'fejl';`
  `export async function delLink(url: string, titel: string, brugDeling: boolean): Promise<DelUdfald>`
- Produces: `export const VAERK = 'Danmarks Adels Aarbog';`
  `export function sidetitel(s: { mode: Mode; slaegtNavn?: string | null; personNavn?: string | null; aNavn?: string | null; bNavn?: string | null; q?: string | null; besiddelseNavn?: string | null }): string`

- [ ] **Step 1: Write failing tests** for `delLink` (mock `navigator.share`/`navigator.clipboard.writeText` med `vi.stubGlobal` eller `Object.defineProperty`):
  - `brugDeling=true` og `share` findes → kalder `share({ title, url })`, returnerer `'delt'`, kalder ikke clipboard.
  - `share` afviser med `new DOMException('x', 'AbortError')` → `'afbrudt'`, clipboard ikke kaldt.
  - `share` afviser med `NotAllowedError` → falder tilbage til clipboard → `'kopieret'`.
  - `brugDeling=false` → kun clipboard → `'kopieret'`; clipboard afviser → `'fejl'`.
  - `share` mangler → clipboard → `'kopieret'`.
- [ ] **Step 2: Write failing tests** for `sidetitel` (separator `' · '`):
  - `{mode:'home'}` → `'Danmarks Adels Aarbog'`
  - `{mode:'person', personNavn:'Conrad Reventlow'}` → `'Conrad Reventlow · Danmarks Adels Aarbog'`; uden navn → `'Danmarks Adels Aarbog'`
  - `{mode:'relate', aNavn:'A', bNavn:'B'}` → `'A og B · Er vi i familie? · Danmarks Adels Aarbog'`; mangler én → `'Er vi i familie? · Danmarks Adels Aarbog'`
  - `{mode:'soeg', q:'Conrad'}` → `'Søg: Conrad · Danmarks Adels Aarbog'`; uden q → `'Personer · Danmarks Adels Aarbog'`
  - `{mode:'about', slaegtNavn:'Reventlow'}` → `'Reventlow · Danmarks Adels Aarbog'`
  - `{mode:'tree', slaegtNavn:'Reventlow'}` → `` `${labelOfMode('tree')} · Reventlow · Danmarks Adels Aarbog` `` (samme for `estates`, `kort`, `arms`, `praesens`)
  - `{mode:'estates', besiddelseNavn:'Clausholm'}` → `'Clausholm · Danmarks Adels Aarbog'` (besiddelsens egen side vinder over slægtens liste)
  - `{mode:'bookmarks'}` → `'Bogmærker · Danmarks Adels Aarbog'`; `{mode:'ukendtSlaegt'}` → `'Slægt ikke fundet · Danmarks Adels Aarbog'`
- [ ] **Step 3:** Run `npm run test -w daa-folgesvend-web -- delLink sidetitel` → FAIL (moduler findes ikke).
- [ ] **Step 4:** Implementér begge. `delLink`: `brugDeling && typeof navigator.share === 'function'` → `share`; `AbortError` → `'afbrudt'`; anden fejl → clipboard.
- [ ] **Step 5:** I `Folgesvend.tsx`: `useEffect(() => { document.title = sidetitel({...}); }, [...])` med `mode`, slægtens navn (`findSlaegt(parsed.slaegt)?.navn`), `model?.byId[focusId]?.name` når `mode==='person'`, `relA`/`relB`-navne fra `model.byId`, `parsed`s søgeord (det, `SoegView` får som `filtre.q`), og `estatesVist?.find(e => e.id === estateId)?.navn` når `estateId` er sat. Navne kommer kun fra modellen, som RLS allerede har filtreret — samme regel som sidens h1.
- [ ] **Step 6:** `npm run test -w daa-folgesvend-web` + `npx tsc -b web` (som `build` gør) → PASS. Commit:
  `feat(web): sidetitel pr. side og del-link med telefonens deleknap`

### Task 3: Del-knappen på personsiden og i slægtskabsresultatet

**Files:**
- Modify: `web/src/components/PersonSide.tsx` (`kopier`, l. ~75-80, og knappen l. ~290), `web/src/components/RelateView.tsx` (`Resultat.kopier`, l. ~124-127, knappen l. ~165)
- Test: `web/src/components/__tests__/PersonSide.test.tsx`, `web/src/components/__tests__/RelateView.test.tsx`

**Interfaces:** Consumes `delLink`, `DelUdfald` (Task 2). `sidetitel` bruges ikke her; titlen til `share` er sidens titel `document.title`.

- [ ] **Step 1: Failing tests:**
  - PersonSide, smal (mock `useSmalSkaerm` → true, `navigator.share` mocket): knappen hedder `Del`; klik kalder `share` med `url` = `origin + /person/<id>`; status-teksten er tom efter `'delt'` og efter `'afbrudt'`.
  - PersonSide, bred: knappen hedder fortsat `Kopiér link`, og `share` kaldes ikke, selv når den findes (desktop-Safari har `share`; på bred skærm kopierer vi).
  - RelateView, smal: resultatets knap hedder `Del resultatet` og deler `origin + slaegtskabPath(a, b)`; bred: `Kopiér link til resultatet` som før.
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Erstat begge `kopier` med `delLink(url, document.title, smal)`; vis `'Linket er kopieret.'` ved `'kopieret'`, eksisterende fejltekst ved `'fejl'`, intet ved `'delt'`/`'afbrudt'`. PersonSide henter `smal` fra `useSmalSkaerm()` (før det tidlige `return`).
- [ ] **Step 4:** Tests + tsc → PASS. Commit: `feat(web): »Del« på telefonen for personside og slægtskab`

### Task 4: Sidehovedet på smal skærm — én række og en menu

**Files:**
- Modify: `web/src/components/Sidehoved.tsx`, `web/src/Folgesvend.tsx` (ny prop `sti`)
- Test: `web/src/components/__tests__/Sidehoved.test.tsx`

**Interfaces:**
- Consumes: eksisterende props; ny prop `sti: string` (Folgesvend sender `loc.path + loc.search`).
- Produces: ingen nye eksporter. Ved smal skærm sidder `menuKnap`-ref'en på menuknappen (☰), så `SlaegterMenu`s `opener` og Folgesvends fokus-retur peger på en knap, der stadig findes.

Smal skærm (tegningerne `Mobil-Hovedside`/`Mobil-Person`): én række — logo 32 px + »Danmarks Adels Aarbog« 19 px serif (link til `/`, `flex: 1; min-width: 0`), så `ekstra` (»Din plads«-monogrammet), så en 44×44 menuknap med tre streger, `aria-label="Menu"`, `aria-expanded`, `aria-controls="mobilmenu"`. Padding `12px 16px`. Menuknappen åbner et panel (`id="mobilmenu"`, `data-overlay`, placeret som `SlaegterMenu`: `position: absolute; top: 100%; left: 0; right: 0; zIndex: 40`) med, i rækkefølge: søgeformularen (samme `id="sidehoved-soeg"`, fuld bredde), `<nav aria-label="Hovedmenu">` med Personer, Slægter, Slægtskab som lodret liste (≥ 44 px høje), Log ind/Log ud, Redaktion ↗ (kun `visRedaktion`). Bred skærm: uændret markup.

- [ ] **Step 1: Failing tests** (mock `useSmalSkaerm` → true i en `describe('smal skærm')`):
  - Kun menuknappen og forsiden-linket er synlige; `queryByRole('navigation', { name: 'Hovedmenu' })` er null, og søgefeltet findes ikke, før menuen åbnes.
  - Klik på `Menu` → `aria-expanded="true"`, Hovedmenu-navigationen og søgefeltet vises; Personer har `href="/soeg"`.
  - Esc → panelet lukker, fokus på `Menu`-knappen. `mousedown` på `Udenfor` → lukker.
  - Klik på Personer eller Slægtskab → panelet lukker (og `onPersoner`/`onSlaegtskab` kaldes). Indsend søgning → `navigate('/soeg?q=…')` og panelet lukker.
  - Klik på Slægter i panelet → panelet lukker, og `setMenuAaben(true, false, <menuknappen>)` kaldes (slægtsmenuen åbnes).
  - Nyt `sti`-prop (rerender) → panelet lukker. `smal` skifter til false (rerender med mocket værdi) → panelet lukker, og den brede navigation vises.
  - Åbning af panelet lukker en åben slægtsmenu (`setMenuAaben(false)`).
  - `ekstra` renderes i rækken (fx `<span>LC</span>` synlig uden at åbne menuen).
  - De eksisterende brede tests er uændrede og grønne.
- [ ] **Step 2:** Run `npm run test -w daa-folgesvend-web -- Sidehoved` → FAIL.
- [ ] **Step 3:** Implementér smal gren i `Sidehoved` (lokal `const [mobilAaben, setMobilAaben] = useState(false)`; Esc/klik-udenfor-lyttere som i `SlaegterMenu.tsx:31-42`; luk ved `sti`/`smal`-skift med `useEffect`). Send `sti` fra `Folgesvend.tsx`.
- [ ] **Step 4:** Tests + tsc → PASS. Designtour `d-mobile-home`, `d-mobile-menu` (opdatér trinnet: klik `Menu`, så `Slægter`) og nyt trin `d-mobile-menu-aaben` (klik `Menu`): rækken er én linje, panelet læses.
- [ ] **Step 5:** Commit `Sidehoved.tsx`, `Folgesvend.tsx`, testen og `scripts/designtour/tour.mjs`:
  `feat(web): sidehovedet som én række med menu på smal skærm`

### Task 5: Personsiden på smal skærm

**Files:**
- Modify: `web/src/components/PersonSide.tsx`
- Test: `web/src/components/__tests__/PersonSide.test.tsx`

**Interfaces:** Consumes `useSmalSkaerm` (allerede importeret i Task 3).

Smal skærm (`Mobil-Person`): handlingerne flyttes op, ikke dubleres. Rækkefølgen i DOM'en er tab-rækkefølgen.
- `<main>` padding `16px 16px 48px`; `<article>` padding `20px`, gap `28`.
- Bogarkets `<header>`: findes et portræt, står det som 92 px bredt miniaturebillede (4:5, `radius.card`) til venstre for navneblokken (h1 32 px); klik åbner lysboksen som i dag. Intet portræt → ingen boks.
- Lige under headeren: handlingsblokken — `Vis i stamtræet` (primær, fuld bredde), derunder `Find slægtskab` + `Del` side om side, så `Det er mig`/bogmærke, statuslinjen. Samme knapper og samme handlers som i dag, flyttet ud i en lokal komponent (`function Handlinger(...)`), som bred skærm renderer i `<aside>` og smal skærm renderer under headeren.
- `<aside>` på smal skærm: kun slægtskortet (våben, »Til slægtens forside«) og »Vis i præsensliste«; portrætfiguren udgår (billedteksten står i lysboksen — kontrollér `MediaLightbox`; mangler den der, sættes billedteksten under miniaturen i 12 px).
- Familie-`<dl>`: én spalte; `<dt>` som `etiketStil` (mono, 11 px, versaler, `inkMuted`) med `marginTop: 8`.
- Embeder: periodespalten 92 px i stedet for 140.

- [ ] **Step 1: Failing tests** (smal mocket):
  - Med portræt: `getByRole('button', { name: /Vis portrættet af .* større/ })` findes før `h1` i dokumentrækkefølgen (`compareDocumentPosition`), og der er kun én sådan knap.
  - Uden portræt: `queryByRole('img', { name: 'Intet portræt' })` er null.
  - `Vis i stamtræet` kommer før overskriften `Familie` i dokumentrækkefølgen; der findes præcis ét `Find slægtskab`-link og én `Del`-knap.
  - Bred skærm (mock false): `Vis i stamtræet` kommer efter `Familie` (i aside), `Intet portræt`-boksen findes — uændret.
- [ ] **Step 2:** Run → FAIL. **Step 3:** Implementér. **Step 4:** Tests + tsc → PASS; designtour `d-mobile-person` + `d-mobile-person-fuld` + `d-mobile-person-medlem` + `d-mobile-person-slaegtskab` — handlinger inden for første skærm, ingen tom boks, navne på én–to linjer.
- [ ] **Step 5:** Commit: `feat(web): personsiden på telefonen — handlinger ved navnet, familie i én spalte`

### Task 6: Valgte personer i »Er vi i familie?« på smal skærm

**Files:**
- Modify: `web/src/components/RelateView.tsx` (`PersonVaelger`, l. 67-116; `smal` sendes ned som prop)
- Test: `web/src/components/__tests__/RelateView.test.tsx`

- [ ] **Step 1: Failing test** (smal): med `?a=103&b=125`-modellen viser feltet kun navnet (`input.value === valgt.name`), og leveårene står som tekst lige under feltet (mono 12 px, `inkMuted`, `id` koblet til feltet med `aria-describedby`). Bred: feltet viser `Navn (leveår)` som i dag.
- [ ] **Step 2:** Run → FAIL. **Step 3:** Implementér (`vist` uden parentes, når `smal`; samme `onChange`-logik med det kortere `vist`). **Step 4:** Tests + tsc → PASS; designtour `d-mobile-relate-link`, `d-mobile-relate-mig`.
- [ ] **Step 5:** Commit: `fix(web): valgte personer skæres ikke af i slægtskabsfelterne på telefonen`

### Task 7: Designtour efter, færdigbevis og dokumentation

**Files:**
- Modify: `web/scripts/designtour/tour.mjs` (trin ved 320 px: `d-smal320-person`, `d-smal320-relate-link`, `d-smal320-home` med `me: '103'`, så monogrammet står i rækken)
- Modify: `docs/design/2026-11-12-webredesign-overdragelse.md` (under fase 9: »Bygget 2026-11-15 …« + det udeladte), `docs/changelog.md`, `docs/decisions.md` (beslutningen: mobilmenu bag ☰ på ≤ 720 px; bundfaner fravalgt i fase 9)

- [ ] **Step 1:** Tilføj 320 px-trinene. Kør hele mobil-touren: `node scripts/designtour/tour.mjs mobile` og `node scripts/designtour/tour.mjs smal320` → **ingen** `⇔`-linjer (intet stikker ud, intet felt < 16 px). Kopiér billederne til `tmp/designtour/fase9-efter/`.
- [ ] **Step 2:** Bred regression: `node scripts/designtour/tour.mjs a-` → ingen nye `⚠`-linjer i forhold til før; stikprøve af `a-home`, `a-personside-fuld`, `a-relate-link` mod `fase8`/tidligere billeder: uændrede.
- [ ] **Step 3:** Fuld gate: `npm run test -w @daa/core`, `npm run test -w daa-folgesvend-web`, `npm run build -w daa-folgesvend-web`, `npx tsc -b web` (som `build` gør). Alt grønt.
- [ ] **Step 4:** Opdatér de tre dokumenter (kort, dateret). Commit: `docs: mobil web (fase 9)`.
