"""Statisk vagt: nye læsere af klausuler skal tage stilling til klausulsæt (omsegmentering).

En post kan have flere klausulsæt (spec 2026-09-27). Ordinalerne 1..n findes i hvert sæt,
så en læser, der ikke filtrerer på det aktuelle sæt, viser to sæt side om side — tavst.
Den eneste læsevej for »postens klausuler« er private.clause_observation_current.

Vagten afviser enhver sporet kodefil, der rører klausulernes kolonner, men ikke står på
listen nedenfor. En ny fil kommer på listen med en begrundelse, efter at den er gjort
sæt-bevidst (eller bevidst læser alle sæt).
"""
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
PATTERN = re.compile(r"observation_kind\s*=\s*'clause'|parent_observation_id|clause_ordinal")
EXTENSIONS = (".sql", ".psql", ".R", ".py", ".ts", ".tsx", ".js")

ALLOWED = {
    # Skema, migrationer og deploy-verifikation: definerer sættene, triggerne og viewet.
    "schema.sql", "db-migrations.sql", "db-verify.sql",
    # Læser det aktuelle sæt via clause_observation_current.
    ".claude/skills/daa-extract/scripts/export_43b_runner_input.R",
    ".claude/skills/daa-extract/scripts/export_clause_evidence_preview.R",
    ".claude/skills/daa-extract/scripts/interpretation_proposal_projection.sql",
    # Læser via fortolkningslinks, som kun kan pege på det aktuelle sæt (trigger).
    ".claude/skills/daa-extract/scripts/interpretation_control_rows.sql",
    # 5b's kontrolark: helposten (parent_observation_id IS NULL) for egen post; klausuler kun via fortolkningslinks.
    ".claude/skills/daa-extract/scripts/identity_control_rows.sql",
    # Overførslens fingeraftryk og digests (#147): læser kun klausuler via fortolkningslinks.
    ".claude/skills/daa-extract/scripts/interpretation_decision_fingerprint.sql",
    ".claude/skills/daa-extract/scripts/interpretation_transfer_digests.sql",
    # Overførslens baseline (#147): vælger pr. helpost max(clause_set_seq) som
    # clause_observation_current og hasher det sæt med private.clause_set_sha256.
    ".claude/skills/daa-extract/scripts/transfer_baseline.sql",
    # Klausul-evidensens projektion og komparator: projicerer alle sæt med clause_set_seq (Task 5).
    ".claude/skills/daa-extract/scripts/clause_evidence_projection.sql",
    ".claude/skills/daa-extract/scripts/compare_clause_evidence_projection.py",
    # Læser kun helposten (parent_observation_id IS NULL), ikke klausuler.
    ".claude/skills/daa-extract/scripts/export_clause_source_texts.R",
    ".claude/skills/daa-extract/scripts/export_model_eligibility.R",
    # 6d-1 placement-eksport: læser kun helposten (parent_observation_id IS NULL) som recordens primary-persona, ikke klausuler.
    ".claude/skills/daa-extract/scripts/placement_eksport.sql",
    # Kildetekst-revisionens afhængighedsfil (trin 6a): bestemmer det aktuelle sæt som writeren
    # (max clause_set_seq under helposten) og hasher det med private.clause_set_sha256; afhængighederne
    # læses gennem private.text_revision_dependents (clause_observation_current).
    ".claude/skills/daa-extract/scripts/source_text_revision_dependencies.sql",
    # Trin 6c-3's afstemning: de nye nøgler er dem, der citerer helpostens aktuelle sæt (clause_observation_current
    # under revisionsevent'ets parent_observation_id); de forældede læses gennem eventets superseded_keys.
    ".claude/skills/daa-extract/scripts/tekstrevision_afstemning.sql",
    # T/V-arkets HTML-kontekst: læser kun helposten (eventets parent_observation_id) og dens gældende tekst, ikke klausuler.
    ".claude/skills/daa-extract/scripts/tekstrevision_tilbagetraek_kontekst.sql",
    # #150 placement-ceremonien: helposten som persona-placementens grundlag og identitetstjekket.
    ".claude/skills/daa-extract/scripts/fix_150_placement.sql",
    # 6d-1 placement-ceremonien (kildeparametriseret efterfølger): kun helposten (parent_observation_id IS NULL) som
    # persona-placementens grundlag og identitetstjekket, ikke klausuler.
    ".claude/skills/daa-extract/scripts/placement_ceremoni.sql",
    # Trin 6a's ceremonimåling: tæller bevidst klausulrækker i ALLE sæt (ikke kun det aktuelle), fordi den skal
    # vise, at ceremonierne hverken tilføjer eller fjerner rækker for 2018-20, og at 1939 får præcis ét sæt.
    ".claude/skills/daa-extract/scripts/maal_trin6a.sql",
    # 6d-3's forælderark (rækkefil v2): klausulerne læses kun gennem fortolkningslinks (supporting), som kun kan pege på
    # det aktuelle sæt (trigger); parent_observation_id bruges kun til at finde helpostens gældende tekst.
    ".claude/skills/daa-extract/scripts/relation_parent_rows.sql",
    # Ingen databaselæsning: kontrakter, manifester og ark bygget af eksporterede data.
    ".claude/skills/daa-extract/scripts/build_43b_judgement_sheet.py",
    ".claude/skills/daa-extract/scripts/build_43b_proposal_manifest.py",
    ".claude/skills/daa-extract/scripts/compare_interpretation_proposal_projection.py",
    ".claude/skills/daa-extract/scripts/evidence_contract.py",
    ".claude/skills/daa-extract/scripts/evidence_runner.py",
}


def _is_test(path: str) -> bool:
    name = Path(path).name
    return path.startswith("tests/") or name.startswith("test_") or name.startswith("test-")


def _tracked_code_files() -> list[str]:
    out = subprocess.run(["git", "ls-files"], cwd=ROOT, capture_output=True, text=True, check=True).stdout
    return [p for p in out.splitlines() if p.endswith(EXTENSIONS) and not p.startswith("docs/")]


def test_every_clause_reader_is_on_the_allowlist():
    offenders = []
    for path in _tracked_code_files():
        if path in ALLOWED or _is_test(path):
            continue
        text = (ROOT / path).read_text(encoding="utf-8", errors="replace")
        if PATTERN.search(text):
            offenders.append(path)
    assert offenders == [], f"nye klausul-læsere uden sæt-afklaring: {offenders}"


def test_allowlist_has_no_stale_entries():
    tracked = set(_tracked_code_files())
    missing = sorted(p for p in ALLOWED if p not in tracked)
    assert missing == [], f"tilladelseslisten peger på filer, der ikke findes: {missing}"


def test_set_aware_readers_actually_use_the_current_view():
    for path in (".claude/skills/daa-extract/scripts/export_43b_runner_input.R",
                 ".claude/skills/daa-extract/scripts/export_clause_evidence_preview.R",
                 ".claude/skills/daa-extract/scripts/interpretation_proposal_projection.sql"):
        assert "clause_observation_current" in (ROOT / path).read_text(encoding="utf-8"), path


def test_pattern_catches_the_spaced_form():
    assert PATTERN.search("WHERE o.observation_kind = 'clause'")
    assert PATTERN.search("WHERE observation_kind='clause'")
