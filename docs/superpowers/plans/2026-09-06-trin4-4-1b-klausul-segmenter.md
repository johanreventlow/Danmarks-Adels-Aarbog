# Trin 4 · dagsværk 4.1b: deterministisk klausul-segmentering — implementeringsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Del hver 2018-20-helpost deterministisk i meningsbærende klausuler, bogført i `clause_ledger`-format med fuld tegn-dækning, og mål på alle 591 records, hvordan reglerne klarer sig — uden modelkald og uden databaseskrivning.

**Architecture:** Nyt motor-script `clause_segment.py` (regler læses fra udgaveprofilen `extraction-profiles.json` → `clause_rules`), et lille læse-kun R-eksport af helposterne fra en restore, og en CLI `build_clause_ledger.py`, der producerer private ledger-artefakter + et aggregeret summary. Den syntetiske "svære fixture" fra Task 2 (2026-08-02-planen) er første test.

**Tech Stack:** Python 3 (stdlib, pytest/unittest som resten af `.claude/skills/daa-extract/scripts/`), R + DBI/RPostgres til eksport, PostgreSQL 17-restore fra 4.1a.

**Spec:** `docs/superpowers/specs/2026-09-06-trin4-fortolkningskaede-og-klausulgranularitet-design.md` §4.1.3 og §4.1.2 ("Dækningsinvariant, to lag").

## Global Constraints

- Ingen modelkald, ingen netværk, ingen databaseskrivning i dette dagsværk.
- Helpost-tekst er persondata (også for afdøde i kombination): eksport og ledger-artefakter ligger under en 0700-mappe uden `work`-komponent, filer 0600, committes aldrig. Repo får kun kode, syntetiske fixtures og aggregater.
- Reglerne bor i profilen, ikke i motoren. En regelændring = ny `clause_rules.version` og ny profilversion; profilen bærer `requires_human_go_for_change: true`, så projektejeren skal give GO for den nye profilversion, før 4.1c bruger den (spec §10).
- Ledgeren bærer aldrig database-UUID'er: `occurrence_id` = manifestets element-id (`source-evidence:<record_key>`), `observation_ids` = `<record_key>#<ordinal>`.
- Offsets i ledger og payload er helpost-relative (0 = helpostens første tegn); databasen er rendition-absolut, og 4.1c oversætter.
- Commits: ét pr. task, Conventional Commits på dansk, ingen push, `git branch --show-current` før commit. Gren: `feat/148-klausul-segmenter` fra `origin/main` (efter at 4.1a er merget, eller ovenpå 4.1a-grenen).

## Roadmappens seks adgangskrav (for dette dagsværk)

1. **Roadmapmål:** trin 4, #148.
2. **Værdikædeled:** `klausulobservationer` (produktion af klausulerne som artefakt; databaseprojektionen er 4.1c).
3. **Generel/profil/legacy:** generel motor (`clause_segment.py`, `build_clause_ledger.py`) + 2018-20-profil (`clause_rules`, `gap_charset`). Ingen legacy.
4. **Redaktionel værdi:** kildebelæg pr. klausul bliver muligt; flag-mekanismen giver redaktøren en kø af tvivlstilfælde frem for gæt.
5. **Bevis:** ledger for alle 591 records med 100 % dækning, 0 tegn uden for hvidlisten i mellemrummene, tal for klausuler pr. record, flag-andel og antal `structural_header`-klausuler; syntetisk fixture med Task 2's syv svære tilfælde grøn.
6. **Erstatter:** den gamle skills antagelse om, at helposten er mindste evidensenhed; `clause_ledger.py` går fra ubrugt kontrakt til brugt.

## Målt udgangspunkt (lokal prod-kopi 2026-09-06, kun tal)

| Måling (2018-20 helposter) | Værdi |
| --- | --- |
| Antal | 591, alle `person_post`, én occurrence pr. record |
| Længde (tegn) min / median / max | 5 / 377 / 8894 |
| Indeholder linjeskift | 0 af 591 (`segment.py`'s `norm()` folder whitespace til ét mellemrum) |
| Indeholder "Børn" / "gift" / ";" / ". " + stort bogstav | 4 / 304 / 25 / 141 |
| Hyppigste tegn uden for det latinske basis-sæt | U+2011 (ikke-brydende bindestreg) 818, `°` 157, `’` 51, `?` 49, `“ ”` 47, U+00AD (blød bindestreg) 34, `[ ]` 29 |

Konsekvens: mellemrummene mellem klausuler er forventeligt kun `" "`; U+2011/U+00AD står *inde i* ord og hører til klausulerne. Mange poster er korte og giver 1-3 klausuler; det er ikke en fejl.

## Filoversigt

- Create: `.claude/skills/daa-extract/scripts/clause_segment.py`
- Create: `.claude/skills/daa-extract/scripts/test_clause_segment.py`
- Create: `.claude/skills/daa-extract/scripts/tests/fixtures/evidence-clauses.synthetic.json`
- Modify: `.claude/skills/daa-extract/references/extraction-profiles.json` (profil `daa-2018-20-v1` → version `1.1.0`, ny nøgle `clause_rules`)
- Modify: `.claude/skills/daa-extract/scripts/evidence_extract.py` (`load_profile` validerer `clause_rules`, hvis den findes)
- Create: `.claude/skills/daa-extract/scripts/export_clause_source_texts.R`
- Create: `.claude/skills/daa-extract/scripts/build_clause_ledger.py`
- Create: `.claude/skills/daa-extract/scripts/test_build_clause_ledger.py`
- Modify: `.github/workflows/ci.yml` (jobbet `evidence contract · pytest`: tilføj de to nye testfiler)
- Modify: `docs/evidensbaseret-genimport/clause-evidence-148-rehearsal.md` (afsnit 4.1b)
- Modify: `docs/changelog.md`

---

### Task 1: Regelkontrakt i profilen

**Files:**
- Modify: `.claude/skills/daa-extract/references/extraction-profiles.json`
- Modify: `.claude/skills/daa-extract/scripts/evidence_extract.py` (`load_profile`, linje 53-62)
- Modify: `.claude/skills/daa-extract/scripts/test_evidence_extract.py`

**Interfaces:**
- Produces: `profile["clause_rules"]` med nøglerne `version`, `terminators`, `non_terminal_abbreviations`, `initial_pattern`, `ordinal_number_pattern`, `structural_header_patterns`, `min_clause_chars`, `gap_charset`, `intraword_chars`; `evidence_extract.load_profile` afviser en ufuldstændig `clause_rules`.

- [ ] **Step 1: Skriv den fejlende test**

Tilføj til `test_evidence_extract.py`:

```python
def test_profile_clause_rules_are_validated(tmp_path):
    payload = json.loads(evidence_extract.PROFILES.read_text(encoding="utf-8"))
    profile = payload["profiles"]["daa-2018-20-v1"]
    assert profile["version"] == "1.1.0"
    rules = profile["clause_rules"]
    assert set(rules) == {"version", "terminators", "non_terminal_abbreviations", "initial_pattern",
                          "ordinal_number_pattern", "structural_header_patterns", "min_clause_chars",
                          "gap_charset", "intraword_chars"}
    broken = json.loads(json.dumps(payload))
    del broken["profiles"]["daa-2018-20-v1"]["clause_rules"]["gap_charset"]
    path = tmp_path / "profiles.json"
    path.write_text(json.dumps(broken), encoding="utf-8")
    with pytest.raises(evidence_extract.ExtractionError, match="EXTRACTION_CLAUSE_RULES_INVALID"):
        evidence_extract.load_profile("daa-2018-20-v1", path)
```

(`json`, `pytest` og `evidence_extract` importeres allerede øverst i filen; ellers tilføj dem.)

- [ ] **Step 2: Kør og se den fejle**

```bash
/usr/bin/python3 -m pytest .claude/skills/daa-extract/scripts/test_evidence_extract.py -q -k clause_rules
```

Forventet: FAIL (`KeyError: 'clause_rules'` eller versions-assert).

- [ ] **Step 3: Skriv reglerne ind i profilen**

I `extraction-profiles.json`, profil `daa-2018-20-v1`: sæt `"version": "1.1.0"` og tilføj:

```json
"clause_rules": {
  "version": "clause-rules-2018-20-v1",
  "terminators": [". ", "; "],
  "non_terminal_abbreviations": [
    "f.", "d.", "g.", "gm.", "m.", "s.", "dat.", "sen.", "jun.", "ca.", "o.", "ovenn.", "sst.", "sm.",
    "kgl.", "Kmh.", "Kmjkr.", "Hofjgm.", "Hofjægerm.", "Gehr.", "Gehkfr.", "Kbh.", "St.", "Sct.", "Fr.", "Frk.", "Hr.",
    "Prof.", "Dr.", "cand.", "stud.", "jur.", "polit.", "med.", "phil.", "theol.", "mag.", "art.", "scient.", "psych.",
    "Chr.", "Th.", "Joh.", "Vilh.", "Ludv.", "Fred.", "Carl.", "Aug.", "Sept.", "Okt.", "Nov.", "Dec.", "Jan.", "Febr.", "Apr.", "Mar.",
    "jan.", "febr.", "mar.", "apr.", "aug.", "sept.", "okt.", "nov.", "dec.",
    "Sø.", "Sg.", "Hrd.", "A.", "Kr.", "kr.", "Nr.", "nr.", "Bd.", "bd.", "s.", "sp.", "res.", "kapt.", "lt.", "oberstlt.", "gen.", "genlt.", "genm.",
    "prem.", "sek.", "vicepr.", "Sen.", "Jr.", "e.Kr.", "f.Kr."
  ],
  "initial_pattern": "(?:^|\\s)[A-ZÆØÅ]\\.$",
  "ordinal_number_pattern": "(?:^|\\s)\\d{1,2}\\.$",
  "structural_header_patterns": [
    "^(Første|Andet|Tredje|Fjerde|Femte|Sjette|Syvende|Ottende|Niende|Tiende|Ellevte|Tolvte|Trettende|Fjortende|Femtende|Sekstende) slægtled\\b",
    "^[IVXLC]+\\.?\\s+(Linje|linje|Gren|gren)\\b"
  ],
  "min_clause_chars": 12,
  "gap_charset": [" "],
  "intraword_chars": ["‑", "­"]
}
```

Listen er et startpunkt; 4.1b's rigtige kørsel (Task 5) måler, hvilke korte tokens før punktum der *ikke* står på listen, og de tilføjes i en ny regelversion efter menneskelig gennemgang af **tokens** (ikke tekst).

- [ ] **Step 4: Validér `clause_rules` i `load_profile`**

I `evidence_extract.py` efter `if not all(isinstance(profile[key], str) ...)`:

```python
CLAUSE_RULE_KEYS = {"version", "terminators", "non_terminal_abbreviations", "initial_pattern",
                    "ordinal_number_pattern", "structural_header_patterns", "min_clause_chars",
                    "gap_charset", "intraword_chars"}


def validate_clause_rules(rules: Any) -> None:
    if not isinstance(rules, Mapping) or set(rules) != CLAUSE_RULE_KEYS:
        raise ExtractionError("EXTRACTION_CLAUSE_RULES_INVALID")
    if not isinstance(rules["version"], str) or not rules["version"].strip():
        raise ExtractionError("EXTRACTION_CLAUSE_RULES_INVALID")
    for key in ("terminators", "non_terminal_abbreviations", "structural_header_patterns", "gap_charset", "intraword_chars"):
        if not isinstance(rules[key], list) or not all(isinstance(v, str) and v for v in rules[key]):
            raise ExtractionError("EXTRACTION_CLAUSE_RULES_INVALID")
    if not rules["terminators"] or not rules["gap_charset"]:
        raise ExtractionError("EXTRACTION_CLAUSE_RULES_INVALID")
    for key in ("initial_pattern", "ordinal_number_pattern"):
        try:
            re.compile(rules[key])
        except (re.error, TypeError):
            raise ExtractionError("EXTRACTION_CLAUSE_RULES_INVALID")
    for pattern in rules["structural_header_patterns"]:
        try:
            re.compile(pattern)
        except re.error:
            raise ExtractionError("EXTRACTION_CLAUSE_RULES_INVALID")
    if not isinstance(rules["min_clause_chars"], int) or isinstance(rules["min_clause_chars"], bool) or rules["min_clause_chars"] < 1:
        raise ExtractionError("EXTRACTION_CLAUSE_RULES_INVALID")
```

og i `load_profile`, før `return`:

```python
    if "clause_rules" in profile:
        validate_clause_rules(profile["clause_rules"])
```

Tilføj `import re` øverst.

- [ ] **Step 5: Kør testene**

```bash
/usr/bin/python3 -m pytest .claude/skills/daa-extract/scripts/test_evidence_extract.py -q
```

Forventet: PASS.

- [ ] **Step 6: Commit**

```bash
git branch --show-current
git add .claude/skills/daa-extract/references/extraction-profiles.json .claude/skills/daa-extract/scripts/evidence_extract.py .claude/skills/daa-extract/scripts/test_evidence_extract.py
git commit -m "feat(evidens): clause_rules i 2018-20-profilen v1.1.0 med validering (#148 4.1b)"
```

---

### Task 2: Syntetisk svær fixture + fejlende segmenteringstests

**Files:**
- Create: `.claude/skills/daa-extract/scripts/tests/fixtures/evidence-clauses.synthetic.json`
- Create: `.claude/skills/daa-extract/scripts/test_clause_segment.py`

**Interfaces:**
- Consumes: `clause_segment.segment_clauses(text: str, rules: Mapping) -> list[dict]` (Task 3) — hver dict har `char_from`, `char_to`, `classification` (`record_text` | `structural_header` | `layout`), `flags` (liste af strenge), `verbatim_text`.
- Consumes: `clause_segment.build_record_ledger(record_key: str, occurrence_key: str, text: str, rules: Mapping) -> dict` (Task 3) med nøglerne `ledger` (fra `clause_ledger.build_ledger`), `clauses` (kun `record_text`/`structural_header`, med `ordinal` fra 1), `gap_violations` (liste af tegn uden for `gap_charset`), `ledger_sha256`.

- [ ] **Step 1: Skriv fixturen (syntetisk, ingen rigtige personer)**

Task 2's syv tilfælde fra 2026-08-02-planen, som records med forventet klausulantal og flag:

```json
{
  "schema_version": "evidence-clauses-fixture-1.0",
  "cases": [
    {"key": "samme-mand-tre-gange", "text": "Alfa Bravo, f. 12. maj 1801 i Charlie, d. 3. jan. 1860 sst. Gift 1830 m. Delta Echo. Alfa Bravo nævnes 1845 som ejer af Foxtrot. Alfa Bravo, den samme, solgte Foxtrot 1852.",
     "expect_clauses": 4, "expect_flags": []},
    {"key": "barn-og-grundlaegger", "text": "Golf Hotel, f. 1770, søn af nr. 3. Stamfader til den yngre linje, se II. Gift 1795 m. India Juliet.",
     "expect_clauses": 3, "expect_flags": []},
    {"key": "gift-med-niece", "text": "Kilo Lima, f. 1800, d. 1870. Gift 1825 m. sin broderdatter Mike November af 7. slægtled, f. 1806, d. 1880, datter af nr. 12.",
     "expect_clauses": 2, "expect_flags": []},
    {"key": "indgiftet-uden-slaegtsnavn", "text": "Oscar Papa, f. 1810. Gift 1835 m. Quebec, f. 1815, d. 1890, datter af gårdejer Romeo Sierra og Tango.",
     "expect_clauses": 2, "expect_flags": []},
    {"key": "titel-og-embede", "text": "Uniform Victor, f. 1820, Kmh., amtmand over Whiskey Amt 1860-1875, R. af Dbg. Gift 1848 m. X-ray Yankee.",
     "expect_clauses": 2, "expect_flags": []},
    {"key": "usikker-ukendt-manglende-dato", "text": "Zulu Alfa, f. ca. 1790 (?), d. efter 1850. Gift m. Bravo, hvis herkomst er ukendt. Død i Charlie, år ukendt.",
     "expect_clauses": 3, "expect_flags": ["uncertain_marker"]},
    {"key": "modstridende-kilder", "text": "Delta Echo, f. 1805 (ifølge DAA 1901: 1806), d. 1877. Gift 1830 m. Foxtrot Golf; gift 2. gang 1850 m. Hotel India.",
     "expect_clauses": 3, "expect_flags": ["multiple_marriages"]},
    {"key": "ukendt-forkortelse", "text": "Juliet Kilo, f. 1830, xyzq. 1850 i Lima. Gift 1855 m. Mike.",
     "expect_clauses": 2, "expect_flags": ["unknown_abbreviation"]},
    {"key": "ubalanceret-parentes", "text": "November Oscar, f. 1840 (søn af nr. 5. Gift 1865 m. Papa.",
     "expect_clauses": 1, "expect_flags": ["unbalanced_parentheses"]},
    {"key": "kort-post", "text": "Quebec Romeo.", "expect_clauses": 1, "expect_flags": ["short_clause"]},
    {"key": "struktur-overskrift", "text": "Femte slægtled. Sierra Tango, f. 1850, d. 1910.",
     "expect_clauses": 2, "expect_flags": [], "expect_structural": 1}
  ]
}
```

- [ ] **Step 2: Skriv testene**

```python
import json
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(__file__))

import clause_ledger
import clause_segment
import evidence_extract

FIXTURE = os.path.join(os.path.dirname(__file__), "tests", "fixtures", "evidence-clauses.synthetic.json")


def rules():
    return evidence_extract.load_profile("daa-2018-20-v1")["clause_rules"]


class TestClauseSegment(unittest.TestCase):
    def setUp(self):
        with open(FIXTURE, encoding="utf-8") as fh:
            self.cases = json.load(fh)["cases"]
        self.rules = rules()

    def test_fixture_cases_segment_as_expected(self):
        for case in self.cases:
            with self.subTest(case["key"]):
                result = clause_segment.build_record_ledger(case["key"], f"source-evidence:{case['key']}", case["text"], self.rules)
                clause_ledger.validate_ledger(result["ledger"], case["text"])
                self.assertEqual(len(result["clauses"]), case["expect_clauses"])
                flags = sorted({flag for clause in result["clauses"] for flag in clause["flags"]})
                self.assertEqual(flags, sorted(case["expect_flags"]))
                structural = sum(1 for c in result["clauses"] if c["classification"] == "structural_header")
                self.assertEqual(structural, case.get("expect_structural", 0))
                self.assertEqual(result["gap_violations"], [])

    def test_clauses_are_exact_substrings_with_one_based_ordinals(self):
        text = self.cases[0]["text"]
        result = clause_segment.build_record_ledger("k", "source-evidence:k", text, self.rules)
        for expected_ordinal, clause in enumerate(result["clauses"], 1):
            self.assertEqual(clause["ordinal"], expected_ordinal)
            self.assertEqual(text[clause["char_from"]:clause["char_to"]], clause["verbatim_text"])
            self.assertNotEqual(clause["verbatim_text"].strip(), "")

    def test_ledger_never_carries_uuids_and_uses_record_scoped_ids(self):
        result = clause_segment.build_record_ledger("rec-1", "source-evidence:rec-1", self.cases[0]["text"], self.rules)
        for row in result["ledger"]:
            self.assertEqual(row["occurrence_id"], "source-evidence:rec-1")
            for oid in row["observation_ids"]:
                self.assertRegex(oid, r"^rec-1#\d+$")

    def test_gap_outside_charset_is_reported_not_swallowed(self):
        text = "Alfa Bravo, f. 1801. Gift 1830 m. Charlie."  # NBSP mellem klausuler
        result = clause_segment.build_record_ledger("k", "source-evidence:k", text, self.rules)
        self.assertEqual(result["gap_violations"], [" "])

    def test_ledger_sha_is_stable_for_same_input(self):
        a = clause_segment.build_record_ledger("k", "source-evidence:k", self.cases[0]["text"], self.rules)
        b = clause_segment.build_record_ledger("k", "source-evidence:k", self.cases[0]["text"], self.rules)
        self.assertEqual(a["ledger_sha256"], b["ledger_sha256"])
        self.assertRegex(a["ledger_sha256"], r"^[0-9a-f]{64}$")


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 3: Kør og se dem fejle**

```bash
/usr/bin/python3 -m pytest .claude/skills/daa-extract/scripts/test_clause_segment.py -q
```

Forventet: FAIL (`ModuleNotFoundError: clause_segment`).

- [ ] **Step 4: Commit**

```bash
git branch --show-current
git add .claude/skills/daa-extract/scripts/tests/fixtures/evidence-clauses.synthetic.json .claude/skills/daa-extract/scripts/test_clause_segment.py
git commit -m "test(evidens): svær syntetisk klausul-fixture og segmenteringstests (#148 4.1b)"
```

---

### Task 3: `clause_segment.py`

**Files:**
- Create: `.claude/skills/daa-extract/scripts/clause_segment.py`

**Interfaces:**
- Produces: `segment_clauses(text, rules) -> list[dict]` og `build_record_ledger(record_key, occurrence_key, text, rules) -> dict` som beskrevet i Task 2. `FLAGS = ("unknown_abbreviation", "unbalanced_parentheses", "short_clause", "multiple_marriages", "uncertain_marker")`.

- [ ] **Step 1: Implementér**

```python
#!/usr/bin/env python3
"""Deterministisk klausul-segmentering af én helpost (spec #148, 4.1b).

Ingen modelkald. Reglerne kommer fra udgaveprofilen; motoren kender kun
mekanikken. Tvivl segmenteres konservativt (længere klausul) og flagges.
Alle offsets er helpost-relative.
"""
from __future__ import annotations

import hashlib
import json
import re
from typing import Any, Mapping

import clause_ledger

FLAGS = ("unknown_abbreviation", "unbalanced_parentheses", "short_clause",
         "multiple_marriages", "uncertain_marker")
_MARRIAGE_RE = re.compile(r"\bgift\b", re.IGNORECASE)
_WORD_BEFORE_DOT_RE = re.compile(r"(\S+)\.$")


def _canonical(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def _is_non_terminal(prefix: str, rules: Mapping[str, Any]) -> tuple[bool, bool]:
    """Returnér (må ikke splittes her, ukendt kort token). prefix slutter på '.'"""
    match = _WORD_BEFORE_DOT_RE.search(prefix)
    if not match:
        return False, False
    token = match.group(1) + "."
    if token in rules["non_terminal_abbreviations"]:
        return True, False
    if re.search(rules["initial_pattern"], prefix):
        return True, False
    if re.search(rules["ordinal_number_pattern"], prefix):
        return True, False
    bare = match.group(1).strip("()[]")
    if bare and bare.isalpha() and len(bare) <= 4 and not bare[0].isupper():
        return True, True  # ukendt kort forkortelse: split ikke, men flag
    return False, False


def _split_points(text: str, rules: Mapping[str, Any]) -> list[tuple[int, list[str]]]:
    """Positioner (indeks i text hvor en ny klausul begynder) + flag for den klausul, der slutter der."""
    points: list[tuple[int, list[str]]] = []
    for terminator in rules["terminators"]:
        start = 0
        while True:
            idx = text.find(terminator, start)
            if idx < 0:
                break
            end_of_clause = idx + len(terminator.rstrip())
            next_start = idx + len(terminator)
            flags: list[str] = []
            if terminator.startswith("."):
                blocked, unknown = _is_non_terminal(text[:idx + 1], rules)
                if unknown:
                    flags.append("unknown_abbreviation")
                if blocked:
                    if unknown:
                        points.append((-next_start, flags))  # negativ = kun flag, ingen split
                    start = next_start
                    continue
            nxt = text[next_start:next_start + 1]
            if nxt and (nxt.isupper() or nxt.isdigit() or nxt in "†([\"“"):
                points.append((next_start, flags))
            start = next_start
    return points


def segment_clauses(text: str, rules: Mapping[str, Any]) -> list[dict[str, Any]]:
    if text != text.strip() or "\n" in text:
        raise ValueError("CLAUSE_TEXT_NOT_NORMALIZED")
    if not text:
        raise ValueError("CLAUSE_TEXT_EMPTY")
    raw_points = _split_points(text, rules)
    starts = sorted({p for p, _ in raw_points if p > 0})
    pending_flags: dict[int, list[str]] = {}
    for p, flags in raw_points:
        pending_flags.setdefault(abs(p), []).extend(flags)
    bounds = [0] + starts + [len(text)]
    clauses: list[dict[str, Any]] = []
    for a, b in zip(bounds, bounds[1:]):
        piece = text[a:b]
        lead = len(piece) - len(piece.lstrip())
        trail = len(piece) - len(piece.rstrip())
        if lead:
            clauses.append({"char_from": a, "char_to": a + lead, "classification": "layout", "flags": []})
        cf, ct = a + lead, b - trail
        if ct > cf:
            flags = sorted(set(f for pos, fl in pending_flags.items() if cf < pos <= ct for f in fl))
            clause_text = text[cf:ct]
            if clause_text.count("(") != clause_text.count(")") or clause_text.count("[") != clause_text.count("]"):
                flags.append("unbalanced_parentheses")
            if len(_MARRIAGE_RE.findall(clause_text)) > 1:
                flags.append("multiple_marriages")
            if "?" in clause_text:
                flags.append("uncertain_marker")
            if len(clause_text) < rules["min_clause_chars"]:
                flags.append("short_clause")
            classification = "structural_header" if any(re.search(p, clause_text) for p in rules["structural_header_patterns"]) else "record_text"
            clauses.append({"char_from": cf, "char_to": ct, "classification": classification, "flags": sorted(set(flags))})
        if trail:
            clauses.append({"char_from": ct, "char_to": b, "classification": "layout", "flags": []})
    # Ubalanceret parentes: flet klausulerne fra den åbne parentes og frem til én (konservativt).
    merged: list[dict[str, Any]] = []
    open_depth = 0
    for clause in clauses:
        piece = text[clause["char_from"]:clause["char_to"]]
        if merged and merged[-1]["classification"] != "layout" and clause["classification"] != "layout" and open_depth > 0:
            last = merged[-1]
            last["char_to"] = clause["char_to"]
            last["flags"] = sorted(set(last["flags"]) | set(clause["flags"]) | {"unbalanced_parentheses"})
            # opslug layout-spannet mellem de to
            if len(merged) >= 2 and merged[-2]["classification"] == "layout" and merged[-2]["char_to"] == last["char_from"]:
                pass
        else:
            merged.append(dict(clause))
        if clause["classification"] != "layout":
            open_depth += piece.count("(") - piece.count(")")
            open_depth = max(open_depth, 0)
    # Efter fletning kan layout-spans ligge inde i en flettet klausul; fjern dem.
    result: list[dict[str, Any]] = []
    for clause in merged:
        if result and clause["char_from"] < result[-1]["char_to"]:
            continue
        result.append(clause)
    # Sammenhængende dækning: layout-spans mellem klausuler, der ikke længere findes, genskabes.
    filled: list[dict[str, Any]] = []
    cursor = 0
    for clause in result:
        if clause["char_from"] > cursor:
            filled.append({"char_from": cursor, "char_to": clause["char_from"], "classification": "layout", "flags": []})
        filled.append(clause)
        cursor = clause["char_to"]
    if cursor < len(text):
        filled.append({"char_from": cursor, "char_to": len(text), "classification": "layout", "flags": []})
    for clause in filled:
        clause["verbatim_text"] = text[clause["char_from"]:clause["char_to"]]
    return filled


def build_record_ledger(record_key: str, occurrence_key: str, text: str, rules: Mapping[str, Any]) -> dict[str, Any]:
    if not record_key or not occurrence_key:
        raise ValueError("CLAUSE_RECORD_KEYS_REQUIRED")
    pieces = segment_clauses(text, rules)
    ordinal = 0
    ledger_input = []
    clauses = []
    gap_violations: list[str] = []
    for piece in pieces:
        if piece["classification"] == "layout":
            for ch in piece["verbatim_text"]:
                if ch not in rules["gap_charset"] and ch not in gap_violations:
                    gap_violations.append(ch)
            ledger_input.append({"char_from": piece["char_from"], "char_to": piece["char_to"], "classification": "layout",
                                 "observation_ids": [], "occurrence_id": occurrence_key, "record_key": record_key})
            continue
        ordinal += 1
        observation_id = f"{record_key}#{ordinal}"
        ledger_input.append({"char_from": piece["char_from"], "char_to": piece["char_to"],
                             "classification": piece["classification"], "observation_ids": [observation_id],
                             "occurrence_id": occurrence_key, "record_key": record_key})
        clauses.append({"ordinal": ordinal, "char_from": piece["char_from"], "char_to": piece["char_to"],
                        "classification": piece["classification"], "flags": piece["flags"],
                        "verbatim_text": piece["verbatim_text"],
                        "verbatim_sha256": hashlib.sha256(piece["verbatim_text"].encode("utf-8")).hexdigest()})
    ledger = clause_ledger.build_ledger(text, ledger_input)
    clause_ledger.validate_ledger(ledger, text)
    ledger_sha256 = hashlib.sha256(_canonical([{k: v for k, v in row.items() if k != "verbatim_text"} for row in ledger]).encode("utf-8")).hexdigest()
    return {"record_key": record_key, "occurrence_key": occurrence_key, "rules_version": rules["version"],
            "ledger": ledger, "clauses": clauses, "gap_violations": gap_violations, "ledger_sha256": ledger_sha256}
```

Bemærk: `ledger_sha256` udelader `verbatim_text` fra hashinput, så manifestet i 4.1c kan bære hashen uden at bære tekst; klausulteksten er dækket af `verbatim_sha256` pr. klausul.

- [ ] **Step 2: Kør testene, ret indtil grøn**

```bash
/usr/bin/python3 -m pytest .claude/skills/daa-extract/scripts/test_clause_segment.py -q
/usr/bin/python3 -m pytest .claude/skills/daa-extract/scripts/test_clause_ledger.py -q
```

Forventet: PASS. Hvis fixturens forventede tal ikke rammes for et tilfælde, er det **reglerne eller fixturen**, der justeres med begrundelse i commit-beskeden — aldrig testens assertion alene.

- [ ] **Step 3: Commit**

```bash
git branch --show-current
git add .claude/skills/daa-extract/scripts/clause_segment.py
git commit -m "feat(evidens): deterministisk klausul-segmentering med flag og fuld dækning (#148 4.1b)"
```

---

### Task 4: Læse-kun eksport af helposter + ledger-CLI

**Files:**
- Create: `.claude/skills/daa-extract/scripts/export_clause_source_texts.R`
- Create: `.claude/skills/daa-extract/scripts/build_clause_ledger.py`
- Create: `.claude/skills/daa-extract/scripts/test_build_clause_ledger.py`

**Interfaces:**
- `export_clause_source_texts.R --source-id <n> --output-dir <0700-mappe>` skriver `clause-source-texts-v1.json` (0600) med rækker `{record_key, occurrence_key, page_from, page_to, char_from, char_to, verbatim_text, verbatim_sha256, rendition_content_sha256}` og `clause-source-index-v1.json` (uden tekst).
- `build_clause_ledger.py --profile daa-2018-20-v1 --texts <fil> --output-dir <0700-mappe>` skriver `clause-ledger-v1.json` (0600; pr. record: `record_key`, `occurrence_key`, `rules_version`, `ledger_sha256`, `clauses[]` med `ordinal`, `char_from`, `char_to`, `classification`, `flags`, `verbatim_sha256` — **uden** `verbatim_text`), `clause-ledger-texts-v1.json` (0600; klausultekster, kun til 4.1c's lokale hash-verifikation) og `clause-ledger-summary.json` (kun aggregater: records, klausuler min/median/max, flag-fordeling, `structural_header`-antal, `gap_violations` som kodepunkter, `unknown_abbreviation`-tokens som *tokens* uden kontekst).

- [ ] **Step 1: Skriv CLI-testen**

```python
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
            with open(texts, "w", encoding="utf-8") as fh:
                json.dump([{"record_key": "I.1", "occurrence_key": "source-evidence:I.1", "page_from": 10, "page_to": 10,
                            "char_from": 100, "char_to": 145, "verbatim_text": "Alfa Bravo, f. 1801, d. 1860. Gift 1830 m. Charlie.",
                            "verbatim_sha256": "0" * 64, "rendition_content_sha256": "1" * 64}], fh)
            out = os.path.join(tmp, "out"); os.mkdir(out); os.chmod(out, 0o700)
            proc = subprocess.run([sys.executable, os.path.join(HERE, "build_clause_ledger.py"), "--profile", "daa-2018-20-v1",
                                   "--texts", texts, "--output-dir", out], capture_output=True, text=True)
            self.assertEqual(proc.returncode, 0, proc.stderr)
            with open(os.path.join(out, "clause-ledger-v1.json"), encoding="utf-8") as fh:
                ledger = json.load(fh)
            self.assertEqual(ledger["schema_version"], "clause-ledger-v1")
            self.assertEqual(len(ledger["records"]), 1)
            self.assertNotIn("verbatim_text", json.dumps(ledger))
            with open(os.path.join(out, "clause-ledger-summary.json"), encoding="utf-8") as fh:
                summary = json.load(fh)
            self.assertEqual(summary["records"], 1)
            self.assertEqual(summary["clauses"]["total"], 2)
            self.assertNotIn("Alfa", json.dumps(summary))
            self.assertEqual(oct(os.stat(os.path.join(out, "clause-ledger-texts-v1.json")).st_mode & 0o777), "0o600")

    def test_cli_refuses_output_dir_with_work_component_or_wrong_mode(self):
        with tempfile.TemporaryDirectory() as tmp:
            bad = os.path.join(tmp, "work"); os.mkdir(bad); os.chmod(bad, 0o700)
            proc = subprocess.run([sys.executable, os.path.join(HERE, "build_clause_ledger.py"), "--profile", "daa-2018-20-v1",
                                   "--texts", os.path.join(tmp, "missing.json"), "--output-dir", bad], capture_output=True, text=True)
            self.assertNotEqual(proc.returncode, 0)
            self.assertIn("OUTPUT_WORK_PATH", proc.stderr)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Kør og se den fejle**

```bash
/usr/bin/python3 -m pytest .claude/skills/daa-extract/scripts/test_build_clause_ledger.py -q
```

Forventet: FAIL (script findes ikke).

- [ ] **Step 3: Skriv `build_clause_ledger.py`**

```python
#!/usr/bin/env python3
"""Byg klausul-ledger for alle records i en privat teksteksport (#148, 4.1b).

Læser ingen database. Skriver kun til en 0700-mappe uden 'work'-komponent.
Ledger-filen bærer ingen tekst; teksterne ligger i en separat 0600-fil.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import statistics
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import clause_segment  # noqa: E402
import evidence_extract  # noqa: E402


def _fail(code: str) -> None:
    print(code, file=sys.stderr)
    raise SystemExit(2)


def _validate_output_dir(path: str) -> Path:
    p = Path(path)
    if not p.is_absolute():
        _fail("OUTPUT_DIR_NOT_ABSOLUTE")
    if any(part == "work" or part.startswith("work_") for part in p.parts):
        _fail("OUTPUT_WORK_PATH")
    if not p.is_dir() or p.is_symlink():
        _fail("OUTPUT_DIR_INVALID")
    if (p.stat().st_mode & 0o777) != 0o700:
        _fail("OUTPUT_DIR_MODE_INVALID")
    return p


def _write_private(path: Path, payload) -> None:
    if path.exists():
        _fail("OUTPUT_EXISTS")
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        json.dump(payload, fh, ensure_ascii=False, indent=1, sort_keys=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--profile", required=True)
    parser.add_argument("--texts", required=True)
    parser.add_argument("--output-dir", required=True)
    args = parser.parse_args()
    out = _validate_output_dir(args.output_dir)
    profile = evidence_extract.load_profile(args.profile)
    rules = profile.get("clause_rules")
    if not rules:
        _fail("PROFILE_CLAUSE_RULES_MISSING")
    try:
        rows = json.loads(Path(args.texts).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        _fail("TEXTS_UNREADABLE")
    records, texts, flag_counter, unknown_tokens, gap_chars = [], {}, Counter(), Counter(), Counter()
    counts = []
    structural = 0
    for row in rows:
        text = row["verbatim_text"]
        if hashlib.sha256(text.encode("utf-8")).hexdigest() != row["verbatim_sha256"] and row["verbatim_sha256"] != "0" * 64:
            _fail("TEXT_HASH_MISMATCH:" + row["record_key"])
        result = clause_segment.build_record_ledger(row["record_key"], row["occurrence_key"], text, rules)
        for ch in result["gap_violations"]:
            gap_chars["U+%04X" % ord(ch)] += 1
        clauses = []
        for clause in result["clauses"]:
            flag_counter.update(clause["flags"])
            if "unknown_abbreviation" in clause["flags"]:
                for token in clause["verbatim_text"].split():
                    if token.endswith(".") and len(token) <= 5 and token not in rules["non_terminal_abbreviations"]:
                        unknown_tokens[token] += 1
            if clause["classification"] == "structural_header":
                structural += 1
            texts[f"{row['record_key']}#{clause['ordinal']}"] = clause["verbatim_text"]
            clauses.append({k: clause[k] for k in ("ordinal", "char_from", "char_to", "classification", "flags", "verbatim_sha256")})
        counts.append(len(clauses))
        records.append({"record_key": row["record_key"], "occurrence_key": row["occurrence_key"],
                        "page_from": row["page_from"], "page_to": row["page_to"],
                        "parent_char_from": row["char_from"], "parent_char_to": row["char_to"],
                        "parent_verbatim_sha256": row["verbatim_sha256"],
                        "rendition_content_sha256": row["rendition_content_sha256"],
                        "rules_version": rules["version"], "ledger_sha256": result["ledger_sha256"], "clauses": clauses})
    ledger = {"schema_version": "clause-ledger-v1", "profile_id": args.profile, "profile_version": profile["version"],
              "rules_version": rules["version"], "segmenter_version": "clause_segment.py@v1", "records": records}
    _write_private(out / "clause-ledger-v1.json", ledger)
    _write_private(out / "clause-ledger-texts-v1.json", texts)
    summary = {"records": len(records), "clauses": {"total": sum(counts), "min": min(counts) if counts else 0,
               "median": statistics.median(counts) if counts else 0, "max": max(counts) if counts else 0},
               "flags": dict(flag_counter), "structural_header": structural,
               "gap_violations": dict(gap_chars), "unknown_abbreviation_tokens": dict(unknown_tokens.most_common(50)),
               "ledger_file_sha256": hashlib.sha256((out / "clause-ledger-v1.json").read_bytes()).hexdigest()}
    _write_private(out / "clause-ledger-summary.json", summary)
    print(json.dumps({k: summary[k] for k in ("records", "clauses", "flags", "structural_header", "gap_violations", "ledger_file_sha256")}, ensure_ascii=False))


if __name__ == "__main__":
    main()
```

- [ ] **Step 4: Skriv `export_clause_source_texts.R`** (samme mønster som `export_legacy_migration_candidates.R`: kun `--source-id`/`--output-dir`, READ ONLY-transaktion, 0700-mappe uden `work`, 0600-filer, exit ≠ 0 hvis filer findes)

```r
#!/usr/bin/env Rscript
# Læse-kun eksport af helposter (occurrence-tekster) til klausul-segmentering (#148 4.1b).
# Åbner en REPEATABLE READ READ ONLY transaktion og ruller altid tilbage.
suppressPackageStartupMessages({ library(DBI); library(RPostgres); library(jsonlite); library(digest) })
args <- commandArgs(trailingOnly = TRUE)
flags <- args[grepl("^--", args)]
allowed <- c("--source-id", "--output-dir")
if (any(!flags %in% allowed) || anyDuplicated(flags) || !all(allowed %in% flags)) stop("EXPORT_CLI_INVALID", call. = FALSE)
value <- function(flag) { i <- match(flag, args); if (is.na(i) || i == length(args) || grepl("^--", args[[i + 1L]])) stop("EXPORT_CLI_INVALID", call. = FALSE); args[[i + 1L]] }
script_dir <- dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE)[1L])))
source(file.path(script_dir, "export_legacy_migration_candidates_helpers.R"))  # genbrug lmc_validate_output_dir
source_id <- suppressWarnings(as.integer(value("--source-id"))); if (is.na(source_id) || source_id <= 0L) stop("EXPORT_CLI_INVALID", call. = FALSE)
output_dir <- lmc_validate_output_dir(value("--output-dir"))
texts_path <- file.path(output_dir, "clause-source-texts-v1.json"); index_path <- file.path(output_dir, "clause-source-index-v1.json")
if (file.exists(texts_path) || file.exists(index_path)) stop("EXPORT_OUTPUT_EXISTS", call. = FALSE)
con <- DBI::dbConnect(RPostgres::Postgres(), dbname = Sys.getenv("PGDATABASE"), host = Sys.getenv("PGHOST"), port = Sys.getenv("PGPORT"), user = Sys.getenv("PGUSER"), password = Sys.getenv("PGPASSWORD"))
on.exit(DBI::dbDisconnect(con), add = TRUE)
DBI::dbExecute(con, "BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY")
rows <- DBI::dbGetQuery(con, "
  SELECT sr.record_key, o.occurrence_key, ob.page_from, ob.page_to, ob.char_from, ob.char_to, ob.verbatim_text,
         encode(extensions.digest(ob.verbatim_text,'sha256'),'hex') AS verbatim_sha256, r.content_sha256 AS rendition_content_sha256
    FROM private.source_observation ob
    JOIN private.source_record_occurrence o ON o.id=ob.occurrence_id
    JOIN private.source_rendition r ON r.id=o.rendition_id
    JOIN private.source_record_anchor_current a ON a.occurrence_id=o.id AND a.decision_status='accepted'
    JOIN private.source_record sr ON sr.id=a.source_record_id
   WHERE r.source_id=$1 AND ob.parent_observation_id IS NULL
   ORDER BY sr.record_key COLLATE \"C\"", params = list(source_id))
DBI::dbExecute(con, "ROLLBACK")
if (nrow(rows) == 0L) stop("EXPORT_NO_ROWS", call. = FALSE)
if (anyDuplicated(rows$record_key)) stop("EXPORT_RECORD_KEY_NOT_UNIQUE", call. = FALSE)
file.create(texts_path); Sys.chmod(texts_path, "0600")
jsonlite::write_json(rows, texts_path, auto_unbox = TRUE, null = "null", digits = NA, pretty = TRUE)
jsonlite::write_json(rows[, setdiff(names(rows), "verbatim_text")], index_path, auto_unbox = TRUE, null = "null", digits = NA, pretty = TRUE)
cat(jsonlite::toJSON(list(records = nrow(rows), texts_sha256 = digest::digest(file = texts_path, algo = "sha256")), auto_unbox = TRUE), "\n")
```

- [ ] **Step 5: Kør Python-testene og CI-listen**

```bash
/usr/bin/python3 -m pytest .claude/skills/daa-extract/scripts/test_build_clause_ledger.py .claude/skills/daa-extract/scripts/test_clause_segment.py -q
```

Forventet: PASS. Tilføj derefter begge testfiler til `.github/workflows/ci.yml` i jobbet `evidence contract · pytest` (linje 103's kommando: læg `.claude/skills/daa-extract/scripts/test_clause_segment.py .claude/skills/daa-extract/scripts/test_build_clause_ledger.py` til listen).

- [ ] **Step 6: Commit**

```bash
git branch --show-current
git add .claude/skills/daa-extract/scripts/build_clause_ledger.py .claude/skills/daa-extract/scripts/test_build_clause_ledger.py .claude/skills/daa-extract/scripts/export_clause_source_texts.R .github/workflows/ci.yml
git commit -m "feat(evidens): eksport af helposter og klausul-ledger-CLI med privat output (#148 4.1b)"
```

---

### Task 5: Rigtig kørsel på alle 591 records

**Files:**
- Modify: `docs/evidensbaseret-genimport/clause-evidence-148-rehearsal.md` (nyt afsnit "Dagsværk 4.1b")
- Modify: `docs/changelog.md`
- (Evt.) Modify: `.claude/skills/daa-extract/references/extraction-profiles.json` (ny regelversion efter token-gennemgang; kræver projektejerens GO)

Forudsætning: restore-basen fra 4.1a (`$DB`) med migration anvendt.

- [ ] **Step 1: Eksportér og segmentér**

```bash
set -euo pipefail; umask 077; export PGTZ=UTC PGHOST=localhost PGPORT=5432 PGUSER="$USER" PGDATABASE="$DB"
ART="$HOME/.private/148b-$(date +%Y%m%d%H%M%S)"; mkdir -p "$ART/export" "$ART/ledger"; chmod 700 "$ART" "$ART/export" "$ART/ledger"
Rscript .claude/skills/daa-extract/scripts/export_clause_source_texts.R --source-id 1 --output-dir "$ART/export"
cd .claude/skills/daa-extract/scripts
/usr/bin/python3 build_clause_ledger.py --profile daa-2018-20-v1 --texts "$ART/export/clause-source-texts-v1.json" --output-dir "$ART/ledger"
cd -
```

Forventet: eksport `records: 591`; CLI printer summary-linjen (kun tal). Stop, hvis `gap_violations` ikke er tomt: så er `gap_charset` forkert målt, og profilen skal opdateres (ny regelversion) *før* næste skridt, ikke efter.

- [ ] **Step 2: Gennemgå ukendte forkortelser som tokens**

```bash
/usr/bin/python3 -c "import json;print(json.dumps(json.load(open('$ART/ledger/clause-ledger-summary.json'))['unknown_abbreviation_tokens'],ensure_ascii=False,indent=1))"
```

Outputtet er *tokens* (fx `"gm."`, `"cand."`), aldrig tekst. Tokens, der er ægte forkortelser, tilføjes til `non_terminal_abbreviations` i en ny `clause_rules.version` (`clause-rules-2018-20-v2`) og profilversion `1.2.0`. Det er en profilændring med `requires_human_go_for_change`: læg tokens frem for projektejeren, få GO, og kør Step 1 igen med den nye version. Tallene fra begge kørsler går i rapporten.

- [ ] **Step 3: Skriv rapportafsnittet (kun aggregater)**

Tilføj til `clause-evidence-148-rehearsal.md`:

```markdown
## Dagsværk 4.1b (segmentering)

Regelversion `<clause_rules.version>`, profilversion `<version>`, ledger-fil-SHA `<ledger_file_sha256>`, eksport-SHA `<texts_sha256>`.

| Måling | Værdi |
| --- | --- |
| Records | 591 |
| Klausuler i alt / min / median / max pr. record | … |
| Flag-fordeling | unknown_abbreviation …, unbalanced_parentheses …, short_clause …, multiple_marriages …, uncertain_marker … |
| `structural_header`-klausuler | … (0 betyder: ingen strukturelt kildemateriale i 2018-20's helposter, jf. spec 4.1.3) |
| Mellemrumstegn uden for hvidlisten | ingen |
| Tokens tilføjet i regelversion 2 (antal) | … |
```

- [ ] **Step 4: Changelog og commit**

```bash
git branch --show-current
git add docs/evidensbaseret-genimport/clause-evidence-148-rehearsal.md docs/changelog.md .claude/skills/daa-extract/references/extraction-profiles.json
git commit -m "docs(genimport): 4.1b klausul-segmentering kørt på alle 591 2018-20-records (#148)"
```

---

## Selvreview-checkliste

- [ ] Ingen fil i repo indeholder rigtige helposter eller klausultekster (grep efter `Reventlow` i nye filer skal give 0 hits uden for docs).
- [ ] `clause-ledger-v1.json` indeholder ikke `verbatim_text` (testen asserterer det).
- [ ] Ledgerens `occurrence_id`/`observation_ids` er nøgler, ikke UUID'er.
- [ ] Profilændringen (v1.1.0 og evt. v1.2.0) er nævnt for projektejeren som GO-punkt.
