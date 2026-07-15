# Divergens-rapport: DAA 1939-stamtavle vs. DAA 2018-20 (indlæst)

**Dato:** 2026-07-15
**Formål:** Kortlægge de konkrete "afvigende sandheder" mellem den ældre Reventlow-stamtavle
(DAA 1939, Louis Bobé) og den nyere (DAA 2018-20, indlæst i modellen) — som testkorpus for
**Problem 2** (konkurrerende slægtskabspåstande på `family_member`,
`docs/superpowers/specs/2026-07-15-family-member-konkurrerende-relationer-design.md`) og som
ekstra kalibreringsdata for **Problem 3** (tværudgave-matching, navnefoldning).
**Status:** Kortlægning — ikke indkodet. Afventer Problem 2-implementering.

## Metode & kilder

Udgave-vs-udgave-sammenligning af de to trykte kilders **tekst** (prod-fri, ingen DB-adgang):
- **1939:** `Dansk Adels Aarbog - Reventlow 1939.pdf`, stamtavle-sektion fysisk s. 490-598
  (Reventlow-delen). Indledningens strukturræsonnement: fysisk s. 493.
- **2018-20:** `Dansk Adels Aarbog - Reventlow - Særudgave.pdf` (414 s.) — den udgave der er
  **indlæst** som modellens ~922 personer.

**Caveat (advisor):** Særudgave-PDF'en er 2018-20-*udgaven*; den indlæste DB er den udgave
*plus vores rettelser* (spøgelses-unioner, multi-union, flere-forældre — [[flere-foraeldre-datafix]]).
Udgave-vs-udgave er den reneste "afvigende sandheder"-sammenligning, men ved indkodning som
konkurrerende assertions skal der gen-tjekkes mod de loadede **konklusioner**, ikke rå-PDF'en.

**Afgrænsning (hvad tæller som divergens):** samme kryds-identificerede forhold med en
*modstridende* påstand. Ekskluderet som støj: OCR-forskelle (1939 er scannet), ren dæknings-
forskel (fravær ≠ modstrid), og historiker-spekulation om personer der ikke er i modellen.

---

## Divergens 1 — De tidligste slægtled: fælles stamfar for holstenske og meklenborgske linje

**Type:** forældreskab/oprindelse (tidlig-middelalderlig, ~1220-1300).

### 1939's påstand (Bobé), fysisk s. 493
> "Da Stamfadrene til Linje I og II, **Gotskalk** og **Ditlev**, der levede samtidigt (o. 1250),
> hver havde en Søn **Hartvig** … er det **sandsynligt, at Gotskalk og Ditlev har været Brødre
> og Sønner af en Hartvig**."

Altså: en **hypotetisk fælles fader Hartvig**, der gør Gotskalk (stamfar, holstenske Linje I) og
Ditlev (stamfar, meklenborgske Linje II) til brødre — en spekulativ sammenknytning af de to
hovedlinjers udspring, hedget med "sandsynligt".

### 2018-20's påstand (Hau), særudgave-linje 280 ff.
> "Den første i kilderne **efterviselige** Reventlow i Holsten er ridderen **Gottschalk von
> Reventlow (-1223-1247-) (I, 1)** …"

2018-20 grunder linjen i den **kildemæssigt beviselige** Gottschalk (I,1), uden den hypotetiske
Hartvig-fader og bror-relation. Linje-strukturen er reorganiseret (I,1 / I,29 / II,1), og to
Gottschalk'er (holstensk -1359-1384- og meklenborgsk -1393-) foreslås endda at være **samme
person** (linje 400-406) — en identifikation 1939 ikke har.

### Konsekvens for Problem 2
- Divergensen ligger i **de nærmeste 2-3 stamfader-generationer** (præcis brugerens beskrivelse).
- **Åbent spørgsmål (skal verificeres før indkodning):** er disse middelalder-stamfædre
  overhovedet i de indlæste 922? Hvis 2018-20-loadet kun tog de dokumenterede grevelige linjer
  fra 1673/1767 og frem, er Hartvig-hypotesen historiker-spekulation *uden for* modellen — og
  dermed ikke Problem 2 v1-materiale (som er scopet til `barn`-slottet for personer i grafen).
- Hvis stamfædrene ER i modellen: dette er en ægte konkurrerende `forældrefamilie`-påstand
  (1939: Gotskalk/Ditlev = børn af Hartvig; 2018-20: ingen sådan fader) → `red_tilfoej_foraeldre_paastand`.

---

## Divergens 2 — Den fynske Linje: medlemskab af slægten

**Type:** medlemskab/identitet (om en hel linje tilhører familien).

### 1939's påstand (Bobé), fysisk s. 493 + 593
1939 medtager **"Den fyenske Linje" (IV)** som en Reventlow-linje (stamfar **Henrik Jensen, 1358**,
på Søbo/Als; fører Reventlow-murtinden men et *andet* hjelmtegn). Bobé er dog selv usikker:
> "… vides de at have regnet sig som hørende til Slægten Reventlow, men **om den fyenske Linjes
> Samhørighed** med de holstenske og meklenborgske Reventlower **kan intet oplyses**."

### 2018-20's påstand (Hau-forskning), særudgave-linje 15596 ff.
> "I stamtavlen … DAA 1939 har **Louis Bobé** ladet den såkaldte Fynske linje være en del af den
> tyske slægt. **Christian Hau har påvist** … at denne fåtallige nordjyske lavadelsslægt, hvis
> stamfar er **Henrik Jensen (-1358-), IKKE hører til** den tyske slægt von Reventlow. … Denne
> slægt er derimod agnatisk beslægtet med … Daa, Galskyt og (mur-)Kaas. Hvad der har fået Louis
> Bobé til at medtage denne slægt … er **uforståeligt**. Allerede **Anders Thiset** antog i sin
> Reventlow-tavle i **DAA 1893** … at der er tale om to forskellige slægter."

Altså: **fuld udeladelse i 2018-20**, begrundet med ny forskning (Hau 2016) — de fynske er en
selvstændig nordjysk lavadelsslægt, der kun lånte Reventlow-navnet pga. våbenlighed; uddøde med
Knud Andersen († 1560).

### Konsekvens for Problem 2
- Dette er en **udgave-konflikt om medlemskab**, ikke et klassisk `barn`-slot-forældreskab. 1939
  hævder Henrik Jensen-linjen ER Reventlow; 2018-20 (+ allerede DAA 1893/Thiset) afviser det.
- **Design-spørgsmål for Problem 2:** passer et medlemskabs-afvisning i v1's `forældrefamilie`-slot,
  eller er det en bredere "hører denne person/linje til slægten"-påstand? Muligvis et rent
  `ikke_samme_som`/eksklusions-scenarie snarere end konkurrerende `family_member`. **Flag til
  Problem 2-spec-revision.**
- Dette er også en **tri-udgave-konvergens**: DAA 1893 (Thiset, afvist) → 1939 (Bobé, medtaget) →
  2018-20 (Hau, afvist) — udgaver retter både frem OG tilbage (jf. Problem 2 §6: "nyeste vinder"
  er fravalgt netop derfor).

---

## Bonus: Problem 3-kalibrering — observerede stavevarianter (facit)

Sammenligningen afdækkede konkrete stave-/ortografi-varianter som navnefoldnings-kernen
(`matchUdgaver` + `navnevarianter.ts`, Problem 3 §3.2) skal normalisere:

| 1939 | 2018-20 / 2012-14 | Regel |
|---|---|---|
| Gotskalk | Gottschalk | `sk`↔`sch`, dobbeltkonsonant (variant-tabel) |
| Ditlev | Detlef | kendt DAA-variant (variant-tabel) |
| Reventlou | Reventlow | `u`↔`w` ord-finalt |
| Fyenske | Fynske | vokal-variant |
| Comtesse | Komtesse | `c`→`k` foran o |
| Benedicta | Benedicte | ord-finalt `a→e` |

Plus de 8 eksakte fødselsdato-match fra præsensliste-udtrækkene (se `work_presens*/`).

---

## Næste skridt

1. **Verificér (kræver DB-læsning):** er de tidlige stamfædre (Gotskalk/Ditlev/Hartvig) og den
   fynske linje i de indlæste 922? Afgør om Divergens 1/2 er Problem 2 v1-materiale eller uden for
   modellen.
2. **Problem 2-spec-input:** Divergens 2 (medlemskab) passer muligvis ikke i `barn`-slot-scopet —
   overvej om der skal et eksklusions-/medlemskabs-mønster til (adjacent til `ikke_samme_som`).
3. Ingen indkodning før Problem 2-implementering (roadmap-rækkefølge: Leverance 0 → Problem 3 →
   Problem 2/1).

## Kilder
- `Dansk Adels Aarbog - Reventlow 1939.pdf` fysisk s. 493 (indledning), s. 593 (fynske linje)
- `Dansk Adels Aarbog - Reventlow - Særudgave.pdf` linje 280 ff. (oprindelse), 15596 ff. (fynske afvisning)
- `docs/flere-daa-udgaver-roadmap.md` (Problem 2)
