# Kalibrering — modeltier for DAA-udtræk

Afgør modelvalget på **evidens** frem for ræsonnement. Baggrund:
`docs/reviews/re-ekstraktion-forberedelse-2026-07-29.md` §Del 1.

## Hvorfor

Omkostningen ved at vælge forkert er et helt genudtræk. Omkostningen ved at
kalibrere er 30 kald pr. model. Den asymmetri afgør at kalibreringen skal køres.

Præcedens: `docs/decisions.md` → "Model-tier" afgjorde samme spørgsmål i juni og
målte at den laveste tier taber på klassifikations-nuancer. Det er dét resultat
kalibreringen skal be- eller afkræfte for GPT-tierne.

## Stratificering — valgt hvor det gik galt, ikke tilfældigt

| Stratum | Poster | Tester |
|---|---|---|
| **A_omtale** | 10 | `er_omtale`. **Facit er kendt uden bogopslag** — de 10 ER de gravsatte omtaler |
| **B_flere_aegteskaber** | 10 | ægtefælle-dekomponering, `ordinal_kilde` |
| **C_taet_biografi** | 10 | embede-vs-karriere, godser, `kilde_span` på lange tekster |

Fast frø (`20260729`), så udvalget er identisk ved gentagne kørsler og modeller
kan sammenlignes.

## Kørsel

```bash
# 1. Vælg poster (skriver til work/kalibrering/ — gitignoreret, PII)
python3 tools/kalibrering/vaelg-poster.py

# 2. Kør udtræk pr. model med den frosne prompt
#    (.claude/skills/daa-extract/references/extract-prompt.md).
#    Ét JSON-objekt pr. post → work/kalibrering/<model>/<kalibrering_id>.json
#    hvor ':' i id'et erstattes af '_'   (A_omtale:43 → A_omtale_43.json)

# 3. Scor
python3 tools/kalibrering/scor.py --udtraek work/kalibrering/terra \
    --batch work/kalibrering/batch.json --navn terra
python3 tools/kalibrering/scor.py --udtraek work/kalibrering/luna \
    --batch work/kalibrering/batch.json --navn luna
```

## Det menneskelige arbejde — holdt så småt som muligt

Første udgave bad om et facit for alle 30 poster, angivet med bare et løbenummer.
Det var ubrugeligt: man kunne ikke se hvem posten handlede om og skulle slå op i
årbogen for hver linje. To ting fjerner det arbejde.

**1. Prosaen står i arket — bogen skal ikke frem.**

```bash
python3 tools/kalibrering/lav-facitark.py   # → work/kalibrering/facitark.md
```

Kalibreringen tester om modellen udtrækker korrekt **fra en given tekst**, ikke
om OCR'en er rigtig. Teksten er derfor facit-grundlaget, og den har vi. Bogen
skal kun frem hvis man mistænker at teksten selv er forkert klippet.
Stratum A er forudfyldt (de ER omtalerne), så 20 af 30 kræver læsning.

**2. Kør begge modeller først — afgør kun hvor de er uenige.**

```bash
python3 tools/kalibrering/uenigheder.py --a work/kalibrering/terra --b work/kalibrering/luna
```

Er to modeller enige om en post, bidrager den intet til rangeringen — uanset om
begge har ret eller begge tager fejl. Kun uenighederne afgør hvilken model der er
bedst. Med to rimeligt gode modeller er det typisk en håndfuld poster frem for
tyve, og hver enkelt præsenteres med prosaen og de to svar side om side.

⚠ **Enighed er ikke sandhed.** To modeller kan dele samme fejl. Derfor scores
stratum A stadig mod sit kendte facit, og de enige poster stikprøves.

**Anbefalet rækkefølge:** kør begge modeller → se uenighederne → udfyld kun dem.
Facitarket er reserven, hvis uenighederne ikke rækker til en klar afgørelse.

Uden `--facit` scorer `scor.py` kun `er_omtale` for stratum A (som ikke kræver
bogopslag). Med `--facit work/kalibrering/facit.json` scores også ægtefælle-data,
embeder og godser.

## Hvad der scores — og hvorfor kun det

Kun de dimensioner der **faktisk fejlede** i 1939-udtrækket. En bred score ville
udvande netop de tal beslutningen skal hvile på.

| Mål | Hvorfor |
|---|---|
| `er_omtale` | Dyreste fejl: ~30 spøgelsespersoner der måtte slettes manuelt |
| `kilde_span` ordret | **Blokerende i pipelinen** (R7) — ikke-ordrette spans afvises |
| navn uden titel/gods | 112 navne var hele sætninger; sænker navnematch fra 0,86 til 0,54 |
| ægtefælle-data | Ægtefæller havde præcis ét faktum — navnet |
| `ordinal_kilde` / `koen_kilde` | Skøn skal kunne skelnes fra kildens udsagn |
| embeder / godser | 0 embeder, og 85 godser gemt i navnefeltet |

## Beslutningen

Skriv udfaldet i `docs/decisions.md` som den forrige model-tier-beslutning —
med tallene, ikke kun konklusionen.
