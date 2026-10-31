# Trin 6b — kalibrering af publiceringskontrollen mod 2018-20

Spec: `docs/superpowers/specs/2026-10-31-trin6b-identitet-design.md` §4.3 pkt. 7 og §4.4. Plan:
`docs/superpowers/plans/2026-10-31-trin6b-identitet.md` Task 10. Kørt 2026-10-31 i en kopi af stand-in'en, aldrig i
prod. Rapporten indeholder kun antal, hashes og basenavne — ingen navne, ingen kildetekst, ingen persona- eller
person-id'er.

## Kort svar

**`controlMargin = 0.05`.** Ingen gitterværdi giver en forkert `enig`, heller ikke med en forkert `samme_som`-klynge.
Reglen er: den mindste fejlfri værdi (0,02) plus ét trin. Kortantallet indgik ikke i valget.

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
| Kontrafaktiske par | 1571 par (persona, anden person i top 5 uden for facits `samme_som`-klynge) |

`export-truth.sql` giver i dag 828 accepterede for kilde 1 (587 `person_external_id` + 174 `family_corroboration` + 66
`human_sheet` + 1 `web_detail`). Kalibreringen bruger kun de 587, som i 5a. `calibrate-publication-control.sql` filtrerer
selv på autoriteten.

## Gittertabel

**Rigtige:** `enig` med facit som bindingsperson (af 587). **Forkerte:** `enig` med en anden kandidatperson som
bindingsperson (af 1571 par). **Forkerte med forkert klynge:** samme par, men i en kørsel, hvor parret er lagt i samme
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

| `controlMargin` | enig | svag: under_margin | svag: under_auto | svag: partner_hoejere | uenig | navnefaelle | ingen_kandidat |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 0,02 | 68 | 6 | 28 | 118 | 1 | 21 | 345 |
| 0,05 | 54 | 20 | 28 | 118 | 1 | 21 | 345 |
| 0,08 | 46 | 28 | 28 | 118 | 1 | 21 | 345 |
| 0,10 | 46 | 28 | 28 | 118 | 1 | 21 | 345 |
| 0,15 | 15 | 59 | 28 | 118 | 1 | 21 | 345 |
| 0,20 | 14 | 60 | 28 | 118 | 1 | 21 | 345 |

De 1571 kontrafaktiske par giver ved alle gitterværdier 1445 `uenig` og 126 `navnefaelle`. Ingen af dem når frem til
margintjekket. Parrene kommer fra de samme kandidatrækker ved alle seks værdier.

**Negativkontrol (forkert klynge).** Én inputkopi med alle 1571 syntetiske par ville samle `samme_som`-klynger på op
til 127 personer (før: højst 6), og så ville kontrollen ikke længere vise én forkert kobling. Parrene er derfor fordelt
på 41 inputkopier. I hver kopi berøres en eksisterende klynge af højst ét syntetisk par, så hvert par samler præcis
facits klynge og den forkerte persons klynge. Det giver 41 kopier × 6 gitterværdier = 246 kørsler.

`red_record_identity_candidates` afviser en ændret kopi (`IDENTITY_CANDIDATE_INPUT_DRIFT`, sådan er den bygget).
Kørslerne er derfor skrevet direkte i kørselstabellerne i kalibreringsbasen med samme indholds-id'er og hashes som
RPC'en. `input_sha256` er serverens kanoniske hash af den ændrede kopi.

| | pr. gitterværdi |
| --- | --- |
| Negativkørsler | 41 |
| Par prøvet (rækken rummer både den forkerte person og facit) | 1571 (0 ikke berørt) |
| — prøvet i mere end én kørsel (samme sammenlægning via en anden klyngepartner) | 1132 |
| — klyngerækken er rang 1 med generatorens tier `auto` | 968 |
| `enig` | **0** |

I 968 par ville en kontrol på klyngens sammenfoldede score have godtaget den forkerte binding. Klassifikatoren bruger
bindingspersonens egen score og giver 0 (spec §4.3 pkt. 2).

## Valget

Den mindste gitterværdi med 0 forkerte og 0 forkerte med forkert klynge er 0,02. Plus ét trin giver
**`controlMargin = 0.05`** (plan Task 10 Step 3). Kortantallet indgik ikke (spec §4.3 pkt. 7).

Forbehold: på 2018-20 skiller marginen ikke rigtige fra forkerte. Alle forkerte par stopper allerede ved `uenig` eller
`navnefaelle`. Facit er cirkulært (149b, som i 5a), så tallene er en øvre grænse. Marginens egentlige værn mod en
tæt konkurrent prøves derfor ikke af disse data.

## 5a-sammenligning (Step 4)

5a's `calibrate` på kørslen med `controlMargin` 0,05 (kandidaterne er de samme ved alle gitterværdier):

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

De 563 personer med publiceret narrativbinding i kilde 3. Talt i matcherens frames (`personFrames`, samme bygning som
generatoren):

| | uden reserve (før Task 4) | med `date_raw-v1` |
| --- | --- | --- |
| Mindst ét år (fødsel eller død) | **45** | **433** |
| Fødselsår | 17 | 367 |
| Dødsår | 37 | 326 |
| Alle 1811 personer i inputtet, mindst ét år | 810 | 1303 |
| Påstande med `date_origin='date_raw'` | 0 | 891 |

130 af de 563 har stadig intet år efter reserven.

## Kommandoer

Alle filer ligger under `~/.private/6b/task10/` (mappe 0700, filer 0600). Kun antal blev læst.

```sh
createdb -T daa5ab_ddl_standin_20261030210000_6am2 t6b_10_cal
psql -d postgres -c "ALTER DATABASE t6b_10_cal SET statement_timeout='2min'"
psql -v ON_ERROR_STOP=1 -d t6b_10_cal -f db-migrations.sql   # to gange
psql -v ON_ERROR_STOP=1 -d t6b_10_cal -f db-rls.sql
psql -d t6b_10_cal -c ANALYZE
# Facit: som export-truth.sql, filtreret på evidence.authority='person_external_id' -> ~/.private/6b/task10/truth587.json
psql -X -At -d t6b_10_cal -v source_id=1 -v actor=… -v mode=list -v personas=… -v year_fallback=date_raw-v1 \
  -f packages/identity-candidates/sql/export-input.sql > ~/.private/6b/task10/input-fb.raw
# (og uden -v year_fallback -> input-nofb.raw)
npx tsx packages/identity-candidates/src/cli.ts generate --input ~/.private/6b/task10/input-fb.json --source-id 1 \
  --top-k 5 --control-margin <x> --out ~/.private/6b/task10/cand-fb-<x>.json      # x ∈ 0.02 … 0.20
psql -X -d t6b_10_cal -v actor=… -v cand_file=~/.private/6b/task10/cand-fb-<x>.json \
  -f packages/identity-candidates/sql/write-candidates.sql
# Negativkontrol: 41 inputkopier ~/.private/6b/task10/neg/input-bNN.json, genereret som ovenfor og indsat direkte
psql -X -d t6b_10_cal -v source_id=1 -v input_sha256=a2df0f1d…f847 \
  -f packages/identity-candidates/sql/calibrate-publication-control.sql
npx tsx packages/identity-candidates/src/cli.ts calibrate --candidates ~/.private/6b/task10/cand-fb-0.05.json \
  --truth ~/.private/6b/task10/truth587.json
```
