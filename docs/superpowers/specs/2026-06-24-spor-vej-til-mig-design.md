# Vej til mig — wayfinder i Spor (Variant C)

**Dato:** 2026-06-24
**Branch:** feat/folgesvend-mobile
**Status:** Design godkendt — klar til implementeringsplan

## Problem

I mobilappens stamtræ-variant C ("Spor") tegnes en lodret rød streg
(`snapGuide`, `src/app/(tabs)/tree.tsx`). Den er ikke i design-specen
(README §5.2 nævner kun center-fokus-**rammen** `snapFrame`), er ikke
koblet til noget, og peger reelt på intet. Brugerens intuition: den skulle
vise vejen til ens eget kort (`meId`, "Det er mig i slægten").

## Mål

Gør den røde streg til en ægte **wayfinder** ("GPS") der viser vejen fra
nuværende fokus til brugerens eget kort, via turn-by-turn retningspil +
antal spring. Ingen tryk-for-hop (brugeren navigerer selv med gestik).

## Invarianter respekteret

- Ingen ændring af gestus-modellen (`moveSnapGen`/`moveSnapSib`).
- Ingen ny store-state — alt afledes af eksisterende
  `snapPath` / `snapDepth` / `meId`.
- `meId` skrives kun via eksisterende `setMe` (profil-toggle).

## Mekanik (verificeret)

- `buildSnapPath` bygger `snapPath` som **én lodret rygrad**: fra fokus'
  øverste ane (via `parentId`-kæden) ned gennem fokus, videre ned ad
  førstefødte-kæden (`childrenOf(...)[0]`). `snapDepth` = fokus' index.
  Derfor: `snapPath[0..snapDepth]` **er** fokus' anekæde.
- `moveSnapGen(±1)`: flytter kun `snapDepth` inden for den faste `snapPath`.
- `moveSnapSib(±1)` (kræver `snapDepth > 0`): skifter til en søskende =
  et andet barn af `snapPath[snapDepth-1]`, og genbygger efterkommer-halen
  som førstefødt-kæde fra den valgte. Søskende-rækkefølge = `childrenOf`-orden.
- Gestus-mapping (eksisterende handler): vandret `dx<0 → moveSnapSib(1)` (▸),
  `dx>0 → moveSnapSib(-1)` (◂); lodret `dy<0 → moveSnapGen(-1)` (▲, aner),
  `dy>0 → moveSnapGen(+1)` (▼, efterkommere).
- `meId` ligger kun på den synlige rygrad hvis mig er direkte ane eller
  direkte førstefødt-efterkommer af fokus. Ellers kræver det søskendeskift.

## Komponent 1 — ren pathfinder (selector)

Fil: `src/data/selectors.ts`. Ingen UI, fuldt testbar.

```ts
export type WayStep = 'up' | 'down' | 'left' | 'right' | 'arrived';

export function wayToMe(
  model: Model,
  snapPath: string[],
  snapDepth: number,
  meId: string,
): { step: WayStep; remaining: number } | null;
```

Returnerer:
- `{ step: 'arrived', remaining: 0 }` når fokus == mig.
- `{ step, remaining }` med næste gestus + samlet antal resterende gestus.
- `null` når mig og fokus ikke deler nogen ane (ingen vej i Spor).

### Algoritme (konstruktiv — bygger hele planen, undgår op/ned-bounce)

1. `F = snapPath[snapDepth]`. Hvis `meId === F` → `arrived`.
2. `A = snapPath.slice(0, snapDepth + 1)` (fokus' anekæde).
   `M = ancestors(meId)` inkl. mig selv (klatr `parentId` til roden, vend).
3. `commonLen` = længden af fælles præfiks(A, M). Hvis `0` → `null`.
   (`lcaDepth = commonLen - 1`.)
4. **Mig er ane til fokus** (`M` er præfiks af `A`, dvs.
   `commonLen === M.length`): mig ligger på `A` i dybde `M.length - 1`.
   Plan = `up` × `(snapDepth - (M.length - 1))`.
5. **Fokus ligger på mig's egen kæde** (`commonLen === snapDepth + 1`,
   dvs. `A` er præfiks af `M`): ren nedstigning fra dybde `snapDepth`.
6. **Ægte forgrening** (ellers): klatr `up` × `(snapDepth - commonLen)` til
   søskende-dybden `commonLen`; så **søskendeskift** fra `A[commonLen]` til
   `M[commonLen]` (samme forælder `M[commonLen-1]`), retning + antal =
   `childrenOf(M[commonLen-1])`-indeks-delta (`left` hvis target-indeks <
   nuværende, ellers `right`); så nedstigning fra dybde `commonLen`.
7. **Nedstigning** fra node `M[d]` i dybde `d` ned til mig: for hvert
   niveau `d → me_depth-1`: `down` (lander på førstefødt =
   `childrenOf(M[d])[0]`), derefter `right` × `idx` hvis `M[d+1]` har
   `childrenOf(M[d])`-indeks `idx > 0` (førstefødt = indeks 0).

Returnér `plan[0]` som `step` og `plan.length` som `remaining`.
Hele planen bygges før retur — derfor ingen lokal-minimum-loop ved
gren-kryds. Recomputeres på hver render (træet er lille, ~925 personer;
kæder er korte).

### Edge cases i selectoren

- `snapDepth === 0` og forgrening → `commonLen` kan ikke overstige 1; hvis
  `A[0] !== M[0]` → `null` (roden er den eneste mulige fælles ane).
- Mig ikke på førstefødt-hale: håndteret af søskendeskift i nedstigning.
- Defensiv: manglende person i `model.byId` → behandl kæden som afsluttet.

## Komponent 2 — UI på den røde streg

Fil: `src/app/(tabs)/tree.tsx`, `VariantC`. Læs `meId` fra store; beregn
`way = useMemo(() => meId ? wayToMe(model, snapPath, snapDepth, meId) : undefined, ...)`.

| Tilstand | `snapGuide` | Badge (overlay) |
|---|---|---|
| Mig ikke valgt (`meId == null`) | dæmpet `rgba(136,26,51,0.16)` (som nu) | lille mono-hint "Vælg dig selv i en profil" |
| `arrived` | fuldt oplyst `rgba(136,26,51,0.40)` | ★ "Du er her" |
| `step` | oplyst `rgba(136,26,51,0.40)` | pil (▲▼◂▸ ud fra `step`) + "N spring til dig" |
| `null` (ingen fælles ane) | **skjult** (render ikke) | — |

- Badge renderes i overlay-laget (efter kort-stakken, `pointerEvents="none"`),
  centreret vandret på linjen, placeret lige over center-fokus-rammen
  (`snapFrame`), så den ikke dækker fokus-kortet.
- Pil-tegn mapping: `up`→▲, `down`→▼, `left`→◂, `right`→▸.
- Farver/typografi følger eksisterende tokens (bordeaux `#881A33`,
  JetBrains Mono til labels). Præcise pixels fastlægges i implementering.

## Komponent 3 — test

Fil: `src/data/__tests__/selectors.test.ts`. Golden-tests for `wayToMe`:

1. Mig == fokus → `arrived`, 0.
2. Mig er direkte ane → `up`, korrekt antal.
3. Mig er førstefødt-efterkommer på linjen → `down`, korrekt antal.
4. Mig er fætter (forgrening m. søskendeskift) → første gestus = `up`
   (eller `left`/`right` hvis allerede på søskende-dybden), korrekt samlet
   antal.
5. Mig uden fælles ane → `null`.
6. Mig er efterkommer men ikke på førstefødt-hale → nedstigning med
   søskende-trin i `remaining`.

Brug eksisterende seed/fixture-mønster i test-filen.

## Bevidst udeladt (YAGNI)

- Tryk-for-hop til mig (brugervalg: ren turn-by-turn).
- Ændring af gestus-tærskler eller -model.
- Ny store-state eller persistering.
- Wayfinder i Variant A/B (kun Spor har den lodrette streg).
