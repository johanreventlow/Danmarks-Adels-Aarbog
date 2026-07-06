# Review 20 — Generations-browser v2: design-logik

**Dato:** 2026-07-05 · **Type:** design-logik-review (ikke bug-jagt) · **Anledning:** bruger så
"underlige resultater" ved empirisk web-test og betvivler om per-linje-slægtled er den mest logiske
browse-akse. Fokus: `web/src/data/tree.ts` (`buildDirection`/`buildBidirectionalColumns` label-
aritmetik, `fallbackRing`), `generations.ts` (`adjacentGen`), activeCoord-resolution.

---

## H1 [HIGH] — Label-aritmetik giver "0. / −1. slægtled" ved founder + forkert linje ved kryds-linje

**Lokation:** `web/src/data/tree.ts:164` (spejlet i `mobile/src/data/selectors.ts`)

**Symptom:** Beviste (ikke-fallback) aner/efterkommer-kolonner får deres slægtled-tal ved ren
aritmetik `activeLokal ∓ depth` i stedet for at læse den faktisk viste persons koordinat.

**Verifikation (kode-citat):**
```typescript
const slaegtled = activeLokal != null ? activeLokal + (kind === 'ancestor' ? -depth : depth) : null;
const label = columnLabel({ kind, depth, slaegtled, linje }); // linje = ac's aktive linje (l206)
```
For en founder (Conrad, `activeCoord` = V/lokal **1**): ane-depth-1 → `1 − 1 = 0` → "0. slægtled";
depth-2 → "−1. slægtled". `linje` er hele vejen den aktive linje (V), så en bevist forælder der
reelt ligger i III/lokal 11 mærkes "Forældre · 0. slægtled" i V-kontekst — forkert tal OG forkert linje.

**Konsekvens:** Synligt forkerte overskrifter ("0./−1. slægtled") for enhver founder/tidlig-generation
med beviste aner — netop de personer feature'en handler om. Desuden **inkonsistens**: fallback-kolonner
bruger `genLabel` = faktisk `adjacentGen`-koordinat (korrekt, fx "11. slægtled"), mens en bevist
kolonne i samme position ville vise arithmetik-tallet. To kolonne-typer, to tal-kilder.

**Foreslået fix:** Læs det FAKTISKE slægtled fra kolonnens person(er)s `genCoord` (i den traverserede
linje) — samme kilde som fallback-ringen bruger — i stedet for `activeLokal ∓ depth`. Dvs. for hver
bevist kolonne: slå den valgte/første persons koordinat op og brug dens `lokal`+`linje`. Falder tilbage
til kinship-only hvis personen ingen koordinat har. Dette fjerner både 0/−1-fejlen OG bevist/fallback-
inkonsistensen, fordi begge så læser den samme faktiske koordinat.

---

## H2 [MEDIUM/design] — Per-linje `slaegtled_lokal` er en diskontinuert browse-akse på tværs af founders

**Symptom:** `slaegtled_lokal` resetter til 1 ved hver linje-start. En browser der krydser linjer ved
founders (feature'ens kerne) får derfor et **springende** tal: op fra Conrad = V "1. slægtled" →
III "11. slægtled" (spring fra 1 til 11). Selv med H1-fixet (korrekte tal) er sekvensen ikke-monoton.

**Overvejelse:** Det "gennemgående" tal (bogens parentes, "Første (tolvte)") er en **kontinuert**
tælling fra den fælles rod og ville give en monoton sekvens (…12 → 11 → 10…) på tværs af linjer —
formentlig en mere logisk akse for en bladrende generations-browser. MEN: `slaegtled_gennem` er kun
udfyldt for IV/V-grenene (bogens single-ordinal-headers i I/II/III gav NULL). Det kan **udledes** for
alle linjer: `gennem = lokal + (linjens rod-offset)`, hvor offset = founderens `gennem − lokal`, fundet
ved at gå op ad `parent_lineage_id`-kæden. Vi har allerede `parent_lineage_id` + `gennem` ved founders.

**Fix-optioner (til beslutning m. bruger + bog-sammenligning):**
- (a) **Behold lokal, fix H1** — korrekte per-linje-tal, men springende ved founders. Mindst arbejde.
- (b) **Udled gennemgående som primær akse** — monoton, matcher bogens parentes-tælling; kræver en
  ren `effectiveGennem(coords, lineageHierarchy)`-helper. Mere logisk for en cross-line browser.
- (c) **Vis begge** ("11. slægtled i III · 24. gennemgående") — rigest, men busier header.

**Åbent:** afventer brugerens direkte bog-sammenligning af de "underlige resultater" — afgør om det
er H1 (ren bug) eller også H2 (akse-valg).

---

## H3 [LOW/UX-logik] — "Hele generationen som naboer/fallback" kan i sig selv være det underlige

**Symptom:** Både fallback-ringen og anker-peers viser HELE slægtledet i linjen (alle personer ved
G∓1 / G), ikke kun ankerets egne (u)beviste slægtninge. For et stort slægtled = mange ikke-ancestrale
personer vist som "naboer". Bevidst ærligt (v1-beslutning), men kan opleves som støj/forvirrende.

**Overvejelse:** Er "slægtled-naboer" den rigtige model, eller bør ringen indsnævres (fx kun samme
`kuld`, eller kun personer med en sti mod ankeret)? Afventer om brugerens "underlige" refererer til
dette. Ikke en bug; et model-spørgsmål.

---

## Codex adversarial-review + reconcile (2026-07-05)

**Verdict: needs-attention — stop før mobil (T7)/merge; model kræver gentænkning.**

### DECISIVT NYT FUND (verified empirisk mod prod) — founder-hoppet er inert mod ægte data
`adjacentGen`'s founder-krydshop (`generations.ts:60`) kræver en koordinat hvor `lineageId ===
parentLineageId`. Men **prod: alle 5 linjer har `parent_lineage_id = NULL`** (verificeret:
`SELECT count(*) FROM lineage WHERE parent_lineage_id IS NOT NULL` → 0). Conrad V/1: `parent_lineage_id
NULL`, `gennem 12`; III/58: `lokal 12`, `parent_lineage_id NULL`. Konsekvens (verified): op-browse fra
en founder → founder-hop finder ingen kandidat → `null` → **ingen ane-ring; ren dødende**. Feature'ens
KERNE (krydse linjer ved founders) virker IKKE mod prod — kun mod syntetiske tests der SELV sætter
`parentLineageId`. Forværret af at `activeCoord` defaulter til lavest-lokal (V/1 — den koordinat der
KRÆVER det knækkede hop) i stedet for gennem-linjen (III/12 — der ville browse fint via ren lokal−1).

### H1 — confirmed (arithmetik "0./−1. slægtled"); "forkert linje"-delen DISMISSED
Bekræftet: `tree.ts:164` giver founder-aner "0./−1. slægtled". DISMISSED: beviste labels viser IKKE
`linje` (kun tallet, `columnLabel`-bevist-gren) — så min "forkert V-linje"-påstand var falsk.
RECALIBRERET fix: "læs første persons koordinat" er ikke robust — en bevist kolonne kan have flere
personer med forskellige/manglende koordinater (Codex). Korrekt fix = **konsensus-regel**: vis absolut
slægtled kun når ALLE viste enige om én (lokal, linje); ellers kinship-only.

### H2 — confirmed problem; min parent_lineage_id-udledning UNSOUND, men gennem-bridge er en vej
Per-linje lokal er diskontinuert (1→11 ved founder). Min "udled gennem via parent_lineage_id" er
umulig (NULL, verified). MEN: V/1 bærer `gennem=12` OG er samme_som III/12 (`lokal 12`) → gennem=lokal
matcher ved founderen. Så gennemgående-aksen kan formentlig udledes fra **founders' `gennem`-værdi +
samme_som-broer** (uafhængigt af parent_lineage_id) — værd at undersøge. Codex-anbefaling: etablér en
komplet, reload-durabel linje-offset/founder-mapping FØRST, afvis tvetydige/urodede linjer; indtil da,
brug lokal kun som linje-kvalificeret metadata, ikke den globale venstre/højre-akse.

### H3 — recalibrated: adskil kandidat-visning fra bevist traversal
Hele-slægtled-naboer/-fallback bør være en EKSPLICIT SEPARAT "generations-kandidater"-visning, ikke
blandet ind i den beviste aner/efterkommer-stribe (blanding = sandsynlig "underlig"-kilde). Indsnævring
via `kuld` ville fabrikere falsk relevans.

### Nye flaws (confirmed)
1. `fallbackRing` ignorerer `activeCoord` (sorterer personens coords på lavest lokal) → multi-linje-
   person kan hoppe gennem V selv om UI er i III-kontekst (`tree.ts:82,88`; activeCoord ej sendt, `:159`).
2. Direkte navigation defaulter til mindste lokal (`Folgesvend.tsx:476,488`) → dobbelt-listet founder
   vælger systematisk gren-G1, ikke den kontinuerte moderlinje-kontekst.

### Læring
Unit-tests med syntetisk data (parentLineageId sat) MASKEREDE at feature-kernen er inert mod prod
(parent_lineage_id NULL). Empirisk + dual-review fangede hvad 335 grønne tests ikke gjorde.

---

## PAUSET 2026-07-05 — status + genoptagelses-guide

Brugeren udskød problemet efter empirisk test. **Intet merget; branchen er fuldt revertbar.**

**Konvergeret retning (Claude + Codex, ikke bygget):**
- **Step 1 (stabilt produkt):** rul træet tilbage til KUN beviste kanter + generations-nummer-labels
  (læst fra faktisk koordinat, "4. slægtled · III-linjen"). SLET `adjacentGen` founder-hop,
  `fallbackRing`, `buildAnchorPeers`. Codex: minimalt-korrekt lock-in selv om Step 2 aldrig bygges.
- **Step 2 (valgfrit, demand-driven):** separat read-only "kilde-register" (side-panel, per-linje,
  bladr N−1/N/N+1 inden for linjen, kuld-grupperet, proveniens, "forbindelser ikke angivet i kilden").
  Aldrig aner/efterkommer-ord for register-medlemskab. Cross-linje = eksplicit "også i III →"-chip.

**Rod-årsag (kort):** fallback fyrer på "mangler i DB" ≠ "genuint ukendt i bogen" → forkerte
kandidater (210 under 208). + parent_lineage_id NULL i prod (founder-hop inert) + patrilinearitet.

**Åbne spørgsmål:** (1) rammer register-listen den oprindelige idé, eller mangler forfatterens
gruppering? (2) ét slægtled ad gangen vs. flere ved siden af hinanden? (bruger ubesvaret) (3) er
Step 1 nok?

**NB:** main/prod har stadig v1's aner-fallback live (samme problem, kun aner) — Step 1 rydder også
det op. Datalaget (slægtled i prod) er korrekt og beholdes.

Fuldt fundament: memory `generations-browser-v2-paused`.
