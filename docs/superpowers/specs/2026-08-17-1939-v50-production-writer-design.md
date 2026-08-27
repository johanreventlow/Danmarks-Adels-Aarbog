# DAA 1939 v50 Production Writer Design

**Dato:** 2026-08-17

**Status:** Godkendt design. Implementering følger en separat plan.

## Formål

Den afsluttede v50-reconciliation og de efterfølgende identitetsreviews har
ført 1939-materialet frem til en skrivebeskyttet database-preview. Næste fase
skal gøre hele v50-reimporten skrivbar uden at genindføre den gamle loaders
destruktive eller implicitte antagelser.

Designet omfatter:

- oprettelse af præcis otte nye kanoniske personer;
- komplet og positiv provenance for fakta, ægteskabsoplysninger og relationer;
- en særskilt production writer for hele v50-reimporten;
- en atomisk staged indlæsning med ægte rollback-dry-run;
- en separat, eksplicit autoriseret offentlig cutover.

Den eksisterende `.claude/skills/daa-extract/scripts/load_daa.R` ændres eller
kaldes ikke. Preview-artefakter er evidensinput og kontrolgrundlag, men er ikke
i sig selv skriveordrer.

## Godkendte hovedbeslutninger

Designet bygger på følgende eksplicit godkendte valg:

1. Produktionskørslen er alt-eller-intet. Ingen af de otte personer må
   committes, før hele den krævede provenance og alle writer-invariants er
   opfyldt.
2. De otte personer oprettes som `staged`. Offentlig aktivering er en separat
   cutover med egen autorisation.
3. Den endelige writer omfatter hele v50-reimporten: både de 543 eksisterende
   personankre og de otte nye personer.
4. Arkitekturen er en hybrid: et deterministisk manifest kompileres lokalt, en
   R-orchestrator styrer transaktionen, og smalle databasefunktioner håndhæver
   writes og invariants.
5. `retain_source_only` er et gyldigt slutresultat for kildeindhold, som ikke
   kan promoveres sikkert. Enhver resterende `unresolved` blokerer produktion.

## Udgangspunkt og låste mængder

Det nuværende read-only arbejde har verificeret:

- 543 eksisterende 1939-personankre;
- 32 source-persona-targets til eksisterende personer;
- 8 `new_person_candidate`;
- 1 `structural_or_summary` blandt de sidste 17 identitetsbeslutninger;
- 0 resterende identitetsmæssigt uafklarede poster i den gruppe;
- provenance-gab på 130 fakta, 94 ægteskabsoplysninger og 81 relationer;
- manglende production writer og manglende produktionsautorisation.

Tallene bliver assertions i manifestkontrakten. De må kun ændres gennem en ny,
versioneret design- og artefaktgeneration; writerens CLI må ikke kunne
tilsidesætte dem.

De otte nye personers låste source-record-keys er:

1. `record-3766faae-ae21-412a-8cfb-745a19ac77f0` — Ditlev, side 503;
2. `record-43d4974a-0532-421d-a3fb-8e7c575a67e7` — Gerhard/Gherardus, side 506;
3. `record-8f346104-cf3c-465f-bfa3-efb78be436b2` — Iven/Ywanus, side 506;
4. `record-b626f5ff-f2fb-4061-bfce-988dbddec846` — Henrik, side 506;
5. `record-80180a6e-2cc6-4968-81ca-004b6662d8ce` — Henning, side 506;
6. `record-a1f4547d-16cc-4110-ad1b-fa3ff1c59a58` — Henning, side 508;
7. `record-89a932c8-7b52-4f5c-9e00-0f2b62ee4422` — Henning Reventlow, side 508;
8. `record-c731fc5a-7e4c-45b8-9bfc-d6eba9f62e5d` — Margrethe, side 517.

## Arkitektur

Løsningen består af fem adskilte lag:

1. **Provenanceafgørelser** klassificerer hvert parkeret fakta-, ægteskabs- og
   relationsobjekt.
2. **Manifestcompiler** samler de godkendte v50-artefakter til et lukket,
   deterministisk write-manifest.
3. **Authorization-artefakt** binder en konkret manifestversion til én database
   og én forventet ændringsmængde.
4. **R-orchestrator** validerer input, åbner transaktionen og kalder kun
   navngivne databaseoperationer.
5. **Databasefunktioner** udfører de tilladte writes, journalfører dem og
   kontrollerer den faktiske før-/eftertilstand før commit.

Dry-run og production apply bruger samme manifestfortolkning og samme
databasefunktioner. Forskellen er alene den terminale handling: dry-run
rollbacker altid, mens en autoriseret apply kan committe efter alle kontroller.

## Production write-manifest

Manifestets schema hedder `1939-v50-production-write-manifest-v1`. Det skal
være lukket: ukendte felter, manglende felter, ukendte enum-værdier og ændret
sortering afvises.

Topniveauet indeholder mindst:

- schema- og generatorversion;
- SHA-256 for samtlige autoritative inputartefakter;
- edition/source-identitet;
- forventet databaseschema- og migrationsversion;
- den eksakte liste over 543 eksisterende personankre;
- præcis otte person-create-elementer;
- alle provenance-dispositioner;
- det komplette forventede kanoniske delta;
- forventede før- og eftertællinger;
- stabile element-ID'er og deterministisk rækkefølge;
- `production_authorized: false`.

Manifestet autoriserer aldrig sig selv. Et separat authorization-artefakt skal
referere manifestets bytehash.

### Person-create-element

Hvert af de otte elementer indeholder:

- stabil `source_record_key`;
- source-id og edition;
- eksakt source-span, ordret tekst og tekstens SHA-256;
- deterministisk `source_persona_id` og persona-key;
- identitetsbeslutning, reviewhash og beslutningsgrundlag;
- kildeunderbygget navn og eventuelt positivt underbygget køn;
- narrativ og dets source-record-ejerskab;
- kildebundne fakta, relationer og familieplaceringer;
- eksplicitte usikkerheder og `source_only`-dispositioner;
- forventede databaseoperationer og invariants.

Manifestet indeholder ikke et forudvalgt numerisk `person.id`. PostgreSQL
tildeler ID'et under transaktionen. Writeren bruger det returnerede ID i alle
afhængige rækker. Den stabile 1939-identitet er `record_key`, ikke et bestemt
sekvensnummer.

### Ingen fabrikerede oplysninger

Kun positiv kildeevidens må udfylde person- og slægtskabsfelter. Usikker tekst
bevarer sin usikkerhed. Eksempelvis må `Sønnesøn (?)` ikke blive en sikker
relation, og den korte Margrethe-post må ikke få opfundne datoer, køn eller
andre attributter. Det er legitimt at oprette en staged person med navn,
kildekontekst og sikker hierarkisk placering, selv om øvrige felter er tomme.

## Provenancekontrakt

Enhver kanonisk oplysning fra 1939 skal kunne spores gennem:

```text
source_record
  -> observation
  -> interpretation
  -> source_persona og canonical person
  -> promotion decision
  -> assertion og citation
  -> conclusion
```

De 130 fakta, 94 ægteskabsoplysninger og 81 relationer klassificeres hver
præcis én gang som:

- `promote_canonical`: identitet og positiv evidens bærer en kanonisk værdi;
- `retain_source_only`: evidensen bevares uden kanonisk projektion;
- `retire_1939_projection`: en tidligere projektion kan pensioneres påvist som
  eksklusivt 1939-ejet;
- `unresolved`: beslutningsgrundlaget er utilstrækkeligt.

Produktion kræver fuld dækning, globale entydighedskontroller og
`unresolved = 0`. `retain_source_only` tæller som en afsluttet, konservativ
disposition og må ikke omklassificeres af writeren.

### Eksisterende og redaktionelle data

En eksisterende kanonisk række må kun ændres eller pensioneres, når positiv
provenance viser, at den er ejet eksklusivt af DAA 1939 og er omfattet af et
manifestelement. Fravær fra det nye artefakt er aldrig slettebevis.

Følgende bevares altid, medmindre en senere særskilt beslutning udtrykkeligt
autoriserer andet:

- redaktionelle data;
- evidens fra andre udgaver eller kilder;
- rækker med blandet ejerskab;
- kanoniske rækker, der ikke er i manifestets forventede delta.

Ægteskabsfakta kræver selvstændig evidens. Eksisterende family-membership er
ikke bevis for vielsesdato, skilsmisse eller anden familiefakta. Relationer
kræver positivt kildebevis og entydig identitet i begge ender.

## Databaseændringer

En migration etablerer kun de nye objekter, som production workflowet kræver.
Den endelige plan skal udlede de præcise navne fra live schema og undgå
parallelle dubletter til allerede eksisterende private evidenstabeller.

Der kræves konceptuelt:

- et append-only write-batch-/eventspor;
- kobling fra hvert databasewrite til manifest-element, source record,
  source persona, promotion og authorization;
- smalle funktioner til private evidensrækker, person-create, kanonisk delta,
  verifikation, reversal og cutover;
- en dedikeret writerrolle uden generelle tabelrettigheder;
- eksplicit revoke fra `PUBLIC` og ikke-redaktionelle roller;
- databasehåndhævede uniqueness-, ownership- og state-transition-regler.

Databasefunktionerne modtager strukturerede, validerede elementer eller
stabile element-ID'er. De må ikke acceptere caller-styrede forventede counts,
fri SQL, ukendte operationstyper eller overskrivning af låste inputhashes.

## Apply-protokol

### Preflight

Før en skrivetransaktion validerer orchestratoren:

- manifest- og authorization-schema samt bytehashes;
- eksakte inputartefakter og provenance-dækning;
- databaseidentitet, source-id og migrationsniveau;
- den aktuelle read-only previews semantiske hash;
- forventede ankre, ejerskab, counts og nul kolliderende targets;
- at authorization gælder det konkrete miljø og ikke er udløbet eller brugt.

### Transaktion

Apply åbner en streng PostgreSQL-transaktion og tager en edition-specifik
advisory lock. De konkrete eksisterende targetrækker låses før mutation.
Writeren bruger database-default/identity til nye numeriske ID'er og må ikke
allokere fra `MAX(id)`.

Skriverækkefølgen er:

1. opret et entydigt write-batch-event;
2. materialisér source records, observations, interpretations og personaer;
3. materialisér accepterede identitets- og promotion-links;
4. opret de otte staged personer og deres unikke 1939-external IDs;
5. skriv narrativer, fakta, assertions, citations og conclusions;
6. skriv relationer, familier, memberships og familiefakta;
7. pensionér kun positivt 1939-ejede projektioner fra manifestet;
8. regenerér afledte caches gennem den autoritative databasevej;
9. kør alle før-/efter- og provenance-invariants;
10. commit eller rollback hele transaktionen.

Ingen delvis succes må være synlig efter en fejl.

### Post-write invariants

Før commit skal databasen mindst bevise:

- præcis 8 nye personer og 8 nye unikke 1939-external IDs;
- alle otte personer er `staged`;
- ingen uventede personoprettelser, -sletninger eller targetændringer;
- alle manifestelementer er anvendt præcis én gang;
- ingen databaseændring findes uden manifest- og provenance-link;
- ingen redaktionel eller fremmed kildeejet række er ændret;
- record-, persona-, person- og relationstargets er globalt entydige;
- alle referencer og promotion-kæder er komplette;
- det faktiske delta matcher manifestets forventede nøgler og row-hashes;
- `unresolved = 0` og alle forventede tællinger matcher.

## Authorization

Authorization er et separat, lille, lukket artefakt, som mindst binder:

- manifestets bytehash;
- database-/projektidentitet og edition;
- forventet preview- og schemahash;
- det eksakte ændringssæt og de otte person-create-keys;
- operationen (`apply`, `reverse` eller `activate`);
- autoriserende principal, tidspunkt og udløb;
- en unik nonce/batch-identitet.

CLI-flags må ikke kunne erstatte eller løsne disse værdier. En authorization
kan bruges én gang. Samme batch-ID med andre bytes afvises.

## Dry-run, idempotens og reversal

`apply --dry-run` gennemfører den samme skrivevej i en rigtig transaktion,
kører alle post-write-kontroller og rollbacker altid. Rapporten viser både det
forventede og det observerede delta. En succesfuld dry-run giver ikke
produktionsautorisation.

En genkørsel med samme allerede committede manifest- og batchhash må ikke
duplikere data. Den verificerer den registrerede sluttilstand og rapporterer
`already_applied`. Samme batch-ID med andet indhold fejler lukket.

Før aktivering kan et committet staged batch tilbageføres med en separat,
hashbundet reversal-authorization. Reversal er en ny journalført transaktion,
som genskaber den verificerede førtilstand; historikken slettes ikke. Efter
offentlig cutover gælder samme append-only kompensationsprincip, men reversal
kræver en særskilt højrisikogodkendelse.

## Cutover

Apply og offentlig aktivering er to operationer. Apply efterlader alle otte
personer staged og producerer en read-only efterrapport.

Cutover kræver:

- en ny `activate`-authorization;
- genvalidering af manifest, batch og database-sluttilstand;
- manuel gennemgang af de otte staged personer;
- nul drift siden apply;
- kontrol af visibility/RLS og afledte caches;
- aktivering af præcis de otte personer i én journalført transaktion.

Cutover må ikke samtidig ændre fakta, relationer eller identiteter. Hvis disse
har driftet, skal der laves et nyt manifest eller en særskilt korrektion før
aktivering.

## Sikkerhed og driftsgrænser

Writeren bruger en dedikeret rolle, som kun kan kalde de navngivne funktioner.
Den har ikke generel `INSERT`, `UPDATE`, `DELETE`, DDL eller vilkårlig
funktionsadgang. Funktionerne har fast `search_path`, kontrolleret owner og
eksplicitte grants/revokes.

Secrets, forbindelsesstrenge og tokens må aldrig serialiseres i manifest,
rapport, journal eller testoutput. Før production apply oprettes og verificeres
et gendannelsespunkt. Tidsgrænser, databaseidentitet og serverversion logges
uden credentials.

## Implementeringsfaser

1. **Manifestkontrakt:** schema, compiler, authorization-format og mutationstest.
2. **Provenanceafklaring:** eksplicit disposition for 130/94/81 og nul
   unresolved.
3. **Databasefundament:** migration, batchjournal, funktioner, rolle og RLS.
4. **Writer:** orchestrator, ægte rollback-dry-run, apply og maskinel rapport.
5. **Generalprøve:** to uafhængige kørsler mod frisk PostgreSQL 17 eller en
   kontrolleret databasekopi, inklusive fejlindsprøjtning.
6. **Staged produktion:** gendannelsespunkt, autoriseret apply og read-only
   efterkontrol.
7. **Cutover:** manuel kontrol, separat authorization og aktivering.

Hver fase har egen implementerings- og reviewport. En grøn tidligere fase
autoriserer ikke automatisk den næste.

## Teststrategi

Implementeringen udvikles test-first og skal mindst dække:

- deterministisk, byteidentisk manifestbygning;
- afvisning af ændrede hashes, spans, counts, keys, schemaer og sortering;
- afvisning af ukendt eller genbrugt authorization;
- afvisning af delvist eksisterende person/external-ID-state;
- konkurrerende writer og preview-to-apply drift;
- forkert source-persona, promotion eller relationstarget;
- manglende citation, observation eller ownership;
- forsøg på at ændre redaktionel eller fremmed evidens;
- fejl efter hvert skrivetrin med bevist fuld rollback;
- idempotent genkørsel og afvisning af samme ID med nye bytes;
- dry-run uden persistent databaseændring;
- staged usynlighed og eksakt otte-personers cutover;
- real PostgreSQL-17 migrations-, privilege-, RLS- og race-tests;
- to semantisk identiske generalprøver med credential-audit.

Fokuserede suites og fulde Python-/R-suites rapporteres separat. En DB-fri
grøn suite kan ikke stå som bevis for production writerens databaseadfærd.

## GO/NO-GO

Production apply er kun `GO`, når:

- manifestet er reproducerbart og hashbundet;
- alle provenanceobjekter er klassificeret, og `unresolved = 0`;
- private evidenstabeller og writerfunktioner findes i korrekt version;
- dry-run og generalprøve matcher det forventede delta;
- alle privilege-, rollback-, idempotens- og race-tests er grønne;
- gendannelsespunktet er verificeret;
- en gyldig, miljøbundet apply-authorization foreligger.

Cutover er kun `GO`, når staged apply er efterkontrolleret uden drift, de otte
personer er manuelt gennemgået, og en særskilt activate-authorization
foreligger.

## Færdigkriterium

Fasen er først færdig, når hele v50-manifestet er reproducerbart, staged
production apply er gennemført med det eksakte forventede delta, alle otte
personer og enhver kanonisk ændring kan spores til originaltekst og beslutning,
beskyttede eksisterende data er bevaret, og cutover er særskilt godkendt og
auditeret.

## Afgrænsning

Designet omfatter ikke:

- ændring eller genbrug af den gamle `load_daa.R`;
- import af andre DAA-årgange;
- generel ombygning eller oprydning af datamodellen;
- identitetsgæt baseret alene på navn eller OCR-lighed;
- automatisk offentliggørelse som del af apply;
- produktionskørsel uden ny, eksplicit authorization.
