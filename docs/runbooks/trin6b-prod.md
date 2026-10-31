# Runbook — trin 6b i prod: ceremoni A (DDL) og B (1939's personas)

Spec: `docs/superpowers/specs/2026-10-31-trin6b-identitet-design.md` §4.1-§4.2, §4.6, §6 og §7. Plan:
`docs/superpowers/plans/2026-10-31-trin6b-identitet.md` Task 13 og 14. Ceremoni C (identiteterne) er blokeret,
indtil 6c's runner har kørt i prod; runbooken udvides med C i Task 15.

- **Ceremoni A** lægger trin 6b's DDL i prod: blokken fra `-- ===== trin 6b: publication-operationer =====` til
  slutningen af `db-migrations.sql` og derefter `db-rls.sql`, i én transaktion. A er additiv:
  - 17 nye funktioner, heraf 5 `public.red_*`, som `authenticated` kan kalde: de to elementoperationer
    `red_apply_reimport_publication_persona` og `red_apply_reimport_publication_identity`, kontrollen
    `red_publication_control` og `red_publication_control_details` samt C's fortrydelse
    `red_reverse_reimport_publication`;
  - 8 eksisterende funktioner erstattes: `decide_source_persona_identity`, `identity_candidate_input`
    (årstalsreserven), `validate_reimport_authorization_payload`, `validate_reimport_writer_config`,
    `red_finalize_reimport`, `red_reimport_batch_result`, `red_source_persona_queue` (webkøens filter) og
    `red_afgoer_source_persona`;
  - 2 indekser på `private.reimport_event`.

  A skriver kun én datarække: publikationsprofilen `daa-1939-publication-v1` i `private.reimport_writer_profile`.
  Ingen tal i målingen ændres.
- **Ceremoni B** skriver 1939's personas med profilen `daa-1939-publication-v1` gennem writerens kæde
  (authorize → begin → apply → finalize). Det er 555 `source_persona` og hver sin `primary`-mention i sin egen
  helpost. B skriver **ingen identitet**. Indtil C har kørt, er de 555 skjult i webkøen, og `red_afgoer_source_persona`
  afviser dem.

Runneren er privat: `~/.private/5ab-overfoersel/26-trin6b.sh` med `26-trin6b-b.R` og 5c-2's `lib.zsh`/`koer.zsh`.
Projektejeren kører alt, der rører prod, fra egen shell. AI-sessionen læser kun rapporter med tal, koder og hashes.

`26-trin6b-b.R` kører kæden med sine egne SQL-kald, ikke med `execute_reimport` fra `apply_reimport_helpers.R`.
Hjælperen kender ikke `publication_persona`: den mangler i `dependency_class`-listen, i nøglerne til `expected_counts`
og i gatewayens operationer. Transaktionsformen er den samme som i 6a:

- dry-run i én transaktion, der rulles tilbage;
- autorisationen committes for sig som `service_role`;
- apply og finalize i én transaktion;
- replay med en ny autorisation.

Samme form som den fælles gateway er sikret ved konstruktion, ikke ved fælles kode.

## Forudsætninger

- PR 1 og PR 2 er merget. `main` er checket ud rent i `/Users/johanreventlow/TypeScript/danmarksadelsaarbog`.
- **Vindue og skrivepause.** Pausen går fra dumpet i skridt 3 til B er godkendt (skridt 11), som i 6a. Der skrives
  ikke redaktionelt i prod i den tid. Både A's restore-alternativ (dumpet fra skridt 3) og B's fortrydelse (dumpet
  fra skridt 8) afhænger af pausen. Projektejeren er den eneste aktive redaktør; meld det, hvis andre er aktive.
  - Pausen er fortrydelsens grænse. En restore af dumpet sletter alt, der er skrevet efter det.
    `fortryd-b` stopper derfor (`T6B_VINDUE_BRUDT`), hvis der er nye `change_set`-rækker eller andre batches end B's
    efter dumpets start.
  - Når 6c's runner har skrevet, kan B ikke længere fortrydes (se Fortrydelse).
- Runnerens faste værdier passer til `main`:
  - `T6B_BLOK`: blokkens sha, `38a83bca…`;
  - `T6B_RLS`: `db-rls.sql`'s sha, `f517b2e5…`;
  - `T6B_PROFILE_SHA`: publikationsprofilens sha, `dfca126f…`;
  - `T6B_MANIFEST_CONTENT`: manifestets indholds-sha, `36dfa422…`.

  Ændres `db-migrations.sql`, `db-rls.sql`, `publication_persona_manifest.sql` eller `maal_trin6b.sql` efter
  øvelsen, skal øvelsen gentages, og værdierne skal opdateres, før der tages GO.
- **Slutøvelsen på `main` efter merge af PR 2 er gennemført** (se Øvelse). Den kører den runner, der skal bruges i
  prod, på en frisk stand-in. Ændres runneren, filerne ovenfor eller skemaet derefter, gentages den før GO.
- `DAA_EXPECTED_TARGET` (prods målidentitet) står i `prod/go-env.txt`, som ved 5c-2 og 6a.

## Forløb (projektejerens shell)

Alle kommandoer køres som `/bin/zsh -f ~/.private/5ab-overfoersel/koer.zsh 26-trin6b.sh …`. `koer.zsh` gemmer
runnerens `DAA_`-linjer (`DAA_T6B_DUMP_FOER`, `DAA_T6B_DUMP_A` og `DAA_T6B_MANIFEST`) i `prod/go-env.txt`.

### Ceremoni A

1. `maal` giver tre linjer:
   - `T6B_MAAL tilstand=foer personas_k3=8 identiteter_k3=8 afventer=0 k1_personas=832 k1_identiteter=832 k1_hash=…`.
     Notér 2018-20-delen (`k1_*`); den skal være uændret gennem hele forløbet;
   - `T6B_MAAL_OK tilstand=foer sekunder=…`. Målingen er ceremoniernes første læsning mod prod og dermed tidsprøven.
     Tager den over 60 s, stoppes der, og der måles igen;
   - `T6B_DEFACL globale_authenticated=0 globale_anon=0 globale_public=0`. Der må ikke være globale default-
     rettigheder til `authenticated`, `anon` eller PUBLIC. Ellers kan en tabel, en writer opretter (C's temp-cache),
     få en grant, ingen har givet. Er et tal større end 0: stop, og afklar det før C.

   Tag samtidig `get_advisors(security)` som før-billede.
2. `go-a` → `GO_6B_A_KODE=<8 hex>`. Projektejeren skriver `GO 6b-A <kode>`. Koden binder:
   - ceremonien og målet (prod/stand-in);
   - commit'en;
   - repo-filerne `db-migrations.sql`, `db-rls.sql`, `maal_trin6b.sql`, målidentitetens SQL og
     `transfer_acl_fingerprint.sql`;
   - de private filer: runneren, R-scriptet, `lib.zsh`, `koer.zsh` og `rollback-preflight.sql`.

   B's kode binder desuden `publication_persona_manifest.sql` og manifestet.
3. `dump` → `DUMP_6B_OK tilstand=foer …` og `EKSTERN_6B_OK … rundtur=ok`. Det er B1: en `age`-krypteret kopi lægges
   på SFTP-serveren, hentes tilbage, sammenlignes og dekrypteres. Den dekrypterede rundtur-kopi slettes efter
   kontrollen. Kvitteringen bærer basens tilstand og dumpets starttid. `apply-a` kræver `foer`.
4. `apply-a --jeg-mener-det --go <kode>` →
   - `B1_6B_OK …`: dumpet og den eksterne kopi er kvitteringens bytes;
   - målingen før skal være `foer`;
   - blokken (sha bundet) og `db-rls.sql` (sha bundet) køres i én transaktion med `lock_timeout` 5 s. Derefter
     `NOTIFY pgrst, 'reload schema'`;
   - `T6B_APPLY_A_OK tilstand=a personas_k3=8 identiteter_k3=8 afventer=0 k1_… sekunder=…`: målingen efter er
     tilstand `a`, 2018-20 er uændret, og publikationsprofilens sha er `T6B_PROFILE_SHA`.
5. `get_advisors(security)` igen. Diff mod før-billedet fra skridt 1:
   - forventet er højst de 5 nye `public.red_*`-funktioner fra listen øverst (SECURITY DEFINER, kan kaldes af
     `authenticated`, som de øvrige `red_apply_reimport_*`);
   - alt andet undersøges, før B køres.

### Ceremoni B

6. `manifest` → `T6B_MANIFEST_OK elementer=555 allerede_persona=8 binding_uegnet=0 helpost_uegnet=0
   ingen_bundet_narrativ=13 ingen_helpost=8 ingen_postbinding=21 staged_ikke_offentlig=2 indhold=36dfa4229cec847a …`.
   - Skridtet er læse-kun og kræver tilstand `a`. Det kører `publication_persona_manifest.sql` mod basen.
     Manifestet rummer kun id'er, nøgler og hashes; mentionens tekst indgår kun som SHA-256.
   - Runneren lægger kilden og profilens sha om manifestet og beregner indholds-sha'en over
     `{source, expected_counts, elements}`.
   - Tal og etiketter skal være præcis disse (se Manifestets etiketter). Indholdet skal være øvelsens. Afviger det,
     er prod en anden end stand-in'en, fx efter redaktionelle skrivninger efter 2026-10-30. Så stopper B her
     (`MANIFEST_SOM_OEVET`), og øvelsen gentages på et nyt dump.
7. `go-b` → `GO_6B_B_KODE=<8 hex>`. Projektejeren skriver `GO 6b-B <kode>`. Koden binder også manifestet.
8. `dump` igen → `DUMP_6B_OK tilstand=a …` og `DAA_T6B_DUMP_A=…`. Det er fortrydelsens dump. `apply-b` kræver et
   dump taget i tilstand `a`, højst 12 timer gammelt; ellers `STOPPORT: DUMP_6B_TILSTAND` eller `DUMP_6B_MANGLER`.
9. `apply-b --jeg-mener-det --go <kode>` →
   - `B1_6B_OK …`;
   - målingen før skal være `a`;
   - `26-trin6b-b.R` kører dry-run, authorize (som `service_role`), apply og replay:
     - `T6B_B_DRYRUN status=finalized`;
     - `T6B_B_KONTROL personas=555 primary_i_egen_helpost=555 helposter=555 identiteter=0 afventer=555
       records_med_to_personas=0 personas_k3=563`;
     - `T6B_B_PUBSTATE n=563 uaendret=TRUE`: `narrative_publication_state` for de 563 bundne poster er byte-ens før
       og efter;
     - `T6B_B_KOE foer=8 efter=8 nye_i_koeen=0 uaendret=TRUE`: webkøen for kilde 3 viser de samme 8 som før og
       ingen af de 555;
     - `T6B_B_REPLAY already_applied samme_batch=TRUE`;
   - `T6B_APPLY_B_OK personas=555 identiteter=0 status=finalized sekunder=… inkl_dryrun=… tilstand=b
     personas_k3=563 identiteter_k3=8 afventer=555`, og `k1` er uændret.
10. `maal` → `T6B_MAAL_OK tilstand=b`, `k1` uændret.
11. Projektejeren godkender B. Skrivepausen slutter, og redaktionen kan skrive igen. Derefter dækker fortrydelsen
    ved restore ikke længere (`T6B_VINDUE_BRUDT`).

Kør aldrig `apply-b` igen, når B er `finalized`: tilstanden er så ikke længere `a`, og runneren stopper selv med
`STOPPORT: T6B_FOER_B`.

## Varighed og prods tidsgrænse

Prods `statement_timeout` er 2 minutter. Grænsen gælder pr. sætning, ikke pr. ceremoni. Stand-in-tallene er fra
slutøvelsen 2026-10-31.

| | Stand-in | Forventet i prod (ca. 55×) | Én sætning? |
|---|---|---|---|
| Målingen (`maal_trin6b.sql`), i alle tilstande | 0,0-0,1 s | sekunder (stop ved > 60 s, skridt 1) | ja |
| Dump (15 MB) | 1,7 s | netværk; minutter | — |
| A: blokken + `db-rls.sql` | 0,2 s | ca. 10-15 s | nej (mange) |
| Manifestet (`publication_persona_manifest.sql`) | 0,9-1,0 s | ca. 50-55 s | **ja** |
| B: dry-run | 2,2-2,3 s | ca. 2 min | nej (ét kald pr. element) |
| B: apply + finalize | 2,2-2,4 s | ca. 2 min | nej |
| B: kontrolforespørgslen (`T6B_B_KONTROL`) | 0,8 s | ca. 45 s | **ja** |
| B: `narrative_publication_state` over 563 (to gange) | 0,3 s | ca. 17 s | **ja** |
| B i alt (`inkl_dryrun`) | 5,2-5,6 s | ca. 5 min | — |
| Fortrydelsen: restore af private+public | 2,8 s | minutter | nej |
| Fortrydelsen: ANALYZE, `db-rls.sql`, grants | 1,3 s | under 2 min | ANALYZE kører med 15 min |

Forholdet mellem prod og stand-in er ikke målt på ny (ingen ekstra prod-berøring). De kendte faktorer fra
6a-runbooken er:

- 2018-20's klausulkørsel tog 230 s i prod mod 4 s på stand-in (148c, 2026-09-18), altså ca. 55×;
- 5c-2's måling tog over 120 s i prod mod 6 s (2026-10-29), altså mindst 20×.

55× er det relevante forhold for B's mange små kald. De tre forespørgsler markeret »ja« er hver én sætning, så hele
deres tid tæller mod grænsen. Den største er manifestet, med et skøn på omkring det halve af grænsen. Overskrides
grænsen alligevel, stopper skridtet med `STATEMENT_TIMEOUT` uden at skrive (manifestet og kontrollerne er læse-kun).
For kontrollerne gælder det dog først **efter** B's commit (se Stoppunkter). Skønnene er ikke beviser.

## Stoppunkter

Alle `STOPPORT:`-linjer stopper uden at skrive yderligere. Hvor langt man er nået, læses af `maal` og af batchens
status i `private.reimport_batch` (profil `daa-1939-publication-v1`).

| Hvor | Tilstand bagefter | Gør |
|---|---|---|
| Før `apply-a`'s blok (`DUMP_6B_MANGLER`, `GO_MISMATCH`, `T6B_FOER`, `T6B_BLOK`, `T6B_RLS`) | `foer`; intet skrevet | Ret årsagen, kør skridtet igen |
| I A's transaktion (`DDL_6B fejlede`) | `foer`; rullet tilbage | Ret årsagen; ny GO, hvis filer ændres |
| Efter A's commit (`DDL_6B_NOTIFY`, `T6B_EFTER_A`, `T6B_K1_UAENDRET`, `T6B_PROFIL`) | A er committet | Kør `maal`. Er den `a` og `k1` uændret: kør `NOTIFY pgrst` manuelt og fortsæt. Ellers: stop og undersøg; fortrydelse af A (nedenfor) |
| `manifest` (`MANIFEST_TAL`, `MANIFEST_DISPOSITIONER`, `MANIFEST_SOM_OEVET`, `T6B_PROFIL`) | `a`; læse-kun | Stop. Prod afviger fra stand-in'en: mål forskellen, gentag øvelsen på et nyt dump, opdatér værdierne |
| B før apply-commit (fejl i dry-run, authorize eller apply) | `a`; batchen rullet tilbage | Læs koden: `T6B_B_FEJL (<kode>; sidste trin: …)` og den fulde fejllinje (`Fejl:`/`Error:`) i `apply-b-*.out`; ret; `apply-b` igen med samme GO. Dumpet i tilstand `a` gælder i 12 timer; derefter et nyt `dump` |
| Efter B's commit: `T6B_B_KONTROL_AFVIGER`, `T6B_B_PUBSTATE_AENDRET`, `T6B_B_KOE_VISER_NYE`, `T6B_B_REPLAY_STATUS`, `T6B_EFTER_B`, `T6B_K1_UAENDRET`, eller en fejl i kontrollerne (`sidste trin: T6B_B_DRYRUN`, men batchen er `finalized`) | batchen `finalized` | Kør `maal`. Er den `b` og `k1` uændret, er B skrevet; undersøg kontrolfejlen bagefter. Viser kontrollen, at B skrev forkert, eller er `k1` ændret: **fortrydelsestilfælde**, `fortryd-b` (nedenfor) |
| Målingens egne fejl (`maal_trin6b.sql fejlede`, `T6B_MAAL_FORM`, `MAAL_6B_UKENDT`) | uændret af fejlen selv | Efter et commit: læs batchens status og kør `maal` igen; før et commit: intet er skrevet |

`GO_MISMATCH` viser den kode, filerne svarer til nu (lib's `expect_eq`, som i 6a). Koden binder indhold og er ikke en
hemmelighed. Brug den ikke uden at have tjekket, hvad der er ændret siden GO.

## Fortrydelse pr. fase (spec §6)

- **Ceremoni A:** de tidligere funktionskroppe fra dumpet fra skridt 3. Det er ikke scriptet og ikke øvet; det
  bygges kun, hvis det bliver nødvendigt. Det kræver:
  - drop de 17 nye funktioner;
  - genskab de 8 erstattede funktioner fra dumpet fra skridt 3, med deres REVOKE/GRANT;
  - drop de 2 nye indekser;
  - tag stilling til profilrækken;
  - kør `db-rls.sql` fra commit'en før 6b.

  Alternativt restore af dumpet fra skridt 3, hvis intet andet er skrevet i vinduet.
- **Ceremoni B, før 6c's runner:** fortrydelse er **kun** restore af dumpet fra skridt 8 (tilstand `a`).
  `source_persona` og `source_persona_mention` er append-only (`private.reject_evidence_mutation`), så ingen writer
  kan slette dem; `red_reverse_reimport` gælder ikke for B. Gør sådan:
  1. `go-fortryd` → `GO_6B_FORTRYD_B_KODE=<8 hex>`. Koden binder også kvitteringen `DAA_T6B_DUMP_A`. Projektejeren
     skriver `GO 6b-fortryd-B <kode>`.
  2. `fortryd-b --jeg-mener-det --go <kode>`. Runneren:
     - kontrollerer dumpet og den eksterne kopi (`B1_6B_OK`);
     - kræver tilstand `b`. Tilstand `c` stopper med `T6B_FORTRYD_C`;
     - kræver, at vinduet holder (`T6B_VINDUE_BRUDT`), og at forbindelsens bruger ejer alt i private+public
       (`RESTORE_PRIVILEGES`);
     - måler grants og default-rettigheder;
     - fjerner rollens skema-defaults;
     - kører `pg_restore --clean --if-exists --no-owner --schema=private --schema=public`;
     - genskaber skema-defaults;
     - kører ANALYZE og `db-rls.sql`;
     - afstemmer grants mod målingen før restoren;
     - sender `NOTIFY pgrst`;
     - kræver, at grants og default-rettigheder er som før restoren, at målingen er `a`, og at `k1` er uændret.

     Kvitteringen er `T6B_FORTRYD_B_OK … restore_fejl=5 … grants_afstemt=<tilbagekaldt>|<givet> acl=som_foer`.
  3. `maal` → `a`. B kan derefter køres igen fra skridt 9 med samme manifest og samme dump (ny batch).

  **`db-rls.sql` alene er ikke nok efter en restore.** pg_dump skriver ACL'er relativt til `acldefault`, og rollens
  default-rettigheder virker på alt, restoren opretter. Det gælder begge veje:
  - prods `postgres` har skema-defaults, der giver anon/authenticated/service_role rettigheder i `public`. De giver
    restorede objekter grants, som dumpet ikke tager tilbage (memory 5/10);
  - den globale `REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC` fjerner PUBLIC's EXECUTE på funktioner, hvis rettighed var
    standarden.

  Øvelsen viste den anden vej: efter restore og `db-rls.sql` manglede PUBLIC EXECUTE på 16 funktioner i `public`.
  Derfor afstemmer `fortryd-b` som `15-undo-data.sh` (`apply_schema_default_acl` og `reconcile_grants` i `lib.zsh`)
  og sammenligner bagefter hele ACL-fingeraftrykket.

  Restorens 4 fejl og 1 advarsel er den kendte klasse: `current_rolle()` og `media_object_synlig_anon(text)` kan ikke
  droppes, fordi RLS-politikker afhænger af dem, og findes derfor allerede. B ændrer ingen funktioner, så det er
  uden betydning her.
- **Efter 6c's runner:** fortolkningerne refererer personaerne og er append-only. B kan ikke længere fortrydes;
  vinduet lukker, når runneren skriver. Det er en bevidst grænse. `fortryd-b` stopper på `T6B_VINDUE_BRUDT`, når
  runnerens batches findes.
- **Efter C, før promotion** (runbookens C-del, Task 15):
  - `public.red_reverse_reimport_publication` (autorisation med `red_authorize_reimport_reversal`) sætter C's
    identiteter til `superseded` (version 2). De 8 eksisterende er urørte;
  - personaerne går **ikke** tilbage i C-køen. En ny C-kørsel dør på `EVIDENCE_IDENTITY_VERSION_CONFLICT`, fordi C
    kræver identitetsversion 0;
  - de afgøres i den menneskelige webkø.
- **Efter promotion:** 6c's fortrydelse gælder.

## Manifestets etiketter (spec §4.6)

| Etiket | Antal | Betydning |
|---|---|---|
| element (B skriver en persona) | 555 | 553 nye, ikke-staged + 2 bundne `staged` |
| `staged_ikke_offentlig` | 2 | Elementer, hvis person er `staged`. De får persona i B; etiketten gælder C (ingen modeldata) |
| `allerede_persona` | 8 | De 8 eksisterende (v50); ingen element |
| `ingen_postbinding` | 21 | Helpost uden publiceret binding |
| `ingen_helpost` | 8 | Records uden helpost |
| `ingen_bundet_narrativ` | 13 | Kilde 3-personer uden publiceret narrativbinding |
| `helpost_uegnet` | **SKAL være 0** | Helpost, som writeren ville afvise |
| `binding_uegnet` | **SKAL være 0** | Binding, som writeren ville afvise |

`[NY]`-klassifikationen findes ikke i basen. Den står kun i C0's beslutningsdokument, ikke i en kolonne. Derfor får
alle 21 ubundne helposter `ingen_postbinding`. Fordelingen 16 `[NY]` (C's `opret_benet`, B4) og 5 andre
(`c3_uafklaret`) kommer fra #160's nøgleliste, ikke fra manifestet. De 2 `samme_som` mellem kilde 3-personer
vises først i C's kontrolrapport.

## Til den senere C-ceremoni (noter; Task 15 skriver forløbet)

- Kandidatinputtet eksporteres med årstalsreserven:
  `psql -v year_fallback=date_raw-v1 -f packages/identity-candidates/sql/export-input.sql`. CLI'en har intet
  `--year-fallback`-flag; reserven bæres i `input_spec`.
- `--candidates-sha256` til `publication_identity_sheet.py manifest` hentes fra **samme** kandidatkørsel som
  `--control`. Værktøjet binder dem ikke til hinanden. En blanding fejler lukket (`PUBLICATION_IDENTITY_RUN_STALE`),
  men først ved apply.
- `controlMargin = 0.05` er foreløbig (Task 10: mindste fejlfri værdi plus ét trin; forkerte bindinger stopper alle
  før marginen). Kalibreringens andet ben køres i Task 15 på stand-in'en efter 6c's runner med
  `packages/identity-candidates/scripts/calibrate-publication-control.sh`.
- `T6B_DEFACL` skal være 0/0/0 før C, se skridt 1.

## Øvelse (2026-10-31)

Stand-in'en er en kopi af `daa5ab_ddl_standin_20261030210000_6am2` (`createdb -T`), 6a's slutøvelses-base. Den er
målt prod-ækvivalent efter 6a (`T6A_MAAL` `k3` 912/584/687/225, tilstand `b`). Et nyt prod-dump ville kræve GO.
Mekanikken er derfor øvet, men redaktionelle prod-skrivninger efter 2026-10-30 er ikke med. Skridt 6
(`MANIFEST_SOM_OEVET`) fanger dem.

Kopien har ICU (`datlocprovider=i`, `en-US`) som prod. `createdb -T` kopierer ikke `ALTER DATABASE … SET`, så
`statement_timeout='2min'` er sat på kopien og kontrolleret fra runnerens forbindelse (`2min`). Planner-statistikken
følger med kopien; `ANALYZE` tog 0,5 s.

- **Første gennemløb (`daa5ab_ddl_standin_20261031160908_6b1`) fandt tre fejl i runneren, alle rettet:**
  - R evaluerer argumenter dovent: autorisationen blev committet inde i kædens transaktion (`Nested transactions
    not supported`). Den tvinges nu før transaktionen;
  - kontrolforespørgslen kaldte `record_helpost_observation` for alle kilde 3-records og fik
    `RECORD_HELPOST_AMBIGUOUS`. Det skete efter B's commit; `maal` gav `b`, præcis som stoppunkt-tabellen siger. Den
    bruger nu `record_helpost_status`;
  - `fortryd-b` med kun `db-rls.sql` gav `T6B_FORTRYD_ACL`: 16 funktioner manglede PUBLIC EXECUTE. Den afstemmer nu
    default-rettigheder og grants (se Fortrydelse).
- **Slutøvelsen (`daa5ab_ddl_standin_20261031162004_6b2`)** med den rettede runner, fra ende til anden, på
  worktree-commit `9e8560a2` (PR 2's gren, før merge):

| Skridt | Resultat |
|---|---|
| `maal` | `foer`; `personas_k3=8 identiteter_k3=8 afventer=0`, `k1_personas=832 k1_identiteter=832 k1_hash=906c2a4d…`; `T6B_DEFACL` 0/0/0 |
| `go-a` → `apply-a` uden dump | `STOPPORT: DUMP_6B_MANGLER` |
| `dump` | `DUMP_6B_OK tilstand=foer` (15.292.845 bytes, 1,7 s), `EKSTERN_6B_OK … rundtur=ok` |
| `apply-a` med forkert kode | `STOPPORT: GO_MISMATCH` |
| `apply-a` | `B1_6B_OK`; `T6B_APPLY_A_OK tilstand=a personas_k3=8 identiteter_k3=8 afventer=0`, `k1` uændret, 0,2 s |
| `maal` | `a`; `T6A_MAAL` uændret (12/2/t, 912/584/687/225/1, `k1_hash=2c530d0a…`) |
| `manifest` × 2 | `T6B_MANIFEST_OK elementer=555`, etiketterne som i tabellen ovenfor, `indhold=36dfa4229cec847a`, ens fil (`842f9c80…`) i begge bygninger; 0,9 s |
| `go-b` → `apply-b` med dumpet fra tilstand `foer` | `STOPPORT: DUMP_6B_TILSTAND` |
| `dump` → `apply-b` | `DUMP_6B_OK tilstand=a`; `T6B_B_DRYRUN status=finalized` (2,3 s); `T6B_B_KONTROL personas=555 primary_i_egen_helpost=555 helposter=555 identiteter=0 afventer=555 records_med_to_personas=0 personas_k3=563`; `T6B_B_PUBSTATE n=563 uaendret=TRUE`; `T6B_B_KOE foer=8 efter=8 nye_i_koeen=0`; `T6B_B_REPLAY already_applied samme_batch=TRUE`; `T6B_APPLY_B_OK personas=555 identiteter=0 status=finalized sekunder=2.4 inkl_dryrun=5.6` |
| `maal` | `b`; `personas_k3=563 identiteter_k3=8 afventer=555`, `k1` uændret |
| `apply-b` igen | `STOPPORT: T6B_FOER_B` (fik `b`) |
| `go-fortryd` → `fortryd-b` med forkert kode | `STOPPORT: GO_MISMATCH` |
| `fortryd-b` | `T6B_FORTRYD_B_OK tilstand=a …`, `k1` uændret, `restore_fejl=5` (den kendte klasse), `grants_afstemt=0\|16` (16 × PUBLIC EXECUTE givet tilbage), `acl=som_foer`; restore 2,8 s, efterarbejde 1,3 s |
| efterprøvning (uden for runneren) | restore-hashen over private+public (`transfer_restore_hash.sql`) er den samme som i tilstand `a` før B (`f674c4ab…`); hele ACL-fingeraftrykket (grants og default-rettigheder) er ens med tilstand `a`; 144 fremmednøgler før og efter; `T6A_MAAL` uændret |
| `maal` | `a` |
| `apply-b` igen (samme manifest, samme dump) | `T6B_APPLY_B_OK personas=555 identiteter=0 … sekunder=2.2 inkl_dryrun=5.2`, alle kontroller som første gang; ny batch-id |
| `maal` | `b`, `k1` uændret |

`T6B_DEFACL` var 0/0/0 i alle tilstande. Den eneste globale default-rettighed i stand-in'en er ejerens egen
(`REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC`), ingen til `authenticated`. Prods egen værdi læses i skridt 1.

De dekrypterede rundtur-kopier blev slettet efter kontrollen; dumpene og `.age` blev liggende.

## Efter ceremonierne

- `docs/evidensbaseret-genimport/status.md`: 1939's »Identitet«: personas i prod, identiteten venter på 6c's runner
  (Task 14 step 4).
- `docs/database-current-state.md` og `docs/changelog.md`.
