# Record-nøglede person-narrativer (#152) — design

**Dato:** 2026-08-29

**Status:** Godkendt design; afventer implementeringsplan

**Roadmapmål:** #152 — narrativer knyttes entydigt til en konkret source record

**Modenhed:** `specificeret`

**Grundlag:** Levende schema og klientkode på lokal `main` ved `7b5dc5a`

## 1. Beslutning

Person-narrativer fra DAA skal fremover læses og skrives med en konkret
source record som redaktionel nøgle. Den eksisterende private
`narrative_record_publication` forbliver den autoritative binding mellem
`public.narrative` og `private.source_record`.

Der tilføjes **ikke** en `source_record_id`-kolonne til `public.narrative`.
Private source-record-UUID'er eksponeres ikke til web, mobil eller offentlige
læsere. Redaktionelle kald identificerer i stedet en record med dens stabile,
editionsneutrale locator `(source_id, record_key)`; databasen resolver og
låser den private UUID internt. Den offentlige projektion bevarer den
eksisterende tilfældige `record_ref`.

Designet er valgt frem for:

- en minimal database-only writer, som ikke ville løse redaktørens eller
  læserens record-granularitet;
- en direkte privat UUID-kolonne på den offentligt læsbare narrative-tabel;
- en fuld immutable narrativversionsmodel, som er den langsigtede retning, men
  er større end #152 og ikke må smugles ind i dette roadmapmål.

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
- `record_key` er aldrig personidentitet.
- `private.narrative_record_publication` er den autoritative relation mellem
  et narrativ og en source record.
- `narrative_record_publication.record_ref` er den eneste record-reference i
  den offentlige læseprojektion.
- `public.narrative.source_id` bevares som bibliografisk source-binding og må
  ikke bruges som erstatning for en source record.

Der oprettes ingen ny public identity-map og ingen klientgenereret UUID.

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

### 4.3 Legacy

Et person/DAA-narrativ uden publication-binding er **legacy**. Det:

- vises som `Overgangsdata — kildepost ikke fastlagt`;
- er read-only i den nye redaktionelle flade;
- bindes aldrig automatisk, heller ikke hvis databasen kun finder én mulig
  source record;
- bliver først redigerbart gennem en senere, eksplicit og auditeret
  record-afgørelse.

#152 bygger ikke en sådan bindings-reviewflade. Den bevarer det uafklarede
materiale synligt og fail-closed.

## 5. Redaktionel læsekontrakt

Der etableres den editionsneutrale `SECURITY DEFINER`-RPC
`public.red_person_narrative_records(p_person_id bigint)` for én person. Den
returnerer en tabelkontrakt; komplekse withdrawn-historikker bæres som valideret
JSONB i den enkelte record-entry.

RPC'en må kun kaldes af en autentificeret bruger med rollen `redaktion`. Den
returnerer ingen private UUID'er. Hver record-række indeholder mindst:

- `person_id`, `source_id`, `source_year` og source-label;
- `record_key`, serverafledt record-label, citation og sideorden;
- `narrative_id`, tekst og privacy, når et aktivt narrativ findes;
- publication-status: `none`, `draft`, `published` eller `withdrawn`;
- read-only `withdrawn_history`, ordnet deterministisk, fordi en record kan
  have mere end én tidligere withdrawn binding;
- eligibility-status og en maskinlæsbar blocking reason;
- en kanonisk `state_sha256` til optimistisk concurrency-kontrol.

Der returneres én overordnet editor-entry pr. source record. En aktiv binding
ligger i entryens aktive felter; withdrawn bindinger ligger i den ordnede
historik. Status er `withdrawn`, når der ikke findes en aktiv binding, men
historikken ikke er tom.

Legacy-rækker returneres i en separat union-gren uden `record_key`, med
`provenance_kind='legacy_narrative'` og `editable=false`.

### 5.1 Hvilke records tilhører personens redaktørvisning?

En source record medtages, når mindst én af disse er sand:

1. recorden har allerede en aktiv eller withdrawn narrativbinding, hvis
   narrative-række peger på personen; eller
2. recorden har et aktuelt accepteret record-anchor og en `primary` persona,
   hvis aktuelle identity state er `accepted` til personen.

En eksisterende eksakt binding er stående autoritet til fortsat redigering af
det samme narrativ for den samme person. Det gælder også de publicerede C3-
bindinger, som er menneskegodkendt og batchauditeret, men ikke nødvendigvis
har en generel `source_persona_identity`-række. Bindingen autoriserer ikke en
ny person, record eller publication-binding.

Hvis en aktuel accepted-primary-identity for recorden peger på en anden
kanonisk person, bliver den eksisterende binding synlig, men blokeret med
`editable=false` og en konkret blocking reason. Fravær af en generel identity-
række blokerer derimod ikke fortsat redigering af en allerede eksakt binding.

Oprettelse af en ny binding — herunder efter kun-withdrawn historik — kræver,
at det aktuelle identity-grundlag entydigt understøtter samme person. Ingen
RPC i #152 må oprette eller ændre en source-persona-identity-afgørelse, og
eksisterende C3-bindinger backfilles ikke til konstruerede identity-afgørelser.

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
- aktuel anchor-/placement- og accepted-primary-identity-tilstand med version;
- den anvendte redigeringsautoritet: `accepted_identity` eller
  `existing_exact_binding`;
- aktiv binding eller eksplicit fravær;
- den ordnede withdrawn-historiks identiteter, statusser og teksthashes;
- narrative-id, tekst, privacy og side;
- publication-status og serverafledte labels;
- om narrativet har afledte `haendelse`-rækker.

Klienten sender hashen tilbage ved hver mutation. Writeren genberegner den
efter låsning og afviser mismatch som stale state. Hashen er concurrency-token,
ikke en godkendelse, og erstatter ikke revalidering af rolle, identity,
anchor, binding eller privacy.

## 6. Redaktionelle skrivekontrakter

Der oprettes separate record-baserede RPC'er:

- `public.red_upsert_person_narrative_record(p_person_id bigint,
  p_source_id bigint, p_record_key text, p_tekst text, p_privat boolean,
  p_expected_state_sha256 text) RETURNS jsonb`;
- `public.red_publicer_person_narrative_record(p_person_id bigint,
  p_source_id bigint, p_record_key text, p_expected_state_sha256 text)
  RETURNS jsonb`;
- `public.red_tilbagetraek_person_narrative_record(p_person_id bigint,
  p_source_id bigint, p_record_key text, p_expected_state_sha256 text)
  RETURNS jsonb`.

De tager kun de redaktionelle felter, som operationen faktisk behøver. Ingen
af dem tager `source_record_id`, narrative-id, labels eller side som
klientautoritet.

### 6.1 Fælles preconditions og låserække

Hver mutation skal i samme transaktion:

1. kræve autentificeret `redaktion`;
2. resolve præcis én source record på `(source_id, record_key)`;
3. låse `private.source_record` først;
4. låse relevante aktive og withdrawn publication-bindinger;
5. låse den aktive narrative-række, hvis den findes;
6. genberegne og sammenligne `state_sha256`;
7. revalidere accepteret anchor og den operationens krævede autoritet:
   entydig accepted-primary-identity ved ny binding, eller en eksisterende
   eksakt binding uden en accepted-primary-konflikt ved fortsat redigering;
8. kontrollere source-, subject-, privacy- og publication-invarianter;
9. udføre præcis én tilladt tilstandsovergang i et change set;
10. returnere den nye servermålte tilstand og dens nye hash.

Unique-indexen beskytter mod en glemt eller konkurrerende writer, men er ikke
en erstatning for source-record-låsen. Ingen writer må låse bindingen før
source recorden.

### 6.2 Upsert-tilstande

Den record-baserede upsert tillader:

| Førtilstand | Handling | Eftertilstand |
| --- | --- | --- |
| Ingen binding | Opret narrativ og serverafledt binding atomisk | `draft` |
| Aktiv `draft` uden identity-konflikt | Opdater præcis det bundne narrativ | `draft` |
| Aktiv `published` uden identity-konflikt | Opdater præcis det bundne narrativ | `published` |
| Kun `withdrawn` historik og accepted identity | Opret nyt narrativ og ny binding | `draft` |
| Legacy uden binding | Afvis | Uændret |
| Ny binding uden entydig accepted identity | Afvis | Uændret |
| Eksisterende binding med accepted identity til anden person | Afvis | Uændret |
| Manglende eller stale anchor | Afvis | Uændret |

Insert bruger narrative-tabellens identity-default; den gamle `max(id)+1`-
allokering videreføres ikke.

En tekstændring af et allerede publiceret narrativ bliver i #152 synlig med
det samme, ligesom i den nuværende model. Redaktørfladen skal advare om dette.
Immutable redigeringsversioner og copy-on-write-publicering er et senere
arkitekturarbejde; #152 må ikke fremstilles som opfyldelse af det princip.

Hvis narrativet har en eller flere `haendelse`-rækker, afvises tekstændringen
med en særskilt fejl. #152 hverken sletter eller regenererer den envejs
proseprojektion.

### 6.3 Publish og withdraw

- Publish kræver en aktiv `draft`, frisk tilstandshash, gyldig accepted-primary-identity/anchor,
  ikke-privat narrativ og en person, der består den eksisterende offentlige
  privacy-/staged-policy.
- Publish bruger de serverafledte labels og må ikke acceptere en
  klientoverstyring.
- Withdraw kræver en aktiv `published` binding og frisk tilstandshash.
- Withdraw muterer kun status på den aktive binding. Tekst og historik slettes
  ikke.
- Genpublicering af en withdrawn binding er ikke tilladt; en ny kladde oprettes
  gennem upsertens withdrawn-only-gren.

### 6.4 Audit og fejlkontrakt

Hver vellykket mutation er ét change set med operation, person, source og
record key i auditbeskrivelsen. Resultatet skal identificere de berørte
narrative- og binding-rækker samt før-/efterhash; et rækkeantal alene er ikke
tilstrækkeligt.

Forventede afvisninger har stabile maskinkoder, mindst for:

- forkert rolle;
- record ikke fundet eller tvetydig;
- stale state;
- manglende/tvetydig anchor eller primary identity;
- person/source mismatch;
- aktiv binding-kollision;
- legacy read-only;
- derived-event-blockering;
- ulovlig publication-transition.

## 7. Offentlig læsekontrakt v2

Den eksisterende `public_person_bio_source_versions(bigint[])` brydes ikke i
den additive fase. RPC'en
`public.public_person_bio_source_versions_v2(p_person_ids bigint[])` tilføjes
med samme privacy- og publication-gates og følgende ekstra sorteringsdata:

- offentligt `source_id`;
- struktureret `source_year` fra `source.aar`;
- numerisk første side som record-order, når den kan afledes;
- eksisterende sikre `record_ref`, labels, tekst og provenance-kind.

V2 returnerer aldrig `record_key`, `source_record_id`, private identity-data,
drafts eller withdrawn bindinger.

Den delte core-mapper bevarer hver RPC-række som en separat version og sorterer:

1. `source_year DESC NULLS LAST`;
2. `source_id DESC` som deterministisk tie-break mellem sources;
3. bound source records før legacy inden for samme source;
4. numerisk record-side;
5. record-label;
6. sikker `record_ref` som sidste tie-break.

Den første publicerede, record-bundne række i denne orden er standardvalget.
Hvis personen ikke har nogen publiceret record-bundet række, er den første
eligible legacy-række fallback. Alle øvrige rækker er fortsat tilgængelige
som selvstændige kildeversioner.

Legacy-rækker kan fortsat vises offentligt efter de eksisterende privacy-gates,
men altid som `Overgangsdata` og aldrig sammenlagt med en record-bundet tekst.

## 8. Web- og mobiloplevelse

Web og mobil bruger samme typer, sortering og statussemantik.

### 8.1 Redaktion

- Sources vises nyeste først efter `source.aar`.
- Inden for hver source vises én fane eller et kort pr. konkret record, ordnet
  efter side og derefter record key.
- Hver record viser `Publiceret`, `Kladde`, `Intet narrativ`, `Tilbagetrukket`
  eller en konkret blokeret tilstand.
- `Intet narrativ` tilbyder `Opret kladde`.
- `Tilbagetrukket` er read-only historik med mulighed for at oprette en ny
  kladde, når preconditions består.
- Legacy vises nederst som
  `Overgangsdata — kildepost ikke fastlagt` og er read-only.
- Gem af en publiceret tekst kræver en tydelig besked om, at ændringen bliver
  offentlig straks.
- Ved stale state overskriver klienten aldrig. Den viser serverens seneste
  tilstand og giver mulighed for at kopiere den lokale tekst eller genindlæse.

### 8.2 Offentlig personvisning

- Kun publicerede, ikke-private og policy-gyldige recordbindinger vises som
  record-bundne versioner.
- Hver record bevares separat med kilde- og citationslabel.
- Nyeste udgave vælges deterministisk efter den fælles v2-orden.
- Legacy blandes ikke med record-bundne tekster.
- Den source-grupperende `buildBioVersions`-fallback fjernes fra det nye
  dataflow. En v2-RPC-fejl giver en eksplicit hente-fejl, ikke en muligvis
  forkert sammenlagt biografi.

## 9. Udrulning

### Fase 1 — additiv database

- Implementér fælles label-/state-projektion og record-baserede editor-RPC'er.
- Implementér offentlig v2-RPC.
- Bevar eksisterende RPC'er og `red_upsert_narrativ` uændret i den additive
  kompatibilitetsperiode.
- Foretag ingen legacy-backfill og ingen omskrivning af eksisterende C3-
  bindinger.

### Fase 2 — web og mobil

- Flyt begge redaktørklienter til record-read/upsert/publish/withdraw.
- Flyt offentlige dataflows til v2 og den delte sortering.
- Fjern den sammenlæggende fallback fra det nye dataflow.
- Verificér web og mobil med fokuserede tests, fuldt build og reel røgtest.

### Fase 3 — fail-closed udfasning

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

Ældre redaktørklienter må gerne fejle synligt efter fase 3; de må ikke kunne
fortsætte den tvetydige skrivevej. Fase 3 deployes ikke, før aktuelle web- og
mobilklienter er verificeret mod fase 1.

### Produktionsgate

Implementering og disposable bevis giver ikke automatisk produktions-GO.
Produktion kræver et separat checkpoint med frisk backup, schema-/ACL-driftcheck,
transaktionel migration, postverify og eksplicit projektejergodkendelse.

## 10. Verifikation

### 10.1 Database og concurrency

Disposable PostgreSQL-integration skal bevise:

- to records for samme person og samme source kan oprettes og redigeres
  uafhængigt;
- hver writer rammer præcis den record-bundne narrative-række;
- en record uden aktiv binding bliver `draft`, ikke `published`;
- kun-withdrawn historik bevares byte-identisk, mens en ny draft oprettes;
- forkert person, source mismatch, manglende anchor og modstridende accepted-
  primary-identity afvises uden writes;
- eksisterende C3-/recordbindinger uden en generel identity-række kan redigeres
  på samme person, mens nye bindinger uden entydig accepted identity afvises;
- stale `state_sha256` afvises uden writes;
- to samtidige creates/updates kan ikke skabe to aktive bindinger eller tabte
  opdateringer; dette testes med reelt separate databasesessioner;
- en narrativ med `haendelse` afviser tekstændring uden sideeffekt;
- publish/withdraw-transitioner og privacy/staged-gates er fail-closed;
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

- `source_year DESC NULLS LAST`, source-id- og record-tie-breaks;
- to records i samme bog forbliver to versioner;
- bound før legacy og ingen tekstkonkatenering;
- draft, published, withdrawn, none og blocked vises korrekt;
- legacy er read-only og sender aldrig en mutation;
- create/save/publish/withdraw sender præcis `(person_id, source_id,
  record_key, expected_state_sha256)` og ingen private UUID'er;
- stale state viser konflikt uden automatisk retry eller overwrite;
- RPC-fejl aktiverer ikke den gamle sammenlæggende fallback;
- samme kontrakttest kører mod web- og mobiladapteren.

### 10.3 Ende-til-ende-røgtest

Røgtesten skal i en isoleret database og en reel browser demonstrere:

1. en person med to records i samme DAA-source;
2. oprettelse af kladde på den ene record;
3. uafhængig redigering af begge records;
4. stale-konflikt fra en anden session;
5. publicering og efterfølgende separat offentlig visning;
6. legacy-rækken synlig, mærket og read-only;
7. web og mobil bruger samme orden og recordidentitet.

Fokuserede tests og fuld suite/build rapporteres separat. En grøn isoleret
SQL-test er ikke alene bevis for `integreret ende-til-ende`.

## 11. Ikke-mål og eksplicit teknisk gæld

- Ingen automatisk binding eller tekstkirurgi for legacy-rækker.
- Ingen fuld immutable narrativversionsmodel eller copy-on-write-publicering.
- Ingen automatisk regenerering af `haendelse`.
- Ingen nye identitetsafgørelser i narrative-writere.
- Ingen udgavespecifik permanent RPC eller tabel.
- Ingen generalisering af batch-/writerinfrastrukturen; det er #153.
- Ingen 2018-20-proveniens-backfill; det er #149 og forudsætter #153.
- Ingen produktionsmutation som følge af design- eller implementerings-GO.

Målarkitekturens krav om adskilte rå, normaliserede, redigerede og
publicerbare narrativversioner er fortsat uopfyldt efter #152. Det skal stå
synligt som senere arkitekturarbejde; den nuværende immediate-update-semantik
må ikke omdøbes til versionssikker publicering.

## 12. Godkendelser

Projektejeren godkendte 2026-08-29, i denne rækkefølge:

1. løsning A med den private publication-sidecar som autoritativ binding;
2. fail-closed, read-only håndtering af ubundne legacy-narrativer;
3. `(source_id, record_key)` som redaktionel kontrakt, serverafledte labels,
   state hash og record-first lock discipline;
4. record-baseret web-/mobiloplevelse og separat offentlig visning;
5. additiv database, klientmigrering og efterfølgende fail-closed udfasning af
   den gamle person/DAA-writer;
6. eksisterende eksakt recordbinding som stående redigeringsautoritet uden
   identity-backfill, men med fail-closed blokering ved en accepted identity til
   en anden person.

Næste tilladte artefakt efter projektejerens review af denne skrevne spec er
en implementeringsplan. Der implementeres ingen kode på grundlag af den
mundtlige godkendelse alene.
