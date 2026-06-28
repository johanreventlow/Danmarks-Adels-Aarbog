# Cycle 05 — Plan 2C-1 entitetslister (read-only)

**Dato:** 2026-06-28
**Scope:** `5a8ca47..7a91bad` (2C-1-implementering, 6 commits: 5 tasks + 2 fixes).
**Reviewers:** Claude (code-analyzer Phase 1) + Codex (Phase 3, adversarial).

## Sammenfatning

| ID | Severity | Status | Commit |
|----|----------|--------|--------|
| NEW1 stale-liste efter write | MEDIUM | ✅ List-del fixet (focus-refetch); model-del DEFER | cd2167c |
| M1 ukendt-type tom liste | LOW | ✅ Implementeret | 0bcaaf3 |
| M2 person-liste rolle-guard | LOW | ✅ Implementeret (recalibreret) | cd2167c |
| M3 medie-cast | COSMETIC | ❌ dismissed | — |

**Codex impact (verified):** 1 semantic-drift (NEW1, list-del fixet), 2 UX-guard (M1, M2).
**DEFER:** redaktionModel-invalidering efter writes (editor-header/byId stale) = 2B-M2 generaliseret →
fokuseret follow-up (loadRedaktionModel forced-reload el. optimistisk byId-patch).
**Læring:** separat read-model skaber cache-invaliderings-gæld — writes opdaterer ikke læse-modellen.

**Note:** Codex reviewede 2C-1-SPEC'en; final opus-review dækkede tværgående risici (publikums-load,
read-only, auth-state, routes, godsListe). Denne cycle = kode-niveau-bugs den ikke dækkede. Read-only
scope → ingen data-tab-stier; fund er korrekthed/UX.

---

## M1 [LOW] — `[type].tsx`: ukendt type-param → tavs tom liste

**Lokation:** `mobile/src/app/redaktion/entitet/[type].tsx:15-41`

**Symptom:** `useLocalSearchParams<{type:string}>()` kan give `undefined`/ukendt værdi (typen er
aspirationel, ej runtime-håndhævet). `titel = TITLER[type ?? ''] ?? 'Entiteter'`; alle `type==='gods'`-
grene falder igennem til `return []`. Navigerer man til `/redaktion/entitet/xxx` ses en tom liste med
titel "Entiteter" uden forklaring — ikke skelnelig fra en tom datatilstand.

**Konsekvens:** Ingen crash; tavs uforklaret tom liste for ukendt type. LOW.

**Foreslået fix:** Eksplicit allowlist-guard (efter `titel` udledes, før auth-guards):
`if (!TITLER[type ?? '']) return <Msg title="Entiteter">Ukendt entitetstype.</Msg>;`

---

## M2 [LOW] — `RedPersonListe` mangler rolle-guard (inkonsistent m. [type]/menu)

**Lokation:** `mobile/src/components/redaktion/RedPersonListe.tsx` (ingen rolle-tjek)

**Symptom:** `[type].tsx` + type-menuen gater `rolle !== 'redaktion'` → "Kræver redaktør-rolle". Men
`RedPersonListe` (den udtrukne 2A-liste, nået via `/redaktion/entitet/person`) har ingen rolle-guard →
en ikke-redaktør kalder `fetchRedaktionPersoner()` (RLS beskytter data) og ser en tom liste uden
forklaring i stedet for "Kræver redaktør-rolle". Pre-eksisterende (2A havde samme), men nu
inkonsistent med 2C-1's auth-state-kontrakt.

**Konsekvens:** Ingen sikkerhedshul (RLS er sikkerhedsnet); UX-inkonsistens. LOW.

**Foreslået fix:** Tilføj `const rolle = useStore((s) => s.rolle); if (rolle !== 'redaktion') return
<...>Kræver redaktør-rolle.</...>;` øverst i `RedPersonListe`, konsistent med [type].tsx-mønsteret.

---

## M3 [COSMETIC] — `RawMedia` cast-mønster i `buildAux`

`medieListe` bruger `(m as { id?: unknown })`-casts fordi `RawMedia` har index-signatur. Funktionelt
korrekt (`?? ''`-fallbacks), men opakt. Forslag: udvid `RawMedia` med eksplicitte felter. Ikke haster.

---

## Codex adversarial-review konsekvens (2026-06-28)

**Verdict:** needs-attention

**Bekræftet (verified):**
- **NEW1 [MEDIUM] stale-cache efter person-writes** — confirmed missed bug. Editoren re-henter kun
  evidens (`fetchPersonEvidence`), ikke `redaktionModel`/`redaktionAux`; `RedPersonListe` henter kun
  ved session-skift. → efter en LIVE person-write (navn/privat) viser person-listen + editor-header
  GAMMEL data til remount/login. Generaliserer 2B-M2 (stale-privat) til hele læse-laget.
  **Fix (denne cycle, scoped):** `RedPersonListe` re-henter på FOCUS (`useFocusEffect`) → listen frisk
  ved tilbagevenden. **DEFER (bredere):** `redaktionModel`-invalidering efter writes (editor-header +
  byId stale) — kræver `loadRedaktionModel`-forced-reload el. optimistisk byId-patch (= 2B-M2, dokumenteret).
- **M1 [LOW] confirmed** — ukendt type → tavs tom liste. Fix-placering: guard EFTER begge useMemo-hooks
  (Codex: før-hooks ville gøre hook-eksekvering betinget). `if (!TITLER[type ?? '']) return <Msg>Ukendt entitetstype.</Msg>`.
- **M2 [LOW] recalibrated** — `RedPersonListe` rolle-guard. Codex korrigerede min naive "guard øverst":
  læs `rolle` UBETINGET med de andre hooks, undertryk fetch i useEffect medmindre redaktion, inkludér
  `rolle` i deps, og placér role-besked-return EFTER alle hooks (ellers hook-orden-brud).

**Dismissed:** M3 (medie-cast — skalar-felter overlever cast+fallback).
**Bekræftet sikkert af Codex:** ownerCount (begge String-id), arms index 12 + tolerant catch,
statisk person-rute registreret før dynamisk.

**Impact-buckets (verified+fixet):**
- Silent-corruption/semantic-drift: **1** (NEW1 — stale liste/header efter write; list-del fixet, model-del deferred).
- False-confidence/UX-guard: **2** (M1 ukendt-type, M2 rolle-guard).

**Læring:** en separat read-model (2B) skaber cache-invaliderings-gæld: writes opdaterer ikke
læse-modellen → stale visning. Hver write-sti der ændrer visning_*/privat bør invalidere redaktionModel.

---

## Verificeret sikkert (code-analyzer Phase 1)

- Promise.all-index for `arms` (12 entries, korrekt destrukturering).
- `godsListe.ownerCount`-nøgle `String(e.id)` matcher `ownersByEstate`-nøgler (`String(objekt_id)`).
- Søg `r.titel.toLowerCase()` null-safe (titel altid streng efter `?? ''`).
- `r.under`-null-tjek; tomme noter renderer intet.
- Route-kollision: statisk `entitet/person` vinder over dynamisk `[type]` (build-time).
- Ingen dobbelt-fetch (entiteter.tsx er nu type-menu, ikke RedPersonListe).
- Hooks kaldt ubetinget før early-returns (ingen Rules-of-Hooks-brud).
- `model`/`aux` aldrig null ved `status==='ready'` (atomisk set).
- seed.ts: alle 5 nye Aux-felter `[]`.
