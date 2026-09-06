# #156 production-afstemning — 2026-09-03

**Udfald:** `INCOMPLETE` / `EVIDENCE_RECONCILIATION_INCOMPLETE`.

Det private operatørkatalog hash-låste de faktisk beholdte manifests og
apply-records. Ingen historisk apply-record har det senere
`daa-evidence-phase-receipt-*-v1`-skema, og ingen fase blev derfor
`mechanically_bound` eller fik et konstrueret bidrag.

| Fase | Tilstand | Fejltoken |
| --- | --- | --- |
| `task25` | `afterdocumented_unbound` | `EVIDENCE_RECONCILIATION_RECEIPT_UNBOUND` |
| `phase-a` | `afterdocumented_unbound` | `EVIDENCE_RECONCILIATION_RECEIPT_UNBOUND` |
| `phase-b` | `afterdocumented_unbound` | `EVIDENCE_RECONCILIATION_RECEIPT_UNBOUND` |
| `narrative-publication` | `afterdocumented_unbound` | `EVIDENCE_RECONCILIATION_RECEIPT_UNBOUND` |
| `name-completion` | `afterdocumented_unbound` | `EVIDENCE_RECONCILIATION_RECEIPT_UNBOUND` |
| `c0` | `afterdocumented_unbound` | `EVIDENCE_RECONCILIATION_RECEIPT_UNBOUND` |
| `d1` | `unavailable` | `EVIDENCE_RECONCILIATION_HISTORICAL_EXCEPTION_NO_MANIFEST` |
| `c3` | `afterdocumented_unbound` | `EVIDENCE_RECONCILIATION_RECEIPT_UNBOUND` |

Den ene autoriserede production-læsning kørte i en `READ ONLY`, `REPEATABLE
READ`-transaktion for `source_id = 3`. Snapshotet blev forseglet privat og
indeholder følgende ikke-identificerende optællinger:

| Sektion | Antal |
| --- | ---: |
| `source_records` | 592 |
| `source_anchors` | 897 |
| `narrative_bindings` | 563 |
| `narrative_sha256` | 563 |
| `persons` | 563 |

Hashene er:

- audit-ledger:
  `9f43e38665c17f8c7bddfc20c6b2bc07410e402f4d7594e858af6e03429bfc43`
- snapshot:
  `f7a9d1a3e6a20e6308473df3f880097d848e397066aa80e0652567f8d9e3cf5a`

Reconcilerens terminalresultat var ordret:

```json
{"artifact_hashes": {"ledger_content_sha256": "9f43e38665c17f8c7bddfc20c6b2bc07410e402f4d7594e858af6e03429bfc43"}, "counts": {"incomplete": 8, "mechanically_bound": 0, "phases": 8}, "error": "EVIDENCE_RECONCILIATION_INCOMPLETE", "phase_ids": ["task25", "phase-a", "phase-b", "narrative-publication", "name-completion", "c0", "d1", "c3"], "status": "incomplete"}
```

Admission stoppede før rækkeafstemning. Der er derfor ingen rækkeidentiteter i
denne rapport og ingen påstand om `match` eller `drift`; det dokumenterede
restpunkt er, at de historiske kørsler kun kan efterdokumenteres og ikke
mekanisk bindes retroaktivt.
