# Evidensbaseret genimport — aktuel status

**Snapshot 2026-11-01**, efter trin 6b's ceremoni A og B i prod (efter 6a, 5c-2 + B11, A6b, reviewets trin B, trin 5c-1 og helhedsreviewet
af trin 1-5, [rapport](../reviews/2026-10-27-trin-1-5/rapport.md)). Dokumentet **overskrives** ved hvert trinskifte og hver
prod-ændring; der skrives ikke tillæg (opdateringsreglen nederst). Det gamle dokument med tillæg til og med
2026-10-27 står i [status-arkiv-til-2026-10-27.md](status-arkiv-til-2026-10-27.md).

## Aktivt programmål

**Trin 6-spec'en:** 1939 gennem de samme operationer som 2018-20 (roadmap trin 6, færdigbevis a-c), opdelt i
delspecs 6a-6e ([spec](../superpowers/specs/2026-10-29-trin6-1939-gennem-kaeden-design.md) §5). **6a er i prod
2026-10-30:** 1939's klausuler er skrevet, og kildetekst-revisionen er bygget og bevist, men ikke anvendt på prod-data.
**6b's ceremoni A og B er i prod 2026-11-01:** 1939's 555 personas er skrevet, men har endnu
ingen identitet. Ceremoni C (identiteterne) kræver, at 6c's runner har kørt; 6c er næste delspec. A6b's kildetekst og klausuler for 2018-20 (decisions 2026-10-28) og vej B (decisions
2026-10-29) ligger i 6c.

## Samlet dom

Kernen holder: evidenslaget, den generelle writer og klausullaget er bevist på den rigtige bog uden kanonisk delta.
Kæden kan **binde** det eksisterende til kilden, men har endnu ikke **oprettet** noget nyt på rigtige data (0 nye
fakta, 0 nye personer; review 2-01). Læseren ser nu personens fakta med kilde, og 622 af de 6.473 offentlige
fakta-rækker er bundet til bogens post (B11). For 2018-20 er trin 1-5 i prod. For 1939 er proveniens,
narrativpublicering, klausuler og personas i prod; resten er 6b's identiteter og trin 6c-6e.

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
| Extractor-runner | `integreret ende-til-ende` (alle 488 tilladte poster kørt i restore 2026-10-01—03; resultatet overført) | ikke påbegyndt |
| Forslag og afgørelse (trin 4) | `produktionsverificeret` 2026-10-05 (3.739 forslag, 676 afgørelser) | ikke påbegyndt |
| Promotion — binding | `produktionsverificeret` (trin 4: 622 bindinger til eksisterende assertions 2026-10-05; 5b: relationsbindinger 2026-10-25/26) | ikke påbegyndt |
| Promotion — oprettelse (nye fakta, personer, familier) | `isoleret implementeret` (kun syntetisk bevist; 0 på rigtige data) | — |
| Identitet (5a) | `produktionsverificeret` 2026-10-25 (GO 2) | personas `produktionsverificeret` 2026-11-01 (6b, GO 6b-B `1c8aade5`: 555 `source_persona` med hver sin `primary`-mention i egen helpost, profil `daa-1939-publication-v1`; skjult i webkøen). Identiteter (ceremoni C): `isoleret implementeret` (deployet ved 6b-A, ubrugt; venter på 6c's runner) |
| Relationer (5b): ægtefæller, børneflokke, ægteskabsnumre | `produktionsverificeret` 2026-10-25 (GO 2); dubletregel, #240 og #248 rettet 2026-10-26. Rettelsesvejen for numre (#244) er `isoleret implementeret` (deployet, ubrugt) | ikke påbegyndt |
| Placement og membership (5c-1) | `produktionsverificeret` 2026-10-27 (GO 150 `3e69560f`: 580 placements, 1167 ledger-dispositioner, 576 memberships, 530 revalideringer). V-82..V-92 står `unresolved` | ikke påbegyndt (trin 6) |
| Læsere på placement/membership (5c-2) | `produktionsverificeret` 2026-10-29 (GO 5c2 `bb1678f9`: 1.113 koordinater, 530 fra placement, 583 legacy; diff mod legacy 37 felter = forventet, træparitet ok; browsertjek som anon) | — (kilde 3 vises fra legacy indtil trin 6) |
| Læserflade: fakta med kildehenvisning (B11) | `produktionsverificeret` 2026-10-29 (6.473 fakta-rækker over alle offentlige personer: 622 bundet til bogens post, 5.765 fra importen, 86 uden kilde; 0 bindinger falder ud; PostgREST-gate og browsertjek som anon). Læserkaldet koster op til ~1,9 s pr. person mod anons 3 s (vej B) | — |
| C3 reversal | — | `integreret ende-til-ende` (ikke udført i prod) |
| Trin 6 (1939 gennem kæden) | — | 6a i prod 2026-10-30; 6b's A og B i prod 2026-11-01 (C venter på 6c); 6c-6e ikke påbegyndt |
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
| A6b | `NOISE_RE` strammes, ny segmenteringsversion, de 12 linjer rettes ind i narrativer og klausuler i prod | gjort for narrativerne, i prod 2026-10-28 (GO a6b `5522a891`, PR #273; `database-current-state.md` §15): profil `2018-20-v2`, 10 narrativer revideret. Kildetekst og klausuler for de 11 poster følger i 6c (decisions 2026-10-28; mekanismen bygget i 6a, I-84 parkeret) |
| B | Én DDL-ceremoni: 1d.3b-01, 1d.1-03, 1d.1-02, 1d.1-04 (mål cachen først) | gjort, i prod 2026-10-28 (GO trinb `33f99750`; `database-current-state.md` §14), merget (PR #272) |

## Restorepunkt og fortrydelse

Seneste restorepunkt: dumpet før 6b's ceremoni B, `daa-prod-20261101122034-6b.dump` (sha `56f9a466…`, tilstand `a`;
`database-current-state.md` §18); dumpet før 6b's ceremoni A er `daa-prod-20261101112742-6b.dump` (sha `075213af…`).
Fortrydelse sker efter gate 8 som omformuleret 2026-10-27 (B1): en særskilt handling eller restore inden for et
deklareret vindue. B1's betingelse er opfyldt for begge 6b-dumps: to kopier (lokalt og `age`-krypteret på
projektejerens SFTP-server, sha `56f905df…` og `7bf2937d…`), begge hashes noteret, rundtur gennemført og
genkontrolleret ved skrivningen. 6b's personas fortrydes kun ved `fortryd-b` (restore af B-dumpet), så længe intet
andet er skrevet siden dumpet og 6c's runner ikke har skrevet; skrivepausen sluttede ved godkendelsen af B. 6b's DDL
med de tidligere funktionskroppe fra A-dumpet (runbook `trin6b-prod.md`, Fortrydelse). 6a's dumps
(`daa-prod-20261030221325-6a.dump`, `…194417-6a.dump`) ville nu også fjerne 6b. 5c-2 + B11 fortrydes uden restore (revert af klient-PR #277; funktionerne bliver
stående, ingen data er skrevet). A6b fortrydes ligeledes uden restore (`apply --tilbage`, ny revision tilbage til den
gamle tekst); trin B's fire funktioner ligeledes (runbookens opskrift).

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
