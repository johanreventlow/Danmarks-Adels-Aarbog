# Evidensbaseret genimport — styrende roadmap

**Myndighed:** Autoritativ prioritering for genimportprogrammet
**Status:** Ét aktivt programmål ad gangen

## Aktivt programmål

Trin 1-3 er `produktionsverificeret` pr. 2026-09-06: #152's cutover til
narrativ-record-kontrakt version 2, #153's generelle writer, 149a (2018-20
kilderegnskab) og 149b (2018-20 narrativ-binding) blev anvendt og efterverificeret
i produktion 2026-09-05/06 (GO 1-4, se `docs/changelog.md`). C3's fem-sagers scope
var anvendt 2026-08-29 ([production-apply-rapporten](c3-production-apply-2026-08-29.md)).

Projektejeren har 2026-09-06 aktiveret **trin 4: den fælles fortolkningskæde og
klausulgranularitet (#147/#148)**. Målet er `specificeret` i
[trin 4-spec'en](../superpowers/specs/2026-09-06-trin4-fortolkningskaede-og-klausulgranularitet-design.md)
(revision 3 efter to uafhængige læsninger) med seks projektejer-valg registreret i
`docs/decisions.md` samme dato: `codex exec` som model-backend, to nye
elementoperationer i den generelle writer, uafhængig anden læser pr. plan,
GDPR-udelukkelsesregler for modelkald, ChatGPT-abonnement som behandlingsgrundlag for
afdødes tekst, og promotion som binding til eksisterende assertions. Arbejdet er delt
i otte dagsværk; planer for 4.1a-4.2 findes, 4.3-4.5 skrives efter de målinger, de
afhænger af. Ingen del af trin 4 er implementeret eller anvendt i produktion.

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
