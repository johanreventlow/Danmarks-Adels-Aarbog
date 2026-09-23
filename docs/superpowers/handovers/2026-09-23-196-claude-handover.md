# Handover — #196 fortolkningsforslag-projektion

Dato: 2026-09-23  
Worktree: `.worktrees/196-interpretation-proposal-prod-gate`  
Branch: `feat/196-interpretation-proposal-prod-gate`

## Mandat og grænser

Implementér kun den godkendte plan
`docs/superpowers/plans/2026-09-21-interpretation-proposal-projection.md`.
Leverancen hører til roadmap trin 4: maskinforslag umiddelbart før menneskelig
afgørelse. Den skal være udgaveneutral, ikke lække rå kildetekst eller
claim-værdier, og er **ikke** autorisation til produktionstilslutning eller
produktionsmutation.

Læs før videre arbejde:

1. `docs/evidensbaseret-genimport/vision.md`
2. `docs/evidensbaseret-genimport/roadmap.md`
3. `docs/evidensbaseret-genimport/teknisk-maalarkitektur.md`
4. `docs/evidensbaseret-genimport/status.md`
5. den nævnte plan og `.superpowers/sdd/2026-09-21-interpretation-proposal-projection/progress.md`

## Sikker commitgrænse

`af42119 feat: bind proposal events to result receipts`

Committen er selvstændig og verificeret. Den indeholder:

- SQL-kanonisering og hash for proposal-receipts samt normalisering af sikre
  JSON-heltal;
- fælles key-materiale/hash/key-hjælpere for eksisterende key-version 1;
- lukkede receipt-hjælpere for interpretation, link og disposition;
- writerens `payload.result_receipt` og `after_sha256` over receipt'en;
- ACL- og katalogkontroller samt fokuserede SQL-tests.

Verificeret før commit:

```text
psql -X -d daa196_task3_receipt -v ON_ERROR_STOP=1 \
  -f tests/sql/test-interpretation-proposal.sql  -> PASS
pytest ...test_compare_interpretation_proposal_projection.py -k sql_contract -> 1 passed
Rscript -e 'testthat::test_file("tests/testthat/test-apply-reimport.R")' -> 32 PASS, 0 FAIL
git diff --check -> tom
```

Den disposable lokale database `daa196_task3_receipt` er klargjort med
`tests/sql/evidence-promotion-bootstrap.sql`, `schema.sql`,
`db-migrations.sql`, `db-rls.sql` og den eksisterende syntetiske
`tests/sql/reimport-writer-v2-bootstrap.sql`. Det er testdata, ikke
produktionsdata.

## Ucommittet WIP — behold og færdiggør, men kald det ikke færdigt

```text
M  .claude/skills/daa-extract/scripts/apply_reimport_helpers.R
M  .claude/skills/daa-extract/scripts/test_compare_interpretation_proposal_projection.py
M  tests/testthat/test-apply-reimport.R
?? .claude/skills/daa-extract/scripts/interpretation_proposal_anon_projection.sql
?? .claude/skills/daa-extract/scripts/interpretation_proposal_projection.psql
?? .claude/skills/daa-extract/scripts/interpretation_proposal_projection.sql
?? .claude/skills/daa-extract/scripts/interpretation_proposal_target_identity.sql
?? tests/integration/test-reimport-interpretation-proposal.R
```

Derudover er denne handover-note og SDD-ledgeret ucommittede dokumentationsændringer.

### Hvad WIP allerede beviser

- `execute_reimport()` har `authorization_policy = c("auto_dry_run",
  "external")` og `transaction_entry`; R-unit-testene beviser, at external
  authorization kræves i begge modes, omgår gatewayens authorizer, og at
  transaction-entry ligger efter advisory lock og før preflight.
- Den nye R-integration bygger en syntetisk source/evidence/accepted-anchor/
  clause-kæde ved at køre den eksisterende clause-fixture i en separat
  R-proces. Det er bevidst: at `source()` den fixture direkte gav RPostgres
  `bad_weak_ptr`, fordi dens DBI-forbindelse var afsluttet.
- Integrationen er grøn mod den disposable database for proposal dry-run og
  apply med external authorization, to claims, to dispositioner og kontrol af
  writerens receipt-hash:

```text
PGDATABASE=daa196_task3_receipt PGHOST=/tmp PGPORT=5432 \
PGUSER=johanreventlow PGPASSWORD='' \
Rscript tests/integration/test-reimport-interpretation-proposal.R
-> interpretation_proposal receipt integration OK
```

- SQL-driveren åbner én `REPEATABLE READ, READ ONLY` transaktion, fastlåser
  UTC/ISO/postgres/`extra_float_digits=1`, sætter `anon` lokalt og kræver ens
  snapshot-hashes for owner- og anon-delene. Runtime-output blev læst som ét
  JSON-dokument og godkendt af den nuværende Python shape-validator.

### Kendte mangler / næste arbejde i denne rækkefølge

1. Færdiggør **Task 2**: owner-projektionen har stadig placeholder-/for
   snævre upstream-, neutral- og promotion-hashes. Udvid til planens komplette
   navngivne relationer. Det skal være lukkede, deterministisk sorterede
   hashgrupper og ingen rå tekst/værdier i output eller fejl.
2. Færdiggør **Task 4** før den påstås brugbar: Python-filen har manifest- og
   shape-validering, men mangler `compare_apply`, `compare_replay`, den lukkede
   CLI og mutationstesten for alle driftklasser. Den må ikke erklære match kun
   på tællinger eller event-id'er.
3. Færdiggør **Task 5**: integrationen mangler stadig før/efter-projektion,
   comparator-`match`, replay med ny authorization, replay-comparison samt en
   mutation af receipt-hash, der giver
   `INTERPRETATION_PROJECTION_RECEIPT_INVALID`.
4. Først derefter Task 6: særskilt CI matrix med disposable DB i begge
   katalogrækkefølger og en sanitiseret rehearsal-receipt. Ingen produktion.

## Vigtige faldgruber

- `db-verify.sql` stopper fortsat ved en **eksisterende, urelateret** ACL-fejl:
  `VERIFY_NARRATIVE_RECORD_V2_FACADE_AUTH_ACL_INVALID:
  public.red_begin_1939_v50_reimport(uuid,text,text)`. Ret eller maskér ikke
  den som del af #196.
- `tests/sql/test-interpretation-proposal.sql` passer på den disposable base.
  PostgreSQL-forventede fejl skal fortsat bruge repository-savepoint-helperen,
  så en forventet fejl ikke aborterer resten af testen.
- Bevar `clause_evidence_projection*` uændret; #196 har egne filer.
- Brug ikke `row::text`, `to_jsonb(row)` eller implicit session-formattering
  som receipt-hash for detaljerede proposal-rækker. Receipt-hjælperne fra
  `af42119` er autoriteten.
- Planens builderkontrakt er smallere end den generiske receiver:
  4.3b accepterer fortsat kun string eller `{raw, normalized?}`; udvid ikke
  builderen til numeriske claim values.
- `psql` mod `/tmp/.s.PGSQL.5432` kræver i dette miljø kørsel uden sandbox.
  Det er kun tilladt mod den explicitte disposable database ovenfor.

## Afslutningskriterium

Ingen GO endnu. Der må først rapporteres teknisk PASS, når Python-mutationer,
disposable PostgreSQL dry-run/apply/**match**/replay, CI-matrix og den
sanitiserede receipt alle er grønne. Produktions-GO og produktionsmutation er
fortsat ikke givet.
