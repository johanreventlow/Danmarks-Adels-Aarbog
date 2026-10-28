# Spor 1d — adversarial kodereview (Codex gpt-6.1-terra, reasoning high), fem runder samlet

> Rå Codex-output, screenet. Runde 1 (bred) og 2 (skarpere) var tynde efter spec'ens definition; runde 3a/3b/3c
> er smalle opfølgere (projektejerens ja til flere runder 2026-10-27). Fund-id'er er omnummereret pr. runde:
> `1d.1-NN`, `1d.2-NN`, `1d.3a-NN`, `1d.3b-NN`, `1d.3c-NN`. Alle kommandologs revideret: ingen adgang uden for den rene eksport.

---

# Runde 1

### 1. Sammendrag

**Datalaget har væsentlige huller; jeg kan ikke give det en samlet kvalitetsgodkendelse.**

- OCR-rettelse og sletning kan ændre eller fjerne kildepåstande i strid med invariant 1; OCR-rettelse skriver også køn direkte i personens cache.
- Redigering af en ikke-valgt oplysning kan ændre den valgte konklusion, selv om kodekommentaren siger det modsatte.
- Frisk skema og migrationsvej bruger forskellige ID-allokeringer i samme redaktionsfunktion.
- Placement-promotionens preview beskytter ikke tilstrækkeligt mod samtidige ændringer, og medlemskabsmodellen blokerer flere kildeoptrædener for samme person.
- Reviewet er statisk og afgrænset. Jeg har set kode fra alle ønskede trin, men **ikke gennemgået dem dybt nok til en samlet dom for hvert trin**. Ingen database eller prod er undersøgt.

### 2. Fund

#### 1d.1-01 — OCR-rettelse overskriver evidens og skriver direkte i cache

**Område/trin:** Forarbejde, redaktions-RPC · **Alvor:** P1  
**Sted:** `schema.sql:2063`, `db-migrations.sql:3907`, `CLAUDE.md:31`

**Påstand:** `red_ret_ocr_felt` ændrer en eksisterende kildepåstand direkte og skriver `person.koen` direkte.

**Evidens:** Ved `rettet` udfører funktionen `UPDATE assertion` for navn og dato og `UPDATE person SET koen=...` for køn. Migrationsversionen gør det samme. Invariant 1 kræver ny påstand ved rettelse; invariant 4 kræver, at `person.koen` afledes af konklusioner.

**Konsekvens:** Den oprindelige påstand er ikke længere bevaret som selvstændig assertion, og køn kan afvige fra evidenslaget. Journal og ændringshistorik kan hjælpe med audit, men gør ikke den oprindelige assertion uforanderlig.

**Forslag:** Opret en ny kilde- eller redaktionsbundet påstand og en eksplicit ny konklusion; regenerér køn fra konklusionen. Tilføj en test, der kontrollerer, at den gamle assertion er uændret.

**Sikkerhed:** Verificeret statisk; om og hvor ofte funktionen er brugt i prod er ikke undersøgt.

#### 1d.1-02 — Sletning fjerner påstand og vælger automatisk en anden

**Område/trin:** Forarbejde, evidensmodel · **Alvor:** P1  
**Sted:** `schema.sql:5932`, `schema.sql:5949`, `schema.sql:5959`

**Påstand:** `red_slet_oplysning` sletter assertions og deres citationer og kan erstatte den valgte konklusion med den ældste tilbageværende påstand uden en særskilt afgørelse.

**Evidens:** Funktionen finder den første anden assertion med `ORDER BY id LIMIT 1`, ompeger konklusionen og udfører derefter `DELETE FROM citation` og `DELETE FROM assertion`. Kun forældrefamilie er særskilt undtaget.

**Konsekvens:** Kildens udsagn og kildehenvisning kan forsvinde, og en anden påstand kan blive gældende alene på grund af ID-rækkefølge. Det bryder invariant 1 og kan give en forkert læserværdi.

**Forslag:** Bevar påstanden og citationen; modellér ugyldiggørelse eller tilbagetrækning som en auditeret hændelse. Kræv eksplicit valg, hvis en anden påstand skal være konklusion.

**Sikkerhed:** Verificeret statisk.

#### 1d.1-03 — Rettelse af en ikke-valgt oplysning ændrer alligevel konklusionen

**Område/trin:** Forarbejde, redaktions-RPC · **Alvor:** P1  
**Sted:** `schema.sql:5915`, `schema.sql:5920`, `db-migrations.sql:4131`

**Påstand:** `red_edit_oplysning` kan gøre en tidligere ikke-valgt oplysning til den valgte konklusion.

**Evidens:** Kommentaren siger, at ompegning kun sker, hvis den gamle påstand var valgt. Når `UPDATE conclusion ... AND valgt_assertion_id=p_assertion_id` ikke finder en række, udfører `ON CONFLICT` imidlertid en opdatering af den eksisterende konklusions `valgt_assertion_id`.

**Konsekvens:** En redaktør kan rette en alternativ oplysning og samtidig, uden et særskilt valg, ændre den kanoniske visning. Den nye assertion kopierer desuden ikke `date_certainty` fra den gamle.

**Forslag:** Lad en rettet, ikke-valgt påstand forblive en kandidat; opret kun en konklusion, hvis det er en eksplicit ønsket handling. Bevar relevante datokvalifikatorer, og test både valgt og ikke-valgt input.

**Sikkerhed:** Verificeret statisk.

#### 1d.1-04 — Tilbagetrukne konklusioner bliver i personens visningscache

**Område/trin:** Forarbejde, cache · **Alvor:** P1  
**Sted:** `schema.sql:5614`, `schema.sql:5671`, `schema.sql:5971`

**Påstand:** Cacheprojektionen filtrerer ikke på konklusionens status og kan derfor fortsat vise en tilbagetrukket værdi.

**Evidens:** `red_tilbagetraek_fakta` sætter `status='tilbagetrukket'`; triggeren regenererer cachen, men `regen_person_visning` læser valgte assertions uden krav om `c.status='afklaret'`. Koden anerkender selv forskellen ved `schema.sql:236`.

**Konsekvens:** Læsere, der bruger `person.visning_*`, kan fortsat se en værdi, redaktionen har trukket tilbage. Jeg har ikke undersøgt de konkrete web- eller mobilkald, som ligger uden for sporet.

**Forslag:** Definér hvilke konklusionstilstande der må projiceres, filtrér konsekvent i cachegeneratoren, regenerér berørte caches og test tilbagetrækning og genaktivering.

**Sikkerhed:** Verificeret statisk for cacheværdien; faktisk eksponering i en bestemt læser er ikke verificeret.

#### 1d.1-05 — Frisk skema og migration allokerer ID’er forskelligt

**Område/trin:** Forarbejde og testgrundlag · **Alvor:** P2  
**Sted:** `schema.sql:5768`, `schema.sql:5781`, `db-migrations.sql:4706`, `.github/workflows/ci.yml:168`

**Påstand:** Samme `red_upsert_fakta` bruger `max(id)+1` i frisk skema, men sekvensgenererede ID’er i den seneste migrationsdefinition.

**Evidens:** Skemaet beregner eksplicit ID for både `fact` og `citation`; migrationen indsætter uden ID. CI har en ren skemasti, men flere efterfølgende job anvender migrationen ovenpå skemaet.

**Konsekvens:** To samtidige kald på skemastien kan vælge samme ID og fejle med nøglekonflikt; testresultater efter migration beviser ikke den rene skemadefinition. Ved én redaktør er samtidighedsrisikoen begrænset, men forskellen er reel og gør installationerne adfærdsmæssigt forskellige.

**Forslag:** Saml definitionerne om sekvensallokering, og udvid paritetstesten til de redaktionsfunktioner, der anvendes i begge installationsveje.

**Sikkerhed:** Verificeret statisk. Jeg har ikke kørt en samtidighedstest.

#### 1d.1-06 — Placement-preview er ikke en låst promotionkontrakt

**Område/trin:** 5c-1, membership-promotion · **Alvor:** P1  
**Sted:** `schema.sql:3038`, `schema.sql:3048`, `schema.sql:3059`, `tests/sql/test-placement-membership.sql:115`

**Påstand:** Promotionen kontrollerer et preview og skriver derefter membership-rækker uden at låse de identiteter, placements og eksisterende medlemskaber, som previewet bygger på.

**Evidens:** Funktionen beregner `placement_membership_set`, sammenligner hash og udfører derefter `INSERT ... ON CONFLICT DO UPDATE`. Den viste test kontrollerer forkert preview-hash og en forud eksisterende konflikt, men ikke en samtidig ændring mellem kontrol og skrivning.

**Konsekvens:** Ved samtidige transaktioner kan det godkendte grundlag ændres, eller en konkurrerende membership-række opstå efter konfliktkontrollen og blive overskrevet af `ON CONFLICT`. Én redaktør reducerer sandsynligheden, men batch- og redaktionsarbejde kan stadig overlappe.

**Forslag:** Lås relevante identiteter, placements og mål i en dokumenteret rækkefølge, genberegn preview under lås, og undlad ubetinget overskrivning ved konflikt. Bevis med en toforbindelses-racetest.

**Sikkerhed:** Sandsynlig ud fra kode og transaktionsforløb; ikke reproduceret mod PostgreSQL.

#### 1d.1-07 — Én kildeoptræden får ejerskab over et fælles medlemskab

**Område/trin:** 5c-1 og overgang til flere årbøger · **Alvor:** P2  
**Sted:** `schema.sql:2207`, `schema.sql:2985`, `schema.sql:3006`

**Påstand:** Membership-promotionen kan ikke samle to gyldige kildeoptrædener for samme person som selvstændigt grundlag for samme medlemskab.

**Evidens:** Membership-tabellerne har én række pr. person og slægt eller linje. `source_basis` bærer én `persona_placement_id`; preview klassificerer en anden placement for samme person som konflikt, enten gennem `same_person>1` eller eksisterende basis.

**Konsekvens:** En senere årbogs gyldige evidens for en allerede kendt person kræver manuel konfliktbehandling og kan blokere hele promotionen for kilden. Det er en konkret begrænsning for den fælles metode, men er ikke i sig selv bevis for en fejl i 2018-20-kørslen.

**Forslag:** Skil det fælles medlemskab fra dets potentielt flere kildegrundlag, og definér hvordan hvert grundlag bliver gældende, forældet eller tilbagetrukket. Test samme person i to source records og to årbøger.

**Sikkerhed:** Verificeret statisk.

#### 1d.1-08 — 5c-opgraderingstesten er ikke med i CI

**Område/trin:** 5c-1, migrationsbevis · **Alvor:** P2  
**Sted:** `tests/sql/test-150-upgrade.sh:1`, `.github/workflows/ci.yml:198`, `.github/workflows/ci.yml:220`

**Påstand:** CI’s placement-tests beviser ikke den særskilte opgradering fra det tidligere skema, som den lokale upgrade-test er skrevet til at kontrollere.

**Evidens:** `test-150-upgrade.sh` bygger fra en tidligere base, anvender migrationen to gange og kontrollerer nye objekter og rettigheder. CI kører placement-tests og ceremonitesten, men jeg fandt ikke et kald til denne upgrade-test.

**Konsekvens:** En ændring kan bestå tests på et frisk skema med migrationer og alligevel fejle på en eksisterende installations migrationsvej. Det betyder ikke, at den konkrete produktionsopgradering fejlede.

**Forslag:** Kør upgrade-testen i CI mod en eksplicit, stabil forudgående revision, eller dokumentér og automatisér et tilsvarende reproducerbart opgraderingsbevis.

**Sikkerhed:** Verificeret ved læsning af scriptet og søgning i CI-konfigurationen; tidligere manuelle kørsler er ikke verificeret.

### 3. Dom pr. område

| Område | Dom | Begrundelse |
|---|---|---|
| Forarbejde: assertion, konklusion og cache | **Bør laves om** | Aktive redaktionsveje bryder centrale evidens- og cacheinvarianter. |
| Trin 1: narrativbinding | **Hul** | Cutover-indgangen er undersøgt i udsnit; det er ikke nok til at bedømme hele publicerings- og reversalforløbet. |
| Trin 2: generel writer | **Hul** | De læste indgange har autorisations- og låsemekanismer, men hele apply/replay/reversal-kæden er ikke gennemgået. |
| Trin 3: source-evidence og legacy-migration | **Hul** | Jeg har kun set writerindgange og systemkortets placering, ikke det samlede proveniensbevis. |
| Trin 4: klausuler og fortolkning | **Hul** | De læste writere har konkrete kontraktkontroller, men reviewet dækker ikke hele kæden eller dens kvalitet. |
| Trin 5a: identitetsvej | **Hul** | Identitetsafgørelsen har versions- og låsekontrol; kandidatgenerering og alle adgangsveje er ikke dækket tilstrækkeligt. |
| Trin 5b: relationspersonas og binding | **Hul** | Relationswriter og offentlig familieprojektion er kun delvist undersøgt. |
| Trin 5c-1: placement og membership | **Hul** | Preview, samtidighed og flere kildegrundlag har de beskrevne problemer. |
| CI og migrationsparitet | **Hul** | Der findes nyttige målrettede tests, men de dækker ikke alle skema-/migrationsforskelle eller 5c-upgradestien. |

*“Hul” for trin 1–5b betyder her primært et hul i dette reviews dækning, ikke en påstand om, at hele den pågældende implementation er defekt.*

### 4. Læst fuldt

Følgende filer eller angivne sektioner blev læst fuldt inden for de viste intervaller; resten blev undersøgt via udsnit og søgning. Antallet er under loftet på 40.

- `docs/evidensbaseret-genimport/vision.md`
- `docs/evidensbaseret-genimport/roadmap.md`
- `docs/evidensbaseret-genimport/status.md:1-170`
- `CLAUDE.md`
- `docs/reviews/2026-10-27-trin-1-5/systemkort.md:13-46`, `:153-330`, `:423-439`
- `schema.sql:2207-2237`, `:2467-2597`, `:2760-2821`, `:2935-3090`, `:5604-5655`, `:5659-5693`, `:5886-5962`, `:5971-5992`, `:9138-9154`, `:18143-18199`
- `db-migrations.sql:7114-7157`, `:7366-7375`, `:4690-4758`
- `tests/sql/test-placement-membership.sql`
- `tests/sql/test-150-upgrade.sh`

Vigtigste søgninger: definitioner af `current_rolle`, placement- og identitetsfunktioner; `SECURITY DEFINER`, grants og levende-person-gates i `db-rls.sql`; `UPDATE`/`DELETE` på `assertion`; cachetriggere; og forekomster af skema, migrationer og upgrade-tests i `.github/workflows/ci.yml`. Jeg sammenlignede desuden seneste funktionsdefinitioner i `schema.sql` og `db-migrations.sql` mekanisk for at finde kandidater til manuel kontrol; en tekstforskel blev ikke i sig selv behandlet som et fund.

### 5. Hvad jeg ikke nåede

- Jeg nåede ikke et dybt adversarialt review af alle dele af trin 1–5 eller af alle Python- og R-pipelines. Især er præsens, hændelser, 1939-C3, reversal, hash-normalisering og de mange øvrige RPC’er ikke dækket tilstrækkeligt.
- Jeg verificerede ikke fundene med databasekørsel, samtidighedstest, netværk eller produktionsdata. Derfor er der ingen påstand om faktisk prod-forekomst eller om, at en bestemt person er eksponeret.
- Styringsdokumenterne og systemkortet blev delvist afkortet i det første samlede output; kun de intervaller, der er angivet ovenfor, tælles som fuldt læst.
- **Sporet bør suppleres eller køres videre**, før det bruges som et fuldt helhedsreview. Fundene ovenfor kan dog efterprøves direkte i de angivne kodepunkter.
---

# Runde 2

### Sammendrag

**Reviewet er for tyndt til en helhedsdom og skal køres om:** Kravet om mindst tre fuldt læste centrale filer eller sektioner for hvert område er ikke opfyldt.

Jeg fandt fire konkrete svagheder. Den alvorligste er, at et hændelsesudtræk, der er sendt til eskalering, samtidig kan gå videre som rent input til en loader, som kan slette eksisterende hændelser. Klausulsegmenteringen fletter heller ikke parenteser som tilsigtet, og præsensvalideringen accepterer både tomme udtræk og en person som sin egen forælder.

Der er også et kendt hul i håndhævelsen af kontrolmodellens stop efter en fejlet stikprøve. Jeg har ikke grundlag for at sige, at disse fejl har ramt produktion. Der er ikke foretaget database- eller netværkskald.

### Fund

#### 1d.2-01 — Hændelsespipeline · Alvor: P1

**Sted:** `.claude/skills/daa-haendelser/scripts/validate_haendelser.py:157`, `.claude/skills/daa-haendelser/scripts/validate_haendelser.py:201`, `.claude/skills/daa-haendelser/scripts/load_haendelser.R:118`, `.claude/skills/daa-haendelser/scripts/load_haendelser_helpers.R:103`

**Påstand:** Et tomt hændelsesudtræk, som H8 sender til eskalering, bliver samtidig optaget i det rene input og kan dermed udløse sletning af tidligere hændelser.

**Evidens:** H8 lægger årsagen i `escalation`, men ikke i `issues`; `validate_all` lægger derfor også rækken i `clean`. Loaderen beregner et merge mod den tomme nye rækkegruppe, og mergeplanens `deletes` udføres som `DELETE`.

**Konsekvens:** Hvis loaderen køres på det rene output før en vellykket eskalering, kan et fejlbehæftet tomt udtræk fjerne eksisterende hændelser og deres markeringer. Jeg har ikke verificeret, at det er sket.

**Forslag:** Hold H8-rækker ude af loaderens input, indtil eskaleringen eksplicit har løst dem. Tilføj en integrationstest med eksisterende hændelser og et tomt H8-udtræk.

**Sikkerhed:** Verificeret ved kodelæsning; følgevirkningen er ikke afprøvet mod en database.

#### 1d.2-02 — Trin 4, klausulsegmentering · Alvor: P1

**Sted:** `.claude/skills/daa-extract/scripts/clause_segment.py:153`, `.claude/skills/daa-extract/scripts/clause_segment.py:179`

**Påstand:** Fletningen af klausuler på tværs af en åben parentes fejler, når der ligger et normalt layout-span mellem klausulerne.

**Evidens:** Fletningen kræver, at det senest tilføjede span ikke er `layout`, men mellemrummet mellem to klausuler indsættes netop som et `layout`-span. En lokal, syntetisk funktionsafprøvning gav to klausuler for `Alpha (Beta. Gamma) Delta.`, begge flagget med `unbalanced_parentheses`.

**Konsekvens:** Kildetekstens meningsbærende parentes kan blive delt mellem observationer. Flagene gør fejlen synlig i segmenteringsresultatet, men det planlagte konservative fælles spænd opstår ikke. Jeg har ikke dokumenteret en konkret påvirket produktionspost.

**Forslag:** Flet hen over mellemliggende layout uden overlap eller tab af dækning, og test både runde og firkantede parenteser samt nesting.

**Sikkerhed:** Verificeret ved kodelæsning og lokal afprøvning uden filer.

#### 1d.2-03 — Præsenspipeline · Alvor: P1

**Sted:** `.claude/skills/daa-presens/scripts/validate_presens.py:31`, `.claude/skills/daa-presens/scripts/validate_presens.py:54`, `.claude/skills/daa-presens/scripts/load_presens.R:189`

**Påstand:** Præsensvalideringen accepterer et selvrefererende forælderlink og et tomt personudtræk som gyldigt.

**Evidens:** Forælderkontrollen undersøger kun, om id’et findes i blokkens id-mængde; den afviser ikke selvreference eller cykler. En syntetisk afprøvning af både selvreference og en tom personliste returnerede ingen fejl. Loaderen bruger efterfølgende linkene til at oprette familiemedlemmer.

**Konsekvens:** Et selvlink kan føre til en familie, hvor samme person behandles som både forælder og barn; et tomt udtræk kan passere uden at synliggøre manglende dækning. Databasekonsekvensen er ikke afprøvet.

**Forslag:** Kræv gyldige, ikke-tomme lokal-id’er, afvis selvreferencer og cykler, og send tomme udtræk til review med en eksplicit disposition.

**Sikkerhed:** Verificeret for validatorens adfærd; loaderens konkrete databaseudfald er udledt af koden.

#### 1d.2-04 — Trin 4, kontrolmodel · Alvor: P2

**Sted:** `.claude/skills/daa-extract/scripts/control_model.py:23`, `.claude/skills/daa-extract/scripts/control_model.py:84`, `docs/decisions.md:749`

**Påstand:** Stoppet efter en fejlet stikprøve er en procedure, som værktøjet ikke selv håndhæver på tværs af kørsler.

**Evidens:** Beslutningen kræver, at årsagen afklares før næste kørsel. Koden siger selv, at en ny plan kan trækkes uden denne kontrol; `SAMPLE_FAILED` stopper den aktuelle generering.

**Konsekvens:** Beviset for, at næste maskinelle accept først skete efter årsagsafklaring, afhænger af ekstern disciplin og dokumentation. Det er ikke bevis for, at nogen har omgået proceduren.

**Forslag:** Registrér fejlet kontrolkørsel og kræv en sporbar afklaringsbeslutning, før en ny kontrolplan for samme scope kan autorisere maskinel accept.

**Sikkerhed:** Verificeret.

### Dom pr. område

| Område | Dom | Begrundelse |
|---|---|---|
| 1. Narrativ og source record | **Ikke dækket** | Cutover-indgang og enkelte kontraktdele er læst; reversal og hele cutover-kernen er ikke tilstrækkeligt gennemgået. |
| 2. Writer og batch | **Ikke dækket** | Begin, lås, finalisering og dele af reversal er læst, men apply-, replay- og autorisationskæden er ikke fulgt samlet. |
| 3. Source-evidence og legacy | **Ikke dækket** | Manifestbygning, rendition og migration er undersøgt; den samlede migrations- og reversalvej er ikke bevist. |
| 4. Klausuler og fortolkning | **Hul** | Parentesfletningen er konkret forkert, og kontrolmodellens stop på tværs af kørsler er procedurebaseret. Promotion er ikke tilstrækkeligt gennemgået til en samlet kvalitetsdom. |
| 5. Identitetsvej | **Ikke dækket** | Kandidatregistrering, dele af afgørelses-RPC’en og arkets binding er læst; kandidatgenerator og alle adgangsveje er ikke fulgt fuldt. |
| 6. Relationspersonas | **Ikke dækket** | Relationswriter, bindingstilstand, børneafgørelse og udtræksdele er læst; genbinding og undtagelsesveje er ikke dækket tilstrækkeligt. |
| 7. Produktionsoverførsel | **Ikke dækket** | Nøglekort, DDL-værktøj og skridtklassifikation er læst; den samlede afbruds- og genkørselsvej er ikke efterprøvet. |
| 8. Python- og R-pipeline | **Hul** | Hændelses- og præsensvejene har konkrete fejl; øvrig segmentering, normalisering og R-loadlag er kun delvist dækket. |

### Læst fuldt

Nedenfor tæller en angiven sektion som én læst sektion. Hvor output blev afkortet, tæller jeg ikke den manglende del som læst.

- `docs/evidensbaseret-genimport/vision.md` og `docs/evidensbaseret-genimport/roadmap.md`.
- `.claude/skills/daa-extract/scripts/source_persona.py`.
- `.claude/skills/daa-extract/scripts/relation_persona_extract.py` og `relation_persona_extract_v2.py`.
- `.claude/skills/daa-extract/scripts/build_legacy_migration_manifest.py`.
- `.claude/skills/daa-extract/scripts/build_source_evidence_rendition.py`.
- `.claude/skills/daa-extract/scripts/clause_segment.py`.
- `.claude/skills/daa-extract/scripts/transfer_steps.py`, `transfer_ddl.py` og `transfer_5ab_keymap.sql`.
- `.claude/skills/daa-extract/scripts/apply_narrative_record_cutover.R`.
- `.claude/skills/daa-presens/scripts/segment_presens.py` og `validate_presens.py`.
- `.claude/skills/daa-haendelser/scripts/validate_haendelser.py:1-215`.
- `schema.sql:3841-4024`, `schema.sql:4174-4190`, `schema.sql:4274-4282`, `schema.sql:15599-15824`, `schema.sql:16100-16141` og `schema.sql:17041-17160`.
- `.claude/skills/daa-extract/scripts/evidence_runner.py:60-138`, `:570-658` og `:683-695`.
- `.claude/skills/daa-extract/scripts/identity_decision_sheet.py:1-125`.
- `.claude/skills/daa-extract/scripts/relation_persona_extract_v3.py:1-110`.
- `.claude/skills/daa-extract/scripts/relation_child_sheet.py:1-130`.
- `.claude/skills/daa-extract/scripts/apply_reimport_helpers.R:1-100`.

Øvrige styringsdokumenter, `CLAUDE.md`, `datamodel-oversigt.md` og systemkortet blev læst gennem et output, der blev afkortet; jeg kan derfor ikke hævde fuld læsning af dem.

De vigtigste søgninger var efter aktuelle SQL-definitioner og deres genoprettelser, `SAMPLE_FAILED`, parentesflag, loadernes `clean`/merge/sletning samt overførselsscripternes `\ir`-inklusioner.

### Hvad jeg ikke nåede

Jeg nåede ikke den obligatoriske bredde på tre centrale fuldt læste sektioner pr. område. Særligt mangler den komplette cutover/reversal, writerens samlede autorisations- og replayforløb, promotion, identitetsadgangene, genbinding og ægtefælleundtagelser, samt ende-til-ende recovery for overførslen. Jeg nåede heller ikke fuld gennemgang af stamtavlens segmentering, normalisering/hashing og R-loadlag.

Derfor er dette **ikke en godkendelse af trin 1–5** og heller ikke et færdigt spor 1d-review. Fundene kan efterprøves og bruges ved den nødvendige omkørsel.
---

# Runde 3a

### Sammendrag

- **Trin 3 har et dokumenteret evidenshul:** Det, der lagres som `verbatim_text`, er normaliseret tekst og svarer ikke nødvendigvis ordret til det rå span.
- Manifestbyggeren kontrollerer ikke, at sidetal og record-nøgle hører til det fundne tekstspan. En syntetisk prøve accepterede både forkert side og forkert nøgle.
- Segmenteringen udelader linjer efter en bred støjregel. Status dokumenterer 13 mulige udeladte prosalinjer; deres faktiske indhold er ikke verificeret her.
- Trin 1 og 2 har flere synlige beskyttelser, men den læste del er for lille til en samlet kvalitetsdom eller et GO.
- Reviewet er statisk og afgrænset. Produktion, databaseadfærd og samtidighed er ikke verificeret.

### Fund

#### 1d.3a-01 — Normaliseret tekst lagres som ordret kildeevidens

**Område/trin · Alvor:** Source-evidence, trin 3 · **P1**

**Sted:** `.claude/skills/daa-extract/scripts/build_source_evidence_manifest.py:126`, `.claude/skills/daa-extract/scripts/build_source_evidence_manifest.py:152`, `schema.sql:3707`

**Påstand:** Det gemte `verbatim_text` er ikke nødvendigvis den ordrette tekst i det gemte rå span.

**Evidens:** Builderen finder posten i en projektion, som sammenfatter whitespace og udelader bestemte linjer, og gemmer postens normaliserede `raw_text` som `verbatim_text`. SQL gemmer denne værdi sammen med rå offsets. En syntetisk prøve gav råt udsnit `'Alfa   beta'` og `verbatim_text` `'Alfa beta'`. Testen kontrollerer kun, at *projektionen* af udsnittet svarer til værdien (`.claude/skills/daa-extract/scripts/test_build_source_evidence_manifest.py:100`).

**Konsekvens:** Feltets navn, fingerprint og anker kan give indtryk af, at den lagrede observation er ordret kildeindhold. Den kan ikke bruges som bevis for den præcise rå tekst, og udeladte linjer inden for et span kan være usynlige i observationen. Det er et brud på kravet om ordret bevarelse og adskillelse af rå og afledt tekst.

**Forslag:** Bevar det præcise rå udsnit og dets hash særskilt fra den normaliserede segmenttekst. Angiv normaliseringsversion og relationen mellem de to; test både rå udsnit og den afledte projektion.

**Sikkerhed:** Verificeret for kode og syntetisk eksempel; omfanget i produktionsdata er ikke målt.

#### 1d.3a-02 — Sidetal og record-nøgle er ikke bundet til det fundne span

**Område/trin · Alvor:** Manifest og ankring, trin 3 · **P1**

**Sted:** `.claude/skills/daa-extract/scripts/build_source_evidence_manifest.py:96`, `.claude/skills/daa-extract/scripts/build_source_evidence_manifest.py:126`, `.claude/skills/daa-extract/scripts/build_source_evidence_manifest.py:138`, `schema.sql:3693`

**Påstand:** Builderen accepterer en vilkårlig gyldig record-nøgle og et syntaktisk gyldigt sidetal for tekst, der findes et andet sted i renditionen.

**Evidens:** Nøglen konstrueres af felter i den indsendte post; siden parses fra `sider`. Tekstsøgningen beviser ingen sammenhæng mellem disse felter og sidemarkører eller postgrænser. I en syntetisk prøve med tekst på side 10 accepterede builderen `I-999` og side `999`. SQL kontrollerer efterfølgende blandt andet positive side- og offsetværdier, men udleder ikke deres sammenhæng med renditionen.

**Konsekvens:** Et forkert eller ændret postartefakt kan give en accepteret occurrence med forkert kildehenvisning eller record-identitet, selv om tekst- og renditionshash stemmer. Prøven viser en manglende gate; den beviser ikke, at de eksisterende produktionsposter er fejlbindet.

**Forslag:** Bind manifestet til et verificeret segmenteringsresultat, og kontrollér sideinterval og postidentitet mod renditionsmarkører og dokumenterede grænser. Tilføj negative tests med korrekt tekst, men forkert side og nøgle.

**Sikkerhed:** Verificeret i kode og med syntetisk prøve.

#### 1d.3a-03 — Muligt meningsbærende indhold fjernes før evidensbyggelsen

**Område/trin · Alvor:** Segmentering og dækningsregnskab, trin 3 · **P1**

**Sted:** `.claude/skills/daa-extract/scripts/segment.py:40`, `.claude/skills/daa-extract/scripts/segment.py:202`, `docs/evidensbaseret-genimport/status.md:248`

**Påstand:** Støjreglen fjerner matchende hele linjer før posttekst og source-evidence dannes, uden at den enkelte udeladelse i den læste kode får en disposition.

**Evidens:** `NOISE_RE` omfatter blandt andet mønsteret `Ridder\s+.+sønner`, og segmenteringen springer matchende linjer over. Status angiver 13 *mulige* `NOISE_RE`-prosalinjer som udestående.

**Konsekvens:** Hvis blot én af linjerne er kildeprosa, mangler meningsbærende indhold i den afledte post og i de efterfølgende observationer. Jeg har ikke læst linjerne og kan derfor ikke fastslå, hvor mange der faktisk er fejl.

**Forslag:** Gennemgå de 13 linjer mod kilden, registrér disposition pr. linje, og ret eller versionsbind segmenteringen dér, hvor den har fjernet indhold. Bevar fremover udeladelser som eksplicitte dækningshændelser.

**Sikkerhed:** Verificeret at reglen udelader match og at restpunktet er dokumenteret; konkret datatab er sandsynligt, men ikke verificeret.

### Dom pr. område

- **Trin 1 — ikke dækket:** Den læste cutover-del binder artefakter og kontrollerer live-sæt; publiceringsgaten sammenligner aktuel tilstand med seneste event. Jeg har ikke fulgt hele stale-, withdrawal- og reversalforløbet.
- **Trin 2 — ikke dækket:** Den læste case-reversal binder plan og kvittering og kontrollerer låserækkefølge. Case-writeren er samtidig lukket ved kontraktversion 2. Jeg har ikke gennemgået hele den gældende profilbundne writers apply, replay og reversal.
- **Trin 3 — hul:** De dokumenterede mangler i råtekst, ankring og dækningsregnskab svækker beviset for kildeproveniens. Det er ikke et bevis for, at alle importerede poster er forkerte.

### Læst fuldt

Filer og afgrænsede sektioner, som er læst i deres helhed inden for reviewets loft:

- `docs/evidensbaseret-genimport/vision.md`
- `docs/evidensbaseret-genimport/roadmap.md`
- `CLAUDE.md`
- `docs/reviews/2026-10-27-trin-1-5/systemkort.md:153-208`
- `.claude/skills/daa-extract/scripts/build_source_evidence_manifest.py`
- `.claude/skills/daa-extract/scripts/build_source_evidence_rendition.py`
- `.claude/skills/daa-extract/scripts/build_legacy_migration_manifest.py`
- `.claude/skills/daa-extract/scripts/reimport_profile.py:1-145`
- `.claude/skills/daa-extract/scripts/test_build_source_evidence_manifest.py:1-154`
- `.claude/skills/daa-extract/scripts/apply_narrative_record_cutover.R`
- `schema.sql:3679-3716`
- `schema.sql:3841-4024`
- `schema.sql:10273-10412`
- `schema.sql:11187-11370`
- `schema.sql:11980-12180`
- `schema.sql:12685-12845`
- `schema.sql:14612-14745`

Øvrigt materiale blev læst i udsnit. De vigtigste søgninger gjaldt case-writerens funktionsnavne, cutover, `sha256`, `sort`, normalisering, `NOISE_RE`, `raw_text` og `normalized_text_sha256`. De fire styringsdokumenter blev efterspurgt i den krævede rækkefølge, men dele af værktøjsoutputtet blev afkortet; jeg kan derfor ikke hævde fuld læsning af målarkitektur og status.

### Hvad jeg ikke nåede

Jeg nåede ikke en fuld gennemgang af cutover-kernens resterende kontrol- og skriveforløb, alle publicerings- og reversalhjælpere, case-apply i sin helhed eller den generelle writers finalize/replay/reversal. Jeg undersøgte heller ikke locale- og Unicode-paritet tilstrækkeligt til en dom. Ingen database, netværk eller produktionstilstand blev undersøgt; der blev kun kørt en lille syntetisk, skrivefri Python-prøve.
---

# Runde 3b

### Sammendrag

**Trin 5b har væsentlige huller i bindingen mellem redaktionel afgørelse og den aktuelle familiestruktur.** En accepteret ægteskabs- eller forældrerelation kan ved første binding ende på en anden familie end den afgjorte.

For børnehenvisninger kan en ændret børneflok genbindes uden en ny afgørelse, selv om afgørelsen gemmer en hash af den oprindelige flok. Testen forventer denne adfærd.

Den generiske afgørelses-RPC giver redaktører en alternativ vej uden om relationsvejens særlige kontrol. Fundene er verificeret ved statisk læsning; jeg har ikke kørt kode eller undersøgt en database.

Ved **allerede bundne ægteskaber** skjules en forældet binding, og genbinding til en anden familie afvises. Genåbningsvejen bevarer en særskilt historisk forbindelse. Dubletværnet stopper det undersøgte tilfælde med to ægtefællepersonas på samme person i samme post, men spørgsmålet er ikke udtømmende dækket.

### Fund

#### 1d.3b-01

**5b · Første binding efter familieskift · Alvor: P1**

**Sted:** `schema.sql:17461`, `schema.sql:17482`, `schema.sql:17367`, `tests/sql/test-relation-binding.sql:920`

**Påstand:** En accepteret ægteskabs- eller forældrerelation kan førstebindes til en anden familie end den, afgørelsen gjaldt.

**Evidens:** Preview kræver, at den anmodede familie svarer til den *aktuelle* `relation_binding_state`, men sammenligner ikke den med `decision_evidence.family_id`. Værnet `RELATION_PROMOTION_REBIND_FAMILY_CHANGED` gælder kun, når der allerede findes en binding. Genåbning kræver derimod en eksisterende binding. Testens `g4` er afgjort, aldrig bundet og flyttes til en anden familie; testen kontrollerer, at genåbning afvises, men prøver ikke første binding til den nye familie.

**Konsekvens:** Afgørelse for familie A → strukturen flyttes til B → første preview og binding kan acceptere B uden en ny afgørelse. Den offentlige projektion kan derefter vise kildehenvisningen ved B, hvis de øvrige publiceringskrav er opfyldt. Jeg har ikke konstateret, at dette er sket i produktion.

**Forslag:** Kræv, at den aktuelle familie svarer til afgørelsens familie også ved første binding. Giv accepterede, endnu ubundne relationer en eksplicit genafgørelsesvej. Tilføj en test for præcis rækkefølgen afgørelse → familieskift → første binding, både for ægteskab og forælder.

**Sikkerhed:** Verificeret ved statisk kode- og testlæsning.

#### 1d.3b-02

**5b · Børnehenvisninger og genbinding · Alvor: P1**

**Sted:** `schema.sql:16124`, `schema.sql:17050`, `tests/sql/test-relation-child.sql:170`

**Påstand:** En ændret børneflok kan bindes på grundlag af en afgørelse, der blev truffet for en anden flok.

**Evidens:** Afgørelsen gemmer `flock_digest`, men `relation_binding_state` sammenligner kun reglens aktuelle familie med afgørelsens familie, ikke den aktuelle flokhash med afgørelsens hash. Testen tilføjer et barn uden egen post før binding og forventer `BOUND`; den tilføjer derefter endnu et barn og forventer, at genbinding gør kilden synlig igen.

**Konsekvens:** Redaktørens godkendelse af en bestemt flok kan komme til at understøtte en anden flok, herunder en ny antalafvigelse, uden at redaktøren ser og godkender den. Den aktuelle state-hash beskytter mod ændring *efter binding*, men beviser ikke, at den ændrede flok blev afgjort.

**Forslag:** Sammenlign aktuel `flock_digest` og relevante afvigelser med afgørelsens grundlag. Ved forskel skal relationen genafgøres, før første binding eller genbinding. Test både tilføjelse og fjernelse af et barn uden egen post.

**Sikkerhed:** Verificeret ved statisk kode- og testlæsning; testen dokumenterer den tilsigtede nuværende adfærd.

#### 1d.3b-03

**5b · Alternativ afgørelsesvej · Alvor: P1**

**Sted:** `schema.sql:8722`, `schema.sql:8743`, `schema.sql:9490`, `schema.sql:17471`, `tests/sql/test-relation-binding.sql:554`

**Påstand:** En redaktør kan acceptere et ægteskabsforslag gennem den generiske RPC uden den særlige relationsafgørelses kontrol og derefter få det strukturelt bundet.

**Evidens:** `red_decide_interpretation` er givet til `authenticated`, kontrollerer redaktørrolle, version og et ikke-tomt evidensobjekt, men begrænser ikke relationsprædikater. Relations-preview kræver `accepted` og gyldig aktuel struktur, men ikke afgørelsesmetoden `family-structure-v1` eller en afgørelsesbundet familie for ægteskab/forælder. Låsetesten accepterer selv et ægteskab direkte med den generiske RPC og en simpel note.

**Konsekvens:** Den særlige vej er ikke en håndhævet adgangsgrænse: en klient med redaktørrolle kan omgå dens hashbundne sætmængde og relationsspecifikke beslutningsgrundlag. Det kræver redaktøradgang; jeg har ikke fundet belæg for adgang for anonyme brugere.

**Forslag:** Gør den generiske afgørelseskerne privat, eller afvis relationsprædikater i dens offentlige indgang og lad kun de kontrollerede relationsfunktioner kalde en privat kerne. Håndhæv samtidig den forventede afgørelsesmetode og familie ved promotion. Tilføj en negativtest under `authenticated`.

**Sikkerhed:** Verificeret ved statisk kode- og testlæsning.

### Dom pr. område

- **5a · Identitetsafgørelse og låsning: solidt, med begrænset dækning.** Den læste kerne låser personaen og kontrollerer forventet version; kandidatvalg kontrolleres mod gældende kandidatkørsel. Kandidatgeneratorens samlede kvalitet og alle adgangsveje er ikke dækket.
- **5b · Relationsbinding og familieskift: hul.** Første binding mangler kobling til den afgjorte familie. For en allerede bundet relation findes der derimod et værn og en særskilt genåbningshistorik.
- **5b · Børnehenvisninger: hul.** Afgørelsen gemmer flokkens digest, men genbinding håndhæver den ikke.
- **5b · Dubletreglen: delvist dækket.** Det læste værn afviser den specifikke situation med to accepterede ægtefællepersonas til samme person i samme post; jeg kan ikke ud fra dette review konkludere, at alle former for dobbeltbinding er umulige.
- **5b · Relationswriter, ægtefælle-undtagelser, ægteskabsnumre og `relation_person_create`: ikke dækket til en samlet dom.** Jeg læste udvalgte writer- og kontrolsektioner, men ikke nok af hele kæden eller dens tests.
- **Levende personer og offentlig adgang: ikke dækket til en samlet dom.** Den læste familieprojektion anvender familiegate og publikationskontrol, og en børnetest kontrollerer skjul ved et levende familiemedlem. Det er ikke en fuld adgangs- eller privatlivsrevision.

### Læst fuldt

Følgende filer eller angivne sektioner blev læst fuldt; store filer blev læst i bidder. Listen omfatter 16 filer/sektioner:

1. `docs/evidensbaseret-genimport/vision.md`
2. `docs/evidensbaseret-genimport/roadmap.md`
3. `docs/evidensbaseret-genimport/teknisk-maalarkitektur.md`
4. `CLAUDE.md`
5. `docs/reviews/2026-10-27-trin-1-5/systemkort.md:239–343`
6. `docs/reviews/2026-10-27-trin-1-5/systemkort.md:407–432`
7. `.claude/skills/daa-extract/scripts/source_persona.py`
8. `.claude/skills/daa-extract/scripts/identity_decision_sheet.py`
9. `.claude/skills/daa-extract/scripts/relation_persona_extract.py`
10. `schema.sql:8722–8822`
11. `schema.sql:8833–8984`
12. `schema.sql:9156–9315`
13. `schema.sql:15971–16171`
14. `schema.sql:17041–17564`
15. `schema.sql:17668–17891`
16. `tests/sql/test-relation-child.sql`

Derudover læste jeg udsnit af status, datamodel, øvrige relevante SQL-funktioner og tests. De vigtigste søgninger var efter `relation_binding_state`, `supersedes_promotion_id`, `decision_evidence`, `red_decide_interpretation`, `flock_digest`, `RELATION_PROMOTION_REBIND_FAMILY_CHANGED`, genåbning og familiedrift. Jeg kontrollerede med søgning, at de relevante funktioner også findes i `db-migrations.sql`; jeg har ikke foretaget en fuld schema/migrations-ækvivalenskontrol.

### Hvad jeg ikke nåede

Jeg gennemgik ikke kandidatgeneratoren ende-til-ende, alle RPC-grants og RLS-politikker, hele relationswriterens låseforløb, alle ægtefælle-undtagelser eller alle varianter af dubletreglen. Jeg gennemgik heller ikke hele `relation_person_create`-kædens autorisation og tests eller alle samtidighedstilfælde for ægteskabsnumre.

Statusdokumentet blev læst i udsnit; et samlet værktøjsoutput blev afkortet, så jeg regner det ikke som fuldt læst. Ingen tests blev kørt, og produktionsdata eller faktisk forekomst af de beskrevne fejl er ikke undersøgt.
---

# Runde 3c

### Sammendrag

**Der er væsentlige huller i de gamle R-skriveveje og i ét af DDL-ceremoniens beviser.** Jeg har ikke grundlag for at konkludere, at de har beskadiget produktion.

`load_daa.R` stopper før skrivning, når narrativkontrakten er version 2. Dens fejl er derfor betingede af en base med version 1; jeg har ikke kontrolleret den aktuelle produktionsbase.

`post_load_fixup.R` har derimod ingen tilsvarende versionsport i den læste kode og kan skrive editionsspecifikke identiteter til en anden valgt udgave. Placement-frysningen i backfillen har desuden et tidsvindue.

DDL-ceremoniens `DATA_DELTA_OK` beviser ikke, at ændringer i de tre tilladte tabeller er de forventede. Data-ceremoniens genoptagelse har nyttige tilstandskontroller, men den private runner og den faktiske produktionskørsel har jeg ikke kunnet gennemgå.

### Fund

#### 1d.3c-01

**R-fixup · Alvor: P1**  
**Sted:** `.claude/skills/daa-extract/scripts/post_load_fixup.R:39`, `:69`, `:92`, `:113`

**Påstand:** Fixup-scriptet accepterer en vilkårlig udgave, men anvender faste Reventlow-linjenavne og faste identitetslinks på dens poster.

**Evidens:** Første argument vælger `source`; derefter upsertes de faste linjer og efternavnet Reventlow for denne kilde, og personopslag på faste linje-/nummerpar bruges til at indsætte `samme_som`. Der er ingen narrativkontraktport i den læste transaktion. Opslaget tager desuden første række, hvis flere matcher.

**Konsekvens:** En kørsel med en anden udgave eller en tvetydig nøgle kan ændre lineage og oprette en forkert kanonisk identitetsrelation. Det er en mulig skrivevej, ikke dokumentation for, at den er brugt forkert i prod.

**Forslag:** Pensionér skrivevejen eller bind den fail-closed til en eksplicit godkendt source og entydige, verificerede identiteter; afvis flertydige personopslag og kræv en aktuel, versionsbundet apply-vej.

**Sikkerhed:** Verificeret i koden; faktisk produktionspåvirkning er ikke undersøgt.

#### 1d.3c-02

**R-backfill / trin 5c · Alvor: P1**  
**Sted:** `.claude/skills/daa-extract/scripts/backfill_slaegtled.R:82`, `:101`, `:113`; `schema.sql:2899`

**Påstand:** Placement-frysningen og idempotensvagten kontrolleres før transaktionen og kan blive forældede før backfillens skrivning.

**Evidens:** Scriptet tæller dispositioner og eksisterende slægtled, starter først derefter transaktionen og opdaterer rækkerne. Placement-writeren låser de enkelte `person_external_id`-rækker og gemmer en hash af deres tilstand, men den læste backfill tager ingen fælles lås omkring kontrol og skrivning.

**Konsekvens:** Ved samtidig placement og backfill kan backfill passere en tom ledger, hvorefter placement registreres, og backfill ændrer de nu frosne legacyværdier. To samtidige backfills kan tilsvarende begge passere idempotensvagten. Dette er en race, ikke et påvist hændelsesforløb; ved én redaktør er risikoen afhængig af overlappende kørsler.

**Forslag:** Tag en fælles, kildespecifik transaktionslås før begge kontroller, og brug samme låsekontrakt i placement-writeren; genkontrollér derefter under låsen og test det faktiske samtidige forløb.

**Sikkerhed:** Verificeret af rækkefølgen i koden; ikke reproduceret mod database.

#### 1d.3c-03

**Overførsel plan A / DDL-driftguard · Alvor: P1**  
**Sted:** `.claude/skills/daa-extract/scripts/transfer_ddl.py:116`; `.claude/skills/daa-extract/references/transfer-5ab-ddl-allowed-data-delta.txt:3`; `docs/runbooks/transfer-5ab-ddl-prod.md:125`

**Påstand:** `DATA_DELTA_OK` accepterer vilkårlige indholdsændringer i de tre tilladte tabeller og beviser derfor ikke det forventede datadelta.

**Evidens:** En ændret hash accepteres alene, hvis tabelnavnet er på allowlisten; selv en forsvundet allowlistet tabel tælles som `changed`. Enhedstesten fastslår netop denne adfærd: `.claude/skills/daa-extract/scripts/test_transfer_ddl.py:157`. Runbooken bruger `DATA_DELTA_OK` som et efterkrav til `DDL_OK`.

**Konsekvens:** Slettede eller forkert ændrede rækker i en tilladt tabel kan give grønt resultat og samme antal ændrede tabeller som den forventede migration. Katalogkontrol og andre digests kan opdage nogle fejl, men den læste deltafunktion beviser ikke mængden eller værdierne. Jeg har ikke påvist forkert prod-data.

**Forslag:** Bind hver tilladt ændring til forventet før-/efterindhold eller en præcis række- og kolonneprojektion; afvis forsvundne eksisterende tabeller og test uventet rækkesletning og ændrede værdier.

**Sikkerhed:** Verificeret i kode, test og runbook; øvrige private ceremonikontroller er ikke læst.

#### 1d.3c-04

**R-load / privathed · Alvor: P1**  
**Sted:** `.claude/skills/daa-extract/scripts/load_daa.R:1037`

**Påstand:** På en base, der tillader den gamle loader, nulstiller den `levende` for alle personer og genberegner kun et snævert udsnit som levende.

**Evidens:** `UPDATE person SET levende = FALSE` følges af en opdatering for personer med nylig fødselskonklusion og uden dødsrelaterede fakta. Ukendt fødselsår behandles som `FALSE`; faktum om død behøver i denne forespørgsel ikke en valgt konklusion.

**Konsekvens:** En eksisterende levende person uden tilstrækkeligt fødselsår eller med et uafklaret dødsfaktum kan blive markeret som afdød og dermed få forkert synlighed. Opdateringen rammer hele basen, ikke kun importens personer. Loaderens versionsport på `load_daa.R:289`–`297` stopper den ved kontraktversion 2, så fundet er **ikke** et bevis for en aktuel prod-skrivevej.

**Forslag:** Hold den gamle loader lukket; hvis en erstatning bygges, skal ukendt privathed være skjult som standard, og kun en afgrænset, godkendt personmængde må få genberegnet status fra gældende konklusioner.

**Sikkerhed:** Verificeret i koden; aktuel kontraktversion og data er ikke målt.

#### 1d.3c-05

**R-load / familietilknytning · Alvor: P1**  
**Sted:** `.claude/skills/daa-extract/scripts/load_helpers.R:390`; `.claude/skills/daa-extract/scripts/load_daa.R:917`

**Påstand:** Børnematcherens fallback kan vælge en union på ordenstal, selv om konteksten også indeholder et tvetydigt eller ukendt partnernavn.

**Evidens:** Når der ikke er præcis ét partnertræf, returnerer funktionen et entydigt ordenstalstræf før kontrollen for flere partnertræf. Loaderen indsætter derefter barnet i den valgte familie.

**Konsekvens:** Et modstridende eller utilstrækkeligt navnesignal kan omsættes til en positiv familiekant frem for et uafklaret tilfælde. Som i 1d.3c-04 er denne konkrete loadervej betinget af, at version 1-porten tillader den.

**Forslag:** Skeln mellem fraværende partnerbevis og et tilstedeværende, uafklaret eller modstridende partnersignal; parkér sidstnævnte og test både flere navnetræf plus ét ordenstal og ukendt navn plus ét ordenstal.

**Sikkerhed:** Verificeret af branchernes rækkefølge; ikke kørt mod data.

### Dom pr. område

- **Indholds-id:** **Ikke dækket tilstrækkeligt til dom.** SHA-256-afledning og nøgleordenskontrol er læst, men jeg har ikke gennemgået alle otte kaldesteders kollisionshåndtering.
- **Overførsel plan A:** **Hul.** Rehearsal beskriver afbrud og genkørsel, men allowlist-guardens grønne resultat er ikke bevis for det præcise datadelta.
- **Overførsel plan B1/B2:** **Ikke dækket tilstrækkeligt til dom.** Klassifikationen skelner mellem før-, efter- og blandet tilstand for de valgte lag, men korrekt lagvalg, hele nøglemappingen og den private runner er ikke fuldt verificeret.
- **R-load og helpers:** **Hul.** Versionsporten begrænser den gamle loaders rækkevidde, men dens privatheds- og familiematching er usikre, hvor den stadig kan køre.
- **R-fixups:** **Bør laves om.** Den aktive fixup kombinerer valgbar source med hårdkodede identiteter, og backfillens fryseguard er ikke atomisk med skrivningen.
- **Historisk `supabase_load.R`:** **Solidt afspærret ved indgangen.** Et ubetinget `stop()` står før forbindelse og reset; den efterfølgende historiske kode er ikke en aktiv normal kørevej.

### Læst fuldt

Følgende filer eller angivne sektioner er læst fuldt. De styrende dokumenter og invarianter er medtaget, fordi projektinstruktionerne kræver dem som grundlag; den samlede udskrift af de større styringsdokumenter blev afkortet, så de regnes ikke som fuldt læst.

1. `docs/evidensbaseret-genimport/vision.md`
2. `docs/evidensbaseret-genimport/roadmap.md`
3. `docs/reviews/2026-10-27-trin-1-5/systemkort.md:344–405`
4. `.claude/skills/daa-extract/scripts/transfer_steps.py`
5. `.claude/skills/daa-extract/scripts/transfer_ddl.py`
6. `.claude/skills/daa-extract/scripts/transfer_5ab_keymap.sql`
7. `.claude/skills/daa-extract/scripts/transfer_5ab_guards.sql`
8. `tests/sql/lib-transfer-5ab.sh`
9. `.claude/skills/daa-extract/scripts/test_transfer_ddl.py`
10. `.claude/skills/daa-extract/scripts/test_transfer_steps.py`
11. `.claude/skills/daa-extract/scripts/backfill_slaegtled.R`
12. `.claude/skills/daa-extract/scripts/post_load_fixup.R`
13. `.claude/skills/daa-extract/scripts/load_helpers.R:325–399`
14. `.claude/skills/daa-extract/scripts/load_daa.R:281–350`
15. `.claude/skills/daa-extract/scripts/load_daa.R:795–940`
16. `.claude/skills/daa-extract/scripts/load_daa.R:1024–1093`
17. `schema.sql:4255–4285`
18. `.claude/skills/daa-extract/references/transfer-5ab-ddl-allowed-data-delta.txt`

Øvrigt er læst som udsnit eller via `rg`, herunder `CLAUDE.md`, målarkitektur og status, de relevante runbookafsnit, `transfer_5ab_digests.sql`, `transfer_pack.py`, tests og R-scripts. Vigtigste søgninger: `content_uuid|deterministic_uuid|COLLATE "C"`, `data-delta|DATA_DELTA|classify|n_uuid_unmapped`, `dbBegin|dbCommit|UPDATE|contract_version|LegacyBackfillFreeze` samt `partner_ref_navn_enige|match_barn_union`.

### Hvad jeg ikke nåede

Jeg har ikke læst de øvrige `transfer_5ab_step_*.sql`, `transfer_answers.py`, alle ceremoni- og determinismetest eller hele `load_daa.R` og `load_helpers.R`. Jeg har heller ikke gennemgået hele `R/` eller `datamodel-oversigt.md`. Den private runner og dens faktiske pakkefiler ligger uden for den tilladte eksport og er ikke læst.

Ingen database, netværk eller tests er kørt. Derfor er hverken aktuel produktionstilstand, den konkrete ceremoni eller races reproduceret i dette review.