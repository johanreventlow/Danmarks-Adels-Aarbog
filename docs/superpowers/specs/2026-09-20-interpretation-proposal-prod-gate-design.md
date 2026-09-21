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
- berørte klausuldispositioners observation-id, version, disposition og
  helrækkehash.

`after_sha256` er hash af det lukkede resultat-receipt, ikke en løs optælling.
Receiptet er den eksakte write-set-binding for projektion, commit-unknown og
reversal. Der oprettes ikke en parallel editionsspecifik receipt-tabel.

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

Under den generelle writerlås og `FOR UPDATE` skal reversal afvise, hvis:

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
2. For hver berørt klausul kopieres dispositionen umiddelbart før 4.4 som en ny
   maskinel version. Evidensen binder både original batch og reversal.
3. Der indsættes ét reversal-event med før-/efter-state-hash og eksakte counts.
4. Autorisationen konsumeres, og originalbatchen markeres `reversed`.

Ingen fortolkning, link, disposition, extraction-run, event, autorisation eller
batch slettes.

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

En læsefunktion returnerer kun metadata og én af følgende tilstande:

- `not_started` — ingen gyldig reversal-event;
- `reversed` — event, batchstatus, autorisation og aktuelle superseded-versioner
  matcher receiptet;
- `drift` — noget findes, men den samlede kontrakt stemmer ikke.

Et gentaget reversal-kald efter en verificeret reversal udfører ingen nye writes
og returnerer det eksisterende resultat. Ved `drift` stoppes der.
Resultatlæsningen er den eneste recoveryvej efter forbindelsestab; operatøren må
ikke gætte ud fra en klientfejl.

### 4.6 Produktionswrapper

En lille editionsneutral wrapper er den eneste dokumenterede 4.4-prod-indgang.
Den:

- accepterer kun et manifest, hvis alle operationer er
  `interpretation_proposal`;
- verificerer manifestbytes, manifesthash, preview-hash, source, profil og
  forventet databaseidentitet;
- kræver en allerede udstedt autorisation og må aldrig kalde
  autorisations-RPC'en;
- kræver et ordret, eksplicit produktionsflag;
- afviser dry-run mod en base, hvor manifestets forslag allerede findes;
- udskriver kun ids, hashes, counts og status;
- håndterer forbindelsestab med resultat-RPC'en, ikke med automatisk genapply.

Den generelle `apply_reimport.R` og dens gateway genbruges som intern motor.
Andre reimportoperationers CLI-kontrakt ændres ikke.

## 5. Dataflow

### 5.1 Normal apply

1. Luk eller disponér 4.1c's åbne restore-vindue.
2. Etabler redaktionel skrivepause.
3. Tag læse-kun preflight og før-projektion.
4. Tag backup og restore netop den backup.
5. Gennemfør fuld rehearsal, inklusive proposal-reversal og korrigeret genkørsel.
6. Lås GO-pakken til commit, databaseidentitet, filer, hashes, manifest,
   preview og forventede counts.
7. Udsted én autorisation.
8. Kør prod-wrapperen én gang.
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

Alle fejl er stabile, maskinlæsbare koder og må kun ledsages af ids, feltnavne og
counts. Ingen fejl må indeholde kildetekst eller claimværdier.

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
afgørelse, promotion og dispositionsskrivning. Præcis én side må vinde; den anden
skal stoppe uden partiel effekt.

## 7. Verifikation

### 7.1 Test-first

Implementeringen følger TDD. Før produktionskode ændres, skal røde tests findes
for mindst:

- projektionens lukkede skema og manifestvalidering;
- hver enkelt driftklasse;
- eksakt event-receipt;
- reversal-preflight og append-only resultat;
- re-run efter kontrolleret reversal;
- afvisning ved beslutning, promotion, senere version og fremmed drift;
- commit-unknown-resultatlæsning;
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
  → apply-projektion = match
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
