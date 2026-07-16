# Roadmap: Flere DAA-udgaver — præsenslister over tid, modstridende relationer, tværudgave-identifikation

> Status: **specificeret, ikke implementeret** (2026-07-15). Alle tre problemer er nu
> udfoldet i grundige design-specs (skrevet af Fable, se links i hvert afsnit nedenfor).
> Ingen kode endnu — afventer en konkret PDF af en anden DAA-udgave (typisk en
> præsensliste) at implementere og kalibrere mod.

## Baggrund

Årbogen har to hovedfunktioner: den store **stamtavle** (historisk slægtstræ,
det eneste der er indlæst i dag — DAA 2018-20, Reventlow) og den periodiske
**præsensliste** (kort oversigt over nulevende medlemmer, udkommer med års
mellemrum, fx DAA 2012-14). Når vi får adgang til en anden udgave — en
præsensliste eller en ældre stamtavle — rejser det tre sammenhængende
problemer, som denne fil holder samlet, fordi løsningen på #3 i praksis er
en forudsætning for #1 og #2 (man skal vide at det er "samme person" før
man kan diffe snapshots eller hæfte modstridende relationer på vedkommende).

## Problem 1 — Præsensliste som tidsserie, ikke isoleret kilde

> **Design-spec:** [`docs/superpowers/specs/2026-07-15-praesensliste-tidsserie-design.md`](superpowers/specs/2026-07-15-praesensliste-tidsserie-design.md)

**Nu:** `daa-presens` genbruger `person`/`fact`/`family`/`family_member` og
opretter en ny `source`-række pr. udgave, med append-only ID-allokering
(`.claude/skills/daa-presens/SKILL.md:88-91`). Der findes **ingen**
"as-of"-snapshot-mekanisme — `person.levende` (schema.sql:124) er et rent
GDPR-synlighedsflag, ikke en udgave-scopet tilstand. Skillets egen
dokumentation erkender hullet eksplicit: identitetssammenkædning mellem
stamtavle og præsensliste er "pragmatisk holdt" i PoC'en (SKILL.md:96-97) —
altså manuel, ikke systematisk. Eneste værktøj er `red_samme_som`
(schema.sql:977-1015), som kan linke to person-ID'er, men uden diffing og
uden forespørgsel af typen "hvad var sandt ved udgave N".

**Åbne spørgsmål:**
- Skal successive præsenslister (DAA 2012-14, 2015-17, …) for samme person
  ligge som separate `person`-rækker linket via `samme_som`, eller skal der
  indføres et udgave-scopet "status"-lag oven på eksisterende `fact`/
  `family_member`-rækker?
- Hvordan vises/beregnes "hvad ændrede sig fra sidste udgave" — ny partner,
  nyt barn, dødsfald siden sidst?
- `docs/database-current-state.md:38-39` bekræfter at ingen præsensliste
  endnu er indlæst i prod — hullet er derfor uafprøvet i praksis.

**Mulig retning (ikke besluttet):** en let tilføjelse oven på det
eksisterende evidenslag — hver `fact`/`family_member`-påstand er allerede
kildebundet, så det "kun" mangler er (a) en eksplicit kobling mellem
`source.aar` og "gyldig som-af"-semantik, og (b) en tværudgave-identitets-
proces (se Problem 3) der forbinder personen på tværs af udgaver, så en
diff bliver mulig.

## Problem 2 — Modstridende slægtskabspåstande mellem udgaver

> **Design-spec:** [`docs/superpowers/specs/2026-07-15-family-member-konkurrerende-relationer-design.md`](superpowers/specs/2026-07-15-family-member-konkurrerende-relationer-design.md)

**Nu, delvist understøttet:** `fact` og den generiske `relation`-tabel har
fuld evidens-infrastruktur: `assertion` (schema.sql:361-371, én kildes
påstand) → `citation` (schema.sql:384-392, kobler assertion til `source`)
→ `conclusion` (schema.sql:373-382, ét kanonisk valg pr. `(target_type,
target_id)`, håndhævet af `UNIQUE (target_type, target_id)` på linje 381)
— rivaliserende påstande **bevares**, kun konklusionen er singular. Dette
er allerede bevist i produktion: en TNG-vs-DAA datokonflikt blev bevidst
indlæst som en **konkurrerende assertion på samme fakta** med vores
konklusion uændret (`docs/decisions.md`, afsnit "TNG er sammenlignings-
reference, ikke facit; uenigheder loades som konkurrerende påstande").

**Hullet:** Selve forældre-/ægtefælle-relationerne ligger i `family`/
`family_member` (schema.sql:315-328), som **ikke** er koblet til
assertion/citation/conclusion-laget. `family_member` har kun et enkelt
`konfidens`-felt pr. række (`sikker|sandsynlig|formodet|omstridt`,
schema.sql:326) med kommentaren "Omstridte hypoteser med kilder ligger i
evidenslaget" — men ingen FK ruter faktisk `family_member`-evidens ind i
`assertion`/`citation`. Der er heller intet unikheds-constraint der
forhindrer to modstridende fædre for samme person (PK er kun
`(family_id, person_id, rolle)`, linje 327) — man *kunne* indlæse en anden
udgaves alternative far som en ny `family`+`family_member`-række, men uden
struktureret måde at markere at den er en konkurrerende, kildebunden
påstand over for den kanoniske.

`claude.md`'s eget designprincip hævder at "Hver trykt DAA-udgave er en
selvstændig `source` — så modstridende udgaver håndteres indfødt" — det
løfte er kun indfriet for `fact`/generisk `relation`, ikke for
`family_member`, hvor selve forældreskabet bor.

**Mulig retning (ikke besluttet):** udvid `family_member` med samme
assertion/citation-mønster som `fact` allerede har (fx `target_type=
'family_member'` i `assertion`/`citation`), så flere udgavers påstande om
forældreskab kan ligge side om side, med den nyeste (eller mest
sandsynlige) udgave som valgt `conclusion` — uden at den ældre påstand
overskrives eller kasseres.

## Problem 3 — Tværudgave-personidentifikation (stavevarianter, latinisering)

> **Design-spec:** [`docs/superpowers/specs/2026-07-15-tvaers-udgave-identifikation-design.md`](superpowers/specs/2026-07-15-tvaers-udgave-identifikation-design.md) (foundational — de to andre specs bygger på denne)

**Nu, `red_samme_som`: rent manuel, ingen scoring.** RPC'en
(schema.sql:977-1015) indsætter blot en relationsrække; invarianter
håndhæves af en trigger (linje 944-973: ingen selv-link, ingen multi-sink,
ingen re-kanonisering) — nul navne-/datosammenligning. Redaktør-UI'et
(`mobile/src/app/redaktion/person/[id].tsx:472-474,538-541`) åbner en
generisk `PersonPicker` (`mobile/src/components/redaktion/PersonPicker.tsx:
17-19`) som er en almindelig fritekst-søgeliste over *alle* personer — ikke
en rangeret kandidatliste. `packages/core/src/sammeSomPreflight.ts`
(`previewSammeSom`) tjekker først konsekvenser *efter* redaktøren allerede
har valgt begge personer (advarer ved køns-/levetids-/forælder-konflikt) —
det er rådgivning efter valget, ikke kandidat-forslag før.

Dette var et **bevidst fravalg**, ikke en forglemmelse:
`docs/superpowers/specs/2026-07-02-redaktionel-samme-som-linking-design.md:
174-179` lister eksplicit "Ingen 'muligvis samme som'-kladde-tilstand" og
"Ingen bulk/auto-matching (crosswalk for støjende)" som YAGNI på
beslutningstidspunktet — men det var før scenariet med flere trykte
udgaver blev konkret.

**Der findes allerede en fungerende matching-tilgang et andet sted i
kodebasen**, som kan genbruges/tilpasses: TNG-QA-pipelinen
(`R/tng-qa/04-match.R`) implementerer blocking + probabilistisk scoring —
ikke eksakt strengmatch:
- `name_similarity()` (linje 12-14): Jaro-Winkler-redigeringsafstand via
  `stringdist::stringdist(method="jw", p=0.1)`.
- `score_pair()` (linje 16-21): vægtet sum — navn 0.6, fødselsårs-overlap
  0.2, dødsårs-overlap 0.1, køns-match 0.1.
- `assign_tiers()` (linje 23-51): injektiv (1:1) grådig tildeling i tre
  bins — `auto` (score ≥0.90, tydelig topkandidat), `review` (≥0.70),
  `none`.
- Blocking sker på førstebogstav-af-normaliseret-navn + ±5 års
  fødselsårsvindue (surnavnet "Reventlow" er for ensartet til at bruges som
  blok-nøgle alene).
- Navnenormalisering (`R/tng-qa/03-normalize.R:5-28`): fjerner
  adelspartikler/titler (von, af, til, greve, baroness …), men bevarer
  **bevidst** diakritiske tegn ("Diakritik bevares ALTID", linje 1) og
  normaliserer **ikke** latiniserede stavevarianter (Cathrina/Catharina/
  Katharina) — præcis den svaghed brugeren peger på.
- Kalibrering er eksplicit uafsluttet (`docs/tng-qa-koersel.md:78-91`):
  "ÆRLIGE begrænsninger (ikke endeligt kalibreret)", ingen håndmærket
  facit-mængde endnu.

Web/mobil-søgning (`web/src/data/browse.ts:32-33`,
`mobile/src/data/selectors.ts:226,237`) er ren `toLowerCase().includes()`
substring-match — ingen diakritik-folding, ingen latiniseret-variant-
håndtering.

**Kendt tilstødende bug:** `docs/reviews/24-datamodel-helhedsreview.md:145`
flager at `post_load_fixup.R` løser `(linje, nr)` uden kilde-filtrering —
"ved 2+ DAA-udgaver kan `(linje, nr)` matche forkert udgaves person →
samme_som-links/lineage mod forkert kilde". Dette er en latent fejlkilde
der aktiveres netop når en anden udgave indlæses, og bør rettes samtidig.

**Brugerens forslag til retning (ikke besluttet, men lovende):** en
redaktør-side "sammenlign udgaver"-funktion, hvor to udgavers personlister
køres gennem en scorings-algoritme (genbrug/udvid TNG-QA's Jaro-Winkler +
års-overlap-tilgang, udvidet til også at normalisere latiniserede
navneformer, ikke kun titler/partikler), og hvor redaktøren får en
rangeret kandidatliste at godkende/afvise — i stedet for dagens fritekst-
søgning. Dette adresserer direkte YAGNI-fravalget i samme_som-designet,
som nu er blevet relevant.

## Rækkefølge

Blokeret på at have en konkret anden DAA-udgave (PDF) at arbejde ud fra.
Når den foreligger, er Problem 3 i praksis forudsætningen for 1 og 2 —
uden pålidelig tværudgave-identifikation kan man hverken diffe præsens-
snapshots eller hæfte en konkurrerende relationspåstand på "samme" person.
Foreslået rækkefølge ved genoptagelse: (a) kør en konkret udgave gennem
`/daa-extract` eller `/daa-presens`, (b) design/implementér tværudgave-
matching (Problem 3) mod det konkrete datasæt, (c) brug matchet til at
udvide `family_member` med assertion/citation (Problem 2) og præsens-
snapshot-diffing (Problem 1).

## Kilder brugt i denne analyse
- `.claude/skills/daa-presens/SKILL.md:88-91,95-99`
- `schema.sql:124,315-328,361-392,944-1015`
- `claude.md` (afsnit "Datamodellens invarianter" + "Faldgruber")
- `docs/decisions.md` ("TNG er sammenlignings-reference…")
- `docs/database-current-state.md:38-39`
- `docs/reviews/24-datamodel-helhedsreview.md:145`
- `docs/superpowers/specs/2026-07-02-redaktionel-samme-som-linking-design.md:174-179`
- `R/tng-qa/03-normalize.R:1-28`, `R/tng-qa/04-match.R:3-51,138-209`
- `docs/tng-qa-koersel.md:78-91`
- `mobile/src/app/redaktion/person/[id].tsx:472-474,538-541`
- `mobile/src/components/redaktion/PersonPicker.tsx:17-19`
- `packages/core/src/sammeSomPreflight.ts`
