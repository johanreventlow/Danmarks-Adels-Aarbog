# Fase D2 — de 21 gift-ind-ægtefæller med synlig partner

**Dato:** 2026-08-20 · **Kilde:** DAA 1939 (v50-genimport) · **Rører kun:** `person.staged`

## Problemet

Efter D1 er der 28 staged personer tilbage: 7 blokerede probander (D3) og 21
gift-ind-ægtefæller, hvis partner allerede er offentligt synlig.

De 21 har **ingen egen post i bogen**. Målt mod prod 2026-08-20:

| Egenskab | Antal af 21 |
|---|---:|
| levende | 0 |
| private | 0 |
| uden navn | 0 |
| eget 1939-narrativ | **0** |
| published record-binding | **0** |
| `person_external_id` | **0** |
| dødsfakta | 2 |

De er navne-stubs: et navn, et ægteskab, og næsten intet andet. De findes,
fordi bogen nævner dem som ægtefælle inde i en Reventlows post.

## Hvorfor D1's kriterium ikke kan genbruges

D1 valgte på ét objektivt kriterium: personen har et 1939-narrativ, og
narrativet har en `published` binding i
`private.narrative_record_publication`. Bindingen betød, at fase A's
kilderegnskab og fase B's tekstarbejde begge havde anerkendt posten.

De 21 har per definition ingen binding. Det er ikke en mangel, der kan
udbedres — de var aldrig selvstændige poster. D2 har derfor brug for et
**andet grundlag**, ikke en lempeligere tærskel på det samme.

## Grundlaget: konsistens med de 24, D1 allerede publicerede

`red_publicer_personer` afstager de valgte **og** staged personer i samme
familie. D1's 44 probander trak derfor 24 ægtefælle-stubs med sig —
personer uden egen binding, uden eget narrativ, uden external_id. Præcis
samme slags som de 21.

De 21 adskiller sig fra de 24 på ét punkt: deres partner blev synlig i en
*tidligere* runde, så ingen publicering nåede at trække dem med. Det er en
tilfældighed i tidsrækkefølgen, ikke en faglig forskel.

**Beslutning:** de 21 publiceres på samme grundlag som de 24 — ægteskabet
med en synlig person er selv grundlaget. At holde dem tilbage ville være en
inkonsistens, ikke en beskyttelse.

Konsekvensen ved at lade være er konkret: en bruger, der ser den synlige
partner, ser et ægteskab, hvor den anden part mangler.

## Udvælgelse

Ét deterministisk prædikat, intet skøn:

```sql
p.staged AND EXISTS (
  SELECT 1 FROM family_member f1
    JOIN family_member f2 ON f2.family_id = f1.family_id
                         AND f2.person_id <> p.id
                         AND f2.rolle = 'partner'
    JOIN person a ON a.id = f2.person_id
   WHERE f1.person_id = p.id
     AND f1.rolle = 'partner'
     AND NOT a.staged)
```

Navnematchning indgår bevidst **ikke**. I en adelsslægt genbruges fornavne i
hver generation; teksten bærer identiteten, navnet gør ikke. Samme lære som
C0 og D1.

**Kontrolmængde målt 2026-08-20** (21 id'er):

```
1480, 1487, 1488, 1553, 1554, 1555, 1618, 1650, 1651, 1657, 1659,
1662, 1664, 1665, 1669, 1671, 1682, 1695, 1698, 1714, 1716
```

Prædikatet er kilden; listen er kontrol. Afviger den på dagen, har basen
ændret sig, og tallene skal måles igen før apply.

## Kontroltal

Simuleret mod prod med funktionens **præcise** prædikat:

| | Forventet |
|---|---:|
| Valgte | 21 |
| Faktisk afstaget | 21 |
| Ekstra medrevne | **0** |
| Staged nu | 28 |
| Staged bagefter | **7** |
| Overlap med C0's uafklarede | **0** |
| Personer med flere unioner | 0 |
| Par hvor begge er staged | 0 |

**Afviger ét af tallene, STOP.**

De 7 tilbage skal være præcis D3's blokerede probander — ikke en rest, der
opstod undervejs.

### En fælde i `red_publicer_personer`

Funktionens medrivnings-prædikat filtrerer **ikke** på rolle:

```sql
OR EXISTS (SELECT 1 FROM family_member fm1
           JOIN family_member fm2 ON fm2.family_id = fm1.family_id
           WHERE fm1.person_id = p.id AND fm2.person_id = ANY(p_person_ids))
```

Et staged **barn** i samme familie ville altså også blive afstaget. Målingen
i dag giver 0 ekstra medrevne, men det er en egenskab ved de aktuelle data,
ikke ved funktionen. Tallet skal måles igen umiddelbart før apply og indgå i
GO-tallene — ikke antages fra denne spec.

## Person 1662 — den eneste undtagelse

1662 er den eneste af de 21 med en `samme_som`-relation. Den peger på person
**785**, som allerede er synlig.

Det ligner en dublet, men de to sidder i **forskellige familier** (590 og
234) — altså to ægteskaber for samme menneske. Frontendens
`samme_som`-collapse viser dem som én person, så publiceringen **tilføjer**
det manglende ægteskab i stedet for at skabe en dubletvisning.

**Beslutning:** 1662 publiceres med de øvrige 20. Uden den viser fladen kun
halvdelen af personens ægteskabshistorik.

Bemærk at dette adskiller sig fra D1's regel, hvor en `samme_som` inden for
1939 skulle sendes til C3. D1's regel handlede om **dubletposter i bogen** —
to selvstændige poster om samme menneske, hvor den ene skal pensioneres.

Her er der ingen poster at vælge imellem: 785 har selv 0 narrativer og 0
`person_external_id` (kun 3 fakta) og er altså også en stub. Ingen af de to er
en bogpost. Det, `samme_som`-linket siger, er at de to ægteskaber tilhører
samme menneske — og hver af de to rækker bærer sit ægteskab. At pensionere den
ene ville fjerne et ægteskab, ikke en dublet.

**Uafklaret og bevidst udeladt:** hvorfra 785's tre fakta stammer, når den
hverken har narrativ eller external_id. Det ændrer ikke D2's beslutning — 785
er synlig i forvejen og røres ikke — men det er en løs ende, der hører hjemme i
C3's identitetsspor.

## Procedure

Let, men med D1's sikkerhedsnet, der faktisk betyder noget. Ingen
beslutningsfil og intet menneskeark: der er ikke 21 valg at træffe, kun ét,
og det er truffet her.

1. **Read-only eksport** — prædikatet køres mod prod, alle kontroltal
   udskrives, resultatet hashes (SHA-256).
2. **Guard** — apply afbryder, hvis `staged`-mængden eller id-listen har
   flyttet sig siden eksporten.
3. **Backup** — `pg_dump` før skrivning, 0600, SHA-256 noteret. Basen kører
   på free tier og har ingen backup.
4. **Én apply, ingen retry** — `red_publicer_personer(ARRAY[…21 id'er])`.
   Går den galt, stopper vi og undersøger; vi prøver ikke igen.
5. **Efterkontrol** — 7 staged tilbage; uændrede person-, fact- og
   relation-tællinger; de 21 offentligt kvalificerede (ikke staged, ikke
   levende, ikke private, navn sat).
6. **Dokumentation** — changelog + `database-current-state.md` afstemt.

### Fortrydbarhed

RPC'en åbner et `change_set`, og `person` står i `version_pk_registry`.
Publiceringen kan derfor rulles tilbage med den almindelige fortryd-vej.
Det er ikke en grund til at springe gates over.

## Hvad ligger uden for D2

- De 7 blokerede probander (D3 / C3)
- C0's efterkørsel (10 koblinger)
- Enhver ændring af fakta, relationer eller narrativer

D2 rører udelukkende `person.staged`.

## Rækkefølge mod de øvrige åbne prod-spor

D2 ændrer hverken narrativer eller bindinger og rører kun `staged` for
personer, som C0's uafklarede ikke omfatter (målt overlap: 0). Den kan
derfor køre uafhængigt af C0's efterkørsel i begge rækkefølger.

Skal begge køres, er D2 først det billigste valg: den er lille, målt og
uafhængig, mens C0's efterkørsel kræver en genmåling, fordi den ikke har
nogen guard mod, at D1 har kørt imellem.

## Succeskriterier

1. Kontroltallene bekræftet mod prod umiddelbart før apply.
2. Én apply, ingen retry; efterkontrollen viser 7 staged tilbage og nul
   delta i øvrigt.
3. De 21 er offentligt kvalificerede.
4. Brugeren har set resultatet i web-fladen — særligt at 1662's ægteskab nu
   fremgår på den collapsede person.
