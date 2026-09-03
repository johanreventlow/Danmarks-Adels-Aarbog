# 1939 v50 fase D1 — publicering af de 44 staged probander: design

**Status:** godkendt i brainstorm 2026-08-19. Implementeringsplan følger.

## Problemet

96 personer står `staged` i prod. `staged` skjuler dem for anonyme læsere,
indtil en redaktør har matchet dem mod eksisterende udgaver — værnet mod
dublette Conrad'er (invariant 8, kurateringssporet K2). De er altså ikke
fejl; de er poster, ingen har taget stilling til endnu.

Målt 2026-08-19 deler de sig sådan:

```
96 staged
├── 51 probander (har 1939-narrativ)
│   ├── 44  har published record-binding fra fase A/B   → D1
│   └──  7  uden binding                                → D3, blokeret
└── 45 gift-ind-ægtefæller
    ├── 21  har en SYNLIG partner                       → D2
    └── 24  har en staged partner                       → følger med D1
```

**D1 dækker de 44.** De øvrige to skiver planlægges hver for sig.

## Hvorfor netop de 44 er den rene mængde

Tre objektive kriterier, ingen skøn: `staged` er sand, personen har et
1939-narrativ, og narrativet har en `published` binding i
`private.narrative_record_publication`. Bindingen betyder at fase A's
kilderegnskab og fase B's tekstarbejde begge har anerkendt posten — den er
en identificeret post i bogen, ikke en løs ende.

Kontrolleret ved udvælgelsen:

- **0 af de 44 er berørt af C0's udestående.** C0's uafklarede
  (sammenlægning, for kort, gennemgang) rører person-id'erne 929, 930, 974,
  977, 991, 1013, 1014, 1017, 1021, 1028, 1138, 1220, 1239, 1241, 1243 og
  1291. Ingen af dem er i de 44.
- **6 har en `samme_som`-relation, og alle seks peger på 2020-udgaven**
  (Gotskalk↔Gottschalk, Henrik↔Hinrich, Ditlev↔Detlef, Detlev↔Detlef,
  Frederik↔Friderich ×2). Det er tværudgave-links, ikke dubletter inden for
  1939. De **bekræfter** identiteten frem for at rejse tvivl, og
  frontendens `samme_som`-collapse viser de to udgavers narrativer som én
  person. De skal publiceres på lige fod med de øvrige.

Navnematchning indgår bevidst **ikke** i udvælgelsen. Staged person 927
hedder »Henrik« og deler navn med otte synlige personer; i en adelsslægt
genbruges fornavne i hver generation. Det er samme lære som i C0: teksten
bærer identiteten, navnet gør ikke.

## Effekten: 68, ikke 44

`red_publicer_personer` afstager de valgte **og deres familie-partnere** —
et bevidst designvalg, så man ikke ender med et ægteskab, hvor den ene part
er usynlig. Målt: de 44 trækker **24 partner-stubs** med sig.

| | Antal |
|---|---|
| Valgte probander | 44 |
| Partner-stubs der følger med | 24 |
| **Bliver offentligt synlige** | **68** |
| Staged tilbage bagefter | 28 (7 blokerede + 21 til D2) |

De 24 er en delmængde af de 45 ægtefæller — netop dem, hvis partner er
blandt de 44. Efter D1 består ægtefælle-restmængden af de 21, hvis partner
allerede var synlig.

Tallet 68 skal stå i GO-pakken. »Vi publicerer 44« ville være misvisende
om, hvor mange mennesker der faktisk bliver synlige for offentligheden.

## Skrivevej

`red_publicer_personer(p_person_ids bigint[])` findes allerede
(db-migrations.sql, 2026-07-20) og er bygget til præcis dette: selektiv
publicering scopet til et udvalg frem for hele kilden. Den kræver rollen
`redaktion`, kører gennem `begin_change_set`, og rydder `staged` for de
valgte plus deres familie-partnere.

**Ingen DDL. Ingen ny RPC.** Vi bruger husets eksisterende værktøj.

## Fortrydelse — modsat C0

`person` står i `version_pk_registry`, og RPC'en åbner et change_set.
Publiceringen kan derfor rulles tilbage ad den normale vej. Det er en reel
forskel fra C0, hvor narrativ-bindingerne ikke er dækket af fortryd, og det
sænker risikoen ved denne fase betydeligt.

Det fritager ikke for gates: at kunne fortryde er ikke det samme som at
ville. En publicering er udadvendt — poster om historiske personer bliver
tilgængelige for enhver — og skal godkendes som sådan.

## Menneskefladen

Token-fil efter husets mønster (som C0 og fase B): én linje pr. person,
byte-låst kontekst, fail-closed konverter, anbefaling udfyldt.

Hver linje viser: person-id, navn, side, antal fakta, om der er
tværudgave-`samme_som`, og hvilke partner-stubs der følger med netop den
person. To lovlige tokens:

- `[PUBLICÉR]` — udfyldt på forhånd
- `[VENT]` — hold denne tilbage; resten kører videre

`[VENT]` er ikke en nødbremse for hele fasen, men for den enkelte post.
Vælges den, fjernes personen fra id-listen — og partner-udvidelsen
genberegnes, så en tilbageholdt proband ikke utilsigtet publicerer sin
ægtefælle.

## Gates

Husets sædvanlige kæde, uændret:

1. Frisk backup (0600 + SHA-256) umiddelbart før.
2. Rehearsal mod en frisk produktionsækvivalent restore, med byte-identiske
   før/efter-baselines på alt der ikke skal ændres.
3. Din godkendelse med eksakte hashes og eksakte tal.
4. Én apply, ingen retry.
5. Efterkontrol: præcis 68 afstaget, 28 staged tilbage, og nul delta på
   person-, fact- og relation-tællinger (publicering ændrer kun `staged`).

`get_advisors(security)` er ikke relevant — der er ingen DDL.

## Verifikation

- Udvælgelsen er deterministisk og bygger kun på de tre objektive
  kriterier; samme base → samme 44.
- **Partner-udvidelsen forudsiges før apply og verificeres efter.** En
  rehearsal-assert skal ramme præcis de 24 forventede partnere. Rammer den
  flere, er der en familie-kant, vi ikke kender, og det skal stoppe kørslen
  — ikke opdages bagefter i produktionen.
- Konverteren er fail-closed som C0's: byte-identitet på alt andet end
  tokenet, hvert id præcis én gang, ukendte tokens afvist.
- Enhedstest af udvælgelse, partner-udvidelse og konverter.

## Afgrænsning

Uden for D1: de 7 blokerede (venter på C0's efterkørsel og C3), de 21
ægtefæller med synlig partner (D2), pensionering af dubletter (der er ingen
i denne mængde), og enhver ændring af fakta, relationer eller narrativer.
**D1 ændrer udelukkende `staged`.**
