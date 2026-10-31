"""Tests for publication_identity_sheet.py (trin 6b C): syntetiske data, ingen database, kun opdigtede navne."""
import hashlib
import json
import subprocess
import sys
import uuid
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import publication_identity_sheet as pis  # noqa: E402
from decision_sheet_core import SheetError  # noqa: E402

RUN = "11111111-1111-4111-8111-111111111111"
BATCH = "22222222-2222-4222-8222-222222222222"
CAND = "ab" * 32
KEYS = ["answer", "binding_id", "binding_status", "candidate_run_id", "candidates_sha256", "expected_identity_version",
        "outcome", "person_id", "persona_batch_id", "rows_sha256", "same_as_hint_person_id", "sheet_line", "sheet_sha256",
        "source_persona_id"]
SCRIPT = Path(__file__).resolve().parent / "publication_identity_sheet.py"


def pid(n):
    return str(uuid.UUID(int=n, version=4))


def make(n_weak=3, n_enig=6, n_sample=2, staged=1, existing=1):
    """Syntetisk control + details. Personas: svage, enige (n_sample af dem i stikprøven), staged, eksisterende."""
    pers, det = [], []
    k = 0

    def add(outcome, sample=False, version=0, not_staged=True):
        nonlocal k
        k += 1
        p = pid(k)
        pers.append({"source_persona_id": p, "identity_version": version, "binding_id": pid(1000 + k),
                     "binding_status": "published", "person_id": 5000 + k, "outcome": outcome, "reason": None,
                     "in_sample": sample, "not_staged": not_staged})
        det.append({"source_persona_id": p, "persona_key": f"1939:r{k}", "binding_id": pid(1000 + k),
                    "binding_status": "published", "person_id": 5000 + k, "record_label": f"Post {k}", "outcome": {"outcome": outcome},
                    "proposed": {"name": f"Testperson Nr{k}", "birth": "1700", "death": "1760"},
                    "persons": [
                        {"person_id": 5000 + k, "role": "binding", "rank": 1, "cluster_score": 2, "score_raw": 2, "signals": ["navn"],
                         "navn": f"Bindingsnavn {k}", "foedt": "1700", "doed": "1760", "titel": ["Hofjægermester"], "record_labels": [f"Post {k}"]},
                        *[{"person_id": 9000 + j, "role": "competitor", "rank": 2 + j, "cluster_score": 3 - j, "score_raw": 3 - j,
                           "signals": [], "navn": f"Konkurrent {j}", "foedt": "1701", "doed": None, "titel": [], "record_labels": []}
                          for j in range(4)]]})
        return p

    for _ in range(n_weak):
        add("svag")
    for i in range(n_enig):
        add("enig", sample=i < n_sample)
    for _ in range(staged):
        add("enig", not_staged=False)
    for _ in range(existing):
        add("svag", version=3)
    return ({"candidate_run_id": RUN, "source_id": 3, "personas": pers},
            {"candidate_run_id": RUN, "source_id": 3, "personas": det})


def dump(path, obj):
    path.write_text(json.dumps(obj), encoding="utf-8")


def fill(text, tokens):
    """Udfyld P-linjer i rækkefølge: tokens er dict pid -> token, standard S."""
    out = []
    for line in text.splitlines():
        if line.startswith("P "):
            p = line.split()[1]
            line = line.replace(": _ #", f": {tokens.get(p, 'S')} #")
        out.append(line)
    return "\n".join(out) + "\n"


def test_kortantal_og_blanding_deterministisk():
    ctl, det = make()
    a = pis.render(ctl, det, "x")
    b = pis.render(ctl, det, "x")
    assert a == b
    pids = [l.split()[1] for _, t in a for l in t.splitlines() if l.startswith("P ")]
    # 3 svage + 1 eksisterende svag + 2 stikprøve = 6; staged og ikke-stikprøve-enige har ikke kort
    assert len(pids) == 6
    sample = [c["source_persona_id"] for c in ctl["personas"] if c["in_sample"]]
    assert all(s in pids for s in sample)
    # blandet: ikke alle stikprøvekort står sammen først/sidst i kontrolrækkefølge
    assert pids != sorted(pids, key=lambda p: (p in sample, p))
    text = "".join(t for _, t in a)
    assert "svag" not in text and "enig" not in text   # udfaldet vises ikke
    assert text.count("#   Konkurrent ") == 18   # højst 3 pr. kort


def test_over_90_kort_fejler():
    ctl, det = make(n_weak=91, n_enig=0, n_sample=0)
    with pytest.raises(SheetError, match="PUBLICATION_SHEET_TOO_MANY_CARDS"):
        pis.render(ctl, det, "x")


def test_hoejst_30_pr_fil():
    ctl, det = make(n_weak=70, n_enig=0, n_sample=0, staged=0, existing=0)
    files = pis.render(ctl, det, "x")
    assert [len(t.split("\nP ")) - 1 for _, t in files] == [30, 30, 10]
    assert [n for n, _ in files] == ["x-1.txt", "x-2.txt", "x-3.txt"]


def build(ctl, det, tmp_path, tokens=None, mutate=None):
    cb = json.dumps(ctl).encode()
    files = pis.render(ctl, det, "x")
    sheets, approved = [], []
    for n, t in files:
        t = fill(t, tokens or {})
        b = t.encode()
        sheets.append((n, b))
        approved.append(hashlib.sha256(b).hexdigest())
    if mutate:
        sheets = mutate(sheets)
    return pis.build_manifest(cb, sheets, approved, BATCH, CAND)


def test_aendret_arkbyte_giver_hashfejl(tmp_path):
    ctl, det = make()
    def mut(sh):
        n, b = sh[0]
        return [(n, b + b"\n")] + sh[1:]
    with pytest.raises(SheetError, match="PUBLICATION_SHEET_HASH_MISMATCH"):
        build(ctl, det, tmp_path, mutate=mut)


@pytest.mark.parametrize("tok", ["F", "U"])
def test_f_u_paa_stikproeve_stopper(tmp_path, tok):
    ctl, det = make()
    s = next(c["source_persona_id"] for c in ctl["personas"] if c["in_sample"])
    with pytest.raises(SheetError, match="PUBLICATION_SAMPLE_FAILED"):
        build(ctl, det, tmp_path, tokens={s: tok})


def test_manifest_noeglesaet_og_hint(tmp_path):
    ctl, det = make()
    sample = [c["source_persona_id"] for c in ctl["personas"] if c["in_sample"]]
    weak = next(c["source_persona_id"] for c in ctl["personas"] if c["outcome"] == "svag" and c["identity_version"] == 0)
    fvar = [c["source_persona_id"] for c in ctl["personas"] if c["outcome"] == "svag" and c["identity_version"] == 0][1]
    man, info = build(ctl, det, tmp_path, tokens={weak: "S 123", fvar: "F"})
    els = man["elements"]
    for k, v in els.items():
        assert sorted(v) == KEYS
        assert k == f"publication-identity:{v['source_persona_id']}"
        assert v["expected_identity_version"] == 0 and v["persona_batch_id"] == BATCH and v["candidate_run_id"] == RUN
    assert els[f"publication-identity:{weak}"]["same_as_hint_person_id"] == 123
    assert els[f"publication-identity:{weak}"]["answer"] == "S"
    assert els[f"publication-identity:{fvar}"]["answer"] == "F"
    # enig udenfor stikprøven: ingen svar, ingen arkfelter; stikprøven: S med arkfelter
    ikke_sample_enig = [c for c in ctl["personas"] if c["outcome"] == "enig" and not c["in_sample"] and c["not_staged"]][0]
    e = els[f"publication-identity:{ikke_sample_enig['source_persona_id']}"]
    assert e["answer"] is None and e["sheet_sha256"] is None and e["rows_sha256"] is None and e["sheet_line"] is None
    s = els[f"publication-identity:{sample[0]}"]
    assert s["answer"] == "S" and len(s["sheet_sha256"]) == 64 and s["sheet_line"] >= 1
    assert s["rows_sha256"] == hashlib.sha256(json.dumps(ctl).encode()).hexdigest()
    # 3 svage + 6 enige nye; staged og eksisterende er dispositioner
    assert man["expected_counts"] == {"person_creates": 0, "source_evidence": 0, "publication_identities": 9}
    assert sorted(d["label"] for d in man["dispositions"]) == ["eksisterende_uaendret", "staged_ikke_offentlig"]


def test_manglende_kort_afvises(tmp_path):
    ctl, det = make()
    def mut(sh):
        n, b = sh[0]
        lines = [l for l in b.decode().splitlines() if not l.startswith("P ")]
        return [(n, "\n".join(lines).encode())] + sh[1:]
    ctl_b = json.dumps(ctl).encode()
    files = pis.render(ctl, det, "x")
    b = "\n".join(l for l in fill(files[0][1], {}).splitlines() if not l.startswith("P ")).encode()
    with pytest.raises(SheetError, match="PUBLICATION_SHEET_CARDS_MISMATCH"):
        pis.build_manifest(ctl_b, [("x-1.txt", b)], [hashlib.sha256(b).hexdigest()], BATCH, CAND)


def run_cli(*a):
    return subprocess.run([sys.executable, "-I", str(SCRIPT), *a], capture_output=True, text=True)


def test_sti_uden_for_private_root_afvises(tmp_path):
    root = tmp_path / "priv"
    root.mkdir()
    ctl, det = make()
    outside = tmp_path / "ctl.json"
    dump(outside, ctl)
    dump(root / "det.json", det)
    r = run_cli("render", "--control", str(outside), "--details", str(root / "det.json"), "--out", str(root / "k"),
                "--private-root", str(root))
    assert r.returncode != 0 and "SHEET_PATH_NOT_PRIVATE" in (r.stderr + r.stdout)


def test_sti_i_git_afvises(tmp_path):
    root = tmp_path / "priv"
    (root / "repo" / ".git").mkdir(parents=True)
    ctl, det = make()
    dump(root / "repo" / "ctl.json", ctl)
    dump(root / "det.json", det)
    r = run_cli("render", "--control", str(root / "repo" / "ctl.json"), "--details", str(root / "det.json"),
                "--out", str(root / "k"), "--private-root", str(root))
    assert r.returncode != 0 and "SHEET_PATH_IN_GIT" in (r.stderr + r.stdout)


def test_cli_ende_til_ende(tmp_path):
    root = tmp_path / "priv"
    root.mkdir()
    ctl, det = make()
    dump(root / "ctl.json", ctl)
    dump(root / "det.json", det)
    r = run_cli("render", "--control", str(root / "ctl.json"), "--details", str(root / "det.json"),
                "--out", str(root / "k"), "--private-root", str(root))
    assert r.returncode == 0, r.stderr
    sheet = root / "k-1.txt"
    assert oct(sheet.stat().st_mode & 0o777) == "0o600"
    sheet.write_text(fill(sheet.read_text(), {}))
    sha = hashlib.sha256(sheet.read_bytes()).hexdigest()
    r = run_cli("manifest", "--control", str(root / "ctl.json"), "--sheets", str(sheet), "--approved-sha256", sha,
                "--persona-batch", BATCH, "--candidates-sha256", CAND, "--out", str(root / "m.json"), "--private-root", str(root))
    assert r.returncode == 0, r.stderr
    assert "elements=9" in r.stdout and "Testperson" not in r.stdout
    assert len(json.loads((root / "m.json").read_text())["elements"]) == 9
