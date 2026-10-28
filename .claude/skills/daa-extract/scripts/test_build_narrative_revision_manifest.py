"""Syntetiske fixtures uden rigtige navne — revisionsmanifestets vagter (A6b)."""
import hashlib
import json

import pytest

import build_narrative_revision_manifest as builder
import segment

RAW = "\n".join([
    "### PAGE 1 ###",
    "I",
    "DEN TESTLIGE LINJE",
    "        1.       Anders Testesen, * 1801. Gift med Inger",
    "von Reventlow, der ejede Testgaard.",
    "                  Han døde 1860.",
    "        2.       Bodil Testesen, * 1803.",
    "### PAGE 2 ###",
    "von REVENTLOW",
    "                  Hun døde 1870.",
])


def build(**kw):
    args = {"raw_text": RAW, "fra": "2018-20", "til": "2018-20-v2", "source_id": 7}
    args.update(kw)
    return builder.build_revision_manifest(**args)


def test_kun_aendrede_poster_med_ren_indsaettelse():
    manifest = build()
    assert manifest["kind"] == "narrative_revision"
    assert [e["record_key"] for e in manifest["elements"]] == ["I-1"]
    element = manifest["elements"][0]
    assert element["inserted_tokens"] == 5
    assert "Testgaard" not in element["old_text"]
    assert "von Reventlow, der ejede Testgaard." in element["new_text"]
    assert element["old_sha256"] == hashlib.sha256(element["old_text"].encode("utf-8")).hexdigest()
    assert element["new_sha256"] == hashlib.sha256(element["new_text"].encode("utf-8")).hexdigest()


def _fake_profile(monkeypatch, name, change):
    def segmenter(lines, profile):
        posts = segment.UDGAVE_PROFILER["2018-20-v2"]["segmenter"](lines, profile)
        return change(posts)
    monkeypatch.setitem(segment.UDGAVE_PROFILER, name,
                        {**segment.UDGAVE_PROFILER["2018-20-v2"], "segmenter": segmenter})


def test_graenseaendring_afvises(monkeypatch):
    _fake_profile(monkeypatch, "fake", lambda posts: posts[:1])
    with pytest.raises(builder.ManifestError, match="NARRATIVE_REVISION_BOUNDARY_CHANGED"):
        build(til="fake")


def test_aendret_andet_felt_end_tekst_afvises(monkeypatch):
    def change(posts):
        posts[1]["nr_label"] = "2a"
        return posts
    _fake_profile(monkeypatch, "fake", change)
    with pytest.raises(builder.ManifestError, match="NARRATIVE_REVISION_BOUNDARY_CHANGED"):
        build(til="fake")


def test_andet_end_indsaettelse_afvises(monkeypatch):
    def change(posts):
        posts[0]["raw_text"] = posts[0]["raw_text"].replace("Han døde", "Han")
        return posts
    _fake_profile(monkeypatch, "fake", change)
    with pytest.raises(builder.ManifestError, match="NARRATIVE_REVISION_NOT_PURE_INSERTION"):
        build(til="fake")


def test_manifest_sha_er_deterministisk():
    first, second = build(), build()
    assert first == second
    body = {k: v for k, v in first.items() if k != "manifest_sha256"}
    canonical = json.dumps(body, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    assert first["manifest_sha256"] == hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def _main_paa(tmp_path, out):
    raw = tmp_path / "raw.txt"
    raw.write_text(RAW, encoding="utf-8")
    return builder.main(["--raw", str(raw), "--fra", "2018-20", "--til", "2018-20-v2",
                         "--source-id", "7", "--out", str(out)])


def test_eksisterende_fil_erstattes_med_ny_0600(tmp_path):
    out = tmp_path / "manifest.json"
    out.write_text("gammel", encoding="utf-8")
    out.chmod(0o644)
    gammel_inode = out.stat().st_ino
    assert _main_paa(tmp_path, out) == 0
    assert out.stat().st_mode & 0o777 == 0o600
    assert out.stat().st_ino != gammel_inode  # ny fil, aldrig skrevet ind i den gamle 0644-fil
    assert json.loads(out.read_text(encoding="utf-8"))["kind"] == "narrative_revision"


def test_symlink_som_out_afvises(tmp_path):
    maal = tmp_path / "andet.json"
    maal.write_text("", encoding="utf-8")
    out = tmp_path / "manifest.json"
    out.symlink_to(maal)
    with pytest.raises(builder.ManifestError, match="NARRATIVE_REVISION_OUT_SYMLINK"):
        _main_paa(tmp_path, out)
    assert maal.read_text(encoding="utf-8") == ""


def test_ingen_aendringer_giver_tomt_manifest():
    assert build(til="2018-20")["elements"] == []
