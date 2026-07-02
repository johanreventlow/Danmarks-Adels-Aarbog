# Review 12 — Koncept, datamodel og implementering (go/no-go før skalering)

**Dato:** 2026-07-02
**Metode:** Seks parallelle read-only review-agenter (datamodel/schema, RLS/sikkerhed, mobile, web, R-pipelines, UI/UX) + tværgående syntese. Prod-tilstand efterprøvet read-only via Supabase security-advisors + katalog-SQL. Ingen projektfiler ændret; ingen DB-skrivninger.
**Scope:** Primært teknisk inkl. UI/UX (findbarhed + redigerings-dækning). GDPR kun som teknisk mekanik. Forretningsmodel/drift uden for scope.
**Evidens:** Alle fund markeret [verificeret] / [antaget] / [usikker]. Kendte, allerede dokumenterede issues (reviews 09-11, decisions.md) gentages ikke som nye fund, men indgår i risikovurderingen med reference.

---

## 1. Executive summary

**Konklusion: Betinget GO.** Konceptet er stærkt, og datamodellen er solid — alle seks del-reviews landede uafhængigt på samme vurdering: *problemerne er implementeringsgæld, ikke designfejl*. Evidenslaget (påstand/konklusion) er reelt implementeret og håndhævet, ikke kun beskrevet; slægtskabsfinderen — kerneproduktet — er bygget, gennemtestet og respekterer konfidens-invarianten; traversal-mønstrene er indekseret og holder strukturelt ved 50k+ personer.

**Men skalering er i dag blokeret af fire hårde forhindringer**, som hver især udløses af et konkret skalerings-trin:

| Udløses af | Blokker |
|---|---|
| **I dag (uafhængigt af skalering)** | Prod-sårbarhed: `anon` har fulde skriverettigheder på `version_pk_registry` (verificeret i prod) — kan forgifte logning og knække fortryd. + anon-eksekverbar synligheds-oracle. |
| **Slægt #2** | Loaderen kan ikke appende: default-reset TRUNCATE'r 17 tabeller (destruerer redaktionsdata), og `--no-reset` er brudt (id-allokering læser aldrig MAX(id)). Der findes ingen fungerende vej til at loade en ny slægt. |
| **Redaktør #2** | `max(id)+1`-id-tildeling i alle skriveveje inkl. selve audit-loggen → duplicate-PK-fejl ved samtidige skrivninger. |
| **50.000 personer** | App-arkitekturen henter hele databasen klient-side og bygger grafen i memory (×2 for redaktører) — boot-tid og memory vokser lineært; O(n·m)-hotspot i buildModel rammer først. |

Dertil to strukturelle huller der skal designes (ikke kun fixes) før multi-slægt: **person-merge/`same_as`** (uden den giver "er vi i familie?" falske negativer på tværs af slægter — præcis dér hvor produktet skal bevise sig) og **medlemsverifikation + samtykke-granularitet** (uden dem er levende-laget reelt offentligt for enhver selv-oprettet konto).

Ingen af betingelserne kræver omdesign af kernen. Anbefaling: kør hærdnings-bølgen i afsnit 5 som forudsætning for skalering — punkt 1-2 bør ske nu.

---

## 2. Fund pr. område

### 2.1 Datamodel & schema

**Styrker:** Evidenslaget er strukturelt håndhævet (`UNIQUE (target_type, target_id)` på conclusion, append-baseret `red_edit_oplysning`, cache-regen læser kun konklusioner — invariant #1/#3/#4 holder, schema.sql:213 m.fl.) [verificeret]. Traversal-indekser i begge retninger på family_member/relation/assertion (schema.sql:512-524) — MRCA-rekursion er indeks-backet, ikke O(n), også ved 50k [verificeret]. Fuzzy datoer følger invariant #5 fuldt. Versioneringslaget er registry-drevet og dual-reviewet.

| Alvor | Fund | Evidens |
|---|---|---|
| HØJ | **Cache-projektionen vælger vilkårlig (alfabetisk max) værdi ved flere facts pr. faktatype.** `regen_person_visning` bruger `max(a.vaerdi_tekst)` på tværs af ALLE personens titel-/navne-facts (schema.sql:255-264). Med fact-kardinalitets-beslutningen (6 legitime titler pr. person) bliver `visning_titel` den leksikografisk største, ikke den primære. Projektionen mangler primær-markering/prioritering — liste- og søgevisning bliver systematisk misvisende ved rige biografier. | [verificeret] |
| HØJ | **Invariant #9 (kontrolleret vokabular) er ikke håndhævet i skemaet.** `vocab` findes (schema.sql:18-23), men ingen FK/CHECK binder `fact.faktatype`, `relation.rolle`, `family_member.rolle/konfidens`, `place.type`, `source.slags` til den. Validering findes kun i udvalgte RPC'er. Med mange redaktører + én importpipeline pr. slægt driver typenavnene fra hinanden ('fødsel' vs 'foedsel') og "samme slags"-forespørgsler bliver upålidelige. | [verificeret] |
| MELLEM | **`person.levende DEFAULT FALSE` er fail-open ved import** (schema.sql:85). En levende person indsat uden eksplicit flag defaulter til afdød = anon-synlig. Håndteret manuelt for Reventlow; ved 50+ presenslister er én glemt mapping = GDPR-læk. Samme mønster i loaderen: ukendt fødselsår ⇒ `levende=FALSE` (load_daa.R:302-317). | [verificeret kodelogik] |
| MELLEM | **Manglende indeks på `note(target_type, target_id)`** — eneste polymorfe tabel uden target-indeks; ~700 notes alene på family → seq-scans ved per-entitet opslag og RLS-evaluering ved skala. | [verificeret] |
| MELLEM | **Polymorf referentiel integritet hviler alene på håndskrevne slet-RPC'er — og kun for person/relation.** Ingen slet-RPC for estate/organisation/source/family/media; intet forhindrer facts/relations mod ikke-eksisterende id'er. `red_doede_links` dækker 3/10 typer (kendt, deferred). Ingen generel orphan-sweep som driftsværktøj. | [verificeret] |
| MELLEM | **Skema-drift: `narrative.fts` findes i prod men er udkommenteret i schema.sql** (schema.sql:526-529) og fraværende i db-migrations.sql — "source of truth"-kontrakten er brudt for netop den kolonne der allerede har forårsaget én prod-bug (review 10). | [verificeret for filerne; antaget for prod] |
| LAV | `red_konflikt`-viewet er en ugrupperet fuld-scan over fact⋈assertion (schema.sql:814-827) — sekunder pr. dashboard-load ved ~500k assertions. | [verificeret] |
| LAV | `profiles.reventlow_person_id` — slægtsspecifik navngivning i auth-laget; skal generaliseres før multi-slægt-medlemskab. | [verificeret] |

### 2.2 RLS & sikkerhed

**Styrker:** Fail-closed grundholdning (NULL-levende skjules; media gates på "mindst én ikke-offentlig person"; historik deny-all) [verificeret]. Konsekvent `SET search_path=public` + intern rolle-gate i alle `red_*`-funktioner [verificeret]. Afledte lag (assertion/citation/text_mention) gater via RLS-filtreret EXISTS; views bruger `security_invoker=true` [verificeret]. Privilegie-eskalering via `profiles` er lukket (kun self-read) [verificeret].

| Alvor | Fund | Evidens |
|---|---|---|
| KRITISK | **`version_pk_registry` er uden RLS, og `anon` har FULDE privilegier (SELECT/INSERT/UPDATE/DELETE/TRUNCATE) i prod.** Bekræftet af Supabase-advisors (eneste ERROR: `rls_disabled_in_public`) og katalog-SQL mod prod. En anonym klient kan via PostgREST ændre/tømme registret → forgifte `log_change` (læser `skip_cols`, schema.sql:1042) og knække/omdirigere fortryd (`_version_pk_where`, schema.sql:1076-1083). Mekanisk fix: enable RLS + revoke. | [verificeret i prod] |
| HØJ | **Anon-eksekverbar synligheds-oracle + audit-spam:** `_subjekt_synlighed` og `begin_change_set` (begge SECURITY DEFINER) er eksekverbare af `anon` via `/rest/v1/rpc/...` — bekræftet af advisors. `_subjekt_synlighed('person', id)` returnerer `'levende'/'privat'/'offentlig'` for præcis de personer RLS skjuler (GDPR-relevant eksistens-oracle); `begin_change_set` lader enhver indsætte rækker i den ellers deny-all'ede `change_set`. Advisors viser desuden at ALLE `red_*`-RPC'er er anon-eksekverbare — de har intern rolle-gate, så det er manglende defence-in-depth, ikke åbne huller, men revoke-listen bør dække hele fladen. | [verificeret i prod] |
| HØJ | **"authenticated" ≡ "medlem" uden medlemskabsverifikation.** `current_rolle()` defaulter til `'medlem'` uden profil-række (schema.sql:309); `auth_read` giver enhver logget-ind bruger alle levende, ikke-private personer (db-rls.sql:263-303). Intet binder en Supabase-konto til foreningsmedlemskab — hvis self-signup er åben (Supabase-default), er levende-laget de facto offentligt. | [policy-kæde verificeret; Auth-config usikker] |
| MELLEM | **Family-subjekter gates ikke på involverede personer:** fact-anon-politikken slipper alt med `subjekt_type <> 'person'` igennem (db-rls.sql:184), og family er i den offentlige referenceliste (db-rls.sql:118) — ægteskabsår/-sted for en levende person kan infereres via den afdøde partner. Samme mønster for narrative/note med family-target. | [policy-hul verificeret; datapåvirkning usikker] |
| MELLEM | **GDPR-sletning stopper ved versioneringslaget:** `change_event.foer/efter` beholder fulde PII-snapshots for evigt, også efter `red_slet_person`. Et art. 17-krav fra et levende medlem kan ikke honoreres uden manuel kirurgi der knækker fortryd-kæden. Ingen retention-/scrubbing-mekanisme designet. | [verificeret] |
| MELLEM | **8 interne funktioner har mutable search_path** (`log_change`, `parse_mentions`, `_version_*`, `_regen_mentions_for`, `_row_pk`) — advisors-WARN; lav praktisk risiko da de ikke kaldes med forhøjede rettigheder af klienter, men bør sættes for konsistens. | [verificeret i prod] |
| LAV | **HaveIBeenPwned-password-beskyttelse er slået fra i Auth** (advisors-WARN). | [verificeret i prod] |
| LAV | `red_suggest` uden rate-/størrelsesbegrænsning (kræver dog `auth.uid()`, schema.sql:793 — anon-spam afkræftet ved verifikation); ingen update-politik på `suggestion.status` → redaktionen kan ikke afgøre forslag via API. | [verificeret] |

**Kendte deferrede punkter (review 09):** TOCTOU i fortryd og parse_mentions-open-token var korrekt prioriteret for single-writer — men TOCTOU-defer'ens præmis falder samme dag redaktør #2 eller medlems-skrivning aktiveres. De skal genåbnes som *del af* go-live, ikke efter.

### 2.3 Mobile-app

**Styrker:** Klar lagdeling med testbar ren-funktions-kerne (buildModel/relationship/selectors) [verificeret]. Robust pagineringsdisciplin (`getAll` kaster ved fejl, load.ts:34-51). Slægtskabsalgoritmen er stærk: bilineal BFS, MRCA, konfidens-propagering "svageste led", korroborationssignal — 38 tests [verificeret]. Sikkert skrive-flow (alt via RPC, dry-run default, preview-sheet, dansk fejloversættelse). TS-disciplin (2× `any` i hele src/).

| Alvor | Fund | Evidens |
|---|---|---|
| KRITISK | **Fuld-database-load klient-side holder ikke ved 50k personer.** `loadFromSupabase` (load.ts:105-135) henter ALLE personer, family_member-rækker, narrativer i fuld tekst, relationer og media og bygger grafen i klienten — og det gøres **to gange** for redaktører (publikums-`model` + `redaktionModel`, useStore.ts:113/257). Sekventiel `.range()`-paginering ⇒ ~200 serielle HTTP-kald ved app-boot på foreningsniveau; narrativ-payload i tiere af MB; `getAll`s 400-side-loft kan nås af assertion/family_member. | [verificeret] |
| HØJ | **O(n·m)-hotspot i buildModel:** `nameOf` laver lineær `persons.find` pr. union (buildModel.ts:32,45-50); `byId`-mappet bygges først bagefter (:106). 50k personer × ~25k unions ≈ milliard-skala sammenligninger → frys ved load. Én-linjes fix (byg opslagsmap først). | [verificeret] |
| HØJ | **Redaktions-pickers henter hele persontabellen ved hver åbning og renderer uvirtualiseret** (PersonPicker.tsx:16, MentionPicker.tsx:25-31 — `ScrollView` + `.map`; publikums-søgningen bruger korrekt `SectionList`). | [verificeret] |
| MELLEM | **Privat-toggle desynkroniserer UI fra DB:** `setPrivat` sættes optimistisk FØR preview-sheetet (person/[id].tsx:368-381); annullering/dry-run efterlader switchen flippet uden write og uden rollback. | [verificeret] |
| MELLEM | **Asymmetrisk fejl-svælgning i person-editoren:** `fetchPersonEvidence/-Relationer/-Familie` har `.catch(() => {})` (person/[id].tsx:257-268) → RLS-/netværksfejl vises som "ingen oplysninger", og redaktøren kan oprette dubletter i god tro. Narrativ-feltet fik netop en guard mod dette (cycle 04); de øvrige sektioner + PersonPicker mangler den. | [verificeret] |
| MELLEM | **Ingen konflikt-håndtering ved samtidige redaktører:** kun fortryd har konflikt-detektion; øvrige RPC'er er last-writer-wins, og `redaktionModel` genindlæses aldrig automatisk i sessionen (useStore.ts:258) — stale navne og krydsende redigeringer bliver hverdag med >1 redaktør. | [verificeret — fravær af mekanisme] |
| MELLEM | **DB-typer er håndskrevne, ikke genererede** (`Raw*` pr. query; ingen `supabase gen types`-artefakt) — skema-drift opdages først runtime, jf. GENERATED-kolonne-buggen der kun blev fundet ved real-device-test. | [antaget — ingen genereret typefil fundet] |
| LAV | Død fuld-tabel-query på `family` (load.ts:110); `media` bruger `select('*')` (:130); `as never`-casts i router.push. | [verificeret] |

**Testdækning:** ~204 tests (12 filer), alle mod rene funktioner — forretningslogikken er godt dækket. Kritiske udækkede stier: hele `useStore` (load/auth/seed-fallback), samtlige skærme/komponenter (nul render-tests — privat-desync-fundet ville en simpel komponenttest have fanget), SkrivePreviewSheet-flowet og 847-linjers person-editorens `Change`-konstruktion. [verificeret ved optælling, ikke eksekveret — read-only-mandat]

### 2.4 Web-app & to-frontend-strategien

**Styrker:** Disciplineret tynd skive (~2.800 LOC, Vite + React 18, ingen unødige deps). Porterede filer markeret "hold i sync"; kerne-kopierne var byte-identiske ved review [verificeret via diff]. Seneste tværgående fix (de62cd6) blev anvendt i begge apps i samme commit. Web har rolle-baseret skrive-routing (`planCall`: redaktion → `red_*`, ellers → `red_suggest`-staging) som mobile ikke har.

| Alvor | Fund | Evidens |
|---|---|---|
| HØJ | **Web renderer narrativ uden mentions-parser — rå `[[type:id\|tekst]]`-tokens lækker til publikum.** DB-laget (live i prod) gemmer tokens; mobile parser dem; web viser rå tekst (Folgesvend.tsx:350, :479; nul forekomster af "mention" i web/src). Værre: webs narrativ-editor er en rå textarea (Redaktion.tsx:339) uden escape-håndtering — en web-redaktør kan korrumpere tokens skrevet fra mobile. | [verificeret at parseren mangler; usikker om prod-narrativer allerede har tokens] |
| HØJ | **Duplikeret datalag med aktiv divergens i skrivelaget:** mobile har fortryd/opret/flytBarn/ordinal; web har forslag/planCall — `redaktionWrite.ts` er allerede markant divergeret, og identiske kopier holdes kun i sync via manuel disciplin. Dobbelt-fix-skatten er dokumenterbar (de62cd6: samme bug rettet to steder, regressionstest kun i mobile). | [verificeret] |
| MELLEM | **Web mangler hele versionerings-/fortryd-app-laget:** web-redaktører kan skrive LIVE men hverken se historik eller fortryde — asymmetrisk risiko. | [verificeret] |
| MELLEM | **Nul testinfrastruktur i web** (ingen tests, ingen test-runner i package.json; delt logik er reelt kun testet via mobiles kopi). | [verificeret] |
| MELLEM | **PWA-beslutningen er ikke indfriet:** intet manifest, ingen service worker, ingen vite-plugin-pwa — ren desktop-SPA. Modsiger stiltiende det oprindelige arkitekturvalg "web + PWA først"; bør enten bygges (lille indsats) eller nedskrives i decisions.md. | [verificeret] |
| MELLEM | **Web-redaktion mangler opret-flows** (kan ikke føde nye entiteter, kun redigere + foreslå). | [verificeret] |
| LAV | Google Fonts fra CDN (Folgesvend.tsx:28) — tredjeparts-kald ved sidevisning i et GDPR-bevidst projekt; mobile bundler lokalt. Design-tokens duplikeret 3 steder (drift-risiko). | [verificeret; GDPR-vurdering antaget] |

**Paritets-hovedtræk:** Kernen (personvisning, stamtræ, slægtskabsfinder, søgning) har fuld paritet med identisk motor. Skævheden er koncentreret i redaktions-/narrativlaget: web mangler opret/fortryd/historik/mentions; mobile mangler forslag/staging. **Anbefaling:** ekstrahér delt core-pakke (types, buildModel, relationship, fields, getAll, mentions — ren TS, nul RN-afhængighed, kan flyttes i dag) med mobiles 200 tests; lad UI'erne forblive separate (designene er reelt forskellige; det er datalaget, ikke UI'et, der bløder).

### 2.5 R-pipelines & datakvalitet

**Styrker:** Klar deterministisk/LLM-arbejdsdeling med blokerende validerings-gate; "manglende udtræk = under-strukturering, aldrig datatab" er arkitektonisk sund og håndhævet (narrativ bevares 100% deterministisk) [verificeret]. Rodårsags-læring omsættes til kode (flere-forældrepar-fixet droppede det forurenede LLM-felt helt) [verificeret]. Transaktionel load med rollback + bulk-COPY — ingen halvloadet tilstand mulig [verificeret]. TNG-QA har seriøs GDPR-disciplin (fail-closed input-gating, read-only-GUC-verifikation) [verificeret].

| Alvor | Fund | Evidens |
|---|---|---|
| KRITISK | **Loaderen kan ikke tilføje slægt #2 — reset er destruktiv, append er brudt.** Default RESET kører `TRUNCATE <17 tabeller> CASCADE` (load_daa.R:163-164), der cascade-sletter versionerings-/redaktionsdata (jf. review 11). `--no-reset` er reelt brudt: kommentaren "start fra max(id) i basen" (load_daa.R:41) er falsk — `nid()` starter altid fra 1 (modsat `load_presens.R:44-45`, der gør det korrekt) → PK-kollision → rollback. Ingen fungerende vej til ny slægt, og ingen vej til at gen-loade Reventlow uden at destruere redaktionsarbejde. | [verificeret] |
| HØJ | **Prod-tilstanden kan ikke regenereres fra ét artefakt:** 591-post-udtrækket ligger spredt over batch-filer i git-ignoreret `work/`; `clean.json` har kun 15 poster; LLM-orkestratoren (`extract_all.py`) er selv git-ignoreret. Hverken Reventlow-reproduktion eller ny-slægt-kørsel er reproducerbar end-to-end. | [verificeret] |
| HØJ | **Fejlklassen "LLM-felt uden deterministisk krydscheck" er kun delvist lukket.** Adresseret: boern, årstal (R1), spans (R7). Ikke adresseret (samme klasse som flere-forældrepar-sagen): navn/tilnavn verificeres aldrig mod raw_text; `date_min/max` verificeres ikke mod `date_raw` (forkert måned/dag lander som blåstemplet ISO-dato); partner-datoer/`partner_foraeldre` har intet R7-krav men loades som fakta på nye personer (load_daa.R:218-220); koen/godser/embeder har kun advisory tjek. | [verificeret] |
| HØJ | **Ægteskabs-miss kan promoveres tavst til prod:** R8 er advisory, og Opus-promote-gaten kræver kun "ikke flere misses end Sonnet" — poster med kendt miss ender i clean.json, og der findes ingen tracking af hvilke prod-poster der bærer kendte R8-misses. | [verificeret] |
| MELLEM | **Edition-/slægts-hardcoding i deterministiske trin** (grep-mønstre med slægtsnavn i `extract_text.sh`; edition-følsomme segment-regexer) — afvikling per slægt kræver en udvikler, ikke en operatør. | [verificeret] |
| MELLEM | **TNG-QA er strukturelt Reventlow-bundet** (hardcodet dump, kalibrering bootstrappet på Reventlow-forhold), og review-afgørelser tabes ved gen-kørsel (kendt H2) — manuel QA-tid akkumulerer ikke. For slægter uden TNG findes intet uafhængigt QA-lag. | [verificeret] |
| MELLEM | **Ingen proces for datagæld:** 4 uafklarede + 46 forældreløse personer findes kun som prosa-anbefaling i review 11 — ingen kø/register. Ved 100 slægter multipliceres halen uden afviklingssystem. | [verificeret — intet tracking-artefakt] |
| LAV | **`load_daa.R` er utestet** — det eneste trin der skriver til prod har ingen tests, mens begge alvorlige prod-datafejl bor netop dér. | [verificeret] |

**100-slægters-vurdering:** Ikke klar i nuværende form, men arkitekturen er principielt multi-slægt-egnet — gælden er implementering, ikke design. Realistisk 1-3 dages kvalificeret arbejde pr. slægt med nuværende tooling; flaskehalsen er menneskelig review-tid, ikke LLM-kost.

### 2.6 UI/UX-flows

**Styrker:** Kernefunktionen "Er vi i familie?" er reelt bygget, synlig og invariant 7-tro (multi-linjer, fælles ane, trin-sti, konfidens på svageste led + korroboration) på begge platforme [verificeret]. Mange indgange til personer (søgning m. alfabet-chips, 3 stamtræ-varianter, godser→ejere, klikbare relations-links). Redaktørens person-editor er dybt evidens-tro (assertion-niveau, konfidens, ordinal, flyt-barn, mentions). Stærk sikkerheds-UX i skriveflowet (dry-run-gate, preview, konflikt-kø, historik m. fortryd).

| Alvor | Fund | Evidens |
|---|---|---|
| HØJ | **Ingen indgang til redaktionen fra mobil-appen:** `/redaktion`-ruterne findes, men intet i publikums-appen linker dertil (root-layout registrerer kun publikums-skærme, _layout.tsx:44-50; grep = 0 hits) — redaktør på mobil kan kun nå editoren via deep-link. | [verificeret] |
| HØJ | **Fakta-usikkerhed er usynlig for slutbrugere:** person-siden viser kun cache-feltet — en omstridt dødsdato med to kilder ser identisk ud med en sikker (person/[id].tsx:66). "UENIGE"-markering og oplysningslag findes kun i redaktionen; citation-laget (citat_tekst/citat_dato) vises ingen steder. Invariant 7 er dermed kun opfyldt for slægtskabs-links, ikke fakta. | [verificeret] |
| HØJ | **Ingen suggestion-review-UI:** web sender forslag til staging med teksten "afventer redaktionel godkendelse", men ingen skærm på nogen platform lister/godkender dem — forslag ender i et sort hul medmindre de håndteres i SQL. | [verificeret] |
| HØJ | **Store dele af entitetskataloget kan ikke redigeres:** mobile entitetslister er eksplicit "ingen detail-editor endnu" (entitet/[type].tsx:56); place, vocab, note, lineage, media, coat_of_arms har ingen editor. En redaktør kan oprette et gods, men aldrig rette dets navn bagefter. | [verificeret] |
| MELLEM | **Fact-editoren er person-only og låst til 4 faktatyper** (`FELTER = ['navn','foedt','doed','titel']`) — invariant 3's pointe (fakta på enhver entitet, nye behov = nye faktatyper) er ikke surfacet: dekorationer, floruit, steds-/ejendoms-tidslinjer kan hverken ses eller redigeres. | [verificeret] |
| MELLEM | **Kilder kan kun knyttes som fritekst** (`p_kilde_fritekst` i alle skrive-RPC'er); man kan oprette en source men ikke vælge den som citation — underminerer evidensmodellens kildebinding i praksis. | [verificeret] |
| MELLEM | **Ingen fuldtekst-/variantsøgning:** kun substring på visningsnavn (selectors.ts:260); `narrative.fts` bruges af ingen frontend. Ingen søgning via titel, gods eller prosa; stavevarianter rammer forbi. | [verificeret] |
| LAV | Web/mobile-redaktion asymmetriske (redaktør skal kende begge flader); "Om slægten" pladsholder-drevet på mobile; web har ingen URL pr. person (kan ikke dele link). | [verificeret / antaget for deep-linking] |

**Dæknings-billede:** En bruger kan fint *finde* personer og slægtskab, men ikke se evidens/usikkerhed på fakta-niveau. En redaktør kan redigere person-kernen, familie-strukturen og narrativer fleksibelt og evidens-tro — men ca. halvdelen af datamodellens entitets-/faktakatalog er read-only eller usynligt i UI, og forslags-kredsløbet er kun halvt bygget.

---

## 3. Udeladte aspekter (samlet)

**I modellen:**
- **Person-merge/`same_as`** — modellen beskriver identitet som evidens-spørgsmål, men skemaet har ingen bærer. Rammer kerneproduktet direkte: kryds-slægts-slægtskab afhænger af ægteskabslinks mellem slægter — præcis dér opstår dubletter (samme kvinde i to slægters stamtavler = to personer) → falske negativer i "er vi i familie?".
- **Ingen "slægt"-entitet** — `lineage` er scoped til én sources linje-inddeling; intet førsteklasses objekt for "slægten Reventlow" som medlemskab/våben/navigation kan hænge på ved 50+ slægter.
- **GDPR-retention for `change_event`** — ret-til-sletning vs. evig fortryd-garanti er uafklaret.
- **Struktureret fødsels-/dødsår på person-cachen** (kun rå tekst) — sortering/filtrering/era-validering ved 50k kræver afledt numerisk år.
- **Suggestion-workflow er en stub** (kun status 'afventer', ingen afgørelses-API).

**I teknikken:**
- **Storage-politikker findes ikke** (0 hits i *.sql) — intet aktivt hul da Storage ikke bruges, men skal designes med afbildet-gating inden multimedie.
- **Server-side søgnings-/traversal-API** (FTS-endpoint, MRCA-RPC) — forudsætning for at forlade klient-side-fuld-load.
- **Genererede DB-typer + delt core-pakke** — begge frontends flyver på håndskrevne typer og manuel sync-disciplin.
- **Datagælds-register + orphan-sweep** som driftsværktøjer.

**I UX:**
- **Ingen bidragskanal for almindelige medlemmer** — visionen er "indsamlingsmotor for næste udgave", men publikums-appen har ingen "foreslå rettelse"-knap (suggestion-tabellen + `red_suggest` findes allerede og kræver kun UI).
- **Samtykke-/levende-forvaltning** — `levende` kan kun sættes ved oprettelse; ingen flade til at ændre levende-/samtykkestatus på eksisterende personer (afventer bevidst auth-tier-design).
- **Vocab-styring fra appen** — rolle-/slags-lister er hårdkodede i UI i stedet for at læse vocab-tabellen.
- Media-upload, dekorations-nøgle (kendt), deep-linking på web.

---

## 4. Go/no-go-vurdering

**GO — på betingelser.** Fundamentet (evidensmodel, RLS-arkitektur, slægtskabsmotor, valideringsfilosofi i pipelinen) er gennemtænkt og reelt implementeret; seks uafhængige reviews fandt ingen designfejl der kræver omdesign. Betingelserne, grupperet efter hvad der udløser dem:

1. **Nu (før alt andet):** Luk prod-sårbarhederne (§2.2 KRITISK+HØJ) — timers arbejde.
2. **Før slægt #2:** Append-sikker loader + kanonisk udtræks-artefakt pr. slægt + person-merge-design.
3. **Før redaktør #2:** Sekvens-migrering af id-tildeling (inkl. `log_change`/`begin_change_set`) + genåbn TOCTOU + konflikt-/refresh-håndtering i appen.
4. **Før rigtige brugere:** Medlemsverifikation + samtykke-granularitet + family-gating + change_event-retention-beslutning.
5. **Før 50k personer:** Server-side søgning + on-demand detalje + MRCA-RPC (buildModel-fixet er en én-linjes quick win, der bør tages straks).

Punkt 2-5 kan køres inkrementelt og delvist parallelt; intet af det invaliderer eksisterende data eller kode-investering.

---

## 5. Prioriteret handlingsliste

| # | Handling | Hvorfor nu | Udløser |
|---|---|---|---|
| 1 | **Luk prod-hullerne:** RLS + revoke på `version_pk_registry`; `REVOKE EXECUTE` fra anon/authenticated på `_subjekt_synlighed`, `begin_change_set` og hele `red_*`/`hist_*`/helper-fladen (behold kun det, klienterne kalder, for authenticated); sæt search_path på de 8 interne funktioner; slå leaked-password-beskyttelse til. | Anon kan i dag skrive i fortryd-registret og aflæse levende/privat-status. Mekanisk, timers arbejde, dual-review + db-verify-asserts. | I dag |
| 2 | **Web: mentions-rendering + escape-håndtering i narrativ-editor.** Portér `mentions.ts` + renderer (ren TS). | Eneste fund hvor skew kan vise ødelagt indhold for slutbrugere og korrumpere data skrevet fra mobile. | I dag |
| 3 | **Append-sikker loader:** `nid()` fra MAX(id) (mønstret findes i `load_presens.R`), source-scoped delete i stedet for global TRUNCATE; + kanonisk versioneret `clean-<slægt>.json` + versioneret trin③-driver. Tests på loaderen. | Ingen fungerende vej til slægt #2; Reventlow kan ikke gen-loades uden at destruere redaktionsarbejde. | Slægt #2 |
| 4 | **Sekvens-migrering:** `max(id)+1` → IDENTITY/sekvenser i alle skriveveje inkl. `log_change` og `begin_change_set`; genåbn TOCTOU-defer'en i samme bølge. | To samtidige redaktører giver duplicate-PK på stort set enhver skrivning, inkl. audit-loggen. | Redaktør #2 |
| 5 | **Person-merge/`same_as`-design** (ADR først): merge-RPC der repointer external_id/family_member/facts/relations/text_mention/change_set/profiles + evidensbåret `same_as`. | Uden den leverer kerneproduktet falske negativer på tværs af slægter. | Slægt #2-3 |
| 6 | **buildModel-quick-win** (byg `byId`-map før union-loop) + virtualisér pickers + fjern død family-query. | Én-linjes fix på det hotspot der rammer først; lav risiko. | Straks |
| 7 | **Auth-hærdning til go-live:** lukket signup/invitation eller medlemskabs-provisionering; samtykke-granularitet pr. levende person (§FREMTID-skitsen); family-gating på involverede personer; dokumenteret change_event-retention-procedure. | Uden dette er levende-laget reelt offentligt, og behandlingsgrundlaget mangler. | Rigtige brugere |
| 8 | **Server-side læsesti:** FTS-søgning (narrative.fts + navn-ilike) med limit, on-demand person-detalje, MRCA som recursive-CTE-RPC; afvikl dobbelt-model for redaktører. | Klient-side fuld-load er den bindende 50k-begrænsning; kan bygges inkrementelt bag nuværende API. | ~5-10k personer |
| 9 | **Vocab-håndhævelse:** FK/CHECK (eller trigger) mod vocab på faktatype/rolle/slags + vocab-drevne lister i UI; `levende` fail-closed ved import (kræv eksplicit flag i loaderen). | Forebygger den drift på tværs af slægter/redaktører som invariant 9 skulle forhindre; lukker GDPR-fail-open ved import. | Slægt #2 |
| 10 | **Delt core-pakke + luk kredsløbene:** `packages/daa-core` (types/buildModel/relationship/fields/getAll/mentions + forenet Change-union) med mobiles tests; suggestion-review-UI + status-API; "foreslå rettelse"-knap i publikums-appen; udvid editor-dækning (entitets-editorer, citation-binding, evidens-visning for slutbrugere). | Stopper dobbelt-fix-skatten; åbner medlems-bidrag (forretningsmålet); lukker invariant 7-hullet for slutbrugere. | Løbende |

---

## 6. Metode-forbehold

- Alle kode-fund er statisk læsning (read-only-mandat): ingen tests/builds kørt, ingen runtime-/memory-målinger. Testtal er optalt fra kildefiler.
- Prod-verifikation begrænset til security-advisors + katalog-SQL (grants); Auth-konfiguration (signup-politik, e-mail-verifikation, MFA) er ikke inspiceret og står som [usikker].
- Skaleringsestimater (boot-tid, kald-antal, LLM-kost) er regnestykker fra kode og dokumentation, ikke belastningstest.
- Web-agentens diff-baserede paritets-tjek afspejler working tree pr. 2026-07-02.
