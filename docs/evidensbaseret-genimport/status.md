# Evidensbaseret genimport — aktuel status

**Verificeret:** 2026-09-06 efter GO 1-4 i prod (#152-cutover, #153, 149a, 149b);
detaljer i `docs/changelog.md` 2026-09-05/06. **Prod opdateret 2026-09-17:** trin 4's skema og writere er deployet uden evidensdata —
se tillægget nedenfor. **Kodestatus opdateret 2026-09-11**
efter merge af trin 4's dagsværk 4.1a-4.2 — se tillægget under Produktionsstatus.

**Kodegrundlag:** Task 12's funktionelle bevis er commit `4922d7e`; den
nuværende dokumentations-HEAD kan være senere og ændrer ikke det bevis

**Tillæg 2026-09-04:** 149b (2018-20 legacy-migration til narrativ-binding, #166)
er `integreret ende-til-ende`, se tabellen og blokeringerne; 149a
(2018-20 kilderegnskab) er `integreret ende-til-ende`, se tabellen; #156
lukket med restpunkt (INCOMPLETE-afstemning, snapshot forseglet).

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
| Extractor-runner og modelkald | `isoleret implementeret` (2026-09-12) | `evidence_runner.py` kalder en model gennem `codex exec` bag en OS-håndhævet Seatbelt-grænse, validerer record-scoped claims, fører forbrugsregnskab og stopper fail-closed på hver fejltype. Kørt ende til ende på én opdigtet post (`runner-rehearsal-147-4-3a.md`), og derefter på **ti virkelige poster fra 2018-20** (`runner-rehearsal-147-4-3b.md`, 2026-09-13): 86 claims, **99 % præcision, 100 % klausulbinding, 100 % ordrette datoer**, ingen udeladelser noteret. Modellen udtrækker altså sande, kildebundne fakta af ægte DAA-prosa. **Promotion mangler stadig** (4.4-4.5), og to fund skal lukkes først: et `relation.*`-claim uden identificerbar modpart (»NN.«, »4 sønner«) og et claim, der er mere præcist end kilden (valgte ét år ud af et tvetydigt spænd). |
| Proposed-ingest og promotion | `isoleret implementeret` (uændret 2026-09-15) | **Ingest-halvdelen er nu født af en reel modelkørsel**, men rækken dækker også promotion, som er urørt. 4.4 (`interpretation_proposal`) skrev 2026-09-14 4.3b's 84 claims som `proposed` i en restore: 8 elementer, 68 `principal` / 16 `other`, 19 klausuldispositioner (13 `fortolkning_foreslaaet`, 6 `afventer_identitet`), nul kanonisk delta, `anon` uberørt (strukturelt bevist), replay `already_applied`, negativ test `REIMPORT_WRITER_PRINCIPAL_WITHOUT_PERSONA` bestået. **Modenheden hæves ikke — men grunden er nu en anden.** Dagsværket er lukket og merget (PR #192; Task 6 afgjort og Task 8 rapporteret 2026-09-15, se `proposal-ingest-147-4-4-rehearsal.md`), så det er ikke længere grenens status, der holder rækken tilbage. Det er, at rækken også dækker **promotion**, hvor `project_evidence.R` fortsat er dry-run og ikke en integreret promotionvej — og at ingesten aldrig har kørt mod andet end en restore. Prod-fortrydelse for operationen er stadig ikke designet (åbent punkt 11.5). |
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
  er åbent, indtil projektejeren lukker det. **Næste datakørsel** er 4.4's
  `interpretation_proposal`, som fortsat mangler en fortolknings-projektion (#196) og ikke
  har nogen prod-fortrydelse (spec åbent punkt 11.5).
- **4.5 mangler plan.** 4.3a, 4.3b og 4.4 er kørt og merget; 4.5 (pilot, afgørelse,
  binding) er næste dagsværk og bruger restoren `daa43b_20260912192527`.
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
Dagsværkene 4.1a-4.4 er **udført og merget**, og skemaet er deployet til prod 2026-09-17.
Næste tilladte arbejde er ét af to, og projektejeren afgør hvilket:

1. **Plan 4.5** — pilot, menneskets afgørelse og binding, mod restoren.
2. **Trin 4's første datakørsel i prod: 4.1c** — kvittering, klausul-projektion og
   prod-runbook (`docs/runbooks/clause-evidence-prod-apply.md`) er på plads; udestår
   kørslens egen gate (preflight, backup, restore-rehearsal) og projektejerens GO.

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
