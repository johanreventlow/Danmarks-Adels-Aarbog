import json
import re
import subprocess
import sys
from pathlib import Path

import pytest

import transfer_5ab_content_check as cc
from decision_sheet_core import SheetError

K1 = "33333333-3333-4333-8333-333333333333"
K2 = "34343434-3434-4343-8343-343434343434"
UUID = re.compile(r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}")
BASE = [f'binding|{K1}:family:7|{{"rule_key": "relation-marriage-v1", "rule_version": 1}}',
        f'classification|{K1}:1|{{"classification": "ordinal_afvigelse"}}',
        'identity|I-1#rel-marriage-10-4|{"person_id": 5, "status": "accepted"}',
        'origin|I-1#rel-marriage-10-4|{"origin": "human_sheet"}',
        'family_source|7:aegteskab:I-1:5|{"family_id": 7}',
        'family_source|7:aegteskab:I-1:5|{"family_id": 7}']


def expected(*entries):
    return {"version": "5ab-expected-v1", "entries": list(entries)}


def cmp(old, new, exp=None):
    return cc.compare(cc.parse_lines("\n".join(old) + "\n"), cc.parse_lines("\n".join(new) + "\n"),
                      cc.load_expected(exp or expected()))


def test_same_files_ok():
    r = cmp(BASE, BASE)
    assert (r.same, r.allowed, r.unexpected, r.unused) == (5, 0, [], 0)


def test_changed_target_without_entry_is_unexpected():
    new = [l.replace(":family:7|", ":family:8|") for l in BASE]
    assert len(cmp(BASE, new).unexpected) == 2      # nøglen forsvinder, og en ny opstår


def test_may_differ_only_on_named_fields():
    new = [l.replace('"origin": "human_sheet"', '"origin": "family_corroboration"') for l in BASE]
    e = {"layer": "origin", "key": "I-1#rel-marriage-10-4", "kind": "may_differ", "fields": ["andet"], "reason": "t"}
    assert len(cmp(BASE, new, expected(e)).unexpected) == 1
    r = cmp(BASE, new, expected({**e, "fields": ["origin"]}))
    assert (r.unexpected, r.allowed) == ([], 1)


def test_absent_new_covers_missing_key():
    e = {"layer": "classification", "key": f"{K1}:1", "kind": "absent_new", "reason": "#244"}
    new = [l for l in BASE if not l.startswith("classification|")]
    r = cmp(BASE, new, expected(e))
    assert (r.unexpected, r.allowed) == ([], 1)


def test_absent_new_on_present_key_is_unexpected():
    e = {"layer": "classification", "key": f"{K1}:1", "kind": "absent_new", "reason": "#244"}
    new = [l.replace("ordinal_afvigelse", "ordinal_beholdt") for l in BASE]
    assert len(cmp(BASE, new, expected(e)).unexpected) == 1


def test_extra_key_in_new_without_entry_is_unexpected():
    new = BASE + [f'binding|{K2}:family:9|{{"rule_key": "relation-child-v1", "rule_version": 1}}']
    assert len(cmp(BASE, new).unexpected) == 1
    e = {"layer": "binding", "key": f"{K2}:family:9", "kind": "absent_old", "reason": "t"}
    assert cmp(BASE, new, expected(e)).unexpected == []


def test_duplicate_rows_are_a_multiset():
    new = [l for l in BASE if not l.startswith("family_source|")] + ['family_source|7:aegteskab:I-1:5|{"family_id": 7}']
    assert len(cmp(BASE, new).unexpected) == 1


def test_sheet_layers_and_unused_entries():
    e1 = {"layer": "sheet:spouse", "key": "persona:1:x", "kind": "absent_new", "reason": "ark"}
    e2 = {"layer": "classification", "key": f"{K2}:1", "kind": "absent_new", "reason": "indtraf ikke"}
    r = cmp(BASE, BASE, expected(e1, e2))
    assert (r.unexpected, r.unused) == ([], 1)


def test_unknown_kind_and_version_are_invalid():
    with pytest.raises(SheetError, match="^EXPECTED_INVALID"):
        cc.load_expected(expected({"layer": "origin", "key": "x", "kind": "maybe", "reason": "t"}))
    with pytest.raises(SheetError, match="^EXPECTED_INVALID"):
        cc.load_expected({"version": "v0", "entries": []})
    with pytest.raises(SheetError, match="^EXPECTED_INVALID"):
        cc.load_expected(expected({"layer": "origin", "key": "x", "kind": "may_differ", "reason": "t"}))


def _cli(tmp_path, old, new, exp):
    root = tmp_path / "priv"; root.mkdir(exist_ok=True)
    (root / "old.txt").write_text("\n".join(old) + "\n", encoding="utf-8")
    (root / "new.txt").write_text("\n".join(new) + "\n", encoding="utf-8")
    (root / "exp.json").write_text(json.dumps(exp), encoding="utf-8")
    rep = root / "rapport.txt"
    if rep.exists():
        rep.unlink()
    r = subprocess.run([sys.executable, "-I", str(Path(cc.__file__)), "--old", str(root / "old.txt"), "--new", str(root / "new.txt"),
                        "--expected", str(root / "exp.json"), "--report", str(rep)], capture_output=True, text=True)
    return r, rep


def test_cli_counts_only_and_report_0600(tmp_path):
    r, rep = _cli(tmp_path, BASE, BASE, expected())
    assert r.returncode == 0, r.stderr
    assert re.fullmatch(r"CONTENT_OK same=5 allowed=0 unused_expected=0\n", r.stdout)
    assert oct(rep.stat().st_mode & 0o777) == "0o600"
    new = [l.replace(":family:7|", ":family:8|") for l in BASE]
    r, rep = _cli(tmp_path, BASE, new, expected())
    assert r.returncode == 3 and re.fullmatch(r"CONTENT_UNEXPECTED n=2 report_sha256=[0-9a-f]{64}\n", r.stdout)
    assert not UUID.search(r.stdout + r.stderr) and K1 in rep.read_text(encoding="utf-8")
    r = subprocess.run([sys.executable, "-I", str(Path(cc.__file__)), "--ukendt", "x"], capture_output=True, text=True)
    assert r.returncode == 2
