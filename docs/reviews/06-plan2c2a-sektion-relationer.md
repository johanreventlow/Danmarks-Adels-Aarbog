# Cycle 06 — Plan 2C-2a sektion-relationer (rediger hverv/godser)

**Dato:** 2026-06-29
**Scope:** `efb4d3e..95f6cfe` (2C-2a, 8 commits: 6 tasks + controller-gate + merge). DB-RPC'er
(red_slet_relation/red_tilfoej_relation), fetchPersonRelationer/mapRelationRow, buildRpcCall-cases,
EntitetPicker, redigerbar editor-sektion.
**Reviewers:** Claude (code-analyzer Phase 1) + Codex (Phase 3, adversarial) — afventer.

## Sammenfatning

| ID | Severity | Status (efter Codex-reconcile) |
|----|----------|--------|
| H1 grant-omission i db-migrations.sql | — | ❌ DISMISSED (PUBLIC-default execute, verificeret) |
| M1 p_rolle '' vs NULL | — | ❌ DISMISSED (rolle NOT NULL → mit fix ville crashe inserts) |
| NEW1 historical_event sletbar i editor | MEDIUM | ✅ Confirmed (Codex-fund) → rettet |
| NEW2 red_tilfoej_relation validerer ej person-subjekt | MEDIUM | ✅ Confirmed (Codex-fund) → rettet |

Final whole-branch review (opus) dækkede tværgående risici (GDPR/RLS, FK-order, write-path, type-kontrakt,
stale-cache) — alle PASS. Denne cycle = kode-niveau-fund den ikke gravede i. **Codex flippede begge mine
draft-fund til dismissed (M1-fixet var runtime-breaking) OG fandt 2 ægte MEDIUM-bugs jeg missede.**

---

## H1 [MEDIUM] — `db-migrations.sql`: manglende GRANT på de 2 nye RPC'er

**Lokation:** `db-migrations.sql` (2C-2a-blok, filens slutning) — ingen GRANT efter `red_slet_relation` /
`red_tilfoej_relation`.

**Symptom:** `db-migrations.sql` er dokumenteret (CLAUDE.md §5) som "kør for at afstemme en allerede
deployet base". De forrige inkrementelt-tilføjede RPC'er bærer eksplicit grant lige efter deres definition:

```sql
-- db-migrations.sql:526-527
grant execute on function public.red_tilfoej_oplysning(bigint,text,date,date,text,text,text) to authenticated;
grant execute on function public.red_opret_fakta(text,bigint,text,text,date,date,text,text,text) to authenticated;
```

2C-2a-blokken slutter derimod på `END $$;` uden grant. Grant-loopet der dækker by-prefix
(`proname like 'red\_%'`) bor KUN i `db-rls.sql:247` — en separat fil der ikke køres af en
db-migrations-reconcile.

**Verifikation (reproduceret via grep):** `grep "grant execute on function" db-migrations.sql` → kun de
2 linjer (526-527); `grep "proname like 'red" schema.sql db-migrations.sql db-rls.sql` → kun
`db-rls.sql:247`. schema.sql har NUL eksplicitte grants (fresh deploy = schema.sql + db-rls.sql-loop,
dækker de nye by-prefix — derfor prod-deployen virkede, jeg re-kørte loopet).

**Konsekvens:** En fremtidig reconcile-replay af `db-migrations.sql` mod en allerede-deployet base (uden
at re-køre db-rls.sql) opretter de 2 RPC'er men grant'er dem ikke → app-kald får Supabase
permission-denied (ikke den forventede rolle-gate-exception). Silent breakage på næste reconcile.
MEDIUM (rammer ikke nuværende prod — loopet blev kørt i controller-gaten).

**Foreslået fix (recalibreret fra analyzer):** Tilføj grants KUN i `db-migrations.sql` efter 2C-2a-blokken,
matchende 526-527-mønsteret. IKKE i schema.sql (bærer aldrig grants — konventionsbrud):
```sql
grant execute on function public.red_slet_relation(bigint) to authenticated;
grant execute on function public.red_tilfoej_relation(bigint,text,bigint,text,text) to authenticated;
```

---

## M1 [LOW] — `p_rolle` gemmes som '' (ikke NULL) ved nye redaktør-rækker

**Lokation:** `mobile/src/data/redaktionWrite.ts` (tilfoejRelation-case, `p_rolle: p.rolle`);
`mobile/src/app/redaktion/person/[id].tsx` (RelTilfoejSheet, rolle-state init `''`).

**Symptom:** Lader redaktøren rolle-feltet stå tomt, sendes `p_rolle: ''` → INSERT gemmer `rolle=''`
(tom streng), hvor historisk-loadede rækker kan have `rolle IS NULL`. `mapRelationRow` normaliserer
begge til `''` (`r.rolle ?? ''`), og dup-guarden er NULL-safe (`coalesce(rolle,'')=coalesce(p_rolle,'')`),
så ingen funktionel bug.

**Verifikation:** `periodeRaw` sendes allerede som `periode || null` (samme case) — `rolle` er den
eneste der sendes rå. Asymmetrien er kosmetisk: DB får et `''`/`NULL`-split synligt kun i direkte
SQL eller fremtidig kode der skelner.

**Konsekvens:** Ingen nuværende funktionel effekt. LOW.

**Foreslået fix:** Send `p_rolle: p.rolle || null` (matcher periodeRaw-mønsteret, holder nye rækker
konsistente med NULL-konventionen). 1-linjes hygiejne.

---

## Verificeret sikkert (code-analyzer Phase 1)

- `red_slet_relation` citation-subquery scoped korrekt til DENNE relations assertions; slet-orden
  citation→conclusion→assertion→note→relation korrekt (ingen orphan/over-delete). (Bekræftet af
  controller-gate rollback-test: rel+ass+con+cit→0.)
- `max(id)+1` = projekt-bredt pre-eksisterende mønster (ikke nyt her); PoC single-writer-debt.
- Dup-guard NULL-håndtering korrekt (coalesce begge sider) — rollback-test: id1==id2, count=1.
- `mapRelationRow` aux-nøgler: orgNavn/godsNavn keyed på `String(id)` (buildAux), `String(objekt_id)`
  matcher — ingen type-mismatch (test redaktionRead.test.ts dækker round-trip).
- `fetchPersonRelationer` filter `in('objekt_type', [org,estate,historical_event])` tilsigtet; ingen
  tilfoej-sti kan lave historical_event (picker = kun org/estate, SQL validerer).
- `onApplied` re-fetcher BÅDE evidens og relationer → relationId altid frisk ved slet (ingen stale-delete).
- EntitetPicker: ingen conditional hooks, `key={x.id}` unik per type.
- Alle relation-writes via setPending→SkrivePreviewSheet (dry-run honoreret, ingen bypass).
- buildRpcCall arg-navne char-for-char = SQL-signaturer (tests dækker fuld arg-objekt).

**Afvist (non-finding):** `Number(p.objektId)`-NaN-guard — aux-id'er er altid `String(numerisk)` by
construction; DB afviser NaN alligevel. Over-engineering at guarde i TS.

**RETTELSE efter Codex (NEW1):** Påstanden "historical_event fetch/no-add asymmetri er sikker" var FORKERT
— jeg tjekkede kun ADD-stien, ikke SLET. Se NEW1.

---

## Codex adversarial-review konsekvens (2026-06-29)

**Verdict:** needs-attention. Codex flippede begge draft-fund + fandt 2 ægte bugs.

**H1 — DISMISSED (verificeret empirisk).** Codex: Postgres grant'er EXECUTE til PUBLIC by default;
grant ikke påkrævet. Reproduceret live (rollback-txn, `grant_test.R`): ny funktion UDEN eksplicit grant
→ `has_function_privilege('authenticated', fn, 'EXECUTE')` = TRUE; `proacl = {=X/postgres, ...,
authenticated=X/postgres, ...}` (`=X` = PUBLIC har EXECUTE, + Supabase-default for authenticated).
Min "reconcile-replay breaker" var falsk. De eksplicitte grants 526-527 er redundant konvention.
(`anon` får også EXECUTE, men SECURITY DEFINER + intern `current_rolle()`-gate blokerer — samme model
som alle red_*.) Bucket: **hard-runtime-save undgået** — havde jeg "fixet" H1 var det blot støj; ingen skade.

**M1 — DISMISSED (verificeret).** Codex: `relation.rolle` er `TEXT NOT NULL` (schema.sql:180), så mit
foreslåede `p_rolle || null` ville give NOT NULL-violation på blank rolle → **breaking insert-fix**.
Desuden findes ingen NULL-rolle-rækker (kolonnen tillader det ikke), så hele '/NULL-split-præmissen er moot.
`''` er korrekt/påkrævet. Bucket: **hard-runtime-crash undgået** (Codex stoppede et fix der ville
crashe alle blank-rolle-inserts i prod).

**NEW1 [MEDIUM] — CONFIRMED (verificeret).** `mobile/src/app/redaktion/person/[id].tsx:368,374`:
HVERV-sektionen filtrerer `art === 'hverv' || art === 'event'` og renderer slet-Pressable (374) for ALLE
— inkl. `historical_event`. Selvom picker/add-RPC ekskluderer events, kan eksisterende event-relationer
SLETTES (og via red_slet_relation deres evidens). Modsiger scope ("kun hverv/godser redigerbare").
Bucket: **semantic-drift / utilsigtet destruktiv kapabilitet.**
**Fix:** event-rækker rendres read-only (ingen slet-knap); kun `art === 'hverv'` får slet. Bevarer
2B-paritet (events var synlige read-only under HVERV) + respekterer scope.

**NEW2 [MEDIUM] — CONFIRMED (verificeret).** `schema.sql:603-617` / `db-migrations.sql`:
`red_tilfoej_relation` validerer objekt (org/estate EXISTS) men IKKE at `p_subjekt_id` (person) findes.
relation er polymorf uden person-FK → et direkte authenticated-redaktion-RPC-kald (eller race med
person-sletning) kan indsætte en dinglende relation hvis subjekt-person ikke findes. Asymmetrisk med
objekt-valideringen. Bucket: **false-confidence / integritets-guard** (lav reachability — UI sender
kun gyldige person-id'er — men inkonsistent guard).
**Fix:** `IF NOT EXISTS(SELECT 1 FROM person WHERE id=p_subjekt_id) THEN RAISE EXCEPTION ...` før
dup-lookup; spejl i db-migrations.sql; rollback-test.

**Codex impact (verified, bucket-distinglueret):**
- Hard-runtime-crash undgået: **1** (M1-fix var NOT NULL-breaking — Codex stoppede det).
- Semantic-drift/destruktiv kapabilitet: **1** (NEW1 event-slet).
- False-confidence/integritets-guard: **1** (NEW2 person-eksistens).
- Dismissed støj: **1** (H1, ingen skade undgået, men sparede redundant grant-edit).

**Læring:** (1) Asymmetri-fund kræver tjek af BEGGE retninger (jeg verificerede ADD-validering men glemte
at SLET-kapabiliteten følger med fetch-filteret → NEW1). (2) "Tilføj manglende GRANT" er ofte støj på
Supabase/Postgres pga. PUBLIC-default — verificér `has_function_privilege` FØR man kalder grant-omission
en bug. (3) Et NOT NULL-felt gør en '/NULL-normaliserings-"hygiejne" til en breaking change — tjek
kolonne-constraint før man foreslår NULL.
