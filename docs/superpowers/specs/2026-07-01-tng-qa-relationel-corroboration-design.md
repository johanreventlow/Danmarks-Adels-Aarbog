# Design: Relationel corroboration i TNG-QA review-køen

> Status: godkendt-til-plan · 2026-07-01 · udspringer af `docs/superpowers/specs/2026-06-29-tng-qa-crosswalk-design.md`

## Formål

TNG-QA-pipelinen (`R/tng-qa/`) matcher vores 925 personer mod TNG-dumpet
udelukkende på attributter (navn/dato/køn) — se beslutning A i
`2026-06-29-tng-qa-crosswalk-design.md`: *"Matching ALDRIG på relationer."*
Konsekvens: 658 par lander i `review`-tier, mange fordi det uniforme
efternavn "Reventlow" gør navnesignalet svagt.

Denne feature bruger **allerede sikre (`auto`-tier) matches** til at berige
review-køen med kontekst: "denne kandidats far/mor/barn er allerede
auto-matchet til TNG-person X — passer det med TNG's egen familie-graf?".
Det er et **beslutningsstøtte-signal til den menneskelige reviewer**, ikke en
ændring af matching-algoritmen.

**Eksplicit ikke-mål:** at ændre `score_pair()`/`assign_tiers()` i
`04-match.R`, at auto-promovere noget til `auto`-tier, eller at foreslå helt
nye kandidater for personer der i dag har `none`-tier. Se §"Ud af scope".

## Baggrund — verificerede tal (2026-07-01, mod 2026-06-30-kørslens data)

En engangs read-only analyse af `data/tng-crosswalk.csv` + `data/tng.duckdb`
+ vores `family_member` gav:

| Signal | Antal review-par | Unikke personer |
|---|---|---|
| Review-par i alt | 658 | 382 |
| ...med auto-matchet **ægtefælle** som nabo | 0 | 0 |
| ...med auto-matchet **forælder/barn** som nabo | 253 | 148 |
| ...hvor kandidatens TNG-id **faktisk** hænger sammen med naboens auto-match i TNG-graf | **185** | **133** |

Ægtefælle-corroboration bidrager intet i praksis (review-tier-personer har
sjældent en identificeret ægtefælle endnu) — kun forælder/barn er
implementeret (se komponent-afsnittet). De 253→185 forskellen er vigtig: en
auto-matchet nabo er IKKE i sig selv støtte — det skal verificeres at
kandidatens TNG-id faktisk optræder som forælder/barn til naboens TNG-id i
TNG's egen graf.

## Centrale beslutninger

1. **Rører ikke `04-match.R`.** Scoring/tier-tildeling er kalibreret
   (bootstrap, 2026-06-30) og uafhængig af denne feature. Corroboration
   beregnes i et nyt trin **4b**, EFTER Trin 4 (fersk `crosswalk`) og FØR
   Trin 5 (`merge_review_decisions`) — rækkefølgen er kritisk: Trin 5 flipper
   allerede nogle `review`-rækker til `accepted`/`afvist` baseret på sidste
   køs afgørelser, og corroboration skal beregnes mens de par stadig er
   `review`-tier, ellers findes de aldrig.
2. **Kun forælder/barn, ikke ægtefælle.** Ægtefælle-logik implementeres ikke
   nu — 0 hits i reelle data er ubrugt kode (YAGNI). Let at tilføje senere
   hvis flere ægtefæller identificeres.
3. **Cirkularitet håndteres eksplicit, ikke ignoreres.** Et par der bekræftes
   (via review-kø `afgoerelse=bekræft`) delvist på baggrund af
   forælder/barn-corroboration vil i Trin 6's `compare_parent_child()` altid
   vise `enig` på netop den kant der gav støtten — det er ikke uafhængig
   evidens. Den **præcise** kant (og kun den) relabel'es til en ny kategori
   `enig_via_matching`. Alle andre relationer for samme person (andre børn,
   ægteskaber) forbliver fuldt uafhængige `enig`-vurderinger.
4. **Persisteret som separat fil, ikke genberegnet i Trin 6.** Trin 6 kan
   ikke selv afgøre *hvilken* af flere mulige kanter for en person der var
   corroboration-kilden. `data/tng-corroboration.csv` (ny, git-ignoreret som
   de tre eksisterende output-filer) gør relabeling deterministisk og
   testbar uafhængigt af Trin 6.
5. **Ingen ny PII-eksponering.** `familie_detalje`-friteksten (med
   person-id'er) lander kun i de allerede git-ignorerede lokale CSV'er
   (`tng-review-queue.csv`, `tng-corroboration.csv`) — samme
   git-ignore-begrundelse som eksisterende output-filer. Den committede
   markdown-rapport får kun en **tal-kun** kategori `enig_via_matching`,
   samme mønster som eksisterende `enig`/`uden_for_scope` (§"GDPR PII-gate" i
   `docs/tng-qa-koersel.md`). Relabeling sker på `g$our_pc` (den GDPR-gatede
   version fra `gate_inputs()`), ikke den rå `our_pc`.
6. **Ikke afhængig af udestående kalibrering.** Håndlabelt facit-sæt og
   `review_cutoff`-kalibrering (se "Pre-prod-run follow-ups" i
   `docs/tng-qa-koersel.md`) er stadig udestående, men denne feature ændrer
   ikke hvad der tæller som `review`/`auto` — den beriger kun review-arbejdet
   uanset hvor godt kalibreret cutoff'et er. Kan bygges parallelt.

## Arkitektur — pipeline-ændring

```
Trin 1 (TNG→DuckDB) ─┐
Trin 2 (Supabase)   ─┴─► our_pairs/our_pc/tngc beregnes HER (flyttet op fra
                          Trin 6 — afhænger kun af ours/tng_families/tng_children,
                          ikke af crosswalk). Ren omrokering, ingen logikændring.

Trin 3-4 (normalisér+match) → crosswalk (tier ∈ auto/review/none), FERSK

Trin 4b (NY): family_corroboration(crosswalk, our_pairs, our_pc,
              tng_families, tngc)
  → data/tng-corroboration.csv (KUN de 133 faktisk bekræftede par:
    person_id, tng_id, neighbor_person_id, rolle, neighbor_tng_id)

Trin 5 (review-merge, UÆNDRET i sig selv):
  → tng-review-queue.csv beriges (venstre-join) med
    familie_stoette (TRUE/FALSE) + familie_detalje (fritekst) FØR skrivning.
    Mennesket redigerer stadig kun afgoerelse/ny_tng_id.

Trin 6 (sammenlign+rapport):
  compare_parent_child()-rækker med kategori=="enig" slås op mod
  tng-corroboration.csv på {child_id,parent_id} == {person_id,neighbor_person_id}.
  Match → kategori <- "enig_via_matching" (kun den ene kant).
  Rapporten opsummerer enig_via_matching som tal, ligesom enig/uden_for_scope.
```

## Komponenter

### `R/tng-qa/04b-corroboration.R` (ny fil)

```r
family_corroboration <- function(crosswalk, our_pairs, our_pc,
                                  tng_families, tngc) {
  # 1. auto_map: navngivet vektor person_id -> tng_id, KUN tier=="auto"
  # 2. for hver review-tier (person_id, tng_id): find naboer via
  #    our_pc (parent_id/child_id af person_id) der har en auto_map-entry
  # 3. for hver nabo: slå op i tngc (reshape_tng_children) om candidate
  #    tng_id faktisk optræder som far/mor/barn til naboens auto-tng-id
  # 4. returnér KUN bekræftede rækker (ikke "har nabo, men bekræftes ikke")
  # → data.frame(person_id, tng_id, familie_stoette=TRUE,
  #              familie_detalje, neighbor_person_id, rolle, neighbor_tng_id)
}
```

Genbruger eksisterende pure functions fra `06-compare.R`
(`our_spouse_pairs`, `derive_our_pc`, `reshape_tng_children`) — ingen
duplikeret logik.

`familie_detalje` er en fast skabelon, ikke fri tekst, så reviewer altid
kan afkode den samme måde: `sprintf("%s (person %d, TNG %s) er auto-matchet
og bekræfter TNG-relationen til kandidat %s", rolle_label, neighbor_person_id,
neighbor_tng_id, tng_id)`, fx *"forælder (person 482, TNG I93) er
auto-matchet og bekræfter TNG-relationen til kandidat I117"*. `rolle_label`
er `"forælder"` eller `"barn"` — samme værdi som gemmes i `rolle`-kolonnen.

### Ændringer i `run-pipeline.R`

- Flyt `our_pairs`/`our_pc`/`our_attr`/`tngc`-beregning op til lige efter
  Trin 1+2.
- Indsæt Trin 4b mellem Trin 4 og Trin 5.
- Trin 5's `rq`-konstruktion venstre-joiner corroboration-kolonner før
  `write.csv(rq, rq_csv)`.

### Ændringer i `06-compare.R`

- `compare_parent_child()` uændret i sin kerne-logik.
- Ny lille wrapper (fx `relabel_corroborated()`) der tager `pc`-output +
  `tng-corroboration.csv`-indholdet og relabel'er de præcise kanter.
  Kaldes fra `run-pipeline.R`'s Trin 6, ikke inde i `compare_parent_child()`
  selv (holder funktionen ren og testbar uden fil-I/O).

### Ændringer i `07-report.R`

- `enig_via_matching` føjes til den eksisterende tal-only opsummering
  (samme sted som `enig`/`uden_for_scope` i dag).

## Test (`R/tng-qa/test-04b-corroboration.R`, testthat)

Ingen eksisterende testfil for denne pipeline i dag — denne feature får sin
egen, da den er data-korrekthed-kritisk (forkert join-retning ville
fejl-tagge cirkularitet eller give reviewer misvisende støtte-signal):

1. Auto-matchet far + TNG-graf bekræfter far-slot → `familie_stoette=TRUE`,
   `rolle="forælder"`.
2. Auto-matchet barn + TNG-graf bekræfter barn-slot → `TRUE`,
   `rolle="barn"`.
3. Auto-matchet nabo, men TNG-graf bekræfter IKKE (kandidatens tng_id står
   ikke som far/mor/barn til naboens tng_id) → ikke i output (dette er
   forskellen mellem de 253 og de 133 fra baggrunds-tallene).
4. Ingen auto-matchet nabo overhovedet → ikke i output.
5. `relabel_corroborated()` rammer kun den præcise `{child,parent}`-kant;
   en anden parent-child-række for samme `person_id` (fx et andet barn)
   forbliver `enig`.
6. Rapport-rendering (`render_report()`) lækker aldrig `familie_detalje`
   eller person-id'er for `enig_via_matching` — kun et tal, samme som
   eksisterende `enig`-håndtering.

## Ud af scope (eksplicit, YAGNI)

- **Kandidat-generering for `none`-tier personer** via familie-graf-hints
  (fx "denne uidentificerede person har et auto-matchet barn — kig i TNG's
  familie til det barn efter en ukendt forælder"). Reel værdi, men en
  markant større feature (candidate generation, ikke annotation af
  eksisterende kandidater) — naturlig fremtidig udvidelse.
- **Ægtefælle-corroboration.** 0 hits i reelle data i dag; kodesti
  implementeres ikke.
- **Multi-hop propagation** (bedsteforældre, søskende, iterative runder).
  Vurderet i tilgangs-diskussionen som for kompleks ift. dokumenteret
  gevinst — se "Tilgang 3" i brainstorm-dialogen.
- **Ændring af `auto_cutoff`/`ambiguity_margin`/`review_cutoff`.** Uændret;
  afhænger af det udestående håndlabelte facit-sæt (separat arbejde).

## Risici / åbne punkter

- **Determinisme på tværs af kørsler:** corroboration beregnes fra bunden
  hver kørsel (som resten af pipelinen). Hvis TNG-dump eller vores DB ændres
  mellem kørsler, kan et tidligere corroboration-bekræftet par miste sin
  støtte i en senere kørsel — `tng-corroboration.csv` overskrives, så
  historikken for *hvorfor* et allerede-bekræftet par blev bekræftet, tabes
  på samme måde som review-kø-persistens-problemet (H2, dokumenteret
  udestående i `docs/tng-qa-koersel.md`). Løses ikke af denne feature, men
  arver samme kendte begrænsning.
- **`accepted_crosswalk()` inkluderer også `ny-id`-afgørelser** (reviewer
  overstyrer til et andet TNG-id). Hvis reviewer vælger `ny-id` for et
  corroboration-støttet par, matcher det nye tng_id højst sandsynligt ikke
  længere `tng-corroboration.csv`-rækken → relabeling springes automatisk
  over (falder tilbage til almindelig `enig`-vurdering). Korrekt adfærd,
  ingen særhåndtering nødvendig.
