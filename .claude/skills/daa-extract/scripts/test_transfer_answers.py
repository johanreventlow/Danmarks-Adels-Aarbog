import json
import re
import subprocess
import sys
from pathlib import Path

import pytest

import transfer_answers as ta
from decision_sheet_core import SheetError

OLD_P1 = "11111111-1111-4111-8111-111111111111"
OLD_P2 = "12121212-1212-4121-8121-121212121212"
NEW_P1 = "21111111-1111-4111-8111-111111111111"
NEW_P2 = "22121212-1212-4121-8121-121212121212"
K1 = "33333333-3333-4333-8333-333333333333"
K2 = "34343434-3434-4343-8343-343434343434"
OLD_I1 = "44444444-4444-4444-8444-444444444444"   # v1-arkets tilfældige versions-id
UUID = re.compile(r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}")


def keymaps(tmp_path, extra_old=(), extra_new=()):
    old = [f"{OLD_P1}|persona:1:aa-1#rel-1", f"{OLD_P2}|persona:1:bb-2#rel-1", f"{OLD_I1}|fortolkning:{K1}#2",
           "55555555-5555-4555-8555-555555555555|batch", "56565656-5656-4565-8565-565656565656|batch", *extra_old]
    new = [f"{NEW_P1}|persona:1:aa-1#rel-1", f"{NEW_P2}|persona:1:bb-2#rel-1", *extra_new]
    po, pn = tmp_path / "old.km", tmp_path / "new.km"
    po.write_text("\n".join(old) + "\n", encoding="utf-8"); pn.write_text("\n".join(new) + "\n", encoding="utf-8")
    return ta.load_keymap(po), ta.load_keymap(pn)


def spouse_rows(p1, cand=10):
    return {"contract": "spouse-exception-rows-v2", "s_rows": [{"source_persona_id": p1, "candidate_person_id": cand}], "o_rows": []}


def run(kind, old_sheet, new_sheet, old_rows, new_rows, kms, dropouts=()):
    return ta.transfer(kind, old_sheet, new_sheet, old_rows, new_rows, kms[0], kms[1], set(dropouts))


def spouse_sheets(old_tok="S", old_o=f"O {K1} 2 1/2 : F", new_o=f"O {K1} 2 1/2 : B"):
    old = f"# S-linje\n#   Bogen: »Bo Beta«\nS {OLD_P1} 0 : {old_tok}\n\n{old_o}\n"
    new = f"# S-linje\n#   Bogen: »Bo Beta«\nS {NEW_P1} 0 : S\n\n{new_o}\n"
    return old, new


def test_spouse_transfers_via_keys(tmp_path):
    old, new = spouse_sheets(old_tok="A # anden person")
    r = run("spouse", old, new, spouse_rows(OLD_P1), spouse_rows(NEW_P1), keymaps(tmp_path))
    assert f"S {NEW_P1} 0 : A # anden person" in r.sheet and f"O {K1} 2 1/2 : F" in r.sheet
    assert (r.transferred, r.dropouts, r.changed) == (2, 0, 0)


def test_spouse_rank_answer_to_other_person_stops(tmp_path):
    old, new = spouse_sheets()
    with pytest.raises(SheetError, match="^ANSWER_PERSON_MOVED 1$"):
        run("spouse", old, new, spouse_rows(OLD_P1, 10), spouse_rows(NEW_P1, 11), keymaps(tmp_path))
    r = run("spouse", old, new, spouse_rows(OLD_P1, 10), spouse_rows(NEW_P1, 10), keymaps(tmp_path))
    assert f"S {NEW_P1} 0 : S" in r.sheet


def test_answer_without_target_and_target_without_answer_stop(tmp_path):
    old = f"S {OLD_P1} 0 : U\nS {OLD_P2} 0 : U\n"
    new = f"S {NEW_P1} 0 : S\n"
    with pytest.raises(SheetError, match="^ANSWER_NO_TARGET 2$"):
        run("spouse", old, new, spouse_rows(OLD_P1), spouse_rows(NEW_P1), keymaps(tmp_path))
    with pytest.raises(SheetError, match="^ANSWER_NO_SOURCE 2$"):
        run("spouse", f"S {OLD_P1} 0 : U\n", f"S {NEW_P1} 0 : S\nS {NEW_P2} 0 : S\n", spouse_rows(OLD_P1), spouse_rows(NEW_P1),
            keymaps(tmp_path))


def test_expected_dropouts_are_counted(tmp_path):
    r = run("spouse", f"S {OLD_P1} 0 : U\nS {OLD_P2} 0 : U\n", f"S {NEW_P1} 0 : S\n", spouse_rows(OLD_P1), spouse_rows(NEW_P1),
            keymaps(tmp_path), dropouts={"persona:1:bb-2#rel-1"})
    assert (r.transferred, r.dropouts) == (1, 1)


def test_version_changed_stops(tmp_path):
    old, new = spouse_sheets(old_tok="U", new_o=f"O {K1} 3 1/2 : B")
    with pytest.raises(SheetError, match="^ANSWER_VERSION_CHANGED 2$"):
        run("spouse", old, new, spouse_rows(OLD_P1), spouse_rows(NEW_P1), keymaps(tmp_path))


def test_old_v1_o_grammar_is_translated(tmp_path):
    old, new = spouse_sheets(old_tok="U", old_o=f"O {OLD_I1} 1/2 : F")
    r = run("spouse", old, new, spouse_rows(OLD_P1), spouse_rows(NEW_P1), keymaps(tmp_path))
    assert f"O {K1} 2 1/2 : F" in r.sheet


def test_changed_context_line_is_marked(tmp_path):
    old, new = spouse_sheets(old_tok="U")
    new = new.replace("»Bo Beta«", "»Bo Betha«")
    r = run("spouse", old, new, spouse_rows(OLD_P1), spouse_rows(NEW_P1), keymaps(tmp_path))
    assert r.changed == 1
    assert "~ - #   Bogen: »Bo Beta«" in r.report and "~ + #   Bogen: »Bo Betha«" in r.report
    assert f"= S persona:1:aa-1#rel-1 0 : U" in r.report and OLD_P1 not in r.report and NEW_P1 not in r.report


def control_rows(name="Ea Eta", fam=7):
    return {"items": [{"kind": "parent", "interpretation_key": K2, "version": 1, "family_id": fam,
                       "partners": [{"name": "X", "born": 1, "died": 2, "own_post_key": None, "counterpart": False},
                                    {"name": name, "born": 3, "died": 4, "own_post_key": "p-1", "counterpart": True}]}]}


def test_control_transfers_r_and_leaves_d_blank(tmp_path):
    old = f"D {OLD_P1} 0 : 2\nR {K2} 1 : A\n"
    new = f"D {NEW_P1} 0 : _\nR {K2} 1 : _\n"
    r = run("control", old, new, control_rows(), control_rows(), keymaps(tmp_path))
    assert f"D {NEW_P1} 0 : _" in r.sheet and f"R {K2} 1 : A" in r.sheet and r.transferred == 1


def test_control_accept_with_other_counterpart_stops(tmp_path):
    with pytest.raises(SheetError, match="^ANSWER_PERSON_MOVED 1$"):
        run("control", f"R {K2} 1 : A\n", f"R {K2} 1 : _\n", control_rows(), control_rows(name="Fa Feta"), keymaps(tmp_path))


def details(p, partner=9, cand=10):
    return [{"persona": {"source_persona_id": p, "version": 0}, "principal_partners": [{"person_id": partner}],
             "candidates": [{"rank": 1, "person_id": cand}]}]


def test_queue_same_person_must_keep_its_place(tmp_path):
    old, new = f"Q {OLD_P1} 0 : same 9 # partner\n", f"Q {NEW_P1} 0 : _ # \n"
    r = run("queue", old, new, details(OLD_P1), details(NEW_P1), keymaps(tmp_path))
    assert f"Q {NEW_P1} 0 : same 9 # partner" in r.sheet
    with pytest.raises(SheetError, match="^ANSWER_PERSON_MOVED 1$"):
        run("queue", old, new, details(OLD_P1), details(NEW_P1, partner=8, cand=9), keymaps(tmp_path))


def test_marriage_s_uses_proposal_partner(tmp_path, monkeypatch):
    monkeypatch.setitem(ta.PROPOSE, "marriage", lambda rows, key, navn: {"a": 5, "b": 6}[rows["who"]])
    old, new = f"M {K1} 1 : S # ok\nM {K2} 1 : U\n", f"M {K1} 1 : S\nM {K2} 1 : S\n"
    r = run("marriage", old, new, {"who": "a"}, {"who": "a"}, keymaps(tmp_path))
    assert f"M {K1} 1 : S # ok" in r.sheet and f"M {K2} 1 : U" in r.sheet
    with pytest.raises(SheetError, match="^ANSWER_PERSON_MOVED 1$"):
        run("marriage", old, new, {"who": "a"}, {"who": "b"}, keymaps(tmp_path))


def test_marriage_v3_keeps_name_override_and_translates_p(tmp_path, monkeypatch):
    seen = []
    monkeypatch.setitem(ta.PROPOSE, "marriage_v3", lambda rows, key, navn: seen.append(navn) or 5)
    old = f"M {K1} 1 : S navn: »Bo Beta« # rettet\nP {OLD_P1} 1 : U\n"
    new = f"M {K1} 1 : S\nP {NEW_P1} 1 : D\n"
    r = run("marriage_v3", old, new, {}, {}, keymaps(tmp_path))
    assert f"M {K1} 1 : S navn: »Bo Beta« # rettet" in r.sheet and f"P {NEW_P1} 1 : U" in r.sheet
    assert seen == ["Bo Beta", "Bo Beta"]


def test_child_transfers(tmp_path):
    r = run("child", f"C {K1} 1 : R # brud\n", f"C {K1} 1 : B\n", {}, {}, keymaps(tmp_path))
    assert f"C {K1} 1 : R # brud" in r.sheet


def test_keymap_duplicate_only_in_lookup_classes(tmp_path):
    keymaps(tmp_path)   # to batch-linjer: mange-til-én, ingen fejl
    with pytest.raises(SheetError, match="^KEYMAP_DUPLICATE"):
        keymaps(tmp_path, extra_new=["66666666-6666-4666-8666-666666666666|persona:1:aa-1#rel-1"])
    with pytest.raises(SheetError, match="^KEYMAP_DUPLICATE"):
        keymaps(tmp_path, extra_new=[f"{NEW_P1}|persona:1:zz"])


def test_cli_prints_only_counts_and_writes_0600(tmp_path):
    root = tmp_path / "priv"; root.mkdir()
    old, new = spouse_sheets(old_tok="U")
    files = {"old.txt": old, "new.txt": new, "old.json": json.dumps(spouse_rows(OLD_P1)), "new.json": json.dumps(spouse_rows(NEW_P1)),
             "drop.txt": "# ingen\n"}
    for k, v in files.items():
        (root / k).write_text(v, encoding="utf-8")
    keymaps(root)
    args = ["transfer", "--kind", "spouse", "--old-sheet", str(root / "old.txt"), "--old-rows", str(root / "old.json"),
            "--old-keymap", str(root / "old.km"), "--new-sheet", str(root / "new.txt"), "--new-rows", str(root / "new.json"),
            "--new-keymap", str(root / "new.km"), "--expected-dropouts", str(root / "drop.txt"),
            "--out-sheet", str(root / "ud.txt"), "--out-report", str(root / "rapport.txt"), "--private-root", str(root)]
    r = subprocess.run([sys.executable, "-I", str(Path(ta.__file__)), *args], capture_output=True, text=True)
    assert r.returncode == 0, r.stderr
    assert re.fullmatch(r"ANSWERS_OK kind=spouse overfoert=2 bortfald=0 aendret=0 report_sha256=[0-9a-f]{64}\n", r.stdout)
    assert not UUID.search(r.stdout + r.stderr) and "Bo Beta" not in r.stdout + r.stderr
    for f in ("ud.txt", "rapport.txt"):
        assert oct((root / f).stat().st_mode & 0o777) == "0o600"
    r = subprocess.run([sys.executable, "-I", str(Path(ta.__file__)), *args], capture_output=True, text=True)
    assert r.returncode == 1 and "ANSWER_OUT_EXISTS" in r.stderr
    r = subprocess.run([sys.executable, "-I", str(Path(ta.__file__)), "transfer", "--ukendt", "x"], capture_output=True, text=True)
    assert r.returncode == 2


def v2_rows(person):
    text = "Gift 1890 med Cia Ceta."
    return {"contract": "relation-persona-v2-input", "source_id": 1, "deceased_cutoff_year": 1906, "rows": [
        {"interpretation_key": K1, "interpretation_version": 1, "predicate": "relation.marriage", "raw": "Gift med Cia Ceta",
         "record_key": "II-1", "marriage_ordinal": 1, "supporting_count": 1, "principal_ok": True, "principal_person_id": 9,
         "principal_partners": [{"person_id": person, "family_id": 3, "ordinal": 1, "navn": "Cia Carla Ceta", "foedt": "1870",
                                 "doed": "1940"}],
         "clauses": [{"observation_id": "o-1", "clause_set_seq": 1, "clause_set_sha256": "c" * 64, "verbatim_text": text,
                      "post_char_from": 100, "post_char_to": 100 + len(text)}]}]}


def test_marriage_s_with_real_v2_proposal(tmp_path):
    old, new = f"M {K1} 1 : S\n", f"M {K1} 1 : S\n"
    assert ta.PROPOSE["marriage"](v2_rows(7), K1, None) == 7
    run("marriage", old, new, v2_rows(7), v2_rows(7), keymaps(tmp_path))
    with pytest.raises(SheetError, match="^ANSWER_PERSON_MOVED 1$"):
        run("marriage", old, new, v2_rows(7), v2_rows(8), keymaps(tmp_path))
