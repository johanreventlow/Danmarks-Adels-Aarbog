# Stikprøve-audit: DAA 1939, baseline før re-segmentering

**Dato:** 2026-07-26 · **N = 25 hovedposter** · **Bedømt mod:** renderede sider fra
`Dansk Adels Aarbog - Reventlow 1939 stamtavle.pdf` (220 dpi, 24 sider) — **ikke** mod OCR-teksten,
så OCR-inducerede fejl ikke skjules bag deres eget input.
**Forudsætter:** [`kvalitetsvurdering-1939-vs-2018-20-2026-07-26.md`](kvalitetsvurdering-1939-vs-2018-20-2026-07-26.md)

Alle 25 poster er afdøde personer. De 7 `levende`-flagede 1939-poster er bevidst holdt ude af
stikprøven (invariant 8 — deres prosa må ikke sendes til en model).

---

## Metode

**Strata** (532 hovedposter efter fravalg af 7 levende):

| Stratum | Definition | Korpus | Stikprøve |
|---|---|---|---|
| S1 | Umatchet (ingen `samme_som`) | 111 | 9 |
| S2 | Matchet + narrativ-defektflag | 205 | 10 |
| S3 | Matchet, intet defektflag | 216 | 6 |

Udvalg deterministisk (`nr*7919 % 1009` inden for stratum) — reproducerbart, ikke cherry-picket.
Post→PDF-side fundet ved vindues-overlap mellem Calamari-narrativet og PDF'ens uafhængige
ABBYY-tekstlag (430/539 poster entydigt; de usikre i stikprøven verificeret manuelt).

**Taksonomi:** narrativ forkert person · fragment/indholdstab · hale-bleed · forældrelink helt
manglende · forældrelink kun far · dato forkert · dato upræcis · navn forkert · ægteskab forkert ·
OCR-fejl i bevaret tekst.

---

## Hovedresultat

| Mål | Ikke-vægtet (25) | **Korpus-estimat (vægtet)** |
|---|---|---|
| Poster med ≥1 **materiel** fejl | 17/25 | **~54 %** (bredt kriterium: ~62 %) |
| Narrativ med mindst én defekt | 16/25 | ~49 % |
| Narrativ med **reelt indholdstab** | 8/25 | ~23 % |
| Narrativ hører til **forkert person** | 1/25 | ~2 % (≈12 poster) |
| Forældrelink mangelfuldt (af poster hvor bogen angiver forældre) | 12/22 | **~51 %** |
| — heraf helt manglende | 9/22 | ~39 % |
| — heraf **kun far, mor mangler** | 3/22 | **~12 %** |
| **Forkert fødsels- eller dødsår** | **0/36 datofelter** | **~0 %** |
| Dato med tabt præcision (dag/måned i bogen, kun år i DB) | 2/36 | ~6 % |
| **Forkert navn** | **0/25** | **~0 %** |
| **Forkert ægtefælle** | **0/11** | **~0 %** |

CI er bred ved n=25 — tallene er størrelsesordener, ikke præcise rater. Retningen er entydig.

### Det vigtigste ved fordelingen

**Fejlene er næsten udelukkende *udeladelser og fejlklip*, ikke *forkerte påstande*.**
Ingen af de 25 poster havde et forkert navn, et forkert år eller en forkert ægtefælle. Det der
mangler eller er klippet forkert, er til gengæld udbredt. Data lyver ikke — de er ufuldstændige.

**Én undtagelse, og den er alvorlig:** post 13 (Sigfred) har fået **en anden persons narrativ**.
Teksten indeholder halen af Gotskalks post (`havde Gods i Gnissow og Katskrog, var død 1414`),
dernæst hele Henrik (Grove)s post, dernæst næste sektions-header. Sigfreds egen tekst
(`nævnes 1359 (s. o.), kvitterede i 1362 …`) findes slet ikke i basen. Det er den ene fejltype der
*ser autoritativ ud og er forkert* — `var død 1414` står nu på en person det ikke gælder.
Estimeret ~12 poster i korpuset.

---

## Fund der kun kan ses ved audit (ingen SQL kan finde dem)

1. **Mor mangler i ~12 % af posterne** (post 204, 402, 501). Bogens gruppeoverskrift navngiver
   begge forældre — `Landraad Henning Reventlows Børn af første Ægteskab m. Valentine von Vieregg` —
   men kun faderen blev linket. En strukturel forespørgsel ser et forældrelink og melder "OK".
   **Den strukturelle måling (184/539 uden link) undervurderer altså problemet.**

2. **Inkonsistent linking inden for samme kuld.** Post 455 (Charlotte Elisabeth Christiane) har
   intet forældrelink, mens dens søskende post 448 (Friedrich) har begge forældre — samme
   gruppeoverskrift, samme side. Det er ikke "bogen mangler data", det er ekstraktionen der springer.

3. **OCR-fejl i en kildehenvisning.** Post 79: DB har `(Aarb. LVIII, 108)`, bogen har
   `(Aarb. XLVIII, 108)` — bind 58 vs. 48. En læser der vil verificere, sendes til det forkerte bind.
   Samme klasse ses i post 86 (`XLVII1`, `1o5`). Kosmetiske OCR-rester (`Wul f`, `E11y`, `S. 44l`)
   er hyppigere men harmløse.

4. **Parser-hul: `druknede 28 Juli 1566`.** Post 534 har den præcise dato i `date_raw`, men
   `date_min/max` = hele 1566. Verbet foran datoen bryder parseren. Post 26 taber tilsvarende
   `mellem 22 og 28 Dec. 1779` → hele 1779.

5. **Defektflaget "kort narrativ" har falske positive.** Post 145 (`9. Povl Bertram, f. 1685 † 1686.`)
   er 32 tegn — og *fuldstændig korrekt*, fordi bogens post er så kort. 1/10 i S2-stratummet.
   Til gengæld var alle 6 S3-poster faktisk rene narrativer → flaget har god recall, men
   **"intet defektflag" betyder kun "narrativet er helt", ikke "posten er fejlfri"**: 2 af de 6
   manglede forældrelink.

---

## Hvor slemt er indholdstabet, konkret

De værste tilfælde mister hele biografien, fordi ankeret er fundet for langt inde i teksten:

- **Post 112 (Joachim Reventlow):** DB starter `1511 til Gram † 1519 Gift m. Abel Buchwald …`.
  Bogen har ~10 linjer før det: Rixdorf med landsbyerne Sellin, Küssow, Rastorf, Tramm; Gram og
  Steensgaard (solgt 1493); beseglede 1467; 1482—88 Amtmand i Flensborg; fik 1494 Runtoft i pant
  for 1000 Mark; ledsagede 1502 Hertug Frederik til Brandenborgs bryllup i Stendal. **Alt tabt.**
- **Post 125 (Bertram):** DB starter `1666. Gift. o. 1632 m. …`. Hele biografien (bøde 4000 Rdlr.
  til hertugen, hyldede 1648 Frederik III i Flensborg, m.v.) står på forrige bogside og mangler.
- **Post 59 (Detlev til Schmoel):** narrativet er et fragment der både starter inde i den
  *forrige* persons sætning (`døde barnløs 1732 og …`) og stopper midt i sin egen
  (`hvis Søn Geheimekonferensraad,`).
- **Post 79 (Abel):** mister sit eget dødssted (`† 1622 i Ekernförde`) og `g.`-markøren, så
  ægteskabet står som løsrevet tekst.
- **Post 534 (Knud):** mister navn + `var 1560—62 Hofsinde, tjente 1564 til Lands og`.

Til sammenligning er 9 af 25 narrativer **ordret korrekte og komplette** (post 26, 145, 178, 211,
244, 290, 389, 455, 488) — inklusive lange poster som 178 og 244. Pipelinen kan altså godt; den
fejler regulært, ikke tilfældigt.

---

## Per-post-facit

`✓` = verificeret korrekt mod bogen · `✗` = fejl · `–` = ikke relevant (bogen har det ikke)

| nr | str. | navn | fødsel | død | forældre | ægtefælle | narrativ | materiel fejl |
|---|---|---|---|---|---|---|---|---|
| 13 | S1 | ✓ | – | – | ✗ mangler | – | ✗✗ **forkert person** | **ja** |
| 26 | S1 | ✓ | ✓ | ✓ upræcis | – appendiks | – | ✓ ren | nej |
| 59 | S1 | ✓ | – | ✓ | ✗ mangler | – | ✗ fragment (begge ender) | **ja** |
| 79 | S2 | ✓ | – | ✓ | ✗ mangler | ✓ | ✗ head + bleed + OCR-kilde | **ja** |
| 92 | S1 | ✓ | – | ✓ | ✗ mangler | – | ✗ trunkeret v. sideskift | **ja** |
| 105 | S1 | ✓ | – | – | ✓ begge | – | ~ kun hale-bleed | nej |
| 112 | S1 | ✓ | – | ✓ | – stamfader | ✓ | ✗✗ ~10 linjer tabt | **ja** |
| 125 | S2 | ✓ | ✓ | ✓ | ✓ far | ✓ | ✗✗ hele biografien tabt | **ja** |
| 145 | S2 | ✓ | ✓ | ✓ | ✗ mangler | – | ✓ ren (flag = falsk pos.) | **ja** |
| 158 | S2 | ✓ | ✓ | ✓ | ✗ mangler | – | ✗ head tabt (+ dåb mangler) | **ja** |
| 178 | S3 | ✓ | ✓ | ✓ | ✓ begge | – | ✓ ren | **nej** |
| 204 | S2 | ✓ | ✓ | – | ~ kun far | – | ~ kun hale-bleed | ja (mor) |
| 211 | S3 | ✓ | ✓ | ✓ | ✗ mangler | ✓ | ✓ ren | **ja** |
| 224 | S2 | ✓ | – | ✓ | ✓ begge | ✓ | ~ kun hale-bleed | nej |
| 244 | S3 | ✓ | ✓ | ✓ | ✓ begge | ✓ | ✓ ren | **nej** |
| 290 | S1 | ✓ | – | ✓ | ✗ mangler | – | ✓ ren | ja (forældre) |
| 356 | S2 | ✓ | ✓ | ✓ | ✓ begge | ✓ | ~ navnelinje tabt | let |
| 369 | S2 | ✓ | ✓ | ✓ | ✓ begge | – | ~ head tabt midt i ord | let |
| 389 | S3 | ✓ | ✓ | ✓ | ✓ begge | ✓ | ✓ ren | **nej** |
| 402 | S2 | ✓ | ✓ | – | ~ kun far | ✓ | ~ head tabt midt i ord | ja (mor) |
| 455 | S3 | ✓ | ✓ | ✓ | ✗ mangler | – | ✓ ren | **ja** |
| 488 | S3 | ✓ | ✓ | ✓ | ✓ begge | – | ✓ ren | **nej** |
| 501 | S2 | ✓ | ✓ | ✓ | ~ kun far | ✓ | ~ hale-bleed | ja (mor) |
| 514 | S1 | ✓ | – | – | – stamfader | ✓ | ~ kun hale-bleed | nej |
| 534 | S1 | ✓ | – | ✓ upræcis | ✓ begge | – | ✗ head tabt | **ja** |

---

## Hvad auditen betyder for planen

1. **Bekræfter niveau 1 (re-segmentering) som rigtigt førstetrin.** Alle 16 narrativ-defekter er
   klip-fejl mod en OCR-tekst der *indeholder* det rigtige indhold — ikke manglende kildetekst.
   Hale-bleed og "start midt i sætning" er regulære og deterministisk løsbare.
2. **Hæver niveau 2 fra valgfrit til nødvendigt.** ~51 % mangelfulde forældrelink, hvoraf ~12 %
   er usynlige for enhver strukturel forespørgsel (mor mangler bag et gyldigt far-link). Samtidig
   viser post 455 vs. 448 at bogens data *er* der — det er ekstraktionen der springer.
3. **Niveau 3 (nye person-rækker) ser lille ud.** Ingen af de 25 poster var en dublet, en
   spøgelsesperson eller en sammenblanding af to personer. Post 13 er en *narrativ*-forveksling,
   ikke en person-forveksling — den rettes af niveau 1 uden at røre `person_id`, så matcharbejdet
   er ikke i fare. **Ingen fuld re-load indiceret af denne stikprøve.**
4. **Dato-hærdningen (A2) holder.** 0 forkerte år på 36 datofelter. To parser-huller fundet
   (`druknede <dato>`, `mellem <d1> og <d2> <måned> <år>`) — små, afgrænsede, testbare.
5. **Genbedøm de samme 25 efter re-segmenteringen.** Baseline er nu låst i tabellen ovenfor, så
   effekten kan måles som før/efter på identisk stikprøve, ikke som et nyt gæt.

---

## EFTER re-segmenteringen (samme dag, samme stikprøve)

Trin 1 er gennemført lokalt. Artefaktet er **ikke** skrevet til prod endnu.

### Ændringer i `segment_1939.py` (TDD, 28 → 40 tests grønne)

| Rettelse | Hvad den fikser |
|---|---|
| **Kuld-overskrifter som snitgrænse.** `group_header_starts()` genkender `Sjette Slægtled.`, `<Navn>s Børn m. <Navn>:` og `af første Ægteskab med …:` — også over flere linjer, hvor blokken samles baglæns fra kolon-linjen, og også når overskriften ender på punktum. | Hale-bleed |
| **Bar romertalslinje.** `STRUCTURAL_BOUNDARY_RE` krævede tekst efter markøren, så `III.` alene på en linje ikke var en grænse. | Gren-header midt i narrativet |
| **Bindestreger fjernes i normaliseringen** (symmetrisk i anker og råtekst). | Navne orddelt ved linjeskift (`Ana-\nstasia`) fandtes ikke → hovedet gik tabt |
| **`_post_number()` foretrækker `_orig_nr`.** `nr` er en GLOBAL tæller (1-539) i 1939-artefaktet, mens bogen nummererer lokalt (`4.`). Nummer-ankeret ledte altså efter `105.` hvor bogen skriver `4.` — reelt dødt for dette korpus. | Nummer-ankeret virker nu |
| **Snap-back til postens egen nummerlinje.** Ligger ankeret inde i posten, flyttes starten tilbage til den sidste nummerlinje før ankeret — kun hvis dens tal matcher bogens lokale nummer, så der pr. konstruktion ikke ligger en fremmed postgrænse imellem. | Manglende hoved |

Tre regressionsvagter blev skrevet *fordi* rettelserne er over-inklusive af natur:
prosalinje der ender på `:`, bogens krydshenvisning `— Børn:`, og prosa der nævner
`<Navn>s Børn` midt i en sætning. Alle tre består.

### Korpus-effekt (alle 539 poster)

| Defekt | Før | Efter | Δ |
|---|---|---|---|
| Starter midt i sætning | 91 | **22** | −69 |
| Gren-header inde i teksten | 33 | **2** | −31 |
| Slutter uden punktum (hale-bleed) | 153 | **71** | −82 |
| Under 60 tegn | 73 | 82 | +9 |
| **Union** | **280 (51,9 %)** | **159 (29,5 %)** | **−121 (−43 %)** |

216 af 539 narrativer ændret. Fordelingen af metoder blev bedre: gruppe-fallback 18 → 14,
nabo-fallback 7 → 4. **Pipelinens egen kvalitetsgate går fra rød til grøn**
(R1/R6-proxy 666/750 = 88,8 % → 684/750 = 91,2 %, krav ≥ 90 %) — værd at bemærke at
**artefaktet der ligger i prod i dag blev accepteret med fejlende gate.**

Stigningen i "under 60 tegn" er forventet og ufarlig: når en bleedet overskrift skæres af,
bliver en kort post kortere. Post 204 går fra 79 til 21 tegn — og 21 tegn er *hele* bogens post
(`8. Ulrik, f. o. 1608.`).

### Effekt på de 25 auditerede poster

**Narrativ-defekter i stikprøven: 16 → 5.**

| Status | Antal | Poster |
|---|---|---|
| **Rettet — nu ordret identisk med bogen** | **11** | 79, 105, 158, 204, 224, 356, 369, 402, 501, 514, 534 |
| Delvist (bleed væk, hoved mangler stadig) | 2 | 112, 125 |
| Uændret defekt | 3 | 13, 59, 92 |
| Var allerede rene | 9 | 26, 145, 178, 211, 244, 290, 389, 455, 488 |

Post 158 fik samtidig **et manglende faktum tilbage i prosaen**: `dbt. 18 Juli` var klippet væk
sammen med hovedet. Det er præcis den mekanisme der gør trin 1 til en forudsætning for trin 2.

### Hvad der stadig fejler, og hvorfor

- **Post 13 (forkert person)** er `gruppe-fallback` — der blev aldrig fundet et anker, så posten
  arver hele gruppens blok. Skal løses ved at indsnævre fallback-spannet, ikke ved bedre snit.
- **Post 59, 92, 112, 125** ligger i bogens *prosa-oversigtsafsnit*, hvor posterne ikke er
  nummereret (`_orig_nr` er `None` eller `A)`). Snap-back har intet at snappe til. Kræver
  understøttelse af bogstavmarkører (`A)`, `B)`) og af unummereret oversigtsprosa.
- **De 71 resterende hale-bleeds** er hovedsagelig to ting: ægte afskæring ved sideskift (posten
  fortsætter på næste side, uden for vinduets region) og falske positive (linjer der lovligt
  ender på `:`). Ingen af delene er header-bleed.

### Artefakter

- `work_1939_stamtavle/narrative_1939_calamari.PROD.json` — **det artefakt der ligger i prod**, taget som backup før genkørsel.
- `work_1939_stamtavle/narrative_1939_calamari.json` — nyt output (ikke deployet).
- Prod-patchen bygges som `patch[nr] = calamari[clean_1939[nr]._id]` — verificeret 539/539 mod den nuværende prod-tekst.

---

## Åbent

- **2018-20 er ikke auditeret** med denne harness. 25-30 poster med samme taksonomi mangler,
  ellers har vi ét målt estimat og ét anekdotisk (~1 % datofejl fra `plan-1939-produktionsklar.md`).
- **De 109 poster hvor post→PDF-side ikke kunne bestemmes entydigt** er ikke undersøgt for om
  usikkerheden i sig selv indikerer en defekt.
- Ægtefællers *egne* datoer er ikke verificeret — kun at den rigtige ægtefælle er knyttet.
