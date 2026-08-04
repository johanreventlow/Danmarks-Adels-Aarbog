# 1939 evidence-pilot — kontrakt-audit

Status: **NO-GO for 1939-A**. Den historiske Terra-kørsel kan reproduceres og
valideres strukturelt i et privat, ignoreret arbejdsområde, men den opfylder
ikke endnu den fælles, profilbundne source-record-kontrakt fra Task 13–14.
Den må derfor ikke tælle som en 1939-pilot eller som grundlag for projektion.

## Frosne input og lokal reproduktion

| Input/artefakt | SHA-256 |
|---|---|
| `Dansk Adels Aarbog - Reventlow 1939.pdf` | `5711975512a2b14a2ce49eee404cc9796c9020343ca67d64b99606035deba0b7` |
| `work_1939_stamtavle/raw.txt` | `efab316b528eafc60074c21c877590b31ab8e960cd1adc14f5c79bf01f12dab7` |
| `full_ocr_calamari_r6_clean.txt` | `020123a3588dacf80705a22fb021ab4f5da97b8de202e8664304ca01f9a6da37` |
| Lokalt, genereret `clean_1939_v3.json` | `c68ace8bffd8d653c4af0aa24586c5c01c3d1f267efe74d546ddddd964b3551b` |

Rendition-beslutningen fra Task 18 fastholdes: Calamari-renditionen er den
frosne arbejdsrendition, rå OCR bevares, og PDF-siden er visuel autoritet ved
tvivl. Den relevante stamtavle ligger på PDF-sider 496–598.

Den eksisterende kørsel blev kopieret til et nyt ignoreret arbejdsområde og
valideret dér, så dens retry-log og andre brugerartefakter ikke blev ændret.
`efterudtraek_1939.py check`, `merge` og `verify` gav:

| Måling | Resultat |
|---|---:|
| Output-batches / records | 22 / 546 |
| Unikke, ikke-tomme `record_key` | 546 / 546 |
| Endeligt afviste valideringsforhold | 0 |
| Retry-kø efter check | 0 |
| Forsøg / retries | 58 / 36 |
| Genbrugte karantæne-batches / friske Terra-batches | 10 / 12 |
| Bevarede legacy-proveniensforhold | 606 |
| Accepterede / afviste nye unions | 17 / 3 |

Faktaændringerne blev kun kontrolleret i det private artefakt: 1.099 nye,
947 erstattede og 110 bevarede facts. 142 ægteskabsidentitetskonflikter og 157
ægteskabsfeltkonflikter blev ikke promoveret som identitetsbeslutninger af
denne audit.

## Stratificeret audit og mangler

Det validerede historiske artefakt dækker 546 **coverage-records** på sider
496–598: 505 nummererede poster, 23 stamfædre og 25 oversigtsposter, minus
syv eksplicitte oversigtsdubletter. Det er derfor forkert at omtale alle 546
som nummererede personer. Artefaktet indeholder bl.a. 208 records i 64
normaliserede navnedubletgrupper, 38 med
flere ægteskaber, 81 med børnehenvisning, seks lange narrativer og 39 usikre
records. Det er brugbare kandidatstrata for en ny fælleskontraktkørsel.

Men batch-inputtet har kun `batch_id` og person-`records`; det har ingen
profilsignatur, rendition-/inputhash eller source-record-manifest. Det
indeholder heller ingen segmenterede linjeoverskrifter, slægtsbeskrivelser,
våbenbeskrivelser eller andre non-person records. Auditkravene om
record-continuity for sådanne strukturer, placement-roller og sammenligning
med 2018's nye profil kan derfor ikke verificeres. `record_key` i det gamle
artefakt er en stabil historisk identitet, men er ikke bevis for en ny,
profile-pinned source-record-accept.

## Igangværende ankerbaseret rekonstruktion

Den nye, deterministiske Calamari-vej er stadig **NO-GO**, men har en
afgrænset, testet forbedring: den genfinder 502 nummererede kandidater mod de
tidligere 483. De tre resterende korte kandidatlinjer forbliver bevidst
afvist, indtil de har en eksplicit rå-structure-bro og PDF-side. Linje-,
stamfader- og oversigtsstrukturen er endnu ikke genoprettet fra Calamari og må
derfor ikke projekteres eller bruges som identitet.

En privat review-template med alle 546 baseline-record-keys er oprettet med
review-status unreviewed. Den indeholder ingen kandidat, accept,
dubletafgørelse eller menneskearksbeslutning og er ikke et coverage-resultat.
Den næste menneskelige gennemgang skal udfylde sådanne beslutninger med
positive ankre; der må ikke genereres dem ud fra navn, nummer eller tekstlig
lighed.

En accepteret bro kræver nu både eksakt Calamari-udsnit og eksakt rå-OCR-
udsnit med koordinater, ordret råtekst og SHA-256 for selve udsnittet. Den
canonical coverage bevarer rå-koordinater og udsnitshash, mens filhashen
fortsat binder hele rå-OCR-kilden. Uafklarede poster kan stadig valideres som
review-ark, men kan aldrig materialiseres som beslutninger eller coverage.

## Før 1939-A kan forelægges

1. Mint og acceptér source records — også de relevante non-person strukturer —
   fra den frosne Calamari-rendition med eksplicit PDF-side og inputhash.
2. Opret et profilpinnet 1939-manifest for et deterministisk, stratificeret
   udvalg; living-person-undtagelsen gælder ikke dette historiske korpus.
3. Kør kun hele, validerede batches gennem fælleskontrakten og auditér
   exact-span, OCR/segmentering, personnummer, dublet- og placement-fejl samt
   relationer mod identitetsregister og 2018 som kandidatankre.
4. Hold alle identitets- og ægteskabskonflikter fail-closed til menneskeark.

Der er ikke kørt nogen databaseprojektion, Supabase-mutation eller
produktionsdeploy som led i denne audit.
