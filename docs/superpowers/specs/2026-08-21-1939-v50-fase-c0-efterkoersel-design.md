# Fase C0's efterkørsel — de 9 record-koblinger

**Dato:** 2026-08-21 · **Kilde:** DAA 1939 (v50-genimport) · **Rører:** `narrative.tekst` + `private.narrative_record_publication`

## Problemet

Fase B erstattede 551 narrativer med renset, evidensbaseret tekst. Tilbage stod
41 kilderecords, som var klassificeret »ægte nye« uden baseline-tilknytning —
deres modstykker i basen beholdt derfor den fejlbehæftede tekst fra den første
1939-import.

C0 afgjorde alle 41 den 2026-08-19: **10 kobling · 16 ny · 7 til C3 · 8 allerede
færdige.** Denne fase udfører koblingerne — minus person 1017, som er flyttet
til C3 (se nedenfor). **Ni personer.**

```
963 · 967 · 978 · 991 · 992 · 1296 · 1297 · 1298 · 1299
```

### Hvorfor 1017 ikke er med

Koblingen ville fjerne 149 tegn (afsnit B) fra 1017's narrativ. Målt mod alle
576 1939-narrativer findes fragmentet **ikke ordret nogen steder**; længste
delvise match er 57 tegn — og det match *er* person 1021's samlede narrativ,
som begynder midt i det orddelte »Revent- low«. 1021 er ikke en post, men halen
af 1017's afsnit B). En kobling ville derfor slette de første ~92 tegn
permanent. Sagen er en C3-sammenlægning, ikke en C0-kobling.
Se `docs/superpowers/reviews/1939-v50-fase-c0-efterkoersel-afklaringer.md`.

## Hvad en kobling er

To skrivninger pr. person, begge gennem prod-live RPC'er:

```sql
red_upsert_narrativ('person', pid, ny_tekst, p_privat := false,
                    p_source_id := 3, p_side := NULL)
red_publicer_narrative_record(narrative_id, source_record_id,
                              record_label   := 'record-<uuid>',
                              citation_label := 'DAA 1939 side NNN')
```

`p_side := NULL` er bevidst: RPC'ens UPDATE-gren skriver `side =
COALESCE(p_side, side)`, så NULL bevarer det eksisterende. **Efterkørslen
retter tekst, ikke sidetal.**

## Den ikke-oplagte opdagelse: records er rå OCR

C0's `verbatim_text` er **ikke** normaliseret. Målt mod fase B's slutinvarianter
fejler **alle ni**:

| | Antal af 9 |
|---|---:|
| Enlige linjeskift (1–13 pr. record) | **9** |
| Uopløste orddelinger (`-\n`) | 7 |
| `### PAGE`-markør | 1 (person 1299) |
| Trailing whitespace | 1 (person 1297) |

Uden normalisering ville fasen indføre rå OCR-tekst i en bestand af 551 rensede
narrativer, og de ni personer ville se anderledes ud end resten.

**Derfor er `narrative_norm_v1` et obligatorisk trin**, ikke en valgfri
oprydning. Den er en ren, deterministisk funktion
(`normalize_narrative_1939_v50.py`), og fase B brugte præcis den samme.

### Hvad normaliseringen efterlader til mennesket

Kørt på de ni med de 41 records som korpus: **8 flag i alt**, alle
`hyphen_unproven` — orddelinger hvor korpus ikke kan bevise, om `Revent-\nlow`
skal blive `Reventlow` eller `Revent-low`.

| Person | Flag |
|---|---:|
| 992 | 1 |
| 1297 | 3 |
| 1298 | 1 |
| 1299 | 3 |

Til sammenligning havde fase B 178 valg (165 merge · 11 keep · 2 strip).

### Hvad der reelt ændrer sig i basen

Efter normalisering, målt mod den nuværende prod-tekst:

| Person | Nu | Bliver | Ændrede tegn | Karakter |
|---|---:|---:|---:|---|
| 991 | 32 | 32 | **0** | identisk — kun bindingen mangler |
| 963 | 103 | 101 | 2 | én orddeling opløst |
| 992 | 107 | 105 | 2 | én orddeling opløst |
| 1296 | 278 | 275 | 13 | ordenstal + linjeskift |
| 1298 | 349 | 344 | 15 | ordenstal + linjeskift |
| 1299 | 666 | 655 | 25 | ordenstal + linjeskift + `### PAGE` fjernet |
| 978 | 100 | 140 | 44 | **nyt indhold** |
| 967 | 149 | 193 | 52 | **nyt indhold** |
| 1297 | 731 | 688 | 69 | normalisering + strukturlinje fjernet |

Sidetallene er efterprøvet som identitetskontrol: `narrative.side` matcher
recordens `page_from` for **alle ni** (508, 508, 509, 504, 504, 574, 574, 574,
574). Vi kobler altså til de poster, teksten faktisk kommer fra.

Kun **967 og 978** tilfører reelt nyt indhold. 1297 mister `»Børn: Ottende
Slægtled IIl.«` — en trykt krydshenvisning af samme klasse som de 73
sidemarkører og 499 søskende-ordenstal, fase B allerede fjernede.

## Arkitektur: fem trin, fem artefakter

```
1 · Eksport (read-only)   DB-tekst + sha256 + privat + side ⊕ recordens rå tekst
2 · Normalisering         narrative_norm_v1; invarianter fail-closed
3 · Menneskeark           8 orddelingsvalg (+ de 2 indholdstilføjelser til orientering)
4 · Manifest              normaliseret tekst + beslutninger, SHA-256-låst
5 · Apply                 én transaktion, ingen retry
```

Adskillelsen er ikke ceremoni. Trin 1–4 kan køres og gennemgås, **uden at prod
kan røres**, og trin 5 kan kun udføre det, der står i et hash-låst manifest, et
menneske har godkendt.

### Hvorfor ny writer frem for at genbruge fase B's

Fase B's writer er 748 linjer og hårdkodet til `length(ops) != 551L`.
**Hårdkodningen er et værn, ikke en mangel** — den forhindrer, at writeren
nogensinde kører med et forkert manifest. At gøre den variabel ville svække en
writer, der har skrevet 551 narrativer korrekt, for at genbruge den til ni.

De to writers værner desuden mod forskellige trusler. Fase B skrev 551
narrativer, den selv havde genereret maskinelt, og skulle værne mod fejl i
transformationen. Efterkørslen skriver ni tekster, et menneske har godkendt, og
skal værne mod at menneskets valg forvanskes på vejen.

Prisen er, at et værn kan glemmes. Modtrækket er dækningstabellen nedenfor:
hvert af fase B's værn genbruges eller fravælges **med begrundelse**, så
udeladelser bliver beslutninger frem for forglemmelser.

### Delvis accept er tilladt

Afvises tre af de ni, køres de seks. Alt-eller-intet ville presse mod at
acceptere en tvivlsom kobling for at få de øvrige igennem. Afviste parkeres
maskinlæsbart med begrundelse, som grænsefejlene.

**Men en tom mængde er ikke en gyldig kørsel.** Afvises alle ni, afbryder
apply'en frem for at åbne en tom transaktion — samme regel som D2's
`D2_APPLY_EMPTY`.

## Værn-dækning

| Fase B's værn | I efterkørslen |
|---|---|
| `OLD_SHA_MISMATCH` | **Genbruges.** Hver operation bærer `expected_old_narrative_sha256` |
| `privat=TRUE` → abort | **Genbruges.** GDPR (invariant 8): writeren sender altid `p_privat=false`, så en privat post ville blive tavst afprivatiseret |
| `side`-afvigelse | **Genbruges som read-only identitetskontrol.** Vi *skriver* ikke `side` (sender NULL), men vi sammenligner `narrative.side` mod recordens `page_from` og afbryder ved afvigelse. Det beviser, at vi rammer den rigtige post. Målt 2026-08-21: **9/9 matcher** |
| Slutinvarianter (`### PAGE`, enligt `\n`, trailing ws) | **Genbruges.** Beviseligt nødvendige: 1299 bærer `### PAGE 0063 ###` |
| `ALREADY_BOUND` | **Genbruges.** RPC'en kaster selv; 0 bindinger målt på forhånd |
| `ORDER_INVALID` | **Genbruges.** Sorteret på `person_id`, ingen dubletter |
| `COUNTS_INVALID` | **Genbruges som hårdkodet 9** |
| `INPUT_HASHES_INVALID` | **Genbruges.** Kandidatfilen SHA-256-låses |
| Advisory lock | **Genbruges.** Samme nøgle `daa-1939-v50-production-writer`, så to writers ikke kan køre samtidig |
| `CANONICAL_INVALID` | **Genbruges.** Kanonisk JSON-serialisering før hash |
| `OUT_OF_SCOPE_INVALID` | **Genbruges.** Kun de ni id'er må optræde |
| `BINDING_ARITHMETIC_INVALID` | **Forenklet:** 9 operationer → 9 bindinger, 0 eksisterende |
| `SIDE_CORRECTIONS_INVALID` | **Fravalgt.** Fase B havde to poster, hvor det trykte sidetal var forkert og krævede en registreret korrektion. Alle ni matcher her, så undtagelses-mekanikken har intet at gøre — og en afvigelse skal derfor være terminal, ikke korrigerbar |
| `FLAGS_INVALID` | **Genbruges** for `hyphen_unproven` |
| `SOURCE_INVALID` | **Genbruges.** `source_id = 3` |

**Plus D2's lærdomme:** `--jeg-mener-det`, obligatorisk `--expect-sha256` og
`--backup`, drift-guard der sammenligner **id-mængden** målt *inde i*
transaktionen, nul-delta-efterkontrol, eksplicit rollback via `tryCatch`,
`dbGetQuery` til `set_config`, og aktør-etablering med
`request.jwt.claim.sub` + verifikation mod `profiles`.

## Fortrydelse — hvad der faktisk kan rulles tilbage

| Skrivning | Fortrydbar? |
|---|---|
| `narrative.tekst` | **Ja.** `narrative` står i `version_pk_registry` → `change_events` |
| `narrative_record_publication` | **Delvist.** `red_tilbagetraek_narrative_record` findes i prod, men efterlader intet `change_event`, så web-fladens fortryd-panel viser den ikke |
| Sidste udvej | `pg_dump` taget i trin 5's gate |

Det er svagere end D2, hvor `change_set 960` dækkede alt. Derfor er rehearsal
obligatorisk.

## Gates

1. **Backup** — `pg_dump`, 0600, SHA-256 noteret. Free tier har ingen backup.
2. **Rehearsal** — frisk restore af dumpen; hele kæden køres dér først.
   Bemærk: `daa1939_d2_rehearsal1` har D2 anvendt og skal re-restores.
3. **GO-pakke** — tal, hashes og de ni diffs fremlagt; eksplicit brugergodkendelse.
4. **Én apply, ingen retry.** Fejler den, undersøges årsagen; den køres ikke igen.
5. **Efterkontrol** — 9 bindinger oprettet, 9 narrativer ændret, nul delta på
   person/fact/relation og på narrativ-*antal*.

## Uden for denne fase

- De 16 `[NY]`-records (personoprettelse, eget autorisations-gate)
- De 7 C3-sammenlægninger — **plus 1017/1021**
- De 12 grænsefejl-kandidater (narrativer der begynder midt i en sætning)
- Publicering af de staged personer (963 og 967 forbliver staged; det er
  bevist ufarligt — `private` er ikke eksponeret gennem API'et, og `anon` ser
  hverken personerne eller deres narrativer)

## Succeskriterier

1. Alle ni records passerer fase B's slutinvarianter **efter** normalisering.
2. De 8 `hyphen_unproven` er afgjort af et menneske i et fail-closed ark.
3. Rehearsal mod frisk restore giver samme resultat som forventet.
4. Én apply; efterkontrollen viser 9 nye bindinger og nul utilsigtet delta.
5. Person 991's tekst er **uændret** — dér tilføjer koblingen kun bindingen.
