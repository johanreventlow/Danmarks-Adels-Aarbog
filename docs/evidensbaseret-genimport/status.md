# Evidensbaseret genimport — aktuel status

**Verificeret:** 2026-08-25
**Kodegrundlag:** `cc9d7d5` for funktionel C3-implementering; senere dokumentationscommits ændrer ikke den funktionelle klassifikation
**Produktionsstatus:** Ikke genverificeret i denne dokumentationsopgave; seneste anvendte måling er dateret 2026-08-22

## Samlet dom

Værdigrundlaget og det generelle fundament er stærkt. 1939-proveniens og
narrativpublicering er en væsentlig delleverance, men den fælles kæde
observation → fortolkning → identitet → promotion → publicering er ikke
integreret ende-til-ende. Skabelonen for en fremtidig årbog er derfor ikke
færdig, og genimporten er samlet **NO-GO som generel leverance**.

## Aktivt programmål og stopport

Det eneste aktive programmål er at afslutte C3 ved den planlagte samlede
integration, disposable rehearsal og stop før produktion. Stopporten er enten
et dokumenteret `READY_FOR_PRODUCTION_GO` eller en fail-closed blocker. En
opnået stopport er ikke produktions-GO og autoriserer ingen
produktionsmutation.

## Modenhed pr. værdikædeled

De eneste tilladte tilstande er `specificeret`, `isoleret implementeret`,
`integreret ende-til-ende` og `produktionsverificeret`.

| Værdikædeled | Tilstand | Afgrænsning og bevis |
| --- | --- | --- |
| 1939 source/rendition og recordproveniens | `produktionsverificeret` | En læse-kun produktionsmåling 2026-08-22 dokumenterede rendition, source records, occurrences, observationer og mentions for 1939. Tilstanden gælder denne afgrænsede leverance og er ikke genverificeret 2026-08-25. |
| 1939 narrativpublicering og kildebinding | `produktionsverificeret` | Den læse-kun måling 2026-08-22 dokumenterede publicerede recordbindinger. Det beviser en væsentlig 1939-delleverance, ikke den fælles genimportkæde. |
| Klausulgranularitet og coverage | `specificeret` | Helpost- og linjegrundlag findes, men den krævede mindste meningsbærende klausul og dens disposition er ikke implementeret ende-til-ende. |
| Extractor-runner og modelkald | `specificeret` | Kontrakter, profiler og validator findes; `evidence_extract.py` kalder bevidst ingen model, og ingen bog er kørt gennem den fælles extractor-kæde. |
| Proposed-ingest og promotion | `isoleret implementeret` | Skema, regler, RPC'er og tests udgør et fundament, men ingen reel extractor-kørsel føder kæden. `project_evidence.R` er fortsat dry-run og ikke en integreret promotionvej. |
| Source persona, identitetskandidater og webkø | `isoleret implementeret` | Moduler, databaseflader og redaktørkø findes, men den virkelige 1939-vej er parallel og bruger ikke denne fælles beslutningsvej. |
| Placement og membership | `isoleret implementeret` | Skema og fundament findes, men de eksisterende personer føres fortsat ikke gennem placement-/membership-datavejen. |
| 2018-20-proveniens | `specificeret` | Fase A-ækvivalent provenance er besluttet, men ikke gennemført. |
| C3 atomisk apply/reversal | `isoleret implementeret` | Preview, manifester, tekstgodkendelse, batchledger, apply, reversal, gateway og writer-lock er langt implementeret. Task 9's samlede integration, disposable rehearsal og stopport er ikke dokumenteret færdige. |
| Tredje-årbogsprøve | `specificeret` | Prøven er generaliseringsbeviset efter begge referenceudgaver; den er ikke gennemført. |

Ingen af de fælles flerudgaveled er aktuelt klassificeret som `integreret
ende-til-ende`. `produktionsverificeret` ovenfor er afgrænset til de målte
1939-delleverancer 2026-08-22 og løfter ikke programmets samlede modenhed.

## Væsentlige leverancer

- 1939 har et kildebundet provenance- og narrativpubliceringslag, verificeret
  ved læse-kun produktionsmåling 2026-08-22.
- Den generelle evidensmodel, append-only audit, identitets-, promotion- og
  publiceringsfundament er væsentligt stærkere end den oprindelige minimumsplan.
- C3 har hashbundne, fail-closed byggeklodser for preview, menneskelig
  tekstgodkendelse, atomisk apply, separat reversal og commit-unknown-håndtering.
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

- C3 mangler Task 9's reelle integrations- og fejlindsprøjtningstests, samlede
  suites og dokumenterede disposable apply/reversal-rehearsal.
- Den kendte schema/migration-paritetsdrift for den ældre
  `ensure_reimport_1939_source_evidence`-signatur skal lukkes eller
  fail-closed dokumenteres under Task 9, før den krævede restore-migration kan
  bestå.
- Der foreligger ingen dokumenteret C3-stopport og intet nyt eksplicit
  produktions-GO.
- Den fælles kæde mangler fortsat klausulobservationer, reel extraction,
  proposed-ingest, én identitetsvej, promotion i drift og publicering med
  kildehenvisning på tværs af referenceudgaverne.

## Næste tilladte arbejde

Kun C3 Task 9's resterende integration, disposable rehearsal og stop før
produktion er tilladt: gennemfør de planlagte integration-/concurrency- og
failure-injection-beviser, de fokuserede og fulde suites, den beskyttede
disposable restore/migration, rollback rehearsal samt committed disposable
apply og reversal med eksakt efterkontrol. Stop derefter og rapportér enten
`READY_FOR_PRODUCTION_GO` eller en fail-closed blocker. Dette arbejde giver
ikke produktions-GO og stopper før enhver production apply.

## Parkeret arbejde

`[NY]`, C1, C2, nye 1939-specialfaser, spor H og M samt alle efterfølgende
roadmapmål er parkeret, indtil C3 har nået stopporten eller projektejeren
udtrykkeligt ændrer prioriteringen. Der åbnes ikke et nyt genimportspor fra
dette snapshot.

## Bevisgrundlag og friskhed

- Funktionelt kodegrundlag: commit `cc9d7d5`; intervallet
  `2f64b7b..cc9d7d5` dokumenterer C3-implementeringen efter
  afvigelsesvurderingen.
- Commitintervallet `cc9d7d5..2e015df` ændrer kun styringsdokumentation og
  ændrer derfor ikke den funktionelle klassifikation.
- [Vision og værdigrundlag](vision.md), [styrende roadmap](roadmap.md) og
  [teknisk målarkitektur](teknisk-maalarkitektur.md) fastlægger henholdsvis
  værdier, prioritet og ønsket systemadfærd.
- [Afvigelsesvurderingen 2026-08-22](../superpowers/reviews/2026-08-22-evidensbaseret-genimport-afvigelsesvurdering.md)
  er grundlag for de seneste anvendte produktionsmålinger; de er ikke
  genverificeret 2026-08-25.
- [Den aktuelle C3-plan](../superpowers/plans/2026-08-22-1939-v50-c3-atomisk-apply.md)
  er grundlag for C3's implementerede dele, åbne Task 9-arbejde og
  produktionsstop.

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
