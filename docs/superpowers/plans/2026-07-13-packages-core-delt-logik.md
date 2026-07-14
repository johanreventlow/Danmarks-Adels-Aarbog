# packages/core — delt web↔mobil-logik — Implementeringsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Udtræk den delte, DOM/RN/netværks-frie logik fra `web/` og `mobile/` til én kanonisk npm-workspace-pakke `@daa/core`, så drift mellem de to apps bliver umulig.

**Architecture:** npm-workspaces monorepo. `packages/core` er en source-only-pakke (rå `.ts`, ingen build-step) som både Vite (web) og Metro/Expo SDK 56 (mobil) transpilerer direkte. Eksekveres **spike-first**: fase 1 beviser tooling (Metro + jest + Vercel + cross-workspace type-resolvering) med én fil (`generations.ts`); kun hvis gaten er grøn kører fase 2 (fuld ekstraktion). Fejler gaten → fallback til plan B (udvid `parity.test.ts`).

**Tech Stack:** TypeScript 5.5 (web) / 6.0 (mobil), Vite 5 + vitest (web), Expo SDK 56 + Metro + jest-expo (mobil), npm 10 workspaces, Node 22.

## Global Constraints

- **Source-only pakke:** `@daa/core` eksporterer rå `.ts` via `"exports": { ".": "./src/index.ts" }`. INGEN build-script, INGEN `dist/`.
- **Ingen React/RN/DOM i core:** kun ren TS. `packages/core/tsconfig.json` må ikke inkludere DOM- eller RN-lib.
- **Ingen adfærdsændring:** dette er en ren refactor. Eksisterende grønne tests (web vitest, mobil jest) er regressions-orakel. Ingen ny logik.
- **Parity-guard-regel:** en funktions parity-assertion i `parity.test.ts` fjernes KUN når funktionen faktisk er flyttet til core — aldrig før.
- **Git:** arbejd på branch `refactor/packages-core-delt-logik` (allerede oprettet). Ingen push/merge uden eksplicit brugergodkendelse. Commit-footer: `Claude-Session: https://claude.ai/code/session_01HDiHmLaxpqNjttu2jtDQvG`.
- **linjeByPerson-konflikt:** web `Record<string,string>` vs mobil `Record<string,string[]>` — forsones eksplicit i Task 4, ikke antaget additivt.

---

## Filstruktur

**Nyt:**
- `package.json` (repo-rod) — workspaces-manifest
- `packages/core/package.json` — `@daa/core`, eget `test`-script + vitest-dep
- `packages/core/tsconfig.json` — strict, ingen DOM/RN
- `packages/core/vitest.config.ts` — node-env
- `packages/core/src/index.ts` — re-eksporterer alle flyttede moduler + delt-type-udsnit
- `packages/core/src/types.ts` — SNÆVERT delt-type-udsnit (kun typer de flyttede moduler bruger)
- `packages/core/src/*.ts` — de flyttede moduler (generations, collation, mentions, fields, pickPreferredBio, relationship, collapseSameAs, sammeSomPreflight, buildGeo, geoSelectors, buildModel, getAll)
- `packages/core/src/__tests__/*.test.ts` — de flyttede tests
- `mobile/metro.config.js` — monorepo watchFolders (hvis SDK 56-default ikke rækker)

**Modificeret:**
- `mobile/jest.config.js` — `transformIgnorePatterns` whitelister `@daa`
- `web/src/**`, `mobile/src/**` — imports `../data/x`/`../lib/x` → `@daa/core`
- `web/src/data/types.ts`, `mobile/src/data/types.ts` — beholder kun ikke-delt restindhold
- `web/src/data/paginate.ts`, `mobile/src/data/load.ts` — importerer `getAll` fra core
- `web/src/data/__tests__/parity.test.ts`, `mobile/src/data/__tests__/parity.test.ts` — reduceres for flyttede funktioner

---

# FASE 1 — SPIKE (GO/NO-GO-gate)

## Task 1: Workspace-skelet + flyt `generations.ts`

**Files:**
- Create: `package.json` (rod), `packages/core/package.json`, `packages/core/tsconfig.json`, `packages/core/vitest.config.ts`, `packages/core/src/index.ts`, `packages/core/src/types.ts`, `packages/core/src/generations.ts`, `packages/core/src/__tests__/generations.test.ts`
- Modify: `mobile/jest.config.js`
- Delete (efter flyt): `web/src/data/generations.ts`, `mobile/src/data/generations.ts`, deres to `__tests__/generations.test.ts`

**Interfaces:**
- Produces: `@daa/core` eksporterer `buildGenCoords`, `buildParentsUnknown`, `GenCoord` (+ øvrige generations-eksporter) og typerne `RawExtId`, `RawLineage`.
- Consumes: intet (første task).

- [ ] **Step 1: Opret repo-rod `package.json`**

```json
{
  "name": "danmarksadelsaarbog-monorepo",
  "private": true,
  "workspaces": ["packages/*", "web", "mobile"]
}
```

- [ ] **Step 2: Opret `packages/core/package.json`**

```json
{
  "name": "@daa/core",
  "version": "0.0.0",
  "private": true,
  "type": "module",
  "exports": { ".": "./src/index.ts" },
  "scripts": { "test": "vitest run", "typecheck": "tsc --noEmit" },
  "devDependencies": { "vitest": "^3.0.0", "typescript": "^5.5.3" }
}
```

- [ ] **Step 3: Opret `packages/core/tsconfig.json`** (ingen DOM/RN)

```json
{
  "compilerOptions": {
    "target": "ES2020",
    "module": "ESNext",
    "lib": ["ES2020"],
    "moduleResolution": "bundler",
    "strict": true,
    "noEmit": true,
    "isolatedModules": true,
    "verbatimModuleSyntax": false,
    "skipLibCheck": true
  },
  "include": ["src"]
}
```

- [ ] **Step 4: Opret `packages/core/vitest.config.ts`**

```ts
import { defineConfig } from 'vitest/config';
export default defineConfig({ test: { globals: true, environment: 'node' } });
```

- [ ] **Step 5: Flyt `generations.ts` + de to typer til core**

```bash
cd /Users/johanreventlow/TypeScript/danmarksadelsaarbog
git mv web/src/data/generations.ts packages/core/src/generations.ts
git mv web/src/data/__tests__/generations.test.ts packages/core/src/__tests__/generations.test.ts
git rm mobile/src/data/generations.ts mobile/src/data/__tests__/generations.test.ts
```

Kopiér `RawExtId` og `RawLineage` (verificeret code-identiske mellem apps) fra `web/src/data/types.ts` til en ny `packages/core/src/types.ts`. Ret `generations.ts`'s import fra `./types` til `./types` (samme relative sti — begge nu i core). Behold `RawExtId`/`RawLineage` i app-`types.ts` for nu (de øvrige app-filer bruger dem stadig — fjernes i fase 2).

- [ ] **Step 6: Opret `packages/core/src/index.ts`**

```ts
export * from './generations';
export type { RawExtId, RawLineage } from './types';
```

- [ ] **Step 7: Peg begge apps' `generations`-forbrugere mod `@daa/core`**

I `mobile/src/data/load.ts`, `mobile/src/data/selectors.ts`, `mobile/src/store/useStore.ts`, `mobile/src/app/redaktion/person/[id].tsx` og alle web-forbrugere: skift `from '../data/generations'` / `from './generations'` → `from '@daa/core'`. Find dem:

```bash
grep -rln "data/generations\|from './generations'\|from '\.\./generations'" web/src mobile/src
```

- [ ] **Step 8: Whitelist `@daa` i mobil-jest** — `mobile/jest.config.js`, tilføj efter `moduleNameMapper`:

```js
  transformIgnorePatterns: [
    'node_modules/(?!((jest-)?react-native|@react-native(-community)?|expo(nent)?|@expo(nent)?/.*|@expo-google-fonts/.*|react-navigation|@react-navigation/.*|@unimodules/.*|unimodules|sentry-expo|native-base|react-native-svg|@daa/.*))',
  ],
```

- [ ] **Step 9: Installér workspace fra roden**

```bash
cd /Users/johanreventlow/TypeScript/danmarksadelsaarbog && npm install
```
Expected: `@daa/core` symlinkes ind i `node_modules/@daa/core`; ingen fejl. Bemærk: web+mobil `package-lock.json` erstattes af én root-lock (forventet — noter i commit).

- [ ] **Step 10: web tsc + vitest grøn**

```bash
cd web && npx tsc -b && npx vitest run
```
Expected: PASS. `@daa/core`-import resolver; generations-testen kører nu fra core (via web's vitest? nej — kør core-testen separat):

```bash
cd ../packages/core && npx vitest run
```
Expected: generations-testen PASS i core.

- [ ] **Step 11: mobil jest grøn (beviser @daa-transform)**

```bash
cd ../../mobile && npx jest
```
Expected: PASS. Hvis fejl `SyntaxError`/`Unexpected token` på `@daa/core` → `transformIgnorePatterns` (Step 8) ramte ikke; juster og gentag. **Dette er den mest sandsynlige spike-fejl.**

- [ ] **Step 12: Commit**

```bash
cd /Users/johanreventlow/TypeScript/danmarksadelsaarbog
git add -A
git commit -m "spike(core): workspace-skelet + flyt generations.ts til @daa/core

Fase-1-spike. Beviser Metro/jest/type-resolvering før fuld ekstraktion.
Root-workspace konsoliderer web+mobil package-lock til én root-lock.

Claude-Session: https://claude.ai/code/session_01HDiHmLaxpqNjttu2jtDQvG"
```

## Task 2: Spike runtime-gate (Metro + Vercel deep-link)

**Files:** ingen kode — verifikation. Muligt: `mobile/metro.config.js` hvis default ikke rækker.

- [ ] **Step 1: Mobil på simulator/device**

```bash
cd mobile && npx expo start --clear
```
Åbn appen. Naviger til en skærm der bruger generations (stamtræ/tree). Expected: bundler + rendrer uden `Unable to resolve "@daa/core"`. Hvis resolve-fejl → opret `mobile/metro.config.js`:

```js
const { getDefaultConfig } = require('expo/metro-config');
const path = require('path');
const projectRoot = __dirname;
const workspaceRoot = path.resolve(projectRoot, '..');
const config = getDefaultConfig(projectRoot);
config.watchFolders = [workspaceRoot];
config.resolver.nodeModulesPaths = [
  path.resolve(projectRoot, 'node_modules'),
  path.resolve(workspaceRoot, 'node_modules'),
];
module.exports = config;
```
Gentag `expo start --clear`.

- [ ] **Step 2: web produktionsbuild lokalt**

```bash
cd ../web && npm run build
```
Expected: `vite build` grøn med `@daa/core` bundlet ind.

- [ ] **Step 3: Vercel preview-deploy + deep-link (BRUGER-GATET)**

Vercel bygger via GitHub-integration ved push. Dette kræver eksplicit brugergodkendelse til at pushe spike-branchen. Alternativt lokal `vercel` CLI. Når deployet:
- Verificér at **install kører fra repo-rod** (så `@daa/core` resolves) — juster Root Directory / install-command hvis nødvendigt (§7 topologi-valg i spec).
- Hit en **dyb URL** (fx `/slaegt/<id>` eller app'ens deep-link-rute), ikke kun forsiden. Expected: siden loader (SPA-rewrite fra `web/vercel.json` intakt).

- [ ] **Step 4: GO/NO-GO-beslutning**

Alle checkpoints grønne (Task 1 Step 10-11 + Task 2 Step 1-3) → **GO**, fortsæt til Fase 2. Ét fejler uopretteligt → **NO-GO**: dokumentér årsag i spec'ens §4, revert workspace-skelettet, og skift til plan B (udvid `parity.test.ts` til alle rene filer). Commit metro.config.js hvis oprettet:

```bash
git add mobile/metro.config.js && git commit -m "spike(core): metro monorepo-config (watchFolders)

Claude-Session: https://claude.ai/code/session_01HDiHmLaxpqNjttu2jtDQvG"
```

---

# FASE 2 — FULD EKSTRAKTION (kun ved GO)

## Task 3: Flyt de selvstændige rene filer (ingen `./types`-dep)

**Files:**
- Move → `packages/core/src/`: `collation.ts` (fra `web/src/lib/`), `mentions.ts` (fra `web/src/lib/`), `fields.ts`, `pickPreferredBio.ts` (fra `web/src/data/`) + deres tests
- Delete: mobil-kopierne + deres tests
- Modify: `packages/core/src/index.ts`; alle app-imports af de fire

**Interfaces:**
- Produces: `@daa/core` eksporterer nu også `collation`-, `mentions`-, `fields`- og `pickPreferredBio`-API'erne (`pickPreferredBio`, `NarrativeCand`, m.fl.).

- [ ] **Step 1: Flyt de fire filer + tests (web-kopien er kanonisk)**

```bash
cd /Users/johanreventlow/TypeScript/danmarksadelsaarbog
git mv web/src/lib/collation.ts packages/core/src/collation.ts
git mv web/src/lib/mentions.ts packages/core/src/mentions.ts
git mv web/src/data/fields.ts packages/core/src/fields.ts
git mv web/src/data/pickPreferredBio.ts packages/core/src/pickPreferredBio.ts
# tests:
git mv web/src/data/__tests__/pickPreferredBio.test.ts packages/core/src/__tests__/pickPreferredBio.test.ts
# (collation/mentions/fields-tests: find og flyt tilsvarende hvis de findes)
git rm mobile/src/lib/collation.ts mobile/src/lib/mentions.ts mobile/src/data/fields.ts mobile/src/data/pickPreferredBio.ts
# + mobil-test-kopier
```

- [ ] **Step 2: Ret `packages/core/src/index.ts`** — tilføj:

```ts
export * from './collation';
export * from './mentions';
export * from './fields';
export * from './pickPreferredBio';
```

- [ ] **Step 3: Opdatér alle app-imports af de fire → `@daa/core`**

```bash
grep -rln "lib/collation\|lib/mentions\|data/fields\|data/pickPreferredBio" web/src mobile/src
```
Skift hver til `from '@daa/core'`.

- [ ] **Step 4: Kør alle suiter grønne**

```bash
cd packages/core && npx vitest run && cd ../../web && npx tsc -b && npx vitest run && cd ../mobile && npx jest && npx tsc --noEmit
```
Expected: alt PASS.

- [ ] **Step 5: Commit**

```bash
cd /Users/johanreventlow/TypeScript/danmarksadelsaarbog && git add -A
git commit -m "refactor(core): flyt selvstændige rene filer (collation, mentions, fields, pickPreferredBio)

Claude-Session: https://claude.ai/code/session_01HDiHmLaxpqNjttu2jtDQvG"
```

## Task 4: Forson `linjeByPerson` + definér snæver delt-type-grænse

**Files:**
- Modify: `packages/core/src/types.ts` (voks til fuldt delt-udsnit), `web/src/data/types.ts`, `mobile/src/data/types.ts`

**Interfaces:**
- Produces: `@daa/core/types` eksporterer alle typer som de flyttede/kommende moduler bruger (`Model`, `Aux`, `Koen`, `Konfidens`, `KONFIDENS_RANK`, `KONFIDENS_VALUES`, `Geo`, `GeoKind`, `GeoPoint`, `AppPerson`, `Union`, `RawEstate`, `RawFact`, `RawPlace`, m.fl.), med `linjeByPerson: Record<string, string[]>`.

- [ ] **Step 1: Fastlæg korrekt `linjeByPerson`-form**

Inspicér hvad `buildModel` faktisk skriver til `linjeByPerson`:

```bash
grep -n "linjeByPerson" web/src/data/buildModel.ts mobile/src/data/buildModel.ts
```
En collapsed grundlægger kan høre til flere linjer → `Record<string, string[]>` (mobils form) er korrekt. Web's `string` er den forkerte annotation. Bekræft ved at læse tildelings-koden.

- [ ] **Step 2: Byg det delte type-udsnit i core**

Kopiér de typer de 11 moduler + getAll refererer, fra web-`types.ts` til `packages/core/src/types.ts`, MEN med `linjeByPerson: Record<string, string[]>`. Udelad app-specifikke typer der IKKE bruges af de delte moduler (behold dem i app-`types.ts`). Verificér hvilke typer der er delte:

```bash
grep -hoE "from ['\"]\./types['\"]" -A0 packages/core/src/*.ts
grep -rhoE "\b(Model|Aux|Koen|Konfidens|Geo|GeoKind|GeoPoint|AppPerson|Union|Raw[A-Za-z]+)\b" packages/core/src/*.ts | sort -u
```

- [ ] **Step 3: App-`types.ts` re-eksporterer delte typer fra core + beholder rest**

I `web/src/data/types.ts` og `mobile/src/data/types.ts`: fjern de nu-delte type-definitioner, tilføj `export type { … } from '@daa/core';` for dem, og behold KUN de app-specifikke (fx web's `geo`/`lineage`-Model-udvidelser hvis de ikke bruges i core, mobils media-felter). Ret evt. web-kode der antog `linjeByPerson: string`.

- [ ] **Step 4: Begge apps' tsc grøn (beviser forsoning)**

```bash
cd web && npx tsc -b && cd ../mobile && npx tsc --noEmit
```
Expected: PASS. Fejl på `linjeByPerson` i web = et reelt sted der antog scalar → ret det (læs koden, ikke cast).

- [ ] **Step 5: Commit**

```bash
cd /Users/johanreventlow/TypeScript/danmarksadelsaarbog && git add -A
git commit -m "refactor(core): snæver delt-type-grænse + forson linjeByPerson (string[] kanonisk)

Claude-Session: https://claude.ai/code/session_01HDiHmLaxpqNjttu2jtDQvG"
```

## Task 5: Flyt de `./types`-afhængige rene moduler

**Files:**
- Move → `packages/core/src/`: `relationship.ts`, `collapseSameAs.ts`, `sammeSomPreflight.ts`, `buildGeo.ts`, `geoSelectors.ts`, `buildModel.ts` + tests
- Delete: mobil-kopierne + tests
- Modify: `packages/core/src/index.ts`; app-imports

**Interfaces:**
- Consumes: delt-type-udsnit fra Task 4.
- Produces: `@daa/core` eksporterer nu hele den rene domænekerne.

- [ ] **Step 1: Flyt filerne (web kanonisk) i afhængighedsorden**

```bash
cd /Users/johanreventlow/TypeScript/danmarksadelsaarbog
for f in relationship collapseSameAs sammeSomPreflight buildGeo geoSelectors buildModel; do
  git mv web/src/data/$f.ts packages/core/src/$f.ts
  git rm mobile/src/data/$f.ts
done
# flyt tilhørende web-tests til core, git rm mobil-test-kopier (find dem først):
ls web/src/data/__tests__/ | grep -E "relationship|collapseSameAs|sammeSomPreflight|buildGeo|geoSelectors|buildModel"
```
Ret interne imports i de flyttede filer: `./collapseSameAs`, `./fields`, `./types` peger nu på core-nabo-filer (samme relative sti — ingen ændring nødvendig da alle er i `packages/core/src/`).

- [ ] **Step 2: Udvid `packages/core/src/index.ts`**

```ts
export * from './relationship';
export * from './collapseSameAs';
export * from './sammeSomPreflight';
export * from './buildGeo';
export * from './geoSelectors';
export * from './buildModel';
```

- [ ] **Step 3: Opdatér app-imports**

```bash
grep -rln "data/relationship\|data/collapseSameAs\|data/sammeSomPreflight\|data/buildGeo\|data/geoSelectors\|data/buildModel" web/src mobile/src
```
Skift hver til `@daa/core`.

- [ ] **Step 4: Alle suiter grønne**

```bash
cd packages/core && npx vitest run && cd ../../web && npx tsc -b && npx vitest run && cd ../mobile && npx jest && npx tsc --noEmit
```
Expected: alt PASS.

- [ ] **Step 5: Commit**

```bash
cd /Users/johanreventlow/TypeScript/danmarksadelsaarbog && git add -A
git commit -m "refactor(core): flyt types-afhængige rene moduler (relationship, collapse, buildModel m.fl.)

Claude-Session: https://claude.ai/code/session_01HDiHmLaxpqNjttu2jtDQvG"
```

## Task 6: Udtræk `getAll`-paginering til core

**Files:**
- Create: `packages/core/src/getAll.ts` + test
- Modify: `web/src/data/paginate.ts`, `mobile/src/data/load.ts`, `packages/core/src/index.ts`
- Delete: evt. `web/src/data/paginate.ts` hvis den KUN indeholder getAll

**Interfaces:**
- Produces: `@daa/core` eksporterer `getAll<T>(makeQuery: () => { range: (from, to) => PromiseLike<{ data: T[] | null; error: unknown }> }): Promise<T[]>`.

- [ ] **Step 1: Flyt `getAll` (web-kopien er kanonisk) til core**

Klip `getAll`-funktionen (+ `PAGE`-konstant + kommentar) fra `web/src/data/paginate.ts:1-` til ny `packages/core/src/getAll.ts`. Hvis `paginate.ts` kun var getAll → `git rm web/src/data/paginate.ts`. Tilføj `export * from './getAll';` til index.

- [ ] **Step 2: Skriv en lille getAll-test i core** (den var utestet før — spec §7 flaggede det)

```ts
import { describe, it, expect } from 'vitest';
import { getAll } from '../getAll';

describe('getAll', () => {
  it('paginerer indtil kort side', async () => {
    const pages = [Array.from({ length: 1000 }, (_, i) => i), [1000, 1001]];
    let call = 0;
    const rows = await getAll<number>(() => ({
      range: async () => ({ data: pages[call++] ?? [], error: null }),
    }));
    expect(rows).toHaveLength(1002);
  });
  it('kaster ved supabase-error', async () => {
    await expect(getAll<number>(() => ({
      range: async () => ({ data: null, error: { message: 'RLS' } }),
    }))).rejects.toBeTruthy();
  });
});
```

- [ ] **Step 3: `load.ts` importerer `getAll` fra core** — fjern den indlejrede `getAll`-definition i `mobile/src/data/load.ts:37-58`, tilføj `import { getAll } from '@daa/core';`. Ret web-forbrugere af `paginate.ts` → `@daa/core`.

- [ ] **Step 4: Alle suiter grønne** (samme kommando som Task 5 Step 4).

- [ ] **Step 5: Commit**

```bash
git commit -am "refactor(core): udtræk getAll-paginering til @daa/core (+ test)

Claude-Session: https://claude.ai/code/session_01HDiHmLaxpqNjttu2jtDQvG"
```

## Task 7: 6 tree/selectors-funktioner — flyt hvis separable

**Files:**
- Investigate: `web/src/data/tree.ts`, `mobile/src/data/selectors.ts`
- Muligt: Create `packages/core/src/treeShared.ts`; Modify tree.ts/selectors.ts

**Interfaces:**
- Produces (hvis flyttet): `@daa/core` eksporterer `columnLabel`, `columnGen`, `buildDirection`, `buildBidirectionalColumns`, `unknownParentRing`, `unknownChildSection`.

- [ ] **Step 1: Vurdér separabilitet**

```bash
grep -nE "^import|from ['\"]" web/src/data/tree.ts | grep -vE "from ['\"]\.|@daa"
```
Tjek om de 6 funktioner (og deres lokale helpers) refererer platform-ting (RN/DOM/react). Rent → flyt. Ikke rent → behold duplikeret + parity-guard.

- [ ] **Step 2a (hvis separable): flyt de 6 til `packages/core/src/treeShared.ts`**

Klip de 6 funktioner + deres private helpers til `treeShared.ts`, eksportér, og lad `tree.ts`/`selectors.ts` importere dem fra `@daa/core` + beholde de platform-specifikke selektorer. Tilføj til index.

- [ ] **Step 2b (hvis IKKE separable): dokumentér + behold**

Skriv en note i `parity.test.ts`-headeren om hvorfor de 6 forbliver spejlede (platform-kobling), og behold assertions uændret. Spring til Task 8.

- [ ] **Step 3: Alle suiter grønne** (samme kommando som Task 5 Step 4).

- [ ] **Step 4: Commit**

```bash
git commit -am "refactor(core): [flyt 6 tree/selectors-funktioner til core | behold spejlet — platform-koblet]

Claude-Session: https://claude.ai/code/session_01HDiHmLaxpqNjttu2jtDQvG"
```

## Task 8: Reducér parity-test + endelig oprydning

**Files:**
- Modify: `web/src/data/__tests__/parity.test.ts`, `mobile/src/data/__tests__/parity.test.ts`
- Verify: ingen spejlede kopier tilbage af flyttede filer

**Interfaces:** ingen nye.

- [ ] **Step 1: Fjern parity-assertions for FAKTISK flyttede funktioner**

`buildGenCoords`, `buildParentsUnknown` (generations, flyttet Task 1) → fjern deres `it(...)`. De 6 tree-funktioner → fjern KUN hvis Task 7 flyttede dem; ellers behold. Hvis parity-testen ender tom → `git rm` begge parity-test-filer + fjern `mobile/src/data/__tests__/parity.test.ts`.

- [ ] **Step 2: Verificér ingen spejlet drift tilbage**

```bash
for f in collapseSameAs relationship generations buildModel sammeSomPreflight buildGeo geoSelectors fields pickPreferredBio collation mentions; do
  w=$(find web/src -name "$f.ts"); m=$(find mobile/src -name "$f.ts")
  [ -n "$w" ] && echo "TILBAGE i web: $w"
  [ -n "$m" ] && echo "TILBAGE i mobil: $m"
done
echo "(intet output = alle flyttet)"
```
Expected: intet output.

- [ ] **Step 3: Fuld suite + typecheck begge apps + core**

```bash
cd packages/core && npx vitest run && cd ../../web && npx tsc -b && npx vitest run && cd ../mobile && npx jest && npx tsc --noEmit
```
Expected: alt grønt. Kør også mobil på device (Task 2 Step 1) én sidste gang som app-lag-verifikation.

- [ ] **Step 4: Commit + opdatér levende dokumentation**

Opdatér `docs/changelog.md` (dateret entry) + `docs/decisions.md` (packages/core-beslutning). Commit:

```bash
git add -A
git commit -m "refactor(core): reducér parity-test til stadig-spejlet flade + oprydning (review 27 Bølge 3 #13)

Claude-Session: https://claude.ai/code/session_01HDiHmLaxpqNjttu2jtDQvG"
```

- [ ] **Step 5: Åbn draft-PR** (kræver push-godkendelse fra bruger)

```bash
gh pr create --draft --base main --title "refactor(core): packages/core delt web↔mobil-logik (review 27 Bølge 3 #13)" --body "$(cat <<'PREOF'
## Summary
- Ny npm-workspace-pakke @daa/core med den rene, delte domænekerne (source-only).
- Eliminerer web↔mobil-duplikering (rodårsag #2 fra review 27).
- Dual-reviewet spec (Codex, 5 fund indarbejdet); spike-first eksekvering.

## Test plan
- [ ] web vitest + tsc grøn
- [ ] core vitest grøn
- [ ] mobil jest + tsc grøn
- [ ] mobil-app kører på device med delt import
- [ ] Vercel preview: dyb URL loader

https://claude.ai/code/session_01HDiHmLaxpqNjttu2jtDQvG
PREOF
)"
```

---

## Fallback (hvis Fase 1-gate = NO-GO)

Plan B: behold to kopier, men udvid `parity.test.ts` til at asserte alle 11 rene filer (+ getAll) er kode-identiske (normalisér kommentar/whitespace). Revert workspace-skelettet (`git revert` af Task 1-2-commits). Dokumentér i spec §4 hvilket checkpoint fejlede og hvorfor.
