# Runbook — første `interpretation_proposal`-kørsel i prod (4.4, issue #147)

Manuel procedure for den første forslags-kørsel mod DAA's produktionsdatabase via
Supabase Session pooler: 4.3b's **84 fortolkningsforslag** (8 elementer, 88 klausul-links)
skrives som `proposed`, bundet til klausulerne fra 4.1c, og bevises med #196's projektion
og komparator. Det kanoniske og det anon-synlige lag ændres ikke. Plan:
`docs/superpowers/plans/2026-09-23-4-4-prod-wrapper.md`.

**Forudsætning — #196's DDL skal være deployet først.** Prod fik 4.4-writeren ved deployet
2026-09-17, men #196 har siden omdefineret 4.4-afsnittet i `db-migrations.sql`
(receipt-/nøglefunktionerne `private.interpretation_proposal_*` og writer-rettelsen af
værdiformen). Projektionen og komparatoren kan ikke køre uden dem. Det deploy er en
**selvstændig, gated DDL-ændring** med egen backup, rehearsal og GO (procedure som
`docs/database-current-state.md` §8) og hører ikke til denne runbook. `01-preflight.sh`
stopper med `DDL_196_MISSING`, hvis funktionerne mangler; rehearsalen af dagens dump
afslører en gammel writer, fordi den kører den kode, prod faktisk har.

Manifestet genbruges uændret: `~/.private/43b-kørsel/proposal-manifest.json`, fil-SHA-256
`c310ca6325b5a3a10c895a0f80161a51a0c24b61c902b807d34c7f8433c65aad`, indholdshash
`a328ede946140a1223be3077d18579d94f763812875a55d67abed00645313cf8`. Det blev genbygget
2026-09-23 med `main`'s builder og var byte-identisk. Det må ikke genbygges i kørslen.

Fortrydelse er **restore af dagens backup**. Der findes ingen forslags-reversal.
Projektejeren har kvitteret for netop dette (`docs/decisions.md`, »4.4's forslags-kørsel i
prod fortrydes kun ved restore«, 2026-09-23). Kvitteringen gentages i GO-pakken. Ved GO
lukkes samtidig 4.1c's fortrydelsesvindue: en restore til et dump fra før 4.1c ville også
fjerne klausulerne.

**Arbejdsdeling.** AI-sessionen rører aldrig prod. **Projektejeren** kører alt, der
forbinder til prod (trin 1 og 3), i egen shell. Trin 2 er rent lokalt og kan køres af
begge. AI'en læser kun rensede rapporter med tal, koder og hashes — aldrig DSN,
credentials, kildetekst, record-nøgler eller manifestets payload.

---

## 1. Adgangskrav og stopport

- **Eksakt 24 filer er bundet** (`verify_go_hashes` kontrollerer dem som *mængde*):
  16 private i `~/.private/147-44-prod/` (`00-freeze.sh`, `01-preflight.sh`, `02-dump.sh`,
  `03-restore-rehearsal.sh`, `04-apply.sh`, `05-verify.sh`, `06-recover.sh`, `lib.zsh`,
  `01-role-probe-prod.R`, `03-proposal-dryrun-prod.R`, `04-proposal-apply-prod.R`,
  `verify.sql`, `restore-hash.sql`, `untouched-hash.sql`, `writer-profiles.sql`,
  `rollback-preflight.sql`), 7 i repoet (`apply_reimport_helpers.R`,
  `interpretation_proposal_projection.{psql,sql}`,
  `interpretation_proposal_anon_projection.sql`,
  `interpretation_proposal_target_identity.sql`,
  `compare_interpretation_proposal_projection.py`, profil-JSON'en) og manifestfilen. En
  manglende eller ekstra linje er STOP. Commit-SHA alene er ikke nok: de 7 repo-stier skal
  også være rene i `git diff`, `git diff --cached` og `git status --porcelain`.
- **Samme bytes i rehearsal og prod.** Rehearsal-rapporten bærer SHA-256 af GO-hashfilen,
  commit og R-bindingerne; `04` og `06` kræver dem identiske med dagens. 03, 04 og 06 kører
  alle trin gennem én funktion (`run_from` i `lib.zsh`); intet script har sin egen kopi af
  et trin.
- **Én prod-login, to roller.** `red_authorize_reimport` må kun kaldes af `service_role`,
  forslags-RPC'en kun af `authenticated`. Rollerne skiftes med `SET LOCAL ROLE` i hver
  sin transaktion; operationens claim sættes lokalt. `01-role-probe-prod.R` beviser i
  rollback-transaktioner, at begge roller virker, at hver af dem nægtes den andens RPC
  (`permission denied`), og at rolle og claim er væk efter COMMIT/ROLLBACK. Proben køres
  i `01`, igen i `04` før første skrivning og i hver `06`.
- **Lukket miljø for R.** R-scriptene startes kun som
  `/usr/bin/env -i <allowlist> /usr/local/bin/Rscript --vanilla`: `--vanilla` forhindrer,
  at `~/.Renviron` overskriver miljøet; prod-oplysningerne læses manuelt af scriptet.
  R-binærens realpath og SHA-256, `R --version` og versionerne af DBI, RPostgres, jsonlite
  og digest bindes — inklusive en indholdshash af hver pakkes installerede filer (R-kode-
  databaser og delte biblioteker), så en geninstallation med samme versionsnummer også er
  STOP — i rehearsal og efterprøves i `04`/`06`.
- **Arvet miljø er STOP før enhver forbindelse:** en ikke-tom `DAA_REIMPORT_ACTOR_ID`
  (`ACTOR_ENV_INHERITED`), `DAA_FAULT` (`FAULT_IN_PROD`) eller en hvilken som helst
  `DAA_LOCAL_*` (`LOCAL_ENV_IN_PROD`). Alle nedarvede `PG*` ryddes, inkl. `PGHOSTADDR`.
  Indlejret Python kører kun som `python3 -I` med eksplicitte fejl (aldrig `assert`).
- **Prod er kun Session pooleren** (`*.pooler.supabase.com:5432`); scripts og R afviser
  andre værter.
- **Nonce-bundne autorisationer.** R vælger en nonce og skriver `<fase>-intent.json`
  (O_EXCL, 0600) FØR `red_authorize_reimport` får netop den nonce (kolonnen er `UNIQUE`).
  Der kan derfor aldrig findes en autorisation for manifestet uden en intent-fil; en
  manifest-bundet autorisation uden intent er NO-GO. Hver autorisation valideres på alle
  bindinger: operation, kilde, manifest, preview, profil, principal, nonce,
  `expected_counts`, element-id'er, databaseidentitet, TTL (30 min ± de millisekunder,
  der går mellem klientens `clock_timestamp()` og rækkens `created_at`) og livscyklus
  (`issued` ⇔ uforbrugt). `authorized_elements_sha256` genberegnes bevidst ikke fra
  manifestet (R-serialisering med brudte tal, samme valg som komparatoren); den skal i
  stedet være identisk på tværs af kørslens autorisationer.
- `preview_sha256` er manifestfilens **byte**-hash (`c310ca63…`), ikke 4.1c's hash af
  stiens tekst.
- Profilen `daa-2018-20-interpretation-proposal-v1` har filversion **`1.0.0`**; det er den
  eneste version, der indsættes og readback-valideres. `interpretation-proposal-v1` er
  writerens `schema_version` og ingen profilversion.
- Aktøren er den ene `redaktion`-profil; R-scriptene finder og sætter den selv. Aktør-ID
  skrives kun til 0600-filer, aldrig til stdout.
- Alle scripts: `set -euo pipefail`, `umask 077`, `PGTZ=UTC`, `noclobber`. Private filer
  0600, mapper 0700. Læse-kun kald får `default_transaction_read_only=on` pr. kommando.
  Ordnet hashning bruger `COLLATE "C"`.
- Hver afvigelse fra forventede hashes eller tal er STOP, ikke et justeringsrum.

De private scripts ligger i `~/.private/147-44-prod/`, committes ikke og tager ingen
hemmeligheder som argumenter:

```bash
/bin/zsh -f ~/.private/147-44-prod/00-freeze.sh begin            # projektejer, FØR dumpet
/bin/zsh -f ~/.private/147-44-prod/01-preflight.sh               # projektejer, læser prod
/bin/zsh -f ~/.private/147-44-prod/02-dump.sh                    # projektejer, læser prod
/bin/zsh -f ~/.private/147-44-prod/03-restore-rehearsal.sh ~/.private/<dagens-dump>.dump   # lokalt
# først efter menneskeligt GO mod §4:
/bin/zsh -f ~/.private/147-44-prod/04-apply.sh --jeg-mener-det   # projektejer, SKRIVER i prod
# kun hvis 04 blev afbrudt (se §5.2) — ALDRIG 04 igen:
/bin/zsh -f ~/.private/147-44-prod/06-recover.sh --jeg-mener-det --mode prod <runmappe>
/bin/zsh -f ~/.private/147-44-prod/05-verify.sh                  # projektejer, læser prod
/bin/zsh -f ~/.private/147-44-prod/00-freeze.sh end              # projektejer, EFTER VERIFY_OK
```

**Kør altid med `/bin/zsh -f`.** Uden `-f` læser zsh `~/.zshenv`, som ville køre før
scriptets første stopport og kunne sætte zsh-optioner, der ændrer scriptets semantik.
Scriptene kontrollerer det selv (exit 2 uden `-f`) og nulstiller derefter optionerne med
`emulate -R zsh`.

**Skriv ikke `!` foran kommandoerne i en shell.** I zsh er `! kommando` negation, så en
fejlet stopport ville give status 0. (I AI-sessionens grænseflade er `! ` præfikset, der
sender en kommando til projektejerens shell — notation i chatten, ikke en del af
kommandoen.)

**Miljøkontrakt.** Stier, binærer og hashes er faste konstanter i `lib.zsh` og kan ikke
styres fra miljøet. Operatøren sætter kun dette:

| Variabel | Sættes til | Bruges af |
|---|---|---|
| `DAA_FREEZE_RESPONSIBLE` | kort ansvarskode uden personoplysninger | `00 begin` |
| `DAA_EXPECTED_TARGET` | målidentiteten fra `01-preflight.sh` | `00`, `01`, `02`, `04`, `05`, `06` |
| `DAA_EXPECTED_COMMIT` | repoets commit-SHA fra GO-pakken | `03`, `04`, `05`, `06` |
| `DAA_GO_HASHES_FILE` | GO-pakkens fil med **24** `sha256  sti`-linjer | `03`, `04`, `05`, `06` |
| `DAA_DUMP_RECEIPT` | `<dump>.receipt.json` fra `02-dump.sh` | `04`, `06` |
| `DAA_REHEARSAL_REPORT` + `_SHA256` | rehearsal-rapporten og dens hash | `04`, `05`, `06` |
| `DAA_FREEZE_REPORT` + `_SHA256` | `00-freeze.sh begin`-rapporten og dens hash | `04`, `05`, `06` |
| `DAA_APPLY_RECEIPT` + `_SHA256` | `apply-receipt.json` fra `04`/`06` og dens hash | `05` |
| `DAA_LOCAL_PGHOST/PORT/USER` | kun hvis den lokale base ikke er `localhost:5432` med din bruger | `03` |

GO-hashfilen skrives med `write_go_hashes <fil>` fra `lib.zsh`, når scripts og repo er
låst; den samme fil bruges i rehearsal og prod.

---

## 2. Trin 1 — skrivepause, læse-kun preflight og ny backup

### 2.1 Skrivekanaler, der skal stå stille fra `00-freeze begin` til `00-freeze end`

- web-redaktørfladen (`redaktion` = 1 = projektejeren; `01` stopper, hvis tallet ændres);
- mobil-dev mod prod;
- andre Claude-/Codex-sessioner og R-/Python-scripts med `~/.Renviron`;
- Supabase-dashboardets SQL-editor;
- andre reimports og prod-scripts.

Almindelige indloggede brugere kan under RLS skrive i `public`-tabeller (fx bogmærker).
Deres skrivninger **går tabt ved en fortrydelse** og vælter gaten (`GATE_DATA`), hvis de
sker mellem dump og kørsel — det siges højt, når pausen annonceres.

**Hvad der beviser pausen** (Supabase free-tier har ingen vedligeholdelsesport, så pausen
*detekteres*, den forhindres ikke):

- `restore-hash.sql` (alle tabeller og sekvenser i `private`+`public`, **ingen**
  eksklusioner) i dumpkvitteringen, genberegnet i trin 0 `gate` før første skrivning:
  ens = ingen skrivning siden dumpet;
- `untouched-hash.sql` (samme minus de otte 4.4-tabeller og deres ene sekvens) fra dumpet
  til `end` og igen i `05`: ens = kørslen og ingen andre har rørt noget uden for 4.4;
- `schema_sha256` (`pg_dump --schema-only --restrict-key=daa44schema`) dump → `gate` →
  `end` → `05`;
- skrivninger i 4.4's egne tabeller for kilde 1 fanges af delta-beviserne og
  komparatorerne.

**Restrisiko:** mellem `gate` og første skrivning går sekunder. En skrivning i det vindue i
en ikke-4.4-tabel fanges af `end`. Tilbage står skrivninger i 4.4's tabeller for *andre*
kilder, som projektionen kun dækker gennem sine hashes af andre kilders rækker.

### 2.2 `00-freeze.sh begin`

Skriver starttid, ansvarskode, målidentitet og antal aktive ikke-egne forbindelser
(`pg_stat_activity`) til en 0600-rapport og `freeze-active.json`. Aktive forbindelser
kræver `--accepter-forbindelser <eksakt antal>`. Udskriver `DAA_FREEZE_REPORT(_SHA256)`.

### 2.3 `01-preflight.sh` (læse-kun)

Samme `preflight_checks` som i `03` og `04`. Alle forventninger er kode; rapporten har kun
tal og koder. Succesmarkør `PREFLIGHT_OK`.

| Kontrol | Forventning |
|---|---|
| manifest (fil-hash, lukkede metadata, komparatorens hash og fulde validering) + profil | 8 / 84 / 88 / 68+16, `c310ca63…`, `a328ede9…`, filversion `1.0.0` |
| målidentitet, `anon`-rolletest, `01-role-probe-prod.R` | `ROLE_PROBE_OK` |
| #196's DDL | 11 funktioner (`DDL_196_MISSING` ellers) |
| 4.1c-grundlag, tomhed, redaktion | `1\|591\|868\|0\|0\|0\|0\|0\|0\|0\|1`: én `finalized` klausul-batch med 591 events, 868 klausuler; 0 forslags-events, 0 `method='model'`, ingen profilrække, 0 aktive autorisationer, **0 autorisationer i alle statusser bundet til manifestet**, 0 `extraction_run` med manifestets run-keys, 0 forældreløse links, 1 redaktion |
| citater (hash pr. citeret klausul) | `88\|88` |
| writerens øvrige krav pr. claim/klausul | `8\|8\|84\|84\|84\|84\|19\|19` (1 anker, 1 parent, aktivt prædikat og kind, værdiform, ny nøgle, distinkte nøgler, `machine`-disposition med provenance, citerede klausuler) |
| persona, identitet, levende (spec §9.2) | `8\|8\|8\|8\|8`: én primær persona, accepteret identitet, eksisterende person, `levende IS FALSE` (NULL tæller ikke) |
| fortrydelsesprivilegier (vej A) | `0\|0\|1\|1\|1\|1` |

Manifestets værdier piber direkte fra Python til psql og skrives aldrig til en fil.

### 2.4 `02-dump.sh` (læse-kun)

`pg_dump -Fc --no-owner` (ikke `--no-privileges`) plus kvittering med de **fem
dump-bundne baselines**, målt umiddelbart før og efter dumpet — de skal være ens, ellers
`DUMP_STATE_UNSTABLE`: `data_sha256`, `schema_sha256`, `untouched_sha256`,
`projection_sans_target_sha256` og `profiles_sha256` (projektionen har ingen
profilrækker). pg_dump-versionen bindes. Alle senere porte sammenligner med disse værdier,
ikke med live-værdier taget senere.

---

## 3. Trin 2 — restore af netop dagens dump og fuld rehearsal

`03-restore-rehearsal.sh <dump>` (kun lokal database; skriver intet i prod):

1. binder dump og kvittering, GO-hashfilen, commit, manifest og profil; opretter de otte
   tomme platformroller og restorer med `--clean --if-exists --no-owner` (kun vault-klassen
   er en tilladt fejl);
2. **restore-troskab:** restorens `data`, `untouched`, projektion og profiler skal være lig
   kvitteringens; schemaet sammenlignes på **objektniveau** (`pg_restore -l -n private -n
   public` af dumpet mod restorens schema-dump) med 148c's tre RLS-afhængige funktioner som
   eneste tilladte afvigelse. Schema-baselinen i rehearsal er restorens egen (vault findes
   ikke lokalt); alle andre baselines er dumpets;
3. en urørt skabelonbase tages til fejlmatricen; rolleprobe og preflight;
4. **hovedkørslen** gennem trinmotoren (§5.1) og `verify.sql`;
5. **fejlmatrix** på kopier af skabelonen: fejl injiceret efter hvert af de 18 trin og i
   hvert R-punkt (`<fase>:after_intent|after_authorize|after_execute` for dry-run, apply,
   replay), hver efterfulgt af `06-recover.sh --mode local-rehearsal`, som skal give det
   forventede udfald og identiske sluttal; plus Autorisationstabellens to
   dobbeltafbrydelser og en tredje genoptagelse, der skal give NO-GO;
6. `db-rls.sql` → `db-verify` på en **kopi** (db-verify efterlader residu og må ikke
   forurene fortrydelsen; hukommelse `fortrydelse-ved-restore-er-ikke-trofast`);
7. **fortrydelsesøvelse** oven på den befolkede hovedbase: `pg_restore --clean --if-exists
   --no-owner --schema=private --schema=public` → `data_sha256` = dumpets og 0 4.4-rækker.

Rapporten (`REHEARSAL_OK`) bærer dump- og kvitteringshash, `dump_kind`, GO-hashfilens hash,
commit, R-bindinger, restore-troskab, hovedkørslens tal og kvittering, én linje pr.
injiceret fejl med faktisk udfald og fortrydelsens resultat. Rehearsal-basen bevares som
bevis. En rehearsal af et stand-in-dump (`dump_kind=standin`) kan aldrig bære et prod-GO.

**Målt mod stand-in 2026-09-23** (prod-dump 18/9 + 4.1c lokalt + hele `db-migrations.sql`
+ `db-rls.sql`, dvs. prod *efter* et #196-deploy; plan D9): `REHEARSAL_OK` med 30/30
fejlinjektioner med forventet udfald og identiske sluttal — begge dobbeltafbrydelser og
NO-GO ved tredje genoptagelse — 8/84/88, 13/6, `verify.sql` =
`8|1|1|84|68|16|0|13|6|0|2|1|0|1|1`, restore-troskab på data, untouched, projektion og
profiler, schema-objektdiff 0, `db-verify` #147 ×2 og #148 ×2, fortrydelse med data-hash
gendannet og `0|0|0|0|0`. Preflight på stand-in'en: `88|88`, `8|8|84|84|84|84|19|19`,
`8|8|8|8|8` på 3 s; baselinerne måles på 12 s (før og efter dumpet), og hele kæden tager
ca. 22 s.

Fire fejl blev fundet og rettet undervejs, og de er værd at kende:

- **Genvalidering må kun bruge varige fakta.** Dry-run-trinets port kræver »0 batches«
  globalt; ved genvalidering efter apply er det naturligvis falsk. Fejlmatricen fangede det
  (`after_step:apply` gav NO-GO). Nu genvaliderer `06` kun autorisationens egne tal.
- **zsh-modifikatorer:** `"$phase:after_intent"` blev til en absolut sti (`:a`). Skriv
  `${phase}:…`.
- **Objektsammenligning af schema** skal filtrere med `pg_restore -l -n`, ikke gætte skemaet
  ud fra tokens (argumentnavnet `private` i `realtime.send` narrede den første parser), og
  `SCHEMA public` dumpes kun ved eksplicit `--schema=public`.
- **RLS-afhængige funktioner efter 20/9:** fortrydelsen kan ikke droppe `current_rolle()`
  og `media_object_synlig_anon(text)` (medie-indkapslingen); navnet er føjet til 148c's
  tilladelsesliste.

Angrebstests (Task 5 Step 3), alle med navngivet STOP og uden skrivning i en ikke-disponerbar
base: kommentarlinje i `verify.sql` → `fil-hashes afviger fra GO-pakken`; `04` uden argument
→ exit 2; arvet `DAA_REIMPORT_ACTOR_ID` i 03/04/06 (begge modes) → `ACTOR_ENV_INHERITED`;
`DAA_FAULT`/`DAA_LOCAL_*` før 04 og 06 prod → `FAULT_IN_PROD`/`LOCAL_ENV_IN_PROD`; 04 med
stand-in-kvittering → `dump_kind`; forkert mål → STOP med 0 autorisationer; sekvens flyttet
og `public`-række ændret efter dump → `GATE_DATA`; gammel manifest-autorisation og
`extraction_run` med run-key → `PREFLIGHT_STATE`; ekstra profilrække efter dry-run →
`PROFILES_BEFORE`; fremmed autorisation efter dry-run → `DELTA_DRYRUN`; ikke-4.4-række ændret
under kæden → `END_UNTOUCHED`; replay-komparator med dry-run-/apply-id → `REPLAY_DRIFT`;
`replayed` i stedet for `after` → ikke `match`; `06` på kvitteret runmappe → STOP.

De sidste fem angrebstests (efter Codex kode-runde 1-3), også med navngivet STOP: script
uden `/bin/zsh -f` → exit 2; levende writer-advisory-lock under `06` → `WRITER_IN_FLIGHT`
uden child-mappe og ny autorisation; `06` med en anden GO-pakke → STOP; levende lokal
writer-proces → `ORIGINAL_PROCESS_ALIVE`; `.zshenv`-sentinel (kører ikke med `-f`, afvises
med exit 2 uden); to samtidige `06` → `RUN_LOCKED` (exit 4) uden `recover-2` og uden ny
autorisation, mens den første fuldfører med `RECOVER_OK`. Suiten: 29/29.

### Målt miljø (endelige bytes, 2026-09-23)

| Kørsel | Resultat | Varighed |
|---|---|---|
| Rehearsal 9 (normalt miljø) | `REHEARSAL_OK faults=30 schema_object_diff=0` | ca. 19 min |
| Rehearsal 10 (fjendtligt miljø, bl.a. `PYTHONOPTIMIZE=1`, `PGHOSTADDR=192.0.2.1`, falsk `DAA_PREVIEW_SHA256`) | `REHEARSAL_OK faults=30 schema_object_diff=0` | ca. 18 min |
| Angrebssuite | 29/29 | — |
| Codex kode-runde 4 (smal, sidste) | GO; ét MINOR (test 20's SIGSTOP-synkronisering er tidsafhængig — kan give falsk FEJL, aldrig falsk bestået) | — |

Begge rehearsals: commit `8804e45`, stand-in-dump, pg_dump 17.10 (Homebrew), samme
GO-hashfil, identisk verify-tupel `8|1|1|84|68|16|0|13|6|0|2|1|0|1|1`, tal
84 claims / 8 elementer / 88 links / 13 `fortolkning_foreslaaet` / 6 `afventer_identitet`,
restore-trofasthed (data, profiler, projektion, uberørt) sand, fortrydelse med
`data_sha256_restored` og `post_rows 0|0|0|0|0`; fortrydelsens `restore_errors=4` er de samme
fire som i alle tidligere rehearsals (tilladelseslisten). Et prod-dump er ikke rehearset:
kørslen er parkeret (decisions 2026-09-23), og en genoptagelse kræver nyt dump, ny rehearsal og
ny GO-hashfil.

---

## 4. GO-pakke

Projektejeren giver ét eksplicit GO mod **netop** disse værdier:

- commit-SHA, bevis for rene repo-stier og GO-hashfilen med de **24** linjer (og dens
  SHA-256, som rehearsal-rapporten bærer);
- skrivepausens start (før dumpet), ansvarskode og antal aktive forbindelser;
- `database_name` og prod-`EXPECTED_TARGET` fra `01`, adskilt fra rehearsalens målidentitet;
- `PREFLIGHT_OK` med tabellens tal i §2.3, herunder `DDL_196` = 11 og privilegierne
  `0|0|1|1|1|1`;
- dagens dumpsti, starttid, størrelse, SHA-256 og kvitteringens fem baselines;
- rehearsal-rapportens SHA-256 med `dump_kind=prod`, `REHEARSAL_OK`, bestået fejlmatrix
  og fortrydelsesøvelsen;
- manifestets fil-hash `c310ca63…`, indholdshash `a328ede9…`, profil `…-v1` med
  filversion `1.0.0` og hash `4e39fff4…`;
- de faste forventninger: 8 elementer, 84 claims, 88 links, 13 `fortolkning_foreslaaet`
  + 6 `afventer_identitet`, én `finalized` batch, nul kanonisk/anon/promotion-delta;
- projektejerens kvittering: »4.4 fortrydes kun ved restore af dagens backup« (2026-09-23)
  og at 4.1c's fortrydelsesvindue dermed lukkes.

GO-kvitteringen gemmes 0600 uden DSN, credentials, kildetekst eller record-nøgler. Ændres
én bundet værdi, bortfalder GO: start igen med ny preflight, dump og rehearsal.

---

## 5. Trin 3 — kørslen i prod

### 5.1 `04-apply.sh --jeg-mener-det`

Afviser arvet miljø før alt andet; binder commit, de 24 fil-hashes, dumpkvittering
(`dump_kind=prod`), rehearsal-rapport, R-bindinger, mål og skrivepause; kører rolleprobe og
preflight læse-kun i en ny runmappe `apply-XXXXXXXX` (udskrives som `DAA_APPLY_RUN=`) og
derefter trinmotoren. Hvert trin skriver præcis én completion-artefakt med O_EXCL; ingen fil
genskrives nogensinde. Trin 3, 7 og 11 har desuden en write-ahead-intent, som aldrig betyder
»færdig«.

| # | Trin | Completion | Port |
|---|---|---|---|
| 0 | `gate` | `gate.json` | live data/schema/untouched = dumpets (første prod-skrivning er IKKE sket endnu) |
| 1 | `predry` | `pre-dry.json` | = dumpets projektion |
| 2 | `profiles_predry` | `profiles-pre-dry.json` | = dumpets profiler |
| 3 | `dryrun` | `dryrun.json` (+ intent før profil-insert) | profil-insert + readback, nonce-autorisation D, dry-run `finalized`/`committed=false` |
| 4 | `before` | `before.json` | — |
| 5 | `profiles_before` | `profiles-before.json` | præcis den ene forventede profilrække |
| 6 | `delta_dryrun` | `delta-dryrun.json` | `before` = `pre-dry` + præcis D; intet andet |
| 7 | `apply` | `apply.json` (+ intent) | nonce-autorisation A forbrugt, 1 `finalized` batch, 8 events |
| 8 | `after` | `after.json` | — |
| 9 | `profiles_after` | `profiles-after.json` | byte-lig `profiles-before` |
| 10 | `fresh` | `fresh.json` | komparator `--mode fresh` = `match`, 8/84/88/{13,6} |
| 11 | `replay` | `replay.json` (+ intent) | ny autorisation R forbrugt, `already_applied`, stadig 1 batch |
| 12 | `replayed` | `replayed.json` | — |
| 13 | `profiles_replayed` | `profiles-replayed.json` | byte-lig `profiles-after` |
| 14 | `replay_match` | `replay-match.json` | komparator `--mode replay` = `match` |
| 15 | `chain` | `chain.json` | kædevalidatoren binder alle input og alle parent→child-led |
| 16 | `end` | `end.json` | untouched/schema = dumpets; autorisationer = Autorisationstabellen |
| 17 | `sanitize` | `sanitized.json` | kun status/kode/tal |

Derefter `apply-receipt.json` (O_EXCL) med SHA-256 af hver fil i runmappekæden;
udskriver `DAA_APPLY_RECEIPT=` og `DAA_APPLY_RECEIPT_SHA256=`. Dry-run efterlader bevidst
én committed, uforbrugt `issued`-autorisation (udløber efter 30 min): gatewayens egen
`auto_dry_run` kan ikke autorisere fra operationsrollen.

**Autorisationstabel** (kun autorisationer med manifestets hash tælles):

| Tilstand | Dry-run | Apply | Replay | Batches | Events |
|---|---|---|---|---|---|
| normal slut | D (issued) | A (consumed) | R (consumed) | 1 (A) | 8 |
| apply afbrudt 1×, intet commit | D | A1 død, A2 consumed | R | 1 (A2) | 8 |
| apply afbrudt 2×: A1 intet commit, A2 commit uden kvittering | D | A1 død, A2 consumed (rekonstrueret) | R | 1 (A2) | 8 |
| apply afbrudt 2× uden commit | D | A1, A2 døde, A3 consumed | R | 1 (A3) | 8 |
| dry-run afbrudt 1× efter RPC | D1 død, D2 | A | R | 1 (A) | 8 |
| replay afbrudt 1×, intet commit | D | A | R1 død, R2 consumed | 1 (A) | 8 |

### 5.2 Afbrydelse → `06-recover.sh` (aldrig 04 igen)

`06-recover.sh --jeg-mener-det --mode prod <runmappe>` binder som `04` og kræver desuden,
at GO-hashfilen, rehearsal-rapporten og freeze-rapporten er **præcis dem, rodens
`context.json` blev skrevet med** — en genoptagelse kan ikke skifte til en anden pakke.
`04` og `06` holder en eksklusiv lås på `run.lock` i den private mappe, så længe de lever;
kører en anden `04`/`06` stadig (fx en første `06`, der ser hængt ud), stopper den nye med
`RUN_LOCKED` (exit 4), før den forbinder: vent, til den første er færdig. Før
klassifikationen prøver `06` writerens to advisory locks (`daa-reimport:1:<profil>` og
`daa-reimport-writer:1:<profil>`); holder en anden session dem, lever det oprindelige forsøg
stadig på serveren, og `06` stopper med `WRITER_IN_FLIGHT` (exit 4): vent og kør igen.
Lever en `0[34]-proposal-*-prod.R`- eller `04-apply.sh`-proces stadig på maskinen (fx
forældreløs efter `kill` af 04), stopper `06` med `ORIGINAL_PROCESS_ALIVE` (exit 4):
afslut processen først. Så
validerer
artefakterne i trinrækkefølge (første manglende/ugyldige = næste trin), slår hver intents
nonce op læse-kun og genoptager i en ny child-runmappe `<rod>/recover-<n>` med de validerede
artefakter kopieret og hash-bundet. Højst to child-niveauer; en tredje genoptagelse er NO-GO.
En autorisation udstedes kun på trin 3, 7 eller 11, og kun når nonce-opslaget har bevist, at
det forrige forsøg på samme trin ikke committede.

| Næste trin | Klassifikation | Udfald → handling |
|---|---|---|
| 0-2 | ingen intent, ingen autorisation, 0 batches | `genstart` → hele kæden fra `gate` |
| 3 | ingen intent | `dryrun-ingen-intent` → `run_from dryrun` |
| 3 | intent, nonce 0 rækker | `dryrun-ingen-autorisation` → nyt `profiles-pre-dry` (0/1 forventet række) → `dryrun` |
| 3 | intent, nonce 1 `issued` | `dryrun-doed-autorisation` → ny `pre-dry` = baseline + døde D'er, nyt `profiles-pre-dry` → `dryrun` |
| 4-6, 8-10, 12-17 | foregående gyldige | `fortsaet` → næste trin |
| 7 | ingen intent / nonce 0 rækker | `apply-ingen-intent` / `apply-ingen-autorisation` (ny `before`, kanonisk lig forælderens) → `apply` |
| 7 | nonce 1 `issued`, 0 batches | `apply-doed-autorisation` → ny `before` = forælderens + døde A'er → `apply` |
| 7 | nonce `consumed`, 1 `finalized` batch med dens id, 8 events | `apply-commit-uden-kvittering` → rekonstruér `apply.json` → `after` |
| 11 | ingen intent / nonce 0 rækker | `replay-ingen-intent` / `replay-ingen-autorisation` → `replay` |
| 11 | nonce 1 `issued` | `replay-doed-autorisation` → `replay-base` = `after` + døde R'er → `replay` |
| 11 | nonce `consumed`, stadig 1 batch | `replay-commit-uden-kvittering` → rekonstruér `replay.json` → `replayed` |
| alle gyldige | ingen kvittering | `kun-kvittering` |
| alt andet | fx 2+ batches, events ∉ {0, 8}, autorisation uden intent, tredje niveau | **NO-GO** (`RECOVER_NOGO`, exit 3) → bevar alt, restore efter §6 |

`06` skriver sin egen `apply-receipt.json` (`recovered: true`) og slutter med
`RECOVER_OK udfald=<navn>`. `05` bruger den kvittering.

### 5.3 `05-verify.sh` (læse-kun)

Kræver apply-kvittering + hash og rehearsal-rapport + hash; genberegner SHA-256 af hver fil i
kvitteringen; tager en ny slutprojektion, der skal være lig kædens `replayed.json`; måler
untouched og schema mod dumpet; genkører **begge** komparatorer og kædevalidatoren med nye
rapportstier; slutkontrol af autorisationerne og `verify.sql` med
`8|1|1|84|68|16|0|13|6|0|2|<1+døde>|0|1|<run-keys>`. Skriver `verify-ok.json`, som
`00-freeze.sh end` nægter at ophæve pausen uden. Succesmarkør `VERIFY_OK`.

---

## 6. Fortrydelse — restore af dagens backup (vej A)

Samme vej som 4.1c (`docs/runbooks/clause-evidence-prod-apply.md` §6), afgrænset til vores
egne skemaer:

```bash
pg_restore --clean --if-exists --no-owner --schema=private --schema=public \
  --dbname "$PGDATABASE" ~/.private/<dagens-dump>.dump
```

Øvelsen i `03` beviser, at dumpet kan lægges tilbage oven på den befolkede base med
`data_sha256` lig dumpets og 0 4.4-rækker. Den beviser ikke prods rettigheder; det gør
privilegie-preflighten (`0|0|1|1|1|1`). De tre RLS-afhængige funktioner droppes ikke og
genskabes ikke — en ændring af dem efter dumpet overlever en fortrydelse. **Prisen:** alt
skrevet i `private`/`public` efter dumpets start går tabt, også brugeres skrivninger under
RLS. En fortrydelse til et dump fra før 4.1c ville også fjerne klausulerne.

---

## 7. Stopregler

- Intet GO uden #196's DDL i prod (`DDL_196` = 11), ny backup, restore af netop dens SHA og
  en fuld bestået rehearsal (`dump_kind=prod`, fejlmatrix bestået) af samme bytes.
- Intet GO, hvis skrivepausen ikke var aktiv før dumpet, eller aktive forbindelser ikke kan
  gøres rede for.
- Enhver lokal ændring i en af de 24 filer efter GO er STOP, også ved uændret commit.
- `GATE_DATA`, `GATE_SCHEMA`, `GATE_UNTOUCHED` eller `DUMP_STATE_UNSTABLE` er STOP før
  første skrivning: nyt dump og ny rehearsal.
- Alt andet end 8 elementer, 84 claims, 88 links, 13/6, én `finalized` batch og replay
  `already_applied` er STOP. Reparér aldrig prod for at få `match`.
- Efter første prod-skrivning (trin 3) betyder enhver afbrydelse **06, aldrig 04**. Et
  `RECOVER_NOGO` eller en komparator-NO-GO betyder: bevar dump, runmapper og rapporter, hold
  pausen og restore efter §6.
- `already_applied` i apply-fasen er STOP (en genkørsel må ikke tavst »lykkes«).

---

## 8. Fælder

1. Dry-run indsætter profilrækken **varigt** og efterlader én `issued`-autorisation; begge
   er forventede og indgår i delta-beviset (trin 5-6).
2. En afbrudt autorisation vælter enhver senere `match`, fordi komparatoren kræver præcis
   én ny autorisation. Derfor tager `06` en ny baseline med de døde autorisationer, før den
   fortsætter — kør aldrig komparatoren i hånden på en genoptaget kæde.
3. `DAA_FAULT` og `DAA_REIMPORT_ACTOR_ID` i miljøet er STOP i prod; `03` kræver `DAA_FAULT`
   tom, fordi den selv styrer fejlinjektionen.
4. R læser `~/.Renviron` ved opstart og overskriver arvede variabler; kun `--vanilla` via
   `run_r` er tilladt.
5. `pg_dump` 17.10 lægger en tilfældig `\restrict`-nøgle i plain-output; schema-hashen kræver
   `--restrict-key=daa44schema`.
6. `db-verify` kører kun mod en disponerbar kopi (residu gør en fortrydelse utrofast).
7. Brug aldrig `zsh -x` til fejlsøgning her: `~/.zshenv` eksporterer et GitHub-token, og
   tracen skriver det i loggen.
8. Ingen hemmeligheder, hostnavne, kildetekst eller record-nøgler i rapporter eller
   AI-output.

---

## 9. Efter kørslen

Når `VERIFY_OK` er dokumenteret: opdatér `docs/evidensbaseret-genimport/status.md`,
changelog, `docs/database-current-state.md` og 4.4-rapporten med dato, commit,
rapport-hashes og restore som rollbackform. Rækken »Proposed-ingest og promotion« løftes
kun for ingest-halvdelen; promotion forbliver dry-run. Projektejeren kører Supabase
Advisors (Security og Performance) og dokumenterer fund. Indekset på
`interpretation_predicate_fk` hører ikke til denne kørsel (84 rækker er ikke skala), men
skal etableres før forslags-writeren kører på skala. Bevar dump, GO-kvittering, scripts,
runmapper og rensede rapporter, indtil projektejeren særskilt lukker rollbackvinduet.
