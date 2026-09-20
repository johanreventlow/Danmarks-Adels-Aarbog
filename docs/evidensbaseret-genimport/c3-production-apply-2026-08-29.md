# C3 production apply — 2026-08-29

**Status:** Gennemført og efterverificeret

**Kodegrundlag:** lokal `main` ved `7b5dc5a`

**Scope:** Kun de fem godkendte C3-sager. Rapporten er ikke bevis for den
generelle genimportkæde og giver ikke produktions-GO til #152 eller senere
roadmapmål.

## Før apply

- En frisk custom-format backup blev oprettet med mode `0600`.
- Backupstørrelse: `6030744` bytes.
- Backup SHA-256:
  `6aac1fedcc069c0f5274d9b2591d864dad30957a94a1979f070e1785c192f332`.
- Backuprestore og migration blev først øvet i disposable databaser.
- Eksisterende tabeldata var hash-identiske før og efter migrationsrehearsal;
  de nye identity-lock-tabeller havde kun deres forventede initialtilstand.
- Den migrerede disposable katalogtilstand matchede produktionskataloget efter
  migration for funktioner, kolonner, constraints, indeks, triggers og
  policies.

Backupens lokale sti og databasecredentials registreres ikke i Git. Backupen
er sensitiv og må ikke slettes uden en udtrykkelig beslutning.

## Migration

Migrationerne blev anvendt i én transaktion under den globale writer-lås
`hashtextextended('daa-1939-v50-production-writer',0)` med afgrænsede lock- og
statement-timeouts.

- `db-migrations.sql` SHA-256:
  `6e850102a1c0ec4632d039cd89c2054ae3d7e05237f7dd5bbf9b4993099c95a4`.
- `db-rls.sql` SHA-256:
  `529f7bcfd505a7ffd075c3ece39ed336e5f137ec4824502759b4796e004b4d`.
- Database system identifier: `7642734024280108049`.

## Autoriserede artefakter

- Preview SHA-256:
  `6c3665a0063df5616b8e5bcd11ae1612e7c77f78e085c3d2b9b2f5014ec80498`.
- Manifest SHA-256:
  `5208fbeb5b621a2e8e61c6eaf51d10f11fdf10571427f2674901f44245199d64`.
- Menneskelig approval-fil SHA-256:
  `c68d7b7341398b3ff3d93a297bf613365a163ee6f99c5c623b90c20c6007f6b7`.
- Tilstand SHA-256:
  `3b450cbc753492e22ecb69ca862b89f5272a37839b150429de3a0608e920f68a`.
- Beslutninger SHA-256:
  `34e34ebd24c9ec83d037658bd5aade97ff55bee78b5c6b027fc0af8d624f85d0`.
- Tekstbundle SHA-256:
  `50d57697bb789470fb7706a8d5971a4d480743a5f9acec4a4a0520181a1429ab`.

Gate-read-only og preflight matchede de autoriserede hashes og den forventede
databasetilstand umiddelbart før apply.

## Apply-resultat

- Batch: `447d81a8-5c21-4b22-832e-e0d2a379a20c`.
- Change set: `966`.
- Batchstatus: `finalized`.
- Noncestatus: `committed`.
- 11 append-only C3-events:
  - 5 `identity_different`;
  - 4 `record_assign`;
  - 2 `record_no_publication`.
- 19 eksakte offentlige change events.

Den uafhængige read-only postverification kontrollerede receipt,
eventhashes, identitetsrelationer med assertion/conclusion, narrative
teksthashes, source-record-bindinger, `no_publication`-fravær, det eksakte
change-set-tabelscope og fravær af åbne C3-batches og autorisationer.

Slutbevis:

```text
C3_POSTVERIFY_OK|447d81a8-5c21-4b22-832e-e0d2a379a20c|966|finalized|11|19|5|4|2
```

## Afgrænsning

- Production apply blev ikke reverseret.
- Reversal er tidligere bevist mod en frisk, produktionsafledt disposable
  restore, men er ikke udført i produktion.
- Ingen push eller ekstern branchpublicering indgik i production apply.
- C3 beviser den afgrænsede fem-sagers korrektionskæde, ikke at DAA's fælles
  flerudgavekæde er færdig.
