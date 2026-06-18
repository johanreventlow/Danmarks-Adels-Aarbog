import os, sys, unittest
sys.path.insert(0, os.path.dirname(__file__))
import validate


class TestDeriveBoern(unittest.TestCase):
    def test_antal_og_range(self):
        raw = "Gottschalk, til Glasau. 3 børn: Tiende slægtled, II, nr. 31-35."
        self.assertEqual(validate.derive_boern(raw),
                         {"antal": 3, "slaegtled": "Tiende slægtled", "linje": "II", "nr_range": [31, 35]})

    def test_enkelt_barn_soen(self):
        raw = "N.N., til X. Søn: nr. 199."
        got = validate.derive_boern(raw)
        self.assertEqual(got["nr_range"], [199, 199])
        self.assertEqual(got["antal"], 1)

    def test_ingen_boerneklausul(self):
        self.assertIsNone(validate.derive_boern("Levede ugift, deres børn boede i udlandet."))

    def test_bar_boern_uden_antal(self):
        raw = "børn: nr. 12-14."
        got = validate.derive_boern(raw)
        self.assertEqual(got["nr_range"], [12, 14])
        self.assertEqual(got["antal"], 3)


class TestDeriveAegteskaber(unittest.TestCase):
    def test_enkelt_aegteskab(self):
        raw = "Frederik, til Brahetrolleborg. g. 26. juli 1975 m. Margrethe Holstein."
        got = validate.derive_aegteskaber(raw)
        self.assertEqual(len(got), 1)
        self.assertEqual(got[0]["ordinal"], 1)
        self.assertEqual(got[0]["partner_navn"], "Margrethe Holstein")
        self.assertFalse(got[0]["skilt"])

    def test_to_aegteskaber_ordinaler(self):
        raw = ("Christian, til Christianssæde. Gift 1° 1698 med Anna Sophie Reedtz, "
               "2° 1712 med Birgitte Restorff, skilt.")
        got = validate.derive_aegteskaber(raw)
        self.assertEqual([a["ordinal"] for a in got], [1, 2])
        self.assertEqual(got[0]["partner_navn"], "Anna Sophie Reedtz")
        self.assertTrue(got[1]["skilt"])

    def test_ingen_aegteskab(self):
        self.assertEqual(validate.derive_aegteskaber("Døde ugift 1701."), [])

    def test_dato_raw_findes_i_tekst(self):
        raw = "N.N. g. 1750 m. Sofie."
        got = validate.derive_aegteskaber(raw)
        self.assertIn(got[0]["dato_raw"].strip(), raw)


if __name__ == "__main__":
    unittest.main()
