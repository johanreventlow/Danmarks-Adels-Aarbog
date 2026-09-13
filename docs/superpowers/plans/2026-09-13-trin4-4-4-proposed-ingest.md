# Trin 4 · dagsværk 4.4: proposed-ingest — implementeringsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Få 4.3b's 86 validerede claims ind i databasen som **forslag** — `proposed`, aldrig kanoniske fakta — bundet til de klausuler, de citerer, så et menneske i 4.5 kan tage stilling til dem én ad gangen.

**Architecture:** En tredje elementoperation i #153's generelle writer, `interpretation_proposal`, bygget efter samme mønster som 4.1c's `clause_evidence`. Ingen ny motor, ingen ny transaktionsmodel.

**Tech Stack:** PostgreSQL 17 (DDL + PL/pgSQL), Python 3 til manifest-builder, R til apply-klienten, pytest + psql-tests.

**Spec:** `docs/superpowers/specs/2026-09-06-trin4-fortolkningskaede-og-klausulgranularitet-design.md` §7.

**Forudgående:** `docs/evidensbaseret-genimport/runner-rehearsal-147-4-3b.md` — 4.3b's kørsel, dens tal og de to fund nedenfor.

**Restore:** dagsværket kører mod **samme base som 4.3b** (spec §3: 4.3b-4.5 deler én restore, fordi klausul-id'erne er database-genererede). Der oprettes ingen ny.

---

## To huller fra 4.3b, som skal lukkes her

4.3b bestod alle fem tærskler, men den menneskelige bedømmelse fandt to ting,
ingen tærskel fangede. Begge har samme rod: **kontrakten kontrollerer form.** Et
claim kan være velformet, sandt og alligevel ubrugeligt — og netop derfor er
ingest-laget det rigtige sted at standse dem.

### H1. Et `relation.*`-claim uden identificerbar modpart

To af seks relations-claims i 4.3b pegede ikke på nogen: `relation.marriage` =
`NN.` og `relation.child` = `4 sønner`. Begge **sande** — bogen siger netop det —
og begge formelt gyldige, fordi kontrakten kun kræver et objekt med ordret `raw`.

Men »4 sønner« er et **antal**, ikke et barn. Bliver det en
`interpretation_proposal`, foreslår vi et barn, der ikke findes, og et menneske i
4.5 skal bruge tid på at afvise noget, maskinen kunne have set.

**Afvises i writeren** med eget fejltoken. Grænsen er ikke »værdien er tom«, men
»værdien identificerer ingen«: et navneløst `NN.`, eller en ren mængdeangivelse
(`4 sønner`, `to døtre`, `flere børn`). Mønstret skal være **snævert og testet** —
det må ikke ramme et rigtigt navn, der tilfældigvis begynder med et tal.

### H2. Et claim, der er mere præcist end kilden

I-11 fik to dødsclaims: `† 1342/1353` — bogens egen tvetydighed — og
`død 1353 (23. april)`, som **vælger** det ene år og tilføjer en dato. Det sidste
er 4.3b's eneste usande claim, og den farligste slags: det ser ud som kvalitet.

Invariant 5 findes netop for at bære fuzzy datoer som `(date_min, date_max)`.
Et forslag, der afgør en tvetydighed, kilden ikke afgør, må ikke kunne promoveres.

**Dette er sværere end H1**, fordi det kræver at sammenligne to claims om samme
forhold på samme record. Task 3 Step 4 afgør formen; hvis den ikke kan lukkes
maskinelt med rimelig sikkerhed, **flages den i stedet til mennesket i 4.5** frem
for at blive gættet på. En detektor, der rammer forkert, er værre end ingen.

## Global Constraints

- **Ingen prod-mutation.** Alt sker mod 4.3b's restore. Trin 4's migrationer er
  stadig ikke i produktionen.
- **Intet promoveres.** Alle interpretationer er `proposed`, `method='model'`,
  version 1. Kanoniske tabeller må ikke ændres — neutralitetsbevis kræves.
- **Ingen ny model-kørsel.** 4.4 ingester 4.3b's eksisterende batch. Skulle en
  genkørsel blive nødvendig, er det et nyt GO.
- **Ingen kildetekst i payload, logs eller rapport.** Claims bærer værdier, som
  kan være ordrette udsnit — de hører i databasen, ikke i et manifest, der
  rejser, eller i en commit-besked.
- **Fortrydelse findes ikke i prod.** §7.4: fortrydelse sker ved restore i
  restore-baser. At prod-fortrydelse mangler, er en forudsætning for et senere
  prod-GO (åbent punkt 11.5) og skal stå i rapporten.

## Roadmappens seks adgangskrav

1. **Roadmapmål:** trin 4, den fælles fortolkningskæde (#147 leverance 2).
2. **Værdikædeled:** »Proposed-ingest og promotion« flyttes fra `isoleret
   implementeret` mod `integreret ende-til-ende` for 2018-20 — promotionsdelen
   først i 4.5.
3. **Generel, profil eller legacy:** generel motor. Tredje elementoperation i
   #153's writer; ingen profilændring.
4. **Redaktionel værdi:** for første gang ligger der forslag i databasen, som en
   redaktør kan tage stilling til. Uden dette trin er 4.3b's claims kun en fil.
5. **Bevis:** 4.3b's batch ingestet (§7.5) — antal = manifest, alle links løser,
   neutralitets- og `anon`-hashes uændrede, replay `already_applied`,
   dispositionsfordeling som forventet, og en negativ test pr. afvisningsgrund.
6. **Erstatter:** intet. `project_evidence.R` forbliver dry-run til trin 6.

## Filoversigt

| Fil | Ændring |
| --- | --- |
| `schema.sql` | `private.deterministic_uuid(text)`; writer-operationen; operation-CHECK; dispositionskoder. |
| `db-migrations.sql` | Samme, idempotent, med kontrakt-drift-guard som 4.1c. |
| `db-rls.sql` | ACL for den nye operation. |
| `db-verify.sql` | `OK: #147 4.4`-blok + negative prober. |
| `tests/sql/test-interpretation-proposal.sql` | **Ny.** Kontrakttest, rød først. |
| `.claude/skills/daa-extract/scripts/build_43b_proposal_manifest.py` | **Ny.** Fra 4.3b's cache til writer-payload. |
| `.claude/skills/daa-extract/scripts/apply_reimport_helpers.R` | `interpretation_proposal` fire steder. |
| `.claude/skills/daa-extract/references/reimport-profiles/daa-2018-20-interpretation-proposal-v1.json` | **Ny.** |
| `.github/workflows/ci.yml` | SQL-testen + Python-testen. |

---

### Task 1: Kontrakttesten (rød først)

- [ ] **Step 1.** `tests/sql/test-interpretation-proposal.sql` — skal fejle med
  `REIMPORT_WRITER_AUTHORIZATION_INVALID`, før DDL'en findes. Samme mønster som
  4.1c's Task 1.
- [ ] **Step 2.** Positive blokke: ét `principal`-claim med én citeret klausul; ét
  med flere; ét `other`-claim (persona `NULL`, disposition `afventer_identitet`).
- [ ] **Step 3.** Negative blokke, én pr. afvisningsgrund fra §7.1 — ukendt
  klausul, hash-afvigende klausul, klausul uden for recordens helpost, inaktivt
  prædikat, værdi ≠ `value_kind`, confidence uden for [0,1], `principal` på en
  record uden persona.
- [ ] **Step 4.** Negative blokke for **H1 og H2** (se Task 3).

### Task 2: `deterministic_uuid` og nøglen

- [ ] **Step 1.** `private.deterministic_uuid(text)`: første 16 bytes af
  `digest(input,'sha256')`, versionsnibble 5, variantbits efter RFC 4122. Basen
  har kun `pgcrypto` — ingen `uuid-ossp`, ingen PG18 `uuidv5()` (spec §7.1 fund 11).
- [ ] **Step 2.** `interpretation_key` = `deterministic_uuid(source_id | record_key
  | predicate | cited ordinals | value_sha256)`. Skriv rækkefølgen og separatoren
  **eksplicit** i en kommentar — to implementeringer, der er uenige om formatet,
  giver tavse dubletter.
- [ ] **Step 3.** Findes nøglen, afvises elementet
  (`REIMPORT_WRITER_INTERPRETATION_PROPOSAL_EXISTS`). Genudtræk kræver en
  menneskelig `superseded`-beslutning og er trin 6.
- [ ] **Step 4.** Test: samme claim to gange giver samme nøgle; ændret værdi giver
  en anden; ændret ordinal-rækkefølge giver **samme** (sorteret før hashning).

### Task 3: Writeren

- [ ] **Step 1.** `private.write_interpretation_proposal` + wrapperen
  `public.red_apply_reimport_interpretation_proposal`. Udvid de lukkede mængder
  **fire steder** (event-CHECK, `validate_reimport_authorization_payload`,
  `red_finalize_reimport`, `red_reimport_batch_result`) plus `db-rls`'s to lister.
  4.1c's lære: glemmes ét sted, fejler writeren først ved apply.
- [ ] **Step 2.** Idempotent `extraction_run` pr. manifest (`run_key`), med usage i
  `manifest`. Post-conflict-lighedskontrol som 4.1c's, så en tidligere run-række
  med anden provenance ikke genbruges.
- [ ] **Step 3.** Klausulopslag via `(record, ordinal, verbatim_sha256)` — aldrig
  via UUID i payloaden. Hashen er det, der binder forslaget til den tekst, modellen
  faktisk så.
- [ ] **Step 4 — H1 og H2.**
  - **H1:** afvis `relation.*`-claims, hvis `value.raw` ikke identificerer nogen.
    Snævert mønster: rent `NN.`/`N.N.`, eller en ren mængdeangivelse
    (`<tal|talord> <søn|sønner|datter|døtre|børn>`) uden navn. Token:
    `REIMPORT_WRITER_RELATION_WITHOUT_COUNTERPART`. **Fire positive kontroller**
    skal bevise, at rigtige navne slipper igennem — herunder et navn med tal
    (»Christian 4.«) og et med forkortelse.
  - **H2:** afgør formen her. Kan to `person.death`-claims på samme record, hvor
    det ene spænd indeholder det andet, opdages maskinelt med rimelig sikkerhed?
    I så fald afvis det snævrere (`REIMPORT_WRITER_NARROWER_THAN_SOURCE`).
    **Kan det ikke, så lad være:** skriv begge som forslag, markér dem med en
    disposition, mennesket i 4.5 kan se, og skriv i rapporten hvorfor. En detektor,
    der rammer forkert, er værre end ingen.
- [ ] **Step 5.** Pr. claim: én `interpretation` (`proposed`, `model_inference`,
  `method='model'`, version 1) + `interpretation_observation` (`supporting`,
  ordinal) i **samme transaktion** under den deferred constraint
  `interpretation_has_observation`.
- [ ] **Step 6.** Klausulregnskab (§7.3): citerede klausuler får ny maskinel
  dispositionsversion `fortolkning_foreslaaet` eller `afventer_identitet`.
  Uciterede beholder deres — det skal **testes**, ikke antages.

### Task 4: Manifest-builder og R-klient

- [ ] **Step 1.** `build_43b_proposal_manifest.py`: fra 4.3b's svar-cache til
  writer-payload. Ét element pr. record. Bind til 4.3b's manifest-hash via
  `--expect-runner-manifest-sha256`, så forslagene ikke kan bygges fra en anden
  kørsel end den, projektejeren gav GO til.
- [ ] **Step 2.** Payloaden bærer `claim_id`, `predicate`, `interpretation_kind`,
  `value`, `confidence`, `cited_clauses[]` = `(ordinal, verbatim_sha256)`,
  `persona_role`. **Lukket nøglesæt** — payloaden lagres permanent i
  `private.reimport_event`.
- [ ] **Step 3.** `apply_reimport_helpers.R` kender operationen fire steder
  (`expected_counts`-nøgle `interpretation_proposals`, `dependency_class`, tælling,
  gateway-dispatch).
- [ ] **Step 4.** Ny reimport-profil, registreret i basen som 4.1c's.

### Task 5: Rigtig kørsel (§7.5)

Mod **4.3b's base**, ikke en ny.

- [ ] **Step 1.** Dry-run: `finalized`, rullet tilbage, nul rækker efter.
- [ ] **Step 2.** Apply: antal interpretationer = manifestets; alle
  klausul-links løser; **kanoniske aggregat-hashes uændrede**; `anon`-hashes
  uændrede.
- [ ] **Step 3.** Replay: `already_applied`.
- [ ] **Step 4.** Dispositionsfordeling opgjort og sammenholdt med det forventede
  (86 claims, heraf de to H1-afvisninger).
- [ ] **Step 5.** Negativ test mod basen: `principal`-claim på en af de tre
  persona-løse records afvises.

### Task 6: Rapport

- [ ] **Step 1.** Rapport med tal, hashes, dispositionsfordeling og — vigtigst —
  hvad H1 og H2 endte med. Hvis H2 ikke kunne lukkes maskinelt, skal det stå
  **tydeligt**, ikke gemmes som et forbehold.
- [ ] **Step 2.** Changelog + `status.md`-modenhed.
- [ ] **Step 3.** **Ryd ikke restoren** — 4.5 skal bruge den. Kun call-dirs og
  overflødige kopier.

---

## Selvreview-checkliste

- [ ] Er de lukkede mængder udvidet **alle** fire steder plus `db-rls`?
- [ ] Giver samme claim samme nøgle — og forskellig værdi en anden?
- [ ] Slipper et rigtigt navn med tal igennem H1-mønstret?
- [ ] Blev H2 lukket maskinelt, eller flaget til mennesket — og står valget i rapporten?
- [ ] Er de kanoniske aggregat-hashes uændrede efter apply?
- [ ] Beholder uciterede klausuler deres disposition? (Testet, ikke antaget.)
- [ ] Er der kildetekst i manifest, logs eller commit-beskeder?
- [ ] Står det i rapporten, at prod-fortrydelse ikke findes (§7.4, åbent punkt 11.5)?
- [ ] Er restoren bevaret til 4.5?

## Anden læser

Planen læses af Codex `gpt-5.6-sol` før Task 1, jf. decisions 2026-09-06 (valg 3).
Bed læseren særligt efterprøve:

1. **Om H1's mønster er snævert nok.** Det skal fange »4 sønner« og `NN.` uden at
   ramme et rigtigt navn. Hvor knækker det?
2. **Om H2 overhovedet bør forsøges maskinelt.** Planen tillader at opgive det —
   er det den rigtige afvejning, eller er der en sikker form, den har overset?
3. **Om `deterministic_uuid` er korrekt** efter RFC 4122, og om nøgleinputtets
   format er entydigt nok til at to implementeringer ikke kan divergere.
4. **Om noget i kæden fra 4.3b's cache til writeren kan tabe eller forveksle et
   claim** — særligt bindingen mellem citeret ordinal og klausul-UUID.
