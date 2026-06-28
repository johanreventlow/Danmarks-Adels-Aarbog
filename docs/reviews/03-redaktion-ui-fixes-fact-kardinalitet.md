# Cycle 03 — Redaktions-UI live-test-fixes + fact-kardinalitet

**Dato:** 2026-06-28
**Scope:** `55437d2..HEAD` (4 kode-commits efter whole-branch-review):
`hydrateAuth`-boot-fix, fact-kardinalitet (read+view), fact-målrettet skrivning
(2 nye RPC'er), skrivemode-pille.
**Reviewers:** Claude (code-analyzer Phase 1) + Codex (Phase 3, adversarial).

## Sammenfatning

| ID | Severity | Status | Commit |
|----|----------|--------|--------|
| H1 | MEDIUM (semantic-drift) | ✅ Implementeret | c069e10 |
| NEW1 | MEDIUM (false-confidence) | ✅ Implementeret | cd593eb |
| H2 | — | ❌ Dismissed (Codex: altid-nyt-fact → upsert nytteløst) | — |
| M1 | LOW | ❌ Dismissed (reset-on-open dækker) | — |

**Codex impact (verified):** 1 semantic-drift (H1) + 1 false-confidence (NEW1). H2/M1 dismissed (ekskl. ROI).
**Læring:** read-lag-fejl må aldrig vise sig som tom review-kø ("tom = alt OK" er farlig default).

---

## H1 [MEDIUM] — `joinEvidence`: `uenig` falsk-positiv ved tom-værdi-oplysninger

**Lokation:** `mobile/src/data/redaktionRead.ts:78-81`

**Symptom:** `uenig = new Set(opl.map(o => o.vaerdi)).size > 1`. `vaerdi` falder tilbage
til `''` når både `vaerdi_tekst` og `date_raw` er null (linje 71). Et fact med én rigtig
værdi + én tom-værdi-assertion → Set = {`'kammerherre'`, `''`} → size 2 → "UENIGE"-badge,
selvom konflikten reelt er en data-mangel, ikke en kilde-uenighed.

**Verifikation:**
```ts
vaerdi: a.vaerdi_tekst ?? a.date_raw ?? '',
...
const distinkte = new Set(opl.map((o) => o.vaerdi));
... uenig: distinkte.size > 1,
```

**Konsekvens:** Misvisende "UENIGE"-markering på et fakta-kort når problemet er manglende
data (tom assertion), ikke reel uenighed. Ikke crash; falsk signal i editoren.

**Foreslået fix:** Ekskludér tomme værdier før distinct:
`const distinkte = new Set(opl.map((o) => o.vaerdi).filter(Boolean));`

---

## H2 [LOW→MEDIUM] — `red_opret_fakta`: conclusion-INSERT uden `ON CONFLICT`

**Lokation:** `schema.sql:409-411` (+ `db-migrations.sql` samme blok)

**Symptom:** `red_opret_fakta` indsætter conclusion uden `ON CONFLICT (target_type,
target_id) DO UPDATE`. Søster-funktionen `red_upsert_fakta` (schema.sql:350) bruger upsert
for præcis samme INSERT. Divergens fra det defensive mønster.

**Verifikation:**
```sql
INSERT INTO conclusion(id, target_type, target_id, valgt_assertion_id, status, ...)
  VALUES ((SELECT coalesce(max(id),0)+1 FROM conclusion), 'fact', v_fact, v_assert,
          'afklaret', 'Redaktør', current_date);
```
`conclusion` har `UNIQUE (target_type, target_id)`. Da `red_opret_fakta` ALTID laver et nyt
`v_fact`, kan en frisk conclusion på det nye fact ikke kollidere → **sikker i praksis**
(bekræftet i rollback-test: fact 3778, conclusion=1). Men ved en fremtidig migration til
IDENTITY-sekvenser eller retry kunne det kaste unique-violation i stedet for upsert.

**Konsekvens:** Ingen i nuværende PoC (max(id)+1 + altid-nyt-fact). Mønster-divergens der
bør lukkes før multi-writer.

**Foreslået fix:** Tilføj `ON CONFLICT (target_type, target_id) DO UPDATE SET
valgt_assertion_id=excluded.valgt_assertion_id, status='afklaret', blaastemplet_af='Redaktør',
blaastemplet_naar=current_date` — nul-cost, fjerner divergensen.

---

## M1 [LOW] — `addScratch` nulstilles ikke ved Annullér

**Lokation:** `mobile/src/app/redaktion/person/[id].tsx:203` (Annullér-handler)

**Symptom:** "Annullér" på "+ Ny [felt]"-formen sætter `setAddFelt(null)` men nulstiller
ikke `addScratch`. Reset-on-open (`setAddFelt(felt); setAddScratch({...})`) dækker det i
praksis, så ingen synlig lækage. Hygiejne-fix.

**Konsekvens:** Ingen data-tab; minimal UX-inkonsistens.

**Foreslået fix:** `onPress={() => { setAddFelt(null); setAddScratch({ vaerdi: '', kilde: '' }); }}`

---

## Codex adversarial-review konsekvens (2026-06-28)

**Verdict:** needs-attention (no-ship indtil H1 + NEW1 rettet)

**Bekræftet (verified — direkte source-evidens, kode-citat):**
- **H1** — `redaktionRead.ts:71-81`: `vaerdi: a.vaerdi_tekst ?? a.date_raw ?? ''` + `new Set(...).size > 1`.
  Værdier `['kammerherre','']` → size 2 → falsk `uenig`. Codex skærper recipe: `.trim().filter(Boolean)`
  (fanger også whitespace-only). + regression-test.
- **NEW1 [medium]** — `redaktionRead.ts:98-101`: `const { data } = await supabase.from('red_konflikt')...;
  return (data ?? []).map(...)`. Supabase-`error` destruktureres væk → ved RLS/grant/migration-skew
  fejler query'en stille → dashboard viser **tom kø = "ingen konflikter"** i stedet for fejl-tilstand.
  Skjuler de poster der KRÆVER gennemsyn. Bucket: false-confidence/process-guard.

**Recalibreret (Codex-argument empirisk efterprøvet → accepteret):**
1. **H2 DISMISSED.** `red_opret_fakta` indsætter ALTID et nyt `v_fact` (max(id)+1), så conclusion på
   det nye fact kan aldrig kollidere; en retry laver bare ENDNU et nyt fact → `ON CONFLICT` ville
   være dead code. Det foreslåede upsert forbedrer ikke retry-sikkerhed. Verificeret ved at læse
   funktions-kroppen: hver kald → unik fact_id → ingen unique-violation mulig. **Droppes.**
2. **M1 DISMISSED.** Reset-on-open (`setAddFelt(felt); setAddScratch({...})`) dækker; Annullér-reset
   er ren hygiejne uden reel effekt. **Droppes** (valgfri kosmetik).

**Impact-buckets (kun verified):**
- Semantic-drift / silent-corruption: 1 (H1 falsk UENIGE-badge).
- False-confidence / process-guard: 1 (NEW1 tom-kø-maskerer-fejl).
- Dismissed (ekskluderet fra ROI): H2 (nytteløst upsert), M1 (kosmetik).

**Læring:** Read-laget (`fetchKonflikter`/`fetchPersonEvidence`/`fetchSletPreview`) sluger
Supabase-fejl og returnerer tomt → en TOM "Til gennemsyn"-kø er tvetydig (ingen konflikter VS
query fejlede). For review-køer er "tom = alt OK" en farlig default. Surface fejl-tilstand.

---

## Verificeret sikkert (code-analyzer Phase 1)

- SQL `coalesce(max(id),0)+1` — accepteret PoC-tradeoff (eksisterende kommentar schema.sql:312);
  begge nye RPC'er spejler `red_upsert_fakta` præcist; single-writer.
- `red_tilfoej_oplysning` fact-eksistens-tjek til stede + korrekt (guard mod stale factId).
- `red_konflikt` `CREATE OR REPLACE`: `fact_id` appendet sidst (kolonne-orden OK).
- `buildRpcCall` arg-navne matcher RPC-signaturer eksakt (op. A + B); factId-null-guard + test.
- `joinEvidence` liste-refactor: sorteret på fact.id, push (ikke overskriv) — ingen fact tabes.
- `FaktaKort.tilføj` factId-sti: `else if (evidens)`-guard korrekt.
- `hydrateAuth` ved boot: korrekt dependency-array, ingen dobbelt-kald.
- Write-path end-to-end trace ren (UI→Change→RPC→DB→re-fetch).
