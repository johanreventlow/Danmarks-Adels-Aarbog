# Trin 4 · klausul-projektion: udgaveneutral delta-afstemning af 4.1c — implementeringsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Gør det muligt at bevise, at én `clause_evidence`-kørsel (4.1c) skrev præcis manifestets klausuler med writerens invarianter, bundet til én batch og den godkendte database, og at intet i de projekterede neutrale tabeller, i det `anon` ser, i kildens øvrige klausuler eller i ældre klausul-hændelser ændrede sig — så spec §11.1's klausul-projektion findes før 4.1c's prod-GO (#195). Writerens øvrige bogføring (autorisation, batch, kørsel) afstemmes kun i de projekterede felter.

**Architecture:** En psql-driver tager i ÉN `READ ONLY`/`REPEATABLE READ`-transaktion en projektion som databaseejer og en `anon`-projektion under `SET LOCAL ROLE anon`, og udskriver én JSON. Den tages før og efter apply. En Python-komparator uden databaseadgang sammenholder de to med det autoriserede manifest og en på forhånd godkendt målidentitet og svarer `match` eller NO-GO med en fejlkode. Tjekket er et *delta*-bevis: det kender ingen udgave, fase eller historik og importerer intet fra den 1939-låste reconciler på `codex/finish-156-158`.

**Tech Stack:** PostgreSQL 17 (ren SQL, indbygget `pg_catalog.sha256`), psql, Python 3.9+ kun standardbibliotek (pytest til tests), R + DBI/RPostgres (integrationstest), GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-09-06-trin4-fortolkningskaede-og-klausulgranularitet-design.md` §4.1.4-4.1.6 og §11.1. Afgørelsen (vej C) står i `docs/decisions.md` (Task 4) og i issue #195. Fortolknings-projektionen er udskudt til #196.

**Revision 4 (2026-09-17)** efter tre Codex `gpt-5.6-sol`-runder (runde 1: NO-GO, 7 BLOCKER / 3 MAJOR; runde 2: NO-GO, 1 ny BLOCKER + 5 delvist lukkede; runde 3: NO-GO, alt lukket på nær hændelsernes helrækkehash). Afgørelserne står i »Revisionslog« nederst.

## Global Constraints

- **Ingen kildetekst forlader databasen.** Al tekst hashes i SQL med `pg_catalog.sha256(convert_to(…,'UTF8'))` (indbygget, kræver ingen extension og virker for `anon`). Ingen tekst i JSON, logs, rapporter, commit-beskeder eller issues.
- Projektioner og rapporter fra rigtige baser er private: `~/.private/…`, mapper 0700, filer 0600, aldrig committet, aldrig overskrevet (ny run-mappe pr. forsøg). Test-fixtures er syntetiske.
- Komparatoren åbner aldrig en database. Projektionen kører kun i `READ ONLY` + `REPEATABLE READ` og håndhæver det selv; `anon`-delen håndhæver desuden `current_user = 'anon'`.
- Udgaveneutral: ingen `1939`/`2018`-strenge i kode, ingen fase-id'er, ingen import fra `reconcile_evidence_phase_gate.py` eller `*_1939_v50`-scripts.
- Sammenlign **mængder og indhold, aldrig antal.** Neutralitet = helrækkehash pr. tabel.
- **Afstemt delta** for en `clause_evidence`-kørsel: kildens nye klausul-observationer og deres dispositioner (felt for felt + invarianter) og de nye `clause_evidence`-hændelser (præcis én batch; alle ældre hændelser bevaret uændret). **Ikke afstemt ud over de projekterede felter:** `private.reimport_authorization`, `private.reimport_batch`, `private.extraction_run` — dér bevises kun målbatchens status, manifest- og profilhash samt målkørslens proveniensfelter, ikke fravær af andre ændringer. `private.reimport_writer_profile` ændres *før* før-projektionen og er ikke en del af deltaet. Alt i de hashede tabeller skal være uændret.
- SQL-filerne `clause_evidence_*.sql` er hver én sætning **uden** afsluttende semikolon og uden `;` eller `'` i kommentarer (driveren interpolerer dem; R kører dem direkte).
- Sortering i SQL: `ORDER BY … COLLATE "C"` på tekst (CI kører `en_US`). Komparatoren sammenligner kanonisk sorteret.
- Python skal køre på `/usr/bin/python3` 3.9 og CI's 3.11: `from __future__ import annotations`, ingen `match`, ingen runtime-`X | Y`.
- Ingen prod-handling i denne plan. Rehearsal kun mod lokale engangskopier. Ingen ny DDL; `schema.sql`/`db-migrations.sql`/`db-rls.sql` røres ikke.
- Commits: ét pr. task, dansk Conventional Commit, ingen push. Gren `feat/148-klausul-projektion` (worktree `.claude/worktrees/klausul-projektion`).

## Roadmappens seks adgangskrav

1. **Roadmapmål:** trin 4, #148 → prod-forudsætning for 4.1c (#195).
2. **Værdikædeled:** afstemning af `klausulobservationer` efter prod-skrivning.
3. **Generel/profil/legacy:** generel (udgaveneutral); ingen profil.
4. **Redaktionel værdi:** projektejeren kan give prod-GO til klausulkørslen med et mekanisk bevis for, at intet uden for det tilladte delta ændrede sig — heller ikke det, offentligheden (`anon`) ser.
5. **Bevis:** pytest-cases for hver fejlkode; CI-integration med match, manipuleret projektion og guard-afvisninger; rehearsal mod prod-tilstanden 2026-09-17: `match` med 591 records / 868 klausuler og to ægte negative mutationer med eksakt fejlkode, alt maskinelt asserteret.
6. **Erstatter:** 4.1c-rehearsalens antal-baserede `kanonisk()`-hash som neutralitetsbevis.

## Vigtige fakta (målt 2026-09-17)

Mod `daa_trin4_rehearsal_20260917141446` (se »Rehearsal-basen«), source 1 = 2018-20:

| Måling | Værdi |
| --- | --- |
| `source_record` / accepterede ankre | 591 / 591 |
| `narrative_record_publication`-rækker (alle statusser) | 587 (541 `published`, 46 `draft`) |
| bundne narrativer / personer | 587 / 587 |
| `person_post`-observationer / klausuler | 591 / 0 |
| `anon` ser (person/fact/assertion/conclusion/narrative/family_member/citation/person_external_id) | 1734/6864/8944/8857/1115/2163/8222/1113 — RLS-filtreret |
| `anon` kan kalde `pg_control_system()` og `pg_catalog.sha256` | ja / ja |
| Helrækkehash over 8 tabeller | 0,5 s |
| psql `\gset` over `SET LOCAL ROLE anon` i én transaktion, SQL indlæst via backtick-variabel | virker |

- **Rehearsal-basen.** Dumpet `daa-prod-20260917141330.dump` er backuppen taget *før* trin 4's DDL-deploy. `daa_trin4_rehearsal_20260917141446` er dumpet + `db-migrations.sql` + `db-rls.sql` som prod fik dem 2026-09-17, verificeret med db-verify og kontrakttests. Den bruges som **template** (`createdb -T`) og må ikke droppes før Task 5 er færdig.
- **Writer-profilrækken** `(1, 'daa-2018-20-clause-evidence-v1')` findes ikke i den migrerede base og dermed ikke i prod. 4.1c's dry-run-script (`~/.private/148-rehearsal-scripts/03-clause-dryrun.R`) indsætter den — en varig skrivning. I prod hører den under 4.1c's egen GO-pakke (se Task 4).
- **`SET ROLE anon` er aldrig kørt mod prod-forbindelsen** (trin 4's prod-verify brugte kun `has_*_privilege`). Runbooken får et preflight-tjek.
- **4.1c-manifestet** `~/.private/148c-manifest-20260910190838.json`: builderens hash genberegnes korrekt (`0b31c5a2…`); topnøgler `expected_counts, manifest_content_sha256, operations, provenance, source`; `source` = `id, profile_id, profile_sha256`; operationer har præcis 11 nøgler; én `clause_rules_version` (`clause-rules-2018-20-v2`).
- **Writerens INSERT** (`private.write_clause_evidence` i `db-migrations.sql`): klausulen får forælderens `occurrence_id`, `page_from/page_to` og `quality_status`; `extraction_method` = profilens præfiks `||':'||clause_rules_version`; `extraction_run_id` = kørsel med `input_sha256` = batchens `manifest_sha256` og `manifest` = `{batch_id, profile_sha256}`; `char_from/char_to` = manifestets `rendition_char_from/to`; `post_char_from/to` = manifestets `char_from/to`; disposition version 1, `decided_by_kind='machine'`, `evidence` = `{batch_id, element_id, manifest_sha256, clause_rules_version}`; disposition = `strukturel` hvis `structural_header`, ellers `maskinelt_flagget` hvis flag, ellers `afventer_fortolkning`.
- Ankerhændelserne ligger i `private.source_record_anchor_event` (viewet `source_record_anchor_current` er afledt).

## Projektionens JSON (schema `daa-clause-evidence-projection-v1`)

Alle nøgler obligatoriske, ingen ekstra:

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
  "clauses": [{
    "observation_id": "<uuid>", "row_sha256": "<64 hex>", "disposition_history_sha256": "<64 hex>",
    "run_id": "<uuid>", "run_matches_profile": true, "extraction_method_matches_profile": true,
    "record_key": "… eller null", "occurrence_key": "…", "clause_ordinal": 1,
    "char_from": 100, "char_to": 110, "post_char_from": 0, "post_char_to": 10,
    "classification": "record_text", "flags": [],
    "verbatim_sha256": "<64 hex>", "parent_verbatim_sha256": "<64 hex eller null>",
    "disposition": "afventer_fortolkning", "disposition_version": 1,
    "decided_by_kind": "machine",
    "disposition_evidence": {"batch_id": "…", "element_id": "clause-evidence:…", "manifest_sha256": "…", "clause_rules_version": "…"},
    "extraction_method": "…:…", "run_input_sha256": "<64 hex>", "run_batch_id": "…",
    "same_occurrence_as_parent": true, "parent_is_root": true,
    "pages_match_parent": true, "quality_matches_parent": true
  }],
  "clause_evidence_events": [{"batch_id": "…", "manifest_sha256": "<64 hex>", "batch_status": "finalized",
                              "profile_id": "…", "profile_sha256": "<64 hex>", "row_sha256": "<64 hex>",
                              "element_id": "clause-evidence:…", "source_record_key": "…"}],
  "neutral_sha256": {"person": "…", "fact": "…", "assertion": "…", "conclusion": "…", "narrative": "…",
                     "relation": "…", "family_member": "…", "citation": "…", "person_external_id": "…",
                     "source_mention": "…", "source_record": "…", "source_record_occurrence": "…",
                     "source_record_anchor_event": "…", "narrative_record_publication": "…",
                     "source_observation_non_clause": "…", "source_observation_clause_other_sources": "…",
                     "clause_disposition_other_sources": "…"},
  "anon_sha256": {"assertion": "…", "citation": "…", "conclusion": "…", "fact": "…",
                  "family_member": "…", "narrative": "…", "person": "…", "person_external_id": "…"}
}
```

`clauses` er **hele** kildens klausulinventar (scoped via `extraction_run.source_id`), ikke kun klausuler under accepterede forekomster; `record_key` er `null`, når forekomsten ikke har ét accepteret anker. Identitet: `observation_id` (stabil inden for databasen mellem før og efter). `row_sha256` er hash af hele observationsrækken, `disposition_history_sha256` af hele klausulens dispositionshistorik — så fremmede klausuler sammenlignes på fuldt indhold, ikke kun de projekterede felter. `run_matches_profile` og `extraction_method_matches_profile` beregnes i SQL mod den writer-profil, målbatchen er bundet til. Hændelser har identiteten `(batch_id, element_id)`.

**Målidentitet:** `database_target_sha256 = sha256(database_name + "\n" + system_identifier_sha256)` (UTF-8, hex). SQL-versionen står i `clause_evidence_target_identity.sql`.

## Filoversigt

- Create: `.claude/skills/daa-extract/scripts/compare_clause_evidence_projection.py` — komparator + CLI.
- Create: `.claude/skills/daa-extract/scripts/test_compare_clause_evidence_projection.py` — pytest.
- Create: `.claude/skills/daa-extract/scripts/clause_evidence_projection.sql` — ejer-projektion (én sætning).
- Create: `.claude/skills/daa-extract/scripts/clause_evidence_anon_projection.sql` — `anon`-hashes (én sætning).
- Create: `.claude/skills/daa-extract/scripts/clause_evidence_target_identity.sql` — målidentitetens hash.
- Create: `.claude/skills/daa-extract/scripts/clause_evidence_projection.psql` — driveren.
- Modify: `tests/integration/test-reimport-clause-evidence.R` — før/efter via driveren + komparator i CI.
- Modify: `.github/workflows/ci.yml` — pytest-fillisten.
- Modify: `docs/runbooks/evidence-import-phase-gate.md`, `docs/decisions.md`, `docs/evidensbaseret-genimport/status.md`, `docs/evidensbaseret-genimport/clause-evidence-148-rehearsal.md`, `docs/changelog.md`.

---

### Task 1: Komparatorens kerne (Python, ren funktion)

**Files:**
- Create: `.claude/skills/daa-extract/scripts/compare_clause_evidence_projection.py`
- Create: `.claude/skills/daa-extract/scripts/test_compare_clause_evidence_projection.py`
- Modify: `.github/workflows/ci.yml` (pytest-linjen i jobbet `evidence contract · pytest`)

**Interfaces:**
- Consumes: manifestformatet fra `build_clause_evidence_manifest.py` og projektionens JSON ovenfor.
- Produces:
  - Konstanter `PROJECTION_SCHEMA`, `RESULT_SCOPE = "clause-evidence-delta-v1"`, `NEUTRAL_LISTS`, `NEUTRAL_HASH_TABLES`, `ANON_HASH_TABLES`, `CLAUSE_FIELDS`, `EXPECTED_FIELDS`, `EVENT_FIELDS`.
  - `class ProjectionError(ValueError)` med `.code` og `.details` (kun nøgler, feltnavne og antal — aldrig værdier).
  - `compute_manifest_sha256(manifest: dict) -> str` — præcis builderens formel.
  - `target_sha256(identity: dict) -> str`
  - `expected_clauses(manifest: dict) -> dict[tuple[str, int], dict]` (validerer manifestet inkl. hash)
  - `compare(manifest, before, after, expected_target_sha256: str, allow_empty: frozenset[str] = frozenset()) -> dict`
  - Fejlkoder: `CLAUSE_PROJECTION_SHAPE_INVALID`, `…_DUPLICATE_ROW`, `…_EMPTY_LIST`, `…_MANIFEST_INVALID`, `…_MANIFEST_HASH_MISMATCH`, `…_SOURCE_MISMATCH`, `…_TARGET_MISMATCH`, `…_TARGET_UNEXPECTED`, `…_RECORD_UNKNOWN`, `…_NEUTRALITY_DRIFT`, `…_CANONICAL_DRIFT`, `…_ANON_DRIFT`, `…_PREEXISTING`, `…_FOREIGN_DRIFT`, `…_EVENT_HISTORY_DRIFT`, `…_BATCH_BINDING_INVALID`, `…_DRIFT`, `…_WRITER_INVARIANT_INVALID` (alle med præfiks `CLAUSE_PROJECTION_`).

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

BATCH = "00000000-0000-4000-8000-00000000b001"


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


def rehash(m):
    m["manifest_content_sha256"] = cp.compute_manifest_sha256(m)
    return m


def manifest():
    return rehash({
        "source": {"id": 1, "profile_id": "p", "profile_sha256": H("b")},
        "provenance": {"ledger_file_sha256": H("a")},
        "expected_counts": {"source_evidence": 0, "person_creates": 0,
                            "canonical_delta": 0, "clause_evidence": 2},
        "operations": [
            operation("R1", H("2"), [clause(1, 0, 10, 100, 110, [], H("3")),
                                     clause(2, 11, 20, 111, 121, ["short_clause"], H("4"))]),
            operation("R2", H("5"), [clause(1, 0, 5, 200, 205, [], H("6"))]),
        ],
    })


IDENTITY = {"database_name": "fixture", "system_identifier_sha256": H("7")}
TARGET = cp.target_sha256(IDENTITY)
OCCURRENCE = {"R1": "o1", "R2": "o2", "R9": "o9"}


def projection(clauses=(), events=()):
    return {
        "schema_version": cp.PROJECTION_SCHEMA,
        "source_id": 1,
        "database_target_identity": dict(IDENTITY),
        "source_records": [{"record_key": "R1"}, {"record_key": "R2"}, {"record_key": "R9"}],
        "source_anchors": [{"record_key": k, "occurrence_key": v} for k, v in OCCURRENCE.items()],
        "narrative_bindings": [{"record_key": "R1", "narrative_id": 7, "status": "published"}],
        "narrative_sha256": [{"narrative_id": 7, "sha256": H("8")}],
        "persons": [{"person_id": 42}],
        "clauses": [copy.deepcopy(c) for c in clauses],
        "clause_evidence_events": [copy.deepcopy(e) for e in events],
        "neutral_sha256": {t: H("0") for t in cp.NEUTRAL_HASH_TABLES},
        "anon_sha256": {t: H("1") for t in cp.ANON_HASH_TABLES},
    }


RUN = "00000000-0000-4000-8000-0000000000e1"


def written_rows(m, batch=BATCH):
    rules = {op["source_record_key"]: op["clause_rules_version"] for op in m["operations"]}
    rows = []
    for (key, ordinal), row in sorted(cp.expected_clauses(m).items()):
        rows.append(dict(row, occurrence_key=OCCURRENCE[key], decided_by_kind="machine",
                         observation_id=f"obs-{key}-{ordinal}", row_sha256=H("a"),
                         disposition_history_sha256=H("b"), run_id=RUN,
                         run_matches_profile=True, extraction_method_matches_profile=True,
                         disposition_evidence={"batch_id": batch, "element_id": f"clause-evidence:{key}",
                                               "manifest_sha256": m["manifest_content_sha256"],
                                               "clause_rules_version": rules[key]},
                         extraction_method=f"clause_segment_v1:{rules[key]}",
                         run_input_sha256=m["manifest_content_sha256"], run_batch_id=batch,
                         same_occurrence_as_parent=True, parent_is_root=True,
                         pages_match_parent=True, quality_matches_parent=True))
    return rows


def events_for(m, status="finalized", batch=BATCH):
    return [{"batch_id": batch, "manifest_sha256": m["manifest_content_sha256"], "batch_status": status,
             "profile_id": m["source"]["profile_id"], "profile_sha256": m["source"]["profile_sha256"],
             "row_sha256": H("e"),
             "element_id": op["element_id"], "source_record_key": op["source_record_key"]}
            for op in m["operations"]]


OLD_EVENT = {"batch_id": "00000000-0000-4000-8000-00000000b0dd", "manifest_sha256": H("c"),
             "batch_status": "finalized", "profile_id": "p", "profile_sha256": H("b"),
             "row_sha256": H("f"), "element_id": "clause-evidence:R9", "source_record_key": "R9"}


def applied(m):
    return projection(written_rows(m), events_for(m))


def run(m, before, after, target=TARGET, allow_empty=frozenset()):
    return cp.compare(m, before, after, target, allow_empty)


def no_go(m, before, after, target=TARGET, allow_empty=frozenset()):
    with pytest.raises(cp.ProjectionError) as e:
        run(m, before, after, target, allow_empty)
    return e.value


def foreign(ordinal=1, sha=H("f"), record_key="R9", occurrence_key="o9", observation_id="obs-foreign",
            row_sha=H("c"), history_sha=H("d")):
    return {"observation_id": observation_id, "row_sha256": row_sha, "disposition_history_sha256": history_sha,
            "run_id": "run-old", "run_matches_profile": True, "extraction_method_matches_profile": True,
            "record_key": record_key, "occurrence_key": occurrence_key, "clause_ordinal": ordinal,
            "char_from": 900, "char_to": 910, "post_char_from": 0, "post_char_to": 10,
            "classification": "record_text", "flags": [], "verbatim_sha256": sha,
            "parent_verbatim_sha256": H("e"), "disposition": "afventer_fortolkning",
            "disposition_version": 1, "decided_by_kind": "machine",
            "disposition_evidence": {"batch_id": "old"}, "extraction_method": "x:y",
            "run_input_sha256": H("9"), "run_batch_id": "old",
            "same_occurrence_as_parent": True, "parent_is_root": True,
            "pages_match_parent": True, "quality_matches_parent": True}


# ---- match og manifest -------------------------------------------------------

def test_match_counts_and_reports_target():
    m = manifest()
    result = run(m, projection(), applied(m))
    assert result["status"] == "match"
    assert result["scope"] == cp.RESULT_SCOPE
    assert result["database_target_sha256"] == TARGET
    assert result["batch_id"] == BATCH
    assert result["counts"]["records"] == 2
    assert result["counts"]["clauses"] == 3
    assert result["counts"]["dispositions"] == {"afventer_fortolkning": 2, "maskinelt_flagget": 1}
    assert result["counts"]["neutral_lists"]["source_records"] == 3


def test_compute_manifest_sha256_matches_builder_formula():
    import hashlib
    import json
    m = manifest()
    body = {k: v for k, v in m.items() if k != "manifest_content_sha256"}
    expected = hashlib.sha256(json.dumps(body, ensure_ascii=False, sort_keys=True,
                                         separators=(",", ":")).encode("utf-8")).hexdigest()
    assert cp.compute_manifest_sha256(m) == expected


def test_expected_clauses_maps_offsets_and_disposition_rule():
    m = manifest()
    m["operations"][1]["clauses"][0].update(classification="structural_header", flags=["x"])
    rows = cp.expected_clauses(rehash(m))
    r1 = rows[("R1", 1)]
    assert (r1["char_from"], r1["char_to"]) == (100, 110)
    assert (r1["post_char_from"], r1["post_char_to"]) == (0, 10)
    assert r1["parent_verbatim_sha256"] == H("2")
    assert r1["disposition_version"] == 1
    assert rows[("R1", 2)]["disposition"] == "maskinelt_flagget"
    assert rows[("R2", 1)]["disposition"] == "strukturel"


@pytest.mark.parametrize("mutate", [
    lambda m: m["provenance"].update(ledger_file_sha256=H("9")),
    lambda m: m["operations"][0].update(ledger_sha256=H("9")),
    lambda m: m["operations"][0].update(gap_charset=[" ", "\t"]),
    lambda m: m["source"].update(profile_sha256=H("9")),
])
def test_non_row_field_changed_without_rehash_is_hash_mismatch(mutate):
    m = manifest()
    after = applied(m)
    mutate(m)
    assert no_go(m, projection(), after).code == "CLAUSE_PROJECTION_MANIFEST_HASH_MISMATCH"


@pytest.mark.parametrize("mutate", [
    lambda m: m["expected_counts"].update(clause_evidence=3),
    lambda m: m["expected_counts"].update(person_creates=1),
    lambda m: m["operations"][0]["clauses"][1].update(ordinal=3),
    lambda m: m["operations"][0].update(element_id="clause-evidence:R2"),
    lambda m: m["operations"][0].update(dependency_class="source_evidence"),
    lambda m: m["operations"][0].update(extra=1),
    lambda m: m["operations"][0]["clauses"][0].update(verbatim_text="tekst"),
    lambda m: m["source"].update(extra=1),
    lambda m: m.update(extra=1),
    lambda m: m.update(operations=[]),
])
def test_manifest_shape_invalid(mutate):
    m = manifest()
    after = applied(manifest())
    mutate(m)
    rehash(m)
    assert no_go(m, projection(), after).code == "CLAUSE_PROJECTION_MANIFEST_INVALID"


def test_manifest_hash_not_hex_is_invalid():
    m = manifest()
    m["manifest_content_sha256"] = "x"
    assert no_go(m, projection(), applied(manifest())).code == "CLAUSE_PROJECTION_MANIFEST_INVALID"


def test_manifest_without_provenance_is_allowed():
    m = manifest()
    del m["provenance"]
    rehash(m)
    assert run(m, projection(), applied(m))["status"] == "match"


# ---- mål og kilde -----------------------------------------------------------

def test_source_mismatch():
    m = manifest()
    m["source"]["id"] = 2
    rehash(m)
    assert no_go(m, projection(), applied(m)).code == "CLAUSE_PROJECTION_SOURCE_MISMATCH"


def test_target_mismatch_between_before_and_after():
    m = manifest()
    after = applied(m)
    after["database_target_identity"]["database_name"] = "other"
    assert no_go(m, projection(), after).code == "CLAUSE_PROJECTION_TARGET_MISMATCH"


def test_consistent_but_unexpected_target_is_no_go():
    m = manifest()
    before, after = projection(), applied(m)
    for p in (before, after):
        p["database_target_identity"]["database_name"] = "restore-kopi"
    assert no_go(m, before, after).code == "CLAUSE_PROJECTION_TARGET_UNEXPECTED"


def test_record_unknown():
    m = manifest()
    before, after = projection(), applied(m)
    for p in (before, after):
        p["source_records"] = [r for r in p["source_records"] if r["record_key"] != "R2"]
    assert no_go(m, before, after).code == "CLAUSE_PROJECTION_RECORD_UNKNOWN"


# ---- neutralitet ------------------------------------------------------------

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
    err = no_go(m, projection(), after)
    assert err.code == "CLAUSE_PROJECTION_NEUTRALITY_DRIFT"
    assert err.details["lists"] == [name]


@pytest.mark.parametrize("name", ["source_records", "source_anchors", "narrative_bindings",
                                  "narrative_sha256", "persons"])
def test_neutral_row_with_extra_key_is_shape_invalid(name):
    m = manifest()
    after = applied(m)
    after[name][-1] = dict(after[name][-1], marker=1)
    assert no_go(m, projection(), after).code == "CLAUSE_PROJECTION_SHAPE_INVALID"


@pytest.mark.parametrize("table", ["fact", "source_record_anchor_event", "clause_disposition_other_sources"])
def test_neutral_table_hash_change_is_canonical_drift(table):
    m = manifest()
    after = applied(m)
    after["neutral_sha256"][table] = H("2")
    err = no_go(m, projection(), after)
    assert err.code == "CLAUSE_PROJECTION_CANONICAL_DRIFT"
    assert err.details["tables"] == [table]


def test_anon_hash_change_is_anon_drift():
    m = manifest()
    after = applied(m)
    after["anon_sha256"]["person"] = H("2")
    err = no_go(m, projection(), after)
    assert err.code == "CLAUSE_PROJECTION_ANON_DRIFT"
    assert err.details["tables"] == ["person"]


def test_list_order_does_not_matter():
    m = manifest()
    after = applied(m)
    after["source_records"].reverse()
    after["clauses"].reverse()
    assert run(m, projection(), after)["status"] == "match"


# ---- klausuler --------------------------------------------------------------

def test_missing_clause_is_drift():
    m = manifest()
    after = applied(m)
    after["clauses"] = [c for c in after["clauses"] if c["record_key"] != "R2"]
    after["clause_evidence_events"] = events_for(m)
    err = no_go(m, projection(), after)
    assert err.code == "CLAUSE_PROJECTION_DRIFT"
    assert err.details["missing"] == [["R2", 1]]


def test_extra_clause_is_drift():
    m = manifest()
    after = applied(m)
    after["clauses"].append(dict(after["clauses"][0], clause_ordinal=3, observation_id="obs-extra"))
    err = no_go(m, projection(), after)
    assert err.code == "CLAUSE_PROJECTION_DRIFT"
    assert err.details["extra"] == [["R1", 3]]


@pytest.mark.parametrize("field,value", [
    ("post_char_to", 9), ("char_from", 101), ("verbatim_sha256", H("9")),
    ("parent_verbatim_sha256", H("9")), ("flags", ["other"]),
    ("disposition", "strukturel"), ("disposition_version", 2), ("classification", "structural_header"),
])
def test_field_mismatch_names_field_without_values(field, value):
    m = manifest()
    after = applied(m)
    after["clauses"][0][field] = value
    err = no_go(m, projection(), after)
    assert err.code == "CLAUSE_PROJECTION_DRIFT"
    assert err.details["mismatched"][0]["fields"] == [field]
    assert str(value) not in str(err.details)


@pytest.mark.parametrize("field,value", [
    ("decided_by_kind", "human"),
    ("disposition_evidence", {"batch_id": BATCH}),
    ("extraction_method", "clause_segment_v1:other-rules"),
    ("run_input_sha256", H("9")),
    ("run_batch_id", "00000000-0000-4000-8000-00000000b002"),
    ("same_occurrence_as_parent", False),
    ("parent_is_root", False),
    ("pages_match_parent", False),
    ("quality_matches_parent", False),
    ("run_matches_profile", False),
    ("extraction_method_matches_profile", False),
])
def test_writer_invariant_violation(field, value):
    m = manifest()
    after = applied(m)
    after["clauses"][0][field] = value
    err = no_go(m, projection(), after)
    assert err.code == "CLAUSE_PROJECTION_WRITER_INVARIANT_INVALID"
    assert err.details["invariants"] == [field]


def test_target_clauses_from_two_runs_is_invariant_invalid():
    m = manifest()
    after = applied(m)
    after["clauses"][0]["run_id"] = "run-andet"
    err = no_go(m, projection(), after)
    assert err.code == "CLAUSE_PROJECTION_WRITER_INVARIANT_INVALID"
    assert err.details["invariants"] == ["run_id"]


def test_preexisting_clauses_for_manifest_record_is_no_go():
    m = manifest()
    assert no_go(m, applied(m), applied(m)).code == "CLAUSE_PROJECTION_PREEXISTING"


def test_unchanged_foreign_clause_is_match():
    m = manifest()
    before = projection([foreign()])
    after = applied(m)
    after["clauses"].append(foreign())
    assert run(m, before, after)["status"] == "match"


def test_changed_foreign_clause_is_foreign_drift():
    m = manifest()
    before = projection([foreign()])
    after = applied(m)
    after["clauses"].append(foreign(sha=H("1")))
    assert no_go(m, before, after).code == "CLAUSE_PROJECTION_FOREIGN_DRIFT"


@pytest.mark.parametrize("change", [{"row_sha": H("1")}, {"history_sha": H("1")}])
def test_foreign_clause_full_row_or_history_change_is_foreign_drift(change):
    m = manifest()
    before = projection([foreign()])
    after = applied(m)
    after["clauses"].append(foreign(**change))
    assert no_go(m, before, after).code == "CLAUSE_PROJECTION_FOREIGN_DRIFT"


def test_new_clause_on_unanchored_occurrence_is_foreign_drift():
    m = manifest()
    after = applied(m)
    after["clauses"].append(foreign(record_key=None, occurrence_key="o-uden-anker"))
    assert no_go(m, projection(), after).code == "CLAUSE_PROJECTION_FOREIGN_DRIFT"


def test_removed_clause_on_unanchored_occurrence_is_foreign_drift():
    m = manifest()
    before = projection([foreign(record_key=None, occurrence_key="o-uden-anker")])
    assert no_go(m, before, applied(m)).code == "CLAUSE_PROJECTION_FOREIGN_DRIFT"


# ---- batch-binding ----------------------------------------------------------

def test_wrong_manifest_hash_on_events_is_binding_invalid():
    m = manifest()
    after = applied(m)
    for ev in after["clause_evidence_events"]:
        ev["manifest_sha256"] = H("9")
    assert no_go(m, projection(), after).code == "CLAUSE_PROJECTION_BATCH_BINDING_INVALID"


def test_open_batch_is_binding_invalid():
    m = manifest()
    after = projection(written_rows(m), events_for(m, status="open"))
    assert no_go(m, projection(), after).code == "CLAUSE_PROJECTION_BATCH_BINDING_INVALID"


def test_events_split_over_two_batches_is_binding_invalid():
    m = manifest()
    events = events_for(m)
    events[1]["batch_id"] = "00000000-0000-4000-8000-00000000b002"
    after = projection(written_rows(m), events)
    assert no_go(m, projection(), after).code == "CLAUSE_PROJECTION_BATCH_BINDING_INVALID"


def test_missing_event_is_binding_invalid():
    m = manifest()
    after = applied(m)
    after["clause_evidence_events"].pop()
    assert no_go(m, projection(), after).code == "CLAUSE_PROJECTION_BATCH_BINDING_INVALID"


def test_event_already_before_is_binding_invalid():
    m = manifest()
    assert no_go(m, projection(events=events_for(m)), applied(m)).code == "CLAUSE_PROJECTION_BATCH_BINDING_INVALID"


def test_unrelated_new_clause_event_is_binding_invalid():
    m = manifest()
    after = applied(m)
    after["clause_evidence_events"].append(dict(OLD_EVENT, batch_id=BATCH, manifest_sha256=H("9")))
    assert no_go(m, projection(), after).code == "CLAUSE_PROJECTION_BATCH_BINDING_INVALID"


@pytest.mark.parametrize("field,value", [("profile_sha256", H("9")), ("profile_id", "andet")])
def test_batch_bound_to_other_profile_is_binding_invalid(field, value):
    m = manifest()
    events = events_for(m)
    for ev in events:
        ev[field] = value
    assert no_go(m, projection(), projection(written_rows(m), events)).code == "CLAUSE_PROJECTION_BATCH_BINDING_INVALID"


def test_old_event_preserved_is_match():
    m = manifest()
    after = applied(m)
    after["clause_evidence_events"].append(dict(OLD_EVENT))
    assert run(m, projection(events=[OLD_EVENT]), after)["status"] == "match"


@pytest.mark.parametrize("mutate", [
    lambda events: events.remove(OLD_EVENT),
    lambda events: events.__setitem__(events.index(OLD_EVENT), dict(OLD_EVENT, batch_status="reversed")),
    # Ændret payload/after_sha256/created_at i den gamle hændelse: kun helrækkehashen flytter sig.
    lambda events: events.__setitem__(events.index(OLD_EVENT), dict(OLD_EVENT, row_sha256=H("1"))),
])
def test_old_event_removed_or_changed_is_history_drift(mutate):
    m = manifest()
    after = applied(m)
    after["clause_evidence_events"].append(dict(OLD_EVENT))
    mutate(after["clause_evidence_events"])
    assert no_go(m, projection(events=[OLD_EVENT]), after).code == "CLAUSE_PROJECTION_EVENT_HISTORY_DRIFT"


def test_duplicate_event_identity_is_no_go():
    m = manifest()
    after = applied(m)
    after["clause_evidence_events"].append(dict(after["clause_evidence_events"][0], batch_status="open"))
    assert no_go(m, projection(), after).code == "CLAUSE_PROJECTION_DUPLICATE_ROW"


# ---- form -------------------------------------------------------------------

@pytest.mark.parametrize("name", ["source_records", "source_anchors", "narrative_bindings",
                                  "narrative_sha256", "persons"])
def test_empty_list_is_no_go_unless_allowed(name):
    m = manifest()
    before, after = projection(), applied(m)
    before[name], after[name] = [], []
    if name in ("source_records", "source_anchors"):
        assert no_go(m, before, after, allow_empty=frozenset({name})).code == "CLAUSE_PROJECTION_EMPTY_LIST"
        return
    assert no_go(m, before, after).code == "CLAUSE_PROJECTION_EMPTY_LIST"
    result = run(m, before, after, allow_empty=frozenset({name}))
    assert result["counts"]["allowed_empty"] == [name]


def test_duplicate_row_is_no_go():
    m = manifest()
    after = applied(m)
    after["persons"].append({"person_id": 42})
    assert no_go(m, projection(), after).code == "CLAUSE_PROJECTION_DUPLICATE_ROW"


def test_duplicate_clause_identity_is_no_go():
    m = manifest()
    after = applied(m)
    after["clauses"].append(dict(after["clauses"][0], verbatim_sha256=H("9")))
    assert no_go(m, projection(), after).code == "CLAUSE_PROJECTION_DUPLICATE_ROW"


@pytest.mark.parametrize("mutate", [
    lambda p: p.update(extra=1),
    lambda p: p.update(schema_version="daa-evidence-production-snapshot-v1"),
    lambda p: p.update(source_id="1"),
    lambda p: p["neutral_sha256"].pop("fact"),
    lambda p: p["anon_sha256"].pop("person"),
    lambda p: p["anon_sha256"].update(relation=H("1")),
    lambda p: p["clauses"].append({"record_key": "R9"}),
    lambda p: p["clauses"][0].update(same_occurrence_as_parent="true"),
    lambda p: p["clause_evidence_events"][0].pop("batch_id"),
    lambda p: p["database_target_identity"].update(system_identifier_sha256="x"),
])
def test_shape_invalid(mutate):
    m = manifest()
    after = applied(m)
    mutate(after)
    assert no_go(m, projection(), after).code == "CLAUSE_PROJECTION_SHAPE_INVALID"
```

- [ ] **Step 2: Kør testene og se dem fejle**

Run (fra worktree-roden): `env -u NODE_OPTIONS /usr/bin/python3 -m pytest .claude/skills/daa-extract/scripts/test_compare_clause_evidence_projection.py -q -p no:cacheprovider`
Expected: collection error `ModuleNotFoundError: No module named 'compare_clause_evidence_projection'`.

- [ ] **Step 3: Implementér kernen**

`.claude/skills/daa-extract/scripts/compare_clause_evidence_projection.py` (CLI'en tilføjes i Task 2):

```python
#!/usr/bin/env python3
"""Afstem én clause_evidence-kørsel mod to læse-kun projektioner (spec §11.1, vej C).

Udgaveneutral: scriptet kender ingen udgave, fase eller historik. Et `match` beviser
kun DELTAET af én kørsel mod den godkendte måldatabase:

1. de fem kildeprojektioner, helrækkehashes af de neutrale tabeller og det, rollen
   `anon` kan se, er uændrede;
2. klausulerne for manifestets records er præcis manifestets klausuler, felt for felt,
   og bærer writerens egne invarianter (forekomst, forælder, sider, kvalitet, kørsel,
   maskinel disposition med batchens evidens);
3. de stammer fra ÉN færdig batch med manifestets genberegnede hash;
4. ingen anden klausul i kildens inventar er tilføjet, fjernet eller ændret.

Det beviser IKKE, at prod er summen af tidligere faser, og det dækker kun de tabeller,
projektionen hasher. Scriptet åbner aldrig en database.
"""
from __future__ import annotations

import hashlib
import json
from collections import Counter
from typing import Any

PROJECTION_SCHEMA = "daa-clause-evidence-projection-v1"
RESULT_SCOPE = "clause-evidence-delta-v1"
ELEMENT_PREFIX = "clause-evidence:"
NEUTRAL_LISTS = ("source_records", "source_anchors", "narrative_bindings", "narrative_sha256", "persons")
NEUTRAL_ROW_KEYS = {
    "source_records": frozenset(("record_key",)),
    "source_anchors": frozenset(("record_key", "occurrence_key")),
    "narrative_bindings": frozenset(("record_key", "narrative_id", "status")),
    "narrative_sha256": frozenset(("narrative_id", "sha256")),
    "persons": frozenset(("person_id",)),
}
# Uden kilde-records og ankre findes intet at skrive klausuler på.
ALWAYS_NONEMPTY = ("source_records", "source_anchors")
NEUTRAL_HASH_TABLES = (
    "person", "fact", "assertion", "conclusion", "narrative", "relation", "family_member",
    "citation", "person_external_id", "source_mention", "source_record", "source_record_occurrence",
    "source_record_anchor_event", "narrative_record_publication", "source_observation_non_clause",
    "source_observation_clause_other_sources", "clause_disposition_other_sources",
)
ANON_HASH_TABLES = ("assertion", "citation", "conclusion", "fact", "family_member", "narrative",
                    "person", "person_external_id")
EXPECTED_FIELDS = ("record_key", "clause_ordinal", "char_from", "char_to", "post_char_from",
                   "post_char_to", "classification", "flags", "verbatim_sha256",
                   "parent_verbatim_sha256", "disposition", "disposition_version")
BOOLEAN_FIELDS = ("same_occurrence_as_parent", "parent_is_root", "pages_match_parent",
                  "quality_matches_parent", "run_matches_profile", "extraction_method_matches_profile")
INVARIANT_FIELDS = ("decided_by_kind", "disposition_evidence", "extraction_method", "run_input_sha256",
                    "run_batch_id") + BOOLEAN_FIELDS
IDENTITY_FIELDS = ("observation_id", "occurrence_key", "row_sha256", "disposition_history_sha256", "run_id")
CLAUSE_FIELDS = frozenset(EXPECTED_FIELDS + INVARIANT_FIELDS + IDENTITY_FIELDS)
EVENT_FIELDS = frozenset(("batch_id", "manifest_sha256", "batch_status", "profile_id", "profile_sha256",
                          "row_sha256", "element_id", "source_record_key"))
PROJECTION_KEYS = frozenset(("schema_version", "source_id", "database_target_identity", "clauses",
                             "clause_evidence_events", "neutral_sha256", "anon_sha256") + NEUTRAL_LISTS)
MANIFEST_TOP_REQUIRED = frozenset(("manifest_content_sha256", "source", "expected_counts", "operations"))
MANIFEST_TOP_OPTIONAL = frozenset(("provenance",))
MANIFEST_SOURCE_KEYS = frozenset(("id", "profile_id", "profile_sha256"))
MANIFEST_COUNT_KEYS = frozenset(("source_evidence", "person_creates", "canonical_delta", "clause_evidence"))
MANIFEST_OPERATION_KEYS = frozenset((
    "element_id", "dependency_class", "source_record_key", "rendition_content_sha256",
    "rendition_projection_sha256", "parent_verbatim_sha256", "clause_rules_version",
    "segmenter_version", "ledger_sha256", "gap_charset", "clauses"))
MANIFEST_CLAUSE_KEYS = frozenset(("char_from", "char_to", "classification", "flags", "ordinal",
                                  "rendition_char_from", "rendition_char_to", "verbatim_sha256"))


class ProjectionError(ValueError):
    """NO-GO. `details` bærer kun nøgler, feltnavne og antal, aldrig værdier eller tekst."""

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


def _canon(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def _canon_set(rows: list[Any]) -> list[str]:
    return sorted(_canon(r) for r in rows)


def compute_manifest_sha256(manifest: dict[str, Any]) -> str:
    """Præcis build_clause_evidence_manifest.py's formel (hash over manifestet uden hash-feltet)."""
    body = {k: v for k, v in manifest.items() if k != "manifest_content_sha256"}
    return hashlib.sha256(_canon(body).encode("utf-8")).hexdigest()


def target_sha256(identity: dict[str, Any]) -> str:
    """Samme formel som clause_evidence_target_identity.sql."""
    text = f"{identity['database_name']}\n{identity['system_identifier_sha256']}"
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def _disposition(classification: str, flags: list[str]) -> str:
    # Spejler private.write_clause_evidence (db-migrations.sql, `v_disposition:=CASE`).
    if classification == "structural_header":
        return "strukturel"
    if flags:
        return "maskinelt_flagget"
    return "afventer_fortolkning"


def _validate_hashes(p: dict[str, Any], key: str, tables: tuple[str, ...]) -> None:
    group = p[key]
    if not isinstance(group, dict) or set(group) != set(tables) or not all(_is_sha(v) for v in group.values()):
        _fail("CLAUSE_PROJECTION_SHAPE_INVALID", part=key)


def _validate_projection(p: Any, allow_empty: frozenset[str]) -> list[dict[str, Any]]:
    if not isinstance(p, dict) or set(p) != PROJECTION_KEYS:
        _fail("CLAUSE_PROJECTION_SHAPE_INVALID", part="keys")
    if p["schema_version"] != PROJECTION_SCHEMA or not _is_int(p["source_id"]) or p["source_id"] <= 0:
        _fail("CLAUSE_PROJECTION_SHAPE_INVALID", part="header")
    identity = p["database_target_identity"]
    if (not isinstance(identity, dict) or set(identity) != {"database_name", "system_identifier_sha256"}
            or not isinstance(identity["database_name"], str) or not _is_sha(identity["system_identifier_sha256"])):
        _fail("CLAUSE_PROJECTION_SHAPE_INVALID", part="database_target_identity")
    _validate_hashes(p, "neutral_sha256", NEUTRAL_HASH_TABLES)
    _validate_hashes(p, "anon_sha256", ANON_HASH_TABLES)
    for name in NEUTRAL_LISTS + ("clause_evidence_events", "clauses"):
        rows = p[name]
        if not isinstance(rows, list) or not all(isinstance(r, dict) for r in rows):
            _fail("CLAUSE_PROJECTION_SHAPE_INVALID", part=name)
    for name in NEUTRAL_LISTS:
        if not all(set(r) == NEUTRAL_ROW_KEYS[name] for r in p[name]):
            _fail("CLAUSE_PROJECTION_SHAPE_INVALID", part=name)
        if len(set(_canon_set(p[name]))) != len(p[name]):
            _fail("CLAUSE_PROJECTION_DUPLICATE_ROW", part=name)
        if not p[name] and (name in ALWAYS_NONEMPTY or name not in allow_empty):
            _fail("CLAUSE_PROJECTION_EMPTY_LIST", part=name)
    events = p["clause_evidence_events"]
    if not all(set(e) == EVENT_FIELDS and isinstance(e["batch_id"], str) and isinstance(e["element_id"], str)
               and _is_sha(e["row_sha256"]) for e in events):
        _fail("CLAUSE_PROJECTION_SHAPE_INVALID", part="clause_evidence_events")
    if len({(e["batch_id"], e["element_id"]) for e in events}) != len(events):
        _fail("CLAUSE_PROJECTION_DUPLICATE_ROW", part="clause_evidence_events")
    seen: set[str] = set()
    for row in p["clauses"]:
        if (set(row) != CLAUSE_FIELDS or not isinstance(row["observation_id"], str)
                or not isinstance(row["occurrence_key"], str)
                or not (row["record_key"] is None or isinstance(row["record_key"], str))
                or not _is_int(row["clause_ordinal"])
                or not _is_sha(row["row_sha256"]) or not _is_sha(row["disposition_history_sha256"])
                or not all(type(row[f]) is bool for f in BOOLEAN_FIELDS)):
            _fail("CLAUSE_PROJECTION_SHAPE_INVALID", part="clauses")
        if row["observation_id"] in seen:
            _fail("CLAUSE_PROJECTION_DUPLICATE_ROW", part="clauses")
        seen.add(row["observation_id"])
    return p["clauses"]


def _validate_manifest(manifest: Any) -> dict[str, dict[str, Any]]:
    def bad(part: str) -> None:
        _fail("CLAUSE_PROJECTION_MANIFEST_INVALID", part=part)

    if not isinstance(manifest, dict):
        bad("top")
    keys = set(manifest)
    if not (MANIFEST_TOP_REQUIRED <= keys <= MANIFEST_TOP_REQUIRED | MANIFEST_TOP_OPTIONAL):
        bad("top")
    if not _is_sha(manifest["manifest_content_sha256"]):
        bad("manifest_content_sha256")
    source = manifest["source"]
    if not isinstance(source, dict) or set(source) != MANIFEST_SOURCE_KEYS or not _is_int(source["id"]):
        bad("source")
    operations = manifest["operations"]
    if not isinstance(operations, list) or not operations:
        bad("operations")
    counts = manifest["expected_counts"]
    if (not isinstance(counts, dict) or set(counts) != MANIFEST_COUNT_KEYS
            or counts["clause_evidence"] != len(operations)
            or any(counts[k] != 0 for k in ("source_evidence", "person_creates", "canonical_delta"))):
        bad("expected_counts")
    by_key: dict[str, dict[str, Any]] = {}
    for op in operations:
        if not isinstance(op, dict) or set(op) != MANIFEST_OPERATION_KEYS:
            bad("operation")
        key = op["source_record_key"]
        if (not isinstance(key, str) or not key or key in by_key
                or op["element_id"] != ELEMENT_PREFIX + key
                or op["dependency_class"] != "clause_evidence"
                or not _is_sha(op["parent_verbatim_sha256"])
                or not isinstance(op["clause_rules_version"], str) or not op["clause_rules_version"]):
            bad("operation")
        clauses = op["clauses"]
        if not isinstance(clauses, list) or not clauses:
            bad("clauses")
        for index, c in enumerate(clauses, start=1):
            if (not isinstance(c, dict) or set(c) != MANIFEST_CLAUSE_KEYS or c["ordinal"] != index
                    or not isinstance(c["flags"], list) or not _is_sha(c["verbatim_sha256"])):
                bad("clause")
        by_key[key] = op
    if compute_manifest_sha256(manifest) != manifest["manifest_content_sha256"]:
        _fail("CLAUSE_PROJECTION_MANIFEST_HASH_MISMATCH")
    return by_key


def expected_clauses(manifest: Any) -> dict[tuple[str, int], dict[str, Any]]:
    """Manifestets klausuler som projektionsrækker (kun EXPECTED_FIELDS)."""
    rows: dict[tuple[str, int], dict[str, Any]] = {}
    for key, op in _validate_manifest(manifest).items():
        for c in op["clauses"]:
            rows[(key, c["ordinal"])] = {
                "record_key": key, "clause_ordinal": c["ordinal"],
                "char_from": c["rendition_char_from"], "char_to": c["rendition_char_to"],
                "post_char_from": c["char_from"], "post_char_to": c["char_to"],
                "classification": c["classification"], "flags": list(c["flags"]),
                "verbatim_sha256": c["verbatim_sha256"],
                "parent_verbatim_sha256": op["parent_verbatim_sha256"],
                "disposition": _disposition(c["classification"], c["flags"]),
                "disposition_version": 1,
            }
    return rows


def compare(manifest: Any, before: Any, after: Any, expected_target_sha256: str,
            allow_empty: frozenset[str] = frozenset()) -> dict[str, Any]:
    before_clauses = _validate_projection(before, allow_empty)
    after_clauses = _validate_projection(after, allow_empty)
    expected = expected_clauses(manifest)
    operations = {op["source_record_key"]: op for op in manifest["operations"]}
    record_keys = set(operations)
    manifest_sha = manifest["manifest_content_sha256"]

    if not (manifest["source"]["id"] == before["source_id"] == after["source_id"]):
        _fail("CLAUSE_PROJECTION_SOURCE_MISMATCH")
    if before["database_target_identity"] != after["database_target_identity"]:
        _fail("CLAUSE_PROJECTION_TARGET_MISMATCH")
    target = target_sha256(after["database_target_identity"])
    if target != expected_target_sha256:
        _fail("CLAUSE_PROJECTION_TARGET_UNEXPECTED")
    unknown = record_keys - {r["record_key"] for r in after["source_records"]}
    if unknown:
        _fail("CLAUSE_PROJECTION_RECORD_UNKNOWN", records=len(unknown))

    drifted = [n for n in NEUTRAL_LISTS if _canon_set(before[n]) != _canon_set(after[n])]
    if drifted:
        _fail("CLAUSE_PROJECTION_NEUTRALITY_DRIFT", lists=drifted)
    tables = [t for t in NEUTRAL_HASH_TABLES if before["neutral_sha256"][t] != after["neutral_sha256"][t]]
    if tables:
        _fail("CLAUSE_PROJECTION_CANONICAL_DRIFT", tables=tables)
    anon = [t for t in ANON_HASH_TABLES if before["anon_sha256"][t] != after["anon_sha256"][t]]
    if anon:
        _fail("CLAUSE_PROJECTION_ANON_DRIFT", tables=anon)

    preexisting = {r["record_key"] for r in before_clauses if r["record_key"] in record_keys}
    if preexisting:
        _fail("CLAUSE_PROJECTION_PREEXISTING", records=len(preexisting))
    # Fremmede klausuler (ikke manifestets records) sammenlignes på hele rækken, inkl.
    # helrækkehash og hele dispositionshistorikken, med databasens egen identitet.
    foreign_before = {r["observation_id"]: _canon(r) for r in before_clauses if r["record_key"] not in record_keys}
    foreign_after = {r["observation_id"]: _canon(r) for r in after_clauses if r["record_key"] not in record_keys}
    if foreign_before != foreign_after:
        changed = set(foreign_before) ^ set(foreign_after)
        changed |= {k for k in set(foreign_before) & set(foreign_after) if foreign_before[k] != foreign_after[k]}
        _fail("CLAUSE_PROJECTION_FOREIGN_DRIFT", clauses=len(changed))

    # Ældre hændelser skal være bevaret uændret, FØR det nye delta beregnes; ellers kan
    # en slettet gammel hændelse gemme sig bag en korrekt ny.
    after_events = set(_canon_set(after["clause_evidence_events"]))
    lost = [e for e in before["clause_evidence_events"] if _canon(e) not in after_events]
    if lost:
        _fail("CLAUSE_PROJECTION_EVENT_HISTORY_DRIFT", events=len(lost))
    before_events = set(_canon_set(before["clause_evidence_events"]))
    new_events = [e for e in after["clause_evidence_events"] if _canon(e) not in before_events]
    batch_ids = {e["batch_id"] for e in new_events}
    element_ids = sorted(ELEMENT_PREFIX + k for k in record_keys)
    source = manifest["source"]
    binding_ok = (
        len(batch_ids) == 1
        and not any(e["manifest_sha256"] == manifest_sha or e["batch_id"] in batch_ids
                    for e in before["clause_evidence_events"])
        and len(new_events) == len(element_ids)
        and all(e["manifest_sha256"] == manifest_sha and e["batch_status"] == "finalized"
                and e["profile_id"] == source["profile_id"] and e["profile_sha256"] == source["profile_sha256"]
                and e["element_id"] == ELEMENT_PREFIX + str(e["source_record_key"]) for e in new_events)
        and sorted(e["element_id"] for e in new_events) == element_ids
    )
    if not binding_ok:
        _fail("CLAUSE_PROJECTION_BATCH_BINDING_INVALID", new_events=len(new_events),
              batches=len(batch_ids), expected=len(element_ids))
    batch_id = next(iter(batch_ids))

    actual: dict[tuple[str, int], dict[str, Any]] = {}
    for row in after_clauses:
        if row["record_key"] in record_keys:
            key = (row["record_key"], row["clause_ordinal"])
            if key in actual:
                _fail("CLAUSE_PROJECTION_DUPLICATE_ROW", part="clauses")
            actual[key] = row
    missing = sorted(set(expected) - set(actual))
    extra = sorted(set(actual) - set(expected))
    mismatched = []
    for key in sorted(set(expected) & set(actual)):
        fields = [f for f in EXPECTED_FIELDS if _canon(expected[key][f]) != _canon(actual[key][f])]
        if fields:
            mismatched.append({"record_key": key[0], "clause_ordinal": key[1], "fields": fields})
    if missing or extra or mismatched:
        _fail("CLAUSE_PROJECTION_DRIFT", missing=[list(k) for k in missing],
              extra=[list(k) for k in extra], mismatched=mismatched)

    failed: set[str] = set()
    for (record_key, _), row in actual.items():
        rules = operations[record_key]["clause_rules_version"]
        checks = {
            "decided_by_kind": row["decided_by_kind"] == "machine",
            "disposition_evidence": row["disposition_evidence"] == {
                "batch_id": batch_id, "element_id": ELEMENT_PREFIX + record_key,
                "manifest_sha256": manifest_sha, "clause_rules_version": rules},
            "extraction_method": isinstance(row["extraction_method"], str)
            and row["extraction_method"].endswith(":" + rules),
            "run_input_sha256": row["run_input_sha256"] == manifest_sha,
            "run_batch_id": row["run_batch_id"] == batch_id,
        }
        checks.update({f: row[f] is True for f in BOOLEAN_FIELDS})
        failed |= {name for name, ok in checks.items() if not ok}
    if len({row["run_id"] for row in actual.values()}) != 1:
        failed.add("run_id")
    if failed:
        _fail("CLAUSE_PROJECTION_WRITER_INVARIANT_INVALID", invariants=sorted(failed))

    dispositions = Counter(row["disposition"] for row in expected.values())
    return {
        "status": "match",
        "scope": RESULT_SCOPE,
        "source_id": after["source_id"],
        "database_target_sha256": target,
        "manifest_content_sha256": manifest_sha,
        "batch_id": batch_id,
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
Expected: alle `passed`. Fejler en test, ret implementeringen — ikke testen — medmindre testen modsiger Global Constraints; notér i så fald afvigelsen i commit-beskeden.

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

### Task 2: Komparatorens CLI — målbinding, privat rapport, exitkoder

**Files:**
- Modify: `.claude/skills/daa-extract/scripts/compare_clause_evidence_projection.py` (tilføj `main`)
- Modify: `.claude/skills/daa-extract/scripts/test_compare_clause_evidence_projection.py` (CLI-tests)

**Interfaces:**
- Consumes: `compare`, `compute_manifest_sha256`, `ProjectionError` fra Task 1.
- Produces:
  - `compare_clause_evidence_projection.py --manifest M --before B --after A --expect-target-sha256 T --report R [--allow-empty narrative_bindings,narrative_sha256,persons]`
    - exit `0` = `match`, `1` = NO-GO, `2` = brugsfejl.
    - stdout: én JSON-linje **uden** `details`. Ved match inkluderes `database_target_sha256`, `manifest_content_sha256`, `batch_id`, `counts` og `input_sha256` (`manifest`, `before`, `after` som fil-SHA-256).
    - Rapporten `R`: fuldt resultat inkl. `details` og `input_sha256`, `O_CREAT|O_EXCL`, 0600. Afvises (`CLAUSE_PROJECTION_REPORT_EXISTS` / `_REPORT_IN_REPOSITORY` / `_REPORT_DIR_MISSING`) før input læses.
    - `--expect-target-sha256` skal være 64 hex, ellers `CLAUSE_PROJECTION_EXPECTED_TARGET_INVALID` (exit 2).
    - `--allow-empty` kun `narrative_bindings`, `narrative_sha256`, `persons`; ellers `CLAUSE_PROJECTION_ALLOW_EMPTY_INVALID` (exit 2).
  - `compare_clause_evidence_projection.py --print-manifest-sha256 M` — skriver kun builderens hash for `M` (til CI-fixturen); exit 0/2.

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


def cli(tmp_path, mp, bp, ap, report="report.json", target=TARGET, *extra):
    return run_cli("--manifest", mp, "--before", bp, "--after", ap,
                   "--expect-target-sha256", target, "--report", tmp_path / report, *extra)


def test_cli_match_writes_private_report_with_input_hashes(tmp_path):
    mp, bp, ap = cli_inputs(tmp_path)
    proc = cli(tmp_path, mp, bp, ap)
    assert proc.returncode == 0, proc.stdout + proc.stderr
    terminal = _json.loads(proc.stdout)
    assert terminal["status"] == "match" and "details" not in terminal
    assert terminal["database_target_sha256"] == TARGET
    import hashlib
    assert terminal["input_sha256"]["after"] == hashlib.sha256(ap.read_bytes()).hexdigest()
    report = tmp_path / "report.json"
    assert stat.S_IMODE(report.stat().st_mode) == 0o600
    assert _json.loads(report.read_text())["status"] == "match"


def test_cli_no_go_keeps_record_keys_out_of_stdout(tmp_path):
    m = manifest()
    after = applied(m)
    after["clauses"][0]["post_char_to"] = 9
    mp, bp, ap = cli_inputs(tmp_path, after)
    proc = cli(tmp_path, mp, bp, ap)
    assert proc.returncode == 1
    assert _json.loads(proc.stdout) == {"status": "no_go", "code": "CLAUSE_PROJECTION_DRIFT"}
    assert "R1" not in proc.stdout and "R1" not in proc.stderr
    report = _json.loads((tmp_path / "report.json").read_text())
    assert report["details"]["mismatched"][0]["record_key"] == "R1"


def test_cli_unexpected_target_is_no_go(tmp_path):
    mp, bp, ap = cli_inputs(tmp_path)
    proc = cli(tmp_path, mp, bp, ap, "report.json", H("9"))
    assert proc.returncode == 1
    assert _json.loads(proc.stdout)["code"] == "CLAUSE_PROJECTION_TARGET_UNEXPECTED"


def test_cli_rejects_malformed_expected_target(tmp_path):
    mp, bp, ap = cli_inputs(tmp_path)
    proc = cli(tmp_path, mp, bp, ap, "report.json", "prod")
    assert proc.returncode == 2
    assert _json.loads(proc.stdout)["code"] == "CLAUSE_PROJECTION_EXPECTED_TARGET_INVALID"
    assert not (tmp_path / "report.json").exists()


def test_cli_refuses_existing_report(tmp_path):
    mp, bp, ap = cli_inputs(tmp_path)
    (tmp_path / "report.json").write_text("x")
    proc = cli(tmp_path, mp, bp, ap)
    assert proc.returncode == 2
    assert _json.loads(proc.stdout)["code"] == "CLAUSE_PROJECTION_REPORT_EXISTS"
    assert (tmp_path / "report.json").read_text() == "x"


def test_cli_refuses_report_inside_repository(tmp_path):
    mp, bp, ap = cli_inputs(tmp_path)
    report = SCRIPT.parent / "must-not-exist-clause-projection-report.json"
    proc = run_cli("--manifest", mp, "--before", bp, "--after", ap,
                   "--expect-target-sha256", TARGET, "--report", report)
    assert proc.returncode == 2
    assert _json.loads(proc.stdout)["code"] == "CLAUSE_PROJECTION_REPORT_IN_REPOSITORY"
    assert not report.exists()


def test_cli_rejects_unknown_allow_empty(tmp_path):
    mp, bp, ap = cli_inputs(tmp_path)
    proc = cli(tmp_path, mp, bp, ap, "report.json", TARGET, "--allow-empty", "source_records")
    assert proc.returncode == 2
    assert _json.loads(proc.stdout)["code"] == "CLAUSE_PROJECTION_ALLOW_EMPTY_INVALID"


def test_cli_unreadable_input_is_usage_error(tmp_path):
    mp, bp, _ = cli_inputs(tmp_path)
    bad = tmp_path / "bad.json"
    bad.write_text("{", encoding="utf-8")
    proc = cli(tmp_path, mp, bp, bad)
    assert proc.returncode == 2
    assert _json.loads(proc.stdout)["code"] == "CLAUSE_PROJECTION_INPUT_UNREADABLE"
    assert not (tmp_path / "report.json").exists()


def test_cli_report_dir_missing(tmp_path):
    mp, bp, ap = cli_inputs(tmp_path)
    proc = run_cli("--manifest", mp, "--before", bp, "--after", ap,
                   "--expect-target-sha256", TARGET, "--report", tmp_path / "findes-ikke" / "r.json")
    assert proc.returncode == 2
    assert _json.loads(proc.stdout)["code"] == "CLAUSE_PROJECTION_REPORT_DIR_MISSING"
    assert not (tmp_path / "findes-ikke").exists()


def test_cli_arguments_missing(tmp_path):
    mp, bp, ap = cli_inputs(tmp_path)
    proc = run_cli("--manifest", mp, "--before", bp, "--after", ap, "--report", tmp_path / "r.json")
    assert proc.returncode == 2
    assert _json.loads(proc.stdout)["code"] == "CLAUSE_PROJECTION_ARGUMENTS_MISSING"
    assert not (tmp_path / "r.json").exists()


def test_cli_print_manifest_sha256(tmp_path):
    m = manifest()
    unhashed = {k: v for k, v in m.items() if k != "manifest_content_sha256"}
    path = write(tmp_path, "unhashed.json", unhashed)
    proc = run_cli("--print-manifest-sha256", path)
    assert proc.returncode == 0
    assert proc.stdout.strip() == m["manifest_content_sha256"]
```

- [ ] **Step 2: Kør og se dem fejle**

Run: `env -u NODE_OPTIONS /usr/bin/python3 -m pytest .claude/skills/daa-extract/scripts/test_compare_clause_evidence_projection.py -q -p no:cacheprovider -k cli`
Expected: FAIL (ingen `main`; subprocess giver tom stdout → `JSONDecodeError`).

- [ ] **Step 3: Implementér `main`** (tilføj `import argparse`, `import os`, `import sys`, `from pathlib import Path` øverst og følgende nederst)

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


def _load(raw: str) -> tuple[Any, str]:
    try:
        data = Path(raw).expanduser().read_bytes()
        return json.loads(data.decode("utf-8")), hashlib.sha256(data).hexdigest()
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
    parser.add_argument("--print-manifest-sha256")
    parser.add_argument("--manifest")
    parser.add_argument("--before")
    parser.add_argument("--after")
    parser.add_argument("--expect-target-sha256")
    parser.add_argument("--report")
    parser.add_argument("--allow-empty", default="")
    args = parser.parse_args(argv)
    if args.print_manifest_sha256:
        try:
            manifest, _ = _load(args.print_manifest_sha256)
            if not isinstance(manifest, dict):
                raise UsageError("CLAUSE_PROJECTION_INPUT_UNREADABLE")
        except UsageError as error:
            _emit({"status": "usage_error", "code": error.code})
            return 2
        print(compute_manifest_sha256(manifest))
        return 0
    try:
        if not all((args.manifest, args.before, args.after, args.expect_target_sha256, args.report)):
            raise UsageError("CLAUSE_PROJECTION_ARGUMENTS_MISSING")
        if not _is_sha(args.expect_target_sha256):
            raise UsageError("CLAUSE_PROJECTION_EXPECTED_TARGET_INVALID")
        allow_empty = frozenset(x for x in args.allow_empty.split(",") if x)
        if not allow_empty <= ALLOWED_EMPTY_CHOICES:
            raise UsageError("CLAUSE_PROJECTION_ALLOW_EMPTY_INVALID")
        report = _check_report_path(args.report)
        (manifest, manifest_sha), (before, before_sha), (after, after_sha) = (
            _load(args.manifest), _load(args.before), _load(args.after))
    except UsageError as error:
        _emit({"status": "usage_error", "code": error.code})
        return 2
    input_sha256 = {"manifest": manifest_sha, "before": before_sha, "after": after_sha}
    try:
        result: dict[str, Any] = dict(compare(manifest, before, after, args.expect_target_sha256, allow_empty),
                                      input_sha256=input_sha256)
        terminal = result
    except ProjectionError as error:
        result = {"status": "no_go", "code": error.code, "details": error.details, "input_sha256": input_sha256}
        terminal = {"status": "no_go", "code": error.code}
    _write_private(report, result)
    _emit(terminal)
    return 0 if result["status"] == "match" else 1


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 4: Kør hele testfilen**

Run: `env -u NODE_OPTIONS /usr/bin/python3 -m pytest .claude/skills/daa-extract/scripts/test_compare_clause_evidence_projection.py -q -p no:cacheprovider`
Expected: alle `passed`. Kør også med `python3.11`, hvis den findes (ellers notér, at kun 3.9 er kørt lokalt; CI kører 3.11).

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/daa-extract/scripts/compare_clause_evidence_projection.py \
        .claude/skills/daa-extract/scripts/test_compare_clause_evidence_projection.py
git commit -m "feat(evidens): CLI til klausul-komparatoren med målbinding og privat rapport (#195)"
```

---

### Task 3: Læse-kun projektion (SQL + psql-driver) og ende-til-ende i CI

**Files:**
- Create: `.claude/skills/daa-extract/scripts/clause_evidence_projection.sql`
- Create: `.claude/skills/daa-extract/scripts/clause_evidence_anon_projection.sql`
- Create: `.claude/skills/daa-extract/scripts/clause_evidence_target_identity.sql`
- Create: `.claude/skills/daa-extract/scripts/clause_evidence_projection.psql`
- Modify: `tests/integration/test-reimport-clause-evidence.R`

**Interfaces:**
- Consumes: Task 2's CLI.
- Produces:
  - Driveren: `DAA_PROJECTION_SQL_DIR=<scripts-mappe> psql -X -At -q -v ON_ERROR_STOP=1 -v source_id=<id> -f .claude/skills/daa-extract/scripts/clause_evidence_projection.psql` → én linje JSON (schema ovenfor).
  - `clause_evidence_target_identity.sql` → én række, kolonne `database_target_sha256`.
  - Guard-fejl (som `invalid input syntax for type integer: "<KODE>:…"`): `CLAUSE_PROJECTION_SOURCE_ID_MISSING`, `CLAUSE_PROJECTION_NOT_READ_ONLY`, `CLAUSE_PROJECTION_NOT_REPEATABLE_READ`, `CLAUSE_PROJECTION_NOT_ANON`.

- [ ] **Step 1: Udvid integrationstesten, så den fejler**

I `tests/integration/test-reimport-clause-evidence.R`:

(a) Lige **efter** listen `manifest_ce <- list(...)` og **før** `validate_reimport_manifest(manifest_ce)`: erstat den tilfældige hash med builderens (komparatoren genberegner den):

```r
# ---- klausul-projektion (spec §11.1, vej C, #195) ---------------------------
scripts_dir <- file.path(root, ".claude/skills/daa-extract/scripts")
comparator <- file.path(scripts_dir, "compare_clause_evidence_projection.py")
proj_dir <- tempfile("klausul-projektion-"); dir.create(proj_dir, mode = "0700")
write_private <- function(name, text) {
  path <- file.path(proj_dir, name); stopifnot(!file.exists(path))
  writeLines(text, path); Sys.chmod(path, "0600"); path
}
manifest_json <- function(m) as.character(jsonlite::toJSON(m, auto_unbox = TRUE, null = "null", digits = NA))
manifest_ce$manifest_content_sha256 <- NULL
unhashed_path <- write_private("manifest-unhashed.json", manifest_json(manifest_ce))
manifest_ce$manifest_content_sha256 <- system2("python3", c(shQuote(comparator), "--print-manifest-sha256",
  shQuote(unhashed_path)), stdout = TRUE)
stopifnot(grepl("^[0-9a-f]{64}$", manifest_ce$manifest_content_sha256))
manifest_path <- write_private("manifest.json", manifest_json(manifest_ce))

projection <- function() {
  out <- suppressWarnings(system2("psql", c("-X", "-At", "-q", "-v", "ON_ERROR_STOP=1",
    "-v", paste0("source_id=", source_id), "-f", shQuote(file.path(scripts_dir, "clause_evidence_projection.psql"))),
    stdout = TRUE, stderr = TRUE, env = paste0("DAA_PROJECTION_SQL_DIR=", shQuote(scripts_dir))))
  if (!is.null(attr(out, "status"))) stop("projektion fejlede: ", paste(out, collapse = "\n"))
  stopifnot(length(out) == 1L)
  out
}
sql_text <- function(name) paste(readLines(file.path(scripts_dir, name), warn = FALSE), collapse = "\n")
guard_error <- function(sql, read_only) {
  pc <- connect(); on.exit(dbDisconnect(pc), add = TRUE)
  dbBegin(pc); on.exit(try(dbRollback(pc), silent = TRUE), add = TRUE, after = FALSE)
  if (read_only) dbExecute(pc, "SET TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY")
  dbGetQuery(pc, "SELECT set_config('daa.projection_source_id', $1, true)", params = list(as.character(source_id)))
  tryCatch({ dbGetQuery(pc, sql); "ingen fejl" }, error = function(err) conditionMessage(err))
}
stopifnot(grepl("CLAUSE_PROJECTION_NOT_READ_ONLY", guard_error(sql_text("clause_evidence_projection.sql"), FALSE), fixed = TRUE))
stopifnot(grepl("CLAUSE_PROJECTION_NOT_ANON", guard_error(sql_text("clause_evidence_anon_projection.sql"), TRUE), fixed = TRUE))
target_sha <- q(sql_text("clause_evidence_target_identity.sql"))$database_target_sha256[[1L]]
stopifnot(grepl("^[0-9a-f]{64}$", target_sha))
run_comparator <- function(before_path, after_path, report_name, target = target_sha) {
  out <- suppressWarnings(system2("python3", c(shQuote(comparator),
    "--manifest", shQuote(manifest_path), "--before", shQuote(before_path), "--after", shQuote(after_path),
    "--expect-target-sha256", target, "--report", shQuote(file.path(proj_dir, report_name)),
    "--allow-empty", "narrative_bindings,narrative_sha256,persons"), stdout = TRUE, stderr = TRUE))
  list(status = if (is.null(attr(out, "status"))) 0L else attr(out, "status"), out = paste(out, collapse = "\n"))
}
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
drift <- run_comparator(before_path, write_private("after-tampered.json", tampered), "report-tampered.json")
stopifnot(drift$status == 1L, grepl("CLAUSE_PROJECTION_DRIFT", drift$out, fixed = TRUE))

wrong_target <- run_comparator(before_path, after_path, "report-target.json", strrep("0", 64L))
stopifnot(wrong_target$status == 1L, grepl("CLAUSE_PROJECTION_TARGET_UNEXPECTED", wrong_target$out, fixed = TRUE))
```

(d) Efter `stopifnot(identical(replay$status, "already_applied"))`:

```r
# Replay må ikke efterlade spor i projektionen.
stopifnot(identical(projection(), after_text))
```

- [ ] **Step 2: Byg en disponerbar base som CI og se testen fejle**

Fra worktree-roden (lokal Homebrew PostgreSQL 17, port 5432):

```bash
export PGHOST=localhost PGPORT=5432 PGUSER=$(whoami) PGTZ=UTC
DB="klausulproj_ci_$(date +%Y%m%d%H%M%S)"; export PGDATABASE="$DB"
echo "$DB" > "${TMPDIR:-/tmp}/klausulproj-db-name.txt"
createdb "$DB"
psql -X -q -v ON_ERROR_STOP=1 -f tests/sql/evidence-promotion-bootstrap.sql
psql -X -q -v ON_ERROR_STOP=1 -f schema.sql
psql -X -q -v ON_ERROR_STOP=1 -f db-rls.sql
psql -X -q -v ON_ERROR_STOP=1 -f tests/sql/1939-v50-writer-bootstrap.sql
psql -X -q -v ON_ERROR_STOP=1 -c 'BEGIN' -f tests/sql/reimport-writer-v2-bootstrap.sql -c 'COMMIT'
psql -X -q -v ON_ERROR_STOP=1 -f db-rls.sql
Rscript tests/integration/test-reimport-clause-evidence.R
```

Kommandoerne er CI-trinnet »Nulstil database til name completion integration« i `.github/workflows/ci.yml`; fejler et af dem lokalt, sammenlign med CI-trinnet og ret kommandoen, ikke skemaet.

Expected: `Rscript` fejler i `system2("python3", … "--print-manifest-sha256" …)` eller i `projection()` fordi driveren/SQL-filerne ikke findes.

- [ ] **Step 3: Skriv ejer-projektionen**

`.claude/skills/daa-extract/scripts/clause_evidence_projection.sql` — **ingen afsluttende semikolon**, ingen `;` eller `'` i kommentarer:

```sql
-- Laese-kun klausul-projektion, ejer-delen (spec 11.1, vej C, issue 195). Udgaveneutral.
-- Koeres af clause_evidence_projection.psql i en READ ONLY + REPEATABLE READ-transaktion
-- efter set_config af daa.projection_source_id. Returnerer kolonnen projection (tekst).
-- Ingen kildetekst forlader databasen: al tekst hashes her med pg_catalog.sha256.
-- Neutralitet maales paa hele raekker pr. tabel, ikke paa antal.
-- Guard-fejl rejses som tekst-til-integer-cast af en ikke-konstant streng, saa
-- planneren ikke kan konstant-folde den.
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
  SELECT o.occurrence_key, c.clause_ordinal, jsonb_build_object(
    'observation_id', c.id::text,
    'row_sha256', encode(pg_catalog.sha256(convert_to(c::text, 'UTF8')), 'hex'),
    'disposition_history_sha256', (SELECT encode(pg_catalog.sha256(convert_to(coalesce(string_agg(h::text, E'\n' ORDER BY h::text COLLATE "C"), ''), 'UTF8')), 'hex')
                                   FROM private.clause_disposition h WHERE h.observation_id = c.id),
    'run_id', run.id::text,
    'run_matches_profile', coalesce(run.schema_version = wp.writer_config ->> 'schema_version'
                                    AND run.extractor_version = wp.writer_config ->> 'extractor_version'
                                    AND run.profile_version = wp.profile_version
                                    AND run.manifest ->> 'profile_sha256' = rb.profile_sha256, false),
    'extraction_method_matches_profile', coalesce(c.extraction_method = (wp.writer_config ->> 'observation_extraction_method')
                                                  || ':' || (d.evidence ->> 'clause_rules_version'), false),
    'record_key', ac.record_key,
    'occurrence_key', o.occurrence_key,
    'clause_ordinal', c.clause_ordinal,
    'char_from', c.char_from, 'char_to', c.char_to,
    'post_char_from', c.post_char_from, 'post_char_to', c.post_char_to,
    'classification', c.clause_classification,
    'flags', c.clause_flags,
    'verbatim_sha256', encode(pg_catalog.sha256(convert_to(c.verbatim_text, 'UTF8')), 'hex'),
    'parent_verbatim_sha256', encode(pg_catalog.sha256(convert_to(parent.verbatim_text, 'UTF8')), 'hex'),
    'disposition', d.disposition,
    'disposition_version', d.version,
    'decided_by_kind', d.decided_by_kind,
    'disposition_evidence', d.evidence,
    'extraction_method', c.extraction_method,
    'run_input_sha256', run.input_sha256,
    'run_batch_id', run.manifest ->> 'batch_id',
    'same_occurrence_as_parent', coalesce(parent.occurrence_id = c.occurrence_id, false),
    'parent_is_root', coalesce(parent.id IS NOT NULL AND parent.parent_observation_id IS NULL, false),
    'pages_match_parent', coalesce(parent.page_from = c.page_from AND parent.page_to = c.page_to, false),
    'quality_matches_parent', coalesce(parent.quality_status = c.quality_status, false)
  ) AS row
  FROM private.source_observation c
  JOIN private.extraction_run run ON run.id = c.extraction_run_id
  JOIN guard g ON g.ok = 1 AND run.source_id = g.source_id
  JOIN private.source_record_occurrence o ON o.id = c.occurrence_id
  LEFT JOIN accepted ac ON ac.occurrence_id = c.occurrence_id
  LEFT JOIN private.source_observation parent ON parent.id = c.parent_observation_id
  LEFT JOIN private.clause_disposition_current d ON d.observation_id = c.id
  LEFT JOIN private.reimport_batch rb ON rb.id::text = run.manifest ->> 'batch_id'
  LEFT JOIN private.reimport_writer_profile wp
    ON wp.source_id = rb.source_id AND wp.profile_id = rb.profile_id AND wp.profile_sha256 = rb.profile_sha256
  WHERE c.observation_kind = 'clause'
), event_rows AS (
  SELECT e.element_id, jsonb_build_object(
    'batch_id', b.id::text,
    'manifest_sha256', b.manifest_sha256,
    'batch_status', b.status,
    'profile_id', b.profile_id,
    'profile_sha256', b.profile_sha256,
    'row_sha256', encode(pg_catalog.sha256(convert_to(e::text, 'UTF8')), 'hex'),
    'element_id', e.element_id,
    'source_record_key', e.source_record_key
  ) AS row
  FROM private.reimport_event e
  JOIN private.reimport_batch b ON b.id = e.batch_id
  JOIN guard g ON g.ok = 1 AND b.source_id = g.source_id
  WHERE e.operation = 'clause_evidence'
), neutral AS (
  SELECT jsonb_build_object(
    'person', (SELECT encode(pg_catalog.sha256(convert_to(coalesce(string_agg(x::text, E'\n' ORDER BY x::text COLLATE "C"), ''), 'UTF8')), 'hex') FROM public.person x),
    'fact', (SELECT encode(pg_catalog.sha256(convert_to(coalesce(string_agg(x::text, E'\n' ORDER BY x::text COLLATE "C"), ''), 'UTF8')), 'hex') FROM public.fact x),
    'assertion', (SELECT encode(pg_catalog.sha256(convert_to(coalesce(string_agg(x::text, E'\n' ORDER BY x::text COLLATE "C"), ''), 'UTF8')), 'hex') FROM public.assertion x),
    'conclusion', (SELECT encode(pg_catalog.sha256(convert_to(coalesce(string_agg(x::text, E'\n' ORDER BY x::text COLLATE "C"), ''), 'UTF8')), 'hex') FROM public.conclusion x),
    'narrative', (SELECT encode(pg_catalog.sha256(convert_to(coalesce(string_agg(x::text, E'\n' ORDER BY x::text COLLATE "C"), ''), 'UTF8')), 'hex') FROM public.narrative x),
    'relation', (SELECT encode(pg_catalog.sha256(convert_to(coalesce(string_agg(x::text, E'\n' ORDER BY x::text COLLATE "C"), ''), 'UTF8')), 'hex') FROM public.relation x),
    'family_member', (SELECT encode(pg_catalog.sha256(convert_to(coalesce(string_agg(x::text, E'\n' ORDER BY x::text COLLATE "C"), ''), 'UTF8')), 'hex') FROM public.family_member x),
    'citation', (SELECT encode(pg_catalog.sha256(convert_to(coalesce(string_agg(x::text, E'\n' ORDER BY x::text COLLATE "C"), ''), 'UTF8')), 'hex') FROM public.citation x),
    'person_external_id', (SELECT encode(pg_catalog.sha256(convert_to(coalesce(string_agg(x::text, E'\n' ORDER BY x::text COLLATE "C"), ''), 'UTF8')), 'hex') FROM public.person_external_id x),
    'source_mention', (SELECT encode(pg_catalog.sha256(convert_to(coalesce(string_agg(x::text, E'\n' ORDER BY x::text COLLATE "C"), ''), 'UTF8')), 'hex') FROM private.source_mention x),
    'source_record', (SELECT encode(pg_catalog.sha256(convert_to(coalesce(string_agg(x::text, E'\n' ORDER BY x::text COLLATE "C"), ''), 'UTF8')), 'hex') FROM private.source_record x),
    'source_record_occurrence', (SELECT encode(pg_catalog.sha256(convert_to(coalesce(string_agg(x::text, E'\n' ORDER BY x::text COLLATE "C"), ''), 'UTF8')), 'hex') FROM private.source_record_occurrence x),
    'source_record_anchor_event', (SELECT encode(pg_catalog.sha256(convert_to(coalesce(string_agg(x::text, E'\n' ORDER BY x::text COLLATE "C"), ''), 'UTF8')), 'hex') FROM private.source_record_anchor_event x),
    'narrative_record_publication', (SELECT encode(pg_catalog.sha256(convert_to(coalesce(string_agg(x::text, E'\n' ORDER BY x::text COLLATE "C"), ''), 'UTF8')), 'hex') FROM private.narrative_record_publication x),
    'source_observation_non_clause', (SELECT encode(pg_catalog.sha256(convert_to(coalesce(string_agg(x::text, E'\n' ORDER BY x::text COLLATE "C"), ''), 'UTF8')), 'hex') FROM private.source_observation x WHERE x.observation_kind <> 'clause'),
    'source_observation_clause_other_sources', (SELECT encode(pg_catalog.sha256(convert_to(coalesce(string_agg(x::text, E'\n' ORDER BY x::text COLLATE "C"), ''), 'UTF8')), 'hex')
      FROM private.source_observation x JOIN private.extraction_run er ON er.id = x.extraction_run_id, guard g
      WHERE x.observation_kind = 'clause' AND er.source_id <> g.source_id),
    'clause_disposition_other_sources', (SELECT encode(pg_catalog.sha256(convert_to(coalesce(string_agg(x::text, E'\n' ORDER BY x::text COLLATE "C"), ''), 'UTF8')), 'hex')
      FROM private.clause_disposition x JOIN private.source_observation ob ON ob.id = x.observation_id
      JOIN private.extraction_run er ON er.id = ob.extraction_run_id, guard g
      WHERE er.source_id <> g.source_id)
  ) AS hashes
)
SELECT jsonb_build_object(
  'schema_version', 'daa-clause-evidence-projection-v1',
  'source_id', g.source_id,
  'database_target_identity', jsonb_build_object(
    'database_name', current_database(),
    'system_identifier_sha256', encode(pg_catalog.sha256(convert_to((pg_control_system()).system_identifier::text, 'UTF8')), 'hex')
  ),
  'source_records', (SELECT coalesce(jsonb_agg(jsonb_build_object('record_key', record_key) ORDER BY record_key COLLATE "C"), '[]'::jsonb) FROM records),
  'source_anchors', (SELECT coalesce(jsonb_agg(jsonb_build_object('record_key', record_key, 'occurrence_key', occurrence_key) ORDER BY record_key COLLATE "C", occurrence_key COLLATE "C"), '[]'::jsonb) FROM accepted),
  'narrative_bindings', (SELECT coalesce(jsonb_agg(jsonb_build_object('record_key', record_key, 'narrative_id', narrative_id, 'status', status) ORDER BY record_key COLLATE "C", narrative_id, status COLLATE "C"), '[]'::jsonb) FROM bound),
  'narrative_sha256', (SELECT coalesce(jsonb_agg(jsonb_build_object('narrative_id', n.id, 'sha256', encode(pg_catalog.sha256(convert_to(n.tekst, 'UTF8')), 'hex')) ORDER BY n.id), '[]'::jsonb)
                       FROM public.narrative n WHERE n.id IN (SELECT narrative_id FROM bound)),
  'persons', (SELECT coalesce(jsonb_agg(jsonb_build_object('person_id', q.person_id) ORDER BY q.person_id), '[]'::jsonb)
              FROM (SELECT DISTINCT n.subjekt_id AS person_id FROM public.narrative n
                    WHERE n.subjekt_type = 'person' AND n.id IN (SELECT narrative_id FROM bound)) q),
  'clauses', (SELECT coalesce(jsonb_agg(row ORDER BY occurrence_key COLLATE "C", clause_ordinal), '[]'::jsonb) FROM clause_rows),
  'clause_evidence_events', (SELECT coalesce(jsonb_agg(row ORDER BY element_id COLLATE "C"), '[]'::jsonb) FROM event_rows),
  'neutral_sha256', neutral.hashes
)::text AS projection
FROM guard g, neutral
WHERE g.ok = 1
```

Bevidste afvigelser fra runbookens 1939-snapshot: bindinger for **alle** statusser (2018-20 har 46 `draft`), `status` i rækken, og klausulinventaret er ikke filtreret på accepterede ankre.

- [ ] **Step 4: Skriv `anon`-delen, målidentiteten og driveren**

`.claude/skills/daa-extract/scripts/clause_evidence_anon_projection.sql` (ingen afsluttende semikolon):

```sql
-- Laese-kun klausul-projektion, anon-delen (spec 4.1.6 anon-hashes, issue 195).
-- Koeres af driveren under SET LOCAL ROLE anon i samme transaktion som ejer-delen.
-- Hasher hele raekker, som anon ser dem gennem RLS. Returnerer kolonnen anon_sha256.
WITH guard AS (
  SELECT CASE
    WHEN current_user <> 'anon'
      THEN ('CLAUSE_PROJECTION_NOT_ANON:' || current_user)::int
    WHEN current_setting('transaction_read_only') <> 'on'
      THEN ('CLAUSE_PROJECTION_NOT_READ_ONLY:' || current_setting('transaction_read_only'))::int
    WHEN current_setting('transaction_isolation') <> 'repeatable read'
      THEN ('CLAUSE_PROJECTION_NOT_REPEATABLE_READ:' || current_setting('transaction_isolation'))::int
    ELSE 1
  END AS ok
)
SELECT jsonb_build_object(
  'assertion', (SELECT encode(pg_catalog.sha256(convert_to(coalesce(string_agg(x::text, E'\n' ORDER BY x::text COLLATE "C"), ''), 'UTF8')), 'hex') FROM public.assertion x),
  'citation', (SELECT encode(pg_catalog.sha256(convert_to(coalesce(string_agg(x::text, E'\n' ORDER BY x::text COLLATE "C"), ''), 'UTF8')), 'hex') FROM public.citation x),
  'conclusion', (SELECT encode(pg_catalog.sha256(convert_to(coalesce(string_agg(x::text, E'\n' ORDER BY x::text COLLATE "C"), ''), 'UTF8')), 'hex') FROM public.conclusion x),
  'fact', (SELECT encode(pg_catalog.sha256(convert_to(coalesce(string_agg(x::text, E'\n' ORDER BY x::text COLLATE "C"), ''), 'UTF8')), 'hex') FROM public.fact x),
  'family_member', (SELECT encode(pg_catalog.sha256(convert_to(coalesce(string_agg(x::text, E'\n' ORDER BY x::text COLLATE "C"), ''), 'UTF8')), 'hex') FROM public.family_member x),
  'narrative', (SELECT encode(pg_catalog.sha256(convert_to(coalesce(string_agg(x::text, E'\n' ORDER BY x::text COLLATE "C"), ''), 'UTF8')), 'hex') FROM public.narrative x),
  'person', (SELECT encode(pg_catalog.sha256(convert_to(coalesce(string_agg(x::text, E'\n' ORDER BY x::text COLLATE "C"), ''), 'UTF8')), 'hex') FROM public.person x),
  'person_external_id', (SELECT encode(pg_catalog.sha256(convert_to(coalesce(string_agg(x::text, E'\n' ORDER BY x::text COLLATE "C"), ''), 'UTF8')), 'hex') FROM public.person_external_id x)
)::text AS anon_sha256
FROM guard
WHERE ok = 1
```

`.claude/skills/daa-extract/scripts/clause_evidence_target_identity.sql` (ingen afsluttende semikolon):

```sql
-- Maalidentitetens hash: sha256(database_name + linjeskift + sha256(system_identifier)).
-- Samme formel som target_sha256 i compare_clause_evidence_projection.py.
SELECT encode(pg_catalog.sha256(convert_to(
  current_database() || E'\n' ||
  encode(pg_catalog.sha256(convert_to((pg_control_system()).system_identifier::text, 'UTF8')), 'hex'),
  'UTF8')), 'hex') AS database_target_sha256
```

`.claude/skills/daa-extract/scripts/clause_evidence_projection.psql`:

```
-- Klausul-projektionens driver (issue 195). Kør:
--   DAA_PROJECTION_SQL_DIR=<mappe med clause_evidence_*.sql> \
--     psql -X -At -q -v ON_ERROR_STOP=1 -v source_id=<id> -f clause_evidence_projection.psql > <ny fil>
-- Ejer-delen og anon-delen tages i SAMME read-only snapshot. Output: én linje JSON.
\set ON_ERROR_STOP on
-- Uden -v source_id: tom værdi, så SQL-guarden rejser CLAUSE_PROJECTION_SOURCE_ID_MISSING.
\if :{?source_id}
\else
\set source_id ''
\endif
\set main_sql `cat "$DAA_PROJECTION_SQL_DIR/clause_evidence_projection.sql"`
\set anon_sql `cat "$DAA_PROJECTION_SQL_DIR/clause_evidence_anon_projection.sql"`
BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY;
SELECT set_config('daa.projection_source_id', :'source_id', true) AS projection_source_id \gset
:main_sql \gset
SET LOCAL ROLE anon;
:anon_sql \gset
RESET ROLE;
SELECT ((:'projection')::jsonb || jsonb_build_object('anon_sha256', (:'anon_sha256')::jsonb))::text;
COMMIT;
```

- [ ] **Step 5: Kør integrationstesten igen**

Run (samme miljø som Step 2): `Rscript tests/integration/test-reimport-clause-evidence.R`
Expected: slutter med `clause_evidence integration OK`.

Symptomer og rette sted: `CLAUSE_PROJECTION_SOURCE_ID_MISSING` → `-v source_id` mangler i `projection()`; `syntax error at or near ":"` → en SQL-fil ender med `;` eller har `'`/`;` i en kommentar (ret filen, ikke driveren); `permission denied` under `anon` → CI-basens grants (sammenlign med `db-rls.sql`), ikke projektionen.

- [ ] **Step 6: Kør guard-negativerne direkte i psql**

```bash
D=.claude/skills/daa-extract/scripts
psql -X -At -v ON_ERROR_STOP=1 -c "SET daa.projection_source_id='1'" -f $D/clause_evidence_projection.sql 2>&1 | grep -o 'CLAUSE_PROJECTION_[A-Z_]*'
PGOPTIONS='-c default_transaction_read_only=on' psql -X -At -v ON_ERROR_STOP=1 -c "SET daa.projection_source_id='1'" -f $D/clause_evidence_projection.sql 2>&1 | grep -o 'CLAUSE_PROJECTION_[A-Z_]*'
PGOPTIONS='-c default_transaction_read_only=on -c default_transaction_isolation=repeatable\ read' psql -X -At -v ON_ERROR_STOP=1 -f $D/clause_evidence_projection.sql 2>&1 | grep -o 'CLAUSE_PROJECTION_[A-Z_]*'
PGOPTIONS='-c default_transaction_read_only=on -c default_transaction_isolation=repeatable\ read' psql -X -At -v ON_ERROR_STOP=1 -f $D/clause_evidence_anon_projection.sql 2>&1 | grep -o 'CLAUSE_PROJECTION_[A-Z_]*'
DAA_PROJECTION_SQL_DIR=$D psql -X -At -q -v ON_ERROR_STOP=1 -f $D/clause_evidence_projection.psql 2>&1 | grep -o 'CLAUSE_PROJECTION_[A-Z_]*'
DAA_PROJECTION_SQL_DIR=$D psql -X -At -q -v ON_ERROR_STOP=1 -v source_id=1 -f $D/clause_evidence_projection.psql | head -c 2; echo
```

(Filerne mangler semikolon; psql sender dem ved filens slutning.)
Expected, i rækkefølge: `CLAUSE_PROJECTION_NOT_READ_ONLY`, `CLAUSE_PROJECTION_NOT_REPEATABLE_READ`, `CLAUSE_PROJECTION_SOURCE_ID_MISSING`, `CLAUSE_PROJECTION_NOT_ANON`, `CLAUSE_PROJECTION_SOURCE_ID_MISSING` (driveren uden `-v source_id`), `{"`. Basen har ingen source 1; det er kun en syntaks- og guardtest.

- [ ] **Step 7: Ryd den disponerbare base op og commit**

```bash
dropdb "$(cat "${TMPDIR:-/tmp}/klausulproj-db-name.txt")" && rm "${TMPDIR:-/tmp}/klausulproj-db-name.txt"
git add .claude/skills/daa-extract/scripts/clause_evidence_projection.sql \
        .claude/skills/daa-extract/scripts/clause_evidence_anon_projection.sql \
        .claude/skills/daa-extract/scripts/clause_evidence_target_identity.sql \
        .claude/skills/daa-extract/scripts/clause_evidence_projection.psql \
        tests/integration/test-reimport-clause-evidence.R
git commit -m "feat(evidens): læse-kun klausul-projektion med anon-hashes og ende-til-ende-test i CI (#195)"
```

(Basen er oprettet af denne task og indeholder kun syntetik; den må droppes uden yderligere bekræftelse.)

---

### Task 4: Runbook, beslutning og status

**Files:**
- Modify: `docs/runbooks/evidence-import-phase-gate.md` (ny sektion lige før `## Hvad denne gate ikke beviser`)
- Modify: `docs/decisions.md` (ny post øverst, lige under indledningen)
- Modify: `docs/evidensbaseret-genimport/status.md`; evt. `docs/database-current-state.md` (Step 4)

- [ ] **Step 1: Tilføj runbook-sektionen**

Indsæt i `docs/runbooks/evidence-import-phase-gate.md` før `## Hvad denne gate ikke beviser`:

````markdown
## Klausul-projektion (udgaveneutral delta-afstemning, spec §11.1)

Gælder `clause_evidence`-kørsler (4.1c). Den afstemmer **én kørsels delta**, ikke
historien: den kender ingen udgave eller fase og afhænger ikke af
`reconcile_evidence_phase_gate.py`, som er låst til 1939/source 3 og ikke er i `main`.
Værktøjet er i `main` (#195): `clause_evidence_projection.psql` med tre SQL-filer og
`compare_clause_evidence_projection.py`.

**Hvad et `match` beviser** (mod den godkendte måldatabase):

1. De fem kildeprojektioner (records, accepterede ankre, narrativbindinger i alle
   statusser, narrativ-hashes, personer) er identiske før og efter.
2. Hele rækker er uændrede i `person`, `fact`, `assertion`, `conclusion`, `narrative`,
   `relation`, `family_member`, `citation`, `person_external_id`, `source_mention`,
   `source_record`, `source_record_occurrence`, `source_record_anchor_event`,
   `narrative_record_publication`, alle ikke-klausul-observationer og andre kilders
   klausuler og dispositioner.
3. Det, rollen `anon` ser gennem RLS i `assertion`, `citation`, `conclusion`, `fact`,
   `family_member`, `narrative`, `person` og `person_external_id`, er uændret.
4. Klausulerne for manifestets records er præcis manifestets (spænd, klassifikation,
   flag, tekst-hash, helpost-hash, startdisposition v1), og hver bærer writerens
   invarianter: samme forekomst, sider og kvalitet som helposten, helposten er rod,
   `extraction_method` slutter på regelversionen, kørslen er bundet til manifestet og
   batchen, dispositionen er maskinel med batchens evidens.
5. Én `finalized` batch med manifestets **genberegnede** hash og writer-profilens id og
   hash, én hændelse pr. record, alle klausuler fra én kørsel, hvis proveniensfelter
   matcher profilen; alle ældre `clause_evidence`-hændelser for kilden er bevaret uændret.
6. Ingen anden klausul i kildens inventar — også under forekomster uden accepteret
   anker — er tilføjet, fjernet eller ændret, målt på hele rækken og hele
   dispositionshistorikken.

**Afstemt delta:** kildens nye klausuler med dispositioner og de nye hændelser, som
ovenfor. **Ikke afstemt** ud over de nævnte felter: `reimport_authorization`,
`reimport_batch` og `extraction_run`.

**Hvad det ikke beviser:** at prod er summen af tidligere faser; tabeller uden for
listerne ovenfor, herunder autorisations-, batch- og kørselsrækkernes øvrige indhold;
RLS/ACL-definitioner (uændret DDL forudsættes).

**Forudsætninger, der hører til 4.1c's egen GO-pakke (ikke denne procedure):**
backup; writer-profilrækken for `daa-2018-20-clause-evidence-v1`, som **ikke findes i
prod** pr. 2026-09-17 — dens indsættelse er en varig prod-skrivning, der skal være et
hash-låst skridt med readback i 4.1c's prod-runbook (endnu ikke skrevet); apply.

**Procedure** (alt mod prod kører i projektejerens shell; sessionen læser kun de private
filer bagefter):

**Målbinding.** Alle psql-kald bruger den eksplicitte forbindelsesstreng `"$DAA_PROD_DSN"`
(Session pooler-DSN'en for DAA-projektet), aldrig omgivende `PG*`-variabler. Projektejeren
verificerer DSN'ens projekt-reference mod Supabase-dashboardet, før preflight køres.
`EXPECTED_TARGET` skrives ind i 4.1c's GO-dokument **før** backup, sammen med
`database_name`, og backup og rehearsal i 4.1c's GO-pakke tages mod samme DSN. Komparatoren
håndhæver derefter, at før- og efter-projektion er taget mod netop den database. Den
tilbageværende tillid hviler på én menneskelig kontrol: at DSN'en er prod.

0. **Læse-kun preflight** (resultatet skrives ind i GO-dokumentet):

   ```bash
   PGOPTIONS='-c default_transaction_read_only=on' psql "$DAA_PROD_DSN" -X -At -v ON_ERROR_STOP=1 \
     -c "SELECT current_database()" \
     -f .claude/skills/daa-extract/scripts/clause_evidence_target_identity.sql \
     -c "SELECT pg_has_role(current_user, 'anon', 'MEMBER')"
   ```

   Linje 1 er `database_name`, linje 2 `EXPECTED_TARGET`. Er linje 3 ikke `t`, kan
   projektionen ikke tage `anon`-hashes mod denne forbindelse — stop.
1. **Redaktionspause** fra før- til efter-projektion. Enhver redigering i vinduet giver
   `CANONICAL_DRIFT`/`ANON_DRIFT` (fail-closed).
2. **Ny run-mappe pr. forsøg; eksisterende mappe afvises, intet overskrives:**

   ```bash
   umask 077; setopt noclobber 2>/dev/null || set -o noclobber
   mkdir -p ~/.private/klausul-projektion-prod && chmod 700 ~/.private/klausul-projektion-prod
   RUN=$(mktemp -d ~/.private/klausul-projektion-prod/run-XXXXXXXX) || { echo "STOP: run-mappe"; exit 1; }
   ```

3. **Før-projektion** (efter profilrækken, før apply):

   ```bash
   DAA_PROJECTION_SQL_DIR=.claude/skills/daa-extract/scripts \
     psql "$DAA_PROD_DSN" -X -At -q -v ON_ERROR_STOP=1 -v source_id=1 \
     -f .claude/skills/daa-extract/scripts/clause_evidence_projection.psql > "$RUN/foer.json"
   ```

4. Apply af 4.1c efter dens egen GO.
5. **Efter-projektion:** samme kommando til `"$RUN/efter.json"`.
6. **Afstemning:**

   ```bash
   /usr/bin/python3 .claude/skills/daa-extract/scripts/compare_clause_evidence_projection.py \
     --manifest ~/.private/<4.1c-manifest>.json --before "$RUN/foer.json" --after "$RUN/efter.json" \
     --expect-target-sha256 <EXPECTED_TARGET fra GO-dokumentet> --report "$RUN/rapport.json"
   shasum -a 256 "$RUN"/*.json
   ```

   `--allow-empty` må **ikke** bruges mod prod.
7. **Bestået** kræver exit 0, `"status": "match"`, `database_target_sha256` =
   `EXPECTED_TARGET`, og at `counts` er lig rehearsalens (`clause-evidence-148-rehearsal.md`,
   afsnit »Klausul-projektion«).
8. **NO-GO** (exit 1): bevar run-mappen urørt, læs kun fejlkoden og den private rapports
   nøgler/feltnavne, og stop. Reparér aldrig prod for at få `match`; vejen tilbage er
   restore (decisions 2026-09-17).
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

**Valgt (C):** en læse-kun projektion (ejer + `anon` i ét snapshot) og en komparator uden
databaseadgang, som beviser én kørsels delta mod en godkendt måldatabase.

**Fravalgt:**
- **A — håndskrevet bidrag i runbooken, som 149a/b.** Runbooken forbyder selv manuelt
  konstruerede bidrag; afstemningen ville være en erklæring, ikke et bevis.
- **B — merge og generalisér 1939-gaten.** Omgør #170, kræver et nyt historisk scope
  (149a → 149b → 4.1c), og 149a/b kan formentlig ikke bindes bagudrettet.

**Prisen, sagt højt:** C beviser ikke historisk fuldstændighed og dækker kun de navngivne
tabeller; helrækkehashes kræver redaktionspause i vinduet. Fortolknings-projektionen
(4.4) står i #196.

**Review:** Codex `gpt-5.6-sol` gav NO-GO to gange før kode (runde 1: 7 BLOCKER; runde 2:
1 ny BLOCKER + 5 delvist lukkede). Rettet: manifest-hashen genberegnes, én batch og én
kørsel bundet til writer-profilen, writer-invarianter tjekkes, klausulinventaret filtreres
ikke på ankre og sammenlignes på hele rækker og dispositionshistorik, ældre hændelser skal
være bevaret, `anon`-hashes er med, målidentiteten er bundet til en eksplicit DSN,
rehearsal-stop er kode. Overdraget/indsnævret: profilrækkens prod-indsættelse hører til
4.1c's GO-pakke; autorisations-, batch- og kørselsrækker afstemmes kun i projekterede
felter; resttilliden er, at DSN'en er prod.

**Fund:** 4.1c-rehearsalens »kanonisk lag identisk« (`kanonisk()` i det private
apply-script) var en hash af `count(*)` pr. tabel. Den erstattes af helrækkehashes.
```

- [ ] **Step 3: Opdatér `status.md`**

I `docs/evidensbaseret-genimport/status.md`, `## Åbne blokeringer`, erstat første punkt (begynder `- **Trin 4's skema er i prod, dets data er ikke.**`) med:

```markdown
- **Trin 4's skema er i prod, dets data er ikke.** Skema og writere deployet 2026-09-17.
  Første datakørsel er 4.1c (klausuler, nul kanonisk delta). Fortrydelseskvitteringen er
  givet (decisions 2026-09-17: fortryd = restore), og klausul-projektionen er defineret
  i fase-pakke-runbooken som et udgaveneutralt delta-tjek (#195). Tilbage før prod-GO:
  4.1c's prod-runbook (herunder writer-profilrækken, som ikke findes i prod) og
  projektejerens GO pr. apply. Fortolknings-projektionen for 4.4 mangler (#196), og for
  `interpretation_proposal` findes ingen prod-fortrydelse (spec åbent punkt 11.5).
```

I `## Næste tilladte arbejde`, erstat punkt 2 med:

```markdown
2. **Trin 4's første datakørsel i prod: 4.1c** — kvittering og klausul-projektion er på
   plads; mangler en prod-runbook (profilrække, backup, rehearsal) og projektejerens GO.
```

- [ ] **Step 4: Verificér at intet er forældet**

Run: `grep -n "klausul-projektion i fase-pakke-runbooken" docs/evidensbaseret-genimport/status.md docs/database-current-state.md docs/changelog.md`
Expected: træf kun i den nye tekst i `status.md` og i historiske changelog-poster (de rettes ikke). Et træf i `docs/database-current-state.md`, der siger projektionen mangler, rettes til samme formulering som i Step 3 — kun den sætning.

- [ ] **Step 5: Commit**

```bash
git add docs/runbooks/evidence-import-phase-gate.md docs/decisions.md docs/evidensbaseret-genimport/status.md
git add docs/database-current-state.md  # kun hvis Step 4 rettede den
git commit -m "docs(genimport): klausul-projektion i fase-pakke-runbooken og beslutning om vej C (#195)"
```

---

### Task 5: Rehearsal mod prod-tilstanden 2026-09-17

**Files:**
- Create (privat, ikke i git): `~/.private/klausul-projektion/rehearsal.sh`, run-mapper under `~/.private/klausul-projektion/`
- Create (gitignoreret): `work/klausul-projektion/03-clause-dryrun.R`, `work/klausul-projektion/04-clause-apply.R` (kopier)
- Modify: `docs/evidensbaseret-genimport/clause-evidence-148-rehearsal.md`, `docs/changelog.md`

**Interfaces:**
- Consumes: Task 2's CLI, Task 3's driver og SQL, template-basen `daa_trin4_rehearsal_20260917141446`, manifest `~/.private/148c-manifest-20260910190838.json`, 4.1c's scripts `~/.private/148-rehearsal-scripts/03-clause-dryrun.R` og `04-clause-apply.R`.
- Produces: tal til runbookens bestået-kriterie (Task 4, Step 1, punkt 7).

Alt sker lokalt mod engangskopier. Intet mod prod. Kun tal, koder og hashes i rapport og chat.

- [ ] **Step 1: Forbered**

```bash
umask 077
mkdir -p ~/.private/klausul-projektion work/klausul-projektion && chmod 700 ~/.private/klausul-projektion
cp ~/.private/148-rehearsal-scripts/03-clause-dryrun.R work/klausul-projektion/03-clause-dryrun.R
cp ~/.private/148-rehearsal-scripts/04-clause-apply.R work/klausul-projektion/04-clause-apply.R
shasum -a 256 ~/.private/148c-manifest-20260910190838.json
psql -X -At -d postgres -c "SELECT count(*) FROM pg_stat_activity WHERE datname='daa_trin4_rehearsal_20260917141446'"   # skal være 0
```

Scripts finder repoet som `../..` fra deres placering; derfor kopierne under `work/klausul-projektion/`. `createdb -T` fejler, hvis template-basen har åbne forbindelser.

- [ ] **Step 2: Skriv rehearsal-scriptet**

`~/.private/klausul-projektion/rehearsal.sh`:

```zsh
#!/bin/zsh
# Klausul-projektion (#195): rehearsal mod prod-tilstanden 2026-09-17.
# Engangskopier af restore + trin 4-migrationer. Alt lokalt. Printer kun tal, koder og hashes.
# Hver stopport er kode: scriptet slutter med exit != 0 ved første afvigelse.
set -euo pipefail
setopt noclobber
umask 077
export PGTZ=UTC PGHOST=localhost PGPORT=5432
PG=/opt/homebrew/opt/postgresql@17/bin
REPO=/Users/johanreventlow/TypeScript/danmarksadelsaarbog/.claude/worktrees/klausul-projektion
TEMPLATE=daa_trin4_rehearsal_20260917141446
MANIFEST=$HOME/.private/148c-manifest-20260910190838.json
SQLDIR=$REPO/.claude/skills/daa-extract/scripts
CMP=$SQLDIR/compare_clause_evidence_projection.py
fail() { print -u2 "STOPPORT: $1"; exit 1; }
ART=$(mktemp -d "$HOME/.private/klausul-projektion/run-XXXXXXXX") || fail "run-mappe"
chmod 700 "$ART" || fail "chmod run-mappe"
RUNID=${ART:t}
DB="klausulproj_rehearsal_$(date +%Y%m%d%H%M%S)"
cd "$REPO" || fail "repo"

expect_eq() { [[ "$2" == "$3" ]] || fail "$1: fik '$2', forventede '$3'"; }
baseline() {
  $PG/psql -X -At -v ON_ERROR_STOP=1 -d "$1" -c "SELECT (SELECT count(*) FROM private.source_observation WHERE observation_kind='person_post')
    ||'|'||(SELECT count(*) FROM private.source_observation WHERE observation_kind='clause')
    ||'|'||(SELECT count(*) FROM private.reimport_writer_profile WHERE source_id=1 AND profile_id='daa-2018-20-clause-evidence-v1')"
}
project() {  # $1 = database, $2 = ny outputfil
  DAA_PROJECTION_SQL_DIR=$SQLDIR $PG/psql -X -At -q -v ON_ERROR_STOP=1 -v source_id=1 -d "$1" \
    -f "$SQLDIR/clause_evidence_projection.psql" > "$2" || fail "projektion af $1"
  [[ $(wc -l < "$2") -eq 1 ]] || fail "projektion af $1 er ikke én linje"
}
compare() {  # $1 = efter-fil, $2 = rapportnavn; sætter CMP_STATUS og CMP_OUT
  set +e
  CMP_OUT=$(/usr/bin/python3 "$CMP" --manifest "$MANIFEST" --before "$ART/foer.json" --after "$1" \
    --expect-target-sha256 "$TARGET" --report "$ART/$2")
  CMP_STATUS=$?
  set -e
  print -r -- "$CMP_OUT"
}
code_of() { /usr/bin/python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("code", ""))' "$1"; }

echo "== kopi af template -> $DB =="
$PG/createdb -T "$TEMPLATE" "$DB"
expect_eq udgangspunkt "$(baseline "$DB")" "591|0|0"
TARGET=$($PG/psql -X -At -v ON_ERROR_STOP=1 -d "$DB" -f "$SQLDIR/clause_evidence_target_identity.sql")
[[ "$TARGET" =~ ^[0-9a-f]{64}$ ]] || fail "målidentitet"
echo "målidentitet: $TARGET"

echo "== dry-run (indsætter writer-profilrækken, ruller data tilbage) =="
PGDATABASE="$DB" PGUSER=$(whoami) Rscript work/klausul-projektion/03-clause-dryrun.R "$MANIFEST" > "$ART/dryrun.log" 2>&1 \
  || fail "dry-run exit != 0 (se $ART/dryrun.log)"
grep -qx 'DRY_RUN_OK' "$ART/dryrun.log" || fail "DRY_RUN_OK mangler"
expect_eq "efter dry-run" "$(baseline "$DB")" "591|0|1"

echo "== før-projektion =="
project "$DB" "$ART/foer.json"

echo "== apply (4.1c-scriptet, med eget replay) =="
PGDATABASE="$DB" PGUSER=$(whoami) Rscript work/klausul-projektion/04-clause-apply.R "$MANIFEST" > "$ART/apply.log" 2>&1 \
  || fail "apply exit != 0 (se $ART/apply.log)"
grep -qx 'APPLY_OK' "$ART/apply.log" || fail "APPLY_OK mangler"
expect_eq "efter apply" "$(baseline "$DB")" "591|868|1"

echo "== efter-projektion =="
project "$DB" "$ART/efter.json"

echo "== afstemning (forventet match) =="
compare "$ART/efter.json" rapport-match.json
expect_eq "match exit" "$CMP_STATUS" "0"
/usr/bin/python3 - "$CMP_OUT" "$TARGET" <<'PY' || fail "match-tal"
import json, sys
r = json.loads(sys.argv[1])
assert r["status"] == "match", r["status"]
assert r["database_target_sha256"] == sys.argv[2]
c = r["counts"]
assert c["records"] == 591 and c["clauses"] == 868, (c["records"], c["clauses"])
assert c["dispositions"] == {"afventer_fortolkning": 617, "maskinelt_flagget": 251}, c["dispositions"]
assert c["neutral_lists"] == {"narrative_bindings": 587, "narrative_sha256": 587, "persons": 587,
                              "source_anchors": 591, "source_records": 591}, c["neutral_lists"]
assert c["allowed_empty"] == []
PY

# Negativerne skal tage efter-projektionen fra SAMME database som før-projektionen:
# målidentiteten hasher databasenavnet, så en kopi med andet navn giver korrekt
# TARGET_MISMATCH (negativ 0) og ville skjule enhver anden fejlkode. Negativ 2 og 1
# muterer derfor $DB selv, i den rækkefølge komparatoren tjekker: først kanonisk
# indhold (fem lister uændrede), derefter en neutral liste oven i.

echo "== negativ 0: navngiven kopi af databasen (forventet TARGET_MISMATCH) =="
$PG/createdb -T "$DB" "${DB}_kopi"
project "${DB}_kopi" "$ART/efter-kopi.json"
compare "$ART/efter-kopi.json" rapport-kopi.json
expect_eq "neg0 exit" "$CMP_STATUS" "1"
expect_eq "neg0 kode" "$(code_of "$CMP_OUT")" "CLAUSE_PROJECTION_TARGET_MISMATCH"

echo "== negativ 2: én family_member-række slettet i \$DB (forventet CANONICAL_DRIFT) =="
$PG/psql -X -q -v ON_ERROR_STOP=1 -d "$DB" -c "SET session_replication_role = replica;
  DELETE FROM public.family_member WHERE ctid = (SELECT ctid FROM public.family_member LIMIT 1);"
project "$DB" "$ART/efter-neg2.json"
compare "$ART/efter-neg2.json" rapport-neg2.json
expect_eq "neg2 exit" "$CMP_STATUS" "1"
expect_eq "neg2 kode" "$(code_of "$CMP_OUT")" "CLAUSE_PROJECTION_CANONICAL_DRIFT"

echo "== negativ 1: ændret occurrence_key i \$DB oven i negativ 2 (forventet NEUTRALITY_DRIFT) =="
$PG/psql -X -q -v ON_ERROR_STOP=1 -d "$DB" -c "SET session_replication_role = replica;
  UPDATE private.source_record_occurrence SET occurrence_key = occurrence_key || '-neg'
   WHERE id = (SELECT a.occurrence_id FROM private.source_record_anchor_current a
                 JOIN private.source_record r ON r.id = a.source_record_id
                WHERE r.source_id = 1 AND a.decision_status = 'accepted'
                ORDER BY r.record_key COLLATE \"C\" LIMIT 1);"
project "$DB" "$ART/efter-neg1.json"
compare "$ART/efter-neg1.json" rapport-neg1.json
expect_eq "neg1 exit" "$CMP_STATUS" "1"
expect_eq "neg1 kode" "$(code_of "$CMP_OUT")" "CLAUSE_PROJECTION_NEUTRALITY_DRIFT"

shasum -a 256 "$MANIFEST" "$ART"/*.json
echo "databaser: $DB ${DB}_kopi"
echo "REHEARSAL_OK $RUNID"
```

`session_replication_role = replica` slår triggere og FK fra i den ene session i rehearsal-basen, så mutationen ikke stoppes af en guard — kun for at fremkalde en ægte ændring i en engangsbase, efter at match-afstemningen er taget.

- [ ] **Step 3: Kør rehearsal**

Run: `zsh ~/.private/klausul-projektion/rehearsal.sh > ~/.private/klausul-projektion/rehearsal-$(date +%Y%m%d%H%M%S).log 2>&1; echo "exit=$?"`
Derefter kun den filtrerede log: `grep -E '^== |^målidentitet|STOPPORT|REHEARSAL_OK|^\{"|^[0-9a-f]{64} |^databaser' <logfil>`

Expected: `exit=0`, `REHEARSAL_OK <runid>`, match-JSON med `records 591`, `clauses 868`, og de tre negative (kopi → `TARGET_MISMATCH`, slettet `family_member` → `CANONICAL_DRIFT`, ændret forekomstnøgle → `NEUTRALITY_DRIFT`) med exit 1 og eksakt kode.

**Stopporte** er kode i scriptet. Ved exit ≠ 0: læs kun `STOPPORT:`-linjen og (ved komparator-NO-GO) fejlkoden og længden af `details.*` i den private rapport. Ret ikke forventningen; en negativ, der ikke giver sin kode, er et fund i værktøjet — stop og rapportér.

- [ ] **Step 4: Skriv rapportafsnittet**

Tilføj nederst i `docs/evidensbaseret-genimport/clause-evidence-148-rehearsal.md` et afsnit `## Klausul-projektion (#195) — rehearsal 2026-09-17` med de faktisk målte værdier: manifest-SHA, målidentitet, `foer.json`/`efter.json`-SHA'er, terminal-JSON for match (uden `input_sha256`-stier), de to negative koder, run-id. Tilføj i 4.1c-afsnittets »Intet kanonisk delta«-tekst sætningen: *»NB: målt som antal pr. tabel; indholdsbeviset er klausul-projektionen nedenfor.«*

- [ ] **Step 5: Changelog**

Tilføj øverst i `docs/changelog.md` (under `# Changelog`), med de målte tal indsat:

```markdown
## 2026-09-17 — Klausul-projektion: udgaveneutralt delta-tjek til 4.1c (#195)

Spec §11.1's klausul-projektion er bygget som vej C: en læse-kun projektion (ejer og
`anon` i ét snapshot) og en komparator uden databaseadgang. De beviser, at én
`clause_evidence`-kørsel skrev præcis manifestets klausuler, bundet til én batch og den
godkendte database, og at intet i de navngivne tabeller — heller ikke det offentligheden
ser — ændrede sig. Fortolknings-projektionen er udskudt til #196.

**Review:** Codex `gpt-5.6-sol` gav NO-GO i to runder før kode; alle fund rettet,
overdraget eller indsnævret (decisions 2026-09-17).

**Fund til 4.1c's prod-kørsel:** writer-profilrækken for `daa-2018-20-clause-evidence-v1`
findes ikke i prod; dens indsættelse er en varig prod-skrivning, der hører til 4.1c's GO.

**Rehearsal** mod prod-tilstanden 2026-09-17 (restore + trin 4-migrationer): `match` med
591 records og 868 klausuler; en navngiven kopi gav `TARGET_MISMATCH`, en ændret forekomstnøgle `NEUTRALITY_DRIFT`, en slettet
`family_member`-række `CANONICAL_DRIFT`. Tal: `clause-evidence-148-rehearsal.md`.

**Fund:** 4.1c-rehearsalens »kanonisk lag identisk« var en hash af antal rækker. Den nye
projektion hasher hele rækker.
```

Afviger de målte tal fra 591/868, er Step 3 ikke bestået — skriv ikke changelog-posten.

- [ ] **Step 6: Commit**

```bash
git add docs/evidensbaseret-genimport/clause-evidence-148-rehearsal.md docs/changelog.md
git commit -m "docs(genimport): rehearsal af klausul-projektionen mod prod-tilstanden (#195)"
```

- [ ] **Step 7: Oprydning (efter commit)**

`dropdb` de to engangsbaser (navnene står på `databaser:`-linjen). `~/.private/klausul-projektion/` bevares. `work/klausul-projektion/` må slettes. Template-basen `daa_trin4_rehearsal_20260917141446` røres ikke; om den skal slettes, afgør projektejeren.

---

## Selvtjek mod spec

| Krav | Task |
| --- | --- |
| §11.1: klausul-projektion defineret før 4.1c-afstemning i prod | 3 (projektion), 4 (runbook) |
| §11.1: issue før første prod-GO | #195 (oprettet 2026-09-17), #196 for fortolkning |
| §4.1.5: nul ændring i de fem projektioner | 1 (`NEUTRALITY_DRIFT`), 5 (negativ 1) |
| §4.1.6: neutralitetshashes uændrede | 1 (`CANONICAL_DRIFT`), 3 (helrækkehashes), 5 (negativ 2) |
| §4.1.6: `anon`-hashes uændrede | 1 (`ANON_DRIFT`), 3 (`anon`-del i samme snapshot) |
| §4.1.6: antal klausulrækker = ledgerens | skærpet til identitet felt for felt + writer-invarianter, 1, 5 (868) |
| §4.1.6: replay `already_applied` | 3 (projektion uændret efter replay) |
| §4.1.4: ekstern nøgle `(record_key, ordinal, verbatim_sha256)` | 1 (nøgle `(record_key, clause_ordinal)`, `verbatim_sha256` felt) |
| Ingen tekst ud af DB | 3 (hash i SQL), 2 (stdout uden details) |

## Revisionslog

**Revision 2 — Codex `gpt-5.6-sol`, NO-GO (7 BLOCKER, 3 MAJOR), 2026-09-17.** Alle fund
vurderet mod writer-koden og målinger på template-basen.

| # | Fund | Afgørelse |
| --- | --- | --- |
| 1 | Manifest-hashen genberegnes ikke; felter uden for rækkerne kan ændres | **Rettet:** `compute_manifest_sha256` = builderens formel, lukkede feltsæt; CI-fixturen får builderens hash via `--print-manifest-sha256`. Målt: det rigtige manifest genberegnes korrekt. |
| 2 | »Én batch« bevises ikke | **Rettet:** `batch_id` i hændelser, præcis ét nyt; binding til `disposition_evidence.batch_id` og `run_batch_id`. |
| 3 | Kun en del af writerens INSERT tjekkes | **Rettet som invarianter** (ikke UUID-felter): forekomst, rod, sider, kvalitet, `extraction_method`, kørsel, maskinel disposition + evidens. Klassificeret som writer-korrekthed. |
| 4 | Klausuler under ikke-accepterede forekomster usynlige | **Rettet:** inventar scoped via `extraction_run.source_id`, `record_key` nullable, identitet `(occurrence_key, clause_ordinal)`; andre kilders klausuler/dispositioner helrækkehashes. |
| 5 | `anon`-hashes fra §4.1.6 mangler | **Rettet:** `anon`-del i samme snapshot via psql-driver; 149b's 8 tabeller. Målt: `anon` kan læse og hashe; `\gset` over rolleskift virker. Preflight-tjek i runbook, fordi `SET ROLE anon` aldrig er kørt mod prod. |
| 6 | Rehearsal-stopporte kun tekst | **Rettet:** exit-status, tokens, tal og negative koder asserteres i scriptet. |
| 7 | Ikke bundet til godkendt mål | **Rettet:** `--expect-target-sha256` påkrævet; hash i terminal og rapport; preflight-SQL i runbook. |
| 8 | Profilrækkens prod-skrivning udefineret | **Overdraget** til 4.1c's prod-runbook (skrives ordret som forudsætning, ikke som skridt her). |
| 9 | Prod-artefakter kan overskrives | **Rettet:** run-mappe pr. forsøg, `noclobber`, fil-SHA'er i rapporten. |
| 10 | »Intet andet« bredere end målt | **Rettet + indsnævret:** fire kildetabeller + `citation`, `person_external_id`, `source_mention` helrækkehashes; eksplicit tilladt delta; påstande begrænset til navngivne tabeller. |

Desuden: `extensions.digest` erstattet af indbygget `pg_catalog.sha256`, så `anon`-delen ikke afhænger af extension-grants.

**Revision 3 — Codex `gpt-5.6-sol` runde 2, NO-GO, 2026-09-17.** Lukket i runde 2: #1, #2,
#5, #6, #8. Resten:

| # | Fund | Afgørelse |
| --- | --- | --- |
| 3 | `extraction_method` kun suffiks-tjek; kørslens proveniens mangler | **Rettet:** SQL beregner `run_matches_profile` (schema/extractor/profile-version + profilhash mod batchens writer-profil) og `extraction_method_matches_profile` (eksakt præfiks fra profilen); hændelser bærer `profile_id`/`profile_sha256` = manifestets; alle målklausuler skal dele én `run_id`. |
| 4 | Fremmede klausuler sammenlignes kun på udsnit; identitet ikke skemagaranteret | **Rettet:** identitet `observation_id`; `row_sha256` (hele rækken) og `disposition_history_sha256` (hele historikken) indgår i sammenligningen. |
| 7 | `EXPECTED_TARGET` skabes fra omgivende forbindelse | **Rettet så langt det kan:** eksplicit `"$DAA_PROD_DSN"` i alle kald, DSN verificeres mod dashboardet, `database_name` + hash skrives i GO før backup, backup/rehearsal mod samme DSN. Resttillid (at DSN'en er prod) er skrevet ordret i runbooken. |
| 9 | `mkdir -p` / `mkdir && chmod` under `set -e` | **Rettet:** `mktemp -d` i både runbook og rehearsal; `fail` defineres før første brug. |
| 10 | Goal/log overdriver »kun tilladt bogføring« | **Rettet:** Goal, Global Constraints og runbook skelner nu »afstemt delta« fra »ikke afstemt«. |
| A | Slettet ældre hændelse gav stadig `match` | **Rettet:** alle før-hændelser skal findes uændret efter (`CLAUSE_PROJECTION_EVENT_HISTORY_DRIFT`) før deltaet beregnes; hændelsesidentitet `(batch_id, element_id)`; negative tests for sletning og ændring. |
| B | `SOURCE_ID_MISSING` nås ikke via driveren | **Rettet:** `\if :{?source_id}` sætter tom værdi; målt: exit 3 med koden. Guard-trinnet tester driveren uden `-v`. |
| C | Ikke test for hver fejlkode | **Rettet:** CLI-tests for `REPORT_DIR_MISSING` og `ARGUMENTS_MISSING`. |

**Revision 4 — Codex runde 3, NO-GO, 2026-09-17.** Lukket: 3, 4, 7, 9, 10, B, C; ingen nye fejl.
Delvist: **A** — hændelser sammenlignedes kun på projekterede felter, så ændret `payload`,
`after_sha256` eller `created_at` i en gammel hændelse gav stadig `match`. **Rettet:**
`row_sha256` (hele `reimport_event`-rækken) indgår i hændelsen; negativ test ændrer kun den.

**Revision 5 — under udførelse af Task 5, 2026-09-17.** Rehearsal-scriptets negativer brugte
kopier med andet databasenavn; komparatoren svarede korrekt `TARGET_MISMATCH` (målidentiteten
hasher databasenavnet) og skjulte de tilsigtede koder. Positiv del bestod (591/868, 617/251).
**Rettet:** kopien er nu negativ 0 (`TARGET_MISMATCH`); negativ 2 og 1 muterer rehearsal-basen
selv, i komparatorens kontrolrækkefølge.
