# Generations-browser v2 — Implementeringsplan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Udvid v1's aner-hul-reparation til en fuld bidirektionel generations-browser med slægtled-naboer i fokus og kombinerede overskrifter.

**Architecture:** Retnings-generaliser den rene kerne (`adjacentGen`, `fallbackRing`), tilføj `buildAnchorPeers` + `columnLabel`, og bær en **aktiv koordinat** i træets state der driver naboer/fallback/labels. Spejlet byte-identisk web (`tree.ts`) + mobil (`selectors.ts`); UI-lag renderer dæmpede naboer + kombinations-labels. Ingen DB-ændring (data fra v1).

**Tech Stack:** TypeScript/React (`web/`, vitest), RN/Expo + Zustand (`mobile/`, jest).

## Global Constraints

- **Design:** `docs/superpowers/specs/2026-07-05-generations-browser-v2-design.md`. Tvivl afgøres der.
- **Invariant:** alle ringe/naboer er rene read-time projektioner. Klik re-ankrer (web `onFocus`, mobil `setFocus`) — skriver ALDRIG en `relation`/`fact`/`visning_*`.
- **Aktiv koordinat bæres i state** (`activeCoord = {sourceId, lineageId, lokal} | null`), sat fra det klikkede kort; default = lavest-lokal ved direkte navigation. Driver naboer + fallback-retning + labels.
- **Efterkommer-retning: INGEN founder-hop** (kun `dir=-1` hopper). Ren `lokal+1` i samme `(sourceId,lineageId)`; ærlig dødende hvor ingen G+1.
- **v1-invarianter bevares:** source+lineage-exakt kandidat-match; fail-closed ambiguøs aner-hop. Eksplicitte regressionstests.
- **Byte-identisk delt kerne:** `adjacentGen`, `fallbackRing`, `buildAnchorPeers`, `columnLabel` tegn-for-tegn ens web↔mobil; mekanisk paritets-test.
- **Peer-cap:** fokus + max K=7 naboer + "+N flere"-udfold. Fokus altid visuelt dominant (via `TreeColumn.focusId`, ikke `selectedId`).
- **Ingen regression:** alle v1-tests forbliver grønne (web 189, mobil 304 som baseline på merged main).
- Commits: Conventional, dansk, ingen Claude-attribution-footer, afslut med `Claude-Session:`-linjen.

---

## Task 1: `adjacentGen` — retnings-generaliseret nabo-generation (web+mobil)

**Files:**
- Modify: `web/src/data/generations.ts` + `mobile/src/data/generations.ts` (byte-identisk): erstat `previousAncestorGen` med `adjacentGen`.
- Test: `web/src/data/__tests__/generations.test.ts` + `mobile/…` (opdatér de eksisterende founder-hop-tests til `adjacentGen(..., -1)` + tilføj dir+1 + source/lineage-scoping).

**Interfaces:**
- Produces: `adjacentGen(coords: GenCoord[], sourceId: string, lineageId: string | null, lokal: number, dir: -1 | 1): { sourceId: string; lineageId: string | null; linje: string; lokal: number } | null`
  - `dir=+1`: samme `(sourceId, lineageId)`, `lokal+1` (returnér koordinatens `linje`); INGEN hop. `null` hvis ingen sådan koordinat-kontekst.
  - `dir=-1`: hvis `lokal>1` → samme linje `lokal-1`. Ellers founder-hop: den ENESTE koordinat hvor `lineageId === parentLineageId(of the (sourceId,lineageId,1) coord)` og `lokal>1`; `null` ellers (fail-closed).
  - Al matching er nu `(sourceId, lineageId)`-scoped (ikke kun `linje`).

- [ ] **Step 1: Skriv de fejlende tests** (opdatér eksisterende + tilføj)

```typescript
import { describe, it, expect } from 'vitest';
import { buildGenCoords, adjacentGen, type GenCoord } from '../generations';

const coords: GenCoord[] = [
  { sourceId: '1', linje: 'V', lineageId: '50', parentLineageId: '10', lokal: 1, gennem: 12, kuld: null },
  { sourceId: '1', linje: 'III', lineageId: '10', parentLineageId: null, lokal: 12, gennem: null, kuld: null },
];

describe('adjacentGen dir=-1 (aner)', () => {
  it('samme linje et slægtled tilbage', () =>
    expect(adjacentGen(coords, '1', '10', 12, -1)).toEqual({ sourceId: '1', lineageId: '10', linje: 'III', lokal: 11 }));
  it('founder (lokal 1) hopper til moderlinjen', () =>
    expect(adjacentGen(coords, '1', '50', 1, -1)).toEqual({ sourceId: '1', lineageId: '10', linje: 'III', lokal: 11 }));
  it('fail-closed: flere/ingen entydig moderlinje → null', () =>
    expect(adjacentGen([coords[0]], '1', '50', 1, -1)).toBeNull());
});
describe('adjacentGen dir=+1 (efterkommer)', () => {
  it('samme linje et slægtled frem, ingen hop', () =>
    expect(adjacentGen(coords, '1', '10', 12, 1)).toEqual({ sourceId: '1', lineageId: '10', linje: 'III', lokal: 13 }));
  it('en founder (lokal 1) går frem i egen linje, IKKE tilbage til moderlinje', () =>
    expect(adjacentGen(coords, '1', '50', 1, 1)).toEqual({ sourceId: '1', lineageId: '50', linje: 'V', lokal: 2 }));
});
```

- [ ] **Step 2: Kør — verificér fejl.** `cd web && npx vitest run src/data/__tests__/generations.test.ts` → FAIL (`adjacentGen` findes ikke).

- [ ] **Step 3: Implementér** (erstat `previousAncestorGen`)

```typescript
export function adjacentGen(
  coords: GenCoord[],
  sourceId: string,
  lineageId: string | null,
  lokal: number,
  dir: -1 | 1,
): { sourceId: string; lineageId: string | null; linje: string; lokal: number } | null {
  const cur = coords.find((c) => c.sourceId === sourceId && c.lineageId === lineageId && c.lokal === lokal);
  if (dir === 1) {
    if (!cur) return null;
    return { sourceId, lineageId, linje: cur.linje, lokal: lokal + 1 };
  }
  // dir === -1
  if (lokal > 1) {
    if (!cur) return null;
    return { sourceId, lineageId, linje: cur.linje, lokal: lokal - 1 };
  }
  const parentId = cur?.parentLineageId ?? null;
  const candidates = coords.filter(
    (c) => c.sourceId === sourceId && c.lineageId != null && c.lineageId === parentId && (c.lokal ?? 0) > 1,
  );
  if (candidates.length !== 1) return null; // fail-closed
  const t = candidates[0];
  return { sourceId, lineageId: t.lineageId, linje: t.linje, lokal: (t.lokal as number) - 1 };
}
```

- [ ] **Step 4: Kør — grøn.** vitest på filen → PASS.
- [ ] **Step 5: Spejl til mobil** (kopiér `adjacentGen` + test byte-identisk, justér import-linje). `cd mobile && npx jest src/data/__tests__/generations.test.ts` → PASS. Bekræft `diff web/src/data/generations.ts mobile/src/data/generations.ts` tomt.
- [ ] **Step 6: tsc begge** (kalder til `previousAncestorGen` i `tree.ts`/`selectors.ts` opdateres i Task 4 — forvent tsc-fejl DER indtil da; hvis Task 1 køres isoleret, behold en midlertidig `previousAncestorGen`-wrapper der delegerer til `adjacentGen(...,-1)` for at holde tsc grøn). Commit: `feat(web,mobile): adjacentGen — retnings-generaliseret nabo-generation`.

---

## Task 2: `columnLabel` — kombinerede overskrifter (web+mobil)

**Files:** Modify `web/src/data/tree.ts` + `mobile/src/data/selectors.ts` (erstat `labelFor`); tests i begge `__tests__`.

**Interfaces:**
- Produces: `columnLabel(a: { kind: 'ancestor'|'descendant'|'anchor'; depth: number; slaegtled: number | null; linje: string | null; fallback?: boolean }): string`
  - `anchor`: `"<slaegtled>. slægtled · <linje>-linjen"` (eller `'Fokus'` hvis `slaegtled==null`).
  - `fallback`: `"muligt · <slaegtled>. slægtled · <linje>-linjen"`.
  - bevist `depth≤4`: `"<kinship> · <slaegtled>. slægtled"` (kinship fra ANCESTOR/DESCENDANT_LABELS); `slaegtled==null` → kun `<kinship>`.
  - bevist `depth≥5`: `"<slaegtled>. slægtled"`; `slaegtled==null` → `"<depth-3>× Tipoldeforældre/-børn"` (v1-fallback).

- [ ] **Step 1-4:** TDD tests for hver gren (anchor, fallback, d≤4 m/u slaegtled, d≥5 m/u slaegtled) → implementér → grøn. Spejl mobil byte-identisk. Commit: `feat(web,mobile): columnLabel — slægtskab · slægtled + fallback-format`.

---

## Task 3: `buildAnchorPeers` — slægtled-naboer m. cap (web+mobil)

**Files:** Modify `web/src/data/tree.ts` + `mobile/src/data/selectors.ts`; tests i begge.

**Interfaces:**
- Consumes: `Model`, `GenCoords`, `anchorId`, `activeCoord: {sourceId,lineageId,lokal} | null`.
- Produces: `buildAnchorPeers(model, genCoords, anchorId, activeCoord, cap=7): { people: ModelPerson[]; overflow: number }`
  - `people` = fokus først, derefter naboer (samme `(sourceId,lineageId,lokal)`, minus fokus), sorteret på navn, klippet til `cap`. `overflow` = antal ud over cap.
  - `activeCoord==null` → `{ people: [fokus], overflow: 0 }`.

- [ ] **Step 1-4:** TDD (naboer inkluderet, fokus først, cap+overflow, tom ved null) → implementér → grøn. Spejl mobil. Commit: `feat(web,mobile): buildAnchorPeers — slægtled-naboer m. cap`.

---

## Task 4: bidirektionel `fallbackRing` + integration i `buildBidirectionalColumns` (web+mobil)

**Files:** Modify `web/src/data/tree.ts` + `mobile/src/data/selectors.ts`; tests i begge.

**Interfaces:**
- `fallbackRing(model, genCoords, anchorId, cur, depth, dir)` (generaliseret fra `fallbackAncestorRing`, bruger `adjacentGen(...,dir)`; source/lineage-scoped kandidat-match bevaret).
- `buildBidirectionalColumns(model, anchorId, up, down, genCoords?, activeCoord?)` — nyt `activeCoord`-arg. Ankeret bygges via `buildAnchorPeers` (+`focusId`); aner OG efterkommer bygger fallback via `fallbackRing(...,-1/+1)` når bevist ring tom; alle kolonners `label` sættes via `columnLabel` (slaegtled = `activeCoord.lokal ∓ depth`, `null` hvis `activeCoord==null`).
- `TreeColumn` += `focusId?: string`, `overflowPeers?: number`. Behold `fallback/genLabel/kuldGroups`.

- [ ] **Step 1: Test** — udvid tree.test: (a) efterkommer-fallback-ring bygges når `childrenOf` tom + `activeCoord` givet (ny person i G+1); (b) anker-kolonne har `focusId` + naboer; (c) proven-kolonne-label = "Forældre · N. slægtled"; (d) `activeCoord=null` → v1-adfærd (ingen peers, ingen fallback, gamle labels). + **v1-regressionstests** (source/lineage-scoped aner-fallback uændret; fail-closed hop).
- [ ] **Step 2-4:** implementér threading → grøn → fuld web-suite + tsc grøn (opdatér `previousAncestorGen`-kald). Spejl mobil `selectors.ts` + jest. Commit: `feat(web,mobile): bidirektionel fallback + anker-peers + labels i builder`.

---

## Task 5: paritets-test for delt kerne (web+mobil)

**Files:** Create `web/src/data/__tests__/parity.test.ts` (+ mobil pendant).

**Interfaces:** læser kilde-teksten for `adjacentGen`, `fallbackRing`, `buildAnchorPeers`, `columnLabel` fra begge platform-filer og asserter funktions-kroppene er tegn-for-tegn ens.

- [ ] **Step 1-4:** implementér parity-test (regex-udtræk af hver funktion fra begge filer, normalisér whitespace ikke, assert lighed) → grøn i begge suiter. Commit: `test(web,mobile): paritets-test for delt generations-kerne`.

---

## Task 6: web UI — activeCoord-state + peer-render + labels

**Files:** Modify `web/src/Folgesvend.tsx`.

**Interfaces:** Consumes `buildBidirectionalColumns(..., activeCoord)` + `TreeColumn.focusId/overflowPeers`.

- [ ] **Step 1: activeCoord-state.** Tilføj `useState` for `activeCoord`; init fra fokus-personens lavest-lokal `genCoord` ved direkte navigation; sæt fra klikket korts coord ved `onFocus`. Thread ind i `buildBidirectionalColumns`-kaldet (linje ~547).
- [ ] **Step 2: render.** Anker: fokus dominant + naboer dæmpede (via `col.focusId`), "+N flere"-kort (`overflowPeers`) folder ud. Kombinations-labels vises fra `col.label`. Efterkommer-fallback får samme stiplede/amber-stil som aner-fallback. Klik overalt → `onFocus` + sæt activeCoord.
- [ ] **Step 3: verificér** ingen skrivning (grep `red_`/`supabase.*insert/update` på diff = tom). tsc + build + `npx vitest run` grøn.
- [ ] **Step 4: empirisk** browser mod prod (bidirektionel browse fra person 246; Conrad bevarer III-kontekst ved ankomst via III-fallback; naboer + labels). Commit: `feat(web): generations-browser UI — naboer, bidirektionel fallback, labels`.

---

## Task 7: mobil UI — activeCoord-state + peer-render + anker-tryk + labels

**Files:** Modify `mobile/src/store/useStore.ts` (activeCoord + setter) + `mobile/src/app/(tabs)/tree.tsx`.

- [ ] **Step 1: store.** `activeCoord` i State + init/set (spejl web-logikken); thread ind i `buildBidirectionalColumns`-kaldet (linje ~135) + useMemo-dep.
- [ ] **Step 2: render.** Spejl Task 6: dæmpede peer-kort + "+N flere", kombinations-labels, efterkommer-fallback-stil. **Anker-kort får tryk-handler** (`setFocus` + activeCoord — v1-hul). Fokus-dominans via `col.focusId`.
- [ ] **Step 3-4:** tsc + `npx jest` grøn; empirisk fysisk enhed. Commit: `feat(mobile): generations-browser UI — naboer, bidirektionel fallback, anker-tryk, labels`.

---

## Afslutning
- [ ] Full-suite: web tsc+vitest, mobil tsc+jest — grøn.
- [ ] `/simplify` på de nye moduler.
- [ ] Dual-review (Codex) af samlet diff.
- [ ] PR `--draft` mod main; changelog/decisions/CLAUDE.md + memory.

## Sporbarhed spec→task
| Spec | Task |
|---|---|
| §2 aktiv-linje-state | 6, 7 (+ tråd i 4) |
| §3 efterkommer-fallback (adjacentGen dir+1, ærlig dødende) | 1, 4 |
| §4 slægtled-naboer (focusId, cap) | 3, 4, 6, 7 |
| §5 kombinations-labels | 2, 4, 6, 7 |
| §6 delt-kode-grænse | 5 |
| §8 v1-regression + paritet | 1, 4, 5 |
