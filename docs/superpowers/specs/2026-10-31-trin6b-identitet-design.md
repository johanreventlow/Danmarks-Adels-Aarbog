# Trin 6b: 1939's identitet — design

**Status:** udkast til projektejerens læsning. Brainstorm-spørgsmål sprunget over efter projektejerens ønske
(2026-10-31); alle valg i dokumentet, der ikke står i den overordnede spec, er markeret *mit valg*.
**Gren:** `docs/trin6b-spec` fra `main` (`6dcdee34`).
**Overordnet spec:** `docs/superpowers/specs/2026-10-29-trin6-1939-gennem-kaeden-design.md` (§5 6b, §6 pkt. 1 og 8,
§7 første punkt).
**Review-budget (B13):** 1 Codex-runde på spec+plan (`gpt-6.1-sol`, Opus dømmer), 1 på diffen før prod.
**Grundlag:** 5a-specen (`2026-09-24-trin5a-identitetsvej-design.md`, §3 pkt. 1: »1939's match flyttes ind i
persona-laget i trin 6«), 149b's migrering (`private.migrate_legacy_narrative_record`), C0/C3 (1939's 559
postbindinger), reviewets `fable-koncept.md` pkt. 16 og `udestaaende-raa.md` pkt. 59-60.

## 1. Roadmap-kobling

1. **Roadmapmål:** trin 6, færdigbevis (a): 1939's identitet går gennem samme operationer som 2018-20's.
2. **Værdikædeled:** source personas og identitet (målarkitekturens gate 5). Det næste led, fortolkning og binding
   (6c), kræver en accepteret identitet pr. persona (overordnet spec §2).
3. **Leverancetype:** generel mekanisme (en ny elementoperation i den generelle writer og en ny, strukturel
   identitetsoprindelse) + generatorforbedringer, som enhver udgave bruger. Ingen editionsnavngiven overflade.
4. **Værdi:** 1939's poster får en sporbar identitet i evidenslaget i stedet for kun C3's postbinding; navnefæller og
   uenigheder med `samme_som` lægges for projektejeren; enighed afgøres maskinelt.
5. **Færdigbevis:** §8.
6. **Erstatter:** C3's postbinding (`existing_exact_binding`) som eneste bærer af 1939's identitet; den uvagtede
   antagelse, at `samme_som` er rigtig, fordi den findes.

## 2. Målt udgangspunkt

Alle tal er fra stand-in'en `daa5ab_ddl_standin_20261030210000_6am2` (= prod efter 6a, manifest byte-ens), kun antal,
2026-10-31. Ikke målt mod prod; tallene genmåles mod prod i ceremoniens `maal` før GO.

### 2.1 Records og personer

| | Antal |
|---|---|
| 1939-records (kilde 3) | 592 |
| — med helpost (én `person`-mention) | 584 |
| — uden helpost (6 `structural_context`, 2 `cross_reference`) | 8 |
| Helposter med publiceret narrativbinding (C3) | 563 → 563 forskellige personer |
| Helposter uden binding | 21 |
| Personas for kilde 3 i dag | 8, alle `accepted` (v50-oprettelsen), alle blandt de 563 |
| Helposter, der skal have persona i 6b | **555** |
| Forankringer pr. helpost: 1 / 2 / 3 / 4 / 5 | 349 / 178 / 45 / 11 / 1 |
| `person`-mentions pr. helpost | præcis 1 for alle 584 |

De 563 bundne personer er alle afdøde (`levende=false`), ingen er `privat`, 2 er `staged`. Hver har præcis én
`person_external_id` for kilde 3 og ingen for kilde 1: de er kilde 3's egne personrækker, hvor 1939's påstande ligger
(overordnet spec §6 pkt. 8).

### 2.2 Hvorfor 149b's migrering ikke kan bruges

Migreringen (`schema.sql:4003-`) kræver for hver record (1) præcis én accepteret forankring, (2) at
`person_external_id.record_key` er recordens nøgle, (3) at narrativet ikke har en publiceringsbinding. Målt på de 584
helposter:

| Gate | Opfyldt |
|---|---|
| Én forankring | 349 |
| `person_external_id.record_key` = recordens nøgle | 8 (de 8 med persona) |
| Ingen publiceringsbinding | 21 |
| **Alle tre** | **0** |

1939's `person_external_id.record_key` stammer fra den gamle indlæsning og har en anden form end evidenslagets
`source_record.record_key`. Identitetskernens oprindelse `legacy_match` bygger på samme nøglelighed og afviser derfor
også. »149b genbruges, hvor den gælder« (overordnet spec §5) gælder ingen 1939-post.

### 2.3 `samme_som` og navnefæller

- 469 af de 563 er koblet med `samme_som` til en 2018-20-person; 466 af disse har en accepteret 2018-20-persona,
  3 har ikke. 2 koblinger går til en anden kilde 3-person. 1 person har to partnere. 93 står alene.
- `relation.konfidens` er NULL på alle 719 `samme_som`. Invarianttriggeren (`enforce_samme_som_invariants`) afviser
  en `samme_som`, der overlapper en `ikke_samme_som`-komponent; 13 `ikke_samme_som` berører de 563.
- **Navnefæller:** 239 af de 561 ikke-staged har mindst én person med samme visningsnavn i en anden
  `samme_som`-klynge (103 har fem eller flere). Kun navn kan altså ikke afgøre dem.
- **Navn og årstal på personasiden:** generatorens input tager personaens navn fra en `person.name`-fortolkning og
  ellers fra den primære mentions tekst, og årstal kun fra fortolkninger. 1939 har ingen fortolkninger før 6c, og
  1939's `person`-mention dækker hele helposten, ikke navnet: 7 af 584 er under 50 tegn, 115 over 400 (op til 3.931).
  Kørt i dag ville generatoren altså sammenligne en hel post med et navn. 2018-20's mentions er lige så lange; 5a
  virkede, fordi trin 4's runner havde lagt navn og årstal som fortolkninger.
- **Årstal på personsiden:** 18 af 370 1939-fødselspåstande har `date_min/max` (5a-beviset); visningscachen har dog
  mindst ét årstal for 434 af de 563.
- **Navnefæller uden kobling:** af de 93 uden `samme_som` har 62 en navnefælle i en anden klynge, 17 af dem en
  2018-20-person. Det er kandidater til en manglende kobling, ikke nødvendigvis fejl.
- `staged` personer er med i generatorens kandidatpulje (flag, ikke filter).
- Generatoren kender allerede `samme_som`-klynger (5b: `packages/identity-candidates/src/rank.ts`, `clusters` fra
  inputtets `same_as`); `udestaaende-raa.md` pkt. 59 er altså delvis løst. Pkt. 60 (årstal) er ikke.

### 2.4 Rester

| Hvad | Antal | Hvad det er |
|---|---|---|
| Helposter uden binding | 21 | 16 `[NY]` (ingen modpart, C0) + 5 andre (C0's uafklarede: grænsefejl og C3-sammenlægninger, fx 1017/1021) |
| Kilde 3-personer uden bundet narrativ | 13 | 8 med `grandfathered_publication` + 5 `staged` (933, 935, 940, 1014, 1135) |
| Bundne, men `staged` | 2 | 963, 967 (C0-efterkørslen) |
| `samme_som` mellem to kilde 3-personer | 2 | dubletter i 1939 (jf. 929/930, 1013/1014 med byte-ens tekst) |

## 3. Afgrænsning

**Med:** persona + mention + identitet for de 555; en kontrol af alle 563 bindinger med generatoren; navnefæller og
uenigheder til projektejeren; generatorens årstal fra rå tekst og kandidatvisning (pkt. 16); synlige dispositioner for
alle rester i §2.4.

**Ikke med:** nye personer (de 16 `[NY]`: opret-benet, B4); sammenlægning af C3-dubletter; at skrive, ændre eller
slette `samme_som`; relationspersonas (ægtefæller, børn: 6d); fortolkninger (6c); de 7 staged personers status.

## 4. Design

### 4.1 Identitetsmål

En 1939-persona peger på den kilde 3-personrække, recordens publicerede narrativ handler om
(`narrative_record_publication` → `narrative.subjekt_id`). Det følger af overordnet spec §6 pkt. 8 og er
deterministisk for de 563. Sammenhængen med 2018-20 bæres af `samme_som`, ikke af identiteten.

### 4.2 Ny indgang: elementoperation `publication_identity` (*mit valg*)

En ny elementoperation i den generelle reimport-writer (authorize → begin → apply → finalize, som 6a) i stedet for at
løsne migreringen. Den udvidede migrering ville skulle opgive tre af sine sikringer, og den flytter publicering, som 6b
ikke skal røre.

Pr. element (én helpost):

- **Forudsætninger, efterprøvet i skrive-transaktionen:** recorden findes for kilden; den har præcis én
  `person`-mention over sine accepterede forankringer (flere forankringer er tilladt); præcis én publiceret
  `narrative_record_publication`; narrativets subjekt er en person med præcis én `person_external_id` for kilden;
  ingen persona findes for recorden. Payloaden bærer hashes af mentionens tekst og bindingens id/status, så drift
  afvises (som 149b).
- **Skriver:** `source_persona` og `source_persona_mention` (rolle `primary`). **Ingen identitet** i dette trin
  (§4.3 bestemmer den). Nøglen er `'1939:' || source_record.record_key`, samme form som de 8 eksisterende
  (*mit valg*: én form inden for kilden; 2018-20 bruger `record_key` alene). Runnerens input kobler i dag persona og
  record på `persona_key = record_key` (`export_43b_runner_input.R:59-66`); 6c skal koble gennem mentionen i stedet
  (§5).
- **Id'er:** deterministiske (`private.deterministic_uuid` af persona-nøglen), som 5b's personas. Replay giver
  `already_applied`.

Identiteten skrives af en ny strukturel oprindelse i `private.decide_source_persona_identity`:
**`publication_binding`** (*mit valg* af navn). Kernen efterprøver selv, ikke kun writeren: `accepted`, version 0,
ingen `basis`, `evidence.authority='narrative_record_publication'`, bindingen er publiceret og peger på målpersonen,
personen har præcis én `person_external_id` for personaens kilde, og personaens primære mention ligger i bindingens
record. Dermed står 1939's identitet med samme styrke som 149b's `legacy_match`, men bygget på det, 1939 faktisk har.

### 4.3 Kontrol før identiteten (kontrolmodellen, *mit valg* af anvendelse)

5a §3 pkt. 1 siger: ingen massegenbekræftelse. Det overholdes: mennesket ser kun uenigheder og en stikprøve.
Maskinen kontrollerer alle.

**Rækkefølge (*mit valg*):** kontrollen kører først, når 6c's runner har lagt `proposed` navn, fødsel og død som
fortolkninger på de 1939-personas (§2.3: uden dem sammenligner generatoren en hel post med et navn). Runneren
kræver kun personas, ikke identitet; promotionen kræver identitet. Derfor: personas (6b, ceremoni B) → runneren
(6c) → kontrol og identiteter (6b, ceremoni C) → kontrolmodel og promotion (6c). Fravalgt: at udlede navn og år af
helposten med en ny regel i inputtet; det ville være en anden navnekilde end 2018-20's og en ny heuristik på rå OCR.

1. Generatoren (`packages/identity-candidates`) køres i `list`-tilstand på de 563 personas (de 555 nye + de 8),
   og kandidaterne gemmes med `red_record_identity_candidates` (5a's vej, ingen ny writer).
2. **Udfald pr. persona:**
   - **enig:** top-1-klyngen er entydig (ingen anden klynge med samme score) og indeholder bindingens person;
   - **uenig:** top-1-klyngen indeholder ikke bindingens person;
   - **navnefælle:** to eller flere klynger deler top-1-score.
3. **enig** får identitet med `publication_binding` (evidensen bærer kandidatkørslens id og rang). En blind stikprøve
   på 20 af de enige går på arket uden svar (kontrolmodellen, overordnet §6 pkt. 1); én R eller U stopper.
4. **uenig** og **navnefælle** går på token-arket (højst ~30 kort pr. ark, forudfyldt med bindingens person,
   overordnet §3 (d)). Kortet viser bindingens person og den eller de konkurrerende klynger side om side med navn,
   leveår, titel og postreference (pkt. 16, kandidatvisning), fordi et forudfyldt ark før har skjult en konkurrent
   (#248). Svar:
   - **S** (bindingen er rigtig): identitet med oprindelse `human`, `basis='human_sheet'`, målet er bindingens person.
     Kortet kan desuden markere »og kandidat X er samme person« (en manglende `samme_som`); markeringen skrives kun
     som note i evidensen og i kontrolrapporten, så en rigtig binding med manglende kobling ikke tvinges til F/U;
   - **F** (bindingen er forkert): identitet `unresolved` med `reason='publication_binding_disputed'`; ingen anden
     person vælges i 6b, og publiceringsbindingen røres ikke (sagen står synligt til en senere C3-rettelse);
   - **U** (ved ikke): `unresolved` med `reason='unknown'`.
5. **Stopregel:** giver kontrollen over 90 kort (tre ark), stoppes der, og afgrænsningen tages op med projektejeren,
   før noget skrives.

En persona uden accepteret identitet er udelukket fra 6c's promotion, som i dag.

### 4.4 Generatoren: årstal fra rå tekst (pkt. 16, *mit valg* af form)

Personasiden får årstal fra runnerens fortolkninger (§4.3). Personsiden mangler dem: uden årstal bliver de 239
navnefæller kort. Inputtet (`private.identity_candidate_input`) får derfor årstal fra påstandens `date_raw` som
reserve, når `date_min/max` mangler. Reglen er deterministisk, bærer oprindelsen `date_raw` i inputtet og vægtes ikke
højere end parsede datoer. Dækningen måles i planen på stand-in'en, før reglen låses; giver den ikke et klart fald i
navnefæller, er stopreglen (§4.3 pkt. 5) svaret.

### 4.5 `samme_som` (*mit valg*)

6b læser `samme_som` og skriver den ikke. »Afklaret« betyder en eksisterende `samme_som`-relation; invarianttriggeren
sikrer, at den ikke modsiger en `ikke_samme_som`. `konfidens` bruges ikke (NULL på alle). Viser kontrollen, at en
1939-persona hører til en anden klynge end sin `samme_som`-partners, er det et **uenig**-kort; projektejeren kan
derefter selv rette koblingen med de eksisterende RPC'er (`red_fjern_samme_som`, `red_samme_som`) uden for ceremonien.
De 93 uden kobling får ingen ny kobling i 6b; de tælles og vises i kontrolrapporten.

### 4.6 Dispositioner for resterne

Ingen af resterne får persona i 6b. Hver vises i ceremoniens rapport med antal og grund:

| Rest | Disposition |
|---|---|
| 16 `[NY]` | `opret_benet` (B4) |
| 5 andre ubundne helposter | `c3_uafklaret` (grænsefejl/sammenlægning; listet pr. record) |
| 8 records uden helpost | `ingen_helpost` |
| 13 kilde 3-personer uden bundet narrativ | `ingen_postbinding` |
| 2 bundne `staged` | får persona og identitet som de øvrige; `staged` ændres ikke (identiteten er privat) |
| 2 `samme_som` mellem kilde 3-personer | vises i kontrolrapporten; ingen ændring |

## 5. Følger

- Efter ceremoni B har 1939 en persona for hver bundet helpost, og 6c's runner kan køre på dem. Efter ceremoni C kan
  promotionen binde til kilde 3-rækken. 6c's delspec skal rumme rækkefølgen runner → 6b C → promotion.
- 6c's runner-input skal koble persona og record gennem den primære mention, ikke gennem `persona_key = record_key`
  (§4.2), og vælge tilladte poster ud fra bindingens person (alle 563 er afdøde), ikke ud fra identiteten.
- `private.identity_candidate_input` ændres (årstalsreserve); det rammer også 2018-20-kørsler. 5a's kalibrering mod de
  587 genkøres i planen og må ikke falde.
- Den nye oprindelse skal med i 5a's guard mod gamle veje (`decide_source_persona_identity`'s oprindelsesliste) og i
  reversalen (`reversal` skal kunne sætte en `publication_binding`-identitet til `superseded`).

## 6. Prod

Tre ceremonier i 6a's form (dump med ekstern kopi, kørsel fra projektejerens shell med `--jeg-mener-det` og GO,
`maal` før og efter):

- **A (DDL):** elementoperationen og dens reversal, den nye oprindelse, årstalsreserven i inputtet. Additiv; tal
  uændrede.
- **B (data):** `publication_identity`-batchen: 555 personas + mentions, ingen identitet.
- *(6c's runner kører her.)*
- **C (data), efter runneren:**
  1. generatoren i `list`-tilstand mod prod (inputtet læses fra prod, kandidaterne skrives med
     `red_record_identity_candidates`); arket bygges lokalt i en gitignoreret arbejdsmappe (alle 563 er afdøde;
     arket sendes aldrig til en model) og udfyldes af projektejeren; arkets hash bindes;
  2. identiteterne: `publication_binding` for enige + S, `unresolved` for F/U, i én transaktion med den bundne hash.

  Udfyldningen kan tage dage; kandidatkørslen bindes af `input_sha256`, så drift i mellemtiden afvises.
- **Fortrydelse:** personas uden identitet har ingen afhængige; `red_reverse_reimport` på batchen (den nye
  elementoperation skal have sin gren i reversalen; bygges og øves i A). Identiteterne fortrydes med
  `reversal`-oprindelsen. Nødudvej: restore af dumpet.
- Øvelse på en frisk stand-in med prods `statement_timeout` (2 min) før hvert GO.

## 7. Færdigbevis

- 555 nye personas, hver med én `primary`-mention i sin egen record; 0 dubletter; replay `already_applied`.
- Hver af de 563 har enten `accepted` (oprindelse `publication_binding` eller `human`) eller `unresolved` med grund;
  intet mål er en anden person end bindingens.
- Kontroltal: enig/uenig/navnefælle, stikprøvens 20 (0 R/U), arkenes S/F/U, antal kort.
- Generatorens dækning af årstal før og efter (personas og 1939-personer), og 5a-kalibreringen uændret eller bedre.
- Resterne i §4.6 talt og listet.
- (a): kun de fælles operationer er brugt (tjekliste: writerens kæde, `decide_source_persona_identity`,
  `red_record_identity_candidates`, token-arket); ingen editionsnavngiven overflade.
- `status.md`: 1939's »Identitet« fra »ikke påbegyndt« til `produktionsverificeret` med dato.

## 8. Afgørelser til projektejeren

Mine valg, som projektejeren bør se:

1. Ny elementoperation og ny oprindelse `publication_binding` i stedet for at løsne 149b (§4.2).
2. Personas nu, identitet først efter 6c's runner (§4.3, rækkefølge); persona-nøglen `'1939:' || record_key` (§4.2).
3. Maskinen kontrollerer alle 563; projektejeren ser kun uenigheder, navnefæller og en blind stikprøve på 20 (§4.3).
4. **F** giver `unresolved`, aldrig en anden person; publiceringsbindingen røres ikke. **S** kan notere en manglende
   `samme_som` uden at skrive den (§4.3).
5. Årstal fra `date_raw` som reserve på personsiden (§4.4).
6. 6b skriver ingen `samme_som` (§4.5).
7. De 2 bundne `staged` får identitet; deres `staged` ændres ikke (§4.6).
8. Stopregel ved over 90 kort (§4.3).

## 9. Uden for scope

Opret-benet (16 `[NY]`), C3-sammenlægninger og -rettelser, `samme_som`-rettelser i ceremonien, relationspersonas,
fortolkninger, placement, læserfladen.

## 10. Reviewlog

(tom)
