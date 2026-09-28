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
- Én uafhængig opus-review: først NO-GO, efter rettelser GO.

**Rækkefølge:** #226 merges FØR GO, og kørslen sker fra `main`. Manifestet binder
`runner_code_sha256` (`2c411820…`, en indholdshash over runnerens filer). Driveren stopper med
`RUNNER_CODE_DRIFT`, hvis koden på `main` ikke er den samme. Et squash-merge beviser derfor ikke,
hvilken kode der kørte, men hashen gør.

## Målt udgangspunkt (2026-09-28, kun tal)

| Fakta | Tal |
| --- | --- |
| Prod-dump (læse-kun, ingen skrivepause) | `ddbe94b8…`, tilstand `591\|984\|591\|1\|0\|0\|1`, klausuler 868 i gamle sæt / 984 i alt |
| Arbejdsbase | `daa44g_20260928170311`: restore = dump på tilstand, kanonisk og portabel anon. `db-migrations.sql` og `db-rls.sql` fra `main` er lagt på med 0 WARNING, så de 8 projektionsfunktioner fra #196 findes |
| Ledger (genbygget mod arbejdsbasen) | 488 `eligible` / 103 `excluded`; 0 status- og 0 hashændringer mod 4.3b's |
| Udvalg | de samme 40 nøgler: 4.3b's 10 + 4.5's 24 + 6 reserve; alle `eligible`, alle helposter uændrede |
| Omsegmenteringens virkning på udvalget | 8 poster har nyt klausulsæt; klausuler 92 → 72 |
| Kontrakt | profil `daa-2018-20-v2` 1.4.0 (klausulregler v3), prompt `d46cda80…` og model `gpt-5.6-terra` som v1; `evidence-runner-1.3`; codex-cli 0.155.1 |
| Pre-run-manifest | `72b8ac59b152c9ef3199a1777e811ec26e528dadb90258cc3f008291df7527fb` (binder `runner_code_sha256` `2c411820…` og codex-cli) |
| Runner-input | `0b51ed9aeef8993d82a8eabef5c961a2f234201d7118216395d3ca653ccf8bab` — GO'et binder den også: ledgeret hasher kun helposten, ikke klausulsættet |

Sammenligneligheden med 4.3b/4.5 holder kun på prompt, model og helpost. Tre ting er ændret:
- klausulgrænserne (8 poster);
- runnerens regler: 4.5 kørte 1.0, og fra 1.1 skal datoer stå ordret i den citerede klausul;
- basens kanoniske fakta: prod i dag er ikke restoren fra 12/9.

Task 4 skiller de tre ad. Alle poster sendes igen, fordi en 1.3-nøgle aldrig rammer et
1.0-svar.

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

- [ ] #226 er merget. Kontrollér, at `main`'s `runner_code_sha256` er lig manifestets.
- [ ] Projektejeren giver GO på manifest-hashen og runner-inputtets hash (hash-bindingsreglen).
- [ ] Kør `bundt_43b` og `bundt_1`-`bundt_4` med `run_evidence_43b.py` som i 4.5-planens Task 3.
  Stier: `~/.private/genbind-44/{manifest.json,runner-input/,ledger/,cache/}`.
  - Adgangstesten kører før hvert kald.
  - `GATE_FAILED`, `BUNDLE_STOPPED`, `CODEX_VERSION_DRIFT` eller en `RUNNER_*_DRIFT` stopper
    sporet med et navngivet fund.
- [ ] **Gate V1:** mindst 30 af de 34 poster skal give mindst ét kontraktgyldigt claim.
  - Under 30: kør `reserve`.
  - Stadig under 30: STOP før ingest.
  - Én timeout må køres igen én gang, fra cachen (4.5's regel).
  - `BATCH_PENDING` efter det ene genforsøg er STOP. En record uden valideret post har ingen
    cachepost, og proposal-builderen stopper ved enhver `CACHE_MISS` i et medtaget bundt.
- [ ] Notér `tool_use` pr. record. Forventet: 0. Bare ét stopper bundtet, og det er et fund.

### Task 2: Ingest i arbejdsbasen

- [ ] Byg proposal-manifestet med `build_43b_proposal_manifest.py --cache-key current` over de
  kørte bundter. Svar fra før P1 afvises uden `--historisk-foer-p1`, og det flag bruges ikke.
- [ ] De private writer-scripts (`~/.private/45-pilot/45-{dryrun,apply}.R`, 24/9) er fra før #222.
  De kopieres til `~/.private/genbind-44/` og gennemgås mod klausulsættene, før de bruges.
  Writeren selv slår citater op i `clause_observation_current` og afviser forkerte hashes
  (`schema.sql` 3842-3851).
- [ ] Kør 4.4's writer i to trin som i 4.5-planens Task 4: først dry-run, derefter apply.
- [ ] Mål:
  - antal `proposed`, som skal svare til antal gyldige claims minus dubletter, H1-afviste og
    `ukendt_rolle`;
  - dispositioner;
  - kanonisk delta, som skal være 0;
  - `db-verify.sql` på en engangskopi.

### Task 3: Kontrolmodellen

- [ ] Klassificér, træk stikprøven og byg arket som i kontrolmodel-planens rækkefølge:
  - stikprøve på 20, seed `kontrolmodel-v1`;
  - `sample_sha256` noteres, før et menneske ser et kort.
- [ ] **Forudfyldningen er snævret ind.** Arkets nøgle er kun (record_key, prædikat, værdi), uden
  rolle og citater (`interpretation_decision_sheet.py`). Derfor bygges prior KUN på denne måde:
  - af `principal`-rækker;
  - fra de 32 poster, hvis klausulsæt er uændret;
  - fra 4.5-arket `c92a6e80…` og kontrolarket `f4616fa5…`;
  - nøgler med modstridende domme på tværs af de to ark udelades;
  - `U` udelades.
- [ ] Kort uden forgænger står tomme i token-filen og skal afgøres aktivt. De kan ikke godkendes
  alene via hashen. Det gælder også alle kort fra de 8 omsegmenterede poster.
- [ ] Projektejeren godkender én hash, når de tomme kort er udfyldt.
- [ ] **Arkets størrelse:** mere end cirka 30 kort (beslutningen 2026-09-27, pkt. 5) er STOP.
  Projektejeren vælger så mellem to sessioner og et snævrere ark; intet afgøres i mellemtiden.
- [ ] Gaten, skrivningen (`human-sheet-kontrol-v1` før `machine-corroboration-v1`), mængdekontrollen
  og bindingen følger kontrolmodel-planen uændret.

### Task 4: Rapport og status

- [ ] **Skil årsagerne ad, før tallene sammenlignes:**
  - Genvalidér 4.5's gemte svar offline under 1.3-reglerne med
    `build_43b_proposal_manifest.py --cache-key legacy --historisk-foer-p1`. Det er kun en
    måling, intet kalder modellen, og intet skrives i basen.
  - Mål forskellen i fakta og assertions for de 40 posters personer mellem restoren
    `daa43b_20260912192527` og `daa44g_20260928170311`, kun med antal og hash.
- [ ] `docs/evidensbaseret-genimport/genbind-44-pilot-2018-20.md` (tal og hashes), opdelt i de 8
  omsegmenterede og de 32 uændrede poster, sammenlignet med 4.5 og kontrolmodel-kørslen:
  - forslag;
  - præcision på kortene;
  - bindinger;
  - antal kort for mennesket;
  - `tool_use`;
  - forbrug.
- [ ] Tillæg i `status.md` og en post i changelog. Kodereview er allerede gjort (P1), så der er
  ingen ny kode i denne task.

### Task 5: 4.4+4.5's prod-GO-pakke genbindes (egen GO, ikke en del af denne plan)

Beslutningens skridt 5 siger »4.4+4.5 i prod«. Arkets afgørelser og stikprøven er nøglet på
`interpretation_id` (`control_model.py`), og id'et er nyt ved hver ingest. Task 3's ark kan
derfor ikke genafspilles direkte i prod. Prod-pakkens egen spec vælger mellem to veje:
- en frisk kontrolmodel-kørsel i prod-vejen;
- artefakter, der bærer `interpretation_key`, så afgørelserne kan genafspilles.

Pakken fra 2026-09-23 (`docs/runbooks/interpretation-proposal-prod-apply.md`) er bundet til de
gamle klausuler. Genbindingen kræver nyt prod-dump på dagen, ny rehearsal mod det og nye
GO-hashes, der dækker Task 2's proposal-manifest. GO'et skal også udtrykkeligt lukke
omsegmenteringens fortrydelsesvindue. Grenen `docs/147-pilot-prod-vej` (45a1b36) er forældet,
fordi nøglerne er ændret, og bygges der ikke videre på.

## Ændringslog

- 2026-09-28: første udgave.
- 2026-09-28: opus-planreview (GO med rettelser), og alle fund er indarbejdet:
  - snævrere prior;
  - `BATCH_PENDING` er STOP;
  - årsagerne skilles ad;
  - 4.5 med i Task 5;
  - P1-rækkefølgen;
  - runner-inputtet er bundet;
  - loft over arkets størrelse;
  - `ukendt_rolle` er med i ingest-optællingen.
