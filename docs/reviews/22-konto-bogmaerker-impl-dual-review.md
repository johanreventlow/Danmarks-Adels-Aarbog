# Review 22 — Konto-bogmærker IMPLEMENTERING (dual-review: Claude + Codex)

**Dato:** 2026-07-06
**Genstand:** diff `c38d54c..HEAD` (14 filer, ~380 linjer ekskl. package-lock) på branch
`feat/bogmaerker-konto` — den faktiske KODE, ikke spec'en (spec dual-reviewet i review 21).

---

## Phase 1 — Claude (via code-analyzer-agent) egne fund, verificeret empirisk

### H1 [HIGH] — mobil `count` er ikke session-gated (badge viser stale tal efter logout)
**Lokation:** `mobile/src/lib/bookmarks.ts:104`
**Symptom:** `ids` er korrekt session-gated (`session ? new Set(idsList) : new Set()`,
linje ~81), men `count: idsList.length` bruger den RÅ, aldrig-ryddede `idsList` direkte.
**Verifikation:**
```ts
const ids = useMemo(() => (session ? new Set(idsList) : new Set<string>()), [session, idsList]);
...
return { ids, has, canSave: session != null, toggle, count: idsList.length };
```
`mobile/src/app/(tabs)/index.tsx:103`: `savedCount={count}` viser derfor det GAMLE antal
bogmærker efter log-ud, selvom `has()`/`ids` korrekt går tomme.
**Konsekvens:** synlig UI-inkonsistens (badge ≠ faktisk tilstand) + kontrakt-afvigelse fra web
(web's hook har slet ikke et `count`-felt).
**Foreslået fix:** `count: ids.size` (afledt af det allerede session-gatede `ids`).

### H2 [HIGH] — mobil har to uafhængige hook-instanser (Home vs. Bogmærker-skærm)
**Lokation:** `mobile/src/app/(tabs)/index.tsx:40` + `mobile/src/app/bogmaerker.tsx:20`
**Symptom:** hver skærm kalder `useBookmarks(session, canonMap)` selvstændigt — to separate
`idsList`/`pendingRef`-instanser. `mobile/src/app/_layout.tsx:50` viser `bogmaerker` som en
`Stack.Screen` OVENPÅ `(tabs)` (Home forbliver monteret nedenunder ved push).
**Verifikation:** web har KUN ét kald (`web/src/Folgesvend.tsx:141`), tråde ned via props —
ingen tilsvarende bug der.
**Konsekvens:** fjern et bogmærke på Bogmærker-skærmen → Home's gem-ikoner/badge opdaterer
IKKE før Home fuldt genmonteres (sker ikke ved almindelig stack-navigation).
**Foreslået fix:** løft bogmærke-state til den delte Zustand-store (som `session` allerede er),
eller del én hook-instans mellem skærmene.

### M1 [MEDIUM] — hurtig dobbelt-toggle af samme id kan race'e sig selv
**Lokation:** `web/src/data/bookmarks.ts:76-93`, `mobile/src/lib/bookmarks.ts:83-100`
**Symptom:** `toggle()` læser `ids.has(cid)` for `wasIn`, men tjekker IKKE `pendingRef` FØR den
sender et nyt kald. To hurtige tryk på samme id (før første netværkskald resolver) kan sende
`add()` derefter `remove()` (eller omvendt) samtidigt; ved out-of-order netværkssvar kan slut-
tilstanden i DB afvige fra sidst-viste UI-tilstand.
**Konsekvens:** kun ved reelt hurtigt dobbelt-tryk + netværks-reordering; `add()` er idempotent
(upsert ignoreDuplicates) så DEN retning maskerer det almindelige tilfælde.
**Foreslået fix:** i `toggle`, hvis `pendingRef.has(cid)` allerede: ignorér nyt tryk eller kø'
det til efter igangværende kald resolver (serialisér pr. id).

### L1 [LOW] — `list()`-fejl sluges tavst (ingen log/feedback)
**Lokation:** begge repositories, `list()`. Acceptabelt for PoC (bogmærker ikke-kritiske,
jf. spec), men umuligt at skelne "ingen bogmærker" fra "fejlede at hente".

---

## Phase 2 — Codex-trigger: JA
Begrundelse: empiriske claims (count bypasses gate, to hook-instanser), cross-platform-
kontrakt-spørgsmål (web/mobil skal have samme adfærd), severity styrer om et refactor
(delt store) er nødvendigt.

## Phase 3+4 — Codex adversarial-review + reconcile (2026-07-06)

**Verdict:** needs-attention → 7 af 8 fund rettet i denne pass; 1 (H2) bevidst udskudt.

### Mine egne fund (H1/H2/M1/L1) — Codex-bekræftelse
| ID | Codex-verdikt | Note |
|---|---|---|
| H1 | confirmed | `count: ids.size` er korrekt — `useMemo` kører synkront i samme render, ingen lag. |
| H2 | confirmed; mit forslag ufuldstændigt | Kun at flytte `idsList` til Zustand er ikke nok — repository-ejerskab, pending-generationer, fetch-livscyklus og rollback skal ALLE blive del af én store-koordinator. Ægte fix = ny bogmærke-slice, ikke en hurtig patch. |
| M1 | confirmed, mere alvorligt end beskrevet | React 19-batching løser IKKE nogen af de to racer (samme-snapshot ELLER krydsende renders); "add er idempotent" gør kun ADD-retningen selv-helende, ikke add/remove-krydsning. |
| L1 | confirmed | Ingen ændring — matcher spec's "ikke-kritisk". |

### Nye Codex-fund (verified empirisk i reconcile)
| ID | Sev | Fund | Status |
|---|---|---|---|
| **N1** | HIGH | Web: `session ? {userId} : null` bygger et NYT objekt-literal hver render → ustabil effekt-dependency → refetch på hver render (`Folgesvend.tsx:141`, `bookmarks.ts:72`). | ✅ Rettet — begge hooks tager nu `userId: string | null` (primitiv). |
| **N2** | HIGH (recalibreret til MEDIUM) | Ingen bruger-nøglet rydning af `idsList` ved brugerskift. Reconcile-verifikation: RLS scoper ALLE reelle skrivninger til `auth.uid()`, så et cross-account "write" er umuligt server-side (0-rows-affected, ikke data-korruption) — kun en misvisende UI-glimt. Yderligere: app'ens UI eksponerer ingen "skift konto uden log-ud"-flow, så scenariet er kun nået via hook-niveau, ikke gennem den faktiske app. | ✅ Mitigeret (ryd ved reelt brugerskift, sporet via ref) — ikke en fuld cross-account-hærdning, da den ikke er nået via UI. |
| **N3** | MEDIUM | Web: `doLogin` har intet `busy`-guard (dobbelt-klik → overlappende `signIn`); `currentSession()` har ingen rejection-handler. | ✅ Rettet. |
| **N4** | — | `repoRef`-staleness — undersøgt, afkræftet (Supabase-klienter er modul-konstanter). | Ingen ændring. |
| SQL | — | Ingen nye korrekthedsfejl i migrations/rls/verify. | Ingen ændring. |

### Selv-fanget regression under fix (empirisk, ikke antaget)
Min FØRSTE N2-mitigering (`setIdsList([])` ubetinget ved hver logget-ind effekt-kørsel)
genintroducerede PRÆCIS samme uendelig-render-loop-mønster som den allerede-hærdede
udlogget-gren beskytter imod — fanget af `npx vitest run` der hang/OOM'ede. Root cause:
en ny tom array-reference hver effekt-kørsel + en ustabil test-`canon`-reference (inline
arrow) fik effekten til at genkøre uendeligt. Rettet med `lastUserIdRef`: ryd KUN ved et
REELT brugerskift (sporet via ref), ikke ved hvert effekt-genkør.

### Impact-bucketing
- **Silent-corruption/UI-inkonsistens:** H1 (stale badge), N1 (unødig refetch-storm).
- **Race/edge-case:** M1 (rapid dobbelt-toggle).
- **Robusthed/proces:** N3 (login-dobbelt-klik-guard).
- **Arkitektur, bevidst udskudt:** H2 (delt bogmærke-state på tværs af mobil-skærme).

### H2 — bevidst udskudt (dokumenteret, ikke glemt)
Mobil har to uafhængige `useBookmarks`-instanser (`(tabs)/index.tsx` + `bogmaerker.tsx`) —
fjernelse af et bogmærke på Bogmærker-skærmen opdaterer ikke Home's badge/ikoner før
Home genmonteres (sker ikke ved almindelig stack-navigation). Web rammes IKKE (kun ét
kald, tråde via props). Codex' reconcile bekræftede at et ægte fix kræver en ny Zustand-
bogmærke-slice (delt `ids`/pending-koordination/repository-ejerskab), ikke en hurtig patch
— udskudt til en separat brainstorm/plan, jf. projektets konvention for ikke-trivielle
arkitektur-ændringer.

**Læring:** en "hurtig" mitigering af ét race-fund (N2) kan selv indføre et race — enhver
`setState` tilføjet i en effekt-krop skal tjekkes for reference-stabilitet (bail-safe
funktionel form ELLER en ref-sporet betingelse), ikke kun det oprindelige fund.

