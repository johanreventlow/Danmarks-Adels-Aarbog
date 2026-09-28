# Trin 4 · genbinding af 4.4: piloten om på de omsegmenterede klausuler — plan

Beslutning: `docs/decisions.md` 2026-09-27 (omsegmentering før 4.4), rækkefølgens skridt 5:
»Piloten om og kontrolmodellen på de nye forslag; derefter 4.4+4.5 i prod.« Omsegmenteringen
kørte i prod 2026-09-28 (`database-current-state.md` §9). Denne plan genbruger 4.5-planen
(`2026-09-23-trin4-4-5-pilot-afgoerelse-binding.md`) og kontrolmodel-planen
(`2026-09-27-trin4-kontrolmodel.md`) og beskriver kun det, der er anderledes.

## Kobling (CLAUDE.md-styringen)

1. **Roadmapmål:** trin 4, den fælles fortolkningskæde (#147), leverance 5.
2. **Værdikædeled:** fortolkning → afgørelse → binding, nu på de klausuler, prod faktisk har.
3. **Leverancetype:** genkørsel af en eksisterende, generel kæde; ingen ny mekanisme.
4. **Redaktionel værdi:** 4.5-pilotens og kontrolmodellens tal er målt på den defekte
   segmentering (decisions 2026-09-27). Først med nye tal kan 4.4+4.5 få prod-GO.
5. **Færdigbevis:** ≥30 bekræftede biografiske poster gennem hele kæden i én base, afgjort med
   kontrolmodellen og bundet; rapport med tal og hashes; 4.4's prod-GO-pakke genbundet.
6. **Erstatter:** 4.5's og kontrolmodellens resultater som grundlag for prod-overførslen.

## Projektejerens valg (2026-09-28)

- **P1 lukkes med Seatbelt-profilen**, ikke med `scram-sha-256` på lokal Postgres.
- **Claude starter modelkaldene** via runneren efter GO på manifestets hash.
- **Omsegmenteringens fortrydelsesvindue lukkes i samme GO som 4.4's prod-kørsel.**

## Forudsætning: P1 er lukket (review 35 §6 pkt. 2, »før næste modelkørsel«)

Grenen `fix/147-p1-runner-gate`:
- Runneren fælder et kald med værktøjsbrug (`tool_use`). Kontrakten er `evidence-runner-1.3`.
- Codex-versionen er bundet i manifestet og tjekkes før hvert kald.
- Seatbelt-profilen spærrer PII uden for hjemmemappen, lokal Postgres (TCP og socket), alle andre
  unix-sockets undtagen DNS og al skrivning undtagen call-dir og `~/.codex/installation_id`.
- Codex får et minimalt miljø.
- Adgangstesten er målt begge veje: ny profil `GATE_OK`, mains profil 19 huller.
- Én uafhængig opus-review: først NO-GO, efter rettelser GO. Grenen skal merges, før
  rapportens `repo_commit` sættes.

## Målt udgangspunkt (2026-09-28, kun tal)

| Fakta | Tal |
| --- | --- |
| Prod-dump (læse-kun, ingen skrivepause) | `ddbe94b8…`, tilstand `591\|984\|591\|1\|0\|0\|1`, klausuler 868 i gamle sæt / 984 i alt |
| Arbejdsbase | `daa44g_20260928170311`: restore = dump på tilstand, kanonisk og portabel anon. `db-migrations.sql` og `db-rls.sql` fra `main` er lagt på med 0 WARNING, så de 8 projektionsfunktioner fra #196 findes |
| Ledger (genbygget mod arbejdsbasen) | 488 `eligible` / 103 `excluded`; 0 status- og 0 hashændringer mod 4.3b's |
| Udvalg | de samme 40 nøgler: 4.3b's 10 + 4.5's 24 + 6 reserve; alle `eligible`, alle helposter uændrede |
| Omsegmenteringens virkning på udvalget | 8 poster har nyt klausulsæt; klausuler 92 → 72 |
| Kontrakt | profil `daa-2018-20-v2` 1.4.0 (klausulregler v3), prompt `d46cda80…` og model `gpt-5.6-terra` som v1; `evidence-runner-1.3`; codex-cli 0.155.1 |
| Pre-run-manifest | `72b8ac59b152c9ef3199a1777e811ec26e528dadb90258cc3f008291df7527fb` |

Sammenligneligheden med 4.3b/4.5 holder på prompt, model og helpost. Forskellen er
klausulgrænserne og runnerens værn. Alle poster sendes igen, fordi en 1.3-nøgle aldrig rammer
et 1.0-svar.

## Global Constraints

- **Ingen prod.** Alt sker i `daa44g_20260928170311` eller i kopier af den. `db-verify.sql`
  køres kun på en engangskopi (`createdb -T`), aldrig på arbejdsbasen.
- **Kun `eligible` records**, og runneren slår op i ledgeret ved hvert kald.
- **Ingen kildetekst i repo, logs, commits eller chat.** Private artefakter er 0600 under
  `~/.private/genbind-44/`. R-eksport køres med `Rscript --vanilla` og et rent lokalt miljø.
- **Budget:** omkring 17.500 input-tokens pr. post, altså cirka 600.000 for 34 poster. 4.5
  brugte 420.495 på 24. Reserven koster cirka 105.000 mere.
- **Review-budget** (decisions 2026-09-23, kun restore): én runde på koden (P1, gennemført) og
  én runde på denne plan. Ingen gate til prod i denne plan.

## Tasks

### Task 1: GO og kørsel

- [ ] Projektejeren giver GO på manifest-hashen ovenfor (hash-bindingsreglen).
- [ ] Kør `bundt_43b` og `bundt_1`-`bundt_4` med `run_evidence_43b.py` som i 4.5-planens Task 3.
  Stier: `~/.private/genbind-44/{manifest.json,runner-input/,ledger/,cache/}`.
  - Adgangstesten kører før hvert kald.
  - `GATE_FAILED`, `BUNDLE_STOPPED`, `CODEX_VERSION_DRIFT` eller en `RUNNER_*_DRIFT` stopper
    sporet med et navngivet fund.
- [ ] **Gate V1:** mindst 30 af de 34 poster skal give mindst ét kontraktgyldigt claim.
  - Under 30: kør `reserve`.
  - Stadig under 30: STOP før ingest.
  - Én timeout må køres igen én gang, fra cachen (4.5's regel).
- [ ] Notér `tool_use` pr. record. Forventet: 0. Bare ét stopper bundtet, og det er et fund.

### Task 2: Ingest i arbejdsbasen

- [ ] Byg proposal-manifestet med `build_43b_proposal_manifest.py --cache-key current` over de
  kørte bundter. Svar fra før P1 afvises uden `--historisk-foer-p1`, og det flag bruges ikke.
- [ ] Kør 4.4's writer i to trin som i 4.5-planens Task 4: først dry-run, derefter apply.
- [ ] Mål:
  - antal `proposed`, som skal svare til antal gyldige claims minus dubletter og H1-afviste;
  - dispositioner;
  - kanonisk delta, som skal være 0;
  - `db-verify.sql` på en engangskopi.

### Task 3: Kontrolmodellen

- [ ] Klassificér, træk stikprøven og byg arket som i kontrolmodel-planens rækkefølge:
  - stikprøve på 20, seed `kontrolmodel-v1`;
  - `sample_sha256` noteres, før et menneske ser et kort.
- [ ] Arket forudfyldes med projektejerens tidligere afgørelser (4.5-arket `c92a6e80…` og
  kontrolarket `f4616fa5…`), når nøgle, prædikat og værdi er identiske.
  - Kort uden forgænger er markeret, så projektejeren kan se, hvad der er nyt.
  - Projektejeren godkender én hash.
- [ ] Gaten, skrivningen (`human-sheet-kontrol-v1` før `machine-corroboration-v1`), mængdekontrollen
  og bindingen følger kontrolmodel-planen uændret.

### Task 4: Rapport og status

- [ ] `docs/evidensbaseret-genimport/genbind-44-pilot-2018-20.md` (tal og hashes), sammenlignet
  med 4.5 og kontrolmodel-kørslen:
  - forslag;
  - præcision på kortene;
  - bindinger;
  - antal kort for mennesket;
  - `tool_use`;
  - forbrug.
- [ ] Tillæg i `status.md` og en post i changelog. Kodereview er allerede gjort (P1), så der er
  ingen ny kode i denne task.

### Task 5: 4.4's prod-GO-pakke genbindes (egen GO, ikke en del af denne plan)

Pakken fra 2026-09-23 (`docs/runbooks/interpretation-proposal-prod-apply.md`) er bundet til de
gamle klausuler. Genbindingen kræver nyt prod-dump på dagen, ny rehearsal mod det og nye
GO-hashes, der dækker Task 2's proposal-manifest. GO'et skal også udtrykkeligt lukke
omsegmenteringens fortrydelsesvindue. Grenen `docs/147-pilot-prod-vej` (45a1b36) er forældet,
fordi nøglerne er ændret, og bygges der ikke videre på.

## Ændringslog

- 2026-09-28: første udgave.
