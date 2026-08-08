# Grænsekontrol fase 1 — implementeringsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bygge en browserflade der viser hver skæring mellem accepterede kildespænd i DAA 1939, mærker de mistænkte, og lader redaktøren dømme dem — uden at ændre et eneste spænd.

**Architecture:** Et Python-lag beregner grænserne og deres signaler ud fra de forankrede spænd, den hash-låste Calamari-tekst, rå OCR og et klausul-regnskab udledt undervejs. Resultatet indlejres i én selvbærende HTML-fil sammen med et delt UI-modul og en ny controller. Fladen gemmer i browserens lokale lager og eksporterer JSON. Ingen kaldevej fører tilbage i evidenskæden i fase 1.

**Tech Stack:** Python 3 (stdlib + pytest), vanilla JavaScript i browseren (ingen byggetrin, ingen afhængigheder), vitest + jsdom til JS-tests.

**Spec:** `docs/superpowers/specs/2026-08-08-graensekontrol-efter-matchning-design.md`

## Global Constraints

- **Gengivelsesfilerne ændres aldrig.** `full_ocr_calamari_r6_clean.txt` og `raw.txt` er hash-låste kilder. Ingen kode i denne plan skriver til dem.
- **Fase 1 ændrer ingen spænd.** Ingen afløsning, intet skæringspunkt, ingen skrivning til evidenskæden. Dommene `graense_flyttet` og `hul_lagt_til_post` findes ikke i fase 1.
- **Fail-closed.** Ugyldigt input hæver `ValueError` med en dansk besked. Aldrig et stille fravalg.
- **Fejlbeskeder og UI-tekst er på dansk.** Kode-identifikatorer og feltnavne er på engelsk, som resten af `daa-extract`.
- **Arbejdsmapperne må ikke committes.** `work/`, `work_1939_stamtavle/` og `work_presens/` er gitignorerede og indeholder PII. Ingen `git add` af filer derfra, og ingen prosa fra dem i commit-beskeder.
- **Klausul-regnskabet sorterer; den negative tværgengivelses-kontrol porter.** Intet hul må kunne massebekræftes alene fordi regnskabet kalder det en overskrift.
- **Grænse-id indeholder et revisionsnummer.** En dom hører til én revision og genaktiveres aldrig ved id-lighed alene.
- **Testkommando:** `python3 -m pytest <fil> -q` fra `.claude/skills/daa-extract/scripts`. Systemets Python mangler pytest; opret ét virtuelt miljø først:
  `python3 -m venv /tmp/daa-venv && /tmp/daa-venv/bin/pip install -r .claude/skills/daa-extract/requirements-test.txt` og brug `/tmp/daa-venv/bin/python -m pytest`.
- **JS-testkommando:** `npx vitest run src/<fil>.test.ts` fra `web/`.

## Filstruktur

| Fil | Ansvar |
|---|---|
| `.claude/skills/daa-extract/scripts/review_ui_shared.js` | **ny** — UI-grundstof begge flader deler: DOM-hjælpere, lokal lagring, eksport, karantæne |
| `.claude/skills/daa-extract/scripts/human_review_1939_ui.js` | **ændres** — bruger det delte modul i stedet for egne kopier |
| `.claude/skills/daa-extract/scripts/make_human_review_1939.py` | **ændres** — indlejrer det delte modul før controlleren |
| `.claude/skills/daa-extract/scripts/boundary_spans_1939.py` | **ny** — samler accepterede spænd, danner grænser med revision, fail-closed på overlap |
| `.claude/skills/daa-extract/scripts/boundary_signals_1939.py` | **ny** — de seks signaler, hulklassifikation, negativ tværgengivelses-port |
| `.claude/skills/daa-extract/scripts/make_boundary_review_1939.py` | **ny** — CLI, hash-validering, view-model, HTML-udskrivning |
| `.claude/skills/daa-extract/scripts/boundary_review_1939_ui.js` | **ny** — fladen: visning, fem domme, OCR-noter, lagring, eksport |
| `web/src/boundaryReview1939Ui.test.ts` | **ny** — vitest for fladen |

Grænsen mellem `boundary_spans_1939` og `boundary_signals_1939` er bevidst: den første ved kun noget om positioner og ejerskab, den anden kun noget om tekst og trykt struktur. Det holder begge små nok til at kunne læses i én omgang.

---

### Task 1: Delt UI-modul

**Files:**
- Create: `.claude/skills/daa-extract/scripts/review_ui_shared.js`
- Modify: `.claude/skills/daa-extract/scripts/human_review_1939_ui.js` (fjern de udtrukne hjælpere, forbrug det delte modul)
- Modify: `.claude/skills/daa-extract/scripts/make_human_review_1939.py` (indlejr det delte modul før controlleren)
- Test: `web/src/humanReview1939Ui.test.ts` (indlæs to kilder i stedet for én), `.claude/skills/daa-extract/scripts/test_make_human_review_1939.py`

**Interfaces:**
- Consumes: intet
- Produces: `global.DAAReviewShared = { element, actionButton, clone, hasOwn, dictionary, sameValue, downloadJson, readStoredDraft, writeStoredDraft }`
  - `element(tag: string, text?: string, attributes?: object) → HTMLElement`
  - `actionButton(text: string, action: string, data?: object) → HTMLButtonElement`
  - `clone(value: any) → any` (JSON-rundtur, `null`/`undefined` uændret)
  - `hasOwn(value: object, key: string) → boolean`
  - `dictionary(entries: [string, any][]) → object` (prototypeløs)
  - `sameValue(left: any, right: any) → boolean` (JSON-sammenligning)
  - `downloadJson(value: any, filename: string) → void`
  - `readStoredDraft(storage, key: string) → object | null` (returnerer `null` ved ugyldig JSON)
  - `writeStoredDraft(storage, key: string, value: any) → string` (tom streng ved succes, ellers dansk fejltekst)

- [ ] **Step 1: Kopiér de eksisterende hjælpere til det nye modul**

Åbn `human_review_1939_ui.js` og find `clone` (linje 34), `hasOwn` (38), `dictionary` (42), `sameValue` (221), `element` (596), `actionButton` (605), `downloadJson` (907). Skriv `review_ui_shared.js` med præcis de samme kroppe:

```js
(function (global) {
  'use strict';

  function clone(value) {
    return value == null ? value : JSON.parse(JSON.stringify(value));
  }

  function hasOwn(value, key) {
    return Object.prototype.hasOwnProperty.call(value, key);
  }

  function dictionary(entries) {
    return entries.reduce((result, [key, value]) => {
      result[key] = value;
      return result;
    }, Object.create(null));
  }

  function sameValue(left, right) {
    return JSON.stringify(left) === JSON.stringify(right);
  }

  function element(tag, text, attributes) {
    const node = document.createElement(tag);
    if (text !== undefined) node.textContent = text;
    Object.entries(attributes || {}).forEach(([name, value]) => {
      node.setAttribute(name, value);
    });
    return node;
  }

  function actionButton(text, action, data) {
    const button = element('button', text, { type: 'button', 'data-action': action });
    Object.entries(data || {}).forEach(([name, value]) => {
      button.setAttribute(`data-${name.replace(/[A-Z]/g, m => '-' + m.toLowerCase())}`, value);
    });
    return button;
  }

  function downloadJson(value, filename) {
    const blob = new Blob([JSON.stringify(value, null, 2)], { type: 'application/json' });
    const link = document.createElement('a');
    link.href = URL.createObjectURL(blob);
    link.download = filename;
    link.click();
  }

  function readStoredDraft(storage, key) {
    try {
      const raw = storage.getItem(key);
      return raw ? JSON.parse(raw) : null;
    } catch (error) {
      return null;
    }
  }

  function writeStoredDraft(storage, key, value) {
    try {
      storage.setItem(key, JSON.stringify(value));
      return '';
    } catch (error) {
      return 'Kladden kunne ikke gemmes lokalt i denne browser.';
    }
  }

  global.DAAReviewShared = {
    element, actionButton, clone, hasOwn, dictionary, sameValue,
    downloadJson, readStoredDraft, writeStoredDraft,
  };
}(typeof globalThis === 'undefined' ? this : globalThis));
```

Sammenlign hver krop tegn for tegn med originalen. Afviger `element` eller `actionButton`, knækker menneskearkets tests — og de er regressionsværnet.

- [ ] **Step 2: Kør menneskearkets tests og se dem bestå uændret**

Fra `web/`: `npx vitest run src/humanReview1939Ui.test.ts`
Expected: PASS, 88 tests. Intet er ændret endnu; dette er nulmålingen der skal reproduceres i step 6.

- [ ] **Step 3: Lad testen indlæse begge kilder**

I `web/src/humanReview1939Ui.test.ts`, efter `const uiSource = readFileSync(...)`:

```ts
const sharedSource = readFileSync(resolve(
  process.cwd(), '../.claude/skills/daa-extract/scripts/review_ui_shared.js',
), 'utf8');
```

Og hvert af de tre steder der kalder `window.eval(uiSource)` (linje 101, 138, 256) bliver:

```ts
window.eval(sharedSource);
window.eval(uiSource);
```

- [ ] **Step 4: Forbrug modulet i menneskearket**

Erstat de syv funktionsdefinitioner i `human_review_1939_ui.js` med én destrukturering øverst i IIFE'en, lige efter `'use strict';`:

```js
  const {
    element, actionButton, clone, hasOwn, dictionary, sameValue, downloadJson,
  } = global.DAAReviewShared;
```

Slet derefter de gamle definitioner. `downloadJson` bruges kun i `createController`; de øvrige bruges bredt. Rør ikke `storageKeyFor`, `sourceIdentity` eller nogen anden funktion — kun de syv.

- [ ] **Step 5: Indlejr modulet i generatoren**

I `make_human_review_1939.py`, ved siden af `UI_PATH`:

```python
SHARED_UI_PATH = Path(__file__).with_name("review_ui_shared.js")
```

I `main()`, hvor `controller` skrives (omkring linje 538-543), indsæt det delte modul først:

```python
    shared = SHARED_UI_PATH.read_text(encoding="utf-8")
    controller = UI_PATH.read_text(encoding="utf-8")
    with args.out.open("x", encoding="utf-8") as handle:
        handle.write(HTML_PREFIX)
        handle.write(payload)
        handle.write(";\n")
        handle.write(shared)
        handle.write("\n")
        handle.write(controller)
        handle.write("\n")
        handle.write(HTML_SUFFIX)
```

Rækkefølgen er bindende: controlleren læser `global.DAAReviewShared` ved indlæsning.

- [ ] **Step 6: Kør begge suiter og bekræft uændret resultat**

Fra `web/`: `npx vitest run src/humanReview1939Ui.test.ts`
Expected: PASS, **88 tests** — samme tal som i step 2. Ændrer tallet sig, er adfærd flyttet og ikke kun kode; find fejlen frem for at rette testen.

Fra `.claude/skills/daa-extract/scripts`: `/tmp/daa-venv/bin/python -m pytest test_make_human_review_1939.py -q`
Expected: PASS. Bemærk at testen matcher HTML'en med `r"const DATA=(.*?);\n\(function \(global\)"` — det delte modul begynder også med `(function (global)`, så regexen rammer nu det delte modul i stedet for controlleren. Det er stadig korrekt for de tests der kun læser `DATA`, men bekræft at ingen test fejler; gør de det, er det fordi de læser efter controlleren, og så skal deres regex have et mere specifikt anker (`window.DAA1939Review`).

- [ ] **Step 7: Commit**

```bash
git add .claude/skills/daa-extract/scripts/review_ui_shared.js \
        .claude/skills/daa-extract/scripts/human_review_1939_ui.js \
        .claude/skills/daa-extract/scripts/make_human_review_1939.py \
        web/src/humanReview1939Ui.test.ts
git commit -m "refactor: udtræk delt UI-grundstof til review_ui_shared.js

Grænsefladen får brug for samme DOM-hjælpere, lagring og eksport som
menneskearket. Uden et delt modul ville de to flader divergere ved første
rettelse. Menneskearkets 88 tests består uændret, hvilket er værnet for at
kun kode og ikke adfærd er flyttet."
```

---

### Task 2: Grænser af accepterede spænd

**Files:**
- Create: `.claude/skills/daa-extract/scripts/boundary_spans_1939.py`
- Test: `.claude/skills/daa-extract/scripts/test_boundary_spans_1939.py`

**Interfaces:**
- Consumes: intet fra tidligere tasks
- Produces:
  - `class BoundaryError(ValueError)`
  - `collect_accepted_spans(anchored: Mapping, automatic: Mapping) → list[dict]` — hvert element `{"baseline_record_key": str, "candidate_id": str, "char_from": int, "char_to": int, "origin": "menneske" | "automatisk"}`, sorteret efter `char_from`. Hæver `BoundaryError` ved overlap eller ved samme post to gange.
  - `build_boundaries(spans: list[dict], source_length: int) → list[dict]` — hvert element `{"boundary_id": str, "revision": int, "before": dict | None, "after": dict | None, "gap": {"char_from": int, "char_to": int}}`. `before is None` ved kildens start, `after is None` ved kildens slut.
  - `boundary_id_for(before: dict | None, after: dict | None, revision: int) → str`

- [ ] **Step 1: Skriv de fejlende tests**

```python
import pytest

from boundary_spans_1939 import (
    BoundaryError, boundary_id_for, build_boundaries, collect_accepted_spans,
)


def anchored(key, cid, char_from, char_to):
    return {cid: {"baseline_record_key": key, "candidate": {
        "candidate_id": cid, "postklasse": "nummereret",
        "calamari_span": {"char_from": char_from, "char_to": char_to},
        "pdf_pages": [500], "approval": {"kind": "human_approved_span_v1",
                                         "calamari_excerpt_sha256": "a" * 64}}}}


def automatic(key, cid, char_from, char_to):
    return {key: {"baseline_record_key": key, "queue_class": "auto_resolved",
                  "candidate": {"candidate_id": cid, "postklasse": "nummereret",
                                "calamari_span": {"char_from": char_from, "char_to": char_to},
                                "pdf_pages": [500]}}}


def test_spans_are_sorted_by_position_and_carry_their_origin():
    spans = collect_accepted_spans(
        {**anchored("rk-b", "human:b", 200, 300)},
        {**automatic("rk-a", "1939:a", 0, 100)},
    )

    assert [span["baseline_record_key"] for span in spans] == ["rk-a", "rk-b"]
    assert [span["origin"] for span in spans] == ["automatisk", "menneske"]
    assert spans[0]["char_from"] == 0 and spans[0]["char_to"] == 100


def test_overlapping_spans_fail_closed():
    with pytest.raises(BoundaryError, match="overlapper"):
        collect_accepted_spans(
            {**anchored("rk-a", "human:a", 0, 150)},
            {**automatic("rk-b", "1939:b", 100, 200)},
        )


def test_the_same_record_cannot_own_two_spans():
    with pytest.raises(BoundaryError, match="to gange"):
        collect_accepted_spans(
            {**anchored("rk-a", "human:a", 0, 100),
             **anchored("rk-a", "human:a2", 200, 300)},
            {},
        )


def test_boundaries_include_the_edges_of_the_source():
    spans = collect_accepted_spans({**anchored("rk-a", "human:a", 50, 100)}, {})

    boundaries = build_boundaries(spans, source_length=200)

    assert len(boundaries) == 2
    assert boundaries[0]["before"] is None
    assert boundaries[0]["gap"] == {"char_from": 0, "char_to": 50}
    assert boundaries[1]["after"] is None
    assert boundaries[1]["gap"] == {"char_from": 100, "char_to": 200}


def test_no_accepted_span_gives_one_boundary_covering_everything():
    boundaries = build_boundaries([], source_length=200)

    assert len(boundaries) == 1
    assert boundaries[0]["before"] is None and boundaries[0]["after"] is None
    assert boundaries[0]["gap"] == {"char_from": 0, "char_to": 200}


def test_adjacent_spans_give_an_empty_gap():
    spans = collect_accepted_spans(
        {**anchored("rk-a", "human:a", 0, 100), **anchored("rk-b", "human:b", 100, 200)},
        {},
    )

    middle = build_boundaries(spans, source_length=200)[1]

    assert middle["before"]["baseline_record_key"] == "rk-a"
    assert middle["after"]["baseline_record_key"] == "rk-b"
    assert middle["gap"] == {"char_from": 100, "char_to": 100}


def test_boundary_id_is_stable_and_revision_bearing():
    before = {"candidate_id": "human:a", "char_from": 0, "char_to": 100}
    after = {"candidate_id": "human:b", "char_from": 100, "char_to": 200}

    first = boundary_id_for(before, after, 0)

    assert first == boundary_id_for(before, after, 0)
    assert first != boundary_id_for(before, after, 1)
    assert first != boundary_id_for(after, before, 0)


def test_boundary_id_survives_a_cycle_only_through_its_revision():
    """A -> B -> A giver samme spænd igen; kun revisionen skiller dommene."""
    before = {"candidate_id": "human:a", "char_from": 0, "char_to": 100}
    after = {"candidate_id": "human:b", "char_from": 100, "char_to": 200}

    assert boundary_id_for(before, after, 0) != boundary_id_for(before, after, 2)
```

- [ ] **Step 2: Kør testene og se dem fejle**

Run: `/tmp/daa-venv/bin/python -m pytest test_boundary_spans_1939.py -q`
Expected: FAIL — `ModuleNotFoundError: No module named 'boundary_spans_1939'`

- [ ] **Step 3: Skriv modulet**

```python
"""Danner grænserne mellem accepterede kildespænd, uden at ændre dem."""

from __future__ import annotations

import hashlib
from collections.abc import Mapping


class BoundaryError(ValueError):
    pass


def _span_of(candidate: object, label: str) -> tuple[int, int]:
    if not isinstance(candidate, Mapping):
        raise BoundaryError(f"{label} mangler kandidat")
    span = candidate.get("calamari_span")
    if not isinstance(span, Mapping):
        raise BoundaryError(f"{label} mangler calamari_span")
    char_from, char_to = span.get("char_from"), span.get("char_to")
    for value in (char_from, char_to):
        if isinstance(value, bool) or not isinstance(value, int) or value < 0:
            raise BoundaryError(f"{label} har ugyldigt calamari_span")
    if char_to <= char_from:
        raise BoundaryError(f"{label} har tomt calamari_span")
    return char_from, char_to


def _entry(record_key: object, candidate: object, origin: str) -> dict:
    if not isinstance(record_key, str) or not record_key:
        raise BoundaryError("accepteret spænd mangler baseline_record_key")
    char_from, char_to = _span_of(candidate, f"post {record_key}")
    candidate_id = candidate.get("candidate_id")
    if not isinstance(candidate_id, str) or not candidate_id:
        raise BoundaryError(f"post {record_key} mangler candidate_id")
    return {
        "baseline_record_key": record_key,
        "candidate_id": candidate_id,
        "char_from": char_from,
        "char_to": char_to,
        "origin": origin,
    }


def collect_accepted_spans(anchored: object, automatic: object) -> list[dict]:
    """Saml de accepterede spænd fra begge producenter, fail-closed på overlap."""
    if not isinstance(anchored, Mapping) or not isinstance(automatic, Mapping):
        raise BoundaryError("accepterede spænd skal leveres som mappings")
    spans: list[dict] = []
    for entry in anchored.values():
        if not isinstance(entry, Mapping):
            raise BoundaryError("forankret kandidat skal være en mapping")
        spans.append(_entry(entry.get("baseline_record_key"),
                            entry.get("candidate"), "menneske"))
    for entry in automatic.values():
        if not isinstance(entry, Mapping):
            raise BoundaryError("automatisk kandidat skal være en mapping")
        spans.append(_entry(entry.get("baseline_record_key"),
                            entry.get("candidate"), "automatisk"))
    owners: dict[str, str] = {}
    for span in spans:
        key = span["baseline_record_key"]
        if key in owners:
            raise BoundaryError(f"post {key} ejer et spænd to gange")
        owners[key] = span["candidate_id"]
    spans.sort(key=lambda span: (span["char_from"], span["char_to"]))
    for left, right in zip(spans, spans[1:]):
        if right["char_from"] < left["char_to"]:
            raise BoundaryError(
                f"spænd overlapper: {left['baseline_record_key']} og "
                f"{right['baseline_record_key']}"
            )
    return spans


def boundary_id_for(before: Mapping | None, after: Mapping | None,
                    revision: int) -> str:
    """Identiteten er de to nabospænd PLUS revisionen.

    Uden revisionen ville A -> B -> A give det oprindelige id igen, og en gammel
    dom kunne fremstå gyldig for en grænse der har været igennem to rettelser.
    """
    if isinstance(revision, bool) or not isinstance(revision, int) or revision < 0:
        raise BoundaryError("revision skal være et ikke-negativt heltal")

    def part(span: Mapping | None, label: str) -> str:
        if span is None:
            return label
        return f"{span['candidate_id']}:{span['char_from']}:{span['char_to']}"

    digest = hashlib.sha256(
        "\0".join(("1939-v2", part(before, "kildestart"), part(after, "kildeslut"),
                   str(revision))).encode("utf-8")
    ).hexdigest()
    return f"graense:1939-v2:{digest}"


def build_boundaries(spans: list[dict], source_length: int) -> list[dict]:
    """Én grænse pr. skifte i ejerskab, inklusive kildens to rande."""
    if isinstance(source_length, bool) or not isinstance(source_length, int) or source_length < 0:
        raise BoundaryError("source_length skal være et ikke-negativt heltal")
    for span in spans:
        if span["char_to"] > source_length:
            raise BoundaryError(
                f"post {span['baseline_record_key']} rækker ud over kildeteksten"
            )
    edges: list[tuple[dict | None, dict | None, int, int]] = []
    if not spans:
        edges.append((None, None, 0, source_length))
    else:
        edges.append((None, spans[0], 0, spans[0]["char_from"]))
        for left, right in zip(spans, spans[1:]):
            edges.append((left, right, left["char_to"], right["char_from"]))
        edges.append((spans[-1], None, spans[-1]["char_to"], source_length))
    return [
        {
            "boundary_id": boundary_id_for(before, after, 0),
            "revision": 0,
            "before": before,
            "after": after,
            "gap": {"char_from": gap_from, "char_to": gap_to},
        }
        for before, after, gap_from, gap_to in edges
    ]
```

- [ ] **Step 4: Kør testene og se dem bestå**

Run: `/tmp/daa-venv/bin/python -m pytest test_boundary_spans_1939.py -q`
Expected: PASS, 8 tests

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/daa-extract/scripts/boundary_spans_1939.py \
        .claude/skills/daa-extract/scripts/test_boundary_spans_1939.py
git commit -m "feat(1939): dan grænser af accepterede kildespænd

Spændene sorteres efter position, ikke efter trykt nummer, fordi det er
kildeteksten der bliver delt. Kildens to rande får hver sin grænse, så
dækningskravet også holder ved bogens ender. Identiteten bærer et
revisionsnummer, så en A->B->A-rettelse ikke genopliver en gammel dom."
```

---

### Task 3: Klausul-regnskab og hulklassifikation

**Files:**
- Create: `.claude/skills/daa-extract/scripts/boundary_signals_1939.py`
- Test: `.claude/skills/daa-extract/scripts/test_boundary_signals_1939.py`

**Interfaces:**
- Consumes: `boundary_spans_1939.build_boundaries` (grænsens `gap`)
- Produces:
  - `classify_gap(clauses: list[dict], gap: Mapping) → dict` — `{"tegn": int, "klasser": {"record_text": int, "structural_header": int, "layout": int, "noise": int}, "har_broedtekst": bool}`
  - `SignalError(ValueError)`

Klausulerne kommer fra `segment.py`'s regnskab: hver klausul er `{"char_from": int, "char_to": int, "classification": "record_text" | "structural_header" | "layout" | "noise", ...}`. Regnskabet dækker hele kildeteksten linje for linje.

- [ ] **Step 1: Skriv de fejlende tests**

```python
import pytest

from boundary_signals_1939 import SignalError, classify_gap


def clause(char_from, char_to, classification):
    return {"char_from": char_from, "char_to": char_to,
            "classification": classification}


CLAUSES = [
    clause(0, 20, "record_text"),
    clause(20, 40, "structural_header"),
    clause(40, 45, "layout"),
    clause(45, 70, "record_text"),
]


def test_a_gap_of_only_heading_and_layout_has_no_prose():
    summary = classify_gap(CLAUSES, {"char_from": 20, "char_to": 45})

    assert summary["har_broedtekst"] is False
    assert summary["klasser"]["structural_header"] == 1
    assert summary["klasser"]["layout"] == 1
    assert summary["tegn"] == 25


def test_a_gap_touching_prose_reports_it():
    summary = classify_gap(CLAUSES, {"char_from": 30, "char_to": 50})

    assert summary["har_broedtekst"] is True
    assert summary["klasser"]["record_text"] == 1


def test_an_empty_gap_has_no_clauses_and_no_prose():
    summary = classify_gap(CLAUSES, {"char_from": 40, "char_to": 40})

    assert summary["tegn"] == 0
    assert summary["har_broedtekst"] is False
    assert summary["klasser"] == {"record_text": 0, "structural_header": 0,
                                  "layout": 0, "noise": 0}


def test_an_unknown_classification_fails_closed():
    with pytest.raises(SignalError, match="klassifikation"):
        classify_gap([clause(0, 10, "opfundet")], {"char_from": 0, "char_to": 10})


def test_a_reversed_gap_fails_closed():
    with pytest.raises(SignalError, match="hul"):
        classify_gap(CLAUSES, {"char_from": 40, "char_to": 20})
```

- [ ] **Step 2: Kør testene og se dem fejle**

Run: `/tmp/daa-venv/bin/python -m pytest test_boundary_signals_1939.py -q`
Expected: FAIL — `ModuleNotFoundError: No module named 'boundary_signals_1939'`

- [ ] **Step 3: Skriv klassifikationen**

```python
"""Signalerne der afgør om en grænse skal læses af et menneske."""

from __future__ import annotations

from collections.abc import Mapping


class SignalError(ValueError):
    pass


KLASSER = ("record_text", "structural_header", "layout", "noise")


def classify_gap(clauses: list[dict], gap: Mapping) -> dict:
    """Opsummér hvad der ligger i hullet mellem to spænd.

    Regnskabet sorterer kun. Om et hul må massebekræftes afgøres af den
    negative tværgengivelses-kontrol, ikke af denne klassifikation: regnskabet
    kalder alt uklassificeret ``record_text`` og bruger ikke 1939-v2-profilens
    fulde strukturlogik.
    """
    if not isinstance(gap, Mapping):
        raise SignalError("hul skal være en mapping")
    char_from, char_to = gap.get("char_from"), gap.get("char_to")
    for value in (char_from, char_to):
        if isinstance(value, bool) or not isinstance(value, int) or value < 0:
            raise SignalError("hul har ugyldige positioner")
    if char_to < char_from:
        raise SignalError("hul slutter før det begynder")
    counts = dict.fromkeys(KLASSER, 0)
    for item in clauses:
        if not isinstance(item, Mapping):
            raise SignalError("klausul skal være en mapping")
        classification = item.get("classification")
        if classification not in KLASSER:
            raise SignalError("ukendt klausul-klassifikation")
        if char_to <= item["char_from"] or item["char_to"] <= char_from:
            continue
        if char_from == char_to:
            continue
        counts[classification] += 1
    return {
        "tegn": char_to - char_from,
        "klasser": counts,
        "har_broedtekst": counts["record_text"] > 0,
    }
```

- [ ] **Step 4: Kør testene og se dem bestå**

Run: `/tmp/daa-venv/bin/python -m pytest test_boundary_signals_1939.py -q`
Expected: PASS, 5 tests

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/daa-extract/scripts/boundary_signals_1939.py \
        .claude/skills/daa-extract/scripts/test_boundary_signals_1939.py
git commit -m "feat(1939): klassificér hullet mellem to accepterede spænd

Ejerløs tekst er legitim — overskrifter, generationslinjer, sidemarkører — og
kategorien findes allerede i segment.py's klausul-regnskab. Et hul kan derfor
slås op frem for gættes. Klassifikationen sorterer; den porter ikke."
```

---

### Task 4: Den negative tværgengivelses-port

**Files:**
- Modify: `.claude/skills/daa-extract/scripts/boundary_signals_1939.py`
- Test: `.claude/skills/daa-extract/scripts/test_boundary_signals_1939.py`

**Interfaces:**
- Consumes: `classify_gap` fra Task 3
- Produces: `may_bulk_confirm(gap_text: str, raw_text_window: str, gap_summary: Mapping) → bool`

Porten er hele grunden til at fase 1 kan have en hurtig-bekræftelses-bunke uden at skjule en manglende person. Den fejl der skabte problemet — et trykt hoved Calamari tabte — er synlig i rå OCR.

- [ ] **Step 1: Skriv de fejlende tests**

```python
from boundary_signals_1939 import may_bulk_confirm


CLEAN_SUMMARY = {"tegn": 30, "klasser": {"record_text": 0, "structural_header": 1,
                                         "layout": 1, "noise": 0},
                 "har_broedtekst": False}


def test_a_heading_only_gap_may_be_bulk_confirmed():
    assert may_bulk_confirm("Sjette Slægtled\n", "Sjette Slægtled\n", CLEAN_SUMMARY) is True


def test_prose_in_the_gap_blocks_bulk_confirmation():
    summary = {**CLEAN_SUMMARY, "har_broedtekst": True}

    assert may_bulk_confirm("noget prosa\n", "noget prosa\n", summary) is False


def test_a_printed_head_in_calamari_blocks_bulk_confirmation():
    assert may_bulk_confirm("7. Heinrich til Gottesgabe\n", "", CLEAN_SUMMARY) is False


def test_a_printed_head_only_in_raw_ocr_still_blocks_bulk_confirmation():
    """Netop den fejl der skabte problemet: Calamari tabte hovedet, rå OCR har det."""
    assert may_bulk_confirm(
        "7 Heinrich til Gottesgabe\n", "7. H e i n r i c h til Gottesgabe\n", CLEAN_SUMMARY,
    ) is False


def test_an_empty_gap_may_be_bulk_confirmed():
    empty = {"tegn": 0, "klasser": dict.fromkeys(
        ("record_text", "structural_header", "layout", "noise"), 0),
        "har_broedtekst": False}

    assert may_bulk_confirm("", "", empty) is True
```

- [ ] **Step 2: Kør testene og se dem fejle**

Run: `/tmp/daa-venv/bin/python -m pytest test_boundary_signals_1939.py -q`
Expected: FAIL — `ImportError: cannot import name 'may_bulk_confirm'`

- [ ] **Step 3: Skriv porten**

Tilføj til `boundary_signals_1939.py`. `POST_1939_RE` genbruges fra `segment` frem for at gentages, så de to steder ikke kan divergere:

```python
import re

import segment

# Et trykt hoved uden punktum ("7 Heinrich") er netop den form Calamari tabte.
# Porten skal derfor være bredere end selve postregelen, ellers lukker den
# præcis den fejl igennem som den findes for.
_LOEST_HOVED_RE = re.compile(
    r"(?m)^\s{0,4}\??\s{0,2}\d{1,3}\s*[a-z]?\.?\s+(?!(?:Jan|Febr|Marts|April|Maj|Juni|"
    r"Juli|Aug|Sept|Okt|Nov|Dec|Aar|s\.\s*M))[^\W\d_]",
    re.UNICODE,
)


def _har_trykt_hoved(text: str) -> bool:
    if not isinstance(text, str):
        raise SignalError("tekst skal være en streng")
    for line in text.splitlines():
        if segment.POST_1939_RE.match(line):
            return True
    return bool(_LOEST_HOVED_RE.search(text))


def may_bulk_confirm(gap_text: str, raw_text_window: str,
                     gap_summary: Mapping) -> bool:
    """Porten til hurtig bekræftelse: tre krav, alle skal holde.

    1. ingen brødtekst i hullet ifølge regnskabet
    2. intet trykt hoved i Calamari-hullet
    3. intet trykt hoved i rå OCR's modsvarende stykke

    Punkt 3 er det afgørende. Et hoved Calamari har tabt, er stadig synligt i
    den anden gengivelse, og uden dette krav kunne en manglende person havne i
    den bunke der godkendes tyve ad gangen.
    """
    if not isinstance(gap_summary, Mapping) or "har_broedtekst" not in gap_summary:
        raise SignalError("hul-opsummering mangler har_broedtekst")
    if gap_summary["har_broedtekst"]:
        return False
    return not _har_trykt_hoved(gap_text) and not _har_trykt_hoved(raw_text_window)
```

- [ ] **Step 4: Kør testene og se dem bestå**

Run: `/tmp/daa-venv/bin/python -m pytest test_boundary_signals_1939.py -q`
Expected: PASS, 10 tests

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/daa-extract/scripts/boundary_signals_1939.py \
        .claude/skills/daa-extract/scripts/test_boundary_signals_1939.py
git commit -m "feat(1939): negativ tværgengivelses-port til hurtig bekræftelse

Klausul-regnskabet kalder alt uklassificeret record_text og bruger ikke
1939-v2-profilens fulde strukturlogik, så en manglende person kunne havne i
bunken der godkendes i stræk. Porten kræver nu: ingen brødtekst, intet trykt
hoved i Calamari, OG intet i rå OCR. Den fejl der skabte hele problemet er
synlig i den anden gengivelse."
```

---

### Task 5: Hoved-, slugnings-, nummerspring- og længdesignaler

**Files:**
- Modify: `.claude/skills/daa-extract/scripts/boundary_signals_1939.py`
- Test: `.claude/skills/daa-extract/scripts/test_boundary_signals_1939.py`

**Interfaces:**
- Consumes: `detect_boundary_defects_1939.fold_ocr`, `_name_stem`, `_printed_number`, `_branch`
- Produces: `span_signals(span: Mapping, record: Mapping, span_text: str, siblings: list[Mapping]) → list[str]` — delmængde af `{"mangler_eget_hoved", "slugt_hoved", "nummerspring", "laengdeafvigelse"}`

`record` er baseline-posten (`navn`, `_orig_nr`, `_gruppe_nr`, `_v2_lokal_id`). `siblings` er baseline-posterne i samme søskendegruppe, hver med den `char_from` deres accepterede spænd har (nøgle `"char_from"`), eller uden nøglen hvis posten ikke har et accepteret spænd.

- [ ] **Step 1: Skriv de fejlende tests**

```python
from boundary_signals_1939 import span_signals


def record(navn, orig_nr, gruppe=1, char_from=None):
    entry = {"navn": navn, "_orig_nr": orig_nr, "_gruppe_nr": gruppe,
             "_v2_lokal_id": f"III.Sjette.III.{orig_nr}"}
    if char_from is not None:
        entry["char_from"] = char_from
    return entry


def test_a_span_opening_with_its_own_printed_head_has_no_signal():
    own = record("Christine Augusta", 6, char_from=0)

    signals = span_signals({"char_from": 0, "char_to": 400}, own,
                           "6. Christine Augusta; g. 1708 i Königsberg.", [own])

    assert signals == []


def test_a_headless_span_is_flagged():
    own = record("Heinrich", 7, char_from=0)

    signals = span_signals({"char_from": 0, "char_to": 200}, own,
                           "Prins Georgs Reg., 1703 Sek.major.", [own])

    assert "mangler_eget_hoved" in signals


def test_a_span_carrying_a_later_siblings_head_is_flagged():
    own = record("Christine Augusta", 6, char_from=0)
    later = record("Heinrich", 7, char_from=400)

    signals = span_signals(
        {"char_from": 0, "char_to": 400}, own,
        "6. Christine Augusta; g. 1708.\n7 Heinrich til Gottesgabe", [own, later],
    )

    assert "slugt_hoved" in signals


def test_a_date_continuation_is_not_a_swallowed_head():
    own = record("Ditlev Christian Ernst", 24, char_from=0)
    sibling = record("Margrethe", 23, char_from=400)

    signals = span_signals(
        {"char_from": 0, "char_to": 400}, own,
        "24. Ditlev Christian Ernst, f. 12 Juni 1712, bgr.\n23 s. M. i Kiel.",
        [own, sibling],
    )

    assert "slugt_hoved" not in signals


def test_siblings_out_of_printed_order_give_a_number_skip():
    own = record("Heino", 5, char_from=900)
    earlier = record("David", 6, char_from=100)

    signals = span_signals({"char_from": 900, "char_to": 1000}, own,
                           "5. Heino til Lelkendorf.", [own, earlier])

    assert "nummerspring" in signals


def test_a_span_far_shorter_than_its_siblings_is_flagged_for_sorting_only():
    own = record("Kort", 3, char_from=0)
    siblings = [own, record("Lang", 4, char_from=100), record("Lang", 5, char_from=900)]

    signals = span_signals({"char_from": 0, "char_to": 20}, own, "3. Kort.", siblings,
                           sibling_lengths=[800, 820])

    assert signals == ["laengdeafvigelse"]
```

- [ ] **Step 2: Kør testene og se dem fejle**

Run: `/tmp/daa-venv/bin/python -m pytest test_boundary_signals_1939.py -q`
Expected: FAIL — `ImportError: cannot import name 'span_signals'`

- [ ] **Step 3: Skriv signalerne**

```python
import statistics

from detect_boundary_defects_1939 import (
    _branch, _name_stem, _printed_number, fold_ocr,
)

_HOVED_VINDUE = 90
_NAVN_PRAEFIKS = 4
# Under en tredjedel af søskendemedianen regnes som afvigende. Rent
# sorteringssignal — det bliver aldrig en advarsel i sig selv.
_LAENGDE_ANDEL = 3


def _group_key(record: Mapping) -> object:
    gruppe = record.get("_gruppe_nr")
    return ("gruppe", gruppe) if gruppe is not None else ("gren", _branch(record))


def _opens_with_own_head(record: Mapping, span_text: str) -> bool:
    stem = _name_stem(record.get("navn"))
    if not stem:
        return True
    window = span_text.lstrip()[:_HOVED_VINDUE]
    number = _printed_number(record)
    if number is not None:
        window = re.sub(rf"^\(?\??\s*{number}\s*[a-z]?[.,)]?\s*", "", window)
    return stem in fold_ocr(window)[:60]


def _swallows_later_head(record: Mapping, span_text: str,
                         siblings: list[Mapping]) -> bool:
    own = _printed_number(record)
    if own is None:
        return False
    later = {}
    for sibling in siblings:
        number = _printed_number(sibling)
        stem = _name_stem(sibling.get("navn"))
        if number is not None and number > own and stem:
            later.setdefault(number, stem)
    for match in re.finditer(r"(?<![\d.,])\b(\d{1,3})\s*[a-z]?\.?\s+(\S.{0,44})",
                             span_text):
        if match.start() == 0:
            continue
        stem = later.get(int(match.group(1)))
        if stem and fold_ocr(match.group(2)).startswith(stem):
            return True
    return False


def _number_skip(record: Mapping, span: Mapping, siblings: list[Mapping]) -> bool:
    own = _printed_number(record)
    if own is None:
        return False
    for sibling in siblings:
        number = _printed_number(sibling)
        position = sibling.get("char_from")
        if number is None or position is None or number == own:
            continue
        if (number < own) != (position < span["char_from"]):
            return True
    return False


def span_signals(span: Mapping, record: Mapping, span_text: str,
                 siblings: list[Mapping], *,
                 sibling_lengths: list[int] | None = None) -> list[str]:
    """De fire signaler der kan udledes af et spænd og dets søskende."""
    if not isinstance(span, Mapping) or "char_from" not in span:
        raise SignalError("spænd mangler char_from")
    if not isinstance(span_text, str):
        raise SignalError("spændtekst skal være en streng")
    signals = []
    if not _opens_with_own_head(record, span_text):
        signals.append("mangler_eget_hoved")
    if _swallows_later_head(record, span_text, siblings):
        signals.append("slugt_hoved")
    if _number_skip(record, span, siblings):
        signals.append("nummerspring")
    if sibling_lengths:
        median = statistics.median(sibling_lengths)
        length = span.get("char_to", span["char_from"]) - span["char_from"]
        if median and (length * _LAENGDE_ANDEL < median
                       or length > median * _LAENGDE_ANDEL):
            signals.append("laengdeafvigelse")
    return signals
```

- [ ] **Step 4: Kør testene og se dem bestå**

Run: `/tmp/daa-venv/bin/python -m pytest test_boundary_signals_1939.py -q`
Expected: PASS, 16 tests

- [ ] **Step 5: Kør nabosuiterne for at bekræfte at genbrugen ikke flyttede adfærd**

Run: `/tmp/daa-venv/bin/python -m pytest test_detect_boundary_defects_1939.py test_make_human_review_1939.py -q`
Expected: PASS, 22 + 56 tests

- [ ] **Step 6: Commit**

```bash
git add .claude/skills/daa-extract/scripts/boundary_signals_1939.py \
        .claude/skills/daa-extract/scripts/test_boundary_signals_1939.py
git commit -m "feat(1939): hoved-, slugnings-, nummerspring- og længdesignaler mod spænd

Hoved- og slugningslogikken er den samme som detektoren bruger mod de gamle
narrativer; den peger nu på de accepterede spænd i stedet. Nummerspring
sammenligner trykt rækkefølge med rækkefølgen i kildeteksten. Længdeafvigelse
er rent sorteringssignal og bliver aldrig en advarsel i sig selv."
```

---

### Task 6: View-model med bunker og global injektivitetskontrol

**Files:**
- Create: `.claude/skills/daa-extract/scripts/make_boundary_review_1939.py`
- Test: `.claude/skills/daa-extract/scripts/test_make_boundary_review_1939.py`

**Interfaces:**
- Consumes: `boundary_spans_1939.collect_accepted_spans`, `build_boundaries`; `boundary_signals_1939.classify_gap`, `may_bulk_confirm`, `span_signals`; `prepare_review_queue_1939.validate_effective_candidate_injectivity`
- Produces: `build_boundary_view_model(spans, boundaries, clauses, calamari_text, raw_text, records, source) → dict` med `{"schema_version": 1, "source": dict, "summary": {"graenser": int, "kraever_vurdering": int, "hurtig_bekraeftelse": int}, "views": {"kraever_vurdering": [id...], "hurtig_bekraeftelse": [id...]}, "boundaries": [...]}`

Hver `boundaries`-post: `{"boundary_id", "revision", "before", "after", "gap", "gap_summary", "gap_text", "raw_window", "signals": [...], "bulk_confirmable": bool, "before_context": str, "after_context": str}`.

- [ ] **Step 1: Skriv den fejlende test for bunkeinddelingen**

```python
import pytest

from make_boundary_review_1939 import build_boundary_view_model

SOURCE = {"edition": "1939", "profile_version": "1939-v2",
          "baseline_sha256": "a" * 64, "calamari_sha256": "b" * 64,
          "raw_ocr_sha256": "c" * 64, "pdf_sha256": "d" * 64}


def test_a_gap_with_a_head_only_in_raw_ocr_requires_judgement():
    calamari = "6. Christine Augusta; g. 1708.\n7 Heinrich til Gottesgabe\n"
    raw = "6. Christine Augusta; g. 1708.\n7. H e i n r i c h til Gottesgabe\n"
    spans = [{"baseline_record_key": "rk-6", "candidate_id": "human:6",
              "char_from": 0, "char_to": 30, "origin": "menneske"}]
    clauses = [{"char_from": 0, "char_to": 30, "classification": "record_text"},
               {"char_from": 30, "char_to": len(calamari),
                "classification": "structural_header"}]
    records = {"rk-6": {"record_key": "rk-6", "navn": "Christine Augusta",
                        "_orig_nr": 6, "_gruppe_nr": 1,
                        "_v2_lokal_id": "III.Sjette.III.6", "sider": "535"}}

    model = build_boundary_view_model(
        spans, clauses, calamari, raw, records, SOURCE,
    )

    tail = model["boundaries"][-1]
    assert tail["bulk_confirmable"] is False
    assert tail["boundary_id"] in model["views"]["kraever_vurdering"]
    assert model["summary"]["graenser"] == 2
```

- [ ] **Step 2: Kør testen og se den fejle**

Run: `/tmp/daa-venv/bin/python -m pytest test_make_boundary_review_1939.py -q`
Expected: FAIL — `ModuleNotFoundError: No module named 'make_boundary_review_1939'`

- [ ] **Step 3: Skriv view-model-byggeren**

```python
"""Bygger en privat, browserlokal grænsegennemgang for 1939."""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
from collections.abc import Mapping
from pathlib import Path

from boundary_signals_1939 import classify_gap, may_bulk_confirm, span_signals
from boundary_spans_1939 import BoundaryError, build_boundaries, collect_accepted_spans
from prepare_review_queue_1939 import validate_effective_candidate_injectivity

KONTEKST_TEGN = 400


def _group_of(record: Mapping) -> object:
    gruppe = record.get("_gruppe_nr")
    return ("gruppe", gruppe) if gruppe is not None else ("gren", record.get("_v2_lokal_id"))


def build_boundary_view_model(spans: list[dict], clauses: list[dict],
                              calamari_text: str, raw_text: str,
                              records: Mapping, source: Mapping) -> dict:
    """Saml grænserne, deres signaler og deres bunke — uden at ændre et spænd."""
    boundaries = build_boundaries(spans, len(calamari_text))
    by_key = {span["baseline_record_key"]: span for span in spans}
    groups: dict[object, list[dict]] = {}
    for key, span in by_key.items():
        record = records.get(key)
        if record is None:
            raise BoundaryError(f"accepteret spænd har ukendt post {key}")
        entry = {**copy.deepcopy(dict(record)), "char_from": span["char_from"]}
        groups.setdefault(_group_of(record), []).append(entry)
    signals_by_key: dict[str, list[str]] = {}
    for key, span in by_key.items():
        record = records[key]
        siblings = groups[_group_of(record)]
        lengths = [
            by_key[sibling["record_key"]]["char_to"]
            - by_key[sibling["record_key"]]["char_from"]
            for sibling in siblings if sibling["record_key"] != key
        ]
        signals_by_key[key] = span_signals(
            span, record, calamari_text[span["char_from"]:span["char_to"]],
            siblings, sibling_lengths=lengths,
        )
    view_required, view_bulk, entries = [], [], []
    for boundary in boundaries:
        gap = boundary["gap"]
        gap_text = calamari_text[gap["char_from"]:gap["char_to"]]
        raw_window = raw_text[gap["char_from"]:gap["char_to"]] if raw_text else ""
        summary = classify_gap(clauses, gap)
        signals = []
        for side in ("before", "after"):
            span = boundary[side]
            if span is not None:
                signals.extend(signals_by_key.get(span["baseline_record_key"], []))
        bulk = may_bulk_confirm(gap_text, raw_window, summary) and not [
            signal for signal in signals if signal != "laengdeafvigelse"
        ]
        entry = {
            **boundary,
            "gap_summary": summary,
            "gap_text": gap_text,
            "raw_window": raw_window,
            "signals": sorted(set(signals)),
            "bulk_confirmable": bulk,
            "before_context": calamari_text[
                max(0, gap["char_from"] - KONTEKST_TEGN):gap["char_from"]],
            "after_context": calamari_text[
                gap["char_to"]:gap["char_to"] + KONTEKST_TEGN],
            "before_navn": (records[boundary["before"]["baseline_record_key"]].get("navn")
                            if boundary["before"] else None),
            "after_navn": (records[boundary["after"]["baseline_record_key"]].get("navn")
                           if boundary["after"] else None),
        }
        entries.append(entry)
        (view_bulk if bulk else view_required).append(entry["boundary_id"])
    return {
        "schema_version": 1,
        "source": copy.deepcopy(dict(source)),
        "summary": {
            "graenser": len(entries),
            "kraever_vurdering": len(view_required),
            "hurtig_bekraeftelse": len(view_bulk),
        },
        "views": {
            "kraever_vurdering": view_required,
            "hurtig_bekraeftelse": view_bulk,
        },
        "boundaries": entries,
    }
```

- [ ] **Step 4: Kør testen og se den bestå**

Run: `/tmp/daa-venv/bin/python -m pytest test_make_boundary_review_1939.py -q`
Expected: PASS, 1 test

- [ ] **Step 5: Tilføj testen for det globale injektivitetskald**

```python
def test_the_canonical_global_injectivity_contract_is_called(monkeypatch):
    """validate_source_bound_evidence beviser ikke globalt fravær af overlap."""
    calls = []
    monkeypatch.setattr(
        "make_boundary_review_1939.validate_effective_candidate_injectivity",
        lambda effective, source: calls.append(sorted(effective)),
    )
    spans = [{"baseline_record_key": "rk-a", "candidate_id": "human:a",
              "char_from": 0, "char_to": 10, "origin": "menneske"}]
    records = {"rk-a": {"record_key": "rk-a", "navn": "Anders", "_orig_nr": 1,
                        "_gruppe_nr": 1, "_v2_lokal_id": "I.1", "sider": "496"}}

    build_boundary_view_model(
        spans, [{"char_from": 0, "char_to": 20, "classification": "record_text"}],
        "1. Anders, f. 1900.\n", "1. Anders, f. 1900.\n", records, SOURCE,
    )

    assert calls == [["rk-a"]]
```

- [ ] **Step 6: Kald kontrollen i implementeringen**

Indsæt i `build_boundary_view_model` lige efter `by_key` er dannet:

```python
    validate_effective_candidate_injectivity(
        {
            key: {"candidate_id": span["candidate_id"],
                  "postklasse": "nummereret",
                  "calamari_span": {"char_from": span["char_from"],
                                    "char_to": span["char_to"]},
                  "pdf_pages": list(records[key].get("pdf_pages") or [])}
            for key, span in by_key.items()
        },
        dict(source),
    )
```

- [ ] **Step 7: Kør testene og se dem bestå**

Run: `/tmp/daa-venv/bin/python -m pytest test_make_boundary_review_1939.py -q`
Expected: PASS, 2 tests

- [ ] **Step 8: Commit**

```bash
git add .claude/skills/daa-extract/scripts/make_boundary_review_1939.py \
        .claude/skills/daa-extract/scripts/test_make_boundary_review_1939.py
git commit -m "feat(1939): view-model for grænsegennemgangen

Bunkeinddelingen porteres af den negative tværgengivelses-kontrol, ikke af
klausul-regnskabet alene, og et signal ud over længdeafvigelse trækker altid
grænsen til individuel vurdering. Den kanoniske globale injektivitetskontrol
kaldes eksplicit: validate_source_bound_evidence validerer kandidater enkeltvis
og beviser ikke globalt fravær af overlap."
```

---

### Task 7: Fladen

**Files:**
- Create: `.claude/skills/daa-extract/scripts/boundary_review_1939_ui.js`
- Test: `web/src/boundaryReview1939Ui.test.ts`

**Interfaces:**
- Consumes: `global.DAAReviewShared` fra Task 1; view-modellen fra Task 6
- Produces: `global.DAABoundaryReview = { init }` hvor `init({data, storage, now, download}) → controller` og `controller = { verdict(boundaryId, verdict, payload) → boolean, note(recordKey, note) → boolean, exportDraft() → object, download() → void }`

De fem domme: `graense_ok`, `graense_forkert` (kræver `begrundelse`), `hul_ejerloest`, `manglende_post`, `kan_ikke_afgoeres` (kræver `begrundelse`).

- [ ] **Step 1: Skriv de fejlende tests**

```ts
// @vitest-environment jsdom
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { expect, it, describe } from 'vitest';

const sharedSource = readFileSync(resolve(
  process.cwd(), '../.claude/skills/daa-extract/scripts/review_ui_shared.js',
), 'utf8');
const uiSource = readFileSync(resolve(
  process.cwd(), '../.claude/skills/daa-extract/scripts/boundary_review_1939_ui.js',
), 'utf8');

function memoryStorage() {
  const values = new Map<string, string>();
  return {
    getItem: (key: string) => values.get(key) ?? null,
    setItem: (key: string, value: string) => values.set(key, value),
    removeItem: (key: string) => values.delete(key),
  };
}

function boundary(id: string, bulk = false) {
  return {
    boundary_id: id, revision: 0,
    before: { baseline_record_key: 'rk-6', candidate_id: 'human:6',
              char_from: 0, char_to: 30 },
    after: { baseline_record_key: 'rk-7', candidate_id: 'human:7',
             char_from: 60, char_to: 90 },
    gap: { char_from: 30, char_to: 60 },
    gap_summary: { tegn: 30, klasser: { record_text: 1, structural_header: 0,
                                        layout: 0, noise: 0 },
                   har_broedtekst: true },
    gap_text: '7 Heinrich til Gottesgabe',
    raw_window: '7. H e i n r i c h til Gottesgabe',
    signals: ['slugt_hoved'],
    bulk_confirmable: bulk,
    before_context: '...s. A. Kapitain ved',
    after_context: 'Prins Georgs Reg., 1703 Sek.major',
    before_navn: 'Christine Augusta',
    after_navn: 'Heinrich',
  };
}

function start(boundaries = [boundary('g-1')]) {
  document.body.innerHTML =
    '<aside><div data-role="sidebar-navigation"></div>'
    + '<p data-role="save-state"></p></aside><main data-role="app"></main>';
  const data = {
    schema_version: 1,
    source: { edition: '1939', profile_version: '1939-v2',
              baseline_sha256: 'a'.repeat(64), calamari_sha256: 'b'.repeat(64),
              raw_ocr_sha256: 'c'.repeat(64), pdf_sha256: 'd'.repeat(64) },
    summary: { graenser: boundaries.length,
               kraever_vurdering: boundaries.filter(b => !b.bulk_confirmable).length,
               hurtig_bekraeftelse: boundaries.filter(b => b.bulk_confirmable).length },
    views: {
      kraever_vurdering: boundaries.filter(b => !b.bulk_confirmable).map(b => b.boundary_id),
      hurtig_bekraeftelse: boundaries.filter(b => b.bulk_confirmable).map(b => b.boundary_id),
    },
    boundaries,
  };
  window.eval(sharedSource);
  window.eval(uiSource);
  return (window as any).DAABoundaryReview.init({
    data, storage: memoryStorage(), now: () => '2026-08-08T10:00:00.000Z',
  });
}

describe('grænsegennemgang', () => {
  it('viser begge sider af skæringen og hvad der ligger imellem', () => {
    start();

    const text = document.querySelector('[data-role="app"]')!.textContent!;
    expect(text).toContain('Christine Augusta');
    expect(text).toContain('Heinrich');
    expect(text).toContain('7 Heinrich til Gottesgabe');
    expect(text).toContain('slugt_hoved');
  });

  it('viser at rå OCR har et hoved Calamari mangler', () => {
    start();

    expect(document.querySelector('[data-role="raw-window"]')!.textContent)
      .toContain('H e i n r i c h');
  });

  it('gemmer en godkendelse og eksporterer den', () => {
    const controller = start();

    expect(controller.verdict('g-1', 'graense_ok')).toBe(true);
    expect(controller.exportDraft().entries).toEqual([{
      boundary_id: 'g-1', revision: 0, verdict: 'graense_ok',
      decided_at: '2026-08-08T10:00:00.000Z',
    }]);
  });

  it('afviser graense_forkert uden begrundelse', () => {
    const controller = start();

    expect(controller.verdict('g-1', 'graense_forkert')).toBe(false);
    expect(controller.verdict('g-1', 'graense_forkert', { begrundelse: 'nr. 7 mangler' }))
      .toBe(true);
  });

  it('kender ikke fase 2-dommene', () => {
    const controller = start();

    expect(controller.verdict('g-1', 'graense_flyttet', { punkt: 30 })).toBe(false);
    expect(controller.verdict('g-1', 'hul_lagt_til_post', { post: 'rk-6' })).toBe(false);
  });

  it('hænger en OCR-note på posten, ikke på grænsen', () => {
    const controller = start();

    expect(controller.note('rk-7', { staar: 'Sopliie', burde: 'Sophie',
                                     raa_bekraefter: true })).toBe(true);
    expect(controller.exportDraft().ocr_noter).toEqual([{
      baseline_record_key: 'rk-7', staar: 'Sopliie', burde: 'Sophie',
      raa_bekraefter: true, noted_at: '2026-08-08T10:00:00.000Z',
    }]);
  });

  it('massebekræfter kun grænser der er portet til det', () => {
    const controller = start([boundary('g-1'), boundary('g-2', true)]);

    expect(controller.verdict('g-1', 'hul_ejerloest')).toBe(true);
    document.querySelector<HTMLButtonElement>('[data-action="bulk-confirm"]')!.click();
    const ids = controller.exportDraft().entries.map((e: any) => e.boundary_id);
    expect(ids).toContain('g-2');
    expect(controller.exportDraft().entries
      .find((e: any) => e.boundary_id === 'g-2').verdict).toBe('hul_ejerloest');
  });

  it('sætter en ugyldig gemt dom i karantæne frem for at kassere den', () => {
    const storage = memoryStorage();
    storage.setItem('daa1939-graenser:v1:{"edition":"1939"}',
                    JSON.stringify({ 'g-ukendt': { verdict: 'graense_ok' } }));
    document.body.innerHTML =
      '<aside><div data-role="sidebar-navigation"></div>'
      + '<p data-role="save-state"></p></aside><main data-role="app"></main>';
    window.eval(sharedSource);
    window.eval(uiSource);
    (window as any).DAABoundaryReview.init({
      data: { schema_version: 1, source: { edition: '1939' },
              summary: { graenser: 1, kraever_vurdering: 1, hurtig_bekraeftelse: 0 },
              views: { kraever_vurdering: ['g-1'], hurtig_bekraeftelse: [] },
              boundaries: [boundary('g-1')] },
      storage, now: () => '2026-08-08T10:00:00.000Z',
    });

    expect(document.querySelector('[data-role="save-state"]')!.textContent)
      .toContain('karantæne');
  });
});
```

- [ ] **Step 2: Kør testene og se dem fejle**

Fra `web/`: `npx vitest run src/boundaryReview1939Ui.test.ts`
Expected: FAIL — filen `boundary_review_1939_ui.js` findes ikke

- [ ] **Step 3: Skriv fladen**

Følg menneskearkets struktur: én IIFE, `init` returnerer en controller, `render` erstatter `[data-role="app"]`. Kernen:

```js
(function (global) {
  'use strict';

  const { element, actionButton, clone, dictionary, downloadJson,
          readStoredDraft, writeStoredDraft } = global.DAAReviewShared;

  const SCHEMA_VERSION = 1;
  // graense_flyttet og hul_lagt_til_post hører til fase 2: de kræver et valgt
  // skæringspunkt og en afløsning af accepteret evidens.
  const VERDICTS = new Set([
    'graense_ok', 'graense_forkert', 'hul_ejerloest', 'manglende_post',
    'kan_ikke_afgoeres',
  ]);
  const REASON_REQUIRED = new Set(['graense_forkert', 'kan_ikke_afgoeres']);
  const SIGNAL_DA = {
    mangler_eget_hoved: 'Posten begynder ikke med sit eget trykte hoved.',
    slugt_hoved: 'Spændet bærer en senere søskendes trykte hoved.',
    nummerspring: 'De trykte numre står i anden rækkefølge end teksten.',
    laengdeafvigelse: 'Spændet er markant kortere eller længere end søskendene.',
  };

  function storageKeyFor(data) {
    return `daa1939-graenser:v${SCHEMA_VERSION}:${JSON.stringify(data.source || {})}`;
  }

  function init({ data, storage = global.localStorage,
                  now = () => new Date().toISOString(), download = () => {} }) {
    const state = {
      data,
      byId: new Map((data.boundaries || []).map(b => [b.boundary_id, b])),
      verdicts: dictionary([]),
      notes: dictionary([]),
      quarantined: dictionary([]),
      selectedId: (data.views.kraever_vurdering[0]
                   || data.views.hurtig_bekraeftelse[0]),
      activeView: 'kraever_vurdering',
      storage,
      storageKey: storageKeyFor(data),
      now,
      message: 'Klar. Ændringer gemmes automatisk lokalt.',
    };
    restore(state);
    const controller = {
      verdict: (id, verdict, payload) => record(state, id, verdict, payload || {}),
      note: (recordKey, note) => addNote(state, recordKey, note),
      exportDraft: () => exportDraft(state),
      download: () => download(exportDraft(state)),
    };
    document.addEventListener('click', event => {
      const action = event.target && event.target.getAttribute
        && event.target.getAttribute('data-action');
      if (!action) return;
      if (VERDICTS.has(action)) {
        const field = document.querySelector('[data-role="reason"]');
        record(state, state.selectedId, action, { begrundelse: field && field.value });
      } else if (action === 'bulk-confirm') {
        state.data.views.hurtig_bekraeftelse.forEach(id => {
          record(state, id, 'hul_ejerloest', {});
        });
      } else if (action === 'export-draft') controller.download();
      else if (action === 'select-boundary') {
        state.selectedId = event.target.getAttribute('data-boundary-id');
        render(state);
      }
    });
    render(state);
    global.DAABoundaryReview.controller = controller;
    return controller;
  }

  global.DAABoundaryReview = { init };
}(typeof globalThis === 'undefined' ? this : globalThis));
```

Udfyld `restore`, `record`, `addNote`, `exportDraft` og `render` efter samme mønster som `human_review_1939_ui.js`:

- `record(state, id, verdict, payload)` → `false` hvis `id` ikke findes, `verdict` ikke er i `VERDICTS`, eller en påkrævet `begrundelse` er tom. Ellers gemmes `{boundary_id, revision, verdict, decided_at, ...begrundelse}` og der kaldes `persist` + `render`.
- `restore(state)` → læs via `readStoredDraft`; en gemt dom hvis `boundary_id` ikke findes i `state.byId`, eller hvis dens `revision` afviger fra grænsens, lægges i `state.quarantined` med en dansk årsag og vises i `[data-role="save-state"]`.
- `exportDraft(state)` → `{schema_version, source, exported_at, entries, ocr_noter}`, hvor `entries` er dommene sorteret efter `boundary_id`.
- `render(state)` → to visninger. `kraever_vurdering` viser den valgte grænse: navn på begge sider, `before_context`, `gap_text` i `[data-role="gap-text"]`, `raw_window` i `[data-role="raw-window"]`, `after_context`, signalerne oversat via `SIGNAL_DA`, fem dom-knapper, et `textarea[data-role="reason"]`, og OCR-notefelterne. `hurtig_bekraeftelse` viser en tabel med én række pr. grænse og en `bulk-confirm`-knap.

- [ ] **Step 4: Kør testene og se dem bestå**

Fra `web/`: `npx vitest run src/boundaryReview1939Ui.test.ts`
Expected: PASS, 8 tests

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/daa-extract/scripts/boundary_review_1939_ui.js \
        web/src/boundaryReview1939Ui.test.ts
git commit -m "feat(1939): flade til grænsegennemgang

Fem domme, ingen af dem ændrer et spænd: fase 1 ser, dømmer og standser.
graense_flyttet og hul_lagt_til_post afvises udtrykkeligt, så fladen ikke
lover en reparation den ikke kan udføre. Rå OCR-vinduet vises ved siden af
Calamari-hullet, fordi det er dér et tabt hoved er synligt."
```

---

### Task 8: Generator-CLI og manuel verifikation

**Files:**
- Modify: `.claude/skills/daa-extract/scripts/make_boundary_review_1939.py` (tilføj `main()` og HTML-udskrivning)
- Test: `.claude/skills/daa-extract/scripts/test_make_boundary_review_1939.py`

**Interfaces:**
- Consumes: alt fra Task 1-7
- Produces: CLI `--anchored --queue-manifest --baseline --calamari --raw --source-manifest [--verdicts] --out`

- [ ] **Step 1: Skriv de fejlende tests**

```python
import hashlib
import json
import sys

import pytest

import make_boundary_review_1939 as subject


def _write_inputs(tmp_path):
    calamari = tmp_path / "calamari.txt"
    raw = tmp_path / "raw.txt"
    calamari.write_text("### PAGE 0001 ###\n1. Anders, f. 1900.\n", encoding="utf-8")
    raw.write_text("### PAGE 0001 ###\n1. Anders, f. 1900.\n", encoding="utf-8")
    baseline = tmp_path / "baseline.json"
    baseline.write_text(json.dumps([{
        "record_key": "rk-a", "navn": "Anders", "sider": "496", "_orig_nr": 1,
        "_gruppe_nr": 1, "_v2_lokal_id": "I.1",
    }]), encoding="utf-8")
    source = {
        "edition": "1939", "profile_version": "1939-v2",
        "baseline_sha256": hashlib.sha256(baseline.read_bytes()).hexdigest(),
        "calamari_sha256": hashlib.sha256(calamari.read_bytes()).hexdigest(),
        "raw_ocr_sha256": hashlib.sha256(raw.read_bytes()).hexdigest(),
        "pdf_sha256": "d" * 64,
    }
    source_manifest = tmp_path / "source.json"
    source_manifest.write_text(json.dumps({"schema_version": 1, "source": source}),
                               encoding="utf-8")
    queue = tmp_path / "queue.json"
    queue.write_text(json.dumps({"schema_version": 1, "source": source, "entries": [{
        "baseline_record_key": "rk-a", "queue_class": "human_required",
        "reason_code": "no_candidate", "reason_da": "ingen kandidat",
    }]}), encoding="utf-8")
    anchored = tmp_path / "anchored.json"
    anchored.write_text(json.dumps({"human:a": {
        "baseline_record_key": "rk-a", "candidate": {
            "candidate_id": "human:a", "postklasse": "nummereret",
            "calamari_span": {"char_from": 18, "char_to": 37},
            "pdf_pages": [496],
            "approval": {"kind": "human_approved_span_v1",
                         "calamari_excerpt_sha256": "e" * 64}}}}),
        encoding="utf-8")
    return baseline, queue, source_manifest, calamari, raw, anchored


def _argv(baseline, queue, source, calamari, raw, anchored, out):
    return ["make_boundary_review_1939.py", "--baseline", str(baseline),
            "--queue-manifest", str(queue), "--source-manifest", str(source),
            "--calamari", str(calamari), "--raw", str(raw),
            "--anchored", str(anchored), "--out", str(out)]


def test_main_writes_a_self_contained_page(tmp_path, monkeypatch):
    inputs = _write_inputs(tmp_path)
    out = tmp_path / "graenser.html"
    monkeypatch.setattr(sys, "argv", _argv(*inputs, out))

    assert subject.main() == 0

    rendered = out.read_text(encoding="utf-8")
    assert "window.DAABoundaryReview.init(" in rendered
    assert "DAAReviewShared" in rendered
    assert "const DATA=" in rendered


def test_main_refuses_a_changed_calamari_file(tmp_path, monkeypatch):
    baseline, queue, source, calamari, raw, anchored = _write_inputs(tmp_path)
    calamari.write_text("ændret kilde", encoding="utf-8")
    out = tmp_path / "graenser.html"
    monkeypatch.setattr(sys, "argv",
                        _argv(baseline, queue, source, calamari, raw, anchored, out))

    with pytest.raises(ValueError, match="calamari hash"):
        subject.main()
    assert not out.exists()


def test_main_refuses_to_overwrite_an_existing_page(tmp_path, monkeypatch):
    inputs = _write_inputs(tmp_path)
    out = tmp_path / "graenser.html"
    out.write_text("findes", encoding="utf-8")
    monkeypatch.setattr(sys, "argv", _argv(*inputs, out))

    with pytest.raises(FileExistsError):
        subject.main()


def test_main_embeds_an_earlier_verdict_export(tmp_path, monkeypatch):
    baseline, queue, source, calamari, raw, anchored = _write_inputs(tmp_path)
    model_source = json.loads(source.read_text(encoding="utf-8"))["source"]
    verdicts = tmp_path / "domme.json"
    verdicts.write_text(json.dumps({
        "schema_version": 1, "source": model_source,
        "exported_at": "2026-08-08T10:00:00.000Z",
        "entries": [], "ocr_noter": [],
    }), encoding="utf-8")
    out = tmp_path / "graenser.html"
    monkeypatch.setattr(sys, "argv", _argv(
        baseline, queue, source, calamari, raw, anchored, out) + [
        "--verdicts", str(verdicts)])

    assert subject.main() == 0
    assert '"tidligere_domme"' in out.read_text(encoding="utf-8")
```

- [ ] **Step 2: Kør testene og se dem fejle**

Run: `/tmp/daa-venv/bin/python -m pytest test_make_boundary_review_1939.py -q`
Expected: FAIL — `AttributeError: module has no attribute 'main'`

- [ ] **Step 3: Skriv CLI'en**

Tilføj til `make_boundary_review_1939.py` — HTML-stilen kopieres fra `make_human_review_1939.py`'s `HTML_PREFIX`/`HTML_SUFFIX` med `DAABoundaryReview` i stedet for `DAA1939Review` og `1939-graensegennemgang.json` som eksportnavn:

```python
UI_PATH = Path(__file__).with_name("boundary_review_1939_ui.js")
SHARED_UI_PATH = Path(__file__).with_name("review_ui_shared.js")


def _source_from_manifest(value: object) -> dict:
    if not isinstance(value, dict):
        raise BoundaryError("source manifest skal være en mapping")
    source = value.get("source", value)
    if not isinstance(source, dict):
        raise BoundaryError("source manifest source skal være en mapping")
    return source


def _automatic_candidates(queue: Mapping) -> dict:
    entries = queue.get("entries")
    if not isinstance(entries, list):
        raise BoundaryError("queue manifest entries skal være en liste")
    return {
        entry["baseline_record_key"]: {
            "baseline_record_key": entry["baseline_record_key"],
            "candidate": entry["candidate"],
        }
        for entry in entries
        if isinstance(entry, Mapping) and entry.get("queue_class") == "auto_resolved"
        and isinstance(entry.get("candidate"), Mapping)
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    for name in ("--baseline", "--queue-manifest", "--source-manifest",
                 "--calamari", "--raw", "--anchored", "--out"):
        parser.add_argument(name, type=Path, required=True)
    parser.add_argument("--verdicts", type=Path,
                        help="tidligere eksport af grænse-domme")
    args = parser.parse_args()
    if args.out.exists():
        raise FileExistsError(args.out)
    baseline_bytes = args.baseline.read_bytes()
    calamari_bytes = args.calamari.read_bytes()
    raw_bytes = args.raw.read_bytes()
    source = _source_from_manifest(
        json.loads(args.source_manifest.read_text(encoding="utf-8")))
    for label, data, field in (
        ("baseline", baseline_bytes, "baseline_sha256"),
        ("calamari", calamari_bytes, "calamari_sha256"),
        ("raw OCR", raw_bytes, "raw_ocr_sha256"),
    ):
        if source.get(field) != hashlib.sha256(data).hexdigest():
            raise ValueError(f"{label} hash matcher ikke source manifest")
    queue = json.loads(args.queue_manifest.read_text(encoding="utf-8"))
    if queue.get("source") != source:
        raise ValueError("queue source hashes matcher ikke source manifest")
    records = {
        record["record_key"]: record
        for record in json.loads(baseline_bytes)
        if isinstance(record, Mapping) and isinstance(record.get("record_key"), str)
    }
    calamari_text = calamari_bytes.decode("utf-8")
    spans = collect_accepted_spans(
        json.loads(args.anchored.read_text(encoding="utf-8")),
        _automatic_candidates(queue),
    )
    clauses = _clauses_for(calamari_text)
    model = build_boundary_view_model(
        spans, clauses, calamari_text, raw_bytes.decode("utf-8"), records, source,
    )
    if args.verdicts:
        earlier = json.loads(args.verdicts.read_text(encoding="utf-8"))
        if earlier.get("source") != source:
            raise ValueError("tidligere domme matcher ikke source manifest")
        model["tidligere_domme"] = earlier
    payload = json.dumps(model, ensure_ascii=False).replace("<", "\\u003c")
    with args.out.open("x", encoding="utf-8") as handle:
        handle.write(HTML_PREFIX)
        handle.write(payload)
        handle.write(";\n")
        handle.write(SHARED_UI_PATH.read_text(encoding="utf-8"))
        handle.write("\n")
        handle.write(UI_PATH.read_text(encoding="utf-8"))
        handle.write("\n")
        handle.write(HTML_SUFFIX)
    print(f"{model['summary']['graenser']} grænser · "
          f"{model['summary']['kraever_vurdering']} kræver vurdering · "
          f"{model['summary']['hurtig_bekraeftelse']} hurtig bekræftelse")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

`_clauses_for(text)` udleder regnskabet i processen. `segment.py` skriver det til en fil via `--emit-evidence-ledger`; kald samme kodevej med en midlertidig fil under `tempfile.TemporaryDirectory()`, læs JSON'en, og returnér `clauses`-listen. Undertryk `stdout`/`stderr` med `contextlib.redirect_stdout(io.StringIO())` som `make_human_review_1939.py` gør omkring sit segmenteringskald.

- [ ] **Step 4: Kør testene og se dem bestå**

Run: `/tmp/daa-venv/bin/python -m pytest test_make_boundary_review_1939.py -q`
Expected: PASS, 6 tests

- [ ] **Step 5: Kør hele den berørte suite**

Run: `/tmp/daa-venv/bin/python -m pytest test_boundary_spans_1939.py test_boundary_signals_1939.py test_make_boundary_review_1939.py test_make_human_review_1939.py test_detect_boundary_defects_1939.py test_anchor_review_choices_1939.py test_prepare_review_queue_1939.py -q`
Expected: PASS

Fra `web/`: `VITE_SUPABASE_URL=https://example.supabase.co VITE_SUPABASE_ANON_KEY=dummy npx vitest run`
Expected: PASS — menneskearkets 88 tests skal stå uændret

- [ ] **Step 6: Manuel verifikationskørsel mod de rigtige data**

Dette er verifikation, ikke en test. Kør mod den aktuelle forankring:

```bash
W=/Users/johanreventlow/TypeScript/danmarksadelsaarbog/work_1939_stamtavle
P=work/task19-1939-pilot
python3 .claude/skills/daa-extract/scripts/make_boundary_review_1939.py \
  --baseline $W/clean_1939_v2.json \
  --queue-manifest $P/review-queue-manifest-v2-run-e.json \
  --source-manifest $P/review-queue-manifest-v2-run-e.json \
  --calamari $W/full_ocr_calamari_r6_clean.txt \
  --raw $W/raw.txt \
  --anchored $P/human-anchored-candidates-v3-run-c.json \
  --out $P/menneskeark-graenser-v1.html
```

Kontrollér tre ting og skriv tallene i commit-beskeden:

1. antal grænser svarer til antal accepterede spænd plus én
2. `kræver vurdering` er ikke nul — er den nul, er porten for løs, ikke dataene rene
3. de to kendte grænsefejl fra `graensefejl-v3.json` (nr. 6 → nr. 7 side 535, nr. 3 → nr. 5 side 528) ligger i `kræver vurdering`, ikke i hurtig bekræftelse. Er de i den forkerte bunke, er signalerne koblet forkert til spændene.

Filen må ikke committes — `work/` er gitignoreret og indeholder PII.

- [ ] **Step 7: Commit**

```bash
git add .claude/skills/daa-extract/scripts/make_boundary_review_1939.py \
        .claude/skills/daa-extract/scripts/test_make_boundary_review_1939.py
git commit -m "feat(1939): CLI til grænsegennemgangen

Alle tre kildefiler hash-valideres mod source-manifestet før noget skrives, og
--out nægter at overskrive. En tidligere eksport kan indlejres, fordi
file://-lageret hænger på den enkelte fil og valgene derfor ikke følger med til
en ny filnavn af sig selv.

Manuel kørsel mod de rigtige data: <indsæt de tre tal fra step 6>."
```

---

## Selv-review

**Spec-dækning.** Hver sektion i spec'ens fase 1 har en task: delt UI-modul (1), spænd og grænser med revision og rande (2), klausul-regnskab (3), negativ tværgengivelses-port (4), de fire spænd-signaler (5), bunker og global injektivitet (6), fladen med fem domme og OCR-noter (7), CLI med hash-validering og indlejret eksport (8). Fase 2 er ude af planen, som spec'en foreskriver.

**Ikke dækket med vilje:** spec'ens fase 2 i sin helhed — afløsningsoperationen, skæringsvinduet, invalideringsgrafen og `pdf_pages` efter en flytning. De hører i en senere plan, hvis fase 1's tal berettiger dem.

**Kendt afhængighed uden for planen:** `human-anchored-candidates-v3-run-c.json` er den aktuelle forankring. Har redaktøren siden eksporteret en nyere kladde, skal forankringen køres igen først, ellers dækker grænserne ikke de nyeste valg.
