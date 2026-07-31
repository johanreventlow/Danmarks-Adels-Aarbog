# Replay-design: source-scoped replace (#123)

**Status:** Besluttet 2026-07-30 (bruger valgte modtil (b) efter helhedsreview).
**Kontekst:** `docs/reviews/helhedsreview-redaktoer-import-muligheder-2026-07-30.md`
Tema A + issue #123. Implementering er IKKE startet — dette dokument er
designsessionens leverance.

## Problemet

Import-laget og redaktør-laget er to adskilte skriveverdener. Loaderen kan kun
append (dubletter ved gen-load) eller `--reset` (TRUNCATE). Alt redaktionelt
arbejde (samme_som-links, sletninger, narrativ-patches) er nøglet til
person-id'er som en reload regenererer — re-ekstraktion kan derfor ikke loades
uden at ofre redaktionsarbejdet. Kun `red_ret_ocr_felt` overlever (journal på
`(import_key, record_key)`).

## Beslutningen: (b) source-scoped replace

Reload **bevarer person-id'er**. Loaderen matcher hver ny post til den
eksisterende person via `record_key` og erstatter kun de rækker kilden ejer;
redaktionelle rækker er nøglet til person-id og består automatisk.

**Fravalgt (a) generaliseret journal** (alle `red_*`-operationer får
reload-invariante ankre + afspilning): ville kræve ændring i ~60 RPC'er samt
migration af de eksisterende samme_som-change_sets fra person-id til stabile
ankre. (b)'s forudsætninger er derimod netop færdigbygget: identitetsregisteret
er komplet (514/514 aktive med trykt adresse, `book_post_id` = artefaktets
`record_key`), reconcile-maskineriet med fire udfald findes og er
perturbationstestet, og alle poster er nummer-krydstjekkede.

## Mekanik

Ny load-mode `--replace <source>` (afløser reset/append ved re-load af en
eksisterende udgave):

1. **Gate:** kræver grønt gate-manifest (#126). Reset-vejen består som nød-flow
   (#124: tømmer nu også change_set/change_event). navn≠ref-guarden (#125) er
   aktiv i replace-mode som i alle modes.
2. **Match-fase:** `reconcile(register, nye_poster)` → fire udfald:
   - **Entydig:** person-id bevares; source-ejede rækker erstattes (se §Ejerskab).
   - **Tvetydig:** STOP — menneskelig afgørelse (om-nøglings-præcedens; slutark).
   - **Ny:** opret person som i dag + mint id i registeret.
   - **Bortfalden:** markér i rapport, slet ALDRIG automatisk (register-princip:
     bortfald kan lige så vel være segmenteringsfejl som ægte sletning).
   Tombstonede `book_post_id`'er må aldrig genindsættes (2.11-præcedensen).
3. **Replay af OCR-rettelser:** `import_korrektion`-overlay uændret (eksisterende
   mekanisme, allerede uden for reset).
4. **Efterverifikation (blokerende):** antal redaktionelle rækker
   (change_event-loggede assertions, samme_som-relationer, red_-narrativer) er
   IDENTISK før/efter replace; db-verify-asserts grønne.

## §Ejerskab: hvad må replace røre?

**Source-ejet (slettes + genindsættes pr. matchet person):** facts + deres
assertions/citations/conclusions med citation → den re-loadede source og uden
change_event-spor; narrativ for den source; relationer/familie-struktur oprettet
af loaderen for den source.

**Redaktionelt (røres ALDRIG):** enhver række med change_event-spor,
samme_som-relationer, red_-narrativ-patches, suggestion, bogmærker, profiles.

Afgrænsningen "har change_event-spor" er den maskinelle diskriminator — den
forudsætter at versioneringshistorikken er retvisende, hvilket #124 netop har
sikret (historik overlever ikke længere id-genbrug).

### Empiri fra dry-run-matchrapporten (2026-07-31, replace_dryrun.R)

Match-tilstanden er PERFEKT: 515 artefaktposter → 514 entydige + 1 tombstonet
(2.11), 0 huller/nye/bortfaldne, 0 tombstonede nøgler i prod. Tre designfund:

1. **Narrativ-undtagelsen (ændrer diskriminatoren):** alle 514 source-3-
   narrativer bærer red-spor — de blev patchet ind via `red_upsert_narrativ`
   (Calamari-kørslen 2026-07-29). Spor-diskriminatoren dur derfor IKKE for
   `narrative`: udgave-narrativer er source-ejede UANSET spor og erstattes af
   re-ekstraktionens (bedre) tekst. Kun narrativer for ANDRE sources røres ikke.
2. **Konflikt-klassen er tom:** 0 af 1.963 fakta har red-spor — ingen source-
   ejede rækker er efterredigeret. Replace-logikkens sværeste tilfælde
   (redaktionel konklusion oven på udskiftet påstand) findes ikke i data i dag;
   klassen skal stadig håndteres (fail-closed: STOP hvis den dukker op), men
   kræver ingen flette-logik i v1.
3. **Familie-grafen:** 670 kanter, 0 med red-spor på kanterne selv; kun 1
   familie med redaktionelt ændret medlemsliste; 296 gift-ind-stubs (uden
   external_id). Trin 4's design kan behandle stub+kanter som source-ejede med
   én undtagelsesliste (den ene familie) frem for generel flette-logik.

samme_som (450) + ikke_samme_som (3) har alle red-spor som forventet — de
består automatisk fordi person-id'erne bevares.

## Forudsætninger (rækkefølge)

0. **record_key-backfill i prod: ✅ ALLEREDE OPFYLDT** (verificeret empirisk
   2026-07-31): prods 514 `person_external_id.record_key`-rækker for source 3
   er en eksakt 1:1-afspejling af registerets 514 aktive `book_post_id`'er
   (0 afvigelser i begge retninger, mængde-tjek via psql). 2018-20's 591 rækker
   har alle `record_key` (filnavns-nøglede). Den gamle "591/1733"-observation
   talte personer HELT uden external_id-række — gift-ind-stubs, som replay
   alligevel behandler som source-ejede. Intet backfill-arbejde nødvendigt.
1. **IDENTITY-migration** (review 24 fund 15 / RED-8): `max(id)+1`-allokering
   skal væk før replace-mode — replace åbner for gentagne loads og dermed flere
   samtidige skrivere mod samme id-rum.
2. **Match-rapport (dry-run):** `--replace --dry-run` udskriver fuld
   udfalds-fordeling + diff-oversigt FØR noget skrives. Første leverance —
   giver empirisk facit for §Ejerskab-afgrænsningen inden der bygges skrive-kode.
3. **Replace af person-scoped data** (facts/narrativ) — mindste farlige skive.
4. **Familie-graf-replace** — sværest: family/family_member er delt struktur
   (gift-ind-stubs, børne-tilknytninger). Egen designrunde når trin 3 er
   verificeret mod den lokale prod-kopi ([[lokal-db-testbase]]-mønstret).

### Kendte v1-begrænsninger (fra sol-review-cyklussen 2026-07-31)

- **OCR-journal vs. konfliktguard:** `red_ret_ocr_felt` logger assertion-events;
  når en OCR-rettelse rammer en source-ejet fact, vil konfliktguarden STOPPE et
  senere `--replace` (fail-closed, ikke datatab). Journalen replayes ganske vist
  ovenpå — men guarden kan ikke vide det. Løses ved behov med et flette-design
  der fritager assertion-events fra `red_ret_ocr_felt`-change_sets hvis feltet
  er journal-dækket. Empirisk tomt i dag.
- **Op til 4 dublet-fakta:** de ikke-source-ejede fakta fredes OG artefaktets
  version genindsættes — accepteret v1-risiko, rapporteres af loaderen.
- **GO-betingelser før ægte prod-kørsel:** grønt manifest uden `--force-gate`
  + destruktiv integrationstest mod lokal prod-kopi.

## Åbne spørgsmål (til implementeringssessionerne)

- Familie-ejerskab: en union med redaktionelt tilføjet medlem — er familien så
  redaktionel? (Foreslået: familien består, kun loader-oprettede medlemmer
  gen-matches.)
- samme_som til en bortfalden person: linket består (personen slettes ikke),
  men skal flages i match-rapporten.
- 2018-20-artefaktets record_keys er filnavns-baserede (`linje-nr`) uden
  register — skal 2018-20 have eget identitetsregister før replace kan bruges
  på den udgave? (Foreslået: ja, men først når 1939-flowet er bevist.)
