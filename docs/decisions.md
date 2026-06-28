# Beslutninger

Kun ikke-oplagte arkitektur-/design-valg. Detaljer i changelog + memory.

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
