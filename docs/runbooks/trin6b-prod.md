# Runbook — trin 6b i prod: ceremoni A (DDL) og B (1939's personas)

Spec: `docs/superpowers/specs/2026-10-31-trin6b-identitet-design.md` §4.1-§4.2, §4.6, §6 og §7. Plan:
`docs/superpowers/plans/2026-10-31-trin6b-identitet.md` Task 13 og 14. Ceremoni C (identiteterne) er blokeret,
indtil 6c's runner har kørt i prod; runbooken udvides med C i Task 15.

- **Ceremoni A** lægger trin 6b's DDL i prod: blokken fra `-- ===== trin 6b: publication-operationer =====` til
  slutningen af `db-migrations.sql` og derefter `db-rls.sql`, i én transaktion. A er additiv:
  - 18 nye funktioner, heraf 5 `public.red_*`, som `authenticated` kan kalde: de to elementoperationer
    `red_apply_reimport_publication_persona` og `red_apply_reimport_publication_identity`, kontrollen
    `red_publication_control` og `red_publication_control_details` samt C's fortrydelse
    `red_reverse_reimport_publication`. Den 18. er `private.require_publication_identity_finalized`, funktionen bag
    constraint-triggeren `trg_reimport_event_publication_identity_finalized` (på `private.reimport_event`, udskudt til
    commit; afviser apply uden finalize med `PUBLICATION_IDENTITY_UNFINALIZED`);
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
  afviser dem. Det samme gælder igen efter en fortrydelse af C, indtil C er kørt igen.

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
- **Vindue og skrivepause.** Pausen går fra dumpet i skridt 3 til B er godkendt (skridt 11), som i 6a. I den tid
  skrives der intet i prod's `public`/`private`: hverken redaktionelt, af medlemmer (bogmærker, `feed_pin`, nye
  tilmeldinger, som giver en `profiles`-række) eller af andre værktøjer. Både A's restore-alternativ (dumpet fra
  skridt 3) og B's fortrydelse (dumpet fra skridt 8) afhænger af pausen. Projektejeren er den eneste aktive redaktør;
  meld det, hvis andre er aktive. Medlemsskrivninger kan ikke stoppes; de opdages af vagten nedenfor.
  - Pausen er fortrydelsens grænse. En restore af dumpet sletter alt, der er skrevet efter det. `fortryd-b` stopper
    derfor **før** restoren (`T6B_VINDUE_BRUDT`), hvis en tabel i `public`/`private` har ændret indhold siden dumpet,
    ud over de rækker B selv skriver. Vagten er generel: et rækkeaftryk pr. tabel og sekvensernes stand
    (`~/.private/5ab-overfoersel/26-trin6b-vindue.sql`, bundet i GO), taget ved dumpet og igen før restoren. Den kender
    ingen tidsstempler og intet ur. Kun `private.reimport_event_id_seq` sammenlignes ikke før restoren, fordi B selv
    flytter den (dry-run og apply; sekvenser rulles ikke tilbage); i dumpets sandwich er den med. `k1` sammenlignes
    desuden med værdien fra dumpet.
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
   - `transfer_catalog_fingerprint.sql`, `transfer_restore_hash.sql` og `transfer_restore_preconditions.sql`
     (fortrydelsens mål);
   - de private filer: runneren, R-scriptet, vindues-SQL'en, `lib.zsh`, `koer.zsh` og `rollback-preflight.sql`.

   B's kode binder desuden `publication_persona_manifest.sql` og manifestet.
3. `dump` → `DUMP_6B_OK tilstand=foer …` og `EKSTERN_6B_OK … rundtur=ok`. Det er B1: en `age`-krypteret kopi lægges
   på SFTP-serveren, hentes tilbage, sammenlignes og dekrypteres. Den dekrypterede rundtur-kopi slettes efter
   kontrollen. Kvitteringen bærer basens tilstand og dumpets starttid (serverens ur). `apply-a` kræver `foer`.
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
8. `dump` igen → `DUMP_6B_OK tilstand=a …`, `DUMP_6B_MAAL_OK vindue=… tabeller=98 restore_hash=… katalog=…
   foraeldreloese=0 …` og `DAA_T6B_DUMP_A=…`. Det er fortrydelsens dump.
   - I tilstand `a` tager `dump` også fortrydelsens mål og lægger dem i kvitteringen (`<dump>.maal/`): grants og
     default-rettigheder, katalogfingeraftrykket, restore-hashen, antal forældreløse rækker (skal være 0, ellers
     `DUMP_6B_FORAELDRELOESE`) og `k1`. Fortrydelsen afstemmer mod netop disse, aldrig mod en måling taget ved sin
     egen start.
   - Vinduets aftryk tages før dumpet og efter målingerne. Er de forskellige, er der skrevet imens, og skridtet
     stopper (`DUMP_6B_SKREVET_UNDER_DUMP`); tag dumpet igen.
   - `apply-b` kræver et dump i tilstand `a`, hvis `start_utc` højst er 12 timer gammel. Ellers stopper den med
     `DUMP_6B_TILSTAND`, `DUMP_6B_MANGLER` eller `DUMP_6B_FOR_GAMMELT`.
9. `apply-b --jeg-mener-det --go <kode>` →
   - `B1_6B_OK …`;
   - målingen før skal være `a`;
   - `26-trin6b-b.R` kører dry-run, authorize (som `service_role`), apply og replay:
     - `T6B_B_DRYRUN status=finalized`;
     - `T6B_B_COMMITTED status=finalized`: B er committet. Alle senere fejl er efter commit;
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
| Dump i tilstand `a`: fortrydelsens mål (vindue × 2, ACL, katalog, restore-hash, forældreløse, `maal`) | 4,9 s | ca. 4-5 min | nej (restore-hashen er én sætning, ca. 2 min; kører med 15 min) |
| A: blokken + `db-rls.sql` | 0,2 s | ca. 10-15 s | nej (mange) |
| Manifestet (`publication_persona_manifest.sql`) | 0,9-1,0 s | ca. 50-55 s | **ja** |
| B: dry-run | 2,2-2,3 s | ca. 2 min | nej (ét kald pr. element) |
| B: apply + finalize | 2,2-2,4 s | ca. 2 min | nej |
| B: kontrolforespørgslen (`T6B_B_KONTROL`) | 0,8 s | ca. 45 s | **ja** |
| B: `narrative_publication_state` over 563 (to gange) | 0,3 s | ca. 17 s | **ja** |
| B i alt (`inkl_dryrun`) | 5,2-5,6 s | ca. 5 min | — |
| Fortrydelsen: vinduets aftryk før restoren | 2,3 s | ca. 2 min | nej (én sætning pr. tabel; 15 min) |
| Fortrydelsen: restore af private+public | 2,8-3,0 s | minutter | nej (arkivet sætter `statement_timeout = 0`) |
| Fortrydelsen: efterarbejde og efterkontroller | 3,8-4,4 s | ca. 4 min | restore-hash og ANALYZE kører med 15 min |

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
| `dump` i tilstand `a` (`DUMP_6B_SKREVET_UNDER_DUMP`, `DUMP_6B_FORAELDRELOESE`, `DUMP_6B_TILSTAND_SKIFTEDE`) | `a`; læse-kun | Ingen gyldig kvittering. Find skriveren / de forældreløse rækker; tag `dump` igen |
| B før apply-commit (fejl i dry-run, authorize eller apply; ingen `T6B_B_COMMITTED`-linje) | `a`; batchen rullet tilbage | Læs koden: `T6B_B_FEJL (<kode>; sidste trin: …)` og den fulde fejllinje (`Fejl:`/`Error:`/`!`) i `apply-b-*.out`; ret; `apply-b` igen med samme GO. Dumpet i tilstand `a` gælder i 12 timer fra `start_utc`; derefter et nyt `dump` |
| Efter B's commit: `T6B_B_FEJL_EFTER_COMMIT`, `T6B_B_KONTROL_AFVIGER`, `T6B_B_PUBSTATE_AENDRET`, `T6B_B_KOE_VISER_NYE`, `T6B_B_REPLAY_STATUS`, `T6B_EFTER_B`, `T6B_K1_UAENDRET` | batchen `finalized` | Kør `maal`. Er den `b` og `k1` uændret, er B skrevet; undersøg kontrolfejlen bagefter. Viser kontrollen, at B skrev forkert, eller er `k1` ændret: **fortrydelsestilfælde**, `fortryd-b` (nedenfor). `fortryd-b` accepterer rå tilstand `b` også med afvigende tal (fx `afventer≠555`, hvor `maal` siger `ukendt`) |
| `fortryd-b` før markøren (`GO_MISMATCH`, `T6B_FORTRYD_ANDET_DUMP`, `T6B_FORTRYD_MAAL_MANGLER`/`_AENDRET`, kvitterings- og ekstern-kontrollen (`DUMP_6B_TILSTAND`, `DUMP_AENDRET`, `B1_EKSTERN_BYTES`, `B1_EKSTERN_SHA`, `SFTP_FEJL`), `T6B_FORTRYD_C`, `T6B_FORTRYD_TILSTAND`, `T6B_K1_AENDRET_I_VINDUET`, `T6B_VINDUE`-fejl, `RESTORE_PRIVILEGES`, `T6B_FORTRYD_LAAS`, `T6B_FORTRYD_MAALING`) | uændret; intet skrevet. Ved en genoptagelse (beslutning 3 eller genstart) står markøren uændret | `T6B_FORTRYD_LAAS`: en anden session holder en lås i public/private eller står »idle in transaction«; vent, og kør igen. `T6B_FORTRYD_ANDET_DUMP`: en påbegyndt fortrydelse af et andet dump findes; gennemfør den først. `T6B_FORTRYD_MAAL_MANGLER`: kvitteringen er i et ældre format eller uden mål |
| `fortryd-b`: `T6B_VINDUE_BRUDT` | uændret (`b`); intet skrevet, ingen markør | Der er skrevet i prod efter dumpet (tabeller/sekvenser i `vindue-afvigende-tabeller.txt`). En restore ville slette det skrevne, og runneren har ingen vej forbi. Projektejeren afgør skrivningen: kan den undværes eller genskrives, eller skal B rettes på anden vis? En fortrydelse, der accepterer tabet, kræver en ændret runner/vindue-SQL og dermed en ny `go-fortryd`. Kør ikke `fortryd-b` igen i håb om et andet udfald |
| `fortryd-b` efter markøren, før `pg_restore` (`T6B_FORTRYD_IGANG` gælder ikke her; `transfer_acl_fingerprint.sql fejlede`, `SCHEMA_DEFAULT_ACL`, `T6B_MARKOER_OMDOEB` ved række 1) | markøren har trin `restore_startet` og vinduet før restoren; skema-defaults kan være ryddet | Kør `fortryd-b` igen. Er markøren fra en **frisk** kørsel (rå `b`, vinduet som før restoren), er det beslutning 1: markøren lægges til side (`.forladt-…`) og den normale vej køres. En afbrudt **genoptaget** restore (beslutning 3) har nulstillet den gemte hash, og basen er ikke rå `b`: det ender i række 4 (`T6B_FORTRYD_UKLAR`) |
| `fortryd-b` under/efter `pg_restore` (`T6B_FORTRYD_RESTORE_FEJL`, `T6B_RESTORE_FEJL_VURDERING` (markøren står på `restore_startet`: række 4), `T6B_FORTRYD_MAALING_EFTER_RESTORE`, `T6B_MARKOER_SKRIV`, fejl i diffen efter `RESTORE_FEJL`) | markøren har trin `restore_afsluttet` (fejlmængden eller exitstatus ikke godkendt; restore-hashen efter er gemt) eller stadig `restore_startet` (hashen efter kunne ikke måles) | Ved `T6B_FORTRYD_RESTORE_FEJL` udskrives `T6B_FORTRYD_DIFF` (antal grants og katalogobjekter, der mangler/er ekstra; objektnavne i `katalog-afvigende-objekter.txt`). Ret årsagen, eller acceptér en ny, forstået fejlklasse ved at udvide mønsteret i runneren (ny `go-fortryd`). Kør så `fortryd-b` igen: beslutning 3 restorer igen, hvis basen står, som den afbrudte restore efterlod den; ellers beslutning 4 |
| `fortryd-b` efter godkendt restore (`T6B_FORTRYD_ANALYZE`/`_RLS`/`_NOTIFY`, `GRANTS_RECONCILE`, `SCHEMA_DEFAULT_ACL` i genskabelsen, `T6B_FORTRYD_ACL`/`_DEFAULT_ACL`/`_KATALOG`/`_FORAELDRELOESE`/`_RESTORE_HASH`, `T6B_EFTER_FORTRYD`, `T6B_K1_UAENDRET`, `T6B_MARKOER_OMDOEB`) | markøren har trin `restore_godkendt` med restore-hashen efter | Ret årsagen, og kør `fortryd-b` igen. Er restore-hashen dumpets, giver det beslutning 2 (kun efterarbejde). Er den ikke dumpets, men den gemte, giver det beslutning 3; ellers beslutning 4 |
| `fortryd-b` ved genoptagelse: `T6B_FORTRYD_UKLAR` (beslutning 4) | markøren findes; intet er restoret i denne kørsel | Ingen af beslutningstabellens rækker 1-3 passer, eller en måling fejlede. `T6B_FORTRYD_UKLAR_DIFF` viser trinnet, antal vindueslinjer, der afviger fra dumpet, og om restore-hashen er dumpets eller den gemte. Typisk er der skrevet efter en afbrudt restore. Projektejeren afgør skrivningen. Den eneste udgang er `go-fortryd --genstart-restore` → `GO 6b-fortryd-B-genstart <kode>` → `fortryd-b --jeg-mener-det --go <kode> --genstart-restore`. Det er en bevidst accept af, at alt skrevet siden dumpet slettes |
| `dump`, `apply-a`, `apply-b`, `manifest`, `go-a`, `go-b` med en markør: `T6B_FORTRYD_IGANG` | uændret | En fortrydelse er påbegyndt og ikke gennemført. Gennemfør `fortryd-b` først (`maal`, `go-fortryd` og `fortryd-b` er tilladt) |
| `apply-b`: `T6B_FORTRYD_MAAL_MANGLER`/`_AENDRET` | `a`; intet skrevet | Kvitteringen fra skridt 8 har ikke gyldige fortrydelsesmål (ældre format, eller filerne er ændret). B køres ikke uden en mulig fortrydelse: tag `dump` igen i tilstand `a`, og tag `go-b` igen |
| Målingens egne fejl (`maal_trin6b.sql fejlede`, `T6B_MAAL_FORM`, `MAAL_6B_UKENDT`) | uændret af fejlen selv | Efter et commit: læs batchens status og kør `maal` igen; før et commit: intet er skrevet |

`GO_MISMATCH` viser den kode, filerne svarer til nu (lib's `expect_eq`, som i 6a). Koden binder indhold og er ikke en
hemmelighed. Brug den ikke uden at have tjekket, hvad der er ændret siden GO.

## Fortrydelse pr. fase (spec §6)

- **Ceremoni A:** de tidligere funktionskroppe fra dumpet fra skridt 3. Det er ikke scriptet og ikke øvet; det
  bygges kun, hvis det bliver nødvendigt. Det kræver:
  - drop triggeren `trg_reimport_event_publication_identity_finalized` på `private.reimport_event` **først**, og derefter
    de 18 nye funktioner (funktionen kan ikke droppes, så længe triggeren afhænger af den);
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
     - kontrollerer dumpet, den eksterne kopi (`B1_6B_OK`) og kvitteringens før-mål;
     - kræver rå tilstand `b` (`T6B_FORTRYD_TILSTAND`). Tilstand `c` stopper med `T6B_FORTRYD_C`;
     - kræver, at `k1` er dumpets (`T6B_K1_AENDRET_I_VINDUET`), og at vinduets aftryk er dumpets
       (`T6B_VINDUE_BRUDT`). Begge tjekkes før restoren;
     - kræver, at forbindelsens bruger ejer alt i private+public (`RESTORE_PRIVILEGES`), og at ingen anden session
       holder en lås i public/private eller står »idle in transaction« (`T6B_FORTRYD_LAAS`);
     - sætter markøren `fortryd-b-<dump-sha>.igang` (trin `restore_startet`, med vinduet lige før restoren) og
       fjerner rollens skema-defaults;
     - kører `pg_restore --clean --if-exists --no-owner --schema=private --schema=public` i runneren selv, med
       exitstatus;
     - vurderer restoren efter mønster, snævert. Godkendt er kun:
       - exitstatus 0 uden fejllinjer;
       - exitstatus 1 med netop »cannot drop function … because other objects depend on it« og »function … already
         exists with same argument types« for præcis `public.current_rolle()` og
         `public.media_object_synlig_anon(text)`, hver højst én gang, og pg_restore's afsluttende advarsel med det
         rigtige antal.

       Prods restore som `postgres` kan dermed gennemføre i én kørsel, hvis kun disse klasser optræder;
     - måler restore-hashen efter restoren (tre forsøg; ellers `T6B_FORTRYD_MAALING_EFTER_RESTORE`, og markøren
       står på `restore_startet`) og skriver den i markøren med trin `restore_godkendt` eller, ved alt andet, med trin
       `restore_afsluttet` og `T6B_FORTRYD_RESTORE_FEJL`;
     - genskaber skema-defaults fra kvitteringens mål;
     - kører ANALYZE og `db-rls.sql`;
     - afstemmer grants mod kvitteringens mål;
     - sender `NOTIFY pgrst`;
     - kontrollerer bagefter mod kvitteringen, som `15-undo-data.sh`:
       - grants og default-rettigheder;
       - kataloget;
       - 0 forældreløse rækker;
       - restore-hashen;
       - målingen er `a`, og `k1` er uændret.

     Kvitteringen er `T6B_FORTRYD_B_OK … beslutning=ny vej=restore genoptaget=0 restore_fejl=5
     grants_afstemt=<tilbagekaldt>|<givet> acl=som_dump katalog=som_dump restore_hash=…`. Markøren omdøbes til
     `.fuldfoert-…`.
  3. `maal` → `a`. B kan derefter køres igen fra skridt 9 med samme manifest og samme dump (ny batch), hvis dumpets
     `start_utc` højst er 12 timer gammel. Ellers tages et nyt `dump` i tilstand `a` (nu efter restoren), og
     `go-b` tages igen. **En ændret runner ændrer alle GO-koder:** er runneren (eller vindues-SQL'en) ændret, fx for
     at acceptere en ny fejlklasse, kræver både en ny `apply-b` og en ny `fortryd-b` et nyt `go-b`/`go-fortryd`,
     også med samme dump.

  **Genoptagelse: en lukket beslutningstabel.** Findes markøren for dette dump, når `fortryd-b` starter, vælges
  præcis én række, i denne rækkefølge. En markør for et andet dump afvises (`T6B_FORTRYD_ANDET_DUMP`, også i
  `go-fortryd`).

  | # | Betingelse | Handling |
  |---|---|---|
  | 1 | rå `maal` = `b`, og vinduet nu = vinduet gemt i markøren lige før restoren | Intet er restoret. Markøren lægges til side (`.forladt-…`), og den normale vej køres fra start med `k1`- og vinduesvagterne (`beslutning=1`) |
  | 2 | trin `restore_godkendt`, og restore-hashen nu = dumpets | Kun efterarbejde (`beslutning=2 vej=efterarbejde`) |
  | 3 | der er gemt en restore-hash efter restoren, og restore-hashen nu = den gemte | Restore igen fra samme dump. Markøren nulstilles **før** `pg_restore` til `restore_startet` med et nyt før-vindue (`beslutning=3`) |
  | 4 | alt andet, også enhver måling, der fejler (restore-hashen eller vinduet) | `STOPPORT: T6B_FORTRYD_UKLAR` med `T6B_FORTRYD_UKLAR_DIFF` (kun antal og flag), og **ingen** restore |

  Udgangen fra række 4 er et eksplicit flag. `go-fortryd --genstart-restore` giver en anden GO-kode
  (`GO_6B_FORTRYD_B_GENSTART_KODE`), som binder flaget. `fortryd-b --jeg-mener-det --go <kode> --genstart-restore`
  restorer igen uanset tilstand (`beslutning=genstart`), og flaget accepteres kun, når en markør findes. **Det er
  operatørens bevidste accept af, at alt skrevet i prod siden dumpet slettes.** Det er også udgangen, når en
  skrivning efter en afbrudt restore skal opgives. Uden flaget er der ingen vej forbi række 4.

  Markøren omdøbes til `.fuldfoert-…`, først når alle efterkontroller er bestået. Mislykkes omdøbningen, stopper
  runneren (`T6B_MARKOER_OMDOEB`). Mens markøren findes, afviser `dump`, `apply-a`, `apply-b`, `manifest`, `go-a` og
  `go-b` at køre (`T6B_FORTRYD_IGANG`).

  I hullet mellem `pg_restore`'s drop-fase og dens afsluttende ACL-pas har anon, authenticated og service_role ingen
  grants på genskabte objekter, fordi skema-defaults er ryddet før restoren. Appen kan derfor ikke skrive i det hul,
  men privilegerede sessioner kan. Genoptag i skrivepausen.

  **Tidsgrænser og låse under restoren.** pg_restore sender selv `statement_timeout = 0`, `lock_timeout = 0`,
  `idle_in_transaction_session_timeout = 0` og `transaction_timeout = 0` på sin forbindelse. Prods
  2-minuttersgrænse annullerer den derfor ikke, og en `lock_timeout` fra miljøet virker ikke.
  - Holder en anden session en lås, venter restoren **uden grænse**. I øvelsen ventede den 39,7 s bag en lås på 45 s
    og blev derefter korrekt. Det samme gælder alle forespørgsler i låsekøen bag den.
  - Derfor stopper `fortryd-b` før restoren på `T6B_FORTRYD_LAAS`. En lås, der tages mellem kontrollen og restoren,
    kan stadig holde den. Står `fortryd-b` stille i restoren, ser operatøren i `pg_stat_activity` (kun pid,
    `wait_event_type` og `state`) og afbryder den blokerende session eller restorens backend med
    `pg_terminate_backend`. pg_restore afslutter da med exitstatus ≠ 0, runneren lever og måler, og markøren går til
    `restore_afsluttet` (beslutning 3). `pg_cancel_backend` afbryder **ikke** restoren; den springer kun den blokerede
    sætning over, og pg_restore fortsætter. **Tryk ikke Ctrl-C på runneren:** det dræber hele procesgruppen, også
    runneren, så markøren står på `restore_startet` uden efter-hash (række 4, en genstart-GO). Dræb heller ikke
    pg_restore-processen alene uden at afslutte backenden: en forældreløs backend kan blive i låsekøen, og så kan
    målingen efter restoren løbe ind i sine 15 minutter (række 4). En afbrudt restore er
    en delvis restore, og beslutningstabellen ovenfor gælder.
  - En delvis restore kan også komme af forbindelsestab, `kill` eller deadlock. Deadlock er mulig, fordi en
    `DROP TABLE` også låser den refererede tabel. Fejlmængden fanger det (`T6B_FORTRYD_RESTORE_FEJL`), og
    genoptagelsen kører restoren igen.
  - I prod kan `pg_stat_activity.state` være NULL for andre rollers sessioner, hvis `postgres` ikke har
    `pg_read_all_stats`. Så tæller idle-in-transaction-delen for lavt, mens låsedelen (`pg_locks`) fanger de sessioner,
    der faktisk holder relationslåse. Efterprøv rollen i prod.

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
  vinduet lukker, når runneren skriver. Det er en bevidst grænse. `fortryd-b` stopper på `T6B_VINDUE_BRUDT`, fordi
  runnerens rækker ændrer aftrykket.
- **Efter C, før promotion** (runbookens C-del, Task 15):
  - `public.red_reverse_reimport_publication` (autorisation med `red_authorize_reimport_reversal`) sætter C's
    identiteter til `superseded` (version 2 efter den første C). De 8 eksisterende er urørte;
  - **C kan køres igen** (projektejeren 2026-10-31, `docs/decisions.md`). En fortrudt publikationsidentitet tæller
    som ingen identitet: personaerne venter igen på kontrol (skjult i webkøen, `red_afgoer_source_persona` afviser
    med `IDENTITY_AWAITING_PUBLICATION_CONTROL`), indtil en ny C er finaliseret, eller et menneske har afgjort dem;
  - den nye C bygges som den første: `red_publication_control` (samme eller ny kandidatkørsel) giver for hver persona
    den aktuelle `identity_version` (fx 2) og `identity_reverted=true`, kortenes P-linjer bærer den version, og
    manifestet sætter `expected_identity_version` til den. Over samme kørsel er stikprøven den samme som før
    fortrydelsen. Writeren godtager en version ≠ 0 kun for en fortrudt publikationsidentitet; ellers
    `EVIDENCE_IDENTITY_VERSION_CONFLICT`;
  - en persona, som et menneske har afgjort efter fortrydelsen, er ikke længere fortrudt. Den er disposition
    `allerede_persona` i manifestet, C afviser den med `EVIDENCE_IDENTITY_VERSION_CONFLICT`, og finalize kræver den
    ikke;
  - en C, der er kørt igen, kan fortrydes igen (version 4 osv.).
- **Efter promotion:** 6c's fortrydelse gælder.

**Kendte begrænsninger i fortrydelsen**

- **6c's runner skal respektere `fortryd-b-*.igang`.** Markøren spærrer kun i `26-trin6b.sh`. En runner, der skriver
  under en påbegyndt fortrydelse, ville ændre basen bag beslutningstabellen. Den ender så i række 4 (fejlsikkert),
  men kun hvis den ændring også flytter restore-hashen.
- **Et gentaget `apply-b` efter en tilbagerulning** (fejl før commit) flytter `reimport_event_id_seq`. Det er
  undtaget i vinduet. Bruger fejlvejen også andre sekvenser, giver en senere `fortryd-b` `T6B_VINDUE_BRUDT`.
  Det er fejlsikkert (stop før restoren); afgør det som ved enhver vinduesfejl.

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
- C's apply og finalize SKAL ligge i **én** transaktion. Databasen håndhæver det: en apply uden finalize i samme
  transaktion afvises ved commit med `PUBLICATION_IDENTITY_UNFINALIZED`.
- Writerne kræver `READ COMMITTED` (`PUBLICATION_PERSONA_ISOLATION` for B, `PUBLICATION_IDENTITY_ISOLATION` for C),
  så kandidatlåsen og aktualitetskontrollen ser en frisk læsning. Runneren må ikke åbne transaktionen med et andet
  isolationsniveau.
- Finalize kræver, at C's personamængde er lig B's kontrolmængde (`PUBLICATION_IDENTITY_SET_MISMATCH`). Staged
  aflæses fra B-hændelsens person, mens manifestet bruger den aktuelle binding; en afvigelse giver derfor
  `SET_MISMATCH`. At den er fraværende, skal bevises i C-øvelsen på stand-in'en, før prod.
- En binding, der trækkes tilbage mellem B og C, er disposition `binding_tilbagetrukket` (control: `binding_status='none'`
  og `b_binding_status='withdrawn'`): intet kort, intet element, talt i manifestets output. Personaen afgøres efter C i
  webkøen. Alle andre `none`/uklare tilstande stopper stadig med `PUBLICATION_CONTROL_BINDING_NOT_PUBLISHED`.
- Runneren kører apply og finalize i én READ COMMITTED-transaktion og sætter aldrig `SET CONSTRAINTS ALL IMMEDIATE`.
- Finalize kræver, at stikprøven ligger i C; ellers `PUBLICATION_IDENTITY_SAMPLE_MISMATCH`.
- Fire kald er umålte mod prods 2 minutter og skal måles i Task 15: `red_publication_control`,
  `red_publication_control_details`, C's første `enig`-element (stikprøven beregnes i writer-kaldet) og finalize's
  genberegning af kandidatinputtet. Runneren sætter session-`statement_timeout` for C, som den gør for restore-hashen.
- En tilbagetrækning efter `render` flytter stikprøven (den afhænger af bindingsstatus). Finalize giver så
  `PUBLICATION_IDENTITY_SAMPLE_MISMATCH`; byg et nyt ark.
- Helpost-drift mellem B og C (B-bindingen er stadig `published`, men bindingsopslaget giver `none`) blokerer C:
  personaen kræves af finalize, writeren kan ikke skrive den (`PUBLICATION_IDENTITY_BINDING_DRIFT`), og arket stopper med
  `PUBLICATION_CONTROL_BINDING_NOT_PUBLISHED`. Stop og afgør; det er C's modstykke til `helpost_uegnet`.
- `red_publication_control_details` og arkene rummer navne og leveår på kandidatpersoner, også levende konkurrenter.
  Filerne ligger kun under `~/.private/6b/` og sendes aldrig til en model.
- Efter en fortrydelse af C (se Fortrydelse) bygges arket og manifestet på ny med det nye `red_publication_control`;
  genbrug ikke control-, details- eller manifestfiler fra den fortrudte C, fordi deres versioner er 0.
  `maal_trin6b.sql` tæller igen personaerne som `afventer`.
- `publication_identity_sheet.py` kræver sammenhængende input: `render` og `manifest` tager begge
  `--control` og `--details` fra samme kørsel (`PUBLICATION_SHEET_INPUT_MISMATCH` ved afvigelse i kørsel, kilde,
  persona-mængde eller binding), og begge stopper ved over 90 kort (`PUBLICATION_SHEET_TOO_MANY_CARDS`).

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
| efterprøvning (uden for runneren; siden fix-runde 1 en del af `fortryd-b`) | restore-hashen over private+public (`transfer_restore_hash.sql`) er den samme som i tilstand `a` før B (`f674c4ab…`); hele ACL-fingeraftrykket (grants og default-rettigheder) er ens med tilstand `a`; 144 fremmednøgler før og efter; `T6A_MAAL` uændret |
| `maal` | `a` |
| `apply-b` igen (samme manifest, samme dump) | `T6B_APPLY_B_OK personas=555 identiteter=0 … sekunder=2.2 inkl_dryrun=5.2`, alle kontroller som første gang; ny batch-id |
| `maal` | `b`, `k1` uændret |

`T6B_DEFACL` var 0/0/0 i alle tilstande. Den eneste globale default-rettighed i stand-in'en er ejerens egen
(`REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC`), ingen til `authenticated`. Prods egen værdi læses i skridt 1.

De dekrypterede rundtur-kopier blev slettet efter kontrollen; dumpene og `.age` blev liggende.

### Fix-runde 1 (2026-10-31): genoptagelig fortrydelse og bredere vindue

Reviewet af runneren fandt tre ting:
- `fortryd-b` kunne ikke genoptages, og dens ACL-mål blev taget ved sin egen start;
- restorens fejl blev talt, men stoppede ikke;
- vinduet så kun `change_set` og batches.

Rettelserne:
- før-mål ved `dump` i tilstand `a`;
- markør og genoptagelse;
- accepteret fejlmængde;
- efterkontroller som i `15-undo-data.sh`;
- generelt rækkeaftryk;
- låsekontrol;
- `start_utc` på serverens ur og 12-timersgrænsen regnet derfra;
- `T6B_B_COMMITTED`.

Øvet på samme stand-in, `…_6b2`. Den blev først bragt tilbage til tilstand `a` med samme trin som `fortryd-b`, så der
kunne tages et dump i det nye format. Kontrollen af den nulstilling: restore-hash `f674c4ab…` og ACL-fingeraftryk ens
med tilstand `a`.

Først blev det vist, at vinduesaftrykket er ens i tilstand `a` og `b`: B's egne rækker er de eneste, B ændrer.

| Skridt | Resultat |
|---|---|
| `dump` i `a` | `DUMP_6B_MAAL_OK vindue=02556c2d… tabeller=98 restore_hash=f674c4ab… katalog=61d260d4… foraeldreloese=0`, 4,9 s |
| `apply-b` | `T6B_B_COMMITTED`; alle kontroller som før; `T6B_APPLY_B_OK personas=555 identiteter=0` |
| Ét bogmærke indsat efter dumpet → `fortryd-b` | `STOPPORT: T6B_VINDUE_BRUDT (1 tabeller …)`: `public.bookmark`. Stop før restoren; `maal` stadig `b` |
| Bogmærket fjernet → `fortryd-b` | `T6B_FORTRYD_B_OK … vej=restore genoptaget=0 restore_fejl=5 grants_afstemt=0\|16 acl=som_dump katalog=som_dump restore_hash=f674c4ab…` |
| `apply-b` | `b` |
| Lås i en anden session (mellemversion uden låsekontrol, med `PGOPTIONS` lock_timeout) | Restoren ventede 39,7 s og blev derefter korrekt (`T6B_FORTRYD_B_OK`). Arkivet sætter selv `lock_timeout = 0` og `statement_timeout = 0`. Derfor kom låsekontrollen før restoren |
| `apply-b` → lås i en anden session → `fortryd-b` | `STOPPORT: T6B_FORTRYD_LAAS (fik '1 0')`; intet skrevet, ingen markør; `maal` `b` |
| View uden for public/private, der afhænger af `public.bookmark` → `fortryd-b` | `STOPPORT: T6B_FORTRYD_RESTORE_FEJL (fik '9 ad2f0e7a…', forventede '5 620b9304…')`. Den nye klasse er `cannot drop table public.bookmark because other objects depend on it` og følgefejl. Markøren er sat |
| Afhængigheden fjernet → `fortryd-b` med `DAA_FAULT=t6b_efter_restore` | Genoptagelse: restore-hashen var ikke dumpets, så restoren kørte igen (fejl `5 620b9304…`, accepteret); derefter `STOPPORT: FAULT_INJECTED` før efterarbejdet |
| `fortryd-b` igen | `T6B_FORTRYD_B_OK … vej=efterarbejde genoptaget=1 grants_afstemt=0\|16 acl=som_dump katalog=som_dump restore_hash=f674c4ab…`. De 16 grants, fejlpunktet efterlod uafstemt, er givet tilbage. Markøren er fuldført; ACL lig tilstand `a`, 144 fremmednøgler |
| `apply-b` | `b` |
| Endelig runner: `fortryd-b` → `apply-b` | `T6B_FORTRYD_B_OK … vej=restore genoptaget=0 restore_fejl=5 …`, restore 2,8 s, efterarbejde 3,8 s; derefter `T6B_APPLY_B_OK personas=555 identiteter=0`, `maal` `b` |

`k1_hash` var `906c2a4d…` i alle målinger. Stand-in'en står i tilstand `b`.

### Fix-runde 2 (2026-10-31): genoptagelsen binder restore-trin og vindue

Reviewet af fix-runde 1 fandt fire ting:
- genoptagelsen valgte efterarbejde alene på data-hashen, så en restore, der døde i post-data, aldrig blev kørt
  igen (N1);
- den kunne slette skrivninger efter en fejlet restore (N2);
- fejlporten gjaldt kun første forsøg (N3);
- en hængende markør spærrede ingenting (N4).

Desuden manglede sekvenserne i vinduet (N6), og `apply-b` efterprøvede ikke fortrydelsesmålene (N7).

Rettelserne:
- markøren har trin;
- restore-hash og aftryk efter restoren gemmes;
- fejlmængden vurderes efter mønster;
- en diff udskrives ved fejl;
- markøren spærrer;
- sekvenserne er med i vinduet;
- `apply-b` kræver gyldige fortrydelsesmål.

Øvet på `…_6b2`. Stand-in'en blev først bragt fra `b` til `a` med fix-runde 1's runner, så der kunne tages et dump i
det nye format.

| Skridt | Resultat |
|---|---|
| `dump` i `a` | `DUMP_6B_MAAL_OK vindue=cb019e50… tabeller=132` (98 tabeller + 34 sekvenser) `restore_hash=f674c4ab… katalog=61d260d4… foraeldreloese=0`, 4,6 s |
| `apply-b` → `fortryd-b` (første version) | `STOPPORT: T6B_VINDUE_BRUDT`: `private.reimport_event_id_seq`. B flytter selv sekvensen (7068 → 8178: dry-run + apply). Sekvensen undtages derfor kun i sammenligningen før restoren |
| `fortryd-b` (ren) → `apply-b` | `T6B_FORTRYD_B_OK … vej=restore genoptaget=0 restore_fejl=5 grants_afstemt=0\|16 acl=som_dump katalog=som_dump restore_hash=f674c4ab…`, restore 3,2 s; derefter `T6B_APPLY_B_OK personas=555 identiteter=0` |
| N1, afbrudt efter data-sektionen (`DAA_FAULT=t6b_afbrudt_efter_data`: pre-data + data, ingen post-data) | `STOPPORT: FAULT_INJECTED`; markøren `trin=restore_startet`, intet efter-mål; 47 af 144 fremmednøgler |
| N4, med markøren: `dump`, `go-b`, `apply-b`, `go-a` | alle `STOPPORT: T6B_FORTRYD_IGANG` |
| N1, genoptagelse | `T6B_FORTRYD_B_OK … vej=restore genoptaget=1 restore_fejl=5 … restore_hash=f674c4ab… advarsel=afbrudt_under_restore_uden_efter_maal`; 144 fremmednøgler |
| `apply-b` → N2: view uden for public/private afhænger af `public.bookmark` → `fortryd-b` | `T6B_FORTRYD_DIFF acl_mangler=16 acl_ekstra=0 katalog_mangler=4 katalog_ekstra=0 objekter=2`; `STOPPORT: T6B_FORTRYD_RESTORE_FEJL (… 9 linjer …)`; markøren `trin=restore_afsluttet`, gemt hash `b06e4227…` |
| N2: view fjernet, ét bogmærke skrevet → `fortryd-b` | `STOPPORT: T6B_FORTRYD_SKREVET_EFTER_RESTORE`; ingen restore |
| N2: bogmærket fjernet → `fortryd-b` | `T6B_FORTRYD_B_OK … vej=restore genoptaget=1 restore_fejl=5 … restore_hash=f674c4ab…` |
| `apply-b` → N1 præcist: view afhænger af `public.slaegtsnavn_normaliser(text)` → `fortryd-b` | `T6B_FORTRYD_DIFF acl_mangler=15 … katalog_mangler=0 objekter=0`; `STOPPORT: T6B_FORTRYD_RESTORE_FEJL (… 7 linjer …)`; markøren `trin=restore_afsluttet` med gemt hash **= dumpets** (`f674c4ab…`) |
| N1: afhængigheden fjernet → `fortryd-b` | `vej=restore genoptaget=1` (ikke `efterarbejde`, selv om data var dumpets), `restore_fejl=5`, `T6B_FORTRYD_B_OK` |
| `apply-b` | `T6B_APPLY_B_OK personas=555 identiteter=0`; `maal` `b` |
| N7: `go-fortryd` + `fortryd-b` med de to ældre kvitteringsformater | `STOPPORT: T6B_FORTRYD_MAAL_MANGLER (kvitteringen har ingen fortrydelsesmaal …)` og `(… vinduet uden sekvenser …)`; ingen Python-fejl |

`k1_hash` var `906c2a4d…` i alle målinger. Stand-in'en står i `b`, uden markør og uden hjælpeskema.

Historisk: koden `T6B_FORTRYD_SKREVET_EFTER_RESTORE` og kvitteringsfeltet `advarsel=…` er afløst af beslutningstabellen i
fix-runde 3. Det tilfælde hedder nu række 4, `T6B_FORTRYD_UKLAR`.

### Fix-runde 3 (2026-10-31): genoptagelsen som lukket beslutningstabel

Reviewet af fix-runde 2 fandt følgende:
- et forældet trin ved en genoptaget restore (F1);
- at et tomt efter-mål og en fejl før `pg_restore` slog vagten fra (F2, F3);
- at runbook og kode ikke stemte (F4);
- at pg_restore's exitstatus blev kasseret (F5);
- at en markør for et andet dump blev forældreløs (F6).

Rettelserne:
- beslutningstabellen ovenfor;
- markøren nulstilles før hver restore;
- målefejl bliver STOPPORT;
- pg_restore køres i runneren med exitstatus;
- `--genstart-restore` bundet i GO;
- markører for andre dumps afvises.

Øvet på `…_6b2` (start i `b`, dumpet `85b0826a…` i tilstand `a`):

| Øvelse | Resultat |
|---|---|
| Række 1: `DAA_FAULT=t6b_efter_markoer` (efter markøren, før restoren) | `STOPPORT: FAULT_INJECTED`; markøren `trin=restore_startet` med før-vindue. Genoptaget: `T6B_FORTRYD_B_OK … beslutning=1 vej=restore genoptaget=0 restore_fejl=5 grants_afstemt=0\|16 … restore_hash=f674c4ab…`; markøren `.forladt-…`. Derefter `apply-b` → `b` |
| Række 2: `DAA_FAULT=t6b_efter_restore` (efter godkendt restore) | `STOPPORT: FAULT_INJECTED`; markøren `trin=restore_godkendt`, gemt hash `f674c4ab…`. Genoptaget: `T6B_FORTRYD_B_OK … beslutning=2 vej=efterarbejde genoptaget=1 grants_afstemt=0\|16 …`. Derefter `apply-b` → `b` |
| Række 3 + F5: `DAA_FAULT=t6b_rc_uden_fejl` (fuld restore, men rc 143 og ingen fejllinjer) | `T6B_FORTRYD_DIFF acl_mangler=16 …`; `STOPPORT: T6B_FORTRYD_RESTORE_FEJL (ikke godkendt: 0 linjer, rc=143 …)`; markøren `trin=restore_afsluttet`. Genoptaget: `T6B_FORTRYD_B_OK … beslutning=3 vej=restore genoptaget=1 restore_fejl=5 …`. Derefter `apply-b` → `b` |
| Række 4: som række 3, derefter ét bogmærke skrevet → `fortryd-b` | `T6B_FORTRYD_UKLAR_DIFF trin=restore_afsluttet vindue_linjer_afviger_fra_dump=2 restore_hash_som_dump=0 restore_hash_som_gemt=0`; `STOPPORT: T6B_FORTRYD_UKLAR (…; ingen restore …)` |
| F6: `go-fortryd` bundet til en anden kvittering, mens markøren findes | `STOPPORT: T6B_FORTRYD_ANDET_DUMP` |
| Genstart: `fortryd-b --genstart-restore` med den almindelige kode | `STOPPORT: GO_MISMATCH` |
| `go-fortryd --genstart-restore` → `fortryd-b` uden flaget med genstart-koden | `STOPPORT: GO_MISMATCH` |
| `fortryd-b --genstart-restore` med genstart-koden | `T6B_FORTRYD_B_OK … beslutning=genstart vej=restore genoptaget=1 restore_fejl=5 … restore_hash=f674c4ab…`. Bogmærket fra række 4 er slettet (0 nye), som accepteret |
| `--genstart-restore` uden markør | `FEJL: --genstart-restore kun ved en paabegyndt fortrydelse` |
| `apply-b` | `T6B_APPLY_B_OK personas=555 identiteter=0`; `maal` `b` |

`k1_hash` var `906c2a4d…` i alle målinger. Stand-in'en står i `b` uden markør.

## Efter ceremonierne

- `docs/evidensbaseret-genimport/status.md`: 1939's »Identitet«: personas i prod, identiteten venter på 6c's runner
  (Task 14 step 4).
- `docs/database-current-state.md` og `docs/changelog.md`.
