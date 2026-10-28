# Evidensbaseret genimport — styrende roadmap

**Myndighed:** Autoritativ prioritering for genimportprogrammet
**Status:** Ét aktivt programmål ad gangen

## Aktivt programmål

**Trin 5, sidste del:** 5c-2 (læserskift) sammen med læserværdien (B11), efter reviewets gates før trin 6.
Status, modenhed pr. led og gates: [status.md](status.md). Sektionen her og status' »Aktivt programmål« skal
sige det samme.

## Styrende rækkefølge

Når C3 har nået sin stopport, er rækkefølgen:

1. Narrativer knyttes entydigt til konkret source record (#152).
2. Permanente writer-/batchmekanismer generaliseres (#153).
3. 2018-20 får fase A-ækvivalent provenance (#149).
4. Den fælles fortolkningskæde og klausulgranularitet færdiggøres (#147/#148).
5. Placement/membership og én identitetsvej konsolideres (#150/#151).
6. Kæden køres ende-til-ende på begge referenceudgaver. Færdigbevis: (a) 1939's
   klausuler, fortolkning, identitet, placement og publicering går gennem de samme
   operationer som 2018-20; (b) læseren ser fakta med kildehenvisning i
   persondetaljen (B11); (c) et medlemskab kan bæres af to kilder — en anden kildes
   placement bekræfter (`corroborated`) i stedet for at give konflikt (B6).
   **Projektets mål slutter her** (decisions 2026-10-28).

   **Beslutningspunkt efter trin 6:** projektejeren vurderer, om PoC'en leverer
   værdi for læser og redaktør, og hvad en fortsættelse koster. Udfaldet
   registreres i `docs/decisions.md`: stop, fortsæt med 7a, eller forelæg
   foreningen en fortsættelse. Trin 7 planlægges ikke før det.
7. *Mulig fortsættelse, ikke en del af projektets mål.* En tredje årbog beviser,
   at kun en lille profil og dokumenterede vokabularudvidelser kræves. Trinnet er
   delt i to (B3), og kandidat-årbogen vælges, før det specificeres. 7b og
   foreningens samlede data forudsætter foreningens accept:
   - **7a** — en ny udgave af en slægt, der allerede findes: identitetsafstemning
     mod den eksisterende bestand med kun profil og vokabular.
   - **7b** — en ny slægt uden eksisterende bestand: segmenteringsprofil, oprettelse
     af personer, familier og fakta, placement og publicering uden `load_daa.R`.
     Kræver spec for opret-benet først (B4).

Roadmaprækkefølgen må kun ændres gennem en begrundet beslutningspost i
`docs/decisions.md`. En implementerende agent må ikke selv omprioritere
programmet.

## Adgangskrav til nye planer

Enhver ny plan eller implementeringsopgave inden for scope skal angive:

1. Hvilket roadmapmål den tilhører.
2. Hvilket led i den fælles værdikæde den lukker.
3. Om leverancen er generel, en udgaveprofil eller midlertidig legacy-afvikling.
4. Hvilken redaktionel eller brugerrettet værdi den muliggør.
5. Hvilket konkret bevis der gør leverancen færdig.
6. Hvilke parallelle eller ældre workflows den erstatter.
7. Sit review-budget (antal runder og modeller) på én linje i spec-hovedet.
   Overskridelse kræver én linje i `docs/decisions.md` (B13).

Kan en opgave ikke besvare disse seks spørgsmål, er den som udgangspunkt uden
for scope og kræver en udtrykkelig beslutning, før den planlægges.

## Modenhedstilstande

Funktionalitet beskrives med præcis én af disse tilstande:

- `specificeret`
- `isoleret implementeret`
- `integreret ende-til-ende`
- `produktionsverificeret`

Tests af et isoleret fundament er ikke bevis for, at den samlede funktion er
færdig. Et roadmapmål flyttes kun til en højere tilstand på grundlag af det
konkrete bevis, som målet selv kræver.

## Kontrollerede afbrydelser

Et akut dataintegritets- eller produktionsproblem må afbryde roadmappet, når
det registreres som en afgrænset hændelse med indgangsgrund, slutkriterium og
tilbagevenden til det aktive mål. Hændelsen må ikke stiltiende blive et nyt
programspor. Den registreres med én linje i `docs/decisions.md` (grund, slutkriterium,
tilbagevenden), når den begynder (B13).

## Hvad der er parkeret

Spor H og M samt nye 1939-undtagelsesfaser er parkerede, medmindre de kræves
af det aktive programmål eller en udtrykkelig beslutning.

## Ændringsmyndighed

Roadmaprækkefølgen må kun ændres ved projektejerens begrundede beslutningspost
i `docs/decisions.md`. Visionen ændres ikke af roadmapet.
