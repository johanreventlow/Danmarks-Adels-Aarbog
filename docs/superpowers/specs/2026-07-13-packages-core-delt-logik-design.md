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
| **types.ts** | **ægte drift** — web har ekstra felter (`visning_fuldt_navn`, `id`, `source_id`, `aar` m.fl.) | delt fundament, kræver forsoning |
| redaktionRead (467), redaktionWrite (153), bookmarks (121) | tung, ægte kode-drift | **ægte platform-specifik — flytter IKKE** |
| model.ts (kun web), load.ts (kun mobil), paginate.ts | fetch-orkestrering | **platform-specifik — flytter IKKE** |
| tree.ts (web) / selectors.ts (mobil) | delvist delt (`buildAnchorPeers`) | forbliver splittet, parity-guard beholdes |

Kernen er altså lille og stabil: de rene funktioner er reelt identiske i dag. Den eneste
overraskelse er `types.ts`, som de 11 alle afhænger af, men hvor de to apps har divergeret
typedefinitionerne.

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
    package.json        # name "@daa/core"; "exports": { ".": "./src/index.ts" }; ingen build-script
    tsconfig.json       # strict; ingen DOM/RN-lib; noEmit
    src/
      index.ts          # re-eksporterer de 11 moduler + types
      types.ts          # KANONISK (forsonet superset — se §5)
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
      __tests__/        # de delte tests, samlet ét sted (vitest)
  web/    → import { … } from "@daa/core"
  mobile/ → import { … } from "@daa/core"
```

**Intern afhængighedsgraf (verificeret ren):** `collapseSameAs → fields, types`;
`sammeSomPreflight → collapseSameAs, types`; resten `→ types` kun. Ingen eksterne/platform-imports.

## 4. Spike-checkpoints (fase 1 — bevis før flytning)

Spiken flytter **kun `collation.ts`** (mindst, nul interne deps udover ingen) til
`packages/core`, wirer workspace-skelettet, og verificerer i rækkefølge:

1. **mobil:** Expo/Metro starter + bundler `@daa/core`-import på device/simulator uden resolve-fejl.
2. **web:** `tsc -b` + `vite build` grønne med `@daa/core`-import.
3. **Vercel:** web-deploy overlever workspace-install. Kendt gotcha ([[vercel-deploy-web]]):
   Root Directory=web + workspace-dep kræver at install kører fra repo-rod, ikke `web/`.
   Verificeres på en preview-deploy, ikke i blinde.
4. **tests:** `vitest run` (web + core) og `jest` (mobil) finder stadig flyttede/uflyttede tests.

**Exit-kriterium:** alle fire grønne → fortsæt til §5. Ét fejler → stop, rapportér årsag,
fald tilbage til B (udvid `parity.test.ts` til alle rene filer i stedet).

## 5. Fuld ekstraktion (fase 2 — kun hvis spiken er ren)

1. **Forson `types.ts` til kanonisk superset.** Web-versionen er rigest; tag den som
   udgangspunkt. Verificér at mobils rene funktioner (identisk kode) stadig `tsc`-kompilerer
   mod supersettet — ekstra felter er additivt sikre, men bekræftes empirisk, ikke antaget.
   Dette er den eneste ikke-mekaniske del af flytningen.
2. Flyt de resterende 10 filer til `packages/core/src/` (kanonisk ÉN kopi).
3. Opdatér imports i begge apps: `../data/x` / `../lib/x` → `@daa/core`.
4. Flyt de delte tests til `packages/core/src/__tests__/`; slet duplikerede test-kopier.
5. Slet de spejlede app-kopier af de 11 + `types.ts`.
6. **Reducér `parity.test.ts`:** de flyttede filer er nu én kilde → deres parity-assertions
   fjernes. Testen beholder kun det stadig-spejlede (`buildAnchorPeers` i `tree.ts`/`selectors.ts`).

## 6. Hvad der bevidst IKKE flytter

- **Fetch-lag** (`model.ts`, `load.ts`, `paginate.ts`) — platform-specifik netværks-orkestrering.
- **Driftet trio** (`redaktionRead`, `redaktionWrite`, `bookmarks`) — ægte platform-forskelle
  (fx `localStorage` vs `AsyncStorage`). Forsøg på at dele dem ville tvinge falsk fælles-abstraktion.
- **`tree.ts` / `selectors.ts`** — kun `buildAnchorPeers` er delt (parity-guarded); resten divergerer bevidst.

## 7. Risici (eksplicit)

| Risiko | Håndtering |
|---|---|
| Vercel-install fra web-subdir finder ikke `@daa/core` | Spike-checkpoint 3 på preview-deploy; alternativ = lettere path-alias-variant uden root-workspace |
| Lockfile-konsolidering (web+mobil har hver sin `package-lock.json`) | Workspaces → én root-lock; spiken afgør konsolidering vs. path-alias |
| `types.ts`-superset bryder mobil-`tsc` | §5.1 empirisk verifikation før flytning af de øvrige filer |
| Metro resolver ikke pakke uden for `mobile/` | SDK 56 auto-detekterer workspaces; ellers `metro.config.js watchFolders` — bevises i checkpoint 1 |
| React 18 (web) vs 19 (mobil)-konflikt | Ingen — `@daa/core` er ren TS uden React |

## 8. Testing

- `packages/core` ejer nu de delte tests (vitest). Ingen adfærdsændring forventes — flytning
  er mekanisk, så eksisterende grønne tests er regressions-orakel.
- Begge apps' `tsc`-typecheck er den primære gate på at imports + typer hænger sammen.
- Ingen ny test-logik kræves (ren refactor uden adfærdsændring) udover at bekræfte at de
  flyttede test-filer stadig eksekverer i deres nye placering.

## 9. Succes-kriterier

- [ ] Spike: alle 4 checkpoints grønne (ellers dokumenteret fallback til B)
- [ ] De 11 rene filer findes i ÉN kanonisk kopi under `packages/core`
- [ ] `types.ts` forsonet; begge apps `tsc`-grønne
- [ ] Ingen spejlede kopier tilbage i `web/`/`mobile/` af de flyttede filer
- [ ] Alle eksisterende tests grønne (web vitest, core vitest, mobil jest)
- [ ] Web-Vercel-deploy fungerer
- [ ] Mobil-app kører på simulator/device med delt import
- [ ] `parity.test.ts` reduceret til kun stadig-spejlet flade
