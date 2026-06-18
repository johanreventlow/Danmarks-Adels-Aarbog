# Auto-eskalering af flaggede udtræk Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Flaggede udtræks-poster (blokerende R1-R7 + recoverable R8-misses) eskaleres automatisk til Opus, re-valideres, og dem der nu består loades med proveniens-stempel — kun stadig-fejlende + en diff-rapport når et menneske.

**Architecture:** Deterministisk Python bærer plumbingen: `validate.py` emitterer en eskalerings-worklist fra udskiftelige detektorer; en ny `escalate_merge.py` re-validerer Opus-output og merger (REPLACE for R8-poster der allerede loadede, APPEND for blokerede). LLM-gen-kørslen er agent-orkestreret (SKILL.md trin ④b), som det nuværende udtræk. Eskalerede konklusioner stemples `blaastemplet_af="Opus-escalated"` ved load.

**Tech Stack:** Python 3.9 (stdlib `unittest` — pytest IKKE installeret), R (DBI/RPostgres). Genbruger funktioner fra `validate.py`.

## Global Constraints

- **Bounded: ÉT eskalerings-forsøg per post.** Stadig-fejlende → menneske (review.json). Ingen løkke.
- **Worklist er et interface:** triggeren hardcodes ikke; detektorer (R1-R7 blokerende, R8 recoverable) fylder den. Forkert-felt-detektor er en navngiven, IKKE-wiret udvidelse i denne plan.
- **Trigger = blokerende issues ELLER R8-advisory.** V9 (vocab-drift) og R2/R3-advisory udløser IKKE eskalering.
- **Promote-kriterium:** Opus-output må kun auto-loades hvis det (a) har 0 blokerende brud OG (b) ikke introducerer FLERE R8-misses end Sonnet-snapshottet havde.
- **REPLACE vs APPEND:** R8-poster ligger allerede i clean.json (de loadede) → opdatér eksisterende. Blokerede poster var ikke i clean.json → tilføj.
- **Snapshot FØR overskrivning:** Sonnet-output gemmes som `work/extracted/<post>.sonnet.json` før Opus skriver — diffen kræver begge versioner under samme skema.
- **Proveniens-stempel:** promoverede eskalerede poster markeres `_escalated: true`; `load_daa.R` sætter `blaastemplet_af="Opus-escalated"` for deres konklusioner.
- **Test-runner:** `python3 -m unittest discover -s .claude/skills/daa-extract/scripts -p 'test_*.py'`. Tests bor ved siden af scriptet.
- **Filsti-base:** `.claude/skills/daa-extract/scripts/` (forkortet `S/`).
- **Commits:** Conventional Commits, dansk, ingen Claude-attribution. Branch `feat/auto-eskalering` (findes allerede; spec er committet der).
- **Out of scope:** forkert-felt-detektor; standalone API-script; selve Task 8-re-kørslen (bruger-gated).

---

### Task 1: `validate.py` — emit eskalerings-worklist

**Files:**
- Modify: `S/validate.py` (ny `escalation_entry()` nær top; `--escalate`-arg + opsamling i `main()`)
- Modify: `S/test_validate.py` (ny testklasse)

**Interfaces:**
- Consumes: `validate()` returnerer `(issues, advisory)` (eksisterende).
- Produces: `escalation_entry(rec: dict, issues: list, advisory: list) -> dict | None` — returnerer `{linje, nr, nr_label, grunde}` hvis posten skal eskaleres (blokerende ELLER R8), ellers `None`. `main()` skriver listen til `--escalate <fil>`.

- [ ] **Step 1: Skriv failing tests**

```python
# i S/test_validate.py
class TestEscalationEntry(unittest.TestCase):
    def test_blokerende_eskaleres(self):
        rec = {"linje": "I", "nr": 5, "nr_label": "5"}
        e = validate.escalation_entry(rec, ["R1: årstal ..."], [])
        self.assertIsNotNone(e)
        self.assertEqual(e["nr_label"], "5")
        self.assertEqual(e["grunde"], ["R1: årstal ..."])

    def test_r8_miss_eskaleres(self):
        rec = {"linje": "I", "nr": 5, "nr_label": "5"}
        e = validate.escalation_entry(rec, [], ["R8: prosa nævner død, men intet død-fakta"])
        self.assertIsNotNone(e)
        self.assertEqual(e["grunde"], ["R8: prosa nævner død, men intet død-fakta"])

    def test_ren_post_eskaleres_ikke(self):
        self.assertIsNone(validate.escalation_entry({"linje": "I", "nr": 5}, [], []))

    def test_v9_vocab_eskalerer_ikke(self):
        e = validate.escalation_entry({"linje": "I", "nr": 5}, [], ["V9: ukendt faktatype"])
        self.assertIsNone(e)
```

- [ ] **Step 2: Kør, verificér FAIL** (`has no attribute 'escalation_entry'`).

Run: `python3 -m unittest discover -s .claude/skills/daa-extract/scripts -p 'test_*.py' -v`

- [ ] **Step 3: Implementér `escalation_entry` (nær de andre helpers, ~efter `derive_aegteskaber`)**

```python
def escalation_entry(rec, issues, advisory):
    """Worklist-post hvis posten skal eskaleres: blokerende brud ELLER R8-miss.
    V9/R2/R3-advisory udløser IKKE eskalering. Returnér None hvis ren."""
    r8 = [a for a in (advisory or []) if a.startswith('R8')]
    if issues or r8:
        return {
            'linje': rec.get('linje'),
            'nr': rec.get('nr'),
            'nr_label': rec.get('nr_label') or str(rec.get('nr')),
            'grunde': list(issues or []) + r8,
        }
    return None
```

- [ ] **Step 4: Wire i `main()` — nyt arg + opsamling**

I `main()`, tilføj argument (efter de andre `add_argument`):
```python
    ap.add_argument('--escalate', help='skriv eskalerings-worklist (blokerende + R8) hertil')
```
I fil-loopet, lige efter `issues, advisory = validate(rec, src, known_by_linje)`:
```python
        ent = escalation_entry(rec, issues, advisory)
        if ent:
            escalation.append(ent)
```
Initialisér `escalation = []` sammen med `clean, review, advisories = [], [], 0`. Efter loopet, ved de andre `json.dump`-kald:
```python
    if args.escalate:
        json.dump(escalation, open(args.escalate, 'w', encoding='utf-8'), ensure_ascii=False, indent=2)
```

- [ ] **Step 5: Kør tests, verificér PASS (alle, inkl. de 15 eksisterende).**

Run: `python3 -m unittest discover -s .claude/skills/daa-extract/scripts -p 'test_*.py' -v`

- [ ] **Step 6: Røgtest mod korpus (worklisten dannes)**

Run:
```bash
cd /Users/johanreventlow/TypeScript/danmarksadelsaarbog
python3 .claude/skills/daa-extract/scripts/validate.py work/posts_full.json data/extracted-2026-06-18/ \
  --clean /tmp/c.json --review /tmp/r.json --escalate /tmp/esc.json
python3 -c "import json; e=json.load(open('/tmp/esc.json')); print('worklist:', len(e), 'poster')"
```
Expected: et heltal (~24 — R8-dødsmisses på nuværende data, 0 blokerende).

- [ ] **Step 7: Commit**

```bash
git add .claude/skills/daa-extract/scripts/validate.py .claude/skills/daa-extract/scripts/test_validate.py
git commit -m "feat(daa-extract): validate.py emitterer eskalerings-worklist (--escalate)"
```

---

### Task 2: `escalate_merge.py` — re-validér Opus-output + merge (promote/keep)

**Files:**
- Create: `S/escalate_merge.py`
- Create: `S/test_escalate_merge.py`
- Modify: `S/validate.py` (tilføj `_escalated` til `ALLOWED_TOP` som forsikring mod R5)

**Interfaces:**
- Consumes: `validate.validate(rec, src, known_by_linje) -> (issues, advisory)`; `validate.norm`.
- Produces:
  - `count_r8(advisory: list) -> int`
  - `decide(reextracted: dict, snapshot: dict, src: dict, known_by_linje: dict) -> tuple[bool, list, list]` — returnerer `(promote: bool, issues, advisory)`. `promote=True` hvis 0 blokerende OG `count_r8(advisory) <= count_r8(snapshot_advisory)`.
  - `merge_escalated(escalation, reext_by_key, snap_by_key, src_by_key, known_by_linje, clean, review) -> tuple[list, list, list]` — returnerer `(new_clean, new_review, promoted_keys)`. Promoverede poster får `_escalated=True`; REPLACE hvis nøglen findes i clean, ellers APPEND. Stadig-fejlende sikres i review.

- [ ] **Step 1: Skriv failing tests**

```python
# S/test_escalate_merge.py
import os, sys, unittest
sys.path.insert(0, os.path.dirname(__file__))
import escalate_merge as em

SRC = {("I", "5"): {"raw_text": "Iwan † 1261. Gift med Sofie.", "linje": "I", "nr": 5}}
KEY = ("I", "5")

def rec(**kw):
    base = {"linje": "I", "nr": 5, "nr_label": "5", "navn": "Iwan", "facts": [], "aegteskaber": []}
    base.update(kw); return base

class TestDecide(unittest.TestCase):
    def test_promote_naar_r8_forbedres(self):
        # snapshot missede død; reextracted fandt den -> R8 falder -> promote
        snap = rec(facts=[])
        reext = rec(facts=[{"faktatype": "død", "date_raw": "† 1261"}])
        promote, issues, adv = em.decide(reext, snap, SRC[KEY], {})
        self.assertTrue(promote)

    def test_afvis_naar_nyt_r8_introduceres(self):
        # reextracted taber en død snapshot havde -> R8 stiger -> afvis
        snap = rec(facts=[{"faktatype": "død", "date_raw": "† 1261"}])
        reext = rec(facts=[])
        promote, issues, adv = em.decide(reext, snap, SRC[KEY], {})
        self.assertFalse(promote)

    def test_afvis_naar_blokerende(self):
        reext = rec(facts=[{"faktatype": "død", "date_raw": "† 1999"}])  # 1999 ikke i prosa -> R1
        promote, issues, adv = em.decide(reext, rec(), SRC[KEY], {})
        self.assertFalse(promote)

class TestMerge(unittest.TestCase):
    def _common(self, reext):
        esc = [{"linje": "I", "nr": 5, "nr_label": "5", "grunde": ["R8: ..."]}]
        return em.merge_escalated(esc, {KEY: reext}, {KEY: rec()}, SRC, {}, clean=[], review=[])

    def test_append_naar_ikke_i_clean(self):
        reext = rec(facts=[{"faktatype": "død", "date_raw": "† 1261"}])
        new_clean, new_review, promoted = self._common(reext)
        self.assertEqual(len(new_clean), 1)
        self.assertTrue(new_clean[0]["_escalated"])
        self.assertIn(KEY, promoted)

    def test_replace_naar_allerede_i_clean(self):
        reext = rec(facts=[{"faktatype": "død", "date_raw": "† 1261"}])
        esc = [{"linje": "I", "nr": 5, "nr_label": "5", "grunde": ["R8: ..."]}]
        old = rec(facts=[])  # gammel ufuldstændig version i clean
        new_clean, new_review, promoted = em.merge_escalated(
            esc, {KEY: reext}, {KEY: rec()}, SRC, {}, clean=[old], review=[])
        self.assertEqual(len(new_clean), 1)                       # opdateret, ikke tilføjet
        self.assertEqual(len(new_clean[0]["facts"]), 1)           # Opus-output vandt
        self.assertTrue(new_clean[0]["_escalated"])
```

- [ ] **Step 2: Kør, verificér FAIL** (`No module named 'escalate_merge'`).

- [ ] **Step 3: Implementér `escalate_merge.py`**

```python
#!/usr/bin/env python3
"""Eskalerings-merge (trin ④b-plumbing): re-validér Opus-gen-udtræk og merge.

Promote-kriterium: 0 blokerende brud OG ikke flere R8-misses end Sonnet-snapshottet.
Promoverede poster markeres _escalated=True (load_daa.R stamper blaastemplet_af).
REPLACE hvis nøglen allerede er i clean (R8-post der loadede); ellers APPEND.
Stadig-fejlende sikres i review.json. Diff-rapport: se gen_diff() (Task 3).
"""
import os, sys, json, argparse
sys.path.insert(0, os.path.dirname(__file__))
import validate


def count_r8(advisory):
    return sum(1 for a in (advisory or []) if a.startswith('R8'))


def _key(rec):
    return (rec.get('linje'), rec.get('nr_label') or str(rec.get('nr')))


def decide(reextracted, snapshot, src, known_by_linje):
    """(promote, issues, advisory) for et Opus-gen-udtræk."""
    issues, advisory = validate.validate(reextracted, src, known_by_linje)
    _, snap_adv = validate.validate(snapshot, src, known_by_linje)
    promote = (not issues) and count_r8(advisory) <= count_r8(snap_adv)
    return promote, issues, advisory


def merge_escalated(escalation, reext_by_key, snap_by_key, src_by_key, known_by_linje, clean, review):
    """Returnér (new_clean, new_review, promoted_keys)."""
    clean_by_key = {_key(r): r for r in clean}
    review_keys = {(r.get('linje'), r.get('nr_label') or str(r.get('nr'))) for r in review}
    promoted = []
    for ent in escalation:
        key = (ent['linje'], ent['nr_label'])
        reext = reext_by_key.get(key)
        if reext is None:
            continue
        snap = snap_by_key.get(key, reext)
        src = src_by_key.get(key)
        promote, issues, advisory = decide(reext, snap, src, known_by_linje)
        if promote:
            # flet autoritativ narrativ ind som validate.main() gør, + marker
            merged = dict(reext)
            if src:
                merged['narrative'] = src['raw_text']
            merged['_escalated'] = True
            clean_by_key[key] = merged          # REPLACE el. APPEND (samme operation på dict)
            review_keys.discard(key)
            promoted.append(key)
        else:
            review_keys.add(key)
            clean_by_key.pop(key, None)         # en R8-post der nu fejler må IKKE blive i clean
    new_clean = list(clean_by_key.values())
    # genopbyg review: behold eksisterende der ikke blev promoveret + nye fejlende
    new_review = [r for r in review if _key(r) in review_keys]
    for key in review_keys:
        if not any(_key(r) == key for r in new_review):
            r = reext_by_key.get(key)
            if r is not None:
                new_review.append(r)
    return new_clean, new_review, promoted


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('posts'); ap.add_argument('reextracted_dir'); ap.add_argument('snapshot_dir')
    ap.add_argument('escalation'); ap.add_argument('clean'); ap.add_argument('review')
    ap.add_argument('--diff', help='skriv diff-rapport (markdown) hertil')
    args = ap.parse_args()
    posts = json.load(open(args.posts, encoding='utf-8'))
    src_by_key = {(p['linje'], p.get('nr_label', str(p['nr']))): p for p in posts}
    known_by_linje = {}
    for p in posts:
        known_by_linje.setdefault(p['linje'], set()).add(p['nr'])
    escalation = json.load(open(args.escalation, encoding='utf-8'))

    def load_dir(d):
        out = {}
        for fn in os.listdir(d):
            if fn.endswith('.sonnet.json'): continue
            if fn.endswith('.json'):
                r = json.load(open(os.path.join(d, fn), encoding='utf-8'))
                out[(r.get('linje'), r.get('nr_label') or str(r.get('nr')))] = r
        return out

    def load_snaps(d):
        out = {}
        for fn in os.listdir(d):
            if fn.endswith('.sonnet.json'):
                r = json.load(open(os.path.join(d, fn), encoding='utf-8'))
                out[(r.get('linje'), r.get('nr_label') or str(r.get('nr')))] = r
        return out

    reext = load_dir(args.reextracted_dir)
    snaps = load_snaps(args.snapshot_dir)
    clean = json.load(open(args.clean, encoding='utf-8'))
    review = json.load(open(args.review, encoding='utf-8'))
    new_clean, new_review, promoted = merge_escalated(escalation, reext, snaps, src_by_key, known_by_linje, clean, review)
    json.dump(new_clean, open(args.clean, 'w', encoding='utf-8'), ensure_ascii=False, indent=2)
    json.dump(new_review, open(args.review, 'w', encoding='utf-8'), ensure_ascii=False, indent=2)
    if args.diff:
        gen_diff(escalation, reext, snaps, set(promoted), args.diff)   # Task 3
    print(f'[escalate] {len(promoted)} promoveret, {len(new_review)} stadig i review', file=sys.stderr)


if __name__ == '__main__':
    main()
```

(`gen_diff` tilføjes i Task 3; `main()` kalder den men Task 2's tests rører kun `decide`/`merge_escalated`.)

- [ ] **Step 4: Tilføj `_escalated` til `ALLOWED_TOP` i `validate.py`** (forsikring mod R5 hvis merged clean.json nogensinde re-valideres)

```python
ALLOWED_TOP = {"linje", "nr", "nr_label", "usikker", "navn", "tilnavn", "koen",
               "facts", "godser", "embeder", "aegteskaber", "boern",
               "begivenheder", "narrative", "_escalated"}
```

- [ ] **Step 5: Kør tests, verificér PASS.**

Run: `python3 -m unittest discover -s .claude/skills/daa-extract/scripts -p 'test_*.py' -v`

- [ ] **Step 6: Commit**

```bash
git add .claude/skills/daa-extract/scripts/escalate_merge.py .claude/skills/daa-extract/scripts/test_escalate_merge.py .claude/skills/daa-extract/scripts/validate.py
git commit -m "feat(daa-extract): escalate_merge — re-validér + promote/keep Opus-eskalering"
```

---

### Task 3: `escalate_merge.py` — diff-rapport (Sonnet vs Opus)

**Files:**
- Modify: `S/escalate_merge.py` (tilføj `gen_diff()`)
- Modify: `S/test_escalate_merge.py` (testklasse)

**Interfaces:**
- Consumes: `escalation` (worklist), `reext_by_key`, `snap_by_key`, `promoted` (set af nøgler).
- Produces: `field_diff(snapshot: dict, reextracted: dict) -> dict` — `{felt: (gammel, ny)}` for felter der ændrede sig. `gen_diff(escalation, reext, snaps, promoted, path)` skriver markdown.

- [ ] **Step 1: Skriv failing tests**

```python
# i S/test_escalate_merge.py
class TestDiff(unittest.TestCase):
    def test_field_diff_fanger_aendring(self):
        snap = {"navn": "Iwan", "facts": []}
        reext = {"navn": "Iwan", "facts": [{"faktatype": "død"}]}
        d = em.field_diff(snap, reext)
        self.assertIn("facts", d)
        self.assertNotIn("navn", d)   # uændret felt udelades

    def test_field_diff_tom_naar_identisk(self):
        self.assertEqual(em.field_diff({"navn": "A"}, {"navn": "A"}), {})
```

- [ ] **Step 2: Kør, verificér FAIL** (`has no attribute 'field_diff'`).

- [ ] **Step 3: Implementér `field_diff` + `gen_diff`**

```python
def field_diff(snapshot, reextracted):
    """{felt: (gammel, ny)} for felter der ændrede sig (ignorér _escalated/narrative)."""
    out = {}
    keys = set(snapshot or {}) | set(reextracted or {})
    keys -= {'_escalated', 'narrative'}
    for k in keys:
        old, new = (snapshot or {}).get(k), (reextracted or {}).get(k)
        if old != new:
            out[k] = (old, new)
    return out


def gen_diff(escalation, reext_by_key, snap_by_key, promoted, path):
    lines = ['# Eskalerings-diff (Sonnet → Opus)', '']
    for ent in escalation:
        key = (ent['linje'], ent['nr_label'])
        d = field_diff(snap_by_key.get(key), reext_by_key.get(key))
        status = 'PROMOVERET' if key in promoted else 'stadig i review'
        lines.append(f'## {ent["linje"]}-{ent["nr_label"]} ({status})')
        lines.append(f'Grunde: {", ".join(ent.get("grunde", []))}')
        if not d:
            lines.append('_ingen feltændring_')
        for felt, (old, new) in sorted(d.items()):
            lines.append(f'- **{felt}**: `{old}` → `{new}`')
        lines.append('')
    open(path, 'w', encoding='utf-8').write('\n'.join(lines))
```

- [ ] **Step 4: Kør tests, verificér PASS.**

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/daa-extract/scripts/escalate_merge.py .claude/skills/daa-extract/scripts/test_escalate_merge.py
git commit -m "feat(daa-extract): eskalerings-diff-rapport (Sonnet vs Opus per felt)"
```

---

### Task 4: `load_daa.R` — stempl eskalerede konklusioner

**Files:**
- Modify: `.claude/skills/daa-extract/scripts/load_daa.R` (`add_conclusion`-default + mutable `current_by` + sæt per record)

**Interfaces:**
- Consumes: `rec[["_escalated"]]` på clean.json-records (sat af `escalate_merge`).
- Produces: konklusioner for eskalerede records får `blaastemplet_af="Opus-escalated"`.

- [ ] **Step 1: Indfør mutable `current_by`** (efter `udgave` er defineret, før load-loopene ~linje 158)

```r
current_by <- udgave   # konklusions-proveniens; sættes per record
```

- [ ] **Step 2: Lad `add_conclusion` læse den (linje 71)**

```r
add_conclusion <- function(tt, tid, chosen, status="afklaret", by=current_by) push("conclusion", list(id=nid("conclusion"), target_type=tt, target_id=tid, valgt_assertion_id=chosen, status=status, blaastemplet_af=by))
```
(Lazy default: `by=current_by` evalueres ved kald → læser den aktuelle værdi.)

- [ ] **Step 3: Sæt `current_by` ved hver record i BEGGE pass** (pass 1 ~linje 176, pass 2 ~linje 199, lige inde i `for (rec in clean) {`)

```r
    current_by <- if (isTRUE(rec[["_escalated"]])) "Opus-escalated" else udgave
```

- [ ] **Step 4: Syntaks-tjek**

Run: `Rscript -e 'invisible(parse(file=".claude/skills/daa-extract/scripts/load_daa.R")); cat("parse ok\n")'`
Expected: `parse ok`

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/daa-extract/scripts/load_daa.R
git commit -m "feat(daa-extract): stempl eskalerede konklusioner blaastemplet_af=Opus-escalated"
```

---

### Task 5: `SKILL.md` — nyt trin ④b (agent-orkestrering)

**Files:**
- Modify: `.claude/skills/daa-extract/SKILL.md` (indsæt trin ④b mellem ④ validering og ⑤ load; opdatér pipeline-diagrammet linje 41-43)

**Interfaces:** Ingen kode — orkestrerings-prosa for den agent der kører skill'en.

- [ ] **Step 1: Indsæt trin ④b efter ④-blokken**

```markdown
### ④b Auto-eskalering (agent-orkestreret, ÉT forsøg)

Kør `validate.py` med `--escalate work/escalation.json`. For HVER post i den worklist:

1. **Snapshot Sonnet-output FØR overskrivning:** kopiér `work/extracted/<linje>-<nr>.json`
   til `work/extracted/<linje>-<nr>.sonnet.json`.
2. **Dispatch en Opus-subagent** med samme udtræks-prompt (trin ③) PLUS postens
   `grunde` fra worklisten ("tidligere forsøg missede/brød: …"). Overskriv
   `work/extracted/<linje>-<nr>.json`.

Kør derefter merge-plumbingen (deterministisk):
```bash
python3 scripts/escalate_merge.py work/posts.json work/extracted/ work/extracted/ \
  work/escalation.json work/clean.json work/review.json --diff work/escalation-diff.md
```
Den re-validerer hvert Opus-output: består det (0 blokerende OG ikke flere R8-misses
end Sonnet) → merges ind i `clean.json` (markeret `_escalated`); ellers → `review.json`.

**Overflad resultatet:** "N eskaleret, M reddet/promoveret, K stadig i review — se
`work/escalation-diff.md`." Stadig-fejlende kræver menneske. ÉT forsøg per post —
gen-eskalér ikke en post der allerede er prøvet med Opus.
```

- [ ] **Step 2: Opdatér pipeline-diagrammet (linje 41-43)** så ④b nævnes mellem validering og load.

```
   ──④validate.py──> {clean.json, review.json, escalation.json}
   ──④b Opus-eskalering (flaggede) ──> opdateret clean.json + escalation-diff.md
   ──⑤load_daa.R──> Supabase
```

- [ ] **Step 3: Verificér ingen kode-reference er forkert** (filstier + scriptnavn matcher faktiske filer)

Run: `ls .claude/skills/daa-extract/scripts/escalate_merge.py && echo ok`
Expected: stien + `ok`.

- [ ] **Step 4: Commit**

```bash
git add .claude/skills/daa-extract/SKILL.md
git commit -m "docs(daa-extract): SKILL.md trin ④b — auto-eskalering af flaggede poster"
```

---

## Self-Review (udført ved skrivning)

- **Spec-dækning:** §3 worklist-interface + detektorer → Task 1 (`escalation_entry`, trigger=blokerende+R8, V9 ekskluderet). §5-6.2 escalate_merge (REPLACE/APPEND + promote-kriterium + regressions-guard) → Task 2. §5 diff-rapport → Task 3. §6.4 proveniens-stempel → Task 4. §6.3 SKILL.md trin ④b + snapshot → Task 5. §3 forkert-felt → bevidst UDE (Global Constraints + spec §9). §8 payoff/Task 8 → docs, ikke kode.
- **Placeholder-scan:** ingen TBD; al kode vist. `gen_diff` refereres i Task 2's `main()` men defineres i Task 3 — eksplicit noteret (Task 2's tests rører den ikke).
- **Type-konsistens:** worklist-entry `{linje, nr, nr_label, grunde}` ens i Task 1 (produceret) + Task 2/3 (konsumeret). `decide()`/`merge_escalated()`/`field_diff()`/`gen_diff()` signaturer ens på tværs af Task 2-3. `_escalated`-marker sat i Task 2, læst i Task 4, tilladt i ALLOWED_TOP (Task 2 step 4). Nøgle-form `(linje, nr_label)` konsekvent.
- **Kendt afgrænsning:** LLM-gen-kørslen (Task 5 trin ④b) er agent-drevet, ikke unit-testet — som resten af udtrækket. Det deterministiske (Task 1-4) er fuldt testet.
