"""Tests for deterministic re-anchoring of exported 1939 human review choices."""

import copy
import hashlib
import json
from unittest import mock

import pytest

import anchor_review_choices_1939 as subject
import prepare_review_queue_1939 as publication_subject
from anchor_review_choices_1939 import build_human_anchored_candidates
from coverage_1939 import validate_coverage
from rendition_occurrences_1939 import (
    CALAMARI_R6_TO_PDF_V1,
    extract_rendition_occurrences,
)
from review_choices_1939 import convert_review_choices, validate_choice_export


PROFILE = "1939-v2"

CAL_LINES = [
    "### PAGE 0001 ###",
    "1. Anders Testesen, f. 1900, d. 1960 paa Testgaard.",
    "2. Bertel Testesen, f. 1902, d. 1970 i Testby.",
    "Cecilie Testdatter, f. 1904, d. 1980 i Testkoebing.",
    "Daniel Testesen uden kildeforekomst-daekning.",
    "Erik Testesen ligeledes uden daekning.",
    "   ",
]
CALAMARI_TEXT = "\n".join(CAL_LINES)
RAW_LINES = [
    "### PAGE 496 ###",
    "1. Anders Testesen, f. 1900, d. 1960 paa Testgaard (raa).",
    "3. Bertel Testesen raa-divergerende.",
    "Cecilie Testdatter raa.",
]
RAW_TEXT = "\n".join(RAW_LINES)


def sha(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def cal_line_span(index):
    start = sum(len(line) + 1 for line in CAL_LINES[:index])
    return start, start + len(CAL_LINES[index])


def raw_line_span(index):
    start = sum(len(line) + 1 for line in RAW_LINES[:index])
    return start, start + len(RAW_LINES[index])


SPAN_A = cal_line_span(1)
SPAN_B = cal_line_span(2)
SPAN_C = cal_line_span(3)

POSTS = [
    {"lokal_id": "P1", "postklasse": "nummereret", "sider": "1",
     "linjer": {"fra": 1, "til": 2}},
    {"lokal_id": "P2", "postklasse": "nummereret", "sider": "1",
     "linjer": {"fra": 2, "til": 3}},
    {"lokal_id": "P4", "postklasse": "stamfader", "sider": "1",
     "linjer": {"fra": 4, "til": 5}},
    {"lokal_id": "P5", "postklasse": "nummereret", "sider": "1",
     "linjer": {"fra": 5, "til": 6}},
    {"lokal_id": "P6", "postklasse": "nummereret", "sider": "1",
     "linjer": {"fra": 6, "til": 7}},
]


CAL_OCCURRENCES = extract_rendition_occurrences(
    CALAMARI_TEXT, rendition="calamari", page_map=CALAMARI_R6_TO_PDF_V1,
)
RAW_OCCURRENCES = extract_rendition_occurrences(
    RAW_TEXT, rendition="raw_ocr", page_map=None,
)

RECORD_KEYS = ("rec-a", "rec-b", "rec-c", "rec-d", "rec-e", "rec-f", "rec-x")
BASELINE_RECORDS = {
    "rec-a": {"record_key": "rec-a", "narrative": "Anders' narrativ.", "sider": "496"},
    "rec-b": {"record_key": "rec-b", "narrative": "Bertels narrativ.", "sider": "496"},
    "rec-c": {"record_key": "rec-c", "narrative": CAL_LINES[3], "sider": "496"},
    "rec-d": {"record_key": "rec-d", "narrative": "Daniels narrativ.", "sider": "3-4"},
    "rec-e": {"record_key": "rec-e", "narrative": "Eriks narrativ.", "sider": ""},
    "rec-f": {"record_key": "rec-f", "narrative": "F-narrativ.", "sider": "496"},
    "rec-x": {"record_key": "rec-x", "narrative": "X-narrativ.", "sider": "496"},
}


def human_required(key):
    return {
        "baseline_record_key": key,
        "queue_class": "human_required",
        "reason_code": "no_candidate",
        "reason_da": "Ingen kandidat med komplet kildebro.",
    }


CLASSIFICATIONS = {key: human_required(key) for key in RECORD_KEYS}

AUTO_RAW_SPAN = (0, 5)
AUTO_CANDIDATE = {
    "candidate_id": "1939:dual-v1:" + "f" * 64,
    "postklasse": "nummereret",
    "calamari_span": {"char_from": SPAN_A[0], "char_to": SPAN_A[0] + 5},
    "pdf_pages": [496],
    "raw_structure_bridge": {
        "kind": "dual_rendition_consensus_v1",
        "raw_char_from": AUTO_RAW_SPAN[0],
        "raw_char_to": AUTO_RAW_SPAN[1],
        "raw_excerpt_sha256": sha(RAW_TEXT[AUTO_RAW_SPAN[0]:AUTO_RAW_SPAN[1]]),
    },
}


def classifications_with_auto():
    result = copy.deepcopy(CLASSIFICATIONS)
    result["rec-auto"] = {
        "baseline_record_key": "rec-auto",
        "queue_class": "auto_resolved",
        "reason_code": "complete_unique_anchored_candidate",
        "reason_da": "Én komplet, entydig og konfliktfri kildebro.",
        "rule_id": "dual_rendition_consensus_v1",
        "postklasse": "nummereret",
        "candidate": copy.deepcopy(AUTO_CANDIDATE),
    }
    return result


def choice(key, candidate_id):
    return {
        "baseline_record_key": key,
        "outcome": "human_selected_candidate",
        "candidate_id": candidate_id,
    }


def text_anchor_id(key, narrative):
    start = CALAMARI_TEXT.find(narrative)
    end = start + len(narrative)
    digest = hashlib.sha256(
        f"{PROFILE}\0{key}\0{start}\0{end}".encode("utf-8")
    ).hexdigest()
    return f"presentation:{PROFILE}:text-anchor:{digest}"


def expected_human_id(span):
    excerpt_sha = sha(CALAMARI_TEXT[span[0]:span[1]])
    digest = hashlib.sha256(
        f"{PROFILE}\0{span[0]}\0{span[1]}\0{excerpt_sha}".encode("utf-8")
    ).hexdigest()
    return f"human:{PROFILE}:span:{digest}"


def baseline_bytes_for(records):
    return json.dumps([records[key] for key in sorted(records)]).encode("utf-8")


def source_for(baseline_bytes, calamari_text, raw_text):
    return {
        "edition": "1939",
        "baseline_sha256": hashlib.sha256(baseline_bytes).hexdigest(),
        "calamari_sha256": sha(calamari_text),
        "raw_ocr_sha256": sha(raw_text),
        "pdf_sha256": "c" * 64,
        "profile_version": PROFILE,
    }


def base_evidence_for(source, keys=RECORD_KEYS):
    return {
        "schema_version": 1,
        "source": copy.deepcopy(source),
        "entries": [{
            "baseline_record_key": key,
            "candidates": [],
            "positive_provenance": None,
            "conflicts": ["manual_review_required"],
            "source_blockers": [],
            "rule_id": None,
        } for key in keys],
    }


def build(choices, *, audit_keys=frozenset(), classifications=None, posts=None,
          baseline_records=None, calamari_text=CALAMARI_TEXT, raw_text=RAW_TEXT,
          cal_occurrences=None, raw_occurrences=None, source_overrides=None,
          first_pdf_page=11):
    records = baseline_records or copy.deepcopy(BASELINE_RECORDS)
    baseline_bytes = baseline_bytes_for(records)
    expected_source = {
        **source_for(baseline_bytes, calamari_text, raw_text),
        **(source_overrides or {}),
    }
    posts_value = posts or copy.deepcopy(POSTS)
    with mock.patch.object(
        subject.segment, "_segment_1939_v2",
        lambda lines, profile: copy.deepcopy(posts_value),
    ):
        return build_human_anchored_candidates(
            choices,
            set(audit_keys),
            classifications or copy.deepcopy(CLASSIFICATIONS),
            baseline_bytes,
            calamari_text,
            raw_text,
            cal_occurrences or copy.deepcopy(CAL_OCCURRENCES),
            raw_occurrences or copy.deepcopy(RAW_OCCURRENCES),
            PROFILE,
            expected_source,
            first_pdf_page,
        )


def test_parserpost_valg_faar_span_og_approval():
    result = build({"rec-a": choice("rec-a", "P1")})
    assert result["parked"] == []
    [(candidate_id, wrapper)] = result["anchored"].items()
    assert candidate_id == expected_human_id(SPAN_A)
    assert wrapper["baseline_record_key"] == "rec-a"
    candidate = wrapper["candidate"]
    assert candidate["candidate_id"] == candidate_id
    assert candidate["calamari_span"] == {"char_from": SPAN_A[0], "char_to": SPAN_A[1]}
    assert candidate["postklasse"] == "nummereret"
    assert candidate["pdf_pages"] == [496]
    assert candidate["approval"] == {
        "kind": "human_approved_span_v1",
        "calamari_excerpt_sha256": sha(CALAMARI_TEXT[SPAN_A[0]:SPAN_A[1]]),
    }
    [entry] = result["evidence_entries"]
    assert entry["baseline_record_key"] == "rec-a"
    assert entry["candidates"] == [candidate]
    assert entry["conflicts"] == []
    assert entry["source_blockers"] == []
    assert entry["rule_id"] == "human_anchor_v1"
    assert entry["positive_provenance"] == {
        "kind": "human_approved_span_v1",
        "baseline_record_key": "rec-a",
        "candidate_id": candidate_id,
    }
    assert result["rewritten_choices"] == {
        "rec-a": {
            "baseline_record_key": "rec-a",
            "outcome": "human_selected_candidate",
            "candidate_id": candidate_id,
        },
    }


def test_text_anchor_valg_genberegnes_og_forankres():
    result = build({"rec-c": choice("rec-c", text_anchor_id("rec-c", CAL_LINES[3]))})
    assert result["parked"] == []
    [(candidate_id, wrapper)] = result["anchored"].items()
    assert candidate_id == expected_human_id(SPAN_C)
    assert wrapper["baseline_record_key"] == "rec-c"
    candidate = wrapper["candidate"]
    assert candidate["calamari_span"] == {"char_from": SPAN_C[0], "char_to": SPAN_C[1]}
    assert candidate["pdf_pages"] == [496]
    assert candidate["postklasse"] == "nummereret"
    assert candidate["approval"]["calamari_excerpt_sha256"] == sha(CAL_LINES[3])


def test_valg_med_alignet_occurrence_faar_raa_bro():
    result = build({"rec-a": choice("rec-a", "P1")})
    [wrapper] = result["anchored"].values()
    raw_span_value = RAW_OCCURRENCES["occurrences"][0]["span"]
    raw_span = (raw_span_value["char_from"], raw_span_value["char_to"])
    assert wrapper["candidate"]["raw_structure_bridge"] == {
        "kind": "human_approved_occurrence_pair_v1",
        "raw_char_from": raw_span[0],
        "raw_char_to": raw_span[1],
        "raw_excerpt_sha256": sha(RAW_TEXT[raw_span[0]:raw_span[1]]),
    }
    assert wrapper["candidate"]["approval"]["kind"] == "human_approved_span_v1"


def test_valg_uden_alignment_faar_kun_approval():
    result = build({"rec-b": choice("rec-b", "P2")})
    assert result["parked"] == []
    [wrapper] = result["anchored"].values()
    candidate = wrapper["candidate"]
    assert "raw_structure_bridge" not in candidate
    assert candidate["approval"] == {
        "kind": "human_approved_span_v1",
        "calamari_excerpt_sha256": sha(CALAMARI_TEXT[SPAN_B[0]:SPAN_B[1]]),
    }


def test_overlap_med_automatisk_kandidat_parkeres():
    result = build(
        {"rec-a": choice("rec-a", "P1")},
        classifications=classifications_with_auto(),
    )
    assert result["anchored"] == {}
    assert result["evidence_entries"] == []
    [parked] = result["parked"]
    assert set(parked) == {
        "baseline_record_key", "reason_code", "reason_da", "candidate_id",
    }
    assert parked["baseline_record_key"] == "rec-a"
    assert parked["reason_code"] == "overlaps_automatic_candidate"
    assert parked["candidate_id"] == "P1"
    assert isinstance(parked["reason_da"], str) and parked["reason_da"]
    assert result["rewritten_choices"]["rec-a"]["candidate_id"] == "P1"


def test_samme_kandidat_to_poster_parkerer_begge():
    result = build({
        "rec-a": choice("rec-a", "P1"),
        "rec-x": choice("rec-x", f"presentation:{PROFILE}:post:0"),
    })
    assert result["anchored"] == {}
    assert result["evidence_entries"] == []
    assert {(p["baseline_record_key"], p["reason_code"]) for p in result["parked"]} == {
        ("rec-a", "candidate_claimed_by_multiple_records"),
        ("rec-x", "candidate_claimed_by_multiple_records"),
    }


def test_wrapper_kandidater_bestaar_validate_coverage():
    result = build({
        "rec-a": choice("rec-a", "P1"),
        "rec-b": choice("rec-b", "P2"),
        "rec-c": choice("rec-c", text_anchor_id("rec-c", CAL_LINES[3])),
    })
    assert result["parked"] == []
    entries = [
        {
            "baseline_record_key": wrapper["baseline_record_key"],
            "status": "accepteret",
            "candidate": wrapper["candidate"],
        }
        for wrapper in result["anchored"].values()
    ]
    validate_coverage(
        {
            "schema_version": 1,
            "source": {
                "edition": "1939",
                "calamari_sha256": "a" * 64,
                "raw_ocr_sha256": "b" * 64,
                "pdf_sha256": "c" * 64,
            },
            "entries": entries,
        },
        expected_baseline_keys={"rec-a", "rec-b", "rec-c"},
    )


def test_indbyrdes_overlap_parkerer_begge_valg():
    records = copy.deepcopy(BASELINE_RECORDS)
    records["rec-x"]["narrative"] = "Anders Testesen, f. 1900"
    result = build(
        {
            "rec-a": choice("rec-a", "P1"),
            "rec-x": choice("rec-x", text_anchor_id("rec-x", "Anders Testesen, f. 1900")),
        },
        baseline_records=records,
    )
    assert result["anchored"] == {}
    assert {(p["baseline_record_key"], p["reason_code"]) for p in result["parked"]} == {
        ("rec-a", "overlaps_other_manual_choice"),
        ("rec-x", "overlaps_other_manual_choice"),
    }


def test_audit_keys_og_andre_outcomes_springes_over():
    result = build(
        {
            "rec-a": choice("rec-a", "P1"),
            "rec-b": {
                "baseline_record_key": "rec-b",
                "outcome": "no_candidate_fits",
                "reason": "passer ikke",
            },
        },
        audit_keys={"rec-a"},
    )
    assert result["anchored"] == {}
    assert result["evidence_entries"] == []
    assert result["parked"] == []
    assert result["rewritten_choices"] == {
        "rec-a": choice("rec-a", "P1"),
        "rec-b": {
            "baseline_record_key": "rec-b",
            "outcome": "no_candidate_fits",
            "reason": "passer ikke",
        },
    }


def test_ukendt_kandidat_id_parkeres_som_ikke_fundet():
    result = build({
        "rec-a": choice("rec-a", "P9"),
        "rec-b": choice("rec-b", f"presentation:{PROFILE}:post:99"),
    })
    assert result["anchored"] == {}
    assert [(p["baseline_record_key"], p["reason_code"]) for p in result["parked"]] == [
        ("rec-a", "parser_post_not_found"),
        ("rec-b", "parser_post_not_found"),
    ]


def test_flertydigt_kandidat_id_parkeres():
    posts = copy.deepcopy(POSTS) + [copy.deepcopy(POSTS[0])]
    result = build({"rec-a": choice("rec-a", "P1")}, posts=posts)
    assert result["anchored"] == {}
    [parked] = result["parked"]
    assert parked["reason_code"] == "parser_post_ambiguous"


def test_text_anchor_digest_mismatch_parkeres():
    forged = f"presentation:{PROFILE}:text-anchor:{'0' * 64}"
    result = build({"rec-c": choice("rec-c", forged)})
    assert result["anchored"] == {}
    [parked] = result["parked"]
    assert parked["reason_code"] == "text_anchor_not_reproducible"
    assert parked["candidate_id"] == forged


def test_pdf_sider_parkerer_naar_grov_occurrence_ikke_indeholder_record_sider():
    result = build({
        "rec-d": choice("rec-d", "P4"),
        "rec-e": choice("rec-e", "P5"),
    })
    assert result["anchored"] == {}
    assert {
        parked["baseline_record_key"]: parked["reason_code"]
        for parked in result["parked"]
    } == {
        "rec-d": "pdf_pages_mismatch",
        "rec-e": "pdf_pages_mismatch",
    }


def test_tomt_kildeudsnit_parkeres_som_verbatim_mismatch():
    result = build({"rec-f": choice("rec-f", "P6")})
    assert result["anchored"] == {}
    [parked] = result["parked"]
    assert parked["reason_code"] == "span_verbatim_mismatch"


def test_occurrence_manifest_skal_matche_kildetekst():
    forged_sha = copy.deepcopy(CAL_OCCURRENCES)
    forged_sha["source_sha256"] = "0" * 64
    with pytest.raises(ValueError, match="^calamari_occurrence_manifest_mismatch$"):
        build({"rec-a": choice("rec-a", "P1")}, cal_occurrences=forged_sha)
    forged_length = copy.deepcopy(CAL_OCCURRENCES)
    forged_length["source_length"] = len(CALAMARI_TEXT) + 5
    with pytest.raises(ValueError, match="^calamari_occurrence_manifest_mismatch$"):
        build({"rec-a": choice("rec-a", "P1")}, cal_occurrences=forged_length)
    forged_raw = copy.deepcopy(RAW_OCCURRENCES)
    forged_raw["source_sha256"] = "0" * 64
    with pytest.raises(ValueError, match="^raw_ocr_occurrence_manifest_mismatch$"):
        build({"rec-a": choice("rec-a", "P1")}, raw_occurrences=forged_raw)


@pytest.mark.parametrize(
    ("rendition", "mutation", "message"),
    [
        ("calamari", "span", "calamari_occurrence_manifest_mismatch"),
        ("calamari", "occurrence_id", "calamari_occurrence_manifest_mismatch"),
        ("calamari", "pdf_pages", "calamari_occurrence_manifest_mismatch"),
        ("calamari", "verbatim_sha256", "calamari_occurrence_manifest_mismatch"),
        ("calamari", "neighbor", "calamari_occurrence_manifest_mismatch"),
        ("calamari", "alignment", "calamari_occurrence_manifest_mismatch"),
        ("raw_ocr", "span", "raw_ocr_occurrence_manifest_mismatch"),
        ("raw_ocr", "occurrence_id", "raw_ocr_occurrence_manifest_mismatch"),
        ("raw_ocr", "pdf_pages", "raw_ocr_occurrence_manifest_mismatch"),
        ("raw_ocr", "verbatim_sha256", "raw_ocr_occurrence_manifest_mismatch"),
        ("raw_ocr", "neighbor", "raw_ocr_occurrence_manifest_mismatch"),
        ("raw_ocr", "alignment", "raw_ocr_occurrence_manifest_mismatch"),
    ],
)
def test_occurrence_manifest_metadata_regenereres_fra_source_bytes(
    rendition, mutation, message,
):
    cal_manifest = copy.deepcopy(CAL_OCCURRENCES)
    raw_manifest = copy.deepcopy(RAW_OCCURRENCES)
    manifest = cal_manifest if rendition == "calamari" else raw_manifest
    occurrence = manifest["occurrences"][0]
    if mutation == "span":
        occurrence["span"]["char_from"] += 1
    elif mutation == "occurrence_id":
        occurrence["occurrence_id"] += "-forged"
    elif mutation == "pdf_pages":
        occurrence["pdf_pages"] = [497]
    elif mutation == "verbatim_sha256":
        occurrence["verbatim_sha256"] = "0" * 64
    elif mutation == "neighbor":
        occurrence["successor_signature"] = "0" * 64
    else:
        occurrence["printed_marker"] = "999"

    with pytest.raises(ValueError, match=message):
        build(
            {"rec-a": choice("rec-a", "P1")},
            cal_occurrences=cal_manifest,
            raw_occurrences=raw_manifest,
        )


def test_pdf_sider_bevarer_grov_flersidet_occurrence_men_kraever_subset():
    covering = {"pdf_pages": [496, 497]}
    assert subject._resolve_pdf_pages(covering, {"sider": "496"}) == [496, 497]
    with pytest.raises(subject._Parked) as mismatch:
        subject._resolve_pdf_pages(covering, {"sider": "498"})
    assert mismatch.value.reason_code == "pdf_pages_mismatch"


def test_kernen_afviser_kilder_der_ikke_matcher_expected_source():
    with pytest.raises(ValueError, match="calamari hash"):
        build({"rec-a": choice("rec-a", "P1")},
              source_overrides={"calamari_sha256": "d" * 64})
    with pytest.raises(ValueError, match="baseline hash"):
        build({"rec-a": choice("rec-a", "P1")},
              source_overrides={"baseline_sha256": "d" * 64})
    with pytest.raises(ValueError, match="raw OCR hash"):
        build({"rec-a": choice("rec-a", "P1")},
              source_overrides={"raw_ocr_sha256": "d" * 64})
    with pytest.raises(ValueError, match="profile_version"):
        build({"rec-a": choice("rec-a", "P1")},
              source_overrides={"profile_version": "1939-v1"})


def test_cr_i_calamari_afvises():
    with pytest.raises(ValueError, match="CR"):
        build({"rec-a": choice("rec-a", "P1")},
              calamari_text=CALAMARI_TEXT.replace("\n", "\r\n", 1))


def test_offsetdrift_parkeres_som_verbatim_mismatch(monkeypatch):
    original = subject._line_offsets

    def drifted(calamari_text):
        lines, offsets = original(calamari_text)
        return lines, [
            offset + (1 if index else 0) for index, offset in enumerate(offsets)
        ]

    monkeypatch.setattr(subject, "_line_offsets", drifted)
    result = build({"rec-a": choice("rec-a", "P1")})
    assert result["anchored"] == {}
    [parked] = result["parked"]
    assert parked["reason_code"] == "span_verbatim_mismatch"


def test_text_anchor_uden_sidetilhoer_parkeres():
    records = copy.deepcopy(BASELINE_RECORDS)
    records["rec-x"]["narrative"] = "### PAGE 0001 ###"
    forged = text_anchor_id("rec-x", "### PAGE 0001 ###")
    result = build({"rec-x": choice("rec-x", forged)}, baseline_records=records)
    assert result["anchored"] == {}
    [parked] = result["parked"]
    assert parked["reason_code"] == "text_anchor_not_reproducible"
    assert parked["candidate_id"] == forged


def test_posts_kan_ikke_leveres_udefra():
    records = copy.deepcopy(BASELINE_RECORDS)
    baseline_bytes = baseline_bytes_for(records)
    expected_source = source_for(baseline_bytes, CALAMARI_TEXT, RAW_TEXT)
    with pytest.raises(TypeError):
        build_human_anchored_candidates(
            {}, set(), copy.deepcopy(CLASSIFICATIONS), baseline_bytes,
            [], CALAMARI_TEXT, RAW_TEXT, copy.deepcopy(CAL_OCCURRENCES),
            copy.deepcopy(RAW_OCCURRENCES), PROFILE, expected_source, 11,
        )
    with pytest.raises(TypeError):
        build_human_anchored_candidates(
            {}, set(), copy.deepcopy(CLASSIFICATIONS), baseline_bytes,
            CALAMARI_TEXT, RAW_TEXT, copy.deepcopy(CAL_OCCURRENCES),
            copy.deepcopy(RAW_OCCURRENCES), PROFILE, expected_source, 11,
            posts=[],
        )


def test_text_anchor_for_post_med_nearby_kandidater_parkeres():
    records = copy.deepcopy(BASELINE_RECORDS)
    records["rec-c"]["sider"] = "496"
    forged = text_anchor_id("rec-c", CAL_LINES[3])
    result = build(
        {"rec-c": choice("rec-c", forged)},
        baseline_records=records,
        first_pdf_page=496,
    )
    assert result["anchored"] == {}
    [parked] = result["parked"]
    assert parked["reason_code"] == "text_anchor_not_reproducible"
    assert parked["candidate_id"] == forged


def test_aegte_anker_accepteres_trods_ikke_berettiget_overlap():
    records = copy.deepcopy(BASELINE_RECORDS)
    records["rec-x"]["narrative"] = "Cecilie Testdatter, f. 1904"
    records["rec-x"]["sider"] = "11"
    result = build(
        {"rec-c": choice("rec-c", text_anchor_id("rec-c", CAL_LINES[3]))},
        baseline_records=records,
    )
    assert result["parked"] == []
    [wrapper] = result["anchored"].values()
    assert wrapper["baseline_record_key"] == "rec-c"
    assert wrapper["candidate"]["calamari_span"] == {
        "char_from": SPAN_C[0], "char_to": SPAN_C[1],
    }


def test_pdf_fallback_laeser_record_sider_uden_daekkende_occurrence():
    assert subject._resolve_pdf_pages(None, {"sider": "503"}) == [503]


def test_kaede_choices_til_accepteret_decision():
    result = build({"rec-a": choice("rec-a", "P1")})
    [(human_id, wrapper)] = result["anchored"].items()
    assert wrapper["baseline_record_key"] == "rec-a"
    converted = convert_review_choices(
        result["rewritten_choices"],
        result["anchored"],
        copy.deepcopy(CLASSIFICATIONS),
        set(),
    )
    assert {
        "baseline_record_key": "rec-a",
        "status": "accepteret",
        "candidate_id": human_id,
    } in converted["decisions"]


def _composition_fixture():
    records = copy.deepcopy(BASELINE_RECORDS)
    baseline_bytes = baseline_bytes_for(records)
    source = source_for(baseline_bytes, CALAMARI_TEXT, RAW_TEXT)
    human_result = build({"rec-a": choice("rec-a", "P1")})
    return (
        base_evidence_for(source), human_result["evidence_entries"], source,
        set(records),
    )


@pytest.mark.parametrize("corruption", ["source", "missing", "unknown", "duplicate"])
def test_composition_afviser_forkert_source_eller_baseline_daekning(corruption):
    base, human_entries, source, baseline_keys = _composition_fixture()
    if corruption == "source":
        base["source"]["calamari_sha256"] = "0" * 64
    elif corruption == "missing":
        base["entries"].pop()
    elif corruption == "unknown":
        base["entries"][-1]["baseline_record_key"] = "ukendt"
    else:
        base["entries"][-1]["baseline_record_key"] = base["entries"][0][
            "baseline_record_key"
        ]

    with pytest.raises(ValueError):
        subject.compose_human_evidence_bundle(
            base, human_entries, source, baseline_keys, CALAMARI_TEXT, RAW_TEXT,
        )


@pytest.mark.parametrize("blocked_kind", ["source_blocker", "existing_evidence"])
def test_composition_afviser_erstatning_af_blokeret_eller_positiv_base_entry(
    blocked_kind,
):
    base, human_entries, source, baseline_keys = _composition_fixture()
    base_by_key = {entry["baseline_record_key"]: entry for entry in base["entries"]}
    if blocked_kind == "source_blocker":
        base_by_key["rec-a"]["source_blockers"] = ["raw_ocr_missing"]
        message = "source-blokeret"
    else:
        base_by_key["rec-a"] = copy.deepcopy(human_entries[0])
        base["entries"] = [
            base_by_key[entry["baseline_record_key"]] for entry in base["entries"]
        ]
        message = "eksisterende positiv evidens"

    with pytest.raises(ValueError, match=message):
        subject.compose_human_evidence_bundle(
            base, human_entries, source, baseline_keys, CALAMARI_TEXT, RAW_TEXT,
        )


def test_composition_afviser_global_kollision_mod_retained_positiv_kandidat():
    base, human_entries, source, baseline_keys = _composition_fixture()
    retained = copy.deepcopy(human_entries[0])
    retained["baseline_record_key"] = "rec-x"
    retained["positive_provenance"]["baseline_record_key"] = "rec-x"
    base["entries"] = [
        retained if entry["baseline_record_key"] == "rec-x" else entry
        for entry in base["entries"]
    ]

    with pytest.raises(ValueError, match="injektiv"):
        subject.compose_human_evidence_bundle(
            base, human_entries, source, baseline_keys, CALAMARI_TEXT, RAW_TEXT,
        )


def _write_cli_fixture(tmp_path, *, corrupt_calamari=False):
    baseline = [copy.deepcopy(BASELINE_RECORDS[key]) for key in RECORD_KEYS]
    baseline_bytes = json.dumps(baseline).encode("utf-8")
    calamari_bytes = CALAMARI_TEXT.encode("utf-8")
    raw_bytes = RAW_TEXT.encode("utf-8")
    source = {
        "edition": "1939",
        "baseline_sha256": hashlib.sha256(baseline_bytes).hexdigest(),
        "calamari_sha256": hashlib.sha256(calamari_bytes).hexdigest(),
        "raw_ocr_sha256": hashlib.sha256(raw_bytes).hexdigest(),
        "pdf_sha256": "c" * 64,
        "profile_version": PROFILE,
    }
    queue = {
        "schema_version": 1,
        "source": source,
        "entries": [human_required(key) for key in RECORD_KEYS],
    }
    export = {
        "schema_version": 1,
        "source": source,
        "exported_at": "2026-08-06T12:00:00Z",
        "entries": [choice("rec-a", "P1")] + [
            {"baseline_record_key": key, "review_status": "unreviewed"}
            for key in RECORD_KEYS if key != "rec-a"
        ],
    }
    if corrupt_calamari:
        calamari_bytes += b"X"
    paths = {
        "choices": tmp_path / "choices.json",
        "queue": tmp_path / "queue.json",
        "baseline": tmp_path / "baseline.json",
        "calamari": tmp_path / "calamari.txt",
        "raw": tmp_path / "raw.txt",
        "cal_occ": tmp_path / "cal-occ.json",
        "raw_occ": tmp_path / "raw-occ.json",
        "base_evidence": tmp_path / "base-evidence.json",
        "wrapper_out": tmp_path / "wrapper.json",
        "evidence_out": tmp_path / "evidence.json",
        "report_out": tmp_path / "report.json",
        "rewritten_out": tmp_path / "rewritten-choices.json",
    }
    paths["choices"].write_text(json.dumps(export), encoding="utf-8")
    paths["queue"].write_text(json.dumps(queue), encoding="utf-8")
    paths["baseline"].write_bytes(baseline_bytes)
    paths["calamari"].write_bytes(calamari_bytes)
    paths["raw"].write_bytes(raw_bytes)
    paths["cal_occ"].write_text(json.dumps(CAL_OCCURRENCES), encoding="utf-8")
    paths["raw_occ"].write_text(json.dumps(RAW_OCCURRENCES), encoding="utf-8")
    paths["base_evidence"].write_text(
        json.dumps(base_evidence_for(source)), encoding="utf-8"
    )
    return paths


def _cli_argv(paths):
    return [
        "anchor_review_choices_1939.py",
        "--choices", str(paths["choices"]),
        "--queue-manifest", str(paths["queue"]),
        "--baseline", str(paths["baseline"]),
        "--calamari", str(paths["calamari"]),
        "--raw", str(paths["raw"]),
        "--calamari-occurrences", str(paths["cal_occ"]),
        "--raw-occurrences", str(paths["raw_occ"]),
        "--base-evidence", str(paths["base_evidence"]),
        "--calamari-first-pdf-page", "11",
        "--wrapper-out", str(paths["wrapper_out"]),
        "--evidence-out", str(paths["evidence_out"]),
        "--report-out", str(paths["report_out"]),
        "--rewritten-choices-out", str(paths["rewritten_out"]),
    ]


def test_cli_hash_gate_afviser_forkerte_kildebytes(tmp_path, monkeypatch):
    paths = _write_cli_fixture(tmp_path, corrupt_calamari=True)
    monkeypatch.setattr("sys.argv", _cli_argv(paths))
    with pytest.raises(ValueError, match="calamari hash"):
        subject.main()
    assert not paths["wrapper_out"].exists()
    assert not paths["evidence_out"].exists()
    assert not paths["report_out"].exists()
    assert not paths["rewritten_out"].exists()


def test_cli_skriver_wrapper_evidens_og_rapport(tmp_path, monkeypatch):
    paths = _write_cli_fixture(tmp_path)
    monkeypatch.setattr(subject.segment, "_segment_1939_v2",
                        lambda lines, profile: copy.deepcopy(POSTS))
    monkeypatch.setattr("sys.argv", _cli_argv(paths))
    assert subject.main() == 0
    wrapper = json.loads(paths["wrapper_out"].read_text(encoding="utf-8"))
    [(candidate_id, entry)] = wrapper.items()
    assert candidate_id == expected_human_id(SPAN_A)
    assert entry["baseline_record_key"] == "rec-a"
    evidence = json.loads(paths["evidence_out"].read_text(encoding="utf-8"))
    assert evidence["schema_version"] == 1
    assert evidence["source"] == json.loads(
        paths["queue"].read_text(encoding="utf-8")
    )["source"]
    assert [item["baseline_record_key"] for item in evidence["entries"]] == list(
        RECORD_KEYS
    )
    human_entry = next(
        item for item in evidence["entries"]
        if item["baseline_record_key"] == "rec-a"
    )
    assert human_entry["rule_id"] == "human_anchor_v1"
    assert human_entry["positive_provenance"]["candidate_id"] == candidate_id

    validated = publication_subject._source_bound_evidence_entries(
        evidence, evidence["source"], set(RECORD_KEYS), CALAMARI_TEXT, RAW_TEXT,
    )
    manifest = publication_subject.classify_review_entries(
        evidence["source"], set(RECORD_KEYS), validated,
    )
    state = publication_subject._review_state(
        {
            "decisions": [{
                "baseline_record_key": "rec-a",
                "status": "accepteret",
                "candidate_id": candidate_id,
            }],
            "audit_results": [],
        },
        evidence["source"],
        set(RECORD_KEYS),
        evidence_entries=validated,
        manifest=manifest,
        baseline_by_key={
            record["record_key"]: record
            for record in json.loads(paths["baseline"].read_text(encoding="utf-8"))
        },
        calamari_text=CALAMARI_TEXT,
        raw_text=RAW_TEXT,
    )
    assert "rec-a" in state.completed_keys
    report = json.loads(paths["report_out"].read_text(encoding="utf-8"))
    assert report["anchored_count"] == 1
    assert report["parked_count"] == 0
    assert report["parked"] == []
    with pytest.raises(FileExistsError):
        subject.main()


def test_cli_afviser_duplikerede_output_stier(tmp_path, monkeypatch):
    paths = _write_cli_fixture(tmp_path)
    paths["evidence_out"] = paths["wrapper_out"]
    monkeypatch.setattr("sys.argv", _cli_argv(paths))
    with pytest.raises(ValueError, match="output-stier"):
        subject.main()
    assert not paths["wrapper_out"].exists()
    assert not paths["report_out"].exists()


def test_cli_fejl_under_skrivning_efterlader_ingen_output(tmp_path, monkeypatch):
    paths = _write_cli_fixture(tmp_path)
    monkeypatch.setattr(subject.segment, "_segment_1939_v2",
                        lambda lines, profile: copy.deepcopy(POSTS))
    monkeypatch.setattr("sys.argv", _cli_argv(paths))
    original_open = subject.Path.open

    def failing_open(self, *open_args, **open_kwargs):
        if self == paths["rewritten_out"]:
            raise OSError("disk fuld")
        return original_open(self, *open_args, **open_kwargs)

    monkeypatch.setattr("pathlib.Path.open", failing_open)
    with pytest.raises(OSError, match="disk fuld"):
        subject.main()
    assert not paths["wrapper_out"].exists()
    assert not paths["evidence_out"].exists()
    assert not paths["report_out"].exists()
    assert not paths["rewritten_out"].exists()


def test_cli_fejl_ved_lukning_efterlader_ingen_output(tmp_path, monkeypatch):
    paths = _write_cli_fixture(tmp_path)
    monkeypatch.setattr(subject.segment, "_segment_1939_v2",
                        lambda lines, profile: copy.deepcopy(POSTS))
    monkeypatch.setattr("sys.argv", _cli_argv(paths))
    original_open = subject.Path.open

    class FailingCloseHandle:
        def __init__(self, handle):
            self._handle = handle

        def write(self, text):
            return self._handle.write(text)

        def close(self):
            self._handle.close()
            raise OSError("disk fuld ved lukning")

    def wrapping_open(self, *open_args, **open_kwargs):
        handle = original_open(self, *open_args, **open_kwargs)
        if self == paths["report_out"]:
            return FailingCloseHandle(handle)
        return handle

    monkeypatch.setattr("pathlib.Path.open", wrapping_open)
    with pytest.raises(OSError, match="disk fuld ved lukning"):
        subject.main()
    assert not paths["wrapper_out"].exists()
    assert not paths["evidence_out"].exists()
    assert not paths["report_out"].exists()
    assert not paths["rewritten_out"].exists()


def test_cli_rewritten_choices_bestaar_validate_choice_export(tmp_path, monkeypatch):
    paths = _write_cli_fixture(tmp_path)
    monkeypatch.setattr(subject.segment, "_segment_1939_v2",
                        lambda lines, profile: copy.deepcopy(POSTS))
    monkeypatch.setattr("sys.argv", _cli_argv(paths))
    assert subject.main() == 0
    rewritten = json.loads(paths["rewritten_out"].read_text(encoding="utf-8"))
    source = json.loads(paths["queue"].read_text(encoding="utf-8"))["source"]
    assert rewritten["exported_at"] == "2026-08-06T12:00:00Z"
    assert rewritten["baseline_sha256"] == source["baseline_sha256"]
    assert [entry["baseline_record_key"] for entry in rewritten["entries"]] == list(
        RECORD_KEYS
    )
    validated = validate_choice_export(rewritten, source, set(RECORD_KEYS))
    assert validated["rec-a"]["candidate_id"] == expected_human_id(SPAN_A)
    assert set(validated) == {"rec-a"}
