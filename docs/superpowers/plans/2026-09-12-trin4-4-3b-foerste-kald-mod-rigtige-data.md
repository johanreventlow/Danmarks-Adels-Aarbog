# Trin 4 · dagsværk 4.3b: første modelkald mod rigtige data — implementeringsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Få svar på det spørgsmål, hele trin 4 hviler på og som stadig er ubesvaret: **udtrækker modellen noget brugbart af ægte DAA-prosa?** Et lille udvalg afdøde personers biografier køres gennem den kæde, 4.3a byggede, og resultatet bedømmes mod et stopkriterium, projektejeren sætter **før** kørslen.

**Architecture:** Ingen ny motor. 4.3a's runner, gate, ledger og cache bruges som de er. Det nye er tre ting: en restore med **fyldt klausullag**, et udvalg af records, og en bedømmelse.

**Tech Stack:** Python 3, R (DBI/RPostgres), PostgreSQL 17 lokalt, `codex exec`.

**Spec:** `docs/superpowers/specs/2026-09-06-trin4-fortolkningskaede-og-klausulgranularitet-design.md` §6.5 (rigtig kørsel), §9.1-9.2 (privatliv), §10 (gates).

**Forudgående:** `docs/evidensbaseret-genimport/runner-rehearsal-147-4-3a.md`.

---

## Dette dagsværk er også en prøve på sporet

4.3a byggede meget maskineri — gate, cache, ledger, fejltaksonomi, claim-kontrakt — uden at
**én eneste rigtig biografi** er blevet behandlet. Vi ved, at kæden virker på en post, jeg
selv har opdigtet i pænt og regelmæssigt sprog. Vi ved intet om, hvordan den klarer
forkortelser, OCR-støj, indskudte sætninger og 1800-tals ortografi.

Derfor er 4.3b ikke kun »næste trin«. Den er den billigste anledning til at opdage, at
resten af trin 4 ikke er pengene værd — og den anledning bliver dyrere for hvert dagsværk,
den udskydes.

**Planen er med vilje lille.** Der bygges intet nyt, før resultatet er set.

## Spec-afvigelse, der kræver GO

### E. Færre end 10 records i første omgang

§6.5 siger »10 afdøde records«. Planen foreslår at begynde med **5**, se på dem, og køre de
resterende 5 bagefter, hvis de første ser fornuftige ud.

Begrundelse: det er første gang persondataværnene er i reel brug frem for i test, og første
gang ægte prosa møder prompten. Halverer man første kørsel, halverer man også prisen for at
opdage, at prompten skal skrives om. Der er intet at vinde ved at sende alle 10 på én gang —
kvoten er ikke problemet, og cachen gør en genkørsel af de første 5 gratis.

Det samlede krav på 10 records opfyldes stadig, blot i to skridt.

## Global Constraints

- **Ingen prod-mutation.** Alt sker mod en lokal restore. Trin 4's tre migrationer er
  stadig ikke i produktionen, og dette dagsværk ændrer ikke på det.
- **Kun `eligible` records.** Udvalget tages fra ledgerens 488 godkendte, aldrig fra de 103
  udelukkede — og runneren slår op i ledgeren for hvert eneste kald uanset.
- **Kun afdøde hovedpersoner.** Det følger af ledgeren, men skrives eksplicit: de fem regler
  skal alle være grønne for hver valgt record.
- **Prosaen forlader ikke maskinen ud over modelkaldet.** Ingen biografitekst i logs, i
  rapporten, i commit-beskeder eller i chatten. Rapporten citerer **claims**, ikke kilde.
- **Kørslen sker bag Seatbelt-gaten** med adgangstesten bestået umiddelbart før.

## Roadmappens seks adgangskrav

1. **Roadmapmål:** trin 4, den fælles fortolkningskæde (#147).
2. **Værdikædeled:** »Extractor-runner og modelkald« flyttes mod `integreret ende-til-ende`
   for 2018-20 — men først når 4.4 har ingestet resultatet. 4.3b leverer inputtet.
3. **Generel, profil eller legacy:** ingen ny motor; kun en kørsel og en bedømmelse.
4. **Redaktionel værdi:** det første rigtige svar på, om modellen kan læse bogen. Ingen
   claims promoveres — de er forslag, ikke fakta.
5. **Bevis:** manifest `green`, alle claims citerer eksisterende ordinaler, forbrug målt pr.
   record, og **projektejerens bedømmelse mod stopkriteriet**.
6. **Erstatter:** intet.

## Filoversigt

| Fil | Ændring |
| --- | --- |
| `.claude/skills/daa-extract/scripts/run_evidence_43b.py` | **Ny.** Kørselsscript; genbruger 4.3a's runner uændret. |
| `docs/evidensbaseret-genimport/runner-rehearsal-147-4-3b.md` | **Ny.** Rapport med tal, forbrug og bedømmelse. |
| `docs/decisions.md` | Stopkriteriet + GO'et. |

---

### Task 0: Restore med fyldt klausullag

**Dette er ikke en formalitet.** Runneren sender modellen *klausuler* og kræver, at claims
citerer klausul-ordinaler. Prod-dumpet har **ingen klausuler** — 4.1c's writer er kørt mod
en restore, aldrig mod produktionen. Uden dette trin er der intet at sende.

- [ ] **Step 1.** Frisk restore af prod-dumpet. Platformrollerne oprettes **før**
  `pg_restore --no-owner --no-privileges`, ellers fejler ~111 GRANT-sætninger.
- [ ] **Step 2.** `db-migrations.sql` for at få trin 4's skema (klausulkolonner,
  writer, prædikattabel).
- [ ] **Step 3.** Kør 4.1b's segmentering og 4.1c's `clause_evidence`-writer, så de 591
  records får deres 868 klausuler. Forvent samme tal som 4.1c's rehearsal; **afvigelser
  rapporteres frem for at accepteres**.
- [ ] **Step 4.** Kør `export_model_eligibility.R` mod netop denne base og gem ledgerens
  SHA-256. Det er **den** ledger, kørslen bindes til — ikke en tidligere.

**Verify:** 591 records, 868 klausuler, ledger med 488 `eligible` (eller et nyt tal, der er
forklaret).

### Task 1: Udvalget

- [ ] **Step 1.** Vælg **5** records fra ledgerens `eligible`. Udvælgelsen skal være
  **deterministisk og dokumenteret** — fx de fem første efter `record_key COLLATE "C"` med
  mindst 3 klausuler. Ikke et skøn, og ikke de »pæneste«: et udvalg, der er valgt for at se
  godt ud, måler ingenting.
- [ ] **Step 2.** Bekræft for hver: `status = eligible`, alle fire regler grønne, og
  `record_input_sha256` matcher det input, kørslen faktisk vil sende.
- [ ] **Step 3.** Skriv record-nøglerne og ledgerens SHA i GO-anmodningen. **Ingen tekst.**

### Task 2: Gaten — projektejerens GO

Spec §10 kræver fire ting før første kald mod rigtige data. De skal alle foreligge:

- [ ] **Step 1.** Hash-bundet eligibility-ledger (Task 0 Step 4). ✓ når SHA er skrevet ned.
- [ ] **Step 2.** Behandlingsgrundlaget kvitteret (spec valg 5).
- [ ] **Step 3.** **Stopkriteriet sat af projektejeren, skriftligt, FØR kørslen.** Uden et
  tal på forhånd bliver »det ser da fornuftigt ud« til et ja. Forslag til formen: *andelen
  af claims, der er korrekte OG citerer den rigtige klausul, skal være mindst X %; ellers
  standser sporet og revurderes.* Tallet er projektejerens, ikke planens.
- [ ] **Step 4.** Projektejerens GO med record-nøgler, ledger-SHA og forventet forbrug.

**Uden alle fire: intet kald.**

### Task 3: Kørslen

- [ ] **Step 1.** Adgangstesten umiddelbart før kaldet. `GATE_FAILED` ⇒ stop.
- [ ] **Step 2.** Kør de 5 records gennem `run_record_guarded` med den rigtige ledger.
  Én record ad gangen (§6.1).
- [ ] **Step 3.** Mål forbrug **pr. record** — det er tallet, trin 6 skal budgetteres på.
- [ ] **Step 4.** Manifest `green` kræver, at **hver** record har en valideret cachepost.
  Delvis dækning er `pending`, og så stopper dagsværket med et navngivet fund.
- [ ] **Step 5.** Kandidaterne er `proposed`. **Intet promoveres**, intet skrives til det
  kanoniske lag. Det er 4.4's og 4.5's arbejde.

### Task 4: Bedømmelsen — dagsværkets egentlige leverance

- [ ] **Step 1.** Læg hver records claims op mod dens klausuler og afgør for hvert claim:
  (a) er påstanden sand ifølge teksten, (b) citerer den den rigtige klausul, (c) er
  værdien ordret hvor den skal være. Det er en **menneskelig** bedømmelse — projektejerens.
- [ ] **Step 2.** Tæl. Sammenhold med stopkriteriet fra Task 2 Step 3.
- [ ] **Step 3.** Noter, hvad modellen **oversprang** — udeladelser er sværere at få øje på
  end fejl, og de er det, der afgør, om laget kan bære en senere promotion.
- [ ] **Step 4.** Beslut: videre til de resterende 5 records, eller stop og revidér
  prompten.

### Task 5: Rapport

- [ ] **Step 1.** Rapport med: udvalg, ledger-SHA, forbrug pr. record, claims pr. record,
  bedømmelsens tal, og hvad der blev oversprunget. **Citér claims, aldrig kildetekst.**
- [ ] **Step 2.** Changelog + `status.md`. Hvis kriteriet ikke er opfyldt, skal det stå
  lige så tydeligt, som hvis det var.
- [ ] **Step 3.** Ryd op: lokal base droppet, ledger- og cachefiler slettet, midlertidige
  mapper væk. Kørslens artefakter må ikke ligge og flyde — de indeholder biografitekst.

---

## Selvreview-checkliste

- [ ] Er udvalget deterministisk — eller valgte jeg poster, der ser pæne ud?
- [ ] Er stopkriteriet sat **før** kørslen og af projektejeren?
- [ ] Slog runneren op i ledgeren for **hvert** kald, ikke kun én gang indledningsvis?
- [ ] Bestod adgangstesten umiddelbart før kaldet — ikke tidligere på dagen?
- [ ] Er der biografitekst i rapporten, logs, commit-beskeder eller chatten?
- [ ] Er klausultallene fra Task 0 sammenholdt med 4.1c's, eller kopieret?
- [ ] Står udeladelserne i rapporten, eller kun fejlene?
- [ ] Er konklusionen skrevet lige så tydeligt, hvis den er negativ?

## Anden læser

Planen læses af Codex `gpt-5.6-sol` før Task 0, jf. decisions 2026-09-06 (valg 3). Bed
læseren særligt efterprøve:

1. **Om Task 0 er fuldstændig.** Mangler der et led mellem prod-dumpet og et brugbart
   klausullag, opdages det først midt i kørslen.
2. **Om afvigelse E (5 frem for 10) svækker beviset**, eller blot deler det i to.
3. **Om bedømmelsen i Task 4 kan gennemføres uden at citere kildetekst** — hvis ikke, skal
   formen ændres, ikke reglen.
4. **Om noget i planen kan sende en ikke-eligible record afsted** trods ledgeren.
