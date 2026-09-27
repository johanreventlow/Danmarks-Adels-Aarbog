# 4.5-pilot — fortolkning, afgørelse og binding (2018-20)

> **Færdig.** Afsnit 1-8 målt 2026-09-26; dommen i afsnit 9 og `pilot-verdict`-blokken er
> godkendt af projektejeren 2026-09-27.

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

## 5. Afgørelse

Afgørelsesarket: 243 beslutningslinjer, 84 forudfyldt fra 4.3b's domme (86 parrede domme:
85 `J`, 1 `N`), 159 nye til projektejeren. `rows_sha256`
`1c5852ce5d934a2c9cb7bc7b2b79ed09ec92a25da31aa7c8f31e2f9f5de63ac4`; godkendt ark
`98bb9a217f622d3957d7f0083a94f88b6f7031d328658fdefb1264e938ccdacd`; aktør: projektejerens
redaktionsprofil. To linjer stod først som `U` og blev afgjort efter en forklaring af
klausulerne.

**Negativtest:** en versionskonflikt lagt på den *sidste* af de 243 afgørelser i en
engangskopi gav 1 `EVIDENCE_INTERPRETATION_VERSION_CONFLICT` og 0 skrevne afgørelser — hele
transaktionen rullede tilbage efter 242 vellykkede kald. **Kørslen:** rc=0; 242 `accepted`,
1 `rejected`, 0 `unresolved`, 0 `proposed` tilbage; alle 243 nye versioner bærer arkets hash.

> **Rettelse 2026-09-27:** under kontrolmodellens kørsel fandt projektejeren én fejl mere blandt de
> 159 nye (`person.death` på I-7, samme fejllæsning som nedenfor). Præcisionen er derfor
> **241/243 = 99,2 %**; tallene i afsnittet er målingen i arbejdsbasen, hvor I-7 fortsat står
> `accepted` (ubundet). Se `kontrolmodel-koersel-2018-20.md`.

**Præcision: 242/243 = 99,6 %.** Af de 159 nye forslag afviste projektejeren **0**. Den eneste
afvisning er det `person.death`-claim, 4.3b allerede dømte usandt: modellen læste en formulering af
typen »var død [dato], da [en senere handling]« som en dødsdato, men det er en seneste grænse for dødsfaldet.

| Prædikat | Accepteret | Afvist | Prædikat | Accepteret | Afvist |
| --- | ---: | ---: | --- | ---: | ---: |
| `mention.place` | 52 | 0 | `person.title` | 8 | 0 |
| `person.death` | 24 | 1 | `person.education` | 7 | 0 |
| `person.office` | 22 | 0 | `event.appointment`, `person.burial`, `person.publication` | 6 hver | 0 |
| `person.rank` | 20 | 0 | `mention.person`, `person.decoration`, `person.military_service` | 4 hver | 0 |
| `person.birth` | 19 | 0 | `event.acquisition`, `person.occupation` | 3 hver | 0 |
| `person.name` | 19 | 0 | `event.dismissal`, `event.marriage`, `person.baptism`, `relation.child` | 2 hver | 0 |
| `relation.marriage` | 16 | 0 | `event.travel`, `person.residence` | 1 hver | 0 |
| `person.estate` | 9 | 0 | | | |

**Exact-span-rate:** 237/243 værdier står ordret i en citeret klausul; **datoer 52/52**. De 6
afvigelser er 4 tekstværdier (titler o.l., skåret til — jf. 4.3b) og 2 hændelser, hvis `raw`
ikke står i klausulen (`normalized` uden `raw`-belæg: 2, begge accepteret). Fra
`evidence-runner-1.1` afvises en dato, der ikke står ordret (afsnit 3).

**Dispositionsdækning:** de 32 poster har 80 klausuler. 48 (60 %) har fået en
fortolkningsdisposition (21 `fortolkning_foreslaaet`, 27 `afventer_identitet`); 17 står som
`afventer_fortolkning` (ingen claim citerer dem) og 15 som `maskinelt_flagget`.

**Afgørelsestid — pilotens vigtigste måling.** Arket krævede flere arbejdssessioner fordelt
over flere dage, og projektejeren har meddelt (2026-09-26), at flere fulde ark ikke er en
farbar vej. Tiden blev ikke målt i timer; det er heller ikke nødvendigt for konklusionen: den
menneskelige gennemgang er kædens flaskehals, ikke modellen, prisen eller koden. Samtidig
fandt gennemgangen 0 fejl blandt 159 nye forslag. Se afsnit 8 og beslutningsforslaget i
`docs/decisions.md` (2026-09-26).

## 6. Dækning mod MANGLER

`MANGLER.txt` er tom: projektejeren noterede ingen udsagn, modellen burde have fundet
(bekræftet 2026-09-26: »ingen mangler«). Dækning efter planens mål: **100 %**. Forbehold:
målet hviler på én læsning af arket, fordelt over flere dage, og arket viser kun citerede
klausuler — de 17 uciterede (`afventer_fortolkning`) er ikke gennemlæst systematisk.

**Brugbarhed:** 32/32 poster har mindst ét accepteret claim.

## 7. Binding

Backup efter afgørelserne og før binding: `efter-afgoerelser.dump`
(`623e0777d12c17453fe96aea9e1f9b6a439cd06307b348a595d4daf33226874d`; tabellens data med).
Bindingen skete i ét batch (`fb11f5de-01a8-46fa-8ccb-7c12f6ae5fec`) under projektejerens
profil: preview og batch i samme transaktion, 0 fejl.

| Prædikat | `MATCH` (bundet) | `NO_MATCH` | Øvrige udfald |
| --- | ---: | ---: | ---: |
| `person.name` | 16 | 3 | 0 |
| `person.birth` | 13 | 6 | 0 |
| `person.death` | 11 | 13 | 0 |
| `person.title` | 3 | 5 | 0 |
| **I alt** | **43** | **27** | 0 |

**Bindingsandel: 43/70 = 61 %** af de accepterede promoverbare fortolkninger. `AMBIGUOUS`,
`NO_IDENTITY`, `NO_PLACEMENT`, `MATCH_SINGLETON` og `UNSUPPORTED_RULE`: 0. Efter bindingen:
43 rækker i `private.interpretation_promotion`, `fact` (7.197) og `assertion` (9.306)
uændrede; en ny målfinding giver 43 `ALREADY_PROMOTED` og 0 `MATCH`.

**Hvorfor 27 ikke fandt et mål** (målt maskinelt, kun antal):

| Årsag | Antal | Heraf |
| --- | ---: | --- |
| Samme værdi, anden skrivemåde — kun tegn/blanktegn afviger | 12 | død 7, fødsel 5 |
| Samme tal, andre ord (fx `f.`/`død`/`*` foran) | 4 | død 3, fødsel 1 |
| Personen har intet kanonisk faktum af typen | 6 | titel 4, død 2 |
| Reelt forskellig værdi | 5 | navn 3, død 1, titel 1 |

16 af de 27 er altså skrivemåde, ikke uenighed. En normalisering, der tåler dem, ville give op
til 59/70 = 84 % — men det er en ændring af RPC'ens sammenligning (DDL, prod-gate), og »samme
tal, andre ord« kan skjule en reel forskel i præcision (fx »ca. 1700« mod »1700«). Kun 5 er
uoverensstemmelser, et menneske bør se.

Promoverbare prædikater udgør 70 af 243 forslag (29 %). De øvrige 71 % kan ikke føre til en
binding med de nuværende regler — de blev afgjort uden at det fører nogen vegne.

## 8. Skalafremskrivning

| 488 `eligible` records | Median-scenarie | p90-scenarie |
| --- | ---: | ---: |
| Input-tokens | ≈ 7,98 mio. | ≈ 8,65 mio. |
| Output-tokens | ≈ 0,31 mio. | ≈ 0,53 mio. |
| Reasoning-tokens | ≈ 0,14 mio. | ≈ 0,25 mio. |
| Kald | 488 + genforsøg (målt: 1 timeout pr. 25 kald) | |

Heraf er 34 records allerede kørt (4.3b's 10 og 4.5's 24); 454 mangler.

| Ved pilotens andele, 454 records | Antal |
| --- | ---: |
| Forslag (7,6 pr. post) | ≈ 3.450 |
| Heraf promoverbare (2,2 pr. post) | ≈ 990 |
| Bindinger ved 61 % | ≈ 600 |
| Reelle uoverensstemmelser (5 pr. 32 poster) | ≈ 70 |

**Menneskelig byrde ved nuværende afgørelsesmodel:** ≈ 3.450 arklinjer = ca. 14 ark af
pilotens størrelse. Pilotens ene ark tog flere dage. **Det er ikke gennemførligt**, og
modellen, prisen og koden er ikke begrænsningen. Beslutningsforslaget 2026-09-26 i
`docs/decisions.md` beskriver en kontrolmodel, hvor mennesket kun ser uoverensstemmelser og
en stikprøve.

**Fremskrivningen dækker ikke** 1939's OCR-klausuler (trin 6), andre aktører end
hovedpersonens persona (trin 5) eller en profilændring efter #189 (sektionsoverskrifter som
klausuler), som vil ændre klausulerne og dermed record-input-hashene.

## 9. Dom — godkendt af projektejeren 2026-09-27

| Stopkriterium (som 4.3b) | Resultat | Tærskel | |
| --- | ---: | ---: | --- |
| Præcision — sand ifølge teksten | 241/243 = **99,2 %** (rettet 2026-09-27; målt 242/243) | ≥ 90 % | ✅ |
| Klausulbinding — citerer eksisterende klausul i posten | 243/243 = **100 %** | ≥ 90 % | ✅ |
| Ordrethed — claims m. ordret krav (datoer) | 52/52 = **100 %** | ≥ 95 % | ✅ |
| Dækning — noterede udsagn fundet | **100 %** (forbehold afsnit 6) | ≥ 60 % | ✅ |
| Brugbarhed — poster m. mindst ét korrekt claim | **32/32** | alle | ✅ |

§8.4: ingen prædikatkategori med absurd lav eller høj dækning noteret. Stophændelser: ingen
claims om levende personer (0 af 30 identificerede personer har `levende` ≠ `false`), ingen
klausul fra en anden record (writerens `CLAUSE_FOREIGN_POST`), intet kontraktbrud.

**Kvaliteten er GO.** Modellen udtrækker sande, kildebundne fakta af ægte DAA-prosa, og kæden
fra klausul til binding virker i én restore uden kanonisk delta.

**Fuld kørsel er NO-GO med den nuværende afgørelsesmodel.** Ikke på grund af kvalitet, men
fordi den kræver ≈ 3.450 menneskelige afgørelser, som projektejeren ikke har kapacitet til, og
fordi gennemgangen af 159 nye forslag fandt 0 fejl (1 ved genlæsning 2026-09-27). Kontrolmodellen, der skal erstatte de
fulde ark, er besluttet 2026-09-27 (`docs/decisions.md`); en fuld kørsel under den kræver en
ny dom efter dens første kørsel. Overførslen af pilotens afgørelser og
bindinger til prod afhænger ikke af denne dom, kun af `breaches` (prod-vej-spec §6.2).

```pilot-verdict
{"breaches":[],"full_run_verdict":"NO-GO"}
```

Blokken følger prod-vej-spec §6.2 (sorterede nøgler, kompakt JSON). `pilot_verdict.py` er
planlagt på `docs/147-pilot-prod-vej`, men ikke implementeret; en fremtidig parsefejl er en fejl
i blokken eller parseren, ikke i piloten.
