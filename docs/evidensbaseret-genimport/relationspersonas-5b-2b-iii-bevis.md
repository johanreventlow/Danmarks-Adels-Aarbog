# Trin 5b del 2b-iii: børneflokkene binder til familien — færdigbevis i restore (2018-20)

- **Spec:** `docs/superpowers/specs/2026-10-20-trin5b-2b-iii-boernehenvisninger-design.md`, godkendt 2026-10-20.
- **Plan:** `docs/superpowers/plans/2026-10-20-trin5b-2b-iii-boernehenvisninger.md` (Task 1-6). Planen er reviewet af Opus (»GO med rettelser«), og rettelserne er indarbejdet.
- **Kørsel:** 2026-10-20 på grenen `docs/151-5b-2b-iii` i en kopi af runde 2's bevisbase, aldrig i prod.

Rapporten indeholder kun tal, hashes og basenavne. Den har ingen navne, ingen kildetekst ud over bogens faste henvisningsform og ingen person- eller aktør-id'er.

## Kort svar

**12 af de 14 børnepåstande er bundet til forælderens familie.** Læseren kan nu se, hvor i DAA 2018-20 børneflokken står:

| | Resultat |
| --- | --- |
| Bindinger | 241 → 253 |
| Børnekilder (`boern`) synlige for en anonym læser | 12, én i hver af de 12 familier |
| Kanoniske tabeller | Uændrede: aggregat-hashes ens og antal rækker uændret |
| 2a's tupel-digest | Uændret |
| Universet | Lukket (272). Børnespanden er gået fra 14 til 2. |
| Genkørsel | Giver 0 |
| Negativtests A-D | Afviser alle |

2b-iii skaber ingen nye slægtskaber. Alle børn sad allerede i familien. Det nye er kildehenvisningen.

De 2 påstande, der ikke er bundet, står uændret som `proposed`:
- én flok fordeler sig på to ægteskaber, og én påstand kan kun binde til én familie;
- én påstand har ingen entydig hovedperson.

## Grundlag

| | |
| --- | --- |
| Commit | `7ec66630` (grenen `docs/151-5b-2b-iii`, ikke pushet) |
| Fil-hashes (SHA-256) | `schema.sql` `4b583bff…38ca`, `db-migrations.sql` `b57a4701…1971`, `db-rls.sql` `ecd34683…f125`, `db-verify.sql` `799c1f59…5e84` |
| Arbejdsbase | `daa5b_2b_iii_bevis_20261020182757` er en kopi af `daa5b_navnv3_bevis_20261019200958` (originalen er uændret og bevares). Den er løftet med `db-migrations.sql` og `db-rls.sql`. `db-verify.sql` er grøn på en base bygget efter CI's opskrift. system_identifier: `7657242220770903427`. **Bevares.** |
| Kilde | 1 (DAA 2018-20), kontrakt 2 |
| Scripts | `~/.private/5b-2b-iii/` (0700, ikke i repo). `hashes.sql`, `univers.sql`, `read.sql` og `bind.sql` er de samme som i runde 2. `bind-preview.sql` `c3acdc0d…` har fået `relation.child` med. Nye: `afgoerelser.sql` `4c2313df…` og `neg.sh` `d75b8678…`. |
| Lokal CI | 7/7 `CI_JOB_OK` (parallelt, ingen genkørsel) og `UPGRADE_OK` på `69c1b08`. Efter arkets omlægning (`7ec66630`) er børnearkets e2e, pytest, db-verify og migrationsstien kørt igen. |

**Før-målingen gav runde 2's sluttal efter afvisningen af P-fortolkningen:**
- Bindinger: 241.
- Antal `person/family/family_member/fact/assertion/citation/conclusion`: 1811/682/2258/7197/9306/8579/9217.
- Universet: 272, heraf børnespanden 14.
- 2a's tupel-digest: `89bde760…5923`.
- Læsningen: 238 familier og 241 synlige kilderækker (234 ægteskab, 7 forælder).

## Erratum og henvisningsformen (spec §2)

Påstandene er krydshenvisninger til en hel børneflok: »N børn: <ordenstal> slægtled, <romertal>, nr. a–b«. Henvisningens dele passer med børnenes felter i `person_external_id`:

| Henvisningens del | Passer med børnenes |
| --- | --- |
| Ordenstallet | `slaegtled_lokal` |
| Parentesen (hvor den findes) | `slaegtled_gennem` |
| Romertallet | `linje` eller `kuld` |
| Intervallet | `nr` i forælderens `linje` |

Et tidligt tjek talte, hvor mange tekster parseren ikke kan læse. Resultatet var 1 af 14, nemlig påstanden uden hovedperson, hvis tekst er ét ord. Tallet var forventet.

## Arket (spec §6)

| | |
| --- | --- |
| Rækkefil | `rows.json` SHA-256 `e6691249…d3ea`: 14 rækker. 12 opfylder reglen, 2 er kort, og 2 bryder den (H3, samt H1 + H2 + H3). |
| Ark | `ARK_OK passer=10 kort=2 uden=2`. Godkendt SHA-256 `cd5edca3…d6a`, umodificeret med alle B. |
| Afgørelsesscript | `SQL_OK b=12 r=0 u=0`, 12 kald af `red_afgoer_relation_interpretation` med `human_sheet`-kontekst |

Projektejeren fandt det første ark svært at navigere i. Arket blev derfor lagt om, før det blev godkendt (commit `7ec66630`):
- vejledning øverst;
- nummererede linjer med forælderens navn, fødselsår og post;
- afvigelser og brud skrevet i almindelige ord.

Det første ark blev ikke godkendt og er omdøbt til `_forkastet_ark-v1.txt`.

## Afgørelse og binding (spec §6-§7)

| | |
| --- | --- |
| Afgørelser | 12 `accepted` med metoden `relation-child-v1`, og alle bærer arkets hash. 2 står `proposed`. |
| Bind-preview | 12 egnede, 241 `ALREADY_APPLIED`, 0 genbindinger, 0 accepterede uden struktur. Preview `7e416480…`, manifest-digest `4194058e…`. |
| Binding | 12 bindinger. Et identisk genkald giver samme batch og 0 nye rækker. Efter-digesten er lig manifest-digesten. |
| Genkørsel | 253 `ALREADY_APPLIED`, 0 egnede |

## Kontrolmålinger (spec §9)

| | Før | Efter |
| --- | --- | --- |
| Kanoniske aggregat-hashes | | **ens** (diff tom) |
| Antal `person/family/family_member/fact/assertion/citation/conclusion` | 1811/682/2258/7197/9306/8579/9217 | uændret |
| 2a's tupel-digest | `89bde760…5923` | `89bde760…5923` |
| Univers | 272 (børnespand 14, bundet 241) | 272 (børnespand 2, bundet 253) |
| Læsning: familier med kilder | 238 | 241 |
| Læsning: synlige kilderækker (ægteskab / forælder / børn) | 241 (234 / 7 / 0) | 253 (234 / 7 / 12) |
| Børnekilder som `anon` | 0 | 12 i 12 familier |

Kun 3 familier er nye i læsningen. De øvrige 9 havde allerede en kilde for ægteskabet og får nu også børneflokkens kilde.

Alle 12 familier er offentlige. Ingen af dem har et levende eller privat medlem, så `family_offentlig` skjuler ingen af børnekilderne.

## Negativtests (spec §9), i kopien `_neg`

| | Udfald | Skrivninger |
| --- | --- | --- |
| **A** Barn med egen post fjernet fra familien efter afgørelsen | Tilstanden er NULL: `accepteret_uden_struktur` 1, egnede 11. Påstanden kommer ikke med i bindingen. | Ingen binding af påstanden |
| **B** Forkert arkhash | `SHEET_HASH_MISMATCH` (rc 1) | Ingen fil |
| **C** Direkte `same` på påstanden, der bryder H3 | `RELATION_CHILD_RULE_NOT_MET` | Status stadig `proposed` |
| **D** Ukendt token (`S`) | `SHEET_TOKEN_NOT_ALLOWED` (rc 1) | Ingen fil |

Planen ville måle A som `RELATION_PROMOTION_STRUCTURE_INVALID` i preview. Bind-preview-scriptet sender dog kun påstande med gyldig tilstand videre, så vagten viser sig i stedet som »accepteret uden struktur«. Selve afvisningen, når en sådan påstand alligevel indsendes, er bevist i `tests/sql/test-relation-child.sql`.

Kopien er omdøbt til `slet_1020__2b_iii_bevis_20261020182757_neg` (84 MB; manifest `~/.private/5b-2b-iii/karantaene-1020.txt`). Den slettes kun efter et nyt ja.

## Fund

1. **Trykfejl i bogen (kort 11).** Henvisningen siger »9 børn«, men peger selv på nr. 2–9, altså 8 poster. Det er netop familiens 8 børn med det rigtige slægtled. Projektejeren vurderede det som en trykfejl i manuskriptet og beholdt B, så kilden peger på de rigtige 8 børn. Fundet kan meldes til redaktionen af næste udgave.
2. **Romertallet i henvisningen er linje eller kuld, ikke postpræfikset.** I brainstormen blev det først slået op som postpræfiks, og det fik 4 rigtige henvisninger til at ligne fejl. Regelen bruger nu børnenes `linje` eller `kuld` (spec §2).
3. **Én flok i to ægteskaber** (»17 børn«: 6 + 10) kræver, at én påstand kan binde til flere familier. Det er udskudt (spec §10).

## Afvigelser fra planen

- **Arket blev lagt om efter projektejerens ønske**, før det blev godkendt. Commit `7ec66630` indeholder også projektionen af forælderens navn.
- **Negativtest A er målt i preview-tællingen** (se ovenfor).
- **Planens »barn flyttet mellem afgørelse og binding« er udført som »barn fjernet«.** Det rammer samme vagt (H5_nr).
