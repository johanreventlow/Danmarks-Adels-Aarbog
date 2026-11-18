# Delspec — persona for en helpost uden tekst; Henrik og Iven (1939) får deres egen tekst

**Status:** **godkendt af projektejeren 2026-11-17** efter brainstorm og bygherre-tjek (§10). Projektejerens
afgørelser står i §3; mine valg er markeret *mit valg*. **Revideret 2026-11-17 efter Task 0 (§9) og Codex-runde 1
med Opus-dom (§10)**; projektejeren godkendte den brede spærring (§4.5), 944's oversigtsomtale (§8) og rettelserne.
**Arv:** decisions 2026-11-17 (backlog 1: Henrik og Iven bindes til deres egne poster), decisions 2026-11-10 (6d-2b:
598 og 603 trukket tilbage, fordi teksterne var andres), 6b (`2026-10-31-trin6b-identitet-design.md` §4.2: elementoperationen
`publication_persona`), 6d-1 (`2026-11-08-trin6d-placement-relationer-medlemskab-design.md` §5.3: placements), 6d-2a
(`2026-11-09-trin6d2a-oversigtsregel-identitet-design.md` §4.4: identitet med `red_afgoer_source_persona` og
`basis=human_sheet`).
**Review-budget (B13), *mit valg*:** 1 Codex-runde (`gpt-6.1-sol`) på spec+plan og 1 på diffen før prod; Opus afvejer
hvert fund. Bygherre-tjekket tæller ikke med.

## 1. Roadmap-kobling

1. **Roadmapmål:** trin 6, færdigbevis (a): 1939's narrativbinding og publicering går gennem de samme operationer som
   2018-20.
2. **Værdikædeled:** source persona → identitet → placement → narrativbinding og publicering.
3. **Leverancetype:** én generel elementoperation i den fælles reimport-writer (persona for en helpost uden aktiv
   tekstbinding; editionsneutral, persona-nøglens prefix fra profilen) og en lille dataceremoni for to 1939-poster.
   Legacy-afvikling af 6d-2b's tilbagetrækninger. Ingen editionsnavngiven permanent overflade.
4. **Værdi:** læseren ser 1939's egne tekster om Henrik (934 → Hinrich, 2) og Iven (929 → Iwan, 44) som 1939-udgaven
   på deres side. Redaktøren kan derefter rette teksterne med den almindelige narrativredigering.
5. **Færdigbevis:** §8.
6. **Erstatter:** tomrummet efter 6d-2b's tilbagetrækning af 598 og 603. Desuden hønen-og-ægget for poster uden tekst:
   6b's `publication_persona` kræver en publiceret binding, og den generelle narrativwriter kræver en persona med
   identitet og placement.
7. **Ændrer en tidligere note:** decisions 2026-11-17, backlog 1, sagde »Ingen ny mekanisme«. Det var forkert (§2);
   noten rettes i samme PR.

## 2. Målt udgangspunkt (prod, læse-kun, 2026-11-17)

| | Henrik 934 | Iven 929 |
|---|---|---|
| Post | `record-e63debca-6fb4-456e-9b11-90a8676d98b8`, s. 498-499, 1.170 tegn | `record-9db9004f-d6a7-4b98-bd0f-f1f90ba770d8`, s. 499, 1.124 tegn |
| Overskrift over posten i bogen | »Til samme Generation, ikke Brødre, hørte:« (efter Volrad, III-9) | »IV A. Hr. Hartvig Reventlows Søn:« |
| Trykt løbenummer | intet | intet |
| Forankringer | 1 (accepteret) | 1 (accepteret) |
| Helpost | én `person`-observation med præcis én mention | samme |
| Klausuler | ja | ja |
| Persona / record-placement / persona-placement | 0 / 0 / 0 | 0 / 0 / 0 |
| Fortolkninger (6c-1) på postens observationer | 0 | 0 |
| Aktiv tekstbinding på posten | ingen | ingen |
| Personens 1939-tekst | 603, `legacy_withdrawn` (Hartvigs tekst) | 598, `legacy_withdrawn` (mest Dosos tekst) |
| `person_external_id` for kilde 3 | 1 | 1 |
| Person | offentlig, ikke staged, afdød | samme |
| `samme_som` | 934 → 2 (Hinrich) | 929 → 44 (Iwan) |

- **Den generelle writer afviser i dag** (`private.narrative_publication_state` for begge):
  `NARRATIVE_RECORD_IDENTITY_REQUIRED`. Identiteten udledes kun gennem en accepteret record-placement, en accepteret
  `principal_member`-persona-placement og en accepteret persona-identitet (`schema.sql:14936-14960`). Redaktørens liste
  (`red_person_narrative_records`, `schema.sql:15588`) finder posten ad samme vej.
- **6b's persona-writer afviser** (`private.write_publication_persona`, `schema.sql:18180`): den kræver præcis én
  publiceret binding på posten og udleder personen af den. Henriks og Ivens poster er 2 af de 21 helposter, som 6b
  sprang over af den grund.
- **149b's migrering kan heller ikke bruges:** den kræver `person_external_id.record_key` = postens nøgle (1939's
  eksterne nøgler er gamle uuid'er) og en grandfathered eller ubrugt legacy-række; 598 og 603 er `withdrawn`. Den ville
  desuden binde den forkerte tekst.
- **6d-1 placerede ingen poster uden trykt løbenummer** (53 af de 64 uplacerede; `placement-6d1-prod.md`). Det gælder
  også Doso (930), der alligevel vises, fordi hans tekst blev bundet ved kontrakt-cutover 2026-09-06
  (`existing_exact_binding`). `private.write_record_placement` (`schema.sql:2729`) kræver intet nummer.
- **Redaktøren** (`web/src/components/PersonNarrativeRecordEditor.tsx`) viser en post med identitet og placement med
  »Opret kladde« og et tomt tekstfelt.
- **0 personer i kilde 3 har i dag mere end én narrativrække.** Henrik og Iven bliver de første (§4.5).
- **Bogpostens tekst er rå OCR:** orddelinger ved linjeskift, `### PAGE 0004 ###` midt i Henriks post og fejl som
  »1ll« (III), »r. 1ven« (Hr. Iven) og »lwanus« (Iwanus).

## 3. Projektejerens afgørelser (2026-11-17)

1. **Vej A:** en ny, generel variant af persona-operationen for poster uden tekst; derefter de eksisterende veje for
   identitet, placement og tekst. Vej B (en manuel redaktørhandling »knyt bogpost til person«) hører til backlog 2 og
   bygges ikke her.
2. **Teksten:** ceremonien skriver en upubliceret kladde fra bogposten, foldet (orddelinger og sidemarkør fjernet).
   Projektejeren retter OCR-fejl i redaktøren og publicerer selv.
3. **Afgrænsning:** kun Henrik og Iven. Claus (afkortet post) og Emeke (ingen egen post) venter på backlog 2.
4. **Placement afgøres af projektejeren** på et kortark (§4.3), fordi posterne ikke har løbenummer.

## 4. Design

### 4.1 Elementoperationen: persona for en helpost uden aktiv tekstbinding (*mit valg* af form)

En ny elementoperation i den generelle reimport-writer (authorize → begin → apply → finalize, som 6b), ikke en
lempelse af `publication_persona`. Grund: `publication_persona`-personas venter på 6b's publiceringskontrol
(`private.persona_awaiting_control`), og den kontrol forudsætter en binding. Arbejdsnavn: `record_persona`
(bygherren vælger det endelige navn; det må ikke være editionsnavngivet).

Pr. element (én helpost):

- **Lås** som `write_publication_persona`: kun `read committed`, kontraktlåsen, `source_record … FOR UPDATE`, derefter
  postens publiceringsrækker i id-orden, og kildens delte kandidatlås.
- **Forudsætninger, efterprøvet under låsen:**
  - posten findes for batchens kilde;
  - helposten (profilens helpost-slags) har præcis én mention, og mentionens id og tekst-hash svarer til payloaden;
  - posten har **ingen aktiv tekstbinding** (`draft` eller `published`);
  - ingen persona i kilden har en mention i helposten, og ingen persona har nøglen;
  - payloadens målperson findes, er ikke levende og har præcis én `person_external_id` for kilden;
  - payloaden bærer sha256 af projektejerens godkendte kortark og kortets linje for posten (§4.2), så personvalget
    er menneskeligt og ikke udledt af automatik.
- **Skriver:** `source_persona` og `source_persona_mention` (rolle `primary`), nøgle = profilens `persona_key_prefix` ||
  `record_key`, indholds-id som 6b. **Ingen identitet.** Hændelsen gemmer målpersonen i `canonical_person_id` og en
  kvittering.
- **Køen:** personaen venter ikke på 6b's kontrol, men venter på identitetsafgørelsen i §4.2. Bygherren sikrer, at
  personaen ikke kan afgøres i webkøen mod en anden person end kortets, mellem persona- og identitetsskrivningen.
  **Afgjort (Task 0 trin 5):** begge skrives i samme ceremonitransaktion; ingen vagt. `red_source_persona_queue` viser
  ellers personaen som `proposed` (`persona_awaiting_control` er falsk).
- **Følgeændringer i den fælles writer:** hændelsens `operation`-CHECK, authorize' og finalize' tællenøgler og
  elementprefix samt `red_reimport_batch_result`'s lukkede lister (nøgler, antal, prefix, operation). En selektiv
  fortrydelse af operationen er *ikke* et krav (*mit valg*, som 6d-3): fortrydelse sker ved restore inden for vinduet
  (§6). De generelle fortrydelser afviser en *finaliseret* batch med operationen med
  `REIMPORT_WRITER_REVERSAL_INVALID` (`red_reverse_reimport` kræver en aktiveret batch med navnefuldendelses-barn;
  `red_reverse_reimport_publication` kun `publication_identity`); det testes. En *aktiveret* batch uden
  `person_create` (fx med et tomt navnefuldendelses-barn) kan i dag fejlagtigt meldes fortrudt af
  `red_reverse_reimport`, uden at dens indhold fortrydes. Det er en generel, eksisterende egenskab ved den fælles writer (backlog), som ikke ændres her;
  fortrydelse sker ved restore (§6).
- **Profil:** `daa-1939-publication-v1` bærer operationen (`persona_key_prefix` `1939:`, helpost-slags `person`); ingen
  ny profilrække (Task 0 trin 5).
- **Opgraderingstest:** CHECK- og signaturændringerne testes mod en base bygget fra prods skema før DDL'en (memory
  `signaturaendring-kraever-opgraderingstest`).

### 4.2 Identitet (eksisterende vej)

`red_afgoer_source_persona(persona, 0, 'same', person, note, {basis: 'human_sheet', sheet_sha256, rows_sha256,
line})` som i 6d-2a §4.4. Kortet viser bogposten (sidebillede og tekst), personens 1939-fakta, linket til 2018-20 og
den forkerte, tilbagetrukne tekst til sammenligning. Kortarkets form følger memory `kortark-kraever-kontekst-html` og
`menneske-gennemgang-token-fil`. Ét ark dækker både identitet (§4.2) og placement (§4.3).

### 4.3 Placement (eksisterende hjælpefunktioner)

`private.write_record_placement` og `private.write_persona_placement` (`principal_member`) som i 6d-1, med
`printed_number = NULL`. Linjeskemaets entry, overskriftsobservationen og `section_path`, slægtled og kuld foreslås
af bygherren efter 6d-1's regler og afgøres af projektejeren på kortet. Overskriftsvalidatoren
(`placement_header_violations(3)`) skal give 0 efter skrivningen.

**Forslag på kortet (Task 0 trin 1):** begge entry 57, `header_observation_id` = linjeoverskriften »Den holstenske
Linje.«, intet trykt nummer, `evidence.basis = 'human_sheet'`.

| | Henrik (934) | Iven (929) |
|---|---|---|
| `header_ids` | linje, slægtled »III.« | linje, kuld »Hr. Hartvig Reventlows Søn:« |
| `human_header_levels` | ingen | `["slaegtled"]` |
| `section_path` | `{header:21,header:2490}` | `{header:21,header:8514}` |
| slægtled / kuld | 3, »III« / ingen | 4, »IV A« / `Hr-Hartvig-Reventlows-Søn` |

»Til samme Generation, ikke Brødre, hørte:« er ikke en overskriftsobservation; Henrik står derfor under »III.« som
Volrad. »IV A.« findes heller ikke som observation (den ligger i hullet efter Claus' afkortede post), så Ivens
slægtled er menneskeangivet som i 43 andre 1939-placements.

- **Ledger:** legacy-rækkerne for 929 og 934 får version 2, `mapped`, med den nye placement gennem
  `private.record_legacy_disposition` (målt på stand-in).
- **Medlemskab (revideret efter Codex r1 fund 6):** `red_promote_placement_memberships` (`schema.sql:3124`) virker på
  hele kilden. **Medlemskab er obligatorisk:** rammer forhåndsvisningens `eligible`-mængde ikke præcis 929 og 934,
  stopper ceremonien uden at skrive. Grund: uden medlemskab for 929 bliver 944's oversigtsomtale stående ved siden af
  Ivens fulde tekst (to 1939-tekster i komponenten). Målt på stand-in: 528 `already_current`, og præcis 929 og 934
  bliver `eligible`; komponenterne [2,934] og [44,929,944] bliver `corroborated` uden dublet.
- **Revalidering:** ingen. Posterne har ingen publiceringer.

### 4.4 Kladden (eksisterende writer)

`red_upsert_person_narrative_record(person, 3, record_key, tekst, false, expected_state_sha256)` som redaktør (memory
`rpc-rollegate-kraever-jwt-claim-sub`); `app.change_set_id` nulstilles før hvert kald. Teksten er
`btrim((private.relation_fold_raw_text(<postens accepterede occurrence>.verbatim_text)).folded)` (6d-3's
profilfoldning; Task 0 trin 4): orddelinger, linjeskift og sidemarkør fjernes. Det svarer til de publicerede 1939-tekster
(foldet post uden løbenummer; posterne har intet). **Ingen OCR-rettelser i ceremonien:** dem laver projektejeren i redaktøren. Status efter
ceremonien: `draft`. Publiceringen er projektejerens egen handling i redaktøren, uden for ceremonien.

### 4.5 To narrativrækker pr. person og kilde

Kladden opretter en ny narrativrække. 598 og 603 består som tilbagetrukne legacy-rækker. Task 0 efterprøver mod
koden, at biografilæseren, oversigtsreglen (6d-2a), udgavevælgeren (6e-1), redaktørens narrativliste og
publiceringshistorikken tåler to rækker for samme person og kilde. Det skal også afgøres, hvad der sker, hvis nogen
fortryder `legacy_withdrawn` på 598 eller 603, efter at den nye tekst er publiceret: to 1939-tekster ville da være
synlige.

**Målt (Task 0 trin 3):** læserne v1/v2, redaktørens liste (nøgle `sourceId:recordKey`, legacy for sig) og historikken
tåler to rækker; klienterne viser hver række som egen version, så databasen er vagten. Fortrydelsen af
`legacy_withdrawn` gav to synlige 1939-tekster i begge rækkefølger (før og efter publiceringen), og Codex r1 fandt en
tredje vej (publicér → tilbagetræk den nye → fortryd legacy → fortryd tilbagetrækningen af den nye).

**Afgjort (projektejeren 2026-11-17): bred spærring.** `private.reverse_narrative_publication_event` afviser
fortrydelse af en `legacy_withdrawn`-hændelse med `NARRATIVE_LEGACY_RECORD_BINDING_EXISTS`, når personen har en
narrativ i samme kilde med en record-binding **i enhver status** (en tilbagetrukket eller kasseret binding beholder
sin række). Tjekket er en selvstændig sætning efter funktionens `LOCK TABLE public.change_set` (samme egenskab som
149b's `NARRATIVE_LEGACY_MIGRATION_BINDING_ACTIVE`). `red_person_narrative_publication_history`'s
`reversal_blocking_reason` får en tilsvarende arm, så fladen ikke tilbyder en knap, RPC'en afviser. Følge: 598/603's
tilbagetrækning er permanent efter ceremonien (kun restore eller en senere bevidst ændring). I prod rammer det i dag
kun 929 og 934 (1791 og 1795 har ingen record-binding).

## 5. Ikke-mål og anti-mål

- Ingen ændring af Claus (935) og Emeke (933), Volrads tekst 601 eller nogen postgrænse.
- Ingen nye personer, familier, fakta eller relationer. Ingen fortolkninger eller modelkørsel på de to poster.
- Ingen lempelse af den generelle narrativwriter eller publiceringsgaten.
- De øvrige 19 helposter uden tekst behandles ikke. Operationen skal kunne bruge dem senere, uden at specen lover det.
- 2018-20 uændret: placements, medlemskaber, publiceringer og koordinater byte-ens.
- **Anti-mål:**
  - en persona med identitet mod en anden person end kortets;
  - en publiceret tekst, som projektejeren ikke selv har publiceret;
  - en læser, der viser 598 eller 603 igen;
  - to synlige 1939-tekster for samme person;
  - et anon-kald, der bliver mere end 10 % langsommere.

## 6. Vejen til prod

Som 6d-2a i mindre skala: privat runner, dump før hver skrivende ceremoni (B1 + `age`-kopi), frys, vinduesvagt, GO pr.
ceremoni, fortryd ved restore, generalprøve fra operatørens cwd på en stand-in fra en frisk prod-dump-kopi.

- **DDL-ceremoni:** DDL'en er `db-migrations.sql`-halen fra separatorlinjen lige før blokken »Fuld personsletning
  (2026-11-14)« til filens slutning (personsletning #369/#377/#380 + record_persona: operationen fra §4.1,
  spærringen fra §4.5 og isolationsvagten i legacy-fortrydelsen) efterfulgt af `db-rls.sql`, i én transaktion.
  Opgraderingstesten kører netop den form fra basen `f37b294a` (prod-form-benet). I samme transaktion, efter hale og
  `db-rls.sql` og før verify, slettes note 72 (forældreløs, `target_type='family'`, `target_id=54`) under en
  forudsætning: den er den eneste forældreløse polymorfe række, og family 54 findes ikke (projektejerens afgørelse
  18/11). Fortryd-DDL anvender `db-rls.sql` fra basecommit (den nye nævner funktioner, restoren fjerner);
  fortryd-data den nye; begge sha-bindes i GO.
- **Dataceremoni** (efter projektejerens kortsvar): authorize og apply af de to persona-elementer, finalize,
  identiteter, placements, ledger og medlemskab, og de to kladder, i én transaktion. **Ethvert `N` eller ugyldigt svar
  stopper hele ceremonien før authorize** (ingen delvis skrivning). Efter finalize og før første identitet tager
  ceremonien `LOCK TABLE public.change_set IN ACCESS EXCLUSIVE MODE` (kodens orden record → audit → person; en
  resterende låsecyklus ender i 40P01 med fuld rollback). Pinnes på indhold: record keys, mention-id'er og -hashes,
  person-id'er og kortarkets sha, aldrig id'er oprettet af ceremonien (memory `pin-indhold-ikke-ceremoniens-id`).
  Ceremonien efterlader en kvittering.
- **Efter ceremonien:** projektejeren retter og publicerer de to kladder i redaktøren. Den publicering er ikke en del
  af fortrydelsesvinduet.
- **Mål før og efter:** `narrative_publication_state` for begge poster (fra `missing_identity` til `eligible`),
  `red_person_narrative_records` for 929 og 934, `placement_header_violations(3)`, KOORD- og paritetshashes som 6d-1,
  `public_person_facts` og biografilæseren for de offentlige personer (uændret indtil publiceringen) samt
  koordinatkaldets tid som anon.

## 7. Overladt til bygherren

Operationens navn og nøjagtige payload; kortformen; foldningsfunktionen; placementens værdier (forslag til kortet);
hvordan identitetsvinduet (§4.1, Køen) lukkes; testopdelingen; runnerens form.

## 8. Færdigbevis

- **Kæden:** Henriks og Ivens poster har hver én persona, en accepteret identitet (934 og 929), en accepteret record-
  og persona-placement, et gældende linje- og slægtsmedlemskab og en kladde. `narrative_publication_state` er
  `eligible` med `accepted_identity` umiddelbart før kladden og `existing_exact_binding` efter; personaens accepterede
  identitet peger stadig på kortets person.
- **Redaktøren:** begge poster står i redaktørens liste med kladden. Projektejeren kan rette og publicere dem.
- **Efter projektejerens publicering:** anon ser 1939-teksten på Hinrichs (2) og Iwans (44) side som 1939-udgaven med
  »DAA 1939, s. 9-10« og »DAA 1939, s. 10« (bogens trykte sidetal, som alle 1939-citater; Volrad på samme PDF-side har
  »s. 9«). 598 og 603 er stadig `withdrawn`, og fortrydelsen af deres tilbagetrækning afvises.
- **Synlige 1939-tekster:** 565 + 2 − 1. 944's korte omtale (narrativ 613, s. 91) bliver oversigtsomtale med detalje
  929 og vises ikke længere på Iwans side (6d-2a-reglen; godkendt af projektejeren 2026-11-17). Narrativet består.
- **Uberørte:** de øvrige 1939-publiceringer, `KOORD_2018_20`, `FAKTA`, 2018-20's paritetshashes og 6d-1's 528
  placements er uændrede; `KOORD_SRC` ændres kun for 929 og 934 (fra gamle nr. 6/11 til placementen). 0 personer med
  to synlige 1939-tekster.
- **Placement:** `placement_header_violations(3)=0`; `placement_human_header_levels(3)` = 103.

## 9. Task 0 (måling før planen låses)

1. 6d-1's regel for linjeskemaets entry, overskrift og `section_path` anvendt på de to poster. Findes »Til samme
   Generation, ikke Brødre, hørte:« som overskriftsobservation, eller skal Henrik placeres under nærmeste
   slægtledsoverskrift?
2. Ledger- og medlemskabsfunktionernes krav, og hvad de skriver for 929 og 934.
3. §4.5's læsere og fortrydelsen af `legacy_withdrawn`, målt mod koden og på en stand-in.
4. Foldningsfunktionens resultat på de to poster (vises på kortet).
5. Om `red_source_persona_queue` viser en persona fra den nye operation, og hvordan identitetsvinduet lukkes.

### 9.1 Resultat (2026-11-17, stand-in fra frisk prod-læsedump, sha256 `64ceddaa…`)

1. Placement: se §4.3's tabel. Prøveplacering gav `placement_header_violations(3)=0`.
2. Ledger: version 2 `mapped` for begge. Medlemskab: præcis 929 og 934 `eligible` (528 `already_current`); promovering
   gav 2; komponenterne `corroborated`.
3. Læsere: tåler to rækker. Fortrydelsen gav to synlige tekster → spærring (§4.5). Citat: »s. 9-10«/»s. 10« (§8).
   Ceremonien ændrer kun `KOORD_SRC` (`KOORD_2018_20`, `FAKTA`, `BIO` og oversigtsreglen uændrede); publiceringen
   ændrer `BIO` og oversigtsreglen (13 → 14: 944).
4. Foldning: `relation_fold_raw_text` + `btrim` (§4.4): Henrik 1.170 → 1.146 tegn, Iven 1.124 → 1.113.
5. Køen viser en persona uden identitet som `proposed`; vinduet lukkes af én transaktion (§4.1). Profilen
   `daa-1939-publication-v1` bærer operationen.

## 10. Reviewlog

### Bygherre-tjek (Opus, 2026-11-17)

Specens påstande er efterprøvet mod `schema.sql` og `web/` og holder:

- Persona-writeren kræver en publiceret binding.
- `persona_awaiting_control` ser kun `publication_persona`-hændelser.
- `red_afgoer_source_persona` tager `human_sheet` uden kandidatkørsel.
- `narrative_publication_state` bliver `accepted_identity` efter identitet og placements.
- Kladden opretter altid en ny narrativrække (§4.5's præmis).
- Én transaktion er mulig: kun narrativwriteren og medlemskabspromoveren åbner change sets, og promoveren lukker sit
  eget. Kladden skrives derfor sidst.
- Redaktøren åbnes på det rå person-id, så 929/934 kan nås uden webændringer.

Ét betinget spørgsmål: hvad hvis medlemskabspromoveringen rammer andre end de to? Afgjort som *mit valg* i §4.3
(spring medlemskab over og notér grunden), fordi projektejeren har afgrænset ceremonien til de to poster. *Omgjort
efter Codex r1 fund 6: medlemskab er obligatorisk.*

### Codex-runde 1 (`gpt-6.1-sol`, spec+plan+Task 0) med Opus-dom (2026-11-17)

11 fund, alle faktuelt korrekte; Opus dømte (projektejeren godkendte dommen):

| # | Fund | Dom | Rettelse |
|---|---|---|---|
| 1 | Spærring kun ved `draft|published` lader veje stå åbne | nødvendig | Bred spærring (§4.5) |
| 2 | `red_reimport_batch_result` mangler; fortrydelse | nødvendig + forenkl | Med i registreringen; eksisterende `REVERSAL_INVALID` testes (§4.1) |
| 3 | `expected_counts` mangler obligatoriske nøgler | forenkl | `{"person_creates":0,"source_evidence":0,"record_personas":n}` |
| 4 | Isolation for spærringen | afvis | Dækket: tjek efter `change_set`-låsen, READ COMMITTED |
| 5 | Låseorden/deadlock | forenkl | Auditlås efter finalize, før identitet (§6) |
| 6 | Valgfrit medlemskab vs. 944 | nødvendig | Obligatorisk medlemskab (§4.3), §8 = +2 −1 |
| 7 | `N`-svar modstridende | forenkl | Ethvert N stopper hele ceremonien (§6) |
| 8 | Fortryd-DDL og `db-rls.sql` | forenkl | Basecommits `db-rls.sql` ved fortryd-DDL (§6) |
| 9 | Opgraderingstestens bevis | forenkl | Base-tjek, CHECK-mængde, sha-liste (plan Task 3) |
| 10 | `authority_kind` efter kladden | forenkl | §8 skelner før/efter kladden |
| 11 | To eksterne id'er kan ikke etableres | nødvendig | Test uden id-række i kilden (plan Task 2) |

### Codex-runde 2 (diff) med Opus-dom (2026-11-18)

NO-GO med fire fund plus et testhul; Opus dømte, projektejeren godkendte dommen (18/11):

| # | Fund | Dom | Rettelse |
|---|---|---|---|
| 1 | Isolation: legacy-fortrydelsen håndhæver ikke READ COMMITTED; et ældre snapshot omgår bindingsspærringen (r1 fund 4 genåbnet) | nødvendig | Vagt `NARRATIVE_LEGACY_REVERSAL_ISOLATION` i legacy-grenen før `LOCK TABLE` + test (REPEATABLE READ, SERIALIZABLE, kontrol) |
| 2 | Batch-fortrydelse: en aktiveret batch kan meldes fortrudt uden indhold | generel egenskab, ingen kodeændring | §4.1 og testkommentaren præciseret (*finaliseret* batch); backlog |
| 3 | Koordinater: ceremoniens koordinathash læser redaktørvisningen | nødvendig | Anon-koordinathash ved siden af redaktørens (`T_RP_POST_KOORD_ANDRE_ANON`) + test |
| 4 | `printed_page` mangler i KOORD | nødvendig | Med i ceremoniens og målingens udtryk; paritetstest |
| 5 | Opgraderingstesten kører ikke prods form | nødvendig | Prod-form-ben: hale + `db-rls.sql` i én transaktion fra `f37b294a` (§6) |
