# Cycle 04 — Plan 2B editor-dybde (separat redaktion-model)

**Dato:** 2026-06-28
**Scope:** `7f2005e..d9811b1` (plan 2B-implementering, 8 commits: 5 tasks + 2 fixes + docs).
**Reviewers:** Claude (code-analyzer Phase 1) + Codex (Phase 3, adversarial).
**Note:** Codex reviewede 2B-SPEC'en (skiftede arkitektur → separat model); denne cycle reviewer
den implementerede KODE.

## Sammenfatning

| ID | Severity | Status | Commit |
|----|----------|--------|--------|
| NEW1 narrativ destruktiv overskrivning | HIGH | ✅ Implementeret | 33ec6f7 |
| NEW2 multi-narrativ-tvetydighed | HIGH→latent | ⏸ DEFER (0 live: 0 multi, 0 privat) | — |
| M2-stale-privat efter write | MED→moot | ⏸ DEFER (privat=0 i basen) | — |
| H1 bioBy/includePrivat | MED→latent | ⏸ DEFER (ingen UI læser redaktionModel.bio) | — |
| M2-IIFE PersonRad / M3 køn-flicker / M1 hydrate | LOW | ❌ dismissed/cleanup | — |

**Codex impact (verified):** 1 destruktiv/silent-corruption save (NEW1). Resten latent/moot (dokumenteret defer).
**Læring:** swallowed fetch-error i en EDITOR-prefill → destruktiv overskrivning; prefill-fejl SKAL
blokere skrive-knappen, ikke bare vise tomt (generaliserer cycle 03 NEW1 til skrive-stier).

---

## H1 [MEDIUM] — `bioBy` filtrerer private narrativer selv ved `includePrivat=true`

**Lokation:** `mobile/src/data/load.ts:117-119`

**Symptom:** `bioBy` (kilden til `AppPerson.bio`) bygges UBETINGET med `if (!n.privat …)`,
uafhængigt af `opts.includePrivat`. Når `loadFromSupabase({includePrivat:true})` loader
redaktion-modellen, får en person hvis ENESTE narrativ er privat `bio: ''` — selvom redaktion
har ret til at se den.

**Verifikation:**
```ts
const bioBy: Record<string, string> = {};
(narratives || []).forEach((n) => {
  if (!n.privat && !bioBy[String(n.subjekt_id)]) bioBy[String(n.subjekt_id)] = n.tekst ?? '';
});
```

**Konsekvens:** Latent nu (editorens narrativ-felt prefilles fra `fetchPersonNarrativ`, ikke fra
`redaktionModel.bio`; INGEN UI læser pt. `redaktionModel.bio`). Men inkonsistent med
`includePrivat`-intentionen, og rammer når 2C/senere viser `redaktionModel.bio`. Lav live-impact,
men ægte konsistens-bug.

**Foreslået fix:** `mapAppPersons` modtager allerede `includePrivat`; relaxér bio-filteret tilsvarende:
```ts
// i loadFromSupabase, hvor bioBy bygges:
if ((opts?.includePrivat || !n.privat) && !bioBy[String(n.subjekt_id)])
  bioBy[String(n.subjekt_id)] = n.tekst ?? '';
```

---

## M1 [LOW] — `loadRedaktionModel` trigges kun fra `_layout`-mount, ikke fra `hydrateAuth`

**Lokation:** `mobile/src/app/redaktion/_layout.tsx:11-13`

**Symptom:** Trigger-effekten loader redaktion-modellen når `rolle` bliver `redaktion` MENS
`redaktion/_layout` er monteret. Ved cold-start hvor `hydrateAuth` genskaber en redaktion-session
FØR brugeren er på en `/redaktion/*`-rute, sker load'et først når layoutet monteres. I normal
navigation fanger dependency-array'et (`[rolle, redaktionStatus, …]`) rolle-skiftet korrekt.

**Konsekvens:** Lav — kun edge-case (deep-link cold-start). Ingen bekræftet bug i normal flow;
skrøbelig kobling mellem rolle-hydrering og layout-mount-orden.

**Foreslået fix (robusthed):** trig `loadRedaktionModel` fra `hydrateAuth` i `useStore.ts` når
`rolle==='redaktion'`, så load er uafhængigt af layout-mount-timing.

---

## M2 [LOW] — `PersonRad` defineret inde i render-IIFE

**Lokation:** `mobile/src/app/redaktion/person/[id].tsx` (familie/sektion-IIFE)

**Symptom:** `PersonRad` genskabes hver render → React behandler den som ny komponent-type →
unmount/remount af hele familie/sektion-listen ved enhver state-ændring (fx pr. tastetryk i
narrativ-feltet via `ev`/`privat`-opdateringer).

**Konsekvens:** Lav (perf/UX-flicker, ingen data-impact). Også flaget i 2B final review (M2).

**Foreslået fix:** hejs `PersonRad` til modul-scope (med props for `router.push`/navn).

---

## M3 [LOW, dismissed] — køn-segment viser kortvarigt 'ukendt' før `ev` loader

**Lokation:** `person/[id].tsx` (køn-pille `aktiv`)

`const aktiv = (ev?.koen ?? 'ukendt') === k;` — `ev` er null på første render → 'ukendt'
highlightes kortvarigt, selv-korrigerer når evidens loader. Kosmetisk; skrive-stien er upåvirket
(tryk laver pending uanset). **Ikke værd at fixe.**

---

## Codex adversarial-review konsekvens (2026-06-28)

**Verdict:** needs-attention (no-ship indtil NEW1 rettet)

**Bekræftet (verified — direkte source-evidens + data-kalibrering):**
- **NEW1 [HIGH]** — `person/[id].tsx:49-54`: narrativ-prefill-effekten `.catch(() => {})` sluger
  fejl fra `fetchPersonNarrativ` (som KASTER ved RLS/netværks-fejl). → `narrativTekst` forbliver
  '' → UI skelner ikke "intet narrativ" fra "fetch fejlede" → tryk på **Gem** kalder
  `red_upsert_narrativ` med tom tekst og **overskriver den eksisterende narrativ destruktivt**.
  Rammer alle **597** eksisterende narrativer. Samme klasse som cycle 03 NEW1, nu DESTRUKTIV.
- **NEW2 [HIGH → DEFER (latent)]** — `redaktionRead.ts` + `red_upsert_narrativ` vælger begge
  laveste id uanset privat. Ved flere narrativer (privat id=5 + offentlig id=8) redigeres id=5,
  den offentlige bio forbliver urørt; editoren viser ikke hvilket. **Data-kalibrering: 0 personer
  har >1 narrativ, 0 private narrativer** → ikke live. Kræver kardinalitets-beslutning
  (UNIQUE(subjekt) ELLER vis-alle + mål-id-RPC) → udskudt til fokuseret fix/2C. Dokumenteret.
- **M2-stale-privat [MEDIUM → DEFER (moot)]** — `onApplied` re-henter kun evidens, ikke
  `redaktionModel`; efter `red_set_privat` LIVE er `redaktionModel.byId[id].privat` stale →
  toggle re-initialiseres forkert ved genåbning. **privat=0 i basen nu** → currently usynlig.
  Mekanismen er reel; kræver model-invalidering efter writes → udskudt (overlapper bredere
  "invalidér redaktionModel efter write"-behov).

**Recalibreret/dismissed:**
- **H1 (bioBy/includePrivat)** recalibrated → latent (ingen UI læser `redaktionModel.bio`;
  `load()` uden opts lækker ikke). Lav prioritet; fix bør parres med NEW2's kardinalitets-valg. DEFER.
- **M1 (hydrateAuth-trigger)** DISMISSED — `hydrateAuth` sætter rolle; den monterede layout-effekt
  reagerer på rolle-skift (dependency-array). loadRedaktionModel trigges korrekt.
- **M2-IIFE (PersonRad)** confirmed men lav (ikke ship-blocking) → DEFER cleanup.
- **M3** dismissed (kosmetisk). **Køn** confirmed korrekt (schema person_koen_chk = mand/kvinde/ukendt).

**Impact-buckets (kun verified+fixet):**
- Silent-corruption/destruktiv: **1** (NEW1 — Gem overskriver narrativ efter slugt fetch-fejl). FIXES.
- Deferred (latent/moot, dokumenteret): NEW2 (0 live), M2-stale (privat=0), H1, PersonRad-cleanup.

**Læring:** swallowed fetch-error i en EDITOR-prefill er værre end i en read-visning — det
muliggør destruktiv overskrivning. Prefill-fejl SKAL blokere skrive-knappen (ikke bare vise tomt).
Generaliserer cycle 03 NEW1 ("tom-som-clean") til skrive-stier.

---

## Verificeret sikkert (code-analyzer Phase 1)

- **GDPR-model-isolering:** `redaktionModel`/`redaktionAux` fuldt adskilt slice; publikums-skærme
  læser kun `s.model`; editoren kun `redaktionModel`. Ingen krydskontaminering.
- **doSignOut-reset (final-review M1):** KOMPLET — nulstiller session/rolle/reventlowPersonId +
  redaktionModel/redaktionAux/redaktionStatus='idle'. Ingen privat-data efter logout.
- **Double-load-guard:** `loading || ready`-tjek før `set('loading')`, synkront `get()` før await.
- **Narrativ-alignment:** `fetchPersonNarrativ` (`order id asc limit 1`) == `red_upsert_narrativ`-mål;
  privat bevaret på Gem (`payload.privat`→`Boolean(c.payload?.privat)`).
- **mapAppPersons-filter:** `includePrivat || !privat`; default false; publikums-load uændret.
- **Køn-write:** mand/kvinde/ukendt → buildRpcCall fakta+koen → red_set_koen.
- **Familie/sektion-selektorer:** kaldt med `redaktionModel`/`redaktionAux` (ikke publikums-model).
