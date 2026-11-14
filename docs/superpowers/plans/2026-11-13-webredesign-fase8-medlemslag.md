# Webredesign fase 8 — personsidens medlemslag: implementeringsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Når »Det er mig« er sat, står slægtskabet til dig over navnet på enhver personside (»Din tipoldefar«,
»Gift med Christian Reventlow, din onkel«); fakta, hvor udgaverne er uenige, får mærket »Uenige kilder«.

**Architecture:** Ren klient. `@daa/core` får én ny ren funktion, der giver slægtskabsordet set fra mig mod
fokuspersonen. `web/src/data/slaegtskab.ts` samler den med `computeRelationship` og ægtefælleindekset til en lille
tilstandstype, og `PersonSide` viser den på pladsen over `<h1>`. Mærket bygger på de noter, `byggUdgaveFakta`
allerede leverer. Ingen DB-ændringer, ingen nye RPC'er.

**Tech Stack:** TypeScript, React 18, vitest + Testing Library (jsdom), npm workspaces.

**Spec:** Der er ingen separat spec, fordi projektejeren sprang spørgsmålene over (2026-11-13). Grundlaget er
`docs/design/2026-11-12-webredesign-overdragelse.md:98-109` (personsiden og medlemslaget), `docs/decisions.md`
2026-11-13 (»Det er mig« i to trin, pkt. 3) og afsnittet **Valg truffet i planen** nedenfor, som projektejeren
godkender sammen med planen.

## Valg truffet i planen (godkendt af projektejeren 2026-11-14)

1. **Sætningen står uden navn:** der står »Din tipoldefar« lige over navnet, ikke »Conrad er din tipoldefar«.
   Navnet står jo i overskriften lige under, og modellen har intet felt for fornavn.
2. **Indgiftede kommer med:** er fokuspersonen gift med en af dine blodslægtninge, står der »Gift med Christian
   Reventlow, din onkel« (ægtefællen som link). Er der flere sådanne ægtefæller, vælges den nærmeste slægtning.
   Usikkerheden sidder på blodsforbindelsen, ikke på ægteskabet: »Gift med Christian Reventlow, sandsynligvis din
   onkel« og »… , omstridt: din onkel«. »Se vejen« fører til vejen mellem dig og ægtefællen.
   Er fokuspersonen din egen ægtefælle, står der »Din ægtefælle«.
3. **Ikke med:** slægt gennem din ægtefælle (svigerforældre, svogre), og slægt gennem to giftermål. Det kræver en
   graf over ægteskaber og hører til »Er vi i familie?«, ikke til en linje på personsiden.
4. **Usikkerhed vises altid (invariant 7):** en vej med et formodet led får »Sandsynligvis« foran; et omstridt led
   får »Omstridt:«. Bekræfter en anden, sikker vej slægtskabet, tilføjes »· bekræftet ad en anden linje«, samme ord
   som »Er vi i familie?«.
5. **Mere end én vej:** linket »Se vejen« (eller »Se alle N veje«) fører til `/slaegtskab?a=<mig>&b=<fokus>`.
   Personsiden nævner **ikke** dobbelt slægtskab. Ordet kommer altid fra den nærmeste linjes egne `d1`/`d2`, og
   sikkerheden fra samme linje. Linjen påstår altså kun det, én bestemt vej bærer.
   Grunden er Codex-review 13/11: core slår linjer sammen efter etiket. Ved sammenlægningen arves kun
   repræsentantens konfidens (`relationship.ts:281-302`), og to linjer med modsat retning kan få samme etiket
   (»Onkel & nevø«). »Dobbelt« kunne derfor skjule et omstridt led eller blande onkel og nevø. »Er vi i familie?«
   har samme svaghed; den står i backlog (task 6) og hører ikke til fase 8.
6. **Ingen forbindelse siges med ord:** »Aarbogen viser ingen fælles ane med dig« i dæmpet tekst. Der står »fælles
   ane« og ikke »slægtskab«, fordi svigerfamilie bevidst ikke undersøges (valg 3). Uden »Det er mig«
   vises intet, og pladsen fylder intet. Login betyder intet her, så det ændrer ikke kravet om intet layoutskift
   ved login.
7. **POC-reglen for levende kræver ingen kode:** gæster og almindelige brugere har ingen levende personer i modellen,
   så en levende »mig« findes kun for redaktionen (decisions 2026-11-13, pkt. 2). Findes »mig« ikke i modellen,
   vises intet. Det må **ikke** »rettes« med et DB-kald.
8. **Ord i dybe led:** rækkerne følger `relationshipLabel` præcis, så personsiden og »Er vi i familie?« aldrig
   uenige. Grandonkel og grandnevø bruges også ved større forskydning, og fra 5 led står der »din ane, N slægtled
   tilbage« og »din efterkommer, N slægtled frem«.
9. **»Uenige kilder« venter på en måling:** lighedsreglen (`factEquality.ts`) er bevidst forsigtig, så en ren
   skrivemåde-forskel kan ende som en »skriver«-note. Task 4 måler det først, og projektejeren vælger derefter ord
   og vægt. Slægtskabslinjen (task 1-3) afhænger ikke af målingen.
10. **Mærket står både på personsiden og i stamtræets panel:** `PersonFakta` er fælles, og de to steder skal være ens.

## Global Constraints

- Implementering starter først efter projektejerens »go«. En parallel session arbejder i de samme dele af
  databasen; se task 0.
- Kun designtokens (`T.*`, `@daa/theme`). Ingen tekst under 11 px. `T.gold` aldrig som tekstfarve (`T.goldInk`).
- Usikkerhed skjules aldrig (invariant 7). Mangler siges med ord.
- `relationshipLabel`'s signatur og output røres ikke, fordi mobil og »Er vi i familie?« bruger den.
- Commits: Conventional Commits på dansk, uden Claude-Session- eller attributionslinje (projektejerens præference).
  Én commit pr. task. Ingen push uden frisk ja; PR altid `--draft`.
- Arbejdet sker på planens gren `docs/webredesign-fase8-plan`. Den rebases på main og omdøbes til
  `feat/webredesign-fase8-medlemslag-v2` i task 0, så plan og kode ender i samme PR. Den gamle
  `feat/webredesign-fase8-medlemslag` røres ikke uden projektejerens ja.
- Den fulde kontrol er CI's node-job (`.github/workflows/ci.yml:55-102`). Lokalt kører man de samme kommandoer, se
  task 6.

## Review Focus

1. **Køn ukendt (`koen: null`):** ordet bliver kønsneutralt (»din onkel/tante«, »dit barnebarn«), aldrig et gæt.
   Testes i task 1.
2. **»Mig« er alias for samme person (samme_som):** står jeg på min egen side via et alias-id, skal der stå »Det er
   dig« og ikke »Samme person«. Det er en kontrakt og ingen ny test: `Folgesvend.tsx` sender `meCanon`, den samme
   kanoniske værdi, som `erMig={focusId === meCanon}` allerede bruger (`Folgesvend.tsx:424-427`). `focusId` er
   kanonisk. `slaegtskabsKontekst` kanoniserer ikke selv.
3. **Fokuspersonen er både blodslægtning og ægtefælle (fætter-kusine-ægteskab):** »Din ægtefælle« vinder. Testes i
   task 2.
4. **Ægtefælle uden id (`spousesBy` med `id: null`, kun navn):** springes over i ægtefællereglen og må ikke kaste
   en fejl. Testes i task 2.
5. **»Det er mig« slås til eller fra på selve siden:** linjen skifter med det samme (»Det er dig« ↔ ingen linje)
   uden genindlæsning. Testes i task 3.

---

### Task 0: Gate — vent på den parallelle session, og genbekræft grundlaget

**Files:** ingen.

- [ ] **Step 1:** Spørg projektejeren, om den parallelle DB-session er merget. Fortsæt kun på et eksplicit »go«.
- [ ] **Step 2:** `git fetch origin`, `git switch docs/webredesign-fase8-plan`, `git rebase origin/main`,
  `git branch -m feat/webredesign-fase8-medlemslag-v2`. Kontrollér med `git branch -vv`, at grenen ikke har
  `origin/main` som upstream, så et senere push ikke rammer main.
- [ ] **Step 3:** `npm ci` fra roden, derefter `npm run test -w @daa/core` og `npm run test -w web`.
  Forventet: begge grønne. Notér eventuelle fejl, der findes på main i forvejen (`feed.spec` i e2e fejler kendt på
  main), før der ændres noget.
- [ ] **Step 4:** Bekræft, at disse stadig findes med samme form, og stop og meld tilbage, hvis ikke:
  `computeRelationship`/`RelationLine` (`packages/core/src/relationship.ts`), `model.indexes.spousesBy`,
  `UdgaveNote`/`UdgaveFaktaLinje` (`packages/core/src/editionFacts.ts:28-40`) og `PersonSide.tsx`'s plads-kommentar
  over `<h1>`.

### Task 1: core — slægtskabsordet set fra mig

**Files:**
- Modify: `packages/core/src/relationship.ts` (ny eksport efter `relationshipLabel`)
- Modify: `packages/core/src/index.ts` (eksportér, hvis index ikke re-eksporterer hele modulet)
- Test: `packages/core/src/__tests__/relationship.test.ts` (ny `describe`)

**Interfaces:**
- Produces: `slaegtskabTilMig(d1: number, d2: number, opts?: { koen?: Koen; half?: boolean }): string`, med små
  bogstaver og pronomen, fx `'din onkel'` og `'dit barnebarn'`. `d1` er afstanden mig→fælles ane og `d2` er
  afstanden fokus→fælles ane, dvs. `computeRelationship(model, mig, fokus)`. `koen` er **fokuspersonens** køn.
  `(0,0)` giver `''` (kalderen håndterer »dig«).

- [ ] **Step 1: Skriv de fejlende tests** (`describe('slaegtskabTilMig — ordet set fra mig')`):

```ts
const m = { koen: 'mand' as const }, k = { koen: 'kvinde' as const };
expect(slaegtskabTilMig(1, 0, m)).toBe('din far');
expect(slaegtskabTilMig(1, 0, k)).toBe('din mor');
expect(slaegtskabTilMig(1, 0)).toBe('din forælder');
expect(slaegtskabTilMig(2, 0, m)).toBe('din bedstefar');
expect(slaegtskabTilMig(3, 0, k)).toBe('din oldemor');
expect(slaegtskabTilMig(4, 0, m)).toBe('din tipoldefar');
expect(slaegtskabTilMig(6, 0, m)).toBe('din ane, 6 slægtled tilbage');
expect(slaegtskabTilMig(0, 1, m)).toBe('din søn');
expect(slaegtskabTilMig(0, 1)).toBe('dit barn');
expect(slaegtskabTilMig(0, 2, k)).toBe('dit barnebarn');
expect(slaegtskabTilMig(0, 3)).toBe('dit oldebarn');
expect(slaegtskabTilMig(0, 4)).toBe('dit tipoldebarn');
expect(slaegtskabTilMig(0, 5)).toBe('din efterkommer, 5 slægtled frem');
expect(slaegtskabTilMig(1, 1, m)).toBe('din bror');
expect(slaegtskabTilMig(1, 1, k)).toBe('din søster');
expect(slaegtskabTilMig(1, 1)).toBe('dit søskende');
expect(slaegtskabTilMig(1, 1, { koen: 'mand', half: true })).toBe('din halvbror');
expect(slaegtskabTilMig(2, 1, m)).toBe('din onkel');          // fokus er ældre (d2 < d1)
expect(slaegtskabTilMig(2, 1)).toBe('din onkel/tante');
expect(slaegtskabTilMig(1, 2, k)).toBe('din niece');          // fokus er yngre
expect(slaegtskabTilMig(1, 2)).toBe('din niece/nevø');         // samme rækkefølge som relationshipLabel
expect(slaegtskabTilMig(1, 3)).toBe('din grandniece/-nevø');
expect(slaegtskabTilMig(3, 1, k)).toBe('din grandtante');
expect(slaegtskabTilMig(1, 3, m)).toBe('din grandnevø');
expect(slaegtskabTilMig(2, 1, { koen: 'mand', half: true })).toBe('din onkel (halv)');
expect(slaegtskabTilMig(2, 2, m)).toBe('din 1. grads fætter');
expect(slaegtskabTilMig(2, 2, k)).toBe('din 1. grads kusine');
expect(slaegtskabTilMig(2, 2)).toBe('din 1. grads fætter/kusine');
expect(slaegtskabTilMig(3, 2, m)).toBe('din 1. grads fætter · 1 gang forskudt');
expect(slaegtskabTilMig(4, 2, k)).toBe('din 1. grads kusine · 2 gange forskudt');
expect(slaegtskabTilMig(3, 3, { koen: 'mand', half: true })).toBe('din 2. grads fætter (halv)');
expect(slaegtskabTilMig(0, 0)).toBe('');
```

Retning, store forskydninger og neutrale halvformer skal også have konkrete forventninger:

```ts
expect(slaegtskabTilMig(4, 1, m)).toBe('din grandonkel');      // forskydning 3 → stadig grand- (valg 8)
expect(slaegtskabTilMig(1, 4)).toBe('din grandniece/-nevø');
expect(slaegtskabTilMig(5, 2, k)).toBe('din 1. grads kusine · 3 gange forskudt');
expect(slaegtskabTilMig(2, 5, m)).toBe('din 1. grads fætter · 3 gange forskudt');
expect(slaegtskabTilMig(1, 1, { half: true })).toBe('dit halvsøskende');
expect(slaegtskabTilMig(2, 2, { half: true })).toBe('din 1. grads fætter/kusine (halv)');
expect(slaegtskabTilMig(1, 2, { half: true })).toBe('din niece/nevø (halv)');
```

Tilføj en begrænset krydstest. Den kontrollerer kun ikke-tomhed og gradtal, ikke retning: for alle
`d1,d2 ∈ 0..5` (undtagen 0,0) skal `relationshipLabel(d1, d2)` og `slaegtskabTilMig(d1, d2)` begge være
ikke-tomme. For `minD ≥ 2` skal gradtallet (`/(\d+)\. grads/`) være det samme i begge.

- [ ] **Step 2:** `npm run test -w @daa/core -- relationship`. Forventet: FAIL (`slaegtskabTilMig` er ikke defineret).
- [ ] **Step 3:** Implementér med samme rækker som `relationshipLabel` (`relationship.ts:135-177`): direkte linje
  n=1..4 og derefter fallback; søskendeplanet; onkel/nevø ved forskydning 1 og grand- ved ≥2, hvor `d2 < d1` betyder,
  at fokus er den ældre; fætter/kusine med grad `min(d1,d2)-1` og forskydning `|d1-d2|`. Brug `g()` til kønsordet.
  Pronomenet er `dit` for barn, barnebarn, oldebarn, tipoldebarn og søskende, ellers `din`. Genbrug `g()`/`gendered()`
  fra filen, og lav ingen ny kønslogik.
- [ ] **Step 4:** `npm run test -w @daa/core` og `npm run typecheck -w @daa/core`. Forventet: PASS, og ingen
  eksisterende `relationshipLabel`-test ændret.
- [ ] **Step 5: Commit** — `git add packages/core/src/relationship.ts packages/core/src/index.ts packages/core/src/__tests__/relationship.test.ts`
  og `git commit -m "feat(core): slægtskabsordet set fra mig (slaegtskabTilMig)"`.

### Task 2: web data — slægtskab som kontekst

**Files:**
- Modify: `web/src/data/slaegtskab.ts` (ny eksport nederst)
- Test: `web/src/data/__tests__/slaegtskab.test.ts` (opret, hvis den ikke findes). Modellen bygges med `buildModel`
  som i `packages/core/src/__tests__/relationship.test.ts:1-25`, udvidet med `koen: 'mand'` på B og A2 og med
  personerne `S` og `X` (begge uden forældre). Disse unioner tilføjes: `{ id: 'uSB', p1: 'S', p2: 'B' }`,
  `{ id: 'uSA2', p1: 'S', p2: 'A2' }`, `{ id: 'uAB', p1: 'A', p2: 'B' }` (fætter-kusine-ægteskab) og
  `{ id: 'uS0', p1: 'S', p2: null, p2_name: 'Ukendt' }` (ægtefælle uden id). `X` har ingen unioner.
  `buildModel` fylder `spousesBy` i begge retninger (`buildModel.ts:50-62`).

**Interfaces:**
- Consumes: `slaegtskabTilMig` (task 1), `computeRelationship` og `model.indexes.spousesBy`.
- Produces:

```ts
export type Sikkerhed = 'sikker' | 'sandsynligvis' | 'omstridt';
// Fælles for blod og gift: beskriver forbindelsen mig ↔ blodslægtningen (fokus selv eller fokus' ægtefælle).
export type Forbindelse = { ord: string; sikkerhed: Sikkerhed; bekraeftetAndenVej: boolean; veje: number };
export type SlaegtskabsKontekst =
  | { art: 'skjult' }                                   // »Det er mig« ikke sat, eller mig findes ikke i modellen
  | { art: 'dig' }
  | { art: 'min-aegtefaelle' }
  | ({ art: 'blod' } & Forbindelse)
  | ({ art: 'gift'; aegtefaelleId: string; aegtefaelleNavn: string } & Forbindelse)
  | { art: 'ingen' };
export function slaegtskabsKontekst(model: Model, meId: string | null, focusId: string): SlaegtskabsKontekst;
```

`ord` er uden stort begyndelsesbogstav (fra `slaegtskabTilMig`) og bygges af `lines[0].d1`/`d2`/`half`, aldrig af
`label` eller `multiplicitet` (valg 5). `sikkerhed` kommer fra `lines[0]`. `veje = lines.length`.

- [ ] **Step 1: Skriv de fejlende tests**, én `it` pr. regel. Prioriteten er: skjult → dig → min-aegtefaelle → blod
  → gift → ingen.
  - `meId` er null → `{ art: 'skjult' }`. `meId` findes ikke i `model.byId` → `skjult`.
  - `meId === focusId` → `dig`.
  - mig=A, fokus=B → `min-aegtefaelle`, selv om de også er fætre (fætter-kusine-ægteskab).
  - mig=A2, fokus=B → `{ art: 'blod', ord: 'din 1. grads fætter', sikkerhed: 'sikker', veje: 1, bekraeftetAndenVej: false }`.
  - Samme med `konfidens: 'formodet'` på kanten B→P2 → `sikkerhed: 'sandsynligvis'`, `bekraeftetAndenVej: false`.
    Med `'omstridt'` → `'omstridt'` (fra `lines[0].usikker` og `lines[0].weakestKonfidens`).
  - `bekraeftetAndenVej` følger reglen fra `RelateView.tsx:143`: `lines[0].usikker`, og der findes en anden linje,
    der ikke er usikker. Den positive test bruger en egen model bygget som fixturen i
    `packages/core/src/__tests__/relationship.test.ts:383-413` (nær usikker linje, fjern sikker linje), med
    forventningen `bekraeftetAndenVej: true` og `veje: 2`. Samme model uden det usikre led → `false`.
  - Ordet følger den nærmeste linjes egen retning, ikke den sammenlagte etiket. Brug Codex' graf som egen model:
    G1 er forælder til A og P, P er forælder til B; G2 er forælder til B og Q, Q er forælder til A; alle mænd.
    Fokus er her både nevø og onkel til mig. Assertér, at `ord === slaegtskabTilMig(lines[0].d1, lines[0].d2, …)`,
    og at resultatet ikke indeholder »dobbelt«.
  - mig=A, fokus=S (gift med B og A2, ingen forældre) → `{ art: 'gift', ord: 'din bror', aegtefaelleId: 'A2', aegtefaelleNavn: 'A2', sikkerhed: 'sikker', veje: 1, bekraeftetAndenVej: false }`.
    A2 vinder over B, fordi `d1+d2` er 2 mod 4. S's ægtefælle uden id (`uS0`) springes over uden fejl. Det gør en
    ægtefællepost med `id === focusId` også (`spousesBy` har ingen vagt mod selvreference, `buildModel.ts:53-65`).
  - Samme med `konfidens: 'formodet'` på kanten A2→P1 → `gift` med `sikkerhed: 'sandsynligvis'`.
  - mig=A, fokus=X → `ingen`.
- [ ] **Step 2:** `npm run test -w web -- slaegtskab`. Forventet: FAIL.
- [ ] **Step 3:** Implementér `slaegtskabsKontekst` i `web/src/data/slaegtskab.ts`. Til ord og køn bruges
  `computeRelationship(model, meId, focusId).lines[0]` og `slaegtskabTilMig(line.d1, line.d2, { koen: model.byId[focusId].koen, half: line.half })`.
  Ægtefællereglen kører `computeRelationship(model, meId, s.id)` for hver ægtefælle med id (undtagen `focusId`).
  Den vælger mindst `lines[0].d1 + lines[0].d2`, og ordet bruger **ægtefællens** køn. Det er ægtefællen, der er
  slægtningen. `Forbindelse` bygges af én fælles hjælper til både blod og gift.
- [ ] **Step 4:** `npm run test -w web -- slaegtskab`. Forventet: PASS.
- [ ] **Step 5: Commit** — `git add web/src/data/slaegtskab.ts web/src/data/__tests__/slaegtskab.test.ts` og
  `git commit -m "feat(web): slægtskab som kontekst beregnet fra »Det er mig«"`.

### Task 3: web UI — linjen over navnet

**Files:**
- Create: `web/src/components/SlaegtskabsLinje.tsx` (ren visning af en `SlaegtskabsKontekst`)
- Test: `web/src/components/__tests__/SlaegtskabsLinje.test.tsx` (bogstavelige kontekst-objekter, ingen model)
- Modify: `web/src/components/PersonSide.tsx` (prop `meId` og pladsen over `<h1>`, i dag kommentaren »Plads til
  medlemslagets …«; opdatér filhovedets kommentar om fase 8)
- Modify: `web/src/Folgesvend.tsx:517` (send `meId={meCanon}`)
- Test: `web/src/components/__tests__/PersonSide.test.tsx` (kun wiring)

**Interfaces:**
- Consumes: `slaegtskabsKontekst`/`SlaegtskabsKontekst` (task 2), `slaegtskabPath(a, b)` og `personPath(id)` fra
  `../data/nav`.
- Produces: `SlaegtskabsLinje({ kontekst, meId, focusId, onVisPerson }: { kontekst: SlaegtskabsKontekst; meId: string | null; focusId: string; onVisPerson: (id: string) => void })`,
  som returnerer `null` ved `skjult`. Desuden en ny valgfri prop `meId?: string | null` på `PersonSide` (default
  `null`). `erMig`/`onToggleMig` er uændrede.

- [ ] **Step 1: Skriv de fejlende tests for `SlaegtskabsLinje`.** Den præcise tekst (`toHaveTextContent` på
  `getByTestId('slaegtskab-kontekst')`) er:
  - `skjult` → intet renderes.
  - `dig` → `Det er dig`. `min-aegtefaelle` → `Din ægtefælle`. `ingen` → `Aarbogen viser ingen fælles ane med dig`.
  - `blod`, `ord: 'din 1. grads fætter'`, sikker, `veje: 1` → `Din 1. grads fætter` og et link `Se vejen` med
    `href` = `slaegtskabPath(meId, focusId)`. Med `veje: 2` → linkteksten `Se alle 2 veje`.
  - `blod` sandsynligvis → `Sandsynligvis din 1. grads fætter`. Omstridt → `Omstridt: din 1. grads fætter`.
    `bekraeftetAndenVej: true` → `· bekræftet ad en anden linje` efter ordet.
  - `gift`, `ord: 'din onkel'`, `aegtefaelleNavn: 'Christian Reventlow'`, sikker, `veje: 1` → `Gift med Christian Reventlow, din onkel`.
    Navnet er et link til `personPath(aegtefaelleId)`, og et klik kalder `onVisPerson(aegtefaelleId)`. `Se vejen`
    peger på `slaegtskabPath(meId, aegtefaelleId)`. Med `veje: 2` → `Se alle 2 veje`.
  - `gift` sandsynligvis → `Gift med Christian Reventlow, sandsynligvis din onkel`. Omstridt →
    `Gift med Christian Reventlow, omstridt: din onkel`. Med `bekraeftetAndenVej: true` →
    `· bekræftet ad en anden linje` efter ordet, som ved blod.
  - Ingen tilstand renderer ordet »dobbelt« (valg 5).
- [ ] **Step 2: Skriv de fejlende wiring-tests i `PersonSide.test.tsx`** (Conrad-fixturen): uden `meId` er
  `queryByTestId('slaegtskab-kontekst')` null. Med `meId === focusId` står der `Det er dig`. Efter `rerender` med
  `meId={null}` forsvinder linjen (Review Focus 5).
- [ ] **Step 3:** `npm run test -w web -- SlaegtskabsLinje PersonSide`. Forventet: de nye tests fejler, de gamle er
  grønne.
- [ ] **Step 4:** Implementér `SlaegtskabsLinje` som ét `<p data-testid="slaegtskab-kontekst">`. Stil: `T.serif`,
  17 px, kursiv, `T.bordeaux`. »Sandsynligvis«/»Omstridt:« i `T.danger` som `konf`-ordet i `PersonLink`.
  `ingen` i `T.inkMuted`, ikke kursiv. Links i `T.bordeaux` via `Link`: ægtefællen med
  `onNavigate={() => onVisPerson(id)}`, »Se vejen« uden handler (routeren tager `/slaegtskab`). Stort
  begyndelsesbogstav sættes kun i visningen.
- [ ] **Step 5:** I `PersonSide` beregnes `const kontekst = useMemo(() => slaegtskabsKontekst(model, meId, focusId), [model, meId, focusId])`
  **før** `if (!p) return null` (hook-rækkefølge). `SlaegtskabsLinje` renderes på pladsen over `<h1>`. I
  `Folgesvend.tsx` sendes `meId={meCanon}` ved siden af `erMig`.
- [ ] **Step 6:** `npm run test -w web`. Forventet: PASS.
- [ ] **Step 7: Commit** — `git add web/src/components/SlaegtskabsLinje.tsx web/src/components/__tests__/SlaegtskabsLinje.test.tsx web/src/components/PersonSide.tsx web/src/Folgesvend.tsx web/src/components/__tests__/PersonSide.test.tsx`
  og `git commit -m "feat(web): personsiden viser slægtskabet til dig over navnet"`.

### Task 4: Mål »skriver«-noterne, før »Uenige kilder« bygges (beslutningspunkt)

**Files:** ét script i sessionens scratchpad-mappe. Det committes ikke.

- [ ] **Step 1:** Skriv et read-only script, der genbruger webbens egen datalæsning præcis, som en gæst ser
  personsiden. Det køres med `npx vite-node <script>` fra `web/`, så Vites `import.meta.env` virker; ingen ændring i
  `web/src`.
  - **Population:** `loadModel()` (`web/src/data/model.ts:58`) som gæst giver de kanoniske, offentlige personer.
  - **Pr. person:** fakta hentes som `Folgesvend.tsx:202-207` gør:
    `fetchPersonDetail(id, personMemberIds(id, model.byId[id]), false, { udgaver: model.udgaver ?? [], udgaveForPersonRaekke: model.udgaveForPersonRaekke ?? {} }, false)`.
    Det sker én person ad gangen, så alle aliasposter samles pr. foldet person, og intet blandes mellem personer.
    Personer, hvis `faktaInput` dækker færre end to udgaver, springes over.
  - **Tælleenhed:** én person × valgt udgave × linjenøgle. For hver udgave som valgt køres
    `byggUdgaveFakta(detail.faktaInput, valgt)`. Der tælles linjer med `vaerdi !== ''`, `!omstridt` og mindst én note
    `art: 'skriver'`. Det er netop de linjer, task 5 ville mærke.
  - Scriptet læser kun offentlige data. Anon-nøglen hentes fra env og printes aldrig.
- [ ] **Step 2:** Output: antal personer, antal linjer med »skriver«-note pr. faktatype, og 25 tilfældige eksempler
  med `valgt værdi` ↔ `anden udgaves værdi`. Hvert eksempel sorteres i hånden: *skrivemåde* (samme betydning) eller
  *reel uenighed*.
- [ ] **Step 3:** Vis tallene for projektejeren, og få et valg mellem:
  (a) mærket »Uenige kilder« på alle »skriver«-linjer,
  (b) kun på reelle uenigheder; det kræver først en strammere lighedsregel og en ny plan, og task 5 udgår,
  (c) intet mærke; den eksisterende note »DAA 1939 skriver: …« er nok.
  Task 5 udføres kun ved (a).

### Task 5 (kun ved valg a): mærket »Uenige kilder«

**Files:**
- Modify: `web/src/components/PersonFakta.tsx` (rækken med `omstridt`-mærket, ca. linje 64-66)
- Test: `web/src/components/__tests__/PersonFakta.test.tsx`

- [ ] **Step 1: Skriv de fejlende tests:** en linje med en note `{ art: 'skriver', … }` og `omstridt: false` →
  `screen.getByText('Uenige kilder')`. Med kun `enig`-noter → intet mærke. Med `omstridt: true` → kun
  `omstridt`-mærket, ikke begge. Med `vaerdi: ''` → intet mærke (noterne vises heller ikke der).
- [ ] **Step 2:** `npm run test -w web -- PersonFakta`. Forventet: FAIL.
- [ ] **Step 3:** Vis mærket med præcis samme stil som `omstridt`-mærket. Teksten er `Uenige kilder`; CSS må gerne
  vise den med versaler.
- [ ] **Step 4:** Hele web-suiten. Forventet: PASS (panelet i stamtræet bruger samme komponent; valg 10).
- [ ] **Step 5: Commit** — `git add web/src/components/PersonFakta.tsx web/src/components/__tests__/PersonFakta.test.tsx`
  og `git commit -m "feat(web): fakta, hvor udgaverne er uenige, mærkes »Uenige kilder«"`.

### Task 6: Dokumentation og den fulde kontrol

**Files:**
- Modify: `docs/decisions.md` (ny `BESLUTTET`-post øverst: valg 1-8 og 10 som godkendt og valget fra task 4,
  plus en `NOTERET`-backlogpost: »Er vi i familie?« viser »Dobbelt …« med kun repræsentantens konfidens og kan slå
  linjer med modsat retning sammen (`relationship.ts:281-302`; Codex-review 13/11))
- Modify: `docs/changelog.md` (dateret post)
- Modify: `docs/design/2026-11-12-webredesign-overdragelse.md:107-109` (fase 8 bygget; hvad der udgik)

- [ ] **Step 1:** Skriv de tre dokumenter. Decisions-posten citerer projektejerens godkendelse ordret.
- [ ] **Step 2:** Den fulde kontrol med præcis de kommandoer, CI's node-job kører (`.github/workflows/ci.yml:55-102`).
  Brug Read-værktøjet til filen, fordi shell-vagten afviser stier med `.github`: `npm run test -w @daa/core`,
  `npm run typecheck -w @daa/core`, `npm run test -w web`, `npm run build -w web`,
  `npm --workspace mobile exec -- tsc --noEmit` og `npm test -w mobile` (core-ændringen rammer også mobil). Web
  kræver dummy-env i `web/.env.local` som i CI, hvis der ikke allerede findes en fil. Overskriv aldrig en eksisterende.
  Forventet: alt grønt.
- [ ] **Step 3:** `npm run dev -w web`. Sæt »Det er mig« på en person, og se linjen på en fætter, en ane, en
  indgiftet ægtefælle og en person uden forbindelse, også ved 390 px bredde. Tag et skærmbillede pr. tilstand til
  PR'en. Forvent »Sandsynligvis« på veje gennem 1939-forældreled, der står som formodet. Det er korrekt efter
  invariant 7, men memory-noten om falske »formodet« i 1939 betyder, at det kan ramme mange. Notér antallet i PR'en.
- [ ] **Step 4: Commit** — `git add docs/decisions.md docs/changelog.md docs/design/2026-11-12-webredesign-overdragelse.md`
  og `git commit -m "docs: slægtskab som kontekst på personsiden (fase 8)"`.
- [ ] **Step 5:** Spørg om ja til push og draft-PR.
