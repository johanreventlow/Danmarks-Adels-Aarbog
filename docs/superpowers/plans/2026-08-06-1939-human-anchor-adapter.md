# 1939 Human-Anchor-Adapter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Gør redaktørens menneskeark-valg anvendelige som accepteret, source-bound evidens (fail-closed), og gør menneskearbejdet migrerbart og ærligt mærket i UI'en.

**Architecture:** Nyt adapter-script efterforankrer eksporterede valg deterministisk til hash-fastlåste Calamari-spans (rå-bro hvor invariant alignment findes, ellers eksplicit `approval`), producerer den manglende anchored-candidates-wrapper og komponerer sikre human-erstatninger ind i et obligatorisk, komplet base-evidence-bundle. Kandidat-kontrakten udvides bagudkompatibelt (`raw_structure_bridge` ELLER `approval`). Task-5-outputtet `{decisions, audit_results}` joines med composed evidence i `prepare_review_queue_1939.py`; grænsen er review-/fil-GO, ikke coverage-materialisering. Generator + UI får reproducerbar kladde-genindlejring og per-post-karantæne.

**Tech Stack:** Python 3 (stdlib only, `/usr/bin/python3` har pytest 8.4.2 — homebrew-python har IKKE pytest), vanilla JS (`human_review_1939_ui.js`, testes via vitest i `web/`).

## Global Constraints

- Arbejdet foregår i worktree `/Users/johanreventlow/TypeScript/danmarksadelsaarbog/.claude/worktrees/evidensbaseret-genimport`, branch `feat/evidensbaseret-genimport`. Verificér `git branch --show-current` før hver commit.
- Kør pytest som `/usr/bin/python3 -m pytest <filer> -q -p no:cacheprovider` fra `.claude/skills/daa-extract/scripts/`.
- Ingen skrivning til database/Supabase/Vercel. Ingen filer under `work/` committes. `work_1939_stamtavle/` og PDF er read-only kilder.
- Alle output-filer oprettes eksklusivt (`open("x")`); genkørsel kræver nyt filnavn.
- Fejlbeskeder på dansk, samme stil som eksisterende (`raise ValueError("…")`).
- `presentation:`-namespace må ALDRIG kunne blive accepteret evidens (uændret invariant).
- Commit-beskeder: Conventional Commits, dansk, ingen Claude-attribution-footers, MEN afsluttes med `Claude-Session: https://claude.ai/code/session_017bLbJ5YYJcmYZ5EvzJTA72`.
- Eksisterende tests må ikke knække: kør berørte suiter efter hver task.
- Design-spec: `docs/superpowers/specs/2026-08-06-1939-human-anchor-adapter-design.md` (læs den først).

---

### Task 1: Kontrakt-udvidelse — `approval` som alternativ til rå-bro

**Files:**
- Modify: `.claude/skills/daa-extract/scripts/coverage_1939.py` (`_validate_candidate`, ny konstant `APPROVAL_KINDS`)
- Modify: `.claude/skills/daa-extract/scripts/review_choices_1939.py:308-324` (`_span`, `_claims_conflict`)
- Modify: `.claude/skills/daa-extract/scripts/prepare_review_queue_1939.py:1086-1097` (`_claims_overlap`)
- Test: `.claude/skills/daa-extract/scripts/test_coverage_1939.py`, `test_review_choices_1939.py`, `test_prepare_review_queue_1939.py`

**Interfaces:**
- Produces: accepteret kandidat-skema der tillader `{candidate_id, postklasse, calamari_span, pdf_pages, raw_structure_bridge?}` ELLER `{…, approval: {"kind": "human_approved_span_v1", "calamari_excerpt_sha256": <64 hex>}}`. Mindst ét af de to felter kræves; begge samtidig er tilladt.
- Konstant `APPROVAL_KINDS = {"human_approved_span_v1"}` eksporteres fra `coverage_1939`.

- [ ] **Step 1: Skriv fejlende tests i `test_coverage_1939.py`**

```python
def _approval_candidate():
    return {
        "candidate_id": "human:1939-v2:span:" + "d" * 64,
        "postklasse": "nummereret",
        "calamari_span": {"char_from": 10, "char_to": 90},
        "pdf_pages": [500],
        "approval": {
            "kind": "human_approved_span_v1",
            "calamari_excerpt_sha256": "e" * 64,
        },
    }

def test_accepteret_kandidat_med_approval_uden_bro_accepteres():
    bundle = {"schema_version": 1, "source": _source(),
              "entries": [{"baseline_record_key": "k1", "status": "accepteret",
                           "candidate": _approval_candidate()}]}
    validate_coverage(bundle, expected_baseline_keys={"k1"})

def test_accepteret_kandidat_uden_bro_og_uden_approval_afvises():
    candidate = _approval_candidate(); del candidate["approval"]
    bundle = {"schema_version": 1, "source": _source(),
              "entries": [{"baseline_record_key": "k1", "status": "accepteret",
                           "candidate": candidate}]}
    with pytest.raises(ValueError):
        validate_coverage(bundle, expected_baseline_keys={"k1"})

def test_approval_med_ukendt_kind_eller_ekstra_felter_afvises():
    for corruption in (
        {"kind": "noget_andet", "calamari_excerpt_sha256": "e" * 64},
        {"kind": "human_approved_span_v1"},
        {"kind": "human_approved_span_v1", "calamari_excerpt_sha256": "E" * 64},
        {"kind": "human_approved_span_v1", "calamari_excerpt_sha256": "e" * 64,
         "ekstra": 1},
    ):
        candidate = _approval_candidate(); candidate["approval"] = corruption
        bundle = {"schema_version": 1, "source": _source(),
                  "entries": [{"baseline_record_key": "k1", "status": "accepteret",
                               "candidate": candidate}]}
        with pytest.raises(ValueError):
            validate_coverage(bundle, expected_baseline_keys={"k1"})
```

Genbrug filens eksisterende `_source()`-helper (findes den ikke, lav én med gyldige `edition`/hash-felter som i eksisterende tests).

- [ ] **Step 2: Kør tests — forventet FAIL** (`kræver raw_structure_bridge`-adfærd)

- [ ] **Step 3: Implementér i `coverage_1939.py`**

Tilføj øverst ved konstanterne:

```python
APPROVAL_KINDS = {"human_approved_span_v1"}
```

I `_validate_candidate` erstattes den ubetingede bro-blok (linjerne der starter med `bridge = _mapping(candidate.get("raw_structure_bridge"), "rå-bro")`) med:

```python
    bridge_value = candidate.get("raw_structure_bridge")
    approval_value = candidate.get("approval")
    if bridge_value is None and approval_value is None:
        raise ValueError("accepteret candidate kræver raw_structure_bridge eller approval")
    if bridge_value is not None:
        bridge = _mapping(bridge_value, "rå-bro")
        _nonempty_string(bridge.get("kind"), "rå-bro kind")
        raw_from = _nonnegative_int(bridge.get("raw_char_from"), "rå-bro raw_char_from")
        raw_to = _nonnegative_int(bridge.get("raw_char_to"), "rå-bro raw_char_to")
        if raw_from >= raw_to:
            raise ValueError("rå-bro skal have raw_char_from < raw_char_to")
        raw_digest = bridge.get("raw_excerpt_sha256")
        if not isinstance(raw_digest, str) or not _SHA256_RE.fullmatch(raw_digest):
            raise ValueError("raw_excerpt_sha256 skal være SHA-256 med små bogstaver")
    if approval_value is not None:
        approval = _mapping(approval_value, "approval")
        if set(approval) != {"kind", "calamari_excerpt_sha256"}:
            raise ValueError("approval har uautoriserede eller manglende felter")
        if approval.get("kind") not in APPROVAL_KINDS:
            raise ValueError("approval kind er ukendt")
        digest = approval.get("calamari_excerpt_sha256")
        if not isinstance(digest, str) or not _SHA256_RE.fullmatch(digest):
            raise ValueError("calamari_excerpt_sha256 skal være SHA-256 med små bogstaver")
```

- [ ] **Step 4: Skriv fejlende test i `test_review_choices_1939.py`** — to approval-kandidater uden bro må ikke kollidere på rå-dimensionen, men skal kollidere på calamari-overlap:

```python
def test_claims_conflict_haandterer_manglende_raa_bro():
    left = {"candidate_id": "a", "calamari_span": {"char_from": 0, "char_to": 10}}
    right = {"candidate_id": "b", "calamari_span": {"char_from": 20, "char_to": 30}}
    assert _claims_conflict(left, right) is False
    overlapping = {"candidate_id": "c", "calamari_span": {"char_from": 5, "char_to": 25}}
    assert _claims_conflict(left, overlapping) is True
```

(Importér `_claims_conflict` som de øvrige private helpers i filen — mønsteret findes allerede.)

- [ ] **Step 5: Implementér `_claims_conflict` i `review_choices_1939.py`**

Erstat `_span` + `_claims_conflict` med:

```python
def _claims_conflict(left: Mapping, right: Mapping) -> bool:
    if left["candidate_id"] == right["candidate_id"]:
        return True
    left_span, right_span = left["calamari_span"], right["calamari_span"]
    if (left_span["char_from"] < right_span["char_to"]
            and right_span["char_from"] < left_span["char_to"]):
        return True
    left_bridge = left.get("raw_structure_bridge")
    right_bridge = right.get("raw_structure_bridge")
    if left_bridge is not None and right_bridge is not None:
        if (left_bridge["raw_char_from"] < right_bridge["raw_char_to"]
                and right_bridge["raw_char_from"] < left_bridge["raw_char_to"]):
            return True
    return False
```

Bemærk: `_legacy_candidate_claim` (linje 347) bygger altid bro-claims fra legacy-felter — uændret.

- [ ] **Step 6: Spejl samme ændring i `prepare_review_queue_1939.py::_claims_overlap`** (samme kode-form som Step 5; funktionen hedder `_claims_overlap`). Tilføj tilsvarende test i `test_prepare_review_queue_1939.py` hvis `_claims_overlap` allerede har direkte tests — ellers dækkes den af Task 4.

- [ ] **Step 7: Kør de tre suiter — forventet PASS, ingen eksisterende tests knækket**

Run: `/usr/bin/python3 -m pytest test_coverage_1939.py test_review_choices_1939.py test_prepare_review_queue_1939.py -q -p no:cacheprovider`

- [ ] **Step 8: Commit** — `feat: tillad menneskegodkendt kandidat uden rå-bro (approval-kontrakt)`

---

### Task 2: Segment-offsets (`linjer`) + streng `_pages`

**Files:**
- Modify: `.claude/skills/daa-extract/scripts/segment.py` (`_segment_1939` linje 767-894, `_flush_1939` linje 365-391, `_unummereret_post_1939` linje 512-548)
- Modify: `.claude/skills/daa-extract/scripts/make_human_review_1939.py:58-66` (`_pages`)
- Test: `.claude/skills/daa-extract/scripts/test_segment_1939.py`, `test_make_human_review_1939.py`

**Interfaces:**
- Produces: hver post-dict fra `_segment_1939_v2` får nyt felt `linjer = {"fra": <int>, "til": <int>}` — halvåbent interval af kildelinje-indekser (indeks i den `lines`-liste segmenteringen fik). `fra` = postens første kildelinje (for nummererede: linjen med det trykte nummer), `til` = sidste tekstlinje + 1. Feltet er additivt; `raw_text`, `sider`, `lokal_id` osv. er UÆNDREDE.
- `_pages(value)` i make_human_review: `None`/`""` → `[]`; parsebar `"8"`/`"8-9"` → liste; alt andet → `ValueError("segmentpost sider er ugyldige")` (i dag: tavs `[]`).

- [ ] **Step 1: Fejlende test i `test_segment_1939.py`**

```python
def test_v2_poster_baerer_kildelinje_interval():
    lines = [
        "### PAGE 0001 ###",
        "Femte Slægtled.",
        "1. Anders Testesen, nævnes 1400, død",
        "1450 i Testby.",
        "2. Bo Testesen, nævnes 1401.",
    ]
    posts = segment._segment_1939_v2(lines, segment.UDGAVE_PROFILER["1939-v2"])
    nummererede = [p for p in posts if p.get("nr") is not None]
    assert all(isinstance(p.get("linjer"), dict) for p in nummererede)
    first = next(p for p in nummererede if p["nr"] == 1)
    assert lines[first["linjer"]["fra"]].startswith("1. Anders")
    assert first["linjer"]["til"] == first["linjer"]["fra"] + 2
```

Tilpas fixture-linjerne til hvad profilens regexer faktisk kræver — kig på eksisterende fixtures i `test_segment_1939.py` og genbrug deres form (post-regex kræver spærret navnesats; kopiér en eksisterende gyldig fixture og tilføj kun asserts på `linjer`). Wrap kaldet i `contextlib.redirect_stdout/stderr` som de eksisterende tests gør.

- [ ] **Step 2: Kør — forventet FAIL (`linjer` er None)**

- [ ] **Step 3: Implementér i `segment.py`**

I `_segment_1939` (linje 865-872), tilføj tracking-felter i `cur`:

```python
            cur = {
                ...eksisterende felter...,
                '_lines': [m.group(4)], '_pages': [page],
                '_linje_fra': i, '_linje_til': i + 1,
            }
```

I append-grenen (linje 879-880):

```python
        if cur is not None:
            cur['_lines'].append(line.strip())
            cur['_linje_til'] = i + 1
```

I `_flush_1939` (efter `cur['raw_text'] = …`):

```python
    cur['linjer'] = {'fra': cur.pop('_linje_fra'), 'til': cur.pop('_linje_til')}
```

(Guard: brug `cur.pop('_linje_fra', None)` og sæt kun `linjer` hvis værdien ikke er None, så `_flush` aldrig knækker på et tomt cur.)

I `_unummereret_post_1939`: registrér `foerste`/`sidste` tekstlinje-indeks i løkken (linje 525-534):

```python
    foerste = sidste = None
    for indeks in range(start, slut):
        line = lines[indeks]
        ... eksisterende continue-grene uændret ...
        tekstlinjer.append(line.strip())
        if foerste is None:
            foerste = indeks
        sidste = indeks
        ...
```

og tilføj i return-dict'en: `'linjer': {'fra': foerste, 'til': sidste + 1},`.

- [ ] **Step 4: Kør segment-suiterne — PASS + ingen regressioner**

Run: `/usr/bin/python3 -m pytest test_segment_1939.py test_segment.py test_segment_slaegtled.py -q -p no:cacheprovider`

- [ ] **Step 5: Empirisk sandhedstjek mod den rigtige kilde (ikke en committet test)**

Kør et engangs-script (må IKKE committes, læg det i `/tmp` eller kør inline) der segmenterer `work_1939_stamtavle/full_ocr_calamari_r6_clean.txt`, bygger char-offsets af linjerne (`offsets[i] = sum(len(l)+1 for l in lines[:i])`), og verificerer for alle 502 poster at `source_text[char_from:char_to]` starter med postens første kildelinje. Rapportér antal OK/FEJL i task-outputtet. Alle skal være OK; hvis ikke, undersøg før commit.

- [ ] **Step 6: Fejlende test for streng `_pages` i `test_make_human_review_1939.py`**

```python
def test_pages_afviser_uparsebar_sideangivelse():
    assert make_human_review_1939._pages(None) == []
    assert make_human_review_1939._pages("8") == [8]
    assert make_human_review_1939._pages("8-10") == [8, 9, 10]
    with pytest.raises(ValueError):
        make_human_review_1939._pages("ukendt")
```

- [ ] **Step 7: Implementér** — i `_pages`: behold `None`/tom-streng → `[]`; ved `ValueError` fra `int(...)` på ikke-tom værdi: `raise ValueError("segmentpost sider er ugyldige")`. Kør suiten (generatorens fulde flow mod fixtures skal stadig bestå — hvis en fixture har uparsebar `sider`, ret fixturen eller undersøg).

- [ ] **Step 8: Commit** — `feat: bevar kildelinje-interval per 1939-post og stram sideparsning`

---

### Task 3: Adapteren `anchor_review_choices_1939.py`

**Files:**
- Create: `.claude/skills/daa-extract/scripts/anchor_review_choices_1939.py`
- Test: `.claude/skills/daa-extract/scripts/test_anchor_review_choices_1939.py`

**Interfaces:**
- Consumes: Task 1-kontrakten (`APPROVAL_KINDS`, approval-kandidater), Task 2-felterne (`post["linjer"]`), eksisterende `validate_choice_export` (`review_choices_1939.py:178`), `sample_auto_resolved` (`review_queue_1939.py:104`), `align_renditions`, canonical `extract_rendition_occurrences`, `segment._segment_1939_v2`, generatorens text-anchor-algoritme og et obligatorisk komplet `--base-evidence` med eksakt source/baseline-dækning.
- Produces (public API brugt af Task 4-5 og CLI):

```python
def build_human_anchored_candidates(
    choices: dict[str, dict],          # fra validate_choice_export
    audit_keys: set[str],
    classifications: dict[str, dict],  # queue-manifest entries by key
    baseline_bytes: bytes,
    calamari_text: str,
    raw_text: str,
    calamari_occurrences: dict,        # occurrence-manifest (indlæst JSON)
    raw_occurrences: dict,
    profile_version: str,
    expected_source: dict,
    calamari_first_pdf_page: int,
) -> dict:
    """Returnerer {"anchored": {candidate_id: wrapper}, "evidence_entries": [...],
    "parked": [{"baseline_record_key", "reason_code", "reason_da", "candidate_id"}]}"""

def compose_human_evidence_bundle(
    base_evidence: dict,
    human_entries: list[dict],
    source: dict,
    baseline_keys: set[str],
    calamari_text: str,
    raw_text: str,
) -> dict:
    """Returnerer komplet valideret evidence-bundle."""
```

  - wrapper-format (præcis det `_anchored_index`/`_selected_candidate` i `review_choices_1939.py:275-305` kræver): `{candidate_id: {"baseline_record_key": key, "candidate": {…accepteret kandidat-skema…}}}`.
  - Human-entry-format: som dual-evidence-entries: `{"baseline_record_key", "candidates": [kandidat], "conflicts": [], "source_blockers": [], "rule_id": "human_anchor_v1", "positive_provenance": {"kind": "human_approved_span_v1", "baseline_record_key", "candidate_id"}}`. CLI'ens `--evidence-out` er ikke denne fragmentliste, men et komplet bundle hvor hver human-entry kun erstatter samme evidensfrie base-key; øvrige base-entries bevares.
  - CLI: `--choices --queue-manifest --baseline --calamari --raw --calamari-occurrences --raw-occurrences --base-evidence --wrapper-out --evidence-out --report-out --rewritten-choices-out` (alle out eksklusive; source, fuld dækning og global effektiv kandidat-/span-injektivitet valideres før outputs åbnes).

**Algoritme (fail-closed, deterministisk):**

1. Kandidat-id-typebestemmelse for hvert manuelt `human_selected_candidate` (spring `audit_keys` og andre outcomes over):
   - `presentation:{profil}:text-anchor:<digest>` → genfind baseline-narrativets entydige forekomst i `calamari_text` (`calamari_text.find(nar)` én gang, `find(nar, start+1) < 0`), genberegn `sha256(f"{profil}\0{key}\0{start}\0{end}")`; mismatch → park `text_anchor_not_reproducible`.
   - `presentation:{profil}:post:<indeks>` → `posts[indeks]` (indeks ude af range → park `parser_post_not_found`).
   - alt andet → poster hvis `candidate_id`/`lokal_id` matcher; 0 → `parser_post_not_found`, >1 → `parser_post_ambiguous`.
   - For post-kandidater: span fra `post["linjer"]` via offsets-tabel (`offsets[i] = kumulativ længde af linjer + 1 pr. linje`); mangler `linjer` → park `parser_post_not_found`.
2. Verbatim: `excerpt = calamari_text[char_from:char_to]`; tom eller whitespace-kun → park `span_verbatim_mismatch`. `calamari_excerpt_sha256 = sha256(excerpt.encode("utf-8"))`.
3. Kandidat-id: `f"human:{profil}:span:" + sha256(f"{profil}\0{char_from}\0{char_to}\0{excerpt_sha}".encode()).hexdigest()`.
4. PDF-sider: record-sider parses altid og skal være positive. Ved entydigt dækkende Calamari-occurrence kræves `record_pages ⊆ occurrence.pdf_pages`, og hele den grove occurrence-side-liste bevares; mismatch parkeres som `pdf_pages_mismatch`. Uden dækkende occurrence bruges de validerede record-sider.
5. Rå-bro: hvis den entydigt dækkende Calamari-occurrence har et invariant par i `align_renditions(...)["pairs"]` → bro = den parrede rå-occurrences span, `kind = "human_approved_occurrence_pair_v1"`, `raw_excerpt_sha256 = sha256(raw_text[raw_from:raw_to])`. Ellers ingen bro. `approval`-feltet sættes ALTID på menneskekandidater (også med bro).
6. Globale kontroller (over auto-kandidater fra `classifications[queue_class=="auto_resolved"]["candidate"]` + alle menneskekandidater):
   - samme kandidat-id valgt af to poster → park begge `candidate_claimed_by_multiple_records`;
   - calamari-span-overlap mod auto → park `overlaps_automatic_candidate`;
   - calamari-span-overlap indbyrdes → park begge `overlaps_other_manual_choice`;
   - rå-span-overlap (kun broede) tilsvarende.
7. Output: kun kandidater der består ALLE kontroller kommer i wrapper og erstatter deres egen evidensfrie slot i det komplette composed bundle; alt andet i `parked`, mens base-entryen bevares. Base-source/dækning, eksisterende positiv evidens og den samlede retained-auto + human-injektivitet er hard failures.

- [ ] **Step 1: Skriv testfil med syntetisk mini-fixture.** Byg i testen en lille kilde (2 sider, 3 poster m. `linjer`), occurrence-manifester med spans der dækker posterne, alignment-venlige occurrences (genbrug fixture-mønstre fra `test_dual_rendition_evidence_1939.py` for manifest-form). Test mindst:

```python
def test_parserpost_valg_faar_span_og_approval()
def test_text_anchor_valg_genberegnes_og_forankres()
def test_valg_med_alignet_occurrence_faar_raa_bro()
def test_valg_uden_alignment_faar_kun_approval()
def test_overlap_med_automatisk_kandidat_parkeres()
def test_samme_kandidat_to_poster_parkerer_begge()
def test_wrapper_kandidater_bestaar_validate_coverage()
```

- [ ] **Step 2: Kør — FAIL (modul findes ikke)**
- [ ] **Step 3: Implementér modulet** (ét fil-scope, følg eksisterende scripts' stil: `_mapping`/`_nonempty`-helpers, ingen I/O i kernefunktionen, CLI i `main()` med eksklusive outputs og hash-gate først).
- [ ] **Step 4: Kør — PASS**
- [ ] **Step 5: Integrationstest i samme testfil: hele kæden**

```python
def test_kaede_choices_til_accepteret_decision():
    # build_human_anchored_candidates -> wrapper
    # convert_review_choices(choices, wrapper, classifications, audit_keys)
    # assert decisions indeholder {"status": "accepteret", "candidate_id": <human:...>}
```

- [ ] **Step 6: Kør alle scripts-suiter** (`/usr/bin/python3 -m pytest test_*.py -q -p no:cacheprovider`) — ingen regressioner.
- [ ] **Step 7: Commit** — `feat: efterforankr menneskeark-valg til source-bound kandidater`

---

### Task 4: Task 6-sømmen — evidensjoin accepterer composed human-evidence

**Files:**
- Modify: `.claude/skills/daa-extract/scripts/prepare_review_queue_1939.py` (`_PROVENANCE_KINDS`-konstanten, `_source_bound_evidence_entries` linje 731-810, `_joined_accepted_candidate` linje 1010-1083)
- Test: `.claude/skills/daa-extract/scripts/test_prepare_review_queue_1939.py`

**Interfaces:**
- Consumes: Task 3's komplette composed evidence-bundle samt Task-5-filen med præcis `{decisions, audit_results}` som `--review`.
- Produces: `--evidence` kan indeholde entries med `rule_id: "human_anchor_v1"`, `positive_provenance.kind: "human_approved_span_v1"` og approval-kandidater (uden bro); `_joined_accepted_candidate` joiner accepterede choice-beslutninger mod dem. Klassifikator-adfærd for auto-sporet er UÆNDRET: `human_approved_span_v1`-evidens må ALDRIG gøre en post `auto_resolved` — den er kun join-grundlag for menneskebeslutninger. Output er publikationskø/-rapport og højst review-/fil-GO.

- [ ] **Step 1: Læs `_PROVENANCE_KINDS`, `_source_bound_evidence_entries` og `_validate_one_candidate_with_existing_contract` (`review_queue_1939.py:339`) og kortlæg præcis hvor kind- og kandidatformen håndhæves.**
- [ ] **Step 2: Fejlende tests:** (a) evidence-entry med approval-kandidat + `human_approved_span_v1`-proveniens validerer; (b) `_joined_accepted_candidate` joiner en accepteret beslutning mod den; (c) klassifikatoren (`classify_review_entries`/`_classify_one`) gør IKKE posten `auto_resolved` på human-evidens — den forbliver `human_required`.
- [ ] **Step 3: Implementér minimalt** — udvid kind-allowlisten og kandidatvalideringen dér hvor den kræver bro (genbrug Task 1-kontrakten frem for at duplikere den; hvis valideringen delegerer til `validate_coverage`, er det meste gratis). Gate i klassifikatoren: `rule_id`/proveniens-kind `human_*` ekskluderes eksplicit fra auto-reglerne.
- [ ] **Step 4: Kør suiten — PASS, ingen regressioner (særligt `test_review_queue_1939.py`).**
- [ ] **Step 5: Commit** — `feat: lad publikationsgatens evidensjoin acceptere menneskeforankret evidens`

---

### Task 5: Reproducerbar kladde-genindlejring i generatoren

**Files:**
- Modify: `.claude/skills/daa-extract/scripts/make_human_review_1939.py` (main, `_review_decisions`, `_assert_sourceless_review_is_unreviewed`-kaldsstedet linje 327-337)
- Test: `.claude/skills/daa-extract/scripts/test_make_human_review_1939.py`

**Interfaces:**
- Consumes: `validate_choice_export(root, source, keys, include_context=True)` → `{"choices": {key: choice}, "final_legacy_entries": …}`.
- Produces: `--review` accepterer NU OGSÅ en browser-choice-eksport. Detektion (samme som `_review_state` i `prepare_review_queue_1939.py:1187-1192`): root har `source` OG (`exported_at` i root ELLER en entry har `outcome`). I så fald: validér med `validate_choice_export` mod source-manifestet, og byg decisions-dict af choice-entries (kun browser-felterne `baseline_record_key, outcome, candidate_id, duplicate_of_baseline_record_key, decided_at, reason`) + legacy-entries som hidtil. Spring `validate_review_template`-kaldet over for choice-eksporter (det afviser `outcome`-felter). Legacy-template-stien er UÆNDRET.

- [ ] **Step 1: Fejlende test:** generér HTML med en syntetisk choice-eksport som `--review` (fixture-mønstrene for baseline/queue/source findes allerede i testfilen); assert at HTML'ens `const DATA`-payload indeholder de indlejrede decisions med `outcome`, og at kaldet IKKE rejser `review har uautoriserede felter`.
- [ ] **Step 2: Kør — FAIL (ValueError).**
- [ ] **Step 3: Implementér detektions-grenen i `main()`** før `validate_review_template`-kaldet. Choice-decisions skal bestå UI'ens `validateDecisionState` (browser-felter alene — det gjorde run-o-formatet allerede).
- [ ] **Step 4: Regressionstest:** legacy unreviewed-template virker stadig; en eksport med forkert source-hash afvises stadig.
- [ ] **Step 5: Kør suiten — PASS. Commit** — `feat: genindlejr eksporteret 1939-kladde reproducerbart i nyt menneskeark`

---

### Task 6: UI — per-post-karantæne + ærlig promoterbarheds-mærkning

**Files:**
- Modify: `.claude/skills/daa-extract/scripts/human_review_1939_ui.js` (`restoreOrInitialize` linje 250-321, `overlayCachedDecisions` linje 222-248, `persist` linje 355-365, `renderCandidate` linje 633-705, `decisionStatusText` linje 719-…, eksport-handleren)
- Test: `web/src/humanReview1939Ui.test.ts`

**Interfaces:**
- Consumes: model-data uændret; `candidate.details || candidate.accepted_review_details` = source-bound evidens.
- Produces:
  1. **Karantæne:** ugyldige POSTER i den gemte kladde flyttes til `state.quarantined = {key: {entry, reason}}` i stedet for at `blockRecovery` rydder alt. Kilde-/schema-mismatch for HELE kladden blokerer fortsat som i dag. `persist()` round-tripper karantænen under nøglen `quarantined` i storage-payloaden (og `restoreOrInitialize` genindlæser den). Hoved-eksporten er UÆNDRET skemaren (ingen nye root-felter); en separat knap `Eksportér karantæne` downloader `1939-review-karantaene.json` når karantænen er ikke-tom. Banner viser antal + årsag.
  2. **Mærkning:** i `renderCandidate`: kandidater med `candidate.details || candidate.accepted_review_details` får linjen `Forankret kildeevidens — kan accepteres direkte.`; øvrige får `Læsehjælp — dit valg gemmes som redaktionel observation og efterforankres maskinelt.` `decisionStatusText` spejler samme skel.

- [ ] **Step 1: Fejlende vitest-tests:**

```typescript
it('sætter en enkelt ugyldig kladdepost i karantæne uden at miste de øvrige', …)
it('round-tripper karantænen gennem persist og genindlæsning', …)
it('holder hoved-eksporten skemaren og eksporterer karantænen separat', …)
it('mærker læsehjælps-kandidater og forankrede kandidater forskelligt', …)
```

Genbrug testfilens eksisterende `init`-harness og storage-mock.

- [ ] **Step 2: Kør — FAIL.** Run: `cd web && npx vitest run src/humanReview1939Ui.test.ts`
- [ ] **Step 3: Implementér.** Karantæne-semantik: i `restoreOrInitialize`s catch omkring `overlayCachedDecisions`/`validateDecisionState` — validér i stedet PR. ENTRY (try/catch pr. nøgle i `overlayCachedDecisions`); fang også kandidat-ejerskabskonflikter pr. entry (rækkefølge: model-decisions først, cache-entries derefter i sorteret nøgleorden, så udfaldet er deterministisk). Bevar `blockRecovery` for: korrupt JSON, schema-/source-mismatch, ugyldig beslutningsbeholder, ugyldige MODEL-decisions.
- [ ] **Step 4: Kør — PASS, alle 80 eksisterende tests grønne.**
- [ ] **Step 5: Commit** — `feat: karantæne i stedet for totalblokering + ærlig kandidatmærkning i 1939-arket`

---

### Task 7: Real-data-replay, dokumentation og fuld verifikation

**Files:**
- Modify: `.claude/skills/daa-extract/SKILL.md` (afsnittet "Privat 1939-undtagelseskø", linje 267-271 + 310-315)
- Modify: `docs/changelog.md`, `docs/decisions.md`
- Ingen commits af `work/`-filer.

**Steps:**

- [ ] **Step 1: Real-data-replay (rapportér tal, commit intet under `work/`):** kør adapteren mod den rigtige eksport `/Users/johanreventlow/Downloads/1939-review-kladd(3).json` + `work/task19-1939-pilot/review-queue-manifest-v2-run-e.json` + occurrences run-f + det komplette source-bundne `dual-evidence-v2-run-f.json`; derefter `prepare_coverage_1939.py --choices-to-decisions … --anchored-candidates <ny wrapper>`. Facit: 25/25 manuelle valg → `accepteret`, heraf 13 med rå-bro og 12 approval-alene; 0 fejlmatch, fem `no_candidate_fits` → `menneskeark`, 5/5 `audit_confirmed`.
- [ ] **Step 2: Generér nyt menneskeark med `--review <eksporten>`** (Task 5-vejen) til `work/task19-1939-pilot/menneskeark-undtagelsesko-v3-run-a.html` og verificér at alle 35 valg er indlejret (samme kontrol som reviewets: udtræk `const DATA`, sammenlign felt for felt).
- [ ] **Step 3: SKILL.md:** dokumentér den faktiske sekvens: adapter med `--base-evidence` → Task-5 `{decisions,audit_results}` → `prepare_review_queue_1939.py --evidence <composed> --review <Task-5>`. Læs parkeringsrapporten. Der findes ingen approval-capable privat coverage-materializer; stop ved review-/fil-GO, og kræv separat design/godkendelse/replay for ny materialisering.
- [ ] **Step 4: `docs/changelog.md`** (dateret entry: reviewfund + adapter + komplet composition implementeret) og **`docs/decisions.md`** (beslutning: approval-kontrakten/rå-bro valgfri for menneskevalg; komplet base-composition; fil-GO-grænse; backlog: slutark-occurrence-resegmentering udskudt med begrundelse).
- [ ] **Step 5: Fuld verifikation:** alle scripts-suiter + `cd web && npx vitest run src/humanReview1939Ui.test.ts` + `npm run build -w web` er IKKE nødvendig (ingen web-app-ændringer ud over testfilen). Rapportér samlede tal.
- [ ] **Step 6: Commit** — `docs: adapter-workflow, changelog og beslutninger for 1939-efterforankring`

---

## Self-review (udført ved planskrivning)

- Spec-dækning: K1→Task 1+3+4, K2→Task 5, K3→Task 6, V1→Task 6, V2→Task 2+3, V3→approval-kontrakt (Task 1) + backlog-notat (Task 7), V4→Task 3-algoritmen, M1→Task 2. ✓
- Ingen placeholder-mønstre; alle kontrakt-ændringer har konkret kode eller præcis lokation + form. ✓
- Typekonsistens: wrapper-format matcher `_anchored_index`/`_selected_candidate`; evidence-entry-format matcher `_joined_accepted_candidate`s krav (kandidatliste + positive_provenance med kind/baseline_record_key/candidate_id). ✓
