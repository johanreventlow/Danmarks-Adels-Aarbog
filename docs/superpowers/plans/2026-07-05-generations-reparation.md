# Generations-reparation af stamtræet — Implementeringsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Når en aner-kant i Kolonner-stamtræet er ubevist, lad brugeren bladre til generations-naboerne (samme linjes forrige slægtled) som ubeviste kandidater — deterministisk backfill af slægtled fra bogen + en ren fallback-ring i træ-byggeren.

**Architecture:** (a) Datalag: `segment.py` fanger slægtled (lokal + gennemgående) + `kuld` deterministisk fra `work/raw_full.txt`; en R-backfill skriver dem til `person_external_id` via ét fortrydbart `change_set`. (b) App-lag: modellen hydrerer generations-koordinater pr. kanonisk person + linje-hierarki; den rene `buildDirection` bygger en fallback-ring når aner-ringen er tom, med et founder-krydshop til moderlinjen. Motoren (`buildModel`/`relationship`) og evidenslaget røres ALDRIG.

**Tech Stack:** Python 3 (segment/pytest), R (DBI/RPostgres + `begin_change_set`), PostgreSQL/Supabase, TypeScript/React (`web/`), React Native/Expo + Zustand (`mobile/`), Vitest/Jest.

## Global Constraints

- **Design-kilde:** `docs/superpowers/specs/2026-07-05-generations-reparation-design.md`. Enhver tvivl afgøres der.
- **Invariant:** fallback-ringen er en ren read-time projektion. Skriv ALDRIG en `relation`-kant, en `fact`, eller til `visning_*`-cachen fra denne feature. At vælge en kandidat re-ankrer kun (navigation).
- **Join-nøgle for backfill:** `(source_id, linje, nr)`. `nr` reset­ter pr. gren — brug ALDRIG `nr` alene. NULL/ukendt `linje` → karantæne (fail-closed), aldrig match.
- **Generation coalesces aldrig** til én værdi pr. person: en founder bærer flere linje-medlemskaber med hver sit tal.
- **Founder-hop degraderer fail-closed:** hop kun ved præcis ét hierarki-kompatibelt mål; ellers stop uden fallback.
- **v1 = kun aner-retningen.** Descendants-fallback og fuld kuld→forælder-opløsning er v2.
- **DB-rækkefølge:** verificér migration + backfill LOKALT mod prod-svarende skema-kopi FØR prod; kør `get_advisors(security)` efter DDL mod prod (memory `koer-get-advisors-efter-ddl`).
- **R-login:** `~/.Renviron` (`SUPABASE_HOST/USER/PASSWORD/PORT/DB`). R's egen `.Renviron` vinder over shell-env — behandl som prod-gated (memory `r-env-renviron-override-farlig`).
- **Commits:** Conventional Commits, dansk. Ingen "Generated with"/"Co-Authored-By: Claude"-footers. Afslut med `Claude-Session:`-linjen.
- **Ingen bypass** af pre-commit/pre-push hooks.

---

## Fase (a) — Datalag: fang slægtled + kuld og backfill til prod

### Task A1: Dansk ordinal→heltal-helper

**Files:**
- Create: `.claude/skills/daa-extract/scripts/ordinals.py`
- Test: `.claude/skills/daa-extract/scripts/test_ordinals.py`

**Interfaces:**
- Produces: `ordinal_to_int(word: str) -> int | None` — normaliserer (lowercase, strip) og slår op i en fast dansk ordinal-tabel; returnerer `None` for ukendte/ikke-ordinaler.

- [ ] **Step 1: Write the failing test**

```python
# test_ordinals.py
from ordinals import ordinal_to_int

def test_known_ordinals():
    assert ordinal_to_int("Første") == 1
    assert ordinal_to_int("andet") == 2
    assert ordinal_to_int("Tolvte") == 12
    assert ordinal_to_int("  Nittende ") == 19

def test_unknown_returns_none():
    assert ordinal_to_int("Tyvende-og-noget") is None
    assert ordinal_to_int("") is None
    assert ordinal_to_int("42") is None
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd .claude/skills/daa-extract/scripts && python3 -m pytest test_ordinals.py -q`
Expected: FAIL — `ModuleNotFoundError: No module named 'ordinals'`

- [ ] **Step 3: Write minimal implementation**

```python
# ordinals.py
"""Dansk ordinal (ord) -> heltal. Dækker slægtled-spændet i DAA + margin.

Bruges af segment.py til at parse 'Første (tolvte) slægtled'-headere. Deterministisk;
udvid tabellen hvis en ny udgave bruger højere slægtled end 'toogtyvende'.
"""
_ORDINALS = {
    "første": 1, "andet": 2, "tredje": 3, "fjerde": 4, "femte": 5, "sjette": 6,
    "syvende": 7, "ottende": 8, "niende": 9, "tiende": 10, "ellevte": 11, "tolvte": 12,
    "trettende": 13, "fjortende": 14, "femtende": 15, "sekstende": 16, "syttende": 17,
    "attende": 18, "nittende": 19, "tyvende": 20, "enogtyvende": 21, "toogtyvende": 22,
}

def ordinal_to_int(word):
    if not word:
        return None
    return _ORDINALS.get(word.strip().lower())
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd .claude/skills/daa-extract/scripts && python3 -m pytest test_ordinals.py -q`
Expected: PASS (2 passed)

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/daa-extract/scripts/ordinals.py .claude/skills/daa-extract/scripts/test_ordinals.py
git commit -m "feat(daa-extract): dansk ordinal->heltal-helper til slægtled"
```

---

### Task A2: `segment.py` fanger dobbelt-nummereret slægtled → lokal + gennemgående

**Files:**
- Modify: `.claude/skills/daa-extract/scripts/segment.py` (SLGT_RE ~linje 42; header-branch ~linje 103-106; post-record ~linje 116-118; docstring ~linje 8-11)
- Test: `.claude/skills/daa-extract/scripts/test_segment_slaegtled.py`

**Interfaces:**
- Produces: hver post-record får felterne `slaegtled_lokal: int | None` og `slaegtled_gennem: int | None` (udover det eksisterende `slaegtled`-råtekst-felt og `kuld`). En header uden parentes sætter kun `slaegtled_lokal` (gennem = None).

- [ ] **Step 1: Write the failing test**

```python
# test_segment_slaegtled.py
import subprocess, sys, json, tempfile, os, textwrap

def _run(raw):
    with tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False, encoding="utf-8") as f:
        f.write(raw); path = f.name
    out = subprocess.run([sys.executable, "segment.py", path], capture_output=True, text=True,
                         cwd=os.path.dirname(__file__) or ".")
    os.unlink(path)
    return json.loads(out.stdout)

def test_single_ordinal_header():
    raw = textwrap.dedent("""\
        I  DEN HOLSTENSKE LINJE
        Første slægtled
        1.  Gottschalk Reventlow, nævnt 1223.
        """)
    posts = _run(raw)
    assert posts[0]["slaegtled_lokal"] == 1
    assert posts[0]["slaegtled_gennem"] is None

def test_dual_numbered_header():
    raw = textwrap.dedent("""\
        V  DEN YNGRE LINJE
        Første (tolvte) slægtled
        1.  Conrad Reventlow, 1644-1708.
        """)
    posts = _run(raw)
    assert posts[0]["slaegtled_lokal"] == 1
    assert posts[0]["slaegtled_gennem"] == 12
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd .claude/skills/daa-extract/scripts && python3 -m pytest test_segment_slaegtled.py -q`
Expected: FAIL — `KeyError: 'slaegtled_lokal'`

- [ ] **Step 3: Update the regex + parsing**

I `segment.py`, øverst (efter `import`): `from ordinals import ordinal_to_int`.

Erstat `SLGT_RE`-linjen med (fanger valgfri parentes-ordinal):

```python
SLGT_RE    = re.compile(r'^\s*(\w+)(?:\s*\((\w+)\))?\s+slægtled\s*$', re.I)
```

Tilføj to felt-holdere i main-løkkens header-state. Ret header-branchen (den nuværende
`m = SLGT_RE.match(line)`-blok) til også at sætte lokal/gennem:

```python
        m = SLGT_RE.match(line)
        if m:
            flush(posts, cur); cur = None
            slaegtled = m.group(1)
            slaegtled_lokal = ordinal_to_int(m.group(1))
            slaegtled_gennem = ordinal_to_int(m.group(2)) if m.group(2) else None
            i += 1; continue
```

Initialisér `slaegtled_lokal = slaegtled_gennem = None` sammen med de øvrige state-variabler
(linjen `linje = slaegtled = marr = kuld = page = cur = None` → tilføj de to nye), og NULstil dem
hvert sted `slaegtled` NULstilles (gren-header-branchene: `slaegtled = marr = kuld = None`
→ tilføj `slaegtled_lokal = slaegtled_gennem = None`).

Tilføj felterne til post-record'en (`cur = {...}`):

```python
                   'slaegtled': slaegtled,
                   'slaegtled_lokal': slaegtled_lokal, 'slaegtled_gennem': slaegtled_gennem,
```

Ret docstring-påstanden (~linje 9): `nr` er **pr. gren**, ikke global — erstat den vildledende sætning:

```python
  * Løbenummeret (nr) reset­ter pr. gren (linje I..V starter hver ved 1). Den unikke nøgle
    er (linje, nr) inden for én kilde — IKKE nr alene.
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd .claude/skills/daa-extract/scripts && python3 -m pytest test_segment_slaegtled.py -q`
Expected: PASS (2 passed)

- [ ] **Step 5: Smoke mod den ægte bog**

Run: `cd .claude/skills/daa-extract/scripts && python3 segment.py ../../../../work/raw_full.txt > /tmp/seg.json && python3 -c "import json; d=json.load(open('/tmp/seg.json')); n=sum(1 for p in d if p.get('slaegtled_lokal')); print(f'{n}/{len(d)} poster med lokal slægtled')"`
Expected: et flertal af poster har `slaegtled_lokal` sat (ikke 0). Noter tallet.

- [ ] **Step 6: Commit**

```bash
git add .claude/skills/daa-extract/scripts/segment.py .claude/skills/daa-extract/scripts/test_segment_slaegtled.py
git commit -m "feat(daa-extract): segment fanger dobbelt-nummereret slægtled (lokal+gennemgående)"
```

---

### Task A3: DB-migration — kolonner + trigger-hærdning

**Files:**
- Modify: `schema.sql` (person_external_id-definition ~linje 118-124; trigger-funktion `trg_regen_from_external_id` ~linje 482-493)
- Modify: `db-migrations.sql` (tilføj idempotent blok)
- Modify: `db-verify.sql` (tilføj assert-task)

**Interfaces:**
- Produces: kolonnerne `person_external_id.slaegtled_lokal INTEGER`, `.slaegtled_gennem INTEGER`, `.kuld TEXT`. Trigger `trg_external_id_regen` fyrer kun på `INSERT`, `DELETE`, og `UPDATE OF person_id, source_id, linje, nr` (ikke på generations-/kuld-UPDATE).

- [ ] **Step 1: Opdatér `schema.sql` (source of truth)**

I `person_external_id`-tabellen, efter `nr INTEGER,`:

```sql
  slaegtled_lokal  INTEGER,                -- slægtled lokalt i linjen (1,2,3… fra grenens start)
  slaegtled_gennem INTEGER,                -- gennemgående slægtled (parentes-tallet i bogen)
  kuld             TEXT,                    -- børne-gruppe-markør (romertal) inde i grenen; proveniens + gruppering
```

Ret trigger-definitionen så generations-/kuld-ændringer ikke regenererer visning-cachen. Erstat
`CREATE TRIGGER trg_external_id_regen ... AFTER INSERT OR UPDATE OR DELETE ...` med:

```sql
CREATE TRIGGER trg_external_id_regen
  AFTER INSERT OR DELETE OR UPDATE OF person_id, source_id, linje, nr ON person_external_id
  FOR EACH ROW EXECUTE FUNCTION trg_regen_from_external_id();
```

- [ ] **Step 2: Tilføj idempotent blok i `db-migrations.sql`**

```sql
-- 2026-07-05: generations-reparation — slægtled + kuld på person_external_id (design-spec 2026-07-05).
ALTER TABLE person_external_id ADD COLUMN IF NOT EXISTS slaegtled_lokal  INTEGER;
ALTER TABLE person_external_id ADD COLUMN IF NOT EXISTS slaegtled_gennem INTEGER;
ALTER TABLE person_external_id ADD COLUMN IF NOT EXISTS kuld             TEXT;

-- Trigger-hærdning: generations-/kuld-UPDATE må IKKE udløse regen_person_visning (påvirker ikke visning_*).
DROP TRIGGER IF EXISTS trg_external_id_regen ON person_external_id;
CREATE TRIGGER trg_external_id_regen
  AFTER INSERT OR DELETE OR UPDATE OF person_id, source_id, linje, nr ON person_external_id
  FOR EACH ROW EXECUTE FUNCTION trg_regen_from_external_id();
```

- [ ] **Step 3: Tilføj assert i `db-verify.sql`** (følg filens eksisterende Task-nummerering/format)

```sql
-- Task N: generations-kolonner findes + trigger scoped
DO $$
BEGIN
  ASSERT (SELECT count(*) FROM information_schema.columns
          WHERE table_name='person_external_id'
            AND column_name IN ('slaegtled_lokal','slaegtled_gennem','kuld')) = 3,
    'Mangler generations-kolonner på person_external_id';
END $$;
```

- [ ] **Step 4: Verificér LOKALT mod prod-svarende skema-kopi**

Følg memory `lokal-db-testbase`: rejs lokal prod-kopi, kør `db-migrations.sql` derefter `db-verify.sql`.
Run: `psql "$LOCAL_DSN" -v ON_ERROR_STOP=1 -f db-migrations.sql && psql "$LOCAL_DSN" -v ON_ERROR_STOP=1 -f db-verify.sql`
Expected: ingen fejl; assert grøn.

- [ ] **Step 5: Commit**

```bash
git add schema.sql db-migrations.sql db-verify.sql
git commit -m "feat(db): slægtled+kuld-kolonner på person_external_id + trigger-hærdning"
```

- [ ] **Step 6: Anvend til prod (BRUGER-GATE)**

STOP. Bed brugeren bekræfte. Anvend derefter `db-migrations.sql` mod prod (MCP `apply_migration` eller psql),
og kør `get_advisors(security)`. Ret evt. nye RLS/search_path-fund før du fortsætter (memory `koer-get-advisors-efter-ddl`).

---

### Task A4: R-backfill af slægtled+kuld → prod via ét change_set

**Files:**
- Create: `.claude/skills/daa-extract/scripts/backfill_slaegtled.R`

**Interfaces:**
- Consumes: segment-output-JSON (`/tmp/seg.json` fra A2 step 5) med felterne `linje, nr, slaegtled_lokal, slaegtled_gennem, kuld`.
- Produces: opdaterede `person_external_id`-rækker i prod under ét `change_set` (operation `backfill_slaegtled`), fortrydbart med `red_fortryd_change_set(<id>)`.

- [ ] **Step 1: Skriv scriptet** (mønster fra `fix_boern_multi_union.R`: idempotens-guard + `dbBegin`/`begin_change_set`/`dbCommit`)

```r
#!/usr/bin/env Rscript
# Backfill af slægtled (lokal+gennemgående) + kuld til person_external_id.
# Join-nøgle: (source_id, linje, nr). NULL/ukendt linje karantænes (ikke matchet).
# Fortrydbart: ét change_set (operation='backfill_slaegtled'). Fortryd: red_fortryd_change_set(<id>).
# Kør EFTER db-migrations.sql (kolonner skal findes). Idempotent via guard.
suppressMessages({library(DBI); library(RPostgres); library(jsonlite)})

args <- commandArgs(trailingOnly = TRUE)
seg_path <- if (length(args)) args[[1]] else "/tmp/seg.json"
posts <- fromJSON(seg_path, simplifyDataFrame = TRUE)

host <- Sys.getenv("SUPABASE_HOST"); user <- Sys.getenv("SUPABASE_USER"); pw <- Sys.getenv("SUPABASE_PASSWORD")
if (host == "" || user == "" || pw == "") stop("Sæt SUPABASE_HOST/USER/PASSWORD i ~/.Renviron.")
con <- dbConnect(RPostgres::Postgres(), host = host,
                 port = as.integer(Sys.getenv("SUPABASE_PORT", "5432")),
                 dbname = Sys.getenv("SUPABASE_DB", "postgres"),
                 user = user, password = pw, sslmode = "require")
on.exit(dbDisconnect(con), add = TRUE)
q  <- function(sql, p = list()) if (length(p)) dbGetQuery(con, sql, params = p) else dbGetQuery(con, sql)

# Resolvér DAA-stamtavle-kilden (den som person_external_id-rækkerne hovedsageligt bruger).
sid <- q("SELECT source_id, count(*) n FROM person_external_id
          GROUP BY source_id ORDER BY n DESC LIMIT 1")$source_id[[1]]
cat(sprintf("[backfill] source_id=%s\n", sid))

# Byg (linje,nr) -> (lokal,gennem,kuld); kun rækker med linje != NA og lokal != NA.
rows <- posts[!is.na(posts$linje) & !is.na(posts$slaegtled_lokal),
              c("linje","nr","slaegtled_lokal","slaegtled_gennem","kuld")]
quarantined <- sum(is.na(posts$linje) & !is.na(posts$slaegtled_lokal))
cat(sprintf("[backfill] %d rækker med linje+lokal; %d karantænet (NULL linje)\n", nrow(rows), quarantined))

# Idempotens-guard.
already <- q("SELECT id FROM change_set WHERE operation='backfill_slaegtled' ORDER BY id LIMIT 1")
if (nrow(already)) stop(sprintf("Allerede anvendt som change_set %s. Fortryd først (red_fortryd_change_set(%s)).",
                                already$id[[1]], already$id[[1]]))

dbBegin(con)
ok <- tryCatch({
  cs <- dbGetQuery(con, "SELECT begin_change_set('backfill_slaegtled', 'Slægtled+kuld fra DAA-stamtavle')")[[1]]
  matched <- 0
  for (i in seq_len(nrow(rows))) {
    n <- dbExecute(con,
      "UPDATE person_external_id
          SET slaegtled_lokal=$1, slaegtled_gennem=$2, kuld=$3
        WHERE source_id=$4 AND linje=$5 AND nr=$6",
      params = list(rows$slaegtled_lokal[i],
                    if (is.na(rows$slaegtled_gennem[i])) NA else rows$slaegtled_gennem[i],
                    if (is.na(rows$kuld[i])) NA else rows$kuld[i],
                    sid, rows$linje[i], rows$nr[i]))
    matched <- matched + n
  }
  cat(sprintf("[backfill] %d person_external_id-rækker opdateret\n", matched))
  cs
}, error = function(e) { dbRollback(con); stop(e) })
dbCommit(con)
cat(sprintf("[backfill] Færdig. change_set id=%s (fortryd: SELECT red_fortryd_change_set(%s);)\n", ok, ok))
```

- [ ] **Step 2: Dry-run-verifikation LOKALT** (mod prod-kopi hvis muligt; ellers læs-only tælling mod prod FØR write)

Run (tælling, ingen skrivning): `psql "$DSN" -c "SELECT count(*) FROM person_external_id WHERE slaegtled_lokal IS NOT NULL;"`
Expected FØR backfill: 0.

- [ ] **Step 3: Kør backfill mod prod (BRUGER-GATE)**

STOP. Bekræft med bruger. Run: `Rscript .claude/skills/daa-extract/scripts/backfill_slaegtled.R /tmp/seg.json`
Expected: rapporterer matched > 0, karantænet-tal, change_set id.

- [ ] **Step 4: Verificér resultat mod prod**

Run: `psql "$DSN" -c "SELECT linje, count(*) FILTER (WHERE slaegtled_lokal IS NOT NULL) med, count(*) tot FROM person_external_id GROUP BY linje ORDER BY linje;"`
Expected: hver linje har et flertal med slægtled; noter dækningsgrad. Stikprøve: Conrad (V, nr 1) → lokal 1, gennem 12.

- [ ] **Step 5: Reload-holdbarhed**

Tilføj et kald til backfill'en i `post_load_fixup.R`-sporet (så en `--force-reset`-reload genanvender den). Følg filens eksisterende idempotente stil (guard mod dobbelt-anvendelse findes allerede i A4-scriptet).

- [ ] **Step 6: Commit**

```bash
git add .claude/skills/daa-extract/scripts/backfill_slaegtled.R .claude/skills/daa-extract/scripts/post_load_fixup.R
git commit -m "feat(daa-extract): fortrydbar backfill af slægtled+kuld til person_external_id"
```

---

## Fase (b) — Model-hydrering: generations-koordinater pr. kanonisk person

### Task B1: Rene generations-helpers (web)

**Files:**
- Create: `web/src/data/generations.ts`
- Test: `web/src/data/__tests__/generations.test.ts`

**Interfaces:**
- Consumes: `RawExtId[]` (udvidet, se B2), `RawLineage[]` (udvidet), `canonicalIdById: Record<string,string>`.
- Produces:
  - `type GenCoord = { sourceId: string; linje: string; lineageId: string | null; parentLineageId: string | null; lokal: number | null; gennem: number | null; kuld: string | null }`
  - `buildGenCoords(extIds, lineageRows, canonicalIdById): Record<string, GenCoord[]>` — kanonisk person-id → alle dens linje-koordinater (coalescer ALDRIG).
  - `previousAncestorGen(coords: GenCoord[], curLinje: string, curLokal: number): { linje: string; lokal: number } | null` — næste aner-ring: `{curLinje, curLokal−1}` hvis `curLokal>1`; ellers founder-hop (§7): den ENESTE moderlinje-koordinat med `lokal>1`, ellers `null`.

- [ ] **Step 1: Write the failing test**

```typescript
import { describe, it, expect } from 'vitest';
import { buildGenCoords, previousAncestorGen, type GenCoord } from '../generations';

const lineage = [
  { id: '10', source_id: '1', kode: 'III', navn: 'Midterste', parent_lineage_id: null },
  { id: '50', source_id: '1', kode: 'V', navn: 'Yngre', parent_lineage_id: '10' },
];

describe('buildGenCoords', () => {
  it('samler flere linje-koordinater på én kanonisk founder', () => {
    const ext = [
      { person_id: '900', source_id: '1', linje: 'V', nr: 1, slaegtled_lokal: 1, slaegtled_gennem: 12, kuld: null },
      { person_id: '901', source_id: '1', linje: 'III', nr: 58, slaegtled_lokal: 12, slaegtled_gennem: 12, kuld: null },
    ];
    const coords = buildGenCoords(ext, lineage, { '900': '900', '901': '900' });
    expect(coords['900']).toHaveLength(2);
    expect(coords['900'].map((c) => c.linje).sort()).toEqual(['III', 'V']);
  });
});

describe('previousAncestorGen', () => {
  const coords: GenCoord[] = [
    { sourceId: '1', linje: 'V', lineageId: '50', parentLineageId: '10', lokal: 1, gennem: 12, kuld: null },
    { sourceId: '1', linje: 'III', lineageId: '10', parentLineageId: null, lokal: 12, gennem: 12, kuld: null },
  ];
  it('går et lokalt slægtled tilbage i samme linje', () => {
    expect(previousAncestorGen(coords, 'III', 12)).toEqual({ linje: 'III', lokal: 11 });
  });
  it('hopper til moderlinjen ved founder (lokal 1)', () => {
    expect(previousAncestorGen(coords, 'V', 1)).toEqual({ linje: 'III', lokal: 11 });
  });
  it('stopper fail-closed når ingen entydig moderlinje findes', () => {
    const only = [coords[0]]; // kun V, lokal 1, ingen gen>1-koordinat
    expect(previousAncestorGen(only, 'V', 1)).toBeNull();
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd web && npx vitest run src/data/__tests__/generations.test.ts`
Expected: FAIL — kan ikke resolve `../generations`.

- [ ] **Step 3: Write implementation**

```typescript
// web/src/data/generations.ts
// Rene generations-helpers til hul-reparation. Coalescer ALDRIG generation pr. person:
// en founder bærer flere linje-koordinater med hver sit tal (design-spec §6-7).
import type { RawExtId, RawLineage } from './types';

export type GenCoord = {
  sourceId: string; linje: string;
  lineageId: string | null; parentLineageId: string | null;
  lokal: number | null; gennem: number | null; kuld: string | null;
};

export function buildGenCoords(
  extIds: RawExtId[],
  lineageRows: RawLineage[],
  canonicalIdById: Record<string, string>,
): Record<string, GenCoord[]> {
  const linById = new Map<string, RawLineage>();
  for (const l of lineageRows) linById.set(`${l.source_id}:${l.kode}`, l);
  const out: Record<string, GenCoord[]> = {};
  for (const x of extIds) {
    if (x.linje == null) continue; // NULL linje karantænes — ingen koordinat
    const canon = canonicalIdById[String(x.person_id)] ?? String(x.person_id);
    const lin = linById.get(`${x.source_id}:${x.linje}`) ?? null;
    (out[canon] ??= []).push({
      sourceId: String(x.source_id), linje: x.linje,
      lineageId: lin ? String(lin.id) : null,
      parentLineageId: lin && lin.parent_lineage_id != null ? String(lin.parent_lineage_id) : null,
      lokal: x.slaegtled_lokal ?? null, gennem: x.slaegtled_gennem ?? null, kuld: x.kuld ?? null,
    });
  }
  return out;
}

export function previousAncestorGen(
  coords: GenCoord[], curLinje: string, curLokal: number,
): { linje: string; lokal: number } | null {
  if (curLokal > 1) return { linje: curLinje, lokal: curLokal - 1 };
  // Founder (lokal 1): hop til moderlinjen. Find den aktuelle koordinats parentLineageId.
  const cur = coords.find((c) => c.linje === curLinje && c.lokal === 1);
  const parentId = cur?.parentLineageId ?? null;
  const candidates = coords.filter(
    (c) => c.lineageId != null && c.lineageId === parentId && (c.lokal ?? 0) > 1,
  );
  if (candidates.length !== 1) return null; // fail-closed: kun præcis ét mål
  return { linje: candidates[0].linje, lokal: (candidates[0].lokal as number) - 1 };
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd web && npx vitest run src/data/__tests__/generations.test.ts`
Expected: PASS (alle 4).

- [ ] **Step 5: Commit**

```bash
git add web/src/data/generations.ts web/src/data/__tests__/generations.test.ts
git commit -m "feat(web): rene generations-koordinat-helpers + founder-hop"
```

---

### Task B2: Hydrér generations-koordinater ind i web-modellen

**Files:**
- Modify: `web/src/data/types.ts` (RawExtId ~linje 28-33; RawLineage ~linje 34; Model ~linje 141-172)
- Modify: `web/src/data/model.ts` (ext-id-select ~linje 68; lineage-select ~linje 70; Model-samling ~linje 145-160)
- Test: `web/src/data/__tests__/model.test.ts` (udvid eller opret assert på `genCoordsByPerson`)

**Interfaces:**
- Consumes: `buildGenCoords` (B1).
- Produces: `Model.genCoordsByPerson: Record<string, GenCoord[]>` tilgængelig for tree-byggeren (C1).

- [ ] **Step 1: Udvid typerne** i `types.ts`:

```typescript
export type RawExtId = {
  person_id: string | number;
  source_id: string | number;
  linje: string | null;
  nr: number | null;
  slaegtled_lokal?: number | null;
  slaegtled_gennem?: number | null;
  kuld?: string | null;
};

export type RawLineage = {
  source_id: string | number;
  kode: string;
  navn: string;
  id?: string | number;
  parent_lineage_id?: string | number | null;
};
```

Tilføj til `Model` (efter `lineage?`): `genCoordsByPerson?: Record<string, import('./generations').GenCoord[]>;`

- [ ] **Step 2: Udvid fetch + samling** i `model.ts`:

Ext-id-select → `select('person_id,source_id,linje,nr,slaegtled_lokal,slaegtled_gennem,kuld')`.
Lineage-select → `select('id,source_id,kode,navn,parent_lineage_id')`.
Tilføj import: `import { buildGenCoords } from './generations';`
I Model-objektet (hvor `lineage: buildLineage(...)` sættes):
`genCoordsByPerson: buildGenCoords(extIds, lineageRows, collapsed.canonicalIdById),`

- [ ] **Step 3: Write/extend test**

```typescript
// i model.test.ts — mock supabase-svar med de nye kolonner og assert:
expect(model.genCoordsByPerson?.['900']).toBeDefined();
```

- [ ] **Step 4: Kør typecheck + tests**

Run: `cd web && npx tsc --noEmit && npx vitest run src/data/__tests__/model.test.ts`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add web/src/data/types.ts web/src/data/model.ts web/src/data/__tests__/model.test.ts
git commit -m "feat(web): hydrér genCoordsByPerson (slægtled+linje-hierarki) i modellen"
```

---

### Task B3: Spejl generations-helpers + hydrering i mobile

**Files:**
- Create: `mobile/src/data/generations.ts` (identisk kerne som B1)
- Test: `mobile/src/data/__tests__/generations.test.ts`
- Modify: `mobile/src/data/types.ts`, `mobile/src/data/load.ts` (spejler B2)

**Interfaces:**
- Produces: `Model.genCoordsByPerson` i mobile-modellen; samme `GenCoord`/`buildGenCoords`/`previousAncestorGen`-signaturer som web.

- [ ] **Step 1: Kopiér B1's `generations.ts` + test** til `mobile/src/data/` (justér import-stier til mobile `types`). Kør: `cd mobile && npx jest src/data/__tests__/generations.test.ts`. Expected: PASS.
- [ ] **Step 2: Spejl B2's type- + fetch-udvidelser** i `mobile/src/data/types.ts` + `load.ts` (samme kolonner i `select`, samme `buildGenCoords`-kald i model-samlingen).
- [ ] **Step 3: Kør typecheck + tests.** Run: `cd mobile && npx tsc --noEmit && npx jest src/data`. Expected: PASS.
- [ ] **Step 4: Commit**

```bash
git add mobile/src/data/generations.ts mobile/src/data/__tests__/generations.test.ts mobile/src/data/types.ts mobile/src/data/load.ts
git commit -m "feat(mobile): spejl generations-koordinater + founder-hop i modellen"
```

---

## Fase (c) — Ren kerne: fallback-ring i træ-byggeren

### Task C1: Fallback-ring i `buildDirection` (web)

**Files:**
- Modify: `web/src/data/tree.ts` (TreeColumn-type ~linje 14-21; `buildDirection` ~linje 39-61; `buildBidirectionalColumns` ~linje 64-78)
- Test: `web/src/data/__tests__/tree.test.ts`

**Interfaces:**
- Consumes: `Model.genCoordsByPerson` (B2), `previousAncestorGen` (B1).
- Produces: `TreeColumn` udvides med `fallback?: boolean`, `genLabel?: string`, `kuldGroups?: Record<string, ModelPerson[]>`. Aner-ringen bygges via generation når `parentsOf` er tom.

- [ ] **Step 1: Write the failing test**

```typescript
import { describe, it, expect } from 'vitest';
import { buildBidirectionalColumns } from '../tree';
import type { Model } from '../types';

// Minimal model: anker P (V, lokal 1, founder) uden beviste forældre; to naboer i III lokal 11.
function makeModel(): Model {
  const persons = [
    { id: 'P', name: 'Conrad', years: '', parentId: null, spouseIds: [], childIds: [] },
    { id: 'A', name: 'Ane1', years: '', parentId: null, spouseIds: [], childIds: [] },
    { id: 'B', name: 'Ane2', years: '', parentId: null, spouseIds: [], childIds: [] },
  ] as any;
  const byId: any = Object.fromEntries(persons.map((p: any) => [p.id, p]));
  return {
    persons, byId, indexes: {} as any,
    genCoordsByPerson: {
      // Founder P = collapset V-1 + III-58 → bærer BEGGE koordinater (coalescer aldrig).
      P: [
        { sourceId: '1', linje: 'V', lineageId: '50', parentLineageId: '10', lokal: 1, gennem: 12, kuld: null },
        { sourceId: '1', linje: 'III', lineageId: '10', parentLineageId: null, lokal: 12, gennem: 12, kuld: null },
      ],
      A: [{ sourceId: '1', linje: 'III', lineageId: '10', parentLineageId: null, lokal: 11, gennem: 11, kuld: 'I' }],
      B: [{ sourceId: '1', linje: 'III', lineageId: '10', parentLineageId: null, lokal: 11, gennem: 11, kuld: 'II' }],
    },
  } as any;
}

describe('fallback-ring', () => {
  it('bygger en founder-hop fallback-ring når aner-ringen er tom', () => {
    const cols = buildBidirectionalColumns(makeModel(), 'P', [], []);
    const fb = cols.find((c) => c.fallback);
    expect(fb).toBeDefined();
    expect(fb!.people.map((p) => p.id).sort()).toEqual(['A', 'B']);
    expect(fb!.genLabel).toContain('slægtled');
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd web && npx vitest run src/data/__tests__/tree.test.ts`
Expected: FAIL — `fallback` findes ikke / ringen er tom.

- [ ] **Step 3: Implementér fallback i `tree.ts`**

Udvid `TreeColumn`:

```typescript
export type TreeColumn = {
  key: string; kind: ColumnKind; depth: number; label: string;
  people: ModelPerson[]; selectedId: string | null;
  fallback?: boolean;                         // true = ubeviste generations-naboer
  genLabel?: string;                          // 'N. slægtled · <linje> (M. gennemgående)'
  kuldGroups?: Record<string, ModelPerson[]>; // gruppering pr. kuld (v1, hvor kendt)
};
```

Tilføj en hjælper + brug den i `buildDirection`'s ancestor-gren (kun `kind==='ancestor'`), lige før
`if (!people.length) break;` — hvis `people` er tom OG vi kan finde en generations-koordinat for `cur`:

```typescript
import { previousAncestorGen, type GenCoord } from './generations';

// Byg fallback-ring: alle personer i (linje, lokal) via genCoordsByPerson. Ren projektion.
function fallbackAncestorRing(
  model: Model, anchorId: string, cur: string, depth: number,
): TreeColumn | null {
  const coords = model.genCoordsByPerson?.[cur];
  if (!coords || !coords.length) return null;
  // Vælg den koordinat vi traverserer på: laveste lokal (nærmest founder-hop) med et gyldigt spring.
  for (const c of coords) {
    if (c.lokal == null) continue;
    const prev = previousAncestorGen(coords, c.linje, c.lokal);
    if (!prev) continue;
    const all = model.persons.filter((p) => {
      if (p.id === anchorId || p.id === cur) return false;
      const pc = model.genCoordsByPerson?.[p.id];
      return !!pc?.some((k) => k.linje === prev.linje && k.lokal === prev.lokal);
    });
    if (!all.length) continue;
    const kuldGroups: Record<string, ModelPerson[]> = {};
    for (const p of all) {
      const k = model.genCoordsByPerson?.[p.id]?.find(
        (x) => x.linje === prev.linje && x.lokal === prev.lokal,
      )?.kuld ?? '—';
      (kuldGroups[k] ??= []).push(p);
    }
    const gennem = all.map((p) => model.genCoordsByPerson?.[p.id]?.find(
      (x) => x.linje === prev.linje && x.lokal === prev.lokal)?.gennem).find((g) => g != null);
    const genLabel = `${prev.lokal}. slægtled · ${prev.linje}-linjen`
      + (gennem != null ? ` (${gennem}. gennemgående)` : '');
    return {
      key: `ancestor:${depth}:fb`, kind: 'ancestor', depth,
      label: 'Muligt slægtled', people: all, selectedId: null,
      fallback: true, genLabel, kuldGroups,
    };
  }
  return null;
}
```

I `buildDirection`, i ancestor-grenen, erstat `if (!people.length) break;` med:

```typescript
    if (!people.length) {
      if (kind === 'ancestor') {
        const fb = fallbackAncestorRing(model, anchorId, cur, depth);
        if (fb) { cols.push(fb); }
      }
      break; // fallback-ringen er en bevidst dødende: vælg re-ankrer i stedet for at drille videre
    }
```

(Signaturen på `buildDirection` skal have `anchorId` — den har det allerede som parameter.)

- [ ] **Step 4: Run test to verify it passes**

Run: `cd web && npx vitest run src/data/__tests__/tree.test.ts`
Expected: PASS.

- [ ] **Step 5: Regression — hele suiten**

Run: `cd web && npx vitest run && npx tsc --noEmit`
Expected: alt grønt (ingen eksisterende tree-test brudt).

- [ ] **Step 6: Commit**

```bash
git add web/src/data/tree.ts web/src/data/__tests__/tree.test.ts
git commit -m "feat(web): fallback-ring i buildDirection (generations-naboer + founder-hop)"
```

---

### Task C2: Spejl fallback-ring i mobile-selektorerne

**Files:**
- Modify: `mobile/src/data/selectors.ts` (TreeColumn ~linje 101; `buildDirection` ~linje 122; `buildBidirectionalColumns` ~linje 146)
- Test: `mobile/src/data/__tests__/selectors.test.ts`

**Interfaces:**
- Produces: identisk `TreeColumn`-udvidelse + fallback-adfærd som C1.

- [ ] **Step 1: Skriv den spejlede test** (kopiér C1's fallback-test, justér import til `../selectors`). Run: `cd mobile && npx jest src/data/__tests__/selectors.test.ts`. Expected: FAIL.
- [ ] **Step 2: Port `fallbackAncestorRing` + TreeColumn-udvidelsen + `buildDirection`-ændringen** fra C1 til `selectors.ts` (samme kode, mobile import-stier).
- [ ] **Step 3: Kør tests + typecheck.** Run: `cd mobile && npx jest src/data && npx tsc --noEmit`. Expected: PASS + ingen regression.
- [ ] **Step 4: Commit**

```bash
git add mobile/src/data/selectors.ts mobile/src/data/__tests__/selectors.test.ts
git commit -m "feat(mobile): spejl fallback-ring i selectors (generations-naboer + founder-hop)"
```

---

## Fase (d) — UI web: render fallback-ringen

### Task D1: Fallback-styling + generations-header i Kolonner-visningen (web)

**Files:**
- Modify: `web/src/Folgesvend.tsx` (Kolonner-/TreeView-render — find hvor `TreeColumn.people` og `column.label` renderes; søg `depth`/`kind`/`selectedId`)
- Modify: `web/src/components/__tests__/TreeView.test.tsx` (hvis TreeView er en separat komponent)

**Interfaces:**
- Consumes: `TreeColumn.fallback/genLabel/kuldGroups` (C1).

- [ ] **Step 1: Find render-stedet** for en kolonne. Run: `cd web && grep -n "TreeColumn\|\.people\|column\.label\|kind ===" src/Folgesvend.tsx src/components/*.tsx`
- [ ] **Step 2: Render fallback distinkt.** For en kolonne med `fallback`: vis `genLabel` i headeren; render kort med stiplet kant + dæmpet/gul baggrund + et "muligt slægtled"-tag; gruppér efter `kuldGroups` (én under-overskrift pr. kuld-nøgle, `—` udelades som overskrift). En proven kolonne renderes uændret. Klik på et fallback-kort kalder den SAMME `onFocus(id)` som normale kort (re-ankrer — skriver intet).
- [ ] **Step 3: Verificér ingen skrivning.** Bekræft i koden at fallback-klik kun kalder `onFocus`/re-anchor — ingen `red_*`/`supabase.from(...).insert/update`.
- [ ] **Step 4: Typecheck + build + tests.** Run: `cd web && npx tsc --noEmit && npm run build && npx vitest run`. Expected: grønt.
- [ ] **Step 5: Empirisk browser-verifikation mod prod.** Naviger til en founder (fx Conrad) hvis forældre er ubeviste; bekræft: fallback-ring vises med korrekt slægtled-label, founder folder over til moderlinjen, klik re-ankrer. (Ingen browser-driver i repo → manuel eller Playwright hvis tilgængelig; noter hvad der blev kørt.)
- [ ] **Step 6: Commit**

```bash
git add web/src/Folgesvend.tsx web/src/components/
git commit -m "feat(web): render fallback-ring med slægtled-header + kuld-gruppering"
```

---

## Fase (e) — UI mobile: render fallback-ringen

### Task E1: Fallback-styling + generations-header i mobile-stamtræet

**Files:**
- Modify: `mobile/src/app/(tabs)/tree.tsx` (kolonne-render)

**Interfaces:**
- Consumes: `TreeColumn.fallback/genLabel/kuldGroups` (C2).

- [ ] **Step 1: Find kolonne-renderen.** Run: `cd mobile && grep -n "TreeColumn\|\.people\|column\|onFocus\|anchorId" src/app/\(tabs\)/tree.tsx`
- [ ] **Step 2: Render fallback distinkt** (spejl D1: stiplet kant/dæmpet baggrund/"muligt slægtled"-tag, `genLabel` som header, kuld-gruppering). Klik kalder den eksisterende `onFocus`/anchor-mutator — skriver intet.
- [ ] **Step 3: Typecheck + tests.** Run: `cd mobile && npx tsc --noEmit && npx jest`. Expected: grønt.
- [ ] **Step 4: Empirisk verifikation** i iOS-simulator/enhed mod prod (memory `mobil-fysisk-enhed-setup`; sim-fetch-bug → brug enhed ved -1005). Bekræft fallback-ring + founder-hop + re-ankring.
- [ ] **Step 5: Commit**

```bash
git add mobile/src/app/
git commit -m "feat(mobile): render fallback-ring med slægtled-header + kuld-gruppering"
```

---

## Afslutning

- [ ] **Full-suite-gate:** `cd web && npx tsc --noEmit && npx vitest run` + `cd mobile && npx tsc --noEmit && npx jest` — alt grønt.
- [ ] **`/simplify`** på de ikke-trivielle nye moduler (`generations.ts`, `tree.ts`/`selectors.ts`-diff).
- [ ] **Dual-review** (Codex) af den samlede diff før PR (cross-package: R+DB+web+mobile).
- [ ] **PR som `--draft`** mod main; `docs/changelog.md` + `docs/decisions.md` opdateret; CLAUDE.md §5-tilstand + relevant memory noteret.

## Sporbarhed: spec → task

| Spec-sektion | Task |
|---|---|
| §4 Datamodel (kolonner + trigger-hærdning) | A3 |
| §5 Datalag (segment-fix, ordinal, join, change_set) | A1, A2, A4 |
| §6 Model-hydrering (koordinat-array, lineage-hierarki) | B1, B2, B3 |
| §7 Founder-krydshop | B1 (`previousAncestorGen`), C1/C2 |
| §8 App-lag (fallback i buildDirection, re-anchor, invariant) | C1, C2, D1, E1 |
| §9 Semantik (kuld-gruppering, NULL-skjul, whole-gen labels) | C1 (kuldGroups), D1/E1 (labels) |
| §10 Test | indlejret pr. task (TDD) |
