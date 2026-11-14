# Færdigbevis: trin 6e-2 i prod — 1939's kildeetiket, trykte sider og koordinater (2026-11-14)

Spec: `docs/superpowers/specs/2026-11-12-trin6e-laeserflade-design.md` (§8 og tillæg §12). Plan:
`docs/superpowers/plans/2026-11-13-trin6e2-kildeetiket-koordinater.md`. Runbook: `docs/runbooks/trin6e2-prod.md`.
Kun udfald, antal, hashes og id'er på afdøde 1939-personer.

## Forløb

| Trin | Resultat |
|---|---|
| Klient | PR #345 merget 2026-11-13 (`0c93e052`) og deployet før DDL; tåler før- og eftertilstand. Stod i prod natten over før DDL (projektejerens valg, i stedet for decisions' »samme dag«): imens viste de 26 1939-legacy-personer med kode VI et løbenummer som bognummer (accepteret overgang, decisions 2026-11-13) |
| Tillæg | PR #346 merget (`a91fa572`) |
| DB | PR #347 merget 2026-11-13 (`8d4782af`, head `c6afc163`); flettet med #342 (redaktøren ser levende), generalprøve 3 på et prod-dump efter #342, review 0 Critical / 0 Important / 7 Minor, CI 7/7 grøn. Ingen SQL på `main` efter `c6afc163` (tjekket før DDL) |
| Runner | `~/.private/5ab-overfoersel/40-trin6e2.sh` (sha `234eb8e3…`, vindue `40-trin6e2-vindue.sql` `cab68c26…`); GO'erne bundet til `main` @ `8d4782af`. Projektejeren kørte alle trin i sin shell; sessionen læste kvitteringerne |
| `maal` før | `fase=foer`, alle tal og hashes = de fastlåste (561/2/33/0/1100/2264, `KOORD_ANDRE 66e9afd9…`, `ETIKETTER_ANDRE d97decc7…`, `FAMILIEKILDER 06e71a11…`, `SKEMA_ETIKETTER 83c4e28d…`) |
| Dump før | `daa-prod-20261114085322-6e2.dump` (sha `331ac5b4…`, age `be15927b…`, SFTP-rundtur ok), restore-hash `156c4073…`, `change_set_max=3683` |
| DDL | GO `da5b40a6`: vindue eksakt → `B1_6E2_OK` → snapshot (`funktioner=4 nye=8`) → vindue ddl kun `public.source` → `T6E2_APPLY_DDL_OK blok=0ad7c6c3569b09f0 katalog=ok` (27,3 s i alt). Bagefter `db-verify`'s `redaktoer-ser-levende` grøn mod prod (læse-kun) |
| `maal` ddl | `fase=ddl`, alle tal og hashes uændrede |
| Dump ddl | `daa-prod-20261114100655-6e2.dump` (sha `b47fd30d…`, age `417e4812…`, SFTP-rundtur ok), restore-hash `09227d41…`, `change_set_max=3683` (ingen skrivning siden før-dumpet) |
| Data | GO `0b9019de` (`sidekort=cd013e9c… etiketter=5c34881f… ceremoni=6fb56fcf… maal=8f0d6e58…`): `ETK_OK bindinger=561 tomme=33 entries=5 revalideret=561 sprunget=2 stale=0`, andre kilders koordinater og etiketter byte-ens; `T6E2_CS_OK ceremoniens=561 fremmede=0`; vindue data kun ceremoniens 6 tabeller/sekvenser; `T6E2_APPLY_DATA_OK tal=0,2,0,0,1100,2264,75186593…,f0cb8884…` = M[data] (180,6 s i alt) |
| `maal` data | `fase=data BINDINGER_RECORD=0 SPRUNGET=2 UDEN_PLACEMENT=0 STALE=0 BIO_OFFENTLIGE=1100 FAKTA_BUNDNE=2264`, `FAMILIEKILDER 75186593…`, `SKEMA_ETIKETTER f0cb8884…` |
| `vindue` | `T6E2_CS_OK ceremoniens=561 fremmede=0`, `T6E2_VINDUE_OK sammenligning=data` |
| Advisors | Statisk (MCP'en ser ikke DAA-projektet): blokken har 12 funktioner, alle med `SET search_path`; `REVOKE ALL … FROM PUBLIC,anon,authenticated,service_role` før hver `GRANT`; `membership_current_set` uden grant. Security Advisor i dashboardet er ikke kørt |

## Tal

| Måling (anon, prod, median af 3) | Før | Efter DDL | Efter data |
|---|---|---|---|
| Koordinat-RPC, pr. kald | 1.261 / 1.263 ms | 306 / 296 ms | 318 / 313 ms |
| Koordinat-RPC, begge sider | 2.524 ms | 602 ms | 631 ms |
| Conrads biografi (392) | 120 ms | 123 ms | 157 ms |

- Koordinat-RPC'en ≤ 0,6 s pr. kald (spec §8): **opfyldt** (≈ 4 × hurtigere; læseren var før 2,5 s mod anons 3 s).
- Conrads biografi ligger under basen 209-487 ms, altså hurtigere end basen; før 6e-2 var den 120 ms. Ingen
  regression.
- Ceremonien: 604 sætninger, 120,1 s, langsomste sætning 19,4 s (stand-in 30,2 s / 11,4 s; prod-faktor ≈ 1,7).
- `maal` 47,3 / 42,9 / 35,3 s; `dump` 103,9 + 82,8 s og 139,0 + 83,3 s.

## Browsertjek og anon-data mod prod

Projektejeren tjekkede personsiderne som anon i browseren: »ser umiddelbart rigtigt ud«. `/person/1198` viderestiller
til `/person/392` (1198 er foldet sammen med 392 via `samme_som`), så 1939-visningen nås gennem udgavevælgeren på 392.
Sessionen hentede de samme data, som browseren får, som anon via PostgREST:

| Tjek | Udfald |
|---|---|
| Koordinat-RPC'en, alle sider | 1.111 rækker (1.000 + 111, som runneren); **0** `record-` og **0** `legacy-source:` |
| Trykte sider | Kilde 3: 561 rækker med trykt side, **højeste 92**; kilde 1: ingen |
| Linjenavne (`lineage_scheme_entry`) | »III. Den ældre meklenborgske Linje af Ziesendorf.«, »A. Den holstenske Linje.«, »B. Den ældre meklenborgske Linje.«, »II. Linjen Gallentin.« |
| Redaktøren ser levende (#342) | `redaktoer-ser-levende` grøn efter DDL. Generalprøve 3: redaktøren 1.167 koordinater (56 ikke-offentlige) før og efter DDL og data, gæsten 0 ikke-offentlige |

**Stikprøve (spec §12):** 5 tilfældige placerede 1939-personer (seed `20261114`) fra anons koordinater, slået op i
»Dansk Adels Aarbog - Reventlow 1939.pdf« på PDF-siden, sidekortet giver (trykt + 489). Sidetallet trykt på PDF-siden
er det viste, og nummeret står ved personen:

| Person | Viser | Bogen |
|---|---|---|
| 1027 | s. 42, nr. 3 | s. 42: »3. Anna † 16 April 1707« |
| 1217 | s. 56, nr. 5 | s. 56: »5. Greve Cai Bertram, f. 14 Aug. 1706« |
| 1770 | s. 13, nr. 7 | s. 13: »7. (?) Hartvig, var 1460 …« |
| 1100 | s. 37, nr. 2 | s. 37: »2. Sophie Margarethe, levede 1717 …« |
| 1793 | s. 53, nr. 2 | s. 53: »2. Charlotte Amalie † ung« — personen har ingen navnepåstand i databasen (kendt: 1939-personer uden navn) |

## Spec §8 (6e-2-delen)

- Ceremonien: genpublicerede = bindinger med `record-` før (561, heraf 33 uden placement), 0 bagefter; `stale` 0;
  offentlige biografier (1.100) og bundne fakta (2.264) ens før og efter; III lyder »… Ziesendorf.«. **Opfyldt.**
- Koordinat-RPC'en som anon ≤ 0,6 s; kilde 1's koordinater og etiketter byte-ens. **Opfyldt.**
- Trykte sider: Conrads 1939-visning viser s. 52 (PDF 541), ingen 1939-side over 92, stikprøve 5/5, linjens navn ved
  begge udgaver. **Opfyldt** (browser + anon-data).
- Ingen `record-`/`legacy-source:`. **Opfyldt** i anons data; DOM'en er set af projektejeren, ikke talt maskinelt.
- `status.md`'s 1939-kolonne hæves. **Gjort** i samme commit.

## Ikke gjort / tilbage

- Personsidens samlede indlæsning er ikke tidsmålt; kun runnerens kald (ovenfor).
- Redaktør-visningen i browseren (logget ind) er ikke tjekket i prod; katalog-tjekket er grønt.
- Security Advisor i dashboardet er ikke kørt (kun statisk).
- De 2 staged 1939-poster beholder `record-`-etiketten (decisions 2026-11-13, afgørelse A).
- 30 »formodet«-forældreled: 28 fra 1939 uden markør i bogen er sat til tom konfidens 2026-11-14 (change_set
  4245-4272); 79/80 (2018-20) har »?« i bogen og forbliver `formodet`.
- Fortrydelse: data med ddl-dumpet (`fortryd`), DDL med snapshot-mappen `prod/6e2/fortryd-ddl-20261114095036`
  (`fortryd-ddl`); begge prøvet i generalprøve 3. Efter færdigbeviset er rettelser almindelig redigering.
