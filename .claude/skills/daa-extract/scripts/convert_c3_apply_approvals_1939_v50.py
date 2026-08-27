#!/usr/bin/env python3
"""Konvertér et byte-låst C3 apply-godkendelsesark til tekstfri afgørelses-JSON.

Vokabularet her (``UAFKLARET|GODKENDT``) er et ANDET, uafhængigt vokabular
end review-fasens ``convert_c3_decisions_1939_v50.py``
(``UAFKLARET/FORSKELLIGE/SAMME/TIL/INGEN_PUBLIKATION/REVISION``) — denne fil
må derfor ikke overloade eller genbruge den konverter direkte (planens
"genbrug"-instruktion, fund H6).

Den byte-låste sekvens (header + fem beslutningslinjer) er derimod IKKE
genimplementeret her: den kommer fra ``apply_approval_sheet`` i
``build_c3_html_review_1939_v50.py`` — den ENE autoritative kilde, som
BÅDE renderer og denne konverter kalder. At implementere rækkefølgen to
gange var den parkerede fejl fra C0-efterkørslen, der aldrig blev lukket.

Arket bærer ``text_bundle_sha256`` (en kanonisk hash over kun
kandidat-afledte felter for de fem ``assign``-sager), ikke et fuldt
manifest-hash (brief-rettelse "fund B1"). Denne konverter genberegner
selv den hash fra det manifest, den får forelagt, og afviser arket, hvis
værdien ikke stemmer.
"""

import hashlib
import importlib.util
import json
import os
import re
import sys
import tempfile
from pathlib import Path
from typing import Any, Dict, List, Optional


SCRIPT_DIR = Path(__file__).resolve().parent
RENDERER_PATH = SCRIPT_DIR / "build_c3_html_review_1939_v50.py"
SCHEMA_VERSION = "1939-v50-c3-apply-approvals-decisions-v1"
CLI_ERROR_RE = re.compile(r"^C3_APPLY_APPROVALS_[A-Z0-9_]+$")
TOKEN_STATUS = {"UAFKLARET": "unresolved", "GODKENDT": "approved"}

# Foreign tokens the imported renderer can raise while validating/building
# the manifest (its own C3_HTML_APPLY_* namespace) are remapped here so
# every SystemExit this module can ever raise matches CLI_ERROR_RE. This is
# the same "wrap the imported module's own tokens" pattern Task 3's
# finalizer uses for Task 1's C3_APPLY_OUTPUT_* tokens.
_RENDERER_TOKEN_MAP = {
    "C3_HTML_APPLY_MANIFEST_INVALID": "C3_APPLY_APPROVALS_MANIFEST_INVALID",
    "C3_HTML_APPLY_MANIFEST_HASH_MISMATCH":
        "C3_APPLY_APPROVALS_MANIFEST_HASH_MISMATCH",
    "C3_HTML_APPLY_COUNT_INVALID": "C3_APPLY_APPROVALS_MANIFEST_INVALID",
    "C3_HTML_APPLY_HASH_INVALID": "C3_APPLY_APPROVALS_MANIFEST_INVALID",
    "C3_HTML_APPLY_INTERNAL_ERROR": "C3_APPLY_APPROVALS_MANIFEST_INVALID",
}


def _import_renderer():
    spec = importlib.util.spec_from_file_location(
        "build_c3_html_review_1939_v50_for_apply_converter", RENDERER_PATH)
    module = importlib.util.module_from_spec(spec)
    if spec.loader is None:
        raise RuntimeError("missing loader")
    spec.loader.exec_module(module)
    return module


renderer = _import_renderer()


def fail(code: str) -> None:
    raise SystemExit(code)


def _remap_renderer_error(error: SystemExit) -> None:
    token = str(error)
    fail(_RENDERER_TOKEN_MAP.get(token, "C3_APPLY_APPROVALS_MANIFEST_INVALID"))


def _manifest_derived(manifest_doc: Dict[str, Any]) -> Any:
    """Genbrug renderer'ens ENE validering/udtræk/hash/ark-generator.

    Returnerer (assign_events, text_bundle_sha256, baseline_sheet_bytes,
    slots) — samme fire ting, renderer'en selv bruger til at bygge
    godkendelseskortene og arket. Fejler i renderer'ens eget
    ``C3_HTML_APPLY_*``-navnerum bliver oversat til dette scripts eget
    ``C3_APPLY_APPROVALS_*``-navnerum, så ingen fremmed token nogensinde
    forlader dette modul.
    """
    try:
        renderer._validate_apply_manifest(manifest_doc)
        assign_events = renderer._apply_assign_events(manifest_doc)
        text_bundle_sha256 = renderer.apply_text_bundle_sha256(assign_events)
        sheet_bytes, slots = renderer.apply_approval_sheet(
            text_bundle_sha256, assign_events)
    except SystemExit as error:
        _remap_renderer_error(error)
        raise AssertionError("unreachable")
    return assign_events, text_bundle_sha256, sheet_bytes, slots


def parse_approvals(approvals_text: str, manifest_doc: Dict[str, Any],
                    manifest_raw: bytes) -> Dict[str, Any]:
    """Validér og konvertér et byte-låst apply-godkendelsesark.

    Genererer den forventede baseline fra ``manifest_doc`` via den delte
    ``apply_approval_sheet``-funktion og sammenligner positionelt: header
    (to linjer) skal matche eksakt (linje 1 = skema, linje 2 = bundle-hash),
    og hver af de fem beslutningslinjer skal matche baseline'ens hale
    (``] approve:<element_id>``) eksakt — kun det firkantede tokens indhold
    må afvige. Duplikat-detektion sker over ALLE linjer, ikke kun den
    forventede position, så en linje flyttet til en forkert position også
    fanges (af den positionelle hale-kontrol, ikke duplikat-tælleren).
    """
    if not isinstance(approvals_text, str):
        fail("C3_APPLY_APPROVALS_TEXT_INVALID")
    if not isinstance(manifest_doc, dict):
        fail("C3_APPLY_APPROVALS_MANIFEST_INVALID")
    if not isinstance(manifest_raw, bytes):
        fail("C3_APPLY_APPROVALS_MANIFEST_INVALID")

    # `manifest_doc` and `manifest_raw` are two separate parameters because
    # every caller in this C3 apply chain (Task 3's finalizer, this
    # converter's own CLI) already holds both a decoded document and its
    # exact source bytes. A direct library caller (a future Task 5/6, per
    # this codebase's own import-sibling-function idiom) could pass a
    # `manifest_doc` that did NOT actually come from `manifest_raw` — this
    # binds them before anything downstream (the emitted
    # `manifest_raw_sha256`, which a later authorization gate will rely on)
    # can attest to a manifest that was never the one validated.
    reread_manifest_doc = _decode_manifest(manifest_raw)
    if (renderer.apply_manifest._canonical_bytes(reread_manifest_doc)
            != renderer.apply_manifest._canonical_bytes(manifest_doc)):
        fail("C3_APPLY_APPROVALS_MANIFEST_BINDING_MISMATCH")

    _assign_events, text_bundle_sha256, baseline_bytes, slots = (
        _manifest_derived(manifest_doc))

    try:
        baseline_text = baseline_bytes.decode("utf-8")
    except UnicodeDecodeError:
        fail("C3_APPLY_APPROVALS_INTERNAL_ERROR")

    actual_lines = approvals_text.splitlines(keepends=True)
    baseline_lines = baseline_text.splitlines(keepends=True)
    if len(actual_lines) < len(baseline_lines):
        fail("C3_APPLY_APPROVALS_LINE_MISSING")
    if len(actual_lines) > len(baseline_lines):
        fail("C3_APPLY_APPROVALS_LINE_UNEXPECTED")

    if actual_lines[0] != baseline_lines[0]:
        fail("C3_APPLY_APPROVALS_SCHEMA_MISMATCH")
    if actual_lines[1] != baseline_lines[1]:
        fail("C3_APPLY_APPROVALS_HASH_MISMATCH")

    for slot in slots:
        tail = "] approve:{}\n".format(slot["element_id"])
        occurrences = sum(
            1 for line in actual_lines
            if line.startswith("[") and line.endswith(tail))
        if occurrences > 1:
            fail("C3_APPLY_APPROVALS_DECISION_DUPLICATE")

    decisions: List[Dict[str, str]] = []
    for index, slot in enumerate(slots):
        line_index = 2 + index
        actual = actual_lines[line_index]
        tail = "] approve:{}\n".format(slot["element_id"])
        if not actual.startswith("["):
            fail("C3_APPLY_APPROVALS_TOKEN_INVALID")
        if not actual.endswith(tail):
            fail("C3_APPLY_APPROVALS_LINE_TAMPERED")
        token = actual[1:-len(tail)]
        if token not in TOKEN_STATUS:
            fail("C3_APPLY_APPROVALS_TOKEN_INVALID")
        decisions.append({
            "element_id": slot["element_id"],
            "status": TOKEN_STATUS[token],
        })

    approved = sum(
        1 for decision in decisions if decision["status"] == "approved")
    return {
        "schema_version": SCHEMA_VERSION,
        "approvals_raw_sha256": hashlib.sha256(
            approvals_text.encode("utf-8")).hexdigest(),
        "manifest_raw_sha256": hashlib.sha256(manifest_raw).hexdigest(),
        "manifest_canonical_content_sha256":
            manifest_doc["canonical_content_sha256"],
        "text_bundle_sha256": text_bundle_sha256,
        "decisions": decisions,
        "counts": {
            "decisions": len(decisions),
            "approved": approved,
            "unresolved": len(decisions) - approved,
        },
    }


def _arguments(argv: List[str]) -> Dict[str, str]:
    allowed = {"--approvals", "--manifest", "--output"}
    values: Dict[str, str] = {}
    position = 0
    while position < len(argv):
        option = argv[position]
        if (option not in allowed or option in values
                or position + 1 >= len(argv)
                or argv[position + 1].startswith("--")):
            fail("C3_APPLY_APPROVALS_ARGUMENTS_INVALID")
        values[option] = argv[position + 1]
        position += 2
    if set(values) != allowed:
        fail("C3_APPLY_APPROVALS_ARGUMENTS_INVALID")
    return values


def _read_input(path: str, failure_code: str) -> bytes:
    try:
        return Path(path).read_bytes()
    except OSError:
        fail(failure_code)
    raise AssertionError("unreachable")


def _decode_text(raw: bytes, failure_code: str) -> str:
    try:
        return raw.decode("utf-8")
    except UnicodeDecodeError:
        fail(failure_code)
    raise AssertionError("unreachable")


def _decode_manifest(raw: bytes) -> Dict[str, Any]:
    try:
        return renderer.apply_manifest._decode_document(
            raw, "C3_APPLY_APPROVALS_MANIFEST_INVALID")
    except SystemExit as error:
        _remap_renderer_error(error)
        raise AssertionError("unreachable")


def publish_output(output: Path, rendered: str) -> None:
    """Publisér med hard-link; destinationen kan aldrig overskrives."""
    temp_path: Optional[Path] = None
    descriptor: Optional[int] = None
    try:
        if os.path.lexists(str(output)):
            fail("C3_APPLY_APPROVALS_OUTPUT_EXISTS")
        descriptor, temporary = tempfile.mkstemp(
            prefix="." + output.name + ".", suffix=".tmp",
            dir=str(output.parent))
        temp_path = Path(temporary)
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            descriptor = None
            handle.write(rendered)
            handle.flush()
            os.fsync(handle.fileno())
        try:
            os.link(str(temp_path), str(output))
        except FileExistsError:
            fail("C3_APPLY_APPROVALS_OUTPUT_EXISTS")
        os.unlink(str(temp_path))
        temp_path = None
    except OSError:
        fail("C3_APPLY_APPROVALS_OUTPUT_WRITE_FAILED")
    finally:
        if descriptor is not None:
            try:
                os.close(descriptor)
            except OSError:
                pass
        if temp_path is not None:
            try:
                os.unlink(str(temp_path))
            except OSError:
                pass


def main(argv: Optional[List[str]] = None) -> int:
    values = _arguments(list(sys.argv[1:] if argv is None else argv))
    output = Path(values["--output"])
    if os.path.lexists(str(output)):
        fail("C3_APPLY_APPROVALS_OUTPUT_EXISTS")
    approvals_raw = _read_input(
        values["--approvals"], "C3_APPLY_APPROVALS_TEXT_INVALID")
    manifest_raw = _read_input(
        values["--manifest"], "C3_APPLY_APPROVALS_MANIFEST_INVALID")
    approvals_text = _decode_text(
        approvals_raw, "C3_APPLY_APPROVALS_TEXT_INVALID")
    manifest_doc = _decode_manifest(manifest_raw)
    result = parse_approvals(approvals_text, manifest_doc, manifest_raw)
    rendered = json.dumps(
        result, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    publish_output(output, rendered)
    counts = result["counts"]
    print("beslutninger={} godkendt={} uafklarede={}".format(
        counts["decisions"], counts["approved"], counts["unresolved"]))
    return 0


def _cli_status() -> int:
    try:
        return main()
    except SystemExit as error:
        token = str(error)
        if CLI_ERROR_RE.fullmatch(token) is None:
            token = "C3_APPLY_APPROVALS_INTERNAL_ERROR"
        print(token, file=sys.stderr)
        return 1
    except Exception:
        print("C3_APPLY_APPROVALS_INTERNAL_ERROR", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(_cli_status())
