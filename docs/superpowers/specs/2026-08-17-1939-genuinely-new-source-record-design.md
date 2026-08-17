# DAA 1939 Genuinely-New Source-Record Design

## Formål

Den v32-bundne paired review har identificeret ejerløse 1939-kildeposter, som
ikke svarer til nogen baseline-post, men som visuelt er verificeret som
selvstændige poster i originalen. Reconciliation-interpreteren kan i dag kun
acceptere carryovers, strukturel kontekst og særlige anchor-/retirement-sager.
Derfor kan en korrekt ny kildepost ikke forlade `unmatched_new_review`, og den
samlede reviewkø kan ikke afsluttes.

Designet tilføjer én snæver, menneskelig beslutning for kildeposten alene. Den
opretter eller identificerer ikke en person, ændrer ikke databasen og giver
ingen efterfølgende identitetsbeslutning.

## Valgt tilgang

`apply_reconciliation_decisions_1939.py` får beslutningstypen
`accept_genuinely_new`. Hver beslutning accepterer præcis én allerede
eksisterende new-entry. Beslutningen kan ikke udledes eller masseanvendes og
må kun oprettes efter visuel PDF-kontrol og sammenligning med literal Calamari.

Et beslutningsobjekt har præcis disse felter:

```json
{
  "decision_kind": "accept_genuinely_new",
  "new_record_key": "record-key",
  "new_source_span": {"char_from": 0, "char_to": 1},
  "record_kind": "unclassified",
  "reason": "visually_verified_distinct_source_record"
}
```

Beslutningsdokumentet bruger den eksisterende lukkede 1939-kontrakt med
`reviewed_by`, `decision_batch` og source-binding til den præcise forgængers
reconciliation-SHA samt uændrede baseline- og Calamari-hashes.

## Fail-closed preconditions

Interpreteren accepterer kun beslutningen, når alle følgende forhold er
sande:

- `new_record_key` findes præcis én gang i forgængeren;
- posten er `unmatched_new_review`, har `record_kind: "unclassified"` og har
  `baseline_record_keys: []`;
- den globale forward/reverse owner-audit beviser, at posten ikke har nogen
  skjult baseline-ejer;
- postens `source_span` er et gyldigt halvt åbent interval og er byte-identisk
  med `new_source_span`;
- posten har ingen eksisterende menneskelig annotation, acceptance-metadata
  eller anden beslutning i samme batch;
- `record_kind` og `reason` har præcis værdierne i kontrakten;
- objektet har ingen manglende, ekstra eller duplikerede felter;
- beslutningens reconciliation-, baseline- og Calamari-hashes matcher
  inputbytes præcist.

Ukendte keys, stale spans, eksisterende eller skjulte ejere, strukturel
kontekst, tidligere accepterede poster, genbrug af samme target og stale
source-hashes afvises. Navn, nærhed eller OCR-heuristik kan ikke alene udløse
beslutningen.

## Output og provenance

Den accepterede new-entry beholder sin key, `record_kind` og `source_span` og
får:

- `disposition: "accepted_genuinely_new_source_record"`;
- `acceptance_basis: "human_verified_genuinely_new_source_record"`;
- `reviewed_by` og `decision_batch`.

`baseline_record_keys` forbliver tom. Ingen baseline-entry ændres. Alle andre
new-entries bevares byte-semantisk, og raw OCR, baseline-data, tidligere
reconciliation-artefakter og beslutningsfiler overskrives ikke.

`accepted_genuinely_new_source_record` er en resolved disposition. En senere
beslutningsbatch skal bevare dispositionen og dens provenance i stedet for at
rekalkulere den tilbage til `unmatched_new_review`.

## Første anvendelse og forventet successor

Den første beslutningsfil bindes til v32 reconciliation-SHA
`cc9aaf4926411b3d11cff6f26de9cafdef26479855765a323091a898c70cbc2d`,
baseline-SHA
`eb52ee25c02866ce4b095a3c53610fea49913c3c87941fed58d984d0bab9f8f0`
og Calamari-SHA
`020123a3588dacf80705a22fb021ab4f5da97b8de202e8664304ca01f9a6da37`.
Den indeholder de 12 poster i Task 4 checkpoint 1 og skriver eksklusive
v33-/rapportartefakter.

Forventet dispositionsændring:

- unresolved baseline: fortsat `47`;
- unmatched new: `90 -> 78`;
- accepted genuinely-new source records: `0 -> 12`;
- accepted carryovers: fortsat `145`;
- retired duplicate/fragment: fortsat `1/1`;
- reconciliation gate: fortsat `NO-GO`.

Efter v33 regenereres paired-review-manifestet mod v33, før næste batch
behandles. Historiske manifest- og reconciliation-bytes bevares.

## Afgrænsning

- Beslutningen accepterer en source record, ikke en fysisk person.
- Den opretter ingen databasepost og ændrer ingen identitet, relation,
  kanonisk person eller produktionsimport.
- Den klassificerer ikke posten som person, krydshenvisning eller strukturel
  kontekst ud over det eksisterende `record_kind: "unclassified"`.
- Der tilføjes ingen bulkbeslutning, automatisk kandidatregel, UI eller
  generisk reviewmotor.
- Poster med mulig baseline-ejer eller reel hierarki-/identitetstvivl forbliver
  eksplicit unresolved.

## Test og audit

Test-first implementering skal bevise en gyldig enkeltbeslutning og en gyldig
batch med flere forskellige targets samt afvisning af:

- ukendt, duplikeret eller genbrugt new key;
- forkert disposition eller `record_kind`;
- deklareret, skjult, malformed eller duplikeret baseline-ejer;
- stale eller ugyldigt source span;
- forkert reason, manglende eller ukendte felter;
- eksisterende menneskelig metadata eller tidligere acceptance;
- stale reconciliation-, baseline- eller Calamari-hash;
- tab af disposition eller provenance i en senere beslutningsbatch.

Artefaktauditen skal bevise eksakt changed set på de 12 new-entry-objekter,
ingen ændrede baseline-objekter, fortsat nul ejere for de 12, deep preservation
af alle øvrige objekter, embedded/standalone report-identitet, forventede
counts, uændrede beskyttede inputhashes, literal Calamari-evidens og fortsat
`NO-GO`. Fokuserede interpretertests, den komplette scriptsuite og
`git diff --check` skal bestå.
