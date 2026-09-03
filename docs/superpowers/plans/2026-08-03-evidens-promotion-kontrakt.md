# Evidens-promotion-kontrakt Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Gør individuelle og bulk-udførte, accepterede evidenspromotioner fail-closed, append-only og uden automatisk oprettelse eller ændring af kanonisk genealogi.

**Architecture:** Den private database ejer en versioneret regelprofil, batch-audit og den eneste promotion-RPC. Reglen kobler et eksakt prædikat til et eksisterende assertion-mål; RPC'en kontrollerer personaidentitet, fact-slot og værdi, før den kun indsætter `interpretation_promotion`. R-arbejdet forbereder og validerer payloads, men skriver aldrig kanoniske rækker.

**Tech Stack:** PostgreSQL 17, Supabase RLS/`SECURITY DEFINER`, SQL-kontrakttest, R (`DBI`, `RPostgres`, `testthat`), GitHub Actions PostgreSQL-service.

## Global Constraints

- Ingen promotion må oprette eller opdatere `person`, `family`, `fact`, `relation`, medlemskab, heraldik, media eller description.
- Kun en accepteret fortolknings aktuelle version og, for personbundne regler, en accepteret source-persona-identitet til samme eksisterende person må promoveres.
- Regler matches eksakt; ukendt prædikat, forkert target, forkert fact-slot, forkert værdi eller manglende evidens afvises.
- Hver promotion er append-only; en batch er atomisk, men indeholder fortsat én promotion pr. fortolkning.
- `load_daa.R` ændres ikke. R-kode må ikke omgå den redaktionelle promotion-RPC.
- Kildepersoner med `mentioned_spouse` eller `child_reference` må ikke få membership/placement/generation gennem denne plan.
- Ingen DAA-år, slægtsnavn eller OCR-specialregel i model, migration eller testfixture.
- Anvend `git branch --show-current` før enhver mutation og før hver commit. Brug kun en isoleret lokal testdatabase, aldrig produktion.

---

### Task 1: Modellér promotionregler og batch-audit

**Files:**
- Modify: `schema.sql`
- Modify: `db-migrations.sql`
- Modify: `db-verify.sql`

**Interfaces:**
- Produces `private.interpretation_promotion_rule` med `(rule_key,rule_version)` som nøgle og `private.interpretation_promotion_batch`.
- Udvider `private.interpretation_promotion` med nullable `rule_key`, `rule_version` og `batch_id`; gamle individuelle links bevares uden batch.
- Version 1-regler er eksakt `person.name → navn`, `person.byname → tilnavn`, `person.title → titel` med `value_kind='text'`, samt `person.birth → fødsel` og `person.death → død` med `value_kind='date_raw'`; alle har `target_type='assertion'`, `requires_persona_identity=true`, `bulk_eligible=true`.

- [ ] **Step 1: Skriv den fejlede SQL-kontrakttest**

Tilføj en `DO $promotion_rule_verify$`-blok i `db-verify.sql`, som fejler med `FEJL: promotionregel-laget mangler`, hvis en af tabellerne eller de tre aktive regler mangler. Den skal kontrollere, at `person.name` ikke kan have en `relation` som mål, og at en ukendt regel ikke findes.

- [ ] **Step 2: Kør testen rødt**

Kør på en disposable database med migrations og RLS anvendt:

```bash
psql -d daa_evidence_verify -v ON_ERROR_STOP=1 -f db-verify.sql
```

Forvent: stop ved `FEJL: promotionregel-laget mangler`.

- [ ] **Step 3: Implementér den mindste append-only model**

Opret i både `schema.sql` og migrations:

```sql
CREATE TABLE private.interpretation_promotion_rule (
  rule_key text NOT NULL CHECK (btrim(rule_key)<>''),
  rule_version integer NOT NULL CHECK (rule_version>=1),
  predicate text NOT NULL CHECK (btrim(predicate)<>''),
  interpretation_kind text NOT NULL CHECK (interpretation_kind='property'),
  target_type text NOT NULL CHECK (target_type='assertion'),
  expected_fact_type text NOT NULL CHECK (expected_fact_type IN ('navn','tilnavn','titel')),
  value_kind text NOT NULL CHECK (value_kind IN ('text','date_raw')),
  requires_persona_identity boolean NOT NULL DEFAULT true,
  requires_principal_placement boolean NOT NULL DEFAULT false,
  bulk_eligible boolean NOT NULL DEFAULT true,
  status text NOT NULL CHECK (status IN ('active','retired')),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (rule_key,rule_version),
  UNIQUE (predicate,rule_version)
);
CREATE UNIQUE INDEX interpretation_promotion_rule_one_active_predicate
  ON private.interpretation_promotion_rule(predicate) WHERE status='active';
CREATE TABLE private.interpretation_promotion_batch (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  rule_profile_hash text NOT NULL CHECK (btrim(rule_profile_hash)<>''),
  preview_hash text NOT NULL CHECK (btrim(preview_hash)<>''),
  promoted_by uuid NOT NULL,
  promoted_by_name text NOT NULL CHECK (btrim(promoted_by_name)<>''),
  promoted_at timestamptz NOT NULL DEFAULT now(),
  requested_count integer NOT NULL CHECK (requested_count>0)
);
```

Seed precisely the five rules above with stable keys `person-name-v1`, `person-byname-v1`, `person-title-v1`, `person-birth-v1` and `person-death-v1`. Add append-only triggers, RLS and explicit `PUBLIC, anon, authenticated` revokes. Add nullable foreign-key columns from `interpretation_promotion` to rule and batch; do not backfill historical rows.

- [ ] **Step 4: Kør SQL-kontrakten grønt**

Genanvend migrations, RLS og `db-verify.sql`. Forvent den nye `NOTICE` for promotionregler og fortsat passering af de tidligere evidensblokke.

- [ ] **Step 5: Commit**

```bash
git branch --show-current
git add schema.sql db-migrations.sql db-verify.sql
git commit -m "feat: define evidence promotion rules and batches"
```

### Task 2: Valider og skriv individuelle/bulk promotioner atomisk

**Files:**
- Modify: `schema.sql`
- Modify: `db-migrations.sql`
- Modify: `db-verify.sql`

**Interfaces:**
- Produces `red_preview_interpretation_promotions(p_items jsonb)` and `red_promote_interpretations_batch(p_items jsonb,p_preview_hash text)`.
- Hvert `p_items`-element er præcist `{"interpretation_id":"uuid","target_type":"assertion","target_id":123}`.
- Preview returnerer `eligible`, `rule_key`, `rule_version`, `target_id` og årsagskode; det returnerer aldrig private source-record UUID'er.

- [ ] **Step 1: Skriv fejlede negative og atomiske SQL-tests**

Udvid `promotion_rule_verify` med testdata for én accepteret persona, én accepteret `person.name`-fortolkning med observation og en assertion på samme persons `navn`-fact. Test disse resultater:

```text
samme person + samme fact-type + samme tekst -> eligible
andet person-id -> EVIDENCE_PROMOTION_IDENTITY_MISMATCH
titel-fact for person.name -> EVIDENCE_PROMOTION_FACT_TYPE_MISMATCH
anden tekst -> EVIDENCE_PROMOTION_VALUE_MISMATCH
to gyldige + én ugyldig i samme batch -> ingen promotion- eller batchrækker
```

- [ ] **Step 2: Kør testen rødt**

Kør den samme disposable `psql`-kommando. Forvent fejl, fordi preview/RPC mangler.

- [ ] **Step 3: Implementér DB-validering og RPC'er**

Tilføj en privat validator, der for hvert inputelement:

1. låser fortolkninger i stigende UUID-orden;
2. kræver `interpretation.status='accepted'`, aktiv eksakt regel og mindst én observationskobling;
3. kræver en accepteret personaidentitet og følger assertion → fact;
4. kræver `fact.subjekt_type='person'`, `fact.subjekt_id=canonical_person_id` og regelens `expected_fact_type`;
5. sammenligner `lower(btrim(normalize(interpretation.value #>> '{}', NFC)))` med regelvalgt `assertion.vaerdi_tekst` (`text`) eller `assertion.date_raw` (`date_raw`);
6. afviser duplikeret `(interpretation_id,target_type,target_id)` som idempotent allerede-promoveret, ikke som ny skrivning.

`red_preview_interpretation_promotions` må kun validere. `red_promote_interpretations_batch` skal genberegne previewet inde i samme transaktion, kræve matching hash, hente aktør/navn fra sessionen og indsætte én batch og én promotion pr. element. Begge RPC'er kræver redaktion; direkte tabeladgang og direkte execute revokeres.

- [ ] **Step 4: Kør den fokuserede kontrakt grønt**

Kør `db-verify.sql`. Bekræft både alle negative koder, en gyldig enkeltpromotion og at batch-rollbacken efterlader nul nye rækker.

- [ ] **Step 5: Commit**

```bash
git branch --show-current
git add schema.sql db-migrations.sql db-verify.sql
git commit -m "feat: validate atomic evidence promotions"
```

### Task 3: Hærd RLS og lav reproducérbar PostgreSQL-CI

**Files:**
- Create: `tests/sql/evidence-promotion-bootstrap.sql`
- Create: `tests/sql/test-evidence-promotion.sql`
- Modify: `db-rls.sql`
- Modify: `.github/workflows/ci.yml`

**Interfaces:**
- Bootstrapper en tom PostgreSQL 17-database med `pgcrypto`, minimal `auth.users` og `auth.uid()` før `schema.sql`.
- CI-jobbet `evidence-promotion-db` anvender bootstrap → schema → RLS → promotiontest mod `postgres:17`.

- [ ] **Step 1: Skriv den fejlede RLS-test**

Skriv `tests/sql/test-evidence-promotion.sql`, som bruger `SET LOCAL ROLE anon` og `authenticated` og beviser, at de hverken kan `SELECT` fra regelsæt/batches/promotioner eller `EXECUTE` promotion-RPC'erne. Testen skal fejle med `EVIDENCE_PROMOTION_RLS_TEST_FAILED` hvis en adgang lykkes.

- [ ] **Step 2: Kør den rødt mod disposable DB**

```bash
psql -d daa_evidence_verify -v ON_ERROR_STOP=1 -f tests/sql/test-evidence-promotion.sql
```

Forvent: fejl før RLS-grants/revokes er implementeret.

- [ ] **Step 3: Implementér RLS og CI-kontrakt**

Tilføj deny-all RLS og eksplicitte revokes for de tre private promotiontabeller og private validatorer. I CI tilføjes:

```yaml
  evidence-promotion-db:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:17
        env: { POSTGRES_PASSWORD: postgres, POSTGRES_DB: evidence_promotion }
        ports: ["5432:5432"]
        options: >-
          --health-cmd "pg_isready -U postgres -d evidence_promotion"
          --health-interval 5s --health-timeout 5s --health-retries 10
```

Jobbet kører derefter bootstrap, `schema.sql`, `db-rls.sql` og den nye SQL-test med `PGPASSWORD=postgres psql -h localhost -U postgres -d evidence_promotion -v ON_ERROR_STOP=1 -f ...`.

- [ ] **Step 4: Kør lokalt grønt og udfør diff-check**

Kør samme fire SQL-filer mod den lokale disposable database og derefter `git diff --check`.

- [ ] **Step 5: Commit**

```bash
git branch --show-current
git add db-rls.sql .github/workflows/ci.yml tests/sql/evidence-promotion-bootstrap.sql tests/sql/test-evidence-promotion.sql
git commit -m "test: run evidence promotion contract in postgres CI"
```

### Task 4: Erstat den spekulative Task 14-writer med en ikke-muterende promotion-adapter

**Files:**
- Create: `.claude/skills/daa-extract/scripts/project_evidence.R`
- Modify: `.claude/skills/daa-extract/scripts/project_evidence_helpers.R`
- Modify: `.claude/skills/daa-extract/scripts/test_project_evidence.R`
- Modify: `tests/testthat/test-project-evidence.R`

**Interfaces:**
- `build_promotion_requests(rows)` returnerer kun `list(interpretation_id, target_type="assertion", target_id)` for eksplicitte, eksisterende target-id'er.
- `project_evidence.R --dry-run input.json` må kun skrive en JSON-rapport til stdout; uden `--dry-run` afviser scriptet med `EVIDENCE_PROJECTOR_PROMOTION_RPC_REQUIRED`.
- Adapteren opretter aldrig kanoniske data og kalder aldrig `dbAppendTable` på public modeltabeller.

- [ ] **Step 1: Skriv fejlede R-tests**

Tilføj testthat-eksempler med håndskrevne rækker:

```r
expect_equal(build_promotion_requests(list(
  list(interpretation_id="i-1", target_type="assertion", target_id=41L)
)), list(list(interpretation_id="i-1", target_type="assertion", target_id=41L)))
expect_error(build_promotion_requests(list(
  list(interpretation_id="i-1", target_type="person", target_id=41L)
)), "EVIDENCE_PROMOTION_TARGET_INVALID")
```

Tilføj en test, der sikrer, at en manglende `target_id` fejler og at ingen status (`accepted` alene) kan blive til en ny person.

- [ ] **Step 2: Kør testen rødt**

```bash
Rscript run-tests.R
```

Forvent: fejl fordi `build_promotion_requests` og CLI-scriptet mangler.

- [ ] **Step 3: Implementér minimal adapter**

Implementér kun inputform- og targetvalidering, deterministisk sortering på `interpretation_id` og en dry-run-rapport med antal gyldige/afviste requests. Scriptet må ikke åbne databaseforbindelse i dry-run og må ved skriveforsøg fejle med den angivne kode, indtil redaktions-UI/RPC-klienten implementeres i en senere plan.

- [ ] **Step 4: Kør R-testen grønt**

Kør `Rscript run-tests.R` og noter eventuelle etablerede, urelaterede skips separat.

- [ ] **Step 5: Commit**

```bash
git branch --show-current
git add .claude/skills/daa-extract/scripts/project_evidence.R .claude/skills/daa-extract/scripts/project_evidence_helpers.R .claude/skills/daa-extract/scripts/test_project_evidence.R tests/testthat/test-project-evidence.R
git commit -m "feat: prepare fail-closed evidence promotion requests"
```

### Task 5: Dokumentér cutover og afgræns næste UI-plan

**Files:**
- Modify: `docs/superpowers/specs/2026-08-03-evidens-promotion-kontrakt-design.md`
- Modify: `docs/superpowers/plans/2026-08-02-evidensbaseret-genimport-og-multislaegt.md`
- Create: `docs/superpowers/reviews/evidence-promotion-contract.md`

**Interfaces:**
- Producerer en kort, evidensbaseret GO/NO-GO for promotionkontrakten.
- Opdaterer Task 14, så den ikke længere lover automatisk kanonisk konstruktion eller zero-match-personoprettelse.

- [ ] **Step 1: Skriv den fejlede dokumentations-checkliste**

I review-notatet oprettes en checklist med de otte testkrav fra designets §8. Alle starter som `- [ ]`.

- [ ] **Step 2: Gennemfør og udfyld kun verificerede punkter**

Indsæt den præcise lokale kommando og resultat for SQL-kontrakt, RLS-negativtest, batch rollback, R-helpertest og CI-jobdefinition. Markér et punkt `ikke verificeret` frem for at udlede det af kode.

- [ ] **Step 3: Opdatér den oprindelige genimportplan**

Erstat Task 14's “projekterer kun accepterede promotions” med: “forbereder private forslag; alle kanoniske promotioner går via den versionerede redaktør-RPC”. Erstat zero-match/mixed-new-testkravet med eksplicit køtilstand uden personoprettelse.

- [ ] **Step 4: Kør samlet verifikation**

Kør SQL-kontraktjobbet, `Rscript run-tests.R` og `git diff --check`. Review-notatet må kun indeholde faktisk observerede resultater.

- [ ] **Step 5: Commit**

```bash
git branch --show-current
git add docs/superpowers/specs/2026-08-03-evidens-promotion-kontrakt-design.md docs/superpowers/plans/2026-08-02-evidensbaseret-genimport-og-multislaegt.md docs/superpowers/reviews/evidence-promotion-contract.md
git commit -m "docs: record evidence promotion contract gate"
```

## Efterfølgende, separat plan

Denne plan slutter med sikker backend og request-adapter. Først derefter designes redaktørfladen med record-preview, “acceptér alle sikre”, selektion, konfliktvisning og samtidighedshåndtering. UI-planen må ikke udvide prædikatprofilen eller give klienten direkte private tabeladgang.
