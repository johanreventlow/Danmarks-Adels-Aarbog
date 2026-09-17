# Trin 4 · klausul-projektion: udgaveneutral delta-afstemning af 4.1c — implementeringsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Gør det muligt at bevise, at én `clause_evidence`-kørsel (4.1c) skrev præcis manifestets klausuler og intet andet, så spec §11.1's krav om en klausul-projektion er opfyldt før 4.1c's prod-GO (#195).

**Architecture:** En læse-kun SQL-projektion (parameteriseret på `source_id`, ingen tekst forlader databasen) tages før og efter apply. En Python-komparator uden databaseadgang sammenholder de to projektioner med det autoriserede manifest og svarer `match` eller NO-GO med en fejlkode. Tjekket er et *delta*-bevis: det kender ingen udgave, fase eller historik og importerer intet fra den 1939-låste reconciler på `codex/finish-156-158`.

**Tech Stack:** PostgreSQL 17 (ren SQL, `extensions.digest`), Python 3.9+ kun standardbibliotek (pytest til tests), R + DBI/RPostgres (integrationstest), GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-09-06-trin4-fortolkningskaede-og-klausulgranularitet-design.md` §4.1.4-4.1.6 og §11.1. Afgørelsen (vej C) står i `docs/decisions.md` (Task 4) og i issue #195. Fortolknings-projektionen er udskudt til #196.

## Global Constraints

- **Ingen kildetekst forlader databasen.** Projektionen hasher `verbatim_text` og `narrative.tekst` i SQL med `extensions.digest(convert_to(…,'UTF8'),'sha256')`. Ingen tekst i JSON, logs, rapporter, commit-beskeder eller issues.
- Projektioner og rapporter fra rigtige baser er private: `~/.private/…`, mapper 0700, filer 0600, aldrig committet. Test-fixtures er syntetiske.
- Komparatoren åbner aldrig en database. Projektionen kører kun i en `READ ONLY` + `REPEATABLE READ`-transaktion og håndhæver det selv (fejlkode `CLAUSE_PROJECTION_NOT_READ_ONLY` / `CLAUSE_PROJECTION_NOT_REPEATABLE_READ`).
- Udgaveneutral: ingen `1939`/`2018`-strenge, ingen fase-id'er, ingen import fra `reconcile_evidence_phase_gate.py` eller andre `*_1939_v50`-scripts.
- Sammenlign **mængder og indhold, aldrig antal** (memory: drift-guard skal sammenligne mængde). Den kanoniske neutralitet er en indholds-hash pr. tabel, ikke `count(*)`.
- Sortering i SQL: `ORDER BY … COLLATE "C"` på tekstnøgler (CI kører `en_US`). Komparatoren sammenligner desuden kanonisk sorteret, så rækkefølge aldrig bærer beviset.
- Python skal køre på `/usr/bin/python3` 3.9 (runbookens tolk) og CI's 3.11: `from __future__ import annotations`, ingen `match`, ingen runtime-`X | Y`.
- Ingen prod-handling i denne plan. Rehearsal kun mod lokal restore. Prod-kørsel af 4.1c kræver sin egen GO.
- Ingen ny DDL, ingen ændring af `schema.sql`/`db-migrations.sql`/`db-rls.sql`.
- Commits: ét pr. task, dansk Conventional Commit, ingen push. Gren `feat/148-klausul-projektion` (worktree `.claude/worktrees/klausul-projektion`).

## Roadmappens seks adgangskrav

1. **Roadmapmål:** trin 4, #148 → prod-forudsætning for 4.1c (#195).
2. **Værdikædeled:** afstemning af `klausulobservationer` efter prod-skrivning.
3. **Generel/profil/legacy:** generel (udgaveneutral); ingen profil.
4. **Redaktionel værdi:** projektejeren kan give prod-GO til klausulkørslen med et mekanisk bevis for, at intet andet end klausulerne ændrede sig.
5. **Bevis:** pytest-cases for hver fejlkode; CI-integration med match, manipuleret projektion (NO-GO) og ikke-read-only-afvisning; rehearsal mod restore af prod-dump 2026-09-17: `match` med 591 records / 868 klausuler, og to ægte negative mutationer giver NO-GO.
6. **Erstatter:** 4.1c-rehearsalens antal-baserede `kanonisk()`-hash som neutralitetsbevis.

## Vigtige fakta (målt 2026-09-17 på restore `daa_trin4_rehearsal_20260917141446` = prod-skema, 0 klausuler)

| Måling (source 1 = 2018-20) | Værdi |
| --- | --- |
| `source_record` | 591 |
| accepterede ankre | 591 |
| `narrative_record_publication`-rækker (alle statusser) | 587 (541 `published`, 46 `draft`) |
| bundne narrativer / personer | 587 / 587 |
| `person_post`-observationer / klausuler | 591 / 0 |
| `extensions.digest(text,text)` findes | ja |
| Indholds-hash over 8 tabeller (person 1811, fact 7197, assertion 9306, conclusion 9217, narrative 1169, relation 2035, family_member 2258, ikke-klausul-observationer 1488) | 0,5 s |

4.1c-manifestet: `~/.private/148c-manifest-20260910190838.json`, `manifest_content_sha256` `0b31c5a2…`, 591 operationer, 868 klausuler, source 1.

**Rehearsal-basen.** Dumpet `daa-prod-20260917141330.dump` er backuppen taget *før* trin 4's DDL-deploy (0 `write_clause_evidence` i dumpets TOC). Restoren `daa_trin4_rehearsal_20260917141446` er dumpet + `db-migrations.sql` + `db-rls.sql` i den rækkefølge, prod fik dem 2026-09-17, verificeret med db-verify og kontrakttests. Den bruges som **template** (`createdb -T`) og må ikke droppes, før Task 5 er færdig.

**Writer-profilrækken** `private.reimport_writer_profile` for `(1, 'daa-2018-20-clause-evidence-v1')` findes **ikke** i den migrerede base (målt: 0) og dermed heller ikke i prod. 4.1c's dry-run-script (`~/.private/148-rehearsal-scripts/03-clause-dryrun.R`) indsætter den. Rækken ligger uden for projektionen (privat konfiguration), så den skal indsættes *før* før-projektionen, ellers ændrer intet sig — men prod-kørslen af 4.1c skal kende dette skridt.

Writerens dispositionsregel (`private.write_clause_evidence` i `db-migrations.sql`, søg `v_disposition:=CASE`): `classification='structural_header'` → `strukturel`; ellers ikke-tomme `flags` → `maskinelt_flagget`; ellers `afventer_fortolkning`. Version 1.

Klausulrækkens felter i databasen: `char_from`/`char_to` = rendition-absolutte (manifestets `rendition_char_from`/`rendition_char_to`); `post_char_from`/`post_char_to` = helpost-relative (manifestets `char_from`/`char_to`).

## Filoversigt

- Create: `.claude/skills/daa-extract/scripts/compare_clause_evidence_projection.py` — komparator + CLI.
- Create: `.claude/skills/daa-extract/scripts/test_compare_clause_evidence_projection.py` — pytest.
- Create: `.claude/skills/daa-extract/scripts/clause_evidence_projection.sql` — læse-kun projektion.
- Modify: `tests/integration/test-reimport-clause-evidence.R` — før/efter-projektion + komparator i CI.
- Modify: `.github/workflows/ci.yml` — pytest-fillisten (jobbet `evidence contract · pytest`).
- Modify: `docs/runbooks/evidence-import-phase-gate.md` — ny sektion »Klausul-projektion«.
- Modify: `docs/decisions.md`, `docs/evidensbaseret-genimport/status.md`, `docs/evidensbaseret-genimport/clause-evidence-148-rehearsal.md`, `docs/changelog.md`.

---

### Task 1: Komparatorens kerne (Python, ren funktion)

**Files:**
- Create: `.claude/skills/daa-extract/scripts/compare_clause_evidence_projection.py`
- Create: `.claude/skills/daa-extract/scripts/test_compare_clause_evidence_projection.py`
- Modify: `.github/workflows/ci.yml` (pytest-linjen i jobbet `evidence contract · pytest`)

**Interfaces:**
- Consumes: manifestformatet fra `build_clause_evidence_manifest.py` (`source.id`, `manifest_content_sha256`, `expected_counts.clause_evidence`, `operations[]` med `element_id`, `dependency_class`, `source_record_key`, `parent_verbatim_sha256`, `clauses[]` med nøglerne `char_from, char_to, classification, flags, ordinal, rendition_char_from, rendition_char_to, verbatim_sha256`).
- Produces:
  - `PROJECTION_SCHEMA = "daa-clause-evidence-projection-v1"`, `RESULT_SCOPE = "clause-evidence-delta-v1"`
  - `NEUTRAL_LISTS = ("source_records", "source_anchors", "narrative_bindings", "narrative_sha256", "persons")`
  - `CANONICAL_TABLES = ("person", "fact", "assertion", "conclusion", "narrative", "relation", "family_member", "source_observation_non_clause")`
  - `CLAUSE_FIELDS = ("record_key", "clause_ordinal", "char_from", "char_to", "post_char_from", "post_char_to", "classification", "flags", "verbatim_sha256", "parent_verbatim_sha256", "disposition", "disposition_version")`
  - `EVENT_FIELDS = ("manifest_sha256", "batch_status", "element_id", "source_record_key")`
  - `class ProjectionError(ValueError)` med `.code: str` og `.details: dict`
  - `expected_clauses(manifest: dict) -> dict[tuple[str, int], dict]`
  - `compare(manifest: dict, before: dict, after: dict, allow_empty: frozenset[str] = frozenset()) -> dict` — returnerer resultatet ved `match`, rejser `ProjectionError` ved NO-GO.
  - Fejlkoder: `CLAUSE_PROJECTION_SHAPE_INVALID`, `CLAUSE_PROJECTION_DUPLICATE_ROW`, `CLAUSE_PROJECTION_EMPTY_LIST`, `CLAUSE_PROJECTION_MANIFEST_INVALID`, `CLAUSE_PROJECTION_SOURCE_MISMATCH`, `CLAUSE_PROJECTION_TARGET_MISMATCH`, `CLAUSE_PROJECTION_RECORD_UNKNOWN`, `CLAUSE_PROJECTION_NEUTRALITY_DRIFT`, `CLAUSE_PROJECTION_CANONICAL_DRIFT`, `CLAUSE_PROJECTION_PREEXISTING`, `CLAUSE_PROJECTION_FOREIGN_DRIFT`, `CLAUSE_PROJECTION_DRIFT`, `CLAUSE_PROJECTION_BATCH_BINDING_INVALID`.

**Projektionens JSON-form** (produceres af Task 3's SQL; alle nøgler obligatoriske, ingen ekstra):

```json
{
  "schema_version": "daa-clause-evidence-projection-v1",
  "source_id": 1,
  "database_target_identity": {"database_name": "…", "system_identifier_sha256": "<64 hex>"},
  "source_records": [{"record_key": "…"}],
  "source_anchors": [{"record_key": "…", "occurrence_key": "…"}],
  "narrative_bindings": [{"record_key": "…", "narrative_id": 7, "status": "published"}],
  "narrative_sha256": [{"narrative_id": 7, "sha256": "<64 hex>"}],
  "persons": [{"person_id": 42}],
  "clauses": [{"record_key": "…", "clause_ordinal": 1, "char_from": 100, "char_to": 110,
               "post_char_from": 0, "post_char_to": 10, "classification": "record_text",
               "flags": [], "verbatim_sha256": "<64 hex>", "parent_verbatim_sha256": "<64 hex>",
               "disposition": "afventer_fortolkning", "disposition_version": 1}],
  "clause_evidence_events": [{"manifest_sha256": "<64 hex>", "batch_status": "finalized",
                              "element_id": "clause-evidence:…", "source_record_key": "…"}],
  "canonical_sha256": {"person": "<64 hex>", "fact": "…", "assertion": "…", "conclusion": "…",
                       "narrative": "…", "relation": "…", "family_member": "…",
                       "source_observation_non_clause": "…"}
}
```

- [ ] **Step 1: Skriv de fejlende tests**

`.claude/skills/daa-extract/scripts/test_compare_clause_evidence_projection.py`:

```python
"""Komparatoren for klausul-projektionen (spec §11.1, vej C). Alt syntetisk."""
from __future__ import annotations

import copy
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))

import compare_clause_evidence_projection as cp


def H(char: str) -> str:
    return char * 64


def clause(ordinal, post_from, post_to, abs_from, abs_to, flags, sha, classification="record_text"):
    return {"ordinal": ordinal, "char_from": post_from, "char_to": post_to,
            "rendition_char_from": abs_from, "rendition_char_to": abs_to,
            "classification": classification, "flags": list(flags), "verbatim_sha256": sha}


def operation(key, parent_sha, clauses):
    return {"element_id": f"clause-evidence:{key}", "dependency_class": "clause_evidence",
            "source_record_key": key, "rendition_content_sha256": H("c"),
            "rendition_projection_sha256": H("e"), "parent_verbatim_sha256": parent_sha,
            "clause_rules_version": "rules-v1", "segmenter_version": "seg-v1",
            "ledger_sha256": H("d"), "gap_charset": [" "], "clauses": clauses}


def manifest():
    return {
        "manifest_content_sha256": H("a"),
        "source": {"id": 1, "profile_id": "p", "profile_sha256": H("b")},
        "expected_counts": {"source_evidence": 0, "person_creates": 0,
                            "canonical_delta": 0, "clause_evidence": 2},
        "operations": [
            operation("R1", H("2"), [clause(1, 0, 10, 100, 110, [], H("3")),
                                     clause(2, 11, 20, 111, 121, ["short_clause"], H("4"))]),
            operation("R2", H("5"), [clause(1, 0, 5, 200, 205, [], H("6"))]),
        ],
    }


def projection(clauses=(), events=()):
    return {
        "schema_version": cp.PROJECTION_SCHEMA,
        "source_id": 1,
        "database_target_identity": {"database_name": "fixture", "system_identifier_sha256": H("7")},
        "source_records": [{"record_key": "R1"}, {"record_key": "R2"}, {"record_key": "R9"}],
        "source_anchors": [{"record_key": "R1", "occurrence_key": "o1"},
                           {"record_key": "R2", "occurrence_key": "o2"},
                           {"record_key": "R9", "occurrence_key": "o9"}],
        "narrative_bindings": [{"record_key": "R1", "narrative_id": 7, "status": "published"}],
        "narrative_sha256": [{"narrative_id": 7, "sha256": H("8")}],
        "persons": [{"person_id": 42}],
        "clauses": [copy.deepcopy(c) for c in clauses],
        "clause_evidence_events": [copy.deepcopy(e) for e in events],
        "canonical_sha256": {t: H("0") for t in cp.CANONICAL_TABLES},
    }


def written_rows(m):
    return [dict(row) for _, row in sorted(cp.expected_clauses(m).items())]


def events_for(m, status="finalized"):
    return [{"manifest_sha256": m["manifest_content_sha256"], "batch_status": status,
             "element_id": op["element_id"], "source_record_key": op["source_record_key"]}
            for op in m["operations"]]


def applied(m):
    return projection(written_rows(m), events_for(m))


def code_of(excinfo):
    return excinfo.value.code


def test_match_counts_records_clauses_and_dispositions():
    m = manifest()
    result = cp.compare(m, projection(), applied(m))
    assert result["status"] == "match"
    assert result["scope"] == cp.RESULT_SCOPE
    assert result["manifest_content_sha256"] == H("a")
    assert result["counts"]["records"] == 2
    assert result["counts"]["clauses"] == 3
    assert result["counts"]["dispositions"] == {"afventer_fortolkning": 2, "maskinelt_flagget": 1}
    assert result["counts"]["neutral_lists"]["source_records"] == 3


def test_expected_clauses_maps_offsets_and_disposition_rule():
    m = manifest()
    m["operations"][1]["clauses"][0].update(classification="structural_header", flags=["x"])
    rows = cp.expected_clauses(m)
    r1 = rows[("R1", 1)]
    assert (r1["char_from"], r1["char_to"]) == (100, 110)
    assert (r1["post_char_from"], r1["post_char_to"]) == (0, 10)
    assert r1["parent_verbatim_sha256"] == H("2")
    assert r1["disposition_version"] == 1
    assert rows[("R1", 2)]["disposition"] == "maskinelt_flagget"
    assert rows[("R2", 1)]["disposition"] == "strukturel"


def test_missing_clause_is_drift():
    m = manifest()
    after = applied(m)
    after["clauses"] = [c for c in after["clauses"] if c["record_key"] != "R2"]
    with pytest.raises(cp.ProjectionError) as e:
        cp.compare(m, projection(), after)
    assert code_of(e) == "CLAUSE_PROJECTION_DRIFT"
    assert e.value.details["missing"] == [["R2", 1]]


def test_extra_clause_is_drift():
    m = manifest()
    after = applied(m)
    extra = dict(after["clauses"][0], clause_ordinal=3)
    after["clauses"].append(extra)
    with pytest.raises(cp.ProjectionError) as e:
        cp.compare(m, projection(), after)
    assert code_of(e) == "CLAUSE_PROJECTION_DRIFT"
    assert e.value.details["extra"] == [["R1", 3]]


@pytest.mark.parametrize("field,value", [
    ("post_char_to", 9), ("char_from", 101), ("verbatim_sha256", H("9")),
    ("parent_verbatim_sha256", H("9")), ("flags", ["other"]),
    ("disposition", "strukturel"), ("disposition_version", 2), ("classification", "structural_header"),
])
def test_field_mismatch_names_field_without_values(field, value):
    m = manifest()
    after = applied(m)
    after["clauses"][0][field] = value
    with pytest.raises(cp.ProjectionError) as e:
        cp.compare(m, projection(), after)
    assert code_of(e) == "CLAUSE_PROJECTION_DRIFT"
    mismatch = e.value.details["mismatched"]
    assert mismatch[0]["fields"] == [field]
    assert str(value) not in str(mismatch)


@pytest.mark.parametrize("name,field,value", [
    ("source_records", "record_key", "R8"),
    ("source_anchors", "occurrence_key", "oX"),
    ("narrative_bindings", "status", "draft"),
    ("narrative_sha256", "sha256", H("1")),
    ("persons", "person_id", 43),
])
def test_neutral_list_value_change_is_drift(name, field, value):
    m = manifest()
    after = applied(m)
    after[name][-1] = dict(after[name][-1], **{field: value})
    with pytest.raises(cp.ProjectionError) as e:
        cp.compare(m, projection(), after)
    assert code_of(e) == "CLAUSE_PROJECTION_NEUTRALITY_DRIFT"
    assert e.value.details["lists"] == [name]


@pytest.mark.parametrize("name", cp.NEUTRAL_LISTS)
def test_neutral_row_with_extra_key_is_shape_invalid(name):
    m = manifest()
    after = applied(m)
    after[name][-1] = dict(after[name][-1], marker=1)
    with pytest.raises(cp.ProjectionError) as e:
        cp.compare(m, projection(), after)
    assert code_of(e) == "CLAUSE_PROJECTION_SHAPE_INVALID"


def test_person_set_change_is_neutrality_drift():
    m = manifest()
    after = applied(m)
    after["persons"] = [{"person_id": 43}]
    with pytest.raises(cp.ProjectionError) as e:
        cp.compare(m, projection(), after)
    assert code_of(e) == "CLAUSE_PROJECTION_NEUTRALITY_DRIFT"
    assert e.value.details["lists"] == ["persons"]


def test_list_order_does_not_matter():
    m = manifest()
    after = applied(m)
    after["source_records"].reverse()
    after["clauses"].reverse()
    assert cp.compare(m, projection(), after)["status"] == "match"


def test_canonical_content_change_is_drift():
    m = manifest()
    after = applied(m)
    after["canonical_sha256"]["fact"] = H("1")
    with pytest.raises(cp.ProjectionError) as e:
        cp.compare(m, projection(), after)
    assert code_of(e) == "CLAUSE_PROJECTION_CANONICAL_DRIFT"
    assert e.value.details["tables"] == ["fact"]


def test_preexisting_clauses_for_manifest_record_is_no_go():
    m = manifest()
    with pytest.raises(cp.ProjectionError) as e:
        cp.compare(m, applied(m), applied(m))
    assert code_of(e) == "CLAUSE_PROJECTION_PREEXISTING"


def foreign(ordinal=1, sha=H("f")):
    return {"record_key": "R9", "clause_ordinal": ordinal, "char_from": 900, "char_to": 910,
            "post_char_from": 0, "post_char_to": 10, "classification": "record_text", "flags": [],
            "verbatim_sha256": sha, "parent_verbatim_sha256": H("e"),
            "disposition": "afventer_fortolkning", "disposition_version": 1}


def test_unchanged_foreign_clause_is_match():
    m = manifest()
    before = projection([foreign()])
    after = applied(m)
    after["clauses"].append(foreign())
    assert cp.compare(m, before, after)["status"] == "match"


def test_changed_foreign_clause_is_foreign_drift():
    m = manifest()
    before = projection([foreign()])
    after = applied(m)
    after["clauses"].append(foreign(sha=H("1")))
    with pytest.raises(cp.ProjectionError) as e:
        cp.compare(m, before, after)
    assert code_of(e) == "CLAUSE_PROJECTION_FOREIGN_DRIFT"


def test_wrong_manifest_hash_on_events_is_binding_invalid():
    m = manifest()
    after = applied(m)
    for ev in after["clause_evidence_events"]:
        ev["manifest_sha256"] = H("9")
    with pytest.raises(cp.ProjectionError) as e:
        cp.compare(m, projection(), after)
    assert code_of(e) == "CLAUSE_PROJECTION_BATCH_BINDING_INVALID"


def test_open_batch_is_binding_invalid():
    m = manifest()
    after = projection(written_rows(m), events_for(m, status="open"))
    with pytest.raises(cp.ProjectionError) as e:
        cp.compare(m, projection(), after)
    assert code_of(e) == "CLAUSE_PROJECTION_BATCH_BINDING_INVALID"


def test_missing_event_is_binding_invalid():
    m = manifest()
    after = applied(m)
    after["clause_evidence_events"].pop()
    with pytest.raises(cp.ProjectionError) as e:
        cp.compare(m, projection(), after)
    assert code_of(e) == "CLAUSE_PROJECTION_BATCH_BINDING_INVALID"


def test_event_already_before_is_binding_invalid():
    m = manifest()
    with pytest.raises(cp.ProjectionError) as e:
        cp.compare(m, projection(events=events_for(m)), applied(m))
    assert code_of(e) == "CLAUSE_PROJECTION_BATCH_BINDING_INVALID"


def test_unrelated_new_clause_event_is_binding_invalid():
    m = manifest()
    after = applied(m)
    after["clause_evidence_events"].append({"manifest_sha256": H("9"), "batch_status": "finalized",
                                            "element_id": "clause-evidence:R9", "source_record_key": "R9"})
    with pytest.raises(cp.ProjectionError) as e:
        cp.compare(m, projection(), after)
    assert code_of(e) == "CLAUSE_PROJECTION_BATCH_BINDING_INVALID"


def test_source_mismatch():
    m = manifest()
    m["source"]["id"] = 2
    with pytest.raises(cp.ProjectionError) as e:
        cp.compare(m, projection(), applied(manifest()))
    assert code_of(e) == "CLAUSE_PROJECTION_SOURCE_MISMATCH"


def test_target_mismatch():
    m = manifest()
    after = applied(m)
    after["database_target_identity"]["database_name"] = "other"
    with pytest.raises(cp.ProjectionError) as e:
        cp.compare(m, projection(), after)
    assert code_of(e) == "CLAUSE_PROJECTION_TARGET_MISMATCH"


def test_record_unknown():
    m = manifest()
    before, after = projection(), applied(m)
    for p in (before, after):
        p["source_records"] = [r for r in p["source_records"] if r["record_key"] != "R2"]
    with pytest.raises(cp.ProjectionError) as e:
        cp.compare(m, before, after)
    assert code_of(e) == "CLAUSE_PROJECTION_RECORD_UNKNOWN"


@pytest.mark.parametrize("name", cp.NEUTRAL_LISTS)
def test_empty_list_is_no_go_unless_allowed(name):
    m = manifest()
    before, after = projection(), applied(m)
    before[name], after[name] = [], []
    if name in ("source_records", "source_anchors"):
        with pytest.raises(cp.ProjectionError) as e:
            cp.compare(m, before, after, allow_empty=frozenset({name}))
        assert code_of(e) == "CLAUSE_PROJECTION_EMPTY_LIST"
        return
    with pytest.raises(cp.ProjectionError) as e:
        cp.compare(m, before, after)
    assert code_of(e) == "CLAUSE_PROJECTION_EMPTY_LIST"
    result = cp.compare(m, before, after, allow_empty=frozenset({name}))
    assert result["counts"]["allowed_empty"] == [name]


def test_duplicate_row_is_no_go():
    m = manifest()
    after = applied(m)
    after["persons"].append({"person_id": 42})
    with pytest.raises(cp.ProjectionError) as e:
        cp.compare(m, projection(), after)
    assert code_of(e) == "CLAUSE_PROJECTION_DUPLICATE_ROW"


def test_duplicate_clause_key_is_no_go():
    m = manifest()
    after = applied(m)
    after["clauses"].append(dict(after["clauses"][0], verbatim_sha256=H("9")))
    with pytest.raises(cp.ProjectionError) as e:
        cp.compare(m, projection(), after)
    assert code_of(e) == "CLAUSE_PROJECTION_DUPLICATE_ROW"


@pytest.mark.parametrize("mutate", [
    lambda p: p.update(extra=1),
    lambda p: p.update(schema_version="daa-evidence-production-snapshot-v1"),
    lambda p: p.update(source_id="1"),
    lambda p: p["canonical_sha256"].pop("fact"),
    lambda p: p["clauses"].append({"record_key": "R9"}),
    lambda p: p["database_target_identity"].update(system_identifier_sha256="x"),
])
def test_shape_invalid(mutate):
    m = manifest()
    after = applied(m)
    mutate(after)
    with pytest.raises(cp.ProjectionError) as e:
        cp.compare(m, projection(), after)
    assert code_of(e) == "CLAUSE_PROJECTION_SHAPE_INVALID"


@pytest.mark.parametrize("mutate", [
    lambda m: m["expected_counts"].update(clause_evidence=3),
    lambda m: m["operations"][0]["clauses"][1].update(ordinal=3),
    lambda m: m["operations"][0].update(element_id="clause-evidence:R2"),
    lambda m: m["operations"][0].update(dependency_class="source_evidence"),
    lambda m: m["operations"][0]["clauses"][0].update(verbatim_text="tekst"),
    lambda m: m.update(operations=[]),
    lambda m: m.update(manifest_content_sha256="x"),
])
def test_manifest_invalid(mutate):
    m = manifest()
    after = applied(manifest())
    mutate(m)
    with pytest.raises(cp.ProjectionError) as e:
        cp.compare(m, projection(), after)
    assert code_of(e) == "CLAUSE_PROJECTION_MANIFEST_INVALID"
```

- [ ] **Step 2: Kør testene og se dem fejle**

Run (fra worktree-roden): `env -u NODE_OPTIONS /usr/bin/python3 -m pytest .claude/skills/daa-extract/scripts/test_compare_clause_evidence_projection.py -q -p no:cacheprovider`
Expected: FAIL / collection error `ModuleNotFoundError: No module named 'compare_clause_evidence_projection'`.

- [ ] **Step 3: Implementér kernen**

`.claude/skills/daa-extract/scripts/compare_clause_evidence_projection.py` (CLI'en `main` tilføjes i Task 2):

```python
#!/usr/bin/env python3
"""Afstem én clause_evidence-kørsel mod to læse-kun projektioner (spec §11.1, vej C).

Udgaveneutral: scriptet kender ingen udgave, fase eller historik. Det beviser kun
DELTAET af én kørsel:

1. de fem runbook-projektioner og det kanoniske lags indholds-hash er uændrede;
2. klausulrækkerne for manifestets records er præcis manifestets klausuler, felt for felt;
3. rækkerne stammer fra én færdig batch med manifestets hash;
4. ingen anden klausul i kilden er ændret.

Det beviser IKKE, at prod er summen af alle historiske faser. Scriptet åbner aldrig
en database; projektionerne produceres af clause_evidence_projection.sql.
"""
from __future__ import annotations

import json
from collections import Counter
from typing import Any

PROJECTION_SCHEMA = "daa-clause-evidence-projection-v1"
RESULT_SCOPE = "clause-evidence-delta-v1"
NEUTRAL_LISTS = ("source_records", "source_anchors", "narrative_bindings", "narrative_sha256", "persons")
# Uden kilde-records og ankre findes intet at skrive klausuler på; de må aldrig være tomme.
ALWAYS_NONEMPTY = ("source_records", "source_anchors")
CANONICAL_TABLES = ("person", "fact", "assertion", "conclusion", "narrative", "relation",
                    "family_member", "source_observation_non_clause")
CLAUSE_FIELDS = ("record_key", "clause_ordinal", "char_from", "char_to", "post_char_from",
                 "post_char_to", "classification", "flags", "verbatim_sha256",
                 "parent_verbatim_sha256", "disposition", "disposition_version")
EVENT_FIELDS = ("manifest_sha256", "batch_status", "element_id", "source_record_key")
NEUTRAL_ROW_KEYS = {
    "source_records": frozenset(("record_key",)),
    "source_anchors": frozenset(("record_key", "occurrence_key")),
    "narrative_bindings": frozenset(("record_key", "narrative_id", "status")),
    "narrative_sha256": frozenset(("narrative_id", "sha256")),
    "persons": frozenset(("person_id",)),
}
PROJECTION_KEYS = frozenset(("schema_version", "source_id", "database_target_identity",
                             "clauses", "clause_evidence_events", "canonical_sha256") + NEUTRAL_LISTS)
MANIFEST_CLAUSE_KEYS = frozenset(("char_from", "char_to", "classification", "flags", "ordinal",
                                  "rendition_char_from", "rendition_char_to", "verbatim_sha256"))
ELEMENT_PREFIX = "clause-evidence:"


class ProjectionError(ValueError):
    """NO-GO. `details` bærer kun nøgler og feltnavne, aldrig værdier eller tekst."""

    def __init__(self, code: str, details: dict[str, Any] | None = None) -> None:
        super().__init__(code)
        self.code = code
        self.details = details or {}


def _fail(code: str, **details: Any) -> None:
    raise ProjectionError(code, details)


def _is_sha(value: Any) -> bool:
    return isinstance(value, str) and len(value) == 64 and all(c in "0123456789abcdef" for c in value)


def _is_int(value: Any) -> bool:
    return type(value) is int


def _canon(row: Any) -> str:
    return json.dumps(row, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def _canon_set(rows: list[Any]) -> list[str]:
    return sorted(_canon(r) for r in rows)


def _disposition(classification: str, flags: list[str]) -> str:
    # Spejler private.write_clause_evidence (db-migrations.sql, `v_disposition:=CASE`).
    if classification == "structural_header":
        return "strukturel"
    if flags:
        return "maskinelt_flagget"
    return "afventer_fortolkning"


def _validate_projection(p: Any, allow_empty: frozenset[str]) -> dict[tuple[str, int], dict[str, Any]]:
    if not isinstance(p, dict) or set(p) != PROJECTION_KEYS:
        _fail("CLAUSE_PROJECTION_SHAPE_INVALID", part="keys")
    if p["schema_version"] != PROJECTION_SCHEMA or not _is_int(p["source_id"]) or p["source_id"] <= 0:
        _fail("CLAUSE_PROJECTION_SHAPE_INVALID", part="header")
    identity = p["database_target_identity"]
    if (not isinstance(identity, dict) or set(identity) != {"database_name", "system_identifier_sha256"}
            or not isinstance(identity["database_name"], str) or not _is_sha(identity["system_identifier_sha256"])):
        _fail("CLAUSE_PROJECTION_SHAPE_INVALID", part="database_target_identity")
    canonical = p["canonical_sha256"]
    if (not isinstance(canonical, dict) or set(canonical) != set(CANONICAL_TABLES)
            or not all(_is_sha(v) for v in canonical.values())):
        _fail("CLAUSE_PROJECTION_SHAPE_INVALID", part="canonical_sha256")
    for name in NEUTRAL_LISTS + ("clause_evidence_events",):
        rows = p[name]
        if not isinstance(rows, list) or not all(isinstance(r, dict) for r in rows):
            _fail("CLAUSE_PROJECTION_SHAPE_INVALID", part=name)
        if len(set(_canon_set(rows))) != len(rows):
            _fail("CLAUSE_PROJECTION_DUPLICATE_ROW", part=name)
    for name in NEUTRAL_LISTS:
        if not all(set(r) == NEUTRAL_ROW_KEYS[name] for r in p[name]):
            _fail("CLAUSE_PROJECTION_SHAPE_INVALID", part=name)
        if not p[name] and (name in ALWAYS_NONEMPTY or name not in allow_empty):
            _fail("CLAUSE_PROJECTION_EMPTY_LIST", part=name)
    if not all(set(e) == set(EVENT_FIELDS) for e in p["clause_evidence_events"]):
        _fail("CLAUSE_PROJECTION_SHAPE_INVALID", part="clause_evidence_events")
    clauses = p["clauses"]
    if not isinstance(clauses, list):
        _fail("CLAUSE_PROJECTION_SHAPE_INVALID", part="clauses")
    keyed: dict[tuple[str, int], dict[str, Any]] = {}
    for row in clauses:
        if (not isinstance(row, dict) or set(row) != set(CLAUSE_FIELDS)
                or not isinstance(row["record_key"], str) or not _is_int(row["clause_ordinal"])):
            _fail("CLAUSE_PROJECTION_SHAPE_INVALID", part="clauses")
        key = (row["record_key"], row["clause_ordinal"])
        if key in keyed:
            _fail("CLAUSE_PROJECTION_DUPLICATE_ROW", part="clauses")
        keyed[key] = row
    return keyed


def expected_clauses(manifest: Any) -> dict[tuple[str, int], dict[str, Any]]:
    """Manifestets klausuler som projektionsrækker (writerens egen afbildning)."""
    def bad(part: str) -> None:
        _fail("CLAUSE_PROJECTION_MANIFEST_INVALID", part=part)

    if not isinstance(manifest, dict) or not _is_sha(manifest.get("manifest_content_sha256")):
        bad("header")
    source = manifest.get("source")
    if not isinstance(source, dict) or not _is_int(source.get("id")):
        bad("source")
    operations = manifest.get("operations")
    if not isinstance(operations, list) or not operations:
        bad("operations")
    counts = manifest.get("expected_counts")
    if not isinstance(counts, dict) or counts.get("clause_evidence") != len(operations):
        bad("expected_counts")
    rows: dict[tuple[str, int], dict[str, Any]] = {}
    seen: set[str] = set()
    for op in operations:
        if not isinstance(op, dict):
            bad("operation")
        key = op.get("source_record_key")
        if (not isinstance(key, str) or not key or key in seen
                or op.get("element_id") != ELEMENT_PREFIX + key
                or op.get("dependency_class") != "clause_evidence"
                or not _is_sha(op.get("parent_verbatim_sha256"))):
            bad("operation")
        seen.add(key)
        clauses = op.get("clauses")
        if not isinstance(clauses, list) or not clauses:
            bad("clauses")
        for index, c in enumerate(clauses, start=1):
            if not isinstance(c, dict) or set(c) != MANIFEST_CLAUSE_KEYS or c["ordinal"] != index:
                bad("clause")
            if not isinstance(c["flags"], list) or not _is_sha(c["verbatim_sha256"]):
                bad("clause")
            rows[(key, index)] = {
                "record_key": key, "clause_ordinal": index,
                "char_from": c["rendition_char_from"], "char_to": c["rendition_char_to"],
                "post_char_from": c["char_from"], "post_char_to": c["char_to"],
                "classification": c["classification"], "flags": list(c["flags"]),
                "verbatim_sha256": c["verbatim_sha256"],
                "parent_verbatim_sha256": op["parent_verbatim_sha256"],
                "disposition": _disposition(c["classification"], c["flags"]),
                "disposition_version": 1,
            }
    return rows


def compare(manifest: Any, before: Any, after: Any,
            allow_empty: frozenset[str] = frozenset()) -> dict[str, Any]:
    before_clauses = _validate_projection(before, allow_empty)
    after_clauses = _validate_projection(after, allow_empty)
    expected = expected_clauses(manifest)
    record_keys = {key for key, _ in expected}
    manifest_sha = manifest["manifest_content_sha256"]

    if not (manifest["source"]["id"] == before["source_id"] == after["source_id"]):
        _fail("CLAUSE_PROJECTION_SOURCE_MISMATCH")
    if before["database_target_identity"] != after["database_target_identity"]:
        _fail("CLAUSE_PROJECTION_TARGET_MISMATCH")
    known = {r.get("record_key") for r in after["source_records"]}
    unknown = sorted(record_keys - known)
    if unknown:
        _fail("CLAUSE_PROJECTION_RECORD_UNKNOWN", records=len(unknown))

    drifted = [n for n in NEUTRAL_LISTS if _canon_set(before[n]) != _canon_set(after[n])]
    if drifted:
        _fail("CLAUSE_PROJECTION_NEUTRALITY_DRIFT", lists=drifted)
    tables = [t for t in CANONICAL_TABLES if before["canonical_sha256"][t] != after["canonical_sha256"][t]]
    if tables:
        _fail("CLAUSE_PROJECTION_CANONICAL_DRIFT", tables=tables)

    preexisting = sorted({k[0] for k in before_clauses if k[0] in record_keys})
    if preexisting:
        _fail("CLAUSE_PROJECTION_PREEXISTING", records=len(preexisting))
    foreign_before = {k: _canon(v) for k, v in before_clauses.items() if k[0] not in record_keys}
    foreign_after = {k: _canon(v) for k, v in after_clauses.items() if k[0] not in record_keys}
    if foreign_before != foreign_after:
        changed = set(foreign_before) ^ set(foreign_after)
        changed |= {k for k in set(foreign_before) & set(foreign_after) if foreign_before[k] != foreign_after[k]}
        _fail("CLAUSE_PROJECTION_FOREIGN_DRIFT", clauses=len(changed))

    actual = {k: v for k, v in after_clauses.items() if k[0] in record_keys}
    missing = sorted(set(expected) - set(actual))
    extra = sorted(set(actual) - set(expected))
    mismatched = []
    for key in sorted(set(expected) & set(actual)):
        fields = [f for f in CLAUSE_FIELDS if _canon(expected[key][f]) != _canon(actual[key][f])]
        if fields:
            mismatched.append({"record_key": key[0], "clause_ordinal": key[1], "fields": fields})
    if missing or extra or mismatched:
        _fail("CLAUSE_PROJECTION_DRIFT", missing=[list(k) for k in missing],
              extra=[list(k) for k in extra], mismatched=mismatched)

    before_events = set(_canon_set(before["clause_evidence_events"]))
    new_events = [e for e in after["clause_evidence_events"] if _canon(e) not in before_events]
    element_ids = sorted(ELEMENT_PREFIX + k for k in record_keys)
    binding_ok = (
        not any(e["manifest_sha256"] == manifest_sha for e in before["clause_evidence_events"])
        and len(new_events) == len(element_ids)
        and all(e["manifest_sha256"] == manifest_sha and e["batch_status"] == "finalized"
                and e["element_id"] == ELEMENT_PREFIX + str(e["source_record_key"]) for e in new_events)
        and sorted(e["element_id"] for e in new_events) == element_ids
    )
    if not binding_ok:
        _fail("CLAUSE_PROJECTION_BATCH_BINDING_INVALID", new_events=len(new_events), expected=len(element_ids))

    dispositions = Counter(row["disposition"] for row in expected.values())
    return {
        "status": "match",
        "scope": RESULT_SCOPE,
        "source_id": after["source_id"],
        "manifest_content_sha256": manifest_sha,
        "counts": {
            "records": len(record_keys),
            "clauses": len(expected),
            "dispositions": dict(sorted(dispositions.items())),
            "neutral_lists": {n: len(after[n]) for n in NEUTRAL_LISTS},
            "allowed_empty": sorted(n for n in allow_empty if not after[n]),
        },
    }
```

- [ ] **Step 4: Kør testene og se dem bestå**

Run: `env -u NODE_OPTIONS /usr/bin/python3 -m pytest .claude/skills/daa-extract/scripts/test_compare_clause_evidence_projection.py -q -p no:cacheprovider`
Expected: alle tests `passed`. Fejler en test, ret implementeringen — ikke testen — medmindre testen modsiger Global Constraints; notér i så fald afvigelsen i commit-beskeden.

- [ ] **Step 5: Tilføj testfilen til CI's pytest-liste**

I `.github/workflows/ci.yml`, jobbet `evidence contract · pytest`: tilføj `.claude/skills/daa-extract/scripts/test_compare_clause_evidence_projection.py` til den lange `python3 -m pytest …`-linje (den der starter med `test_reimport_profile.py`), sidst før ` -q`.

Verify: `grep -c "test_compare_clause_evidence_projection.py" .github/workflows/ci.yml` → `1`.

- [ ] **Step 6: Commit**

```bash
git add .claude/skills/daa-extract/scripts/compare_clause_evidence_projection.py \
        .claude/skills/daa-extract/scripts/test_compare_clause_evidence_projection.py \
        .github/workflows/ci.yml
git commit -m "feat(evidens): komparator for klausul-projektionen (#195)"
```

---

### Task 2: Komparatorens CLI — privat rapport, exitkoder

**Files:**
- Modify: `.claude/skills/daa-extract/scripts/compare_clause_evidence_projection.py` (tilføj `main`)
- Modify: `.claude/skills/daa-extract/scripts/test_compare_clause_evidence_projection.py` (CLI-tests)

**Interfaces:**
- Consumes: `compare`, `ProjectionError` fra Task 1.
- Produces: kommandoen
  `compare_clause_evidence_projection.py --manifest M --before B --after A --report R [--allow-empty narrative_bindings,narrative_sha256,persons]`
  - exit `0` = `match`, exit `1` = NO-GO, exit `2` = brugsfejl (argparse, ulæselig input, rapportsti ugyldig).
  - stdout: én JSON-linje **uden** `details` (så record-nøgler aldrig havner i en terminal-log): `{"status": "match", "scope": …, "counts": …}` eller `{"status": "no_go", "code": …}` eller `{"status": "usage_error", "code": …}`.
  - Rapporten `R`: fuldt resultat inkl. `details`, oprettet med `O_CREAT|O_EXCL`, mode 0600. Afvises (`CLAUSE_PROJECTION_REPORT_EXISTS` / `CLAUSE_PROJECTION_REPORT_IN_REPOSITORY` / `CLAUSE_PROJECTION_REPORT_DIR_MISSING`) før input læses.
  - `--allow-empty` accepterer kun `narrative_bindings`, `narrative_sha256`, `persons`; andet → `CLAUSE_PROJECTION_ALLOW_EMPTY_INVALID`, exit 2.

- [ ] **Step 1: Skriv de fejlende CLI-tests** (tilføj nederst i testfilen)

```python
import json as _json
import os
import stat
import subprocess

SCRIPT = Path(__file__).resolve().parent / "compare_clause_evidence_projection.py"


def write(tmp_path, name, data):
    path = tmp_path / name
    path.write_text(_json.dumps(data), encoding="utf-8")
    return path


def run_cli(*args):
    env = {k: v for k, v in os.environ.items() if k != "NODE_OPTIONS"}
    return subprocess.run([sys.executable, str(SCRIPT), *map(str, args)],
                          capture_output=True, text=True, env=env)


def cli_inputs(tmp_path, after=None):
    m = manifest()
    return (write(tmp_path, "manifest.json", m), write(tmp_path, "before.json", projection()),
            write(tmp_path, "after.json", after if after is not None else applied(m)))


def test_cli_match_writes_private_report(tmp_path):
    mp, bp, ap = cli_inputs(tmp_path)
    report = tmp_path / "report.json"
    proc = run_cli("--manifest", mp, "--before", bp, "--after", ap, "--report", report)
    assert proc.returncode == 0, proc.stderr
    terminal = _json.loads(proc.stdout)
    assert terminal["status"] == "match" and "details" not in terminal
    assert stat.S_IMODE(report.stat().st_mode) == 0o600
    assert _json.loads(report.read_text())["status"] == "match"


def test_cli_no_go_keeps_record_keys_out_of_stdout(tmp_path):
    m = manifest()
    after = applied(m)
    after["clauses"] = [c for c in after["clauses"] if c["record_key"] != "R2"]
    mp, bp, ap = cli_inputs(tmp_path, after)
    report = tmp_path / "report.json"
    proc = run_cli("--manifest", mp, "--before", bp, "--after", ap, "--report", report)
    assert proc.returncode == 1
    terminal = _json.loads(proc.stdout)
    assert terminal == {"status": "no_go", "code": "CLAUSE_PROJECTION_DRIFT"}
    assert "R2" not in proc.stdout and "R2" not in proc.stderr
    assert _json.loads(report.read_text())["details"]["missing"] == [["R2", 1]]


def test_cli_refuses_existing_report(tmp_path):
    mp, bp, ap = cli_inputs(tmp_path)
    report = tmp_path / "report.json"
    report.write_text("x")
    proc = run_cli("--manifest", mp, "--before", bp, "--after", ap, "--report", report)
    assert proc.returncode == 2
    assert _json.loads(proc.stdout)["code"] == "CLAUSE_PROJECTION_REPORT_EXISTS"
    assert report.read_text() == "x"


def test_cli_refuses_report_inside_repository(tmp_path):
    mp, bp, ap = cli_inputs(tmp_path)
    report = SCRIPT.parent / "must-not-exist-clause-projection-report.json"
    proc = run_cli("--manifest", mp, "--before", bp, "--after", ap, "--report", report)
    assert proc.returncode == 2
    assert _json.loads(proc.stdout)["code"] == "CLAUSE_PROJECTION_REPORT_IN_REPOSITORY"
    assert not report.exists()


def test_cli_rejects_unknown_allow_empty(tmp_path):
    mp, bp, ap = cli_inputs(tmp_path)
    proc = run_cli("--manifest", mp, "--before", bp, "--after", ap,
                   "--report", tmp_path / "r.json", "--allow-empty", "source_records")
    assert proc.returncode == 2
    assert _json.loads(proc.stdout)["code"] == "CLAUSE_PROJECTION_ALLOW_EMPTY_INVALID"


def test_cli_unreadable_input_is_usage_error(tmp_path):
    mp, bp, _ = cli_inputs(tmp_path)
    bad = tmp_path / "bad.json"
    bad.write_text("{", encoding="utf-8")
    proc = run_cli("--manifest", mp, "--before", bp, "--after", bad, "--report", tmp_path / "r.json")
    assert proc.returncode == 2
    assert _json.loads(proc.stdout)["code"] == "CLAUSE_PROJECTION_INPUT_UNREADABLE"
    assert not (tmp_path / "r.json").exists()
```

- [ ] **Step 2: Kør og se dem fejle**

Run: `env -u NODE_OPTIONS /usr/bin/python3 -m pytest .claude/skills/daa-extract/scripts/test_compare_clause_evidence_projection.py -q -p no:cacheprovider -k cli`
Expected: FAIL (scriptet har ingen `main`; subprocess afslutter med exit 0 og tom stdout → `JSONDecodeError`).

- [ ] **Step 3: Implementér `main`** (tilføj nederst i `compare_clause_evidence_projection.py`, og tilføj `import argparse`, `import os`, `import sys`, `from pathlib import Path` øverst)

```python
ALLOWED_EMPTY_CHOICES = frozenset(("narrative_bindings", "narrative_sha256", "persons"))


class UsageError(ValueError):
    def __init__(self, code: str) -> None:
        super().__init__(code)
        self.code = code


def _inside_repository(path: Path) -> bool:
    return any((parent / ".git").exists() for parent in (path.parent, *path.parent.parents))


def _check_report_path(raw: str) -> Path:
    path = Path(raw).expanduser().absolute()
    if not path.parent.is_dir():
        raise UsageError("CLAUSE_PROJECTION_REPORT_DIR_MISSING")
    if _inside_repository(path):
        raise UsageError("CLAUSE_PROJECTION_REPORT_IN_REPOSITORY")
    if path.exists() or path.is_symlink():
        raise UsageError("CLAUSE_PROJECTION_REPORT_EXISTS")
    return path


def _load(raw: str) -> Any:
    try:
        with open(raw, encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, ValueError):
        raise UsageError("CLAUSE_PROJECTION_INPUT_UNREADABLE") from None


def _write_private(path: Path, data: dict[str, Any]) -> None:
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        json.dump(data, handle, ensure_ascii=False, sort_keys=True, indent=2)
        handle.write("\n")
    os.chmod(path, 0o600)


def _emit(data: dict[str, Any]) -> None:
    print(json.dumps(data, ensure_ascii=False, sort_keys=True))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--before", required=True)
    parser.add_argument("--after", required=True)
    parser.add_argument("--report", required=True)
    parser.add_argument("--allow-empty", default="")
    args = parser.parse_args(argv)
    try:
        allow_empty = frozenset(x for x in args.allow_empty.split(",") if x)
        if not allow_empty <= ALLOWED_EMPTY_CHOICES:
            raise UsageError("CLAUSE_PROJECTION_ALLOW_EMPTY_INVALID")
        report = _check_report_path(args.report)
        manifest, before, after = _load(args.manifest), _load(args.before), _load(args.after)
    except UsageError as error:
        _emit({"status": "usage_error", "code": error.code})
        return 2
    try:
        result: dict[str, Any] = compare(manifest, before, after, allow_empty)
        terminal = result
    except ProjectionError as error:
        result = {"status": "no_go", "code": error.code, "details": error.details}
        terminal = {"status": "no_go", "code": error.code}
    _write_private(report, result)
    _emit(terminal)
    return 0 if result["status"] == "match" else 1


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 4: Kør hele testfilen**

Run: `env -u NODE_OPTIONS /usr/bin/python3 -m pytest .claude/skills/daa-extract/scripts/test_compare_clause_evidence_projection.py -q -p no:cacheprovider`
Expected: alle `passed`. Kør også med CI-lignende tolk, hvis en findes: `python3.11 -m pytest …` (spring over, hvis `python3.11` ikke er installeret — notér det).

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/daa-extract/scripts/compare_clause_evidence_projection.py \
        .claude/skills/daa-extract/scripts/test_compare_clause_evidence_projection.py
git commit -m "feat(evidens): CLI til klausul-komparatoren med privat rapport (#195)"
```

---

### Task 3: Læse-kun projektion (SQL) og ende-til-ende i CI

**Files:**
- Create: `.claude/skills/daa-extract/scripts/clause_evidence_projection.sql`
- Modify: `tests/integration/test-reimport-clause-evidence.R`

**Interfaces:**
- Consumes: Task 2's CLI; tabellerne `private.source_record`, `private.source_record_anchor_current`, `private.source_record_occurrence`, `private.narrative_record_publication`, `public.narrative`, `private.source_observation`, `private.clause_disposition_current`, `private.reimport_event`, `private.reimport_batch` og de syv kanoniske `public`-tabeller.
- Produces: én SQL-sætning, der returnerer én række med kolonnen `projection` (jsonb) i formen fra Task 1. Parameter: `daa.projection_source_id` (sat med `SET`/`set_config` i samme session/transaktion). Guard-fejl: `CLAUSE_PROJECTION_SOURCE_ID_MISSING`, `CLAUSE_PROJECTION_NOT_READ_ONLY`, `CLAUSE_PROJECTION_NOT_REPEATABLE_READ` (rejses som `invalid input syntax for type integer: "<KODE>:…"`).

- [ ] **Step 1: Udvid integrationstesten, så den fejler**

I `tests/integration/test-reimport-clause-evidence.R`:

(a) Lige efter `validate_reimport_manifest(manifest_ce)` indsættes hjælperne:

```r
# ---- klausul-projektion (spec §11.1, vej C, #195) ---------------------------
projection_sql <- paste(readLines(file.path(root,
  ".claude/skills/daa-extract/scripts/clause_evidence_projection.sql"), warn = FALSE), collapse = "\n")
comparator <- file.path(root, ".claude/skills/daa-extract/scripts/compare_clause_evidence_projection.py")
projection <- function(read_only = TRUE) {
  pc <- connect(); on.exit(dbDisconnect(pc), add = TRUE)
  dbBegin(pc); on.exit(try(dbRollback(pc), silent = TRUE), add = TRUE, after = FALSE)
  if (read_only) dbExecute(pc, "SET TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY")
  dbGetQuery(pc, "SELECT set_config('daa.projection_source_id', $1, true)", params = list(as.character(source_id)))
  as.character(dbGetQuery(pc, projection_sql)$projection[[1L]])
}
proj_dir <- tempfile("klausul-projektion-"); dir.create(proj_dir, mode = "0700")
write_private <- function(name, text) { path <- file.path(proj_dir, name); writeLines(text, path); Sys.chmod(path, "0600"); path }
run_comparator <- function(before_path, after_path, report_name) {
  out <- suppressWarnings(system2("python3", c(shQuote(comparator),
    "--manifest", shQuote(manifest_path), "--before", shQuote(before_path), "--after", shQuote(after_path),
    "--report", shQuote(file.path(proj_dir, report_name)),
    "--allow-empty", "narrative_bindings,narrative_sha256,persons"), stdout = TRUE, stderr = TRUE))
  list(status = if (is.null(attr(out, "status"))) 0L else attr(out, "status"), out = paste(out, collapse = "\n"))
}
manifest_path <- write_private("manifest.json",
  as.character(jsonlite::toJSON(manifest_ce, auto_unbox = TRUE, null = "null", digits = NA)))

not_read_only <- tryCatch({ projection(read_only = FALSE); "ingen fejl" }, error = function(err) conditionMessage(err))
stopifnot(grepl("CLAUSE_PROJECTION_NOT_READ_ONLY", not_read_only, fixed = TRUE))
```

(b) Umiddelbart **før** linjen `applied <- execute_reimport(manifest_ce, preview_sha_ce, "apply", ...`:

```r
before_path <- write_private("before.json", projection())
```

(c) Umiddelbart **efter** `stopifnot(count1("SELECT count(*) FROM private.clause_disposition_current ... >= 2L)`:

```r
after_text <- projection()
after_path <- write_private("after.json", after_text)
matched <- run_comparator(before_path, after_path, "report-match.json")
if (matched$status != 0L) stop("klausul-projektion ikke match: ", matched$out)
stopifnot(grepl('"status": "match"', matched$out, fixed = TRUE))

tampered <- sub('"disposition": "afventer_fortolkning"', '"disposition": "strukturel"', after_text, fixed = TRUE)
stopifnot(!identical(tampered, after_text))
no_go <- run_comparator(before_path, write_private("after-tampered.json", tampered), "report-tampered.json")
stopifnot(no_go$status == 1L, grepl("CLAUSE_PROJECTION_DRIFT", no_go$out, fixed = TRUE))
```

(d) Efter `stopifnot(identical(replay$status, "already_applied"))`:

```r
# Replay må ikke efterlade spor i projektionen.
stopifnot(identical(projection(), after_text))
```

- [ ] **Step 2: Byg en disponerbar base som CI og se testen fejle**

Kør fra worktree-roden (lokal Homebrew PostgreSQL 17, port 5432; basenavnet er engangs):

```bash
export PGHOST=localhost PGPORT=5432 PGUSER=$(whoami) PGTZ=UTC
DB="klausulproj_ci_$(date +%Y%m%d%H%M%S)"; export PGDATABASE="$DB"
createdb "$DB"
psql -X -q -v ON_ERROR_STOP=1 -f tests/sql/evidence-promotion-bootstrap.sql
psql -X -q -v ON_ERROR_STOP=1 -f schema.sql
psql -X -q -v ON_ERROR_STOP=1 -f db-rls.sql
psql -X -q -v ON_ERROR_STOP=1 -f tests/sql/1939-v50-writer-bootstrap.sql
psql -X -q -v ON_ERROR_STOP=1 -c 'BEGIN' -f tests/sql/reimport-writer-v2-bootstrap.sql -c 'COMMIT'
psql -X -q -v ON_ERROR_STOP=1 -f db-rls.sql
echo "$DB" > "${TMPDIR:-/tmp}/klausulproj-db-name.txt"
Rscript tests/integration/test-reimport-clause-evidence.R
```

Genbyggeskridtene er de samme som CI-trinnet »Nulstil database til name completion integration« i `.github/workflows/ci.yml`; hvis et af dem fejler lokalt, sammenlign med CI-trinnet og ret kommandoen, ikke skemaet.

Expected: `Rscript` fejler i `readLines(...)` med `cannot open file '…/clause_evidence_projection.sql'`.

- [ ] **Step 3: Skriv projektionen**

`.claude/skills/daa-extract/scripts/clause_evidence_projection.sql`:

```sql
-- Læse-kun klausul-projektion (spec §11.1, vej C, #195). Udgaveneutral.
--
-- Kaldes i en transaktion med READ ONLY og REPEATABLE READ, efter
--   SELECT set_config('daa.projection_source_id', '<id>', true);   -- eller SET i sessionen
-- Returnerer én række med kolonnen `projection` (jsonb), som
-- compare_clause_evidence_projection.py læser.
--
-- Ingen kildetekst forlader databasen: klausul-, helpost- og narrativtekst
-- hashes her. Det kanoniske lag afstemmes på INDHOLD (rækketekst pr. tabel),
-- ikke på antal — en ændret række med uændret antal skal give drift.
--
-- Guard-fejl rejses som en tekst->integer-cast af en ikke-konstant streng, så
-- planneren ikke kan konstant-folde den og fejle ved hver kørsel.
WITH guard AS (
  SELECT
    CASE
      WHEN nullif(current_setting('daa.projection_source_id', true), '') IS NULL
        THEN ('CLAUSE_PROJECTION_SOURCE_ID_MISSING:' || coalesce(current_setting('daa.projection_source_id', true), ''))::int
      WHEN current_setting('transaction_read_only') <> 'on'
        THEN ('CLAUSE_PROJECTION_NOT_READ_ONLY:' || current_setting('transaction_read_only'))::int
      WHEN current_setting('transaction_isolation') <> 'repeatable read'
        THEN ('CLAUSE_PROJECTION_NOT_REPEATABLE_READ:' || current_setting('transaction_isolation'))::int
      ELSE 1
    END AS ok,
    nullif(current_setting('daa.projection_source_id', true), '')::bigint AS source_id
), records AS (
  SELECT r.id, r.record_key
  FROM private.source_record r
  JOIN guard g ON g.ok = 1 AND r.source_id = g.source_id
), accepted AS (
  SELECT r.record_key, a.occurrence_id, o.occurrence_key
  FROM records r
  JOIN private.source_record_anchor_current a ON a.source_record_id = r.id AND a.decision_status = 'accepted'
  JOIN private.source_record_occurrence o ON o.id = a.occurrence_id
), bound AS (
  SELECT r.record_key, p.narrative_id, p.status
  FROM records r
  JOIN private.narrative_record_publication p ON p.source_record_id = r.id
), clause_rows AS (
  SELECT ac.record_key, c.clause_ordinal, jsonb_build_object(
    'record_key', ac.record_key,
    'clause_ordinal', c.clause_ordinal,
    'char_from', c.char_from, 'char_to', c.char_to,
    'post_char_from', c.post_char_from, 'post_char_to', c.post_char_to,
    'classification', c.clause_classification,
    'flags', c.clause_flags,
    'verbatim_sha256', encode(extensions.digest(convert_to(c.verbatim_text, 'UTF8'), 'sha256'), 'hex'),
    'parent_verbatim_sha256', encode(extensions.digest(convert_to(parent.verbatim_text, 'UTF8'), 'sha256'), 'hex'),
    'disposition', d.disposition,
    'disposition_version', d.version
  ) AS row
  FROM accepted ac
  JOIN private.source_observation c ON c.occurrence_id = ac.occurrence_id AND c.observation_kind = 'clause'
  JOIN private.source_observation parent ON parent.id = c.parent_observation_id
  LEFT JOIN private.clause_disposition_current d ON d.observation_id = c.id
), event_rows AS (
  SELECT e.element_id, jsonb_build_object(
    'manifest_sha256', b.manifest_sha256,
    'batch_status', b.status,
    'element_id', e.element_id,
    'source_record_key', e.source_record_key
  ) AS row
  FROM private.reimport_event e
  JOIN private.reimport_batch b ON b.id = e.batch_id
  JOIN guard g ON g.ok = 1 AND b.source_id = g.source_id
  WHERE e.operation = 'clause_evidence'
), canonical AS (
  SELECT jsonb_build_object(
    'person', (SELECT encode(extensions.digest(convert_to(coalesce(string_agg(x::text, E'\n' ORDER BY x::text COLLATE "C"), ''), 'UTF8'), 'sha256'), 'hex') FROM public.person x),
    'fact', (SELECT encode(extensions.digest(convert_to(coalesce(string_agg(x::text, E'\n' ORDER BY x::text COLLATE "C"), ''), 'UTF8'), 'sha256'), 'hex') FROM public.fact x),
    'assertion', (SELECT encode(extensions.digest(convert_to(coalesce(string_agg(x::text, E'\n' ORDER BY x::text COLLATE "C"), ''), 'UTF8'), 'sha256'), 'hex') FROM public.assertion x),
    'conclusion', (SELECT encode(extensions.digest(convert_to(coalesce(string_agg(x::text, E'\n' ORDER BY x::text COLLATE "C"), ''), 'UTF8'), 'sha256'), 'hex') FROM public.conclusion x),
    'narrative', (SELECT encode(extensions.digest(convert_to(coalesce(string_agg(x::text, E'\n' ORDER BY x::text COLLATE "C"), ''), 'UTF8'), 'sha256'), 'hex') FROM public.narrative x),
    'relation', (SELECT encode(extensions.digest(convert_to(coalesce(string_agg(x::text, E'\n' ORDER BY x::text COLLATE "C"), ''), 'UTF8'), 'sha256'), 'hex') FROM public.relation x),
    'family_member', (SELECT encode(extensions.digest(convert_to(coalesce(string_agg(x::text, E'\n' ORDER BY x::text COLLATE "C"), ''), 'UTF8'), 'sha256'), 'hex') FROM public.family_member x),
    'source_observation_non_clause', (SELECT encode(extensions.digest(convert_to(coalesce(string_agg(x::text, E'\n' ORDER BY x::text COLLATE "C"), ''), 'UTF8'), 'sha256'), 'hex') FROM private.source_observation x WHERE x.observation_kind <> 'clause')
  ) AS hashes
)
SELECT jsonb_build_object(
  'schema_version', 'daa-clause-evidence-projection-v1',
  'source_id', g.source_id,
  'database_target_identity', jsonb_build_object(
    'database_name', current_database(),
    'system_identifier_sha256', encode(extensions.digest(convert_to((pg_control_system()).system_identifier::text, 'UTF8'), 'sha256'), 'hex')
  ),
  'source_records', (SELECT coalesce(jsonb_agg(jsonb_build_object('record_key', record_key) ORDER BY record_key COLLATE "C"), '[]'::jsonb) FROM records),
  'source_anchors', (SELECT coalesce(jsonb_agg(jsonb_build_object('record_key', record_key, 'occurrence_key', occurrence_key) ORDER BY record_key COLLATE "C", occurrence_key COLLATE "C"), '[]'::jsonb) FROM accepted),
  'narrative_bindings', (SELECT coalesce(jsonb_agg(jsonb_build_object('record_key', record_key, 'narrative_id', narrative_id, 'status', status) ORDER BY record_key COLLATE "C", narrative_id, status COLLATE "C"), '[]'::jsonb) FROM bound),
  'narrative_sha256', (SELECT coalesce(jsonb_agg(jsonb_build_object('narrative_id', n.id, 'sha256', encode(extensions.digest(convert_to(n.tekst, 'UTF8'), 'sha256'), 'hex')) ORDER BY n.id), '[]'::jsonb)
                       FROM public.narrative n WHERE n.id IN (SELECT narrative_id FROM bound)),
  'persons', (SELECT coalesce(jsonb_agg(jsonb_build_object('person_id', q.person_id) ORDER BY q.person_id), '[]'::jsonb)
              FROM (SELECT DISTINCT n.subjekt_id AS person_id FROM public.narrative n
                    WHERE n.subjekt_type = 'person' AND n.id IN (SELECT narrative_id FROM bound)) q),
  'clauses', (SELECT coalesce(jsonb_agg(row ORDER BY record_key COLLATE "C", clause_ordinal), '[]'::jsonb) FROM clause_rows),
  'clause_evidence_events', (SELECT coalesce(jsonb_agg(row ORDER BY element_id COLLATE "C"), '[]'::jsonb) FROM event_rows),
  'canonical_sha256', canonical.hashes
) AS projection
FROM guard g, canonical
WHERE g.ok = 1;
```

Afvigelser fra runbookens 1939-snapshot, bevidst: bindinger tages for **alle** statusser (2018-20 har 46 `draft`, som ellers ville være usynlige), `status` er med i rækken, og narrativ-hashes/personer følger alle bundne narrativer.

- [ ] **Step 4: Kør integrationstesten igen**

Run (samme miljø som Step 2): `Rscript tests/integration/test-reimport-clause-evidence.R`
Expected: slutter med `clause_evidence integration OK`.

Hvis `set_config` via `dbGetQuery` ikke gælder for den efterfølgende sætning (fx fordi RPostgres åbner en ny transaktion), er symptomet `CLAUSE_PROJECTION_SOURCE_ID_MISSING`. Ret da hjælperen, så `SET TRANSACTION`, `set_config` og projektionen kører på samme forbindelse i samme `dbBegin`-blok (det er designet); ret aldrig SQL-guarden.

- [ ] **Step 5: Kør guard-negativerne direkte i psql**

```bash
psql -X -At -v ON_ERROR_STOP=1 -c "SET daa.projection_source_id='1'" -f .claude/skills/daa-extract/scripts/clause_evidence_projection.sql 2>&1 | grep -o 'CLAUSE_PROJECTION_[A-Z_]*'
PGOPTIONS='-c default_transaction_read_only=on' psql -X -At -v ON_ERROR_STOP=1 -c "SET daa.projection_source_id='1'" -f .claude/skills/daa-extract/scripts/clause_evidence_projection.sql 2>&1 | grep -o 'CLAUSE_PROJECTION_[A-Z_]*'
PGOPTIONS='-c default_transaction_read_only=on -c default_transaction_isolation=repeatable\ read' psql -X -At -v ON_ERROR_STOP=1 -f .claude/skills/daa-extract/scripts/clause_evidence_projection.sql 2>&1 | grep -o 'CLAUSE_PROJECTION_[A-Z_]*'
PGOPTIONS='-c default_transaction_read_only=on -c default_transaction_isolation=repeatable\ read' psql -X -At -q -v ON_ERROR_STOP=1 -c "SET daa.projection_source_id='1'" -f .claude/skills/daa-extract/scripts/clause_evidence_projection.sql | head -c 40; echo
```

Expected, i rækkefølge: `CLAUSE_PROJECTION_NOT_READ_ONLY`, `CLAUSE_PROJECTION_NOT_REPEATABLE_READ`, `CLAUSE_PROJECTION_SOURCE_ID_MISSING`, og til sidst begyndelsen af et JSON-objekt (`{"`). Denne base har ingen source 1, så de fem lister er tomme — det er her kun en syntaks- og guardtest.

- [ ] **Step 6: Ryd den disponerbare base op og commit**

```bash
dropdb "$(cat "${TMPDIR:-/tmp}/klausulproj-db-name.txt")" && rm "${TMPDIR:-/tmp}/klausulproj-db-name.txt"
git add .claude/skills/daa-extract/scripts/clause_evidence_projection.sql tests/integration/test-reimport-clause-evidence.R
git commit -m "feat(evidens): læse-kun klausul-projektion og ende-til-ende-test i CI (#195)"
```

(Basen er oprettet af denne task og indeholder kun syntetik; den må droppes uden yderligere bekræftelse.)

---

### Task 4: Runbook, beslutning og status

**Files:**
- Modify: `docs/runbooks/evidence-import-phase-gate.md` (ny sektion lige før `## Hvad denne gate ikke beviser`)
- Modify: `docs/decisions.md` (ny post øverst, lige under indledningen)
- Modify: `docs/evidensbaseret-genimport/status.md` (»Åbne blokeringer« og »Næste tilladte arbejde«)

**Interfaces:**
- Consumes: kommandoerne fra Task 2 og Task 3.
- Produces: den prod-procedure, som 4.1c's prod-GO henviser til.

- [ ] **Step 1: Tilføj runbook-sektionen**

Indsæt i `docs/runbooks/evidence-import-phase-gate.md` før `## Hvad denne gate ikke beviser`:

````markdown
## Klausul-projektion (udgaveneutral delta-afstemning, spec §11.1)

Gælder `clause_evidence`-kørsler (4.1c). Den afstemmer **én kørsels delta**, ikke
historien: den kender ingen udgave eller fase og afhænger ikke af
`reconcile_evidence_phase_gate.py`, som er låst til 1939/source 3 og ikke er i `main`.
Værktøjet er i `main`: `clause_evidence_projection.sql` og
`compare_clause_evidence_projection.py` (#195).

**Hvad et `match` beviser:**

1. De fem projektioner for kilden (records, accepterede ankre, narrativbindinger i alle
   statusser, narrativ-hashes, personer) er identiske før og efter.
2. Indholdet af `person`, `fact`, `assertion`, `conclusion`, `narrative`, `relation`,
   `family_member` og alle ikke-klausul-observationer er uændret — målt som indholds-hash
   pr. tabel, ikke antal.
3. Klausulrækkerne for manifestets records er præcis manifestets klausuler: spænd
   (rendition-absolut og helpost-relativ), klassifikation, flag, tekst-hash,
   helpost-hash og startdisposition (version 1).
4. Rækkerne kommer fra én `finalized` batch med manifestets `manifest_content_sha256`,
   én hændelse pr. record, og ingen anden klausul i kilden er ændret.

**Hvad det ikke beviser:** at prod er summen af tidligere faser; RLS/ACL (uændret DDL);
`anon`-synlighed ud over det, der følger af uændret indhold; andre skemaer end de nævnte.

**Procedure** (hver kørsel mod prod sker i projektejerens shell; sessionen læser kun de
private filer bagefter):

1. **Redaktionspause.** Ingen redigering i web-fladen fra før-projektion til
   efter-projektion — enhver kanonisk ændring i vinduet giver
   `CLAUSE_PROJECTION_CANONICAL_DRIFT` (fail-closed, ikke en fejl i værktøjet).
2. **Før-projektion** (efter backup og efter at writer-profilrækken for
   `daa-2018-20-clause-evidence-v1` er indsat — den findes ikke i prod pr. 2026-09-17 og
   ligger uden for projektionen — men før apply):

   ```bash
   umask 077; mkdir -p ~/.private/klausul-projektion-prod && chmod 700 ~/.private/klausul-projektion-prod
   PGOPTIONS='-c default_transaction_read_only=on -c default_transaction_isolation=repeatable\ read' \
     psql -X -At -q -v ON_ERROR_STOP=1 \
     -c "SET daa.projection_source_id='1'" \
     -f .claude/skills/daa-extract/scripts/clause_evidence_projection.sql \
     > ~/.private/klausul-projektion-prod/foer.json
   ```

3. Apply af 4.1c efter dens egen GO.
4. **Efter-projektion:** samme kommando til `efter.json`.
5. **Afstemning:**

   ```bash
   /usr/bin/python3 .claude/skills/daa-extract/scripts/compare_clause_evidence_projection.py \
     --manifest ~/.private/<4.1c-manifest>.json \
     --before ~/.private/klausul-projektion-prod/foer.json \
     --after ~/.private/klausul-projektion-prod/efter.json \
     --report ~/.private/klausul-projektion-prod/rapport.json
   ```

   `--allow-empty` må **ikke** bruges mod prod; det findes kun til CI's syntetiske
   kilde uden narrativer.
6. **Bestået** kræver exit 0, `"status": "match"` **og** at tællingerne i terminalen er
   lig rehearsalens (`records`, `clauses`, `dispositions`, `neutral_lists`) — se
   `docs/evidensbaseret-genimport/clause-evidence-148-rehearsal.md`, afsnit
   »Klausul-projektion«.
7. **NO-GO** (exit 1): bevar alle tre input og rapporten, læs kun fejlkoden og den private
   rapports nøgler/feltnavne, og stop. Reparér aldrig prod for at få `match`; vejen
   tilbage er restore (decisions 2026-09-17).
````

- [ ] **Step 2: Tilføj beslutningsposten**

Indsæt i `docs/decisions.md` lige efter indledningen (før `## BESLUTTET: 4.1c's klausulkørsel i prod fortrydes kun ved restore (2026-09-17)`):

```markdown
## BESLUTTET: klausul-projektionen er et udgaveneutralt delta-tjek, ikke en udvidelse af 1939-gaten (2026-09-17)

**Afgjort af projektejeren** (vej C af tre) for spec §11.1, issue #195.

**Baggrund.** Fase-pakke-runbookens værktøj (`reconcile_evidence_phase_gate.py` m.fl.,
~9.000 linjer) ligger kun på den umergede gren `codex/finish-156-158`. #170 udelod det
bevidst som udgavespecifikt og INCOMPLETE. Det er låst til 1939/source 3's otte
historiske faser (`HISTORICAL_PHASE_CONTRACTS`), mens 4.1c's 591 records er 2018-20
(source 1), skrevet af 149a/149b, som gaten ikke kender. En prøve-merge gav én
docs-konflikt og 215 grønne tests — koden virker, men passer ikke til opgaven.

**Valgt (C):** en læse-kun SQL-projektion + en komparator uden databaseadgang, som beviser
én kørsels delta: uændrede fem projektioner og kanonisk indhold, klausulrækker =
manifestet, binding til batchens manifest-hash.

**Fravalgt:**
- **A — håndskrevet bidrag i runbooken, som 149a/b.** Runbooken forbyder selv manuelt
  konstruerede bidrag; afstemningen ville være en erklæring, ikke et bevis.
- **B — merge og generalisér 1939-gaten.** Omgør #170, kræver et nyt historisk scope
  (149a → 149b → 4.1c), og 149a/b kan formentlig ikke bindes bagudrettet.

**Prisen, sagt højt:** C beviser ikke historisk fuldstændighed, og det kanoniske
indholds-hash gør tjekket følsomt for enhver redigering i vinduet (kræver redaktionspause).
Fortolknings-projektionen (4.4) er ikke med; den står i #196.

**Fund:** 4.1c-rehearsalens »kanonisk lag identisk« (`kanonisk()` i det private
apply-script) var en hash af `count(*)` pr. tabel. Den erstattes af indholds-hashen.
```

- [ ] **Step 3: Opdatér `status.md`**

I `docs/evidensbaseret-genimport/status.md`, afsnittet `## Åbne blokeringer`, erstat første punkt (det der begynder `- **Trin 4's skema er i prod, dets data er ikke.**`) med:

```markdown
- **Trin 4's skema er i prod, dets data er ikke.** Skema og writere deployet 2026-09-17.
  Første datakørsel er 4.1c (klausuler, nul kanonisk delta). Fortrydelseskvitteringen er
  givet (decisions 2026-09-17: fortryd = restore), og klausul-projektionen er defineret
  i fase-pakke-runbooken som et udgaveneutralt delta-tjek (#195). Tilbage før prod-GO:
  projektejerens GO pr. apply. Fortolknings-projektionen for 4.4 mangler (#196), og for
  `interpretation_proposal` findes ingen prod-fortrydelse (spec åbent punkt 11.5).
```

I `## Næste tilladte arbejde`, erstat punkt 2 med:

```markdown
2. **Trin 4's første datakørsel i prod: 4.1c** — forudsætningerne (kvittering og
   klausul-projektion) er på plads; kræver backup, rehearsal og projektejerens GO.
```

- [ ] **Step 4: Verificér at intet er forældet**

Run: `grep -n "klausul-projektion i fase-pakke-runbooken, som ikke findes" docs/evidensbaseret-genimport/status.md docs/database-current-state.md`
Expected: ingen træf i `status.md`. Træf i `docs/database-current-state.md` rettes i samme task med samme formulering som ovenfor (kvittering givet, projektion defineret, #195) — kun den ene sætning.

- [ ] **Step 5: Commit**

```bash
git add docs/runbooks/evidence-import-phase-gate.md docs/decisions.md docs/evidensbaseret-genimport/status.md
git add docs/database-current-state.md  # kun hvis Step 4 rettede den
git commit -m "docs(genimport): klausul-projektion i fase-pakke-runbooken og beslutning om vej C (#195)"
```

---

### Task 5: Rehearsal mod prod-tilstanden 2026-09-17

**Files:**
- Create (privat, ikke i git): `~/.private/klausul-projektion/rehearsal.sh`, artefakter under `~/.private/klausul-projektion/<db>/`
- Create (gitignoreret): `work/klausul-projektion/03-clause-dryrun.R`, `work/klausul-projektion/04-clause-apply.R` (kopier)
- Modify: `docs/evidensbaseret-genimport/clause-evidence-148-rehearsal.md`, `docs/changelog.md`

**Interfaces:**
- Consumes: Task 2's CLI, Task 3's SQL, template-basen `daa_trin4_rehearsal_20260917141446` (se »Vigtige fakta«), manifest `~/.private/148c-manifest-20260910190838.json`, 4.1c's scripts `~/.private/148-rehearsal-scripts/03-clause-dryrun.R` og `04-clause-apply.R`.
- Produces: tal til runbookens bestået-kriterie (Task 4, Step 1, punkt 6).

Alt sker lokalt mod engangskopier af template-basen. Intet mod prod. Kun tal, koder og hashes i rapport og chat.

- [ ] **Step 1: Forbered**

```bash
umask 077
mkdir -p ~/.private/klausul-projektion work/klausul-projektion && chmod 700 ~/.private/klausul-projektion
cp ~/.private/148-rehearsal-scripts/03-clause-dryrun.R work/klausul-projektion/03-clause-dryrun.R
cp ~/.private/148-rehearsal-scripts/04-clause-apply.R work/klausul-projektion/04-clause-apply.R
shasum -a 256 ~/.private/148c-manifest-20260910190838.json
psql -X -At -d postgres -c "SELECT count(*) FROM pg_stat_activity WHERE datname='daa_trin4_rehearsal_20260917141446'"   # skal være 0
```

Scripts finder repoet som `../..` fra deres egen placering; derfor kopierne under `work/klausul-projektion/`. `createdb -T` fejler, hvis template-basen har åbne forbindelser.

- [ ] **Step 2: Skriv rehearsal-scriptet**

`~/.private/klausul-projektion/rehearsal.sh`:

```zsh
#!/bin/zsh
# Klausul-projektion (#195): rehearsal mod prod-tilstanden 2026-09-17
# (engangskopi af restore + trin 4-migrationer). Alt lokalt. Printer kun tal, koder og hashes.
set -euo pipefail
umask 077
export PGTZ=UTC PGHOST=localhost PGPORT=5432
PG=/opt/homebrew/opt/postgresql@17/bin
REPO=/Users/johanreventlow/TypeScript/danmarksadelsaarbog/.claude/worktrees/klausul-projektion
TEMPLATE=daa_trin4_rehearsal_20260917141446
MANIFEST=$HOME/.private/148c-manifest-20260910190838.json
SQL=$REPO/.claude/skills/daa-extract/scripts/clause_evidence_projection.sql
CMP=$REPO/.claude/skills/daa-extract/scripts/compare_clause_evidence_projection.py
DB="klausulproj_rehearsal_$(date +%Y%m%d%H%M%S)"
ART=$HOME/.private/klausul-projektion/$DB
mkdir -p "$ART" && chmod 700 "$ART"
cd "$REPO"

project() {  # $1 = database, $2 = outputfil
  PGOPTIONS='-c default_transaction_read_only=on -c default_transaction_isolation=repeatable\ read' \
    $PG/psql -X -At -q -v ON_ERROR_STOP=1 -d "$1" -c "SET daa.projection_source_id='1'" -f "$SQL" > "$2"
  chmod 600 "$2"
}

baseline() {
  $PG/psql -X -At -d "$DB" -c "SELECT (SELECT count(*) FROM private.source_observation WHERE observation_kind='person_post'),
    (SELECT count(*) FROM private.source_observation WHERE observation_kind='clause'),
    (SELECT count(*) FROM private.reimport_writer_profile WHERE source_id=1 AND profile_id='daa-2018-20-clause-evidence-v1')"
}

echo "== kopi af template -> $DB =="
$PG/createdb -T "$TEMPLATE" "$DB"

echo "== udgangspunkt (forventet 591|0|0) =="
baseline

echo "== dry-run (4.1c-scriptet; indsætter writer-profilrækken, ruller data tilbage) =="
PGDATABASE="$DB" PGUSER=$(whoami) Rscript work/klausul-projektion/03-clause-dryrun.R "$MANIFEST" 2>&1 \
  | grep -E '^== |DRY_RUN_OK|Error' || true

echo "== efter dry-run (forventet 591|0|1) =="
baseline

echo "== før-projektion =="
project "$DB" "$ART/foer.json"
shasum -a 256 "$ART/foer.json"

echo "== apply (4.1c-scriptet, med eget replay) =="
PGDATABASE="$DB" PGUSER=$(whoami) Rscript work/klausul-projektion/04-clause-apply.R "$MANIFEST" 2>&1 \
  | grep -E '^== |APPLY_OK|Error' || true

echo "== efter-projektion =="
project "$DB" "$ART/efter.json"
shasum -a 256 "$ART/efter.json"

echo "== afstemning (forventet exit 0, match) =="
/usr/bin/python3 "$CMP" --manifest "$MANIFEST" --before "$ART/foer.json" --after "$ART/efter.json" \
  --report "$ART/rapport-match.json" && echo "exit=0" || echo "exit=$?"

echo "== negativ 1: ændret occurrence_key på én accepteret forekomst (forventet NEUTRALITY_DRIFT) =="
$PG/createdb -T "$DB" "${DB}_neg1"
$PG/psql -X -q -v ON_ERROR_STOP=1 -d "${DB}_neg1" -c "SET session_replication_role = replica;
  UPDATE private.source_record_occurrence SET occurrence_key = occurrence_key || '-neg'
   WHERE id = (SELECT a.occurrence_id FROM private.source_record_anchor_current a
                 JOIN private.source_record r ON r.id = a.source_record_id
                WHERE r.source_id = 1 AND a.decision_status = 'accepted'
                ORDER BY r.record_key COLLATE \"C\" LIMIT 1);"
project "${DB}_neg1" "$ART/efter-neg1.json"
/usr/bin/python3 "$CMP" --manifest "$MANIFEST" --before "$ART/foer.json" --after "$ART/efter-neg1.json" \
  --report "$ART/rapport-neg1.json" || echo "exit=$?"

echo "== negativ 2: én family_member-række slettet (forventet CANONICAL_DRIFT) =="
$PG/createdb -T "$DB" "${DB}_neg2"
$PG/psql -X -q -v ON_ERROR_STOP=1 -d "${DB}_neg2" -c "SET session_replication_role = replica;
  DELETE FROM public.family_member WHERE ctid = (SELECT ctid FROM public.family_member LIMIT 1);"
project "${DB}_neg2" "$ART/efter-neg2.json"
/usr/bin/python3 "$CMP" --manifest "$MANIFEST" --before "$ART/foer.json" --after "$ART/efter-neg2.json" \
  --report "$ART/rapport-neg2.json" || echo "exit=$?"

echo "== databaser: $DB ${DB}_neg1 ${DB}_neg2 (bevares til rapporten er skrevet) =="
echo REHEARSAL_DONE
```

`session_replication_role = replica` slår triggere og FK fra i den ene session på de disponerbare kopier, så mutationen ikke stoppes af en guard. Det er kun for at fremkalde en ægte ændring i en engangsbase.

- [ ] **Step 3: Kør rehearsal**

Run: `zsh ~/.private/klausul-projektion/rehearsal.sh > ~/.private/klausul-projektion/rehearsal.log 2>&1; echo "exit=$?"; grep -cE 'STOPPORT|Error' ~/.private/klausul-projektion/rehearsal.log`
Derefter: `grep -E '^== |^exit=|^\{"|APPLY_OK|REHEARSAL_DONE|^[0-9|]+$|^restore-fejl|^[0-9a-f]{64} ' ~/.private/klausul-projektion/rehearsal.log` (logget indeholder kun tal, koder og hashes, men læs det filtreret).

Expected:
- udgangspunkt `591|0|0`; `DRY_RUN_OK`; efter dry-run `591|0|1`
- `APPLY_OK`
- afstemning: `{"counts": {"allowed_empty": [], "clauses": 868, "dispositions": {"afventer_fortolkning": 617, "maskinelt_flagget": 251}, "neutral_lists": {"narrative_bindings": 587, "narrative_sha256": 587, "persons": 587, "source_anchors": 591, "source_records": 591}, "records": 591}, …, "status": "match"}` og `exit=0`
- negativ 1: `{"code": "CLAUSE_PROJECTION_NEUTRALITY_DRIFT", "status": "no_go"}`, `exit=1`
- negativ 2: `{"code": "CLAUSE_PROJECTION_CANONICAL_DRIFT", "status": "no_go"}`, `exit=1`

**Stopporte:** udgangspunkt ≠ `591|0|0`, ingen `DRY_RUN_OK`, efter dry-run ≠ `591|0|1`, ingen `APPLY_OK`, eller afstemningen ≠ `match` → stop, kør ikke videre, rapportér fejlkoden og (kun) nøglerne `details.*`'s længder fra den private rapport. Hvis en negativ ikke giver sin forventede kode, er det et fund i værktøjet — stop og rapportér, ret ikke forventningen.

- [ ] **Step 4: Skriv rapportafsnittet**

Tilføj nederst i `docs/evidensbaseret-genimport/clause-evidence-148-rehearsal.md` et afsnit `## Klausul-projektion (#195) — rehearsal 2026-09-17` med de faktisk målte værdier (ikke de forventede): dump-SHA, manifest-SHA, `foer.json`/`efter.json`-SHA'er, udgangspunkt, terminal-JSON for match, de to negative koder. Tilføj en sætning i 4.1c-afsnittets »Intet kanonisk delta«-punkt: *»NB: målt som antal pr. tabel; indholdsbeviset er klausul-projektionen nedenfor.«*

- [ ] **Step 5: Changelog**

Tilføj øverst i `docs/changelog.md` (under `# Changelog`):

```markdown
## 2026-09-17 — Klausul-projektion: udgaveneutralt delta-tjek til 4.1c (#195)

Spec §11.1's klausul-projektion er bygget som vej C: en læse-kun SQL-projektion og en
komparator uden databaseadgang. De beviser, at én `clause_evidence`-kørsel skrev præcis
manifestets klausuler og intet andet. Fortolknings-projektionen er udskudt til #196.

**Fund til 4.1c's prod-kørsel:** writer-profilrækken for `daa-2018-20-clause-evidence-v1`
findes ikke i prod; 4.1c's dry-run-script indsætter den. Det er en prod-skrivning, der
skal med i 4.1c's GO.

**Rehearsal** mod prod-tilstanden 2026-09-17 (restore + trin 4-migrationer): `match` med <records> records og
<clauses> klausuler; en ændret forekomstnøgle gav `NEUTRALITY_DRIFT`, en slettet
`family_member`-række `CANONICAL_DRIFT`. Tal: `clause-evidence-148-rehearsal.md`.

**Fund:** 4.1c-rehearsalens »kanonisk lag identisk« var en hash af antal rækker. Den nye
projektion hasher indholdet.
```

Erstat `<records>` og `<clauses>` med de målte tal fra Step 3.

- [ ] **Step 6: Commit**

```bash
git add docs/evidensbaseret-genimport/clause-evidence-148-rehearsal.md docs/changelog.md
git commit -m "docs(genimport): rehearsal af klausul-projektionen mod prod-restore (#195)"
```

- [ ] **Step 7: Oprydning (efter commit)**

De tre rehearsal-baser er engangskopier oprettet af denne task: `dropdb` dem (`$DB`, `${DB}_neg1`, `${DB}_neg2`; navnene står i loggen). `~/.private/klausul-projektion/` bevares (projektioner + rapporter bruges som reference ved prod-kørslen). `work/klausul-projektion/` må slettes. Template-basen `daa_trin4_rehearsal_20260917141446` røres ikke af denne task; om den skal slettes, afgør projektejeren.

---

## Selvtjek mod spec

| Krav | Task |
| --- | --- |
| §11.1: klausul-projektion defineret før 4.1c-afstemning i prod | 3 (projektion), 4 (runbook) |
| §11.1: issue før første prod-GO | #195 (oprettet 2026-09-17), #196 for fortolkning |
| §4.1.5: bidraget erklærer nul ændring i de fem projektioner | 1 (`NEUTRALITY_DRIFT`), 5 (målt) |
| §4.1.6: neutralitetshashes uændrede | 1 (`CANONICAL_DRIFT`), 3 (indholds-hash), 5 (negativ 2) |
| §4.1.6: antal klausulrækker = ledgerens | skærpet til identitet felt for felt, 1 (`DRIFT`), 5 (868) |
| §4.1.6: replay `already_applied` | 3 (projektion uændret efter replay) |
| §4.1.4: ekstern nøgle `(record_key, ordinal, verbatim_sha256)` | 1 (nøgle `(record_key, clause_ordinal)` + `verbatim_sha256` felt) |
| Ingen tekst ud af DB | 3 (hash i SQL), 2 (stdout uden details) |

Ikke dækket, bevidst: `anon`-synlighed som særskilt hash (RLS/DDL uændret; indhold dækket), historisk fuldstændighed, fortolkninger (#196).
