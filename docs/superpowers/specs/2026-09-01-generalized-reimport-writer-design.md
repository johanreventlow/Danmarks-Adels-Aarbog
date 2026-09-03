# #153: Generaliseret genimport-writer — design

**Status:** Godkendt af projektejer 2026-09-01 efter Codex-selvreview og
uafhængigt, read-only Sol-review.
**Roadmapmål:** #153, "Permanente writer-/batchmekanismer generaliseres".
**Myndighed:** #153 samt `docs/evidensbaseret-genimport/{vision,roadmap,teknisk-maalarkitektur,status}.md`. Levende schema og kode er teknisk source of truth.

## 1. Formål og sporbarhed til missionen

1939-writeren er i dag en permanent, editionsnavngiven databaseoverflade:
`private.reimport_1939_{authorization,write_batch,write_event,name_completion_result}`
og `red_*_1939_v50_*`. Den kan derfor ikke bruges af den næste årbog uden at
købe endnu en permanent parallel arkitektur. Det bryder visionens krav om en
fælles motor og en lille udgaveprofil.

| Krav fra #153 | Denne leverance | Færdigbevis |
| --- | --- | --- |
| Generalisér `reimport_1939_*` | Generiske primære tabeller og helpers uden editionsnavn | Frisk schema og migrationsvej har kun generiske primærer |
| Generalisér hele aktive `red_*_1939_v50_*`-writerflade | Generiske authorize/begin/apply/finalize/reversal/cutover/name-completion RPC'er | SQL-kontrakter dækker hver funktion og den gamle 1939-adgangsvej |
| `source_id` og profil-id | En uforanderlig, source-bundet writerprofil indgår i hver autorisation og batch | Samme writer køres med en syntetisk anden source/profil uden 1939-konstanter |
| Én overgangsversion | Smalle, signaturfaste 1939-views og RPC-wrappers kalder kun den generiske kerne | Legacy-kontrakt- og idempotens-tests er grønne |
| Stop ny editionsgæld | `db-verify.sql` låser alle tilladte `_1939`-katalogobjekter i en eksplicit allowlist | En ny permanent `_1939`-funktion/relation får verificeringen til at fejle |

**Værdikædeled:** den fælles motors apply/reversal-gate efter menneskelig
afgørelse og før publiceringskontrol.
**Leverancetype:** en generel permanent mekanisme med én tidsafgrænset
legacy-afvikling; 1939-egenskaber bliver data i en profil, ikke nye
databasebegreber.
**Redaktionel/læserrettet værdi:** den næste udgave kan anvende samme
autoriserede, reversible og auditerede writer. Det bevarer kilde-, batch- og
beslutningsspor uden at få redaktionen til at skifte writerflow pr. årbog.
**Workflow, der erstattes:** en ny udgave må ikke længere kopiere
`reimport_1939_*`, `red_*_1939_v50_*` eller den hardcodede R-gateway.

## 2. Afgrænsning

### Inden for #153

- Hele den aktive 1939 production-writerfamilie: autorisation, batch,
  append-only events, source-evidence, person-create, canonical-delta,
  finalize, reversal, cutover/activation og name-completion.
- Den editionsnavngivne R-gateway, som i dag hardcoder `source_id = 3` og
  1939-RPC-navne.
- Frisk-installations-DDL, migrations-DDL, RLS/ACL'er, SQL/R-tests og
  `db-verify`-kataloggaten for denne kontrakt.
- En 1939-compatibility-facade i præcis én dokumenteret overgangsversion.

### Bevidst uden for #153

- Ingen ny 2018-20-import, ingen ændring af kildeindhold og ingen reel tredje
  årbog. Den anden profil i test er en disponibel kontraktfixture, ikke en
  dataimport.
- Ingen omskrivning af 1939-ekstraktion, OCR, reviewark, manifestgeneratorer
  eller andre editionsspecifikke arbejdsartefakter. De må fortsat være
  editionsnavngivne, fordi de ikke er permanente fælles databaseoverflader.
- Ingen sammensmeltning af den eksisterende C3-specifikke
  `reimport_case_*`-mekanisme med denne writer. Dens `phase='c3'`-kontrakt,
  selection/receipt-semantik og produktionsbevis er et separat spor. Delte
  canonical-JSON-helpers får editionsneutrale primærnavne med en begrænset
  kompatibilitetsalias, men C3's batchmodel ændres ikke her.
- Ingen V3 source-scoped-evidence-ledger, ny publiceringsmodel, browserarbejde
  eller ændring af #152's policy, frysning eller produktions-cutover-gate.
  #153 skal derimod bruge den allerede specificerede v2-kontrakt korrekt; den
  må ikke genåbne en v1-skrivesti som om #152 ikke fandtes.
- Ingen produktionsdatabase, push, merge, deploy eller produktions-GO.

Denne afgrænsning er et bevidst værn mod, at #153 igen vokser fra en mekanisk
writergeneralisering til et nyt programspor.

## 3. Målarkitektur

### 3.1 Generisk writerprofil

Der indføres én privat, append-only profilregistry med en sammensat identitet:

```text
private.reimport_writer_profile
  (source_id, profile_id) PRIMARY KEY
  profile_version, profile_sha256, writer_config, created_at
  UNIQUE (source_id, profile_id, profile_sha256)
```

`profile_id` er en versionsbåren, menneskeligt læsbar nøgle, eksempelvis
`daa-1939-v50-production-write-v1`. `profile_sha256` binder den eksakte
konfiguration. En ny konfiguration får et nyt `profile_id`; en profilrække må
aldrig ændres eller slettes efter oprettelse, heller ikke før første batch.
En trigger afviser `UPDATE` og `DELETE`, så en ID/hash-kombination altid er
forsejlet.

`writer_config` er et valideret, lukket objekt med netop de værdier, der i dag
er skjulte 1939-konstanter: extraction-run-identitet og versioner,
rendition-nøgle/-type/-metadata, observationens metode/label og
citationslabel-template. Det må ikke indeholde SQL, vilkårlige funktionsnavne
eller et åbent regelsprog. Den generiske writer læser kun disse validerede
felter. Inden implementering skal en tabelbaseret literal-inventory klassificere
hver eksisterende 1939-konstant som (a) generisk invariant, (b) valideret
profilfelt, (c) manifest-/autorisationdata eller (d) legacy-adfærd, der skal
fjernes. Hardcodede source-ID'er, editionslabels, otte-rækkers antagelser og
gamle RPC-navne må ikke overleve uklassificeret. Profilen ejer dermed
fysisk/sproglig editionsforskel; motoren ejer autorisation, audit, identitet,
gater og mutation.

Det godkendte manifest er en generisk, lukket envelope med `source_id`,
`profile_id` og `profile_sha256` ud over de nuværende manifest-/preview-hashes
og operationer. Alle generiske indgangspunkter, der opretter eller autoriserer
et batch, modtager og verificerer samme triple mod den uforanderlige
profilregistry før nogen mutation. Triple og profilhash lagres på autorisation
og batch.

`reimport_authorization` har en unik
`(id, source_id, profile_id, profile_sha256)`-nøgle, og batchens tilsvarende
quadruple er en foreign key til den. En separat
`(source_id, profile_id, profile_sha256)`-foreign key til profilregistryet
forhindrer både profilforfalskning og glid mellem batch og autorisation. Alle
replay-, finalized-batch-genbrug-, reversal-, cutover- og child-batchopslag
skal bruge den komplette source-/profilidentitet sammen med deres eksisterende
manifest/principal- eller parent-betingelser. Andre historikrækker er bundet
til samme profil gennem deres ikke-null batchreference; de får ikke en løs,
uverificeret profilkolonne.

### 3.2 Primære dataobjekter og helpers

Følgende er de eneste primære writerobjekter for denne kontrakt:

```text
private.reimport_authorization
private.reimport_batch
private.reimport_event
private.reimport_name_completion_result
private.reimport_writer_profile

private.reject_reimport_event_mutation()
private.require_reimport_editor()
private.require_reimport_open_batch(uuid)
private.ensure_reimport_source_evidence(uuid, text, jsonb)
private.reimport_canonical_json_text(jsonb)
private.reimport_canonical_json_sha256(jsonb)
```

De beholder de eksisterende hash-, expiry-, principal-, idempotens-,
append-only-, expected-count- og before/after-state-invarianter. De generiske
fejl har `REIMPORT_*`-navne. Ingen kernefunktion må læse en 1939-konstant,
antage `source_id = 3` eller konstruere en editionsspecifik DDL-identitet.
Expected counts, source-batchrelationer og eventantal kommer fra den
autoriserede manifest-/batchidentitet, aldrig fra et editionsfast tal.

Aktive writer- og name-completion-låse afledes af den konkrete
`(source_id, profile_id)`-identitet. En legacy-wrapper går gennem netop samme
kerne og dermed samme lås; den må ikke etablere en parallel låsevej.

### 3.3 Narrativ record-kontrakt v2

Den generiske writer er en efterfølger til #152, ikke en undtagelse fra den.
Før enhver generisk mutation tages den samme globale
`daa-narrative-record-contract`-lås, som beskytter v2-cutover, før
source-/profil- og øvrige writerlåse. Derefter kræves
`narrative_record_contract_version() = 2`; version 1 og enhver ukendt version
fejler fail-closed med en generisk kontraktfejl.

Person-create, activation, reversal og enhver narrativændring må i v2 kun
gennemføre record-/publication-mutationer gennem #152's event-backede,
state-hashbundne RPC-kontrakt. Den generiske writer må ikke indsætte, opdatere
eller slette `narrative` eller `narrative_record_publication` direkte. Den
skal bevare #152's frysning og stale-/publication-gater; den ændrer hverken
cutovermyndighed eller eksisterende C3-facades policy. C3 forbliver sin egen
`reimport_case_*`-kontrakt og må fortsat fejle lukket, når den eksisterende
#152-kontrakt kræver det.

### 3.4 Offentlig generisk RPC-flade

Den generiske flade hedder:

```text
red_authorize_reimport(..., p_source_id, p_profile_id, ...)
red_begin_reimport(...)
red_apply_reimport_source_evidence(...)
red_apply_reimport_person_create(...)
red_apply_reimport_canonical_delta(...)
red_finalize_reimport(...)
red_authorize_reimport_reversal(...)
red_reverse_reimport(...)
red_authorize_reimport_cutover(...)
red_activate_reimport_batch(...)

red_lock_reimport_name_completion(..., p_source_id, p_profile_id)
red_authorize_reimport_name_completion(..., p_source_id, p_profile_id, ...)
red_preflight_reimport_name_completion(...)
red_begin_reimport_name_completion(...)
red_apply_reimport_name_completion(...)
red_finalize_reimport_name_completion(...)
```

En signatur-for-signatur ACL-matrix er en del af kontrakten: owner,
`SECURITY DEFINER`, fast `search_path`, `PUBLIC`/`anon`/`authenticated`/
`service_role`-grants og påkrævet redaktionsrolle angives for både generiske
og legacy-RPC'er. Den afledes fra den levende flades tre adgangsklasser
(service-only authorisation, authenticated writer og den særskilte
name-completion-flade); den må ikke erstattes af et blanket grant. Tests
beviser hver celle i matricen, især at klientrollen ikke kan selvautorisere.

En komplet generisk-til-legacy fejlmatrix angiver for hver observerbar
`REIMPORT_1939_*`, `NAME_COMPLETION_1939_*` og cutoverfejl det tilsvarende
generiske fejlforhold og wrapperens præcise oversættelse. Ukendte fejl
oversættes ikke tavst.

Den generiske reimport- og name-completion-R-gateway modtager
source/profil/hash fra det verificerede manifest og kalder kun den generiske
flade. Den ejer transaktion, preflight, rollback og manifesthash som før, men
ikke editionsvalg eller hardcodede source-ID'er. De eksisterende 1939-scripts
bliver tynde inputvaliderende adapters, der kalder disse gateways og ikke DBI
eller gamle RPC'er direkte.

## 4. 1939-overgangsversion og dataflytning

### 4.1 Kompatibilitetskontrakt

`reimport-writer-v1` er den eneste overgangsversion. Den indeholder:

- views med de gamle private relationsnavne over de generiske primærer;
- signaturfaste `red_*_1939_v50_*`-wrappers; og
- hvor aktive C3-kald stadig behøver dem, snævre aliases for de gamle
  canonical-JSON-helpernavne.

Wrappers pinner `(source_id = 3, profile_id =
'daa-1939-v50-production-write-v1')` samt den seedede profilrækkes
`profile_sha256` og
delegerer umiddelbart til den
generiske flade. De ejer ingen egen skrive- eller valideringslogik.
Kompatibilitet betyder samme SQL-signatur og returtype, samme
rolle-/ACL-adfærd, transaktions-/idempotensadfærd og de legacy-fejltokens, som
eksisterende callers og kontrakttests observerer; wrapperen oversætter derfor
de relevante generiske domænefejl ved grænsen. Nye callers må kun bruge
generiske navne.

Aliasernes fjernelse er en eksplicit #149-exitopgave efter en separat,
reviewet migrations- og consumer-inventory. De må ikke forlænges eller fjernes
stiltiende. Dette er ikke en produktionsautorisation.

### 4.2 Migrationskontrakt

For et allerede migreret miljø skal migrations-DDL i én transaktion:

1. oprette og forsegle 1939's profilrække med dens hashbundne
   `writer_config`;
2. flytte/omdøbe de eksisterende 1939-primærtabeller og en udtømmende
   dependent-object-inventory: indeks, PK/unique/check/FK-constraints,
   policies, typer, owned identity-sekvenser, append-only triggers og
   triggerfunktioner;
3. backfille og håndhæve `(source_id, profile_id, profile_sha256)` på
   historiske autorisationer/batches og bekræfte, at hver historisk
   resultatrække når samme profil via sin batchreference;
4. oprette de gamle relationviews og public wrappers først, når den generiske
   kerne er komplet; og
5. kontrollere bevaret rækkeidentitet, rækkeantal, batch/event/referencekæde,
   den komplette profilidentitet, hashes og ACL'er før commit.

En frisk installation skaber alene de generiske tabeller og derefter de
udtrykkelige transition-views/wrappers. Den må aldrig starte med 1939-tabeller
for efterfølgende at omdøbe dem.

Migrations- og friskvejen skal ende i samme katalog- og funktionskontrakt.
Fejl, manglende profil, source/profile-mismatch eller drift giver en eksplicit
fejl og rollback; ingen silent fallback til den gamle writer er tilladt.

## 5. Editionsnavne-gate

`db-verify.sql` får en permanent katalogassertion, der serialiserer alle
navngivne, permanente `_1939`-afhængigheder i `public` og `private`:
relationer (inklusive views, indexes og sequences), relationstyper,
funktioner med signatur, triggers med parentrelation, constraints med
constrainttype/parentrelation og policies. Den sammenligner det præcise sæt
med en versionsstyret, kommenteret allowlist af allerede godkendte
legacy-kontrakter, inklusive denne specs smalle v1-views/wrappers og
eksisterende C3-objekter.

Assertationen fejler med `REIMPORT_EDITION_OBJECT_ALLOWLIST_DRIFT`, hvis et nyt
permanent `_1939`-objekt opstår eller et allowlistobjekt får forkert slags,
signatur eller parent. Negative rollback-isolerede fixtures opretter én ekstra
funktion, relation, constraint, policy, sequence/index og trigger efter tur
og beviser fejlen. Den er en driftgate mod ny gæld, ikke en påstand om, at alle
eksisterende historiske objekter er fjernet.

## 6. Test- og færdigbevis

Følgende bevispakke er nødvendig før #153 kan kaldes integreret:

1. **Generisk SQL-kontrakt:** tabeltyper, composite profile-hash-FK,
   profilimmutabilitet, append-only events/results, #152 v2-global-lock-first,
   event-backed recordmutation, ACL-/fejlmatricer, `SECURITY DEFINER`/
   search path og alle generiske writer- og name-completion-signaturer.
2. **To profiler:** source 3's seedede 1939-profil og en disponibel anden
   source/profil gennemfører hele den samme generiske kæde: autorisation →
   begin → source evidence/person-create → name-completion → finalize →
   activation og separat reversal. Begge bruger med vilje identiske manifest-
   og preview-hashes for at bevise profile-scoped idempotens. Forkert
   source/profil, ukendt profil, profilhashdrift og manifestprofilhash-mismatch
   afvises før writes.
3. **Hele writerfladen:** canonical-delta (fortsat fail-closed, hvis dens
   policy er unsupported), reversal, cutover/activation og name-completion
   testes på generisk API med gældende locks, exact state assertions og uden
   hardcodet editionsantal eller source-ID.
4. **Legacy-paritet:** de gamle 1939-navne beviser samme positive flow,
   idempotens, tamper-afvisning, rollegrænse, append-only-beskyttelse og
   returtyper. De må kun skabe/læse generiske primærrækker med den pinnede
   profil.
5. **R-gateway:** enhedstests beviser både reimport- og name-completion-
   manifestets source/profil/profilhashbinding, at begge gateways kalder
   generiske RPC'er, og at 1939-wrapper-scripts alene er legacy-adapters uden
   egne DBI-kald eller gamle RPC-navne.
6. **Installationsparitet:** frisk schema → migrations og en repræsentativ
   migreret fixture ender med identisk serialiseret generisk katalog, inklusiv
   constraints, policies, types, sequences, indexes, routines, triggers,
   parentidentiteter og ACL'er; historiske rækker og referencer er bevaret.
7. **Kataloggate:** positiv allowlistkontrol og negative ny-`_1939`-mutationer
   for hver understøttet katalogobjekttype.

Alle databasebeviser køres kun mod en lokal, disponibel PostgreSQL-database.
Grønne enhedstests alene er ikke nok: mindst én gennemløbende SQL/R-vej skal
bevise, at den virkelige privilegie-, transaktions- og migrationsflade virker.

## 7. Ikke-forhandlingsbare sikkerhedsgrænser

- Ingen production-DB-forbindelse, produktionmutation, push, merge eller
  deploy er en del af #153.
- Ingen adgang til eller ændring af `work/` eller beskyttede reviewartefakter.
- Ingen nye permanente editionsnavngivne databaseobjekter udenfor den
  dokumenterede v1-allowlist.
- Ingen ny udgave må få en wrapper; den bruger kun
  `source_id + profile_id + profile_sha256`.
- Uafklaret profil, authorization, source-binding, manifest, targettilstand
  eller rollback-sikkerhed stopper fail-closed.

## 8. Definition af færdig

#153 er færdig som kodeleverance, når den generiske writer er den eneste
primære mekanisme, 1939 er en lille profil plus v1-compatibility-facade,
`db-verify` stopper ny editionsgæld, og bevispakken i §6 er grøn i det rene
worktree. Det gør #153 til en nødvendig, isoleret leverance på vej mod #149;
det gør ikke 2018-20, den fælles genimportkæde eller hele roadmapet
produktionsklart.
