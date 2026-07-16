# Review 30 — Problem 2 (konkurrerende forældrefamilie) dual-review

**Dato:** 2026-07-16
**Scope:** Hele Problem 2 — DB-lag (PR #39, merget: schema.sql/db-migrations.sql/db-verify.sql),
R-loadere (member_evidence), app-lag (PR #40: redaktionWrite/Read + UI web+mobil).
**Metode:** 3 parallelle code-analyzer bug-hunts (DB / R / app) → empirisk reproduktion → fix → verify.

## Sammenfatning

3 klasser af fund. De to DB-fund (B1/B2) er den samme rod: de **tre strukturelle
`family_member`-mutatorer blev opdateret asymmetrisk** — kun `red_flyt_barn` fik slot-vedligehold,
så invariant P1/komplethed IKKE holdt for "ALLE skrive-veje" (§2). Begge empirisk reproduceret +
fikset + dækket af ny db-verify-fixture. R-laget rent (member_evidence backstoppet af eksisterende
EXCLUDE). App-laget: én MEDIUM (discovery-flade slugte fejl) + import-dedup-hærdning.

## Fund + resolution

### B1 [HIGH→FIXED] — `red_slet_familie_link` efterlod forældreløst afklaret slot
**Lokation:** schema.sql:1173 / db-migrations.sql (review-30-blok)
**Symptom:** Efter backfill har hver person et afklaret slot. Sletning af en 'barn'-række (via
`sletFamilieLink` — som §6 trin 3c bruger til at fjerne alias-personens rå barn-række) efterlod slottets
afklarede conclusion pegende på en familie personen ikke længere optog → global P1-drift-assert fyrer.
**Reproduktion:** `red_slet_familie_link(barn)` → 1 forældreløst afklaret slot (bekræftet mod daa_test2).
**Fix:** `red_slet_familie_link(rolle='barn')` retrakterer slottet (status='tilbagetrukket') NÅR det
afklarede slot peger på DEN fjernede familie. Betingelsen sikrer at `red_flyt_barns` interne slet
(slot peger på til efter re-peg) ikke rører den. **Verificeret:** 0 forældreløse, 1 retrakteret.

### B2 [HIGH→FIXED] — `red_tilfoej_barn` (nyt barn) lavede slotløs barn-række
**Lokation:** schema.sql:1186 / db-migrations.sql (review-30-blok)
**Symptom:** Tilføjelse af et genuint nyt barn (`tilfoejBarn`-app-art) gav en barn-række uden
forældrefamilie-slot → going-forward-invarianten "enhver 'barn'-række har et evidens-spor" (§5) brudt;
backfill-komplethed-assert fyrer.
**Reproduktion:** `red_tilfoej_barn` på ny person → 1 slotløs barn-række (bekræftet).
**Fix:** `red_tilfoej_barn(rolle='barn')` find-or-creater slottet via ny delt helper
`_ensure_foraeldrefamilie_redaktionel` NÅR personen ikke allerede har et slot (no-op fra
red_flyt_barn/red_vaelg_foraeldre, der håndterer slottet selv). **Verificeret:** 0 slotløse.

**Delt fix:** `_ensure_foraeldrefamilie_redaktionel(barn, family)` — idempotent find-or-create af
slot + redaktionel assertion + afklaret conclusion. `red_flyt_barn` bruger den nu til slot-vedligehold
(re-etablér til til-familien MEDMINDRE slottet allerede peger dertil → bevarer red_vaelg's valgte
source-bundne assertion; håndterer også retraktion fra intern slet + omstridt slot — lukker DB-L1).

### App-MEDIUM [FIXED] — `fetchForaeldreKonflikter` slugte query-fejl → falsk "alt rent"
**Lokation:** web+mobil redaktionRead.ts (fetchForaeldreKonflikter)
**Symptom:** `const { data } = ...` uden fejl-tjek → brudt view/RLS/migration returnerer `[]` →
dashboardet påstår "Ingen forældre-konflikter". Dette er discovery-fladen for hele featuren.
**Fix:** `if (error) throw error` (spejler søster-`fetchKonflikter`s throw-on-error-mønster).

### App [FIXED] — import-dedup fejlede-åbent + nullable-udgave-skrøbelighed
**Lokation:** web Redaktion.tsx (importable) / mobil ForaeldrePaastandePanel.tsx
**Symptom:** (a) når `egen==null` (person uden barn-familie) → `egen?.udgave===undefined` og
`r.fam.udgave` er aldrig undefined → within-udgave-dedup deaktiveret → spuriøs same-udgave-import
mulig. (b) `udgave`-sammenligning er en nullable streng; to source-løse familier `null!==null=false`.
**Fix:** Gate import på at `egen` findes (ellers kan tværudgave ikke verificeres → intet tilbydes);
sammenlign på numerisk `sourceId` frem for nullable `udgave`. Plus: `fetchBarnFamilie.udgave` fik
titel-fallback (display-konsistens m. buildForaeldreSlot); slot-citation-query fik `.order('id')`
(stabil proveniens, first-wins var nondeterministisk).

## Bevidst IKKE fikset (dokumenteret)

- **DB-L2:** idempotens sluger en 2. citation fra SAMME kilde+familie (spec §4.5 by design). Accepteret.
- **DB-L3 / backfill mis-cite:** STRICT-kildeopslag fanger IKKE en multi-edition base (fail-open mod
  operatør-fejl). Dokumenteret i migrations-kommentar + [[flere-daa-udgaver-korpus]]-fixture-fælde;
  prod er single-edition. **Anbefaling holdt:** kør backfill KUN mod verificeret single-edition-base.
- **R-LOW:** loaderne fejler kryptisk (rå "column does not exist") mod umigreret base, men ruller rent
  tilbage (ingen korruption). SKILL.md dokumenterer migrations-kravet. Ikke blokerende.
- **Web 700ms-refetch (App-LOW):** racy + redundant, men spejler eksisterende ForaeldreUkendtControl-
  konvention; self-correcting via parent-loadPerson-refetch. Beholdt (repo-konvention).

## Verifikation

- **Empirisk reproduktion** af B1+B2 FØR fix (mod daa_test2) og bekræftet 0 EFTER fix.
- **Ny db-verify-fixture** "mutator-slot-vedligehold": B2 tilføj→opret, flyt→følg, B1 slet→retrakter.
- **Regression:** alle Problem 2 db-verify-blokke grønne (forældre-konflikt, undo, mutator, backfill-skip);
  red_flyt_barn-redesignet bryder ikke vælg+flyt+P1 eller undo.
- **App:** web tsc rent + data 76/76; mobil tsc 0 + jest 190/190; blast-radius (public read-path) uændret.
- **schema.sql↔db-migrations.sql:** de 4 hånd-editerede funktioner parser rent (ekstraheret + anvendt).

## Codex adversarial-review (Phase 3+4)

Kørt (job review-mrnw7lw6, Codex-session 019f6c5e). Verdict: needs-attention. Codex fandt reelle
huller Claude-siden missede — reconcile per empirical-reproduction-rule (hver claim reproduceret/verificeret):

- **[HIGH] B2 delete→re-add — VERIFIED (empirisk reproduceret) → FIXED.** Efter B1 retrakterer slottet,
  kaldte re-add'ens `red_tilfoej_barn` kun helper når *fact* manglede — det retrakterede fact fandtes →
  slot forblev 'tilbagetrukket' → slotløs completeness-brud. **Repro:** delete→re-add gav status=tilbagetrukket,
  1 slotløs. **Fix:** guarden tjekker nu "ingen AFKLARET conclusion mod p_family" (dækker intet slot,
  retrakteret slot, forkert-pegende slot; no-op når red_vaelg/red_flyt allerede pegede rigtigt). Ny fixture-gren.
- **[MEDIUM] Dashboard-fejlmaskering — VERIFIED → FIXED.** Mit throw-fix var besejret: kalderne
  (`.catch(()=>setRows([]))`) konverterede fejlen tilbage til [] → "ingen konflikter". **Fix:** separat
  fejl-state + blokerende fejlbesked i web ForaeldreKonflikterListe + mobil foraeldre-konflikter-skærm.
- **[MEDIUM] Import-dedup ukendt proveniens — VERIFIED → FIXED.** `sourceId !==` når én er null →
  `null!==tal`=true → tilbudt. **Fix:** kræv BEGGE sourceId non-null før sammenligning (web+mobil).
  Dybere fix (afled rival-kilde fra slot-citation frem for personens 1. external_id) holdt som noteret opfølgning.
- **[MEDIUM] Helper LIMIT 1 kaprede source-bunden assertion — VERIFIED → FIXED.** Ved re-etablering m.
  flere destinations-assertions kunne helperen vælge en vilkårlig (evt. source-bunden rival) som konklusion.
  **Fix:** helperen matcher nu KUN en source-LØS (redaktionel) assertion (`NOT EXISTS citation m. source_id`),
  ordnet; kaprer aldrig en source-bunden påstand. **Repro:** valgt-citation-source=NULL efter re-etablering.
- **[MEDIUM] Helper max(id)+1 concurrency — INHERITED, ikke fikset.** Codebase-bred accepteret single-writer-
  PoC-begrænsning (alle red_*-funktioner + spec §3 ID-allokering); ikke en review-30-regression. Migration til
  sequences er et separat codebase-bredt spor. ON CONFLICT (target_type,target_id) er korrekt for conclusion.

**Verifikation efter Codex-fix:** delete→re-add → afklaret + source-løs valgt; alle Problem 2 db-verify-blokke
grønne (vælg+flyt+P1 bevarer a2 uændret); web tsc rent + data 76/76; mobil tsc 0 + jest 190/190.

## Fase 4-prep fable-review (2026-07-16)

To fable-agenter reviewede Fase 4-forberedelsen (prod-parathed). Begge "IKKE-KLAR" med reelle fund:

- **[HIGH sikkerhed] `_ensure_foraeldrefamilie_redaktionel` var en åben anon-skrivevej — FIXED.**
  SECURITY DEFINER UDEN `current_rolle()`-guard; Supabases default-grants ville eksponere den via
  PostgREST → anon kunne re-pege et barns afklarede slot til vilkårlig familie (forfalsket evidens,
  ulogget). **Fix:** `current_rolle()='redaktion'`-guard i helperen (gratis — kalderne er allerede
  redaktion). Verificeret: intern kald OK, direkte non-redaktion afvist.
- **[runbook] Rollback var brudt (forkert pg_restore-syntaks + ufuldstændig `--clean`) — FIXED.** Nyt
  `db-rollback-foraeldrefamilie.sql` (kirurgisk down-script: sletter data, reverterer de 3 objekt-
  refererende funktioner til pre-Problem-2 fra git, dropper additions). Rehearset: alt væk, funktioner revertet.
- **[runbook] Trin 3-forventning umulig på prod (rolle-gatede verify-blokke SPRINGER OVER pga.
  auth.users-FK) — FIXED** (runbook nedjusteret til ugatede asserts; fixture-blokke bevises i GATE 0).
- **Runbook-hærdning:** session-pooler-krav, obligatorisk test-restore + rollback-øvelse (GATE 0),
  skrive-frys (max(id)+1-race), `--single-transaction`, `LC_ALL=C` (dansk `FEJL:` vs `ERROR:`-grep-fælde),
  GDPR (chmod/kryptér/slet-frist, PGPASSWORD), multi-edition-abortens external_id-falsk-negativ (precheck e),
  loader-`~/.Renviron`-note, post-cutover-doc, free-tier-varme.
- **RLS verificeret OK** (fable): slot-fact person-gatet, konflikt-view security_invoker → ingen anon-lækage.
