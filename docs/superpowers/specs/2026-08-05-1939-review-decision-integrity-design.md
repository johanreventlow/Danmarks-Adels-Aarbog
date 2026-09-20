# 1939 review- og beslutningsintegritet

## Formål

Et review-ark skal afvise en rå-udsnitshash, der ikke matcher den ordrette
råtekst, før der skrives et beslutningsoutput. Den direkte
review_to_decisions-funktion skal desuden selv håndhæve de globale
dubletmålregler.

## Kontrakt

For en accepteret review-post skal SHA-256 af raw_verbatim_text kodet som
UTF-8 være identisk med raw_excerpt_sha256. Formatkontrol alene er ikke nok.

review_to_decisions bygger først en key-indekseret entry-mængde, afviser
duplicate baseline_record_key og bruger derefter den fælles
duplicate_target_errors-regel med review_status. Først derefter omsætter den
entries til beslutninger. Den accepterer aldrig unreviewed.

## Afgrænsning

Kontrollen læser kun review-data i hukommelsen. Den søger ikke i OCR, ændrer
ikke review-filer og udfører ingen materialisering, database- eller
deploymenthandling.

## Test

Syntetiske tests dækker en hash med korrekt format men forkert indhold og en
direkte konvertering med ukendt dubletmål, selvreference, dubletkæde og mål i
menneskeark. En komplet gyldig review-mapping består.
