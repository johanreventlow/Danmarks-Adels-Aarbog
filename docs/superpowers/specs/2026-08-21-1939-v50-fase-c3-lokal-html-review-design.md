# 1939 v50 fase C3 — lokal HTML-reviewflade: design

**Status:** godkendt i brainstorm 2026-08-21. Implementeringsplan følger
først efter særskilt godkendelse af denne spec.

**Godkendt tillæg 2026-08-21:** Specialens identitetsstandard er ændret til
`UAFKLARET`, så den genererede baseline også passerer converterens G3-gate,
når alias 1021 allerede har en anden `samme_som`-kant. R40 og R15 beholder
standarderne `TIL 1017` og `TIL 1021`. Fladen starter derfor med 13
uafklarede og 2 afklarede beslutninger.

## Problemet

C3's hashbundne tekstark er maskinelt sikkert, men vanskeligt at navigere i.
Det samler 15 beslutningslinjer for syv sager i én tekstfil, og den
byte-låste form gør det uklart for redaktøren, hvilke dele der må ændres.

Web-redaktørens eksisterende »læg personer sammen« kan ikke erstatte arket.
Den udfører en produktionsskrivning af `samme_som` og dækker kun
identitetsaksen. C3 skal uafhængigt afgøre både personidentitet og placering af
hver kilderecord, og den aktuelle fase skal fortsat stoppe før enhver
databaseskrivning.

Der bygges derfor en lokal, statisk HTML-reviewflade oven på den allerede
godkendte C3-kontrakt. Fladen er kun en lettere måde at redigere de samme 15
tokens på. Den ændrer hverken beslutningssemantik, hashes eller konverterens
autoritet.

## Beslutninger

| Spørgsmål | Valg |
|---|---|
| Hvad eksporterer siden? | Et nyt `c3-afgoerelser-redigeret.txt`, ikke beslutnings-JSON. |
| Skriver siden til databasen? | Nej. Ingen netværks-, database- eller filsystemskrivning ud over brugerens eksplicitte browserdownload. |
| Hvad er den endelige validator? | Den eksisterende `convert_c3_decisions_1939_v50.py`, uændret. |
| Hvor ligger siden? | Kun i `work/task27-1939-v50-c3-review/`; den committes aldrig. |
| Gemmer browseren kladder? | Nej. Ingen `localStorage`, cookies eller autosave. |
| Må modellen se den virkelige side? | Nej. Virkelige `work/`-data åbnes ikke i model- eller browserværktøjer. |

## Scope og artefakter

En ny Python-generator læser lokalt:

- `selection-v1.json`;
- `current-state-v1.json`; og
- det eksisterende `c3-afgoerelser.txt`.

Den validerer hele den eksisterende kæde og skriver ét selvstændigt dokument:

```text
work/task27-1939-v50-c3-review/c3-review.html
```

HTML-filen indeholder alle nødvendige styles, data og JavaScript. Der er ingen
CDN, import, `fetch`, analytics eller anden ekstern afhængighed. Generatorens
stdout indeholder kun sikre counts og SHA-256-værdier.

Siden downloader:

```text
c3-afgoerelser-redigeret.txt
```

Downloaden konverteres ikke automatisk. Efter menneskets eksplicitte
godkendelse køres den eksisterende Python-konverter som et separat trin.

## Sideopbygning

Siden viser syv sagskort og en fast oversigtsbjælke.

Oversigten viser:

- aktuel sag, fx `1 af 7`;
- antal afklarede og uafklarede beslutninger;
- links til alle syv kort; og
- forrige/næste-navigation.

Hvert almindeligt kort viser lokalt den relevante kildetekst, kandidater og
strukturelle tilstand samt to tydeligt adskilte valg:

1. **Er personerne samme menneske?**
2. **Hvem tilhører denne kilderecord?**

Specialkortet 1017/1021 viser tre valg:

1. identitet mellem 1021 og 1017;
2. R40/A's placering; og
3. R15/B's placering.

Standardværdierne er eksakt de værdier, det eksisterende tekstark allerede
bærer: de 12 almindelige beslutninger og specialens identitetsbeslutning er
`UAFKLARET`, mens specialens to recordforslag er `TIL 1017` og `TIL 1021`.
Specialens identitetskontrol modtager desuden den foretrukne retning 1021
alias → 1017 canonical fra den autoritative `review_sequence()`. Vælger
redaktøren aktivt `Samme menneske`, initialiseres selectorernes eksakte token
derfor som `SAMME 1021 1017`; almindelige sagers selectoradfærd er uændret.

## Beslutningskontroller

### Identitet

Brugeren vælger mellem:

- `Uafklaret` → `UAFKLARET`;
- `Forskellige personer` → `FORSKELLIGE`; eller
- `Samme menneske` → `SAMME <alias> <canonical>`.

Ved `Samme menneske` vises to separate personvælgere. Begge begrænses til
sagens `allowed_person_ids`, og samme person kan ikke vælges i begge felter.
Aliasretningen er synlig og indgår i den viste eksporttoken.

### Kilderecord

Brugeren vælger mellem:

- `Uafklaret` → `UAFKLARET`;
- `Tilhører person` → `TIL <person-id>`;
- `Ingen publikation` → `INGEN_PUBLIKATION`; eller
- `Kræver record-revision` →
  `REVISION <split_into|merged_from|replaced_by>`.

Personvælgeren er begrænset til sagens tilladte personer. Revisionstype er et
lukket valg, ikke et frit tekstfelt.

Hvert valg viser altid den eksakte tokenstreng, som downloades. Der er ingen
skjult eller kontekstafhængig oversættelse.

`UAFKLARET` forbliver et gyldigt fail-closed udfald og spærrer ikke download.
Oversigten gør uafklarede valg synlige, men presser ikke redaktøren til at
godkende utilstrækkelig evidens.

## Bytebevarende eksport

HTML-generatoren læser reviewarkets rå bytes og indlejrer dem Base64-kodet.
Den udleder de 15 redigerbare tokenområders præcise byteintervaller fra den
eksisterende autoritative `review_sequence()` og det validerede ark.

Browserens eksport arbejder på bytes, ikke på en normaliseret tekstkopi:

1. Base64 dekodes til de oprindelige bytes.
2. De 15 tokenintervaller erstattes i faldende byteposition, så tidligere
   offsets ikke forskydes.
3. Alle bytes uden for tokenintervallerne kopieres urørt.
4. Resultatet downloades som UTF-8-tekst uden browserbaseret newline- eller
   Unicode-normalisering.

Ved urørte valg skal downloadens bytes derfor være identiske med det
oprindelige reviewark. Ved redigering må en byte-diff kun ramme de 15
tokenområder. Den eksisterende konverter beviser den samme egenskab igen ved
positionsstreng rekonstruktion.

Efter download beregner siden SHA-256 med browserens lokale Web Crypto API og
viser hashen. Web Crypto bruges kun lokalt; det sender ingen data ud.

## Sikker rendering

Kildetekst og navne indlejres som data, ikke som eksekverbar markup. Dynamisk
tekst sættes med `textContent`; den må aldrig interpoleres i `innerHTML`.
Base64-data holdes adskilt fra scripts, så tekst som `</script>` eller HTML-
tags ikke kan bryde ud af datafeltet.

Siden indeholder:

- ingen netværkskald;
- ingen forms med eksternt `action`;
- ingen `localStorage`, `sessionStorage`, cookies eller IndexedDB;
- ingen evalueret tekst (`eval`, `Function`, inline event-attributter); og
- ingen database- eller Supabase-klient.

En refresh nulstiller siden til det hashbundne udgangspunkt. Kun brugerens
eksplicitte download skaber en ny fil.

## Fail-closed generator

Generatoren skal før HTML-output:

- beregne selection-, state- og reviewhash fra eksakte bytes;
- validere selection/state gennem den eksisterende review-builder;
- validere hele reviewarket gennem den eksisterende beslutningskonverter uden
  at kræve, at alle valg er afklarede;
- kræve præcis syv sager, otte records og 15 beslutningslinjer;
- kræve den låste 1017/1021-kontrakt;
- kræve unikke beslutnings-ID'er og ikke-overlappende tokenintervaller; og
- afvise eksisterende output og publicere HTML atomisk uden overskrivning.

Ved fejl skrives ingen delvis HTML-fil. Fejl er stabile `C3_HTML_*`-tokens og
må ikke indeholde navne eller narrativ tekst.

## Verifikation

Python-kode og tests kører med `/usr/bin/python3` 3.9.6.

Enhedstests bruger kun syntetiske fixtures og beviser mindst:

- præcis syv kort og 15 kontroller;
- de seks almindelige to-aksers sager og specialens tre valg;
- korrekte defaultværdier og lukkede valgmængder;
- at urørt eksport er byte-identisk med inputarket;
- at redigering kun ændrer tokenbytes, også når tokenlængden ændres;
- danske UTF-8-tegn og newlinebytes bevares;
- HTML-/script-lignende syntetisk tekst forbliver inert;
- selection-, state- og reviewhashdrift afvises;
- manglende, ekstra, duplikerede eller overlappende tokenområder afvises;
- output er no-clobber og tempfiler ryddes ved fejl; og
- HTML/JavaScript indeholder ingen netværks-, lagrings- eller databaseskrivevej.

Den genererede syntetiske HTML testes i rigtig Chromium/Playwright:

- navigation og statusoversigt virker;
- afhængige person-/revisionfelter vises korrekt;
- ulovligt selv-link kan ikke eksporteres;
- urørt og redigeret download har de forventede eksakte bytes; og
- den viste SHA-256 matcher downloadens bytes.

Det faktiske `work/`-dokument åbnes ikke i browserkontrol, screenshot,
Playwright-output eller modelkontekst. Den virkelige HTML genereres først
efter at syntetiske browsertests er grønne og afleveres direkte til brugeren
som lokal fil.

## Uden for scope

- Ændringer af web-redaktøren eller dens `samme_som`-funktion.
- Direkte generering af C3-beslutnings-JSON fra browseren.
- Database-, RPC- eller apply-kald.
- Persistens af kladder i browseren.
- Automatisk accept af alle sager.
- Ændringer af C3's beslutningssemantik eller eksisterende konverter.
- En senere apply-fase.

## Næste gate

Efter særskilt godkendelse af denne spec skrives en implementeringsplan. Planen
skal ende ved den lokale HTML-fil og stoppe for menneskelig gennemgang. Først
efter redaktørens download og eksplicitte godkendelse må den eksisterende
konverter køres.
