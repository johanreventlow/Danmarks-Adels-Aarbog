# Eager-udtræk & data-strategi — design

**Dato:** 2026-06-18
**Status:** Godkendt (brainstorm) — afventer implementeringsplan
**Scope:** Data-strategi (tråd B). Parse-styrkelse (tråd A) foldet ind som forudsætning.
Context-budget (C) og repo-oprydning (D) håndteres separat — se §7.

---

## 1. Problem & motiv

Spørgsmålet der startede designet: *bør vi udtrække ALLE fakta i narrativet til
senere brug, men kun vise det væsentlige? Og hjælper det ved flere kilder
(flere DAA-udgaver) på samme person?*

**Drivkraften er fremtidssikring:** udtræk mens prosaen + LLM-konteksten er
frisk, frem for en dyr re-parse senere når behovet opstår.

Nøgle-indsigt: **den dyre, ikke-regenererbare ressource er LLM-kørslen** (de 591
strukturerede udtræk), ikke lagring. DB'en regenereres på ~14 sek
(`load_daa.R` truncerer + genindlæser). Marginal-omkostningen ved at udtrække
mere *i samme kørsel* er lav; omkostningen ved at re-køre senere er høj.

---

## 2. Kerne-beslutning: to risiko-tiers (ikke ét "extract alt"-valg)

"Extract alt vs. vis væsentligt" er **to beslutninger med modsat risikoprofil**:

### Tier 1 — Proveniens-fangst (LAV risiko, verificerbar) — **gør det**
Gem kilde-spanet hvert fakta blev udtrukket fra, i `citation.citat_tekst`
(felt findes allerede i skemaet; populeres ikke i dag).

- **Verificerbart:** spanet SKAL være substring af postens `raw_text` —
  håndhæves deterministisk præcis som R1 håndhæver årstal.
- **Ren fremtidssikring:** med spanet gemt kan fakta genverificeres, forfremmes
  eller afstemmes på tværs af udgaver **uden ny LLM-kørsel**.
- Ikke en data-kategori — en egenskab på ALLE udtrukne fakta.

### Tier 2 — Katalog-udvidelse (HØJERE risiko, fortolket) — **gated, inkrementel**
Flere fakta-typer ind i evidenslaget. Hver ny type er fortolkning der vandrer
ind i de (semantisk) uforanderlige `assertion`-rækker.

- Kræver **egen deterministisk valideringsgate per type** i `validate.py` før
  den eager-udtrækkes — ellers permanent hallucination i evidenslaget.
- Tilføjes type-for-type, ikke som "extract alt".

**Den reelle akse for Tier 2: verificerbar vs. fortolket.**

| | Verificerbar (anker i teksten → sikker at gate) | Fortolket (dom uden anker → risikabel) |
|---|---|---|
| Datoer | fødsel/død/dåb/begravelse/floruit (`date_raw` ordret, R1) ✅ | alder-ved-hændelse (udledt) |
| Slægtskab | ægteskab (`g.`,`1°`,`med X`,`skilt`), børn (`nr. N-M`) | "formodet søn af…" (inferens) |
| Godser | `til <Gods>` (token i tekst) | bopæl fra prosa ("boede på…") |
| Titler/embeder | greve, kammerherre, oberst (vocab-ord til stede) | karakteristik ("dygtig administrator") |
| Dekorationer | R., DM., S.K. (lukket forkortelses-vocab) | religion/konfession |
| Død | — | dødsårsag udledt af prosa |
| Identitet | bogens (linje, nr.) eksplicit | identitetssammenkædning (§9 udskudt) |

Venstre kolonne udtrækkes stort set **allerede** (`extraction-schema.json`).
Tier 2 handler primært om at flytte få ting fra "ligger i prosa" til
"struktureret + gated" — fx dekorationer (kræver dekorations-nøgle fra anden
DAA-udgave) og evt. bopæl/uddannelse hvor de er stated nok.

---

## 3. Arkitektur: hvor de eager-udtrukne fakta bor

Skemaet bærer allerede det fulde evidenslag (`fact → assertion → citation →
conclusion`) og `load_daa.R` populerer det. Multi-source er indbygget
(N assertions per fact → `conclusion` vælger/markerer omstridt).

**Datastrøm (uændret form, rigere indhold):**

```
work/extracted/*.json   ← LLM-output (bredt katalog + proveniens-span)   [KANDIDAT-CACHE]
        │
        ▼  validate.py (deterministiske gates per fakta-type)
        │
   gatet delmængde
        │
        ▼  load_daa.R (truncate + reload, ~14s)
        │
   assertion + citation(citat_tekst) + conclusion   [DB — regenererbar]
```

- **`work/extracted/`-JSON er kandidat-cachen.** Bredt katalog + proveniens
  skrives ind i JSON'en. Ingen separat staging-tabel — JSON'en *er* staging.
- `validate.py` loader kun den **gatede delmængde** ind i `assertion`. Bredere
  katalog ⇒ bredere delmængde, vokser inkrementelt bag valideringsregler.
- `assertion`-uforanderlighed er **semantisk, ikke operationel**: DB regenereres
  frit fra JSON.

**Konsekvens — cachen skal bevares bevidst (se også §7/D):**
`work/extracted/` er i dag både `.gitignore`'d og `.claudeignore`'d → det dyre
aktiv behandles som disposabelt. Det durable LLM-output flyttes til et bevaret/
versioneret sted (fx tracked `data/extracted/` eller release-artefakt); ad-hoc
scripts/batches/reports forbliver disposable.

---

## 4. Forudsætning (tråd A): parse-styrkelse er gaten der gør eager-udtræk sikkert

Eager-udtræk hæver indsatsen på validering, fordi mere LLM-output betros til det
(semantisk) uforanderlige lag. Tre tiltag, i rækkefølge:

1. **Golden tests FØRST.** 30-50 svære poster (middelalder, flere ægteskaber,
   moderne lange poster, tvetydige børnelinks, relative datoer) med forventet
   JSON for centrale felter. Bygger regressionsnettet før parser/validator
   ændres. (Findes pt. ikke — `scripts/` har nul tests.)
2. **Deterministisk ægteskaber.** ~~Kopiér `derive_boern()`-mønstret fra
   `validate.py` til ægteskaber og overskriv LLM-feltet i `main()` præcis som
   børn.~~ **REVIDERET ved implementering (2026-06-18):** demoteret til
   *advisory-only*. Whole-branch-review fandt empirisk at ægteskabs-prosa er
   parentes-tæt (`(F.: …)`, citater, tredjeparts-remarriages) og IKKE regulær
   som børne-prosa — en regex-overskrivning korrumperede 74% af partnernavne
   (fx I-49 droppede rigtig ægtefælle, indsatte en tredjeparts remarriage).
   `derive_aegteskaber()` bevares, men driver kun R8-mismatch-flag; LLM-feltet
   er autoritativt for ægteskaber. Det målte tilbageværende miss er **4,1%
   dødsfakta** (24/591); ægteskaber forbliver LLM-udtrukket med advisory-flag.
3. **Mismatch-flag for slægtskab.** `validate.py` udleder forventede signaler
   fra prosaen (forventet antal ægteskaber, partnernavn til stede, fødsel/død,
   børneklausul) og flagger manglende udtræk til review. Slægtskabsfelter får
   højere krav end embeder/dekorationer, fordi de driver kernefunktionen
   ("er vi i familie?").

**Bevidst fravalgt fra Codex' forslag:** fuld intra-post grammatisk zoning
(post-niveau segmentering findes allerede i `segment.py`); separat
candidate-extraction-trin (overlapper §3's JSON-cache). Span-proveniens (Codex
#4) er IKKE fravalgt — det er Tier 1, og under fremtidssikrings-motivet er det
selve gevinsten.

---

## 5. Display: render-tid-prioritet, ikke gemt felt

- Visnings-rækkefølge udledes af **fakta-type ved render-tid** (fødsel/død/
  ægteskab/titel højt; embede-detaljer/dekorationer lavt; resten foldet væk).
- **Intet gemt `væsentlighed`-flag** — holder extraction/display ortogonale og
  undgår vedligehold. `person.visning_*`-cachen dækker allerede top-niveau.
- Alt udtrukket forbliver søgbart/filtrerbart uanset default-visning.
- "Extract alt (gated), vis væsentligt" er dermed løst uden ny persistens.

---

## 6. Multi-source: gevinsten er latent (capture-now / link-later)

- Skemaet bærer N-assertions-per-fact + `conclusion` ⇒ afstemning på tværs af
  udgaver *kan* lade sig gøre.
- **Men payoff er latent:** den kræver identitets-sammenkædning ("er person X i
  DAA-2012 = person Y i Særudgaven?"), som CLAUDE.md §9 eksplicit udskyder til
  efter PoC.
- Eager proveniens-fangst **nu** betyder data er *klar* den dag linking bygges.
  Det høster ikke afstemning i morgen. Oversælg det ikke som umiddelbar gevinst.
- Reconciliation virker kun over det **sammenlignelige strukturerede katalog**;
  fri prosa forbliver per-source `narrative` (vis side-om-side, afstem ikke
  strukturelt).

---

## 7. Uden for denne spec (håndteres separat)

| Tråd | Handling |
|---|---|
| **C — context-budget** | **Allerede løst** via `.claudeignore` (work/, work_presens/, node_modules, dist, pdf ekskluderet). Bekræft, ingen videre handling. |
| **D — repo-oprydning** | **Gøres direkte som separat opgave.** Nuance fra §3: bevar/versionér `work/extracted/` (durable LLM-output); smid ad-hoc scripts/batches/reports/dumps. Ikke "slet alt i work/". |

---

## 8. Eksplicit omkostning

Både proveniens-fangst (Tier 1) og katalog-udvidelse (Tier 2) kræver en **ny
LLM-extraction over alle 591 poster** (ændret prompt + `extraction-schema.json`).
~1 fuld kørsel. Bevidst beslutning, ikke bivirkning. Golden tests + deterministisk
ægteskaber (§4.1-4.2) kan laves *før* re-kørslen og beskytter den.

---

## 9. Åbne punkter til implementeringsplanen

1. Konkret span-granularitet i `citat_tekst`: ordret token, omgivende klausul,
   eller hel sætning? (Forslag: mindste klausul der indeholder ankeret.)
2. Hvilke Tier 2-typer (om nogen) tilføjes i første runde — eller venter alle
   til en dekorations-nøgle/behov findes?
3. Bevarings-sted for `work/extracted/`: tracked `data/extracted/` vs.
   release-artefakt vs. DB-dump i repo.
4. Verificér det reelle ægteskabs-miss-tal (måling, ikke antaget "~9%").
