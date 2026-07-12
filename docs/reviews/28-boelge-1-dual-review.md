# Review 28 — Dual-review af review-27 Bølge 1

**Dato:** 2026-07-13
**Scope:** 6 commits på `fix/review-27-boelge-1` (T1 CI, R1 fejlhåndtering web+mobil,
S1 GeoMap-escape, P4 død query, S2 privat-filter). Implementerer Bølge 1 fra
`docs/reviews/27-kodekvalitet-sikkerhed-performance-review-web-mobil.md`.
**Metode:** Phase 1 Claude-review (uafhængig code-analyzer bug-hunt + manuel
type-check + empirisk prod-verifikation), Phase 2 trigger-beslutning, Phase 3 Codex
adversarial-review, Phase 4 reconcile.

---

## Phase 1 — Claude-review

Uafhængig code-analyzer granskede alle 5 ændringspunkter. **Én reel (men inert)
adfærdsændring; resten verificeret sikker.**

### D1 [LOW — verificeret inert] fetchAbout: `privat IS NULL`-semantik
**Lokation:** `web/src/data/public.ts` (fetchAbout-query + fjernet klient-`continue`)
**Symptom:** Gammel `if (r.privat) continue` inkluderede rækker med `privat IS NULL`
(`if(null)` = falsy → beholdt). Ny `.eq('privat', false)` ekskluderer dem (SQL
`NULL = false` → NULL, ikke true). En slaegt/lineage-narrativ med `privat=NULL`
ville forsvinde fra "Om slægten".
**Verifikation (empirisk, prod 2026-07-13):**
- `narrative?privat=is.null` → **0 rækker** i hele basen (0 for slaegt/lineage).
- `schema.sql:410`: `privat BOOLEAN DEFAULT FALSE` → normale inserts giver FALSE.
- `fetchPersonDetail`/`fetchEstateInfo` brugte ALLEREDE `.eq('privat', false)` på
  samme tabel før dette PR.
**Konsekvens:** Ingen. Ingen NULL-rækker findes; ændringen gør fetchAbout
*konsistent* med de to søster-funktioner frem for afvigende (den var den eneste der
filtrerede klient-side). At tilføje `.or('privat.is.null,...')` til KUN denne ville
gen-introducere divergens.
**Beslutning:** Behold `.eq('privat', false)`. DEFAULT-FALSE-antagelsen er noteret
i kode-kommentaren.

### Verificeret sikkert (ingen fund)
- **orThrow-typer:** `{data:T; error:unknown}` er strukturelt kompatibel med
  supabase-js' diskriminerede unions. `maybeSingle()` uden match → `{data:null,
  error:null}` → orThrow kaster IKKE (error null), returnerer null, håndteret med
  `?.`/`?? []` ved alle 5 call-sites. Tomme `.in()`-grene fik `error:null` tilføjet
  → matcher signaturen. `tsc -b` rent.
- **GeoMap-escape (S1):** hexdump bekræfter regex-targets `3c`/`e2 80 a8`/`e2 80 a9`
  (`<`/U+2028/U+2029) → korrekt mappet til `<`/` `/` `. Data bevaret
  ved runtime (WebView-JS læser `<`→`<`). Øvrige HTML-interpolationer er
  app-konstanter (Colors/DEMO_STYLE/MAPLIBRE_*/interactive/mode), ikke bruger-data;
  `points` er eneste bruger-data og er escaped.
- **load.ts (P4):** destructure- og Promise.all-array har begge 16 elementer efter
  fjernelse; `family` bruges ikke andetsteds. Ren død-kode-fjernelse.
- **CI (T1):** `test`=`vitest run`/`jest` (ej watch). Web-suite verificeret grøn med
  DUMMY-creds (301/301) → hermetisk, ingen secrets/netværk. Mobil 365/365 lokalt.
- **Redaktion.tsx (R1):** `loadErr`-banner (linje 439) renderes ubetinget i shell'en
  (ingen `if(!model) return`-gate før) → fejl surfacer, ingen evig-loading-fælde.
  Verificeret ved læsning af render-rækkefølge.

### Deferred (uden for Bølge 1's navngivne fund)
- Mobil person-editor har yderligere tavse catches (`refreshMedia` ~325,
  post-write-refresh ~795-798) i en anden kodesti nær den kendte crash. Ikke rørt.

---

## Phase 2 — Codex-trigger: **YES**

Flere triggers opfyldt: (1) CI-gate-ændring (ci.yml), (2) executable YAML-recipe,
(3) sikkerheds-escape-recipe (S1, korrekthed er sikkerhedskritisk), (4) empiriske
claims (RLS gater privat; 0 NULL-rækker; CI-hermeticitet). Kør Codex.

---

## Phase 3 — Codex adversarial-review (2026-07-13)

**Verdict: approve — ingen materielle fund.**

- **D1 recalibreret som "reel men aktuelt inert NULL-only drift"** — samstemmer med
  Claude-analysen.
- **Bekræftet:** orThrow, GeoMap-escaping, load.ts-slot-alignment, CI-konfiguration
  og Redaktion `loadErr`-claimet.
- **Ingen ny bug fundet.** Doc'et oplyser korrekt de resterende tavse mobil-refresh-
  catches (deferred).
- Codex' egne test/build-reruns fejlede KUN pga. read-only-sandbox der blokerede
  midlertidige writes (`.env.local` kunne ikke skrives, `npm ci --dry-run` exit 255)
  — ikke repo-fejl. Uafhængigt bekræftet grønt: web 301/301 (dummy-env), mobil 365/365.

---

## Phase 4 — Reconcile

**Verdict: ship.** Ingen recalibreringer; ingen nye fund; ingen implementeringsændringer.

**Bekræftet (verified empirisk — reproduceret uafhængigt af Codex, ej peer-review-laundering):**
- **D1 inert:** `narrative?privat=is.null` → 0 rækker mod prod (kørt af Claude, ikke
  overtaget fra Codex). Schema `DEFAULT FALSE`. → behold `.eq('privat', false)`.
- **Sikkerhed S1:** hexdump af regex-targets (Claude) + Codex-gennemgang af hele
  `buildHtml()` bekræfter at `points` er eneste bruger-data i WebView-HTML og er escaped.
- **CI hermeticitet:** web-suite grøn med dummy-creds (kørt af Claude).
- **orThrow-typer / load.ts-alignment / Redaktion-loadErr:** verificeret ved
  kode-inspektion (Claude) + Codex-bekræftelse.

**Impact-bucketing:** Ingen recipes reddet (Codex fandt intet at rette). D1 hører i
bucket *silent-corruption/semantic-drift* men er verificeret uden live-effekt →
ekskluderet fra enhver ROI-tælling.

**Læring:** Ved små, veldefinerede ændringer med hermetiske tests tilføjede dual-review
tillid men ingen nye fund — trigger-beslutningen (YES) var stadig korrekt pga.
sikkerheds-escape + CI-gate + empiriske claims. `privat IS NULL`-nuancen er et
lærebogseksempel på empirical-reproduction-rule: fanget af analyzer, men severity
korrekt nedjusteret til inert via direkte prod-query frem for antagelse.
