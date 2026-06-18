# Eager-udtræk & parse-styrkelse Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Gør DAA-udtrækket sikkert eager — deterministisk ægteskabs-udtræk + golden-test-net + mismatch-flagging (Fase A), og felt-proveniens (`citation.citat_tekst`) så fakta kan genverificeres/afstemmes uden ny LLM-kørsel (Fase B / Tier 1).

> **Implementerings-udfald (2026-06-18):** Task 2's deterministiske ægteskabs-udtræk blev **demoteret til advisory-only** efter whole-branch-review (regex-overskrivning korrumperede 74% af partnernavne på rigtig parentes-tæt prosa). `derive_aegteskaber()` driver nu kun R8-flag; LLM-feltet er autoritativt. Tasks 1, 3–7 leveret som planlagt. **Task 8 (re-kørsel + load) er ikke kørt** — bruger-gated. Se spec §4.2.

**Architecture:** Den deterministiske validerings-/udlednings-layer (`validate.py`) er hvor risiko-gatesne bor; LLM-output (`work/extracted/*.json`) er en regenererbar kandidat-cache, DB'en bygges fra den på ~14s. Golden tests dækker det deterministiske layer (LLM-trinnet er ikke-deterministisk og testes ikke direkte). Proveniens-spanet skrives ind i extraction-JSON, gates som substring af `raw_text`, og trådes via `load_daa.R` til `citation.citat_tekst`.

**Tech Stack:** Python 3.9 (stdlib `unittest` — pytest er IKKE installeret), R (DBI/RPostgres), regex. PostgreSQL/Supabase-skema findes; ingen skemaændring nødvendig (`citat_tekst` findes allerede).

## Global Constraints

- **Påstande er semantisk uforanderlige** — ny viden = ny påstand + ny konklusion, aldrig overskrivning af `assertion`-værdier i DB. (Operationelt regenereres DB frit fra JSON.)
- **Hver dato/span SKAL findes ordret i postens `raw_text`** — deterministisk håndhævet. Intet udtrukket felt uden tekst-anker loades.
- **Trin ④ (`validate.py`) er fejlfri kode** — deterministiske udledninger (børn, og nu ægteskaber) overskriver LLM-felter; LLM-trinnet er kun rygrad-forslag.
- **Span-granularitet (`kilde_span`):** den mindste klausul i `raw_text` der indeholder ankeret (dato-token / partnernavn / godsnavn). SKAL være substring af `raw_text`.
- **Tier 2 (katalog-udvidelse) er UDE af denne plan.** Kun parse-styrkelse + Tier 1-proveniens. Tier 2 + display = senere planer.
- **Test-runner:** `python3 -m unittest discover -s .claude/skills/daa-extract/scripts -p 'test_*.py'`. Tests bor ved siden af scriptet de dækker.
- **Filsti-base:** `.claude/skills/daa-extract/scripts/` (forkortet `S/` herunder).
- **Commits:** Conventional Commits, dansk beskrivelse, ingen Claude-attribution. Arbejd på branch `feat/eager-udtraek-parse-styrkelse`.

---

## FASE A — Parse-styrkelse (ingen LLM-re-kørsel; ren gevinst, beskytter Fase B)

### Task 1: Golden-test-harness + lås nuværende `derive_boern`

Etablér unittest-nettet og frys den eksisterende deterministiske børne-udledning FØR `validate.py` røres.

**Files:**
- Create: `S/test_validate.py`
- Reference: `S/validate.py:51-77` (`BOERN_RE`, `derive_boern`)

**Interfaces:**
- Consumes: `derive_boern(raw_text: str) -> dict | None` fra `validate.py`
- Produces: importérbart testmodul; mønster for senere golden-fixtures

- [ ] **Step 1: Skriv golden tests for eksisterende `derive_boern`**

```python
# S/test_validate.py
import os, sys, unittest
sys.path.insert(0, os.path.dirname(__file__))
import validate


class TestDeriveBoern(unittest.TestCase):
    def test_antal_og_range(self):
        raw = "Gottschalk, til Glasau. 3 børn: Tiende slægtled, II, nr. 31-35."
        self.assertEqual(validate.derive_boern(raw),
                         {"antal": 3, "slaegtled": "Tiende slægtled", "linje": "II", "nr_range": [31, 35]})

    def test_enkelt_barn_soen(self):
        raw = "N.N., til X. Søn: nr. 199."
        got = validate.derive_boern(raw)
        self.assertEqual(got["nr_range"], [199, 199])
        self.assertEqual(got["antal"], 1)

    def test_ingen_boerneklausul(self):
        self.assertIsNone(validate.derive_boern("Levede ugift, deres børn boede i udlandet."))

    def test_bar_boern_uden_antal(self):
        raw = "børn: nr. 12-14."
        got = validate.derive_boern(raw)
        self.assertEqual(got["nr_range"], [12, 14])
        self.assertEqual(got["antal"], 3)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Kør og verificér PASS (fryser nuværende adfærd)**

Run: `python3 -m unittest discover -s .claude/skills/daa-extract/scripts -p 'test_*.py' -v`
Expected: 4 tests PASS. Hvis en fejler → den dokumenterer en eksisterende bug; justér forventningen til faktisk adfærd og noter i commit (ikke ret `validate.py` her).

- [ ] **Step 3: Commit**

```bash
git add .claude/skills/daa-extract/scripts/test_validate.py
git commit -m "test(daa-extract): golden tests låser derive_boern-adfærd"
```

---

### Task 2: Deterministisk ægteskabs-udledning `derive_aegteskaber()`

Den største kvalitetsgevinst (spec §4.2). Parser de faste ægteskabs-markører fra prosaen og overskriver LLM-feltet i `main()`, præcis som børn.

**Files:**
- Modify: `S/validate.py` (tilføj `AEGT_RE` + `derive_aegteskaber()` nær `derive_boern`, ~linje 78; wire i `main()` nær linje 199-204)
- Modify: `S/test_validate.py` (ny testklasse)

**Interfaces:**
- Consumes: `norm(s)` fra `validate.py`
- Produces: `derive_aegteskaber(raw_text: str) -> list[dict]` — hver dict har `{ordinal:int, partner_navn:str|None, dato_raw:str|None, skilt:bool}`. Tom liste hvis ingen ægteskab. Brugt i `main()` til at overskrive `rec['aegteskaber']` når den deterministiske liste er ikke-tom.

- [ ] **Step 1: Skriv failing tests (golden-fixtures fra reelle mønstre)**

```python
# tilføj i S/test_validate.py
class TestDeriveAegteskaber(unittest.TestCase):
    def test_enkelt_aegteskab(self):
        raw = "Frederik, til Brahetrolleborg. g. 26. juli 1975 m. Margrethe Holstein."
        got = validate.derive_aegteskaber(raw)
        self.assertEqual(len(got), 1)
        self.assertEqual(got[0]["ordinal"], 1)
        self.assertEqual(got[0]["partner_navn"], "Margrethe Holstein")
        self.assertFalse(got[0]["skilt"])

    def test_to_aegteskaber_ordinaler(self):
        raw = ("Christian, til Christianssæde. Gift 1° 1698 med Anna Sophie Reedtz, "
               "2° 1712 med Birgitte Restorff, skilt.")
        got = validate.derive_aegteskaber(raw)
        self.assertEqual([a["ordinal"] for a in got], [1, 2])
        self.assertEqual(got[0]["partner_navn"], "Anna Sophie Reedtz")
        self.assertTrue(got[1]["skilt"])

    def test_ingen_aegteskab(self):
        self.assertEqual(validate.derive_aegteskaber("Døde ugift 1701."), [])

    def test_dato_raw_findes_i_tekst(self):
        raw = "N.N. g. 1750 m. Sofie."
        got = validate.derive_aegteskaber(raw)
        self.assertIn(got[0]["dato_raw"].strip(), raw)
```

- [ ] **Step 2: Kør tests, verificér FAIL**

Run: `python3 -m unittest .claude.skills.daa-extract.scripts.test_validate.TestDeriveAegteskaber -v`
(eller discover-kommandoen). Expected: FAIL med `AttributeError: module 'validate' has no attribute 'derive_aegteskaber'`.

- [ ] **Step 3: Implementér `derive_aegteskaber` (første-cut; iterér til fixtures passerer)**

```python
# i S/validate.py, efter derive_boern (~linje 78)

# Ægteskabs-markører er faste i DAA-prosaen: "Gift"/"g." starter en klausul,
# ordinaler "1°/2°/3°" nummererer dem, "med"/"m." indleder partneren,
# "skilt" flagger opløsning. Vi splitter på ordinal-markører (eller på
# sekventielle "g."/"Gift" hvis ingen ordinaler) og udtrækker per klausul.
_ORD = {"1": 1, "2": 2, "3": 3, "4": 4, "1°": 1, "2°": 2, "3°": 3, "4°": 4}
AEGT_SPLIT = re.compile(r'(?:\bGift\b|\bg\.)\s*', re.I)
PARTNER_RE = re.compile(r'\bm(?:ed|\.)\s+([A-ZÆØÅ][\wÆØÅæøå.\- ]+?)(?=[,.;(]| g\.| \d°|$)')
ORD_RE = re.compile(r'^\s*(\d)\s*°')
DATE_IN_CLAUSE = re.compile(r'\d{3,4}(?:\s*\.\s*\w+\.?\s*\d{0,4})?')


def derive_aegteskaber(raw_text):
    """Udled ægteskaber deterministisk fra prosaen. Returnér liste (evt. tom)."""
    txt = norm(raw_text or '')
    parts = AEGT_SPLIT.split(txt)
    if len(parts) < 2:               # ingen "Gift"/"g."-markør
        return []
    out, n = [], 0
    for seg in parts[1:]:            # parts[0] = tekst før første markør
        n += 1
        mo = ORD_RE.match(seg)
        ordinal = int(mo.group(1)) if mo else n
        pm = PARTNER_RE.search(seg)
        dm = DATE_IN_CLAUSE.search(seg.split(' med ')[0].split(' m.')[0])
        out.append({
            'ordinal': ordinal,
            'partner_navn': norm(pm.group(1)) if pm else None,
            'dato_raw': dm.group(0).strip() if dm else None,
            'skilt': bool(re.search(r'\bskilt\b', seg, re.I)),
        })
    return out
```

- [ ] **Step 4: Wire i `main()` — overskriv LLM-feltet (mønster som `derive_boern`)**

```python
# i main(), i fil-loopet, lige efter derive_boern-blokken (~linje 204):
        if src:
            derived_a = derive_aegteskaber(src['raw_text'])
            if derived_a:
                # bevar LLM-felter validatoren ikke udleder (partner_foedsel, sted, type)
                # ved at flette på ordinal; deterministiske felter vinder.
                llm = {a.get('ordinal'): a for a in (rec.get('aegteskaber') or [])}
                for a in derived_a:
                    base = llm.get(a['ordinal'], {})
                    base.update({k: v for k, v in a.items() if v is not None or k == 'skilt'})
                    a.clear(); a.update(base)
                rec['aegteskaber'] = derived_a
```

- [ ] **Step 5: Kør tests + hele suiten, verificér PASS. Iterér regex hvis fixtures fejler**

Run: `python3 -m unittest discover -s .claude/skills/daa-extract/scripts -p 'test_*.py' -v`
Expected: alle PASS. Marriage-parsing er svær — tilføj reelle poster fra `work/extracted/` som fixtures og udvid regex til de passerer. Dokumentér evt. mønstre den IKKE fanger i en kommentar.

- [ ] **Step 6: Commit**

```bash
git add .claude/skills/daa-extract/scripts/validate.py .claude/skills/daa-extract/scripts/test_validate.py
git commit -m "feat(daa-extract): deterministisk ægteskabs-udledning i validate.py

Overskriver LLM-felt som boern; fjerner systematisk ægteskabs-miss."
```

---

### Task 3: Mismatch-flagging af manglende slægtskab + miss-måling

`validate.py` udleder forventede signaler fra prosaen og flagger poster hvor LLM-udtrækket mangler dem. Giver samtidig det reelle miss-tal (spec §9 #4) som biprodukt.

**Files:**
- Modify: `S/validate.py` (ny `expected_signals()` + R8-tjek i `validate()`)
- Modify: `S/test_validate.py`

**Interfaces:**
- Consumes: `derive_aegteskaber`, `norm`
- Produces: `expected_signals(raw_text: str) -> dict` med booleans `{venter_aegteskab, venter_boern, venter_doed}`; nye advisory-linjer i `validate()`-output.

- [ ] **Step 1: Skriv failing test**

```python
# i S/test_validate.py
class TestExpectedSignals(unittest.TestCase):
    def test_venter_aegteskab_men_mangler(self):
        rec = {"aegteskaber": [], "boern": None, "facts": []}
        raw = "N.N. g. 1750 m. Sofie. † 1799."
        sig = validate.expected_signals(raw)
        self.assertTrue(sig["venter_aegteskab"])
        self.assertTrue(sig["venter_doed"])
```

- [ ] **Step 2: Kør, verificér FAIL** (`has no attribute 'expected_signals'`).

- [ ] **Step 3: Implementér `expected_signals` + R8-advisory i `validate()`**

```python
# i S/validate.py
def expected_signals(raw_text):
    txt = norm(raw_text or '')
    return {
        'venter_aegteskab': bool(derive_aegteskaber(txt)),
        'venter_boern': BOERN_RE.search(txt) is not None,
        'venter_doed': bool(re.search(r'[†☩]|\bdøde?\b|\bd\.\s*\d', txt, re.I)),
    }

# i validate(), før `return issues, advisory` (~linje 173):
    if src_text:
        sig = expected_signals(src_text)
        if sig['venter_aegteskab'] and not (rec.get('aegteskaber')):
            advisory.append('R8: prosa nævner ægteskab, men intet udtrukket')
        if sig['venter_doed'] and not any(
                f.get('faktatype') == 'død' for f in (rec.get('facts') or [])):
            advisory.append('R8: prosa nævner død, men intet død-fakta')
```

- [ ] **Step 4: Kør tests, verificér PASS.**

Run: `python3 -m unittest discover -s .claude/skills/daa-extract/scripts -p 'test_*.py' -v`

- [ ] **Step 5: Mål det reelle miss-tal mod hele korpus**

Run:
```bash
cd /Users/johanreventlow/TypeScript/danmarksadelsaarbog
python3 .claude/skills/daa-extract/scripts/validate.py \
  work/posts.json work/extracted/ --clean /tmp/clean.json --review /tmp/review.json 2>&1 \
  | grep -c 'R8:'
```
Expected: et heltal. Noter det i commit-beskeden — det ERSTATTER det antagede "~9%". (Bemærk: efter Task 2 udleder validatoren selv ægteskaber, så R8-ægteskab bør være ~0; miss-tallet måles bedst på en kopi af extracted/ FØR Task 2's overskrivning, hvis baseline ønskes.)

- [ ] **Step 6: Commit**

```bash
git add .claude/skills/daa-extract/scripts/validate.py .claude/skills/daa-extract/scripts/test_validate.py
git commit -m "feat(daa-extract): R8 mismatch-flag for manglende slægtskab/død (måler reelt miss-tal)"
```

**CHECKPOINT:** Fase A er komplet og selvstændig kørbar software. Stop her hvis Fase B's LLM-re-kørsel ikke ønskes nu.

---

## FASE B — Tier 1 proveniens (kræver schema-felt i JSON + LLM-re-kørsel)

### Task 4: Bevar nuværende `work/extracted/` som versioneret snapshot

Re-kørslen i Task 7 OVERSKRIVER `work/extracted/`. Det er det dyre, ikke-regenererbare aktiv → snapshot det FØRST (spec §3, §9 #3).

**Files:**
- Create: `data/extracted-2026-06-18/` (git-tracked kopi af de 591 JSON)
- Modify: `.gitignore` (undtag den nye sti fra `work/`-reglen er ikke nødvendig; ny sti ligger uden for `work/`)

- [ ] **Step 1: Kopiér + track**

```bash
cd /Users/johanreventlow/TypeScript/danmarksadelsaarbog
mkdir -p data/extracted-2026-06-18
cp work/extracted/*.json data/extracted-2026-06-18/
ls data/extracted-2026-06-18/*.json | wc -l   # forvent 591
```

- [ ] **Step 2: Commit snapshot**

```bash
git add data/extracted-2026-06-18/
git commit -m "chore(daa-extract): versionér 591 LLM-udtræk som durable cache før re-kørsel"
```

---

### Task 5: Tilføj `kilde_span` til extraction-schema + prompt-vejledning

**Files:**
- Modify: `.claude/skills/daa-extract/references/extraction-schema.json` (per-fact + per-aegteskab `kilde_span`)
- Modify: `.claude/skills/daa-extract/SKILL.md` (trin ③-vejledning)

**Interfaces:**
- Produces: extraction-output har valgfrit `kilde_span: string` på hvert `facts[]`-item og hvert `aegteskaber[]`-item.

- [ ] **Step 1: Tilføj feltet i `facts.items.properties` (efter `sted`, ~linje 29)**

```json
          "sted": {"type": ["string", "null"]},
          "kilde_span": {"type": ["string", "null"], "description": "mindste klausul i raw_text der indeholder dette faktas anker (dato/værdi). SKAL være substring af raw_text. Bruges til felt-proveniens (citation.citat_tekst)."}
```

- [ ] **Step 2: Tilføj samme felt i `aegteskaber.items.properties` (efter `note`, ~linje 81)**

```json
          "note": {"type": ["string", "null"], "description": "anden fri tekst om ægteskabet"},
          "kilde_span": {"type": ["string", "null"], "description": "klausulen i raw_text dette ægteskab kom fra; SKAL være substring af raw_text"}
```

- [ ] **Step 3: Tilføj vejledning i SKILL.md trin ③ (efter date_raw-reglen, ~linje 78-84)**

```markdown
* **kilde_span (proveniens):** for hvert fakta og ægteskab, kopiér den mindste
  klausul fra `raw_text` der indeholder ankeret (dato-token, partnernavn,
  godsnavn). Den SKAL være en ordret substring af `raw_text` — `validate.py`
  afviser poster hvor et span ikke findes ordret (R7). Opfind aldrig spanet.
```

- [ ] **Step 4: Verificér JSON er valid**

Run: `python3 -c "import json; json.load(open('.claude/skills/daa-extract/references/extraction-schema.json')); print('ok')"`
Expected: `ok`

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/daa-extract/references/extraction-schema.json .claude/skills/daa-extract/SKILL.md
git commit -m "feat(daa-extract): kilde_span felt-proveniens i extraction-schema + prompt"
```

---

### Task 6: R7 substring-gate i `validate.py`

**Files:**
- Modify: `S/validate.py` (`validate()`: R7-tjek)
- Modify: `S/test_validate.py`

**Interfaces:**
- Consumes: `norm`, `rec['facts'][*]['kilde_span']`, `rec['aegteskaber'][*]['kilde_span']`, `src['raw_text']`
- Produces: R7-brud (blokerende) når et `kilde_span` ikke er substring af `raw_text`.

- [ ] **Step 1: Skriv failing tests**

```python
# i S/test_validate.py
class TestProvenansGate(unittest.TestCase):
    def _run(self, rec, raw):
        src = {"raw_text": raw}
        issues, _ = validate.validate(rec, src, {})
        return issues

    def test_span_findes(self):
        rec = {"linje": "I", "nr": 1, "facts": [{"faktatype": "død", "kilde_span": "† 1300"}]}
        self.assertEqual([i for i in self._run(rec, "N.N. † 1300, til X.") if i.startswith("R7")], [])

    def test_span_hallucineret(self):
        rec = {"linje": "I", "nr": 1, "facts": [{"faktatype": "død", "kilde_span": "† 1399"}]}
        bad = [i for i in self._run(rec, "N.N. † 1300, til X.") if i.startswith("R7")]
        self.assertEqual(len(bad), 1)
```

- [ ] **Step 2: Kør, verificér FAIL** (R7 findes ikke endnu → `test_span_hallucineret` fejler).

- [ ] **Step 3: Implementér R7 i `validate()` (efter R1-blokken, ~linje 121)**

```python
    # R7: felt-proveniens — hvert kilde_span SKAL være ordret substring af prosaen.
    spans = [f.get('kilde_span') for f in (rec.get('facts') or [])]
    spans += [a.get('kilde_span') for a in (rec.get('aegteskaber') or [])]
    for sp in spans:
        if sp and norm(sp) not in hay:
            issues.append(f'R7: kilde_span "{sp}" findes ikke ordret i prosaen (hallucination?)')
```

- [ ] **Step 4: Kør tests, verificér PASS.**

Run: `python3 -m unittest discover -s .claude/skills/daa-extract/scripts -p 'test_*.py' -v`

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/daa-extract/scripts/validate.py .claude/skills/daa-extract/scripts/test_validate.py
git commit -m "feat(daa-extract): R7 — gate kilde_span som substring af raw_text"
```

---

### Task 7: Tråd `kilde_span` → `citation.citat_tekst` i `load_daa.R`

**Files:**
- Modify: `.claude/skills/daa-extract/scripts/load_daa.R` (`add_citation` linje 70; `fact_value` linje 94-97; fakta-loop linje 190-195; ægteskabs-vielse linje 226-228)

**Interfaces:**
- Consumes: `kilde_span` på facts/aegteskaber i `clean.json`
- Produces: `citation.citat_tekst` populeret for fakta der bærer span.

- [ ] **Step 1: Udvid `add_citation` (linje 70) med `citat`-param**

```r
add_citation <- function(aid, sid, side=NA, kval="primær", citat=NA) push("citation", list(id=nid("citation"), assertion_id=aid, source_id=sid, side=side, citat_tekst=citat, kvalitet=kval))
```

- [ ] **Step 2: Udvid `fact_value` (linje 94-97) med `span`-param**

```r
fact_value <- function(pid, ft, vaerdi=NA, dmin=NA, dmax=NA, qual=NA, raw=NA, sid, side, sted=NA, st="person", span=NA) {
  fid <- add_fact(pid, ft, get_place(sted), st)
  aid <- add_assertion("fact", fid, vaerdi, iso(dmin), iso(dmax), qual, raw)
  add_citation(aid, sid, side, citat=span); add_conclusion("fact", fid, aid); invisible(fid) }
```

- [ ] **Step 3: Send span fra fakta-loopet (linje 190-195)**

```r
    for (f in g(rec, "facts", list())) {
      if (f$faktatype %in% c("erhverv", "uddannelse")) next
      fact_value(pid, f$faktatype, vaerdi = g(f,"vaerdi"), dmin = g(f,"date_min"),
                 dmax = g(f,"date_max"), qual = g(f,"date_qualifier"), raw = g(f,"date_raw"),
                 sid = src, side = side, sted = g(f,"sted"), span = g(f,"kilde_span"))
    }
```

- [ ] **Step 4: Send span fra vielse-fakta (linje 226-228)**

```r
      if (!is.null(a$dato_raw) || !is.null(a$date_min) || !is.null(a[["sted"]]))
        fact_value(fam, "vielse", dmin = g(a,"date_min"), dmax = g(a,"date_max"),
                   raw = g(a,"dato_raw"), sted = g(a,"sted"), sid = src, side = side,
                   st = "family", span = g(a,"kilde_span"))
```

- [ ] **Step 5: Syntaks-tjek R**

Run: `Rscript -e 'invisible(parse(file=".claude/skills/daa-extract/scripts/load_daa.R")); cat("parse ok\n")'`
Expected: `parse ok`

- [ ] **Step 6: Commit**

```bash
git add .claude/skills/daa-extract/scripts/load_daa.R
git commit -m "feat(daa-extract): populér citation.citat_tekst fra kilde_span (felt-proveniens)"
```

---

### Task 8: Re-kør udtræk over 591 poster + load (DEN EKSPLICITTE OMKOSTNING)

Spec §8: én fuld LLM-kørsel. Integration + verifikation. Kør KUN efter Fase A + Task 4-7 er grønne.

**Files:**
- Regenererer: `work/extracted/*.json`, `work/clean.json`; loader til Supabase.

- [ ] **Step 1: Re-kør LLM-udtrækket** per `SKILL.md` trin ③ (én post ad gangen, default Sonnet), nu med `kilde_span` i hvert fakta/ægteskab. Output til `work/extracted/`.

- [ ] **Step 2: Validér**

Run:
```bash
python3 .claude/skills/daa-extract/scripts/validate.py \
  work/posts.json work/extracted/ --clean work/clean.json --review work/review.json
```
Expected: review-rapport på stderr; tjek R7-brud er få/nul (ellers fix prompt/span og gen-kør de poster).

- [ ] **Step 3: Load**

Run: `Rscript .claude/skills/daa-extract/scripts/load_daa.R work/clean.json`
Expected: load uden fejl (~14s).

- [ ] **Step 4: Verificér proveniens i DB (spot-check)**

Run (mod Supabase):
```sql
SELECT count(*) FROM citation WHERE citat_tekst IS NOT NULL;
SELECT citat_tekst FROM citation WHERE citat_tekst IS NOT NULL LIMIT 5;
```
Expected: ikke-nul antal; spans matcher prosa.

- [ ] **Step 5: Opdatér snapshot + docs**

```bash
cp work/extracted/*.json data/extracted-2026-06-18/
git add data/extracted-2026-06-18/ docs/changelog.md
git commit -m "feat(daa-extract): re-kørsel med felt-proveniens; citat_tekst populeret"
```

---

## Self-Review (udført ved skrivning)

- **Spec-dækning:** Tier 1 proveniens → Task 5-8. Tier 2 → bevidst UDE (Global Constraints). §4.1 golden tests → Task 1. §4.2 deterministisk ægteskaber → Task 2. §4.3 mismatch-flag → Task 3. §3 durable cache/§9 #3 → Task 4. §8 omkostning/re-kørsel → Task 8. §9 #4 miss-måling → Task 3 step 5. §5 display → UDE (separat plan, noteret).
- **Placeholder-scan:** ingen TBD; al kode vist. Marriage-regex markeret som "iterér til fixtures passerer" — fixtures ER specifikationen (TDD), ikke placeholder.
- **Type-konsistens:** `derive_aegteskaber` returtype (list[dict] m. ordinal/partner_navn/dato_raw/skilt) ens i Task 2+3. `kilde_span` ens på tværs af schema (Task 5), gate (Task 6), loader (Task 7). `add_citation(..., citat=)` / `fact_value(..., span=)` ens i Task 7.
- **Kendt risiko:** marriage-parsing er svær; Task 2 step 5 kræver iteration med reelle fixtures. Display + Tier 2 er separate fremtidige planer.
