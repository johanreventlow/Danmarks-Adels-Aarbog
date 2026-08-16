# 1939: særskilte kildeposter for hierarkiske henvisninger

## Formål

Fem menneskeligt godkendte generationshenvisninger skal bevares i den
hashbundne 1939-kilde uden at være en del af en persons narrative tekst og uden
at kunne oprette personer:

| Bogside | Henvisning | Calamari-spænd |
|---|---|---|
| 500 | `Sønner: V` | `11945..11955` |
| 512 | `Børn: Tredje Slægtled I.` | `38259..38284` |
| 512 | `Døtre: Tredje\nSlægtled II.` | `38949..38977` |
| 513 | `Børn: Tredje Slægtled III.` | `39498..39526` |
| 528 | `Børn: Tredje Slægtled.` | `67129..67153` |

Spændene er koordinater i den eksisterende Calamari-rendition med SHA-256
`020123a3588dacf80705a22fb021ab4f5da97b8de202e8664304ca01f9a6da37`.

## Valgt model

Hver henvisning materialiseres som en selvstændig source record med:

- `record_kind: "structural_context"`;
- det eksakte verbatim-spænd;
- accepteret menneskelig provenance;
- `person_creation: "forbidden"` i den afledte afstemningsannotation.

Henvisningen er dermed auditerbar og kan senere bruges til hierarkisk
relationstolkning, men den er ikke en source persona og kan ikke blive en
kanonisk person uden ny, særskilt evidens.

## Grænsegeometri

Der genereres en ny, afledt grænseeksport; den eksisterende eksport overskrives
ikke. Den afledte eksport bindes til originalens SHA-256
`5fca128211319594cef4b0a3d9d91376486474d79dbb1cac602af6641e0e11da`
og beslutningsbatchen; drift af originalen afviser genereringen. Eksporten
tilføjer et valgfrit topniveaufelt
`strukturelle_henvisninger`, hvis poster har `char_from`, `char_to`,
`record_kind: "structural_context"` og
`person_creation: "forbidden"`.

Den afledte geometri foretager kun disse ændringer:

1. Ny skæring ved `11945`, så Henriks personpost slutter før `Sønner: V`.
2. De fire eksisterende udeladelser `38259..38284`, `38949..38977`,
   `39498..39526` og `67129..67153` fjernes.
3. De fire gamle slutskæringer `38283`, `38976`, `39525` og `67152` erstattes
   med skæringer ved begge ender af de godkendte strukturelle spænd.
4. `11945..11955` afgrænses af den nye og den allerede eksisterende skæring.

Alle andre skæringer, udeladelser, sider og kildetekst forbliver byte-identiske.
Det eksisterende ændringsregnskab bevares som historik; den afledte ændring får
sin egen eksplicitte batchproveniens frem for at omskrive de gamle tællere.

## Materialisering

Materialiseringen validerer `strukturelle_henvisninger` fail-closed:

- spændene skal være positive, unikke, sorterede og uden overlap;
- de må ikke overlappe udeladelser;
- hvert spænd skal svare præcist til ét effektivt cut-interval og én
  materialiseret record;
- recorden får `record_kind: "structural_context"` i stedet for
  `unclassified`;
- manglende, delvise eller ekstra strukturelle spænd giver `NO-GO`/fejl uden
  output;
- ældre eksporter uden feltet betyder nul structural-context-poster.

Rapporten får tælleren `structural_record_candidates`.

## Ledger og afstemning

Ledgeren er fortsat append-only. Uændrede acceptance-id'er genbruger deres
record keys; fem nye structural-context-poster og den forkortede Henrik-post
får nye nøgler. Den tidligere, længere Henrik-acceptance bliver stående som
historisk ledgerpost, men er ikke aktiv i den nye materialisering.

Afstemningen skal derfor kræve, at alle aktive acceptance-id'er findes i
ledgeren, men må acceptere historiske ledgerposter, som ikke er aktive i den
aktuelle materialisering. Historiske poster må hverken blive nye entries eller
ejere i den aktuelle afstemning.

Efter genmaterialisering bygges afstemningen på ny fra den oprindelige baseline.
Alle tidligere menneskelige afgørelser genvalideres mod den nye, eksakte
geometri; ingen afgørelse genbruges alene på navn eller rækkefølge.

## Fejltilstande og afgrænsning

Hele processen afvises uden delvise output ved kildedrift, ukendt spænd,
overlap, manglende cut-afgrænsning, forkert record kind, ledgerdrift eller
ufuldstændig genvalidering af tidligere beslutninger.

Arbejdet ændrer ikke databasen, personidentiteter, facts, familieforbindelser
eller identitetsregister. Det klargør alene korrekt og tabsfri kildegeometri.

## Testkrav

Testene skal bevise:

1. alle fem henvisninger bliver separate structural-context-records;
2. personspændene slutter før henvisningerne;
3. structural-context-spænd kan ikke være udeladelser eller delintervaller;
4. ældre eksporter uden feltet fortsat materialiseres uændret;
5. en append-only ledger med historiske entries accepteres, mens manglende
   aktive entries afvises;
6. uændrede records beholder nøgler, mens ny Henrik-geometri og de fem nye
   records får nye nøgler;
7. fuld materialisering og afstemning er deterministisk og bevarer et komplet
   regnskab over accepterede, strukturelle og udeladte Calamari-intervaller;
8. hver structural-context-record eksplicit forbyder personoprettelse i den
   menneskeligt godkendte afstemning.
