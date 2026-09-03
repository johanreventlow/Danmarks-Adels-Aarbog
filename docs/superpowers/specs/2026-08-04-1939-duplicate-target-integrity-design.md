# 1939 dubletmålintegritet

## Formål

En eksplicit dublet er kun gyldig, når den positivt henviser til én konkret,
accepteret coverage-record. En ikke-tom tekstværdi er ikke tilstrækkeligt
bevis for en sådan henvisning.

## Kontrakt

Efter alle coverage-entries er læst, skal hver entry med status
eksplicit_dublet opfylde alle tre regler:

1. duplicate_of_baseline_record_key er en key i den forventede
   baseline-mængde;
2. målet er ikke entryens egen baseline_record_key;
3. målets status er accepteret.

Dermed kan en dublet hverken pege uden for ledgeren, på sig selv, på en anden
dublet eller på en menneskearks-post. Flere eksplicitte dubletter må godt
henvise til samme accepterede mål, hvis de hver især er dokumenteret i
review-arket.

## Dataflow og fejl

Coverage-validatoren udfører først den eksisterende entry-validering og
baseline-dækningskontrol. Derefter slår den hver dublets mål op i den
færdige, validerede entry-mængde. En overtrædelse afviser hele coverage-
bundleet.

Review-validatoren bruger samme globale regel efter sin entry-validering.
Review-rapporten viser den konkrete target-fejl som blocker. Ingen regel
opretter, ændrer eller gætter på et dubletmål.

## Test og kompatibilitet

Syntetiske tests dækker mål uden for baseline, selvreference, kæde til anden
dublet og mål i menneskeark. Et gyldigt mål med status accepteret består.
Det eksisterende private review-ark indeholder kun unreviewed-poster og
forbliver derfor uændret og gyldigt.
