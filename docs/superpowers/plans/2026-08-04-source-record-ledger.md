# Source-record-ledger Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Gør en eksplicit accepteret, privat segmentering til validerbare source records med opaque keys, så profile-pinnede batches kan forberedes uden at gætte identitet.

**Architecture:** `evidence_contract.py` bliver den fælles fremmednøgle- og unikhedsvagt. En ny, filbaseret ledgeradapter mint'er kun nye keys for menneskeligt accepterede rækker og afviser drift for kendte acceptancer. Den producerer et evidence bundle; hverken adapteren eller planen udfører modelkald, database- eller canonical mutationer.

**Tech Stack:** Python 3, `pytest`, JSON og eksisterende `evidence_contract` / `evidence_extract`.

## Global Constraints

- Record keys er opaque UUID-baserede og må aldrig udledes af navn, side, nummer, OCR-position, teksthash eller rækkefølge.
- Input kræver eksplicit menneskelig accept; uafklaret eller drift går til fejl, ikke til automatisk re-anchoring.
- Ledger, review-filer, bundles og persontekst ligger kun i ignoreret `work/`.
- Source editions er isolerede. Ingen database, netværk eller modelkaldes.
- Test først: hver ny adfærd skal beviseligt fejle før implementationen skrives.

---

### Task 1: Luk source-record- og anchor-krydshenvisninger i kontrakten

**Files:**

- Modify: `.claude/skills/daa-extract/scripts/evidence_contract.py`
- Modify: `.claude/skills/daa-extract/scripts/test_evidence_contract.py`

**Interfaces:**

- Consumes: et bundle med `source_records` og `source_record_anchor_events`.
- Produces: `validate_bundle(bundle) -> None`, som afviser tomme/duplikerede source-record-id'er og record keys samt anchors til ikke-eksisterende records.

- [ ] **Step 1: Skriv tre fejlede tests**

```python
def test_bundle_rejects_anchor_to_unknown_source_record():
    bundle = valid_bundle()
    bundle["source_record_anchor_events"] = [accepted_anchor("missing")]
    with pytest.raises(ContractError, match="unknown source record"):
        validate_bundle(bundle)

def test_bundle_rejects_duplicate_source_record_key():
    bundle = valid_bundle(source_records=[record("a", "record-same"), record("b", "record-same")])
    with pytest.raises(ContractError, match="duplicate source record key"):
        validate_bundle(bundle)
```

- [ ] **Step 2: Kør kun de nye tests og bekræft RED**

```bash
/usr/bin/python3 -m pytest .claude/skills/daa-extract/scripts/test_evidence_contract.py -k "unknown_source_record or duplicate_source_record_key" -q
```

Forventet: fejl, fordi den nuværende validator ikke validerer `source_records` eller anchorens source-record-id.

- [ ] **Step 3: Implementér den minimale validator**

```python
source_record_ids: set[str] = set()
record_keys: set[str] = set()
for record in bundle["source_records"]:
    record_id = _require(record.get("id"), "source record id")
    record_key = _require(record.get("record_key"), "source record key")
    if record_id in source_record_ids or record_key in record_keys:
        raise ContractError("duplicate source record")
    source_record_ids.add(record_id)
    record_keys.add(record_key)
```

Kontrollér derefter i anchor-løkken, at `source_record_id` findes i `source_record_ids`.

- [ ] **Step 4: Kør fokuseret og fuld kontrakttest**

```bash
/usr/bin/python3 -m pytest .claude/skills/daa-extract/scripts/test_evidence_contract.py -q
```

Forventet: alle tests består.

- [ ] **Step 5: Commit**

```bash
git diff --check
git branch --show-current
git add .claude/skills/daa-extract/scripts/evidence_contract.py .claude/skills/daa-extract/scripts/test_evidence_contract.py
git commit -m "fix: validate source record anchors"
```

### Task 2: Implementér privat, append-only source-record-ledger

**Files:**

- Create: `.claude/skills/daa-extract/scripts/source_record_ledger.py`
- Create: `.claude/skills/daa-extract/scripts/test_source_record_ledger.py`

**Interfaces:**

- Consumes: `materialize(review, ledger)`, hvor `review` har `source_id`, `rendition_id`, `rendition_sha256`, `extraction_run_id` og `records`. Hver record har `acceptance_id`, `record_kind`, `decision_status`, `reviewed_by`, `decision_version`, `verbatim_text` og `span` med `page_from`, `page_to`, `char_from`, `char_to` og `bbox`.
- Produces: `(next_ledger, evidence_bundle)`; caller skriver først resultatet efter en succesfuld validering.
- Reuses: `mint_record_key()` og `validate_bundle()` fra `evidence_contract`.

- [ ] **Step 1: Skriv RED-test for mintning og idempotens**

```python
def test_materialize_mints_opaque_key_once_and_is_idempotent():
    first_ledger, first_bundle = materialize(review(), empty_ledger())
    second_ledger, second_bundle = materialize(review(), first_ledger)
    assert first_ledger == second_ledger
    assert first_bundle == second_bundle
    assert first_bundle["source_records"][0]["record_key"].startswith("record-")
```

- [ ] **Step 2: Kør den nye test og bekræft RED**

```bash
/usr/bin/python3 -m pytest .claude/skills/daa-extract/scripts/test_source_record_ledger.py -q
```

Forventet: importfejl, fordi modulet endnu ikke findes.

- [ ] **Step 3: Implementér minimal materialisering**

```python
def materialize(review: Mapping[str, Any], ledger: Mapping[str, Any]) -> tuple[dict[str, Any], dict[str, Any]]:
    validated = _validate_review(review)
    existing = _index_ledger(ledger)
    next_entries = []
    for accepted in validated:
        prior = existing.get(accepted["acceptance_id"])
        entry = prior if prior is not None else {
            "acceptance_id": accepted["acceptance_id"],
            "record_key": mint_record_key(),
            "immutable": _immutable_fingerprint(accepted),
        }
        if prior is not None and prior["immutable"] != _immutable_fingerprint(accepted):
            raise LedgerError("accepted record drift")
        next_entries.append(entry)
    next_ledger = {"schema_version": "1.0", "entries": sorted(next_entries, key=lambda entry: entry["acceptance_id"])}
    bundle = _bundle_from(validated, next_ledger)
    validate_bundle(bundle)
    return next_ledger, bundle
```

Generér deterministiske event- og occurrence-id'er fra `acceptance_id`; mint kun `record_key` med `mint_record_key`. Indsæt ingen record ved andet end `decision_status == "accepted"`.

- [ ] **Step 4: Tilføj og kør RED/GREEN-tests for fail-closed drift**

```python
def test_materialize_rejects_changed_text_for_known_acceptance_without_mutating_ledger():
    ledger, _ = materialize(review(), empty_ledger())
    ledger_before = copy.deepcopy(ledger)
    with pytest.raises(LedgerError, match="drift"):
        materialize(review(verbatim_text="ændret"), ledger)
    assert ledger == ledger_before
```

Tilføj følgende yderligere fail-closed tests:

```python
def test_materialize_rejects_duplicate_acceptance_id():
    with pytest.raises(LedgerError, match="duplicate acceptance"):
        materialize(review(records=[accepted("a"), accepted("a")]), empty_ledger())

def test_materialize_rejects_nonaccepted_record():
    with pytest.raises(LedgerError, match="accepted"):
        materialize(review(records=[accepted("a", decision_status="proposed")]), empty_ledger())

def test_materialize_rejects_existing_acceptance_in_another_edition():
    ledger, _ = materialize(review(source_id="2018-20"), empty_ledger())
    with pytest.raises(LedgerError, match="drift"):
        materialize(review(source_id="1939"), ledger)

def test_materialize_returns_a_contract_valid_bundle():
    _, bundle = materialize(review(), empty_ledger())
    assert validate_bundle(bundle) is None
```

- [ ] **Step 5: Kør fokuserede og berørte fulde tests**

```bash
/usr/bin/python3 -m pytest .claude/skills/daa-extract/scripts/test_source_record_ledger.py .claude/skills/daa-extract/scripts/test_evidence_contract.py .claude/skills/daa-extract/scripts/test_evidence_extract.py -q
```

- [ ] **Step 6: Commit**

```bash
git diff --check
git branch --show-current
git add .claude/skills/daa-extract/scripts/source_record_ledger.py .claude/skills/daa-extract/scripts/test_source_record_ledger.py
git commit -m "feat: add fail-closed source record ledger"
```

### Task 3: Ret pilotgaten til den implementerede adapter

**Files:**

- Modify: `docs/superpowers/reviews/2018-evidence-pilot.md`

**Interfaces:**

- Consumes: Task 2's private source-record bundle.
- Produces: en korrekt status: klar til privat accept/mintning, men ikke til modeludtræk før manifestets records er accepteret og profile-pinnet.

- [ ] **Step 1: Opdatér den konkrete gate**

Erstat den nuværende GO-tekst med, at locatorerne alene ikke er `record_key`, og at Step 3 først åbner efter Task 2 har materialiseret og valideret den private acceptance-ledger. Bevar privacy-policyen og påstanden om ingen modelkørsel.

- [ ] **Step 2: Verificér rapportens afgrænsning og diff**

```bash
git diff --check
rg -n "record_key|modelkørsel|GO for Task 16" docs/superpowers/reviews/2018-evidence-pilot.md
```

Forventet: rapporten påstår ikke længere, at locatorer alene åbner modelkørslen.

- [ ] **Step 3: Commit**

```bash
git branch --show-current
git add docs/superpowers/reviews/2018-evidence-pilot.md
git commit -m "docs: correct 2018 evidence pilot gate"
```

## Verifikation før overlevering

```bash
/usr/bin/python3 -m pytest .claude/skills/daa-extract/scripts/test_source_record_ledger.py .claude/skills/daa-extract/scripts/test_evidence_contract.py .claude/skills/daa-extract/scripts/test_evidence_extract.py -q
git diff --check
git status --short
```

Bekræft særskilt, at kun trackede script-, test- og rapportfiler committes; alle reviews, ledgerdata, bundles og persontekst forbliver under ignoreret `work/`.
