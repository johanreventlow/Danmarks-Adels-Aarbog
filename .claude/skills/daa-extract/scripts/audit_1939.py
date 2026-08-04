#!/usr/bin/env python3
"""Read-only structural audit for a 1939 Calamari rendition."""

import argparse
import contextlib
import io
import json
from pathlib import Path

import segment


def main(argv=None):
    parser = argparse.ArgumentParser(description="Udskriv 1939-segmenteringssummary uden persontekst.")
    parser.add_argument("--input", required=True, type=Path)
    args = parser.parse_args(argv)
    text = args.input.read_text(encoding="utf-8")
    with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
        posts = segment._segment_1939(text.splitlines(), segment.UDGAVE_PROFILER["1939"])
    print(json.dumps(segment.segmentation_summary_1939(posts, text), ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
