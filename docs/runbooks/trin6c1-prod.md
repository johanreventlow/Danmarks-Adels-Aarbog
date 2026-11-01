# Runbook — trin 6c-1 i prod: ceremoni A (DDL) og B (1939's forslag)

Spec: `docs/superpowers/specs/2026-11-01-trin6c1-runner-og-identitet-design.md` §4.4, §4.6, §6 og §7. Plan:
`docs/superpowers/plans/2026-11-01-trin6c1-runner-og-identitet.md` Task 10. Ceremoni C (6b's identiteter) følger
`docs/runbooks/trin6b-prod.md`, som 6b-planens Task 15 udvider; den køres først, når B her er i prod.

Kort sagt: **A** gør forslagswriteren i stand til at finde 1939's helpost, og **B** lægger modellens forslag til
1939's ca. 500 poster i prod som private forslag (`proposed`). Ingen læser eller redaktør ser forslagene, før de er
afgjort (6c-2). Ingen kanoniske data (personer, fakta, påstande) ændres.

- **Ceremoni A** lægger trin 6c-1's DDL i prod: blokken fra
  `-- ===== trin 6c-1: forslagswriteren følger helpost-reglen =====` til slutningen af `db-migrations.sql` og derefter
  `db-rls.sql`, i én transaktion med `lock_timeout` 5 s. A er additiv:
  - `private.write_interpretation_proposal` erstattes (helposten vælges med helpost-reglen og profilens helpost-slags
    i stedet for »præcis én forankring«; for 2018-20 er udfaldet identisk);
  - forslagsprofilen `daa-1939-interpretation-proposal-v1` (kilde 3) indsættes i `private.reimport_writer_profile`.
    Det er A's eneste datarække. Målingen er uændret (`foer` → `a` med samme tal).
- **Ceremoni B** skriver 494 elementer med i alt 2.774 forslag (version 1, `proposed`) gennem den generelle writer
  (`interpretation_proposal`) via `execute_reimport` i `apply_reimport_helpers.R`, samme vej som 2018-20's forslag og
  6a's klausuler: dry-run i én transaktion, der rulles tilbage; autorisationen committet for sig som `service_role`;
  apply og finalize i én transaktion; replay med en ny autorisation (`already_applied`). Manifestet er det samme, som
  stand-in'en fik; nøglerne (`interpretation_key`) er deterministiske og indeholder ingen id'er.

Runneren er privat: `~/.private/5ab-overfoersel/27-trin6c1.sh` med `27-trin6c1-b.R`, `27-trin6c1-vindue.sql` og 5c-2's
`lib.zsh`/`koer.zsh`. Projektejeren kører alt, der rører prod, fra egen shell. AI-sessionen læser kun linjer med tal,
koder og hashes.

## Forudsætninger

- PR 1 og PR 2 (#290, #291) er merget. `main` er checket ud rent i `/Users/johanreventlow/TypeScript/danmarksadelsaarbog`
  (runneren læser repo-filerne derfra, og GO-koderne binder commit'en). Den checkout stod ved øvelsen på en anden gren;
  skift til `main` før `go-a`.
- 6b's ceremoni A og B er i prod (database-current-state §18), og der er **ingen påbegyndt 6b-fortrydelse**. Runneren
  stopper enhver handling ud over `maal` med `T6C1_6B_FORTRYD_IGANG`, hvis der findes en `fortryd-b-*.igang` i
  `~/.private/6b/`, i `~/.private/5ab-overfoersel/prod/6b/` (der skriver `26-trin6b.sh` dem) eller i stand-in'ens
  `6b/`-mappe.
- De fire bundne inputfiler fra Task 8 ligger under `~/.private/6c1/` (0700/0600) og læses kun af runneren:
  `ingest/forslag-manifest.json`, `ledger/eligibility-ledger-v1.json`, `fuld/manifest.json` (runner-manifestet) og
  `input/runner-input-v1.json`. B's GO-kode binder alle fire.
- **Forbindelsens rolle i prod** er Supabase's `postgres` via Session pooleren (`~/.Renviron`, som 6a/6b). B genberegner
  eligibility-ledgeren, og eksporten kræver en rolle, der omgår RLS (`rolsuper OR rolbypassrls`); ellers kunne RLS
  skjule en levende slægtning og gøre udelukkelsen for mild. `postgres` skal have `BYPASSRLS`. `apply-b` tjekker det,
  før den genberegner, og stopper med `EXPORT_ROLE_NOT_RLS_BYPASS`. Rollen skal også eje de tabeller, B skriver i
  (`T6C1_B_ANALYZE_EJER`, se Varighed), og eje alt i private+public for fortrydelsen (`RESTORE_PRIVILEGES`).
- **Vindue og skrivepause.** Pausen går fra A's dump (skridt 3) til B er godkendt (skridt 11), som i 6a og 6b. Både A's
  restore-alternativ og B's fortrydelse afhænger af den. `fortryd-b` sammenligner et rækkeaftryk pr. tabel og
  sekvensernes stand (`27-trin6c1-vindue.sql`) med aftrykket ved B's dump og stopper før restoren
  (`T6C1_VINDUE_BRUDT`), hvis noget ud over B's egne rækker er ændret.
- **Øvelsen er gennemført med den runner, der skal bruges** (se Øvelse). Ændres runneren, en bundet repo-fil
  (`db-migrations.sql`, `db-rls.sql`, `maal_trin6c1.sql`, `interpretation_transfer_digests.sql`,
  `export_model_eligibility.R`, `apply_reimport_helpers.R`, `evidence_runner.py`, profilfilen) eller en af de fire
  inputfiler, gentages øvelsen, og de faste værdier i runneren opdateres, før der tages GO.
- `DAA_EXPECTED_TARGET` (prods målidentitet) står i `prod/go-env.txt`, som ved 5c-2, 6a og 6b.
- **Modelrunneren** (`run_evidence_43b.py`, ikke en del af ceremonierne) skal køre med en `PATH` uden
  `~/.cmuxterm`-indgange: Seatbelt-profilen nægter adgang til cmux-shim'en for `codex`, og alle kald fejler så som
  `unknown` uden at sende noget (Task 8's første pilotforsøg). Brug den rigtige binær i `~/.local/bin`.

## Forløb (projektejerens shell)

Alle kommandoer køres som `/bin/zsh -f ~/.private/5ab-overfoersel/koer.zsh 27-trin6c1.sh …`. `koer.zsh` gemmer
runnerens `DAA_`-linjer (`DAA_T6C1_DUMP_FOER`, `DAA_T6C1_DUMP_A`, ved en uklar fortrydelse `DAA_T6C1_UKLAR`) i
`prod/go-env.txt`. Flagene er faste: skrivende handlinger kræver `--jeg-mener-det --go <kode>`, og ethvert ukendt
argument afvises.

### Ceremoni A

1. `maal` →
   - `T6C1_MAAL tilstand=foer forslag_k3=0 poster_k3=0 identiteter_k3=8 afventer=555 k1_forslag_hash=a9e32b70…`;
   - `T6C1_MAAL_OK tilstand=foer raa=foer sekunder=…` (over 60 s: stop, og mål igen);
   - `T6C1_DEFACL globale_authenticated=0 globale_anon=0 globale_public=0`.

   `k1_forslag_hash` er 2018-20's forslagsdigest og skal være `a9e32b70…` gennem hele forløbet (runneren tjekker
   det i hvert skridt). Tag `get_advisors(security)` som før-billede.
2. `go-a` → `GO_6C1_A_KODE=<8 hex>`. Projektejeren skriver `GO 6c1-A <kode>`. Koden binder ceremonien, målet
   (prod), commit'en, repo-filerne `db-migrations.sql`, `db-rls.sql`, `maal_trin6c1.sql`,
   `interpretation_transfer_digests.sql`, målidentitetens SQL og fortrydelsens fire mål-SQL'er
   (`transfer_acl_fingerprint.sql`, `transfer_catalog_fingerprint.sql`, `transfer_restore_hash.sql`,
   `transfer_restore_preconditions.sql`) samt de private filer (runneren, R-scriptet, vindues-SQL'en, `lib.zsh`,
   `koer.zsh`, `rollback-preflight.sql`).
3. `dump` → `DUMP_6C1_OK tilstand=foer …` og `EKSTERN_6C1_OK … ekstern=sftp rundtur=ok` (B1: `age`-krypteret kopi på
   SFTP-serveren, hentet tilbage, sammenlignet og dekrypteret; rundtur-kopien slettes efter kontrollen).
4. `apply-a --jeg-mener-det --go <kode>` →
   - `B1_6C1_OK …`; målingen før skal være `foer`;
   - blokken (sha `20615bb6…`) og `db-rls.sql` (sha `f517b2e5…`) i én transaktion; derefter `NOTIFY pgrst`;
   - `T6C1_APPLY_A_OK tilstand=a tal=0,0,8,555 k1=a9e32b70aba3ef35 profil=c6131dcc9655fd74 sekunder=…`: målingen er
     `a`, 2018-20 uændret, og forslagsprofilens sha er `c6131dcc…`.
5. `get_advisors(security)` igen. A tilføjer ingen funktion og ingen grant (`write_interpretation_proposal` er privat
   og REVOKE'et fra alle). Forventet diff: ingen. Alt andet undersøges før B.

### Ceremoni B

6. `manifest-b` (læse-kun, kræver tilstand `a`) →
   - `T6C1_INPUT_OK elementer=494 claims=2774 principal=2127 other=647 citater=2799 klausuler=682
     afventer_identitet=433 fortolkning_foreslaaet=249 records=500 ledger=cbed2e7ff343de9f klausulsaet=e8faa1666b136d83`;
   - `T6C1_INPUT_PRAEDIKATER …` (antal pr. prædikat, se Forventede tal);
   - `T6C1_MANIFEST_B_OK forslag=64c6f6a114643769 indhold=9208596e3ba76fc8 ledger=cbed2e7ff343de9f
     runner_manifest=6dc5be16ff360721 profil=c6131dcc9655fd74 …`.

   Skridtet efterprøver kæden lokalt: forslagsmanifestets indholds-sha (`9208596e…`, genberegnet), dets kilde (3) og
   profil (= profilfilens og basens sha), dets henvisning til runner-manifestet (`6dc5be16…`, også genberegnet) og til
   ledgerens fil-sha; at runner-manifestets 500 records er `eligible` uden årsager i ledgeren med samme input-sha; og
   at runner-inputtets helpost-tekst giver de samme input-sha'er. Af runner-inputtet beregnes klausulsættets hash pr.
   record (`evidence_runner.canonical_clause_set`) og et aggregat (`klausulsaet=e8faa166…`). Forventningen til B (antal
   pr. rolle, prædikat og disposition) skrives, før B kører.
7. `go-b` → `GO_6C1_B_KODE=<8 hex>`. Projektejeren skriver `GO 6c1-B <kode>`. Koden binder også
   `export_model_eligibility.R` (med hjælperen), `apply_reimport_helpers.R`, `evidence_runner.py`, profilfilen og de
   fire inputfiler.
8. `dump` igen → `DUMP_6C1_OK tilstand=a …`, `EKSTERN_6C1_OK …`, `DUMP_6C1_MAAL_OK vindue=… tabeller=132
   restore_hash=… katalog=… foraeldreloese=0 …` og `DAA_T6C1_DUMP_A=…`. Det er fortrydelsens dump med dens mål (grants,
   katalog, restore-hash, forældreløse rækker, `k1`, vinduet før og efter dumpet). `apply-b` kræver et dump i
   tilstand `a`, hvis `start_utc` højst er 12 timer gammel.
9. `apply-b --jeg-mener-det --go <kode>` →
   - `B1_6C1_OK …`; målingen før skal være `a`; profilen i basen er manifestets;
   - inputkæden igen (`T6C1_INPUT_OK …`, som skridt 6);
   - rolletjekket (`EXPORT_ROLE_NOT_RLS_BYPASS` ved fejl);
   - **ledgeren genberegnes mod prod** med den bundne ledgers `restore_identity` og skal være byte-ens med den bundne
     fil: `T6C1_LEDGER foer records=592 eligible=500 excluded=92 sha=cbed2e7ff343de9f sekunder=…`. Afviger den (fx
     fordi `levende` eller en kildetekst er ændret i prod efter øvelsen), skrives intet: `T6C1_LEDGER_DIFF …` og
     `STOPPORT: T6C1_B_LEDGER_AFVIGER`;
   - `27-trin6c1-b.R`:
     - `T6C1_B_START statement_timeout=2min elementer=494 claims=2774`;
     - **klausulsættet genberegnes inde i hver kædes transaktion** (efter advisory-låsen) og skal være det bundne:
       `T6C1_B_KLAUSULSAET dryrun|apply|replay records=500 agg=e8faa1666b136d83`. Ellers `T6C1_B_KLAUSULSAET_AFVIGER`
       og tilbagerulning;
     - `T6C1_B_DRYRUN status=finalized`;
     - `T6C1_B_COMMITTED status=finalized`: B er committet. Alle senere fejl er efter commit;
     - `ANALYZE` af de syv tabeller, B skrev i (se Varighed);
     - `T6C1_B_KANONISK fact=7193->7193 assertion=9306->9306 uaendret=TRUE`: personer, fakta, påstande (antal og
       rækkehash), konklusioner, narrativer, relationer og familiemedlemmer er uændrede (kanonisk delta 0);
     - `T6C1_B_KONTROL koersler=1 forslag=2774 principal=2127 other=647 proposed_v1=2774 citater=2799 klausuler=682
       poster=494`, `T6C1_B_PRAEDIKATER …`, `T6C1_B_DISPOSITIONER afventer_identitet=433 fortolkning_foreslaaet=249`
       og `T6C1_B_FORVENTNING som_skrevet=TRUE` (skrevet = forventningen fra skridt 6);
     - `T6C1_B_REPLAY already_applied`;
     - `T6C1_B_APPLY forslag=2774 poster=494 status=finalized sekunder=… inkl_dryrun=…` og `T6C1_B_TID …` (maksimum
       pr. sætningsslags);
   - **ledgeren igen efter commit**: `T6C1_LEDGER efter … sha=cbed2e7ff343de9f`. Afviger den nu, er det et
     fortrydelsestilfælde (`T6C1_B_LEDGER_EFTER_AFVIGER`; se Stoppunkter);
   - `T6C1_B_DIGEST n=2774 proposal_digest=8eadf701b222b60692c61615ce20a66b2dd5eb45796830c208634c5ea5e2cf99` (lig
     stand-in'ens; ellers `T6C1_B_DIGEST`);
   - `T6C1_APPLY_B_OK … tilstand=b tal=2774,494,8,555`, og `k1` er uændret.
10. `maal` → `T6C1_MAAL tilstand=b forslag_k3=2774 poster_k3=494 identiteter_k3=8 afventer=555 k1_forslag_hash=a9e32b70…`.
11. Projektejeren godkender B. Skrivepausen slutter. Derefter dækker fortrydelsen ved restore ikke længere
    (`T6C1_VINDUE_BRUDT`), og **6b-B kan ikke længere fortrydes** (se Fortrydelse).

Kør aldrig `apply-b` igen, når B er `finalized`: tilstanden er så `b`, og runneren stopper selv med `T6C1_FOER_B`.

**Afvigelse fra spec §4.6 (»i samme transaktion«).** Klausulsættet genberegnes i skrivetransaktionen. Ledgeren kan
ikke: den er et eget script (`export_model_eligibility.R`, læse-kun i sit eget REPEATABLE READ-snapshot). Den
genberegnes derfor umiddelbart før dry-run og igen umiddelbart efter commit. En ændring mellem de to tidspunkter ses af
den anden genberegning, og B kan da fortrydes, fordi vinduet stadig holder.

## Varighed og prods tidsgrænse

Prods `statement_timeout` er 2 minutter pr. sætning. Stand-in-tallene er fra slutøvelsen 2026-11-01
(`…_20261101204529_6c1r`). Prod anslås med de målte faktorer fra 6b-B (database-current-state §18): ca. 27× for mange
små writer-/RPC-kald, ca. 3× for én stor læsning. 27× står med som øvre grænse også for læsningerne.

| Sætning | Stand-in (maks.) | ×3 | ×27 | Gældende faktor |
|---|---|---|---|---|
| `maal_trin6c1.sql` (alle tilstande) | 0,2-0,3 s | 1 s | 8 s | 3× (6b's måling: 0,7-0,9 s i prod) |
| A: blok + `db-rls.sql` (mange sætninger) | 0,1-0,2 s | — | — | 6b's A tog 16,3 s i prod |
| Dump (15,7 MB) / dump i `a` med mål | 1,7 s / 4,8-4,9 s | — | — | 6b: 87 s + 17,5 s i prod |
| Ledgerens genberegning: eksportens ene store forespørgsel | 2,10 s (hele processen 2,8-3,1 s inkl. R-start) | 6 s | 57 s | 3× |
| Klausulsættet (én forespørgsel, 3 gange i B) | 0,69 s | 2 s | 19 s | 3× |
| Autorisationen (`red_authorize_reimport` med hele payloaden, 1,7 MB) | 0,69 s | — | 19 s | 27× |
| Ét writer-kald (`interpretation_proposal`), maks. af 494 | 0,058 s | — | 1,6 s | 27× |
| Finalize | 0,002 s | — | 0,1 s | 27× |
| `ANALYZE` pr. tabel efter commit (7 tabeller) | 0,05 s | — | 1,4 s | 27× |
| Kanonisk måling / kontrolforespørgsel | 0,15 s / 0,01 s | 0,5 s | 4 s | 3× |
| Forslagsdigestet for kilde 3 (efter `ANALYZE`) | 0,1-0,3 s | 1 s | 8 s | 3× |
| B's dry-run i alt (ikke én sætning) | 10,1 s | — | ca. 4,5 min | 27× |
| B's apply + finalize i alt (ikke én sætning) | 9,9-10,2 s | — | ca. 4,5 min | 27× |
| `apply-b` i alt (inkl. to ledgergenberegninger) | ca. 33 s | — | ca. 10-12 min | — |
| Fortrydelse: restore / efterarbejde | 3,1-3,2 s / 4,0-4,2 s | — | minutter | restore uden tidsgrænse; mål med 15 min |

Ingen sætning anslås over 60 s med sin gældende faktor; ledgerens forespørgsel ligger lige under (57 s) selv med 27×.

**Fund: digestet kræver frisk statistik.** I øvelsen tog forslagsdigestet for kilde 3 16,6 s, så længe
planner-statistikken var fra før B (ANALYZE ved restoren), og 0,1 s efter `ANALYZE` af de skrevne tabeller. 16,6 s ville
være ca. 50 s med 3× og ca. 7,5 min med 27× (over grænsen). Prods autovacuum når ikke nødvendigvis at analysere
inden. `27-trin6c1-b.R` kører derfor `ANALYZE` af `interpretation`, `interpretation_observation`,
`clause_disposition`, `extraction_run`, `reimport_event`, `reimport_batch` og `reimport_authorization` lige efter
commit, og den tjekker før noget skrives, at forbindelsens rolle ejer dem (`T6C1_B_ANALYZE_EJER`): `ANALYZE` på en
tabel, rollen ikke ejer, giver kun en advarsel og springer tabellen over.

## Stoppunkter

Alle `STOPPORT:`-linjer stopper uden at skrive yderligere. Hvor langt man er nået, læses af `maal` og af batchens
status i `private.reimport_batch` (profil `daa-1939-interpretation-proposal-v1`).

| Hvor | Tilstand bagefter | Gør |
|---|---|---|
| Enhver handling ud over `maal`: `T6C1_6B_FORTRYD_IGANG` | uændret | En fortrydelse af 6b-B er påbegyndt. Gennemfør den med `26-trin6b.sh` først (trin6b-runbooken) |
| Før `apply-a`'s blok (`DUMP_6C1_MANGLER`, `GO_MISMATCH`, `T6C1_FOER`, `T6C1_K1_AENDRET`, `T6C1_BLOK`, `T6C1_RLS`) | `foer`; intet skrevet | Ret årsagen, kør skridtet igen |
| I A's transaktion (`DDL_6C1 fejlede`) | `foer`; rullet tilbage | Ret årsagen; ny GO, hvis filer ændres |
| Efter A's commit (`DDL_6C1_NOTIFY`, `T6C1_EFTER_A`, `T6C1_K1_UAENDRET`, `T6C1_PROFIL`) | A er committet | Kør `maal`. Er den `a` og `k1` uændret: kør `NOTIFY pgrst` manuelt og fortsæt. Ellers: stop; fortrydelse af A |
| `manifest-b`/inputkæden (`T6C1_MANIFEST_*`, `T6C1_PROFILFIL_AFVIGER`, `T6C1_RUNNER_MANIFEST_*`, `T6C1_LEDGER_*`, `T6C1_RUNNER_INPUT_AFVIGER`, `T6C1_PROFIL_MANIFEST`) | `a`; læse-kun | En inputfil eller profilen er ikke den øvede. Find ændringen; ingen B før øvelsen er gentaget |
| `dump` i `a` (`DUMP_6C1_SKREVET_UNDER_DUMP`, `DUMP_6C1_FORAELDRELOESE`, `DUMP_6C1_TILSTAND_SKIFTEDE`) | `a`; læse-kun | Ingen gyldig kvittering. Find skriveren / de forældreløse rækker; tag `dump` igen |
| `apply-b` før R (`EXPORT_ROLE_NOT_RLS_BYPASS`, `T6C1_LEDGER_EKSPORT_FEJL`) | `a`; intet skrevet | Forbindelsens rolle omgår ikke RLS, eller eksporten fejlede (koden står i linjen). Ret, og kør igen |
| `apply-b`: `T6C1_B_LEDGER_AFVIGER` (med `T6C1_LEDGER_DIFF records_afviger=… felter_afviger=…`) | `a`; intet skrevet | **Prod er ændret efter øvelsen** (fx `levende` eller en helpost-tekst). Det er netop den vagt, Review Focus 5 kræver. Stop. Projektejeren afgør ændringen; et nyt udfald kræver ny ledger, nyt udvalg og ny øvelse (eller et reservemanifest uden de berørte poster) |
| B før apply-commit (`T6C1_B_KLAUSULSAET_AFVIGER`, `T6C1_B_ANALYZE_EJER`, `T6C1_B_PROFIL_AFVIGER`, writerfejl, ingen `T6C1_B_COMMITTED`) | `a`; batchen rullet tilbage | `T6C1_B_FEJL (<kode>; sidste trin: …)`; fuld fejllinje i `apply-b-*.out`. Klausulsættet afviger: en kildetekst eller omsegmentering er ændret efter øvelsen; som ledgerafvigelsen. Andet: ret, og `apply-b` igen med samme GO |
| Efter B's commit: `T6C1_B_FEJL_EFTER_COMMIT`, `T6C1_B_KANONISK_AENDRET`, `T6C1_B_KONTROL_AFVIGER`, `T6C1_B_REPLAY_STATUS`, `T6C1_B_DIGEST`, `T6C1_EFTER_B`, `T6C1_K1_UAENDRET` | batchen `finalized` | Kør `maal`. Er den `b` og `k1` uændret, er B skrevet; undersøg kontrolfejlen bagefter. Viser kontrollen, at B skrev forkert, eller er `k1` ændret: **fortrydelsestilfælde**, `fortryd-b` |
| Efter B's commit: `T6C1_B_LEDGER_EFTER_AFVIGER` | batchen `finalized` | Ledgeren ændrede sig mellem genberegningen før dry-run og efter commit. **Fortrydelsestilfælde**: `go-fortryd` → `fortryd-b`, mens vinduet holder; derefter som `T6C1_B_LEDGER_AFVIGER` |
| `fortryd-b` og genoptagelsen | se trin6b-runbookens tilsvarende rækker | Koden er 6b's med navnene `T6C1_…`: `T6C1_FORTRYD_C`, `T6C1_FORTRYD_TILSTAND`, `T6C1_K1_AENDRET_I_VINDUET`, `T6C1_VINDUE_BRUDT`, `T6C1_FORTRYD_LAAS`, `T6C1_FORTRYD_RESTORE_FEJL`, `T6C1_FORTRYD_UKLAR` (beslutningstabellen), `T6C1_GENSTART_*` |
| Målingens egne fejl (`maal_trin6c1.sql fejlede`, `T6C1_MAAL_FORM`, `MAAL_6C1_UKENDT`) | uændret af fejlen selv | Efter et commit: læs batchens status og kør `maal` igen; før et commit: intet er skrevet |

`GO_MISMATCH` viser den kode, filerne svarer til nu. Brug den ikke uden at have tjekket, hvad der er ændret siden GO.

## Fortrydelse pr. fase (spec §6)

- **Ceremoni A:** restore af A-dumpet (skridt 3) i vinduet, som 6a's og 6b's A. Alternativt manuelt: genskab
  `private.write_interpretation_proposal` fra A-dumpet (med dens REVOKE), tag stilling til profilrækken
  `daa-1939-interpretation-proposal-v1`, og kør `db-rls.sql` fra commit'en før 6c-1. Ikke scriptet og ikke øvet; det
  bygges kun, hvis det bliver nødvendigt. Efter B kan A ikke fortrydes alene (B's forslag er skrevet af den nye writer
  med den nye profil).
- **Ceremoni B, før C:** forslag er append-only, så ingen writer kan slette dem. Fortrydelse er **kun** restore af
  dumpet fra skridt 8 (tilstand `a`), og kun så længe vinduet holder (intet andet skrevet i public/private siden
  dumpet):
  1. `go-fortryd` → `GO_6C1_FORTRYD_B_KODE=<8 hex>`; koden binder også kvitteringen `DAA_T6C1_DUMP_A`. Projektejeren
     skriver `GO 6c1-fortryd-B <kode>`.
  2. `fortryd-b --jeg-mener-det --go <kode>` → `T6C1_FORTRYD_B_OK tilstand=a tal=0,0,8,555 k1=a9e32b70aba3ef35
     beslutning=ny vej=restore genoptaget=0 restore_fejl=5 grants_afstemt=0|16 acl=som_dump katalog=som_dump
     restore_hash=…`. Forløbet er 6b's (`26-trin6b.sh fortryd-b`, trin6b-runbooken »Fortrydelse pr. fase«): rå
     tilstand `b` kræves, `k1` og vinduet skal være dumpets, markøren `fortryd-b-<dump-sha>.igang` sættes før
     restoren, `pg_restore --clean --if-exists` af private+public med fejlmønsteret (de 4 kendte fejl om
     `current_rolle()`/`media_object_synlig_anon(text)` + advarslen), skema-defaults ryddes og genskabes, `ANALYZE`,
     `db-rls.sql`, grants afstemmes mod dumpets mål (`reconcile_grants`), `NOTIFY pgrst`, og efterkontroller af
     grants, default-rettigheder, katalog, forældreløse rækker, restore-hash og `maal` = `a`. Genoptagelsens lukkede
     beslutningstabel (række 1-4, UKLAR-episoder og `--genstart-restore`) er 6b's.
  3. `maal` → `a`. B kan køres igen fra skridt 9 med samme manifest og dump (ny batch), hvis dumpets `start_utc` højst
     er 12 timer gammel; ellers nyt `dump` i `a` og nyt `go-b`.

  Vinduet undtager kun B's egne rækker: autorisationer, batches og hændelser under forslagsprofilen,
  `extraction_run` for kilde 3 med writerens præfiks `interpretation-proposal:`, fortolkningerne fra den kørsel, deres
  `interpretation_observation` og de `clause_disposition`-versioner, der peger på profilens batches. Kun
  `private.reimport_event_id_seq` sammenlignes ikke før restoren (B flytter den i dry-run og apply; målt: ingen anden
  sekvens flytter sig).
- **6b-B's fortrydelsesvindue lukker, når B skriver.** Forslagene refererer 6b's personas og er append-only;
  `26-trin6b.sh fortryd-b` stopper på `T6B_VINDUE_BRUDT`, fordi B's rækker ændrer 6b's aftryk. Omvendt nægter
  `27-trin6c1.sh` at køre, mens en 6b-fortrydelse er påbegyndt.
- **Efter C (6b's ceremoni C) har skrevet:** B kan ikke længere fortrydes ved restore (`T6C1_FORTRYD_C`; C's
  `publication_identity` ville forsvinde med). C fortrydes med 6b's `reversal` → `superseded` og kan genkøres
  (decisions 2026-10-31).
- **Efter afgørelse/promotion (6c-2):** 6c's egen fortrydelse gælder.

## Ceremoni C

C kører som 6b-runbooken beskriver (`docs/runbooks/trin6b-prod.md`, udvidet af 6b-planens Task 15-16), når B er i
prod og godkendt. 6c-1 lukker de punkter, 6b parkerede (spec §4.7); de øves på stand-in'en efter B (Task 9).

## Forventede tal

Kun antal og hashes. Fra slutøvelsen 2026-11-01 (stand-in = `_6bm`, prod efter 6b-B).

| | Værdi |
|---|---|
| A-blokkens sha / `db-rls.sql` | `20615bb60407b9f3…` / `f517b2e5ac11b9ac…` |
| Forslagsprofilens sha (`daa-1939-interpretation-proposal-v1`) | `c6131dcc9655fd74abeb3de787592ee76a7fa17944a9b525b41a38bdd7acd6dc` |
| Forslagsmanifest: indholds-sha / fil-sha | `9208596e3ba76fc89f61a17e34cf1c29548a3fdbc7d51209a4f41fe1349fc90b` / `64c6f6a114643769…` |
| Runner-manifest (`manifest_sha256`) | `6dc5be16ff360721fefbe5718d5fbcba4761362b8d85121bc316888ecbc2a21d` |
| Eligibility-ledger (`exclusion-1939-v1`): fil-sha, records/eligible/excluded | `cbed2e7ff343de9f…`; 592 / 500 / 92 |
| Klausulsættets aggregat over runner-manifestets 500 records | `e8faa1666b136d83…` |
| Elementer / forslag / poster med forslag | 494 / 2.774 / 494 |
| Roller: `principal` (med persona) / `other` (uden) | 2.127 / 647 |
| Citater (`interpretation_observation`) / citerede klausuler | 2.799 / 682 |
| Klausuldispositioner: `afventer_identitet` / `fortolkning_foreslaaet` | 433 / 249 |
| Prædikater | `event.acquisition=15 event.appointment=6 event.dismissal=4 event.marriage=29 event.travel=2 mention.estate=5 mention.person=17 mention.place=344 person.baptism=60 person.birth=302 person.burial=58 person.death=296 person.decoration=41 person.education=75 person.estate=201 person.military_service=29 person.name=401 person.occupation=38 person.office=240 person.rank=58 person.residence=23 person.title=249 relation.child=4 relation.marriage=271 relation.parent=6` |
| Forslagsdigest for kilde 3 (`interpretation_transfer_digests.sql`) | n=2.774, `8eadf701b222b60692c61615ce20a66b2dd5eb45796830c208634c5ea5e2cf99` |
| `k1_forslag_hash` (2018-20; uændret i alle tilstande) | `a9e32b70aba3ef35787c6d2b466181842b3b26b1a397971a4574b75b869430e1` |
| `maal` `foer` = `a` / `b` | `0 0 8 555` / `2774 494 8 555` (forslag_k3 poster_k3 identiteter_k3 afventer) |
| Kanonisk (før = efter B) | fact 7.193, assertion 9.306; rækkehash uændret |
| `db-verify.sql` på en engangskopi i tilstand `b` | 137 OK, 0 fejl (32,7 s) |

Forslagsmanifestets regnskab (Task 8): rå 2.938, kontrakt-afviste 163, H1 1, dubletter 0, ingestible 2.774,
principal uden persona 0.

## Øvelse (2026-11-01)

Kørt med `DAA_STANDIN_DB=<stand-in>` og `DAA_STANDIN_REPO=<worktree for docs/trin6c1-koersel>` (= `main` + en
dokumentcommit; commit `f5741f25`). SFTP er i stand-in-tilstand en lokal mappe (`ekstern=lokal-simulering`); den
rigtige SFTP-vej er 6b's kode, som kørte i prod 2026-11-01.

1. **Første stand-in** `daa5ab_ddl_standin_20261101203417_6c1r` (`createdb -T …_6bm`, ICU, 2 min, `ANALYZE`):
   `maal` `foer` → A → `a` → `manifest-b` → B. Tre fejl blev fundet og rettet i runneren, før B lykkedes; ingen af dem
   skrev noget, der ikke blev rullet tilbage eller fortrudt:
   - aggregatet over klausulsættet brugte R's locale-sortering mod Pythons kodepunktsortering
     (`T6C1_B_KLAUSULSAET_AFVIGER`; nu `sort(method = "radix")`);
   - autorisationen manglede aktørens claim på sin forbindelse (`REIMPORT_WRITER_ROLE_FORBIDDEN`; nu som 25-trin6a-b.R);
   - en kontrolforespørgsel efter commit brugte `ORDER BY 1 COLLATE "C"` (B var committet; fortrudt med `fortryd-b`,
     som samtidig beviste, at vinduets undtagelser er dækkende).

   Derefter B → `b` (digestet fastlagt), `fortryd-b` → `a`, B → `b` (samme digest), `db-verify.sql` på en
   engangskopi: 137 OK, 0 fejl. Her blev digestets afhængighed af statistik fundet (se Varighed).
2. **Slutøvelse** på en frisk stand-in `daa5ab_ddl_standin_20261101204529_6c1r` med den færdige runner: `maal` `foer`
   → `go-a`/`dump`/`apply-a` → `a` → `manifest-b` → `go-b`/`dump` i `a` → `apply-b` → `b` (alle tal og digestet som
   fastlagt) → `go-fortryd`/`fortryd-b` → `a` → `apply-b` → `b` → `db-verify.sql` på en engangskopi (137 OK). Til sidst
   kom ejerskabstjekket (`T6C1_B_ANALYZE_EJER`) til R-scriptet; `fortryd-b` → `a` → `apply-b` → `b` blev kørt igen med
   den endelige runner. A's kodevej er uændret siden; dens GO-kode ændrede sig kun, fordi R-scriptets hash indgår.
3. Kvitteringer: replay `already_applied` i hver B; `T6C1_LEDGER foer/efter` byte-ens med den bundne ledger i hver B;
   `T6C1_FORTRYD_B_OK … restore_fejl=5 grants_afstemt=0|16 acl=som_dump katalog=som_dump` i hver fortrydelse;
   `k1_forslag_hash` uændret i alle målinger. En kunstig 6b-markør i stand-in'ens `6b/`-mappe stoppede `apply-b` med
   `T6C1_6B_FORTRYD_IGANG`.

Review Focus 5 (`levende` ændres i prod mellem dumpet og B) øves i Task 9 step 4 på stand-in'en. Runneren stopper da
med `T6C1_B_LEDGER_AFVIGER`, før noget skrives.

## Efter ceremonierne

- `docs/database-current-state.md`: nyt afsnit for 6c-1 A og B med målte prod-tider og forholdet til stand-in'en.
- `docs/changelog.md` og `status.md` (1939 »Extractor-runner« → `produktionsverificeret`, »Forslag og afgørelse« →
  forslag i prod).
- Notér prod-tiderne for ledgerens genberegning, autorisationen og digestet her, så C's og 6c-2's skøn bygger på dem.
