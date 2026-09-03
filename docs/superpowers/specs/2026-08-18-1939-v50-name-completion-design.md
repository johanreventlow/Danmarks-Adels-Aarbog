# DAA 1939 v50 Name Completion Design

**Dato:** 2026-08-18

**Status:** Godkendt design. Implementering følger en separat plan.

## Formål

Den autoriserede DAA 1939 v50-production-batch
`560c39f8-5c87-4c0d-a768-025d97fa2974` oprettede otte personer som
`staged` med komplette private source-persona- og narrativspor. Det anvendte
manifest autoriserede præcis nul kanoniske ændringer. Da
`person_external_id`-triggeren efter oprettelsen kaldte
`regen_person_visning()`, blev writerens midlertidige `visning_navn` derfor
korrekt regenereret fra det tomme kanoniske faktagrundlag til `NULL`.

Denne fase skal fuldføre navnene uden at omskrive den oprindelige batch eller
omgå den evidensbaserede model. Den skal:

- oprette præcis ét kildebundet, valgt `navn`-faktum for hver af de otte
  staged personer;
- lade den eksisterende cachefunktion aflede visningsnavnene;
- bevare de otte personer som `staged`;
- gøre navnefuldførelsen append-only, separat autoriseret og reversibel;
- forhindre cutover, hvis en af de otte ikke har den eksakte, godkendte
  navneprovenance.

Fasen omfatter ikke cutover, relationer, familier, køn, datoer eller andre
kanoniske fakta.

## Låste forudsætninger

Følgende produktionsstate er udgangspunktet og må kun læses under lokal
udvikling og rehearsal:

- database `postgres`, cluster system identifier `7642734024280108049`;
- oprindelig batch `560c39f8-5c87-4c0d-a768-025d97fa2974`, status
  `finalized`;
- oprindelig authorization
  `1086cce9-f713-4bf3-9d8f-41ab19094bf0`, status `consumed`;
- oprindelig manifest-bytehash
  `8417b6deeaf32b3cf39a4f2995a06211f8368172dfa97a188e03c6f7ef379a1f`;
- oprindelig manifest-content-hash
  `8c6a9f56af7f1e75e1b961f561cc2118478ac4d9e08f838c9e5279938c545f03`;
- præcis otte `person_create`-events med person-ID 1846-1853;
- alle otte personer er `staged=true`, har ét entydigt DAA 1939-record key
  og har intet eksisterende `navn`-fact;
- nul cutover-authorizations og nul aktiverede personer.

Drift i en af disse forudsætninger giver `NO-GO`. Numeriske person-ID'er er
låst for denne korrektionsbatch, fordi de allerede er database-returnerede
resultater fra den committede batch; fremtidige importer må fortsat ikke
forudsige ID'er.

## Arkitektonisk beslutning

Den oprindelige production-batch og dens 313 events er immutable. Dens
manifest må ikke regenereres med et nyt delta, og dens `expected_counts` eller
`observed_counts` må ikke ændres.

Navnene fuldføres i en ny, underordnet writer-batch med en særskilt
authorization-operation `name_completion`. Den genbruger det eksisterende
authorization-, batch- og eventspor, men har sit eget lukkede manifest og
smalle databasefunktioner. Hver operation bindes eksplicit til den
oprindelige batch og det oprindelige `person_create`-payload.

Dette vælges frem for:

- direkte kald til `red_upsert_fakta`, som ikke binder hele sættet til én
  manifest-/databaseauthorization og ikke giver det nødvendige source-record-
  resultatlink;
- direkte opdatering af `person.visning_*`, som ville gøre afledte caches til
  autoritativ data;
- reversal og genimport, som er unødvendigt destruktivt og ville omskrive
  allerede verificeret provenance.

## Name-completion-manifest

Det nye lukkede schema hedder
`1939-v50-name-completion-manifest-v1`. Det kompileres deterministisk fra:

1. den byteeksakte oprindelige production-manifest;
2. det byteeksakte production-apply-resultat;
3. den read-only post-apply-audit;
4. den godkendte liste over otte navne.

Topniveauet indeholder kun:

- schema- og generatorversion;
- SHA-256 for alle inputartefakter;
- database- og source-identitet;
- oprindeligt batch-ID og oprindelige manifesthashes;
- præcis otte operationer i stabil record-key-rækkefølge;
- `counts: {name_completions: 8, operations: 8}`;
- forventet databaseændring: otte facts, assertions, citations og conclusions,
  nul person-, external-ID-, relation-, family- eller activation-ændringer;
- content-hash;
- `production_authorized: false` og `cutover_authorized: false`.

Ukendte felter, ændret sortering, dubletter, manglende rækker eller
caller-styrede count-overrides afvises.

### Operation

Hver operation har et stabilt element-ID
`name-completion:<source_record_key>` og indeholder:

- oprindeligt batch-ID og `person_create`-element-ID;
- database-returneret `person_id`;
- `source_id=3`, edition og `source_record_key`;
- den oprindelige source-persona-id;
- eksakt navn fra det autoriserede `person_create`-payload;
- source-span, page-evidence, ordret tekst og teksthash;
- hash af det oprindelige writer-event-payload;
- forventet førstate: `staged=true`, tom navnecache og nul `navn`-facts;
- forventet efterstate: ét afklaret `navn`-fact med én valgt assertion og én
  DAA 1939-citation.

De otte navne er Ditlev; Gerhard (Gherardus de Reventlow); Henning; Henning
Reventlow; Iven (Ywanus de Reuentlo); Henning; Henrik; og Margrethe, bundet
til deres eksisterende record keys og person-ID'er. Navn alene bruges aldrig
som identitetsnøgle.

## Databasekontrakt

### Schema

`private.reimport_1939_authorization.operation` udvides med
`name_completion`. En ny privat append-only resultattabel binder:

- completion-batch og element-ID;
- oprindelig batch;
- person, source record og source persona;
- oprettet fact, assertion, citation og conclusion;
- autoriseret payloadhash og resultathash.

Tabellen har uniqueness på både `(batch_id, element_id)` og på den
oprindelige `(source_batch_id, person_id, source_record_id)`. Den er RLS-
beskyttet, uden policies, og alle rettigheder samt hjælpefunktioners EXECUTE
revokes fra `PUBLIC`, `anon` og `authenticated`, bortset fra de eksplicit
godkendte redaktionelle RPC'er.

Resultatlinket er auditspor og slettes ikke ved reversal. Genererede numeriske
row-ID'er gemmes derfor som auditerede værdier uden delete-blokerende FK'er til
de kanoniske rækker; integriteten valideres før insert, finalize, cutover og
reversal.

### Smalle RPC'er

Der tilføjes særskilte funktioner til:

1. authorization af ét eksakt name-completion-manifest;
2. åbning af én completion-batch;
3. anvendelse af ét autoriseret navneelement;
4. finalize med eksakt otte-elementers audit.

Authorization bindes til database, cluster system identifier, principal,
source, oprindelig batch, begge manifesthashes, eksakt payload-map, nonce og
udløbstid. Den kan kun bruges én gang.

Writerfunktionen accepterer ikke fri faktatype, fri target-type eller andre
felter. Den kan kun oprette `fact(subjekt_type='person', faktatype='navn')`
med assertionens `vaerdi_tekst` lig operationens låste navn. Citationen har
`source_id=3`, eksakt kildeside og ordret tekst. Conclusion er `afklaret`,
vælger netop assertionen og mærkes med den versionslåste
name-completion-beslutning.

### ID-allokering og samtidighed

De eksisterende fact/assertion/citation/conclusion-tabeller har legacy
BIGINT-primary keys uden identity-default, og eksisterende redaktionelle
writers bruger fortsat `max(id)+1`. Denne fase må ikke foretage en skjult,
global sekvensmigration.

Completion-writeren tager derfor den editionsspecifikke advisory lock og
låser de fire kanoniske tabeller i en mode, der konflikter med samtidige
inserts, før den allokerer den lille, lukkede otte-rækkers mængde. Alle IDs
allokeres og bruges i samme transaktion. Rehearsal skal bevise, at en
konkurrerende redaktionel insert enten venter eller afvises, aldrig kolliderer.

## Validering og writes

For hvert element låses og kontrolleres:

1. den oprindelige batch er stadig `finalized`;
2. det oprindelige `person_create`-event findes præcis én gang og matcher
   person-ID, record key, source persona, navn og payloadhash;
3. private source record/persona/identity/narrative-publication-kæder findes
   og peger på samme source og person;
4. personen er stadig staged og har ingen valgt eller uvalgt navnefact;
5. external ID er stadig entydigt for `source_id=3` og record key;
6. payloadet er byte-semantisk lig authorizationens element.

Derefter oprettes i samme transaktion:

1. `fact` for personens navn;
2. immutable assertion med kildenavnet;
3. citation med DAA 1939, side og fuld ordret tekst;
4. afklaret conclusion, som vælger assertionen;
5. privat result-link og append-only `canonical_delta`-writer-event.

Conclusion-triggeren kalder den eksisterende `regen_person_visning()`. Efter
hvert element skal `visning_navn` være eksakt kildenavnet. Hvor lineage giver
ét entydigt slægtsnavn, kontrolleres `visning_fuldt_navn` efter den eksisterende
afledningsregel; designet ændrer ikke denne regel.

Finalize kræver præcis otte distinct, hashgyldige events, otte result-links,
otte staged personer og otte komplette fact/assertion/citation/conclusion-
kæder. Enhver forskel rollbacker hele completion-batchen.

## Reversal

Den eksisterende reversal af den oprindelige production-batch udvides, så en
finalized name-completion-child håndteres atomisk. Reversal sletter i
afhængighedsrækkefølge de otte completion-conclusions, citations, assertions
og facts, markerer completion-batchen `reversed` og fortsætter derefter den
eksisterende person/provenance-reversal.

Result-links og writer-events forbliver som append-only audit og peger på de
historiske row-ID'er. En delvis eller konkurrerende ændring af en af de
kanoniske rækker gør reversal `NO-GO`; writeren må ikke slette data, den ikke
længere entydigt ejer.

En completion-batch kan ikke reverseres eller genanvendes uafhængigt gennem en
uautoriseret generisk funktion.

## Cutover-port

`red_activate_1939_v50_batch` må fortsat kun kaldes med en særskilt cutover-
authorization. Før aktivering kontrollerer funktionen nu også, at hver af den
oprindelige batchs otte person-create-events har præcis ét result-link fra en
finalized completion-batch, og at alle bundne kanoniske rækker stadig:

- eksisterer med eksakte IDs og værdier;
- peger på den korrekte person;
- har citation til source 3 og den autoriserede side/tekst;
- har en afklaret conclusion, som vælger den autoriserede assertion;
- giver det forventede `visning_navn`;
- tilhører en person, der stadig er staged.

Manglende completion, ekstra navnefact, payloaddrift, cachemismatch eller
ændret provenance giver `REIMPORT_1939_NAME_COMPLETION_INVALID` og fuld
rollback. Denne designgodkendelse autoriserer ikke cutover.

## Lokal orchestration

En separat builder og R-orchestrator håndterer kun name completion. De gamle
v1-production-artefakter og deres builder ændres ikke semantisk.

Orchestratoren understøtter:

- `dry-run`, som bruger de ægte databasefunktioner og altid rollbacker;
- `apply`, som kræver en reloadet, uudløbet one-use-authorization;
- ingen retry efter en uklar writer-respons;
- eksklusiv outputfil og credential-audit;
- database-returneret batch- og row-ID-map i resultatet.

Et production-apply kræver en ny lokal backup og en ny eksplicit godkendelse,
som navngiver databaseidentitet, migrations/RLS-hashes, completion-manifesthash
og one-use apply. Ingen tidligere godkendelse genbruges.

## Teststrategi

Implementeringen udvikles med observeret RED før produktionskode og skal mindst
dække:

- byteidentisk manifest og lukket schema;
- eksakt 8/8 coverage, stabile keys og ingen caller-count-overrides;
- drift i oprindelig batch, person-map, navn, side, tekst, source persona,
  payloadhash eller databaseidentitet;
- manglende, ekstra eller allerede eksisterende navnefacts;
- ikke-staged person og ukendt/konkurrerende external ID;
- authorization expiry, principal mismatch, reuse og element-tampering;
- atomisk rollback efter hvert write-trin;
- præcis citation/source-record/provenance-binding;
- korrekt `visning_navn` gennem den rigtige conclusion-trigger;
- nul ændring af facts, relationer, familier eller personer uden for de otte;
- idempotent read/replay-detektion uden dobbelt facts;
- sikker samtidighed med en konkurrerende redaktionel fact-writer;
- korrekt child-aware reversal uden sletning ved drift;
- cutover-afvisning før completion og ved enhver efterfølgende drift;
- RLS/ACL og SECURITY DEFINER-search-path;
- to semantisk identiske rehearsals på friske restores;
- fulde Python-, R- og fokuserede PostgreSQL-suites.

## Produktionsprocedure og stopporte

1. Implementér og review lokalt.
2. Byg manifest og kør rollback-dry-run på en frisk restore af den permanente
   pre-apply-backup, derefter på en frisk snapshotkopi af den aktuelle staged
   state.
3. Kør to uafhængige completion/reversal-rehearsals.
4. Udfør read-only production-preflight og generér en reviewpakke med alle
   hashes, otte navne, præcis delta og restore-reference.
5. **Stop og kræv en ny eksplicit production-authorization.**
6. Ved godkendelse: tag ny lokal backup, anvend migration/RLS, udsted one-use
   authorization og kør præcis én completion-apply uden retry.
7. Efterkontrollér read-only. Personerne forbliver staged.
8. **Stop igen.** Cutover kræver sin egen senere godkendelse.

## Færdigkriterium

Fasen er klar til production-review, når:

- det oprindelige batch- og manifestspor er byte- og databasemæssigt urørt;
- et lukket completion-manifest reproducerer præcis otte navneoperationer;
- dry-run, rollback, reversal, ACL og concurrency er bevist i PostgreSQL 17;
- alle otte navne har komplette kilde- og canonical-links;
- alle otte caches regenereres korrekt og personerne forbliver staged;
- cutover-porten afviser enhver ufuldstændig eller ændret completion;
- ingen production-write eller cutover er sket uden den nye særskilte port.
