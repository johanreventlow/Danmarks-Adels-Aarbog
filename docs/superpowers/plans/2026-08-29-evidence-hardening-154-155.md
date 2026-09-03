# Evidenshærdning #154 og #155 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` and implement one task at a time. The SQL tests below must first fail for the stated missing behaviour before changing production SQL.

**Goal:** Lukke #154's tavse RPC-grant-drift og #155's konkrete integritet-,
migrations- og JSON-kontrakthuller, uden produktionsadgang eller ændringer af
den narrative-record-model i #152.

**Architecture:** `schema.sql` er clean-slate-kontrakten og
`db-migrations.sql` er den additive kontrakt. `db-verify.sql` ejer de
database-nære negative og samtidige beviser; Python ejer læsning og driftstest
af JSON-Schema-filer. CI opretter alene PostgreSQL-servicecontainere og kører
begge installationsveje mod disposerbare databaser.

**Tech Stack:** PostgreSQL 17, psql, dblink, GitHub Actions og Python 3.11/
pytest.

## Ufravigelige rammer

- Udfør kun arbejdet i worktree `fix/evidence-hardening-154-155`; kontrollér
  `git branch --show-current` og `git status --short` før hver ændring og
  commit.
- Kør aldrig `db-verify.sql`, migrations eller fixtures mod production eller en
  delt lokal database. CI bruger kun servicecontainerens database.
- Lad `UPDATE`/`DELETE`-beskyttelsen være; den eksisterer allerede. Tilføj kun
  den manglende `TRUNCATE`-beskyttelse.
- `public.red_*`-ACL-policyen skal være en udtrykkelig, versionsstyret test-
  allowlist, ikke en navneheuristik eller implicit `PUBLIC`-grant.
- En accepted revision må aldrig selv flytte en anchor. En re-anchoring skal
  altid være en append-only ny anchor-version med auditmetadata.

## Task 1: Første fejlede SQL-kontrakter

**Files:**

- Modify: `db-verify.sql`

- [ ] Tilføj den minimale failing test for hver ny invariant, uden at ændre
  `schema.sql` eller `db-migrations.sql`:

  - Opret en syntetisk `public.red_evidence_acl_verify()` i `db-verify.sql`.
    Assertér, at `SET LOCAL ROLE anon` og `authenticated` begge fejler før
    grant; giv derefter kun `authenticated` EXECUTE og assertér success for
    rollen og fortsat denial for `anon`. Ryd objektet op inden den omgivende
    rollback-sentinel.
  - Byg et `VALUES`-baseret ACL-policy-katalog over alle aktuelle
    `public.red_*`-overloads, med de tre forventede booleske grants for
    `anon`, `authenticated` og `service_role`. Fejlmeldingen skal udskrive
    `p.oid::regprocedure` for både uklassificerede og forkert grantede RPC'er.
    `PUBLIC` EXECUTE skal være forbudt for hver post.
  - Udvid den eksisterende evidence-fixture med en `TRUNCATE
    private.source_observation`; kræv `EVIDENCE_APPEND_ONLY`, derefter en
    succesfuld INSERT, så en fejlet statement ikke forgifter fixtureforløbet.
    Katalogassertionen skal kontrollere en aktiv row-trigger for `UPDATE`/
    `DELETE` og en aktiv statement-trigger for `TRUNCATE` på alle 11 tabeller.
  - Opret to source records og occurrences. Forankr successor-recorden
    accepted og forsøg derefter en accepted `split_into` til den: forvent en
    specifik `EVIDENCE_REVISION_SUCCESSOR_ALREADY_ANCHORED`-fejl. Bevis den
    positive vej i en separat fixture: accepted revision til en frisk,
    uforankret successor; ny `rejected` version af den gamle anchor med
    auditmetadata; derpå accepted anchor til successor.
  - Efter en succesfuld `red_decide_interpretation(..., 'accepted', ...)`,
    kald samme RPC på den accepted version og assertér en ny domænefejl og
    uændret antal versioner. Gentag for `rejected`, `unresolved` og
    `superseded`; behold den eksisterende stale-version-test som særskilt
    regressionscase.
  - Tilføj en dblink-gate med to transaktioner mod samme proposed
    interpretation. Den anden writer skal blokere før den første committer;
    efter commit skal den fejle på status/aktuel-version og må ikke efterlade
    endnu en decision-version. Registrér gaten i
    `tests/sql/run-db-verify-disposable.sql`.

- [ ] Kør den isolerede databasekontrakt på en **helt frisk lokal disposable
  database** med alle fem PG-parametre sat (`PGHOST`, `PGPORT`, `PGUSER`,
  `PGPASSWORD`, `PGDATABASE`). Bekræft, at hver ny assertion fejler for den
  manglende feature og ikke på fixture- eller rollekonfiguration.

## Task 2: Implementér den minimale clean-slate- og migrations-ændring

**Files:**

- Modify: `schema.sql`
- Modify: `db-migrations.sql`
- Modify: `db-verify.sql`

- [ ] I `schema.sql` udvid den eksisterende loop over de 11 evidenstabeller
  med et separat `BEFORE TRUNCATE ... FOR EACH STATEMENT`-triggernavn (fx
  `_append_only_truncate`) til `private.reject_evidence_mutation()`.
  Bevar den eksisterende row-trigger uændret.

- [ ] Erstat `private.validate_source_record_revision_event()` i både
  `schema.sql` og `db-migrations.sql`. Efter stabil `FOR UPDATE`-låsning af
  predecessor/successor og før INSERT returneres, skal en accepted revision
  afvises, når `private.source_record_anchor_current` har en accepted row for
  `NEW.successor_record_id`; brug fejlkoden
  `EVIDENCE_REVISION_SUCCESSOR_ALREADY_ANCHORED`. `proposed` og `rejected`
  revisions må fortsat versioneres. Revisionen ændrer ikke anchor-events.

- [ ] Erstat `red_decide_interpretation()` i begge SQL-filer. Efter låsning af
  den aktuelle række skal den kræve `v_current.status='proposed'`, før den
  indsætter version+1, ellers fejlmeldingen
  `EVIDENCE_INTERPRETATION_NOT_PROPOSED`. Bevar aktør-, rolle-, evidence- og
  stale-version-kontrollerne samt samme `FOR UPDATE`-serialisering.

- [ ] I migrations-loopet: drop/recreate både row- og truncate-triggerne,
  så en eksisterende database opgraderes idempotent. Kør derefter den fokuserede
  failing SQL-suite igen og bekræft green; kør den en gang mere for at bevise
  migrations-idempotens.

## Task 3: Gør JSON-schema til en kørt kontrakt

**Files:**

- Modify: `.claude/skills/daa-extract/references/interpretation-schema.json`
- Modify: `.claude/skills/daa-extract/scripts/test_evidence_contract.py`

- [ ] Tilføj først pytests, der indlæser både observations- og fortolknings-
  schema med `json.loads`, kræver Draft 2020-12-URI'en, og sammenligner
  fortolkningsstatus' lukkede enum med SQL-kontraktens fem værdier:
  `proposed`, `accepted`, `rejected`, `unresolved`, `superseded`.
  Testen skal mislykkes, fordi de to sidste endnu mangler.

- [ ] Tilføj kun `unresolved` og `superseded` til JSON-enum'en. Kør den
  fokuserede test og hele `test_evidence_contract.py` med `/usr/bin/python3`.

## Task 4: Test den faktiske migrationsvej i CI

**Files:**

- Create: `tests/sql/evidence-hardening-pre-migration.sql`
- Modify: `.github/workflows/ci.yml`

- [ ] Opret en test-only, versionsfast pre-#154/#155 baseline. Den kører efter
  den nuværende clean schema-installation i en tom database og genskaber kun
  de tre berørte gamle kontrakter: ingen TRUNCATE-triggere, den gamle
  revision-validator og den gamle `red_decide_interpretation`. Kommentér
  dens basiscommit og forbyd brug uden for test. Den er ikke en produktion-
  rollback.

- [ ] Udvid `evidence-promotion-db` med to adskilte, navngivne databaseforløb
  i samme PostgreSQL 17-service:

  1. **Migreret baseline:** bootstrap, `schema.sql`, `db-rls.sql`,
     `evidence-hardening-pre-migration.sql`, `db-migrations.sql` to gange,
     `tests/sql/test-evidence-promotion.sql`, derefter
     `tests/sql/run-db-verify-disposable.sql`.
  2. **Fresh schema:** bootstrap i en ny database, `schema.sql`, `db-rls.sql`,
     `db-migrations.sql` to gange, samme smalle og fulde verify-suite.

  Brug eksplicit `PGHOST=localhost`, `PGPORT=5432`, `PGUSER=postgres`,
  `PGPASSWORD=postgres` og den rigtige `PGDATABASE` ved den komplette
  `db-verify`-kørsel, så dblink aldrig falder tilbage til en anden port eller
  database.

- [ ] Kør workflow-trinnets psql-kommandoer lokalt mod en disposable PG17-
  instans, hvis tilgængelig; ellers markér lokalt som sandbox-/miljøbegrænset
  og lad CI være den autoritative kørselsgate. `git diff --check` skal altid
  være grønt.

## Task 5: Dokumentér den transactionelle deploy-kontrakt

**Files:**

- Modify: `docs/database-current-state.md`

- [ ] Tilføj en kort, operationsnær note: global default revoke gælder den
  normale deploy-ejer; en ny `public.red_*` kræver en eksplicit rolleklassifi-
  cering og passende `GRANT EXECUTE` i samme transaktion som `CREATE OR
  REPLACE FUNCTION`. Angiv at den katalogbaserede `db-verify`-policy og begge
  CI-installationsveje er gate; ingen note må påstå produktionstilstand eller
  udført deploy.

- [ ] Kør og registrér:

  ```bash
  /usr/bin/python3 -m pytest .claude/skills/daa-extract/scripts/test_evidence_contract.py -q
  git diff --check
  git status --short
  ```

## Task 6: Selvreview, uafhængigt review og afslutning

- [ ] Selvreview den samlede diff med fokus på: ACL-allowlistens fuldstændig-
  hed, `SECURITY DEFINER`-adgang, trigger-enable-status, migrationens
  idempotens, db-verify cleanup, dblink-lock-tidsgrænser og at baseline-scriptet
  ikke kan bruges som produktion-rollback.
- [ ] Kør relevante database- og Python-suiter samt den fulde passende
  repository-verifikation. Rapporter fokuserede og fulde resultater separat.
- [ ] Lad Claude Fable 5 udføre én skrivebeskyttet review af den faktiske diff
  og relevant omkringliggende SQL/CI. Vurder hvert fund teknisk; ret kun
  gyldige fund og kør de berørte tests igen. Gentag kun Fable-review, hvis en
  rettelse ændrer design eller risikoprofil væsentligt.
- [ ] Commit først efter grøn verification og rent `git diff --check`. Ingen
  push, merge eller produktionshandling uden særskilt brugeraccept.
