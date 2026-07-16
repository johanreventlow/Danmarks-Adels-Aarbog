# Review 28 — Flere DAA-udgaver: Problem 3 + Leverance 0 + loader-hygiejne (PR #37)

**Dato:** 2026-07-16
**Scope:** PR #37 — tværudgave-matcher (`@daa/core`), `red_ikke_samme_som` (DB), `redaktionRead`-bro,
Leverance 0 (`post_load_fixup.R` fail-closed source), loader-hygiejne (`source.aar`, partner-stub `add_extid`).
**Metode:** `/simplify` (4 parallelle cleanup-agenter) + `/dual-review-cycle` (Claude code-analyzer korrektheds-
bug-hunt). **Codex-pass skippet** — `auth_required` i baggrunds-session; Claude-reviewet var empirisk-verificeret
(Jaro-Winkler håndverificeret, SQL-guards sporet til faktiske forbrugere, `parse_aar` edge-cases gennemgået).

## /simplify — 4 agenter (reuse, simplification, efficiency, altitude)

| Fund | Angle(r) | Status |
|---|---|---|
| Mappere (`buildMatchPersoner`/`parseIkkeSammeSomPar`) duplikeret web↔mobil | alle 4 | ✅ Flyttet til `@daa/core` (commit 6fefe3d) |
| `buildScored` beregner `overlapEvidence` 2× i top-K-gren | efficiency+simplification | ✅ Beregnes 1× |
| `yearOf` duplikerer `parseYear` | reuse | ✅ Genbruger `parseYear` |
| `VARIANT_MAP[repr]=repr` no-op | simplification | ✅ Fjernet |
| `fetchMatchPersoner` over-henter conclusion/assertion | efficiency | ⏸ **Skippet+dokumenteret**: batch-`.in(factIds)` sprænger PostgREST-URL; rigtig fix = server-side view (udskudt) |
| Marginal sort pr. A-gruppe; altitude-nits | efficiency/altitude | ⏸ Skippet (spec-kohærente/marginale) |

## /dual-review-cycle — Claude korrektheds-bug-hunt

**Verdict: ingen HIGH/MEDIUM correctness-bugs.** Omfattende "verificeret sikker"-liste: substring-hazard
(alle samme_som-forbrugere bruger `.eq`, trigger `WHEN rolle='samme_som'` eksakt), SQL-guards/normalisering/
idempotens, Jaro-Winkler (DWAYNE/DUANE=0.84 håndverificeret), `assignTiers`-injektivitet, `buildScored`
post-simplify (overlap 1×), `parse_aar` edge-cases, `post_load_fixup` fail-closed, `buildMatchPersoner` as-of.

**3 LOW-fund:**
| ID | Fund | Status |
|---|---|---|
| L1 | `red_ikke_samme_som` manglede `pg_advisory_xact_lock` → concurrent kontradiktion muligt | ✅ Fixed (c0426c6), re-testet 10/10 |
| L2 | Christian↔Kristian → c-blok vs k-blok (aldrig sammenlignet) | ✅ Fixed (variant-klasse), core 254/254 |
| L3 | final `a→e` på 4-tegns tokens (Asta→aste) | ⏸ Skippet — spec-kompatibel §3.2 + editor-gatet (advisory) |

## Verifikation (samlet)

- **Core:** 254/254 (matcher + foldning + mappere); Jaro-Winkler mod kanoniske vektorer.
- **Matcher mod ægte data:** 8/8 facit-par genfundet som auto, 0 falske (1939↔2012-14-udtræk).
- **DB (`red_ikke_samme_som`):** 10/10 integrationstests mod lokal prod-kopi (`daa_test2`) — evidens-triple,
  idempotens begge veje, kontradiktions-guards begge retninger, rolle-gate, drift-assert, advisory-lock.
- **Lokal load:** 2012-14 + 1939 præsenslister loadet i `daa_test2` — integrationstester Leverance 0 +
  hygiejne (source.aar=2014/1939, partner-stub external_id).
- **Web/mobil:** redaktionRead tsc rent + mobil 32/32. (Web-komponent-tests fejler på manglende
  `@testing-library/react` i worktree — miljø-artefakt, ikke PR-kode; grønt i CI/main.)

## Verdict: **merge-klar** (bruger markerer "Ready for review")

**Kendte, bevidste udeståender (ikke blokerende):**
- `fetchMatchPersoner` over-fetch → server-side view ved skala (dokumenteret i koden).
- Advisory-lock lukker TOCTOU, men single-writer-PoC-posturen består (samme klasse som `max(id)+1`).
- "Sammenlign udgaver"-UI (§5) er ikke i denne PR (bevidst — bruger valgte 1/2/3, ikke 4).
