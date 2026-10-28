# Evidensbaseret genimport — aktuel status

**Snapshot 2026-10-28**, efter reviewets trin B i prod (efter trin 5c-1 og helhedsreviewet af trin 1-5,
[rapport](../reviews/2026-10-27-trin-1-5/rapport.md)). Dokumentet **overskrives** ved hvert trinskifte og hver
prod-ændring; der skrives ikke tillæg (opdateringsreglen nederst). Det gamle dokument med tillæg til og med
2026-10-27 står i [status-arkiv-til-2026-10-27.md](status-arkiv-til-2026-10-27.md).

## Aktivt programmål

**Trin 5 (#150/#151), sidste del:** 5c-2 (læserskift) sammen med læserværdien fra B11. Reviewets trin A og B er gjort
(B i prod 2026-10-28); tilbage er A6b. Derefter skrives trin 6-spec'en. Rækkefølge og
indhold: [rapport §6](../reviews/2026-10-27-trin-1-5/rapport.md); beslutningerne: `docs/decisions.md` 2026-10-27 (B1-B13).

## Samlet dom

Kernen holder: evidenslaget, den generelle writer og klausullaget er bevist på den rigtige bog uden kanonisk delta.
Kæden kan **binde** det eksisterende til kilden, men har endnu ikke **oprettet** noget nyt på rigtige data (0 nye
fakta, 0 nye personer; review 2-01), og læseren ser kun familiernes kildelinje (1a-03). For 2018-20 er trin 1-5c-1
i prod. For 1939 er kun proveniens og narrativpublicering i prod; resten er trin 6.

## Modenhed pr. værdikædeled

Tilladte tilstande: `specificeret`, `isoleret implementeret`, `integreret ende-til-ende`, `produktionsverificeret`.
»Ikke påbegyndt« betyder, at ingen af dem gælder.

| Led | 2018-20 (kilde 1) | 1939 |
|---|---|---|
| Narrativ-record-kontrakt (#152) og generel writer (#153) | `produktionsverificeret` 2026-09-06 (kontrakt v2; gælder alle udgaver) | samme |
| Rendition, source records, forekomster, ankre | `produktionsverificeret` 2026-09-06 (149a: 591 records, nul kanonisk delta) | `produktionsverificeret` (læse-kun måling 2026-08-22; afgrænset 1939-leverance) |
| Narrativbinding og -publicering | `produktionsverificeret` 2026-09-06 (149b: 541 publicerede, 46 kladder; 4 `unresolved_text`: I-133, II-35, III-129, IV-94) | `produktionsverificeret` (C3 2026-08-29: 5 sager; afgrænset) |
| Klausuler | `produktionsverificeret` 2026-09-18, omsegmenteret 2026-09-28 | ikke påbegyndt (ingen `clause_rules` i 1939-profilen) |
| Extractor-runner | `integreret ende-til-ende` (alle 488 tilladte poster kørt i restore 2026-10-01—03; resultatet overført) | ikke påbegyndt |
| Forslag og afgørelse (trin 4) | `produktionsverificeret` 2026-10-05 (3.739 forslag, 676 afgørelser) | ikke påbegyndt |
| Promotion — binding | `produktionsverificeret` (trin 4: 622 bindinger til eksisterende assertions 2026-10-05; 5b: relationsbindinger 2026-10-25/26) | ikke påbegyndt |
| Promotion — oprettelse (nye fakta, personer, familier) | `isoleret implementeret` (kun syntetisk bevist; 0 på rigtige data) | — |
| Identitet (5a) | `produktionsverificeret` 2026-10-25 (GO 2) | ikke påbegyndt |
| Relationer (5b): ægtefæller, børneflokke, ægteskabsnumre | `produktionsverificeret` 2026-10-25 (GO 2); dubletregel, #240 og #248 rettet 2026-10-26. Rettelsesvejen for numre (#244) er `isoleret implementeret` (deployet, ubrugt) | ikke påbegyndt |
| Placement og membership (5c-1) | `produktionsverificeret` 2026-10-27 (GO 150 `3e69560f`: 580 placements, 1167 ledger-dispositioner, 576 memberships, 530 revalideringer). V-82..V-92 står `unresolved` | ikke påbegyndt (trin 6) |
| Læsere på placement/membership (5c-2) | ikke påbegyndt | — |
| Læserflade: fakta med kildehenvisning (B11) | ikke påbegyndt. Familiernes kildelinje i `DetailPanel` findes (5b 2a) | — |
| C3 reversal | — | `integreret ende-til-ende` (ikke udført i prod) |
| Trin 6 (1939 gennem kæden), 7a, 7b | ikke påbegyndt; ingen spec | ikke påbegyndt |

## Gates før trin 6 (fra reviewet)

| | Handling | Status |
|---|---|---|
| A1 | `load_presens.R`: `--reset` fjernet, `--jeg-mener-det` krævet (1c-01) | gjort, gren `fix/review-trin-a` |
| A2 | De gamle loadere frosset ved kontrakt v2 (B5) | gjort, samme gren |
| A3 | RED-8 porteret til `schema.sql`, paritetsvagt, sekvens-verify (1b-01) | gjort, samme gren; verify-blokken grøn på en genskabt kopi af prod 2026-10-28 (db-verify køres ikke mod prod) |
| A4 | Styringsdokumenter afstemt (1a-01, 1a-14) | gjort, samme gren |
| A5 | C3-deployfil stoppet, røde R-tests arkiveret (1b-04, 1c-04/05) | gjort, samme gren |
| A6 | Projektejeren læser de 13 `NOISE_RE`-linjer mod kilden (1d.3a-03) | gjort: 12 er prosa, der mangler i teksten (decisions 2026-10-27) |
| A6b | `NOISE_RE` strammes, ny segmenteringsversion, de 12 linjer rettes ind i narrativer og klausuler i prod | åben, kræver plan og GO |
| B | Én DDL-ceremoni: 1d.3b-01, 1d.1-03, 1d.1-02, 1d.1-04 (mål cachen først) | gjort, i prod 2026-10-28 (GO trinb `33f99750`; `database-current-state.md` §14). Grenen er ikke merget |

## Restorepunkt og fortrydelse

Seneste restorepunkt: dumpet før trin B, `daa-prod-20261028184913-trinb.dump` (sha `e253f352…`;
`database-current-state.md` §14). Fortrydelse sker efter gate 8 som omformuleret 2026-10-27 (B1): en særskilt
handling eller restore inden for et deklareret vindue. B1's betingelse er opfyldt for dette dump: to kopier (lokalt og
`age`-krypteret på projektejerens SFTP-server, sha `0e5bc17f…`), begge hashes noteret, rundtur og prøvegendannelse
gennemført før skrivningen. Trin B's fire funktioner fortrydes uden restore (runbookens opskrift).

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
