# 1939 v50 C3 Identity Invariants Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Historisk status (2026-09-03):** Checkboksene er planens oprindelige
> arbejdsspor, ikke en aktuel udførelseslog eller en C3-apply-autorisation.
> Kontrollér levende SQL, changelog, commits og aktuelle tests; brug
> `docs/evidensbaseret-genimport/status.md` for genimportprogrammets samlede
> status og næste tilladte arbejde.

**Goal:** Harden the general `samme_som`/`ikke_samme_som` database invariants so C3 can safely record five `FORSKELLIGE` decisions without component contradictions or races with person deletion.

**Architecture:** Reuse `_samme_som_gruppe()` as the one component oracle, enforce cross-component contradictions in the general RPC/trigger layer, and serialize all identity mutations and person deletion through one advisory-lock and sorted person-row-lock order. Verify the live schema, migration mirror, ACL surface, rollback behavior, and two-session concurrency before the C3 batch writer is allowed to depend on these primitives.

**Tech Stack:** PostgreSQL 17 SQL/PLpgSQL, Supabase Auth/RLS conventions, `psql`, `dblink`, R/testthat integration harness.

**Spec:** `docs/superpowers/specs/2026-08-22-1939-v50-fase-c3-apply-design.md`

## Global Constraints

- No `work/` file may be read, printed, committed, or copied into tests.
- No production database mutation is authorized by this plan.
- New `SECURITY DEFINER` code uses a fixed `search_path`, explicit actor/role checks, fully qualified objects, and explicit revoke/grant statements.
- Acquire `same_som_mutation` before person-row locks; lock person rows in ascending ID order.
- `/usr/bin/python3` remains the only Python interpreter, although this plan is SQL/R-only.
- Database tests run only against disposable databases; all five `PGDATABASE`, `PGHOST`, `PGPORT`, `PGUSER`, and `PGPASSWORD` are set together or all omitted.
- Each task ends with fresh focused verification, spec review, code-quality review, and a separate commit.

---

### Task 1: Enforce component-wide identity contradictions

**Files:**
- Modify: `schema.sql`
- Modify: `db-migrations.sql`
- Modify: `db-verify.sql`
- Create: `tests/sql/test-1939-v50-c3-identity-invariants.sql`

**Interfaces:**
- Consumes: `public._samme_som_gruppe(bigint) -> table(pid bigint)`.
- Produces: `private.identity_components_have_rejection(bigint,bigint) -> boolean` and hardened `public.red_ikke_samme_som`/`private.enforce_samme_som_invariants` behavior.

- [ ] **Step 1: Write failing component-conflict SQL tests**

Add transaction-scoped fixtures proving both indirect contradictions:

```sql
-- Component A: a1 -> ac; component B: b1 -> bc.
-- FORSKELLIGE inside one component must fail.
PERFORM public.red_samme_som(a1, ac);
PERFORM public.red_samme_som(a2, ac);
BEGIN
  PERFORM public.red_ikke_samme_som(a1, a2);
  RAISE EXCEPTION 'EXPECTED_COMPONENT_DIFFERENT_REJECTION';
EXCEPTION WHEN others THEN
  IF SQLERRM NOT LIKE '%IDENTITY_COMPONENT_CONTRADICTION%' THEN RAISE; END IF;
END;

-- An existing rejection between components must block every bridge edge.
PERFORM public.red_ikke_samme_som(a1, b1);
BEGIN
  PERFORM public.red_samme_som(a2, b2);
  RAISE EXCEPTION 'EXPECTED_COMPONENT_SAME_REJECTION';
EXCEPTION WHEN others THEN
  IF SQLERRM NOT LIKE '%IDENTITY_COMPONENT_CONTRADICTION%' THEN RAISE; END IF;
END;
```

Also prove direct idempotency remains unchanged and a rejection between truly separate components succeeds.

- [ ] **Step 2: Run the focused SQL test and confirm RED**

Run against a disposable database loaded with current schema/migrations:

```bash
/opt/homebrew/opt/postgresql@17/bin/psql --set=ON_ERROR_STOP=1 --dbname="$PGDATABASE" --file=tests/sql/test-1939-v50-c3-identity-invariants.sql
```

Expected: the indirect same-component and cross-component rejection tests reach their sentinel failures.

- [ ] **Step 3: Implement one component-rejection oracle**

Define identically in `schema.sql` and `db-migrations.sql`:

```sql
CREATE OR REPLACE FUNCTION private.identity_components_have_rejection(
  p_left bigint, p_right bigint
) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, public, private
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.relation r
    WHERE r.rolle = 'ikke_samme_som'
      AND r.subjekt_type = 'person' AND r.objekt_type = 'person'
      AND (
        (r.subjekt_id IN (SELECT pid FROM public._samme_som_gruppe(p_left))
         AND r.objekt_id IN (SELECT pid FROM public._samme_som_gruppe(p_right)))
        OR
        (r.objekt_id IN (SELECT pid FROM public._samme_som_gruppe(p_left))
         AND r.subjekt_id IN (SELECT pid FROM public._samme_som_gruppe(p_right)))
      )
  )
$$;
```

Revoke all public execution on the helper. In `red_ikke_samme_som`, reject when the two component ID sets overlap. In `enforce_samme_som_invariants`, call the helper before inserting a bridge edge and raise the stable token `IDENTITY_COMPONENT_CONTRADICTION`.

- [ ] **Step 4: Add drift assertions to `db-verify.sql`**

Assert the helper exists with `prosecdef=true`, the fixed search path, no `PUBLIC`/`anon`/`authenticated` execute privilege, and both component-negative scenarios pass inside a rolled-back verification block.

- [ ] **Step 5: Run focused and existing identity verification**

Run:

```bash
/opt/homebrew/opt/postgresql@17/bin/psql --set=ON_ERROR_STOP=1 --dbname="$PGDATABASE" --file=tests/sql/test-1939-v50-c3-identity-invariants.sql
/opt/homebrew/opt/postgresql@17/bin/psql --set=ON_ERROR_STOP=1 --dbname="$PGDATABASE" --file=db-verify.sql
```

Expected: both commands exit 0 with the transaction rolled back.

- [ ] **Step 6: Commit Task 1**

```bash
git add schema.sql db-migrations.sql db-verify.sql tests/sql/test-1939-v50-c3-identity-invariants.sql
git commit -m "fix(identity): enforce component contradictions"
```

---

### Task 2: Serialize identity writes with person deletion

**Files:**
- Modify: `schema.sql`
- Modify: `db-migrations.sql`
- Modify: `db-verify.sql`
- Modify: `tests/sql/test-1939-v50-c3-identity-invariants.sql`
- Create: `tests/integration/test-1939-v50-c3-identity-concurrency.R`

**Interfaces:**
- Consumes: component oracle from Task 1.
- Produces: `private.lock_identity_people(bigint[]) -> void`; hardened `red_samme_som`, `red_ikke_samme_som`, and `red_slet_person` lock ordering.

- [ ] **Step 1: Write a failing lock-order unit test**

Add catalog/source assertions requiring all three public writers to acquire `same_som_mutation` before person-row locks, and require the helper to sort/deduplicate IDs:

```sql
SELECT private.lock_identity_people(ARRAY[p_high, p_low, p_low]);
-- A second session locking p_low must block before it can mutate either endpoint.
```

The helper must raise `IDENTITY_PERSON_NOT_FOUND` if the locked row count differs from the deduplicated non-`NULL` input set; negative fixture IDs are valid `bigint` person IDs in repository tests.

- [ ] **Step 2: Write a failing two-session race test**

Use `dblink` or two DBI connections in the R integration test:

1. session A begins `red_ikke_samme_som(a,b)` and pauses after locks;
2. session B calls `red_slet_person(a)` with a short `lock_timeout`;
3. session B must time out/block, never commit a deletion past A;
4. repeat with session A using `red_samme_som(a,b)`;
5. reverse the starting order and prove the identity writer waits or fails because the person no longer exists;
6. after both schedules, assert no person relation endpoint references a missing person.

- [ ] **Step 3: Confirm RED**

Run:

```bash
Rscript tests/integration/test-1939-v50-c3-identity-concurrency.R
```

Expected: at least one schedule demonstrates the current orphan race or missing shared lock order.

- [ ] **Step 4: Implement the sorted row-lock helper and writer order**

Define:

```sql
CREATE OR REPLACE FUNCTION private.lock_identity_people(p_person_ids bigint[])
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public, private AS $$
DECLARE v_expected integer; v_locked integer;
BEGIN
  SELECT count(*) INTO v_expected
  FROM (SELECT DISTINCT x FROM unnest(p_person_ids) x WHERE x IS NOT NULL) q;
  SELECT count(*) INTO v_locked
  FROM (
    SELECT p.id FROM public.person p
    WHERE p.id IN (SELECT DISTINCT x FROM unnest(p_person_ids) x)
    ORDER BY p.id FOR UPDATE
  ) q;
  IF v_expected < 1 OR v_locked <> v_expected THEN
    RAISE EXCEPTION 'IDENTITY_PERSON_NOT_FOUND';
  END IF;
END $$;
```

Each writer must call, in order:

```sql
PERFORM pg_advisory_xact_lock(hashtext('samme_som_mutation'));
PERFORM private.lock_identity_people(ARRAY[p_left, p_right]);
```

`red_slet_person` takes the same advisory lock before locking its single person row and before collecting relation IDs.

- [ ] **Step 5: Verify all schedules and rollback/undo behavior**

Run the focused SQL test, R concurrency test, and the relevant `db-verify.sql` blocks. Assert exact idempotency still creates no empty change set.

- [ ] **Step 6: Commit Task 2**

```bash
git add schema.sql db-migrations.sql db-verify.sql tests/sql/test-1939-v50-c3-identity-invariants.sql tests/integration/test-1939-v50-c3-identity-concurrency.R
git commit -m "fix(identity): lock people before relation writes"
```

---

### Task 3: Prove deployable identity hardening

**Files:**
- Verify all files from Tasks 1–2
- Modify only if a test exposes a defect: `db-rls.sql`

**Interfaces:**
- Produces: the reviewed identity prerequisite consumed by the C3 atomic apply plan.

- [ ] **Step 1: Run schema/migration parity checks**

Create two disposable databases, load `schema.sql` into one and the repository migration/bootstrap path into the other, then compare `pg_get_functiondef`, ACLs, triggers, and relevant constraints for every touched function.

- [ ] **Step 2: Run authorization gates**

Test `anon`, authenticated member, authenticated redactor, and direct-connection redactor claims. The direct redactor test runs:

```sql
BEGIN READ ONLY;
SELECT set_config('request.jwt.claim.sub', '<synthetic-redactor-uuid>', true);
SELECT public.red_ikke_samme_som(<synthetic-a>, <synthetic-b>);
ROLLBACK;
```

Expected: valid redactor reaches a read-only write error; other roles fail with the role token.

- [ ] **Step 3: Run full SQL and repository regressions**

Run `db-verify.sql`, all SQL integration tests, the full R suite, and the full Python suite with `/usr/bin/python3`. Report SQL, R, and Python separately.

- [ ] **Step 4: Audit forbidden privilege expansion**

Verify no new table DML grant, no helper execution grant, no dynamic SQL, no unfixed `search_path`, and no function callable by `PUBLIC` beyond the existing deliberate surface.

- [ ] **Step 5: Commit any test-proven parity correction**

If no correction was required, make no commit. Otherwise commit only the exact verified parity/ACL fix with a narrow message.

- [ ] **Step 6: Stop at the prerequisite checkpoint**

Record focused/full results and the commit range. Do not connect to production or start C3 apply artifacts until both independent spec and quality reviews approve this plan's output.
