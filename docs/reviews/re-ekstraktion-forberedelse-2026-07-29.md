# Re-ekstraktion af DAA 1939 — forberedelse

**Dato:** 2026-07-29 · **Status:** forberedelse, ikke påbegyndt
**Formål:** afgøre modelvalg og fastlægge hvad der SKAL udtrækkes, så vi undgår flere genudtræk.

## Del 1 — Modelvalg

### Hvad LLM-trinnet faktisk laver

Kun **ét** af pipelinens fem trin bruger en model (`SKILL.md` ③). Alt andet er deterministisk:

| | |
|---|---|
| Narrativen | **ikke** LLM — prosaen klippes ordret af `segment.py` |
| `boern` | **ikke** LLM — parses deterministisk; LLM missede den systematisk |
| `date_min`/`date_max` | **ikke** LLM — udledes af `date_raw` i trin ④ |
| `record_key` | **ikke** LLM — kommer nu fra identitetsregisteret |
| **Struktureret rygrad pr. post** | ← modellens eneste opgave |

Konteksten er **én post ad gangen**. Det er ikke en lang-kontekst-opgave; det er mange små,
skema-bundne opgaver med to hårde krav: `date_raw` og `kilde_span` skal stå **ordret** i prosaen
(R7 fejler ellers), og klassifikationen skal ramme rigtigt.

### Præcedens der peger direkte på svaret

`docs/decisions.md` (2026-06-16) afgjorde samme spørgsmål for Claude-tierne:

> Sonnet til stamtavle-udtræk (klarer tredjeparts-fælder, dense biografier). Haiku testet: rammer
> genealogisk rygrad tæt, men **taber på klassifikations-nuancer (karriere vs embede)** og er flakier.

Det er ikke et generelt "større er bedre". Det er en **målt** observation om præcis den dimension
denne opgave er svær på: at skelne hvad der er rygrad fra hvad der er biografisk staffage.

### Anbefaling

**`gpt-5.6-terra` på max effort.**

- Opgavens hårde del er *klassifikation*, ikke volumen eller lang kontekst — og det er netop dér den
  billige tier målt tabte sidst.
- **Frarådes: `luna`.** Ikke fordi den er svag, men fordi projektet allerede har målt at
  tilsvarende tier fejler på denne ene dimension. At gentage forsøget uden ny information ville være
  at genopdage et kendt resultat.
- **`sol` er formentlig overkill** til langt de fleste poster — men se eskalering nedenfor.

### Eskalering frem for ét valg

Pipelinen har allerede et to-tier-mønster (`escalate_merge.py`, "Opus-eskalering af flaggede").
Genbrug det:

```
terra (max effort)  →  alle poster
   ↓ flagget af valideringen (R1-R8, lav faktatæthed, tvetydig klassifikation)
sol (max effort)    →  kun de flaggede
```

Det holder omkostningen nede uden at ofre de svære poster — og "flagget" er allerede defineret af
den eksisterende validering, så der skal ikke opfindes et nyt kriterium.

### Afgør det med en kalibrering, ikke med et gæt

`facit_1939.py` findes allerede og rapporterer **kun tal** (PII-disciplin). Kør derfor:

1. Vælg ~30 poster stratificeret: 10 tætte biografier · 10 med flere ægteskaber · 10 fra
   oversigtsprosaen (hvor fejlen skete sidst).
2. Udtræk med **terra max** og **luna max** mod samme prompt.
3. Scor mod et håndlavet facit på de dimensioner der fejlede: er posten en person eller en omtale ·
   er ægtefællen dekomponeret · er `date_raw` ordret · rammer titel-vs-embede.
4. Vælg på evidens. Beslutningen skrives i `docs/decisions.md` som den forrige.

**Omkostningen ved kalibreringen er ~30 kald.** Omkostningen ved at vælge forkert er et helt
genudtræk — det er den asymmetri der afgør at kalibreringen skal køres.

---

## Del 2 — Hvad SKAL udtrækkes (målt mangel, ikke ønskeliste)

Målt mod prod 2026-07-29. Sammenligningsgrundlaget er DAA 2018-20, som er udtrukket med den
nuværende kontrakt og fungerer.

### K1 — Faktatyper 1939 slet ikke har

| Faktatype | 2018-20 | **1939** |
|---|---|---|
| dåb | 237 | **0** |
| dekoration | 131 | **0** |
| floruit | 105 | **0** |
| dødsårsag | 21 | **0** |
| klosterindgang | 8 | **0** |
| tilnavn | 5 | **0** |
| adling | 4 | **0** |
| overhoved | 4 | **0** |

Otte typer, nul forekomster. Bogen fra 1939 *indeholder* dåbsdatoer og dekorationer — de blev bare
ikke udtrukket. **Kontrakten skal kræve dem eksplicit**, ikke bare tillade dem.

### K2 — Embeder og hverv: 1939 har ingen

```
personer med embede-relation:   2018-20: 150      1939: 0
```

506 embede-relationer i alt, **ingen** fra 1939. Det er den største enkeltmangel, og den rammer
netop de personer bogen skriver mest om.

### K3 — Ægtefæller: kun et navn

```
snit fakta pr. ægtefælle:   2018-20: 2,62      1939: 1,00
                            (fødsel 237/331)   (fødsel 0/296)
```

1939-ægtefæller har **præcis ét faktum** — navnet. Ingen datoer, intet køn, ingen steder. 2018-20
viser at det kan lade sig gøre. Se også omtale-journal-planen: ægtefællens felter skal kunne rettes,
og det forudsætter at de findes.

### K4 — Køn

625 personer uden `koen`, alle ægtefæller. Kontrakten skal kræve køn på **enhver** navngiven person,
også dem der kun optræder i en ægteskabsklausul.

### K5 — Navne må ikke være sætninger

112 af 604 ægtefæller (18,5 %) har gods, titel eller parentes inde i navnefeltet:

> `General af Infanteriet, Guvernør i Kbhvn. Nicolai Maximilian Friherre Gersdorff til Baroniet Marselisborg og Gross-Nordsee`

Navn · titel · gods er **tre** felter. Målt konsekvens: et titel-præfiks sænker
navnesammenligningen fra ~0,86 til 0,54 og forhindrer tværudgave-match.

### K6 — Godser som relationer, ikke som tekst

85 ægtefæller har gods i navnet og **nul** godsrelationer. Af de godser: 25 findes allerede i
`estate`, 33 delvist, **52 kendes slet ikke**. Bogen navngiver dem; udtrækket taber dem.

### K7 — Steder

864 steder findes, men kun **3 har koordinater**. Kontrakten bør kræve stednavnet ordret som skrevet
(så det kan geokodes senere) — ikke normaliseret af modellen.

### K8 — Hændelser: laget er tomt

`haendelse`-tabellen har **0 rækker** for begge udgaver. Formidlingslaget er bygget, men aldrig
fyldt. Det er et selvstændigt LLM-pass (`/daa-haendelser`) og hører ikke nødvendigvis i denne
re-ekstraktion — men beslutningen bør tages bevidst, ikke ved forglemmelse.

### K9 — Omtaler må ikke blive personer

Den dyreste fejl sidst: oversigtsprosa gav ~30 spøgelsesposter. Modellen *så* det selv — den
skrev `_ctx.gruppe = "narrativ-kæde (…)"`. **Kontrakten skal kræve et eksplicit felt**
(`er_omtale: true`) frem for at lade det ligge i en fritekst-etiket, så valideringen kan gate på
det i stedet for at nogen skal opdage det bagefter.

### K10 — Modellen skal deklarere sin egen usikkerhed

Hvor et felt beror på modellens skøn frem for bogens ord, skal det fremgå:

- `ordinal_kilde: "bog" | "udledt"` — bogen skriver `1°/2°` eller vi tæller
- `koen_kilde: "bog" | "udledt"` — står der "datteren", eller gætter vi på fornavnet

Så kan fail-closed-gates bygges på det. Uden det kan vi ikke skelne et faktum fra et skøn — og det
var præcis dét der gjorde ægteskabsnummeret ubrugeligt som nøgle.

---

## Del 3 — Rækkefølge

1. **Opdatér kontrakten** (`extraction-schema.json` + `extract-prompt.md`) med K1-K10. Bump
   `prompt-version`, så kørsler kan sammenlignes.
2. **Kalibrér** (Del 1) på ~30 stratificerede poster. Skriv beslutningen i `decisions.md`.
3. **Kør fuldt udtræk** med den valgte model + eskalering.
4. **Afstem mod identitetsregisteret** — `reconcile()` afgør hvilke poster der er de samme.
   Tvetydige stopper fail-closed og kræver menneskelig afgørelse.
5. **Load** — record_key følger med fra registeret, så de 613 match overlever.

## Åbne forbehold

- `reconcile()` er unit-testet, men **aldrig kørt mod et rigtigt nyt udtræk**. Trin 4 er det første
  virkelige møde med den funktion, og den bør køres i tørløb først.
- Kalibreringen forudsætter et håndlavet facit for ~30 poster. Det er manuelt arbejde mod bogen og
  bør laves af en der kan læse gotisk sats.
- K8 (hændelser) er medtaget som beslutning, ikke som krav.
