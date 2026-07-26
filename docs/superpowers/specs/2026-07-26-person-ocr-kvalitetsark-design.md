# Personers OCR-kvalitetsark — Design

**Dato:** 2026-07-26  
**Status:** Design godkendt i dialog; afventer brugerens review af dette dokument  
**Platform:** Kun web-redaktionen  
**Arbejdstræ:** `feat/person-spreadsheet-design`

## 1. Formål

Redaktøren skal kunne se alle rå, indlæste personposter i et spreadsheet-lignende
kvalitetsark, finde systematiske OCR-/indlæsningsfejl og rette dem i en
sammenhængende arbejdsgang.

Én række er altid én rå `person.id`. Rækker foldes ikke via `samme_som`, fordi
råposterne netop skal kunne sammenlignes, kvalitetssikres og rettes hver for sig.
Gridet viser dog kanonisk ID og matchstatus som kontekst.

Første version retter kun:

- navn
- fødselsdato
- dødsdato
- køn

Titler, familie og relationer vises som sammenfatninger og genveje til den
eksisterende personeditor. De redigeres ikke direkte i gridet.

## 2. Godkendte rammebeslutninger

1. **Rå personpost pr. række.** Ingen `same_som`-collapse i kvalitetsarket.
2. **Kun web.** Mobilens eksisterende personliste og personeditor ændres ikke.
3. **Enkeltrettelser først.** Ingen masseændringer eller paste-over-mange-celler
   i v1.
4. **Dedikeret databaseprojektion.** Griddets læsemodel leveres af én
   redaktionsbeskyttet RPC, ikke N evidensopslag pr. række.
5. **Grid + kildekontrol.** Tabellen er arbejdsfladen; den aktive fejl åbner et
   sidepanel med importværdi, kildekontekst og eksplicit gem.
6. **OCR-rettelse er ikke en ny historisk påstand.** Rettelsen korrigerer en
   fejlagtig transskription af samme kilde og må derfor ikke skabe en
   konkurrerende assertion eller en ny conclusion.
7. **Holdbar korrektionsjournal.** Rettelser og reviewafgørelser skal overleve
   fuld `load_daa.R --reset` og må ikke nøgles på regenererbare database-ID'er.
8. **Alle personer er altid tilgængelige.** QA-køen er et gemt view oven på det
   fulde datasæt, ikke griddets eneste indgang.

## 3. Begreber

| Begreb | Definition |
|---|---|
| **Rå personpost** | Én fysisk `person`-række før `samme_som`-collapse. |
| **OCR-rettelse** | Korrektion af databasens transskription/strukturering, så den afspejler den samme kildes faktiske udsagn. Ikke ny viden og ikke en ny kildepåstand. |
| **Redaktionel ændring** | Ny fortolkning, ny kilde eller valg mellem konkurrerende påstande. Håndteres fortsat af den eksisterende evidenseditor og er ikke gridets v1-skrivevej. |
| **Datasætnøgle** | Reload-stabil identitet for et importeret værk/datasæt, fx `daa:reventlow:1939`. |
| **Postnøgle** | Reload-stabil identitet for én extraction-post inden for datasættet. |
| **Kildefingeraftryk** | Deterministisk hash af postens relevante importerede værdi og OCR-kontekst. Forhindrer, at en gammel rettelse anvendes blindt på ændret input. |
| **QA-flag** | Deterministisk, ikke-skrivende signal om en mulig fejl. |

## 4. Nuværende model og den nødvendige særregel

`person.visning_navn`, `visning_foedt`, `visning_doed` og øvrige
`visning_*`-kolonner er afledte caches. De må aldrig være skriveautoritet.
Navn og datoer ligger som `fact → assertion → citation → conclusion`, og
`regen_person_visning` projicerer den valgte assertion til personrækken.

Den almindelige `red_edit_oplysning` er bevidst append-baseret: den opretter en
ny assertion og repointer conclusion. Det er korrekt for redaktionelle
ændringer, men forkert for en ren OCR-rettelse:

- den gamle OCR-fejl ville fortsat ligne et reelt udsagn fra kilden
- den nye assertion ville være uden den oprindelige `source_id`
- historikken ville ligne kildeuenighed, selvom kilden kun siger én ting

V1 indfører derfor en strengt afgrænset korrektions-RPC, som må opdatere den
importerede assertion på stedet. Særreglen bryder ikke evidenssemantikken:
assertionens tilsigtede betydning — “det kilden siger” — ændres ikke; kun den
fejlagtige transskription korrigeres.

Assertionens ID, fact, citation, `source_id`, conclusion og
`uforanderlig=true` bevares. `change_set`/`change_event` registrerer før- og
efter-snapshot, så rettelsen fortsat er sporbar og fortrydbar.

## 5. Overordnet arkitektur

```text
red_person_grid()  ───────►  Web-kvalitetsark
       │                         │
       │                         ├─ filtre/sortering/kolonnevalg
       │                         └─ aktiv celle + kildepanel
       │                                      │
       └──────── red_ret_ocr_felt() ◄─────────┘
                         │
                         ├─ valider aktuel import + fingerprint
                         ├─ begin_change_set
                         ├─ ret assertion eller person.koen
                         ├─ upsert import_korrektion
                         └─ returnér den genberegnede grid-række

load_daa.R
  ├─ identificér datasæt + postnøgle
  ├─ hent matchende import_korrektion
  ├─ kontrollér fingerprint
  └─ anvend rettelse før fact/assertion-bufferen bygges
```

Gridet foretager aldrig direkte tabelskrivninger. Alle skriverettigheder går
gennem den afgrænsede RPC.

## 6. Reload-stabile identiteter

Den nuværende model er ikke tilstrækkelig som varig korrektionsnøgle:

- `person.id` og `source.id` kan ændres ved reset
- `person_external_id` gemmer `linje` og heltals-`nr`
- loaderens interne matching kan bruge `nr_label`, som ikke føres frem til
  `person_external_id`

Derfor tilføjes additivt:

### `source.import_key`

- `TEXT`, reload-stabil og unik for et importdatasæt
- eksempel: `daa:reventlow:1939`
- loaderen skal kræve en eksplicit/deterministisk nøgle frem for at udlede den
  løst af en visningstitel

### `person_external_id.record_key`

- `TEXT`, den stabile extraction-postnøgle
- unik inden for `source.import_key`
- må bevare labels og andre identitetsdele tabsfrit; den må ikke reduceres til
  et heltal

Eksisterende rækker kan have NULL under migrationen. Kvalitetsarket tillader
læsning af dem, men OCR-rettelse er fail-closed, indtil en stabil postnøgle
findes.

## 7. Korrektions- og reviewjournal

Ny tabel: `import_korrektion`.

Minimumskontrakt:

| Felt | Betydning |
|---|---|
| `id` | Identitets-PK; ny tabel bør bruge identity/sekvens frem for `max(id)+1`. |
| `import_key` | Reload-stabil datasætnøgle; ingen FK til den regenererbare `source`-række. |
| `record_key` | Reload-stabil extraction-post. |
| `felt` | `navn`, `foedsel`, `doed`, `koen` eller `post` for et rent række-review. |
| `input_fingerprint` | Hash af det input afgørelsen gælder for. |
| `importeret` | Kanonisk JSON-snapshot af den observerede importværdi. |
| `korrigeret` | Kanonisk JSON med ny værdi; NULL ved “godkendt som korrekt” eller “udskudt”. |
| `status` | `aaben`, `rettet`, `godkendt`, `udskudt` eller `stale`. |
| `actor_id`, `actor_navn` | Hvem traf afgørelsen. |
| `oprettet_at`, `opdateret_at` | Audit-tidspunkter. |

Unik logisk nøgle: `(import_key, record_key, felt)`.

Tabellen:

- har RLS
- kan kun læses og skrives af redaktion
- har ingen FK til `person`, `source`, `fact`, `assertion` eller `citation`
- står uden for `load_daa.R`'s reset-liste
- optages i versionerings-/historikdesignet i det omfang, det ikke duplikerer
  dens egen actor/tids-audit

Hvis et fingerprint ændrer sig ved reload, sættes journalposten til `stale`.
Rettelsen anvendes ikke automatisk, og posten kommer tilbage i QA-køen.

## 8. Læseprojektionen `red_person_grid`

RPC'en returnerer én række pr. rå personpost og er den eneste griddatasource.
Den skal hente data set-baseret og må ikke udføre klientdrevet N+1.

Rækkekontrakten omfatter mindst:

### Identitet og import

- `person_id`
- `import_key`
- `record_key`
- source/udgave
- linje, nummer og eventuelle slægtled
- `samme_som`-status og kanonisk person-ID

### Kernefelter

- valgt/importeret navn
- rå fødselsdato og afledte bounds
- rå dødsdato og afledte bounds
- køn
- levende, privat, staged og status

### Sammenfatninger

- antal titler
- antal familier
- antal relationer
- antal kildebelagte assertions

### QA og review

- alle aktive QA-koder
- højeste alvor
- reviewstatus pr. redigerbart felt
- om rettelsen kan gemmes sikkert
- eventuel blokårsag, fx manglende `record_key`

V1 kan hente hele den paginerede projektion og filtrere/sortere i browseren.
Kontrakten skal være stabil nok til senere server-side filtre uden at ændre
rækkeformatet.

## 9. QA-regler

QA-regler er deterministiske og foretager aldrig automatisk skrivning.

V1 omfatter:

- mistænkelige OCR-tegn eller tegnmønstre
- ufortolkelig dato
- fødsel efter død
- struktureret værdi, der ikke stemmer med den bevarede OCR-kontekst
- manglende navn
- dubleret datasæt/postnøgle eller udgave + linje + bognummer
- manglende kildekontekst
- staged og uafklaret `samme_som` som kontekstflag

“Manglende fødsel” og “manglende død” er ikke automatisk fejl; historiske
personer kan legitimt mangle disse oplysninger. Sådanne completeness-signaler
må vises særskilt fra OCR-fejl.

Reviewstatus:

- **Åben:** fundet, ikke gennemgået
- **Rettet:** korrigeret
- **Godkendt:** mærkelig, men korrekt i forhold til det kontrollerede input
- **Udskudt:** kræver senere undersøgelse
- **Stale:** input har ændret sig siden afgørelsen

## 10. Kildepanelets sandhedsniveau

`citation.citat_tekst` kommer for loader-fakta fra extraction-feltet
`kilde_span`. Det er OCR-/extraction-kontekst, ikke i sig selv et facsimile af
den trykte bog.

Panelet skal derfor skelne tydeligt:

- **OCR-kontekst:** bevaret `kilde_span`/narrativtekst
- **Kildereference:** værk/udgave og side
- **Original side/facsimile:** kun hvis en faktisk billed-/PDF-side senere er
  tilgængelig gennem en autoriseret mediekobling

UI'et må aldrig kalde OCR-kontekst “bogens originale tekst”. En
karakterkorrektion kan gemmes efter redaktørens kontrol mod den eksterne
kildeside; facsimile-integration er nyttig, men ikke et v1-krav.

## 11. Web-UI

Det eksisterende personområde får en visningsvælger:

- **Liste:** nuværende personbrowser
- **Kvalitetsark:** nyt grid

### Faste views

- Alle personer
- Åbne OCR-fejl
- Rettede
- Godkendte
- Udskudte
- Stale

“Alle personer” viser også personer uden QA-flag. Seneste view og filtre kan
gemmes lokalt i browseren. “Nulstil filtre” går altid til alle personer.

### Grid

- sticky header
- fastlåste identitetskolonner
- sortering på relevante kolonner
- kombinerbare filtre
- kolonner kan skjules
- ingen checkbox-/bulk-handlinger i v1
- titler, familie og relationer er tællere/genveje, ikke inline-editorer

### Kildepanel

Panelet åbner for den aktive celle og viser:

- importeret værdi
- OCR-kontekst med korrekt label
- udgave og side
- ny værdi
- datoens foreslåede normalisering, når feltet er en dato
- korrektionshistorik
- “Gem OCR-rettelse”, “Godkend som korrekt”, “Udskyd” og “Annuller”

En celle gemmes aldrig på blur. En rettelse kræver eksplicit handling i
panelet.

Efter succes returnerer RPC'en den friske række. Griddet erstatter kun denne
række, genberegner filtre og kan flytte fokus til næste åbne fejl.

## 12. Skrivekontrakten `red_ret_ocr_felt`

RPC'en modtager logisk identitet, ikke kun et database-ID:

- `import_key`
- `record_key`
- felt
- forventet `input_fingerprint`
- korrigeret JSON-værdi eller reviewstatus

RPC'en skal:

1. kræve `current_rolle() = 'redaktion'`
2. slå aktuel source/person/fact/assertion op via de stabile nøgler
3. låse målposten og genberegne fingerprint
4. afvise ved mismatch med en konfliktfejl
5. kontrollere, at assertionen faktisk er importeret fra dette datasæt og er
   den relevante valgte assertion
6. starte ét `change_set`
7. opdatere assertionen på stedet for navn/dato eller `person.koen` for køn
8. bevare assertion-ID, fact, citation, `source_id`, conclusion og
   `uforanderlig`
9. upserte `import_korrektion`
10. returnere den friske grid-række

Ingen del må committe alene. Hvis journal-upsert eller datarettelse fejler,
rulles hele handlingen tilbage.

Almindelig `red_edit_oplysning` ændres ikke og bruges fortsat i den
specialiserede evidenseditor.

## 13. Datorettelser

Datoens rå tekst er den primære redigerbare værdi. Korrektionspayloaden kan
desuden rumme:

- `date_min`
- `date_max`
- `date_qualifier`
- `date_certainty`
- `calendar`

Normalisering skal være deterministisk og valideret mod de samme fixtures som
extraction-pipelinen. Implementeringsplanen skal vælge én fælles kontrakt og
paritetsteste TypeScript- og Python/R-forbrugerne; den må ikke kopiere en løs,
uafhængig parser uden tests.

Kan den rettede rå dato ikke normaliseres sikkert:

- den rå rettelse må gemmes
- bounds må ikke gættes
- usikre/ukendte bounds bliver NULL
- et “dato kræver normalisering”-flag forbliver åbent

Dermed undgås inkonsistens mellem rettet `date_raw` og gamle, fejlagtige bounds.

## 14. Fejl og samtidighed

- Ingen optimistisk dataændring før RPC-succes.
- Ved netværks-/RLS-/valideringsfejl forbliver panelet åbent med brugerens
  indtastning.
- Tomt resultat må aldrig fortolkes som vellykket rettelse.
- Fingerprint-konflikt forklares som “input er ændret; genindlæs og kontrollér
  igen”.
- En rettelse med manglende stabil postnøgle er blokeret, ikke nedgraderet til
  `person.id`.
- Rolle- eller sessionskift lukker skriveadgangen fail-closed.
- Genforsøg er idempotent via den logiske korrektion-key og det forventede
  fingerprint.

## 15. RLS og GDPR

Kvalitetsarket kan indeholde levende og private personer og må derfor kun være
tilgængeligt for redaktører.

- RPC'erne foretager eksplicit rollekontrol.
- `import_korrektion` har RLS og ingen anon-/almindelig authenticated-adgang.
- Eventuelle `SECURITY DEFINER`-funktioner får eksplicit `REVOKE EXECUTE FROM
  PUBLIC` og kun nødvendige grants.
- Ingen service-role-nøgle sendes til webklienten.
- En databaseprojektion/view må ikke omgå RLS ved et utilsigtet
  security-definer-view; RPC'ens adgangskontrakt er sikkerhedsgrænsen.
- Fejlmeddelelser og logning må ikke lække private rækkedata til almindelige
  brugere.

## 16. Verifikation

### Database

- redaktør kan læse grid; medlem og anon afvises
- OCR-rettelse opdaterer korrekt assertion og bevarer source/citation/conclusion
- ingen ekstra assertion eller conclusion oprettes
- kønsrettelse opdaterer kun den målrettede rå person
- `change_event` har korrekt før/efter
- fortryd genskaber data og gridprojektion
- journal og data er atomiske
- fingerprint-mismatch afvises

### Reload-fixture

1. Indlæs et lille datasæt.
2. Ret et felt gennem RPC'en.
3. Genindlæs med nye database-ID'er.
4. Bekræft, at rettelsen anvendes på samme logiske post.
5. Ændr input/fingerprint.
6. Bekræft, at rettelsen bliver `stale` og ikke anvendes blindt.
7. Medtag en post, hvis nummerlabel ikke kan repræsenteres tabsfrit som et
   heltal.

### Web

- “Alle personer” inkluderer rækker uden QA-flag
- kombinerede filtre og reset fungerer
- ingen skrivning på blur
- gem/godkend/udskyd opdaterer kun den aktive celle/række
- fejl bevarer udkastet
- manglende `record_key` viser blokårsag
- titler/familie/relationer åbner eksisterende editor
- ét pagineret gridopslag, ingen evidens-N+1
- nuværende liste og personeditor regresserer ikke

### Datoer

- eksakt dato, år, før/efter, cirka, interval og floruit
- OCR-typiske `I`/`1`- og `t`/`†`-tilfælde
- ufortolkelig rettelse bevarer raw og nulstiller/undlader bounds sikkert
- paritetsfixtures mellem extraction-normalisering og webkontrakt

## 17. Udrulning

Additiv rækkefølge:

1. `source.import_key`, `person_external_id.record_key`,
   `import_korrektion`, RLS og grants
2. læse- og korrektions-RPC'er
3. loaderens nøgle- og overlay-understøttelse
4. web-kvalitetsark

Database og loader kan udrulles før UI'et uden at bryde eksisterende web- eller
mobilklienter. Webvisningen må først aktiveres, når reload-fixturen og
rolle/RLS-testene består.

## 18. Bevidste fravalg i v1

- ingen mobilvisning
- ingen bulk-edit, paste eller fill-handle
- ingen inline-redigering af titel, familie eller relation
- ingen redigering af staged, `samme_som` eller privat i gridet
- ingen automatisk OCR-korrektion
- ingen LLM-baseret QA-gate
- ingen facsimile-/PDF-integration som leverancekrav
- ingen erstatning af den eksisterende evidenseditor
- ingen server-side filtermotor, medmindre målinger viser, at klientfiltrering er
  utilstrækkelig

## 19. Forventede komponentgrænser

- SQL: additive kolonner/tabel, RLS/grants, læse-RPC, korrektions-RPC
- extraction/loader: stabil datasæt- og postnøgle, korrektions-overlay og
  reload-fixture
- web data: grid-rækketyper, mapper, fetch og write-adapter
- web UI: view-vælger, filterlinje, grid, kildepanel og historik
- tests: SQL-verifikation, loader-fixture, rene QA/filtertests og
  komponentinteraktioner

Implementeringsplanen skal fastlægge de konkrete filankre efter endnu en
live-inspektion af branchens aktuelle schema-, loader- og webfiler. Den må ikke
udvide v1 til de bevidste fravalg ovenfor.
