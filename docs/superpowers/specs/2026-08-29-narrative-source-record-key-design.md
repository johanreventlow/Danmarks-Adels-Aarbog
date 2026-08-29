# Record-nøglede person-narrativer (#152) — design

**Dato:** 2026-08-29

**Status:** Revideret efter DAA-arkitektur- og eksternt driftsreview; afventer
projektejerens review af den skrevne revision

**Roadmapmål:** #152 — narrativer knyttes entydigt til en konkret source record

**Modenhed:** `specificeret`

**Grundlag:** Levende schema og klientkode på lokal `main` ved `7b5dc5a`

## 1. Beslutning

Person-narrativer fra DAA skal fremover læses og skrives med en konkret
source record som redaktionel nøgle. Den eksisterende private
`narrative_record_publication` forbliver den aktuelle binding mellem
`public.narrative` og `private.source_record`; en ny append-only
publication-eventlog bliver den autoritative historik for kladder,
publiceringer, revisioner, tilbagetrækninger og fortrydelser.

Der tilføjes **ikke** en `source_record_id`-kolonne til `public.narrative`.
Private source-record-UUID'er eksponeres ikke til web, mobil eller offentlige
læsere. Redaktionelle kald identificerer i stedet en record med dens stabile,
editionsneutrale locator `(source_id, record_key)`; databasen resolver og
låser den private UUID internt. `private.source_record` får en separat,
tilfældig og uforanderlig `public_ref`, som er recordens stabile offentlige
reference på tværs af publication-bindingers livscyklus.

Designet er valgt frem for:

- en minimal database-only writer, som ikke ville løse redaktørens eller
  læserens record-granularitet;
- en direkte privat UUID-kolonne på den offentligt læsbare narrative-tabel;
- en fuld selvstændig rå/normaliseret/redigeret tekstversionsmodel, som er
  større end #152. #152 bevarer dog hver konkret publiceret tekstversion og
  dens provenance i den append-only publication-eventlog; den må ikke nøjes
  med at overskrive en tidligere publiceret tekst uden versionsspor.

For person/DAA-sporet erstatter denne spec source-nøglingen i den historiske
2026-07-03-spec om flere narrativer pr. person. Den erstatter også issue #152's
og `docs/decisions.md`'s tidligere skitse med en direkte
`public.narrative.source_record_id`: skitsen dokumenterer, hvorfor C3 kunne
køre først, men er ikke længere implementeringskontrakten. `source.aar`, den
generiske ikke-personlige narrative-model og øvrige uafhængige beslutninger
fra den ældre spec berøres ikke.

## 2. Roadmapkobling og færdigdefinition

Dette design opfylder roadmapets seks adgangskrav således:

1. **Roadmapmål:** #152, før generalisering af writeren i #153.
2. **Værdikædeled:** publication gate og offentlig læseprojektion med
   kildehenvisning; writerens eligibility-kontrol berører desuden den allerede
   afgjorte identity gate uden at skabe en ny identitetsafgørelse.
3. **Leverancetype:** en permanent, editionsneutral fælles mekanisme samt en
   afgrænset legacy-afvikling. Ingen nye 1939-navngivne produktionsflader.
4. **Værdi:** redaktøren kan vedligeholde flere selvstændige kildeposter for
   samme person og samme DAA-udgave uden at overskrive den første narrativrække;
   læseren ser kildeteksterne som separate historiske optrædener.
5. **Færdigbevis:** disposable databaseintegration, konkurrencetest, schema- og
   RLS-verifikation, fokuserede og fulde web-/mobiltests samt reel røgtest af
   record-valg, uafhængig redigering, legacy-readonly og offentlig visning.
   Produktionsverificeret er en senere, separat modenhedstilstand og kræver
   et eksplicit produktions-GO.
6. **Erstattede workflows:** person/DAA-grenen af `red_upsert_narrativ`,
   kildebaserede narrativfaner i redaktionen og den offentlige fallback, der
   sammenkæder flere narrativer pr. source. Den generiske writer bevares for
   andre subjekttyper og ikke-DAA-kilder.

### 2.1 Operationel overgangsomkostning

En read-only produktionsmåling i det eksterne review 2026-08-29 rapporterede
563 eksisterende publication-bindinger, 591 ubundne person/DAA-narrativer fra
2018-20 og kun 8 accepterede `source_persona_identity`-rækker. Tallene er et
snapshot og skal genmåles ved production-gaten, men de gør en vigtig konsekvens
synlig:

- eksisterende eksakte bindinger kan fortsat redigeres, når deres øvrige
  preconditions består;
- en ny binding kan kun oprettes for en record, hvis den aktuelle accepterede
  principal/co-principal-identitetsmængde entydigt er den valgte person;
- hovedparten af nye person/DAA-bindinger vil derfor være blokeret, indtil de
  relevante senere roadmapmål (#153, #149 og til sidst #151) har leveret
  recordproveniens og den fælles accepterede identitetsvej;
- 2018-20-legacy forbliver tekstmæssigt read-only, men skal kunne tages ned
  narrativ-granulært gennem den særskilte legacy-withdrawal i dette design;
- den eksisterende DAA-loader må efter cutover ikke fortsætte en direkte
  narrativmutation uden event- og recordkontrakten. Den afviser derfor hele
  kørslen før første write, indtil #153 leverer den generaliserede writer;
- `red_slet_person` må ikke slette en mutable narrativprojektion og efterlade
  eller kaskadeslette publication-historikken. Indtil den åbne
  tombstone-/retentionsbeslutning er afgjort, afviser den derfor tidligt for en
  person med #152-publication-events; granulær legacy-/record-withdrawal er den
  tilgængelige offentlige nedtagningsvej.

Det er en bevidst fail-closed redaktions- og importfrysning, ikke en skjult
teknisk bivirkning. Production cutover kræver projektejerens særskilte,
udtrykkelige accept af denne omkostning; review af arkitekturretningen alene er
ikke den accept.

## 3. Nuværende problem

Schemaet tillader allerede flere narrative-rækker pr. person og source. Den
reelle kollapsning ligger i skrivere og læsere:

- `red_upsert_narrativ` finder første række på
  `(subjekt_type, subjekt_id, source_id)` med `ORDER BY id LIMIT 1`;
- web- og mobilredaktionen læser og skriver på source-niveau, ikke
  source-record-niveau;
- den record-bundne offentlige RPC bevarer rækkerne, men returnerer ikke den
  strukturerede udgavekronologi, og klienten sorterer derfor alfabetisk;
- den gamle offentlige fallback grupperer og sammenkæder tekst pr. source.

Patologien er ikke kun teoretisk: en person kan have flere source records i
samme udgave, og en historisk legacy-række kan indeholde tekst fra mere end
én fysisk post. Derfor må hverken source-id, narrativ-id-rækkefølge eller
"præcis én mulig kandidat" bruges som implicit record-afgørelse.

## 4. Autoritativ datamodel

### 4.1 Identiteter

- `private.source_record.id` er intern databaseidentitet.
- `(private.source_record.source_id, private.source_record.record_key)` er den
  stabile record-locator i den redaktionelle API-kontrakt.
- `private.source_record.public_ref` er en tilfældig, unik og uforanderlig UUID,
  som må eksponeres som source recordens stabile offentlige identitet.
- `record_key` er aldrig personidentitet.
- `private.narrative_record_publication` er den autoritative aktuelle
  projektion af relationen mellem et narrativ og en source record.
- `narrative_record_publication.record_ref` er en historisk publication-
  reference og bevares for v1-kompatibilitet. Den er ikke source recordens
  stabile identitet og må ikke bruges i nye eksterne links eller citationer.
- `private.narrative_publication_event` er den autoritative, append-only
  versions- og beslutningshistorik.
- `public.narrative.source_id` bevares som bibliografisk source-binding og må
  ikke bruges som erstatning for en source record.

Der oprettes ingen offentlig tabel eller klientgenereret UUID. `public_ref`
ligger på den private source record og forlader kun databasen gennem gatede
RPC'er. Kolonnen er `NOT NULL UNIQUE DEFAULT gen_random_uuid()` og beskyttes af
en trigger, som afviser senere ændring; migrationen beviser, at hver eksisterende
record fik præcis én unik reference.

### 4.2 Aktiv binding

Den eksisterende invariant bevares:

- et narrativ har højst én publication-binding;
- en source record har højst én aktiv binding med status `draft` eller
  `published`;
- `withdrawn` er historik og må ikke muteres tilbage til en aktiv binding;
- source på narrativ og source record skal være ens;
- recordbindingen er kun gyldig for `subjekt_type='person'`.

Den partielle unique-index på aktiv `source_record_id` er den deklarative
sidste barriere. Alle almindelige writere skal desuden følge samme låserække.

### 4.3 Append-only publication-eventlog

`private.narrative_publication_event` er editionsneutral og dækker både
record-bundne og grandfathered legacy-publiceringer. Tabellen har mindst:

- tilfældigt event-id, stream-id og monoton stream-version;
- eventtype:
  `baseline`, `draft_created`, `draft_updated`, `published`,
  `draft_discarded`, `published_revision`, `revalidated`, `withdrawn`,
  `reversal`, `legacy_migrated` eller `legacy_withdrawn`;
- binding-, narrative-, source- og source-record-identitet, når relevant;
- aktør-id, aktørnavn, tidspunkt, change-set-id og beslutningsgrundlag;
- event-id'et, der reverseres, når eventet er en fortrydelse;
- kanonisk før- og eftertilstand med SHA-256 for begge;
- den fulde private tekstversion, teksthash, privacy og side;
- det præcise provenance-snapshot: accepterede anchor-eventversioner,
  occurrence-id'er, rendition-id'er og rendition-content-hashes;
- source recordens aktuelle split/merge/replacement-revisionstilstand;
- den anvendte identity-authority og dens version eller den grandfathered
  eksisterende bindingsautoritet;
- publication-policy-input og policyhash.

Eventtabellen har en trigger, som afviser `UPDATE` og `DELETE`, og er uden
direkte grants til `anon` og `authenticated`. Aktuel binding og narrative-række
er projektioner, der kun må ændres atomisk sammen med næste event.

Den aktuelle streamtilstand reduceres deterministisk fra eventrækkefølgen. Hvert
event binder sin fulde semantiske før- og eftertilstand; også et reversal-event
har derfor en ny, selvstændig eftertilstand. Offentlige læsere må ikke udlede
tilstanden ved blot at finde "seneste event med typen published".

En publiceret version er gyldig, når eventstreamens reducerede eftertilstand
stadig matcher den levende record-, anchor-, rendition-, identity-, tekst- og
policytilstand. Drift gør publiceringen stale og fail-closed usynlig; den
slettes eller overskrives ikke. En redaktør kan efter review oprette et
`revalidated`-event, som binder en ny konkret provenance- og policytilstand.

### 4.4 Grandfathered legacy-publication

Et person/DAA-narrativ uden publication-binding er **legacy**. Det bliver ikke
automatisk betragtet som hverken publiceret eller record-bundet.

Før produktionsmigrationen bygges et hash-låst manifest med det eksakte ID-sæt
og tekst-/privacy-/person-/source-hashes for de ubundne narrativer, som allerede
er offentligt synlige og skal bevares midlertidigt. Efter særskilt menneskelig
godkendelse indlæses de i `private.narrative_legacy_publication` som
`grandfathered_publication`; hver ledger-række får en tilfældig, unik og
uforanderlig `legacy_publication_ref`, og et `baseline`-event registrerer
beslutningen.

Kun rækker i denne ledger kan vises som offentlig legacy. De:

- vises som `Overgangsdata — kildepost ikke fastlagt`;
- er read-only for tekst og recordbinding i den nye redaktionelle flade;
- bindes aldrig automatisk, heller ikke hvis databasen kun finder én mulig
  source record;
- skjules, hvis den levende tekst, privacy, person eller source ikke længere
  matcher baseline-hashen;
- får en append-only disposition som `migrated` eller `withdrawn`, når den
  midlertidige publicering ophører.

Read-only betyder ikke, at materialet ikke kan tages ned. En særskilt,
narrativ-granulær writer kan disponere én aktiv legacy-publication som
`withdrawn` uden at ændre teksten eller `narrative.privat`. Det skjuler kun den
valgte legacy-biografi og bevarer den private audit; en eventuel genetablering
går gennem den dedikerede, sikkerhedsgatede reversal.

Nye ubundne narrativer bliver aldrig optaget ved en dynamisk query eller
automatisk baseline. Exit-betingelsen er en eksplicit record-disposition; for
2018-20 leveres recordproveniensen af #149 efter writer-generaliseringen i
roadmapmål #153.

Roadmapmål #152 bygger ikke selve bindings-reviewfladen for legacy. Det bevarer
det godkendte historiske publiceringssæt synligt, mens alt andet ubundet
materiale forbliver fail-closed.

## 5. Redaktionel læsekontrakt

Der etableres den editionsneutrale `SECURITY DEFINER`-RPC
`public.red_person_narrative_records(p_person_id bigint)` for én person. Den
returnerer en tabelkontrakt; komplekse withdrawn-historikker bæres som valideret
JSONB i den enkelte record-entry.

RPC'en må kun kaldes af en autentificeret bruger med rollen `redaktion`. Den
returnerer ingen interne private UUID'er; de særskilt designede, uforanderlige
`source_record_ref` og `legacy_publication_ref` er sikre kontraktreferencer.
Hver record-række indeholder mindst:

- `person_id`, `source_id`, `source_year` og source-label;
- `record_key`, stabil `source_record_ref`, serverafledt record-label, citation
  og sideorden;
- `narrative_id`, tekst og privacy, når et aktivt narrativ findes;
- publication-status: `none`, `draft`, `published`, `stale_published` eller
  `withdrawn`;
- read-only `withdrawn_history`, ordnet deterministisk, fordi en record kan
  have mere end én tidligere withdrawn binding;
- seneste publication-eventversion og publiceret teksthash;
- eligibility-status og en maskinlæsbar blocking reason;
- en kanonisk `state_sha256` til optimistisk concurrency-kontrol.

Der returneres én overordnet editor-entry pr. source record. En aktiv binding
ligger i entryens aktive felter; withdrawn bindinger ligger i den ordnede
historik. Status er `withdrawn`, når der ikke findes en aktiv binding, men
historikken ikke er tom.

Legacy-rækker returneres i en separat union-gren uden `record_key`, med
`legacy_publication_ref`, `provenance_kind='grandfathered_legacy'` og
`text_editable=false`. Kun aktive, hash-matchende rækker fra legacy-ledgeren
returneres offentligt. Redaktørkontrakten viser også withdrawn legacy-historik
og angiver særskilt, om den aktive række kan tages ned.

### 5.1 Hvilke records tilhører personens redaktørvisning?

En source record medtages, når mindst én af disse er sand:

1. recorden har allerede en aktiv eller withdrawn narrativbinding, hvis
   narrative-række peger på personen; eller
2. recorden har et aktuelt accepteret record-anchor og mindst én aktuelt
   accepteret persona-placement med rollen `principal_member` eller
   `co_principal`, hvis aktuelle identity state er `accepted` til personen.

`primary persona` er ikke et selvstændigt skemabegreb og bruges ikke som
implementeringsregel. Writeren beregner i stedet mængden af aktuelle
`canonical_person_id` for alle accepterede `principal_member`- og
`co_principal`-placements på recorden. En ny binding er kun entydigt
autoriseret, når denne mængde er præcis `{p_person_id}`; en anden person eller
en uafklaret/tom mængde blokerer fail-closed.

En eksisterende eksakt binding med et importeret `baseline`-event er stående
autoritet til fortsat redigering af det samme narrativ for den samme person.
Det gælder også de publicerede C3-
bindinger, som er menneskegodkendt og batchauditeret, men ikke nødvendigvis
har en generel `source_persona_identity`-række. Bindingen autoriserer ikke en
ny person, record eller publication-binding.

Hvis den aktuelle accepterede principal/co-principal-identitetsmængde for
recorden indeholder en anden kanonisk person, bliver den eksisterende binding
synlig, men blokeret med `editable=false` og en konkret blocking reason. Fravær
af en generel identity-række blokerer derimod ikke fortsat redigering af en
allerede eksakt binding.

Oprettelse af en ny binding — herunder efter kun-withdrawn historik — kræver,
at det aktuelle identity-grundlag entydigt understøtter samme person. Ingen
RPC i #152 må oprette eller ændre en source-persona-identity-afgørelse, og
eksisterende C3-bindinger backfilles ikke til konstruerede identity-afgørelser.
Denne authority-kind er en kontrolleret legacy-bro, ikke en anden permanent
identity-vej: #151's konsolidering skal give den en eksplicit disposition og
fjerne behovet for den ved nye publiceringsbeslutninger.

Produktionssnapshottene betyder, at denne bro i overgangsperioden bærer næsten
hele den faktiske redigeringsautoritet for eksisterende 1939-bindinger. Ordet
`legacy-bro` beskriver dens planlagte livscyklus, ikke dens aktuelle volumen.

### 5.2 Serverafledte labels

Klienten sender aldrig `record_label`, `citation_label` eller `side` som
autoritative værdier.

- En eksisterende bindings labels bevares.
- For en ny binding afledes record-label deterministisk fra en accepteret
  placement-label, når der findes præcis én aktiv og gyldig placement;
  ellers bruges `record_key`.
- Citationen afledes fra source-label og de distinkte sideintervaller for
  aktuelt accepterede anchors, sorteret numerisk og kompakt gengivet.
- Manglende accepteret anchor er en terminal precondition-fejl, ikke en tom
  eller klientopfundet citation.

Labelprojektionen skal implementeres ét sted på serversiden og kontrakttestes;
read, create og publish må ikke have parallelle formatteringsregler.

### 5.3 Tilstandshash

`state_sha256` beregnes fra en kanonisk JSON-tilstand, som mindst binder:

- `(person_id, source_id, record_key)` og intern resolved record-identitet;
- stabil `source_record.public_ref`;
- aktuel anchor-/placement- og accepteret principal/co-principal-
  identitetsmængde med version;
- aktuel source-record-revisionstilstand;
- den anvendte redigeringsautoritet: `accepted_identity` eller
  `existing_exact_binding`;
- aktiv binding eller eksplicit fravær;
- den ordnede withdrawn-historiks identiteter, statusser og teksthashes;
- narrative-id, tekst, privacy og side;
- seneste publication-event-id, stream-version og eventets før-/efterhash;
- publication-status, provenance-/policyhash og serverafledte labels;
- om narrativet har afledte `haendelse`-rækker.

For legacy indgår desuden `legacy_publication_ref`, ledgerstatus,
baseline-hash, seneste legacy-event og eksplicit withdrawal-disposition.

Klienten sender hashen tilbage ved hver mutation. Writeren genberegner den
efter låsning og afviser mismatch som stale state. Hashen er concurrency-token,
ikke en godkendelse, og erstatter ikke revalidering af rolle, identity,
anchor, binding eller privacy.

### 5.4 Redaktionel publication-historik

Den rolle-gatede læse-RPC
`public.red_person_narrative_publication_history(p_person_id bigint)` returnerer
den ordnede eventhistorik for personens recordbindinger og grandfathered
legacy-publicationer. Hver række indeholder mindst event-id, change-set-id,
stream-version, eventtype, targetets `source_record_ref` eller
`legacy_publication_ref`, før-/efterhash og `can_reverse` med blocking reason.

RPC'en er den konkrete mapping mellem webhistorikken og den dedikerede
reversal. Den kan returnere de private før-/eftertekster til en godkendt
redaktør, men eksponerer aldrig source-record-UUID'er, policy-input eller andre
private identitetsrækker til offentlige roller.

## 6. Redaktionelle skrivekontrakter

Der oprettes separate record-baserede RPC'er samt én afgrænset
legacy-withdrawal:

- `public.red_upsert_person_narrative_record(p_person_id bigint,
  p_source_id bigint, p_record_key text, p_tekst text, p_privat boolean,
  p_expected_state_sha256 text) RETURNS jsonb`;
- `public.red_publicer_person_narrative_record(p_person_id bigint,
  p_source_id bigint, p_record_key text, p_expected_state_sha256 text)
  RETURNS jsonb`;
- `public.red_revider_publiceret_person_narrative_record(p_person_id bigint,
  p_source_id bigint, p_record_key text, p_tekst text,
  p_expected_state_sha256 text) RETURNS jsonb`;
- `public.red_revalider_person_narrative_record(p_person_id bigint,
  p_source_id bigint, p_record_key text, p_expected_state_sha256 text)
  RETURNS jsonb`;
- `public.red_kasser_person_narrative_record(p_person_id bigint,
  p_source_id bigint, p_record_key text, p_expected_state_sha256 text)
  RETURNS jsonb`;
- `public.red_tilbagetraek_person_narrative_record(p_person_id bigint,
  p_source_id bigint, p_record_key text, p_expected_state_sha256 text)
  RETURNS jsonb`;
- `public.red_tilbagetraek_legacy_narrative(p_legacy_publication_ref uuid,
  p_expected_state_sha256 text, p_begrundelse text) RETURNS jsonb`;
- `public.red_fortryd_person_narrative_publication_event(p_event_id uuid,
  p_expected_state_sha256 text) RETURNS jsonb`.

De tager kun de redaktionelle felter, som operationen faktisk behøver. Ingen
af dem tager `source_record_id`, narrative-id, labels eller side som
klientautoritet. Legacy-writeren adresserer kun den godkendte ledger-rækkes
uforanderlige `legacy_publication_ref`, aldrig en vilkårlig narrative-række.

### 6.1 Fælles preconditions og låserække

Hver record-baseret mutation skal i samme transaktion:

1. tage den delte cutover-lås og kræve aktiv contract-version `2`;
2. kræve autentificeret `redaktion`;
3. resolve præcis én source record på `(source_id, record_key)`;
4. låse `private.source_record` først;
5. låse relevante aktive og withdrawn publication-bindinger;
6. låse den seneste publication-eventversion og legacy-disposition, når de
   findes;
7. låse den aktive narrative-række, hvis den findes;
8. genberegne og sammenligne `state_sha256`;
9. revalidere accepteret anchor og den operationens krævede autoritet:
   den entydige principal/co-principal-identitetsmængde ved ny binding, eller
   en eksisterende eksakt binding uden en accepteret principal/co-principal-
   identitetskonflikt ved fortsat redigering;
10. kontrollere source-, subject-, privacy-, provenance- og
   publication-invarianter;
11. udføre præcis én tilladt projektionstilstandsovergang og append præcis
    ét event i samme change set;
12. verificere eventets efterhash mod den levende tilstand;
13. returnere den nye servermålte tilstand, event-id og nye hash.

Unique-indexen beskytter mod en glemt eller konkurrerende writer, men er ikke
en erstatning for source-record-låsen. Ingen writer må låse bindingen før
source recorden.

Legacy-withdrawal resolver ledger-rækken på `legacy_publication_ref` og låser i
rækkefølgen ledger, seneste event og narrative-række. Den kræver aktiv,
hash-matchende grandfathered status, frisk state hash og en ikke-tom privat
begrundelse. Den opretter ikke en source record og anvender derfor ikke
record-låserækken.

### 6.2 Upsert-tilstande

Den record-baserede upsert tillader:

| Førtilstand | Handling | Eftertilstand |
| --- | --- | --- |
| Ingen binding + entydig accepteret identitetsmængde | Opret narrativ, binding og event atomisk | `draft` |
| Aktiv `draft` uden identity-konflikt | Opdater præcis kladden og append event | `draft` |
| Aktiv `published` | Afvis almindelig upsert | Uændret |
| `stale_published` | Afvis almindelig upsert | Uændret |
| Kun `withdrawn` historik + entydig accepteret identitetsmængde | Opret nyt narrativ, binding og event | `draft` |
| Legacy uden binding | Afvis | Uændret |
| Ny binding uden entydig accepteret identitetsmængde | Afvis | Uændret |
| Eksisterende binding med accepteret identity til anden person | Afvis | Uændret |
| Manglende eller stale anchor | Afvis | Uændret |

Insert bruger narrative-tabellens identity-default; den gamle `max(id)+1`-
allokering videreføres ikke. Record-bundne drafts er fail-closed skjult af
publication-gaten og den direkte narrative-RLS; `narrative.privat=false` er
aldrig i sig selv tilstrækkeligt til offentlig synlighed.

Et allerede publiceret narrativ kan ikke gemmes gennem almindelig upsert.
Redaktøren bruger en udtrykkelig `Publicér ændring`-handling, som atomisk:

1. revaliderer den aktuelle publication- og provenance-tilstand;
2. gemmer den nye tekst i narrative-projektionen;
3. appender et `published_revision`-event med fuld gammel og ny tekstversion;
4. efterverificerer tekst- og tilstandshash.

Der findes derfor ingen tavs immediate-update af publiceret tekst. #152
opretter ikke separate tabeller for alle rå og normaliserede tekststadier, men
de konkrete offentlige versioner kan rekonstrueres fra eventloggen.

Hvis narrativet har en eller flere `haendelse`-rækker, afvises tekstændringen
med en særskilt fejl. #152 hverken sletter eller regenererer den envejs
proseprojektion.

En aktiv kladde kan kasseres eksplicit gennem
`red_kasser_person_narrative_record`. Handlingen sletter hverken narrativ,
binding eller tidligere draft-versioner; den sætter den aktuelle projektion
til `withdrawn` og appender `draft_discarded`. En senere ny kladde følger den
almindelige withdrawn-only-gren og kræver igen aktuelt identity-grundlag.

### 6.3 Publish, revision, revalidation, discard og withdraw

- Publish kræver en aktiv `draft`, frisk tilstandshash, accepteret anchor og
  operationens gyldige autoritet: en entydig principal/co-principal-
  identitetsmængde ved en ny binding eller en eksisterende eksakt binding uden
  identitetskonflikt. Narrativet skal være ikke-privat, og personen skal bestå
  den eksisterende offentlige privacy-/staged-policy.
- Publish bruger serverafledte labels og et konkret provenance-/policy-snapshot
  og appender et `published`-event. Klientoverstyring af labels eller
  provenance er ikke tilladt.
- Revision af en publiceret tekst er en ny eksplicit publiceringsbeslutning,
  ikke et almindeligt save; den appender `published_revision`.
- En stale publicering er usynlig. `revalidated` kan kun oprettes efter
  eksplicit redaktørhandling mod den friske state hash og uden tekstændring.
- Withdraw kræver en aktiv `published` binding og frisk tilstandshash.
- Withdraw muterer statusprojektionen og appender et `withdrawn`-event. Tekst
  og historik slettes ikke.
- Legacy-withdrawal kræver en aktiv, hash-matchende grandfathered ledger-række,
  sætter kun ledger-dispositionen til `withdrawn` og appender
  `legacy_withdrawn`. Den ændrer ikke teksten eller `narrative.privat`, men
  skjuler straks kun denne legacy-publication gennem v1, v2 og direkte RLS.
- Genpublicering af en withdrawn binding er ikke tilladt; en ny kladde oprettes
  gennem upsertens withdrawn-only-gren.

### 6.4 Dedikeret reversal og generisk undo

`red_fortryd_person_narrative_publication_event` er den eneste tilladte
fortrydelsesvej for #152-events. Den:

- kræver, at eventet er seneste ikke-reverserede event i streamen;
- afviser et target med eventtypen `reversal`; audit-fortrydelser kan ikke selv
  fortrydes som redo, og den ønskede tilstand skal i stedet skabes gennem en ny
  eksplicit domænehandling;
- låser og måler samme record- eller legacy-state som de øvrige writere;
- kræver, at den levende tilstand er identisk med eventets eftertilstand;
- revaliderer privacy, identity, provenance og policy før en reversal, som
  ville gøre indhold offentligt;
- gendanner den semantiske førtilstand og appender et nyt `reversal`-event med
  egen identitet og reference til det reverserede event;
- sletter aldrig eventhistorik. Reversal af en ny draft markerer bindingen
  withdrawn frem for at slette beviset for, at den fandtes.

Reversal af `legacy_withdrawn` må kun genetablere ledgerens aktive status, hvis
den oprindelige baseline stadig matcher, og den aktuelle person-, privacy- og
publication-policy fortsat tillader offentlighed. Ellers forbliver
publicationen withdrawn.

Det generiske `red_fortryd_change_set` skal afvise change sets, som indeholder
en `narrative_publication_event`, med
`NARRATIVE_RECORD_DEDICATED_REVERSAL_REQUIRED`. Dermed kan den almindelige
undo-motor ikke gendanne narrative-rækken uden samtidig at gendanne den
private publication-projektion og eventhistorik. Webhistorikken ruter i stedet
disse change sets til den dedikerede reversal-RPC.

Mekanismen er et eksplicit første opslag, før der oprettes et reversal-change
set eller udføres inverse DML:

```sql
EXISTS (
  SELECT 1
    FROM private.narrative_publication_event
   WHERE change_set_id = p_change_set_id
)
```

Eventtabellens `change_set_id` og §5.4's historik-RPC leverer den modsatte
mapping fra webhistorikken til `event_id`. `public.change_event` bruges ikke
som oracle for private publication-events.

### 6.5 Audit og fejlkontrakt

Hver vellykket mutation er ét change set med operation, person, source og
record key i auditbeskrivelsen. Resultatet skal identificere event,
narrative- og binding-rækker samt før-/efterhash; et rækkeantal alene er ikke
tilstrækkeligt. En mutation uden præcis én matchende append-only event skal
rulle tilbage.

Alle `SECURITY DEFINER`-funktioner får fast, kvalificeret `search_path`, en
kontrolleret owner, som ikke bruges som klientrolle, og eksplicitte grants
efter mindst mulige privilegier. `PUBLIC`, `anon` og andre roller får ingen
implicit adgang til private tabeller eller redaktionelle writere.

Forventede afvisninger har stabile maskinkoder, mindst for:

- forkert rolle;
- record ikke fundet eller tvetydig;
- stale state;
- stale publication eller publication-event mismatch;
- manglende/tvetydig anchor eller principal/co-principal-identitetsmængde;
- person/source mismatch;
- aktiv binding-kollision;
- forsøg på at redigere legacy-tekst eller -binding;
- derived-event-blockering;
- ulovlig publication-transition;
- generisk undo på et dedikeret publication-change-set;
- ikke-seneste, allerede reverseret eller driftet reversal-event;
- reversal-af-reversal;
- ugyldig, allerede withdrawn eller driftet legacy-publication;
- gammel DAA-loader eller direkte updater efter aktiv contract-version `2`;
- hel-person-sletning med append-only publication-historik.

## 7. Offentlig læsekontrakt v2

Den editionsneutrale, offentligt læsbare
`public.narrative_record_contract_version() RETURNS integer` er deploy-gaten.
Den returnerer `1` i den additive forberedelsesfase og erstattes
transaktionelt med version `2` som cutoverens sidste logiske skridt. Nye
klienter bruger ikke v2 eller de nye writere, før den returnerer mindst `2`.
Funktionen returnerer kun versionsnummeret og eksponerer ingen privat tilstand.

Den eksisterende `public_person_bio_source_versions(bigint[])` brydes ikke i
den additive fase. RPC'en
`public.public_person_bio_source_versions_v2(p_person_ids bigint[])` tilføjes
med samme privacy- og publication-gates og følgende ekstra sorteringsdata:

- offentligt `source_id`;
- struktureret `source_year` fra `source.aar`;
- numerisk første side som record-order, når den kan afledes;
- stabil `source_record_ref`, labels, den godkendte eventtekst og
  provenance-kind.

V2 returnerer aldrig `record_key`, `source_record_id`, private identity-data,
drafts eller withdrawn bindinger.

En record-bundet række returneres kun, når:

- bindingens aktuelle projektion er `published`;
- eventstreamens reducerede eftertilstand er `published` og matcher den
  aktuelle projektion;
- den levende tekst-, provenance-, identity-, privacy- og policytilstand
  matcher den reducerede eftertilstands publicerede hash.

RPC'en leverer tekstversionen fra den autoritative reducerede eftertilstand. En
stale eller delvist muteret projektion er usynlig, indtil en eksplicit revision
eller revalidation skaber et nyt event.

Den delte core-mapper bevarer hver RPC-række som en separat version og sorterer:

1. `source_year DESC NULLS LAST`;
2. `source_id ASC` som ren deterministisk tie-break mellem sources;
3. bound source records før legacy inden for samme source;
4. numerisk record-side;
5. record-label;
6. stabil `source_record_ref` som sidste tie-break.

Kun `source.aar` udtrykker kronologi. `source_id` er en opaque
databaseidentitet og må ikke fortolkes som nyere eller ældre; sources uden år
sorteres derfor sidst, uanset deres id.

Den første publicerede, record-bundne række i denne orden er standardvalget.
Hvis personen ikke har nogen publiceret record-bundet række, er den første
eligible legacy-række fallback. Alle øvrige rækker er fortsat tilgængelige
som selvstændige kildeversioner.

Legacy-rækker vises kun, når de har en aktiv, hash-matchende grandfathered
legacy-publication. De vises altid som `Overgangsdata` og aldrig sammenlagt med
en record-bundet tekst. Nye ubundne rækker er fail-closed usynlige.

Den eksisterende v1-RPC bevarer sin signatur i kompatibilitetsperioden, men
dens implementation flyttes til den samme event- og legacy-gatede projektion.
Dermed kan en gammel klient ikke omgå stale- eller publication-gaten.

Direkte `SELECT` på `public.narrative` må heller ikke omgå kontrakten. For
`anon` og `authenticated` uden redaktionsautoritet er RLS-reglen udtømmende,
når `subjekt_type='person'` og sourcen har `slags='DAA-udgave'`:

- en record-bundet række er kun synlig, når den serverkontrollerede
  publication-predicate består;
- en ubundet række er kun synlig, når en aktiv, hash-matchende grandfathered
  legacy-ledger autoriserer netop den;
- alle andre person/DAA-rækker, herunder nye ubundne, drafts, withdrawn og
  stale projektioner, er skjult.

Ikke-personlige narrativer og person-narrativer fra ikke-DAA-sources bevarer
deres eksisterende RLS-semantik. Den eksisterende redaktion-policy kan fortsat
læse private projektioner, men alle førstepartsflows, som læser person/DAA,
flyttes til RPC-kontrakten, fordi den returnerer den godkendte eventtekst og den
komplette kildehenvisning. `haendelse`-policyens eksisterende
`EXISTS narrative`-kaskade skal dermed bevidst skjule en hændelse, hvis dens
person/DAA-narrativ ikke længere har en gyldig offentlig publication; øvrige
narrativtyper må ikke rammes.

## 8. Web- og mobiloplevelse

Web og mobil bruger samme læsetyper, sortering og statussemantik. Den fulde
record-baserede redaktørflade bygges i web. Mobilens redaktørspor er fortsat
parkeret; #152 laver kun den minimale sikre klientmigration, som kræves for at
lukke den gamle writer.

### 8.1 Redaktion

- Sources vises nyeste først efter `source.aar`.
- Inden for hver source vises én fane eller et kort pr. konkret record, ordnet
  efter side og derefter record key.
- Hver record viser `Publiceret`, `Kladde`, `Intet narrativ`, `Tilbagetrukket`,
  `Publicering kræver genvalidering` eller en konkret blokeret tilstand.
- `Intet narrativ` tilbyder `Opret kladde`.
- `Tilbagetrukket` er read-only historik med mulighed for at oprette en ny
  kladde, når preconditions består.
- En aktiv kladde har handlingen `Kassér kladde`, som bevarer historikken og
  opretter `draft_discarded`.
- Legacy vises nederst som
  `Overgangsdata — kildepost ikke fastlagt`; teksten er read-only, men en aktiv
  række har en særskilt `Tag biografi ned`-handling med begrundelse.
- En publiceret tekst har ikke almindelig `Gem`. Ændringen udføres gennem
  `Publicér ændring`, viser før/efter-konsekvensen og opretter en ny
  publiceret eventversion.
- En stale publicering er offentligt skjult og tilbyder `Genvalidér
  publicering` efter visning af den ændrede provenance eller policy.
- Ved stale state overskriver klienten aldrig. Den viser serverens seneste
  tilstand og giver mulighed for at kopiere den lokale tekst eller genindlæse.
- Historik/fortryd bruger publication-eventets dedikerede reversal, ikke den
  generiske change-set-undo. Et reversal-event tilbyder ikke selv `Fortryd`.

### 8.2 Mobil-redaktørens minimum

- Mobilen kalder aldrig den gamle source-nøglede writer.
- Den henter den record-baserede kontrakt og sender altid `record_key` og
  `state_sha256` ved en tilladt handling.
- Hvis der ikke findes præcis én entydig, redigerbar aktiv record, er
  person/DAA-narrativredigering read-only med henvisning til webredaktionen.
- Mobilen får ikke fulde recordfaner, withdrawn-historik eller avanceret
  reversal-UI i #152.

### 8.3 Offentlig personvisning

- Kun publicerede, ikke-private og policy-gyldige recordbindinger vises som
  record-bundne versioner.
- Hver record bevares separat med kilde- og citationslabel.
- Den stabile `source_record_ref` bevares på tværs af withdraw og ny
  publication-binding.
- Nyeste udgave vælges deterministisk efter den fælles v2-orden.
- Legacy blandes ikke med record-bundne tekster.
- Den source-grupperende `buildBioVersions`-fallback fjernes fra det nye
  dataflow. En v2-RPC-fejl giver en eksplicit hente-fejl, ikke en muligvis
  forkert sammenlagt biografi.

## 9. Udrulning

### Fase 0 — styring og hash-låste baselines

- Opdatér roadmap/status med den gennemførte C3-produktionskørsel og #152 som
  aktivt programmål.
- Registrér den reviderede #152-beslutning i `docs/decisions.md`; den tidligere
  direkte `narrative.source_record_id`-skitse bliver historisk, ikke gældende
  implementeringskontrakt.
- Byg et read-only kandidatmanifest over alle eksisterende recordbindinger,
  deres publication-tilstand og de eventbaselines, migrationen vil oprette.
- Byg et separat read-only kandidatmanifest med det eksakte grandfathered
  legacy-ID-sæt og alle relevante førhashes.
- Genmål den operationelle bestand: bindinger, legacy pr. source, accepterede
  persona-identiteter, records uden entydig identity og berørte direkte læsere.
- Kræv menneskelig godkendelse af begge friske production-manifester før en
  production apply; dynamisk `INSERT ... SELECT` uden godkendt ID-sæt er ikke
  tilladt.
- Manifesterne er snapshots, ikke stående autorisation. Enhver ændring mellem
  godkendelse og cutover afviser hele transaktionen og kræver nye manifester og
  ny menneskelig godkendelse.
- Kræv desuden en særskilt projektejergodkendelse af den målte redaktions- og
  importfrysning i §2.1.

### Fase 1 — additiv databaseforberedelse

- Tilføj og backfill unik `private.source_record.public_ref` uden at ændre
  source recordens interne identitet.
- Implementér append-only publication-eventlog, grandfathered legacy-ledger,
  fælles label-/state-/publication-projektion, granulær legacy-withdrawal og
  dedikeret reversal.
- Definér den editionsneutrale cutover-gate som
  `hashtextextended('daa-narrative-record-contract',0)`. Alle
  narrative-capable gamle og nye veje tager den som første transaktionslås med
  `pg_advisory_xact_lock_shared` ved almindelig drift og
  `pg_advisory_xact_lock` ved cutover. Eksisterende 1939-/loaderlåse tages
  altid bagefter.
- Opdatér hver gammel person/DAA-skrivevej, herunder `red_upsert_narrativ`, de
  gamle publication-RPC'er, C3's eksakte narrative-writer,
  `R/update-1939-narratives.R`, `R/update-2018-narratives.R` og
  `.claude/skills/daa-extract/scripts/load_daa.R`, til først at tage den delte
  cutover-lås og derefter kontrollere, at contract-versionen fortsat er `1`.
  Loaderen afviser efter version `2` hele kørslen før første mutation med
  `NARRATIVE_RECORD_LOADER_MIGRATION_REQUIRED`, indtil #153 erstatter dens
  direkte narrative-write.
- Lad `red_slet_person` tage den delte cutover-lås, opdatér
  `red_slet_person_preview` til at vise publication-eventhistorik, og afvis
  tidligt med en stabil domænefejl, når historikken findes. #152 må hverken
  slette eller kaskadeslette append-only events; den permanente
  tombstone-/retentionsløsning forbliver et særskilt åbent valg.
- Bring `schema.sql`'s gamle `max(id)+1`-definition af `red_upsert_narrativ` i
  sync med den effektive identity-default-definition i `db-migrations.sql`, og
  bevis at ingen aktiv person/DAA-vej kan bruge `max(id)+1` efter cutover.
- Implementér record-baserede editor-RPC'er, publication-historik og offentlig
  v2-RPC.
- Installér `narrative_record_contract_version()` med resultat `1`.
- Nye write-RPC'er installeres uden almindelig `authenticated`-write-authority,
  og v2-dataflowet aktiveres ikke endnu. De gamle klienter og gate-instrumenterede
  writere bevarer deres version-1-adfærd frem til cutover;
  forberedelsesfasen må derfor ikke påstå, at eventloggen allerede er komplet.
- Test hele den kommende baseline og cutover mod en frisk disposable
  produktionsrestore.

### Fase 2 — web og minimal mobilmigration

- Flyt webredaktionen til record-read/upsert/publish/revision/revalidate/
  discard/withdraw/legacy-withdraw/history/reversal.
- Flyt mobilredaktionen til den minimale fail-closed recordkontrakt i §8.2;
  byg ikke den parkerede fulde mobilredaktør.
- Flyt offentlige dataflows til v2 og den delte sortering.
- Klassificér samtlige direkte `public.narrative`-læsere i web og mobil.
  Person/DAA-flows flyttes til v2/editor-RPC; ikke-personlige og ikke-DAA-flows
  bevises uændrede. `haendelse`-kaskaden testes særskilt.
- Fjern den sammenlæggende fallback fra det nye dataflow.
- Deploy klienterne capability-aware: de bruger først den nye kontrakt, når
  serveren annoncerer det aktive contract-version efter cutover. Før cutover
  fortsætter den deployede kode den eksisterende læsevej og må ikke kalde de
  endnu ikke autoriserede nye writere.
- Verificér web og mobil med fokuserede tests, fuldt build og reel røgtest.

### Fase 3 — atomisk write-authority-cutover

Under en eksklusiv transaktionslås på den samme globale cutover-gate og i én
transaktion:

1. kontrollér de godkendte baseline-manifesters eksakte ID-sæt og førhashes;
2. lås `public.narrative` i den etablerede kanoniske tabelrækkefølge og løft
   identity-sekvensens næste værdi monotont over levende narrative-id'er,
   relevante historiske `change_event`-id'er, publication-eventernes
   narrative-id'er og den allerede allokerede sekvensværdi;
3. indlæs record-publication-baselines og grandfathered legacy-ledger og
   verificér eventernes efterhashes;
4. omskriv ikke C3-bindinger og konstruér ingen identity-afgørelser; registrér
   kun deres målte tilstand som `baseline`-events;
5. flyt v1-RPC'en og direkte narrative-RLS til den event-/legacy-gatede
   projektion;
6. giv `authenticated` execute på de nye writer-RPC'er;
7. luk alle gamle person/DAA-skriveveje og gør loaderens version-2-afvisning
   aktiv;
8. sæt serverens narrative-record-contract-version aktiv som transaktionens
   sidste logiske skridt.

Sekvensløftet følger projektets eksisterende monotone floor-kontrakt: det sker
under tabel- og cutover-lås, må aldrig sænke næste værdi og bruger ikke en
ulåst `setval(max(id)+1)`. Dermed dækkes både identity-defaults, historiske
slettede id'er og direkte loader-id'er.

Alle nye writere tager den delte cutover-lås og kræver version `2`, før de
resolver eller muterer en record. Et gammelt kald, som blev autoriseret lige
før cutover, men ventede på den eksklusive lås, genlæser derfor versionen efter
låsning og afvises uden writes. ACL-revokes er en ekstra adgangsbarriere, ikke
det eneste concurrency-bevis.

Efter verificeret klientmigrering ændres den gamle `red_upsert_narrativ`, så
den afviser **alle** `subjekt_type='person'`-skrivninger til en source med
`slags='DAA-udgave'` med en stabil `NARRATIVE_RECORD_REQUIRED`-fejl.

I samme fase fjernes `authenticated`-execute fra de gamle
`red_publicer_narrative_record(bigint,uuid,text,text)` og
`red_tilbagetraek_narrative_record(bigint)`. De må ikke forblive en alternativ
vej uden state hash, identity-/anchor-gate og serverafledte labels. Eventuel
fortsat `service_role`-adgang kræver en konkret levende consumer og verificeres
eksplicit; ellers revokes den også.

Den gamle writer bevares for:

- ikke-personlige subjekter;
- person-narrativer fra ikke-DAA-sources, indtil et senere roadmapmål beslutter
  andet.

Ældre redaktørklienter må gerne fejle synligt efter cutover; de må ikke kunne
fortsætte den tvetydige skrivevej. Cutover deployes ikke, før aktuelle web- og
mobilklienter er verificeret capability-aware mod fase 1.

### Produktionsgate

Implementering og disposable bevis giver ikke automatisk produktions-GO.
Produktion kræver et separat checkpoint med frisk backup, schema-/ACL-driftcheck,
transaktionel migration, postverify, eksplicit projektejergodkendelse og den
særskilte accept af §2.1's målte overgangsomkostning.

## 10. Verifikation

### 10.1 Database og concurrency

Disposable PostgreSQL-integration skal bevise:

- to records for samme person og samme source kan oprettes og redigeres
  uafhængigt;
- hver writer rammer præcis den record-bundne narrative-række;
- en record uden aktiv binding bliver `draft`, ikke `published`;
- drafts er usynlige gennem både v1, v2 og direkte narrative-SELECT;
- kun-withdrawn historik bevares byte-identisk, mens en ny draft oprettes;
- forkert person, source mismatch, manglende anchor og en tom, tvetydig eller
  modstridende principal/co-principal-identitetsmængde afvises uden writes;
- eksisterende C3-/recordbindinger uden en generel identity-række kan redigeres
  på samme person, mens nye bindinger uden en entydig accepteret
  principal/co-principal-identitetsmængde afvises;
- stale `state_sha256` afvises uden writes;
- to samtidige creates/updates kan ikke skabe to aktive bindinger, to eventer
  med samme stream-version eller tabte opdateringer; dette testes med reelt
  separate databasesessioner;
- et gammelt writer-kald, der starter før cutover og blokerer på den fælles
  gate, afvises uden writes efter contract-version `2`; nye writere kan ikke
  skrive før version `2`;
- DAA-loaderen tager cutover-gaten før sin eksisterende writer-lås, virker som
  før ved version `1` og afviser hele version-2-kørslen før første write;
- de to direkte narrative-update-scripts afviser tilsvarende version `2`, og
  `red_slet_person` afviser før writes, når personen har publication-events;
- cutoverens monotone narrative-sekvensløft håndterer både en høj eksplicit
  loader-id, et slettet historisk id og en allerede allokeret sequence-værdi;
  næste default-insert kolliderer ikke, og resync sænker aldrig sekvensen;
- en narrativ med `haendelse` afviser tekstændring uden sideeffekt;
- almindelig upsert af publiceret tekst afvises; eksplicit revision bevarer den
  fulde gamle og nye publicerede tekstversion i hvert sit event;
- publish/revision/revalidate/withdraw-transitioner og privacy/staged-gates er
  fail-closed;
- anchor-, rendition-, identity-, tekst- eller policy-drift gør den offentlige
  projektion usynlig gennem v1, v2 og direkte SELECT;
- revalidation kræver frisk state og opretter en ny beslutningsversion;
- hvert writerkald appender præcis én hash-matchende event, og eventtabellen
  afviser update/delete;
- kassation af en kladde appender `draft_discarded`, bevarer alle versioner og
  tillader kun en senere ny kladde gennem den normale identity-gate;
- dedikeret reversal virker for draft-create, draft-update, draft-discard,
  publish, published-revision, revalidate, withdraw og legacy-withdraw; drift
  eller ikke-seneste event afvises uden writes, og reversal-af-reversal afvises;
- generisk `red_fortryd_change_set` afviser #152-change sets gennem det direkte
  private eventopslag uden at røre narrative eller binding, også når sættet ikke
  har en `public.change_event`;
- historik-RPC'en mapper hvert publication-change-set til det korrekte event og
  markerer kun et faktisk reversibelt seneste domæneevent som `can_reverse`;
- baselineimporten matcher de to godkendte manifesters eksakte ID-sæt og
  hashes; en ekstra, manglende eller driftet række afviser hele transaktionen;
- kun aktive hash-matchende grandfathered legacy-rækker er offentlige; nye
  ubundne narrativer bliver ikke synlige;
- granulær legacy-withdrawal skjuler præcis den valgte biografi gennem v1, v2
  og direkte SELECT uden at skjule personens andre narrativer; event, begrundelse
  og tekst bevares privat, og en usikker reversal afvises;
- direkte RLS skjuler alle ikke-autoriserede person/DAA-rækker, mens
  ikke-personlige og ikke-DAA-narrativer bevarer deres eksisterende synlighed;
  `haendelse`-kaskaden følger kun den tilsigtede narrative-publication;
- `source_record.public_ref` er unik, uforanderlig og den samme efter withdraw
  og en ny binding;
- public/editor-RPC'er returnerer ingen private source-record-UUID'er;
- grants, revokes, owner, `search_path`, RLS og PostgREST-signaturer er eksakt
  verificeret;
- den gamle writer afviser person/DAA efter fase 3, men godkendte andre cases
  virker fortsat;
- de gamle publish/withdraw-RPC'er kan ikke kaldes af `authenticated` efter
  fase 3, og ingen klient refererer dem længere;
- change sets og events matcher den eksakte write-set, ikke kun antal.

### 10.2 Fælles core, web og mobil

Kontrakttests skal mindst dække:

- `source_year DESC NULLS LAST`, opaque `source_id ASC`- og
  record-tie-breaks;
- to records i samme bog forbliver to versioner;
- bound før legacy og ingen tekstkonkatenering;
- draft, published, stale_published, withdrawn, none og blocked vises korrekt;
- legacy-tekst og -binding er read-only; kun den særskilte withdrawal sender
  `legacy_publication_ref`, frisk state hash og begrundelse;
- create/save/discard/publish/revision/revalidate/withdraw/reversal sender den
  præcise record- og state-kontrakt og ingen private source-record-UUID'er;
- publiceret tekst har ingen almindelig save-vej;
- stale state viser konflikt uden automatisk retry eller overwrite;
- stale publicering vises som blokeret i redaktionen og er fraværende offentligt;
- RPC-fejl aktiverer ikke den gamle sammenlæggende fallback;
- samme offentlige kontrakttest kører mod web- og mobiladapteren;
- mobilen er fail-closed read-only ved nul eller flere mulige aktive records og
  indeholder ikke den parkerede fulde recordredaktør.

### 10.3 Ende-til-ende-røgtest

Røgtesten skal i en isoleret database og en reel browser demonstrere:

1. en person med to records i samme DAA-source;
2. oprettelse af kladde på den ene record;
3. uafhængig redigering af begge records;
4. stale-konflikt fra en anden session;
5. eksplicit publicering, publiceret revision og separat offentlig visning af
   den godkendte eventtekst;
6. provenance-drift, som skjuler publiceringen, efterfulgt af eksplicit
   revalidation;
7. dedikeret reversal uden tab af eventhistorik;
8. kladdekassation uden sletning af historik og synligt forbud mod
   reversal-af-reversal;
9. grandfathered legacy synlig og tekst-read-only, granulær withdrawal af kun
   den valgte biografi samt en ubaseline't legacy-række, der forbliver skjult;
10. stabil `source_record_ref` gennem withdraw og ny binding;
11. web og mobil bruger samme offentlige orden og recordidentitet, mens mobilens
    tvetydige redaktørcase er read-only.

Fokuserede tests og fuld suite/build rapporteres separat. En grøn isoleret
SQL-test er ikke alene bevis for `integreret ende-til-ende`.

## 11. Ikke-mål og eksplicit teknisk gæld

- Ingen automatisk binding eller tekstkirurgi for legacy-rækker.
- Ingen fuld selvstændig tabelmodel for alle rå, normaliserede og redigerede
  tekststadier. Konkrete publicerede versioner og deres provenance bevares dog
  obligatorisk i publication-eventloggen.
- Ingen automatisk regenerering af `haendelse`.
- Ingen nye identitetsafgørelser i narrative-writere.
- Ingen udgavespecifik permanent RPC eller tabel.
- Ingen fuld mobil-recordredaktør; kun den nødvendige sikre klientmigration.
- Ingen generalisering af batch-/writerinfrastrukturen; det er #153.
- Ingen 2018-20-proveniens-backfill; det er #149 og forudsætter #153.
- Ingen ny implicit legacy-publication fra en loader. Den eksisterende
  DAA-loader er midlertidigt blokeret ved contract-version `2`, indtil #153
  leverer den nye writerkontrakt.
- Ingen løsning af den eksisterende tombstone-/retentionsbeslutning for
  hel-person-sletning. #152 blokerer i stedet hard delete, når append-only
  publication-events findes, så historikken ikke ødelægges stiltiende.
- Ingen garanti for almindelig oprettelse af nye person/DAA-kladder før den
  entydige identity-gate er befolket; den målte overgangsfrysning i §2.1 er en
  eksplicit produktionsomkostning.
- Ingen produktionsmutation som følge af design- eller implementerings-GO.

Målarkitekturens fulde krav om adskilte rå, normaliserede og redigerede
tekststadier er fortsat uopfyldt efter #152. #152 lukker kun den konkrete
offentlige versionsgrænse: ingen publiceret tekst overskrives uden et nyt
append-only publicerings-event, og offentlige læsere ser kun en eventbundet,
ikke-stale version.

## 12. Godkendelser

Projektejeren godkendte 2026-08-29, i denne rækkefølge:

1. løsning A med den private publication-sidecar som autoritativ binding;
2. fail-closed, read-only håndtering af ubundne legacy-narrativer;
3. `(source_id, record_key)` som redaktionel kontrakt, serverafledte labels,
   state hash og record-first lock discipline;
4. oprindeligt en record-baseret web-/mobiloplevelse og separat offentlig
   visning; punkt 11 nedenfor indsnævrer den fulde redaktørflade til web;
5. additiv database, klientmigrering og efterfølgende fail-closed udfasning af
   den gamle person/DAA-writer;
6. eksisterende eksakt recordbinding som stående redigeringsautoritet uden
   identity-backfill, men med fail-closed blokering ved en accepted identity til
   en anden person.

Efter den tværgående DAA-arkitekturgennemgang bad projektejeren samme dag om at
revidere specen med:

7. append-only publication-eventaudit og dedikeret reversal;
8. konkret tekst-/occurrence-/rendition-/identity-/policybinding og stale-gate;
9. et eksakt, hash-låst og menneskegodkendt grandfathered legacy-ledger;
10. en stabil offentlig `source_record.public_ref` adskilt fra
    publication-bindingens gamle `record_ref`;
11. mobil scope't til den minimale sikre klientmigration.

Det eksterne review 2026-08-29 er i denne revision disponeret således:

12. granulær legacy-withdrawal er tilføjet som et sikkerhedsminimum, så én
    biografi kan tages ned uden at skjule hele personen;
13. den målte frysning af nye bindinger og DAA-import er gjort til en synlig
    overgangsomkostning, som kræver særskilt projektejergodkendelse før
    production cutover;
14. RLS-reglen omfatter nu udtrykkeligt både bundne og ubundne person/DAA-rækker,
    mens ikke-DAA-semantik bevares, og den direkte DAA-loader er med i
    write-authority-cutoveren;
15. generisk undo bruger et direkte eventopslag på `change_set_id`, og
    webhistorikken får den manglende eventmapping;
16. cutover får et monotont sekvensløft; påstanden i det eksterne review om den
    effektive gamle writers `max(id)+1` var ikke helt korrekt, fordi den seneste
    definition i `db-migrations.sql` allerede bruger identity-default, men
    `schema.sql`-driften og øvrige direkte writer-id'er skal stadig lukkes;
17. principal/co-principal er defineret med skemaets faktiske roller,
    kladdekassation er en eksplicit event, reversal-af-reversal er forbudt, og
    `source_id` er kun en opaque, deterministisk `ASC`-tie-break.

Instruksen om at indarbejde fair reviewfund autoriserer denne skriftlige
revision. Den tæller ikke som den særskilte accept af §2.1's production-
omkostning eller som implementerings-/produktions-GO.

Næste tilladte artefakt efter projektejerens review af denne skrevne spec er
en implementeringsplan. Der implementeres ingen kode på grundlag af den
mundtlige godkendelse alene.
