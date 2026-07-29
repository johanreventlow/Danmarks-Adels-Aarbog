# 1939-artefaktet afstemt med prod

**Dato:** 2026-07-29 · **Status:** udført · **Ingen prod-ændringer** (kun artefakt + pipeline-kode)

Forudsætning for alt nøglearbejde, jf. `docs/superpowers/plans/2026-07-29-aegtefaelle-forankring.md`
§6 trin 1: artefaktet og basen skal beskrive samme korpus, før nogen identitet mintes.

## Divergensen

| | |
|---|---|
| Poster i `linked_clean.json` / `clean_1939.json` | **539** |
| 1939-hovedposter i prod | **515** |
| Difference | **24** |

Alle 24 er gjort rede for — ingen uforklarede afvigelser:

- **23** slettet 2026-07-28 via dubletgennemgangen (`docs/reviews/dubletter-1939-2026-07-27.md`)
- **1** slettet manuelt 2026-07-27: `nr` 43 *Cay Friedrich til Altenhof*
  (`change_set` 629/630, `red_slet_person` på person 966)

`nr` 43 blev først antaget "aldrig loadet", fordi den manglede i det tidligste prod-dump. Det dump
var fra 28. juli — altså **efter** sletningen. `change_set`-journalen afgjorde spørgsmålet.
Posten er samme defekt-klasse som de øvrige: `_ctx.gruppe = "narrativ-kæde (Henning Reventlows
[VI.2] formodede efterslægt)"`, nabo til `nr` 42 og 44, der begge endte på slettelisten.

## Mekanikken: gravsten i artefaktet

Valgt frem for en separat eksklusionsliste, så begrundelsen aldrig kan komme væk fra posten.

```json
{ "_id": "…", "navn": "…", "fjernet": "dublet — oversigts-/prosaomtale; slettet i prod 2026-07-27/28" }
```

**Den kritiske detalje:** `nr` tildeles af en løbende tæller i `convert_all`. Springes en gravsten
over **før** optællingen, rykker alle efterfølgende poster ét ned — og prods eksisterende `nr` ville
pege på de forkerte personer. Tælleren tæller derfor gravstenen **med**; posten udelades kun fra
*output*:

```python
nr += 1
if rec.get("fjernet"):
    continue
```

## Verifikation

| Kontrol | Resultat |
|---|---|
| Poster ud af konverteren | **515** |
| `nr`-mængden mod prods `nr`-mængde | **identisk** |
| Poster med forælder-link, før → efter | **190 → 190** (uændret) |
| Poster med `boern`-range, før → efter | **51 → 51** (uændret) |
| Rapport-nøgler ændret af gravstenene | **ingen** |

Gravstenene rammer kun omtale-ghosts, som per konstruktion ingen kanter havde — derfor er
link-kvaliteten bit-identisk.

**Fem regressionstests** tilføjet til `test_convert_1939.py` (syntetiske poster, ingen PII):
udelades fra output · overlevende beholder `nr` · flere gravstene i træk · uændret adfærd uden
gravsten · `nr_label` følger `nr`.

## De 24 gravsatte `nr`

```
39, 41, 42, 43, 45, 46, 47, 48, 49, 50, 53, 56,
57, 58, 59, 60, 67, 92, 93, 95, 96, 97, 111, 175
```

Listen står her fordi artefakterne er gitignorerede (PII): går de tabt, kan gravstenene sættes igen
herfra. Ved en fremtidig **re-ekstraktion** er listen derimod ikke nok — da skal posterne
identificeres på ny mod identitetsregisteret (planens §4).

## Hvad der IKKE er gjort

- `validate.py` er kun udvidet med `fjernet` i `ALLOWED_TOP`. Der er **ingen regel** der kræver at
  en gravsten har en begrundelse, eller som advarer hvis antallet ændrer sig uventet.
- Gravstenene er sat i **begge** artefakter (`linked_clean.json`, `clean_1939.json`), men ingen af
  dem er under versionsstyring. Den eneste varige kopi af listen er dette dokument.
- Ingen genindlæsning er kørt. Afstemningen er verificeret ved at køre konverteren, ikke ved at
  loade mod en base.
