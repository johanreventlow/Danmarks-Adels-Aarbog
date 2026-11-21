# Børn pr. ægteskab i bogens rækkefølge — implementeringsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Personsiden grupperer børn pr. ægteskab (som stamtræet), og børn står på personside og stamtræ i Aarbogens rækkefølge (søskende-rækken er uden for scope).

**Architecture:** En ren core-funktion bygger et indeks over stamtavlenumre (`bogNrBy`) fra `person_external_id` og sorterer en børneflok efter dem. Web-modellen får indekset; `byggFokusRaekker` sorterer børnene med det, og `PersonSide` genbruger `byggFokusRaekker(...).boerneGrupper` i stedet for den flade `childrenOf`-liste.

**Tech Stack:** TypeScript, React, vitest; npm workspaces (`@daa/core`, `web`).

**Spec:** `docs/superpowers/specs/2026-11-21-boern-pr-aegteskab-design.md`

## Global Constraints

- Ingen DB-, skema- eller loader-ændringer. Mobil røres ikke.
- `family_member.ordinal` bruges ikke til børn (det er partneres ægteskabsnummer).
- Overskriftstekster genbruges fra stamtræet: `Med <navn>`, `Ægteskab ikke angivet`, `BOERN_UDEN_AEGTESKAB`.
- Med ét ægteskab: ingen underoverskrift; flad liste som i dag, blot sorteret.

## Review Focus

1. Fokus er en indgiftet ægtefælle uden eget nummer (Sophie Amalie Hahns side): børnene skal stadig sorteres efter deres numre → test i Task 1 (`forælder uden nummer`).
2. Barn foldet af to udgaver (1939 + 2018-20) med forskellige numre: den nyeste udgave afgør → test i Task 1 (`nyeste udgave vinder`).
3. Forælder har en linje i udgaven, men børnene er nummereret i en anden (fx forælderen er hoved for en ny linje): børnene sorteres stadig efter deres fælles linjes numre, ikke efter fødselsår → test i Task 1 (`ingen fælles linje med forælderen`).
4. Udgave med ukendt år (`aar: null`) må ikke vinde over en dateret → dækket af sorteringsreglen (null sidst) i Task 1's `nyeste udgave vinder` (tilføj én udgave med `aar: null`).
5. Personside med to ægteskaber, hvor et barn mangler ægteskab: restgruppe med note, intet barn forsvinder → test i Task 3.

---

### Task 1: Core — stamtavlenummer-indeks og sortering

**Files:**
- Create: `packages/core/src/bogensOrden.ts`
- Modify: `packages/core/src/types.ts` (Model: `bogNrBy?: Record<string, BogNr[]>`), `packages/core/src/index.ts` (eksport)
- Test: `packages/core/src/__tests__/bogensOrden.test.ts` (følg mappens eksisterende placering af core-tests)

**Interfaces:**
- Produces:
  - `export type BogNr = { sourceId: string; linje: string; nr: number; nrLabel: string | null }`
  - `export function byggBogNr(extIds: RawExtId[], canonicalIdById: Record<string, string>): Record<string, BogNr[]>` — nøgle = kanonisk person-id; rækker med `linje == null` eller `nr == null` springes over.
  - `export function sorterBoernEfterBogen<T extends { id: string; born: number | null; name: string }>(boern: readonly T[], foraelderId: string, bogNrBy: Record<string, BogNr[]> | undefined, udgaver: readonly { sourceId: string; aar: number | null }[] | undefined): T[]`

**Algoritme (sorterBoernEfterBogen):**
1. Kandidat-udgaver: alle `sourceId` som forælderen eller et barn har `BogNr` i; ordnet efter `aar` faldende (ukendt år sidst), forælderens egne udgaver før de øvrige ved samme år.
2. Vælg den første kandidat-udgave U, hvor mindst ét barn har et `BogNr`.
3. Barnets nøgle = barnets `BogNr` i U (højst ét pr. person og udgave). Gyldige linjer = forælderens linjer i U, hvis mindst ét barn er nummereret i en af dem; ellers den linje i U, flest af børnene er nummereret i (lige: alfabetisk første). Kun børn i en gyldig linje har nøgle.
4. Børn med nøgle først, sorteret på `linje`, så `nr`, så label (`nrLabel ?? String(nr)`, som `compareLineHead`). Derefter børn uden nøgle efter `born` (null sidst), så `name` (`localeCompare('da')`).
5. Uden `bogNrBy` eller uden nogen nøgle: kun trin 4's fallback.

- [ ] **Step 1: Skriv de fejlende tests**

```ts
// byggBogNr
it('folder alias til kanonisk og springer rækker uden linje/nr over', () => {
  const r = byggBogNr([
    { person_id: 1, source_id: 10, linje: 'V', nr: 14, nr_label: '14' },
    { person_id: 2, source_id: 9, linje: 'V', nr: 12, nr_label: null },
    { person_id: 3, source_id: 10, linje: null, nr: 3 },
  ], { '2': '1' });
  expect(r['1']).toEqual([
    { sourceId: '10', linje: 'V', nr: 14, nrLabel: '14' },
    { sourceId: '9', linje: 'V', nr: 12, nrLabel: null },
  ]);
  expect(r['3']).toBeUndefined();
});

// sorterBoernEfterBogen — B(id,born,name)-hjælper; udgaver U2018={sourceId:'20',aar:2018}, U1939={sourceId:'10',aar:1939}
it('sorterer efter nummer i forælderens linje, ikke efter indgangsrækkefølge', ...)
  // forælder F: V/1 i '20'; børn c(nr 4), a(nr 2), b(nr 3) givet i rækkefølgen c,a,b → a,b,c
it('15a før 15b', ...)            // samme nr 15, nrLabel '15b' og '15a' → 15a først
it('børn uden nummer sidst efter fødselsår, så navn', ...)
  // x(nr 2), y(ingen, born 1700), z(ingen, born null), w(ingen, born 1690) → x,w,y,z
it('nyeste udgave vinder', ...)
  // barn p: '10' nr 9, '20' nr 2; barn q: '10' nr 1, '20' nr 3; udgave '30' aar:null, p nr 1 → p,q
it('forælder uden nummer (indgiftet ægtefælle)', ...)
  // F uden BogNr; børn i '20' linje V nr 7 og nr 5 → nr 5 først
it('ingen fælles linje med forælderen', ...)
  // F: '20' III/12; børn k: '20' V/3, l: '20' V/2, born omvendt → l,k (V er børnenes fælles linje)
it('uden bogNrBy: fødselsår-fallback', ...)
```

- [ ] **Step 2: Kør og se dem fejle**

Run: `npm run test -w @daa/core -- bogensOrden`
Expected: FAIL (modul findes ikke)

- [ ] **Step 3: Implementér `bogensOrden.ts`, `Model.bogNrBy` og eksport fra `index.ts`**

- [ ] **Step 4: Kør core-suiten**

Run: `npm run test -w @daa/core && npm run typecheck -w @daa/core`
Expected: PASS, ingen typefejl

- [ ] **Step 5: Commit** — `feat(core): sortér børn efter Aarbogens stamtavlenummer`

---

### Task 2: Web-modellen og stamtræets børn bruger bogens rækkefølge

**Files:**
- Modify: `web/src/data/model.ts` (sæt `bogNrBy: byggBogNr(extIds, collapsed.canonicalIdById)` i `model`-objektet ved siden af `genCoordsByPerson`)
- Modify: `web/src/data/fokusTrae.ts` (børn sorteres)
- Test: `web/src/data/__tests__/fokusTrae.test.ts`

**Interfaces:**
- Consumes: `byggBogNr`, `sorterBoernEfterBogen`, `Model.bogNrBy`, `Model.udgaver` (Task 1)
- Produces: `byggFokusRaekker` returnerer `boerneGrupper[*].boern` i bogens rækkefølge (typer uændrede).

- [ ] **Step 1: Fejlende tests i `fokusTrae.test.ts`**

```ts
it('børn i bogens rækkefølge inden for hvert ægteskab', ...)
  // A gift med E1 (u1) og E2 (u2); parentChild-rækkefølge K3,K1 (u1), K4,K2 (u2);
  // bogNrBy: A '20' V/1; K1 V/2, K3 V/3, K2 V/4, K4 V/5; udgaver [{sourceId:'20',aar:2018}]
  // → grupper [['K1','K3'], ['K2','K4']] (navne)
it('ét ægteskab: én gruppe i bogens rækkefølge', ...)
```

- [ ] **Step 2: Kør — FAIL**

Run: `npm run test -w web -- fokusTrae`

- [ ] **Step 3: I `byggFokusRaekker`: `boernP = sorterBoernEfterBogen(childrenOf(model, focusId), focusId, model.bogNrBy, model.udgaver)`.** Grupperne arver rækkefølgen fra `boernP` (de filtrerer `boernP`).

- [ ] **Step 4: Kør web-suiten**

Run: `npm run test -w web && npm run build -w web`
Expected: PASS

- [ ] **Step 5: Commit** — `feat(web): stamtræet viser børn i Aarbogens rækkefølge`

---

### Task 3: Personsiden grupperer børn pr. ægteskab

**Files:**
- Modify: `web/src/components/PersonSide.tsx:214-226` (»Børn«-rækken)
- Test: `web/src/components/__tests__/PersonSide.test.tsx`

**Interfaces:**
- Consumes: `byggFokusRaekker(model, focusId)` → `{ aegteskaber, boerneGrupper, boerneNote }` (Task 2), `BOERN_UDEN_AEGTESKAB`.

**Adfærd:** Beregn `const fam = useMemo(() => byggFokusRaekker(model, focusId), [model, focusId])` før det tidlige `return`. Visningsbetingelsen for rækken er uændret (`v.spouses.length > 0 || v.children.length > 0`). Inde i `<dd>`: én `<ul>` pr. gruppe; når `fam.aegteskaber.length > 1` får hver gruppe en underoverskrift (`Med <navn>` / `Ægteskab ikke angivet`, serif kursiv som i `FokusTrae.tsx:176-178`), og restgruppen får `boerneNote` som `Mangel`-tekst. `konfOrd(c.id, focusId)` og `v.boerneKilder` under listerne bevares.

- [ ] **Step 1: Fejlende tests**

```ts
it('to ægteskaber: børn under »Med <hustru>« i bogens rækkefølge', ...)
  // forvent getByText('Med Anna Margrethe Gabel') og 'Med Sophie Amalie Hahn';
  // within(gruppe 1) navne i nr-orden; within(gruppe 2) ditto
it('barn uden ægteskab: »Ægteskab ikke angivet« + note, intet barn forsvinder', ...)
  // forvent getByText(BOERN_UDEN_AEGTESKAB) og alle børnenavne på siden
it('overskrifternes navne matcher »Gift med«', ...)
  // to ægteskaber, ægtefæller med id i byId: hvert »Med X« har et X blandt »Gift med«-navnene
it('ét ægteskab: ingen »Med …«-overskrift', ...)
  // queryByText(/^Med /) === null
```

- [ ] **Step 2: Kør — FAIL**

Run: `npm run test -w web -- PersonSide`

- [ ] **Step 3: Implementér renderingen**

- [ ] **Step 4: Kør hele web-jobbet som CI**

Run: `npm run test -w web; echo exit:$?` og `npm run build -w web` (CI-jobbet kopierer en dummy `web/.env.local`)
Expected: exit 0, ingen typefejl, build OK

- [ ] **Step 5: Commit** — `feat(web): personsiden viser børn pr. ægteskab`

---

### Efter Task 3

- Push + draft-PR kun efter projektejerens ja. Afprøv Conrad Reventlow på Vercel-preview (to grupper, rigtig rækkefølge) før merge.
