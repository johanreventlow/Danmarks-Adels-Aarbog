# Spor 1a — beslutningssporet (fase 1, helhedsreview trin 1-5)

Alle stier er relative til EKS. "0b" = `docs/reviews/2026-10-27-trin-1-5/beslutningskronologi.md`,
"0e" = `docs/reviews/2026-10-27-trin-1-5/leverancetidslinje.md`, "0d" = `…/udestaaende-raa.md`.
Forbehold fra 0d:3: eksporten er taget før docs-PR #271 (5c-1 i prod). Det, at status ikke nævner 5c-1, er
derfor ikke et fund her. De forældede steder, jeg nævner nedenfor, går længere tilbage end 5c-1.

## 1. Sammendrag

1. Styringsdokumenterne (`status.md`, `roadmap.md`) modsiger sig selv om aktivt mål, prod-tilstand og næste arbejde — den direkte årsag til orienteringstabet (1a-01).
2. Kursskiftet væk fra `load_daa.R` er ufuldført: CLAUDE.md/skill kalder den »fremadrettet«, decisions »historisk« og fejlskabende (1a-02).
3. Trin 4's 622 bindinger og alle strukturerede fakta er usynlige for læseren; åbent i 10 uger, ikke nævnt eksplicit i roadmappet (1a-03).
4. Restore-only fortrydelse + byg-i-restore-og-overfør kostede et overførselsprogram pr. trin (U43: 10 af 15 PR'er) og gjorde trin 4-5 reelt ufortrydelige (1a-04).
5. Styringsregler blev besluttet men ikke håndhævet (review-budget, kontrollerede afbrydelser); glidningen blev selvdiagnosticeret tre gange, men fokus holdt i oktober (1a-05, 1a-09).
6. Proces og kontrolmodel er ude af proportion med en PoC for én familie og én redaktør (1a-10, 1a-12).

## 2. Stikprøve af 0b's kildehenvisninger

| 0b-henvisning | Påstand i 0b | Resultat |
|---|---|---|
| `docs/decisions.md:709` | Ingen fulde afgørelsesark (2026-09-27) | Passer (overskrift på linje 709) |
| `docs/decisions.md:441` | 5b `family_corroboration`, "efter syv review-runder" | Passer (441; "syv review-runder" på 444-445) |
| `docs/decisions.md:1609` | Pivot ~08-06 "uden skriftlig beslutning" | Passer (1609; ordlyden på 1612) |
| `docs/decisions.md:2066` | C1 udskudt | Passer |
| `docs/decisions.md:797` | Review-budget efter konsekvens | Passer |
| `docs/decisions.md:1337` | Styringsregler efter PM-gennemgang | Passer |
| `docs/decisions.md:1638` | Præcisering; "gaten ophæves" samme dag | Passer (1638; "AFGJORT" på 1654) |
| `docs/decisions.md:3114` / `:2768` | 06-27 "redigér=UPDATE bryder #1" mod 07-03 "bryder IKKE, append" | Passer begge (3134-3135; 2774-2778) |
| `_ledger-rulings.txt:33` og `:31-32` | Forælder-barn-krydstjek; Task 4-rulings | Passer |
| `docs/decisions.md:470/507` (note om kontraktfrys) | Bemærkningen om modstrid | Linjerne passer. Der er **ingen reel modstrid**: frysen gjaldt til den fulde kørsel (507, 10-03) og blev erklæret ophørt efter overførslen (497-500, 10-05). Det er rækkefølge i tid, ikke uenighed |

Resultat: 10/10 henvisninger passer. Én af 0b's mulige modstride er ikke en modstrid. Henvisninger, som jeg kun
har brugt via 0b og ikke selv efterprøvet, er markeret "via 0b".

## 3. Uge for uge: besluttet (0b) mod leveret (0e)

| Uge | Besluttet (0b, udvalg) | Leveret (0e) | Afvigelse |
|---|---|---|---|
| U25-26 (15/6-28/6) | DAA først, selektiv rygrad, lineage (a), redaktions-kerneskive | Parsere, datamodel, mobil 34 + redaktion 25 commits | Ingen |
| U27 (29/6) | 07-03: TNG-backlog — **smart-lister "NÆSTE FOKUS"**, medie-rigdom "udskudt samlet" | 357 commits: medie slice 0-C (#17-#22), feed v3, stamtræ, samme_som | Smart-lister blev aldrig bygget og blev aldrig taget af listen (1a-14) |
| U28-U30 (6/7-26/7) | Bogmærker, packages/core, RLS fail-closed, plan-1939 (07-17), feed fase 4 udskudt | ~400 commits: feed fase 1-3, medie fase 1-4, præsens (45), sammenlign-udgaver | Formidlingsfunktioner uden prioriteringsbeslutning (genimportprogrammet fandtes ikke endnu, så det er ikke glidning mod trin 1-5) |
| U31 (27/7) | Firleddet adresse, replay source-scoped (07-30) | Replay-kæden, prod-replace | Ingen |
| **U32-U34 (3/8-22/8)** | 08-02: genimport-design **"sættes på pause"**; 08-03 promotion-kontrakt | 537 commits, U34 alene 216 med scope `1939`; ca. 40 specs for 1939 v50 | **Pivot uden skriftlig beslutning** (`docs/decisions.md:1612`). D1 publicerede før GO-pakken fandtes (via 0b, changelog:1667) |
| U35 (24/8) | Model 2: fire autoritative dokumenter | 39 commits | Ingen |
| U36 (31/8) | 09-03: "seks spor parallelt, trin 3-4 på nul efter ~180 commits" (`docs/decisions.md:1343`) | GO 1-4 i prod | Andet selvdiagnosticerede tilbagefald |
| U37 (7/9) | Trin 4 aktiveret, tærskler, profiler | 18 PR'er, alle trin 4 | Bedst afstemte uge |
| U38 (14/9) | 09-17 restore-only; 09-20 rettighedsorakel | 4.4 + 4.1c i prod; **10 PR'er sikkerhed** (#202-#211) | Sikkerhedsuge midt i trin 4. Kun issue #164 bærer mærket `kontrolleret-afbrydelse` (`_issues.txt:2`). Sammenhængen er sandsynlig, ikke dokumenteret |
| U39 (21/9) | 09-23: 4.4 parkeres, review-budget; 09-27 kontrolmodel, omsegmentering | #212-#222: 4.4-projektion og GO-pakke, pilot, kontrolmodel | GO-pakken blev færdig og derefter aldrig brugt (1a-06) |
| U40-41 (28/9-11/10) | 10-01 samlet overførsel; 10-05 trin 5 aktiveret | #223-#238: fuld kørsel, plan A/B, overførsel, 5a, 5b del 1 | Ingen |
| U42 (12/10) | 2b deles; "fire Codex-runder 290→539 linjer" | #239-#243 | Review-budget overskredet (1a-05) |
| **U43 (19/10)** | Indholds-id'er, 5a's 31 afgørelser overføres ikke, GO 2-politik | 15 PR'er, **10 af dem overførselsmaskineri** (#250-#259) | Overførslen fylder mere end indholdet (1a-04) |
| U44 (26/10) | #240, #248, rute A, 5c-1 | 9 PR'er, fire prod-ceremonier på én dag | #240 og #248 er ikke registreret som kontrollerede afbrydelser (1a-09) |

Fra uge 41 ligger stort set al aktivitet på det aktive mål (scopes 151/150/240/244/248). Disciplinen om ét aktivt
mål holdt altså i oktober. Problemet er nu ikke glidning. Problemet er, hvor meget hvert skridt koster.

## 4. Fund

### 1a-01 — Styringsdokumenterne siger imod sig selv og er forældede (orienteringstabet)
- Område/trin: programstyring, alle trin · **Alvor: P1** (styringsdokumentet giver forkert retning: "bevis der
  ikke beviser")
- Sted: `docs/evidensbaseret-genimport/status.md:142`, `:159`, `:161`, `:174-175`, `:178`, `:206-213`, `:266`,
  `:333-337`; `docs/evidensbaseret-genimport/roadmap.md:21-25`; `CLAUDE.md` (afsnittet "Evidensbaseret
  genimport — bindende styringsgrundlag")
- Påstand: Netop de dokumenter, som CLAUDE.md gør bindende at læse først, giver samtidig modsatte svar på,
  hvad det aktive mål er, hvad der er i prod, og hvad der skal laves nu.
- Evidens: `status.md:142` "Det aktive programmål er nu #152" mod `:256` "Det aktive programmål er nu trin 5".
  `:174` 149a `produktionsverificeret (2026-09-06)`, mens samme række slutter med "Ikke
  `produktionsverificeret`; prod-rækkefølge …". `:178` #152 `produktionsverificeret`, men "Ingen production
  cutover eller produktions-GO er givet". `:159` klausulgranularitet `specificeret`, selv om klausulerne kørte i
  prod 18/9 (`:217`). `:206-213` "ingen reel extractor-runner udfylder det" og "2018-20 har … ikke source
  records". `:266` "Næste tilladte arbejde: 1. 5b del 2", selv om 2a-2b-iii er leveret (0e U42-U43).
  `roadmap.md:25` "næste arbejde er 5b del 2". `status.md:333-337` kræver et nyt afstemt snapshot ved
  afslutningen af hver roadmapfase. Trin 4 sluttede 10-05, men der kom kun tilføjede tillæg oven på teksten.
- Konsekvens: Hvert nyt agentpas og du selv læser tre-fire tilstande på én gang. Det er den direkte mekanisme bag
  "mistede orienteringen". Det åbner også for, at en agent på et forældet afsnit planlægger noget, der allerede er
  gjort, eller springer et trin over.
- Hvem besluttede: Modellen med fire dokumenter er projektejerens (`docs/decisions.md:1540`). CI-håndhævelse
  blev "bevidst udskudt" (`:1556`). Tillægsformen er en agentpraksis, og hvem der valgte den, er uklart.
- Hvad kostede det: Det kan ikke måles i dage. Det kostede orientering, og 0d:117 måtte selv flage
  dokumentationsdrift.
- Fremover: Skriv `status.md` om til ét snapshot på højst én side ved hvert trinskifte. Forbyd tillæg. Historik
  hører hjemme i changelog. Hold roadmappets afsnit "Aktivt programmål" på én linje. Lav én billig CI-kontrol, der
  tjekker, at status' og roadmappets "aktivt mål" er ens.
- Sikkerhed: verificeret.

### 1a-02 — `load_daa.R` har tre gældende statusser; den gamle indlæsevej er aldrig lukket
- Område/trin: import, overgang fra legacy (målarkitektur), trin 7 · **Alvor: P1** (risiko for data: en
  dokumenteret indgang genskaber kendte fejl)
- Sted: `CLAUDE.md:23`; `.claude/skills/daa-extract/SKILL.md:58`, `:189`; `docs/decisions.md:120-123`;
  `docs/evidensbaseret-genimport/teknisk-maalarkitektur.md:222-233`
- Påstand: Kursen blev lagt om til evidenskæden, men indgangsdokumenterne sender stadig nye indlæsninger gennem
  den gamle indlæser.
- Evidens: CLAUDE.md:23 "Load går gennem skill'ens `load_daa.R` (append/staged)". SKILL.md:189 "`load_daa.R` er
  den fremadrettede loader". decisions.md:122-123 "`load_daa.R` er historisk; genimport går gennem evidenskæden
  … en genindlæsning med den gamle indlæser ville genskabe dobbeltfamilierne". Målarkitekturen (222-226) kræver,
  at legacy-veje er tidsafgrænsede og har en exit-betingelse. Der er ingen exit-post i decisions. Samme
  grundårsag går igen i spøgelses-unioner (07-03, loader-guard udestår) og 16 tomme unioner (`_issues.txt` #163,
  parkeret).
- Konsekvens: Den dokumenterede indgang til trin 7 er netop den vej, der laver dobbeltfamilier og
  spøgelses-unioner.
- Hvem besluttede: "historisk" står i projektejerens #240-post (10-26). At CLAUDE.md og skill'en ikke blev rettet,
  er uklart, sandsynligvis en glemt opfølgning.
- Hvad kostede det: #240 kostede én prod-ceremoni plus DDL (0e U44, #261-#262). Grundårsagen står tilbage.
- Fremover: Træf én beslutning nu. Enten fryses `load_daa.R` (den nægter ukendte/nye kilder uden et eksplicit
  legacy-flag), eller den gøres til profilens dokumenterede trin 0 med guard'en `navn ≠ ref`. Ret CLAUDE.md:23 og
  SKILL.md samme dag.
- Sikkerhed: verificeret (dokumenterne). At en ny årbog faktisk ville gå den vej, er sandsynligt.

### 1a-03 — Læserværdien af trin 4 udebliver; roadmappet nævner ikke læseprojektionen eksplicit
- Område/trin: trin 4-6, vision · **Alvor: P2** (vigtigst for spørgsmålet "dækker det behovet")
- Sted: `docs/decisions.md:1786-1813`; `web/src/data/public.ts:208-262`; `docs/evidensbaseret-genimport/roadmap.md:29-38`;
  `docs/evidensbaseret-genimport/vision.md:19-20`; `docs/decisions.md:826-828`
- Påstand: Trin 4's 622 bindinger mellem kilde og faktum, og alle strukturerede fakta, har ingen vej til
  læseren. Spørgsmålet har stået "Ikke besluttet" i 10 uger.
- Evidens: decisions.md:1810 "Ikke besluttet: om persondetaljen skal have en fakta-sektion". `fetchPersonDetail`
  (public.ts:208-262) henter kun `narrative` og `relation`. Vision:19-20 nævner læserværdi som fælles
  succeskriterium. Projektejerens regel 09-23 (decisions.md:826) siger: "Hvert dagsværk ender med noget, en
  redaktør eller læser kan bruge, eller med en måling". Intet af roadmappets 7 trin nævner "offentlig læseprojektion med kildehenvisning" eksplicit (værdikædens sidste led, målarkitektur:34); den er kun implicit i trin 6's "ende-til-ende". Det, der taler
  imod: 5b's `public_family_sources` vises i `web/src/components/DetailPanel.tsx:43`. Det er den ene synlige
  læsergevinst.
- Konsekvens: Trin 4 er `produktionsverificeret`, men læseren kan ikke se noget af det. Bogens oplysninger (dåb,
  død, navneformer) er usynlige for personer uden prosa (D2's 21 stubbe).
- Hvem besluttede: Ingen. Spørgsmålet er åbent.
- Hvad kostede det: Trin 4 fyldte U37-U41, ca. 45 PR'er (#172-#233). Læsergevinsten er udskudt på ubestemt tid.
- Fremover: Før trin 6: én beslutningspost og én dags skive med en fakta-sektion i persondetaljen (konklusion +
  kildehenvisning). Skriv "læseren kan se det" ind som exit-kriterium for trin 6.
- Sikkerhed: verificeret.

### 1a-04 — Fortrydelse kun ved restore + byg i restore og overfør samlet = et overførselsprogram for hvert trin
- Område/trin: trin 4-5, overførsel til prod · **Alvor: P2**
- Sted: `docs/decisions.md:991`, `:834`, `:464`, `:290/:309/:334/:358/:378/:403` ("Uændret: restore-only");
  `docs/decisions.md:662-669` (09-27); `:580` (10-01); `:203-212`, `:230`, `:261-273` (10-21/22);
  `docs/evidensbaseret-genimport/teknisk-maalarkitektur.md:158-160`, `:182-187`; `docs/changelog.md:16`
- Påstand: Fortrydelse kun ved restore blev valgt mindst 9 gange. Det modsiger målarkitekturens
  apply/reversal-gate, og der er ingen ændringspost til målarkitekturen. Sammen med "byg i restore, overfør samlet
  én gang" har det skabt det dyreste enkeltstående mønster i trin 4-5.
- Evidens: Gate 8 (målarkitektur:158-160) skal bevise, at en fortrydelse "rammer præcis den godkendte mængde".
  En restore rammer alt siden backuppen. Allerede 09-27 (10 dage efter det første valg) måtte projektejeren afvise
  restore, fordi den "ville rulle anon-hærdning, medie-indkapsling, bogmærker og rettelser tilbage" (via 0b,
  decisions:662). 10-22: hashes "indeholder basens identitet og tilfældige versions-id'er, så de kan ikke
  sammenlignes mellem baser" (decisions.md:209-210). Det udløste id'er af indholdet (8 rækkearter, 261) og
  nøglede digests over 21 lag (status.md:171). 5a's 31 kalibreringsafgørelser fra projektejeren blev kasseret
  (230). Rute A fik "ingen fortryd-vej for data" (changelog.md:16).
- Konsekvens: I dag kan trin 4/5 i praksis ikke fortrydes. En restore til 10-05-dumpet ville tabe GO 1, GO 2,
  #240, #248 og 5c-1. Det gælder for én redaktør og formentlig ingen eksterne læsere, så den praktiske risiko er
  lav, men den er hobet op.
- Hvem besluttede: Projektejeren hver gang, efter agentens forslag (09-17, 09-23, 10-01, 10-06, 10-21).
  Tilfældige id'er var en følge, ingen så på tidspunktet; det er bagklogskab. Tabet ved restore var kendt fra
  09-23.
- Hvad kostede det: Overførslen for trin 4 (#231-#233, U40-U41) og trin 5 (#250-#259, 10 af 15 PR'er i U43, ca. 1
  uge). 5c-1 gik direkte mod et frisk dump og i prod på 2 dage. Det er en forbedring, men den er ikke
  beslutningsført.
- Fremover: Trin 6 bygges med indholds-id'er fra starten og med en smal reversal pr. batch, eller også gøres
  restore-only til en formel ændring af målarkitekturens gate 8. Gør 5c-1-formen (byg mod frisk dump, én
  ceremoni) til den beslutningsførte standard.
- Sikkerhed: verificeret (beslutningerne). Ugeomkostningen er udledt af 0e.

### 1a-05 — Review-budgettet (09-23) blev besluttet og derefter overskredet uden undtagelsesgrundlag
- Område/trin: proces, trin 5 · **Alvor: P2**
- Sted: `docs/decisions.md:797-831`; `:444-445`; `:374`; `:5-7`; `:205`
- Påstand: Projektejerens budget på 2+2 runder (undtagelsesrunde kun med begrundet ja) blev brudt i hvert af de
  efterfølgende hovedtrin.
- Evidens: Budget, 09-23 (807-824). 5b, 10-06: "efter brainstorm og syv review-runder (Claude + Codex)" (444-445).
  2b-i, 10-12: "Fire Codex-runder voksede spec'en fra ca. 290 til 539 linjer" (374). 5c-1: spec Fable-reviewet,
  plan Codex/Opus, implementering Codex r1 NO-GO, derefter Opus-dom (5-7). Ingen af posterne nævner en
  undtagelsesrunde.
- Konsekvens: Reglen mod scope-vækst gennem review virker ikke. Specs vokser, og "otte teoretiske risici står som
  kendte begrænsninger" (374-376), som så skal bæres videre.
- Hvem besluttede: Budgettet er projektejerens. Runderne blev sat i gang af agenten, og projektejeren godkendte
  resultatet (efter 0b).
- Hvad kostede det: Det kan ikke kvantificeres fra 0e. Spec-vækst på 85 % i ét tilfælde.
- Fremover: Hver spec får en linje i hovedet med "Reviewrunder: n/budget". Overskridelse kræver én linje i
  decisions med begrundelse, ellers stopper arbejdet.
- Sikkerhed: verificeret.

### 1a-06 — Bygget, merget, opgivet og ikke fjernet (ufuldførte kursskift i koden)
- Område/trin: trin 4-5 · **Alvor: P2**
- Sted: `docs/decisions.md:799-802`, `:485`, `:598`; `.github/workflows/ci.yml:142`;
  `.claude/skills/daa-extract/scripts/interpretation_proposal_projection.sql`;
  `docs/evidensbaseret-genimport/relationspersonas-5b-2b-ii-bevis.md:20`;
  `docs/evidensbaseret-genimport/relationspersonas-5b-navneregel-v3-bevis.md:169`;
  `docs/superpowers/specs/2026-10-21-trin5ab-2018-20-prod-overfoersel-design.md:92-93`;
  `docs/evidensbaseret-genimport/status.md:168`
- Påstand: Flere byggede veje blev opgivet eller bevist ubrugte, men blev stående og vedligeholdes stadig.
- Evidens:
  - **4.4's GO-pakke og #196-projektionen:** "fire uafhængige reviewrunder på planen og fire på koden, et
    bibliotek på ~2200 linjer og en fejlmatrix på 30 cases … for 84 usynlige `proposed`-forslag" (799-802).
    Projektionen blev erklæret "erstattet" (485), og pakken "genbindes ikke" (598). Projektionsfiler og
    `test_compare_interpretation_proposal_projection.py` køres stadig af CI (ci.yml:142).
  - **`relation_person_create`:** begge bevisrapporter siger, at beviset på bogens data "skal foreligge før en
    prod-overførsel af 2b-ii". Overførselsspec'en (92-93) deployede alligevel vejen som `isoleret implementeret`
    med 0 elementer. D-reglen (≤ 1906) gav 0 tilfælde i 2018-20.
  - **`red_ret_aegteskabsnummer`:** "deployet, men ubrugt" (status.md:168).
  - Udenfor trin 1-5: feedets forbrugslag uden `haendelse`-data (#130, "tænd det byggede forbrugslag").
- Konsekvens: CI-minutter og vedligehold bruges på døde veje. Der ligger en ubevist personoprettelsesvej i prod.
  En stillet forudsætning ("skal foreligge før") blev ophævet, uden at bevisrapporterne blev rettet.
- Hvem besluttede: Parkering og "erstattet" er projektejerens (09-23, 10-05). Modenhedsafgrænsningen er
  projektejerens efter Fable-review (10-21). At oprydningen udeblev, er uklart.
- Hvad kostede det: 4.4-pakken fyldte ca. U38-U39 (#212, #214, #215 plus plan) uden brug.
- Fremover: Hver "erstattet"/"parkeret"-beslutning får en oprydningslinje: fjern, eller flyt til `archive/` og
  ud af CI. Brug ikke "isoleret implementeret" som adgangsbillet til prod.
- Sikkerhed: verificeret.

### 1a-07 — Promotion-kontrakten (08-03) modsiges af 5b og 5c uden at være afløst
- Område/trin: promotion, trin 4-5 · **Alvor: P2**
- Sted: `docs/superpowers/specs/2026-08-03-evidens-promotion-kontrakt-design.md:5`, `:30`, `:33`;
  `docs/superpowers/specs/2026-10-26-trin5c-placement-membership-design.md:123-131`; `docs/decisions.md:441-460`
- Påstand: To af kontraktens invarianter siger det modsatte af det, der nu kører i prod. Kontraktens statuslinje
  siger stadig "Implementeret".
- Evidens: 08-03:30 "Hverken batch eller enkeltpromotion må oprette `person`, `family`, `fact`, `relation`,
  medlemskab". 08-03:33 "Placement og genealogisk generation ændres ikke af promotion i version 1". Over for det:
  5c §4.4 "Membership via promotion … `person_slaegt_membership` (`agnatic`)", maskinelt accepteret.
  5b/2b-ii's `relation_person_create` opretter personer (441-460). Ingen post kalder det "promotion-kontrakt v2".
- Konsekvens: En agent, der læser kontrakten, får den modsatte regel af prods adfærd. Formuleringen "version 1"
  åbner sandsynligvis for, at 5c er tænkt som v2, men det står ingen steder.
- Hvem besluttede: Projektejeren godkendte 5b- og 5c-specerne. Afløsningen af kontrakten er uklar.
- Hvad kostede det: Indtil nu intet. Det er gæld.
- Fremover: Én decisions-post "Promotion-kontrakt v2" og en statuslinje i 08-03-specen ("afløst for
  membership/oprettelse af …").
- Sikkerhed: verificeret.

### 1a-08 — Invariant 1 har sanktionerede undtagelser, som CLAUDE.md ikke kender
- Område/trin: datamodel · **Alvor: P2**
- Sted: `CLAUDE.md:31`; `docs/decisions.md:3134-3135`, `:2774-2778`; `schema.sql:2065`, `:5886`, `:5960`;
  `docs/superpowers/specs/2026-07-26-person-ocr-kvalitetsark-design.md:28` (via 0b)
- Påstand: CLAUDE.md siger "Påstande overskrives aldrig". I praksis overskrives og slettes påstande ad to
  besluttede veje, og to decisions-poster beskriver redigering modsat af hinanden.
- Evidens: 06-27 "redigér=UPDATE, slet=DELETE bryder invariant #1 … bevidst PoC-valg" (3134). 07-03 "Redigering
  sker append-baseret … aldrig overskrivning" (2776-2777). Skemaet giver begge delvist ret: `red_edit_oplysning`
  er append-baseret (5887), men kommentaren på 5886 siger stadig "UPDATE assertion direkte".
  `red_ret_ocr_felt` UPDATE'er assertion (2065), hvilket er projektejerens 07-26-valg ("OCR-rettelse er ikke en
  ny historisk påstand"). `red_slet_oplysning` DELETE'er (5960).
- Konsekvens: Reviewere og agenter vil enten rapportere falske brud eller overse ægte brud.
- Hvem besluttede: OCR-undtagelsen er projektejerens. 06-27 er agentens/uklart.
- Hvad kostede det: Ingen målt omkostning. Det er gæld.
- Fremover: Skriv de to undtagelser ind i invariant 1's tekst, eller lav OCR-rettelsen om til en ny
  assertion-version. Markér 06-27-posten som afløst.
- Sikkerhed: verificeret (skemaet er kun brugt til at efterprøve beslutningen, ikke vurderet som kode).

### 1a-09 — Samme glidning selvdiagnosticeret tre gange; styringsredskaberne blev ikke brugt bagefter
- Område/trin: programstyring, U32-U44 · **Alvor: P2**
- Sted: `docs/decisions.md:1612`, `:1638-1654`, `:1343`, `:803`, `:1349`, `:1358-1359`;
  `docs/evidensbaseret-genimport/roadmap.md:71-76`; `docs/evidensbaseret-genimport/teknisk-maalarkitektur.md:222-226`;
  `_issues.txt:2`
- Påstand: Glidningen væk fra programmålet blev opdaget 22/8, 3/9 og 23/9. Rettelserne var beslutninger, men de
  redskaber, beslutningerne indførte, blev kun delvist brugt bagefter.
- Evidens: 22/8 "pivoterede ~2026-08-06 uden skriftlig beslutning" (1612). Anti-creep-gaten blev skrevet samme
  dag og "ophæves" samme dag. Det var en agentafgørelse ifølge 0b (1654). 3/9 "seks spor kørte parallelt" (1343).
  23/9 "mønstret fra 2026-09-03 igen" (803). "Kontrolleret afbrydelse" forekommer kun i 09-03-posten (1349,
  1358-1359). #240 og #248 (prod-datafejl, 26/10) har ingen indgangsgrund, slutkriterium eller tilbagevenden som
  krævet i roadmap.md:73-76. #164 har båret mærket siden 3/9; et slutkriterium er ikke fundet i decisions (sandsynlig).
- Konsekvens: Augusts 1939-spor (U32-U34, 537 commits, ca. 40 specs) er efter målarkitekturen (222-226) en
  legacy-vej, der skal udfases. 1939's kæde hører til trin 6 (roadmap.md:18-19), så dele af arbejdet skal laves om
  i den fælles kæde. Positivt: i oktober holdt fokus.
- Hvem besluttede: Pivoten er agentens/uklart. Rettelserne er projektejerens. Ophævelsen af gaten er agentens.
- Hvad kostede det: Ca. 3 uger (U32-U34). Vision-ikke-målet "gøre 1939 internt perfekt" blev brugt som arbejdsform.
- Fremover: Registrér afbrydelser i én linje (grund, slut, retur). En agent må ikke ophæve en gate, som er
  skrevet i projektejerens navn. Lav en kort afvigelsesmåling som 22/8 ved hvert trinskifte.
- Sikkerhed: verificeret.

### 1a-10 — Kontrolmodellen: tung ceremoni, lav erklæret bevisværdi, og i 5c-1 var den ikke blind
- Område/trin: menneskelig godkendelse, trin 4-5 · **Alvor: P2** (ceremonien er delvist teoretisk ved PoC-skala)
- Sted: `docs/decisions.md:21-27`, `:273`, `:110-114`; `docs/superpowers/specs/2026-10-06-trin5b-relationspersonas-design.md:83`, `:790`;
  `docs/decisions.md:743` (via 0b)
- Påstand: Kontrolkørslen er bygget med blind trækning, forseglede ark, trækninger afledt af indhold og
  hash-binding, men projektet beskriver selv dens bevisværdi som lav. I 5c-1 blev blindheden brudt og
  accepteret.
- Evidens: 5b-spec:83 "Matchet … er derfor næsten selvbekræftende". decisions.md:273 kalder kontrollen "en
  advarselslampe mod maskinfejl, ikke et værn mod redaktøren". 5c-1 (decisions.md:21-27): "Arket blev aflæst i
  dialog med agenten, der anvendte reglens definition … fravalgt en ny blind stikprøve". #240 gjorde 2018-20's
  kontrolkørsel "brugt op" (110-114).
- Konsekvens: Den udførte formalitet antyder en sikkerhed, beviset ikke bærer. Samtidig koster den
  projektejertid og kode (indholds-id'er for trækninger, -v2-trækninger).
- Hvem besluttede: Projektejeren (09-27, 10-10, 10-27). Den konkrete arkmekanik er agentens.
- Hvad kostede det: Ark-designet før kontrolmodellen: fulde menneskeark blev specificeret 09-06 (§8.2), før projektejerens kapacitet var målt; 4.5-arket på 243 linjer krævede "flere arbejdssessioner over flere dage" (`docs/decisions.md:715-716`) og blev først rettet 09-27. Selve ceremonien indgår i 1a-04/1a-12.
- Fremover: Vælg én af to. Enten kaldes den en røgtest (20 tilfældige kort, ingen forsegling eller
  hash-ceremoni), eller blindheden holdes strengt, så agenten aldrig læser arket sammen med projektejeren.
- Sikkerhed: verificeret.

### 1a-11 — Udskudte afgrænsninger faldt mellem skiverne og blev til #248 (offentlig fejl)
- Område/trin: trin 5b · **Alvor: P2** (fejlen var synlig for læseren; rettet)
- Sted: `docs/superpowers/specs/2026-10-11-trin5b-2b-i-genbinding-og-aegtefaeller-design.md:403-404`;
  `docs/decisions.md:55-61`, `:68-70`, `:374-376`, `:1012` (via 0b)
- Påstand: 2b-i skubbede "genafgørelse ved familieskift" til 2b-ii, og 2b-ii leverede det aldrig. Samtidig
  skjulte et forudfyldt ark konflikten. Tilsammen bandt det to ægteskaber til den forkerte, offentlige familie.
- Evidens: 2b-i §13: "Genafgørelse af en accepteret relation, hvis struktur er flyttet til en anden familie →
  2b-ii" (403-404). decisions.md:68-70: "Det lukker hullet, som 2b-i-spec'en (§13 pkt. 1) udskød til 2b-ii, og som
  2b-ii ikke leverede". Arket "forudfyldte »S = kandidat nr. 1« og viste kun kandidat 1 … Læseren viser
  kildeteksten på den forkerte, offentlige familie" (56-60). Derudover: "otte teoretiske risici … som
  overførsels-spec'en skal tage stilling til før prod" (374-376). Om de blev håndteret, er ikke efterprøvet.
- Konsekvens: Risiko blev skubbet foran sig, indtil den ramte prod. Det udløste ny DDL og en permanent arkregel
  (`SHEET_UNANSWERED`).
- Hvem besluttede: Skiveopdelingen er projektejerens. Forudfyldningen er agentens/uklart (09-15).
- Hvad kostede det: 26/10: to prod-ceremonier, ny spec og rute A (#265-#268).
- Fremover: Hver "→ senere skive"-udskydelse får et issue og et tjek i overførselsspec'ens gate ("alle udskudte
  punkter fra skiverne er lukket eller eksplicit båret videre").
- Sikkerhed: verificeret. At de otte risici blev håndteret, er ikke efterprøvet.

### 1a-12 — Processens omfang står ikke mål med en PoC for én familie
- Område/trin: proces, tværgående · **Alvor: P2** (vedligeholdelsesgæld; flere elementer er teoretiske ved
  projektets skala)
- Sted: `docs/reviews/2026-10-27-trin-1-5/maalinger.md:68-71`; `docs/reviews/2026-10-27-trin-1-5/udestaaende-raa.md:121`;
  `docs/plan-1939-produktionsklar.md:46`; `docs/evidensbaseret-genimport/status.md:169-172`
- Påstand: Dokumentation, værktøj og ceremonier er dimensioneret som til et flerbrugersystem med mange læsere.
  Projektet er en PoC med én redaktør og ca. 1.800 personer.
- Evidens: Specs: 101 filer / 27.231 linjer. Planer: 132 / 92.665 linjer. `daa-extract/scripts` 112.813 linjer.
  17 runbooks. Decisions 3.514 linjer, changelog 4.473 (wc -l i EKS). 126 udestående punkter, heraf 42 "kendt
  begrænsning" og 21 "udskudt" (0d). 718 lokale baser / 14,6 GB (0d:121). Prod-overførslen af 5a+5b: 25
  genspilsskridt, digests over 21 lag, `FREEZE_BEGIN_OK`/`PREFLIGHT_OK`/D0/D1 (status.md:169-172).
  Pre-launch: "Data i basen er kun offentliggjort til brugeren selv" (plan-1939:46, 07-17). Det er ikke bekræftet
  siden.
- Konsekvens: Næste trin arver alle begrænsningerne. Det tager uforholdsmæssig tid at sætte sig ind i arbejdet,
  for både dig og agenter. Hvert lille datafix bliver en ceremoni (U44: fire ceremonier på én dag).
- Hvem besluttede: Hvert element blev besluttet lokalt, ofte af projektejeren. Ingen har besluttet den samlede
  proportion.
- Hvad kostede det: Ikke opgjort i dage. Det er størrelsesordenen i sig selv, der er fundet.
- Fremover: Find ud af, om prod reelt har eksterne læsere. Gør det ikke, så tillad en let gate for kanonisk
  skrivning: dump, script og efter-måling, uden pause og uden genspilsprøve.
- Sikkerhed: verificeret (tallene). At der ikke er eksterne læsere, er sandsynligt (beskrevet 07-17, ikke siden).

### 1a-13 — C3's "generiske" reimport-familie afhænger af 1939-navngivne hjælpere
- Område/trin: trin 1-3, editionsneutralitet · **Alvor: P3**
- Sted: `schema.sql:3507`, `:3524` (definitioner); brugt i `public.red_apply_reimport_cases`,
  `red_reverse_reimport_cases`, `red_preview_reimport_cases`, `red_authorize_reimport_cases`,
  `red_authorize_reimport_case_reversal` (schema.sql:8196-11641); `db-verify.sql:564-567`;
  `docs/superpowers/specs/2026-08-22-1939-v50-fase-c3-apply-design.md:25` (via 0b)
- Påstand: C3-familien blev besluttet som "ikke en 1939-specifik batchfamilie", men den kalder
  `private.reimport_1939_canonical_json_sha256` og `require_reimport_1939_editor`.
- Evidens: 24 forekomster i de fem funktioner, 27 i alt (awk over schema.sql). Til gengæld er `_1939`-navnerummet
  dokumenteret som et lukket kompatibilitetsnavnerum med allowlist (db-verify.sql:564-567, #153). Det tæller
  positivt.
- Konsekvens: En tredje årbog bruger 1939-navngivne objekter i sin fælles vej. Det er i strid med kriteriet for
  generalisering (målarkitektur:209-210).
- Hvem besluttede: Uklart.
- Hvad kostede det: Lidt, indtil trin 7.
- Fremover: Omdøb de to hjælpere til generiske navne ved trin 6 og lad 1939-navnene stå som wrappers.
- Sikkerhed: verificeret.

### 1a-14 — Døde beslutninger og planer står stadig som gældende
- Område/trin: tværgående · **Alvor: P3**
- Sted: `docs/decisions.md:3268`; `docs/plan-1939-produktionsklar.md:3`; `docs/flere-daa-udgaver-roadmap.md:3`;
  `docs/README.md:51`, `:53`
- Påstand: Flere prioriteringer og planer er aldrig blevet trukket tilbage i selve filen.
- Evidens: "Gemte rapporter/smart-lister: NÆSTE FOKUS" (07-03) blev aldrig bygget (grep: ingen implementering
  eller afløsning). `plan-1939-produktionsklar.md:3` "Status: Aktiv styringsplan", mens README:51 kalder den
  "Historisk plan … ikke gældende styring".
- Konsekvens: Små forvekslinger og ekstra læsning.
- Hvem besluttede: Projektejeren (07-03). Den manglende afløsning er uklar.
- Hvad kostede det: Ubetydeligt.
- Fremover: Én linje øverst i hver historisk fil, plus en afløsningspost for "næste fokus".
- Sikkerhed: verificeret.

### 1a-15 — Trin 4's restpunkter ligger stille, mens samme problem løses i et andet lag
- Område/trin: trin 4-5 · **Alvor: P3**
- Sted: `docs/decisions.md:497-500`; `docs/evidensbaseret-genimport/status.md:165-166`, `:271-273`
- Påstand: Titel-i-navn-problemet er lagt i en ventende promptversion (trin 4) og løses samtidig deterministisk
  som navneregel v3 (trin 5). Det er et dobbeltspor uden beslutning om, hvem der ejer reglen.
- Evidens: Restpunkterne fra 10-05 ("næste promptversion … titel/gods-reglen", "138 navne-assertions", "runnerens
  kvotefejl") er ikke lavet (0d:55, 57, 59). Navneregel v3 håndterer "titler inde i adelsnavne" (status.md:166).
- Konsekvens: To regler for det samme begreb kan give forskellige svar i trin 6.
- Hvem besluttede: Projektejeren (restpunkterne). Ejerskabet er uklart.
- Hvad kostede det: Endnu ikke noget.
- Fremover: Beslut før trin 6, hvilket lag der ejer navnereglen.
- Sikkerhed: verificeret.

## 5. Dom pr. område

| Område | Dom | Begrundelse |
|---|---|---|
| Styringsmodel (vision, roadmap, ét aktivt mål) | solidt men overbygget | Visionen og målarkitekturen er klare og gode. Disciplinen om ét aktivt mål holdt i oktober. Men regler (budget, afbrydelser, adgangskrav) blev besluttet uden at blive håndhævet |
| Beslutningsorakel (`status.md`, roadmappets status, decisions) | **hul** | Selvmodsigende og forældet netop der, hvor man skal orientere sig (1a-01). Decisions er grundig, men har ingen afløsningsmarkering (1a-07, 1a-08, 1a-14) |
| Fortrydelse og prod-overførsel | bør laves om | Restore-only plus overførsel bagefter har kostet ca. 1 uge pr. trin og gjort trin 4-5 reelt ufortrydelige (1a-04). 5c-1's form er bedre og bør gøres til standard |
| Kontrolmodel og menneskearbejde | solidt men overbygget | Overgangen fra fulde ark til afvigelser plus stikprøve var rigtig. Ceremonien omkring stikprøven står ikke mål med dens erklærede værdi (1a-10), og forudfyldning har givet en offentlig fejl (1a-11) |
| Reviewproces | solidt men overbygget | Reviewene fandt ægte fejl, men budgettet er brudt, og specs vokser af reviews (1a-05). Døde veje lever videre (1a-06) |
| Overgang fra legacy | **hul** | Den gamle indlæser er stadig den dokumenterede indgang (1a-02). 1939's august-spor skal genbesøges i trin 6 (1a-09) |
| Behovsdækning for læseren | **hul** | Trin 4's værdi er usynlig. Roadmappet har intet trin, der leverer den (1a-03) |

## 6. Læst fuldt

Fuldt (7):
1. `docs/reviews/2026-10-27-trin-1-5/beslutningskronologi.md` (1-553)
2. `docs/reviews/2026-10-27-trin-1-5/leverancetidslinje.md` (1-550)
3. `docs/evidensbaseret-genimport/vision.md`
4. `docs/evidensbaseret-genimport/roadmap.md`
5. `docs/evidensbaseret-genimport/status.md` (1-337)
6. `docs/evidensbaseret-genimport/teknisk-maalarkitektur.md`
7. `_issues.txt`

Sektioner (12): `docs/decisions.md` 1-50, 50-123, 196-215, 360-380, 435-460, 703-735, 795-835, 1335-1362,
1600-1660, 1786-1814, 2060-2075, 2768-2792, 3114-3136, 3255-3318; `_ledger-rulings.txt` 30-36;
`docs/reviews/2026-10-27-trin-1-5/udestaaende-raa.md` 1-12, 135-160; `…/maalinger.md` 40-72 og overskrifter;
`.claude/skills/daa-extract/SKILL.md` 40-70, 180-192; `docs/superpowers/specs/2026-10-11-trin5b-2b-i-…-design.md`
389-410; `…/2026-10-26-trin5c-…-design.md` 123-135; `…/2026-08-03-evidens-promotion-kontrakt-design.md` 11-20;
`relationspersonas-5b-navneregel-v3-bevis.md` 125-135; `schema.sql` 2055-2066, 5884-5900; `db-verify.sql`
555-567; `docs/flere-daa-udgaver-roadmap.md` 1-12; `docs/plan-1939-produktionsklar.md` 1-8.

I alt 19 enheder, under loftet på 40.

Vigtigste grep-søgninger: `load_daa` (CLAUDE.md, decisions, skill); `review-runde|runder|Codex-runde`
(decisions); `kun ved restore|restore-only|ingen fortryd` (decisions, changelog); `målarkitektur` (decisions);
`kontrolleret afbrydelse` (decisions); `smart-list|gemte rapporter` (docs); `pre-launch|go-live` (docs);
`UPDATE/DELETE FROM assertion` (schema.sql); funktionsnavne med `1939|2018|v50` (schema, migrations);
afhængigheder af `reimport_1939_canonical_json_sha256`/`require_reimport_1939_editor` (awk, schema.sql);
`fetchPersonDetail|from('fact')|family_sources` (web/src); `projection` (skill-scripts, tests, ci.yml);
`skal foreligge før` og `isoleret implementeret|relation_person_create` (beviser, overførselsspec);
filtællinger og `wc -l` for specs, plans og runbooks.

## 7. Hvad jeg ikke nåede

- `docs/changelog.md` er ikke læst selvstændigt. Jeg har brugt 0b's del 2 og 0e. Påstandene om D1 før GO-pakken
  og 1939-tekstkvalitet hviler på 0b.
- Om overførselsspec'en (10-21) håndterede 2b-i's "otte teoretiske risici", er ikke efterprøvet (1a-11).
- Om prod har eksterne læsere i dag, kan ikke afgøres fra eksporten (1a-12).
- Augusts ca. 40 1939-specs er kun vurderet via 0b. Jeg har ikke selv målt, hvor meget af dem trin 6 kan genbruge.
- U27-U30's formidlingsarbejde (feed, medier, præsens) er kun vurderet som "uden for trin 1-5". Om det var den
  rigtige prioritering for "er vi i familie?"-kernen, er ikke vurderet.
- Ugeomkostninger er udledt af PR- og commit-tællinger i 0e (squash fra U38), ikke af persondage.
