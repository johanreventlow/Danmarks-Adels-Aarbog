"""Trin 5a+5b-overførslen (plan B1 Task 6): pakken for data-ceremonien (`transfer-pack-5ab-v1`).

Pakken beskriver arbejdskørslen som en række skridt (sql / writer / hash_gated) med de nøglede items' hash, skridtets lag
og lagenes digests før og efter (transfer_5ab_digests.sql). Genspilleren (B2's runner) går skridt for skridt: `classify`
over skridtets lag giver WRITE (tilstanden før), ALREADY_APPLIED (tilstanden efter, fx efter et afbrud mellem COMMIT og
logføringen) eller MIXED (alt andet; stop). Efter et skridt skal `classify` give ALREADY_APPLIED. `next` giver det første
skridt, der ikke er logført som færdigt. Lag overlapper mellem skridt (decide og reject skriver begge i interpretations), så
`classify` er kun meningsfuld for det næste skridt, aldrig for hele pakken bagefter.

  init       --pack P --d1-receipt-sha256 H --restore-hash H
  add-step   --pack P --name --type --script --vars J --inputs J --items-sha256 H --layers a,b --count N
             --digests-in F --digests-out F --seconds S
  validate   --pack P                          ⇒ PACK_OK steps=… pack_sha256=…   (ellers PACK_INVALID <felt>)
  classify   --pack P --n K --digests F        ⇒ WRITE | ALREADY_APPLIED | MIXED (exit 3)
  inventory-add --pack P --root R --private D --key repo:<sti>|private:<sti>  ⇒ PACK_INVENTORY_OK n=… pack_sha256=…
  inventory  --pack P --root R --private D     ⇒ INVENTORY_OK n=…               (ellers INVENTORY_MISMATCH <sti>)
  next       --pack P --done 1,2,…             ⇒ NEXT n=… name=… | NEXT_NONE
Et skridts `script` er en inventarnøgle (`repo:<sti>` eller `private:<sti>`). `inventory` kræver, at hvert skridts script og
alle filer, det trækker ind med `\\ir` (transitivt), står i inventaret med deres sha256. `validate` kræver kontinuitet: deler
to skridt et lag, er det senere skridts digest ind lig det tidligere skridts digest ud.
Pakken bærer ingen uuid'er; stdout har kun koder, tal og hashes."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))   # -I tilføjer ikke scriptets mappe
from decision_sheet_core import SheetError  # noqa: E402

VERSION = "transfer-pack-5ab-v1"
TYPES = ("sql", "writer", "hash_gated")
# Lagene fra transfer_5ab_digests.sql (Task 1). authorizations_issued er kun rapport: et afbrud efter autorisationen
# efterlader en issued-række, så laget må aldrig afgøre et skridts tilstand.
LAYERS = ("personas", "identities", "identity_events", "candidate_runs", "candidates", "control_runs", "control_samples",
          "control_exclusions", "control_parent_cards", "control_events", "control_parent_events", "interpretations", "parties",
          "classifications", "dispositions", "writer_profiles", "bindings", "family_sources", "authorizations_consumed",
          "authorizations_issued", "counts")
HEX64 = re.compile(r"[0-9a-f]{64}")
INCLUDE = re.compile(r"^\\ir\s+(\S+)\s*$", re.M)
KINDS = ("repo", "private")


def _canon(obj) -> bytes:
    return json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")


def pack_sha256(p: dict) -> str:
    return hashlib.sha256(_canon({k: v for k, v in p.items() if k != "pack_sha256"})).hexdigest()


def new_pack(*, d1_receipt_sha256: str, restore_hash: str) -> dict:
    p = {"version": VERSION, "base": {"d1_receipt_sha256": d1_receipt_sha256, "restore_hash": restore_hash}, "inventory": {},
         "steps": []}
    p["pack_sha256"] = pack_sha256(p)
    return p


def _layer_shas(digests: dict, layers: list[str]) -> dict[str, str]:
    try:
        return {lag: digests[lag]["sha256"] for lag in layers}
    except KeyError as exc:
        raise SheetError(f"PACK_INVALID digests {exc.args[0]}") from None


def add_step(p: dict, *, name: str, type: str, script: str, vars: dict, inputs: dict, items_sha256: str, layers: list[str],
             count: int, digests_in: dict, digests_out: dict, seconds: float) -> None:
    p["steps"].append({"n": len(p["steps"]) + 1, "name": name, "type": type, "script": script, "vars": vars, "inputs": inputs,
                       "items_sha256": items_sha256, "layers": list(layers), "count": int(count),
                       "digests_in": _layer_shas(digests_in, layers), "digests_out": _layer_shas(digests_out, layers),
                       "seconds": float(seconds)})
    p["pack_sha256"] = pack_sha256(p)


def validate(p: dict) -> None:
    def bad(felt):
        raise SheetError(f"PACK_INVALID {felt}")
    if p.get("version") != VERSION:
        bad("version")
    base = p.get("base") or {}
    if not all(HEX64.fullmatch(str(base.get(k, ""))) for k in ("d1_receipt_sha256", "restore_hash")):
        bad("base")
    if not isinstance(p.get("inventory"), dict) or not all(HEX64.fullmatch(str(v)) for v in p["inventory"].values()):
        bad("inventory")
    if not isinstance(p.get("steps"), list):
        bad("steps")
    last: dict[str, str] = {}
    for i, s in enumerate(p["steps"], 1):
        if s.get("n") != i:
            bad("n")
        if not s.get("name"):
            bad("name")
        kind, _, rel = str(s.get("script", "")).partition(":")
        if kind not in KINDS or not rel:
            bad("script")
        if s.get("type") not in TYPES:
            bad("type")
        if not isinstance(s.get("vars"), dict) or not isinstance(s.get("inputs"), dict) \
                or not all(HEX64.fullmatch(str(v)) for v in s["inputs"].values()):
            bad("inputs")
        if not HEX64.fullmatch(str(s.get("items_sha256", ""))):
            bad("items_sha256")
        layers = s.get("layers")
        if not isinstance(layers, list) or not layers or "authorizations_issued" in layers or not set(layers) <= set(LAYERS) \
                or len(set(layers)) != len(layers):
            bad("layers")
        if not isinstance(s.get("count"), int) or s["count"] < 0:
            bad("count")
        for k in ("digests_in", "digests_out"):
            d = s.get(k)
            if not isinstance(d, dict) or set(d) != set(layers) or not all(HEX64.fullmatch(str(v)) for v in d.values()):
                bad(k)
        # Et skridt, der skriver, skal flytte mindst ét af sine lag; ellers kan det ikke skelnes fra ALREADY_APPLIED.
        if s["count"] > 0 and s["digests_in"] == s["digests_out"]:
            bad("digests_out")
        # Kontinuitet: intet må have skrevet i et lag mellem to skridt, der begge har det (fx et skridt, der blev kørt
        # men ikke tilføjet). Ellers falder pakken først i genspillet som MIXED, efter at de tidligere skridt har skrevet.
        if any(last.get(lag, v) != v for lag, v in s["digests_in"].items()):
            bad("continuity")
        last.update(s["digests_out"])
    if p.get("pack_sha256") != pack_sha256(p):
        bad("pack_sha256")


def classify(p: dict, n: int, digests: dict) -> str:
    if not 1 <= n <= len(p["steps"]):
        raise SheetError("PACK_STEP_UNKNOWN")
    s = p["steps"][n - 1]
    cur = _layer_shas(digests, s["layers"])
    if cur == s["digests_out"]:
        return "ALREADY_APPLIED"
    if cur == s["digests_in"]:
        return "WRITE"
    return "MIXED"


def next_step(p: dict, done: set[int]) -> tuple[int, str] | None:
    return next(((s["n"], s["name"]) for s in p["steps"] if s["n"] not in done), None)


def _sha_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _resolve(key: str, root: Path, private: Path) -> Path:
    kind, _, rel = key.partition(":")
    if kind not in KINDS or not rel:
        raise SheetError(f"INVENTORY_MISMATCH {key}")
    base = (root if kind == "repo" else private).resolve()
    f = base / rel
    if f.is_symlink() or not f.is_file() or not f.resolve().is_relative_to(base):
        raise SheetError(f"INVENTORY_MISMATCH {key}")
    return f


def _includes(key: str, f: Path) -> list[str]:
    """Nøglerne for de filer, `f` trækker ind med `\\ir` (relativt til f's mappe, samme rod)."""
    kind, _, rel = key.partition(":")
    out = []
    for inc in INCLUDE.findall(f.read_text(encoding="utf-8")):
        out.append(f"{kind}:" + os.path.normpath(os.path.join(os.path.dirname(rel), inc)).replace(os.sep, "/"))
    return out


def check_inventory(p: dict, root: Path, private: Path) -> int:
    inv = p["inventory"]
    for key in sorted(inv):
        if _sha_file(_resolve(key, root, private)) != inv[key]:
            raise SheetError(f"INVENTORY_MISMATCH {key}")
    # Koden, der kører, skal være bundet: hvert skridts script og alt, det trækker ind (transitivt).
    todo, seen = [s["script"] for s in p["steps"]], set()
    while todo:
        key = todo.pop(0)
        if key in seen:
            continue
        seen.add(key)
        if key not in inv:
            raise SheetError(f"INVENTORY_MISMATCH {key}")
        f = _resolve(key, root, private)
        if f.suffix == ".sql":
            todo.extend(_includes(key, f))
    # Den private mappe må ikke rumme filer, pakken ikke kender (et ark eller manifest, der ikke er bundet).
    for f in sorted(x for x in private.rglob("*") if x.is_file()):
        key = "private:" + f.relative_to(private).as_posix()
        if key not in inv:
            raise SheetError(f"INVENTORY_MISMATCH {key}")
    return len(inv)


def inventory_add(p: dict, key: str, root: Path, private: Path) -> None:
    p["inventory"][key] = _sha_file(_resolve(key, root, private))
    p["pack_sha256"] = pack_sha256(p)


def read_digests(path: Path) -> dict:
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.startswith("daa.transfer_5ab_digests="):
            return json.loads(line.split("=", 1)[1])
    raise SheetError("PACK_DIGESTS_UNREADABLE")


def _load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def _save(path: Path, p: dict, *, new: bool = False) -> None:
    tmp = path.with_name(path.name + ".tmp")
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
    if new and path.exists():
        raise SheetError("PACK_EXISTS")
    if tmp.exists():
        tmp.unlink()
    fd = os.open(tmp, flags, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        fh.write(json.dumps(p, sort_keys=True, indent=1, ensure_ascii=False) + "\n")
    os.replace(tmp, path)


def main() -> int:
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    c = {k: sub.add_parser(k) for k in ("init", "add-step", "validate", "classify", "inventory-add", "inventory",
                                       "next")}
    for p in c.values():
        p.add_argument("--pack", required=True)
    c["init"].add_argument("--d1-receipt-sha256", required=True)
    c["init"].add_argument("--restore-hash", required=True)
    for a in ("--name", "--type", "--script", "--vars", "--inputs", "--items-sha256", "--layers", "--count", "--digests-in",
              "--digests-out", "--seconds"):
        c["add-step"].add_argument(a, required=True)
    c["classify"].add_argument("--n", required=True, type=int)
    c["classify"].add_argument("--digests", required=True)
    for k in ("inventory", "inventory-add"):
        c[k].add_argument("--root", required=True)
        c[k].add_argument("--private", required=True)
    c["inventory-add"].add_argument("--key", required=True)
    c["next"].add_argument("--done", required=True)
    args = ap.parse_args()
    pk = Path(args.pack)
    try:
        if args.cmd == "init":
            _save(pk, new_pack(d1_receipt_sha256=args.d1_receipt_sha256, restore_hash=args.restore_hash), new=True)
            validate(_load(pk))
            print("PACK_INIT_OK")
            return 0
        p = _load(pk)
        if args.cmd == "add-step":
            validate(p)
            add_step(p, name=args.name, type=args.type, script=args.script, vars=json.loads(args.vars),
                     inputs=json.loads(args.inputs), items_sha256=args.items_sha256, layers=args.layers.split(","),
                     count=int(args.count), digests_in=read_digests(Path(args.digests_in)),
                     digests_out=read_digests(Path(args.digests_out)), seconds=float(args.seconds))
            validate(p)
            _save(pk, p)
            print(f"PACK_STEP_OK n={len(p['steps'])} pack_sha256={p['pack_sha256']}")
            return 0
        validate(p)
        if args.cmd == "inventory-add":
            inventory_add(p, args.key, Path(args.root), Path(args.private))
            validate(p)
            _save(pk, p)
            print(f"PACK_INVENTORY_OK n={len(p['inventory'])} pack_sha256={p['pack_sha256']}")
        elif args.cmd == "validate":
            print(f"PACK_OK steps={len(p['steps'])} pack_sha256={p['pack_sha256']}")
        elif args.cmd == "classify":
            state = classify(p, args.n, read_digests(Path(args.digests)))
            print(state)
            return 3 if state == "MIXED" else 0
        elif args.cmd == "inventory":
            print(f"INVENTORY_OK n={check_inventory(p, Path(args.root), Path(args.private))}")
        else:
            done = {int(x) for x in args.done.split(",") if x.strip()}
            nxt = next_step(p, done)
            print(f"NEXT n={nxt[0]} name={nxt[1]}" if nxt else "NEXT_NONE")
    except SheetError as exc:
        raise SystemExit(str(exc))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
