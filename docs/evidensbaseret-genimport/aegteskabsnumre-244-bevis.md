# #244: ægteskabsnumrene efter skriverens vindue — færdigbevis i restore (2018-20)

- **Spec:** `docs/superpowers/specs/2026-10-20-244-aegteskabsnumre-design.md`, godkendt 2026-10-20.
- **Plan:** `docs/superpowers/plans/2026-10-20-244-aegteskabsnumre.md` (Task 1-6). Planen er reviewet af Opus, og rettelserne er indarbejdet før udførelsen.
- **Kørsel:** 2026-10-20 på grenen `fix/244-aegteskabsnumre` i en kopi af 2b-iii's bevisbase, aldrig i prod.

Rapporten indeholder kun tal, hashes og basenavne. Den har ingen navne, ingen kildetekst og ingen person- eller aktør-id'er.

## Kort svar

**De 4 skæve ægteskabsnumre er rettet og genbundet i samme familie.** Fremover regner systemet nummeret ud fra samme placering i teksten, som skriveren bruger. Nye fejl af samme slags afvises, når bogens eget »g. N°« siger noget andet.

| | Resultat |
| --- | --- |
| Rettede numre | 4 (2 poster, byttet 1↔2), via et hash-bundet ark med 4 linjer, alle `B` |
| Genbindinger | 4, alle med `supersedes_promotion_id`, til samme familie |
| Kanoniske tabeller og `family_member.ordinal` | Uændrede |
| 2a's tupel-digest | Uændret |
| Universet | 272 (uændret) |
| Læsning | Som før: 241 familier, 253 synlige kilderækker |
| `book_ordinal≠family_ordinal` | 10 → 6. De 6 er ægte afvigelser, se fund 1 |
| »N°« lig serverens nummer | 40 af 40 |
| Negativtests | 6 af 6 afviser |

## Grundlag

| | |
| --- | --- |
| Commit | `b335acc5` (grenen `fix/244-aegteskabsnumre`, ikke pushet) |
| Fil-hashes (SHA-256) | `schema.sql` `c6981ca5…0f74`, `db-migrations.sql` `4f5ef719…20e4`, `db-rls.sql` `cccaa40a…f44b`, `db-verify.sql` `cf40b39c…3cc3` |
| Arbejdsbase | `daa244_bevis_20261020222244` er en kopi af `daa5b_2b_iii_bevis_20261020182757` (originalen er uændret og bevares). Den er løftet med `db-migrations.sql` og `db-rls.sql` uden fejl. system_identifier: `7657242220770903427`. **Bevares.** |
| Kilde | 1 (DAA 2018-20), kontrakt 2 |
| Scripts | `~/.private/244/` (0700, ikke i repo). `antal.sql`, `hashes.sql`, `univers.sql`, `read.sql`, `bind-preview.sql` og `bind.sql` er de samme som i 2b-iii. Nye: `maal.sql` `3b1fd849…`, `maal-6.sql` `aaa2d5d2…`, `mellem.sql` `a4ba2eec…`, `tupler.sql` `0ecb9c2d…`, `afgoerelser.sql` `511071a8…` og `neg.sh` `704a6f98…`. |
| Lokal CI | 7/7 `CI_JOB_OK` og `UPGRADE_OK` på `b335acc5`. Writer-jobbets låsetest var flaky under parallel kørsel og grøn ved genkørsel alene. |
| Tid (som ejer, varm) | `relation_persona_input(1)`: original 80–93 ms, kopi 105–112 ms. Bind-preview: original 1,0–1,3 s, kopi 0,8 s. Begge under 2 × originalen. |

**2a's tupel-digest** udvælger bindinger uden nøglen `supersedes_promotion_id`. Promote skriver altid nøglen (JSON-null ved første binding), så digesten dækker kun de 210 bindinger fra før 2b-i. Genbindingerne har nøglen og ændrer den ikke. Digesten siger derfor intet om de 43 senere bindinger. Det er noteret til Fable-reviewet af trin 1-5. Digesten over de gældende bindinger (nedenfor) dækker dem.

## Erratum (spec §2)

Runde 2-rapportens fund 1 og issuet sagde, at påstandens tekst »rækker ud over klausulen«. Det er forkert. Den rå tekst springer et stykke midt i klausulen over, typisk en parentes. `relation_marriage_ordinals` søgte efter hele den rå tekst med `strpos`, fik NULL og sorterede påstanden sidst. Skriveren placerede den rigtigt med det eneste minimale ordnede ordvindue. Rettelsen lader funktionen bruge samme vindue (`private.relation_ordered_windows`).

## Arket (spec §6)

| | |
| --- | --- |
| Rækkefil | `rows.json` SHA-256 `5949e021…86a3`: 4 rækker |
| Ark | `ARK_OK linjer=4 uden=0`. Godkendt SHA-256 `78a3040e…0d09`, umodificeret med alle `B` |
| Afgørelsesscript | `SQL_OK b=4 u=0`: 4 kald af `red_ret_aegteskabsnummer` med `human_sheet`-kontekst |

I alle 4 linjer siger bogens »N°« og familiens nummer det samme. Det gemte nummer var det modsatte.

## Rettelse og binding (spec §7-§8)

| | |
| --- | --- |
| Anvendt | rc 0. 4 rækker i `marriage_ordinal_correction` og 4 nye partversioner med `origin='ordinal_correction'`. Inputtet giver derefter 0 rækker. |
| Mellemtilstand | 249 gældende bindinger. Synlige kilderækker 253 → 249 (ægteskab 234 → 230). Det er synlighedshullet fra spec §8. |
| Bind-preview | 4 egnede, alle 4 genbindinger, 249 `ALREADY_APPLIED`, 0 accepterede uden struktur. Preview `d7fc3531…`, manifest-digest `e0a2e4f3…`. |
| Binding | 4 bindinger, 4 med `supersedes`. Et identisk genkald giver samme batch og 0 nye rækker. Efter-digesten er lig manifest-digesten. |
| Genkørsel | 253 `ALREADY_APPLIED`, 0 egnede |
| De 4 genbindinger | Samme fortolkning og samme familie som den afløste binding. Tilstandshashen er ny. |

## Kontrolmålinger (spec §9)

| | Før | Efter |
| --- | --- | --- |
| Kanoniske aggregat-hashes | | **ens** (diff tom) |
| Antal `person/family/family_member/fact/assertion/citation/conclusion` | 1811/682/2258/7197/9306/8579/9217 | uændret |
| `family_member.ordinal`-digest | `cfa061ad…0054` | uændret |
| 2a's tupel-digest | `89bde760…5923` | uændret |
| Bindingsrækker | 253 | 257 (4 historiske) |
| Gældende bindinger | 253 | 253 |
| Digest over gældende bindinger | `a9d34268…37b0` | `10095e43…d2a5` (4 tupler ændret) |
| `book≠family` blandt gældende | 10 | 6 |
| Bundne ægteskaber med anden metode end `family-structure-v1` | 0 | 0 |
| Univers | 272 | 272 |
| Læsning: familier / synlige kilderækker | 241 / 253 | 241 / 253 |
| »N°« lig serverens nummer | 40 af 40 | 40 af 40 |

## Negativtests, i kopien `_neg`

Kopien er taget efter rettelsen. Gentagelserne (B-D) rammer derfor den rettede tilstand.

| | Udfald | Skrivninger |
| --- | --- | --- |
| **A** Forkert arkhash | `SHEET_HASH_MISMATCH` (rc 1) | Ingen fil |
| **A2** Token `R` i arket | `SHEET_TOKEN_NOT_ALLOWED` (rc 1) | Ingen fil |
| **B** Samme afgørelsesscript igen | `MARRIAGE_ORDINAL_CORRECTION_VERSION_MISMATCH` (rc 3) | Ingen |
| **C** Direkte kald med partversion 1 | `…_VERSION_MISMATCH` | Ingen |
| **D** Direkte kald med partversion 2 (gemt = nyt) | `…_NOT_NEEDED` | Ingen |
| **E** Kald som ikke-redaktion | `EVIDENCE_ROLE_FORBIDDEN` | Ingen |

Rettelsesrækker før og efter: 4 og 4. Kopien er omdøbt til `slet_1020__244_bevis_20261020222244_neg` (83 MB; manifest `~/.private/244/karantaene-1020.txt`). Den slettes kun efter et nyt ja.

## Fund

1. **6 ægte afvigelser mellem bog og familie.** Spec §9.2 ventede `book≠family` = 0 efter rettelsen. Målt var 10 før: de 4 skæve og 6 andre. I de 6 er det gemte nummer lig serverens nummer, og familiens nummer afviger. 2 af dem har bogens »N°« lig det gemte nummer. De er klassificeret tidligere (`ordinal_afvigelse`/`ordinal_beholdt`) og hører ikke til #244.
2. **Prod-genspil kræver et udtrykkeligt valg i overførsels-spec'en (spec §10).** De autoriserede `relation_persona`-payloads for de 2 poster bærer det gamle nummer. Med den rettede funktion afviser skriveren dem med `SPAN_INVALID`, så en overførsel af 5a+5b vil stoppe på netop dem. Overførsels-spec'en skal vælge én af to veje og bevise den i restore:
   - ny autorisation af de batches, de 4 elementer ligger i; eller
   - genspil af de oprindelige batches med den gamle funktion, derefter rettelse og genbinding.

   Den skal også håndtere synlighedshullet mellem rettelse og genbinding.
3. **Familiekorroborationen er lukket for de 4 ægtefællepersonaer** efter rettelsen. Den var allerede lukket for dem, fordi deres identitet er accepteret.

## Afvigelser fra planen

- **`book≠family` efter er 6, ikke 0** (fund 1). Ruling i ledgeren.
- **`_neg`-kopien er taget efter rettelsen**, ikke før. Gentagelse og `NOT_NEEDED` rammer derved netop den rettede tilstand.
- **Negativtest E (rolle) er tilføjet** ud over planen.
- **Det første preview-kald manglede manifest-stien.** psql skrev derfor filen `:manifest`. Den var identisk med det senere manifest og er omdøbt til karantæne.
