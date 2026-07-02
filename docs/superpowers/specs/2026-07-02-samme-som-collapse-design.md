# samme_som-collapse (frontend identitets-projektion) — Design

**Dato:** 2026-07-02
**Status:** Godkendt (afventer dual-review + implementeringsplan)
**Beslutning:** `docs/decisions.md` § "Identitetssammenkædning: samme_som-relation + collapse i app (løsning A)"

## 1. Formål

Samme fysiske person optræder som **flere** `person`-rækker i basen:

- **(a) Slægtslinje-grundlæggere** — står i DAA to gange: i oprindelses-linjen og som rod af den linje de grundlagde. Fx Conrad de Reventlow (III-58 + V-1), Detlef de Reventlou (III-104 + IV-1). Begge er allerede linket via `samme_som` (`post_load_fixup.R`).
- **(b) Kryds-slægt-broer** — indgiftede med egen slægt et andet sted. Fx Beke Ahlefeldt-Laurvig (ægtefælle-stub i Reventlow nu; barn af Julius Ahlefeldt i kommende Ahlefeldt-import). **Uden for scope for denne iteration** (kræver server-side privacy — se §9).

Beslutningen (datamodel §9) er **LINK, ikke merge**: en `samme_som`-relation forbinder posterne; begge DB-rækker bevares (proveniens + fortrydbart). **Frontend skal folde dem sammen**, så brugeren møder ÉN person i søgning, person-visning og slægtskabsfinder.

Denne iteration bygger **frontend-projektionen** for **web + mobile** samtidig.

## 2. Arkitektur: valideret, reversibel identitets-projektion

Slægtskabs-motoren (`web/src/data/relationship.ts`, spejlet i mobile) forudsætter én identitet pr. person-id: BFS opad over `parentsByChild`, MRCA, sti-rekonstruktion, node-disjunkthed. At gøre den `samme_som`-bevidst ville komplicere afstand/MRCA/uafhængighed i mange kodestier.

Derfor: **projicér en kanonisk graf FØR `buildModel`; motoren forbliver urørt.** Men projektionen er *reversibel og valideret*, ikke en lossy omskrivning (Codex-review 2026-07-02).

### Hook-punkt
`web/src/data/model.ts` `loadModel()` bygger i dag `db: Db = {persons, unions, parentChild}` og kalder `buildModel(db)`. Indsæt projektionen imellem. Spejlet i `mobile/src/data/load.ts`.

### Kontrakt
Ny fil `web/src/data/collapseSameAs.ts` (+ spejlet `mobile/src/data/collapseSameAs.ts`):

```ts
export type SameAsEdge = { alias: string; canonical: string; konfidens?: Konfidens };
export type Provenance = { personId: string; linje: string | null; nr: number | null };
export type CollapseResult = {
  db: Db;                                   // projiceret: kanoniske id'er, flettede personer
  canonicalIdById: Record<string, string>;  // ETHVERT medlems-id -> kanonisk id (alias-map)
  mergedFrom: Record<string, Provenance[]>;  // kanonisk id -> alle kilde-poster (til badge)
  quarantined: QuarantineNote[];            // grupper der IKKE blev foldet + årsag
};
export function collapseSameAs(
  rawDb: Db,
  edges: SameAsEdge[],
  ext: Map<string, Provenance>,     // person-id -> {linje, nr}
  visibility: Map<string, boolean>, // person-id -> privat
): CollapseResult;
```

`loadModel` returnerer fremover både `Model` (fra `buildModel(result.db)`) OG `canonicalIdById` + `mergedFrom`, så Zustand-storen kan gemme dem (person-visning + rute-resolution bruger dem).

## 3. Kanonisk id — stabilt og eksplicit

**IKKE "flest felter"** (ustabilt — kan skifte ved næste import og bryde ruter/bogmærker).

`samme_som` er **retningsbestemt**: `subjekt` = alias (oprindelses-post), `objekt` = kanonisk (primær-post med fulde data). Matcher det allerede indsatte i `post_load_fixup.R` (III-58→V-1, III-104→IV-1). **Kanonisk id = `objekt`-siden.** `collapseSameAs` modtager kanterne som `{alias, canonical}` (loaderen af kanterne mapper `subjekt→alias, objekt→canonical`).

Union-find grupperer transitivt (A=B, B=C → én gruppe). For en gruppe er kanonisk = det medlem der kun optræder som `canonical`, aldrig som `alias`. Er det tvetydigt (flere kandidat-kanoniske, eller ingen entydig) → **karantæne** (§6).

**Alias-map (`canonicalIdById`)** afbilder hvert medlems-id → kanonisk id. Ruten `/person/<id>` og alle indgående id-opslag resolves gennem det, så et link til enten III-58 eller V-1 lander på den samlede person.

> Note: person-id'er er ikke reload-invariante (hele appens `/person/<id>`-routing er ustabil på tværs af reload — et præeksisterende forhold, ikke introduceret her). Denne projektion garanterer stabilitet *inden for* en load og korrekt alias-resolution; reload-invariant routing er et separat, udokumenteret behov.

## 4. Kun godkendte links foldes

Kun `samme_som`-relationer med en **`afklaret` konklusion** (redaktionelt blåstemplet) indgår i `edges`. Konsekvenser:

- **Blast-radius begrænset:** union-find er transitiv; én forkert kant kan smelte hele komponenter sammen. Kun blåstemplede identiteter foldes.
- **Sti-konfidens:** en blåstemplet identitet behandles som sikker, så `samme_som`-kanten behøver ikke figurere i stiens `weakestKonfidens`. Spekulative identitets-hypoteser (ikke `afklaret`) foldes IKKE — de forbliver to poster (kan senere vises som "muligvis samme som", uden for scope her).

## 5. Synligheds-guard (GDPR)

`collapseSameAs` folder **kun grupper hvor alle medlemmer har samme synlighed** (alle `privat=false`). Blandet synlighed → gruppen karantæneres (foldes ikke) + noteres.

Dette lukker Codex-fodgeværet: RLS skjuler private personer/relationer server-side, så en offentlig klient kan ikke se at en offentlig dublet er `samme_som` en privat person — havde vi foldet på tværs af synlighed ville den offentlige dublet forblive eksponeret. Kryds-synligheds-broer (Beke: levende/privat ↔ offentlig) venter derfor på server-side privacy-klasse (§9). Conrad+Detlef (alle afdøde/offentlige) foldes.

Bemærk: `privat = OR` ved merge er stadig korrekt for grupper der ER samme synlighed, men er ikke det der bærer GDPR-garantien — det gør synligheds-guarden.

## 6. Konflikt-validering og karantæne

Efter id-omskrivning, FØR resultatet accepteres, valideres hver gruppe. En gruppe der fejler **karantæneres** (foldes ikke — medlemmerne forbliver separate person-poster) og tilføjes `quarantined` med årsag. Aldrig tavs oprydning.

Afvisnings-kriterier:
1. **Selv-kant:** en kanonisk person bliver sin egen forælder eller ægtefælle.
2. **Cyklus:** den projicerede forældre-graf (kun de berørte noder) bliver cyklisk (DFS-check).
3. **Konkurrerende forældre:** to medlemmer har hver et **ikke-tomt, forskelligt** forældre-sæt (rigtige konkurrerende fødsels-familier — må ikke afgøres af PostgREST-rækkefølge via `firstUnionKey`). Ét ikke-tomt + ét tomt (fx Conrad: III-58 har forældre, V-1 har ingen) er IKKE konflikt → arv det ikke-tomme.
4. **Tvetydig kanonisk** (§3).

Køns- og vital-dato-konflikter **registreres** (i `quarantined`-note eller en advarsels-liste) men er ikke i sig selv blokerende — coalesce vælger deterministisk, men uenigheden overflades.

## 7. Merge-mekanik

For en gruppe der passerer validering, flettes til den kanoniske post:
- `name`: fra den kanoniske (objekt-)post — den har fulde data.
- `born/died/titel/koen`: coalesce (første ikke-null i deterministisk medlem-rækkefølge: kanonisk først, derefter alias'er sorteret på id).
- **`years` regenereres** fra de flettede `born/died` (sti-visningen i `relationship.ts` bruger `years` separat — inkonsistens ellers).
- `privat`: OR over gruppen (redundant med guarden §5, men bevaret for robusthed).
- `mergedFrom[kanonisk]`: alle medlemmers `{personId, linje, nr}`.

Kant-omskrivning og dedup:
- `unions.p1/p2` → kanonisk id. Drop union hvor `p1===p2` (selv-union efter merge). **Dedup IKKE kun på partner-par** — bevar `familie_id` (samme par kan have flere selvstændige ægteskaber, `docs/decisions.md:97`); to unions er kun dublet hvis samme `familie_id`.
- `parentChild.child/parent` → kanonisk id. Drop hvor `child===parent`. **Dedup på `(kanonisk-forælder, kanonisk-barn, familie-id)`** — ikke kun endpoints, ellers aggregerer den eksisterende konfidens-logik (`buildModel.ts:88`) samme endpoint-kant på tværs af familier og beholder fejlagtigt den stærkeste påstand.

## 8. Person-visning: Aux-projektion + proveniens

Person-visningen (`web` person-side, `mobile/src/app/person/[id].tsx`) slår hjælpedata op på ét person-id: linje, kilder, embeder, godser, medier, narrativ (`buildAux`). Efter collapse skal **den samlede visning samle begge posters hjælpedata**:

- Person-detalje-opslag resolver indgående id → kanonisk via `canonicalIdById`, og henter hjælpedata for **alle** medlems-id'er i gruppen (union af embeder/godser/medier/narrativer), ikke kun ét.
- `linjeByPerson` udvides til **flere linjer pr. person** (en collapsed grundlægger tilhører både oprindelses- og grundlagt-linje).
- **Proveniens-badge:** person-visningen viser eksplicit `mergedFrom` — fx "Optræder i DAA i den mecklenburgske linje (III-58) og som grundlægger af den grevelige linje (V-1)".

## 9. Uden for scope (bevidst udskudt)

- **Server-side privacy-klasse** — propagering af `privat`/`levende` på tværs af `samme_som`-klassen før RLS, så kryds-synligheds-broer (Beke) bliver GDPR-sikre. Krav før (b)-tilfælde kan foldes i publikums-web/mobile.
- **Kryds-slægt-broer (Beke-typen)** — venter på ovenstående + Ahlefeldt-import.
- **Automatisk identitets-detektion i skala** — via crosswalk/matching når nye slægter importeres. Crosswalken er p.t. for støjende til bulk (ikke injektiv). Manuel `samme_som`-linking dækker de få kendte tilfælde nu.
- **Reload-invariant person-routing** — præeksisterende, bredere end denne feature.
- **"Muligvis samme som"-visning** af ikke-`afklaret` identitets-hypoteser.

## 10. Test

Rene enhedstests af `collapseSameAs` (web + mobile spejlet), plus regression på `buildModel`/`relationship`:
- **Conrad-fixture:** III-58 (ingen datoer, har forælder) + V-1 (datoer, ingen forælder) → én kanonisk (V-1) med V-1's datoer OG III-58's forælder; `mergedFrom` = begge; far-link (tidl. manglende) nu til stede.
- **Detlef-fixture:** III-104 + IV-1 tilsvarende.
- **Kæde:** A→B, B→C → én gruppe, ét kanonisk.
- **Cyklus:** samme_som der ville gøre X til sin egen ane → karantæne, ikke fold.
- **Konkurrerende forældre:** to medlemmer med forskellige ikke-tomme forældre → karantæne.
- **Blandet synlighed:** privat + offentlig i samme gruppe → karantæne (ikke foldet).
- **Kant-dedup:** samme `(forælder, barn, familie)` fra to medlemmer → én kant; forskellig familie bevares.
- **years-regen:** coalesced datoer giver konsistent `years`.
- **relationship-regression:** node-disjunkthed/`uafhaengige` og anepar-gruppering korrekt efter collapse (to stier gennem samme fysiske person er ikke uafhængige).
- **Aux-projektion:** person-visning for enten III-58 eller V-1 → samme samlede data + multi-linje badge.

## 11. Berørte filer (forventet)

- `web/src/data/collapseSameAs.ts` (ny) + `mobile/src/data/collapseSameAs.ts` (ny, spejlet)
- `web/src/data/model.ts` + `mobile/src/data/load.ts` — hook + fetch af `samme_som`-kanter (godkendte) + `person_external_id` + synlighed
- `web/src/data/types.ts` (+ mobile) — `ModelPerson.mergedFrom?`, `CollapseResult`, `SameAsEdge`
- Person-visning (web + `mobile/src/app/person/[id].tsx`) — alias-resolution, Aux-union, multi-linje badge
- Zustand-store — gem `canonicalIdById` + `mergedFrom`
- Tests: `web/src/data/__tests__/`, `mobile/src/data/__tests__/`
