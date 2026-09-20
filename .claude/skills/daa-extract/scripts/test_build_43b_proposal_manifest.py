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

from build_43b_proposal_manifest import persona_rolle, uden_modpart

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
