# Færdigbevis: trin 6 — 1939 gennem samme kæde som 2018-20 (2026-11-22)

Spec: `docs/superpowers/specs/2026-10-29-trin6-1939-gennem-kaeden-design.md` §8. Roadmap trin 6, færdigbevis (a)-(c).
Delbeviserne står i delspec'ernes færdigbeviser; her samles de, og det sidste punkt i (b) er målt 2026-11-22.

## (a) Samme operationer

1939's klausuler, fortolkning, identitet, placement og publicering er gået gennem de samme RPC'er og writere som
2018-20, uden nye editionsnavngivne permanente overflader (tjekliste i hver delspec):

| Led | Delspec, i prod | Bevis |
|---|---|---|
| Klausuler | 6a, 2026-10-30 | `database-current-state.md` §17 |
| Personas og identitet | 6b A+B 2026-11-01, C 2026-11-02; 6d-2a 2026-11-10 | §18, §20, §25 |
| Fortolkning, kontrol, rettelse, binding | 6c-1 2026-11-02, 6c-2 2026-11-06, 6m 2026-11-07, 6c-3 2026-11-08 | §19, §21-§23, [6c-3](kildetekst-revision-6c3-prod.md) |
| Placement og medlemskab | 6d-1, 2026-11-09 | §24, [6d-1](placement-6d1-prod.md) |
| Relationer | 6d-3, 2026-11-11 | §27 |
| Publicering og læser | 6e-1 2026-11-12, 6e-2 2026-11-14 | §30, [6e-1](laeserflade-6e1-prod.md), [6e-2](laeserflade-6e2-prod.md) |

## (b) Læseren (som `anon` mod prod)

| Spec §8 (b) | Bevis |
|---|---|
| En sammenfoldet person åbner på 2018-20; 1939 viser 1939's fakta med »DAA 1939, s. N« | 6e-1 + 6e-2: Conrad (V-1) viser s. 52; [6e-2](laeserflade-6e2-prod.md) §8 |
| En 1939-person uden 2018-20-modpart viser bundne 1939-fakta | 2026-11-22, læse-kun: person 1235 (ingen `samme_som`, kun 1939-narrativ) giver som `anon` 6 valgte fakta, heraf 4 bundet til 1939-posten med »DAA 1939, s. 57«. (6e-1's person 927 beviser kun »ingen vælger«: ét fakta, ubundet.) |
| En rettet værdi viser bogens værdi og er bundet | 2026-11-22, læse-kun: påstand 11940 (person 1071, rettet `bogen_har_ret` fra »Dellev« til »Detlev«) er valgt og `afklaret`; `public_person_facts` som `anon` giver »Detlev« med `record_label` »I, nr. 2« og »DAA 1939, s. 31-32«. Browser som anon: `/person/1071` viderestiller til den samlede person 25; »Detlev« 1 gang, »Dellev« 0, ingen `record-`/`legacy-source:` |
| En 1939-person har linje og nr. fra placement, ikke `linje='1939'` | 6e-2: 561 koordinater fra placement, ingen `record-`-etiket som anon |
| Personsiden for de tungeste personer svarer under anons grænse med god margen | Målt 2026-11-22, se nedenfor |

### Tunge personsider (målt 2026-11-22)

Anons grænse er `statement_timeout` = 3 s pr. kald. De tungeste sider er valgt **pr. samlet side** (`samme_som`-komponent,
som læseren viser én side for): fakta, familierækker og narrativtegn summeret over komponentens rækker; top 12 plus
tidligere målte tunge (149, 405, 442), 306 fra en første optælling pr. række og en let sammenligning (927).

**Serverens egen tid** (som `anon`, `EXPLAIN ANALYZE`, prod):

| Kald | Tid |
|---|---|
| `public_person_source_coordinates_samlet()` (hele modellen, samme for alle sider) | 336 ms |
| `public_person_facts` for den tungeste komponent (178, 298, 967, 1354) | 484 ms |

**Browser som anon** (headless Chromium mod `danmarks-adels-aarbog.vercel.app`, én side ad gangen, 3 kørsler pr. side,
median; tiderne er klientens og rummer netværk og kø, fordi siden sender 31-46 kald samtidig):

| Side | Rækker | »Fakta« synlig | Længste kald (median / max) | Kald | Fejl |
|---|---|---|---|---|---|
| 178 | 4 | 4,2 s | 1,1 / 1,2 s | 41 | 0 |
| 255 | 3 | 4,3 s | 1,2 / 1,3 s | 46 | 0 |
| 529 | 3 | 3,7 s | 1,2 / 2,2 s | 32 | 0 |
| 94 | 3 | 4,5 s | 1,2 / 1,2 s | 32 | 0 |
| 544 | 3 | 3,7 s | 1,2 / 1,4 s | 32 | 0 |
| 284 | 2 | 3,7 s | 1,1 / 1,5 s | 32 | 0 |
| 515 | 2 | 4,6 s | 1,4 / 1,4 s | 37 | 0 |
| 534 | 2 | 3,8 s | 1,1 / 1,4 s | 32 | 0 |
| 546 | 2 | 4,1 s | 1,2 / 1,5 s | 31 | 0 |
| 309 | 2 | 3,6 s | 1,1 / 1,3 s | 32 | 0 |
| 364 | 2 | 3,9 s | 1,2 / 1,2 s | 32 | 0 |
| 510 | 2 | 4,4 s | 1,1 / 1,2 s | 32 | 0 |
| 306 | — | 3,7 s | 1,2 / 1,2 s | 39 | 0 |
| 405 | — | 3,6 s | 1,2 / 1,3 s | 32 | 0 |
| 442 | — | 4,1 s | 1,2 / 2,7 s | 31 | 0 |
| 149 (to runder) | — | 4,7 / 3,8 s | 2,3 / 3,3 s; 1,3 / 1,4 s | 31 | 0 |
| 927 (let) | — | 4,1 s | 1,2 / 1,4 s | 41 | 0 |

529 er målt i to runder (median fra anden, max over begge). **Dom: opfyldt.** 0 fejlede kald i 57 sideindlæsninger. Serverens tid for de tunge kald er 0,3-0,5 s mod grænsen på
3 s. Ét klientmålt kald på 3,3 s (149, koldt første besøg) gentog sig ikke (1,4 s i næste runde) og gav ingen fejl.
**Grænsen gælder pr. kald, ikke hele siden:** ingen personside viser »Fakta« under 3 s. Tiden (3,6-4,7 s) er den samme
for den lette side (927: 4,1 s) som for de tunge, så den skyldes sidens faste 31-46 samtidige kald, ikke personens
mængde. Det er en brugeroplevelse, ikke anons grænse, og står som kendt rest nedenfor.

## (c) To kilder

6d-1 (2026-11-09): `membership_component_states()` giver 441 `corroborated` (alle med to kilder), 3 `conflict`, 212
`single`, 224 `none` ([6d-1](placement-6d1-prod.md)).

## Tal i prod og A6b-resten

Tallene pr. led står i [status.md](status.md)'s modenhedstabel. A6b-resten: 6c-3 (2026-11-08) rettede de 10 posters
kildetekst og klausuler; I-84 er parkeret med synlig disposition (decisions 2026-10-29/30).

## Status-punktet: 1939-kolonnen

Spec'ens §8 hæver 1939-kolonnen led for led til `produktionsverificeret`. Tre celler er det ikke, og roadmappets
(a)-(c) afhænger ikke af dem:

- **Kildetekst-revision** (`isoleret implementeret`): 6a skulle kun bygge og bevise mekanismen (§6 pkt. 7); den er
  `produktionsverificeret` for kilde 1 (6c-3), og (a) kræver ikke, at en 1939-helpost er revideret.
- **Promotion — oprettelse** (—): oprettelse af nye personer, familier og fakta er opret-benet (B4), som hører til
  fortsættelsen (decisions 2026-10-28 pkt. 3).
- **C3 reversal** (`integreret ende-til-ende`): en fortrydelse af C3, ikke en operation i kæden.

## Kendte rester (ikke en del af færdigbeviset)

- **Personsidens samlede tid:** ~4 s til »Fakta« for gæster, også på lette sider (31-46 samtidige kald). Hvert kald er
  under anons grænse.
- **Biografilæserens fart:** udskudt »til før projektets afslutning« (decisions 2026-11-10). Feedets biografier tager
  ~10 s (#422, åben); personsidens biografikald er inden for grænsen (decisions 2026-11-10: 209-487 ms).
- **Stående forslag:** 1939: 25 forslag (23 uden faktum, 2 uden identitet), 203 ægteskaber, 5 forældre og 4 børn
  `proposed` med årsag (6d-3). 2018-20: 59 `SKRIVEMAADE` (datobindingernes del 2 ikke besluttet).
- **6d-2b indsnævret:** tekstrettelser, grænsefejl og afstemningswriterens fejl er kendte begrænsninger.
- **#409:** 1.076 af 1939's datopåstande mangler strukturerede datogrænser (læserne viser `date_raw`); udskudt 2026-11-20.
- **#388:** 1794's dobbelte »Greve«; indlæsningen må ikke skrive tomme navne.
- **1939's 16 `[NY]`-records (#160):** første rigtige prøve af opret-benet (B4), efter trin 6.
- **Oprettelse** af nye personer, familier og fakta er ikke en del af trin 6 og er kun bevist syntetisk.
