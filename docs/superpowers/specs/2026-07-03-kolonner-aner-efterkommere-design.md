# Design: Bidirektionelle kolonner (aner + efterkommere) i stamtræet

**Dato:** 2026-07-03
**Status:** Godkendt (design) + Codex-reviewet (1 BLOCKER + 5 SHOULD-FIX + 2 NICE-TO-HAVE indarbejdet) — afventer implementeringsplan
**Omfang:** Web (`web/`) + Mobil (`mobile/`). Kun stamtræets variant B ("Kolonner"). Variant A ("Fokus") og C ("Spor") røres ikke.

---

## 1. Baggrund & problem

Kolonner-visningen (variant B) blev netop tilføjet på web (matcher mobilens eksisterende `buildColumns`). Den kan i dag **kun drille nedad** — fokus-personen står yderst, og hver kolonne til højre viser efterkommere. Brugeren vil også kunne se **aner** (forældre, bedsteforældre …), helst **begge retninger i samme visning**.

Modellen eksponerer allerede `parentsByChild: Record<string, string[]>` (begge forældre) i begge apps, så ane-data er tilgængelig uden skema- eller loader-ændringer.

## 2. Mental model

Fokus-personen er et **fast anker** i midten af den vandret-scrollende kolonne-stribe:

```
◀ aner                     fokus                 efterkommere ▶
┌────────────┬──────────┬────────┬───────┬───────────┐
│Bedsteforæl.│ Forældre │ FOKUS  │ Børn  │ Børnebørn │
├────────────┼──────────┼────────┼───────┼───────────┤
│ Peder      │ Jørgen   │ Anna   │ Bo ›  │ Ida       │
│ Karen      │ Mette    │        │ Cille │ …         │
└────────────┴──────────┴────────┴───────┴───────────┘
   vælg forælder ◀                  ▶ vælg barn (som i dag)
```

To symmetriske drill-retninger fra ankeret:

- **Efterkommere (højre)** — uændret adfærd: en kolonne viser **alle børn** af den valgte person i kolonnen til venstre; vælg et barn → dets børn vises i næste kolonne til højre. Traversering: `childrenOf`.
- **Aner (venstre)** — nyt: en kolonne viser **begge forældre** (`parentsByChild`) af den valgte person i kolonnen til **højre** for den; vælg en forælder → dens to forældre vises endnu længere til venstre. Bilineal drill, symmetrisk med efterkommer-siden.

### Anker- og fokus-semantik (bevidst, matcher nuværende adfærd)

- Ankeret **flytter sig ikke**, når du vælger et kort. Kun app'ens fokus (detalje-panel/`focusId`) følger valget — præcis som descendant-drillen fungerer i dag.
- **Ekstern navigation** (sidebar, detalje-panel-link, back) nulstiller ankeret til den nye person og rydder begge drill-retninger.
- **Konsekvens:** visningen viser én ane-linje opad-venstre + efterkommere nedad-højre fra ankeret — *ikke* ankerets kollaterale slægtninge (fx forældres søskende). Dette matcher den nuværende linje-baserede drill. Fuld re-centrering ("klik en bedsteforælder → gør dem til nyt anker") er en mulig **senere** udvidelse, bevidst uden for dette design.

## 3. Default-visning (aner skal være opdagelige)

Når Kolonner åbnes eller fokus skifter: **Forældre-kolonne synlig til venstre + Børn-kolonne til højre**, med **fokus-kolonnen centreret** (auto-scroll til midten). Så begge retninger er umiddelbart synlige — brugeren skal ikke gætte, at man kan scrolle til venstre. Kolonner uden data (fx ingen registrerede forældre) udelades helt i den retning.

## 4. Kolonne-labels & retnings-affordances (erstatter "Generation N")

Relative slægts-labels centreret om ankeret (rene slægts-ord, ingen pile i headeren):

| Retning | Dybde 1 | 2 | 3 | 4 | ≥5 (fallback) |
|---|---|---|---|---|---|
| Aner (venstre) | Forældre | Bedsteforældre | Oldeforældre | Tipoldeforældre | `"{n}. slægtled tilbage"` |
| Anker | **Fokus** | — | — | — | — |
| Efterkommere (højre) | Børn | Børnebørn | Oldebørn | Tipoldebørn | `"{n}. slægtled frem"` |

**Retnings-metafor er konsekvent vandret** (stribens akse), ikke lodret. Så:
- Kant-vejledning ved stribens ender: `◀ aner` / `efterkommere ▶`.
- **Kort-chevron peger i drill-retningen:** ane-kort med forældre viser en **venstre-chevron `‹`** (drill mod venstre); efterkommer-kort med børn viser en **højre-chevron `›`** (som i dag). Anker-kortet har ingen chevron.

## 5. Arkitektur

Delt mønster i begge apps: en **ren, retnings-parametriseret kolonne-bygger** + en komposer, adskilt fra React/komponent-laget (jf. `web/src/data/tree.ts`, `mobile/src/data/selectors.ts`).

### 5.1 Ren funktion (data-lag)

Generaliser den nuværende bygger til at tage en **traverserings-funktion**:

```ts
type Traverse = (model: Model, id: string) => ModelPerson[]; // childrenOf | parentsOf

type TreeColumn = {
  key: string;              // STABIL identitet: `${kind}:${depth}` (ancestor:1 ≠ descendant:1)
  kind: 'ancestor' | 'anchor' | 'descendant';
  depth: number;            // 0 = anker, 1 = første ring, … (positiv i BEGGE retninger)
  label: string;            // relativt slægts-label (§4)
  people: ModelPerson[];    // ALLE registrerede (ordnet, se nedenfor) — ikke antaget = 2
  selectedId: string | null;
};

// Bygger kolonner der udvider fra ankeret i ÉN retning (ankeret IKKE inkluderet):
// selections[i] = valgt person i ring i+1; kæden stopper ved første ring uden valg
// eller når den valgte er barn-/forældreløs.
function buildDirection(model, anchorId, selections, traverse, kind): TreeColumn[];

// Komposer: [...aner omvendt, ankerkolonne, ...efterkommere]
function buildBidirectionalColumns(model, anchorId, up, down): TreeColumn[];
```

**Cyklus-guard (rigtig, ikke bare iterations-loft):** `MAX_DEPTH` alene stopper ikke en
cyklus — en self-forælder eller en person der optræder to gange på samme kæde ville rendere
gentaget. `buildDirection` fører derfor et **visited-`Set`** seedet med `anchorId` og stopper
FØR en allerede-set id gentages (pr. retning). Cross-retnings-dublet (samme person i både `up`
og `down`, kun muligt ved defekt data) er en datafejl der i værste fald viser personen to gange
— bundet, ingen uendelig løkke. Testes med self-edge + ane/efterkommer-løkke.

**`parentsOf`:** `web/src/data/model.ts` mangler den → **tilføjes på web** (tynd wrapper om
`parentsByChild[id]` → `ModelPerson[]`, kanoniske efter samme_som-collapse). **Mobil har den
allerede** (`mobile/src/data/selectors.ts:37`) → genbruges. Ane-kolonnen viser **alle**
registrerede forældre i stabil rækkefølge (far før mor, jf. `compareParentOrder` — normativt),
robust over for 1, 2 eller (ved defekt data) flere forældre.

### 5.2 Drill-tilstand

To selektions-arrays i stedet for det nuværende ene `path`:

- `anchorId: string` — fast center (reset-mål ved ekstern navigation).
- `up: string[]` — valgte aner (`up[0]` = valgt forælder af ankeret, `up[1]` = valgt forælder af `up[0]`, …).
- `down: string[]` — valgte efterkommere (`down[0]` = valgt barn af ankeret, …).

- **Web:** lokal `useState` i `TreeView`.
- **Mobil:** `useStore` (zustand) — den nuværende `path`-slice erstattes/udvides tilsvarende. Variant C's egen sti-tilstand røres ikke.

### 5.3 Reset-effekt (frontier-tjek, IKKE fuldt medlemskab)

**Rettet efter Codex-review (BLOCKER):** et fuldt medlemskabs-tjek (`focusId ∈ up/down`) kan
IKKE skelne intern drill fra ekstern navigation til en person der tilfældigvis allerede er valgt.
Modeksempel: drill `A→B→C` (`down=[B,C]`), klik så `B` i sidebaren → `B ∈ down` → tilstanden ville
(forkert) bevares, i strid med §2. Den nuværende descendant-baseline undgår dette ved kun at
acceptere path-**halen** (`Folgesvend.tsx`), ikke medlemskab.

Bidirektional analog: efter en drill er `focusId` altid den netop valgte = den **yderste** (frontier)
node i den retning der blev udvidet. Effekten bevarer derfor kun ved frontier-match:

```
const keep =
  (up.length === 0 && down.length === 0 && focusId === anchorId) ||
  focusId === up[up.length - 1] ||      // yderste ane
  focusId === down[down.length - 1];    // yderste efterkommer
if (!keep) reset to { anchorId: focusId, up: [], down: [] };
```

Drill-tap afkorter+udvider ét retnings-array og sætter fokus = den nye frontier → `keep` holder.
Ekstern navigation (sidebar/detalje/back) sætter fokus til en vilkårlig node → typisk ikke en
frontier → nulstil. Residual-edge: ekstern navigation der lander præcis på en nuværende frontier
bevarer visningen — men den node ER allerede den yderste synlige, så det er korrekt (samme klasse
som baseline'ens "navigér til halen bevarer stien").

*(Alternativ, lige så korrekt: en provenance-`ref` sat synkront i `selectAncestor`/`selectDescendant`;
frontier-tjekket vælges fordi det er tilstandsløst og spejler den beviste baseline.)*

**Invariant (load-bearing):** `focusId` og alle id'er i `up`/`down` er **kanoniske** (`focusId` er
post-`canon`; `up`/`down` udvides KUN med `parentsOf`/`childrenOf`-id'er). Kanoniske id'er sikrer
korrekt **lighed** i frontier-tjekket — de afgør ikke event-oprindelse; det gør frontier-formen.

### 5.4 Valg af kort (historik-fri)

Drill-valg går gennem den historik-frie `onFocus` (matcher designets `selectAt` vs `goToPerson`), så en dyb drill ikke fylder detalje-panelets tilbage-stak:

```
selectAncestor(depth, id):   setUp(prev => prev.slice(0, depth-1).concat(id));   onFocus(id)
selectDescendant(depth, id): setDown(prev => prev.slice(0, depth-1).concat(id)); onFocus(id)
```

### 5.5 Auto-scroll (platform-specifik, todelt ved prepend)

- **Mount/reset:** centrér anker-kolonnen i viewporten (scroll til ankerets offset − (viewport−kolonnebredde)/2).
- **Ned-drill** (`down` voksede): scroll højre til nyeste kolonne (som i dag).
- **Op-drill** (`up` voksede): en venstre-kolonne prepend'es → alt eksisterende indhold forskydes til
  højre, så ankeret "hopper". Todelt håndtering:
  1. **Kompensér før paint** så ankeret IKKE springer (web: `useLayoutEffect`, sæt `scrollLeft +=`
     den tilføjede kolonnes bredde+gap; RN: der findes ingen `scrollLeft` — brug `onContentSizeChange`/
     `onLayout` til at få ny bredde og `scrollTo({x, animated:false})` med eksplicit offset, IKKE en
     `setTimeout`-baseret `scrollToEnd`, der ikke er en layout-garanti).
  2. **Afslør** derefter den nye kolonne med en lille animeret scroll.
- **Prioritet på smalle skærme:** kan viewporten ikke rumme både anker og den nye kolonne, **vinder
  "afslør den nye kolonne"** (ankeret må forskydes) — ellers var op-drillen usynlig. Dette er den
  eksplicitte konflikt-regel Codex efterspurgte.
- **Måle-strategi:** kolonnebredder er faste (web ~208px, RN 166px) + kendt gap → kompensationen
  regnes deterministisk uden per-kort-måling. Web: automatiseret assertion på anker-scroll-mål (spy
  på `scrollTo`/`scrollLeft`). RN: eksplicit manuel Expo-checkliste (op-drill springer ikke).

## 6. Testning

- **Ren `buildBidirectionalColumns` / `buildDirection` (unit):**
  - anker uden forældre/børn → kun anker-kolonne.
  - anker med både forældre og børn, ingen valg → `[Forældre, Fokus, Børn]` med korrekte labels.
  - ane-drill: vælg forælder → Bedsteforældre-kolonne dukker op; korrekt `selectedId`.
  - efterkommer-drill (regression): uændret adfærd.
  - dybde-labels + ≥5 fallback (`{n}. slægtled tilbage/frem`).
  - retning uden data udelades.
  - **kolonne-`key`-identitet:** `ancestor:1` og `descendant:1` har forskellige keys (ingen kollision).
  - **cyklus-guard:** self-forælder (person er sin egen forælder) + ane/efterkommer-løkke → bounded,
    ingen gentagen render, terminerer.
  - **forældre-antal:** 1, 2, dedup-collapsed og (defekt) >2 forældre → alle vises, far-før-mor-ordnet.
- **Web RTL (`TreeView`):** default viser Forældre+Børn; op-drill afslører Bedsteforældre; ned-drill
  afslører Børnebørn; `onFocus` kaldes (ikke `onPick`).
  - **reset:** ekstern `focusId`-ændring til en person der IKKE er en frontier → nulstil til den
    person (kol 0-analog). Inkl. modeksemplet: drill `A→B→C`, ekstern nav til `B` → **nulstiller**
    (bevarer IKKE), da `B` ikke er down-frontier.
  - **centrering:** ved åbning/reset kaldes scroll-mål = anker-kolonnens offset (spy på `scrollTo`);
    "centreret" = anker i viewportens midte når begge sider har plads, ellers blot synligt. Fuld
    visuel centrering verificeres manuelt.
- **Mobil:** unit-test af den delte bygger i `selectors.test.ts` (samme cases som web-unit);
  skærm-verifikation manuelt (Expo) inkl. op-drill-scroll-checkliste (§5.5).

## 7. Berørte filer (forventet)

**Web:** `web/src/data/tree.ts` (bygger), `web/src/data/model.ts` (**tilføj** `parentsOf`),
`web/src/Folgesvend.tsx` (`TreeView`-tilstand + render + scroll), tests.
**Mobil:** `mobile/src/data/selectors.ts` (bygger; `parentsOf` findes allerede — genbruges),
`mobile/src/store/useStore.ts` (erstat `path`-slice med `anchorId`/`up`/`down`; opdatér ALLE
mutatorer der i dag rører `path`: `load`, `setFocus`, `setVariant`, `pickLinje`, `clearLinje`,
`setPath`/`selectAt`-analogen), `mobile/src/app/(tabs)/tree.tsx` (variant B render + scroll), tests.
Variant A (`focusId`) og C (`snapPath`/`snapDepth`) læser IKKE `path` (Codex-verificeret) og røres ikke.

## 8. Risici / åbne implementeringsdetaljer

1. **Layout-shift ved prepend af venstre-kolonner** (§5.5) — todelt kompensér+afslør; smalskærm-prioritet
   defineret (afslør vinder). Web `useLayoutEffect`; RN via layout/content-size-events, ikke `setTimeout`.
2. **Mobil zustand-migration** — `path` læses kun af variant B (verificeret), men flere mutatorer
   sætter den; alle skal migreres til det nye slice (§7), ellers efterlades død/inkonsistent tilstand.
3. **Reset-provenance** — frontier-tjekket (§5.3), ikke fuldt medlemskab; residual-edge (ekstern nav
   til en frontier bevarer visningen) er bevidst accepteret.
4. **Cyklus/dublet i data** — visited-`Set` pr. retning (§5.1); cross-retnings-dublet (defekt data)
   viser i værste fald personen to gange, bundet.
5. **Deep labels** — verificér de danske slægts-termer (tipoldeforældre osv.) + fallback læser rent.
6. **Forældre-antal & -ordning** — antag ikke præcis 2; vis alle registrerede, far-før-mor
   (`compareParentOrder`), normativt.
