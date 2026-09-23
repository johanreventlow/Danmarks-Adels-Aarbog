# Rehearsal — fortolkningsforslag-projektion (#196, trin 4)

Dato: 2026-09-23 · Plan: `docs/superpowers/plans/2026-09-21-interpretation-proposal-projection.md`
Branch: `feat/196-interpretation-proposal-prod-gate` · Kode-commit: `30afa21`
(CI-wiring og denne ledger i efterfølgende commit).

**Kun disponerbare lokale PostgreSQL 17-baser** (`daa196_ci_schema_rls_migrations`,
`daa196_ci_schema_migrations_rls`), bygget fra `evidence-promotion-bootstrap.sql`,
`schema.sql`, `db-rls.sql`, `db-migrations.sql` (×2) og de syntetiske writer-fixtures.
Ingen produktionsforbindelse. Al data er syntetisk.

## Kommandoer (lokal gengivelse af CI-jobbet `interpretation-proposal-db`)

Pr. katalogrækkefølge: frisk base → bootstrap → dedikerede logins
(`daa_proposal_ci` NOINHERIT ∈ `authenticated`; `daa_proposal_authorizer_ci` NOINHERIT ∈
`service_role`) → katalog i matrixens rækkefølge → `db-rls.sql` →
`tests/sql/test-interpretation-proposal.sql` → `tests/sql/run-db-verify-disposable.sql` →
writer-fixtures → `Rscript tests/integration/test-reimport-interpretation-proposal.R` med
`DAA_PROPOSAL_STRICT_LOGINS=1` og de to logins.

## Resultater

| Gate | schema-rls-migrations | schema-migrations-rls |
|---|---|---|
| `test-interpretation-proposal.sql` | PASS | PASS |
| `run-db-verify-disposable.sql` | PASS | PASS |
| Rolle-livscyklus (COMMIT/ROLLBACK nulstiller rolle + claims) | PASS | PASS |
| Operationslogin kan ikke autorisere; autorisatorlogin kan ikke skrive | PASS | PASS |
| Dry-run (ekstern autorisation) ændrer ingen projektion | PASS | PASS |
| Apply → comparator `match` | PASS | PASS |
| Muteret receipt → `INTERPRETATION_PROJECTION_RECEIPT_INVALID` | PASS | PASS |
| Replay (`already_applied`) → replay-comparator `match`; forkert autorisation afvist | PASS | PASS |
| Negative skemaer (RW, READ COMMITTED, anon-som-ejer, ejer-som-anon, split snapshot) giver navngiven kode og intet output | PASS | PASS |
| Kildemutanter (guard-prædikat slået fra, literal bevaret) mister deres afvisning | PASS | PASS |
| R→PG-grænse: ±(2^53−1), `1.0`, `1e0`, `-0` bevares/normaliseres; SQL-hash = Python-hash; ±2^53, bigint-grænser, brøk, `1e400` afvist i R før gateway | PASS | PASS |
| Superuser som operationslogin afvist (`INTEGRATION_LOGIN_SUPERUSER:OPERATION`) | PASS (kørt én gang) | — |

Sanitiserede comparator-kvitteringer:

| | schema-rls-migrations | schema-migrations-rls |
|---|---|---|
| source_id | 149513656 | 149561108 |
| database_target_sha256 | `618fd05b…a6da9c7ba` | `990e36e9…f176a55efc` |
| manifest_content_sha256 | `13320487…495ad68a` | `e217bc8e…cfad36426d` |
| batch_id | `ad660e8e-830c-44f1-9b8c-84c69143b84d` | `65e8a76f-69e9-4e84-b28c-ba413a949d6b` |
| replay_authorization_id | `d2878fc8-709f-43a7-9531-45c9012a4e14` | `2eb59487-aaa0-49e4-823f-e0b2e83332fd` |
| counts | elements 1 · claims 2 · links 3 · `afventer_identitet` 2 | samme |
| apply / replay | `match` / `match` | `match` / `match` |

Øvrige gates: `pytest` (comparator + 4.3b-builder) 198 passed · `Rscript run-tests.R`
FAIL 0 · `git diff --check` tom.

## Ikke kørt

- GitHub Actions-kørsel af det nye job: **BLOCKED** indtil grenen pushes (push kræver
  projektejerens godkendelse). Den lokale gengivelse ovenfor bruger samme trin, men lokal
  unix-socket-auth frem for CI's password-auth.
- Ikke-medlem-login (`permission denied to set role`): kun i CI-jobbet.

```text
Leverance #196-projektion: PARTIAL (alle lokale gates PASS; CI-kørsel afventer push)
Produktions-GO: IKKE GIVET
Produktionsmutation: INGEN
```
