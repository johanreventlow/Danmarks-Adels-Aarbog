# Rettelser på indgiftede ægtefæller — plan

**Dato:** 2026-07-29 · **Status:** plan, ikke påbegyndt
**Formål:** gøre det muligt at rette OCR-fejl på de 627 indgiftede ægtefæller.

> **Denne plan er skrevet om to gange.** Den første form gav ægtefæller en syntetisk
> `person_external_id`-række. Den blev forkastet efter to uafhængige reviews. §7 dokumenterer
> hvorfor — læs den før du genopfinder den tidligere løsning.

## 1. Problemet

`red_ret_ocr_felt` forankrer en rettelse på `(source.import_key, person_external_id.record_key)` —
altså på **bogens egen postidentitet**. Indgiftede ægtefæller har ingen sådan post: de nævnes kun
inde i partnerens opslag. RPC'en afviser dem med `ingen_importanker`.

Det er 627 af 1733 personer — 36 % af korpus, og 66 % af det kvalitetsarket ikke kan røre.

## 2. Hvorfor ikke bare give dem en `person_external_id`

Tabellen betyder *bogens egen postidentitet* (`schema.sql:141-150`). En person der kun er **omtalt**
inde i en anden post har ikke en. En syntetisk række ville forveksle to forskellige ting:

| | |
|---|---|
| **personidentitet** | hvem er dette menneske |
| **omtale-proveniens** | hvor i bogen står der noget om hende |

Ægtefællen har kun det sidste. Dertil kommer en konkret bivirkning: sættes `linje` på rækken,
påhæfter `regen_person_visning()` slægtsnavnet, og *Marie Elisabeth Blome* bliver til *Marie
Elisabeth Reventlow*. Hun blev gift ind i slægten; hun tilhører den ikke.

## 3. Løsningen: journalisér omtalen, ikke personen

Rettelsen nøgles på **hvor omtalen står**, ikke på en opdigtet post:

```
(import_key, anker_record_key, aegteskab_noegle, partnerfelt)
```

- `anker_record_key` — hovedpostens eksisterende, stabile nøgle
- `aegteskab_noegle` — hvilket ægteskab i den post (se §4 — dette er det svære)
- `partnerfelt` — `navn` · `foedsel` · `doed` · `koen`

Ingen ny personpost opfindes, og `person_external_id` beholder sin betydning.

### Hvad det kræver

| Lag | Ændring |
|---|---|
| `import_korrektion` | måltype + målnøgle-kolonner; unikhed over `(import_key, anker_record_key, aegteskab_noegle, partnerfelt)` |
| fingeraftryk | skal inkludere de nye dimensioner, ellers kan to omtaler kollidere |
| `red_ret_ocr_felt` | skal kunne opløse **præcis ét** anker, **ét** ægteskab, **én** partner. I dag kræver den at ankerpersonen *er* den redigerede person (`schema.sql:443-474`) |
| **DB-bærer (manglede i første udgave)** | ny kolonne på `family`/`family_member` der bærer `aegteskab_noegle` — uden den kan journalnøglen ikke opløses til en række. Basen har i dag kun `ordinal`, som §4 erklærer ubrugelig |
| loader | skal replaye rettelsen inde i `aegteskaber` **før** partnerpersonen materialiseres |
| `has_reset_blocking_editorial_changes()` | whitelister KUN strengen `'red_ret_ocr_felt'` (`load_helpers.R:42`). Nyt operationsnavn → reset blokeres altid; genbrugt navn → reset tillades før loaderen kan replaye. Helper + loader skal opdateres **senest samtidig** med RPC'en |
| kvalitetsark | ægtefællerækker skal vise hvilket anker de hænger på |

**Gate på partner-opløsning:** anker og ægtefælle har *begge* `rolle='partner'`, og
`partner_ekstern_ref`-grenen (`load_daa.R:379-386`) kan linke en eksisterende, **ankret** person som
partner. For sådan en person findes der så to skrivestier til samme assertion (record_key-stien og
omtale-stien) med hver sin journalnøgle → dobbelt-journal og fingerprint-drift. Omtale-stien skal
derfor **kun** tillades når partneren ikke har eget anker. Bemærk også: `red_ret_ocr_felt` kræver
i dag at personen har præcis ét anker i alt (`schema.sql:471-474`) — det krav skal genbesøges.

## 4. Den svære del: `aegteskab_noegle`

`family_member.ordinal` kan **ikke** bære nøglen. Den sættes af LLM-udtrækket:

```
LLM  →  convert_1939_stamtavle.py:148 (passthrough)  →  load_daa.R:378
```

`validate.py:804-805` siger det eksplicit: *"aegteskaber er IKKE deterministisk — LLM-udtræk er
autoritativt."* `derive_aegteskaber()` er advisory (`validate.py:678`) og skriver aldrig en ordinal.
Nummeret deler dermed proveniens med `nr` og `linje='1939'`: tildelt af pipelinen, ikke af bogen.

**Og kardinalitet redder ikke situationen.** "Ankerpersonen har kun ét ægteskab" er en egenskab ved
*dagens* udtræk. Finder en senere ekstraktion et ægteskab nummer to, kan `:1` flytte til en anden
ægtefælle — og en allerede udstedt nøgle peger så forkert, bagudrettet.

### Konsekvens

`aegteskab_noegle` skal være **opaque og én gang mintet**, ikke genudledt. Det kræver samme
identitetsregister som 1939-hovedposterne (`docs/decisions.md` → "1939-posternes permanente
løbenummer"): id, fysisk lokator, status, matchhistorik — og fail-closed ved tvetydighed.

**Ægtefælle-identitet kan derfor ikke løses før 1939-hovedposternes identitet er løst.**

## 5. Hvad der KAN gøres uafhængigt — de 331 fra 2018-20

**Dette afsnit har svinget mellem to yderpunkter; begge var forkerte** (dual-review 2026-07-29,
se `docs/reviews/aegtefaelle-plan-dual-review-2026-07-29.md`).

- *"Realistisk gevinst: 0"* var en **over-korrektion**: 2018-20 behøver ikke et register af
  1939-kaliber. Ankeridentiteten er stabil (`record_key` = filnavnet i
  `data/extracted-2026-06-18/`), så reconciliation efter en re-ekstraktion er intra-post — typisk
  ét ægteskab — ikke 1939's fulde postidentitets-problem.
- *"Én linje skrevet tilbage i artefaktfilen"* var en **under-korrektion**: snapshot-mappen læses
  af ingen kode (loaderen tager ét `clean.json`, `load_daa.R:6`; grep viser kun docs-referencer),
  en ny top-level-property fejler R5 fail-closed (`validate.py:22,769`), og nøglen mangler under
  alle omstændigheder en DB-bærer (§3).

**Den reelle kanal for de 331:** nøglen mintes som *nested* property i `aegteskaber`-objekterne i
det artefakt loaderen faktisk læser, plus validate-passthrough, loader-læsning og DB-kolonnen fra
§3. Overkommelig — men fire lag, ikke én linje.

**Gevinst i to trin:** 331 personer uden 1939-registeret · yderligere 296 når 1939 har identitet.

## 6. Rækkefølge

1. **Afstem 1939-artefaktet med prod.** Artefakterne har 539 poster; prod har 515. Regnestykket er
   539 − 1 − 23: **`nr` 43 blev aldrig loadet** (mangler i prod-dump fra før sletningerne) og 23
   dubletter er siden slettet — begge dele findes kun i basen, og `person_external_id` står på
   loaderens reset-liste (`load_helpers.R:74-78`), så en genindlæsning ville genskabe dubletterne
   og genindføre spørgsmålet om nr 43. **Ingen nøgle må mintes før dette er gjort.**
2. **Etablér identitetsregisteret** for 1939-hovedposter (fysisk lokator + opaque id + fail-closed
   reconciliation). Fælles forudsætning for §4 og for 1939's egen `record_key`.
3. **Udvid `import_korrektion`** med måltype/målnøgle + fingeraftryk.
4. **Omskriv `red_ret_ocr_felt`** til at kunne forankre på en omtale — og opdater
   `has_reset_blocking_editorial_changes()` + loader-replay **i samme leverance** (§3).
5. **Backfill og verificér** (§8).

## 7. Hvorfor den første form blev forkastet

| Version | Antagelse | Hvad der væltede den |
|---|---|---|
| 1 | ægteskabsnummeret er positionsafhængigt og skrøbeligt | — (viste sig rigtigt, men begrundet forkert) |
| 2 | nummeret er stabilt, fordi tælleren følger bogens rækkefølge | **analyserede forkert kodesti** — `derive_aegteskaber` skriver aldrig ordinalen |
| 3 | de 463 med ét ægteskab kan nøgles risikofrit | **kardinalitet er ikke en varig egenskab** — et ægteskab nummer to kan dukke op |
| 4 | derfor er gevinsten 0 uden identitetsregister | **over-korrektion** — 2018-20's ankeridentitet er stabil; kun 1939 kræver registeret (§5) |

Fælles mønster: hver version antog at *noget i det nuværende udtræk* kunne bære identitet. Det kan
intet af det. Se `docs/decisions.md` for den fulde vurdering af kandidaterne.

## 8. Verifikation

- korpus-diff på `visning_efternavn` + `visning_fuldt_navn`, alle personer → **0 forskelle**
- ⚠ en diff på 0 beviser kun at cachen er **urørt**, ikke at den er **korrekt**: id 811
  (`Mundhenke`) og 852 (`Ahlefeldt-Laurvig`) bærer i dag efternavne som `regen_person_visning()`
  umuligt kan have sat — forældet cache. Noteret så en fremtidig diff ikke tolker dem som noget
  planen forårsagede
- ingen række med `linje = '1939'` rørt
- `get_advisors(security)` uændret
- rettelser skal være **reload-durable**. Præcisering efter dual-review: `person_external_id`
  nulstilles ved reset, men **`import_korrektion` gør ikke** — journalen står bevidst uden for
  `loader_model_tables()` (`load_daa.R:285`, `load_helpers.R:75-79`) og replayes efter reset.
  Journal-tilgangen i §3 er altså reload-durable **by design**; det er endnu et argument for den
  frem for syntetiske `person_external_id`-rækker

## 9. Åbne forbehold

- De **10 ordinal-kollisioner** har mindst fire mulige forklaringer med **modsatte** handlinger:
  spøgelses-union (slet) · samme ægteskab attesteret af begge udgaver (match — evidensmodellen efter
  design) · LLM udelod ordinal (udfyld) · gengifte med samme partner (behold begge). `R4`
  (`validate.py:736-739`) filtrerer NULL fra og blokerer derfor kun gentagne ikke-NULL ordinaler —
  kollisionernes oprindelse er **uafklaret**. En oprydning der antager spøgelse kan slette et ægte
  ægteskab.
- **Gruppe-fallback** (`segment_1939.py:16`) giver ankerløse poster gruppens delte tekstblok, så
  flere søskende kan dele samme klip. "Én persons narrativ" er ikke altid én person.
- Ægtefællers navnefakta får citation **uden `span`** (`load_daa.R:386-401`), så den præcise
  bogkontekst mangler i kvalitetsarkets review-visning.
- Tallene (627 / 331 / 10 / 489 / 539 vs 515) er målt af Claude mod prod 2026-07-29. Codex kunne
  ikke verificere dem selvstændigt under read-only-reglen.
