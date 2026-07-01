# 11 — Personer med flere forældrepar: omfang, rodårsag, rettelse (2026-07-01)

## Baggrund
Bruger observerede at flere personer i appen så ud til at have mere end ét
forældrepar. Undersøgt via read-only SQL mod prod + kildekode-gennemgang.

## Omfang (målt direkte i prod, kun `rolle='barn'` — den eneste rolle der
tæller genetisk i slægtskabsfinderen)

| Mål | Antal |
|---|---|
| Personer med beviseligt modstridende forældrepar (≥2 familier som barn) | 90 (67×2, 23×3) |
| — heraf ekstra fejlagtige `barn`-rækker | 113 |
| `barn`-relationer der krydser linje-grænse ift. familiens forældre | 163 af 559 |
| Unikke personer berørt af mindst én linje-krydsende `barn`-relation | 136 |

Fordeling på tværs af de tidlige grene: linje I (33), III (24), IV (15), II (11), V (7).

## Rodårsag
`load_daa.R:14` dokumenterede det selv som en kendt "v1-forenkling": børn
knyttes til en familie via `boern.nr_range` + nøglen `(linje, løbenummer)`.
Matching-koden (`load_daa.R:246-260`, før fix) prøvede **først** det
LLM-udtrukne `boern.linje`-felt ("stated"), som kommentaren selv betegnede som
"ofte forurenet (kuld-markør forvekslet med linje)", og faldt kun tilbage til
forælderens egen linje hvis `stated` ikke fandtes i persontabellen (`pmap`).

DAA's løbenumre genbruges/nulstartes per linje. Da `stated` var forurenet,
matchede den nogle gange **tilfældigt** et løbenummer i en helt anden gren.
Eksempel (verificeret): person 58 "Gottschalk von Reventlow" er reelt
linje I, nr. 29 (søn af Iwan von Reventlow). Et forurenet `boern.linje`-felt på
*Theodor* (linje IV, nr. 13) og *Conrad Detlef* (linje V, nr. 20) — begge
adskilte grene, generationer senere — pegede begge tilfældigt på nr. 29, som
"tilfældigvis" findes i linje I, og Gottschalk blev fejlagtigt tilføjet som
barn i tre familier på tværs af tre generationer.

Guard'en tjekkede kun om nøglen *fandtes* et sted i persontabellen — ikke om
den faktisk hørte til den rigtige gren.

## Kode-rettelse
`load_daa.R:246-260`: `stated`-feltet (LLM-udtrukket `boern.linje`) er droppet
helt fra matchingen — børn matches nu UDELUKKENDE til `key(rec$linje, n)`
(forælderens egen linje). Første forsøg var blot at bytte rækkefølge
(prøv egen linje FØRST, `stated` som fallback), men det modsagde stadig
data-oprydningen: enhver fremtidig gen-indlæsning ville kunne genskabe et
kryds-linje-barn, hver gang et `stated`-felt tilfældigt matchede et løbenummer
i en anden gren FØR forælderens egen linje blev prøvet (kun i "gap"-tilfælde,
men stadig en regression). Ved at droppe `stated` helt matcher loaderens
output nu præcis den samme regel som prod-oprydningen brugte (barn.linje ==
en af familiens partneres linje) — en gen-indlæsning kan derfor ikke
reintroducere de 163 slettede rækker. Prisen: de sjældne ægte kryds-linje-børn
(hvis de findes) fanges ikke af v1 og skal tilføjes manuelt.

## Data-oprydning i allerede indlæst prod-data
Ren SQL-korrektion (ingen re-udtræk nødvendig) baseret på at
`person_external_id.linje` (sat direkte fra hver posts eget `linje`-felt i
pass 1, upåvirket af buggen) er pålidelig facitliste:

- For hver `family_member`-række med `rolle='barn'`: er barnets egen linje
  blandt linjerne for familiens `partner`-medlemmer? Hvis ikke → forkert
  spuriøs række, slettes.

Fordeling af de 163 slettede rækker:
- 63 personer: 1 korrekt familie bevaret, 1 forkert slettet.
- 23 personer: 1 korrekt familie bevaret, 2 forkerte slettet.
- 46 personer: eneste familie var forkert → slettet, nu forældreløs i data
  (ærligt "mangler" frem for "forkert" — matcher invariant #1, evidensbaseret).
- 4 personer: INGEN af deres familier matcher deres egen linje → begge slettet,
  **kræver manuel gennemgang**: Owe (I/35, person_id 65), Agnes Gertrud Louise
  (IV/85, id 381), Nils Christian (IV/89, id 385), Kara Anita (IV/90, id 387).

Kørt som `change_set` #3 (`data_correction_flere_foraeldre_2026-07-01`) —
163 `change_event`-rækker logget, fuldt fortrydbart via
`red_fortryd_change_set(3)`. Lokal JSON-backup af hele `family_member`
(før-tilstand, 1310 rækker) gemt i `work/backup-family_member-2026-07-01.json`
(git-ignoreret, kun ikke-personhenførbare id/rolle-data).

**Verificeret efter kørsel:** `family_member` 1310→1147 rækker (−163 ✓),
163 change_events på change_set 3 ✓, 0 personer med modstridende
forældrepar tilbage ✓.

## Udestående
Under den GAMLE kode kunne en forurenet `stated` på den RIGTIGE forælders egen
post-behandling kapre en helt anden (forkert) person i stedet for det rigtige
barn — det rigtige barn blev så aldrig linket dér, og endte enten forældreløst
(46 personer) eller forkert linket et tredje sted (nogle af de 90). Det
betyder de 46 orphans + de 4 uafklarede formentlig IKKE kræver en blind
manuel PDF-gennemgang: den fixede loader (kun egen-linje-match) vil med stor
sandsynlighed linke mange af dem korrekt, HVIS den rigtige forælders
kildepost genkøres. Dette er ikke gjort her, fordi:
- `work/clean.json` (15 poster) er ikke det fulde udtræk brugt til den
  aktuelle load — de 591 poster ligger spredt i `work/batch/*.json` og flere
  `work/batch_*.json`-filer, og skal findes/samles før en målrettet gen-kørsel.
- En fuld `load_daa.R --reset`-genindlæsning ville TRUNCATE alle model-tabeller
  og dermed cascade-slette al efterfølgende versionerings-/redaktionsdata —
  kræver egen plan + eksplicit godkendelse, ikke del af denne fix.

**Anbefalet næste skridt** (ikke udført): lokalisér de relevante kildeposter
for de 4 navngivne personer (Owe, Agnes Gertrud Louise, Nils Christian, Kara
Anita) og deres formodede forældre i `work/batch/`, kør den fixede
matching-logik isoleret (uden fuld reset) mod netop disse, og indsæt
manuelt hvis en gyldig linje-match findes. De 46 øvrige orphans kan
efterfølgende køres samlet med samme metode.
