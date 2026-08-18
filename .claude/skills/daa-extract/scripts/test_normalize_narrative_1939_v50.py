from __future__ import annotations

import difflib
import hashlib
import json
import re
from pathlib import Path

import pytest

import normalize_narrative_1939_v50 as subject
from normalize_narrative_1939_v50 import normalize_narrative_v1

PHASE_A_ANCHOR_MANIFEST_SHA256 = (
    "1945416b3b56e781787366008a2463b419cb8ed4df3ef1399211cac5c999e208"
)
PRODUCTION_WRITE_MANIFEST_SHA256 = (
    "8417b6deeaf32b3cf39a4f2995a06211f8368172dfa97a188e03c6f7ef379a1f"
)
CALAMARI_SHA256 = "020123a3588dacf80705a22fb021ab4f5da97b8de202e8664304ca01f9a6da37"

# Independently defined (not imported from the module under test) so a
# typo in the implementation's own pattern can't hide from this check.
_PAGE_MARKER_BLOCK_RE = re.compile(r"\n*### PAGE \d{4} ###\n*")


# ---------------------------------------------------------------------------
# Diff-class control: every character-level hunk between ``raw`` and the
# normalized ``text`` must belong to one of the five declared change
# classes. Shared by the mixed-fixture unit test and the corpus regression.
#
# Page-marker blocks are stripped out *before* diffing (via the same
# mechanical, judgment-free regex substitution the contract specifies),
# rather than being classified as part of the generic character diff.
# difflib's LCS-based opcodes can otherwise split one conceptual marker
# deletion into several oddly-shaped hunks -- a marker block is long and
# made of ordinary letters/digits/spaces, so it can spuriously "match" a
# few characters of unrelated surrounding prose and get chopped into
# pieces that don't individually look like a marker. Stripping first keeps
# the diff surgical for the four dewrap/ordinal classes, which is what
# this check actually needs to police.
# ---------------------------------------------------------------------------

_LEADING_TRIM_RE = re.compile(r"\s*(?:\d{1,2}\.\s+)?")


def _classify_hunk(raw: str, norm: str, i1: int, i2: int, j1: int, j2: int) -> str | None:
    raw_seg = raw[i1:i2]
    norm_seg = norm[j1:j2]

    if i1 == 0 and norm_seg == "" and _LEADING_TRIM_RE.fullmatch(raw_seg):
        return "leading_trim"
    if raw_seg == "\n" and norm_seg == " ":
        return "soft_wrap"
    if raw_seg == "-\n" and norm_seg == "":
        return "hyphen_merge"
    if raw_seg == "\n" and norm_seg == "" and i1 > 0 and raw[i1 - 1] == "-":
        return "hyphen_keep"
    if raw_seg and set(raw_seg) == {"\n"} and norm_seg == "" and i1 > 0 and raw[i1 - 1] == "\n":
        return "paragraph_collapse"
    return None


def assert_diff_classes_allowed(raw: str, norm: str) -> None:
    assert "### PAGE" not in norm, f"page marker leaked into normalized text: {norm!r}"

    marker_free = _PAGE_MARKER_BLOCK_RE.sub("\n", raw)
    sm = difflib.SequenceMatcher(None, marker_free, norm, autojunk=False)
    for tag, i1, i2, j1, j2 in sm.get_opcodes():
        if tag == "equal":
            continue
        cls = _classify_hunk(marker_free, norm, i1, i2, j1, j2)
        assert cls is not None, (
            f"unclassified diff hunk {tag} marker_free={marker_free[i1:i2]!r} -> "
            f"norm={norm[j1:j2]!r} "
            f"context={marker_free[max(0, i1 - 20):i2 + 20]!r}"
        )


# ---------------------------------------------------------------------------
# Step 1: rule-by-rule tests (contract points 1-6)
# ---------------------------------------------------------------------------


def test_afsnit_bevares():
    result = normalize_narrative_v1("a\n\nb", corpus="")
    assert result["text"] == "a\n\nb"
    assert result["flags"] == []

    result = normalize_narrative_v1("a\n\n\nb", corpus="")
    assert result["text"] == "a\n\nb"
    assert result["flags"] == []


def test_bloed_ombrydning():
    result = normalize_narrative_v1("linje1\nlinje2", corpus="")
    assert result["text"] == "linje1 linje2"
    assert result["applied"]["soft_breaks_joined"] == 1
    assert result["flags"] == []

    # Pre-existing double spaces are never collapsed beyond the one the
    # rule itself introduces.
    result = normalize_narrative_v1("linje1  \nlinje2", corpus="")
    assert result["text"] == "linje1   linje2"


def test_orddeling_lille_bogstav():
    result = normalize_narrative_v1("sammen-\ntrækkes", corpus="")
    assert result["text"] == "sammentrækkes"
    assert result["applied"]["hyphens_merged"] == 1
    assert result["applied"]["hyphens_kept_compound"] == 0
    assert result["flags"] == []


def test_kompositum_stort_bogstav():
    # Corpus corroborates the hyphenated form decisively (found unbroken
    # elsewhere), joined form is not present -- clean default+corroborated
    # keep, no flag needed.
    corpus = "Se Reventlow-Criminil andetsteds i bogen."
    result = normalize_narrative_v1("Reventlow-\nCriminil", corpus=corpus)
    assert result["text"] == "Reventlow-Criminil"
    assert result["applied"]["hyphens_kept_compound"] == 1
    assert result["applied"]["hyphens_merged"] == 0
    assert result["flags"] == []


def test_korpus_tiebreak():
    # (a) upper-case Y, but the corpus only has the JOINED form unbroken
    # elsewhere -> merge wins despite the upper-case default.
    corpus_joined_wins = "Se ReventlowCriminil andetsteds i bogen."
    result = normalize_narrative_v1("Reventlow-\nCriminil", corpus=corpus_joined_wins)
    assert result["text"] == "ReventlowCriminil"
    assert result["applied"]["hyphens_merged"] == 1
    assert result["applied"]["hyphens_kept_compound"] == 0
    assert result["flags"] == []

    # (b) lower-case Y, but the corpus only has the HYPHENATED form
    # unbroken elsewhere -> keep wins despite the lower-case default.
    corpus_hyphen_wins = "Se over-drager andetsteds i bogen."
    result = normalize_narrative_v1("over-\ndrager", corpus=corpus_hyphen_wins)
    assert result["text"] == "over-drager"
    assert result["applied"]["hyphens_kept_compound"] == 1
    assert result["applied"]["hyphens_merged"] == 0
    assert result["flags"] == []


def test_hyphen_uafklaret_flager():
    # Neither form present anywhere in the corpus -- case is the only
    # signal, corpus is inconclusive -> keep X-Y (default) AND flag.
    raw = "Reventlow-\nCriminil"
    result = normalize_narrative_v1(raw, corpus="intet relevant her")
    assert result["text"] == "Reventlow-Criminil"
    assert result["applied"]["hyphens_kept_compound"] == 1
    assert len(result["flags"]) == 1
    flag = result["flags"][0]
    assert flag["kind"] == "hyphen_ambiguous"
    assert flag["char_offset"] == raw.index("-")
    assert "Reventlow" in flag["context"] and "Criminil" in flag["context"]

    # Both forms present -- also inconclusive -> same fail-closed outcome.
    corpus_both = "ReventlowCriminil ... Reventlow-Criminil"
    result_both = normalize_narrative_v1(raw, corpus=corpus_both)
    assert result_both["text"] == "Reventlow-Criminil"
    assert len(result_both["flags"]) == 1
    assert result_both["flags"][0]["kind"] == "hyphen_ambiguous"


def test_ordenstal_strippes():
    result = normalize_narrative_v1("1. Sybille Malvina Lonny, f. 1800.", corpus="")
    assert result["text"] == "Sybille Malvina Lonny, f. 1800."
    assert result["applied"]["ordinal_stripped"] == 1
    assert result["flags"] == []

    # Also after a leading newline (OCR line-wrap noise before the digit).
    result = normalize_narrative_v1("\n1. Sybille Malvina Lonny, f. 1800.", corpus="")
    assert result["text"] == "Sybille Malvina Lonny, f. 1800."
    assert result["applied"]["ordinal_stripped"] == 1
    assert result["flags"] == []


def test_ordenstal_uden_punktum_flager():
    raw = "7 Heinrich til Gottesgabe (solgt 1708)."
    result = normalize_narrative_v1(raw, corpus="")
    assert result["text"] == raw
    assert result["applied"]["ordinal_stripped"] == 0
    assert len(result["flags"]) == 1
    flag = result["flags"][0]
    assert flag["kind"] == "ordinal_ambiguous"
    assert flag["char_offset"] == 0
    assert "Heinrich" in flag["context"]


def test_ordenstal_parentes_flager():
    raw = "2) Greve Conrad til Grevskabet Reventlow."
    result = normalize_narrative_v1(raw, corpus="")
    assert result["text"] == raw
    assert result["applied"]["ordinal_stripped"] == 0
    assert len(result["flags"]) == 1
    flag = result["flags"][0]
    assert flag["kind"] == "ordinal_ambiguous"
    assert flag["char_offset"] == 0
    assert "Conrad" in flag["context"]


def test_ordenstal_uden_ordenstal_uroert():
    # The "50 without" bucket: no digit-shaped prefix at all -- silently
    # untouched, unflagged.
    raw = "Greve Marie Eugen Stephan, f. 9 April 1896 i Berlin."
    result = normalize_narrative_v1(raw, corpus="")
    assert result["text"] == raw
    assert result["applied"]["ordinal_stripped"] == 0
    assert result["flags"] == []


def test_ingen_andre_aendringer():
    corpus = "Se Brahe-Trolleborg andetsteds i denne bog."
    raw = (
        "1. Wulf Erhardt gik til Kjøbenhvn (sic!), en Stavefejl forbliver "
        "urørt.\nHan skrev sammen-\ntrækkes og Brahe-\nTrolleborg som "
        "eksempel.\n\n\nNyt Afsnit her."
    )
    result = normalize_narrative_v1(raw, corpus=corpus)
    text = result["text"]

    # Untouched punctuation / spelling / OCR-noise survives verbatim.
    assert "Kjøbenhvn (sic!)" in text
    assert "en Stavefejl forbliver urørt." in text

    # Each declared rule fired as expected.
    assert "sammentrækkes" in text
    assert "Brahe-Trolleborg" in text
    assert "\n\n" in text
    assert text.count("\n\n\n") == 0

    assert result["applied"]["ordinal_stripped"] == 1
    assert result["applied"]["hyphens_merged"] == 1
    assert result["applied"]["hyphens_kept_compound"] == 1
    assert result["flags"] == []

    assert_diff_classes_allowed(raw, text)


def test_determinisme():
    corpus = "Se Brahe-Trolleborg andetsteds i denne bog."
    raw = (
        "1. Wulf Erhardt gik til Kjøbenhvn.\nHan skrev sammen-\ntrækkes og "
        "Brahe-\nTrolleborg."
    )
    first = normalize_narrative_v1(raw, corpus=corpus)
    second = normalize_narrative_v1(raw, corpus=corpus)
    assert first == second


# ---------------------------------------------------------------------------
# Interference cases explicitly called out in the brief.
# ---------------------------------------------------------------------------


def test_bindestreg_ved_afsnitsgraense():
    # A hyphen immediately followed by a genuine paragraph break: paragraph
    # collapsing runs first and leaves exactly two newlines behind, so the
    # hyphen rule (which only fires for exactly one trailing newline) must
    # never touch it.
    raw = "brud-\n\n\nOluf"
    result = normalize_narrative_v1(raw, corpus="")
    assert result["text"] == "brud-\n\nOluf"
    assert result["applied"]["hyphens_merged"] == 0
    assert result["applied"]["hyphens_kept_compound"] == 0
    assert result["flags"] == []


def test_ordinal_efter_ledende_whitespace_uden_ordenstal():
    # Leading whitespace-only trim (lstrip) with nothing ordinal-shaped
    # following it -- covers a real OCR artifact ("\n. Gese, ...").
    raw = "\n. Gese, gift før 1378 m. Matthias Ziesendorf."
    result = normalize_narrative_v1(raw, corpus="")
    assert result["text"] == ". Gese, gift før 1378 m. Matthias Ziesendorf."
    assert result["applied"]["ordinal_stripped"] == 0
    assert result["flags"] == []
    assert_diff_classes_allowed(raw, result["text"])


# ---------------------------------------------------------------------------
# Degenerate hyphen sites found empirically in the real 1939 corpus: not
# the illustrated word-hyphenation pattern at all (a numeral range, an
# abbreviation period right before the hyphen, or nothing left to join to).
# Fail closed: leave untouched, flag, never guess.
# ---------------------------------------------------------------------------


def test_hyphen_talomraade_uroert_og_flaget():
    raw = "Skivehus i Nørre H. (1735-\n50), Osterrade."
    result = normalize_narrative_v1(raw, corpus="")
    assert result["text"] == raw
    assert result["applied"]["hyphens_merged"] == 0
    assert result["applied"]["hyphens_kept_compound"] == 0
    assert len(result["flags"]) == 1
    assert result["flags"][0]["kind"] == "hyphen_ambiguous"


def test_hyphen_efter_forkortelsespunktum_uroert_og_flaget():
    raw = "1725 Sek.-\nMajor, 1733 kar. Oberst."
    result = normalize_narrative_v1(raw, corpus="")
    assert result["text"] == raw
    assert result["applied"]["hyphens_merged"] == 0
    assert result["applied"]["hyphens_kept_compound"] == 0
    assert len(result["flags"]) == 1
    assert result["flags"][0]["kind"] == "hyphen_ambiguous"


def test_hyphen_ved_tekstslutning_uroert_og_flaget():
    raw = "Foo-\n"
    result = normalize_narrative_v1(raw, corpus="")
    assert result["text"] == raw
    assert result["applied"]["hyphens_merged"] == 0
    assert result["applied"]["hyphens_kept_compound"] == 0
    assert len(result["flags"]) == 1
    assert result["flags"][0]["kind"] == "hyphen_ambiguous"


# ---------------------------------------------------------------------------
# Contract point 0 (extension): page-boundary marker blocks. A rendition
# may embed a literal ``### PAGE nnnn ###`` inside a person's verbatim
# span when it crosses a PDF page boundary, surrounded by any amount of
# blank-line "rendition structure" that is NOT a real paragraph break.
# ---------------------------------------------------------------------------


def test_sidemarkoer_prosa_fortsaettelse_bliver_mellemrum():
    # Prose that merely continues across a page turn: the whole marker
    # block collapses to ONE soft linebreak, never a paragraph break --
    # even though it visually looks like a blank-line-delimited block.
    raw = (
        "Dorothea g. o. 1560 m. hert.\n\n### PAGE 0019 ###\n"
        "gottorpsk Amtmand Ove Rantzau."
    )
    result = normalize_narrative_v1(raw, corpus="")
    assert result["text"] == (
        "Dorothea g. o. 1560 m. hert. gottorpsk Amtmand Ove Rantzau."
    )
    assert result["applied"]["page_markers_removed"] == 1
    assert result["applied"]["soft_breaks_joined"] == 1
    assert "### PAGE" not in result["text"]
    assert result["flags"] == []


def test_sidemarkoer_orddeling_sammentraekkes():
    # A word hyphenated across the page turn re-enters the ordinary
    # hyphen rule once the marker no longer sits between the halves:
    # lower-case continuation -> merge, exactly like any other
    # "sammen-\ntrækkes" case.
    raw = "Han var Med-\n\n### PAGE 0053 ###\nlem af Ordenen."
    result = normalize_narrative_v1(raw, corpus="")
    assert result["text"] == "Han var Medlem af Ordenen."
    assert result["applied"]["page_markers_removed"] == 1
    assert result["applied"]["hyphens_merged"] == 1
    assert result["applied"]["hyphens_kept_compound"] == 0
    assert "### PAGE" not in result["text"]
    assert result["flags"] == []


def test_sidemarkoer_kompositum_bevares():
    # Upper-case continuation across a page turn, corroborated by the
    # corpus -> kept as a compound, same as any other "Reventlow-\nY"
    # case, just with a marker sitting in the gap beforehand.
    raw = "Han ejede Rigsfri-\n\n### PAGE 0074 ###\nHerregaarden."
    corpus = "Se Rigsfri-Herregaarden andetsteds i bogen."
    result = normalize_narrative_v1(raw, corpus=corpus)
    assert result["text"] == "Han ejede Rigsfri-Herregaarden."
    assert result["applied"]["page_markers_removed"] == 1
    assert result["applied"]["hyphens_kept_compound"] == 1
    assert result["applied"]["hyphens_merged"] == 0
    assert "### PAGE" not in result["text"]
    assert result["flags"] == []


def test_sidemarkoer_blanklinje_varianter_alle_bliver_et_mellemrum():
    # However many blank lines surround the marker on either side, the
    # whole block is rendition structure, not a paragraph break -- it
    # always collapses to exactly one soft linebreak.
    variants = [
        "Foo.\n### PAGE 0001 ###\nBar.",
        "Foo.\n\n\n### PAGE 0002 ###\n\n\nBar.",
        "Foo.### PAGE 0003 ###Bar.",
        "Foo.\n\n### PAGE 0004 ###\nBar.",
    ]
    for raw in variants:
        result = normalize_narrative_v1(raw, corpus="")
        assert result["text"] == "Foo. Bar.", raw
        assert result["applied"]["page_markers_removed"] == 1
        assert "\n\n" not in result["text"]
        assert "### PAGE" not in result["text"]


def test_sidemarkoer_som_allerfoerste_indhold_i_span():
    raw = "### PAGE 0010 ###\n1. Sybille, f. 1800."
    result = normalize_narrative_v1(raw, corpus="")
    assert result["text"] == "Sybille, f. 1800."
    assert result["applied"]["page_markers_removed"] == 1
    assert result["applied"]["ordinal_stripped"] == 1
    assert "### PAGE" not in result["text"]
    assert result["flags"] == []


def test_sidemarkoer_som_sidste_indhold_i_span():
    raw = "Foo bar.\n\n### PAGE 0099 ###"
    result = normalize_narrative_v1(raw, corpus="")
    assert result["text"] == "Foo bar. "
    assert result["applied"]["page_markers_removed"] == 1
    assert result["applied"]["soft_breaks_joined"] == 1
    assert "### PAGE" not in result["text"]
    assert result["flags"] == []


def test_sidemarkoer_invariant_aldrig_i_output():
    # Explicit invariant check (also asserted as a hard fail-closed guard
    # inside normalize_narrative_v1 itself): the marker literal must never
    # survive into the normalized text, across every marker fixture above.
    fixtures = [
        "Dorothea g. o. 1560 m. hert.\n\n### PAGE 0019 ###\ngottorpsk Amtmand.",
        "Han var Med-\n\n### PAGE 0053 ###\nlem af Ordenen.",
        "### PAGE 0010 ###\n1. Sybille, f. 1800.",
        "Foo bar.\n\n### PAGE 0099 ###",
    ]
    for raw in fixtures:
        result = normalize_narrative_v1(raw, corpus="")
        assert "### PAGE" not in result["text"], raw


# ---------------------------------------------------------------------------
# Step 4: corpus regression against the real fase-A / task-25 artifacts.
# Skipped when the (gitignored) work/ artifacts are not present.
# ---------------------------------------------------------------------------


def _load_scope_texts(worktree: Path):
    writer_dir = worktree / "work/task25-1939-v50-production-writer"
    phase_a_path = writer_dir / "phase-a-anchor-manifest-v1.json"
    production_path = writer_dir / "production-write-manifest-v1.json"
    calamari_path = (
        Path("/Users/johanreventlow/TypeScript/danmarksadelsaarbog")
        / "work_1939_stamtavle/full_ocr_calamari_r6_clean.txt"
    )
    required = [phase_a_path, production_path, calamari_path]
    if not all(path.exists() for path in required):
        return None

    def sha(path: Path) -> str:
        return hashlib.sha256(path.read_bytes()).hexdigest()

    assert sha(phase_a_path) == PHASE_A_ANCHOR_MANIFEST_SHA256
    assert sha(production_path) == PRODUCTION_WRITE_MANIFEST_SHA256
    assert sha(calamari_path) == CALAMARI_SHA256

    phase_a = json.loads(phase_a_path.read_text(encoding="utf-8"))
    production = json.loads(production_path.read_text(encoding="utf-8"))
    corpus = calamari_path.read_text(encoding="utf-8")

    texts = [
        op["verbatim_text"]
        for op in phase_a["operations"]
        if op.get("canonical_target")
    ]
    texts += [pc["verbatim_text"] for pc in production["person_creates"]]
    return texts, corpus


def test_korpus_regression_551_spans():
    worktree = Path(__file__).resolve().parents[4]
    loaded = _load_scope_texts(worktree)
    if loaded is None:
        pytest.skip("realdata-artefakter (work/) findes ikke i denne checkout")
    texts, corpus = loaded

    assert len(texts) == 551

    def run_all():
        return [normalize_narrative_v1(t, corpus) for t in texts]

    results_a = run_all()
    results_b = run_all()
    assert results_a == results_b  # determinisme over to kørsler

    ordinal_stripped_sum = sum(r["applied"]["ordinal_stripped"] for r in results_a)
    assert ordinal_stripped_sum == 499

    ordinal_ambiguous_flags = [
        flag
        for result in results_a
        for flag in result["flags"]
        if flag["kind"] == "ordinal_ambiguous"
    ]
    assert len(ordinal_ambiguous_flags) == 2
    contexts = [flag["context"] for flag in ordinal_ambiguous_flags]
    assert any("Heinrich" in c for c in contexts)
    assert any("Conrad" in c for c in contexts)

    page_markers_removed_sum = sum(
        r["applied"]["page_markers_removed"] for r in results_a
    )
    assert page_markers_removed_sum == 73

    for raw, result in zip(texts, results_a):
        assert "### PAGE" not in result["text"], raw
        assert_diff_classes_allowed(raw, result["text"])
