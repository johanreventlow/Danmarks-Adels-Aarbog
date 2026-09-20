# Trin 4 · dagsværk 4.3b: første modelkald mod rigtige data — implementeringsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Få svar på det spørgsmål, hele trin 4 hviler på og som stadig er ubesvaret: **udtrækker modellen noget brugbart af ægte DAA-prosa?** Et lille udvalg afdøde personers biografier køres gennem den kæde, 4.3a byggede, og resultatet bedømmes mod et stopkriterium, projektejeren sætter **før** kørslen.

**Architecture:** Ingen ny motor. 4.3a's runner, gate, ledger og cache bruges som de er. Det nye er fire ting: en restore med **fyldt klausullag** (hele kæden fra dump til runner-input, se Task 0), et **stratificeret** udvalg, et **pre-run-manifest** som GO-grundlag, og en bedømmelse i et privat, hashet ark.

**Tech Stack:** Python 3, R (DBI/RPostgres), PostgreSQL 17 lokalt, `codex exec`.

**Spec:** `docs/superpowers/specs/2026-09-06-trin4-fortolkningskaede-og-klausulgranularitet-design.md` §6.5 (rigtig kørsel), §9.1-9.2 (privatliv), §10 (gates).

**Forudgående:** `docs/evidensbaseret-genimport/runner-rehearsal-147-4-3a.md`.

---

## Revision 1 (2026-09-12) — efter adversarial gennemgang (Codex `gpt-5.6-sol`)

> **Samlet dom: »Planen er ikke klar til udførelse.«** 12 fund, heraf 5 blokerende. Alle
> accepteret. To af dem var brister i **allerede merget kode** og er rettet særskilt i
> PR #185 — de hører ikke til planen, men de ville have gjort dagsværket usikkert.

### R1 (BLOKERENDE, rettet i #185): værnet bandt ikke hashen til det afsendte input

`run_record_guarded` modtog `record_input_sha256` som argument fra kalderen og beregnede den
aldrig af sit eget `export`. En kalder kunne opgive en godkendt records nøgle og hash og
sende et andet indhold videre. 4.3a's kørselsscript demonstrerede præcis den form.
**Lukket:** hashen beregnes nu af `export`, og prompten bindes til det objekt, guarden så.

### R2 (BLOKERENDE, rettet i #185): de to hashes kunne aldrig matche

Ledgeren hashede `string_agg` over alle observationer, runneren en JSON-serialisering.
Kontrollen ville enten afvise alt eller blive omgået. **Lukket:** én definition,
`canonical_record_input` = sha256 af helpostens tekst, brugt af både SQL og Python.

### R3 (BLOKERENDE): hele leddet fra database til runner-format manglede

»Kør 4.1b's segmentering og 4.1c's writer« er ikke en procedure. Task 0 beskrev hverken
eksporten af helposterne, opbygning og validering af klausulledgeren, writerens payload og
autorisation, eller — vigtigst — **eksporten af de færdige klausuler til det objekt,
`run_record_guarded` skal modtage**. Opdages det midt i kørslen, er dagsværket spildt.
Task 0 er skrevet om med navngivne mellemprodukter og en model-fri preflight.

### R4 (BLOKERENDE): planen ville ødelægge den restore, 4.4 og 4.5 skal bruge

Spec §3 siger udtrykkeligt, at 4.3b-4.5 **deler én restore**, fordi klausul-id'erne er
database-genererede. Task 5 Step 3 ville droppe basen og slette artefakterne — så kunne 4.4
ikke ingeste 4.3b's batch mod de samme klausuler. Oprydningen er vendt om: call-dirs ryddes
straks, restoren og de hash-bundne artefakter **bevares** til efter 4.5, med 0600, navngivet
placering og en eksplicit sletningsgate.

### R5 (BLOKERENDE): GO'et manglede den manifest-hash, §10 kræver

Spec §10 kræver projektejerens GO med **manifest-hash og budget**. Planen bad om record-nøgler
og ledger-SHA. Der skal derfor bygges et `pending` **pre-run-manifest** før modellen kaldes —
records, inputhashes, ledgerhash, profil, prompt, model, skema, budget — og dets hash er
GO-grundlaget. Resultatmanifestet afledes bagefter uden at ændre den godkendte inputidentitet.

### R6 (MAJOR): »citér claims« kan selv offentliggøre kildetekst

Flere prædikater kræver **ordrette** værdier. En rapport, der gengiver claims, kan derfor
gengive biografitekst, selv om den ikke citerer klausuler — i modstrid med planens egen regel.
**Rettet:** den committede rapport rummer kun record-nøgler, prædikater, domme og aggregater.
Selve bedømmelsen sker i et lokalt `0600`-ark; rapporten henviser til dets hash.

### R7 (MAJOR): bedømmelsen kunne ikke efterprøves

Der er ingen konflikt i, at projektejeren læser kildetekst lokalt. Konflikten er, at
rapporterede domme om sandhed og udeladelser **ikke kan auditeres ud fra claims alene**.
**Rettet:** et privat bedømmelsesartefakt med claim-id, klausulordinal, dom pr. kriterium og
en særskilt liste over forventede udtræk. Hashet; kun hash, metode og tal committes. Slettes
efter projektejerens godkendelse, ikke automatisk ved dagsværkets slutning.

### R8 (MAJOR): stopmetrikken målte kun præcision — ikke dækning

»Andel korrekte claims« kan blive 100 %, hvis modellen returnerer ét sikkert claim og
overspringer alt andet. Planen erkendte selv, at udeladelser afgør, om laget kan bære
promotion — og lod dem så være ude af kriteriet. **Metrikken kan altså give GO til et
ubrugeligt spor.** Erstattet af fem mål med hver sin tærskel.

### R9 (MAJOR): planen afleverede en ufuldstændig beslutning

At projektejeren vælger tærsklen er rigtig governance. Men planen foreslog intet tal, viste
ingen konsekvenser og definerede ikke nævneren — ejeren blev bedt om at opfinde målemetoden.
**Rettet:** planen foreslår nu konkrete tærskler med begrundelse, som projektejeren godkender
eller ændrer. Og: stopkriteriet er **ikke** en af §10's fire gater, som planen påstod — det er
et additivt dagsværksgreb. Rettet i teksten.

### R10 (MAJOR): 5+5 var ikke ét sammenligneligt bevis

Der er ingen teknisk grund til at køre ti i én omgang. Men »hvis de første ser fornuftige ud«
gjorde de sidste fem betingede, og deres udvalg var udefineret. Ændres prompten efter de
første fem, er de to halvdele heller ikke ét ti-record-bevis. **Rettet:** alle ti defineres
før første kald og køres under samme frosne profil/prompt/model/skema. Ændres prompten,
nulstilles beviset, og ti nye records køres under den nye version.

### R11 (MAJOR): udvalget målte ikke det, dagsværket skal undersøge

»De fem første med mindst tre klausuler« er deterministisk, men et alfabetisk prefix kan let
være homogent. Determinisme forhindrer cherry-picking; den skaber ikke informationsværdi — og
dagsværkets formål er netop at møde forkortelser, OCR-støj og ortografi. **Rettet:** hash-bundet
stratificering efter målbare signaler, deterministisk udvalg inden for hvert stratum.

### R12 (MINOR): »proposed« forvekslede kontrakt med databasetilstand

4.3b producerer validerede claims; det er 4.4, der opretter `interpretation_proposal`.
Omformuleret til »validerede forslag til senere ingest; ingen `interpretation_proposal` er
endnu oprettet«.

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

### E. Ti records, kørt som 5 + 5 — ikke fem med option på fem mere

§6.5 kræver 10 afdøge records. Planen deler kørslen i to bundter på fem, så prisen for at
opdage en promptfejl halveres. Der er ingen teknisk grund til at kalde ti i én omgang: §6.4
tillader batches på 5-10, og cachen gør genkørsel af de første fem gratis.

**Men opdelingen er operationel, ikke en reduktion af beviset** (R10). Derfor:

- **Alle ti records defineres før første kald** — også de sidste fem. Ingen af dem er
  betinget af, at de første »ser fornuftige ud«.
- **Alle ti køres under samme frosne kontrakt:** samme profilversion, promptfil og -hash,
  model og outputskema.
- **Ændres prompten undervejs, nulstilles 4.3b-beviset.** Så køres ti records under den nye
  version — de fem gamle tæller ikke med, fordi de så er målt på noget andet.

## Global Constraints

- **Ingen prod-mutation.** Alt sker mod en lokal restore. Trin 4's tre migrationer er
  stadig ikke i produktionen, og dette dagsværk ændrer ikke på det.
- **Kun `eligible` records.** Udvalget tages fra ledgerens 488 godkendte, aldrig fra de 103
  udelukkede — og runneren slår op i ledgeren for hvert eneste kald uanset.
- **Kun afdøde hovedpersoner.** Det følger af ledgeren, men skrives eksplicit: de fem regler
  skal alle være grønne for hver valgt record.
- **Prosaen forlader ikke maskinen ud over modelkaldet.** Ingen biografitekst i logs,
  commit-beskeder eller chatten. Og (R6) **heller ikke i rapporten via claims**: flere
  prædikater kræver ordrette værdier, så en gengivet claim-værdi *er* kildetekst. Den
  committede rapport rummer record-nøgler, prædikater, domme og tal — aldrig rå `value`.
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
| `.claude/skills/daa-extract/scripts/build_43b_runner_input.py` | **Ny.** Task 0 Step 8-9: DB → runner-format + model-fri preflight. |
| `.claude/skills/daa-extract/scripts/build_43b_manifest.py` | **Ny.** Pre-run-manifestet, hvis hash er GO-grundlaget (R5). |
| `.claude/skills/daa-extract/scripts/run_evidence_43b.py` | **Ny.** Kørselsscript; genbruger 4.3a's runner uændret. |
| `docs/evidensbaseret-genimport/runner-rehearsal-147-4-3b.md` | **Ny.** Rapport — tal, hashes og aggregater, ingen claim-værdier. |
| `docs/decisions.md` | Tærsklerne, afvigelse E og GO'et. |

Uden for repoet (privat, `0600`, bevares til efter 4.5): restore-basen, eligibility-ledgeren,
begge manifester, svar-cachen og bedømmelsesarket.

---

### Task 0: Restore med fyldt klausullag

**Dette er ikke en formalitet.** Runneren sender modellen *klausuler* og kræver, at claims
citerer klausul-ordinaler. Prod-dumpet har **ingen klausuler** — 4.1c's writer er kørt mod
en restore, aldrig mod produktionen. Uden dette trin er der intet at sende.

Hvert led har et navngivet mellemprodukt. »Kør 4.1b og 4.1c« var ikke en procedure (R3).

- [x] **Step 1.** Frisk restore af prod-dumpet. Platformrollerne (`dashboard_user`,
  `supabase_auth_admin`, `supabase_storage_admin`, `supabase_realtime_admin`, `pgbouncer`
  m.fl.) oprettes **før** `pg_restore --no-owner --no-privileges`, ellers fejler ~111
  GRANT-sætninger. **Basen navngives og bevares** — 4.4 og 4.5 skal bruge netop den (R4).
- [x] **Step 2.** `db-migrations.sql` for trin 4's skema (klausulkolonner, writer,
  prædikattabel). Verificér, at `private.source_observation.parent_observation_id` findes.
- [x] **Step 3.** **Eksportér helposterne** med `export_clause_source_texts.R` →
  `clause-source-texts-v1.json` + `clause-source-index-v1.json`.
- [x] **Step 4.** **Byg og validér klausulledgeren** med `build_clause_ledger.py` (4.1b's
  segmentering, profilens `clause_rules` v1.2.0) → ledgerfil + dens SHA-256.
- [x] **Step 5.** **Byg writer-payloaden** med `build_clause_evidence_manifest.py`, bundet
  til ledgerfilens SHA via `--expect-ledger-sha256`. Kræver renditionen genskabt fra PDF'en
  og hash-verificeret mod basens `content_sha256` — uden det kan offsets ikke oversættes.
- [x] **Step 6.** **Kør writeren** (`red_apply_reimport_clause_evidence`) og verificér med
  `db-verify`'s `#148`-blokke. Forvent 591 records / 868 klausuler som i 4.1c's rehearsal;
  **afvigelser rapporteres frem for at accepteres**.
- [x] **Step 7.** **Eksportér eligibility-ledgeren** mod netop denne base; gem dens SHA-256.
  Det er **den** ledger, kørslen bindes til.
- [x] **Step 8.** **Eksportér runner-inputtet**: pr. record helposten (`post_verbatim_text`,
  ankeret for `canonical_record_input`), dens klausuler som `(ordinal, verbatim_text,
  verbatim_sha256)` og personaen. Det er objektet, `run_record_guarded` modtager.
- [x] **Step 9 — model-fri preflight.** Byg og validér **alle ti** runner-input uden at kalde
  modellen: hver record er `eligible`, `canonical_record_input` matcher ledgerens hash, alle
  ordinaler er sammenhængende, og hver klausultekst matcher sin egen `verbatim_sha256`.
  Fejler ét af dem, stopper dagsværket her — før noget sendes.

**Verify:** 591 records, 868 klausuler, ledger med 488 `eligible` (eller et forklaret tal),
og ti preflight-validerede runner-input.

### Task 1: Udvalget

- [x] **Step 1 — stratificér, vælg så deterministisk (R11).** Et alfabetisk prefix er
  deterministisk, men kan let være homogent, og dagsværkets formål er netop at møde
  forkortelser, OCR-støj, indskud og ortografi. Definér strata på **målbare signaler**:
  tekstlængde (kort/middel/lang), klausulantal, tilstedeværelse af segmenteringsflag
  (`unknown_abbreviation` m.fl.), og om posten rummer ægteskabs- eller usikre datomønstre.
  Inden for hvert stratum vælges deterministisk (første efter `record_key COLLATE "C"`).
  Strata-definitionen hashes og skrives ned **før** udvælgelsen.
- [x] **Step 2.** Vælg **alle ti** records nu — fem til første bundt, fem til andet. Ingen af
  dem er betinget af, hvordan de første går (R10).
- [x] **Step 3.** Bekræft for hver: `status = eligible`, alle fire regler grønne, og
  `canonical_record_input(export)` er lig ledgerens `record_input_sha256`. Det er preflighten
  fra Task 0 Step 9; her dokumenteres blot resultatet.
- [x] **Step 4.** Skriv record-nøgler, strata og ledgerens SHA i GO-anmodningen. **Ingen tekst.**

### Task 2: Gaten — projektejerens GO

Spec §10 kræver tre ting før første kald mod rigtige data. Planen tilføjer en fjerde, som er
et **additivt dagsværksgreb** — ikke et krav fra §10 (R9 rettede den påstand).

- [x] **Step 1 (§10).** Hash-bundet eligibility-ledger (Task 0 Step 7). ✓ når SHA er noteret.
- [x] **Step 2 (§10).** Behandlingsgrundlaget kvitteret (spec valg 5).
- [x] **Step 3 (§10) — pre-run-manifestet.** §10 kræver GO med **manifest-hash og budget**,
  ikke kun ledger-SHA (R5). Byg derfor et `pending`-manifest **før** modellen kaldes, med:
  de ti record-nøgler, hver records `canonical_record_input`, ledgerens SHA, profil-id og
  -version, promptfil og -hash, model, outputskemaets SHA og det forventede tokenbudget.
  **Manifestets hash er GO-grundlaget.** Efter kørslen afledes et resultatmanifest uden at
  ændre den godkendte inputidentitet.
- [x] **Step 4 (additivt) — stopkriteriet, skriftligt, før kørslen.** Uden tal på forhånd
  bliver »det ser da fornuftigt ud« til et ja.

  Planen **foreslår** nedenstående; projektejeren godkender eller ændrer dem (R9 — det er
  ikke ejerens opgave at opfinde målemetoden). Ét samlet procenttal er utilstrækkeligt, fordi
  det kun måler præcision: en model, der returnerer ét sikkert claim og overspringer resten,
  ville score 100 % (R8).

  | Mål | Nævner | Foreslået tærskel |
  | --- | --- | --- |
  | **Præcision** — claimet er sandt ifølge teksten | alle claims | ≥ 90 % |
  | **Klausulbinding** — claimet citerer den rigtige klausul | alle claims | ≥ 90 % |
  | **Ordrethed** — værdien er ordret hvor prædikatet kræver det | claims m. ordret krav | ≥ 95 % |
  | **Dækning** — andel af menneskeligt annoterede udsagn, modellen fandt | annoterede udsagn | ≥ 60 % |
  | **Brugbarhed** — records med mindst ét korrekt claim | ti records | 10/10 |

  Begrundelse for niveauerne: præcision og binding skal være høje, fordi et forkert claim
  koster redaktionel tid at opdage. Ordrethed er strengere, fordi den er mekanisk og en fejl
  dér betyder, at prompten er misforstået. Dækning er sat lavere, fordi laget er **selektivt**
  efter invariant 6 — men under 60 % er det ikke rygraden, det henter. Brugbarhed på 10/10
  fanger, om enkelte posttyper falder helt igennem.

  **Kritiske fejltyper får selvstændig stopregel**, uanset procenterne: et claim om en
  **levende** person, eller et claim der citerer en klausul fra en anden record, standser
  sporet øjeblikkeligt.
- [x] **Step 5.** Projektejerens GO med **manifest-hash**, budget og de godkendte tærskler.

**Uden alle fem: intet kald.**

### Task 3: Kørslen

- [x] **Step 1.** Adgangstesten umiddelbart før kaldet. `GATE_FAILED` ⇒ stop.
- [x] **Step 2.** Kør de 5 records gennem `run_record_guarded` med den rigtige ledger.
  Én record ad gangen (§6.1).
- [x] **Step 3.** Mål forbrug **pr. record** — det er tallet, trin 6 skal budgetteres på.
- [x] **Step 4.** Manifest `green` kræver, at **hver** record har en valideret cachepost.
  Delvis dækning er `pending`, og så stopper dagsværket med et navngivet fund.
- [x] **Step 5.** Resultatet er **validerede forslag til senere ingest**. Der oprettes
  **ingen** `interpretation_proposal` — den tilstand kommer først i 4.4 (R12: kontraktstatus
  er ikke databasetilstand). Intet promoveres, intet skrives til det kanoniske lag.
- [x] **Step 6.** Kør første bundt på fem, derefter andet bundt på fem — **samme frosne
  kontrakt for begge**. Ændres prompten undervejs, nulstilles beviset (afvigelse E).

### Task 4: Bedømmelsen — dagsværkets egentlige leverance

Bedømmelsen sker i et **privat artefakt**, ikke i rapporten. Der er ingen konflikt i, at
projektejeren læser kildetekst lokalt — konflikten er, at domme om sandhed og udeladelser
**ikke kan efterprøves ud fra claims alene** (R7). Artefaktet gør dem auditerbare uden at
kildeteksten havner i repoet.

- [x] **Step 1 — opret bedømmelsesarket.** Lokalt, `0600`, uden for repoet. Én række pr.
  claim: claim-id, record-nøgle, klausulordinal, prædikat, værdi, **og klausulens tekst** —
  det sidste kun her. Plus en særskilt sektion pr. record: *hvilke udsagn i teksten burde
  have givet et claim?* Den liste er forudsætningen for at kunne måle dækning.
- [x] **Step 2 — døm hvert claim** på de tre kriterier: sandt ifølge teksten, citerer rigtig
  klausul, ordret hvor prædikatet kræver det. Menneskelig bedømmelse, projektejerens.
- [x] **Step 3 — tæl de fem mål** fra Task 2 Step 4 og sammenhold med tærsklerne.
- [x] **Step 4 — udeladelserne.** Sammenhold de forventede udtræk fra Step 1 med de faktiske
  claims. Udeladelser er sværere at få øje på end fejl, og de afgør, om laget kan bære en
  senere promotion.
- [x] **Step 5 — hash arket.** Kun hashen, metoden og aggregaterne går i rapporten.
  **Arket slettes først efter projektejerens godkendelse** — ikke automatisk ved dagsværkets
  slutning, for så kan konklusionen ikke efterprøves.
- [x] **Step 6 — beslut.** Er tærsklerne opfyldt: videre til 4.4. Ellers: stop, og revidér
  prompten frem for at sænke tærsklen.

### Task 5: Rapport

- [x] **Step 1.** Rapport med: strata og udvalg, ledger-SHA, **manifest-hash**, forbrug pr.
  record, antal claims pr. record, de fem måls tal, udeladelser og bedømmelsesarkets hash.
  **Ingen rå claim-værdier** — flere prædikater er ordrette, så værdien *er* kildetekst (R6).
- [x] **Step 2.** Changelog + `status.md`. Hvis tærsklerne ikke er opfyldt, skal det stå
  lige så tydeligt, som hvis de var.
- [x] **Step 3 — oprydning, vendt om (R4).** Spec §3: **4.3b-4.5 deler én restore**, fordi
  klausul-id'erne er database-genererede. Basen må derfor **ikke** droppes her.

  | Ryddes straks | Bevares til efter 4.5 |
  | --- | --- |
  | call-dirs | restore-basen |
  | overflødige kopier af eksporter | eligibility-ledger + dens SHA |
  | | pre-run- og resultatmanifest |
  | | svar-cachen |
  | | bedømmelsesarket (til godkendelse) |

  Det bevarede ligger `0600` i en navngivet privat mappe uden for repoet. **Sletningen er en
  eksplicit gate efter 4.5**, ikke en oprydning her — men den skal ske, for artefakterne
  indeholder biografitekst.

---

## Selvreview-checkliste

- [ ] Er udvalget **stratificeret** — eller er det bare et alfabetisk prefix, der tilfældigvis
      er homogent?
- [ ] Er alle ti records defineret før første kald, og kørt under samme frosne kontrakt?
- [ ] Foreligger **manifest-hashen** før GO — ikke kun ledger-SHA'en?
- [ ] Måler stopkriteriet også **dækning**, eller kun præcision?
- [ ] Er stopkriteriet sat **før** kørslen og af projektejeren?
- [ ] Slog runneren op i ledgeren for **hvert** kald, ikke kun én gang indledningsvis?
- [ ] Bestod adgangstesten umiddelbart før kaldet — ikke tidligere på dagen?
- [ ] Er der biografitekst i rapporten, logs, commit-beskeder eller chatten — **også via
      ordrette claim-værdier?**
- [ ] Er restoren bevaret til 4.4/4.5, eller nåede jeg at rydde den?
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
