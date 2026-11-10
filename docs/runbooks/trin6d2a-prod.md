# Runbook: trin 6d-2a i prod — oversigtsreglen og 1939's resterende identitetssager

Spec: `docs/superpowers/specs/2026-11-09-trin6d2a-oversigtsregel-identitet-design.md` (rev. 4). Plan:
`docs/superpowers/plans/2026-11-09-trin6d2a-oversigtsregel-identitet.md` (Task 7-8). Beslutning: `docs/decisions.md`
2026-11-09 »6d-2 deles i 6d-2a og 6d-2b«.
Runner: `~/.private/5ab-overfoersel/34-trin6d2a.sh` med `34-trin6d2a-vindue.sql` (aldrig i repoet), bygget som
`33-trin6d1.sh`. Den kaldes via `/bin/zsh -f ~/.private/5ab-overfoersel/koer.zsh 34-trin6d2a.sh <handling>` fra
operatørens cwd. De bundne input ligger i `~/.private/6d2a/` (mappen 0700, filerne 0600, sha'erne fastlåst i
runneren): `kortmanifest.json` (`cb5e1c13…`, kontrakt `trin6d2a-kortmanifest-v1`) og `kort-svar.txt` (`c001c206…`,
K1-K4 = J). Runneren tjekker kæden mellem dem: manifestets kontrakt og kilde, `svar_sha256` = svarfilens sha, ét svar
pr. kort, og at K1's par er målescriptets par (1014, 1048). Alle linjer er kun antal, koder og hashes. Prod-skrivning
(`apply-*`, `fortryd`) sker kun i projektejerens shell med `--jeg-mener-det --go <kode>`. Hovedcheckouten skal være
ren og stå på den commit, GO er bundet til (`main` efter merge). **Begge** GO-koder binder DDL-blokken,
`identitet_ceremoni.sql`, `maal_trin6d2a.sql`, `db-rls.sql`, manifest, svar, runneren, vinduesvagten og commit'en
(Codex-fund 11).

## To ceremonier

1. **DDL** (blok `-- ===== trin 6d-2a: oversigtsomtaler og samme_som-retning =====` + `db-rls.sql` i én transaktion,
   `lock_timeout 5s`). Kun `CREATE OR REPLACE FUNCTION` + `REVOKE/GRANT`. Tre nye funktioner
   (`private.overview_mention_narratives(bigint[])`, `private.samme_som_data_direction(bigint,bigint)`,
   `public.red_overview_mentions(bigint[])`); ændrede: begge biografilæsere og `red_samme_som`. Kontrol efter:
   grant-matrixen `-----x-xxxxx` (de to private uden EXECUTE; `red_overview_mentions` og `red_samme_som` kun
   authenticated; begge biografilæsere anon og authenticated), og `FAKTA` uændret.
2. **Data** (`apply-data`): ét kald af `identitet_ceremoni.sql` (src=3) i ÉN transaktion under egen
   `statement_timeout=15min`: K1 = `samme_som` 1014 → 1048, K2-K4 = identiteterne for personas `589f8292` → 1054,
   `b06067a3` → 1123, `a573cad1` → 1158, og til sidst kvitteringen (change_set `identitet_ceremoni` på kilden,
   summary `T6D2A_OK …`). Hver førtilstand efterprøves under lås mod manifestet (`T6D2A_PRE_MANIFEST`). En fejl ruller
   alt tilbage.

## Rækkefølge

| Trin | Handling | Forventet (generalprøven, stand-in `6d2ab`) |
|---|---|---|
| 0 | `maal` | `T6D2A_MAAL fase=foer regel=na synlige_anon=na bio_oversigt=na kanter_par=0 unresolved=1 uden_identitet=2 KOORD_2018_20=99a5a2de… KOORD_SRC=2136dfc0… FAKTA=… BIO=…`, `T6D2A_MAAL_OK tilstand=foer` |
| 0b | `anon` | `T6D2A_ANON_BASIS …` (tidsbudgettets basis, gemt privat); evt. `T6D2A_ANON_OVER_3S …` |
| 1 | `dump` | `DUMP_6D2A_OK tilstand=foer`, `EKSTERN_6D2A_OK … rundtur=ok`, `DUMP_6D2A_MAAL_OK … vindue_linjer=136`, `DAA_T6D2A_DUMP=…` |
| 2 | `go-ddl` → projektejeren `apply-ddl --jeg-mener-det --go <kode>` | `T6D2A_PAKKE_OK filer=2 kort=4 kanter=1 identiteter=3`, `T6D2A_VINDUE_OK sammenligning=eksakt`, `T6D2A_APPLY_DDL_OK tilstand=ddl blok=dfaaf9dacebdcac2` |
| 3 | advisors (`get_advisors` security + performance, læse-kun) | ingen nye fund ud over de kendte |
| 4 | `maal` | `fase=ddl regel=10 synlige_anon=9 bio_oversigt=0 kanter_par=0 unresolved=1 uden_identitet=2`, KOORD og FAKTA som trin 0, BIO ændret |
| 4b | `anon` | `T6D2A_ANON_BUDGET fase=ddl … OK …` (ingen kald over max(basis × 1,10; basis + 20 ms)) |
| 5 | `dump` | `DUMP_6D2A_OK tilstand=ddl` (data-dumpet; fortrydelsens grundlag) |
| 6 | `go-data` | `manifest=cb5e1c1343544706 svar=c001c206de9acb88`, `GO_6D2A_DATA_KODE=…` |
| 7 | projektejeren `apply-data --jeg-mener-det --go <kode>` | se næste tabel |
| 8 | `verify` | `T6D2A_VERIFY_OK tal=11,9,0,1,0,0 …` (FAKTA = ddl-dumpets), `T6D2A_ANON_BUDGET fase=data … OK` |

`apply-data`'s linjer:

| Linje | Betydning |
|---|---|
| `T6D2A_PAKKE_OK filer=2 kort=4 kanter=1 identiteter=3` | pakken og kæden mellem filerne |
| `T6D2A_VINDUE_OK sammenligning=eksakt linjer=136` | intet i `public`/`private` er ændret siden data-dumpet |
| `T6D2A_DATA_START fase=ddl kanter=1 identiteter=3` | |
| `T6D2A_CEREMONI_TID saetninger=14 maks_s=15.8 sum_s=15.8` (stand-in) | `\timing` fra ceremonien |
| `T6D2A_OK kanter=1 identiteter=3 regel=11` | ceremoniens kvittering (fastlåst) |
| `T6D2A_APPLY_DATA_OK fase=data tal=11,9,0,1,0,0 koord=99a5a2de04b1b921 fakta=uaendret bio_aendret=nej` | FAKTA og KOORD uændrede; BIO uændret, fordi 1014 er `staged` |

**Tid.** Ceremonien er én sætning på 15,8 s på stand-in (FAKTA og reglen beregnes før og efter i transaktionen).
Med den værste skrive-faktor, der er målt (6c-2: ≈27), giver det ≈7 min, under ceremoniens 15 min. `maal` tager
≈10 s på stand-in (FAKTA over alle offentlige personer dominerer). **Målt i prod (fase foer): `maal` 34,2 s mod
10,2 s på stand-in = læsefaktor ≈3,4** (6d-1: 2,5-2,7). Ceremonien ventes derfor ≈1 min i prod; selv faktor 27
holder under 15 min. Prods `statement_timeout` (2 min) gælder ikke:
runneren sætter sin egen læsegrænse, og ceremonien sætter `15min` lokalt.

**Tidsbudgettet** (spec §4.1 rev. 4). `anon` måler biografilæseren v2 med alle anon-synlige personer
(feedets største kald), koordinat-RPC'en, `public_person_facts` for 199/529/289 og `public_family_sources` for
309/298/364. Hvert kald køres tre gange, og medianen bruges. Fase `foer` gemmer basis, og senere faser sammenlignes
med basis fra samme base. Tærsklen er max(basis × 1,10; basis + 20 ms), fordi kald på 14-20 ms ikke kan skelne 10 % fra
støj. Anon's 3 s løftes til 120 s under målingen. Kald over 3 s meldes som
`T6D2A_ANON_OVER_3S` og er ikke en fejl her. Biografilæseren med alle personer ligger allerede på ≈2,9-3,2 s på
stand-in *før* 6d-2a, og det er backlog (decisions 2026-11-09). Selve 6d-2a lagde +2-8 % til på stand-in, og det
spænd er målestøj (data ændrer ikke biografien).

**Prods basis (fase `foer`, målt 10/11):** `bio_alle 13053 ms`, `koordinater 1414`, `facts_199 438`, `facts_289 179`,
`facts_529 175`, `famsrc_298 79`, `famsrc_309 74`, `famsrc_364 74`. Biografilæseren med alle personer er altså ≈4,5 ×
stand-in og over anon's 3 s allerede før 6d-2a; feedets biografikald fejler i prod i dag. Det er ikke en følge af
6d-2a, og budgettet sammenligner med prods egen basis.

## Fastlåste værdier og deres uafhængige kilder

- `T6D2A_BLOK=dfaaf9dacebdcac2…` = blokken skåret fra `db-migrations.sql` på grenen; `T6D2A_RLS=16ac093b…` =
  grenens `db-rls.sql`.
- `M[foer|ddl|data]` = spec §8's forventning (10 narrativer, 9 synlige før; 11 efter 1014's kobling, stadig 9
  synlige; 0 leveret som biografi), målt på to stand-ins og på en prod-kopi med DDL (Task 6's accept).
- `KOORD_2018_20`/`KOORD_SRC` = 6d-1's fastlåste hashes (uændrede siden 6d-1's prod-ceremoni).
- `FAKTA`/`BIO` er rækketekst-hashes og afhænger af basens locale. De fastlåses ikke, men sammenlignes kun inden for
  samme base.
- Vinduets undtagelser er målt på stand-in `6d2aa`:
  - **Data:** `private.identity_mutation_generation`, `private.source_persona_identity(_event)`,
    `public.relation`/`assertion`/`conclusion`, `public.change_set`/`change_event` og deres sekvenser.
  - **DDL:** kun de fem sekvenser, som en tilbagerullet data-ceremoni rykker (som 33). Målt `-` i den rene kørsel.

## Stoppunkter

| Linje | Betyder | Gør |
|---|---|---|
| `MAAL_6D2A_UKENDT` i trin 0 | prod er ændret siden generalprøven | ny `dump-kopi`, ny `standin`, generalprøve igen |
| `T6D2A_VINDUE_BRUDT_FOER_*` | prod er skrevet siden dumpet | intet kørt; tag `dump` igen |
| `T6D2A_EFTER_DDL_FAKTA` | DDL'en ændrede faktalæserne | fortryd-DDL (nedenfor) |
| `T6D2A_ANON_BUDGET_BRUDT` | et kald er over budget | stop før data; kør `anon` igen (støj?), ellers fortryd-DDL |
| `T6D2A_CEREMONI_FEJL (T6D2A_PRE_…)` | intet skrevet (fase ddl) | prod afviger fra manifestet: nyt kort/manifest, ingen genkørsel |
| `T6D2A_CEREMONI_FEJL (T6D2A_POST_…)` | rullet tilbage (fase ddl); sekvenserne kan være rykket | `dump` igen før næste `apply-data` |
| `T6D2A_CEREMONI_FEJL_EFTER_COMMIT` | committet (fase data) | `verify`, eller fortryd-data |
| `T6D2A_DATA_FAERDIG` | ceremonien er kørt | `verify` |

## Fortrydelse (kun under meldt frys)

- **Data:** `DAA_T6D2A_DUMP=<ddl-dumpets kvittering>` (står i go-env efter trin 5) → `go-fortryd` → projektejeren
  `fortryd --jeg-mener-det --go <kode>`. Restore af dumpet. Kræver, at alle change_sets siden dumpet er ceremoniens
  (kvitteringen + `red_samme_som`), og at kataloget er uændret.
- **DDL** (kun efter fortryd-data, basen i fase `ddl`): `koer.zsh --saet DAA_T6D2A_DUMP=<foer-dumpets kvittering>` →
  `go-fortryd` → `fortryd`. Katalogdiffen skal være præcis de tre nye funktioner (ellers
  `T6D2A_FORTRYD_DDL_UKENDT_OBJEKT` uden drop). Funktionerne droppes, dumpet restores, og `db-rls.sql` genanvendes **som
  før 6d-2a**. Den hentes fra git ved merge-basen `94517497` og efterprøves mod sha `e63c2182…` (= 6d-1's). Grenens
  udgave allow-lister `red_overview_mentions`, som fortrydelsen netop har fjernet.
- Vinduesvagten kører lige før markøren: et bogmærke e.l. efter dumpet stopper fortrydelsen uden markør.
- Vagten har to lag:
  - **Mod dumpet:** sammenlignes med undtagelser for de tabeller, ceremonien selv skriver.
  - **Mod aftrykket efter ceremonien:** fortryd-data kræver desuden, at hele basen er lig det aftryk, runneren
    gemmer lige efter ceremoniens COMMIT (`T6D2A_VINDUE_EFTER_GEMT`). Det gemmes også ved
    `T6D2A_CEREMONI_FEJL_EFTER_COMMIT`. Derved fanges skrivninger, der ikke laver en change_set, fx en
    identitetsafgørelse efter ceremonien (`T6D2A_VINDUE_BRUDT_EFTER_CEREMONI`).

`verify` udskriver `T6D2A_VERIFY_OK` efter datatjekkene og måler først derefter tidsbudgettet. Et
`T6D2A_ANON_BUDGET_BRUDT` her betyder, at data er i orden, men at et kald er over grænsen. Kør `anon` igen op til to
gange (biografilæseren med alle personer svinger ±8 % uden ændringer). Er bruddet vedvarende, beslutter
projektejeren, om der skal fortrydes.

## Generalprøven 10/11

`6d2aa`-`6d2ac` er kopier af `6d1c` (prod efter 6d-1); `6d2ad` er en frisk prod-`dump-kopi` (10/11).

- `6d2aa` (`daa5ab_ddl_standin_20261109231326_6d2aa`), iteration:
  - Kørt: `maal` → `anon` → `dump` → forkert GO (`GO_MISMATCH`) → `apply-ddl` → `anon` → `dump` → `apply-data`
    (`T6D2A_OK kanter=1 identiteter=3 regel=11`, 14 s) → `verify` → gentaget data (`T6D2A_DATA_FAERDIG`) →
    fortryd-data (vinduets data-mængde målt) → fortryd-DDL.
  - Tre runnerfejl blev fundet og rettet:
    - `OVER_3S` sammenlignede som tekst under dansk locale.
    - Katalogteksten var schema-kvalificeret.
    - Fortryd-DDL genanvendte grenens `db-rls.sql` (`RLS_REDACTION_RPC_ALLOW_LIST_SIGNATURE_MISSING` efter restore).
  - `6d2aa` står halvt fortrudt med markør og må ikke bruges.
- `6d2ab` (`daa5ab_ddl_standin_20261109232324_6d2ab`), den rene vej med alle værdier fastlåst:
  - DDL og data: `maal` → `anon` → `dump` → `apply-ddl` uden flag (afvist) → `apply-ddl` → `anon` (OK) → `dump` →
    `apply-data` (samme tal, 15,8 s) → `verify` (OK).
  - Fortrydelse: et bogmærke efter data-dumpet → `fortryd` stoppede med `T6D2A_VINDUE_BRUDT` uden markør. Bogmærket
    blev fjernet → fortryd-data `T6D2A_FORTRYD_OK tilstand=ddl` → fortryd-DDL `T6D2A_FORTRYD_OK tilstand=foer`
    (3 funktioner droppet).
  - Ændret svarfil → `T6D2A_PAKKE_SHA`. Filen blev lagt tilbage, og sha'en er efterprøvet. `6d2ab` står i fase `foer`.
- `6d2ac` (`daa5ab_ddl_standin_20261109233713_6d2ac`), fejlvejene (runneren midlertidigt ændret og lagt tilbage,
  sha'en efterprøvet):
  - Fejl før COMMIT: `T6D2A_CEREMONI_FEJL (T6D2A_POST_REGEL regel=11 (forventet 12)); IKKE committet (fase ddl)`.
    En ny `apply-data` uden nyt dump gav `T6D2A_VINDUE_BRUDT_FOER_DATA` (præcis de fem sekvenser). Fortryd-DDL lige
    derefter gav `T6D2A_FORTRYD_OK tilstand=foer`, hvilket bekræfter DDL-undtagelsen.
  - Fejl efter COMMIT (en ekstra sætning efter ceremonien): `T6D2A_VINDUE_EFTER_GEMT`,
    `T6D2A_CEREMONI_FEJL_EFTER_COMMIT … (fase data)`. Derefter gav `verify` `T6D2A_VERIFY_OK tal=11,9,0,1,0,0`.
  - En identitetsrække blev ændret efter ceremonien. Den gamle vagt sagde OK (`sammenligning=data`), men
    `T6D2A_VINDUE_BRUDT_EFTER_CEREMONI` stoppede fortrydelsen uden markør. Ændringen blev rullet tilbage → fortryd-data
    `T6D2A_FORTRYD_OK tilstand=ddl`. `6d2ac` står i fase `ddl`.
- `6d2ad` (`daa5ab_ddl_standin_20261110064713_6d2ad`), slut-generalprøven fra prods `dump-kopi`
  (`daa-prod-20261110064333-6d2a-kopi.dump`, sha `975285af…`), kørt fra repo-roden med commit `356dc20a`:
  - `standin` (restore 3,9 s) → `maal` (fase `foer`, samme tal og KOORD som prod) → `anon` (basis) → `dump` →
    `go-ddl` → `apply-ddl` (0,2 s) → `anon` (OK) → `dump` → `maal` (`10 9 0 0 1 2`) → `go-data` → `apply-data`
    (`T6D2A_OK kanter=1 identiteter=3 regel=11`, 14,3 s, `fakta=uaendret bio_aendret=nej`) → `verify` (OK, budget OK).
  - fortryd-data → `T6D2A_FORTRYD_OK tilstand=ddl tal=10,9,0,0,1,2` (vagt `data` + `efter_ceremoni`) → `--saet` på
    foer-dumpet → fortryd-DDL → `T6D2A_FORTRYD_OK tilstand=foer` (3 funktioner droppet); `maal` derefter = før-tallene,
    BIO-hash tilbage på `3177a5d1…`.
  - Restorens fejl er de fire kendte (`current_rolle`, `media_object_synlig_anon`) + advarslen (`restore_fejl=5`).
  - Ingen fastlåst værdi afveg; runneren er uændret (sha `ac7cbd0d…`).
- **Appens sammenlægning** (Codex-fund 8; `collapseSameAs` fra `packages/core` på anon-data fra en prod-kopi med DDL
  og data):
  - 715 afklarede kanter og 9 karantænegrupper, både før og efter.
  - De 9 synlige oversigtspersoner foldes ind i deres detaljepersons kort, og ingen af de 11 komponenter er i
    karantæne.
  - 967 og 1014 er `staged`, så de har intet anon-kort. 1048 har sink 134 (uændret).
  - Alle 11 detaljepersoner leverer én kilde 3-biografi som anon; oversigtspersonerne leverer 0.

## Udestår før prod

1. ~~Prod-læsetrin (`maal`, `anon`, `dump-kopi`)~~ kørt 10/11; tal ovenfor.
2. ~~Generalprøve på frisk `dump-kopi`~~ `6d2ad` grøn 10/11.
3. Projektejerens valg om biografilæserens 13 s (rettes før eller efter 6d-2a).
4. Uafhængig review af runneren og grenen (Task 8) før GO i prod.
