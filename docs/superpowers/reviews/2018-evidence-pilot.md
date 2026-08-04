# 2018-20 evidence-pilot: klar til privat udtræk

**Dato:** 2026-08-04
**Status:** Deterministisk input, segmentering og et privat manifest er klar.
De 30 godkendte personsegmenter er materialiseret som private, profile-pinnede
source records. Ingen modelkørsel eller produktionsmutation er udført.

## Lokal, tekstfri feasibility-kontrol

Den lokale, historiske testdatabase `daa_baseline` indeholder én DAA-udgave for
2020 med 591 eksterne personidentiteter. Deraf er 47 markeret `levende` og er
udelukket fra ethvert muligt pilotudvalg. Af de resterende 544 afdøde kandidater
er der tilstrækkelig variation til den personlige del af en senere pilot:

| Egenskab | Antal afdøde kandidater |
|---|---:|
| Lange biografier (mindst 1.000 tegn) | 109 |
| Titel eller embede | 201 |
| Flere ægteskaber | 50 |
| Fødselsfaktum | 371 |
| Dødsfaktum | 432 |
| Uafklarede forældre | 4 |

Tallene er kun aggregater; rapporten indeholder ingen personprosa eller
personidentifikatorer.

## Løst inputgate

Den frosne PDF er nu tilgængelig og har SHA-256
`3beadfc15e3fa1a4090589af56cd4e95599a9231e8f979dfb60c4e27bbd8252a`.
Den lokale, ignorerede rendition af PDF-side 93--247 giver 591 segmenterede
personposter og en clause-ledger med strukturelle observationer. Manifestet
vælger deterministisk 30 entydigt afdøde poster (seks strata) samt ti
strukturelle observationer. Manifestet, råteksten og posterne ligger kun i
`work/task16-2018-pilot/` og indeholder ikke i denne rapport.

Der er ingen repræsenterede personer med flere kanoniske lineage-memberships i
den historiske baseline; det noteres som et uopfyldt stratum, ikke som en
syntetisk pilotkategori.

47 levende poster findes i udgaven. Den godkendte policy er, at de ekskluderes
helt fra eksterne modelbatches. To flertydige lokatorgrupper (`I-15`, `I-41`)
er også ekskluderet, fordi `(linje,nr)` ikke er et entydigt anker. Ingen sådan
tekst er sendt til en model.

## Beslutning

**GO for Task 16, step 3 (privat udtræk af denne batch).** Den private ledger
har 30 accepterede personrecords, og batchmanifestet er profile-pinnet til
`daa-2018-20-v1` / `gpt-5.6-terra`; det har status `pending` og må kun indeholde
disse 30 afdøde, entydige forekomster. De ti strukturelle observationer er
parkeret, fordi de endnu mangler positive PDF-sideankre. Step 4--5 forbliver
åbne, indtil modeloutput er fuldt valideret og gennemgået i en separat database.
