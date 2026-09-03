# 1939 Exception Review Queue Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a private, fail-closed 1939 exception queue that hides only fully anchored, conflict-free records, exposes deterministic audit samples, and lets the editor resolve only genuine ambiguities through a reliable browser-local UI.

**Architecture:** A pure Python classifier consumes complete baseline coverage plus already anchored candidate evidence and produces one immutable queue manifest. A separate view-model builder combines that manifest with deduplicated parser suggestions; the HTML generator only renders the model and never performs matching. Browser decisions use an explicit schema and are converted to the existing coverage contract only after the selected candidate has passed the existing exact-anchor validators.

**Tech Stack:** Python 3 standard library and pytest; browser-local HTML/CSS/JavaScript; Vitest with jsdom from `web`; existing `coverage_1939.py`, `prepare_coverage_1939.py`, and 1939 segmentation scripts.

## Global Constraints

- Source identity is `record_key`; never use `(linje, nr)` as identity.
- `auto_resolved` requires one complete anchored candidate, positive provenance, global injectivity, non-overlapping spans, matching PDF pages, no conflicts, and pinned source/profile hashes.
- Name, number, page proximity, candidate ranking, or a confidence score can never promote a record.
- Any missing gate produces `human_required` or `source_blocked`; there is no probabilistic fallback.
- Human candidate selection is an observation, not `accepteret`; only the existing exact-anchor validation can promote it.
- Candidate display is deduplicated by stable `candidate_id`, never by text or page.
- The audit sample is deterministic: five percent of `auto_resolved`, with at least two records from every present rule/post-class stratum.
- Existing review JSON and private artifacts are never overwritten; every generated output uses exclusive creation.
- No task writes to the database, Supabase, Vercel, or production.
- Before every source mutation and commit, run `git branch --show-current` and confirm `feat/evidensbaseret-genimport`.
- Focused and full-suite verification results are reported separately.

---

### Task 1: Pure fail-closed queue classifier

**Files:**
- Create: `.claude/skills/daa-extract/scripts/review_queue_1939.py`
- Create: `.claude/skills/daa-extract/scripts/test_review_queue_1939.py`

**Interfaces:**
- Consumes: `baseline_keys: set[str]`, `evidence_entries: list[dict]`, and `source: dict` with `edition`, `baseline_sha256`, `calamari_sha256`, `raw_ocr_sha256`, `pdf_sha256`, and `profile_version`.
- Produces: `classify_review_entries(source: dict, baseline_keys: set[str], evidence_entries: list[dict]) -> dict` with `schema_version`, copied `source`, and one entry per `record_key` containing `queue_class`, `reason_code`, `reason_da`, `candidate`, `rule_id`, and `postklasse` where applicable.
- Reuses: candidate validation semantics from `coverage_1939.validate_coverage`; it does not duplicate weaker candidate rules.
- Positive provenance is a mapping `{kind, baseline_record_key, candidate_id}`. `kind` must be one of the explicitly supported provenance rules, and both identifiers must equal the entry being classified; a boolean flag is invalid.

The test module defines the complete factories used below:

```python
def source(**overrides):
    value = {
        "edition": "1939", "baseline_sha256": "a" * 64,
        "calamari_sha256": "b" * 64, "raw_ocr_sha256": "c" * 64,
        "pdf_sha256": "d" * 64, "profile_version": "1939-v2",
    }
    value.update(overrides)
    return value


def anchored_candidate(candidate_id="candidate-1", postklasse="nummereret"):
    return {
        "candidate_id": candidate_id, "postklasse": postklasse,
        "calamari_span": {"char_from": 10, "char_to": 20},
        "pdf_pages": [498],
        "raw_structure_bridge": {
            "kind": "record_start", "raw_char_from": 100, "raw_char_to": 110,
            "raw_excerpt_sha256": "e" * 64,
        },
    }


def evidence(key, candidate=None, *, source_blockers=None, **overrides):
    candidates = [] if candidate is None else [candidate]
    value = {
        "baseline_record_key": key, "candidates": candidates,
        "positive_provenance": ({
            "kind": "record_key_v2_locator", "baseline_record_key": key,
            "candidate_id": candidate["candidate_id"],
        } if candidate else None),
        "conflicts": [], "source_blockers": source_blockers or [],
        "rule_id": "complete_anchor_v1",
    }
    value.update(overrides)
    return value
```

- [ ] **Step 1: Write failing classification tests**

```python
def test_complete_unique_candidate_is_auto_resolved():
    result = classify_review_entries(
        source(), {"rk-1"}, [evidence("rk-1", candidate=anchored_candidate())]
    )
    assert result["entries"] == [{
        "baseline_record_key": "rk-1",
        "queue_class": "auto_resolved",
        "reason_code": "complete_unique_anchored_candidate",
        "reason_da": "Én komplet, entydig og konfliktfri kildebro.",
        "candidate": anchored_candidate(),
        "rule_id": "complete_anchor_v1",
        "postklasse": "nummereret",
    }]


@pytest.mark.parametrize("mutation,reason", [
    (lambda e: e.update(positive_provenance=None), "missing_positive_provenance"),
    (lambda e: e.update(conflicts=["locator_collision"]), "evidence_conflict"),
    (lambda e: e["candidates"].append(anchored_candidate("candidate-2")), "multiple_candidates"),
])
def test_missing_gate_requires_human(mutation, reason):
    entry = evidence("rk-1", candidate=anchored_candidate())
    mutation(entry)
    result = classify_review_entries(source(), {"rk-1"}, [entry])
    assert result["entries"][0]["queue_class"] == "human_required"
    assert result["entries"][0]["reason_code"] == reason


def test_missing_source_material_is_source_blocked():
    result = classify_review_entries(
        source(), {"rk-1"}, [evidence("rk-1", source_blockers=["raw_ocr_missing"])]
    )
    assert result["entries"][0]["queue_class"] == "source_blocked"
    assert result["entries"][0]["reason_code"] == "raw_ocr_missing"
```

- [ ] **Step 2: Run the focused tests and verify RED**

Run:

```bash
PYTHONPYCACHEPREFIX=/tmp/daa1939-pycache /usr/bin/python3 -m pytest -q \
  .claude/skills/daa-extract/scripts/test_review_queue_1939.py
```

Expected: collection fails because `review_queue_1939` does not exist.

- [ ] **Step 3: Implement the strict classifier**

```python
QUEUE_CLASSES = {"auto_resolved", "human_required", "source_blocked"}


def classify_review_entries(source, baseline_keys, evidence_entries):
    _validate_source_manifest(source)
    by_key = _complete_evidence_index(baseline_keys, evidence_entries)
    provisional = [_classify_one(key, by_key[key]) for key in sorted(baseline_keys)]
    _demote_candidate_collisions(provisional)
    _demote_span_overlaps(provisional)
    if {entry["baseline_record_key"] for entry in provisional} != baseline_keys:
        raise ValueError("queue baseline-dækning fejler")
    return {"schema_version": 1, "source": copy.deepcopy(source), "entries": provisional}


def _classify_one(key, evidence):
    if evidence.get("source_blockers"):
        return _blocked(key, evidence["source_blockers"][0])
    candidates = evidence.get("candidates") or []
    if len(candidates) != 1:
        return _human(key, "no_candidate" if not candidates else "multiple_candidates")
    provenance = evidence.get("positive_provenance")
    if not _valid_positive_provenance(provenance, key, candidates[0]["candidate_id"]):
        return _human(key, "missing_positive_provenance")
    if evidence.get("conflicts"):
        return _human(key, "evidence_conflict")
    _validate_one_candidate_with_existing_contract(key, candidates[0])
    return _automatic(key, candidates[0], evidence)
```

`_validate_one_candidate_with_existing_contract` must build a one-entry coverage bundle and call `validate_coverage`; it must not reimplement or relax the existing candidate validator. Collision and overlap demotion changes all involved entries to `human_required` with `candidate_collision` or `calamari_span_overlap`.

- [ ] **Step 4: Add exhaustive gate and accounting tests**

Add tests for malformed source hashes, duplicate/missing baseline keys, unknown post class, empty PDF pages, invalid raw bridge, duplicate candidate IDs, identical Calamari spans, partially overlapping spans, input non-mutation, and exact accounting. Use this parameterized core and separate two-entry collision/overlap cases:

```python
@pytest.mark.parametrize("candidate_mutation", [
    lambda c: c.update(postklasse="ukendt"),
    lambda c: c.update(pdf_pages=[]),
    lambda c: c["raw_structure_bridge"].update(raw_char_to=100),
])
def test_invalid_candidate_never_becomes_automatic(candidate_mutation):
    candidate = anchored_candidate()
    candidate_mutation(candidate)
    with pytest.raises(ValueError):
        classify_review_entries(source(), {"rk-1"}, [evidence("rk-1", candidate)])


def test_every_key_is_accounted_for_once():
    result = classify_review_entries(
        source(), {"rk-a", "rk-h", "rk-b"},
        [evidence("rk-a", anchored_candidate()), evidence("rk-h"),
         evidence("rk-b", source_blockers=["pdf_missing"])],
    )
    assert len(result["entries"]) == 3
    assert {entry["baseline_record_key"] for entry in result["entries"]} == {
        "rk-a", "rk-h", "rk-b",
    }
```

- [ ] **Step 5: Run focused tests and verify GREEN**

Run the Step 2 command.

Expected: all `test_review_queue_1939.py` tests pass.

- [ ] **Step 6: Commit Task 1**

```bash
git branch --show-current
git add .claude/skills/daa-extract/scripts/review_queue_1939.py \
  .claude/skills/daa-extract/scripts/test_review_queue_1939.py
git commit -m "feat: classify 1939 review exceptions"
```

---

### Task 2: Deterministic stratified audit sampling

**Files:**
- Modify: `.claude/skills/daa-extract/scripts/review_queue_1939.py`
- Modify: `.claude/skills/daa-extract/scripts/test_review_queue_1939.py`

**Interfaces:**
- Consumes: the complete manifest from Task 1.
- Produces: `sample_auto_resolved(manifest: dict, *, rate: float = 0.05, minimum_per_stratum: int = 2) -> list[str]` returning sorted `record_key` values.
- Stratum key: exact tuple `(rule_id, postklasse)` from `auto_resolved` entries.

Add these factories to the existing Task 1 test module:

```python
def automatic(key, rule_id="complete_anchor_v1", postklasse="nummereret"):
    return {
        "baseline_record_key": key, "queue_class": "auto_resolved",
        "reason_code": "complete_unique_anchored_candidate", "reason_da": "komplet",
        "candidate": anchored_candidate(key), "rule_id": rule_id,
        "postklasse": postklasse,
    }


def human(key):
    return {"baseline_record_key": key, "queue_class": "human_required",
            "reason_code": "no_candidate", "reason_da": "ingen kandidat"}


def queue_manifest(*entries, source_hash="a" * 64):
    return {"schema_version": 1,
            "source": source(baseline_sha256=source_hash), "entries": list(entries)}
```

- [ ] **Step 1: Write failing deterministic sampling tests**

```python
def test_sample_is_deterministic_stratified_and_automatic_only():
    manifest = queue_manifest(
        *[automatic(f"n-{i}", "complete_anchor_v1", "nummereret") for i in range(40)],
        *[automatic(f"o-{i}", "complete_anchor_v1", "oversigtspost") for i in range(10)],
        human("human-1"),
    )
    first = sample_auto_resolved(manifest)
    second = sample_auto_resolved(copy.deepcopy(manifest))
    assert first == second
    assert len([key for key in first if key.startswith("n-")]) == 2
    assert len([key for key in first if key.startswith("o-")]) == 2
    assert "human-1" not in first


def test_changed_source_hash_changes_seed_not_membership_rules():
    entries = [automatic(f"rk-{i}") for i in range(100)]
    first = sample_auto_resolved(queue_manifest(*entries, source_hash="a" * 64))
    second = sample_auto_resolved(queue_manifest(*entries, source_hash="b" * 64))
    assert first != second
    assert len(first) == len(second)
```

- [ ] **Step 2: Run tests and verify RED**

Run Task 1's focused pytest command.

Expected: failure because `sample_auto_resolved` is missing.

- [ ] **Step 3: Implement stable hash ordering per stratum**

```python
def sample_auto_resolved(manifest, *, rate=0.05, minimum_per_stratum=2):
    _validate_rate(rate, minimum_per_stratum)
    seed = _source_seed(manifest["source"])
    strata = defaultdict(list)
    for entry in manifest["entries"]:
        if entry["queue_class"] == "auto_resolved":
            strata[(entry["rule_id"], entry["postklasse"])].append(entry)
    selected = []
    for stratum, entries in sorted(strata.items()):
        count = min(len(entries), max(minimum_per_stratum, math.ceil(len(entries) * rate)))
        ordered = sorted(entries, key=lambda entry: hashlib.sha256(
            f"{seed}|{stratum}|{entry['baseline_record_key']}".encode("utf-8")
        ).hexdigest())
        selected.extend(entry["baseline_record_key"] for entry in ordered[:count])
    return sorted(selected)
```

- [ ] **Step 4: Add boundary tests**

Test empty `auto_resolved`, strata with one member, rates `0`, `1`, and outside `[0,1]`, non-positive `minimum_per_stratum`, reordered manifest input, and no mutation.

- [ ] **Step 5: Run focused tests and verify GREEN**

Run Task 1's focused pytest command.

Expected: all tests pass.

- [ ] **Step 6: Commit Task 2**

```bash
git branch --show-current
git add .claude/skills/daa-extract/scripts/review_queue_1939.py \
  .claude/skills/daa-extract/scripts/test_review_queue_1939.py
git commit -m "feat: sample automatic 1939 reviews"
```

---

### Task 3: Build the private queue manifest and deduplicated view model

**Files:**
- Create: `.claude/skills/daa-extract/scripts/prepare_review_queue_1939.py`
- Create: `.claude/skills/daa-extract/scripts/test_prepare_review_queue_1939.py`
- Modify: `.claude/skills/daa-extract/scripts/make_human_review_1939.py`
- Modify: `.claude/skills/daa-extract/scripts/test_make_human_review_1939.py`

**Interfaces:**
- Consumes: baseline JSON, anchored-evidence JSON, existing review decisions, pinned Calamari text/profile, and Task 1 classification.
- Produces: `build_review_view_model(baseline: list[dict], manifest: dict, nearby_candidates: dict[str, list[dict]], audit_keys: list[str], decisions: dict[str, dict]) -> dict`.
- Candidate presentation fields: `candidate_id`, `lokal_id`, `pdf_pages`, `calamari_pages`, `raw_text`, `rank_reason`; anchored candidates retain their complete private evidence object under `details`.
- Queue views: `required`, `automatic`, `audit`, and `completed`. `required` contains both `human_required` and `source_blocked`, with `source_blocked` reported as a visible subcount; existing human decisions additionally make a record visible in `completed`.

The new test module defines local, complete model factories:

```python
def source():
    return {"edition": "1939", "baseline_sha256": "a" * 64,
            "calamari_sha256": "b" * 64, "raw_ocr_sha256": "c" * 64,
            "pdf_sha256": "d" * 64, "profile_version": "1939-v2"}


def baseline(key, pages="498"):
    return {"record_key": key, "navn": key, "sider": pages,
            "narrative": f"gammel tekst {key}"}


def nearby(candidate_id, pages):
    return {"candidate_id": candidate_id, "lokal_id": candidate_id,
            "pdf_pages": pages, "calamari_pages": [page - 495 for page in pages],
            "raw_text": f"ny tekst {candidate_id}", "rank_reason": "samme_pdf_side"}


def human(key, reason="multiple_candidates"):
    return {"baseline_record_key": key, "queue_class": "human_required",
            "reason_code": reason, "reason_da": "kræver vurdering"}


def anchored_candidate(candidate_id):
    return {"candidate_id": candidate_id, "postklasse": "nummereret",
            "calamari_span": {"char_from": 10, "char_to": 20},
            "pdf_pages": [498], "raw_structure_bridge": {
                "kind": "record_start", "raw_char_from": 100, "raw_char_to": 110,
                "raw_excerpt_sha256": "e" * 64,
            }}


def automatic(key):
    return {"baseline_record_key": key, "queue_class": "auto_resolved",
            "reason_code": "complete_unique_anchored_candidate", "reason_da": "komplet",
            "candidate": anchored_candidate(key), "rule_id": "complete_anchor_v1",
            "postklasse": "nummereret"}


def manifest(*entries):
    return {"schema_version": 1, "source": source(), "entries": list(entries)}
```

- [ ] **Step 1: Write failing view-model tests**

```python
def test_multpage_candidate_is_deduplicated_by_candidate_id():
    model = build_review_view_model(
        [baseline("rk-1", pages="498-499")],
        manifest(human("rk-1", "multiple_candidates")),
        {"rk-1": [nearby("c-1", [498, 499]), nearby("c-1", [498, 499])]},
        [], {},
    )
    assert [c["candidate_id"] for c in model["records"][0]["candidates"]] == ["c-1"]


def test_required_is_default_and_automatic_remains_inspectable():
    model = build_review_view_model(
        [baseline("rk-a"), baseline("rk-h")],
        manifest(automatic("rk-a"), human("rk-h")),
        {"rk-a": [], "rk-h": []}, [], {},
    )
    assert model["summary"] == {
        "required": 1, "automatic": 1, "audit": 0, "completed": 0, "source_blocked": 0,
    }
    assert model["default_view"] == "required"
```

- [ ] **Step 2: Run focused tests and verify RED**

```bash
PYTHONPYCACHEPREFIX=/tmp/daa1939-pycache /usr/bin/python3 -m pytest -q \
  .claude/skills/daa-extract/scripts/test_prepare_review_queue_1939.py \
  .claude/skills/daa-extract/scripts/test_make_human_review_1939.py
```

Expected: failure because `prepare_review_queue_1939` is missing.

- [ ] **Step 3: Implement stable deduplication and queue assembly**

```python
def _deduplicate_candidates(candidates):
    by_id = {}
    for candidate in candidates:
        candidate_id = _nonempty(candidate.get("candidate_id"), "candidate_id")
        previous = by_id.get(candidate_id)
        if previous is not None and previous != candidate:
            raise ValueError("samme candidate_id har forskelligt indhold")
        by_id[candidate_id] = copy.deepcopy(candidate)
    return [by_id[key] for key in sorted(by_id)]


def build_review_view_model(baseline, manifest, nearby_candidates, audit_keys, decisions):
    _assert_baseline_and_manifest_cover_same_record_keys(baseline, manifest)
    records = []
    for record in baseline:
        key = record["record_key"]
        classification = manifest_entry_by_key[key]
        records.append(_view_record(
            record, classification,
            _deduplicate_candidates(nearby_candidates.get(key, [])),
            key in set(audit_keys), decisions.get(key),
        ))
    return _complete_view_model(records, manifest["source"])
```

Ranking may order candidates with deterministic, explicitly labelled reading aids, but it may not alter classification or discard candidates. The first three are initially expanded; `candidate_count` and all candidates remain in the model.

- [ ] **Step 4: Add generator CLI contract**

Extend `make_human_review_1939.py` with required `--queue-manifest` and `--source-manifest` inputs. Retain exclusive `--out`. Remove page-only classification logic from the HTML generator; page-near candidates are display aids only.

The CLI must fail if baseline, queue, review, or source hashes disagree, if any baseline key is missing, or if an output already exists.

- [ ] **Step 5: Add accounting and failure tests**

Test all 546 keys accounted for; duplicate baseline key; missing manifest key; conflicting duplicate candidate; top-three initial expansion without loss of remaining candidates; automatic records accessible but not in default queue; audit records are automatic; source-blocked records show their reason; existing decision appears in completed. Include this losslessness assertion:

```python
def test_top_three_is_presentation_only_and_all_candidates_survive():
    candidates = [nearby(f"c-{i}", [498]) for i in range(5)]
    model = build_review_view_model(
        [baseline("rk-1")], manifest(human("rk-1")),
        {"rk-1": candidates}, [], {},
    )
    record = model["records"][0]
    assert record["initial_candidate_ids"] == ["c-0", "c-1", "c-2"]
    assert [candidate["candidate_id"] for candidate in record["candidates"]] == [
        "c-0", "c-1", "c-2", "c-3", "c-4",
    ]
```

- [ ] **Step 6: Run focused tests and verify GREEN**

Run the Step 2 command.

Expected: all focused tests pass.

- [ ] **Step 7: Commit Task 3**

```bash
git branch --show-current
git add .claude/skills/daa-extract/scripts/prepare_review_queue_1939.py \
  .claude/skills/daa-extract/scripts/test_prepare_review_queue_1939.py \
  .claude/skills/daa-extract/scripts/make_human_review_1939.py \
  .claude/skills/daa-extract/scripts/test_make_human_review_1939.py
git commit -m "feat: build 1939 exception review model"
```

---

### Task 4: Reliable browser controller and real DOM tests

**Files:**
- Create: `.claude/skills/daa-extract/scripts/human_review_1939_ui.js`
- Modify: `.claude/skills/daa-extract/scripts/make_human_review_1939.py`
- Create: `web/src/humanReview1939Ui.test.ts`
- Modify: `.claude/skills/daa-extract/scripts/test_make_human_review_1939.py`

**Interfaces:**
- Produces: `window.DAA1939Review.init({data, storage, now, download}) -> controller`.
- Controller surface used by tests: read-only `selectedKey` plus `selectRecord(recordKey)`, `choose(outcome, payload)`, `undo()`, `next()`, `previous()`, `setView(view)`, and `exportDraft()`.
- Browser decisions use outcomes `human_selected_candidate`, `no_candidate_fits`, `possible_duplicate`, and `undecidable`.

The DOM test loads the committed controller, not a rewritten test copy:

```typescript
// @vitest-environment jsdom
import { readFileSync } from "node:fs";

const uiSource = readFileSync(new URL(
  "../../.claude/skills/daa-extract/scripts/human_review_1939_ui.js",
  import.meta.url,
), "utf8");

function memoryStorage() {
  const values = new Map<string, string>();
  return {
    getItem: (key: string) => values.get(key) ?? null,
    setItem: (key: string, value: string) => values.set(key, value),
    removeItem: (key: string) => values.delete(key),
  };
}

function startReview({storage, records}) {
  document.body.innerHTML = '<aside data-role="save-state"></aside><main data-role="app"></main>';
  window.eval(uiSource);
  return (window as any).DAA1939Review.init({data: viewModel(records), storage,
    now: () => "2026-08-05T12:00:00+02:00", download: vi.fn()});
}
```

- [ ] **Step 1: Write the V5 regression test in jsdom**

```typescript
it("records the candidate id, persists it, and confirms success", () => {
  const storage = memoryStorage();
  const controller = startReview({ storage, records: [humanRecord("rk-1", "candidate-1")] });

  document.querySelector<HTMLButtonElement>('[data-action="select-candidate"]')!.click();

  expect(controller.exportDraft().entries[0]).toMatchObject({
    baseline_record_key: "rk-1",
    outcome: "human_selected_candidate",
    candidate_id: "candidate-1",
  });
  expect(JSON.parse(storage.getItem(controller.storageKey)!)).toBeTruthy();
  expect(document.querySelector('[data-role="save-state"]')).toHaveTextContent(
    "Visuelt spor er gemt lokalt"
  );
});
```

- [ ] **Step 2: Run the DOM test and verify RED**

```bash
npm --prefix web test -- src/humanReview1939Ui.test.ts
```

Expected: failure because `human_review_1939_ui.js` and its event delegation do not exist.

- [ ] **Step 3: Extract the UI controller and eliminate inline handlers**

```javascript
(function (global) {
  function init({ data, storage = global.localStorage, now = () => new Date().toISOString(), download }) {
    const state = restoreOrInitialize(data, storage);
    document.addEventListener("click", event => {
      const button = event.target.closest("[data-action]");
      if (!button) return;
      dispatch(button.dataset.action, button.dataset, state);
    });
    render(state);
    return createController(state, { storage, now, download });
  }
  global.DAA1939Review = { init };
})(window);
```

Candidate buttons use `data-action="select-candidate"` and an escaped `data-candidate-id`. No generated content may contain an inline `onclick` attribute.

- [ ] **Step 4: Implement the approved queue workflow**

Implement dashboard counts; default required queue; automatic/audit/completed views; one record at a time; plain-Danish reason; old text beside three initially expanded candidates; `Vis alle kandidater`; details disclosure; four decision actions; duplicate target search; previous/next/undo; automatic next only after persisted success.

```javascript
function choose(outcome, payload = {}) {
  const previous = structuredClone(state.decisions[state.selectedKey] || null);
  const decision = validateUiChoice(state, outcome, payload);
  state.decisions[state.selectedKey] = decision;
  try {
    persist(state);
  } catch (error) {
    restoreDecision(state, state.selectedKey, previous);
    showStorageError(error);
    return false;
  }
  state.undoStack.push({recordKey: state.selectedKey, previous});
  showSaved("✓ Valget er gemt lokalt.");
  moveToNextRequired(state);
  render(state);
  return true;
}
```

- [ ] **Step 5: Add DOM coverage for storage and navigation**

Add jsdom tests for: all four actions; candidate IDs containing quotes and Danish characters; restore after reload; `storage.setItem` exception shows persistent error and does not advance; previous/next boundaries; undo restores persisted prior decision; view filters; automatic record inspection; audit label; candidate expansion; duplicate target selection; and export callback payload.

```typescript
it("does not confirm or advance when persistence fails", () => {
  const storage = memoryStorage();
  storage.setItem = () => { throw new Error("quota"); };
  const controller = startReview({storage, records: [humanRecord("rk-1", "c-1"), humanRecord("rk-2", "c-2")]});
  expect(controller.choose("human_selected_candidate", {candidate_id: "c-1"})).toBe(false);
  expect(controller.selectedKey).toBe("rk-1");
  expect(document.querySelector('[data-role="save-state"]')).toHaveTextContent("Kunne ikke gemme");
});


it("supports candidate ids containing quotes", () => {
  const controller = startReview({storage: memoryStorage(),
    records: [humanRecord("rk-1", 'Volrad "ældre"')]});
  document.querySelector<HTMLButtonElement>('[data-action="select-candidate"]')!.click();
  expect(controller.exportDraft().entries[0].candidate_id).toBe('Volrad "ældre"');
});
```

- [ ] **Step 6: Make Python embed the tested JavaScript unchanged**

`make_human_review_1939.py` reads `human_review_1939_ui.js` relative to `__file__` and embeds it into the self-contained output. Add a Python test asserting the embedded bytes equal the committed JS source and that no `onclick=` exists.

- [ ] **Step 7: Run focused Python and DOM tests**

```bash
PYTHONPYCACHEPREFIX=/tmp/daa1939-pycache /usr/bin/python3 -m pytest -q \
  .claude/skills/daa-extract/scripts/test_make_human_review_1939.py \
  .claude/skills/daa-extract/scripts/test_prepare_review_queue_1939.py
npm --prefix web test -- src/humanReview1939Ui.test.ts
```

Expected: both commands pass.

- [ ] **Step 8: Commit Task 4**

```bash
git branch --show-current
git add .claude/skills/daa-extract/scripts/human_review_1939_ui.js \
  .claude/skills/daa-extract/scripts/make_human_review_1939.py \
  .claude/skills/daa-extract/scripts/test_make_human_review_1939.py \
  web/src/humanReview1939Ui.test.ts
git commit -m "feat: add reliable 1939 review workflow"
```

---

### Task 5: Versioned choice export and fail-closed after-control

**Files:**
- Create: `.claude/skills/daa-extract/scripts/review_choices_1939.py`
- Create: `.claude/skills/daa-extract/scripts/test_review_choices_1939.py`
- Modify: `.claude/skills/daa-extract/scripts/prepare_coverage_1939.py`
- Modify: `.claude/skills/daa-extract/scripts/test_prepare_coverage_1939.py`

**Interfaces:**
- Produces: `validate_choice_export(value: dict, expected_source: dict, expected_keys: set[str]) -> dict[str, dict]`.
- Produces: `convert_review_choices(choices: dict[str, dict], anchored_candidates: dict[str, dict], classifications: dict[str, dict], audit_keys: set[str]) -> dict` with separate `decisions` and `audit_results` lists.
- Each `anchored_candidates[candidate_id]` is `{baseline_record_key, candidate}`. Accepted conversion occurs only when both the selected `candidate_id` and its recorded baseline owner match the choice, and the candidate passes existing coverage validation.
- A choice for `auto_resolved` is legal only when the key belongs to `audit_keys`. Selecting the existing automatic candidate records `audit_confirmed`; a different candidate, `no_candidate_fits`, `possible_duplicate`, or `undecidable` records `audit_failed` with `rule_id` and reason and does not replace the automatic coverage entry.

The choice tests define their local decision factories explicitly:

```python
def choice(key, outcome, **fields):
    return {"baseline_record_key": key, "outcome": outcome, **fields}


def expected_source():
    return {"edition": "1939", "baseline_sha256": "a" * 64,
            "calamari_sha256": "b" * 64, "raw_ocr_sha256": "c" * 64,
            "pdf_sha256": "d" * 64, "profile_version": "1939-v2"}


def choice_export(*entries):
    return {"schema_version": 1, "source": expected_source(),
            "exported_at": "2026-08-05T12:00:00+02:00", "entries": list(entries)}


def human(key):
    return {"baseline_record_key": key, "queue_class": "human_required",
            "reason_code": "multiple_candidates", "reason_da": "flere kandidater"}


def automatic(key, candidate_id):
    return {"baseline_record_key": key, "queue_class": "auto_resolved",
            "reason_code": "complete_unique_anchored_candidate", "reason_da": "komplet",
            "candidate": anchored_candidate(candidate_id),
            "rule_id": "complete_anchor_v1", "postklasse": "nummereret"}


def anchored_candidate(candidate_id):
    return {"candidate_id": candidate_id, "postklasse": "nummereret",
            "calamari_span": {"char_from": 10, "char_to": 20},
            "pdf_pages": [498], "raw_structure_bridge": {
                "kind": "record_start", "raw_char_from": 100, "raw_char_to": 110,
                "raw_excerpt_sha256": "e" * 64,
            }}
```

- [ ] **Step 1: Write failing schema and conversion tests**

```python
def test_selected_candidate_promotes_only_when_exact_candidate_exists():
    converted = convert_review_choices(
        {"rk-1": choice("rk-1", "human_selected_candidate", candidate_id="c-1")},
        {"c-1": {"baseline_record_key": "rk-1", "candidate": anchored_candidate("c-1")}},
        {"rk-1": human("rk-1")}, set(),
    )
    assert converted["decisions"] == [{
        "baseline_record_key": "rk-1", "status": "accepteret", "candidate_id": "c-1",
    }]
    assert converted["audit_results"] == []


def test_selected_candidate_without_exact_anchor_remains_parked():
    converted = convert_review_choices(
        {"rk-1": choice("rk-1", "human_selected_candidate", candidate_id="c-1")},
        {}, {"rk-1": human("rk-1")}, set(),
    )
    assert converted["decisions"] == [{
        "baseline_record_key": "rk-1",
        "status": "menneskeark",
        "reason": "human_selected_candidate_requires_exact_anchor:c-1",
    }]


def test_audit_disagreement_blocks_rule_without_replacing_automatic_decision():
    converted = convert_review_choices(
        {"rk-a": choice("rk-a", "no_candidate_fits", reason="teksten tilhører naboen")},
        {}, {"rk-a": automatic("rk-a", candidate_id="c-a")}, {"rk-a"},
    )
    assert converted["decisions"] == []
    assert converted["audit_results"] == [{
        "baseline_record_key": "rk-a", "audit_status": "audit_failed",
        "rule_id": "complete_anchor_v1", "reason": "teksten tilhører naboen",
    }]
```

- [ ] **Step 2: Run focused tests and verify RED**

```bash
PYTHONPYCACHEPREFIX=/tmp/daa1939-pycache /usr/bin/python3 -m pytest -q \
  .claude/skills/daa-extract/scripts/test_review_choices_1939.py \
  .claude/skills/daa-extract/scripts/test_prepare_coverage_1939.py
```

Expected: collection fails because `review_choices_1939` is missing.

- [ ] **Step 3: Implement exact export validation**

Require schema version, every source/profile hash, export timestamp, unique known baseline keys, known outcomes, and outcome-specific fields. `human_selected_candidate` requires a known `candidate_id`; `possible_duplicate` requires a distinct baseline target; `no_candidate_fits` and `undecidable` require a non-empty reason and forbid candidate/target fields.

```python
def validate_choice_export(value, expected_source, expected_keys):
    root = _mapping(value, "choice export")
    if root.get("schema_version") != 1 or root.get("source") != expected_source:
        raise ValueError("choice export source/version matcher ikke")
    entries = _unique_entries(root.get("entries"), expected_keys)
    return {entry["baseline_record_key"]: _validate_choice(entry) for entry in entries}
```

- [ ] **Step 4: Implement conservative conversion**

For required records, convert `no_candidate_fits` and `undecidable` to `menneskeark` with stable reason codes. Convert `possible_duplicate` only when `duplicate_of_baseline_record_key` is present; let existing duplicate-target integrity checks decide whether the target is accepted. Convert a selected candidate to accepted only through the anchored candidate map and existing coverage validation; otherwise park it. For audit keys, emit only `audit_confirmed` or `audit_failed`; never rewrite the automatic coverage entry through the audit path.

- [ ] **Step 5: Wire a new explicit CLI mode**

Add `--choices-to-decisions CHOICES.json --queue-manifest QUEUE.json --anchored-candidates CANDIDATES.json --out NEW.json` to `prepare_coverage_1939.py`. It must use exclusive creation, validate every source hash, and leave legacy CLI modes unchanged.

- [ ] **Step 6: Add fail-closed tests**

Test stale baseline hash, stale profile version, duplicate/unknown baseline key, unknown candidate, a choice for an automatic non-audit record, audit agreement, audit disagreement, invalid duplicate target, self-target, missing reason, unknown field, malformed timestamp, output already exists, and no mutation of input objects.

```python
@pytest.mark.parametrize("mutation,message", [
    (lambda root: root["source"].update(baseline_sha256="f" * 64), "source/version"),
    (lambda root: root["entries"].append(copy.deepcopy(root["entries"][0])), "dublet"),
    (lambda root: root["entries"][0].update(outcome="ukendt"), "outcome"),
])
def test_choice_export_rejects_stale_duplicate_or_unknown(mutation, message):
    value = choice_export(choice("rk-1", "undecidable", reason="uklar kilde"))
    mutation(value)
    with pytest.raises(ValueError, match=message):
        validate_choice_export(value, expected_source(), {"rk-1"})
```

- [ ] **Step 7: Run focused tests and verify GREEN**

Run the Step 2 command.

Expected: all tests pass.

- [ ] **Step 8: Commit Task 5**

```bash
git branch --show-current
git add .claude/skills/daa-extract/scripts/review_choices_1939.py \
  .claude/skills/daa-extract/scripts/test_review_choices_1939.py \
  .claude/skills/daa-extract/scripts/prepare_coverage_1939.py \
  .claude/skills/daa-extract/scripts/test_prepare_coverage_1939.py
git commit -m "feat: validate 1939 review choices"
```

---

### Task 6: Private pilot generation, accounting, and publication gate

**Files:**
- Modify: `.claude/skills/daa-extract/scripts/prepare_review_queue_1939.py`
- Modify: `.claude/skills/daa-extract/scripts/test_prepare_review_queue_1939.py`
- Modify: `.claude/skills/daa-extract/SKILL.md`
- Create private, ignored outputs only: `work/task19-1939-pilot/review-queue-manifest-v1.json`, `work/task19-1939-pilot/menneskeark-undtagelsesko-v1.html`, and `work/task19-1939-pilot/review-queue-report-v1.json`

**Interfaces:**
- CLI: `prepare_review_queue_1939.py --baseline ... --evidence ... --review ... --calamari ... --raw ... --pdf ... --profile-version 1939-v2 --queue-out ... --report-out ...`.
- Report fields: source hashes/profile, `baseline_total`, `auto_resolved`, `human_required`, `source_blocked`, `audit`, `completed`, reason-code counts, stratum counts, collision/overlap counts, and `publication_gate`.
- `publication_gate` is `GO` only when all 546 keys are classified, all automatic candidates pass the existing exact validator, every sampled key has an `audit_confirmed` result, and no rule group is audit-blocked. Missing, failed, or undecidable audit results are blocking.

The report test uses explicit queue entries:

```python
def expected_source():
    return {"edition": "1939", "baseline_sha256": "a" * 64,
            "calamari_sha256": "b" * 64, "raw_ocr_sha256": "c" * 64,
            "pdf_sha256": "d" * 64, "profile_version": "1939-v2"}


def queue_entry(key, queue_class, reason_code):
    return {"baseline_record_key": key, "queue_class": queue_class,
            "reason_code": reason_code, "reason_da": reason_code}


def report_manifest(*entries):
    return {"schema_version": 1, "source": expected_source(), "entries": list(entries)}
```

- [ ] **Step 1: Write failing report and gate tests**

```python
def test_report_accounts_for_every_record_and_fails_closed():
    report = build_queue_report(
        report_manifest(
            queue_entry("rk-a", "auto_resolved", "complete_unique_anchored_candidate"),
            queue_entry("rk-h", "human_required", "multiple_candidates"),
            queue_entry("rk-b", "source_blocked", "raw_ocr_missing"),
        ),
        audit_keys=["rk-a"], completed_keys={"rk-h"}, audit_results=[],
    )
    assert report["baseline_total"] == 3
    assert report["auto_resolved"] == 1
    assert report["human_required"] == 1
    assert report["source_blocked"] == 1
    assert report["publication_gate"] == "NO-GO"
```

- [ ] **Step 2: Run focused tests and verify RED**

Run Task 3's focused pytest command.

Expected: failure because report generation is missing.

- [ ] **Step 3: Implement the exclusive CLI and report**

Use `Path.open("x")` for both outputs. Hash files from bytes, pin `profile_version`, classify, sample, merge decisions and audit results, write the queue manifest, and calculate the report from the written manifest. Never infer a positive link inside this command; `--evidence` must already contain the complete candidate and positive-provenance mapping.

- [ ] **Step 4: Document the private workflow**

In `.claude/skills/daa-extract/SKILL.md`, document exact generation, opening, export, choice validation, and regeneration commands. State that HTML/localStorage are drafts, exported JSON is the durable handoff, and no generated `work/` artifact is committed.

- [ ] **Step 5: Run all focused tests**

```bash
PYTHONPYCACHEPREFIX=/tmp/daa1939-pycache /usr/bin/python3 -m pytest -q \
  .claude/skills/daa-extract/scripts/test_review_queue_1939.py \
  .claude/skills/daa-extract/scripts/test_prepare_review_queue_1939.py \
  .claude/skills/daa-extract/scripts/test_make_human_review_1939.py \
  .claude/skills/daa-extract/scripts/test_review_choices_1939.py \
  .claude/skills/daa-extract/scripts/test_prepare_coverage_1939.py
npm --prefix web test -- src/humanReview1939Ui.test.ts
```

Expected: both commands pass.

- [ ] **Step 6: Generate the real private pilot without overwriting V5**

Run the documented command using:

- baseline `../../../work_1939_stamtavle/clean_1939_v2.json`;
- Calamari `../../../work_1939_stamtavle/full_ocr_calamari_r6_clean.txt`;
- raw OCR `../../../work_1939_stamtavle/raw.txt`;
- PDF `../../../Dansk Adels Aarbog - Reventlow 1939.pdf`;
- existing private review `work/task19-1939-pilot/coverage-review.json`;
- new versioned output names listed above.

Record exact counts from the generated report. Do not claim that same-page suggestions are `auto_resolved`; without complete `--evidence`, they remain `human_required`.

- [ ] **Step 7: Manually verify the Volrad acceptance case**

Open the new HTML locally. Search for `Volrad [Reventlow]`. Verify that the Volrad parserpost appears exactly once, other candidates remain available, clicking it persists the exact candidate ID, the green confirmation appears, reload restores the choice, undo restores the prior state, and export contains the source hashes and choice.

- [ ] **Step 8: Run the full Python suite and the full web unit suite**

```bash
PYTHONPYCACHEPREFIX=/tmp/daa1939-pycache /usr/bin/python3 -m pytest -q \
  .claude/skills/daa-extract/scripts
npm --prefix web test
```

Expected: all tests pass or pre-existing unrelated failures are reported verbatim and separately; no baseline is described as green when a known failure remains.

- [ ] **Step 9: Confirm repository scope and commit source/docs only**

```bash
git branch --show-current
git status --short --ignored
git check-ignore work/task19-1939-pilot/review-queue-manifest-v1.json \
  work/task19-1939-pilot/menneskeark-undtagelsesko-v1.html \
  work/task19-1939-pilot/review-queue-report-v1.json
git add .claude/skills/daa-extract/scripts/prepare_review_queue_1939.py \
  .claude/skills/daa-extract/scripts/test_prepare_review_queue_1939.py \
  .claude/skills/daa-extract/SKILL.md
git commit -m "feat: prepare private 1939 exception review"
```

The commit must not contain `work/`, PDFs, OCR text, exported decisions, or person data.

---

### Task 7: Independent review and final handoff

**Files:**
- Review only all source and test files changed in Tasks 1–6.
- Do not modify private pilot artifacts during review.

**Interfaces:**
- Consumes: implementation commits and fresh focused/full verification output.
- Produces: severity-sorted findings and an explicit GO/NO-GO for using the HTML as a private review tool; this is not a database promotion GO.

- [ ] **Step 1: Run scoped adversarial review**

Trace classification input through queue class, candidate display, browser choice, export, choice validation, and coverage conversion. Attempt to falsify each automatic gate, injectivity, span non-overlap, hash pin, audit-block behavior, storage confirmation, and output exclusivity claim.

- [ ] **Step 2: Verify changed-file scope**

```bash
git diff --name-only a23f267..HEAD
git status --short --ignored
```

Expected: only planned source/tests/docs are tracked; all `work/` outputs and source materials are ignored.

- [ ] **Step 3: Re-run fresh verification after review fixes**

Run Task 6 Steps 5 and 8 again. Record focused Python, DOM, full Python, and full web results separately.

- [ ] **Step 4: Report the private-tool gate**

Report:

- exact classification and audit counts;
- remaining mandatory human count by reason;
- whether Volrad DOM persistence passed;
- focused/full test results;
- review findings and resolution commits;
- `GO` only for private review use when no unresolved P0/P1 finding remains.

Explicitly state that database reimport, Supabase deployment, Vercel deployment, and production promotion remain outside this plan.
