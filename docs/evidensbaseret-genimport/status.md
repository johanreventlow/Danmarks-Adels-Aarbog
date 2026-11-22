# Evidensbaseret genimport — aktuel status

**Snapshot 2026-11-22**, efter review 37's blok 1-4, S3, S5, S8 og P11 i prod 2026-11-21/22 (redaktionens RPC'er,
synlighed og sletning hærdet; ingen ændring af genimportkædens led, `database-current-state.md` §41-§46), første
hændelses-load (#130, §40), #415 (synlighed pr. `samme_som`-gruppe, §38), #401 (`fødenavn`, §35), #396 og
`visning_floruit` (§33-§34) og personsletningen taget i brug (#387). Forrige snapshot 2026-11-18 var efter
`record_persona` i prod (Henrik og Iven har deres egen 1939-tekst), 6e-2 i prod (1939's kildeetiket, trykte sider og koordinater), 2018-20's datobindinger i prod (509 fødsler og dødsfald bundet til bogens post), 6e-1 (læseren viser valgt udgave forrest), 6d-3 i prod (1939's relationer, dobbelt ægtefælle, 1791 skjult), 6d-2b (fire forkert tilskrevne 1939-tekster trukket tilbage), 6d-2a (oversigtsreglen og 1939's sidste identitetssager), 6d-1 (1939's placements og medlemskaber), 6c-3 (2018-20's A6b-rest), 6m del 2 (faktaforslag rettet efter bogen), 6m del 1 (læsertekst rettet efter bogen) og 6c-2's ceremoni 4 (efter 6c-1, 6b's A, B og C, 6a, 5c-2 + B11, A6b, reviewets trin B, trin 5c-1 og helhedsreviewet
af trin 1-5, [rapport](../reviews/2026-10-27-trin-1-5/rapport.md)). Dokumentet **overskrives** ved hvert trinskifte og hver
prod-ændring; der skrives ikke tillæg (opdateringsreglen nederst). Det gamle dokument med tillæg til og med
2026-10-27 står i [status-arkiv-til-2026-10-27.md](status-arkiv-til-2026-10-27.md).

## Aktivt programmål

**Trin 6-spec'en:** 1939 gennem de samme operationer som 2018-20 (roadmap trin 6, færdigbevis a-c), opdelt i
delspecs 6a-6e ([spec](../superpowers/specs/2026-10-29-trin6-1939-gennem-kaeden-design.md) §5). **6a er i prod
2026-10-30:** 1939's klausuler er skrevet, og kildetekst-revisionen er bygget og bevist, men ikke anvendt på prod-data.
**6b's ceremoni A og B er i prod 2026-11-01:** 1939's 555 personas er skrevet, men har endnu
ingen identitet. 6c er delt i 6c-1 (runneren på 1939 og 6b's ceremoni C) og 6c-2 (kontrol, rettelse, binding, vej B
og resten af A6b) (decisions 2026-11-01); A6b-resten er siden skilt ud som 6c-3 (decisions 2026-11-02). **6c-1's ceremoni A og B er i prod 2026-11-02:** modellens 2.774 forslag til
494 af 1939's poster ligger som private `proposed`-fortolkninger. **6b's ceremoni C er i prod 2026-11-02 efter
retning 2** (C3's binding bliver identiteten; kun konflikter og en stikprøve på kort): 552 af de 553 nye personas har
en accepteret identitet, én er `unresolved` (omstridt binding). **6c-2 er i prod 2026-11-06** (ceremoni 1-4, tilstand
d): 1.106 af 1939's forslag er accepteret og bundet til eksisterende påstande, 83 påstande rettet efter bogen (70 i 3b,
13 i ceremoni 4), 25 forslag står tilbage (23 uden faktum, 2 uden identitet); kort 122 er `unresolved`. Vej B
(decisions 2026-10-29) er i prod med 6c-2's ceremoni 1. **6m del 1 er i prod 2026-11-07** (decisions 2026-11-06):
en model har holdt alle 592 poster og 2.774 forslag op mod bogens sidebilleder, og 268 af 1939's narrativer er
revideret med projektejerens 606 rettelser (`database-current-state.md` §21). **6m del 2 er i prod 2026-11-07** (decisions 2026-11-07, PR #303,
`database-current-state.md` §22): DDL 6m-a (`red_ret_forslag`) og data-ceremoni A har givet 93 af modellens
markerede forslag bogens læsning (VERSION 56, BIND 23, RET_OG_BIND 14), rettet 14 påstande efter bogen og bundet 37
afgørelser; bindinger 1.106 → 1.136, rettelser 83 → 97. Trin 6m er dermed afsluttet. **6c-3 er i prod 2026-11-08**
(PR #305/#307/#308, `database-current-state.md` §23, [færdigbevis](kildetekst-revision-6c3-prod.md)): A6b's kildetekst
og klausuler for 2018-20 er rettet med kildetekst-revisionen (10 tekstversioner, 58 nøgler forældet, 75 nye forslag),
og de 16 kildehenvisninger er kvitteret som 14 genbundet og 2 tilbagetrukket. Trin 6c er dermed afsluttet. **6d-1 er
i prod 2026-11-09** (PR #310, `database-current-state.md` §24, [færdigbevis](placement-6d1-prod.md)): 528 af 1939's
592 records er placeret med bogens egne koordinater, 528 linjemedlemskaber ligger på 1939-personerne, ledgeren har 528
`mapped` og 48 `retained_legacy`, og 441 `samme_som`-komponenter er bekræftet af begge udgaver (afledt B6). Læseren
viser 1939 fra legacy indtil 6e. 6d-2 er delt i 6d-2a og 6d-2b (decisions 2026-11-09). **6d-2a er i prod
2026-11-10** (PR #312, `database-current-state.md` §25): oversigtsreglen gælder i biografilæserne (en 1939-tekst, der
kun omtaler personen i en nedstigningsoversigt, vises ikke som biografi, når komponenten har detaljepersonens tekst),
`samme_som` får retning efter data, 1014 er koblet til 1048, og de tre sidste oversigtspersonas har identitet
(`unresolved` 1 → 0, uden identitet 2 → 0). Biografilæseren med alle personer blev 12,7 → ≈25 s (accepteret;
optimering udskudt til før projektets afslutning, decisions 2026-11-10). **6d-2b er i prod 2026-11-10** i indsnævret
form (decisions 2026-11-10, `database-current-state.md` §26): fire forkert tilskrevne 1939-tekster er trukket tilbage
(synlige 569 → 565); tekstrettelser, grænsefejl og afstemningswriterens fejl er kendte begrænsninger. **6d-3 er i
prod 2026-11-11** (PR #315, `database-current-state.md` §27): writerens profiler er data, og 1939's tekst foldes; 69
strukturelle bindinger for kilde 3 (68 ægteskaber, 46 maskinelt og 22 via kontrolkort, og 1 forælder); 42 `samme_som`
fjerner den dobbelte ægtefælle (42 → 0); 1791 og 1795 er private; kilde 1 uændret. 203 ægteskaber, 5 forældre og 4
børn står `proposed` med årsag (161 parkeret af navnereglen, 42 ikke egnede; børn kræver `relation-child-v1`). De 29
records uden narrativbinding har 0 relationsforslag. **6e-1 er i prod 2026-11-12, 6e-2 2026-11-14** (`database-current-state.md` §30: 561 1939-bindinger med læsbar etiket og trykt side, koordinatkaldet 1,26 → 0,31 s; [færdigbevis](laeserflade-6e2-prod.md)). De 30 »formodet«-forældreled: 28 rettet 2026-11-14, 79/80 bekræftet af bogens »?« (decisions). 2018-20's fødsler og dødsfald er bundet til bogens post 2026-11-12 (`database-current-state.md` §28: 509 bindinger; 59 `SKRIVEMAADE` står `proposed`, del 2 er ikke besluttet). Åben backlog fra 6d-3: en
1939-navneregel, hovedpersoner ukoblet mens ægtefællen er koblet (decisions 2026-11-11) og den fælles 5ab-runners
`profile_file`. **`record_persona` er i prod 2026-11-18** (PR #382, `database-current-state.md` §32): en ny generel
elementoperation giver en helpost uden tekstbinding en persona. Henriks (934) og Ivens (929) 1939-poster har fået
persona, identitet (kortark), placement, medlemskab og en kladde, som projektejeren har rettet og publiceret. Synlige
1939-tekster for anon er 554 → 555 (+2, og 944's omtale bliver oversigtsomtale). Fortrydelse af 598/603's
`legacy_withdrawn` er spærret, når personen har en record-binding i kilden. Samme DDL installerede personsletningens
kode (#369/#377/#380); den er siden taget i brug (#387) og har fået én sletteknap (P11, §45).

## Samlet dom

Kernen holder: evidenslaget, den generelle writer og klausullaget er bevist på den rigtige bog uden kanonisk delta.
Kæden kan **binde** det eksisterende til kilden, men har endnu ikke **oprettet** noget nyt på rigtige data (0 nye
fakta, 0 nye personer; review 2-01). Læseren ser nu personens fakta med kilde, og 622 af de 6.473 offentlige
fakta-rækker er bundet til bogens post (B11, målt 2026-10-29; datobindingerne 2026-11-12 har siden bundet 509 af 2018-20's fødsler og dødsfald). For 2018-20 er trin 1-5 i prod. For 1939 er proveniens,
narrativpublicering, klausuler, personas, identiteter, modellens forslag, 6c-2/6m's afgørelser og bindinger samt
6d-1's placements og medlemskaber, 6d-2a's oversigtsregel og identiteter, 6d-2b's tilbagetrækninger, 6d-3's
relationsbindinger og 6e's læserflade (6e-1 2026-11-12, 6e-2 2026-11-14) i prod.

## Modenhed pr. værdikædeled

Tilladte tilstande: `specificeret`, `isoleret implementeret`, `integreret ende-til-ende`, `produktionsverificeret`.
»Ikke påbegyndt« betyder, at ingen af dem gælder.

| Led | 2018-20 (kilde 1) | 1939 |
|---|---|---|
| Narrativ-record-kontrakt (#152) og generel writer (#153) | `produktionsverificeret` 2026-09-06 (kontrakt v2; gælder alle udgaver) | samme |
| Rendition, source records, forekomster, ankre | `produktionsverificeret` 2026-09-06 (149a: 591 records, nul kanonisk delta) | `produktionsverificeret` (læse-kun måling 2026-08-22; afgrænset 1939-leverance) |
| Narrativbinding og -publicering | `produktionsverificeret` 2026-09-06 (149b: 541 publicerede, 46 kladder; 4 `unresolved_text`: I-133, II-35, III-129, IV-94; A6b 2026-10-28: 10 narrativer revideret med de beskårne prosalinjer, kildeteksten følger i trin 6) | `produktionsverificeret` (C3 2026-08-29: 5 sager; afgrænset). Gælder begge udgaver: siden #130 (2026-11-22, §40) har 764 narrativer hændelser og kan først revideres, når redaktøren har fjernet dem (A2) |
| Klausuler | `produktionsverificeret` 2026-09-18, omsegmenteret 2026-09-28; uændret ved 6a (984 klausuler, 591 poster, hash `2c530d0a…`) | `produktionsverificeret` 2026-10-30 (6a, GO 6a-B `a0524bcd`: 912 klausuler på 584 helposter, profil `daa-1939-clause-evidence-v1`; 687 `afventer_fortolkning`, 225 `maskinelt_flagget`; 8 poster uden helpost; kanonisk lag uændret) |
| Kildetekst-revision (helpost-tekst rettes, afhængige fortolkninger forældes) | `produktionsverificeret` (6c-3 i prod 2026-11-08: 10 poster revideret, 16 bindinger kvitteret; [færdigbevis](kildetekst-revision-6c3-prod.md)) | samme generelle mekanisme som kilde 1 (deployet 2026-10-30 med 6a); bevidst ikke anvendt på 1939, fordi ingen 1939-helpost har krævet tekstrettelse (trin 6-spec'en §5: »bygget og bevist, men ikke anvendt på prod-data«). 6d-2b's tekstrettelser og grænsefejl er kendte begrænsninger og ville gå her og gennem grænserevision (B4) |
| Extractor-runner | `integreret ende-til-ende` (alle 488 tilladte poster kørt i restore 2026-10-01—03; resultatet overført) | `produktionsverificeret` 2026-11-02 (6c-1: de 500 `eligible` poster efter `exclusion-1939-v1` kørt lokalt 2026-11-01 med prompt 1.1.0, profil `daa-1939-v2`, `gpt-5.6-terra`; 92 udelukket; resultatet overført ved GO 6c1-B) |
| Forslag og afgørelse (trin 4) | `produktionsverificeret` 2026-10-05 (3.739 forslag, 676 afgørelser) | forslag `produktionsverificeret` 2026-11-02 (6c-1, GO 6c1-B `2a2ba22b`: 2.774 `proposed` på 494 poster, profil `daa-1939-interpretation-proposal-v1`; 433 klausuler `afventer_identitet`, 249 `fortolkning_foreslaaet`; kanonisk lag uændret). Afgørelse `produktionsverificeret` 2026-11-06 (6c-2's ceremoni 4: 1.106 accepteret, heraf 1.073 maskinelt efter klassifikationen; 25 står tilbage). 6m del 2 2026-11-07: 93 nye forslagsversioner med bogens læsning (`menneske-laesning-v1`), 37 afgørelser |
| Promotion — binding | `produktionsverificeret` (trin 4: 622 bindinger til eksisterende assertions 2026-10-05; 5b: relationsbindinger 2026-10-25/26). Datobindinger 2026-11-12 (GO n `50178e6e`, k `75ef1336`): 583 datoforslag, 565 nye versioner efter `dato-markoer-v2`, 509 fødsler og dødsfald accepteret og bundet (20 kort + 489 maskinelt), bindinger 1.759 → 2.268, 0 tabt; 59 `SKRIVEMAADE` står `proposed` ([færdigbevis](dato-bindinger-2018-20-prod.md)) | `produktionsverificeret` 2026-11-06 (6c-2: 1.106 bindinger til eksisterende påstande; 83 påstande rettet efter bogen). 6m del 2 2026-11-07: 1.136 bindinger, 97 påstande rettet |
| Promotion — oprettelse (nye fakta, personer, familier) | `isoleret implementeret` (kun syntetisk bevist; 0 på rigtige data) | — |
| Identitet (5a) | `produktionsverificeret` 2026-10-25 (GO 2) | personas `produktionsverificeret` 2026-11-01 (6b, GO 6b-B `1c8aade5`: 555 `source_persona` med hver sin `primary`-mention i egen helpost, profil `daa-1939-publication-v1`; skjult i webkøen). Identiteter `produktionsverificeret` 2026-11-02 (6b's C efter retning 2, GO 6c1-C `df185473`: 553 elementer, 454 `publication_binding` inkl. stikprøven 20/20, 98 `human` S, 1 `human` F → `unresolved`; `afventer=0`; `database-current-state.md` §20). 6d-2a 2026-11-10 (GO `fb102458`): tre oversigtspersonas fik identitet; `maal` viser `unresolved` 1 → 0 og uden identitet 2 → 0 (§25). 1939's personer med tom navnepåstand: 12 målt i prod 2026-11-18 (1795 slettet); 11 navngivet af projektejeren i Redaktion med kilde 2026-11-19; 1780 er bogens eget »(?)«; resten (1794's dobbelte »Greve«, indlæsningen må ikke skrive tomme navne) står i #388 |
| Relationer (5b): ægtefæller, børneflokke, ægteskabsnumre | `produktionsverificeret` 2026-10-25 (GO 2); dubletregel, #240 og #248 rettet 2026-10-26. Rettelsesvejen for numre (#244, `red_ret_aegteskabsnummer`) er `isoleret implementeret` (deployet, ubrugt): en reserve, fordi fejlen aldrig opstod i prod (decisions, »#244 opstod aldrig i prod«); kun som RPC, ingen app-flade | `produktionsverificeret` 2026-11-11 (6d-3, GO data `b43349c9`: profil `relation-persona-1939` som data med tekstfoldning; 115 elementer, 69 bindinger = 68 ægteskaber + 1 forælder; 42 D-`samme_som`; 203/5/4 står `proposed` pr. årsag; browsertjek som anon; §27) |
| Placement og membership (5c-1) | `produktionsverificeret` 2026-10-27 (GO 150 `3e69560f`: 580 placements, 1167 ledger-dispositioner, 576 memberships, 530 revalideringer). V-82..V-92 står `unresolved` | `produktionsverificeret` 2026-11-09 (6d-1, GO `79609895`: 528 record- og 528 persona-placements af 592 records, 138 overskrifter, ledger 528 `mapped` + 48 `retained_legacy`, 528 memberships, 528 revalideringer, 0 stale; B6 441 `corroborated`, 3 `conflict`; [færdigbevis](placement-6d1-prod.md)) |
| Læsere på placement/membership (5c-2) | `produktionsverificeret` 2026-10-29 (GO 5c2 `bb1678f9`: 1.113 koordinater, 530 fra placement, 583 legacy; diff mod legacy 37 felter = forventet, træparitet ok; browsertjek som anon) | `produktionsverificeret` 2026-11-14 (6e-2: 1939's koordinater fra placement med bogens nøgle og trykte side, 561 rækker med side, højeste 92; 0 `record-`/`legacy-source:` som anon; stikprøve 5/5 mod bogen; [færdigbevis](laeserflade-6e2-prod.md)) |
| Læserflade: fakta med kildehenvisning (B11) | `produktionsverificeret` 2026-10-29 (6.473 fakta-rækker over alle offentlige personer: 622 bundet til bogens post, 5.765 fra importen, 86 uden kilde; 0 bindinger falder ud; PostgREST-gate og browsertjek som anon). Læserkaldet koster op til ~1,9 s pr. person mod anons 3 s (vej B). 2026-11-12: kilde 1's fødsler med postens koordinat 67 → 334 og dødsfald 88 → 330 (datobindingerne); særskilt måling af de 10 tungeste 2018-20-personers fakta-kald: median ≤ 137 ms; browsertjek som anon || `produktionsverificeret` 2026-11-14 (6e-1 viser 1939's fakta som valgt udgave eller note; 6e-2: fakta-kilden med »DAA 1939, s. N«; bundne fakta (2.264) og offentlige biografier (1.100) uændrede; browsertjek som anon) |
| C3 reversal | — | `integreret ende-til-ende` (ikke udført i prod). C3's 5 sager (2026-08-29) er siden grundlag for 6a-6e's 1939-data; om reversal stadig kan køres uden at bryde dem, er ikke vurderet, så den regnes ikke for en tilgængelig fortrydelse |
| Trin 6 (1939 gennem kæden) | — | 6a i prod 2026-10-30; 6b's A og B i prod 2026-11-01; 6c-1 i prod 2026-11-02 (A, B og 6b's C efter retning 2); 6c-2 i prod 2026-11-06 (tilstand d); 6m del 1 i prod 2026-11-07 (268 narrativer revideret); 6m del 2 i prod 2026-11-07 (93 forslagsversioner, 14 påstandsrettelser, 37 bindinger); 6c-3 i prod 2026-11-08 (2018-20's A6b-rest: 14 genbundet, 2 tilbagetrukket); 6d-1 i prod 2026-11-09 (528 placements og medlemskaber); 6d-2a i prod 2026-11-10 (oversigtsregel, 1014 → 1048, 3 identiteter); 6d-2b i prod 2026-11-10 (indsnævret: 4 tekster trukket tilbage); 6d-3 i prod 2026-11-11 (69 relationsbindinger, 42 D-`samme_som`, 1791/1795 private); 6e-1 i prod 2026-11-12 (læseren viser valgt udgave forrest, [færdigbevis](laeserflade-6e1-prod.md)); 6e-2 i prod 2026-11-14 (1939's kildeetiket, trykte sider, koordinater; [færdigbevis](laeserflade-6e2-prod.md)) |
| Trin 7a, 7b | ikke påbegyndt; ingen spec | ikke påbegyndt |

## Gates før trin 6 (fra reviewet)

| | Handling | Status |
|---|---|---|
| A1 | `load_presens.R`: `--reset` fjernet, `--jeg-mener-det` krævet (1c-01) | gjort, gren `fix/review-trin-a` |
| A2 | De gamle loadere frosset ved kontrakt v2 (B5) | gjort, samme gren |
| A3 | RED-8 porteret til `schema.sql`, paritetsvagt, sekvens-verify (1b-01) | gjort, samme gren; verify-blokken grøn på en genskabt kopi af prod 2026-10-28 (db-verify køres ikke mod prod) |
| A4 | Styringsdokumenter afstemt (1a-01, 1a-14) | gjort, samme gren |
| A5 | C3-deployfil stoppet, røde R-tests arkiveret (1b-04, 1c-04/05) | gjort, samme gren |
| A6 | Projektejeren læser de 13 `NOISE_RE`-linjer mod kilden (1d.3a-03) | gjort: 12 er prosa, der mangler i teksten (decisions 2026-10-27) |
| A6b | `NOISE_RE` strammes, ny segmenteringsversion, de 12 linjer rettes ind i narrativer og klausuler i prod | gjort for narrativerne, i prod 2026-10-28 (GO a6b `5522a891`, PR #273; `database-current-state.md` §15): profil `2018-20-v2`, 10 narrativer revideret. Kildetekst og klausuler for de 10 poster i prod med 6c-3 2026-11-08 (`database-current-state.md` §23; I-84 parkeret) |
| B | Én DDL-ceremoni: 1d.3b-01, 1d.1-03, 1d.1-02, 1d.1-04 (mål cachen først) | gjort, i prod 2026-10-28 (GO trinb `33f99750`; `database-current-state.md` §14), merget (PR #272) |

## Restorepunkt og fortrydelse

**Ingen fortrydelse ved restore er åben.** Prod er skrevet i siden de seneste ceremoni-dumps (`record_persona`,
redaktionelle rettelser, hændelses-loadet, review 37), så en restore ville fjerne senere arbejde. Hver senere ændring
har sin egen fortrydelse uden restore (runner eller runbook, `database-current-state.md` §32-§46). `-laes`-dumpene fra
2026-11-18/20 er kilder til generalprøver, ikke restorepunkter. Seneste ceremoni-dumps: 6e-2's før-dump
`daa-prod-20261114085322-6e2.dump` (`331ac5b4…`) og ddl-dump `daa-prod-20261114100655-6e2.dump` (`b47fd30d…`), begge
`age`-krypteret på SFTP (rundtur ok). Før dem: datobindingernes n-dump `daa-prod-20261112220624-dato.dump` (sha
`96a3f303…`), ddl-dumpet `daa-prod-20261112212606-dato.dump` (`ef227696…`) og foer-dumpet
`daa-prod-20261112193719-dato.dump` (`a7add600…`). Før det: 6c-3's til 6d-3's dumps (`database-current-state.md` §23-§27). Ældre: dumpet mellem 6m del 2's DDL og ceremoni A, `daa-prod-20261107194057-6m2.dump` (sha
`76b5c7e9…`, `ddl_6ma=1`; `fortryd` og `fortryd-ddl` i runbook `trin6m-del2-prod.md`, kun indtil der skrives noget nyt
i prod); dumpet før DDL'en er `daa-prod-20261107190023-6m2.dump` (sha `8b2f1231…`). Før det: dumpet før 6m del 1's
ceremoni B, `daa-prod-20261107105651-6m.dump` (tilstand d). Før det: dumpet før 6c-2's ceremoni 4,
`daa-prod-20261106075122-6c2.dump` (tilstand c3b). Før 6c-2: dumpet før 6c-1's ceremoni B, `daa-prod-20261102060018-6c1.dump` (sha `fc15557a…`, tilstand
`a`; `database-current-state.md` §19); dumpet før 6c-1's ceremoni A er `daa-prod-20261101221444-6c1.dump` (sha
`198712b4…`). Fortrydelse sker efter gate 8 som omformuleret 2026-10-27 (B1): en særskilt handling eller restore inden
for et deklareret vindue. B1's betingelse er opfyldt for begge 6c-1-dumps: to kopier (lokalt og `age`-krypteret på
projektejerens SFTP-server, sha `3f871040…` og `1eff634a…`), begge hashes noteret, rundtur gennemført og
genkontrolleret ved skrivningen. 6b's ceremoni C har skrevet, så 6c-1's forslag kan ikke længere fortrydes ved
restore af B-dumpet. C selv fortrydes uden restore med `reverse-c` (identiteterne `superseded`, tilstand `b`), og
retning 2's DDL derefter særskilt med `fortryd-ddl` (runbook `trin6c1-prod.md`, Fortrydelse af C). 6c-1's DDL fra A
fortrydes ikke alene, efter at B har skrevet. 6b-B's restore-fortrydelse
er lukket, fordi forslagene refererer 6b's personas; 6b's og 6a's dumps ville nu også fjerne 6c-1. 5c-2 + B11
fortrydes uden restore (revert af klient-PR #277; funktionerne bliver stående, ingen data er skrevet). A6b fortrydes
ligeledes uden restore (`apply --tilbage`, ny revision tilbage til den gamle tekst); trin B's fire funktioner
ligeledes (runbookens opskrift).

## Parkeret

Spor H og M, C1/C2, DNA, mediefase 5 og flersproget. 1939's 16 `[NY]`-records er ikke længere bare parkeret: de er
første rigtige prøve af opret-benet (B4), efter trin 6.

## Bevisgrundlag

- [Vision](vision.md), [roadmap](roadmap.md), [teknisk målarkitektur](teknisk-maalarkitektur.md).
- Helhedsreview trin 1-5: [`docs/reviews/2026-10-27-trin-1-5/`](../reviews/2026-10-27-trin-1-5/rapport.md).
- Prod-tilstand og ceremonier: [`docs/database-current-state.md`](../database-current-state.md).
- Bevisrapporter pr. trin står i denne mappe (149a/149b-rehearsal, `2018-20-fuld-koersel.md`,
  `identitetsvej-5a-bevis.md`, `relationspersonas-5b-*-bevis.md`, `aegteskabsnumre-244-bevis.md`).
- Historiske specs, planer og reviews er historik, ikke aktuel status. Levende kode og schema er source of truth for
  tekniske detaljer.

## Opdateringsregel

1. Dokumentet er **ét snapshot**. Det overskrives ved hvert trinskifte og hver prod-ændring. Tillæg er ikke tilladt;
   historikken står i `docs/changelog.md` og git.
2. »Aktivt programmål« er én kort sektion og skal sige det samme som roadmappets »Aktivt programmål«.
3. En tilstand angives altid med udgave og led. Modenhed hæves kun med konkret, dateret bevis; ellers bevares den
   lavere klassifikation.
