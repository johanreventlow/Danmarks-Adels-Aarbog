# Review 01 — DAA parse-styrkelse + auto-eskalering (dual-review)

**Dato:** 2026-06-18
**Scope:** Begge features merged til main i dag (diff `55ba29e..HEAD`, ~756 LOC, 7 filer):
`validate.py`, `escalate_merge.py` (ny), `load_daa.R`, `extraction-schema.json`, `SKILL.md` + 2 testfiler.
**Forudgående review:** 5 per-task-reviews + 1 whole-branch opus-review (fandt 3 integration-bugs, fixet).
**Formål med denne pass:** Codex adversarisk verifikation af (a) at fixene er korrekte, (b) hvad alle Claude-passes missede. Immutable evidens-lag = høj indsats; auto-load gør gate-korrekthed kritisk.

---

## Kontekst Codex skal kende

- `validate.py` (trin ④) er deterministisk "fejlfri kode". `validate(rec, src, known_by_linje) -> (issues, advisory)`. `issues` = blokerende (post loader ikke); `advisory` = ikke-blokerende (R8 = manglende død/ægteskab; V9 = vocab).
- `normalize_record(rec, src)` udleder `boern` deterministisk fra prosa (overskriver LLM-felt) — kaldes i `validate.main()` OG i `escalate_merge.decide()`.
- `escalate_merge.py`: re-validerer Opus-gen-udtræk, promoverer til clean.json hvis 0 blokerende OG R8-typer ikke udvides ift. Sonnet-snapshot. Promoverede markeres `_escalated=True`; `load_daa.R` stempler deres konklusioner `blaastemplet_af="Opus-escalated"`.
- `derive_aegteskaber` er DEMOTERET til advisory (forrige feature): bruges KUN af `expected_signals` (R8). Må IKKE overskrive `rec['aegteskaber']`.

---

## Claims der skal verificeres adversarisk (empirisk, mod faktisk kode)

### H1 [HIGH] — normalize_record-refactor er behavior-preserving i validate.main()
**Claim:** Udskillelsen af boern-override til `normalize_record()` ændrer ikke `validate.main()`'s adfærd for ikke-eskalerings-brug; og kaldet i `decide()` betyder at den promoverede `merged = dict(reext)` faktisk bærer den normaliserede `boern` (fordi `normalize_record` muterer `reext` in-place FØR `merged` bygges).
**Verificér:** spores `boern` korrekt hele vejen? Er der en sti hvor `merged` får rå LLM-`boern`?

### H2 [HIGH] — R8 set-subset-gate afviser miss-type-swap korrekt
**Claim:** `_r8_types(reext) <= _r8_types(snap)` (subset) promoverer kun hvis ingen NY R8-miss-type introduceres. En swap (snap mangler ægteskab; reext mangler død i stedet) afvises.
**Verificér:** brug af fuld R8-streng som set-nøgle — er der en kombination hvor swap fejlagtigt promoveres, eller hvor en ægte forbedring fejlagtigt afvises? Hvad hvis reext har strict-subset (færre misses)?

### H3 [HIGH] — manglende snapshot fejler closed
**Claim:** `decide()` returnerer `promote=False` hvis `snapshot is None` (ingen reext-fallback). Ingen post promoveres uden en ægte Sonnet-baseline at sammenligne mod.
**Verificér:** er der en sti i `merge_escalated` hvor en manglende snapshot alligevel ender i clean?

### H4 [MEDIUM] — nr_label-fix lukker både-clean-og-review for bogstav-poster
**Claim:** `validate.main()`s review-record har nu `nr_label`, så en blokeret 15a-post (nr=15) ikke får divergerende nøgle ("I","15") vs eskalerings-nøgle ("I","15a"). Promoveres den, fjernes den fra review.
**Verificér:** er nøgle-formen `(linje, nr_label or str(nr))` konsekvent på ALLE producer/consumer-sites (validate review+clean, escalate_merge `_key`, escalation worklist)?

### H5 [MEDIUM] — derive_aegteskaber er reelt inert (kun advisory)
**Claim:** Efter demoteringen muterer `derive_aegteskaber` IKKE `rec['aegteskaber']` nogen steder; den bruges kun i `expected_signals` til R8-signalet.
**Verificér:** grep alle call-sites; er der nogen residual overskrivning i `main()`?

### H6 [MEDIUM] — R7 substring-gate falsk-flagger ikke legitime spans
**Claim:** R7 (`norm(sp) not in hay` hvor hay = norm(raw_text)) afviser kun hallucinerede spans. Et span der ordret findes i prosaen (efter whitespace-normalisering) består.
**Verificér:** kan en legitim `kilde_span` falsk-afvises pga. normaliserings-mismatch (fx unicode, bindestreger, ombrudt whitespace)? Kan en hallucination slippe igennem via substring-tilfældighed?

### H7 [LOW] — kilde_span når citat_tekst for både facts og vielse
**Claim:** `load_daa.R` tråder `kilde_span` → `citat_tekst` for både fakta-loopet og vielse-fakta; eksisterende call-sites uden span defaulter til NA.
**Verificér:** ingen brudt call-site; ingen positional-arg-misalignment i R.

---

## Codex adversarial-review konsekvens (2026-06-18)

Verdict: needs-attention. Claims H1-H5, H7 **confirmed**; H6 **recalibreret**; 2 nye fund.

**Bekræftet (verified empirisk i denne reconcile):**
- H1 (normalize_record muterer reext in-place før merged-kopi → promoveret post bærer udledt boern): confirmed af Codex' object-identity-trace.
- H2 (R8 set-subset afviser swap + tillader strict-subset-forbedring): confirmed.
- H3 (manglende snapshot fejler closed): confirmed.
- H4 (nr_label-nøgle konsekvent): confirmed.
- H5 (derive_aegteskaber inert, kun expected_signals/R8): confirmed.
- H7 (kilde_span → citat_tekst for facts + vielse): confirmed.

**Nye fund:**

### NEW1 [HIGH → reklassificeret: dokumenteret §3-begrænsning] — R7 substring-provenans er ikke semantisk
**Lokation:** `validate.py` R7+R1.
**Reproduceret:** `faktatype='død', date_raw='1300', kilde_span='1300'` mod `raw_text='N.N. født 1300 på X.'` → `validate` returnerer `([], [])`. En falsk død-påstand med fødsels-årstal slipper i clean/load.
**Bucket:** silent-corruption (falsk fakta i uforanderligt lag).
**Reconcile-dom:** verified, men dette ER den bevidst-accepterede §3-begrænsning ("forkert-felt / present-but-wrong-shape — portene er blinde"). Rammer hele extraction-pipelinen (ikke kun eskalering) og var aldrig en semantisk gate — R7 giver proveniens/auditbarhed, ikke type-validering. IKKE en regression fra dagens arbejde. Den type-bevidste styrkelse Codex foreslår er PRÆCIS den "forkert-felt-detektor" worklist-interfacet (§3) blev bygget til. → **Bruger-beslutning:** løft baren nu (wire detektoren) eller behold som navngiven udvidelse.

### NEW2 [MEDIUM] — fejlede eskaleringer mister brud/advisory-diagnostik i review.json
**Lokation:** `escalate_merge.py` `merge_escalated` (review-rebuild-loop).
**Reproduceret:** kode-inspektion — `new_review.append(reext_by_key.get(key))` appender den RÅ reext-record, ikke en review-formet dict. `decide()`s `issues`/`advisory` kasseres i else-grenen. En R8-ren post gen-udtrukket som blokerende (`† 1999`) ender i review.json UDEN `brud` → mennesket ser ikke fejlårsagen.
**Bucket:** false-confidence/process-guard (degraderet recovery-sti).
**Reconcile-dom:** verified, udokumenteret, indført af escalate_merge. **FIX NU.**
**Fix:** opsaml `issues`/`advisory` per fejlende nøgle i `merge_escalated`; append review-formet objekt `{linje, nr, nr_label, navn, brud, advisory}` (matcher `validate.main`-formen). Regression-test: R8-ren post der fejler blokerende efter Opus → review-entry har `brud`.

**Læring:** Codex' adversariske pass (3. uafhængige engine efter 5 per-task + 1 opus whole-branch) fangede et ægte recovery-sti-hul (NEW2) ingen Claude-pass så, OG demonstrerede §3-begrænsningen konkret (NEW1). Bekræfter dual-review-værdien: forskellige engines fanger forskellige klasser. Substring-provenans ≠ semantisk validering — fremtidig type-bevidst detektor anbefales.
