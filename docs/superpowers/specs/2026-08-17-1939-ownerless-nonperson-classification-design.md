# DAA 1939 Ownerless Non-Person Classification Design

## Formål

Tre visuelt og literal-verificerede, ejerløse source records er fortsat
`unmatched_new_review`, selv om de ikke repræsenterer personer: én strukturel
Gallentin-fortælling og to krydshenvisninger. Krydshenvisningerne har allerede
en præcis menneskelig `human_annotation`, men interpreterens disposition-logik
kan ikke gøre annotationen resolved.

Designet tilføjer to eksplicitte, source-record-only beslutninger. De må ikke
oprette en baseline-ejer, person eller identitet.

## Beslutningskontrakter

En eksisterende annotation kan afsluttes med:

```json
{
  "decision_kind": "resolve_annotated_cross_reference",
  "new_record_key": "record-key",
  "new_source_span": {"char_from": 0, "char_to": 1},
  "reason": "human_verified_cross_reference"
}
```

En strukturel fortælling kan accepteres med:

```json
{
  "decision_kind": "accept_structural_context",
  "new_record_key": "record-key",
  "new_source_span": {"char_from": 0, "char_to": 1},
  "reason": "human_verified_structural_narrative"
}
```

Begge bruger den eksisterende lukkede beslutningsfil med reviewer, batch og
hashbinding til den eksakte reconciliation-, baseline- og Calamari-forgænger.

## Fail-closed preconditions

Begge targets skal findes præcis én gang, være `unmatched_new_review`, have
`record_kind: "unclassified"`, et gyldigt source span identisk med det
deklarerede, `baseline_record_keys: []` og nul afledte forward-ejere. Targetet
må ikke genbruges af en anden beslutning.

`resolve_annotated_cross_reference` kræver desuden præcis:

```json
{
  "new_record_key": "samme target-key",
  "record_kind": "cross_reference",
  "person_creation": "forbidden_without_separate_evidence"
}
```

under `human_annotation`, samt nonempty string `reviewed_by` og
`decision_batch` fra den oprindelige annotation. Targetet må ikke allerede
have classification/resolution-metadata.

`accept_structural_context` kræver, at targetet ikke har human annotation,
reviewer, batch, classification basis eller anden menneskelig metadata.

Forkert reason, manglende eller ekstra beslutningsfelter, stale hashes/spans,
ukendte keys, ejere, annotation drift eller target reuse afvises.

## Output og provenance

En krydshenvisning beholder den oprindelige annotation, reviewer og batch og
får:

- `record_kind: "cross_reference"`;
- `disposition: "accepted_cross_reference"`;
- `classification_basis: "human_confirmed_existing_cross_reference_annotation"`;
- `resolved_by` og `resolution_batch` fra den nye beslutningsfil.

En strukturel post får:

- `record_kind: "structural_context"`;
- `disposition: "accepted_structural_context"`;
- `classification_basis: "human_verified_structural_context"`;
- `reviewed_by` og `decision_batch`.

Begge forbliver ejerløse. `accepted_cross_reference` tilføjes til resolved
dispositions. Senere batches skal validere og bevare begge klassifikationers
metadata fail closed. Eksisterende maskinelt accepteret strukturel kontekst
uden den nye classification basis forbliver kompatibel og uændret.

## Første anvendelse

Beslutningsfilen bindes til v45 SHA
`249d7e3ed158ee831845d0faac361366c60db9d2b9e08312886b99654fc6a342`,
baseline-SHA
`eb52ee25c02866ce4b095a3c53610fea49913c3c87941fed58d984d0bab9f8f0`
og Calamari-SHA
`020123a3588dacf80705a22fb021ab4f5da97b8de202e8664304ca01f9a6da37`.

Den klassificerer:

- structural: `record-c2eff948-485c-421f-9f41-1a7c8650d8c0`, span
  `[32503,33941)`;
- cross-reference: `record-0df24f62-3f1d-42f1-b863-4f0e443c1ad4`, span
  `[75906,75953)`;
- cross-reference: `record-d6346df9-b841-4504-826c-b018ef7da558`, span
  `[92073,92121)`.

Forventet v46:

- unresolved baseline: fortsat `6`;
- unmatched new: `8 -> 5`;
- accepted structural context: `5 -> 6`;
- accepted cross-reference: `0 -> 2`;
- reconciliation gate: fortsat `NO-GO`.

## Afgrænsning og test

Beslutningerne ændrer ingen baseline, person, identitet, relation, database,
raw OCR eller produktionsimport. De gælder ikke embedded fragments eller
segmentation-/identity-klynger.

TDD skal dække gyldig enkelt- og blandet batch, exact output og report counts,
alle preconditions, target reuse og stale hashes. Senere-batch-tests skal
afvise malformed/manglende klassifikationshistorik og bevare valide poster.
Artefaktaudit skal bevise 0 baseline- og præcis 3 new-entry-ændringer, fortsat
nul ejere, deep preservation, report identity, literal evidens og `NO-GO`.
