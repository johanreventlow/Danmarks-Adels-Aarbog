# Review 08 — Opret-ny-entitet (person/gods/kilde/organisation)

**Dato:** 2026-06-30
**Branch:** feat/redaktion-opret-ny-entitet (1b38800..b497886)
**Reviewere:** Claude (per-task ×6 + opus whole-branch), Codex (spec + plan tidligere; nu impl-diff)
**Verdict (Claude):** READY-TO-MERGE med web-e2e-gate. Ingen Critical/Important. 3 Minor.

Feature: "Tilføj"-fanen (tidligere dead stub) opretter nu ny person/estate/source/organisation
via 4 komposite SECURITY DEFINER RPC'er gennem den eksisterende dry-run→live write-sti.

---

## Verificeret korrekt (Claude, empirisk)

- **GDPR privat=true i 3 lag (via UI):** RPC-default (`red_opret_person` `p_privat DEFAULT true`),
  UI-hardcode (`byg()` `privat: true`), buildRpcCall videresender. **Via shippet UI** er ny person
  aldrig anon-læsbar uanset `levende`-toggle. RLS verificeret live: `person.anon_read` =
  `levende=false AND COALESCE(privat,false)=false`. NB: en crafted/direkte redaktør-RPC med
  `privat=false` KAN omgå UI-hardcoden — se Codex-finding nedenfor (rolle-gated, ikke priv-escalation).
- **Prod-grants + signaturer:** alle 4 RPC'er `auth_exec=true` live; deployede signaturer = buildRpcCall char-for-char.
- **Create→navigate ende-til-ende:** `submitChange` live → `{result: bigint}`; `onApplied` kun ved
  `!dryRun`; `efterOpret` (OpretSheet.tsx:77-82) awaiter forced reload, gater nav på
  `redaktionStatus==='ready'`, `router.push` kun for person. Ingen sti hvor onApplied får non-id
  (kun 4 RETURNS-bigint-arter routes) eller push før reload.
- **Single-Modal:** `visible={visible && !pending}` + SkrivePreviewSheet som fragment-søskende (ikke nested) → iOS-sikkert.
- **Stale-vokab-fix:** `Tilbage → nulstil()` rydder alle felter → ingen forkert `slags`/`koen` ved type-skift.
- **NULL+whitespace-guard:** `nullif(btrim(x),'') IS NULL` i alle 4 RPC'er. id=max+1 (husstil). Atomisk (1 funktion = 1 txn).

---

## M1 [MEDIUM] — Reload-fejl efter vellykket write = tavs → dublet-risiko

**Lokation:** `mobile/src/components/redaktion/OpretSheet.tsx:79-82`
**Symptom:** Hvis live-write lykkes men efterfølgende `loadRedaktionModel(true)` fejler
(`redaktionStatus !== 'ready'`), returnerer `efterOpret` tavst uden at lukke. SkrivePreviewSheet
bliver i 'ok'-state med "Luk"-knap og INGEN besked om at refresh fejlede.
**Verifikation:**
```ts
await useStore.getState().loadRedaktionModel(true);
if (useStore.getState().redaktionStatus !== 'ready') return; // ← tavs; entiteten ER oprettet
```
**Konsekvens:** Entiteten er skrevet. Trykker brugeren Luk + opretter igen (ingen UNIQUE på navn/titel)
→ tavs dublet. Acceptabelt single-editor PoC, men en bruger-synlig besked bør lukke hullet.
**Foreslået fix:** På refresh-fejl-grenen: vis "oprettet, men listen kunne ikke opdateres — genindlæs"
i stedet for tavs `return`.

## M2 [LOW] — `router.push(... as never)` taber typed-route-guard

**Lokation:** `mobile/src/components/redaktion/OpretSheet.tsx:82`
**Symptom:** `as never`-cast omgår Expo Routers typed-route-tjek; en malformet sti fanges ikke ved compile.
**Konsekvens:** Kosmetisk; matcher escape-hatch-mønster brugt andre steder, men håndbygget sti mister sit eneste typed-værn.
**Foreslået fix:** Brug typed-route-form hvis Expo Router-versionen understøtter det; ellers behold (lav prioritet).

## M3 [LOW] — Happy-path DB-test PASS = fravær-af-exception

**Lokation:** plan Task 1 Step 7 (DO-blok via execute_sql)
**Symptom:** MCP-laget returnerer kun fejl-objekter; `RAISE NOTICE` sluges → testen kan ikke skelnes
fra en DO-blok der aldrig kørte (fx hvis SET LOCAL blev ignoreret).
**Konsekvens:** Lav risiko — den negative rolle-gate-test bekræfter JWT-maskineriet virker. Værd at
notere for fremtidige test-forfattere.
**Foreslået fix:** Ingen (dokumenteret). Evt. fremtid: assert mod en out-param/returneret række frem for NOTICE.

---

## Codex adversarial-review konsekvens (2026-06-30)

**Verdict: needs-attention** (1 verified footgun + M1; resten dokumenteret-accepteret).

**Bekræftet (verified empirisk i denne reconcile):**
- **M1** (MEDIUM, reload-fejl tavs) — Codex confirmed; reproduceret i `OpretSheet.tsx:79-82` + `useStore.ts:257`. → fixet.
- **M2** (LOW, `as never`) — confirmed; → fixet (typed-route).
- **GDPR-footgun [Codex High → recalibreret MEDIUM]:** **Empirisk verificeret mod LIVE base:** RLS ER
  deployet (alle 6 evidens-tabeller `relrowsecurity=true`, 3 policies hver); `person.anon_read`-qual =
  `(levende=false AND COALESCE(privat,false)=false)`. Så en afdød person med `privat=false` ER anon-læsbar.
  `buildRpcCall` videresender eksplicit `privat:false` (`redaktionWrite.ts`), og `red_opret_person`
  indsætter den. **MEN:** (a) RPC er rolle-gated → kun en redaktør kan kalde; (b) shippet UI hardcoder
  `privat:true` (`OpretSheet.tsx:55`) → normal brug aldrig eksponeret. Det er IKKE en
  privilege-escalation. Recalibreret fra High→Medium: ikke en live-exploit, men (1) doc 08's tidligere
  absolutte claim "aldrig anon-læsbar via NOGEN sti" var **empirisk falsk** (rettet ovenfor), og (2) en
  footgun mod design-intent (decisions.md: synlighed sættes bevidst via `red_set_privat` EFTER opret).
  **Hærdnings-anbefaling (kræver prod re-deploy → bruger-beslutning):** tving `privat=true` i
  `red_opret_person` (drop `p_privat`-param + `byg()`-felt) → opret kan aldrig eksponere; synlighed
  kun via `red_set_privat`. Codex' caveat "RLS måske ikke anvendt" = **FALSK** (verificeret deployet).

**Dokumenteret-accepteret (confirmed, ingen ny handling):**
- **id-race** (MEDIUM, Codex confirmed): ulåst `max(id)+1` i alle 4 allocators + person's fakta-id'er.
  Konsekvens = request fejler med duplicate-PK + **fuld rollback (ingen partiel oprettelse)**. Alle
  eksisterende write-RPC'er deler mønstret; spec §8 + plan dokumenterer det som accepteret single-editor
  PoC. Post-PoC: sequence/identity.
- **slags ingen CHECK** (LOW, confirmed): RPC validerer ikke `slags`; crafted/direkte kald kan persistere
  vilkårligt vokab. `koen` HAR CHECK. Accepteret PoC (UI-gated), dokumenteret i spec §8.

**Dismissed af Codex (ingen defekt):** named-notation-kald gyldig (positional før named, matcher
prod-signatur), trigger fyrer ved conclusion-INSERT, atomicitet (exceptions ruller hele txn tilbage),
boolean-omission (`!= null` bevarer `false`), dry-run gater navigation.

**Impact-buckets (Codex verified-saves):**
- Silent-corruption-risk: M1 (tavs dublet ved reload-fejl) — fixet.
- Process/design-guard: GDPR-footgun (doc-claim + hærdnings-anbefaling).
- Cleanup: M2 typed-route — fixet.
- Dokumenteret-accepteret (ekskl. fra ROI): id-race, vokab.

**Læring:** absolutte sikkerheds-claims ("aldrig via NOGEN sti") i review-docs SKAL verificeres mod den
LEVENDE RLS-tilstand, ikke kun mod UI-laget — UI-hardcode beskytter ikke direkte RPC/crafted-Change-stier.
