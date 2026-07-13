# Review 29 — Dual-review af review-27 Bølge 2

**Dato:** 2026-07-13
**Scope:** De 5 Bølge-2-commits på `fix/review-27-boelge-2` (`git diff 795e436..HEAD`) —
P1 lazy maplibre, P2 content-visibility, R2 retry/dvale, R3 ErrorBoundary (web+mobil),
T2 parity-test + buildModel-port, M-K3 selectMeId. De 2 forudgående hotfix-commits
(GeoMap U+2028 + CI-tsc, PR #30) er reviewet separat og uden for scope her.
**Metode:** Phase 1 uafhængig code-analyzer + fuld egen tsc/test/build-verifikation;
Phase 2 trigger-beslutning; Phase 3 Codex adversarial-review; Phase 4 reconcile.

**Kontekst-note:** GeoMap-syntaksfejlen (Bølge 1 S1) blev fundet UNDER dette Bølge-2-
arbejde af en agent der kørte `npx tsc --noEmit` på mobilen — en gate Bølge 1 manglede.
Rettet i #30 + mobil-tsc tilføjet til CI. Se [[mobil-tsc-i-ci-og-u2028-regex]].

---

## Phase 1 — Claude-review

**Egen verifikation (kørt på branchen, ikke antaget):** web 319/319 vitest + `build`
rent; mobil `npx tsc --noEmit` 0 fejl + jest 368/368. (Bevidst kørt selv — læringen fra
Bølge 1 var at en blokeret rerun ikke er verifikation.)

Uafhængig code-analyzer granskede 6 punkter. **Ingen runtime-fund.**

- **M-K3 `selectMeId`:** returnerer en primitiv → ingen infinite re-render; skrive-path
  (`setMe`/AsyncStorage) gemmer stadig rå id; alle sammenligninger sker mod kanoniske
  model-nøgler; `relate.tsx:57 setRelA(meId)` sætter korrekt det kanoniske id;
  `canonicalId` stadig brugt i `person/[id].tsx` til rute-id-opløsning (kun isMe-canon
  fjernet, nu dækket af selectoren). Verificeret sikkert.
- **T2 parity `stripPointerComments`:** over-strip trigges ikke af de faktiske kommentarer
  (`fields.ts` 2 linjer, `pickPreferredBio.ts` 1 linje); 5/7 moduler har ingen
  pointer-kommentar → strip er no-op → hele-fil-sammenligning fanger drift; asymmetrisk
  consuming ville give falsk RØD (sikkert), ikke falsk grøn. Ægte kode-divergens fejler
  testen. Verificeret sikkert.
- **P1 lazy maplibre:** alle 4 render-sites wrappet i Suspense; ingen eager GeoMap/
  MapLightbox-import i src → maplibre forbliver bag lazy-grænser.
- **R2 loadData:** `useCallback([])` uden stale closure; mount-effekt kører én gang, intet loop.
- **R3 web:** korrekt class-component; `main.tsx` wrapper roden → dækker Folgesvend + Redaktion.
- **R3 mobil:** `export function ErrorBoundary({error, retry}: ErrorBoundaryProps)` = korrekt
  expo-router v56-signatur, eksporteret fra rod-`_layout.tsx`.

---

## Phase 2 — Codex-trigger: **YES**

Triggers: M-K3 race-condition-claim (empirisk), parity-testens normaliserings-heuristik,
expo-router v56-API-kontrakt (R3 mobil), lazy-loading-adfærdsændring (P1). Bølge 1's
dual-review missede en bug pga. blokeret Codex-rerun → ekstra grund til adversarisk 2. mening
(men egen tsc/test/build er allerede kørt grønt, så Codex' verdict er ikke eneste gate).

---

## Phase 3 — Codex adversarial-review (2026-07-13)

**Verdict: needs-attention — ét reelt fund (MEDIUM) som Claude-analyzeren eksplicit (fejlagtigt) friholdt.**

- **Bekræftet:** M-K3, P1, P2, R2, R3 web, R3 mobil (mod installeret expo-router 56.2.11 + SDK 56-API).
- **T2 parity — recalibreret (MEDIUM):** `stripPointerComments` gik i "unrestricted consuming"
  efter en pointer-linje og forkastede ENHVER efterfølgende linje (også kode) frem til `.`/`)`.
  Codex demonstrerede empirisk at `export const REAL_WEB_ONLY_DRIFT = true;` indsat ved
  pointer-kommentaren i `fields.ts` blev slugt → falsk grøn. Dermed kunne gate'en, hvis
  eneste formål er at fange drift, SKJULE reel fremtidig drift. Phase 1-analyzerens påstand
  ("asymmetrisk consuming → falsk RØD, sikker") var forkert.
- Codex' egen vitest-rerun var read-only-sandbox-blokeret; fundet blev bevist via node-repro.

---

## Phase 4 — Reconcile

**Verdict: fixed & ship.**

**Verificeret empirisk (reproduceret uafhængigt — ej peer-review-laundering):**
- Reproducerede falsk-grøn selv via node: rå-forskellige filer → normaliseret ens; den
  injicerede `export const DRIFT`-linje forsvandt. Bekræfter Codex' fund direkte.

**Fix (commit på branchen):** normalizeren har nu TO vagter — (1) forbruger kun `//`-kommentar-
linjer (kode afbryder straks → aldrig slug kode), (2) stopper ved pointer-sætningens slut (så en
delt efterfølgende modul-doc-kommentar ikke over-strippes). Ny regressions-test beviser at
kode-drift indsat ved pointeren giver rød test. Alle 320 web-tests grønne (16 i parity.test.ts).

**Bemærk (proces):** mit FØRSTE fix-forsøg (kun kommentar-guard, uden sætnings-stop) over-strippede
`fields.ts`' delte modul-doc og fejlede `fields`-paritetstesten — fanget ved at KØRE testen, ikke
antage. Den kombinerede to-vagt-løsning er verificeret grøn.

**Impact-bucketing:** 1 fund, bucket *false-confidence/process-guard* (en regressions-gate der
kunne skjule drift). Ingen hard-crash/silent-corruption. M-K3-korrekthedsfixet stod uanfægtet.

**Læring:** Codex fangede præcis hvad code-analyzeren FRIHOLDT — adversarisk 2. mening har
selvstændig værdi selv efter en "ren" Phase 1. Og empirical-reproduction-rule virkede i begge
retninger: reproducér fundet FØR accept, og kør testen FØR du tror fixet holder.
