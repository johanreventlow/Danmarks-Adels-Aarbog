# Evidens-promotion: konservativ, bulk-venlig kontrakt

**Dato:** 2026-08-03

**Status:** Implementeret som privat promotion-backend og ikke-muterende dry-run-adapter. Se `docs/superpowers/reviews/evidence-promotion-contract.md` for observeret testbevis og den afgrænsede GO/NO-GO.

**Scope:** En generel, editionsuafhængig kontrakt mellem accepterede fortolkninger i det private evidenslag og allerede eksisterende kanoniske genealogiske mål.

**Ikke scope i første version:** Automatisk oprettelse af personer, familier, facts, relationer, medlemskaber, våben, media eller descriptions. Ingen ændring af den gamle `load_daa.R`-vej.

## 1. Beslutning

En import må aldrig udlede sin egen kanoniske skrivepolitik. Den må indlæse kildeobservationer og foreslå fortolkninger, men en promotion er først gyldig, når en redaktør har valgt et eksisterende mål og den deklarative kontrakt har valideret forbindelsen.

```text
accepteret fortolkning
  + accepteret kildepersona-identitet (hvis personbundet)
  + redaktørens valgte eksisterende kanoniske mål
  + versioneret promotionregel
  → append-only interpretation_promotion
```

Det giver ingen nye genealogiske objekter under import. Mangler den kanoniske struktur, opretter redaktøren den via den almindelige redaktionsskrivevej, før den konkrete fortolkning kobles på.

Dette er en generel regel for alle slægter, udgaver og kildetyper. Den indeholder hverken DAA-år, slægtsnavne eller særregler for OCR.

## 2. Invarianter

1. **Fail closed.** Et prædikat uden aktiv regel, manglende eller forkert mål, uafklaret persona eller manglende observation afvises; fortolkningen bliver privat.
2. **Ingen automatisk kanonisk oprettelse.** Hverken batch eller enkeltpromotion må oprette `person`, `family`, `fact`, `relation`, medlemskab eller en heraldisk entitet.
3. **Én promotion, ét udsagn.** Hver `interpretation_promotion` angår én accepteret fortolkningsversion og ét konkret kanonisk mål. Massehandlinger er kun en transaktionel ergonomisk indpakning.
4. **Kanonisk identitet er forudsætning.** En personbundet fortolkning kan kun promoveres, når dens source persona har status `accepted` og præcis den samme eksisterende `canonical_person_id` som målet tilhører.
5. **Ingen placement-arv.** En omtalt ægtefælle, et barn eller anden sekundær persona arver aldrig hovedpersonens source-record-placement. Placement og genealogisk generation ændres ikke af promotion i version 1.
6. **Kilde- og redaktørdata bevares adskilt.** Promotionen dokumenterer forbindelsen; den kopierer ikke råtekst til `narrative` eller til `entity_description`.
7. **Bevar manuel prioritet.** En eksisterende kanonisk assertion/conclusion ændres ikke af promotion. Modstridende eller nye værdier kræver en særskilt redaktionel ændring og derefter en ny, valideret promotion.

## 3. Deklarativ promotionprofil

En migrationsstyret tabel `private.interpretation_promotion_rule` er den autoritative, versionerede profil. Reglerne er generiske data, ikke kodegrene i R-loaderen eller særregler for en slægt.

Hver regel har mindst:

- stabil `rule_key` og `rule_version`;
- et eksakt `predicate`;
- forventet `interpretation_kind`;
- tilladt `target_type`;
- eventuel forventet `fact.faktatype`;
- om accepteret personaidentitet kræves;
- om principal/co-principal placement kræves;
- om reglen er bulk-egnet;
- status `active` eller `retired`.

Regler matches eksakt. Prædikater med kun en godkendt familie, men ukendt suffix, bliver ikke implicit accepteret. En ny forskningskategori kræver derfor en ny versionsstyret regel og test, men ingen udvidelse af den genealogiske kerne.

## 4. Første, bevidst smalle promotionsæt

Version 1 aktiverer kun personbundne egenskabsudsagn, som kan forbindes til en allerede eksisterende assertion på et eksisterende fact-slot:

| Prædikat | Tilladt mål | Krav |
|---|---|---|
| `person.name` | `assertion` | Assertionens fact er `person/<canonical_person_id>` og har faktatype `navn`; normaliseret værdi matcher. |
| `person.byname` | `assertion` | Samme, med faktatype `tilnavn`. |
| `person.birth` | `assertion` | Samme, med faktatype `fødsel`; dato-/tekstværdi matcher den eksisterende assertion. |
| `person.death` | `assertion` | Samme, med faktatype `død`; dato-/tekstværdi matcher den eksisterende assertion. |
| `person.title` | `assertion` | Samme, med faktatype `titel`; værdi matcher. |

En assertion er valgt som mål frem for blot et fact, fordi den præcise påstand — inklusive kildeværdi, dato og den eksisterende conclusionshistorik — er det kanoniske udsagn, som en ny kildefortolkning faktisk underbygger.

Værdimatch er deterministisk og regeldefineret: trimning og Unicode-normalisering er tilladt; ordret kildeværdi, rå dato og konklusion ændres aldrig. Et ikke-match er ikke en fejl i kilden, men en kø til redaktionel afklaring.

## 5. Bevidst udsatte kategorier

Følgende bevares som accepterede private fortolkninger i første version, men kan ikke promoveres:

- ægteskab, partnerskab, forælder-barn og andre familie-/relationsudsagn;
- lineage- og slægtsmedlemskab samt source placements;
- embeder, gods, bopæl, uddannelse, dekorationer og hændelser;
- våben, afbildninger, billedtekster og generelle beskrivelser;
- ikke-personbundne udsagn.

De kræver hver deres strukturerede inputkontrakt: især eksplicitte deltagere/roller, target-identiteter, perioder, membershiprolle eller heraldisk objekt. De må ikke falde tilbage til navnelighed eller til en persons record placement. Når en sådan kontrakt er specificeret, kan den tilføjes som nye regler uden at ændre version 1's betydning.

## 6. Redaktørens arbejdsgang og bulk

Redaktørfladen samler fortolkninger efter record og source persona, men beholder hvert udsagn som selvstændig beslutning.

1. Redaktøren afgør eller bekræfter kildepersonaens identitet.
2. Systemet finder kun mål, der passer til promotionprofilen, den accepterede identitet og værdimatch.
3. En preview viser antal fortolkninger, konkrete mål, regelversion og at ingen kanoniske rækker oprettes eller ændres.
4. Redaktøren kan vælge enkeltudsagn, “alle sikre i denne record” eller et vilkårligt udvalg.
5. Den endelige batch kører atomisk. Hver valgt fortolkning får sin egen append-only `interpretation_promotion`; fejler én validering, rulles hele batchen tilbage.

En ny append-only `private.interpretation_promotion_batch` registrerer gruppehandlingens profilversion, aktør, preview-hash, tidspunkt og antal. `interpretation_promotion` får et valgfrit `batch_id`. Eksisterende enkeltpromotioner har `batch_id=NULL`; det er ikke en legacy-undtagelse, men den korrekte repræsentation af en individuel afgørelse.

Bulk-knappen må kun omfatte regler med `bulk_eligible=true`. Den må aldrig springe en individuel kontraktkontrol over eller ændre en eksisterende conclusion.

## 7. Databasegrænse

En `SECURITY DEFINER`-RPC, fx `red_promote_interpretations_batch`, tager kun fortolknings-ID'er og redaktørens valgte mål som input. Den:

- kræver en autentificeret redaktør;
- låser fortolkningerne i en stabil ID-orden;
- slår hver fortolknings aktuelle accepterede version, personaidentitet, regel og mål op;
- udfører alle valideringer i databasen;
- indsætter batch og individuelle promotions atomisk;
- bruger sessionsafledt aktør/navn og accepterer ikke disse fra klienten;
- revokerer direkte adgang til regler, batch og private evidensrækker.

R-loaderen bliver dermed aldrig en kanonisk writer. Den kan højst indlæse private, `proposed` fortolkninger; promotion går gennem samme redaktionelle RPC for manuel og bulkbetjent brug.

## 8. Testkontrakt

Mindst følgende tests er bindende:

- korrekt `person.name` til eksisterende assertion accepteres;
- forkert fact-type, værdi, person eller uafklaret persona afvises;
- ukendt prædikat afvises og forbliver privat;
- to promotioner i én gyldig bulkbatch opretter to links og én batch;
- én ugyldig række ruller hele bulkbatchen tilbage;
- en promotion ændrer ikke assertion, conclusion, person, familie, relation, placement eller generation;
- ægtefælle-/lineage-/heraldikfortolkning kan ikke promoveres i version 1;
- anonym og almindelig authenticated adgang kan hverken læse eller skrive private promotiondata;
- en eksisterende individuel promotion og en senere batchpromotion bevarer separat auditspor.

Tests kører mod en disposable lokal PostgreSQL-database, hvor migrations og RLS først anvendes. CI får en eksplicit testdatabase-service; rene R-hjælpetests alene tæller ikke som dækning af denne kontrakt.

## 9. Konsekvens for Task 14

Task 14 opdeles:

1. den private ingest- og identitetsvej fortsætter uændret;
2. promotion-kontrakten og dens editor-RPC implementeres før databundet projektionsloader;
3. den efterfølgende loader må kun forberede/validere private forslag, ikke skabe kanonisk genealogi;
4. senere, særskilte udvidelser kan tilføje familie, membership og heraldik gennem nye, eksplicitte promotionprofiler.

Dermed bliver “zero-match” ikke en automatisk ny person. Et zero-match er en redaktionel køtilstand, indtil nogen bevidst opretter en kanonisk person og tager stilling til dennes struktur.
