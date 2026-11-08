# Runbook: trin 6c-3 i prod — 2018-20's A6b-rest (tekstrevision og genbinding)

Spec: `docs/superpowers/specs/2026-11-07-trin6c3-a6b-resten-design.md`. Plan: `docs/superpowers/plans/2026-11-07-trin6c3-a6b-resten.md`.
Beslutninger: `docs/decisions.md` 2026-11-07 (afgrænsning) og 2026-11-08 (genkørsel, I-11 og sammensætningen pr.
post, godkendt som valg A).
Runner: `~/.private/5ab-overfoersel/32-trin6c3.sh` med `32-trin6c3-b.R`, `32-trin6c3-maal.sql`, `32-trin6c3-rev.sql` og
`32-trin6c3-vindue.sql` (aldrig i repoet). Den kaldes via `/bin/zsh -f ~/.private/5ab-overfoersel/koer.zsh 32-trin6c3.sh <handling>` fra
operatørens cwd. De bundne input ligger i `~/.private/6c3/prod-pakke/` (18 filer, 0600). Alle linjer er kun antal, nøgler
og hashes. Prod-skrivning (`apply-*`, `fortryd`) sker kun i projektejerens shell med `--jeg-mener-det --go <kode>`.
Hovedcheckouten skal være ren og stå på den commit, GO er bundet til (`main` efter merge).

## To ceremonier

1. **DDL** (blok `-- ===== trin 6c-3a: tekstrevision og relationer =====` + `db-rls.sql` i én transaktion,
   `lock_timeout 5s`). Forudsætning: PostgreSQL ≥ 15 (`UNIQUE NULLS NOT DISTINCT`). Kontrol efter: ingen EXECUTE for
   anon/authenticated på de fire private funktioner, ingen grants på `private.text_revision_reconciliation`.
   Fortrydelse: `fortryd` med DDL-dumpet. Katalogdiffens nye tabel og funktioner droppes, så restore og `db-rls.sql`.
   Det kræver, at data ikke er kørt.
2. **Data** (`apply-data`): revision (R-kæden, 10 operationer) → forslag (R-kæden, 9 elementer, 75 forslag) → parter
   (A-filtreret, 8 elementer) → afstemning → kontrolplan → `oversaet` → preflight → `fakta.sql` → forældre → børn →
   relationer → kvittering. Hver læsning og hver SQL-fil får session-`statement_timeout=30min`. Runneren måler
   tilstanden ved start og springer gjorte trin over. Efter en fejl efter revisionen køres `apply-data` igen med
   samme GO; artefakterne ligger i `prod/6c3/data-<dump16>/`. Fortrydelse: `fortryd` med data-dumpet (restore).

## Rækkefølge

| Trin | Handling | Forventet (generalprøverne c3g og c3h 8/11) |
|---|---|---|
| 0 | `maal` | `T6C3_MAAL_OK tilstand=foer`, `andre=049163332f67…`, `REV_MAAL … fakta_9_bundet=9 … familiekilder_7=7` |
| 1 | `dump` | `DUMP_6C3_OK tilstand=foer`, `EKSTERN_6C3_OK … rundtur=ok`, `DUMP_6C3_MAAL_OK … vindue=… vindue_linjer=134`, `DAA_T6C3_DUMP=…` (B1: hash i `database-current-state.md`) |
| 2 | `go-ddl` → projektejeren `apply-ddl --jeg-mener-det --go <kode>` | `T6C3_VINDUE_OK sammenligning=eksakt linjer=134`, `T6C3_APPLY_DDL_OK tilstand=ddl blok=1e8d9553eb3806df` |
| 3 | advisors / grant-gennemgang | ingen nye fund (runneren har tjekket grants) |
| 4 | `maal` | `tilstand=ddl` |
| 5 | `dump` | `DUMP_6C3_OK tilstand=ddl`, `vindue_linjer=136` (data-dumpet; fortrydelsens grundlag) |
| 6 | (afgjort 8/11: sammensætningen, valg A — pakken som den er) | — |
| 7 | `go-data` | `forslagsmanifest=9592824354b4c926 sammensaetning=cf40e590… svar=4950a82d… tilbagetraek=974a389d…`, `GO_6C3_DATA_KODE=…` |
| 8 | projektejeren `apply-data --jeg-mener-det --go <kode>` | se næste tabel |
| 9 | `verify` | `T6C3_VERIFY_OK kvittering genbundet=14 genfundet=30 ikke_genfundet=28 tilbagetrukket=2 andre=049163332f678113` |
| 10 | tre stikprøver som anon i læserfladen (plan Task 9 Step 5) | et genbundet faktum og en genbundet familie med kildelinje |

`apply-data`'s linjer i rækkefølge (stand-in-sekunder i parentes; prod var 13-27 gange langsommere i 6c-2 og 6m):

| Linje | Betydning |
|---|---|
| `T6C3_VINDUE_OK sammenligning=eksakt linjer=136` | intet i `public`/`private` er ændret siden data-dumpet (ved genoptagelse: `sammenligning=data`) |
| `T6C3_DEPS_OK sha=aac2372c901aa514` (0,5 s) | afhængighedsfilen genmålt = den bundne |
| `T6C3_B_APPLY rev operationer=10 status=finalized` (2,2 s) | revisionen: 58 nøgler `superseded`, 10 tekstversioner |
| `T6C3_LEDGER foer sha=22080ca1c79fab7a` (1,4 s) | eligibility-ledgeren efter revisionen = den bundne |
| `T6C3_B_APPLY forslag operationer=9 status=finalized` (1,2 s) | 75 nye forslag (`key_version 2`) |
| `T6C3_A_FILTER nye=75 A=74 ude=1 ok=True` | I-11's nye ægteskab er filtreret fra (decisions 2026-11-08, valg A) |
| `PARTER_OK elementer=8 elementer_sha256 13e5418285aa2805…` | prods partsudtræk er logisk lig stand-in'ens |
| `T6C3_PARTER_TAL … "parties": 11 … "spouse_personas": 3` (0,4 s) | 3 genbrugte ægtefælle-personas, 0 nye (personas 1395) |
| `T6C3_AFSTEMNING_OK logisk=75e967418bf36fed` | afstemningen efter parterne = den bundne (bortset fra batch_id) |
| `T6C3_KONTROL r sekunder=…` (43 s) | kontrolmodellens rækkeeksport; den længste læsning |
| `AFGRAENS_OK noegler=75 items=611->15 rows=2834->75` | kontrolmodellen afgrænset til de nye nøgler |
| `OVERSAET_OK felter=13 personas=7 svar_sha256 4950a82d…` | svarene oversat til prods id'er (`KORT_PROD_AFVIGER` = stop) |
| `TEKSTREVISION_PREFLIGHT_OK noegler=58 bindinger=16 genbind=14 tilbagetraek=2 fakta_bundne=10` | før første binding |
| `CONTROL_V2_OK … afgoerelser=3 stikproeve=10 … bundet=10` (18 s) | faktaafgørelser og -bindinger |
| `T6C3_FORAELDRE`, `T6C3_BOERN`, `RELATIONER_OK aegteskaber=3 bindinger=6` | relationsafgørelser og -bindinger |
| `TEKSTREVISION_KVITTERING_OK {"genbundet": 14, "genfundet": 30, "ikke_genfundet": 28, "tilbagetrukket": 2}` | 58 + 16 kvitteret |
| `T6C3_APPLY_DATA_OK tilstand=faerdig tal=1,58,10,75,15,1395,13,4,1,3,16,74` | REV_MAAL: fakta bundet 8/9, familiekilder 6/7, narrativer uændrede |

## Vindue og frys

Frys fra `dump` (trin 1) til `verify` (trin 9): ingen andre skrivninger i prod, heller ikke på 1939 eller fra
læsere med redaktørrolle (spec §5 pkt. 5). Runneren kontrollerer det selv: `change_set` må ikke vokse mellem dump og
`apply-*`, og ved genoptagelse må der ikke være fremmede change_sets. `andre` (kilde 1's øvrige forslag) skal være
uændret hele vejen.

Medlemmers skrivninger (bogmærker, nye tilmeldinger med en `profiles`-række) opretter intet change_set og kan ikke
stoppes. En restore af dumpet ville slette dem lydløst (Codex' diffreview 8/11, fund 1). Derfor tager `dump` et
**vinduesaftryk**: én linje pr. tabel og sekvens i `public`/`private` (antal + hash, ingen indhold), målt mellem de to
restore-hashes. Det sammenlignes med basen nu:

- før `apply-ddl` og før en første `apply-data` eksakt (alt skal være som ved dumpet; ellers `dump` igen);
- ved genoptagelse af `apply-data` og i `fortryd` før restoren, undtagen de tabeller/sekvenser, ceremonien selv ændrer.
  Listerne er målt på `c3h` og fastlåst i runneren: DDL ændrer kun kvitteringstabellen og dens sekvens; data ændrer
  16 tabeller/sekvenser, alle i `private` (forslag, fortolkninger, promotions, reimport-hændelser, kvitteringen).
  Hele `public` sammenlignes altså eksakt.

Vagten koster én læsning af basen ved hvert `dump`, `apply-*` og `fortryd`: målt 2,6 s på `c3h`, med prod-faktoren
13-27 ca. 35-70 s pr. læsning, i alt ca. 2-5 minutter over de fire læsninger (to dump, to apply). Hver tabel er sin
egen sætning, og sessionen har `LAES_TIMEOUT`. Vagten gælder kun prod mod prod (samme base), så den har ingen
fastlåst hash.

Data-vinduet er ca. 70 s på stand-in. Med prod-faktoren fra 6c-2 (≈27) bliver det ca. 30 minutter, mest
rækkeeksporten (≈19 min) og `fakta.sql` (≈8 min). Begge ligger under 30 minutter. Stand-in-tid er ikke prod-tid, så
`maal`'s `sekunder=` i trin 0 bruges som målt forhold (stand-in 0,6 s).

**Fastlåste værdier:** runneren afviser prod, hvis en fastlåst værdi mangler. Alle værdier er målt på stand-ins fra
prod-dumpet `890d7f49…` (7/11). Afviger `maal` i trin 0 (`MAAL_6C3_UKENDT`, typisk `andre` eller `personas`), er prod
ændret siden: tag en ny `dump-kopi`, lav en ny stand-in med `standin`, kør generalprøven igen og fastlås igen. Prod
røres ikke.

## Stoppunkter

| Stop | Tilstand | Udgang |
|---|---|---|
| `DDL_6C3A fejlede` | rullet tilbage | ret årsagen; ny GO |
| `T6C3_DEPS_AFVIGER` | intet skrevet | prod afviger fra stand-in'en: ny `dump-kopi` og generalprøve |
| `T6C3_B_FEJL (rev/forslag …; intet committet)` | uændret | se `r-<etiket>-*.out`; `apply-data` igen |
| `T6C3_B_FEJL_EFTER_COMMIT` | trinnet er committet, en kontrol fejlede | `maal`; afgør genoptag eller `fortryd` |
| `T6C3_LEDGER_AFVIGER` | revisionen står, ingen forslag | ledgeren afviger: fortryd, ny generalprøve |
| `T6C3_NYE_NOEGLER_AFVIGER`, `T6C3_A_FILTER`, `PARTER_AFVIGER` | forslagene står, ingen parter | fortryd (prod er ikke stand-in'en) |
| `T6C3_PARTER_APPLY_FEJL` | batchen er rullet tilbage | Review Focus 1: et genfundet ægteskab med uændret `post_offset` giver `unique_violation`. Det opstod ikke i generalprøverne. Prod er dumpet, og `PARTER_OK` beviser logisk lighed med stand-in'en. Sker det alligevel: fortryd |
| `T6C3_AFSTEMNING_AFVIGER`, `…RAEKKER_AFVIGER`, `KORT_PROD_AFVIGER`, `T6C3_PREFLIGHT…` | parterne står, intet afgjort | fortryd |
| `T6C3_FAKTA_FEJL` / `…FORAELDRE…` / `…BOERN…` / `…RELATIONER…` | den fejlede fil er rullet tilbage, de tidligere står | `maal`; `apply-data` igen (genoptager fra tilstanden med den gemte `gen.json`) eller fortryd |
| `T6C3_KVITTERING` | alle bindinger står, ingen kvittering | `apply-data` igen; ellers fortryd |
| `T6C3_EFTER_<trin> (tilstand; tal …)` eller `T6C3_DATA_TILSTAND_UKENDT` | trinnet er committet, men tallene passer ikke til den fastlåste tilstand | genoptagelse afvises (runneren kender ikke tilstanden); `fortryd` (bruger den rå tilstand) |
| `T6C3_VINDUE_BRUDT_FOER_DDL` / `…_FOER_DATA` | intet kørt | noget er skrevet siden dumpet (se `afvigende.txt`: kun tabelnavne). Afklar hvad; `dump` igen og ny GO |
| `T6C3_VINDUE_BRUDT_GENOPTAG` | ceremonien er delvist committet | andet end ceremonien har skrevet i vinduet. Genoptag ikke; afklar med `afvigende.txt`, før der vælges `fortryd` (som så stopper på samme vagt) |
| `T6C3_VINDUE_BRUDT` (fortryd) | intet restoret, ingen markør | en restore ville slette skrivninger efter dumpet (typisk `public.bookmark`/`public.profiles`). Projektejeren afgør: enten bliver ceremonien stående, eller skrivningerne genskabes manuelt efter en restore, der så kræver en beslutning uden for runneren. Runneren har ingen tilsidesættelse |
| `T6C3_VINDUE_MANGLER` | uændret | dumpet er taget med en runner uden vinduesaftryk; `dump` igen |
| `T6C3_FORTRYD_IGANG` | en fortrydelse er påbegyndt | gennemfør `fortryd` med samme dump. *Kendt mangel:* runneren afviser i dag alle handlinger undtagen `maal`, mens markøren ligger, også `fortryd` selv; markøren (`fortryd-<dump16>.igang`) skal flyttes manuelt efter `maal`, før fortrydelsen kan gentages |

Genoptagelse blev afprøvet på c3g fra `parter`, `fakta` og `boern` (stand-in-krogen `DAA_T6C3_TEST_STOP`, kun stand-in).

## Fortrydelse

`DAA_T6C3_DUMP=<kvittering> koer.zsh 32-trin6c3.sh go-fortryd` → projektejeren `fortryd --jeg-mener-det --go <kode>`.
Kræver ingen fremmede change_sets siden dumpet og ingen andre sessioner med låse. Efter: ACL, default-ACL, katalog og
restore-hash som dumpet, `andre` uændret (`T6C3_FORTRYD_OK`). Afprøvet på c3f (DDL og data) og c3g (data).
DDL-fortrydelsen er kun kørt på c3f, før værdierne var fastlåst.

## Generalprøverne 8/11

- `c3f` (`daa5ab_ddl_standin_20261108154214_c3f`, runnerens `standin` fra dump `890d7f49…`): DDL, fortryd-DDL, DDL,
  data (to stop undervejs, se nedenfor) og fortryd-data. preflight-, relations-, forælder- og børne-SQL er byte-ens
  med c3e's, hvor svarene blev givet. Fire fund blev rettet i runneren: forslagsprofilen har 1 batch fra trin 4
  (vagten er »før + 1«); afstemningens `batch_id` er base-specifik; partsbatchens output bærer klausul-id'er (kun
  tallene fastlåses); publiceringshashen afhænger af `TimeZone` (runneren kører UTC begge steder).
- `c3g` (`daa5ab_ddl_standin_20261108154822_c3g`): hele forløbet med alle værdier fastlåst (ingen `T6C3_FASTLAAS`),
  genoptagelse fra tre tilstande, `verify` og fortryd-data.
- `c3h` (`daa5ab_ddl_standin_20261108164526_c3h`, efter Codex' diffreview): vinduesvagten. DDL → fortryd-DDL og DDL →
  data → fortryd-data målte ceremoniernes egne tabeller (fastlåst). Derefter, med listerne fastlåst: et bogmærke
  indsat efter data-dumpet → `apply-data` stoppede med `T6C3_VINDUE_BRUDT_FOER_DATA` (kun `public.bookmark`, tilstand
  stadig `ddl`); fjernet → data kørte med samme tal som `c3g`; et bogmærke indsat efter data → `fortryd` stoppede med
  `T6C3_VINDUE_BRUDT` (ingen restore, ingen markør, tilstand `faerdig`); fjernet → fortryd-data `T6C3_FORTRYD_OK`
  (`sammenligning=data`), og fortryd-DDL `T6C3_FORTRYD_OK` (`sammenligning=ddl`). Genoptagelse med vagten: data
  stoppet efter `rev` og efter `fakta` (`DAA_T6C3_TEST_STOP`), begge genoptaget med `T6C3_VINDUE_OK
  sammenligning=data` og samme slutresultat (`tal=1,58,10,75,15,1395,13,4,1,3,16,74`, kvittering 14/30/28/2); derefter
  fortryd-data `T6C3_FORTRYD_OK`. `c3h` står i tilstand `ddl`.
