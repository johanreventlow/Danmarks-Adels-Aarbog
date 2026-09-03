# 1939 v50 Fase B: Narrativ-erstatning + normalisering — taskplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.
> BEMÆRK: Task 3 er et HÅRDT menneskeligt checkpoint — eksekvering
> standser dér, indtil brugeren har afgjort flag-arket.
>
> **Historisk status (2026-09-03):** Checkboksene er den oprindelige fase
> B-arbejdsgang, ikke aktuel status for v50 eller det samlede
> genimportprogram. Brug `docs/evidensbaseret-genimport/status.md`, changelog,
> commits og aktuelle tests ved status- eller gate-spørgsmål.

**Goal:** Erstat de 551 kanoniske 1939-narrativer (543 eksisterende + 8 nye
personers) med den menneskeverificerede Calamari-tekst, normaliseret
(ombrydning fjernet, orddelinger sammentrukket, søskende-ordenstal
strippet), og publicér record-provenance for alle — med gamle tekster
bevaret i versionshistorikken.

**Architecture:** En ren, versioneret normaliseringstransform
(`narrative_norm_v1`) + en deterministisk manifest-bygger + et
menneskeligt flag-/diff-checkpoint + en hard-låst R-writer der i ÉN
transaktion kører 551× `red_upsert_narrativ` (source-nøglet, versioneret
via change_set) og 543× `red_publicer_narrative_record`
(ny-publiceringsvejen; de 8 har allerede published bindinger, som IKKE
røres — genkald ville fejle ALREADY_BOUND). Ingen DDL.

**Tech Stack:** Python 3 + pytest, R + testthat (DB-fri gateway-tests),
PostgreSQL 17 lokalt (rehearsal), psql mod prod (gated).

**Spec:** `docs/superpowers/plans/2026-08-18-1939-v50-resten-af-genimporten.md`
(fase B, inkl. normaliseringskontrakten pkt. 1-6).

## Global Constraints

- Prod-apply er IKKE en del af planen; Task 6 slutter i en GO-pakke.
  Backup + eksplicit brugergodkendelse m. eksakte hashes før apply.
- Verbatim/spans/rendition er byte-eksakte og urørlige; KUN
  `narrative.tekst` normaliseres. Ingen ændring af `citat_tekst`,
  `private.*`-evidens eller kanoniske fakta.
- `red_upsert_narrativ` og `red_publicer_narrative_record` bruges som de
  er (begge prod-live); INGEN DDL. Aktør = redaktions-profil via
  `set_config('request.jwt.claim.sub',…)`.
- Deterministisk output; dobbeltkørsel byte-identisk. Ingen
  tidsstempler/tilfældighed i manifestindhold.
- Supabase MCP `execute_sql` er read-only (kun efterkontrol).
- work/-artefakter committes aldrig. `load_daa.R` røres ikke.

## Faktagrundlag (verificeret 2026-08-18 aften — genudled ikke, assert)

- **Scope 551 = 543 + 8:** tekstkilder er (a) fase A-manifestet
  `work/task25-1939-v50-production-writer/phase-a-anchor-manifest-v1.json`
  (fil-SHA `1945416b3b56e781787366008a2463b419cb8ed4df3ef1399211cac5c999e208`):
  de 543 operationer MED `canonical_target.person_id` bærer span +
  verbatim + page_evidence + source_record_key; (b) task 25-manifestet
  `production-write-manifest-v1.json` (fil-SHA `8417b6de…`):
  `person_creates` (8) bærer samme felter + `name`.
- **26 narrativer udenfor scope:** prod har 577 personer m.
  source-3-narrativ; 543+8 dækkes; de 26 øvrige klassificeres READ-ONLY i
  Task 2 (forventet: de 3 pensionerede + parkerede/spanless) og røres ikke.
- **Ordenstal på 551-scopet:** 499 entydige `^\d{1,2}\.\s+` efter
  lstrip; 50 uden; 2 flags («7 Heinrich til Gottesgabe…» uden punktum;
  «2) Greve Conrad til Grevskabet Reventlow…» m. parentes). Disse tre tal
  SKAL asserteres af transformen mod det rigtige scope.
- **Bindinger i prod:** præcis 8 rækker i
  `private.narrative_record_publication`, alle `published`, alle for de 8
  nye. De 543 har INGEN binding → ny-publiceringsvejen i
  `red_publicer_narrative_record` indsætter direkte som `published`
  (etiketter: `record_label = source_record_key`,
  `citation_label = 'DAA 1939 side ' || page_from` — samme konvention som
  de 8 eksisterende).
- **`red_upsert_narrativ(p_subjekt_type,p_subjekt_id,p_tekst,p_privat,p_source_id,p_side)`**
  (schema.sql:3868): opdaterer eksisterende (person,source)-narrativ eller
  indsætter; skaber ét change_set pr. kald (versionshistorik = gamle
  tekster bevares). Alle 551 findes → forventet 551 UPDATEs, 0 INSERTs.
  `p_privat=false`, `p_side = page_from::text`.
- **Replay-politik (modsat fase A):** upsert er ikke naturligt idempotent.
  Writer-preflighten SKAL derfor verificere expected_old_narrative_sha256
  pr. narrativ mod DB før skrivning — efter en gennemført apply matcher
  intet, og en genkørsel afvises fail-closed. Det er den ønskede adfærd.
- Calamari-filen:
  `/Users/johanreventlow/TypeScript/danmarksadelsaarbog/work_1939_stamtavle/full_ocr_calamari_r6_clean.txt`
  (SHA `020123a3588dacf80705a22fb021ab4f5da97b8de202e8664304ca01f9a6da37`) —
  korpus til bindestreg-tiebreak.
- Rehearsal-basen `daa1939_phase_a_rehearsal1` (post-fase-A-tilstand
  identisk med prod) kan bruges til at hente gamle narrativ-tekster og som
  rehearsal-udgangspunkt (template-kopi; prod har fået fase A-applyen med
  samme indhold — verificér med kontroltal 592/897 før brug).

---

### Task 1: Normaliseringstransformen `narrative_norm_v1`

**Files:**
- Create: `.claude/skills/daa-extract/scripts/normalize_narrative_1939_v50.py`
- Create: `.claude/skills/daa-extract/scripts/test_normalize_narrative_1939_v50.py`

**Interfaces:**
- Produces: ren funktion
  `normalize_narrative_v1(raw: str, corpus: str) -> dict` med nøglerne
  `text` (normaliseret), `flags` (liste af
  `{"kind": "hyphen_ambiguous"|"hyphen_unproven"|"ordinal_ambiguous",
  "context": <±40 tegn>, "char_offset": <int i raw>}`), `applied`
  (tællinger: `soft_breaks_joined`, `hyphens_merged`,
  `hyphens_kept_compound`, `ordinal_stripped` 0/1,
  `page_markers_removed`). Deterministisk, ingen I/O. Slutinvariianter:
  intet `### PAGE`, intet enligt `\n`, ingen trailing whitespace.

- [ ] **Step 1: Skriv fejlende tests** — én test pr. regel i
  programplanens normaliseringskontrakt (pkt. 1-6), minimum:

```python
def test_afsnit_bevares():            # "a\n\nb" -> "a\n\nb"; "a\n\n\nb" -> "a\n\nb"
def test_bloed_ombrydning():          # "linje1\nlinje2" -> "linje1 linje2"
def test_orddeling_lille_bogstav():   # "sammen-\ntrækkes" -> "sammentrækkes"
def test_kompositum_stort_bogstav():  # "Reventlow-\nCriminil" -> "Reventlow-Criminil"
def test_korpus_tiebreak():           # XY ubrudt i korpus, X-Y ikke -> "XY" trods stort bogstav (og omvendt)
def test_hyphen_uafklaret_flager():   # begge/ingen i korpus + stort bogstav -> behold "X-Y" + flag
def test_ordenstal_strippes():        # "1. Sybille Malvina Lonny, f…" -> "Sybille Malvina Lonny, f…" (også efter ledende \n)
def test_ordenstal_uden_punktum_flager():   # "7 Heinrich til…" -> uændret + ordinal_ambiguous-flag
def test_ordenstal_parentes_flager():       # "2) Greve Conrad…" -> uændret + flag
def test_ingen_andre_aendringer():    # tegnsætning/stavning/OCR-fejl urørt; diff-klassekontrol på blandet fixture
def test_determinisme():              # to kald -> identisk dict
```

- [ ] **Step 2: Kør — forvent FAIL** (`/usr/bin/python3 -m pytest test_normalize_narrative_1939_v50.py -q` fra scripts-mappen)
- [ ] **Step 3: Implementér** (ren funktion + små hjælpere; korpus-opslag
  som simple `in`-søgninger på ubrudte former; INGEN regex-gæt ud over de
  specificerede mønstre)
- [ ] **Step 4: Korpus-regressionstest** (skip hvis work/ mangler): kør
  transformen på alle 551 rigtige spans (543 fra fase A-manifestet + 8 fra
  task 25-manifestet); assert: `ordinal_stripped`-sum == 499; præcis 2
  `ordinal_ambiguous`-flags (de to kendte kontekster); 0 tegn-ændringer
  uden for de tilladte klasser (verificér ved at "af-normalisere" ikke —
  men ved diff-klassifikation: hvert diff-hunk skal være linjeskift→space,
  `-\n`-sammentrækning, afsnits-kollaps eller ordenstal-strip); flaglisten
  deterministisk over to kørsler.
- [ ] **Step 5: Kør — forvent PASS; commit**
  (`feat(1939): narrative_norm_v1 — dewrap + ordenstals-strip m. fail-closed flags`)

### Task 2: Manifest-bygger for narrativ-erstatningen

**Files:**
- Create: `.claude/skills/daa-extract/scripts/build_narrative_replacement_manifest_1939_v50.py`
- Create: `.claude/skills/daa-extract/scripts/test_build_narrative_replacement_manifest_1939_v50.py`

**Interfaces:**
- Consumes: `normalize_narrative_v1` — byggeren IMPORTERER modulet
  (importlib fra samme mappe, som testfilerne gør). Transformen er fasens
  kerne og må aldrig findes i to kopier (controller-ruling; modsat
  batch-validatorerne, hvor duplikering er bevidst).
- Consumes: fase A-manifest (fil-SHA `1945416b…`), task 25-manifest
  (`8417b6de…`), Calamari (`020123a3…`), OG en eksport af de nuværende
  prod-narrativ-tekster (Task 2 genererer den selv read-only fra
  `daa1939_phase_a_rehearsal1` og hash-låser filen).
- Produces: `narrative-replacement-manifest-v1.json` med
  `schema_version="1939-v50-narrative-replacement-manifest-v1"`, 551
  operationer `{person_id, source_record_key, source_span, page_from,
  raw_sha256, normalized_sha256, normalized_text,
  expected_old_narrative_sha256, binding: "create"|"existing",
  record_label, citation_label}`, counts
  `{narratives:551, updates:551, inserts:0, bindings_create:543,
  bindings_existing:8}`, flagliste (må KUN være tom hvis Task 3-afgørelsen
  er indarbejdet), klassifikation af de 26 udenfor-scope (person_id +
  årsag), `manifest_content_sha256`.

- [ ] **Step 1: Fejlende tests** (fixtures + real-artefakt-skip-mønster):
  scoping-aritmetik 543+8=551 og 577−551=26; old-sha-eksport hash-låst;
  binding-split 543/8; determinisme; nøgle-komplethed pr. operation;
  afvisning ved flag-liste uden afgørelsesfil.
- [ ] **Step 2: FAIL → Step 3: Implementér → Step 4: PASS**
- [ ] **Step 5: Kør mod de rigtige artefakter** → manifest + rapport i
  work/task25-1939-v50-production-writer/; notér byte- og content-SHA.
- [ ] **Step 6: Commit** (`feat(1939): manifest-bygger for narrativ-erstatningen (551, fail-closed scoping)`)

### Task 3: MENNESKELIGT CHECKPOINT — flag- og diff-ark

**Files:**
- Create (work/, ikke committet):
  `work/task25-1939-v50-production-writer/narrative-replacement-review.md`

- [ ] **Step 1:** Generér arket: (a) ALLE flags fra transformen
  (bindestreg-uafklarede + de 2 ordenstals-flags) med kontekst og foreslået
  afgørelse; (b) 15 stikprøve-diffs (gammel prod-tekst ↔ ny normaliseret,
  spredt over korte/lange/flag-nære poster); (c) de 26 udenfor-scope med
  klassifikation.
- [ ] **Step 2: STOP.** Controlleren fremlægger arket for brugeren.
  Brugerens afgørelser (pr. flag: strip/behold/andet) skrives til
  `work/task25-1939-v50-production-writer/narrative-replacement-decisions-v1.json`
  og manifestet fra Task 2 regenereres med afgørelserne indarbejdet
  (`--decisions`-input, hash-låst). INGEN videre tasks før dette er sket.

### Task 4: R-writer `apply_narrative_replacement_1939_v50.R`

**Files:**
- Create: `.claude/skills/daa-extract/scripts/apply_narrative_replacement_1939_v50.R`
- Create: `.claude/skills/daa-extract/scripts/apply_narrative_replacement_1939_v50_helpers.R`
- Create: `.claude/skills/daa-extract/scripts/test_apply_narrative_replacement_1939_v50.R`
- Create: `tests/testthat/test-apply-narrative-replacement-1939-v50.R`

**Interfaces:**
- CLI: `--manifest … --manifest-sha256 … --output … (--dry-run | --apply)`
  (eksplicit tilstand obligatorisk, fase A-ruling). Én transaktion:
  1. preflight: databaseidentitet; alle 551 nuværende narrativ-SHA'er ==
     `expected_old_narrative_sha256` (én afvigelse → abort m. person_id);
     nøjagtigt 8 published bindinger og 0 for de 543; batch `328a813a…`
     (fase A) finalized så source-records findes;
  2. aktør-setup (`set_config`), 551× `red_upsert_narrativ` — returneret
     narrative_id skal matche eksisterende id (0 inserts);
  3. 543× `red_publicer_narrative_record` (ny-publicering) — returneret
     binding-id noteres; de 8 røres IKKE;
  4. verify: alle 551 narrativ-SHA'er == `normalized_sha256`; 551
     published bindinger i alt; kanoniske tællinger (person/fact/relation/
     family) uændrede; narrative-antal uændret;
  5. rollback (dry-run) eller commit (apply).
- DB-fri tests efter fase A-mønstret (fake gateway, kaldsorden,
  rollback-én-gang, hash-afvisning, old-sha-drift → abort, tilstandsflag).

- [ ] Steps: fejlende tests → FAIL → implementér → PASS → fulde suiter →
  commit (`feat(1939): narrativ-erstatnings-writer (551 upserts + 543 publiceringer, én transaktion)`)

### Task 5: Rehearsal

- [ ] Frisk template-kopi af `daa1939_phase_a_rehearsal1` (verificér
  592/897-kontroltal først — den har allerede fase A-tilstanden som prod).
- [ ] Baseline (narrativ-SHA'er pr. person + bindings-dump + kanoniske
  tællinger + change_set-antal) → dry-run (byte-identisk) → apply
  (forventet: 551 narrativer m. nye SHA'er, 551 published bindinger,
  change_set +551, narrative-antal uændret, kanonisk nul-delta) → replay
  (forventet: FAIL-CLOSED afvisning pga. old-sha-drift, 0 ændringer) →
  rapport i work/.
- [ ] Stikprøve: 5 personers gamle tekst genfindes i versionshistorikken
  (`hist_for_subjekt`-vejen).

### Task 6: GO-pakke

- [ ] `docs/superpowers/reviews/1939-v50-phase-b-readiness.md` efter fase
  A-mønstret: alle hashes (manifest byte+content, decisions-fil, alle
  inputs), rehearsal-tal, flag-afgørelsernes antal, replay-fail-closed-
  bevis, suite-resultater, credentialscan, godkendelsesliste (prod-id,
  ny backup, hashes, én --apply, efterkontrol). Commit. STOP.
