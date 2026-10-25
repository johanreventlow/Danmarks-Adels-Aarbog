# Evidensbaseret genimport — aktuel status

**Verificeret:** 2026-09-06 efter GO 1-4 i prod (#152-cutover, #153, 149a, 149b);
detaljer i `docs/changelog.md` 2026-09-05/06. **Prod opdateret 2026-09-17:** trin 4's skema og writere er deployet uden evidensdata —
se tillægget nedenfor. **Prod-data 2026-09-18:** 4.1c's klausuler kørt. **Afstemt
2026-09-23:** 4.4's prod-kørsel parkeret, 4.5 næste — se tillæg 2026-09-23. **4.5 kørt
2026-09-26** i restoren — se tillæg 2026-09-26. **Prod-data 2026-09-28:** 2018-20's klausuler
omsegmenteret (51 poster, `match`); samme dag er 4.4 genbundet i en lokal kopi — se tillæg
2026-09-28. **Hele 2018-20 kørt 2026-10-01—03** i en lokal kopi — se tillæg 2026-10-03.
**Prod-data 2026-10-05:** hele 2018-20's fortolkningskæde overført (3.739 forslag, 676
afgørelser, 622 bindinger, `VERIFY_OK`) — se tillæg 2026-10-05. **Samme dag:** trin 4
afsluttet for 2018-20 og trin 5 aktiveret (decisions 2026-10-05). **Trin 5a merget 2026-10-06
(#236) og 5b del 1 merget 2026-10-11 (#237)**, begge bevist i restore, ikke deployet.
**Prod-data 2026-10-25:** 5a+5b's data for 2018-20 overført (GO 2, `VERIFY_OK`) — se tillæg 2026-10-25.
**Kodestatus opdateret 2026-09-11**
efter merge af trin 4's dagsværk 4.1a-4.2 — se tillægget under Produktionsstatus.

**Kodegrundlag:** Task 12's funktionelle bevis er commit `4922d7e`; den
nuværende dokumentations-HEAD kan være senere og ændrer ikke det bevis

**Tillæg 2026-09-04:** 149b (2018-20 legacy-migration til narrativ-binding, #166)
er `integreret ende-til-ende`, se tabellen og blokeringerne; 149a
(2018-20 kilderegnskab) er `integreret ende-til-ende`, se tabellen; #156
lukket med restpunkt (INCOMPLETE-afstemning, snapshot forseglet).

**Tillæg 2026-10-25 — 5a+5b's data for 2018-20 er i prod.** DDL'en kom i prod 2026-10-22 (GO 1). Data-ceremonien
(`runbooks/transfer-5ab-data-prod.md`, plan B2) genspillede arbejdskørsel 3's pakke (`46f5d1e5…`, 25 skridt), optaget
på en restore af D1 og kontrolleret mod beviskæden, efter projektejerens GO 2. Første forsøg stoppede ved skridt 3
(`STATEMENT_TIMEOUT`, prods 2-minutters grænse) efter to skrevne skridt; den private runner sætter nu 15 min for
skridtets forbindelse, rettelsen blev bevist på en stand-in med samme grænse, og genspillet fortsatte fra skridt 3
under en ny GO 2 (`4bd78fa9…`). Udfald: `REPLAY_OK steps=25`, `VERIFY_OK` (alle nøglede digests = pakkens slut,
kanonisk baseline = D1's, `anon` uændret), rådgiveren uden nye fund, webtjek og skrivepausen afsluttet. Kilde 1:
252 nye bindinger (622 → 874; ét ægteskab forbliver forslag efter dubletreglen, decisions 2026-10-25), 245 nye
personas og identiteter, 0 nye personer. 5a og 5b er `produktionsverificeret` for 2018-20, undtagen oprettelse af
nye personer og #244's rettelsesvej.

**Tillæg 2026-10-05 — 2018-20's fortolkningskæde er i prod.** Pakken (`07355ccc…`, plan A) og
ceremonien (plan B, `runbooks/transfer-2018-20-prod.md`) blev først øvet mod lokale stand-ins af prod
og en læse-kun probe. Efter projektejerens GO kørte ceremonien samme dag: generalprøve på pausens
eget dump (`REHEARSAL_OK`), derefter i prod 3.739 forslag, 676 afgørelser og 622 bindinger med
`VERIFY_OK` (tilstand `COMPLETE`, alle tre digests lig pakken, baseline, uberørte tabeller og grants
uændret, `anon` uden adgang). Ingest og afgørelse er `produktionsverificeret` for 2018-20; promotion
kun for bindingsdelen (dokumenteret binding til eksisterende assertions, ingen nye fakta).
Omsegmenteringens fortrydelsesvindue er lukket; pausens dump er det nye restorepunkt.

**Tillæg 2026-10-03 — hele 2018-20 er kørt gennem kæden i én base.** I en lokal kopi af et frisk
prod-dump (2026-10-01) gav alle 488 tilladte poster 3.739 forslag, 74 kort for projektejeren (61 A, 0
R, 13 U), 602 maskinelle accepter og 622 bindinger, intet kanonisk delta
(`2018-20-fuld-koersel.md`). Pilotens 34 poster kom identiske tilbage fra cachen, og alle 46
pilotbindinger går igen. De 13 U er navne med titel eller godsbetegnelse i værdien (decisions
2026-10-03). **Intet i prod:** overførslen kræver sin egen spec, og omsegmenteringens
fortrydelsesvindue står åbent til den overførsels GO.

**Tillæg 2026-09-28 — 4.4 er genbundet: piloten kørt om på de omsegmenterede klausuler.** I en
lokal kopi af et frisk prod-dump gav de 34 poster 230 forslag, 24 kort for projektejeren (alle
accepteret), 26 maskinelle accepter og 46 bindinger, intet kanonisk delta
(`genbind-44-pilot-2018-20.md`). Første modelkørsel med P1's værn (`evidence-runner-1.3`): 0
værktøjsbrug. Runnerens nye regler og basens fakta er målt til nul forskel mod 4.5; den største kilde
til forskel er selve genkaldet (68 % af forslagene på uændrede poster går ordret igen). Prod-pakken
skal derfor bære netop disse forslag. Næste er 4.4+4.5's prod-GO-pakke (egen GO).

**Tillæg 2026-09-27 — kontrolmodellen er bygget og kørt én gang.** I en kopi af restoren med
4.5's forslag genafspillet gav den samme 43 bindinger som 4.5's fulde ark (identiske forslag og mål)
med 26 kort for projektejeren i stedet for 243; 23 forslag blev accepteret maskinelt
(`machine-corroboration-v1`). Begge kendte fejl lå blandt uoverensstemmelserne, som mennesket ser
(`kontrolmodel-koersel-2018-20.md`). Projektejeren fandt samtidig en fejl mere i 4.5 (I-7), så det
godkendte 4.5-ark er rettet og godkendt med ny hash (`c92a6e80…`), som bruges ved overførslen til prod.

**Tillæg 2026-09-26 — 4.5-piloten er kørt i restoren; kvaliteten holder, afgørelsesmodellen
ikke.** Hele kæden (klausuler → runner → ingest → afgørelse → binding) er kørt for 32 poster i
arbejdsbasen `daa45_pilot_20260924093200` (kopi af restoren), aldrig i prod
(`interpretation-pilot-2018-20.md`). 243 forslag, præcision 241/243 (rettet 2026-09-27; 1 fejl blandt 159
nye), ordrette datoer 52/52, 43 bindinger (61 % af de accepterede promoverbare), intet kanonisk
delta. Men projektejerens ark på 243 linjer tog flere dage, og ≈ 3.450 afgørelser for resten af
2018-20 er ikke gennemførligt. Dommen (godkendt 2026-09-27): kvalitet GO, fuld kørsel NO-GO med den
nuværende afgørelsesmodel. En ny kontrolmodel — kun uoverensstemmelser og en stikprøve — er
BESLUTTET i `decisions.md` 2026-09-27. Runneren er samtidig `evidence-runner-1.1` (datoer skal
stå ordret i den citerede klausul; review 35, P10).

**Tillæg 2026-09-23 — 4.4's prod-kørsel er klar, men parkeret.** GO-pakken for den første
`interpretation_proposal`-kørsel i prod er færdig: runbook
(`docs/runbooks/interpretation-proposal-prod-apply.md`), private scripts bundet af en
GO-hashfil, restore-rehearsal i normalt og fjendtligt miljø (`REHEARSAL_OK`, 30 fejlcases),
angrebssuite 29/29 og uafhængigt kodereview GO (draft-PR #215). Fortrydelse er restore af
dagens backup (spec 11.5 afgjort, `decisions.md` 2026-09-23). Projektejeren har samme dag
**parkeret selve kørslen og #196's DDL**, til 4.5 er bevist i restoren: 4.5 kræver ikke prod
(spec §8.2/§8.5), og forslag i prod har ingen værdi, før et menneske kan afgøre dem.
Genoptagelse kræver nyt prod-dump, ny rehearsal og nyt GO. Samme dag vedtaget:
review-budget og gater efter skrivningens konsekvens (`decisions.md`). Modenhedsrækkerne
flyttes ikke.

**Tillæg 2026-09-17 — trin 4's skema og writere er i prod, men ingen data.** Blokkene
4.1a, 4.1c, 4.2 og 4.4 er deployet efter preflight, backup, restore-rehearsal og
projektejerens GO (`docs/database-current-state.md` §8). Prod har nu klausullaget,
prædikat-navnerummet og begge writere — men **ingen writer er kørt mod prod**: 0
fortolkninger, 1488 observationer, uændret. Datakørslerne er fortsat gated (se Åbne
blokeringer). Modenhedsrækkerne flyttes ikke af et skemadeploy.

**Tillæg 2026-09-15 — trin 4's dagsværk 4.4 er lukket og merget.** Proposed-ingest er
bevist mod 4.3b's restore (manifest `a328ede9…`, runner-manifest `56a57a56…`, profil
`4e39fff4…`): 84 forslag, forventet fordeling nedskrevet før kørslen og ramt på alle otte tal.
`db-verify.sql` er grøn mod basen **med** de live rækker. Alle dagsværkets tasks er lukkede:
**Task 6** afgjort — reviewsignalet bor i menneskearket (spec §8.2-errata), ikke i en
`proposal_flags`-kolonne, se `decisions.md` — og **Task 8** rapporteret i
`proposal-ingest-147-4-4-rehearsal.md`. Merget som PR #192 (efter #191 med selve
writer-operationen), CI grøn på alle ti jobs.

**Pr. 2026-09-15 var koden i `main`, ikke i produktionsdatabasen** — skemaet er siden
deployet, se tillæg 2026-09-17. Restoren `daa43b_20260912192527` skal
bevares — 4.5 bruger den, fordi klausul-id'erne er database-genererede.

**Produktionsstatus:** C3 (2026-08-29), #152-cutover (kontrakt 2), #153's generelle
writer, 149a (591 records/forekomster/ankre) og 149b (541 publicerede + 46 kladde-bindinger)
er anvendt og efterverificeret i prod 2026-09-05/06. Trin 4's skema og writere (4.1a, 4.1c,
4.2, 4.4) er deployet 2026-09-17 — uden evidensdata.

**Tillæg 2026-09-11 — trin 4's dagsværk 4.1a-4.2 er `implementeret og merget`.**
#173, #174, #175, #176 og #177 er i `main` med grøn CI: klausullagets skema, den
deterministiske segmentering, `clause_evidence`-writeren og prædikat-navnerummet.
Hvert dagsværk er kørt mod en frisk restore af prod-dumpet, og 4.1c skrev 868
klausuler på 591 helposter **uden delta i det kanoniske lag**. Trin 4 har dermed
kode — men **stadig ingen prod-mutation**: prod-databasen har hverken
klausulkolonnerne, writeren eller prædikattabellen. Prod-GO er en selvstændig,
ustartet beslutning.

## Samlet dom

Værdigrundlaget og det generelle fundament er stærkt. 1939-proveniens og
narrativpublicering er en væsentlig delleverance, men den fælles kæde
observation → fortolkning → identitet → promotion → publicering er ikke
integreret ende-til-ende. Skabelonen for en fremtidig årbog er derfor ikke
færdig, og genimporten er samlet **NO-GO som generel leverance**.

## Aktivt programmål og stopport

C3 passerede 2026-08-29 sin tekniske stopport og blev derefter kørt i
produktion efter et særskilt GO. Apply-batch
`447d81a8-5c21-4b22-832e-e0d2a379a20c`, change set `966`, blev `finalized` og
bestod den uafhængige read-only postverification.

Det aktive programmål er nu #152. Det har en revideret, 2026-08-29 godkendt
designspecifikation, som gør den operationelle frysning, granulær
legacy-nedtagning og den midlertidige blokering af hel-person-sletning
eksplicit. Task 12 har derefter bevist kontrakten ende-til-ende i en syntetisk,
disponibel PostgreSQL-restore med reelle samtidighedsræs, klienttests og
browser-smoke. Task 13 har skrevet den særskilte production-runbook; der er
stadig ikke givet produktions-GO.

## Modenhed pr. værdikædeled

De eneste tilladte tilstande er `specificeret`, `isoleret implementeret`,
`integreret ende-til-ende` og `produktionsverificeret`.

| Værdikædeled | Tilstand | Afgrænsning og bevis |
| --- | --- | --- |
| 1939 source/rendition og recordproveniens | `produktionsverificeret` | En læse-kun produktionsmåling 2026-08-22 dokumenterede rendition, source records, occurrences, observationer og mentions for 1939. Tilstanden gælder denne afgrænsede leverance og er ikke genverificeret 2026-08-25. |
| 1939 narrativpublicering og kildebinding | `produktionsverificeret` | Den læse-kun måling 2026-08-22 dokumenterede den daværende bundne bestand; C3 postverify 2026-08-29 beviste yderligere fire eksakte production record-assignments. Det beviser en væsentlig 1939-delleverance, ikke den fælles genimportkæde. |
| Klausulgranularitet og coverage | `specificeret` | Helpost- og linjegrundlag findes, men den krævede mindste meningsbærende klausul og dens disposition er ikke implementeret ende-til-ende. |
| Extractor-runner og modelkald | `integreret ende-til-ende` for 2018-20, hovedpersonens persona, i restore (2026-09-26) | `evidence_runner.py` (`evidence-runner-1.1`) kalder modellen gennem `codex exec` bag en Seatbelt-grænse, validerer record-scoped claims (datoer skal stå ordret i den citerede klausul) og stopper fail-closed. Kørt på 34 virkelige poster fra 2018-20 (4.3b: 10, 4.5: 24): præcision 99-99,6 %, klausulbinding 100 %, ordrette datoer 100 % (`runner-rehearsal-147-4-3b.md`, `interpretation-pilot-2018-20.md`). Ikke kørt mod prod; sandbox-grænsens huller er review 35, P1. |
| Proposed-ingest og promotion | Ingest og afgørelse: `produktionsverificeret` for 2018-20 (2026-10-05). Promotion: kun bindingsdelen `produktionsverificeret` for 2018-20 (2026-10-05) | **2026-10-05:** hele 2018-20 overført til prod efter `runbooks/transfer-2018-20-prod.md`: 3.739 forslag, 676 afgørelser, 622 bindinger, `VERIFY_OK` med pakkens tre digests (tillæg 2026-10-05). Tidligere: 4.4's writer har ingestet 243 forslag i en restore uden kanonisk delta; 4.5 afgjorde dem med projektejerens ark og bandt 43 til eksisterende assertions (`interpretation-pilot-2018-20.md`). Trin 4's promotion er en dokumenteret binding, ikke oprettelse af nye fakta (spec §8.3, åbent punkt 11.3). Intet er kørt mod prod: 4.4's GO-pakke er parkeret (tillæg 2026-09-23), og fuld kørsel afventer kontrolmodellens første kørsel (`decisions.md` 2026-09-27). |
| Source persona, identitetskandidater og webkø | `produktionsverificeret` for 2018-20 (2026-10-25, GO 2; i restore 5a 2026-10-05, 5b del 1 2026-10-11) | Trin 5a: én identitetsvej — privat kerne med strukturel oprindelse og cutover, kandidatgenerator, hash-bundet identitetsark og webkø gennem samme RPC. Kalibrering (øvre grænse, 587 personas) og blind genbekræftelse (30 + webspor: 25 samme, 0 anden, 6 uafklaret) i [identitetsvej-5a-bevis.md](identitetsvej-5a-bevis.md). Ikke deployet; tre svagheder til 5b (samme_som-klynger, 1939-årstal, kandidatvisning). **Trin 5b del 1 (2026-10-11, #237; restore, ikke prod):** 234 ægtefælle-personas med kildebundne navne; maskinel bekræftelse (`family_corroboration`) kun efter en bestået blind kontrolkørsel — 30 ægtefællekort, 0 afvigelser, 173 bekræftet maskinelt, øvre 95 %-grænse ca. 13,9 % ([relationspersonas-5b-del1-bevis.md](relationspersonas-5b-del1-bevis.md)). Børn, uoverensstemmelser og nye personer er del 2. **I prod 2026-10-25 (GO 2)** efter `runbooks/transfer-5ab-data-prod.md` (tillæg 2026-10-25). |
| Relationsbindinger og kildevisning (5b del 2a, #151) | `produktionsverificeret` for 2018-20 (2026-10-25, GO 2; i restore 2026-10-11) | 203 maskinelt afgjorte ægteskaber + 7 accepterede forældrepåstande bundet til deres kanoniske familie (`structural_family`, 210 bindinger, manifest-digest = efter-digest), offentlig `public_family_sources` bag publicerings- og familiegaten (210 rækker), kildelinje i `DetailPanel`; 0 kanonisk delta, 4 negativtests i [relationspersonas-5b-2a-bevis.md](relationspersonas-5b-2a-bevis.md). **I prod 2026-10-25 (GO 2)** efter `runbooks/transfer-5ab-data-prod.md` (tillæg 2026-10-25). Rådgiveren (`08 data`) uden nye fund. |
| Ægtefælle-undtagelser, kø og genbinding (5b del 2b-i, #151) | `produktionsverificeret` for 2018-20 (2026-10-25, GO 2; i restore 2026-10-13) | De 31 ægtefæller fra 2a er afgjort: 22 via et hash-bundet undtagelsesark og 9 via webkøen (5 samme, 3 uafklaret, 1 ny person til 2b-ii). 3 ordinal-afvigelser er klassificeret `ordinal_beholdt`. 20 nye bindinger (i alt 230 kilderækker), og genbindingsvejen er bevist (negativtest D). 0 kanonisk delta. 7 ægteskaber fejler lukket på grund af dobbelte familier (#240). Se [relationspersonas-5b-2b-i-bevis.md](relationspersonas-5b-2b-i-bevis.md). **I prod 2026-10-25 (GO 2)** efter `runbooks/transfer-5ab-data-prod.md` (tillæg 2026-10-25). I prod blev ét ægteskab stående som forslag (252 bindinger, ikke 253): dubletreglen (5b §23.4) binder til laveste visningsplads; rettes før 1939 (decisions 2026-10-25). |
| Nye afdøde ægtefæller og klausul-disposition (5b del 2b-ii, #151) | `produktionsverificeret` for 2018-20 (2026-10-25, GO 2; i restore 2026-10-18) | Andet gennemløb (profil v2) over de 14 ægteskaber uden ægtefælle-persona med et hash-bundet ark: regelens forslag S 10/N 1/I 1/U 2, projektejerens svar S 2/U 12 (navneregel og klausulopdeling fejler på adelsnavne med titel inde i navnet — fund til næste runde). 2 nye bindinger (232 kilderækker), 0 nye personer (ingen D; oprettelsen af nye afdøde ægtefæller er derfor kun bevist på syntetiske data og forbliver `isoleret implementeret`, også efter GO 2), 122 klausuler disponeret efter identitet pr. aktør, 0 kanonisk delta, negativtest A-F afviser. Se [relationspersonas-5b-2b-ii-bevis.md](relationspersonas-5b-2b-ii-bevis.md). **I prod 2026-10-25 (GO 2)** efter `runbooks/transfer-5ab-data-prod.md` (tillæg 2026-10-25). |
| Navneregel v3 over 2b-ii's 12 `U` (5b del 2b-ii runde 2, #151) | `produktionsverificeret` for 2018-20 (2026-10-25, GO 2; i restore 2026-10-20) | Navneregel v3 (titler inde i adelsnavne, strammere partnertræf, løst dubletværn) over et hash-bundet ark: regel S 9/I 1/U 2, svar S 9/U 3; P-linjen (2b-i's `new_person_needed`) besvaret U, fordi fortolkningen er forkert; fortolkningen er afvist i bevisbasen 2026-10-20. 9 nye bindinger (241 kilderækker), 9 klausuler disponeret, 0 kanonisk delta, negativtest A og C afviser. **0 nye personer: oprettelsen er stadig kun bevist syntetisk.** Fund: ægteskabsnummeret bliver forkert ved klausulopdelingsfejl (4 falske `ordinal_afvigelse`; separat runde). Se [relationspersonas-5b-navneregel-v3-bevis.md](relationspersonas-5b-navneregel-v3-bevis.md). **I prod 2026-10-25 (GO 2)** efter `runbooks/transfer-5ab-data-prod.md` (tillæg 2026-10-25). |
| Børnehenvisninger (5b del 2b-iii, #151) | `produktionsverificeret` for 2018-20 (2026-10-25, GO 2; i restore 2026-10-20) | De 14 `relation.child` er krydshenvisninger til hele børneflokke (erratum til hovedspecen §22.9). Reglen `relation-child-v1` binder flokken til forælderens familie, når bogens antal, postnumre, slægtled, linje/kuld og køn passer. Hash-bundet ark for alle 12, der opfylder reglen: 12 bindinger (253 kilderækker), 12 børnekilder synlige for læseren, 0 kanonisk delta, negativtest A-D afviser. 2 står `proposed` (flok i to ægteskaber; ingen hovedperson). Fund: trykfejl i bogen (»9 børn«, nr. 2-9). Se [relationspersonas-5b-2b-iii-bevis.md](relationspersonas-5b-2b-iii-bevis.md). **I prod 2026-10-25 (GO 2)** efter `runbooks/transfer-5ab-data-prod.md` (tillæg 2026-10-25). |
| Ægteskabsnumre (#244, 5b) | Nummereringen: `produktionsverificeret` for 2018-20 (2026-10-25, GO 2; i restore 2026-10-20). Rettelsesvejen: `isoleret implementeret` | `relation_marriage_ordinals` nummererer nu efter skriverens ordvindue (årsagen var en parentes midt i klausulen, ikke en overskreden klausulgrænse). Værn: skriveren afviser, når bogens »g. N°« modsiger nummeret. 4 skæve numre (2 poster, byttet 1↔2) rettet via et hash-bundet ark med 4 linjer og `red_ret_aegteskabsnummer`, genbundet i samme familie (4 genbindinger, 253 kilderækker). 0 kanonisk delta, `family_member.ordinal` uændret, negativtest 6/6 afviser. De 4 skæve numre opstod aldrig i prod: arbejdskørslen regenererede persona-manifesterne med rigtige numre, så `red_ret_aegteskabsnummer` er deployet, men ubrugt, og genbindingen med `supersedes` er ikke øvet i prod (decisions 2026-10-25). Se [aegteskabsnumre-244-bevis.md](aegteskabsnumre-244-bevis.md). **I prod 2026-10-25 (GO 2)** efter `runbooks/transfer-5ab-data-prod.md` (tillæg 2026-10-25). |
| Id'er af indholdet (#151, forudsætning for overførslen af 5a+5b) | `i prod` (DDL 2026-10-22, GO 1; data 2026-10-25, GO 2) | 8 rækkearter med id af indholdet (`private.content_uuid`): ægtefællepersona, omtale, identitetshændelse, kandidatkørsel, kandidat, kontrolkørsel, stikprøve og forældrekort; kollision fejler lukket (`DETERMINISTIC_ID_COLLISION`). Kontrolstikprøven trækkes og vises efter indhold (`control-sample-v2`/`control-display-v2`, erratum til 5b §23.3). Arkværktøjerne er uden tilfældige id'er (2b-i's `O`-linjer på fortolkningsnøgle og version, kontrakt `spouse-exception-rows-v2`; v3-arket uden dato) og sorterer med `COLLATE "C"`. Hovedtesten (to baser med forskellig collation, tidszone og forhistorik) var rød mod den gamle kode og er grøn; opgradering fra prods træ `140a17b` er grøn. Deployet i DDL-ceremonien (GO 1); data-ceremonien (GO 2) genspillede med de samme id'er (`VERIFY_OK`). |
| DDL-ceremonien for 5a+5b (overførslen, plan A, #151) | `i prod` (DDL, 2026-10-22, GO 1) | Fase 0 (`FREEZE_BEGIN_OK`, `PREFLIGHT_OK`), D0 verificeret ved restore, rehearsal på netop D0 (`REHEARSAL_OK`: idempotens, fire afbrud, fortrydelse `0\|16`), `DDL_OK` (tilstand `PRE`, `DATA_DELTA_OK changed=3 new=12`), `DDL_VERIFY_OK advisors=ok` og D1 verificeret. Skrivepausen fortsætter; plan B (data, GO 2) skrives mod D1. 5a's 31 kalibreringsafgørelser overføres ikke (decisions 2026-10-21). |
| Værktøj til data-ceremonien for 5a+5b (overførslen, plan B1, #151) | `i prod` (brugt i GO 2, 2026-10-25) | Nøglekort og nøglede digests over 21 lag (rækketilstand og diagnose af uoversatte uuid'er), uberørt-hash med andre kilder og værn; skridt-SQL for profil, afgør, bind, disposition, afvisning, kandidater, kontrol og korroboration med nøglede items og hashes genberegnet i basen; køens ark (port af 2b-i's private kø-anvendelse), svaroverførsel via nøgler og pakkeformatet `transfer-pack-5ab-v1`. Bevis: capture i én base og replay i en anden med andre tilfældige id'er, collation og tidszone giver ens digests; pakken genspillet på en tredje base, inkl. genoptagelse efter afbrud (CI: `writer-1939-v50-db` og `python`). Brugt i plan B2's ceremoni (næste række). |
| Data-ceremonien for 5a+5b (overførslen, plan B2, #151) | `i prod` (data, 2026-10-25, GO 2) | Arbejdskørsel 3 på en ICU-restore af D1 (`PACK_OK` `46f5d1e5…`, `CONTENT_OK same=8827 allowed=51` efter afgørelse A), genspilsprøve (`REHEARSAL_OK`) og GO 2-filen `4bd78fa9…`. I prod: første forsøg stoppede ved skridt 3 (`STATEMENT_TIMEOUT`; prods 2-minutters grænse, 4.4's G7) efter to skrevne skridt; rettelsen (15 min for skridtets forbindelse) blev bevist på en stand-in med samme grænse, og genspillet fortsatte fra skridt 3: `REPLAY_OK steps=25`, `VERIFY_OK measure_sha256=92a609f5…`, `ADVISORS_DATA_OK nye=0`, webtjek, `FREEZE_END_OK`. Kilde 1: 252 nye bindinger (622 → 874), 245 nye personas, 0 nye personer. |
| Placement og membership | `isoleret implementeret` | Skema og fundament findes, men de eksisterende personer føres fortsat ikke gennem placement-/membership-datavejen. |
| 2018-20-proveniens (149a) | `produktionsverificeret` (2026-09-06) | 2026-09-03: hele kæden bevist mod den rigtige bog og mod en restore af prod-dumpet migreret til kontrakt v2: PDF `3beadfc1…`, rå tekst `2dd5cf84…`, manifest `c7d19c01…` (591 elementer) → 1 rendition / 591 records / 591 forekomster / 591 ankre, nul kanonisk delta (5 aggregat-hashes), `anon` uændret (9 hashes), replay `already_applied`, reversal fail-closed (`docs/evidensbaseret-genimport/source-evidence-149a-rehearsal.md`). Krævede rettelse af #153's migrationsguard (finalized terminal ved 0 person_creates). Ikke `produktionsverificeret`; prod-rækkefølge #152 → #153 (med guard-rettelsen) → 149a. Bindinger er nu leveret af 149b (#166), se næste række. |
| 2018-20 narrativ-binding (149b, #166) | `produktionsverificeret` (2026-09-06) | 2026-09-04: legacy-migration-writeren bevist mod samme restore, oveni 149a: manifest `b4baa1ae…`/`662f16f3…`, profil `954f3bb3…`, preview `774efc5b…` → 587 elementer, 541 `bound_published`, 46 `bound_draft`, 4 `unresolved_text` (`I-133, II-35, III-129, IV-94`), 0 `unresolved_identity`; ledger source 1 = 541 `migrated` + 3 `grandfathered_publication` + 0 `withdrawn`; 587 `source_persona` + 587 accepterede identiteter; offentlig v2-flade viser 541 `source_record` og kun 3 `legacy_narrative` for source 1 (fra 544); nul kanonisk delta (4 aggregat-hashes) og `anon` uændret (8 hashes); replay `already_applied`; per-narrativ reversal gendanner begge streams eksakt; batch-reversal kun dry-run (587 elementer, `committed=false`); `red_reverse_reimport` afvist (`REIMPORT_WRITER_REVERSAL_INVALID`) (`docs/evidensbaseret-genimport/legacy-migration-149b-rehearsal.md`). Krævede en rettelse af #152's læsefunktioner (gate + record-gren filtrerer nu på bindingsstatus, ellers dublet efter fuld fortrydelse). Ikke `produktionsverificeret`: prod-apply kræver #152-cutover → #153 (guard-rettelsen) → 149a i prod, projektejerens kvittering for valg A (identitet uden placement-kæde) og valg B (reversal-designet), samt en frisk neutralitetsmåling (`withdrawn` binding ∧ `grandfathered` ledger = 0) i prod før apply. |
| C3 atomisk apply | `produktionsverificeret` | Production batch `447d81a8-5c21-4b22-832e-e0d2a379a20c` / change set `966` blev finalized med 5 identity-, 4 assign- og 2 no-publication-events og bestod eksakt read-only postverify. |
| C3 reversal | `integreret ende-til-ende` | Separat reversal er bevist mod en frisk, produktionsafledt disposable restore med eksakt gendannet domænetilstand; den er ikke udført i produktion. |
| #152 record-nøglede person-narrativer | `produktionsverificeret` (2026-09-06) | Den editionsneutrale record-kontrakt med append-only publication-versioner, stale-gate, granulær legacy-withdrawal, grandfathered legacy-ledger og stabil offentlig source-record-reference er bevist i Task 12's syntetiske, disponerbare restore, reelle DBI-ræs, fulde klient-/server-suiter og browser-smoke. Den aktive frysning af nye bindinger/DAA-import og `red_slet_person`-blokken er fortsat bevidst design, ikke en åbning af gamle writers. Ingen production cutover eller produktions-GO er givet. |
| Tredje-årbogsprøve | `specificeret` | Prøven er generaliseringsbeviset efter begge referenceudgaver; den er ikke gennemført. |

Den afgrænsede #152-kontrakt er `integreret ende-til-ende`; den fælles
flerudgavekæde er fortsat ikke integreret ende-til-ende, og C3 er en afgrænset
1939-korrektionskæde. `produktionsverificeret`
ovenfor er afgrænset til de målte 1939-delleverancer 2026-08-22 og løfter ikke
programmets samlede modenhed.

## Væsentlige leverancer

- 1939 har et kildebundet provenance- og narrativpubliceringslag, verificeret
  ved læse-kun produktionsmåling 2026-08-22.
- Den generelle evidensmodel, append-only audit, identitets-, promotion- og
  publiceringsfundament er væsentligt stærkere end den oprindelige minimumsplan.
- C3 har hashbundne, fail-closed byggeklodser for preview, menneskelig
  tekstgodkendelse, atomisk apply, separat reversal og commit-unknown-håndtering.
- C3's samlede Task 9-rehearsal har bevist 5 identitetshændelser, 4 narrative
  tildelinger og 2 `no_publication`-hændelser som ét 11-hændelsesforløb med
  eksakt reversal.
- C3 production apply gentog det autoriserede 11-event-scope og bestod
  uafhængig efterverifikation af receipt, eventhashes, identitetsrelationer,
  narrative teksthashes, bindinger, no-publication-fravær og change-set-scope.
- Den menneskeverificerede 1939-segmentering er et stærkt udgavespecifikt
  resultat, men er ikke et bevis for en fælles flerudgavemetode.

## Fundament uden fuld anvendelse

- Fortolknings- og promotionlaget findes, men ingen reel extractor-runner
  udfylder det.
- Source-persona-modulerne og webkøen findes, men den reelle 1939-identitetsvej
  er fortsat parallel.
- Placement-, membership- og lineage-overflader findes, men er ikke den
  aktive datavej for den eksisterende bestand.
- 2018-20 har profil- og pilotforberedelse, men ikke source records,
  rendition-proveniens eller en gennemført fælles kæde.

## Åbne blokeringer

- **Trin 4's første data er i prod (4.1c, 2026-09-18).** 591 records og 868 klausuler
  skrevet i én `finalized` batch, afstemt med klausul-projektionen (`match`, uændrede
  neutrale lister, intet kanonisk delta). Procedure og bevis:
  `docs/runbooks/clause-evidence-prod-apply.md` og changelog 2026-09-18. Fortrydelsesvinduet
  er åbent, indtil projektejeren lukker det. **4.4's `interpretation_proposal` i prod er
  parkeret** (tillæg 2026-09-23): fortolknings-projektionen (#196) er merget, fortrydelse
  er afgjort som restore, og GO-pakken er færdig, men kørslen og #196's DDL venter på 4.5's
  pilotrapport. **Tillæg 2026-09-27:** venter nu også på, at 2018-20's klausuler segmenteres om
  med en ny writer-operation (review 35 P3/P4/S4; `decisions.md` 2026-09-27). P4 er gjort.
  **Tillæg 2026-09-27 (aften):** P3 og S4 er implementeret og merget (#222: klausulsæt,
  `clause_revision`, S4) og øvet mod et frisk prod-dump med `REHEARSAL_OK` — 51 poster revideret,
  fortrudt og kørt frem igen, alle `match`, intet kanonisk delta
  (`omsegmentering-rehearsal-2018-20.md`). **Tillæg 2026-09-28: kørt i prod** efter
  `docs/runbooks/clause-revision-prod-apply.md` (tre review-runder af operatørpakken, læse-kun prøve
  i prod, rehearsal af dagens dump): 51 poster revideret, 116 klausuler skrevet, 197 `erstattet`,
  komparatoren `match`, intet kanonisk delta (`database-current-state.md` §9). Fortrydelse er en ny
  revision (07), vinduet er åbent.
- **4.5 er kørt i restoren (2026-09-26)**; fuld kørsel er NO-GO med den nuværende
  afgørelsesmodel (menneskelig kapacitet), se tillæg 2026-09-26 og `decisions.md` samme dato.
  4.3a's Codex-forbrugsprobe er **kørt 2026-09-11** og lukket: `codex exec --json`
  rapporterer forbrug i `turn.completed`, så spec §6.6's stopbetingelse for 4.3 er ikke
  udløst. Proben målte samtidig, at ~21,5k input-tokens er fast CLI-overhead pr. kald —
  batchstørrelsen i §6.4 er derfor bærende for økonomien, ikke en optimering
  (`runner-usage-probe-147-4-3a.md`).
- Den eksisterende åbne tombstone-/retentionsbeslutning betyder, at #152 fortsat
  blokerer hel-person-sletning for personer med publication-events; granulær
  withdrawal løser kun offentlig nedtagning af den enkelte biografi.
- Den fælles kæde mangler fortsat klausulobservationer, reel extraction,
  proposed-ingest, én identitetsvej, promotion i drift og publicering med
  kildehenvisning på tværs af referenceudgaverne; trin 4 leverer de tre første for
  2018-20 (hovedpersonens persona), trin 5 identitetsvejen, trin 6 begge udgaver.
- Restpunkter fra GO 4: de fire `unresolved_text`-records (`I-133`, `II-35`, `III-129`,
  `IV-94`) og 13 mulige `NOISE_RE`-prosalinjer er uændrede; `get_advisors` skal
  tjekkes i Supabase-dashboardet.

## Næste tilladte arbejde

Roadmap-trin 1-3 (#152, #153, #149) er `produktionsverificeret` pr. 2026-09-06. **Trin 4**
(#147/#148) er afsluttet for 2018-20 2026-10-05: kæden er overført til prod med `VERIFY_OK`
(tillæg 2026-10-05). Det aktive programmål er nu **trin 5: placement/membership og én
identitetsvej (#150/#151)**, aktiveret af projektejeren 2026-10-05 (decisions samme dato), i
rækkefølgen 5a → 5b → 5c. 5a er merget 2026-10-06 (#236) og 5b del 1 2026-10-11 (#237); begge er
bevist i restore ([identitetsvej-5a-bevis.md](identitetsvej-5a-bevis.md),
[relationspersonas-5b-del1-bevis.md](relationspersonas-5b-del1-bevis.md)); 5a+5b's data for 2018-20 er i prod
2026-10-25 (GO 2, tillæg 2026-10-25). Næste tilladte arbejde er:

0. **Efter GO 2 (#151):** dubletreglen (5b §23.4) rettes før 1939 (DDL; decisions 2026-10-25), #240 og #248,
   derefter 5c. Før trin 6: Fable-review af trin 1-5 (konsistens og kodekvalitet) med de udestående punkter.

1. **5b del 2 (#151):** brainstorm → spec-tillæg → plan for børn (§22.9), de 31
   uoverensstemmelser, nye personer, familiekorrektion (`F`-kort), `samme_som` for dubletter,
   udtrækkets fejllæsning af »(F.: …)« og final reviews M1-M10 (især M1: registreringen skal udelukke
   kerne-afviselige personas). Listen står i bevisrapportens sidste afsnit; bevisbasen
   `daa5b_bevis_20261010093638` bevares til del 2. Prod-deploy af 5a/5b: GO 1 (DDL) 2026-10-22 og GO 2 (data) 2026-10-25.
2. **Restpunkter fra trin 4 (egne opgaver):** næste promptversion (»var †«-reglen og
   titel/gods-reglen; erstatter de 13 `U`-kort), oprydning af 138 navne-assertions med
   titelord, runnerens håndtering af Codex' nye kvotefejl.

Trin 4's afsluttede forløb, til historik:

- **Kontrolmodellen** er bygget, kørt og merget (2026-09-27, #217).
- 4.5-arket er rettet (I-7) og godkendt med ny hash `c92a6e80…` (2026-09-27).
- Review 35's P3/P4/S4 er afgjort og bygget (#219, #220, #222), og omsegmenteringen er kørt i
  prod 2026-09-28. Piloten er kørt om på de reviderede klausuler, og kontrolmodellen igen
  (2026-09-28, `genbind-44-pilot-2018-20.md`): 230 forslag, 46 bindinger. Piloten overføres ikke
  for sig (decisions 2026-10-01).
- Hele 2018-20 (488 poster) er kørt i en restore af et frisk prod-dump (2026-10-01—03,
  `2018-20-fuld-koersel.md`): 3.739 forslag, 622 bindinger. Den samlede overførsel er kørt i prod
  2026-10-05 (`VERIFY_OK`), og omsegmenteringens fortrydelsesvindue er dermed lukket.

Prod-mutationer kræver fortsat en udtrykkelig GO pr. apply.

## Parkeret arbejde

`[NY]`, C1, C2, nye 1939-specialfaser samt spor H og M er fortsat parkeret.
Roadmapmål #152's mobilændring er kun den minimale sikre migration, som kræves
for at lukke den gamle writer; den genåbner ikke det fulde mobilredaktørspor.

## Bevisgrundlag og friskhed

- Funktionelt kodegrundlag: commit `cc9d7d5`; intervallet
  `2f64b7b..cc9d7d5` dokumenterer C3-implementeringen efter
  afvigelsesvurderingen.
- [Task 9-rehearsalrapporten 2026-08-29](c3-task9-rehearsal-2026-08-29.md)
  dokumenterer backupafgrænsning, restore/migration, artefakthashes,
  testsuiter, apply/reversal-receipts og den tekniske stopport.
- [C3 production-apply-rapporten](c3-production-apply-2026-08-29.md)
  dokumenterer backuphash, migrationshashes, autoriserede artefakter,
  production receipt og read-only postverify.
- [Den reviderede #152-spec](../superpowers/specs/2026-08-29-narrative-source-record-key-design.md)
  beskriver det aktive programmål og dets produktionsgrænser.
- [Task 12-rehearsalrapporten](narrative-record-key-152-rehearsal.md)
  dokumenterer det konkrete ende-til-ende-bevis, herunder disposable restore,
  reelle samtidighedsræs, fulde suiter, browser-smoke og read-only reviews.
- [#152-cutover-runbooken](../runbooks/narrative-record-key-cutover.md)
  fastholder den separate, hash- og identitetsbundne production-gate.
- [Vision og værdigrundlag](vision.md), [styrende roadmap](roadmap.md) og
  [teknisk målarkitektur](teknisk-maalarkitektur.md) fastlægger henholdsvis
  værdier, prioritet og ønsket systemadfærd.
- [Trin 5a's færdigbevis](identitetsvej-5a-bevis.md) og [trin 5b del 1's
  færdigbevis](relationspersonas-5b-del1-bevis.md) dokumenterer identitetsvejen og den
  maskinelle familiebekræftelse i restore (ikke prod).
- [Afvigelsesvurderingen 2026-08-22](../superpowers/reviews/2026-08-22-evidensbaseret-genimport-afvigelsesvurdering.md)
  er grundlag for de seneste anvendte produktionsmålinger; de er ikke
  genverificeret 2026-08-25.
- [Den aktuelle C3-plan](../superpowers/plans/2026-08-22-1939-v50-c3-atomisk-apply.md)
  er grundlag for C3's implementerede dele, afsluttede tekniske Task 9-bevis,
  lokale integration og produktionsstop.

Historiske specs, planer og reviews er bevis og historik, ikke selv aktuel
programstatus. Levende kode og schema er source of truth for tekniske detaljer,
mens driftfølsomme produktionsforhold kræver en frisk, udtrykkeligt autoriseret
kontrol.

## Opdateringsregel

Der skal oprettes et nyt evidensafstemt snapshot ved afslutningen af en
roadmapfase og før en ny genimportplan, hvis gren, kode eller
produktionsforhold har ændret sig væsentligt. Snapshotet må kun hæve modenhed,
når det krævede konkrete bevis er gennemført og dateret; ellers bevares den
lavere, fail-closed klassifikation.
