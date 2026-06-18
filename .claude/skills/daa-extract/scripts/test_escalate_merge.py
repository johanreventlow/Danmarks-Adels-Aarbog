import os, sys, unittest, tempfile
sys.path.insert(0, os.path.dirname(__file__))
import escalate_merge as em

SRC = {("I", "5"): {"raw_text": "Iwan † 1261. Gift med Sofie.", "linje": "I", "nr": 5}}
KEY = ("I", "5")

def rec(**kw):
    base = {"linje": "I", "nr": 5, "nr_label": "5", "navn": "Iwan", "facts": [], "aegteskaber": []}
    base.update(kw); return base

class TestDecide(unittest.TestCase):
    def test_promote_naar_r8_forbedres(self):
        # snapshot missede død; reextracted fandt den -> R8 falder -> promote
        snap = rec(facts=[])
        reext = rec(facts=[{"faktatype": "død", "date_raw": "† 1261"}])
        promote, issues, adv = em.decide(reext, snap, SRC[KEY], {})
        self.assertTrue(promote)

    def test_afvis_naar_nyt_r8_introduceres(self):
        # reextracted taber en død snapshot havde -> R8 stiger -> afvis
        snap = rec(facts=[{"faktatype": "død", "date_raw": "† 1261"}])
        reext = rec(facts=[])
        promote, issues, adv = em.decide(reext, snap, SRC[KEY], {})
        self.assertFalse(promote)

    def test_afvis_naar_blokerende(self):
        reext = rec(facts=[{"faktatype": "død", "date_raw": "† 1999"}])  # 1999 ikke i prosa -> R1
        promote, issues, adv = em.decide(reext, rec(), SRC[KEY], {})
        self.assertFalse(promote)

class TestMerge(unittest.TestCase):
    def _common(self, reext):
        esc = [{"linje": "I", "nr": 5, "nr_label": "5", "grunde": ["R8: ..."]}]
        return em.merge_escalated(esc, {KEY: reext}, {KEY: rec()}, SRC, {}, clean=[], review=[])

    def test_append_naar_ikke_i_clean(self):
        reext = rec(facts=[{"faktatype": "død", "date_raw": "† 1261"}])
        new_clean, new_review, promoted = self._common(reext)
        self.assertEqual(len(new_clean), 1)
        self.assertTrue(new_clean[0]["_escalated"])
        self.assertIn(KEY, promoted)

    def test_replace_naar_allerede_i_clean(self):
        reext = rec(facts=[{"faktatype": "død", "date_raw": "† 1261"}])
        esc = [{"linje": "I", "nr": 5, "nr_label": "5", "grunde": ["R8: ..."]}]
        old = rec(facts=[])  # gammel ufuldstændig version i clean
        new_clean, new_review, promoted = em.merge_escalated(
            esc, {KEY: reext}, {KEY: rec()}, SRC, {}, clean=[old], review=[])
        self.assertEqual(len(new_clean), 1)                       # opdateret, ikke tilføjet
        self.assertEqual(len(new_clean[0]["facts"]), 1)           # Opus-output vandt
        self.assertTrue(new_clean[0]["_escalated"])

    def test_nu_fejlende_fjernes_fra_clean(self):
        # Reext med hallucineret årstal (1999 ikke i prosa) => R1 bloker
        # Post sad allerede i clean => skal POP'es og lægges i review
        reext_bad = rec(facts=[{"faktatype": "død", "date_raw": "† 1999"}])
        esc = [{"linje": "I", "nr": 5, "nr_label": "5", "grunde": ["R8: ..."]}]
        old = rec(facts=[])  # sad i clean inden eskalering
        new_clean, new_review, promoted = em.merge_escalated(
            esc, {KEY: reext_bad}, {KEY: rec()}, SRC, {}, clean=[old], review=[])
        self.assertEqual(len(new_clean), 0)          # fjernet fra clean
        self.assertEqual(len(new_review), 1)         # havnet i review
        self.assertNotIn(KEY, promoted)

class TestDiff(unittest.TestCase):
    def test_field_diff_fanger_aendring(self):
        snap = {"navn": "Iwan", "facts": []}
        reext = {"navn": "Iwan", "facts": [{"faktatype": "død"}]}
        d = em.field_diff(snap, reext)
        self.assertIn("facts", d)
        self.assertNotIn("navn", d)   # uændret felt udelades

    def test_field_diff_tom_naar_identisk(self):
        self.assertEqual(em.field_diff({"navn": "A"}, {"navn": "A"}), {})

    def test_field_diff_ignorerer_escalated_og_narrative(self):
        snap = {"navn": "A", "_escalated": False, "narrative": "old"}
        reext = {"navn": "A", "_escalated": True, "narrative": "new"}
        d = em.field_diff(snap, reext)
        # skal være tom da _escalated og narrative ignoreres
        self.assertEqual(d, {})

    def test_gen_diff_markdown_format(self):
        import tempfile
        escalation = [
            {"linje": "I", "nr_label": "5", "grunde": ["R8: ..."]}
        ]
        reext_by_key = {("I", "5"): {"navn": "Iwan", "facts": [{"faktatype": "død"}]}}
        snap_by_key = {("I", "5"): {"navn": "Iwan", "facts": []}}
        promoted = {("I", "5")}

        with tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.md') as f:
            path = f.name

        try:
            em.gen_diff(escalation, reext_by_key, snap_by_key, promoted, path)
            with open(path, 'r', encoding='utf-8') as f:
                content = f.read()
            self.assertIn("# Eskalerings-diff", content)
            self.assertIn("## I-5 (PROMOVERET)", content)
            self.assertIn("Grunde: R8: ...", content)
            self.assertIn("- **facts**:", content)
        finally:
            os.unlink(path)
