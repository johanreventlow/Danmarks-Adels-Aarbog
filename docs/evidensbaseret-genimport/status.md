# Evidensbaseret genimport — aktuel status

**Verificeret:** 2026-09-06 efter GO 1-4 i prod (#152-cutover, #153, 149a, 149b);
detaljer i `docs/changelog.md` 2026-09-05/06. **Prod opdateret 2026-09-17:** trin 4's skema og writere er deployet uden evidensdata —
se tillægget nedenfor. **Prod-data 2026-09-18:** 4.1c's klausuler kørt. **Afstemt
2026-09-23:** 4.4's prod-kørsel parkeret, 4.5 næste — se tillæg 2026-09-23. **4.5 kørt
2026-09-26** i restoren — se tillæg 2026-09-26. **Prod-data 2026-09-28:** 2018-20's klausuler
omsegmenteret (51 poster, `match`); samme dag er 4.4 genbundet i en lokal kopi — se tillæg
2026-09-28. **Kodestatus opdateret 2026-09-11**
efter merge af trin 4's dagsværk 4.1a-4.2 — se tillægget under Produktionsstatus.

**Kodegrundlag:** Task 12's funktionelle bevis er commit `4922d7e`; den
nuværende dokumentations-HEAD kan være senere og ændrer ikke det bevis

**Tillæg 2026-09-04:** 149b (2018-20 legacy-migration til narrativ-binding, #166)
er `integreret ende-til-ende`, se tabellen og blokeringerne; 149a
(2018-20 kilderegnskab) er `integreret ende-til-ende`, se tabellen; #156
lukket med restpunkt (INCOMPLETE-afstemning, snapshot forseglet).

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
| Proposed-ingest og promotion | Ingest: `integreret ende-til-ende` i restore. Promotion: kun bindingsdelen `integreret ende-til-ende` i restore (2026-09-26) | 4.4's writer har ingestet 243 forslag i en restore uden kanonisk delta; 4.5 afgjorde dem med projektejerens ark og bandt 43 til eksisterende assertions (`interpretation-pilot-2018-20.md`). Trin 4's promotion er en dokumenteret binding, ikke oprettelse af nye fakta (spec §8.3, åbent punkt 11.3). Intet er kørt mod prod: 4.4's GO-pakke er parkeret (tillæg 2026-09-23), og fuld kørsel afventer kontrolmodellens første kørsel (`decisions.md` 2026-09-27). |
| Source persona, identitetskandidater og webkø | `isoleret implementeret` | Moduler, databaseflader og redaktørkø findes, men den virkelige 1939-vej er parallel og bruger ikke denne fælles beslutningsvej. |
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

Roadmap-trin 1-3 (#152, #153, #149) er `produktionsverificeret` pr. 2026-09-06. Det
aktive programmål er **trin 4: den fælles fortolkningskæde og klausulgranularitet
(#147/#148)**, aktiveret af projektejeren 2026-09-06 (decisions samme dato, seks valg).
Spec: `docs/superpowers/specs/2026-09-06-trin4-fortolkningskaede-og-klausulgranularitet-design.md`.
Dagsværkene 4.1a-4.4 er **udført og merget**, skemaet er deployet til prod 2026-09-17, og
4.1c's klausuler er kørt i prod 2026-09-18. Næste tilladte arbejde er:

1. **Kontrolmodellen er bygget og kørt** (2026-09-27, gren `feat/147-kontrolmodel`); tilbage er
   uafhængigt kodereview og merge. Kandidat bagefter: promptregel for »var † [dato], da …«
   (ny promptversion — egen beslutning).
2. 4.5-arket er rettet (I-7) og godkendt med ny hash `c92a6e80…` (2026-09-27). Næste: projektejerens beslutning om 4.4's forslag og 4.5's afgørelser skal i prod samlet
   (prod-vej-spec på `docs/147-pilot-prod-vej`), og i så fald genbinding af 4.4's GO-pakke.
   Review 35's P3/P4/S4 er afgjort og bygget (#219, #220, #222), og omsegmenteringen er kørt i prod
   2026-09-28. Piloten er kørt om på de reviderede klausuler, og kontrolmodellen igen (2026-09-28,
   `genbind-44-pilot-2018-20.md`): 230 forslag, 46 bindinger. Næste: 4.4+4.5's prod-GO-pakke
   genbindes til disse forslag og afgørelser (egen GO; samme GO lukker omsegmenteringens
   fortrydelsesvindue).

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
