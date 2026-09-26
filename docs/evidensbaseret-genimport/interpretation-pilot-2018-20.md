# 4.5-pilot — fortolkning, afgørelse og binding (2018-20)

> **UDKAST.** Afsnit 1-4 er målt og færdige. Afsnit 5-8 afventer projektejerens
> afgørelsesark (Task 5-6) og bindingen (Task 7); de er markeret **AFVENTER**.

Roadmapmål: trin 4 (#147/#148), dagsværk 4.5. Spec:
`docs/superpowers/specs/2026-09-06-trin4-fortolkningskaede-og-klausulgranularitet-design.md`
§8. Plan: `docs/superpowers/plans/2026-09-23-trin4-4-5-pilot-afgoerelse-binding.md`.
Alle kørsler er sket i arbejdsbasen `daa45_pilot_20260924093200` (en kopi af restoren
`daa43b_20260912192527`), aldrig i restoren selv og aldrig i prod. Rapporten indeholder
record-nøgler, tal og hashes — ingen klausultekst og ingen claim-værdier.

## 1. Udvalg

24 nye poster valgt før første kald, deterministisk ud fra strata `45-strata-v3`
(`strata_sha256` `5e7d4e4ca45324ad87104258711cacc2c9e600ba193b184759a4c05940c1c30a`),
blandt ledgerens `eligible` records og uden 4.3b's 10. 6 reserveposter i samme GO.
1 krydshenvisning udelukket.

| Bundt | Poster |
| --- | --- |
| bundt_1 | I-105 II-24 I-3 I-7 I-106 III-1 |
| bundt_2 | I-121 I-96 I-119 III-120 I-13 I-97 |
| bundt_3 | I-133 III-76 I-130 III-83 I-122 III-5 |
| bundt_4 | I-24 III-62 I-43 V-18 I-70 III-87 |
| reserve (ikke kørt) | II-3 I-108 I-5 III-92 I-60 V-39 |

Dækning af de 24: mindst ét gift-udsagn 15, flere gift-udsagn 6, usikker dato 18,
titel 22 (§8.1; V4: gift-antallet dækker både indgiftede og slægtens egne).

## 2. Kontrakt og GO

| | |
| --- | --- |
| Runner-manifest | `b18205f7d6fc44e97c1ded499c32df871e95ad776cc36054b02af5775935a4e0` |
| GO | projektejeren 2026-09-24, efter kvotenulstilling |
| Model / profil | `gpt-5.6-terra` / 1.3.0 (samme som 4.3b) |
| Prompt | `d46cda80177cf3b6c327842ceff0f1e32b589748055537f7f3af6fabfd11abbb` |
| Runner-kode | `c2d7f4528af1780ae14e48b7fe8e221ad42bb33d91ffe03b315890af957bc949` (`evidence-runner-1.0`) |

Codex' eneste koderunde (NO-GO: 1 BLOCKER, 4 MAJOR) lå før GO; alle fund er rettet med
test først, og manifestet er bygget efter rettelserne (planens ændringslog 2026-09-24).

## 3. Kørslen

| Bundt | Dækket | Delvis | Gyldige claims | Input-tokens |
| --- | ---: | ---: | ---: | ---: |
| bundt_1 | 6/6 | 3 | 31 | 100.285 |
| bundt_2 | 6/6 | 2 | 36 | 117.800 |
| bundt_3 | 6/6 | 4 | 37 | 102.044 |
| bundt_4 | 6/6 | 2 | 56 | 100.366 |
| **I alt** | **24/24** | **11** | **160** | **420.495** |

**Gaten (V1):** 24 nye poster med mindst ét kontraktgyldigt claim + 4.3b's 8 = **32 ≥ 30**.
Reserven blev ikke kørt.

**Én timeout.** II-24 ramte runnerens timeout (900 s) i første forsøg. Spec §6.3 er
fail-closed (batchen forbliver `pending`), og svar-cachen er bygget til netop genkørsel:
bundtet blev kørt igen, de fem besvarede records kom fra cachen, og kun II-24 blev kaldt —
nu med 1 gyldigt claim. Regel fastlagt før genforsøget: ét genforsøg pr. timeout, derefter
`failed`. 1 timeout på 25 kald.

**Afvisninger ved kontrakten:** 14 af 174 rå claims (8 %): `RUNNER_CLAIM_VALUE_INVALID` 9,
`RUNNER_CLAIM_PERSONA_REQUIRED` 4, `RUNNER_CLAIM_PREDICATE_INVALID` 1. Derudover 1 afvist af
H1 i forslagsbyggeren; 0 dubletter; 0 ukendte roller.

**Binding og ordrethed på de 160 gyldige claims: 160/160 (100 %).** Ordretheden er *målt*
efter kørslen, ikke håndhævet under den: værdien står tegn for tegn i mindst én af de
citerede klausuler. Runneren (`evidence-runner-1.0`) tjekkede kun værdiens *form*
(`validate_claim_value`: skalar eller objekt med ikke-tom `raw`), aldrig om værdien står i
klausulen — så de 9 `VALUE_INVALID` ovenfor er formfejl og siger intet om ordrethed.
(Review 35, fund P10.) Fra `evidence-runner-1.1` afviser runneren dato-claims (`date_raw`),
hvis værdi ikke står i en citeret klausul (`RUNNER_CLAIM_VALUE_NOT_VERBATIM`); titler og
hændelser er bevidst undtaget (projektejerens valg 2026-09-26). Piloten kørte under 1.0, og
ingen af dens datoer ville være afvist. Tallet er derfor et resultat for netop disse 160 claims, ikke en
egenskab, kæden garanterer. Målt over hele arkets 243 forslag (inkl. 4.3b's) står 6 værdier
ikke ordret; 2 af dem er hændelser, projektejeren bedømte som sande i 4.3b. Den
meningsfulde størrelse er afvisningsraten (14/174) og præcisionen i afsnit 5.

**Prædikatfordeling (gyldige claims):**

| Prædikat | Claims | Prædikat | Claims |
| --- | ---: | --- | ---: |
| `mention.place` | 41 | `person.estate` | 5 |
| `person.rank` | 16 | `person.education` | 5 |
| `person.death` | 16 | `person.burial` | 5 |
| `person.birth` | 13 | `person.military_service` | 4 |
| `relation.marriage` | 13 | `mention.person` | 3 |
| `person.name` | 12 | `relation.child`, `event.marriage`, `event.acquisition` | 2 hver |
| `person.office` | 10 | `event.travel`, `event.dismissal`, `person.residence`, `person.baptism`, `person.occupation`, `person.decoration` | 1 hver |
| `person.title` | 5 | | |

Claims pr. post: median 5,5, max 14. Klausuler pr. post: median 1 (42 i alt).

### Forbrug pr. record (n = 24)

| | Sum | Median | p90 | Min | Max |
| --- | ---: | ---: | ---: | ---: | ---: |
| Input | 420.495 | 16.344 | 17.718 | 16.159 | 36.300 |
| heraf cachet input | 186.368 | 11.008 | 13.056 | 0 | 28.160 |
| Output | 17.288 | 637 | 1.096 | 350 | 1.555 |
| Reasoning | 7.996 | 293 | 516 | 131 | 862 |

II-24's første forsøg (timeout) har ingen registreret usage og er ikke med i tallene.

## 4. Proposed-ingest

Forslagsmanifestet (`manifest_content_sha256`
`25732a53f5f509a8a49a06641df0f7179e0a7a4a483953bc6794f7c8777b52de`, 24 elementer) blev
ingestet med 4.4's writer via dry-run og derefter apply. Forventningen blev skrevet ned før
kørslen; alle tal ramte.

| Tal | Forventet | Målt |
| --- | ---: | ---: |
| Elementer | 24 | 24 |
| Nye fortolkninger | 159 | 159 |
| `principal` / `other` | 101 / 58 | 101 / 58 |
| Forslag i alt (84 fra 4.4 + nye) | 243 | 243 |
| Reimport-hændelser | 32 | 32 |
| `afventer_identitet` (i alt) | 27 | 27 |
| `fortolkning_foreslaaet` (i alt) | 21 | 21 |
| Forslag uden persona | 74 | 74 |
| Kanonisk delta | 0 | 0 |

`anon`s rettigheder er uændrede før og efter (hash af grants).

## 5. Afgørelse — AFVENTER

Afgørelsesarket: 243 beslutningslinjer, 84 forudfyldt fra 4.3b's domme (86 parrede domme:
85 `J`, 1 `N`), 159 til projektejeren. `rows_sha256`
`1c5852ce5d934a2c9cb7bc7b2b79ed09ec92a25da31aa7c8f31e2f9f5de63ac4`; arkets hash: AFVENTER.

AFVENTER: præcision pr. prædikat (`accepted / (accepted + rejected)`, `unresolved` for sig),
`normalized` uden `raw`-belæg, dispositionsdækning, negativtestens udfald.

## 6. Dækning mod MANGLER — AFVENTER

## 7. Binding — AFVENTER

Bindingsandel `MATCH` / accepterede promoverbare, med `MATCH_SINGLETON`, `NO_MATCH`,
`AMBIGUOUS`, `NO_IDENTITY`, `NO_PLACEMENT`, `ALREADY_PROMOTED` og `UNSUPPORTED_RULE` hver
for sig. Backup- og bindingsbatch-hashes.

## 8. Skalafremskrivning

Forbrugsdelen er målt nu; bindings- og afgørelsesdelen afventer afsnit 5-7.

| 488 `eligible` records | Median-scenarie | p90-scenarie |
| --- | ---: | ---: |
| Input-tokens | ≈ 7,98 mio. | ≈ 8,65 mio. |
| Output-tokens | ≈ 0,31 mio. | ≈ 0,53 mio. |
| Reasoning-tokens | ≈ 0,14 mio. | ≈ 0,25 mio. |
| Kald | 488 + genforsøg (målt: 1 timeout pr. 25 kald) | |

Heraf er 34 records allerede kørt (4.3b's 10 og 4.5's 24). AFVENTER: forventet menneskelig
afgørelsestid pr. forslag og forventet antal bindinger ved samme andel.

**Fremskrivningen dækker ikke** 1939's OCR-klausuler (trin 6), andre aktører end
hovedpersonens persona (trin 5) eller en profilændring efter #189 (sektionsoverskrifter som
klausuler), som vil ændre klausulerne og dermed record-input-hashene.

## 9. Dom — AFVENTER

Stopkriteriet (som 4.3b): præcision ≥ 90 %, klausulbinding ≥ 90 %, ordrethed ≥ 95 %,
dækning ≥ 60 %, brugbarhed for alle biografiske poster; plus §8.4 (absurd lav eller høj
dækning i en prædikatkategori er `NO-GO` for fuld kørsel).
