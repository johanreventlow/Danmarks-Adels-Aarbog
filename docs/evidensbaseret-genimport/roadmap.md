# Evidensbaseret genimport — styrende roadmap

**Myndighed:** Autoritativ prioritering for genimportprogrammet
**Status:** Ét aktivt programmål ad gangen

## Aktivt programmål

Afslut C3 ved den planlagte samlede integration, disposable rehearsal og stop
før produktion.

Stopporten er enten et dokumenteret `READY_FOR_PRODUCTION_GO` eller en
fail-closed blocker. Stopporten giver ikke i sig selv produktions-GO.

## Styrende rækkefølge

Når C3 har nået sin stopport, er rækkefølgen:

1. Narrativer knyttes entydigt til konkret source record (#152).
2. Permanente writer-/batchmekanismer generaliseres (#153).
3. 2018-20 får fase A-ækvivalent provenance (#149).
4. Den fælles fortolkningskæde og klausulgranularitet færdiggøres (#147/#148).
5. Placement/membership og én identitetsvej konsolideres (#150/#151).
6. Kæden køres ende-til-ende på begge referenceudgaver.
7. En tredje årbog beviser, at kun en lille profil og dokumenterede
   vokabularudvidelser kræves.

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
programspor.

## Hvad der er parkeret

Spor H og M samt nye 1939-undtagelsesfaser er parkerede, medmindre de kræves
af det aktive programmål eller en udtrykkelig beslutning.

## Ændringsmyndighed

Roadmaprækkefølgen må kun ændres ved projektejerens begrundede beslutningspost
i `docs/decisions.md`. Visionen ændres ikke af roadmapet.
