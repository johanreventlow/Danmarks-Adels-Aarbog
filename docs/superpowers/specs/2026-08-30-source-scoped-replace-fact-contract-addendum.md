# #153 addendum: Source-scoped evidence append, fase A

**Dato:** 2026-08-31
**Status:** Afvist scope-variant — ikke normativ.
**Supplerer:** `2026-08-30-generalized-writer-batch-design.md`, afsnittet
*Source-scoped replace-writer*.

## Beslutning og effekt på #153

Dette dokument bevares som begrundelse for den afviste fase-A-retning. Den
autoritative efterfølger er
`2026-08-31-source-scoped-evidence-visibility-design.md`; ingen del af dette
udkast giver implementeringsautoritet.

Task 4 deles. Fase A er en lille append-only writer for nye, positivt
kildeejede tekstuelle evidenskæder. Den er et sikkert delresultat, ikke en
implementering af den styrende source-scoped replace-writer. Den ændrer derfor
ikke #153-designets krav om senere egentlig replace og compensating reversal,
og #153 kan ikke erklæres færdig alene på grundlag af fase A.

Fase A erstatter det tidligere v2-udkast i denne fil. Den gamle Task 4-plan er
ikke autoriseret og skal revideres efter godkendelse af dette addendum.

## Præcist scope

En batch må kun oprette nye rækker i denne retning:

```
source_id -> citation -> assertion -> fact(person)
```

Hver assertion har mindst én citation fra batchens ene `source_id`. Facten har
`subjekt_type='person'` og en eksisterende, entydigt matchet `person_id`.
Begge bindinger kommer fra en persisteret, hashbundet redaktionel attestation.

Fase A må ikke oprette eller ændre `conclusion`, `relation`, `note`,
`haendelse`, `story`, familieobjekter, `same_som`, narrativ eller
publication-event. Den må ikke ændre, slette eller adoptere en eksisterende
fact, assertion eller citation. Nye personer og source records er
`SOURCE_EVIDENCE_APPEND_CREATE_STAGED_OUT_OF_SCOPE`; fravær i input udleder
aldrig DML.

`reversal_mode=not_supported` er bindende. Fejl før terminal receipt ruller
den aktuelle transaktion tilbage. Senere replace, deletion eller compensation
kræver en ny, godkendt source-scoped replace-specifikation og autorisation.

## Lukket manifest

Den muterende RPC accepterer alene et canonisk
`source-scoped-evidence-append-v1`-manifest med præcis dette topniveau:

```
{schema,source_id,record_keys,input_sha256,expected_counts,operations}
```

Canonical JSON er RFC 8785 (JCS) UTF-8. Ukendte felter, duplikerede keys,
ikke-canoniske bytes, flydende tal, eksponentnotation og ikke-NFC-strenge
afvises. `input_sha256` er SHA-256 over de uændrede rå inputbytes; alle andre
hashes er SHA-256 over de fulde JCS-bytes af deres viste objekt. ID'er er
decimalstrenge uden fortegn eller foranstillede nuller; `null` er kun gyldigt,
hvor det er angivet nedenfor.

`record_keys` er en ikke-tom, bytevist sorteret array af source-scope.
`operations` er en ikke-tom, bytevist `element_id`-sorteret array.
`expected_counts` er præcist
`{facts_created,assertions_created,citations_created}` med ikke-negative
heltal: antal operationer, assertions og citations. Preflight genberegner dem.

En operation er præcist:

```
{element_id,source_record_key,person_id,fact_key,chain,chain_sha256}
```

`element_id`, `fact_key`, `assertion_key` og `citation_key` matcher
`[a-z0-9][a-z0-9._-]{0,127}`. `fact_key` er 64 lowercase hextegn fra
SHA-256(JCS(`{source_id,source_record_key,element_id}`)); den er aldrig et
database-ID. `chain_sha256` er SHA-256(JCS(`{schema:"source-evidence-chain-v1",
fact_key,chain}`)).

`chain` er præcist:

```
{fact:{faktatype,sted_id},assertions:[{assertion_key,vaerdi_tekst,
 citations:[{citation_key,side,citat_tekst,citat_dato,kvalitet]}]}
```

`faktatype` og `vaerdi_tekst` er ikke-tomme NFC-tekststrenge; `sted_id` er et
decimal-ID eller `null`. Assertions og citations er ikke-tomme og sorteres på
deres key. Citationens øvrige felter er ikke-tom NFC-tekst eller `null`.
Fase A sætter assertionens objekt- og datofelter til SQL `NULL`, `calendar`
til `'gregoriansk'` og `uforanderlig` til `true`; manifestet kan ikke vælge
andre værdier. Citationens `source_id` er altid manifestets og er ikke et
caller-felt.

## Attestation, preflight og apply

Før autorisation persisteres en redaktionel binding med serverallokeret ID og
SHA-256(JCS(payload)) over præcist:

```
{schema:"source-evidence-append-binding-v1",source_id,source_record_id,
 source_record_key,person_id,person_external_id,review_basis_sha256,actor_id}
```

Autorisationen er single-use og binder manifest-hash, input-hash,
attestation-ID/-hash, databaseidentitet, actor, nonce, udløb og element-scope.
Exact replay med samme manifest og autorisation returnerer oprindelig receipt;
alle andre afvigelser fejler før DML.

Read-only preflight verificerer JCS, bindingen, source-scope, `fact_key`-
fravær i adapter-ledgeren og expected counts. Den afviser enhver eksisterende
fact med samme `(person_id,faktatype,sted_id)` eller eksisterende chain-hash.
Et match er NO-GO, aldrig en implicit replace.

Write tager advisory locks for source-scope og hver `(source_id,fact_key)` i
stabil orden. Den tager derefter en advisory lock for hver canonical
`(person_id,faktatype,sted_id)`-tuple i bytevist JCS-orden, source records i
UUID-orden og personer i ID-orden. Den genberegner preflight efter låsning.
Den bruger kun en
migrationsdefineret, concurrency-sikker fact-ID-allokator: caller-ID'er og
`max(id)+1` er forbudt. Den opretter fact, assertions og citations samt én
adapterejet append-only mapping pr. ny ID:

```
{source_id,fact_key,member_kind,member_key,db_id,chain_sha256,batch_id}
```

`member_kind` er `fact`, `assertion` eller `citation`, og factens key er
`"fact"`. Unikhed på `(source_id,fact_key,member_kind,member_key)` samt
`(member_kind,db_id)` forhindrer key- og DB-ID-genbrug. Fase A kalder aldrig
`public.begin_change_set` og sætter ikke `app.change_set_id`.

## Receipt, drift og beviser

Postverify genberegner levende kæder, `chain_sha256`, mappinger og counts før
finalisering. `verified_state_sha256` er SHA-256(JCS af
`{schema:"source-evidence-append-verified-v1",manifest_sha256,operations}`),
hvor operations i elementorden er
`{element_id,fact_key,chain_sha256,members}` og members i
`member_kind,member_key`-orden er `{member_kind,member_key,db_id}`.
Afvigelse ruller transaktionen tilbage. Receipt indeholder kun
manifest-/input-/attestation-/database-/autorisationbindinger, counts,
stabile keys og `verified_state_sha256`, aldrig rå evidenstekst. En særskilt
current-state-verifier rapporterer senere drift uden at ændre receipt.

En frisk disposable database skal bevise:

1. schema-/JCS-/hash-/binding-/actor-/database-/nonce-/scope-afvisning før DML;
2. vellykket append med præcise counts, receipt og idempotent exact replay;
3. afvisning af eksisterende/adopteret kæde, update/delete, ny person/source,
   conclusion/relation/note/narrativ og caller- eller `max(id)+1`-ID;
4. rollback før receipt og senere current-state-drift;
5. to-session race med samme key og overlappende source scope uden dobbelt-ID,
   dobbelt-kæde, deadlock eller delvis batch;
6. RLS/ACL-denial for `anon`, almindelig `authenticated` og ikke-redaktionelle
   roller.

## Ikke-mål og næste gate

Fase A åbner ikke narrative-entrypoints og er ikke adgang til Task 5. Den
erstatter ikke source-scoped replace, eksisterende-fact adoption, update/delete,
compensation, conclusions, relationer eller publicering. Hver af dem kræver en
senere specifikation, der lukker ownership-, consumer-, concurrency- og
reversal-kontrakten.
