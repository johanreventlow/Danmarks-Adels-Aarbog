# Trin 5a — én identitetsvej: færdigbevis i restore (2018-20)

Beslutning: `docs/decisions.md` 2026-10-05 (trin 5 aktiveret, 5a først). Spec:
`docs/superpowers/specs/2026-09-24-trin5a-identitetsvej-design.md`. Plan:
`docs/superpowers/plans/2026-09-24-trin5a-identitetsvej.md` (Task 9). Kørt 2026-10-05 i en kopi af den
fulde 2018-20-kørsels base, aldrig i prod. Rapporten indeholder tal, hashes og basenavne — ingen navne,
ingen kildetekst og ingen persona- eller person-id'er.

## Kort svar

Identitetsvejen virker ende til ende med et rigtigt menneske: maskinen foreslår kandidater, redaktøren
afgør dem i et hash-bundet token-ark eller gennem webkøens RPC, og hver afgørelse står i databasen med
aktør, grundlag og — når en kandidat blev fulgt — kandidat, kørsel og rang. Af 30 blindt genbekræftede
personas fulgte redaktøren kandidat 1 i 24 og lod 6 stå uafklarede; alle 24 er samme person som den
eksisterende kobling (0 forskellige). Webspor og arkspor skriver samme evidens bortset fra arkets egne
bindinger. En forældet afgørelse afvises atomisk.

Kalibreringen er en **øvre grænse**: facit er 149b's faste 1:1-kobling, og personerne er oprettet fra
de samme poster. Den viser også tre svagheder, der hører til 5b (sidst i rapporten).

## Grundlag

| | |
| --- | --- |
| Arbejdsbase | `daa5a_bevis_20261005223551` = kopi af `daa2018f_20261001133125` (den fulde 2018-20-kørsel, samme indhold som prod efter overførslen 2026-10-05), løftet med `db-migrations.sql` + `db-rls.sql` (0 fejl — også cutover-blokken på et prod-ækvivalent katalog) |
| Kilde | 1 (DAA 2018-20) |
| Facit | 587 accepterede identiteter, alle med autoritet `person_external_id` (149b) |
| Generator | `identity-candidates-1.0`, standardscoring (se valget nedenfor) |

## Kalibrering (§8.1)

Alle 587 accepterede personas i kilde 1 (`mode=list`); navn fra `person.name`-fortolkningen (accepted
eller proposed) eller mention-fallback. Kalibreringen skriver intet i databasen.

| | std | normaliseret |
| --- | --- | --- |
| Personas | 587 | 587 |
| Uden navn (og dermed uden kandidat) | 337 | 337 |
| Med navn | 250 | 250 |
| Top-1 rigtig | 228 (91 % af 250) | 199 (80 %) |
| Top-3 rigtig | 240 (96 %) | 223 (89 %) |
| `auto` (rang 1): antal / rigtige | 159 / 159 | 34 / 33 |
| `review`: antal / rigtige | 50 / 50 | 216 / 166 |
| `none`: antal / rigtige | 41 / 19 | 0 / 0 |

Særskilt for personas **uden årstal** (ingen parsebart fødsels- eller dødsår):

| | std | normaliseret |
| --- | --- | --- |
| Med facit | 185 | 185 |
| Uden kandidat | 151 | 151 |
| Top-1 / top-3 | 14 / 25 | 14 / 25 |
| Rang-1-tier | `none` 34 (14 rigtige) | `review` 34 (14 rigtige) |

**Valg: standardscoring** — højere top-1 (228 mod 199) og fuld præcision for `auto` (159/159 mod
33/34). Ingen tærskel blev sat på forhånd; tallene afgør kun konfigurationen, ikke automatisk accept
(5a accepterer aldrig automatisk).

**Tyndhed og forbehold:**

- **337 af 587 er uden navn.** Kun 263 personas har en `person.name`-fortolkning (250 accepted, 13
  unresolved — de uafklarede bruges ikke). Mention-fallback rammer intet i kilde 1: alle personaens
  mentions har typen `person_post` (hele posten), ikke `person`, og hele posten er ikke et navn.
- **Facit er cirkulært.** Alle 587 identiteter er 149b's faste kobling, og personerne er oprettet fra de
  samme poster; navn og år ligner derfor mere end ved en virkelig ny udgave. Tallene er en øvre grænse.
- **Kendte titelfejl** i `person.name` (decisions 2026-10-03; 138 navne-assertions med titelord)
  trækker navnelighed ned.
- Kalibreringen gentages i 5b på andre personer end hovedpersonerne.

## Blind genbekræftelse (§8.2)

Stikprøve: 30 personas stratificeret på rang-1-tier (12 `auto`, 12 `review`, 6 `none`) plus én persona
reserveret til webspor-pariteten. Arket viste kun kandidaterne, ikke det gamle svar.

| | |
| --- | --- |
| Kandidatkørsel (gældende) | 31 personas, 93 kandidater; input `1b5efdfe…f19e`, config `0815d06d…dda6`, kandidater `ed6c236e6c8a42d0675c765fd0dad362d6e6dbc0a3ca34987a6138b6dd6f329f` |
| Rækkefil | `e7df4f4a67384f7bb03222caa20f1865cda3b5f04befd9f2ca04840e39ff2bd9` |
| Godkendt ark | `ada4e9fdee2fb19bb1b4cbaec45ce6bb3247f23fa93ad5944e2e22b5b03b7789` (30 linjer: 24 × kandidat 1, 6 × `U`) |
| Negativtest | Kopi af SQL'en med sidste afgørelses version +1: `EVIDENCE_IDENTITY_VERSION_CONFLICT`, 0 nye hændelser (595 → 595) — hele arket ruller tilbage |
| Arkkørsel | rc 0, 30 nye hændelser i én transaktion |

Sammenligning med den eksisterende kobling (begge spor samlet, 31 afgørelser):

| Samme person | Anden person | Ikke accepteret | Kandidat fulgt |
| --- | --- | --- | --- |
| 25 | 0 | 6 | 25 |

De 6 uafklarede er personas, hvor redaktøren ikke kunne afgøre identiteten ud fra det viste — fx tre
kandidater med samme navn, uden årstal og med samme score.

## Webspor-paritet

Webkøen blev ikke startet mod arbejdsbasen (ingen lokal API, spec §8.2). Redaktøren afgjorde
webspor-personaen ud fra kandidatlisten (kandidat 1); payloaden er den, webkøens vitest fastlåser
(`p_context: {basis:'web_detail', candidate_id, run_id}`), sendt som `authenticated` med redaktørens
aktør. Resultat: `accepted`, rang 1, aktør sat.

| Evidensnøgler | |
| --- | --- |
| Webspor | `action, basis, candidate_id, candidate_rank, note, run_id` |
| Kun i arkspor | `line, rows_sha256, sheet_sha256` (arkets egne bindinger) |
| Kun i webspor | — |

## Svagheder til 5b

1. **`samme_som`-klynger.** Generatoren kender ikke de 719 `samme_som`-relationer mellem personer. Samme
   historiske person (fx én person fra 2018-20 og én fra 1939, allerede koblet) står derfor som flere
   kandidater; redaktøren ser konkurrerende kandidater, og en lige score mellem dem ville blokere `auto`.
   Kandidater i samme klynge bør slås sammen eller markeres.
2. **1939-personers årstal.** Matcheren læser kun den valgte assertions `date_min`/`date_max`; for
   1939-personer er det udfyldt for 18 af 370 fødselsassertions. 1939-kandidater får derfor næsten kun
   navnesignal. Årstal bør udledes af den rå tekst, når den parsede dato mangler, eller 1939's datoer
   udfyldes.
3. **Kandidatvisningen.** Ark og webkø viser kun navn og leveår. Ved navnesammenfald uden år har
   mennesket intet at afgøre på; kandidaternes embeder, titler og post bør vises.

## Review

Anden læser (Codex `gpt-5.6-sol`): planen 4 runder (GO 2026-10-05); koden 2 runder — runde 1 NO-GO
(token-arkene læste arket igen efter hash-tjekket; webkøen kunne vise en tidligere personas detalje ved
omvendt svarrækkefølge), begge rettet med regressionstest, runde 2 GO uden fund. Hele CI (7 jobs) er
genafspillet lokalt og grønt.
