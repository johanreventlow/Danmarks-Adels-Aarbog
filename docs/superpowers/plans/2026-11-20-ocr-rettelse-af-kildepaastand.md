# OCR-rettelse af kildepåstand (uden importanker) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redaktøren kan rette en læsefejl i en importeret kildepåstand direkte på påstanden — også for personer uden importanker — så der ikke opstår en alternativ påstand ved siden af.

**Architecture:** Ny RPC `red_ret_ocr_paastand` ved siden af `red_ret_paastand`. Den skriver i samme journal (`paastand_korrektion`, ny grund `ocr`, `interpretation_id` NULL), retter påstanden på samme id (B12-undtagelsen) og fortrydes med den eksisterende `red_fortryd_change_set`. Ceremonifunktionen `red_ret_paastand` røres ikke ("værdien er aldrig fri" gælder fortsat der). Webeditoren får en knap »Ret læsefejl« på kildepåstande.

**Tech Stack:** PostgreSQL/plpgsql (schema.sql, db-migrations.sql, db-rls.sql, db-verify.sql), psql-testfil i CI, React/TypeScript (web), vitest.

**Spec:** Denne plan (ingen separat spec). Udløsende sag: person 1559 Sophie von Sperling, fødsel »25 Marts 157« (DAA 1939, PDF-side 529; assertion 13833, fact 11315), skal være »25 Marts 1578«. Målt læse-kun i stand-in `r397a1_standin_20261120164941` 2026-11-20: 0 importankre, én påstand, citeret af kilde 3, `uforanderlig`, valgt, ingen binding, ingen redaktørrettelse.

**Review-budget:** 1 runde Opus-review af hele grenen før PR; overskridelse kræver én linje i decisions (B13).

## Adgangskrav (roadmap §»Adgangskrav til nye planer«)

1. **Roadmapmål:** intet — redaktørværktøj uden for genimportkæden (som kvalitetsarket). Kræver derfor beslutningspost (Task 1).
2. **Værdikædeled:** ingen; redaktionel kvalitet af eksisterende kildepåstande.
3. **Leverancetype:** generel (alle udgaver, alle personfakta med en kilde).
4. **Værdi:** læsefejl i 1939-påstande (ca. 1100 personer uden anker, changelog 2026-07-29) kan rettes uden at efterlade den forkerte læsning som alternativ på personsiden.
5. **Færdigbevis:** person 1559 viser »25 Marts 1578« i prod med én påstand; `red_paastand_historik(13833)` viser rettelsen med grund `ocr` og original `25 Marts 157`.
6. **Erstatter:** `red_edit_oplysning` som (forkert) vej til OCR-rettelser på kildepåstande; supplerer kvalitetsarket for personer uden anker.
7. **Review-budget:** se hovedet.

## Global Constraints

- Invariant 1: påstande overskrives aldrig — undtagen OCR-rettelse, der retter transskriptionen med original i journal + `change_event`. Denne plan udvider undtagelsen; CLAUDE.md-listen opdateres.
- Fejlkoder i RPC er ASCII-store-bogstaver med præfiks `PAASTAND_`; UI-tekster dansk.
- `paastand_korrektion` har ingen klientadgang; eneste læsevej er `red_paastand_historik`.
- Nye RPC'er: `SECURITY DEFINER`, `SET search_path=pg_catalog,public,private`, `REVOKE ALL ... FROM PUBLIC,anon,authenticated`, `GRANT EXECUTE ... TO authenticated`.
- `db-migrations.sql` er idempotent (kører 2× i CI).
- Commits: Conventional Commits, dansk beskrivelse, ingen Claude-attribution, ingen Claude-Session-linje. Ingen push uden ja.
- Prod-DDL før merge (memory: merge før DDL). Tjek `origin/main` og åbne PR'er for SQL-ændringer før push og før prod-DDL (#405 og en anden session rører de samme filer).

## Review Focus

1. **Person med ét stabilt anker, hvor påstanden er citeret af ankerets kilde** → afvises med `PAASTAND_BRUG_KVALITETSARK` (ellers to journaler for samme rettelse; kvalitetsarkets fingerprint bliver `stale`). Test i Task 2.
2. **Ufortolkelig dato** (fx »25 Marts 15?8«) → kan gemmes med `date_min/date_max/date_qualifier/date_certainty` = NULL, når redaktøren bekræfter; UI kræver bekræftelse som `OcrKildepanel`. Test i Task 2 + Task 4.
3. **Redaktørens egen påstand** (`uforanderlig=false` eller citation uden kilde) → afvises `PAASTAND_IKKE_KILDEPAASTAND`; knappen vises ikke. Test i Task 2 + Task 3.
4. **Fortrydelse** → `red_fortryd_change_set` genskaber påstanden præcis (date_raw/min/max/qualifier/certainty), journalrækken står, `red_paastand_historik` viser `fortrudt=true`, og visningscachen følger med. Test i Task 2.
5. **Gyldig binding, som den nye værdi bryder** → `PAASTAND_BINDING_BRYDES`, intet skrevet. Test i Task 2.

---

### Task 1: Beslutning og dokumentation

**Files:**
- Modify: `docs/decisions.md` (ny post øverst, efter linje 4)
- Modify: `CLAUDE.md:31` (invariant 1's undtagelsesliste)

- [ ] **Step 1:** Skriv decisions-post `## BESLUTTET: OCR-rettelse af kildepåstand uden importanker (2026-11-20)`: udløser (1559), at redaktørens editor laver ny påstand, at kvalitetsarket kræver anker, valget af søsterfunktion frem for udvidelse af `red_ret_paastand` (ceremoniens garanti "værdien er aldrig fri" bevares), grund `ocr` i samme journal, afgrænsningen (Task 2), og at leverancen er uden for roadmappets aktive mål (adgangskrav 1-7 ovenfor i kort form).
- [ ] **Step 2:** I CLAUDE.md invariant 1: tilføj `red_ret_ocr_paastand` ved siden af `red_ret_ocr_felt` som OCR-undtagelse (original i `paastand_korrektion` og `change_event`).
- [ ] **Step 3:** Commit: `git add docs/decisions.md CLAUDE.md && git commit -m "docs(beslutning): OCR-rettelse af kildepåstand uden importanker"`

### Task 2: DB — `red_ret_ocr_paastand` + journalgrund `ocr`

**Files:**
- Modify: `schema.sql` (CHECK på `paastand_korrektion.grund` ved ~10266; ny funktion lige efter `red_ret_paastand`'s GRANT ~10477)
- Modify: `db-migrations.sql` (ny idempotent blok sidst i filen)
- Modify: `db-rls.sql:746` (allow-liste) + REVOKE/GRANT ved ~912
- Modify: `db-verify.sql:3044` (signaturliste) + `:11157` (sikkerhedsblok)
- Create: `tests/sql/test-ocr-paastand.sql`
- Modify: `.github/workflows/ci.yml:213` og `:258` (kør testfilen efter `test-paastand-rettelse.sql` i begge evidens-jobs)

**Interfaces:**
- Produces: `public.red_ret_ocr_paastand(p_assertion_id bigint, p_forventet jsonb, p_ny jsonb) RETURNS jsonb` → `{assertion_id, grund:'ocr', foer, efter, change_set_id, korrektion_id}` (samme form som `red_ret_paastand`).
- `p_forventet`: præcis som `red_ret_paastand`: `{fact_id, faktatype, vaerdi_tekst, date_raw, valgt_assertion_id, citation_sources:[bigint]}`; enhver afvigelse → `PAASTAND_DRIFT`.
- `p_ny`: **enten** `{"vaerdi_tekst": text}` **eller** `{"date_raw": text, "date_min": date|null, "date_max": date|null, "date_qualifier": text|null, "date_certainty": text|null}` — præcis de nøgler. Datoformen kræver at påstanden har `date_raw IS NOT NULL`; tekstformen at `vaerdi_tekst IS NOT NULL`.

Regler, i denne rækkefølge (lås: person FOR UPDATE → assertion FOR UPDATE → fact FOR SHARE):

| Betingelse | Fejl |
|---|---|
| `auth.uid()` NULL eller `current_rolle()` ≠ `redaktion` | `PAASTAND_ROLLE_FORBUDT` |
| påstand findes ikke / ikke på personfaktum / drift mod `p_forventet` | `PAASTAND_DRIFT` |
| faktatype = `forældrefamilie` | `PAASTAND_FAKTATYPE_UGYLDIG` |
| `uforanderlig IS FALSE` | `PAASTAND_IKKE_KILDEPAASTAND` |
| distinkte `citation.source_id` ≠ præcis én ikke-NULL | `PAASTAND_KILDE_DELT` (NULL-kilde alene → `PAASTAND_IKKE_KILDEPAASTAND`) |
| person har præcis ét anker med `import_key`+`record_key`, ankerets `source_id` = påstandens kilde, og faktatype ∈ {navn, fødsel, død} | `PAASTAND_BRUG_KVALITETSARK` |
| `p_ny` ikke præcis én af formerne / tom tekst / ugyldig dato / `date_min>date_max` / qualifier ∉ {exact,before,after,between,about,floruit,NULL} / certainty ∉ {certain,uncertain,ambiguous,NULL} / formen passer ikke til påstanden | `PAASTAND_VAERDI_UGYLDIG` |
| ny værdi = gammel (tekst resp. date_raw) | `PAASTAND_VAERDI_UAENDRET` |
| gyldig binding brydes (kopi af blokken i `red_ret_paastand` med `private.binding_value_matches(r.value_kind,cur.value,v_new_vaerdi,v_new_raw)`) | `PAASTAND_BINDING_BRYDES` |

Skrivning: `begin_change_set('red_ret_ocr_paastand', format('Paastand %s: ocr', id), 'person', subjekt_id)`; UPDATE af enten `vaerdi_tekst` eller alle fem datokolonner; `INSERT INTO paastand_korrektion(... grund='ocr', interpretation_id=NULL ...)`. Visningscachen følger af `trg_assertion_regen`.

- [ ] **Step 1: Skriv `tests/sql/test-ocr-paastand.sql`** (mønster: `tests/sql/test-paastand-rettelse.sql` — `BEGIN; \ir fixtures/...; ... ROLLBACK;`, hjælper `pg_temp.pr_fakta`-lignende, redaktør via `set_config('request.jwt.claim.sub',…)` + `SET LOCAL ROLE authenticated`, jf. `tests/sql/fixtures/kalder-matrix.sql`). Tilfælde, hver med `RAISE EXCEPTION 'TEST_FAILED: …'` ved afvigelse:
  - `ocr_dato_rettes`: anker-løs person, fødsel `'25 Marts 157'` kilde X → `p_ny={"date_raw":"25 Marts 1578","date_min":"1578-03-25","date_max":"1578-03-25","date_qualifier":"exact","date_certainty":null}` → samme assertion-id har ny værdi; antal påstande på faktum uændret (1); journalrække grund `ocr`, `foer->>'date_raw'='25 Marts 157'`; `person.visning_foedt` = `'25 Marts 1578'`.
  - `ocr_tekst_rettes`: navnepåstand rettes via `{"vaerdi_tekst":…}`.
  - `ocr_ufortolkelig`: `date_raw` med min/max/qualifier/certainty NULL accepteres.
  - `ocr_fortryd`: `red_fortryd_change_set(<cs>)` → alle fem datokolonner som før; `red_paastand_historik` → `fortrudt=true`; cache tilbage.
  - Afvisninger: `PAASTAND_ROLLE_FORBUDT` (anon og ikke-redaktør), `PAASTAND_DRIFT` (forkert `date_raw` i forventet), `PAASTAND_IKKE_KILDEPAASTAND` (uforanderlig=false; og citation uden kilde), `PAASTAND_KILDE_DELT` (to kilder), `PAASTAND_FAKTATYPE_UGYLDIG` (forældrefamilie), `PAASTAND_BRUG_KVALITETSARK` (ét stabilt anker på samme kilde, fødsel), `PAASTAND_VAERDI_UGYLDIG` (begge former; ekstra nøgle; min>max; qualifier `'ca'`), `PAASTAND_VAERDI_UAENDRET`, `PAASTAND_BINDING_BRYDES` (fixture med gyldig binding — genbrug opsætningen fra `test-paastand-rettelse.sql`).
  - Efter hver afvisning: påstand og journal uændret.
- [ ] **Step 2: Kør mod lokal testklynge og se den fejle** (funktion findes ikke):
  `createdb ocrp_t && psql -d ocrp_t -f tests/sql/evidence-promotion-bootstrap.sql -f schema.sql -f db-rls.sql -f db-migrations.sql -f db-migrations.sql -f db-rls.sql && psql -d ocrp_t -v ON_ERROR_STOP=1 -f tests/sql/test-ocr-paastand.sql`
  Forventet: fejl `function public.red_ret_ocr_paastand(...) does not exist`. (Sæt `PGUSER` som CI-jobbet, jf. memory »Lokale CI-klynger«.)
- [ ] **Step 3: Implementér** i `schema.sql` (CHECK `grund IN ('bogen_har_ret','linjeskift-v1','ocr')`; funktion + REVOKE/GRANT) og spejl i `db-migrations.sql`: `ALTER TABLE paastand_korrektion DROP CONSTRAINT IF EXISTS paastand_korrektion_grund_check; ALTER TABLE ... ADD CONSTRAINT paastand_korrektion_grund_check CHECK (...)`; `CREATE OR REPLACE FUNCTION`. Opdatér tabelkommentaren i schema.sql (»skrives kun af red_ret_paastand« → begge). `db-rls.sql`: signatur i allow-listen + REVOKE/GRANT; kommentaren ved linje 910 nævner begge skriveveje. `db-verify.sql`: signatur i listen ved 3044 og i FOREACH-arrayet ved 11157.
- [ ] **Step 4: Kør testen + den eksisterende** → begge grønne:
  `psql -d ocrp_t -v ON_ERROR_STOP=1 -f tests/sql/test-ocr-paastand.sql -f tests/sql/test-paastand-rettelse.sql -f tests/sql/run-db-verify-disposable.sql`
  Kør derefter **hele** de to evidens-CI-jobs' psql-sekvens lokalt (`ci.yml:204-260`), ikke kun egne filer; tjek exit-kode. Slet egne testbaser efter commit.
- [ ] **Step 5: Wire testen i CI** (`ci.yml` efter begge `test-paastand-rettelse.sql`-linjer).
- [ ] **Step 6: Commit:** `git add schema.sql db-migrations.sql db-rls.sql db-verify.sql tests/sql/test-ocr-paastand.sql .github/workflows/ci.yml && git commit -m "feat(db): OCR-rettelse af kildepåstand uden importanker (red_ret_ocr_paastand)"`

### Task 3: Web — data- og skrivelag

**Files:**
- Modify: `web/src/data/redaktionRead.ts:61-70` (`Oplysning` + mapping ved 114)
- Create: `web/src/data/ocrPaastand.ts`
- Modify: `web/src/data/redaktionWrite.ts` (`Change.art` + ny gren ved ~293; `oversaetFejl` ~807)
- Test: `web/src/data/__tests__/ocrPaastand.test.ts`, `web/src/data/__tests__/redaktionWrite.test.ts`

**Interfaces:**
- Consumes: `normaliserOcrDato(raw)` fra `@daa/core`; `FeltEvidens`, `Oplysning`, `Kilde` fra `redaktionRead.ts`; `DATE_FELT` (eksportér den fra `redaktionWrite.ts`).
- Produces:
  - `Oplysning.vaerdiTekst: string | null` og `Oplysning.dateRaw: string | null` (rå kolonner; `vaerdi` uændret).
  - `kanRetteLaesefejl(o: Oplysning): boolean` — sand når `o.uforanderlig !== false` og præcis én distinkt ikke-null `kilder[].sourceId`.
  - `byggOcrPaastand(f: FeltEvidens, o: Oplysning, ny: string, bekraeftUfortolkelig: boolean): { p_assertion_id: number; p_forventet: Record<string, unknown>; p_ny: Record<string, unknown> } | null` — null hvis tom/uændret værdi, eller dato ikke forstået og ikke bekræftet. Datoform når `DATE_FELT.has(f.felt)`, ellers tekstform. `citation_sources` = sorterede distinkte ikke-null sourceIds; `valgt_assertion_id` = `f.konklusionAssertionId`.
  - `Change.art` får `'retLaesefejl'` med `payload: { forventet, ny }`; skrivegrenen returnerer `{ fn: 'red_ret_ocr_paastand', args: { p_assertion_id, p_forventet, p_ny } }`.

- [ ] **Step 1: Skriv fejlende tests:**
  - `kanRetteLaesefejl`: kildepåstand m. én kilde → true; `uforanderlig:false` → false; to kilder → false; kun `sourceId:null` → false.
  - `byggOcrPaastand` for fødsel `'25 Marts 157'`→`'25 Marts 1578'`: `p_ny` toEqual `{date_raw:'25 Marts 1578', date_min:'1578-03-25', date_max:'1578-03-25', date_qualifier:<det normaliserOcrDato giver>, date_certainty:<ditto>}`; `p_forventet.date_raw==='25 Marts 157'`, `vaerdi_tekst===null`, `citation_sources` toEqual `[3]`.
  - Uforstået dato uden bekræftelse → `null`; med → min/max/qualifier/certainty `null`.
  - Navn → `p_ny` toEqual `{ vaerdi_tekst: 'Sophie' }`.
  - `redaktionWrite`: `art:'retLaesefejl'` → `fn==='red_ret_ocr_paastand'`; `oversaetFejl('PAASTAND_BRUG_KVALITETSARK')` returnerer dansk tekst (ikke rå kode) — tilsvarende for alle ti koder fra Task 2.
- [ ] **Step 2:** `npm run test -w web -- ocrPaastand redaktionWrite` → FAIL.
- [ ] **Step 3: Implementér.** Danske fejltekster, fx `PAASTAND_BRUG_KVALITETSARK` → »Personen har et importanker — ret feltet i kvalitetsarket.«; `PAASTAND_DRIFT` → »Påstanden er ændret siden indlæsning. Genindlæs.«; `PAASTAND_BINDING_BRYDES` → »Rettelsen ville bryde en bekræftet binding til bogen.«
- [ ] **Step 4:** Samme kommando → PASS. Kør derefter hele `npm run test -w web` og `npm run build -w web`; tjek exit-kode (memory: `Redaktion.mediaFakta` kan fejle tilfældigt — genkør alene).
- [ ] **Step 5: Commit:** `git add web/src/data/redaktionRead.ts web/src/data/ocrPaastand.ts web/src/data/redaktionWrite.ts web/src/data/__tests__/ocrPaastand.test.ts web/src/data/__tests__/redaktionWrite.test.ts && git commit -m "feat(web): skrivevej til OCR-rettelse af kildepåstand"`

### Task 4: Web — knappen »Ret læsefejl« i personeditoren

**Files:**
- Modify: `web/src/Redaktion.tsx` (`renderOplysning`, ~1912-1955)
- Test: `web/src/__tests__/Redaktion.ocrPaastand.test.tsx` (mønster: `Redaktion.kvalitetsark.test.tsx`)

**Interfaces:** Consumes `kanRetteLaesefejl`, `byggOcrPaastand` (Task 3).

- [ ] **Step 1: Skriv fejlende komponenttest:** kildepåstand viser knap »Ret læsefejl« ved siden af »Redigér«; redaktørens egen (`uforanderlig:false`) viser den ikke. Klik → formular med værdifelt forudfyldt med `o.dateRaw ?? o.vaerdiTekst`, forklaringstekst »Retter bogens tekst, som den står trykt — ingen ny påstand.«, og for datofelter en fortolkningslinje fra `normaliserOcrDato` (»Forstået som 25.3.1578« / »Kan ikke fortolkes« + afkrydsning »Gem alligevel uden fortolket dato«). »Gem rettelse« er deaktiveret når `byggOcrPaastand` giver null. Gem → `submitChange` kaldt med `art:'retLaesefejl'`. Prøvekørsel går gennem den eksisterende `run()`/`submitChange({dryRun})` og sender intet (assert: ingen RPC i dry-run).
- [ ] **Step 2:** `npm run test -w web -- Redaktion.ocrPaastand` → FAIL.
- [ ] **Step 3: Implementér** med eksisterende stilobjekter (`inp`, `btnGhost`, `iconBtn`, `T`) og `sc`/`setSc`-mønstret (nøgle `'ocr:'+assertionId`). Efter vellykket gem genindlæses evidensen som efter `redigerOplysning`.
- [ ] **Step 4:** PASS; derefter hele web-suiten + build + `npm run e2e` med `PLAYWRIGHT_PORT` (memory: e2e genbruger dev-server).
- [ ] **Step 5: Commit:** `git add web/src/Redaktion.tsx web/src/__tests__/Redaktion.ocrPaastand.test.tsx && git commit -m "feat(redaktion): ret læsefejl i kildepåstand fra personeditoren"`

### Task 5: Review og PR

- [ ] **Step 1:** Opus-review af hele grenen (`git diff main...HEAD`), én runde. Rettelser som atomare commits.
- [ ] **Step 2:** Tjek `git fetch && git log HEAD..origin/main -- '*.sql'` og åbne PR'er for SQL-konflikter; rebase ved behov og kør Task 2 Step 4 igen.
- [ ] **Step 3:** Efter projektejerens ja: push og `gh pr create --draft`.

### Task 6: Prod-DDL (projektejerens shell) → merge

- [ ] **Step 1:** Generalprøve på frisk stand-in af prod: dump → restore → `db-migrations.sql` (2×) + `db-rls.sql` → `db-verify.sql`-blokkene for 6c-2b og den nye funktion → kør 1559-rettelsen (Task 7) i en `BEGIN … ROLLBACK` med `request.jwt.claim.sub` sat. Fortryd-DDL: hent `db-rls.sql` ved merge-basen (`git show <base>:db-rls.sql`) — memory »Fortryd-DDL: db-rls før grenen«.
- [ ] **Step 2:** Script under scratchpad, som projektejeren kører med `! zsh <sti>`: prod-dump (restorepunkt, sha noteret) → `--single-transaction` apply af blokken → læse-kun verifikation (funktion findes, ACL, CHECK). Statement-timeout 2 min.
- [ ] **Step 3:** Merge PR (projektejer) efter grøn CI.

### Task 7: Ret 1559 og dokumentér

- [ ] **Step 1:** Projektejeren retter i webredaktionen: person 1559 → Fødsel → »Ret læsefejl« → `25 Marts 1578` → Gem (prøvekørsel slået fra).
- [ ] **Step 2:** Verificér læse-kun: én påstand på fact 11315; `date_raw='25 Marts 1578'`, `date_min=date_max='1578-03-25'`; `visning_foedt` opdateret; journalrække grund `ocr` med `foer->>'date_raw'='25 Marts 157'`; personsiden som anon viser 1578 uden alternativ.
- [ ] **Step 3:** Opdatér `docs/database-current-state.md` (ny RPC, journalgrund), `docs/changelog.md` (dateret post), og commit: `docs(ocr): red_ret_ocr_paastand i prod; 1559 rettet`.
