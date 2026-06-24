# Vej til mig — wayfinder i Spor — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Gør den ukoblede røde streg i stamtræets Spor-variant til en ægte turn-by-turn wayfinder mod brugerens eget kort (`meId`).

**Architecture:** Ren pathfinder-selector (`wayToMe`) i `src/data/selectors.ts` beregner næste gestus + antal resterende spring fra fokus til mig over slægts-træet (op til fælles ane → søskendeskift → ned). `VariantC` i `tree.tsx` kalder kun selectoren og tegner streg-tilstand + badge. Ingen ny store-state.

**Tech Stack:** TypeScript, React Native (Expo), Zustand, Jest.

## Global Constraints

- Arbejdsmappe: `mobile/` (Expo-app). Alle stier relative hertil.
- Test-runner: `npm test` (Jest). Kør enkelt fil: `npx jest src/data/__tests__/selectors.test.ts`.
- Ingen ændring af gestus-modellen (`moveSnapGen`/`moveSnapSib`) eller store-state.
- Farver via eksisterende tokens: bordeaux `#881A33` (`Colors.bordeaux`). Labels i JetBrains Mono (`Mono`-komponent).
- Gestus-mapping (eksisterende): ▲ = aner (`moveSnapGen(-1)`), ▼ = efterkommere (`moveSnapGen(+1)`), ◂ = `moveSnapSib(-1)`, ▸ = `moveSnapSib(+1)`. Søskende-rækkefølge = `childrenOf`-orden (førstefødt = indeks 0).
- Conventional Commits, dansk beskrivelse. Ingen Claude-attribution-footer. Hver commit slutter med `Claude-Session: https://claude.ai/code/session_01HWFBATmnarqAbdt5npiHZN`.

---

### Task 1: Pathfinder-selector `wayToMe` + golden-tests

**Files:**
- Modify: `mobile/src/data/selectors.ts` (tilføj `WayStep` + `ancestorsOf` + `wayToMe`)
- Test: `mobile/src/data/__tests__/selectors.test.ts` (ny `describe`-blok + udvidet fixture)

**Interfaces:**
- Consumes: `childrenOf(model, parentId): ModelPerson[]` og typerne `Model`, `ModelPerson` (allerede importeret i `selectors.ts`).
- Produces:
  ```ts
  export type WayStep = 'up' | 'down' | 'left' | 'right' | 'arrived';
  export function wayToMe(
    model: Model, snapPath: string[], snapDepth: number, meId: string,
  ): { step: WayStep; remaining: number } | null;
  ```

- [ ] **Step 1: Skriv den fejlende test**

Tilføj nederst i `mobile/src/data/__tests__/selectors.test.ts` (importér `wayToMe` ved at udvide den eksisterende import fra `'../selectors'`). Brug en egen, dybere fixture, så ane/søskende/efterkommer-stier findes:

```ts
// Wayfinder-fixture: 1 ┬ 2 ┬ 4
//                     │   └ 7
//                     └ 3 ── 5      (6 = isoleret, egen rod)
const wayDb: Db = {
  persons: [
    mk('1', 'Rod Reventlow', 1644),
    mk('2', 'Andet led A', 1670),
    mk('3', 'Andet led B', 1672),
    mk('4', 'Tredje led A', 1700),
    mk('7', 'Tredje led B', 1702),
    mk('5', 'Tredje led C', 1704),
    mk('6', 'Fremmed slægt', 1680),
  ],
  unions: [{ id: 'u1', p1: '1', p2: null, p2_name: null, year: null }],
  parentChild: [
    { child: '2', parent: '1', union: 'u1' },
    { child: '3', parent: '1', union: 'u1' },
    { child: '4', parent: '2', union: 'u1' },
    { child: '7', parent: '2', union: 'u1' },
    { child: '5', parent: '3', union: 'u1' },
  ],
};
const wayModel = buildModel(wayDb);
// snapPath for fokus=4: anekæde [1,2,4] + tom hale → depth 2
const path124 = buildSnapPath(wayModel, '4', '1'); // { path:['1','2','4'], depth:2 }
// snapPath for fokus=1: [1] + førstefødt-hale [2,4] → depth 0
const path1 = buildSnapPath(wayModel, '1', '1');    // { path:['1','2','4'], depth:0 }

describe('wayToMe — vej til mig i Spor', () => {
  test('fokus == mig → arrived', () => {
    expect(wayToMe(wayModel, path124.path, path124.depth, '4')).toEqual({ step: 'arrived', remaining: 0 });
  });

  test('mig er ane til fokus → up, antal generationer', () => {
    expect(wayToMe(wayModel, path124.path, path124.depth, '1')).toEqual({ step: 'up', remaining: 2 });
  });

  test('mig er fætter (forgrening m. søskendeskift) → up først, 3 spring', () => {
    // fokus=4 (depth2), mig=5: op til depth1, skift 2→3 (right), ned til 5
    expect(wayToMe(wayModel, path124.path, path124.depth, '5')).toEqual({ step: 'up', remaining: 3 });
  });

  test('mig er førstefødt-efterkommer på linjen → down', () => {
    // fokus=1 (depth0), mig=4: ned, ned
    expect(wayToMe(wayModel, path1.path, path1.depth, '4')).toEqual({ step: 'down', remaining: 2 });
  });

  test('mig er efterkommer men ikke på førstefødt-hale → down først, søskende-trin tælles', () => {
    // fokus=1 (depth0), mig=7: ned (→2), ned (→førstefødt 4), right (4→7)
    expect(wayToMe(wayModel, path1.path, path1.depth, '7')).toEqual({ step: 'down', remaining: 3 });
  });

  test('mig uden fælles ane → null', () => {
    expect(wayToMe(wayModel, path124.path, path124.depth, '6')).toBeNull();
  });

  test('mig findes ikke i model → null', () => {
    expect(wayToMe(wayModel, path124.path, path124.depth, 'ukendt')).toBeNull();
  });
});
```

- [ ] **Step 2: Kør testen — verificér at den fejler**

Run: `cd mobile && npx jest src/data/__tests__/selectors.test.ts -t "wayToMe"`
Expected: FAIL — `wayToMe is not a function` (ikke eksporteret endnu).

- [ ] **Step 3: Implementér selectoren**

Tilføj i `mobile/src/data/selectors.ts` (efter `buildSnapPath`-funktionen). `ModelPerson`/`Model`/`childrenOf` er allerede tilgængelige i filen.

```ts
export type WayStep = 'up' | 'down' | 'left' | 'right' | 'arrived';

// Anekæde inkl. personen selv, ældste først (samme klatre-mønster som buildSnapPath).
function ancestorsOf(model: Model, id: string): string[] {
  const out: string[] = [];
  let c: ModelPerson | undefined = model.byId[id];
  let g = 0;
  while (c && g < 40) {
    out.unshift(c.id);
    c = c.parentId ? model.byId[c.parentId] : undefined;
    g++;
  }
  return out;
}

// Næste gestus + antal resterende spring fra fokus til mig i Spor-navigationen.
// Bygger HELE gestus-planen konstruktivt (op til fælles ane → søskendeskift → ned),
// så der ikke opstår op/ned-bounce ved gren-kryds. null = ingen fælles ane (ingen vej).
export function wayToMe(
  model: Model,
  snapPath: string[],
  snapDepth: number,
  meId: string,
): { step: WayStep; remaining: number } | null {
  const focus = snapPath[snapDepth];
  if (!focus) return null;
  if (focus === meId) return { step: 'arrived', remaining: 0 };

  const A = snapPath.slice(0, snapDepth + 1); // fokus' anekæde (snapPath ER anekæden)
  const M = ancestorsOf(model, meId);          // mig's anekæde
  if (!M.length || A[0] !== M[0]) return null;  // ingen fælles ane → ingen vej

  let commonLen = 0;
  while (commonLen < A.length && commonLen < M.length && A[commonLen] === M[commonLen]) commonLen++;

  const plan: WayStep[] = [];

  // Søskende-indeks (førstefødt = 0). -1 hvis ikke fundet (defensivt).
  const childIndex = (parentId: string, childId: string): number =>
    childrenOf(model, parentId).findIndex((p) => p.id === childId);

  // Nedstigning fra node M[d] (i dybde d) ned til mig: per niveau ned (lander på
  // førstefødt) + søskende-trin til det rette barn.
  const descendFrom = (d: number) => {
    for (let i = d; i < M.length - 1; i++) {
      plan.push('down');
      const idx = childIndex(M[i], M[i + 1]);
      for (let s = 0; s < idx; s++) plan.push('right');
    }
  };

  if (commonLen === M.length) {
    // Mig er ane til fokus: mig ligger på A i dybde M.length-1 → klatr op.
    const meDepth = M.length - 1;
    for (let s = 0; s < snapDepth - meDepth; s++) plan.push('up');
  } else if (commonLen === snapDepth + 1) {
    // Fokus ligger på mig's egen kæde (A præfiks af M) → ren nedstigning.
    descendFrom(snapDepth);
  } else {
    // Ægte forgrening: klatr op til søskende-dybden commonLen, skift søskende
    // fra A[commonLen] til M[commonLen] (samme forælder), stig så ned.
    for (let s = 0; s < snapDepth - commonLen; s++) plan.push('up');
    const fromIdx = childIndex(M[commonLen - 1], A[commonLen]);
    const toIdx = childIndex(M[commonLen - 1], M[commonLen]);
    const sib = toIdx - fromIdx;
    for (let s = 0; s < Math.abs(sib); s++) plan.push(sib > 0 ? 'right' : 'left');
    descendFrom(commonLen);
  }

  if (!plan.length) return null;
  return { step: plan[0], remaining: plan.length };
}
```

- [ ] **Step 4: Kør testen — verificér at den består**

Run: `cd mobile && npx jest src/data/__tests__/selectors.test.ts -t "wayToMe"`
Expected: PASS — alle 7 cases grønne.

- [ ] **Step 5: Kør hele selector-suiten (ingen regression)**

Run: `cd mobile && npx jest src/data/__tests__/selectors.test.ts`
Expected: PASS — eksisterende `buildSearch`/`buildColumns`/`buildSnapPath`-tests stadig grønne.

- [ ] **Step 6: Commit**

```bash
cd mobile && git add src/data/selectors.ts src/data/__tests__/selectors.test.ts
git commit -m "$(cat <<'EOF'
feat(mobile): wayToMe-pathfinder til Spor-wayfinder

Ren selector: næste gestus + antal spring fra fokus til mig
(op til fælles ane → søskendeskift → ned). Golden-tests for ane/
fætter/efterkommer/arrived/uden-fælles-ane.

Claude-Session: https://claude.ai/code/session_01HWFBATmnarqAbdt5npiHZN
EOF
)"
```

---

### Task 2: UI-wiring i `VariantC` (streg-tilstand + badge)

**Files:**
- Modify: `mobile/src/app/(tabs)/tree.tsx` (import, `VariantC`-body, `styles`)

**Interfaces:**
- Consumes: `wayToMe(model, snapPath, snapDepth, meId)` + `WayStep` fra Task 1; `useStore`-selector `s.meId`.
- Produces: ingen (terminalt UI-lag).

- [ ] **Step 1: Udvid import fra selectors**

I `mobile/src/app/(tabs)/tree.tsx`, find den eksisterende import-linje fra `'../../data/selectors'` (den der importerer `childrenOf`) og tilføj `wayToMe`:

```ts
import { buildColumns, childrenOf, treeFocusA, wayToMe } from '../../data/selectors';
```

(Behold de øvrige navne der allerede står i linjen; tilføj kun `wayToMe`. Verificér det faktiske importnavn-sæt før ændring.)

- [ ] **Step 2: Læs `meId` + beregn `way` i `VariantC`**

I `VariantC`, lige efter linjen `const snapDepth = useStore((s) => s.snapDepth);`, tilføj:

```ts
const meId = useStore((s) => s.meId);
const way = useMemo(
  () => (meId ? wayToMe(model, snapPath, snapDepth, meId) : undefined),
  [meId, model, snapPath, snapDepth],
);
const ARROW: Record<Exclude<WayStep, 'arrived'>, string> = { up: '▲', down: '▼', left: '◂', right: '▸' };
```

Tilføj `WayStep` til samme selectors-import som i Step 1 (`import { ..., wayToMe, type WayStep } ...` — eller en separat `import type { WayStep } from '../../data/selectors';`).

- [ ] **Step 3: Erstat den ubetingede guide-linje med tilstands-styret rendering**

Find i `VariantC`'s `return`:

```tsx
        {/* Lodret guide-linje */}
        <View style={styles.snapGuide} pointerEvents="none" />
```

Erstat med (streg skjules kun når mig er valgt men uden fælles ane = `way === null`):

```tsx
        {/* Lodret guide-linje — wayfinder mod eget kort */}
        {(meId == null || way) && (
          <View style={[styles.snapGuide, way ? styles.snapGuideLit : null]} pointerEvents="none" />
        )}
```

- [ ] **Step 4: Tilføj wayfinder-badge i overlay-laget**

I samme `return`, lige efter center-fokus-rammen (`<View style={styles.snapFrame} pointerEvents="none" />`), tilføj badge-blokken:

```tsx
        {/* Wayfinder-badge på linjen, over fokus-rammen */}
        {meId == null ? (
          <View style={styles.wayBadge} pointerEvents="none">
            <View style={styles.wayPill}>
              <Mono size={8} color={Colors.bordeaux} style={{ letterSpacing: 8 * 0.08, textTransform: 'uppercase' }}>Vælg dig selv i en profil</Mono>
            </View>
          </View>
        ) : way?.step === 'arrived' ? (
          <View style={styles.wayBadge} pointerEvents="none">
            <View style={styles.wayPill}>
              <Mono size={9} color={Colors.bordeaux} style={{ letterSpacing: 9 * 0.08 }}>★ Du er her</Mono>
            </View>
          </View>
        ) : way ? (
          <View style={styles.wayBadge} pointerEvents="none">
            <View style={styles.wayPill}>
              <Mono size={10} color={Colors.bordeaux}>{ARROW[way.step]} {way.remaining} spring til dig</Mono>
            </View>
          </View>
        ) : null}
```

- [ ] **Step 5: Tilføj styles**

I `StyleSheet.create({ ... })`-blokken, i `// Variant C`-sektionen, tilføj efter `snapGuide`-linjen:

```ts
  snapGuideLit: { backgroundColor: 'rgba(136,26,51,0.40)' },
  wayBadge: { position: 'absolute', left: 0, right: 0, top: '50%', marginTop: -94, alignItems: 'center' },
  wayPill: { backgroundColor: Colors.paperCard, borderWidth: StyleSheet.hairlineWidth, borderColor: 'rgba(136,26,51,0.30)', borderRadius: 14, paddingVertical: 5, paddingHorizontal: 12, ...Shadow.card },
```

- [ ] **Step 6: Typecheck + lint**

Run: `cd mobile && npx tsc --noEmit && npx expo lint`
Expected: ingen nye fejl (advarsler i urørte filer ignoreres).

- [ ] **Step 7: Manuel verifikation (UI — ingen unit-test for RN-komponent)**

Run: `cd mobile && npx expo start`
Tjek i appen (simulator/enhed):
1. Uden mig valgt → Spor viser dæmpet streg + "Vælg dig selv i en profil".
2. Åbn en profil, tryk "Det er mig i slægten" → tilbage til Spor.
3. Fokus på en anden person → streg lyser, badge viser pil + "N spring til dig"; pilen peger mod den gestus der mindsker N.
4. Navigér hele vejen til mig → badge bliver "★ Du er her" ved ankomst.
5. (Hvis flere slægter er loadet) vælg mig i en anden slægt end fokus → streg skjult.

Noter resultatet (bestået/afvigelser) i commit-beskrivelsen.

- [ ] **Step 8: Commit**

```bash
cd mobile && git add "src/app/(tabs)/tree.tsx"
git commit -m "$(cat <<'EOF'
feat(mobile): vej-til-mig wayfinder i Spor-variant

Rød streg kobles til meId: pil + antal spring mod eget kort, ★ ved
ankomst, hint når mig ikke er valgt, skjult uden fælles ane.

Claude-Session: https://claude.ai/code/session_01HWFBATmnarqAbdt5npiHZN
EOF
)"
```

---

## Self-Review

**Spec coverage:**
- Komponent 1 (pathfinder `wayToMe`) → Task 1. ✓ (signatur, algoritme-grene, edge cases, null-tilfælde alle dækket i kode + tests)
- Komponent 2 (UI streg-tilstande + badge) → Task 2. ✓ (alle 4 tabel-tilstande: ikke-valgt/arrived/step/null)
- Komponent 3 (golden-tests) → Task 1 Step 1-5. ✓ (alle 6 spec-scenarier + ekstra "ukendt mig")

**Placeholder-scan:** Ingen TBD/TODO; al kode konkret; manuel UI-test har eksplicit tjekliste (RN-komponent kan ikke unit-testes meningsfuldt her). ✓

**Type-konsistens:** `WayStep` defineret Task 1, brugt Task 2. `wayToMe`-signatur identisk i interface-blok, kode og tests. `childrenOf(model, parentId)`-orden = søskende-orden brugt konsistent i `childIndex`. `ARROW` dækker `Exclude<WayStep,'arrived'>` (de fire retninger). ✓

**Bevidst udeladt (matcher spec YAGNI):** intet tryk-for-hop, ingen gestus-model-ændring, ingen ny store-state.
