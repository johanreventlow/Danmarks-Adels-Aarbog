# Review 16 — samme_som-collapse kerne-motor (FASE A)

**Dato:** 2026-07-02
**Område:** `mobile/src/data/collapseSameAs.ts` + type-tilføjelser i `mobile/src/data/types.ts`
**Metode:** Dual-review (Claude code-analyzer + egen empirisk verifikation + Codex adversarial)
**Spec:** `docs/superpowers/specs/2026-07-02-samme-som-collapse-design.md`
**Plan:** `docs/superpowers/plans/2026-07-02-samme-som-collapse.md` (Task 1-3)

Identitets-projektion der folder flere `person`-rækker (linket via afklarede `samme_som`)
til ÉN kanonisk post FØR `buildModel`. Ren funktion, reversibel (alias-map + proveniens),
valideret (konflikter karantæneres, aldrig tavs drop). 19 kerne-tests grønne; fuld mobile-
suite 231/231.

---

## Fund + status

### H1 [MEDIUM] — Manglende selv-ægtefælle-validering (spec §6.1-hul) — ✅ RETTET
**Lokation:** `validateGroups`, kombineret-graf-fase.
**Symptom:** `validateGroups` tjekkede kun selv-*forælder*, ikke selv-*ægtefælle*. Spec §6.1
kræver karantæne når et merge gør en person til "sin egen forælder **eller ægtefælle**".
**Verifikation (verified):** `buildModel.addSpouse` (buildModel.ts:39-46) har INGEN `pid===oid`-
guard. En `afklaret` `samme_som` mellem to personer der er registreret gift med hinanden ville
folde gruppen, omskrive union til `p1=p2=canon`, og gøre den kanoniske person til sin egen
ægtefælle i `spousesBy`-indekset (synlig korruption).
**Impact-bucket:** silent-corruption / semantic.
**Fix:** scan `rawDb.unions` på `cm2`; `cid(cm2,p1)===cid(cm2,p2)` og canon i `accepted0` →
`rej(canon, 'selv-ægtefælle efter merge')`. Regressions-test tilføjet.

### H2 [MEDIUM/LOW] — Manglende "fødsler årtier fra hinanden"-tjek (spec §6.5-hul) — ✅ RETTET
**Lokation:** `validateGroups`, vital-blok.
**Symptom:** Levetids-tjekket er gated på `born.length && died.length`. Spec §6.5 lister en tredje
indikator ("fødsler årtier fra hinanden") som ikke var implementeret.
**Verifikation (verified):** to medlemmer med fødselsår 1644 og 1750 men INGEN dødsår → levetids-
tjek springes over, køns-tjek passerer → et fejl-blåstemplet link ville folde to åbenlyst
forskellige personer.
**Impact-bucket:** silent-corruption / semantic.
**Fix:** `born.length > 1 && max(born) - min(born) > MAX_BIRTH_SPREAD_YEARS (80)` → karantæne.
Tærskel valgt langt over legitim kilde-til-kilde-usikkerhed (defense-in-depth). Regressions-test tilføjet.

### H3 [LOW] — Cyklus-attribution over-karantænerede uskyldige grupper — ✅ RETTET
**Lokation:** `validateGroups`, global cyklus-detektion.
**Symptom:** `[...stack, hit].find(accepted)` søgte hele DFS-stien, ikke selve cyklus-udsnittet.
En accepteret gruppe FØR cyklus-indgangen (uden for cyklussen) kunne blive karantæneret.
**Verifikation (verified — EMPIRISK):** konstrueret fixture (M accepteret uden for cyklus, N's
merge skaber cyklus P↔N); før fix var `canonicalIdById['a1']===undefined` (M ikke foldet). Ikke
korruption (restart-loopet fanger altid N), men en gyldig foldning tabt. Bekræftet uafhængigt af
code-analyzer.
**Impact-bucket:** sub-optimal (fail-safe; ingen korruption).
**Fix:** karantænér ALLE accepterede grupper i cyklus-udsnittet `stack.slice(indexOf(hit))` — rører
ikke off-cyklus grupper, og garanterer at hver merge-induceret kant i cyklussen fjernes (projektionen
altid acyklisk). Regressions-test tilføjet.

### M1 [LOW] — Coalesce-rækkefølge ikke id-sorteret (spec §7-afvigelse) — ✅ RETTET
**Symptom:** `others` bevarede `ids`-rækkefølge (Set-insertion), ikke "alias'er sorteret på id"
(spec §7). For 3+-medlems-grupper med konfliktende ikke-null-værdier blev coalesce traversérings-
afhængig (ikke-deterministisk på tværs af loads). Harmløst for de reelle 2-medlems-grupper.
**Fix:** `.sort()` på alias-id'erne før coalesce.

### M2 [LOW cosmetic] — Selv-forælder-`rej` manglede `!rejected`-guard — ✅ RETTET
**Symptom:** flere selv-kanter for samme canon kunne producere duplikerede `QuarantineNote`s.
**Fix:** tilføjet `!rejected.has(canon)`-guard (paritet med cyklus-stien).

### D1 [HIGH] — Rejekteret forældre-gruppe maskerede konkurrerende forældre — ✅ RETTET (Codex-opgraderet)
**Symptom:** competing-parents kanoniserede forældre via `cm = canonMap(groups)` (ALLE foreslåede
grupper). Hvis en gruppes forældre kun ser ens ud fordi en ANDEN gruppe (senere rejekteret)
kanoniserer dem sammen, slipper konkurrerende forældre igennem.
**Verifikation (verified — EMPIRISK):** Codex gav konkret trigger; reproduceret i test: merge A→B
(A barn af P, B barn af Q) + P→Q der rejektes pga. køn. `cm` normaliserer P/Q→Q, så A→B's forældre
ser ens ud og A→B foldes. Efter P/Q af-mergedes har A→B to forskellige forældre-familier →
`buildModel.firstUnionKey` (buildModel.ts:64-71) vælger vilkårligt. Før fix: `accepted.has('B')===true`.
**Impact-bucket:** silent-corruption / semantic (forkert forælder på foldet person).
**Rettelse (recalibreret fra "defer"):** `validateGroups` omskrevet til **fixed-point-løkke** — alle
checks genkøres på den aktuelt-accepterede canon-map indtil en runde ikke rejekterer mere. Subsumerer
også `cm`/`cm2`-splittet (én canon-map pr. runde) og M2-duplikat-noten (`rej` idempotent). Regressions-test tilføjet.

### D2 [MEDIUM] — Konfidens first-wins ved kant-dedup nedgraderede — ✅ RETTET (Codex-opgraderet)
**Symptom:** `dedupeByKey` beholdt FØRSTE række pr. `parent|child|union`. To rækker der kanoniserer
til samme triple med forskellig `konfidens` → first-wins kunne beholde den svagere.
**Verifikation (verified):** Codex bekræftede at `buildModel.konfByEdge` KUN ser den overlevende
række (dedup sker før buildModel), så stærkeste-vinder-logikken dér mitigerer IKKE. Nedgradering af
sti-advarsler mulig. (Bemærk: same-union-kollisionen forudsætter A/B som co-partnere = self-ægtefælle,
der nu fanges af H1 — men fixet er billigt og future-proofer mod TNG-enrichment.)
**Impact-bucket:** silent-corruption / semantic (svækket relations-konfidens).
**Rettelse:** parentChild-dedup beholder STÆRKESTE konfidens ved kollision (via `KONFIDENS_RANK`).
Regressions-test tilføjet.

---

## ✅ Verificeret sikkert (code-analyzer)
- Union-find + unik-sink: kæder (A→B→C), tvetydig sink, 2-node-cyklus, diamant (A→B,A→C,B→D,C→D
  accepterer D), ufuldstændig komponent — alle korrekt.
- Completeness/GDPR-gate: karantænerer enhver gruppe med medlem uden for `knownIds` (spec §3/§5).
- Ingen gyldig parent-child-kant tabt; karantænerede medlemmer aldrig foldet.
- `years`-regen før `buildModel` (konsistent med umulig-forælder-guard).

## Codex adversarial-review konsekvens (2026-07-02)

Verdict: **needs-attention → løst inline.**

**Bekræftet (verified empirisk) + rettet:**
- H1, H2, H3, M1, M2: bekræftet af Codex; fixes lukker de demonstrerede huller.
- **D1** (HIGH, opgraderet fra egen "defer"): reproduceret empirisk (interagerende-gruppe-fixture) →
  fixed-point-omskrivning.
- **D2** (MEDIUM, opgraderet): bekræftet at dedup fjerner stærkere evidens før buildModel →
  konfidens-stærkeste-dedup.
- **Ingen ny cyklus-escape:** Codex bekræftede at reject-all-in-cycle-slice-DFS terminerer og
  rejekterer hver foldet gruppe i cyklus-udsnittet — ingen merge-induceret cyklus når `buildModel`.

**Impact-buckets:** silent-corruption/semantic ×4 (H1 self-ægtefælle, H2 fødsler-langt-fra, D1
konkurrerende forældre, D2 konfidens-nedgradering), sub-optimal ×2 (H3 over-karantæne, M1 coalesce-orden),
cleanup ×1 (M2 duplikat-note). Deferred: 0.

**Læring:** "Contrived/current-data"-defer på et invariant-brud er ikke gyldigt hvis det bryder en
STATED invariant (spec §6 karantæne-garanti) — Codex' konkrete trigger viste at D1 var silent-corruption,
ikke kosmetik. Fixed-point-validering er den rette altitude når rejektion af én gruppe ændrer de øvriges
kanonisering (single-pass med `cm`/`cm2`-split var bandaid'et).
