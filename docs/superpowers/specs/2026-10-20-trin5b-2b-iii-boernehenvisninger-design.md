# Trin 5b del 2b-iii — børnehenvisningerne binder til familien (#151)

**Status:** Designet blev godkendt i brainstormen 2026-10-20 i tre dele. Projektejeren valgte:
- **mål:** kildehenvisning på børnene, frem for kun oprydning;
- **tilgang A:** flokken binder til forælderens familie, frem for ét barn pr. påstand (B) eller en ny påstandstype (C);
- **del 1** med køn som blokerende krav og romertal som krav for den maskinelle vej;
- **del 2:** 6 maskinelt, 2 af dem i stikprøven, og 7 kort med forudfyldte forslag;
- **del 3:** binding med flok-digest og læservisning i web, kun i restore.

**AFVENTER projektejerens gennemgang af den skrevne spec.**

**Roadmap:** trin 5, delspec 5b, del 2, skive b-iii. Dokumenterne kaldes herefter:
- »hovedspecen«: `docs/superpowers/specs/2026-10-06-trin5b-relationspersonas-design.md`;
- »2a-specen«: `docs/superpowers/specs/2026-10-11-trin5b-2a-binding-design.md`;
- »2b-ii-specen«: `docs/superpowers/specs/2026-10-17-trin5b-2b-ii-nye-personer-og-disposition-design.md`.

Beslutninger: `docs/decisions.md` 2026-10-10 (børn taget ud af del 1) og 2026-10-17 (børn til 2b-iii).

## 1. Adgangskrav (roadmap)

| Krav | Svar |
| --- | --- |
| Roadmapmål | Trin 5 (#151), 5b »personas for ægtefæller og børn« |
| Værdikædeled | Fortolkning → relationsafgørelse (maskinel regel og menneske) → binding → offentlig læseprojektion med kildehenvisning |
| Leverancetype | Generel regel `relation-child-v1` (`structural_family`) og en udgaveprofil for 2018-20's henvisningsform. Ingen nye tabeller. |
| Redaktionel/læserrettet værdi | 8 familier får en kilderække for deres børneflok. Læseren kan se, hvor i DAA 2018-20 forælder→barn-forbindelsen står. |
| Færdigbevis | §9 |
| Erstatter | `RELATION_CHILD_DEFERRED`: de 14 `relation.child` står i dag som `proposed` uden vej videre |

## 2. Erratum til hovedspecen §22.9

§22.9 antog, at en børnepåstand nævner ét barn, så valget stod mellem flere børn. Det er forkert. Målt i bevisbasen `daa5b_navnv3_bevis_20261019200958` den 2026-10-20 er påstandene **krydshenvisninger til en hel børneflok**, i formen »N børn: <ordenstal> slægtled, <romertal>, nr. a–b«. De står sidst i forælderens post, og børnene står i deres egne poster inden for nummerintervallet.

Tilfældene er nummereret 1–14 i påstandenes nøgleorden:

| Tilfælde | Antal | Hvad der passer |
| --- | --- | --- |
| 1, 2, 3, 4, 8, 9 | 6 | Det hele: angivet antal = intervallets længde = familiens barnerækker = børn med egen post, og alle ligger i intervallet med forælderens præfiks. |
| 7, 10, 11, 12 | 4 | Numrene passer med forælderens præfiks, men romertallet peger på en anden afdeling. |
| 5 | 1 | »9 børn«, men intervallet og familien har 8. |
| 6 | 1 | »17 børn« uden henvisning; 16 børn med egen post i 2 ægteskaber (6 + 10). |
| 13 | 1 | »3 sønner (?)« uden henvisning; 3 sønner i én familie. |
| 14 | 1 | Ingen entydig hovedperson. |

**Romertallet** betegner afdelingen eller linjen i stamtavlen (I–V), samme slags betegnelse som postpræfikset. I de 6 rigtige henvisninger er det lig forælderens præfiks.

I de 4 afvigende tilfælde gennemgik projektejeren navne og årstal den 2026-10-20 og afgjorde, at **databasens familie har ret, og at henvisningen i bogen eller OCR'en er forkert**:
- **7 og 12:** henvisningens slægtled er umuligt i forhold til forælderens fødselsår.
- **11 og 12:** posterne findes ikke, fordi afdeling II slutter ved nr. 35.
- **10:** projektejerens vurdering.

Alle ca. 77 børn sidder allerede som `barn` i forælderens familie. 2b-iii skaber derfor **ingen nye slægtskaber**. Det giver kildehenvisning på forbindelser, der findes i forvejen.

Køn: i de 3 påstande, der siger »døtre« eller »sønner«, har alle børn det rigtige køn (2/2, 4/4 og 3/3). Ingen barnerække i de berørte familier er `omstridt`.

## 3. Afgrænsning

**Med:**
- de 14 `relation.child` i kilde 1;
- reglen `relation-child-v1`;
- `relation_binding_state` for `relation.child`;
- `public_family_sources` med slags `boern`;
- web-visning;
- arket for 2b-iii.

**Udenfor:**
- prod-overførsel;
- mobil-appen (kun til udvikling);
- #244 (ægteskabsnumre);
- #240 (dobbelte familier);
- børn uden henvisning i andre udgaver (1939 hører til trin 6);
- at rette bogens forkerte henvisninger.

## 4. Henvisningsparseren (udgaveprofil, Python og SQL-tvilling)

Henvisningen læses deterministisk af påstandens `raw`; ingen model læser teksten. Grammatikken:

```
henvisning := antal [ " (?)" ] [ ":" sted ]
antal      := TAL (" børn" | " døtre" | " sønner") | "Datter" | "Søn"        (Datter/Søn ⇒ antal 1)
sted       := ordenstal [ " (" ordenstal ")" ] " slægtled," [ " " ROMERTAL "," ] " nr. " TAL [ BINDESTREG TAL ] [ "." ]
```

- `BINDESTREG` omfatter `-`, `‑` (U+2011) og `–`.
- Resultatet er:
  - `count`;
  - `sex`: `kvinde` (døtre/Datter), `mand` (sønner/Søn) eller NULL;
  - `uncertain`: sand, når `(?)` står i teksten;
  - `generation_text`;
  - `section`: romertallet eller NULL;
  - `nr_from` og `nr_to`.
- **Tekst, der ikke følger grammatikken, giver `parse = NULL`.** Påstanden bliver så et kort eller U, aldrig en maskinel afgørelse.
- Python-funktionen (`relation_child_ref.py`) og SQL-tvillingen (`private.relation_child_ref(text)`) låses mod hinanden af en tvillingtest, som i 2b-ii runde 2.

## 5. Matchreglen `relation-child-v1`

En påstand er **maskinelt egnet**, når alle betingelser holder:

1. Påstanden er `proposed`, citerer præcis én klausul, og hovedpersonen har en accepteret identitet med præcis én postnøgle i kilde 1, med præfiks `P` og nummer.
2. `parse` er ikke NULL, `section` og `nr_from` er sat, og `uncertain` er falsk.
3. `section = P`.
4. `count = nr_to − nr_from + 1`.
5. Hovedpersonen er `partner` i præcis én familie `F`, hvor der er børn med egen post i kilde 1 (`relation_structural_candidates`). Ingen af `F`'s rækker er `omstridt`.
6. Mængden af postnøgler for `F`'s børn med egen post er netop `{P-nr_from … P-nr_to}`.
7. Antallet af barnerækker i `F` er lig `count`.
8. Er `sex` sat, har alle barnerækker i `F` det køn.

**Resultat på de 14 tilfælde:**

| Tilfælde | Udfald |
| --- | --- |
| 1, 2, 3, 4, 8, 9 | Egnede |
| 7, 10, 11, 12 | Ikke egnede (3) |
| 5 | Ikke egnet (4 og 7) |
| 6, 13 | Ikke egnede (2) |
| 14 | Ikke egnet (1) |

## 6. Afgørelsesvejen

**Den maskinelle vej:** `red_afgoer_relation_interpretation` får `basis = 'machine_rule'`. Kravene er:
- handlingen er `same`;
- `p_family_id` er NULL, fordi serveren selv udleder `F` efter §5;
- konteksten bærer arkets hash, rækkefilens hash og rækkenummeret i rækkefilen (`line`), så også de maskinelle afgørelser er bundet til det godkendte ark.

Serveren genberegner §5 under familielåsen (`lock_family_rows`). Er en betingelse brudt, kaster den `RELATION_CHILD_RULE_NOT_MET`.

`RELATION_CHILD_DEFERRED` fjernes. For `relation.child` gælder:

| Handling | Krav |
| --- | --- |
| `same` | Basis `machine_rule` eller `human_sheet`. Med `human_sheet` kræves betingelse 1, 5 og 8. Betingelse 6 kræves, når henvisningen har et interval i forælderens afdeling; ellers kræves blot mindst ét barn med egen post i `F`. Betingelse 2, 3, 4 og 7 kan tilsidesættes af mennesket, og kortet viser afvigelsen. |
| `rejected` / `unresolved` | Kun `human_sheet` eller `web_detail` |

- Der indsættes **ingen** `child`-part. Evidensen bærer `family_id`, flok-digestet (§7) og de parsede felter.
- Afvigelser fra §5 skrives i afgørelsens evidens som `afvigelser` (fx `henvisning_afviger`, `antal_afviger`, `uden_henvisning`). Klassifikationstabellen bruges ikke, fordi dens CHECK kun gælder ordinal-klassifikationerne.

**Arket** (`relation_child_sheet.py`) følger 2b-ii's form: rækkefil → render → menneskets gennemgang med `open -e` → hash i chat → `sql` → manifest og afgørelsesscript.
- **Kort:** de egnede, der ikke er i stikprøven, kommer ikke på arket. Kortene er de ikke-egnede med en hovedperson (7) plus en stikprøve på 2 af de egnede, trukket deterministisk ud fra rækkefilens hash.
- **Tokens:** `B` (bind), `R` (afvis), `U` (uafgjort). Stikprøven tager kun `B`/`R`; ét `R` i stikprøven stopper hele den maskinelle del.

| Kort | Forudfyldt |
| --- | --- |
| 7, 10, 11, 12 | `R`, med begrundelsen »fejlhenvisning; familien er rigtig« |
| 5, 13 | `B` |
| 6 | `U` (to familier, og påstanden kan kun binde til én) |

- **Hvert kort viser:** bogens tekst, de parsede felter, `F`'s børn (navn, fødselsår, postnøgle) og, ved afvigende afdeling, de poster, henvisningen peger på, og deres forældre.
- **Arket er privat** (`~/.private/5b-2b-iii/`, 0600), aldrig i repo eller chat.
- Tilfælde 14 kommer ikke på arket. Det forbliver `proposed`, som i 2b-ii.

## 7. Bindingen

`private.relation_binding_state` får en gren for `relation.child`. Den kræver en accepteret påstand med `family_id` i evidensen og hovedpersonen som `partner` i familien, og returnerer:

```
{contract:'relation-binding-state-v1', interpretation:{…}, parties:[principal],
 family:{family_id, rows:[principal-partnerrækken + alle barnerækker (person_id, rolle, ordinal, konfidens)]},
 counterpart_person_id: NULL, children:{count, section, nr_from, nr_to, sex}}
```

- **NULL**, hvis en barnerække er `omstridt`, eller hvis hovedpersonen ikke længere er `partner` i familien.
- **Drift:** digestet ændrer sig, når et barn tilføjes, fjernes eller flyttes. Den eksisterende kontrol i `public_family_sources` (`reimport_canonical_json_sha256(st) = bound_sha`) skjuler så kilden, indtil genbinding.
- **Regelregistret:** `('relation-child-v1','relation.child')` og reglen `('relation-child-v1',1,'relation.child','relation','family',NULL,'relation',false,false,true,'active','structural_family')`.
- **Bindingsvejen:** `decide.sql`, bind-preview og `red_promote_relation_interpretations_batch`, som i 2a.
- **Ordinal-klassifikationerne** gælder kun ægteskaber. Børn klassificeres ikke.

## 8. Læseren

**`public_family_sources`:**
- `slags = CASE predicate WHEN 'relation.marriage' THEN 'aegteskab' WHEN 'relation.parent' THEN 'foraelder' ELSE 'boern' END`;
- for `boern` er `counterpart_person_id` forælderen (hovedpersonen);
- publicerings- og familiegaten er uændret.

**`packages/core`:**
- `FamilieKilde.slags` udvides med `'boern'`, og `mapFamilieKilder` godtager det;
- `familieIderForPerson` returnerer desuden `boerneFamilier`: de familier, hvor fokuspersonen er partner og har børn.

**`DetailPanel` (web):**
- hos forælderen vises kildelinjen ved børnelisten for den familie, den hører til;
- hos et barn vises den ved den forælder, der er modpart, og kun i barnets fødselsfamilie.

En ældre klient springer `boern` over, fordi `mapFamilieKilder` frasorterer ukendte slags.

## 9. Færdigbevis

**CI (syntetiske personer):**
- **Parseren og tvillingtesten:** alle former i §4, inkl. `Datter:`, `(?)`, U+2011 og tekst uden henvisning.
- **Reglen** for hver betingelse i §5: forkert afdeling, forkert antal, et ekstra barn uden post, forkert køn, to familier, `omstridt` og `uncertain`.
- **Writeren:**
  - `machine_rule` med brudt regel giver `RELATION_CHILD_RULE_NOT_MET`;
  - `human_sheet` kan tilsidesætte 2/3/4/7, men ikke 5/6/8;
  - `rejected`;
  - ingen `child`-part.
- **Bindingen:** et barn tilføjet efter binding gør kilden usynlig; `omstridt` giver NULL.
- **Core og web:** `boern` vises ved begge personer, og en ukendt slags springes over.
- **Arket:** e2e-test (render, hash, `sql`, ét `R` i stikprøven stopper maskindelen), i `.github/workflows/ci.yml`.

**Restore** (en kopi af `daa5b_navnv3_bevis_20261019200958`, aldrig prod):
- rækkefil og ark; projektejerens gennemgang og hash; afgørelser; decide; bind-preview; binding; genkørsel 0;
- **forventet med de forudfyldte svar:**
  - 8 bindinger (6 maskinelt + 5 og 13);
  - 4 `rejected`;
  - 1 `unresolved` (6);
  - 1 `proposed` (14);
- læsningen +8 kilderækker af typen `boern`; universets spand `barn_2c_proposed` falder fra 14, og fordelingen på de øvrige spande måles og rapporteres;
- kanonisk delta 0 (aggregat-hashes ens), 2a's tupel-digest uændret;
- **negativtests:**
  - et barn flyttet efter manifestet ⇒ binding afvist;
  - forkert arkhash;
  - et `U` hævet til `B` ⇒ `SHEET_TOKEN_NOT_ALLOWED`;
  - `machine_rule` på et ikke-egnet tilfælde ⇒ `RELATION_CHILD_RULE_NOT_MET`.

**Rapport:** `docs/evidensbaseret-genimport/relationspersonas-5b-2b-iii-bevis.md`, kun tal og hashes.

## 10. Kendte begrænsninger

- Børn med flere fødselsfamilier (adoption, to forældrepar) er ikke set i 2018-20. Reglen fejler lukket (betingelse 5).
- Tilfælde 6 kræver, at én påstand binder til to familier. Det udskydes, og påstanden står `unresolved`.
- De 4 forkerte henvisninger afvises. Om fejlen ligger i bogen eller OCR'en, er ikke tjekket i PDF'en (side 142, 97, 103 og 116). Det noteres i rapporten.
