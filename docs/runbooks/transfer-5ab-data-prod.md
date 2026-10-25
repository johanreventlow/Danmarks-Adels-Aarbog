# Runbook — data-ceremonien for 5a+5b (2018-20), GO 2

Autoritativ ceremoni for datadelen af spec
`docs/superpowers/specs/2026-10-21-trin5ab-2018-20-prod-overfoersel-design.md` (§6.4, §7-§9, GO 2 og
datafortrydelsen), bygget i plan B1 (`docs/superpowers/plans/2026-10-22-trin5ab-overfoersel-b1-vaerktoej.md`) og
plan B2 (`docs/superpowers/plans/2026-10-23-trin5ab-overfoersel-b2-ceremoni.md`). Ceremonien genspiller
arbejdskørslens pakke (25 skridt) i prod. Udgangspunktet er D1, der blev taget efter GO 1
(`transfer-5ab-ddl-prod.md`). Den skriver 5a+5b's personas, identiteter, afgørelser, bindinger,
børnehenvisninger, dispositioner, klassifikationer og P-afvisningen for kilde 1 (2018-20). Ingen nye kanoniske
personer.
Runbooken nævner aldrig kildetekst, navne eller aktør-uuid; kun tal, koder og hashes.

Prod rammes **kun** af projektejeren i egen shell (`! /bin/zsh -f …`). AI-sessionen åbner ingen forbindelse
til prod-basen; `17-go2.sh` er lokal og skriver kun GO 2-filen og `go-env.txt`.

## 1. Forudsætninger

- **Scripts:** `~/.private/5ab-overfoersel/` (`00-freeze.sh`, `08-advisors.sh`, `12-genspil.sh`,
  `14-verify-data.sh`, `15-undo-data.sh`, `16-hold-varm.sh`, `17-go2.sh`, `lib.zsh`, `koer.zsh`,
  `kaede-5ab.txt` m.fl.; den fulde liste er `GO2_PRIVATE_FILES` i `lib.zsh` og står i GO 2-filen).
  `koer.zsh` bærer GO-miljøet i `prod/go-env.txt` (fra GO 1; senere linjer vinder).
- **Overrides gives kun med `koer.zsh --saet NAVN=VÆRDI`**, aldrig som miljøvariabel foran kaldet (samme
  grund som i GO 1).
- **Aktøren:** `~/.private/5ab-overfoersel/b2/aktoer.txt` (0600, én uuid, sha = pakkens `actor_sha256`);
  `12` læser den (`ACTOR_FILE_MODE`, `ACTOR_FILE_INVALID`, `ACTOR_SHA_MISMATCH`, `PACK_ACTOR`).
- **`DAA_REPO` er hovedcheckouten på `main` ved GO 2-commit'en** (Task 7's docs-merge):

  ```
  ! git -C /Users/johanreventlow/TypeScript/danmarksadelsaarbog switch main && git -C /Users/johanreventlow/TypeScript/danmarksadelsaarbog pull --ff-only
  ```

  Repo-filerne i
  inventaret (`B2_REPO_FILES`) skal være rene og byte-ens med pakkens inventar (`REPO_DIRTY`,
  `INVENTORY_MISMATCH`), og commit'en skal være GO 2's (`COMMIT_MISMATCH`). Docs-ændringer efter optagelsen
  ændrer ikke inventaret.
- **Skrivepausen** fra GO 1 (`freeze-begin-20261022161315`, ansvarlig `jr`) løber stadig og slutter først
  ved `VERIFY_OK` (afsnit 5) eller en fortrydelse. Ingen redigering i webfladen imens: hver `change_set` efter
  D1's dump-start stopper indgangen. Et fejlslagent forsøg forlænger pausen: efter en datafortrydelse slutter
  den kun ved et nyt, vellykket genspil eller ved også at fortryde DDL'en (afsnit 6). Læg ceremonien, så der er
  tid til at rette og prøve igen.
- **Hold prod varm:** Supabase free tier pauser efter 7 dage uden trafik. Indtil ceremonien er kørt:

  ```
  ! /bin/zsh -f ~/.private/5ab-overfoersel/koer.zsh 16-hold-varm.sh
  ```

  mindst hver 5. dag og altid samme dag som ceremonien (læse-kun, `SELECT 1`). Om Supabase tæller det som
  aktivitet, er ikke målt; pauses projektet alligevel, genoptages det i dashboardet, og indgangsvagterne fanger
  enhver ændring.
- **Kun Session pooleren** (`*.pooler.supabase.com:5432`); alt andet giver `POOLER_REQUIRED`.

## 2. Pakken og dens beviser (lokalt, før GO 2)

Arbejdskørsel 3 (`daa5ab_data_arbejd_20261024221304`, commit `1edb762b`) er pakken. Bevist lokalt
2026-10-24/25:

| Bevis | Resultat |
| --- | --- |
| Optagelse | `CAPTURE_DONE steps=25`, `n_uuid_unmapped` 0, kanonisk delta kun i `identity` (5b's eget lag) |
| Indholdskontrol mod beviskæden (`daa244_bevis_20261020222244`) | `CONTENT_OK same=8827 allowed=51 unused_expected=0` efter projektejerens afgørelse A (afsnit 7) |
| Pakke | `PACK_OK steps=25 pack_sha256=46f5d1e59a9259f03168f67951f5b6d669e462e692ee4412917f6a36ca836150` |
| Genspil på frisk ICU-restore af D1, `PGTZ=Pacific/Chatham` (endelige bytes) | `REPLAY_OK` 25 skridt, `VERIFY_OK`, anden gennemkørsel skriver intet, 853 s inkl. verify og fortrydelse |
| Fortrydelse | `UNDO_OK`; restoren giver 5 kendte fejllinjer (`current_rolle()`/`media_object_synlig_anon(text)`, som i GO 1 afsnit 6), `fejl_sha256` `620b9304…` |
| Fortrydelsens prod-gren (stand-in, efter `VERIFY_OK` med markøren flyttet til side) | `UNDO_OK` (samme fejl, katalog og ACL = D1's), derefter `ENTRY_OK state=PRE` |
| Afbrud (stand-in i prod-tilstand) | `decide_2a` før commit og `disposition_2bii` efter autorisation ⇒ `STEP_FAILED … (STEP_FAULT)`; genkørsel fortsætter (`PARTIAL`) ⇒ `REPLAY_OK` + `VERIFY_OK`; én ubrugt autorisation ekstra (`reimport issued` 1 → 2) |
| Indgangsvagter (stand-in) | ekstra grant ⇒ `ENTRY_ACL`; ændret `change_set` ⇒ `ENTRY_RESTORE_HASH`, før første skrivning |
| Diagnose (libc-restore) | `REPLAY_OK` + `VERIFY_OK`; ingen lag afviger |

**Tal efter ceremonien (kilde 1):** bindinger 622 → 874 (**252** nye, ikke spec'ens 253; afsnit 7),
`public_family_sources` 0 → 252, personas og identiteter 587 → 832, fortolkninger 4.415 → 4.669, dispositioner
1.747 → 1.878, kandidater 2.327, kontrolstikprøve 30.

## 3. GO 2

**GO 1-hashfilen udstedes på ny først.** `lib.zsh` og `koer.zsh` er ændret efter GO 1 (plan B1/B2), så GO 1's
hashfil passer ikke længere, og `09-undo-ddl.sh` (opgivelsesvejen, afsnit 6) ville stoppe på `GO_HASHES`. Efter
de sidste kodeændringer bygges en ny fil (`go_hashes_lines` på de nuværende bytes, `prod/go-hashes-ddl-<ts>.txt`,
0600). Projektejeren godkender den på grundlag af en diff mod GO 1-filen (kun `lib.zsh`- og `koer.zsh`-linjerne
må afvige), og den sættes med `koer.zsh --saet DAA_GO_HASHES_FILE=<ny fil>`.

GO 2-filen bygges efter Task 7's merge. `17-go2.sh` er lokal og skriver kun filen; AI-sessionen kører den gennem
`koer.zsh`, så linjerne gemmes i `go-env.txt`. Er `DAA_EXPECTED_COMMIT` sat, kræver `17` den (`COMMIT_MISMATCH`):

```
! /bin/zsh -f ~/.private/5ab-overfoersel/koer.zsh --saet DAA_EXPECTED_COMMIT=<main-commit efter Task 7>
! /bin/zsh -f ~/.private/5ab-overfoersel/koer.zsh 17-go2.sh <run-3-mappe> \
    <run-3-mappe>/rapport/indholdskontrol-20261025091518.txt b2/maalinger/forventede-forskelle.json \
    b2/rehearsal-data.json b2/rehearsal-data-<genspilsbase>.json <run-3-mappe>/rapport/*.rapport \
    b2/rapport-opsummering-20261025.txt prod/go-hashes-ddl-<ts>.txt
```

Indholdskontrollens rapport er `CONTENT_OK`-kørslen (`indholdskontrol-20261025091518.txt`), ikke den første
(`n=42`). Forventet: `GO2_HASHES_OK linjer=… skridt=25 pack_sha256=46f5d1e5… commit=<main>` og linjerne
`DAA_GO2_HASHES_FILE`/`DAA_GO2_HASHES_SHA256`. Hver linje skal have en absolut sti
(`grep -c '^[0-9a-f]\{64\}  /' <fil>` = antal linjer).

**GO 2 binder** (alt står i GO 2-filen): repo-filerne og de private scripts; D1-kvitteringen; pakken
(`pack.json`), arbejdskørslens `meta.json`, `capture-done.json`, start- og slutmålinger (digests, uberørt,
vagter, baseline, kanoniske dele, restore-hash, ACL) og `godkendelser.txt` (hvert arks sha og
godkendelsesmåde). `12`, `14` og `15` kræver, at alle disse faste linjer står i filen (`GO_HASH_MISMATCH
(ubundet: …)`). Desuden rapporterne givet som argumenter: indholdskontrollen, listen over forventede
forskelle (afgørelse A; `17` binder den ikke selv), `rehearsal-data.json` og svaroverførslens rapporter.

Overførselsrapporterne (plan B2 Task 7 Step 5): projektejeren besluttede 2026-10-25, at en formopsummering
(antal og linjetyper pr. rapport, intet indhold; `b2/rapport-opsummering-20261025.txt`) træder i stedet for fuld
gennemlæsning. Alle svar er overført; de markerede linjer er kort- og kommentartekst efter den nye stikprøve,
#244-bortfaldet og v3's OBS- og `bundet`-linjer. Opsummeringen gives som argument til `17` og bindes. GO 2 er
projektejerens ord i chatten, bundet til `DAA_GO2_HASHES_SHA256`.

## 4. Genspil i prod (GO 2 skrivende)

Først indgangen alene (skriver intet):

```
! /bin/zsh -f ~/.private/5ab-overfoersel/koer.zsh 16-hold-varm.sh
! /bin/zsh -f ~/.private/5ab-overfoersel/koer.zsh 12-genspil.sh prod
```

Forventet: `ENTRY_OK state=PRE NEXT n=1 name=profile`. Indgangens vagter, i rækkefølge:

| Vagt | Stopkode |
| --- | --- |
| Rent miljø (ingen `DAA_FAULT`, `DAA_LOCAL_*`, `DAA_STANDIN_*`, arvet aktør) | `FAULT_IN_PROD` / `LOCAL_ENV_IN_PROD` / `STANDIN_REPO_IN_PROD` / `ACTOR_ENV_INHERITED` |
| Rent repo, GO 2-commit | `REPO_DIRTY` / `COMMIT_MISMATCH` |
| GO 2-filens sha og hver bundet fil | `GO_HASH_MISMATCH` |
| Pakken gyldig, inventaret = repoet, kilde og aktør = pakkens | `PACK_INVALID` / `INVENTORY_MISMATCH` / `PACK_SOURCE` / `ACTOR_FILE_*` / `ACTOR_SHA_MISMATCH` / `PACK_ACTOR` |
| Fuld pakke (D1-restore, kædens skridt, slutvagterne bestået) | `PACK_INCOMPLETE` / `PACK_CHAIN` / `PACK_SLUT` |
| Mål = prods identitet = GO-miljøets | »maalidentiteten afviger fra GO-pakken« |
| Skrivepausen aktiv fra før D1's dump-start, rapporten bundet | `FREEZE_NOT_ACTIVE` / `FREEZE_REPORT_BINDING` |
| Restore-hash = D1's | `ENTRY_RESTORE_HASH` (enhver dataændring siden D1, fx en webredigering) |
| Portabel ACL = arbejdskørslens start = D1's | `ENTRY_ACL` |
| 0 `change_set` efter D1's dump-start | `NO_WRITE_SINCE_DUMP` (forsvar i dybden; restore-hashen fanger det først) |
| Digests = pakkens start | `ENTRY_DIGESTS` |

Derefter:

```
! /bin/zsh -f ~/.private/5ab-overfoersel/koer.zsh 12-genspil.sh prod --jeg-mener-det
```

Forventet: 25 linjer `STEP n <navn> WRITE s=…` (skridt uden skrivning: `ALREADY_APPLIED`) og
`REPLAY_OK steps=25`. Lokalt tog skridtene i alt ca. 6 minutter (kandidater ~150 s, korroboration ~55 s,
kontrol ~37 s); i prod 2026-10-25 tog kandidater 231 s, korroboration 101 s og kontrol 67 s.

**Tidsgrænsen:** prod afbryder en enkeltsætning efter 2 min (4.4's G7). Runneren sætter derfor
`statement_timeout = '15min'` for hvert skridts forbindelse og stopper med `TIMEOUT_NOT_SET`, hvis værdien ikke
når sessionen (rettet 2026-10-25, efter at første forsøg stoppede ved skridt 3 med `STATEMENT_TIMEOUT`). Lokale
baser har ingen grænse, så en genspilsprøve fanger det kun på en stand-in med `ALTER DATABASE … SET
statement_timeout = '2min'`.

**Stop i indgangen (`state=PRE`) er ikke en fortrydelsessag.** Intet er skrevet; en `ENTRY_*`-kode betyder,
at prod har ændret sig siden D1 (også en rullet-tilbage webskrivning ændrer sekvenserne og dermed
restore-hashen). Kør **ikke** `15` (den nægter med `UNDO_NOT_STARTED`, fordi restoren ville slette den fremmede
ændring umålt); mål forskellen (`change_set`, sekvenser, grants) og forelæg den.

**Afbrud eller `STEP_FAILED`:** kør samme kommando igen. Run-mappen har `started.txt`/`done.txt`, så
genspillet starter som `PARTIAL` og klassificerer kun næste skridt; et skridt, der ikke nåede `COMMIT`, er
uændret og køres igen. En ubrugt autorisation efter et afbrud i `disposition` er forventet og udelades af
verifikationen. I `PARTIAL` springes indgangens restore-hash- og ACL-vagter bevidst over; en fremmed skrivning
mellem to forsøg fanges først af `14` (`VERIFY_UNTOUCHED`, `VERIFY_ACL`). **Uoprettelig:** `MIXED` (exit 3:
lagene er hverken før eller efter skridtet) og divergens efter `COMMIT` (`RUNNER_REPLAY_DIVERGED`,
`RUNNER_LAYER_UNDECLARED`, `REPLAY_DIGESTS`: skridtet er skrevet, men ikke logført, så næste kørsel giver
`MIXED`) ⇒ fortrydelse (afsnit 6). Hvad der så kræves, afhænger af rettelsen: ændres kun private scripts, ny
genspilsprøve og ny GO 2-fil; ændres en fil i pakkens inventar (skridt-SQL, `B2_REPO_FILES`, kædefilen), ny
arbejdskørsel (plan B2 Task 5-7).

## 5. Efter genspillet

I denne rækkefølge; webtjekket (læse-kun) ligger før `00 end`, fordi det er sidste øjeblik, en fortrydelse er
mulig:

```
! /bin/zsh -f ~/.private/5ab-overfoersel/koer.zsh 14-verify-data.sh prod
! /bin/zsh -f ~/.private/5ab-overfoersel/koer.zsh 08-advisors.sh data
```

**Webfladen:** åbn en af de berørte familier og se, at ægteskabernes kildehenvisning vises; åbn redaktørens
identitetskø (skal svare uden fejl). Derefter:

```
! /bin/zsh -f ~/.private/5ab-overfoersel/koer.zsh 00-freeze.sh end
```

Forventet: `VERIFY_OK measure_sha256=… authorizations_issued=…` (skriver `prod/verify-ok.json`; `14` kan
kun skrive markøren én gang), `ADVISORS_DATA_OK nye=0` (`08 data` kan køres igen; hver kørsel får sin egen
fil, og `advisors-after.txt` skal have GO 1's sha) og `FREEZE_END_OK mode=verify`. `14` kræver: alle nøglede digests =
arbejdskørslens slut (`authorizations_issued` kun rapporteret), `n_uuid_unmapped` 0, kanonisk baseline =
arbejdskørslens start = D1's (`a51323ac…`; 0 nye personer), uberørt og andre kilder uændrede, vagterne =
arbejdskørslens slut, `anon`-matrixen (portabel ACL) = D1's. `08 data` kræver ingen nye
sikkerhedsfund i forhold til GO 1's `advisors-after.txt` (ceremonien skriver ingen DDL); se også Advisors →
Security i dashboardet. Skrivepausen er ophævet ved `FREEZE_END_OK`.

**Fejler `08 data` eller webtjekket efter `VERIFY_OK`:** `15` nægter (`VERIFY_OK_FINDES`). En fortrydelse kræver
da projektejerens udtrykkelige beslutning; markøren flyttes reversibelt til side
(`mv prod/verify-ok.json prod/verify-ok.tilbagekaldt-<ts>.json`), og `15` køres. Efter `00 end` er der bevidst
ingen scriptet datafortrydelse: pausen er væk, og en ny pause kan ikke begynde før D1's dump.

## 6. Fortrydelse (data)

```
! /bin/zsh -f ~/.private/5ab-overfoersel/koer.zsh 15-undo-data.sh prod --jeg-mener-det
```

`15` kræver, at genspillet er begyndt (`UNDO_NOT_STARTED`, se afsnit 4), og at D1's ACL-linjefil har
kvitteringens portable og lokale del (`UNDO_ACL_SOURCE`). Den restorer D1's `private`/`public` (som GO 1's
fortrydelse: skema-defaults fjernes først, grants og defaults afstemmes mod D1's ACL-linjer bagefter,
`NOTIFY pgrst`), arkiverer genspillets run-mappe (`genspil-data.fortrudt-<ts>`), så et nyt `12` starter som
`PRE`, og giver `UNDO_OK`, når restore-hash og portabel ACL er D1's, og det portable katalog (tabeller, views,
funktioner, RLS-politikker) er det samme som før restoren og D1's (`UNDO_CATALOG`). Restoren forventes at give
de samme 5 fejllinjer som i genspilsprøven (de to storage-afhængige funktioner): sammenlign `fejl_sha256` i
`UNDO_OK`-linjen med genspilsprøvens (`620b9304…`); en afvigelse forelægges. Restoren er kun øvet lokalt, ikke
mod Supabase over pooleren; webfladen kan svare med fejl, mens den kører. Prisen: alt skrevet i `private`/`public` efter D1's start går tabt; under pausen er det kun
ceremonien. Markøren hedder `undo-data-ok-<ts>.json`. Prod-grenen er kørt på en stand-in (afsnit 2).

**Pausen fortsætter efter en datafortrydelse.** `00-freeze.sh end` kræver `verify-ok.json`, og
`end --efter-fortrydelse` kræver GO 1's DDL-fortrydelse (`undo-ok.json`, tilstand `PRE`); DDL'en står stadig
efter `15`. Vejen videre er derfor: ret årsagen og genspil (afsnit 4), med samme GO 2, hvis intet i GO 2-filen er
ændret, ellers en ny. En ny pause kan ikke erstatte den gamle: indgangen kræver en pause, der begyndte før D1's
dump. Opgives overførslen helt, fortrydes også DDL'en efter GO 1-runbookens afsnit 6 (med den genudstedte GO
1-hashfil, afsnit 3; `DAA_EXPECTED_COMMIT` er da GO 2's), og pausen lukkes med `end --efter-fortrydelse`.

## 7. Kendte afvigelser fra spec'en

- **252 bindinger, ikke 253** (projektejerens afgørelse A, 2026-10-25). Kontrolarket bruger en ny stikprøve og
  blander kandidaternes visningspladser. Et dubletsvar (`1=3`: to personposter er samme individ) bindes efter
  spec §23.4 til den laveste visningsplads. I beviskæden stod den personpost øverst, som familien bruger; i
  arbejdskørslen den anden. Ægtefællepersonaens identitet peger derfor i prod på dubletposten, og ét ægteskab
  bliver stående som forslag uden kildehenvisning for læseren, til dubletten slås sammen
  (`samme_som`-arbejdet). Fejlen i reglen rettes før 1939 (`decisions.md`).
- **38 identiteter skifter oprindelse** mellem kontrolark (`human_sheet`) og familieopslag
  (`family_corroboration`), fordi stikprøven er ny (19 hver vej). Identiteterne er de samme.
- De øvrige forventede forskelle (#244's genbindinger og bortfald) står i plan B2 Task 0 og i listen over
  forventede forskelle.

## 8. Efter `VERIFY_OK`

- Docs: `status.md`, `changelog.md`, `database-current-state.md` (plan B2 Task 8 Step 5).
- **Oprydning** af arbejds-, genspils-, stand-in- og diagnosebaser (`daa5ab_data_*`) og karantænen
  `karantaene-test-20261024` (tidligst 2026-11-07): kun efter måling og projektejerens ja. Dumps, pakken,
  `go-env.txt` og bevisbaserne bevares.

## 9. Udfald 2026-10-25

- **GO 2 `d66e19f8…`:** `HOLD_VARM_OK`, `ENTRY_OK state=PRE`; genspillet skrev skridt 1-2 og stoppede ved skridt 3
  (`STEP_FAILED 3 candidates (STATEMENT_TIMEOUT)`; ét RPC-kald, rullet tilbage). Prod stod i `PARTIAL`, skrivepausen
  aktiv.
- **Rettelsen** (afsnit 4, Tidsgrænsen) blev bevist på stand-in s3 med en grænse på 2 min: de gamle bytes gav samme
  stop, og med de nye fortsatte genoptagelsen fra skridt 3 til `REPLAY_OK` og `VERIFY_OK`. Derefter `RUNNER_OK`, ny
  genspilsprøve (`REHEARSAL_OK`, 771 s), ny GO 1-hashfil (kun `lib.zsh` afviger) og ny GO 2-fil `4bd78fa9…`.
- **GO 2 `4bd78fa9…`:** `ENTRY_OK state=PARTIAL NEXT n=3 name=candidates`, skridt 3-25 skrevet,
  `REPLAY_OK steps=25 slut_sha256=92a609f5…`; `VERIFY_OK` med samme sha, `authorizations_issued=1`;
  `ADVISORS_DATA_OK nye=0 forsvundne=0` (60 fund, sha = GO 1's); webtjek; `FREEZE_END_OK mode=verify`.
