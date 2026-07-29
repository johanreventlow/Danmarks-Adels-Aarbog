import os, sys, io, tempfile, contextlib, unittest
sys.path.insert(0, os.path.dirname(__file__))
import segment


def run_segment(text):
    """Kør segment.main på en midlertidig råtekst; returnér posts (undertryk stdout/stderr)."""
    with tempfile.NamedTemporaryFile('w', suffix='.txt', delete=False, encoding='utf-8') as fh:
        fh.write(text); path = fh.name
    try:
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            return segment.main(path)
    finally:
        os.unlink(path)


class TestMarrRegex(unittest.TestCase):
    def test_matcher_bar_kolon(self):
        self.assertTrue(segment.MARR_RE.match("af andet ægteskab med Anna Hedwig von Qualen:"))

    def test_matcher_kolon_bindestreg(self):
        # DAA-bogen skriver undertiden "...:-" (kolon + bindestreg). Skal stadig matche,
        # ellers klæber den forrige heading til det næste barn (III-85-fejlen).
        m = segment.MARR_RE.match("af første ægteskab med Catharina von Brockdorff:-")
        self.assertTrue(m)
        self.assertEqual(segment.norm(m.group(1)), "af første ægteskab med Catharina von Brockdorff")

    def test_matcher_med_krydsref_og_bindestreg(self):
        self.assertTrue(segment.MARR_RE.match("med Beke von Pogwisch (se nr. 16):-"))


class TestKolonBindestregBleed(unittest.TestCase):
    def test_bindestreg_heading_klaeber_ikke_til_naeste_barn(self):
        # Reproducerer III-85: en "(se nr. N):"-heading, derefter en "...:-"-heading,
        # derefter et barn. Barnet SKAL få den nærmeste (:-)-heading, ikke den forrige.
        raw = "\n".join([
            "### PAGE 1 ###",
            "        55.       Iwan, til Roest. – Gift med NN.",
            "                  med Margaretha von Rumohr (se nr. 55):",
            "        84.       Sophie – * 1670.",
            "                  af første ægteskab med Catharina von Brockdorff:-",
            "        85.       Detlef – * 2. okt. 1673, † 1. marts 1674.",
            "                  af andet ægteskab med Anna Hedwig von Qualen:",
            "        86.       Abel – * 1675.",
        ])
        posts = run_segment(raw)
        by = {p["nr"]: p.get("aegteskab_kontekst") for p in posts}
        self.assertEqual(by.get(85), "af første ægteskab med Catharina von Brockdorff")
        self.assertEqual(by.get(86), "af andet ægteskab med Anna Hedwig von Qualen")
        # barn 84 hører til den forrige (Rumohr)-heading
        self.assertEqual(by.get(84), "med Margaretha von Rumohr (se nr. 55)")


class TestLokalId(unittest.TestCase):
    """lokal_id = bogens egen strukturelle adresse (linje.nr_label) — TRYKT,
    ikke beregnet. Halvdelen af identitetsregisterets lokator; en overset post
    må aldrig forskyde naboernes identitet (jf. test_perturbation.py)."""

    RAW = "\n".join([
        "### PAGE 1 ###",
        "I",
        "DEN HOLSTENSKE LINJE",
        "        1.       Gottschalk, nævnes 1237.",
        "        15a.       Claus, til Aalebæk.",
        "        15b.       Ditlev, broder til 15a.",
    ])

    def test_lokal_id_er_linje_punkt_nr_label(self):
        posts = run_segment(self.RAW)
        self.assertEqual([p["lokal_id"] for p in posts], ["I.1", "I.15a", "I.15b"])

    def test_suffiks_poster_faar_hver_sin_identitet(self):
        # 15a/15b er DISTINKTE personer — nr alene ville give kollision.
        posts = run_segment(self.RAW)
        self.assertEqual(len({p["lokal_id"] for p in posts}), len(posts))

    def test_manglende_linje_giver_none_ikke_gaet(self):
        # Post uden linje-kontekst: lokal_id sættes ikke — R9-gaten blokerer
        # posten nedstrøms frem for at give den en gættet identitet.
        posts = run_segment("### PAGE 1 ###\n        7.       Henning, uden gren-header.")
        self.assertEqual(posts[0].get("lokal_id"), None)


if __name__ == "__main__":
    unittest.main()
