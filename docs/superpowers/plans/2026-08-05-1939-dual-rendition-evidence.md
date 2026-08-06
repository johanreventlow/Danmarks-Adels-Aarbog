# 1939 Dual-Rendition Evidence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Generate source-bound 1939 evidence from unique baseline ownership anchors plus structurally unique agreement between Calamari and raw OCR, so the private queue shows only genuine exceptions and deterministic audit samples.

**Architecture:** Two pure Python layers first turn each pinned OCR rendition into exact, record-key-free occurrences and then derive only alignment edges that satisfy hard structural predicates. A consensus layer binds an opaque baseline `record_key` through a unique exact narrative occurrence in its declared source rendition, requires the corresponding pair to be invariant across all maximum-cardinality monotone alignments, and materializes the existing strict queue-evidence grammar. Existing queue, browser and publication gates remain authoritative and fail closed.

**Tech Stack:** Python 3 standard library, pytest, existing `segment._evidence_ledger`, `coverage_1939`, `review_queue_1939`, `prepare_review_queue_1939`, browser-local HTML/JavaScript, Vitest/jsdom, pinned private OCR/PDF artifacts.

## Global Constraints

- Source identity is `record_key`; `(linje, nr)`, names, pages, candidate ranks and similarity scores are never identity.
- Calamari and raw OCR must independently support the same logical record interval before `auto_resolved` is possible.
- A baseline record needs a unique codepoint-exact narrative anchor in the rendition named by `_narrativ_kilde`; no fuzzy or normalized fallback is allowed.
- Structural locators and `_v2_lokal_id` may narrow candidates but never constitute positive evidence.
- Accepted pairings must be invariant across every maximum-cardinality monotone alignment; multiple equally valid alignments remain human work.
- Candidate IDs, occurrence IDs, Calamari spans and raw spans are globally injective and non-overlapping.
- The seven known overview duplicates never become automatic people.
- Existing V1/V5 and all other private artifacts are immutable. New outputs use exclusive creation and V2 names.
- Calamari pages use the pinned piecewise `calamari-r6-to-pdf-v1` mapping;
  raw-OCR markers use `raw-absolute-pdf-v1`. A constant-offset fallback is forbidden.
- Generated OCR, PDF, occurrence, evidence, queue, report and HTML artifacts remain ignored and are never committed.
- No task writes to the database, `load_daa.R`, Supabase, Vercel or production.
- Before every source/doc mutation and commit, run `git branch --show-current` and require `feat/evidensbaseret-genimport`.
- Use `/usr/bin/python3 -m pytest`; report focused and full-suite results separately.
- Each task requires a fresh independent review before the next task starts.
- Treat artifacts emitted by the same pinned local pipeline as trusted internal
  inputs. Validate consumed fields and facts that prevent realistic wrong
  imports; do not duplicate an upstream schema validator for unused metadata or
  add defenses whose only purpose is resisting deliberately forged internal
  JSON.

---

### Task 1: Exact record-key-free rendition occurrences

**Files:**
- Create: `.claude/skills/daa-extract/scripts/rendition_occurrences_1939.py`
- Create: `.claude/skills/daa-extract/scripts/test_rendition_occurrences_1939.py`
- Read/reuse: `.claude/skills/daa-extract/scripts/segment.py`

**Interfaces:**
- Consumes: decoded OCR text, rendition name and an exact page-map definition.
- Produces: `extract_rendition_occurrences(source_text: str, *, rendition: str, page_map: tuple[tuple[int, int], ...] | None) -> dict`.
- `page_map=CALAMARI_R6_TO_PDF_V1` uses the pinned piecewise map. `page_map=None`
  is allowed only for `raw_ocr`, whose page markers already contain physical PDF pages.
- Root schema:

```python
{
    "schema_version": 1,
    "rendition": "calamari",          # or "raw_ocr"
    "source_sha256": "a" * 64,
    "source_length": 1234,
    "page_mapping_id": "calamari-r6-to-pdf-v1",
    "page_mapping_points": [[1, 496], [5, 500]],
    "occurrences": [{
        "occurrence_id": "occ:calamari:<digest>",
        "order": 0,
        "span": {"char_from": 20, "char_to": 80},
        "verbatim_sha256": "b" * 64,
        "pdf_pages": [496],
        "post_class": "nummereret",   # or None when source structure is insufficient
        "printed_marker": "1",
        "section_signature": ["I"],
        "predecessor_signature": None,
        "successor_signature": "<canonical JSON digest>",
    }],
}
```

- The extractor may use `segment._evidence_ledger(source_text)` to identify source-derived occurrence clauses, but must independently validate clause coverage, order and exact slices.
- It never accepts a baseline, emits a `record_key`, or mutates the ledger.

- [ ] **Step 1: Write failing exact-span and source-only tests**

```python
def test_extracts_exact_source_only_occurrences():
    text = "### PAGE 1 ###\nI. Første Slægtled\n1. Alfa\nfortsat\n2. Beta\n"
    result = extract_rendition_occurrences(
        text, rendition="calamari", page_map=((1, 496),)
    )
    assert result["source_sha256"] == hashlib.sha256(text.encode()).hexdigest()
    assert [o["printed_marker"] for o in result["occurrences"]] == ["1", "2"]
    assert all("record_key" not in o for o in result["occurrences"])
    for occurrence in result["occurrences"]:
        span = occurrence["span"]
        exact = text[span["char_from"]:span["char_to"]]
        assert hashlib.sha256(exact.encode()).hexdigest() == occurrence["verbatim_sha256"]


def test_occurrence_ends_before_next_record_marker():
    text = "### PAGE 1 ###\n1. Volrad\nprosa\n2. Emeke\n"
    result = extract_rendition_occurrences(
        text, rendition="raw_ocr", page_map=None
    )
    first, second = result["occurrences"]
    assert first["span"]["char_to"] <= second["span"]["char_from"]
    assert "Emeke" not in text[first["span"]["char_from"]:first["span"]["char_to"]]
```

- [ ] **Step 2: Run the focused file and verify RED**

Run:

```bash
PYTHONPYCACHEPREFIX=/tmp/daa1939-occ-pycache /usr/bin/python3 -m pytest -q \
  .claude/skills/daa-extract/scripts/test_rendition_occurrences_1939.py
```

Expected: collection fails because `rendition_occurrences_1939` does not exist.

- [ ] **Step 3: Implement strict ledger collapsing**

Implement these public and private boundaries:

```python
RENDITIONS = {"calamari", "raw_ocr"}
POST_CLASSES = {"nummereret", "stamfader", "oversigtspost"}


CALAMARI_R6_TO_PDF_V1 = (
    (1, 496), (5, 500), (10, 505), (15, 510), (20, 515),
    (25, 520), (30, 525), (40, 535), (45, 540), (50, 545),
    (53, 550), (58, 555), (63, 575), (68, 580), (73, 585),
    (78, 590), (83, 595), (85, 598), (86, 598),
)


def extract_rendition_occurrences(source_text, *, rendition, page_map):
    mapping = _validate_page_map(rendition, page_map)
    ledger = segment._evidence_ledger(source_text)
    _validate_complete_clause_partition(source_text, ledger["clauses"])
    occurrences = _collapse_occurrence_clauses(
        source_text, ledger["clauses"], page_mapping=mapping
    )
    _attach_neighbor_signatures(occurrences)
    _validate_occurrence_partition(occurrences, len(source_text))
    return {
        "schema_version": 1,
        "rendition": rendition,
        "source_sha256": _sha256_text(source_text),
        "source_length": len(source_text),
        "occurrences": occurrences,
    }
```

`_validate_complete_clause_partition` requires exact built-in JSON-compatible
types, ordered non-overlapping clause spans, and
`source_text[char_from:char_to] == verbatim_text`. Layout clauses may sit between
two clauses owned by the same occurrence; the collapsed occurrence span includes
that layout so each occurrence remains one exact contiguous source interval.

`_collapse_occurrence_clauses` derives `printed_marker` only from an explicit
record-start regex at the first record-text line. It derives `section_signature`
only from preceding source structural headers. It does not use a person name.

- [ ] **Step 4: Add adversarial partition and metadata tests**

Add separate tests for:

```python
@pytest.mark.parametrize("rendition", ["calamari", "raw_ocr"])
def test_output_is_deterministic_and_input_is_not_mutated(rendition):
    text = "### PAGE 1 ###\n1. Alfa\n2. Beta\n"
    before = text
    first = extract_rendition_occurrences(
        text, rendition=rendition,
        page_map=((1, 496),) if rendition == "calamari" else None,
    )
    second = extract_rendition_occurrences(
        text, rendition=rendition,
        page_map=((1, 496),) if rendition == "calamari" else None,
    )
    assert first == second
    assert text == before


@pytest.mark.parametrize("bad_map", [True, [(1, 496)], ((5, 500), (1, 496))])
def test_calamari_page_map_requires_exact_ordered_tuple(bad_map):
    with pytest.raises(ValueError, match="page_map"):
        extract_rendition_occurrences(
            "1. Alfa\n", rendition="calamari", page_map=bad_map
        )


def test_repeated_printed_numbers_remain_distinct_occurrences():
    result = extract_rendition_occurrences(
        "1. Alfa\nI.\n1. Beta\n", rendition="raw_ocr", page_map=None
    )
    ones = [o for o in result["occurrences"] if o["printed_marker"] == "1"]
    assert len(ones) == 2
    assert len({o["occurrence_id"] for o in ones}) == 2
```

Add a real pinned-map test asserting Calamari page 58 maps to PDF 555 and page
63 maps to PDF 575; this catches accidental reintroduction of a constant offset.
For the gap, overlap and verbatim-corruption tests, deep-copy the real ledger,
change exactly one clause span or `verbatim_text`, monkeypatch
`segment._evidence_ledger` to return it, and assert `ValueError`. Add one fixture
with a page marker between two clauses of the same occurrence and assert that
the collapsed span covers the marker and reports both pages. Add one leading
unclassified prose fixture and assert it remains an occurrence with
`printed_marker is None`. Assert every non-edge predecessor/successor signature
equals the canonical signature of its actual neighbor.

- [ ] **Step 5: Run focused and existing ledger tests**

Run:

```bash
PYTHONPYCACHEPREFIX=/tmp/daa1939-occ-pycache /usr/bin/python3 -m pytest -q \
  .claude/skills/daa-extract/scripts/test_rendition_occurrences_1939.py \
  .claude/skills/daa-extract/scripts/test_segment.py
```

Expected: all tests pass.

- [ ] **Step 6: Commit Task 1**

```bash
git branch --show-current
git add .claude/skills/daa-extract/scripts/rendition_occurrences_1939.py \
  .claude/skills/daa-extract/scripts/test_rendition_occurrences_1939.py
git commit -m "feat: extract exact 1939 rendition occurrences"
```

---

### Task 2: Unique baseline narrative ownership anchors

**Files:**
- Create: `.claude/skills/daa-extract/scripts/dual_rendition_evidence_1939.py`
- Create: `.claude/skills/daa-extract/scripts/test_dual_rendition_evidence_1939.py`

**Interfaces:**
- Produces: `locate_baseline_anchors(baseline_records: list[dict], *, calamari_text: str, raw_text: str, calamari_occurrences: dict, raw_occurrences: dict) -> dict[str, dict]`.
- Each positive result contains `record_key`, `rendition`, `occurrence_id`, exact narrative `span`, `_v2_lokal_id`, and status `unique_exact_anchor`.
- Each negative result contains `record_key`, status `unanchored`, and exactly one primary reason: `missing_exact_baseline_narrative`, `repeated_exact_baseline_narrative`, `unknown_narrative_source`, `anchor_outside_occurrence`, or `anchor_occurrence_collision`.

- [ ] **Step 1: Write failing ownership-anchor tests**

```python
def test_unique_exact_narrative_binds_record_key_to_one_occurrence():
    baseline = [{
        "record_key": "rk-1", "_v2_lokal_id": "I.1",
        "_narrativ_kilde": "calamari", "narrative": "Alfa prosa",
    }]
    result = locate_baseline_anchors(
        baseline,
        calamari_text="1. Alfa prosa\n",
        raw_text="1. A1fa prosa\n",
        calamari_occurrences=occurrence_manifest("calamari", "1. Alfa prosa\n"),
        raw_occurrences=occurrence_manifest("raw_ocr", "1. A1fa prosa\n"),
    )
    assert result["rk-1"]["status"] == "unique_exact_anchor"
    assert result["rk-1"]["rendition"] == "calamari"


@pytest.mark.parametrize("text,reason", [
    ("ingen tekst", "missing_exact_baseline_narrative"),
    ("Alfa prosa / Alfa prosa", "repeated_exact_baseline_narrative"),
])
def test_missing_or_repeated_narrative_never_anchors(text, reason):
    baseline = [{
        "record_key": "rk-1", "_v2_lokal_id": "I.1",
        "_narrativ_kilde": "calamari", "narrative": "Alfa prosa",
    }]
    result = locate_baseline_anchors(
        baseline,
        calamari_text=text,
        raw_text="1. A1fa prosa\n",
        calamari_occurrences=occurrence_manifest("calamari", text),
        raw_occurrences=occurrence_manifest("raw_ocr", "1. A1fa prosa\n"),
    )
    assert result["rk-1"]["status"] == "unanchored"
    assert result["rk-1"]["reason"] == reason
```

- [ ] **Step 2: Run focused test and verify RED**

Run:

```bash
PYTHONPYCACHEPREFIX=/tmp/daa1939-consensus-pycache /usr/bin/python3 -m pytest -q \
  .claude/skills/daa-extract/scripts/test_dual_rendition_evidence_1939.py
```

Expected: collection fails because `dual_rendition_evidence_1939` does not exist.

- [ ] **Step 3: Implement exact anchor location**

```python
NARRATIVE_SOURCES = {"calamari": "calamari", "raw": "raw_ocr"}


def locate_baseline_anchors(
    baseline_records, *, calamari_text, raw_text,
    calamari_occurrences, raw_occurrences,
):
    records = _validate_baseline_records(baseline_records)
    occurrence_indexes = {
        "calamari": _validated_occurrence_index(calamari_occurrences, calamari_text),
        "raw_ocr": _validated_occurrence_index(raw_occurrences, raw_text),
    }
    anchors = {}
    for record in records:
        anchors[record["record_key"]] = _locate_one_exact_anchor(
            record, calamari_text, raw_text, occurrence_indexes
        )
    return _demote_anchor_occurrence_collisions(anchors)
```

Use `str.find` followed by a second `find` from `first + 1`; no whitespace,
case, Unicode, hyphen or OCR normalization is allowed. Empty narrative is
unanchored. An exact slice must be wholly contained in exactly one occurrence.

- [ ] **Step 4: Add full ownership and type tests**

Add tests for duplicate/missing `record_key`, duplicate `_v2_lokal_id`, unknown
`_narrativ_kilde`, empty narrative, a narrative crossing two occurrences, two
records claiming one occurrence, input non-mutation, exact built-in types and a
substring that differs only by whitespace/case/soft hyphen remaining unanchored.

- [ ] **Step 5: Run Tasks 1–2 focused tests**

```bash
PYTHONPYCACHEPREFIX=/tmp/daa1939-consensus-pycache /usr/bin/python3 -m pytest -q \
  .claude/skills/daa-extract/scripts/test_rendition_occurrences_1939.py \
  .claude/skills/daa-extract/scripts/test_dual_rendition_evidence_1939.py
```

Expected: all tests pass.

- [ ] **Step 6: Commit Task 2**

```bash
git branch --show-current
git add .claude/skills/daa-extract/scripts/dual_rendition_evidence_1939.py \
  .claude/skills/daa-extract/scripts/test_dual_rendition_evidence_1939.py
git commit -m "feat: anchor 1939 records to exact narratives"
```

---

### Task 3: Unique monotone cross-rendition consensus

**Files:**
- Modify: `.claude/skills/daa-extract/scripts/dual_rendition_evidence_1939.py`
- Modify: `.claude/skills/daa-extract/scripts/test_dual_rendition_evidence_1939.py`

**Interfaces:**
- Produces: `align_renditions(calamari_manifest: dict, raw_manifest: dict) -> dict`.
- Root result contains `pairs`, `calamari_unmatched`, `raw_unmatched`, and `ambiguous_occurrence_ids`.
- A pair is emitted only when it occurs in every maximum-cardinality monotone alignment allowed by hard compatibility edges.
- Produces: `derive_consensus(anchors: dict[str, dict], alignment: dict, *, calamari_manifest: dict, raw_manifest: dict) -> dict[str, dict]`.

- [ ] **Step 1: Write failing unique-alignment tests**

```python
def test_unique_monotone_alignment_pairs_same_structural_sequence():
    cal = manifest(occ("c1", 0, "1"), occ("c2", 1, "2"))
    raw = manifest(occ("r1", 0, "1"), occ("r2", 1, "2"))
    result = align_renditions(cal, raw)
    assert result["pairs"] == [
        {"calamari_occurrence_id": "c1", "raw_occurrence_id": "r1"},
        {"calamari_occurrence_id": "c2", "raw_occurrence_id": "r2"},
    ]


def test_equally_valid_repeated_marker_is_ambiguous_not_guessed():
    cal = manifest(occ("c1", 0, "1"))
    raw = manifest(occ("r1", 0, "1"), occ("r2", 1, "1"))
    result = align_renditions(cal, raw)
    assert result["pairs"] == []
    assert result["ambiguous_occurrence_ids"] == ["c1", "r1", "r2"]
```

- [ ] **Step 2: Run the two tests and verify RED**

Run their exact node IDs with `/usr/bin/python3 -m pytest -q`. Expected:
`ImportError` for `align_renditions`.

- [ ] **Step 3: Implement hard compatibility and capped alignment enumeration**

```python
def _compatible(left, right):
    return all((
        left["post_class"] in POST_CLASSES,
        right["post_class"] in POST_CLASSES,
        left["post_class"] == right["post_class"],
        left["printed_marker"] == right["printed_marker"],
        _pages_compatible(left["pdf_pages"], right["pdf_pages"]),
        left["section_signature"] == right["section_signature"],
    ))


def align_renditions(calamari_manifest, raw_manifest):
    cal = _validated_occurrences(calamari_manifest, "calamari")
    raw = _validated_occurrences(raw_manifest, "raw_ocr")
    edges = _compatibility_edges(cal, raw)
    optimum = _maximum_monotone_cardinality(edges, len(cal), len(raw))
    forward, backward = _optimal_path_membership(edges, len(cal), len(raw))
    invariant_pairs = _edges_present_in_every_optimal_alignment(
        edges, optimum, forward, backward
    )
    return _alignment_result(cal, raw, invariant_pairs, edges)
```

`_pages_compatible` requires identical sorted physical PDF-page tuples. A page
offset tolerance is not permitted. If source inspection proves a mapping error,
fix the explicit page mapping and regenerate instead of weakening this predicate.

The dynamic program uses integer counts capped at `2`; it never chooses by score
or iteration order. If an edge can be omitted in another optimal alignment, it
is ambiguous and not emitted.

- [ ] **Step 4: Implement record consensus from invariant pairs**

```python
def derive_consensus(
    anchors, alignment, *, calamari_manifest, raw_manifest,
):
    pair_by_occurrence = _bidirectional_pair_index(alignment["pairs"])
    result = {}
    for key in sorted(anchors):
        result[key] = _derive_one_consensus(
            anchors[key], pair_by_occurrence,
            calamari_manifest, raw_manifest,
        )
    return _demote_global_consensus_conflicts(result)
```

`_derive_one_consensus` requires the anchored occurrence to have one invariant
counterpart. It checks compatible predecessor/successor pair signatures and both
interval ends. Section/document edges use explicit sentinels. It emits
`consensus` only when all gates pass; otherwise it emits one allowlisted reason.

- [ ] **Step 5: Add boundary, neighbor and injectivity tests**

Add these explicit fixtures; the shown assertions are mandatory:

```python
def test_different_ocr_wording_can_consensus_when_boundaries_match():
    alignment = align_renditions(
        manifest(occ("c1", 0, "1", text="Volrad")),
        manifest(occ("r1", 0, "1", text="V o 1 r a d")),
    )
    assert alignment["pairs"] == [{
        "calamari_occurrence_id": "c1", "raw_occurrence_id": "r1",
    }]


def test_volrad_span_containing_emeke_anchor_is_boundary_disagreement():
    result = derive_consensus(
        anchors_with_nested_successor("rk-volrad", "rk-emeke"),
        alignment_for("c-volrad", "r-volrad", "c-emeke", "r-emeke"),
        calamari_manifest=volrad_manifest("calamari", nested=False),
        raw_manifest=volrad_manifest("raw_ocr", nested=True),
    )
    assert result["rk-volrad"]["status"] == "unanchored"
    assert result["rk-volrad"]["reason"] == "boundary_disagreement"


def test_alignment_is_identical_after_deepcopy():
    cal = manifest(occ("c1", 0, "1"), occ("c2", 1, "2"))
    raw = manifest(occ("r1", 0, "1"), occ("r2", 1, "2"))
    assert align_renditions(cal, raw) == align_renditions(
        copy.deepcopy(cal), copy.deepcopy(raw)
    )
```

Define `anchors_with_nested_successor`, `alignment_for` and `volrad_manifest`
as literal two-record factories in the test module. Add one test per remaining
reason: predecessor reorder, missing successor, page disagreement, post-class
disagreement, two record keys owning one occurrence, overlapping accepted spans
and document-edge sentinel. Each test asserts `status == "unanchored"` plus the
exact allowlisted reason; the post-class fixture additionally asserts that no
compatibility edge is created.

- [ ] **Step 6: Run Tasks 1–3 focused tests**

Run both test files. Expected: all tests pass.

- [ ] **Step 7: Commit Task 3**

```bash
git branch --show-current
git add .claude/skills/daa-extract/scripts/dual_rendition_evidence_1939.py \
  .claude/skills/daa-extract/scripts/test_dual_rendition_evidence_1939.py
git commit -m "feat: derive unique 1939 OCR consensus"
```

---

### Task 4: Strict source-bound evidence materialization

**Files:**
- Modify: `.claude/skills/daa-extract/scripts/dual_rendition_evidence_1939.py`
- Modify: `.claude/skills/daa-extract/scripts/test_dual_rendition_evidence_1939.py`
- Modify: `.claude/skills/daa-extract/scripts/review_queue_1939.py`
- Modify: `.claude/skills/daa-extract/scripts/test_review_queue_1939.py`
- Modify: `.claude/skills/daa-extract/scripts/prepare_review_queue_1939.py`
- Modify: `.claude/skills/daa-extract/scripts/test_prepare_review_queue_1939.py`

**Interfaces:**
- Produces: `build_source_bound_evidence(baseline_bytes: bytes, calamari_bytes: bytes, raw_bytes: bytes, pdf_bytes: bytes, *, profile_version: str) -> tuple[dict, dict, dict]` returning evidence, Calamari occurrence manifest and raw occurrence manifest.
- Positive provenance kind and rule ID are exactly `dual_rendition_consensus_v1`.
- Extends the existing strict provenance-kind allowlist; all previous kinds and no-flag behavior remain unchanged.

- [ ] **Step 1: Write failing end-to-end evidence test**

```python
def test_consensus_materializes_existing_strict_evidence_grammar():
    evidence, cal_occ, raw_occ = build_source_bound_evidence(
        baseline_bytes=baseline_bytes("Alfa prosa", source="calamari"),
        calamari_bytes=b"### PAGE 1 ###\n1. Alfa prosa\n2. Beta\n",
        raw_bytes=b"### PAGE 1 ###\n1. A1fa prosa\n2. Beta\n",
        pdf_bytes=b"%PDF-synthetic",
        profile_version="1939-v2",
    )
    entry = evidence["entries"][0]
    assert entry["positive_provenance"] == {
        "kind": "dual_rendition_consensus_v1",
        "baseline_record_key": "rk-1",
        "candidate_id": entry["candidates"][0]["candidate_id"],
    }
    classify_review_entries(
        evidence["source"], {"rk-1"}, evidence["entries"]
    )
```

- [ ] **Step 2: Run the new test and verify RED**

Expected: import failure for `build_source_bound_evidence` or rejection of the
new provenance kind.

- [ ] **Step 3: Implement evidence construction**

```python
RULE_ID = "dual_rendition_consensus_v1"


def build_source_bound_evidence(
    baseline_bytes, calamari_bytes, raw_bytes, pdf_bytes,
    *, profile_version,
):
    _require_exact_boundary_types(
        baseline_bytes, calamari_bytes, raw_bytes, pdf_bytes,
        profile_version,
    )
    baseline = _strict_baseline_json(baseline_bytes)
    calamari_text = calamari_bytes.decode("utf-8", errors="strict")
    raw_text = raw_bytes.decode("utf-8", errors="strict")
    cal_occ = extract_rendition_occurrences(
        calamari_text, rendition="calamari",
        page_map=CALAMARI_R6_TO_PDF_V1,
    )
    raw_occ = extract_rendition_occurrences(
        raw_text, rendition="raw_ocr", page_map=None
    )
    anchors = locate_baseline_anchors(
        baseline,
        calamari_text=calamari_text,
        raw_text=raw_text,
        calamari_occurrences=cal_occ,
        raw_occurrences=raw_occ,
    )
    alignment = align_renditions(cal_occ, raw_occ)
    consensus = derive_consensus(
        anchors, alignment,
        calamari_manifest=cal_occ, raw_manifest=raw_occ,
    )
    evidence = _materialize_complete_evidence(
        baseline, consensus,
        baseline_bytes=baseline_bytes, calamari_bytes=calamari_bytes,
        raw_bytes=raw_bytes, pdf_bytes=pdf_bytes,
        profile_version=profile_version,
    )
    return evidence, cal_occ, raw_occ
```

Candidate IDs are deterministic:

```python
candidate_id = "1939:dual-v1:" + hashlib.sha256(
    canonical_json({
        "record_key": key,
        "calamari_span": cal_span,
        "raw_span": raw_span,
        "source": source,
    })
).hexdigest()
```

The candidate uses the Calamari occurrence span, compatible PDF pages and the
raw occurrence span/digest. A non-consensus entry has no candidate/provenance,
stores sorted allowlisted conflict codes, and uses `source_blockers` only for
missing/invalid source material.

- [ ] **Step 4: Extend strict queue provenance and diagnostics**

Add `dual_rendition_consensus_v1` to the explicit provenance allowlists in both
queue validation layers. Add Danish reason text for the allowlisted consensus
failure codes. `_classify_one` may preserve the highest-priority allowlisted
code as `reason_code`, but it must still return `human_required`; unknown or
multiple malformed codes return `evidence_conflict`.

- [ ] **Step 5: Add adversarial evidence tests**

Add tests that reject/demote:

- bool/float/string schema versions and page offsets;
- bytes subclasses and mapping/list/string subclasses at trust boundaries;
- a candidate whose source span or raw digest does not match current bytes;
- changed baseline, Calamari, raw or PDF bytes;
- duplicate candidate IDs, occurrence owners or overlapping spans;
- a `presentation:` candidate ID;
- a source-less artifact with positive fields;
- a v2 locator plus name/page but no exact narrative ownership anchor;
- a fabricated dual-consensus provenance attached to a non-consensus candidate.
- an occurrence representing one of the seven filtered overview duplicates in
  both renditions: because it has no key in the 546-record baseline, it remains
  unmatched and cannot create an extra evidence entry or person.

Also assert the current source-less V1 template still classifies every key as
`human_required/no_candidate`.

- [ ] **Step 6: Run focused evidence and queue suites**

```bash
PYTHONPYCACHEPREFIX=/tmp/daa1939-evidence-pycache /usr/bin/python3 -m pytest -q \
  .claude/skills/daa-extract/scripts/test_rendition_occurrences_1939.py \
  .claude/skills/daa-extract/scripts/test_dual_rendition_evidence_1939.py \
  .claude/skills/daa-extract/scripts/test_review_queue_1939.py \
  .claude/skills/daa-extract/scripts/test_prepare_review_queue_1939.py
```

Expected: all tests pass.

- [ ] **Step 7: Commit Task 4**

```bash
git branch --show-current
git add .claude/skills/daa-extract/scripts/dual_rendition_evidence_1939.py \
  .claude/skills/daa-extract/scripts/test_dual_rendition_evidence_1939.py \
  .claude/skills/daa-extract/scripts/review_queue_1939.py \
  .claude/skills/daa-extract/scripts/test_review_queue_1939.py \
  .claude/skills/daa-extract/scripts/prepare_review_queue_1939.py \
  .claude/skills/daa-extract/scripts/test_prepare_review_queue_1939.py
git commit -m "feat: materialize dual-rendition 1939 evidence"
```

---

### Task 5: Exclusive CLI, deterministic report and documented workflow

**Files:**
- Create: `.claude/skills/daa-extract/scripts/prepare_dual_rendition_evidence_1939.py`
- Create: `.claude/skills/daa-extract/scripts/test_prepare_dual_rendition_evidence_1939.py`
- Modify: `.claude/skills/daa-extract/SKILL.md`

**Interfaces:**
- CLI:

```bash
/usr/bin/python3 .claude/skills/daa-extract/scripts/prepare_dual_rendition_evidence_1939.py \
  --baseline BASELINE.json --calamari CALAMARI.txt --raw RAW.txt --pdf SOURCE.pdf \
  --profile-version 1939-v2 \
  --calamari-occurrences-out CAL.json --raw-occurrences-out RAW.json \
  --evidence-out EVIDENCE.json --report-out REPORT.json
```

- All four outputs use exclusive creation. Any failure removes only files
created by that invocation.
- Report fields include input hashes, baseline total, exact-anchor counts by
source/result, occurrence/alignment counts, consensus total, every reason count,
collision/overlap counts and deterministic artifact SHA-256 values.

- [ ] **Step 1: Write failing CLI success and cleanup tests**

```python
def test_cli_writes_four_exclusive_source_bound_outputs(tmp_path):
    args, outputs = cli_fixture(tmp_path, suffix="a")
    assert main(args) == 0
    assert all(path.exists() for path in outputs.values())
    evidence = json.loads(outputs["evidence"].read_text())
    assert evidence["source"]["profile_version"] == "1939-v2"


def test_cli_refuses_any_existing_output_before_reading_sources(tmp_path):
    args, outputs = cli_fixture(tmp_path, suffix="existing")
    outputs["raw_occurrences"].write_text("preserve")
    with pytest.raises(FileExistsError):
        main(args)
    assert outputs["raw_occurrences"].read_text() == "preserve"
    assert not outputs["evidence"].exists()


def test_two_clean_runs_are_byte_identical(tmp_path):
    args_a, outputs_a = cli_fixture(tmp_path, suffix="a")
    args_b, outputs_b = cli_fixture(tmp_path, suffix="b")
    assert main(args_a) == main(args_b) == 0
    for name in outputs_a:
        assert outputs_a[name].read_bytes() == outputs_b[name].read_bytes()
```

`cli_fixture` writes the same minimal baseline/OCR/PDF input bytes for every
suffix and returns the exact argv list plus four distinct output paths. Add a
cleanup test that monkeypatches the third exclusive write to raise, then asserts
the first two newly created files were removed, the third/fourth do not exist,
and a pre-existing sentinel outside the four paths is unchanged.

The report must not embed output paths so two clean runs can be byte-identical.

- [ ] **Step 2: Run the CLI test file and verify RED**

Expected: collection fails because the CLI module does not exist.

- [ ] **Step 3: Implement byte-captured exclusive CLI**

Read each input exactly once as built-in `bytes`, call
`build_source_bound_evidence`, serialize canonical sorted/indented JSON bytes in
memory, calculate output hashes from those bytes, and then create outputs with
mode `xb`. Validate all output paths are pairwise distinct before reading input.

- [ ] **Step 4: Document exact V2 commands and boundaries**

Document:

1. evidence/occurrence generation;
2. Task 6 queue/report generation with source-bound evidence;
3. V2 HTML generation;
4. deterministic audit and browser export;
5. exclusive regeneration with new filenames;
6. ignored/private artifact rules;
7. explicit statement that review-tool `GO` is not database/deployment GO.

- [ ] **Step 5: Run CLI and prior focused suites**

```bash
PYTHONPYCACHEPREFIX=/tmp/daa1939-dual-cli-pycache /usr/bin/python3 -m pytest -q \
  .claude/skills/daa-extract/scripts/test_prepare_dual_rendition_evidence_1939.py \
  .claude/skills/daa-extract/scripts/test_dual_rendition_evidence_1939.py \
  .claude/skills/daa-extract/scripts/test_prepare_review_queue_1939.py
```

Expected: all tests pass.

- [ ] **Step 6: Commit Task 5**

```bash
git branch --show-current
git add .claude/skills/daa-extract/scripts/prepare_dual_rendition_evidence_1939.py \
  .claude/skills/daa-extract/scripts/test_prepare_dual_rendition_evidence_1939.py \
  .claude/skills/daa-extract/SKILL.md
git commit -m "feat: prepare private dual-rendition evidence"
```

---

### Task 6: Exception-first V2 UI diagnostics and audit visibility

**Files:**
- Modify: `.claude/skills/daa-extract/scripts/prepare_review_queue_1939.py`
- Modify: `.claude/skills/daa-extract/scripts/test_prepare_review_queue_1939.py`
- Modify: `.claude/skills/daa-extract/scripts/make_human_review_1939.py`
- Modify: `.claude/skills/daa-extract/scripts/test_make_human_review_1939.py`
- Modify: `.claude/skills/daa-extract/scripts/human_review_1939_ui.js`
- Modify: `web/src/humanReview1939Ui.test.ts`

**Interfaces:**
- Default view contains `human_required` and `source_blocked` only.
- A separate `Stikprøver` filter exposes only deterministic audit entries.
- Each exception displays `reason_da` and a short comparison of Calamari/raw
boundary status; hashes remain in an optional technical disclosure.
- Existing localStorage, save confirmation, reload, undo and export schemas are
unchanged.

- [ ] **Step 1: Write failing view-model and DOM tests**

```python
def test_default_view_contains_only_real_exceptions():
    model = build_review_view_model(
        baseline_records("rk-auto", "rk-human"),
        manifest_with_auto_and_human(), nearby_candidates={},
        audit_keys=["rk-auto"], decisions={},
    )
    assert model["default_view"] == "required"
    assert model["views"]["required"] == ["rk-human"]
    assert model["views"]["audit"] == ["rk-auto"]


def test_diagnostic_reason_is_danish_and_specific():
    record = view_record_for_reason("boundary_disagreement")
    assert record["reason_code"] == "boundary_disagreement"
    assert "grænse" in record["reason_da"].lower()


def test_volrad_boundary_disagreement_shows_successor_context_once():
    record = view_record_for_reason(
        "successor_disagreement", successor="Emeke"
    )
    html = render_review_record(record)
    assert html.count("Emeke") == 1
```

```typescript
it('starts on exceptions and exposes automatic records only as samples', () => {
  startReview({ storage: memoryStorage(), records: [
    humanRecord('rk-human', 'candidate-human'),
    automaticRecord('rk-audit', 'candidate-audit', true),
  ] });
  expect(document.body.textContent).toContain('rk-human');
  expect(document.body.textContent).not.toContain('rk-audit');
  document.querySelector<HTMLButtonElement>('[data-view="audit"]')!.click();
  expect(document.body.textContent).toContain('rk-audit');
});

it('preserves save, reload, undo and export behavior in V2', () => {
  const storage = memoryStorage();
  startReview({
    storage, records: [humanRecord('rk-1', 'candidate-1')],
  });
  document.querySelector<HTMLButtonElement>('[data-action="select-candidate"]')!.click();
  expect(document.querySelector('[data-role="save-state"]')!.textContent).toContain('Gemt');
  document.body.innerHTML = '';
  const second = startReview({
    storage, records: [humanRecord('rk-1', 'candidate-1')],
  });
  expect(document.body.textContent).toContain('Valgt');
  document.querySelector<HTMLButtonElement>('[data-action="undo"]')!.click();
  expect(document.body.textContent).not.toContain('Valgt');
  second.controller.exportDraft();
});
```

- [ ] **Step 2: Run focused Python/DOM tests and verify RED**

```bash
PYTHONPYCACHEPREFIX=/tmp/daa1939-ui-v2-pycache /usr/bin/python3 -m pytest -q \
  .claude/skills/daa-extract/scripts/test_make_human_review_1939.py \
  .claude/skills/daa-extract/scripts/test_prepare_review_queue_1939.py
npm --prefix web test -- src/humanReview1939Ui.test.ts
```

- [ ] **Step 3: Implement the smallest diagnostic view changes**

Extend only the existing view-model records and event-delegated controller.
Do not add a second persistence format or inline JavaScript handlers. Render all
source strings through the existing escaping/JSON embedding boundary.

- [ ] **Step 4: Add hostile diagnostic rendering tests**

Cover `</script>` in a reason, mixed-case closing tags, record keys containing
CSS/HTML metacharacters, unknown reason codes, empty audit strata and a
source-blocked-only queue. Unknown diagnostics must render the generic
fail-closed explanation and never become automatic.

- [ ] **Step 5: Run focused UI suites**

Run the Step 2 commands. Expected: all tests pass.

- [ ] **Step 6: Commit Task 6**

```bash
git branch --show-current
git add .claude/skills/daa-extract/scripts/prepare_review_queue_1939.py \
  .claude/skills/daa-extract/scripts/test_prepare_review_queue_1939.py \
  .claude/skills/daa-extract/scripts/make_human_review_1939.py \
  .claude/skills/daa-extract/scripts/test_make_human_review_1939.py \
  .claude/skills/daa-extract/scripts/human_review_1939_ui.js \
  web/src/humanReview1939Ui.test.ts
git commit -m "feat: show only 1939 evidence exceptions"
```

---

### Task 7: Private 546-record V2 pilot and exact accounting

**Files:**
- Create ignored outputs only under `work/task19-1939-pilot/`.
- Modify source/tests only if the real run exposes a reproducible contract bug;
  fix it first with a synthetic failing test and a separate commit.

**Interfaces:**
- Inputs are the existing pinned 546-record baseline, Calamari OCR, raw OCR and
1939 PDF.
- Outputs use the exact V2 names from the design and never overwrite V1/V5.
- Produces exact machine-readable counts; no minimum automatic count is a gate.

- [ ] **Step 1: Record immutable input and preserved-output hashes**

Run SHA-256 over the four inputs and all existing V1/V5 artifacts. Store the
command output in the ignored Task 7 run report, not Git.

- [ ] **Step 2: Generate dual occurrence/evidence artifacts twice**

Use the documented CLI with distinct `v2-run-a` and `v2-run-b` output paths.
Compare corresponding bytes with `cmp`. Any difference is a failure.

- [ ] **Step 3: Create a fresh review template, then generate queue/report V2**

Run `prepare_coverage_1939.py --make-review-template` to create the exclusive
`coverage-review-v2.json` from the same baseline. Then run
`prepare_review_queue_1939.py` with the V2 source-bound evidence as `--evidence`
and the new source-less unreviewed template as `--review`. Use exclusive
`review-queue-manifest-v2.json` and `review-queue-report-v2.json` outputs.

- [ ] **Step 4: Generate the V2 HTML**

Run `make_human_review_1939.py` with the V2 queue/source manifest and write
`menneskeark-undtagelsesko-v2.html` exclusively.

- [ ] **Step 5: Assert exact accounting and inspect Volrad**

Machine assertions require:

```python
assert baseline_total == 546
assert auto_resolved + human_required + source_blocked == 546
assert completed == 0
assert publication_gate == "NO-GO"
assert all candidate_ids and spans are globally injective
assert no accepted Calamari/raw spans overlap
```

For Volrad, record its actual class, reason, Calamari span, raw span and neighbor
signatures. If it is automatic, both renditions must end before the independently
recognized Emeke/Henrik occurrence. Otherwise it must be a visible exception.

- [ ] **Step 6: Run the focused suites**

```bash
PYTHONPYCACHEPREFIX=/tmp/daa1939-v2-pilot-pycache /usr/bin/python3 -m pytest -q \
  .claude/skills/daa-extract/scripts/test_rendition_occurrences_1939.py \
  .claude/skills/daa-extract/scripts/test_dual_rendition_evidence_1939.py \
  .claude/skills/daa-extract/scripts/test_prepare_dual_rendition_evidence_1939.py \
  .claude/skills/daa-extract/scripts/test_review_queue_1939.py \
  .claude/skills/daa-extract/scripts/test_prepare_review_queue_1939.py \
  .claude/skills/daa-extract/scripts/test_make_human_review_1939.py \
  .claude/skills/daa-extract/scripts/test_review_choices_1939.py \
  .claude/skills/daa-extract/scripts/test_prepare_coverage_1939.py
npm --prefix web test -- src/humanReview1939Ui.test.ts
```

- [ ] **Step 7: Run full suites and report baselines separately**

```bash
PYTHONPYCACHEPREFIX=/tmp/daa1939-v2-full-pycache /usr/bin/python3 -m pytest -q \
  .claude/skills/daa-extract/scripts
npm --prefix web test
```

Do not call the full web baseline green if Supabase variables still prevent
suite collection. Report focused controller results separately.

- [ ] **Step 8: Confirm private scope and commit source fixes only**

```bash
git branch --show-current
git status --short --ignored
git check-ignore work/task19-1939-pilot/
```

Do not stage any `work/` file. If no source bug was found, Task 7 has no commit.

---

### Task 8: Independent data-quality review and handoff

**Files:**
- Review only all tracked changes from Tasks 1–7.
- Read but never modify the new private V2 artifacts.

**Interfaces:**
- Produces severity-sorted findings and separate gates for private review use and
publication. It never grants database/deployment permission.

- [ ] **Step 1: Trace the full ownership chain**

Trace source bytes → clause ledger → occurrence spans → unique narrative anchor
→ compatibility edges → invariant alignment pair → consensus → evidence
candidate/provenance → queue class → audit sample → HTML/export → publication
report.

- [ ] **Step 2: Attempt to falsify every automatic gate within the risk model**

Exercise substituted source bytes, duplicate narratives, repeated markers,
equally optimal alignments, neighbor reorder, section edges, page drift,
occurrence/candidate/span collisions, stale or mixed pipeline artifacts,
presentation IDs, stale V1 review data and incomplete audits. Do not require
defenses against deliberately forged trusted intermediate JSON or exhaustive
revalidation of upstream metadata that the consumer does not use.

- [ ] **Step 3: Verify scope and immutable private history**

```bash
git diff --name-only 968833d..HEAD
git status --short --ignored
```

Compare recorded V1/V5 hashes with their current hashes and confirm every new V2
artifact is ignored.

- [ ] **Step 4: Re-run fresh focused and full verification**

Run Task 7 Steps 6 and 7 from a clean tracked worktree. Record exact counts and
failures separately.

- [ ] **Step 5: Report final gates**

Report:

- exact automatic, audit, human and source-blocked counts by reason/post class;
- unique-exact-anchor counts by source and failure reason;
- alignment pair/ambiguity counts;
- Volrad result and boundary evidence;
- focused/full test results;
- all review findings and resolution commits;
- `GO` or `NO-GO` for private HTML review use;
- publication gate from the actual report, expected `NO-GO` before decisions and
  audit completion;
- explicit statement that DB reimport, Supabase, Vercel and production remain
  outside scope.
