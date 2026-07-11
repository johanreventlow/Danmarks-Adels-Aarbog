# Review 27 — dual-review af review-26-rettelserne (generationsbrowser)

**Branch:** `feat/generations-browser-v2` · **Dato:** 2026-07-11 · **Scope:** rettelserne af Codex-review 26
(HIGH 2 + HIGH 1). Den bredere feature blev reviewet i brief 26; her reviewes KUN rettelserne.

**Changeset:** 17 filer, +131/−31. Kerne-logik: `red_tilbagetraek_fakta` (schema.sql + db-migrations.sql),
`tilbagetraekFakta`-art + `factId` i markerings-fetch (web+mobil write-path), ordlyd (tree.ts/selectors.ts +
render). **Verifikationsniveau (efter cyklussens egne fixes):** tsc rent (web+mobil), web 243/243, mobil 332/332,
lokal DB-rollback-test af RPC'en mod prod-kopien (`daa_test2`, rullet tilbage, inkl. guard-assertion).
`red_tilbagetraek_fakta` var prod-live 2026-07-11 (uden guard) — den guardede version **kræver re-apply**.

---

## Phase 1 — Claude-review (code-analyzer bug-hunt)

**Resultat: 0 reelle bugs.** Fuld retract-livscyklus tracet på tværs af begge platforme:

- **H2-fix korrekt (verified):** `red_upsert_fakta` håndhæver ét fact pr. `(subjekt,faktatype)` (find-or-create)
  + én konklusion pr. fact via `ON CONFLICT (target_type,target_id)`. Markér→Opdatér muterer SAMME konklusion
  (status forbliver 'afklaret'). `red_tilbagetraek_fakta` flipper den ene række til 'tilbagetrukket' → 0 afklarede
  tilbage. Ingen sti efterlader den hængende 'afklaret'.
- **Re-Markér reaktiverer (verified):** konklusionsrækken består efter retract; frisk Markér rammer
  `ON CONFLICT DO UPDATE ... status='afklaret'` med en ny påstand → projicerer igen. Round-trip bekræftet.
- **`fetchForaeldreUkendtMarkering` kan ikke returnere stale/forkert markering (verified):** fact-query scoped
  `.eq('faktatype','forældre_ukendt')` → ≤1 fact-id; konklusion gated `.eq('status','afklaret')` → efter retract
  null → Fjern-knap forsvinder. `factId = target_id` (NOT NULL PK-komponent) → kan aldrig fejl-resolve til andet fact.
- **Guard `aid == null || fid == null` korrekt (verified):** `Number("0")`/`Number("")` → 0 (ikke NaN/null); et
  ikke-eksisterende fact-id 0 matcher 0 rækker i UPDATE (harmløst no-op). Ikke reachable i praksis (id'er ≥1).
- **Gammel `sletOplysning` (per-oplysnings-🗑) urørt (verified):** kun forældre-ukendt-Fjern-knappen omruttet.
- **Web/mobil-paritet eksakt (verified):** `Change`-union, `ForaeldreUkendtMarkering`-type (m. factId),
  `buildRpcCall`-gren, og `childSectionNote`-strenge byte-identiske. Tests opdateret til nye strenge/RPC; ingen
  stale asserts tilbage.

**LOW-anbefalinger (ikke-blokerende):**
- L1: mobil `childSectionNote`-strengen (`selectors.ts:311`) har ingen unit-test; kun web (`tree.test.ts:387`)
  asserterer den. Spejl assertionen i en mobil-test for at låse paritet. (Ingen bug — ingen stale test findes.)
- L2: valgfri `Number.isFinite`-hærdning af `buildRpcCall`; pt. unreachable da `factId` altid stammer fra et
  numerisk DB-id.

---

## Phase 4 — Codex adversarial-review konsekvens (2026-07-11)

**Verdict: needs-attention** — retract-fixet er korrekt, men Codex hævede den rigtige robustheds- +
scoping-flanke som code-analyzer missede. Alle claims verificeret empirisk mod koden (ingen laundering).

**Bekræftet af Codex (verified):** re-Markér reaktiverer (ON CONFLICT); `sletOplysning` urørt;
web/mobil-paritet på de ændrede runtime-stier.

**Recalibreret (verified empirisk):**
1. **"Ét fact pr. (subjekt,faktatype)" er IKKE schema-håndhævet** — `fact` har kun `id`-PK
   (schema.sql:303, verificeret). Det er en konvention i `red_upsert_fakta`s find-or-create, ikke en
   unik constraint. I praksis ≤1 (alle markerings-writes går gennem `red_upsert_fakta`; `red_opret_fakta`
   kaldes aldrig med `forældre_ukendt`), men ikke garanteret.
2. **`fetchForaeldreUkendtMarkering` var ikke-deterministisk** — `.limit(1)` uden `order` (verificeret
   mod PU-loaderen `model.ts:194` som HAR `.order('id')`). **Rettet:** `.order('target_id')` tilføjet
   (begge platforme) → vælger deterministisk laveste fact-id.
3. **`Number('')===0`-hul i null-guard** — guarden afviste kun `null`. **Rettet:** afvis tom/blank
   eksplicit + `Number.isFinite` (begge platforme; test tilføjet).

**Fixet i denne cyklus (in-scope robusthed):**
- **MEDIUM — tomt change_set + falsk succes:** `red_tilbagetraek_fakta` tjekkede ikke om noget blev
  ramt. **Rettet:** fail-closed `IF NOT EXISTS(... afklaret ...) THEN RAISE` FØR `begin_change_set`
  (schema.sql + db-migrations.sql). Lokal rollback-test udvidet: dobbelt-retract rejser nu "Ingen aktiv
  markering" i stedet for stille-succes. **Kræver prod-re-apply.**
- **LOW — stale kommentar** i `Redaktion.tsx` (sagde `red_slet_oplysning (fjern)`) → rettet.

**Ny bug — SURFACE TIL BRUGER (pre-eksisterende, IKKE regression fra review-26):**
- **HIGH (a) — samme_som-collapse gør Fjern ufuldstændig.** Den offentlige projektion kanoniserer facts
  fra flere rå personer til én (samme_som-collapse; `buildParentsUnknown` "første vinder", generations.ts:47),
  MEN editor-fetch/markér/fjern arbejder på det rå `personId` (redaktionRead.ts:162; redaktøren collapser
  bevidst IKKE). Er to samme_som-linkede medlemmer BEGGE markeret, fjerner Fjern kun den ene; den anden
  projicerer stadig. **Verificeret pre-eksisterende:** markér (`red_upsert_fakta`), gammel fjern
  (`red_slet_oplysning`) OG ny fjern er ALLE rå-scoped — review-26 ændrede *hvordan* der fjernes, ikke
  *scope*. Dette er en eskalering af Codex' oprindelige review-26 MEDIUM 3 (multi-markering "første vinder").
  **Bruger-beslutning 2026-07-11: accepteret som PoC-grænse (backlog)** — se `docs/decisions.md`
  "Forældre ukendt … rå-scope vs. samme_som-kanonisk". Sjældent (kræver to samme_som-linkede personer
  BEGGE hånd-markeret); determinisme-fixet gør adfærden konsistent; kaskadér/konflikt-visning genbesøges
  hvis et reelt tilfælde dukker op.

**Bekræftet ikke-problemer (verified):** ingen manglende read-gate andre steder (de øvrige ugatede
conclusion-reads er generisk evidensvisning, ikke markerings-projektion); `red_fortryd_change_set` genskaber
`status='afklaret'` korrekt (schema.sql:1609/1623); `conclusion.status` er fri TEXT uden CHECK → 'tilbagetrukket'
afvises ikke. `begin_change_set`s `max(id)+1`-race er eksisterende PoC-infra (schema-kommenteret "acceptabelt,
én redaktør") — backlog, ikke denne cyklus.

**Impact-bucketing (verified saves fra Codex-passet):**
- Hard runtime-crash: 0
- Silent-corruption / semantic drift: 1 (samme_som Fjern-divergens — surfacet, pre-eksisterende)
- False-confidence / process-guard: 2 (tomt change_set falsk-succes; ikke-deterministisk fetch)
- Sub-optimal / cleanup: 2 (NaN-guard-hul; stale kommentar)

**Læring:** code-analyzer verificerede den lokale livscyklus korrekt men antog RPC-konventionen
(`≤1 fact`) som en schema-invariant — Codex fandt at konventionen ikke er håndhævet, og at editorens
rå-scope divergerer fra projektionens kanoniske scope. Ved review af collapse-baserede features: tjek
altid om skrive-/fjern-stien opererer på samme id-rum (rå vs. kanonisk) som læse-projektionen.
