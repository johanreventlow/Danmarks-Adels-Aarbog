# Stikprøve-audit: DAA 2018-20

**Dato:** 2026-07-26 · **N = 28 hovedposter** · **Bedømt mod:**
`Dansk Adels Aarbog - Reventlow - Særudgave.pdf` (414 sider)
**Formål:** give 2018-20 samme målte tal som 1939, så de to udgaver kan sammenlignes —
i stedet for ét målt estimat og ét anekdotisk.
**Sammenlign med:** [`stikproeve-audit-1939-baseline-2026-07-26.md`](stikproeve-audit-1939-baseline-2026-07-26.md)

Alle 28 er afdøde personer; de 47 `levende`-flagede 2018-20-poster er holdt ude (invariant 8).

---

## Metodeforskel, og hvorfor den er forsvarlig

1939-auditen blev bevidst bedømt mod **renderede sideBILLEDER**, fordi kilden er en scannet
bog: at auditere udtrækket mod dets egen OCR-tekst ville systematisk skjule OCR-inducerede fejl.

Særudgaven er derimod en **digital InDesign-eksport** (`6116990-DAA 2018-20_saerudgave.indd`)
med ægte indlejret tekstlag — ikke OCR af et scan. Tekstlaget *er* bogens tekst. Sammenligning
mod det er derfor eksakt og ikke cirkulær. Stikprøven blev alligevel indledt med tre sider som
billeder (s. 116, 132, 145) for at bekræfte at tekstlaget svarer til det trykte; det gjorde det.

Strata som i 1939 (S1 umatchet 10 · S2 defektflag 10 · S3 ren 8), deterministisk udvalg,
poster lokaliseret ved normaliseret tekstsøgning over alle 415 sider.

---

## Resultat

| Mål | 2018-20 (N=28) | 1939 (N=25) |
|---|---|---|
| **Narrativ ordret identisk med bogen** | **27/28 = 96 %** | 9/25 = 36 % |
| Narrativ med defekt | **1/28** | 16/25 |
| Narrativ hører til forkert person | **0/28** | 1/25 |
| Forældrelink mangelfuldt | **0/27** | 12/22 |
| Forkert navn | 0/28 | 0/25 |
| Forkert fødsels-/dødsår | 0 | 0/36 felter |

**Brugerens vurdering holder: 2018-20 er markant bedre.** Og forskellen er strukturel, ikke
tilfældig — 2018-20 er udtrukket af en ren digital tekst, 1939 af OCR på et scan.

### Forældrelink — den største 1939-mangel findes ikke her

27 af 28 har **begge** forældre linket. Den 28. (I-13, Otte til Bliesdorf) har ingen — og bærer
i stedet faktatypen `forældre_ukendt` = *"ingen forbindelse angivet"*. Det er den ærlige
registrering, ikke en udeladelse.

Ingen far-uden-mor-tilfælde. Til sammenligning manglede moderen bag et gyldigt far-link i
~12 % af 1939-stikprøven. To konkrete personer optræder i begge udgaver og illustrerer det:

| Person | 1939 | 2018-20 |
|---|---|---|
| Marie Liane Mathilde (1939 nr 501 / 2018-20 IV-72) | kun far (`Georg Carl Ernst`) | **begge** (+ `Ida Pauline Klementine von Gruben`) |
| Charlotta Amalia (1939 nr 277 / 2018-20 V-5) | forkert bundet post | **begge** (`Conrad` + `Anna Margaretha Gabel`) |

### Den ene defekt

**IV-72 (Komtesse Marie Liane Mathilde)** — narrativet er ordret korrekt, men har
`Sjette (nittende) slægtled` hængende på halen. Bogens post slutter ved
`… Gertrud Elisabeth Sandegren, * 18. okt. 1896 i Uddevalla, † ...)`.

Samme fejlklasse som 1939's hale-bleed, blot langt sjældnere. Den er **tællelig korpus-bredt**:

| Prædikat | 2018-20 (591) | 1939 (539, efter re-segmentering) |
|---|---|---|
| Starter midt i sætning | **2** | 22 |
| Slutter uden punktum | **33** | 71 |
| — heraf slutter på `…slægtled` | **14** | 0 |
| Under 60 tegn | 70 | 82 |
| Union (uden "kort") | **34 = 5,8 %** | 85 = 15,8 % |

De **14 poster der ender på `…slægtled`** er den konkrete, afgrænsede oprydning i 2018-20:
en trailing sektionsoverskrift skal skæres af. Rent narrativ-lag, samme form som 1939-patchen
— ingen personer, ingen links.

**Alle 14 er verificeret som ægte bleeds**, ikke afkortede krydshenvisninger. Skelnen er
entydig, og det er den regel en oprydning skal bruge:

- **Legitim krydshenvisning** slutter med en reference: `– 6 børn: Syvende (attende) slægtled, V, nr. 119‑124.`
- **Bleed** er en bar overskrift uden reference, klistret på efter postens egen sidste sætning:
  `… i Itzehoe Adelige Kloster. Tredje (sekstende) slægtled`

To af de 14 (V-44, V-156) indeholder *begge* — først en gyldig krydshenvisning midt i teksten,
derefter den bare overskrift til sidst. Et snit må derfor kun fjerne den afsluttende bare form.

⚠️ Mindst én af de 14 er en nulevende person. En oprydning skal køre gennem samme
`levende`-disciplin som al anden 1939/2018-20-behandling (invariant 8) — ingen prosa om
levende personer sendes til en model.

Bemærk at "under 60 tegn" er et dårligt prædikat i **begge** udgaver: bogen har mange poster
der legitimt er korte (`Detlef – * 1677, † 1678.`, `David – † før faderen.`). 4 af de 10
S2-poster i denne stikprøve var falske positive af netop den grund.

---

## Per-post-facit

`✓` = ordret identisk med bogen

| linje-nr | stratum | narrativ | forældre | linje-nr | stratum | narrativ | forældre |
|---|---|---|---|---|---|---|---|
| I-13 | S1 | ✓ | `forældre_ukendt` (korrekt) | III-85 | S2 | ✓ | begge |
| I-26 | S1 | ✓ | begge | III-105 | S2 | ✓ | begge |
| II-26 | S1 | ✓ | begge | IV-72 | S2 | ✗ hale-bleed | begge |
| III-13 | S1 | ✓ | begge | V-5 | S2 | ✓ | begge |
| III-26 | S1 | ✓ | begge | V-13 | S2 | ✓ | begge |
| III-46 | S1 | ✓ | begge | V-19 | S2 | ✓ | begge |
| IV-79 | S1 | ✓ | begge | I-46 | S3 | ✓ | begge |
| V-46 | S1 | ✓ | begge | I-79 | S3 | ✓ | begge |
| V-72 | S1 | ✓ | begge | I-112 | S3 | ✓ | begge |
| V-105 | S1 | ✓ | begge | III-79 | S3 | ✓ | begge |
| I-111 | S2 | ✓ | begge | III-112 | S3 | ✓ | begge |
| I-117 | S2 | ✓ | begge | V-79 | S3 | ✓ | begge |
| III-25 | S2 | ✓ | begge | V-112 | S3 | ✓ | begge |
| III-65 | S2 | ✓ | begge | V-145 | S3 | ✓ | begge |

---

## Konklusion

**2018-20 skal ikke laves om.** De to kendte mangler er små og afgrænsede:

1. **14 narrativer med trailing sektionsoverskrift** — mekanisk oprydning i narrativ-laget.
2. **16,4 % uparsede datoer** (331/2024 rå datoer) mod 1939's 7,8 % — det eneste sted hvor
   1939 er bedre. Sandsynligvis relative former (`s.å.`/`s.m.`), som bevidst blev sprunget over
   i A2. Bemærk at 2018-20's datoer er *rigere* (dag-præcision hvor 1939 ofte kun har år), så
   der er mere at parse og fejle på.

## Forbehold

- N=28 giver bred CI. Ved 27/28 korrekte er den reelle rate et sted omkring 85-99 % — retningen
  er entydig, det præcise tal er det ikke.
- Ægtefællers *egne* datoer er ikke verificeret, kun at den rigtige ægtefælle er knyttet.
- Forældrelink er verificeret mod bogens gruppeoverskrift for de poster hvor overskriften stod
  på samme side; for de øvrige er navnematchet vurderet som plausibelt, ikke bekræftet.
