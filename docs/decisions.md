# Beslutninger

Kun ikke-oplagte arkitektur-/design-valg. Detaljer i changelog + memory.

## Versionering + hyperlinks App-lag (2026-06-30)

**Escape-fix lagt på encode-siden (`makeToken`), ikke decode-siden (scanneren).**
Mit første fix-forsøg (H1) var at indsnævre scannerens backslash-gren til kun `\|[]`. Det løser
intet: `]` er legitimt eskaperet, så en ueskaperet trailing backslash sluger stadig afgrænserens
første `]` uanset hvor smal regex'en er — verificeret empirisk med en node-simulation af begge
varianter. Korrekt fix: eskaper `\` SELV i `makeToken`; scanneren forbliver uændret, fordi dens
ubegrænsede "backslash+næste-tegn=ét par"-logik er korrekt, NÅR encoderen garanterer at enhver
literal backslash altid er doblet. Generel læring: et escape-alfabet skal inkludere escape-tegnet
selv, ikke kun de tegn det beskytter.

**`reverteret`-status beregnes fra HELE historik-listen, ikke fra rækkens eget felt.**
`change_set.reverterer_id` på række R betyder "R fortrød hvilket sæt" — sat på det NYE
reversal-sæt, peger TILBAGE på det ORIGINALE. En original post X's eget `reverterer_id` forbliver
derfor NULL efter X er fortrudt. `mapHistRow` tager nu et `revertedIds`-sæt (alle `reverterer_id`-
værdier fra hele resultatet) som parameter, i stedet for at læse feltet direkte på hver række.

## Versionering + hyperlinks DB-lag (2026-06-30)

**`begin_change_set` wires i ALLE DML-skrive-RPC'er, inkl. de 4 opretter-RPC'er.**
Implementeringsplanens task-liste nævnte 17 RPC'er og udelod `red_opret_person/estate/kilde/
organisation`. Men `red_opret_person` kalder `red_upsert_fakta` nested — uden et change_set åbnet
i den YDRE opretter ville person-INSERT'en ikke logges, og de nestede kald ville åbne separate sæt
(spec-finding H1). Design-specens §6 ("Alle `red_*`") er den korrekte autoritet; planens liste var
en mangel. `red_suggest` (staging) og `red_slet_person_preview` (read-only) forbliver uwired.

**Restore-divergens-tjek dækker DELETE-inverse (ikke kun INSERT/UPDATE).**
Den optimistiske B9-kontrol skal sammenligne nuværende række mod den *post-state* sættet efterlod:
INSERT/UPDATE → `efter`, DELETE → SQL NULL (række skal være ABSENT). Den oprindelige plan-kode
tjekkede kun INSERT/UPDATE, så en genbrugt PK efter en sletning kunne overskrives blindt ved
fortryd. Dual-review-fund H1; rettet.

**`_version_upsert_row` lister kun snapshot-kolonner i INSERT/SET.**
Snapshot udelader skip_cols (`person.visning_*`, `profiles.email/rolle`). `(jsonb_populate_record).*`
ville sætte dem NULL ved restore → `profiles.rolle NOT NULL`-crash, og NOT NULL-tjekket fyrer FØR
ON CONFLICT-arbitrering, så det rammer selv ved UPDATE-restore af eksisterende række. Fix: eksplicit
kolonne-liste fra snapshot-nøgler → skip_cols får DEFAULT ved insert, bevares ved update. Dual-review
H2 (opgraderet fra LOW). Cache (`visning_*`) regenereres separat efter restore.

**TOCTOU i restore deferret bevidst.** `_version_current_row`-tjek + inverse-DML er ikke atomiske.
Acceptabelt under single-writer PoC (samme threat-model som `max(id)+1`-id-tildeling, spec §4.6);
genåbnes ved flerbruger-skrivning.

## TNG-QA: tre kerne-valg i match + QA (2026-06-30)

**Auto-tier = ambiguitets-margin, ikke `unique_block`.**
Næsten alle i basen hedder "Reventlow", så `unique_block` ("ene plausible navne-kandidat")
er ALDRIG sand → auto var altid 0. Valgt: auto kræver at bedste kandidat er ≥
`ambiguity_margin` (0.05) foran nr. 2 (+ score≥cutoff + top-kandidat). Kalibreret mod
*bootstrap-ankre* (entydige eksakte matches) i stedet for et håndlabelt facit-sæt — bevidst
hurtig-start; ankrene er korrekte pr. konstruktion, så de validerer ikke præcision uafhængigt
(non-anker-auto øjen-kontrolleres i `calibrate.R`). Forkastet: sænke `unique_block`-strenghed
(ville ikke skalere med uniform efternavn).

**Dato-overlap tæller kun som scoring-evidens ved reel dato på begge sider.**
`intervals_overlap` returnerer TRUE når begge datoer er ukendte (NA→±Inf), så et middelmådigt
navne-match fik 0.3 "gratis" vægt og kunne auto-promoteres på navn alene (fx forskelligt
efternavn, ingen datoer). `.overlap_evidence` kræver dato på begge sider. Konsekvens: auto
kræver reel fødselsårs-korroboration (navne-only maxer på 0.7). Bivirkning: dato-løse
nr.2-kandidater taber vægt → større margin → flere entydige auto (273→347).

**GDPR PII-gate = INPUT-gating, ikke output-gating.**
Filtrér ALLE sammenlignings-input (vores + TNG) til afdøde-ikke-private FØR sammenligning, så
ingen levende person kan komme ind i `disc` — heller ikke som relateret 2.-endepunkt. Reducerer
garantien til én kontrollerbar invariant frem for "hver refereret id på hver række blev tjekket".
KRITISK: TNG-siden filtreres OGSÅ (ellers navngiver `mangler_hos_os` en levende ægtefælle til en
afdød). Fail-closed på ukendt privacy. Forkastet: output-filtrering af `disc` + tekst-scan
(`assert_no_living_pii`) som primær — degraderet til backstop (svækkes når id'er → labels).

## Opret: privat FORCERET true + sted udskudt (2026-06-29, hærdet 2026-06-30)

**Ny person oprettes med `privat=true` — IKKE konfigurerbar ved opret.**
RLS-reglen `levende=false AND privat=false` gør personen anon-læsbar. En glemt levende-toggle
ville ellers publicere en nulevende person umiddelbart ved opret. Frem til cycle-08 var `p_privat`
en parameter med default `true`, men en crafted kald med `p_privat=false` kunne omgå beskyttelsen.
**cycle-08 (2026-06-30):** `p_privat`-parameteren fjernet helt — `INSERT` hardkoder `privat=true`.
Gammel 7-arg signatur DROPpet; ny 6-arg erstatter. Synlighed skiftes udelukkende via
`red_set_privat`. Ansvaret for synlighed placeres dermed eksplicit hos redaktøren.

**Gods-sted udskudt.**
`EntitetPicker` understøtter kun organisation/estate, og `redaktionAux` har ingen `placeListe`.
En sted-picker til gods kræver ny aux-datasektion og ny picker-komponent — ikke i scope for PoC.

## Plan 2C-2b: redigerbar familie-sektion — 5 nøgle-valg (2026-06-29)

**`red_slet_familie_link` sletter aldrig `family`-entiteten (Codex H1).**
`family`-tabellen bærer i gennemsnit 276 facts og 700 notes i nuværende load. Disse binder via
`(target_type='family', target_id)` — polymorfisk, ingen FK, ingen cascade-constraint. En
sletning af family-rækken ville efterlade al evidens forældreløs. RPC'en sletter KUN
`family_member`-rækkerne. En tom family (ingen members) er bedre end orphaned evidens;
fjernelse af en tom family kræver eksplicit audit og separat RPC.

**Ingen auto-dedup af unioner i `red_opret_union` (Codex H2).**
Et par (A, B) kan logisk have to selvstændige ægteskaber (fx skilsmisse + gengifte). En
pair-dedup (`WHERE partner_a=X AND partner_b=Y → returnér eksisterende family_id`) ville flette
børn og ægteskabs-events fra to distinkte tidslinjer ind i ét family-objekt. RPC'en opretter
ALTID en ny family-entitet + 2 partner-links. Ansvaret for at identificere et allerede
eksisterende ægteskab og vælge det korrekte family-objekt ligger i UI-laget / redaktøren.

**Cyklus-guard + selv-forælder-afvisning i `red_tilfoej_barn` (Codex H3).**
To separate afvisninger i RPC-laget (SECURITY DEFINER, ikke kun klient-lag):
(1) Selv-forælder: `p_barn_id` == en af familiens partnere → RAISE.
(2) Cyklus: recursiv CTE traverserer opad i slægtstræet fra `p_barn_id`; hvis nogen ane == en
af familiens partnere → RAISE.
Begge afvisninger er nødvendige i databaselaget — klient-side-guard alene kan omgås ved
direkte RPC-kald.

**`fetchPersonFamilie` separat fra `redaktionAux`.**
`redaktionAux` sammensætter familie-visningen til display (formaterede listestrenge), men
eksponerer hverken `family_member.konfidens` eller primærnøglerne (`family_id` + `person_id`)
som slet- og konfidens-kaldene kræver. Separat fetch mod `family_member`-tabellen var den eneste
korrekte løsning — omskrivning af aux-kontrakten ville bryde resten af editoren. Analogt med
2C-2a's valg af separat `fetchPersonRelationer`.

**Era-validering: klient-side advar-og-tillad.**
`eraAdvarsel` er en blød advarsel, ikke en hard-reject. Begrundelse: 27 af de eksisterende
familie-links i databasen er historisk inkonsistente (era-fejl fra DAA-parseren) — en
hard-reject ville blokere korrekt redigering af disse poster. Redaktøren modtager advarslen,
bekræfter og fortsætter. Hard-reject forudsætter at alle 27 era-fejl er rettet i basen.

**Live RPC-deploy + rollback-tests + manuel e2e er controller-gated.**
Samme model som tidligere plans: bruger-OK + backup (R/RPostgres) inden DDL kører mod prod.
App-siden er komplet og testet (121/121 jest, tsc rent); RPC'erne eksisterer endnu ikke i prod.

## Plan 2C-2a: redigerbar sektion-relationer — scope + nøgle-valg (2026-06-29)

**Redigerbart scope: kun relation-baserede hverv/godser; familie og kilder read-only.**
Familie (family_member) og kilder (external_id) er udeladt af 2C-2a. Familie-redigering
kræver separat semantik (opret familie-enhed, kobl forælder/barn, håndtér
`family_member.konfidens`) og er udskudt til plan 2C-2b. Kilder (external_id) kræver
opret-flow for nye source-entiteter. Begge deferred = bevidst scope-grænse.

**Separat `fetchPersonRelationer` frem for genbrug af `redaktionAux`.**
`redaktionAux` eksponerer relationer som formaterede listestrenge uden `relation.id`.
Slet-kaldet (`red_slet_relation`) kræver præcist `relation_id`. En separat pagineret
fetch (direkte mod `relation`-tabellen, filtreret på `subjekt_id`) var den eneste
korrekte løsning — genbrug af aux ville kræve en destruktiv omskrivning af aux-kontrakten
der bryder resten af editoren.

**`red_slet_relation` skal FK-ordne evidens-slettelsen manuelt.**
`relation`-tabellen har intet ON DELETE CASCADE til sin evidens: `assertion`, `conclusion`,
`citation`, `note` binder på `(target_type='relation', target_id)` — polymorft, uden FK.
RPC'en sletter i rækkefølge citation → conclusion → assertion → note → relation for at
undgå forældreløse evidens-rækker. (~955 evidens-rækker er knyttet til relationer i nuværende load.)
Løsningen er bevidst SECURITY DEFINER + rolle-gated (anon → P0001) som de øvrige red_*-RPC'er.

**`red_tilfoej_relation` validerer objekt_type og eksistens + dup-guard.**
Validering af `objekt_type` mod tilladt sæt og eksistens af `objekt_id` sker i RPC'en
(ikke i app-laget) — nødvendigt for at undgå FK-violation + meningsløse relationer ved
klientfejl. Dup-guard returnerer eksisterende `relation.id` ved gentagelse (idempotent),
ingen dublet indsættes.

**Live RPC-deploy + rollback-test + manuel e2e er controller-gated.**
Samme model som tidligere DDL-deploys: bruger-OK + backup inden DDL kører mod prod.
App-siden er komplet; RPC'erne eksisterer endnu ikke i prod.

## Plan 2C-1: entitetslister read-only via udvidet buildAux (2026-06-28)
Redaktions-appens Entiteter-tab viste kun personer (2A). 2C-1 gjorde den til en type-menu med
read-only lister over de øvrige entiteter.

**Ikke-oplagte fund/valg:**
- **RPC-fladen er person-centrisk.** Ingen write-RPC for source/organisation/estate/media/coat_of_arms
  → 2C-1 er nødvendigvis read-only; entitets-redigering kræver nye RPC'er (= 2C-3).
- **Datakilde: udvidet `buildAux`, ikke separate fetches.** De fire lister (kilde/org/medie/gods)
  kommer fra de rå arrays buildAux allerede modtager → ingen ekstra fetch. Kun `coat_of_arms` er nyt.
- **`majorat` er ikke en entitet** — det er en `slags` af `estate` (len/stamhus/lensgrevskab) og er
  dermed i gods-listen. (estate.slags er desuden NULL på alle 229 rækker nu.) Promovering til egen
  entitet = fremtidigt model-arbejde (jf. lineage-promoveringen).
- **`coat_of_arms` (våben) FINDES** — Codex fangede en fejlpåstand om at tabellen manglede; våben
  inkluderet.
- **Auth-state-kontrakt:** lister/menu skelner rolle≠redaktion ("Kræver redaktør") fra load
  ("Henter…") — ellers permanent "Henter…" for ikke-redaktører (Codex).

## Plan 2B: separat redaktion-MODEL frem for per-person re-derivation (2026-06-28)
Person-editoren lænede sig på den delte anon-model (893, uden levende) → "ikke fundet" for de 70
levende som 2A nu når. Det oprindelige design var en per-person `fetchRedaktionPerson(id)` der
re-deriverede familie/sektioner.

**Codex-review afslørede at re-derivationen ville DIVERGERE** fra den faktiske logik:
`buildModel` chrono-filtrerer umulige forælder-barn-kanter + vælger første fødselsfamilie;
`buildAux` klassificerer hverv som BÅDE organisation OG `historical_event` med specifik
format/sort. En forenklet re-implementering ville vise andre (flere/umulige) forældre og mangle
hverv ift. publikums-visningen.

**Beslutning: SEPARAT REDAKTION-MODEL.** Load én ekstra fuld model via redaktion-sessionen
(`loadFromSupabase({includePrivat:true})` → `buildModel`), gemt i en adskilt store-slice. Editoren
bruger de EKSISTERENDE selektorer/aux uændret → ingen divergens, pagination gratis (getAll), al
derivation genbrugt. Publikums-faner bruger uændret den offentlige model (ingen GDPR-læk).

**Konsekvenser:**
- To modeller side om side (offentlig 893 / redaktion 963). Lazy-loadet ved rolle=redaktion.
- `AppPerson.privat` tilføjet (toggle-init); `loadFromSupabase` får `includePrivat`-param.
- Narrativ-privat-fix (`fetchPersonNarrativ` = skrive-mål + bevar privat) — `red_upsert_narrativ`
  redigerer første narrativ uanset privat, så prefill skal læse SAMME række.
- Kun køn redigerbart i 2B; familie/sektion read-only (relations-redigering = 2C).

## Plan 2A: separat redaktion-person-fetch + pool-baseret søg (2026-06-28)
Redaktions-appen manglede in-app-navigation til personer (konflikt-køen tom efter kardinalitets-fix,
entitetslister stub) → man tastede URL → web-reload → skrivemode nulstillet. 2A gav Entiteter-tab'en
en person-liste.

**Ikke-oplagt valg: SEPARAT `fetchRedaktionPersoner` frem for genbrug af den delte model.**
Den delte publikums-model filtrerer `privat` ud (`load.ts:103`) OG loades ved boot som anon (kun
offentlige). Genbrug ville enten skjule levende/private for redaktøren ELLER (ved reload-med-private)
lække dem til publikums-fanerne (samme model). Separat fetch (RLS-gated, inkl. levende/privat) holder
GDPR-grænsen ren. Verificeret: redaktion ser 963, anon 893.

**Konsekvenser:**
- `buildSearch` → pool-baseret `searchPool` (DRY; publikum + redaktion deler søg/alfabet/sort-logik).
- Pagination obligatorisk (`getAll`/`.range`) — PostgREST capper ved 1000 lydløst (Codex 2A H1).
- `RedPerson.born` direkte fra visning_foedt, ikke aar-strengen (ellers dødsår-som-fødeår, Codex 2A M1).
- Tag på liste-rækker = `levende || privat` (de 70 skjulte er levende, ikke manuelt-private).

## Fact-kardinalitet: flere facts pr. (person, faktatype) er korrekt, ikke konflikt (2026-06-28)
Bruger-feedback under live-test: person 199 viste kun 1 titel, og konflikt-køen flagede
"6 uenige titel-værdier". Data-tjek: personen har **6 separate titel-facts** (kammerjunker,
konferensråd, kammerherre, gehejmeråd, gehejmekonferensråd, landråd i Holsten) — alle
legitime titler båret gennem livet, ikke konkurrerende påstande om samme forhold.

**Beslutning: en person kan have N facts af samme faktatype, og det er den korrekte model.**
Konsekvenser, rettet:
- **`red_konflikt`-view:** grain ændret fra `(person, faktatype)` til **pr. fact** — ægte
  konflikt = >1 distinkt assertion-værdi INDEN FOR ét fact (to kilder uenige om samme forhold).
  Efter rettelsen: 0 konflikt-rækker i nuværende load (alle facts har én oplysning) — den
  gamle kø var 100% falske positiver.
- **`joinEvidence` / person-editor:** `PersonEvidence.felter` er nu `Record<felt, FeltEvidens[]>`
  (liste pr. felt). Editoren viser ét kort PR. FACT under en felt-overskrift (titel → 6 kort).
  Tidligere overskrev `joinEvidence` pr. felt → kun det sidste fact var synligt.

**Write-side (løst 2026-06-28):** to nye RPC'er adskiller de to operationer som
`red_upsert_fakta`'s find-or-create blandede sammen:
- `red_tilfoej_oplysning(p_fact_id, …)` — operation A: ny oplysning til ET specifikt fact
  (per-kort "+ Tilføj oplysning"). Rører ikke conclusion (kandidat; vælg med red_set_konklusion).
- `red_opret_fakta(p_subjekt_type, p_subjekt_id, p_faktatype, …)` — operation B: ALTID nyt
  distinkt fact (sektion-knap "+ Ny titel"). Tillader flere facts pr. faktatype.
`red_upsert_fakta` (find-or-create) beholdes for R-load/bagudkomp, men UI bruger den ikke mere.

## Redaktions-UI: vertikal kerne-skive + 3 ikke-oplagte DB-valg (2026-06-27)
Redaktør-appens UI bygget som **vertikal kerne-skive** (dashboard + person-editor + konto +
3 sheets), ikke hele handoff-designet. Entitetslister, generisk record-editor, opret-flow og
relations/sektion-redigering udskudt til plan 2 — kerne-skiven validerer hele evidens-skrive-stien
end-to-end hurtigst. Køn-editor + familie/sektion-visning også udskudt (spec §6.2 ikke fuldt
indfriet; bevidst nedskaleret, bruger-godkendt).

**Tre ikke-oplagte DB-valg (Codex-review fangede dem som spec-fejl før impl):**
1. **`red_konflikt`-view kræver `security_invoker=true`.** Et alm. PostgreSQL-view kører med
   ejer-rettigheder og **omgår RLS** på fact/assertion → ville lække private personers konflikter
   til anon/medlem. security_invoker arver kalderens RLS. (GDPR, invariant #8.)
2. **Redaktion-read-RLS er nødvendig, ikke valgfri.** Den eksisterende `auth_read`-policy skjuler
   private rækker for ALLE authenticated. Uden en redaktion-specifik policy ville en redaktørs egen
   privat-toggle gøre personen usynlig for hende selv ved næste re-fetch (kan ikke ophæves). Løst med
   policy gated på `current_rolle()='redaktion'` (ikke `using(true)` — bevarer medlem-GDPR-laget).
   **Konsekvens:** en redaktør har fuldt indsyn i ALLE nulevende — bevidst privacy-udvidelse for rollen.
3. **Slet-advarsel skal hente indgående OG udgående relationer.** `red_slet_person` sletter
   relationer hvor personen er subjekt ELLER objekt, men app-modellen (`load.ts`) henter kun subjekt.
   Egen `red_slet_person_preview`-RPC spejler RPC'ens slette-logik 1:1, så advarslen ikke underrapporterer.

**Blød/mutabel assertion bevaret** (arvet fra 2026-06-26-spec): redigér=UPDATE, slet=DELETE bryder
invariant #1 (uforanderlighed), men er bevidst PoC-valg m. reversibel migrationssti i RPC-kroppen.

## Slægtslinje promoveret til entitet `lineage` — (a) nu, (b) senere (2026-06-23)
Linjer var bare et `linje`-label på `person_external_id`. Et label kan ikke bære navn,
våben, adlingsdato eller forgrening. CLAUDE.md §9 + datamodel-oversigt §5 forhåndsgodkendte
en promovering ("kan promoveres hvis branch-niveau-udsagn ønskes"); behovet for navne
(og i andre slægter: linjer der adles → nye adelsfamilier) udløser den.

**Valg: minimal entitet nu, ikke fuld udbygning.** `lineage` oprettes med kun
`(id, source_id, kode, navn)` — trin (a), navngivning. Bevidst IKKE bygget endnu:
`parent_lineage_id` (forgrening), `status`, `fact subjekt_type='lineage'` (adling/floruit/
alternative navne m. evidens), `relation` til våben/kilde/person. Det er trin (b).

**Hvorfor det ikke bryder invariant #2** ("nye behov = rolletyper, ikke tabeller): en
linje er en ny *slags ting* med egen identitet, ikke en ny måde at forbinde på. Label-
løsningen brød netop sammen ved "adlet gren → ny familie".

**Hvorfor (a) ikke maler os i et hjørne:** (a) skaber SAMME tabel som (b) bruger, bare
med færre kolonner. (b) er ren `ALTER ADD COLUMN` + nye relationer — nul rename, nul
data-migration. Det rå `linje`-token på `person_external_id` bliver liggende som join-nøgle
og proveniens (mapper til trykt side). Backfill udleder `source_id` fra data, så den binder
til den faktiske DAA-source uanset id. App falder tilbage til `Linje {kode}` hvis navn mangler.

## boern udledes deterministisk; boern.linje er IKKE JSON-linjen (2026-06-17)
Børne-referencer ("3 børn: Tiende slægtled, II, nr. 31-35") parses deterministisk i
`validate.py` (`derive_boern`), ikke af LLM-trinnet — LLM'en missede dem systematisk
(Codex-udtræk: kun 38/123 fanget). Teksten er regulær; deterministisk kode er fejlfri.

**aegteskaber-udtræk er stadig LLM (åben):** Modsat boern parses ægteskaber af
LLM-trinnet — og det misser ~9% (26/288 poster har "Gift" i narrativ men tom
`aegteskaber`, fx V-106 Christian Benedictus' ægtefælle Sophie Pauline Schjær).
Børn loades alligevel (deterministisk boern), men deres familie får ingen partner.
**Anbefalet fix:** løft ægteskabs-klausulen til deterministisk parsing i `validate.py`
(som boern). Klausulen er regulær ("Gift [dato] [sted] med Navn (F.: forældre),
* fødsel, † død") men rigere end boern (ordinaler, 1°/2°, skilsmisse, b.v.,
ægtefælle-forældre) → mere regex-arbejde. Ikke implementeret.

**Kryds-gren-tvetydighed (åben):** Romertallet i børne-ref ("…, II, nr. 31") er bogens
INTERNE gren-tæller i slægtleddet, IKKE JSON-linjen (I-V). Det matcher JSON-linjen ~85%,
men `nr` genbruges på tværs af 133 linjer, så i 145 tilfælde findes barn-nr i BÅDE
"stated" og forælder-linje. Loaderen (`load_daa.R`) vælger stated først → 97 verificerede
fejl (stated-kandidat historisk umulig, hundreder af år fra forælder), 38 ægte kryds-gren
(stated korrekt), ~10 uklare. **Anbefalet fix:** era-baseret tie-break — afvis stated hvis
kandidatens fødselsår er >80 år fra forælderens; ellers behold stated. Påvirker kun ældre
linjer I/III (Reventlow-hovedlinje V er entydig). Ikke implementeret endnu.

## Import: DAA-PDF først, TNG kun enrichment (2026-06-15)
Databasen bygges fra den trykte DAA (autoritativ, kohærent kilde), ikke fra TNG-dumpet
(25k personer, blandede tredjeparts-kilder → ville forurene grundlaget). TNG bliver
senere "flere påstande fra en svagere kilde"; konklusionslogikken foretrækker DAA.
Hver DAA-udgave = én `source`; identitetssammenkædning pragmatisk i PoC.

## Selektiv struktur — kun genealogisk rygrad (2026-06-16)
Rygrad = navn/titel/fødsel/dåb/død/begravelse/floruit/ægteskab/forældre-børn/godser/
adling/dekoration. **Erhverv + uddannelse er IKKE rygrad** — de ligger i prosaen
(narrativ for nummererede personer; bio-note for ægtefæller uden post). Begrundelse:
de forbinder ikke entiteter og driver ikke træet (§6). Overvejet/forkastet: strukturere
karriere som fakta for alle (kræver dyrt re-udtræk, lille genealogisk gevinst).

## Titel ≠ navn; flere navne-former = påstande (2026-06-16)
Titel ("Greve") er eget `titel`-fakta, aldrig bagt ind i navnet; display komponerer.
Samme person nævnt flere steder = flere navne-påstande; konklusion vælger kanonisk.
Relative datoer (s.å./s.m.) opløses til ISO ved udtræk, rå tekst bevaret.

## Bulk-insert frem for row-by-row (2026-06-16)
Loaderen akkumulerer i hukommelsen og skriver per tabel med dbAppendTable/COPY i
FK-rækkefølge. Row-by-row over session-pooleren var både langsomt (30+ min) OG
skrøbeligt (forbindelsen droppede → rollback). Bulk = ~14 sek + kort transaktion.

## Load-laget som deterministisk normaliserings-trin (2026-06-16)
Kategoriserings-/dedup-regler (estate-dedup, child-linje-fallback, akademisk-grad-
klassificering) anvendes ved load på hele datasættet i én 14-sek reload — frem for
dyrt LLM-re-udtræk. Udtrækket fanger rå-værdien; loaderen pålægger struktur.

## Model-tier: Sonnet til udtræk; Haiku afprøvet (2026-06-16)
Sonnet til stamtavle-udtræk (klarer tredjeparts-fælder, dense biografier). Haiku
testet: rammer genealogisk rygrad tæt, men taber på klassifikations-nuancer (karriere
vs embede) og er flakier. Forkastet for fuld kørsel efter clobber-fejl; egnet til
billig broaden HVIS isolerede output-mapper + terse output.
