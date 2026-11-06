# Runbook — trin 6m del 1 i prod: modelgennemgang af 1939 og rettelse af læserteksten

Spec: `docs/superpowers/specs/2026-11-05-trin6m-modelgennemgang-1939-design.md` (§4.1-§4.5, §6, §7). Plan:
`docs/superpowers/plans/2026-11-06-trin6m-del1-modelgennemgang-og-laesertekst.md` Task 7-8.

Kort sagt: en model (Opus-underagenter) holder hver af 1939's 592 poster og alle forslag op mod bogens sidebilleder.
Projektejeren ser kun de rettelser af *læserteksten* (narrativet), modellen foreslår, og vælger selv. Én ceremoni
skriver de valgte rettelser som nye revisioner af de publicerede narrativer. Klausuler, forslag, afgørelser, bindinger
og kildetekst røres ikke (vej (a)); 6c-2's tal og 2018-20's bindinger (`k1`) er de samme før og efter.

| Skridt | Hvad | Skriver |
|---|---|---|
| eksport | læse-kun: poster, narrativer (med `state_sha256`), placering og forslag → ny gennemgangsmappe | nej |
| input, briefs | modelinput i bidder à 25 poster med sidebilleder (150 dpi), én brief pr. bid | nej (lokalt) |
| model | Opus-underagenter, højst 6 ad gangen; hver læser kun sin inputfil og sine sidebilleder og skriver kun `svar-A-k`/`svar-B-k` | nej (lokalt) |
| saml | fail-closed sammenlægning; stop ved over 300 grupper (exit 3) | nej (lokalt) |
| kort, flet, sql | projektejerens kort (L/K/N/tom) → ark bundet til manifestet → ceremoniens SQL | nej (lokalt) |
| apply-b | `red_revider_publiceret_person_narrative_record` pr. post med eksportens `state_sha256`, i én transaktion | narrativ-revisioner |

Runneren er privat: `~/.private/5ab-overfoersel/30-trin6m.sh` med 5c-2's `lib.zsh` og `koer.zsh` (som fra 6m tillader
`30-…`-scripts). Projektejeren kører `apply-b` og `fortryd` fra egen shell; læse- og lokale trin kan sessionen køre via
præcise allow-regler. Alt ud er antal, nøgler og hashes; bogtekst og navne ligger kun i 0600-filer under `~/.private`.

## Forudsætninger

- Tilstand d (6c-2 afsluttet): `koer.zsh 30-trin6m.sh maal` → `T6M_MAAL_OK tilstand=d`; tallene
  `25 0 0 0 1106 1106 83 1` og `k1 d5bedf7d…` er fastlåst i runneren.
- Grenen merget til `main`, og hovedcheckoutet står rent på merge-commit'en (GO binder commit og repo-filerne).
- Bogens PDF `Dansk Adels Aarbog - Reventlow 1939.pdf` i repo-roden; sha `57119755…` er fastlåst (`T6M_PDF_AENDRET`).
- Aktørfilen `~/.private/5ab-overfoersel/b2/aktoer.txt` (0600) som i 6c-2.
- **Fryse:** ingen redigering af 1939-narrativer i prod fra eksporten, til ceremonien er godkendt. Runneren opdager
  brud på to måder: `apply-b` sammenligner narrativernes hash med dumpets (`T6M_NARRATIVER_AENDRET_SIDEN_DUMP`), og
  RPC'en kaster `NARRATIVE_RECORD_STATE_STALE` for en post, der er ændret siden eksporten.

## Forløb

Alle kommandoer køres fra `~/.private/5ab-overfoersel` (operatørens cwd) som
`/bin/zsh -f koer.zsh 30-trin6m.sh <handling>`. `koer.zsh` gemmer `DAA_T6M_MAPPE` og `DAA_T6M_DUMP` i miljøfilen.

1. `eksport` → `T6M_EKSPORT_OK poster=592 forslag=… bundne=563 ubundne=13 skrivbare=561 sha256=… sekunder=…` og
   `DAA_T6M_MAPPE=…/gennemgang-<stempel>`.
2. `input` → `MG_INPUT_OK poster=592 bidder=24 forslag=… manuelle=… sider=… uden_billede=0` (ca. 45 s).
   `manuelle` er forslag om personer, der ikke opfylder filteret (decisions 2026-11-05); de går ikke til modellen.
3. `briefs` → `MG_BRIEFS_OK briefs=24`.
4. **Pilot:** én Opus-underagent på `brief-1.md`; svaret til sessionen er kun `SVAR_OK poster= forslag=`. Tjek
   bagefter, at der ikke er kommet andre filer i mappen eller scratchpad'en end `svar-A-1.json` og `svar-B-1.json`.
   `saml-pilot 1` → `MG_SAML_OK … manifest=…` til `samlet-pilot-1.json`. Projektejeren ser tallene og siger til.
5. Resten af bidderne, højst 6 underagenter ad gangen. `saml` → `MG_SAML_OK …`. Ved exit 3
   (`T6M_OVER_TAERSKEL`): stop og vis projektejeren tallene (spec §4.3.3).
6. `kort` → `LT_KORT_OK sider= grupper= svarbare= rapport= manifest=`; projektejeren åbner selv
   `…/model/kort-b/kort-1.html` (`! open …`), svarer og henter svarfilen.
7. `flet <svarfil>…` → `LT_FLET_OK L= K= N= ubesvaret= ark_sha256=`.
8. `sql` → `LT_SQL_OK poster= rettelser= k_sager= graense= legacy= kun_rapport= sha256=`.
9. Øvelse på en frisk stand-in med det rigtige ark (Task 7's forløb), før prod.
10. `dump` → `DUMP_6M_OK …`, `EKSTERN_6M_OK … rundtur=ok`, `DAA_T6M_DUMP=…`.
11. `go-b` → `GO_6M_B_KODE=<8 hex>`; projektejeren kører
    `/bin/zsh -f koer.zsh 30-trin6m.sh apply-b --jeg-mener-det --go <kode>` →
    `T6M_APPLY_B_OK poster=N lig=N tal=25,0,0,0,1106,1106,83,1 k1=d5bedf7d… narrativ_hash=… sekunder=…`.
12. `verify` → `VERIFY_B poster=N lig=N`. Spor A's `samlet.json`, `k-sager.json`, `graensefejl.txt` og
    `legacy-sager.json` bliver i gennemgangsmappen som input til del 2.

## Stoppunkter

| Linje | Betyder | Gør |
|---|---|---|
| `T6M_MAAL_UKENDT` / `…_TILSTAND` | basen er ikke i tilstand d med 6c-2's tal | stop; mål og spørg |
| `T6M_OVER_TAERSKEL` | over 300 grupper efter gruppering | stop; vis projektejeren tallene |
| `SVAR_*`, `RETTELSE_*`, `BILLEDSTOETTE_MANGLER` (saml) | et modelsvar er ugyldigt | kør den bid igen med en ny underagent |
| `MANIFEST_MISMATCH`, `SVAR_IKKE_TILLADT`, `SVAR_KONFLIKT` (flet/sql) | svarfil eller ark passer ikke til samlet | lav kort igen; aldrig håndrettelse af arket |
| `T6M_NARRATIVER_AENDRET_SIDEN_DUMP` | et 1939-narrativ er ændret efter dumpet | intet er skrevet; find ændringen, ny eksport |
| `CEREMONI_B fejlede (NARRATIVE_RECORD_STATE_STALE…)` | en post er ændret efter eksporten | rullet tilbage; ny eksport og ny gennemgang af den post |
| `T6M_VERIFY_B` efter apply | ceremonien er committet, men en tekst-sha afviger | stop; fortryd fra dumpet |

## Varighed og prods tidsgrænse

Øvelsen på stand-in (6/11, 25 poster): længste enkeltkald 178 ms, hele transaktionen 0,29 s, `apply-b` 0,2 s.
Eksporten er én læse-kun forespørgsel på 1,5 s. 6c-2's prod/stand-in-forhold var ca. 13× (`maal` 83 s mod 6,4 s);
selv ved 20× er længste kald ca. 3,6 s, under halvdelen af prods `statement_timeout` på 2 min. Prods grænse gælder pr.
sætning; transaktionen kalder RPC'en én gang pr. post.

## Fortrydelse

`go-fortryd` (med `DAA_T6M_DUMP` = kvitteringen for dumpet før `apply-b`) → projektejeren kører
`fortryd --jeg-mener-det --go <kode>` → `T6M_FORTRYD_OK narrativ_hash=<dumpets> restore_hash=<dumpets> …`. Restoren
afvises, hvis andre end ceremoniens aktør har skrevet siden dumpet (`T6M_FORTRYD_FREMMEDE_AENDRINGER`), eller hvis der
er låse eller transaktioner i gang. Bagefter er ACL, katalog, restore-hash og narrativernes hash som dumpets.

## Øvelse (2026-11-06, plan Task 7)

Stand-in `daa5ab_ddl_standin_20261106204605_6m` (fra `dump-kopi` 20261106201924), kørt fra `~/.private` med syntetiske
modelsvar (A alle `OK`; B én entydig rettelse i 25 skrivbare poster) og et syntetisk ark (L på alle 25 grupper):

- `eksport` 1,5 s → `input` (24 bidder, 2.553 forslag, 221 manuelle, 88 sider) → `briefs` → `saml` (25 grupper,
  `over_taerskel=0`) → `kort` → `flet` (L=25) → `sql` (25 poster).
- `dump` → `go-b` → `apply-b` → `T6M_APPLY_B_OK poster=25 lig=25`, 6c-2's tal og `k1` uændrede; 25 change_sets og 25
  `published_revision`-hændelser; alle 563 stadig `published`, 561 med `publish_revision`.
- `fortryd` → `T6M_FORTRYD_OK`, narrativernes hash og restore-hashen som dumpets.
- **Drift:** ét af de 25 narrativer ændret direkte efter `sql`. Runneren stopper med
  `T6M_NARRATIVER_AENDRET_SIDEN_DUMP`; ceremoniens SQL kørt direkte kaster `NARRATIVE_RECORD_STATE_STALE` ved post 13,
  og de 12 kald før er rullet tilbage (0 nye change_sets, narrativernes hash uændret).
