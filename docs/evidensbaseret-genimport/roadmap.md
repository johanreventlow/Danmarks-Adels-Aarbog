# Evidensbaseret genimport — styrende roadmap

**Myndighed:** Autoritativ prioritering for genimportprogrammet
**Status:** Ét aktivt programmål ad gangen

## Aktivt programmål

Trin 1-3 er `produktionsverificeret` pr. 2026-09-06: #152's cutover til
narrativ-record-kontrakt version 2, #153's generelle writer, 149a (2018-20
kilderegnskab) og 149b (2018-20 narrativ-binding) blev anvendt og efterverificeret
i produktion 2026-09-05/06 (GO 1-4, se `docs/changelog.md`). C3's fem-sagers scope
var anvendt 2026-08-29 ([production-apply-rapporten](c3-production-apply-2026-08-29.md)).

**Trin 4** (den fælles fortolkningskæde og klausulgranularitet, #147/#148), aktiveret
2026-09-06, er **afsluttet for 2018-20** (`docs/decisions.md` 2026-10-05): klausulerne er kørt
i prod 2026-09-18 og omsegmenteret 2026-09-28, og hele 2018-20's kæde — 3.739 forslag, 676
afgørelser, 622 bindinger — er overført til prod 2026-10-05 med `VERIFY_OK`. Ingest og
afgørelse er `produktionsverificeret` for 2018-20; promotion kun for bindingsdelen. 1939's
kæde hører til trin 6.

Projektejeren har 2026-10-05 aktiveret **trin 5: placement/membership og én identitetsvej
(#150/#151)**, delt i tre delspecs: **5a** én identitetsvej (#151) → **5b** personas for
ægtefæller og børn samt oprettelse af nye kanoniske personer → **5c** placement/membership
(#150). 5a er merget 2026-10-06 (#236) og 5b del 1 (ægtefællers identitet) 2026-10-11 (#237),
begge bevist i restore og ikke deployet; næste arbejde er 5b del 2 (decisions 2026-10-10).

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
