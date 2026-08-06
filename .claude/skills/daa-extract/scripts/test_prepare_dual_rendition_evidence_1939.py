import hashlib
import json

import pytest

import prepare_dual_rendition_evidence_1939 as subject


def cli_fixture(tmp_path, *, suffix):
    tmp_path.mkdir(parents=True, exist_ok=True)
    baseline = tmp_path / "baseline.json"
    calamari = tmp_path / "calamari.txt"
    raw = tmp_path / "raw.txt"
    pdf = tmp_path / "source.pdf"
    baseline.write_bytes(json.dumps([{
        "record_key": "rk-1",
        "_v2_lokal_id": "I.1",
        "_narrativ_kilde": "calamari",
        "narrative": "Alfa prosa",
    }], ensure_ascii=False).encode("utf-8"))
    calamari.write_bytes(b"### PAGE 1 ###\n1. Alfa prosa\n")
    raw.write_bytes(b"### PAGE 496 ###\n1. A1fa prosa\n")
    pdf.write_bytes(b"%PDF-synthetic")
    outputs = {
        "calamari_occurrences": tmp_path / ("calamari-occurrences-" + suffix + ".json"),
        "raw_occurrences": tmp_path / ("raw-occurrences-" + suffix + ".json"),
        "evidence": tmp_path / ("evidence-" + suffix + ".json"),
        "report": tmp_path / ("report-" + suffix + ".json"),
    }
    args = [
        "--baseline", str(baseline), "--calamari", str(calamari),
        "--raw", str(raw), "--pdf", str(pdf),
        "--profile-version", "1939-v2",
        "--calamari-occurrences-out", str(outputs["calamari_occurrences"]),
        "--raw-occurrences-out", str(outputs["raw_occurrences"]),
        "--evidence-out", str(outputs["evidence"]),
        "--report-out", str(outputs["report"]),
    ]
    return args, outputs


def test_cli_writes_four_exclusive_source_bound_outputs(tmp_path):
    args, outputs = cli_fixture(tmp_path, suffix="a")

    assert subject.main(args) == 0

    assert all(path.exists() for path in outputs.values())
    evidence = json.loads(outputs["evidence"].read_text(encoding="utf-8"))
    report = json.loads(outputs["report"].read_text(encoding="utf-8"))
    assert evidence["source"]["profile_version"] == "1939-v2"
    assert report["source"] == evidence["source"]
    assert report["baseline_total"] == 1
    assert report["exact_anchor_counts"]["calamari"]["unique_exact_anchor"] == 1
    assert report["occurrence_counts"] == {"calamari": 1, "raw_ocr": 1}
    assert report["alignment_counts"]["invariant_pairs"] == 1
    assert set(report["artifact_sha256"]) == {
        "calamari_occurrences", "raw_occurrences", "evidence",
    }
    assert report["artifact_sha256"]["evidence"] == hashlib.sha256(
        outputs["evidence"].read_bytes()
    ).hexdigest()


def test_cli_refuses_existing_output_before_reading_sources(tmp_path):
    args, outputs = cli_fixture(tmp_path, suffix="existing")
    outputs["raw_occurrences"].write_text("preserve", encoding="utf-8")
    for option in ("--baseline", "--calamari", "--raw", "--pdf"):
        args[args.index(option) + 1] = str(tmp_path / (option + "-missing"))

    with pytest.raises(FileExistsError):
        subject.main(args)

    assert outputs["raw_occurrences"].read_text(encoding="utf-8") == "preserve"
    assert not outputs["evidence"].exists()


def test_cli_rejects_duplicate_output_paths_before_reading_sources(tmp_path):
    args, outputs = cli_fixture(tmp_path, suffix="duplicate")
    args[args.index("--evidence-out") + 1] = str(outputs["calamari_occurrences"])
    for option in ("--baseline", "--calamari", "--raw", "--pdf"):
        args[args.index(option) + 1] = str(tmp_path / (option + "-missing"))

    with pytest.raises(ValueError, match="distinct"):
        subject.main(args)

    assert not any(path.exists() for path in outputs.values())


def test_two_clean_runs_are_byte_identical(tmp_path):
    args_a, outputs_a = cli_fixture(tmp_path / "a", suffix="a")
    args_b, outputs_b = cli_fixture(tmp_path / "b", suffix="b")

    assert subject.main(args_a) == subject.main(args_b) == 0

    for name in outputs_a:
        assert outputs_a[name].read_bytes() == outputs_b[name].read_bytes()


def test_write_failure_removes_only_outputs_created_by_this_invocation(tmp_path, monkeypatch):
    args, outputs = cli_fixture(tmp_path, suffix="cleanup")
    sentinel = tmp_path / "unrelated-sentinel.txt"
    sentinel.write_text("preserve", encoding="utf-8")
    original = subject._write_exclusive
    calls = 0

    def fail_third_write(path, payload):
        nonlocal calls
        calls += 1
        if calls == 3:
            raise OSError("synthetic output failure")
        return original(path, payload)

    monkeypatch.setattr(subject, "_write_exclusive", fail_third_write)

    with pytest.raises(OSError, match="synthetic output failure"):
        subject.main(args)

    assert calls == 3
    assert not any(path.exists() for path in outputs.values())
    assert sentinel.read_text(encoding="utf-8") == "preserve"


def test_exclusive_writer_preserves_file_it_did_not_create(tmp_path):
    sentinel = tmp_path / "existing-output.json"
    sentinel.write_text("preserve", encoding="utf-8")

    with pytest.raises(FileExistsError):
        subject._write_exclusive(sentinel, b"replacement")

    assert sentinel.read_text(encoding="utf-8") == "preserve"
