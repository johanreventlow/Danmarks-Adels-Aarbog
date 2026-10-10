import hashlib
import json
import sys
from copy import deepcopy
from pathlib import Path

import pytest

import identity_control_sheet as ics
from decision_sheet_core import SheetError

CTL = "c" * 8 + "-0000-4000-8000-" + "0" * 12
P1, P2 = "11111111-1111-4111-8111-111111111111", "22222222-2222-4222-8222-222222222222"
K1 = "33333333-3333-4333-8333-333333333333"
C1, C2 = "44444444-4444-4444-8444-444444444444", "55555555-5555-4555-8555-555555555555"
RUN = "66666666-6666-4666-8666-666666666666"
O1 = "77777777-7777-4777-8777-777777777777"
TEKST = "Gift 1725 med Anna Berg, f. 1705."


def rows():
    return {"control_run_id": CTL, "candidate_run_id": RUN, "k_random": 20, "items": [
        {"kind": "identity", "stratum": "navnefaelle", "source_persona_id": P1, "version": 0, "record_key": "I-1", "pages": "12",
         "principal": {"name": "Hoved Et", "born": "1700", "died": "1760"}, "marriage_ordinal": 1,
         "observation_id": O1, "text_sha256": "e" * 64, "text": TEKST, "span": [14, 23],
         "display": [{"position": 1, "candidate_id": C2, "name": "Anna Berg", "born": "1710", "died": "1780",
                      "titles": [], "own_post_key": None, "parents": []},
                     {"position": 2, "candidate_id": C1, "name": "Anna Berg", "born": "1705", "died": "1770",
                      "titles": ["hofdame"], "own_post_key": "II-9",
                      "parents": [{"name": "Carl Berg", "born": "1670", "died": "1730"},
                                  {"name": "Maria Berg", "born": None, "died": None}]}]},
        {"kind": "identity", "stratum": "single_family", "source_persona_id": P2, "version": 0, "record_key": "I-2", "pages": "13–14",
         "principal": {"name": "Hoved To", "born": None, "died": "1801"}, "marriage_ordinal": 2,
         "observation_id": O1, "text_sha256": "f" * 64, "text": "Gift 2° med Bodil.", "span": None,
         "display": [{"position": 1, "candidate_id": C1, "name": "Bodil", "born": None, "died": None,
                      "titles": [], "own_post_key": None, "parents": []}]},
        {"kind": "parent", "interpretation_key": K1, "version": 1, "record_key": "I-17", "pages": "40",
         "principal": {"name": "Barn Et", "born": "1730", "died": "1790"}, "observation_id": O1, "text_sha256": "d" * 64,
         "text": "søn af Carl Berg.", "family_id": 11,
         "partners": [{"name": "Carl Berg", "born": "1670", "died": "1730", "own_post_key": "I-10", "counterpart": True},
                      {"name": "Maria Berg", "born": None, "died": None, "own_post_key": None, "counterpart": False}]},
    ]}


def ark(tokens, r=None):
    text = ics.render_sheet(r or rows())
    for tok in tokens:
        text = text.replace(" : _", f" : {tok}", 1)
    return text


def sql_for(tokens):
    return ics.decision_sql(ics.parse_sheet(ark(tokens)), rows(), sheet_sha256="a" * 64, rows_sha256="b" * 64)


def test_aegtefaellekort_viser_hovedperson_klausul_spaend_og_foraeldre():
    text = ics.render_sheet(rows())
    assert "## ÆGTEFÆLLEKORT 1/2 · post I-1 · PDF-side 12 · ægteskab nr. 1" in text
    assert "#   Hovedperson: Hoved Et (1700–1760)" in text
    assert "#   Bogen: »Gift 1725 med [[Anna Berg]], f. 1705.«" in text
    assert "#   2: Anna Berg (1705–1770)  · hofdame  · egen post II-9" in text
    assert "#        forældre: Carl Berg (1670–1730), Maria Berg (?–?)" in text


def test_aegtefaellekort_er_blinde():
    blok = ics.render_sheet(rows()).split("D " + P1)[0]
    for ord_ in ("score", "auto", "familie 11", "family", C1, C2, "person 7", "navnefaelle"):
        assert ord_ not in blok


def test_kort_uden_spaend_og_med_en_kandidat():
    text = ics.render_sheet(rows())
    assert "#   Bogen: »Gift 2° med Bodil.«" in text
    assert "#   Hovedperson: Hoved To (?–1801)" in text and "PDF-side 13–14" in text


def test_klausul_normaliseres_til_en_linje():
    r = rows()
    r["items"][1]["text"] = "Gift 2°\nD med  Bodil #x\nR y"
    text = ics.render_sheet(r)
    assert "#   Bogen: »Gift 2° D med Bodil #x R y«" in text
    assert sum(1 for l in text.splitlines() if l.startswith("D ")) == 2
    assert sum(1 for l in text.splitlines() if l.startswith("R ")) == 1


def test_foraeldrekort_viser_familie_modpart_og_udsagn():
    text = ics.render_sheet(rows())
    assert "## FORÆLDREKORT 1/1 · post I-17 · PDF-side 40" in text
    assert "#   Familie: Carl Berg (1670–1730) · egen post I-10 ← modpart; Maria Berg (?–?)" in text
    assert "#   Udsagn: bogen siger, at hovedpersonen er barn af denne familie." in text
    assert f"R {K1} 1 : _" in text


def test_aegtefaellekort_foer_foraeldrekort():
    text = ics.render_sheet(rows())
    assert text.index("D " + P1) < text.index("D " + P2) < text.index("R " + K1)


@pytest.mark.parametrize("tokens", [["1", "X", "A"], ["2", "N", "R"], ["U", "1", "F"], ["1", "1", "U"]])
def test_gyldige_tokens(tokens):
    assert [l.tok for l in ics.parse_sheet(ark(tokens))] == tokens


@pytest.mark.parametrize("tokens", [["P 7", "1", "A"], ["A", "1", "A"], ["1", "1", "1"], ["4", "1", "A"]])
def test_ugyldige_tokens(tokens):
    with pytest.raises(SheetError, match="SHEET_TOKEN_INVALID"):
        ics.parse_sheet(ark(tokens))


def test_uafgjort_afvises():
    with pytest.raises(SheetError, match="SHEET_UNDECIDED"):
        ics.parse_sheet(ark(["1", "1"]))


def test_rettet_kontekstlinje_afvises():
    text = ark(["1", "1", "A"]).replace("Hoved Et", "Hoved Andet", 1)
    with pytest.raises(SheetError, match="SHEET_RENDER_MISMATCH"):
        ics.check_render(text, rows())


def test_to_transaktioner_identitet_foerst():
    sql = sql_for(["2", "1", "A"])
    t1, t2 = sql.split("COMMIT;")[:2]
    assert t1.index("red_seal_identity_control_run") < t1.index("red_afgoer_source_persona") < t1.index("red_evaluate_identity_control_run")
    assert "red_afgoer_relation_interpretation" not in t1 and "red_classify_parent_card" not in t1
    assert "red_afgoer_relation_interpretation" in t2 and "red_seal" not in t2 and "red_evaluate" not in t2


def test_aegtefaelle_sender_null_og_visningsplads():
    sql = sql_for(["2", "X", "A"])
    s1 = next(l for l in sql.splitlines() if P1 in l)
    assert "'same', NULL" in s1 and '"display_position": 2' in s1 and f'"control_run_id": "{CTL}"' in s1
    s2 = next(l for l in sql.splitlines() if P2 in l)
    assert "'different', NULL" in s2 and "display_position" not in s2


def test_foraelder_a_lader_serveren_oploese_familien():
    r = next(l for l in sql_for(["1", "1", "A"]).splitlines() if K1 in l)
    assert "red_afgoer_relation_interpretation" in r and "'same', NULL" in r and f'"control_run_id": "{CTL}"' in r
    assert "display_position" not in r and "11" not in r.split("'same'")[1].split(",")[1]


def test_foraelder_r_og_f():
    r = next(l for l in sql_for(["1", "1", "R"]).splitlines() if K1 in l)
    assert "'rejected', NULL" in r
    f = next(l for l in sql_for(["1", "1", "F"]).splitlines() if K1 in l)
    assert f"red_classify_parent_card('{CTL}'::uuid, '{K1}'::uuid, 1, 'F'," in f


def test_foraelder_u_skriver_intet():
    sql = sql_for(["1", "1", "U"])
    assert K1 not in sql
    t2 = sql.split("COMMIT;")[1]
    assert "<> 0 THEN RAISE EXCEPTION 'DECISION_COUNT_MISMATCH'" in t2


def test_cli_laeser_arket_én_gang(tmp_path, monkeypatch, capsys):
    rf = tmp_path / "rows.json"; rf.write_text(json.dumps(rows()), encoding="utf-8")
    af = tmp_path / "ark.txt"; af.write_text(ark(["2", "1", "A"]), encoding="utf-8")
    sha = hashlib.sha256(af.read_bytes()).hexdigest()
    ægte = Path.read_bytes
    læst = {"n": 0}

    def bytes_(self):
        if self == af:
            læst["n"] += 1
            if læst["n"] > 1:
                return ark(["1", "1", "U"]).encode("utf-8")
        return ægte(self)

    monkeypatch.setattr(Path, "read_bytes", bytes_)
    monkeypatch.setattr(sys, "argv", ["x", "sql", "--sheet", str(af), "--approved-sha256", sha, "--rows", str(rf),
                                      "--expect-rows-sha256", hashlib.sha256(rf.read_bytes()).hexdigest(),
                                      "--out", str(tmp_path / "d.sql")])
    assert ics.main() == 0 and læst["n"] == 1
    assert '"display_position": 2' in (tmp_path / "d.sql").read_text(encoding="utf-8")


def test_render_cli_taeller_kort(tmp_path, monkeypatch, capsys):
    rf = tmp_path / "rows.json"; rf.write_text(json.dumps(rows()), encoding="utf-8")
    monkeypatch.setattr(sys, "argv", ["x", "render", "--rows", str(rf), "--out", str(tmp_path / "ark.txt")])
    assert ics.main() == 0
    out = capsys.readouterr().out
    assert "ARK_OK aegtefaellekort=2 foraeldrekort=1 navnefaeller=1" in out
    assert (tmp_path / "ark.txt").stat().st_mode & 0o777 == 0o600
