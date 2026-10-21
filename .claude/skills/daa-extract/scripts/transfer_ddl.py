#!/usr/bin/env python3
"""DDL-overførslen for 5a+5b (plan A Task 2): afbrudsfiler, fortrydelsens DROP-liste og datadelta.

  prefix      --migrations <sti> --point <punkt> --out <sti>
  removal-sql --before <kataloglinjer> --after <kataloglinjer> --out <sti>
  data-delta  --before <tabelhashes> --after <tabelhashes> --allow <fil>

Kataloglinjer er transfer_catalog_fingerprint.sql's: <del>|<art>|<identitet>|<md5>|<ejet>. Kun den portable
del (P) bruges. Fejl er navngivne koder (SystemExit), aldrig fri tekst i genereret SQL.
"""
import argparse
import hashlib
import os
import re
import sys

POINTS = {
    "after-153-commit": ("COMMIT;", 0),
    "in-5a-cutover": ("-- END 5a-cutover", 0),
    "in-function-window": (
        "REVOKE ALL ON FUNCTION red_identity_candidate_input(bigint,jsonb) FROM PUBLIC,anon,authenticated;", -1),
}
# Rækkefølge og DROP-form pr. art; c/k/i/t/p følger relationen eller genskabes af restoren.
DROP = [("v", "VIEW"), ("m", "MATERIALIZED VIEW"), ("f", "ROUTINE"), ("r", "TABLE"), ("s", "SEQUENCE"),
        ("y", "TYPE"), ("o", "DOMAIN")]
DROP_KINDS = {k for k, _ in DROP}
SUB_KINDS = {"c", "k", "i", "t", "p"}
IDENT = re.compile(r'^[a-z_][a-z0-9_]*\.[a-z_][a-z0-9_]*(\([a-z0-9_ ,."\[\]]*\))?$')
EMPTY_SHA = hashlib.sha256(b"").hexdigest()


def _sha(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def _write_new(path, text):
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write(text)


def prefix(migrations, point, out):
    lines = open(migrations, encoding="utf-8").read().splitlines(keepends=True)
    if point == "before-rls":
        n = len(lines)
    elif point in POINTS:
        marker, offset = POINTS[point]
        hits = [i for i, l in enumerate(lines) if l.rstrip("\n") == marker]
        if len(hits) != 1:
            raise SystemExit("PREFIX_MARKER")
        n = hits[0] + 1 + offset
    else:
        raise SystemExit("PREFIX_POINT")
    text = "".join(lines[:n])
    _write_new(out, text)
    return n, _sha(text)


def _portable(lines):
    """art|identitet -> (md5, ejet) for de portable linjer."""
    d = {}
    for raw in lines:
        raw = raw.rstrip("\n")
        if not raw:
            continue
        f = raw.split("|")
        if len(f) != 5 or f[0] not in ("P", "L"):
            raise SystemExit("CATALOG_LINE")
        if f[0] == "P":
            d[(f[1], f[2])] = (f[3], f[4])
    return d


def removal_sql(before, after):
    b, a = _portable(before), _portable(after)
    new = sorted(set(a) - set(b))
    new_rel = {ident for kind, ident in new if kind == "r"}
    drops, skipped = {k: [] for k in DROP_KINDS}, 0
    for kind, ident in new:
        if kind in DROP_KINDS:
            if not IDENT.match(ident):
                raise SystemExit("REMOVAL_IDENTITY")
            if kind == "s" and a[(kind, ident)][1] == "1":
                skipped += 1  # kolonne-ejet sekvens (serial/identity): PG afviser DROP; restoren fjerner den
                continue
            drops[kind].append(ident)
        elif kind in SUB_KINDS:
            # Kommer aldrig i SQL (navne kan have mellemrum/æøå); relationen er de to første led.
            if ".".join(ident.split(".", 2)[:2]) not in new_rel:
                skipped += 1
        else:
            raise SystemExit("CATALOG_KIND")
    body = ["BEGIN;"]
    for kind, word in DROP:
        for ident in sorted(drops[kind], key=lambda s: s.encode("utf-8")):
            body.append(f"DROP {word} IF EXISTS {ident} CASCADE;")
    body.append("COMMIT;")
    stats = {"drop": sum(len(v) for v in drops.values()), "skipped_existing": skipped,
             "removed_by_ddl": len(set(b) - set(a))}
    return "\n".join(body) + "\n", stats


def _table_hashes(lines):
    d = {}
    for raw in lines:
        raw = raw.strip()
        if not raw:
            continue
        name, sep, h = raw.partition("=")
        if not sep or not h or not re.fullmatch(r"[a-z_][a-z0-9_]*\.[a-z_][a-z0-9_]*", name) or name in d:
            raise SystemExit("TABLE_HASH_LINE")
        d[name] = h
    return d


def data_delta(before, after, allow):
    b, a = _table_hashes(before), _table_hashes(after)
    changed = new = 0
    for name in sorted(set(b) | set(a)):
        if name in b and name in a:
            if b[name] != a[name]:
                if name not in allow:
                    raise SystemExit("DATA_DELTA_UNEXPECTED")
                changed += 1
        elif name in b:
            if name not in allow:
                raise SystemExit("DATA_DELTA_UNEXPECTED")
            changed += 1
        else:
            if a[name] != EMPTY_SHA:
                raise SystemExit("DATA_DELTA_UNEXPECTED")
            new += 1
    return {"changed": changed, "new": new}


def _read_allow(path):
    out = set()
    for raw in open(path, encoding="utf-8"):
        tok = raw.split("#", 1)[0].strip()
        if tok:
            out.add(tok.split()[0])
    return out


def main(argv=None):
    p = argparse.ArgumentParser(prog="transfer_ddl.py")
    sub = p.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("prefix")
    s.add_argument("--migrations", required=True)
    s.add_argument("--point", required=True, choices=sorted(list(POINTS) + ["before-rls"]))
    s.add_argument("--out", required=True)
    s = sub.add_parser("removal-sql")
    s.add_argument("--before", required=True)
    s.add_argument("--after", required=True)
    s.add_argument("--out", required=True)
    s = sub.add_parser("data-delta")
    s.add_argument("--before", required=True)
    s.add_argument("--after", required=True)
    s.add_argument("--allow", required=True)
    args = p.parse_args(argv)
    if args.cmd == "prefix":
        n, sha = prefix(args.migrations, args.point, args.out)
        print(f"PREFIX_OK point={args.point} lines={n} sha256={sha}")
    elif args.cmd == "removal-sql":
        sql, st = removal_sql(open(args.before, encoding="utf-8").read().splitlines(),
                              open(args.after, encoding="utf-8").read().splitlines())
        _write_new(args.out, sql)
        print(f"REMOVAL_OK drop={st['drop']} skipped_existing={st['skipped_existing']} "
              f"removed_by_ddl={st['removed_by_ddl']} sha256={_sha(sql)}")
    else:
        st = data_delta(open(args.before, encoding="utf-8").read().splitlines(),
                        open(args.after, encoding="utf-8").read().splitlines(), _read_allow(args.allow))
        print(f"DATA_DELTA_OK changed={st['changed']} new={st['new']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
