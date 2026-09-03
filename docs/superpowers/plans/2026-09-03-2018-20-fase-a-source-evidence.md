# 149a — kilderegnskab for DAA 2018-20 gennem den generelle genimport-writer

> **Til agent-arbejdere:** PÅKRÆVET UNDER-SKILL: brug
> `superpowers:subagent-driven-development` eller `superpowers:executing-plans`
> task for task. Brug `superpowers:test-driven-development` i hver kodetask,
> `superpowers:systematic-debugging` ved hver fejlende verifikation og
> `superpowers:verification-before-completion` før enhver færdigmelding.

**Goal:** Bygge ét hash-låst manifest med 591 `source_evidence`-elementer (én
rendition, 591 source records, 591 forekomster, 591 accepterede ankre) for
`source_id = 1`, køre det gennem #153's generelle writer via R-gatewayen mod en
engangs-restore, og bevise nul kanonisk delta. Ingen bindinger, ingen
personoprettelse, intet modelkald, ingen prod-apply.

**Architecture:** Udgaven bor i ÉN profil-JSON. Alle scripts er
profil-parametriserede og editionsneutrale i navnet. Kæden er:
profil → pdftotext-rendition (SHA-låst) → `segment.py` (paritetslåst) →
`build_source_evidence_manifest.py` (deterministisk, fail-closed) →
`export_reimport_preview.R` (læse-kun før-billede) → `red_authorize_reimport`
(service-rolle) → `apply_reimport.R --dry-run|--apply` → rehearsal-rapport.
Writeren selv er uændret; 149a leverer kun input og bevis.

**Tech Stack:** Python 3.11 + pytest, R + testthat + DBI/RPostgres/jsonlite/digest,
PostgreSQL 17 (Supabase-skema, `SECURITY DEFINER` RPC'er), GitHub Actions,
`pdftotext` (poppler).

**Spec:** `docs/superpowers/specs/2026-09-03-2018-20-fase-a-provenance-design.md`
(kun §2, §3, §4, §6, §7, §9). Styringsgrundlag: `docs/evidensbaseret-genimport/`
`vision.md`, `roadmap.md`, `teknisk-maalarkitektur.md`, `status.md`.

## Global Constraints

Ordret fra spec'en, ikke til forhandling:

- **§7, modelkald:** »Fase A kalder ingen model. Tekst om levende personer
  forlader ikke maskinen.«
- **§7, persondata:** »Rapporter og fixtures indeholder kun `record_key`, tal og
  hashes, aldrig navne eller narrativtekst.«
- **§1 række 3, editionsnavne-gate:** »Ingen nye DB-objekter, scripts eller
  tabeller med `2018` i navnet; nye scripts parametriseres på profil.« Den ene
  tilladte undtagelse er profil-JSON'ens filnavn under
  `references/reimport-profiles/`.
- **§1 række 5, nul kanonisk delta:** »aggregat-hash af `person`, `fact`,
  `family_member`, `narrative` og `narrative_record_publication` uændret;
  replay giver `already_applied`.«
- **§2, afgrænsning:** ingen narrativ-bindinger, ingen identitet, ingen
  tekstændringer, ingen strukturelle records, ingen klausul-observationer,
  ingen fortolkning, ingen placement/membership, ingen personoprettelse.
- **§6, kontrakt:** writeren kræver `public.narrative_record_contract_version() = 2`;
  rehearsal-basen migreres til v2 efter `docs/runbooks/narrative-record-key-cutover.md`.
- **§1 række 5 + §6, prod:** »Prod-apply er en separat gate.« Denne plan
  indeholder **intet** prod-trin, ingen prod-forbindelse, intet push og ingen merge.

Hertil disse arbejdsregler:

- Arbejd kun i `feat/149-2018-20-fase-a` under
  `.claude/worktrees/149-2018-20-fase-a`. Ren worktree før og efter hver task.
- Læs, print, opret eller ændr aldrig `work/`, `work_1939_stamtavle/` eller
  `work_presens/`. `data/extracted-2026-06-18/*.json` må kun læses på felterne
  `linje` og `nr_label` — filerne indeholder navne.
- Alle databasekald går mod en lokal, disponerbar PostgreSQL 17. Sæt altid alle
  fem `PGHOST/PGPORT/PGDATABASE/PGUSER/PGPASSWORD` sammen.
  Rehearsal-basenavne følger `daa149a_<formål>_<dato>`.
- Ændr ikke `schema.sql`'s writer-familie, `db-migrations.sql`, `load_daa.R`,
  #152's runbook eller klientkode. 149a er en forbruger af #153's kontrakt.

## Målte kontraktfakta (verificér selv før du koder)

| Fakta | Kilde |
| --- | --- |
| `public.red_authorize_reimport(p_manifest_sha256 text,p_preview_sha256 text,p_database_identity text,p_source_id bigint,p_profile_id text,p_profile_sha256 text,p_expected_counts jsonb,p_authorized_elements jsonb,p_nonce uuid,p_expires_at timestamptz) RETURNS uuid` | `schema.sql:2646` |
| `p_database_identity` skal være `jsonb_build_object('database_name',current_database(),'system_identifier',(pg_control_system()).system_identifier::text)::text` | `schema.sql:2657` |
| `expected_counts` har PRÆCIS nøglerne `person_creates` og `source_evidence`, begge heltal | `schema.sql:2583-2593` (`private.validate_reimport_authorization_payload`) |
| `authorized_elements`-nøgler skal matche `^person-create:.+$` eller `^source-evidence:.+$`, og antallet pr. klasse skal svare til `expected_counts` | `schema.sql:2599-2603` |
| `red_apply_reimport_source_evidence(uuid,text,jsonb)` kræver `p_payload->>'disposition' = 'retain_source_only'` | `schema.sql:2727` |
| Payload skal have `source_record_key`, `source_span{char_from,char_to}`, `page_evidence{page_from,page_to}`, `verbatim_text`, `rendition_content_sha256 ~ '^[0-9a-f]{64}$'`; `char_from>=0`, `char_to>char_from`, `page_from>=1`, `page_to>=page_from` | `schema.sql:2624-2628` |
| `authorized_elements->element_id` skal være jsonb-identisk med payload (eller payload uden `category`) | `schema.sql:2622-2623` |
| `category` bliver **samtidig** `source_record.record_kind`, `source_observation.observation_kind` og `source_mention.mention_kind`; default `'person'` | `schema.sql:2635`, `:2641`, `:2642` |
| `element_id` bliver `source_record_occurrence.occurrence_key` | `schema.sql:2639` |
| Rendition afledes af profilen: `rendition_key`, `rendition_kind`, `metadata` fra `writer_config`; kun `content_sha256` kommer fra payload. Drift → `REIMPORT_WRITER_RENDITION_DRIFT` | `schema.sql:2633-2634` |
| Anker skrives altid som `decision_status='accepted'` med `evidence = {batch_id, element_id}` og `decided_by_name` fra `public.profiles` | `schema.sql:2640` |
| `private.validate_reimport_writer_config` kræver præcis feltmængden `citation_label_template, extractor_version, observation_extraction_method, rendition_key, rendition_kind, rendition_metadata, run_key_prefix, schema_version`, og `citation_label_template` skal indeholde `{page_from}` præcis én gang og ingen andre `{...}` | `schema.sql:2366-2378` |
| `profile_sha256 = private.reimport_canonical_json_sha256(writer_config)` er en CHECK-constraint | `schema.sql:2389` |
| Kanonisk JSON-regel: objekt → `{` + `"key":value` sorteret `ORDER BY 1`, komma-separeret, ingen mellemrum; array → elementorden bevaret; skalar → `jsonb::text` | `schema.sql:2480-2489` |
| `red_authorize_reimport` er REVOKED fra `authenticated` og GRANTED kun til `service_role`; `red_preflight_reimport_authorization`, `red_begin_reimport`, `red_apply_reimport_source_evidence`, `red_finalize_reimport`, `red_reimport_batch_result` er GRANTED til `authenticated` | `schema.sql:3178-3180` |
| Alle writer-kald kræver `private.require_reimport_writer_editor()`: `auth.uid()` ikke NULL og `public.current_rolle() = 'redaktion'` | `schema.sql:2544-2549` |
| Manifestets form for gatewayen er **lukket**: præcis `manifest_content_sha256`, `source{id,profile_id,profile_sha256}`, `expected_counts{source_evidence,person_creates,canonical_delta}`, `operations[]` med `element_id` + `dependency_class` | `apply_reimport_helpers.R`, `validate_reimport_manifest` |
| `execute_reimport(manifest, preview_sha256, mode, gateway, authorization)` udleder payload = operation minus `element_id` og `dependency_class` | `apply_reimport_helpers.R`, `reimport_authorized_payloads` |
| CLI: `apply_reimport.R --manifest --manifest-sha256 --preview-sha256 (--dry-run \| --apply --authorization)`; `--manifest-sha256` tjekkes mod manifestfilens BYTES | `apply_reimport.R` |
| `record_key` for 2018-20 er `paste0(linje, "-", nr_label)` (bindestreg) | `.claude/skills/daa-extract/scripts/load_helpers.R:153` |
| `lokal_id` er `f"{linje}.{nr_label}"` (punktum) | `.claude/skills/daa-extract/scripts/segment.py:146` |
| `raw_text = norm(' '.join(lines))` med `norm(s) = re.sub(r'\s+',' ',s).strip()`; PAGE-, blanke og NOISE-linjer indgår aldrig | `segment.py:147`, `:118`, `:225-227` |

## Dokumenterede afvigelser fra spec-teksten

Disse fire er målt i koden og skal stå i rehearsal-rapporten (Task 6).

1. **»Eksakt delstreng« (spec §4).** `raw_text` er whitespace-normaliseret
   (`segment.py:147`) og kan aldrig være en litteral delstreng af
   `pdftotext -layout`-outputtet. 149a implementerer eksakt delstrengssøgning i
   en **normaliseret projektion** af renditionen med offset-kort tilbage til
   den rå tekst. Ingen fuzzy-match, ingen tolerance. Invarianten
   `project(rendition[char_from:char_to]) == raw_text` verificeres pr. post og
   fail-closer med `SOURCE_EVIDENCE_SPAN_ROUNDTRIP_MISMATCH`.
2. **Anker-evidens (spec §4).** Writeren hardcoder
   `evidence = {batch_id, element_id}` (`schema.sql:2640`). Spec'ens
   `{method, segment_version, rendition_content_sha256, raw_text_sha256}` kan
   ikke produceres uden at ændre #153. 149a bærer i stedet `anchor_method`,
   `segment_version` og `verbatim_sha256` som payload-nøgler; de lander
   uforanderligt i `private.reimport_event.payload` og i occurrencens
   `structural_fingerprint`. Spec'ens `raw_text_sha256` pr. post er
   `verbatim_sha256` (= occurrencens `physical_fingerprint`); på
   rendition-niveau er den `rendition_content_sha256`.
3. **Paritetsgrundlag (spec §4).** `data/extracted-2026-06-18/*.json` har
   nøglerne `linje, nr, nr_label, navn, tilnavn, facts, godser, embeder,
   aegteskaber, boern, begivenheder, usikker, koen` — hverken `raw_text` eller
   `sider`. Paritet er derfor **mængden af `lokal_id`** (591, verificeret) plus
   antal. Pr.-post-`raw_text`-hash bindes i stedet internt mellem Task 2's
   `segment-digest.json` og Task 3's `verbatim_sha256`.
4. **Reversal (spec §1 række 5).** `public.red_reverse_reimport` kræver
   `b.status = 'activated'` og præcis ét afsluttet `name_completion`-barnebatch
   (`schema.sql:3102-3106`). En ren `source_evidence`-batch kan derfor hverken
   aktiveres eller reverseres, og der findes ingen sletningsvej for
   `source_record`/`source_record_occurrence`/`source_record_anchor_event`.
   149a beviser i stedet (a) at der intet er at reversere kanonisk (identisk
   aggregat-hash), (b) at `red_reverse_reimport` fail-closer med
   `REIMPORT_WRITER_REVERSAL_INVALID`, og (c) at hele evidenslaget gendannes af
   en øvet restore fra 0600-backuppen. Afvigelsen kræver en post i
   `docs/decisions.md` efter spec §10 og projektejerens kvittering.

## File Structure

| Fil | Ansvar |
| --- | --- |
| `.claude/skills/daa-extract/references/reimport-profiles/daa-2018-20-source-evidence-v1.json` | Hele udgavespecifikationen: source, profil, `writer_config`, målte hashes, segmentversion, forventede tal, pdftotext-argumenter. |
| `.claude/skills/daa-extract/scripts/reimport_profile.py` | Profilindlæser, feltvalidering, kanonisk JSON-SHA identisk med `private.reimport_canonical_json_sha256`. |
| `.claude/skills/daa-extract/scripts/test_reimport_profile.py` | pytest for indlæser og kanonisk hash (kendt vektor fra PostgreSQL 17). |
| `.claude/skills/daa-extract/scripts/build_source_evidence_rendition.py` | Reproducér rendition efter profilen, verificér PDF-/tekst-SHA, kør `segment.py`, verificér paritet, skriv `segment-digest.json`. |
| `.claude/skills/daa-extract/scripts/test_build_source_evidence_rendition.py` | pytest for SHA-gate, paritetsgate og digest. |
| `.claude/skills/daa-extract/scripts/build_source_evidence_manifest.py` | Deterministisk manifest-bygger: projektion, eksakt delstreng, sideafledning, elementorden, `manifest_content_sha256`. |
| `.claude/skills/daa-extract/scripts/test_build_source_evidence_manifest.py` | pytest for span, sider, dubletter, determinisme og persondata-fravær. |
| `.claude/skills/daa-extract/scripts/export_reimport_preview.R` | Læse-kun CLI for før-billede og autorisationsanmodning. |
| `.claude/skills/daa-extract/scripts/export_reimport_preview_helpers.R` | Rene, injicerbare valideringer og preview-opbygning. |
| `tests/testthat/test-export-reimport-preview.R` | testthat-kontrakt for preview-helpers. |
| `tests/integration/test-reimport-source-evidence.R` | Syntetisk DBI-integration: dry-run, apply, tal, aggregat-hash, anon, replay, reversal-afvisning. |
| `docs/runbooks/source-evidence-reimport-rehearsal.md` | Manuel rehearsal mod engangs-restore af prod-dump; dump-sti er CLI-parameter. |
| `docs/evidensbaseret-genimport/source-evidence-149a-rehearsal.md` | Rehearsal-rapport med tal og hashes. |
| `docs/evidensbaseret-genimport/source-evidence-149a-phase-package-contribution.md` | Bidrag/receipt til fase-pakke-gaten (#156). |
| `db-verify.sql` | Udvid `private.assert_reimport_edition_catalog()` med en tom `_2018`-allowlist. |
| `tests/sql/test-reimport-edition-catalog.sql` | Negativ case for `_2018`-drift. |
| `.github/workflows/ci.yml` | pytest-trin for de tre nye moduler + syntetisk integrationstrin. |
| `docs/evidensbaseret-genimport/status.md`, `docs/changelog.md`, `docs/decisions.md` | Modenhed, historik og afvigelsesbeslutning. |

---

### Task 1: Profil-JSON og profilindlæser

**Files:**

- Create: `.claude/skills/daa-extract/scripts/reimport_profile.py`
- Create: `.claude/skills/daa-extract/scripts/test_reimport_profile.py`
- Create: `.claude/skills/daa-extract/references/reimport-profiles/daa-2018-20-source-evidence-v1.json`

**Interfaces:**

- Consumes: den kanoniske JSON-regel i `private.reimport_canonical_json_text`
  (`schema.sql:2480-2489`), feltmængden i
  `private.validate_reimport_writer_config` (`schema.sql:2366-2378`) og
  CHECK-constrainten `profile_sha256 = private.reimport_canonical_json_sha256(writer_config)`
  (`schema.sql:2389`).
- Produces:
  - `reimport_profile.canonical_json_text(value: Any) -> str`
  - `reimport_profile.canonical_json_sha256(value: Any) -> str`
  - `reimport_profile.load_profile(path: pathlib.Path) -> dict[str, Any]` med
    tilføjet nøgle `profile_sha256: str`
  - `reimport_profile.ProfileError(ValueError)`

- [ ] **Step 1: Skriv den fejlende pytest**

  Opret `.claude/skills/daa-extract/scripts/test_reimport_profile.py`:

  ```python
  """Syntetiske fixtures uden rigtige navne — profilindlæser og kanonisk hash."""
  import json
  from pathlib import Path

  import pytest

  import reimport_profile as rp

  FIXTURE_WRITER_CONFIG = {
      "citation_label_template": "Synthetic side {page_from}",
      "extractor_version": "fixture-v1",
      "observation_extraction_method": "fixture_method",
      "rendition_key": "fixture-rendition",
      "rendition_kind": "pdf_text_layer",
      "rendition_metadata": {
          "edition": "fixture",
          "pdf_sha256": "a" * 64,
          "pdftotext_version": "fixture 0.0",
      },
      "run_key_prefix": "fixture:",
      "schema_version": "fixture-manifest-v1",
  }
  # Verificeret 2026-09-03 mod PostgreSQL 17 med samme kanoniske tekstregel som
  # private.reimport_canonical_json_text (schema.sql:2480-2489).
  KNOWN_VECTOR = "834feadfd65f4b7cecad2fa3d8b058e1d2cd03fe2a805cf9c6cfa2fa6e789ef7"


  def profile_dict(**overrides):
      profile = {
          "profile_schema_version": "reimport-source-evidence-profile-v1",
          "source_id": 4242,
          "profile_id": "fixture-source-evidence-v1",
          "profile_version": "fixture-v1",
          "writer_config": json.loads(json.dumps(FIXTURE_WRITER_CONFIG)),
          "pdf_sha256": "a" * 64,
          "raw_text_sha256": "b" * 64,
          "segment_version": "segment.py@fixture-v1",
          "expected_counts": {"person_creates": 0, "source_evidence": 3},
          "pdftotext_args": {
              "layout": True,
              "first_page": 1,
              "last_page": 2,
              "page_marker": "### PAGE {page} ###",
          },
      }
      profile.update(overrides)
      return profile


  def write(tmp_path, profile):
      path = tmp_path / "profile.json"
      path.write_text(json.dumps(profile, ensure_ascii=False, indent=2) + "\n",
                      encoding="utf-8")
      return path


  def test_canonical_sha_matches_postgres_known_vector():
      assert rp.canonical_json_sha256(FIXTURE_WRITER_CONFIG) == KNOWN_VECTOR


  def test_canonical_text_sorts_keys_and_drops_separators():
      assert rp.canonical_json_text({"b": 1, "a": {"d": [1, 2], "c": "x"}}) == \
          '{"a":{"c":"x","d":[1,2]},"b":1}'


  def test_canonical_text_renders_bool_and_null_like_jsonb():
      assert rp.canonical_json_text({"t": True, "f": False, "n": None}) == \
          '{"f":false,"n":null,"t":true}'


  def test_canonical_sha_rejects_float():
      with pytest.raises(rp.ProfileError) as error:
          rp.canonical_json_sha256({"a": 1.5})
      assert str(error.value) == "PROFILE_CANONICAL_FLOAT_FORBIDDEN"


  def test_load_profile_returns_profile_sha256(tmp_path):
      loaded = rp.load_profile(write(tmp_path, profile_dict()))
      assert loaded["profile_sha256"] == KNOWN_VECTOR


  def test_load_profile_rejects_unfilled_placeholder(tmp_path):
      broken = profile_dict(pdf_sha256="<UDFYLDES FRA INVENTERING>")
      with pytest.raises(rp.ProfileError) as error:
          rp.load_profile(write(tmp_path, broken))
      assert str(error.value) == "PROFILE_PLACEHOLDER_UNFILLED"


  def test_load_profile_rejects_unknown_top_level_key(tmp_path):
      with pytest.raises(rp.ProfileError) as error:
          rp.load_profile(write(tmp_path, profile_dict(extra="x")))
      assert str(error.value) == "PROFILE_FIELD_SET_INVALID"


  def test_load_profile_rejects_writer_config_field_drift(tmp_path):
      config = json.loads(json.dumps(FIXTURE_WRITER_CONFIG))
      del config["run_key_prefix"]
      with pytest.raises(rp.ProfileError) as error:
          rp.load_profile(write(tmp_path, profile_dict(writer_config=config)))
      assert str(error.value) == "PROFILE_WRITER_CONFIG_INVALID"


  def test_load_profile_rejects_citation_template_with_two_tokens(tmp_path):
      config = json.loads(json.dumps(FIXTURE_WRITER_CONFIG))
      config["citation_label_template"] = "Synthetic {page_from} {page_to}"
      with pytest.raises(rp.ProfileError) as error:
          rp.load_profile(write(tmp_path, profile_dict(writer_config=config)))
      assert str(error.value) == "PROFILE_WRITER_CONFIG_INVALID"


  def test_load_profile_rejects_collation_ambiguous_keys(tmp_path):
      config = json.loads(json.dumps(FIXTURE_WRITER_CONFIG))
      config["rendition_metadata"] = {"pdf_a": 1, "pdfa": 2}
      with pytest.raises(rp.ProfileError) as error:
          rp.load_profile(write(tmp_path, profile_dict(writer_config=config)))
      assert str(error.value) == "PROFILE_KEY_COLLATION_UNSTABLE"


  def test_load_profile_rejects_nested_pdf_sha_mismatch(tmp_path):
      config = json.loads(json.dumps(FIXTURE_WRITER_CONFIG))
      config["rendition_metadata"]["pdf_sha256"] = "c" * 64
      with pytest.raises(rp.ProfileError) as error:
          rp.load_profile(write(tmp_path, profile_dict(writer_config=config)))
      assert str(error.value) == "PROFILE_PDF_SHA256_MISMATCH"


  def test_load_profile_rejects_nonzero_person_creates(tmp_path):
      broken = profile_dict(expected_counts={"person_creates": 1, "source_evidence": 3})
      with pytest.raises(rp.ProfileError) as error:
          rp.load_profile(write(tmp_path, broken))
      assert str(error.value) == "PROFILE_EXPECTED_COUNTS_INVALID"


  def test_repository_profile_has_the_locked_identity():
      path = (Path(__file__).resolve().parents[1] /
              "references/reimport-profiles/daa-2018-20-source-evidence-v1.json")
      raw = json.loads(path.read_text(encoding="utf-8"))
      assert raw["source_id"] == 1
      assert raw["profile_id"] == "daa-2018-20-source-evidence-v1"
      assert raw["expected_counts"] == {"person_creates": 0, "source_evidence": 591}
      assert raw["writer_config"]["rendition_key"] == "daa-2018-20-pdftotext-r1"
      assert raw["writer_config"]["rendition_kind"] == "pdf_text_layer"
  ```

- [ ] **Step 2: Kør den fejlende test**

  ```bash
  python3 -m pytest .claude/skills/daa-extract/scripts/test_reimport_profile.py -q
  ```

  Forventet: FEJL — `ModuleNotFoundError: No module named 'reimport_profile'`,
  0 tests kørt.

- [ ] **Step 3: Implementér indlæseren**

  Opret `.claude/skills/daa-extract/scripts/reimport_profile.py`:

  ```python
  #!/usr/bin/env python3
  """Indlæs og validér én udgaveprofil for den generelle source_evidence-writer.

  Den kanoniske JSON-regel er en bit-for-bit spejling af
  private.reimport_canonical_json_text (schema.sql:2480-2489): objekter serialiseres
  med sorterede nøgler, ingen mellemrum, og skalarer som jsonb::text.
  """
  from __future__ import annotations

  import argparse
  import hashlib
  import json
  import re
  from pathlib import Path
  from typing import Any

  HASH_RE = re.compile(r"^[0-9a-f]{64}$")
  KEY_RE = re.compile(r"^[a-z][a-z0-9_]*$")
  PLACEHOLDER = "<UDFYLDES FRA INVENTERING>"
  PROFILE_SCHEMA_VERSION = "reimport-source-evidence-profile-v1"

  PROFILE_KEYS = {
      "profile_schema_version", "source_id", "profile_id", "profile_version",
      "writer_config", "pdf_sha256", "raw_text_sha256", "segment_version",
      "expected_counts", "pdftotext_args",
  }
  WRITER_CONFIG_KEYS = {
      "citation_label_template", "extractor_version", "observation_extraction_method",
      "rendition_key", "rendition_kind", "rendition_metadata", "run_key_prefix",
      "schema_version",
  }
  WRITER_CONFIG_TEXT_KEYS = (
      "run_key_prefix", "schema_version", "extractor_version", "rendition_key",
      "rendition_kind", "observation_extraction_method",
  )
  RENDITION_METADATA_KEYS = {"edition", "pdf_sha256", "pdftotext_version"}
  PDFTOTEXT_ARGS_KEYS = {"layout", "first_page", "last_page", "page_marker"}
  EXPECTED_COUNTS_KEYS = {"person_creates", "source_evidence"}


  class ProfileError(ValueError):
      pass


  def _fail(code: str) -> None:
      raise ProfileError(code)


  def canonical_json_text(value: Any) -> str:
      if isinstance(value, bool):
          return "true" if value else "false"
      if value is None:
          return "null"
      if isinstance(value, dict):
          parts = []
          for key in sorted(value):
              if not isinstance(key, str):
                  _fail("PROFILE_CANONICAL_TYPE_INVALID")
              parts.append(json.dumps(key, ensure_ascii=False) + ":"
                           + canonical_json_text(value[key]))
          return "{" + ",".join(parts) + "}"
      if isinstance(value, list):
          return "[" + ",".join(canonical_json_text(item) for item in value) + "]"
      if isinstance(value, float):
          _fail("PROFILE_CANONICAL_FLOAT_FORBIDDEN")
      if isinstance(value, int):
          return str(value)
      if isinstance(value, str):
          return json.dumps(value, ensure_ascii=False)
      _fail("PROFILE_CANONICAL_TYPE_INVALID")
      raise AssertionError("unreachable")


  def canonical_json_sha256(value: Any) -> str:
      return hashlib.sha256(canonical_json_text(value).encode("utf-8")).hexdigest()


  def _assert_collation_stable(value: Any) -> None:
      """PostgreSQLs ORDER BY 1 kan ignorere tegnsætning; kodepunktordenen skal
      give samme resultat, ellers divergerer profile_sha256 fra databasens."""
      if isinstance(value, list):
          for item in value:
              _assert_collation_stable(item)
          return
      if not isinstance(value, dict):
          return
      keys = list(value)
      for key in keys:
          if not isinstance(key, str) or not KEY_RE.match(key):
              _fail("PROFILE_KEY_COLLATION_UNSTABLE")
      if sorted(keys) != sorted(keys, key=lambda k: (k.replace("_", ""), k)):
          _fail("PROFILE_KEY_COLLATION_UNSTABLE")
      for key in keys:
          _assert_collation_stable(value[key])


  def _assert_no_placeholder(value: Any) -> None:
      if isinstance(value, str) and PLACEHOLDER in value:
          _fail("PROFILE_PLACEHOLDER_UNFILLED")
      if isinstance(value, dict):
          for item in value.values():
              _assert_no_placeholder(item)
      if isinstance(value, list):
          for item in value:
              _assert_no_placeholder(item)


  def _text(value: Any) -> bool:
      return isinstance(value, str) and value.strip() != "" and "\x00" not in value


  def _positive_int(value: Any) -> bool:
      return isinstance(value, int) and not isinstance(value, bool) and value >= 1


  def _validate_writer_config(config: Any, pdf_sha256: str) -> None:
      if not isinstance(config, dict) or set(config) != WRITER_CONFIG_KEYS:
          _fail("PROFILE_WRITER_CONFIG_INVALID")
      for key in WRITER_CONFIG_TEXT_KEYS:
          if not _text(config[key]):
              _fail("PROFILE_WRITER_CONFIG_INVALID")
      template = config["citation_label_template"]
      if not isinstance(template, str) or template.count("{page_from}") != 1 \
              or re.search(r"\{[^}]*\}", template.replace("{page_from}", "")):
          _fail("PROFILE_WRITER_CONFIG_INVALID")
      metadata = config["rendition_metadata"]
      if not isinstance(metadata, dict) or set(metadata) != RENDITION_METADATA_KEYS \
              or not _text(metadata["edition"]) or not _text(metadata["pdftotext_version"]) \
              or not isinstance(metadata["pdf_sha256"], str):
          _fail("PROFILE_WRITER_CONFIG_INVALID")
      if metadata["pdf_sha256"] != pdf_sha256:
          _fail("PROFILE_PDF_SHA256_MISMATCH")


  def load_profile(path: Path) -> dict[str, Any]:
      try:
          profile = json.loads(Path(path).read_text(encoding="utf-8"))
      except (OSError, ValueError):
          _fail("PROFILE_UNREADABLE")
      _assert_no_placeholder(profile)
      if not isinstance(profile, dict) or set(profile) != PROFILE_KEYS:
          _fail("PROFILE_FIELD_SET_INVALID")
      if profile["profile_schema_version"] != PROFILE_SCHEMA_VERSION:
          _fail("PROFILE_FIELD_SET_INVALID")
      if not _positive_int(profile["source_id"]) or not _text(profile["profile_id"]) \
              or not _text(profile["profile_version"]) or not _text(profile["segment_version"]):
          _fail("PROFILE_FIELD_SET_INVALID")
      for key in ("pdf_sha256", "raw_text_sha256"):
          if not isinstance(profile[key], str) or not HASH_RE.match(profile[key]):
              _fail("PROFILE_MEASURED_HASH_INVALID")
      counts = profile["expected_counts"]
      if not isinstance(counts, dict) or set(counts) != EXPECTED_COUNTS_KEYS \
              or counts["person_creates"] != 0 or not _positive_int(counts["source_evidence"]):
          _fail("PROFILE_EXPECTED_COUNTS_INVALID")
      args = profile["pdftotext_args"]
      if not isinstance(args, dict) or set(args) != PDFTOTEXT_ARGS_KEYS \
              or args["layout"] is not True or not _positive_int(args["first_page"]) \
              or not _positive_int(args["last_page"]) or args["last_page"] < args["first_page"] \
              or args["page_marker"] != "### PAGE {page} ###":
          _fail("PROFILE_PDFTOTEXT_ARGS_INVALID")
      _validate_writer_config(profile["writer_config"], profile["pdf_sha256"])
      _assert_collation_stable(profile["writer_config"])
      profile["profile_sha256"] = canonical_json_sha256(profile["writer_config"])
      return profile


  def main() -> None:
      parser = argparse.ArgumentParser()
      parser.add_argument("--profile", required=True)
      args = parser.parse_args()
      profile = load_profile(Path(args.profile))
      print(json.dumps({
          "source_id": profile["source_id"],
          "profile_id": profile["profile_id"],
          "profile_version": profile["profile_version"],
          "profile_sha256": profile["profile_sha256"],
          "expected_counts": profile["expected_counts"],
      }, ensure_ascii=False, indent=2))


  if __name__ == "__main__":
      main()
  ```

- [ ] **Step 4: Opret profil-JSON'en med de målte konstanter**

  Opret `.claude/skills/daa-extract/references/reimport-profiles/daa-2018-20-source-evidence-v1.json`.
  De seks felter markeret `<UDFYLDES FRA INVENTERING>` udfyldes fra
  inventeringsrapporten
  (`docs/superpowers/reviews/2026-09-03-2018-20-fase-a-inventering.md`) FØR
  filen bruges; `load_profile` afviser filen indtil da med
  `PROFILE_PLACEHOLDER_UNFILLED`. `first_page`/`last_page` skal skrives som
  heltal, ikke strenge.

  ```json
  {
    "profile_schema_version": "reimport-source-evidence-profile-v1",
    "source_id": 1,
    "profile_id": "daa-2018-20-source-evidence-v1",
    "profile_version": "source-evidence-v1",
    "writer_config": {
      "citation_label_template": "DAA 2018-20 side {page_from}",
      "extractor_version": "source-evidence-v1",
      "observation_extraction_method": "deterministic_segment_v1",
      "rendition_key": "daa-2018-20-pdftotext-r1",
      "rendition_kind": "pdf_text_layer",
      "rendition_metadata": {
        "edition": "2018-20",
        "pdf_sha256": "<UDFYLDES FRA INVENTERING>",
        "pdftotext_version": "<UDFYLDES FRA INVENTERING>"
      },
      "run_key_prefix": "reimport-source-evidence:",
      "schema_version": "source-evidence-manifest-v1"
    },
    "pdf_sha256": "<UDFYLDES FRA INVENTERING>",
    "raw_text_sha256": "<UDFYLDES FRA INVENTERING>",
    "segment_version": "segment.py@2018-20-v1",
    "expected_counts": {
      "person_creates": 0,
      "source_evidence": 591
    },
    "pdftotext_args": {
      "layout": true,
      "first_page": "<UDFYLDES FRA INVENTERING>",
      "last_page": "<UDFYLDES FRA INVENTERING>",
      "page_marker": "### PAGE {page} ###"
    }
  }
  ```

- [ ] **Step 5: Kør testen grønt**

  ```bash
  python3 -m pytest .claude/skills/daa-extract/scripts/test_reimport_profile.py -q
  ```

  Forventet: PASS, 13 tests.

- [ ] **Step 6: Bekræft den kendte vektor mod PostgreSQL**

  ```bash
  /opt/homebrew/opt/postgresql@17/bin/psql -X -Atc 'WITH v(j) AS (VALUES ($j${"citation_label_template":"Synthetic side {page_from}","extractor_version":"fixture-v1","observation_extraction_method":"fixture_method","rendition_key":"fixture-rendition","rendition_kind":"pdf_text_layer","rendition_metadata":{"edition":"fixture","pdf_sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","pdftotext_version":"fixture 0.0"},"run_key_prefix":"fixture:","schema_version":"fixture-manifest-v1"}$j$::jsonb)), i AS (SELECT (SELECT string_agg(to_jsonb(k)::text||chr(58)||((j->$m$rendition_metadata$m$)->k)::text, chr(44) ORDER BY k) FROM jsonb_object_keys(j->$m$rendition_metadata$m$) k) t FROM v), o AS (SELECT chr(123)||string_agg(to_jsonb(k)::text||chr(58)||CASE WHEN k=$m$rendition_metadata$m$ THEN chr(123)||(SELECT t FROM i)||chr(125) ELSE (j->k)::text END, chr(44) ORDER BY k)||chr(125) t FROM v, jsonb_object_keys(j) k) SELECT encode(sha256(convert_to(t,$e$UTF8$e$)),$h$hex$h$) FROM o;' postgres
  ```

  Forventet output: `834feadfd65f4b7cecad2fa3d8b058e1d2cd03fe2a805cf9c6cfa2fa6e789ef7`
  — identisk med `KNOWN_VECTOR` i testen.

- [ ] **Step 7: Commit**

  ```bash
  git add .claude/skills/daa-extract/scripts/reimport_profile.py \
          .claude/skills/daa-extract/scripts/test_reimport_profile.py \
          .claude/skills/daa-extract/references/reimport-profiles/daa-2018-20-source-evidence-v1.json
  git commit -m "feat(genimport): profil-JSON og fail-closed profilindlæser med kanonisk hash"
  ```

---

### Task 2: Rendition-reproduktion og segmenteringsparitet

**Files:**

- Create: `.claude/skills/daa-extract/scripts/build_source_evidence_rendition.py`
- Create: `.claude/skills/daa-extract/scripts/test_build_source_evidence_rendition.py`

**Interfaces:**

- Consumes: `reimport_profile.load_profile(path) -> dict`,
  `.claude/skills/daa-extract/scripts/extract_text.sh <pdf> <first> <last>`
  (skriver `### PAGE n ###` + `pdftotext -f n -l n -layout` til stdout),
  `.claude/skills/daa-extract/scripts/segment.py <raw.txt>` (skriver
  JSON-array med `linje`, `nr`, `nr_label`, `sider`, `raw_text` til stdout),
  og `data/extracted-2026-06-18/*.json` — udelukkende felterne `linje` og
  `nr_label`.
- Produces:
  - `build_source_evidence_rendition.verify_pdf(pdf_bytes: bytes, profile: dict) -> str`
  - `build_source_evidence_rendition.verify_rendition(rendition_bytes: bytes, profile: dict) -> str`
  - `build_source_evidence_rendition.baseline_lokal_ids(directory: Path) -> list[str]`
  - `build_source_evidence_rendition.segment_parity(posts, baseline_ids, expected_count) -> list[str]`
  - `build_source_evidence_rendition.segment_digest(posts, profile) -> dict`
  - Filer i `--output-dir`: `rendition.txt`, `posts.json`, `segment-digest.json`
  - `build_source_evidence_rendition.RenditionError(ValueError)`

- [ ] **Step 1: Skriv den fejlende pytest**

  Opret `.claude/skills/daa-extract/scripts/test_build_source_evidence_rendition.py`:

  ```python
  """Syntetiske fixtures uden rigtige navne — rendition- og paritetsgates."""
  import hashlib
  import json

  import pytest

  import build_source_evidence_rendition as rendition


  def profile(**overrides):
      base = {
          "pdf_sha256": hashlib.sha256(b"fixture-pdf").hexdigest(),
          "raw_text_sha256": hashlib.sha256(b"fixture-text").hexdigest(),
          "segment_version": "segment.py@fixture-v1",
          "expected_counts": {"person_creates": 0, "source_evidence": 2},
      }
      base.update(overrides)
      return base


  def posts():
      return [
          {"linje": "I", "nr": 1, "nr_label": "1", "sider": "10", "raw_text": "Alfa beta"},
          {"linje": "I", "nr": 2, "nr_label": "2a", "sider": "10-11", "raw_text": "Gamma delta"},
      ]


  def test_verify_pdf_accepts_locked_hash():
      assert rendition.verify_pdf(b"fixture-pdf", profile()) == \
          hashlib.sha256(b"fixture-pdf").hexdigest()


  def test_verify_pdf_rejects_other_pdf():
      with pytest.raises(rendition.RenditionError) as error:
          rendition.verify_pdf(b"other-pdf", profile())
      assert str(error.value) == "SOURCE_EVIDENCE_PDF_SHA_MISMATCH"


  def test_verify_rendition_accepts_locked_hash():
      assert rendition.verify_rendition(b"fixture-text", profile()) == \
          hashlib.sha256(b"fixture-text").hexdigest()


  def test_verify_rendition_rejects_drifted_text():
      with pytest.raises(rendition.RenditionError) as error:
          rendition.verify_rendition(b"fixture-text ", profile())
      assert str(error.value) == "SOURCE_EVIDENCE_RENDITION_SHA_MISMATCH"


  def test_baseline_lokal_ids_reads_only_structural_keys(tmp_path):
      (tmp_path / "I-1.json").write_text(
          json.dumps({"linje": "I", "nr": 1, "nr_label": "1", "navn": "IKKE-LÆST"}),
          encoding="utf-8")
      (tmp_path / "I-2a.json").write_text(
          json.dumps({"linje": "I", "nr": 2, "nr_label": "2a", "navn": "IKKE-LÆST"}),
          encoding="utf-8")
      assert rendition.baseline_lokal_ids(tmp_path) == ["I.1", "I.2a"]


  def test_segment_parity_accepts_identical_sets():
      assert rendition.segment_parity(posts(), ["I.1", "I.2a"], 2) == ["I.1", "I.2a"]


  def test_segment_parity_rejects_missing_lokal_id():
      with pytest.raises(rendition.RenditionError) as error:
          rendition.segment_parity(posts(), ["I.1", "I.2a", "I.3"], 3)
      assert str(error.value) == "SOURCE_EVIDENCE_SEGMENT_PARITY_MISMATCH"


  def test_segment_parity_rejects_extra_lokal_id():
      with pytest.raises(rendition.RenditionError) as error:
          rendition.segment_parity(posts(), ["I.1"], 2)
      assert str(error.value) == "SOURCE_EVIDENCE_SEGMENT_PARITY_MISMATCH"


  def test_segment_parity_rejects_wrong_expected_count():
      with pytest.raises(rendition.RenditionError) as error:
          rendition.segment_parity(posts(), ["I.1", "I.2a"], 3)
      assert str(error.value) == "SOURCE_EVIDENCE_SEGMENT_PARITY_MISMATCH"


  def test_segment_parity_rejects_missing_linje():
      broken = posts()
      broken[0]["linje"] = None
      with pytest.raises(rendition.RenditionError) as error:
          rendition.segment_parity(broken, ["I.1", "I.2a"], 2)
      assert str(error.value) == "SOURCE_EVIDENCE_SEGMENT_PARITY_MISMATCH"


  def test_segment_digest_contains_no_verbatim_text():
      digest = rendition.segment_digest(posts(), profile())
      assert digest["segment_version"] == "segment.py@fixture-v1"
      assert digest["posts"] == [
          {"record_key": "I-1",
           "verbatim_sha256": hashlib.sha256("Alfa beta".encode()).hexdigest()},
          {"record_key": "I-2a",
           "verbatim_sha256": hashlib.sha256("Gamma delta".encode()).hexdigest()},
      ]
      serialized = json.dumps(digest, ensure_ascii=False)
      assert "Alfa beta" not in serialized and "Gamma delta" not in serialized


  def test_segment_digest_is_deterministic():
      assert rendition.segment_digest(posts(), profile()) == \
          rendition.segment_digest(posts(), profile())
  ```

- [ ] **Step 2: Kør den fejlende test**

  ```bash
  python3 -m pytest .claude/skills/daa-extract/scripts/test_build_source_evidence_rendition.py -q
  ```

  Forventet: FEJL — `ModuleNotFoundError: No module named
  'build_source_evidence_rendition'`.

- [ ] **Step 3: Implementér renditionsscriptet**

  Opret `.claude/skills/daa-extract/scripts/build_source_evidence_rendition.py`:

  ```python
  #!/usr/bin/env python3
  """Reproducér renditionen for én udgaveprofil og bevis segmenteringsparitet.

  Fail-closed: PDF-SHA, rå-tekst-SHA og mængden af lokal_id skal alle matche
  profilen og det eksisterende segmenteringsartefakt, ellers stopper fasen.
  Læser aldrig andet end `linje` og `nr_label` fra baseline-artefaktet, så der
  aldrig passerer navne gennem dette trin (spec §7).
  """
  from __future__ import annotations

  import argparse
  import hashlib
  import json
  import subprocess
  from pathlib import Path
  from typing import Any

  from reimport_profile import load_profile

  SCRIPT_DIR = Path(__file__).resolve().parent


  class RenditionError(ValueError):
      pass


  def _fail(code: str) -> None:
      raise RenditionError(code)


  def verify_pdf(pdf_bytes: bytes, profile: dict[str, Any]) -> str:
      digest = hashlib.sha256(pdf_bytes).hexdigest()
      if digest != profile["pdf_sha256"]:
          _fail("SOURCE_EVIDENCE_PDF_SHA_MISMATCH")
      return digest


  def verify_rendition(rendition_bytes: bytes, profile: dict[str, Any]) -> str:
      digest = hashlib.sha256(rendition_bytes).hexdigest()
      if digest != profile["raw_text_sha256"]:
          _fail("SOURCE_EVIDENCE_RENDITION_SHA_MISMATCH")
      return digest


  def baseline_lokal_ids(directory: Path) -> list[str]:
      ids: list[str] = []
      for path in sorted(Path(directory).glob("*.json")):
          row = json.loads(path.read_text(encoding="utf-8"))
          linje, nr_label = row.get("linje"), row.get("nr_label")
          if not isinstance(linje, str) or not linje \
                  or not isinstance(nr_label, str) or not nr_label:
              _fail("SOURCE_EVIDENCE_BASELINE_INVALID")
          ids.append(f"{linje}.{nr_label}")
      if not ids or len(ids) != len(set(ids)):
          _fail("SOURCE_EVIDENCE_BASELINE_INVALID")
      return sorted(ids)


  def _structural_ids(posts: Any) -> list[str]:
      if not isinstance(posts, list) or not posts:
          _fail("SOURCE_EVIDENCE_SEGMENT_PARITY_MISMATCH")
      produced: list[str] = []
      for post in posts:
          if not isinstance(post, dict):
              _fail("SOURCE_EVIDENCE_SEGMENT_PARITY_MISMATCH")
          linje, nr_label = post.get("linje"), post.get("nr_label")
          if not isinstance(linje, str) or not linje \
                  or not isinstance(nr_label, str) or not nr_label:
              _fail("SOURCE_EVIDENCE_SEGMENT_PARITY_MISMATCH")
          produced.append(f"{linje}.{nr_label}")
      return produced


  def segment_parity(posts: Any, baseline_ids: list[str], expected_count: int) -> list[str]:
      produced = _structural_ids(posts)
      if len(produced) != len(set(produced)) or len(produced) != expected_count \
              or set(produced) != set(baseline_ids):
          _fail("SOURCE_EVIDENCE_SEGMENT_PARITY_MISMATCH")
      return sorted(set(produced))


  def segment_digest(posts: Any, profile: dict[str, Any]) -> dict[str, Any]:
      rows = []
      for post in posts:
          linje, nr_label = post.get("linje"), post.get("nr_label")
          text = post.get("raw_text")
          if not isinstance(text, str) or not text:
              _fail("SOURCE_EVIDENCE_SEGMENT_PARITY_MISMATCH")
          rows.append({
              "record_key": f"{linje}-{nr_label}",
              "verbatim_sha256": hashlib.sha256(text.encode("utf-8")).hexdigest(),
          })
      rows.sort(key=lambda row: row["record_key"])
      digest = {
          "digest_schema_version": "source-evidence-segment-digest-v1",
          "segment_version": profile["segment_version"],
          "raw_text_sha256": profile["raw_text_sha256"],
          "posts": rows,
      }
      digest["digest_sha256"] = hashlib.sha256(json.dumps(
          digest, ensure_ascii=False, sort_keys=True, separators=(",", ":")
      ).encode("utf-8")).hexdigest()
      return digest


  def main() -> None:
      parser = argparse.ArgumentParser()
      parser.add_argument("--profile", required=True)
      parser.add_argument("--pdf", required=True)
      parser.add_argument("--baseline-dir", default="data/extracted-2026-06-18")
      parser.add_argument("--output-dir", required=True)
      args = parser.parse_args()

      profile = load_profile(Path(args.profile))
      output_dir = Path(args.output_dir)
      if output_dir.exists():
          _fail("SOURCE_EVIDENCE_OUTPUT_EXISTS")
      verify_pdf(Path(args.pdf).read_bytes(), profile)

      version = subprocess.run(["pdftotext", "-v"], capture_output=True, text=True).stderr
      expected_version = profile["writer_config"]["rendition_metadata"]["pdftotext_version"]
      if expected_version not in version:
          _fail("SOURCE_EVIDENCE_PDFTOTEXT_VERSION_MISMATCH")

      pdftotext_args = profile["pdftotext_args"]
      extracted = subprocess.run(
          [str(SCRIPT_DIR / "extract_text.sh"), str(Path(args.pdf).resolve()),
           str(pdftotext_args["first_page"]), str(pdftotext_args["last_page"])],
          capture_output=True, check=True)
      verify_rendition(extracted.stdout, profile)

      output_dir.mkdir(parents=True)
      rendition_path = output_dir / "rendition.txt"
      rendition_path.write_bytes(extracted.stdout)

      segmented = subprocess.run(
          ["python3", str(SCRIPT_DIR / "segment.py"), str(rendition_path)],
          capture_output=True, check=True, cwd=SCRIPT_DIR)
      posts = json.loads(segmented.stdout.decode("utf-8"))
      (output_dir / "posts.json").write_bytes(segmented.stdout)

      ids = segment_parity(posts, baseline_lokal_ids(Path(args.baseline_dir)),
                           profile["expected_counts"]["source_evidence"])
      digest = segment_digest(posts, profile)
      (output_dir / "segment-digest.json").write_text(
          json.dumps(digest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

      print(json.dumps({
          "raw_text_sha256": profile["raw_text_sha256"],
          "posts": len(ids),
          "segment_digest_sha256": digest["digest_sha256"],
      }, ensure_ascii=False, indent=2))


  if __name__ == "__main__":
      main()
  ```

- [ ] **Step 4: Kør testen grønt**

  ```bash
  python3 -m pytest .claude/skills/daa-extract/scripts/test_build_source_evidence_rendition.py -q
  ```

  Forventet: PASS, 12 tests.

- [ ] **Step 5: Commit**

  ```bash
  git add .claude/skills/daa-extract/scripts/build_source_evidence_rendition.py \
          .claude/skills/daa-extract/scripts/test_build_source_evidence_rendition.py
  git commit -m "feat(genimport): profilstyret rendition-reproduktion med paritetsgate"
  ```

---

### Task 3: Manifest-bygger

**Files:**

- Create: `.claude/skills/daa-extract/scripts/build_source_evidence_manifest.py`
- Create: `.claude/skills/daa-extract/scripts/test_build_source_evidence_manifest.py`

**Interfaces:**

- Consumes: `reimport_profile.load_profile(path) -> dict`, `segment.PAGE_RE`,
  `segment.NOISE_RE` (samme regex-objekter som segmenteringen bruger til at
  springe linjer over), og payload-kontrakten i
  `private.ensure_reimport_source_evidence` (`schema.sql:2624-2643`).
- Produces:
  - `build_source_evidence_manifest.project_rendition(text: str) -> tuple[str, list[int]]`
  - `build_source_evidence_manifest.pages_from_sider(sider: Any) -> tuple[int, int]`
  - `build_source_evidence_manifest.record_key_of(post: dict) -> str`
  - `build_source_evidence_manifest.build_manifest(profile: dict, rendition_bytes: bytes, posts: list) -> dict`
  - Manifestfil på formen `{manifest_content_sha256, source, expected_counts, operations}`
    som `validate_reimport_manifest` i `apply_reimport_helpers.R` accepterer.
  - `build_source_evidence_manifest.ManifestError(ValueError)`

- [ ] **Step 1: Skriv den fejlende pytest**

  Opret `.claude/skills/daa-extract/scripts/test_build_source_evidence_manifest.py`:

  ```python
  """Syntetiske fixtures uden rigtige navne — manifest-byggerens gates."""
  import hashlib
  import json

  import pytest

  import build_source_evidence_manifest as builder

  RENDITION = (
      "### PAGE 10 ###\n"
      "                    I\n"
      "        DEN SYNTETISKE LINJE\n"
      "\n"
      "1.  Alfa   Bravo,  f. 1801,\n"
      "    d. 1860.\n"
      "\n"
      "### PAGE 11 ###\n"
      "2a. Charlie Delta, f. 1830.\n"
  )
  RENDITION_BYTES = RENDITION.encode("utf-8")


  def profile(**overrides):
      base = {
          "source_id": 4242,
          "profile_id": "fixture-source-evidence-v1",
          "profile_sha256": "d" * 64,
          "raw_text_sha256": hashlib.sha256(RENDITION_BYTES).hexdigest(),
          "segment_version": "segment.py@fixture-v1",
          "expected_counts": {"person_creates": 0, "source_evidence": 2},
      }
      base.update(overrides)
      return base


  def posts():
      return [
          {"linje": "I", "nr": 1, "nr_label": "1", "sider": "10",
           "raw_text": "Alfa Bravo, f. 1801, d. 1860."},
          {"linje": "I", "nr": 2, "nr_label": "2a", "sider": "10-11",
           "raw_text": "Charlie Delta, f. 1830."},
      ]


  def test_projection_collapses_whitespace_and_drops_page_markers():
      projection, offsets = builder.project_rendition(RENDITION)
      assert "### PAGE" not in projection
      assert "Alfa Bravo, f. 1801, d. 1860." in projection
      assert len(offsets) == len(projection)
      assert RENDITION[offsets[0]] == projection[0]


  def test_pages_from_sider_single_page():
      assert builder.pages_from_sider("93") == (93, 93)


  def test_pages_from_sider_page_range():
      assert builder.pages_from_sider("93-94") == (93, 94)


  def test_pages_from_sider_rejects_free_text():
      with pytest.raises(builder.ManifestError) as error:
          builder.pages_from_sider("93 f.")
      assert str(error.value) == "SOURCE_EVIDENCE_PAGE_INVALID"


  def test_pages_from_sider_rejects_descending_range():
      with pytest.raises(builder.ManifestError) as error:
          builder.pages_from_sider("94-93")
      assert str(error.value) == "SOURCE_EVIDENCE_PAGE_INVALID"


  def test_record_key_uses_dash_like_load_helpers():
      assert builder.record_key_of(posts()[1]) == "I-2a"


  def test_build_manifest_produces_writer_ready_operations():
      manifest = builder.build_manifest(profile(), RENDITION_BYTES, posts())
      assert set(manifest) == {"manifest_content_sha256", "source",
                               "expected_counts", "operations"}
      assert manifest["source"] == {"id": 4242,
                                    "profile_id": "fixture-source-evidence-v1",
                                    "profile_sha256": "d" * 64}
      assert manifest["expected_counts"] == {"source_evidence": 2,
                                             "person_creates": 0,
                                             "canonical_delta": 0}
      first = manifest["operations"][0]
      assert first["element_id"] == "source-evidence:I-1"
      assert first["dependency_class"] == "source_evidence"
      assert first["disposition"] == "retain_source_only"
      assert first["category"] == "person_post"
      assert first["page_evidence"] == {"page_from": 10, "page_to": 10}
      assert first["source_span"]["char_to"] > first["source_span"]["char_from"] >= 0
      assert first["rendition_content_sha256"] == profile()["raw_text_sha256"]
      assert first["anchor_method"] == "deterministic-segment"
      assert first["verbatim_sha256"] == hashlib.sha256(
          first["verbatim_text"].encode()).hexdigest()


  def test_build_manifest_span_roundtrips_to_raw_text():
      manifest = builder.build_manifest(profile(), RENDITION_BYTES, posts())
      for operation in manifest["operations"]:
          span = operation["source_span"]
          sliced = RENDITION[span["char_from"]:span["char_to"]]
          assert builder.project_rendition(sliced)[0] == operation["verbatim_text"]


  def test_build_manifest_rejects_text_not_in_rendition():
      broken = posts()
      broken[0]["raw_text"] = "Echo Foxtrot, f. 1900."
      with pytest.raises(builder.ManifestError) as error:
          builder.build_manifest(profile(), RENDITION_BYTES, broken)
      assert str(error.value) == "SOURCE_EVIDENCE_SPAN_NOT_FOUND"


  def test_build_manifest_rejects_duplicate_lokal_id():
      broken = posts()
      broken[1]["nr_label"] = "1"
      with pytest.raises(builder.ManifestError) as error:
          builder.build_manifest(profile(), RENDITION_BYTES, broken)
      assert str(error.value) == "SOURCE_EVIDENCE_RECORD_KEY_DUPLICATE"


  def test_build_manifest_rejects_rendition_hash_drift():
      with pytest.raises(builder.ManifestError) as error:
          builder.build_manifest(profile(raw_text_sha256="e" * 64),
                                 RENDITION_BYTES, posts())
      assert str(error.value) == "SOURCE_EVIDENCE_RENDITION_SHA_MISMATCH"


  def test_build_manifest_rejects_count_drift():
      with pytest.raises(builder.ManifestError) as error:
          builder.build_manifest(
              profile(expected_counts={"person_creates": 0, "source_evidence": 3}),
              RENDITION_BYTES, posts())
      assert str(error.value) == "SOURCE_EVIDENCE_COUNT_MISMATCH"


  def test_build_manifest_is_deterministic():
      first = builder.build_manifest(profile(), RENDITION_BYTES, posts())
      second = builder.build_manifest(profile(), RENDITION_BYTES, posts())
      assert first["manifest_content_sha256"] == second["manifest_content_sha256"]
      assert json.dumps(first, sort_keys=True) == json.dumps(second, sort_keys=True)


  def test_build_manifest_carries_no_structured_person_data():
      manifest = builder.build_manifest(profile(), RENDITION_BYTES, posts())
      allowed = {"element_id", "dependency_class", "source_record_key", "source_id",
                 "category", "disposition", "rendition_content_sha256", "source_span",
                 "page_evidence", "verbatim_text", "verbatim_sha256", "anchor_method",
                 "segment_version"}
      for operation in manifest["operations"]:
          assert set(operation) == allowed
  ```

- [ ] **Step 2: Kør den fejlende test**

  ```bash
  python3 -m pytest .claude/skills/daa-extract/scripts/test_build_source_evidence_manifest.py -q
  ```

  Forventet: FEJL — `ModuleNotFoundError: No module named
  'build_source_evidence_manifest'`.

- [ ] **Step 3: Implementér manifest-byggeren**

  Opret `.claude/skills/daa-extract/scripts/build_source_evidence_manifest.py`:

  ```python
  #!/usr/bin/env python3
  """Byg ét lukket, ikke-autoriserende source_evidence-manifest for én udgaveprofil.

  Manifestets form er #153's lukkede gateway-kontrakt (apply_reimport_helpers.R,
  validate_reimport_manifest): præcis manifest_content_sha256, source,
  expected_counts og operations.  Scriptet rører aldrig en database og
  autoriserer aldrig en skrivning.

  Ankring: segment.py:147 gemmer raw_text = norm(' '.join(lines)), så en post er
  aldrig en litteral delstreng af pdftotext-outputtet.  project_rendition bygger
  derfor den samme normalisering over hele renditionen med et offset-kort tilbage
  til den rå tekst, og posten skal findes som EKSAKT delstreng i den projektion.
  Ingen fuzzy-match.
  """
  from __future__ import annotations

  import argparse
  import hashlib
  import json
  import re
  import sys
  from pathlib import Path
  from typing import Any

  sys.path.insert(0, str(Path(__file__).resolve().parent))

  import segment
  from reimport_profile import load_profile

  SIDER_RE = re.compile(r"^(\d{1,6})(?:-(\d{1,6}))?$")
  WHITESPACE_RE = re.compile(r"\s")


  class ManifestError(ValueError):
      pass


  def _fail(code: str) -> None:
      raise ManifestError(code)


  def _project_line(line: str, base: int) -> tuple[list[str], list[int]]:
      chars: list[str] = []
      offsets: list[int] = []
      pending_space = False
      for index, char in enumerate(line):
          if WHITESPACE_RE.match(char):
              if chars:
                  pending_space = True
              continue
          if pending_space:
              chars.append(" ")
              offsets.append(base + index)
              pending_space = False
          chars.append(char)
          offsets.append(base + index)
      return chars, offsets


  def project_rendition(text: str) -> tuple[str, list[int]]:
      """Samme linjeregler som segment._segment_2018_20: PAGE-, blanke og
      NOISE-linjer springes over, øvrige linjer strippes og samles med ét
      mellemrum."""
      chars: list[str] = []
      offsets: list[int] = []
      cursor = 0
      for line in text.split("\n"):
          base = cursor
          cursor += len(line) + 1
          if segment.PAGE_RE.match(line) or not line.strip() \
                  or segment.NOISE_RE.match(line):
              continue
          line_chars, line_offsets = _project_line(line, base)
          if not line_chars:
              continue
          if chars:
              chars.append(" ")
              offsets.append(base)
          chars.extend(line_chars)
          offsets.extend(line_offsets)
      return "".join(chars), offsets


  def pages_from_sider(sider: Any) -> tuple[int, int]:
      if not isinstance(sider, str):
          _fail("SOURCE_EVIDENCE_PAGE_INVALID")
      match = SIDER_RE.match(sider)
      if match is None:
          _fail("SOURCE_EVIDENCE_PAGE_INVALID")
      page_from = int(match.group(1))
      page_to = int(match.group(2)) if match.group(2) else page_from
      if page_from < 1 or page_to < page_from:
          _fail("SOURCE_EVIDENCE_PAGE_INVALID")
      return page_from, page_to


  def record_key_of(post: dict[str, Any]) -> str:
      """Samme nøgle som load_helpers.R:153 (linje + '-' + nr_label)."""
      linje, nr_label = post.get("linje"), post.get("nr_label")
      if not isinstance(linje, str) or not linje \
              or not isinstance(nr_label, str) or not nr_label:
          _fail("SOURCE_EVIDENCE_RECORD_KEY_INVALID")
      return f"{linje}-{nr_label}"


  def build_manifest(profile: dict[str, Any], rendition_bytes: bytes,
                     posts: Any) -> dict[str, Any]:
      rendition_sha = hashlib.sha256(rendition_bytes).hexdigest()
      if rendition_sha != profile["raw_text_sha256"]:
          _fail("SOURCE_EVIDENCE_RENDITION_SHA_MISMATCH")
      text = rendition_bytes.decode("utf-8")
      projection, offsets = project_rendition(text)
      if not isinstance(posts, list) or not posts:
          _fail("SOURCE_EVIDENCE_POSTS_INVALID")

      operations: list[dict[str, Any]] = []
      seen: set[str] = set()
      cursor = 0
      for post in posts:
          if not isinstance(post, dict):
              _fail("SOURCE_EVIDENCE_POSTS_INVALID")
          record_key = record_key_of(post)
          if record_key in seen:
              _fail("SOURCE_EVIDENCE_RECORD_KEY_DUPLICATE")
          seen.add(record_key)
          verbatim = post.get("raw_text")
          if not isinstance(verbatim, str) or not verbatim:
              _fail("SOURCE_EVIDENCE_VERBATIM_TEXT_INVALID")
          start = projection.find(verbatim, cursor)
          if start < 0:
              _fail("SOURCE_EVIDENCE_SPAN_NOT_FOUND")
          end = start + len(verbatim)
          char_from = offsets[start]
          char_to = offsets[end - 1] + 1
          if char_from < 0 or char_to <= char_from:
              _fail("SOURCE_EVIDENCE_SPAN_OVERLAP")
          if project_rendition(text[char_from:char_to])[0] != verbatim:
              _fail("SOURCE_EVIDENCE_SPAN_ROUNDTRIP_MISMATCH")
          cursor = end
          page_from, page_to = pages_from_sider(post.get("sider"))
          operations.append({
              "element_id": f"source-evidence:{record_key}",
              "dependency_class": "source_evidence",
              "source_record_key": record_key,
              "source_id": profile["source_id"],
              "category": "person_post",
              "disposition": "retain_source_only",
              "rendition_content_sha256": rendition_sha,
              "source_span": {"char_from": char_from, "char_to": char_to},
              "page_evidence": {"page_from": page_from, "page_to": page_to},
              "verbatim_text": verbatim,
              "verbatim_sha256": hashlib.sha256(verbatim.encode("utf-8")).hexdigest(),
              "anchor_method": "deterministic-segment",
              "segment_version": profile["segment_version"],
          })

      if len(operations) != profile["expected_counts"]["source_evidence"]:
          _fail("SOURCE_EVIDENCE_COUNT_MISMATCH")

      manifest = {
          "source": {
              "id": profile["source_id"],
              "profile_id": profile["profile_id"],
              "profile_sha256": profile["profile_sha256"],
          },
          "expected_counts": {
              "source_evidence": len(operations),
              "person_creates": profile["expected_counts"]["person_creates"],
              "canonical_delta": 0,
          },
          "operations": sorted(
              operations,
              key=lambda op: (op["source_span"]["char_from"], op["element_id"])),
      }
      manifest["manifest_content_sha256"] = hashlib.sha256(json.dumps(
          manifest, ensure_ascii=False, sort_keys=True, separators=(",", ":")
      ).encode("utf-8")).hexdigest()
      return manifest


  def main() -> None:
      parser = argparse.ArgumentParser()
      parser.add_argument("--profile", required=True)
      parser.add_argument("--rendition-text", required=True)
      parser.add_argument("--posts", required=True)
      parser.add_argument("--output", required=True)
      args = parser.parse_args()
      output = Path(args.output)
      if output.exists():
          _fail("SOURCE_EVIDENCE_OUTPUT_EXISTS")
      profile = load_profile(Path(args.profile))
      manifest = build_manifest(
          profile,
          Path(args.rendition_text).read_bytes(),
          json.loads(Path(args.posts).read_text(encoding="utf-8")))
      output.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
                        encoding="utf-8")
      print(json.dumps({
          "manifest_content_sha256": manifest["manifest_content_sha256"],
          "manifest_bytes_sha256": hashlib.sha256(output.read_bytes()).hexdigest(),
          "source_evidence": len(manifest["operations"]),
      }, ensure_ascii=False, indent=2))


  if __name__ == "__main__":
      main()
  ```

- [ ] **Step 4: Kør testen grønt**

  ```bash
  python3 -m pytest .claude/skills/daa-extract/scripts/test_build_source_evidence_manifest.py -q
  ```

  Forventet: PASS, 15 tests.

- [ ] **Step 5: Bevis gateway-kompatibilitet**

  Manifestet skal accepteres af `validate_reimport_manifest`. Byg et
  fixture-manifest fra testens data og send det gennem R-valideringen:

  ```bash
  Rscript -e 'source(".claude/skills/daa-extract/scripts/apply_reimport_helpers.R"); m <- jsonlite::fromJSON(commandArgs(TRUE)[[1]], simplifyVector = FALSE); validate_reimport_manifest(m); cat("MANIFEST OK", length(m$operations), "\n")' /private/tmp/daa149a-fixture-manifest.json
  ```

  Forventet: `MANIFEST OK 2`. Fejler valideringen, er manifestets nøglemængde
  eller talformat drevet, og Step 3 skal rettes — ikke helpers.

- [ ] **Step 6: Commit**

  ```bash
  git add .claude/skills/daa-extract/scripts/build_source_evidence_manifest.py \
          .claude/skills/daa-extract/scripts/test_build_source_evidence_manifest.py
  git commit -m "feat(genimport): deterministisk source_evidence-manifest med eksakt delstrengsankring"
  ```

---

### Task 4: Læse-kun preview og autorisationsvej

**Files:**

- Create: `.claude/skills/daa-extract/scripts/export_reimport_preview_helpers.R`
- Create: `.claude/skills/daa-extract/scripts/export_reimport_preview.R`
- Create: `tests/testthat/test-export-reimport-preview.R`

**Interfaces:**

- Consumes: `apply_reimport_helpers.R`'s `validate_reimport_manifest(manifest)`,
  `reimport_authorized_payloads(manifest) -> named list`,
  `reimport_writer_expected_counts(manifest) -> list(person_creates, source_evidence)`;
  `public.narrative_record_contract_version()`;
  `private.reimport_writer_profile`; ACL'en i `schema.sql:3178-3180`.
- Produces:
  - `preview_source_state(query, manifest) -> list` (før-billede)
  - `preview_authorization_request(manifest) -> list(expected_counts, authorized_elements)`
  - `validate_preview_readonly(state)` som fail-closer på skrivbar transaktion
  - `build_reimport_preview(query, manifest, manifest_bytes_sha256) -> list`
  - Fil `<output>` hvis SHA-256 er `preview_sha256` til `apply_reimport.R --preview-sha256`
  - `PREVIEW_*`-fejlkoder

**Autorisationsvejen (mål, ikke gæt):**

- `public.red_authorize_reimport(...)` er REVOKED fra `PUBLIC, anon,
  authenticated, service_role` i `schema.sql:3178` og derefter GRANTED **kun**
  til `service_role` i `schema.sql:3179`. Alle øvrige trin
  (`red_preflight_reimport_authorization`, `red_begin_reimport`,
  `red_apply_reimport_source_evidence`, `red_finalize_reimport`,
  `red_reimport_batch_result`) er GRANTED til `authenticated`
  (`schema.sql:3180`).
- Uanset rolle kræver hver funktion `private.require_reimport_writer_editor()`
  (`schema.sql:2544-2549`): `auth.uid()` skal være sat og
  `public.current_rolle()` skal være `'redaktion'`. `auth.uid()` læses af
  Supabase fra `request.jwt.claim.sub`.
- I rehearsal sættes principalen præcis som
  `tests/integration/test-reimport-writer.R:18-25` gør det: opret rækken i
  `auth.users`, opret `public.profiles`-rækken med `rolle='redaktion'`, og kør
  `SELECT set_config('request.jwt.claim.sub', <uuid>, false)`. Ejer-/superuser-
  sessionen omgår GRANT'en, men **ikke** rollekravet.
- `red_begin_reimport` kræver `v_auth.principal_id = v_actor`
  (`schema.sql:2710`), så autorisation og apply skal udføres af **samme**
  aktør-UUID.
- `--dry-run` selv-autoriserer i gatewayen (`apply_reimport_helpers.R`,
  `authorize`-grenen) og ruller tilbage. `--apply` gør det **ikke**: den kræver
  `--authorization '{"id":"<uuid>"}'` fra en allerede committet autorisation.

- [ ] **Step 1: Skriv den fejlende testthat-test**

  Opret `tests/testthat/test-export-reimport-preview.R`:

  ```r
  library(testthat)

  root <- normalizePath(file.path(getwd(), "../.."), mustWork = TRUE)
  source(file.path(root, ".claude/skills/daa-extract/scripts/apply_reimport_helpers.R"), local = TRUE)
  source(file.path(root, ".claude/skills/daa-extract/scripts/export_reimport_preview_helpers.R"), local = TRUE)

  sha <- function(letter) paste(rep(letter, 64L), collapse = "")

  fixture_manifest <- function() {
    list(
      manifest_content_sha256 = sha("a"),
      source = list(id = 4242L, profile_id = "fixture-source-evidence-v1",
                    profile_sha256 = sha("b")),
      expected_counts = list(source_evidence = 2L, person_creates = 0L,
                             canonical_delta = 0L),
      operations = list(
        list(element_id = "source-evidence:I-1", dependency_class = "source_evidence",
             source_record_key = "I-1", disposition = "retain_source_only",
             category = "person_post", rendition_content_sha256 = sha("c"),
             source_span = list(char_from = 0L, char_to = 9L),
             page_evidence = list(page_from = 10L, page_to = 10L),
             verbatim_text = "Alfa Bravo"),
        list(element_id = "source-evidence:I-2a", dependency_class = "source_evidence",
             source_record_key = "I-2a", disposition = "retain_source_only",
             category = "person_post", rendition_content_sha256 = sha("c"),
             source_span = list(char_from = 20L, char_to = 33L),
             page_evidence = list(page_from = 10L, page_to = 11L),
             verbatim_text = "Charlie Delta")))
  }

  fake_query <- function(overrides = list()) {
    function(sql, params = list()) {
      if (grepl("transaction_read_only", sql, fixed = TRUE))
        return(overrides$state %||% data.frame(
          database_identity = "{\"database_name\":\"daa149a\",\"system_identifier\":\"1\"}",
          database_name = "daa149a", system_identifier = "1",
          transaction_read_only = "on", contract_version = 2L,
          stringsAsFactors = FALSE))
      if (grepl("reimport_writer_profile", sql, fixed = TRUE))
        return(overrides$profile %||% data.frame(n = 1L))
      if (grepl("source_rendition", sql, fixed = TRUE))
        return(data.frame(renditions = 0L, records = 0L, occurrences = 0L,
                          anchors = 0L, runs = 0L))
      if (grepl("person_external_id", sql, fixed = TRUE))
        return(overrides$keys %||% data.frame(record_key = c("I-1", "I-2a"),
                                              stringsAsFactors = FALSE))
      data.frame(h = sha("f"), stringsAsFactors = FALSE)
    }
  }

  `%||%` <- function(x, y) if (is.null(x)) y else x

  test_that("authorization request mirrors the writer's closed payload contract", {
    request <- preview_authorization_request(fixture_manifest())
    expect_identical(names(request$expected_counts), c("person_creates", "source_evidence"))
    expect_identical(request$expected_counts$source_evidence, 2L)
    expect_identical(request$expected_counts$person_creates, 0L)
    expect_identical(sort(names(request$authorized_elements)),
                     c("source-evidence:I-1", "source-evidence:I-2a"))
    expect_true(all(grepl("^source-evidence:.+$", names(request$authorized_elements))))
    expect_null(request$authorized_elements[["source-evidence:I-1"]]$element_id)
    expect_null(request$authorized_elements[["source-evidence:I-1"]]$dependency_class)
    expect_identical(request$authorized_elements[["source-evidence:I-1"]]$disposition,
                     "retain_source_only")
  })

  test_that("preview refuses a writable transaction", {
    state <- data.frame(
      database_identity = "{\"database_name\":\"daa149a\",\"system_identifier\":\"1\"}",
      database_name = "daa149a", system_identifier = "1",
      transaction_read_only = "off", contract_version = 2L, stringsAsFactors = FALSE)
    expect_error(
      build_reimport_preview(fake_query(list(state = state)), fixture_manifest(), sha("e")),
      "PREVIEW_TRANSACTION_NOT_READ_ONLY")
  })

  test_that("preview refuses a base that is not on narrative record contract 2", {
    state <- data.frame(
      database_identity = "{\"database_name\":\"daa149a\",\"system_identifier\":\"1\"}",
      database_name = "daa149a", system_identifier = "1",
      transaction_read_only = "on", contract_version = 1L, stringsAsFactors = FALSE)
    expect_error(
      build_reimport_preview(fake_query(list(state = state)), fixture_manifest(), sha("e")),
      "PREVIEW_NARRATIVE_RECORD_CONTRACT_REQUIRED")
  })

  test_that("preview refuses a missing writer profile row", {
    expect_error(
      build_reimport_preview(fake_query(list(profile = data.frame(n = 0L))),
                             fixture_manifest(), sha("e")),
      "PREVIEW_WRITER_PROFILE_MISSING")
  })

  test_that("preview reports the record_key set difference as sets, not counts", {
    keys <- data.frame(record_key = c("I-1", "I-3"), stringsAsFactors = FALSE)
    preview <- build_reimport_preview(fake_query(list(keys = keys)),
                                      fixture_manifest(), sha("e"))
    expect_identical(preview$record_key_coverage$only_in_manifest, "I-2a")
    expect_identical(preview$record_key_coverage$only_in_person_external_id, "I-3")
  })

  test_that("preview binds the manifest and carries no verbatim text", {
    preview <- build_reimport_preview(fake_query(), fixture_manifest(), sha("e"))
    expect_identical(preview$manifest$manifest_content_sha256, sha("a"))
    expect_identical(preview$manifest$manifest_bytes_sha256, sha("e"))
    expect_identical(preview$before_counts$source_record, 0L)
    serialized <- jsonlite::toJSON(preview, auto_unbox = TRUE, null = "null")
    expect_false(grepl("Alfa Bravo", serialized, fixed = TRUE))
    expect_false(grepl("Charlie Delta", serialized, fixed = TRUE))
  })

  test_that("preview rejects a manifest with person_creates", {
    manifest <- fixture_manifest()
    manifest$expected_counts$person_creates <- 1L
    expect_error(build_reimport_preview(fake_query(), manifest, sha("e")),
                 "REIMPORT_MANIFEST_COUNTS_INVALID")
  })
  ```

- [ ] **Step 2: Kør den fejlende test**

  ```bash
  Rscript -e 'testthat::test_file("tests/testthat/test-export-reimport-preview.R")'
  ```

  Forventet: FEJL — `cannot open file
  '.../export_reimport_preview_helpers.R': No such file or directory`.

- [ ] **Step 3: Implementér helpers**

  Opret `.claude/skills/daa-extract/scripts/export_reimport_preview_helpers.R`:

  ```r
  # Fail-closed, forbindelsesfrie helpers til det læse-kun før-billede, der
  # binder én source_evidence-apply.  Filen har ingen sideeffekter og testes med
  # injiceret query-funktion.

  `%||%` <- function(value, fallback) if (is.null(value)) fallback else value

  preview_stop <- function(code) stop(code, call. = FALSE)

  preview_hash <- function(value) {
    is.character(value) && length(value) == 1L && !is.na(value) &&
      grepl("^[0-9a-f]{64}$", value)
  }

  preview_authorization_request <- function(manifest) {
    validate_reimport_manifest(manifest)
    if (!identical(manifest$expected_counts$person_creates, 0L) ||
        !identical(manifest$expected_counts$canonical_delta, 0L))
      preview_stop("PREVIEW_PERSON_CREATE_FORBIDDEN")
    list(
      expected_counts = reimport_writer_expected_counts(manifest),
      authorized_elements = reimport_authorized_payloads(manifest)
    )
  }

  preview_source_state <- function(query, manifest) {
    state <- query(paste(
      "SELECT jsonb_build_object('database_name',current_database(),",
      "'system_identifier',(pg_control_system()).system_identifier::text)::text",
      "AS database_identity, current_database() AS database_name,",
      "(pg_control_system()).system_identifier::text AS system_identifier,",
      "current_setting('transaction_read_only') AS transaction_read_only,",
      "public.narrative_record_contract_version() AS contract_version"))
    if (!identical(as.character(state$transaction_read_only[[1L]]), "on"))
      preview_stop("PREVIEW_TRANSACTION_NOT_READ_ONLY")
    if (!identical(as.integer(state$contract_version[[1L]]), 2L))
      preview_stop("PREVIEW_NARRATIVE_RECORD_CONTRACT_REQUIRED")
    profile <- query(paste(
      "SELECT count(*) AS n FROM private.reimport_writer_profile",
      "WHERE source_id=$1 AND profile_id=$2 AND profile_sha256=$3"),
      list(manifest$source$id, manifest$source$profile_id,
           manifest$source$profile_sha256))
    if (!identical(as.integer(profile$n[[1L]]), 1L))
      preview_stop("PREVIEW_WRITER_PROFILE_MISSING")
    state
  }

  preview_before_counts <- function(query, manifest) {
    counts <- query(paste(
      "SELECT (SELECT count(*) FROM private.source_rendition WHERE source_id=$1) AS renditions,",
      "(SELECT count(*) FROM private.source_record WHERE source_id=$1) AS records,",
      "(SELECT count(*) FROM private.source_record_occurrence o",
      " JOIN private.source_rendition r ON r.id=o.rendition_id WHERE r.source_id=$1) AS occurrences,",
      "(SELECT count(*) FROM private.source_record_anchor_event a",
      " JOIN private.source_record sr ON sr.id=a.source_record_id",
      " WHERE sr.source_id=$1 AND a.decision_status='accepted') AS anchors,",
      "(SELECT count(*) FROM private.extraction_run WHERE source_id=$1) AS runs"),
      list(manifest$source$id))
    list(
      source_rendition = as.integer(counts$renditions[[1L]]),
      source_record = as.integer(counts$records[[1L]]),
      source_record_occurrence = as.integer(counts$occurrences[[1L]]),
      source_record_anchor_accepted = as.integer(counts$anchors[[1L]]),
      extraction_run = as.integer(counts$runs[[1L]])
    )
  }

  preview_record_key_coverage <- function(query, manifest) {
    manifest_keys <- sort(vapply(manifest$operations, `[[`, "", "source_record_key"))
    rows <- query(
      "SELECT record_key FROM public.person_external_id WHERE source_id=$1 AND record_key IS NOT NULL",
      list(manifest$source$id))
    external_keys <- sort(unique(as.character(rows$record_key)))
    list(
      manifest_keys = length(manifest_keys),
      person_external_id_keys = length(external_keys),
      only_in_manifest = setdiff(manifest_keys, external_keys),
      only_in_person_external_id = setdiff(external_keys, manifest_keys)
    )
  }

  preview_canonical_baseline <- function(query) {
    aggregate <- function(sql) {
      row <- query(sprintf(paste(
        "SELECT coalesce(encode(sha256(convert_to(",
        "string_agg(row_text, chr(10) ORDER BY row_text),'UTF8')),'hex'),'empty') AS h",
        "FROM (%s) s"), sql))
      as.character(row$h[[1L]])
    }
    list(
      person = aggregate("SELECT p::text AS row_text FROM public.person p"),
      fact = aggregate("SELECT f::text AS row_text FROM public.fact f"),
      family_member = aggregate("SELECT m::text AS row_text FROM public.family_member m"),
      narrative = aggregate("SELECT n::text AS row_text FROM public.narrative n"),
      narrative_record_publication = aggregate(
        "SELECT b::text AS row_text FROM private.narrative_record_publication b")
    )
  }

  build_reimport_preview <- function(query, manifest, manifest_bytes_sha256) {
    request <- preview_authorization_request(manifest)
    if (!preview_hash(manifest_bytes_sha256))
      preview_stop("PREVIEW_MANIFEST_BYTES_HASH_INVALID")
    state <- preview_source_state(query, manifest)
    list(
      preview_schema_version = "reimport-source-evidence-preview-v1",
      database = list(
        database_identity = as.character(state$database_identity[[1L]]),
        database_name = as.character(state$database_name[[1L]]),
        system_identifier = as.character(state$system_identifier[[1L]]),
        narrative_record_contract_version = 2L),
      source = manifest$source,
      manifest = list(
        manifest_content_sha256 = manifest$manifest_content_sha256,
        manifest_bytes_sha256 = manifest_bytes_sha256),
      expected_counts = request$expected_counts,
      before_counts = preview_before_counts(query, manifest),
      record_key_coverage = preview_record_key_coverage(query, manifest),
      canonical_baseline_sha256 = preview_canonical_baseline(query),
      database_write_authorized = FALSE,
      production_authorized = FALSE
    )
  }
  ```

- [ ] **Step 4: Implementér CLI'en**

  Opret `.claude/skills/daa-extract/scripts/export_reimport_preview.R`:

  ```r
  #!/usr/bin/env Rscript
  # Læse-kun før-billede for én source_evidence-apply.  Åbner en REPEATABLE READ
  # READ ONLY transaktion, kalder aldrig en muterende RPC og ruller altid tilbage.
  suppressPackageStartupMessages({ library(DBI); library(RPostgres); library(jsonlite) })

  args <- commandArgs(trailingOnly = TRUE)
  flags <- args[grepl("^--", args)]
  allowed <- c("--profile", "--manifest", "--manifest-sha256", "--output")
  if (any(!flags %in% allowed) || anyDuplicated(flags) || !all(allowed %in% flags))
    stop("PREVIEW_CLI_INVALID", call. = FALSE)
  value <- function(flag) {
    index <- match(flag, args)
    if (is.na(index) || index == length(args) || grepl("^--", args[[index + 1L]]))
      stop("PREVIEW_CLI_INVALID", call. = FALSE)
    args[[index + 1L]]
  }

  script_arg <- grep("^--file=", commandArgs(), value = TRUE)[1L]
  script_dir <- dirname(normalizePath(sub("^--file=", "", script_arg)))
  source(file.path(script_dir, "apply_reimport_helpers.R"))
  source(file.path(script_dir, "export_reimport_preview_helpers.R"))

  manifest_path <- value("--manifest")
  size <- file.info(manifest_path)$size
  if (is.na(size)) stop("PREVIEW_CLI_INVALID", call. = FALSE)
  raw <- readBin(manifest_path, "raw", n = size)
  manifest_bytes_sha256 <- digest::digest(raw, algo = "sha256", serialize = FALSE)
  if (!identical(manifest_bytes_sha256, value("--manifest-sha256")))
    stop("PREVIEW_MANIFEST_HASH_INVALID", call. = FALSE)
  manifest <- jsonlite::fromJSON(rawToChar(raw), simplifyVector = FALSE)

  profile <- jsonlite::fromJSON(value("--profile"), simplifyVector = FALSE)
  if (!identical(as.integer(profile$source_id), as.integer(manifest$source$id)) ||
      !identical(profile$profile_id, manifest$source$profile_id))
    stop("PREVIEW_PROFILE_MANIFEST_MISMATCH", call. = FALSE)

  output <- value("--output")
  if (file.exists(output)) stop("PREVIEW_OUTPUT_EXISTS", call. = FALSE)

  con <- DBI::dbConnect(RPostgres::Postgres(), dbname = Sys.getenv("PGDATABASE"),
    host = Sys.getenv("PGHOST"), port = Sys.getenv("PGPORT"),
    user = Sys.getenv("PGUSER"), password = Sys.getenv("PGPASSWORD"))
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  DBI::dbExecute(con, "BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY")
  query <- function(sql, params = list())
    if (length(params)) DBI::dbGetQuery(con, sql, params = params) else DBI::dbGetQuery(con, sql)
  preview <- build_reimport_preview(query, manifest, manifest_bytes_sha256)
  DBI::dbExecute(con, "ROLLBACK")

  writeLines(jsonlite::toJSON(preview, auto_unbox = TRUE, null = "null", pretty = TRUE),
             output)
  cat(jsonlite::toJSON(list(
    preview_sha256 = digest::digest(file = output, algo = "sha256"),
    manifest_content_sha256 = manifest$manifest_content_sha256,
    manifest_bytes_sha256 = manifest_bytes_sha256,
    source_evidence = length(manifest$operations)
  ), auto_unbox = TRUE, pretty = TRUE), "\n")
  ```

  **Konvention for `preview_sha256`:** `apply_reimport.R --preview-sha256` er
  for databasen en uigennemsigtig binding. 149a binder den til
  **preview-artefaktets filbytes**, så en apply er bundet til præcis det
  før-billede, den blev godkendt på. Bemærk konflikten:
  `public.red_authorize_reimport_name_completion` kræver
  `b.preview_sha256 = p_source_manifest_bytes_sha256` (`schema.sql:2996`), så en
  batch bundet på denne måde kan **aldrig** kædes videre til
  `name_completion`. Det er acceptabelt for 149a (0 `person_creates`), men skal
  stå i rehearsal-rapporten, og Task 5 asserter at der ikke findes en
  `name_completion`-autorisation for profilen.

- [ ] **Step 5: Kør testen grønt**

  ```bash
  Rscript -e 'testthat::test_file("tests/testthat/test-export-reimport-preview.R")'
  ```

  Forventet: PASS, 7 tests, 0 fejl.

- [ ] **Step 6: Kør hele R-suiten**

  ```bash
  Rscript run-tests.R
  ```

  Forventet: PASS uden nye fejl.

- [ ] **Step 7: Commit**

  ```bash
  git add .claude/skills/daa-extract/scripts/export_reimport_preview.R \
          .claude/skills/daa-extract/scripts/export_reimport_preview_helpers.R \
          tests/testthat/test-export-reimport-preview.R
  git commit -m "feat(genimport): laese-kun preview og autorisationsanmodning for source_evidence"
  ```

---

### Task 5: Rehearsal mod engangs-restore

**Files:**

- Create: `tests/integration/test-reimport-source-evidence.R`
- Create: `docs/runbooks/source-evidence-reimport-rehearsal.md`
- Modify: `.github/workflows/ci.yml`

**Interfaces:**

- Consumes: `public.red_authorize_reimport(text,text,text,bigint,text,text,jsonb,jsonb,uuid,timestamptz)`,
  `public.red_preflight_reimport_authorization(uuid,text,text)`,
  `public.red_begin_reimport(uuid,text,text)`,
  `public.red_apply_reimport_source_evidence(uuid,text,jsonb)`,
  `public.red_finalize_reimport(uuid) -> jsonb`,
  `public.red_reimport_batch_result(uuid,uuid) -> jsonb`,
  `public.red_authorize_reimport_reversal(uuid,uuid,timestamptz) -> uuid`,
  `public.red_reverse_reimport(uuid,uuid) -> jsonb`;
  `execute_reimport(manifest, preview_sha256, mode, gateway, authorization) -> list`
  og `new_reimport_dbi_gateway(connection_factory)` fra `apply_reimport_helpers.R`;
  `tests/sql/reimport-writer-v2-bootstrap.sql`.
- Produces: en syntetisk, CI-kørbar integrationstest og en manuel
  runbook-procedure mod en engangs-restore af et prod-dump. Runbooken tager
  dump-stien som `--dump`-parameter; ingen sti er hardkodet.

- [ ] **Step 1: Skriv den fejlende integrationstest**

  Opret `tests/integration/test-reimport-source-evidence.R`:

  ```r
  # Disponerbar #149a source_evidence-integration.  Hver identitet, hash og
  # tekst nedenfor er syntetisk; der oprettes intet historisk kildeindhold.
  suppressPackageStartupMessages({ library(DBI); library(RPostgres); library(jsonlite) })

  root <- normalizePath(file.path(dirname(sub("^--file=", "",
    grep("^--file=", commandArgs(), value = TRUE)[1L])), "../.."), mustWork = TRUE)
  source(file.path(root, ".claude/skills/daa-extract/scripts/apply_reimport_helpers.R"))

  stopifnot(nzchar(Sys.getenv("PGHOST")), nzchar(Sys.getenv("PGPORT")),
    nzchar(Sys.getenv("PGDATABASE")), nzchar(Sys.getenv("PGUSER")))
  connect <- function() dbConnect(Postgres(), dbname = Sys.getenv("PGDATABASE"),
    host = Sys.getenv("PGHOST"), port = Sys.getenv("PGPORT"),
    user = Sys.getenv("PGUSER"), password = Sys.getenv("PGPASSWORD"))
  con <- connect(); on.exit(dbDisconnect(con), add = TRUE)
  q <- function(sql, params = list())
    if (length(params)) dbGetQuery(con, sql, params = params) else dbGetQuery(con, sql)
  e <- function(sql, params = list())
    if (length(params)) dbExecute(con, sql, params = params) else dbExecute(con, sql)
  sha <- function(letter) paste(rep(letter, 64L), collapse = "")

  stopifnot(q("SELECT public.narrative_record_contract_version() v")$v[[1L]] == 2L)

  actor <- "14900000-0000-4000-8000-000000000001"
  source_id <- 149001L
  profile_id <- "fixture-source-evidence-v1"
  writer_config <- paste0('{"citation_label_template":"Synthetic side {page_from}",',
    '"extractor_version":"fixture-v1","observation_extraction_method":"deterministic_segment_v1",',
    '"rendition_key":"fixture-pdftotext-r1","rendition_kind":"pdf_text_layer",',
    '"rendition_metadata":{"edition":"fixture","pdf_sha256":"', sha("a"),
    '","pdftotext_version":"fixture 0.0"},"run_key_prefix":"reimport-source-evidence:",',
    '"schema_version":"source-evidence-manifest-v1"}')

  e("INSERT INTO auth.users(id,email) VALUES($1,'149a@example.invalid') ON CONFLICT(id) DO NOTHING", list(actor))
  e("INSERT INTO public.profiles(id,email,rolle,navn) VALUES($1,'149a@example.invalid','redaktion','Task 149a') ON CONFLICT(id) DO UPDATE SET rolle='redaktion'", list(actor))
  e("INSERT INTO public.source(id,titel,udgave,slags) VALUES($1,'Fixture','synthetic','DAA-udgave') ON CONFLICT(id) DO NOTHING", list(source_id))
  profile_sha <- q("SELECT private.reimport_canonical_json_sha256($1::jsonb) h", list(writer_config))$h[[1L]]
  e("INSERT INTO private.reimport_writer_profile(source_id,profile_id,profile_version,profile_sha256,writer_config) VALUES($1,$2,'source-evidence-v1',$3,$4::jsonb) ON CONFLICT(source_id,profile_id,profile_sha256) DO NOTHING",
    list(source_id, profile_id, profile_sha, writer_config))
  e("SELECT set_config('request.jwt.claim.sub',$1,false)", list(actor))

  rendition_sha <- sha("c")
  operation <- function(key, char_from, char_to, page_from, page_to, text) list(
    element_id = paste0("source-evidence:", key), dependency_class = "source_evidence",
    source_record_key = key, source_id = source_id, category = "person_post",
    disposition = "retain_source_only", rendition_content_sha256 = rendition_sha,
    source_span = list(char_from = char_from, char_to = char_to),
    page_evidence = list(page_from = page_from, page_to = page_to),
    verbatim_text = text,
    verbatim_sha256 = digest::digest(text, algo = "sha256", serialize = FALSE),
    anchor_method = "deterministic-segment", segment_version = "segment.py@fixture-v1")
  manifest <- list(
    manifest_content_sha256 = sha("9"),
    source = list(id = source_id, profile_id = profile_id, profile_sha256 = profile_sha),
    expected_counts = list(source_evidence = 2L, person_creates = 0L, canonical_delta = 0L),
    operations = list(
      operation("F-1", 0L, 10L, 10L, 10L, "Alfa Bravo"),
      operation("F-2a", 20L, 33L, 10L, 11L, "Charlie Delta")))
  validate_reimport_manifest(manifest)
  preview_sha <- sha("8")

  aggregate_hash <- function(sql) as.character(q(sprintf(paste(
    "SELECT coalesce(encode(sha256(convert_to(string_agg(row_text, chr(10) ORDER BY row_text),",
    "'UTF8')),'hex'),'empty') AS h FROM (%s) s"), sql))$h[[1L]])
  canonical_state <- function() list(
    person = aggregate_hash("SELECT p::text AS row_text FROM public.person p"),
    fact = aggregate_hash("SELECT f::text AS row_text FROM public.fact f"),
    family_member = aggregate_hash("SELECT m::text AS row_text FROM public.family_member m"),
    narrative = aggregate_hash("SELECT n::text AS row_text FROM public.narrative n"),
    narrative_record_publication = aggregate_hash(
      "SELECT b::text AS row_text FROM private.narrative_record_publication b"))
  anon_state <- function() {
    dbBegin(con); e("SET LOCAL ROLE anon")
    state <- list(
      person = aggregate_hash("SELECT p::text AS row_text FROM public.person p"),
      person_external_id = aggregate_hash("SELECT x::text AS row_text FROM public.person_external_id x"),
      narrative = aggregate_hash("SELECT n::text AS row_text FROM public.narrative n"),
      fact = aggregate_hash("SELECT f::text AS row_text FROM public.fact f"),
      citation = aggregate_hash("SELECT c::text AS row_text FROM public.citation c"),
      conclusion = aggregate_hash("SELECT c::text AS row_text FROM public.conclusion c"),
      assertion = aggregate_hash("SELECT a::text AS row_text FROM public.assertion a"),
      family_member = aggregate_hash("SELECT m::text AS row_text FROM public.family_member m"))
    dbRollback(con); state
  }

  canonical_before <- canonical_state(); anon_before <- anon_state()
  env_gateway <- function() new_reimport_dbi_gateway(connect)
  Sys.setenv(DAA_REIMPORT_ACTOR_ID = actor)

  dry <- execute_reimport(manifest, preview_sha, "dry-run", env_gateway())
  stopifnot(identical(dry$status, "finalized"), isFALSE(dry$committed))
  stopifnot(q("SELECT count(*) n FROM private.source_record WHERE source_id=$1", list(source_id))$n[[1L]] == 0L)

  database_identity <- q("SELECT jsonb_build_object('database_name',current_database(),'system_identifier',(pg_control_system()).system_identifier::text)::text i")$i[[1L]]
  authorization_id <- q(paste("SELECT public.red_authorize_reimport($1,$2,$3,$4,$5,$6,$7::jsonb,$8::jsonb,",
    "gen_random_uuid(),clock_timestamp()+interval '10 minutes') AS id"),
    list(manifest$manifest_content_sha256, preview_sha, database_identity, source_id,
      profile_id, profile_sha,
      jsonlite::toJSON(reimport_writer_expected_counts(manifest), auto_unbox = TRUE),
      jsonlite::toJSON(reimport_authorized_payloads(manifest), auto_unbox = TRUE, null = "null")))$id[[1L]]

  applied <- execute_reimport(manifest, preview_sha, "apply", env_gateway(),
    list(id = authorization_id))
  stopifnot(identical(applied$status, "finalized"), isTRUE(applied$committed))

  counts <- q(paste(
    "SELECT (SELECT count(*) FROM private.source_rendition WHERE source_id=$1) AS renditions,",
    "(SELECT count(*) FROM private.source_record WHERE source_id=$1) AS records,",
    "(SELECT count(*) FROM private.source_record_occurrence o JOIN private.source_rendition r",
    " ON r.id=o.rendition_id WHERE r.source_id=$1) AS occurrences,",
    "(SELECT count(*) FROM private.source_record_anchor_event a JOIN private.source_record sr",
    " ON sr.id=a.source_record_id WHERE sr.source_id=$1 AND a.decision_status='accepted') AS anchors"),
    list(source_id))
  stopifnot(counts$renditions[[1L]] == 1L, counts$records[[1L]] == 2L,
            counts$occurrences[[1L]] == 2L, counts$anchors[[1L]] == 2L)
  stopifnot(q("SELECT count(*) n FROM private.source_record WHERE source_id=$1 AND record_kind<>'person_post'", list(source_id))$n[[1L]] == 0L)
  stopifnot(identical(canonical_state(), canonical_before))
  stopifnot(identical(anon_state(), anon_before))
  stopifnot(q("SELECT count(*) n FROM private.reimport_authorization WHERE source_id=$1 AND profile_id=$2 AND operation='name_completion'", list(source_id, profile_id))$n[[1L]] == 0L)

  replay_authorization <- q(paste("SELECT public.red_authorize_reimport($1,$2,$3,$4,$5,$6,$7::jsonb,$8::jsonb,",
    "gen_random_uuid(),clock_timestamp()+interval '10 minutes') AS id"),
    list(manifest$manifest_content_sha256, preview_sha, database_identity, source_id,
      profile_id, profile_sha,
      jsonlite::toJSON(reimport_writer_expected_counts(manifest), auto_unbox = TRUE),
      jsonlite::toJSON(reimport_authorized_payloads(manifest), auto_unbox = TRUE, null = "null")))$id[[1L]]
  replayed <- execute_reimport(manifest, preview_sha, "apply", env_gateway(),
    list(id = replay_authorization))
  stopifnot(identical(replayed$status, "already_applied"))
  stopifnot(identical(canonical_state(), canonical_before))

  batch_id <- q("SELECT id FROM private.reimport_batch WHERE source_id=$1 AND profile_id=$2 AND status='finalized' ORDER BY finalized_at DESC LIMIT 1",
    list(source_id, profile_id))$id[[1L]]
  reversal_authorization <- q("SELECT public.red_authorize_reimport_reversal($1,gen_random_uuid(),clock_timestamp()+interval '5 minutes') AS id",
    list(batch_id))$id[[1L]]
  reversal <- try(q("SELECT public.red_reverse_reimport($1,$2)",
    list(batch_id, reversal_authorization)), silent = TRUE)
  stopifnot(inherits(reversal, "try-error"),
    grepl("REIMPORT_WRITER_REVERSAL_INVALID", as.character(reversal), fixed = TRUE))
  stopifnot(identical(canonical_state(), canonical_before))

  cat("PASS source_evidence reimport integration\n")
  ```

  Bemærk: reversal-assertionen er bevidst **fail-closed-bevis**, ikke et
  gendannelsesbevis, jf. dokumenteret afvigelse 4.

- [ ] **Step 2: Kør den fejlende test**

  ```bash
  Rscript tests/integration/test-reimport-source-evidence.R
  ```

  Forventet: FEJL — `cannot open file '.../tests/integration/test-reimport-source-evidence.R'`
  før filen findes; efter oprettelse men uden en v2-base fejler den med
  `REIMPORT_NARRATIVE_RECORD_CONTRACT_REQUIRED` fra første RPC-kald.

- [ ] **Step 3: Klargør en disponerbar v2-base og kør grønt**

  ```bash
  /opt/homebrew/opt/postgresql@17/bin/createdb daa149a_synthetic_20260903
  for f in tests/sql/evidence-promotion-bootstrap.sql schema.sql db-rls.sql \
           tests/sql/1939-v50-writer-bootstrap.sql; do
    PGDATABASE=daa149a_synthetic_20260903 \
      /opt/homebrew/opt/postgresql@17/bin/psql -X -v ON_ERROR_STOP=1 -f "$f"
  done
  PGDATABASE=daa149a_synthetic_20260903 \
    /opt/homebrew/opt/postgresql@17/bin/psql -X -v ON_ERROR_STOP=1 \
    -c 'BEGIN' -f tests/sql/reimport-writer-v2-bootstrap.sql -c 'COMMIT'
  PGDATABASE=daa149a_synthetic_20260903 \
    /opt/homebrew/opt/postgresql@17/bin/psql -X -v ON_ERROR_STOP=1 -f db-rls.sql
  PGHOST=127.0.0.1 PGPORT=5432 PGDATABASE=daa149a_synthetic_20260903 \
  PGUSER="$(id -un)" PGPASSWORD='' \
    Rscript tests/integration/test-reimport-source-evidence.R
  ```

  Forventet: `PASS source_evidence reimport integration`.

- [ ] **Step 4: Skriv den manuelle runbook**

  Opret `docs/runbooks/source-evidence-reimport-rehearsal.md` med præcis disse
  seks sektioner. Dump-stien er altid `--dump`/`$DUMP_PATH`, aldrig hardkodet.

  1. **Adgangskrav og stopport.** Ingen prod-forbindelse. Alle fem `PG*` sættes
     sammen mod den disponerbare profil. Basenavn:
     `daa149a_<formål>_<dato>` (fx `daa149a_rehearsal_20260903`). `umask 077`,
     backup mode 0600 og dens SHA-256 noteres.
  2. **Restore.** Genbrug §2 i `docs/runbooks/narrative-record-key-cutover.md`:
     ```bash
     set -euo pipefail
     umask 077
     REHEARSAL_DATABASE="daa149a_rehearsal_$(date +%Y%m%d%H%M%S)"
     /opt/homebrew/opt/postgresql@17/bin/createdb \
       --host="$PGHOST" --port="$PGPORT" --username="$PGUSER" "$REHEARSAL_DATABASE"
     PGDATABASE="$REHEARSAL_DATABASE" /opt/homebrew/opt/postgresql@17/bin/pg_restore \
       --clean --if-exists --no-owner --dbname="$REHEARSAL_DATABASE" "$DUMP_PATH"
     PGDATABASE="$REHEARSAL_DATABASE" /opt/homebrew/opt/postgresql@17/bin/psql \
       -X -v ON_ERROR_STOP=1 -Atc \
       "SELECT current_database(), (pg_control_system()).system_identifier, public.narrative_record_contract_version()"
     ```
     Fortsæt kun ved kontraktversion `1`.
  3. **Migrér til kontrakt v2.** Brug den rigtige #152-vej, ikke den syntetiske
     fixture: `tests/sql/reimport-writer-v2-bootstrap.sql` fail-closer med
     `CUTOVER_INVENTORY_LIVE_DRIFT` på en base med rigtige narrativer
     (`.github/workflows/ci.yml`, trinnet »Reimport writer migration from
     pre-153 ledger«). Kør i stedet, mod rehearsal-basen, sekvensen fra
     `docs/runbooks/narrative-record-key-cutover.md` §3-§5 og
     `docs/evidensbaseret-genimport/narrative-record-key-152-rehearsal.md`:
     `export_narrative_record_cutover.R --output-dir`, derefter
     `build_narrative_record_cutover_review.py`, en navngiven lokal reviewers
     beslutningsfil, `convert_narrative_record_cutover_approvals.py`, og til
     sidst `apply_narrative_record_cutover.R --mode preflight` (forventet
     `preflight_rolled_back`) efterfulgt af `--mode apply`. Assertér
     `narrative_record_contract_version() = 2`.
  4. **Indsæt writer-profilen.** Én `INSERT` i
     `private.reimport_writer_profile` med `source_id`, `profile_id`,
     `profile_version` og `writer_config` fra profil-JSON'en; `profile_sha256`
     beregnes af `private.reimport_canonical_json_sha256(writer_config)`.
     Assertér at værdien er identisk med `reimport_profile.py --profile`'s
     output. Tabellen er append-only (`schema.sql:2533`), så en fejlagtig
     profil kræver en ny `profile_id`.
  5. **Byg, preview, autorisér, kør.**
     ```bash
     python3 .claude/skills/daa-extract/scripts/build_source_evidence_rendition.py \
       --profile .claude/skills/daa-extract/references/reimport-profiles/daa-2018-20-source-evidence-v1.json \
       --pdf "$PDF_PATH" --output-dir "$ARTIFACT_DIR/rendition"
     python3 .claude/skills/daa-extract/scripts/build_source_evidence_manifest.py \
       --profile .claude/skills/daa-extract/references/reimport-profiles/daa-2018-20-source-evidence-v1.json \
       --rendition-text "$ARTIFACT_DIR/rendition/rendition.txt" \
       --posts "$ARTIFACT_DIR/rendition/posts.json" \
       --output "$ARTIFACT_DIR/source-evidence-manifest-v1.json"
     MANIFEST_BYTES_SHA="$(shasum -a 256 "$ARTIFACT_DIR/source-evidence-manifest-v1.json" | cut -d' ' -f1)"
     Rscript .claude/skills/daa-extract/scripts/export_reimport_preview.R \
       --profile .claude/skills/daa-extract/references/reimport-profiles/daa-2018-20-source-evidence-v1.json \
       --manifest "$ARTIFACT_DIR/source-evidence-manifest-v1.json" \
       --manifest-sha256 "$MANIFEST_BYTES_SHA" \
       --output "$ARTIFACT_DIR/source-evidence-preview-v1.json"
     PREVIEW_SHA="$(shasum -a 256 "$ARTIFACT_DIR/source-evidence-preview-v1.json" | cut -d' ' -f1)"
     Rscript .claude/skills/daa-extract/scripts/apply_reimport.R \
       --manifest "$ARTIFACT_DIR/source-evidence-manifest-v1.json" \
       --manifest-sha256 "$MANIFEST_BYTES_SHA" \
       --preview-sha256 "$PREVIEW_SHA" --dry-run
     ```
     Autorisationen udstedes derefter i én psql-transaktion af den rolle, der
     har EXECUTE på `public.red_authorize_reimport` (`service_role`;
     `schema.sql:3179`), med `request.jwt.claim.sub` sat til den samme
     `redaktion`-aktør, som skal køre apply (`schema.sql:2710` kræver
     `principal_id = auth.uid()`). `p_expected_counts` og
     `p_authorized_elements` tages ordret fra preview-artefaktets
     `expected_counts` og manifestets operationer minus `element_id`/
     `dependency_class`. Til sidst:
     ```bash
     DAA_REIMPORT_ACTOR_ID="$ACTOR_UUID" \
     Rscript .claude/skills/daa-extract/scripts/apply_reimport.R \
       --manifest "$ARTIFACT_DIR/source-evidence-manifest-v1.json" \
       --manifest-sha256 "$MANIFEST_BYTES_SHA" \
       --preview-sha256 "$PREVIEW_SHA" --apply \
       --authorization "$ARTIFACT_DIR/authorization-v1.json"
     ```
  6. **Verifikation.** Assertér 1 rendition, 591 records, 591 occurrences, 591
     accepterede ankre; identisk aggregat-hash før/efter for `person`, `fact`,
     `family_member`, `narrative`, `private.narrative_record_publication`;
     identisk `SET LOCAL ROLE anon`-hash for `person`, `person_external_id`,
     `narrative`, `fact`, `assertion`, `conclusion`, `citation`,
     `family_member` samt `public.public_person_bio_source_versions_v2` for de
     berørte `person_id`'er; replay giver `already_applied`;
     `red_reverse_reimport` afvises med `REIMPORT_WRITER_REVERSAL_INVALID`.
     Gendannelse af evidenslaget bevises ved at droppe rehearsal-basen,
     restore igen fra `$DUMP_PATH` og assertere 0 renditions/records/
     occurrences/ankre for `source_id = 1`.

- [ ] **Step 5: Tilføj CI-trin**

  I `.github/workflows/ci.yml`, i jobbet `writer-1939-v50-db`, umiddelbart
  efter trinnet »Generic reimport writer source/profile locking«:

  ```yaml
      - name: Source evidence writer integration
        env:
          PGHOST: localhost
          PGPORT: 5432
          PGUSER: postgres
          PGPASSWORD: postgres
          PGDATABASE: writer_1939
        run: Rscript tests/integration/test-reimport-source-evidence.R
  ```

  I jobbet `evidence-contract`, efter det eksisterende pytest-trin:

  ```yaml
      - run: python3 -m pytest .claude/skills/daa-extract/scripts/test_reimport_profile.py .claude/skills/daa-extract/scripts/test_build_source_evidence_rendition.py .claude/skills/daa-extract/scripts/test_build_source_evidence_manifest.py -q
  ```

- [ ] **Step 6: Kør begge CI-kommandoer lokalt**

  ```bash
  python3 -m pytest .claude/skills/daa-extract/scripts/test_reimport_profile.py \
    .claude/skills/daa-extract/scripts/test_build_source_evidence_rendition.py \
    .claude/skills/daa-extract/scripts/test_build_source_evidence_manifest.py -q
  PGHOST=127.0.0.1 PGPORT=5432 PGDATABASE=daa149a_synthetic_20260903 \
  PGUSER="$(id -un)" PGPASSWORD='' \
    Rscript tests/integration/test-reimport-source-evidence.R
  ```

  Forventet: `40 passed` og `PASS source_evidence reimport integration`.

- [ ] **Step 7: Commit**

  ```bash
  git add tests/integration/test-reimport-source-evidence.R \
          docs/runbooks/source-evidence-reimport-rehearsal.md \
          .github/workflows/ci.yml
  git commit -m "test(genimport): rehearsal og CI-gate for source_evidence-writeren"
  ```

---

### Task 6: Rapport, fase-pakke-bidrag og editionsnavne-gate

**Files:**

- Create: `docs/evidensbaseret-genimport/source-evidence-149a-rehearsal.md`
- Create: `docs/evidensbaseret-genimport/source-evidence-149a-phase-package-contribution.md`
- Modify: `db-verify.sql`
- Modify: `tests/sql/test-reimport-edition-catalog.sql`
- Modify: `docs/evidensbaseret-genimport/status.md`
- Modify: `docs/changelog.md`
- Modify: `docs/decisions.md`

**Interfaces:**

- Consumes: `private.assert_reimport_edition_catalog()` (`db-verify.sql:561-707`),
  hvis `actual`-side i dag kun scanner `%\_1939%` (`db-verify.sql:627, 641, 649,
  659, 675, 684`); rehearsal-resultaterne fra Task 5; modenhedsskalaen i
  `docs/evidensbaseret-genimport/status.md:36-37`.
- Produces: en rapport med tal og hashes uden persondata, et fase-pakke-bidrag
  med kvittering, en udvidet editionskatalog-gate, og en modenhedsopdatering
  til `integreret ende-til-ende` (ikke `produktionsverificeret`).

- [ ] **Step 1: Skriv den fejlende katalog-gate-test**

  I `tests/sql/test-reimport-edition-catalog.sql`, umiddelbart før den
  afsluttende `SELECT private.assert_reimport_edition_catalog(); ROLLBACK;`:

  ```sql
  SAVEPOINT task149a_extra_2018_relation;
  CREATE TABLE private.task149a_extra_relation_2018(id bigint);
  SELECT pg_temp.task6_expect_catalog_drift('RELATION_2018');
  ROLLBACK TO SAVEPOINT task149a_extra_2018_relation;
  SELECT private.assert_reimport_edition_catalog();

  SAVEPOINT task149a_extra_2018_function;
  CREATE FUNCTION private.task149a_extra_function_2018()
  RETURNS void LANGUAGE sql AS 'SELECT NULL::void';
  SELECT pg_temp.task6_expect_catalog_drift('FUNCTION_2018');
  ROLLBACK TO SAVEPOINT task149a_extra_2018_function;
  SELECT private.assert_reimport_edition_catalog();
  ```

- [ ] **Step 2: Kør den fejlende test**

  ```bash
  /opt/homebrew/opt/postgresql@17/bin/createdb daa149a_gate_20260903
  for f in tests/sql/evidence-promotion-bootstrap.sql schema.sql db-migrations.sql \
           db-rls.sql db-verify.sql; do
    PGDATABASE=daa149a_gate_20260903 \
      /opt/homebrew/opt/postgresql@17/bin/psql -X -v ON_ERROR_STOP=1 -f "$f"
  done
  PGDATABASE=daa149a_gate_20260903 \
    /opt/homebrew/opt/postgresql@17/bin/psql -X -v ON_ERROR_STOP=1 \
    -f tests/sql/test-reimport-edition-catalog.sql
  ```

  Forventet: FEJL — `REIMPORT_EDITION_CATALOG_RELATION_2018_NOT_REJECTED`,
  fordi `actual` i dag kun scanner `%\_1939%`.

- [ ] **Step 3: Udvid katalog-gaten**

  I `db-verify.sql`, i `actual`-CTE'en i
  `private.assert_reimport_edition_catalog()`, udvid hver af de seks
  `LIKE '%\_1939%' ESCAPE E'\\'`-prædikater til også at ramme `_2018`. Ret
  eksempelvis relations-grenen (`db-verify.sql:627`) fra:

  ```sql
        AND c.relname LIKE '%\_1939%' ESCAPE E'\\'
  ```

  til:

  ```sql
        AND (c.relname LIKE '%\_1939%' ESCAPE E'\\'
             OR c.relname LIKE '%\_2018%' ESCAPE E'\\')
  ```

  Gør det tilsvarende for `t.typname` (`:641`), `p.proname` (`:649`),
  `t.tgname` (`:659`), `constraint_row.conname` (`:675`) og `p.polname`
  (`:684`). `expected`-listen udvides **ikke**: 149a har en tom `_2018`-
  allowlist, så ethvert permanent `_2018`-objekt bliver drift. Opdatér
  kommentaren over funktionen (`db-verify.sql:558-560`) til: »`_1939` er et
  lukket kompatibilitets-navnerum, og `_2018` er en tom allowlist: #149a's
  udgave bor i én profil-JSON, ikke i katalogen.«

- [ ] **Step 4: Kør gaten grøn**

  ```bash
  /opt/homebrew/opt/postgresql@17/bin/dropdb --if-exists daa149a_gate_20260903
  /opt/homebrew/opt/postgresql@17/bin/createdb daa149a_gate_20260903
  for f in tests/sql/evidence-promotion-bootstrap.sql schema.sql db-migrations.sql \
           db-rls.sql db-verify.sql; do
    PGDATABASE=daa149a_gate_20260903 \
      /opt/homebrew/opt/postgresql@17/bin/psql -X -v ON_ERROR_STOP=1 -f "$f"
  done
  PGDATABASE=daa149a_gate_20260903 \
    /opt/homebrew/opt/postgresql@17/bin/psql -X -v ON_ERROR_STOP=1 \
    -f tests/sql/test-reimport-edition-catalog.sql
  PGDATABASE=daa149a_gate_20260903 \
    /opt/homebrew/opt/postgresql@17/bin/psql -X -v ON_ERROR_STOP=1 \
    -f tests/sql/run-db-verify-disposable.sql
  ```

  Forventet: begge scripts afsluttes med exit 0 uden
  `REIMPORT_EDITION_OBJECT_ALLOWLIST_DRIFT`.

- [ ] **Step 5: Skriv rehearsal-rapporten**

  Opret `docs/evidensbaseret-genimport/source-evidence-149a-rehearsal.md` med
  præcis disse afsnit og intet persondata (§7: kun `record_key`, tal og hashes):

  - **Overskrift og afgrænsning.** »Dette er afgrænset, lokalt disponerbart
    bevis, ikke en produktionsautorisation. Ingen produktionsdatabase, push,
    merge, deploy eller netværkshandling er brugt, og ingen `work/`-sti er
    tilgået.«
  - **Basetabel.** Kolonner: base (`daa149a_*`), formål, opsætning,
    kontraktversion før/efter, exit.
  - **Låste inputhashes.** `pdf_sha256`, `raw_text_sha256`,
    `profile_sha256`, `segment_digest_sha256`, `manifest_content_sha256`,
    `manifest_bytes_sha256`, `preview_sha256`.
  - **Tal.** Renditions 1, source records 591, occurrences 591, accepterede
    ankre 591, `person_creates` 0, `canonical_delta` 0. Strukturelle blokke
    tælles og rapporteres, men skrives ikke (spec §4).
  - **Nul kanonisk delta.** Aggregat-hash før og efter for `person`, `fact`,
    `family_member`, `narrative`, `private.narrative_record_publication` — i
    to kolonner, identiske.
  - **Synlighed.** `SET LOCAL ROLE anon`-hash før og efter for de otte
    anon-læselige tabeller plus
    `public.public_person_bio_source_versions_v2`.
  - **Replay og reversal.** `already_applied`; `red_reverse_reimport` afvist
    med `REIMPORT_WRITER_REVERSAL_INVALID`; gendannelse bevist ved ny restore.
  - **De fire dokumenterede afvigelser** ordret fra denne plans afsnit
    »Dokumenterede afvigelser fra spec-teksten«, med fil:linje.
  - **Restpunkter.** `docs/runbooks/evidence-import-phase-gate.md` findes ikke
    i repoet; receipt-skemaerne `daa-evidence-phase-receipt-*-v1` er kun nævnt
    i `docs/decisions.md:38`. Fase-pakke-gaten kan derfor ikke lukkes af 149a
    alene.

- [ ] **Step 6: Skriv fase-pakke-bidraget**

  Opret
  `docs/evidensbaseret-genimport/source-evidence-149a-phase-package-contribution.md`
  som ét bidrag med kvittering, jf. spec §6 (»Manifestet registreres i #156's
  ledger som bidrag med receipt«) og `docs/decisions.md:37-44`:

  - `contribution_id`: `source-evidence-149a`
  - `state`: `afterdocumented` (samme tilstand som #156's adaptervej)
  - `source`: `{id: 1, profile_id: "daa-2018-20-source-evidence-v1", profile_sha256: <hash>}`
  - `manifest`: `{manifest_content_sha256, manifest_bytes_sha256}`
  - `preview`: `{preview_sha256}`
  - `expected_counts`: `{person_creates: 0, source_evidence: 591}`
  - `observed_counts`: `{person_creates: 0, source_evidence: 591}`
  - `batch`: `{batch_id, status: "finalized", database_name, system_identifier}`
  - `backup`: `{sha256, mode: "0600"}`
  - `canonical_delta`: `{rows_changed: 0, aggregate_hashes_identical: true}`
  - `replay`: `already_applied`
  - `reversal`: `{available: false, observed_code: "REIMPORT_WRITER_REVERSAL_INVALID", restore_proof: true}`
  - `production_authorized`: `false`, `apply_gate`: `"NO-GO"`
  - Eksplicit restpunkt: den manglende
    `docs/runbooks/evidence-import-phase-gate.md` og de udefinerede
    receipt-skemaer skal leveres af #156, før gaten kan lukkes.

- [ ] **Step 7: Opdatér status, changelog og beslutninger**

  I `docs/evidensbaseret-genimport/status.md`, i tabellen »Modenhed pr.
  værdikædeled«, erstat rækken:

  ```
  | 2018-20-proveniens | `specificeret` | Fase A-ækvivalent provenance er besluttet, men ikke gennemført. |
  ```

  med:

  ```
  | 2018-20-proveniens | `integreret ende-til-ende` | 149a's kilderegnskab — 1 rendition, 591 source records, 591 forekomster og 591 accepterede ankre — er bevist gennem #153's generelle writer mod en engangs-restore af prod-dumpet med nul kanonisk delta, uændret `anon`-synlighed og `already_applied` ved replay. Reversal er ikke tilgængelig for en ren `source_evidence`-batch; gendannelse er bevist ved restore. Ingen produktions-apply og intet produktions-GO. Bindinger er 149b. |
  ```

  I `docs/changelog.md`, øverst i den dateret afsnitsrække, tilføj et afsnit
  under 2026-09-03 med: de låste inputhashes, tallene 1/591/591/591, nul
  kanonisk delta, de fire dokumenterede afvigelser, den udvidede
  editionskatalog-gate, og at prod er en separat GO.

  I `docs/decisions.md`, tilføj efter afsnittet »#149 opdelt i 149a og 149b«:

  ```
  **149a: reversal er ikke tilgængelig for en ren source_evidence-batch.**
  `public.red_reverse_reimport` kræver `status='activated'` og præcis ét
  afsluttet `name_completion`-barnebatch (schema.sql:3093-3127), og der findes
  ingen sletningsvej for `source_record`/`source_record_occurrence`/
  `source_record_anchor_event`. Spec §1 række 5's reversal-krav opfyldes derfor
  som (a) nul kanonisk delta målt ved identisk aggregat-hash, (b) observeret
  fail-closed `REIMPORT_WRITER_REVERSAL_INVALID`, og (c) gendannelse bevist ved
  restore fra 0600-backup. Ændringen er en spec §10-ændring og kræver
  projektejerens kvittering før prod-GO.

  **149a: preview_sha256 bindes til preview-artefaktets filbytes.**
  Konsekvensen er, at batchen aldrig kan kædes til
  `public.red_authorize_reimport_name_completion`, som kræver
  `preview_sha256 = kildemanifestets filbytes-SHA` (schema.sql:2996). 149a har
  0 `person_creates` og skal ikke kædes; 149b skal vælge bindingen bevidst.
  ```

- [ ] **Step 8: Kør den fulde lokale gate**

  ```bash
  python3 -m pytest .claude/skills/daa-extract/scripts/test_reimport_profile.py \
    .claude/skills/daa-extract/scripts/test_build_source_evidence_rendition.py \
    .claude/skills/daa-extract/scripts/test_build_source_evidence_manifest.py -q
  Rscript run-tests.R
  PGDATABASE=daa149a_gate_20260903 \
    /opt/homebrew/opt/postgresql@17/bin/psql -X -v ON_ERROR_STOP=1 \
    -f tests/sql/test-reimport-edition-catalog.sql
  git status --short && git diff --check
  ```

  Forventet: pytest PASS, R-suiten PASS, SQL-gaten exit 0, ren worktree bortset
  fra de tilsigtede filer.

- [ ] **Step 9: Commit**

  ```bash
  git add docs/evidensbaseret-genimport/source-evidence-149a-rehearsal.md \
          docs/evidensbaseret-genimport/source-evidence-149a-phase-package-contribution.md \
          docs/evidensbaseret-genimport/status.md \
          docs/changelog.md docs/decisions.md \
          db-verify.sql tests/sql/test-reimport-edition-catalog.sql
  git commit -m "docs(genimport): rehearsal-rapport, fase-pakke-bidrag og tom 2018-allowlist i editionskataloget"
  ```

---

## Selv-review

### Spec-dækning pr. paragraf

| § | Krav | Dækket af | Bemærkning |
| --- | --- | --- | --- |
| §2 I scope | Én rendition | Task 2 (SHA-låst pdftotext), Task 3 (`rendition_content_sha256` pr. element), writeren afleder `rendition_key`/`kind`/`metadata` af profilen | — |
| §2 I scope | 591 personposter som source records | Task 2 paritetsgate (591 `lokal_id`), Task 3 `expected_counts`-gate, Task 5 assertion `records = 591` | — |
| §2 I scope | Én forekomst og ét accepteret anker pr. post | Writeren skriver begge pr. element (`schema.sql:2639-2640`); Task 5 asserterer 591/591 | — |
| §2 I scope | Ét hash-låst manifest gennem den generelle writer | Task 3 `manifest_content_sha256`, Task 4 preview-binding, Task 5 gateway-kørsel | — |
| §2 I scope | Fase-pakke-gate | Task 6 bidrag + kvittering | Restpunkt: runbooken findes ikke |
| §2 Ikke i scope | Ingen bindinger, identitet, tekstændringer, strukturelle records, klausuler, fortolkning, placement, personoprettelse, modelkald | `expected_counts.person_creates = 0` håndhæves i profilindlæser (Task 1), manifest-bygger (Task 3), preview (Task 4) og af `red_finalize_reimport`; ingen kode kalder en model | Strukturelle blokke tælles kun i rapporten |
| §3 | PDF identificeres ved SHA-256 | Task 1 `pdf_sha256` (låst), Task 2 `SOURCE_EVIDENCE_PDF_SHA_MISMATCH` | — |
| §3 | `pdftotext -layout` med `### PAGE n ###` | Task 1 `pdftotext_args.page_marker`, Task 2 kalder `extract_text.sh` | — |
| §3 | Output-SHA låses; afvigelse dokumenteres | Task 1 `raw_text_sha256`, Task 2 `SOURCE_EVIDENCE_RENDITION_SHA_MISMATCH`, Task 6 rapportafsnit | — |
| §3 | Én `source_rendition` med `rendition_key`, `rendition_kind`, `content_sha256`, metadata | Profilens `writer_config`; writeren skriver rækken; Task 5 asserterer 1 | — |
| §4 | Segmentering deterministisk, 591 poster identiske med baseline | Task 2 `segment_parity` | Afvigelse 3: paritet på `lokal_id`-mængde |
| §4 | `record_key` som prod bruger | Task 3 `record_key_of` = `load_helpers.R:153`; Task 4 preview rapporterer mængdeforskellen som mængder, ikke antal | — |
| §4 | `record_kind = 'person_post'` | Task 3 `category = "person_post"`; Task 5 asserterer | Sætter samtidig `observation_kind` og `mention_kind` |
| §4 | Eksakt delstreng, `char_from`/`char_to`, `page_from`/`page_to` | Task 3 `project_rendition`, `pages_from_sider` | Afvigelse 1 |
| §4 | Anker `accepted` med evidens | Writeren; Task 3 bærer `anchor_method`, `segment_version`, `verbatim_sha256` | Afvigelse 2 |
| §6 | Manifest, `expected_counts = {person_creates: 0, source_evidence: 591}` | Task 3 | — |
| §6 | Writer-profil med #153's lukkede feltmængde | Task 1 `_validate_writer_config` | — |
| §6 | Kontrakt v2 før rehearsal | Task 4 `PREVIEW_NARRATIVE_RECORD_CONTRACT_REQUIRED`, Task 5 runbook §3 | — |
| §6 | Prod-rækkefølge #152 → #153 → 149a | Task 6 rapport + status; ingen prod-trin | — |
| §6 | Gate: backup 0600+SHA, restore, hash-låst manifest, ét apply, replay, reversal | Task 5 runbook §1-§6, Task 6 bidrag | Afvigelse 4 |
| §7 | Ingen modelkald | Ingen kode i planen kalder en model | — |
| §7 | Ingen navne/narrativtekst i fixtures og rapporter | Task 2 læser kun `linje`/`nr_label`; Task 2/3 tester eksplicit for fravær; Task 6's rapportafsnit er tal+hashes | `verbatim_text` er bogtekst i manifestet, ikke i rapporten |
| §9 | Python-tests: delstreng, sideafledning, injektivitetsbrud, tekstafvigelse, determinisme | Task 3, 15 tests | Stopgrænse (>10 % `unresolved`) hører til 149b §5 og er ikke i 149a |
| §9 | R-tests: dry-run/apply, eksakte antal, nul kanonisk delta, replay, reversal | Task 5 | — |
| §9 | Synlighed: `SET LOCAL ROLE anon` før og efter | Task 5 `anon_state()` | — |

### Pladsholder-scan

`<UDFYLDES FRA INVENTERING>` forekommer i planen **kun** inde i profil-JSON-
blokken i Task 1 Step 4, ved præcis de seks felter, der først kan måles af
inventeringen: `writer_config.rendition_metadata.pdf_sha256`,
`writer_config.rendition_metadata.pdftotext_version`, `pdf_sha256`,
`raw_text_sha256`, `pdftotext_args.first_page` og `pdftotext_args.last_page`.
`reimport_profile.load_profile` afviser filen med `PROFILE_PLACEHOLDER_UNFILLED`,
så længe strengen står nogetsteds i profilen, og krydstjekker at
`rendition_metadata.pdf_sha256` er identisk med det øverste `pdf_sha256`
(`PROFILE_PDF_SHA256_MISMATCH`). Ingen andre pladsholderformer forekommer:
planen indeholder ingen `TBD`, ingen »tilføj fejlhåndtering«, ingen »som i Task
N«, og hver kodeblok er gengivet fuldt ud dér, hvor den skal skrives.

### Typekonsistens på tværs af tasks

| Værdi | Type | Producent | Forbruger | Kontrol |
| --- | --- | --- | --- | --- |
| `profile_sha256` | 64-tegns hex-streng | Task 1 `canonical_json_sha256` | Task 3 `manifest.source.profile_sha256`, Task 4 profilopslag, Task 5 `red_authorize_reimport` | `schema.sql:2389` CHECK; kendt vektor verificeret mod PostgreSQL 17 |
| `source_id` | Python `int` / JSON heltal / R `integer` / SQL `bigint` | Task 1 profil | Task 3 `manifest.source.id`, Task 4, Task 5 | `validate_reimport_manifest` kræver `is.integer` |
| `expected_counts` | Manifest: 3 heltalsnøgler; DB: 2 heltalsnøgler | Task 3 | `reimport_writer_expected_counts` skærer til 2 | `private.validate_reimport_authorization_payload` |
| `element_id` | `"source-evidence:" + record_key` | Task 3 | `authorized_elements`-nøgle, `occurrence_key` | Regex `^source-evidence:.+$` (`schema.sql:2599-2603`) |
| `record_key` | `linje + "-" + nr_label` | Task 3 `record_key_of` | `source_record.record_key`, Task 4 mængdesammenligning mod `person_external_id` | `load_helpers.R:153` |
| `lokal_id` | `linje + "." + nr_label` | Task 2 | Kun paritet mod baseline | `segment.py:146` |
| `char_from`/`char_to` | Python `int` ≥ 0 / SQL `integer`, `char_to > char_from` | Task 3 | `source_record_occurrence`, `source_observation` | `schema.sql:488-489`, `:2626` |
| `page_from`/`page_to` | Python `int` ≥ 1, `page_to ≥ page_from` | Task 3 `pages_from_sider` | Occurrence og observation | `schema.sql:485-486`, `:2627` |
| `verbatim_text` | Ikke-tom streng = `raw_text` | Task 2/3 | Occurrence, observation, mention; `physical_fingerprint = sha256(verbatim_text)` | Lig `verbatim_sha256` i Task 3; matcher 149b's `narrative_norm_v1`-sammenligning, fordi prod-narrativerne blev indlæst fra samme `raw_text` |
| `disposition` | Konstanten `"retain_source_only"` | Task 3 | `red_apply_reimport_source_evidence` | `schema.sql:2727` |
| `category` | Konstanten `"person_post"` | Task 3 | `record_kind`, `observation_kind`, `mention_kind` | `schema.sql:2635/2641/2642`; eneste kind-filter i skemaet er `observation_kind='header'` (`schema.sql:1738`), som er upåvirket |
| `manifest_content_sha256` | 64-tegns hex over kanonisk JSON af manifestet uden feltet selv | Task 3 | `red_authorize_reimport(p_manifest_sha256)`, `red_begin_reimport` | `apply_reimport.R` sender `manifest$manifest_content_sha256` |
| `manifest_bytes_sha256` | 64-tegns hex over manifestfilens bytes | Task 3 stdout | `apply_reimport.R --manifest-sha256`, Task 4 binding | `apply_reimport.R` `digest(raw)` |
| `preview_sha256` | 64-tegns hex over preview-filens bytes | Task 4 | `apply_reimport.R --preview-sha256`, `red_authorize_reimport(p_preview_sha256)` | Bevidst valg; udelukker `name_completion`-kædning (`schema.sql:2996`) |
| Payload-nøglemængde | 11 nøgler efter fjernelse af `element_id` og `dependency_class` | Task 3 | `authorized_elements->element_id` skal være jsonb-identisk med payload | `schema.sql:2622-2623`; Task 3's sidste test låser mængden |
