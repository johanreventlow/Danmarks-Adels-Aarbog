"""Klassifikationsreglerne i 4.4's manifest-builder.

Her — ikke i writeren — afgøres om et claim kommer med. Writeren ser én record
ad gangen, så en exception der ruller hele recorden tilbage; det var den fejl,
projektejeren afgjorde imod efter 4.3b's bundt 1. Derfor skal reglerne have
deres egen dækning.
"""
from __future__ import annotations

import json
from pathlib import Path

import pytest

from build_43b_proposal_manifest import parse_cached_raw_claims, persona_rolle, uden_modpart
from evidence_runner import partition_record_claims, sha256_text

PROFIL = (Path(__file__).resolve().parents[1]
          / "references/reimport-profiles/daa-2018-20-interpretation-proposal-v1.json")


@pytest.fixture(scope="module")
def profil() -> dict:
    return json.loads(PROFIL.read_text(encoding="utf-8"))


# --- persona_role -------------------------------------------------------------

@pytest.mark.parametrize("predicate,forventet", [
    ("person.death", "principal"),
    # Spec §7.2's hul: event.* handler om hovedpersonen uden person.-præfiks.
    ("event.appointment", "principal"),
    ("event.dismissal", "principal"),
    ("event.acquisition", "principal"),
    ("heraldry.blazon", "principal"),
    ("lineage.introduction", "principal"),
    ("mention.person", "other"),
    ("relation.marriage", "other"),
])
def test_rollen_kommer_fra_profilens_kort(profil, predicate, forventet):
    assert persona_rolle(predicate, profil["persona_role_map"]) == forventet


def test_ukendt_praedikat_giver_ingen_rolle(profil):
    """Fail-closed: kalderen afviser claimet frem for at gætte en rolle."""
    assert persona_rolle("ukendt.ting", profil["persona_role_map"]) is None


def test_laengste_praefiks_vinder():
    """Ellers ville listernes rækkefølge afgøre det stiltiende."""
    kort = {"principal": ["event."], "other": ["event.marriage"]}
    assert persona_rolle("event.marriage", kort) == "other"
    assert persona_rolle("event.travel", kort) == "principal"


def test_selvmodsigende_kort_rejser():
    kort = {"principal": ["event."], "other": ["event."]}
    with pytest.raises(ValueError, match="selvmodsigende"):
        persona_rolle("event.x", kort)


# --- H1: relation uden modpart ------------------------------------------------

@pytest.mark.parametrize("raw", ["NN.", "N. N.", "ukendt", "4 sønner", "fire døtre",
                                 "tvillinger", "børn", "  "])
def test_h1_fanger_vaerdier_uden_modpart(profil, raw):
    assert uden_modpart(raw, profil["no_counterpart_denylist"]) is True


@pytest.mark.parametrize("raw", ["Anne Sophie Reventlow", "4 sønner, som døde små",
                                 "Christian Ditlev"])
def test_h1_er_anchored_paa_hele_strengen(profil, raw):
    """Med vilje: H1 er en tidsbesparelse, ikke en korrekthedsgate. 4.5 er gaten."""
    assert uden_modpart(raw, profil["no_counterpart_denylist"]) is False


def test_h1_laeser_baade_streng_og_objektvaerdi(profil):
    deny = profil["no_counterpart_denylist"]
    assert uden_modpart({"raw": "NN."}, deny) is True
    assert uden_modpart({"raw": "Anne"}, deny) is False
    assert uden_modpart({"ingen_raw": "NN."}, deny) is False


def test_numeric_claim_values_are_rejected_before_builder_key_derivation():
    """Mutation caught: accepting a numeric value would let it reach key material."""
    text = "Født 1. jan. 1800 i Fiktivby."
    record = {
        "record_key": "I-42", "persona_id": "persona-1", "clauses": [
            {"ordinal": 1, "verbatim_text": text, "verbatim_sha256": sha256_text(text)},
        ],
    }
    legal = {"clause_ordinals": [1], "predicate": "person.birth", "value": "1. jan. 1800",
             "confidence": 0.9, "source_persona_id": "persona-1"}
    numeric = dict(legal, value={"raw": "1800", "normalized": 1800})
    accepted, rejected = partition_record_claims([legal, numeric], record)
    assert accepted == [legal]
    assert rejected == [{"claim": numeric, "fejl": "RUNNER_CLAIM_VALUE_INVALID"}]


def test_cached_raw_claims_reject_duplicate_json_keys_before_partitioning():
    """Mutation caught: an ordinary json decoder silently retains the last key."""
    with pytest.raises(ValueError, match="CACHE_RAW_JSON_INVALID"):
        parse_cached_raw_claims('{"claims":[],"claims":[]}')


def test_cached_raw_claims_returns_only_a_json_claim_list():
    assert parse_cached_raw_claims('{"claims":[]}') == []


def test_cached_raw_fractional_confidence_survives_the_claim_boundary():
    """Review C1: strict decoding must not turn a legal 0.9 confidence into a Decimal
    that the runner's float check then rejects."""
    text = "Født 1. jan. 1800 i Fiktivby."
    record = {
        "record_key": "I-42", "persona_id": "persona-1", "clauses": [
            {"ordinal": 1, "verbatim_text": text, "verbatim_sha256": sha256_text(text)},
        ],
    }
    raw = ('{"claims":[{"clause_ordinals":[1],"predicate":"person.birth",'
           '"value":"1. jan. 1800","confidence":0.9,"source_persona_id":"persona-1"}]}')
    accepted, rejected = partition_record_claims(parse_cached_raw_claims(raw), record)
    assert rejected == []
    assert len(accepted) == 1 and accepted[0]["confidence"] == 0.9


def test_current_cache_key_finder_filen_med_record_key(tmp_path):
    import build_43b_proposal_manifest as b
    import evidence_runner
    rec = {"record_key": "R-1", "persona_id": "p", "post_verbatim_text": "t",
           "clauses": [{"ordinal": 1, "verbatim_text": "t",
                        "verbatim_sha256": evidence_runner.sha256_text("t")}]}
    ident = {"profile_id": "daa-2018-20-v1", "profile_version": "1.3.0", "model": "m",
             "prompt_sha256": "p", "record_key": "R-1",
             "record_input_sha256": evidence_runner.canonical_record_input(rec),
             "clause_set_sha256": evidence_runner.canonical_clause_set(rec),
             "claims_schema_sha256": "s",
             "runner_contract_version": evidence_runner.RUNNER_CONTRACT_VERSION}
    assert b.cache_path(tmp_path, ident, mode="current").name == \
        f"{evidence_runner.ResponseCache.key(ident)}.json"
    # 4.5's runner-manifest bærer kontrakt 1.0: dens cachefiler blev skrevet uden
    # klausulsæt og skal findes under samme navn som ved kørslen.
    v10 = dict(ident, runner_contract_version="evidence-runner-1.0")
    felter = ("profile_id", "profile_version", "model", "prompt_sha256", "record_key",
              "record_input_sha256", "claims_schema_sha256", "runner_contract_version")
    import hashlib
    ved_koerslen = hashlib.sha256("\x1f".join(str(v10[f]) for f in felter).encode()).hexdigest()
    assert b.cache_path(tmp_path, v10, mode="current").name == f"{ved_koerslen}.json"
    legacy = {k: v for k, v in ident.items() if k != "record_key"}
    assert b.cache_path(tmp_path, legacy, mode="legacy").name == \
        f"{b.legacy_cache_key(legacy)}.json"


def test_records_to_ingest_tager_kun_navngivne_bundter():
    import pytest
    import build_43b_proposal_manifest as b
    m = {"records": ["A", "B", "C"], "bundter": {"bundt_1": ["A", "B"], "reserve": ["C"]}}
    assert b.records_to_ingest(m, None) == ["A", "B", "C"]
    assert b.records_to_ingest(m, ["bundt_1"]) == ["A", "B"]
    with pytest.raises(ValueError, match="BUNDLE_UNKNOWN"):
        b.records_to_ingest(m, ["bundt_9"])


def _runner_manifest(**aendr):
    from build_43b_manifest import manifest_sha256
    m = {"records": ["A", "B", "C"], "bundter": {"bundt_1": ["A", "B"], "reserve": ["C"]}}
    m.update(aendr)
    m["manifest_sha256"] = manifest_sha256(m)
    return m


def test_runner_manifestet_genberegnes_og_bundterne_valideres():
    """4.5-kodereview, fund 5: feltet alene beviser intet; hashen genberegnes, og
    bundterne skal være en disjunkt opdeling af records."""
    import build_43b_proposal_manifest as b
    m = _runner_manifest()
    b.verify_runner_manifest(m, m["manifest_sha256"])
    with pytest.raises(ValueError, match="RUNNER_MANIFEST_DRIFT"):
        b.verify_runner_manifest(m, "0" * 64)
    manipuleret = dict(m, bundter={"bundt_1": ["A", "B", "C"], "reserve": ["C"]})
    with pytest.raises(ValueError, match="RUNNER_MANIFEST_TAMPERED"):
        b.verify_runner_manifest(manipuleret, m["manifest_sha256"])
    for bundter in ({"bundt_1": ["A", "B"], "reserve": ["B", "C"]},    # dublet
                    {"bundt_1": ["A", "B"]},                           # C mangler
                    {"bundt_1": ["A", "B", "C", "D"]}):                 # D uden for records
        m2 = _runner_manifest(bundter=bundter)
        with pytest.raises(ValueError, match="RUNNER_BUNDLES_INVALID"):
            b.verify_runner_manifest(m2, m2["manifest_sha256"])


def test_cli_stopper_paa_manipuleret_bundt_uden_output(tmp_path, monkeypatch, capsys):
    import build_43b_proposal_manifest as b
    m = _runner_manifest()
    m["bundter"]["bundt_1"].append("C")          # efter hashen
    (tmp_path / "m.json").write_text(json.dumps(m), encoding="utf-8")
    monkeypatch.setattr("sys.argv", ["b", "--runner-manifest", str(tmp_path / "m.json"),
                                     "--runner-input", str(tmp_path / "findes-ikke.json"),
                                     "--cache-dir", str(tmp_path), "--profile", str(PROFIL),
                                     "--out", str(tmp_path / "out.json"),
                                     "--expect-runner-manifest-sha256", m["manifest_sha256"]])
    assert b.main() == 1
    assert "RUNNER_MANIFEST_TAMPERED" in capsys.readouterr().out
    assert not (tmp_path / "out.json").exists()


def test_cli_afviser_svar_fra_foer_p1_uden_flag(tmp_path, monkeypatch, capsys):
    """Review 35, P1: et 1.0-1.2-svar kan stamme fra et kald, der kørte en kommando.
    Builderen må kun læse dem, når nogen udtrykkeligt genbygger et historisk manifest."""
    import build_43b_proposal_manifest as b
    m = _runner_manifest()
    (tmp_path / "m.json").write_text(json.dumps(m), encoding="utf-8")
    monkeypatch.setattr("sys.argv", ["b", "--runner-manifest", str(tmp_path / "m.json"),
                                     "--runner-input", str(tmp_path / "findes-ikke.json"),
                                     "--cache-dir", str(tmp_path), "--profile", str(PROFIL),
                                     "--out", str(tmp_path / "out.json"),
                                     "--expect-runner-manifest-sha256", m["manifest_sha256"]])
    assert b.main() == 1
    assert "PRE_P1_CACHE_REFUSED" in capsys.readouterr().out
    assert not (tmp_path / "out.json").exists()


# --- hele bygningen ----------------------------------------------------------

def _rec(key, persona, tekst):
    return {"record_key": key, "persona_id": persona, "post_verbatim_text": tekst,
            "clauses": [{"ordinal": 1, "verbatim_text": tekst, "verbatim_sha256": sha256_text(tekst)}]}


def _byg(tmp_path, monkeypatch, records, svar, mode="current"):
    """Kører CLI'en over et komplet, syntetisk runner-manifest og en cache i den givne tilstand."""
    import build_43b_proposal_manifest as b
    from build_43b_manifest import manifest_sha256
    from evidence_runner import canonical_clause_set, canonical_record_input
    m = {"records": list(records), "bundter": {"bundt_01": list(records)},
         "profile_id": "p", "profile_version": "1", "model": "m", "prompt_sha256": "a" * 64,
         "claims_schema_sha256": "b" * 64, "runner_contract_version": "evidence-runner-1.3",
         "eligibility_ledger_sha256": "c" * 64}
    m["manifest_sha256"] = manifest_sha256(m)
    cache = tmp_path / "cache"
    cache.mkdir()
    for key, rec in records.items():
        ident = {"profile_id": "p", "profile_version": "1", "model": "m", "prompt_sha256": "a" * 64,
                 "record_input_sha256": canonical_record_input(rec),
                 "clause_set_sha256": canonical_clause_set(rec), "claims_schema_sha256": "b" * 64,
                 "runner_contract_version": (b.LEGACY_RUNNER_CONTRACT_VERSION if mode == "legacy"
                                             else "evidence-runner-1.3")}
        if mode == "current":
            ident["record_key"] = key
        b.cache_path(cache, ident, mode=mode).write_text(json.dumps(
            {"raw": json.dumps({"claims": svar[key]}), "usage": {"input_tokens": 1}}), encoding="utf-8")
    (tmp_path / "m.json").write_text(json.dumps(m), encoding="utf-8")
    (tmp_path / "ri.json").write_text(json.dumps({"records": records}), encoding="utf-8")
    monkeypatch.setattr("sys.argv", ["b", "--runner-manifest", str(tmp_path / "m.json"),
                                     "--runner-input", str(tmp_path / "ri.json"),
                                     "--cache-dir", str(cache), "--profile", str(PROFIL),
                                     "--out", str(tmp_path / "out.json"), "--cache-key", mode,
                                     "--expect-runner-manifest-sha256", m["manifest_sha256"]]
                        + (["--historisk-foer-p1"] if mode == "legacy" else []))
    return b.main()


def _claim(predicate, value, persona):
    return {"clause_ordinals": [1], "predicate": predicate, "value": {"raw": value}, "confidence": 0.9,
            "source_persona_id": persona}


def test_principal_claim_paa_post_uden_persona_sorteres_fra_og_taelles(tmp_path, monkeypatch, capsys):
    """2026-10-02, II-35: writeren afviser et principal-forslag på en post uden persona
    (REIMPORT_WRITER_PRINCIPAL_WITHOUT_PERSONA) og ruller hele posten tilbage. Byggeren
    skal afgøre det først — og kun fælde det ene claim."""
    tekst = "Gift i Odense med Anna."
    records = {"A": _rec("A", "p-A", tekst), "B": _rec("B", "", tekst)}
    svar = {"A": [_claim("event.marriage", "Gift i Odense", None),
                  _claim("mention.place", "Odense", None)],
            "B": [_claim("event.marriage", "Gift i Odense", None),
                  _claim("mention.place", "Odense", None)]}
    assert _byg(tmp_path, monkeypatch, records, svar) == 0
    assert "principal uden persona 1" in capsys.readouterr().out
    out = json.loads((tmp_path / "out.json").read_text(encoding="utf-8"))
    ops = {o["source_record_key"]: o for o in out["operations"]}
    assert [c["predicate"] for c in ops["A"]["claims"]] == ["event.marriage", "mention.place"]
    assert [(c["predicate"], c["persona_role"]) for c in ops["B"]["claims"]] == [("mention.place", "other")]
    r = out["provenance"]["regnskab"]
    assert r["principal_uden_persona"] == 1 and r["ingestible"] == 3 and r["raa_claims"] == 4
    assert out["provenance"]["principal_uden_persona_claims"] == [
        {"record_key": "B", "predicate": "event.marriage"}]


def test_post_uden_persona_kun_med_principal_claims_giver_intet_element(tmp_path, monkeypatch, capsys):
    tekst = "Gift i Odense med Anna."
    records = {"B": _rec("B", "", tekst)}
    svar = {"B": [_claim("event.marriage", "Gift i Odense", None)]}
    assert _byg(tmp_path, monkeypatch, records, svar) == 0
    out = json.loads((tmp_path / "out.json").read_text(encoding="utf-8"))
    assert out["operations"] == [] and out["expected_counts"]["interpretation_proposals"] == 0
    assert out["provenance"]["regnskab"]["principal_uden_persona"] == 1


@pytest.mark.parametrize("persona", [None, "", "MANGLER"])
def test_alle_former_for_manglende_persona_fanges(tmp_path, monkeypatch, persona):
    tekst = "Gift i Odense med Anna."
    rec = _rec("B", persona, tekst)
    if persona == "MANGLER":
        del rec["persona_id"]
    svar = {"B": [_claim("event.marriage", "Gift i Odense", None)]}
    assert _byg(tmp_path, monkeypatch, {"B": rec}, svar) == 0
    out = json.loads((tmp_path / "out.json").read_text(encoding="utf-8"))
    assert out["provenance"]["regnskab"]["principal_uden_persona"] == 1


def test_legacy_uden_frasortering_faar_ingen_ny_konto(tmp_path, monkeypatch):
    """Byte-identiteten for 4.3b/4.5: kontoen findes kun i current-tilstand."""
    tekst = "Gift i Odense med Anna."
    svar = {"A": [_claim("event.marriage", "Gift i Odense", None)]}
    assert _byg(tmp_path, monkeypatch, {"A": _rec("A", "p-A", tekst)}, svar, mode="legacy") == 0
    prov = json.loads((tmp_path / "out.json").read_text(encoding="utf-8"))["provenance"]
    assert "principal_uden_persona" not in prov["regnskab"]
    assert "principal_uden_persona_claims" not in prov


def test_legacy_med_frasortering_fejler_lukket(tmp_path, monkeypatch, capsys):
    """Legacy-manifestet har ingen konto til frasorterede claims; regnskabet ville ikke gå op."""
    tekst = "Gift i Odense med Anna."
    svar = {"B": [_claim("event.marriage", "Gift i Odense", None)]}
    assert _byg(tmp_path, monkeypatch, {"B": _rec("B", "", tekst)}, svar, mode="legacy") == 1
    assert "PRINCIPAL_UDEN_PERSONA_I_LEGACY 1" in capsys.readouterr().out
    assert not (tmp_path / "out.json").exists()


# --- 1939-profilen (trin 6c-1) -------------------------------------------------

PROFIL_1939 = PROFIL.with_name("daa-1939-interpretation-proposal-v1.json")


@pytest.fixture(scope="module")
def profil_1939() -> dict:
    return json.loads(PROFIL_1939.read_text(encoding="utf-8"))


def test_1939_profilen_er_2018_20s_med_egne_versioner_og_helpost(profil, profil_1939):
    assert profil_1939["source_id"] == 3 and profil_1939["edition"] == "1939"
    assert profil_1939["writer_config"]["helpost_observation_kind"] == "person"
    assert profil_1939["no_counterpart_denylist"]["version"] == "nn-denylist-1939-v1"
    assert profil_1939["persona_role_map"]["version"] == "persona-role-1939-v1"
    for nøgle in ("unknown_person", "quantity_only"):
        assert profil_1939["no_counterpart_denylist"][nøgle] == profil["no_counterpart_denylist"][nøgle]
    for nøgle in ("principal", "other"):
        assert profil_1939["persona_role_map"][nøgle] == profil["persona_role_map"][nøgle]
    assert profil_1939["operation_settings"] == profil["operation_settings"]


@pytest.mark.parametrize("raw", ["4 Sønner", "N. N.", "To Døtre", "Børn", "Ukendt"])
def test_1939_h1_fanger_store_forbogstaver(profil_1939, raw):
    assert uden_modpart(raw, profil_1939["no_counterpart_denylist"]) is True
