# DAA 1939 v50 — fase C0: kandidatrapport

**Dato:** 2026-08-19 · **Status:** afventer brugerens afgørelser
**Plan:** `docs/superpowers/plans/2026-08-19-1939-v50-fase-c0-record-kobling.md`
**Spec:** `docs/superpowers/specs/2026-08-19-1939-v50-fase-c0-record-kobling-design.md`

**Intet er skrevet til produktionsdatabasen.** Den eneste prod-kontakt er en
read-only `SELECT` (Task 1). Der er ikke bygget noget manifest, ikke kaldt
nogen RPC og ikke autoriseret nogen skrivning.

## Input (SHA-256)

| Artefakt | SHA-256 |
|---|---|
| `import-preview-v1.json` | `04f2780b4fc3f63263324cbb5133e07d1eed70018f7ea11212597a26cc196ca5` |
| `database-preview-v1.json` | `a00efd43a34358f95f4b0df40695f4abd3b279066bee196e3cbdbd1b87b9e97c` |
| `boundary-materialization-v3-ditlev.json` | `73aa0eecb365de35b8e5ca38af87c7b247fbdd7d14e2ece358d86e4680056b4f` |
| `full_ocr_calamari_r6_clean.txt` | `020123a3588dacf80705a22fb021ab4f5da97b8de202e8664304ca01f9a6da37` |
| `production-write-manifest-v1.json` | `8417b6deeaf32b3cf39a4f2995a06211f8368172dfa97a188e03c6f7ef379a1f` |
| `narrative-state-v1.json` (frisk prod-eksport) | `857ff49a52b4f42a9f9fd574048f5273de81a7e374cca50df925a35eeaa1e0b0` |
| **`linkage-candidates-v1.json`** (output) | `2b2235fe21e22063366fb3de79d446bffd2147d5dfd27223ec0ea1534dcbd3b0` |
| **`c0-afgoerelser.txt`** (til brugeren) | `cf99735b0ca6629fb0703c18406d505b1f68182cfbc37e083df20fc56d8c23f3` |

De fem første er hash-låst i koden. Filnavne-versionering
(`source-record-reconciliation-v33` … `-v49`) er **ikke** en ordning og må
ikke bruges til at vælge input — strømmen hedder v50, mens filerne hedder
v33-v49.

## Klassefordeling (41 records)

| Klasse | Antal | Udfyldt token |
|---|---|---|
| Foreslået kobling | 9 | `[KOBL]` |
| Kræver stillingtagen | 1 | `[SPØRG]` |
| For kort til at matche | 5 | `[SPØRG]` |
| Sammenlægning (→ C3) | 7 | `[C3]` |
| Ingen kandidat | 11 | `[NY]` |
| Allerede færdig | 8 | `[FÆRDIG]` |

## Lukning begge veje

**Personer med gammel tekst: 26** (ikke 23 — se proxy-verifikationen nedenfor)

- forklaret: 17
- løst i C0: 9
- udskudt til C3: 8
- **uforklaret: 9** → `933, 934, 935, 940, 991, 1135, 1791, 1795, 1802`
  - heraf berørt af en for kort record: `991`

**`database_only` (preview 2026-08-17): 23** — heraf uforklaret 6:
`933, 934, 935, 940, 991, 1135`

De 9 uforklarede er fasens vigtigste fund og må ikke rundes væk. De hænger
sandsynligvis sammen med de 11 `aegte_ny`-records: **alle 11 har dækning
0.00**, altså ingen tekstlighed overhovedet med noget i prod. Flere af dem
er lange, indholdsrige personposter (Hr. Henrik, Hr. Iven, Hr. Claus,
s. 498-499), mens flere af de uforklarede personer bærer ødelagte
fragment-tekster fra gamle grænsefejl. Hypotesen er at de er hinandens
modstykker — men teksten er så beskadiget, at ingen maskinel sammenligning
kan bevise det. Det er en redaktionel opgave, ikke en tærskeljustering.

## Proxy-verifikation (planens Task 1, step 6b)

Prod-eksporten: **577 narrativer**, 551 med publiceret record-binding,
**26 uden**. Sættet uden binding er et **supersæt** af den empiriske
gammel-tekst-liste fra 2026-08-19 (23 personer): alle 23 er med, plus
`991`, `1791` og `1795`.

Alle tre ekstra er fragmenter fra gamle grænsefejl:

- **1791** har midt-i-sætning-navn (`"fyenske Rytterreg.)"`) og tekst der
  begynder inde i en parentes.
- **1795** er navnløs, 22 tegn: `"M. (S) t 4 April 1837."`
- **991** er `"I1. Hr. Iven til Rixdorf † 1569."` — ordret identisk med
  record `d790ab87` blandt de 41.

Den empiriske liste var altså ufuldstændig; binding-proxyen bruges som
gammel-tekst-sæt. Havde vi stolet på den empiriske liste, ville tre
personer være faldet ud af fasen ubemærket.

## Gates

Fire gates, alle grønne uden at ankre eller grænser blev justeret:

1. **Positivt anker** — record `82f49e95…` → person 1299 klassificeres
   `kobling` (dækning 1.00). Beviser at tærsklerne ikke er for stramme.
2. **Negativt anker** — record `4ba8b3b2…` klassificeres `aegte_ny`.
   Valgt empirisk efter første kørsel: den er en ren strukturel
   overgangstekst (»Fra ovennævnte Joachim Reventlow til Rixdorf nedstammer
   den yngre holstenske Linje … uddøde i Mandsstammen 1783«) og handler om
   en linje, ikke om én person. Beviser at tærsklerne ikke er for løse.
3. **Ingen person hævdet to gange** — ingen to records peger på samme
   person som topkandidat.
4. **Fordelingsalarm** — antal koblinger under grænsen på 25.

Output er byte-identisk under tre `PYTHONHASHSEED`-værdier. 67 pytest-tests
+ 9 R-assertions grønne.

## To fejl fanget undervejs — begge i C0's eget værktøj

**1. Længde-asymmetri, begge veje.** Første udkast målte tekstlighed med
`SequenceMatcher.ratio()`, som er symmetrisk. En 400-tegns record der
ligger *perfekt* inde i et langt narrativ scorer målt **0.015** — en ægte
match ville være blevet stemplet »ægte ny« uden flag. Skiftet til
`coverage = matchede tegn / min(længde)` løste det og genskabte fejlen
spejlvendt: korte modparter blev promiskuøse (person 1149 »Henrich«, 10
skelettegn, fik dækning 1.00 mod kalibreringsrecorden, fordi de ti
bogstaver findes *spredt* i 502 tegn). **Kalibreringsgaten fangede det på
første ægte kørsel.** Rettelsen er et krav om ét *sammenhængende* anker
(længste blok ≥ min(40, 80 % af korteste)), som skar
kalibreringsrecordens 60 kandidater ned til den ene rigtige.

**2. Otte records var allerede færdigbehandlede.** Import-preview er fra
2026-08-17, altså **før** task 25 oprettede personerne 1846-1853. Syv af de
oprindelige 16 koblingsforslag pegede på netop de personer, og en ottende
(`4. Margrethe.`) stod som `for_kort`. En kobling ville have kollideret med
den UNIQUE binding, deres narrativ allerede har. De har nu deres egen
klasse, `allerede_materialiseret`, som slår tekstsignalet — det er et
faktum om databasen, ikke en vurdering af lighed. Konverteren afviser
`[KOBL]` på dem.

## Afgørelser truffet 2026-08-19

Alle 41 er afgjort. **0 uafklarede.**

| Udfald | Antal |
|---|---|
| `[KOBL]` | 10 |
| `[NY]` | 16 |
| `[C3]` | 7 |
| `[FÆRDIG]` | 8 |

Beslutningsfil: `c0-afgoerelser.txt` (`e7458bf1…`) →
`c0-afgoerelser.json` (`9b702544…`).

De seks poster, der stod som `[SPØRG]`, blev afgjort ved at læse kildens og
databasens tekst side om side (`c0-tekster-side-om-side.txt`):

- **R37 → `[KOBL]` (person 991).** Kildens `I1. Hr. Iven til Rixdorf †
  1569.` er tegn for tegn identisk med prods tekst. Posten er kort, men
  identiteten er ikke i tvivl — netop derfor tillader konverteren `[KOBL]`
  på en for kort post med præcis én kandidat.
- **R08, R14, R25, R36 → `[NY]`.** Fire korte oversigtslinjer (`I. Ditlev
  † 1536, Biskop i Lübeck.`, `A. Henning til Hemmelmark († 1705), Fader
  til:`) uden nogen kandidat i basen. Samme slags som det negative anker:
  strukturelle punkter i stamtavlen, ikke personposter.
- **R10 → `[NY]`.** Kilden handler om Storkansler Conrad Reventlows søn
  (1700-tallet); kandidaten person 1291 er født **1864**. De 0.60 dækning
  stammer alene fra de fælles godsnavne (Reventlow, Christianssæde,
  Brahe-Trolleborg). Ikke samme person.

Effekt på lukningen: person 991 løses nu af R37, så de uforklarede går fra
9 til **8** (933, 934, 935, 940, 1135, 1791, 1795, 1802).

### R40 ændrer person 1017's viste biografi

Koblingen R40 → person 1017 er mere end en binding. Kilden består af to
afsnit, A) og B), som er to selvstændige records (R40 og R15). I basen er
begge havnet i ét for stort narrativ på 1017, mens person 1021 kun har en
afskåret stump, der begynder midt i ordet »Reventlow« — en gammel
grænsefejl.

Fase B-efterkørslen vil derfor **erstatte 1017's tekst med A) alene**.
Det er en reparation, men det fjerner synligt indhold fra biografien;
B)-delen hører til 1021 og følger med R15 i C3. Det skal stå i
efterkørslens GO-pakke, så tekstændringen ikke ser ud som et tab.

## Til brugeren

Beslutningsfilen er `work/task26-1939-v50-c0-record-linkage/c0-afgoerelser.txt`
— 41 linjer, mistænkelige øverst, anbefaling udfyldt. Ret kun tokenet i den
firkantede parentes; alt andet er byte-låst og verificeres ved indlæsning.

Tokens: `[KOBL]` · `[NY]` · `[C3]` · `[SPØRG]` · `[FÆRDIG]`

### Hvor `[SPØRG]` fører hen

Seks records har `[SPØRG]` udfyldt (1 stillingtagen + 5 for korte). De er
bevidst **ikke-terminale**: de bliver ikke til en skrivning, men til en
samtale. Konkret bliver de en kort opfølgningsrunde, hvor vi ser på
recordens fulde tekst mod kildesiden sammen — fem af dem er så korte
(»4. Margrethe.«, »I. Ditlev † 1536, Biskop i Lübeck.«), at afgørelsen
kræver bogens kontekst, ikke mere maskinkraft. Ændrer du et `[SPØRG]` til
et af de andre tokens, er den terminal med det samme.

Undtagelse med vilje: `[KOBL]` **er** tilladt på en for kort post, når den
har præcis én kandidat — det gælder R37 (`I1. Hr. Iven til Rixdorf † 1569.`
→ person 991), hvor teksten er ordret identisk, og et menneske uden videre
kan se hvad værktøjet ikke tør konkludere. Har posten flere kandidater,
afviser konverteren `[KOBL]`, fordi arket ikke kan udtrykke *hvilken* der
menes, og et ja ellers tavst ville binde til den øverste støjmatch.

### Til den senere GO-pakke: to af de ni KOBL-mål er `staged`

Personerne **967** og **963** er `staged`. C0 skriver ikke, så det ændrer
intet her — men efterkørslen *skriver*, og at publicere en record-binding
på en staged persons narrativ er et synligheds-/RLS-spørgsmål, ingen har
afklaret. `staged` findes netop for at skjule umatchede poster for anonyme
læsere (invariant 8). Det skal afgøres i efterkørslens GO-pakke, ikke
opdages under tidspres.

## Hvad der ikke sker i C0

Prod-skrivningen af `[KOBL]`-afgørelserne (fase B-efterkørsel, eget
manifest, egen GO-pakke — og den skal bære fase B's to fangne fælder:
replay-værn der dækker `privat`/`side`, og skema-kvalificeret `digest()`).
Personoprettelse for `[NY]` (task 25-mønstret, egen autorisation og eget
cutover-gate). Sammenlægningerne (C3). OCR-fejl i teksten (redaktørfladen).
Publicering af staged personer (fase D) — **C0 rører tekst, ikke
synlighed.**

**Fortryd dækker ikke narrativ-bindingerne** (`narrative_record_publication`
står ikke i `version_pk_registry`). En forkert kobling kan derfor ikke
rulles tilbage ad normal vej. Det er grunden til at afgørelserne træffes
færdigt her, før noget skrives.
