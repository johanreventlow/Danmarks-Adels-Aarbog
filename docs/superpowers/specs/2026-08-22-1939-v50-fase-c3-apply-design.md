# 1939 v50 fase C3 — sagsatomisk apply: design

**Status:** Designsektionerne er godkendt af brugeren 2026-08-22. Denne
samlede spec skal godkendes særskilt, før der skrives implementeringsplan.

## Formål

C3-reviewfasen har produceret et valideret, tekstfrit og hashbundet
beslutnings-JSON for syv sager. To beslutninger er bevidst `UAFKLARET`.
Apply-fasen skal derfor anvende præcis de fem fuldt afklarede sager og lade
begge akser i de øvrige to sager være helt urørte.

De fem valgte sager indeholder samlet:

- fem identitetsafgørelser `FORSKELLIGE`;
- fem recordafgørelser `TIL <person-id>`; og
- én recordafgørelse `INGEN_PUBLIKATION`.

Fasen skal omsætte disse beslutninger til én atomisk, autoriseret og fuldt
reversibel databasebatch. Den må ikke fortolke de to uafklarede sager,
anvende en af deres akser eller udlede nye redaktionelle beslutninger.

## Bindende beslutninger

| Spørgsmål | Beslutning |
|---|---|
| Apply-enhed | Hele sagen. Kun fem sager, hvor både identitet og alle records er afklaret. |
| Atomaritet | Alle fem sager i ét server-side RPC-kald og én PostgreSQL-transaktion. |
| `TIL`-semantik | Normaliseret narrativtekst plus publiceringsbinding efter særskilt tekstgodkendelse. |
| `INGEN_PUBLIKATION` | Ingen domænemutation; append-only beslutningsevent og bevis for fravær af aktiv binding. |
| Identitet | Fem komponentvaliderede `ikke_samme_som`; ingen `samme_som` oprettes i denne batch. |
| Genkørsel | Batch-idempotens på nonce og alle artefakthashes; samme nonce med drift afvises. |
| Reversal | Én dedikeret, sagsatomisk reversal med exact-after/CAS. |
| Produktions-GO | Først efter disposable apply, reconnect, reversal og særskilt brugerautorisation. |

## Hvorfor de eksisterende writeveje ikke er tilstrækkelige

En klientløkke over `red_ikke_samme_som`, narrativ-RPC og
`red_publicer_narrative_record` er NO-GO:

- den giver ikke én varig kvittering, der binder alle fem sager til C3's
  beslutningshash;
- `red_ikke_samme_som` validerer i dag direkte par, ikke hele
  `samme_som`-komponenter;
- de almindelige identitets-RPC'er låser ikke personrækkerne mod samtidig
  `red_slet_person`;
- publiceringsbindingen er ikke dækket af generisk change-set-undo;
- `red_publicer_narrative_record` er ikke en transfer- eller batchkontrakt;
- `TIL` autoriserer ikke i sig selv de konkrete narrative tekstbytes; og
- commit-ukendt, idempotens og post-commit-reversal ville ligge i klientkode.

De generelle `source_record_placement`- og `source_persona_placement`-tabeller
må heller ikke genbruges. De beskriver evidensbaseret lineage-placement med
scheme-entry og header-/mention-evidens, som C3 ikke bærer. C3's `TIL` er her
en narrativ/publiceringsprojektion, ikke lineage-placement.

Den eksisterende generelle 1939-reimportbatch udvides heller ikke. Dens
operationstyper, counts og reversal er lukkede omkring tidligere
person-create/name-completion-forløb. C3 får en selvstændig, mindre
batchfamilie, som kan verificeres og reverseres uden at ændre de ældre
writeres kontrakt.

## Artefaktkæde

Apply-fasen er en envejs, hashbundet kæde:

```text
C3 beslutnings-JSON
  -> C3 candidate-manifest
  -> read-only databasepreview
  -> final C3 apply-manifest
  -> lokal HTML-tekstgennemgang
  -> byte-låst godkendelsesark
  -> tekstfri godkendelses-JSON
  -> expiring databaseauthorization
  -> atomisk C3-batch
  -> batchkvittering
```

Alle runtimeartefakter ligger under
`work/task27-1939-v50-c3-apply/`, er gitignorerede og model-blinde. Virkelige
narrativtekster må behandles af lokale scripts og den lokale browser, men må
ikke udskrives, committes, screenshots eller sendes ind i modelkontekst.
CLI-output er begrænset til skemaer, counts, filbasenames, status og hashes.

### Candidate-manifest og final apply-manifest

Candidate-manifestet er databaseuafhængigt. Det udleder præcis de fem hele
sager fra C3-beslutningerne, normaliserer de fem recordtekster og binder:

- selection-, state-, review- og decisions-SHA-256 fra C3;
- decisions-filens eksakte bytehash;
- eksakt fem case-ID'er og seks recordbeslutninger;
- logiske person-ID'er, RID'er og record keys;
- normaliseret tekst, flags og teksthash pr. `assign`; og
- candidate-manifestets egen bytehash og canonical-content-hash.

Den read-only databasepreview slår de logiske nøgler op og måler alle
drift-prone IDs og førtilstande. Først derefter bygger en deterministisk
finalizer det endelige apply-manifest. Det endelige manifest har et
versionsmærket skema og binder mindst:

- candidate-manifestets og databasepreviewets eksakte bytehashes;
- hele den forudgående C3-hashkæde;
- eksakt fem case-ID'er og seks recordbeslutninger;
- database name og PostgreSQL system identifier;
- kilde-ID og eksakte source-record-ID'er/record keys;
- et kanonisk payload pr. sag; og
- final-manifestets egen bytehash og canonical-content-hash.

For hver identitetsafgørelse indeholder payloaden:

- de to person-ID'er i den C3-godkendte normaliserede rækkefølge;
- handlingen `different`;
- forventet identitetskomponent-fingerprint; og
- forventet fravær eller eksakt idempotent `ikke_samme_som`-relation.

For hver `assign` indeholder payloaden:

- case-ID og RID;
- source-record-ID og record key;
- target-person-ID og target-narrative-ID;
- forventet gammel narrativ-SHA-256, side, privatstatus og bindingstilstand;
- den eksakte normaliserede nye tekst og SHA-256;
- alle anvendte normaliseringsflags;
- afledte record- og citation-labels; og
- eksakt forventet bindingstilstand `absent` eller `draft_same_record`.

For `no_publication` indeholder payloaden ingen narrativtekst. Den binder
source-recorden og den forventede tilstand, hvor ingen draft eller published
personbinding eksisterer.

### Normalisering og tekstpreview

C3's `TIL` vælger person, men godkender ikke automatisk tekstnormalisering.
De fem records køres derfor gennem en navngiven, deterministisk
normaliseringsprofil. Rå OCR må ikke skrives direkte.

En lokal, selvstændig HTML viser fem før/efter-sammenligninger med:

- fuld gammel og ny narrativtekst;
- source-record-kontekst og side;
- synlige normaliseringsflags;
- eksakte teksthashes; og
- ét uafhængigt valg `GODKENDT` eller `UAFKLARET` pr. record.

Siden har ingen netværk, databaseklient eller browserpersistens og renderer
tekst med sikre DOM-API'er. Den eksporterer et byte-låst godkendelsesark. En
separat konverter validerer arket mod det eksakte manifest/preview og skriver
tekstfri godkendelses-JSON. Apply kræver fem `GODKENDT`; ét `UAFKLARET`
stopper hele batchen.

## Databasemodel

Der indføres private, deny-all og append-only C3-tabeller. De præcise navne
låses i implementeringsplanen, men kontrakten omfatter:

### Authorization

Én række binder:

- operation `c3_apply` eller `c3_reversal`;
- manifest-, preview-, approval-, decisions- og state-hashes;
- database name og system identifier;
- eksakt authorized payload-map og counts;
- principal, nonce, issued/consumed timestamps og udløbstid; og
- status `issued|consumed|expired`.

### Batch

Én batchrække binder authorization og indeholder:

- status `open|finalized|reversed`;
- eksakt fem-sags-ID-mængde;
- forventede og observerede counts;
- fælles change-set-ID;
- created/finalized/reversed timestamps; og
- reference til reversal-authorization og reversal-kvittering.

### Event

Der skrives append-only events for alle elleve afklarede handlinger i de fem
sager: fem identitetsafgørelser og seks recordafgørelser.

Identitetseventet registrerer mindst relation-ID og udfaldet `created` eller
`reused`. Recordeventet registrerer action, relevante IDs, before-kind,
before-/after-hashes og payloadhash. `no_publication` får et varigt event med
bevist fravær af aktiv binding, selv om handlingen ikke muterer domænet.

Alle public-schema-tabeller har RLS. C3-tabellerne placeres i `private`, får
RLS som defense in depth og `REVOKE ALL` fra `PUBLIC`, `anon` og
`authenticated`. Klienten får ingen direkte DML-rettigheder.

## Databasefunktioner

Følgende logiske grænser kræves; implementeringsplanen fastlåser endelige
signaturer efter testinventar:

1. `red_preview_1939_v50_c3_apply(...) -> jsonb`
   - read-only og redaktør-gated;
   - genmåler den eksakte fem-sags state;
   - returnerer canonical preview og exact ID-set/counts.
2. `red_authorize_1939_v50_c3_apply(...) -> uuid/jsonb`
   - binder expiring nonce, principal, databaseidentitet og alle payloads.
3. `red_apply_1939_v50_c3_batch(...) -> jsonb`
   - ét RPC-kald og én transaktion for alle fem sager;
   - returnerer eksisterende receipt ved eksakt idempotent genkørsel.
4. `red_authorize_1939_v50_c3_reversal(...) -> uuid/jsonb`.
5. `red_reverse_1939_v50_c3_batch(...) -> jsonb`
   - exact-after/CAS og samlet reversal i én transaktion.

Public RPC'er er kun de nødvendige, rolle-gatede entrypoints. Privilegerede
helpers ligger i `private`. `SECURITY DEFINER` bruges kun, hvor private
tabeller/RLS kræver det; alle sådanne funktioner får fast, minimal
`search_path` og fuldt kvalificerede objektreferencer. PostgreSQL giver ellers
som udgangspunkt bred execute-adgang til nye funktioner, så alle nye
funktioner får eksplicit `REVOKE EXECUTE FROM PUBLIC, anon, authenticated`
før præcise grants.

Authorization følger den eksisterende 1939-writers totrinsmønster:

- service-role-gateway udsteder den kortlivede authorization; og
- en autentificeret, eksplicit redaktørprincipal konsumerer den gennem apply.

En direkte DBI-forbindelse skal sætte den rigtige JWT subject-claim lokalt i
transaktionen og verificere både profil og `current_rolle()='redaktion'`.

## Identitetsinvarianter

`FORSKELLIGE` er en komponentpåstand, ikke kun et råt personpar.

Før apply skal den generelle databaseinvariant hærdes:

- `red_ikke_samme_som(a,b)` afviser, hvis `_samme_som_gruppe(a)` og
  `_samme_som_gruppe(b)` overlapper;
- en ny `samme_som`-kant afviser enhver `ikke_samme_som`-kant mellem de to
  komponenter, ikke kun mellem de direkte endepunkter;
- komponentkontrollen for `samme_som` ligger i triggerlaget, så alle writers
  dækkes; og
- begge identitets-RPC'er låser involverede personrækker i stigende ID under
  `samme_som_mutation`, før eksistens- og grafkontrol.

Det lukker både indirekte kontradiktioner og racet med `red_slet_person` på de
polymorfe relationer uden person-FK.

Eksakt eksisterende `ikke_samme_som` genbruges idempotent. Receipt/event
markerer den `reused`; reversal må kun fjerne `created` relationer.

## Record- og publiceringsinvarianter

Apply må kun fortsætte, hvis hvert target-narrativ under lås matcher preview:

- narrative-ID, person-ID, source-ID, privatstatus, side og teksthash;
- source-record-ID/key og accepteret kildeankring;
- bindingstilstand `absent` eller en eksakt draft til samme record og samme
  afledte labels; og
- ingen anden draft/published personbinding for den samme source-record.

Alt andet er terminal drift. Der er ingen implicit rebind, withdrawal,
flytning eller label fra frit klientinput.

Narrativteksten ændres under batchens fælles, re-entrant change set.
Publiceringsbindingen er ikke i det generiske version registry, så C3-eventet
gemmer dens eksakte before/after-tilstand til dedikeret reversal.

`INGEN_PUBLIKATION` skjuler eller ændrer ikke eksisterende legacy-narrativer.
Det betyder alene, at den konkrete source-record ikke publiceres som
personrecord i denne batch.

## Låseorden og atomaritet

Apply og reversal bruger samme deterministiske rækkefølge:

1. `pg_advisory_xact_lock(hashtextextended('daa-1939-v50-production-writer',0))`;
2. actor/profile/role-gate;
3. `pg_advisory_xact_lock(hashtext('samme_som_mutation'))`;
4. alle involverede personrækker i stigende ID;
5. source-records i stigende UUID/kanonisk tekstorden;
6. narrativer i stigende ID;
7. eksisterende bindingsrækker i stigende narrative-ID;
8. identitetsrelationer/evidens i dokumenteret ID-rækkefølge.

Transaktionen udfører ingen fil-, netværks- eller anden ekstern I/O og holdes
kort. `lock_timeout` og `statement_timeout` er eksplicitte. Loader og
post-load må ikke overlappe C3-apply, medmindre de først bringes ind under
samme globale låseorden.

Alle fem sager valideres og låses før første domænemutation. En fejl i enhver
sag ruller authorization-consume, change set, identitet, narrativer,
bindinger, events og batchkvittering tilbage samlet.

## Reversal

Reversal er en ny batch, ikke en løs række af UI-undo-kald.

Før mutation kræves exact-after/CAS for:

- alle batchoprettede eller genbrugte identitetsrelationer;
- narrativernes efterhash og øvrige låste felter;
- bindingsrækker og status;
- C3-event-ID-set og payloadhashes; og
- den finalized batchkvittering.

Reversal udfører i én transaktion:

- genskabelse af tidligere narrativtekst gennem fælles change-set-undo;
- sletning af præcis batchoprettede bindingsrækker;
- genskabelse af en tidligere draft inklusive dens oprindelige værdier;
- fjernelse af kun `created` identitetsrelationer og deres evidens;
- ingen mutation af `reused` identitetsrelationer; og
- append-only reversal-events samt status `reversed`.

Hvis nogen eftertilstand er ændret siden apply, fejler non-force reversal uden
delresultat. Fasen tilbyder ingen `force=true`-omgåelse.

## Idempotens og commit-ukendt

Nonce er unik. Samme nonce og eksakt samme authorization/manifest returnerer
den eksisterende finalized receipt. Samme nonce med anden hash eller payload
afvises.

Gatewayen behandler forbindelsestab efter commit som `commit unknown`:

- den må ikke genudføre blindt;
- den reconnecter og slår receipt op på nonce plus alle hashes;
- eksakt finalized receipt er succes;
- fravær er sikkert ikke-committed;
- enhver delvis eller afvigende tilstand er terminal og kræver manuel audit.

## Verifikation og produktionsgate

Implementeringen udvikles TDD og testes først syntetisk uden forbindelse til
produktionsdata.

Minimumsdækning:

- præcis fem hele sager, fem `different`, fem `assign` og én
  `no_publication`;
- de to uafklarede sager og alle deres handlinger er fraværende;
- selection/state/review/decisions/manifest/preview/approval-hashdrift;
- same nonce/same payload idempotens og same nonce/different payload afvisning;
- komponentbaserede `same`/`different`-konflikter;
- concurrent personsletning kan ikke efterlade forældreløs relation;
- target-narrativ/binding/source-record-drift;
- eksisterende binding kun `absent` eller eksakt `draft_same_record`;
- fejlindsprøjtning før og efter hver sag giver nul delresultat;
- apply giver ét batch-ID, ét change set og eksakte event-/ID-sæt;
- apply -> reversal genskaber eksakt førtilstand;
- nyere drift gør reversal fail-closed;
- to konkurrerende identiske applys;
- apply mod identitets-RPC, publicerings-RPC, personsletning og loader;
- ACL/RLS/rolle-gate for anon, medlem, redaktion og service role; og
- ingen PII/narrativ tekst i logs, tests, receipts eller godkendelses-JSON.

Før produktions-GO gennemføres:

1. lokal, menneskelig godkendelse af alle fem tekstdiffs;
2. frisk backup med mode `0600` og SHA-256;
3. restore til disposable PostgreSQL;
4. rigtig gateway/DBI apply i én transaktion efterfulgt af `ROLLBACK`;
5. reconnect og eksakt byte-/ID-set-kontrol af førtilstanden;
6. committed disposable apply og reconnect-kontrol;
7. dedikeret reversal, reconnect og eksakt førtilstandskontrol;
8. to-sessioners concurrencytests; og
9. særskilt bruger-GO til produktion.

En direkte rolle-gatetest må køres i `BEGIN READ ONLY`: korrekt redaktør skal
passere rollegaten og fejle på den første write, ikke på rollen. En reel
success/rollback-test kræver write-enabled disposable database.

Miljøvariabler er alle-eller-ingen:
`PGDATABASE`, `PGHOST`, `PGPORT`, `PGUSER` og `PGPASSWORD`. Da fallback er pr.
variabel, må ingen delmængde sættes.

Python kører med `/usr/bin/python3` 3.9.6, og al ny Pythonkode er
3.9-kompatibel. Python-, R-/DBI- og SQL-tests rapporteres separat.

## Uden for scope

- Apply af de to sager med en `UAFKLARET` akse.
- Automatisk udfyldning af uafklarede beslutninger.
- `SAMME`-writes i denne batch.
- Lineage-/scheme-placement.
- Nye logiske records for `REVISION`.
- Implicit rebind eller withdrawal af eksisterende publiceringer.
- Publicering af staged personer.
- De øvrige lowercase-start- eller `[NY]`-sager.
- Produktionsapply uden en ny, eksplicit GO efter fuld rehearsal.

## Næste gate

Efter særskilt godkendelse af denne spec skrives en implementeringsplan. Planen
skal ende ved fuldt verificeret disposable apply/reversal og et nyt stop før
produktion. Specgodkendelsen er ikke produktionsautorisation.
