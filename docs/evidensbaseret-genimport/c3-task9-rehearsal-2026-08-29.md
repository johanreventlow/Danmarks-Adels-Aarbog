# C3 Task 9 — disposable rehearsal 2026-08-29

## Dom

Den tekniske stopport er **`READY_FOR_PRODUCTION_GO`**.

Det er ikke et produktions-GO. Produktionen blev kun læst for at oprette den
beskyttede backup; hver migration, apply og reversal blev udført mod lokale,
navngivne engangsdatabaser. Projetejeren valgte efter stopporten lokal
integration i `main`; der er ikke pushet.

## Produktionsafgrænsning og backup

- Backup:
  `/private/tmp/daa1939-c3-task9-production-unmutated-20260829T055559Z.dump`
- Format og rettigheder: PostgreSQL custom archive, mode `0600`
- Størrelse: `5.844.194` bytes
- SHA-256:
  `8b7a9ec4ed4bcbd9b486c92e8265ae3bb33355a11d93c23fb50e06809fb8621f`
- Restore-listen udelod kun den lokalt manglende Supabase Vault-extension,
  dens kommentar og `vault.secrets`; ingen genealogi- eller C3-data blev
  udeladt.

Backupen er ukrypteret og kan indeholde følsomme produktionsdata. Den ligger
lokalt med begrænsede filrettigheder og må ikke deles eller slettes uden en
udtrykkelig beslutning.

## Restore, migration og artefaktbinding

- Frisk rehearsal-database:
  `daa1939_c3_task9_rehearsal_20260829_070449`
- Database system identifier: `7679319414148662096`
- Restore-bundne artefakter ligger under den private mappe
  `/private/tmp/daa1939-c3-task9-rehearsal.8hBc8i` med mode `0700`.
- Kandidat-SHA-256:
  `34e34ebd24c9ec83d037658bd5aade97ff55bee78b5c6b027fc0af8d624f85d0`
- Preview-SHA-256:
  `8876f140926412149cc71811c82a6323d34e03d4e11eab88d1aa0ba3b61ab596`
- Manifest-SHA-256:
  `9d56fae1de0ecc5abb0c367dbdb6d898d7bc687dba4185e0233d4d57388464e8`
- Godkendelses-SHA-256:
  `5581e39d61a3663e6b13126fdfcdcfa213d978bb1b58c73ae936d625e7017be0`
- Tekstbundle-SHA-256:
  `50d57697bb789470fb7706a8d5971a4d480743a5f9acec4a4a0520181a1429ab`
- Omfang: 5 sager, 5 identitetshændelser, 4 narrative tildelinger,
  2 `no_publication`-hændelser og 11 C3-hændelser i alt.

Forudsætningskontrollen fandt ingen dublerede aktive
`source_record_id`-bindinger. En injiceret fejl midt i migrationen rullede hele
transaktionen tilbage med uændret C3-katalogfingeraftryk. Derefter bestod
`db-migrations.sql`, `db-rls.sql` og hele `db-verify.sql`. En frisk base oprettet
fra `schema.sql` bestod efterfølgende samme migration, så den tidligere
schema/migration-signaturdrift er lukket.

Det produktionsbundne manifest blev fail-closed afvist mod restore-basen med
`C3_APPLY_DATABASE_MISMATCH`. Databaseidentiteten i det produktionsbundne og
restore-bundne manifest er forskellig; samme eksakte lighedsgate forhindrer
også et restore-bundet manifest i at blive anvendt mod produktion.

## Apply og reversal

- Oprindelig og endelig domæne-state SHA-256:
  `977b60710b6bbb1552fcf9fa48caed4f0377911bad08ee7137126716e7b7f215`
- Rollback-rehearsal: `rolled_back=true`, ingen ledger-residue og eksakt
  uændret state-hash.
- Apply-batch: `14c528e0-20f2-4d0e-99c1-53ef84982dfd`
- Apply change set: `967`
- Apply-receipt SHA-256:
  `1396aa0172486c4e581e4bda79b1fde9c85c946164b5a2ce55e1d788646a6ca5`
- Replay med samme nonce returnerede samme batch og change set uden nye rækker.
- Reversal-batch: `fa46a749-8447-49fd-99c5-c5a5e7cc8872`
- Reversal change set: `968`
- Reversal-receipt SHA-256:
  `252aa2cc9d10c58ec3ee35ff44798124df6d5baf9931bbf0a0071b7ea79d8e85`
- Efter reversal var domænetilstanden eksakt den oprindelige. Kun det
  append-only autorisations-, batch- og hændelsesledger, som beviser apply og
  reversal, stod tilbage.

## Verifikation

- C3 integration: 49 assertions; alle fem failure-positioner, tre reelle
  writer-schedules, concurrent identical apply, nonce-drift, idempotens og
  eksakt reversal bestod.
- Writer-lock: 8 reelle schedules og 4 power controls bestod.
- Fokuseret preview/gateway-R: 136 henholdsvis 255 assertions bestod.
- Fuld R-suite: 831 bestået, 0 fejl, 14 kendte path-warnings og 2 forventede
  skips.
- Fuld Python-suite: 2.358 bestået og 34 skipped.
- Genereret JavaScript og no-writer-kontrol: 4 bestået.
- Syntetisk Chromium: begge C3-reviewflader bestod download- og
  beslutningsforløbene.
- `git diff --check`: ren.

## Betingelser før produktion

1. Den lokalt integrerede commit verificeres som faktisk `main`-tree uden push.
2. Der gives et nyt, eksplicit produktions-GO; denne rapport er ikke GO'et.
3. Produktionsforløbet bygger frisk produktionspreview og manifest fra den
   integrerede kode og genbruger kun det databaseuafhængige kandidatmanifest
   og den godkendte tekstbundle.
4. Kontrollen for dublerede aktive source-record-bindinger gentages lige før
   produktionsmigrationen.
5. Migration, ACL-verifikation og gateway reconciliation følger den samme
   globale writer-lock og stopper fail-closed ved enhver hash-, state- eller
   databaseidentitetsafvigelse.
