# DAA 1939: fail-closed godkendelse af tekstanker

## Formål

Udvid `apply_reconciliation_decisions_1939.py` med en særskilt menneskelig
afgørelse for eksisterende `text_anchor_review`-poster. Udvidelsen skal bevare
en eksisterende `record_key` på præcis ét PDF-gennemgået nyt kildepostmål uden
at forveksle tekstankere med grænseændringer eller svække den globale
en-til-en-afstemning.

Udvidelsen må ikke automatisk godkende tekstankerposter. Hver afgørelse skal
fortsat komme fra en eksplicit, hashbundet beslutningsfil efter kildekontrol.

## Beslutningsformat

En godkendelse har præcis disse felter:

```json
{
  "baseline_record_key": "<eksisterende UUID>",
  "decision_kind": "accept_text_anchor",
  "selected_new_record_key": "<nyt record-id>"
}
```

Ekstra eller manglende felter afvises. Dokumentets eksisterende krav til
`schema_version`, `source.edition`, afstemnings-SHA-256, baseline-SHA-256,
Calamari-SHA-256, `reviewed_by` og `decision_batch` ændres ikke.

## Acceptkriterier

`accept_text_anchor` accepteres kun, når alle følgende forhold gælder:

1. `baseline_record_key` findes og har aktuelt dispositionen
   `text_anchor_review`.
2. Baselinepostens `evidence_method` er `unique_exact_narrative`.
3. Baselineposten har præcis ét eksisterende match.
4. `selected_new_record_key` er netop dette match og findes i `new_entries`.
5. Det valgte mål vælges ikke af en anden afgørelse i samme beslutningsfil.
6. Det valgte mål har ikke andre uafgjorte baseline-ejere.
7. Beslutningsfilens afstemningshash matcher de indlæste bytes.

Enhver afvigelse afvises med `DecisionError`. Der indføres ingen fallback,
normalisering, navnematching, sidebaseret matching eller automatisk valg.

## Resultat og proveniens

Ved en gyldig afgørelse får både baselineposten og den valgte nye post
dispositionen `accepted_carryover`. Baselineposten bevarer sin eksisterende
`baseline_record_key` og får:

- `selected_new_record_key`;
- `reconciliation_basis: "human_accepted_text_anchor"`;
- eksisterende beslutningsmetadata (`reviewed_by`, `decision_batch` og
  beslutningskildens hashbinding) efter samme mønster som andre menneskelige
  afgørelser.

Tidligere accepterede grænseændringer, strukturelle kontekster og pensionerede
dubletter skal bevares byte-uafhængigt af den nye afgørelsestype. Rapportens
eksisterende optællinger genberegnes efter den samme fælles kodevej.

## Afgrænsning

Denne ændring omfatter kun registrering af allerede gennemgåede
`text_anchor_review`-afgørelser. Den omfatter ikke:

- automatisk massegodkendelse af de 50 aktuelle poster;
- ændring af, hvordan `reconcile_source_records_1939.py` finder tekstankere;
- afgørelse af `unresolved`, `merge_review` eller `unmatched_new_review`;
- ændring af identitetsregister, database, loader eller produktionsdata;
- OCR-korrektion eller omskrivning af rå kildetekst.

## Testkrav

Den fokuserede testsuite skal mindst bevise:

1. En gyldig, entydig tekstankerafgørelse bliver `accepted_carryover` med
   `human_accepted_text_anchor`.
2. Forkert disposition eller andet `evidence_method` afvises.
3. Nul eller flere end ét match afvises.
4. Ukendt eller forkert valgt mål afvises.
5. Ekstra beslutningsfelter afvises.
6. Genbrug af samme nye mål og fortsat flere baseline-ejere afvises.
7. Hashdrift afvises.
8. En senere tekstankerbatch bevarer tidligere grænseafgørelser, strukturelle
   kontekster og dubletpensionering.
9. Rapportens resttal og dispositionsoptællinger er korrekte.

Efter de fokuserede tests køres hele DAA-scriptsuiten fra
`.claude/skills/daa-extract/scripts` med `/usr/bin/python3 -m pytest -q`.

## Efterfølgende arbejdsflow

Når implementeringen er verificeret, gennemgås de 50 aktuelle
`text_anchor_review`-poster mod deres eksakte kildespænd og PDF-kontekst.
Kun entydige poster skrives til hashbundne beslutningsbatches. Reelle
tvetydigheder forbliver synligt uafgjorte og forelægges brugeren.
