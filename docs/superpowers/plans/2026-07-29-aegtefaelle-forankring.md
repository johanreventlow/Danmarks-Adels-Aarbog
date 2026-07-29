# Ægtefælle-forankring — plan

**Dato:** 2026-07-29 · **Status:** plan, ikke påbegyndt
**Formål:** gøre de 627 gift-ind-ægtefæller redigerbare i OCR-kvalitetsarket.

## Problemet i én sætning

En rettelse skal kunne pege på **hvor i bogen** den hører til; indgiftede ægtefæller har ikke et
eget opslag at pege på, kun en omtale inde i deres partners.

`red_ret_ocr_felt` forankrer på `(source.import_key, person_external_id.record_key)`. Ægtefæller har
slet ingen `person_external_id`-række, så RPC'en har intet anker og afviser med `ingen_importanker`.
Det er 627 af 1733 personer — **36 % af korpus**, og hele 66 % af det arket ikke kan røre.

## Målt grundlag (2026-07-29, mod prod)

| | |
|---|---|
| Familier i alt | 664 |
| — begge parter har bogpost | 10 (slægtninge gift med hinanden) |
| — **præcis én part indgift** | **627** |
| — **begge parter uden bogpost** | **0** |
| — kun én part registreret | 27 |

**Ingen union mangler bogpost på begge sider.** Det er ikke et held: bogen er en slægtsbog, så
mindst én part er altid slægtsmedlem med eget opslag. Skulle tilfældet opstå, er det en **datafejl**
— ikke et tilfælde planen skal håndtere. Det bør derfor være en assert, ikke en gren i koden.

Alle 627 ægtefæller optræder i **præcis én** union (0 med flere). Ankerpersonen kan derimod have
flere ægteskaber:

| Ankerpersoner (med bogpost, optræder som partner) | 562 |
|---|---|
| gift én gang | 473 |
| gift to gange | 70 |
| gift 3+ gange | 19 (flest: 5) |
| **ægtefæller der derfor kræver et ægteskabs-indeks** | **164** |

## Nøglens form

```
record_key = <ankerpersonens record_key> + ':' + <ægteskabsnummer>
```

For 463 af de 627 er ægteskabsnummeret altid 1 og kunne udelades — men det gør nøglen uensartet.
Behold det altid; ensartethed er mere værd end kortere nøgler.

## Er ægteskabsnummeret stabilt? — NEJ

⚠ **Dette afsnit er omskrevet to gange. Læs kun denne version.** Historikken står i §"Rettelser"
nedenfor, fordi den forklarer hvorfor konklusionen er som den er.

### Hvor tallet FAKTISK kommer fra

`family_member.ordinal` sættes af **LLM-udtrækket**, ikke af nogen deterministisk regel:

```
LLM-udtræk  →  convert_1939_stamtavle.py:148  ("ordinal": a.get("ordinal"), ren passthrough)
            →  load_daa.R:378                 (add_member(..., ordinal = g(a, "ordinal")))
```

`validate.py:804-805` siger det eksplicit:

> *"aegteskaber er IKKE deterministisk — LLM-udtræk er autoritativt; `derive_aegteskaber()` bruges
> kun advisory (R8)."*

`derive_aegteskaber()` kaldes ét sted i produktion (`validate.py:678`) og kun som et boolsk
advarselsflag. **Den skriver aldrig en ordinal.**

### Konsekvens

`ordinal` deler proveniens med `nr` og `linje='1939'`: **tildelt af pipelinen, ikke af bogen.** En
re-ekstraktion kører LLM'en igen, og LLM-output er ikke deterministisk. Nummeret er derfor **ikke**
en stabil nøglekomponent, og det står i samme kategori som de to andre værdier vi allerede har
besluttet ikke at nøgle på.

### Yderligere fund der svækker nøglen

- **"Pr. narrativ = pr. person" holder ikke.** `segment_1939.py:16` — ankerløse poster får
  *gruppens* delte tekstblok. Flere søskende kan dele samme klip.
- **Grænserne flytter sig empirisk.** Re-segmenteringen 2026-07-26 flyttede postgrænser i **216**
  narrativer (`docs/decisions.md`).
- **`R4` blokerer dublet-ordinaler *inden for* én post** (`validate.py:736-739`). De 10 kollisioner
  i prod må derfor komme fra **flere poster eller kilder** — se §"De 10 kollisioner".

### Valgt vej: nøgl kun hvor bogen selv nummererer

Sæt `record_key` for:

- alle ægtefæller hvor ankerpersonen har **præcis ét** ægteskab (463 af 627) — intet nummer i spil
- ægtefæller hvor **bogen selv** skriver `1°`/`2°` — bogens eget tal, stabilt på tværs af kørsler

**Park resten.** Fail-closed, samme disciplin som beslutningen om 1939's `record_key`: hellere ingen
nøgle end en der kan pege forkert uden at nogen opdager det.

Det kræver at udtrækket **registrerer om tallet kom fra bogen eller fra modellens skøn**. Det gør
det ikke i dag — og det er en ændring i ekstraktionskontrakten, ikke i denne backfill. Uden det felt
kan de to grupper ikke skilles ad, og planen kan kun gennemføre den første (463).

### Re-ekstraktions-kontrol — nødvendig, men ikke tilstrækkelig

En kontrol af *antal ægteskaber + partnernavne* pr. ankerperson efter re-ekstraktion fanger ikke:

- **ombytning:** samme antal og samme navnesæt, men nummer 1 og 2 byttet → nøglen peger på den
  forkerte ægtefælle. Kontrollen skal sammenligne **afbildningen nummer→partnernavn**, ikke mængder.
- **navnløse ægtefæller:** to med `partner_navn = NULL` er ikke til at skelne.
- **1939 er cirkulær:** kontrollen matcher "pr. ankerperson", men 1939-ankre har ingen `record_key`.
  Den forudsætter altså den identitet den skulle beskytte.
- **falske alarmer fryser:** en legitim OCR-navnerettelse ændrer navnesættet → fail-closed → den
  person kan aldrig re-nøgles.

Kontrollen skal derfor sammenligne afbildningen, ikke mængderne — og den løser ikke 1939.

## De 10 kollisioner — flere mulige forklaringer

Fordi `R4` allerede blokerer dublet-ordinaler inden for én post, stammer kollisionerne fra flere
poster eller kilder. Mindst tre forklaringer, og de kræver **modsatte** handlinger:

| Forklaring | Rigtig handling |
|---|---|
| Spøgelses-union (to unioner, bogen beskriver ét ægteskab) | slet den ene |
| **Samme ægteskab attesteret af begge udgaver** | **match dem — det er evidensmodellen efter design** |
| LLM udelod ordinal på to reelle ægteskaber | udfyld, slet intet |
| Gengifte med samme partner | behold begge |

**En oprydning der antager spøgelses-union kan slette et ægte ægteskab.** Hver af de 10 skal
afgøres mod bogen med alle fire forklaringer i hånden.

## Rettelser undervejs (bevaret, fordi de forklarer konklusionen)

1. **Første version:** ordinal er positionsafhængig for 28 af 38 poster og dermed skrøbelig.
2. **Anden version — forkert:** trak det tilbage med den begrundelse at `derive_aegteskaber`
   klipper i bogens rækkefølge og nulstiller pr. person. **Fejlen var at analysere den forkerte
   kodesti** — den funktion er advisory og skriver aldrig en ordinal. Målingen "10 fra bogens
   markører, 28 fra tælleren" målte tilstedeværelsen af `°` i teksten, ikke hvordan tallet blev
   sat, og beviser derfor ingenting om proveniensen.
3. **Denne version:** ordinal kommer fra LLM'en og er ikke stabil. Den oprindelige bekymring var
   rigtig; retraktionen var forkert.

## `linje` — hvad feltet faktisk gør, og hvem der bruger det rigtigt

Feltet har **to opgaver på én gang**: det er proveniens (hvilken gren i bogen) *og* nøglen der
udleder efternavnet, via `regen_person_visning()`s join
`lineage ON l.source_id = pei.source_id AND l.kode = pei.linje`.

For DAA 2018-20 falder de to sammen. For DAA 1939 gør de ikke:

| Kilde | `linje` | Personer | Findes som gren? | Får efternavn |
|---|---|---|---|---|
| 2018-20 | `I`–`V` | 591 | ✅ | 582 |
| 1939 | `VI` | 26 | ✅ (`lineage` id 7, "Den fyenske Linje") | 26 |
| **1939** | **`'1939'`** | **489** | ❌ **placeholder, ingen gren** | **0** |

**Svar på spørgsmålet: nej, grenen bruges ikke på alle de rigtige slægtsmedlemmer.** 489 ægte
Reventlow'er står uden efternavn, fordi konverteren gav dem et syntetisk `linje='1939'` der ikke
matcher nogen gren. De 26 med `linje='VI'` får deres, fordi der siden er oprettet en gren for dem.

Det er samme fejlklasse som en placeholder-`record_key`: en værdi der udfylder et felt uden at
betyde det feltet skal betyde. Vi har allerede besluttet ikke at sætte placeholder-nøgler for 1939
(`docs/decisions.md`); `linje='1939'` er den beslutning, truffet modsat, før den blev formuleret.

### Konsekvens for denne plan

Planen skriver nye rækker i **præcis det felt der allerede er forkert for 489 personer**. To ting
følger:

1. **Ægtefæller får `linje = NULL`.** Ikke en placeholder. Får en indgift hustru en linje, påhæfter
   `regen_person_visning()` slægtsnavnet, og *Marie Elisabeth Blome* bliver til *Marie Elisabeth
   Reventlow*. Hun blev gift ind i slægten; hun tilhører den ikke. `linje` og `record_key` bor i
   samme tabel og udfyldes normalt sammen — derfor er det let at ramme forkert.
2. **Backfillen må ikke røre de 489.** De er uden for scope her, men skal håndteres af
   1939-identitetsarbejdet, som alligevel skal afgøre hvad `linje` betyder for 1939. Assert: ingen
   opdatering rammer en række med `linje = '1939'`.

## Verifikation — og hvad den ikke beviser

Korpus-diff på `visning_efternavn` og `visning_fuldt_navn` for alle personer før og efter.
Forventet: **0 forskelle**.

⚠ **Men en diff på 0 beviser kun at migrationen ikke ÆNDREDE cachen — ikke at cachen er korrekt.**
`regen_person_visning()` er eneste skriver, og den kan kun udlede `Reventlow`. Alligevel står der i
dag to ægtefæller uden `person_external_id` med et efternavn sat:

| id | navn | `visning_efternavn` |
|---|---|---|
| 811 | Hedwig | `Mundhenke` |
| 852 | Beke | `Ahlefeldt-Laurvig` |

Ingen af de to kan stamme fra den nuværende udledning — det er deres **egne pigenavne**, altså
forældet cache fra et tidligere mekanisme eller en siden fjernet `person_external_id`-række.
`UPDATE`-sætningen har en `IS DISTINCT FROM`-vagt og skriver kun ved ændring, så en værdi der aldrig
regenereres bliver stående.

Verifikationen skal derfor være **to** kontroller, ikke én:

- **diff = 0** → migrationen rørte ikke cachen
- **ingen ny række med `visning_efternavn` sat uden at udledningen ville producere den** → cachen er
  konsistent for de rækker vi tilføjer

De to eksisterende afvigelser er forudbestående og skal ikke rettes af denne plan — men de skal
noteres, så en fremtidig diff ikke tolker dem som noget planen forårsagede.

## Rækkefølge

1. **Backfill de 463** hvor ankerpersonen kun er gift én gang. Ingen nummer-afhængighed, ingen
   forudsætninger. Det er planens eneste trin der kan gennemføres i dag.
2. **Opgør de 10 kollisioner** mod bogen med alle fire forklaringer i hånden (se ovenfor) — det er
   dataoprydning, ikke nummerering, og udfaldet kan være både sletning og matchning.
3. **Udvid ekstraktionskontrakten** med et felt der siger om ordinalen kom fra bogens `1°`-markør
   eller fra modellens skøn. Uden det kan de resterende 164 ikke nøgles fail-closed.
4. **Rettelser skal være reload-durable.** Trin 1-2 retter i basen; en `--force-reset` regenererer
   fra artefaktet og ville efterlade nyMintede nøgler forældreløse. Rettelserne hører derfor i
   artefaktet eller i `post_load_fixup.R`-mønstret — ellers bygger planen præcis den skrøbelighed
   `docs/decisions.md` besluttede at undgå.
4. **Verificér:** korpus-diff 0 forskelle · ingen ny inkonsistent `visning_efternavn` ·
   ingen række med `linje='1939'` rørt · `red_person_grid` viser 331 flere redigerbare ·
   `get_advisors(security)` uændret.
5. **Indfør re-ekstraktions-kontrollen** (antal ægteskaber + partnernavne pr. ankerperson,
   fail-closed) som en del af pipelinens gate — ikke som en engangs-kontrol.

**Gevinst, realistisk:** trin 1 alene giver 463 nøgler — men kun de 2018-20-ægtefæller blandt dem
bliver faktisk redigerbare, da 1939-ankre selv mangler `record_key`. Forventet **~250 af 1733**
(34 % → ~48 %). De resterende kræver enten 1939-identitet eller den udvidede ekstraktionskontrakt.

## Afgrænsning

- **1939-ægtefæller (296 af de 627) bliver stadig blokerede.** Deres ankerperson er en
  1939-hovedpost, som selv mangler `record_key` — se `docs/decisions.md` → "1939-posternes
  permanente løbenummer". Denne plan gør dem **klar**; de bliver først redigerbare når 1939 får
  identitet. Reelt frigiver planen alene **331 personer** (2018-20's ægtefæller).
- De 27 unioner med kun én registreret part er ikke omfattet — de har ingen ægtefælle at forankre.
- De 10 familier hvor begge parter har bogpost har allerede hver sit anker og skal ikke røres.

## Åbne forbehold

- Om `ordinal` er stabil på tværs af en **genindlæsning** er ikke undersøgt. Tildeles den af
  loaderen ud fra rækkefølgen i artefaktet, arver nøglen samme skrøbelighed som 1939's løbenumre.
  Det skal afklares før backfill — ellers bygger vi det problem vi netop har besluttet at undgå.
- Antallet af kollisioner (10) er målt på det nuværende korpus. Det ændrer sig hvis flere
  spøgelses-unioner ryddes op undervejs.
