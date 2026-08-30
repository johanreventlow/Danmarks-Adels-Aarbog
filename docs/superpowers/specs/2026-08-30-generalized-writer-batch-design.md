# #153: Varig writer- og batchkontrakt

**Dato:** 2026-08-30

**Status:** Godkendt design. Implementering kræver en separat, reviewet plan.

## Formål

#153 etablerer den editionsneutrale kontrakt, som de varige, muterende genimportveje skal opfylde. Kontrakten bruges af fire afgrænsede domæneflows:

1. C3-sags apply og reversal;
2. evidens-promotion, herunder atomiske promotionsbatches;
3. narrative record-key-cutover;
4. source-scoped replace af en udgaves kildeejet data, herunder den nu frosne DAA-loaders direkte narrativwrite.

Målet er ikke at ensrette deres genealogiske effekt eller at bygge en ny generisk databasejournal. Målet er, at hver writer dokumenterbart identificerer sit input, sin autorisation, sit replayforløb, sin låseadfærd og sit verificerede slutresultat på samme måde.

## Roadmapkobling

| Krav | #153's svar |
| --- | --- |
| Roadmapmål | #153, efter #152 og før #149. |
| Værdikædeled | Den kontrollerede overgang fra redaktionelt godkendt input til kanonisk/publiceret effekt. |
| Leverancetype | Varigt, editionsneutralt kontraktfundament med fire domæneadaptere. |
| Redaktionel/læserrettet værdi | Redaktøren får én gennemskuelig måde at se autorisation, forventet effekt, receipt og fortrydelsesmulighed på; læserens publicerede kildebinding bliver ikke en uigennemskuelig sideeffekt. |
| Færdigbevis | Den nye source-scoped writer og de to fortsat muterende adaptere opfylder den samme kontrakttest mod en frisk disposable database; C3 beviser efter #152 sin historiske konformitet uden ny write-adgang. Alle resultater afviser drift og har en dokumenteret terminal receipt. |
| Erstattet workflow | `load_daa.R`'s og de tilhørende direkte narrative-updateres v1-writevej. Domænespecifikke ledger-tabeller og RPC'er erstattes ikke. |

Dette er en nødvendig forudsætning for 2018-20 fase A, men er ikke i sig selv beviset for generalisering. Det fulde bevis kræver fortsat en faktisk 2018-20-kæde og derefter en tredje årbog uden nye permanente editionsnavngivne overflader.

Projektejerens udtrykkelige beslutning 2026-08-30 aktiverer #153 efter den færdiggjorte #152-leverance. Roadmap, status og beslutningsloggen registrerer samme tilstand uden at ændre den styrende rækkefølge.

## Bindende afgrænsninger

- Der oprettes ikke en fælles, generisk journal- eller eventtabel på tværs af datamodellen.
- Eksisterende C3-ledger, promotion-tabeller og narrative-cutover-receipts bevarer deres domæneejerskab og migrationshistorik.
- Kontrakten må ikke skabe en generisk writer med vilkårlige tabelnavne, fri SQL, caller-styrede counts eller caller-styrede forventede hashes.
- Ingen adapter må gøre en tidligere privat eller uafklaret fortolkning kanonisk eller offentlig uden den pågældende domæneflows eksisterende, udtrykkelige redaktionelle grundlag.
- Ingen produktionsdatabase, production apply, reversal, cutover, push, merge eller deploy er omfattet af design- eller implementeringsgodkendelsen.
- Udgave-, slægts- og OCR-særregler hører i små profiler eller inputartefakter, aldrig i kontraktens permanente navne eller branches.

## Den fælles writer-kontrakt

Hver adapter skal eksponere en versionssat operationprofil. Profilen er en lukket, maskinvalideret struktur og indeholder mindst:

- `operation_family`: stabil editionsneutral familie, fx C3-sagsændring, evidenspromotion eller narrative-contract-cutover;
- `contract_version`: et eksplicit versionsnummer;
- `execution_kind`: `apply`, `reversal`, `promotion`, `cutover`, `recover` eller `conformance_read_only`;
- `reversal_mode`: `exact_restore`, `compensating` eller `not_supported`;
- en eksakt, kanonisk inputidentitet: schema-version, canonical JSON-SHA-256, og eksplicit scope over de berørte stabile elementer;
- databaseidentitet, forventet schema-/kontraktversion og et lukket `authorization_mode`;
- adapterens stabile element-ID'er, forventede counts og adapter-specifikke før-/efterinvarianter;
- en deklaration af de låse og den globale låseorden, adapteren bruger for overlap med andre writers;
- receipt-schema, terminale statusser og den postverify, som er nødvendig for at udstede en grøn receipt.

Kontraktens fælles serialisering skal være deterministisk: samme semantiske input giver samme bytes og SHA-256; ukendte felter, manglende felter, duplikerede element-ID'er og anden sortering afvises. Hver adapter må have yderligere domænefelter, men kun under sit lukkede adapter-schema.

### Autorisation og idempotens

Hver muterende adapter skal erklære og håndhæve ét af tre lukkede modes: `single_use_database_authorization`, `actor_bound_preview_authorization` eller `external_go_nonce_authorization`. `authorization_mode=none` er kun gyldig for en dokumenteret read-only operation. Autorisationen skal være bundet til den aktuelle database, den autentificerede redaktør eller den dokumenterede eksterne trust root, og den eksakte inputidentitet. Adapteren må aldrig tage aktør, forventede counts eller inputhashes ukontrolleret fra klienten.

Et exact replay skal enten returnere den oprindelige verificerede receipt eller et udtrykkeligt, maskinlæsbart `already_applied`-resultat med samme identitet. For en `cutover` kan den eneste tilladte replayvej i stedet være det eksplicit deklarerede `recover`-forløb; den må ikke foregive en ny apply. Et replay med blot én afvigende hash, scope, autorisation eller effekt skal fejle før domænemutation med en stabil driftfejl. En fejl før terminal receipt må ikke efterlade en delvis synlig effekt. En receipt er historisk bevis; senere live-drift måles af en særskilt current-state-verifier og gør ikke den historiske receipt usand.

### Låse og terminal effect

Hver adapter skal deklarere sin konkrete låseorden. For fælles ressourcer skal planen bevise, at ordenen ikke inverterer mod de to øvrige adaptere. Når source records, personer, narrativer eller publication bindings overlapper, skal fraværs- og eksisterende-række-tilstande begge være beskyttet. Lokale domænelåse kan ligge efter de fælles ressourcer, men må ikke skabe en cyklus.

En receipt udstedes først efter adapterens egen postverify har kontrolleret den faktiske databaseeffekt. Receipt'en skal binde operationprofil, inputidentitet, autorisation (hvor relevant), batch-/operation-ID, terminal status, eksakte counts og den verificerede eftertilstand. Den er ikke en ny global journal; den projekteres fra eller lagres sammen med adapterens eksisterende domæneledger.

## Adapterkrav

### C3 apply/reversal (historisk konformitet)

C3 beholder `reimport_case_authorization`, `reimport_case_batch` og `reimport_case_event` som sin historiske ledger. Den deklarerer `execution_kind=conformance_read_only` efter narrative-contract version 2; en ny C3 apply eller reversal er bevidst lukket og skal fortsat afvises med `NARRATIVE_RECORD_LEGACY_WRITER_DISABLED`. Konformitetstesten læser de historiske batches, deres `exact_restore`-reversal receipts og deres hash-/CAS-invarianter uden at åbne en batch eller ændre publication-eventhistorik.

#153 må kun tilføje read-only kontraktmapping, fælles testværktøj eller nødvendige interoperabilitetsgates; den må ikke genåbne C3, udvide den med 1939-specialfaser eller lade den skrive uden om #152-eventloggen.

### Evidens-promotion

Promotion beholder `interpretation_promotion_batch` og de individuelle, append-only `interpretation_promotion`-rækker. Adapteren skal gøre previewidentitet, profilversion, atomiskhed, exact replay og postverify maskinverificerbare som en writer-kontrakt. Den må fortsat kun forbinde en godkendt fortolkning med et eksisterende, valideret kanonisk assertion-mål og må aldrig oprette eller ændre genealogiske kerneobjekter.

Promotion bruger `authorization_mode=single_use_database_authorization`: den udstedes til én editor, én database, én preview-/regelprofilhash og ét lukket element-scope; den har udløb, engangsforbrug og terminal status. Batch-ledgeren skal udvides eller suppleres adapterejet med den autorisation, de observerede counts, postverify-resultatet og receipt-bindingen. Promotion erklærer indtil en særskilt, godkendt domænespecifikation andet `reversal_mode=not_supported`. Append-only audit må ikke slettes eller omfortolkes som en teknisk rollback. Receipt og redaktionel UI/runbook skal gøre denne begrænsning synlig før execution.

### Narrative record-key-cutover

Narrative-cutover beholder sin eksklusive contract-version, nonce-bundne receipt og hele inventory-/postverify-gaten. Adapteren bruger `authorization_mode=external_go_nonce_authorization`: den menneskelige projektejer-GO, dens hashbundne approval-artefakt og den engangs nonce er trust root; receipt'en skal fortsat binde disse til databaseidentitet og terminal effekt. `execution_kind=recover` er den eneste tilladte genoptagelsesvej efter ukendt commit-resultat. Adapteren erklærer `reversal_mode=not_supported`: #153 opfinder ikke en efterfølgende tekst-/binding-rollback. I stedet skal preflight og terminal receipt tydeligt vise, at operationen er en autoriseret, one-shot schema-/dataovergang med fail-closed inventory og fuld postverify.

Kontraktmappingen må ikke svække den eksisterende låsning af både rækker og fraværsmængder, eller gøre nye direkte læsere, private bindinger eller identitetsblokerede records synlige.

### Source-scoped replace-writer

Denne er den obligatoriske permanente afløser for den efter #152 frosne direkte narrative-write i `load_daa.R` og de tilsvarende direkte updatere. Den arbejder altid mod et eksplicit source-scope og stabile `record_key`-identiteter, bevarer eksisterende person-ID'er ved entydigt match og ændrer kun positivt kildeejet data. Redaktionsarbejde, fremmed kildeevidens, publication-eventhistorik og rækker med uklart eller blandet ejerskab fredes fail-closed.

Writeren bruger `authorization_mode=single_use_database_authorization` og `reversal_mode=compensating`. En kompensation er en ny, særskilt autoriseret source-scoped replace mod et tidligere content-addressed manifest; den må ikke slette redaktionel eller append-only historik og må ikke udlede slettebevis af fravær. Før write kræves et read-only dry-run med entydige/tvetydige/nye/bortfaldne udfald, låst source-scope, ownership-rapport og en konkret forventet delta. Tvetydighed, nyt data uden eksplicit policy, bortfald uden særskilt beslutning eller enhver ownership-konflikt afviser hele batchen før første write.

For hvert source-ejet narrativ skal writeren bruge #152's record-bundne publicationvej og kun disse overgange: ingen binding eller kun withdrawn historik plus entydig accepteret identitet kan oprette en `draft_created`; en aktiv `draft` uden identitetskonflikt kan ændres med `draft_updated`; aktiv `published` eller `stale_published`, legacy uden binding, manglende/stale anchor, identitet til anden person eller en `haendelse`-afhængighed afviser den enkelte planlagte ændring før batchens første write. Writere må aldrig ændre publiceret tekst, skabe `published_revision`, gøre en publicering stale eller udføre withdrawal. Den eventuelle offentlige tekstændring forbliver en særskilt, menneskegodkendt `Publicér ændring`-handling gennem #152-RPC'en. Batchens preflight er kun grøn, når hver narrativændring passer til én af de tilladte draft-overgange; ellers er hele source-scopet `NO-GO`.

Efter write skal postverify bevise bevarede person-ID'er, uændret redaktionelt/fremmed materiale, korrekt record-event/projection-effekt, idempotent exact replay og det deklarerede source-ejede delta. Direkte narrative mutation uden denne kontrakt forbliver afvist med `NARRATIVE_RECORD_LOADER_MIGRATION_REQUIRED`.

Postverify skal herudover bevise præcis én `draft_created` eller `draft_updated` publication-event pr. autoriseret narrativeffekt og ingen `published`, `published_revision` eller `withdrawn`-event fra writeren.

## Implementeringsform

Fælles implementation begrænses til små, editionsneutrale hjælpere for canonical JSON/hash, lukket operationprofil-validering og receiptkontrol. Domæne-RPC'er, ledger-tabeller og postverify bliver adapterejede. En ny årbog tilføjer en profil og en adapterkonfiguration; den må ikke kræve en ny permanent editionsnavngivet databaseoverflade.

Planen skal før enhver ændring kortlægge levende schema, migrationer, RLS, RPC'er, R/Python-orchestratorer og SQL/integrationstests for alle fire adaptere. Historiske planer er ikke nok som teknisk facit.

## Test- og sikkerhedskontrakt

Hver fortsat muterende adapter skal på en frisk disposable PostgreSQL-database mindst bevise:

1. lukket profil- og inputvalidering;
2. forkert databasebinding, udløbet/manglende autorisation og hashdrift afvises før mutation;
3. en gyldig execution er atomisk og giver én verificerbar terminal receipt;
4. exact replay er idempotent, mens semantisk drift afvises;
5. adapterens declared reversal-mode efterleves: source-scoped replace kompenserer kun gennem et nyt autoriseret manifest, mens promotion og cutover ikke udgiver en falsk rollbackgaranti;
6. postverify før finalisering opdager ændret eftertilstand og nægter grøn receipt; en separat current-state-verifier rapporterer senere drift;
7. samtidige operationer med overlappende fælles ressourcer ikke deadlocker eller bryder absence-/ownership-invarianter;
8. `anon`, almindelig `authenticated` og ikke-redaktionelle roller ikke får direkte læse-/skrive-/execute-adgang til private kontraktdata eller private hjælpere.

En separat tværadaptertest skal køre source-scoped replace, promotion og cutover-profiler mod samme bootstrap og kontrollere deres fælles kontraktfelter uden at antage ens domænepayload. En C3-konformitetstest skal desuden bevise, at de historiske receipts kan læses, men at version-2-gaten afviser ny C3 mutation. Grønne enhedstests alene er ikke tilstrækkelige; mindst én integrationstest skal bruge hver rigtig databasevej og hver rigtig postverify.

## Ikke-mål og færdigkriterier

Ikke-mål er at gennemføre 2018-20 fase A, køre en ny årbog, generalisere den fulde importer eller give produktions-GO. #153 er færdig, når source-scoped replace, promotion og cutover opfylder ovenstående kontrakt med grønne, afgrænsede og tværadapter disposable-DB-tests; C3 er verificeret historisk og lukket for ny write; deres runbooks er konsistente med deres erklærede reversal-mode; og independent review har vurderet de sikkerheds- og dataintegritetsrelevante ændringer.

Den fælles genimportmetode forbliver fail-closed og højst `isoleret implementeret`, indtil roadmapets senere praktiske generaliseringsbevis er gennemført.
