import json
import re
import shutil
import subprocess
import sys
import hashlib
from pathlib import Path

import pytest

import make_human_review_1939 as subject


def test_pages_expands_ranges_and_rejects_malformed_values():
    assert subject._pages("496-498") == [496, 497, 498]
    assert subject._pages("498") == [498]
    assert subject._pages("498-496") == []


def test_pages_afviser_uparsebar_sideangivelse():
    assert subject._pages(None) == []
    assert subject._pages("") == []
    assert subject._pages("8") == [8]
    assert subject._pages("8-10") == [8, 9, 10]
    with pytest.raises(ValueError):
        subject._pages("ukendt")
    with pytest.raises(ValueError):
        subject._pages("side 498")


def test_presentation_candidates_are_deterministic_and_preserve_unique_local_id():
    posts = [
        {"lokal_id": None, "sider": "3", "raw_text": "Uden id"},
        {"lokal_id": "Stamme.Volrad", "sider": "3", "raw_text": "Volrad"},
    ]

    first = subject._presentation_candidates(posts, 496, "1939-v2")
    second = subject._presentation_candidates(posts, 496, "1939-v2")

    assert first == second
    assert first[0]["candidate_id"] == "presentation:1939-v2:post:0"
    assert first[0]["lokal_id"] == "presentation:1939-v2:post:0"
    assert first[1]["candidate_id"] == "Stamme.Volrad"
    assert first[1]["lokal_id"] == "Stamme.Volrad"


def test_colliding_local_ids_keep_presentation_value_but_get_unique_namespaced_ids():
    posts = [
        {"lokal_id": "Stamme.Dublet", "sider": "3", "raw_text": "Første"},
        {"lokal_id": "Stamme.Dublet", "sider": "3", "raw_text": "Anden"},
    ]

    candidates = subject._presentation_candidates(posts, 496, "1939-v2")

    assert [candidate["candidate_id"] for candidate in candidates] == [
        "presentation:1939-v2:post:0", "presentation:1939-v2:post:1",
    ]
    assert [candidate["lokal_id"] for candidate in candidates] == [
        "Stamme.Dublet", "Stamme.Dublet",
    ]


@pytest.mark.parametrize(
    ("posts", "profile", "message"),
    [
        ([{"lokal_id": None, "sider": "3"}], "", "profile_version"),
        (
            [
                {"lokal_id": None, "sider": "3"},
                {"lokal_id": "presentation:1939-v2:post:0", "sider": "3"},
            ],
            "1939-v2",
            "candidate_id-kollision",
        ),
    ],
)
def test_presentation_candidate_identity_fails_closed(posts, profile, message):
    with pytest.raises(ValueError, match=message):
        subject._presentation_candidates(posts, 496, profile)


def test_presentation_candidate_rejects_invalid_post_index():
    with pytest.raises(ValueError, match="post_index"):
        subject._candidate_from_post(
            {"lokal_id": None, "sider": "3"}, 496, "1939-v2", -1,
            force_presentation_id=True,
        )


def test_exact_text_anchor_fallback_rejects_a_repeated_narrative():
    narrative = "Markvard sælger en Rente af 100 Mark Lybsk."
    source = f"### PAGE 0085 ###\n{narrative}\n{narrative}"

    candidates = subject._unique_exact_text_anchor_candidates(
        [{"record_key": "rk-markvard", "narrative": narrative}],
        source, 496, "1939-v2",
    )

    assert candidates == {}


def test_exact_text_anchor_fallback_rejects_overlapping_baseline_claims():
    full = "Markvard sælger 1423 en Rente af 100 Mark Lybsk til Abbed Bertram."
    nested = "en Rente af 100 Mark Lybsk"
    source = f"### PAGE 0085 ###\n{full}"

    candidates = subject._unique_exact_text_anchor_candidates([
        {"record_key": "rk-full", "narrative": full},
        {"record_key": "rk-nested", "narrative": nested},
    ], source, 496, "1939-v2")

    assert candidates == {}


def test_text_anchor_fallback_is_limited_to_human_required_records():
    manifest = {"entries": [
        {"baseline_record_key": "rk-human", "queue_class": "human_required"},
        {"baseline_record_key": "rk-auto", "queue_class": "auto_resolved"},
        {"baseline_record_key": "rk-blocked", "queue_class": "source_blocked"},
    ]}

    assert subject._text_anchor_fallback_keys(manifest) == {"rk-human"}


def test_exact_text_fallback_distinguishes_a_parser_gap_on_the_expected_page():
    narrative = "Markvard sælger 1423 en Rente af 100 Mark Lybsk."
    source = f"### PAGE 0085 ###\n{narrative}"

    # Calamari page 85 translates to PDF 597 through CALAMARI_R6_TO_PDF_V1, so
    # 597 is the record's own expected page for this branch.
    candidates = subject._unique_exact_text_anchor_candidates(
        [{"record_key": "rk-markvard", "narrative": narrative, "sider": "597"}],
        source, 496, "1939-v2",
    )

    assert candidates["rk-markvard"]["rank_reason"] == (
        "entydigt_tekstanker_uden_parserkandidat"
    )


def _source(baseline_bytes, calamari_bytes, raw_bytes=b"Raa OCR Volrad"):
    return {
        "edition": "1939",
        "baseline_sha256": hashlib.sha256(baseline_bytes).hexdigest(),
        "calamari_sha256": hashlib.sha256(calamari_bytes).hexdigest(),
        "raw_ocr_sha256": hashlib.sha256(raw_bytes).hexdigest(),
        "pdf_sha256": "d" * 64,
        "profile_version": "1939-v2",
    }


def _write_inputs(tmp_path):
    baseline = tmp_path / "baseline.json"
    review = tmp_path / "review.json"
    queue = tmp_path / "queue.json"
    source = tmp_path / "source.json"
    calamari = tmp_path / "calamari.txt"
    raw = tmp_path / "raw.txt"
    baseline.write_text(json.dumps([{
        "record_key": "record-1", "navn": "Volrad", "sider": "498",
    }]), encoding="utf-8")
    calamari.write_text("### PAGE 0003 ###\nVolrad", encoding="utf-8")
    raw.write_text("Raa OCR Volrad", encoding="utf-8")
    source_value = _source(baseline.read_bytes(), calamari.read_bytes(), raw.read_bytes())
    source.write_text(json.dumps({"schema_version": 1, "source": source_value}), encoding="utf-8")
    queue.write_text(json.dumps({"schema_version": 1, "source": source_value, "entries": [{
        "baseline_record_key": "record-1", "queue_class": "human_required",
        "reason_code": "no_candidate", "reason_da": "ingen kandidat",
    }]}), encoding="utf-8")
    review.write_text(json.dumps({"schema_version": 1, "source": source_value,
        "baseline_sha256": source_value["baseline_sha256"], "entries": [{
            "baseline_record_key": "record-1", "review_status": "unreviewed",
        }]}), encoding="utf-8")
    return baseline, review, queue, source, calamari


def _argv(baseline, review, queue, source, calamari, out):
    return ["make_human_review_1939.py", "--baseline", str(baseline),
            "--queue-manifest", str(queue), "--source-manifest", str(source),
            "--review", str(review), "--calamari", str(calamari),
            "--raw", str(calamari.with_name("raw.txt")),
            "--calamari-first-pdf-page", "496", "--out", str(out)]


def test_hydrates_exact_dual_rendition_text_for_source_bound_candidate():
    calamari = "forord\n3. Greve Otto Carl Ferdinand Christian Gottlieb\nslut"
    raw = "forord\n3. Greve O t t o Carl Ferdinand Christian Gottlieb\nslut"
    calamari_text = "3. Greve Otto Carl Ferdinand Christian Gottlieb"
    raw_text = "3. Greve O t t o Carl Ferdinand Christian Gottlieb"
    calamari_from = calamari.index(calamari_text)
    raw_from = raw.index(raw_text)
    evidence = {
        "candidate_id": "candidate-otto",
        "postklasse": "nummereret",
        "calamari_span": {
            "char_from": calamari_from,
            "char_to": calamari_from + len(calamari_text),
        },
        "pdf_pages": [578],
        "raw_structure_bridge": {
            "kind": "dual_rendition_consensus_v1",
            "raw_char_from": raw_from,
            "raw_char_to": raw_from + len(raw_text),
            "raw_excerpt_sha256": hashlib.sha256(raw_text.encode("utf-8")).hexdigest(),
        },
    }
    model = {"records": [{
        "queue_class": "auto_resolved",
        "classification": {"candidate": evidence},
        "candidates": [{
        "candidate_id": "candidate-otto",
        "details": evidence,
    }]}]}

    subject._hydrate_source_bound_candidates(model, calamari, raw)

    candidate = model["records"][0]["candidates"][0]
    assert candidate["calamari_verbatim_text"] == calamari_text
    assert candidate["raw_verbatim_text"] == raw_text


def test_source_hydration_rejects_wrong_raw_excerpt_hash():
    evidence = {
        "candidate_id": "candidate-1",
        "postklasse": "nummereret",
        "calamari_span": {"char_from": 0, "char_to": 1},
        "pdf_pages": [498],
        "raw_structure_bridge": {
            "kind": "dual_rendition_consensus_v1",
            "raw_char_from": 0,
            "raw_char_to": 1,
            "raw_excerpt_sha256": "0" * 64,
        },
    }
    model = {"records": [{
        "queue_class": "auto_resolved",
        "classification": {"candidate": evidence},
        "candidates": [{"candidate_id": "candidate-1", "details": evidence}],
    }]}

    with pytest.raises(ValueError, match="raw_excerpt_sha256"):
        subject._hydrate_source_bound_candidates(model, "A", "A")


def test_source_hydration_does_not_upgrade_a_human_page_candidate():
    details = {
        "candidate_id": "page-candidate",
        "postklasse": "nummereret",
        "calamari_span": {"char_from": 0, "char_to": 1},
        "pdf_pages": [498],
        "raw_structure_bridge": {
            "kind": "dual_rendition_consensus_v1",
            "raw_char_from": 0,
            "raw_char_to": 1,
            "raw_excerpt_sha256": hashlib.sha256(b"A").hexdigest(),
        },
    }
    candidate = {"candidate_id": "page-candidate", "details": details}
    model = {"records": [{
        "queue_class": "human_required",
        "classification": {"candidate": None},
        "candidates": [candidate],
    }]}

    subject._hydrate_source_bound_candidates(model, "A", "A")

    assert "calamari_verbatim_text" not in candidate
    assert "raw_verbatim_text" not in candidate


def test_main_rejects_changed_complete_raw_source(tmp_path, monkeypatch):
    baseline, review, queue, source, calamari = _write_inputs(tmp_path)
    out = tmp_path / "menneskeark.html"
    calamari.with_name("raw.txt").write_text("aendret raw OCR", encoding="utf-8")
    monkeypatch.setattr(sys, "argv", _argv(baseline, review, queue, source, calamari, out))

    with pytest.raises(ValueError, match="raw OCR hash"):
        subject.main()


def test_main_shows_candidates_on_translated_pdf_pages(tmp_path, monkeypatch):
    baseline, review, queue, source, calamari = _write_inputs(tmp_path)
    out = tmp_path / "menneskeark.html"
    monkeypatch.setattr(subject.segment, "_segment_1939_v2", lambda *_: [{
        "lokal_id": "Stamme.Volrad", "sider": "3", "raw_text": "Hr. Volrad",
    }])
    monkeypatch.setattr(sys, "argv", _argv(baseline, review, queue, source, calamari, out))

    assert subject.main() == 0

    payload = json.loads(re.search(
        r"const DATA=(.*?);\n\(function \(global\)", out.read_text(encoding="utf-8")
    ).group(1))
    assert payload["records"][0]["candidates"] == [{
        "candidate_id": "Stamme.Volrad",
        "lokal_id": "Stamme.Volrad",
        "pdf_pages": [498],
        "calamari_pages": [3],
        "raw_text": "Hr. Volrad",
        "rank_reason": "samme_pdf_side",
    }]
    assert payload["default_view"] == "required"
    rendered = out.read_text(encoding="utf-8")
    assert "window.DAA1939Review.init({data: DATA, download: downloadDraft});" in rendered
    assert "data-action" in rendered
    assert "daa1939-review:" in rendered


def test_main_emits_a_node_parseable_script_block(tmp_path, monkeypatch):
    """A literal backslash-n separator makes the generated page unparseable."""
    if shutil.which("node") is None:
        pytest.skip("node findes ikke på PATH")

    baseline, review, queue, source, calamari = _write_inputs(tmp_path)
    out = tmp_path / "menneskeark.html"
    monkeypatch.setattr(sys, "argv", _argv(baseline, review, queue, source, calamari, out))

    assert subject.main() == 0

    rendered = out.read_text(encoding="utf-8")
    script = rendered.split("<script>", 1)[1].split("</script>", 1)[0]
    script_path = tmp_path / "menneskeark.js"
    script_path.write_text(script, encoding="utf-8")
    result = subprocess.run(
        ["node", "--check", str(script_path)], text=True, capture_output=True,
    )
    assert result.returncode == 0, result.stderr or result.stdout


def test_main_shows_a_unique_exact_text_anchor_when_the_baseline_page_is_stale(
    tmp_path, monkeypatch
):
    baseline, review, queue, source, calamari = _write_inputs(tmp_path)
    out = tmp_path / "menneskeark.html"
    narrative = (
        "Markvard (Marquardus Revetlo ''laicus, frater religiosi\n"
        "viri domini Hartwic Reventlo ordinis Carthusiensis sælger\n"
        "1423 til Abbed Bertram i Reinfeld en Rente af 100 Mark Lybsk\n"
        "(Reinfeld Nr. 13, Statsark. i Kiel)."
    )
    baseline_value = json.loads(baseline.read_text(encoding="utf-8"))
    baseline_value[0].update(navn="Markvard", sider="598", narrative=narrative)
    baseline.write_text(json.dumps(baseline_value), encoding="utf-8")
    calamari.write_text(
        "### PAGE 0085 ###\n" + narrative + "\n### PAGE 0086 ###\nNæste side",
        encoding="utf-8",
    )
    source_value = _source(
        baseline.read_bytes(), calamari.read_bytes(),
        calamari.with_name("raw.txt").read_bytes(),
    )
    source.write_text(json.dumps({"schema_version": 1, "source": source_value}), encoding="utf-8")
    queue_value = json.loads(queue.read_text(encoding="utf-8"))
    queue_value["source"] = source_value
    queue.write_text(json.dumps(queue_value), encoding="utf-8")
    review_value = json.loads(review.read_text(encoding="utf-8"))
    review_value["source"] = source_value
    review_value["baseline_sha256"] = source_value["baseline_sha256"]
    review.write_text(json.dumps(review_value), encoding="utf-8")
    monkeypatch.setattr(subject.segment, "_segment_1939_v2", lambda *_: [])
    monkeypatch.setattr(sys, "argv", _argv(baseline, review, queue, source, calamari, out))

    assert subject.main() == 0

    payload = json.loads(re.search(
        r"const DATA=(.*?);\n\(function \(global\)", out.read_text(encoding="utf-8")
    ).group(1))
    assert len(payload["records"][0]["candidates"]) == 1
    candidate_id = payload["records"][0]["candidates"][0]["candidate_id"]
    assert payload["records"][0]["candidates"] == [{
        "candidate_id": candidate_id,
        "lokal_id": candidate_id,
        "pdf_pages": [597],
        "calamari_pages": [85],
        "raw_text": narrative,
        "rank_reason": "entydigt_tekstanker_uden_forventet_side",
    }]
    assert candidate_id.startswith(
        "presentation:1939-v2:text-anchor:"
    )


def test_main_generates_html_when_segment_posts_lack_or_duplicate_local_ids(
    tmp_path, monkeypatch
):
    baseline, review, queue, source, calamari = _write_inputs(tmp_path)
    out = tmp_path / "menneskeark.html"
    monkeypatch.setattr(subject.segment, "_segment_1939_v2", lambda *_: [
        {"lokal_id": None, "sider": "3", "raw_text": "Uden id"},
        {"lokal_id": "Stamme.Dublet", "sider": "3", "raw_text": "Første"},
        {"lokal_id": "Stamme.Dublet", "sider": "3", "raw_text": "Anden"},
    ])
    monkeypatch.setattr(sys, "argv", _argv(baseline, review, queue, source, calamari, out))

    assert subject.main() == 0

    payload = json.loads(re.search(
        r"const DATA=(.*?);\n\(function \(global\)", out.read_text(encoding="utf-8")
    ).group(1))
    candidates = payload["records"][0]["candidates"]
    assert [candidate["candidate_id"] for candidate in candidates] == [
        "presentation:1939-v2:post:0",
        "presentation:1939-v2:post:1",
        "presentation:1939-v2:post:2",
    ]
    assert [candidate["lokal_id"] for candidate in candidates] == [
        "presentation:1939-v2:post:0", "Stamme.Dublet", "Stamme.Dublet",
    ]


def test_main_embeds_the_committed_controller_bytes_without_inline_handlers(tmp_path, monkeypatch):
    baseline, review, queue, source, calamari = _write_inputs(tmp_path)
    out = tmp_path / "menneskeark.html"
    monkeypatch.setattr(sys, "argv", _argv(baseline, review, queue, source, calamari, out))

    assert subject.main() == 0

    rendered = out.read_bytes()
    committed = (Path(subject.__file__).parent / "human_review_1939_ui.js").read_bytes()
    start = rendered.index(
        b"(function (global) {", rendered.index(b"global.DAAReviewShared")
    )
    end = start + len(committed)
    assert rendered[start:end] == committed
    assert b"onclick=" not in rendered


def test_main_gives_sidebar_names_and_record_content_independent_scroll_containers(
    tmp_path, monkeypatch
):
    baseline, review, queue, source, calamari = _write_inputs(tmp_path)
    out = tmp_path / "menneskeark.html"
    monkeypatch.setattr(sys, "argv", _argv(baseline, review, queue, source, calamari, out))

    assert subject.main() == 0

    rendered = out.read_text(encoding="utf-8")
    style = re.search(r"<style>(.*?)</style>", rendered, flags=re.DOTALL).group(1)
    aside_rule = re.search(r"aside\{([^}]*)\}", style).group(1)
    main_rule = re.search(r"main\{([^}]*)\}", style).group(1)
    list_rule = re.search(
        r'\[data-role="record-list"\]\{([^}]*)\}', style,
    ).group(1)
    assert "height:100dvh" in aside_rule
    assert "overflow:hidden" in aside_rule
    assert "overflow:auto" in main_rule
    assert "flex:1" in list_rule
    assert "min-height:0" in list_rule
    assert "overflow-y:auto" in list_rule


def test_main_uses_a_plain_desktop_sidebar_and_a_separate_mobile_toggle(
    tmp_path, monkeypatch
):
    baseline, review, queue, source, calamari = _write_inputs(tmp_path)
    out = tmp_path / "menneskeark.html"
    monkeypatch.setattr(sys, "argv", _argv(baseline, review, queue, source, calamari, out))

    assert subject.main() == 0

    rendered = out.read_text(encoding="utf-8")
    prefix = rendered.split("const DATA=", 1)[0]
    assert '<aside data-mobile-open="false">' in prefix
    assert 'data-action="toggle-sidebar"' in prefix
    assert 'data-role="sidebar-navigation"' in prefix
    assert "<details" not in prefix


def test_main_escapes_mixed_case_closing_script_in_source_text(tmp_path, monkeypatch):
    baseline, review, queue, source, calamari = _write_inputs(tmp_path)
    out = tmp_path / "menneskeark.html"
    hostile_text = 'Før </ScRiPt><img data-injected="yes"> efter'
    baseline_value = json.loads(baseline.read_text(encoding="utf-8"))
    baseline_value[0]["narrative"] = hostile_text
    baseline.write_text(json.dumps(baseline_value), encoding="utf-8")
    source_value = _source(baseline.read_bytes(), calamari.read_bytes())
    source.write_text(json.dumps({"schema_version": 1, "source": source_value}), encoding="utf-8")
    queue_value = json.loads(queue.read_text(encoding="utf-8"))
    queue_value["source"] = source_value
    queue.write_text(json.dumps(queue_value), encoding="utf-8")
    review_value = json.loads(review.read_text(encoding="utf-8"))
    review_value["source"] = source_value
    review_value["baseline_sha256"] = source_value["baseline_sha256"]
    review.write_text(json.dumps(review_value), encoding="utf-8")
    monkeypatch.setattr(sys, "argv", _argv(baseline, review, queue, source, calamari, out))

    assert subject.main() == 0

    rendered = out.read_text(encoding="utf-8")
    assert len(re.findall(r"<script\b", rendered, flags=re.IGNORECASE)) == 1
    assert len(re.findall(r"</script\s*>", rendered, flags=re.IGNORECASE)) == 1
    assert '<img data-injected="yes">' not in rendered
    embedded_json = re.search(
        r"const DATA=(.*?);\n\(function \(global\)", rendered,
    ).group(1)
    assert "<" not in embedded_json
    payload = json.loads(embedded_json)
    assert payload["records"][0]["narrative"] == hostile_text


def test_main_escapes_mixed_case_closing_script_in_diagnostic_reason(tmp_path, monkeypatch):
    baseline, review, queue, source, calamari = _write_inputs(tmp_path)
    out = tmp_path / "menneskeark.html"
    hostile_reason = 'Før </ScRiPt><img data-injected="reason"> efter'
    queue_value = json.loads(queue.read_text(encoding="utf-8"))
    queue_value["entries"][0].update(
        reason_code="boundary_disagreement", reason_da=hostile_reason,
    )
    queue.write_text(json.dumps(queue_value), encoding="utf-8")
    monkeypatch.setattr(sys, "argv", _argv(baseline, review, queue, source, calamari, out))

    assert subject.main() == 0

    rendered = out.read_text(encoding="utf-8")
    assert len(re.findall(r"<script\b", rendered, flags=re.IGNORECASE)) == 1
    assert '<img data-injected="reason">' not in rendered
    payload = json.loads(re.search(
        r"const DATA=(.*?);\n\(function \(global\)", rendered,
    ).group(1))
    assert payload["records"][0]["reason_da"] == hostile_reason


def test_main_embeds_specific_raw_exact_anchor_failure_diagnosis(tmp_path, monkeypatch):
    baseline, review, queue, source, calamari = _write_inputs(tmp_path)
    out = tmp_path / "menneskeark.html"
    queue_value = json.loads(queue.read_text(encoding="utf-8"))
    queue_value["entries"][0].update(
        reason_code="missing_exact_baseline_narrative",
        reason_da=(
            "Det lagrede narrativ findes ikke præcist én gang i rå OCR; "
            "derfor findes ingen positiv kildebro."
        ),
        anchor_rendition="raw_ocr",
    )
    queue.write_text(json.dumps(queue_value), encoding="utf-8")
    monkeypatch.setattr(sys, "argv", _argv(baseline, review, queue, source, calamari, out))

    assert subject.main() == 0

    payload = json.loads(re.search(
        r"const DATA=(.*?);\n\(function \(global\)", out.read_text(encoding="utf-8")
    ).group(1))
    record = payload["records"][0]
    assert record["reason_code"] == "missing_exact_baseline_narrative"
    assert record["reason_da"] == (
        "Det lagrede narrativ findes ikke præcist én gang i rå OCR; "
        "derfor findes ingen positiv kildebro."
    )
    assert record["boundary_context"] == "Rå OCR: intet præcist, entydigt narrativanker."


@pytest.mark.parametrize("which", ["baseline", "queue", "review", "source"])
def test_main_rejects_disagreeing_hashes(tmp_path, monkeypatch, which):
    baseline, review, queue, source, calamari = _write_inputs(tmp_path)
    out = tmp_path / "menneskeark.html"
    if which == "baseline":
        baseline.write_text("[]", encoding="utf-8")
    elif which == "queue":
        value = json.loads(queue.read_text(encoding="utf-8"))
        value["source"]["baseline_sha256"] = "0" * 64
        queue.write_text(json.dumps(value), encoding="utf-8")
    elif which == "review":
        value = json.loads(review.read_text(encoding="utf-8"))
        value["baseline_sha256"] = "0" * 64
        review.write_text(json.dumps(value), encoding="utf-8")
    else:
        value = json.loads(source.read_text(encoding="utf-8"))
        value["source"]["baseline_sha256"] = "0" * 64
        source.write_text(json.dumps(value), encoding="utf-8")
    monkeypatch.setattr(sys, "argv", _argv(baseline, review, queue, source, calamari, out))

    with pytest.raises(ValueError, match="hash"):
        subject.main()


def test_main_refuses_to_overwrite_existing_output(tmp_path, monkeypatch):
    baseline, review, queue, source, calamari = _write_inputs(tmp_path)
    out = tmp_path / "menneskeark.html"
    out.write_text("old", encoding="utf-8")
    monkeypatch.setattr(sys, "argv", _argv(baseline, review, queue, source, calamari, out))

    with pytest.raises(FileExistsError):
        subject.main()


def test_main_accepts_task1_review_ledger_with_matching_baseline_hash(tmp_path, monkeypatch):
    baseline, review, queue, source, calamari = _write_inputs(tmp_path)
    out = tmp_path / "menneskeark.html"
    value = json.loads(review.read_text(encoding="utf-8"))
    value.pop("source")
    value["entries"][0]["baseline_locator"] = {"pages": "498", "local_id": None}
    review.write_text(json.dumps(value), encoding="utf-8")
    monkeypatch.setattr(sys, "argv", _argv(baseline, review, queue, source, calamari, out))

    assert subject.main() == 0


def test_main_reembeds_a_source_validated_choice_export_with_browser_fields(
    tmp_path, monkeypatch
):
    baseline, review, queue, source, calamari = _write_inputs(tmp_path)
    out = tmp_path / "menneskeark.html"
    source_value = json.loads(source.read_text(encoding="utf-8"))["source"]
    choice = {
        "baseline_record_key": "record-1",
        "outcome": "human_selected_candidate",
        "candidate_id": "Stamme.Volrad",
        "decided_at": "2026-08-06T12:00:00Z",
        "review_status": "unreviewed",
        "baseline_locator": {"pages": "498", "local_id": None},
        "review_note": "Bevares ikke i den genindlejrede browser-kladde.",
    }
    review.write_text(json.dumps({
        "schema_version": 1,
        "source": source_value,
        "baseline_sha256": source_value["baseline_sha256"],
        "exported_at": "2026-08-06T12:01:00Z",
        "entries": [choice],
    }), encoding="utf-8")
    monkeypatch.setattr(subject.segment, "_segment_1939_v2", lambda *_: [{
        "lokal_id": "Stamme.Volrad", "sider": "3", "raw_text": "Hr. Volrad",
    }])
    monkeypatch.setattr(sys, "argv", _argv(baseline, review, queue, source, calamari, out))

    assert subject.main() == 0

    payload = json.loads(re.search(
        r"const DATA=(.*?);\n\(function \(global\)", out.read_text(encoding="utf-8")
    ).group(1))
    assert payload["records"][0]["decision"] == {
        "baseline_record_key": "record-1",
        "outcome": "human_selected_candidate",
        "candidate_id": "Stamme.Volrad",
        "decided_at": "2026-08-06T12:00:00Z",
    }


def test_main_synthesizes_unreviewed_decisions_for_every_untouched_choice_export_record(
    tmp_path, monkeypatch
):
    """Generator parity: every baseline key gets a model decision.

    Regression test for the browser round-trip bug: exportDraft
    (human_review_1939_ui.js) has always fallen back to
    {baseline_record_key, draft: true} for a record with no decision. In the
    legacy flow this fallback never fired because the review template always
    supplied review_status: unreviewed + baseline_locator for every record.
    The choice-export-embedding generator path must supply the same
    unreviewed+locator decision for untouched records so the browser's
    fallback never fires and the locator survives every export/import cycle.
    """
    baseline, review, queue, source, calamari = _write_inputs(tmp_path)
    out = tmp_path / "menneskeark.html"
    baseline_value = json.loads(baseline.read_text(encoding="utf-8")) + [{
        "record_key": "record-2", "navn": "Anden", "sider": "499",
        "_v2_lokal_id": "Stamme.Anden",
    }]
    baseline.write_text(json.dumps(baseline_value), encoding="utf-8")
    source_value = _source(
        baseline.read_bytes(), calamari.read_bytes(), calamari.with_name("raw.txt").read_bytes(),
    )
    source.write_text(json.dumps({"schema_version": 1, "source": source_value}), encoding="utf-8")
    queue.write_text(json.dumps({"schema_version": 1, "source": source_value, "entries": [
        {"baseline_record_key": "record-1", "queue_class": "human_required",
         "reason_code": "no_candidate", "reason_da": "ingen kandidat"},
        {"baseline_record_key": "record-2", "queue_class": "human_required",
         "reason_code": "no_candidate", "reason_da": "ingen kandidat"},
    ]}), encoding="utf-8")
    review.write_text(json.dumps({
        "schema_version": 1,
        "source": source_value,
        "baseline_sha256": source_value["baseline_sha256"],
        "exported_at": "2026-08-06T12:01:00Z",
        "entries": [
            {"baseline_record_key": "record-1", "outcome": "undecidable",
             "decided_at": "2026-08-06T12:00:00Z", "reason": "uklar kilde"},
            # The browser's actual exportDraft fallback shape for an
            # untouched record — never a decision, must still validate.
            {"baseline_record_key": "record-2", "draft": True},
        ],
    }), encoding="utf-8")
    monkeypatch.setattr(subject.segment, "_segment_1939_v2", lambda *_: [{
        "lokal_id": "Stamme.Volrad", "sider": "3", "raw_text": "Hr. Volrad",
    }])
    monkeypatch.setattr(sys, "argv", _argv(baseline, review, queue, source, calamari, out))

    assert subject.main() == 0

    payload = json.loads(re.search(
        r"const DATA=(.*?);\n\(function \(global\)", out.read_text(encoding="utf-8")
    ).group(1))
    by_key = {record["record_key"]: record for record in payload["records"]}
    assert by_key["record-1"]["decision"] == {
        "baseline_record_key": "record-1",
        "outcome": "undecidable",
        "decided_at": "2026-08-06T12:00:00Z",
        "reason": "uklar kilde",
    }
    assert by_key["record-2"]["decision"] == {
        "baseline_record_key": "record-2",
        "review_status": "unreviewed",
        "baseline_locator": {"pages": "499", "local_id": "Stamme.Anden"},
    }


@pytest.mark.parametrize(
    ("choice", "message"),
    [
        (
            {"outcome": "human_selected_candidate", "candidate_id": "Stamme.Volrad"},
            "decided_at",
        ),
        (
            {
                "outcome": "human_selected_candidate",
                "candidate_id": "ukendt-kandidat",
                "decided_at": "2026-08-06T12:00:00Z",
            },
            "findes ikke blandt postens aktuelle kandidater",
        ),
        (
            {
                "outcome": "possible_duplicate",
                "duplicate_of_baseline_record_key": "manglende-record",
                "decided_at": "2026-08-06T12:00:00Z",
            },
            "dubletmål findes ikke",
        ),
    ],
)
def test_main_rejects_browser_invalid_choice_export_before_writing_html(
    tmp_path, monkeypatch, choice, message
):
    baseline, review, queue, source, calamari = _write_inputs(tmp_path)
    out = tmp_path / "menneskeark.html"
    source_value = json.loads(source.read_text(encoding="utf-8"))["source"]
    review.write_text(json.dumps({
        "schema_version": 1,
        "source": source_value,
        "baseline_sha256": source_value["baseline_sha256"],
        "exported_at": "2026-08-06T12:01:00Z",
        "entries": [{"baseline_record_key": "record-1", **choice}],
    }), encoding="utf-8")
    monkeypatch.setattr(subject.segment, "_segment_1939_v2", lambda *_: [{
        "lokal_id": "Stamme.Volrad", "sider": "3", "raw_text": "Hr. Volrad",
    }])
    monkeypatch.setattr(sys, "argv", _argv(baseline, review, queue, source, calamari, out))

    with pytest.raises(ValueError, match=message):
        subject.main()
    assert not out.exists()


def test_main_rejects_choice_export_with_candidate_owned_by_another_record(
    tmp_path, monkeypatch
):
    baseline, review, queue, source, calamari = _write_inputs(tmp_path)
    out = tmp_path / "menneskeark.html"
    baseline_value = json.loads(baseline.read_text(encoding="utf-8")) + [{
        "record_key": "record-2", "navn": "Anden", "sider": "498",
    }]
    baseline.write_text(json.dumps(baseline_value), encoding="utf-8")
    source_value = _source(
        baseline.read_bytes(), calamari.read_bytes(), calamari.with_name("raw.txt").read_bytes(),
    )
    source.write_text(json.dumps({"schema_version": 1, "source": source_value}), encoding="utf-8")
    queue.write_text(json.dumps({"schema_version": 1, "source": source_value, "entries": [
        {"baseline_record_key": "record-1", "queue_class": "human_required",
         "reason_code": "no_candidate", "reason_da": "ingen kandidat"},
        {"baseline_record_key": "record-2", "queue_class": "human_required",
         "reason_code": "no_candidate", "reason_da": "ingen kandidat"},
    ]}), encoding="utf-8")
    review.write_text(json.dumps({
        "schema_version": 1,
        "source": source_value,
        "baseline_sha256": source_value["baseline_sha256"],
        "exported_at": "2026-08-06T12:01:00Z",
        "entries": [
            {"baseline_record_key": key, "outcome": "human_selected_candidate",
             "candidate_id": "Stamme.Volrad", "decided_at": "2026-08-06T12:00:00Z"}
            for key in ("record-1", "record-2")
        ],
    }), encoding="utf-8")
    monkeypatch.setattr(subject.segment, "_segment_1939_v2", lambda *_: [{
        "lokal_id": "Stamme.Volrad", "sider": "3", "raw_text": "Hr. Volrad",
    }])
    monkeypatch.setattr(sys, "argv", _argv(baseline, review, queue, source, calamari, out))

    with pytest.raises(ValueError, match="allerede valgt"):
        subject.main()
    assert not out.exists()


def _embedded_record(key, candidate_id, *, queue_class="human_required",
                     is_audit=False, decision=None, classification=None):
    return {
        "record_key": key,
        "queue_class": queue_class,
        "is_audit": is_audit,
        "candidates": [{"candidate_id": candidate_id}],
        "decision": decision,
        "classification": classification,
    }


def test_embedded_choice_rejects_non_audit_auto_resolved_record_before_html():
    decision = {
        "baseline_record_key": "record-auto",
        "outcome": "human_selected_candidate",
        "candidate_id": "candidate-auto",
        "decided_at": "2026-08-06T12:00:00Z",
    }
    model = {"records": [_embedded_record(
        "record-auto", "candidate-auto", queue_class="auto_resolved",
        decision=decision,
        classification={"queue_class": "auto_resolved", "candidate": {
            "candidate_id": "candidate-auto",
        }},
    )]}

    with pytest.raises(ValueError, match="auto_resolved"):
        subject._validate_embedded_choice_decisions(model, {"record-auto"})


@pytest.mark.parametrize("existing_kind", ["automatic", "accepted_legacy"])
def test_embedded_choice_rejects_candidate_owned_by_existing_decision(existing_kind):
    shared = "shared-candidate"
    choice = {
        "baseline_record_key": "record-choice",
        "outcome": "human_selected_candidate",
        "candidate_id": shared,
        "decided_at": "2026-08-06T12:00:00Z",
    }
    chosen = _embedded_record("record-choice", shared, decision=choice)
    if existing_kind == "automatic":
        existing = _embedded_record(
            "record-existing", shared, queue_class="auto_resolved",
            classification={
                "queue_class": "auto_resolved",
                "candidate": {"candidate_id": shared},
            },
        )
    else:
        existing = _embedded_record("record-existing", shared, decision={
            "baseline_record_key": "record-existing",
            "review_status": "accepteret",
            "candidate_id": shared,
        })

    with pytest.raises(ValueError, match="allerede valgt"):
        subject._validate_embedded_choice_decisions(
            {"records": [chosen, existing]}, {"record-choice"},
        )


def test_main_rejects_choice_export_with_changed_pinned_source(tmp_path, monkeypatch):
    baseline, review, queue, source, calamari = _write_inputs(tmp_path)
    out = tmp_path / "menneskeark.html"
    choice_export = json.loads(review.read_text(encoding="utf-8"))
    choice_export["exported_at"] = "2026-08-06T12:01:00Z"
    choice_export["entries"][0].update(
        outcome="no_candidate_fits", reason="Ingen kandidat passer."
    )
    choice_export["source"]["calamari_sha256"] = "0" * 64
    review.write_text(json.dumps(choice_export), encoding="utf-8")
    monkeypatch.setattr(sys, "argv", _argv(baseline, review, queue, source, calamari, out))

    with pytest.raises(ValueError, match="review source hashes"):
        subject.main()


def test_main_rejects_sourceless_review_with_a_human_decision(tmp_path, monkeypatch):
    baseline, review, queue, source, calamari = _write_inputs(tmp_path)
    out = tmp_path / "menneskeark.html"
    value = json.loads(review.read_text(encoding="utf-8"))
    value.pop("source")
    value["entries"][0].update(review_status="menneskeark", reason="vurderet")
    review.write_text(json.dumps(value), encoding="utf-8")
    monkeypatch.setattr(sys, "argv", _argv(baseline, review, queue, source, calamari, out))

    with pytest.raises(ValueError, match="legacy review"):
        subject.main()


@pytest.mark.parametrize("field", ["calamari_sha256", "raw_ocr_sha256", "pdf_sha256", "profile_version"])
def test_main_rejects_completed_review_with_changed_pinned_source(tmp_path, monkeypatch, field):
    baseline, review, queue, source, calamari = _write_inputs(tmp_path)
    out = tmp_path / "menneskeark.html"
    value = json.loads(review.read_text(encoding="utf-8"))
    value["entries"][0].update(review_status="menneskeark", reason="vurderet")
    value["source"][field] = "x" * 64 if field.endswith("sha256") else "1939-v1"
    review.write_text(json.dumps(value), encoding="utf-8")
    monkeypatch.setattr(sys, "argv", _argv(baseline, review, queue, source, calamari, out))

    with pytest.raises(ValueError, match="review source hashes"):
        subject.main()


def test_main_rejects_review_missing_a_baseline_key(tmp_path, monkeypatch):
    baseline, review, queue, source, calamari = _write_inputs(tmp_path)
    out = tmp_path / "menneskeark.html"
    value = json.loads(review.read_text(encoding="utf-8"))
    value["entries"] = []
    review.write_text(json.dumps(value), encoding="utf-8")
    monkeypatch.setattr(sys, "argv", _argv(baseline, review, queue, source, calamari, out))

    with pytest.raises(ValueError, match="review baseline-dækning"):
        subject.main()


@pytest.mark.parametrize(
    ("field", "value", "message"),
    [
        ("calamari_span", {"char_from": 1, "char_to": 1}, "char_from < char_to"),
        ("raw_excerpt_sha256", "0" * 64, "matcher ikke raw_verbatim_text"),
    ],
)
def test_main_reuses_authoritative_legacy_review_validation(
    tmp_path, monkeypatch, field, value, message
):
    baseline, review, queue, source, calamari = _write_inputs(tmp_path)
    out = tmp_path / "menneskeark.html"
    ledger = json.loads(review.read_text(encoding="utf-8"))
    ledger["entries"][0].update({
        "review_status": "accepteret",
        "candidate_id": "candidate-1",
        "post_index": 0,
        "calamari_span": {"char_from": 0, "char_to": 1},
        "calamari_verbatim_text": "A",
        "pdf_pages": [498],
        "kind": "line_header",
        "raw_char_from": 0,
        "raw_char_to": 1,
        "raw_verbatim_text": "A",
        "raw_excerpt_sha256": hashlib.sha256(b"A").hexdigest(),
    })
    ledger["entries"][0][field] = value
    review.write_text(json.dumps(ledger), encoding="utf-8")
    monkeypatch.setattr(sys, "argv", _argv(baseline, review, queue, source, calamari, out))

    with pytest.raises(ValueError, match=message):
        subject.main()


def test_main_rejects_legacy_duplicate_target_that_is_not_accepted(tmp_path, monkeypatch):
    baseline, review, queue, source, calamari = _write_inputs(tmp_path)
    out = tmp_path / "menneskeark.html"
    baseline_value = [
        {"record_key": "record-1", "navn": "Volrad", "sider": "498"},
        {"record_key": "record-2", "navn": "Anden", "sider": "498"},
    ]
    baseline.write_text(json.dumps(baseline_value), encoding="utf-8")
    source_value = _source(baseline.read_bytes(), calamari.read_bytes())
    source.write_text(json.dumps({"schema_version": 1, "source": source_value}), encoding="utf-8")
    queue.write_text(json.dumps({"schema_version": 1, "source": source_value, "entries": [
        {"baseline_record_key": "record-1", "queue_class": "human_required", "reason_code": "x", "reason_da": "x"},
        {"baseline_record_key": "record-2", "queue_class": "human_required", "reason_code": "x", "reason_da": "x"},
    ]}), encoding="utf-8")
    review.write_text(json.dumps({"schema_version": 1, "source": source_value,
        "baseline_sha256": source_value["baseline_sha256"], "entries": [
            {"baseline_record_key": "record-1", "review_status": "eksplicit_dublet",
             "duplicate_of_baseline_record_key": "record-2"},
            {"baseline_record_key": "record-2", "review_status": "unreviewed"},
        ]}), encoding="utf-8")
    monkeypatch.setattr(sys, "argv", _argv(baseline, review, queue, source, calamari, out))

    with pytest.raises(ValueError, match="accepteret"):
        subject.main()


def test_main_embeds_valid_cross_page_accepted_anchor_for_browser_audit(tmp_path, monkeypatch):
    baseline, review, queue, source, calamari = _write_inputs(tmp_path)
    out = tmp_path / "menneskeark.html"
    raw_text = "Accepteret manuel tekst"
    ledger = json.loads(review.read_text(encoding="utf-8"))
    ledger["entries"][0].update({
        "review_status": "accepteret",
        "candidate_id": "manual-anchor",
        "post_index": 7,
        "calamari_span": {"char_from": 10, "char_to": 20},
        "calamari_verbatim_text": "Accepteret Calamari-tekst",
        "pdf_pages": [700],
        "kind": "manual_cross_page_anchor",
        "raw_char_from": 100,
        "raw_char_to": 123,
        "raw_verbatim_text": raw_text,
        "raw_excerpt_sha256": hashlib.sha256(raw_text.encode("utf-8")).hexdigest(),
    })
    review.write_text(json.dumps(ledger), encoding="utf-8")
    monkeypatch.setattr(subject.segment, "_segment_1939_v2", lambda *_: [{
        "lokal_id": "near-page", "sider": "3", "raw_text": "Nærliggende kandidat",
    }])
    monkeypatch.setattr(sys, "argv", _argv(baseline, review, queue, source, calamari, out))

    assert subject.main() == 0

    payload = json.loads(re.search(
        r"const DATA=(.*?);\n\(function \(global\)", out.read_text(encoding="utf-8")
    ).group(1))
    record = payload["records"][0]
    assert [candidate["candidate_id"] for candidate in record["candidates"]] == [
        "manual-anchor", "near-page",
    ]
    attached = record["candidates"][0]
    assert attached["rank_reason"] == "accepteret_review_evidens"
    assert attached["raw_text"] == raw_text
    assert attached["accepted_review_details"] == ledger["entries"][0]


def test_pdf_pages_come_from_the_calibrated_map_not_from_counting():
    """Calamari skips plate pages, so counting drifts up to 17 pages."""
    assert subject._pdf_page_for(1, 496) == 496
    assert subject._pdf_page_for(50, 496) == 545
    # PDF 546 is a plate page absent from Calamari: page 51 is already 547.
    assert subject._pdf_page_for(51, 496) == 547
    assert subject._pdf_page_for(63, 496) == 575
    assert subject._pdf_page_for(86, 496) == 598


def test_pdf_page_translation_counts_when_the_origin_is_not_the_r6_map():
    """No measured map exists for another page origin, so counting is all there is."""
    assert subject._pdf_page_for(63, 11) == 73


def test_main_refuses_a_1939_v2_run_with_a_first_page_the_map_disagrees_with(
    tmp_path, monkeypatch
):
    baseline, review, queue, source, calamari = _write_inputs(tmp_path)
    out = tmp_path / "menneskeark.html"
    argv = _argv(baseline, review, queue, source, calamari, out)
    argv[argv.index("--calamari-first-pdf-page") + 1] = "495"
    monkeypatch.setattr(sys, "argv", argv)

    with pytest.raises(ValueError, match="CALAMARI_R6_TO_PDF_V1"):
        subject.main()
    assert not out.exists()


def test_candidate_from_post_translates_a_late_page_with_the_map():
    candidate = subject._candidate_from_post(
        {"lokal_id": "III.Sjette.V.1", "sider": "63", "raw_text": "Heinrich"},
        496, "1939-v2", 0,
    )

    assert candidate["calamari_pages"] == [63]
    assert candidate["pdf_pages"] == [575]
