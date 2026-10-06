import hashlib
import json
import sys
from pathlib import Path

import pytest

import identity_control_sheet as ics
from decision_sheet_core import SheetError

CTL = "c" * 8 + "-0000-4000-8000-" + "0" * 12
P1, P2 = "11111111-1111-4111-8111-111111111111", "22222222-2222-4222-8222-222222222222"
K1 = "33333333-3333-4333-8333-333333333333"
C1, C2 = "44444444-4444-4444-8444-444444444444", "55555555-5555-4555-8555-555555555555"
RUN = "66666666-6666-4666-8666-666666666666"


def rows():
    return {"control_run_id": CTL, "candidate_run_id": RUN, "items": [
        {"kind": "identity", "sample": True, "source_persona_id": P1, "version": 0, "record_key": "I-1",
         "principal_record_key": "I-1", "marriage_ordinal": 1, "name": "Mage Et",
         "display": [{"position": 1, "candidate_id": C2, "person_id": 9, "person_name": "Anden", "born": None, "died": None,
                      "titles": [], "own_post_key": None},
                     {"position": 2, "candidate_id": C1, "person_id": 7, "person_name": "Mage Et", "born": "1801", "died": None,
                      "titles": ["kammerherre"], "own_post_key": None}]},
        {"kind": "identity", "sample": False, "source_persona_id": P2, "version": 0, "record_key": "I-2",
         "principal_record_key": "I-2", "marriage_ordinal": 2, "name": "Mage To", "reason": "count_mismatch", "run_id": RUN,
         "candidates": [{"rank": 1, "candidate_id": C1, "person_id": 7, "person_name": "Mage To", "born": None, "died": None,
                         "titles": [], "own_post_key": None, "score": 0.9, "tier": "review", "signals": ["name", "family_partner"],
                         "family_id": 30, "ordinal": 2}]},
        {"kind": "relation", "sample": True, "interpretation_key": K1, "version": 1, "record_key": "I-3",
         "predicate": "relation.child", "families": [{"position": 1, "family_id": 40, "counterpart_name": "Barn", "counterpart_post_key": "I-9"}]},
    ]}


def ark(tokens):
    text = ics.render_sheet(rows())
    for tok in tokens:
        text = text.replace(" : _", f" : {tok}", 1)
    return text


def sql_for(tokens):
    r = rows()
    text = ark(tokens)
    return ics.decision_sql(ics.parse_sheet(text), r, sheet_sha256="a" * 64, rows_sha256="b" * 64)


def test_stikproeve_er_blind_og_i_serverens_orden():
    text = ics.render_sheet(rows())
    blok = text.split("D " + P1)[0].split("# POST I-1")[1]
    assert "score" not in blok and "auto" not in blok and "familie" not in blok
    assert blok.index("1: Anden") < blok.index("2: Mage Et")


def test_uoverensstemmelse_viser_grund_og_signaler():
    text = ics.render_sheet(rows())
    assert "grund: count_mismatch" in text and "score 0.9" in text and "familie 30 nr 2" in text


def test_sql_forsegler_foerst_og_evaluerer_sidst():
    sql = sql_for(["2", "1", "1"])
    lines = [l for l in sql.splitlines() if "red_" in l]
    assert "red_seal_identity_control_run" in lines[0]
    assert "red_evaluate_identity_control_run" in lines[-1]


def test_stikproeve_same_sender_null_og_visningsplads():
    sql = sql_for(["2", "1", "1"])
    s1 = next(l for l in sql.splitlines() if P1 in l)
    assert "'same', NULL" in s1 and '"display_position": 2' in s1 and f'"control_run_id": "{CTL}"' in s1
    assert "candidate_id" not in s1


def test_p_paa_stikproeve_har_ingen_visningsplads():
    sql = sql_for(["P 7", "1", "1"])
    s1 = next(l for l in sql.splitlines() if P1 in l)
    assert "'same', 7" in s1 and "display_position" not in s1 and f'"control_run_id": "{CTL}"' in s1


def test_uoverensstemmelse_bruger_kandidat_id_uden_kontrol():
    sql = sql_for(["2", "1", "1"])
    s2 = next(l for l in sql.splitlines() if P2 in l)
    assert C1 in s2 and RUN in s2 and "control_run_id" not in s2


def test_relationslinje_sample():
    sql = sql_for(["2", "1", "1"])
    r = next(l for l in sql.splitlines() if K1 in l)
    assert "red_afgoer_relation_interpretation" in r and "'same', NULL" in r and '"display_position": 1' in r


def test_relationslinje_afviser_x():
    with pytest.raises(SheetError, match="SHEET_TOKEN_INVALID"):
        ics.parse_sheet(ark(["2", "1", "X"]))


def test_cli_laeser_arket_én_gang(tmp_path, monkeypatch):
    rf = tmp_path / "rows.json"; rf.write_text(json.dumps(rows()), encoding="utf-8")
    af = tmp_path / "ark.txt"; godkendt = ark(["2", "1", "1"]); af.write_text(godkendt, encoding="utf-8")
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


def many(n_sample, n_rest):
    base = rows()
    s, d = base["items"][0], base["items"][1]
    items = [{**s, "source_persona_id": f"{i:08x}-1111-4111-8111-111111111111", "record_key": f"S-{i:03d}"}
             for i in range(n_sample)]
    items += [{**d, "source_persona_id": f"{i:08x}-2222-4222-8222-222222222222", "record_key": f"A-{i:03d}"}
              for i in range(n_rest)]
    return {**base, "items": items}


def test_hele_stikproeven_i_ark_1_og_kun_ark_1_forsegler():
    parts = ics.split_rows(many(12, 100))
    assert [p["part"] for p in parts] == [1, 2] and [p["seal"] for p in parts] == [True, False]
    assert sum(it["sample"] for it in parts[0]["items"]) == 12 and len(parts[0]["items"]) == 80
    assert not any(it["sample"] for it in parts[1]["items"]) and len(parts[1]["items"]) == 32


def test_overloebsark_forsegler_og_evaluerer_ikke():
    part = ics.split_rows(many(12, 100))[1]
    text = ics.render_sheet(part).replace(" : _", " : U")
    sql = ics.decision_sql(ics.parse_sheet(text), part, sheet_sha256="a" * 64, rows_sha256="b" * 64)
    assert "# Ark 2 af 2" in text
    assert "red_seal_identity_control_run" not in sql and "red_evaluate_identity_control_run" not in sql


def test_stikproeve_over_graensen_afvises():
    with pytest.raises(SheetError, match="SHEET_SAMPLE_TOO_LARGE"):
        ics.split_rows(many(81, 0))


def test_overloebsark_med_stikproeve_afvises():
    part = dict(ics.split_rows(many(12, 100))[1])
    part["items"] = part["items"] + many(1, 0)["items"]
    with pytest.raises(SheetError, match="SHEET_PART_INVALID"):
        ics.decision_sql([], part, sheet_sha256="a" * 64, rows_sha256="b" * 64)
