# Evidensbaseret genimport — aktuel status

**Verificeret:** 2026-08-29 efter C3 production apply og postverify

**Kodegrundlag:** lokal `main` ved `7b5dc5a`; #152 er foreløbig kun en
docs-only designbranch

**Produktionsstatus:** C3's eksakte fem-sagers scope er migreret, anvendt og
efterverificeret i produktion; #152 har ingen produktionsmutation

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

Det aktive programmål er nu #152. Det er `specificeret` i en revideret og
2026-08-29 godkendt designspecifikation, som efter eksternt review også gør den
operationelle frysning, granulær legacy-nedtagning og den midlertidige blokering
af hel-person-sletning eksplicit. Godkendelsen åbner kun for en
implementeringsplan. Planen er nu udarbejdet og afventer review; der er ikke
givet kode- eller produktions-GO til #152.

## Modenhed pr. værdikædeled

De eneste tilladte tilstande er `specificeret`, `isoleret implementeret`,
`integreret ende-til-ende` og `produktionsverificeret`.

| Værdikædeled | Tilstand | Afgrænsning og bevis |
| --- | --- | --- |
| 1939 source/rendition og recordproveniens | `produktionsverificeret` | En læse-kun produktionsmåling 2026-08-22 dokumenterede rendition, source records, occurrences, observationer og mentions for 1939. Tilstanden gælder denne afgrænsede leverance og er ikke genverificeret 2026-08-25. |
| 1939 narrativpublicering og kildebinding | `produktionsverificeret` | Den læse-kun måling 2026-08-22 dokumenterede den daværende bundne bestand; C3 postverify 2026-08-29 beviste yderligere fire eksakte production record-assignments. Det beviser en væsentlig 1939-delleverance, ikke den fælles genimportkæde. |
| Klausulgranularitet og coverage | `specificeret` | Helpost- og linjegrundlag findes, men den krævede mindste meningsbærende klausul og dens disposition er ikke implementeret ende-til-ende. |
| Extractor-runner og modelkald | `specificeret` | Kontrakter, profiler og validator findes; `evidence_extract.py` kalder bevidst ingen model, og ingen bog er kørt gennem den fælles extractor-kæde. |
| Proposed-ingest og promotion | `isoleret implementeret` | Skema, regler, RPC'er og tests udgør et fundament, men ingen reel extractor-kørsel føder kæden. `project_evidence.R` er fortsat dry-run og ikke en integreret promotionvej. |
| Source persona, identitetskandidater og webkø | `isoleret implementeret` | Moduler, databaseflader og redaktørkø findes, men den virkelige 1939-vej er parallel og bruger ikke denne fælles beslutningsvej. |
| Placement og membership | `isoleret implementeret` | Skema og fundament findes, men de eksisterende personer føres fortsat ikke gennem placement-/membership-datavejen. |
| 2018-20-proveniens | `specificeret` | Fase A-ækvivalent provenance er besluttet, men ikke gennemført. |
| C3 atomisk apply | `produktionsverificeret` | Production batch `447d81a8-5c21-4b22-832e-e0d2a379a20c` / change set `966` blev finalized med 5 identity-, 4 assign- og 2 no-publication-events og bestod eksakt read-only postverify. |
| C3 reversal | `integreret ende-til-ende` | Separat reversal er bevist mod en frisk, produktionsafledt disposable restore med eksakt gendannet domænetilstand; den er ikke udført i produktion. |
| #152 record-nøglede person-narrativer | `specificeret` | Godkendt, editionsneutralt design med append-only publication-versioner, stale-gate, granulær legacy-withdrawal, grandfathered legacy-ledger og stabil offentlig source-record-reference. Den målte frysning af nye bindinger/DAA-import og den midlertidige `red_slet_person`-blokering er accepteret som designpræmis; ingen implementering endnu. |
| Tredje-årbogsprøve | `specificeret` | Prøven er generaliseringsbeviset efter begge referenceudgaver; den er ikke gennemført. |

Ingen af de fælles flerudgaveled er aktuelt klassificeret som `integreret
ende-til-ende`; C3 er en afgrænset 1939-korrektionskæde. `produktionsverificeret`
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

- #152-implementeringsplanen afventer review før kodearbejde.
- Den friske production-måling mangler fortsat; væsentlig drift fra den
  godkendte overgangsomkostning kræver ny projektejerbeslutning ved den senere
  production-gate.
- Den eksisterende åbne tombstone-/retentionsbeslutning betyder, at #152
  foreløbig må blokere hel-person-sletning for personer med publication-events;
  granulær withdrawal løser kun offentlig nedtagning af den enkelte biografi.
- #152 mangler implementation, disposable databasebevis, klientmigration og
  et eventuelt senere særskilt production-GO.
- Den fælles kæde mangler fortsat klausulobservationer, reel extraction,
  proposed-ingest, én identitetsvej, promotion i drift og publicering med
  kildehenvisning på tværs af referenceudgaverne.

## Næste tilladte arbejde

Næste tilladte handling er review af
[#152-implementeringsplanen](../superpowers/plans/2026-08-29-narrative-source-record-key-implementation.md).
Ingen kode- eller #152-produktionsmutation er autoriseret.

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
  beskriver det aktive programmål i modenheden `specificeret`.
- Commitintervallet `cc9d7d5..2e015df` ændrer kun styringsdokumentation og
  ændrer derfor ikke den funktionelle klassifikation.
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
