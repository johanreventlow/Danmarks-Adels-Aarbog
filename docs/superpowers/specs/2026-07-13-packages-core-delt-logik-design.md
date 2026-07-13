# Design: `packages/core` — delt web↔mobil-logik (review 27, Bølge 3 #13)

**Dato:** 2026-07-13
**Status:** Godkendt design (afventer dual-review + implementeringsplan)
**Kilde:** Review 27 §2 (rodårsag #2: web↔mobil-duplikering) + Bølge 3-item #13
**Relateret:** [[review-cycle-port-shared-vs-specific]], [[vercel-deploy-web]]

---

## 1. Problem

`web/` og `mobile/` er to selvstændige npm-projekter uden delingsmekanisme. ~11 rene,
DOM/RN/netværks-frie logik-moduler er fysisk spejlet i begge apps. En bugfix i én kopi
når ikke automatisk den anden. Bølge 2 tilføjede et `parity.test.ts` der pinner **et
udsnit** (`buildGenCoords`, `buildParentsUnknown`, `buildAnchorPeers`) tegn-for-tegn —
men resten af den spejlede flade er uovervåget.

**Empirisk driftstilstand (målt 2026-07-13):**

| Fil | Kode-drift | Vurdering |
|---|---|---|
| collapseSameAs, relationship, generations, buildModel, sammeSomPreflight, buildGeo, geoSelectors | ingen (identisk) | ren delt logik |
| fields, pickPreferredBio, collation, mentions | kun kommentar-drift, kode identisk | ren delt logik |
| **types.ts** | **ægte *bidirektionel* drift** — begge har unikke felter; `linjeByPerson` er hård type-konflikt (`string` vs `string[]`) | delt fundament, kræver **snæver type-grænse**, ikke superset (§5.1) |
| redaktionRead (467), redaktionWrite (153), bookmarks (121) | tung, ægte kode-drift | **ægte platform-specifik — flytter IKKE** |
| model.ts (kun web), load.ts (kun mobil) | fetch-orkestrering | orkestrering flytter IKKE, men **`getAll` flytter** (§6) |
| `getAll` (i `paginate.ts` + indlejret i `load.ts`) | dupleret, platform-fri | **flytter til core** (dual-review-fund) |
| tree.ts (web) / selectors.ts (mobil) | 6 delte funktioner (parity-guarded), + platform-specifikke | 6 delte flyttes hvis separable, ellers guard beholdes (§6.1) |

Kernen er lille og stabil: de rene *funktioner* er reelt identiske i dag. De to reelle
overraskelser (fundet i dual-review) er (a) `types.ts` divergerer bidirektionelt *under*
de identiske funktioner, og (b) parity-guarden dækker 6 tree/selectors-funktioner — mere
delt flade end først antaget.

## 2. Beslutning

**Tilgang A — fuld `packages/core` npm-workspace — eksekveret spike-first.**

Forkastede alternativer:
- **B (udvidet paritetsværn):** billigst, men efterlader dobbelt-redigering og løser ikke rodårsagen.
- **C (B + udskudt ADR):** var anbefalet så længe mobil antoges live i prod. Da mobil kun
  kører på udviklerens egen enhed (dev-stadie), falder A's tungeste con (brækket prod-build)
  væk, og Expo SDK 56's stærke monorepo-støtte gør Metro-friktionen lav. A blev den rigtige.

Spike-first = C's disciplin foldet ind i A: bevis mobil-Metro + Vercel *før* fuld flytning,
fald tilbage til B hvis et checkpoint fejler. Ingen "flyt alle og se".

## 3. Arkitektur

**Source-only intern pakke — ingen build-artefakt.** Begge bundlere (Vite, Metro)
transpilerer rå `.ts` direkte; ingen `dist/`, ingen watch-loop.

```
/  (nyt monorepo-rod)
  package.json          # npm workspaces: ["packages/*", "web", "mobile"]
  packages/core/
    package.json        # name "@daa/core"; "exports": { ".": "./src/index.ts" }; eget "test"-script + vitest-dep; ingen build-script
    tsconfig.json       # strict; ingen DOM/RN-lib; noEmit
    src/
      index.ts          # re-eksporterer modulerne + delt-type-udsnit
      types.ts          # SNÆVERT delt-type-udsnit (kun typer de flyttede moduler bruger — se §5.1)
      collapseSameAs.ts
      relationship.ts
      generations.ts
      buildModel.ts
      sammeSomPreflight.ts
      buildGeo.ts
      geoSelectors.ts
      fields.ts
      pickPreferredBio.ts
      collation.ts
      mentions.ts
      getAll.ts         # generisk paginering, udtrukket fra paginate.ts/load.ts (§6)
      # (evt. treeShared.ts — de 6 tree/selectors-funktioner, hvis rent separable, §6.1)
      __tests__/        # de delte tests, samlet ét sted (vitest)
  web/    → import { … } from "@daa/core"
  mobile/ → import { … } from "@daa/core"
```

**Intern afhængighedsgraf (verificeret ren):** `collapseSameAs → fields, types`;
`sammeSomPreflight → collapseSameAs, types`; resten `→ types` kun. Ingen eksterne/platform-imports.

## 4. Spike-checkpoints (fase 1 — bevis før flytning)

> **Revideret efter dual-review (Codex, 2026-07-13):** spiken flyttede oprindeligt
> kun `collation.ts`, men den har nul interne deps og importeres ikke af mobil-jest —
> den ville bevise for lidt. Spiken flytter i stedet en fil **med både `./types`-dep
> og faktisk mobil-jest-forbrug**.

Spiken flytter **`pickPreferredBio.ts` + det minimale delte type-udsnit den kræver**
(fra §5) til `packages/core`, wirer workspace-skelettet, og verificerer i rækkefølge:

1. **mobil (Metro):** Expo/Metro starter + bundler `@daa/core`-import på device/simulator.
   *NB: mobil har ingen `babel.config.js` — bekræft eksplicit at babel-preset-expo
   transpilerer rå TS fra workspace-pakken, ikke kun fra `mobile/src`.*
2. **mobil (jest):** en `@daa/core`-import eksekveres i en mobil-jest-test.
   *Kendt gotcha (verificeret): `jest-expo`-presettets `transformIgnorePatterns` ignorerer
   `node_modules` undtagen en allowlist der IKKE indeholder `@daa` → rå TS brækker. Fix:
   whitelist `@daa` i `transformIgnorePatterns`.* Dette er den mest sandsynlige stille fejl.
3. **web:** `tsc -b` + `vite build` grønne med `@daa/core`-import (Vite/vitest transformerer
   workspace-deps via esbuild — laveste risiko).
4. **Vercel (deep-link, ikke kun build):** preview-deploy hvor en **dyb URL** (fx
   `/slaegt/<id>`) faktisk loader — se §7 for topologi-valget der ligger til grund.
5. **type-resolvering:** `pickPreferredBio`'s `./types`-dep resolver på tværs af workspace
   i begge apps' `tsc` (beviser at den delte-type-grænse fra §5 virker mekanisk).

**Exit-kriterium:** alle fem grønne → fortsæt til §5. Ét fejler → stop, rapportér årsag,
fald tilbage til B (udvid `parity.test.ts` til alle rene filer i stedet).

## 5. Fuld ekstraktion (fase 2 — kun hvis spiken er ren)

> **Revideret efter dual-review (Codex, 2026-07-13):** den oprindelige plan om at
> flytte hele `types.ts` som "web-superset" var **empirisk forkert**. `types.ts` er
> bidirektionelt inkompatibel: mobil har felter web mangler (`visning_fuldt_navn`,
> `aar`, media-felter, `mediaById`) og web har felter mobil mangler (`geo`, `lineage`,
> `genCoordsByPerson`, `parentsUnknownByPerson`). Værst: `linjeByPerson` er en **hård
> type-konflikt** — web `Record<string,string>` vs mobil `Record<string,string[]>`.
> Et naivt superset kan derfor ikke kompilere for begge, og at slette begge app-`types.ts`
> ville udvide scope langt ud over de 11 moduler.

1. **Definér en snæver delt-type-grænse — flyt IKKE hele `types.ts`.** Udtræk kun de
   typer de ekstraherede moduler faktisk bruger, til `packages/core/src/types.ts`.
   App-specifikke `Raw*`, `Aux` og de berigede `Model`-udvidelser (geo/lineage/media)
   **bliver i hver app**. Den ene ægte konflikt (`linjeByPerson`) forsones eksplicit:
   afklar hvilken form de delte funktioner reelt producerer (én collapsed grundlægger
   kan høre til flere linjer → `string[]` er sandsynligvis korrekt), ret den forkerte
   app-annotation, og bekræft begge apps' `tsc` grønt **før** de øvrige filer flyttes.
2. Flyt de øvrige rene filer til `packages/core/src/` (kanonisk ÉN kopi). Inkl. **`getAll`**
   (se §6 — ekstraheres fra `paginate.ts`/`load.ts`).
3. Opdatér imports i begge apps: `../data/x` / `../lib/x` → `@daa/core`.
4. Flyt de delte tests til `packages/core/src/__tests__/`; slet duplikerede test-kopier.
5. Slet de spejlede app-kopier af de flyttede filer (behold app-`types.ts` med det
   ikke-delte restindhold).
6. **Reducér `parity.test.ts` KUN for faktisk flyttede funktioner** (se §6.1) — ikke før.

## 6. Hvad der bevidst IKKE flytter

- **Fetch-orkestrering** (`model.ts`, `load.ts`) — platform-specifik query-batching mod Supabase.
  **MEN:** den generiske `getAll<T>`-paginering (identisk i `web/src/data/paginate.ts:6`
  og indlejret i `mobile/src/data/load.ts:42`, ingen platform-import — koden flager sig
  selv "delt-pakke-ekstraktion er follow-up") **flytter til core**. `model.ts`/`load.ts`
  beholder kun selve orkestreringen og importerer `getAll` fra `@daa/core`.
- **Driftet trio** (`redaktionRead`, `redaktionWrite`, `bookmarks`) — ægte platform-forskelle
  (fx `localStorage` vs `AsyncStorage`). Forsøg på at dele dem ville tvinge falsk fælles-abstraktion.

### 6.1 `tree.ts` / `selectors.ts` — mere delt end først antaget

> **Rettet efter dual-review:** spec'en påstod fejlagtigt at "kun `buildAnchorPeers` er
> delt". `buildAnchorPeers` **findes ikke** som funktion (kun i en kommentar). Den
> nuværende `parity.test.ts` pinner faktisk **6 delte tree↔selectors-funktioner**:
> `columnLabel`, `columnGen`, `buildDirection`, `buildBidirectionalColumns`,
> `unknownParentRing`, `unknownChildSection` (`parity.test.ts:83-105`).

Beslutning for disse 6: **verificér om de er rent separable** (ingen platform-import i
netop de funktioner). Hvis ja → ekstrahér dem til et `packages/core/src/treeShared.ts`-modul
og lad `tree.ts`/`selectors.ts` beholde de platform-specifikke selektorer. Hvis nej →
behold dem duplikeret **med** deres parity-assertions. **Parity-assertions for en funktion
fjernes først når og hvis funktionen faktisk er flyttet til core** — aldrig før.

## 7. Risici (eksplicit)

| Risiko | Håndtering |
|---|---|
| **Vercel-topologi + deep-links** (`web/vercel.json` har SPA-rewrite `/(.*) → /index.html`) | Vælg ÉN reproducerbar topologi (se nedenfor) — build-success ≠ deep-links virker; valider en dyb URL på preview |
| Vercel-install fra web-subdir finder ikke `@daa/core` | Del af topologi-valget; verificeres på preview-deploy, ikke i blinde |
| Lockfile-konsolidering (web+mobil har hver sin `package-lock.json`) | Workspaces → én root-lock; spiken afgør konsolidering vs. path-alias |
| **`types.ts` bidirektionel + `linjeByPerson`-type-konflikt** | §5.1: snæver delt-type-grænse (flyt ikke hele filen) + eksplicit forsoning af `linjeByPerson`; begge apps' `tsc` grønt før øvrige filer flyttes |
| **mobil-jest transformerer ikke rå TS fra `@daa/core`** (`jest-expo` `transformIgnorePatterns`-allowlist omfatter ikke `@daa`) | Spike-checkpoint 2; whitelist `@daa` i `transformIgnorePatterns` |
| Metro/babel transpilerer ikke workspace-TS (mobil har ingen `babel.config.js`) | Spike-checkpoint 1 — bekræft babel-preset-expo dækker workspace-pakken |
| Metro resolver ikke pakke uden for `mobile/` | SDK 56 auto-detekterer workspaces; ellers `metro.config.js watchFolders` |
| React 18 (web) vs 19 (mobil)-konflikt | Ingen — `@daa/core` er ren TS uden React |

**Vercel-topologi (afklares i spiken, ikke antaget):** to reproducerbare muligheder —
(a) behold **Root Directory=web** og konfigurér Vercel til at inkludere kilde uden for
roden + køre install fra repo-rod (så `@daa/core` resolves); `web/vercel.json`-rewrites
forbliver på plads. (b) skift til **repo-rod** med eksplicit web-workspace build/output-
kommandoer og **flyt/dupliker rewrite-konfigurationen** til den nye projekt-rod. Uanset
valg: valideringskriteriet er at en **dyb URL loader** på preview, ikke blot at buildet grønt.

## 8. Testing

- `packages/core` ejer nu de delte tests (vitest). `packages/core/package.json` skal have
  et **eksplicit `test`-script + `vitest`-devDependency** (core kører sin egen suite, ikke
  web's). Ingen adfærdsændring forventes — flytning er mekanisk, så eksisterende grønne
  tests er regressions-orakel.
- Begge apps' `tsc`-typecheck er den primære gate på at imports + typer hænger sammen —
  særligt den forsonede `linjeByPerson` (§5.1).
- Ingen ny test-logik kræves (ren refactor uden adfærdsændring) udover: (a) bekræft at de
  flyttede test-filer stadig eksekverer, og (b) den ene nye mobil-jest-import-test fra
  spike-checkpoint 2 (bevis at `@daa/core` transformeres).

## 9. Succes-kriterier

- [ ] Spike: alle **5** checkpoints grønne (ellers dokumenteret fallback til B)
- [ ] De rene filer (11 moduler + `getAll`) findes i ÉN kanonisk kopi under `packages/core`
- [ ] Delt-type-grænsen defineret snævert; `linjeByPerson`-konflikt forsonet; begge apps `tsc`-grønne
- [ ] App-`types.ts` beholder kun ikke-delt restindhold; ingen spejlede kopier af flyttede filer
- [ ] `packages/core/package.json` har eget `test`-script + `vitest`-dep
- [ ] Alle eksisterende tests grønne (web vitest, core vitest, mobil jest inkl. ny import-test)
- [ ] Web-Vercel-deploy: en **dyb URL** loader på preview (ikke kun build-success)
- [ ] Mobil-app kører på simulator/device med delt import
- [ ] De 6 tree/selectors-funktioner: enten flyttet til core, eller stadig parity-guarded
      (aldrig guard fjernet uden flytning)

---

## Dual-review reconcile (Codex, 2026-07-13)

**Verdict:** needs-attention (5 fund, alle indarbejdet). Alle verificeret empirisk i
denne reconcile — ingen peer-review-laundering.

| Fund | Alvor | Bucket | Repro-evidens | Status |
|---|---|---|---|---|
| types.ts ikke web-superset; bidirektionel + `linjeByPerson`-type-konflikt | HIGH | semantic | `web:244 Record<string,string>` vs `mobil:215 Record<string,string[]>`; unikke felter i begge retninger | §5.1 omskrevet til snæver type-grænse |
| parity guarder 6 ægte funktioner; `buildAnchorPeers` fiktiv | HIGH | false-confidence | `parity.test.ts:83-105` | §6.1 tilføjet; guard-fjernelse gated på faktisk flytning |
| spike beviste for lidt (collation: ingen deps/jest) | MEDIUM | process | matcher egen F1 | §4 spiker nu `pickPreferredBio` + mobil-jest-import |
| `getAll` misklassificeret som platform-specifik | MEDIUM | cleanup/scope | identisk `paginate.ts:6` + `load.ts:42`, ingen platform-import | §6 flytter `getAll` til core |
| Vercel-topologi + deep-links underspecificeret | MEDIUM | false-confidence | `web/vercel.json` SPA-rewrite findes | §7 konkret topologi-valg + deep-link-validering |

**Læring:** ved "spejlede filer er identiske"-antagelser — typefundamentet (`types.ts`)
og test-guardens *faktiske* omfang skal verificeres separat; "identisk kode" i funktioner
udelukker ikke divergerende type-kontrakter under dem. [[collapse-write-vs-read-idspace]]-
familien: stol ikke på en kommentars ordvalg (`buildAnchorPeers`) som funktions-inventar.
