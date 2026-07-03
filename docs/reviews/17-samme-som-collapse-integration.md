# Review 17 — samme_som-collapse integration (FASE B mobile + FASE C web)

**Dato:** 2026-07-02
**Metode:** code-analyzer (Claude) pr. platform + empirisk prod-validering
**Kerne-review:** `16-samme-som-collapse-kerne.md` (FASE A, Claude+Codex).

Integrations-lagene der wirer den (dual-review-hærdede) kerne ind i web + mobile: fetch af godkendte
`samme_som`, collapse før `buildModel`, alias-resolution i state, Aux-projektion, proveniens-badge.

## FASE B (mobile) — fund

- **M1 [MEDIUM] — `meId` ikke kanoniseret ved isMe** (`person/[id].tsx`) — ✅ RETTET. Rå
  `meId===person.id` brød "★ Dig"-badgen for foldede personer (gemt alias-meId matchede ikke
  kanonisk). Storens engangs-resolution er race-afhængig (hydrateMe vs load). Fix: read-site
  `canonicalId(meId)===person.id`.
- **M2 [LOW] — `linjeCounts` pr. ext-række** — ✅ RETTET. Nu distinkte kanoniske personer pr. linje.
- **D [LOW] — `extMap` last-row-wins for proveniens** — DEFER (cosmetic; medlem er normalt én DAA-post).
- ✅ Verificeret sikkert: approved-conclusion-match (delt PK-rum, ingen kollision), start-ids på
  collapsed db, buildAux-kanonisering konsistent, redaktion `collapse:false` isoleret.

## FASE C (web) — fund

- **C1 [MEDIUM/latent] — `fetchEstateOwners` viste `#<id>` for foldet ejer** (`public.ts:48`) —
  ✅ RETTET. Rå `subjekt_id` slået op i collapsed `model.byId` → foldet alias mangler → `#id`.
  Trigger IKKE på nuværende data (ejere ligger under kanonisk id), men reel latent regression i
  featurens egen klasse. Fix: `canonicalIdById` threadet til fetchEstateOwners + kanonisér opslag.
  (Mobile er dækket: buildAux kanoniserer `ownersByEstate.personId`.)
- **C2 [LOW] — bio-union rækkefølge + stub-støj** — ✅ RETTET (delvist). Alias-posten (fx 255)
  bærer en kryds-reference-stub ("se V. Den grevelige linje…"), kanonisk (392) den fulde bio.
  Union ordner nu **kanonisk først** (fuld bio leder) + dedup af eksakte dubletter. Stubben bevares
  trailing (spec §8 union — ingen info tabt).
- **C3 [LOW] — offices/estates duplikeret ved union** — ✅ RETTET. Dedup på label|period / id.
- ✅ Verificeret: **meId-fixet korrekt spejlet** (meCanon ved alle read-sites), buildBrowse
  `.includes` korrekt for multi-linje, badge-guards mod undefined, narrativ `privat=false` i query
  (intet læk), canonicalId altid i `ids` (self-narrativ aldrig tabt).

## Empirisk prod-validering (read-only mod `xjnvdhajfyr…`)

De 2 eksisterende `samme_som` (relation 972: Conrad 255→392; relation 973: Detlef 178→298) er
begge `afklaret`. Begge grupper: begge medlemmer `mand`, alias har forælder-link + intet dato,
kanonisk har datoer + intet forælder-link → **matcher Conrad-fixturen præcis**; folder rent
(ingen karantæne), founder arver forælder-link. Ejer/office-relationer ligger under kanonisk id
(C1 trigger ikke i dag). Begge medlemmer har 1 narrativ hver (C2 relevant).
