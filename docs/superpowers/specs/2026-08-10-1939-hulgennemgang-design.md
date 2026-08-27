# Design: vedvarende gennemgang af ejerløse huller

**Dato:** 2026-08-10  
**Branch:** `feat/evidensbaseret-genimport`  
**Status:** brugergodkendt design; klar til implementeringsplan

## Formål

De 97 oprindelige ejerløse huller vises som et par:

```text
=== EJERLØS TEKST · N tegn ===
…
=== SLUT EJERLØS TEKST ===
```

Når mennesket har håndteret et hul med skæringer og eventuelle udeladelser, skal
begge hjælpemarkører kunne slettes som en vedvarende kvittering. I den nuværende
flade eksporteres denne handling ikke. Markørerne kan derfor genopstå ved
`--markeringer`, og et halvt par kan stå tilbage uden entydig betydning.

Dette design gør hulparret til én review-enhed uden at tildele ejerskab eller ændre
bogtekst, skæringer, udeladelser eller deres kildekoordinater.

## Semantik

For hvert af de 97 forventede hulspænd gælder præcis tre tilstande:

| Begyndelse | Slutning | Betydning |
|---|---|---|
| til stede | til stede | hullet mangler gennemgang |
| slettet | slettet | hullet er gennemgået og håndteret |
| kun én til stede | — | strukturel fejl; ingen eksport eller sidekvittering |

"Gennemgået og håndteret" er reviewstatus. Det betyder ikke, at tekststykket har
fået en ejer, og det erstatter ikke en senere ejerskabsrunde. Skæringer og
`[[UDELAD]]` er fortsat de eneste indholdsmarkeringer.

Et hulpar kan strække sig over en sidegrænse. Mennesket sletter da begyndelsen på
den ene side og slutningen på den anden. Den midlertidige halve tilstand er synlig
som fejl, indtil begge linjer er slettet; andet redigeringsarbejde kan fortsætte.

## Eksportkontrakt

§7 udvides bagudkompatibelt med et nyt topniveaufelt:

```json
"huller": {
  "i_alt": 97,
  "gennemgaaet": [
    {"char_from": 0, "char_to": 868}
  ]
}
```

Regler:

- `char_from` og `char_to` er tegnkoordinater i den uforanderlige
  Calamari-kildetekst.
- `gennemgaaet` sorteres stigende på `(char_from, char_to)`.
- Hvert interval skal matche ét af generatorens 97 forventede hulspænd eksakt.
- Dubletter, ukendte intervaller, boolske/ikke-heltallige koordinater og forkert
  `i_alt` afvises fail-closed.
- En eksport uden `huller` er en ældre eksport og betyder nul gennemgåede huller.
- `schema_version` forbliver `1`; feltet er en valgfri, bagudkompatibel udvidelse.
- Eksisterende felter i §7 ændres ikke.

Den redigerede tekst eksporteres fortsat ikke.

## Generering og genindlæsning

Generatoren indlejrer de 97 forventede spænd som `expectedHoleSpans`. Ved
`--markeringer` valideres `huller` mod netop dette sæt, før HTML-filen skrives.

- Ikke-gennemgået hul: begge markører genereres.
- Gennemgået hul: ingen af de to markører genereres.
- Ugyldig import: generatoren stopper med en dansk fejl og skriver ingen HTML.

Eksport → genindlæsning skal derfor genskabe samme hulmarkørtilstand, og den
eksisterende byte-gate skal stadig genskabe Calamari-teksten byte for byte efter
strip af alle navngivne markører.

## Browservalidering

Parseren kanoniserer hulmarkørerne gennem de eksisterende
kanonisk↔vist-mappings. For hvert forventet spænd tælles begyndelses- og
slutmarkører:

- `1 + 1`: ikke gennemgået.
- `0 + 0`: gennemgået og medtages i eksportfeltet.
- Alle andre antal: fejl, inklusive dubletter og halve par.

Fejlen skal navngive det forventede hul og den relevante kildeside/PDF-side. Den
er en strukturel annoteringsfejl, ikke en bogtekstændring, men den blokerer både
eksport og sidekvittering på samme måde som en ukendt markør.

## Sidevisning

Sidelistens `ejerløs`-tal skal være levende:

- Den tæller intakte, ikke-gennemgåede hulpar på siden, hvor hullets begyndelse
  ligger.
- Når begge markører slettes, falder tallet uden genindlæsning.
- Gennemgåede huller tæller ikke som ventende arbejde.
- Et halvt eller dubleret par giver fejl i stedet for at blive talt som færdigt.

Sideidentiteten forbliver kildesiden 1–86. Feltet `sider` og dets migration af
tvetydigt PDF-sidetal 598 ændres ikke.

## Fejltekst og hjælp

Redigeringsnøglen skal sige, at begge hulmarkører slettes, når hullet er
gennemgået og håndteret. En halv ramme skal give en kort dansk fejl, eksempelvis:

```text
ejerløs ramme mangler begyndelse på kildeside 1 (PDF-side 496)
```

Fladen må ikke auto-slette modparten. En enkelt sletning kan være et uheld, og
fail-closed synlighed er vigtigere end automatisk oprydning.

## Testkrav

Automatiske tests skal mindst bevise:

1. Begge markører til stede eksporterer hullet som ikke gennemgået.
2. Begge markører slettet eksporterer det eksakte hulspænd som gennemgået.
3. Kun begyndelse eller kun slutning blokerer eksport og sidekvittering.
4. Dubleret begyndelse eller slutning afvises.
5. En ældre eksport uden `huller` genskaber alle hulpar.
6. En gyldig eksport med `huller` udelader begge markører ved genindlæsning.
7. Ukendte, dublerede og fejltypede importerede hulspænd afvises før output.
8. Sidelistens ejerløs-tal falder levende ved sletning af et helt par.
9. Positioner før og efter eksport→reload er identiske.
10. Byte-gaten er grøn med både viste og slettede hulpar og fanger fortsat
    ændring af bogens `### PAGE`-linjer.
11. Den rigtige Chromium-verifikation dækker helt par, halvt par, levende
    sidetælling, eksport og genindlæsning.

## Afgrænsning

Ingen del af dette arbejde:

- tildeler tekst til poster;
- materialiserer accepteret evidens;
- skriver database eller loader;
- udleder automatisk, at et hul er håndteret af bestemte skæringer;
- ændrer tavshed = godkendelse for skæringer;
- ændrer markørgrammatikken ud over den allerede godkendte start-/slutramme.
