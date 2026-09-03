# DAA 1939 Legacy-Anchor Repair Design

## Formål

To baseline-poster har forurenede, maskinelt afledte source spans, selv om de tilsvarende materialiserede poster har korrekte PDF- og Calamari-grænser. En menneskelig, hashbundet beslutning skal kunne knytte baseline-posten til den korrekte eksisterende, ejerløse source record uden at omskrive eller skjule det gamle anchor.

Designet gælder kun:

- Margrethe `c52df82f-0cd9-4c66-ab76-8a429df0124f`: stale span `[50370,50568)`, korrekt target `record-9bd09532-097b-49e1-aa99-14bef66588d6` med span `[49214,49537)`.
- Iwen `6bfbce43-740d-49b1-9b4b-1aa2e9b17266`: stale span `[182918,183074)`, korrekt target `record-07204254-7bc5-4754-bcd2-68a1c79408c5` med span `[182918,183021)`.

De tidligere accepterede Bertram- og Johannes-targets er korrekte og må ikke invalideres eller få ekstra ejere.

## Beslutningskontrakt

`apply_reconciliation_decisions_1939.py` får beslutningstypen `repair_legacy_anchor`. Et beslutningsobjekt har præcis disse felter:

```json
{
  "baseline_record_key": "baseline-record-key",
  "decision_kind": "repair_legacy_anchor",
  "selected_new_record_key": "record-key",
  "stale_source_span": {"char_from": 0, "char_to": 1},
  "selected_new_source_span": {"char_from": 0, "char_to": 1},
  "discarded_source_spans": [
    {"char_from": 0, "char_to": 1}
  ],
  "reason": "neighbor_record_contamination"
}
```

Beslutningsdokumentet bruger den eksisterende lukkede 1939-kontrakt og bindes til v31-reconciliation-SHA `ee37434d78057088f0b20f16a642dee82e24875c02ff9d8dc1b1b538cb6ee725`, baseline-SHA `eb52ee25c02866ce4b095a3c53610fea49913c3c87941fed58d984d0bab9f8f0` og Calamari-SHA `020123a3588dacf80705a22fb021ab4f5da97b8de202e8664304ca01f9a6da37`. Reviewer og batch registreres som ved andre menneskelige reconciliation-beslutninger.

## Fail-closed preconditions

Interpreteren accepterer kun beslutningen, når alle følgende forhold er sande:

- baseline-key findes præcis én gang, er `unresolved`, har tom `matches`, har et gyldigt `source_span`, og dette span er byte-identisk med `stale_source_span`;
- baseline-postens `unresolved_reason` er `unique_exact_narrative_outside_new_record`;
- target-key findes præcis én gang, er `unmatched_new_review`, har `baseline_record_keys: []`, og targetets span er byte-identisk med `selected_new_source_span`;
- targetet er ikke valgt, annoteret eller berørt af en anden beslutning i samme batch;
- reason er præcis `neighbor_record_contamination`;
- `discarded_source_spans` er en ikke-tom, sorteret, ikke-overlappende liste, der er præcis den geometriske mængdeforskel `stale_source_span - selected_new_source_span`;
- hvert span har heltalskoordinater, `0 <= char_from < char_to`, og der findes ingen ukendte felter;
- beslutningens reconciliation-, baseline- og Calamari-hashes matcher inputbytes præcist.

Manglende, ekstra, duplikerede, stale eller geometrisk inkonsistente værdier afvises. Interpreteren må ikke gætte mål ud fra navn, nærhed eller overlap.

## Output og provenance

Den accepterede baseline-post beholder sit oprindelige `source_span` som historisk evidens og får:

- én syntetiseret match-kant til targetet med `geometry_relation: "human_repaired_legacy_anchor"`;
- `selected_new_record_key`;
- `disposition: "accepted_carryover"`;
- `reconciliation_basis: "human_repaired_legacy_anchor"`;
- `reviewed_by` og `decision_batch`;
- et `legacy_anchor_repair`-objekt med stale span, selected target span, discarded spans og reason.

Targetet får baseline-key som sin eneste ejer og `accepted_carryover`. Ingen anden baseline- eller new-entry må ændres. Det oprindelige baseline-anchor slettes ikke, og raw OCR, baseline-data, materialization, ledger og tidligere beslutningsartefakter forbliver uændrede.

## Anvendelse og forventet successor

En ny beslutningsfil anvendes direkte på v31. Den indeholder præcis de to visuelt verificerede repairs i samme batch. Resultatet skrives til nye eksklusive v32-artefakter; v31 overskrives ikke.

Forventet dispositionsændring:

- accepted carryovers: `143 -> 145`;
- unresolved baseline: `49 -> 47`;
- unmatched new: `92 -> 90`;
- retired duplicate: fortsat `1`;
- retired fragment: fortsat `1`;
- publication/reconciliation gate: fortsat `NO-GO`.

Det godkendte paired-review-manifest er bundet til v31 og bliver derfor historisk efter repair. Det regenereres fra v32 før yderligere batches; gamle bytes bevares.

## Afgrænsning

- Den afviste generiske `unique_exact_narrative_partial_overlap`-adfærd implementeres ikke.
- Korrekte source cuts, omissions, materialization records, Bertram-beslutningen og Johannes-beslutningen ændres ikke.
- Beslutningen opretter ingen person, identitet eller databasepost og giver ingen automatisk godkendelse.
- En fremtidig legacy-anchor repair kræver samme fulde menneskelige evidens og kan ikke udledes automatisk af denne batch.

## Test og audit

Unit tests skal dække den gyldige disjunkte Margrethe-geometri og den delvist overlappende Iwen-geometri samt afvisning af:

- forkert source disposition eller unresolved reason;
- eksisterende/ghost/duplikeret target-owner;
- stale eller forkert baseline-/target-span;
- tom, usorteret, overlappende eller ufuldstændig discarded-liste;
- forkert reason, ukendte felter eller genbrugt target;
- stale reconciliation-, baseline- eller Calamari-hash;
- tab af repair-metadata eller disposition i en senere beslutningsbatch.

Artefaktauditen skal bevise eksakt ændret set på to baseline- og to new-entry-objekter, ene-ejerskab, deep preservation af alle andre objekter, embedded/standalone report-identitet, forventede counts, uændrede beskyttede inputhashes og fortsat `NO-GO`. Fokuserede tests og hele scriptsuiten skal bestå.
