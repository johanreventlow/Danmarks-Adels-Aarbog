import hashlib
import json
import os
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(__file__)


class TestBuildClauseLedger(unittest.TestCase):
    def test_cli_builds_ledger_and_summary_without_text_leak(self):
        with tempfile.TemporaryDirectory() as tmp:
            os.chmod(tmp, 0o700)
            texts = os.path.join(tmp, "texts.json")
            text = "Alfa Bravo, f. 1801, d. 1860. Gift 1830 m. Charlie."
            with open(texts, "w", encoding="utf-8") as fh:
                json.dump([{"record_key": "I.1", "occurrence_key": "source-evidence:I.1", "page_from": 10, "page_to": 10,
                            "char_from": 100, "char_to": 100 + len(text), "verbatim_text": text,
                            "verbatim_sha256": hashlib.sha256(text.encode("utf-8")).hexdigest(),
                            "rendition_content_sha256": "1" * 64}], fh)
            out = os.path.join(tmp, "out"); os.mkdir(out); os.chmod(out, 0o700)
            proc = subprocess.run([sys.executable, os.path.join(HERE, "build_clause_ledger.py"), "--profile", "daa-2018-20-v1",
                                   "--texts", texts, "--output-dir", out], capture_output=True, text=True)
            self.assertEqual(proc.returncode, 0, proc.stderr)
            with open(os.path.join(out, "clause-ledger-v1.json"), encoding="utf-8") as fh:
                ledger = json.load(fh)
            self.assertEqual(ledger["schema_version"], "clause-ledger-v1")
            self.assertEqual(ledger["gap_charset"], [" "])
            self.assertEqual(len(ledger["records"]), 1)
            self.assertNotIn("verbatim_text", json.dumps(ledger))
            with open(os.path.join(out, "clause-ledger-summary.json"), encoding="utf-8") as fh:
                summary = json.load(fh)
            self.assertEqual(summary["records"], 1)
            self.assertEqual(summary["clauses"]["total"], 2)
            self.assertNotIn("Alfa", json.dumps(summary))
            self.assertEqual(oct(os.stat(os.path.join(out, "clause-ledger-texts-v1.json")).st_mode & 0o777), "0o600")

    def test_segmenter_version_is_derived_from_the_code(self):
        """Review 35, P4: den hårdkodede "clause_segment.py@v1" stod stille gennem fire
        kodeændringer; ledgeren kunne ikke sige, hvilken kode der skrev klausulerne."""
        sys.path.insert(0, HERE)
        import build_clause_ledger as b
        version = b.segmenter_version()
        self.assertTrue(version.startswith("clause_segment.py@sha256:"))
        self.assertNotEqual(version, "clause_segment.py@v1")
        with tempfile.TemporaryDirectory() as tmp:
            for name in b.SEGMENTER_SOURCES:
                with open(os.path.join(HERE, name), "rb") as src, open(os.path.join(tmp, name), "wb") as dst:
                    dst.write(src.read())
            from pathlib import Path
            self.assertEqual(b.segmenter_version(Path(tmp)), version)
            for name in b.SEGMENTER_SOURCES:
                with open(os.path.join(tmp, name), "ab") as fh:
                    fh.write(b"\n# aendret\n")
                changed = b.segmenter_version(Path(tmp))
                self.assertNotEqual(changed, version, name)
                version = changed

    def test_ledger_carries_the_derived_segmenter_version(self):
        sys.path.insert(0, HERE)
        import build_clause_ledger as b
        with tempfile.TemporaryDirectory() as tmp:
            os.chmod(tmp, 0o700)
            texts = os.path.join(tmp, "texts.json")
            text = "Alfa Bravo, f. 1801. Gift 1830."
            with open(texts, "w", encoding="utf-8") as fh:
                json.dump([{"record_key": "I.1", "occurrence_key": "source-evidence:I.1", "page_from": 1, "page_to": 1,
                            "char_from": 0, "char_to": len(text), "verbatim_text": text,
                            "verbatim_sha256": hashlib.sha256(text.encode("utf-8")).hexdigest(),
                            "rendition_content_sha256": "1" * 64}], fh)
            out = os.path.join(tmp, "out"); os.mkdir(out); os.chmod(out, 0o700)
            proc = subprocess.run([sys.executable, os.path.join(HERE, "build_clause_ledger.py"), "--profile", "daa-2018-20-v1",
                                   "--texts", texts, "--output-dir", out], capture_output=True, text=True)
            self.assertEqual(proc.returncode, 0, proc.stderr)
            with open(os.path.join(out, "clause-ledger-v1.json"), encoding="utf-8") as fh:
                self.assertEqual(json.load(fh)["segmenter_version"], b.segmenter_version())

    def test_cli_refuses_output_dir_with_work_component_or_wrong_mode(self):
        with tempfile.TemporaryDirectory() as tmp:
            bad = os.path.join(tmp, "work"); os.mkdir(bad); os.chmod(bad, 0o700)
            proc = subprocess.run([sys.executable, os.path.join(HERE, "build_clause_ledger.py"), "--profile", "daa-2018-20-v1",
                                   "--texts", os.path.join(tmp, "missing.json"), "--output-dir", bad], capture_output=True, text=True)
            self.assertNotEqual(proc.returncode, 0)
            self.assertIn("OUTPUT_WORK_PATH", proc.stderr)


if __name__ == "__main__":
    unittest.main()
