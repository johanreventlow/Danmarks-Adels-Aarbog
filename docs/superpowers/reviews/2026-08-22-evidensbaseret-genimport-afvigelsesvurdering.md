# Evidensbaseret genimport — afvigelsesvurdering mod den oprindelige plan

**Dato:** 2026-08-22 · **Branch:** `feat/evidensbaseret-genimport` (493 commits siden merge-base `3117836`)
**Grundlag:** spec `2026-08-02-evidensbaseret-genimport-og-multislaegt-design.md`, plan `2026-08-02-evidensbaseret-genimport-og-multislaegt.md`, fem uafhængige læse-kun kodeaudits (fase 1-2, 3, 4, 5-6, 7-9) og en læse-kun måling af prod 2026-08-22.
**Beslutninger 2026-08-22 (brugeren):** fortolkningslaget SKAL fyldes; 2018-20 SKAL have fase A-ækvivalent; fase-pakke-gaten vedtaget. Issues #147-#158. Se `docs/decisions.md` øverst.
**Formål:** Fastholde hvad der blev planlagt, hvad der blev bygget, og for hvert udestående afgøre: *savnes* (skal laves), *bedre end planlagt* (planen opdateres), eller *droppet scope* (skal besluttes eksplicit). Dokumentet er anti-creep-ankeret: intet nyt spor startes uden at stå her.

---

## 1. Hovedkonklusion

Programmet skiftede retning omkring 2026-08-06 uden at skrive det ned. Planen beskrev **ét** produkt: bred, granulær udtrækning af to bøger til et observationslag, fortolkning, identitetsafklaring uden gæt, og forfremmelse til kanonisk model — i en parallel database med én samlet cutover. Det byggede produkt er **et provenance-lag for 1939 lagt oven på de gamle loader-data**: 592 kilderecords med byte-ankre, 577 narrativer erstattet med renset kildetekst, 559 publicerede bindinger, staged 835 → 7.

Det byggede er **bedre end planen på ét punkt** (menneskeverificeret segmentering frem for LLM-segmentering — planen undervurderede postgrænse-problemet, som spec §3 ellers forudså) og **stærkere end planen i DB-fundamentet** (fase 1-2). Det er **ikke bedre** på programmets kerne: fortolkningslaget er tomt, ingen bog er udtrukket under fælleskontrakten, 2018-20 er uberørt, og kæden observation → fortolkning → kanonisk er afbrudt i begge ender.

**Dommen:** Det praktiske ærinde (fejlbehæftede 1939-tekster) er løst godt. Det designede ærinde (evidensbaseret genimport) er ikke nået og er ikke erstattet af noget tilsvarende. Det skal enten genoptages eller eksplicit droppes — det må ikke blive ved med at være "under vejs".

## 2. Prod-måling 2026-08-22 (læse-kun)

| Lag | Rækker | Betydning |
|---|---|---|
| `private.source_record` / `_occurrence` / `source_observation` / `source_mention` | 592 / 897 / 897 / 897 | Observation = hel post (gns. 297-778 tegn, max 3.931). Mention er 1:1-kopi af observationen. Ingen klausulgranularitet. |
| `private.source_rendition` | 1 (`daa-1939-calamari-r6-clean`) | Kun Calamari. PDF-tekstlag ikke bevaret som rendition. |
| Records pr. kilde | 1939: 592 · 2018-20: 0 | Referencebogen aldrig rørt. |
| `private.interpretation` / `_promotion` / `_promotion_rule` | 0 / 0 / 5 | Fortolkningslaget er tomt. Regler findes, aldrig brugt. |
| `private.source_persona` / `_identity` / `_identity_event` | 8 / 8 / 8 | Kun de 8 nyoprettede personer. |
| `private.source_record_placement` / `public.person_*_membership` | 0 / 0 | Slægtled og medlemskab ligger stadig i `person_external_id` / `lineage`. |
| `public.slaegt` / `lineage_scheme` / `_entry` | 1 / 3 / 8 | Modellen er seedet, ikke brugt af visningskæden. |
| `private.narrative_record_publication` | 559 published | **Den reelle leverance.** |
| `private.reimport_1939_*` | 4 tabeller | Udgavespecifikke — bryder spec-invariant 12. |
| `public.person` (staged) / `fact` / `family` / `haendelse` | 1.811 (7) / 7.197 / 682 / 0 | Kanoniske data = juli-loaden (`load_daa.R`, urørt) + D1/D2-publicering. |

## 3. Plan-task for plan-task

| Task | Planlagt | Bygget | Dom |
|---|---|---|---|
| 2 Evidenskontrakt | Dataklasser, JSON-skema, 12 tests, svær fixture, CI | Dataklasser + 23 tests + CI-job ✅. JSON-skemaer dekorative (loades ikke). **Fixturen er tom** (1 observation, ingen af de 7 svære tilfælde). | Delvist — fixturen **savnes** (§7.1) |
| 3 Klausul-ledger | Mindste meningsbærende klausul, fuld tegndækning | Ledger pr. *tekstlinje*; dækning triviel. `record_key` altid `None`, placements altid `[]`. | Forsimplet — klausulniveau **savnes** (§7.2) |
| 4 Privat kildelag | 11 tabeller, append-only, låst schema, anchor-RPC | 11 tabeller ✅, append-only-triggere ✅, dblink-samtidighedstest ✅, kildescope-triggere (bonus). Accept i trigger, ikke RPC (stærkere). TRUNCATE ikke blokeret. Global `REVOKE EXECUTE` default (planen advarede). | **Bedre end planlagt** m. to fund (§7.8, §7.9) |
| 5 Fortolkning/identitet DDL | Append-only versionslog, deferred constraints, SECURITY DEFINER | Alt ✅ + owner-only provenance-check + promotion-regler/-batch (bonus). | **Bedre end planlagt** |
| 6 Slægt/lineage/scheme | DDL, Reventlow som slægt, inventar, kompat-view, core-typer | DDL ✅ (sammensatte FK'er, bonus), inventar ✅, view ✅, core ✅. Reventlow seedet som `'historical'`; membership-tabeller skrives aldrig; slægtsnavn afledes stadig af legacy; `red_person_grid` bruger `max(slaegtled_lokal)`. | Skelet uden data — **savnes** (§7.4) |
| 7 Web lineage-scope | `LineageContext`, kollisionstest | ✅ web. Mobil ikke (uden for task). | Som planlagt |
| 8-9 Heraldik (spor H) | Tabel, relationer, RPC, UI | Tabel + RLS + core-typer. Ingen RPC, UI, blasoneringsmigration. | Udskudt som tilladt — versioneret tabel uden skrivevej (§7.10) |
| 10 Identitetskandidater | `IdentityCandidate`, injectivitet, remap | ✅ modul + 11 tests. **0 konsumenter.** 1939 bruger egen kandidatbygger. | Dødt modul (§7.5) |
| 11 Redaktørkø | 4 RPC'er, webkø | ✅ DB hærdet, UI 7/7 tests. **Aldrig brugt.** Detail mangler spans/modstrid; historik-RPC kaldes ikke. | Ubrugt parallelspor (§7.5) |
| 12 Mobil (spor M) | Paritet | Ikke påbegyndt. | Udskudt som tilladt |
| 13 Extraction | Profiler, batches, validator, **LLM-udtræk** | Profiler ✅ (terra/sol låst), manifest ✅, validator ✅. **Ingen model-kald** (docstring: "deliberately does not call a model"). Aldrig kørt mod en bog. Prædikatvokabular matcher ikke promotion-reglerne. Hofstilling/erhverv/dekoration ikke adskilt (§7.3). | **Kernen savnes** (§7.1) |
| 14 Promotion (erstattet 08-03) | Konservativ binding til eksisterende assertion, 5 prædikater | DB + RPC'er + CI-job ✅. Intet indlæser `proposed`; ingen UI/script kalder promotion. `project_evidence.R` = dry-run-stub. | Bygget, afkoblet (§7.1) |
| 15 Kildeversioner | `BioSourceVersion`, sikker RPC, legacy-adapter | ✅ DB + core + web + mobil. Kanonisk resumé mangler. **Én narrativ pr. person pr. udgave** → spec §11 ("tre opslag i samme bog = tre tekster") strukturelt umuligt. Legacy-ledger (mapped/retained/archived/unresolved) findes ikke. | Delvist — §11 **savnes** (§7.6) |
| 16 2018-20 pilot | 30+10 records, LLM-kørsel, review, projektion | 40 records materialiseret, profil pinnet. **Stoppet før modelkørsel** (08-04). | Ikke reelt startet (§7.1) |
| 17 Fuld 2018-20 | 591 poster, placement-/narrativ-ledger, GO 2018-A/B | Intet. | **Droppet uden beslutning** (§7.1) |
| 18 1939 tekstbeslutning | Rendition-valg | ✅ Calamari R6 frosset, SHA-låst. | Som planlagt |
| 19 1939 pilot | Stratificeret kørsel under fælleskontrakt, GO 1939-A | NO-GO 08-04; aldrig genforelagt. | Erstattet (§4) |
| 20 Fuld 1939 | Ny udtrækning, placements, narrativ-ledger, GO 1939-B | Erstattet af v50: menneskesegmentering + gamle Terra-fakta + narrativ-erstatning. | Erstattet — fakta-delen **savnes** (§4, §7.1) |
| 21 Cutover-rehearsal | Parallel DB fra nul, gammel↔ny sammenligning, rollback-test | Pr.-fase restore-rehearsal + backup. Ingen parallel DB, ingen sammenligning, ingen restore-and-old-app-reads-it-test. | Gate omdefineret (§5) |
| 22 GO/NO-GO-pakke | Samlet pakke før prod | Fase-pakker (A, B, D2, C0f). Task 25-apply 08-18 og D1 uden pakke. | Gate omdefineret (§5) |

## 4. Hvad v50-sporet leverede i stedet (og hvorfor det var rigtigt)

1939-pilotens NO-GO (08-04) viste at postgrænser — ikke tegn-OCR — var den dominerende fejlkilde. Grænsekontrol fase 1 målte 101 poster uden spænd og 46.015 ejerløse tegn. Pivoten til hele Calamari-teksten i én tekstboks med markørlinjer gav 651 menneskeverificerede skæringer og 68/68 trykte postnumre dækket. Det *er* spec §17's "OCR-/segmenteringspilot først" — bare manuel frem for maskinel, og det var bedre end planens antagelse.

Derfra: reconciliation v31→v50 (592 records), task 25 production writer, fase A (kilderegnskab), B (narrativ-erstatning + `narrative_norm_v1`), C0 + efterkørsel (koblinger), D1/D2 (publicering). Alt med hash-låste manifester, restore-rehearsal og backup (undtagen §5-fundene).

**Det v50 ikke gjorde:** udtrække fakta under fælleskontrakten. 1939's 1.078 literal facts og 212 ægteskaber er fortsat Terra-kørslen fra juli, genbrugt mod v50-verbatim. C1 (promover dem som kildebundne assertions) blev udskudt 08-19 med begrundelsen "fortolkningslaget er tomt" — hvilket er cirkulært: laget er tomt fordi ingen udfylder det.

## 5. Gates: omdefineret, ikke respekteret

Planens fem menneskelige gates (2018-A, 2018-B, 1939-A, 1939-B, cutover-rehearsal → GO/NO-GO) blev ingen af dem givet i deres definerede form. Erstatningen — fase-pakke med backup + restore-rehearsal + hashes + brugergodkendelse → ét apply — er en *anden risikomodel*: fortrydelse afhænger af `change_set` (dækker ikke `narrative_record_publication`) eller dump-restore, og der findes ingen uafhængig gammel↔ny sammenligning.

To prod-skrivninger er ikke auditerbare fra repoet: task 25-apply 08-18 (readiness-dokumentet kl. 02:40 siger NO-GO; changelog siger "apply tidligere på dagen") inkl. DDL-deploy af hele det private lag, og D1 (kørt ved opfundet `--dryrun`-flag). Det er dokumenteret i memory og changelog, men hører med her.

Fase-pakke-modellen skal enten vedtages som den gældende prod-gate (og skrives i `docs/decisions.md`) eller forkastes. Den må ikke arves stiltiende.

## 6. Spec-invarianter: hvilke holder

| # | Invariant | Holder? |
|---|---|---|
| 1 | Originalen uforanderlig | ✅ rendition SHA-låst, append-only |
| 2 | Kildeudsagn ≠ slutninger (lag) | ⚠️ lagene findes, men fortolkningslaget er tomt — i praksis to lag (kilde + kanonisk), ikke fire |
| 3 | Ingen evidens uden anker | ✅ for narrativer (897 byte-ankre); ❌ for fakta (Terra-fakta har `citat_tekst`, ikke observations-ankre) |
| 4 | Ingen tavse tab (klausulregnskab) | ❌ intet klausulregnskab; linjeledger kun i segmenter-sidecar |
| 5 | Ingen tvungen sikkerhed | ✅ i 1939-reviewene (fail-closed `UAFKLARET`) |
| 6 | Én fysisk person kanonisk | ⚠️ via `samme_som` (465 links), ikke via persona-identitet |
| 7 | Ingen automatisk identitetsgæt | ✅ overholdt (eneste automatik, `source_persona.py`, kaldes ikke) |
| 8 | Kildenarrativer bevares separat | ⚠️ pr. udgave ja; pr. opslag nej (§7.6) |
| 9 | Slægt/linje/nummerering adskilt | ✅ i DDL; ❌ i datavej |
| 10 | Indgiftning ≠ medlemskab | ✅ DDL-håndhævet; membership dog tom |
| 11 | Kanonisk model konservativ | ✅ |
| 12 | Alt nyt er generelt | ❌ `reimport_1939_*`, `red_*_1939_v50_*` |
| 13 | Slægtled = kontekst | ✅ ingen generation-kolonne på person (db-verify) |
| 14 | Forekomstanker ≠ personanker | ✅ |
| 15 | Våben = selvstændige entiteter | ⏸ udskudt |

## 7. Udestående — med dom og anbefaling

Hvert punkt har en af tre domme. **Savnes** = planen havde ret, vi vil mangle det. **Beslut** = ægte valg, som skal træffes eksplicit (ikke glide). **Teknisk gæld** = skal lukkes uanset retning.

### 7.1 Fortolkningslaget er tomt, og ingen vej fylder det — *BESLUTTET 2026-08-22: savnes → #147*
Ingen extractor kalder en model; intet script indlæser `proposed`-fortolkninger; promotion v1 kan kun binde til allerede eksisterende assertions; vokabularerne (`life_event.birth` vs. `person.birth`) matcher ikke. Uden dette er "nye klassifikationer uden nyt grundudtræk" (spec §20) ikke opnået, og 2018-20 kan ikke genimporteres evidensbaseret. **Hvad vi vil savne:** indgiftedes oplysninger (§13), embeder/hofstilling/uddannelse/rejser som strukturerede fakta (§7.3), kildebundne ægteskaber, og muligheden for at en fremtidig forskningsidé kan besvares fra observationslaget. **Anbefaling:** Afgør om dette er programmets mål. Hvis ja: byg extractor-runneren (Task 13's manglende led) + `proposed`-ingest + vokabular-mapping, og kør 2018-20-piloten (Task 16 trin 3) som første reelle test. Hvis nej: skriv det i `decisions.md`, og arkivér Task 13-14-koden som "kontrakt uden runner".

### 7.2 Observationer er helposter, ikke klausuler — *Savnes → #148*
Spec §5 og §15.1. Uden klausulniveau kan en fortolkning ikke pege på et præcist kildeudsnit, og klausulregnskabet ("hver klausul får én disposition") kan ikke føres. Hvis 7.1 besvares "ja", er dette forudsætningen; hvis "nej", er helpost-niveauet tilstrækkeligt til narrativ-provenance og punktet bortfalder.

### 7.3 2018-20 er uberørt — *BESLUTTET 2026-08-22: fase A-ækvivalent → #149*
Halvdelen af scope. Planen ville bruge 2018-20 til at *fryse metoden* (pålideligt tekstlag, 591 kendte record keys). Nu er metoden frosset på 1939 i stedet, hvilket er det sværere tilfælde — ikke i sig selv forkert. Men 2018-20's 591 narrativer har ingen kildebinding, ingen source records og ingen rendition. **Anbefaling:** Mindst fase A-ækvivalent for 2018-20 (records + ankre + bindinger) bør gennemføres, så begge udgaver har samme provenance-niveau; ellers er "kildeversioner" i UI asymmetriske. Fuld udtrækning følger 7.1.

### 7.4 Identitet, slægtled og medlemskab for de ~1.800 eksisterende personer ligger i legacy-kolonner — *Savnes → #150*
Persona-, placement- og membership-tabellerne er skeletter. Task 17/20 trin 3-4 (migrér `slaegtled_*`/`kuld` til placement med positiv header-observation; ledger pr. legacy-række) er ikke udført, og dispositionerne `mapped/retained_legacy/archived_by_editor/unresolved` er ikke modelleret. Konsekvens: multi-slægt-modellen er en mulighed, ikke en tilstand; slægtsnavn afledes stadig af `lineage.slaegtsnavn`; `red_person_grid` bruger `max(slaegtled_lokal)`. **Anbefaling:** Planlæg som egen fase efter 7.1/7.3-beslutningen — men ledgeren for legacy-rækker kan bygges nu uden extraction.

### 7.5 To identitetsveje — *Beslut → #151*
Webkøen (Task 11) og `source_persona.py` (Task 10) er bygget og ubrugte; al ægte identitet gik via lokale token-/HTML-ark i `work/` + batch-writer der skriver `accepted` direkte (spec §6.2 siger ingest må kun skrive `proposed`). Den lokale vej er *strengere* (byte-låst, fail-closed) men audit-sporet i DB er kun en hash + batch-udførerens navn, og menneskets afgørelse ligger i gitignorerede filer. **Anbefaling:** Vælg én: (a) lad den lokale vej skrive `proposed`, som webkøen bekræfter (giver DB-audit med redaktør som aktør), eller (b) afvikl webkøen som PoC og dokumentér token-fil-vejen som den gældende. Ikke begge.

### 7.6 Én narrativ pr. person pr. udgave — *Savnes → #152*
`red_upsert_narrativ` er nøglet på `(subjekt, source_id)`, og `narrative_record_publication.narrative_id` er UNIQUE. Spec §11's "tre opslag i samme bog = tre tekster" kan ikke udtrykkes. 1017/1021-sagen og de 12 afskårne narrativer (929/930 og 1013/1014 byte-identiske) er symptomer.

> **RETTELSE 2026-08-22 (efter måling — se §7.6b).** To påstande i afsnittet ovenfor var forkerte, og de nåede både `decisions.md` og issue #152, før de blev efterprøvet. De står stadig her, så rettelsen kan læses mod originalen.

### 7.6b Rettelse: hvad målingen faktisk viste

Tre målinger mod prod 2026-08-22, alle læse-kun:

1. **"Strukturelt umuligt" er forkert.** `public.narrative` har ingen unique-constraint på `(subjekt_type, subjekt_id, source_id)` — kun `narrative_pkey` på `id` og et *ikke*-unikt indeks `ix_narrative_subjekt`. Én-pr-udgave håndhæves af `red_upsert_narrativ` og af læserne (`pickPreferredBio`, `public_person_bio_source_versions`), ikke af skemaet. #152 er derfor en writer-/læser-ændring med en additiv kolonne, ikke en skemarestrukturering. Det gør opgaven **mindre** end først antaget.
2. **"Blokerer C3-apply" var en påstand, ikke en udledning.** Den er ikke efterprøvet her og må ikke bruges som gate, før det er afgjort, om C3's operationer er *bindinger* (fremadkompatible med en senere nøgleændring) eller *tekstkirurgi* (som en nøgleændring skal rulle tilbage). Se §7.6c.
3. **Den bundne bestand er ren — men det beviser ikke, at modellen er tilstrækkelig.** Alle 559 publicerede bindinger er 1:1 med deres record: 0 narrativer er længere end deres record (median −3,3 %, forklaret af `narrative_norm_v1`). Tallet gælder dog kun det, fase B rørte; **alle kendte patologier ligger i den ubundne rest** (25 person-records uden binding), som målingen per konstruktion udelader. Tallet må ikke læses som "modellen er fin".

**Den afgørende måling — 1017/1021 — bekræfter derimod merge-patologien empirisk:**

| Objekt | Længde | Forhold |
|---|---:|---|
| Person 1017's narrativ | 369 tegn | indeholder **hele** record A **plus begyndelsen af** record B |
| `record-e8bace88` (s. 504, "A) Otto til Wittenberg…") | 236 tegn | start **og** slut findes i 1017 → fuldt dækket |
| `record-5fc1a041` (s. 505, "B) Ditlev til Wittenberg…") | 150 tegn | start findes i 1017, slut findes **ikke** → afskåret |
| Person 1021's narrativ | 57 tegn | begynder `"low († 1752)…"` = halen af B's orddelte »Revent-\nlow« |

Altså: **ét narrativ spænder to records, og ét record spænder to narrativer** — begge retninger af misforholdet i én sag. Den nuværende nøgle kan ikke udtrykke, hvor teksten kommer fra. Det er en stærkere begrundelse for #152 end spec §11's grundlægger-eksempel, fordi det er observeret i egne data frem for forudset.

Yderligere i den ubundne rest: `record-6fe0fbac` ("Doso, maa være Broder til Hartvig") matcher **både** person 929 og 930, hvis narrativer er byte-identiske (samme md5, 302 tegn). Samme mønster for 1013/1014 (md5-identiske, 127 tegn).

**Bemærk også** at 3 af de 12 "begynder midt i en sætning"-sager er falske positiver: 956 (`"lven"` = OCR af »Iven«), 1308 og 1413 (`"l. Comtesse"` = OCR af »1. Comtesse«). Det er tegnfejl, ikke grænsefejl. Reelle fragment-sager er 1017/1021, 1791 (hvis *navn* er »fyenske Rytterreg.)«), 977 og 1772 (planche-OCR).

### 7.6c Åbent efter rettelsen
Sekvensen »#152 før C3« hviler nu på ét ubesvaret spørgsmål: er C3's apply-operationer bindinger eller tekstkirurgi? Bindinger → C3 kan køre først, #152 er uafhængig. Tekstkirurgi → #152 skal først, ellers skal arbejdet gøres om. Afgøres af gennemgangen af `2026-08-22-1939-v50-c3-atomisk-apply.md`, ikke af skøn.

### 7.7 Udgavespecifikke tabeller og RPC'er — *Teknisk gæld → #153*
`private.reimport_1939_{authorization,write_batch,write_event,name_completion_result}` og `red_*_1939_v50_*` bryder invariant 12. Omfang (Codex' optælling): 27 1939-specifikke tabel-/funktionsdefinitioner i `schema.sql` og 106 Python/R-filer med `1939_v50` i navnet. Næste bog kan ikke genbruge writeren uden kopi. **Anbefaling:** Omdøb/generalisér til `reimport_batch` med `source_id` som parameter, før 2018-20 rører dem. Kan være en mekanisk refactor.

### 7.8 Global `ALTER DEFAULT PRIVILEGES REVOKE EXECUTE ON FUNCTIONS` — *Teknisk gæld → #154*
`db-rls.sql:14-15`. Planen (Task 4 trin 4) advarede udtrykkeligt. Enhver fremtidig `public.red_*` deployet af samme ejer uden eksplicit `GRANT EXECUTE TO authenticated` bliver tavst ukaldbar fra appen. **Anbefaling:** Enten tilføj en db-verify-assert, der fanger ugrantede public-funktioner, eller rul tilbage til schema-lokal revoke som planlagt.

### 7.9 DB-hærdningshuller — *Teknisk gæld → #155*
(a) TRUNCATE omgår append-only (ingen `BEFORE TRUNCATE`-trigger). (b) `db-verify.sql` — hvor dblink-samtidigheds- og default-privilege-beviserne bor — kører ikke i CI; kun `tests/sql/test-evidence-promotion.sql`. (c) `db-migrations.sql` køres aldrig i CI; "migreret DB"-vejen er manuel. (d) Split/merge-forbuddet mod tavs genankring lever kun i Python + dokumentation, ikke i DB. (e) Task 2's svære fixture er tom. (f) `interpretation-schema.json` kender ikke `unresolved`/`superseded`.

### 7.10 Heraldik (spor H) og mobil (spor M) — *Droppet scope, lovligt*
Udskudt som planen tillader. Men `entity_description` er en versioneret tabel uden skrive-RPC, og `CoatOfArmsAssociation` har ingen producent. **Anbefaling:** Lad dem ligge; notér i `decisions.md` at spor H/M er parkeret, ikke glemt.

### 7.11 Gate-model og to uauditerede prod-skrivninger — *BESLUTTET 2026-08-22: fase-pakke-gaten vedtaget → #156*
Se §5. **Anbefaling:** Vedtag fase-pakke-modellen skriftligt i `decisions.md` med dens kendte svaghed (ingen gammel↔ny sammenligning), og tilføj én efterfølgende kontrol: en samlet "er prod lig med summen af manifesterne"-afstemning (Task 21 trin 3 i reduceret form).

### 7.12 Allerede kendte v50-udeståender (fra overdragelsen 08-21) — *Igangværende → #158*
Narrativ-bindinger (`narrative_record_publication`) er kun delvist fortrydbare og optræder ikke i det almindelige fortryd-panel (jf. C0f-GO-pakken §fortrydelse; C3-designet forsøger at lukke det). C3 (7 records + 1017/1021; invarianter bygget, apply ikke); 16 `[NY]`-records; 7 staged (933, 935, 940, 963, 967, 1014, 1135); C1 udskudt; C2-køen ikke startet; 644 narrativ-løse ægtefæller; to parkerede kodefejl i C0f-kæden (`flags_sha256`, dubleret sekvens); strukturerede fakta usynlige i læserfladen (`fetchPersonDetail` henter aldrig `fact`); hændelsesudtræk aldrig kørt (#130); 16 tomme unioner; `get_advisors` efter `red_slet_person`; ingen draft-PR.

### 7.13 Dokumentationsdrift — *Teknisk gæld → #157*
Checkbokse i mindst seks planer (Task 8, Task 14, 08-05 placement, fase B, same-som-paritet, C3-invarianter) modsvarer ikke commits. `docs/database-current-state.md` siger stadig "source 3 = 539 direkte poster". Changelog 08-18 ("v50-strømmen lukket i prod") overdriver. Planerne kan ikke bruges som statuskilde; dette dokument + changelog er det indtil rettet.

## 8. Svar på spørgsmålet "er det vi fik bedre?"

- **Bedre:** segmenteringen (menneske > LLM på postgrænser), DB-fundamentet (fase 1-2, 5), narrativ-provenance (559 bindinger), `narrative_norm_v1`, fail-closed review-kæderne.
- **Lige så godt, anden form:** gate-modellen — hvis den vedtages bevidst (§7.11).
- **Ikke bedre, ikke erstattet:** extraction + fortolkning + promotion (7.1-7.2), 2018-20 (7.3), legacy-migration til den nye model (7.4), flere opslag pr. bog (7.6).
- **Dårligere end planen krævede:** invariant 12 (7.7), global REVOKE (7.8), to prod-skrivninger uden pakke (7.11).

Programmet er altså **ikke færdigt og ikke bedre end planen samlet set**, men det har lagt et fundament, hvorpå planens kerne stadig kan bygges uden at smide noget væk. Den afgørende beslutning er 7.1: skal fortolkningslaget fyldes, eller er provenance-laget produktet? Alt andet følger af den.

## 9. Uafhængig krydskontrol (Codex, samme dag, read-only, uden DB)

Codex nåede uafhængigt samme hoveddom: fundament GO m. forbehold; oprindelig plan NO-GO; 1939-biografilæser betinget GO; "1939-genimporten afsluttet" NO-GO. Codex tilføjede 7.12's fortryd-hul og kvantificeringen i 7.7, og modererede de 16 tomme unioner til et mistankesignal (overtaget). Én uenighed: Codex regner klausul-ledgeren som leveret ("fuldtegnsdækkende"); den dækker alle tegn, men pr. *linje*, ikke pr. klausul, og beviser derfor ikke spec §15.1 — 7.2 fastholdes. Codex' gennemgang omfattede ikke prod-målingen (§2), extractorens manglende model-kald, narrativ-nøglen (7.6), de to identitetsveje (7.5), global REVOKE/TRUNCATE (7.8-7.9) eller de to uauditerede prod-skrivninger (§5).

## 10. Hvad der IKKE må ske herfra

- Ingen ny v50-fase (C1, C2, C3-apply, `[NY]`) startes, før 7.1 og 7.6 er besluttet — ellers bygges videre på en model, der måske skal skiftes.
- Ingen ny plan uden henvisning til et punkt i §7.
- Ingen prod-skrivning uden committet GO-pakke (§5).
