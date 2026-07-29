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

## Er ægteskabsnummeret stabilt? — undersøgt, ja

`family_member.ordinal` findes allerede og bærer ægteskabsnummeret:

| | |
|---|---|
| `partner`-rækker | 1301 |
| med `ordinal` | 1281 |
| **uden `ordinal`** | **20** |
| værdier | 1–4 |

### Hvor tallet kommer fra

`derive_aegteskaber()` (`validate.py`) udleder det på to måder:

```python
if ord_positions:            # bogen skriver selv "1° … 2° …"
    ordinal = int(ord_str)   # bogens eget tal
else:
    running_ordinal += 1     # tælling i tekstrækkefølge
```

Af 1939-artefaktets 38 poster med flere ægteskaber bærer **10** bogens egne `1°/2°`-markører;
de øvrige 28 får tallet af tælleren.

### ⚠ Retraktion (2026-07-29)

En tidligere version af denne plan konkluderede at de 28 tællede tilfælde var
**positionsafhængige og dermed skrøbelige**, på linje med 1939's `nr` og `linje='1939'`.
**Den konklusion var forkert**, og planen skal ikke bygge på den.

Efterprøvningen:

- `segment_1939.py` klipper **sammenhængende udsnit** `(start, end)` af råteksten. Den omordner
  aldrig. Ordene står i bogens rækkefølge.
- `derive_aegteskaber(raw_text)` nulstiller `running_ordinal = 0` **pr. narrativ**, altså pr.
  person — tallet løber ikke på tværs af poster.

Tælleren reproducerer derfor **bogens egen implicitte rækkefølge**. Det stabile faktum man ville
udlede af i en "gør nummeret solidt"-øvelse *er* bogens læserækkefølge — og det er præcis dét
tælleren allerede bruger. Der er ikke noget mere stabilt at flytte den over på.

### Den reelle rest-risiko, og hvad der fanger den

`ordinal` er ikke selvstændigt skrøbelig. Den arver **én** skrøbelighed: om en `Gift`-klausul
lander i den rigtige persons narrativ. Flytter en klausul person ved en fremtidig re-ekstraktion,
er ægteskabet tilskrevet et forkert menneske — og da er nummeret det mindste af problemerne. Intet
nummereringsskema opdager det.

**Derfor: en re-ekstraktions-kontrol frem for en ny nummerering.** Efter enhver fremtidig
re-ekstraktion kontrolleres pr. ankerperson at

- antallet af ægteskaber er uændret, og
- sættet af partnernavne er uændret

sammenlignet med det der står i basen. Triller kontrollen for en person, **re-nøgles den person
ikke** (fail-closed). Det fanger den fejl der faktisk kan ske, og som ingen nummerering fanger.

### De 10 kollisioner er et dataproblem, ikke et talproblem

| Ankerpersoner med flere ægteskaber | 89 |
|---|---|
| entydige ordinaler | 79 |
| **kolliderer** (to unioner med samme eller manglende ordinal) | **10** |

Med den nye forståelse skærpes tolkningen: er bogens rækkefølge stabil, og reproducerer tælleren
den, så betyder to unioner med **samme** ordinal under én ankerperson at der er registreret **to
unioner hvor bogen beskriver ét ægteskab**. Det er spøgelses-union-mønsteret, som er ryddet op
før (`docs/changelog.md`, change_sets 3-7).

**De 10 skal derfor afgøres mod bogen som dataoprydning.** Det er fortsat planens første skridt og
dens egentlige arbejde — men det er oprydning, ikke nummerering.

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

1. **Opgør de 10 ordinal-kollisioner** og afgør hver enkelt mod bogen. Uden dette kan nøglen ikke
   sættes — en nøgle der peger på to rækker er værre end ingen nøgle, fordi rettelsen lander
   vilkårligt uden fejlmelding. Forventet årsag: to unioner registreret hvor bogen beskriver ét
   ægteskab (spøgelses-union). Altså dataoprydning.
2. **Fyld de 20 manglende `ordinal`** ud fra bogens rækkefølge.
3. **Backfill `record_key`** for de 627 — `linje` NULL, `nr` NULL.
4. **Verificér:** korpus-diff 0 forskelle · ingen ny inkonsistent `visning_efternavn` ·
   ingen række med `linje='1939'` rørt · `red_person_grid` viser 331 flere redigerbare ·
   `get_advisors(security)` uændret.
5. **Indfør re-ekstraktions-kontrollen** (antal ægteskaber + partnernavne pr. ankerperson,
   fail-closed) som en del af pipelinens gate — ikke som en engangs-kontrol.

**Gevinst:** 591 → 1218 redigerbare (34 % → 70 %).

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
