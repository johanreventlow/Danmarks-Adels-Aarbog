# Fase C0's efterkørsel — de 9 record-koblinger: implementeringsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Erstat ni personers 1939-narrativ med den normaliserede record-tekst og opret bindingen, bag et menneskeark på otte orddelingsvalg og en fail-closed apply.

**Architecture:** Fem artefakter i kæde — read-only eksport (R) → normalisering + flag-udtræk (Python) → menneskeark + fail-closed konverter (Python) → hash-låst manifest (Python) → apply (R). Trin 1–4 kan køres og gennemgås uden at prod kan røres; trin 5 kan kun udføre det, der står i et hash-låst manifest. Den rene beslutnings-anvendelse importeres fra fase B's manifest-bygger (verificeret mod 178 ægte flag); kun writeren er ny.

**Tech Stack:** R (DBI/RPostgres/jsonlite/digest), testthat, Python 3 (stdlib), pytest, PostgreSQL 17/Supabase.

**Spec:** `docs/superpowers/specs/2026-08-21-1939-v50-fase-c0-efterkoersel-design.md`

## Global Constraints

- **De ni person-id'er er faste:** `963, 967, 978, 991, 992, 1296, 1297, 1298, 1299`. Person **1017 er IKKE med** — den er flyttet til C3.
- **Prod-wrappere skal være fail-closed.** Ethvert skrivende script SKAL kræve `--jeg-mener-det`, `--expect-sha256` og `--backup`, og SKAL afvise ukendte og duplikerede flag. Baggrund: i fase D1 blev et opfundet `--dryrun` ignoreret, og 68 personer blev publiceret uden godkendelse.
- **`narrative_norm_v1` er obligatorisk.** C0's `verbatim_text` er rå OCR: alle ni har enlige linjeskift, syv har uopløste orddelinger, 1299 bærer `### PAGE 0063 ###`, 1297 trailing whitespace. Reglerne må ALDRIG genimplementeres — `normalize_narrative_1939_v50.py` importeres.
- **`p_side := NULL`.** `red_upsert_narrativ`s UPDATE-gren skriver `side = COALESCE(p_side, side)`. Efterkørslen retter tekst, ikke sidetal. Men `narrative.side` SKAL sammenlignes mod recordens `page_from` som identitetskontrol (målt 2026-08-21: 9/9 match).
- **`privat = TRUE` på nogen af de ni → ABORT.** Writeren sender altid `p_privat := false`, så en privat post ville blive tavst afprivatiseret. Det er et GDPR-brud (invariant 8), ikke en datafejl.
- **Fejlkoder er stabile strenge** i `SCREAMING_SNAKE_CASE` med prefikset `C0F_`.
- **R-scripts læser forbindelsen** fra `PGHOST`/`PGDATABASE`/… med fallback til `SUPABASE_*` — samme `env_or`-mønster som `export_d2_spouse_selection_1939_v50.R`. Sæt ALLE fem `PG*`-variabler ved lokal omdirigering; env_or falder tilbage per variabel, så en manglende `PGHOST` sender scriptet mod PROD.
- **Aktør-etablering:** `red_upsert_narrativ` og `red_publicer_narrative_record` gates på `current_rolle()='redaktion'`. Over en direkte forbindelse er `auth.uid()` NULL → rollen bliver `medlem`. Sæt `set_config('request.jwt.claim.sub', 'ba4ce28d-42a0-48af-a47c-773c26934236', true)` INDE i transaktionen via `dbGetQuery` (ikke `dbExecute`) og verificér mod `profiles` før skrivning.

## Værn-sporing: spec'ens dækningstabel → denne plan

Hele begrundelsen for at bygge en ny writer frem for at genbruge fase B's var,
at hvert af dens værn skulle genbruges eller fravælges **med begrundelse**.
Denne tabel er kontrollen: findes der en task uden en linje her, er et værn
glemt — ikke fravalgt.

| Fase B's værn | Bæres af | Fejlkode |
|---|---|---|
| `OLD_SHA_MISMATCH` | Task 5 (`c0f_plan_apply`) | `C0F_APPLY_OLD_SHA_MISMATCH` |
| `privat=TRUE` → abort | Task 1 + Task 5 | `C0F_SELECTION_PRIVAT`, `C0F_APPLY_PRIVAT` |
| `side` som identitetskontrol | Task 2 + Task 5 | `C0F_FLAGS_SIDE_MISMATCH`, `C0F_APPLY_SIDE_MISMATCH` |
| Slutinvarianter (`### PAGE`, enligt `\n`, trailing ws) | Task 2 (`assert_invariants`) + Task 4 (`_assert_invariants` på den FÆRDIGE tekst) | `C0F_FLAGS_INVARIANT_*`, `C0F_MANIFEST_INVARIANT_*` |
| `ALREADY_BOUND` | Task 5 | `C0F_APPLY_ALREADY_BOUND` |
| `ORDER_INVALID` | Task 1 (sorteret + `sort()`-sammenligning fanger dubletter) | `C0F_SELECTION_IDS_INVALID` |
| `COUNTS_INVALID` (hårdkodet 9) | Task 1 + Task 2 | `C0F_SELECTION_COUNT_INVALID`, `C0F_FLAGS_IDS_INVALID` |
| `INPUT_HASHES_INVALID` | Task 2 (`input_hashes` over selection/candidates/decisions) | — (hashes bæres i dokumentet; manifestets egen lås er `C0F_APPLY_MANIFEST_SHA_MISMATCH`) |
| Advisory lock | Task 5 (`pg_try_advisory_xact_lock`, samme nøgle som fase B) | `C0F_APPLY_LOCK_BUSY` |
| `CANONICAL_INVALID` | Task 2 + Task 4 (`json.dumps(sort_keys=True)`), **bevist** af Task 2's PYTHONHASHSEED-kørsel | — (determinisme testes, ikke hævdes) |
| `OUT_OF_SCOPE_INVALID` | Task 1 + Task 2 (kun de ni id'er) | `C0F_SELECTION_IDS_INVALID`, `C0F_FLAGS_IDS_INVALID` |
| `BINDING_ARITHMETIC_INVALID` | Task 4 (`counts.bindings_create`) + Task 5 (efterkontrol) | `C0F_APPLY_POSTCHECK_MISMATCH` |
| `SIDE_CORRECTIONS_INVALID` | **Fravalgt.** Fase B havde to poster med forkert trykt sidetal, som krævede en registreret korrektion. Alle ni matcher her, så en afvigelse skal være terminal, ikke korrigerbar | — |
| `FLAGS_INVALID` | Task 4 (`VALID_ACTIONS`) | `C0F_MANIFEST_ACTION_INVALID`, `C0F_MANIFEST_FLAG_KIND_UNKNOWN` |
| `SOURCE_INVALID` | Task 1, 2 og 5 (`source_id = 3` overalt) | — (hårdkodet, ingen vej til en anden kilde) |

**Plus D2's lærdomme** — alle i Task 5: `--jeg-mener-det`, obligatorisk
`--expect-sha256` og `--backup`, drift-guard målt *inde i* transaktionen,
nul-delta-efterkontrol, eksplicit `tryCatch`-rollback, `dbGetQuery` til
`set_config`, aktør-etablering + verifikation mod `profiles`, og
tilstedeværelses-assertion før hver fail-closed gate
(`C0F_APPLY_TAELLING_MANGLER`, `C0F_SELECTION_KOLONNE_MANGLER`).

---

---

### Task 1: Read-only eksport af de ni personers nuværende tilstand

**Files:**
- Create: `.claude/skills/daa-extract/scripts/export_c0_followup_selection_1939_v50_helpers.R`
- Create: `.claude/skills/daa-extract/scripts/export_c0_followup_selection_1939_v50.R`
- Create: `.claude/skills/daa-extract/scripts/test_export_c0_followup_selection_1939_v50.R`
- Create: `tests/testthat/test-export-c0-followup-selection-1939-v50.R`

**Interfaces:**
- Consumes: intet fra tidligere tasks.
- Produces: `build_c0_followup_selection_1939_v50(rows, database_name, database_identity, generator)` → `list` med `schema_version`, `database_name`, `database_identity`, `generator`, `selected` (sorteret på `person_id`; hvert element har `person_id`, `narrative_id`, `old_sha256`, `privat`, `side`). Task 2 læser den JSON.

- [ ] **Step 1: Write the failing test**

Create `.claude/skills/daa-extract/scripts/test_export_c0_followup_selection_1939_v50.R`:

```r
## DB-fri tests for export_c0_followup_selection_1939_v50_helpers.R.
script_arg <- grep("^--file=", commandArgs(), value = TRUE)[1L]
script_dir <- if (!is.na(script_arg) && !identical(script_arg, "--file=-e")) {
  dirname(normalizePath(sub("^--file=", "", script_arg)))
} else {
  getwd()
}
source(file.path(script_dir, "export_c0_followup_selection_1939_v50_helpers.R"))

ok <- 0L
expect <- function(value, message = "expectation failed") {
  if (!isTRUE(value)) stop(message, call. = FALSE)
  ok <<- ok + 1L
}
expect_error <- function(expr, pattern) {
  got <- tryCatch({ force(expr); "" }, error = function(e) conditionMessage(e))
  expect(grepl(pattern, got, fixed = TRUE), paste(pattern, got))
}

SHA <- paste(rep("a", 64), collapse = "")
fixture_rows <- function() {
  data.frame(
    person_id = c(967, 963, 978, 991, 992, 1296, 1297, 1298, 1299),
    narrative_id = c(636, 632, 647, 660, 661, 965, 966, 967, 968),
    old_sha256 = rep(SHA, 9),
    privat = rep(FALSE, 9),
    side = c("508", "508", "509", "504", "504", "574", "574", "574", "574"),
    stringsAsFactors = FALSE
  )
}

## 1) Lykkelig sti: sorteret paa person_id, alle felter baaret videre.
doc <- build_c0_followup_selection_1939_v50(fixture_rows(), "postgres", "764273", "test")
expect(identical(doc$schema_version, "1.0"))
expect(identical(length(doc$selected), 9L))
expect(identical(doc$selected[[1]]$person_id, 963))
expect(identical(doc$selected[[9]]$person_id, 1299))
expect(identical(doc$selected[[1]]$side, "508"))

## 2) Antallet er laast til NI. 1017 er flyttet til C3, og et tiende id ville
##    betyde at nogen har genindsat den -- eller at udvalget er skredet.
expect_error(build_c0_followup_selection_1939_v50(
  fixture_rows()[1:8, ], "postgres", "764273", "test"), "C0F_SELECTION_COUNT_INVALID")

## 3) Praecis DE ni id'er -- ikke ni vilkaarlige.
forkert <- fixture_rows(); forkert$person_id[[1]] <- 1017
expect_error(build_c0_followup_selection_1939_v50(
  forkert, "postgres", "764273", "test"), "C0F_SELECTION_IDS_INVALID")

## 4) privat=TRUE er et GDPR-broud (invariant 8), ikke en datafejl: writeren
##    sender altid p_privat=false, saa posten ville blive tavst afprivatiseret.
priv <- fixture_rows(); priv$privat[[3]] <- TRUE
expect_error(build_c0_followup_selection_1939_v50(
  priv, "postgres", "764273", "test"), "C0F_SELECTION_PRIVAT")

## 4b) NA spaerrer ogsaa: publicering skal kraeve bevis, ikke fravaer af modbevis.
priv_na <- fixture_rows(); priv_na$privat[[3]] <- NA
expect_error(build_c0_followup_selection_1939_v50(
  priv_na, "postgres", "764273", "test"), "C0F_SELECTION_PRIVAT")

## 5) Uden narrativ er der intet at erstatte.
mangler <- fixture_rows(); mangler$narrative_id[[2]] <- NA
expect_error(build_c0_followup_selection_1939_v50(
  mangler, "postgres", "764273", "test"), "C0F_SELECTION_NARRATIVE_MISSING")

## 6) old_sha256 er replay-vaernets anker; en malformet hash goer det tandloest.
daarlig <- fixture_rows(); daarlig$old_sha256[[4]] <- "kort"
expect_error(build_c0_followup_selection_1939_v50(
  daarlig, "postgres", "764273", "test"), "C0F_SELECTION_SHA_INVALID")

## 7) En manglende kolonne maa ikke ligne "ingen problemer": any(logical(0))
##    er FALSE, saa en fail-closed gate ville vaere tavs.
for (kolonne in c("privat", "side", "old_sha256", "narrative_id")) {
  uden <- fixture_rows(); uden[[kolonne]] <- NULL
  expect_error(build_c0_followup_selection_1939_v50(
    uden, "postgres", "764273", "test"), "C0F_SELECTION_KOLONNE_MANGLER")
}

cat(sprintf("OK: %d assertions\n", ok))
```

Create `tests/testthat/test-export-c0-followup-selection-1939-v50.R`:

```r
testthat::test_that("export-c0-followup-selection R contract passes direct assertions", {
  root <- normalizePath(file.path(getwd(), "..", ".."))
  old <- getwd()
  on.exit(setwd(old), add = TRUE)
  setwd(file.path(root, ".claude", "skills", "daa-extract", "scripts"))
  testthat::expect_no_error(source("test_export_c0_followup_selection_1939_v50.R", local = TRUE))
})
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
cd .claude/skills/daa-extract/scripts && Rscript test_export_c0_followup_selection_1939_v50.R
```
Expected: FAIL — `cannot open file 'export_c0_followup_selection_1939_v50_helpers.R'`

- [ ] **Step 3: Write the helpers**

Create `.claude/skills/daa-extract/scripts/export_c0_followup_selection_1939_v50_helpers.R`:

```r
## Ren transformation: DB-raekker -> eksportdokument for C0's efterkoersel.
## Ingen DB-adgang, saa den kan testes uden forbindelse (samme moenster som
## export_d2_spouse_selection_1939_v50_helpers.R).

## De ni koblinger. Person 1017 er BEVIDST udeladt: dens kobling ville slette
## 149 tegn, hvoraf de foerste ~92 ikke findes noget andet sted -- person 1021
## er halen af dens afsnit B). Sagen er en C3-sammenlaegning.
C0F_PERSON_IDS <- c(963, 967, 978, 991, 992, 1296, 1297, 1298, 1299)

C0F_SHA_RE <- "^[0-9a-f]{64}$"

## En fail-closed gate der spoerger "er nogen af dem private?" svarer FALSE,
## naar kolonnen slet ikke findes: any(logical(0)) er FALSE. Fravaer af data
## ville altsaa ligne fravaer af problem. Derfor kraeves felterne foerst.
c0f_kraev_kolonner <- function(df, navne) {
  mangler <- setdiff(navne, names(df))
  if (length(mangler) > 0L)
    stop(paste0("C0F_SELECTION_KOLONNE_MANGLER:", paste(mangler, collapse = ",")),
         call. = FALSE)
}

## Spaerrer ved TRUE OG ved NA: publicering skal kraeve bevis, ikke fravaer af
## modbevis. any(c(NA)) er NA og ville faa `if` til at fejle uklart.
c0f_spaerrer <- function(x) any(is.na(x) | as.logical(x))

build_c0_followup_selection_1939_v50 <- function(rows, database_name,
                                                 database_identity, generator) {
  c0f_kraev_kolonner(rows, c("person_id", "narrative_id", "old_sha256",
                             "privat", "side"))
  if (!identical(as.numeric(nrow(rows)), as.numeric(length(C0F_PERSON_IDS))))
    stop("C0F_SELECTION_COUNT_INVALID", call. = FALSE)
  if (!identical(sort(as.numeric(rows$person_id)), sort(C0F_PERSON_IDS)))
    stop("C0F_SELECTION_IDS_INVALID", call. = FALSE)
  if (c0f_spaerrer(rows$privat)) stop("C0F_SELECTION_PRIVAT", call. = FALSE)
  if (any(is.na(rows$narrative_id)))
    stop("C0F_SELECTION_NARRATIVE_MISSING", call. = FALSE)
  if (!all(grepl(C0F_SHA_RE, as.character(rows$old_sha256))))
    stop("C0F_SELECTION_SHA_INVALID", call. = FALSE)

  selected <- lapply(order(rows$person_id), function(i) list(
    person_id    = as.numeric(rows$person_id[[i]]),
    narrative_id = as.numeric(rows$narrative_id[[i]]),
    old_sha256   = as.character(rows$old_sha256[[i]]),
    privat       = as.logical(rows$privat[[i]]),
    side         = if (is.na(rows$side[[i]])) NA else as.character(rows$side[[i]])
  ))
  list(schema_version = "1.0", database_name = database_name,
       database_identity = database_identity, generator = generator,
       selected = selected)
}
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
cd .claude/skills/daa-extract/scripts && Rscript test_export_c0_followup_selection_1939_v50.R
```
Expected: `OK: 15 assertions`

- [ ] **Step 5: Write the CLI wrapper**

Create `.claude/skills/daa-extract/scripts/export_c0_followup_selection_1939_v50.R`:

```r
#!/usr/bin/env Rscript
## CLI: Rscript export_c0_followup_selection_1939_v50.R --output PATH
##   [--expect-database-name NAME]
##
## READ-ONLY. Henter de ni koblingspersoners nuvaerende 1939-narrativ:
## id, tekst-hash, privat-flag og side. Skriver aldrig; kalder ingen RPC.
args <- commandArgs(trailingOnly = TRUE)
allowed <- c("--output", "--expect-database-name")
flags <- args[grepl("^--", args)]
if (any(!flags %in% allowed) || anyDuplicated(flags))
  stop("C0F_EXPORT_CLI_INVALID", call. = FALSE)
if (!("--output" %in% flags)) stop("C0F_EXPORT_CLI_INVALID", call. = FALSE)
value <- function(flag) {
  index <- match(flag, args)
  if (is.na(index) || index == length(args) || grepl("^--", args[[index + 1L]]))
    stop("C0F_EXPORT_CLI_INVALID", call. = FALSE)
  args[[index + 1L]]
}
output <- value("--output")
if (file.exists(output)) stop("C0F_EXPORT_OUTPUT_EXISTS", call. = FALSE)
expect_database_name <- if ("--expect-database-name" %in% flags)
  value("--expect-database-name") else NA_character_

script_arg <- grep("^--file=", commandArgs(), value = TRUE)[1L]
script_dir <- dirname(normalizePath(sub("^--file=", "", script_arg)))
source(file.path(script_dir, "export_c0_followup_selection_1939_v50_helpers.R"))

env_or <- function(primary, fallback) {
  result <- Sys.getenv(primary)
  if (nzchar(result)) result else Sys.getenv(fallback)
}
con <- DBI::dbConnect(RPostgres::Postgres(),
  dbname = env_or("PGDATABASE", "SUPABASE_DB"), host = env_or("PGHOST", "SUPABASE_HOST"),
  port = as.integer(env_or("PGPORT", "SUPABASE_PORT")), user = env_or("PGUSER", "SUPABASE_USER"),
  password = env_or("PGPASSWORD", "SUPABASE_PASSWORD"),
  sslmode = if (nzchar(Sys.getenv("PGDATABASE"))) "disable"
            else if (nzchar(Sys.getenv("SUPABASE_SSLMODE"))) Sys.getenv("SUPABASE_SSLMODE")
            else "require",
  bigint = "integer")
on.exit(DBI::dbDisconnect(con), add = TRUE)

identity <- DBI::dbGetQuery(con,
  "SELECT current_database() AS database_name,
          (pg_control_system()).system_identifier::text AS database_identity")
database_name <- identity$database_name[[1L]]
if (!is.na(expect_database_name) && !identical(database_name, expect_database_name))
  stop(paste0("C0F_EXPORT_DATABASE_MISMATCH:observed=", database_name,
              ":expected=", expect_database_name), call. = FALSE)

## extensions.digest: skema-kvalificeret, som fase B laerte (search_path
## gaelder ikke i alle kontekster).
rows <- DBI::dbGetQuery(con, "
  SELECT n.subjekt_id AS person_id, n.id AS narrative_id,
         encode(extensions.digest(convert_to(n.tekst,'UTF8'),'sha256'),'hex') AS old_sha256,
         n.privat, n.side
    FROM narrative n
   WHERE n.subjekt_type='person' AND n.source_id=3
     AND n.subjekt_id = ANY('{963,967,978,991,992,1296,1297,1298,1299}'::bigint[])
   ORDER BY n.subjekt_id")

doc <- build_c0_followup_selection_1939_v50(
  rows, database_name, identity$database_identity[[1L]],
  "export_c0_followup_selection_1939_v50.R")

writeLines(jsonlite::toJSON(doc, auto_unbox = TRUE, pretty = TRUE, null = "null"), output)
cat(sprintf("valgte=%d privat=%d\n", length(doc$selected),
            sum(vapply(doc$selected, function(r) isTRUE(r$privat), logical(1)))))
```

- [ ] **Step 6: Run the full R suite**

Run: `Rscript run-tests.R`
Expected: alle tests grønne, inkl. `test-export-c0-followup-selection-1939-v50.R`

- [ ] **Step 7: Commit**

```bash
git add .claude/skills/daa-extract/scripts/export_c0_followup_selection_1939_v50*.R \
        .claude/skills/daa-extract/scripts/test_export_c0_followup_selection_1939_v50.R \
        tests/testthat/test-export-c0-followup-selection-1939-v50.R
git commit -m "feat(1939): read-only eksport af C0-efterkørslens ni personer"
```

---

### Task 2: Normalisering og flag-udtræk

**Files:**
- Create: `.claude/skills/daa-extract/scripts/build_c0_followup_flags_1939_v50.py`
- Create: `.claude/skills/daa-extract/scripts/test_build_c0_followup_flags_1939_v50.py`

**Interfaces:**
- Consumes: Task 1's JSON (`selected[].person_id`, `.narrative_id`, `.old_sha256`, `.side`) og `work/task26-1939-v50-c0-record-linkage/linkage-candidates-v1.json`.
- Produces: `build_flags_document(selection, candidates, record_by_person)` → `dict` med `schema_version`, `input_hashes`, `operations` (hver med `person_id`, `narrative_id`, `old_sha256`, `source_record_key`, `page_from`, `default_text`, `flags`), `flag_counts`. Task 3 og 4 læser den.

- [ ] **Step 1: Write the failing test**

Create `.claude/skills/daa-extract/scripts/test_build_c0_followup_flags_1939_v50.py`:

```python
"""DB-frie tests for build_c0_followup_flags_1939_v50.py."""
import importlib.util
import pathlib
import pytest

_DIR = pathlib.Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location(
    "c0f_flags", _DIR / "build_c0_followup_flags_1939_v50.py")
mod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(mod)

SHA = "a" * 64
IDS = [963, 967, 978, 991, 992, 1296, 1297, 1298, 1299]


def _selection(**kw):
    sel = [{"person_id": p, "narrative_id": 600 + i, "old_sha256": SHA,
            "privat": False, "side": "508"} for i, p in enumerate(IDS)]
    doc = {"schema_version": "1.0", "selected": sel}
    doc.update(kw)
    return doc


def _record_by_person():
    return {p: "record-%032x" % p for p in IDS}


def _candidates(text="Ditlev til Wittenberg.\n"):
    return {"records": [{"new_record_key": "record-%032x" % p,
                         "verbatim_text": text,
                         "pages": {"page_from": 508, "page_to": 508}}
                        for p in IDS]}


def test_happy_path_produces_nine_operations():
    doc = mod.build_flags_document(_selection(), _candidates(), _record_by_person())
    assert len(doc["operations"]) == 9
    assert [op["person_id"] for op in doc["operations"]] == IDS
    assert doc["schema_version"] == "1939-v50-c0-followup-flags-v1"


def test_default_text_is_normalized_not_raw():
    """Rå OCR må ALDRIG nå manifestet: alle ni records har enlige linjeskift,
    og 1299 bærer '### PAGE'. Uden normalisering ville fasen indføre rå tekst
    i en bestand af 551 rensede narrativer."""
    doc = mod.build_flags_document(
        _selection(), _candidates("Revent-\nlow til Gaarz.\n\n### PAGE 0063 ###\n"),
        _record_by_person())
    for op in doc["operations"]:
        assert "### PAGE" not in op["default_text"]
        assert "-\n" not in op["default_text"]
        assert not op["default_text"].endswith(("\n", " "))


def test_side_mismatch_is_terminal():
    """narrative.side vs recordens page_from er en IDENTITETSKONTROL: den
    beviser at vi rammer den rigtige post. Målt 2026-08-21: 9/9 match."""
    sel = _selection()
    sel["selected"][0]["side"] = "999"
    with pytest.raises(SystemExit, match="C0F_FLAGS_SIDE_MISMATCH"):
        mod.build_flags_document(sel, _candidates(), _record_by_person())


def test_side_null_is_terminal():
    sel = _selection()
    sel["selected"][0]["side"] = None
    with pytest.raises(SystemExit, match="C0F_FLAGS_SIDE_MISSING"):
        mod.build_flags_document(sel, _candidates(), _record_by_person())


def test_missing_record_is_terminal():
    rbp = _record_by_person()
    del rbp[963]
    with pytest.raises(SystemExit, match="C0F_FLAGS_RECORD_MISSING"):
        mod.build_flags_document(_selection(), _candidates(), rbp)


def test_person_1017_is_rejected():
    """1017 er flyttet til C3: dens kobling ville slette ~92 tegn permanent."""
    sel = _selection()
    sel["selected"][0]["person_id"] = 1017
    with pytest.raises(SystemExit, match="C0F_FLAGS_IDS_INVALID"):
        mod.build_flags_document(sel, _candidates(), _record_by_person())


def test_empty_normalized_text_is_terminal():
    with pytest.raises(SystemExit, match="C0F_FLAGS_TEXT_EMPTY"):
        mod.build_flags_document(_selection(), _candidates("   \n  "),
                                 _record_by_person())


def test_flag_ids_are_unique_and_sorted():
    doc = mod.build_flags_document(
        _selection(), _candidates("Revent-\nlow og Futter-\nkamp.\n"),
        _record_by_person())
    ids = [f["flag_id"] for op in doc["operations"] for f in op["flags"]]
    assert len(ids) == len(set(ids))
    assert ids == sorted(ids)
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
cd .claude/skills/daa-extract/scripts && python3 -m pytest test_build_c0_followup_flags_1939_v50.py -q
```
Expected: FAIL — `No such file or directory: build_c0_followup_flags_1939_v50.py`

- [ ] **Step 3: Write the implementation**

Create `.claude/skills/daa-extract/scripts/build_c0_followup_flags_1939_v50.py`:

```python
#!/usr/bin/env python3
"""Normalisering og flag-udtræk for C0's efterkørsel.

C0's ``verbatim_text`` er RÅ OCR. Målt 2026-08-21 fejler alle ni records fase
B's slutinvarianter: alle har enlige linjeskift, syv har uopløste orddelinger,
1299 bærer ``### PAGE 0063 ###`` og 1297 trailing whitespace. Uden
normalisering ville fasen indføre rå tekst i en bestand af 551 rensede.

Reglerne genimplementeres ALDRIG: ``normalize_narrative_1939_v50`` importeres
som den ene kanoniske transform, præcis som fase B gjorde.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import pathlib
import sys
from typing import Any, Dict, List

_SCRIPTS_DIR = pathlib.Path(__file__).resolve().parent

# De ni koblinger. 1017 er BEVIDST udeladt -- se spec'ens afsnit "Hvorfor 1017
# ikke er med": dens kobling ville slette ~92 tegn permanent.
PERSON_IDS = [963, 967, 978, 991, 992, 1296, 1297, 1298, 1299]

CONTEXT_RADIUS = 60


def _fail(code: str) -> None:
    raise SystemExit(code)


def _import_normalize():
    spec = importlib.util.spec_from_file_location(
        "normalize_narrative_1939_v50",
        _SCRIPTS_DIR / "normalize_narrative_1939_v50.py")
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


_normalize_mod = _import_normalize()
normalize_narrative_v1 = _normalize_mod.normalize_narrative_v1
_LONE_NEWLINE_RE = _normalize_mod._LONE_NEWLINE_RE


def assert_invariants(text: str, context: str) -> None:
    """Fase B's slutinvarianter, genhaevdet efter normalisering."""
    if "### PAGE" in text:
        _fail("C0F_FLAGS_INVARIANT_PAGE_MARKER:" + context)
    if _LONE_NEWLINE_RE.search(text):
        _fail("C0F_FLAGS_INVARIANT_LONE_NEWLINE:" + context)
    if text != text.rstrip():
        _fail("C0F_FLAGS_INVARIANT_TRAILING_WS:" + context)
    if not text.strip():
        _fail("C0F_FLAGS_TEXT_EMPTY:" + context)


def build_flags_document(selection: Dict[str, Any], candidates: Dict[str, Any],
                         record_by_person: Dict[int, str]) -> Dict[str, Any]:
    selected = selection.get("selected") or []
    ids = sorted(int(row["person_id"]) for row in selected)
    if ids != sorted(PERSON_IDS):
        _fail("C0F_FLAGS_IDS_INVALID")

    recs = {r["new_record_key"]: r for r in candidates.get("records", [])}
    # Korpus = ALLE records' rå tekst. normalize_narrative_v1 bruger det til at
    # bevise sammentrækninger; et smallere korpus ville gøre flere orddelinger
    # "unproven" og dermed flytte maskinelle afgørelser over på mennesket.
    corpus = "\n".join(r["verbatim_text"] for r in candidates.get("records", []))

    by_person = {int(row["person_id"]): row for row in selected}
    operations: List[Dict[str, Any]] = []
    flag_counts: Dict[str, int] = {}
    seen_flag_ids = set()

    for pid in sorted(PERSON_IDS):
        row = by_person[pid]
        key = record_by_person.get(pid)
        if key is None or key not in recs:
            _fail("C0F_FLAGS_RECORD_MISSING:%d" % pid)
        record = recs[key]

        # Identitetskontrol: beviser at vi rammer den rigtige post. Vi SKRIVER
        # ikke side (p_side=NULL), men en afvigelse betyder at recorden og
        # narrativet ikke er samme trykte post.
        side = row.get("side")
        if side is None:
            _fail("C0F_FLAGS_SIDE_MISSING:%d" % pid)
        page_from = int(record["pages"]["page_from"])
        if str(side).strip() != str(page_from):
            _fail("C0F_FLAGS_SIDE_MISMATCH:%d:observed=%s:expected=%d"
                  % (pid, side, page_from))

        raw = record["verbatim_text"]
        result = normalize_narrative_v1(raw, corpus)
        default_text = result["text"]
        assert_invariants(default_text, "person=%d" % pid)

        flags = []
        for flag in result["flags"]:
            flag_id = "%s:%d:%s" % (key, flag["char_offset"], flag["kind"])
            if flag_id in seen_flag_ids:
                _fail("C0F_FLAGS_ID_COLLISION:" + flag_id)
            seen_flag_ids.add(flag_id)
            off = flag["char_offset"]
            lo, hi = max(0, off - CONTEXT_RADIUS), min(len(raw), off + CONTEXT_RADIUS)
            flags.append({
                "flag_id": flag_id, "kind": flag["kind"],
                "char_offset": off, "context": raw[lo:hi],
                "person_id": pid, "source_record_key": key,
            })
            flag_counts[flag["kind"]] = flag_counts.get(flag["kind"], 0) + 1
        flags.sort(key=lambda f: f["flag_id"])

        operations.append({
            "person_id": pid,
            "narrative_id": int(row["narrative_id"]),
            "old_sha256": row["old_sha256"],
            "source_record_key": key,
            "page_from": page_from,
            "default_text": default_text,
            "flags": flags,
        })

    return {
        "schema_version": "1939-v50-c0-followup-flags-v1",
        "generator": "build_c0_followup_flags_1939_v50.py",
        "operations": operations,
        "flag_counts": flag_counts,
    }


def _sha256_file(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--selection", required=True)
    parser.add_argument("--candidates", required=True)
    parser.add_argument("--decisions", required=True,
                        help="C0's afgoerelsesfil (c0-afgoerelser.json)")
    parser.add_argument("--output", required=True)
    args = parser.parse_args(argv)

    out = pathlib.Path(args.output)
    if out.exists():
        _fail("C0F_FLAGS_OUTPUT_EXISTS")

    sel_path = pathlib.Path(args.selection)
    cand_path = pathlib.Path(args.candidates)
    dec_path = pathlib.Path(args.decisions)
    selection = json.loads(sel_path.read_text(encoding="utf-8"))
    candidates = json.loads(cand_path.read_text(encoding="utf-8"))
    decisions = json.loads(dec_path.read_text(encoding="utf-8"))

    # record_by_person udledes af C0's EGNE afgoerelser -- aldrig af navne
    # eller af raekkefoelge. Kun [KOBL] med en person_id blandt de ni.
    record_by_person = {}
    for row in decisions.get("decisions", []):
        if row.get("token") != "[KOBL]":
            continue
        pid = row.get("person_id")
        if pid in PERSON_IDS:
            record_by_person[int(pid)] = row["new_record_key"]

    doc = build_flags_document(selection, candidates, record_by_person)
    doc["input_hashes"] = {
        "selection_sha256": _sha256_file(sel_path),
        "candidates_sha256": _sha256_file(cand_path),
        "decisions_sha256": _sha256_file(dec_path),
    }
    out.write_text(json.dumps(doc, ensure_ascii=False, indent=2, sort_keys=True),
                   encoding="utf-8")
    total = sum(doc["flag_counts"].values())
    print("operationer=%d flag=%d %s" % (len(doc["operations"]), total, doc["flag_counts"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
cd .claude/skills/daa-extract/scripts && python3 -m pytest test_build_c0_followup_flags_1939_v50.py -q
```
Expected: `8 passed`

- [ ] **Step 5: Verify determinism under three hash seeds**

Run:
```bash
cd .claude/skills/daa-extract/scripts
for seed in 0 1 42; do
  PYTHONHASHSEED=$seed python3 -m pytest test_build_c0_followup_flags_1939_v50.py -q | tail -1
done
```
Expected: `8 passed` alle tre gange. Samme krav som C0 selv stillede.

- [ ] **Step 6: Commit**

```bash
git add .claude/skills/daa-extract/scripts/build_c0_followup_flags_1939_v50.py \
        .claude/skills/daa-extract/scripts/test_build_c0_followup_flags_1939_v50.py
git commit -m "feat(1939): normalisering og flag-udtræk til C0-efterkørslen"
```

---

### Task 3: Menneskeark og fail-closed konverter

**Files:**
- Create: `.claude/skills/daa-extract/scripts/build_c0_followup_review_1939_v50.py`
- Create: `.claude/skills/daa-extract/scripts/convert_c0_followup_decisions_1939_v50.py`
- Create: `.claude/skills/daa-extract/scripts/test_c0_followup_review_1939_v50.py`

**Interfaces:**
- Consumes: Task 2's flag-dokument.
- Produces: `render_review(flags_doc)` → `str` (arket) og `parse_review(text, flags_doc)` → `dict` med `decisions` (`{flag_id: "merge"|"keep"}`) og `accepted_person_ids` (`list[int]`). Task 4 læser konverterens JSON.

- [ ] **Step 1: Write the failing test**

Create `.claude/skills/daa-extract/scripts/test_c0_followup_review_1939_v50.py`:

```python
"""DB-frie tests for menneskearket og dets fail-closed konverter."""
import importlib.util
import pathlib
import pytest

_DIR = pathlib.Path(__file__).resolve().parent


def _load(name):
    spec = importlib.util.spec_from_file_location(name, _DIR / (name + ".py"))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


build = _load("build_c0_followup_review_1939_v50")
conv = _load("convert_c0_followup_decisions_1939_v50")


def _flags_doc():
    return {
        "schema_version": "1939-v50-c0-followup-flags-v1",
        "operations": [
            {"person_id": 991, "narrative_id": 660, "old_sha256": "a" * 64,
             "source_record_key": "record-x", "page_from": 504,
             "default_text": "Hr. Iven til Rixdorf.", "flags": []},
            {"person_id": 992, "narrative_id": 661, "old_sha256": "b" * 64,
             "source_record_key": "record-y", "page_from": 504,
             "default_text": "Reventlow til Gaarz.", "flags": [
                 {"flag_id": "record-y:12:hyphen_unproven",
                  "kind": "hyphen_unproven", "char_offset": 12,
                  "context": "Revent-\nlow til", "person_id": 992,
                  "source_record_key": "record-y"}]},
        ],
        "flag_counts": {"hyphen_unproven": 1},
    }


def test_sheet_prefills_the_recommended_action():
    """Anbefalingerne er UDFYLDT: står en linje urørt, er den enig."""
    text = build.render_review(_flags_doc())
    assert "[MERGE]" in text
    assert "record-y:12:hyphen_unproven" in text


def test_sheet_lists_person_without_flags_as_auto():
    """991 har ingen flag — dens tekst er allerede korrekt. Den skal fremgå,
    så mennesket ser HELE mængden, ikke kun det der kræver valg."""
    text = build.render_review(_flags_doc())
    assert "991" in text


def test_roundtrip_unchanged_sheet_yields_defaults():
    doc = _flags_doc()
    out = conv.parse_review(build.render_review(doc), doc)
    assert out["decisions"] == {"record-y:12:hyphen_unproven": "merge"}
    assert out["accepted_person_ids"] == [991, 992]


def test_keep_is_honoured():
    doc = _flags_doc()
    text = build.render_review(doc).replace("[MERGE]", "[KEEP]", 1)
    assert conv.parse_review(text, doc)["decisions"] == {
        "record-y:12:hyphen_unproven": "keep"}


def test_afvis_removes_the_person_but_keeps_the_others():
    """Delvis accept: afvises én, kører de øvrige. Alt-eller-intet ville
    presse mod at acceptere noget tvivlsomt for at få resten igennem."""
    doc = _flags_doc()
    text = build.render_review(doc).replace("[ACCEPT] 991", "[AFVIS]  991", 1)
    out = conv.parse_review(text, doc)
    assert out["accepted_person_ids"] == [992]


def test_unknown_token_is_terminal():
    doc = _flags_doc()
    text = build.render_review(doc).replace("[MERGE]", "[MAASKE]", 1)
    with pytest.raises(SystemExit, match="C0F_REVIEW_TOKEN_INVALID"):
        conv.parse_review(text, doc)


def test_edited_context_is_terminal():
    """Byte-låst kontekst: alt andet end tokenet verificeres. Ellers kunne en
    utilsigtet redigering flytte et valg til et andet sted i teksten."""
    doc = _flags_doc()
    text = build.render_review(doc).replace("Revent-", "Rvent-", 1)
    with pytest.raises(SystemExit, match="C0F_REVIEW_LINE_TAMPERED"):
        conv.parse_review(text, doc)


def test_missing_line_is_terminal():
    doc = _flags_doc()
    text = "\n".join(l for l in build.render_review(doc).splitlines()
                     if "record-y:12" not in l)
    with pytest.raises(SystemExit, match="C0F_REVIEW_FLAG_MISSING"):
        conv.parse_review(text, doc)


def test_all_rejected_is_terminal():
    """En tom mængde er ikke en gyldig kørsel — samme regel som D2_APPLY_EMPTY."""
    doc = _flags_doc()
    text = build.render_review(doc).replace("[ACCEPT]", "[AFVIS] ")
    with pytest.raises(SystemExit, match="C0F_REVIEW_EMPTY"):
        conv.parse_review(text, doc)
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
cd .claude/skills/daa-extract/scripts && python3 -m pytest test_c0_followup_review_1939_v50.py -q
```
Expected: FAIL — `No such file or directory: build_c0_followup_review_1939_v50.py`

- [ ] **Step 3: Write the sheet generator**

Create `.claude/skills/daa-extract/scripts/build_c0_followup_review_1939_v50.py`:

```python
#!/usr/bin/env python3
"""Menneskeark for C0's efterkørsel — token pr. linje, byte-låst kontekst.

Følger husets grænseflade-mønster: ret KUN tokenet i den firkantede parentes;
alt andet på linjen verificeres byte-for-byte ved indlæsning. Anbefalingerne
er udfyldt på forhånd, så en urørt linje betyder "enig".

Målt 2026-08-21 er der otte flag i alt, alle ``hyphen_unproven``, fordelt på
fire personer. Fase B havde 178 til sammenligning.
"""
from __future__ import annotations

import argparse
import json
import pathlib
import sys
from typing import Any, Dict

DEFAULT_ACTION = {"hyphen_unproven": "merge"}
TOKEN_BY_ACTION = {"merge": "[MERGE]", "keep": "[KEEP] "}

HEADER = """\
# DAA 1939 — C0's efterkørsel: ni record-koblinger
#
# Ret KUN tokenet i den firkantede parentes forrest på hver linje.
# Alt andet på linjen er låst og verificeres byte-for-byte ved indlæsning.
#
# PERSON-linjer — skal koblingen udføres?
#   [ACCEPT] erstat personens narrativ og opret bindingen
#   [AFVIS]  spring denne person over (de øvrige kører alligevel)
#
# ORDDELING-linjer — er de to stumper ét ord?
#   [MERGE]  Revent- + low  ->  Reventlow
#   [KEEP]   bevar bindestregen (ægte kompositum)
#
# Anbefalingerne er UDFYLDT. Lad en linje stå, hvis du er enig.
# Intet skrives til databasen her — det sker i en særskilt runde, du godkender.
"""


def render_review(flags_doc: Dict[str, Any]) -> str:
    lines = [HEADER]
    for op in flags_doc["operations"]:
        pid = op["person_id"]
        n_flag = len(op["flags"])
        lines.append("")
        lines.append("== PERSON %d — s.%d — %d tegn — %s ==" % (
            pid, op["page_from"], len(op["default_text"]),
            "%d orddeling(er) at afgøre" % n_flag if n_flag else "ingen valg; teksten er allerede korrekt"))
        lines.append("[ACCEPT] %d  %s" % (pid, op["source_record_key"]))
        for flag in op["flags"]:
            if flag["kind"] not in DEFAULT_ACTION:
                # Maalingen 2026-08-21 gav kun hyphen_unproven, men det er en
                # egenskab ved DATA, ikke ved koden. En ny flagtype skal give
                # en laesbar fejl, ikke en KeyError midt i en render.
                raise SystemExit("C0F_REVIEW_FLAG_KIND_UNKNOWN:" + flag["kind"])
            token = TOKEN_BY_ACTION[DEFAULT_ACTION[flag["kind"]]]
            lines.append("%s %s  |  %s" % (
                token, flag["flag_id"], flag["context"].replace("\n", "\\n")))
    return "\n".join(lines) + "\n"


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--flags", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args(argv)
    out = pathlib.Path(args.output)
    if out.exists():
        raise SystemExit("C0F_REVIEW_OUTPUT_EXISTS")
    doc = json.loads(pathlib.Path(args.flags).read_text(encoding="utf-8"))
    out.write_text(render_review(doc), encoding="utf-8")
    total = sum(len(op["flags"]) for op in doc["operations"])
    print("personer=%d orddelingsvalg=%d" % (len(doc["operations"]), total))
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 4: Write the fail-closed converter**

Create `.claude/skills/daa-extract/scripts/convert_c0_followup_decisions_1939_v50.py`:

```python
#!/usr/bin/env python3
"""Fail-closed konverter: menneskeark -> beslutnings-JSON.

Alt andet end tokenet er byte-låst. En redigeret kontekst er terminal, ikke
noget der forsøges tolket: ellers kunne en utilsigtet ændring flytte et valg
til et andet sted i teksten uden at nogen opdagede det.
"""
from __future__ import annotations

import argparse
import json
import pathlib
import sys
from typing import Any, Dict

ACTION_BY_TOKEN = {"[MERGE]": "merge", "[KEEP]": "keep"}
PERSON_TOKENS = {"[ACCEPT]": True, "[AFVIS]": False}


def _fail(code: str) -> None:
    raise SystemExit(code)


def parse_review(text: str, flags_doc: Dict[str, Any]) -> Dict[str, Any]:
    forventet_flag = {}
    forventet_person = {}
    for op in flags_doc["operations"]:
        forventet_person[op["person_id"]] = "%d  %s" % (
            op["person_id"], op["source_record_key"])
        for flag in op["flags"]:
            forventet_flag[flag["flag_id"]] = "%s  |  %s" % (
                flag["flag_id"], flag["context"].replace("\n", "\\n"))

    decisions: Dict[str, str] = {}
    accepted = []
    set_person = set()
    for number, line in enumerate(text.splitlines(), start=1):
        if not line.strip() or line.lstrip().startswith("#") or line.startswith("=="):
            continue
        token, _, hale = line.partition(" ")
        hale = hale.strip()
        if token in PERSON_TOKENS:
            pid = int(hale.split()[0])
            if pid not in forventet_person:
                _fail("C0F_REVIEW_PERSON_UNKNOWN:line=%d" % number)
            if hale != forventet_person[pid]:
                _fail("C0F_REVIEW_LINE_TAMPERED:line=%d" % number)
            if pid in set_person:
                _fail("C0F_REVIEW_PERSON_DUPLICATE:line=%d" % number)
            set_person.add(pid)
            if PERSON_TOKENS[token]:
                accepted.append(pid)
        elif token in ACTION_BY_TOKEN:
            flag_id = hale.split("  |  ")[0]
            if flag_id not in forventet_flag:
                _fail("C0F_REVIEW_FLAG_UNKNOWN:line=%d" % number)
            if hale != forventet_flag[flag_id]:
                _fail("C0F_REVIEW_LINE_TAMPERED:line=%d" % number)
            if flag_id in decisions:
                _fail("C0F_REVIEW_FLAG_DUPLICATE:line=%d" % number)
            decisions[flag_id] = ACTION_BY_TOKEN[token]
        else:
            _fail("C0F_REVIEW_TOKEN_INVALID:line=%d:token=%s" % (number, token))

    if set(forventet_person) - set_person:
        _fail("C0F_REVIEW_PERSON_MISSING:" + ",".join(
            str(p) for p in sorted(set(forventet_person) - set_person)))
    if set(forventet_flag) - set(decisions):
        _fail("C0F_REVIEW_FLAG_MISSING:" + ",".join(
            sorted(set(forventet_flag) - set(decisions))))
    if not accepted:
        _fail("C0F_REVIEW_EMPTY")
    return {"decisions": decisions, "accepted_person_ids": sorted(accepted)}


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--review", required=True)
    parser.add_argument("--flags", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args(argv)
    out = pathlib.Path(args.output)
    if out.exists():
        _fail("C0F_DECISIONS_OUTPUT_EXISTS")
    flags_doc = json.loads(pathlib.Path(args.flags).read_text(encoding="utf-8"))
    result = parse_review(
        pathlib.Path(args.review).read_text(encoding="utf-8"), flags_doc)
    result["schema_version"] = "1939-v50-c0-followup-decisions-v1"
    out.write_text(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True),
                   encoding="utf-8")
    print("accepteret=%d afgjorte_orddelinger=%d" % (
        len(result["accepted_person_ids"]), len(result["decisions"])))
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 5: Run test to verify it passes**

Run:
```bash
cd .claude/skills/daa-extract/scripts && python3 -m pytest test_c0_followup_review_1939_v50.py -q
```
Expected: `9 passed`

- [ ] **Step 6: Commit**

```bash
git add .claude/skills/daa-extract/scripts/build_c0_followup_review_1939_v50.py \
        .claude/skills/daa-extract/scripts/convert_c0_followup_decisions_1939_v50.py \
        .claude/skills/daa-extract/scripts/test_c0_followup_review_1939_v50.py
git commit -m "feat(1939): menneskeark og fail-closed konverter til C0-efterkørslen"
```

---

### Task 4: Hash-låst manifest

**Files:**
- Create: `.claude/skills/daa-extract/scripts/build_c0_followup_manifest_1939_v50.py`
- Create: `.claude/skills/daa-extract/scripts/test_build_c0_followup_manifest_1939_v50.py`

**Interfaces:**
- Consumes: Task 2's flag-dokument og Task 3's beslutnings-JSON, samt `linkage-candidates-v1.json` (rå tekst til splice).
- Produces: `build_manifest(flags_doc, decisions_doc, candidates)` → `dict` med `schema_version`, `operations` (hver med `person_id`, `narrative_id`, `expected_old_narrative_sha256`, `source_record_key`, `page_from`, `new_text`, `new_text_sha256`), `counts`. Task 5 læser den JSON.

- [ ] **Step 1: Write the failing test**

Create `.claude/skills/daa-extract/scripts/test_build_c0_followup_manifest_1939_v50.py`:

```python
"""DB-frie tests for manifest-byggeren."""
import hashlib
import importlib.util
import pathlib
import pytest

_DIR = pathlib.Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location(
    "c0f_manifest", _DIR / "build_c0_followup_manifest_1939_v50.py")
mod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(mod)

RAW = "Revent-\nlow til Gaarz.\n"


def _flags_doc():
    import importlib.util as iu
    spec = iu.spec_from_file_location(
        "c0f_flags", _DIR / "build_c0_followup_flags_1939_v50.py")
    flags_mod = iu.module_from_spec(spec)
    spec.loader.exec_module(flags_mod)
    default = flags_mod.normalize_narrative_v1(RAW, RAW)
    return {
        "schema_version": "1939-v50-c0-followup-flags-v1",
        "operations": [{
            "person_id": 992, "narrative_id": 661, "old_sha256": "b" * 64,
            "source_record_key": "record-y", "page_from": 504,
            "default_text": default["text"],
            "flags": [dict(f, flag_id="record-y:%d:%s" % (f["char_offset"], f["kind"]),
                           person_id=992, source_record_key="record-y")
                      for f in default["flags"]],
        }],
        "flag_counts": {"hyphen_unproven": len(default["flags"])},
    }


def _candidates():
    return {"records": [{"new_record_key": "record-y", "verbatim_text": RAW,
                         "pages": {"page_from": 504, "page_to": 504}}]}


def _decisions(doc, action="merge"):
    return {"decisions": {f["flag_id"]: action
                          for op in doc["operations"] for f in op["flags"]},
            "accepted_person_ids": [992]}


def test_default_decisions_reproduce_default_text():
    doc = _flags_doc()
    man = mod.build_manifest(doc, _decisions(doc), _candidates())
    assert man["operations"][0]["new_text"] == doc["operations"][0]["default_text"]


def test_keep_changes_the_text():
    doc = _flags_doc()
    if not doc["operations"][0]["flags"]:
        pytest.skip("fixturen gav ingen flag")
    man = mod.build_manifest(doc, _decisions(doc, "keep"), _candidates())
    assert man["operations"][0]["new_text"] != doc["operations"][0]["default_text"]


def test_rejected_person_is_excluded():
    doc = _flags_doc()
    dec = _decisions(doc)
    dec["accepted_person_ids"] = []
    with pytest.raises(SystemExit, match="C0F_MANIFEST_EMPTY"):
        mod.build_manifest(doc, dec, _candidates())


def test_missing_decision_is_terminal():
    doc = _flags_doc()
    if not doc["operations"][0]["flags"]:
        pytest.skip("fixturen gav ingen flag")
    dec = _decisions(doc)
    dec["decisions"] = {}
    with pytest.raises(SystemExit, match="C0F_MANIFEST_DECISION_MISSING"):
        mod.build_manifest(doc, dec, _candidates())


def test_new_text_sha256_matches_the_text():
    doc = _flags_doc()
    man = mod.build_manifest(doc, _decisions(doc), _candidates())
    op = man["operations"][0]
    assert op["new_text_sha256"] == hashlib.sha256(
        op["new_text"].encode("utf-8")).hexdigest()


def test_invariants_are_reasserted_after_splice():
    """Et splice kan i princippet genindføre et brud; invarianterne hævdes
    derfor igen på den FÆRDIGE tekst, ikke kun på default_text."""
    doc = _flags_doc()
    doc["operations"][0]["default_text"] += "\n### PAGE 0001 ###"
    with pytest.raises(SystemExit, match="C0F_MANIFEST_INVARIANT"):
        mod.build_manifest(doc, _decisions(doc), _candidates())
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
cd .claude/skills/daa-extract/scripts && python3 -m pytest test_build_c0_followup_manifest_1939_v50.py -q
```
Expected: FAIL — `No such file or directory: build_c0_followup_manifest_1939_v50.py`

- [ ] **Step 3: Write the implementation**

Create `.claude/skills/daa-extract/scripts/build_c0_followup_manifest_1939_v50.py`:

```python
#!/usr/bin/env python3
"""Manifest-bygger for C0's efterkørsel.

Beslutnings-anvendelsen er KOMPOSITION over ``normalize_narrative_v1``, aldrig
en anden kopi af dens regler: transformen er et strengt venstre-mod-højre-pas
uden lookahead ud over det flagede sted, så en afkortning af rå-teksten præcis
ved et flags ``char_offset`` og en genkørsel giver et EKSAKT præfiks af
standard-outputtet — og dermed splice-positionen via modulets eget API.
Mønsteret er verificeret mod alle 178 ægte flag i fase B.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import pathlib
import sys
from typing import Any, Dict, List, Tuple

_SCRIPTS_DIR = pathlib.Path(__file__).resolve().parent

DEFAULT_ACTION = {"hyphen_unproven": "merge"}
VALID_ACTIONS = {"hyphen_unproven": {"merge", "keep"}}


def _fail(code: str) -> None:
    raise SystemExit(code)


def _import(name: str):
    spec = importlib.util.spec_from_file_location(name, _SCRIPTS_DIR / (name + ".py"))
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


_flags_mod = _import("build_c0_followup_flags_1939_v50")
normalize_narrative_v1 = _flags_mod.normalize_narrative_v1


def _assert_invariants(text: str, context: str) -> None:
    if "### PAGE" in text:
        _fail("C0F_MANIFEST_INVARIANT_PAGE_MARKER:" + context)
    if _flags_mod._LONE_NEWLINE_RE.search(text):
        _fail("C0F_MANIFEST_INVARIANT_LONE_NEWLINE:" + context)
    if text != text.rstrip():
        _fail("C0F_MANIFEST_INVARIANT_TRAILING_WS:" + context)
    if not text.strip():
        _fail("C0F_MANIFEST_INVARIANT_EMPTY:" + context)


def _decided_text(raw: str, corpus: str, default_text: str,
                  op_flags: List[Dict[str, Any]], decisions: Dict[str, str]) -> str:
    edits: List[Tuple[int, int, str]] = []
    for flag in op_flags:
        kind = flag["kind"]
        flag_id = flag["flag_id"]
        if kind not in VALID_ACTIONS:
            _fail("C0F_MANIFEST_FLAG_KIND_UNKNOWN:" + flag_id)
        action = decisions.get(flag_id)
        if action is None:
            _fail("C0F_MANIFEST_DECISION_MISSING:" + flag_id)
        if action not in VALID_ACTIONS[kind]:
            _fail("C0F_MANIFEST_ACTION_INVALID:" + flag_id)
        if action == DEFAULT_ACTION[kind]:
            continue
        prefix_text = normalize_narrative_v1(raw[:flag["char_offset"]], corpus)["text"]
        prefix_len = len(prefix_text)
        # Ikke-tom kontrol selv naar default-spannet er 0 tegn: den bekraefter
        # at HELE praefikset flugter med standard-outputtet foer der splices,
        # saa en skredet prefix_len aldrig kan indsaette en "-" det forkerte sted.
        if default_text[:prefix_len] != prefix_text:
            _fail("C0F_MANIFEST_DECISION_PREFIX_MISMATCH:" + flag_id)
        # hyphen_unproven: standarden har allerede sammentrukket, 0 tegn beholdt.
        edits.append((prefix_len, prefix_len, "-"))
    edits.sort(key=lambda e: -e[0])
    text = default_text
    seen: List[Tuple[int, int]] = []
    for lo, hi, span in edits:
        if any(not (hi <= a or lo >= b) for a, b in seen):
            _fail("C0F_MANIFEST_DECISION_SPLICE_OVERLAP")
        seen.append((lo, hi))
        text = text[:lo] + span + text[hi:]
    return text


def build_manifest(flags_doc: Dict[str, Any], decisions_doc: Dict[str, Any],
                   candidates: Dict[str, Any]) -> Dict[str, Any]:
    accepted = set(int(p) for p in decisions_doc.get("accepted_person_ids", []))
    if not accepted:
        _fail("C0F_MANIFEST_EMPTY")
    decisions = decisions_doc.get("decisions") or {}
    recs = {r["new_record_key"]: r for r in candidates.get("records", [])}
    corpus = "\n".join(r["verbatim_text"] for r in candidates.get("records", []))

    operations = []
    for op in flags_doc["operations"]:
        pid = int(op["person_id"])
        if pid not in accepted:
            continue
        key = op["source_record_key"]
        if key not in recs:
            _fail("C0F_MANIFEST_RECORD_MISSING:%d" % pid)
        new_text = _decided_text(recs[key]["verbatim_text"], corpus,
                                 op["default_text"], op["flags"], decisions)
        # Invarianterne haevdes paa den FAERDIGE tekst: et splice kan i
        # princippet genindfoere et brud, som default_text ikke havde.
        _assert_invariants(new_text, "person=%d" % pid)
        operations.append({
            "person_id": pid,
            "narrative_id": int(op["narrative_id"]),
            "expected_old_narrative_sha256": op["old_sha256"],
            "source_record_key": key,
            "page_from": int(op["page_from"]),
            "new_text": new_text,
            "new_text_sha256": hashlib.sha256(new_text.encode("utf-8")).hexdigest(),
        })
    operations.sort(key=lambda o: o["person_id"])
    if not operations:
        _fail("C0F_MANIFEST_EMPTY")
    return {
        "schema_version": "1939-v50-c0-followup-manifest-v1",
        "generator": "build_c0_followup_manifest_1939_v50.py",
        "source": {"edition": "1939", "database_source_id": 3},
        "counts": {"operations": len(operations), "bindings_create": len(operations)},
        "operations": operations,
    }


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--flags", required=True)
    parser.add_argument("--decisions", required=True)
    parser.add_argument("--candidates", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args(argv)
    out = pathlib.Path(args.output)
    if out.exists():
        _fail("C0F_MANIFEST_OUTPUT_EXISTS")
    read = lambda p: json.loads(pathlib.Path(p).read_text(encoding="utf-8"))
    man = build_manifest(read(args.flags), read(args.decisions), read(args.candidates))
    out.write_text(json.dumps(man, ensure_ascii=False, indent=2, sort_keys=True),
                   encoding="utf-8")
    print("operationer=%d bindinger=%d" % (
        man["counts"]["operations"], man["counts"]["bindings_create"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
cd .claude/skills/daa-extract/scripts && python3 -m pytest test_build_c0_followup_manifest_1939_v50.py -q
```
Expected: `6 passed` (én kan blive `skipped`, hvis fixturens tekst ikke gav flag)

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/daa-extract/scripts/build_c0_followup_manifest_1939_v50.py \
        .claude/skills/daa-extract/scripts/test_build_c0_followup_manifest_1939_v50.py
git commit -m "feat(1939): hash-låst manifest til C0-efterkørslen"
```

---

### Task 5: Fail-closed apply-wrapper

**Files:**
- Create: `.claude/skills/daa-extract/scripts/apply_c0_followup_1939_v50_helpers.R`
- Create: `.claude/skills/daa-extract/scripts/apply_c0_followup_1939_v50.R`
- Create: `.claude/skills/daa-extract/scripts/test_apply_c0_followup_1939_v50.R`
- Create: `tests/testthat/test-apply-c0-followup-1939-v50.R`

**Interfaces:**
- Consumes: Task 4's manifest.
- Produces: `c0f_parse_apply_args(args)` → `list(manifest, expect_sha256, backup)`; `c0f_plan_apply(manifest, live)` → `list(operations, forventet_bindinger)`; `c0f_check_postcheck(before, after, forventet_bindinger)` → `TRUE`.

- [ ] **Step 1: Write the failing test**

Create `.claude/skills/daa-extract/scripts/test_apply_c0_followup_1939_v50.R`:

```r
## DB-frie tests for apply_c0_followup_1939_v50_helpers.R.
script_arg <- grep("^--file=", commandArgs(), value = TRUE)[1L]
script_dir <- if (!is.na(script_arg) && !identical(script_arg, "--file=-e")) {
  dirname(normalizePath(sub("^--file=", "", script_arg)))
} else {
  getwd()
}
source(file.path(script_dir, "apply_c0_followup_1939_v50_helpers.R"))

ok <- 0L
expect <- function(value, message = "expectation failed") {
  if (!isTRUE(value)) stop(message, call. = FALSE)
  ok <<- ok + 1L
}
expect_error <- function(expr, pattern) {
  got <- tryCatch({ force(expr); "" }, error = function(e) conditionMessage(e))
  expect(grepl(pattern, got, fixed = TRUE), paste(pattern, got))
}

## --- CLI-gaten ---------------------------------------------------------
fuld <- c("--manifest", "m.json", "--expect-sha256", "abc", "--backup", "b.dump",
          "--jeg-mener-det")

## 1) Lykkelig sti.
p <- c0f_parse_apply_args(fuld)
expect(identical(p$manifest, "m.json"))
expect(identical(p$expect_sha256, "abc"))
expect(identical(p$backup, "b.dump"))

## 2) UDEN bekraeftelse afvises. I fase D1 blev et opfundet --dryrun ignoreret,
##    og 68 personer blev publiceret i prod uden godkendelse.
expect_error(c0f_parse_apply_args(head(fuld, -1)), "C0F_APPLY_CONFIRMATION_REQUIRED")

## 3) Ukendt flag maa aldrig blive til tavs accept.
expect_error(c0f_parse_apply_args(c(fuld, "--dryrun")), "C0F_APPLY_CLI_INVALID")

## 4) Duplikeret flag.
expect_error(c0f_parse_apply_args(c(fuld, "--manifest", "n.json")), "C0F_APPLY_CLI_INVALID")

## 5) Hash-laasen er obligatorisk: uden den kan et haandredigeret manifest
##    saette sin egen forventning, som efterkontrollen saa "bekraefter".
expect_error(c0f_parse_apply_args(
  c("--manifest", "m.json", "--backup", "b.dump", "--jeg-mener-det")),
  "C0F_APPLY_SHA_REQUIRED")

## 6) Backup er obligatorisk: basen koerer paa free tier uden automatisk backup.
expect_error(c0f_parse_apply_args(
  c("--manifest", "m.json", "--expect-sha256", "abc", "--jeg-mener-det")),
  "C0F_APPLY_BACKUP_REQUIRED")

## 7) En flag-vaerdi der selv ligner et flag er en tastefejl, ikke en vaerdi.
expect_error(c0f_parse_apply_args(
  c("--manifest", "--expect-sha256", "abc", "--backup", "b.dump", "--jeg-mener-det")),
  "C0F_APPLY_CLI_INVALID")

## --- Guarden mod at basen har flyttet sig ------------------------------
SHA <- paste(rep("c", 64), collapse = "")
fixture_manifest <- function(...) {
  base <- list(
    schema_version = "1939-v50-c0-followup-manifest-v1",
    counts = list(operations = 2, bindings_create = 2),
    operations = list(
      list(person_id = 963, narrative_id = 632, page_from = 508,
           expected_old_narrative_sha256 = SHA, new_text = "A", new_text_sha256 = SHA),
      list(person_id = 991, narrative_id = 660, page_from = 504,
           expected_old_narrative_sha256 = SHA, new_text = "B", new_text_sha256 = SHA)))
  utils::modifyList(base, list(...))
}
fixture_live <- function(...) {
  base <- list(
    narrative_ids = c(632, 660), old_shas = c(SHA, SHA),
    privat = c(FALSE, FALSE), sider = c("508", "504"), bindinger = 0)
  utils::modifyList(base, list(...))
}

## 8) Lykkelig sti.
plan <- c0f_plan_apply(fixture_manifest(), fixture_live())
expect(identical(length(plan$operations), 2L))
expect(identical(plan$forventet_bindinger, 2))

## 9) Teksten er aendret siden eksporten -- replay-vaernet.
expect_error(c0f_plan_apply(fixture_manifest(),
  fixture_live(old_shas = c(paste(rep("d", 64), collapse = ""), SHA))),
  "C0F_APPLY_OLD_SHA_MISMATCH")

## 10) privat=TRUE ville blive tavst afprivatiseret (GDPR, invariant 8).
expect_error(c0f_plan_apply(fixture_manifest(), fixture_live(privat = c(FALSE, TRUE))),
             "C0F_APPLY_PRIVAT")

## 10b) NA spaerrer ogsaa.
expect_error(c0f_plan_apply(fixture_manifest(), fixture_live(privat = c(NA, FALSE))),
             "C0F_APPLY_PRIVAT")

## 11) Sidetallet er identitetskontrollen: afviger det, er recorden og
##     narrativet ikke samme trykte post.
expect_error(c0f_plan_apply(fixture_manifest(), fixture_live(sider = c("999", "504"))),
             "C0F_APPLY_SIDE_MISMATCH")

## 12) En eksisterende binding ville faa RPC'en til at kaste halvvejs igennem.
expect_error(c0f_plan_apply(fixture_manifest(), fixture_live(bindinger = 1)),
             "C0F_APPLY_ALREADY_BOUND")

## 13) Narrativet er forsvundet.
expect_error(c0f_plan_apply(fixture_manifest(), fixture_live(narrative_ids = c(632, 999))),
             "C0F_APPLY_NARRATIVE_DRIFT")

## 14) Ukendt schema_version.
expect_error(c0f_plan_apply(fixture_manifest(schema_version = "x"), fixture_live()),
             "C0F_APPLY_SCHEMA_UNKNOWN")

## 15) Tom mangde naar aldrig apply.
tom <- fixture_manifest(counts = list(operations = 0, bindings_create = 0))
tom$operations <- list()
expect_error(c0f_plan_apply(tom, fixture_live(narrative_ids = numeric(0))),
             "C0F_APPLY_EMPTY")

## --- Efterkontrollen ---------------------------------------------------
fixture_taelling <- function(...) {
  base <- list(bindinger = 0, narrativer = 1169, personer = 1811,
               fakta = 7197, relationer = 2030)
  utils::modifyList(base, list(...))
}

## 16) Lykkelig sti: praecis to nye bindinger, intet andet rykket.
expect(isTRUE(c0f_check_postcheck(fixture_taelling(),
                                  fixture_taelling(bindinger = 2), 2)))

## 17) Forkert antal bindinger.
expect_error(c0f_check_postcheck(fixture_taelling(),
  fixture_taelling(bindinger = 3), 2), "C0F_APPLY_POSTCHECK_MISMATCH")

## 18) Fasen maa ikke aendre ANTALLET af narrativer -- kun deres tekst.
expect_error(c0f_check_postcheck(fixture_taelling(),
  fixture_taelling(bindinger = 2, narrativer = 1170), 2), "C0F_APPLY_DELTA_NOT_ZERO")
expect_error(c0f_check_postcheck(fixture_taelling(),
  fixture_taelling(bindinger = 2, personer = 1812), 2), "C0F_APPLY_DELTA_NOT_ZERO")

## 19) Et tabt taellefelt maa ikke passere nul-delta:
##     identical(as.numeric(NULL), as.numeric(NULL)) er TRUE.
mangler <- fixture_taelling(); mangler$fakta <- NULL
expect_error(c0f_check_postcheck(mangler, fixture_taelling(bindinger = 2), 2),
             "C0F_APPLY_TAELLING_MANGLER")

cat(sprintf("OK: %d assertions\n", ok))
```

Create `tests/testthat/test-apply-c0-followup-1939-v50.R`:

```r
testthat::test_that("apply-c0-followup R contract passes direct assertions", {
  root <- normalizePath(file.path(getwd(), "..", ".."))
  old <- getwd()
  on.exit(setwd(old), add = TRUE)
  setwd(file.path(root, ".claude", "skills", "daa-extract", "scripts"))
  testthat::expect_no_error(source("test_apply_c0_followup_1939_v50.R", local = TRUE))
})
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
cd .claude/skills/daa-extract/scripts && Rscript test_apply_c0_followup_1939_v50.R
```
Expected: FAIL — `cannot open file 'apply_c0_followup_1939_v50_helpers.R'`

- [ ] **Step 3: Write the helpers**

Create `.claude/skills/daa-extract/scripts/apply_c0_followup_1939_v50_helpers.R`:

```r
## Ren logik bag C0-efterkoerslens apply: CLI-gaten, guarden mod at basen har
## flyttet sig, og efterkontrollen. Ingen DB-adgang.

## Fail-closed argument-parser. Et ukendt flag er en FEJL: i fase D1 blev et
## opfundet --dryrun stiltiende slugt, og 68 personer blev publiceret i prod.
c0f_parse_apply_args <- function(args) {
  allowed <- c("--manifest", "--expect-sha256", "--backup", "--jeg-mener-det")
  flags <- args[grepl("^--", args)]
  if (any(!flags %in% allowed) || anyDuplicated(flags))
    stop("C0F_APPLY_CLI_INVALID", call. = FALSE)
  if (!("--manifest" %in% flags)) stop("C0F_APPLY_CLI_INVALID", call. = FALSE)
  value <- function(flag) {
    index <- match(flag, args)
    if (is.na(index) || index == length(args) || grepl("^--", args[[index + 1L]]))
      stop("C0F_APPLY_CLI_INVALID", call. = FALSE)
    args[[index + 1L]]
  }
  manifest <- value("--manifest")
  if (!("--expect-sha256" %in% flags)) stop("C0F_APPLY_SHA_REQUIRED", call. = FALSE)
  expect_sha256 <- value("--expect-sha256")
  ## Basen koerer paa free tier UDEN automatisk backup. At tage en dump er en
  ## instruktion i planen; her er det en betingelse for at koere.
  if (!("--backup" %in% flags)) stop("C0F_APPLY_BACKUP_REQUIRED", call. = FALSE)
  backup <- value("--backup")
  ## Bekraeftelsen tjekkes SIDST, saa en malformet kommandolinje aldrig kan
  ## fremstaa som "manglede bare bekraeftelsen".
  if (!("--jeg-mener-det" %in% flags))
    stop("C0F_APPLY_CONFIRMATION_REQUIRED", call. = FALSE)
  list(manifest = manifest, expect_sha256 = expect_sha256, backup = backup)
}

c0f_spaerrer <- function(x) any(is.na(x) | as.logical(x))

## Sammenligner manifestet med basen som den ser ud NU. `live` skal maales
## INDE i skrive-transaktionen; ellers staar vinduet mellem maaling og
## skrivning aabent (TOCTOU).
c0f_plan_apply <- function(manifest, live) {
  if (!identical(manifest$schema_version, "1939-v50-c0-followup-manifest-v1"))
    stop("C0F_APPLY_SCHEMA_UNKNOWN", call. = FALSE)
  ops <- manifest$operations
  if (length(ops) == 0L) stop("C0F_APPLY_EMPTY", call. = FALSE)

  forventet_narr <- vapply(ops, function(o) as.numeric(o$narrative_id), numeric(1))
  if (!identical(sort(as.numeric(live$narrative_ids)), sort(forventet_narr)))
    stop("C0F_APPLY_NARRATIVE_DRIFT", call. = FALSE)
  ## Replay-vaern: er teksten aendret siden eksporten, gaelder beslutningerne
  ## en anden tekst end den vi er ved at overskrive.
  if (!identical(as.character(live$old_shas),
                 vapply(ops, function(o) as.character(o$expected_old_narrative_sha256),
                        character(1))))
    stop("C0F_APPLY_OLD_SHA_MISMATCH", call. = FALSE)
  ## GDPR (invariant 8): writeren sender altid p_privat=false, saa en privat
  ## post ville blive tavst afprivatiseret.
  if (c0f_spaerrer(live$privat)) stop("C0F_APPLY_PRIVAT", call. = FALSE)
  ## Identitetskontrol: beviser at recorden og narrativet er samme trykte post.
  if (!identical(as.character(live$sider),
                 vapply(ops, function(o) as.character(o$page_from), character(1))))
    stop("C0F_APPLY_SIDE_MISMATCH", call. = FALSE)
  ## red_publicer_narrative_record kaster SOURCE_RECORD_PUBLICATION_ALREADY_BOUND
  ## halvvejs igennem; vi vil hellere stoppe foer noget er skrevet.
  if (!identical(as.numeric(live$bindinger), 0))
    stop("C0F_APPLY_ALREADY_BOUND", call. = FALSE)

  list(operations = ops, forventet_bindinger = as.numeric(length(ops)))
}

## Efterkontrol: fasen aendrer narrativ-TEKST og tilfoejer bindinger. Antallet
## af narrativer, personer, fakta og relationer skal staa stille.
c0f_check_postcheck <- function(before, after, forventet_bindinger) {
  felter <- c("bindinger", "narrativer", "personer", "fakta", "relationer")
  if (length(setdiff(felter, names(before))) > 0L ||
      length(setdiff(felter, names(after))) > 0L)
    stop("C0F_APPLY_TAELLING_MANGLER", call. = FALSE)
  if (!identical(as.numeric(after$bindinger) - as.numeric(before$bindinger),
                 as.numeric(forventet_bindinger)))
    stop("C0F_APPLY_POSTCHECK_MISMATCH", call. = FALSE)
  for (felt in c("narrativer", "personer", "fakta", "relationer")) {
    if (!identical(as.numeric(before[[felt]]), as.numeric(after[[felt]])))
      stop("C0F_APPLY_DELTA_NOT_ZERO", call. = FALSE)
  }
  invisible(TRUE)
}
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
cd .claude/skills/daa-extract/scripts && Rscript test_apply_c0_followup_1939_v50.R
```
Expected: `OK: 24 assertions`

- [ ] **Step 5: Write the CLI wrapper**

Create `.claude/skills/daa-extract/scripts/apply_c0_followup_1939_v50.R`:

```r
#!/usr/bin/env Rscript
## CLI: Rscript apply_c0_followup_1939_v50.R --manifest PATH
##   --expect-sha256 HEX --backup DUMP --jeg-mener-det
##
## SKRIVER TIL PRODUKTION. Erstatter narrativtekst og opretter bindinger for
## de accepterede koblinger. EEN transaktion, ingen retry.
args <- commandArgs(trailingOnly = TRUE)
script_arg <- grep("^--file=", commandArgs(), value = TRUE)[1L]
script_dir <- dirname(normalizePath(sub("^--file=", "", script_arg)))
source(file.path(script_dir, "apply_c0_followup_1939_v50_helpers.R"))

parsed <- c0f_parse_apply_args(args)
if (!file.exists(parsed$manifest)) stop("C0F_APPLY_MANIFEST_MISSING", call. = FALSE)
{
  ## file= hasher filens bytes og matcher `shasum -a 256`.
  actual <- digest::digest(file = parsed$manifest, algo = "sha256")
  if (!identical(actual, parsed$expect_sha256))
    stop("C0F_APPLY_MANIFEST_SHA_MISMATCH", call. = FALSE)
}
if (!file.exists(parsed$backup)) stop("C0F_APPLY_BACKUP_MISSING", call. = FALSE)
if (file.info(parsed$backup)$size < 1e6) stop("C0F_APPLY_BACKUP_TOO_SMALL", call. = FALSE)
backup_sha <- digest::digest(file = parsed$backup, algo = "sha256")
manifest <- jsonlite::fromJSON(parsed$manifest, simplifyVector = FALSE)

## Begge RPC'er gates paa current_rolle()='redaktion', som udledes af
## profiles WHERE id = auth.uid(). Over en direkte forbindelse er auth.uid()
## NULL -> rollen bliver 'medlem' og kaldet kastes.
REDAKTOER_UUID <- "ba4ce28d-42a0-48af-a47c-773c26934236"
ADVISORY_LOCK_KEY <- "daa-1939-v50-production-writer"

env_or <- function(primary, fallback) {
  result <- Sys.getenv(primary)
  if (nzchar(result)) result else Sys.getenv(fallback)
}
con <- DBI::dbConnect(RPostgres::Postgres(),
  dbname = env_or("PGDATABASE", "SUPABASE_DB"), host = env_or("PGHOST", "SUPABASE_HOST"),
  port = as.integer(env_or("PGPORT", "SUPABASE_PORT")), user = env_or("PGUSER", "SUPABASE_USER"),
  password = env_or("PGPASSWORD", "SUPABASE_PASSWORD"),
  sslmode = if (nzchar(Sys.getenv("PGDATABASE"))) "disable"
            else if (nzchar(Sys.getenv("SUPABASE_SSLMODE"))) Sys.getenv("SUPABASE_SSLMODE")
            else "require",
  bigint = "integer")
on.exit(DBI::dbDisconnect(con), add = TRUE)

pg_bigint_array <- function(x) paste0("{", paste(as.integer(x), collapse = ","), "}")
ids <- vapply(manifest$operations, function(o) as.integer(o$person_id), integer(1))

taellinger <- function() {
  r <- DBI::dbGetQuery(con, "
    SELECT (SELECT count(*) FROM private.narrative_record_publication) AS bindinger,
           (SELECT count(*) FROM narrative) AS narrativer,
           (SELECT count(*) FROM person)    AS personer,
           (SELECT count(*) FROM fact)      AS fakta,
           (SELECT count(*) FROM relation)  AS relationer")
  list(bindinger = r$bindinger[[1L]], narrativer = r$narrativer[[1L]],
       personer = r$personer[[1L]], fakta = r$fakta[[1L]], relationer = r$relationer[[1L]])
}

## Rollback er EKSPLICIT i en tryCatch frem for on.exit: on.exit paa et
## scripts topniveau har ingen funktions-frame at haenge paa.
DBI::dbBegin(con)
resultat <- tryCatch({
  ## Advisory lock: samme noegle som fase B, saa to writers ikke kan koere
  ## samtidig mod den samme bestand.
  laas <- DBI::dbGetQuery(con, "SELECT pg_try_advisory_xact_lock(hashtext($1)) AS ok",
                          params = list(ADVISORY_LOCK_KEY))
  if (!isTRUE(laas$ok[[1L]])) stop("C0F_APPLY_LOCK_BUSY", call. = FALSE)

  foer <- taellinger()
  live_rows <- DBI::dbGetQuery(con, "
    SELECT n.subjekt_id AS person_id, n.id AS narrative_id,
           encode(extensions.digest(convert_to(n.tekst,'UTF8'),'sha256'),'hex') AS old_sha,
           n.privat, n.side,
           (SELECT count(*) FROM private.narrative_record_publication b
             WHERE b.narrative_id = n.id) AS bundet
      FROM narrative n
     WHERE n.subjekt_type='person' AND n.source_id=3
       AND n.subjekt_id = ANY($1::bigint[])
     ORDER BY n.subjekt_id", params = list(pg_bigint_array(ids)))

  plan <- c0f_plan_apply(manifest, list(
    narrative_ids = live_rows$narrative_id, old_shas = live_rows$old_sha,
    privat = live_rows$privat, sider = live_rows$side,
    bindinger = sum(as.numeric(live_rows$bundet))))

  DBI::dbGetQuery(con, "SELECT set_config('request.jwt.claim.sub', $1, true)",
                  params = list(REDAKTOER_UUID))
  rolle <- DBI::dbGetQuery(con, "SELECT rolle FROM profiles WHERE id = $1::uuid",
                           params = list(REDAKTOER_UUID))
  if (nrow(rolle) != 1L || !identical(rolle$rolle[[1L]], "redaktion"))
    stop("C0F_APPLY_ACTOR_NOT_REDAKTION", call. = FALSE)

  for (op in plan$operations) {
    ## p_side = NULL: RPC'ens UPDATE-gren skriver side = COALESCE(p_side, side),
    ## saa NULL bevarer det eksisterende. Efterkoerslen retter tekst, ikke sidetal.
    nid <- DBI::dbGetQuery(con,
      "SELECT red_upsert_narrativ('person', $1::bigint, $2::text, false, 3, NULL) AS id",
      params = list(as.integer(op$person_id), op$new_text))$id[[1L]]
    if (!identical(as.numeric(nid), as.numeric(op$narrative_id)))
      stop(paste0("C0F_APPLY_NARRATIVE_ID_DRIFT:", op$person_id), call. = FALSE)

    src <- DBI::dbGetQuery(con,
      "SELECT id FROM private.source_record WHERE record_key = $1",
      params = list(op$source_record_key))
    if (nrow(src) != 1L)
      stop(paste0("C0F_APPLY_SOURCE_RECORD_MISSING:", op$source_record_key), call. = FALSE)

    DBI::dbGetQuery(con,
      "SELECT red_publicer_narrative_record($1::bigint, $2::uuid, $3::text, $4::text) AS id",
      params = list(as.integer(op$narrative_id), src$id[[1L]],
                    op$source_record_key,
                    sprintf("DAA 1939 side %d", as.integer(op$page_from))))
  }

  efter <- taellinger()
  c0f_check_postcheck(foer, efter, plan$forventet_bindinger)
  cs <- DBI::dbGetQuery(con, "SELECT max(id) AS id FROM change_set")$id[[1L]]

  ## Taber vi forbindelsen EFTER commit, men foer svaret naar frem, er
  ## tilstanden UKENDT -- ikke delvis, men uafgjort.
  tryCatch(DBI::dbCommit(con), error = function(e)
    stop(paste0("C0F_APPLY_COMMIT_UKENDT: prod kan VAERE aendret. ",
                "Verificer bindings-antallet foer du overvejer at koere igen. ",
                "Underliggende: ", conditionMessage(e)), call. = FALSE))
  list(n = length(plan$operations), foer = foer$bindinger, efter = efter$bindinger,
       change_set = cs)
}, error = function(e) {
  if (!grepl("C0F_APPLY_COMMIT_UKENDT", conditionMessage(e), fixed = TRUE))
    try(DBI::dbRollback(con), silent = TRUE)
  stop(conditionMessage(e), call. = FALSE)
})

cat(sprintf("change_set=%s\n", resultat$change_set))
cat(sprintf("backup=%s sha256=%s\n", parsed$backup, backup_sha))
cat(sprintf("OK: %d koblinger; bindinger %d -> %d\n",
            resultat$n, resultat$foer, resultat$efter))
```

- [ ] **Step 6: Run the full suites**

Run:
```bash
Rscript run-tests.R
cd .claude/skills/daa-extract/scripts && python3 -m pytest test_build_c0_followup_flags_1939_v50.py \
  test_c0_followup_review_1939_v50.py test_build_c0_followup_manifest_1939_v50.py -q
```
Expected: R-suiten grøn; pytest `23 passed`

- [ ] **Step 7: Commit**

```bash
git add .claude/skills/daa-extract/scripts/apply_c0_followup_1939_v50*.R \
        .claude/skills/daa-extract/scripts/test_apply_c0_followup_1939_v50.R \
        tests/testthat/test-apply-c0-followup-1939-v50.R
git commit -m "feat(1939): fail-closed apply-wrapper til C0-efterkørslen"
```

---

### Task 6: Rehearsal, menneskeark og prod-kørsel

**Files:**
- Modify: `docs/changelog.md`
- Modify: `docs/database-current-state.md`
- Modify: `docs/decisions.md`

**Interfaces:**
- Consumes: alle scripts fra Task 1–5.
- Produces: intet kode; prod-tilstanden ændres, og dokumentationen afstemmes.

> **GATE:** Step 5 skriver til produktion og må først køres, når brugeren
> udtrykkeligt har sagt GO til de faktiske tal fra Step 4. Ingen af trinene
> må slås sammen.

- [ ] **Step 1: Tag backup og stil rehearsal-basen op**

Run:
```bash
mkdir -p work/task30-1939-v50-c0-efterkoersel
val() { sed -n "s/^$1=//p" ~/.Renviron | tr -d '"' | head -1; }
export PGPASSWORD="$(val SUPABASE_PASSWORD)"
STAMP=$(date +%Y%m%d-%H%M%S)
OUT="work/task30-1939-v50-c0-efterkoersel/pre-c0f-$STAMP.dump"
pg_dump "host=$(val SUPABASE_HOST) port=$(val SUPABASE_PORT) dbname=$(val SUPABASE_DB) user=$(val SUPABASE_USER) sslmode=require" \
  --format=custom --no-owner --no-acl --file="$OUT"
chmod 0600 "$OUT"; shasum -a 256 "$OUT"
dropdb --if-exists daa1939_c0f_rehearsal1
createdb daa1939_c0f_rehearsal1
pg_restore --no-owner --no-acl --dbname=daa1939_c0f_rehearsal1 "$OUT"
```
Expected: dump 0600 m. SHA-256 noteret; restore med enkelte rolle-fejl (forventet — Supabase-roller findes ikke lokalt).

**Bemærk:** `daa1939_d2_rehearsal1` har D2 anvendt og må IKKE genbruges.

- [ ] **Step 2: Kør kæden mod rehearsal-basen**

Run:
```bash
export PGDATABASE=daa1939_c0f_rehearsal1 PGHOST=localhost PGPORT=5432 \
       PGUSER=$(whoami) PGPASSWORD=dummy
W=work/task30-1939-v50-c0-efterkoersel
S=.claude/skills/daa-extract/scripts
C=work/task26-1939-v50-c0-record-linkage

Rscript $S/export_c0_followup_selection_1939_v50.R --output $W/rehearsal-selection.json \
  --expect-database-name daa1939_c0f_rehearsal1
python3 $S/build_c0_followup_flags_1939_v50.py --selection $W/rehearsal-selection.json \
  --candidates $C/linkage-candidates-v1.json --decisions $C/c0-afgoerelser.json \
  --output $W/rehearsal-flags.json
python3 $S/build_c0_followup_review_1939_v50.py --flags $W/rehearsal-flags.json \
  --output $W/rehearsal-ark.txt
python3 $S/convert_c0_followup_decisions_1939_v50.py --review $W/rehearsal-ark.txt \
  --flags $W/rehearsal-flags.json --output $W/rehearsal-decisions.json
python3 $S/build_c0_followup_manifest_1939_v50.py --flags $W/rehearsal-flags.json \
  --decisions $W/rehearsal-decisions.json --candidates $C/linkage-candidates-v1.json \
  --output $W/rehearsal-manifest.json
Rscript $S/apply_c0_followup_1939_v50.R --manifest $W/rehearsal-manifest.json \
  --expect-sha256 $(shasum -a 256 $W/rehearsal-manifest.json | cut -d' ' -f1) \
  --backup $W/pre-c0f-*.dump --jeg-mener-det
```
Expected: `valgte=9 privat=0` · `operationer=9 flag=8 {'hyphen_unproven': 8}` · `personer=9 orddelingsvalg=8` · `accepteret=9 afgjorte_orddelinger=8` · `operationer=9 bindinger=9` · `OK: 9 koblinger; bindinger 550 -> 559`

**Afviger flag-antallet fra 8, STOP** og fremlæg afvigelsen: normaliseringen har fundet noget andet, end målingen 2026-08-21 viste.

- [ ] **Step 3: Verificér rehearsal-resultatet og fail-closed-adfærd**

Run:
```bash
psql -d daa1939_c0f_rehearsal1 -X -q -c "
SELECT count(*) AS bindinger FROM private.narrative_record_publication;
SELECT count(*) AS narrativer FROM narrative;
SELECT subjekt_id, length(tekst) FROM narrative
 WHERE subjekt_type='person' AND source_id=3
   AND subjekt_id IN (963,967,978,991,992,1296,1297,1298,1299) ORDER BY subjekt_id;"
# gentaget kørsel SKAL afvises
Rscript $S/apply_c0_followup_1939_v50.R --manifest $W/rehearsal-manifest.json \
  --expect-sha256 $(shasum -a 256 $W/rehearsal-manifest.json | cut -d' ' -f1) \
  --backup $W/pre-c0f-*.dump --jeg-mener-det
```
Expected: 559 bindinger; narrativ-antal uændret; person 991 er **32 tegn** (uændret — dér tilføjer koblingen kun bindingen); gentaget kørsel afvist med `C0F_APPLY_ALREADY_BOUND`.

- [ ] **Step 4: Kør trin 1–4 mod prod og fremlæg menneskearket**

Run:
```bash
unset PGDATABASE PGHOST PGPORT PGUSER PGPASSWORD
W=work/task30-1939-v50-c0-efterkoersel; S=.claude/skills/daa-extract/scripts
C=work/task26-1939-v50-c0-record-linkage
Rscript $S/export_c0_followup_selection_1939_v50.R --output $W/selection-v1.json \
  --expect-database-name postgres
python3 $S/build_c0_followup_flags_1939_v50.py --selection $W/selection-v1.json \
  --candidates $C/linkage-candidates-v1.json --decisions $C/c0-afgoerelser.json \
  --output $W/flags-v1.json
python3 $S/build_c0_followup_review_1939_v50.py --flags $W/flags-v1.json \
  --output $W/ark-v1.txt
```

Fremlæg `ark-v1.txt` for brugeren: ni personer, otte orddelingsvalg. **Vent på
det udfyldte ark.** Kør derefter konverter + manifest og fremlæg manifestets
SHA-256, de ni tegn-delta og backuppens hash. **Vent på eksplicit GO.**

- [ ] **Step 5: Apply mod prod — én gang, ingen retry**

Run:
```bash
Rscript $S/apply_c0_followup_1939_v50.R --manifest $W/manifest-v1.json \
  --expect-sha256 <SHA fra Step 4> --backup $W/pre-c0f-<stamp>.dump --jeg-mener-det
```
Expected: `OK: 9 koblinger; bindinger 550 -> 559`

Fejler den, STOP. Kør ikke igen — den melder selv, hvad der har flyttet sig.

- [ ] **Step 6: Efterkontrol mod prod**

Run:
```bash
val() { sed -n "s/^$1=//p" ~/.Renviron | tr -d '"' | head -1; }
export PGPASSWORD="$(val SUPABASE_PASSWORD)"
psql "host=$(val SUPABASE_HOST) port=$(val SUPABASE_PORT) dbname=$(val SUPABASE_DB) user=$(val SUPABASE_USER) sslmode=require" -X -q -c "
BEGIN READ ONLY;
SELECT count(*) AS bindinger FROM private.narrative_record_publication;
SELECT count(*) AS narrativer FROM narrative;
SELECT count(*) AS personer FROM person;
SELECT subjekt_id, length(tekst) AS tegn FROM narrative
 WHERE subjekt_type='person' AND source_id=3
   AND subjekt_id IN (963,967,978,991,992,1296,1297,1298,1299) ORDER BY subjekt_id;
SELECT count(*) AS stadig_raa FROM narrative
 WHERE subjekt_type='person' AND source_id=3 AND tekst LIKE '%### PAGE%';
ROLLBACK;"
```
Expected: 559 bindinger; narrativ- og persontal uændrede; person 991 = 32 tegn; `stadig_raa = 0`.

- [ ] **Step 7: Opdatér dokumentationen og commit**

Skriv i `docs/changelog.md`: de ni tegn-delta, manifestets og dumpens SHA-256,
change_set-id'et, og at 1017 gik til C3. Afstem `docs/database-current-state.md`.
Marker C0-punktet i `docs/decisions.md` som udført, og lad C3-punktet stå åbent.

```bash
git add docs/changelog.md docs/database-current-state.md docs/decisions.md
git commit -m "docs(1939): C0's efterkørsel udført i prod — 9 koblinger"
```

---

## Fortrydelse

| Skrivning | Fortrydbar? |
|---|---|
| `narrative.tekst` | **Ja** — `narrative` står i `version_pk_registry` → `change_events` |
| `narrative_record_publication` | **Delvist** — `red_tilbagetraek_narrative_record(narrative_id)` findes i prod, men efterlader intet `change_event` |
| Sidste udvej | Dumpen fra Step 1 |
