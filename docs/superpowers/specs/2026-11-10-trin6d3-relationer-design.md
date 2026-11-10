# Delspec 6d-3 — 1939's relationer (ægteskaber, forældre, børn) og oprydning efter legacy-importen

**Status:** udkast 2026-11-10, afventer projektejerens godkendelse af dokumentet. Projektejeren sprang
brainstormens spørgsmål over og har besvaret §9's tre valg (alle som anbefalet). Øvrige valg er markeret *mit valg*.
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
  271 ægteskaber har præcis én familie med samme ordinal, og den har en ægtefælle; 5 hovedpersoner har ingen familie;
  2 har familier, men ingen med ordinalen. Intet ægteskab lander i en familie uden ægtefælle.
- **Overslag over den maskinelle population** (eligibility-kontraktens tællebetingelser tilnærmet pr. hovedperson):
  **≈220** kandidater til maskinel accept, **38** hvor hovedpersonens antal ægteskabsforslag ≠ antal familier (kort),
  **13** der ikke kan bindes (6 med to klausuler, 5 uden familie, 2 uden ordinal). Navnetjek og foldning (§2.2)
  trækker yderligere fra; realistisk antal bundne ægteskaber er ca. 200-250. Task 0 måler det præcist med den rigtige
  kontrakt.

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

**Empirisk prøve** (core's `collapseSameAs` + `buildModel` på stand-in'ens personer, familier og 719 `samme_som`,
scratchpad-script): i dag har 1065's komponent (kanonisk 18) to ægtefæller, 598 »Joachim Diedrich von Dewitz« og 1537
»Oberst … til Løitmark«; Gabel (815) og Hahn (816) har hver to ægtemænd, Conrad (392) og 1791. Med de hypotetiske
kanter `1537 → 598` og `1791 → 392`: 18 har én ægtefælle, 815 og 816 hver én ægtemand, 0 nye karantæner.
Panelet viser ægtefæller fra `spousesBy` (`DetailPanel.tsx:67`), der deduplikerer på (id, navn); `p2_name` er altid
`null` (`web/src/data/model.ts:127`), så navnet er den kanoniske persons.

### 2.5 Læserens familiekilde

`public_family_sources` (`schema.sql:20712`) returnerer `counterpart_person_id` fra bindingens tilstand.
`DetailPanel` viser en ægteskabskilde kun, når modparten er *den viste ægtefælles id eller personens eget id*
(`web/src/components/DetailPanel.tsx:52-56`; forælderkilden tilsvarende `:59`). Uden kanonisk opslag vil en
1939-binding (modpart = 1939's ægtefællerække, som er alias) aldrig blive vist hos en sammenfoldet person, og det er
næsten alle. Mobilen viser ikke familiekilder.

Resten af offentlighedsgaten (præcis én supporting-observation, præcis én published binding på recorden, narrativets
subjekt blandt parterne, `person_daa_narrative_publication_allowed`): alle 281 forslags records har præcis én
published binding med hovedpersonen som subjekt og tilladt narrativ. **De 6 ægteskaber med to klausuler fejler
`n_support=1`** og vil være usynlige selv med en binding (v1-udtrækket parkerer dem også).

### 2.6 1791, 1795 og de skjulte

- **1791** (»fyenske Rytterreg.)«, død 21 Juli 1708 = Conrad Reventlows (1198) dødsdag; fakta: `navn`, `død`) er
  partner i familie 742 (med 1823, ordinal 1, `vielse`) og 743 (med 1824, ordinal 2, `vielse`). Conrad har selv 540
  (med 1613, ordinal 1, 5 børn, `vielse`), 541 (med 1614, ordinal 2, 2 børn, `vielse`) og 726 (alene, ingen børn,
  ingen fakta). **1823 og 1613 er begge `samme_som` → 815** (Anna Margrethe Gabel), **1824 og 1614 → 816** (Sophie
  Amalie Hahn). 742/743 er altså dubletter af 540/541 med tekstlevnet i Conrads plads; 1823/1824 bærer datoer, som
  1613/1614 mangler. Læseren viser i dag Gabel og Hahn med to ægtemænd. Ingen persona-identitet peger på 1791.
  Topologi: Conrads komponent har sink **392** (`255 → 392`, `1198 → 392`); 1791 har ingen `samme_som`. Unionsguarden
  i `samme_som`-triggeren (`schema.sql:7577-7590`) rammer ikke: ingen union har en part i 1791's og en i 392's
  komponent.
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
- **Børnebindingen:** `relation_binding_state` (`schema.sql:19599-19604`) giver kun en binding for
  `relation.child`, når afgørelsens `method` er `relation-child-v1`, og reglen består ved læsning. En kortafgørelse
  alene giver derfor ingen binding og ingen synlig kilde for de 4 børneforslag.
- **I-11 (2018-20):** kilde 1 har 4 `relation.marriage` `proposed` uden parter (decisions 2026-11-08): I-103 og V-159
  har én familie med ordinalen og en ægtefælle; I-11's familie med ordinalen har ingen ægtefælle; II-35 har ingen
  familie.

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
  familie, 2 uden ordinal) får ikke en ny familie. 5b's `person_create`-gren bruges ikke på 1939.
- **»Synlig disposition« er ikke en ny skrivning.** Der findes ingen writer for et partsløst relationsforslag:
  `relation_disposition_state` (`schema.sql:20454`) gælder kun klausuldispositioner `afventer_identitet`, hvis
  relationsforslag allerede har parter med identitet. Forslag, 6d-3 ikke binder, står `proposed`; runnerens
  `maal`/`verify` tæller dem pr. årsag med nøgle (`interpretation_key`), og `status.md` registrerer dem som kendt
  begrænsning. Ingen editionsnavngiven årsagskode gemmes i basen (*mit valg*).
- `relation-child-v2` på placementkoordinater og en menneskelig gren i børnebindingen. De 4 børneforslag står
  `proposed` og tælles i færdigbeviset med årsagen »børnereglen læser 1939's syntetiske koordinater« (*mit valg*,
  ændrer 6d-spec §7; registreres i decisions ved godkendelse). Anti-målet nedenfor gælder dermed ikke for dem: de
  bliver ikke accepteret uden binding.
- 5b's `person_create`-gren, også for 2018-20: I-11 (familie uden ægtefælle) og II-35 (ingen familie) står `proposed`
  og tælles som 1939's 7 (*mit valg*).
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
   Profilen adskiller **navneregel** og **tilladte prædikater med payloadform**: v3-grenen afviser i dag andet end
   ægteskaber (`schema.sql:17595`), så 1939-profilen skal eksplicit tillade `relation.parent` med v1's payloadform
   (Codex fund 9).
   **Foldningen gælder også ægteskabsnummeret (Codex runde 2, fund 1).** `relation_marriage_ordinals` (`:17472`)
   nummererer postens ægteskaber efter positionen af det eneste ordnede ordvindue (`relation_ordered_windows`) i den
   ufoldede tekst; uden vindue bliver positionen NULL og sorteres sidst, og writeren genbruger og kontrollerer
   nummeret (`:17674`, `:17681`). Målt: **59 af 1939's 271 ægteskaber har ingen position** (57 forekomster), og i
   **11 poster med flere ægteskaber** kan nummereringen derfor være forkert, så kandidatfamilien bliver forkert. Profilens
   foldning skal bruges i positions- og nummerberegningen med tilbageføring til originalens positioner, og 2018-20's
   numre skal være uændrede (regression). Bevis: poster med flere ægteskaber og blandet orddeling. §2.1's 264
   ordinaltræf er målt med de nuværende, muligvis forkerte numre.
2. **Udtræk.** Målet er, at de 160 linjeskift-sager bliver elementer. De 13 med sidemarkør eller afkortning parkeres
   synligt, medmindre foldningen også dækker sidemarkøren (byggerens valg, men tallet rapporteres).
3. **Identitet.** Ægtefællens persona får kandidater blandt hovedpersonens 1939-familiers partnere. Maskinel accept
   følger **hele** 5b's eksisterende eligibility-kontrakt (`red_corroborate_family_identities` →
   `decide_source_persona_identity` → `private.check_family_corroboration`, `schema.sql:19576`, `:10319`, `:19435`:
   postens ægteskabsantal = personens familieantal, ordinalvalg ved flere familier (ved én familie kræves intet
   ordinalmatch, `:19490`), ingen `omstridt`/`formodet` konfidens, intet dobbeltmål, kandidatmålet = familiens eksakte
   legacy-partner, navnetærskel, stikprøve og eksklusioner) med blind stikprøve, ikke kun »ordinal + navn« (Codex
   fund 7, runde 1+2). Task 0 måler
   populationen og afvisningsårsagerne før kortrunden; resten på kort.
4. **Afgørelse og binding.** Ægteskaber som 2b-i: `red_decide_relation_interpretations` (kun `relation.marriage`,
   `schema.sql:19785`) og `red_promote_relation_interpretations_batch` med `structural_family`. **Forældre** går
   ad 2a's vej: `red_afgoer_relation_interpretation` (`schema.sql:18864`) med kandidat fra
   `relation_structural_candidates` (`:18838`), som kræver en accepteret primary-persona fra samme kilde på
   modpartens eksakte medlemsrække og præcis én kandidat; Task 0 måler kandidatdækningen for de 6, og manglende eller
   flertydige kandidater står `proposed` (Codex fund 1). De 4 børn står `proposed` (§4); ingen maskinel børneregel
   på kilde 3. De 6 ægteskaber med to klausuler står `proposed` (usynlige i læseren selv med binding, §2.5).
5. **Afstemning gennem læsergaten:** hver planlagt binding afstemmes nøglet gennem hele `public_family_sources`'
   gate efter ceremonien (som anon); en binding, der er gyldig, men usynlig, er et fund, ikke et færdigbevis
   (Codex fund 2).
6. **2018-20's partsløse ægteskaber:** I-103 og V-159 køres med 2018-20's v3-profil i samme ceremoni; I-11 og II-35
   står `proposed` (§4).

### 5.2 Spor D

For hver af de ≤44 kandidater viser kortet 1939-ægtefællen (navn, datoer, posttekst, side) mod *alle* tvillingens
ægtefæller. Projektejeren svarer: samme som ægtefælle *n* / ingen af dem. »Ingen af dem« skrives ikke i basen
(ingen `red_ikke_samme_som`); svaret står i kortarket og ceremoniens manifest (*mit valg*: én skrivetype færre at
fortryde). »Samme« skrives med den eksisterende
`red_samme_som(alias=1939-række, objekt=2018-20-rækkens sink)` (`schema.sql:7650`), så retningen følger de 237
eksisterende. Ingen forudfyldning.

**Forudsætninger (Codex fund 3):** RPC'en kan vende retningen efter data (`samme_som_data_direction`, `:7670`) og
afviser ved eksisterende aliasmål (G3), indgående links (G4), afviste komponenter og fælles partnerunion
(`:7563-7590`); collapse karantænerer ved konkurrerende forældre, selv-ægteskab og cyklus
(`collapseSameAs.ts:169`, `:195-234`). Planen kræver derfor pr. kandidat: topologiopslag før kortet (ingen af de 44
1939-ægtefæller har `samme_som` i dag, §2.4), kontrol af den faktisk skrevne retning, og en samlet collapse-prøve
(core's `collapseSameAs` på stand-in-data efter skrivningen) med 0 nye karantæner.

**Rækkefølge (Codex fund 4):** identitetskandidaternes input indeholder hele `same_as`-mængden (`schema.sql:11253`),
og kontrolstatus genberegner inputhashen (`:19083`, `:19185`). Spor D og O skrives derfor **før** spor R's
kandidatkørsel; ændres `samme_som` efter, genberegnes kandidater og kontrol.

### 5.3 Spor L

En editionsneutral rettelse i `packages/core` (`familieKilder`) og `DetailPanel`: modparten slås op gennem
`canonicalIdById` før sammenligningen, for **alle tre kildearter** (Codex fund 8): ægteskab (mod `spouseId`/`focusId`,
`DetailPanel.tsx:52-56`), forælder (mod `parentId`, `:59`) og børn (mod forælderen og `focusId`, `:59-62`). Id'er
normaliseres som decimalstrenge begge steder. Tests pr. kildeart: alias-modpart vises; en kilde fra en anden families
modpart vises ikke; en ukendt modpart (ikke i aliaskortet) sammenlignes uændret. Ingen DB-ændring.

### 5.4 Spor O (1791)

1791 er et stykke af Conrads post (narrativet 94 % i 1198's post; samme dødsdag). To veje, begge eksisterende
redaktørhandlinger, der kan fortrydes og ikke sletter noget:

- **(a) `red_samme_som(1791 → 392)`** (projektejerens første valg, §9). Komponentens sink er 392 (1198 er alias for
  392, §2.6). I læseren folder 742/743 sammen med 540/541, og Gabel og Hahn får én ægtemand (empirisk prøve, §2.4).
  **Følge, opdaget efter valget:** læseren henter fakta for alle fysiske medlemmer af komponenten
  (`web/src/data/personMembers.ts`, `public_person_facts`), så 1791's `navn` »fyenske Rytterreg.)« og `død` står i
  Conrads faktaliste som »fra den oprindelige import«. De kan ikke fjernes: begge påstande er `uforanderlig=true`, og
  `red_slet_oplysning` afviser importerede påstande (`schema.sql:6736`; målt på stand-in'en).
- **(b) `red_set_privat(1791, true)`** (`schema.sql:6821`; *min nye anbefaling*). `person_offentlig` udelukker private
  personer, og `family_offentlig` skjuler en familie, når et medlem ikke er offentligt; det kaskaderer til fakta,
  relationer og narrativer. 1791, dens to fakta og familierne 742/743 forsvinder for læseren. 1823/1824 (alias for
  815/816) består med deres datoer. Empirisk prøve (core's collapse uden 1791 og 742/743): Gabel og Hahn har hver én
  ægtemand (Conrad), 0 nye karantæner. Ingen `samme_som`, så Conrads komponent røres ikke, og collapse kan ikke
  karantænere på en skjult tvilling (1791 har ingen kanter). Fortrydes med `red_set_privat(1791, false)`.
  **Tabsafstemning (Codex runde 3, fund 2):** `family` er læsbar, men familiefakta følger `family_offentlig`
  (`db-rls.sql:119`, `:260`, `:469`), så 742/743's `vielse` bliver usynlige. De har samme datoer som 540/541's
  (21 Juli 1667, 1 Maj 1681; 540/541 har desuden sted 730); intet indhold forsvinder for læseren. 1823/1824's
  persondatoer består. Ingen af de fire vielser er bundet til bogen.
  **RLS-tro prøve (fund 4):** `family_member` filtreres pr. person (`db-rls.sql:462`), så læseren får 742/743 som
  unioner med 1823/1824 og `p2=null` (`web/src/data/model.ts:126`). Prøven gentaget med det input (kun 1791's
  rækker fjernet): Gabel og Hahn har hver én ægtemand, 0 nye karantæner.
  Ulempe: 1791 og 742/743 består i redaktørens visning som dubletter. `privat` er skemaets »GDPR: MANUEL skjulning«
  (`schema.sql:128`); brugen her er manuel skjulning af et importlevn, ikke en GDPR-sag, og den ændrer ingen
  RLS-regel (invariant 8 uændret). Placements, B6-tilstand, kandidatinput og narrativets `withdrawn` påvirkes ikke
  (`schema.sql:3040`, `:3382`, `:9538`, `:14849`; Codex runde 3).

**Projektejeren valgte (b)** (§9). Spor O har dermed ingen `samme_som` og påvirker ikke spor R's kandidatinput; det
skrives stadig før R (§6). 1795 afgøres på kort: levn → samme behandling (`red_set_privat`), eller stå.

## 6. Prod og fortrydelse

- **DDL-blok:** profildata + writerens opslag + evt. hjælpefunktioner; idempotent i `db-migrations.sql`,
  `schema.sql` opdateres, `db-verify.sql` asserter 2018-20-profilernes uændrede opførsel. `get_advisors` efter DDL.
- **Dataceremoni:** runner i `~/.private/5ab-overfoersel/` med `maal/apply/verify/fortryd --jeg-mener-det`, som
  6d-1/6d-2b. Rækkefølge: spor D og O, så spor R. Indholdsafledte id'er (`content_uuid`): persona og mention
  (`schema.sql:17735`, `:17745`) og identitetskandidatkørsler (`:11317`). Tilfældige pr. kørsel: batch-,
  autorisations- og versions-id'er, change_sets og `samme_som`-relationernes id'er (Codex fund 10, runde 1+2). Pins
  og afstemning går på indhold (`interpretation_key`, `record_key`, `family_id`, person-id-par).
- **Fortrydelse: ét regime for ceremonien (Codex runde 2, fund 2).** 5b's fortrydelse var *restore-only* (5b-spec
  §13): der findes ingen writer-reversal for relationspersonas, en accepteret relationsfortolkning kan ikke genafgøres
  via normal-RPC'en (`schema.sql:9609`), og genåbning kræver et faktisk familieskift (`:19912-19920`). Derfor:
  - **Ceremoniens `fortryd` = restore** af dumpet taget umiddelbart **før spor D** (altså før alle tre spor), med
    skrivepause fra dump til `VERIFY_OK`, vindues-vagt pr. tabel og katalogdiff (6c-2's form; memory: restore er ikke
    trofast, bogmærker og tilmeldinger forsvinder lydløst). Fejler et spor, fortrydes hele ceremonien.
  - **Afbrudte tilstande (Codex runde 3, fund 3):** sporene committer hver for sig (D, O, R's batches), så ceremonien
    kan stoppe efter D, efter D+O eller midt i R. 6c-2's restore-vagt forventer én afsluttet tilstand
    (`docs/runbooks/trin6c2-prod.md:215`); 6d-3's vagt skal i stedet acceptere ethvert **præfiks** af ceremoniens egne
    skrivninger (nøglet på ceremoniens change_sets og kvitteringer, også når aktøren er den samme som i drift) og
    intet andet siden dumpet. Planen fastlægger transaktionsgrænserne og øver restore efter D, efter D+O og midt i R.
    `begin_change_set` genbruger et aktivt sæt (`schema.sql:9175`); runneren nulstiller `app.change_set_id` mellem
    kald, der skal have hvert sit sæt. Runneren kører som redaktion med `request.jwt.claim.sub` sat (`:6535`).
  - **Spor L** rulles ikke tilbage af en DB-restore og skal ikke: læserrettelsen er korrekt uden 1939-bindinger.
  - **Efter `VERIFY_OK`** er der ingen ceremoni-fortrydelse. Enkeltsager er almindeligt redaktørarbejde under
    kernens regler (`red_fjern_samme_som`, `red_set_privat`, menneskelig identitetsafgørelse), med de samme
    samtidighedsvilkår som al anden redigering; 6d-3 lover ikke en selektiv fortrydelse (*forenklet efter Codex
    runde 3, fund 1*: en sikker selektiv sletning ville kræve, at alle evidens-writers fulgte samme låseprotokol,
    `schema.sql:6687`, `:7165`). Kvitteringen gemmer pr. D-par førbillede (intet link), relation-id, faktisk retning
    og change_set som revisionsspor; førbillede og skrivning sker i samme transaktion under
    `samme_som_mutation`-låsen (re-entrant med RPC'ens egen, `:7655`).
  Planen beviser restore-fortrydelsen fra alle tre afbrydelsestilstande på stand-in før prod.
- **Web:** spor L deployes med Vercel **før** DB-ceremonien (læserrettelsen er harmløs uden 1939-bindinger, og
  anti-målet kræver, at bindingerne er synlige fra første øjeblik).
- Stand-in: en frisk restore af prod efter 6d-2b (ICU, `statement_timeout` 2 min som prod).

## 7. Kort

Én kortrunde, lokal HTML med posttekst, side, forældre og familiens øvrige medlemmer (memory: kort kræver kontekst;
værktøjsnoten fra 6c-3 om forælderarket bygges som repo-værktøj her). Før kortene: tab vist i tal og ét samlet valg
(memory: vis tab før kortrunde). Forventet omfang: ≤44 D-kort, ægteskaber uden entydig familie/navn (≥7 + parkerede
efter foldning), 6 forældre, 1795. Model mod PDF-siden må forbehandle (6d-1's form), projektejeren ser
undtagelser og en stikprøve.

## 8. Færdigbevis

1. Tal i prod: elementer, parkerede pr. årsag, identiteter (maskine/kort), afgørelser, strukturelle bindinger for
   kilde 3; nye `samme_som`; 1791's tilstand.
2. Hver binding før ceremonien er gældende efter (2018-20 uændret; nøglet afstemning, ikke kun antal).
3. Læseren som `anon` mod prod: en sammenfoldet person viser »DAA 1939« som kilde på et ægteskab; en person fra spor D
   viser én ægtefælle; Conrads ægtefæller viser én ægtemand.
4. `status.md`'s relationsrække for 1939 hæves til `produktionsverificeret`.

## 9. Projektejerens valg (2026-11-10)

1. **Spor D er med i 6d-3** (≤44 kort uden forudfyldning).
2. **1791 markeres privat** med `red_set_privat(1791, true)` (§5.4 b; projektejerens valg efter Codex runde 2,
   der afløser første valg, `samme_som` → Conrad, fordi 1791's uforanderlige fakta da ville stå i Conrads faktaliste).
   Det tæller som »ryddet« i decisions 2026-11-10's forstand: læseren viser ikke længere 1791 som ægtemand.
3. **Spor L er med i 6d-3** og deployes før dataceremonien.

## 10. Reviewlog

**Byggertjek 2026-11-10 (Opus, frisk kontekst):** 6 spørgsmål, efterprøvet mod koden og stand-in'en.
1. Børnebindingen kræver `relation-child-v1` → efterprøvet (`schema.sql:19599-19604`); børnene får disposition (§4).
2. §9's valg → forelagt projektejeren.
3. 2018-20's 4 partsløse ægteskaber → målt (§2.7); 2 bindes, 2 får disposition.
4. Familie uden ægtefælle → målt: 0 af 1939's 271 (§2.1).
5. »Ingen af dem« på D-kort → skrives ikke i basen (§5.2).
6. Deployrækkefølge → spor L før ceremonien (§6).

**Codex-runde 1 (2026-11-10, `gpt-6.1-sol`, review-budgettets spec+plan-runde brugt på specen): NO-GO, 9 MAJOR + 1
MINOR.** Afvejet af Opus mod koden og stand-in'en; alle nødvendige.

| # | Fund | Afvejning | Ændring |
|---|---|---|---|
| 1 | Forældre kan ikke afgøres via `red_decide_relation_interpretations` | nødvendig (efterprøvet `:19785`) | §5.1.4: 2a's vej + kandidatmåling |
| 2 | L sikrer ikke synlighed; gaten har flere krav | nødvendig; målt: 281/281 består publiceringsdelen, 6 fejler `n_support` | §2.5, §5.1.4-5 |
| 3 | `samme_som`'s guards og retning | nødvendig (efterprøvet `:7563-7590`, `:7670`); 1198 er alias → 1791 → 392 | §2.6, §5.2, §5.4 |
| 4 | D/O efter R gør kontrollen forældet | nødvendig | §5.2, §6: D/O før R |
| 5 | Fremadrettet rettelse er ikke fortrydelse | nødvendig | §6: R restore-only |
| 6 | D/O-fortrydelse kan fjerne ældre link | nødvendig (efterprøvet `:7658`) | §6: oprettet-mærke |
| 7 | Maskinaccept for svag | nødvendig | §5.1.3: hele eligibility-kontrakten |
| 8 | L mangler forælder/børn | nødvendig | §5.3 |
| 9 | Profil skal adskille prædikater | nødvendig (efterprøvet `:17595`) | §5.1.1 |
| 10 | Persona/mention-id'er er indholdsafledte | nødvendig (efterprøvet `:17735`) | §6 |

**Efterprøvning efter runde 1 (Opus, rådgiver):** empirisk collapse-prøve (§2.4), overslag over maskinpopulationen
(§2.1), »synlig disposition« er ikke en skrivning (§4), 1791's fakta i Conrads faktaliste (§5.4).

**Codex-runde 2 (2026-11-10, `gpt-6.1-sol`, ud over budgettet på projektejerens anmodning): NO-GO.** Runde 1: 7
LUKKET, 3 DELVIST (5, 6, 10). 4 nye MAJOR, afvejet af Opus; alle nødvendige.

| # | Fund | Afvejning | Ændring |
|---|---|---|---|
| 1 | Foldning mangler i ægteskabsnummeret | nødvendig; målt 59/271 uden position, 11 poster i risiko (`:17472`) | §5.1.1 |
| 2 | Én ceremoni, to fortrydelsesregimer | nødvendig | §6: ét regime, restore af dump før D |
| 3 | Oprettet-mærket beviser ikke sikker fjernelse | nødvendig (efterprøvet `:7165`) | §6: mærke i samme transaktion + evidens-efterbillede |
| 4 | 1791's fakta kan ikke slettes | nødvendig; målt: `uforanderlig=true` (`:6736`) | §5.4: ny vej (b) `red_set_privat`, empirisk prøvet; §9 genåbnet |
| R1-10 | Kandidatkørsler er også indholdsafledte | nødvendig (`:11317`) | §6 |
| R1-7 | Én familie kræver intet ordinalmatch; overslaget er ikke hele kontrakten | nødvendig | §5.1.3 |

**Codex-runde 3 (2026-11-10, `gpt-6.1-sol`, smal: kun §5.4 b og §6; projektejeren har frigivet budgettet for
dagen): A NO-GO, B NO-GO; 3 MAJOR + 1 MINOR.** Afvejet af Opus:

| # | Fund | Afvejning | Ændring |
|---|---|---|---|
| 1 | Selektiv D-fjernelse efter `VERIFY_OK` kan slette samtidig evidens | forenkl: ingen selektiv ceremoni-fortrydelse efter `VERIFY_OK`; drift er almindelig redigering | §6 |
| 2 | 742/743's `vielse` skjules uden afstemning | nødvendig; målt: samme datoer på 540/541, intet tab | §5.4 b |
| 3 | Restore fra afbrudte fler-spors tilstande | nødvendig | §6: præfiks-vagt, øvelse efter D, D+O og midt i R |
| 4 | Collapse-prøven brugte ikke RLS' input | nødvendig; gentaget med RLS-tro input, samme resultat | §5.4 b |

Codex fandt ingen følger for placements, B6, kandidatinput, narrativstatus eller GDPR-regler. Næste Codex-review:
planen og derefter diffen før prod.
