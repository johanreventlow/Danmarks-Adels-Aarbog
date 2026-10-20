# Trin 5b del 2b-iii — børnehenvisningerne binder til familien (#151)

## Status

Designet blev godkendt i brainstormen 2026-10-20 i tre dele. Projektejeren valgte:
- **Mål:** kildehenvisning på børnene, ikke kun oprydning.
- **Tilgang A:** flokken binder til forælderens familie. Alternativerne var ét barn pr. påstand (B) og en ny påstandstype (C).
- **Køn:** blokerende krav.
- **Webvisning:** med i skiven.

Spec'en er revideret samme dag efter et uafhængigt review (Opus, »GO med rettelser«) og en efterfølgende måling. Målingen viste, at romertallet i henvisningen ikke er linje-præfikset (§2). Projektejeren valgte derefter **ét menneskeligt ark for alle 13** i stedet for en maskinel vej plus stikprøve.

**GODKENDT af projektejeren 2026-10-20** (»ja, skriv planen«), inkl. revisionen af drift-reglen i §7.

**Roadmap:** trin 5, delspec 5b, del 2, skive b-iii.

Dokumenterne kaldes herefter:
- »hovedspecen«: `docs/superpowers/specs/2026-10-06-trin5b-relationspersonas-design.md`;
- »2a-specen«: `docs/superpowers/specs/2026-10-11-trin5b-2a-binding-design.md`;
- »2b-ii-specen«: `docs/superpowers/specs/2026-10-17-trin5b-2b-ii-nye-personer-og-disposition-design.md`.

Beslutninger: `docs/decisions.md` 2026-10-10 (børn taget ud af del 1) og 2026-10-17 (børn til 2b-iii).

## 1. Adgangskrav (roadmap)

| Krav | Svar |
| --- | --- |
| Roadmapmål | Trin 5 (#151), 5b »personas for ægtefæller og børn« |
| Værdikædeled | Fortolkning → menneskelig relationsafgørelse (hash-bundet ark, serveren håndhæver reglen) → binding → offentlig læseprojektion med kildehenvisning |
| Leverancetype | Generel regel `relation-child-v1` (`structural_family`) og en henvisningsparser for 2018-20's form. Ingen nye tabeller. |
| Redaktionel/læserrettet værdi | Op til 12 familier får en kilderække for deres børneflok. Læseren kan se, hvor i DAA 2018-20 forælder→barn-forbindelsen står. |
| Færdigbevis | §9 |
| Erstatter | `RELATION_CHILD_DEFERRED`: de 14 `relation.child` står i dag `proposed` uden vej videre |

## 2. Erratum til hovedspecen §22.9

§22.9 antog, at en børnepåstand nævner ét barn, så valget stod mellem flere børn. Det er forkert. Målt i bevisbasen `daa5b_navnv3_bevis_20261019200958` den 2026-10-20 er påstandene **krydshenvisninger til en hel børneflok**. Formen er »N børn: <ordenstal> [(<ordenstal>)] slægtled, <romertal>, nr. a[–b]«, eventuelt »Datter:« eller »Søn:« for ét barn. Henvisningen står sidst i forælderens post, og børnene står i deres egne poster.

**Felterne i `public.person_external_id`** (schema.sql:141-150):
- `linje` (I–V, postnøglens præfiks);
- `nr`;
- `kuld` (børnegruppe-markør, romertal);
- `slaegtled_lokal`;
- `slaegtled_gennem`.

**Henvisningens dele passer med børnenes felter i alle 10 tilfælde, der har et interval:**
- ordenstallet = børnenes `slaegtled_lokal`;
- ordenstallet i parentes = `slaegtled_gennem`, hvor det står;
- romertallet = børnenes `linje` eller `kuld`;
- intervallet = børnenes `nr` i forælderens `linje`.

Under brainstormen blev romertallet fejlagtigt slået op som linje-præfiks. Det fik 4 henvisninger til at ligne fejl. Det er de ikke: bogen og databasen er enige.

Tilfældene er nummereret 1–14 i påstandenes nøgleorden:

| Tilfælde | Antal | Hvad der passer |
| --- | --- | --- |
| 1-4, 7-12 | 10 | Det hele: antal, interval, familiens barnerækker, børn med egen post, slægtled og romertal (linje eller kuld) |
| 5 | 1 | »9 børn«; intervallet og familien har 8. Alt andet passer. |
| 6 | 1 | »17 børn« uden henvisning. 16 børn med egen post i 2 ægteskaber (6 + 10). |
| 13 | 1 | »3 sønner (?)« uden henvisning. 3 sønner i én familie. |
| 14 | 1 | Ingen entydig hovedperson |

**Øvrige målinger:**
- Alle ca. 77 børn sidder allerede som `barn` i forælderens familie. 2b-iii skaber derfor **ingen nye slægtskaber**. Den giver kildehenvisning på forbindelser, der findes i forvejen.
- Køn: hvor teksten siger »døtre« eller »sønner«, har alle børn det rigtige køn (2/2, 4/4 og 3/3).
- Ingen barnerække i de berørte familier er `omstridt`.

## 3. Afgrænsning

**Med:**
- de 14 `relation.child` i kilde 1;
- SQL-parseren;
- reglen `relation-child-v1`;
- writer-grenen for `relation.child`;
- `relation_binding_state` for `relation.child`;
- `public_family_sources` med slags `boern`;
- web-visning;
- arket.

**Udenfor:**
- prod-overførsel;
- mobil-appen (kun til udvikling);
- #244 (ægteskabsnumre) og #240 (dobbelte familier);
- én påstand bundet til flere familier (tilfælde 6);
- adopterede, pleje- og stedbørn;
- 1939 (trin 6).

## 4. Henvisningsparseren (SQL, én implementering)

`private.relation_child_ref(p_raw text) RETURNS jsonb` er IMMUTABLE og deterministisk. Ingen model læser teksten. Grammatikken:

```
henvisning := antal [ " (?)" ] [ ":" sted ]
antal      := TAL (" børn" | " døtre" | " sønner") | "Datter" | "Søn"        (Datter/Søn ⇒ antal 1)
sted       := ordenstal [ " (" ordenstal ")" ] " slægtled," [ " " ROMERTAL "," ] " nr. " TAL [ BINDESTREG TAL ] [ "." ]
```

**Grammatikkens detaljer:**
- `BINDESTREG` er `-`, `‑` (U+2011) eller `–`.
- Ordenstal er de danske ordenstalsord fra »første« til »tyvende«, uden hensyn til store og små bogstaver.

**Resultatet:**
- `count`;
- `sex`: `kvinde` ved døtre/Datter, `mand` ved sønner/Søn, ellers NULL;
- `uncertain`: sand ved »(?)«;
- `gen_local` og `gen_through`: heltal eller NULL;
- `section`: romertallet eller NULL;
- `nr_from`;
- `nr_to`, som sættes til `nr_from`, når bindestregen mangler.

Tekst, der ikke følger grammatikken, giver NULL.

Der er ingen Python-tvilling. Arket renderes fra en privat SQL-projektion (§6), så der kun findes én parser.

## 5. Matchreglen `relation-child-v1`

Barnerækker er `family_member` med `rolle='barn'`. Postnøglen er `public.person_external_id`, med `source_id = 1` og felterne `linje`, `nr`, `kuld`, `slaegtled_lokal` og `slaegtled_gennem`. Alle sammenligninger evalueres som `IS [NOT] DISTINCT FROM` eller `coalesce(…, false)`, så en NULL aldrig lader en betingelse passere.

**Krævet altid (H, kan ikke tilsidesættes):**

- **H1:** Påstanden er `proposed` og citerer præcis én klausul. Hovedpersonen har en accepteret identitet og præcis én `person_external_id` i kilde 1 med `linje` = `L`.
- **H2:** `relation_child_ref(raw)` er ikke NULL.
- **H3:** Hovedpersonen er `partner` i præcis én familie `F` med mindst én barnerække. `F` har ingen `omstridt`-række og ingen række med `rolle` i (`adopteret_barn`, `plejebarn`, `stedbarn`).
- **H4:** Er `sex` sat, har alle barnerækker i `F` det køn.
- **H5:** Er `nr_from` sat, gælder alt følgende:
  - mængden af `nr` for `F`'s børn med `person_external_id` i kilde 1 og `linje = L` er netop `{nr_from … nr_to}`;
  - ingen af `F`'s børn har en `person_external_id` i kilde 1 med en anden `linje`;
  - `section`, når det er sat, er lig hvert barns `linje` eller `kuld`;
  - `gen_local`, når det er sat, er lig hvert barns `slaegtled_lokal`, og tilsvarende for `gen_through`.
- **H6:** Er `nr_from` ikke sat, har mindst ét barn i `F` en `person_external_id` i kilde 1.

**Afvigelser (A, mennesket kan tilsidesætte, og afvigelsen vises på kortet):**
- **A1:** `count` er forskellig fra antallet af barnerækker i `F`.
- **A2:** `nr_from` er sat, og `count` er forskellig fra `nr_to − nr_from + 1`.
- **A3:** `uncertain`.
- **A4:** `nr_from` er ikke sat (ingen henvisning).

**Udfald på de 14 tilfælde:**

| Tilfælde | Udfald |
| --- | --- |
| 1-4, 7-12 | H opfyldt og ingen A, altså »passer helt« |
| 5 | H opfyldt, A1 og A2 |
| 13 | H opfyldt, A3 og A4 |
| 6 | H3 brudt (2 familier) |
| 14 | H1 brudt |

## 6. Afgørelsesvejen: ét hash-bundet ark

**Projektionen.** `private.relation_child_sheet_input(p_source_id)` (REVOKE fra alle API-roller; mønster: `spouse_exception_projection`) returnerer pr. påstand:
- nøgle og version;
- `raw` og det parsede resultat;
- H-udfaldet og A-listen;
- `F` og børnene: navn, fødselsår, postnøgle, linje, kuld og slægtled.

Den kaldes kun af ejeren lokalt mod restore-kopien. Inputtet låses som i 2b-ii (rækkefil-hash).

**Arket** (`relation_child_sheet.py`, mønster: `relation_marriage_sheet_v3.py`) har tre dele:
- **Første blok:** én kort linje pr. påstand, der »passer helt«, forudfyldt `B`.
- **Anden blok:** kort for påstande med A-afvigelser, med bogens tekst, de parsede felter og børnene. Forudfyldt `B` for 5 og 13.
- **Påstande, der bryder H:** står kun som optælling, uden linje. Tilfælde 6 og 14 forbliver `proposed`.

Tokens: `B` (bind), `R` (afvis) og `U` (lad stå `proposed`; intet skrives). Arket er privat (`~/.private/5b-2b-iii/`, 0600) og kommer aldrig i repo eller chat. Projektejeren gennemgår det med `open -e` og giver hashen i chat. `sql` danner derefter afgørelsesscriptet og manifestet. Python-scriptet afviser tokens uden for `B`/`R`/`U` (`SHEET_TOKEN_NOT_ALLOWED`). Serveren **registrerer** arkets hash, rækkefilens hash og linjen i evidensen, men verificerer ikke arket selv. Bindingen til det godkendte ark beror på scriptets kontrol, som i 2b-ii.

**Writeren.** `red_afgoer_relation_interpretation` får en selvstændig gren for `relation.child`. Grenen erstatter `RELATION_CHILD_DEFERRED` (schema.sql:15368) og genbruger ikke forældregrenens kandidatlogik (`v_n<>1`, `child`-part):

- **Basis:** `same` og `rejected` kræver `human_sheet` med hash og linje (uændret validering, schema.sql:15355-15358). `unresolved` afvises for `relation.child` (`RELATION_DECISION_INVALID`), fordi en afgjort fortolkning ikke kan genåbnes (`red_decide_interpretation` kræver `proposed`, schema.sql:8239). »Ikke nu« er derfor arkets `U`, som ikke skriver noget.
- **`p_family_id` skal være NULL** for `relation.child`, også ved `same`. Det er en undtagelse fra schema.sql:15387. Serveren udleder `F` efter H3.
- **`same`:** under `lock_family_rows` over hovedpersonen og `F`'s medlemmer genberegner serveren H1-H6. Ved brud kastes `RELATION_CHILD_RULE_NOT_MET`. A-afvigelser er tilladt. Evidensen bærer:
  - `family_id`;
  - `flock_digest`: SHA-256 over den kanoniske JSON af `F`'s barnerækker (`person_id`, `rolle`, `konfidens`), sorteret efter `person_id`. Det er kun et revisionsspor og bruges ikke som drift-vagt (§7);
  - det parsede resultat;
  - `afvigelser` (A-koderne).

  Der indsættes **ingen** `child`-part. Klassifikationstabellen bruges ikke, fordi dens CHECK kun omfatter ordinal-klassifikationerne (schema.sql:16084).
- **`rejected`:** kræver kun H1's første del.

## 7. Bindingen

`private.relation_binding_state` får en gren for `relation.child` (i dag returnerer den NULL, schema.sql:16026). Grenen kræver en accepteret påstand, hvis evidens har `family_id`, og at hovedpersonen stadig er `partner` i `F`.

**Grenen tjekker reglen, ikke et øjebliksbillede** (projektejerens valg 2026-10-20). Den genberegner H1's identitetsdel og H3-H6 mod `F`, **som familien ser ud nu**, med det parsede resultat fra påstanden. Er en H-betingelse brudt, returnerer den **NULL**. Afgørelsens `flock_digest` sammenlignes ikke.

| Ændring | Virkning |
| --- | --- |
| Mellem afgørelse og binding | Preview og batch genberegner tilstanden. Et H-brud ⇒ NULL ⇒ bindingen afvises. Passer familien stadig med bogen (fx et 9. barn uden egen post tilføjet), bindes den aktuelle flok. |
| Efter bindingen | Tilstanden indeholder familiens rækker, så enhver ændring giver en ny tilstands-hash. Den eksisterende kontrol i `public_family_sources` (`reimport_canonical_json_sha256(st) = bound_sha`) skjuler så kilden. |
| Genopretning | Den eksisterende genbinding fra 2b-i: en ny binding ved siden af den gamle, append-only. Den kræver kun, at reglen stadig holder, ikke en ny afgørelse eller en ny påstand. Ingen genbinding, hvis H er brudt. |

**Konsekvens:** en binding efter en ændring, der stadig passer med bogen, dækker den aktuelle flok, ikke nødvendigvis præcis den, projektejeren så på kortet. Det accepteres, fordi bogens numre, slægtled og køn stadig skal passe.

Ellers returneres:

```
{contract:'relation-binding-state-v1', interpretation:{…}, parties:[principal],
 family:{family_id, rows:[principal-partnerrækken + alle barnerækker (person_id, rolle, ordinal, konfidens)]},
 counterpart_person_id: <hovedpersonens person_id>, flock_digest, children:{count, section, nr_from, nr_to, sex}}
```

Hovedpersonen står som `counterpart_person_id`, så `public_family_sources` (schema.sql:16994) og `mapFamilieKilder` virker uændret. Feltet betyder her »forælderen, kilden vises ved«.

**Reglen og bindingsvejen:**
- Regelregistret får `('relation-child-v1','relation.child')` og reglen `('relation-child-v1',1,'relation.child','relation','family',NULL,'relation',false,false,true,'active','structural_family')`. Den består `interpretation_promotion_rule_mode_check` og prædikat-triggeren (verificeret i reviewet).
- Bindingen kører gennem `decide.sql`, bind-preview og `red_promote_relation_interpretations_batch`, som i 2a.
- Ordinal-klassifikationerne gælder kun ægteskaber.

Både `schema.sql` og `db-migrations.sql` (idempotent) får alle ændringer. `tests/sql/test-relation-decision.sql`, som i dag tester `RELATION_CHILD_DEFERRED`, skrives om.

## 8. Læseren

**`public_family_sources`:**
- `slags = CASE predicate WHEN 'relation.marriage' THEN 'aegteskab' WHEN 'relation.parent' THEN 'foraelder' ELSE 'boern' END`;
- `counterpart_person_id` kommer fra tilstanden, altså forælderen ved `boern`;
- publicerings- og familiegaten (`family_offentlig`, `db-rls.sql:119`) er uændret. Den afviser hele familien, hvis ét medlem ikke er offentligt, så en børnekilde kan ikke afsløre en levende eller skjult person (verificeret i reviewet).

**`packages/core/familieKilder.ts`:**
- `FamilieKilde.slags` udvides med `'boern'`;
- `mapFamilieKilder` godtager `'boern'`;
- `familieIderForPerson` returnerer desuden `boerneFamilier`, dvs. familier, hvor fokuspersonen er partner og har børn.

**`DetailPanel` (web):** børnene vises i dag som én flad liste.
- **Hos forælderen:** kildelinjen vises én gang under børnelisten pr. bundet familie, fx »Børn: Kilde: DAA 2018-20 · Post …«.
- **Hos et barn:** kildelinjen vises ved forælderen i forældresektionen, når barnet er `barn` i familien, og forælderen er `counterpart`.
- **Den anden forælder** i familien får ikke linjen, fordi henvisningen står i hovedpersonens post.

En ældre klient springer `boern` over.

## 9. Færdigbevis

**CI** (syntetiske personer):
- **Parseren:**
  - alle former i §4: `Datter:`, `Søn:`, `(?)`, U+2011, enkelt nummer (`nr_to = nr_from`), med og uden parentes-slægtled, uden romertal;
  - tekst uden for grammatikken giver NULL.
- **Writeren:**
  - hvert H-brud giver `RELATION_CHILD_RULE_NOT_MET`, inkl. NULL-felter, der ikke må slippe igennem;
  - A-afvigelser tilladt;
  - `p_family_id` sat ⇒ afvist;
  - `unresolved` ⇒ afvist;
  - `rejected` virker;
  - ingen `child`-part.
- **Bindingen:**
  - et barn med egen post uden for intervallet tilføjet mellem afgørelse og binding ⇒ tilstanden er NULL, og preview afviser;
  - et barn uden egen post tilføjet mellem afgørelse og binding ⇒ H holder, og den aktuelle flok bindes;
  - et barn tilføjet efter binding ⇒ kilden er usynlig, og en genbinding bringer den tilbage, når H holder;
  - et barn flyttet ud efter binding (H5 brudt) ⇒ usynlig, og genbinding afvist;
  - `omstridt` ⇒ NULL.
- **Core og web:**
  - `boern` vises ved forælderen og ved barnet hos den rigtige forælder;
  - ikke hos den anden forælder;
  - en ukendt slags springes over.
- **Arket** (e2e): render, hash, `sql`, `SHEET_TOKEN_NOT_ALLOWED`. Testen skal i `.github/workflows/ci.yml`.

**Restore** (kopi af `daa5b_navnv3_bevis_20261019200958`, aldrig prod):
- **Forløbet:** rækkefil → ark → projektejerens gennemgang og hash → afgørelser → decide → bind-preview → binding → genkørsel giver 0.
- **Forventet med de forudfyldte svar:** 12 bindinger (de 10, der passer helt, samt 5 og 13); 0 `rejected`; 2 `proposed` (6 og 14).
- **Læsningen** målt med `read.sql` som i 2a-2b-ii. Kilderækker af typen `boern` stiger med højst 12. Familier med en ikke-offentlig person falder fra (`family_offentlig`), og antallet rapporteres.
- **Universet**, målt med det private `univers.sql`: spanden for børnepåstande falder fra 14 til 2, og fordelingen rapporteres.
- **Kanonisk delta 0:** aggregat-hashes ens, 2a's tupel-digest uændret.
- **Negativtests:**
  - et barn med egen post flyttet ud af familien mellem afgørelse og binding ⇒ binding afvist;
  - forkert arkhash;
  - et `U` hævet til `B` på et H-brud ⇒ `RELATION_CHILD_RULE_NOT_MET`;
  - ukendt token ⇒ `SHEET_TOKEN_NOT_ALLOWED`.

**Rapport:** `docs/evidensbaseret-genimport/relationspersonas-5b-2b-iii-bevis.md`, kun tal og hashes.

## 10. Kendte begrænsninger

- **Tilfælde 6:** én påstand dækker børn i to ægteskaber. Det kræver binding til flere familier og udskydes. Påstanden står `proposed`.
- **Adopterede, pleje- og stedbørn** blokerer (H3). De er ikke set i de berørte familier.
- **Serveren verificerer ikke arkets indhold, kun de registrerede hashes,** som i 2b-ii.
- **Et ændret barnesæt** skjuler kilden, indtil den genbindes (§7). Genbindingen kræver en kørsel af 2b-i's genbindingsvej, ikke en ny afgørelse. Bryder ændringen reglen, kan kilden ikke komme tilbage uden en ny fortolkningsversion via trin 4-kæden. Det er tilsigtet: så passer bogen ikke længere med familien.
