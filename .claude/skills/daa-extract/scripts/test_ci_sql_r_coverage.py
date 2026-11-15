"""Review 36, D3: hver SQL-/shell-/R-testfil skal enten køres af CI eller stå på en begrundet liste.

Før denne vagt kørte 22 filer under `tests/sql/` og `tests/integration/` aldrig i CI, uden at noget
sagde fra; én af dem (C3's portræt/sletnings-låsetest) var rød på en prod-lignende base fra start.

Vagten læser det rigtige `.github/workflows/ci.yml` og følger kun *kørsler* — `psql -f`, `\\i`/`\\ir`,
`bash`, `Rscript` og `for x in …; do`-løkker, der udfylder et `$x` i sådan en kørsel — rekursivt ind i de
scripts, CI kører. Kommentarer fjernes først, så en fil, der blot nævnes i en kommentar, ikke tæller.
Den fejler, hvis

* en kandidat (`tests/sql/test-*.sql|sh`, `tests/sql/inspect-*.sql`, `tests/integration/*.R`) hverken
  nås eller står i `tests/ikke-i-ci.txt`;
* en linje i listen mangler begrundelse, peger på en fil, der ikke findes, eller på en fil, CI faktisk
  kører — en forældet undtagelse skjuler ellers, at listen er gledet.
"""
from __future__ import annotations

import re
from pathlib import Path

REPO = Path(__file__).resolve().parents[4]
CI = REPO / ".github" / "workflows" / "ci.yml"
SKIP = REPO / "tests" / "ikke-i-ci.txt"

# Et kørsels-token: det, der står efter -f / \i / \ir / bash / Rscript.
_EXEC = re.compile(r"""(?:(?<![\w-])-f|\\ir?|(?<![\w-])bash|(?<![\w-])Rscript)\s+["']?([^\s"';|&)]+)""")
_FOR = re.compile(r"\bfor\s+(\w+)\s+in\s+(.*?);\s*do\b(.*?)\bdone\b", re.S)


def _candidates() -> list[Path]:
    # Kun disse tre mønstre og ét niveau: aldrig en rekursiv søgning (invariant 8).
    files = [*REPO.glob("tests/sql/test-*.sql"), *REPO.glob("tests/sql/test-*.sh"),
             *REPO.glob("tests/sql/inspect-*.sql"), *REPO.glob("tests/integration/*.R")]
    return sorted(p.resolve() for p in files)


def _strip_comments(text: str, suffix: str) -> str:
    if suffix == ".sql":
        return re.sub(r"--[^\n]*", "", text)
    # yml/sh/R: hele kommentarlinjer og efterstillede ` # …`.
    return re.sub(r"(?m)(^|\s)#[^\n]*", r"\1", text)


def _refs(text: str, here: Path) -> set[Path]:
    """Filer, som teksten kører. `here` er mappen, relative \\ir-stier løses fra."""
    tokens = [m.group(1) for m in _EXEC.finditer(text)]
    for var, words, body in _FOR.findall(text):
        for m in _EXEC.finditer(body):
            tok = m.group(1)
            if f"${var}" in tok or f"${{{var}}}" in tok:
                for w in words.split():
                    w = w.strip("\"'")
                    tokens.append(tok.replace(f"${{{var}}}", w).replace(f"${var}", w))
    out = set()
    for tok in tokens:
        if "$" in tok:
            continue
        for base in (REPO, here):
            p = (base / tok).resolve()
            if p.is_file():
                out.add(p)
                break
    return out


def reached(ci_text: str) -> set[Path]:
    seen: set[Path] = set()
    frontier = list(_refs(_strip_comments(ci_text, ".yml"), REPO))
    while frontier:
        f = frontier.pop()
        if f in seen:
            continue
        seen.add(f)
        if f.suffix in {".sql", ".sh", ".R"} and REPO in f.parents:
            frontier.extend(_refs(_strip_comments(f.read_text(errors="ignore"), f.suffix), f.parent))
    return seen


def _skip_list() -> dict[Path, str]:
    out = {}
    for n, line in enumerate(SKIP.read_text(encoding="utf-8").splitlines(), 1):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        sti, _, grund = line.partition("|")
        assert grund.strip(), f"{SKIP.name}:{n}: mangler begrundelse efter '|'"
        out[(REPO / sti.strip()).resolve()] = grund.strip()
    return out


def test_every_sql_and_r_test_is_run_or_listed():
    run = reached(CI.read_text(encoding="utf-8"))
    skip = _skip_list()
    uden_for = [str(f.relative_to(REPO)) for f in _candidates() if f not in run and f not in skip]
    assert uden_for == [], f"testfiler, CI hverken kører eller lister i {SKIP.name}: {uden_for}"


def test_skip_list_entries_exist_and_are_not_run():
    run = reached(CI.read_text(encoding="utf-8"))
    skip = _skip_list()
    mangler = [str(p.relative_to(REPO)) for p in skip if not p.is_file()]
    koeres = [str(p.relative_to(REPO)) for p in skip if p in run]
    assert mangler == [], f"{SKIP.name} peger på filer, der ikke findes: {mangler}"
    assert koeres == [], f"{SKIP.name} lister filer, CI faktisk kører: {koeres}"


def test_guard_sees_a_removed_run_line():
    # Negativ kontrol: fjernes én kørselslinje fra ci.yml, er filen ikke længere nået.
    target = REPO / "tests/integration/test-reimport-writer.R"
    ci = CI.read_text(encoding="utf-8")
    assert target.resolve() in reached(ci)
    uden = "\n".join(l for l in ci.splitlines() if "test-reimport-writer.R" not in l)
    assert target.resolve() not in reached(uden)


def test_guard_ignores_comments_and_follows_loops():
    sql = REPO / "tests/sql/test-relation-child.sql"
    loop = "run: |\n  for t in test-relation-child; do psql -f \"tests/sql/$t.sql\"; done\n"
    assert sql.resolve() in reached(loop)
    assert sql.resolve() not in reached("  # psql -f tests/sql/test-relation-child.sql\n")
