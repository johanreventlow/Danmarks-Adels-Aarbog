# 1939-grænseflade Finpudsning Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Indram ejerløse huller, bogfør in-place-godkendte forslag korrekt og advar levende om ét-tegnsforskudte udeladelser uden at ændre kildetekst- eller eksportkoordinater.

**Architecture:** Udvid den eksisterende eksakte markørgrammatik med én navngiven slutlinje og lad generatoren placere den ved hullets `char_to`. Ret kanonisk↔vist matching ved at matche samplacerede linjemarkører én-til-én i samme deterministiske orden som kompositionen. Beregn udeladelsesadvarsler af parserens kildekoordinater og vis dem som ikke-blokerende dansk UI-status.

**Tech Stack:** Python 3, pytest, browserlokal JavaScript, Node.js og Playwright/Chromium.

## Global Constraints

- `docs/superpowers/plans/2026-08-09-graenseflade-spec.md` §3, §4, §5, §7 og §9b står fast.
- Byte-gaten skal fortsat strippe kun eksakte, navngivne `===`-markører; ingen generisk `^===` og aldrig `^###`.
- Eksportens positioner er tegnkoordinater i Calamari-kildeteksten; slutmarkør og advarsel må ikke forskyde dem.
- Resultatet er review-/fil-GO; ingen materialisering, database, loader eller ejerskabsrunde 2.
- `work/` og `work_1939_stamtavle/` må kun behandles af lokale scripts; tekstindhold må ikke udskrives eller committes.
- Ingen push.

---

### Task 1: Indram ejerløse huller

**Files:**
- Modify: `.claude/skills/daa-extract/scripts/make_boundary_text_1939.py`
- Modify: `.claude/skills/daa-extract/scripts/boundary_text_1939_ui.js`
- Test: `.claude/skills/daa-extract/scripts/test_make_boundary_text_1939.py`
- Modify: `.claude/skills/daa-extract/scripts/verify_boundary_text_browser.mjs`

**Interfaces:**
- Consumes: `text_model["huller"]` med `char_offset` og hullets længde.
- Produces: `char_to` på hulmodellen og linjemarkøren `=== SLUT EJERLØS TEKST ===` ved netop dette kildeoffset.

- [ ] **Step 1: Skriv fej­lende generator-/parsertests**

Tilføj tests der kræver start og slut omkring samme hul, kræver at parseren stripper slutlinjen, og sammenligner eksporterede skærings-/udeladelseskoordinater før og efter slutlinjen.

- [ ] **Step 2: Kør de nye tests og verificér RED**

Run: `/usr/bin/python3 -m pytest .claude/skills/daa-extract/scripts/test_make_boundary_text_1939.py -q -k 'hole or ejerloes'`

Expected: FAIL fordi `char_to`/`holeEnd` og den eksakte slutmarkør ikke findes.

- [ ] **Step 3: Implementér minimal generator og eksakt strip-grammatik**

Tilføj `char_to`, annotation-kind `holeEnd`, dens deterministiske rank og det eksakte regex `^=== SLUT EJERLØS TEKST ===$`. Lad kun startmarkøren tælle i sidelistens `ejerloes`-tal.

- [ ] **Step 4: Verificér GREEN og browseroptælling**

Run: `/usr/bin/python3 -m pytest .claude/skills/daa-extract/scripts/test_make_boundary_text_1939.py -q`

Expected: alle fokustests PASS; browserverifikatoren kræver 97 start- og 97 slutmarkører samt uændret sum på 45.757 ejerløse tegn.

### Task 2: Bevar forslagets identitet ved samplacerede markører

**Files:**
- Modify: `.claude/skills/daa-extract/scripts/boundary_text_1939_ui.js`
- Test: `.claude/skills/daa-extract/scripts/test_make_boundary_text_1939.py`

**Interfaces:**
- Consumes: parserens markører og `lineMarkerMappings` med `displayOffset`, `canonicalOffset`, `kind`, `text` og valgfrit `origin`.
- Produces: kanoniske markører hvor hver mapping bruges højst én gang pr. vist offset, og hvor et redigeret forslag beholder sit forslag-offset.

- [ ] **Step 1: Skriv en reproducerende kollisions-test**

Byg to forskellige kanoniske offsets, der vises på samme linjestart: en eksisterende bruger-cut og et forslag. Redigér forslagets linje in-place til `=== SKÆRING ===` og kræv `forslag_godkendt: 1`, uændret skæringssæt og korrekt oprindelse.

- [ ] **Step 2: Kør testen og verificér RED**

Run: `/usr/bin/python3 -m pytest .claude/skills/daa-extract/scripts/test_make_boundary_text_1939.py -q -k 'colocated or proposal'`

Expected: FAIL med `forslag_godkendt == 0` eller forkert kanonisk offset.

- [ ] **Step 3: Implementér deterministisk én-til-én-matchning**

Gruppér parsermarkører og mappings pr. `displayOffset`, sorter mappings efter samme line-rank/tekst-regel som kompositionen, behold eksakte kind/text-match først, og lad en `cut` konsumere den tilsvarende resterende `cut`, derefter `proposal`, derefter `boundary`. En mapping må ikke genbruges af næste linje.

- [ ] **Step 4: Verificér GREEN og round-trip**

Run: `/usr/bin/python3 -m pytest .claude/skills/daa-extract/scripts/test_make_boundary_text_1939.py -q -k 'proposal or round_trip or canonical'`

Expected: PASS med identiske kildekoordinater før og efter `apply_markeringer`.

### Task 3: Levende advarsel om efterladt tegn

**Files:**
- Modify: `.claude/skills/daa-extract/scripts/make_boundary_text_1939.py`
- Modify: `.claude/skills/daa-extract/scripts/boundary_text_1939_ui.js`
- Test: `.claude/skills/daa-extract/scripts/test_make_boundary_text_1939.py`
- Modify: `.claude/skills/daa-extract/scripts/verify_boundary_text_browser.mjs`

**Interfaces:**
- Consumes: `parseMarkedText(...).omissions`, `data.sourceText` og `data.pages`.
- Produces: en liste af advarsler med `charOffset`, kildeside, PDF-side og lokal linje samt synlig dansk status i `[data-role="omission-warning"]`.

- [ ] **Step 1: Skriv fej­lende funktions- og UI-tests**

Kræv advarsel når `source[char_from-2] == "\n"` og `source[char_from-1]` er ikke-blankt. Kræv ingen advarsel ved korrekt linjestart, delvis markering med mere end ét foranstående tegn eller blankt tegn. Kræv at UI-status opdateres efter 300 ms.

- [ ] **Step 2: Kør tests og verificér RED**

Run: `/usr/bin/python3 -m pytest .claude/skills/daa-extract/scripts/test_make_boundary_text_1939.py -q -k 'omission_warning or efterladt'`

Expected: FAIL fordi advarselsfunktionen og DOM-noden ikke findes.

- [ ] **Step 3: Implementér ikke-blokerende advarsel**

Beregn advarslen fra kildekoordinater, vis antal samt første kildeside/PDF-side/linje og nulstil teksten når fejlen rettes. Byte-gate, eksportknap og sidekvittering styres fortsat kun af integritetsgaten.

- [ ] **Step 4: Verificér GREEN**

Run: `/usr/bin/python3 -m pytest .claude/skills/daa-extract/scripts/test_make_boundary_text_1939.py -q`

Expected: PASS; advarslen finder formen uden at afvise tilladte delvise udeladelser generelt.

### Task 4: Reload-undersøgelse og samlet verifikation

**Files:**
- Modify if warranted by evidence: `.claude/skills/daa-extract/scripts/test_make_boundary_text_1939.py`
- Modify: `.claude/skills/daa-extract/scripts/verify_boundary_text_browser.mjs`
- Generate only, never commit: `work/task19-1939-pilot/<ny fil>.html`

**Interfaces:**
- Consumes: eksisterende eksport via `--markeringer`, det rigtige Calamari-input og den nye generator.
- Produces: optællingsbaseret bevis for uændrede koordinater; ingen spekulativ produktionsrettelse hvis forskydningen stadig ikke reproduceres.

- [ ] **Step 1: Kør round-trip-regressioner for begge UDELAD-skrivemåder**

Run: `/usr/bin/python3 -m pytest .claude/skills/daa-extract/scripts/test_make_boundary_text_1939.py -q -k 'udelad or reload or round_trip'`

Expected: PASS med identiske `char_from`/`char_to`.

- [ ] **Step 2: Generér en ny rigtig HTML uden at udskrive PII**

Kør den kontraktfastlagte generator med den seneste eksport og et nyt outputnavn. Expected stdout: `446 grænser · 97 huller · 61 forslag · 86 PDF-sider`.

- [ ] **Step 3: Kør alle obligatoriske verifikationer friskt**

Run:

```bash
/usr/bin/python3 -m pytest .claude/skills/daa-extract/scripts/test_make_boundary_text_1939.py -q
/usr/bin/python3 -m pytest .claude/skills/daa-extract/scripts -q
node .claude/skills/daa-extract/scripts/verify_boundary_text_browser.mjs <ny.html> "$W/full_ocr_calamari_r6_clean.txt"
/usr/bin/python3 .claude/skills/daa-extract/scripts/check_graenseflade_export.py <eksport.json> --calamari "$W/full_ocr_calamari_r6_clean.txt" --boundaries work/task19-1939-pilot/menneskeark-graenser-v8.html --forrige <tidligere.json>
git diff --check
```

Expected: 0 fejl; browserkontrollerne inkluderer slutmarkører, live forslagbogføring og live ét-tegnsadvarsel.

- [ ] **Step 4: Rapportér reload-forskydningen ærligt**

Hvis den ikke reproduceres, behold punktet åbent og rapportér præcist hvilke round-trips der var nulafvigende. Runde 2-ejerskab forbliver uden for dette arbejde.

- [ ] **Step 5: Commit de autoriserede kilde-, test- og planfiler; push ikke**

```bash
git add docs/superpowers/plans/2026-08-10-graenseflade-finpudsning.md \
  .claude/skills/daa-extract/scripts/make_boundary_text_1939.py \
  .claude/skills/daa-extract/scripts/boundary_text_1939_ui.js \
  .claude/skills/daa-extract/scripts/test_make_boundary_text_1939.py \
  .claude/skills/daa-extract/scripts/verify_boundary_text_browser.mjs
git commit -m "fix(1939): gør grænsefladens markeringer selvforklarende"
```
