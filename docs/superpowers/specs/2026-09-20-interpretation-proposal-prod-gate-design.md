# 4.4 fortolkningsforslag: produktionsgate og append-only reversal

**Dato:** 2026-09-20  
**Status:** Godkendt 2026-09-20; ingen produktionsmutation
**Issue:** #196  
**Roadmap:** trin 4, den fælles fortolkningskæde og klausulgranularitet (#147/#148)

## 1. Beslutning

4.4's `interpretation_proposal` må først få produktions-GO, når tre
udgaveneutrale leverancer findes og er bevist mod en frisk, disponibel restore af
produktionstilstanden efter 4.1c:

1. en læse-kun fortolkningsprojektion og en databasefri komparator;
2. en append-only, autoriseret batch-reversal, der kun virker før menneskelige
   afgørelser eller promotion;
3. en produktionswrapper og runbook med eksakt mål-, input- og
   autorisationsbinding.

Leverancen gør 4.4 **prod-GO-klar**. Den giver ikke GO og kører ikke mod
produktion.

Den valgte løsning er operation-specifik og genbruger de eksisterende generelle
kontrakter for writer, autorisation, batch, låse og versionshistorik. Den
allerede produktionsbrugte 4.1c-projektion generaliseres eller omskrives ikke.

## 2. Roadmapets seks adgangskrav

1. **Roadmapmål:** trin 4, #147/#148. #196 lukker specens åbne punkt 11.1 for
   fortolkninger; reversal lukker den del af punkt 11.5, der gælder 4.4's
   maskinelle forslag.
2. **Værdikædeled:** proposed interpretations → menneskelig afgørelse. Gaten
   beviser den maskinelle ingests eksakte delta og giver en sikker vej tilbage,
   før mennesket overtager.
3. **Leverancetype:** generel og udgaveneutral. Ingen funktion, tabel, profil
   eller permanent workflow-overflade navngives efter 2018-20 eller 1939.
4. **Redaktionel og læserrettet værdi:** redaktionen kan modtage kildebundne
   forslag uden at risikere, at et forkert batch kun kan fjernes ved fuld
   database-restore. Offentlig og kanonisk tilstand måles som uændret.
5. **Færdigbevis:** syntetiske kontrakttests, SQL-race-tests, fulde relevante
   suiter og én frisk prod-afledt rehearsal med
   `før → dry-run → apply → match → reversal → recovery-match → genkørsel`.
6. **Workflow der erstattes:** de private `44-apply.R`-udlæg, som kunne
   re-autorisere under apply, manglede eksplicit produktionsguard og kun havde
   restore af hele databasen som recovery.

## 3. Nuværende tilstand og problem

Skemaet og writeren for `interpretation_proposal` er deployet i produktion,
men writeren er ikke kørt der. Rehearsalen mod 4.3b-restoren skrev 84 forslag i
otte elementer, oprettede én extraction-run og 19 nye
klausuldispositionsversioner uden kanonisk delta.

Den nuværende mangel har tre dele:

- fase-pakke-gaten kan ikke afstemme fortolkninger, observationslinks,
  extraction-run og dispositionsovergange;
- en forkert, finalized proposal-batch kan kun fjernes ved fuld restore;
- det private apply-udlæg er ikke en egnet produktionsgrænse.

En restore-only-model blev forkastet. En restore kan slette alle redaktionelle
ændringer siden backuppen og giver ikke en normal, auditerbar recoveryvej.

## 4. Arkitektur og komponenter

### 4.1 Fortolkningsprojektion

Projektionen følger #195's mønster:

- SQL kører read-only mod én navngiven `source_id` og én konkret database;
- ejerprojektion og `anon`-projektion tages i samme konsistente snapshot;
- output indeholder kun identiteter, feltnavne, hashes, boolske invarianter og
  counts — aldrig kildetekst, claimværdier, navne eller narrative bytes;
- komparatoren har ingen databaseadgang og modtager før-projektion,
  efter-projektion, manifest og forventet målidentitet.

Projektionskontrakten skal mindst dække:

- databaseidentitet og source-identitet;
- de fem eksisterende neutrale lister;
- helrækkehashes for kanoniske og offentlige tabeller;
- `anon`-projektionens hashes;
- upstream source records, occurrences, ankre, klausuler, mentions, personas,
  persona-mention-links, identitetsafgørelser og placements;
- `private.interpretation`, `interpretation_observation`, relevante
  `extraction_run`-rækker og hele dispositionshistorikken for de berørte
  klausuler;
- den præcise reimport-autorisation, batch og alle relevante events;
- promotion- og beslutningstabeller som neutralitetsflade.

Komparatoren genberegner manifestets hash og afviser ukendte eller ekstra
nøgler. Et apply-`match` kræver samtidig:

1. samme forventede database før og efter;
2. uændret upstream, kanonisk, offentlig og `anon`-tilstand;
3. én ny finalized batch med manifestets source, profil og hash;
4. ét autoriseret event pr. manifest-element og ingen fremmede events;
5. eksakt ét forslag pr. ingestible claim;
6. eksakte observationslinks til manifestets citerede klausuler;
7. én extraction-run med de forventede runner-, model- og promptbindinger;
8. kun de forventede klausuler får ny disposition, med korrekt prioritet mellem
   `fortolkning_foreslaaet` og `afventer_identitet`;
9. ingen ændring af andre fortolkninger, links, runs eller dispositioner.

Et senere `already_applied`-kald er ikke byte-identisk med efter-projektionen:
den levende replayvej konsumerer en ny autorisation, selv om den genbruger den
finalized batch. En særskilt replay-komparator tillader præcis denne ene nye,
korrekt bundne consumed authorization og kræver nul andre deltaer.

Manifestets claimværdier må ikke skrives til projektionsfilen. Writerren
beregner i stedet kanoniske hashes og et resultat-receipt pr. claim og klausul.
SQL-projektionen efterprøver, at de lagrede rækker svarer til eventets
autoriserede input, og eksporterer kun receiptet og invarianterne. Komparatoren
sammenholder disse med manifestets egne kanoniske hashes.

### 4.2 Resultat-receipt i reimport-eventet

`interpretation_proposal`-eventet udvides med en lukket, versioneret
`result_receipt` uden rå værdier:

- `claim_id`;
- `interpretation_id`, `interpretation_key` og version;
- kanonisk `value_sha256` og helrækkehash;
- `extraction_run_id`;
- sorterede observationslinks med observation-id, klausulordinal,
  `verbatim_sha256`, evidensrolle og linkordinal;
- berørte klausuldispositioners observation-id samt lukkede `before`- og
  `written`-receipts med version, disposition og helrækkehash. Flere events på
  samme klausul skal danne én ubrudt kæde tilbage til samme præ-batch-baseline.

`after_sha256` er hash af det lukkede resultat-receipt, ikke en løs optælling.
Receiptet er den eksakte write-set-binding for projektion, commit-unknown og
reversal. Der oprettes ikke en parallel editionsspecifik receipt-tabel.

Helrækkehash er her et operationelt navn, ikke PostgreSQLs implicitte
composite-tekstformat. Operationen får en dedikeret kanonisk JSON-/SHA-helper
med denne bytekontrakt: UTF-8; nøgler i Unicode-scalar-rækkefølge svarende til
`COLLATE "C"` over gyldig UTF-8; ingen Unicode-normalisering; minimal JSON-
escaping med lowercase hex; rå non-ASCII; stabile literals; kun signed 64-bit
heltal som numeriske tokens. Timestamps og decimaler i row-receipts er
normaliserede strenge. Parsed fraktioner/eksponenter afvises, mens leksikalsk
negativt nul kanoniseres som `0`. Hver relation har et versionsfast, lukket JSON-feltsæt. SQL-projektion,
writer, state-hash og komparator bruger samme golden-byte-kontrakt. Den
eksisterende generelle kanoniske helper ændres ikke, fordi ældre profilhashes er
en bagudkompatibilitetsgrænse.

Manifestets `claim_id` er transportidentitet, ikke databasefortolkningens UUID.
Den levende `key_version=1`-algoritme flyttes byte-identisk til én privat SQL-
helper. Writer og SQL-projektion genberegner nøglen dér; receiptet binder
`claim_id` til den validerede `interpretation_key` og et key-material-hash.

### 4.3 Append-only proposal-reversal

Reversal er en ny editionsneutral operation oven på de eksisterende
`reimport_authorization`, `reimport_batch`, `reimport_event`,
`interpretation` og `clause_disposition`-kontrakter.

Den eksisterende `red_reverse_reimport` ændres ikke til at skjule to
forskellige semantikker. Den er bundet til aktiverede person-/name-completion-
batches. Proposal-reversal får navngivne RPC'er for autorisation, apply og
resultatlæsning.

Autorisationen bindes til:

- batch-id, manifesthash, source, profil og databaseidentitet;
- batchens eksakte, genberegnede proposal-state-hash;
- forventede antal elementer, claims, links og dispositionsversioner;
- aktør, nonce og kort udløbstid.

Reversal og proposal-apply tager først den eksklusive side af den eksisterende
`daa-narrative-record-contract`-advisory lock, derefter generic writer-lock og
de eksisterende anchor-advisory keys, før deterministiske `FOR UPDATE`-låse.
Dermed færdiggøres eller blokeres andre kontraktwriters før state genberegnes.
Under disse låse skal reversal afvise, hvis:

- batchen ikke er en ren, finalized `interpretation_proposal`-batch;
- eventer eller receipts ikke matcher autorisation og aktuelle rækker;
- en fortolkning ikke længere er den aktuelle `proposed`-version;
- en senere beslutningsversion findes;
- en berørt fortolkning er promoveret eller indgår i et promotion-batch;
- en klausul har fået en senere disposition end den version, batchen skrev;
- extraction-run, observationslinks, source/persona-binding eller målbase er
  drevet;
- autorisationen er forkert, udløbet, genbrugt eller udstedt til en anden aktør.

Ved et grønt preflight udføres alt i én transaktion:

1. For hvert proposal indsættes en ny `superseded`-version med samme
   fortolkningsdata og kopierede observationslinks. Beslutningsevidensen binder
   original batch, event, manifest og reversal-autorisation.
2. For hver distinkt berørt klausul kopieres den receipt-bundne maskinelle
   disposition umiddelbart før batchens første 4.4-write som en ny
   maskinel version. Både proposal-apply og reversal afviser en aktuel eller
   præ-apply menneskelig disposition. Reversal-evidensen er kompatibel med den
   levende dispositionstrigger: originalt manifesthash og proposal-batch-id er
   obligatoriske, og evidensen binder desuden reversal-autorisation,
   proposal-state og hash af den tidligere maskinevidens.
3. Der indsættes ét reversal-event med før-/efter-state-hash og eksakte counts.
4. Autorisationen konsumeres, og originalbatchen markeres `reversed`.

Ingen fortolkning, link, disposition, extraction-run, event, autorisation eller
batch slettes.

Proposal-state-hashen omfatter desuden en særskilt upstream-binding til den
eksakte accepted anchor-event og occurrence, root-observation, citerede
klausuler, source mentions, primære persona-link, source persona, aktive
predicate-rækker, extraction-run og databaseidentitet. Identity/placement er
ikke inputs til den levende proposal-writer og hører derfor kun til den brede
projektionsdrift, ikke operationens state-graf. Apply genberegner bindingen efter
hele låseprotokollen; preflight alene autoriserer aldrig en driftet state.

Et recovery-`match` betyder derfor ikke byte-identisk database med før-billedet.
Det betyder, at batchen ikke længere har aktive `proposed`/`accepted`-
fortolkninger eller promotion, at klausulernes aktuelle dispositioner svarer til
før-billedet, og at de nye superseded-versioner og reversal-events udgør den
forventede append-only historik.

### 4.4 Kontrolleret genkørsel

Den nuværende writer afviser enhver eksisterende `interpretation_key`. Den
udvides snævert, så samme deterministiske nøgle kan få en ny `proposed`-version,
men kun når den aktuelle version:

- er `superseded`;
- bærer den lukkede batch-reversal-evidens;
- stammer fra en batch med status `reversed`;
- ikke er promoveret og ikke har en nyere version.

Alle andre eksisterende nøgler afvises fortsat. Den nye proposal-version
refererer til den superseded version, bruger den nye extraction-run og kopierer
kun det nye manifests observationslinks. Dermed kan en korrigeret kørsel
gentages uden at remint'e identitet eller slette historik.

### 4.5 Commit-unknown og idempotens

Reversal-læsefunktionen returnerer kun metadata og én af følgende tilstande:

- `not_started` — ingen gyldig reversal-event;
- `reversed` — event, batchstatus, autorisation og aktuelle superseded-versioner
  matcher receiptet;
- `drift` — noget findes, men den samlede kontrakt stemmer ikke.

Et gentaget reversal-kald efter en verificeret reversal udfører ingen nye writes
og returnerer det eksisterende resultat. Ved `drift` stoppes der.
Resultatlæsningen er den eneste recoveryvej efter forbindelsestab; operatøren må
ikke gætte ud fra en klientfejl.

Proposal-apply har en separat resultatfunktion slået op alene på
autorisation-id, så et batch-id i en tabt klientproces ikke er en
recoveryforudsætning. Den returnerer kun `not_started`, `committed` eller
`drift`. `committed` kræver én konsumeret autorisation, én finalized batch,
eksakte counts/events/receipts og aktuelle rækker samt samme aktør og
databaseidentitet. Åben, delvis, duplikeret eller forkert bundet state er altid
`drift`.

Begge resultatfunktioner er datamæssigt læsende, men låsetagende. De tager først
shared narrative-contract-lock, derefter samme source/profile-writer-lock som
apply og derpå authorization/batch/result-rækker `FOR UPDATE`. Først efter en
igangværende commit eller rollback er afsluttet, må `not_started`, `committed`,
`reversed` eller `drift` klassificeres. Reversal-RPC'en tager den eksklusive
contract-lock først og kalder den private result-helper i en eksplicit
"lock-already-held"-tilstand; shared→exclusive lock-upgrade er forbudt.

### 4.6 Produktionswrapper

En lille editionsneutral wrapper er den eneste dokumenterede 4.4-prod-indgang.
Den:

- accepterer kun et manifest, hvis alle operationer er
  `interpretation_proposal`;
- verificerer manifestbytes, manifesthash, preview-hash, source, profil og
  forventet databaseidentitet samt bytehash og indhold af både pre-GO-pakke og
  execution-envelope;
- kræver en allerede udstedt autorisation og må aldrig kalde
  autorisations-RPC'en;
- kræver et ordret, eksplicit produktionsflag;
- afviser dry-run mod en base, hvor manifestets forslag allerede findes;
- udskriver kun ids, hashes, counts og status;
- håndterer forbindelsestab med resultat-RPC'en, ikke med automatisk genapply.

Hver ordinær eller ny recoveryforbindelse rydder libpq-miljøet, forbinder med
de eksplicitte connection fields, genberegner og sammenligner målidentiteten,
skifter med `SET LOCAL ROLE authenticated`, etablerer derefter den forventede
editoraktør som transaktionslokal claim og verificerer `current_user`,
`auth.uid()` og redaktørrollen før første RPC. En resolver må
ikke arve mål- eller aktørvalidering fra den tabte forbindelse.

CLI'en har særskilte `proposal-result` og `reversal-result`-kommandoer. Hver
write/result-kommando kræver den relevante uforanderlige envelope og matcher en
frisk authorization-readback mod den. Hele processen, inklusive sourcing,
parsing, filadgang, subprocess og connect, ligger bag én lukket fejlgrænse:
kendte koder kan ledsages af validerede
ids, hashes, feltnavne og counts; ukendte DBI-, connect- og subprocessfejl
bliver en generisk intern kode. Rå condition-messages, DSN'er, passwords,
filstier og værdier må aldrig udskrives.

Den generelle `apply_reimport.R` og dens gateway genbruges som intern motor.
Andre reimportoperationers CLI-kontrakt ændres ikke.

## 5. Dataflow

### 5.1 Normal apply

1. Luk eller disponér 4.1c's åbne restore-vindue.
2. Etabler redaktionel skrivepause.
3. Tag læse-kun preflight og før-projektion.
4. Tag backup og restore netop den backup.
5. Gennemfør fuld rehearsal, inklusive proposal-reversal og korrigeret genkørsel.
6. Lås en uforanderlig pre-GO-pakke til commit, databaseidentitet, filer,
   hashes, manifest, preview og forventede counts; pakken indeholder ingen
   autorisation.
7. Giv eventuelt eksplicit GO mod pre-GO-pakkens hash, udsted én autorisation,
   og lås en separat execution-envelope til pre-GO-hash, GO-kvittering,
   autorisations-id/udløb/readback, aktør og egen hash. Pre-GO-pakken ændres
   aldrig.
8. Kør prod-wrapperen én gang mod execution-envelope.
9. Tag efter-projektion og kør den databasefri komparator.
10. Kun `match` kan lukke apply; ellers aktiveres recoveryrunbooken.

### 5.2 Reversal

1. Tag frisk proposal-state og efterprøv, at batchen stadig er reversibel.
2. Udsted én kortlivet reversal-autorisation til den konkrete state-hash.
3. Kør reversal én gang.
4. Ved klientfejl: læs resultatstatus; kør ikke automatisk igen.
5. Tag efter-reversal-projektion.
6. Recovery-komparatoren kræver samme aktive semantiske tilstand som før apply,
   uændrede neutrale/public/anon-hashes og den forventede append-only historik.

## 6. Fejlhåndtering

Alle fejl er stabile, maskinlæsbare koder og må kun ledsages af ids, hashes,
feltnavne og counts. Ingen fejl må indeholde kildetekst eller claimværdier.

Fejlgrupperne er:

- projektionsform, manifestform eller hashdrift;
- uventet database/source/profil;
- neutralitets-, kanonisk- eller anon-drift;
- manglende, ekstra eller afvigende proposal-/link-/run-/dispositionsrækker;
- ugyldig batch-/event-/receiptbinding;
- ugyldig eller stale reversal-autorisation;
- menneskelig afgørelse, promotion eller anden downstream-afhængighed;
- stale klausuldisposition eller konkurrerende writer;
- commit-unknown `drift`.

Race-sikkerhed bevises, ikke antages: reversal konkurrerer i tests med menneskelig
afgørelse, promotion og dispositionsskrivning i begge lock-orderings. Testene
skal observere reel ventetilstand med bounded timeout, afvise deadlock/timeout som
success og bevise, at præcis én side vinder, mens den anden stopper uden partiel
effekt.

## 7. Verifikation

### 7.1 Test-first

Implementeringen følger TDD. Før produktionskode ændres, skal røde tests findes
for mindst:

- projektionens lukkede skema og manifestvalidering;
- hver enkelt driftklasse;
- eksakt event-receipt;
- reversal-preflight og append-only resultat;
- re-run efter kontrolleret reversal;
- en særskilt rerun-komparator, som kun accepterer eksakt reversal-lineage;
- afvisning ved beslutning, promotion, senere version og fremmed drift;
- commit-unknown-resultatlæsning;
- recoveryforbindelsens egen mål- og aktørvalidering samt secret-redaction;
- prod-wrapperens forbud mod selvautorisation og manglende produktionsflag.

### 7.2 Syntetiske og databasebaserede beviser

1. Python-tests muterer target, manifest, interpretation, link, run,
   disposition, event og alle neutralitetshashes enkeltvis.
2. SQL-kontrakttests beviser DDL, ACL, receipt, reversal, idempotens og races.
3. R-tests beviser wrapper- og gatewaykontrakten uden produktionsforbindelse.
4. `schema.sql`, `db-migrations.sql`, `db-rls.sql` og `db-verify.sql` skal give
   samme endelige katalog og privilegier.
5. Relevante fulde suiter skal være grønne.

### 7.3 Definition of done

En frisk, disponibel restore af produktionstilstanden efter 4.1c skal gennemføre:

```text
før-projektion
  → dry-run uden durable rows
  → apply
  → apply-projektion = match
  → proposal-reversal
  → recovery-projektion = match
  → korrigeret genkørsel, som genbruger uændrede deterministiske nøgler
    og kun danner nye nøgler for ændrede claims
  → rerun-projektion = match
```

Rapporten fastholder databaseidentitet, dump-/fil-/manifest-/previewhashes,
batch- og autorisations-id'er, counts, testkommandoer og resultater. Den må ikke
indeholde kildetekst eller claimværdier.

## 8. Afgrænsning

Følgende er udtrykkeligt uden for scope:

- reversal af 4.5's menneskelige afgørelser;
- reversal af promotion eller kanoniske mål;
- selve 4.4-produktionskørslen og ethvert prod-GO;
- 1939-klausulprofil, 1939-`persona_role_map` eller nye 1939-specialfaser;
- #189's segmenteringsfejl;
- generalisering eller omskrivning af 4.1c-projektionen;
- oprydning i profilens ubrugte konfigurationsnøgler, medmindre de konkret
  forhindrer den hashbundne gate;
- 4.5-planen.

## 9. Leverancegrænser

Arbejdet opdeles i tre sekventielle leverancer:

1. **#196-projektion:** read-only SQL, databasefri komparator, syntetiske tests
   og restore-bevis.
2. **Proposal-reversal:** receipts, RPC'er, writerens kontrollerede re-run,
   SQL/R-tests og recovery-bevis.
3. **Prod-wrapper og runbook:** operatørgrænse, commit-unknown-procedure og fuld
   rehearsalrapport.

Hver leverance skal kunne reviewes isoleret. Ingen leverance må kaldes færdig på
grundlag af grønne helpertests alene; det konkrete restore-bevis er den samlede
stopport.
