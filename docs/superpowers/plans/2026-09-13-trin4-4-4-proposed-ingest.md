# Trin 4 · dagsværk 4.4: proposed-ingest — implementeringsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Få 4.3b's kontraktvaliderede claims ind i databasen som **forslag** — `proposed`, aldrig kanoniske fakta — bundet til de klausuler, de citerer, så et menneske i 4.5 kan tage stilling til dem én ad gangen.

**Architecture:** En tredje elementoperation i #153's generelle writer, `interpretation_proposal`, bygget efter samme mønster som 4.1c's `clause_evidence`. Ingen ny motor, ingen ny model-kørsel, ingen ny restore.

**Tech Stack:** PostgreSQL 17 (DDL + PL/pgSQL), Python 3 til manifest-builder, R til apply-klienten, pytest + psql-tests.

**Spec:** `docs/superpowers/specs/2026-09-06-trin4-fortolkningskaede-og-klausulgranularitet-design.md` §7.

**Restore:** **samme base som 4.3b** (spec §3: 4.3b-4.5 deler én restore, fordi klausul-id'erne er database-genererede). Der oprettes ingen ny.

> ## Denne plan er skrevet om fra bunden (2026-09-13)
>
> En tidligere udgave fik 13 fund af første læser. Rettelserne blev skrevet som et
> revisionsafsnit **øverst**, mens task-kroppen forblev uændret — `git show 1a14102`
> viser **+125 / −0 linjer**. Anden læser (Fable) konstaterede, at »revisionen er en
> præambel, ikke en revision«: en implementør, der fulgte checkboxene, ville bygge
> den plan, første læser havde afvist.
>
> Det er samme fejl, plan 4.2's revision selv advarede mod (»ret kroppen, ikke kun
> forordet«). Derfor er denne udgave skrevet forfra. **Der er ingen præambel — alt
> står i de steps, der skal udføres.** Ændringsloggen ligger til sidst.

---

## Hvad 4.3b faktisk viste

Tre ting fra forrige dagsværk styrer denne plan. To af dem blev først forstået, da
**selve sætningen** blev læst — efter to forkerte diagnoser.

### A. Det ene usande claim var en sproglig fejl, ikke overpræcision

Bogen skriver: *»…var død 1353 (23. april), **da** hans sønner … solgte landsbyen.«*
**23. april 1353 er salgets dato, ikke dødsfaldets.** Modellen læste konstruktionen
»var død [dato], da [begivenhed]« som en dødsdato.

Begge dødsclaims stod **ordret** i teksten; modellen udledte intet. Fejlen kan derfor
**ikke** fanges ved at sammenligne datointervaller — der er intet interval at
sammenligne. Den kræver forståelse af sætningens grammatik.

**Konsekvens: der bygges ingen maskinel detektor for dette i 4.4.** Det hører til
menneskets arbejde i 4.5. To tidligere udgaver af planen foreslog detektorer
(sammenlign søsterclaims; sammenlign `date_min/max` med `raw`) — den første
sammenlignede modeloutput med modeloutput, den anden refererede til felter, et
`date_raw`-claim slet ikke har. Begge er skrottet.

### B. To relations-claims identificerer ingen

`relation.marriage` = `NN.` og `relation.child` = `4 sønner`. Sande og formelt
gyldige, men uden modpart at binde til. Det er **den fejl, 4.4 kan og skal fange** —
og den fanges i **builderen**, ikke i writeren (se C).

### C. Ét writer-element er én record

Rejser writeren en exception for ét claim, ruller **hele recorden** tilbage. Det er
præcis den fejl, projektejeren afgjorde imod efter 4.3b's bundt 1, hvor ét ugyldigt
claim fældede seks korrekte. Enhver pr.-claim-afvisning, der kan afgøres på forhånd,
hører derfor i builderen.

## Global Constraints

- **Ingen prod-mutation.** Alt mod 4.3b's restore. Trin 4's migrationer er stadig ikke i produktionen.
- **Intet promoveres.** Alle interpretationer er `proposed`, `method='model'`, version 1. Kanoniske aggregat-hashes skal være uændrede.
- **Ingen ny model-kørsel.** 4.4 ingester 4.3b's eksisterende svar. En genkørsel er et nyt GO.
- **`value.raw` ER autoriseret privat evidens.** §7.1 kræver `value` i payloaden, og et claims værdi kan være et ordret kildeudsnit. Det, der **ikke** må med, er hel klausul- eller helposttekst. Payloaden lagres permanent i `private.reimport_event` — derfor RLS/ACL, ingen anon-adgang, og ingen udvidelse af recordmængden ud over den godkendte manifestliste.
- **Ingen kildetekst i logs, rapporter eller commit-beskeder.**
- **Prod-fortrydelse findes ikke** (§7.4). Fortrydelse sker ved restore. Det er en forudsætning for et senere prod-GO (åbent punkt 11.5) og skal stå i rapporten.

## Roadmappens seks adgangskrav

1. **Roadmapmål:** trin 4, den fælles fortolkningskæde (#147 leverance 2).
2. **Værdikædeled:** »Proposed-ingest og promotion« mod `integreret ende-til-ende` for 2018-20; promotionsdelen først i 4.5.
3. **Generel, profil eller legacy:** generel motor; tredje elementoperation i #153's writer.
4. **Redaktionel værdi:** for første gang ligger der forslag i databasen, en redaktør kan tage stilling til. Uden dette trin er 4.3b's claims kun en fil.
5. **Bevis:** 4.3b's batch ingestet (§7.5) — fem afstemte tal, alle links løser, neutralitets- og `anon`-hashes uændrede, replay `already_applied`, negativ test pr. afvisningsgrund.
6. **Erstatter:** intet. `project_evidence.R` forbliver dry-run til trin 6.

## Filoversigt

| Fil | Ændring |
| --- | --- |
| `schema.sql` | `private.deterministic_uuid(text)`; writer-operationen; operation-CHECK; dispositionskoder. |
| `db-migrations.sql` | Samme, idempotent, med kontrakt-drift-guard som 4.1c. |
| `db-rls.sql` | ACL for den nye operation. |
| `db-verify.sql` | `OK: #147 4.4`-blok + negative prober. |
| `tests/sql/test-interpretation-proposal.sql` | **Ny.** Kontrakttest, rød først. |
| `.claude/skills/daa-extract/scripts/build_43b_proposal_manifest.py` | **Ny.** Fra 4.3b's cache til writer-payload, med klassifikation og fem-tals-regnskab. |
| `.claude/skills/daa-extract/scripts/test_build_43b_proposal_manifest.py` | **Ny.** Uden den kører builderens logik ingen steder i CI. |
| `.claude/skills/daa-extract/scripts/apply_reimport_helpers.R` | `interpretation_proposal` fire steder. |
| `.claude/skills/daa-extract/references/reimport-profiles/daa-2018-20-interpretation-proposal-v1.json` | **Ny.** Rummer også `nn_denylist` (se Task 4). |
| `.github/workflows/ci.yml` | SQL-testen + Python-testen. |

---

### Task 0: Målinger, der skal foreligge før noget bygges

Flere af de tidligere udgavers tal var antagelser. Disse måles først, read-only, mod
4.3b's restore og cache — **uden modelkald**.

- [ ] **Step 1.** Er nogen af de 10 records blandt de **3 tekstkollisions-par**? Cache-nøglen bærer nu `record_key` (PR #188), men 4.3b's cachefiler blev skrevet før rettelsen. Er ingen af de 10 ramt, er kollisionen uden konsekvens for 4.4 — og det skal stå som **målt**, ikke antaget.
- [ ] **Step 2.** Hvor mange claims blev **kontrakt-afvist** i IV-34? Rapporten siger »nogle … resten« uden tal. Det tal er første led i regnskabskæden.
- [ ] **Step 3.** Fordeling pr. `interpretation_kind` i de kontraktvaliderede claims. Findes der `event.*` eller `property`-claims uden `person.`-præfiks (`heraldry.*`, `lineage.*`, `genealogy.*`, `image.*`)? Det afgør Task 5's rolleproblem.
- [ ] **Step 4.** Persona-vej-paritet: giver `persona_key = record_key` (eksportens vej) og helpost → mention → `source_persona_mention` med rolle `primary` (spec §7.2's vej) **samme** svar for hele 2018-20 — ikke kun de 10?
- [ ] **Step 5.** Antal persona-løse records. Spec §7.1 siger **fire** (`unresolved_text`); en tidligere planudgave skrev tre uden måling. Mål, og brug spec'ens fire som forventning indtil andet er dokumenteret.

**Verify:** fem målte tal skrevet ned, før Task 1 begynder.

### Task 1: Kontrakttesten (rød først)

- [ ] **Step 1.** `tests/sql/test-interpretation-proposal.sql` skal fejle med `REIMPORT_WRITER_AUTHORIZATION_INVALID`, før DDL'en findes.
- [ ] **Step 2.** Positive blokke: ét `principal`-claim med én citeret klausul; ét med flere; ét `other`-claim (persona `NULL`, disposition `afventer_identitet`).
- [ ] **Step 3.** Negative blokke, én pr. afvisningsgrund fra §7.1: ukendt klausul; hash-afvigende klausul; klausul uden for recordens helpost; inaktivt prædikat; værdi ≠ `value_kind`; confidence uden for [0,1]; `principal` på en record uden persona.
- [ ] **Step 4.** **Ingen H1-test i SQL.** Relations-claims uden modpart afvises i builderen (Task 4), ikke i writeren — se »Hvad 4.3b viste«, punkt C.

### Task 2: `deterministic_uuid` og nøglen

- [ ] **Step 1.** `private.deterministic_uuid(text)`: første 16 bytes af `digest(input,'sha256')`, versionsnibble 5, variantbits efter RFC 4122. Kvalificér `extensions.digest` og pin `search_path` som i `write_clause_evidence`.
- [ ] **Step 2 — dokumentér ærligt.** Dette er **ikke** en RFC-konform UUIDv5: v5 betegner SHA-1 over et namespace. Konstruktionen er projektets egen deterministiske UUID, som spec §7.1 foreskriver formen for. **Skriv det i funktionens kommentar**, så en senere læser ikke tror, den er standard.
- [ ] **Step 3 — kanonisk nøgleinput.** Ikke en separatorstreng: et **versioneret, kanonisk JSON-format** med faste feltnavne, UTF-8, og **sorterede, unikke** ordinaler. Spec §7.1's fem felter er grundlaget: `source_id`, `record_key`, `predicate`, ordinaler, `value_sha256`. Definér `value_sha256` som sha256 af `value`'s kanoniske JSON.
- [ ] **Step 4 — spec-errata eller ej.** Tilføjes `interpretation_kind` og `persona_role` til nøglen, er det en **ændring af spec §7.1** og kræver errata. Standpunkt: **tilføj dem ikke.** `interpretation_kind` er funktionelt bestemt af `predicate`; `persona_role` ville kun være nødvendig, hvis samme record + prædikat + værdi + ordinaler legitimt kunne optræde i begge roller — og det er ikke vist.
- [ ] **Step 5.** Tests: fast **testvektor** (kendt input → kendt UUID); samme claim to gange giver samme nøgle; ændret værdi giver en anden; ombyttet ordinal-rækkefølge giver **samme**; og en kollisionskanttest, hvor et felt indeholder tegn, der ville bryde en separatorbaseret form.
- [ ] **Step 6.** Findes nøglen, afvises elementet (`REIMPORT_WRITER_INTERPRETATION_PROPOSAL_EXISTS`). Genudtræk kræver en menneskelig `superseded`-beslutning og er trin 6.

### Task 3: Writeren

- [ ] **Step 1.** `private.write_interpretation_proposal` + wrapperen `public.red_apply_reimport_interpretation_proposal`. Udvid de lukkede mængder **fire steder** (event-CHECK, `validate_reimport_authorization_payload`, `red_finalize_reimport`, `red_reimport_batch_result`) plus `db-rls`'s to lister. Operation-præfiks `interpretation-proposal:` (§7.1). 4.1c's lære: glemmes ét sted, fejler writeren først ved apply.
- [ ] **Step 2.** Idempotent `extraction_run` pr. manifest (`run_key`), usage i `manifest`, med post-conflict-lighedskontrol som 4.1c's.
- [ ] **Step 3 — klausulopslag med kardinalitet præcis 1.** Hele vejen: recordens **ene accepterede** anchor → occurrence → **præcis én** helpost → barn med `(ordinal, verbatim_sha256)`. Et løst join på record og ordinal kan ramme en parallel occurrence eller en klausul fra forkert forælder. Tre negative fixtures: samme ordinal/hash under forkert occurrence, forkert parent, og en konstrueret dublet.
- [ ] **Step 4 — `interpretation_kind` afledes af tabellen**, aldrig af payloaden eller prædikatpræfikset. 4.2's lære: gættet ud fra præfikset kunne ikke skelne `event.marriage` fra `relation.marriage`.
- [ ] **Step 5.** Pr. claim: én `interpretation` (`proposed`, `model_inference`, `method='model'`, version 1) + `interpretation_observation` (`supporting`, ordinal) i **samme transaktion** under den deferred constraint `interpretation_has_observation`.
- [ ] **Step 6 — klausulregnskab (§7.3).** Citerede klausuler får ny maskinel dispositionsversion `fortolkning_foreslaaet` eller `afventer_identitet`. Fastlæg to ting, spec'en ikke afgør: (a) **præcedens**, når samme klausul citeres af både et `principal`- og et `other`-claim; (b) at der skrives **præcis én** ny version pr. klausul pr. element — triggeren kræver `max+1`, så to opdateringer i samme transaktion kolliderer. Uciterede klausuler beholder deres — **testet**, ikke antaget.
- [ ] **Step 7.** Writeren returnerer `interpretations_written` pr. element, så R-klienten kan afstemme mod manifestets claim-antal (4.1c's `clauses_written`-mønster).

### Task 4: Manifest-builderen — hvor claims klassificeres

Alt, der kan afgøres før writeren, afgøres her. Det er det, der forhindrer, at ét
claim fælder en hel record.

- [ ] **Step 1 — adressér 4.3b's cache eksplicit.** Cache-nøgleudledningen ændrede sig med PR #188, så 4.3b's filer findes ikke under den nuværende `key()`. Builderen adresserer dem via en **hash-bundet filliste** (filnavne + indholdshashes) og genvaliderer identiteten ved at re-udlede med den nøgleudledning, der **gjaldt ved kørslen** (`evidence-runner-1.0`, syv felter) — eksplicit, ikke via den aktuelle funktion. Bump `RUNNER_CONTRACT_VERSION`, så gamle og nye nøgler ikke kan blandes.
- [ ] **Step 2 — hash-verificeret join.** Manifestets recordpost peger på cache-key, `record_input_sha256` og den hash-bundne runner-eksports hash. Builderen henter hver ordinals `verbatim_sha256` fra **eksporten**, ikke fra modellens svar. `claim_id` defineres deterministisk.
- [ ] **Step 3 — re-kør kontraktvalideringen.** Cachens `raw` rummer **alle** modellens claims, inklusive de kontrakt-afviste (IV-34). Builderen kører `partition_record_claims` mod eksporten med **pinnet** `interpretation-predicates.json`-sha og `RUNNER_CONTRACT_VERSION`.
- [ ] **Step 4 — H1: relations-claims uden modpart.** Afvis `relation.*`, hvis værdien ikke identificerer nogen. **Lukket denylist** af hele-streng-former, ikke en generel detektor: normalisér først (NFKC, casefold, whitespace-kollaps, strip afsluttende tegnsætning), match derefter `NN`/`N.N.`/`N. N.`-varianter og et eksplicit dansk mængdesæt (`4 sønner`, `en søn`, `et barn`, `tvillinger`, `børn`, …), anchored fra start til slut.

  **Listen hører i reimport-profilen**, ikke i kode: den er udgavespecifik (2018-20 er moderne retskrivning, 1939 skriver »Sønner/Døtre«) og ændres under den eksisterende GO-gate.

  Anchored match giver **falske negativer** (»4 sønner, som døde små« slipper igennem). Det er acceptabelt, fordi 4.5 er menneskegatet — **sig det i koden**, så reglen ikke forveksles med en korrekthedsgaranti. Positive tests: initialer, forkortede fornavne, patronymer, regnalnumre (»Christian 4.«), fremmedsprogede navne, og navne der begynder med et talord.
- [ ] **Step 5 — dedup.** Modellen kan gentage et claim inden for samme record (IV-19 gav 25). Uden dedup taber en dublet hele recorden på `..._PROPOSAL_EXISTS`. Deduplikér på `interpretation_key` i builderen.
- [ ] **Step 6 — fem tal i manifestet.** `rå claims` → `kontrakt-afviste` → `H1-afviste` → `dubletter` → `ingestible`. Ikke tre. Bind manifestet til 4.3b's resultatfil-hash og til `runner_manifest_sha256`.
- [ ] **Step 7 — payloaden ordret efter §7.1.** Lukket nøglesæt: `source_record_key`, `runner_manifest_sha256`, `model_version`, `prompt_version`, og pr. claim `claim_id`, `predicate`, `interpretation_kind`, `value`, `confidence`, `cited_clauses[]` = `(ordinal, verbatim_sha256)`, `persona_role`. Definér og test usage-aggregeringen fra cacheposterne.
- [ ] **Step 8.** `apply_reimport_helpers.R` kender operationen fire steder (`expected_counts`-nøgle `interpretation_proposals`, `dependency_class`, tælling, gateway-dispatch) og **afstemmer** writerens `interpretations_written` mod manifestets tal pr. element.

### Task 5: `persona_role` — og hullet i spec §7.2

Spec §7.2 definerer `principal` (recordens persona) og `other` (`NULL`, form
`mention`/`relation`). Men et `event.appointment` om hovedpersonen er hverken: det
er `property`-agtigt uden `person.`-præfiks. Med en ren »ikke-`person.*` → `other`«-regel
ville det få persona `NULL` og dets klausuler `afventer_identitet` — **forkert**.

Det samme gælder `heraldry.*`, `lineage.*`, `genealogy.*`, `image.*`.

- [x] **Step 1.** Task 0 Step 3 har målt, om sådanne claims overhovedet findes i de
  kontraktvaliderede. Gør de ikke, er problemet teoretisk her — **skriv det som målt**
  og luk det for dette dagsværk.
- [x] **Step 2.** Gør de, så vælg **én** vej og skriv den i spec-errata: enten en
  rollekolonne i `interpretation_predicate`, eller en eksplicit tabel i den nye
  reimport-profil. **Gæt ikke ud fra præfikset** — det er 4.2's fejl igen.
- [x] **Step 3.** `persona_role = principal` kræver **verificeret lighed** mellem
  runnerens persona og recordens entydige primary persona, fundet ad spec §7.2's vej
  (helpost → mention → `source_persona_mention` rolle `primary`) med kardinalitet 1.
  Builder og writer skal bruge **samme** forespørgsel — Task 0 Step 4 har målt, at de
  to veje er enige.

### Task 6: Reviewsignal for claims, mennesket skal se nærmere på (punkt A)

Den sproglige fejlklasse fra 4.3b kan ikke fanges maskinelt. Men 4.5 skal kunne se,
hvilke claims der fortjener ekstra opmærksomhed — og **en klausul-disposition kan
ikke bære det**: flere claims kan citere samme klausul, så et flag dér ville både
mistænkeliggøre korrekte claims og undlade at pege på det forkerte.

- [x] **Step 1 — VALGT 2026-09-15: menneskearket, ikke en flagkolonne.**
  Signalet bor i bedømmelsesarkets forudfyldte anbefalingskolonner (spec §8.2), som
  `build_43b_judgement_sheet.py` allerede renderer for 4.3b. **Ingen DDL i dette
  dagsværk.** Tre grunde, i vægtrækkefølge:

  1. **Task 7 er allerede kørt.** De 84 forslag står i restoren
     `daa43b_20260912192527`, som 4.5 skal bruge (spec §3). En `proposal_flags`-kolonne
     skulle ind via writer-payloadens lukkede nøglesæt (§7.1) → nyt manifest → ny batch;
     men writerens guard er fail-closed pr. `interpretation_key`
     (`REIMPORT_WRITER_INTERPRETATION_PROPOSAL_EXISTS`) og replay kortslutter på
     batch-niveau. Valget i dag ville altså koste enten en genkørsel af hele 4.4 på en
     frisk base, eller et `UPDATE` uden om `private.reimport_event` og uden om tabellens
     versionsdisciplin (`interpretation_key`/`version`/`supersedes_id`). Begge er dyrere
     end det, flaget skulle løse.
  2. **Arket ER spec'ens kanal.** §8.2 foreskriver allerede »menneske-ark (token-pr-linje
     med forudfyldt anbefaling), hashes ved godkendelse«. Den forudfyldte anbefaling er
     reviewsignalet. En flagkolonne ville lave en anden kopi af den inde i basen og kræve
     errata til §8.2; arket kræver ingen.
  3. **Flaget ville persistere en projektion.** Efter Step 3 (ingen maskinel H2-regel) er
     der intet tilbage, et flag kunne bære, som ikke allerede er forespørgbart:
     `confidence`, `persona_role`, antal citerede klausuler, klausulens egne
     `clause_flags` (`unknown_abbreviation`, #189's 3-tegns `VI.`) og
     `value_kind = date_raw`. Datamodellens invariant 4 siger netop, at afledte værdier
     ikke persisteres som data.

  **Prisen, sagt højt:** signalet lever uden for databasen, indtil afgørelsen skrives ind
  med `red_decide_interpretation`. Mistes arket, mistes signalet — derfor er hash-bindingen
  ved godkendelse (§8.2) ikke valgfri.

  **Genåbningskriterium:** måler 4.5, at redaktøren har brug for flaget forespørgbart
  *efter* afgørelsen (fx til trin 6's UI), er `proposal_flags` en additiv kolonne, der kan
  komme til på en base, som alligevel skal bygges om. Valget her lukker ikke den dør;
  den omvendte vej findes ikke.

- [x] **Step 2 — bortfalder.** Gjaldt kun flagkolonnen. Kollisionsrisikoen mod
  `interpretation_proposal_actor_check` (som forbyder `decided_*` på `proposed`) er
  dermed heller ikke aktuel: arket bærer intet, der skrives til
  `private.interpretation`, før mennesket faktisk har afgjort claimet.

- [x] **Step 3 — ingen maskinel H2-regel.** Skrevet i planen her og i builderens kode
  (`build_43b_proposal_manifest.py`): »mere præcist end kilden« afgøres **ikke** maskinelt
  i dette dagsværk. Fejlen i 4.3b var sproglig — *terminus ante quem* læst som dødsdato —
  begge claims stod ordret i teksten, og `date_raw`-claims har intet interval at
  sammenligne. En detektor ville derfor enten sammenligne modeloutput med modeloutput
  eller referere til felter, claimet ikke har. Begge tidligere udgaver af planen gjorde
  netop det.

- [x] **Step 4 — 4.5's plan arver forpligtelsen.** Når plan 4.5 skrives, skal arkets
  anbefalingskolonner udledes af de felter, der allerede kan forespørges (listen i Step 1
  punkt 3), efter mønsteret i `build_43b_judgement_sheet.py`: forudfyldt hvor maskinen kan
  afgøre det, tomt hvor kun mennesket kan. Forpligtelsen er skrevet ind som errata til
  spec §8.2, så den ikke kun lever i denne plan.

### Task 7: Rigtig kørsel (§7.5)

Mod **4.3b's base**.

- [x] **Step 1.** Dry-run: `finalized`, rullet tilbage, nul rækker efter.
- [x] **Step 2.** Apply: `interpretations_written` = manifestets ingestible-tal pr. element; alle klausul-links løser; **kanoniske aggregat-hashes uændrede**; `anon`-hashes uændrede.
- [x] **Step 3.** Replay: `already_applied`.
- [x] **Step 4.** **Skriv den forventede dispositionsfordeling ned FØR kørslen** — ellers er »som forventet« ikke en kontrol. Sammenhold bagefter.
- [x] **Step 5.** Negativ test: `principal`-claim på en persona-løs record afvises. **Bemærk:** den kan ikke køres inde i batchen, fordi alle 10 records har persona og eksporten afviser persona-løse. Kræver en separat autorisation med rollback, mod en af de records, Task 0 Step 5 målte.

### Task 8: Rapport

- [x] **Step 1.** `docs/evidensbaseret-genimport/proposal-ingest-147-4-4-rehearsal.md`.
  **Det blev seks tal, ikke fem** — Task 5's `persona_role_map` er fail-closed og har derfor
  sin egen afvisningsgrund (`ukendt_rolle`, målt til 0). Alle hashes, dispositionsfordeling
  forventet vs. målt (otte tal, nul afvigelser), og udfaldet af Task 5 og 6 står i rapporten.
  **Ud over planen:** Task 0's måling 2 var uafklaret (»blev aldrig gemt«); en read-only probe
  har nu fordelt de syv kontrakt-afviste pr. record — **alle syv er IV-34's**, ingen anden
  post bidrog. Attributionen er dermed målt, ikke sluttet af at IV-34 var markeret `delvis`.
- [x] **Step 2.** Changelog-post og `status.md` skrevet i `19cf97f`, afstemt efter Task 6 i
  `0f5e10c`, og henviser nu til rapporten. **Modenheden hæves ikke:** rækken dækker også
  promotion, som er urørt, og grenen er umerget.
- [x] **Step 3.** Rapportens afsnit 9, med konsekvensen sagt i hverdagssprog: kører ingesten
  mod prod, kan den ikke fortrydes uden at rulle hele databasen tilbage.
- [x] **Step 4.** Restoren `daa43b_20260912192527` er **bevaret** og markeret som sådan i
  rapportens afsnit 11. Sletning er en gate efter 4.5, fordi klausul-id'erne er
  database-genererede (spec §3).

---

## Selvreview-checkliste

- [ ] Foreligger Task 0's fem målinger, før noget blev bygget?
- [ ] Er de lukkede mængder udvidet **alle** fire steder plus `db-rls`?
- [ ] Har `deterministic_uuid` en fast testvektor, og står det i koden, at den ikke er RFC-konform v5?
- [ ] Kan et enkelt dårligt claim stadig fælde en hel record? (H1 og dubletter i builderen, ikke writeren.)
- [ ] Afstemmer R-klienten writerens returtal mod manifestets pr. element?
- [ ] Slipper et rigtigt navn med tal igennem denylisten — og ligger listen i profilen, ikke i kode?
- [ ] Står det i koden, at denylisten er en tidsbesparelse og ikke en korrekthedsgate?
- [ ] Er der skrevet en forventet dispositionsfordeling **før** kørslen?
- [ ] Er de kanoniske aggregat-hashes uændrede efter apply?
- [ ] Står det i rapporten, at prod-fortrydelse ikke findes?
- [ ] Er restoren bevaret til 4.5?
- [x] Er reviewsignalets kanal **valgt** (ikke udskudt), begrundet, og står genåbningskriteriet skrevet ned?

## Ændringslog

**2026-09-13, omskrevet fra bunden.** Første udgave fik 13 fund af første læser
(Codex `gpt-5.6-sol`); rettelserne blev skrevet som præambel uden at ændre
task-kroppen, hvilket anden læser (Fable) fandt som blokerende fund F1. Denne udgave
bærer rettelserne i selve stepsene.

Væsentlige ændringer i forhold til første udgave:

| | |
| --- | --- |
| H1 (relation uden modpart) | flyttet fra writeren til **builderen** — ét element er én record |
| H2 (mere præcist end kilden) | **opgivet som maskinel regel**; fejlen var sproglig, ikke numerisk |
| Denylisten | lukket, normaliseret, anchored — og i **profilen**, ikke i kode |
| Cache-adressering | eksplicit filliste + re-udledning med kørslens egen nøgleudledning |
| Regnskab | **fem** tal, ikke tre; writeren returnerer pr. element |
| Nøgleinput | kanonisk JSON; spec'ens fem felter fastholdt (ingen errata) |
| Klausulopslag | kardinalitet præcis 1, hele vejen fra anchor |
| `persona_role` | målt først; spec §7.2's hul for `event.*` erkendt |
| Reviewsignal | afgøres **her**, ikke udskudt til 4.5 |
| Task 0 | ny — fem målinger, der tidligere var antagelser |

Segmenteringsfejlen bag 4.3b's sønderdelte sætning (`VI.` som egen klausul) hører til
4.1b's motor og er registreret som **issue #189**.

**2026-09-15, Task 6 afgjort.** Projektejeren valgte menneskearket frem for en
`proposal_flags`-kolonne. Task 6's steps bærer begrundelsen og genåbningskriteriet;
`proposal_flags` er fjernet fra Filoversigten, og forpligtelsen for 4.5's ark er skrevet
som errata til spec §8.2. Rækkefølgen var det afgørende: havde Task 6 ligget før Task 7,
havde kolonnen været billig — fordi de 84 rækker allerede står i restoren, er den samme
kolonne nu en ombygning.
