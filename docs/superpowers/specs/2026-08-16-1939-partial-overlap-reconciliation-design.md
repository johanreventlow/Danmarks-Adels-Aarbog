# DAA 1939 Partial-Overlap Reconciliation Design

> **Status: SUPERSEDED / NO-GO.** Replay viste, at to unikke baseline-narrativer var forurenet med tekst fra naboposter. Generisk partial-overlap-routing ville derfor skabe falske ejerskabskanter mod korrekt accepterede targets. Designet erstattes af `2026-08-17-1939-legacy-anchor-repair-design.md`.

## Formål

Når et baseline-narrativ forekommer præcis én gang i den hashbundne Calamari-tekst, men kun overlapper en ny post delvist, må reconciliatoren ikke kassere den positive kildeevidens. Den skal bevare overlaprelationen som en menneskekrævende boundary review uden at godkende identitet, ejerskab eller grænse automatisk.

## Valgt løsning

`reconcile_source_records_1939.py` udvides, så et unikt, eksakt narrativ med nul fuldt indeholdende nye poster undersøges for strengt geometrisk overlap med de aktive nye source records.

- Ingen overlap: posten forbliver `unresolved` med den eksisterende årsag.
- Ét overlap: posten får én eksisterende match-kant med den geometriske relation `old_inside_new`, `new_inside_old` eller `partial_overlap`; dispositionen beregnes af den eksisterende logik som `boundary_change_review`.
- Flere overlap: alle overlapkanter bevares, og den eksisterende logik klassificerer posten som `split_review` eller `split_merge_review` afhængigt af konkurrerende ejerskab.
- En target med flere baseline-ejere forbliver `merge_review`; ingen ejer fjernes eller vælges automatisk.

Kun positivt tegninterval-overlap (`new.char_from < old.char_to` og `new.char_to > old.char_from`) må skabe en kant. Nærhed, ens navne, normaliseret tekst eller præsentationsdata må ikke skabe reconciliation-kanter.

## Kildebinding og provenance

Den eksisterende raw reconciliation forbliver bundet til baseline-, Calamari-, materialization- og ledger-bytes. Overlapkanter afledes kun af spans, som allerede er udledt fra det unikke, eksakte narrativ og de aktive materialiserede poster.

En overlapkant er kun review-routing. Den må ikke ændre `accepted_carryover`, oprette personer eller gøre publication-gaten grøn. En senere menneskelig `accept_boundary_change`-beslutning skal fortsat bindes til den eksakte reconciliation-SHA og vælge præcis ét eksisterende target.

## Replay og artefakter

Efter kodeændringen genbygges raw reconciliation fra den eksisterende korrigerede Ditlev-materialization og append-only ledger. Alle tidligere beslutningsbatches genafspilles sekventielt med nye reconciliation-hashbindinger; beslutningspayload, reviewer, batch, baseline-hash og Calamari-hash bevares.

Replayet skal bevare:

- det eksakte sæt af 143 accepterede baseline-carryovers fra v31;
- én `retired_duplicate` og én `retired_fragment`;
- alle valgte target keys og historiske beslutningsmetadata;
- alle unrelated baseline- og new-entry-data, bortset fra de forventede nye overlapkanter og afledte dispositionsændringer i den hidtil uafklarede kø.

Den nye raw/replayed reconciliation får nye, eksklusive artefaktnavne. v31 og alle tidligere artifacts overskrives ikke.

## Fail-closed validering

Implementeringen skal afvise eller bevare reviewtilstand ved:

- ugyldige, manglende eller tomme spans;
- overlap med flere nye poster;
- target med flere baseline-ejere;
- stale reconciliation- eller kildehashes;
- forsøg på at acceptere et target, der ikke findes som match i den aktuelle reconciliation;
- replay-drift i tidligere accepterede eller pensionerede baseline keys.

Ingen proximity- eller literal-name-kandidat fra det separate review-manifest må importeres til raw reconciliation.

## Testdesign

Reconciliatorens tests skal dække:

- unikt narrativ med ét delvist overlap bliver `boundary_change_review`;
- geometrirelationerne beregnes korrekt;
- nul overlap forbliver `unresolved`;
- flere overlap bliver split-review og bevarer alle kanter;
- konkurrerende baseline-ejere bliver merge-review;
- nærhed uden overlap skaber ingen kant;
- eksisterende exact-span, fully-contained narrative og prior-positive-span adfærd er uændret.

Efter replay kræves en deterministisk audit af accepterede key-sæt, ejerskab, dispositioner, rapportidentitet, hashes og deep preservation. Den fulde scriptsuite skal bestå før næste visuelle beslutningsbatch.
