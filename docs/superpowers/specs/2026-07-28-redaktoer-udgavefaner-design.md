# Redaktørens personliste og udgave-faner — design

**Dato:** 2026-07-28 · **Status:** design godkendt, ikke implementeret

## Problemet

Samme person findes nu i flere DAA-udgaver, og redaktørens personliste viser én post pr.
databaserække. Et matchet par optræder derfor som to poster der ser ens ud — og med flere slægter
på vej bliver listen uoverskuelig.

Brugerens observation: folder man de *allerede matchede* sammen, står de **umatchede** tilbage som
to ens linjer ved siden af hinanden. Sammenfoldningen rydder op *og* gør det udestående arbejde
synligt i samme greb.

## Del 1 — Sammenfoldning i sidebar-listen

Gælder sidebar-listen under **Personer** (navigations-listen), ikke kvalitetsarket. Kvalitetsarket
har sit eget, bevidste valg om at vise begge rækker (`PersonKvalitetsark.tsx`), og det står ved magt.

**Én post pr. kanonisk gruppe**, med et mærke der viser antal udgaver:

```
Reventlow, Christian Ditlev   1748-1827   [2 udg.]      ← matchet, foldet
Reventlow, Christian Ditlev   1748-1827                 ← ikke matchet endnu
Reventlow, Christian Ditlev   1748-1827                 ←   (to ens = arbejde at gøre)
Reventlow, Conrad             1644-1708   [⚠ karantæne] ← markeret, men blokeret
```

**Sorteringen ændres ikke.** Alfabetisk som i dag — det er netop dét der får to umatchede til at
lande ved siden af hinanden.

### Karantænerede grupper foldes ikke

`collapseSameAs` sætter i dag **238 grupper** i karantæne (konkurrerende forældre). De foldes ikke
for læseren. Foldede redaktøren dem alligevel, ville redaktionen vise én person hvor hjemmesiden
viser to — og divergensen ville aldrig blive opdaget. De vises derfor som separate poster med et
advarselsmærke.

Konsekvens: sammenfoldningen skal bruge **samme** `collapseSameAs` som læseren, ikke en
genimplementering. Jf. `docs/decisions.md` om skrive- kontra læse-id-rum.

### Datagrundlag

`fetchRedaktionPersoner` udvides med to ting den ikke henter i dag:

- `samme_som`-kanterne (til `collapseSameAs`)
- udgave-tilhør pr. person (`person_external_id.source_id`), med ægtefælle-arv via den
  eksisterende `udledKilderForAegtefaeller`

**Forbehold:** de 627 gift-ind-ægtefæller har ingen bogpost og får kun et udgave-mærke ved at arve
partnerens. Det gør mærket til en *udledning*, ikke en aflæsning, og skal fremgå visuelt (parentes
eller kursiv) — ellers ser det ud som om bogen har givet dem et opslag.

**Navnet vises råt.** Redaktionen omskriver aldrig bogens påstand; kun mærket er tilføjet. Samme
princip som efternavns-badget (`RedPerson.efternavnAfledt`).

## Del 2 — Profilen med udgave-faner

```
[ Konklusion ]  [ DAA 2018-20 ]  [ DAA 1939 ]
```

Fanerne genereres af hvilke kilder gruppen faktisk har evidens i — ikke en fast liste.

### Hvorfor "Konklusion" er en selvstændig fane

Datamodellen har to lag: uforanderlige **påstande** pr. kilde, og én foranderlig **konklusion**
ovenpå. Fanestrukturen gør de to lag synlige.

Alternativet — kun udgave-faner, hvor den valgte værdi markeres — bryder sammen når konklusionen er
en værdi **ingen** udgave påstår. Den har da ingen fane at bo i, og at vise den under "DAA 1939"
ville hævde at bogen siger noget den ikke siger. Man ender med en "Redaktionelt"-fane, som *er*
konklusions-fanen i forklædning.

### Konklusions-fanen

Øverst en **"Uenigheder"-sektion** med kun de felter hvor udgaverne siger noget forskelligt — de
eneste der kræver en beslutning. Resten vises nedenfor med proveniens pr. felt.

```
Uenigheder (1)
  Død    ○ 11. okt. 1827    DAA 2018-20
         ● 11. Oktbr. 1827  DAA 1939      ← valgt

Øvrige felter
  Navn   Christian Ditlev Reventlow   fra DAA 2018-20
  Født   1748                         fra begge (enige)
```

### Udgave-fanerne

Read-only visning af den udgaves påstande, med én handling: **"Ret transskription"**. Den hører
hjemme her, fordi den ændrer *hvad vi mener bogen siger*.

### To redaktionelle handlinger, to steder

Den nuværende flade blander dem sammen. De skal skilles ad:

| Handling | Hvor | RPC | Findes |
|---|---|---|---|
| "Bogen siger faktisk X" (transskription) | udgave-fanen | `red_ret_ocr_felt` (anker: `import_key`+`record_key`) | ✅ |
| "Vi vælger 1939's værdi" | konklusions-fanen | `red_set_konklusion(assertion_id)` | ✅ |
| "Vi konkluderer noget ingen bog siger" | konklusions-fanen | `red_edit_oplysning` (append: bevarer gammel påstand, re-peger konklusion i ét `change_set`) | ✅ |

**Ingen ny skrivevej skal bygges** — det er en ny sammensætning af eksisterende operationer.
Fortrydelse, `change_set`-historik og rollback virker derfor uændret.

⚠ **Spærre at respektere:** konklusioner på `forældrefamilie` afvises eksplicit af
`red_set_konklusion` og skal gå gennem `red_vaelg_foraeldre`, som bevarer forældre-projektionen
(invariant P1).

### Værnet mod den største risiko

Risikoen ved en konklusions-fane er at redaktøren *bor* i den og retter OCR-fejl derfra. Så forbliver
bogens transskription forkert, og fejlen genopstår ved næste indlæsning eller matchning.

Når en redigeret konklusionsværdi afviger fra den valgte kildes påstand, spørges der:

> **Er det bogen der er fejllæst, eller vælger du en anden værdi?**
> ○ Bogen siger faktisk dette → retter transskriptionen i den valgte udgave
> ○ Jeg vælger en anden værdi end bogens → ny konklusion, bogen står uændret

Det ene dialogvalg **er** adskillelsen af de to handlinger i praksis.

### Oprydning: narrativ-fanerne smelter ind

Narrativet har allerede udgave-faner i redaktørfladen, med egen tilstand. De foldes ind i den nye
struktur frem for at ligge som en anden, parallel fane-række — ellers har profilen to sæt
udgave-faner der kan pege forskellige steder hen.

## Del 3 — 1939: læsbar og anvendelig, ikke korrigerbar

`red_set_konklusion` tager **kun et assertion-id** og har intet ankerkrav. Derfor:

| Med 1939 | |
|---|---|
| Se hvad bogen siger | ✅ |
| Vælge 1939's oplysning som gældende | ✅ |
| Rette transskriptionen | ❌ intet `record_key` |

1939's evidens er altså fuldt **anvendelig**, bare ikke **korrigerbar**. Se
`docs/decisions.md` → "1939-posternes permanente løbenummer" for hvorfor nøglen bevidst ikke er sat
endnu, og i hvilken rækkefølge det bør tages op.

**"Ret transskription" vises deaktiveret med begrundelse — ikke skjult.** Skjules den, ser
1939-fanen ud som om alt er i orden. Samme gælder de 627 gift-ind-ægtefæller (`ingen_importanker`).

## Fejltilstande der skal siges ligeud

- **Karantæneret gruppe** → "markeret som samme person, men foldes ikke sammen — konkurrerende
  forældre". Ellers ser redaktøren én person hvor læseren ser to.
- **Felt uden konklusion** (påstande findes, intet valg truffet) → vis som *uafklaret*, ikke tomt.
  `red_set_konklusion` upserter netop for at undgå tavs no-op her.
- **Felt uden evidens i fanen** → "ingen oplysning i denne udgave", forskelligt fra "udgaven siger
  tom".

## Test

Rene funktioner i `@daa/core`, testet uden DB:

- sammenfoldning til listeposter — inkl. at karantænerede **ikke** foldes
- udregning af "uenigheder": hvilke felter er udgaverne faktisk uenige om
- disambiguerings-reglen: afviger den nye værdi fra den valgte kildes påstand?

Plus én regressionstest der fastholder featurens egen målsætning: **et umatchet par skal blive ved
med at stå som to poster.** Det er let at bryde ved et uheld senere.

## Uden for denne opgave

- **`record_key` til 1939** — forudsætning for redigerbarhed. Egen beslutning, se `decisions.md`.
- **De 627 ægtefællers redigerbarhed** — egen plan (forælderens `record_key` + indeks i
  `aegteskaber`; `linje` SKAL være NULL, ellers påhæfter `regen_person_visning()` slægtsnavnet til
  indgifte).
- **B1, nøglerummet** — to slægters "Linje I" i samme udgave. Se
  `docs/reviews/flerslaegt-parathed-2026-07-28.md`.

## Hvornår er to udgaver "uenige" om en dato? (målt 2026-07-28)

Brugerfund: datoerne er skrevet forskelligt i de to bøger, så en naiv sammenligning ville flage
næsten alle personer. Målt på de matchede par i prod:

| | fødsel | død |
|---|---|---|
| Sammenlignelige par | 354 | 307 |
| Rå tekst ens | 14 (4 %) | 18 (5 %) |
| Parsede datoer *identiske* | 73 | 59 |
| **Parsede datoer forskellige** | **281 (79 %)** | **248 (81 %)** |

En sammenligning på rå tekst er altså ubrugelig — men **en sammenligning på parsede datoer er det
også.** Det var det overraskende. Årsagen viser sig når man spørger *hvordan* de er forskellige:

| | fødsel | død |
|---|---|---|
| Identiske intervaller | 73 | 59 |
| **Det ene interval indeholder det andet** | **277** | **235** |
| Delvist overlap uden indeholdelse | **0** | **0** |
| **Disjunkte (ægte uenighed)** | **4** | **12** |

**Bøgerne er næsten aldrig uenige — de er forskelligt præcise.** I 99 % (fødsel) og 96 % (død) af
parrene indeholder det ene interval det andet: den ene bog skriver `1748`, den anden
`11. okt. 1748`. Det er ikke to påstande der strider mod hinanden; det er en grov og en fin.

Og taksonomien er ren: **delvist overlap uden indeholdelse forekommer nul gange.** Hvert par er
enten identisk, indeholdende eller disjunkt.

### Reglen

| Forhold | Betydning | Hvad UI'et gør |
|---|---|---|
| Identiske intervaller | Enige | Vis som enige. Ingen handling. |
| Ét interval indeholder det andet | Enige, forskellig præcision | Vis den **fineste** som konklusion. Ingen handling; præcisionen kan ses i udgave-fanen. |
| Disjunkte intervaller | **Ægte uenighed** | Hør til i "Uenigheder". Kræver beslutning. |

Sammenligning sker på `date_min`/`date_max`, **aldrig** på `date_raw`. Rå tekst bevares som
proveniens og vises i udgave-fanen, men bruges ikke til at afgøre enighed.

**Konsekvens for "Uenigheder"-sektionen:** den ville i dag indeholde **16 felter i alt** på tværs af
alle 429 matchede par — ikke ~660. Det er en liste man kan gennemgå, hvilket var hele formålet.

**Åbent til planen:** samme spørgsmål for ikke-dato-felter (navn, titel, sted). Der findes ingen
normaliseret form at sammenligne på, og `matchKey`-foldningen er bygget til scoring, ikke til at
afgøre enighed. Kandidat: vis som "forskellig skrivemåde" frem for "uenighed", medmindre der findes
et bedre grundlag.

## Åbne forbehold

- Antallet af karantænerede grupper (238) er målt 2026-07-28 og falder i takt med matcharbejdet.
  Designet afhænger ikke af tallet, kun af at tilstanden findes.
- Dato-målingen er lavet på personer der **allerede er matchet**. Par hvor datoerne var åbenlyst
  uforenelige blev formentlig aldrig til par, så andelen af ægte uenigheder er sandsynligvis
  underestimeret. Reglen påvirkes ikke — kun forventningen til hvor lang listen bliver.
