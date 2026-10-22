"""Trin 5a+5b-overførslen (plan B1 Task 5): overfør menneskets svar fra beviskædens ark til arbejdskørslens ark via nøgler.

Hver svarlinje (`<T> <ref> <ver> … : <svar>`) parses efter værktøjets grammatik. Ref'en oversættes gammelt uuid → nøgle
(nøglekortets opslagsklasse, transfer_5ab_keymap.sql) → nyt uuid; en interpretation_key er selv en nøgle og står uændret.
Svar, der peger på en person via en plads (kontrolkortets `R … A`, undtagelsesarkets `S`, ægteskabsarkets `M … S`, køens
`same <person>`), kræver, at samme person står på samme plads i det nye ark, ellers ANSWER_PERSON_MOVED. Det nye ark skrives
med de overførte svar; rapporten viser hver blok (kontekst og svarlinje) før og efter oversættelse til nøgler, markeret
`=`, `~`, `-`, `+`. Arkene rummer navne og kildetekst; stdout har kun antal og en hash."""
from __future__ import annotations

import argparse
import difflib
import hashlib
import json
import os
import re
import sys
from dataclasses import dataclass, field, replace
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))   # -I tilføjer ikke scriptets mappe
from decision_sheet_core import SheetError  # noqa: E402

UUID = r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"
UUID_RE = re.compile(UUID)
LINE = re.compile(rf"^(?P<t>[A-Z]) (?P<ref>{UUID}) (?P<ver>[0-9]+)(?P<mid>(?: [^:]*?)?) : (?P<ans>.*)$")
OLD_O = re.compile(rf"^O (?P<ref>{UUID}) (?P<mid>[0-9?]+/[0-9?]+) : (?P<ans>.*)$")   # undtagelsesarket v1 (versions-id)
LOOSE = re.compile(rf"^[A-Z] {UUID} ")
LOOKUP = ("persona:", "fortolkning:", "kandidatkoersel:", "kandidat:", "kontrol:", "foraelderkort:", "stikproeve:", "omtale:",
          "binding:", "disposition:")
# Pr. ark: linjetyper og deres ref (persona-uuid eller interpretation_key); `skip` står tomme i det nye ark (kontrolarkets
# blinde D-linjer får en ny stikprøve).
KINDS = {"control": ({"R": "ikey"}, {"D"}), "spouse": ({"S": "persona", "O": "ikey"}, set()), "queue": ({"Q": "persona"}, set()),
         "marriage": ({"M": "ikey"}, set()), "marriage_v3": ({"M": "ikey", "P": "persona"}, set()), "child": ({"C": "ikey"}, set())}


@dataclass
class Keymap:
    fwd: dict[str, str]
    rev: dict[str, str]


def load_keymap(path: Path) -> Keymap:
    fwd: dict[str, str] = {}; rev: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        u, _, k = line.partition("|")
        if u in fwd:
            raise SheetError("KEYMAP_DUPLICATE uuid")
        fwd[u] = k
        if k.startswith(LOOKUP):
            if k in rev:
                raise SheetError("KEYMAP_DUPLICATE nøgle")
            rev[k] = u
    return Keymap(fwd, rev)


@dataclass
class Answer:
    n: int            # ordinal blandt arkets svarlinjer (1-baseret)
    t: str
    ref: str          # arkets eget uuid
    key: str          # nøglen (persona:… eller ikey:…)
    ver: int
    mid: str
    ans: str
    idx: int          # linjenummer i arket (0-baseret)
    context: list[str] = field(default_factory=list)

    @property
    def tok(self) -> str:
        return self.ans.split("#")[0].split()[0] if self.ans.split("#")[0].split() else ""


def parse(text: str, kind: str, km: Keymap, *, old: bool) -> list[Answer]:
    types, skip = KINDS[kind]
    out: list[Answer] = []; ctx: list[str] = []
    for idx, line in enumerate(text.splitlines()):
        m = LINE.match(line)
        if not m and old and kind == "spouse" and line.startswith("O "):
            o = OLD_O.match(line)
            if o:
                k = km.fwd.get(o["ref"], "")
                fm = re.fullmatch(rf"fortolkning:({UUID})#([0-9]+)", k)
                if not fm:
                    raise SheetError(f"ANSWER_REF_UNKNOWN {len(out) + 1}")
                out.append(Answer(len(out) + 1, "O", fm[1], "ikey:" + fm[1], int(fm[2]), " " + o["mid"], o["ans"], idx, ctx))
                ctx = []
                continue
        if not m:
            if LOOSE.match(line) and line[0] in set(types) | skip:
                raise SheetError(f"ANSWER_LINE_INVALID {len(out) + 1}")
            if line.strip():
                ctx.append(line)
            continue
        t = m["t"]
        if t not in types and t not in skip:
            raise SheetError(f"ANSWER_LINE_INVALID {len(out) + 1}")
        if types.get(t) == "persona" or t in skip:
            key = km.fwd.get(m["ref"], "")
            if not key.startswith("persona:"):
                raise SheetError(f"ANSWER_REF_UNKNOWN {len(out) + 1}")
        else:
            key = "ikey:" + m["ref"]
        out.append(Answer(len(out) + 1, t, m["ref"], key, int(m["ver"]), m["mid"], m["ans"], idx, ctx))
        ctx = []
    return out


# Personen bag et pladssvar; None = svaret peger ikke på en plads.
def _propose_v2(rows: dict, key: str, navn: str | None):
    from relation_persona_extract_v2 import propose
    row = next(r for r in rows["rows"] if r["interpretation_key"] == key)
    return propose(row, int(rows["deceased_cutoff_year"])).get("partner_person_id")


def _propose_v3(rows: dict, key: str, navn: str | None):
    from relation_persona_extract_v3 import NameOverrideError, propose
    row = next(r for r in rows["rows"] if r["interpretation_key"] == key)
    try:
        return propose(row, int(rows["deceased_cutoff_year"]), name_override=navn).get("partner_person_id")
    except NameOverrideError:
        return None


PROPOSE = {"marriage": _propose_v2, "marriage_v3": _propose_v3}
NAVN = re.compile(r"navn:\s*»([^»«]+)«")


def person_of(kind: str, a: Answer, rows) -> tuple | None:
    tok = a.tok
    if kind == "spouse" and a.t == "S" and tok == "S":
        return ("kandidat1", next((r["candidate_person_id"] for r in rows["s_rows"] if r["source_persona_id"] == a.ref), None))
    if kind == "control" and a.t == "R" and tok == "A":
        it = next((x for x in rows["items"] if x.get("kind") == "parent" and x["interpretation_key"] == a.ref), {})
        cp = [(i, p.get("name"), p.get("born"), p.get("died"), p.get("own_post_key"))
              for i, p in enumerate(it.get("partners") or []) if p.get("counterpart")]
        return ("modpart", it.get("family_id"), tuple(cp))
    if kind == "queue" and tok == "same":
        person = int(a.ans.split("#")[0].split()[1])
        d = next((x for x in rows if x["persona"]["source_persona_id"] == a.ref), {})
        for i, pp in enumerate(d.get("principal_partners") or []):
            if pp.get("person_id") == person:
                return ("partner", i, person)
        for c in d.get("candidates") or []:
            if c.get("person_id") == person:
                return ("kandidat", c.get("rank"), person)
        return ("ingen", person)
    if kind in PROPOSE and a.t == "M" and tok == "S":
        nm = NAVN.search(a.ans)
        return ("forslag", PROPOSE[kind](rows, a.ref, nm[1] if nm else None))
    return None


def _keyed(text: str, km: Keymap) -> str:
    return UUID_RE.sub(lambda m: km.fwd.get(m[0], m[0]), text)


@dataclass
class Result:
    sheet: str
    report: str
    transferred: int
    dropouts: int
    changed: int


def transfer(kind: str, old_sheet: str, new_sheet: str, old_rows, new_rows, old_km: Keymap, new_km: Keymap,
             dropouts: set[str]) -> Result:
    if kind not in KINDS:
        raise SheetError("ANSWER_KIND_UNKNOWN")
    _, skip = KINDS[kind]
    olds = [a for a in parse(old_sheet, kind, old_km, old=True) if a.t not in skip]
    news_all = parse(new_sheet, kind, new_km, old=False)
    news = {(a.t, a.key): a for a in news_all if a.t not in skip}
    lines = new_sheet.splitlines()
    report: list[str] = []
    done: set[tuple[str, str]] = set()
    n_tr = n_drop = n_changed = 0
    for a in olds:
        b = news.get((a.t, a.key))
        if b is None:
            if a.key in dropouts:
                n_drop += 1
                report += ["", f"## bortfald {a.t} {a.key}"] + [f"- {_keyed(c, old_km)}" for c in a.context] + [
                    f"- {_keyed(old_sheet.splitlines()[a.idx], old_km)}"]
                continue
            raise SheetError(f"ANSWER_NO_TARGET {a.n}")
        if b.ver != a.ver:
            raise SheetError(f"ANSWER_VERSION_CHANGED {a.n}")
        po = person_of(kind, a, old_rows)
        # Det overførte svar læses mod det nye arks rækker (samme svar, ny plads).
        if po is not None and po != person_of(kind, replace(b, ans=a.ans), new_rows):
            raise SheetError(f"ANSWER_PERSON_MOVED {a.n}")
        out_line = f"{b.t} {b.ref} {b.ver}{b.mid} : {a.ans}"
        lines[b.idx] = out_line
        done.add((b.t, b.key)); n_tr += 1
        old_block = [_keyed(c, old_km) for c in a.context] + [f"{a.t} {a.key} {a.ver}{a.mid} : {a.ans}"]
        new_block = [_keyed(c, new_km) for c in b.context] + [f"{b.t} {b.key} {b.ver}{b.mid} : {a.ans}"]
        block, changed = _diff(old_block, new_block)
        n_changed += changed
        report += ["", f"## {b.t} {b.key}"] + block
    for b in news.values():
        if (b.t, b.key) in done:
            continue
        if b.key in dropouts:
            n_drop += 1
            report += ["", f"## bortfald {b.t} {b.key}"] + [f"+ {_keyed(c, new_km)}" for c in b.context] + [
                f"+ {_keyed(lines[b.idx], new_km)}"]
            continue
        raise SheetError(f"ANSWER_NO_SOURCE {b.n}")
    end = "\n" if new_sheet.endswith("\n") else ""
    return Result("\n".join(lines) + end, "\n".join(report).lstrip("\n") + "\n", n_tr, n_drop, n_changed)


def _diff(old: list[str], new: list[str]) -> tuple[list[str], int]:
    out: list[str] = []
    for op, i1, i2, j1, j2 in difflib.SequenceMatcher(a=old, b=new, autojunk=False).get_opcodes():
        if op == "equal":
            out += [f"= {x}" for x in old[i1:i2]]
        elif op == "replace":
            out += [f"~ - {x}" for x in old[i1:i2]] + [f"~ + {x}" for x in new[j1:j2]]
        elif op == "delete":
            out += [f"- {x}" for x in old[i1:i2]]
        else:
            out += [f"+ {x}" for x in new[j1:j2]]
    return out, int(any(not x.startswith("= ") for x in out))


def check_private_path(path: Path, root: Path) -> Path:
    root_r = root.resolve()
    if path.is_symlink():
        raise SheetError("SHEET_PATH_SYMLINK")
    p = path.resolve()
    if root_r not in p.parents:
        raise SheetError("SHEET_PATH_NOT_PRIVATE")
    for parent in [p.parent, *p.parent.parents]:
        if (parent / ".git").exists():
            raise SheetError("SHEET_PATH_IN_GIT")
    return p


def _write_new(path: Path, text: str) -> None:
    try:
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    except FileExistsError:
        raise SheetError("ANSWER_OUT_EXISTS") from None
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        fh.write(text)


def main() -> int:
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    t = sub.add_parser("transfer")
    t.add_argument("--kind", required=True, choices=sorted(KINDS))
    for a in ("--old-sheet", "--old-rows", "--old-keymap", "--new-sheet", "--new-rows", "--new-keymap", "--expected-dropouts",
              "--out-sheet", "--out-report"):
        t.add_argument(a, required=True)
    t.add_argument("--private-root", default=str(Path.home() / ".private"))
    args = ap.parse_args()
    root = Path(args.private_root)
    try:
        p = {k: check_private_path(Path(getattr(args, k)), root) for k in
             ("old_sheet", "old_rows", "old_keymap", "new_sheet", "new_rows", "new_keymap", "expected_dropouts", "out_sheet", "out_report")}
        drops = {l.strip() for l in p["expected_dropouts"].read_text(encoding="utf-8").splitlines()
                 if l.strip() and not l.lstrip().startswith("#")}
        r = transfer(args.kind, p["old_sheet"].read_text(encoding="utf-8"), p["new_sheet"].read_text(encoding="utf-8"),
                     json.loads(p["old_rows"].read_text(encoding="utf-8")), json.loads(p["new_rows"].read_text(encoding="utf-8")),
                     load_keymap(p["old_keymap"]), load_keymap(p["new_keymap"]), drops)
        _write_new(p["out_sheet"], r.sheet)
        _write_new(p["out_report"], r.report)
    except SheetError as exc:
        raise SystemExit(str(exc).split(" — ")[0])
    print(f"ANSWERS_OK kind={args.kind} overfoert={r.transferred} bortfald={r.dropouts} aendret={r.changed} "
          f"report_sha256={hashlib.sha256(r.report.encode('utf-8')).hexdigest()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
