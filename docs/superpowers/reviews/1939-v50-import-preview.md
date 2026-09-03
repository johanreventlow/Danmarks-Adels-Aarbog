# DAA 1939 v50 import-preview — resultat

**Dato:** 2026-08-17

**Udfald:** Lokal preview er komplet og reproducerbar. Den aktuelle database er
sammenlignet i en verificeret read-only transaktion. Dry-run og reimport er
fortsat `NO-GO`, fordi det private source-recordlag mangler i produktion og
flere identitets-/provenanceklasser kræver afklaring.

## Sikkerhedsgrænse

- Den gamle `load_daa.R` blev hverken ændret eller kaldt.
- Supabase-sessionen brugte `BEGIN READ ONLY` og verificerede
  `transaction_read_only=on` på PostgreSQL 17.6.
- SQL-adapteren accepterer kun den lukkede read-only grammar; transaction
  pooler-port 6543 afvises.
- Ingen canonical person-create/update/delete er autoriseret.
- Ingen database-, migration-, RPC-, temp-table- eller loader-skrivning blev
  udført.

## Lokal v50-konvertering

Kilderegnskabet er komplet:

- 592 materialiserede source records;
- 543 aktive baseline-to-source-record mappings;
- 3 pensionerede legacy records;
- 41 genuinely-new source records med forbud mod personoprettelse;
- 6 structural-context og 2 cross-reference source-only records.

Legacy payload mod v50-verbatim:

| Klasse | Literal | Manglende span | Ikke-literal | Pensioneret |
|---|---:|---:|---:|---:|
| Facts | 1.078 | 38 | 92 | 1 |
| Ægteskaber | 212 | 38 | 56 | 2 |

Derudover kræver 81 børne-/strukturrelationer særskilt positiv
source-validering. Narrativerne er 478 ændrede, 65 uændrede og 3 pensionerede.
Ingen af kandidaterne er en skriveordre.

## Aktuel database

Personankrene for den aktive v50-baseline er stærke:

- 543/543 matcher præcis én eksisterende `person_external_id`;
- 0 mangler;
- 0 kollisioner;
- de 3 pensionerede legacy records findes stadig i databasen;
- 23 yderligere eksisterende DAA 1939-personposter har ingen v50-baseline-
  mapping og skal bevares, indtil deres relation til de 41 genuinely-new
  source records er afgjort.

De 23 er listet med stabile record keys, person-id, navn, staged-status og
antal narrativer/facts/family-members i det private database-preview-artefakt.
De må ikke fortolkes som slettekandidater.

Narrativer:

- 0 inserts;
- 478 tekstforskelle;
- 65 uændrede;
- 0 kollisioner;
- 0 med `red_*`-ændringsspor.

Facts:

- 2.175 eksisterende facts på de berørte personer;
- 2.172 har DAA 1939-citation og intet `red_*`-spor;
- 3 har hverken DAA 1939-citation eller `red_*`-spor;
- previewet har 1.078 literal-kvalificerede kandidater og 131 parkerede inkl.
  den pensionerede fact.

Den store forskel mellem preview-fact-count og database-fact-count er ikke
fortolket som deletes. En senere writer skal sammenligne assertion-værdier og
slots, ikke kun faktatype eller rå antal.

Relationer:

- 803 generiske relationer og 689 family-member-kanter berører personerne;
- 320 relationer er DAA 1939-citerede uden `red_*`-spor;
- 480 har `red_*`-spor uden DAA 1939-citation;
- 3 har hverken source-citation eller redaktionelt spor;
- roller: 320 `ejer`, 476 `samme_som`, 5 `ikke_samme_som`, 2 `afbildet`.

De 480 redaktionelle relationer må aldrig erstattes af et source-scoped load.
Previewets 212 literal-kvalificerede ægteskaber, 96 parkerede ægteskaber og 81
pending børnerelationer er fortsat kandidater, ikke mutationsbeslutninger.

## Capability-gap

Den aktuelle database mangler `private.source_record`-kolonnerne
`source_id`, `record_key` og `record_kind` (tabellen er ikke installeret eller
synlig). Derfor kan dry-runnen ikke opgøre eksisterende kontra forventede
private source-record inserts. Resultatet er eksplicit `NO-GO`; fravær er ikke
blevet behandlet som en tom tabel.

## Gates og næste kritiske vej

Blokeringerne er:

1. installer/verificér det allerede designede private source-recordlag gennem
   en særskilt migrationsgodkendelse;
2. afklar de 41 genuinely-new records mod de 23 eksisterende umappede
   1939-personposter og øvrige kanoniske personer;
3. gennemgå 130 aktive fact-kandidater med manglende/ikke-literal provenance,
   94 tilsvarende ægteskaber og 81 børnerelationer;
4. design og godkend en konkret source-/assertion-writer med replay,
   ejerskabsbevis og rollback-plan;
5. genkør previewet, før en reimport kan få GO.

## Artefakter og reproducerbarhed

Ignorerede private artefakter:

- `work/task21-1939-v50-import-preview/import-preview-v1.json`
  (`04f2780b4fc3f63263324cbb5133e07d1eed70018f7ea11212597a26cc196ca5`);
- `work/task21-1939-v50-import-preview/import-preview-v1-report.md`
  (`ae0e7dd063c3c385714bae756a7a8f26b3cae85062b12bff9b8af554304b2922`);
- `work/task21-1939-v50-import-preview/database-preview-v1.json`
  (`a00efd43a34358f95f4b0df40695f4abd3b279066bee196e3cbdbd1b87b9e97c`);
- `work/task21-1939-v50-import-preview/database-preview-v1-report.md`
  (`8add670471611c485572775be356eda1799f98bf887d385357393aa63527442f`).

En anden live read-only-kørsel gav samme semantiske SHA-256
`35c1d2f27f2c23560118cc0e7a759bb5a681cbc3d38837a6c4ff8b0e9e8dcc4f`,
når kun `snapshot_at` blev fjernet.
