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
  **✅ BEGGE OPFYLDT 2026-07-31:**
  - *Destruktiv test:* frisk prod-dump (1:1 på 8 nøgletal) → skarp `--replace`
    mod lokal kopi: 514 matchede/1 tombstonet skippet/0 bortfaldne; 1604
    source-ejede rækker × 4 tabeller erstattet; **uafhængigt før/efter-snapshot
    (md5 over samme_som, change_event-sum, person-id-rum, family_member,
    andre-sources-narrativer, bookmarks) 100 % identisk**; person-id'er bevaret
    (stikprøvet via record_key); 0 genoplivede historik-id'er (nye fakta starter
    ved 6837 = over gulvet); R-suiten 543/543 inkl. DB-smoke. Gentaget dry-run
    efter replace viser fixpoint (1608→1608 — de 4 dublet-fakta er source-ejede
    efter første kørsel).
  - *Manifest:* convert_1939 skriver nu gate-manifest (commit 836c1af);
    clean_1939.json har grønt manifest (515/515 rene) — gate GRØN uden
    `--force-gate`, verificeret mod loaderen.
  - *Sekvens-gulv-migrationen* rehearset lokalt OG **APPLIED TIL PROD samme
    dag** (fact 6836→6837, eneste kollision; efterverificeret: alle 25
    sekvenser over gulvet, 0 brud). **Alle forudsætninger for ægte
    prod-replace er hermed på plads.**

## Trin 4-design: familie-graf-replace (2026-07-31)

Empiri fra den lokale prod-kopi (post-trin-3): 315 familier med 1939-medlem =
296 × (1 hovedperson + 1 navngiven stub, 286 barn-kanter) + 19 × (1 hovedperson
alene — parkerings-/default-unioner, 69 barn-kanter). 0 hovedperson↔hovedperson-
unioner. **209 af 296 stubs bærer redaktionelle samme_som/ikke_samme_som-links**
(tvær-udgave-ægtefælle-matchning) + 4 person-change_events på stubs → **stubs
kan ALDRIG slettes/genoprettes; deres person-id er redaktionel valuta.**
Kun 1 familie har change_event-spor på medlemslisten (kendt fra dry-run).

**Princip: strukturen (family-id, stub-person-id) genbruges via match;
indholdet (family-fakta, stub-fakta, noter, barn-kanter) erstattes.**

1. **Kortlægning pr. matchet hovedperson:** eksisterende partner-familier →
   `(family_id, stub_id, stub_navn, ordinal, har_red_spor)`.
2. **Union-match:** artefakt-ægteskab ↔ eksisterende union via normaliseret
   partnernavn (split_title-rest — samme princip som `match_barn_union`:
   partnernavn primær, ordinal kryds-tjek). Tvetydighed (to unioner, samme
   partnernavn) = STOP fail-closed.
3. **Matchet union:** family_id + stub_id genbruges; source-ejede family-fakta-
   kæder, family-noter og stub-fakta (navn/titel/fødsel/dåb/død) erstattes;
   ordinal opdateres.
4. **Umatchet artefakt-ægteskab:** ny familie + ny stub (som append-flowet).
5. **Bortfalden union:** består + rapporteres — aldrig auto-slettet
   (register-princippet; en bortfalden union med samme_som-stub er ellers
   datatab af redaktionsarbejde).
6. **Barn-kanter:** source-ejede (uden change_event-spor) slettes og genopbygges
   fra artefaktet mod de genbrugte/nye family_ids; kanter med spor fredes
   (skip-hvis-findes beskytter mod PK-kollision når artefaktet genindsætter
   en fredet kant).
7. **Parkerings-unioner (ingen stub):** ingen id-valuta at bevare → slettes
   som source-ejede og genopstår ved behov under genopbygningen.
8. **Fredning:** familie med change_event-spor på family/family_member er
   redaktionel — hele familien springes over (indhold urørt) og rapporteres;
   artefaktets tilsvarende union behandles da som bortfalden-i-spejl (ingen
   dublet-oprettelse: matchede fredede unioner tæller som matchede).

**Udvidet efterverifikation (blokerende):** samme_som/ikke_samme_som-mængden
byte-identisk; alle stub-id'er med samme_som eksisterer fortsat og har fortsat
en partner-kant; fredede kanter uændrede; change_set/change_event-antal
uændret; EXCLUDE-invarianten (én fødselsfamilie pr. barn) holder.

**✅ SOL-GO 2026-07-31** efter tre adversarialer runder (commits 77d2aa2 →
b2f47d5 → 50d58fc): (1) positivt familie-ejerskab, to-grenet — MED evidens
kræves alt fuldt citeret mod denne source; UDEN evidens kræves positivt
proveniens-bevis pr. ikke-matchet medlem (fremmed external_id diskvalificerer;
extid-løse skal have ≥1 fakta-citation mod denne source og ingen fremmed —
personer uden proveniens fredes fail-closed). Begge omgåelsesklasser bevist
lukket med injicerede syntetiske legacy-familier. (2) Artefakt-navnedubletter
uden parvis distinkte ordinaler fail-closes up-front (kørsel-uafhængigt).
(3) NA-navne-sikring i alle match-sammenligninger. 582/582 tests.

**✅ IMPLEMENTERET + DESTRUKTIVT TESTET 2026-07-31** (commit 53fd921):
match_replace_unioner (DB-fri, testdækket) + replace-familie-fase i loaderen.
Skarp kørsel mod lokal prod-kopi: 295 unioner genbrugt (id-stabile stubs),
19 parkeringer genopbygget, 1 fredet sprunget over, 0 bortfaldne; uafhængigt
md5-snapshot (stub-id'er, samme_som, 2018-20-graf, narrativer) 100 % identisk;
0 dobbelt-fødselsfamilier; fixpoint ved genkørsel. 569/569 tests.
To fund fra testen: (1) Iven-casen (I-72: to hustruer begge 'Margarethe
Rantzau') krævede navn+ordinal-fase før navn-alene; (2) pmap var
record_key-nøglet men pass 2 slår linje-nøglet op — latent brud for alle
UUID-nøglede artefakter, også i append; rettet til altid-linje-nøgle.

## Åbne spørgsmål (til implementeringssessionerne)

- Familie-ejerskab: en union med redaktionelt tilføjet medlem — er familien så
  redaktionel? (Foreslået: familien består, kun loader-oprettede medlemmer
  gen-matches.)
- samme_som til en bortfalden person: linket består (personen slettes ikke),
  men skal flages i match-rapporten.
- 2018-20-artefaktets record_keys er filnavns-baserede (`linje-nr`) uden
  register — skal 2018-20 have eget identitetsregister før replace kan bruges
  på den udgave? (Foreslået: ja, men først når 1939-flowet er bevist.)
