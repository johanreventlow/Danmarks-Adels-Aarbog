# Evidens-promotion: autoriseret enkeltbatch

En redaktør godkender kun, at bestemte accepterede fortolkninger dokumenteres
som private audit-links til allerede eksisterende assertions. Den opretter,
ændrer eller publicerer aldrig personer, facts, assertions eller anden
kanonisk genealogi, og den har ingen undo/reversal.

Før apply vælges de konkrete `interpretation_id`/`assertion`-mål i den
redaktionelle preview. Preview-hashen og den afledte regelprofil er bundet til
den aktuelle database-identitet, redaktøren og en frisk single-use nonce.
`red_authorize_interpretation_promotions(...)` udsteder autorisationen; apply
skal bruge samme items, preview-hash og autorisations-id før udløb.

En authorization starter som `issued`. En identisk authorize-kald med samme
aktør, nonce, valg og hash returnerer det samme id; genbrug af samme nonce med
andet indhold afvises. Kun én uforbrugt authorization for samme valgte items
og database kan eksistere. Apply gør den `consumed`; den præcise samme apply
returnerer den samme receipt, mens et andet request med id'et afvises. Udløbne
uafsluttede authorizations markeres `expired` ved næste authorize-forsøg og
kan aldrig anvendes.

`red_promote_interpretations_batch(...)` genberegner previewet under sine
stabile fortolknings-, regel-, persona-, identitets-, placement-, assertion-
og fact-låse. Den afviser drift, forkert aktør/database, udløbet eller brugt
nonce, dublet-scope og enhver ikke-eligible item før en batch eller promotion
indsættes. Ved succes returneres en lukket historisk receipt med batch-id,
autorisation, observerede tal og en hash af de levende promotion-links.

Receipt er historisk bevis for den afsluttede batch. Senere current-state
kontrol skal hente receipt- og bindingfelter fra
`private.interpretation_promotion_batch` og
`private.interpretation_promotion_batch_state(uuid)`; vilkårlige R-værdier er
ikke databaseproveniens. En senere link-drift ændrer ikke receiptet, men ændrer
current-state-hashen og skal derfor rapporteres som drift.

Den redaktionelle registrering skal altid gemme: det faktiske udvalg af
interpretation-/assertion-id'er, preview-hashen, authorization-id'et og den
returnerede receipt. Hverken preview eller receipt er en tilladelse til at
oprette kanoniske rækker, og der findes bevidst ingen undo- eller reversal-
operation for promotion-linkene.
