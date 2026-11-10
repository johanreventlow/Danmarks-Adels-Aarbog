# Delspec 6d-3 — 1939's relationer (ægteskaber, forældre, børn) og oprydning efter legacy-importen

**Status:** udkast 2026-11-10, ikke godkendt. Projektejeren sprang brainstormens spørgsmål over (»spring
spørgsmålene over«); valgene nedenfor er *mit valg*, indtil projektejeren har svaret på §9.
**Overordnet spec:** `docs/superpowers/specs/2026-10-29-trin6-1939-gennem-kaeden-design.md` §3 (læseroplevelsen),
§5 (6d's rækkefølge, pkt. 3 relationer), §6 pkt. 8 (1939 hører hjemme på kilde 3-rækken; sammenhængen bæres af
afklaret `samme_som`; ingen nye familier eller familiemedlemmer), §8 (færdigbevis).
**Delspec 6d:** `2026-11-08-trin6d-placement-relationer-medlemskab-design.md` §3 (tabellen) og §7.
**Forudgående mekanisme:** 5b (`2026-10-06-trin5b-relationspersonas-design.md`, 2a, 2b-i, 2b-ii, 2b-iii) og 6c-3a
(genbrugt persona, `persona_family_context`).
**Arv:** decisions 2026-11-10 (6d-2b): 1791 skal ryddes, de 29 records uden narrativbinding vurderes, de skjulte
1135/940/933/935 registreres. Decisions 2026-11-08: I-11's nye ægteskab (2018-20) og værktøjsnoterne fra 6c-3's
kortrunde.
**Review-budget (B13):** 1 Codex-runde (`gpt-6.1-sol`) på spec+plan og 1 på diffen før prod; Opus afvejer hvert fund.

## 1. Roadmap-kobling

1. **Roadmapmål:** trin 6, »1939 gennem de samme operationer som 2018-20« (roadmap pkt. 6; trin 6-specen §5, 6d pkt. 3).
   Relationer står ikke i færdigbevis (a)'s opremsning, men i trin 6-specens læseroplevelse (§3: »ægteskaber og børn
   som strukturerede, klikbare oplysninger«) og i 6d's rækkefølge.
2. **Værdikædeled:** fortolkning (`relation.*`, `proposed` siden 6c-1) → relationspersona for ægtefælle/forælder/barn
   → identitet → afgørelse → strukturel binding til den eksisterende familie → læserens familiekilde.
3. **Leverancetype:** genbrug af 5b's RPC'er og writere; en lille 1939-profil (tekstform for udtrækket); én
   generalisering (writerens profilliste gøres til data i stedet for 2018-20-literaler); én lille læserrettelse
   (editionsneutral). Midlertidig legacy-afvikling for 1791.
4. **Værdi for læseren:** (a) et 1939-ægteskab viser »DAA 1939, s. N« som kilde ved siden af 2018-20's; (b) op til 43
   sammenfoldede personer holder op med at vise den samme ægtefælle to gange (§2.4); (c) Conrad Reventlows
   ægtefæller holder op med at have en ekstra ægtemand ved navn »fyenske Rytterreg.)« (§2.6).
5. **Færdigbevis:** §8.
6. **Erstatter:** 1939-legacy-loaderens ukildebundne `family_member`-rækker som eneste spor af 1939's ægteskaber;
   tekstlevnet 1791 som partner i to familier.

## 2. Målt udgangspunkt

Målt 2026-11-10 på stand-in `daa5ab_ddl_standin_20261110150105_6d2afb` (= prod efter 6d-2a). Stand-in'en er fra
før 6d-2b, men 6d-2b ændrede kun fire narrativers publiceringsstatus, ikke relationer, familier eller personer.
Genmåles i plan-Task 0. Kun antal og person-id'er for afdøde.

### 2.1 Forslagene

- **Kilde 3:** 271 `relation.marriage`, 6 `relation.parent`, 4 `relation.child`, alle `proposed`, ingen med parter
  (17 `mention.person` er uden for 6d-3). Til sammenligning har 2018-20 241 ægteskaber, 7 forældre og 11 børn bundet
  strukturelt (`interpretation_promotion` med `rule_mode='structural_family'`).
- **Input:** `private.relation_persona_input(3)` (`schema.sql:17501`) leverer alle 281. Alle har `principal_ok`
  (præcis én primary-mention med accepteret identitet på helposten), og hovedpersonen er en kilde 3-række i alle 281.
  Alle ægteskaber har et `marriage_ordinal`; 265 citerer én klausul, 6 citerer to.
- **Postformer:** forslagene ligger på 231 records: 113 ægteskaber på `person`-records, 64 på `marriage`, 65 på
  `relationship`, 29 på `fact`. Alle records har en persona.
- **Familieopslag:** hovedpersonens familier (`persona_family_context`, `schema.sql:18464`, eksakt person-id): 264 af
  271 ægteskaber har en familie med samme ordinal; 5 hovedpersoner har ingen familie; 2 har familier, men ingen med
  ordinalen.

### 2.2 5b's udtræk på 1939's tekst

`relation_persona_extract.py` (v1) kørt lokalt på inputtet (ingen skrivning): **88 elementer** (80 ægteskaber,
5 forældre, 3 børn); parkeret: 173 `ikke_ordret`, 14 `intet_navn`, 6 `flere_klausuler`. Af de 173 skyldes **160
alene linjeskift og orddelinger**: 1939's klausultekst er `raw` (bevarer `\n` og `-\n`), mens forslagets `raw` er
foldet. 13 har desuden sidemarkører (`### PAGE nnnn ###`) inde i spændet eller er afkortet. 2018-20's tekst er foldet,
derfor ramte v1 dér 242 af 248.

### 2.3 Familierne

333 familier har en 1939-person som partner (313 med to partnere, 20 med én). Ægtefællen er i alle 313 en person
uden kilde 3-identitet: en række, legacy-loaderen oprettede for 1939. Alle 356 børn i familierne er 1939-personer.

### 2.4 Sammenhængen med 2018-20 og den dobbelte ægtefælle

Klassifikation af de 333 via afklaret `samme_som` (`relation.rolle='samme_som'`, subjekt = alias, objekt = kanonisk;
`web/src/data/model.ts:145`):

| Hovedperson koblet | Ægtefælle koblet | Ægtefællen = partner i tvillingens familie | Familier |
|---|---|---|---|
| ja | ja | ja | 226 |
| ja | nej / ingen ægtefælle | — | 62 (heraf 16 uden ægtefælle) |
| ja | ja | nej | 2 |
| nej | ja | — | 9 |
| nej | nej | — | 34 |

**Retning:** 1939's ægtefællerække er alias i 237 af 237 koblinger, 1939-hovedpersonen i 290 af 292. Læseren viser
derfor 2018-20-rækkerne som kanoniske.

**Den dobbelte ægtefælle (kodelæsning, browsertjek i Task 0):** sammenfoldningen omskriver unionerne til kanoniske
id'er og deduplikerer kun på familie-id (`packages/core/src/collapseSameAs.ts:320-324`); `buildModel.addSpouse`
deduplikerer på (id, navn) (`packages/core/src/buildModel.ts:39-46`). Er hovedpersonen foldet, men 1939-ægtefællen
ikke koblet til tvillingens ægtefælle, får personen to ægtefæller: 2018-20's (»Joachim Diedrich von Dewitz«) og
1939's legacy-række (»Oberst Joachim Diedrich von Dewitz til Løitmark«). **44 familier hos 43 personer** er
kandidater (hovedperson koblet, ægtefælle ikke, tvillingen har mindst én ægtefælle). Tallet er en øvre grænse.
Navnene er stikprøvevis åbenlyst den samme person (titel og »til <gods>« i 1939-navnet), men nogle tvillinger har
flere ægtefæller, så kandidaten er ikke givet.

### 2.5 Læserens familiekilde

`public_family_sources` (`schema.sql:20712`) returnerer `counterpart_person_id` fra bindingens tilstand.
`DetailPanel` viser en ægteskabskilde kun, når modparten er *den viste ægtefælles id eller personens eget id*
(`web/src/components/DetailPanel.tsx:52-56`; forælderkilden tilsvarende `:59`). Uden kanonisk opslag vil en
1939-binding (modpart = 1939's ægtefællerække, som er alias) aldrig blive vist hos en sammenfoldet person, og det er
næsten alle. Mobilen viser ikke familiekilder.

### 2.6 1791, 1795 og de skjulte

- **1791** (»fyenske Rytterreg.)«, død 21 Juli 1708 = Conrad Reventlows (1198) dødsdag; fakta: `navn`, `død`) er
  partner i familie 742 (med 1823, ordinal 1, `vielse`) og 743 (med 1824, ordinal 2, `vielse`). Conrad har selv 540
  (med 1613, ordinal 1, 5 børn, `vielse`), 541 (med 1614, ordinal 2, 2 børn, `vielse`) og 726 (alene, ingen børn,
  ingen fakta). **1823 og 1613 er begge `samme_som` → 815** (Anna Margrethe Gabel), **1824 og 1614 → 816** (Sophie
  Amalie Hahn). 742/743 er altså dubletter af 540/541 med tekstlevnet i Conrads plads; 1823/1824 bærer datoer, som
  1613/1614 mangler. Læseren viser i dag Gabel og Hahn med to ægtemænd. Ingen persona-identitet peger på 1791.
- **1795** (22 tegn, intet navn): ét `navn`-faktum, ingen familier, ingen `samme_som`, ingen persona-identitet.
- **933, 935, 940, 1135:** ingen familier, ingen `samme_som`. De berører ikke relationerne; de står som registreret
  i decisions 2026-11-10 (skjulte, uden publicering).
- **De 29 records uden narrativbinding** (s. 498-539): **0 relationsforslag** ligger på dem. Relationerne kræver
  ikke personas for dem; de lukkes for 6d-3's vedkommende som kendt begrænsning (opret-benet/7b).

### 2.7 Kode, der er editionsbundet

- Writeren `red_apply_reimport_relation_persona` accepterer kun profilerne `relation-persona-2018-20-v1..v3`
  (`schema.sql:17589-17596`, `:17641`); udtrækkerne har dem som konstanter (`relation_persona_extract*.py`).
- Børneflok-reglen `relation_child_rule` (`schema.sql:18553`) læser `person_external_id.linje/nr/kuld/slaegtled`,
  for 1939 de syntetiske koordinater.
- **I-11 (2018-20):** kilde 1 har 4 `relation.marriage` `proposed` uden parter, heriblandt I-11's (decisions
  2026-11-08).

## 3. Opdeling (*mit valg*)

6d-3 går i prod som én DDL-blok + én dataceremoni (6d-1-formen), plus en web-deploy af læserrettelsen. Fire spor:

| Spor | Indhold |
|---|---|
| **R — relationer** | 5b-vejen på kilde 3 og I-11: relationspersonas → identitet → afgørelse → strukturel binding |
| **D — dobbelt ægtefælle** | `samme_som` mellem 1939's ægtefællerække og tvillingens ægtefælle, hvor kortet bekræfter det |
| **L — læseren** | familiekilden slår modparten op kanonisk |
| **O — oprydning** | 1791 (og 1795, hvis kortet afgør den som levn) |

## 4. Mål, ikke-mål og anti-mål

**Mål**

1. 1939's ægteskaber, forældre og børn går gennem de samme RPC'er og writere som 2018-20 (`red_relation_persona_*`,
   `red_apply_reimport_relation_persona`, identitetsvejen, `red_decide_relation_interpretations`,
   `red_promote_relation_interpretations_batch`).
2. Writerens profiler er data (en profiltabel eller `reimport_writer_profile.writer_config`), ikke literaler, og
   1939-profilen er én række: tekstform `raw` med foldning af linjeskift, orddelinger og sidemarkører ved
   sammenligningen, mens spændet gemmes i den originale tekst.
3. En 1939-ægtefælles persona får identitet til **1939's legacy-række** for ægtefællen (trin 6-specen §6 pkt. 8;
   `persona_family_context` arbejder på eksakt person-id), og ægteskabet bindes til hovedpersonens 1939-familie.
4. Læseren viser 1939's ægteskabs- og forælderkilde hos den sammenfoldede person.
5. Den dobbelte ægtefælle forsvinder, hvor projektejeren bekræfter, at de to rækker er samme person.
6. 1791 står ikke længere som ægtemand i læseren.

**Ikke-mål**

- Nye personer, familier eller familiemedlemmer (opret-benet, B4). Et ægteskab uden familie (5 hovedpersoner uden
  familie, 2 uden ordinal) får en synlig disposition, ikke en ny familie. 5b's `person_create`-gren bruges ikke på 1939.
- `relation-child-v2` på placementkoordinater. Med 4 børneforslag er en ny regel dyrere end kort (*mit valg*,
  ændrer 6d-spec §7; registreres i decisions ved godkendelse).
- `mention.person` (17), at gøre 1939 internt perfekt, og at rette 1939 efter 2018-20.
- 1939-koordinaterne i læseren og en udgavevælger for familier (6e).

**Anti-mål**

- En 1939-binding, læseren aldrig kan se (derfor spor L før eller samtidig med bindingen).
- At en børneregel afgør 1939-børn ud fra de syntetiske koordinater (v1 må ikke køre maskinelt på kilde 3).
- Et forudfyldt kort, der skjuler, at tvillingen har flere ægtefæller (memory: forudfyldt ark skjuler konflikt).
- Sletning uden måling vist i samme besked som forespørgslen.

## 5. Design

### 5.1 Spor R

1. **Profil.** Writerens tilladte profiler og deres regler (v1/v2/v3-grenene) læses fra profildata. 2018-20's tre
   profiler får samme navne og opførsel som i dag (regressionstest: 2018-20's kvitteringer verificerer uændret).
   1939 får `relation-persona-1939-v1` (navn kan vælges frit; det er data): v3's navneregel og titelliste, tekstform
   `raw`, foldning ved sammenligning. Udtrækkeren læser profilen fra en fil/CLI-argument i stedet for en konstant.
2. **Udtræk.** Målet er, at de 160 linjeskift-sager bliver elementer. De 13 med sidemarkør eller afkortning parkeres
   synligt, medmindre foldningen også dækker sidemarkøren (byggerens valg, men tallet rapporteres).
3. **Identitet.** Ægtefællens persona får kandidater blandt hovedpersonens 1939-familiers partnere. Entydig familie
   med ordinal + navnematch → maskinel accept (5b's kontrolmodel med blind stikprøve); resten på kort.
4. **Afgørelse og binding.** Som 2b-i: `red_decide_relation_interpretations` og
   `red_promote_relation_interpretations_batch` med `structural_family`. Forældre og børn (10) går på kort; ingen
   maskinel børneregel på kilde 3.
5. **I-11** og de øvrige 3 partsløse 2018-20-ægteskaber køres med 2018-20's v3-profil i samme ceremoni.

### 5.2 Spor D

For hver af de ≤44 kandidater viser kortet 1939-ægtefællen (navn, datoer, posttekst, side) mod *alle* tvillingens
ægtefæller. Projektejeren svarer: samme som ægtefælle *n* / ingen af dem. »Samme« skrives med den eksisterende
`red_samme_som(alias=1939-række, objekt=2018-20-række)` (`schema.sql:7650`), så retningen følger de 237
eksisterende. Ingen forudfyldning. Spor D kan køres før spor R, fordi identiteten i R peger på 1939-rækken
uafhængigt af `samme_som`.

### 5.3 Spor L

En editionsneutral rettelse i `packages/core` (`familieKilder`) og `DetailPanel`: modparten slås op gennem
`canonicalIdById` før sammenligningen med `spouseId`/`focusId`. Test: en sammenfoldet person med en binding på
alias-familien viser kilden; en kilde fra en anden families modpart vises ikke. Ingen DB-ændring.

### 5.4 Spor O (1791)

*Min anbefaling:* `red_samme_som(1791 → 1198)`. Begrundelse: 1791 er et stykke af Conrads post (narrativet 94 % i
1198's post; samme dødsdag); i læseren folder 742/743 sammen med 540/541, fordi ægtefællerne allerede kanoniserer til
815/816, så Gabel og Hahn får én ægtemand. Det er en eksisterende redaktørhandling, kan fortrydes og sletter
intet. Ulempe: »fyenske Rytterreg.)« bliver et alias-navn under Conrad, og 742/743 består som dubletfamilier.
*Alternativ:* slette 742, 743 og 1791 (måling og samtykke først; `red_slet_person_preview` viser blokeringer). Det
fjerner 1823/1824's eneste familier og deres datoer bliver familieløse. 1795 afgøres på kort: levn → samme behandling
mod den person, kortet peger på, eller stå.

## 6. Prod og fortrydelse

- **DDL-blok:** profildata + writerens opslag + evt. hjælpefunktioner; idempotent i `db-migrations.sql`,
  `schema.sql` opdateres, `db-verify.sql` asserter 2018-20-profilernes uændrede opførsel. `get_advisors` efter DDL.
- **Dataceremoni:** runner i `~/.private/5ab-overfoersel/` med `maal/apply/verify/fortryd --jeg-mener-det`, som
  6d-1/6d-2b. Persona-, mention- og batch-id'er er tilfældige pr. kørsel: pins og afstemning går på indhold
  (`interpretation_key`, `record_key`, `family_id`, person-id'er), aldrig på ceremoniens egne id'er.
- **Fortrydelse:** 5b's fortrydelse var *restore-only* (5b-spec §13; der findes ingen writer-reversal for
  relationspersonas, kun `red_reverse_reimport_publication`/`red_reverse_reimport_cases` for andre batchtyper).
  Restore i prod er ikke trofast (memory: anon-grants via default privileges, nye DDL-objekter består, bogmærker og
  tilmeldinger forsvinder lydløst). Planen skal derfor vælge: (a) restore med vindues-vagt pr. tabel og katalogdiff,
  som 6c-2, eller (b) en fortrydelse, der kun rører ceremoniens egne rækker (nøglet på indhold). *Min anbefaling:*
  (b) for spor D og O (`samme_som` fjernes med `red_fjern_samme_som`, `schema.sql:7695`) og for spor R 5b's egen
  regel: rettelse fremad gennem kernens menneskelige oprindelse (`red_afgoer_source_persona`, afløste parter), restore
  kun som nødbremse med skrivepause fra backup til `VERIFY_OK`. Planen beviser fortrydelsen på stand-in før prod.
- **Web:** spor L deployes med Vercel efter DB-ceremonien (læserrettelsen er harmløs uden 1939-bindinger).
- Stand-in: en frisk restore af prod efter 6d-2b (ICU, `statement_timeout` 2 min som prod).

## 7. Kort

Én kortrunde, lokal HTML med posttekst, side, forældre og familiens øvrige medlemmer (memory: kort kræver kontekst;
værktøjsnoten fra 6c-3 om forælderarket bygges som repo-værktøj her). Før kortene: tab vist i tal og ét samlet valg
(memory: vis tab før kortrunde). Forventet omfang: ≤44 D-kort, ægteskaber uden entydig familie/navn (≥7 + parkerede
efter foldning), 10 forældre/børn, 1795. Model mod PDF-siden må forbehandle (6d-1's form), projektejeren ser
undtagelser og en stikprøve.

## 8. Færdigbevis

1. Tal i prod: elementer, parkerede pr. årsag, identiteter (maskine/kort), afgørelser, strukturelle bindinger for
   kilde 3; nye `samme_som`; 1791's tilstand.
2. Hver binding før ceremonien er gældende efter (2018-20 uændret; nøglet afstemning, ikke kun antal).
3. Læseren som `anon` mod prod: en sammenfoldet person viser »DAA 1939« som kilde på et ægteskab; en person fra spor D
   viser én ægtefælle; Conrads ægtefæller viser én ægtemand.
4. `status.md`'s relationsrække for 1939 hæves til `produktionsverificeret`.

## 9. Projektejerens valg (åbne)

1. Spor D med i 6d-3 (≤44 kort), eller backlog?
2. 1791: `samme_som` → Conrad (anbefalet) eller sletning af 742/743/1791?
3. Spor L i 6d-3 (anbefalet) eller i 6e?

## 10. Reviewlog

(tom)
