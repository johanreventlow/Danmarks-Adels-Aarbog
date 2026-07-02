# DAA-reimport i fire etaper — Implementeringsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reducere dubletter og forkerte/manglende slægtskabslinks i DAA-datagrundlaget ved først at rette den deterministiske loader (0 tokens), måle effekten med TNG-QA, og derefter kun re-udtrække de poster hvor selve LLM-udtrækket er problemet.

**Architecture:** Fire sekventielle etaper med beslutnings-gates imellem. Etape 1 er kodeændringer (Python `validate.py` + R `load_daa.R`, TDD). Etape 2-4 er kørsels-/beslutnings-protokoller der bygger på Etape 1's kode og gates på målte TNG-QA-tal, ikke på antagelser. Loaderens fejl bor i det deterministiske lag; re-udtræk er sidste udvej, ikke første.

**Tech Stack:** Python 3 (`unittest`, ingen eksterne deps), R (`DBI`/`RPostgres`/`jsonlite`, `testthat` via `Rscript run-tests.R`), Supabase Postgres (prod = separat projekt; test = `postgres.xjnvdhajfyr` "Test-udgave-A").

## Nøglefund der styrer planen (verificeret i denne session)

1. **De 125 manglende links er et LINKING-problem, ikke et manglende-person-problem.** Alle 121 forældre-referencer i TNG-QA-rapporten (2026-07-01) har forælderen til stede i vores matchede data (bucket c = 0, målt mod `data/tng-crosswalk.csv`). **Konsekvens: re-udtræk (Etape 3) genindvinder IKKE de 125 links** — de skal rettes i loaderen (Etape 1). Dette er den vigtigste enkeltkonklusion.
2. **Dublet-løftestangen er `partner_ekstern_ref`, ikke navne-match.** 202 af 372 ægteskaber med navngiven partner har `partner_ekstern_ref` udfyldt; kun 4 partnere matcher en hovedpersons navn eksakt (alle "NN"). Intern-ref-formen er "se nr. 97" / "nr. 106" / "…linje, nr. 79".
3. **`kuld` og `aegteskab_kontekst` findes IKKE i clean-records** (0/591) — kun i `posts_full.json`. 537/591 poster har `aegteskab_kontekst`, heraf 91 med ordinal ("af første ægteskab med …"). `validate.py` skal flette dem ind før loaderen kan binde børn til rette union.
4. **Ingen post i denne udgave har >1 børne-reference** (0/591 via `BOERN_RE.finditer`). `finditer`-fixet er derfor YAGNI for denne udgave og udeladt.
5. **`~/.Renviron` peger p.t. på TESTBASEN** (`postgres.xjnvdhajfyr`, 3 personer), ikke prod. Prod (925 personer, det appen viser) er et separat projekt. **Enhver re-load skal bekræfte target-base først.**
6. **Loaderen defaulter til `RESET` = `TRUNCATE … CASCADE`** på alle modeltabeller. Prod har nu redaktionelle skrivninger + `change_event`-historik. TRUNCATE mod prod er den eneste irreversible handling i planen.

## Global Constraints

- **Ingen ændring rammer prod uden eksplicit brugergodkendelse** (global regel §5/§8). Al udvikling og verifikation sker mod testbasen eller lokalt.
- **Påstande er uforanderlige** (invariant #1): loaderen retter aldrig eksisterende påstande — den skriver nye. Dedup betyder "opret ikke en ny person", ikke "flet to eksisterende".
- **Cache-felter (`visning_*`, `koen`, `levende`) regenereres, redigeres aldrig direkte** (invariant #4).
- **Python-tests:** `python3 .claude/skills/daa-extract/scripts/test_validate.py` (unittest, 28 grønne p.t.). Kør fra repo-roden med fuld sti.
- **R-tests:** `Rscript run-tests.R` fra repo-roden (`testthat`, filer i `tests/testthat/`). Rene helper-funktioner testes uden DB.
- **Alle kommandoer køres fra repo-roden** `/Users/johanreventlow/TypeScript/danmarksadelsaarbog`.
- **Conventional Commits, dansk beskrivelse, ingen Claude-attribution-footer** (GIT_WORKFLOW.md).
- **Loader-helper-funktioner skal være rene** (ingen DB-I/O, ingen `<<-`) så de kan unit-testes i `testthat` — DB-wiring forbliver i `load_daa.R`'s transaktionsblok.

---

# ETAPE 1 — Loader- og validate-fixes (0 tokens)

Retter den deterministiske pipeline. Alle tasks er TDD. Ingen LLM-kald.

---

### Task 0: Klassificér de 125 manglende links (a/b-split) — GATE, prod read-only

Sætter scope for resten. Bucket c er allerede fastslået = 0. Denne task splitter de resterende i **(a) samme-linje** (loaderen droppede et barn den burde have linket → Task 6-8 retter det) og **(b) kryds-linje** (forælder i anden gren; datafixet i review 11 dropper disse bevidst → kræver TNG-corroboration, uden for Etape 1).

**Files:**
- Create: `work/link-klassifikation.csv` (output, git-ignoreret)
- Read: `docs/reviews/tng-qa-rapport-2026-07-01.md`, `data/tng-crosswalk.csv`

**Interfaces:**
- Produces: en optælling `{a_samme_linje: N, b_kryds_linje: M}` der citeres i Etape 2's forventnings-gate og afgør om Task 6-8 dækker flertallet.

- [ ] **Step 1: Bekræft hvilken base der har prod-data**

Kør (read-only) mod den forbindelse `~/.Renviron` peger på:

```bash
Rscript -e 'suppressMessages(library(DBI)); con <- dbConnect(RPostgres::Postgres(), host=Sys.getenv("SUPABASE_HOST"), port=as.integer(Sys.getenv("SUPABASE_PORT","5432")), dbname="postgres", user=Sys.getenv("SUPABASE_USER"), password=Sys.getenv("SUPABASE_PASSWORD"), sslmode="require"); print(dbGetQuery(con, "SELECT count(*) n FROM person")); dbDisconnect(con)'
```

Forventet ved prod: ~925. Ved testbasen: 3. **Hvis 3 → stop og bed brugeren pege `~/.Renviron` (eller en engangs-env) mod prod for denne read-only klassifikation.** Kør ikke videre mod testbasen — den har ikke dataene.

- [ ] **Step 2: Hent forælder-linjer read-only fra prod**

```bash
Rscript -e 'suppressMessages(library(DBI)); con <- dbConnect(RPostgres::Postgres(), host=Sys.getenv("SUPABASE_HOST"), port=as.integer(Sys.getenv("SUPABASE_PORT","5432")), dbname="postgres", user=Sys.getenv("SUPABASE_USER"), password=Sys.getenv("SUPABASE_PASSWORD"), sslmode="require"); write.csv(dbGetQuery(con, "SELECT person_id, linje, nr FROM person_external_id"), "work/extid-prod.csv", row.names=FALSE); dbDisconnect(con)'
```

- [ ] **Step 3: Join og klassificér**

```python
# work/klassificer_links.py
import csv, re
tng2pid, pid2linje = {}, {}
for r in csv.DictReader(open('data/tng-crosswalk.csv')):
    tng2pid[r['tng_id']] = int(r['person_id'])
for r in csv.DictReader(open('work/extid-prod.csv')):
    pid2linje[int(r['person_id'])] = r['linje']
a=b=ukendt=0; rows=[]
for ln in open('docs/reviews/tng-qa-rapport-2026-07-01.md', encoding='utf-8'):
    m = re.match(r'- \*\*([IVX]+)-(\d+)\*\* \([^)]+\): TNG (?:father|mother)_tng: (\S+)', ln)
    if not m: continue
    barn_linje, parent_tng = m.group(1), m.group(3)
    ppid = tng2pid.get(parent_tng); plinje = pid2linje.get(ppid) if ppid else None
    bucket = 'ukendt' if plinje is None else ('a_samme_linje' if plinje==barn_linje else 'b_kryds_linje')
    rows.append((f"{barn_linje}-{m.group(2)}", parent_tng, plinje, bucket))
    a += bucket=='a_samme_linje'; b += bucket=='b_kryds_linje'; ukendt += bucket=='ukendt'
csv.writer(open('work/link-klassifikation.csv','w')).writerows([('barn','parent_tng','parent_linje','bucket'), *rows])
print(f'a_samme_linje={a}  b_kryds_linje={b}  ukendt={ukendt}')
```

Run: `python3 work/klassificer_links.py`
Expected: en fordeling, fx `a_samme_linje=70 b_kryds_linje=51 ukendt=0`.

- [ ] **Step 4: Notér scope-konklusion (ingen commit — arbejdsfil)**

Skriv fordelingen ind i Etape 2's gate nedenfor. **Beslutningsregel:** hvis `a` ≥ `b`, dækker Etape 1 (Task 6-8) flertallet og planen kører som skrevet. Hvis `b` > `a`, er kryds-linje-problemet dominerende → hæv prioritet på TNG-corroboration (fase 1-planen `2026-07-01-tng-qa-relationel-corroboration-fase1.md`) og behandl Etape 1 som partiel gevinst.

---

### Task 1: `load_daa.R` — `--dry-run` flag

Muliggør at teste alle følgende loader-ændringer uden at skrive til nogen base.

**Files:**
- Modify: `.claude/skills/daa-extract/scripts/load_daa.R:19-23` (argparse), `:176-338` (transaktion)
- Test: `tests/testthat/test-load-daa.R` (opret)

**Interfaces:**
- Produces: `DRY_RUN <- ("--dry-run" %in% argv)`. Når sat: byg alle buffere, kør `flush_all()` erstattes af en optælling, `dbCommit` springes over (`dbRollback`), rapportér rækketal pr. tabel til stderr, skriv intet.

- [ ] **Step 1: Skriv den fejlende test (pure-function-udtræk)**

Udtræk buffer-optælling til en ren funktion. I `tests/testthat/test-load-daa.R`:

```r
source(".claude/skills/daa-extract/scripts/load_helpers.R")  # ny fil, se Step 3

test_that("buffer_counts tæller rækker pr. tabel", {
  buf <- list(person = list(list(id=1), list(id=2)), fact = list(list(id=1)))
  expect_equal(buffer_counts(buf), c(person = 2L, fact = 1L))
})
```

- [ ] **Step 2: Kør testen — den fejler**

Run: `Rscript run-tests.R 2>&1 | grep -A2 buffer_counts`
Expected: FAIL — `could not find function "buffer_counts"` / filen findes ikke.

- [ ] **Step 3: Opret `load_helpers.R` med den rene funktion**

```r
# .claude/skills/daa-extract/scripts/load_helpers.R
# Rene, DB-frie hjælpere til load_daa.R — unit-testbare i testthat.
buffer_counts <- function(buf) {
  tbls <- ls(buf)
  vapply(setNames(tbls, tbls), function(t) length(buf[[t]]), integer(1))
}
```

- [ ] **Step 4: Wire dry-run ind i `load_daa.R`**

Tilføj efter linje 23:
```r
DRY_RUN <- ("--dry-run" %in% argv)
```
Kilde `load_helpers.R` øverst (efter `library`-blokken):
```r
source(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value=TRUE)[1])), "load_helpers.R"))
```
Erstat `dbCommit(con); message(...)` (linje 336) med:
```r
  if (DRY_RUN) {
    message("DRY-RUN: ingen commit. Bufret pr. tabel:")
    print(buffer_counts(.buf))
    dbRollback(con)
  } else {
    dbCommit(con); message(sprintf("Indlæst %d poster (udgave %s).", length(clean), udgave))
  }
```

- [ ] **Step 5: Kør R-tests + dry-run-smoke mod testbasen**

Run: `Rscript run-tests.R 2>&1 | tail -3`
Expected: alle testthat-tests PASS.
Run: `Rscript .claude/skills/daa-extract/scripts/load_daa.R work/clean.json "Test" --no-reset --dry-run 2>&1 | tail -8`
Expected: "DRY-RUN: ingen commit" + rækketal, ingen fejl.

- [ ] **Step 6: Commit**

```bash
git add .claude/skills/daa-extract/scripts/load_daa.R .claude/skills/daa-extract/scripts/load_helpers.R tests/testthat/test-load-daa.R
git commit -m "feat(daa-load): --dry-run flag + buffer_counts helper"
```

---

### Task 2: `load_daa.R` — RESET-guard mod redaktionelle ændringer (SIKKERHED)

Nægter `TRUNCATE CASCADE`, hvis basen indeholder redaktionelle (ikke-import) `change_event`-rækker. Skal ligge før nogen re-load mod prod.

**Files:**
- Modify: `.claude/skills/daa-extract/scripts/load_daa.R:177-179` (RESET-blok)
- Modify: `.claude/skills/daa-extract/scripts/load_helpers.R` (ren prædikat)
- Test: `tests/testthat/test-load-daa.R`

**Interfaces:**
- Consumes: en data.frame `ce` med kolonne `kilde` fra `change_set`.
- Produces: `has_editorial_changes(ce)` → `TRUE` hvis nogen række har `kilde` udenfor `{'daa-import','load_daa'}`.

- [ ] **Step 1: Skriv den fejlende test**

```r
test_that("has_editorial_changes ser bort fra import-changes", {
  expect_false(has_editorial_changes(data.frame(kilde=c("daa-import","load_daa"))))
  expect_true(has_editorial_changes(data.frame(kilde=c("daa-import","redaktion"))))
  expect_false(has_editorial_changes(data.frame(kilde=character(0))))
})
```

- [ ] **Step 2: Kør — fejler**

Run: `Rscript run-tests.R 2>&1 | grep -A2 has_editorial`
Expected: FAIL — funktion findes ikke.

- [ ] **Step 3: Implementér i `load_helpers.R`**

```r
has_editorial_changes <- function(ce) {
  if (is.null(ce) || !nrow(ce)) return(FALSE)
  any(!(ce$kilde %in% c("daa-import", "load_daa")))
}
```

- [ ] **Step 4: Wire ind i RESET-blokken (`load_daa.R:177`)**

```r
  if (RESET) {
    ce <- tryCatch(dbGetQuery(con, "SELECT kilde FROM change_set"), error=function(e) data.frame(kilde=character(0)))
    if (has_editorial_changes(ce))
      stop("RESET afvist: basen har redaktionelle change_set-rækker. Brug --no-reset (differentiel) eller bekræft eksplicit sletning.")
    message("RESET: tømmer model-tabeller…")
    ex(paste0("TRUNCATE ", paste(model_tables, collapse=", "), " CASCADE;"))
  }
```

- [ ] **Step 5: Kør tests**

Run: `Rscript run-tests.R 2>&1 | tail -3`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat(daa-load): RESET-guard afviser TRUNCATE ved redaktionelle change_set-rækker"
```

---

### Task 3: `validate.py` — flet `kuld` + `aegteskab_kontekst` ind i clean-records

Loaderens korrekt-union-fix (Task 8) kræver disse felter, som i dag kun findes i `posts.json`.

**Files:**
- Modify: `.claude/skills/daa-extract/scripts/validate.py:392-395` (clean-append)
- Test: `.claude/skills/daa-extract/scripts/test_validate.py`

**Interfaces:**
- Produces: hver clean-record får `rec['kuld']` og `rec['aegteskab_kontekst']` fra kilde-posten (kan være `None`). `ALLOWED_TOP` udvides så R5 ikke flagger dem.

- [ ] **Step 1: Skriv den fejlende test**

I `test_validate.py`, ny klasse:
```python
class TestKontekstMerge(unittest.TestCase):
    def test_merge_kuld_og_kontekst(self):
        rec = {"linje": "I", "nr": 66, "nr_label": "66", "navn": "X"}
        src = {"linje": "I", "nr": 66, "nr_label": "66",
               "raw_text": "X, til Y. 1700.", "kuld": "I",
               "aegteskab_kontekst": "af første ægteskab med Anna von Ahlefeldt"}
        out = validate.merge_kontekst(dict(rec), src)
        self.assertEqual(out["kuld"], "I")
        self.assertEqual(out["aegteskab_kontekst"], "af første ægteskab med Anna von Ahlefeldt")
    def test_merge_haandterer_manglende_src(self):
        out = validate.merge_kontekst({"linje":"I","nr":1,"nr_label":"1","navn":"X"}, None)
        self.assertIsNone(out["kuld"])
```

- [ ] **Step 2: Kør — fejler**

Run: `python3 .claude/skills/daa-extract/scripts/test_validate.py 2>&1 | tail -4`
Expected: FAIL — `module 'validate' has no attribute 'merge_kontekst'`.

- [ ] **Step 3: Implementér**

I `validate.py`, efter `normalize_record`:
```python
def merge_kontekst(rec, src):
    """Flet kuld + aegteskab_kontekst fra kilde-posten ind (loaderen bruger dem
    til union-binding). Begge kan være None."""
    rec['kuld'] = src.get('kuld') if src else None
    rec['aegteskab_kontekst'] = src.get('aegteskab_kontekst') if src else None
    return rec
```
Udvid `ALLOWED_TOP` (linje 22-24): tilføj `"kuld", "aegteskab_kontekst"`.
I `main()`, i clean-grenen (efter `rec['narrative'] = src['raw_text']`, linje 394):
```python
            merge_kontekst(rec, src)
```

- [ ] **Step 4: Kør tests**

Run: `python3 .claude/skills/daa-extract/scripts/test_validate.py 2>&1 | tail -3`
Expected: OK (30 tests).

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/daa-extract/scripts/validate.py .claude/skills/daa-extract/scripts/test_validate.py
git commit -m "feat(daa-validate): flet kuld+aegteskab_kontekst ind i clean-records"
```

---

### Task 4: `validate.py` — deterministisk dato-normalisering + hærdet R1

Fjerner LLM'ens fri ISO-syntese: `date_min`/`date_max` udledes deterministisk af `date_raw`, og R1 tjekker at det udledte år faktisk står i `date_raw` (fanger fejl-attribuering — fx vielsesår udtrukket som dødsår).

**Files:**
- Modify: `.claude/skills/daa-extract/scripts/validate.py` (ny `derive_date_bounds`, kald i `normalize_record`, hærdet R1)
- Test: `.claude/skills/daa-extract/scripts/test_validate.py`

**Interfaces:**
- Produces: `derive_date_bounds(date_raw)` → `(date_min|None, date_max|None)` som ISO-strenge. `normalize_record` overskriver `f['date_min']/f['date_max']` for hvert fakta med `date_raw`. R1 tilføjer brud hvis et udledt år ikke findes i `date_raw`.

- [ ] **Step 1: Skriv de fejlende tests**

```python
class TestDateBounds(unittest.TestCase):
    def test_aar_kun(self):
        self.assertEqual(validate.derive_date_bounds("1698"), ("1698-01-01", "1698-12-31"))
    def test_fuld_dato(self):
        self.assertEqual(validate.derive_date_bounds("26. juli 1975"), ("1975-07-26", "1975-07-26"))
    def test_ca(self):
        lo, hi = validate.derive_date_bounds("ca. 1500")
        self.assertTrue(lo.startswith("1500") and hi.startswith("1500"))
    def test_uparsebar(self):
        self.assertEqual(validate.derive_date_bounds("ukendt"), (None, None))
```

- [ ] **Step 2: Kør — fejler**

Run: `python3 .claude/skills/daa-extract/scripts/test_validate.py 2>&1 | tail -4`
Expected: FAIL — `derive_date_bounds` findes ikke.

- [ ] **Step 3: Implementér `derive_date_bounds`**

```python
_MDR = {'jan':1,'feb':2,'mar':3,'apr':4,'maj':5,'jun':6,'jul':7,'aug':8,'sep':9,'okt':10,'nov':11,'dec':12}
def derive_date_bounds(date_raw):
    """Udled (date_min, date_max) ISO deterministisk fra rå dato. Kun år -> hele
    året; dag-måned-år -> punkt. Uparsebart/span -> (None, None); date_raw bevares
    altid andetsteds. LLM'en skal IKKE selv syntetisere disse."""
    if not date_raw: return (None, None)
    t = date_raw.strip().lower()
    years = re.findall(r'\d{4}', t)
    if len(years) != 1:                       # span (1680-1720) eller intet: overlad til raw
        return (None, None)
    y = years[0]
    dm = re.search(r'(\d{1,2})\.\s*([a-zæøå]+)', t)
    if dm and dm.group(2)[:3] in _MDR:
        mo = _MDR[dm.group(2)[:3]]; da = int(dm.group(1))
        iso = f"{y}-{mo:02d}-{da:02d}"; return (iso, iso)
    return (f"{y}-01-01", f"{y}-12-31")
```

- [ ] **Step 4: Kald i `normalize_record` + hærd R1**

I `normalize_record` (efter boern-blokken), tilføj:
```python
    for f in rec.get('facts') or []:
        if f.get('date_raw'):
            lo, hi = derive_date_bounds(f['date_raw'])
            f['date_min'], f['date_max'] = lo, hi
```
I `validate()`, udbyg R1 (efter den eksisterende årstals-løkke): for hvert fakta med både `date_min` og `date_raw`, tjek at `date_min`'s år står i `date_raw`:
```python
    for f in (rec.get('facts') or []):
        dmin = f.get('date_min')
        if dmin and f.get('date_raw'):
            yr = dmin[:4]
            if yr not in f['date_raw']:
                issues.append(f'R1: date_min-år {yr} findes ikke i date_raw "{f["date_raw"]}" (fejl-attribueret dato?)')
```

- [ ] **Step 5: Kør tests**

Run: `python3 .claude/skills/daa-extract/scripts/test_validate.py 2>&1 | tail -3`
Expected: OK.

- [ ] **Step 6: Commit**

```bash
git add .claude/skills/daa-extract/scripts/validate.py .claude/skills/daa-extract/scripts/test_validate.py
git commit -m "feat(daa-validate): deterministisk dato-udledning + hærdet R1 mod fejl-attribuering"
```

---

### Task 5: `load_daa.R` — partner-dedup via `partner_ekstern_ref`

Når en ægtefælle har en intern reference ("se nr. 97") til en person der allerede findes i denne kilde, link den eksisterende person i stedet for at oprette en dublet-stub.

**Files:**
- Modify: `.claude/skills/daa-extract/scripts/load_daa.R:227-257` (ægteskabs-løkken)
- Modify: `.claude/skills/daa-extract/scripts/load_helpers.R` (ren parser)
- Test: `tests/testthat/test-load-daa.R`

**Interfaces:**
- Produces: `parse_intern_ref(ref, default_linje)` → `list(linje=..., nr=...)` eller `NULL` hvis `ref` ikke er en intern se-nr (eksterne "DAA 1937, II, 122" → `NULL`, så de stadig oprettes som stub).

- [ ] **Step 1: Skriv de fejlende tests**

```r
test_that("parse_intern_ref genkender interne se-nr", {
  expect_equal(parse_intern_ref("se nr. 97", "I"), list(linje="I", nr="97"))
  expect_equal(parse_intern_ref("nr. 106", "III"), list(linje="III", nr="106"))
  expect_equal(parse_intern_ref("von Reventlow. III. Den mecklenburgske linje, nr. 79", "I"),
               list(linje="III", nr="79"))
})
test_that("parse_intern_ref afviser eksterne udgave-refs", {
  expect_null(parse_intern_ref("DAA 1937, II, 122", "I"))
  expect_null(parse_intern_ref("DAA 1913, 135", "I"))
  expect_null(parse_intern_ref(NA, "I"))
})
```

- [ ] **Step 2: Kør — fejler**

Run: `Rscript run-tests.R 2>&1 | grep -A2 parse_intern_ref`
Expected: FAIL.

- [ ] **Step 3: Implementér i `load_helpers.R`**

```r
# Intern reference = "se nr. N" / "nr. N" / "… linje, nr. N" i SAMME kilde.
# Ekstern (anden DAA-udgave, "DAA 1937, II, 122") -> NULL: stub oprettes stadig.
parse_intern_ref <- function(ref, default_linje) {
  if (is.null(ref) || length(ref) == 0 || is.na(ref)) return(NULL)
  if (grepl("DAA|\\b1[89]\\d\\d\\b", ref)) return(NULL)   # ekstern udgave
  linje <- default_linje
  lm <- regmatches(ref, regexpr("\\b(I{1,3}V?|VI{0,3})\\b(?=\\.?\\s*Den|,\\s*nr)", ref, perl=TRUE))
  if (length(lm) && nzchar(lm)) linje <- lm
  nm <- regmatches(ref, regexpr("nr\\.?\\s*(\\d+)", ref, perl=TRUE))
  if (!length(nm) || !nzchar(nm)) return(NULL)
  nr <- sub(".*?(\\d+).*", "\\1", nm)
  list(linje = linje, nr = nr)
}
```

- [ ] **Step 4: Wire ind i ægteskabs-løkken (`load_daa.R:230`)**

Erstat blokken `if (!is.null(a$partner_navn) && !is.na(a$partner_navn)) {` … `add_member(fam, sp, "partner", ordinal = g(a, "ordinal"))` med en variant der først prøver at genfinde en eksisterende person:
```r
      ref <- parse_intern_ref(g(a, "partner_ekstern_ref"), rec$linje)
      existing_key <- if (!is.null(ref)) key(ref$linje, ref$nr) else NULL
      if (!is.null(existing_key) && exists(existing_key, envir = pmap, inherits = FALSE)) {
        add_member(fam, get(existing_key, envir = pmap), "partner", ordinal = g(a, "ordinal"))
      } else if (!is.null(a$partner_navn) && !is.na(a$partner_navn)) {
        sp <- add_person(); sp_t <- split_title(a$partner_navn)
        # ... (uændret stub-oprettelse som i dag: navn/titel/datoer/note/add_member)
      }
```
(Behold den eksisterende stub-krop uændret i `else if`-grenen.)

- [ ] **Step 5: Kør tests + dry-run-smoke**

Run: `Rscript run-tests.R 2>&1 | tail -3`
Expected: PASS.
Run: `Rscript .claude/skills/daa-extract/scripts/load_daa.R work/clean_full2.json "DAA 2018-20" --no-reset --dry-run 2>&1 | grep person`
Expected: lavere `person`-tal end før dedup (færre stubs). Notér tallet.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat(daa-load): dedup ægtefælle via partner_ekstern_ref (link eksisterende, opret ikke dublet)"
```

---

### Task 6: `load_daa.R` — observerbar barn-linking

Hvert uopløst barn-opslag logges med årsag (i dag droppes de tavst — jf. review-punkt C1). Producerer en rapport der gør Etape 2's måling mulig.

**Files:**
- Modify: `.claude/skills/daa-extract/scripts/load_daa.R:258-281` (barn-løkken), transaktions-slut
- Test: `tests/testthat/test-load-daa.R`

**Interfaces:**
- Produces: en akkumulator `.unresolved` (env) med rækker `list(forael_linje, forael_nr, barn_nr, aarsag)`; skrives til `work/load-unresolved.csv` og optælles til stderr efter load.

- [ ] **Step 1: Skriv den fejlende test (ren klassifikator)**

```r
test_that("barn_lookup_reason klassificerer opslag", {
  pmap_keys <- c("I-30", "I-31")
  expect_equal(barn_lookup_reason("I", "30", pmap_keys), "ok")
  expect_equal(barn_lookup_reason("I", "99", pmap_keys), "nr_ikke_i_linje")
})
```

- [ ] **Step 2: Kør — fejler**

Run: `Rscript run-tests.R 2>&1 | grep -A2 barn_lookup_reason`
Expected: FAIL.

- [ ] **Step 3: Implementér i `load_helpers.R`**

```r
# Hvorfor et barn-opslag (linje,nr) ikke kunne linkes. pmap_keys = kendte "linje-nr".
barn_lookup_reason <- function(linje, nr, pmap_keys) {
  if (paste0(linje, "-", nr) %in% pmap_keys) "ok" else "nr_ikke_i_linje"
}
```

- [ ] **Step 4: Wire ind i barn-løkken (`load_daa.R:264-280`)**

Tilføj `.unresolved <- new.env(parent=emptyenv()); .unresolved$rows <- list()` ved buffer-init (nær linje 64). I løkken, i `else`-grenen hvor `ck` er `NULL`:
```r
        if (!is.null(ck)) {
          konf <- if (isTRUE(get0(ck, envir = umap, inherits = FALSE))) "formodet" else NA
          add_member(fam, get(ck, envir = pmap), "barn", konfidens = konf)
        } else {
          .unresolved$rows <- c(.unresolved$rows, list(list(
            forael_linje = rec$linje, forael_nr = lbl_of(rec), barn_nr = as.character(n),
            aarsag = barn_lookup_reason(rec$linje, as.character(n), ls(pmap)))))
        }
```
Efter load (før `dbDisconnect`), skriv rapporten:
```r
  if (length(.unresolved$rows)) {
    ur <- do.call(rbind, lapply(.unresolved$rows, as.data.frame, stringsAsFactors=FALSE))
    write.csv(ur, "work/load-unresolved.csv", row.names = FALSE)
    message(sprintf("BEMÆRK: %d uopløste barn-opslag — se work/load-unresolved.csv", nrow(ur)))
  }
```

- [ ] **Step 5: Kør tests + dry-run**

Run: `Rscript run-tests.R 2>&1 | tail -3`
Expected: PASS.
Run: `Rscript .claude/skills/daa-extract/scripts/load_daa.R work/clean_full2.json "DAA 2018-20" --no-reset --dry-run 2>&1 | grep uopløste`
Expected: en optælling; inspicér `work/load-unresolved.csv`.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat(daa-load): observerbar barn-linking — log uopløste opslag med årsag"
```

---

### Task 7: `load_daa.R` — 15a/15b basenr → label-opslag

Børn af en 15a/15b-forælder kan i dag aldrig linkes (opslag på "15" mod nøgle "15a"). Slå basenr op mod alle labels med samme basenr.

**Files:**
- Modify: `.claude/skills/daa-extract/scripts/load_daa.R:274` (nøgle-opslag), `load_helpers.R`
- Test: `tests/testthat/test-load-daa.R`

**Interfaces:**
- Produces: `resolve_barn_keys(linje, nr, pmap_keys)` → character-vektor af matchende nøgler. Basenr "15" matcher "I-15", ellers "I-15a"+"I-15b" hvis rene "15" ikke findes.

- [ ] **Step 1: Skriv den fejlende test**

```r
test_that("resolve_barn_keys foretrækker eksakt basenr, ellers a/b-varianter", {
  expect_equal(resolve_barn_keys("I", 15, c("I-15","I-15a")), "I-15")
  expect_setequal(resolve_barn_keys("I", 15, c("I-15a","I-15b")), c("I-15a","I-15b"))
  expect_equal(resolve_barn_keys("I", 99, c("I-15")), character(0))
})
```

- [ ] **Step 2: Kør — fejler**

Run: `Rscript run-tests.R 2>&1 | grep -A2 resolve_barn_keys`
Expected: FAIL.

- [ ] **Step 3: Implementér i `load_helpers.R`**

```r
resolve_barn_keys <- function(linje, nr, pmap_keys) {
  eksakt <- paste0(linje, "-", nr)
  if (eksakt %in% pmap_keys) return(eksakt)
  varianter <- grep(sprintf("^%s-%d[a-z]$", linje, nr), pmap_keys, value = TRUE)
  varianter
}
```

- [ ] **Step 4: Wire ind (`load_daa.R:274-279`)**

Erstat den enkelte `k2`/`ck`-udledning med en løkke over `resolve_barn_keys`:
```r
        for (ck in resolve_barn_keys(rec$linje, n, ls(pmap))) {
          konf <- if (isTRUE(get0(ck, envir = umap, inherits = FALSE))) "formodet" else NA
          add_member(fam, get(ck, envir = pmap), "barn", konfidens = konf)
        }
```
(Uopløst-logging fra Task 6 flyttes til `if (!length(resolve_barn_keys(...)))`.)

- [ ] **Step 5: Kør tests + dry-run**

Run: `Rscript run-tests.R 2>&1 | tail -3`
Expected: PASS. Dry-run: `work/load-unresolved.csv` har færre rækker end i Task 6.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "fix(daa-load): link børn af 15a/15b-forældre via basenr-varianter"
```

---

### Task 8: `load_daa.R` — bind børn til rette union via `aegteskab_kontekst`

I dag knyttes alle børn til første union. Brug `aegteskab_kontekst` ("af første/andet ægteskab") + `kuld` (fra Task 3) til at vælge den korrekte union.

**Files:**
- Modify: `.claude/skills/daa-extract/scripts/load_daa.R:258-281`
- Modify: `load_helpers.R`
- Test: `tests/testthat/test-load-daa.R`

**Interfaces:**
- Consumes: `rec$aegteskab_kontekst` (fra Task 3), `fams` (liste af family-id i ordinal-rækkefølge).
- Produces: `union_index_for_kontekst(kontekst)` → 1-baseret indeks eller `NA` (→ fald tilbage til union 1). "af første ægteskab" → 1, "af andet ægteskab"/"2. ægteskab" → 2, osv.

- [ ] **Step 1: Skriv den fejlende test**

```r
test_that("union_index_for_kontekst mapper ordinal-tekst til indeks", {
  expect_equal(union_index_for_kontekst("af første ægteskab med Anna von Ahlefeldt"), 1L)
  expect_equal(union_index_for_kontekst("af andet ægteskab med NN"), 2L)
  expect_equal(union_index_for_kontekst("af 3. ægteskab"), 3L)
  expect_true(is.na(union_index_for_kontekst("med Elisabeth NN (se nr. 1)")))
  expect_true(is.na(union_index_for_kontekst(NULL)))
})
```

- [ ] **Step 2: Kør — fejler**

Run: `Rscript run-tests.R 2>&1 | grep -A2 union_index_for_kontekst`
Expected: FAIL.

- [ ] **Step 3: Implementér i `load_helpers.R`**

```r
union_index_for_kontekst <- function(kontekst) {
  if (is.null(kontekst) || length(kontekst) == 0 || is.na(kontekst)) return(NA_integer_)
  k <- tolower(kontekst)
  ord <- c("første"=1L,"anden"=2L,"andet"=2L,"tredje"=3L,"fjerde"=4L,"femte"=5L)
  for (w in names(ord)) if (grepl(paste0("\\b", w, " ægteskab"), k)) return(ord[[w]])
  m <- regmatches(k, regexpr("(\\d+)\\.\\s*ægteskab", k))
  if (length(m) && nzchar(m)) return(as.integer(sub("\\..*", "", m)))
  NA_integer_
}
```

- [ ] **Step 4: Wire ind i barn-løkken (`load_daa.R:260-262`)**

Erstat `fam <- if (length(fams)) fams[[1]] else add_family("union")` med:
```r
      ui <- union_index_for_kontekst(rec$aegteskab_kontekst)
      fam <- if (length(fams) && !is.na(ui) && ui <= length(fams)) fams[[ui]]
             else if (length(fams)) fams[[1]]
             else add_family("union")
```

- [ ] **Step 5: Kør tests + dry-run**

Run: `Rscript run-tests.R 2>&1 | tail -3`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat(daa-load): bind børn til korrekt union via aegteskab_kontekst-ordinal"
```

---

### Task 9: Frys trin ③-prompten som fil i skillen

Etape 3 kræver en reproducerbar prompt (jf. review-punkt D). Kanonisér den nuværende prompt fra `work/EXTRACT_PROMPT.md` + `work/extract_kit/INSTRUKTION.md` som en versioneret skill-fil, så "Sonnet 5 vs Sonnet 4.6" kan sammenlignes uden prompt-drift.

**Files:**
- Create: `.claude/skills/daa-extract/references/extract-prompt.md`
- Modify: `.claude/skills/daa-extract/SKILL.md:90-104` (peg på filen i stedet for punktliste)

**Interfaces:**
- Produces: én autoritativ promptfil trin ③ altid bruger; SKILL.md's §③ refererer den frem for at genkomponere krav.

- [ ] **Step 1: Konsolidér prompten**

Kopiér indholdet af `work/EXTRACT_PROMPT.md` (verificeret komplet: regler, rygrad-definition, embeder-vs-karriere) til `.claude/skills/daa-extract/references/extract-prompt.md`, tilføj øverst en versionslinje: `<!-- prompt-version: 2026-07-02 (Sonnet 5-baseline) -->` og en note om at hver dato-værdi skal stå ordret i `raw_text`, og at `date_min`/`date_max` nu udledes deterministisk i trin ④ (LLM leverer kun `date_raw`).

- [ ] **Step 2: Ret SKILL.md §③**

Erstat punktlisten "Prompten til hver post … skal indeholde:" med: `Brug den frosne prompt i \`references/extract-prompt.md\` uændret. Rediger promptfilen (ikke ad hoc), og bump prompt-version ved ændringer.`

- [ ] **Step 3: Verificér ingen dangling reference**

Run: `grep -n "archetype.md\|extract-prompt" .claude/skills/daa-extract/SKILL.md`
Expected: SKILL.md peger nu på `docs/daa-extraction-archetype.md` (fuld sti) og `references/extract-prompt.md`. Ret samtidig den forkerte `references/archetype.md`-reference (linje 117) → `docs/daa-extraction-archetype.md`.

- [ ] **Step 4: Commit**

```bash
git add .claude/skills/daa-extract/references/extract-prompt.md .claude/skills/daa-extract/SKILL.md
git commit -m "docs(daa-extract): frys trin ③-prompt som versioneret skill-fil + ret dangling reference"
```

---

# ETAPE 2 — Gratis re-load fra eksisterende udtræk (0 tokens)

Kør den rettede pipeline mod det udtræk der allerede ligger på disk. Måler hvor meget af problemet Etape 1 løser — uden en eneste token.

**Forudsætning:** Etape 1 Task 0-8 færdige og committet. Task 0's a/b-fordeling indsat her: `a_samme_linje=___  b_kryds_linje=___`.

- [ ] **Trin 1: Re-validér det eksisterende udtræk med den nye validate.py**

```bash
python3 .claude/skills/daa-extract/scripts/validate.py \
  work/posts_full.json work/extracted/ \
  --clean work/clean-v2.json --review work/review-v2.json --escalate work/escalation-v2.json
```
Dette anvender deterministisk dato-udledning (Task 4) + kontekst-merge (Task 3) på det eksisterende udtræk. Notér antal rene/flaggede vs. den gamle kørsel.

- [ ] **Trin 2: Etablér TNG-QA baseline FØR re-load**

Kør TNG-QA-pipelinen mod den nuværende prod-tilstand og gem rapporten som baseline (den findes allerede: `docs/reviews/tng-qa-rapport-2026-07-01.md`). Notér nøgletal: `mangler_hos_os=125, dato_uenig=4, ekstra_hos_os=0`.

- [ ] **Trin 3: Dry-run mod testbasen**

```bash
Rscript .claude/skills/daa-extract/scripts/load_daa.R work/clean-v2.json "DAA 2018-20" --no-reset --dry-run
```
Expected: person-tal lavere end 925 (dedup virker), `work/load-unresolved.csv` skrevet. Inspicér uopløste barn-opslag: krydstjek mod Task 0's bucket-a-liste — er de forventede samme-linje-børn nu linket?

- [ ] **Trin 4: BESLUTNINGS-GATE — vælg re-load-strategi**

To muligheder, afgøres med brugeren:
- **(A) Differentiel re-load** (`--no-reset`): sikrest, bevarer redaktionelt arbejde + change-historik, men kræver at dedup-nøglen (`person_external_id`) matcher eksisterende rækker. Kræver upsert-logik der IKKE er i denne plan (se "Udestår" nedenfor).
- **(B) Fuld RESET-reload**: kun hvis prod endnu ikke har redaktionelt arbejde værd at bevare (RESET-guarden fra Task 2 afgør dette maskinelt). Simplest, men sletter change-historik.

**Kør ikke mod prod uden eksplicit brugergodkendelse** (global §5/§8). Bekræft target-base (`SELECT count(*) FROM person` skal vise prod, ikke testbasens 3).

- [ ] **Trin 5: Re-load (efter godkendelse) + regenerér cache**

Loaderen regenererer selv `visning_*` + `levende` til sidst. Efter load: kør TNG-QA igen → `docs/reviews/tng-qa-rapport-<dato>.md`.

- [ ] **Trin 6: Mål effekten (dette er hele pointen med Etape 2)**

Sammenlign ny rapport mod baseline:
```bash
diff <(grep -E "mangler_hos_os|dato_uenig|ekstra_hos_os" docs/reviews/tng-qa-rapport-2026-07-01.md) \
     <(grep -E "mangler_hos_os|dato_uenig|ekstra_hos_os" docs/reviews/tng-qa-rapport-<ny-dato>.md)
```
**Forventning (kalibreret mod nøglefund):** `mangler_hos_os` falder med ca. `a_samme_linje`-tallet fra Task 0 (bucket a er det Etape 1 kan genindvinde). Bucket b forbliver — det er kryds-linje, som kræver Etape 4's TNG-corroboration. Dubletter (person-tal) falder. Skriv resultatet i `docs/reviews/12-etape2-reload-effekt.md`.

- [ ] **Trin 7: GATE til Etape 3** — kun de poster hvor TNG-QA stadig viser `dato_uenig` eller R8-advisories (manglende ægteskab/død) efter re-load er kandidater til re-udtræk. Byg listen:
```bash
grep -E "dato_uenig|R8" docs/reviews/tng-qa-rapport-<ny-dato>.md work/review-v2.json > work/reextract-kandidater.txt
```

---

# ETAPE 3 — Målrettet Sonnet 5-re-udtræk (~5-8M tokens)

Kun de poster hvor selve udtrækket er problemet — ikke de 125 links (som Etape 1/4 dækker). Forventet omfang: 100-150 poster, ikke 591.

**Forudsætning:** Etape 2 færdig; `work/reextract-kandidater.txt` bygget; Task 9 (frossen prompt) færdig.

- [ ] **Trin 1: Peg extract_all.py på Sonnet 5**

I `work/extract_all.py:MODEL` (linje ~30): sæt default til `claude-sonnet-5` (verificér eksakt model-id mod `/claude-api`-skill før kørsel — id'et er `claude-sonnet-5`). Behold `--model`-forwarding og `CLAUDE_EFFORT=low` (kost-kontrol, jf. memory).

- [ ] **Trin 2: Snapshot de nuværende udtræk**

```bash
for f in $(cut -d' ' -f1 work/reextract-kandidater.txt | sort -u); do
  cp "work/extracted/$f.json" "work/extracted/$f.sonnet46.json" 2>/dev/null
done
```

- [ ] **Trin 3: Re-udtræk KUN kandidaterne med den frosne prompt**

Byg en delmængde-posts-fil med kun kandidaterne og kør `extract_all.py` mod den, med `--model claude-sonnet-5`. Prompten hentes fra `references/extract-prompt.md` (Task 9) — ikke ad hoc.

- [ ] **Trin 4: Validér + eskalerings-merge (promote-gate)**

```bash
python3 .claude/skills/daa-extract/scripts/validate.py work/posts_full.json work/extracted/ \
  --clean work/clean-v3.json --review work/review-v3.json --escalate work/escalation-v3.json
python3 .claude/skills/daa-extract/scripts/escalate_merge.py work/posts_full.json \
  work/extracted/ work/extracted/ work/escalation-v3.json work/clean-v3.json work/review-v3.json \
  --diff work/reextract-diff.md
```
Inspicér `work/reextract-diff.md`: viser Sonnet 5's ændringer per post. **Menneske-gate:** promoverede poster med feltændringer i embeder/godser/begivenheder (regel-fri felter) skal øjes manuelt — promote-gaten ser kun R1-R8.

- [ ] **Trin 5: Re-load + mål mod TNG-QA igen** (samme protokol som Etape 2 Trin 5-6). Dokumentér i `docs/reviews/13-etape3-reextract-effekt.md`.

---

# ETAPE 4 — Fuldt re-udtræk (betinget) + TNG-som-kilde

To spor, hvert betinget på et målt kriterium fra tidligere etaper.

## Spor A — Fuldt re-udtræk (kun hvis stikprøven kræver det)

**Betingelse:** Kør stikprøve-protokollen på det nuværende udtræk FØR du beslutter dig:
- [ ] Udtræk 15 tilfældige clean-poster, læg prosa side om side med det strukturerede udtræk, tæl fakta-fejl manuelt.
- [ ] **Gate:** hvis fejlraten > ~10% på fakta som de målrettede kandidater (Etape 3) ikke dækkede → fuldt Sonnet 5-re-udtræk berettiget. Ellers spring Spor A over (ikke token-værd).
- [ ] Hvis kørt: fuld `extract_all.py --model claude-sonnet-5` over alle 591 poster med frossen prompt → validate → escalate → re-load. Fordi loaderen (Etape 1) og prompten (Task 9) nu er rettet, spildes intet.

## Spor B — TNG som selvstændig kilde (løser bucket b — kryds-linje-links)

Dette er den korrekte brug af TNG, jf. datamodellens design: TNG loades som en **separat `source`** hvis udsagn bliver **påstande ved siden af** DAA's, ikke en korrektionsmotor der overskriver.

- [ ] **Trin 1: Genbrug fase 1-corroboration-planen.** `docs/superpowers/plans/2026-07-01-tng-qa-relationel-corroboration-fase1.md` beriger allerede review-køen med familie-støtte-signal. Byg videre på den — skriv ikke en parallel mekanisme.
- [ ] **Trin 2: For bucket b (kryds-linje-links fra Task 0)** — hvor TNG's familie-graf bekræfter et forælder-barn-forhold DAA's global-nr-genbrug gjorde tvetydigt: opret en TNG-`source`, load forholdet som en `family_member`-relation med `konfidens` afledt af TNG-tier, og lad en `conclusion` afgøre. Disse er præcis de links Etape 1 bevidst ikke genindvandt (egen-linje-only-reglen fra review 11).
- [ ] **Trin 3: Beslutnings-gate med bruger** — TNG-som-kilde er en modelbeslutning (ny kilde i evidenslaget). Egner sig til en OpenSpec-proposal før implementering, da det udvider datagrundlagets kilde-sæt.

---

## Udestår / bevidst uden for denne plan

- **Differentiel upsert-loader (Etape 2 mulighed A):** kræver `person_external_id`-baseret upsert i stedet for append. Ikke i denne plan — hvis RESET-guarden (Task 2) blokerer, er dette næste skridt og bør være egen OpenSpec-proposal (ændrer loader-kontrakten fundamentalt).
- **Cross-source person-dedup mod `/daa-presens`-append:** presens-listen appender nulevende som separat kilde uden identitetssammenkædning. Egen opgave.
- **`derive_boern` finditer (flere kuld pr. post):** YAGNI for denne udgave (0 poster). Genovervej ved ny udgave.
- **R7-udvidelse til godser/embeder/begivenheder:** proveniens-gate dækker kun facts+ægteskaber. Separat hærdning.

## Self-review-noter

- **Spec-dækning:** de fire etaper fra brugerens anmodning er alle dækket (1: Task 1-9; 2: gratis re-load; 3: målrettet re-udtræk; 4: fuldt re-udtræk + TNG). Nøglefund #1 (bucket c=0) er indarbejdet ved at flytte relations-genindvinding fra Etape 3 til Etape 1 og eksplicit adskille bucket a (Etape 1) fra bucket b (Etape 4 Spor B).
- **Type-konsistens:** `parse_intern_ref`/`resolve_barn_keys`/`union_index_for_kontekst`/`barn_lookup_reason`/`has_editorial_changes`/`buffer_counts` bor alle i `load_helpers.R` og testes i `tests/testthat/test-load-daa.R`; `merge_kontekst`/`derive_date_bounds` i `validate.py` + `test_validate.py`.
- **Sikkerhed:** RESET-guard (Task 2) + target-base-bekræftelse (Etape 2 Trin 4) beskytter mod TRUNCATE mod prod med redaktionelt indhold.
