# 1939 rå-brointegritet

## Formål

En accepteret 1939-coverage-bro skal bevise både Calamari- og rå-OCR-siden
positivt. De nuværende rå-koordinater kan alene ikke bevise, at de peger på
det tilsigtede kildestykke.

## Kontrakt

En accepteret review-post skal fortsat have raw_char_from, raw_char_to og
kind, og skal desuden have:

- raw_verbatim_text: det præcise tekstudsnit fra rå OCR;
- raw_excerpt_sha256: SHA-256 af netop dette tekstudsnit, kodet som UTF-8.

Ved materialisering skal systemet kræve:

1. 0 <= raw_char_from < raw_char_to <= len(raw_text);
2. raw_text[raw_char_from:raw_char_to] er identisk med raw_verbatim_text;
3. SHA-256 af raw_verbatim_text kodet som UTF-8 matcher
   raw_excerpt_sha256.

Den canonical coverage-fil gemmer koordinater, kind og raw_excerpt_sha256;
den kopierer ikke raw_verbatim_text. Den globale raw_ocr_sha256 fastholder
hele kildefilen, mens udsnitshashen gør hvert anker uafhængigt
kontrollerbart.

## Fejlgrænser

- Manglende, tom eller uoverensstemmende råtekst afvises før
  coverage-materialisering.
- En ugyldig SHA-256 eller et interval uden for råteksten afvises før
  coverage-materialisering.
- Der foretages ingen råtekst-søgning, normalisering eller korrektion.
  Koordinaterne og det ordrette udklip kommer stadig eksplicit fra
  menneskearket.
- unreviewed, menneskeark og eksplicit_dublet må ikke bære
  kandidat-/rå-brofelter.

## Bagudkompatibilitet og test

Det eksisterende private ark indeholder kun unreviewed-poster og påvirkes
derfor ikke. Nye accepterede poster skal udfylde de ekstra felter.
Syntetiske tests dækker eksakt match, forkert råtekst, forkert hash,
interval uden for råteksten og fravær af felterne. Hele scriptsuiten køres
efter ændringen.
