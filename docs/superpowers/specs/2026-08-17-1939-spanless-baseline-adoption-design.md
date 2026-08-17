# DAA 1939 Spanless-Baseline Adoption Design

## Formål

Tolv unresolved baseline-poster uden `source_span` er nu entydigt fundet i
Calamari og på komplette PDF-sider. Hver svarer til præcis én ejerløs
new-entry, som tidligere blev accepteret som
`accepted_genuinely_new_source_record`, fordi den spanløse baseline ikke kunne
deltage i den maskinelle reconciliation.

Poster og kildespænd er korrekte; det manglende led er ejerskab. En ny,
hashbundet menneskelig beslutning skal kunne overtage en allerede accepteret
ejerløs source record til én spanløs baseline uden at oprette eller
identificere en person og uden at miste den tidligere genuine-new-proveniens.

## Valgt tilgang

`apply_reconciliation_decisions_1939.py` får beslutningstypen
`adopt_genuinely_new_target`. Hver beslutning knytter præcis én spanløs
baseline til præcis én eksisterende new-entry.

Et beslutningsobjekt har præcis disse felter:

```json
{
  "baseline_record_key": "baseline-record-key",
  "decision_kind": "adopt_genuinely_new_target",
  "selected_new_record_key": "record-key",
  "selected_new_source_span": {"char_from": 0, "char_to": 1},
  "reason": "spanless_baseline_exact_source_recovery"
}
```

Beslutningsdokumentet bruger den eksisterende lukkede 1939-kontrakt med
`reviewed_by`, `decision_batch` og source-binding til den præcise forgængers
reconciliation-SHA samt uændrede baseline- og Calamari-hashes. Beslutningen
kan kun oprettes efter literal Calamari-søgning og visuel kontrol af komplette
relevante PDF-sider.

## Fail-closed preconditions

Interpreteren accepterer kun beslutningen, når alle følgende forhold er
sande:

- baseline-key findes præcis én gang, er `unresolved`, har
  `unresolved_reason: "narrative_not_exact"`, har `matches: []`, og mangler
  feltet `source_span` helt;
- baseline-posten har ingen tidligere selected target, reconciliation basis,
  human annotation, reviewer, decision batch eller adoption-metadata;
- target-key findes præcis én gang, har `record_kind: "unclassified"`, er
  `accepted_genuinely_new_source_record` og har `baseline_record_keys: []`;
- den globale forward/reverse owner-audit beviser, at targetet ikke har en
  skjult baseline-ejer;
- targetets gyldige halvt åbne `source_span` er byte-identisk med
  `selected_new_source_span`;
- targetet har præcis
  `acceptance_basis: "human_verified_genuinely_new_source_record"`, nonempty
  string `reviewed_by` og `decision_batch`, og ingen `human_annotation`,
  reconciliation basis, prior-adoption eller anden modstridende metadata;
- baseline og target bruges højst én gang i batchen, og targetet bruges ikke
  af nogen anden decision kind;
- reason er præcis `spanless_baseline_exact_source_recovery`, objektet har
  ingen ukendte felter, og reconciliation-, baseline- og Calamari-hashes
  matcher inputbytes præcist.

Manglende, ekstra, duplikerede eller stale værdier afvises. Navn, nærhed eller
OCR-heuristik kan ikke alene udløse beslutningen; interpreteren gætter hverken
target eller source span.

## Output og provenance

Den accepterede baseline beholder fraværet af `source_span` som historisk
evidens og får:

- én syntetisk match-kant til targetet med
  `geometry_relation: "human_recovered_spanless_baseline"`;
- `selected_new_record_key`;
- `disposition: "accepted_carryover"`;
- `reconciliation_basis: "human_adopted_spanless_baseline"`;
- `reviewed_by` og `decision_batch`;
- `spanless_baseline_recovery` med det valgte target-span og reason.

Targetet får baseline-key som sin eneste ejer og:

- `disposition: "accepted_carryover"`;
- `reconciliation_basis: "human_adopted_spanless_baseline"`;
- den nye `reviewed_by` og `decision_batch`;
- `prior_genuinely_new_acceptance` med den tidligere `acceptance_basis`,
  `reviewed_by` og `decision_batch`.

Den gamle top-level `acceptance_basis` fjernes fra targetet, efter at dens
værdi er flyttet tabsfrit til `prior_genuinely_new_acceptance`. Historiske
v33-v41-artefakter forbliver uændrede, så både den oprindelige beslutning og
den nye overtagelse kan reproduceres.

En senere beslutningsbatch skal validere og bevare hele adoptionen fail closed:
baseline-match, selected target, basis, recovery-metadata, targetets ene ejer,
target-basis og prior-acceptance skal være indbyrdes konsistente. Manglende
eller ændret historik afvises frem for at blive rekalkuleret lydløst.

## Første anvendelse og forventet successor

Den første beslutningsfil bindes til v41 reconciliation-SHA
`59398f7a7f2fe615c83243ce3209ba3d74d11e3a88001fd2edabf142beefe4ae`,
baseline-SHA
`eb52ee25c02866ce4b095a3c53610fea49913c3c87941fed58d984d0bab9f8f0`
og Calamari-SHA
`020123a3588dacf80705a22fb021ab4f5da97b8de202e8664304ca01f9a6da37`.
Den indeholder de 12 visuelt verificerede adoptioner fra Task 4 checkpoint 10
og skriver nye eksklusive v42-/rapportartefakter.

Forventet dispositionsændring:

- accepted carryovers: `156 -> 168`;
- unresolved baseline: `36 -> 24`;
- accepted genuinely-new source records: `70 -> 58`;
- unmatched new: fortsat `9`;
- retired duplicate/fragment: fortsat `1/1`;
- reconciliation gate: fortsat `NO-GO`.

Efter v42 regenereres paired-review-manifestet mod v42, før de næste 12
spanløse baselines gennemgås. Alle gamle manifest-, decision- og
reconciliation-bytes bevares.

## Afgrænsning

- Beslutningen retter source-record-ejerskab; den opretter, sammenlægger eller
  identificerer ikke en fysisk person.
- Den ændrer ingen database, relation, kanonisk person, identity decision,
  raw OCR, source PDF eller produktionsimport.
- Den gælder ikke baselines med source span, targets i
  `unmatched_new_review`, strukturel kontekst, cross-references, delvise
  overlap eller flerparts-klynger.
- Der tilføjes ingen bulkregel, automatisk adoption, generisk reviewmotor eller
  UI. Hver baseline/target-kant forbliver en eksplicit menneskelig decision.

## Test og audit

Test-first implementering skal bevise en gyldig enkeltadoption, flere
uafhængige adoptioner i samme batch og en gyldig senere batch. Negative tests
skal afvise:

- baseline med source span, forkert disposition/reason eller eksisterende
  match/proveniens;
- target med forkert disposition/kind/span, eksisterende eller skjult ejer,
  annotation eller malformed genuine-new-proveniens;
- ukendt eller genbrugt baseline/target, target-reuse på tværs af decision
  kinds, forkert reason og ukendte felter;
- stale reconciliation-, baseline- eller Calamari-hash;
- tab eller modstrid i baseline recovery, target adoption eller indlejret
  prior genuine-new-proveniens i en senere batch.

Artefaktauditen skal bevise eksakt changed set på 12 baseline- og 12
new-entry-objekter, ene-ejerskab, intet opfundet baseline-span, tabsfri
prior-acceptance, deep preservation af alle øvrige objekter,
embedded/standalone report-identitet, forventede counts, uændrede beskyttede
inputhashes, literal Calamari-evidens og fortsat `NO-GO`. Fokuserede tests,
hele scriptsuiten og `git diff --check` skal bestå.
