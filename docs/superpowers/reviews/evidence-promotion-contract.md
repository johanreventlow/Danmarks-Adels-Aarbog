# Evidens-promotion-kontrakt: gate

**Dato:** 2026-08-03
**Gren:** `feat/evidensbaseret-genimport`
**Afgørelse:** Begrænset GO for privat promotion-backend og dry-run-adapter. **NO-GO** for automatisk kanonisk writer, produktions-cutover og påstand om fuldt grønt CI.

## Observeret bevis

- [x] Korrekt `person.name` til eksisterende assertion accepteres.
- [x] Forkert person, fact-type og værdi afvises fail-closed.
- [x] Ukendt regel findes ikke, og `person.name` kan ikke målrettes `relation`.
- [x] To gyldige promotioner i én batch giver præcis to links og én batch.
- [x] En ugyldig række ruller batchen tilbage uden nye audit-rækker.
- [x] Promotion ændrer ikke `person`, `fact` eller `assertion`.
- [x] Ægtefælleomtale afvises, når en regel kræver principal placement; v1-reglerne er assertion-bundne personregler.
- [x] `anon` og `authenticated` kan ikke læse private promotiontabeller eller kalde private validatorer.
- [ ] Samspil mellem ældre individuel promotion og senere batchpromotion er ikke kørt som selvstændig test.

Kommandoer og observerede resultater:

- `/opt/homebrew/opt/postgresql@17/bin/psql -d daa_evidence_promotion_contract_20260803 -v ON_ERROR_STOP=1 -f tests/sql/evidence-promotion-bootstrap.sql`, derefter `schema.sql`, `db-rls.sql` og `tests/sql/test-evidence-promotion.sql`: exit 0; RLS-kontrakten udskrev `OK`.
- Den isolerede `$promotion_rule_verify$`-blok fra `db-verify.sql`: exit 0; den udskrev både promotion-preview/batch-atomaritet og regel-audit som `OK`.
- `Rscript run-tests.R`: 576 pass, 0 fejl, 1 kendt opt-in lokal-DB-smoke skip.
- CI-jobbet `evidence-promotion-db` er defineret i `.github/workflows/ci.yml`, men det er ikke observeret kørt i GitHub Actions i denne gate.

`db-verify.sql` som helhed er ikke grøn på en tom disposable database: efter de beståede promotionblokke fejler den senere ved `regen genskabte ikke visning_navn`. Promotion- og identity-samtidighedsblokke kræver `dblink` og blev sprunget over. Ingen af disse forhold må omskrives til en grøn fuld-suite-påstand.

## Afgrænsning

`project_evidence.R` forbereder kun validerede assertion-requests i `--dry-run`. Uden flag afviser den med `EVIDENCE_PROJECTOR_PROMOTION_RPC_REQUIRED`. Den må ikke åbne en databaseforbindelse eller oprette/ændre kanonisk genealogi. Zero-match er fortsat en redaktionel køtilstand.
