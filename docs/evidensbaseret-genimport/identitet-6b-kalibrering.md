# Trin 6b — kalibrering af publiceringskontrollen mod 2018-20

Spec: `docs/superpowers/specs/2026-10-31-trin6b-identitet-design.md` §4.3 pkt. 7 og §4.4. Plan:
`docs/superpowers/plans/2026-10-31-trin6b-identitet.md` Task 10. Kørt 2026-10-31 i en kopi af stand-in'en, aldrig i
prod. Hele beviset er bagefter genskabt i en ny kopi udelukkende med det committede script (afsnittet *Genskabelse*);
alle tal nedenfor kom ud identisk. Rapporten indeholder kun antal, hashes og basenavne — ingen navne, ingen kildetekst, ingen persona- eller
person-id'er.

## Kort svar

**`controlMargin = 0.05`.** Ingen gitterværdi giver en forkert `enig`, heller ikke med en forkert `samme_som`-klynge.
Reglen er: den mindste fejlfri værdi (0,02) plus ét trin. Kortantallet indgik ikke i valget. Værdien er foreløbig:
spec §4.3 pkt. 7's andet ben (stand-in efter runnerens prøvekørsel) køres i plan Task 15 step 2 med samme script.

Årstalsreserven løfter de 563 bundne 1939-personer fra 45 til 433 med mindst ét år i matcherens frames.

## Grundlag

| | |
| --- | --- |
| Arbejdsbase | `t6b_10_cal` = `createdb -T daa5ab_ddl_standin_20261030210000_6am2`; `statement_timeout='2min'`; `db-migrations.sql` × 2 + `db-rls.sql` (0 fejl); `ANALYZE` |
| Kilde | 1 (DAA 2018-20) |
| Facit | 587 accepterede identiteter med `evidence.authority='person_external_id'` (149b's kobling, som i 5a) |
| Generator | `identity-candidates-1.2`, standardscoring, `--top-k 5`; `autoCutoff` 0,9, `ambiguityMargin` 0,05, `reviewCutoff` 0,7 |
| Input (med reserve) | `year_fallback: date_raw-v1`; `input_sha256` `a2df0f1d0503a8ab73ad8319a8a4e04cfe69ac8d2eaaacf165b3dec1f23bf847` |
| Input (uden reserve) | `input_sha256` `adcb090e4070aaabb009179cfc41c0a2e4665e677d80a246830c92cc3f6923f8` |
| Kandidater | 1247 rækker for 587 personas; `candidates_sha256` `ec895b0281c1508bfb47cfe1774c9869a7f22abff6a871df6ceeb2f46ba1b606` (ens for alle 6 gitterværdier, kun `config` skifter) |
| Kontrafaktiske par | 1571 par (persona, person): hvert klyngemedlem i `member_scores` i personaens top-5-rækker, der ligger uden for facits `samme_som`-klynge |

`export-truth.sql` giver i dag 828 accepterede for kilde 1 (587 `person_external_id` + 174 `family_corroboration` + 66
`human_sheet` + 1 `web_detail`). Kalibreringen bruger kun de 587, som i 5a: `export-calibration-truth.sql` og
`calibrate-publication-control.sql` filtrerer selv på autoriteten (`-v facit=authority:person_external_id`, standard)
og kræver `canonical_person_id` sat.

## Gittertabel

**Rigtige:** `enig` med facit som bindingsperson (af 587). **Forkerte:** `enig` med et klyngemedlem fra personaens
top-5-rækker uden for facits klynge som bindingsperson (af 1571 par). **Forkerte med forkert klynge:** samme par, men i en kørsel, hvor parret er lagt i samme
klynge (af 1571 par).

| `controlMargin` | rigtige | forkerte | forkerte med forkert klynge |
| --- | --- | --- | --- |
| 0,02 | 68 | 0 | 0 |
| **0,05** | **54** | **0** | **0** |
| 0,08 | 46 | 0 | 0 |
| 0,10 | 46 | 0 | 0 |
| 0,15 | 15 | 0 | 0 |
| 0,20 | 14 | 0 | 0 |

Udfald med facit som bindingsperson:

| `controlMargin` | enig | svag: under_margin | svag: under_auto | svag: uden_aarstal | svag: partner_hoejere | uenig | navnefaelle | ingen_kandidat |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 0,02 | 68 | 6 | 28 | 0 | 118 | 1 | 21 | 345 |
| 0,05 | 54 | 20 | 28 | 0 | 118 | 1 | 21 | 345 |
| 0,08 | 46 | 28 | 28 | 0 | 118 | 1 | 21 | 345 |
| 0,10 | 46 | 28 | 28 | 0 | 118 | 1 | 21 | 345 |
| 0,15 | 15 | 59 | 28 | 0 | 118 | 1 | 21 | 345 |
| 0,20 | 14 | 60 | 28 | 0 | 118 | 1 | 21 | 345 |

De 1571 kontrafaktiske par giver ved alle gitterværdier 1445 `uenig` og 126 `navnefaelle`. Ingen af dem når frem til
margintjekket. Parrene kommer fra de samme kandidatrækker ved alle seks værdier.

**Negativkontrol (forkert klynge).** Én inputkopi med alle 1571 syntetiske par ville samle `samme_som`-klynger på op
til 127 personer (før: højst 6), og så ville kontrollen ikke længere vise én forkert kobling. Parrene er derfor fordelt
på 41 inputkopier. I hver kopi berøres en eksisterende klynge af højst ét syntetisk par, så hvert par samler præcis
facits klynge og den forkerte persons klynge. Det giver 41 kopier × 6 gitterværdier = 246 kørsler. Parrene udtrækkes
af `sql/calibration-negative-pairs.sql`; fordelingen og mutationen af `same_as` er `partitionPairs`/`mutateSameAs` i
`src/calibration.ts` (`calibration-cli.ts split`, med vitest).

`red_record_identity_candidates` afviser en ændret kopi (`IDENTITY_CANDIDATE_INPUT_DRIFT`, sådan er den bygget).
Kørslerne er derfor skrevet direkte i kørselstabellerne i kalibreringsbasen af `sql/calibration-negative-insert.sql`
med samme indholds-id'er og hashes som RPC'en. `input_sha256` er serverens kanoniske hash af den ændrede kopi
(`sql/calibration-input-hash.sql`). Indsættelsen nægter uden `-v kalibreringsbase=ja`, og scriptet nægter en base,
hvis navn ikke rummer `_cal`, medmindre `--jeg-ved-det-er-en-kalibreringsbase` er givet. En sådan ekstra kørsel med
samme config ville gøre en rigtig kørsel forældet for `publication_identity`.

| | pr. gitterværdi |
| --- | --- |
| Negativkørsler | 41 |
| Par prøvet (rækken rummer både den forkerte person og facit) | 1571 (0 ikke berørt) |
| — prøvet i mere end én kørsel (samme sammenlægning via en anden klyngepartner) | 1132 |
| — klyngerækken er rang 1 med generatorens tier `auto` | 968 |
| `enig` | **0** |

I 968 par stod den sammenfoldede klyngerække (forkert person + facit) som rang 1 med tier `auto`. Den ville altså have
bestået en kontrol på klyngens sammenfoldede score ved en margin ≤ 0,05 (`ambiguityMargin`); tallet er det samme ved
alle seks værdier. Klassifikatoren bruger bindingspersonens egen score og giver 0 (spec §4.3 pkt. 2).

## Valget

Den mindste gitterværdi med 0 forkerte og 0 forkerte med forkert klynge er 0,02. Plus ét trin giver
**`controlMargin = 0.05`** (plan Task 10 Step 3). Kortantallet indgik ikke (spec §4.3 pkt. 7).

Forbehold: på 2018-20 skiller marginen ikke rigtige fra forkerte. Alle forkerte par stopper allerede ved `uenig` eller
`navnefaelle`. Facit er cirkulært (149b, som i 5a), så tallene er en øvre grænse. Marginens egentlige værn mod en
tæt konkurrent prøves derfor ikke af disse data.

## 5a-sammenligning (Step 4)

Strenge tal: 5a's `calibrate` (`src/cli.ts calibrate`). Klyngebevidste tal: `src/calibration-cli.ts
cluster-calibrate` (`clusterCalibrate` i `src/calibration.ts`, med vitest; facit er et træf, når den står i rækkens
`member_scores`). Kandidaterne er de samme ved alle gitterværdier (ét `candidates_sha256`); planens 5a-krav tælles
klyngebevidst.

| | 5a-beviset (1.0, uden klynger) | 1.2 uden reserve | 1.2 med reserve (valgt) |
| --- | --- | --- | --- |
| Med navn | 250 | 250 | 250 |
| Top-1 (`calibrate`, rep.-id = facit) | 228 | 226 | 227 |
| Top-3 (`calibrate`) | 240 | 238 | 238 |
| `auto` antal / rigtige (`calibrate`) | 159 / 159 | 161 / 161 | 162 / 161 |
| `review` antal / rigtige (`calibrate`) | 50 / 50 | 48 / 46 | 48 / 47 |
| `none` antal / rigtige | 41 / 19 | 41 / 19 | 40 / 19 |
| Top-1, facit i rækkens klynge | — | 228 | 229 |
| Top-3, facit i rækkens klynge | — | 240 | 240 |
| `auto` / `review` rigtige, facit i klyngen | — | 161 / 48 | 162 / 48 |
| Uden årstal: med facit / uden kandidat / top-1 / top-3 | 185 / 151 / 14 / 25 | 185 / 151 / 14 / 25 | 185 / 151 / 14 / 25 |

5a's `calibrate` regner kun et træf, når rækkens `candidate_person_id` er facit. Siden 1.1 folder generatoren
`samme_som`-klynger sammen, og rækken bærer repræsentantens id (familiepartneren eller laveste id). Står facit i
klyngen under et andet id, tæller `calibrate` det som en fejl. Med facit i rækkens klynge som træf er reserven lig
med eller bedre end 5a på alle linjer: top-1 229 mod 228, top-3 240 mod 240, `auto` 162/162 og `review` 48/48.
Med `calibrate`'s strenge regel ligger reserven over 1.2 uden reserve (top-1 227 mod 226, `review` 47 mod 46).
Afstanden til 5a-beviset (top-1 228, top-3 240) findes allerede uden reserve og kommer fra 1.1's sammenfoldning.
Reserven giver én rang-1 mere i `auto` (162 mod 161) og én mindre i `none` (40 mod 41).

## Årstalsdækning (Step 5)

De 563 personer med publiceret narrativbinding i kilde 3 (`sql/export-bound-persons.sql -v source_id=3`). Talt i
matcherens frames (`personFrames`, samme bygning som generatoren) af `src/calibration-cli.ts years` over personsiden af
kilde 1-inputtet med og uden reserve (personsiden er den samme for alle kilder):

| | uden reserve (før Task 4) | med `date_raw-v1` |
| --- | --- | --- |
| Mindst ét år (fødsel eller død) | **45** | **433** |
| Fødselsår | 17 | 367 |
| Dødsår | 37 | 326 |
| Alle 1811 personer i inputtet, mindst ét år | 810 | 1303 |
| Påstande med `date_origin='date_raw'` | 0 | 891 |

130 af de 563 har stadig intet år efter reserven.

## Genskabelse

Hele beviset køres af `packages/identity-candidates/scripts/calibrate-publication-control.sh`. Scriptet kalder kun
committede SQL-filer og CLI'er og udskriver kun antal og hashes. Data (id'er, input med navne, kandidater) skrives til
`--dir` (mappe 0700, filer 0600), og ingen agent læser dem.

```sh
createdb -T daa5ab_ddl_standin_20261030210000_6am2 t6b_10_cal
psql -d postgres -c "ALTER DATABASE t6b_10_cal SET statement_timeout='2min'"
psql -X -q -v ON_ERROR_STOP=1 -d t6b_10_cal -f db-migrations.sql
psql -X -q -v ON_ERROR_STOP=1 -d t6b_10_cal -f db-migrations.sql
psql -X -q -v ON_ERROR_STOP=1 -d t6b_10_cal -f db-rls.sql
psql -X -d t6b_10_cal -c ANALYZE
packages/identity-candidates/scripts/calibrate-publication-control.sh --db t6b_10_cal --source 1 --bound-source 3 \
  --dir ~/.private/6b/task10/repro
dropdb t6b_10_cal
```

Scriptets trin (`--steps main,negative,measure,compare,years`):

| Trin | Gør |
| --- | --- |
| `main` | facit (`sql/export-calibration-truth.sql`) → persona-listen = facits `source_persona_id`'er → `sql/export-input.sql` (`psql -q`, så filen er ren JSON) med og uden `-v year_fallback=date_raw-v1` → `src/cli.ts generate --top-k 5 --control-margin <x>` pr. gitterværdi → `sql/write-candidates.sql` (`red_record_identity_candidates`); desuden én kandidatfil uden reserve til sammenligningen |
| `negative` | `sql/calibration-negative-pairs.sql` → `src/calibration-cli.ts split` → `sql/calibration-input-hash.sql` pr. kopi → generering pr. gitterværdi → `sql/calibration-negative-insert.sql` |
| `measure` | `sql/calibrate-publication-control.sql` (gittertabellen og udfaldstabellen) |
| `compare` | `src/cli.ts calibrate` (streng) og `src/calibration-cli.ts cluster-calibrate` (klyngebevidst), uden og med reserve |
| `years` | `sql/export-bound-persons.sql` → `src/calibration-cli.ts years`, uden og med reserve |

Genkørslen 2026-10-31 gav samme input-hashes, samme `candidates_sha256`, 41 kopier og 246 negativkørsler. Gitter- og
udfaldstabellen, 1445/126, 1132, 968 og 0 ikke berørt, 5a-tallene og årstalsdækningen kom ud identisk. Til Task 15
(kilde 3): `--facit binding` bruger bindingens person som facit for personas med publiceret binding, undtagen staged.
