"""Review 36, K10: én privat skrivevej (`private_io.py`)."""
from __future__ import annotations

import os
import stat
import subprocess
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import private_io  # noqa: E402
from decision_sheet_core import SheetError  # noqa: E402
from private_io import (PrivateIOError, check_private_path, write_private_new,  # noqa: E402
                        write_private_new_many, write_private_replace)

SCRIPTS = Path(__file__).resolve().parent


def _mode(p: Path) -> int:
    return stat.S_IMODE(os.lstat(p).st_mode)


# --- write_private_new --------------------------------------------------------

def test_new_writes_exact_bytes_with_mode_0600(tmp_path):
    p = tmp_path / "ark.txt"
    write_private_new(p, "æøå\r\nlinje\n")
    assert p.read_bytes() == "æøå\r\nlinje\n".encode("utf-8")   # ingen newline-oversættelse
    assert _mode(p) == 0o600


def test_new_is_0600_even_under_a_permissive_umask(tmp_path):
    gammel = os.umask(0)
    try:
        write_private_new(tmp_path / "a", b"x")
        write_private_replace(tmp_path / "b", b"x")
    finally:
        os.umask(gammel)
    assert _mode(tmp_path / "a") == 0o600 and _mode(tmp_path / "b") == 0o600


def test_new_refuses_an_existing_file_and_leaves_it_untouched(tmp_path):
    p = tmp_path / "ark.txt"
    p.write_text("udfyldt af et menneske", encoding="utf-8")
    with pytest.raises(PrivateIOError, match="PRIVATE_OUT_EXISTS"):
        write_private_new(p, "nyt ark")
    assert p.read_text(encoding="utf-8") == "udfyldt af et menneske"


def test_new_error_is_a_sheet_error_and_keeps_the_callers_code(tmp_path):
    p = tmp_path / "koe.txt"
    p.write_bytes(b"")
    with pytest.raises(SheetError, match="KOE_OUT_EXISTS"):
        write_private_new(p, "x", exists_code="KOE_OUT_EXISTS")


def test_new_refuses_a_symlink_even_a_dangling_one(tmp_path):
    maal = tmp_path / "andetsteds.txt"
    link = tmp_path / "ark.txt"
    link.symlink_to(maal)
    with pytest.raises(PrivateIOError):
        write_private_new(link, "x")
    assert not maal.exists()


def test_new_many_refuses_all_before_writing_any(tmp_path):
    ark, token = tmp_path / "ark.txt", tmp_path / "token.txt"
    token.write_text("gammelt token", encoding="utf-8")
    with pytest.raises(PrivateIOError, match="PRIVATE_OUT_EXISTS"):
        write_private_new_many([(ark, "nyt ark"), (token, "nyt token")])
    assert not ark.exists()
    assert token.read_text(encoding="utf-8") == "gammelt token"


def test_new_many_writes_every_file_0600(tmp_path):
    write_private_new_many([(tmp_path / "a", "1"), (tmp_path / "b", b"2")])
    assert (tmp_path / "a").read_text() == "1" and (tmp_path / "b").read_bytes() == b"2"
    assert _mode(tmp_path / "a") == 0o600 and _mode(tmp_path / "b") == 0o600


# --- write_private_replace ----------------------------------------------------

def test_replace_overwrites_and_tightens_a_wider_mode(tmp_path):
    p = tmp_path / "manifest.json"
    p.write_text("gammel", encoding="utf-8")
    p.chmod(0o644)
    write_private_replace(p, "ny")
    assert p.read_text(encoding="utf-8") == "ny"
    assert _mode(p) == 0o600


def test_replace_refuses_a_symlink_and_leaves_its_target_untouched(tmp_path):
    maal = tmp_path / "maal.txt"
    maal.write_text("urørt", encoding="utf-8")
    link = tmp_path / "out.txt"
    link.symlink_to(maal)
    with pytest.raises(PrivateIOError, match="PRIVATE_OUT_SYMLINK"):
        write_private_replace(link, "x")
    assert link.is_symlink() and maal.read_text(encoding="utf-8") == "urørt"


def test_replace_is_atomic_when_the_write_is_interrupted(tmp_path, monkeypatch):
    """En afbrydelse midt i skrivningen efterlader det gamle indhold — aldrig en
    trunkeret fil — og ingen tempfil (runnerens cache, review 36 K10)."""
    p = tmp_path / "svar.json"
    p.write_text('{"gammelt": true}', encoding="utf-8")

    def afbrudt(fd, data):
        os.write(fd, bytes(data[:3]))
        raise KeyboardInterrupt

    monkeypatch.setattr(private_io, "_write_all", afbrudt)
    with pytest.raises(KeyboardInterrupt):
        write_private_replace(p, '{"nyt": "og langt"}')
    assert p.read_text(encoding="utf-8") == '{"gammelt": true}'
    assert sorted(x.name for x in tmp_path.iterdir()) == ["svar.json"]


def test_replace_goes_through_a_private_tempfile_and_os_replace(tmp_path, monkeypatch):
    p = tmp_path / "svar.json"
    set_ = []
    ægte = os.replace

    def spion(src, dst):
        src = Path(src)
        set_.append((src.name, _mode(src), src.parent == p.parent, Path(dst) == p))
        ægte(src, dst)

    monkeypatch.setattr(private_io.os, "replace", spion)
    write_private_replace(p, "x")
    (navn, mode, samme_mappe, til_maal), = set_
    assert navn.startswith(".") and navn.endswith(".tmp") and not navn.endswith(".json")
    assert mode == 0o600 and samme_mappe and til_maal


# --- check_private_path (flyttet uændret) ------------------------------------

def test_check_private_path_is_the_same_object_from_the_old_modules():
    import identity_queue_sheet
    import spouse_exception_sheet
    import transfer_answers
    assert spouse_exception_sheet.check_private_path is check_private_path
    assert identity_queue_sheet.check_private_path is check_private_path
    assert transfer_answers.check_private_path is check_private_path


def test_check_private_path_keeps_its_codes(tmp_path):
    root = tmp_path / "privat"
    root.mkdir()
    (root / "ok.txt").write_text("x")
    assert check_private_path(root / "ok.txt", root) == (root / "ok.txt").resolve()
    with pytest.raises(SheetError, match="SHEET_PATH_NOT_PRIVATE"):
        check_private_path(tmp_path / "ude.txt", root)
    (root / "link.txt").symlink_to(root / "ok.txt")
    with pytest.raises(SheetError, match="SHEET_PATH_SYMLINK"):
        check_private_path(root / "link.txt", root)
    (root / "repo" / ".git").mkdir(parents=True)
    with pytest.raises(SheetError, match="SHEET_PATH_IN_GIT"):
        check_private_path(root / "repo" / "a.txt", root)


# --- CLI-scripts skal kunne importere modulet under `python -I` --------------

#: Scripts, der efter K10 importerer `private_io`.  Under `python -I` lægges
#: scriptets mappe IKKE på sys.path; pytest gør, så en manglende `sys.path.insert`
#: ville være grøn her og brække den rigtige kørsel.  Scripts, der i forvejen
#: importerer en søsterfil uden sys.path-indsættelse, er ikke -I-kørbare før eller
#: efter K10; de står i den anden liste, så forskellen er synlig.
I_SAFE = ["build_43b_judgement_sheet.py", "build_43b_manifest.py", "build_43b_proposal_manifest.py",
          "build_43b_selection.py", "build_45_selection.py", "build_clause_evidence_manifest.py",
          "build_eligible_selection.py", "build_header_manifest.py", "identity_queue_sheet.py",
          "placement_kort_1939.py",
          "relation_persona_extract.py", "run_evidence_43b.py", "transfer_5ab_content_check.py",
          "transfer_answers.py", "transfer_ddl.py"]


@pytest.mark.parametrize("script", I_SAFE)
def test_converted_script_imports_under_isolated_mode(script):
    r = subprocess.run([sys.executable, "-I", str(SCRIPTS / script), "--help"],
                       capture_output=True, text=True, timeout=60, cwd=SCRIPTS.parent.parent.parent.parent)
    assert r.returncode == 0, r.stderr[-300:]
