# Trin 6b: 1939's identitet — design

**Status:** GODKENDT af projektejeren 2026-10-31, efter Codex-runde 1 (§10); de 9 afgørelser i §8 godkendt. Brainstorm-spørgsmål sprunget over efter projektejerens ønske
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
5. **Færdigbevis:** §7.
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
`source_record.record_key`. Nøgleligheden håndhæves i 149b-writeren (`schema.sql:4063-4066`); identitetskernens
`legacy_match` kræver kun, at den leverede eksterne nøgle er entydig og peger på målpersonen
(`schema.sql:9488-9503`). »149b genbruges, hvor den gælder« (overordnet spec §5) gælder ingen 1939-post.

En helpost med flere forankringer har én forankring med `person`-observationen og andre med records' øvrige
observationer (fakta, ægteskaber); hver forekomst har præcis én topobservation. 6a's klausul-writer vælger helposten
efter helpost-reglen. Trin 4's forslagswriter gør ikke: den kræver præcis én accepteret forankring
(`schema.sql:4980-4983`) og afviser derfor 235 af de 584 (§5).

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

**Med:** persona + mention for de 555; en kontrol af de 561 ikke-staged bindinger med generatoren; identitet for de
553 nye ikke-staged; navnefæller og uenigheder til projektejeren; generatorens årstal fra `date_raw` og
kandidatvisning (pkt. 16); synlige dispositioner for alle rester (§4.6).

**Ikke med:** nye personer (de 16 `[NY]`: opret-benet, B4); sammenlægning og rettelse af C3-bindinger; at skrive,
ændre eller slette `samme_som` eller publiceringsbindinger i ceremonien; at ændre de 8 eksisterende identiteter;
relationspersonas (6d); fortolkninger og runneren (6c); de 7 staged personers status.

## 4. Design

### 4.1 Identitetsmål

En 1939-persona peger på den kilde 3-personrække, recordens publicerede narrativ handler om
(`narrative_record_publication` → `narrative.subjekt_id`). Det følger af overordnet spec §6 pkt. 8 og er
deterministisk for de 563. Sammenhængen med 2018-20 bæres af `samme_som`, ikke af identiteten.

### 4.2 Personas: elementoperation `publication_persona` (ceremoni B, *mit valg*)

En ny elementoperation i den generelle reimport-writer (authorize → begin → apply → finalize, som 6a) i stedet for at
løsne migreringen. Den udvidede migrering ville skulle opgive tre af sine sikringer, og den flytter publicering, som 6b
ikke skal røre.

Pr. element (én helpost):

- **Lås:** recorden (`source_record … FOR UPDATE`) og derefter publiceringsbindingen, i den rækkefølge, før nogen
  læsning, der afgør skrivningen.
- **Forudsætninger, efterprøvet under låsen:** recorden findes for kilden; den har præcis én `person`-observation
  blandt sine accepterede forankringer og præcis én mention i den (helpost-reglen fra 6a); præcis én publiceret
  `narrative_record_publication`; narrativets subjekt er en person med præcis én `person_external_id` for kilden;
  **ingen persona for kilden har en mention i recordens helpost** (ikke kun: ingen persona med samme nøgle). Payloaden
  bærer hashes af mentionens tekst og af bindingens id og status; drift afvises (som 149b).
- **Skriver:** `source_persona` og `source_persona_mention` (rolle `primary`). **Ingen identitet.** Nøglen er
  `'1939:' || source_record.record_key`, samme form som de 8 eksisterende (*mit valg*: én form inden for kilden;
  2018-20 bruger `record_key` alene).
- **Id'er:** indholds-id (`private.content_uuid('source-persona', {source_id, persona_key})`), som 5b's personas
  efter #151 (præciseret i planen; udkastet sagde `deterministic_uuid`). Replay giver `already_applied`.
- **Webkøen:** personas uden identitet vises i dag som `proposed` i `red_source_persona_queue`. Mellem B og C må de
  ikke afgøres der. En persona venter på kontrol, når den ikke har en identitetsrække eller har en fortrudt
  publikationsidentitet (§6), er skrevet af en `publication_persona`-batch, og ingen `finalized`
  `publication_identity`-batch navngiver den batch. Sådanne personas
  er skjult i køen, og `red_afgoer_source_persona` afviser dem (præciseret i planen: kandidatkørslen alene lukker
  ikke vinduet). C afviser desuden enhver persona, hvis identitetsversion ikke er 0, undtagen en fortrudt
  publikationsidentitet (§6).

### 4.3 Kontrol og identitet (ceremoni C, *mit valg* af anvendelse)

> **Ændret 2026-11-02 (retning 2):** for 1939's C erstattes pkt. 3-6 af delspec 6c-1 §4.8: C3-bindingen er
> identiteten for `enig`, `svag` og `ingen_kandidat`; kun `uenig` (inkl. bindingspersonen fraværende blandt
> kandidaterne) og `navnefaelle` plus en stikprøve på 20 af de automatiske går på kort; loftet er 125. Øvelsen af
> designet nedenfor gav 550 kort (`docs/decisions.md` 2026-11-02).

5a §3 pkt. 1 siger: ingen massegenbekræftelse. Det overholdes: mennesket ser kun uenigheder, svage sager og en
stikprøve. Maskinen kontrollerer alle.

**Rækkefølge (*mit valg*):** kontrollen kører først, når 6c's runner har lagt `proposed` navn, fødsel og død som
fortolkninger på personaerne (§2.3: uden dem sammenligner generatoren en hel post med et navn). Runneren kræver kun
personas, ikke identitet; promotionen kræver identitet. Derfor: personas (6b, B) → runneren (6c) → kontrol og
identiteter (6b, C) → kontrolmodel og promotion (6c). Fravalgt: at udlede navn og år af helposten med en ny regel i
inputtet; det ville være en anden navnekilde end 2018-20's og en ny heuristik på rå OCR.

**Kontrolmængden:** de 561 ikke-staged bundne personas (de 553 nye + de 8). De 2 staged indgår ikke, fordi runneren
ikke må sende dem til en model (§4.6). De 8 eksisterende identiteter kontrolleres, men ændres ikke (§4.6).

1. Generatoren (`packages/identity-candidates`) køres i `list`-tilstand, og kandidaterne gemmes med
   `red_record_identity_candidates` (5a's vej).
2. **Bindingspersonens egen score afgør, ikke klyngens.** Generatoren folder kandidater i samme `samme_som`-klynge
   sammen og beholder det bedste medlems score (`rank.ts:45-62`). Kontrollen må ikke bruge den sammenfoldede score:
   ellers kan en 2018-20-partner med bedre årstal »bekræfte« en 1939-række, der selv matcher dårligt, og koblingen
   bekræfter sig selv (cirkulært, mod overordnet §7). Generatoren udskriver derfor også bindingspersonens egen
   score og signaler og, for hver konkurrerende klynge, dens bedste medlem. Fuldt komponentmedlemskab tages fra
   inputtets `same_as`, ikke fra de medlemmer, der overlevede filtreringen.
3. **Udfald pr. persona** (tærskler kalibreres i planen, se pkt. 7):
   - **enig:** bindingspersonen selv har generatorens `auto`-tier, mindst ét årstalssignal ud over navnet, og en
     margin til den bedste konkurrerende klynge på mindst den kalibrerede værdi;
   - **svag:** bindingspersonen er bedst, men uden `auto`, uden årstalssignal eller under marginen;
   - **uenig:** en anden klynge scorer højere end bindingspersonen selv;
   - **navnefælle:** en anden klynge scorer lige med bindingspersonen;
   - **ingen kandidat:** bindingspersonen er ikke blandt kandidaterne.
   Hver persona får præcis ét udfald.
4. **enig** får identitet med oprindelsen `publication_binding` (§4.3.1). En blind stikprøve på 20 af de enige går
   på arket uden svar (kontrolmodellen, overordnet §6 pkt. 1); ét F eller U stopper C.
5. **svag, uenig, navnefælle, ingen kandidat** går på token-arket (højst ~30 kort pr. ark, overordnet §3 (d)). Kortet
   viser bindingens person og de konkurrerende klynger side om side med navn, leveår, titel og postreference
   (pkt. 16), med bindingspersonens egen score adskilt fra klyngens, fordi et forudfyldt ark før har skjult en
   konkurrent (#248). Svar:
   - **S** (bindingen er rigtig): identitet med oprindelsen `human`, `basis='human_sheet'`, med arkets og
     rækkefilens hash og linjen (5a's arkvej). Kortet kan desuden markere »og kandidat X er samme person« (en
     manglende `samme_som`); det skrives kun som note i evidensen og i kontrolrapporten;
   - **F** (bindingen er forkert): identitet `unresolved` med `reason='publication_binding_disputed'`. Ingen anden
     person vælges. Narrativet står publiceret på den udpegede person, som i dag; kontrolrapporten lister hver F, og
     projektejeren kan straks trække publiceringen tilbage med den eksisterende
     `red_tilbagetraek_person_narrative_record` uden for ceremonien. Rettelsen af selve bindingen er C3-arbejde;
   - **U** (ved ikke): `unresolved` med `reason='unknown'`.
6. **Stopregel:** over 90 kort (tre ark) i alt, eller en stikprøve med R/U, stopper C, før noget skrives, og
   afgrænsningen tages op med projektejeren.
7. **Kalibrering (planen):** tærsklerne for **enig** fastlægges på 2018-20's 587 kendte svar (5a §8.1) og på en
   stand-in efter en prøvekørsel af runneren; kriteriet er 0 forkerte **enig** blandt de kendte. Ingen tærskel
   vælges for at holde kortantallet nede.

En persona uden accepteret identitet er udelukket fra 6c's promotion, som i dag.

#### 4.3.1 Oprindelsen `publication_binding` og C's indgang

Identiteterne i C skrives af en ny elementoperation `publication_identity` i samme writer-kæde; autorisationen binder
hele afgørelsesmængden. Payload pr. persona: persona-id, forventet identitetsversion 0 (eller den aktuelle version af en fortrudt
publikationsidentitet, §6), bindingens id og status,
kandidatkørslens id og `candidates_sha256`, udfaldet, og for S/F/U arkets hash, rækkefilens hash og linjen. Writeren
efterprøver under lås (persona → binding → personrække): at kandidatkørslen stadig er kildens seneste med samme
konfiguration, at bindingen er uændret og publiceret, at versionen er 0 (eller en fortrudt publikationsidentitets, §6),
og at udfaldet stemmer med de gemte
kandidater.

Den nye strukturelle oprindelse i `private.decide_source_persona_identity` efterprøver selv, ikke kun writeren:
`accepted`, version 0 (eller en fortrudt publikationsidentitets aktuelle version, §6), ingen `basis`,
`evidence.authority='narrative_record_publication'`; bindingen er publiceret og
peger på målpersonen; personen har præcis én `person_external_id` for personaens kilde; personaens primære mention
ligger i bindingens records gældende helpost (accepteret forankring), og ingen anden persona for kilden har en mention
dér. S, F og U skrives af samme writer gennem den eksisterende oprindelse `human` (`basis='human_sheet'`, med
`reason` ved F og U). Writeren kalder kernen direkte, fordi `red_afgoer_source_persona` ikke kan sætte `reason`; den
er dermed den anden serverkalder af `human` (præciseret i planen; `docs/decisions.md` 2026-10-31).

### 4.4 Generatoren: årstal fra `date_raw` (pkt. 16, *mit valg* af form)

Personasiden får årstal fra runnerens fortolkninger (§4.3). Personsiden mangler dem: uden årstal bliver de 239
navnefæller kort. Inputtet (`private.identity_candidate_input`) får derfor årstal fra påstandens `date_raw` som
reserve, når `date_min/max` mangler. Reglen er deterministisk, bærer oprindelsen `date_raw` i inputtet og vægtes ikke
højere end parsede datoer. Reserven er tilvalgt i `input_spec` (`year_fallback: date_raw-v1`), så eksisterende
kandidat- og 5b-kontrolkørsler ikke driver (præciseret i planen). Dækningen måles i planen på stand-in'en, før reglen
låses.

### 4.5 `samme_som` (*mit valg*)

6b læser `samme_som` og skriver den ikke. »Afklaret« betyder en eksisterende `samme_som`-relation; invarianttriggeren
sikrer, at den ikke modsiger en `ikke_samme_som`. `konfidens` bruges ikke (NULL på alle). Kontrollen ser på
bindingspersonen selv (§4.3 pkt. 2); scorer partnerens klynge højere end den, eller tilhører personaen tydeligt en
anden klynge, bliver det et kort. Projektejeren kan derefter selv rette koblingen med de eksisterende RPC'er
(`red_fjern_samme_som`, `red_samme_som`) uden for ceremonien. De 93 uden kobling får ingen ny kobling i 6b.

### 4.6 Dispositioner

Hver vises i ceremoniens rapport med antal og grund:

| Hvad | Persona (B) | Identitet (C) |
|---|---|---|
| 553 nye, ikke-staged | ja | efter kontrollen |
| 2 bundne `staged` (963, 967) | ja | nej; disposition `staged_ikke_offentlig`. Runneren må ikke sende dem til en model (overordnet §6 pkt. 6); deres identitet afgøres, når de bliver offentlige, eller med et kort uden modeldata |
| 8 eksisterende (v50) | findes | uændret; kontrolleres kun. Et udfald andet end **enig** kommer på arket som oplysning; en ændring kræver en særskilt, versionsbundet afgørelse uden for C |
| 16 `[NY]` | nej | `opret_benet` (B4) |
| 5 andre ubundne helposter | nej | `c3_uafklaret` (listet pr. record) |
| 8 records uden helpost | nej | `ingen_helpost` |
| 13 kilde 3-personer uden bundet narrativ | — | `ingen_postbinding` |
| 2 `samme_som` mellem kilde 3-personer | — | vises i kontrolrapporten; ingen ændring |

## 5. Følger

- **6c's forudsætninger** (skal stå i 6c's delspec; C kan ikke køre uden dem):
  - runnerens input kobler persona og record gennem den primære mention, ikke gennem `persona_key = record_key`
    (`export_43b_runner_input.R:59-66`);
  - runnerens input og trin 4's forslagswriter vælger helposten efter 6a's helpost-regel; i dag kræver writeren
    præcis én accepteret forankring (`schema.sql:4980-4983`), og eksporten samler klausuler pr. `record_key`
    (`export_43b_runner_input.R:88-103`). 235 af de 584 helposter har flere forankringer;
  - tilladte poster vælges med hele gaten (afdød, ikke privat, ikke staged), ikke ud fra identiteten;
  - rækkefølgen runner → 6b C → promotion.
- `private.identity_candidate_input` ændres (årstalsreserve), og generatoren udskriver bindingspersonens egen score;
  det rammer også 2018-20-kørsler. 5a's kalibrering mod de 587 genkøres i planen og må ikke falde.
- Den nye oprindelse skal med i 5a's guard mod gamle veje og i reversalen (`reversal` skal kunne sætte en
  `publication_binding`-identitet til `superseded`).

## 6. Prod

Tre ceremonier i 6a's form (dump med ekstern kopi, kørsel fra projektejerens shell med `--jeg-mener-det` og GO,
`maal` før og efter):

- **A (DDL):** de to elementoperationer og deres reversal, den nye oprindelse, årstalsreserven, webkøens filter.
  Additiv; tal uændrede.
- **B (data):** `publication_persona`: 555 personas + mentions, ingen identitet.
- *(6c's runner kører her.)*
- **C (data), efter runneren:**
  1. generatoren i `list`-tilstand mod prod (inputtet læses fra prod, kandidaterne skrives med
     `red_record_identity_candidates`); arket bygges lokalt i en gitignoreret arbejdsmappe (kun afdøde, ikke-staged;
     sendes aldrig til en model) og udfyldes af projektejeren; arkets hash bindes;
  2. `publication_identity`: identiteterne i én batch med den bundne afgørelsesmængde (§4.3.1).

  Udfyldningen kan tage dage. Driften mellem kandidatkørsel og skrivning fanges af writerens efterprøvning (§4.3.1);
  webkøens filter forhindrer afgørelser i mellemtiden.
- **Fortrydelse pr. fase:**
  - *efter B, før runneren:* restore af B-dumpet i det deklarerede vindue, som 6a's ceremoni B. `source_persona` og
    `source_persona_mention` er append-only (`private.reject_evidence_mutation`), så en writer kan ikke slette dem
    (rettet efter Codex' plan-runde; udkastet sagde `red_reverse_reimport`);
  - *efter runneren:* fortolkningerne refererer personaerne og er append-only; B kan ikke længere fortrydes. Vinduet
    lukker, når runneren skriver; det står i runbooken som en bevidst grænse;
  - *efter C, før promotion:* `reversal` sætter C's identiteter til `superseded`; de 8 eksisterende er urørte. C kan
    derefter køres igen: en fortrudt publikationsidentitet (aktuel tilstand `superseded`, seneste overgang er
    fortrydelsen af en `publication_identity`-batch) tæller som ingen identitet, så personaerne igen venter på
    kontrol, indtil en ny C er finaliseret. Det er den eneste udgang: mens de venter, er de skjult i webkøen, og
    `red_afgoer_source_persona` afviser dem, så 6b har ingen menneskelig nødudgang. Den nye C skriver med den aktuelle
    version i stedet for 0 (projektejeren 2026-10-31, `docs/decisions.md`);
  - *efter promotion:* 6c's fortrydelse gælder.
- Øvelse på en frisk stand-in med prods `statement_timeout` (2 min) før hvert GO.

## 7. Færdigbevis

- 555 nye personas, hver med én `primary`-mention i sin egen helpost; 0 records med to personas; replay
  `already_applied`.
- Hver af de 553 nye ikke-staged har enten `accepted` (`publication_binding` eller `human`) eller `unresolved` med
  grund; intet mål er en anden person end bindingens. De 2 staged og de 8 eksisterende står som i §4.6.
- Kontroltal: enig/svag/uenig/navnefælle/ingen kandidat, stikprøvens 20 (0 R/U), arkenes S/F/U, antal kort, antal F
  og hvad der blev gjort med deres publicering.
- Kalibrering: 0 forkerte **enig** blandt 2018-20's kendte svar; 5a-kalibreringen uændret eller bedre; årstals-
  dækning før og efter.
- Resterne i §4.6 talt og listet.
- (a): kun de fælles operationer er brugt (tjekliste: writerens kæde, `decide_source_persona_identity`,
  `red_record_identity_candidates`, token-arket); ingen editionsnavngiven overflade.
- `status.md`: 1939's »Identitet« fra »ikke påbegyndt« til `produktionsverificeret` med dato.

## 8. Afgørelser til projektejeren

Mine valg, som projektejeren bør se:

1. To nye elementoperationer (`publication_persona` i B, `publication_identity` i C) og en ny oprindelse
   `publication_binding` i stedet for at løsne 149b (§4.2, §4.3.1).
2. Personas nu, identitet først efter 6c's runner (§4.3); persona-nøglen `'1939:' || record_key` (§4.2).
3. Maskinen kontrollerer de 561 ikke-staged; bindingspersonens egen score afgør, ikke klyngens; **enig** kræver
   `auto`, årstal og margin, kalibreret til 0 forkerte på 2018-20's kendte svar. Projektejeren ser svage sager,
   uenigheder, navnefæller, sager uden kandidat og en blind stikprøve på 20 (§4.3).
4. **F** giver `unresolved`, aldrig en anden person; publiceringen står, men listes, og kan trækkes tilbage med den
   eksisterende RPC. **S** kan notere en manglende `samme_som` uden at skrive den (§4.3).
5. Årstal fra `date_raw` som reserve på personsiden (§4.4).
6. 6b skriver ingen `samme_som` (§4.5).
7. De 2 staged får persona, men ingen identitet i 6b; de 8 eksisterende identiteter ændres ikke (§4.6).
8. Stopregel ved over 90 kort (§4.3).
9. B fortrydes kun ved restore af dumpet, og kun indtil runneren har skrevet (§6; rettet efter Codex' plan-runde:
   personas er append-only).

## 9. Uden for scope

Opret-benet (16 `[NY]`), C3-sammenlægninger og -rettelser, `samme_som`-rettelser og publiceringsændringer i
ceremonien, relationspersonas, fortolkninger og runneren, placement, læserfladen.

## 10. Reviewlog

### Codex-runde 1 på specen (2026-10-31, `gpt-6.1-sol`, efter projektejerens ønske): NO-GO, 11 fund

Runden ligger uden for B13-budgettet (én runde på spec+plan); projektejeren bad om den. Plan-runden kører stadig.
Desuden ét eget fund (12). Afvejning (Opus):

| # | Alvor | Fund | Afvejning | Indarbejdet |
|---|---|---|---|---|
| 1 | BLOCKER | Klyngens score kan bekræfte en forkert `samme_som` cirkulært | nødvendig | §4.3 pkt. 2, §4.5 |
| 2 | BLOCKER | Forslagswriteren og eksporten tåler ikke flere forankringer (235 helposter) | nødvendig; 6c-arbejde, men forudsætning for C | §2.2, §5 |
| 3 | HIGH | »Enig« kan acceptere rent navnematch; intet udfald uden kandidat | nødvendig | §4.3 pkt. 3 og 7 |
| 4 | HIGH | De 2 staged må ikke til runneren | nødvendig | §4.3, §4.6 |
| 5 | HIGH | De 8 eksisterende identiteter passer ikke i C (version 0) | nødvendig | §4.6 |
| 6 | HIGH | Ingen lås eller dubletvagt på recorden | nødvendig | §4.2, §4.3.1 |
| 7 | HIGH | C har ingen indgang, der efterprøver afgørelsesmængden | nødvendig | §4.3.1 |
| 8 | HIGH | B kan ikke fortrydes, når runneren har skrevet | nødvendig | §6 pr. fase |
| 9 | HIGH | F efterlader narrativet publiceret på en omstridt person | forenkl: ingen ny mekanisme; listes, og den eksisterende tilbagetrækning bruges | §4.3 pkt. 5 |
| 10 | MEDIUM | S havde to modstridende skrivekontrakter | nødvendig | §4.3 pkt. 5, §6 |
| 11 | MEDIUM | `legacy_match`-guarden beskrevet forkert | rettelse af fakta | §2.2 |
| 12 | (eget) | Webkøen viser de nye personas som `proposed` mellem B og C | nødvendig | §4.2, §6 |

### Codex-runde på spec+plan (2026-10-31, `gpt-6.1-sol`, B13-runden): NO-GO, 12 fund

Afvejning og indarbejdelse står i planens reviewlog (`2026-10-31-trin6b-identitet.md`, sidst). Ændringer i specen:
§4.4 (reserven tilvalgt i `input_spec`), §6 og §8 pkt. 9 (B fortrydes kun ved restore).

### Afsluttende review (2026-10-31)

- I2 (afsluttende review): projektejeren valgte genkørsel frem for webkø. §6 (*efter C, før promotion*) og §4.2 er
  rettet; den snævre kernevagt står i `docs/decisions.md` 2026-10-31.
- I2-review D1/D2: den eneste udgang for en ventende persona er en ny C (controller-beslutning; ingen menneskelig
  nødudgang i 6b), og §4.2's definition af at vente omfatter en fortrudt publikationsidentitet.
