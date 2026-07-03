# Design: Bidirektionelle kolonner (aner + efterkommere) i stamtræet

**Dato:** 2026-07-03
**Status:** Godkendt (design) — afventer implementeringsplan
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

## 4. Kolonne-labels (erstatter "Generation N")

Relative slægts-labels centreret om ankeret:

| Retning | Dybde 1 | 2 | 3 | 4 | ≥5 (fallback) |
|---|---|---|---|---|---|
| Aner ▲ | Forældre | Bedsteforældre | Oldeforældre | Tipoldeforældre | `"{n}. slægtled ↑"` |
| Anker | **Fokus** | — | — | — | — |
| Efterkommere ▼ | Børn | Børnebørn | Oldebørn | Tipoldebørn | `"{n}. slægtled ↓"` |

## 5. Arkitektur

Delt mønster i begge apps: en **ren, retnings-parametriseret kolonne-bygger** + en komposer, adskilt fra React/komponent-laget (jf. `web/src/data/tree.ts`, `mobile/src/data/selectors.ts`).

### 5.1 Ren funktion (data-lag)

Generaliser den nuværende bygger til at tage en **traverserings-funktion**:

```ts
type Traverse = (model: Model, id: string) => ModelPerson[]; // childrenOf | parentsOf

type TreeColumn = {
  kind: 'ancestor' | 'anchor' | 'descendant';
  depth: number;            // 0 = anker, 1 = første ring, …
  label: string;            // relativt slægts-label (§4)
  people: ModelPerson[];
  selectedId: string | null;
};

// Bygger kolonner der udvider fra ankeret i ÉN retning (ankeret IKKE inkluderet):
// selections[i] = valgt person i ring i+1; kæden stopper ved første ring uden valg
// eller når den valgte er barn-/forældreløs. Guard mod cyklus (MAX_DEPTH).
function buildDirection(model, anchorId, selections, traverse, kind): TreeColumn[];

// Komposer: [...aner omvendt, ankerkolonne, ...efterkommere]
function buildBidirectionalColumns(model, anchorId, up, down): TreeColumn[];
```

`parentsOf(model, id)` er en tynd wrapper om `parentsByChild[id]` → `ModelPerson[]` (kanoniske efter samme_som-collapse), symmetrisk med den eksisterende `childrenOf`. Tilføjes til `web/src/data/model.ts` og mobilens tilsvarende.

### 5.2 Drill-tilstand

To selektions-arrays i stedet for det nuværende ene `path`:

- `anchorId: string` — fast center (reset-mål ved ekstern navigation).
- `up: string[]` — valgte aner (`up[0]` = valgt forælder af ankeret, `up[1]` = valgt forælder af `up[0]`, …).
- `down: string[]` — valgte efterkommere (`down[0]` = valgt barn af ankeret, …).

- **Web:** lokal `useState` i `TreeView`.
- **Mobil:** `useStore` (zustand) — den nuværende `path`-slice erstattes/udvides tilsvarende. Variant C's egen sti-tilstand røres ikke.

### 5.3 Reset-effekt (invariant bevaret)

Én effekt kilet på `focusId`: bevar tilstanden hvis `focusId` er ankeret eller en aktuelt valgt node (op/ned); ellers ekstern navigation → nulstil (`anchorId = focusId`, `up = []`, `down = []`).

```
if (focusId === anchorId || up.includes(focusId) || down.includes(focusId)) keep;
else reset to { anchorId: focusId, up: [], down: [] };
```

**Invariant (load-bearing):** `focusId` og alle id'er i `up`/`down` er **kanoniske** (`focusId` er post-`canon` fra `navigateTo`/`onFocus`; `up`/`down` udvides KUN med `parentsOf`/`childrenOf`-id'er, som er kanoniske efter samme_som-collapse). Ellers ville medlemskabs-tjekket fejle og nulstille ved hvert drill-tap.

### 5.4 Valg af kort (historik-fri)

Drill-valg går gennem den historik-frie `onFocus` (matcher designets `selectAt` vs `goToPerson`), så en dyb drill ikke fylder detalje-panelets tilbage-stak:

```
selectAncestor(depth, id):   setUp(prev => prev.slice(0, depth-1).concat(id));   onFocus(id)
selectDescendant(depth, id): setDown(prev => prev.slice(0, depth-1).concat(id)); onFocus(id)
```

### 5.5 Auto-scroll

- **Mount/reset:** centrér anker-kolonnen i viewporten.
- **Ned-drill** (`down` voksede): scroll højre til nyeste kolonne (som i dag).
- **Op-drill** (`up` voksede): afslør den nye venstre-kolonne. **Risiko:** at prepende en venstre-kolonne forskyder eksisterende indhold til højre → fokus-kolonnen "hopper". Implementeringen skal kompensere `scrollLeft` med den tilføjede kolonnes bredde (eller scrolle så den nye kolonne bliver synlig uden at ankeret springer). Kaldes ud som eksplicit implementeringsopgave.

## 6. Testning

- **Ren `buildBidirectionalColumns` / `buildDirection` (unit):**
  - anker uden forældre/børn → kun anker-kolonne.
  - anker med både forældre og børn, ingen valg → `[Forældre, Fokus, Børn]` med korrekte labels.
  - ane-drill: vælg forælder → Bedsteforældre-kolonne dukker op; korrekt `selectedId`.
  - efterkommer-drill (regression): uændret adfærd.
  - dybde-labels + ≥5 fallback.
  - retning uden data udelades.
- **Web RTL (`TreeView`):** default viser Forældre+Børn; op-drill afslører Bedsteforældre; ned-drill afslører Børnebørn; ekstern `focusId`-ændring nulstiller til den nye person; `onFocus` kaldes (ikke `onPick`).
- Mobil: unit-test af `buildColumns`/`buildBidirectionalColumns` i `selectors.test.ts`; skærm-verifikation manuelt (Expo).

## 7. Berørte filer (forventet)

**Web:** `web/src/data/tree.ts` (bygger), `web/src/data/model.ts` (`parentsOf`), `web/src/Folgesvend.tsx` (`TreeView`-tilstand + render + scroll), tests.
**Mobil:** `mobile/src/data/selectors.ts` (bygger + `parentsOf`), `mobile/src/store/useStore.ts` (tilstand), `mobile/src/app/(tabs)/tree.tsx` (variant B render + scroll), tests.

## 8. Risici / åbne implementeringsdetaljer

1. **Layout-shift ved prepend af venstre-kolonner** (§5.5) — skal håndteres, ellers springer visningen ved op-drill.
2. **Mobil zustand-migration** — den nuværende `path`-slice bruges kun af variant B; verificér ingen anden variant læser den før erstatning.
3. **Deep labels** — verificér de danske slægts-termer (tipoldeforældre osv.) og fallback-formen læser rent.
4. **`parentsOf`-ordning** — forældre bør vises konsistent (far før mor, jf. `compareParentOrder`) i ane-kolonnerne.
