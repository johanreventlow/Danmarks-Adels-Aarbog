# Design: Relationel corroboration i TNG-QA review-køen

> Status: godkendt-til-plan · 2026-07-01 · udspringer af `docs/superpowers/specs/2026-06-29-tng-qa-crosswalk-design.md`
> Revideret 2026-07-01 efter to uafhængige Codex-reviews (se §"Codex-review-fund indarbejdet").

## Formål

TNG-QA-pipelinen (`R/tng-qa/`) matcher vores personer mod TNG-dumpet
udelukkende på attributter (navn/dato/køn) — se beslutning A i
`2026-06-29-tng-qa-crosswalk-design.md`: *"Matching ALDRIG på relationer."*
Konsekvens: 658 par lander i `review`-tier, mange fordi det uniforme
efternavn "Reventlow" gør navnesignalet svagt.

Denne feature bruger **allerede sikre (`auto`-tier) matches** til at berige
review-køen med kontekst: "denne kandidats far/mor/barn er allerede
auto-matchet til TNG-person X — passer det med TNG's egen familie-graf?".
Det er et **beslutningsstøtte-signal til den menneskelige reviewer**, ikke en
ændring af matching-algoritmen, og det betyder **at strukturel støtte var
til stede** — ikke at reviewerens afgørelse faktisk blev truffet på grund af
den (systemet kender ikke reviewerens motivation).

**Eksplicit ikke-mål:** at ændre `score_pair()`/`assign_tiers()` i
`04-match.R`, at auto-promovere noget til `auto`-tier, eller at foreslå helt
nye kandidater for personer der i dag har `none`-tier. Se §"Ud af scope".

## Faseinddeling (ny efter Codex-review)

Feature'en splittes i to uafhængigt leverbare faser, fordi Fase 2 viste sig
at afhænge af et eksisterende bug i review-merge'en (se §"Forudsætninger"):

- **Fase 1 — annotation af review-køen.** Trin 4b beregner corroboration og
  beriger `tng-review-queue.csv`. Læser kun fra crosswalk, skriver kun til
  review-køen. Ingen afhængighed af merge-korrekthed. **Kan bygges nu.**
- **Fase 2 — cirkularitets-relabeling i Trin 6** (`enig_via_matching`).
  Kræver at et bekræftet par i `accepted_crosswalk()` pålideligt kan spores
  tilbage til én bestemt kandidat-række — hvilket `merge_review_decisions()`
  i dag ikke garanterer (se §"Forudsætninger"). **Blokeret indtil
  merge-fix + injektivitetstjek (M2) er på plads.**

## Baggrund — verificerede tal (2026-07-01, mod 2026-06-30-kørslens data)

En engangs read-only analyse af `data/tng-crosswalk.csv` + `data/tng.duckdb`
+ vores `family_member` gav:

| Signal | Antal review-par | Unikke personer |
|---|---|---|
| Review-par i alt | 658 | 382 |
| ...med auto-matchet **ægtefælle** som nabo | 0 | 0 |
| ...med auto-matchet **forælder/barn** som nabo | 253 | 148 |
| ...hvor kandidatens TNG-id **faktisk** hænger sammen med naboens auto-match i TNG-graf | **185** | **133** |

(Crosswalk'en dækker 963 unikke `person_id` — rettet fra en tidligere fejlagtig
"925", som var CLAUDE.md's overordnede base-tal, ikke crosswalk-dækningen.)

Ægtefælle-corroboration bidrager intet i praksis (review-tier-personer har
sjældent en identificeret ægtefælle endnu) — kun forælder/barn er
implementeret (se komponent-afsnittet). De 253→185 forskellen er vigtig: en
auto-matchet nabo er IKKE i sig selv støtte — det skal verificeres at
kandidatens TNG-id faktisk optræder som forælder/barn til naboens TNG-id i
TNG's egen graf.

**Caveat (Codex-fund, lav prioritet men værd at sige højt):** disse tal er et
øjebliksbillede af én Supabase-pull + én TNG-dump-version — ikke et
committet/reproducerbart artefakt. De kan drifte hvis `family_member` eller
TNG-dumpet ændres. Det er en beskrivelse af *forventet størrelsesorden*, ikke
en facit-kilde.

## Centrale beslutninger

1. **Rører ikke `04-match.R`.** Scoring/tier-tildeling er kalibreret
   (bootstrap, 2026-06-30) og uafhængig af denne feature. Corroboration
   beregnes i et nyt trin **4b**, EFTER Trin 4 (fersk `crosswalk`) og FØR
   Trin 5 (`merge_review_decisions`) — rækkefølgen er kritisk: Trin 5 flipper
   allerede nogle `review`-rækker til `accepted`/`afvist` baseret på sidste
   køs afgørelser, og corroboration skal beregnes mens de par stadig er
   `review`-tier, ellers findes de aldrig. **Verificeret** direkte mod
   `run-pipeline.R`/`05-review.R` under Codex-reviewet.
2. **Kun forælder/barn, ikke ægtefælle.** Ægtefælle-logik implementeres ikke
   nu — 0 hits i reelle data er ubrugt kode (YAGNI). Let at tilføje senere
   hvis flere ægtefæller identificeres.
3. **Kun biologisk `rolle=="barn"`, og aldrig `konfidens=="omstridt"`.**
   Genbrugte `derive_our_pc()` filtrerer i dag literalt på `rolle=="barn"`
   (springer `adopteret_barn`/`plejebarn`/`stedbarn` over — dokumenteret
   eksisterende begrænsning, ikke noget denne feature retter) og ignorerer
   `konfidens` helt. For corroboration specifikt er det utilstrækkeligt: at
   vise en reviewer "støttet af X" når X selv er en **omstridt**
   forælder/barn-relation i vores egen base, ville være aktivt vildledende —
   værre end slet ingen støtte-signal. `family_corroboration()` filtrerer
   derfor `our_pc`-naboer til `konfidens IS NULL OR konfidens IN ('sikker',
   'sandsynlig')` før opslag mod TNG-grafen.
4. **Cirkularitet håndteres INDE i `compare_parent_child()`, ikke som
   post-hoc match på dens output (rettet efter Codex-review).**
   Oprindeligt design ville matche en post-hoc wrapper mod
   `compare_parent_child()`'s outputkolonner — men den funktion returnerer
   kun `child_id`/`tng_id`/`kategori`/`detalje`; `parent_id` findes **ikke**
   som kolonne, kun indlejret i en formateret tekststreng
   (`sprintf("vores %s %d", rolle, parent_id)`, `06-compare.R:135`). En
   post-hoc join på en ikke-eksisterende kolonne var uimplementerbar. I
   stedet får `compare_parent_child()` en ny valgfri parameter
   `corrob_edges` (data.frame med allerede-orienterede `child_id,parent_id`
   fra `04b`s output — se §Komponenter) og tjekker medlemskab **inde i den
   eksisterende løkke**, hvor `our_pc$child_id[i]`/`our_pc$parent_id[i]`
   allerede er rigtige kolonner, før `detalje`-strengen bygges. Det løser
   samtidig retnings-tvetydigheden (kandidat kan være barnet ELLER
   forælderen relativt til naboen) — `04b` gemmer allerede kanten i
   `{child_id,parent_id}`-orientering, så der ikke skal gættes på
   retning i Trin 6.
5. **Persisteret som separat fil, ikke genberegnet i Trin 6.**
   `data/tng-corroboration.csv` (ny) gør relabeling deterministisk og
   testbar uafhængigt af Trin 6. **Skal tilføjes `.gitignore` eksplicit** —
   Codex-reviewet fandt at min oprindelige påstand om at den var
   "git-ignoreret som de tre eksisterende" var **faktuelt forkert**: jeg
   verificerede selv med `git check-ignore` at `.gitignore` kun nævner de tre
   eksisterende filer ved eksakt navn (linje 19-21), ikke et mønster der
   dækker nye filer. Rettes som del af implementeringen.
6. **Tre-tilstands status, ikke boolean.** `familie_stoette=TRUE/FALSE` ville
   sammenblande "ingen auto-nabo" med "auto-nabo findes, men TNG-grafen
   modsiger den" — to væsentligt forskellige review-signaler. Feltet bliver
   `familie_status ∈ {"ingen_auto_nabo", "bekraeftet", "modstridende"}`.
7. **PII: samme retention-model som de tre eksisterende lokale filer — ingen
   ny politik opfundet her.** `familie_detalje`-friteksten (med person-id'er)
   lander kun i de lokale, git-ignorerede filer. Der findes i dag ingen
   dokumenteret retention/adgangs-politik for `tng-crosswalk.csv`/
   `tng-review-queue.csv`/`tng.duckdb` heller — at kræve én ny udelukkende
   for denne fjerde fil, når ingen af de tre andre har det, er scope ud over
   denne spec (en repo-bred politik for git-ignorerede lokale QA-filer er en
   selvstændig indsats). Den committede markdown-rapport får kun en
   **tal-kun** kategori `enig_via_matching`, samme mønster som eksisterende
   `enig`/`uden_for_scope` (§"GDPR PII-gate" i `docs/tng-qa-koersel.md`).
   Relabeling sker på `g$our_pc` (den GDPR-gatede version fra
   `gate_inputs()`), ikke den rå `our_pc`.
8. **Kalibrering (facit-sæt/`review_cutoff`) er fortsat parallel-sikkert —
   men review-merge-fixet er det IKKE.** Oprindeligt skrev jeg at hele
   feature'en var uafhængig af udestående kalibreringsarbejde. Det holder
   for facit-sæt/cutoff-kalibrering (Fase 1 rører ikke tier-tildeling). Det
   holder **ikke** for Fase 2 — se §"Forudsætninger" nedenfor, som Codex
   fandt og jeg verificerede direkte i `05-review.R`.

## Forudsætninger (blokerende for Fase 2, ikke for Fase 1)

**`merge_review_decisions()` matcher afgørelser kun på `person_id`, ikke
`(person_id, tng_id)`** (`05-review.R:12`: `which(cw$person_id == pid)`).
Med 658 review-par fordelt på 382 personer (~1,7 kandidat/person i snit) er
det almindeligt at én person har flere kandidat-rækker. En enkelt
`afgoerelse`-værdi for den person flipper **alle** dens kandidat-rækker til
samme tier — også kandidater revieweren aldrig eksplicit tog stilling til.
For en generel QA-pipeline er det allerede et kendt problem (`M2` i
`docs/tng-qa-koersel.md`: "Validér injektivitet ved accept"). For **dette**
feature er det blokerende, fordi Fase 2 forudsætter at et bekræftet par i
`accepted_crosswalk()` entydigt kan spores tilbage til den specifikke
`(person_id,tng_id)`-kandidat corroboration blev beregnet for — ellers kan
`enig_via_matching`-relabeling ende med at markere den forkerte kandidats
kant, eller slet ingen.

**Krav før Fase 2 implementeres:**
1. `merge_review_decisions()` nøgles på `(person_id, tng_id)`, ikke
   `person_id` alene.
2. Post-merge injektivitetstjek (M2): afvis/flag hvis samme `tng_id` optræder
   accepteret for to `person_id`, eller omvendt.

Fase 1 (annotation) er upåvirket af dette — den læser kun den friske,
endnu-ikke-mergede crosswalk.

## Arkitektur — pipeline-ændring

```
Trin 1 (TNG→DuckDB) ─┐
Trin 2 (Supabase)   ─┴─► our_pairs/our_pc/tngc beregnes HER (flyttet op fra
                          Trin 6 — afhænger kun af ours/tng_families/tng_children,
                          ikke af crosswalk. our_pairs bruges fortsat af Trin 6's
                          eksisterende compare_marriages(), UAFHÆNGIGT af
                          corroboration — se nedenfor). Ren omrokering, ingen
                          logikændring.

Trin 3-4 (normalisér+match) → crosswalk (tier ∈ auto/review/none), FERSK

Trin 4b (NY, Fase 1): family_corroboration(crosswalk, our_pc,
                       tng_families, tngc)
  → data/tng-corroboration.csv (git-ignoreret, tilføjes .gitignore).
    KUN de faktisk bekræftede kanter, allerede orienteret:
    person_id, tng_id, child_id, parent_id, familie_status="bekraeftet",
    neighbor_person_id, neighbor_tng_id, rolle

Trin 5 (review-merge, UÆNDRET indtil Fase 2-forudsætning er løst):
  → tng-review-queue.csv beriges (venstre-join, ÉN RÆKKE PR. (person_id,tng_id)
    — flere corroborerende naboer for samme kandidat AGGREGERES til én række
    med familie_stoette_antal + sammenkædet familie_detalje, ikke duplikerede
    rækker) med familie_status + familie_detalje FØR skrivning.
    Mennesket redigerer stadig kun afgoerelse/ny_tng_id.

Trin 6 (sammenlign+rapport, Fase 2 — BLOKERET, se Forudsætninger):
  compare_parent_child(our_pc, tng_children, xwalk, corrob_edges) tjekker
  INDE I løkken, for hver "enig"-kandidat-kant, om {child_id,parent_id}
  findes i corrob_edges → kategori <- "enig_via_matching" for netop den
  kant. Alle andre kanter for samme person forbliver uændrede.
  Rapporten opsummerer enig_via_matching som tal, ligesom enig/uden_for_scope.
```

## Komponenter

### `R/tng-qa/04b-corroboration.R` (ny fil, Fase 1)

```r
family_corroboration <- function(crosswalk, our_pc, tng_families, tngc) {
  # 1. auto_map: navngivet vektor person_id -> tng_id, KUN tier=="auto"
  # 2. our_pc filtreres til rolle=="barn" (allerede givet) OG
  #    konfidens IS NULL/"sikker"/"sandsynlig" (IKKE "omstridt"/"formodet")
  # 3. for hver review-tier (person_id, tng_id): find naboer via det
  #    filtrerede our_pc der har en auto_map-entry
  # 4. for hver nabo: slå op i tngc (reshape_tng_children) om candidate
  #    tng_id faktisk optræder som far/mor/barn til naboens auto-tng-id
  # 5. returnér KUN bekræftede kanter, allerede orienteret som
  #    (child_id, parent_id) ift. our_pc's egen retning — INGEN gætning
  #    om retning i Trin 6.
  # → data.frame(person_id, tng_id, child_id, parent_id, rolle,
  #              neighbor_person_id, neighbor_tng_id, familie_detalje)
}
```

Genbruger eksisterende pure functions fra `06-compare.R`
(`derive_our_pc`, `reshape_tng_children`) — ingen duplikeret logik.
Ægtefælle-parameteren (`our_pairs`) er fjernet fra signaturen, da den ikke
bruges (beslutning #2).

`familie_detalje` er en fast skabelon: `sprintf("%s (person %d, TNG %s) er
auto-matchet og bekræfter TNG-relationen til kandidat %s", rolle_label,
neighbor_person_id, neighbor_tng_id, tng_id)`, fx *"forælder (person 482,
TNG I93) er auto-matchet og bekræfter TNG-relationen til kandidat I117"*.

### Ændringer i `run-pipeline.R`

- Flyt `our_pc`/`our_attr`/`tngc`-beregning op til lige efter Trin 1+2
  (`our_pairs` udgår, se ovenfor).
- Indsæt Trin 4b mellem Trin 4 og Trin 5.
- Trin 5's `rq`-konstruktion venstre-joiner corroboration-kolonner
  (aggregeret pr. `(person_id,tng_id)`, se arkitektur-diagram) før
  `write.csv(rq, rq_csv)`.
- Fase 2 (blokeret): Trin 6-kaldet til `compare_parent_child()` udvides med
  `corrob_edges`-parameteren, læst fra `data/tng-corroboration.csv` hvis den
  findes (fail-closed: mangler filen, er `corrob_edges` tom, og alt
  rapporteres som almindelig `enig` — samme idiom som eksisterende
  `if (file.exists(rq_csv))`-mønster for review-køen i Trin 5).

### Ændringer i `06-compare.R` (Fase 2, blokeret)

- `compare_parent_child()` får ny valgfri parameter `corrob_edges = NULL`.
  Inde i den eksisterende "our edges -> TNG"-løkke: hvis `hit` er TRUE OG
  `(our_pc$child_id[i], our_pc$parent_id[i])` findes i `corrob_edges`, sæt
  `kategori <- "enig_via_matching"` i stedet for `"enig"`. Ingen ekstern
  wrapper, ingen afhængighed af outputkolonner der ikke findes.

### Ændringer i `07-report.R` (Fase 2, blokeret)

- `enig_via_matching` føjes til den eksisterende tal-only opsummering
  (samme sted som `enig`/`uden_for_scope` i dag).

## Test

**`tests/testthat/test-04b-corroboration.R`** (rettet lokation — der findes
allerede en testthat-suite i `tests/testthat/` kørt via `run-tests.R`; en fil
under `R/tng-qa/` ville aldrig blive opdaget):

1. Auto-matchet far + TNG-graf bekræfter far-slot → kant med
   `rolle="forælder"`, korrekt `(child_id,parent_id)`-orientering.
2. Auto-matchet barn + TNG-graf bekræfter barn-slot → `rolle="barn"`,
   **omvendt** `(child_id,parent_id)`-orientering ift. test 1 (kandidaten er
   her forælderen) — dette er testen der fanger den retnings-fejl Codex
   fandt i det oprindelige design.
3. Auto-matchet nabo, men TNG-graf bekræfter IKKE → ikke i output (forskellen
   mellem de 253 og de 133 fra baggrunds-tallene).
4. Auto-matchet nabo via `konfidens="omstridt"`-relation → ikke i output,
   selvom TNG-grafen ellers ville bekræfte den.
5. Ingen auto-matchet nabo overhovedet → ikke i output.
6. To corroborerende naboer for samme `(person_id,tng_id)` → én aggregeret
   review-kø-række, ikke to duplikerede rækker.

**`tests/testthat/test-06-compare-corroboration.R`** (Fase 2):

7. `compare_parent_child(..., corrob_edges=<kant>)` relabel'er kun den
   præcise kant til `enig_via_matching`; en anden parent-child-række for
   samme `person_id` (fx et andet barn) forbliver `enig`.
8. `corrob_edges=NULL` eller tom data.frame → identisk output til det
   nuværende `compare_parent_child()` uden parameteren (bagudkompatibilitet).
9. Rapport-rendering (`render_report()`) lækker aldrig `familie_detalje`
   eller person-id'er for `enig_via_matching` — kun et tal, samme som
   eksisterende `enig`-håndtering.

## Ud af scope (eksplicit, YAGNI)

- **Kandidat-generering for `none`-tier personer** via familie-graf-hints.
  Reel værdi, men en markant større feature (candidate generation, ikke
  annotation af eksisterende kandidater) — naturlig fremtidig udvidelse.
- **Ægtefælle-corroboration.** 0 hits i reelle data i dag; kodesti
  implementeres ikke.
- **Multi-hop propagation** (bedsteforældre, søskende, iterative runder).
  Vurderet i tilgangs-diskussionen som for kompleks ift. dokumenteret
  gevinst — se "Tilgang 3" i brainstorm-dialogen.
- **Ændring af `auto_cutoff`/`ambiguity_margin`/`review_cutoff`.** Uændret;
  afhænger af det udestående håndlabelte facit-sæt (separat arbejde).
- **Adopteret/pleje/stedbarn som corroboration-kilde.** `derive_our_pc()`
  filtrerer i dag literalt på `rolle=="barn"` — denne feature arver den
  begrænsning fremfor at udvide den, for at holde ændringen fokuseret.
- **Ny repo-bred retention/adgangs-politik for git-ignorerede lokale
  QA-filer.** Findes ikke i dag for de tre eksisterende filer; opfindes ikke
  isoleret for denne fjerde.
- **Provenance/versionering af corroboration på tværs af kørsler** (se
  §Risici) — samme kendte begrænsning som H2 (review-kø-persistens);
  løses ikke her.

## Risici / åbne punkter

- **Determinisme på tværs af kørsler (accepteret risiko, ikke løst her):**
  corroboration beregnes fra bunden hver kørsel. Hvis TNG-dump eller vores DB
  ændres mellem kørsler, kan et tidligere corroboration-bekræftet par miste
  sin støtte i en senere kørsel — `tng-corroboration.csv` overskrives, så
  historikken for *hvorfor* et allerede-bekræftet par blev bekræftet, tabes.
  Samme kendte begrænsning som review-kø-persistens-problemet (H2,
  `docs/tng-qa-koersel.md`). Løses ikke af denne feature.
- **`accepted_crosswalk()` inkluderer også `ny-id`-afgørelser.** Hvis
  reviewer vælger `ny-id` for et corroboration-støttet par, matcher det nye
  `tng_id` ikke længere `tng-corroboration.csv`-rækken → relabeling springes
  automatisk over (falder tilbage til almindelig `enig`-vurdering). Korrekt
  adfærd, ingen særhåndtering nødvendig.
- **Ydelse:** ingen særskilt optimering — datamængden (963 personer, 658
  review-par) er lille nok til at de samme per-par R-løkker der allerede
  bruges i `06-compare.R` er tilstrækkelige. Ikke vurderet som en reel risiko
  ved denne skala.

## Codex-review-fund indarbejdet

To uafhængige Codex-reviews (2026-07-01) af den oprindelige version af denne
spec fandt fem højt-prioriterede fejl, som alle er verificeret direkte mod
kildekoden (ikke blot antaget korrekte) og indarbejdet ovenfor:

1. `parent_id` er ikke en kolonne i `compare_parent_child()`s output →
   post-hoc-wrapper-designet var uimplementerbart. **Rettet:** flyttet
   relabeling ind i `compare_parent_child()`s egen løkke (beslutning #4).
2. `merge_review_decisions()` nøgles kun på `person_id` → kan silently
   acceptere ureviewede kandidater. **Rettet:** ny blokerende forudsætning
   for Fase 2 (§Forudsætninger); Fase 1 er upåvirket.
3. `data/tng-corroboration.csv` var faktisk ikke git-ignoreret trods
   påstand om det modsatte. **Rettet:** eksplicit handling i
   beslutning #5.
4. Foreslået teststi (`R/tng-qa/test-*.R`) ville aldrig blive kørt —
   der findes en `tests/testthat/`-suite. **Rettet:** §Test.
5. `konfidens` (herunder `omstridt`) blev ignoreret i corroboration-kilden.
   **Rettet:** beslutning #3.

Øvrige fund (925→963-tal, boolean→tre-tilstands status, aggregering ved
flere naboer, "sikre" auto-matches er overformuleret) er også indarbejdet.
Fund vurderet som scope-creep for denne spec — ny retention-politik,
provenance/versionering på tværs af kørsler, ydelsesoptimering ved nuværende
skala — er eksplicit afvist med begrundelse i §"Ud af scope"/§"Risici".
