from __future__ import annotations

import hashlib
import importlib.util
import json
import os
import stat
from pathlib import Path

import pytest


HERE = Path(__file__).resolve().parent


def load_module(name: str, filename: str):
    spec = importlib.util.spec_from_file_location(name, HERE / filename)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


review = load_module(
    "narrative_record_cutover_review",
    "build_narrative_record_cutover_review.py",
)
converter = load_module(
    "narrative_record_cutover_converter",
    "convert_narrative_record_cutover_approvals.py",
)


def canonical(value: object) -> bytes:
    return (
        json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
        + "\n"
    ).encode("utf-8")


def sha(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def row_hash(row: dict) -> str:
    unhashed = dict(row)
    unhashed.pop("row_sha256", None)
    return sha(canonical(unhashed))


def artifacts() -> dict[str, bytes]:
    database = {
        "database_name": "daa_task7_synthetic",
        "system_identifier": "7657242220770903427",
    }
    record_rows = [
        {
            "binding_id": "70000000-0000-0000-0000-000000000001",
            "narrative_id": 101,
            "person_id": 11,
            "source_id": 5,
            "source_kind": "DAA-udgave",
            "source_record_id": "70000000-0000-0000-0000-000000000011",
            "record_key": "side-2",
            "status": "published",
            "record_label": "II.",
            "citation_label": "DAA 1939, s. 2",
            "publication_state_sha256": "1" * 64,
            "narrative_text_sha256": "2" * 64,
            "binding_match_count": 1,
        },
        {
            "binding_id": "70000000-0000-0000-0000-000000000002",
            "narrative_id": 102,
            "person_id": 12,
            "source_id": 5,
            "source_kind": "DAA-udgave",
            "source_record_id": "70000000-0000-0000-0000-000000000012",
            "record_key": "side-10",
            "status": "draft",
            "record_label": "X.",
            "citation_label": "DAA 1939, s. 10",
            "publication_state_sha256": "3" * 64,
            "narrative_text_sha256": "4" * 64,
            "binding_match_count": 1,
        },
    ]
    for row in record_rows:
        row["row_sha256"] = row_hash(row)
    legacy_rows = [
        {
            "legacy_publication_ref": "70000000-0000-0000-0000-000000000101",
            "narrative_id": 201,
            "person_id": 21,
            "source_id": 6,
            "source_kind": "DAA-udgave",
            "narrative_text_sha256": "5" * 64,
            "baseline_sha256": "6" * 64,
            "binding_match_count": 0,
        },
        {
            "legacy_publication_ref": "70000000-0000-0000-0000-000000000102",
            "narrative_id": 202,
            "person_id": 22,
            "source_id": 6,
            "source_kind": "DAA-udgave",
            "narrative_text_sha256": "7" * 64,
            "baseline_sha256": "8" * 64,
            "binding_match_count": 0,
        },
    ]
    for row in legacy_rows:
        row["row_sha256"] = row_hash(row)
    record = {
        "schema_version": "narrative-record-baseline-candidates-v1",
        "database": database,
        "rows": record_rows,
    }
    legacy = {
        "schema_version": "narrative-legacy-baseline-candidates-v1",
        "database": database,
        "rows": legacy_rows,
    }
    inventory = {
        "schema_version": "narrative-record-cutover-inventory-v1",
        "database": database,
        "record_candidate_ids": [row["binding_id"] for row in record_rows],
        "legacy_candidate_ids": [row["narrative_id"] for row in legacy_rows],
        "counts_by_source": [
            {"source_id": 5, "record_candidates": 2, "legacy_candidates": 0},
            {"source_id": 6, "record_candidates": 0, "legacy_candidates": 2},
        ],
        "accepted_identity_count": 2,
        "identity_blocked_record_count": 3,
        "classified_direct_readers": [
            {"path": "mobile/src/data/about.ts", "classification": "non_person_control"},
            {"path": "mobile/src/data/haendelser.ts", "classification": "rls_gated_metadata"},
            {"path": "mobile/src/data/load.ts", "classification": "v2_public_rpc"},
            {"path": "mobile/src/data/presensLinjer.ts", "classification": "non_person_control"},
            {"path": "mobile/src/data/publicBioVersions.ts", "classification": "v2_public_rpc"},
            {"path": "mobile/src/data/redaktionRead.ts", "classification": "v2_editor_rpc"},
            {"path": "web/src/data/feedAux.ts", "classification": "v2_public_rpc"},
            {"path": "web/src/data/haendelser.ts", "classification": "rls_gated_metadata"},
            {"path": "web/src/data/presensLinjer.ts", "classification": "non_person_control"},
            {"path": "web/src/data/public.ts", "classification": "v2_public_rpc"},
            {"path": "web/src/data/redaktionRead.ts", "classification": "v2_editor_rpc"},
        ],
    }
    return {
        "record": canonical(record),
        "legacy": canonical(legacy),
        "inventory": canonical(inventory),
    }


def decisions(values: dict[str, bytes], *, unresolved: bool = False) -> bytes:
    record = review.strict_load_json(values["record"])
    legacy = review.strict_load_json(values["legacy"])
    inventory = review.strict_load_json(values["inventory"])
    document = {
        "schema_version": "narrative-record-cutover-decisions-v1",
        "database": record["database"],
        "input_hashes": {
            "record_candidates_sha256": sha(values["record"]),
            "legacy_candidates_sha256": sha(values["legacy"]),
            "inventory_sha256": sha(values["inventory"]),
        },
        "record_decisions": [
            {
                "binding_id": row["binding_id"],
                "row_sha256": row["row_sha256"],
                "decision": "uafklaret" if unresolved and index == 0 else "godkend baseline",
            }
            for index, row in enumerate(record["rows"])
        ],
        "legacy_decisions": [
            {
                "narrative_id": row["narrative_id"],
                "row_sha256": row["row_sha256"],
                "decision": (
                    "uafklaret"
                    if unresolved and index == 0
                    else "bevar offentligt som grandfathered"
                    if index == 0
                    else "skjul ved cutover"
                ),
            }
            for index, row in enumerate(legacy["rows"])
        ],
    }
    return canonical(document)


def test_strict_json_rejects_duplicate_keys_and_noncanonical_raw() -> None:
    with pytest.raises(review.ContractError, match="DUPLICATE_JSON_KEY"):
        review.strict_load_json(b'{"rows":[],"rows":[]}\n')
    with pytest.raises(review.ContractError, match="NON_CANONICAL_JSON"):
        review.validate_candidate_bundle(
            b'{"schema_version": "narrative-record-baseline-candidates-v1", "rows": []}\n',
            artifacts()["legacy"],
            artifacts()["inventory"],
        )


def test_review_rejects_duplicate_ids_null_hashes_bad_order_and_identity_drift() -> None:
    values = artifacts()
    record = review.strict_load_json(values["record"])
    record["rows"][1]["binding_id"] = record["rows"][0]["binding_id"]
    record["rows"][1]["row_sha256"] = row_hash(record["rows"][1])
    with pytest.raises(review.ContractError, match="DUPLICATE_RECORD_CANDIDATE"):
        review.validate_candidate_bundle(canonical(record), values["legacy"], values["inventory"])

    record = review.strict_load_json(values["record"])
    record["rows"][0]["publication_state_sha256"] = None
    record["rows"][0]["row_sha256"] = row_hash(record["rows"][0])
    with pytest.raises(review.ContractError, match="INVALID_SHA256"):
        review.validate_candidate_bundle(canonical(record), values["legacy"], values["inventory"])

    record = review.strict_load_json(values["record"])
    record["rows"].reverse()
    with pytest.raises(review.ContractError, match="RECORD_CANDIDATE_ORDER"):
        review.validate_candidate_bundle(canonical(record), values["legacy"], values["inventory"])

    inventory = review.strict_load_json(values["inventory"])
    inventory["database"]["database_name"] = "another_database"
    with pytest.raises(review.ContractError, match="DATABASE_IDENTITY_MISMATCH"):
        review.validate_candidate_bundle(values["record"], values["legacy"], canonical(inventory))

    record = review.strict_load_json(values["record"])
    record["rows"][0]["binding_match_count"] = 2
    record["rows"][0]["row_sha256"] = row_hash(record["rows"][0])
    with pytest.raises(review.ContractError, match="AMBIGUOUS_RECORD_BINDING"):
        review.validate_candidate_bundle(canonical(record), values["legacy"], values["inventory"])

    legacy = review.strict_load_json(values["legacy"])
    legacy["rows"][0]["source_kind"] = "arkiv"
    legacy["rows"][0]["row_sha256"] = row_hash(legacy["rows"][0])
    with pytest.raises(review.ContractError, match="NON_DAA_CANDIDATE"):
        review.validate_candidate_bundle(values["record"], canonical(legacy), values["inventory"])


def test_html_is_offline_hash_bound_and_uses_only_safe_dom_apis() -> None:
    values = artifacts()
    html = review.build_review_html(values["record"], values["legacy"], values["inventory"])
    text = html.decode("utf-8")
    assert sha(values["record"]) in text
    assert sha(values["legacy"]) in text
    assert sha(values["inventory"]) in text
    assert "createElement" in text and "textContent" in text
    assert "innerHTML" not in text and "document.write" not in text
    assert "fetch(" not in text and "XMLHttpRequest" not in text
    assert "Godkend alle" not in text
    assert "godkend baseline" in text
    assert "bevar offentligt som grandfathered" in text
    assert "skjul ved cutover" in text
    assert "uafklaret" in text


def test_review_and_converter_preserve_legacy_bigint_beyond_javascript_safe_range() -> None:
    values = artifacts()
    legacy = review.strict_load_json(values["legacy"])
    inventory = review.strict_load_json(values["inventory"])
    exact_ids = [9007199254740993, 9007199254740994]
    for row, narrative_id in zip(legacy["rows"], exact_ids):
        row["narrative_id"] = narrative_id
        row["row_sha256"] = row_hash(row)
    inventory["legacy_candidate_ids"] = exact_ids
    values["legacy"] = canonical(legacy)
    values["inventory"] = canonical(inventory)

    html = review.build_review_html(
        values["record"], values["legacy"], values["inventory"]
    ).decode("utf-8")
    assert "JSON.parse" not in html
    assert '"narrative_id_decimal":"9007199254740993"' in html
    assert "RAW_INTEGER" in html
    assert "return value[RAW_INTEGER]" in html

    converted = converter.convert_artifacts(
        values["record"], values["legacy"], values["inventory"], decisions(values)
    )
    approval = review.strict_load_json(converted[converter.APPROVAL_NAME])
    assert approval["legacy_keep_ids"] == [exact_ids[0]]
    assert approval["legacy_hide_ids"] == [exact_ids[1]]


def test_converter_refuses_unresolved_without_publishing_final_artifacts(tmp_path: Path) -> None:
    values = artifacts()
    with pytest.raises(converter.ContractError, match="UNRESOLVED_DECISION"):
        converter.convert_and_publish(
            values["record"], values["legacy"], values["inventory"],
            decisions(values, unresolved=True), tmp_path,
        )
    assert list(tmp_path.iterdir()) == []


@pytest.mark.parametrize("axis", ["missing", "extra", "duplicate", "unknown", "altered"])
def test_converter_rejects_inexact_record_decisions(axis: str) -> None:
    values = artifacts()
    decision = review.strict_load_json(decisions(values))
    if axis == "missing":
        decision["record_decisions"].pop()
    elif axis == "extra":
        decision["record_decisions"].append({
            "binding_id": "70000000-0000-0000-0000-000000000099",
            "row_sha256": "9" * 64,
            "decision": "godkend baseline",
        })
    elif axis == "duplicate":
        decision["record_decisions"].append(dict(decision["record_decisions"][0]))
    elif axis == "unknown":
        decision["record_decisions"][0]["decision"] = "auto-godkend"
    else:
        decision["record_decisions"][0]["row_sha256"] = "0" * 64
    with pytest.raises(converter.ContractError):
        converter.convert_artifacts(
            values["record"], values["legacy"], values["inventory"], canonical(decision)
        )


def test_converter_emits_exact_full_record_and_disjoint_legacy_partition() -> None:
    values = artifacts()
    result = converter.convert_artifacts(
        values["record"], values["legacy"], values["inventory"], decisions(values)
    )
    record_manifest = review.strict_load_json(result[converter.RECORD_MANIFEST_NAME])
    legacy_manifest = review.strict_load_json(result[converter.LEGACY_MANIFEST_NAME])
    approval = review.strict_load_json(result[converter.APPROVAL_NAME])
    candidates = review.strict_load_json(values["record"])
    legacy_candidates = review.strict_load_json(values["legacy"])

    assert [row["binding_id"] for row in record_manifest["rows"]] == [
        row["binding_id"] for row in candidates["rows"]
    ]
    assert [row["narrative_id"] for row in legacy_manifest["rows"]] == [201]
    assert approval["legacy_keep_ids"] == [201]
    assert approval["legacy_hide_ids"] == [202]
    assert set(approval["legacy_keep_ids"]).isdisjoint(approval["legacy_hide_ids"])
    assert sorted(approval["legacy_keep_ids"] + approval["legacy_hide_ids"]) == [
        row["narrative_id"] for row in legacy_candidates["rows"]
    ]
    hashes = approval["input_hashes"]
    assert hashes == {
        "approval_decisions_sha256": sha(decisions(values)),
        "inventory_sha256": sha(values["inventory"]),
        "legacy_candidates_sha256": sha(values["legacy"]),
        "legacy_manifest_sha256": sha(result[converter.LEGACY_MANIFEST_NAME]),
        "record_candidates_sha256": sha(values["record"]),
        "record_manifest_sha256": sha(result[converter.RECORD_MANIFEST_NAME]),
    }


def test_changed_candidate_bytes_invalidate_decisions_even_if_json_values_match() -> None:
    values = artifacts()
    changed = values["record"][:-1] + b" \n"
    with pytest.raises(converter.ContractError, match="NON_CANONICAL_JSON|INPUT_HASH_MISMATCH"):
        converter.convert_artifacts(
            changed, values["legacy"], values["inventory"], decisions(values)
        )


@pytest.mark.parametrize(
    "axis", ["counts", "negative_identity", "reader_shape", "reader_missing", "reader_reordered"]
)
def test_inventory_metrics_are_exact_and_reconciled_to_candidates(axis: str) -> None:
    values = artifacts()
    inventory = review.strict_load_json(values["inventory"])
    if axis == "counts":
        inventory["counts_by_source"][0]["record_candidates"] = 1
    elif axis == "negative_identity":
        inventory["identity_blocked_record_count"] = -1
    elif axis == "reader_shape":
        inventory["classified_direct_readers"][0]["unexpected"] = True
    elif axis == "reader_reordered":
        inventory["classified_direct_readers"][0], inventory["classified_direct_readers"][1] = (
            inventory["classified_direct_readers"][1], inventory["classified_direct_readers"][0]
        )
    else:
        inventory["classified_direct_readers"].pop()
    with pytest.raises(review.ContractError, match="INVENTORY_"):
        review.validate_candidate_bundle(
            values["record"], values["legacy"], canonical(inventory)
        )


def test_output_policy_rejects_repo_work_symlink_and_nonprivate_directory(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    # En kunstig repo-rod: CI's checkout ligger under /home/runner/work/…, så den rigtige
    # rod rammer OUTPUT_WORK_PATH, før repo-vagten nås.
    repo_root = tmp_path / "repo"
    repo_root.mkdir(mode=0o700)
    monkeypatch.setattr(review, "REPO_ROOT", repo_root)
    with pytest.raises(review.PublicationError, match="OUTPUT_INSIDE_REPOSITORY"):
        review.open_output_directory(repo_root)
    with pytest.raises(review.PublicationError, match="OUTPUT_WORK_PATH"):
        review.open_output_directory(tmp_path / "work" / "review")
    real = tmp_path / "real"
    real.mkdir(mode=0o700)
    link = tmp_path / "link"
    link.symlink_to(real, target_is_directory=True)
    with pytest.raises(review.PublicationError, match="OUTPUT_SYMLINK"):
        review.open_output_directory(link)
    loose = tmp_path / "loose"
    loose.mkdir(mode=0o755)
    with pytest.raises(review.PublicationError, match="OUTPUT_DIRECTORY_MODE"):
        review.open_output_directory(loose)
    sensitive = tmp_path / "work" / "approved"
    output = sensitive / "output"
    output.mkdir(parents=True, mode=0o700)
    alias = tmp_path / "ancestor-alias"
    alias.symlink_to(sensitive, target_is_directory=True)
    with pytest.raises(review.PublicationError, match="OUTPUT_WORK_PATH"):
        review.open_output_directory(alias / "output")


def test_fd_safe_bundle_publication_is_0600_no_overwrite_and_recoverable(tmp_path: Path) -> None:
    os.chmod(tmp_path, 0o700)
    bundle = {"a.json": b"a\n", "b.json": b"b\n"}
    outcome = review.publish_bundle(tmp_path, bundle)
    assert outcome == "published"
    for name, raw in bundle.items():
        path = tmp_path / name
        assert path.read_bytes() == raw
        assert stat.S_IMODE(path.stat().st_mode) == 0o600
    with pytest.raises(review.PublicationError, match="OUTPUT_TARGET_EXISTS"):
        review.publish_bundle(tmp_path, bundle)

    recover = tmp_path / "recover"
    recover.mkdir(mode=0o700)
    (recover / "a.json").write_bytes(bundle["a.json"])
    os.chmod(recover / "a.json", 0o600)
    assert review.recover_bundle(recover, bundle) == "recovered"
    assert (recover / "b.json").read_bytes() == bundle["b.json"]


def test_output_directory_swap_between_validation_and_open_fails_closed(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    output = tmp_path / "output"
    output.mkdir(mode=0o700)
    original = review._validate_output_path

    def swap_after_validation(path: Path):
        validated = original(path)
        output.rename(tmp_path / "original-output")
        output.mkdir(mode=0o700)
        return validated

    monkeypatch.setattr(review, "_validate_output_path", swap_after_validation)
    with pytest.raises(review.PublicationError, match="OUTPUT_DIRECTORY_RACE"):
        review.open_output_directory(output)


def test_recovery_fails_closed_on_foreign_or_ambiguous_target(tmp_path: Path) -> None:
    os.chmod(tmp_path, 0o700)
    bundle = {"a.json": b"approved\n", "b.json": b"approved-b\n"}
    (tmp_path / "a.json").write_bytes(b"foreign\n")
    os.chmod(tmp_path / "a.json", 0o600)
    with pytest.raises(review.PublicationError, match="ARTIFACT_RECOVERY_REQUIRED"):
        review.recover_bundle(tmp_path, bundle)
    assert not (tmp_path / "b.json").exists()


def test_staging_fsync_failure_cleans_exact_temp_before_reporting_failure(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    os.chmod(tmp_path, 0o700)
    real_fsync = os.fsync

    def fail_regular_file_fsync(descriptor: int) -> None:
        if stat.S_ISREG(os.fstat(descriptor).st_mode):
            raise OSError("injected file fsync failure")
        real_fsync(descriptor)

    monkeypatch.setattr(review.os, "fsync", fail_regular_file_fsync)
    with pytest.raises(review.PublicationError, match="OUTPUT_PUBLICATION_FAILED"):
        review.publish_bundle(tmp_path, {"a.json": b"approved\n"})
    assert list(tmp_path.iterdir()) == []


def test_first_temp_fstat_failure_is_tracked_closed_and_requires_recovery(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    os.chmod(tmp_path, 0o700)
    real_open = os.open
    real_fstat = os.fstat
    temp_handles: list[int] = []
    failed = False

    def track_temp_open(path, *args, **kwargs):
        handle = real_open(path, *args, **kwargs)
        if str(path).startswith(".nrk."):
            temp_handles.append(handle)
        return handle

    def fail_first_temp_fstat(descriptor: int):
        nonlocal failed
        if descriptor in temp_handles and not failed:
            failed = True
            raise OSError("injected first temp fstat failure")
        return real_fstat(descriptor)

    monkeypatch.setattr(review.os, "open", track_temp_open)
    monkeypatch.setattr(review.os, "fstat", fail_first_temp_fstat)
    with pytest.raises(review.PublicationError, match="ARTIFACT_RECOVERY_REQUIRED"):
        review.publish_bundle(tmp_path, {"a.json": b"approved\n"})
    assert len(temp_handles) == 1
    with pytest.raises(OSError):
        real_fstat(temp_handles[0])
    assert any(path.name.startswith(".nrk.") for path in tmp_path.iterdir())
    assert not (tmp_path / "a.json").exists()


def test_recovery_rejects_untracked_publisher_temp_inventory(tmp_path: Path) -> None:
    os.chmod(tmp_path, 0o700)
    orphan = tmp_path / ".nrk.orphan.0.tmp"
    orphan.write_bytes(b"unknown staged bytes\n")
    os.chmod(orphan, 0o600)
    with pytest.raises(review.PublicationError, match="ARTIFACT_RECOVERY_REQUIRED"):
        review.recover_bundle(tmp_path, {"a.json": b"approved\n"})
    assert not (tmp_path / "a.json").exists()
    assert orphan.exists()


def test_unprovable_temp_cleanup_requires_explicit_recovery(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    os.chmod(tmp_path, 0o700)
    real_fsync = os.fsync
    real_unlink = os.unlink

    def fail_regular_file_fsync(descriptor: int) -> None:
        if stat.S_ISREG(os.fstat(descriptor).st_mode):
            raise OSError("injected file fsync failure")
        real_fsync(descriptor)

    def fail_temp_unlink(path, *args, **kwargs):
        if str(path).startswith(".nrk."):
            raise OSError("injected temp cleanup failure")
        return real_unlink(path, *args, **kwargs)

    monkeypatch.setattr(review.os, "fsync", fail_regular_file_fsync)
    monkeypatch.setattr(review.os, "unlink", fail_temp_unlink)
    with pytest.raises(review.PublicationError, match="ARTIFACT_RECOVERY_REQUIRED"):
        review.publish_bundle(tmp_path, {"a.json": b"approved\n"})
    assert any(path.name.startswith(".nrk.") for path in tmp_path.iterdir())
    assert not (tmp_path / "a.json").exists()


def test_legacy_publication_refs_are_candidate_identity_not_reused() -> None:
    first = review.new_legacy_publication_ref()
    second = review.new_legacy_publication_ref()
    assert first != second
    assert review.require_uuid(first, "ref") == first
    assert review.require_uuid(second, "ref") == second
