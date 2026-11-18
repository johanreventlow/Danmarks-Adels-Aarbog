# Runbook: record_persona i prod — Henrik og Iven (1939) får deres egen tekst som kladde

Spec: `docs/superpowers/specs/2026-11-17-persona-for-post-uden-tekst-design.md` (§6 vejen til prod, §8 færdigbevis).
Plan: `docs/superpowers/plans/2026-11-17-persona-for-post-uden-tekst.md` (Task 5).

Runner: `~/.private/5ab-overfoersel/42-record-persona.sh` med `42-record-persona-vindue.sql` (aldrig i repoet), bygget
som `34-trin6d2a.sh` med `40-trin6e2.sh`'s kopi-tjek, vindue-handling og katalogdiff. Den kaldes fra operatørens cwd:

```
env -u PGOPTIONS /bin/zsh -f ~/.private/5ab-overfoersel/koer.zsh 42-record-persona.sh <handling> [--jeg-mener-det --go <kode>]
```

- Alle linjer er kun antal, koder og hashes; posttekst, navne og aktør-uuid står kun i 0600-filer.
- Prod-skrivning (`apply-*`, `fortryd*`) sker kun i projektejerens shell med `--jeg-mener-det --go <kode>`.
- Hovedcheckouten skal være ren og stå på den commit, GO er bundet til (`main` efter merge).
- Kortpakken ligger i `~/.private/record-persona/` (mappen 0700, filerne 0600, sha'erne fastlåst i runneren):
  `kortmanifest.jsonl` (`20b4a68d…`), `kort-svar.txt` (`c753aea9…`) og `note72_ddl.sql` (`532d5ded…`). Runneren tjekker kæden: svarfilens første
  linje bærer manifestets sha, manifestet har præcis posterne `record-e63debca…` → 934 og `record-9db9004f…` → 929,
  og hvert kort har præcis ét `J` for identitet og placement (et `N` stopper). Målingen læser manifestet i alle faser.
- **Alle fire GO-koder** binder commit'en, halen (sha), `record_persona_ceremoni.sql`, `maal_record_persona.sql`,
  begge `db-rls.sql`-versioner (grenens og basecommittens `f37b294a`), manifest, svar, runneren, vinduesvagten,
  `lib.zsh`, `koer.zsh` og `rollback-preflight.sql`. `go-fortryd*` binder desuden dumpets kvittering.

## To ceremonier

1. **DDL** (`apply-ddl`): `db-migrations.sql` fra separatorlinjen lige før `-- Fuld personsletning (2026-11-14)` til
   filens slutning, + `db-rls.sql`, i én transaktion med `lock_timeout 5s`.
   - Halen rummer **personsletningens blokke** og som sidste blok `-- ===== record_persona: persona for helpost uden
     tekst =====` (operationen `record_persona`, writeren, autorisationens tællinger og spærringen af fortrydelsen af
     `legacy_withdrawn`).
   - **Personsletningens kode kommer med i prod** (projektejerens afgørelse). Den sover, til dens egen ceremoni. To
     nye tabeller (`private.person_purge_manifest`, `private.person_purge_udbakke`), nye triggere på eksisterende
     tabeller (`trg_polymorf_*` m.fl.) og ca. 46 funktioner, inkl. #380's udbakke og genbrugstriggere. Personsletningens
     session er orienteret (18/11) og venter: **giv den besked med den deployede commit og halens sha** efter
     `apply-ddl` (dens Task 13 bliver ren data).
   - **Note 72** (forældreløs: `target_type='family'`, `target_id=54`; familie 54 findes ikke) slettes i samme
     transaktion efter halen og `db-rls.sql` (`note72_ddl.sql`, projektejerens afgørelse 18/11). Forbetingelsen er
     `db-verify.sql`'s `$purge_verify_polymorf$` (main f9a38018): præcis ét fund, `note.target_type=family:1`, ellers
     `NOTE72_FORBETINGELSE` og alt rulles tilbage; sletningen skal ramme præcis én række (`NOTE72_SLET`). Uden
     change_set logger `log_change` ikke sletningen. Fortryd-DDL (restore af foer-dumpet) bringer noten tilbage.
   - Runneren skærer halen selv, efterprøver at begge overskrifter står præcis én gang i filen, at record_persona-
     overskriften står i halen, og at halen ikke har `BEGIN;`/`COMMIT`/`ROLLBACK`/psql-metakommandoer. Halen og
     `db-rls.sql` køres som sha-tjekkede kopier.
   - Kontrol efter: fase `ddl`, FAKTA/BIO/KOORD_2018_20 uændrede, grant-matrixen, katalogdiffen mod foer-dumpet og
     vinduet (kun de fastlåste tabeller/sekvenser). Katalogets aftryk lige efter DDL'en gemmes til fortryd-ddl.
2. **Data** (`apply-data`): ét kald af `record_persona_ceremoni.sql` (src=3, profil `daa-1939-publication-v1`) i ÉN
   transaktion (ceremonien sætter selv `statement_timeout 15min`). Ceremonien skriver to personas, identiteterne
   934/929, record- og persona-placements, ledger, medlemskab og til sidst de to kladder (status draft), og kvitteringen
   (change_set `record_persona_ceremoni` på kilden). Ethvert ugyldigt svar eller en afvigende førtilstand stopper før
   authorize; en fejl ruller alt tilbage. Aktøren skal være projektejerens redaktionsprofil i `auth.users`
   (`T_RP_AKTOER`).

## Rækkefølge

| Trin | Handling | Forventet |
|---|---|---|
| 1 | `maal` | `T_RP_MAAL fase=foer personas=0 identiteter=0 placements=0 kladder=0 eligible=0 header_violations=0 synlige_1939=565 …`, `T_RP_MAAL_OK tilstand=foer` (tal = `M[foer]`, fastlåst i generalprøven) |
| 2 | `anon` | `T_RP_ANON_BASIS …` (prods egen basis, gemt privat); evt. `T_RP_ANON_OVER_3S …` |
| 3 | `dump` | `DUMP_RP_OK tilstand=foer`, `EKSTERN_RP_OK … rundtur=ok`, `DUMP_RP_MAAL_OK …`, `DAA_TRP_DUMP=…` |
| 4 | `dump-kopi` | `DUMP_RP_KOPI_OK …` (ukrypteret stand-in-kilde af samme tilstand; til at genskabe prod lokalt ved fejl) |
| 5 | **meld frys**; `go-ddl` | `T_RP_PAKKE_OK filer=3 kort=2`, `hale=… rls=… rls_foer=… ceremoni=… maal=…`, `manifest=20b4a68d9f71b634 svar=c753aea96f3af955`, `GO_RP_DDL_KODE=…` |
| 6 | projektejeren `apply-ddl --jeg-mener-det --go <kode>` | `T_RP_VINDUE_OK sammenligning=eksakt`, `B1_RP_OK tilstand=foer …`, `T_RP_KATALOG_EFTER_DDL_GEMT …`, `T_RP_VINDUE_AFVIGER sammenligning=ddl navne=<RP_VINDUE_UDELAD_DDL>`, `T_RP_APPLY_DDL_OK tilstand=ddl hale=<RP_HALE[1,16]>` |
| 7 | advisors (security + performance, læse-kun) | ingen nye fund ud over de kendte (memory `koer-get-advisors-efter-ddl`) |
| 8 | `maal` | `fase=ddl`, tal = `M[ddl]` (som foer), KOORD som foer |
| 9 | `anon` | `T_RP_ANON_BUDGET fase=ddl … OK …` (ingen kald over max(basis × 1,10; basis + 20 ms)) |
| 10 | `dump` | `DUMP_RP_OK tilstand=ddl` (data-dumpet; fortryd-datas grundlag) |
| 11 | `dump-kopi` | som trin 4 |
| 12 | `go-data` | samme sha-linje og pakke-linje, `GO_RP_DATA_KODE=…` |
| 13 | projektejeren `apply-data --jeg-mener-det --go <kode>` | se næste tabel |
| 14 | `verify` | `T_RP_VERIFY_OK tal=2,2,2,2,2,0,565 laeser=<RP_VERIFY> … fakta=uaendret bio=uaendret` |
| 15 | `anon` | `T_RP_ANON_BUDGET fase=data … OK …`; **meld frys ophævet** |

`apply-data`'s linjer:

| Linje | Betydning |
|---|---|
| `T_RP_VINDUE_OK sammenligning=eksakt` | intet i `public`/`private` er ændret siden data-dumpet |
| `T_RP_DATA_START fase=ddl kort=2 tal=0,0,0,0,0,0,565 profil=…` | forventningerne; profilens sha = `RP_PROFILE_SHA` |
| `T_RP_CEREMONI_TID saetninger=… maks_s=… sum_s=…` | `\timing` fra ceremonien |
| `T_RP_OK personas=2 identiteter=2 placements=2 medlemskab=2 kladder=2` | ceremoniens kvittering (fastlåst) |
| `T_RP_VINDUE_EFTER_GEMT linjer=… sha=…` | aftrykket lige efter COMMIT (fortryd-datas vagt) |
| `T_RP_CS_OK anker=1 andre=0 i_alt=<RP_E_CS>` | alle change_sets efter dumpet er ceremoniens transaktion |
| `T_RP_VINDUE_AFVIGER sammenligning=data navne=…` + `T_RP_VINDUE_OK sammenligning=data` | rækker afviger kun i ceremoniens tabeller |
| `T_RP_APPLY_DATA_OK fase=data tal=2,2,2,2,2,0,565 … fakta=uaendret bio=uaendret` | KOORD_SRC ændret (kun 929/934); FAKTA, BIO, KOORD_2018_20 og de synlige tekster uændrede |

`verify`'s `laeser=` er syv tal: kladder for 934 og 929 i redaktørens liste (status `draft`, manifestets post),
`legacy_withdrawn`-hændelser for 934 og 929 med `NARRATIVE_LEGACY_RECORD_BINDING_EXISTS` (fortrydelsen af 598/603
afvises), 944's narrativ som oversigtsomtale for 44/929, og anon's kilde 3-rækker på komponenterne 2/934 og 44/929.
Forventet før publiceringen: `1 1 ≥1 ≥1 0 <før> <før>` (fastlåses i generalprøven som `RP_VERIFY`).

## Efter verify: projektejeren publicerer (uden for vinduet)

1. Projektejeren åbner 934 og 929 i redaktøren, retter OCR-fejlene i kladderne (»1ll«, »r. 1ven«, »lwanus« m.fl.) og
   publicerer begge. Det er ikke en del af ceremonien.
2. **Med publiceringen lukker fortryd-data**: hans change_sets har et andet `created_at` end ceremoniens
   (`T_RP_FORTRYD_CS_IKKE_CEREMONIENS`), og aftrykket efter ceremonien passer ikke længere
   (`T_RP_VINDUE_BRUDT_EFTER_CEREMONI`). En fejl efter publiceringen rettes i redaktøren eller med en ny ændring, ikke
   med restore.
3. `bevis` (læse-kun) og `anon` måler færdigbeviset (spec §8). Tallene nedenfor er spec'ens forventning, ikke målinger;
   generalprøven fastlåser de målte:
   - `T_RP_MAAL fase=data … kladder=0 … synlige_1939=566` → `tilstand=publ` (565 + 2 − 1: Henriks og Ivens tekster
     kommer til, 944's korte omtale udelades som oversigtsomtale).
   - `T_RP_BEVIS_OK … laeser=1,1,≥1,≥1,1,1,1` (fastlåses som `RP_BEVIS` på en simuleret publicering i generalprøven):
     begge publiceret, fortrydelsen af 598/603's tilbagetrækning stadig spærret, 944 nu oversigtsomtale, én kilde
     3-tekst på hver komponent.
   - `T_RP_ANON_BUDGET fase=publ … OK`.
   - Browsertjek som anon: Hinrichs (2) og Iwans (44) side viser 1939-teksten som 1939-udgaven med »DAA 1939,
     s. 9-10« og »DAA 1939, s. 10«; 598 og 603 vises ikke.

## Fastlåste værdier og deres kilder

Runneren afviser prod, hvis en fastlåst værdi mangler (`T_RP_IKKE_FASTLAAST`; kun `anon`, `vindue` og `dump-kopi` er
undtaget). På en stand-in udskrives tomme værdier som `T_RP_FASTLAAS navn=værdi`.

| Værdi | Kilde |
|---|---|
| `PAKKE_SHA` (manifest `20b4a68d…`, svar `c753aea9…`), posterne → 934/929 | kortrunden; spec §2 |
| `RP_HALE`, `RP_RLS`, `RP_CEREMONI_SHA`, `RP_MAALSQL_SHA` | filerne i `main` efter merge; generalprøven udskriver dem (`T_RP_FASTLAAS`). Genpinnes, hvis review eller merge ændrer filen |
| `RP_RLS_FOER` | `git show f37b294a:db-rls.sql` (prods SQL-basis) |
| `RP_PROFILE_SHA` | `private.reimport_writer_profile` (kilde 3, `daa-1939-publication-v1`); målt af `apply-data` på stand-in'en |
| `RP_HEADER_RULE` | overskrifternes `extraction_run.run_key` (6d-1); på stand-in'en givet som `DAA_LOCAL_RP_HEADER_RULE` |
| `M[foer/ddl/data/publ]`, `KS[…]`, `RP_KOORD_ANDRE` | `maal` i hver fase i generalprøven; `publ` efter en simuleret publicering |
| `RP_OK` | ceremoniens kvittering (kontrakten fra Task 4) |
| `RP_E_CS` | change_sets i ceremoniens transaktion (generalprøven) |
| `RP_GRANTS` | grant-matrixen efter DDL'en for `RP_GRANT_FN` (generalprøven) |
| `RP_DDL_KATALOG_DIFF` | katalogdiffen mod foer-dumpet efter DDL'en (generalprøven) |
| `RP_VINDUE_UDELAD_DDL` | halens egne rækkeændringer + de sekvenser, en tilbagerullet data-ceremoni rykker (generalprøvens fejlvej) |
| `RP_VINDUE_UDELAD_DATA` | ceremoniens tabeller og sekvenser (generalprøven) |
| `RP_VERIFY`, `RP_BEVIS` | `verify` og `bevis` i generalprøven |

FAKTA og BIO er rækketekst-hashes og afhænger af basens locale (memory `row-text-hash-afhaenger-af-locale`). De
fastlåses ikke, men sammenlignes kun inden for samme base: før/efter i samme handling og mod ddl-dumpets kvittering.

**Tidsbudgettet** (spec §5: intet anon-kald mere end 10 % langsommere). `anon` måler koordinat-RPC'en og
biografilæseren v2 for komponenterne 2/934 og 44/929 og for en uberørt person (392). Hvert kald køres tre gange, og
medianen bruges. Fase `foer` gemmer basis **på samme base** (prods egen i prod), senere faser sammenlignes med den.
Tærsklen er max(basis × 1,10; basis + 20 ms). Anon's 3 s løftes til 120 s under målingen; kald over 3 s meldes som
`T_RP_ANON_OVER_3S` og er ikke en fejl her.

## Stoppunkter

| Linje | Betyder | Gør |
|---|---|---|
| `T_RP_MAAL_UKENDT` i trin 1 | prod er ændret siden generalprøven | ny `dump-kopi`, ny `standin`, generalprøve igen |
| `T_RP_PAKKE_SHA` / `T_RP_PAKKE_KAEDE` | pakken er ændret eller binder ikke | intet kørt; læg den godkendte pakke tilbage |
| `T_RP_HALE_*` | halen er ikke den fastlåste, eller den har transaktionsstyring | intet kørt; tjek commit |
| `T_RP_VINDUE_BRUDT_FOER_*` | prod er skrevet siden dumpet | intet kørt; tag `dump` igen |
| `T_RP_KATALOG_FOER_DDL` | kataloget er ændret siden foer-dumpet | intet kørt; tag `dump` igen |
| `DDL_RP fejlede (…); rullet tilbage (maalt: fase foer)` | intet ændret | ret årsagen; `dump` er stadig gyldigt |
| `DDL_RP_FEJL_EFTER_COMMIT` | halen er committet (fase ddl) | `maal` + `anon`, eller fortryd-ddl |
| `DDL_RP_UAFKLARET` / `T_RP_CEREMONI_UAFKLARET` | fasen kunne ikke måles | `maal` før noget andet |
| `NOTE72_FORBETINGELSE: <fund>` / `NOTE72_SLET` | prod har andre forældreløse rækker, eller note 72 er ændret | rullet tilbage (fase foer); vurdér med personsletningens session |
| `T_RP_EFTER_DDL_*` (FAKTA, BIO, KOORD, grants, katalog, vindue) | DDL'en er committet, men gjorde mere end ventet | stop før data; vurdér med Claude, ellers fortryd-ddl |
| `T_RP_ANON_BUDGET_BRUDT` | et kald er over budget | kør `anon` igen (støj?); vedvarende efter DDL: stop før data, ellers fortryd-ddl |
| `T_RP_CEREMONI_FEJL (T_RP_PRE_…)` | intet skrevet (fase ddl) | prod afviger fra manifestet: nyt kort/manifest, ingen genkørsel |
| `T_RP_CEREMONI_FEJL (T_RP_POST_KOORD_ANDRE_ANON)` | en anden kildes anonyme koordinater ændrede sig under ceremonien (fx en samtidig synlighedsændring) | rullet tilbage; frysen er brudt — find årsagen, `dump` igen |
| `T_RP_CEREMONI_FEJL (T_RP_WRITE_…/T_RP_POST_…)` | rullet tilbage (fase ddl); sekvenserne kan være rykket | `dump` igen før næste `apply-data` |
| `T_RP_CEREMONI_FEJL_EFTER_COMMIT` | committet (fase data) | `verify`, eller fortryd |
| `T_RP_DATA_FAERDIG` | ceremonien er kørt | `verify` |
| `T_RP_VINDUE_EFTER_FINDES` | en ceremoni har allerede committet på dette ddl-dump (og er fortrudt) | intet kørt; `dump` igen |
| `T_RP_VINDUE_EFTER_MANGLER` i fortryd | basen står i data, men aftrykket efter ceremonien mangler | intet restoret; stop og vurdér med Claude (genskab IKKE aftrykket i hånden i prod) |
| `T_RP_FORTRYD_KATALOG_AENDRET_EFTER_DDL` / `…_EFTER_DDL_MANGLER` | kataloget er ændret siden `apply-ddl`, eller aftrykket mangler | intet rørt |
| `T_RP_FORTRYD_DDL_UKENDT_OBJEKT` / `…_TABEL_IKKE_TOM` | katalogdiffen har et objekt, drop-planen ikke kender, eller en ny tabel har rækker | intet droppet |
| `T_RP_FORTRYD_IGANG` | en fortrydelse er påbegyndt (markør) | stop; vurdér med Claude |

## Negativer (Step 4: stopper før enhver skrivning)

| Forsøg | Kode | Hvor |
|---|---|---|
| forkert GO-kode | `STOPPORT: T_RP_GO_MISMATCH (…)` | `assert_go`, før forbindelsen |
| GO-kode i forkert form | `FEJL: T_RP_GO_FORM (…)` (exit 2) | argumenterne |
| manglende `--jeg-mener-det` eller `--go` | `FEJL: T_RP_FLAG_MANGLER (…)` (exit 2) | argumenterne |
| gentaget `apply-data` | `STOPPORT: T_RP_DATA_FAERDIG (…)` | første måling efter GO; intet skrevet |
| ændret svarfil | `STOPPORT: T_RP_PAKKE_SHA (kort-svar.txt) (…)` | `pakke_tjek`, før GO og forbindelsen |

## Fortrydelse (kun under meldt frys)

Kvitteringen vælges med `koer.zsh --saet DAA_TRP_DUMP=<kvittering>`; uden den tager runneren det nyeste dump i den
krævede fase. `go-fortryd*` viser kvitteringens fase og sha og binder den i koden.

- **Data** (`go-fortryd` → projektejeren `fortryd --jeg-mener-det --go <kode>`): restore af ddl-dumpet + grenens
  `db-rls.sql` (kopi, sha-tjekket). Kræver, at alle change_sets siden dumpet er ceremoniens transaktion (kvitteringen og
  samme `created_at`), at kataloget er uændret, og at hele basen er lig aftrykket lige efter ceremonien. Kun indtil
  projektejeren publicerer (se ovenfor).
- **DDL** (kun efter fortryd-data, basen i fase `ddl`; `go-fortryd-ddl` → `fortryd-ddl --jeg-mener-det --go <kode>`):
  - Kræver 0 change_sets siden foer-dumpet, katalogdiffen lig `RP_DDL_KATALOG_DIFF` og kataloget lig aftrykket fra
    `apply-ddl`.
  - Drop-planen bygges af katalogdiffen og droppes i én transaktion: nye/ændrede triggere, politikker og constraints
    på eksisterende tabeller, nye indeks, de nye tabeller (skal være tomme) og de nye funktioner.
  - Derefter restore af foer-dumpet og `db-rls.sql` **som ved basecommitten `f37b294a`** (hentet fra git og
    sha-tjekket mod `RP_RLS_FOER` før markøren). Grenens udgave nævner funktioner, restoren har fjernet (memory
    `fortryd-ddl-rls-foer-grenen`).
  - Fortryd-DDL tager også personsletningens kode ud af prod: giv den anden session besked.
- Begge: vinduesvagten lige før markøren (et bogmærke e.l. efter dumpet stopper uden markør), låsetjek, restore,
  default-ACL og grants afstemt, og bevis bagefter: ACL, katalog og restore-hash som dumpets, fasen som dumpets.

## Kendte forhold

- **»Slet helt« må ikke bruges** i Redaktion fra `apply-ddl` til personsletningens egen ceremoni (Task 13) er kørt.
  Efter DDL'en virker knappen og sletter en person helt; sletningen har endnu ikke haft sin egen generalprøve mod
  prod-data. Gælder også oplagte fejlpersoner som 1791.
- Fortrydelse af en `legacy_withdrawn`/`legacy_migrated`-hændelse kræver nu `READ COMMITTED`
  (`NARRATIVE_LEGACY_REVERSAL_ISOLATION`); appen kører altid sådan, kun en direkte SQL-session kan ramme koden.
- Ceremonien holder `ACCESS EXCLUSIVE` på `change_set`, mens POST regner FAKTA/BIO/KOORD som anon; redaktørskrivning
  venter imens (meldt frys).

- **Halen er ikke hele forskellen til `f37b294a`.** Tre linjer før halen er også ændret: to `to_regprocedure`-
  indgange i `$public_red_revoke$`-listen (`red_apply_reimport_record_persona`, `red_slet_person_helt[_preview]`) og
  en tom linje. De køres ikke med halen; grants for de nye funktioner kommer fra halen selv og fra `db-rls.sql`. En
  senere fuld genkørsel af `db-migrations.sql` kører dem.
- `maal` skelner `data` (kladder 2) og `publ` (kladder 0) på kladdetallet; en halv publicering giver `ukendt`.
- En fejl efter DDL'en og før data viser ikke noget nyt for læseren: halen ændrer ingen læser (FAKTA/BIO/KOORD
  efterprøves).

## Generalprøven (18/11)

Kilde: prod-`dump-kopi` 20261118114316 (sha `19bb7cd7…`, taget i projektejerens shell). Stand-ins bygget med
runnerens `standin`, kørt fra operatørens cwd (`~`) gennem `koer.zsh` med `DAA_STANDIN_REPO` = grenens checkout.

| Base | Forløb | Resultat |
|---|---|---|
| g1 | `maal` → `anon` → `dump` → `go-ddl` → `apply-ddl` → `maal` → `anon` → `dump` → `go-data` → `apply-data` → `verify` → `anon` → simuleret publicering som redaktør → `bevis` | DDL 0,3 s (note 72 slettet; personsletningens 8 verify-blokke grønne bagefter); ceremoni `T_RP_OK …` på 53 s (længste sætning 24 s), `apply-data` 84 s; `verify` FAKTA/BIO uændret, synlige 554; efter publicering `bevis` synlige **555** (= 554 + 2 − 1; 944's omtale skjult), FAKTA uændret, BIO ændret; fortrydelse af 598/603's `legacy_withdrawn` afvist med `NARRATIVE_LEGACY_RECORD_BINDING_EXISTS` (RPC og historik) |
| g1 | negativer | forkert GO → `T_RP_GO_MISMATCH`; manglende flag → `T_RP_FLAG_MANGLER`; gentaget `apply-data` → `T_RP_DATA_FAERDIG`; ændret svarfil (kopi) → `T_RP_PAKKE_SHA` |
| g2 | frem til data → `go-fortryd`/`fortryd` → `maal` (fase ddl) → `DAA_TRP_DUMP` = foer-kvitteringen → `go-fortryd-ddl`/`fortryd-ddl` | data: `T_RP_FORTRYD_OK tilstand=ddl`, ACL/katalog som dumpet; DDL: drop af 11 triggere, 1 constraint, 2 tabeller, 25 funktioner, restore, `db-rls.sql` fra `f37b294a`; `T_RP_FORTRYD_OK tilstand=foer`, restore-hash `599233f4…` = foer-dumpets; note 72 tilbage |
| g3 | hele rækkefølgen med den **fastlåste** runner | samme tal som g1; 0 `T_RP_FASTLAAS`-linjer |

Målt: `synlige_1939` tæller anon-synlige tekster i biografilæseren (554), ikke publiceringer (565, spec §8); forskellen
er uændret siden 17/11. Fortryd-DDL kræver, at foer-dumpets kvittering vælges (`koer.zsh --saet DAA_TRP_DUMP=…`).
Efter merge måler `dump-kopi`'s efterfølgende `maal` også i prod (før merge mangler målescriptet i hovedcheckouten).
