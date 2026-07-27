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

def test_slaegtled_header_bloeder_ikke_ind_i_forrige_post():
    # Reproducerer prod-fejlen (14 poster i 2018-20-udgaven, audit 2026-07-26): en bar
    # slaegtled-overskrift ("Tredje (sekstende) slægtled") stod alene paa sin egen linje
    # efter en tom linje, men blev alligevel opfattet som fortsaettelse af FORRIGE post i
    # stedet for at trigge SLGT_RE og starte en ny sektion.
    raw = textwrap.dedent("""\
        I  DEN HOLSTENSKE LINJE
        Andet slægtled
        9.        Komtesse Caroline Mathilde – * 1767, døbt s.m. i Hof- og
                  Slotskirken, † 1834 i Itzehoe. – Konventualinde i Itzehoe Adelige
                  Kloster.

                                          Tredje (sekstende) slægtled

        10.       Komtesse Margaretha – * 1786, begravet 1787.
        """)
    posts = _run(raw)
    ni = [p for p in posts if p["nr"] == 9][0]
    ti = [p for p in posts if p["nr"] == 10][0]
    assert "slægtled" not in ni["raw_text"]
    assert ni["raw_text"].rstrip().endswith("Kloster.")
    assert ti["slaegtled_lokal"] == 3
    assert ti["slaegtled_gennem"] == 16


def test_slaegtled_header_med_efterfoelgende_kuld_bloeder_ikke_ind():
    # Skarpere variant af samme fejl (IV/1, IV/85, V/1, V/17 i audit): headeren blev
    # efterfulgt af en KULD-markoer ("I" + "<titel> <navns> børn") der OGSAA bloedte ind,
    # fordi cur aldrig blev nulstillet foer disse linjer blev naaet.
    raw = textwrap.dedent("""\
        IV  DEN LENSGREVELIGE LINJE
        Første slægtled
        1.        Lensgreve Detlef til Altenhof – * 1700, † 1762, bisat i
                  Reventlowske Gravkapel i Sarau Kirke. – 9 børn.

                                          Andet (femtende) slægtled

                                                     I
                              Overkammerherre Detlef lensgreve de Reventlous børn

                  af første ægteskab med Wilhelmina komtesse af Bernstorff:

        2.        Komtesse Margaretha – * 1786.
        """)
    posts = _run(raw)
    en = [p for p in posts if p["nr"] == 1][0]
    to = [p for p in posts if p["nr"] == 2][0]
    assert "slægtled" not in en["raw_text"]
    assert "Overkammerherre" not in en["raw_text"]
    assert en["raw_text"].rstrip().endswith("9 børn.")
    assert to["slaegtled_lokal"] == 2
    assert to["slaegtled_gennem"] == 15
    assert to["aegteskab_kontekst"] == "af første ægteskab med Wilhelmina komtesse af Bernstorff"
