# C0's efterkørsel og de 7 blokerede — genmåling efter D1

**Dato:** 2026-08-20 · **Karakter:** read-only måling mod prod · **Intet skrevet.**

> **⚠️ Delvist afløst.** Afsnit 2's anbefaling (»kør de otte uproblematiske som
> én batch, og afgør 1017 og 1297 hver for sig mod kildesiden«) er overhalet af
> `1939-v50-fase-c0-efterkoersel-afklaringer.md`, som afgjorde begge ved måling:
> **9 af 10 er klar** (inkl. 1297), og **1017 hører til C3**, fordi person 1021
> viser sig at være halen af 1017's afsnit B). Afsnit 3's kortlægning af de 7
> blokerede står uændret, bortset fra at 963/967's RLS-spørgsmål nu er afgjort:
> der er ingen lækage.

C0's 41 afgørelser blev truffet 2026-08-19, *før* fase D1 kørte. Efterkørslen
har ingen guard mod at basen har flyttet sig imens, så grundlaget skulle
måles igen før noget kunne planlægges. Det er gjort her.

## 1. Grundlaget står intakt

Alle 10 `[KOBL]`-afgørelser genmålt mod prod:

| Måling | Resultat |
|---|---|
| Målperson findes | 10/10 |
| `private.source_record` med afgørelsens `record_key` findes | 10/10 |
| Bindinger på målpersonens 1939-narrativ | **0 for alle 10** |
| Bindinger på afgørelsens record | **0 for alle 10** |

Ingen af de 10 er blevet bundet i mellemtiden, og ingen kollision med den
`UNIQUE` narrativ-binding, der fangede otte af de 41 under C0. D1 rørte som
lovet kun `person.staged`.

**Men grundlaget er ikke det samme som klarsignal.** To spørgsmål nedenfor
skal afgøres af et menneske, før efterkørslen kan planlægges færdig.

## 2. To af de 10 fjerner synligt indhold

Efterkørslen erstatter målpersonens narrativtekst med recordens. For otte af
de ti vokser teksten eller er praktisk talt uændret. To krymper:

| Person | Nu | Efter | Delta | Karakter |
|---|---:|---:|---:|---|
| 1017 | 369 | 237 | **−132** | 149 sammenhængende tegn slettes i halen; resten uændret |
| 1297 | 731 | 704 | −27 | ny tekst er en **ren delstreng** — halen falder bort |

Begge er hale-afkortninger, ikke omskrivninger. Det er signaturen på en
grænsefejl-reparation: den gamle tekst løb ind i den næste post, og
koblingen skærer den tilbage til postens egen udstrækning.

C0's egen changelog-note advarede om netop 1017 (R40): teksten skæres til
afsnit A) alene, og hvis B)-delen hører til person 1021 — som går til C3 —
følger den med derhen. **Er den antagelse rigtig, er tabet en flytning.
Er den forkert, forsvinder 149 tegn.** 1297 blev ikke flagget og bærer
samme spørgsmål i mindre skala.

Anbefaling: kør de otte uproblematiske som én batch, og afgør 1017 og 1297
hver for sig mod kildesiden. Der er ingen grund til at lade to
tekstspørgsmål gate otte rene koblinger.

**Fortryd dækker ikke narrativ-bindingerne** (`narrative_record_publication`
står ikke i `version_pk_registry`) — en forkert kobling kan ikke rulles
tilbage ad normal vej. Det er grunden til at afgørelsen tages før skrivning.

## 3. De 7 blokerede staged — og hvorfor de ikke er én gruppe

Efter D2 vil præcis 7 staged personer stå tilbage: **933, 935, 940, 963,
967, 1014, 1135.**

De deler ét objektivt træk: alle har et 1939-narrativ og et
`person_external_id`, men **0 published bindinger**. Det er præcis D1's
kriterium, de fejler på. Ingen er levende eller privat; alle har navn.

De er dog tre forskellige sager:

| Personer | Sag |
|---|---|
| 933, 935, 940, 1135 | Blandt C0's **9 uforklarede** — poster med gammel tekst, hvis modstykke ikke kunne findes maskinelt (alle 11 »uden kandidat« har dækning 0.00). Hører til C3's identitetsspor. |
| 1014 | Står på C0's **uafklarede**-liste. Afventer C0. |
| **963, 967** | **`[KOBL]`-mål der selv er staged.** C0-rapporten flagede dem: at publicere en record-binding på en staged persons narrativ er et synligheds-/RLS-spørgsmål, som **ingen har afklaret**. |

963 og 967 er derfor ikke et D3-spørgsmål, men et **C0-spørgsmål**: de indgår
i efterkørslens ti koblinger. Rækkefølgen mellem »bind record« og »gør
synlig« skal besluttes, ikke opdages undervejs.

## 4. Konsekvens for planlægningen

- **D2** er upåvirket: 0 overlap med C0's uafklarede, og ingen af de 21 er
  blandt de 10 koblinger. Den kan køre først.
- **C0's efterkørsel** mangler stadig et apply-værktøj — der findes kun
  `build_c0_record_linkage`, `match_c0_records` og
  `convert_c0_linkage_decisions`. Efterkørslen skal designes, ikke bare køres.
- **D3** kan ikke afgrænses meningsfuldt endnu: 5 af de 7 hører til C0/C3, og
  963/967 afklares som en del af efterkørslen. Der er reelt 4 personer (933,
  935, 940, 1135) plus 1014, som er en ren C3-sag.
