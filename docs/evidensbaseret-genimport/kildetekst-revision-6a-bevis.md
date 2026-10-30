# Kildetekst-revisionen på stand-in (trin 6a, Task 15) — anvendes ikke i prod

Bevis for spec §8 »Stand-in« (`docs/superpowers/specs/2026-10-29-trin6a-klausuler-og-kildetekst-revision-design.md`):
revisionen af 2018-20's A6b-poster kørt gennem hele writer-kæden på en kopi af prod. Revisionen anvendes **ikke** i
prod i 6a. Første brug er 6c's samlede ceremoni (revision, genkørsel og genbinding), med et frisk dump lige før.
Kun antal, nøgletyper og hashes er gengivet. Ingen posttekst.

## Base

`daa5ab_ddl_standin_20261030150000_6aa` består af:
- 5c-2-dumpet (`0e988082…`);
- 5c-2-blokken og `db-rls.sql`, så basen er prod-ækvivalent (`C2B11_MAAL_OK tilstand=efter`, `C2B11_DIFF n=37 ens`);
- ceremoni A (hele `db-migrations.sql` ×2 + `db-rls.sql`, `main` 4dc21226).

Basen er en kopi (`createdb -T`) og arvede derfor ikke prods `statement_timeout='2min'`. Hele revisionen tog 0,5 s,
så grænsen pr. sætning var ikke i nærheden af at blive ramt.

## Trin 1 — manifestet

| | Målt | Forventet (spec/plan) |
|---|---|---|
| Kandidater (posttekst forskellig under v1 og v2's sidehovedregel) | 11 | 11 A6b-poster |
| Operationer | 10 | 10 |
| `dispositions` | `I-84: span_outside` | `[I-84: span_outside]` |
| Klausuler i de nye sæt | 20 | — |
| Forventede forældede nøgler | 58 | 58 |
| Forventet bindingstab | 16: 9 `assertion`, 7 `family` | 16: 9 + 7 |

Klausuleksporten (`--helpost-kind person_post`) gav 591 helposter og 0 uden helpost. Renditionens sha er
`2dd5cf84…`, og afhængighedsfilen er målt med `source_text_revision_dependencies.sql` i ét læse-snapshot.

## Trin 2-3 — før og efter anvendelsen

Kæden: dry-run (`finalized`, intet skrevet) → authorize som `service_role` → apply (`finalized`, `committed`, 0,5 s,
ét kald pr. post) → replay (`already_applied`).

| Måling (personerne bag de 16 promotions) | Før | Efter |
|---|---|---|
| Promotions: assertion / family | 9 / 7 | 9 / 7 |
| Personer med de 9 fakta | 5 | 5 |
| De 9 fakta »bundet til bogens post« | 9 | 0 |
| De 9 fakta »fra den oprindelige import« | 0 | 9 |
| Fakta i alt for de 5 personer (`public_person_facts`) | 26 | 26 |
| Familiekilder for de 7 familier (`public_family_sources`) | 7 | 0 |
| `public.narrative`, hash over alle rækker | `e80d8e8b…` | `e80d8e8b…` |
| `private.narrative_record_publication`, hash over alle rækker | `c93d7479…` | `c93d7479…` |

Desuden:
- 10 `source_text_revision`-hændelser;
- foreningsmængden af kvitteringernes `binding_loss` er præcis de 16 forventede promotions (0 ekstra, 0 mangler);
- 58 fortolkninger er `superseded` med basis `source_text_revision`;
- 10 tekstversioner er skrevet.

Narrativ-hashene er taget over hele tabellerne, ikke kun de 10 poster, og er uændrede. Det er derfor et stærkere
bevis end kravet. De 9 fakta og de 7 familiekilder falder ud som forventet, indtil 6c genbinder.

## Trin 4 — genkørsel

I én transaktion, der blev rullet tilbage, blev et nyt forslag sendt gennem forslags-writerens fulde kæde med den
rigtige profil `daa-2018-20-interpretation-proposal-v1`. Forslaget gjaldt én af de forældede property-fortolkninger
og havde samme prædikat og værdi og samme klausulordinal i det nye sæt. Resultat:

`GENKOERSEL_OK key_version=2 text_version=1 ny_noegle_ulig_gammel=t status_ny=proposed`

S4-åbningen virker altså på rigtige data. Den nye nøgle er bundet til tekstversion 1 og er forskellig fra den
forældede. At S4 stadig spærrer for ikke-reviderede poster, er bevist i CI
(`tests/sql/test-interpretation-proposal-rerun.sql`).

## Forslagsnøglerne efter revisionen (R13-d)

Forslagsprojektionen (`interpretation_proposal_projection.psql`, kilde 1) genberegner hver kvitteret nøgle med
kvitteringens version:

| Base | Rækker med `key_matches` | heraf `false` |
|---|---|---|
| A + B, ingen revision (`…_6ar`) | 4.681 | 0 |
| A + revision (`…_6aa`) | 4.739 (+ de 58 forældede versioner) | 0 |

Komparatorens krav om historiske nøgler gør altså ikke en ceremoni rød på prods data. Målingen gentages før 6c's
ceremoni på et frisk dump.

## Komparatoren gennem den gældende helposttekst

Punktet udgår med begrundelse (spec §8 tillader det). Inventeringen (Task 7/13, R13-a) flyttede ikke
klausul-projektionen til `helpost_text_current`. Den hasher den tekst, *klausulens sæt* er skåret af
(`parent_text_id`, ellers basisteksten). Revisionens nye sæt er bundet til den nye tekstversion, og de gamle sæt til
basisteksten. Hvert sæt er derfor konsistent med sin egen tekst, uden at komparatoren skal se den gældende tekst.

## Ikke dækket her

- **I-84** er parkeret (projektejeren, 2026-10-29) og står som disposition, ikke som operation.
- **6c's genbinding** af de 16 og genkørsel af fortolkningerne hører til 6c's ceremoni.
