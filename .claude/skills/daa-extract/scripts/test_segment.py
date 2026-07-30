import os, sys, io, tempfile, contextlib, unittest
sys.path.insert(0, os.path.dirname(__file__))
import segment


def run_segment(text, udgave=None):
    """Kør segment.main på en midlertidig råtekst; returnér posts (undertryk stdout/stderr)."""
    with tempfile.NamedTemporaryFile('w', suffix='.txt', delete=False, encoding='utf-8') as fh:
        fh.write(text); path = fh.name
    try:
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            return segment.main(path, udgave=udgave)
    finally:
        os.unlink(path)


def run_segment_med_rapport(text, udgave=None):
    """Som run_segment, men behold kvalitetsrapporten til assertions."""
    with tempfile.NamedTemporaryFile('w', suffix='.txt', delete=False, encoding='utf-8') as fh:
        fh.write(text); path = fh.name
    try:
        stderr = io.StringIO()
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(stderr):
            posts = segment.main(path, udgave=udgave)
        return posts, stderr.getvalue()
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


class TestSegment1939Profil(unittest.TestCase):
    """Syntetiske 1939-eksempler; ingen rå bogtekst eller PII."""

    def test_centreret_afspaerret_slaegtled_og_lille_romertal(self):
        raw = "\n".join([
            "### PAGE 490 ###",
            "   Reventlow.",
            "490",
            "                    III.",
            "Den anden meklenborgske Linje af Teststed.",
            "                  (S. 19).",
            "                     O ttende S læ gtled ,",
            "                              i.",
            "3. J o h a n til Gram og Tovskov (udskilt Testgods),",
            "   fortsatte sin opdigtede fortælling.",
        ])
        posts = run_segment(raw, udgave="1939")
        self.assertEqual(len(posts), 1)
        self.assertEqual((posts[0]["slaegtled"], posts[0]["afsnit"]),
                         ("Ottende", "I"))
        self.assertEqual(posts[0]["raw_text"],
                         "J o h a n til Gram og Tovskov (udskilt Testgods), "
                         "fortsatte sin opdigtede fortælling.")
        self.assertEqual(posts[0]["lokal_id"], "III.Ottende.I.3")

    def test_usikker_post_og_titelpraefiks_med_spaerret_navn(self):
        raw = "\n".join([
            "                    IV.",
            "Den fjerde Linje af Teststed.",
            "                  (S. 43).",
            "                     O ttende S læ gtled ,",
            "                             II.",
            "1. (?) M a g d a 1 e n e er en syntetisk post.",
            "2. Comtesse H i l d e b o r g J u t t a fortsætter.",
        ])
        posts = run_segment(raw, udgave="1939")
        self.assertEqual([p["nr_label"] for p in posts], ["1", "2"])
        self.assertEqual([p["usikker"] for p in posts], [True, False])
        self.assertTrue(posts[0]["raw_text"].startswith("(?) M a g d a 1 e n e"))
        self.assertTrue(posts[1]["raw_text"].startswith(
            "Comtesse H i l d e b o r g J u t t a"))

    def test_venstrestillet_pegepind_wrap_aendrer_aldrig_state(self):
        raw = "\n".join([
            "                    IV.",
            "Den fjerde Linje af Teststed.",
            "                  (S. 43).",
            "                     O ttende S læ gtled ,",
            "                             II.",
            "5. A n n a skrev en opdigtet fortælling.",
            "— Børn: Ottende",
            "Slægtled I.",
            "6. B e n t fortsatte fortællingen.",
        ])
        posts = run_segment(raw, udgave="1939")
        self.assertEqual([p["slaegtled"] for p in posts], ["Ottende", "Ottende"])
        self.assertEqual([p["afsnit"] for p in posts], ["II", "II"])
        self.assertIn("— Børn: Ottende Slægtled I.", posts[0]["raw_text"])

    def test_gruppebeskrivelse_droppes_og_taelles(self):
        raw = "\n".join([
            "                    IV.",
            "Den fjerde Linje af Teststed.",
            "                  (S. 43).",
            "                     O ttende S læ gtled ,",
            "                             II.",
            "Christian Detlev Frederik Vilhelm Ferdinand Greve Re-",
            "  ventlows Døtre med Hilda Charlotte Malvine Agnes",
            "                  Comtesse Reventlow:",
            "6. B e n t er en syntetisk post.",
        ])
        posts, rapport = run_segment_med_rapport(raw, udgave="1939")
        self.assertEqual(posts[0]["raw_text"], "B e n t er en syntetisk post.")
        self.assertIn("3 gruppe-kontekstlinjer droppet", rapport)

    def test_s_m_dato_og_kildelinje_afvises_som_poststarter(self):
        raw = "\n".join([
            "                    IL",
            "Linjen Gallentin.",
            "                  (S. 21).",
            "                     O ttende S læ gtled ,",
            "                             II.",
            "4. A n n a har en fortsættelse.",
            "6. 24 s. M. (B).",
            "6. Conrad: Den danske grevelige Linie, IV, S. 52.",
            "5. B e n t er næste post.",
        ])
        posts = run_segment(raw, udgave="1939")
        self.assertEqual([p["nr_label"] for p in posts], ["4", "5"])
        self.assertIn("24 s. M. (B).", posts[0]["raw_text"])
        self.assertIn("Conrad: Den danske grevelige Linie, IV, S. 52.",
                      posts[0]["raw_text"])

    def test_iil_normalisering_og_lokal_id_komposition(self):
        raw = "\n".join([
            "                    IV.",
            "Den fjerde Linje af Teststed.",
            "                  (S. 43).",
            "                     O ttende S læ gtled ,",
            "                            IIL.",
            "5. A n n a er en syntetisk post.",
            "                             II.",
            "6. B e n t er en syntetisk post.",
        ])
        posts = run_segment(raw, udgave="1939")
        self.assertEqual(
            [(p["afsnit"], p["lokal_id"]) for p in posts],
            [("III", "IV.Ottende.III.5"), ("II", "IV.Ottende.II.6")],
        )

    def test_afsnit_udelades_og_lokal_id_er_fail_closed(self):
        med_kontekst = run_segment("\n".join([
            "                    IL",
            "Linjen Gallentin.",
            "                  (S. 21).",
            "                     O ttende S læ gtled ,",
            "6. C a r l er en syntetisk post.",
        ]), udgave="1939")
        uden_linje = run_segment(
            "                     O ttende S læ gtled ,\n"
            "1. A n n a er syntetisk.", udgave="1939")
        uden_slaegtled = run_segment(
            "                    I\nDen første Linje af Teststed.\n1. B e n t er syntetisk.", udgave="1939")
        # IL er OCR for II — romertallet fra blok-headeren ER linje-leddet
        self.assertEqual(med_kontekst[0]["lokal_id"], "II.Ottende.6")
        self.assertIsNone(uden_linje[0]["lokal_id"])
        self.assertIsNone(uden_slaegtled[0]["lokal_id"])

    def test_ombrudt_romertals_linje_header_saetter_kort_label(self):
        raw = "\n".join([
            # blok-form uden "(S. nn)."-linje — sidehenvisningen er valgfri
            "                    III,",
            "Den anden meklenborgske Linje af Teststed.",
            "                     O ttende S læ gtled ,",
            "                              I.",
            "1. D o r a er en syntetisk post.",
        ])
        posts = run_segment(raw, udgave="1939")
        self.assertEqual(posts[0]["linje"], "III")
        self.assertEqual(posts[0]["lokal_id"], "III.Ottende.I.1")

    def test_navnlost_barn_og_rent_spoergsmaalstegn_er_poster(self):
        raw = "\n".join([
            "                    I",
            "Den første Linje af Teststed.",
            "                     F ø rste S læ gtled .",
            "1. En Søn",
            "2. en Datter",
            "3. (?)",
        ])
        posts = run_segment(raw, udgave="1939")
        self.assertEqual([p["nr_label"] for p in posts], ["1", "2", "3"])
        self.assertEqual([p["usikker"] for p in posts], [False, False, True])

    def test_kvalitetsrapport_taeller_og_lister_alle_risici(self):
        raw = "\n".join([
            "U n n a er en unummereret stamfader.",
            "                    I",
            "Den første Linje af Teststed.",
            "                     O ttende S læ gtled ,",
            "                              I.",
            "1. A n n a er en syntetisk post.",
            "1. B e n t er en dublet.",
            "3. C a r l efterlader et hul.",
            "                     Z zte S læ gtled ,",
            "gruppebeskrivelse:",
            "                     F ø rste S læ gtled .",
            "1. D o r a følger efter et umarkeret slægtledsfald.",
        ])
        _, rapport = run_segment_med_rapport(raw, udgave="1939")
        self.assertIn("[segment] 4 poster", rapport)
        self.assertIn("0 poster uden lokal_id", rapport)
        self.assertIn("1 unummererede poster", rapport)
        self.assertIn("1 gruppe-kontekstlinjer droppet", rapport)
        self.assertIn("1 ukendte ordinalord: ['Zzte']", rapport)
        self.assertIn("1 slægtled-fald uden linjeskift", rapport)
        self.assertIn("dublet-poster i gruppe I.Ottende.I: ['1']", rapport)
        self.assertIn("mangler [2]", rapport)
        self.assertIn("lokal_id-dubletter: ['I.Ottende.I.1']", rapport)


class TestPegepindKrydstjek1939(unittest.TestCase):
    """Bogen dobbeltbogfører strukturen — pegepindene er facitliste."""

    def _profil(self):
        return segment.UDGAVE_PROFILER["1939"]

    def test_peget_gruppe_der_findes_giver_ingen_advarsel(self):
        posts = [
            {"linje": "I", "slaegtled": "Syvende", "afsnit": "II", "lokal_id": "I.Syvende.II.1",
             "raw_text": "N.N. † 1700. — Børn: Ottende Slægtled I."},
            {"linje": "I", "slaegtled": "Ottende", "afsnit": "I", "lokal_id": "I.Ottende.I.1",
             "raw_text": "M.M. f. 1690."},
        ]
        self.assertEqual(segment._pegepind_krydstjek_1939(posts, self._profil()), [])

    def test_peget_gruppe_uden_modpart_meldes(self):
        # Pegepinden nævner Niende Slægtled — ingen gruppe har det: misset
        # markør ELLER OCR-tab. Skal meldes, aldrig ties.
        posts = [{"linje": "I", "slaegtled": "Syvende", "afsnit": None,
                  "lokal_id": "I.Syvende.3",
                  "raw_text": "N.N. † 1700. — Børn: Niende Slægtled II."}]
        mangler = segment._pegepind_krydstjek_1939(posts, self._profil())
        self.assertEqual(len(mangler), 1)
        self.assertIn("Niende", mangler[0][1])

    def test_pegepind_uden_roman_matcher_ethvert_afsnit(self):
        posts = [
            {"linje": "I", "slaegtled": "Femte", "afsnit": "III", "lokal_id": "I.Femte.III.2",
             "raw_text": "N.N. — Børn: Sjette Slægtled."},
            {"linje": "I", "slaegtled": "Sjette", "afsnit": "I", "lokal_id": "I.Sjette.I.1",
             "raw_text": "M.M."},
        ]
        self.assertEqual(segment._pegepind_krydstjek_1939(posts, self._profil()), [])

    def test_prosa_med_ordinallignende_ord_ignoreres(self):
        # "Søn: Peter Slægtled…" findes ikke — men et ikke-ordinal førsteord
        # må aldrig udløse krydstjek (fail-soft mod prosa).
        posts = [{"linje": "I", "slaegtled": "Femte", "afsnit": None, "lokal_id": "I.Femte.1",
                  "raw_text": "N.N. — Børn: Peter Slægtled arvede intet."}]
        self.assertEqual(segment._pegepind_krydstjek_1939(posts, self._profil()), [])


if __name__ == "__main__":
    unittest.main()
