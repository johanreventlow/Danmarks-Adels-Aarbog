# Review-brief — "Forældre ukendt"-markering + generations-browser (branch `feat/generations-browser-v2`)

**Til:** ekstern review (Codex)
**Dato:** 2026-07-10
**Branch:** `feat/generations-browser-v2` (8 nye commits oven på den pausede v2, IKKE merget)
**Diff:** `git diff main...HEAD` (ignorér `docs/reviews/20-*`, `docs/superpowers/plans|specs/2026-07-05-generations-browser-v2*` — pre-eksisterende v2-artefakter)
**Status:** web 241/241 + mobil 329/329 grønne · tsc + vite build grønne · byte-identisk delt kerne (paritets-testet) · data-fit verificeret mod prod · empirisk E2E (markér→se) delvist gjort af bruger

Bed reviewet fokusere på **korrekthed + invariant-brud**, ikke stil (en 4-agent `/simplify` er allerede kørt på kernen).

---

## 1. Problemet (hvorfor featuren findes)

Stamtræet havde ét signal — "ingen `family_member`-kant" — der dækkede over **fire forskellige virkeligheder**:

| Tilstand | Betydning | Repræsentation |
|---|---|---|
| 1 | Bevist forælder-kant | `family_member` (rolle 'barn') |
| 2 | Formodet forælder til en KONKRET person ("formentlig søn af N") | `family_member.konfidens='formodet'` (eksisterende, invariant 7) |
| 3 | **Kilden angiver ingen forbindelse opad** (de tidligste led) | ❌ manglede |
| 4 | Kanten står i bogen, men er ikke udtrukket endnu | ❌ manglede |

v1/v2's tidligere "generations-fallback" tolkede **alt** fravær af en kant som tilstand 3 og viste generations-kandidater → forkerte forslag (person 210 vist som mulig slægtning til 208). Den fallback kører **stadig live på main/prod** (kun aner-retning). Kernediagnosen: modellen manglede en **epistemisk primitiv** til at skelne tilstand 3 fra 4.

**Løsningen:** at kilden ikke angiver en forbindelse er *selv en kildepåstand*. Den bliver et `fact(faktatype='forældre_ukendt')` + assertion + citation + konklusion — **ingen ny tabel/kolonne** (invariant 2: "nyt behov = ny faktatype"). Fuld analyse: `docs/reviews/25-generationer-ukendt-forbindelse-analyse.md` (ligger i main, ikke branchen).

---

## 2. Design-beslutninger (bruger-interview 2026-07-09)

1. **To grader** på markeringen (assertionens `vaerdi_tekst`):
   - `'forælder ukendt'` — en forælder findes, men er ukendt for os → "Mulige forældre".
   - `'ingen forbindelse angivet'` — bogen forbinder slet ikke personen opad → neutral ordlyd, **aldrig** "muligt barn".
   - NB: tilstand 2 (formodet, navngiven forælder) er IKKE en markering — det er en `konfidens='formodet'`-kant. Markeringen er kun for tilstand 3 (ingen forælder at linke).
2. **Inline distinkt kolonne** i selve Kolonner-træet — bevidst IKKE et separat side-panel-register (det var netop det spor der gled væk fra brugerens ønske om inline-bladring). Markeringen gør inline ærligt (gatet på markering, ikke fravær).
3. **Nedad-retning (2026-07-10):** markerede-uforbundne skal også ses når man bladrer NED fra en stamfader. Valgt som **ren projektion** af de eksisterende markeringer (ikke en ny 'børn_ukendte'-markering — se §5). **Altid-synlig sektion**, **patrilineær køns-gate** (kun mandlige ankre).

---

## 3. Arkitektur i ét blik

```
DB (uændret skema)            App read-lag                     Tree-byggere (rene, byte-identiske)         Render
fact 'forældre_ukendt'   →   fetchParentsUnknownRows()   →   buildParentsUnknown()                  →   candidate-kolonne (aner)
 + assertion (grad)           (overlapper hoved-batch)        → model.parentsUnknownByPerson             + "uforbundne"-sektion (nedad)
 + citation (kilde)                                           → buildBidirectionalColumns
 + afklaret konklusion                                          → unknownParentRing (aner-dødende)
                                                                → unknownChildSection (nedad-frontier)
```

Skrivning (redaktør): `markerForaeldreUkendt`-Change → `red_upsert_fakta` (find-or-create ét fact pr. person); fjern → `sletOplysning`-Change → `red_slet_oplysning`. Alt gennem det fortrydbare `submitChange`/`setPending`-flow (change_set).

---

## 4. Review-map (fil for fil)

**Delt kerne — SKAL være byte-identisk web↔mobil (håndhævet af `parity.test.ts` på 7 funktioner):**
- `web/src/data/generations.ts` ↔ `mobile/src/data/generations.ts`: `GRADE_FORAELDER_UKENDT`/`GRADE_INGEN_FORBINDELSE`, `ParentsUnknown`, `buildParentsUnknown` (folder facts+konklusioner+assertions+citations → kanonisk opslag; kanoniserer via samme_som; kun AFKLAREDE tæller), `buildGenCoords`.
- `web/src/data/tree.ts` ↔ `mobile/src/data/selectors.ts`: `columnLabel`, `columnGen` (læser faktisk koordinat, ikke aritmetik — review 20 H1), `buildDirection`, `buildBidirectionalColumns`, **`unknownParentRing`** (aner-kandidat-ring; forrige slægtled; fyrer ved dødende + markering), **`unknownChildSection`** (nedad-projektion; næste slægtled; marker-gate + bevist-forælder-eksklusion + køns-gate). `TreeColumn` + `UnconnectedChildGroup`-typer.

**Read-lag (platform-specifik I/O, ikke paritets-låst):**
- `web/src/data/model.ts` (`loadModel` + `fetchParentsUnknownRows`) ↔ `mobile/src/data/load.ts` (`loadFromSupabase` + `fetchParentsUnknownRows`). NB: markerings-hentningen STARTES før hoved-`Promise.all` og overlapper den (buildParentsUnknown kanoniserer bagefter).
- `web/src/data/types.ts` (`Model.parentsUnknownByPerson`) + `mobile/src/data/load.ts` (`LoadResult`) + `mobile/src/store/useStore.ts` (store-felt + SEED-default).
- `web/src/data/redaktionRead.ts` ↔ `mobile/src/data/redaktionRead.ts`: `fetchForaeldreUkendtMarkering` (nuværende markering til editor-prefill/fjern).

**Skrive-lag:**
- `web/src/data/redaktionWrite.ts` ↔ `mobile/src/data/redaktionWrite.ts`: `buildRpcCall` — `markerForaeldreUkendt`-art (→ `red_upsert_fakta`). Fjern kollapset til den generiske `sletOplysning`-art (/simplify-fund).

**UI:**
- `web/src/Folgesvend.tsx` (kandidat-kolonne-branch `col.candidate` + nedad-sektion `col.unconnectedChildren`) ↔ `mobile/src/app/(tabs)/tree.tsx`.
- `web/src/Redaktion.tsx` (`ForaeldreUkendtControl`) ↔ `mobile/src/app/redaktion/person/[id].tsx` (markerings-kontrol).

**DB:** `db-migrations.sql` — idempotent vokabular-seed (kun `vocab`-rækker; ingen skema-ændring).

---

## 5. Invarianter reviewet SKAL verificere holder

1. **Ingen skema-ændring.** Markeringen er udelukkende `fact`/`assertion`/`citation`/`conclusion` via `red_upsert_fakta`. Ingen ny tabel/kolonne.
2. **Marker-gating (kerne-invarianten).** Kandidat-UI (både `unknownParentRing` og `unknownChildSection`) må fyre KUN på en TILSTEDEVÆRENDE afklaret markering — ALDRIG på fravær af en DB-kant. Det var v1/v2's bug. Verificér at ingen sti kan vise en umarkeret person som kandidat.
3. **Byte-identisk delt kerne.** De 7 funktioner i §4 skal være tegn-for-tegn ens web↔mobil (`parity.test.ts` fejler ellers). Verificér at ingen platform-specifik logik er sneget ind i dem.
4. **Skrive-model.** Al skrivning går via `red_*`-RPC'er (rolle-gatet `current_rolle()='redaktion'`); ingen direkte klient-skrivning; markeringen er fortrydbar (change_set).
5. **Bevist-forælder-eksklusion (nedad).** En markeret person MED en bevist forælder er et sikkert barn, ikke en kandidat — `unknownChildSection` udelader `model.indexes.parentsByChild[p.id]?.length > 0`. (Dækker "mor bevist, far ukendt"-dubletten.)
6. **Patrilineær køns-gate (nedad).** `unknownChildSection` returnerer tomt hvis ankeret ikke er `koen === 'mand'`.
7. **Grad-ærlighed.** `'ingen forbindelse angivet'` må ALDRIG rendere som barn-claim; kun `'forælder ukendt'` bruger "Muligt barn"/"Mulige forældre"-ordlyd.

---

## 6. Foreslåede fokus-/risiko-områder (hvor rigtige fejl kan gemme sig)

- **`fetchParentsUnknownRows`-overlap:** funktionen startes før hoved-`Promise.all` og await'es efter collapse. Verificér at split (fetch uden `canonicalIdById`, build efter) er korrekt, og at tom-sæt-kortcirkuleringen (`if (!facts.length) return empty`) ikke skjuler en fejl.
- **Frontier-only-fyring (nedad):** `unknownChildSection` hænges kun på den yderste børne-kolonne (`sel === null`) + emitteres som ren kolonne ved barnløs anker. Verificér at den ikke (a) gentages i mellemliggende drillede generationer, (b) mangler på ankerets egen børne-kolonne (depth 1), (c) kolliderer på `key` (`descendant:N:unconn` vs `descendant:N`).
- **Kanonisering:** `buildParentsUnknown` kanoniserer `subjekt_id` via samme_som-collapse. Verificér at en markering på et alias-id lander på det kanoniske id (og ikke tabes/dubleres).
- **"Første afklarede markering vinder"** pr. person i `buildParentsUnknown` — er den deterministisk (afhænger den af række-rækkefølge)?
- **Cross-linje / founder med flere koordinater:** `unknownParentRing`/`unknownChildSection` itererer den markeredes/ankerets coords pr. linje. Verificér at en collapset founder (III/12 + V/1) håndteres uden dobbelt-tælling eller forkert linje-match.
- **Nedad O(coords × persons)-scan:** acceptabel? (Fyrer kun på frontier + med markeringer; sjældent. Vi vurderede den acceptabel, men bekræft.)
- **Aner-retningens dødende + label:** `unknownParentRing` bygger sin label inline (`${lokal}. slægtled · ${linje}-linjen`) frem for `columnLabel` — bevidst (columnLabel ville tilføje "Forældre ·"-kinship-præfiks). Bekræft at det er korrekt, ikke en glemt genbrug.
- **Sikkerhed:** markerings-facts er anon-læsbare for afdøde (RLS). Verificér at der ikke findes en anon/authenticated SKRIVE-sti til `fact 'forældre_ukendt'` udenom `red_upsert_fakta`-rollegaten. (Se også den separate DB-sikkerheds-note: `_delete_relation_evidence` blev fundet ugated i et tidligere review — urelateret til denne feature, men værd at holde øje med i samme base.)

---

## 7. Testdækning

- **Ren logik:** `web|mobile/src/data/__tests__/tree.test.ts` (+ `selectors.test.ts` mobil): `unknownParentRing` (marker-gate, grad, forrige slægtled, founder-cross-linje, dødende-uden-medlemmer) + `unknownChildSection` (køns-gate, bevist-forælder-eksklusion, marker-gate, grad-split, barnløs-anker, anden-linje-mismatch). `generations.test.ts`: `buildParentsUnknown` (afklaret-gate, kanonisering, første-vinder). `redaktionWrite.test.ts`: `markerForaeldreUkendt` + fjern-via-sletOplysning.
- **Komponent (web):** `TreeView.test.tsx`: kandidat-kolonne (ordlyd, proveniens, kuld, klik-re-anker, INGEN ugated kolonne uden markering) + nedad-sektion (ordlyd, kilde, klik-re-anker).
- **Paritet:** `parity.test.ts` (begge platforme): 7 delte funktioner byte-identiske.

---

## 8. Verifikations-status (ærligt)

- ✅ **Data-fit mod prod** (anon-læsesti): 20 af 25 uforbundne personer sidder på `lokal ≥ 2` (kun 5 på lokal 1 hvor aner-ringen er inert), og alle 20 har medlemmer i forrige slægtled. Featuren er IKKE inert mod ægte data. Nedad: person 1 (Gottschalk) er `koen=mand`, så de 4 markerede (13/24/35/93) surfacer under deres mandlige lokal-N-ankre.
- ⚠️ **E2E (markér → se ringen rendere):** brugeren har markeret 4 personer og verificeret aner-retningen; nedad-retningen er netop landet og bør øjne-bekræftes på både web og mobil. Bemærk: mobil-markeringen rører redaktør-person-editoren, som har en tidligere urapporteret crash-note.
- ❌ **Ikke kørt:** `/dual-review-cycle`, merge. Anbefalet: dual-review FØR merge, da merge fjerner v1's aner-fallback der er live på prod (en synlig adfærdsændring rider med).

---

## 9. Commits (nyeste først)

```
docs(changelog): nedad-projektion
feat(stamtræ): nedad-projektion — uforbundne i næste slægtled (efterkommer-retning)
docs(changelog): forældre-ukendt-markering + inline kandidat-kolonne
refactor(stamtræ): /simplify-pass (4 agenter) — 5 fund anvendt
feat(redaktion): authoring for "forældre ukendt"-markering (web+mobil)
feat(stamtræ): Phase C — inline marker-gatet kandidat-kolonne (web+mobil)
feat(stamtræ): Phase B — data-lag for "forældre ukendt"-markering (2 grader)
feat(stamtræ): Phase A — kun beviste kanter + slægtled-labels (fjern ugated fallback)
```
