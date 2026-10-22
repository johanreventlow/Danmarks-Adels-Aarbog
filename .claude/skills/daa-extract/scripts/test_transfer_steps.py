import hashlib
import json
import subprocess
import sys
from pathlib import Path

import pytest

import transfer_steps as ts
from decision_sheet_core import SheetError

H = lambda c: c * 64  # noqa: E731


def digests(**layers):
    return {lag: {"n": 1, "sha256": sha} for lag, sha in layers.items()}


def pack():
    p = ts.new_pack(d1_receipt_sha256=H("d"), restore_hash=H("5"))
    ts.add_step(p, name="profile", type="sql", script="repo:s/profile.sql", vars={"src": 1}, inputs={}, items_sha256=H("1"),
                layers=["writer_profiles"], count=1, digests_in=digests(writer_profiles=H("a")),
                digests_out=digests(writer_profiles=H("b")), seconds=1.0)
    ts.add_step(p, name="decide", type="hash_gated", script="repo:s/decide.sql", vars={"src": 1}, inputs={}, items_sha256=H("2"),
                layers=["interpretations", "classifications"], count=1,
                digests_in=digests(interpretations=H("c"), classifications=H("e"), writer_profiles=H("b")),
                digests_out=digests(interpretations=H("f"), classifications=H("0"), writer_profiles=H("b")), seconds=2.0)
    return p


def test_valid_pack_and_layers_only():
    p = pack()
    ts.validate(p)
    assert p["steps"][1]["digests_in"] == {"interpretations": H("c"), "classifications": H("e")}
    assert p["version"] == "transfer-pack-5ab-v1"


@pytest.mark.parametrize("mut,felt", [
    (lambda p: p["steps"][0].__setitem__("type", "magi"), "type"),
    (lambda p: p["steps"][1].__setitem__("n", 1), "n"),
    (lambda p: p["steps"][0]["layers"].append("authorizations_issued"), "layers"),
    (lambda p: p["steps"][0]["layers"].append("ukendt_lag"), "layers"),
    (lambda p: p["steps"][0].__setitem__("items_sha256", ""), "items_sha256"),
    (lambda p: p["steps"][0].__setitem__("digests_out", dict(p["steps"][0]["digests_in"])), "digests_out"),
    (lambda p: p.__setitem__("version", "v0"), "version"),
    (lambda p: p["steps"][0].__setitem__("script", "s/profile.sql"), "script"),
])
def test_invalid_pack(mut, felt):
    p = pack(); mut(p); p["pack_sha256"] = ts.pack_sha256(p)
    with pytest.raises(SheetError, match=f"^PACK_INVALID {felt}$"):
        ts.validate(p)


def test_tampered_pack_sha():
    p = pack(); p["steps"][0]["items_sha256"] = H("9")
    with pytest.raises(SheetError, match="^PACK_INVALID pack_sha256$"):
        ts.validate(p)


def test_pack_sha_changes_with_one_item_hash():
    a, b = pack(), pack()
    b["steps"][1]["items_sha256"] = H("3"); b["pack_sha256"] = ts.pack_sha256(b)
    assert a["pack_sha256"] != b["pack_sha256"]


def test_classify_three_states_only_over_step_layers():
    p = pack()
    # Andre lag (writer_profiles) må være hvad som helst for skridt 2.
    assert ts.classify(p, 2, digests(interpretations=H("c"), classifications=H("e"), writer_profiles=H("7"))) == "WRITE"
    assert ts.classify(p, 2, digests(interpretations=H("f"), classifications=H("0"))) == "ALREADY_APPLIED"
    assert ts.classify(p, 2, digests(interpretations=H("f"), classifications=H("e"))) == "MIXED"


def test_classify_step_without_writes_is_already_applied():
    p = ts.new_pack(d1_receipt_sha256=H("d"), restore_hash=H("5"))
    ts.add_step(p, name="bind", type="hash_gated", script="repo:s/bind.sql", vars={}, inputs={}, items_sha256=H("1"), layers=["bindings"],
                count=0, digests_in=digests(bindings=H("a")), digests_out=digests(bindings=H("a")), seconds=0.1)
    ts.validate(p)
    assert ts.classify(p, 1, digests(bindings=H("a"))) == "ALREADY_APPLIED"


def test_next_skips_done_steps():
    p = pack()
    assert ts.next_step(p, set()) == (1, "profile")
    assert ts.next_step(p, {1}) == (2, "decide")
    assert ts.next_step(p, {1, 2}) is None


def _repo_with_steps(tmp_path):
    repo, priv = tmp_path / "repo", tmp_path / "priv"
    (repo / "s").mkdir(parents=True); priv.mkdir()
    (repo / "s" / "profile.sql").write_text("\\ir inc/begin.sql\nSELECT 1;\n")
    (repo / "s" / "inc").mkdir(); (repo / "s" / "inc" / "begin.sql").write_text("SELECT 2;\n")
    (repo / "s" / "decide.sql").write_text("SELECT 3;\n")
    return repo, priv


def _inv(p, repo, priv, *keys):
    sha = lambda f: hashlib.sha256(f.read_bytes()).hexdigest()  # noqa: E731
    p["inventory"] = {k: sha((repo if k.startswith("repo:") else priv) / k.split(":", 1)[1]) for k in keys}
    p["pack_sha256"] = ts.pack_sha256(p)


STEP_FILES = ("repo:s/profile.sql", "repo:s/inc/begin.sql", "repo:s/decide.sql")


def test_inventory_missing_changed_and_extra(tmp_path):
    repo, priv = _repo_with_steps(tmp_path)
    (repo / "a.sql").write_text("a"); (priv / "ark.txt").write_text("x")
    p = pack(); _inv(p, repo, priv, *STEP_FILES, "repo:a.sql", "private:ark.txt")
    assert ts.check_inventory(p, repo, priv) == 5
    (priv / "ekstra.txt").write_text("y")
    with pytest.raises(SheetError, match="^INVENTORY_MISMATCH private:ekstra.txt$"):
        ts.check_inventory(p, repo, priv)
    (priv / "ekstra.txt").unlink(); (repo / "a.sql").write_text("b")
    with pytest.raises(SheetError, match="^INVENTORY_MISMATCH repo:a.sql$"):
        ts.check_inventory(p, repo, priv)
    (repo / "a.sql").unlink()
    with pytest.raises(SheetError, match="^INVENTORY_MISMATCH repo:a.sql$"):
        ts.check_inventory(p, repo, priv)


def test_inventory_requires_step_scripts_and_their_includes(tmp_path):
    repo, priv = _repo_with_steps(tmp_path)
    p = pack(); _inv(p, repo, priv, "repo:s/profile.sql", "repo:s/decide.sql")
    with pytest.raises(SheetError, match="^INVENTORY_MISMATCH repo:s/inc/begin.sql$"):
        ts.check_inventory(p, repo, priv)
    _inv(p, repo, priv, "repo:s/profile.sql", "repo:s/inc/begin.sql")
    with pytest.raises(SheetError, match="^INVENTORY_MISMATCH repo:s/decide.sql$"):
        ts.check_inventory(p, repo, priv)


def test_inventory_key_outside_root(tmp_path):
    repo, priv = _repo_with_steps(tmp_path)
    (tmp_path / "x.sql").write_text("x")
    p = pack(); _inv(p, repo, priv, *STEP_FILES)
    p["inventory"]["repo:../x.sql"] = hashlib.sha256(b"x").hexdigest(); p["pack_sha256"] = ts.pack_sha256(p)
    with pytest.raises(SheetError, match="^INVENTORY_MISMATCH repo:../x.sql$"):
        ts.check_inventory(p, repo, priv)


def test_continuity_between_steps_sharing_a_layer():
    p = pack()
    ts.add_step(p, name="reject", type="sql", script="repo:s/decide.sql", vars={}, inputs={}, items_sha256=H("4"),
                layers=["interpretations"], count=1, digests_in=digests(interpretations=H("f")),
                digests_out=digests(interpretations=H("6")), seconds=1.0)
    ts.validate(p)
    p["steps"][2]["digests_in"]["interpretations"] = H("7"); p["steps"][2]["digests_out"]["interpretations"] = H("6")
    p["pack_sha256"] = ts.pack_sha256(p)
    with pytest.raises(SheetError, match="^PACK_INVALID continuity$"):
        ts.validate(p)


def _cli(*a):
    return subprocess.run([sys.executable, "-I", str(Path(ts.__file__)), *a], capture_output=True, text=True)


def test_cli_roundtrip_and_unknown_argument(tmp_path):
    pk = tmp_path / "pack.json"
    din, dout = tmp_path / "in.dg", tmp_path / "out.dg"
    din.write_text("daa.transfer_5ab_digests=" + json.dumps({**digests(writer_profiles=H("a")), "n_uuid_unmapped": 0}) + "\n")
    dout.write_text("daa.transfer_5ab_digests=" + json.dumps({**digests(writer_profiles=H("b")), "n_uuid_unmapped": 0}) + "\n")
    assert _cli("init", "--pack", str(pk), "--d1-receipt-sha256", H("d"), "--restore-hash", H("5")).returncode == 0
    r = _cli("add-step", "--pack", str(pk), "--name", "profile", "--type", "sql", "--script", "repo:s/p.sql", "--vars", '{"src":1}',
             "--inputs", "{}", "--items-sha256", H("1"), "--layers", "writer_profiles", "--count", "1",
             "--digests-in", str(din), "--digests-out", str(dout), "--seconds", "0.5")
    assert r.returncode == 0, r.stderr
    assert _cli("validate", "--pack", str(pk)).stdout.startswith("PACK_OK steps=1 pack_sha256=")
    assert _cli("classify", "--pack", str(pk), "--n", "1", "--digests", str(din)).stdout == "WRITE\n"
    assert _cli("classify", "--pack", str(pk), "--n", "1", "--digests", str(dout)).stdout == "ALREADY_APPLIED\n"
    mixed = tmp_path / "x.dg"
    mixed.write_text("daa.transfer_5ab_digests=" + json.dumps(digests(writer_profiles=H("c"))) + "\n")
    r = _cli("classify", "--pack", str(pk), "--n", "1", "--digests", str(mixed))
    assert r.returncode == 3 and r.stdout == "MIXED\n"
    assert _cli("next", "--pack", str(pk), "--done", "").stdout == "NEXT n=1 name=profile\n"
    assert _cli("next", "--pack", str(pk), "--done", "1").stdout == "NEXT_NONE\n"
    assert _cli("validate", "--pack", str(pk), "--ukendt").returncode == 2
    assert _cli("init", "--pack", str(pk), "--d1-receipt-sha256", H("d"), "--restore-hash", H("5")).returncode == 1


def test_cli_inventory_add_binds_files(tmp_path):
    repo, priv = _repo_with_steps(tmp_path)
    pk = tmp_path / "pack.json"; ts._save(pk, pack(), new=True)
    for k in STEP_FILES:
        r = _cli("inventory-add", "--pack", str(pk), "--root", str(repo), "--private", str(priv), "--key", k)
        assert r.returncode == 0 and r.stdout.startswith("PACK_INVENTORY_OK n="), r.stderr
    r = _cli("inventory", "--pack", str(pk), "--root", str(repo), "--private", str(priv))
    assert r.stdout == "INVENTORY_OK n=3\n", r.stderr
    r = _cli("inventory-add", "--pack", str(pk), "--root", str(repo), "--private", str(priv), "--key", "repo:mangler.sql")
    assert r.returncode == 1 and "INVENTORY_MISMATCH repo:mangler.sql" in r.stderr
