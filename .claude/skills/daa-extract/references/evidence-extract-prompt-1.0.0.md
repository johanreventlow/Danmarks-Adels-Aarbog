<!-- evidence-extract-prompt-1.0.0
     Record-scoped prompt til model-runneren (#147 dagsværk 4.3a).
     Frossen: rediger ikke ad hoc. En ændring kræver en ny version af BÅDE denne fil
     og profilens prompt_file/prompt_sha256, samt projektejerens GO.

     IKKE den samme som references/extract-prompt.md, som er den gamle trin ③-vej
     (skriver work/extracted/*.json med Write og validerer mod extraction-schema.json).
     De to eksisterer side om side med vilje. -->

# Udtræk af belæg fra én post i en adelsårbog

Du får ÉN post fra en trykt slægtsbog, delt op i nummererede klausuler. Din opgave er
at udtrække de fakta, posten faktisk påstår, og for hvert faktum pege på den eller de
klausuler, det står i.

Returnér JSON efter det medsendte skema. Intet andet.

## Input

`record.json` indeholder postens klausuler:

```json
{"record_key": "…", "persona_id": "…",
 "clauses": [{"ordinal": 1, "verbatim_text": "…"}, …]}
```

`ordinal` er klausulens nummer. Det er dét, du citerer — ikke tegnpositioner.

## Regler

1. **Citér altid mindst én ordinal.** Et claim uden belæg i teksten er ubrugeligt og
   afvises. Står et faktum i flere klausuler, så nævn dem alle.
2. **Udled ikke.** Skriv kun det, posten siger. Står der ingen dødsdato, så er der
   intet dødsfaldsclaim — gæt ikke ud fra alder, generation eller sammenhæng.
3. **Datoer gengives ORDRET** som de står (`"12. Decbr. 1801"`, `"o. 1750"`,
   `"f. 1801"`). Omregn ikke til ISO, og udfyld ikke et årstal, bogen ikke skriver.
   Den ordrette form er det, der skal kunne efterprøves mod siden.
4. **Brug kun prædikater fra listen nedenfor.** Findes der ikke et passende, så
   undlad claimet. Opfind aldrig et nyt navn.
5. **Værdiens form følger prædikatet.** De fleste tager en almindelig tekststreng.
   Prædikater om relationer, hændelser, navnedele og omtaler tager i stedet et objekt
   med feltet `raw`, der indeholder den ordrette tekst.
6. **`confidence` er et tal mellem 0 og 1** og udtrykker, hvor klart posten siger det —
   ikke hvor sandsynligt du finder det. Står det tydeligt: tæt på 1. Er formuleringen
   vag eller forkortet: lavere.
7. **`source_persona_id` skal med på alle `person.*`-claims** og skal være postens
   egen `persona_id`. Claims om andre personer end postens hovedperson hører til et
   senere trin — udelad dem.
8. **Ingen claims er et gyldigt svar.** Rummer posten intet udtrækbart, returnér
   `{"claims": []}`. Det er bedre end at presse et faktum frem.

## Hvad du IKKE skal

- Ikke skrive filer, ikke køre kommandoer, ikke slå noget op uden for posten.
  Du har alt, du skal bruge, i `record.json`.
- Ikke gengive posten som fritekst. Kun claims.
- Ikke rette bogens stavemåder, forkortelser eller navneformer.

## Prædikater

Den autoritative liste ligger i `references/interpretation-predicates.json`, som er en
projektion af databasens egen tabel. Hovedgrupperne:

- `person.*` — fakta om postens hovedperson: `person.birth`, `person.death`,
  `person.baptism`, `person.burial` (alle ordrette datoer), `person.name`,
  `person.title`, `person.rank`, `person.office`, `person.education`,
  `person.occupation`, `person.residence`, `person.estate`, `person.decoration`,
  `person.military_service`, `person.publication` m.fl.
- `relation.*` — `relation.marriage`, `relation.parent`, `relation.child`.
- `event.*` — daterede begivenheder: `event.marriage`, `event.appointment`,
  `event.dismissal`, `event.acquisition`, `event.travel`.
- `mention.*` — omtaler af steder, personer, godser og organisationer.
- `heraldry.*`, `image.*`, `lineage.*`, `genealogy.*` — våben, billedtekster,
  indledninger og generationsoverskrifter.

## Eksempel

Post:

```
1. Christian Ditlev, f. 21. Juni 1710 paa Krenkerup.
2. Blev 1735 Kammerjunker.
3. Gift 4. Maj 1739 m. Charlotte Amalie v. Holstein.
```

Svar:

```json
{"claims": [
  {"clause_ordinals": [1], "predicate": "person.birth", "value": "f. 21. Juni 1710",
   "confidence": 1.0, "source_persona_id": "<postens persona_id>"},
  {"clause_ordinals": [1], "predicate": "mention.place", "value": {"raw": "Krenkerup"},
   "confidence": 0.9},
  {"clause_ordinals": [2], "predicate": "person.title", "value": "Kammerjunker",
   "confidence": 1.0, "source_persona_id": "<postens persona_id>"},
  {"clause_ordinals": [3], "predicate": "relation.marriage",
   "value": {"raw": "Charlotte Amalie v. Holstein"}, "confidence": 1.0}
]}
```

Bemærk: fødselsdatoen er gengivet ordret med `f.`, ikke omskrevet til `1710-06-21`.
Stedet er en omtale, ikke et fødselsfaktum. Og ægteskabet citerer kun klausul 3.
