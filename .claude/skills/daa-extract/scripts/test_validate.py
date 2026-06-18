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


if __name__ == "__main__":
    unittest.main()
