# 1939 Review Readable Sources and Sidebar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the private 1939 review sheet human-readable by showing exact dual-rendition source text and moving the active record list into a searchable left sidebar.

**Architecture:** The Python generator remains the only place that reads source files. It validates both complete source hashes, slices source-bound candidate spans fail-closed, verifies the raw excerpt hash, and embeds only the exact presentation text in the standalone HTML. The browser controller renders navigation in the sidebar, filters only the active view, and keeps technical evidence in collapsed disclosures.

**Tech Stack:** Python 3, pytest, standalone JavaScript, DOM/jsdom, Vitest, HTML/CSS.

## Global Constraints

- The artifact remains private and browser-local; it must not write to the database, Supabase, or Vercel.
- Exact source slices are presentation evidence only and do not promote or match records.
- Missing, malformed, out-of-range, or hash-mismatched source evidence fails closed during generation.
- The existing review decisions, local autosave, export schema, and active-view partitions remain unchanged.
- The navigation list contains only the active view and previous/next follows its search filter.
- Every visible name shows `Mangler`, `Kladde gemt`, or `Afsluttet`, and the sidebar reports `X mangler af Y` for the active view.
- Opaque IDs and hashes remain available only under technical details.

---

### Task 1: Hydrate Exact Dual Source Text

**Files:**
- Modify: `.claude/skills/daa-extract/scripts/make_human_review_1939.py`
- Modify: `.claude/skills/daa-extract/scripts/test_make_human_review_1939.py`

**Interfaces:**
- Consumes: source manifest hashes plus `candidate.details.calamari_span` and `candidate.details.raw_structure_bridge`.
- Produces: presentation-only `calamari_verbatim_text` and `raw_verbatim_text` candidate fields.

- [x] **Step 1: Write failing tests for exact slicing and complete-file raw hash validation**

Add tests that generate a source-bound candidate, assert both exact slices are embedded, and assert generation rejects a changed raw source or a mismatched raw excerpt hash.

- [x] **Step 2: Run the focused pytest file and verify the new tests fail for missing `--raw` and missing presentation fields**

Run: `/usr/bin/python3 -m pytest .claude/skills/daa-extract/scripts/test_make_human_review_1939.py -q`

- [x] **Step 3: Implement fail-closed source hydration**

Add `--raw`, validate `raw_ocr_sha256`, validate integer half-open spans against source lengths, verify `sha256(raw_slice)`, then add both verbatim fields without changing classifier evidence.

- [x] **Step 4: Run the focused pytest file and verify it passes**

Run: `/usr/bin/python3 -m pytest .claude/skills/daa-extract/scripts/test_make_human_review_1939.py -q`

### Task 2: Render Approved Sidebar and Readable Candidate Card

**Files:**
- Modify: `.claude/skills/daa-extract/scripts/human_review_1939_ui.js`
- Modify: `.claude/skills/daa-extract/scripts/make_human_review_1939.py`
- Modify: `web/src/humanReview1939Ui.test.ts`

**Interfaces:**
- Consumes: candidate presentation fields and the existing `views` record-key lists.
- Produces: `data-role="sidebar-navigation"`, `data-role="record-search"`, filtered record buttons with processing status and missing count, and labeled Calamari/raw source blocks.

- [x] **Step 1: Write failing DOM tests for sidebar placement, filtering, active-view isolation, readable question, dual labels, and hidden technical ID**

The test fixture must include the same sidebar container as the generated HTML. Assert that the list is inside the sidebar, search reduces the list, navigation follows the filtered list, names visibly distinguish `Mangler`, `Kladde gemt`, and `Afsluttet`, the missing counter updates, and the main card shows both source renditions before technical evidence.

- [x] **Step 2: Run the focused Vitest file and verify the new assertions fail**

Run: `npm test -- --run src/humanReview1939Ui.test.ts` from `web/`.

- [x] **Step 3: Implement minimal state, rendering, and responsive CSS**

Add independent `recordSearch` state, filter `visibleKeys`, render the dashboard/search/list into the sidebar container, use a native compact picker on small screens, and render `Er denne kildepost …?` plus labeled verbatim blocks. Keep the parser ID inside the existing technical disclosure.

- [x] **Step 4: Run focused DOM tests and refactor only while green**

Run: `npm test -- --run src/humanReview1939Ui.test.ts` from `web/`.

### Task 3: Regenerate a New Private Artifact and Verify the Real Sample

**Files:**
- Modify: `.claude/skills/daa-extract/SKILL.md`
- Create: `work/task19-1939-pilot/menneskeark-undtagelsesko-v2-run-g.html` (ignored private artifact)

**Interfaces:**
- Consumes: current E queue/review/source artifacts and both pinned OCR files.
- Produces: a new exclusive HTML artifact without overwriting earlier review files.

- [x] **Step 1: Update the documented generator command with `--raw`**

Use `../../../work_1939_stamtavle/raw.txt` and preserve the exclusive-output rule.

- [x] **Step 2: Generate a new versioned artifact**

Run the documented generator against the current authoritative queue with a new output suffix.

- [x] **Step 3: Verify Otto's exact Calamari and raw text plus navigation structure in the generated HTML**

Parse the embedded payload, find candidate `1939:dual-v1:a73293a837718f92f4e631477ea08de0342aecee8a5dd629c92cf752239f874b`, and assert both text fields contain `Otto Carl Ferdinand Christian Gottlieb`. Confirm sidebar and search roles occur in the HTML.

- [x] **Step 4: Run focused Python and DOM suites, then the proportionate broader suites**

Report focused and broader results separately, including environmental collection failures rather than calling them green.
