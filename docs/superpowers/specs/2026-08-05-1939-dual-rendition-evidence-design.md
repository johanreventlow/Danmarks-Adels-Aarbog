# 1939 dual-rendition evidence design

## Purpose

Reduce unnecessary editorial work in the private 1939 review queue without
weakening its fail-closed publication boundary. The system may hide a record
from the normal human queue only when the Calamari and raw-OCR renditions
independently delimit the same logical source record. Any disagreement remains
visible for human review.

This design approves only generation of private, source-bound evidence and a
new review-queue version. It does not authorize database reimport, canonical
person mutation, Supabase or Vercel deployment, or production promotion.

## Current state

The V1 queue accounts for all 546 baseline `record_key` values, but its evidence
input is intentionally source-less. It therefore contains zero positive
candidates and classifies all 546 records as `human_required/no_candidate`.
The review UI and publication gate are already fail-closed and independently
reviewed. This phase supplies them with source-bound evidence; it does not
relax their contracts.

## Trust and risk model

This is a private editorial import tool, not a hostile-input service. Artifacts
produced by one step of the same pinned local pipeline are trusted as that
step's output. A consumer validates the fields it actually relies on and the
cross-step facts needed to prevent a wrong import; it does not revalidate every
unused metadata field merely to defend against a deliberately forged internal
JSON file.

The realistic risks in scope are stale or mixed source files, ambiguous or
missing ownership, incomplete coverage, overlaps, reordered records, identity
collisions and accidental malformed input. Source hashes, exact narrative
ownership, complete span partitions, injectivity, deterministic output and the
human exception queue remain required. Deliberate manipulation of ignored
intermediate artifacts is outside the threat model.

The baseline has 546 unique `_v2_lokal_id` values, but a locator is not source
identity and cannot prove a match by itself. Existing Calamari segmentation also
contains missing and colliding structural identifiers. Reusing those identifiers
as sufficient evidence would make the new process circular.

## Decision

Use dual-rendition structural consensus.

Calamari and raw OCR are parsed independently into exact source occurrences.
A baseline record becomes `auto_resolved` only when both occurrence streams
support one globally injective mapping to its `record_key`, agree on the logical
record boundaries, and pass all existing source/hash/candidate validators.

OCR wording may differ. Agreement concerns record ownership and structure:
the same logical record, the same predecessor and successor anchors, compatible
PDF pages, and non-overlapping exact spans in each rendition.

The existing v2 locator is a corroborating signal and lookup aid. It is never
sufficient positive evidence, whether alone or combined only with a name, number,
page, similarity score, or candidate rank.

## Architecture

### 1. Rendition occurrence extraction

A pure Python component extracts occurrences separately from:

- the pinned Calamari text;
- the pinned raw OCR text.

Each occurrence contains only source-derived data:

- a stable run-local occurrence ID;
- exact `char_from` and `char_to` offsets in that rendition;
- the exact verbatim slice digest;
- the PDF page or page interval supported by explicit page markers/mapping;
- structural headers in effect at the occurrence;
- its printed record marker, when present;
- the previous and next occurrence IDs and structural signatures;
- a post class: `nummereret`, `stamfader`, or `oversigtspost`.

Calamari page numbers are not converted with a constant offset. Its cropped PDF
omits illustration plates, so the mapping to physical PDF pages is the existing
verified piecewise map with ID `calamari-r6-to-pdf-v1`. Its control points are
stored as `(Calamari page, physical PDF page)`:

```text
(1,496), (5,500), (10,505), (15,510), (20,515), (25,520),
(30,525), (40,535), (45,540), (50,545), (53,550), (58,555),
(63,575), (68,580), (73,585), (78,590), (83,595), (85,598),
(86,598)
```

Intermediate pages use deterministic piecewise-linear interpolation and nearest
integer rounding. Raw OCR page markers already contain physical PDF pages and
use mapping ID `raw-absolute-pdf-v1`. The mapping ID and control points are
included in the private occurrence manifests. An absent, changed, unordered or
non-monotone map blocks generation; no constant-offset fallback is allowed.

Extraction preserves uncertain prose as an unanchored occurrence. It never
assigns `record_key`, invents a missing header, or silently joins adjacent prose.

### 2. Cross-rendition consensus

A separate pure function compares the two occurrence streams with the complete
546-record baseline. It produces exactly one evidence entry for every
`record_key`.

A positive match requires all of the following:

1. Exactly one eligible Calamari occurrence and one eligible raw occurrence.
2. A positive baseline ownership anchor: the baseline record's stored narrative
   must occur exactly once, codepoint-for-codepoint in decoded Unicode, in the rendition
   named by its pinned `_narrativ_kilde`, and that exact slice must be contained
   by the proposed occurrence. A repaired, missing, repeated or non-exact
   narrative is not an automatic anchor.
3. A unique structural address within each rendition.
4. Compatible post class and PDF-page evidence.
5. Agreement on predecessor and successor logical anchors. At a document or
   section edge, the corresponding explicit boundary replaces the missing
   neighbor.
6. An injective global assignment: neither occurrence, candidate ID, Calamari
   span, nor raw span belongs to another baseline record.
7. No split, merge, overlap, reordered neighbor, source blocker, or conflicting
   signal.
8. Exact source hashes and pinned profile version.

The baseline `_v2_lokal_id` may narrow the candidate set only after the
occurrences have been independently extracted. It cannot satisfy any missing
gate and cannot resolve a collision.

The exact stored narrative is the positive link from an opaque `record_key` to
one physical rendition occurrence. Dual-rendition structural agreement then
checks that the independently extracted occurrence in the other rendition has
the same logical ownership and boundaries. This avoids using a structural
locator to prove itself. Records without a unique exact narrative anchor remain
human work in this phase; no fuzzy fallback is permitted.

### 3. Source-bound evidence materialization

The consensus result is materialized in the existing strict Task 6 evidence
grammar:

- one entry per baseline `record_key`;
- exactly one complete candidate plus matching positive provenance for a
  consensus match;
- no candidate and a deterministic conflict/reason code otherwise;
- exact Calamari span, PDF pages, raw structure span, and raw excerpt digest;
- complete source object with baseline, Calamari, raw OCR and PDF SHA-256 values
  plus profile version.

Positive provenance uses a new versioned rule ID describing dual-rendition
consensus. The existing queue classifier remains the final authority and
revalidates the produced candidate through the current coverage contract.

### 4. Existing queue and UI

The current queue classifier, deterministic audit sampler, view-model builder,
browser controller, export conversion and publication report remain the final
gate. Their validation semantics are not relaxed. The classifier/view model may
be extended only to preserve allowlisted diagnostic reasons from a rejected
consensus candidate. They receive a new source-bound evidence artifact and
produce exclusive V2 outputs.

The normal UI starts on exceptions only. Automatically resolved records are
available in a separate sample/audit view. Each exception displays a short,
specific Danish explanation of the failed gate rather than internal hash data.

## Classification and reason codes

Consensus matches enter the existing `auto_resolved` class and deterministic
audit sampling.

All other records are classified fail-closed. The evidence generator reports
one primary reason and may retain secondary diagnostic details. Required primary
reasons are:

- `missing_in_calamari`;
- `missing_in_raw_ocr`;
- `multiple_calamari_occurrences`;
- `multiple_raw_occurrences`;
- `boundary_disagreement`;
- `predecessor_disagreement`;
- `successor_disagreement`;
- `page_disagreement`;
- `post_class_disagreement`;
- `occurrence_collision`;
- `span_overlap`;
- `ambiguous_structure`;
- `known_overview_duplicate`;
- `source_material_missing`.

A source file that is absent, has a wrong hash, cannot be decoded, or cannot be
fully accounted for blocks generation. It does not yield a partial positive
artifact.

## Boundary semantics

The two OCR spans do not need equal text or equal character offsets. They must
represent the same logical interval in document order.

Agreement is established by matching both ends of the interval:

- the record begins after the same accepted predecessor or explicit section
  boundary;
- it ends before the same accepted successor or explicit section/document
  boundary;
- no third occurrence starts inside either span;
- neither span is reused or overlaps another accepted record.

For a Volrad-like block, the record is automatic only if both renditions place
the successor boundary before Emeke/Henrik. If either rendition includes those
persons in Volrad's interval or lacks an unambiguous boundary, Volrad receives
`boundary_disagreement` or `successor_disagreement` and stays in human review.

## Known duplicates and special post classes

The seven known overview duplicates remain explicit non-promotable exceptions.
They are never converted into ordinary people by consensus.

Unnumbered founders and overview records use the same dual-rendition rule but
their structural signature is based on explicit section context and neighboring
occurrences rather than a printed person number. A missing or repeated signature
is `ambiguous_structure`.

## Audit and editorial workload

The established deterministic sample remains five percent of `auto_resolved`,
with at least two records from every present `(rule_id, postklasse)` stratum.
Audit failures or undecidable samples block their complete rule group and keep
the publication report at `NO-GO`.

The default human queue contains only `human_required` and `source_blocked`
records. Automatic records remain inspectable through the sample/audit view.
No user is asked to review an automatic record outside the deterministic audit
unless a later source or rule change invalidates its evidence.

## Output lifecycle

All generated files are private and ignored. Writers use exclusive creation and
remove partial outputs after an error. Existing V1/V5 files are never modified.

The first successful run creates new versioned artifacts, including:

- a dual-rendition occurrence manifest for each OCR source;
- a source-bound evidence artifact;
- `review-queue-manifest-v2.json`;
- `review-queue-report-v2.json`;
- `menneskeark-undtagelsesko-v2.html`.

Every artifact records its schema/rule version and upstream hashes. Reuse is
allowed only when all bytes, versions, page-mapping IDs/control points, counts
and digests match.

## Testing and acceptance

### Pure synthetic tests

Tests cover:

- exact two-rendition agreement;
- differing OCR text with matching structural boundaries;
- Volrad-like overrun into the next person;
- missing, duplicate, reordered and merged occurrences;
- section and document edges;
- page and post-class disagreement;
- candidate, occurrence and span collisions;
- malformed types, hashes and source bytes;
- input non-mutation and deterministic output.

For each positive fixture, changing one boundary, neighbor, page, class or owner
must demote the record or reject the artifact.

### Private 546-record regression

The private run must:

- account for all 546 unique `record_key` values exactly once;
- produce globally injective positive assignments;
- contain no overlapping accepted Calamari or raw spans;
- pass the existing coverage, queue, choice and publication validators;
- produce byte-identical occurrence, evidence, queue and report artifacts on two
  clean runs with different output paths;
- leave all earlier private artifacts byte-for-byte unchanged.

The report records exact counts by queue class, post class, rule and reason code.
No target count of automatic records is a correctness criterion. A low automatic
count is acceptable; a false positive is not.

### UI regression

The V2 HTML must preserve the verified browser behavior: visible save
confirmation, local persistence, reload recovery, undo and durable JSON export.
The actual Volrad record is checked to ensure that its displayed text and
classification reflect the dual-rendition boundary result.

### Review gate

An independent data-quality review traces source bytes through occurrence
extraction, consensus, evidence, queue, audit and HTML. It attempts to expose
realistic pipeline failures that could omit, duplicate or misassign source
records, but does not require defenses against deliberately forged trusted
intermediate files. Private review use is `GO` only with no unresolved P0/P1
finding within this risk model. Database reimport and deployment remain
`NO-GO` and outside this specification.

## Non-goals

- Rewriting `load_daa.R`.
- Changing canonical genealogy, identities, facts, families or unions.
- Promoting model output or similarity scores as identity evidence.
- Completing the separate facts-after-extraction v3 pipeline.
- Deploying to Supabase, Vercel or production.
- Optimizing the automatic count by weakening a gate.
