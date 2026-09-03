# 149a source_evidence: rehearsal-rapport

**Observeret:** 2026-09-03
**Kodegrundlag:** `feat/149-2018-20-fase-a` t.o.m. Task 5 + guard-rettelsen (commit efter 1a82f8a)
**Resultat:** Del A (syntetisk v2-base) **GRØN**; Del B (restore af prod-dump) **GENNEMFØRT** efter rettelse af #153's migrationsguard (samme aften)

Dette er afgrænset, lokalt disponerbart bevis, ikke en produktionsautorisation.
Ingen produktionsdatabase, push, merge, deploy eller netværkshandling er brugt.
Kun tal, nøgler og hashes; ingen persondata.

## Låste inputhashes (den rigtige bog)

| Artefakt | SHA-256 |
| --- | --- |
| PDF (`Dansk Adels Aarbog - Reventlow - Særudgave.pdf`) | `3beadfc15e3fa1a4090589af56cd4e95599a9231e8f979dfb60c4e27bbd8252a` |
| Rå tekst (`pdftotext -layout` 26.07.0, sider 93-247) | `2dd5cf8408943ccc50ac4d89dcbd08ac3b49a90fdabd1ddcbd7b22d218026563` |
| Profil `daa-2018-20-source-evidence-v1` | `5919b60384e4b32e26e5308c849e51a6b61722c109edb17e24262c175df676db` |
| Segment-digest (591 poster) | `eded027e49bbde6857e4c9bcb53b5a3954c1438fc271e26c9b5b4355694df742` |
| Manifest, indhold | `c7d19c014610b2e824719048e3733607279e55bbe88b96dc99cce4e3d6f83a8e` |
| Manifest, filbytes | `db58e4074fd54093959d2cecd2ec33569f5e82f6ff340242610278bb5eae819b` |

Manifestet har 591 `source_evidence`-elementer og 0 `person_create`; alle 591
poster fundet som eksakte spænd i den normaliserede projektion;
`validate_reimport_manifest`: OK.

## Del A: syntetisk v2-base `daa149a_synthetic_20260903`

| Trin | Resultat |
| --- | --- |
| Kontraktversion | 2 |
| pytest (3 moduler) | 39 passed |
| `tests/integration/test-reimport-source-evidence.R` | PASS, kørt to gange mod samme base (idempotent pr. kørsel) |
| Dry-run | `finalized`, ikke committet, tal uændrede |
| Apply | 1 rendition, +2 records, +2 occurrences, +2 accepterede ankre |
| Kanonisk delta (`person`, `fact`, `family_member`, `narrative`, `narrative_record_publication`) | aggregat-hash identisk før/efter |
| `SET LOCAL ROLE anon` | identisk før/efter |
| Replay | `already_applied` |
| `red_reverse_reimport` | afvist `REIMPORT_WRITER_REVERSAL_INVALID` (plan-afvigelse 4) |
| `Rscript run-tests.R` | FAIL 0, PASS 2792 |

## Del B: restore af prod-dump `pre-c0f-20260821-112005.dump`

| Trin | Resultat |
| --- | --- |
| Dump SHA-256 | `fcfeb22532975d45803b98813e51bdde33b5a79537547b7ce202a28eaf7046b3` |
| `pg_restore` til `daa149a_rehearsal_20260903` | exit 1, kun `supabase_vault`-fejl (findes ikke lokalt); person = 1811; source 1: 0 records |
| `db-migrations.sql` | **exit 3**: `REIMPORT_LEGACY_IN_FLIGHT_MIGRATION_BLOCKED` (`db-migrations.sql:11539`, guard i `reimport_writer_upgrade`) |
| Årsag | 1939 fase A-batch (source 3, 584 source_evidence-events, 2026-08-18) er `finalized`; guarden kræver `activated`/`reversed`; en ren source_evidence-batch kan aldrig aktiveres |
| Ikke nået | profilindsættelse, preview, autorisation, apply, tal, hash-lighed, replay, restore-bevis |

Basen `daa149a_rehearsal_20260903` er delvist migreret og må ikke genbruges.

## Del B, andet forsøg: `daa149a_rehearsal2_20260903` (kopi af ren restore)

| Trin | Resultat |
| --- | --- |
| `db-migrations.sql` med guard-rettelsen | exit 0; batch `328a813a…` migreret til `private.reimport_batch` som `finalized` (0/584, profil `daa-1939-v50-production-write-v1`) |
| #152-cutover (§3b, den ægte kæde) | export, review, convert, preflight `preflight_rolled_back`, apply `committed` → kontraktversion **2** |
| Writer-profil | `profile_sha256 = 5919b603…` (matcher profilindlæseren) |
| Preview (`export_reimport_preview.R`) | SHA `80709daf…`; før-billede 0/0/0/0/0 for source 1 |
| Dry-run | exit 0, intet skrevet |
| Autorisation / apply | autorisation `628eb264…`; batch `a3304ce1-7004-4d01-97d4-83eab2ad84f8` `finalized`, committet |
| Tal efter apply | **1 rendition / 591 records / 591 forekomster / 591 accepterede ankre** |
| Kanonisk delta (`person`, `fact`, `family_member`, `narrative`, `narrative_record_publication`) | fem aggregat-hashes identiske før/efter (`PGTZ=UTC`) |
| `SET LOCAL ROLE anon` | ni hashes identiske mod referencebasen `daa149a_anonref_20260903` (dump + migrationer + cutover uden reimport) |
| Replay | `already_applied` |
| `red_reverse_reimport` | afvist `REIMPORT_WRITER_REVERSAL_INVALID` |
| Gendannelsesbevis (§6.6) | ingen frisk restore (ingen baser måtte droppes); `daa149a_dumpbase_20260903` viser 0/0/0/0 for source 1 |

Uafhængig efterkontrol af forælderen: `db-migrations.sql` kørt på en ny kopi
af den rene restore → exit 0, batch `328a813a…` = `finalized`, 3 batches i alt.

## Dokumenterede afvigelser

Se planens afsnit »Dokumenterede afvigelser fra spec-teksten« og
`docs/decisions.md` 2026-09-03. Reversal-afvigelsen afventer projektejerens
kvittering.

## Restpunkter

1. Guard-rettelsen er på grenen og bevist mod dumpet; prod (bekræftet læse-kun
   2026-09-03) har samme finalized fase A-batch, så rettelsen SKAL med i #153's
   prod-migration.
2. Fase-pakke-bidrag med receipt for Del B (batch `a3304ce1…`) er ikke skrevet.
3. Runbookens §6.2/§6.5 er rettet som noter (PGTZ, reversal-grant).
