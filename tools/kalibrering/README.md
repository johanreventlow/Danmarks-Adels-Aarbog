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

Uden `--facit` scores kun `er_omtale` for stratum A (som ikke kræver bogopslag).
Med `--facit work/kalibrering/facit.json` scores også ægtefælle-data, embeder og
godser mod menneskeligt facit — udfyld `facit-skabelon.json` mens du læser bogen.

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
