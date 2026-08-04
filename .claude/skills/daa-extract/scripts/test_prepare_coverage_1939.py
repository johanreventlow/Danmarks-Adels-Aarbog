import pytest

from prepare_coverage_1939 import assemble_coverage, build_candidates


def post(**overrides):
    value = {
        "lokal_id": "Stamme.1",
        "postklasse": None,
        "sider": "496",
        "raw_text": "Alfa",
    }
    value.update(overrides)
    return value


def bridge(**overrides):
    value = {
        "candidate_id": "candidate-1",
        "post_index": 0,
        "calamari_span": {"char_from": 0, "char_to": 8},
        "calamari_verbatim_text": "1. Alfa\n",
        "pdf_pages": [496],
        "kind": "line_header",
        "raw_char_from": 100,
        "raw_char_to": 112,
    }
    value.update(overrides)
    return value


def test_build_candidates_preserves_explicit_exact_calamari_slice():
    result = build_candidates("1. Alfa\n2. Beta\n", [post()], [bridge()])

    assert result == [{
        "candidate_id": "candidate-1",
        "postklasse": "nummereret",
        "calamari_span": {"char_from": 0, "char_to": 8},
        "pdf_pages": [496],
        "raw_structure_bridge": {
            "kind": "line_header",
            "raw_char_from": 100,
            "raw_char_to": 112,
        },
    }]


@pytest.mark.parametrize(
    ("bridges", "posts", "message"),
    [
        ([bridge(calamari_verbatim_text="forkert")], [post()], "ikke eksakt Calamari-span"),
        ([bridge(post_index=1)], [post()], "ukendt post_index"),
        ([bridge(), bridge(candidate_id="candidate-2")], [post()], "post_index forekommer flere gange"),
        ([bridge(), bridge(post_index=1, candidate_id="candidate-2",
                           calamari_span={"char_from": 4, "char_to": 16},
                           calamari_verbatim_text="lfa\n2. Beta\n")],
         [post(), post(lokal_id="Stamme.2", raw_text="Beta")], "overlapper"),
        ([bridge(pdf_pages=[497])], [post()], "PDF-sider stemmer ikke"),
        ([bridge(raw_char_from=12, raw_char_to=12)], [post()], "rå-bro"),
    ],
)
def test_build_candidates_rejects_unanchored_or_ambiguous_bridge(bridges, posts, message):
    with pytest.raises(ValueError, match=message):
        build_candidates("1. Alfa\n2. Beta\n", posts, bridges)


def test_assemble_coverage_resolves_only_known_candidate_ids():
    candidates = build_candidates("1. Alfa\n2. Beta\n", [post()], [bridge()])

    result = assemble_coverage(
        source(),
        {"rk-1", "rk-2"},
        [
            {"baseline_record_key": "rk-1", "status": "accepteret", "candidate_id": "candidate-1"},
            {"baseline_record_key": "rk-2", "status": "menneskeark", "reason": "ingen-entydig-bro"},
        ],
        candidates,
    )

    assert result["entries"][0]["candidate"] == candidates[0]
    assert result["entries"][1]["status"] == "menneskeark"


def test_assemble_coverage_rejects_unknown_candidate_id():
    with pytest.raises(ValueError, match="ukendt candidate_id"):
        assemble_coverage(
            source(),
            {"rk-1"},
            [{"baseline_record_key": "rk-1", "status": "accepteret", "candidate_id": "ukendt"}],
            [],
        )


def source():
    return {
        "edition": "1939",
        "calamari_sha256": "a" * 64,
        "raw_ocr_sha256": "b" * 64,
        "pdf_sha256": "c" * 64,
    }
