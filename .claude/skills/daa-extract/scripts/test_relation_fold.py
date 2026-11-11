"""Trin 6d-3: Python-tvillingen til private.relation_ordered_windows(text, raw, text_form) — samme fælles tilfælde
som SQL-testen (tests/fixtures/relation-fold-cases.json). Kun opdigtede tekster."""
import json
from pathlib import Path

import pytest

import relation_persona_extract_v2 as v2

FIXTURE = Path(__file__).resolve().parents[4] / "tests" / "fixtures" / "relation-fold-cases.json"


def test_fold_fixture():
    cases = json.loads(FIXTURE.read_text(encoding="utf-8"))
    assert cases, "fixturen er tom"
    for c in cases:
        w = v2.windows(c["text"], c["raw"], c["text_form"])
        if c["w_from"] is None:
            assert len(w) != 1, c["id"]
        else:
            assert w == [(c["w_from"], c["w_to"])], c["id"]


def test_folded_er_default_og_uaendret():
    t = "Gift 1890 med Ida Dal, f. 1801."
    assert v2.windows(t, "Gift med Ida Dal") == v2.windows(t, "Gift med Ida Dal", "folded") == [(0, 21)]
    # rå tekst med orddeling taber vinduet i 'folded' (i dag) men finder det i 'raw'
    r = "Gift 1890 med Ida Bran-\ndenburg, f. 1801."
    assert v2.windows(r, "Gift med Ida Brandenburg", "folded") == []
    assert v2.windows(r, "Gift med Ida Brandenburg", "raw") == [(0, 31)]


def test_ukendt_tekstform_afvises():
    with pytest.raises(ValueError):
        v2.windows("a", "a", "xyz")
