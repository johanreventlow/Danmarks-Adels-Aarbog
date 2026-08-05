import copy

import pytest

from coverage_1939 import validate_coverage


def source(**overrides):
    value = {
        "edition": "1939",
        "calamari_sha256": "a" * 64,
        "raw_ocr_sha256": "b" * 64,
        "pdf_sha256": "c" * 64,
    }
    value.update(overrides)
    return value


def accepted(key, candidate_id="candidate-1", **overrides):
    value = {
        "baseline_record_key": key,
        "status": "accepteret",
        "candidate": {
            "candidate_id": candidate_id,
            "postklasse": "nummereret",
            "calamari_span": {"char_from": 0, "char_to": 10},
            "pdf_pages": [496],
            "raw_structure_bridge": {
                "kind": "line_header",
                "raw_char_from": 20,
                "raw_char_to": 30,
                "raw_excerpt_sha256": "d" * 64,
            },
        },
    }
    value.update(overrides)
    return value


def duplicate(key, target):
    return {
        "baseline_record_key": key,
        "status": "eksplicit_dublet",
        "duplicate_of_baseline_record_key": target,
    }


def parked(key, reason="manglende-pdf-side"):
    return {
        "baseline_record_key": key,
        "status": "menneskeark",
        "reason": reason,
    }


def bundle(*entries, **overrides):
    value = {"schema_version": 1, "source": source(), "entries": list(entries)}
    value.update(overrides)
    return value


def test_accepts_complete_injective_coverage_without_mutating_input():
    value = bundle(
        accepted("rk-1"),
        duplicate("rk-2", "rk-1"),
        parked("rk-3"),
    )
    original = copy.deepcopy(value)

    result = validate_coverage(
        value,
        expected_baseline_keys={"rk-1", "rk-2", "rk-3"},
    )

    assert result["rk-1"]["status"] == "accepteret"
    assert result["rk-2"]["status"] == "eksplicit_dublet"
    assert value == original


@pytest.mark.parametrize("invalid_version", [True, 1.0, "1", None])
def test_schema_version_requires_exact_integer_one(invalid_version):
    value = bundle(parked("rk-1"))
    if invalid_version is None:
        value.pop("schema_version")
    else:
        value["schema_version"] = invalid_version

    with pytest.raises(ValueError, match="schema_version"):
        validate_coverage(value, expected_baseline_keys={"rk-1"})


def test_rejects_duplicate_candidate_id():
    with pytest.raises(ValueError, match="ikke-injektiv kandidat"):
        validate_coverage(
            bundle(accepted("rk-1"), accepted("rk-2", "candidate-1")),
            expected_baseline_keys={"rk-1", "rk-2"},
        )


def test_rejects_candidate_without_raw_excerpt_hash():
    candidate = accepted("rk-1")["candidate"]
    del candidate["raw_structure_bridge"]["raw_excerpt_sha256"]

    with pytest.raises(ValueError, match="raw_excerpt_sha256"):
        validate_coverage(
            bundle(accepted("rk-1", candidate=candidate)),
            expected_baseline_keys={"rk-1"},
        )


@pytest.mark.parametrize(
    ("target", "message"),
    [
        ("ukendt", "ukendt dubletmål"),
        ("rk-4", "må ikke pege på sig selv"),
        ("rk-2", "skal være accepteret"),
        ("rk-3", "skal være accepteret"),
    ],
)
def test_rejects_duplicate_without_accepted_distinct_baseline_target(target, message):
    with pytest.raises(ValueError, match=message):
        validate_coverage(
            bundle(
                accepted("rk-1"),
                duplicate("rk-2", "rk-1"),
                parked("rk-3"),
                duplicate("rk-4", target),
            ),
            expected_baseline_keys={"rk-1", "rk-2", "rk-3", "rk-4"},
        )


def test_accepts_multiple_duplicates_with_one_accepted_target():
    result = validate_coverage(
        bundle(
            accepted("rk-1"),
            duplicate("rk-2", "rk-1"),
            duplicate("rk-3", "rk-1"),
        ),
        expected_baseline_keys={"rk-1", "rk-2", "rk-3"},
    )

    assert result["rk-3"]["duplicate_of_baseline_record_key"] == "rk-1"


@pytest.mark.parametrize(
    ("value", "expected_keys", "message"),
    [
        (bundle(accepted("rk-1")), {"rk-1", "rk-2"}, "baseline-dækning fejler"),
        (bundle(accepted("rk-1")), set(), "baseline-dækning fejler"),
        (bundle(accepted("rk-1"), accepted("rk-1", "candidate-2")), {"rk-1"}, "dublet baseline"),
        (bundle({"baseline_record_key": "rk-1", "status": "ukendt"}), {"rk-1"}, "ukendt status"),
        (bundle(accepted("rk-1"), source=source(calamari_sha256="upper" * 13)), {"rk-1"}, "SHA-256"),
        (bundle(accepted("rk-1", candidate_id="")), {"rk-1"}, "candidate_id"),
        (bundle(accepted("rk-1", candidate_id="candidate-1", candidate={
            **accepted("rk-1")["candidate"],
            "calamari_span": {"char_from": 10, "char_to": 10},
        })), {"rk-1"}, "Calamari-span"),
        (bundle(accepted("rk-1", candidate_id="candidate-1", candidate={
            **accepted("rk-1")["candidate"],
            "pdf_pages": [],
        })), {"rk-1"}, "PDF-side"),
        (bundle(accepted("rk-1", candidate_id="candidate-1", candidate={
            **accepted("rk-1")["candidate"],
            "raw_structure_bridge": {"kind": "line_header", "raw_char_from": 2, "raw_char_to": 2},
        })), {"rk-1"}, "rå-bro"),
        (bundle(parked("rk-1", reason="")), {"rk-1"}, "reason"),
        (bundle({**duplicate("rk-1", "rk-2"), "candidate": accepted("rk-1")["candidate"]}), {"rk-1"}, "må ikke have candidate"),
    ],
)
def test_rejects_invalid_coverage(value, expected_keys, message):
    with pytest.raises(ValueError, match=message):
        validate_coverage(value, expected_baseline_keys=expected_keys)
