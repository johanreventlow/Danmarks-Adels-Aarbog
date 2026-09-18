# Runbook — første `clause_evidence`-kørsel i prod (4.1c, issue #148)

Manuel procedure for den første datakørsel af `clause_evidence` mod DAA's
produktionsdatabase via Supabase Session pooler. Der deployes ingen DDL: skema,
RLS og writere har været live siden 2026-09-17. Leverancen er 591 records og 868
klausuler i én `finalized` batch, uden ændring af det kanoniske eller anon-synlige
lag.

Manifestet genbruges uændret:
`~/.private/148c-manifest-20260910190838.json`. Der eksporteres eller segmenteres
ikke igen. Manifestets 591 helpost-hashes og rendition-hash er målt identiske med
prod 2026-09-17; writeren stopper desuden ved
`REIMPORT_WRITER_RENDITION_DRIFT` eller `CLAUSE_EVIDENCE_PARENT_TEXT_DRIFT`.

Fortrydelse er **restore af dagens backup**. Der findes ingen klausul-reversal, og
Supabase free-tier har ingen anden backup. Projektejeren har kvitteret særskilt for
netop dette (`docs/decisions.md`, posten »4.1c's klausulkørsel i prod fortrydes kun
ved restore«, 2026-09-17); kvitteringen skal gentages i GO-pakken, men er ikke et
udestående.

Værktøjet, runbooken bygger på, er i `main` siden #197: `clause_evidence_projection.psql`
med sine tre SQL-filer og `compare_clause_evidence_projection.py` (issue #195).

**Arbejdsdeling.** AI-sessionens prod-adgang er blokeret af harnessets klassifikator,
også læse-kun. Derfor kører **projektejeren** alt, der rører prod (trin 1 og 3), i egen
shell. Trin 2 er rent lokalt og kan køres af begge. AI'en må kun læse rensede rapporter
med tal, koder og hashes — aldrig DSN, credentials, kildetekst eller record-nøgler.

---

## 1. Adgangskrav og stopport

- Kør fra en ren, fastlåst `main`, der indeholder #148/#195-værktøjerne. Notér
  commit-SHA i GO-pakken. Ingen kode må ændres mellem rehearsal og prod-apply.
  **Commit-SHA er ikke nok som binding:** en lokal ændring i en sourcet hjælpefil
  (`apply_reimport_helpers.R`), i projektionens SQL eller i komparatoren flytter ikke
  SHA'en. Derfor er det kodede stopporte — både i rehearsal og umiddelbart før
  prod-apply — at `git diff --quiet`, `git diff --cached --quiet` og
  `git status --porcelain` for de eksekverede stier er tomme, og at SHA-256 af HVER fil,
  der køres eller sources, matcher GO-pakken: de fem prod-scripts, de to hærdede
  R-kopier, `apply_reimport_helpers.R`, de fire projektionsfiler og komparatoren.
- Alle private filer og mapper er mode `0600`/`0700`; hvert script starter med
  `set -euo pipefail`, `umask 077` og `PGTZ=UTC`.
- **Forbindelsen sættes eksplicit i hvert script, aldrig arvet.** Projektet har ingen
  DSN-variabel; mønstret er det samme som trin 4's skema-deploy: scriptet rydder først
  alle nedarvede `PG*` (`PGHOST PGPORT PGDATABASE PGUSER PGPASSWORD PGSSLMODE PGOPTIONS
  PGSERVICE PGCONNECT_TIMEOUT`) og sætter dem derefter fra `~/.Renviron`
  (`SUPABASE_HOST/PORT/DB/USER/PASSWORD`, `PGSSLMODE=require`, Session pooler).
  `PGPASSWORD` udskrives aldrig. Projektejeren sammenholder host-værdien med Supabase-
  dashboardet, første gang GO-pakken skrives.
- **Målbindingen er det, der beviser databasen** — ikke variablernes navne. Hvert script
  beregner `EXPECTED_TARGET` med `clause_evidence_target_identity.sql` på sin EGEN
  forbindelse og sammenligner med GO-pakkens værdi (`DAA_EXPECTED_TARGET`). Afvigelse er
  exit ≠ 0 før enhver skrivning.
- Læse-kun kald sætter `PGOPTIONS='-c default_transaction_read_only=on'` **pr. kommando**,
  ikke som eksport — en eksport ville også ramme skrivekaldene og få apply til at fejle
  midt i kørslen.
- **R-writerne skal bindes til samme mål.** `03-clause-dryrun.R` og `04-clause-apply.R`
  læser `PGHOST`/`PGDATABASE`/`PGPORT`/`PGUSER`/`PGPASSWORD` fra miljøet, som de finder
  det; psql kan derfor verificere prod, mens R skriver i en anden base.
  Derfor bruges **hærdede kopier** i `~/.private/148c-prod/` (`03-clause-dryrun-prod.R`,
  `04-clause-apply-prod.R`), som: (a) rydder alle nedarvede `PG*`, (b) forbinder med
  præcis den DSN, GO-pakken binder, (c) beregner målidentitetens hash med formlen fra
  `clause_evidence_target_identity.sql` på **sin egen** forbindelse og afbryder, hvis
  den afviger fra GO-pakkens `EXPECTED_TARGET` — før profilindsættelse, før autorisation
  og før apply. De originale scripts bruges kun lokalt i trin 2.
- Fasepakkens afsnit **»Klausul-projektion (udgaveneutral
  delta-afstemning, spec §11.1)«** er autoritativt for målidentitet,
  før-/efter-projektion og komparator. Kommandoerne gentages ikke her.
- `SET TRANSACTION READ ONLY` alene beskytter ikke psql-autocommit. Alle øvrige
  læse-kun psql-kald skal køre med
  `PGOPTIONS='-c default_transaction_read_only=on'`. Projektionen bruger sin egen
  transaktion. Fasepakkens målidentitets-preflight består kun af `SELECT` og skal
  køres ordret som dokumenteret dér.
- Prod skal ved preflight have 591 helposter, 0 klausuler for den aktuelle
  kørsel, 0 `clause_evidence`-hændelser for profilen, ingen aktiv autorisation og
  **ingen** writer-profilrække for `(1,
  daa-2018-20-clause-evidence-v1)`. En allerede eksisterende profilrække er
  STOP og skal undersøges; den må ikke slettes eller overskrives.
- **Skrivepausen begynder FØR dumpet og holdes til efter `VERIFY_OK`.** Den dækker alle
  skrivestier: redaktørfladen (web/mobil), R-loadere, manuelle psql-sessioner og enhver
  automatik. `change_set.created_at >= dump_start` er kun en SUPPLERENDE kontrol — den
  fanger ikke loadere eller direkte SQL, der skriver uden `change_set` (samme forbehold
  står i trin 4's eget apply-script). Uden en håndhævet pause fra før dumpet kan en
  skrivning mangle i backuppen, og en senere restore ville slette den.
- Pausen erklæres og ophæves eksplicit med `00-freeze.sh begin|end`, som skriver
  starttidspunkt, ansvarlig og en optælling af aktive ikke-egne forbindelser
  (`pg_stat_activity`) til en 0600-rapport. Optællingen og pausens tidsrum skal begge
  fremvises i GO-pakken.
- **Hvad håndhæver pausen på hver skrivesti** (målt 2026-09-17 mod prod-restoren):
  - *Redaktørfladen (web/mobil):* redaktionelle skrivninger kræver rollen `redaktion`,
    og der findes **præcis én** profil med den rolle — projektejeren selv. Pausen
    håndhæves derfor ved, at projektejeren ikke redigerer i vinduet og lukker åbne
    redaktør-faner. `01-preflight.sh` verificerer læse-kun, at antallet af
    `redaktion`-profiler stadig er 1; et højere tal er STOP, fordi pausen så afhænger
    af en anden person.
  - *R-loadere og manuelle psql-sessioner:* kører kun manuelt fra projektejerens
    maskine. Der er ingen automatik: `.github/workflows/` har ingen prod-hemmeligheder
    (målt), så CI kan ikke skrive mod prod.
  - *Almindelige indloggede brugere:* kan under RLS skrive i ~30 `public`-tabeller
    (fx bogmærker). De indgår ikke i projektionens hash-sæt, så de kan ikke forurene
    beviset — men de **går tabt ved en fortrydelse**, se §6. Det er en del af prisen
    for restore og skal siges højt, når pausen annonceres.
- Hver afvigelse fra forventede hashes eller tal er STOP, ikke et
  justeringsrum. `--allow-empty` må aldrig bruges mod prod.

De seks private scripts (`00-freeze.sh` … `05-verify.sh`) ligger i
`~/.private/148c-prod/`, committes ikke og tager ingen hemmeligheder som argumenter. Projektejeren kører dem således:

```bash
zsh ~/.private/148c-prod/00-freeze.sh begin           # projektejer, FØR dumpet
zsh ~/.private/148c-prod/01-preflight.sh              # projektejer, læser prod
zsh ~/.private/148c-prod/02-dump.sh                   # projektejer, læser prod
zsh ~/.private/148c-prod/03-restore-rehearsal.sh ~/.private/<dagens-dump>.dump   # lokalt
# først efter menneskeligt GO mod §4:
zsh ~/.private/148c-prod/04-apply.sh --jeg-mener-det  # projektejer, SKRIVER i prod
zsh ~/.private/148c-prod/05-verify.sh                 # projektejer, læser prod
zsh ~/.private/148c-prod/00-freeze.sh end             # projektejer, EFTER VERIFY_OK
```

**Skriv ikke `!` foran kommandoerne i en shell.** I zsh er `! kommando` negation: et
fejlet script ville give status 0 og et bestået 1, så stopporten ville vende. (I
AI-sessionens grænseflade er `! ` derimod præfikset, der sender en kommando til
projektejerens egen shell — det er notation i chatten, ikke en del af kommandoen.)

Trin 1 og 3 kører kun projektejeren. Trin 2 rører ingen prod-forbindelse og kan køres
af AI'en, som også kontrollerer scriptstruktur og de rensede rapporter.

---

## 2. Trin 1 — læse-kun preflight og ny backup

### 2.1 `01-preflight.sh` (læse-kun)

Scriptet følger navngivning og rapportmønster fra `trin4prod-01-preflight.sh` og
skriver en unik, mode-0600 `preflight-<tid>.txt`. Det skal:

1. afvise argumenter, og afvise at køre, hvis en af `~/.Renviron`-værdierne mangler;
2. køre målidentitets-preflighten **ordret** fra fasepakkens
   »Klausul-projektion«, notere `database_name` og `EXPECTED_TARGET`, og kræve
   at rolletesten giver `anon`;
3. med `PGOPTIONS='-c default_transaction_read_only=on'` kontrollere, at 4.1c-
   skemaet/writeren findes, at der ikke er aktive autorisationer, og at
   profilrækken, klausulerne og profilens events endnu ikke findes;
4. hash-kontrollere manifestfilen og dens lukkede metadata uden at udskrive
   payload: 591 operationer, 868 klausuler,
   `manifest_content_sha256=0b31c5a22c1045fcfb0528b8099f1e118cb235882ca92a6341808eb56c8655f6`,
   profil-hash
   `7696cb87b9d5fecb3693d201d023ec84d27d25b35dee92f09bd6b75e88ce31f5`,
   rendition-hash
   `2dd5cf8408943ccc50ac4d89dcbd08ac3b49a90fdabd1ddcbd7b22d218026563`
   og ledger-fil-hash
   `8f4a88f5803287778666c120fa36bc5e770cebe685286f0e2a4eb9bc08980210`;
5. genmåle, at alle 591 parent-hashes matcher prod. Rapporten må kun vise
   `591/591`, koder og hashes;
6. kræve **0** forældreløse rækker i `private.interpretation_observation` (se §6: en
   forældreløs række gør en fortrydelse utrofast) og at antallet af profiler med rollen
   `redaktion` fortsat er 1:

```sql
SELECT (SELECT count(*) FROM private.interpretation_observation io
          WHERE NOT EXISTS (SELECT 1 FROM private.interpretation i WHERE i.id = io.interpretation_id)
             OR NOT EXISTS (SELECT 1 FROM private.source_observation o WHERE o.id = io.observation_id)) AS foraeldreloese,
       (SELECT count(*) FROM public.profiles WHERE rolle = 'redaktion') AS redaktioner
```

Alle forventninger ovenfor skal være kode (`[[ ... ]]`, SQL-assertion eller
tilsvarende), så scriptet afslutter forskelligt fra 0 ved første afvigelse.
Succesmarkør: `PREFLIGHT_OK`.

### 2.2 `02-dump.sh` (læse-kun mod prod)

Scriptet følger `148-01-prod-dump.sh`/`trin4prod-02-dump.sh`:

- brug `pg_dump -Fc --no-owner`, men **ikke** `--no-privileges`;
- gem dumpets starttid i UTC **før** `pg_dump` starter;
- skriv dump, starttid, størrelse og SHA-256 til en unik mode-0600 rapport;
- verificér rettigheder og en ikke-tom fil i kode, og afslut med `DUMP_OK`.

Dumpets starttid er friskhedsgrænsen. Et senere antalsmatch kan ikke erstatte
kontrollen af `change_set.created_at >= dumpets starttid`.

---

## 3. Trin 2 — restore af netop dagens backup og fuld rehearsal

### 3.1 `03-restore-rehearsal.sh` (kun lokal database)

Scriptet modtager præcis én dumpsti, binder dens SHA-256 og opretter en ny,
disponerbar lokal database samt en ny 0700-runmappe. Før `pg_restore` oprettes
disse tomme `NOLOGIN`-roller, hvis de mangler:

```text
dashboard_user, supabase_auth_admin, supabase_storage_admin,
supabase_realtime_admin, pgbouncer, anon, authenticated, service_role
```

Ellers fejler 111 `GRANT`/`OWNER`-sætninger, og restoren er ikke trofast.
`pg_restore`-fejl om `supabase_vault` er de eneste tilladte restore-fejl; enhver
anden fejl er en kodet stopport.

Restoren skal svare til preflightens databaseinventar og være en restore af
**netop** SHA'en fra `02-dump.sh`. Der køres ingen migration eller anden DDL.
Derefter øves den fulde prod-rækkefølge:

1. Kør `148c-03-clause-dryrun.R` mod restoren. Scriptet indsætter
   writer-profilrækken varigt, sætter selv `request.jwt.claim.sub` for
   `red_*`-RPC'erne og ruller klausuldata tilbage. Kræv `DRY_RUN_OK`,
   `finalized`, `committed=false`, fortsat 0 klausuler og præcis én profilrække.
2. Genberegn profil-hashen fra profilfilen og læs rækken tilbage. Fil,
   manifest og database skal alle være
   `7696cb87b9d5fecb3693d201d023ec84d27d25b35dee92f09bd6b75e88ce31f5`.
3. Tag før-projektionen med fasepakkens autoritative kommando. Filen skal være
   én gyldig JSON-linje. Mål `neutral_lists` her; disse rehearsal-tal, ikke
   tallene fra 2026-09-17, låses i GO-pakken.
4. Kør `148c-04-clause-apply.R` mod restoren. Kræv `APPLY_OK`, første apply
   `finalized/committed=true` og scriptets indbyggede replay
   `already_applied`. Autorisationen skal udstedes til manifestets eksakte
   `expected_counts`/elementmængde og må ikke genbruges til andet.
5. Tag efter-projektionen og kør komparatoren ordret efter fasepakken med
   restore-databasens målidentitet. `--allow-empty` er forbudt.
6. Kør alle verifikationsforespørgsler, som `05-verify.sh` senere skal bruge
   mod prod. De skal bestå her; en uprøvet SQL-fejl efter prod-apply er ikke
   acceptabel. Tekstsortering bruger altid `COLLATE "C"`.
7. Kør `db-verify`s to #148-blokke mod restoren (`tests/sql/run-db-verify-disposable.sql`).
   De hører KUN til rehearsalen: runneren opretter disponerbare objekter og må ikke
   køres mod prod.
8. Notér, at 04-scriptets indbyggede replay udsteder en **ny autorisation** pr. kørsel.
   Det er forventet (samme mønster som 4.4's apply-script) og efterlader en forældreløs
   autorisationsrække uden batch. Antallet af autorisationer er derfor ikke en stopport;
   antallet af `finalized` batches for kørslen er (præcis 1).

Rehearsalens maskinelle bestået-kriterier er:

| Måling | Eksakt forventning |
|---|---:|
| Records / `clause_evidence`-hændelser | 591 / 591 |
| Klausuler / dispositioner | 868 / 868 |
| Dispositioner | 617 `afventer_fortolkning`; 251 `maskinelt_flagget` |
| Batches for kørslen | 1, status `finalized` |
| Klausuler uden post-relativt par / uden for parent-span | 0 / 0 |
| Kanonisk og anon-synligt lag | uændret |
| Replay | `already_applied` |
| Projektion | exit 0, `status=match`, korrekt målidentitet |

`neutral_lists` skal være målt i denne restore og kopieres eksakt til §4.
Scriptet skriver kun tal, koder og hashes til `rehearsal-<tid>.txt/json`, hasher
rapportfilerne og slutter med `REHEARSAL_OK`. En fejlet restore eller rehearsal
bevares urørt og er NO-GO.

---

## 4. GO-pakke

Projektejeren giver ét eksplicit GO mod **netop** følgende værdier; ikke mod en
beskrivelse som »samme manifest« eller »tallene ser rigtige ud«:

- repo commit-SHA **plus** bevis for ren arbejdstræ (`git diff`/`git diff --cached`/
  `git status --porcelain` tomme for de eksekverede stier) og SHA-256 af hver fil, der
  køres eller sources: de seks private scripts (`00-freeze.sh` … `05-verify.sh`), de to
  hærdede R-kopier, `apply_reimport_helpers.R`, de fire projektionsfiler og
  komparatoren;
- skrivepausens starttidspunkt (før dumpet), ansvarlig og optællingen af aktive
  ikke-egne forbindelser fra `00-freeze.sh begin`;
- fortrydelsesvejen (vej A, §6: `pg_restore --clean --if-exists --no-owner
  --schema=private --schema=public`), resultatet af privilegie-preflighten mod prod (0
  ikke-ejede relationer, 0 ikke-ejede funktioner, medlemskab og `CREATE` på begge
  skemaer), og tallene fra den lokale fortrydelsesøvelse — herunder at `neutral_sha256`
  efter restore var identisk med før-tilstanden;
- `database_name` og prod-`EXPECTED_TARGET` fra `01-preflight.sh`;
- dagens dumpsti, dump-starttid, dumpstørrelse og dump-SHA-256;
- SHA-256 af rehearsal-rapporten og bevis for, at den brugte netop dump-SHA'en;
- manifestfilens byte-SHA-256, manifestets indholdshash
  `0b31c5a2…`, 591 operationer og 868 klausuler;
- rendition-hash `2dd5cf84…`, ledger-fil-hash `8f4a88f5…` og beviset
  `591/591` matchende parent-hashes;
- profil-id/version og profil-hash `7696cb87…` med readback fra restoren;
- `EXPECTED_TARGET` for prod samt rehearsalens egen målidentitet, tydeligt
  adskilt;
- rehearsalens eksakte `neutral_lists` og de faste forventninger 591/868,
  617/251, én `finalized` batch, uændret kanonisk/anon-lag og replay
  `already_applied`;
- projektejerens kvittering: »fortrydelse af `clause_evidence` sker ved restore
  af dagens backup« (givet 2026-09-17, gentages her).

GO-kvitteringen gemmes 0600 og må ikke indeholde DSN, credentials, kildetekst
eller record-nøgler. Ændres én bundet værdi, bortfalder GO; start igen med ny
preflight, backup og restore-rehearsal.

---

## 5. Trin 3 — profilskrivning, før-projektion, apply og verifikation i prod

### 5.1 `04-apply.sh` (skriver mod prod)

Dette script må kun køre med det eksakte argument `--jeg-mener-det`. Det binder
GO-pakkens commit-, script-, manifest-, profil-, mål- og dump-hashes i kode og
skal umiddelbart før første skrivning:

1. genverificere Session pooler-målet og `EXPECTED_TARGET`;
2. genverificere dagens dump-SHA og `REHEARSAL_OK`-rapportens SHA;
3. med `PGOPTIONS='-c default_transaction_read_only=on'` kræve 0 aktive
   autorisationer og 0 profilrækker/klausuler/events for denne kørsel;
4. kræve `count(change_set where created_at >= dump_start) = 0`. Er tallet ikke
   nul, er backuppen forældet, selv hvis alle øvrige antal er uændrede: kassér
   GO og gentag trin 1-2 med nyt dump;
5. bekræfte, at redaktionspausen er aktiv.

Først derefter må scriptet køre `148c-03-clause-dryrun.R` mod prod. Det er den
første prod-mutation, fordi scriptet indsætter writer-profilrækken. Kræv samme
dry-run-resultat som i rehearsal, og lav straks readback af profil-id, version,
writer-config-hash og profil-hash. Alle skal matche profilfilen og manifestets
`7696cb87…`. Ved fejl: STOP, bevar alt, ingen manuel rettelse; restore er vejen
tilbage.

Når profil-readback består, tager `04-apply.sh` før-projektionen ved at følge
fasepakkens autoritative trin og validerer filen som én JSON-linje. Først nu må
`148c-04-clause-apply.R` køres én gang mod prod. Kræv `APPLY_OK`,
`finalized/committed=true`; scriptsættet skal også bevise replay som
`already_applied`. Scriptet skriver en unik mode-0600 apply-rapport og slutter
med `APPLY_DONE`, men erklærer ikke samlet succes før `05-verify.sh` består.

Hvis forbindelsen forsvinder omkring commit, er udfaldet ukendt. **Kør ikke apply igen,
og udsted ikke en ny autorisation.** Afgør tilstanden med denne læse-kun forespørgsel,
som kun binder manifestets hash:

```bash
PGOPTIONS='-c default_transaction_read_only=on' psql -X -At -F' | ' -v ON_ERROR_STOP=1 -c "
SELECT (SELECT encode(pg_catalog.sha256(convert_to(current_database() || E'\n' ||
          encode(pg_catalog.sha256(convert_to((pg_control_system()).system_identifier::text,'UTF8')),'hex'),
          'UTF8')),'hex')) AS maalidentitet,
       b.id::text, b.status, b.source_id, b.profile_id, b.profile_sha256,
       count(e.id) AS events,
       count(*) FILTER (WHERE e.element_id LIKE 'clause-evidence:%') AS klausul_elementer,
       count(DISTINCT e.element_id) AS distinkte_elementer
  FROM private.reimport_batch b
  LEFT JOIN private.reimport_event e ON e.batch_id = b.id AND e.operation = 'clause_evidence'
 WHERE b.manifest_sha256 = '<manifest_content_sha256 fra GO-pakken>'
 GROUP BY b.id, b.status, b.source_id, b.profile_id, b.profile_sha256
 ORDER BY b.id::text"
```

(Ingen `COLLATE` her: forespørgslen giver nul eller én række, og escaping af
anførselstegn i en kopieret kommando er selv en fælde.)

Assertér ALLE bindinger, før udfaldet læses: `maalidentitet` = GO-pakkens
`EXPECTED_TARGET`, `source_id` = 1, `profile_id` = `daa-2018-20-clause-evidence-v1`,
`profile_sha256` = `7696cb87…`. Afviger én af dem, er det NO-GO uanset resten — så er
det ikke vores kørsel.

| Resultat | Betydning | Handling |
|---|---|---|
| 0 rækker | apply nåede aldrig at committe | Gentag trin 1's preflight-assertions; apply må køres én gang mere mod SAMME GO |
| 1 række, `finalized`, events = 591 og distinkte elementer = 591 | apply lykkedes | Gå til `05-verify.sh`; kør ikke apply igen |
| 1 række, `finalized`, andre tal | delvis eller fremmed batch | NO-GO: bevar alt, fortryd ved restore |
| 1 række, `open` | autorisation/batch in-flight | NO-GO: bevar alt, fortryd ved restore |
| 1 række, anden status (`reversed`, `activated` …) | uventet tilstand for denne kørsel | NO-GO: bevar alt, fortryd ved restore |
| 1 række, men en binding afviger | en anden kørsels batch | NO-GO: bevar alt, rør ikke prod, eskalér |
| >1 række | mere end én batch på samme manifest | NO-GO: bevar alt, fortryd ved restore |

### 5.2 `05-verify.sh` (læse-kun)

Mens redaktionspausen fortsat er aktiv, tager scriptet efter-projektionen og
kører komparatoren efter fasepakkens autoritative procedure. Bestået kræver:

- exit 0 og `status=match`;
- `database_target_sha256` = GO-pakkens prod-`EXPECTED_TARGET`;
- `records=591`, `clauses=868`;
- dispositioner eksakt 617/251;
- `neutral_lists` eksakt lig **denne GO-pakkes** restore-rehearsal;
- ingen `allowed_empty`, ingen kanonisk drift og ingen anon-drift;
- 591 `clause_evidence`-hændelser i præcis én `finalized` batch;
- profil-readback uændret og replay `already_applied`.

De supplerende læse-kun forespørgsler er de samme bytes, som bestod i rehearsal,
kører med `PGOPTIONS` og `ORDER BY ... COLLATE "C"`, og udskriver kun tal,
koder og hashes. Rapporten og alle projektioner hashes og bevares 0600.

**Rå artefakt vs. renset rapport.** Komparatorens egen rapport indeholder ved drift
konkrete `record_key`-værdier i `missing`, `extra` og `mismatched`, og dry-run-loggen
udskriver redaktørens aktør-ID. De filer er **rå, private evidensartefakter**: de
bevares 0600, sendes aldrig til AI-sessionen og gengives aldrig i dokumentationen. Det,
AI'en og dokumentationen må se, er en renset udskrift, som scriptet laver:

```bash
/usr/bin/python3 -c 'import json,sys
r=json.load(open(sys.argv[1]))
d=r.get("details",{})
print(json.dumps({"status":r["status"],"code":r.get("code"),"scope":r.get("scope"),
 "counts":r.get("counts"),"database_target_sha256":r.get("database_target_sha256"),
 "details_laengder":{k:(len(v) if hasattr(v,"__len__") else v) for k,v in d.items()}},
 ensure_ascii=False,sort_keys=True))' "$RUN/rapport.json" > "$RUN/rapport-renset.json"
```

De hærdede R-kopier må ikke udskrive aktør-ID; de logger kun, at en aktør med rollen
`redaktion` blev fundet.
Succesmarkør: `VERIFY_OK`. Først derefter ophæver projektejeren
redaktionspausen.

---

## 6. Fortrydelse — restore af dagens backup

Fortrydelse er den ENESTE vej tilbage, og den skal være øvet og bundet, før GO gives.
Rehearsalen i trin 2 beviser en restore til en **tom** lokal base; det er ikke det
samme som at lægge dumpet tilbage oven på en **befolket** database med Supabases
managed roller, ACL'er og aktive forbindelser.

**Øv fortrydelsen i trin 2 (lokalt, samme kørsel).** Rækkefølgen er:

1. Restorer dagens dump **med ejerskab** (altså UDEN `--no-owner`) til rehearsal-basen,
   efter at de otte tomme `NOLOGIN`-roller er oprettet. Så ligner objektejerskabet prods,
   og `--clean` i punkt 4 prøver samme drop-mønster som i prod.
2. Notér basens **tilstands-hash** før apply med `state-hash.sql` (nedenfor): en
   deterministisk hash over ALLE tabeller i `private` og `public`. Den dækker også
   `reimport_batch`, `reimport_authorization` og `extraction_run`, som projektionens
   `neutral_sha256` ikke omfatter.
3. Kør rehearsalens dry-run, profil-readback, før-projektion, apply og afstemning som
   i §3.
4. Kør `pg_restore --clean --if-exists --schema=private --schema=public` med dagens dump
   **oven på den samme, nu befolkede base** — ikke en frisk base.
5. Kræv i kode: 0 klausuler, 0 `clause_evidence`-hændelser, ingen writer-profilrække, og
   at tilstands-hashen er **identisk** med punkt 2.
6. Notér hvilke fejl restoren gav (kun `supabase_vault` er tilladt).

```sql
-- state-hash.sql — laese-kun, deterministisk (proevet: 1,5 s mod prod-restoren)
SELECT encode(pg_catalog.sha256(convert_to(coalesce(string_agg(h, E'\n' ORDER BY h COLLATE "C"), ''), 'UTF8')), 'hex') AS state_sha256
  FROM (
    SELECT n.nspname || '.' || c.relname || ':' ||
           encode(pg_catalog.sha256(convert_to(
             coalesce(query_to_xml(format('SELECT x::text AS r FROM %I.%I x ORDER BY x::text COLLATE "C"',
                                          n.nspname, c.relname), false, true, '')::text, ''), 'UTF8')), 'hex') AS h
      FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname IN ('private','public') AND c.relkind = 'r'
  ) s
```

**Målt i øvelsen 2026-09-17** (stand-in-dump taget lokalt af prod-tilstanden, klausuler
skrevet, derefter fortrydelse): tilstands-hashen vendte tilbage til præcis
før-tilstanden, og basen havde 0 klausuler, 0 `clause_evidence`-hændelser og 0
writer-profilrækker. Men `pg_restore` gav **8 fejl** i tre klasser:

1. `cannot drop function public.current_rolle() / public.media_id_for_object(text) /
   public.media_synlig_anon(bigint) because other objects depend on it` — RLS-politikker
   afhænger af dem. De bliver derfor ikke droppet og ikke genskabt. **Konsekvens:** en
   funktion, der er ÆNDRET efter dumpet, overlever en fortrydelse. Skrivepausen fra før
   dumpet er det, der holder den risiko nede.
2. `function … already exists with same argument types` for de samme tre — følgen af 1.
3. **`interpretation_observation_interpretation_id_fkey` kunne ikke genskabes**, fordi
   øvelsesbasen indeholdt én forældreløs række i `private.interpretation_observation`
   (`interpretation_id` uden `interpretation`, `observation_id` uden `source_observation`).
   Efter fortrydelsen havde basen **0 af 2** fremmednøgler på tabellen.

   **Hvor rækken kom fra — og hvorfor prod er ren.** Rækken blev oprettet 2026-09-17
   kl. 14:14:51, altså da rehearsal-basen blev bygget, af `db-verify.sql`'s
   dblink-samtidighedstest (`66000000-…`-fixturen), som indsætter i en separat session og
   ikke rydder rækken op igen. Prod-dumpet fra kl. 14:13:30 har **nul** rækker i tabellen
   (målt med `pg_restore --data-only --table=interpretation_observation`), så prod er ikke
   ramt. Derfor gælder også: `db-verify` kører KUN mod en disponerbar base — en kørsel mod
   prod ville efterlade netop denne række, og så ville en senere fortrydelse tabe to
   fremmednøgler.

**Målt i prøvekørslen af scriptene 2026-09-18** (rent stand-in-dump, hele kæden):
`REHEARSAL_OK` — 591 records, 868 klausuler, 617/251 dispositioner, 591 hændelser i én
`finalized` batch, `db-verify`s to #148-markører, **0** fejl i den første restore, **6**
tilladte fejl i fortrydelses-restoren, tilstands-hash identisk før/efter, 0 klausuler og
0 hændelser bagefter, replay `already_applied`, komparator `match`. To fejl blev fundet
og rettet undervejs, og de er værd at kende:

- psql interpolerer **ikke** variabler i `-c`-kommandoer. `-v dump_start=… :'dump_start'`
  gav en syntaksfejl; tidsstemplet inlines nu med en streng ISO-formatkontrol før brug.
- De tre RLS-afhængige funktioner giver **to** beskedformer:
  `cannot drop function public.X(args) because other objects depend on it` og
  `function "X" already exists with same argument types` (bart navn, uden skema og
  argumenter). En tilladelsesliste, der kun kender den første, stopper en korrekt
  fortrydelse.

**Rækken kan ikke bare slettes, hvis den opstår.** `private.interpretation_observation`
er append-only (`EVIDENCE_APPEND_ONLY`-trigger), så en oprydning kræver
`SET session_replication_role = replica` — i sig selv en prod-mutation, der skal have sin
egen GO og sit eget bevis. Derfor er stopporten nedenfor billigere end konsekvensen.

**Rehearsal-basen bevares** efter `REHEARSAL_OK` (den er beviset, GO'et hviler på) og
droppes først, når kørslen er afsluttet eller GO'et er bortfaldet. Scriptet skriver basens
navn i rapporten.

**Stopport før GO (billig, og den fanger netop den lækage):** prod skal have **0**
forældreløse rækker i `private.interpretation_observation`, og øvelsens fejlliste må kun
indeholde klasse 1 og 2. En fortrydelse, der efterlader tabellen uden fremmednøgler, er
ikke den tilstand, kvitteringen dækker.

**Hvad øvelsen beviser — og ikke beviser.** Den beviser, at dumpet kan lægges tilbage
oven på en befolket base og genskabe fuld tilstand i `private`+`public`. Den beviser
IKKE, at prods `postgres`-bruger har rettighederne: lokalt kører vi som superuser.
Rettighedsspørgsmålet besvares kun af privilegie-preflighten mod prod nedenfor, og dens
krævede resultat er 0/0 plus medlemskab og `CREATE`. Restoren fjerner desuden kun
objekter, der findes i dumpets indholdsfortegnelse — objekter oprettet efter dumpet
består. **Prisen ved en fortrydelse:** alt, hvad der er skrevet i `private` eller
`public` efter dumpets starttid, går tabt — også almindelige brugeres skrivninger under
RLS. Det er derfor, skrivepausen begynder før dumpet.

**Prod-metoden er valgt: vej A, afgrænset til vores egne to skemaer** (projektejeren,
2026-09-17). Supabase free-tier har ingen point-in-time-restore, så fortrydelse er et
`pg_restore` af dagens dump.

Målt i dumpet fra 2026-09-17 (`pg_restore -l`, ingen prod-forbindelse): 1 458 objekter
ejes af `postgres`, men 285 af `supabase_auth_admin`, 86 af `supabase_storage_admin`, 61
af `supabase_admin` og 51 af `supabase_realtime_admin`. Prods forbindelsesbruger er
`postgres` og er **ikke** superuser, så en fuld `--clean` ville forsøge at droppe
objekter, den ikke ejer. Inden for `private` og `public` ejer `postgres` derimod alle
1 395 rigtige objekter; de øvrige seks poster er ACL-/DEFAULT-ACL-poster, som `--clean`
ikke dropper. Klausulkørslen skriver kun i `private`, så en afgrænset restore er både
nok og gennemførlig:

```bash
pg_restore --clean --if-exists --no-owner --schema=private --schema=public \
  --dbname "$PGDATABASE" ~/.private/<dagens-dump>.dump
```

**Privilegie-preflight (læse-kun, køres af projektejeren FØR apply).** Gem som
`~/.private/148c-prod/rollback-preflight.sql` og kør med
`PGOPTIONS='-c default_transaction_read_only=on' psql -X -At -F' = ' -f …`:

```sql
SELECT * FROM (
SELECT 'bruger' AS maaling, current_user::text AS vaerdi
UNION ALL SELECT 'superuser', (SELECT rolsuper::text FROM pg_roles WHERE rolname=current_user)
UNION ALL SELECT 'relationer i private+public som brugeren IKKE ejer',
  (SELECT count(*)::text FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname IN ('private','public') AND c.relkind IN ('r','v','m','S','p')
      AND NOT pg_has_role(current_user, c.relowner, 'MEMBER'))
UNION ALL SELECT 'funktioner i private+public som brugeren IKKE ejer',
  (SELECT count(*)::text FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname IN ('private','public') AND NOT pg_has_role(current_user, p.proowner, 'MEMBER'))
UNION ALL SELECT 'skema private: ejer/medlem',
  (SELECT pg_get_userbyid(nspowner)||'/'||pg_has_role(current_user,nspowner,'MEMBER')::text
     FROM pg_namespace WHERE nspname='private')
UNION ALL SELECT 'skema public: ejer/medlem',
  (SELECT pg_get_userbyid(nspowner)||'/'||pg_has_role(current_user,nspowner,'MEMBER')::text
     FROM pg_namespace WHERE nspname='public')
UNION ALL SELECT 'CREATE paa private/public',
  (SELECT has_schema_privilege(current_user,'private','CREATE')::text||'/'||
          has_schema_privilege(current_user,'public','CREATE')::text)
) q ORDER BY maaling COLLATE "C"
```

Kravet er: **0** relationer og **0** funktioner, som brugeren ikke ejer, medlemskab af
begge skemaers ejere, og `CREATE` på begge. Alt andet er STOP, og så er fortrydelsen
ikke vej A — se alternativet nedenfor. Forespørgslen er prøvet mod prod-restoren, så
syntaksen er kendt god.

**Alternativ, hvis preflighten fejler:** nyt Supabase-projekt, restore af dumpet dertil
og omlægning af fladen. Det rører ikke den beskadigede base, men kræver nye nøgler, et
nyt `VITE_`-build af `web/` (env bages ind ved build) og en ny mobil-build. Vælges den
vej, skal GO-pakken bære den i stedet.

**GO må ikke gives, før preflighten er kørt mod prod med det krævede resultat og
fortrydelsen er øvet lokalt efter punkt 1-4.** Preflightens tal og øvelsens tal er en
del af GO-pakken.

---

## 7. Stopregler

- Intet GO uden en ny backup, en restore af netop dens SHA og en fuld bestået
  rehearsal af samme scripts og revision.
- Intet GO uden en valgt, preflightet og lokalt øvet fortrydelsesvej (§6). En
  fortrydelse, der først prøves den dag den skal bruges, er ikke en fortrydelse.
- Intet GO, hvis skrivepausen ikke var aktiv allerede før dumpet, eller hvis
  `00-freeze.sh begin` viste aktive ikke-egne forbindelser, der ikke kunne gøres rede
  for. Manglende `change_set`-rækker beviser ikke det modsatte.
- Enhver lokal ændring i en eksekveret eller sourcet fil efter GO er STOP, også når
  commit-SHA er uændret.
- Enhver `change_set.created_at >= dump_start` er STOP: nyt dump og ny
  rehearsal. Antal alene er aldrig en friskheds-port.
- Enhver anden restore-fejl end `supabase_vault`, manglende platformrolle eller
  ACL-afvigelse er STOP.
- Enhver afvigelse i mål-, dump-, script-, manifest-, rendition-, ledger-,
  parent-, profil-, rapport- eller commit-hash er STOP.
- Alt andet end 591 records, 868 klausuler, 617/251 dispositioner, 591 events,
  én `finalized` batch og replay `already_applied` er STOP.
- Enhver forskel i GO-pakkens `neutral_lists`, kanoniske rækker eller anon-
  projektion er STOP. Reparér aldrig prod for at få `match`.
- Komparator exit 1, en fejlkode, traceback uden JSON eller ugyldig projektion
  er NO-GO. Exit 2 er en brugsfejl: ret kun inputtet og genbrug de urørte
  projektioner, hvis deres hashes fortsat matcher GO.
- `REIMPORT_WRITER_RENDITION_DRIFT`,
  `CLAUSE_EVIDENCE_PARENT_TEXT_DRIFT`, uventet eksisterende profil/klausuler
  eller en aktiv autorisation er STOP.
- Efter enhver prod-mutation betyder STOP: bevar dump, runmappe og rapporter,
  hold redaktionen pauset, og gendan dagens backup. Der findes ingen kirurgisk
  klausul-reversal.

---

## 8. Fælder

1. `SET TRANSACTION READ ONLY` i psql-autocommit er en no-op. Brug sessionens
   `default_transaction_read_only`; projektionen styrer selv transaktionen.
2. Uændrede antal beviser ikke en frisk backup. Gate altid på `change_set` siden
   dumpets **start**, ikke sluttid.
3. Opret alle otte Supabase-platformroller som tomme `NOLOGIN`-roller før
   restore. Ellers er 111 GRANT/OWNER-fejl ikke harmløse.
4. `red_*` kræver `request.jwt.claim.sub` i transaktionen. R-scriptsættet gør
   dette; fjern ikke kontrollen.
5. Brug `COLLATE "C"` ved ordnet hashning/sortering; CI/lokal `en_US` og prod
   kan ellers give forskellige resultater.
6. Verifikations-SQL skal have bestået i rehearsal. En SQL-fejl efter apply gør
   ikke skrivningen ugjort.
7. Profilrækken indsættes varigt af dry-run. Før-projektionen tages derfor
   **efter** profil-readback og **før** klausul-apply.
8. Skrivepausen varer fra **før dumpet** til efter `VERIFY_OK` — ikke kun fra før- til
   efter-projektion. Trafik i projektionsvinduet giver korrekt
   `CANONICAL_DRIFT`/`ANON_DRIFT`; trafik mellem dump og pausestart er værre, for den
   er usynlig for gaten og går tabt ved en fortrydelse.
9. `neutral_lists` kommer fra dagens restore-rehearsal, ikke fra
   2026-09-17-rapporten. `database_target_sha256` er databasespecifik og må
   heller ikke kopieres fra en ældre rehearsal.
10. `--allow-empty` er forbudt mod prod. Der må ikke eksporteres eller
    segmenteres på ny i denne kørsel.
11. Ingen hemmeligheder, hostnavne, kildetekst eller record-nøgler må optræde i
    rapporter eller AI-output; brug kun `<record-key>` i et nødvendigt eksempel.

---

## 9. Efter kørslen

Når `VERIFY_OK` er dokumenteret, opdateres `status.md`, changelog,
`database-current-state` og `clause-evidence-148-rehearsal.md` med dato,
commit, rapport-hashes, de godkendte tal/hashes og restore som rollbackform.
Ingen kildetekst eller record-nøgler indsættes i dokumentationen.

Projektejeren kører derefter Supabase Advisors i dashboardet for både
**Security** og **Performance** og dokumenterer nye fund. Det kendte
Performance-fund `interpretation_predicate_fk` mangler indeks. Indekset hører
ikke til denne datakørsel og må ikke sniges ind her, men det **skal** etableres
før forslags-writeren kører på skala.

Bevar dagens dump, GO-kvittering, private scripts, før-/efter-projektioner og
alle rensede rapporter, indtil projektejeren særskilt lukker rollbackvinduet.
