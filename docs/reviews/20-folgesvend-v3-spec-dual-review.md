# Review 20 — Følgesvend v3 spec (dual-review: Claude + Codex)

**Dato:** 2026-07-05
**Genstand:** `docs/superpowers/specs/2026-07-05-folgesvend-v3-feed-drawer-bogmaerker-design.md`
**Type:** SPEC-review (ingen kode implementeret endnu). Read-only.
**Reviewers:** Claude (Phase 1) + Codex adversarial (Phase 3, `codex exec --sandbox read-only`).

Codex-trigger (Phase 2 = JA): spec'en indeholder en TS-kontrakt, cross-modul-claims
(spejler web-bogmærker, bruger `Model`/`Aux`) og empiriske påstande om modellens API.

---

## Phase 1 — Claude egne fund (4 huller)

- **A** — `slaegt`-kort: intet deterministisk mål-valg ("en markant person" udefineret).
- **B** — portrait + citat udledes begge af personer-med-bio → samme person kan blive begge.
- **C** — embede/jubilæum har intet udvælgelsesloft → kort-eksplosion muligt.
- **D** — `useBookmarks` bør afhænge af `canonicalIdById`-mappet, ikke funktionsreferencen.

## Phase 3 — Codex adversarial (verificeret empirisk i reconcile)

Alle fund uafhængigt reproduceret mod kildekode (ingen peer-review-laundering).

| ID | Verdikt | Evidens (verified) | Konsekvens |
|---|---|---|---|
| DS1 | bekræftet m. caveat | `AppPerson.title: string` (ikke-null), `bio: string` (types.ts:135) | `FeedCard.title` nullable ↔ kilde ikke-null; bio-filter = `bio.trim()!==''` |
| DS2 | bekræftet | `Union.p1/p2` (p2 nullable) (types.ts:103) | forbundet: filtrér `p2!==null`, navne fra `model.byId` |
| DS3 | bekræftet | `officesBy/godsListe/ownersByEstate/vaabenListe` findes (types.ts:205-223) | ingen ændring |
| DS4 | bekræftet | `computeRelationship(model,aId,bId): RelationResult` m. `.label` (relationship.ts:307) | slaegt: håndtér `found:false` |
| BM1 | **spec-defekt** | web-store er SYNC: `useState`-init + sync `toggle()` (bookmarks.ts:38,77) | async-port ≠ "kun init-effekt"; kræver async-repo + sync hook-state + race-sikker mutation |
| BM2 | bekræftet (= D) | web-hook dep = canon-FUNKTION (bookmarks.ts:79); mobil-`canonicalId` er STABIL (useStore.ts:188) | stabil funktion → recollapse-renormalisering MISSES; dep skal være mappet |
| BM3 | bekræftet | `@react-native-async-storage/async-storage` i package.json:11 | ingen ændring |
| A/B/C/D | bekræftet | — | jf. Phase 1 |
| NEW1 | **spec-defekt** | `Union.year` OG `p2_name` sættes `null` af loader (load.ts:255-259) | forbundet: intet vielsestekst-/p2_name-grundlag; `marBottom` neutral, navne fra `model.byId` |
| NEW2 | **spec-defekt** | `/relate` læser `relA/relB` fra store (relate.tsx:35-38) | slaegt-kort skal bære `aId/bId` + `onOpen` sætter `setRelA/setRelB` FØR `router.push` |
| NEW3 | **spec-defekt** | web-test antager øjeblikkelig storage-effekt (bookmarks.test.ts:23,69) | tilføj async/race-tests (forsinket read, map-skift under hydrering, hurtige toggles, unmount) |

## Impact-bucketing

- **Silent-corruption / semantisk drift:** BM1 (async-race → tabte/dublerede bogmærker), BM2/D
  (recollapse-renormalisering misses → alias+kanonisk sameksisterer), NEW1 (forbundet lover data
  der ikke findes → tom/forkert tekst).
- **False-confidence / process:** NEW3 (test-plan dækker ikke den nye async-fejlklasse).
- **Under-specifikation (blokerer implementering):** A, B, C, NEW2.
- **Cleanup / type-præcision:** DS1 (nullable-alignment), DS2/DS4 (null-guards).

## Reconcile → spec-rettelser (alle anvendt i spec v2)

1. **DS1** — portrait/citat-kilde = `bio.trim()!==''`; `title` normaliseres (`hasTitle = title!==''`).
2. **DS2/NEW1** — forbundet: kun unions m. `p2!==null` og begge personer i `byId`; navne fra
   `model.byId`; `marBottom` = `year? 'gift '+year : 'gift'` (year p.t. altid null → "gift").
3. **DS4/A/NEW2** — slaegt: emit KUN når `meId` og `focusId` begge sat og distinkte; `aId=meId`,
   `bId=focusId`; `computeRelationship`; skip hvis `found:false`; kort bærer `aId/bId`; `onOpen`
   sætter `setRelA(aId)/setRelB(bId)` før `router.push('/relate')`.
4. **B** — portrait og citat trækker fra DISJUNKTE partitioner af bio-populationen (stabil
   hash af id) → ingen person begge steder.
5. **C** — per-kind cap før interleave (konstant `FEED_CAPS`): portrait ≤12, citat ≤4, gods (alle),
   forbundet ≤6, embede ≤6, jubilaeum ≤6, vaaben (alle), slaegt ≤1, samle 1. Udvælgelse =
   første N efter stabil id-sort.
6. **BM1** — omskriv §6: async `BookmarkStore` (`list()/toggle()` → Promise); hook holder
   `ids: Set` i `useState` som render-sandhed (sync `has`); `toggle` opdaterer state optimistisk +
   persisterer async; hydrering i effect; race-sikring (seneste-skrivning-vinder / serialiseret write).
7. **BM2/D** — hook-dep = `canonicalIdById` (map); canon-funktion memoiseres af mappet.
8. **NEW3** — test-plan udvides m. async/race-cases.

**Verdict:** needs-attention → alle 11 fund adresseret i spec v2. Ingen backend-/model-ændring
tilføjet. Klar til implementeringsplan efter bruger-review.

**Læring:** ved port af en SYNC localStorage-kontrakt til AsyncStorage er "kun én afvigelse"
næsten altid undervurderet — sync-render-adgang (`has()`) og atomiske mutationer skjuler en
async-race-fejlklasse der kræver eksplicit hook-state-design, ikke bare `await`.
