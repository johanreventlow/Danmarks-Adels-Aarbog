# DAA-præsensliste: arketypisk model for udtræk

> Kontrakt for hvordan en DAA-**præsensliste** (liste over nulevende
> familiemedlemmer, fx Reventlow i DAA 2012-2014 s.360-362) parses til
> datamodellen. Anderledes end stamtavlen (se `daa-extraction-archetype.md`):
> relations-træ per gren-hoved, ingen global løbenr, OCR-støjet kilde.

## 1. Formatets struktur

```
<ROMERTAL> LINJE  /  REVENTLOW  /  <N>. GREN          ← gren-header (versaler)
  <HOVED-person, fuld inline-post>  Børn:
     a. <barn>  ... Søn:/Børn:
        1) <barnebarn>  ... Børn:
           a) <oldebarn>
  af 1. ægteskab: / af 2. ægteskab:                   ← kuld-undergruppe (småt)
  SØSTRE / SØSTER / SØSKENDE / FARFARS FARBROR  ...   ← slægtskab RELATIVT til gren-hoved (versaler)
     <kollateral slægtning + dennes efterkommere>
```

- **Gren** (`1. GREN`, `2. GREN` …) = underafdeling af en linje. Hver gren har ét
  **hoved** (proband) + efterkommere + kollaterale slægtninge.
- **Slægtskabs-sektioner** (versal-headers: `SØSTRE`, `SØSKENDE`, `FARFARS FARBROR`)
  beskriver hvordan den følgende gruppe relaterer sig til **grenens hoved**.
- **Nesting** angiver forælder→barn: `a. b. c.` → `1) 2) 3)` → `a) b) c)`; også
  `(1 (2 (3`. Undergrupper `af 1./2. ægteskab:` fordeler børn på unioner.

## 2. Person-post (inline felter)

`<titel> <Navn>, * <fødsel> i <sted> (<sogn> K.) (søn af … / F.: <forældre>),
<erhverv…>, g. [1°] <dato> i <sted> m. <ægtefælle> (F.: <ægtefælles forældre>),
* <ægtefælles fødsel>[, skilt][; 2° …]. † <død>. [<bopæl>]. Børn:`

| Element | Mål | Note |
|---|---|---|
| Titel | `fact` `titel` | Greve/Komtesse/lensgreve/Grevinde → også køn-signal |
| Navn | `fact` `navn` | rens OCR-mellemrum: "C hristian"→"Christian" |
| Køn | `person.koen` | Greve/søn→mand; Komtesse/datter→kvinde |
| `* dato i sted` | `fact` `fødsel` | OCR-tolerant; bevar rå tekst |
| `† dato` (OCR: `f`/`j`) | `fact` `død` | normalisér OCR-dagger |
| Erhverv | `fact` `erhverv` | flere tilladt (socialrådgiver, kammerherre) |
| `[bopæl]` | `fact` `bopæl` → `place` | nulevende-residens, fx "Stenstrup, Svendborg" |
| `g. [N°] … m. …` | `family` + `family_member` | ordinal fra 1°/2°; `skilt` → note/status |
| nesting (a./1)/a)) | `family_member` rolle `barn` | forælder = posten ét niveau op |
| `(søn af …)` / `(F.: …)` | note på posten | forældre/svigerforældre som tekst, ikke nye entiteter |
| slægtskabs-sektion | `relation` el. note | label relativt til gren-hoved |

## 3. Hvem bliver en person — og hvem bliver note

Spejler stamtavlens to-tier-konvention (verificeret: stamtavlen opretter gift-ind
ægtefæller som personer med `rolle='partner'`):

- **Enhver med sin EGEN post** (eget navn + fødsel/ægteskab/bopæl) bliver en
  person — uanset blod eller gift-ind. Det gælder også gift-ind-slægtninge der
  optræder under en slægtskabs-header, fx en **MOR**, en svigerforælder med egen
  post osv. Sæt `relation_til_hoved` til deres slægtskab ("mor", "søster",
  "farfars farbror", …). Drop dem ALDRIG. Blod-vs-gift-ind bæres af relationen
  (blod = `barn`-kæde via foraelder_lokal_id; gift-ind = partner/relation-label),
  ikke af om personen oprettes.
- **Kun nævnt i parentes** `(søn af …)` / `(F.: …)` (forældre/svigerforældre der
  IKKE har egen post) = tekst i `foraeldre_note`/`partner_foraeldre`, ikke person.
- **Krydsref** (`se DAA 1924`, `se DAA 1901`) = kilde-/identitetslink, ikke påstand.
- Heraldisk/historisk prosa efter listen (Reventlow-Criminil-afsnittet) = `narrative`
  på slægten, ikke person-fakta.

## 4. OCR-tolerance (kritisk — kilden er scannet/OCR'et)

Kilden har systematisk OCR-støj. Udtræk skal være robust; validering må IKKE kræve
streng verbatim-match:
- Initial-split: `C hristian`→`Christian`, `J ohan`→`Johan`, `O tto`→`Otto`.
- Dagger: `†` gengives `f`, `j`, `j23.febr.` → tolk som dødsmarkør.
- `agteskab`→`ægteskab`, `Bøm`→`Børn`, `ffiherreinde`→`friherreinde`, manglende
  mellemrum (`ogBeke`).
- Datoer normaliseres til (date_min,date_max) hvor muligt; rå tekst bevares som læst.
- **R1-reglen (dato findes ordret i prosaen) er her ADVISORY, ikke blokerende** —
  OCR gør verbatim-match upålideligt. Validering fokuserer på struktur (køn,
  forælder-links, ordinaler) frem for tegn-præcис dato-match.

## 5. Pipeline

1. `pdftotext -layout` + strip løbende sidehoved (slægtsnavn alene) + sidetal.
2. `segment_presens.py`: grov segmentering i **gren-blokke** (split på `N. GREN`),
   bærer linje/gren + slægtskabs-sektions-kontekst.
3. LLM per gren-blok → liste af personer med `lokal_id` + `foraelder_lokal_id`
   (rekonstruér træet fra nesting) + fakta + ægteskaber. Default Sonnet.
4. `validate_presens.py`: struktur-checks (køn sat, forælder-links peger på
   eksisterende lokal_id, ordinaler stiger). Dato-verbatim kun advisory.
5. `load_presens.R`: personer + fakta + forælder-barn + ægtefælle-familier,
   source = DAA-præsensliste-udgaven. `person.levende = TRUE`.
