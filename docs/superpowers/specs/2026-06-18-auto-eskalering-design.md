# Auto-eskalering af flaggede udtræk — design

**Dato:** 2026-06-18
**Status:** Godkendt (brainstorm) — afventer implementeringsplan
**Bygger på:** parse-styrkelse + Tier 1-proveniens (`docs/superpowers/specs/2026-06-18-eager-udtraek-data-strategi-design.md`), nu merged til main.

---

## 1. Problem & motiv

Kvalitetskontrollen (`validate.py`) flagger poster hvor LLM-udtrækket fejler eller
er ufuldstændigt. I dag er reaktionen manuel: et menneske gen-kører flaggede
poster med en stærkere model (Opus) og flytter godkendte til `clean.json`.

Idéen: **automatisér løkken** — flaggede poster sendes automatisk til en stærkere
model, re-valideres, og dem der nu består loades; kun det der stadig fejler (plus
en diff-rapport til stikprøve) når et menneske.

**Hvorfor det virker:** to fejltyper har modsat redningsevne:
- **AI fandt på noget** (hallucination) — porten blokerer det allerede; en stærkere
  model finder bare på mindre.
- **AI missede noget der STÅR i teksten** (under-udtræk) — her redder en gen-kørsel
  med stærkere model ofte oplysningen. **Dette er hovedgevinsten.**

Bekræftet af parse-styrkelsen: Opus håndterer den parentes-tætte ægteskabs-prosa
markant bedre end den regex vi forkastede.

---

## 2. Besluttede rammer (brainstorm)

| Dimension | Beslutning |
|---|---|
| **Scope** | Blivende pipeline-feature i `/daa-extract`-skill'en (ikke engangs). Gælder alle fremtidige import. |
| **Trigger** | Begge typer: blokerende (review.json: R1-R7) OG recoverable misses (R8). |
| **Tilsyn** | Auto-load af eskalerede poster der nu består + diff-rapport til stikprøve. Menneske ser kun: poster der stadig fejler, + diff-rapporten hvis ønsket. |
| **Model** | Opus (allerede dokumenteret fallback i SKILL.md trin ③). |
| **Forsøg** | Bounded: ÉT eskalerings-forsøg per post. Stadig-fejlende → menneske. Ingen løkke (porten må ikke blive et mål modellen lærer at snyde). |
| **Placering** | Skill-integreret (kanonisk vej). Deterministisk plumbing i Python; LLM-trinnet agent-orkestreret. |

---

## 3. Kernebeslutning: worklist som interface, fyldt af udskiftelige detektorer

Triggeren hardcodes IKKE. `validate.py` bygger en **eskalerings-worklist** fra et
sæt detektorer. I dag fylder to den:

- **Blokerende** (R1-R7): opdigtet dato/span, struktur-brud, ugyldigt nr_range.
  Posten loader ikke.
- **Recoverable miss** (R8): prosa nævner død/ægteskab, intet udtrukket. Posten
  loader (R8 er advisory), men er ufuldstændig.

### Ærlig begrænsning — "forkert-felt" fanges IKKE (endnu)

Eksempel fra nuværende data: post I-5 (Iwan) fik `titel = "1248 (29. febr.)"` —
en dato i titel-feltet. Det er hverken blokeret (datoen STÅR i teksten → R1
består) eller manglende (R8 tier). Portene er blinde for "present-but-wrong-shape".

**Konsekvens:** featuren eskalerer i denne omgang IKKE den selvsikre-fejl-klasse.
Men fordi worklisten er et interface, kan en fremtidig **plausibilitets-detektor**
(fx "dato-formet streng i et ikke-dato-felt") tilføjes som ny detektor der fylder
worklisten — **uden at røre eskalerings-maskineriet**. Hullet er en *navngiven
udvidelse*, ikke en skjult mangel. Wires ikke i denne plan.

---

## 4. Arkitektur: testbart split

| Lag | Hvad | Testbart? |
|---|---|---|
| **Deterministisk Python** | worklist-generering, Sonnet-snapshot, re-validering, merge/promote, diff-rapport | Ja — golden-harness (`test_validate.py` + ny `test_escalate_merge.py`) |
| **LLM-trin (agent-drevet)** | Opus-subagent gen-udtrækker en flagget post | Nej — orkestreret af skill'en som det nuværende udtræk |

Samme split som resten af projektet (deterministisk kode = fejlfri & testet;
LLM-trin = agent-drevet).

---

## 5. Dataflow (ét bounded forsøg)

```
validate.py  → clean.json + review.json + escalation.json (NY worklist: {linje, nr, grunde[]})
   │
   ▼ trin ④b (SKILL.md, agent-drevet): for hver post i escalation.json
   │   1. snapshot Sonnet-output → work/extracted/<post>.sonnet.json   (FØR overskrivning)
   │   2. dispatch Opus-subagent m. posten + de konkrete grunde → overskriv work/extracted/<post>.json
   │
   ▼ escalate_merge.py (deterministisk):
   │   re-validér de eskalerede poster, så:
   │   ├─ består nu → merge ind i clean.json (auto-load) + stamp blaastemplet_af="Opus-escalated"
   │   ├─ stadig fejl → review.json (menneske)
   │   └─ diff-rapport: <post>.sonnet.json vs <post>.json pr. felt → work/escalation-diff.md
   │
   ▼ skill printer kort oversigt: "N eskaleret, M reddet, K stadig i review — se escalation-diff.md"
```

---

## 6. Komponenter

### 6.1 `validate.py` — emit worklist
- Nyt flag `--escalate escalation.json`.
- Worklisten = liste af `{linje, nr, nr_label, grunde: [...]}` hvor `grunde` samler
  både blokerende brud (R1-R7) og recoverable misses (R8) for posten.
- **Ændrer IKKE** clean/block-beslutningen: R8-poster står i *både* clean.json (de
  loader) og escalation.json (værd at prøve igen). Blokerede står i *både*
  review.json og escalation.json.
- Detektorerne struktureres så nye kan tilføjes uden at røre worklist-emit (jf. §3).

### 6.2 Ny `escalate_merge.py` — re-validér, merge, diff
Deterministisk. Tager: pre-eskalerings-snapshots (`*.sonnet.json`), post-eskalerings
extracted, posts-fil, eksisterende clean.json/review.json. Producerer opdateret
clean.json + review.json + diff-rapport. To merge-stier:
- **REPLACE:** R8-post findes allerede i clean.json (loadede) → opdatér eksisterende
  post med Opus-output.
- **APPEND:** blokeret post var ikke i clean.json → tilføj når den nu består.

### 6.3 `SKILL.md` — nyt trin ④b
Agent-orkestrering: for hver post i escalation.json, snapshot + dispatch Opus-subagent
(ét forsøg), kør derefter `escalate_merge.py`, overflad oversigten.

### 6.4 Proveniens-stempel
Eskalerede konklusioner stemples `blaastemplet_af = "Opus-escalated"` (felt findes i
`conclusion`-skemaet). Gør eskaleret data auditbar/søgbar — den reelle sikkerhed ved
auto-load given portenes blinde vinkler.

---

## 7. Test (golden-harness)

- **worklist-generering:** R8 + blokerende fylder worklisten; en ren post gør ikke.
- **REPLACE-sti:** R8-post i clean.json opdateres korrekt af Opus-output.
- **APPEND-sti:** blokeret post tilføjes til clean.json når den nu består.
- **Regressions-edge (kritisk):** Opus-output består R1-R7 men introducerer et *nyt*
  R8-miss → må IKKE promoveres blindt som forbedring (net-neutral/værre skal fanges).
- **snapshot-bevarelse:** `<post>.sonnet.json` skrives før overskrivning, så diffen
  har begge versioner under samme skema.

---

## 8. Payoff (ærligt)

- **I dag:** 24 R8-misses recoverable (målt). 0 blokerede på nuværende data (R7
  ikke aktiv endnu — gammel data har ingen `kilde_span`).
- **Ved Task 8** (re-kør m. `kilde_span`): R7 aktiveres → kan tilføje
  span-hallucinations-blokeringer; antal kendes først ved kørslen.
- **Durabel værdi:** fremtidige DAA-udgaver, andre slægter, andre kilder hvor
  Sonnet-default fejler mere. Investeringen betaler sig ved skala, ikke på PoC'en
  alene (samme logik som multi-source).

---

## 9. Uden for denne spec

- **Forkert-felt-detektor** (plausibilitet) — navngiven udvidelse (§3), wires ikke nu.
- **Standalone API-orkestrerings-script** (à la `work/extract_all.py`) — fravalgt;
  reintroducerer en model-kaldende kode-sti vi rydder ud, og duplikerer skill'ens
  prompt-logik. Skill-integreret er den kanoniske vej.
- **Selve Task 8-re-kørslen** — separat, bruger-gated (jf. parse-styrkelse-planen).
  Denne feature er KLAR til at bruges i den re-kørsel når den udføres.

---

## 10. Åbne punkter til implementeringsplanen

1. Format på `grunde[]` i escalation.json (regel-koder + kort tekst?).
2. Diff-rapportens granularitet (kun ændrede felter, eller fuld side-om-side?).
3. Hvordan Opus-subagentens prompt får "de konkrete grunde" med (genbrug
   extraction-prompt + tilføj "tidligere forsøg missede: …").
4. Bounded-retry-bogføring: hvordan markeres en post som "allerede eskaleret" så
   den ikke gen-eskaleres i en senere kørsel (idempotens).
