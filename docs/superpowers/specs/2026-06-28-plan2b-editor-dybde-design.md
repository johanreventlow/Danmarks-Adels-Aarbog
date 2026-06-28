# Plan 2B — Editor-dybde: separat redaktion-model + køn + familie/sektion-visning (design/spec)

**Dato:** 2026-06-28
**Status:** Godkendt design (revideret efter Codex-review) — klar til implementeringsplan
**Branch:** arbejd på `main` (feature-branch ved implementering)
**Kontekst:** Plan 2A gjorde levende personer søgbare. Men person-editoren henter
navn/familie/sektioner fra den DELTE anon-model (893, uden levende) → `model.byId[id]` er
undefined for de 70 levende → "Personen blev ikke fundet". 2B gør editoren selv-forsynende
via en **separat redaktion-model**, tilføjer **køn-editor** (redigerbar), og viser **familie +
sektioner read-only**.

Forudgående: plan 1 (kerne-editor), plan 2A.

---

## 0. Arkitektur-valg (revideret efter Codex adversarial-review 2026-06-28)

**Oprindeligt design:** per-person `fetchRedaktionPerson(id)` der re-deriverer familie/sektioner.
**Codex fandt:** den simplificerede re-derivation ville DIVERGERE fra `buildModel` (chrono-filter
af umulige forælder-barn-kanter + første-fødselsfamilie-regel) og `buildAux` (hverv =
organisation OG `historical_event`; `stripParen(periode_raw)`; års-sort). Re-implementering =
to kilder + fejlrisiko.

**Revideret valg: SEPARAT REDAKTION-MODEL.** Load én ekstra fuld model via redaktion-sessionen
(963 inkl. levende, getAll-pagineret af eksisterende `load.ts`), gemt **adskilt** fra
publikums-modellen. Editoren bruger de eksisterende selektorer (`parentsOf`/`spousesOf`/
`childrenByMarriage`) + `aux` (`officesBy`/`estatesBy`/`sourcesBy`) **UÆNDRET** → ingen
divergens, pagination gratis, al derivation genbrugt. (Codex #2/#3/#4 opløses; #1 narrativ er
en separat fix, se §4.)

---

## 1. Besluttede valg

| Beslutning | Valg | Note |
|---|---|---|
| Editor-datakilde | **Separat redaktion-model** (`buildModel`/`buildAux` over redaktion-fetch) | Genbruger al familie/sektion-derivation; virker for levende. |
| Redigerbart i 2B | **Kun køn** | Familie/relationer + sektioner = read-only (relations-redigering = 2C). |
| Privat-isolering | **Adskilt store-slice** (`redaktionModel`/`redaktionAux`) | Publikums-faner bruger uændret den offentlige model (ingen GDPR-læk). |
| Narrativ-redigering | **Eksplicit narrativ-fetch + bevar privat** | Fixer Codex #1 (privat-tab). |

---

## 2. Separat redaktion-model

### 2.1 Load
- `loadFromSupabase` får en valgfri param `{ includePrivat?: boolean }`. Default `false`
  (publikums-adfærd uændret: `.filter(p => !p.privat)`). Redaktion-kaldet sætter `true` →
  inkluderer privat-markerede (RLS returnerer dem kun for redaktion alligevel; filteret må ikke
  fjerne dem). Pagination (getAll) er allerede på plads → ingen 1000-cap (Codex #3).
- Store-slice (`store/useStore.ts`): `redaktionModel: Model | null`, `redaktionAux: Aux | null`,
  `redaktionStatus: 'idle'|'loading'|'ready'|'error'`, action `loadRedaktionModel()`.
  `loadRedaktionModel` kalder `loadFromSupabase({ includePrivat: true })` → `buildModel(res.db)`
  → sætter `redaktionModel`/`redaktionAux`/`redaktionStatus='ready'`. Kaster-fanges → status='error'
  (ikke seed-fallback — redaktion skal vide hvis det fejler; ALDRIG tom-som-clean).

### 2.2 Trigger
- `redaktion/_layout.tsx` (eller `(red-tabs)/_layout`): `useEffect` → hvis `rolle==='redaktion'`
  && `redaktionStatus==='idle'` → `loadRedaktionModel()`. Lazy, én gang pr. login-session.
- Publikums-modellen (`model`/`aux`) røres ikke. To modeller side om side: offentlig (893) til
  publikums-faner, redaktion (963) til redaktions-ruter.

### 2.3 privat på model-personer (til toggle-init)
- `load.ts`'s `appPersons`-map beholder `privat` (`privat: Boolean(p.privat)` — additivt felt på
  `AppPerson`). Begge modeller får feltet (offentlig = altid false; redaktion = faktisk). Bruges
  til at initialisere Privat-toggle korrekt (retter også 2A-review-driften hvor toggle var
  hardkodet false).

## 3. Editor-ændringer (`mobile/src/app/redaktion/person/[id].tsx`)

Editoren skifter fra publikums-`model` til `redaktionModel`/`redaktionAux`:
- **Header (navn/år):** `redaktionModel.byId[id]` (`.name`/`.years`). Virker for levende.
  Hvis `redaktionStatus==='loading'` → spinner/"henter"; `'error'` → fejl-tilstand;
  `byId[id]` mangler → "Personen blev ikke fundet".
- **Køn (NYT, redigerbart):** "KØN"-afsnit under kerne-fakta med segment **mand/kvinde/ukendt**
  (vocab fra `person_koen_chk`, BEKRÆFTET korrekt af Codex). Nuværende køn fra `fetchPersonEvidence`
  (`ev.koen`, eksisterende). Valg → `setPending({ art:'fakta', felt:'koen', vaerdi })` (eksisterende
  buildRpcCall-case → `red_set_koen`) → SkrivePreviewSheet → efter LIVE: re-fetch `fetchPersonEvidence`.
- **Privat-toggle:** init fra `redaktionModel.byId[id].privat` (ikke længere hardkodet false).
- **Familie & relationer (read-only):** `parentsOf(redaktionModel, id)` / `spousesOf(...)` /
  `childrenByMarriage(...)` — EKSISTERENDE selektorer, samme derivation som publikum (ingen
  divergens). Grupper Forældre/Ægtefæller/Børn; rad = `InitialBadge` + navn; tap → naviger til
  den person i redaktions-editoren. Tom gruppe skjules.
- **Sektioner (read-only):** `redaktionAux.officesBy[id]` (hverv), `estatesBy[id]` (godser),
  `sourcesBy[id]` (kilder) — EKSISTERENDE aux (inkl. `historical_event`-hverv + korrekt format/sort).
  Rader med titel + periode/værk. Tom sektion skjules.
- **Editoren bruger ikke længere den offentlige `model`.** (Dashboard-konflikt-navne bruger stadig
  offentlig model — uændret, uden for scope.)

## 4. Narrativ-redigering — fix Codex #1 (privat-tab)

Problem: `red_upsert_narrativ` redigerer FØRSTE narrativ (ORDER BY id) uanset privat, p_privat
default false. Prefill fra "første ikke-private" ≠ skrive-mål → en privat bio kan overskrives +
gøres offentlig.

Fix:
- Ny `fetchPersonNarrativ(id): Promise<{ tekst: string; privat: boolean } | null>` — henter
  FØRSTE narrativ by id (uanset privat) = præcis den række `red_upsert_narrativ` vil redigere.
  Prefill-kilde == skrive-mål.
- Editor prefiller `narrativTekst` fra dette (ikke fra `model.bio`), og **bevarer privat-flaget**
  på Gem: `setPending({ art:'narrativ', ..., payload:{ privat: <det hentede flag> } })`.
- Intet narrativ (`null`) → tomt felt; Gem opretter nyt (privat=false). Multi-narrativ-valg
  (hvilket af flere) = senere; 2B redigerer kun det første.

## 5. Fejlhåndtering
- `loadRedaktionModel`/`fetchPersonNarrativ` kaster ved error → editor/redaktion-rute viser
  eksplicit fejl-tilstand. ALDRIG tom-som-clean (cycle 03 NEW1).

## 6. Test
- **jest:** `loadFromSupabase({includePrivat:true})` beholder privat-personer (mock-rows; bekræft
  filter ikke fjerner dem) + default uændret. `mapRedPerson`-stil: privat på AppPerson-map.
  Køn-write-case allerede dækket (buildRpcCall `fakta`+`koen` → `red_set_koen`). Familie/sektion-
  visning bruger EKSISTERENDE selektorer (allerede testet) — ingen ny derivation at teste.
  Narrativ-fetch-mapping (først-by-id, privat bevaret) — lille ren mapping.
- **Manuel:** reload → redaktion → redaktion-model loader → åbn en LEVENDE person (Entiteter-liste)
  → editoren ÅBNER (header) → familie/sektioner vist (matcher publikum) → skift køn (LIVE) →
  header-køn opdateres → narrativ: privat bio bevares ved Gem.

## 7. Berørte artefakter
**Ændrede:**
- `mobile/src/data/load.ts` (param `includePrivat`; behold `privat` på appPersons).
- `mobile/src/data/types.ts` (`AppPerson.privat?: boolean`).
- `mobile/src/store/useStore.ts` (redaktionModel/redaktionAux/redaktionStatus + `loadRedaktionModel`).
- `mobile/src/app/redaktion/_layout.tsx` (trigger `loadRedaktionModel` ved rolle=redaktion).
- `mobile/src/data/redaktionRead.ts` (`fetchPersonNarrativ`).
- `mobile/src/app/redaktion/person/[id].tsx` (header/familie/sektion fra redaktionModel; køn-editor;
  privat-toggle-init; narrativ-prefill fra fetchPersonNarrativ + bevar privat).
- Tests: `load`-test (includePrivat) + `redaktionRead`-test (narrativ-fetch-mapping).

## 8. Scope / non-goals
**I scope:** separat redaktion-model (virker for levende, genbruger derivation); køn-editor
(redigerbar); familie + sektioner read-only via eksisterende selektorer/aux; narrativ-privat-fix;
fejl-tilstande.

**Non-goals (→ 2C / senere):**
- Redigér familie/relationer/sektioner (rolle-vælgere, relation-RPC'er, gods/hverv-entiteter).
- Medier-visning/upload; multi-narrativ-valg.
- Generisk record-editor + andre entiteter + opret-flow.
- Fjerne offentlig-model-afhængighed uden for editoren (dashboard-konflikt-navne uændret).
- Forene 2A's `fetchRedaktionPersoner` med redaktion-modellen (kunne gøres senere; 2A's liste
  virker uændret).
