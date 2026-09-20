### Task 9: Close the remaining generic contract and integrity gaps

**Authority:** Owner-approved 2026-09-02 after the Task 8 SOL re-review found
six remaining specification gaps. This task is the single bounded correction
round for those findings. It does not reopen C3, #152 cutover policy, terminal
history semantics, production authority, or support for another real edition.

**Files:**

- Modify: `schema.sql`, `db-migrations.sql`, `db-rls.sql`, `db-verify.sql`
- Modify: `.claude/skills/daa-extract/scripts/apply_name_completion_helpers.R`
- Modify: `tests/sql/test-reimport-writer.sql`,
  `tests/sql/test-reimport-name-completion.sql`,
  `tests/sql/test-reimport-writer-migration.sql`,
  `tests/sql/reimport-writer-legacy-terminal-fixture.sql`,
  `tests/sql/reimport-writer-legacy-invalid-terminal-fixture.sql`,
  `tests/sql/inspect-reimport-writer-catalog.sql`
- Modify: `tests/integration/test-reimport-writer-locking.R`,
  `tests/integration/test-reimport-writer.R`,
  `tests/testthat/test-apply-name-completion.R`, and only directly affected
  facade/catalog tests
- Modify: this plan and
  `docs/evidensbaseret-genimport/reimport-writer-153-rehearsal.md` only with
  observed evidence

**Interfaces:**

- Consumes Task 8's generic v2 kernel, one-version 1939 facade, two-track
  terminal migration fixture and exact ACL matrix.
- Produces the complete generic RPC surface, server-bound name-completion
  apply gateway, collision-safe name inserts, closed typed profile config,
  complete routine-body parity and exact terminal result/source-record
  integrity.

- [ ] **Step 1: Specify the missing generic RPC contract RED**

  Add behavior-first SQL assertions for these exact generic signatures:

  ```text
  public.red_apply_reimport_canonical_delta(uuid,text,jsonb)
  public.red_lock_reimport_name_completion(text,bigint,text)
  public.red_authorize_reimport_name_completion(text,uuid,text,text,bigint,text,text,jsonb,jsonb)
  ```

  The lock must reject invalid or missing `(source_id, profile_id)` before
  mutation; the authorizer must reject a mismatched complete `(source_id,
  profile_id, profile_sha256)` triple. The dedicated canonical-delta entry point
  must take the shared v2 lock, validate the open batch/profile writer boundary
  and then fail closed with
  `REIMPORT_WRITER_CANONICAL_DELTA_UNSUPPORTED`; it must never call the
  name-completion writer. The exact legacy wrapper must pin the seeded 1939
  identity and translate that error to
  `REIMPORT_1939_CANONICAL_DELTA_UNSUPPORTED` without changing rows. Extend the
  signature-specific ACL tests: the generic canonical-delta and lock are
  authenticated-only, the generic name-completion authorizer is
  service-role-only, and all three remain denied to `PUBLIC`/`anon`.

  Run the focused SQL tests and record the expected missing-signature or wrong-
  behavior failures before changing DDL.

- [ ] **Step 2: Implement the RPCs and server-bind apply-mode name completion**

  Implement the three signatures identically in fresh and migration DDL,
  update exact revokes/grants and all 1939 wrappers, and remove the facade's
  synthetic `{}` call into `red_apply_reimport_name_completion`. In the R DBI
  gateway, return the complete server `authorization` object from
  `red_preflight_reimport_name_completion`; validate its database name, system
  identifier and exact source/profile/hash against both the supplied
  authorization and manifest before `red_begin_reimport_name_completion`.
  Add an apply-mode test in which the supplied object is locally valid but the
  server returns a different source/profile/hash; require rollback and
  `REIMPORT_NAME_COMPLETION_AUTHORIZATION_REQUIRED` or the narrower existing
  database/profile mismatch token before any child batch is created. Run the R
  and SQL tests to GREEN.

- [ ] **Step 3: Close and consume `writer_config` RED/GREEN**

  Add fresh/migration tests proving a profile is rejected unless
  `writer_config` is a JSON object with exactly these eight keys and no others:

  ```text
  run_key_prefix, schema_version, extractor_version, rendition_key,
  rendition_kind, rendition_metadata, observation_extraction_method,
  citation_label_template
  ```

  The seven scalar values must be non-empty strings; `rendition_metadata` must
  be an object; `citation_label_template` must contain the literal
  `{page_from}` exactly once and must not contain another brace placeholder.
  Implement one immutable private validator used by the table constraint in
  fresh and migration DDL. Build the inserted citation label from that template
  by replacing `{page_from}` with the authorized payload's integer page value,
  and assert both profiles get their own literal label. Reject missing, extra,
  null, wrong-typed and malformed-template fixtures before a profile row is
  stored. Re-run profile, name-completion, migration and parity tests.

- [ ] **Step 4: Prove collision-safe cross-profile writes RED/GREEN**

  Extend the disposable two-connection integration test from lock acquisition
  to two real, authorized name-completion writes for different profiles. Hold
  the first transaction across ID allocation, start the second, release the
  first, then require both commits, distinct `fact.id`/`citation.id`, complete
  result/event rows and no duplicate-key error. First observe the current
  `max(id)+1` collision. Then serialize only the shared legacy ID-allocation
  critical section with a dedicated transaction advisory lock, acquired after
  the global contract and source/profile locks and before computing both IDs.
  Record the intentional trade-off: profile lifecycle state remains
  independent, while the two global integer-ID allocations are briefly
  serialized because those public tables do not own safe sequences. Do not
  broaden this task into identity-column conversion or unrelated writer
  changes.

- [ ] **Step 5: Complete routine parity and terminal source-record integrity**

  Replace the hand-selected routine subset in
  `inspect-reimport-writer-catalog.sql` with the complete explicitly versioned
  #153 kernel/facade set, including at least
  `private.lock_reimport_writer`,
  `private.validate_reimport_authorization_payload`,
  `private.validate_reimport_writer_config`,
  `private.reject_reimport_writer_mutation`, and
  `public.red_preflight_reimport_authorization`, plus the new generic RPCs.
  Keep signature, owner, definer, search path, ACL and
  `pg_get_functiondef` SHA-256 in the byte-comparable receipt. Require exact
  fresh/clean-upgraded parity.

  In the terminal migration guard, require each name-completion result's
  `source_record_id` to resolve to the source parent's exact
  `person_create` event `source_record_key` and source. Add a fixture that
  changes only `result.source_record_id` to a different valid record while all
  other references remain valid; the migration must fail and roll back. Run
  both approved historical terminal topologies, every invalid topology,
  atomicity and clean-upgrade parity to GREEN.

- [ ] **Step 6: Review, verify and close Task 8/9**

  Self-review the full Task 9 diff against all six SOL findings and every
  relevant §3-§5 specification clause. Run the complete disposable fresh-v2,
  clean-upgraded-v2, historical-v1 terminal migration, C3 fail-closed, ACL,
  DBI, R/testthat, catalog and build gates with all five PG variables. Obtain a
  fresh task-scoped Codex review, critically fix valid findings and rerun the
  affected evidence. Then obtain one GPT-5.6-Sol xhigh independent read-only
  re-review because this correction materially changes the public RPC,
  concurrency and migration-integrity risk profile. Update only observed
  rehearsal evidence, mark Task 8 Step 6 and this step complete, and commit.
  No production action, push, merge or production GO.
