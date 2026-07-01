# Review 10 — Versionering + hyperlinks (App-lag, RN/Expo)

**Dato:** 2026-06-30
**Område:** `mobile/src/lib/mentions.ts`, `NarrativRenderer.tsx`, `MentionPicker.tsx`,
`redaktionRead.ts`/`redaktionWrite.ts` (historik/fortryd/døde-links-tilføjelser),
`SkrivePreviewSheet.tsx` (ny `onError`-prop), `historik/[id].tsx`, editor-/visnings-wiring.
**Reviewer:** Claude (draft) → Codex (adversarisk) → reconcile.
**Verifikation:** `tsc --noEmit` 0 fejl, jest 197/197 grøn efter `/simplify` (begge er det
skarpeste automatiserede signal her — komponenter/skærme er IKKE Expo-kørt, jf. plan
§"Test-niveau"). **Status er derfor kode-komplet + statisk verificeret, IKKE runtime-verificeret.**
Se §"Manuel Expo-verifikation" nedenfor for hvad der udestår før den påstand kan styrkes.

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

---

## Manuel Expo-verifikation — punch list

**Opdateret 2026-06-30 (anden session):** en iOS-simulator var faktisk tilgængelig
(`xcrun simctl` + Xcode), modsat tidligere antagelse. App'en blev bygget med
`expo run:ios` mod den faktiske prod-Supabase (893 personer loadet korrekt) og afprøvet
med reelle taps via `idb` (facebook/fb tap — installeret til formålet; kræver ikke
macOS Accessibility-rettigheder som System Events/AppleScript ville).

1. **✅ KONFIRMERET (empirisk, real device).** Da ingen LIVE-narrativ har et `[[...]]`-token,
   blev et testtoken midlertidigt injiceret lokalt (`person.bio + ' [[person:1|TEST-LINK til
   person 1]] og [[estate:1|død estate-type]].'` i `app/person/[id].tsx`, hot-reloadet via
   Metro, ALDRIG committet/pushet — revertet med `git checkout` efter test). Resultat:
   `[[person:...]]` rendrede med aktiv bordeaux/underline-stil og navigerede korrekt
   (`router.push`) til personen ved tap; `[[estate:...]]` (ikke-implementeret type i
   `NarrativRenderer`) rendrede korrekt med den inaktive grå stil, ingen krasch. Hele
   parseNarrativ→render→tap→navigate-kæden virker end-to-end mod et rigtigt device.
2. **✅ KONFIRMERET.** Bio-klamp + "Læs hele biografien"/"Vis mindre"-toggle fungerede korrekt
   gentagne gange med `NarrativRenderer`s multi-segment `Text`-børn (inkl. det injicerede
   testtoken til sidst i en lang biografi) — ingen layout- eller klamp-regression.
**Opdateret igen samme session — brugeren loggede selv ind som redaktør** (jeg har ingen
adgangskode og skrev den ikke; brugeren tastede den direkte i simulatoren). Det afslørede
desuden et separat, reelt UI-fund (ikke i den oprindelige punch-list): se "Fund: omvendt
dry-run-toggle-polaritet" nedenfor.

3. **✅ KONFIRMERET (empirisk, real device, redaktør-login).** Søgte "Theodor" i MentionPicker,
   valgte en træffer — token `[[person:302|Theodor]]` blev indsat MIDT i den eksisterende
   bio-tekst ved markørens faktiske position (ikke for enden), og markøren flyttede sig
   korrekt til lige efter det indsatte token. Insert-at-cursor virker som tilsigtet.
**Opdateret igen — brugeren godkendte separat én minimal LIVE-testskrivning** (append af en
testsætning til `narrative` for en obskur 1600-talsperson, id 111 "Abel"), specifikt for at
skabe den første nogensinde `change_set`-række i prod og dermed kunne teste fortryd-flowet.

4. **🐛→✅ KONFIRMERET, men afslørede en REEL PROD-BUG undervejs.** Første fortryd-forsøg
   (`red_fortryd_change_set`, `p_change_set_id: 1`) fejlede hårdt med en ægte Postgres-fejl:
   `cannot insert a non-DEFAULT value into column "fts"`. Rodårsag (verificeret i live skema):
   `narrative.fts` er en `GENERATED ALWAYS AS (to_tsvector('danish', tekst)) STORED`-kolonne
   — aktiv i prod, selvom `CLAUDE.md` §9 hævder fuldtekstindekset er "kommenteret ud" (endnu
   et schema-drift-fund). `_version_upsert_row` bygger sin `INSERT`/`ON CONFLICT`-kolonneliste
   direkte fra `jsonb_object_keys(p_row)` og ekskluderede kun de kendte `skip_cols`
   (review09 H2) — IKKE generated-kolonner generelt. Det betyder **enhver tabel med en
   generated-kolonne har en strukturelt knækket fortryd-sti**, ikke kun `narrative`.
   Transaktionen rullede korrekt atomisk tilbage (Postgres tillader slet ikke handlingen) —
   ingen delvis korruption, `change_set.reverterer_id` forblev `null`, verificeret via
   read-only SQL. **Fix anvendt til prod** (`version_upsert_row_exclude_generated_cols`-
   migration, `schema.sql`+`db-migrations.sql` opdateret): `WHERE NOT EXISTS (SELECT 1 FROM
   pg_attribute a JOIN pg_class c ... WHERE ... a.attgenerated = 's')` filtrerer nu
   kolonnelisten. Genkørt fortryd efter fix: **lykkedes** — `change_set #2` oprettet med
   `reverterer_id: 1`, Abels narrativ-tekst genoprettet til nøjagtig original ordlyd
   (verificeret via read-only SQL, ikke kun UI).
5. **❌ IKKE TESTET.** Kræver en reel B9-divergens (to konkurrerende ændringer af samme
   underliggende data) — vurderet for høj yderligere prod-risiko til at konstruere i denne
   omgang uden en ny, separat godkendelse.
6. **✅ KONFIRMERET (empirisk, ægte data).** Efter fortryd viste historik-listen korrekt: den
   ORIGINALE post ("Opdaterede narrativ...") fik label "Fortrudt" (inaktiv, ingen knap) —
   H2-fixets `revertedIds`-beregning virker på ægte data. Reversal-posten ("Fortrød:
   Opdaterede narrativ...") viste en AKTIV "Fortryd"-knap — bekræfter at dette teknisk er en
   gyldig redo-handling, som forudset i H2-analysen; knappen er fortsat uændret-mærket
   (ingen "Fortryd fortrydelsen"-tekst), men adfærden er nu verificeret korrekt, ikke kun
   antaget.

**To reelle nær-uheld under manuel test (proces-læring, ikke app-bugs).** Under interaktion
via `idb`-baserede taps ramte to koordinat-fejl utilsigtet destruktive/forkerte forhåndsvisninger
(`red_slet_familie_link` og `red_set_koen`) — begge fanget og annulleret FØR "Skriv til basen",
takket være at `SkrivePreviewSheet` altid viser den eksakte RPC + argumenter før udførelse.
Ingen af de to nåede databasen. Læring: efter enhver tekstindtastning der kan ændre layoutets
højde, skal knap-koordinater genhentes friskt (`idb ui describe-all`) umiddelbart før tryk —
et screenshot taget selv ét kommando tidligere kan være forældet nok til at ramme forkert.

**Fund: omvendt dry-run-toggle-polaritet (brugerfund, rettet samme session).** Switchen i
`redaktion/person/[id].tsx` var kablet `value={!dryRun}` (ON/højre = LIVE), mens den
IDENTISKE switch på Konto- og dashboard-skærmen bruger `value={dryRun}` (ON/højre =
dry-run/sikker) — samme globale felt, modsat retning afhængig af skærm. Brugeren opdagede
dette ved selvsyn ("den lille pil... er anvendt inkonsekvent"). Rettet i `ecad25c`
(`value={dryRun}`/`onValueChange={setDryRun}`, matcher de to andre skærme; `trackColor`-par
byttet om for uændret visuelt resultat). Ikke en del af dual-review cycle 10 — fanget først
ved faktisk brug af appen, hvilket er præcis den slags fund statisk review ikke kan nå.

**Konklusion:** punkt 1, 2, 3, 4 og 6 er nu fuldt empirisk verificeret på et rigtigt device
mod ægte prod-data (inkl. redaktør-login og én godkendt LIVE-testskrivning). Punkt 5
(konflikt-retry) forbliver utestet — kræver en konstrueret B9-divergens, vurderet til at
kræve separat ny godkendelse. To ægte fund undervejs, ingen del af den oprindelige
dual-review cycle 10, begge kun opdaget ved faktisk kørsel:
1. **UI-bug** (brugerfund): omvendt dry-run-toggle-polaritet i `redaktion/person/[id].tsx` — rettet.
2. **DB-bug** (HIGH, hard-crash-bucket): `_version_upsert_row` manglede eksklusion af
   `GENERATED ALWAYS`-kolonner — gjorde fortryd strukturelt knækket for enhver tabel med en
   sådan kolonne (`narrative.fts` i praksis). Migration anvendt til prod + `schema.sql`/
   `db-migrations.sql` opdateret; genkørt fortryd bekræftet succesfuld efter fix.
