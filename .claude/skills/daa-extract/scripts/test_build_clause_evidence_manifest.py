"""Tests for clause_evidence-manifestbyggeren (#148 4.1c).

Alt syntetisk: opdigtede navne og en lille rendition med samme linjeregler som
den rigtige. Kernen i testene er offset-oversættelsen — helposten er IKKE en
litteral delstreng af renditionen, så et manifest må aldrig kunne bygges på
`parent.char_from + post-relativ offset`.
"""
import hashlib
import json
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(__file__))

import build_clause_evidence_manifest as B
import build_source_evidence_manifest as sem


def _sha(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


# To linjer, der foldes til én post med ét mellemrum imellem — netop det, der
# gør posten kortere end sit rå spænd.
RENDITION = "### PAGE 93 ###\nAlfa Bravo, f. 1801.    Gift 1830\n   m. Charlie Delta.\n"


def _fixture():
    projected, offsets = sem.project_rendition(RENDITION)
    post = projected.strip()
    p = projected.index(post)
    q = p + len(post)
    parent_from, parent_to = offsets[p], offsets[q - 1] + 1
    delt = post.index("Gift")
    klausuler = [
        {"ordinal": 1, "char_from": 0, "char_to": delt - 1,
         "classification": "record_text", "flags": [],
         "verbatim_sha256": _sha(post[0:delt - 1])},
        {"ordinal": 2, "char_from": delt, "char_to": len(post),
         "classification": "record_text", "flags": ["multiple_marriages"],
         "verbatim_sha256": _sha(post[delt:len(post)])},
    ]
    ledger = {
        "schema_version": "clause-ledger-v1",
        "rules_version": "clause-rules-fixture-v1",
        "segmenter_version": "clause_segment.py@v1",
        "gap_charset": [" "],
        "records": [{
            "record_key": "REC1", "occurrence_key": "source-evidence:REC1",
            "page_from": 93, "page_to": 93,
            "parent_char_from": parent_from, "parent_char_to": parent_to,
            "parent_verbatim_sha256": _sha(post),
            "rendition_content_sha256": _sha(RENDITION),
            "rules_version": "clause-rules-fixture-v1",
            "ledger_sha256": "d" * 64,
            "clauses": klausuler,
        }],
    }
    profile = {
        "source_id": 1, "profile_id": "fixture-ce", "profile_version": "clause-evidence-v1",
        "profile_sha256": "a" * 64, "raw_text_sha256": _sha(RENDITION),
        "clause_rules_version": "clause-rules-fixture-v1",
        "segmenter_version": "clause_segment.py@v1",
        "expected_counts": {"person_creates": 0, "source_evidence": 0, "clause_evidence": 1},
    }
    return profile, ledger, post, parent_from, parent_to


class TestClauseEvidenceManifest(unittest.TestCase):
    def setUp(self):
        self.profile, self.ledger, self.post, self.pcf, self.pct = _fixture()

    def test_posten_er_ikke_en_litteral_delstreng_af_renditionen(self):
        # Selve forudsætningen for hele oversættelsen: havde spændet været lineært,
        # ville den naive addition have virket, og testen her ville være meningsløs.
        self.assertNotEqual(self.pct - self.pcf, len(self.post))

    def test_bygger_manifest_med_oversatte_offsets(self):
        m = B.build_manifest(self.profile, self.ledger, RENDITION, "e" * 64)
        self.assertEqual(len(m["operations"]), 1)
        op = m["operations"][0]
        self.assertEqual(op["element_id"], "clause-evidence:REC1")
        self.assertEqual(m["provenance"]["ledger_file_sha256"], "e" * 64)
        for c in op["clauses"]:
            self.assertTrue(self.pcf <= c["rendition_char_from"] < c["rendition_char_to"] <= self.pct)
            self.assertNotIn("verbatim_text", c)
        # Den anden klausul ligger efter et foldet mellemrum: den naive addition
        # ville ramme forkert, oversættelsen rammer rigtigt.
        anden = op["clauses"][1]
        self.assertNotEqual(anden["rendition_char_from"], self.pcf + anden["char_from"])

    def test_manifestet_baerer_ingen_tekst(self):
        m = B.build_manifest(self.profile, self.ledger, RENDITION, "e" * 64)
        rå = json.dumps(m, ensure_ascii=False)
        self.assertNotIn("Alfa Bravo", rå)
        self.assertNotIn("Charlie Delta", rå)

    def test_afviser_forkert_rendition(self):
        with self.assertRaises(B.BuildError) as ctx:
            B.build_manifest(self.profile, self.ledger, RENDITION + " ", "e" * 64)
        self.assertEqual(str(ctx.exception), "RENDITION_SHA_MISMATCH")

    def test_afviser_forkert_regelversion(self):
        self.ledger["rules_version"] = "clause-rules-fixture-v2"
        with self.assertRaises(B.BuildError) as ctx:
            B.build_manifest(self.profile, self.ledger, RENDITION, "e" * 64)
        self.assertEqual(str(ctx.exception), "LEDGER_RULES_VERSION_MISMATCH")

    def test_afviser_helpost_der_ikke_kan_ankres(self):
        self.ledger["records"][0]["parent_verbatim_sha256"] = "f" * 64
        with self.assertRaises(B.BuildError) as ctx:
            B.build_manifest(self.profile, self.ledger, RENDITION, "e" * 64)
        self.assertEqual(str(ctx.exception), "CLAUSE_EVIDENCE_PARENT_ANCHOR_FAILED")

    def test_afviser_klausul_hvis_hash_ikke_matcher_udsnittet(self):
        self.ledger["records"][0]["clauses"][0]["verbatim_sha256"] = "0" * 64
        with self.assertRaises(B.BuildError) as ctx:
            B.build_manifest(self.profile, self.ledger, RENDITION, "e" * 64)
        self.assertEqual(str(ctx.exception), "CLAUSE_EVIDENCE_TEXT_HASH_MISMATCH")

    def test_afviser_layout_klausul(self):
        self.ledger["records"][0]["clauses"][0]["classification"] = "layout"
        with self.assertRaises(B.BuildError) as ctx:
            B.build_manifest(self.profile, self.ledger, RENDITION, "e" * 64)
        self.assertEqual(str(ctx.exception), "LEDGER_CLASSIFICATION_NOT_PROJECTABLE")

    def test_afviser_tomt_flag(self):
        self.ledger["records"][0]["clauses"][1]["flags"] = ["  "]
        with self.assertRaises(B.BuildError) as ctx:
            B.build_manifest(self.profile, self.ledger, RENDITION, "e" * 64)
        self.assertEqual(str(ctx.exception), "LEDGER_FLAGS_INVALID")

    def test_afviser_forkert_antal(self):
        self.profile["expected_counts"]["clause_evidence"] = 2
        with self.assertRaises(B.BuildError) as ctx:
            B.build_manifest(self.profile, self.ledger, RENDITION, "e" * 64)
        self.assertEqual(str(ctx.exception), "LEDGER_COUNT_MISMATCH")


if __name__ == "__main__":
    unittest.main()


class TestClauseRevisionManifest(unittest.TestCase):
    """Omsegmentering (spec 2026-09-27): revisions-tilstanden tager kun poster, hvis
    klausulsæt ændres, og bærer det sæt, den erstatter."""

    def setUp(self):
        self.profile, self.ledger, self.post, self.pcf, self.pct = _fixture()
        self.profile = dict(self.profile, profile_schema_version="reimport-clause-revision-profile-v1",
                            expected_counts={"person_creates": 0, "source_evidence": 0, "clause_revisions": 1})
        evidence = B.build_manifest(dict(self.profile, expected_counts={"person_creates": 0, "source_evidence": 0, "clause_evidence": 1}),
                                    self.ledger, RENDITION, "e" * 64)
        self.ledger_hash = B.clause_set.clause_set_sha256(evidence["operations"][0]["clauses"])

    def _current(self, sha, seq=1):
        return {"REC1": {"clause_set_seq": seq, "clause_set_sha256": sha}}

    def test_aendret_post_bliver_en_revision_med_det_erstattede_saet(self):
        m = B.build_revision_manifest(self.profile, self.ledger, RENDITION, "e" * 64, self._current("0" * 64))
        op, = m["operations"]
        self.assertEqual(op["element_id"], "clause-revision:REC1")
        self.assertEqual(op["dependency_class"], "clause_revision")
        self.assertEqual((op["replaces_clause_set_seq"], op["replaces_clause_set_sha256"]), (1, "0" * 64))
        self.assertEqual(m["expected_counts"], {"source_evidence": 0, "person_creates": 0,
                                                "canonical_delta": 0, "clause_revisions": 1})

    def test_uaendret_post_springes_over_og_taellingen_skal_passe(self):
        with self.assertRaises(B.BuildError):
            B.build_revision_manifest(self.profile, self.ledger, RENDITION, "e" * 64, self._current(self.ledger_hash))
        m = B.build_revision_manifest(dict(self.profile, expected_counts={"person_creates": 0, "source_evidence": 0, "clause_revisions": 0}),
                                      self.ledger, RENDITION, "e" * 64, self._current(self.ledger_hash))
        self.assertEqual(m["operations"], [])

    def test_post_uden_aktuelt_saet_afvises(self):
        with self.assertRaises(B.BuildError):
            B.build_revision_manifest(self.profile, self.ledger, RENDITION, "e" * 64, {})

    def test_current_sets_fra_projektionen(self):
        rows = [
            {"record_key": "REC1", "clause_set_seq": 1, "clause_set_sha256": "1" * 64, "is_current_set": False},
            {"record_key": "REC1", "clause_set_seq": 2, "clause_set_sha256": "2" * 64, "is_current_set": True},
            {"record_key": "REC1", "clause_set_seq": 2, "clause_set_sha256": "2" * 64, "is_current_set": True},
            {"record_key": None, "clause_set_seq": 1, "clause_set_sha256": "3" * 64, "is_current_set": True},
        ]
        self.assertEqual(B.current_sets_from_projection({"clauses": rows}),
                         {"REC1": {"clause_set_seq": 2, "clause_set_sha256": "2" * 64}})
        with self.assertRaises(B.BuildError):
            B.current_sets_from_projection({"clauses": rows + [dict(rows[1], clause_set_sha256="9" * 64)]})


# Beregnet på BASE-koden før 6a's Task 10: sha256 af json.dumps(manifest, ensure_ascii=False,
# sort_keys=True, indent=2) for 2018-fixturen (_fixture) bygget med ledger-hash "e"*64.
PINNED_2018_MANIFEST_SHA256 = "cba00baa6dae922ab386fd0f8b4d0e36569ba8bed4600bf8dcf4983a56ac4a9b"

RAW_RENDITION = "### PAGE 7 ###\nAlfa Bravo, f. 1801.\nGift 1830 m. Charlie Delta.\nEcho Foxtrot.\n"


def _raw_fixture():
    post = "Alfa Bravo, f. 1801.\nGift 1830 m. Charlie Delta."
    pcf = RAW_RENDITION.index(post)
    pct = pcf + len(post)
    delt = post.index("Gift")
    ledger = {
        "schema_version": "clause-ledger-v1", "rules_version": "clause-rules-fixture-v1",
        "segmenter_version": "clause_segment.py@v1", "gap_charset": [" ", "\n"],
        "records": [{
            "record_key": "REC1", "occurrence_key": "source-evidence:REC1", "page_from": 7, "page_to": 7,
            "parent_char_from": pcf, "parent_char_to": pct, "parent_verbatim_sha256": _sha(post),
            "rendition_content_sha256": _sha(RAW_RENDITION), "rules_version": "clause-rules-fixture-v1",
            "ledger_sha256": "d" * 64,
            "clauses": [
                {"ordinal": 1, "char_from": 0, "char_to": delt - 1, "classification": "record_text",
                 "flags": [], "verbatim_sha256": _sha(post[0:delt - 1])},
                {"ordinal": 2, "char_from": delt, "char_to": len(post), "classification": "record_text",
                 "flags": [], "verbatim_sha256": _sha(post[delt:])},
            ],
        }],
    }
    profile = {
        "source_id": 3, "profile_id": "fixture-ce-raw", "profile_version": "clause-evidence-v1",
        "profile_sha256": "a" * 64, "raw_text_sha256": _sha(RAW_RENDITION),
        "clause_rules_version": "clause-rules-fixture-v1", "segmenter_version": "clause_segment.py@v1",
        "writer_config": {"text_form": "raw", "helpost_observation_kind": "person"},
        "expected_counts": {"person_creates": 0, "source_evidence": 0, "clause_evidence": 1},
    }
    return profile, ledger, post, pcf, pct


class TestRawTextForm(unittest.TestCase):
    def setUp(self):
        self.profile, self.ledger, self.post, self.pcf, self.pct = _raw_fixture()

    def test_raw_manifest_offsets_are_identity(self):
        m = B.build_manifest(self.profile, self.ledger, RAW_RENDITION, "e" * 64)
        op, = m["operations"]
        for c in op["clauses"]:
            self.assertEqual(c["rendition_char_from"], self.pcf + c["char_from"])
            self.assertEqual(c["rendition_char_to"], self.pcf + c["char_to"])
            self.assertEqual(_sha(RAW_RENDITION[c["rendition_char_from"]:c["rendition_char_to"]]),
                             c["verbatim_sha256"])
        self.assertEqual(op["rendition_projection_sha256"], _sha(RAW_RENDITION))
        self.assertEqual(m["provenance"]["rendition_projection_sha256"], _sha(RAW_RENDITION))

    def test_raw_anchor_hash_mismatch_fails(self):
        self.ledger["records"][0]["parent_verbatim_sha256"] = "f" * 64
        with self.assertRaises(B.BuildError) as ctx:
            B.build_manifest(self.profile, self.ledger, RAW_RENDITION, "e" * 64)
        self.assertEqual(str(ctx.exception), "CLAUSE_EVIDENCE_PARENT_ANCHOR_FAILED")

    def test_raw_anchor_outside_rendition_fails(self):
        self.ledger["records"][0]["parent_char_to"] = len(RAW_RENDITION) + 5
        with self.assertRaises(B.BuildError) as ctx:
            B.build_manifest(self.profile, self.ledger, RAW_RENDITION, "e" * 64)
        self.assertEqual(str(ctx.exception), "CLAUSE_EVIDENCE_PARENT_ANCHOR_FAILED")

    def test_2018_manifest_byte_identical(self):
        profile, ledger, *_ = _fixture()
        m = B.build_manifest(profile, ledger, RENDITION, "e" * 64)
        digest = hashlib.sha256(json.dumps(m, ensure_ascii=False, sort_keys=True, indent=2)
                                .encode("utf-8")).hexdigest()
        self.assertEqual(digest, PINNED_2018_MANIFEST_SHA256)
