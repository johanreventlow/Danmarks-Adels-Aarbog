import json
import re
import sys

import make_human_review_1939 as subject


def test_pages_expands_ranges_and_rejects_malformed_values():
    assert subject._pages("496-498") == [496, 497, 498]
    assert subject._pages("498") == [498]
    assert subject._pages("498-496") == []
    assert subject._pages("side 498") == []


def test_main_shows_candidates_on_translated_pdf_pages(tmp_path, monkeypatch):
    baseline = tmp_path / "baseline.json"
    review = tmp_path / "review.json"
    calamari = tmp_path / "calamari.txt"
    out = tmp_path / "menneskeark.html"
    baseline.write_text(json.dumps([{
        "record_key": "record-1", "navn": "Volrad", "sider": "498",
    }]), encoding="utf-8")
    review.write_text(json.dumps({"entries": [{
        "baseline_record_key": "record-1", "review_status": "unreviewed",
    }]}), encoding="utf-8")
    calamari.write_text("### PAGE 0003 ###\nVolrad", encoding="utf-8")
    monkeypatch.setattr(subject.segment, "_segment_1939_v2", lambda *_: [{
        "lokal_id": "Stamme.Volrad", "sider": "3", "raw_text": "Hr. Volrad",
    }])
    monkeypatch.setattr(sys, "argv", ["make_human_review_1939.py",
        "--baseline", str(baseline), "--review", str(review),
        "--calamari", str(calamari), "--calamari-first-pdf-page", "496",
        "--out", str(out),
    ])

    assert subject.main() == 0

    payload = json.loads(re.search(
        r"const DATA=(.*?);\nlet rows=", out.read_text(encoding="utf-8")
    ).group(1))
    assert payload["rows"][0]["candidates"] == [{
        "lokal_id": "Stamme.Volrad",
        "sider": "498",
        "calamari_sider": "3",
        "raw_text": "Hr. Volrad",
    }]
