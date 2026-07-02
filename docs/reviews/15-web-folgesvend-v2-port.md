# Review 15 — web-følgesvend v2-port (dual-review)

**Branch:** `worktree-web-folgesvend-v2-port` (10 commits, `origin/main..HEAD`)
**Område:** `web/src/Folgesvend.tsx` + data-lag (`browse.ts`, `lineage.ts`, `sources.ts`, `model.ts`, `types.ts`, `lib/collation.ts`)
**Kontekst:** Port af `design/project/Reventlow-web-v2.dc.html` ind i web-appen; data-lag porteret fra `mobile/src/data/`. 59 tests grønne, tsc/build grønne.
**Claude-review:** code-analyzer (2026-07-02). **Codex adversarial:** afventer.

---

## H1 [MEDIUM] — `activeLetter` nulstilles aldrig → blank, låst liste (dead-end)

**Lokation:** `web/src/Folgesvend.tsx` (pickLinje/clearLinje) + `web/src/data/browse.ts:42-45`

**Symptom:** Vælg et bogstav-chip (fx "S") mens hele slægten vises → vælg derefter en Linje hvor intet efternavn starter med S. `activeLetter='S'` bevares, men den scopede pools `letters` indeholder ikke "S".

**Verifikation:**
```ts
// browse.ts
const groups = letters
  .filter((l) => !activeLetter || l === activeLetter)   // 'S' ikke i letters → []
  .map((l) => ({ letter: l, people: byL[l] }));
// Folgesvend.tsx render: grouped=true, groups=[] → intet renderes.
// "Ingen træffere" er gated på flat.length===0, men flat.length>0 → INGEN besked.
```
Værre: hvis den scopede pool kun har ét initial, skjules hele chip-rækken (`browse.letters.length > 1`), så der er hverken aktiv chip ELLER "Alle"-knap → ægte dead-end (escape kun via linje-skift/søgning).

**Konsekvens:** Tom liste uden forklaring og uden synlig vej ud. Rammer §9.1×§9.2-krydset direkte.

**Foreslået fix:** (a) nulstil `activeLetter` i `pickLinje`/`clearLinje`, OG (b) defensivt i `buildBrowse`: behandl `activeLetter` som "Alle" hvis det ikke findes i `letters` (robust mod alle pool-skift-stier; unit-testbart).

---

## H2 [MEDIUM] — Gren-filter scoper søgning stiltiende; label skjuler det

**Lokation:** `web/src/data/browse.ts:24-28` + `web/src/Folgesvend.tsx` (browse-label)

**Symptom:** Når `activeLinje` er sat, filtreres OGSÅ søgeresultater til grenen (bevidst, matcher designets `linjeByPerson`-filter). Men labelen skifter til `"${n} træffere"` så snart `query` er sat → enhver visuel indikation af gren-scope forsvinder under søgning. En person der findes globalt men i en anden gren giver "Ingen træffere".

**Verifikation:**
```ts
// label:
{activeLinje && !query ? `Linje ${activeLinje} · ${n}` : `${n} ${query ? 'træffere' : 'personer'}`}
//            ^^^^^^^^ scope-indikator tabes når query er sat
```

**Konsekvens:** Forvirrende "manglende" personer; brugeren aner ikke søgningen er begrænset til linjen.

**Foreslået fix:** Bevar linje-indikationen i labelen også under søgning (`Linje X · N træffere`). Bevar bevidst gren-scoping af søgning (design-tro).

---

## M3 [LOW] — Stale-flash ved gods-skift (pre-eksisterende)

**Lokation:** `web/src/Folgesvend.tsx` (estateOwners-effekt)

**Symptom:** `estateOwners` nulstilles ikke ved `estateId`-skift (modsat `estateInfo`), så gods A→B viser A's ejere indtil B's fetch resolver; klassisk sen-resolver-race. **Pre-eksisterende** (ikke introduceret i denne port). Kosmetisk.

**Foreslået fix (valgfri):** `setEstateOwners([])` først i effekten, evt. abort-guard.

---

## M4 [LOW] — Fjernet `.slice(0,400)`-cap (kendt, bevidst)

**Lokation:** `web/src/Folgesvend.tsx` (personRow-render)

**Symptom:** Grupperet visning uden søgning renderer alle 852+ personer som inline-styled divs, ingen virtualisering/memo. Jank-risiko på svage enheder ved tom søgning. Korrekthed OK; søgning reducerer pool.

**Foreslået fix (valgfri):** Virtualisering eller blød cap på flad visning. Bevidst udeladt (alfabet-hop forudsætter browse-alle).

---

## Verificeret rent (code-analyzer)

- React-closures: handlers gendannes hver render → ingen stale-closure-fælder.
- Fokus-historik: `navigateTo` guard'er `focusId !== id`; `goBack` slice konsistent; `startFokus` rører ikke historik.
- `buildLineage`/`buildSources` vs `mobile/src/data/buildAux.ts`: identisk logik (headId=laveste nr, `nr==null→9999`, navn-fallback, dedup).
- `loadModel`: `Promise.all`-destrukturering matcher rækkefølge; `.catch(()=>[])` kun på extIds/lineage/sources (graceful); person/members-fejl propagerer til `setErr`.
- mig-koncept: stale `meId` håndteret via `model?.byId[meId]`-guards overalt; localStorage SSR-guarded.
- Estates eager-fetch: præcis én fetch (`if(!estates)`).
- Keys: stabile unikke keys overalt.

---

## H5 [LATENT — dokumenteret, ikke fikset] — lineage nøgles kun på `kode`, ikke `(source_id, kode)`

**Lokation:** `web/src/data/lineage.ts` (+ delt med `mobile/src/data/buildAux.ts`)

**Symptom (Codex-fund):** Schemaet identificerer linjer med `(source_id, kode)`, men `buildLineage`/`buildSources` ignorerer `source_id`. Med data fra flere DAA-udgaver kunne rækker overskrive samme persons linje, tælles dobbelt, og konkurrere om `headId` på tværs af udgaver; linjenavne overskrives efter `kode` alene.

**Empirisk verifikation (2026-07-02, read-only mod prod):**
```sql
distinct_sources_in_extid = 1     -- kun én kilde i person_external_id
distinct (source_id,kode) = 5     -- = distinct kode = 5 (ingen kollision)
persons_with_multiple_linje_rows = 0
```
→ Buggen **manifesterer ikke** med nuværende single-source-data; `buildLineage` giver korrekt output i dag.

**Beslutning:** DEFER + dokumentér. (1) Latent under nuværende data. (2) `mobile` har identisk logik — at ændre kun `web` ville skabe web/mobil-divergens. Fixes i **begge** apps samtidig når multi-kilde-data introduceres (nøgl projektionen på `source_id+kode`, eller vælg eksplicit udgave før projektion).

---

## Codex adversarial-review konsekvens (2026-07-02)

**Verdict:** needs-attention (NO-SHIP) → adresseret. Codex bekræftede H1, recalibrerede H2↓/M3↑, dismissede M4, og fandt to ting Claude-review missede (H5 lineage-kontrakt + tolerant-catch).

**Bekræftet + fikset (verified empirisk):**
- **H1** — repro-logik verificeret i kode; defensiv `effectiveLetter`-fix bekræftet korrekt+tilstrækkelig af Codex. Fix + 3 regressionstests. Commit `e06f1b5`.
- **M3** — request-race verificeret (permanent overskrivning, ikke flash). Cancelled-guard på begge gods-effekter. Commit `e06f1b5`.
- **Codex-MED (tolerant catch)** — verificeret i kode. `console.warn` ved degradering (graceful bevaret, synlig). Recalibreret vs. Codex' forslag om fuld propagering: PoC + mobil-paritet → logging frem for hård fejl. Commit `e06f1b5`.

**Bekræftet + fikset (recalibreret ned):**
- **H2** — Codex: ikke dead-end (escapes via "Hele slægten"-chip) → low. Label-fix bevaret alligevel (billig UX). Commit `e06f1b5`.

**Latent — dokumenteret, ikke fikset (empirisk verificeret latent):**
- **H5 (Codex-HIGH lineage source_id)** — 1 kilde, 0 multi-linje-personer → manifesterer ikke; delt m. mobil. Se H5 ovenfor.

**Dismissed:**
- **M4 (perf-cap)** — ingen empirisk benchmark; ikke ship-blocking. Bevidst udeladt (alfabet-hop forudsætter browse-alle).

**Impact-buckets (fikset):**
- Silent-corruption/semantic: 2 (M3 permanent gods-overskrivning, H1 blank dead-end)
- False-confidence/process: 1 (tolerant-catch skjulte RLS-fejl)
- Cleanup/UX: 1 (H2 label)

**Læring:** Ren-funktion-udtræk (`buildBrowse`/`buildLineage`/`buildSources`) betalte sig i review: hvert fund kunne verificeres/fikses+testes DB-uafhængigt. Codex' stærkeste fund (H5) var en delt kontrakt-issue med søster-appen — verificér ALTID om et "port"-fund er web-specifikt eller delt før fix, for at undgå utilsigtet app-divergens.

