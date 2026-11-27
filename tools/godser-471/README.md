# Godser #471, fase 1: forslagsark og plan

Foreslår, hvordan de 430 rækker i `estate` skal ryddes op i gårde og majorater (grevskab, baroni, stamhus), jf.
`docs/decisions.md` »BESLUTTET: godserne ryddes op i to niveauer — majorat og gård (#471, 2026-11-26)«.
Værktøjet ændrer intet i databasen. Det skriver et HTML-ark til projektejeren og en plan-fil, som Task 10
(`R/godser-fase1.R`) udfører, når projektejeren har svaret.

## Kørsel

```bash
python3 -I tools/godser-471/forslag.py \
  --db <prod-kopi på standard-socket'en> \
  --ark <sti UDEN FOR repo'et>/471-forslagsark.html \
  --plan tools/godser-471/plan.forslag.json
```

- Læser kun: værktøjet sætter selv `PGOPTIONS='-c default_transaction_read_only=on'` og stopper, hvis
  `transaction_read_only` ikke er `on`. Forbindelsen følger ellers `PGHOST`/`PGPORT` fra miljøet.
- `--ark` inde i repo'et afvises.
- `kilde_hash` (estate + gods-relationer) beregnes med præcis samme SQL som målingen af prod; sammenlign med prod,
  før arket vises.
- Udskriver optællingen (grupper, sammenlægninger, nye gårde, kopier, spørgsmål) som JSON.

Tests (uden database): `/usr/bin/python3 -m pytest tools/godser-471/test_forslag.py`.

## Persondata

Værktøjet læser aldrig personnavne. Det eneste opslag i `person` er `levende`-flaget (`SQL_LEVENDE_EJER`), og det
returnerer kun gods-id'er; en test sikrer, at ingen anden forespørgsel rører `person`. Har et gods med fritekst i
navnet (parentes, »af«, »til« …) en levende ejer, stopper værktøjet, så en nulevendes navn ikke ender i et citat.
Arket og planen indeholder gods-, relations- og medie-id'er, godsnavne, perioder og udgaver — aldrig hvem.

## Sådan dannes forslaget

1. **Nøgle** pr. række: navnet uden parentes, `[…]`, »til« foran/bagved og formord, med små bogstaver og uden
   bindestreg og mellemrum; formordet (grevskab/baroni/stamhus, også bestemt form og flertal) giver arten.
   Gårde og majorater med samme navn er hver sin nøgle (`gård:christianssæde` ≠ `grevskab:christianssæde`).
2. **»X med Y, Z«**: rækken hører til X's gruppe, og hvert ejerforhold kopieres til Y og Z (eksisterende gruppe
   eller ny gård, `ny:<navn>`). »med landsbyerne …« og »sammen med …« giver ingen kopi (flages).
   **»Grevskaberne X og Y«** giver tilsvarende en kopi til majoratet Y. **»X og Y«** (uden »med«) er sin egen
   gruppe med valget »del op« / »behold« — aldrig forvalgt.
3. **Navneskift** i parentesen (»fra 1741 Christianssæde«, »senere Ditlevslyst«) samler gruppen med det nye navns.
4. **Den række, der bliver stående**: rækken med et slettet ejerforhold i `change_event` (den må aldrig lægges
   sammen væk); ellers en række med ejerforhold fra DAA 2018-20, med sted, med rent navn, med flest koblinger.
   **Navnet** er den nyeste udgaves form (2018-20 før 1939), uden parentes; majoratet får formordet med stort
   (»Grevskabet Christianssæde«). Ingen automatisk aa→å.
5. **Billeder af bygninger** (`media.slags='gods'`) på et majorat flyttes til gården, når titlen nævner en gård,
   der findes som række.
6. **Spørgsmål** uden forvalg:
   - **H** (hører under): majorat og gård med samme (eller lignende) navn. Godsnavnene siger aldrig selv
     »hører under«, så svaret kræver periode, udgave og bogens ord. Undtagelse: Vallø, hvor billedets overskrift
     (»… 1713-1730 hovedsæde i grevskabet Vallø«) er bogens ord. **Krenkerup-mønstret** (gårdens ejerperioder ligger
     inden for majoratets) giver valget »flyt ejerforholdet til majoratet«.
   - **S** (ligner hinanden): grupper, hvis navne er ens efter en grov stavefoldning eller kun adskiller sig ved en
     stedtilføjelse (»ved Slesvig«, », Galten Herred«), samlet i sammenhængende klynger.
7. **Tvivl = intet forvalg**: forskellige steder (sogn), flere rækker med slettede ejerforhold, navne der ikke
   tyder på en gård (len, herred, sogn, fogderi, birk, palæ, hus, kongsgård, kloster, forlening, »o.s.v.« …),
   lister med mærkelige led, kopimål der kun ligner en eksisterende gård, billeder med en anden gårds titel.

## Arket: projektejeren svarer i browseren

Arket er én lokal HTML-fil (ingen netværk, ingen CDN). Hvert kort har radioknapper:

- »Du skal vælge« (grupper uden forvalg, alle S- og H-spørgsmål) har intet valgt på forhånd.
- »Forslag« har forslaget valgt, men det kan ændres.
- Enkle rækker har kun et »ret«, når der findes et alternativ.

H-»ja« kræver udgave og bogens ord; perioden er forudfyldt, hvor værktøjet har den. Standardvisningen viser kun
det, der skal besvares. Der er filtre (Skal afgøres/Forslag/Enkle/Alle), søgning, en fremdriftslinje og taster
(`n` næste ubesvarede, `j`/`k` næste/forrige, `1`-`9` vælger svar). Knappen »Alle ubesvarede S-spørgsmål: nej«
spørger først.

Svarene gemmes i browseren (localStorage, nøglet på `kilde_hash` + planens sha256). »Gem svar« henter
`471-svar.json`, og »Kopiér svar« kopierer samme JSON:

```json
{"version": 1, "kilde_hash": {...}, "plan_forslag_sha256": "...",
 "svar": {"G12": "C", "S3": "nej", "H2": {"svar": "ja", "periode": "1729-1924", "citat": "…", "kilde": 1}}}
```

Svaret indeholder kun besvarede poster og ændrede forslag; uændrede forslag er accepteret.

## Fletning til plan.json (fail-closed)

```bash
python3 -I tools/godser-471/forslag.py --flet 471-svar.json --plan-ud tools/godser-471/plan.json
```

Fletningen læser `plan.forslag.json` (standard: ved siden af værktøjet; ellers `--plan`) og svarfilen. Den afviser
– og skriver intet – ved:

- ukendte nøgler eller poster;
- forkert `kilde_hash` eller sha256 af `plan.forslag.json`;
- manglende svar på en åben post;
- ugyldige valg;
- H-»ja« uden udgave eller citat;
- et S-»ja«, hvor en af grupperne er valgt »behold rækkerne adskilt«;
- en række, der lægges sammen to steder eller får to navne;
- en plan, som `valider_plan` afviser.

Et S-»ja« erstatter de øvrige gruppers egne sammenlægninger og navne, og alle mål (kopier, flytninger, »hører
under«), der pegede på deres rækker, peger om på den første gruppes række. Værktøjet udskriver et dansk resumé
(antal pr. operation mod forslaget, ændrede forslag) og planens sha256 til hash-bindingen.

## Plan-filen

`plan.forslag.json` har Task 10's format (`version`, `kilde_db`, `kilde_hash`, `opret`, `saet`, `sammenlaeg`,
`kopier`, `hoerer_under`, `flyt`) med **kun de forvalgte** operationer, plus:

- `gruppe` på hver operation;
- `aabne`: grupper og spørgsmål uden forvalg (de står ikke i operationslisterne);
- `forvalg`: det valgte alternativ pr. gruppe;
- `alternativer`: alle alternativer pr. gruppe/spørgsmål med tekst og operationer.

Post-id'er er `G<nr>`, `S<n>` og `H<n>` (i `aabne`, `forvalg`, `alternativer`, `poster`); operationernes `gruppe`
er gruppenummeret (tal) eller `S…`/`H…`. `poster` beskriver gruppernes rækker og overlevende række og S/H-spørgsmålenes
grupper; `snapshots` er rækkerne med slettede ejerforhold. Den endelige `plan.json` laves med `--flet` (ovenfor) og
har kun operationerne plus `grundlag` (sha256 af forslaget og svaret).

`opret` slår Task 10 op på navn + art; `saet` sender altid `slags` (NULL = »art ukendt«, ikke »uændret«).
