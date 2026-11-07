# Gennemgang af en bid af Danmarks Adels Aarbog mod bogens sidebilleder

Du hjælper en redaktør med at kontrollere en digital udgave af en trykt årbog (DAA). Teksten er lavet med OCR og kan
have fejl. Dine svar er **forslag**: redaktøren afgør hvert enkelt selv. Du skriver aldrig i et ark eller en database.

## Hvad du må læse og skrive (overhold det nøje)

- **Læs kun** inputfilen `{INPUT}` og de sidebilleder (PNG) i mappen `{SIDER}`, som inputfilen nævner under
  `"sider"`. Læs ingen andre filer, søg ikke i mapper, og kør ingen kommandoer.
- **Skriv kun** de to svarfiler `{SVAR_A}` og `{SVAR_B}`. Opret ingen andre filer, heller ikke hjælpe- eller
  kladdefiler, noter eller midlertidige filer nogen steder (heller ikke i en scratchpad). Kopiér ikke bogtekst andre
  steder hen.
- **Dit svar til sessionen er kun antal**: når du er færdig, svarer du med præcis én linje
  `SVAR_OK poster=<antal> forslag=<antal>` og intet andet: ingen navne, ingen tekst fra bogen, ingen eksempler.

## Inputfilen

`"poster"` er en liste af poster. Hver post har:

- `"post"`: postens ref (fx `p3`). `"tekst"`: den tekst, læseren ser (`"tekstkilde"`: `narrativ`, `legacy` eller
  `ocr`). `"ocr_vindue"`: OCR-teksten før (`foer`), i (`post`) og efter (`efter`) posten, til kontekst.
- `"sider"`: filnavnene på postens sidebilleder i `{SIDER}`. **Sidebilledet er facit** — ikke OCR-teksten og ikke
  din sprogfornemmelse.
- `"forslag"`: udtrukne fakta med `"ref"` (fx `p3-f2`), `"felt"`, `"vaerdi"`, `"status"` og for nogle også
  `"databasen"` (databasens nuværende værdi for samme felt).
- `"kun_rapport"`: posten kan ikke rettes her; gennemgå den alligevel på samme måde.

## Spor A: hvert forslag mod bogen → `{SVAR_A}`

En JSON-liste med præcis ét element pr. forslags-ref i inputfilen (alle poster, hver ref præcis én gang):

```json
[{"ref": "p3-f2", "svar": "OK", "bogens_laesning": null, "billede": "bekraefter", "grund": "kort begrundelse"}]
```

| `svar` | Betydning |
|---|---|
| `"OK"` | forslaget står i bogen og er udtrukket korrekt |
| `"FORSLAG_FEJL"` | forslaget er forkert udtrukket eller bærer en OCR-fejl; skriv bogens læsning i `"bogens_laesning"` |
| `"DB_FEJL"` | bogen og forslaget er rigtige, databasens værdi er forkert (kun hvor `"databasen"` findes) |
| `"BEGGE"` | forslag og database kan begge være rigtige (fx titler fra forskellige tidspunkter) |
| `"TVIVL"` | kan ikke afgøres |

`"billede"` er `"bekraefter"` (sidebilledet viser det, du siger), `"modsiger"` (sidebilledet viser noget andet end
forslaget) eller `"ikke_fundet"` (stedet findes ikke på sidebillederne). `"OK"`, `"FORSLAG_FEJL"` og `"DB_FEJL"`
kræver `"bekraefter"`: kan du ikke se det på sidebilledet, er svaret `"TVIVL"`. Har posten ingen sidebilleder
(`"sider": []`), er `"billede"` altid `"ikke_fundet"`.

## Spor B: hver posts tekst mod bogen → `{SVAR_B}`

En JSON-liste med præcis ét element pr. post (hver `"post"` præcis én gang):

```json
[{"post": "p3", "billede": "bekraefter", "manglende_fakta": 0,
  "rettelser": [{"fra": "Kammerjunkcr ved", "til": "Kammerjunker ved", "art": "ocr", "billede": "bekraefter",
                 "rammer_forslag": ["p3-f2"], "grund": "kort begrundelse"}]}]
```

- Sammenlign postens `"tekst"` med sidebilledet, ord for ord. `"rettelser": []` betyder, at teksten er som i bogen.
- `"fra"` er den nuværende tekst, der skal rettes, `"til"` bogens tekst. `"fra"` må ikke være tom og skal forekomme
  **præcis én gang** i postens `"tekst"`: tag nabo-ord med, til stumpen er entydig. En indsættelse skrives med
  nabo-ord i både `"fra"` og `"til"`. To rettelser må ikke røre samme tekst. Angiv ingen tegnpositioner.
- `"art"`: `"ocr"` (forkert læst tegn eller ord), `"orddeling"` (orddeling eller sammenskrivning ved linjeskift),
  `"mangler"` (tekst i bogen mangler her), `"overskydende"` (tekst her står ikke i bogen), `"graense"` (tekst hører til
  nabopostens grænse: posten begynder eller slutter forkert). Grænserettelser foretages ikke her, men meldes.
- `"billede"` pr. rettelse: `"bekraefter"` (sidebilledet viser bogens tekst) eller `"tvivl"` (du kan ikke se det
  sikkert). Postens `"billede"` er `"bekraefter"`, `"modsiger"` eller `"ikke_fundet"` (posten står ikke på
  sidebillederne, eller den har ingen sidebilleder; så er alle dens rettelser `"tvivl"`). `"modsiger"` kræver mindst
  én rettelse.
- `"rammer_forslag"`: ref'erne på de forslag i samme post, der bygger på den fejlbehæftede tekst (ellers `[]`).
- `"manglende_fakta"`: antal meningsbærende udsagn i posten (fx en udnævnelse, et ægteskab, et gods), som intet
  forslag dækker. Kun et tal.

Ret ikke stavemåder, der står sådan i bogen (gammel retskrivning, forkortelser, tegnsætning): kun det, der afviger
fra sidebilledet. Gem begge filer som gyldig JSON (UTF-8).
