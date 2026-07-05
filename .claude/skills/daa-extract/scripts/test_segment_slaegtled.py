import subprocess, sys, json, tempfile, os, textwrap

def _run(raw):
    with tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False, encoding="utf-8") as f:
        f.write(raw); path = f.name
    out = subprocess.run([sys.executable, "segment.py", path], capture_output=True, text=True,
                         cwd=os.path.dirname(__file__) or ".")
    os.unlink(path)
    return json.loads(out.stdout)

def test_single_ordinal_header():
    raw = textwrap.dedent("""\
        I  DEN HOLSTENSKE LINJE
        Første slægtled
        1.  Gottschalk Reventlow, nævnt 1223.
        """)
    posts = _run(raw)
    assert posts[0]["slaegtled_lokal"] == 1
    assert posts[0]["slaegtled_gennem"] is None

def test_dual_numbered_header():
    raw = textwrap.dedent("""\
        V  DEN YNGRE LINJE
        Første (tolvte) slægtled
        1.  Conrad Reventlow, 1644-1708.
        """)
    posts = _run(raw)
    assert posts[0]["slaegtled_lokal"] == 1
    assert posts[0]["slaegtled_gennem"] == 12
