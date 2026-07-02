# samme_som-collapse (frontend identitets-projektion) — Design

**Dato:** 2026-07-02
**Status:** Godkendt + dual-reviewet (afventer implementeringsplan)
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

Union-find grupperer transitivt (A=B, B=C → én gruppe). **Normalisér parallelle/duplikerede kanter først.** Kanonisk = **den unikke sink** i gruppens rettede graf (medlem med alias-outdegree 0 — optræder aldrig som `alias`). Karantæne (§6) hvis:
- **ingen unik sink:** `A→B, A→C` (B og C begge kandidater — A kan ikke have to kanoniske); `A→B, B→A` (retnings-cyklus, ingen sink).
- **ufuldstændig komponent:** et endpoint findes IKKE i `rawDb.persons`. RLS kan have trunkeret en privat/levende tvilling væk, så en delvist observeret gruppe ser entydig ud uden at være komplet. Kun **komplet-observerede** grupper (alle medlemmer + alle kanter til stede i de hentede data) foldes — dette er også GDPR-mekanismen (§5).

**Alias-map (`canonicalIdById`)** afbilder hvert medlems-id → kanonisk id. Ruten `/person/<id>` og alle indgående id-opslag resolves gennem det, så et link til enten III-58 eller V-1 lander på den samlede person.

> Note: person-id'er er ikke reload-invariante (hele appens `/person/<id>`-routing er ustabil på tværs af reload — et præeksisterende forhold, ikke introduceret her). Denne projektion garanterer stabilitet *inden for* en load og korrekt alias-resolution; reload-invariant routing er et separat, udokumenteret behov.

## 4. Kun godkendte links foldes

Kun `samme_som`-relationer med en **`afklaret` konklusion** (redaktionelt blåstemplet) indgår i `edges`. Konsekvenser:

- **Blast-radius begrænset:** union-find er transitiv; én forkert kant kan smelte hele komponenter sammen. Kun blåstemplede identiteter foldes.
- **Sti-konfidens:** en blåstemplet identitet behandles som sikker, så `samme_som`-kanten behøver ikke figurere i stiens `weakestKonfidens`. Spekulative identitets-hypoteser (ikke `afklaret`) foldes IKKE — de forbliver to poster (kan senere vises som "muligvis samme som", uden for scope her).

## 5. GDPR: completeness + RLS er mekanismen (ikke en klient-side guard)

**Vigtig korrektion (Codex 2026-07-02):** en klient-side synligheds-guard er hverken mulig eller nødvendig. RLS-modellen er `person_offentlig(pid) = (levende=false AND coalesce(privat,false)=false)` (`db-rls.sql:43`) — synlighed afhænger af **både `levende` OG `privat`**, ikke kun `privat`. En `samme_som`-relation udleveres kun hvis **begge** person-endpoints er synlige for klienten (`db-rls.sql`, relation-politik gater på `person_offentlig` af begge endpoints). En privat/levende tvilling — OG kanten til den — er derfor helt usynlig for en anon-klient. Klienten kan altså ikke "se den blandede gruppe og karantænere den"; der er ingen gruppe at se.

**Mekanismen er derfor completeness (§3) + RLS, ikke en `privat`-sammenligning:** fold kun **komplet-observerede** grupper (alle medlemmer + alle kanter til stede i de hentede data). RLS garanterer at en delvist-synlig gruppe mangler enten et medlem eller en kant → fejler completeness → foldes ikke. Ingen privat data kan derfor vandre ind i en offentlig kanonisk post.

Konsekvenser:
- En offentlig dublet hvis `samme_som`-tvilling er privat/levende forbliver **ufoldet** (klienten ser hverken tvillingen eller kanten). Det er **ikke et læk** (ingen privat data eksponeres) — kun *ufuldstændig* collapse, udskudt til server-side privacy-klasse (§9). Conrad+Detlef (alle afdøde/offentlige, komplet observeret) foldes.
- **Collapse-resultatet kan variere pr. klient** (anon folder færre grupper end et authenticated medlem der ser levende ikke-private personer). Det er korrekt — hver klient folder konsistent præcis hvad den kan observere komplet.
- `privat = OR` ved merge bevares for de synlige medlemmer (robusthed), men bærer ikke GDPR-garantien.

## 6. Konflikt-validering og karantæne

Validering køres på den **fuldt omskrevne, KOMBINEREDE** forældre-graf (ALLE collapses anvendt samtidig), **FØR nogen kant droppes** (Codex 2026-07-02: ellers skjuler en tavs self-edge-drop netop den konflikt valideringen skal fange, og to grupper der er sikre hver for sig kan konflikte samlet). En gruppe (eller kombination) der fejler **karantæneres** (foldes ikke — medlemmerne forbliver separate poster) og tilføjes `quarantined` med årsag. Aldrig tavs oprydning.

Afvisnings-kriterier:
1. **Selv-kant:** en kanonisk person bliver sin egen forælder eller ægtefælle på den omskrevne graf. (Detekteres her, IKKE droppet i §7.)
2. **Cyklus:** cyklus i **HELE** den projicerede forældre-graf (global reachability, ikke kun berørte noder — en merge kan lukke en cyklus gennem uberørte X/Y).
3. **Konkurrerende forældre:** to medlemmer har hver et **ikke-tomt, forskelligt** forældre-sæt (rigtige konkurrerende fødsels-familier — må ikke afgøres af PostgREST-rækkefølge via `firstUnionKey`). Ét ikke-tomt + ét tomt (Conrad: III-58 har forældre, V-1 har ingen) er kun ikke-konflikt **når gruppen er komplet-observeret (§3) og linket afklaret** — tomt kan ellers betyde ukendt/filtreret data.
4. **Tvetydig/manglende/ufuldstændig kanonisk** (§3).
5. **Hard vital/køn-konflikt (defense-in-depth):** kendt-forskelligt køn, ikke-overlappende levetider, eller fødsler årtier fra hinanden → **blokér automatisk collapse**. Det er stærke falsk-identitets-indikatorer, også for et blåstemplet link (en redaktør kan have linket forkert). Registreres i `quarantined`.

`§7`-merge udføres KUN for grupper der passerer alle kriterier.

## 7. Merge-mekanik

For en gruppe der passerer validering, flettes til den kanoniske post:
- `name`: fra den kanoniske (objekt-)post — den har fulde data.
- `born/died/titel/koen`: coalesce (første ikke-null i deterministisk medlem-rækkefølge: kanonisk først, derefter alias'er sorteret på id).
- **`years` regenereres** fra de flettede `born/died` (sti-visningen i `relationship.ts` bruger `years` separat — inkonsistens ellers).
- `privat`: OR over gruppen (redundant med guarden §5, men bevaret for robusthed).
- `mergedFrom[kanonisk]`: alle medlemmers `{personId, linje, nr}`.

Kant-omskrivning og dedup (kun for grupper der passerede §6 — de har pr. konstruktion INGEN selv-kanter, så der er intet at "droppe"; selv-kanter er et §6-karantæne-signal, ikke en tavs oprydning):
- `unions.p1/p2` → kanonisk id. **Dedup IKKE kun på partner-par** — bevar `familie_id` (samme par kan have flere selvstændige ægteskaber, `docs/decisions.md:97`); to unions er kun dublet hvis samme `familie_id`.
- `parentChild.child/parent` → kanonisk id. **Dedup på `(kanonisk-forælder, kanonisk-barn, familie-id)`** — ikke kun endpoints, ellers aggregerer den eksisterende konfidens-logik (`buildModel.ts:88`) samme endpoint-kant på tværs af familier og beholder fejlagtigt den stærkeste påstand.
- `born/died` filtrerer parent-child-kanter i `buildModel` (umulig-forælder-guard, `buildModel.ts:23`, især linje 27-28) — et forkert coalescet år kan derfor lydløst fjerne en gyldig kant. `years`-regenereringen skal ske FØR `buildModel`, og vital-konflikter fanges af §6.5.

## 8. Person-visning: Aux-projektion + proveniens

Person-visningen (`web` person-side, `mobile/src/app/person/[id].tsx`) slår hjælpedata op på ét person-id: linje, kilder, embeder, godser, medier, narrativ (`buildAux`). Efter collapse skal **den samlede visning samle alle posters hjælpedata** — og **ALLE person-id-bærende strukturer** skal kanoniseres eller resolveres ved brug (Codex 2026-07-02: ellers alias-navigation + inkonsistente tællinger):

- Person-detalje-opslag resolver indgående id → kanonisk, og henter hjælpedata for **alle** medlems-id'er i gruppen. Web henter i dag persondetalje for præcis ét id (`public.ts:103`) → udvid til alle medlemmer.
- **Narrativ = UNION** af alle medlemsposters narrativer, ikke "første offentlige" (`public.ts:106`).
- `linjeByPerson` udvides fra `Record<string,string>` til **flere linjer pr. person** (`Record<string,string[]>`, `mobile/.../types.ts:153`) — en collapsed grundlægger tilhører både oprindelses- og grundlagt-linje.
- Rå person-id'er andre steder skal også resolves/kanoniseres: `buildAux` `ownersByEstate[].personId` (`buildAux.ts:110`), `linjeList.headId` (`buildAux.ts:87`), start/fokus-id'er i slægtskabsfinderen, og gemt `meId` i storen.
- **Private facts/narrativer må ALDRIG coalesces ind i publikums-projektionen.** RLS sikrer det for anon/medlem; redaktions-modellen holdes eksplicit separat (som i dag, `mobile/src/store/useStore.ts:71`).
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
- **Kæde:** A→B, B→C → én gruppe, ét kanonisk (C = unik sink).
- **Tvetydig sink:** A→B, A→C → karantæne (ingen unik sink).
- **Retnings-cyklus:** A→B, B→A → karantæne (ingen sink).
- **Ufuldstændig komponent:** endpoint mangler i `rawDb.persons` (RLS-trunkeret) → karantæne, og collapse må IKKE hævde at gruppen blev observeret+karantæneret.
- **Forældre-cyklus (global):** samme_som der ville gøre X til sin egen ane — inkl. via UBERØRTE noder → karantæne.
- **To grupper, sikre enkeltvis, konflikt samlet:** kombineret projektion validering → karantæne.
- **Konkurrerende forældre:** to medlemmer med forskellige ikke-tomme forældre → karantæne.
- **Hard vital/køn-konflikt:** kendt-forskelligt køn / ikke-overlappende levetider → blokér collapse (§6.5).
- **Self-parent:** samme_som der giver selv-forælder → **karantæne** (ikke tavs drop).
- **RLS-integration:** offentlig A `samme_som` privat/levende B → anon modtager KUN A (ikke B, ikke kanten); A forbliver ufoldet; ingen privat data i A's projektion.
- **Kant-dedup:** samme `(forælder, barn, familie)` fra to medlemmer → én kant; forskellig `familie_id` bevares.
- **years-regen:** coalesced datoer giver konsistent `years`; forkert coalescet år må ikke lydløst fjerne en gyldig parent-child-kant.
- **Aux-id-resolution:** alias i `ownersByEstate[].personId`, `linjeList.headId`, gemt `meId`, narrativ-link → resolver til kanonisk.
- **Privat-isolation:** privat narrativ/fact fra redaktions-load vandrer IKKE ind i publikums-projektionen.
- **relationship-regression:** node-disjunkthed/`uafhaengige` og anepar-gruppering korrekt efter collapse (to stier gennem samme fysiske person er ikke uafhængige).
- **Aux-projektion:** person-visning for enten III-58 eller V-1 → samme samlede data (union af narrativer/embeder/godser) + multi-linje badge.

## 11. Berørte filer (forventet)

- `web/src/data/collapseSameAs.ts` (ny) + `mobile/src/data/collapseSameAs.ts` (ny, spejlet)
- `web/src/data/model.ts` + `mobile/src/data/load.ts` — hook + fetch af `samme_som`-kanter (godkendte) + `person_external_id` + synlighed
- `web/src/data/types.ts` (+ mobile) — `ModelPerson.mergedFrom?`, `CollapseResult`, `SameAsEdge`
- Person-visning (web + `mobile/src/app/person/[id].tsx`) — alias-resolution, Aux-union, multi-linje badge
- Zustand-store — gem `canonicalIdById` + `mergedFrom`
- Tests: `web/src/data/__tests__/`, `mobile/src/data/__tests__/`

## 12. Dual-review reconcile (Codex adversarial, 2026-07-02)

Verdict: **needs-attention → løst inline.** Codex reviewede både den forudgående tilgang OG det færdige spec. Alle fund verificeret empirisk mod kode før accept (ingen peer-review-laundering).

**Bekræftet (verified empirisk) + rettet i spec:**
- **§6/§7-modstrid** (self-edge karantæne vs. tavs drop) — *semantic*. Verificeret i egen spec-tekst. Rettet: validering på fuldt omskreven kombineret graf FØR drop; self-edge = karantæne-signal.
- **Cyklus for snæver** (kun berørte noder) — *semantic*. Rettet: global reachability + kombineret-projektion-validering (grupper sikre enkeltvis kan konflikte samlet).
- **Kanonisk = unik sink + completeness** — *semantic*. Verificeret (kæde/ambiguøs/cyklus-cases). Rettet §3: unik sink, normalisér parallelle kanter, karantæne ved manglende endpoint (ufuldstændig RLS-komponent).
- **Synligheds-guard uhåndhævelig klient-side** — *false-confidence*. Verificeret mod `db-rls.sql:43` (`person_offentlig = levende=false AND ikke-privat`; kant kun udleveret hvis begge endpoints synlige). Rettet §5: GDPR-mekanisme = completeness + RLS, ikke klient-side `privat`-guard; synlighed = levende OG privat; resultat kan variere pr. klient.
- **Aux ufuldstændig id-projektion** — *semantic*. Verificeret: `linjeByPerson: Record<string,string>` (types.ts:153), `ownersByEstate[].personId` (buildAux.ts:110), `linjeList.headId` (buildAux.ts:87), narrativ = "første offentlige" (public.ts:106). Rettet §8: kanonisér ALLE id-bærende strukturer + meId + narrativ-union + multi-linje.
- **File:line-ankre** — *cleanup*. Rettet: buildModel.ts:23/27-28 (ikke :16), relationship.ts:236 (years).

**Inferred (plausibel, accepteret som defense-in-depth):**
- **Hard vital/køn-konflikt bør blokere** selv blåstemplede links — tilføjet §6.5. Vores links er `afklaret` (en redaktør har vouchet), så dette er belt-and-suspenders mod et fejl-blesset link.

**Impact-buckets:** semantic/silent-corruption ×5 (de fem ovenfor der ville have givet forkerte slægtskaber/tællinger eller skjulte konflikter), false-confidence ×1 (synligheds-guard), defense-in-depth ×1 (vital-blok), cleanup ×1 (ankre).

**Læring:** Klient-side privacy-guards i et RLS-gated system er ofte illusoriske — RLS har allerede fjernet det klienten skulle guarde imod. Den rigtige klient-side invariant er *completeness* ("fold kun hvad jeg kan observere helt"), ikke en re-implementering af synlighedsreglen.
