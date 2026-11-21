#!/usr/bin/env python3
"""Trin ③c: læg hændelser uden nogen datogrænse til side før load.

Kører efter validering og eskalering. Hændelser hvor hverken date_min eller date_max
kunne udledes (heller ikke via H9-kontekstopløsning) fjernes fra clean.json og skrives
til en parkeringsfil til senere redaktionel gennemgang eller beslutning om at droppe.
Narrativet bliver i clean.json (evt. med tom liste), så loaderens merge stadig dækker det.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from validate_haendelser import _write_json, parker_udaterede


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("clean", help="clean.json; omskrives på stedet")
    parser.add_argument("--parkeret", required=True, help="parkeringsfil (overskrives)")
    args = parser.parse_args()

    clean = json.loads(Path(args.clean).read_text(encoding="utf-8"))
    if not isinstance(clean, list):
        raise SystemExit("clean.json skal være en liste")
    kept, parked = parker_udaterede(clean)
    _write_json(args.clean, kept)
    _write_json(args.parkeret, parked)
    beholdt = sum(len(r["haendelser"]) for r in kept)
    print(f"[parker-udaterede] {beholdt} beholdt, {len(parked)} parkeret", file=sys.stderr)


if __name__ == "__main__":
    main()
