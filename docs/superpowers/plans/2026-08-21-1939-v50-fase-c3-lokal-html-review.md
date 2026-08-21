# Fase C3 — lokal HTML-reviewflade Implementation Plan

> **For Codex:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Use superpowers:test-driven-development for every behavior change and superpowers:verification-before-completion before commits and handoff.

**Goal:** Byg en lokal, selvstændig HTML-flade, som gør de 15 eksisterende C3-beslutningstokens redigerbare uden at ændre resten af det hashbundne tekstark, og stop ved menneskelig gennemgang af den downloadede tekstfil.

**Architecture:** En ny Python 3.9-generator genbruger den eksisterende C3-review-builder og beslutningskonverter som autoritative validatorer. Den indlejrer reviewarkets rå bytes og et valideret view-model som Base64 i én statisk HTML-fil. Browserkode renderer alene med sikre DOM-API'er og eksporterer ved at erstatte præcise token-byteintervaller. Alle tests bruger syntetiske data; virkelig `work/`-data må kun behandles af CLI'en og må aldrig åbnes i model-, browser- eller testoutput.

**Tech Stack:** Python 3.9.6 (`/usr/bin/python3`), stdlib, pytest, HTML/CSS/vanilla JavaScript, Node 22, Playwright 1.61/Chromium.

**Approved design:** `docs/superpowers/specs/2026-08-21-1939-v50-fase-c3-lokal-html-review-design.md`

---

## Binding constraints

- Run every Python command with `/usr/bin/python3` and keep syntax compatible with Python 3.9.
- Never print, inspect, screenshot, or send actual `work/` contents to a model or browser tool.
- Never commit anything under `work/`.
- The HTML may create only an explicit browser download; it must not use network, database, Supabase, browser storage, cookies, IndexedDB, `eval`, `Function`, `innerHTML`, inline event handlers, or external assets.
- Do not modify the decision grammar or bypass `convert_c3_decisions_1939_v50.py`.
- Do not run the converter on the user's edited file during this plan.
- Do not write to PostgreSQL. If a later task needs database access, all five `PGDATABASE`, `PGHOST`, `PGPORT`, `PGUSER`, and `PGPASSWORD` must be set together or all omitted.
- Make one implementation commit per task after its focused verification and review are green.

## Files

Create:

- `.claude/skills/daa-extract/scripts/build_c3_html_review_1939_v50.py`
- `.claude/skills/daa-extract/scripts/test_build_c3_html_review_1939_v50.py`
- `.claude/skills/daa-extract/scripts/c3_html_review_test_fixtures.py`
- `.claude/skills/daa-extract/scripts/test_c3_html_review_browser_1939_v50.mjs`

Read and reuse without changing unless a failing test proves a compatibility defect:

- `.claude/skills/daa-extract/scripts/build_c3_review_1939_v50.py`
- `.claude/skills/daa-extract/scripts/convert_c3_decisions_1939_v50.py`
- `.claude/skills/daa-extract/scripts/test_build_c3_review_1939_v50.py`
- `.claude/skills/daa-extract/scripts/test_convert_c3_decisions_1939_v50.py`

Generate locally but never commit:

- `work/task27-1939-v50-c3-review/c3-review.html`
- later, by the user in the browser: `c3-afgoerelser-redigeret.txt`

---

### Task 1: Lock the HTML payload and token-interval contract

**Files:**

- Create: `.claude/skills/daa-extract/scripts/test_build_c3_html_review_1939_v50.py`
- Create: `.claude/skills/daa-extract/scripts/c3_html_review_test_fixtures.py`
- Create: `.claude/skills/daa-extract/scripts/build_c3_html_review_1939_v50.py`

**Step 1: Add a synthetic seven-case fixture factory**

Build the smallest synthetic selection/state/review chain that satisfies the existing C3 validators. The factory must generate exactly seven cases, eight records, 15 decisions, the locked 1017/1021 special case, Danish UTF-8 text, and inert attack strings such as `</script><img src=x onerror=globalThis.__C3_PWNED__=1>`.

Expose a test-only API and CLI:

```python
def write_fixture(output_dir: Path) -> Dict[str, Path]:
    """Write selection.json, state.json and review.txt; return their paths."""

def main(argv: Optional[Sequence[str]] = None) -> int:
    """Accept --output-dir and print only file basenames plus safe hashes/counts."""
```

The review file must be produced through the existing `render_review()` rather than handwritten, so fixture grammar cannot drift from production.

**Step 2: Write failing unit tests for validation and slot discovery**

Test the future public seams:

```python
slots = decision_slots(review_bytes, selection_doc, state_doc, input_hashes)
assert len(slots) == 15
assert len({slot["decision_id"] for slot in slots}) == 15
assert all(slots[i]["end"] <= slots[i + 1]["start"] for i in range(14))
assert review_bytes[slots[0]["start"]:slots[0]["end"]].decode("utf-8") == slots[0]["default_token"]
```

Add negative tests for:

- selection, state, and review hash drift;
- a missing, extra, duplicate, or reordered decision line;
- duplicate decision IDs;
- zero-width, out-of-range, or overlapping byte intervals;
- invalid UTF-8 in the review bytes;
- any count other than seven cases, eight records, and 15 decisions;
- a broken 1017/1021 special contract.

Assert stable public errors beginning with `C3_HTML_`, and assert exceptions do not contain synthetic names or narrative text.

**Step 3: Run the tests and confirm RED**

Run:

```bash
/usr/bin/python3 -m pytest -q .claude/skills/daa-extract/scripts/test_build_c3_html_review_1939_v50.py
```

Expected: FAIL because the generator module/API does not exist.

**Step 4: Implement fail-closed validation and exact byte intervals**

The module must import the existing review and converter modules. Validate the exact byte hashes, decode strictly as UTF-8, then call the converter on the complete review before locating slots. Derive semantic order from `review_sequence()` and locate each decision token only at the position implied by the fully validated line, never with a global token search.

Use immutable interval records internally:

```python
@dataclass(frozen=True)
class DecisionSlot:
    decision_id: str
    case_id: str
    decision_type: str
    start: int
    end: int
    default_token: str
    allowed_person_ids: Tuple[int, ...]
```

After constructing slots, require unique IDs, strict source ordering, valid UTF-8 boundaries, non-overlap, and byte-for-byte equality between every interval and its expected default token. Return JSON-safe dictionaries only at the HTML boundary.

**Step 5: Run focused tests and confirm GREEN**

Run:

```bash
/usr/bin/python3 -m pytest -q .claude/skills/daa-extract/scripts/test_build_c3_html_review_1939_v50.py
```

Expected: all Task 1 tests pass.

**Step 6: Review and commit Task 1**

Inspect the diff for accidental production data, duplicated decision grammar, unstable exception text, Python >3.9 syntax, and writes outside test temp directories. Then run:

```bash
git add .claude/skills/daa-extract/scripts/build_c3_html_review_1939_v50.py .claude/skills/daa-extract/scripts/test_build_c3_html_review_1939_v50.py .claude/skills/daa-extract/scripts/c3_html_review_test_fixtures.py
git commit -m "feat(1939): validate C3 HTML review payload"
```

---

### Task 2: Generate the self-contained safe review interface

**Files:**

- Modify: `.claude/skills/daa-extract/scripts/build_c3_html_review_1939_v50.py`
- Modify: `.claude/skills/daa-extract/scripts/test_build_c3_html_review_1939_v50.py`

**Step 1: Write failing tests for the generated artifact**

Add tests proving:

- exactly seven case navigation entries and 15 decision controls are represented in the payload;
- six ordinary cases have identity plus record controls and the special case has three controls;
- defaults and closed choice sets match the approved design;
- names, narratives, raw review bytes, and payload JSON are Base64 data, not interpolated HTML/JavaScript;
- dynamic rendering uses `textContent`/element properties and never `innerHTML`;
- no network, external asset, database, Supabase, storage, cookie, IndexedDB, `eval`, `Function`, or inline-event path occurs;
- the extracted script parses with real `node --check`;
- the Base64 payload separator cannot terminate or mutate the script;
- changing token length still permits descending-offset byte replacement;
- unchanged export bytes exactly equal the source review bytes;
- Danish characters and original newline bytes survive unchanged outside token intervals.

The script parse test must extract the actual `<script>` from generated synthetic HTML into a temporary `.js` file and execute:

```python
subprocess.run(["node", "--check", str(script_path)], check=True, capture_output=True, text=True)
```

**Step 2: Run the new tests and confirm RED**

Run the same focused pytest command. Expected: FAIL because HTML rendering and client export are absent.

**Step 3: Implement a Base64-only document boundary**

Implement these Python seams:

```python
def build_payload(
    selection_doc: Mapping[str, Any],
    state_doc: Mapping[str, Any],
    review_bytes: bytes,
    input_hashes: Mapping[str, str],
) -> Dict[str, Any]:
    """Return the validated seven-card, 15-slot browser view-model."""

def render_html(payload: Mapping[str, Any], review_bytes: bytes) -> bytes:
    """Return one complete UTF-8 HTML document with Base64 data blocks."""
```

Use fixed, generated HTML markup only. Put the Base64 strings in non-executable data elements whose content alphabet cannot contain `<`, `>`, quotes, or `/`. Parse the decoded JSON only after page load.

**Step 4: Implement safe controls and byte-preserving export**

The browser script must:

- create elements with `document.createElement()`;
- set all untrusted strings with `textContent`;
- render identity choices `UAFKLARET`, `FORSKELLIGE`, and `SAMME alias canonical`;
- render record choices `UAFKLARET`, `TIL person`, `INGEN_PUBLIKATION`, and the three closed `REVISION` kinds;
- reject alias equal to canonical both in UI state and again immediately before export;
- show the exact output token beside every control;
- show case navigation, previous/next, and resolved/unresolved counts;
- reconstruct a fresh `Uint8Array` from original bytes plus descending slot replacements;
- download only after explicit click as `c3-afgoerelser-redigeret.txt`;
- compute SHA-256 from the exact downloaded bytes with `crypto.subtle.digest()` and display it;
- keep all state in memory so refresh restores defaults.

Do not make download depend on all fields being resolved: `UAFKLARET` is valid and visibly counted.

**Step 5: Add atomic no-clobber CLI publication**

The CLI must accept only:

```text
--selection PATH --state PATH --review PATH --output PATH
```

It must read exact bytes, calculate hashes internally, validate before writing, refuse an existing output, write a sibling temp file, `fsync`, and atomically publish without overwriting. On every failure, remove only its own temp file. Stdout may contain counts, basenames, and SHA-256 values, never names or narratives.

**Step 6: Run focused verification and confirm GREEN**

Run:

```bash
/usr/bin/python3 -m pytest -q .claude/skills/daa-extract/scripts/test_build_c3_html_review_1939_v50.py
```

Expected: all unit and generated-artifact tests pass, including real `node --check`.

**Step 7: Review and commit Task 2**

Mechanically search the created files for forbidden APIs and external URLs, then inspect any matches manually:

```bash
rg -n "innerHTML|fetch\(|XMLHttpRequest|WebSocket|localStorage|sessionStorage|indexedDB|document\.cookie|supabase|eval\(|new Function|on[a-z]+=" .claude/skills/daa-extract/scripts/build_c3_html_review_1939_v50.py .claude/skills/daa-extract/scripts/test_build_c3_html_review_1939_v50.py
```

Commit:

```bash
git add .claude/skills/daa-extract/scripts/build_c3_html_review_1939_v50.py .claude/skills/daa-extract/scripts/test_build_c3_html_review_1939_v50.py
git commit -m "feat(1939): render local C3 review interface"
```

---

### Task 3: Prove browser behavior in real Chromium

**Files:**

- Create: `.claude/skills/daa-extract/scripts/test_c3_html_review_browser_1939_v50.mjs`
- Modify: `.claude/skills/daa-extract/scripts/test_build_c3_html_review_1939_v50.py` only if an artifact-contract assertion belongs in Python rather than browser behavior

**Step 1: Write the failing Playwright harness**

The Node script must create a temporary directory, invoke the synthetic fixture CLI with `/usr/bin/python3`, invoke the production HTML generator, and open only that synthetic `file://` HTML in Playwright Chromium.

Use Node's strict assertions and fail nonzero. Record every request and reject anything whose protocol is not `file:` or `data:`. Never start a web server.

**Step 2: Assert the complete interaction contract**

Cover in one deterministic browser run:

- seven cards, `1 af 7`, direct navigation, previous/next, and status counts;
- all default tokens including the three special defaults;
- identity and record dependent selectors appear only for the chosen mode;
- same-person self-link is disabled and also fails export if state is tampered with;
- an allowed alias/canonical direction changes the exact shown token;
- record assignment, no-publication, and each revision kind map to exact tokens;
- synthetic `</script>`/HTML payload remains visible text and does not execute;
- unchanged download is byte-identical to `review.txt`;
- an edited download differs only within the validated token regions, including a length-changing token;
- displayed SHA-256 equals Node's hash of the downloaded bytes;
- reload restores defaults;
- no network request, browser storage, cookie, or unexpected file is created.

Use Playwright's download event and `download.createReadStream()` or `download.saveAs()` into the temporary directory. Never print page content, names, narratives, or downloaded text.

**Step 3: Run and confirm RED before completing selectors/behavior**

Run:

```bash
node .claude/skills/daa-extract/scripts/test_c3_html_review_browser_1939_v50.mjs
```

Expected initially: FAIL at the first missing or incorrect browser behavior.

**Step 4: Make the minimum production changes required for GREEN**

Keep all fixes in the Python generator's static HTML/JavaScript. Do not weaken the browser assertions, add external dependencies, or introduce browser-only grammar separate from the payload's closed choices.

**Step 5: Run real Chromium and confirm GREEN**

Run the Node command again. If Chromium cannot launch because the sandbox blocks the installed Playwright cache, rerun this exact narrow command with sandbox escalation. Expected: a short safe summary such as case/control/assertion counts, with no fixture prose.

**Step 6: Re-run Python artifact tests**

Run:

```bash
/usr/bin/python3 -m pytest -q .claude/skills/daa-extract/scripts/test_build_c3_html_review_1939_v50.py
```

Expected: GREEN after all browser-driven changes.

**Step 7: Review and commit Task 3**

Inspect the test for accidental production paths, screenshots, tracing, console dumps, or persistent browser profiles. Commit:

```bash
git add .claude/skills/daa-extract/scripts/test_c3_html_review_browser_1939_v50.mjs .claude/skills/daa-extract/scripts/build_c3_html_review_1939_v50.py .claude/skills/daa-extract/scripts/test_build_c3_html_review_1939_v50.py
git commit -m "test(1939): verify C3 review UI in Chromium"
```

---

### Task 4: Regression verification, local generation, and human-review stop

**Files:**

- Verify all files from Tasks 1–3
- Generate only: `work/task27-1939-v50-c3-review/c3-review.html`

**Step 1: Run focused C3 tests**

Run:

```bash
/usr/bin/python3 -m pytest -q \
  .claude/skills/daa-extract/scripts/test_build_c3_selection_1939_v50.py \
  .claude/skills/daa-extract/scripts/test_export_c3_state_1939_v50.py \
  .claude/skills/daa-extract/scripts/test_build_c3_review_1939_v50.py \
  .claude/skills/daa-extract/scripts/test_convert_c3_decisions_1939_v50.py \
  .claude/skills/daa-extract/scripts/test_build_c3_html_review_1939_v50.py
node .claude/skills/daa-extract/scripts/test_c3_html_review_browser_1939_v50.mjs
```

Expected: all focused Python tests and Chromium assertions pass.

**Step 2: Run the complete regression suites**

Run Python with the bound interpreter:

```bash
/usr/bin/python3 -m pytest -q .claude/skills/daa-extract/scripts
```

Run the repository's established R suite exactly as documented by its existing runner. Report Python and R results separately, including known skips/warnings rather than folding them into one verdict.

**Step 3: Audit the exact committed surface**

Require that the generator and browser test contain no network/database/write path beyond atomic HTML publication, temp test files, and explicit browser download. Confirm `work/` remains ignored and absent from `git diff --cached` and commit history.

Run:

```bash
git status --short
git diff --check
git log --oneline -4
```

Commit any final verified test-only correction as its own narrowly named commit. Do not amend earlier commits.

**Step 4: Generate the real local HTML without exposing its contents**

Only after all synthetic tests are green, run:

```bash
/usr/bin/python3 .claude/skills/daa-extract/scripts/build_c3_html_review_1939_v50.py \
  --selection work/task27-1939-v50-c3-review/selection-v1.json \
  --state work/task27-1939-v50-c3-review/current-state-v1.json \
  --review work/task27-1939-v50-c3-review/c3-afgoerelser.txt \
  --output work/task27-1939-v50-c3-review/c3-review.html
```

Do not open, screenshot, parse into model context, or run browser automation against this real HTML. Capture only the generator's safe counts and hashes. If the output already exists, stop rather than overwrite it.

**Step 5: Verify metadata without reading content**

Confirm only:

- the output exists and is a regular file;
- its byte size and SHA-256;
- it remains ignored/untracked;
- the Git worktree is clean after committed implementation.

Do not print any HTML or review lines.

**Step 6: Hand off and stop at the human gate**

Give the user the clickable local path to `c3-review.html`, the safe verification summary, and these instructions:

1. Open the local HTML themselves.
2. Review all seven cards and leave uncertain choices as `UAFKLARET`.
3. Download `c3-afgoerelser-redigeret.txt`.
4. Tell Codex the downloaded file's exact local path and explicitly approve the separate conversion step.

Do not convert the file, generate decision JSON, call an RPC, or write to the database in this plan.

---

## Completion criteria

- The committed implementation is Python 3.9 compatible and all focused/unit/browser tests are green.
- The generated synthetic JavaScript passes artifact-level `node --check`.
- Real Chromium proves navigation, safe rendering, exact-byte export, and displayed hash behavior.
- The real local HTML exists only under ignored `work/`, and its contents have not entered model or browser-tool context.
- No C3 decision JSON or database mutation has occurred.
- The workflow is stopped awaiting the user's seven-case review and explicit approval for conversion.
