# Runbook: trin 6d-3 i prod — 1939's relationer, dobbelt ægtefælle og 1791

Spec: `docs/superpowers/specs/2026-11-10-trin6d3-relationer-design.md`. Plan:
`docs/superpowers/plans/2026-11-10-trin6d3-relationer.md` (Task 8-9). Beslutning: `docs/decisions.md` 2026-11-10
»6d-3's afgrænsning«.
Runner: `~/.private/5ab-overfoersel/36-trin6d3.sh` med `36-trin6d3-vindue.sql` (aldrig i repoet), bygget som
`34-trin6d2a.sh`. Den kaldes via `/bin/zsh -f ~/.private/5ab-overfoersel/koer.zsh 36-trin6d3.sh <handling>` fra
operatørens cwd (ikke repo-roden). Alle linjer er kun antal, koder og hashes. Prod-skrivning (`apply-*`, `fortryd`)
sker kun i projektejerens shell med `--jeg-mener-det --go <kode>`. Hovedcheckouten skal være ren (også uden
usporede filer) og stå på den commit, GO er bundet til (`main` efter merge).

**Den bundne pakke** ligger i `~/.private/6d3/prod-pakke/` (mappen 0700, filerne 0600, sha'erne fastlåst i runneren,
og begge GO-koder binder dem alle):

| Fil | sha (16) | Hvad |
|---|---|---|
| `kortmanifest.json` | `85ead8a7b7e03c3d` | D/O-kortene (kontrakt `trin6d3-kortmanifest-v1`, kilde 3) |
| `kortsvar.json` | `59865ca2feee6038` | projektejerens svar: 42 × `S`, O1 = `P` (kontrakt `trin6d3-kortsvar-v1`) |
| `v1.json`, `v3.json` | `b640263116b10069`, `9110d77a85f5eaa8` | R's udtræksinput, som basen skal genskabe byte for byte |
| `persona-manifest.json` | `904f95d576500f64` | udtrækket med 1939-profilen (115 elementer) |
| `cand-input.json`, `candidates.json` | `06e41f3cd042ddac`, `9d98a7a26328e3da` | kandidatinput og generatorens uddata (generatoren køres ikke i prod) |
| `ctl-rows.json`, `ctl-ark.txt`, `ctl.sql` | `a6f60b5375895eb5`, `22b1cd51d4da9649`, `685615f0cd0465cf` | kontrolarkets rækker, det besvarede ark (22 ægtefællekort + forældrekortet) og arkets SQL |
| `candidates/control/corroborate/decide/bind.items` | `680fc400…`, `5d2f4fb2…`, `8b887d45…`, `ceac3e10…`, `5a7e8aa8…` | generalprøvens nøglede items; prod kører skridtene i **replay** mod dem |

Pakken er et udsnit af Task 6's filer (`~/.private/6d3/t6/`, `~/.private/6d3/kort/`). Items-filerne er nøglet på
indhold (`persona_key`, `interpretation_key`, version, familie- og person-id'er, der findes i prod før ceremonien).
Persona-, kandidat-, kontrolkørsels- og stikprøve-id'erne er `content_uuid`. Derfor giver en prod-kopi de samme filer:
rækkefilen `a6f60b53…` blev genskabt byte for byte på tre stand-ins.

## To GO-koder, tre data-handlinger

1. **DDL** (`go-ddl` → `apply-ddl`). Blokken `-- ===== trin 6d-3: relationsprofiler som data og tekstfoldning =====`
   og `db-rls.sql` køres i én transaktion med `lock_timeout 5s`. Den opretter én ny tabel,
   `private.relation_persona_profile`, med 4 seeds. Fire funktioner er nye (`relation_fold_raw_text`,
   `relation_name_compare_text`, `relation_ordered_windows(text,text,text)`, `relation_text_form`), og fem ændres.
   Alle ni er private uden EXECUTE for anon/authenticated (grant-matrix `------------------`). Efter DDL'en skal
   `FAMKILDER` være uændret.
2. **Data** (`go-data` → `apply-d` → `apply-o` → `apply-r`, samme kode til alle tre).
   - **D:** `samme_som_kort_ceremoni.sql` i én transaktion. Giver 42 `samme_som`, hvor 1939-rækken er alias.
   - **O:** `privat_kort_ceremoni.sql` i én transaktion. Sætter 1791 og 1795 private. Familierne 742/743 skal have
     familie-md5 `cbdb2d3b…` før skrivningen.
   - **R:** syv skridt, hvert med sin egen commit:
     1. persona-batch: writer-profil, autorisation og batch;
     2. kandidater;
     3. kontrolkørsel;
     4. kontrolark (to transaktioner: kontrolsvarene og forælderafgørelsen);
     5. korroboration;
     6. afgørelse;
     7. binding.

     Før hvert skrivende skridt genskaber runneren basens input og kræver det byte-ens med pakken (`T6D3_R_DRIFT`
     ellers). Skridt 2-3 og 5-7 kører `transfer_5ab_step_*.sql` i replay, og de stopper før RPC'en, hvis basens
     items afviger (`STEP_ITEMS_MISMATCH`).

**Vinduesvagten er en kæde af aftryk** (`data-<ddl-dump>/kaede.txt`). Hver data-handling kræver, at basen er lig
kædens seneste aftryk; det første aftryk er ddl-dumpets. Hvert skrivende skridt tager et nyt aftryk lige efter sin
commit eller fejl. Markøren `igang` står fra før skridtet skriver, til aftrykket er taget. Fortryd kræver basen lig
det seneste aftryk og ingen markør. Den accepterer altså ethvert præfiks af ceremoniens egne skrivninger og intet
andet (spec §6).

**Ingen genoptagelse.** Fejler et skridt efter en commit, er eneste vej at fortryde til ddl-dumpet, og så forsvinder D
og O også. D, O og R kan køres igen på samme ddl-dump, fordi alt er deterministisk og bundet. Derfor gælder to krav:

- **Meldt frys i prod fra `apply-d` til `verify` er færdig** (≈5-10 min). Ingen bogmærker, ingen redigeringer, heller
  ikke projektejerens egne. En fremmed skrivning stopper næste skridt og også fortrydelsen.
- **Slut-generalprøve på en frisk `dump-kopi` samme dag som prod** (trin 3b), med samme commit og pakke som prod. Den
  tages i fase `foer`, før `go-ddl`, så hele rækkefølgen (også DDL'en og `anon`-basis) øves på den. Drift mellem
  kopien og data-ceremonien fanges af runnerens førtjek: D/O's manifestkontrol, R's byte-sammenligning af input
  (`T6D3_R_DRIFT`) og replay-skridtenes items. Alle stopper før skridtets skrivning.

## Rækkefølge

| Trin | Handling | Forventet (generalprøven, stand-in `g3`) |
|---|---|---|
| 0 | Vercel deployer L (efter merge); browsertjek som anon | ingen synlig ændring uden 1939-bindinger |
| 1 | `maal` | `T6D3_MAAL fase=foer ddl=f forslag_k3=271/6/4 bundne_k3=0 samme_som=720 dobbelt=42 privat_1791=0 uden_position=59 K1_ORD=1857a95c… K1_BIND=9e0db348…` |
| 2 | `anon` | `T6D3_ANON_BASIS …` (basis gemt privat; `bio_alle` er over 3 s allerede før 6d-3, kendt backlog) |
| 3 | `dump` | `DUMP_6D3_OK tilstand=foer`, `EKSTERN_6D3_OK … rundtur=ok`, `DUMP_6D3_MAAL_OK … vindue_linjer=136` |
| 3b | slut-generalprøve: `dump-kopi` → `standin <kvittering> <suffiks>` → trin 1-4 og 6-8, 11-14 på stand-in'en (`DAA_STANDIN_DB`, `DAA_ENV_FILE`) fra en checkout af den mergede commit | alle linjer som her; ingen `T6D3_FASTLAAS`; stop ved enhver afvigelse |
| 4 | `go-ddl` → projektejeren `apply-ddl --jeg-mener-det --go <kode>` | `T6D3_VINDUE_OK mod=dump`, `T6D3_EFTER_DDL_GEMT …`, `T6D3_APPLY_DDL_OK tilstand=ddl blok=bf3e402b06f11ff2 seed=4:f87b9679…` |
| 5 | advisors (`get_advisors` security + performance, læse-kun) | ingen nye fund ud over de kendte |
| 6 | `maal` | `fase=ddl ddl=t … uden_position=10`, K1 og FAMKILDER som trin 1 |
| 7 | `anon` | `T6D3_ANON_BUDGET fase=ddl … OK` |
| 8 | `dump` | `DUMP_6D3_OK tilstand=ddl … vindue_linjer=137` (fortrydelsens grundlag) |
| 10 | **frys meldt** | |
| 11 | `go-data` → projektejeren `apply-d --jeg-mener-det --go <kode>` | `T6D3_KAEDE n=1 skridt=d status=ok`, `T6D3_D_OK links=42 ingen=0`, `T6D3_APPLY_D_OK fase=d tal=271/6/4,0,762,0,0,10` |
| 12 | `apply-o …` (samme kode) | `T6D3_VINDUE_OK mod=d:ok`, `T6D3_KAEDE n=2 skridt=o status=ok`, `T6D3_O_OK privat=2`, `T6D3_APPLY_O_OK fase=o tal=271/6/4,0,762,0,1,10` |
| 13 | `apply-r …` (samme kode) | se næste tabel; `T6D3_APPLY_R_OK fase=r tal=203/5/4,69,762,0,1,10` |
| 14 | `verify` | `T6D3_VERIFY_OK tal=203/5/4,69,762,0,1,10 k1_ord=1857a95c… k1_bind=9e0db348…`, `T6D3_ANON_BUDGET fase=r … OK` |
| 15 | frys ophævet; browsertjek som anon (Task 9 trin 4) | »DAA 1939« på et ægteskab hos en sammenfoldet person; én ægtefælle hos et D-par; Gabel/Hahn én ægtemand |

`apply-r`'s linjer (replay):

| Linje | Betydning |
|---|---|
| `T6D3_R_INPUT_OK v1.json` / `v3.json` / `persona-manifest.json` | basens udtræksinput og udtrækket = pakkens |
| `T6D3_R_SKRIDT persona {"person_creates": 0, "source_evidence": 0, "relation_personas": 115}` | persona-batchen |
| `T6D3_R_INPUT_OK cand-input.json`, `T6D3_R_SKRIDT candidates n=1096 items=6f6f8bcb… mode=replay` | kandidatkørslen |
| `T6D3_R_SKRIDT control n=22 items=d9c3ba05…` | kontrolkørslen: 22 stikprøvekort |
| `T6D3_R_INPUT_OK ctl-rows.json` / `ctl.sql`, `T6D3_R_SKRIDT kontrolark status=passed` | det besvarede ark passer på basens rækker; kontrollen bestået |
| `T6D3_R_SKRIDT corroborate n=46`, `decide n=68`, `bind n=69` | 46 maskinelle + 22 kort = 68 ægtefælleidentiteter; 68 ægteskaber + 1 forælder bundet |

**Tid** (stand-in): D 3,5 s, O 0,1 s, R 112 s (heraf vinduesaftryk ≈1 s pr. skridt), `maal` 11,6 s, et dump med mål
≈20 s, fortryd ≈20 s. Med 6d-2a's målte læsefaktor (≈3,4) ventes R på ≈6-7 min i prod. Hvert skridt sætter sin egen
`statement_timeout` (læsninger og R-skridt 30 min, D/O 15 min), så prods 2 min gælder ikke.

**Tidsbudgettet** (Review Focus 5). `anon` måler med samme metode som 6d-2a (median af 3, tærskel max(basis ×
1,10; basis + 20 ms)):

- biografilæseren med alle personer;
- `public_person_facts` for 199/529/289;
- `public_family_sources` for 309/298/364 (6d-2a's tunge, 2018-20) og for 386/390/392. Alle 69 nye kilder lander
  i hver sin 1939-familie (0 → 1 kilde, målt før-base mod `g2`); de tre er nogle af dem.

Kaldet over alle offentlige familier (`famsrc_alle`) vokser med antallet af kilder: R tilføjer 69, så 259 bliver
til 328 kilder og tiden går fra 1100 til 1400 ms på stand-in. Det sammenlignes derfor som µs pr. returneret kilde
(4228 før, 4212 efter). Læseren kalder aldrig funktionen med alle familier, kun med én persons familier.

## Fastlåste værdier og deres kilder

- `T6D3_BLOK=bf3e402b…` er blokken skåret fra grenens `db-migrations.sql`. `T6D3_RLS=a21d5034…` er grenens
  `db-rls.sql`. `T6D3_RLS_FOER=16ac093b…` er `db-rls.sql` ved merge-basen `aafbbcfb` (= prods, 6d-2b).
- `M[foer|ddl|d|o|r]`, `K1_ORD`, `K1_BIND`, `FAMILIE_MD5`, `R_PERSONA`, `PROFIL_SEED`, grant-matrixen og items er
  målt på stand-ins fra prods `dump-kopi` 10/11 (`g1`, `g2`). De er efterprøvet uændret på `g3` og stemmer med Task
  0/6/7's målinger: før `59/720/42`, efter D `762`/`0`, R `68`+`1`. K1 er ens i alle faser.
- `FAMKILDER` er en rækketekst-hash. Den fastlåses ikke, men sammenlignes inden for samme base: uændret af DDL'en og
  lig ddl-dumpets ved `apply-d`.
- Fortryd-DDL's katalogdiff skal være præcis tabellen `private.relation_persona_profile` (kolonner, nøgle, checks) og
  de fire nye funktioner. Tabellens indhold skal være de 4 seeds (`4:f87b9679…`).

## Stoppunkter

| Linje | Betyder | Gør |
|---|---|---|
| `MAAL_6D3_UKENDT` / `T6D3_*_FASE` | prod er ændret siden generalprøven, eller fasen er en anden end ventet | `maal`; ny `dump-kopi` og generalprøve |
| `T6D3_VINDUE_BRUDT_FOER_DDL` / `_FOER_D` | prod er skrevet siden dumpet | intet kørt; `dump` igen |
| `T6D3_VINDUE_BRUDT_FOER_O` / `_FOER_R` | en fremmed skrivning efter D/O (frysen er brudt) | intet kørt. **Fortryd stopper også** (`T6D3_VINDUE_BRUDT`), fordi en restore ville slette skrivningen. Stop og vurdér med Claude: enten fjernes skrivningen (den er kendt og ejeren enig), eller den bevares og fortryd laves i hånden |
| `T6D3_PAKKE_SHA` / `T6D3_PAKKE_KAEDE` | en pakkefil er ændret | intet kørt; genskab filen fra `~/.private/6d3/` og efterprøv sha'en |
| `T6D3_R_DRIFT (<fil>)` | basens genskabte input afviger fra pakkens (før skridtets skrivning) | D, O og tidligere R-skridt er committet: fortryd til ddl-dumpet; undersøg afvigelsen på en `dump-kopi` |
| `DDL_6D3 fejlede …; rullet tilbage` | intet ændret (målt) | ret årsagen; `dump` er stadig gyldigt |
| `DDL_6D3_FEJL_EFTER_COMMIT` | blokken er committet; aftrykket efter DDL'en er gemt | `maal` + `anon`, eller fortryd-DDL |
| `T6D3_EFTER_DDL_FAMKILDER` | DDL'en ændrede familiekilderne | fortryd-DDL |
| `T6D3_ANON_BUDGET_BRUDT` (trin 7) | et kald er over budget | stop før data; `anon` igen (støj?), ellers fortryd-DDL |
| `T6D3_CEREMONI_FEJL (d\|o: T6D3_PRE_…)` | intet skrevet, men kæden har et `fejl`-aftryk | `dump` igen (ny kæde) eller fortryd; prod afviger fra manifestet: nyt kort, ingen genkørsel |
| `T6D3_CEREMONI_FEJL (… T6D3_POST_…)` / `T6D3_R_FEJL (…)` | skridtet fejlede; kæden har aftrykket | fortryd til ddl-dumpet |
| `T6D3_KAEDE_FINDES` / `T6D3_R_PAABEGYNDT` / `T6D3_*_KAEDE` | en data-ceremoni er allerede kørt på dette dump (ingen genoptagelse) | intet kørt; fortryd, eller `dump` igen, hvis intet er committet |
| `T6D3_KAEDE_IGANG` | et skridt har skrevet uden efterfølgende aftryk (runneren blev afbrudt) | intet kørt; stop og vurdér med Claude. Genskab IKKE aftrykket i hånden i prod: det ville godkende skrivninger efter skridtet |
| `T6D3_FORTRYD_KATALOG_AENDRET(_EFTER_DDL)` | en funktion er ændret siden dumpet/DDL'en | intet restoret |

## Fortrydelse (kun under meldt frys)

- **Data, fra ethvert præfiks** (efter D, efter O, midt i R, efter R): `DAA_T6D3_DUMP` står i go-env efter trin 8 →
  `go-fortryd` → projektejeren `fortryd --jeg-mener-det --go <kode>`. Kræver:
  - basen lig kædens seneste aftryk (`T6D3_VINDUE_OK mod=<skridt>:<status>`) og ingen `igang`-markør;
  - alle change_sets siden dumpet fra ceremoniens aktør;
  - kataloget som i ddl-dumpet.

  Restoren efterprøves mod dumpets restore-hash, ACL, default-ACL, katalog, målelinje, K1 og FAMKILDER. Kædens mappe
  omdøbes til `data-<dump>.fortrudt-<tid>`, så D-O-R kan køres igen på samme ddl-dump.
- **DDL** (kun efter fortryd-data, basen i fase `ddl`): `koer.zsh --saet DAA_T6D3_DUMP=<foer-dumpets kvittering>` →
  `go-fortryd` → `fortryd`. Kræver:
  - ingen change_sets siden foer-dumpet;
  - basens rækker lig aftrykket lige efter `apply-ddl` (sekvenser må afvige);
  - kataloget lig aftrykket efter `apply-ddl`;
  - katalogdiffen præcis 6d-3's nye objekter, og profiltabellen = seeds.

  Fortrydelsen dropper tabellen og funktionerne, restorer og genanvender `db-rls.sql` fra `aafbbcfb`.
- `db-verify.sql` køres ikke mod prod eller prod-kopier. Den kræver dblink og indsætter sine egne testdata. Den kørte
  grønt i CI og i Task 5's opgraderingstest. Beviset for en fortrydelse er runnerens lighedstjek mod dumpet.

## Generalprøven 11/11

Fra prods `dump-kopi` 10/11 (`daa-prod-20261110214135-6d2a-kopi.dump`, sha `f10943f4…`). Kørt fra `$HOME` med en ren
worktree af commit `3eab65d1` som `DAA_STANDIN_REPO`.

- `g1` (`daa5ab_ddl_standin_20261111154455_g1`), iteration. Fastlåste `foer`, `ddl`, `d`, `o`, K1, blok, RLS,
  seeds, grants og katalogdiff. To runnerfejl blev fundet og rettet:
  - Kontroltjekket kaldte `control_run_status` uden redaktørens claim.
  - Fortryd-data flyttede kun `kaede.txt`, så næste D fandt et gammelt aftryk og stoppede efter sin commit. Det var
    fail-closed: markøren stod, og fortryd nægtede (`T6D3_KAEDE_IGANG`). Rettet: hele kædens mappe omdøbes, og
    aftrykskollisionen tjekkes før skrivningen.

  Fortryd fra præfikset `r-kontrolark` blev også prøvet her (OK). `g1` står i fase `d` med markør og må ikke bruges.
- `g2` (`daa5ab_ddl_standin_20261111155540_g2`), den rene vej i capture. Hele kæden gik igennem med 115 / 1096 / 22
  / passed / 46 / 68 / 69, og items blev lagt i pakken. `verify` fandt `famsrc_alle` +27 % (rækkeantal; se
  tidsbudgettet), og målet blev ændret til µs pr. kilde. `g2` står i fase `r`.
- `g3` (`daa5ab_ddl_standin_20261111160349_g3`), den rene vej i **replay** med alle værdier fastlåst:
  `maal` → `anon` → `dump` → `apply-ddl` → `maal` → `anon` (OK) → `dump` → `apply-d` → `apply-o` → `apply-r` (alle
  items = pakkens) → `verify` (OK, budget OK).
  - Fortryd fra fem præfikser, hver gang tilbage til ddl-dumpets restore-hash `5ed3f37a…` og `maal` = `ddl`:
    1. efter fuld R;
    2. efter D;
    3. efter D+O;
    4. midt i R efter autorisationen, før batchen (`DAA_T6D3_TEST_FAULT=efter_autorisation`; aftrykket viste kun
       writer-profil + autorisation);
    5. midt i R efter persona-batchen (`DAA_T6D3_TEST_STOP=persona`).
  - Fortryd-DDL bagefter: katalogdiffen præcis tabellen og de 4 funktioner, restore-hash = foer-dumpets
    `b23c1de6…`, `maal` = `foer`, `anon` inden for ±3 % af den første basis.
  - Negativer, alle uden skrivning:
    - forkert GO (`GO_MISMATCH`);
    - manglende flag og `--go` uden `--jeg-mener-det`;
    - ukendt argument (`--dryrun`);
    - testflag uden stand-in;
    - `apply-ddl` på et ddl-dump (`DUMP_6D3_TILSTAND`);
    - gentaget `apply-d` (`T6D3_D_FASE`);
    - ændret svarfil (`T6D3_PAKKE_SHA`; filen er lagt tilbage, og sha'en er efterprøvet);
    - et bogmærke efter D: `apply-o` → `T6D3_VINDUE_BRUDT_FOER_O`, og `fortryd` → `T6D3_VINDUE_BRUDT`, så bogmærket
      blev bevaret.

    `g3` står i fase `d` med det ekstra bogmærke.
- **Læsermodellen** (`collapseSameAs` fra `packages/core` på anon-data; før = prod-kopien før DDL, efter = `g2`):
  - Karantænegrupper: 9 → 9.
  - Personer med 2+ ægtefæller: 98 → 60.
  - De 42 D-kort (41 hovedpersoner, én med to kort) mister hver præcis den dobbelte ægtefælle.
  - Gabel/Hahn (815/816) går fra 2 til 1 ægtemand, og 1791 er usynlig for anon.
  - Læsergaten passer: kilderne stiger med præcis 69 (259 → 328).
- `g4` (`daa5ab_ddl_standin_20261111163901_g4`), runnerens fejlgrene (efter rådgiverens review). Først sattes
  budgetfamilierne til 386/390/392, og fejlgrenen `DDL_6D3_FEJL_EFTER_COMMIT` gemmer nu også katalogaftrykket.
  - **O-før-fejl:** 1795 sat privat før ddl-dumpet. D gik igennem, og O stoppede med
    `T6D3_PRE_MANIFEST kort O1 (privat)` uden at skrive (kæden fik `o fejl`).
  - **Genkørsler afvist:** `apply-o` → `T6D3_O_KAEDE`; `apply-r` → `T6D3_R_FASE`.
  - **Fortryd:** OK fra præfikset `d ok, o fejl`.
  - **R-skridtfejl:** `fault=before_commit` på `decide` (`DAA_T6D3_TEST_STEP_FAULT=decide`) gav
    `T6D3_R_FEJL (decide: STEP_FAULT)`. Aftrykket var lig korroborationens (rullet tilbage), og fortryd gik OK.
  - **Ren vej:** D → O → R → `verify` OK.
    - Tidsbudget: 2018-20-kaldene og `famsrc_alle` pr. kilde er uændrede (4214/4323 µs).
    - De tre 1939-familier gik fra 10 til 14-17 ms, inden for støjgulvet (+20 ms).
    - Fejlteksten ved en ceremonifejl skelner nu mellem fase `ddl` (intet committet: dump igen) og senere (fortryd).

## Udestår før prod

1. Prod-læsetrin `dump-kopi` (projektejerens shell; auto-mode-klassifikatoren afviser den som [Production Reads]) og
   slut-generalprøve på den (trin 3b). Afviger prods `maal` fra `foer`-linjen, er prod ændret siden 10/11, og pakken
   skal måles igen.
2. Codex-review af hele grenens diff og af runneren (Task 9 trin 1), **før** slut-generalprøven: i 6d-2a ændrede
   reviewet runneren og gjorde generalprøven ugyldig.
3. Push, draft-PR, CI, merge, Vercel (Task 9 trin 2).
4. **Hovedcheckouten skal være ren**: `go-*` stopper med `REPO_DIRTY` ved usporede filer. I repo-roden ligger 23
   usporede CI-uddatafiler (`parity-*.txt`, `reimport*.out/json`, 622 KB). De skal flyttes (karantæne, målt først)
   efter projektejerens ja.
5. **Budgettet for 1939-familierne** (386/390/392): de går fra 0 til 1 kilde og fra 10 til 14-17 ms på stand-in.
   Prods familiekald er målt til ≈5 × stand-in, så +35-40 ms i prod vil overskride max(basis × 1,10; basis + 20 ms).
   `verify` vil da melde `T6D3_ANON_BUDGET_BRUDT`, efter at data er committet. Projektejeren beslutter før prod, om
   de tre kald skal være informative (kaldet laver mere arbejde, fordi der nu er en kilde) eller bindende.
