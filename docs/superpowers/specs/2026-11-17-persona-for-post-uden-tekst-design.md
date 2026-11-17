# Delspec — persona for en helpost uden tekst; Henrik og Iven (1939) får deres egen tekst

**Status:** **godkendt af projektejeren 2026-11-17** efter brainstorm og bygherre-tjek (§10). Projektejerens
afgørelser står i §3; mine valg er markeret *mit valg*.
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
  personaen ikke kan afgøres i webkøen mod en anden person end kortets, mellem persona- og identitetsskrivningen. Det
  sker enten ved at skrive begge i samme ceremonitransaktion eller med en vagt.
- **Følgeændringer i den fælles writer:** hændelsens `operation`-CHECK, authorize' og finalize' tællenøgler og
  elementprefix, samt fortrydelsens operationsliste. En selektiv fortrydelse af operationen er *ikke* et krav (*mit
  valg*, som 6d-3): fortrydelse sker ved restore inden for vinduet (§6). Kalder en generel fortrydelse en batch med
  operationen, skal den stoppe med en eksplicit fejl.
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

- **Ledger:** legacy-rækkerne for 929 og 934 får en ny version `mapped` med den nye placement gennem den eksisterende
  ledgerfunktion, hvis 6d-1's regel tillader det; ellers registreres grunden.
- **Medlemskab og B6 (*mit valg*, efter bygherre-tjekket):** `red_promote_placement_memberships` (`schema.sql:3124`)
  virker på hele kilden og kan ikke begrænses til to personer. Task 0 kører forhåndsvisningen på en stand-in. Rammer
  den præcis 929 og 934 uden konflikt, køres den i ceremonien. Rammer den andre personer eller fejler den (fx
  `PLACEMENT_MEMBERSHIP_FOREIGN_SOURCE`), springes medlemskab over, og grunden noteres i kvitteringen og i
  `decisions.md`. Medlemskab er ikke en forudsætning for tekstbindingen, og ceremonien må ikke vokse ud over de to
  poster (§3 pkt. 3).
- **Revalidering:** ingen. Posterne har ingen publiceringer.

### 4.4 Kladden (eksisterende writer)

`red_upsert_person_narrative_record(person, 3, record_key, tekst, false, expected_state_sha256)` som redaktør (memory
`rpc-rollegate-kraever-jwt-claim-sub`). Teksten er bogpostens `verbatim_text`, foldet med samme regel som 1939's
øvrige tekstfoldning (`private.relation_fold_raw_text` eller 6d-3's profilfoldning; bygherren vælger og dokumenterer).
Sidemarkøren fjernes. **Ingen OCR-rettelser i ceremonien:** dem laver projektejeren i redaktøren. Status efter
ceremonien: `draft`. Publiceringen er projektejerens egen handling i redaktøren, uden for ceremonien.

### 4.5 To narrativrækker pr. person og kilde

Kladden opretter en ny narrativrække. 598 og 603 består som tilbagetrukne legacy-rækker. Task 0 efterprøver mod
koden, at biografilæseren, oversigtsreglen (6d-2a), udgavevælgeren (6e-1), redaktørens narrativliste og
publiceringshistorikken tåler to rækker for samme person og kilde. Det skal også afgøres, hvad der sker, hvis nogen
fortryder `legacy_withdrawn` på 598 eller 603, efter at den nye tekst er publiceret: to 1939-tekster ville da være
synlige. Bygherren afgør, om fortrydelsen skal spærres, eller om det dokumenteres som en kendt redaktørhandling.

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

- **DDL-ceremoni:** operationen fra §4.1, `db-rls.sql`-grants og opgraderingstesten, i én transaktion.
- **Dataceremoni** (efter projektejerens kortsvar): authorize og apply af de to persona-elementer, finalize,
  identiteter, placements, ledger og medlemskab, og de to kladder, i én transaktion. Pinnes på indhold: record keys,
  mention-id'er og -hashes, person-id'er og kortarkets sha, aldrig id'er oprettet af ceremonien (memory
  `pin-indhold-ikke-ceremoniens-id`). Ceremonien efterlader en kvittering.
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
  og persona-placement og en kladde. `narrative_publication_state` er `eligible` med `accepted_identity`.
- **Redaktøren:** begge poster står i redaktørens liste med kladden. Projektejeren kan rette og publicere dem.
- **Efter projektejerens publicering:** anon ser 1939-teksten på Hinrichs (2) og Iwans (44) side som 1939-udgaven med
  »DAA 1939, s. 498-499« og »s. 499«. 598 og 603 er stadig `withdrawn`.
- **Uberørte:** de øvrige 1939-publiceringer (565 synlige), 2018-20's paritetshashes og 6d-1's 528 placements er
  uændrede. 0 personer med to synlige 1939-tekster.
- **Placement:** `placement_header_violations(3)=0`.

## 9. Task 0 (måling før planen låses)

1. 6d-1's regel for linjeskemaets entry, overskrift og `section_path` anvendt på de to poster. Findes »Til samme
   Generation, ikke Brødre, hørte:« som overskriftsobservation, eller skal Henrik placeres under nærmeste
   slægtledsoverskrift?
2. Ledger- og medlemskabsfunktionernes krav, og hvad de skriver for 929 og 934.
3. §4.5's læsere og fortrydelsen af `legacy_withdrawn`, målt mod koden og på en stand-in.
4. Foldningsfunktionens resultat på de to poster (vises på kortet).
5. Om `red_source_persona_queue` viser en persona fra den nye operation, og hvordan identitetsvinduet lukkes.

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
(spring medlemskab over og notér grunden), fordi projektejeren har afgrænset ceremonien til de to poster.
