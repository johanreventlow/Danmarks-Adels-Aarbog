# 149a source_evidence: rehearsal-rapport

**Observeret:** 2026-09-03
**Kodegrundlag:** `feat/149-2018-20-fase-a` t.o.m. Task 5
**Resultat:** Del A (syntetisk v2-base) **GRØN**; Del B (restore af prod-dump) **STOPPET** i #153's migrationsguard

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

## Dokumenterede afvigelser

Se planens afsnit »Dokumenterede afvigelser fra spec-teksten« og
`docs/decisions.md` 2026-09-03. Reversal-afvigelsen afventer projektejerens
kvittering.

## Restpunkter

1. #153's guard skal disponeres (accept af `finalized` som terminal for
   batches med 0 person_creates, eller et terminalt trin for fase A-batchen)
   og verificeres læse-kun mod prod, før #153's prod-GO og 149a's ægte rehearsal.
2. Fase-pakke-bidrag med receipt kan først skrives efter en gennemført Del B.
3. Editionskatalog-gaten (`_2018`-allowlist, plan Task 6 Step 1-4) er ikke udført.
