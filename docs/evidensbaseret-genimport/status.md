# Evidensbaseret genimport — aktuel status

**Verificeret:** 2026-08-30 efter #152 disposable ende-til-ende-rehearsal

**Kodegrundlag:** Task 12's funktionelle bevis er commit `4922d7e`; den
nuværende dokumentations-HEAD kan være senere og ændrer ikke det bevis

**Tillæg 2026-09-03:** 149a (2018-20 kilderegnskab) er `integreret ende-til-ende`, se tabellen og blokeringerne; #156 lukket med restpunkt (INCOMPLETE-afstemning, snapshot forseglet).

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
| Extractor-runner og modelkald | `specificeret` | Kontrakter, profiler og validator findes; `evidence_extract.py` kalder bevidst ingen model, og ingen bog er kørt gennem den fælles extractor-kæde. |
| Proposed-ingest og promotion | `isoleret implementeret` | Skema, regler, RPC'er og tests udgør et fundament, men ingen reel extractor-kørsel føder kæden. `project_evidence.R` er fortsat dry-run og ikke en integreret promotionvej. |
| Source persona, identitetskandidater og webkø | `isoleret implementeret` | Moduler, databaseflader og redaktørkø findes, men den virkelige 1939-vej er parallel og bruger ikke denne fælles beslutningsvej. |
| Placement og membership | `isoleret implementeret` | Skema og fundament findes, men de eksisterende personer føres fortsat ikke gennem placement-/membership-datavejen. |
| 2018-20-proveniens (149a) | `integreret ende-til-ende` | 2026-09-03: hele kæden bevist mod den rigtige bog og mod en restore af prod-dumpet migreret til kontrakt v2: PDF `3beadfc1…`, rå tekst `2dd5cf84…`, manifest `c7d19c01…` (591 elementer) → 1 rendition / 591 records / 591 forekomster / 591 ankre, nul kanonisk delta (5 aggregat-hashes), `anon` uændret (9 hashes), replay `already_applied`, reversal fail-closed (`docs/evidensbaseret-genimport/source-evidence-149a-rehearsal.md`). Krævede rettelse af #153's migrationsguard (finalized terminal ved 0 person_creates). Ikke `produktionsverificeret`; prod-rækkefølge #152 → #153 (med guard-rettelsen) → 149a. Bindinger er 149b (#166). |
| C3 atomisk apply | `produktionsverificeret` | Production batch `447d81a8-5c21-4b22-832e-e0d2a379a20c` / change set `966` blev finalized med 5 identity-, 4 assign- og 2 no-publication-events og bestod eksakt read-only postverify. |
| C3 reversal | `integreret ende-til-ende` | Separat reversal er bevist mod en frisk, produktionsafledt disposable restore med eksakt gendannet domænetilstand; den er ikke udført i produktion. |
| #152 record-nøglede person-narrativer | `integreret ende-til-ende` | Den editionsneutrale record-kontrakt med append-only publication-versioner, stale-gate, granulær legacy-withdrawal, grandfathered legacy-ledger og stabil offentlig source-record-reference er bevist i Task 12's syntetiske, disponerbare restore, reelle DBI-ræs, fulde klient-/server-suiter og browser-smoke. Den aktive frysning af nye bindinger/DAA-import og `red_slet_person`-blokken er fortsat bevidst design, ikke en åbning af gamle writers. Ingen production cutover eller produktions-GO er givet. |
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

- **#153's migrationsguard afviste 1939 fase A-batchen** (`finalized`, 0 person_creates,
  kan aldrig aktiveres) — bekræftet i prod læse-kun 2026-09-03. Rettet generelt på
  `feat/149-2018-20-fase-a` (evidensbundet undtagelse + tests, bevist mod dumpet).
  Rettelsen SKAL indgå i #153's prod-migration; #153's `afventer-prod-GO` gælder
  først med den.
- #152 afventer en særskilt, frisk produktions-GO efter
  [cutover-runbooken](../runbooks/narrative-record-key-cutover.md). Først
  kræves preliminær autorisation, mode-0600 backup/restore-rehearsal og frisk
  production-inventory; derefter kan et final-GO binde release-SHA, udløb,
  backup- og artifact-hashes, databaseidentitet og et eksternt writer-traffic
  hold fra apply gennem bestået postverify. Væsentlig drift fra den 2026-08-29
  godkendte konsekvens kræver ny projektejerbeslutning.
- Den eksisterende åbne tombstone-/retentionsbeslutning betyder, at #152
  foreløbig må blokere hel-person-sletning for personer med publication-events;
  granulær withdrawal løser kun offentlig nedtagning af den enkelte biografi.
- #152 mangler kun den særskilte production-gate og et eventuelt senere,
  eksplicit production-GO; integrationen er ikke `produktionsverificeret`.
- Den fælles kæde mangler fortsat klausulobservationer, reel extraction,
  proposed-ingest, én identitetsvej, promotion i drift og publicering med
  kildehenvisning på tværs af referenceudgaverne.

## Næste tilladte arbejde

Næste tilladte handling er en projektejer-review af
[#152-cutover-runbooken](../runbooks/narrative-record-key-cutover.md) med en
frisk, læse-kun production-inventory. Ingen #152-produktionsmutation er
autoriseret uden en ny udtrykkelig GO.

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
