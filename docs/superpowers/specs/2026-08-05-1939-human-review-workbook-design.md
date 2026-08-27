# 1939 menneskeark som Excel-projektmappe

## Formål

Gøre de 546 historiske coverage-records tilgængelige for redaktionel
gennemgang uden at kræve redigering af JSON eller gæt om vurderingsopgaven.

## Projektmappe

Start her forklarer at hver række er en historisk 1939-post, ikke en database-
person. Den forklarer de tre valg: accepteret betyder at redaktøren indtaster
en eksakt kildebro; eksplicit_dublet betyder at rækken henviser til en anden
accepteret baseline-key; menneskeark betyder at en kort begrundelse parkerer
rækken.

Review er én filtrérbar række pr. baseline-record. Den viser record_key,
navn, linje, nummer, sider, lokalt id, narrativt uddrag, ægteskaber og
usikkerhedsmarkering fra det historiske baseline-artefakt. Redaktørfelter er
review_status, reason, duplicate_of_baseline_record_key samt de eksplicitte
Calamari-, PDF- og rå-OCR-ankerfelter.

Afgørelser viser en kort feltmatrix pr. status og understreger at tomme
eller uklare ankre ikke må udfyldes med gæt.

## Sikker roundtrip

Projektmappen er en privat, ignoreret arbejdsartefakt. En senere importer må
kun læse de eksplicitte redaktørfelter, validere baseline-hash og alle
eksisterende review-kontrakter og derefter skrive et nyt JSON-beslutningssæt
eksklusivt. Excel-filen ændrer aldrig den eksisterende JSON-ledger.

## Verifikation

Generatoren skal bevise 546 unikke rækker, korrekt baseline-hash, gyldige
statusværdier i dropdown, tydelige instruktioner og ingen afkortede nøglefelter
ved visuel kontrol.
