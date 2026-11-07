# Evidensbaseret genimport — aktuel status

**Snapshot 2026-11-07**, efter 6m del 1 i prod (læsertekst rettet efter bogen) og 6c-2's ceremoni 4 (efter 6c-1, 6b's A, B og C, 6a, 5c-2 + B11, A6b, reviewets trin B, trin 5c-1 og helhedsreviewet
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
revideret med projektejerens 606 rettelser (`database-current-state.md` §21). **6m del 2 er i gang** (decisions 2026-11-07): plan og værktøj
bygget på gren `feat/trin6m-del2` (A-kort, flet, `red_ret_forslag`), ikke i prod; prod-ceremonierne afventer. Næste: frisk prod-kopi og øvelse på stand-in, projektejerens samlede F og foreløbigt 14 kort, derefter ceremonierne (DDL 6m-a, så data). De 13 ubundne narrativer
og 39 tekstrettelser uden læsertekst er flyttet til 6d. A6b's kildetekst og klausuler for 2018-20 (decisions
2026-10-28) ligger i 6c-3 (decisions 2026-11-02).

## Samlet dom

Kernen holder: evidenslaget, den generelle writer og klausullaget er bevist på den rigtige bog uden kanonisk delta.
Kæden kan **binde** det eksisterende til kilden, men har endnu ikke **oprettet** noget nyt på rigtige data (0 nye
fakta, 0 nye personer; review 2-01). Læseren ser nu personens fakta med kilde, og 622 af de 6.473 offentlige
fakta-rækker er bundet til bogens post (B11). For 2018-20 er trin 1-5 i prod. For 1939 er proveniens,
narrativpublicering, klausuler, personas, identiteter og modellens forslag i prod; resten er 6c-2, 6c-3 og trin 6d-6e.

## Modenhed pr. værdikædeled

Tilladte tilstande: `specificeret`, `isoleret implementeret`, `integreret ende-til-ende`, `produktionsverificeret`.
»Ikke påbegyndt« betyder, at ingen af dem gælder.

| Led | 2018-20 (kilde 1) | 1939 |
|---|---|---|
| Narrativ-record-kontrakt (#152) og generel writer (#153) | `produktionsverificeret` 2026-09-06 (kontrakt v2; gælder alle udgaver) | samme |
| Rendition, source records, forekomster, ankre | `produktionsverificeret` 2026-09-06 (149a: 591 records, nul kanonisk delta) | `produktionsverificeret` (læse-kun måling 2026-08-22; afgrænset 1939-leverance) |
| Narrativbinding og -publicering | `produktionsverificeret` 2026-09-06 (149b: 541 publicerede, 46 kladder; 4 `unresolved_text`: I-133, II-35, III-129, IV-94; A6b 2026-10-28: 10 narrativer revideret med de beskårne prosalinjer, kildeteksten følger i trin 6) | `produktionsverificeret` (C3 2026-08-29: 5 sager; afgrænset) |
| Klausuler | `produktionsverificeret` 2026-09-18, omsegmenteret 2026-09-28; uændret ved 6a (984 klausuler, 591 poster, hash `2c530d0a…`) | `produktionsverificeret` 2026-10-30 (6a, GO 6a-B `a0524bcd`: 912 klausuler på 584 helposter, profil `daa-1939-clause-evidence-v1`; 687 `afventer_fortolkning`, 225 `maskinelt_flagget`; 8 poster uden helpost; kanonisk lag uændret) |
| Kildetekst-revision (helpost-tekst rettes, afhængige fortolkninger forældes) | `isoleret implementeret` (6a: deployet 2026-10-30, ubrugt; første brug er A6b-resten i 6c) | samme |
| Extractor-runner | `integreret ende-til-ende` (alle 488 tilladte poster kørt i restore 2026-10-01—03; resultatet overført) | `produktionsverificeret` 2026-11-02 (6c-1: de 500 `eligible` poster efter `exclusion-1939-v1` kørt lokalt 2026-11-01 med prompt 1.1.0, profil `daa-1939-v2`, `gpt-5.6-terra`; 92 udelukket; resultatet overført ved GO 6c1-B) |
| Forslag og afgørelse (trin 4) | `produktionsverificeret` 2026-10-05 (3.739 forslag, 676 afgørelser) | forslag `produktionsverificeret` 2026-11-02 (6c-1, GO 6c1-B `2a2ba22b`: 2.774 `proposed` på 494 poster, profil `daa-1939-interpretation-proposal-v1`; 433 klausuler `afventer_identitet`, 249 `fortolkning_foreslaaet`; kanonisk lag uændret). Afgørelse `produktionsverificeret` 2026-11-06 (6c-2's ceremoni 4: 1.106 accepteret, heraf 1.073 maskinelt efter klassifikationen; 25 står tilbage) |
| Promotion — binding | `produktionsverificeret` (trin 4: 622 bindinger til eksisterende assertions 2026-10-05; 5b: relationsbindinger 2026-10-25/26) | `produktionsverificeret` 2026-11-06 (6c-2: 1.106 bindinger til eksisterende påstande; 83 påstande rettet efter bogen) |
| Promotion — oprettelse (nye fakta, personer, familier) | `isoleret implementeret` (kun syntetisk bevist; 0 på rigtige data) | — |
| Identitet (5a) | `produktionsverificeret` 2026-10-25 (GO 2) | personas `produktionsverificeret` 2026-11-01 (6b, GO 6b-B `1c8aade5`: 555 `source_persona` med hver sin `primary`-mention i egen helpost, profil `daa-1939-publication-v1`; skjult i webkøen). Identiteter `produktionsverificeret` 2026-11-02 (6b's C efter retning 2, GO 6c1-C `df185473`: 553 elementer, 454 `publication_binding` inkl. stikprøven 20/20, 98 `human` S, 1 `human` F → `unresolved`; `afventer=0`; `database-current-state.md` §20). 13 af 1939's personer mangler navn (tom navnepåstand), rettes efter C |
| Relationer (5b): ægtefæller, børneflokke, ægteskabsnumre | `produktionsverificeret` 2026-10-25 (GO 2); dubletregel, #240 og #248 rettet 2026-10-26. Rettelsesvejen for numre (#244) er `isoleret implementeret` (deployet, ubrugt) | ikke påbegyndt |
| Placement og membership (5c-1) | `produktionsverificeret` 2026-10-27 (GO 150 `3e69560f`: 580 placements, 1167 ledger-dispositioner, 576 memberships, 530 revalideringer). V-82..V-92 står `unresolved` | ikke påbegyndt (trin 6) |
| Læsere på placement/membership (5c-2) | `produktionsverificeret` 2026-10-29 (GO 5c2 `bb1678f9`: 1.113 koordinater, 530 fra placement, 583 legacy; diff mod legacy 37 felter = forventet, træparitet ok; browsertjek som anon) | — (kilde 3 vises fra legacy indtil trin 6) |
| Læserflade: fakta med kildehenvisning (B11) | `produktionsverificeret` 2026-10-29 (6.473 fakta-rækker over alle offentlige personer: 622 bundet til bogens post, 5.765 fra importen, 86 uden kilde; 0 bindinger falder ud; PostgREST-gate og browsertjek som anon). Læserkaldet koster op til ~1,9 s pr. person mod anons 3 s (vej B) | — |
| C3 reversal | — | `integreret ende-til-ende` (ikke udført i prod) |
| Trin 6 (1939 gennem kæden) | — | 6a i prod 2026-10-30; 6b's A og B i prod 2026-11-01; 6c-1 i prod 2026-11-02 (A, B og 6b's C efter retning 2); 6c-2 i prod 2026-11-06 (tilstand d); 6m del 1 i prod 2026-11-07 (268 narrativer revideret); 6m del 2 i gang (plan og værktøj bygget på gren feat/trin6m-del2; ikke i prod); 6c-3 og 6d-6e ikke påbegyndt |
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
| A6b | `NOISE_RE` strammes, ny segmenteringsversion, de 12 linjer rettes ind i narrativer og klausuler i prod | gjort for narrativerne, i prod 2026-10-28 (GO a6b `5522a891`, PR #273; `database-current-state.md` §15): profil `2018-20-v2`, 10 narrativer revideret. Kildetekst og klausuler for de 11 poster følger i 6c-3 (decisions 2026-10-28 og 2026-11-02; mekanismen bygget i 6a, I-84 parkeret) |
| B | Én DDL-ceremoni: 1d.3b-01, 1d.1-03, 1d.1-02, 1d.1-04 (mål cachen først) | gjort, i prod 2026-10-28 (GO trinb `33f99750`; `database-current-state.md` §14), merget (PR #272) |

## Restorepunkt og fortrydelse

Seneste restorepunkt: dumpet før 6m del 1's ceremoni B, `daa-prod-20261107105651-6m.dump` (tilstand d; fortrydelse
i runbook `trin6m-del1-prod.md`, kun indtil der skrives noget nyt i prod). Før det: dumpet før 6c-2's ceremoni 4,
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
