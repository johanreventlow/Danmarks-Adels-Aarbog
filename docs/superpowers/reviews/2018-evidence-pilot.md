# 2018-20 evidence-pilot: forberedende NO-GO

**Dato:** 2026-08-03  
**Status:** Ingen extraction, modelkørsel eller produktionsmutation er udført.

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

## Blokeringer

Pilotens nødvendige kildeside findes ikke i dette worktree: der er ingen rå
2018-20-PDF, tekst-rendition eller andet input, der kan hashes og bindes til et
batchmanifest. `data/extracted-2026-06-18/` indeholder 591 tidligere
strukturerede person-outputfiler, ikke den rå kildetekst. Den lokale database
har desuden nul `private.source_record`-rækker for udgaven, og kan derfor ikke
levere de mindst ti krævede strukturelle/non-person records.

47 levende poster findes i udgaven. Der foreligger ingen særskilt godkendelse
af ekstern databehandler, retention eller destination for deres tekst. Ingen
sådan tekst er sendt til en model.

## Beslutning

**NO-GO for Task 16, step 3--5.** En ny pilot må først starte, når en frosset
2018-20-rendition med inputhash er stillet til rådighed, de strukturelle records
kan indgå i manifestet, og behandling af eventuel levende-persontekst er
udtrykkeligt afklaret. Da kan et deterministisk, ikke-levende 30-personers
udvalg dannes fra den målte population ovenfor.
