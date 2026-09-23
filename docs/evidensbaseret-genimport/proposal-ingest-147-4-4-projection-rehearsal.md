# Rehearsal — fortolkningsforslag-projektion (#196, trin 4)

Dato: 2026-09-23 · Plan: `docs/superpowers/plans/2026-09-21-interpretation-proposal-projection.md`
Branch: `feat/196-interpretation-proposal-prod-gate` · Kode-commit: `7fe02b3`
(efter review-rettelserne; første kørsel var på `30afa21`).

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

Sanitiserede comparator-kvitteringer (kørsel på `7fe02b3`):

| | schema-rls-migrations | schema-migrations-rls |
|---|---|---|
| source_id | 149510469 | 149516521 |
| database_target_sha256 | `618fd05b…a6da9c7ba` | `990e36e9…f176a55efc` |
| manifest_content_sha256 | `f0b0d3fa…0e38b7e8` | `3d46ba99…cbedf450` |
| batch_id | `091424d8-363b-4dd9-aa88-92eb70a47869` | `3a38bc0b-9414-4d35-98fa-50484f661e57` |
| replay_authorization_id | `7cee7ba5-3eb4-4152-b951-1522e49a42de` | `d7f36682-c61f-4184-9a26-5a05cb3cf72c` |
| counts | elements 1 · claims 2 · links 3 · `afventer_identitet` 2 | samme |
| apply / replay | `match` / `match` | `match` / `match` |

## Review-rettelser mellem første og anden kørsel

Et uafhængigt helgrens-review fandt to regressioner, som første kørsel ikke kunne se,
fordi fixturen var formet efter fejlen:

- Writeren læste `{value,raw}` på den allerede normaliserede værdi og afviste derfor alle
  rigtige `{raw, normalized?}`-værdier. Grænsefixturen bruger nu den rigtige form og var
  rød mod den gamle writer (`REIMPORT_WRITER_VALUE_KIND_INVALID`), grøn efter rettelsen.
- 4.3b-builderen gav `Decimal`-confidence efter streng afkodning, så runner-grænsen afviste
  hver rigtig claim med brøk-confidence. Ny test afkoder en rå cache-streng.

Desuden: manifest-hash på almindelig float-parse, tolerance for rækker uden accepteret
anker, før-dispositioner fra enhver triggergyldig maskinrække, ingen navne i maskin-
dispositioner, snævrere PREEXISTING_TARGET, SQL↔Python golden vectors, receipt-
tidszonetest og helper-ACL i db-verify.

Øvrige gates: `pytest` (comparator + 4.3b-builder) 205 passed · `Rscript run-tests.R`
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
