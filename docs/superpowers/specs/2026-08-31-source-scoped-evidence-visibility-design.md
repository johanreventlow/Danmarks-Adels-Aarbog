# #153: Source-scoped evidence visibility og revisioner

**Dato:** 2026-08-31
**Status:** Udkast til review — ingen implementeringsautoritet endnu.
**Supplerer:** `2026-08-30-generalized-writer-batch-design.md`, afsnittet
*Source-scoped replace-writer*.

## Formål og beslutning

#153's source-scoped writer skal fortsat kunne create, replace, remove og
kompensere positivt ejet kildeevidens. Den må imidlertid ikke gøre en ny
fact/assertion/citation læsbar, alene fordi dens person allerede er offentlig.
Denne specifikation indfører derfor en adapterejet, privat revisions- og
visibility-binding for de evidenskæder, writeren forvalter.

Den bevarer RLS-adfærden for historiske, ubundne facts. En adapterbundet kæde
er kun læsbar for `anon` og almindelig `authenticated`, når dens specifikke
revision har en gældende, positiv publiceringsbeslutning. Redaktionen beholder
sin eksisterende arbejdsadgang. En publiceringsbeslutning er altid separat fra
source-scoped apply.

Dette er en afgrænset #153-adapterudvidelse, ikke en global backfill eller en
ny generisk journal. Den erstatter det afviste fase-A-udkast i
`2026-08-30-source-scoped-replace-fact-contract-addendum.md`.

## Invariants og afgrænsning

Writerens dataeffekt er fortsat begrænset til den positive kæde
`source -> citation -> assertion -> fact(person)` og højst én
#152-kompatibel narrative draft-effekt. Den ændrer aldrig `relation`, `note`,
`haendelse`, `story`, familieobjekter, `same_som`, identitets- eller
publiceringshistorik. Den må ikke ændre publiceret narrativ eller skabe
`published`, `published_revision`, `stale` eller `withdrawn` narrativevents.

Nye evidensrækker er append-only. Replace og remove betyder aldrig fysisk
sletning: de opretter eller ændrer kun private revisionstilstande. En allerede
publiceret revision forbliver læsbar, indtil en særskilt publiceringsbeslutning
erstatter eller afpublicerer den. Apply ændrer aldrig synligheden af en
tidligere revision.

Fravær i importerede data er aldrig slettebevis. Tvetydig identitet, blandet
ejerskab, uventet consumer, stale attestation, hashdrift eller ukendt
manifestfelt afviser hele batchen før første model-DML.

## Dataejerskab og revisionsmodel

Den private adapter får seks domæneejede V3-revisionsrelationer:

```
private.source_scoped_evidence_v3_chain
  (id, source_id, source_record_id, source_record_key, source_persona_id,
   canonical_person_id, chain_key, created_by_batch)

private.source_scoped_evidence_v3_revision
  (id, chain_id, revision, predecessor_revision_id, fact_id,
   revision_kind, chain_sha256, manifest_semantic_sha256, created_by_batch)

private.source_scoped_evidence_v3_member
  (revision_id, member_kind, member_key, fact_id, assertion_id, citation_id)

private.source_scoped_evidence_v3_publication
  (id, chain_id, revision_id, decision, decision_state_sha256,
   decided_by, decided_at, supersedes_publication_id)

private.source_scoped_evidence_v3_chain_state /
private.source_scoped_evidence_v3_chain_event
  (chain_id, head_revision_id, visible_revision_id, state_version,
   state_sha256, last_event_id) / (id, chain_id, event_type, predecessor_state_sha256,
   after_state_sha256, revision_id, publication_id)
```

`chain_key` er SHA-256 over den canonical JSONB-projektion
`{schema:"source-scoped-evidence-v3-chain-key-v1",source_id,source_record_key,element_id}`.
`source_id` er et JSON-tal, de to øvrige felter er ikke-tomme strings, og
operationerne sorteres efter `element_id` i enhver projektion, der indeholder
flere chain keys.
En chain er én kildepost/fortolkning mod én godkendt kanonisk person. Chainens
alle source-, record-, persona- og personbindinger samt `created_by_batch` er
immutable; `UNIQUE(source_id,chain_key)` forbyder reparenting. En revision er
immutable og nummereres strengt stigende pr. chain med
`UNIQUE(chain_id,revision)`. `predecessor_revision_id` er enten `NULL` for
revision 1 eller den umiddelbart foregående revision i samme chain.
`revision_kind=content` kræver en ikke-null `fact_id`, mens `tombstone` kræver
`fact_id IS NULL`. `member_kind` er kun `fact`, `assertion` eller `citation`.
Den fysiske member-række har tre typed nullable FK'er (`fact_id` mod `fact`,
`assertion_id` mod `assertion`, `citation_id` mod `citation`) med en `CHECK`,
der kræver præcist én ikke-null kolonne og at den matcher `member_kind`.
`UNIQUE(revision_id,member_kind,member_key)` samt én partial unique index for
hver typed FK forhindrer delte eller fejltypede members; en polymorf `db_id`-FK
må ikke foregives at være deklarativt mulig.

Revisioner, members og publication-events opdateres eller slettes aldrig.
En revision er enten `content` med en fuld membermængde eller `tombstone` med
ingen modelmembers; tombstone repræsenterer remove og compensation af create
uden fysisk delete. Publication-events er immutable og har kun beslutningerne
`adopt_baseline`, `publish`, `supersede` eller `withdraw` samt den eksakte,
hashbundne menneskelige beslutningspayload.

Den muterbare chain-state er kun en serverprojektion af den append-only
eventstrøm. Hvert event har et immutable UUID-primary-key `id`; state har
præcist én række pr. chain og `last_event_id` FK til det event, som skabte den.
Den må kun ændres af en secured
append-event-trigger: dens `head_revision_id` og `visible_revision_id` skal
tilhøre samme chain, `visible_revision_id` skal være en content-revision, og
`state_version` skal stige med én. Dens state-hash er nøjagtigt SHA-256 over
den canonical JSONB-projektion
`{schema:"source-scoped-evidence-v3-chain-state-v1",chain_id,head_revision_id,visible_revision_id,state_version,last_event_id}`,
hvor ID'er serialiseres som strings og manglende IDs som JSON `null`.
`after_state_sha256` er denne afledte hash og indgår ikke selv i preimaget.

De eneste chain-events er `source_revision_created`, `eligible`, `published`,
`superseded` og `withdrawn`. Deres transitioner er:

| Event | Krav før | Efter `head` | Efter `visible` |
| --- | --- | --- | --- |
| `source_revision_created` | ny, korrekt nummereret revision med den gamle head som umiddelbar forgænger | ny revision | uændret |
| `eligible` | revisionen er current head | samme revision | uændret |
| `published` | current eligible content-head, ingen visible revision | samme revision | head |
| `superseded` | current eligible content-head og en anden visible content-revision | samme revision | head |
| `withdrawn` | current eligible tombstone-head og en visible revision | samme revision | `NULL` |

En ny `source_revision_created` erstatter altid head-projektionen, så en ældre
draft eller eligible revision aldrig senere kan publiceres. Revisionens
afledte status kommer alene fra denne eventstrøm; den er ikke en opdaterbar
kolonne på revisionen.

En historisk, ubundet kæde kan kun få en første chain/revision via en særskilt,
redaktionel `adopt_baseline`-publiceringsbeslutning. Dens candidate er
read-only mod public modeldata: den måler og mapper en præcis positivt ejet
kæde og opretter ingen facts, assertions eller citations. Først den menneskelige
beslutnings-RPC opretter atomisk binding, `published`-revision og
publication-event, og kun hvis den gamle RLS allerede tillod synlighed. Der er
dermed også en positiv publiceringsbeslutning for en baseline; adoption kan
aldrig gøre skjult data synligt. Uafklaret eller consumer-bundet baseline kan
ikke adopteres.

## Persistens- og migrationsdisposition

V3 opretter egne append-only `private.source_scoped_replace_v3_attestation`,
`private.source_scoped_replace_v3_authorization`,
`private.source_scoped_replace_v3_authorization_attestation`,
`private.source_scoped_replace_v3_batch`, `private.source_scoped_replace_v3_event`
og `private.source_scoped_replace_v3_manifest_artifact` ud over de seks
revisions-/visibility-relationer ovenfor. V1-tabellerne
`private.source_scoped_replace_authorization`, `_batch` og `_event` forbliver
urørte, utilgængelige for V3 og må hverken omdøbes, genbruges eller få ny
semantik. V3-migrationen skal ved første apply oprette manglende V3-objekter.
Ved rerun accepteres et eksisterende V3-objekt kun, når dens definitioner,
constraints, triggers, ACL'er og en versioneret migrationsreceipt-hash matcher
eksakt; enhver anden V3-navnekollision afvises. Den må ikke lave en implicit
disposition af v1 eller C3. Autorisation og batch har kun dokumenterede single-use/terminal-
transitioner; attestationer, manifest-artefakter, revisioner, members,
publicationer og events kan aldrig opdateres eller slettes.

V1's tre offentlige writer-RPC'er pensioneres atomisk i både fresh schema og
migration: `public.red_authorize_source_scoped_replace(text,text,uuid,uuid,jsonb,text,text,timestamptz)`,
`public.red_apply_source_scoped_replace(uuid,jsonb)` og
`public.red_verify_source_scoped_replace(uuid)`. `EXECUTE` revokes fra
`PUBLIC`, `anon`, `authenticated` og `service_role`; deres erstattede bodies
har ingen DML og afviser altid med `SOURCE_SCOPED_REPLACE_V1_RETIRED`.
V1-ledgerens eksisterende rows bevares kun som historik, får append-/mutation-
guards der afviser INSERT/UPDATE/DELETE, og kan ikke være input til V3. Kun de
versionsnavngivne V3-RPC'er kan få de mindst mulige `authenticated`-grants.
Schema- og migrationsverifikation skal både `has_function_privilege`-afvise V1
for alle fire roller og hash-/inspektionsteste de tre pensionerede function

### Task 4A-v4 receipt-transition

Task 4D's autorisationsattestation, profile-/element-scope-hashes og
identity-default-paritet er en udvidelse af den oprindelige Task 4A-fysiske
V3-kontrakt. De installeres derfor gennem en eksplicit
`source-scoped-evidence-v3-task4a-v4`-transition; v1--v3 receipts ændres aldrig
eller overskrives. Før nogen v4-DDL udføres, skal migreringen enten verificere
en eksisterende v4-receipt mod den *allerede installerede* v4-kontrakt, eller,
hvis v4 mangler, afvise enhver v4-tabel, -kolonne, -constraint, -trigger,
funktion eller ACL som et unreceipted del-footprint. Første v4-apply kræver
desuden, at den seneste accepterede Task 4A-forgængerreceipt og, når den findes,
Task 4C-v7-receipt stadig matcher deres respektive historiske projektioner.

Når den rene forløber er verificeret, opretter v4 den specificerede
`private.source_scoped_replace_v3_authorization_attestation`-relation og de
specificerede attestation-/authorization-kolonner. V4-kontrakt-hashen binder
alle V3-relationers stabile definitioner, constraints, indexes, triggers, RLS
og ACL-projektioner, samt `fact.id`/`citation.id` identity-sekvensernes
default, ownership og floor. Den binder bevidst ikke definitionen af den endnu
ufærdige Task 4D-kernel. Først derefter indsættes den append-only v4-receipt.

Task 4D opretter efterfølgende sin egen `source-scoped-evidence-v3-task4d-v1`
kernelreceipt over canonical-hash-helperne og de færdige source
authorize/apply/verify-RPC'er, inklusive deres private ACL'er. Receipt'en
valideres før en senere kernelmutation. `db-rls.sql` installerer derefter de
eneste public V3 `authenticated`-EXECUTE-grants og opretter den efterfølgende
`source-scoped-evidence-v3-task4d-v2` RLS-receipt, der binder de færdige
function-ACL'er. Migrationssporet efterlader dem alle revoked, indtil den
RLS-bundne slutkontrol har kørt.
bodies, så en gammel muterende route ikke kan genopstå ved migration.

Den lukkede V3-RPC-allowlist er alene:

```
public.red_authorize_source_scoped_replace_v3(
  text,text,uuid,uuid,uuid,jsonb,text,text,text,text,timestamptz) returns uuid
public.red_apply_source_scoped_replace_v3(uuid,jsonb) returns jsonb
public.red_verify_source_scoped_replace_v3(uuid) returns jsonb
public.red_authorize_source_scoped_evidence_publication_v3(
  uuid,uuid,uuid,text,jsonb,uuid,timestamptz) returns uuid
public.red_publish_source_scoped_evidence_revision_v3(uuid,jsonb) returns jsonb
public.red_authorize_source_scoped_evidence_adoption_v3(
  uuid,jsonb,text,jsonb,uuid,timestamptz) returns uuid
public.red_adopt_source_scoped_evidence_v3(uuid,jsonb,jsonb) returns jsonb
```

Source-authorisationens signatur er præcist
`red_authorize_source_scoped_replace_v3(database_name text, system_identifier text, deployment_id uuid, actor_id uuid, nonce uuid, manifest jsonb, manifest_semantic_sha256 text, dry_run_semantic_sha256 text, ownership_semantic_sha256 text, artifact_sha256 text, expires_at timestamptz) -> uuid`.
Den kræver `actor_id=auth.uid()` og `current_rolle()='redaktion'` før
ledger-DML; `deployment_id`, `actor_id` og `nonce` er dermed de tre
UUID-argumenter i denne rækkefølge. Apply kræver den samme actor og rolle som
autorisationen. Verify tager authorization-ID'et og er læsbart for enhver
aktuel `redaktion`-bruger, men returnerer aldrig raw input eller private
artefakter. Kun `authenticated` får de eksplicitte EXECUTE-grants på de syv
RPC'er; `PUBLIC`, `anon` og `service_role` får ingen V3 RPC- eller private
tabelgrants.

I rækkefølge er de ikke-selvindlysende argumenter source/publication/adoption-
authorizationernes immutable deployment-ID, database-/systemidentitet,
source-manifestets semantic/dry-run/ownership/artifact-hashes og
publicationens/adoptionens expected-state-hash. Hver authorization persisterer
både deployment-ID og deployment-hash og afviser, hvis artifact-, inventory-
eller database-bindingen ikke matcher deployment-rækken.
Alle syv er `SECURITY DEFINER`, kontrollerer `auth.uid()` og de relevante
redaktionsroller, og får kun de eksplicit dokumenterede grants. Ingen
uversioneret source-scoped RPC må være en V3-alias eller have V3-semantik.

`schema.sql` er den deklarative complete-build-kilde. `db-migrations.sql` skal
have samme additive tabeller, constraints, triggers, functions, identity-
defaults, revokes og RLS-paritet i en faktisk migrationsblok — ikke blot en
marker eller en afhængighed af schema-kørsel. Verifikationen sammenligner
`pg_get_constraintdef`, identity-sekvensers floor/ownership, triggernavne,
function-signaturer og privileges mellem fresh schema og migreret database.

## Synlighed og publiceringsbeslutning

Visibility-grænsen er ikke en direkte kaldbar boolsk helper. PostgreSQL kræver
`EXECUTE` for enhver funktion, som et view bruger; en privat no-grant helper
kan derfor ikke være implementationen bag et public view. Bindingstesten
udtrykkes i stedet relationelt i tre DB-ejede `SECURITY BARRIER`-views:

```
public.source_scoped_evidence_visible_fact_ids
public.source_scoped_evidence_visible_assertion_ids
public.source_scoped_evidence_visible_citation_ids
```

Views bruger deres normale DB-ejerprivilegier (ikke `security_invoker`), men
udtrykker den eksisterende public-gate eksplicit i hvert view, så ejerens
RLS-bypass aldrig kan udvide synligheden. Hvert view udsender kun en
ID-projektion for rows, som allerede passerer den
eksisterende anonyme/autentificerede public-gate (herunder den relevante
`person_offentlig`-/target-gate) og som enten er historisk ubundne eller er
members af kædens aktuelle publicerede revision. Views udsender aldrig draft,
eligible, withdrawn, redaktionelt skjulte eller blot ikke-eksisterende IDs og
eksponerer ingen revision-, chain- eller decision-kolonner. `anon` og
`authenticated` kan kun få `SELECT` på disse ID-projektioner, aldrig adgang
til `private`-relationer eller en parameteriseret private-state-funktion;
`PUBLIC` og `service_role` får ingen sådan grant.

Fact-, assertion- og citation-RLS skal kræve både deres eksisterende
person/target-gate og `EXISTS` i det tilsvarende visibility-index-view. En
direkte forespørgsel på et skjult eller ikke-eksisterende ID giver dermed i
begge tilfælde ingen view-række og er ikke en private-state-oracle. Views,
RPC'er og `SECURITY DEFINER`-funktioner, der læser disse tabeller, skal
kortlægges; redaktionelle bypasses skal anvende en eksplicit, testet undtagelse
og må ikke gøre en ikke-redaktionel read path synlig. `note` og `relation` må
ikke antages at arve synlighed: deres effektive read paths indgår som egne
inventory- og RLS-tests. Source-writeren opretter ingen af dem.

`red_publish_source_scoped_evidence_revision_v3` kræver redaktionsrolle, den
aktuelle chain-state-hash, source-record/persona/identity-binding,
databaseidentitet og menneskelig beslutningspayload. Den accepterer kun
chainens aktuelle `eligible` head og bruger compare-and-swap på state-version.
Den publicerer en ny revision kun hvis chainen ikke har en anden public
revision, eller hvis den aktive publice revision ikke har nogen beskyttet
consumer. Ved replace publiceres den nye og den gamle supersedes atomisk; ved
en publicerbar tombstone skifter den aktive revision til `withdrawn`. Begge er
append-only publiceringsbeslutninger. En `note`,
`relation`, `haendelse`, `story`, promotion-link eller anden katalogkendt
consumer på den gamle revision gør beslutningen NO-GO frem for at skjule en
uventet afhængighed.

Publicationens menneskelige beslutningspayload indeholder altid det autoriserede
`deployment_id` og `deployment_sha256`; authorizationen sammenligner begge mod
den immutable deployment-række før den måler inventory eller ændrer state.

Publiceringsvejen er to-trins single-use:
`red_authorize_source_scoped_evidence_publication_v3(chain_id,revision_id,
deployment_id,expected_state_sha256,decision_payload,nonce,expires_at)` efterfulgt af
`red_publish_source_scoped_evidence_revision_v3(authorization_id,decision)`. Den
første RPC måler candidate, inventory og state; den anden låser samme chain,
genberegner alle bindings og forbruger autorisationen. Begge returnerer eller
persisterer den lukkede promotion-receipt med decision-, state- og
databaseidentitet.

## Lukket reader-, consumer- og writer-inventory

`private.source_scoped_evidence_contract_inventory` er et versioneret,
append-only contract snapshot med `schema_contract_version`,
`catalog_definition_sha256`, `reader_probe_source_sha256`,
`consumer_probe_source_sha256`, `writer_probe_source_sha256` og
`inventory_result_sha256`. De tre prober er private `SECURITY DEFINER`-funktioner
uden application-grants; deres source-hashes er SHA-256 over deres fulde
`pg_get_functiondef`-definition. `catalog_definition_sha256` dækker alle FK'er
til fact/assertion/citation med tabel, kolonnepar, update/delete-action,
deferrability og validation-status.

Hvert V3-authorization peger på en immutable
`private.source_scoped_evidence_v3_deployment`-række med UUID, inventory-FK,
`repository_writer_artifact_sha256`, `schema_contract_version`, database-
identitet, registreringsactor/-tid og en canonical deployment-hash. Der findes
ingen muterbar "current" deployment: en ny kode-/inventory-version opretter en
ny række, og authorize/apply/publication genberegner databaseinventaret samt
kræver den eksakte, persisterede deployment-hash. En gateway/CI-job må alene
oprette deployment-rækken efter at have målt Git-artifact-snapshot'et; DB-RPC'er
læser aldrig worktree eller Git.

Den eneste registreringsvej er den private, no-application-grant
`private.register_source_scoped_evidence_v3_deployment(uuid,text,text,text,text,text,uuid) -> uuid`.
Den modtager inventory-ID, HEAD-tree provenance, artifact-hash,
schema-contract-version, database-/systemidentitet og registreringsactor;
den måler databaseidentiteten igen, sætter `registered_at` på serveren og
persisterer den canonical deployment-projektion
`{schema:"source-scoped-evidence-v3-deployment-v1",inventory_id,repository_tree_id,repository_writer_artifact_sha256,schema_contract_version,database_name,system_identifier,registered_by,registered_at}`.
Kun den dedikerede databasegruppe `daa_source_scoped_evidence_deployer` får
`EXECUTE`; den har ingen direkte tabel-DML. `PUBLIC`, `anon`, `authenticated`,
`service_role` og øvrige application-roller får hverken execute eller private
tabelprivilegier. Direkte INSERT og forged deployment-/inventory-hash afvises.

`inventory_result_sha256` er hash over den frisk genererede, stable sorterede
fulde discovery-mængde
`{kind,object_schema,object_name,object_oid,definition_sha256,dependency_edges,member_kind,guard}`.
`definition_sha256` kommer for hver view/funktion fra `pg_get_viewdef` eller
`pg_get_functiondef`; `dependency_edges` kommer fra den komplette relevante
`pg_depend`-closure. En entrys `guard` angiver den observerede RLS-, view- eller
redaktionelle undtagelse. Hashen er resultatet, ikke blot probernes kode, og
bindes i profile, autorisation og receipt.

Consumer-proben skal mindst kontrollere `conclusion`, `note`, `relation`,
`haendelse.fact_id`, `story.fact_id`, interpretation-promotion og alle
polymorfe `target_type/target_id`, `subjekt_type/subjekt_id` og
`objekt_type/objekt_id`-par, der discovery-findes i `pg_catalog`. Reader-proben
skal inventere alle public views/RPC'er og `SECURITY DEFINER`-funktioner med
direkte eller transitiv læsning af fact/assertion/citation og klassificere dem
som RLS-gated eller redaktionelt undtagne. Writer-inventory omfatter alle
create/edit/delete/undo-veje for samme tre tabeller. Den må ikke påstå, at
`pg_depend` alene finder PL/pgSQL- eller dynamic-SQL-afhængigheder: alle
inventerede databasefunktioners fulde definition indgår derfor direkte i
resultathashen, og enhver dynamic-SQL-funktion skal enten have en eksplicit,
hashbundet model-target-allowlist eller afvises som inventory-drift.

Et separat, tracked repository-artifact-snapshot dækker alle R-, Python- og
SQL-entrypoints, der kan nå model-DML: hver entry er
`{path,blob_sha256,language,writer_class,allowed_db_api,model_targets}` og har
en exact allowlist. Gateway/CI måler kun et committed tree: `git ls-tree -r -z
HEAD` bestemmer scope, `git cat-file blob HEAD:<path>` leverer de eksakte
blob-bytes, og `blob_sha256` er SHA-256 over disse bytes — aldrig Git's native
object-id (som kan være SHA-1). Den native `HEAD` tree-id gemmes kun som
reproducerbar provenance ved siden af artifact-hashen. Index- og worktree-
ændringer, herunder beskyttede untracked prototyper, indgår ikke i deployment-
snapshot'et. Et nyt eller ændret committed `dbExecute`, `dbAppendTable`, SQL
`INSERT`/`UPDATE`/`DELETE`, `COPY`, dynamic SQL eller ny databasefunktion mod
fact/assertion/citation gør preflight NO-GO, indtil entryen er eksplicit
klassificeret. Tests, fixtures og disposable-only SQL registreres særskilt og
kan aldrig blive produktionswriter-allowlist.

Databasegrænsen gør denne artifactkontrol håndhævelig: application-,
extract- og `service_role`-roller har ingen direkte INSERT/UPDATE/DELETE på
fact/assertion/citation; de må kun kalde en inventory-allowlistet,
`SECURITY DEFINER`-writer. En direkte eller uinventeret ekstern DML-vej
afvises derfor af databaseprivilegier før write. De eksisterende bound-member
triggers afviser stadig edit/delete/undo af V3-bound rows, og V3-kernens egne
new-row-inserts skal bindes til dens aktuelle autorisation og expected typed
member før receipt. DB-ejerens administrative nøgle er uden for
application-trust-boundary og må ikke bruges af repository-writers.

CI og den lokale, repository-bundne gateway genkører både database-discovery og
repository-artifact-snapshot før deployment/autorisation. Deployment registrerer
den godkendte artifact-hash i den private V3 contract-record. DB-RPC'erne har
aldrig filesystem-/Git-adgang: apply og publication genvaliderer kun live
databaseinventory samt den persisterede deployment- og authorization-bundne
artifact-hash. Alle tre lag sammenligner de komplette entry-mængder med det
autoriserede snapshot;
enhver ny FK, polymorf kolonnepar, reader eller writer — også en ny writer bag
en ellers uændret probe — er `SOURCE_SCOPED_EVIDENCE_INVENTORY_DRIFT` før DML.
En guard-trigger afviser
update/delete af en adapterbundet member gennem enhver generisk writer. En
anden guard-trigger afviser nye consumers af ikke-publice revisionsmembers og
nye consumers af en public member, når operationen ville gøre en senere
supersede/withdraw usikker. Bound members er således uigenkaldeligt
append-only, mens redaktionelle readers fortsat kan se dem under deres
eksplicitte undtagelse.

## Manifest, provenance og autorisation

Det muterende manifest er `source-scoped-replace-v3`. Det består af en lukket
semantic JSONB-payload og en separat raw input-identitet:

```
{schema, source_id, record_keys, input_sha256, manifest_semantic_sha256,
 dry_run_semantic_sha256, ownership_semantic_sha256, expected_counts,
 policy_decisions, narrative_operations, source_operations}
```

`manifest_semantic_sha256` er SHA-256 over den canonical JSONB-projektion med
schema `source-scoped-replace-v3-semantic-v1` og præcist disse felter:

```
{schema,source_id,record_keys,input_sha256,dry_run_semantic_sha256,
 ownership_semantic_sha256,expected_counts,policy_decisions,
 narrative_operations,source_operations}
```

Objektkeys og alle arrays har en specificeret stabil sortering, tal er JSON-tal,
og UUID-/ID-værdier er JSON-strings. Transportmanifestets afledte
`manifest_semantic_sha256`-felt indgår udtrykkeligt ikke i hash-preimaget; der
er ingen selvreference. Den samme projektion bruges ved preflight,
autorisation, apply, receipt og exact replay. Raw manifesttekst og inputbytes
må gemmes privat, men er ikke database-parse-trust-root; compilerens
duplicate-key/JCS-kontrol er et obligatorisk, testet klientværn. Databasen
foregiver således ikke at have bevaret duplicate keys eller klientens rå
byteorden. `policy_decisions` er i semantic-v1 præcist den tomme liste `[]`;
nye policybeslutninger kræver en ny versionsnavngivet manifestgrammatik.
`expected_counts` er præcist objektet
`{source_operations,content_revisions,tombstone_revisions,facts,assertions,citations,narrative_operations}`
med ikke-negative JSON-heltal. Compileren udleder hver værdi fra de deklarerede
operationer og desired chains; authorize og apply genudleder dem og kræver
eksakt lighed før ledger- eller model-DML.

Alle nedenstående hashfelter er SHA-256 over canonical JSONB med objektkeys i
lexikografisk orden, arrays i den angivne sortering, bigint/UUID som strings i
serverprojektioner og uden det afledte hashfelt selv. Kernelens måling er
autoritativ; klientens hash er kun en forventning, som skal matche før DML:

* `prestate_sha256`: `{schema:"source-scoped-evidence-v3-prestate-v1",chain_key,head_revision_id,head_state_sha256,members}`, hvor `members` er den sorterede `{member_kind,member_key,db_id,row_sha256}`-mængde fra den aktuelle head.
* `preservation_set_sha256`: `{schema:"source-scoped-evidence-v3-preservation-v1",chain_key,required_members}`, med samme member-form og sortering.
* `ownership_sha256`: `{schema:"source-scoped-evidence-v3-ownership-v1",source_id,chain_key,owned_members,preservation_set,consumer_bindings}`, hvor bindings sorteres efter `{consumer_kind,consumer_id,member_kind,member_key}`.
* `expected_after_sha256`: `{schema:"source-scoped-evidence-v3-after-v1",chain_key,revision_kind,desired_chain_sha256,member_keys}`; `member_keys` er den sorterede V3-member-key-liste og er tom for tombstone.
* `dry_run_semantic_sha256` og `ownership_semantic_sha256`: henholdsvis de versionerede, sorterede `{schema,source_id,record_keys,operations,expected_counts}`-projektioner `source-scoped-evidence-v3-dry-run-v1` og `source-scoped-evidence-v3-ownership-set-v1`, hvor `operations` sorteres efter `element_id` og hver række er præcist `{element_id,prestate_sha256,ownership_sha256,preservation_set_sha256,expected_after_sha256}`.

Authorisationen persisterer de servermålte dry-run-, ownership-, attestation-,
profile-, element-scope- og deployment-artifacts som separate immutable
artefakter med deres versionerede preimages; den accepterer aldrig en rå
klienttekst som hash-trust-root. Artifact-kind er præcist én af `manifest`,
`dry_run`, `ownership`, `attestation`, `profile`, `element_scope` eller
`writer_snapshot`; hver autorisation har præcist én række per påkrævet kind.

Gatewayens klientpreflight er `BEGIN READ ONLY` og begrænser sig til den
lukkede manifest-/artifact-validering samt publict læsbare checks. Den får
aldrig `private`-schema- eller tabelprivilegier og kalder ingen ny preflight-
RPC. De private deployment-, inventory-, identity- og ownership-bindinger
genmåles udelukkende i den eksisterende V3-authorize-kernel og igen under
apply-låsene. Dermed bevares både den lukkede syv-RPC-allowlist og den
mindst-privilegerede gatewayrolle.

Hver source-operation angiver `element_id`, `operation`, `chain_key`,
`source_record_key`, `source_persona_id`, `identity_event_id`, `person_id`,
`prestate_sha256`, `desired_chain`, `desired_chain_sha256`,
`ownership_sha256`, `preservation_set_sha256`, `expected_after_sha256`,
`previous_manifest_semantic_sha256`, `previous_batch_id` og
`previous_manifest_artifact_sha256`. De tre `previous_*`-felter er alle JSON
`null` for create/replace/remove og alle ikke-null for compensation; de tre
værdier skal referere samme tidligere, committed V3-batch og dens private
manifest-artefakt. Operation er kun `create_chain`, `replace_chain`,
`remove_owned_chain` eller `compensate_chain`.
`adopt_baseline` er det særskilte, read-only candidate/publiceringsflow ovenfor
og er ikke en muterende source-operation. Remove opretter ingen modelrækker og
kan kun skabe en withdrawal-kandidat; den ændrer ikke tidligere synlighed.

`desired_chain` er den eneste muterende inputkilde til en V3 content-revision;
authorize og apply læser aldrig modelindhold fra en hash, raw input, V1 eller en
anden skjult kanal. Den har præcist keys `schema` og `members` og er den
canoniske JSONB-projektion

```
{schema:"source-scoped-evidence-v3-desired-chain-v1",members}
```

og `desired_chain_sha256` er SHA-256 over netop denne projektion. `members` er
en lukket liste. Compileren normaliserer den stabilt efter `member_kind`-
rækkefølgen fact, assertion, citation og derefter dens numeriske
`member_key`-suffix, før den beregner hash; authorize og apply kræver den
normaliserede array-orden. En content-kæde har præcist én fact med
`member_key="fact:1"`, mindst én assertion
med fortløbende `assertion:1`, `assertion:2`, ... og mindst én citation med
fortløbende `citation:1`, `citation:2`, .... Hver assertion skal refereres af
mindst én citation; citations er kædens blade. Nummeret er et positivt decimalt
heltal uden fortegn eller foranstillede nuller; listen må hverken have huller
eller duplikater.

Fact-memberen er nøjagtigt

```
{member_kind:"fact",member_key:"fact:1",subjekt_type:"person",subjekt_id,
 faktatype,sted_id}
```

hvor `subjekt_id` er JSON-tal og lig operationens `person_id`, `faktatype` er
en ikke-tom string, og `sted_id` er JSON-tal eller `null`. Assertion-memberen
er nøjagtigt

```
{member_kind:"assertion",member_key,target_type:"fact",target_member_key:"fact:1",
 vaerdi_tekst,objekt_type,objekt_id,date_min,date_max,date_qualifier,
 date_certainty,date_raw,calendar,uforanderlig}
```

Hvor `target_member_key` altid er `fact:1`, de nullable tekst-/dato-felter er
enten string eller `null`, `objekt_id` er JSON-tal eller `null`, og
`uforanderlig` er JSON boolean. `objekt_type` og `objekt_id` er enten begge
`null` eller begge ikke-null; `sted_id` skal referere en eksisterende place før
DML. Ikke-null `date_min` og `date_max` skal være ISO-8601-datoer med
`date_min <= date_max`; `date_certainty`, `date_qualifier` og `calendar` skal
opfylde de samme enum-/check-regler som måltabellen. Citation-memberen er nøjagtigt

```
{member_kind:"citation",member_key,assertion_member_key,source_id,side,
 citat_tekst,citat_dato,kvalitet}
```

hvor `assertion_member_key` refererer én deklareret assertion, `source_id` er
JSON-tal og lig manifestets topniveau-`source_id`, og de øvrige felter er string
eller `null`. Alle nullable felter skal være til stede som JSON `null`; ukendte
felter, implicitte standarder, caller-ID'er og udeklarerede topologier afvises.
For `remove_owned_chain` skal `desired_chain` være den samme schema-projektion
med tom `members`-liste og `desired_chain_sha256` dens hash. Create og replace
og compensate afviser tom eller ufuldstændig kæde, og hver payload/hash-forskel
afviser før ledger- eller model-DML.

Adoption-candidaten er nøjagtigt
`{schema,chain_key,source_id,source_record_id,source_record_key,
source_persona_id,identity_event_id,canonical_person_id,members,
member_state_sha256,legacy_visibility_sha256}`. `members` er den stable,
sorterede `{member_kind,db_id,row_sha256}`-mængde; `member_state_sha256` er
dens canonical JSONB-hash. `legacy_visibility_sha256` hasher den servermålte
rolleprojektion `{anon,authenticated}` for præcis fact/assertion/citation-
kæden ved eksplicit evaluering af de eksisterende base-RLS predicates, ikke ved
at lade en `SECURITY DEFINER`-funktion bypass'e RLS. Adoption er kun mulig, når
begge projections er helt positive. Den menneskelige beslutning er nøjagtigt
`{schema:"source-scoped-evidence-v3-adoption-decision-v1",chain_key,candidate_sha256,deployment_id,deployment_sha256,expected_state_sha256,decision:"adopt_baseline",rationale,policy_basis_sha256}`;
dens canonical hash er separat fra candidate-hashen. Både
`red_authorize_source_scoped_evidence_adoption_v3` og
`red_adopt_source_scoped_evidence_v3` kræver `current_rolle()='redaktion'` og
bliver bundet til candidate-hash, decision-hash/payload, state-hash, database,
actor, nonce og expiry. Apply gemmer samme decision-payload/hash i den immutable
publication-række og receipt'en, genmåler alt under samme locks og returnerer
en standard promotion-receipt; enhver forskel er
`SOURCE_SCOPED_EVIDENCE_ADOPTION_STALE`.

En narrative-operation er én af to lukkede former. Upsert er nøjagtigt
`{operation:"upsert",element_id,person_id,source_id,record_key,text,text_sha256,privat,expected_state_sha256}`;
`text_sha256` er SHA-256 over UTF-8-teksten, `privat` er JSON boolean, og
`expected_state_sha256` er #152-kernens record-bundne state-hash. Reverse er
nøjagtigt `{operation:"reverse",element_id,person_id,source_id,record_key,original_event_id,reversal_state_sha256}`.
Begge former er kun gyldige, når deres `element_id` findes i én source-operation
med samme source-record/persona/person-binding; reverse skal høre til en
`compensate_chain` og binde præcist sidste ikke-reverserede #152-event.
Terminal receipt indeholder kun dens keys, hash og kernel-event-ID.

En append-only record-attestation indeholder den sorterede, præcist udtømmende
binding per operation:

```
{element_id, source_id, source_record_id, source_record_key,
 source_persona_id, identity_event_id, identity_event_version,
 canonical_person_id, review_basis_sha256}
```

Attestation-rækken indeholder også `element_id`, `identity_event_id`,
`identity_event_version` og `review_basis_sha256`; dens canonical hash er over
den viste projektion med schema
`source-scoped-evidence-v3-record-attestation-v1`. Den immutable
`authorization_attestation`-linkrække har præcist
`{authorization_id,element_id,attestation_id,attestation_sha256}` og unik
`(authorization_id,element_id)`. Autorisationen gemmer desuden hashene over
den sorterede attestation-linkmængde, den validerede writer-profile og den
sorterede element-scope-projektion. Preflight låser og genvaliderer
source-record, persona, identity-event/-state og person imod hver binding.
`record_key` bruges aldrig som personidentitet.
Autorisationen er single-use og binder deployment-ID/-hash, semantic manifest-,
dry-run-, ownership-, attestation-, profile-, deployment-artifact- og database-
hash, actor, nonce, udløb, element-scope og ved compensation
`previous_manifest_semantic_sha256`.

## Apply, locks og compensation

Den fælles låseorden er bindende:

1. shared `daa-narrative-record-contract` gate;
2. source-scope advisory lock;
3. source records i stabil UUID-orden;
4. `LOCK TABLE public.change_set IN ACCESS EXCLUSIVE MODE`;
5. personer i stigende ID-orden;
6. narrative bindings/events/narratives, derefter anchors, occurrences og
   renditions i #152-kernens dokumenterede ordre;
7. source personas, placements, identity-state og source-record revisions i
   samme #152-orden;
8. chains/revisions/publiceringsbindinger i stable key-orden;
9. facts, assertions og citations i stigende ID-orden;
10. authorisation, batch og receipt-ledger.

Source writeren prelocker alle resurser i punkt 3–7 for hver narrativeffekt
før evidence-DML, så det efterfølgende #152-kald ikke kan tage en ny ressource
i omvendt orden. Promotion og publication skal bruge det samme låsekort; en
ukendt eller ny shared resource er `SOURCE_SCOPED_REPLACE_LOCK_INVENTORY_DRIFT`.

Apply gentager hele preflight i write-transaktionen. Før fact-DML er
`app.change_set_id` tomt. Nye model-ID'er kommer alene fra tabellernes
migrationsdefinerede `DEFAULT` identity-sekvenser; caller-ID'er, `max(id)+1` og
særskilte allokatorer er forbudt. Apply opretter kun nye modelrows og private
bindings, aldrig model-update/delete. Højst én #152 narrativemutation køres
efter fact-DML som sidste model-DML: upsert bruger
`private.mutate_person_narrative_record('upsert',...)` og skal returnere
`draft_created` eller `draft_updated`; reverse bruger alene
`red_fortryd_person_narrative_publication_event` med den bundne event/state.
Efter den er kun ledger, postverify og receipt tilladt.

Compensation er et nyt autoriseret v3-manifest. Hver `compensate_chain` refererer
den tidligere batch, private manifest-artefakt og
`previous_manifest_semantic_sha256`, kræver en ny current-state-attestation og
opretter en ny immutable content- eller tombstone-revision med forgængerens
verified prestate som den eneste tilladte desired state. Den genbruger aldrig
model-ID'er eller en gammel revision. Hvis forgængeren er publiceret, ændrer
den nye revision først synlighed efter en ny publiceringsbeslutning.

Kompensation af en narrativeffekt bruger den eksklusive #152-
`red_fortryd_person_narrative_publication_event`-vej mod det præcise,
seneste ikke-reverserede event og dens friske eftertilstandshash. V3-
kompensationsautorisationen binder både det oprindelige narrative event-ID og
den separate #152 reversal-state-hash; hvis #152 afviser reversal, afviser hele
kompensationsbatchen før nogen evidensrevision oprettes. V3 kalder aldrig en
generisk narrative undo eller en `discard`-transition som genvej.

## Receipt, verification og testkrav

Profilen bruger fortsat `execution_kind=apply`,
`authorization_mode=single_use_database_authorization` og
`reversal_mode=compensating`. Receipt'en følger det fælles lukkede sæt:
profile og hash, mode, terminal status, input- og databaseidentity,
authorization identity, operation ID, observed counts og verified state.
Apply-argumentet er præcist det canonical transportmanifest, som authorize
lagrede; kernel genberegner dets semantic-hash og kræver canonical JSONB-lighed
med authorizationens manifest. En single-use replay med samme manifest returnerer
kun den eksisterende immutable receipt uden DML; enhver anden apply-payload eller
hash afvises. Apply returnerer præcist `{replayed,receipt}`, hvor `replayed` er
JSON boolean. Verify-argumentet er authorization-ID.

Apply-receipten er nøjagtigt
`{schema:"source-scoped-evidence-v3-apply-receipt-v1",authorization_id,batch_id,terminal_status,manifest_semantic_sha256,observed_counts,verified_state}`;
`terminal_status` er altid `applied`, og `observed_counts` har samme
eksakte keys som `expected_counts`. `verified_state` er den sorterede canonical
projektion `{schema:"source-scoped-evidence-v3-verified-state-v1",source_operations,narrative_operations}`;
source-operationerne indeholder `element_id`, `chain_key`, `revision_id`,
`revision_kind`, `member_mappings` og `after_state_sha256`, og narrative-
operationerne indeholder `element_id`, `event_id` og `event_state_sha256`.
`receipt_sha256` hasher netop receipt-objektet uden sig selv. Senere legitim
publication verificeres i den separate publication/adoption-receipt og dens egen
current-state-hash. V3-verifieren returnerer præcist
`{receipt,apply_state,publication_state}`, hvor `apply_state` er receiptens immutable
`verified_state`, og `publication_state` er den sorterede
`{schema:"source-scoped-evidence-v3-publication-state-v1",chains}`-projektion
med `{chain_key,head_revision_id,visible_revision_id,state_sha256}` per chain.
Den fælles `wb_validate_current_state` sammenligner kun den historisk
uforanderlige apply-state med apply-receipt'en. En publication-overgang er
derfor hverken falsk receipt-drift eller skjult undertrykkelse af ægte
apply-drift.

Source replace beholder den fælles profil med `execution_kind=apply`,
`authorization_mode=single_use_database_authorization` og
`reversal_mode=compensating`. Adoption og publication bruger særskilte,
adapterejede profiler med `execution_kind=promotion`,
`authorization_mode=single_use_database_authorization` og
`reversal_mode=not_supported`; de passer dermed den eksisterende fælles
profile-validator uden en ny execution-kind.

`red_verify_source_scoped_replace_v3` returnerer både historisk receipt og frisk
current state. Postverify bruger de tre policy-safe visibility-index-views;
receipt kan ikke blive grøn, hvis en draft-revision er læsbar for `anon` eller
almindelig `authenticated`.

En frisk disposable database skal mindst bevise:

1. draft, eligible, superseded og withdrawn synlighed for fact, assertion,
   citation, note-/relation-afledte reads og alle relevante public views/RPC'er,
   inklusive at der ikke findes en kaldbar parameteriseret private-state-oracle,
   og at hvert visibility-index-view
   højst projicerer de ID'er, hvis eksisterende public-gate allerede er sand;
2. publicering kun med frisk state-hash og redaktionel beslutning, atomisk
   supersede/withdrawal og afvisning ved consumer eller policy-drift;
3. source replace/adoption/remove/compensation med positive ownership-,
   identity-, preservation- og current-state-attestationer, immutable members,
   stale-head-afvisning og tombstone efter remove/compensation af create;
4. semantic-hash-, database-, actor-, nonce-, expiry- og scope-drift før DML,
   exact replay samt forkastelse af raw-byte-påstand som database-trust-root;
5. #152-kompatibel låseorden og to-session races mellem source writer,
   narrative writer, publicering og promotion uden deadlock eller
   synlighedsbrud;
6. schema/migration identity-paritet, RLS/ACL-denial og ingen adgang til
   private artefakter eller bindings for `anon`, almindelig `authenticated`
   og ikke-redaktionelle roller; en direkte parameteriseret private-state-oracle
   findes ikke, mens de begrænsede ID-views verificeres mod
   den eksisterende public-gate.
7. inventory/probe-drift ved ny FK, reader, databasewriter, repository-writer,
   dynamic-SQL writer og polymorf consumer samt guard-afvisning af alle
   generiske edit/delete/undo-veje for bound members og ACL-afvisning af rå
   ekstern model-DML.

## Ikke-mål

Denne specifikation backfiller ikke historiske facts, ændrer ikke globalt
offentlighedsniveau for ubundne rows, implementerer ikke en ny generisk journal
og åbner ikke 2018-20 eller produktion. Adoptering er per positivt bevist kæde,
aldrig bulk-migrering. Task 5 forbliver lukket, til source writer, receipt,
visibility og conformance er implementeret og verificeret.
