"""Review 36, D3: CI's python-job skal køre ALLE Python-testfiler.

Den tidligere håndskrevne liste udelod 69 af 134 filer, uden at noget sagde fra.
Denne test læser det rigtige `.github/workflows/ci.yml` (ikke en kopi af listen) og
fejler, hvis

* en `test_*.py` under `.claude/skills/*/scripts/` hverken ligger i en mappe, CI-trinnet
  giver pytest, eller står i trinnets udelukkelser (`--ignore=` / `--deselect=`);
* en skill-mappe med testfiler slet ikke er med i kommandoen;
* en udelukkelse peger på en fil eller test, der ikke (længere) findes — en forældet
  udelukkelse skjuler ellers, at listen er gledet.

Filer, der kører, men springer alle tests over (fx manglende gitignorerede artefakter),
fanges ikke her; de står i pytest's `-rs`-opsummering i CI-loggen.
"""
from __future__ import annotations

import ast
import re
import shlex
from pathlib import Path

REPO = Path(__file__).resolve().parents[4]
CI = REPO / ".github" / "workflows" / "ci.yml"
STEP_NAME = "pipeline · pytest (alle testfiler)"


def _python_job(text: str) -> str:
    m = re.search(r"^  python:\n(.*?)(?=^  [a-z][a-z0-9_-]*:\n)", text, re.S | re.M)
    assert m, "python-jobbet findes ikke i ci.yml"
    return m.group(1)


def _step_run(job: str) -> str:
    i = job.index(f"- name: {STEP_NAME}")
    rest = job[i:]
    m = re.search(r"\n        run: \|\n((?:          .*\n|\s*\n)+)", rest)
    assert m, "trinnets run-blok ikke fundet"
    return "\n".join(line[10:] for line in m.group(1).splitlines())


def _ci_command():
    script = _step_run(_python_job(CI.read_text(encoding="utf-8")))
    # Kommentarlinjer i bash-arrayet bærer årsagerne; de er ikke argumenter.
    uden_kommentarer = "\n".join(l for l in script.splitlines() if not l.strip().startswith("#"))
    tokens = shlex.split(uden_kommentarer)
    i = tokens.index("pytest")
    assert tokens[i - 2:i] == ["python3", "-m"], tokens[i - 2:i + 1]
    # Positionelle stier er dem, der peger ind i repoet; `no:cacheprovider` (til `-p`) og
    # `${udeluk[@]}` er ikke stier.
    paths = [t for t in tokens[i + 1:] if t.startswith(".claude/")]
    ignores = [t.split("=", 1)[1] for t in tokens if t.startswith("--ignore=")]
    deselects = [t.split("=", 1)[1] for t in tokens if t.startswith("--deselect=")]
    return paths, ignores, deselects


def _test_files():
    # Kun skill-mapperne og kun ét niveau: aldrig en rekursiv søgning, der kunne gå ned i
    # gitignorerede arbejdsmapper (invariant 8).
    return sorted(p for p in REPO.glob(".claude/skills/*/scripts/test_*.py"))


def test_the_ci_step_is_found_and_runs_whole_directories():
    paths, _, _ = _ci_command()
    assert paths, "CI-trinnet giver ingen stier til pytest"
    for p in paths:
        assert (REPO / p).is_dir(), f"CI-stien er ikke en mappe: {p}"


def test_every_python_test_file_is_run_or_explicitly_excluded():
    paths, ignores, _ = _ci_command()
    dirs = [(REPO / p).resolve() for p in paths]
    ignored = {(REPO / p).resolve() for p in ignores}
    uden_for = [str(f.relative_to(REPO)) for f in _test_files()
                if f.resolve() not in ignored and not any(d in f.resolve().parents for d in dirs)]
    assert uden_for == [], f"testfiler, CI hverken kører eller udelukker: {uden_for}"


def test_exclusions_point_at_things_that_exist():
    _, ignores, deselects = _ci_command()
    for p in ignores:
        assert (REPO / p).is_file(), f"forældet --ignore: {p}"
    for node in deselects:
        fil, _, navn = node.partition("::")
        assert (REPO / fil).is_file(), f"forældet --deselect (fil): {node}"
        funktioner = {n.name for n in ast.walk(ast.parse((REPO / fil).read_text(encoding="utf-8")))
                      if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef))}
        assert navn.split("[")[0].split("::")[-1] in funktioner, f"forældet --deselect (test): {node}"


# Review 37 C13: node-testfiler (`test_*.mjs`) i skill-mapperne kører ikke under pytest og var usynlige for vagten.
# Hver skal enten køres af ci.yml (stien står i workflowet) eller stå her med årsagen til, at den kun køres lokalt.
KUN_LOKALT_MJS = {
    ".claude/skills/daa-extract/scripts/test_c3_html_review_browser_1939_v50.mjs":
        "kræver Playwright-Chromium og /usr/bin/python3; CI-minutterne er begrænsede. Køres lokalt med "
        "`node <fil>`, når C3-HTML-reviewet (build_c3_html_review_1939_v50.py) ændres.",
}


def _mjs_test_files():
    # Samme afgrænsning som _test_files: kun skill-mapperne, ét niveau.
    return sorted(str(p.relative_to(REPO)) for p in REPO.glob(".claude/skills/*/scripts/test_*.mjs"))


def test_every_node_test_file_is_run_or_explicitly_local():
    ci = CI.read_text(encoding="utf-8")
    usynlige = [f for f in _mjs_test_files() if f not in ci and f not in KUN_LOKALT_MJS]
    assert usynlige == [], f"node-testfiler, CI hverken kører eller lister som kun lokale: {usynlige}"


def test_local_only_node_tests_exist_and_are_not_also_in_ci():
    ci = CI.read_text(encoding="utf-8")
    for f, aarsag in KUN_LOKALT_MJS.items():
        assert (REPO / f).is_file(), f"forældet KUN_LOKALT_MJS: {f}"
        assert aarsag.strip(), f"KUN_LOKALT_MJS uden årsag: {f}"
        assert f not in ci, f"{f} køres af CI og skal ikke stå som kun lokal"


def test_every_exclusion_carries_a_reason():
    script = _step_run(_python_job(CI.read_text(encoding="utf-8")))
    linjer = script.splitlines()
    for i, l in enumerate(linjer):
        if l.strip().startswith(("--ignore=", "--deselect=")):
            # Nærmeste ikke-udelukkelseslinje ovenfor skal være en kommentar (årsagen).
            j = i - 1
            while j >= 0 and linjer[j].strip().startswith(("--ignore=", "--deselect=")):
                j -= 1
            assert j >= 0 and linjer[j].strip().startswith("#"), f"udelukkelse uden årsag: {l.strip()}"
