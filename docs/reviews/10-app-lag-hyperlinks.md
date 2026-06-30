# Review 10 — Versionering + hyperlinks (App-lag, RN/Expo)

**Dato:** 2026-06-30
**Område:** `mobile/src/lib/mentions.ts`, `NarrativRenderer.tsx`, `MentionPicker.tsx`,
`redaktionRead.ts`/`redaktionWrite.ts` (historik/fortryd/døde-links-tilføjelser),
`SkrivePreviewSheet.tsx` (ny `onError`-prop), `historik/[id].tsx`, editor-/visnings-wiring.
**Reviewer:** Claude (draft) → Codex (adversarisk) → reconcile.
**Verifikation:** `tsc --noEmit` 0 fejl, jest 187/187 grøn (begge er det skarpeste automatiserede
signal her — komponenter/skærme er IKKE Expo-kørt, jf. plan §"Test-niveau").

---

## H1 [HIGH] — Label der ender på ueskaperet backslash bryder closing-tag-detektion

**Lokation:** `mobile/src/lib/mentions.ts` — scan-loopet i `parseNarrativ` (linje ~44) vs.
`makeToken`'s escape-sæt (linje ~60).

**Symptom:** `makeToken` escaper kun `|`, `[`, `]` — ikke `\` selv. Hvis en visningstekst ender
på en (ueskaperet) backslash umiddelbart før token-afslutningen, fortolker scan-loopets
backslash-gren `\]` som ÉT escaped-tegn-par og spiser begge tegn. Den resterende ene `]`
matcher aldrig `]]`-tjekket → `closed` forblir `false` → hele tokenet falder til rå tekst.

**Verifikation (empirisk reproduceret):**
```
makeToken('person', 1, 'X\\')  →  "[[person:1|X\]]"
parseNarrativ(...)             →  [{ kind: 'text', text: '[[person:1|X\\]]' }]
```
Linket bliver IKKE genkendt — hele token-syntaksen lækkes som synlig tekst i biografien.

**Konsekvens:** Stille indholds-korruption (ingen krasch, ingen fejl) for ethvert
brugerautoreret label der ender på backslash (fx en kopieret Windows-sti, eller blot et
afsluttende `\`). Ingen test dækkede dette — bekræftet gap, ikke en accepteret begrænsning.

**Foreslået fix:** Begræns scan-loopets backslash-gren til kun at behandle `\` som
escape-lead-in når næste tegn er ét af `|[]` (mirror `unescape()`'s tegnklasse):
```ts
if (after[i] === '\\' && /[|[\]]/.test(after[i + 1] ?? '')) {
  label += after.slice(i, i + 2); i += 2; continue;
}
```
En lone `\` (ikke følgt af `|[]`) falder dermed igennem til den almindelige
tegn-for-tegn-gren (`label += after[i]; i += 1`) og kan ikke længere "sluge" den
efterfølgende `]`.

---

## H2 [MEDIUM] — `reverteret`-feltet har omvendt semantik ift. historik-UI'ens brug

**Lokation:** `mobile/src/data/redaktionRead.ts` `mapHistRow` (`reverteret: r.reverterer_id != null`)
vs. `mobile/src/app/redaktion/historik/[id].tsx` (Fortryd-knap vises kun når `!post.reverteret`).

**Symptom:** `change_set.reverterer_id` på en række R betyder *"R fortrød hvilket sæt"* —
sat på det NYE reversal-sæt, peger tilbage på det ORIGINALE (verificeret: `schema.sql:931`
+ `red_fortryd_change_set`'s afvisnings-tjek `schema.sql:1092`,
`EXISTS (SELECT 1 FROM change_set WHERE reverterer_id=p_change_set_id)` — det ER
"er-allerede-fortrudt"-mønsteret, men brugt server-side på ID'et, ikke klient-side på rækken).

`mapHistRow` læser derfor det FORKERTE felt til UI'ens formål: den originale handling X's
`reverterer_id` forbliver `NULL` efter X er fortrudt (fortrydelsen satte feltet på det NYE
sæt Y, ikke på X) → `reverteret=false` for X for evigt → Fortryd-knappen forbliver synlig og
aktiv på en allerede-fortrudt post.

**Konsekvens:** Et andet tryk på Fortryd rammer DB'ens egen guard
(`'FEJL: change_set % er allerede fortrudt'`) — som IKKE matcher `handleError`'s
`/afvist.*force/i`-mønster → fejlen vises som rå, uoversat Postgres-tekst i stedet for at
blive forhindret (knappen burde være væk) eller vist på dansk. Desuden viser selve
revert-handlingen (Y) "Fortrudt" i UI'en — hvilket fejlagtigt antyder at Y selv blev
fortrudt, når Y faktisk ER fortrydelsen.

Ingen data-korruption (DB'en håndhæver invarianten korrekt server-side) — ren UX-forvirring.

**Foreslået fix:** Beregn revideret-status fra HELE listen `hist_for_subjekt` returnerer
(en post R er fortrudt hvis en ANDEN post i listen har `reverterer_id === R.id`), ikke fra
postens eget felt. Tilføj desuden et dansk fald-tilbage for "allerede fortrudt" i `oversaetFejl`.

---

## Stier vurderet KORREKTE (ikke fund)

- **Unicode/surrogate-par-håndtering** i `parseNarrativ`'s tegn-for-tegn-fallback: ren
  slice/concat uden længde-baserede antagelser → æøå/emoji round-tripper korrekt.
- **Ingen infinite-loop-risiko**: hver iteration gør mindst ét tegns fremskridt.
- **`MentionPicker`/`PersonPicker`-genbrug**: identisk pool-form til `searchPool`;
  `RedPerson.id` er altid `String(numericId)` → `Number(p.id)` i `makeToken` er sikkert.
- **`NarrativRenderer`-navigation**: dangling/dead person-links krascher ikke.
- **`SkrivePreviewSheet`'s nye `onError`-prop**: additiv, ingen ændring for de 2 eksisterende
  kaldere (`OpretSheet.tsx`, editoren); fyrer efter `setStatus('err')`, matcher doc-kommentar.
- **`historik/[id].tsx` pending/onError-interplay**: ingen reel race — `handleError` er en
  frisk closure pr. render over aktuel `pending`/`poster`.

---

## Codex adversarisk-review konsekvens (2026-06-30)

Verdict: needs-attention → **needs-fix** (begge oprindelige fund bekræftet, MIN H1-fix-recipe
var selv forkert; 1 nyt fund tilføjet — alle rettet + regressions-testet).

**Bekræftet (verificeret empirisk):**
- **H1** — confirmed, MEN min foreslåede fix (`/[|[\]]/`-narrowing i scanneren) løste IKKE
  problemet: `]` er legitimt i escape-klassen, så en ueskaperet trailing backslash stadig
  sluger afgrænserens første `]` uanset hvor smal regex'en er. Reproduceret med
  node-simulation af begge varianter (se under). **Korrekt fix (Codex's anbefaling, anvendt):**
  escape `\` selv i `makeToken` (encode-siden); scanneren forbliver UÆNDRET (dens originale
  ubegrænsede "backslash+næste-tegn=ét par"-logik er korrekt, NÅR encoderen garanterer at
  enhver literal backslash altid er doblet). 7 round-trip-cases verificeret (trailing `\`,
  `\|`, `\]`, dobbelt-backslash, blandet) — alle passerer efter fix.
- **H2** — confirmed. Listebaseret beregning (samle alle `reverterer_id`-værdier fra hele
  `hist_for_subjekt`-resultatet, derefter `revertedIds.has(r.id)` pr. række) er semantisk
  korrekt, som Codex bekræftede. `mapHistRow` udvidet med `revertedIds`-parameter (default
  tomt sæt, bagudkompatibel signatur). Tilføjet defensivt dansk fald-tilbage i `oversaetFejl`
  for "allerede fortrudt" (selvom korrekt klient-beregning burde forhindre at UI'en når dertil).

**Nyt fund (Codex, ikke i mit draft):**
- **M3 [MEDIUM]** — `MentionPicker` viste `.catch(() => {})` + tom liste som "Ingen.",
  umuliggørende at skelne en netværks-/auth-fejl fra reelt nul personer. Fixet: status-state
  (`loading`/`ready`/`error`) + oversat fejlbesked + "Prøv igen"-knap; "Ingen." vises kun efter
  et bekræftet succesfuldt tomt svar. **Out-of-scope-note:** `PersonPicker.tsx` (det mirror'ede
  eksisterende mønster) har PRÆCIS samme `.catch(() => {})`-mangel — pre-eksisterende kode
  udenfor denne diff, ikke rettet her.

**Impact-buckets (verified):**
- Silent content-corruption: 1 (H1 — token-syntaks lækket som synlig tekst).
- False-confidence/process: 2 (H2 — vedvarende aktiv Fortryd-knap på allerede-fortrudt post +
  uoversat rå DB-fejl; M3 — fejl umulig at skelne fra tom liste).

**Læring:** Et escape-alfabet skal inkludere ESCAPE-TEGNET SELV (`\`), ikke kun de tegn det
beskytter — ellers kan en literal forekomst af escape-tegnet i brugerdata blive fejltolket som
starten på en escape-sekvens af et efterfølgende, urelateret afgrænsnings-tegn. Symmetrisk
encode/decode (samme tegnklasse begge veje) er nødvendig, ikke kun tilstrækkelig — en
asymmetri opdages ikke af enheds-tests der kun tester decode-siden isoleret.
