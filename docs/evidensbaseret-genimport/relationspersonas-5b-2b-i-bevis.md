# Trin 5b del 2b-i — ægtefælle-undtagelser, kø og genbinding: færdigbevis i restore (2018-20)

Beslutning: `docs/decisions.md` 2026-10-12 (2b splittet; 2b-i er den slanke version uden nye RPC'er og
tabeller). Spec: `docs/superpowers/specs/2026-10-11-trin5b-2b-i-genbinding-og-aegtefaeller-design.md`
(errata §15, 2026-10-13). Plan: `docs/superpowers/plans/2026-10-12-trin5b-2b-i.md` (Task 0-9). Kørt
2026-10-12/13 på grenen `docs/151-5b-2b-i` i en kopi af 2a's bevisbase, aldrig i prod. Rapporten
indeholder tal, hashes og basenavne — ingen navne, ingen kildetekst og ingen persona-, person- eller
aktør-id'er.

## Kort svar

De **31** ægtefæller, som 2a efterlod i køen, er alle afgjort: **22** ved et undtagelsesark, hvor
projektejeren godkendte Claudes forudfyldte forslag uden rettelser, og **9** fra en token-fil over køen
(5 samme som hovedpersonens faktiske partner, 3 uafklarede, 1 ny person til 2b-ii). Arkets tre
ordinal-afvigelser er alle klassificeret `ordinal_beholdt` (familiens nummer beholdes). Efterkørslen
afgjorde og bandt **20** nye ægteskaber; 0 genbindinger, fordi intet `B` blev valgt. Den offentlige
læsning giver nu **230** kilderækker (210 + 20). Det kanoniske lag er uændret, 2a's 210 bindinger er
uændrede, og hver af kildens 272 relationspåstande ligger i præcis én spand. **7** ægteskaber bindes ikke,
fordi parret står i to familier i det kanoniske træ (issue #240); bindingen fejler lukket, som den skal
(errata §15.1). Genbindingsvejen er bevist i negativtest D.

## Grundlag

| | |
| --- | --- |
| Commit | kode `f943ed9`, errata `49713f7` (grenen `docs/151-5b-2b-i`, ikke pushet) |
| Fil-hashes (SHA-256) | `schema.sql` `ec536a17…d7bd`, `db-migrations.sql` `1db2aa56…fd26`, `db-rls.sql` `4ae2f3f5…5ede`, `db-verify.sql` `ea5864ff…dafa` |
| Arbejdsbase | `daa5b_2b_i_bevis_20261012093656` = kopi af `daa5b_2a_bevis_20261011185524` (uændret, bevares), løftet med `db-migrations.sql` + `db-rls.sql`; `db-verify.sql` grøn. system_identifier `7657242220770903427`. **Bevares.** |
| Kilde | 1 (DAA 2018-20), kontrakt 2 |
| Scripts | `~/.private/5b-2b-i/` (0700, ikke i repo): `hashes.sql` `f05df86c…`, `univers.sql` `e7037ee0…`, `decide.sql` `05d0ac45…`, `bind-preview.sql` `7a60b94e…`, `bind.sql` `a581be75…`, `read.sql` `c2658ed6…`, `neg.sh` `13de11ad…`, `koe-apply.py` `b3957cfb…` |

Før-målingen i arbejdsbasen gav præcis 2a's tal: de syv kanoniske hashes, v2-læsningen (50, `1447d4ec…`),
universet (272: bundet 210, ægtefælle `proposed` 31, uden ægtefælle-persona 14, barn 14, forælder `proposed`
2, forælder `rejected` 1), 0 accepterede uden gældende binding og 2a's tupel-digest `89bde760…5923`.

## Arket (spec §5)

| | |
| --- | --- |
| Rækkefil | `rows.json` SHA-256 `633629e0…eab1`: 22 S-rækker (alle tier `none`, 10 kandidater, kandidat 1 er partner i hovedpersonens familie), 3 O-rækker (bogen 1, familien 2) |
| Ark | 25 linjer, forudfyldt `S` ×22 og `F` ×3; godkendt SHA-256 `02c8cc0f…45d2` = den byggede fil (ingen rettelser) |
| Script | `apply.sql` SHA-256 `d70a08c9…`; kildelås, familielåse, rækkehash-vagt, tælleblok |
| Udfald | `S` 22, `A` 0, `U` 0, `B` 0, `F` 3; accepterede personas i kilde 1: 790 → 812; 0 change_sets (kun `B` skriver kanonisk) |

Hjælp til gennemsynet (privat, ikke i repo): et navnetjek (7 med alle navneled i kilden, 15 med nogle, 0
uden), et årstjek (ingen modsigelser; to usædvanlige aldersforskelle) og en familieoversigt pr. linje.
Familieoversigten afslørede de dobbelte familier (#240). O-forslaget `F` er begrundet med, at bogen ikke
nummererer ægteskabet: 1 er udtrækkets standard, og familiens 2 bærer et tidligere ægteskab.

## Køen (spec §6.4)

| | |
| --- | --- |
| Sager | 9 ægtefæller, detaljer hentet med `red_source_persona_detail` som `authenticated` (`koe-detaljer.json` `f1817406…`) |
| Token-fil | `koe.txt` godkendt SHA-256 `a2f6474c…81d5` = Claudes forslag (ingen rettelser); anvendt i én transaktion gennem `red_afgoer_source_persona` med `human_sheet`-kontekst (`koe-apply.sql` `a329da46…`), mængdevagt over de åbne sager og tælleblok |
| Klassifikation | anden kandidat/partner → `same` 5; ny person → `new_person_needed` 1 (2b-ii); uafklaret → `unresolved` 3 (parkeret); forkert udtræk 0; mulig familiefejl 0 |
| Efter | ægtefæller i kilde 1: `accepted` 230, `unresolved` 4, `proposed` 0 |

Observation til 2b-ii: i alle 5 `same`-sager var hovedpersonens faktiske partner (3/4–5/6 fælles navneled,
samme ægteskabsnummer) **ikke** blandt kandidatmatcherens 10 kandidater. Køens grund var
`partner_not_candidate`; detaljevisningens partnerboks (Task 6-7) er netop den vej, der fanger dem.

## Afgørelse og binding (spec §7)

| | |
| --- | --- |
| Afgørelse | preview 20 egnede, 4 nye ordinal-afvigelser, set-hash `e2bcc5d2…0960`; afgjort 20 (`family-structure-v1`); nøgle-digest se note |
| Preview | 20 egnede, 0 genbindinger, 210 `RELATION_PROMOTION_ALREADY_APPLIED`; 0 accepterede uden struktur; previewhash `7d9f57fc…047c` |
| Manifest (skrevet **før** bindingen) | `manifest.json` (0600), fil-SHA-256 `b911c79d…`; tupel-digest `f6eb575a625d0eb33a130fe36ba1c6f5944240b9c2c5dd225764456b78359c14` |
| Batch | 20 bindinger (alle ægteskaber, 20 familier), heraf 17 med vielsesfaktum |
| Efter-digest | `f6eb575a…9c14` = manifestet |
| Identisk genkald | samme batch-id, 0 nye rækker |
| Genkørsel af efterkørslen | afgørelse 0, preview 0 egnede (230 allerede bundet); et tomt manifest afvises af RPC'en (`RELATION_PROMOTION_ITEMS_INVALID`), så binding springes over |

Note: nøgle-digesten er md5 af de 223 sorterede fortolkningsnøgler med metode `family-structure-v1`
(203 fra 2a + 20), `1ee7ffefcff772d3d82ae1a97c7a82cf`. Klassifikationer i alt 10: 3 `ordinal_afvigelse`
fra 2a, 3 `ordinal_beholdt` fra arket, 4 nye `ordinal_afvigelse` (errata §15.3).

## 0 kanonisk delta og læsning

| Tabel | Før = efter (md5, som 2a) |
| --- | --- |
| `person` | `1d530c9e…4a3d` |
| `family` | `6519ecc6…2385` |
| `family_member` | `499bcd6b…054a` (uden `B` heller ikke `ordinal`-delta) |
| `fact` | `fb9728a6…e0e0` |
| `assertion` | `b47d13f8…2d48` |
| `citation` | `77ab9491…cc60` |
| `conclusion` | `7d99b7d6…b994` |
| v2-biografilæsning som `anon`, 50 faste personer (liste-md5 `4a3abe2d…c084`) | 50 rækker, `1447d4ec…8579` |

`public_family_sources` som `anon` for de 227 bundne familier: **230 rækker** (223 `aegteskab`, 7
`foraelder`), digest `b40da27e34c290b09cdccffa66334a17`. Læsekravet er 210 + nye bindinger (errata §15.2).

## Univers og globalt (spec §9)

| Spand | Antal |
| --- | --- |
| `accepted` med gældende binding | 230 |
| `accepted` uden gældende binding | **0** |
| ægteskab, ægtefælle `accepted`, parret i flere familier (#240, errata §15.1) | 7 |
| ægteskab, ægtefælle `new_person_needed` | 1 |
| ægteskab, ægtefælle `unresolved` | 3 |
| ægteskab uden ægtefælle-persona | 14 |
| `relation.child` (`proposed`) | 14 |
| forælder `proposed` | 2 |
| forælder `rejected` | 1 |
| **I alt** | **272**, univers-md5 `627b30962ffd6ae4c120d4d031679e7b` |

Globalt (alle kilder): 0 accepterede fortolkninger med familiebinding men uden gældende; historiske
bindinger 0 = genbindinger 0. 2a's 210 tupler genberegnet: `89bde760…5923` (uændret).

## Negativtests (spec §9; hver i sin egen kopi, taget før arket)

| Kopi | Indgreb | Udfald |
| --- | --- | --- |
| A | én S-persona afgjort efter udtrækket, derefter arkets script | `SPOUSE_SHEET_ROWS_STALE`, 0 skrivninger (accepterede 798 = 798) |
| B | en S-linje ændret til `A`, den godkendte hash givet | `SHEET_HASH_MISMATCH`, intet script skrevet |
| C | variantark med `B`, preview og manifest, derefter familiens nummer ændret igen | `RELATION_PROMOTION_PREVIEW_STALE`, 0 rækker (832 = 832) |
| D | variantark med `B` uden efterkørsel | familien 0 kilderækker og 1 accepteret uden gældende binding; efter efterkørslen 1 og 0, historiske 1 = genbindinger 1 |

C og D brugte et variantark (første O-linje `F` → `B`) med sin egen hash; det er kun en test og aldrig
anvendt i arbejdsbasen. Kopierne er omdøbt til `slet_1013__daa5b_2b_i_bevis_20261012093656_neg{A,B,C,D}`
(karantæne; manifest `~/.private/5b-2b-i/karantaene-1013.txt`; sletning kun efter måling og
projektejerens ja).

## Test og webspor

- **SQL i CI's friske sti:** unikhed pr. tilstand (Task 1), preview v2 og genbinding (Task 2),
  projektionen og `ordinal_beholdt` (Task 3), detaljevisningens partnerkontekst (Task 6).
- **Værktøjet** (`spouse_exception_sheet.py`): 13 pytest-tests; ende til ende mod en fixture-base
  (`test-spouse-exception-sheet.sh`) → `SHEET_E2E_OK`.
- **Opgraderingstest** fra 2a's head `31008f5` med eksisterende bindinger (`test-relation-binding-upgrade.sh`,
  kun lokalt): `UPGRADE_OK`; røgtest af deploystien fra `ebf2022` grøn.
- **Hele CI lokalt**: alle 7 jobs grønne (node: core 422, feed 129, identity-candidates 20, web 953,
  build, mobil-tsc, mobil 450; python 15 + 37 + 893; R 3299; fire PostgreSQL-jobs i hver sin klynge).
- **Web:** partnerboks og »Samme som denne partner« er dækket af vitest; Playwright er udeladt (ingen
  auth-harness lokalt; planens ruling).

## Advisors

Som 2a: `get_advisors` kan ikke pege på en lokal restore-kopi. `db-verify.sql` er grøn i bevisbasen, og
`get_advisors` køres som gate i overførslens runbook umiddelbart efter DDL.

## Review

Spec: Codex `gpt-5.6-sol` r1-r4 (alle NO-GO); Opus afvejede de 28 fund, og projektejeren godkendte den
slanke version 2026-10-12 (specens §14). Plan: ingen Codex-runde (projektejerens valg).

Kode-review af hele grenen (Opus, efter beviset): GO med forbehold, 0 Critical, 2 Important, 8 Minor. De to
Important er rettet i `7d89063`, efter beviset:

- **I1:** arkets SQL låser nu `standard_conforming_strings=on`, så en note med backslash når databasen uændret.
- **I2:** arket tåler et tomt ægteskabsnummer (`?`). Et `B` uden bogens nummer afvises.

Beviset kørte med værktøjet fra før rettelsen. De rettede stier blev ikke ramt af bevisets input: arket blev
godkendt uændret, så det havde kun standardnoter uden `'` eller `\`, og ingen af de 3 O-linjer havde et tomt
nummer. Projektejeren godkendte, at Playwright-testen udelades. De 8 Minor er udskudt.

## Status

5b del 2b-i er **bevist i restore, ikke deployet**. Intet fra 5a eller 5b er i prod. Åbent:

- **#240** dobbelte familier (5 par): når de er lagt sammen, afgør og binder en ny efterkørsel de 7
  ægteskaber.
- **Kendte begrænsninger** (spec §12 pkt. 1-8 og errata §15.3-4): bl.a. samtidige familieredigeringer,
  ingen kvittering, `F` via operatørens script, de 4 nye ordinal-afvigelser til næste ark og arkets
  familievisning ved dubletter.
- **2b-ii:** 1 ny person (`new_person_needed`), klausul-disposition; de 3 `unresolved` er parkeret.
