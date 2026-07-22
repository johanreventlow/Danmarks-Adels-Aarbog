# Præsensliste-visning (beregnet, anker-baseret) — Design

**Dato:** 2026-07-22
**Status:** Godkendt design — afventer implementeringsplan
**Relateret:** `docs/superpowers/specs/2026-07-15-praesensliste-tidsserie-design.md` (som-af/diff mellem
trykte udgaver — ORTOGONALT: dette spec er læsevisningen, tidsserie-spec'et er redaktions-diffen),
`docs/daa-presens-archetype.md` + `.claude/skills/daa-presens/SKILL.md` (parsing af trykte
præsenslister — bruges IKKE af v1, men er leverandør til den fremtidige proveniens-påbygning, §10),
`docs/superpowers/specs/2026-07-02-samme-som-collapse-design.md` (collapse-kernen — forbruges uændret).

## 1. Formål

En **præsensliste** er DAA's læsevenlige familieoversigt omkring en linjes/grens overhoved: overhovedets
egen familie først, derefter **relationsgrupper** (SØSKENDE, MOR, FARBROR, FARFARS BROR …) der samler de
øvrige relevante levende familiemedlemmer med indrykkede undertræer. Afdøde medtages kun som
forbindelsesled til levende. Ægtefæller vises sammen med deres familie. Indryk, rækkefølge og
relationsoverskrifter ER strukturen — den kan ikke erstattes af filtrering på `levende = ja`.

Featuren leverer denne visning digitalt for web og mobil som en **ren beregnet projektion** af
slægtsgrafen. Referenceeksempler: DAA 2012-2014, PDF-side 360-364 (Reventlow I linje + II linje 1.-3.
gren) samt bogens redaktionsprincipper (trykt side 15).

## 2. Rammebeslutninger (alle bruger-godkendte 2026-07-22)

1. **Beregnet, ikke lagret (mulighed A).** Strukturen (grupper, overskrifter, kuratering) beregnes fra
   slægtsgrafen — bogens opstilling lagres ikke som rygrad. Konsekvens: visningen opdaterer sig selv,
   når nye kilder loades (fx en fremtidig præsensliste-udgave som append via load-then-link), og virker
   for alle grene, data dækker. Kilde-proveniens-annotering (mulighed C) er en senere påbygning (§10).
2. **Ankerpersoner er linje-/gren-overhoveder — aldrig frit valg.** Adelsslægter har linjer og grene med
   overhoveder; præsenslisten er slægtens kanoniske opstilling, ikke "en visning omkring vilkårlig
   person". Fra en person-side hopper man til *den gren personen tilhører*.
3. **Overhoveder udpeges redaktionelt som fakta** (§4) — succession er juridisk/sædvane-baseret
   (primogenitur, patenter, adoption) og kan ikke afledes rent af grafen. Ingen automatik.
4. **Redaktion-only v1, bygget som læseflade.** Visningen bygges som rigtig læse-/browseflade i
   Følgesvend (web) + mobil-route, men gated bag login + redaktør-rolle. Når authenticated-tier +
   samtykke er designet (kendt udestående, tidsserie-spec §7), åbnes samme flade for medlemmer — ingen
   ombygning.
5. **Visning + validering.** Kernen genererer moderne overskrifter og udleverer QA-advarsler
   (§7) — men listen redigeres ikke i v1 (fuld "levende liste"-redigering er fravalgt, §10).

## 3. Begreber

| Begreb | Definition |
|---|---|
| **Ankerperson / overhoved** | Personen en grens præsensliste beregnes omkring. Udpeget via overhoved-fakta (§4). |
| **Relationsgruppe** | Selvstændigt begreb: (a) strukturel slægtskabssti fra ankeret (fx `far → far → bror`), (b) genereret dansk overskrift ("FARFARS BROR"), (c) gruppens rodpersoner, (d) hver rods levende-filtrerede undertræ. Overskriften er hverken en person eller en generation — den er en navngiven gruppe der forklarer forbindelsen til ankeret. |
| **Forbindelsesperson** | Afdød person der kun medtages, fordi undertræet under vedkommende indeholder levende (eller en efterlevende ægtefælle). Vises komprimeret (§6). |
| **Blodlinje vs. gift-ind** | Blod = `barn`-kæder i grafen; partnere er gift-ind og vises altid sammen med deres familie. Slægtsafgrænsning følger blodkanter — gift-ind-personers egen slægt medtages aldrig (morens bror er ikke med, præcis som i bogen). |

## 4. Datamodel: overhoved-fakta (ingen skemaændring)

Ny faktatype `overhoved` i `vocab` (invariant 2 + 9: nye behov = nye faktatyper som data, ikke nye
tabeller). Ét fakta pr. udpegning:

- **Subjekt:** personen der er overhoved.
- **Værdi:** linje-/gren-identifikation som struktureret tekst, fx `II linje, 1. gren` — formatet
  fastlægges i implementeringsplanen, men skal kunne sorteres deterministisk (linje-romertal, gren-nr).
- **Kilde:** kildebundet hvor muligt (DAA-udgaven påstår hvem der er overhoved) eller redaktionelt
  (`source_id NULL`) — helt efter evidensmodellen. Successionsskift = ny påstand + ny konklusion;
  intet overskrives.
- **Skrivevej:** eksisterende fact-RPC'er (`red_upsert_fakta`-familien) — ingen ny RPC, ingen ny RLS.
- **Periode:** overhoved-fakta kan tidsafgrænses som alle fakta; visningen bruger den aktuelle konklusion.

Gren-medlemskab lagres IKKE — det afledes af anker-partitioneringen (§5, trin 6).

## 5. Algoritmen `buildPresensListe`

Signatur (packages/core, ren funktion på den **collapsede** model — `collapseSameAs` køres først,
alle id'er er kanoniske):

```
buildPresensListe(model: CollapsedModel, anker: PersonId, alleAnkre: AnkerInfo[]): PresensGren
```

1. **Ankerblok:** anker + partnere + efterkommere rekursivt. Levende medtages; afdøde kun hvis deres
   undertræ indeholder levende eller en efterlevende ægtefælle — ellers udelades de (bogens s. 15-regel).
   Beskæringen er bottom-up: beregn hele undertræet, behold afdøde noder kun med levende under sig.
2. **Opstigning ad blodlinjen:** for hvert forfaderled fra ankeret (forælder, bedsteforælder, …) findes
   forfaderens øvrige børn = sidegrens-rødder. Hver rod med ikke-tomt levende-filtreret undertræ (samme
   beskæring som trin 1) bliver en relationsgruppe-rod.
3. **Gift-ind-grupper:** levende gift-ind-forælder → gruppe MOR (eller FAR — generatoren er
   kønssymmetrisk og følger den forælder, blodlinjen IKKE går via). Afdød blodslægtnings efterlevende
   ægtefælle → ENKE-mønstret (fx FARS ENKE): den afdøde vises forkortet som forbindelsesled, enken under.
4. **Overskrift-generator:** sti → dansk term, tabelstyret og deterministisk. To-leds sammensætninger
   som bogen bruger dem (`far+bror` → FARBROR, `far+far` → FARFAR, `far+søster` → FARS SØSTER); længere
   stier som genitivkæder (FARFARS BROR, FARS FARBROR). Ental/flertal/køn efter gruppens sammensætning:
   én søster → SØSTER, flere → SØSTRE, blandet køn → SØSKENDE; tilsvarende FARBROR/FARBRØDRE/FARS
   SØSKENDE. Altid moderne former — bogens arkaiske varianter ("FARS FARFADERS …") gengives ikke
   (et ikke-problem netop fordi vi genererer; original-formuleringer kommer først ind med
   proveniens-påbygningen §10).
5. **Rækkefølge (deterministisk, verificeret mod DAA 2012-14 I + II linje):** ankerblok → søskende →
   mor → [fars niveau: fars søskende, fars enke] → [farfars niveau] → … — stigende generationsafstand;
   inden for et niveau blod-grupper før gift-ind-grupper; inden for en gruppe personer i fødselsorden.
6. **Anker-partitionering (gren-afgrænsning):** møder opstigningen en sidegren, der indeholder et andet
   udpeget overhoved, springes den over — den dækkes af sin egen gren-sektion. Sidegrene uden eget
   overhoved medtages (det er "FARFARS FARBROR"-tilfældet, PDF-side 362). Grenene partitionerer dermed
   sig selv ud fra ankersættet.
7. **Stop-kriterium:** opstigningen fortsætter, til grafen slipper op, eller ingen resterende sidegrene
   har levende — data afgrænser sig selv.
8. **Usikkerhed:** stier/grupper bygget på `family_member.konfidens` under `sikker` markeres usikre i
   output (invariant 7: usikkerhed vises, skjules aldrig).

Output-kontrakt (form fastlægges i planen): ordnet træ af sektioner — ankerblok + relationsgrupper,
hver med overskrift, sti, rodpersoner, undertræer med indryks-niveau, forbindelsesled-flag,
usikkerheds-flag — plus advarselslisten (§7).

## 6. UI (web + mobil, samme ordforråd)

- **Indgang:** "Præsensliste" i Følgesvend-navigationen (web) + route i mobilens drawer. Forsiden lister
  linjer/grene med overhovednavne (afledt af overhoved-fakta, sorteret); man kan læse én gren eller
  scrolle hele slægten i bogens rækkefølge.
- **Grensektion:** overhoved-blok øverst (navn, titel, partner, børn indrykket), derefter
  relationsgrupper med versal-overskrifter — bevidst typografisk slægtskab med bogen.
- **Afdøde forbindelsespersoner:** komprimeret og kursiveret/nedtonet (som bogens kursiv) — kun navn +
  årstal, ingen fuld post.
- **Ægtefæller:** inline hos deres familie ("g. m. …"), aldrig egne poster.
- **Person-links:** hvert navn linker til person-siden; person-siden får "Vis i præsensliste"-genvej,
  der hopper til personens gren og scroller til personen. Findes personen i ingen gren, forklarer
  genvejen hvorfor (jf. §7).
- **Usikkerhed:** synlig markering med forklaring på usikre grupper/stier.
- **Gating:** hele fladen kræver login + redaktør-rolle i v1 (klient-gate; data er i forvejen
  RLS-beskyttet — se §8).

## 7. Valideringssignaler (redaktions-QA, ikke blokerende)

Kernen udleverer en advarselsliste sammen med visningen; vises som diskret banner for redaktøren:

- **Levende uden gren:** levende person i grafen der ikke lander i nogen gren-sektion (hul i ankersættet
  eller manglende kant).
- **Dobbelt-nået:** person nået ad to veje (identitets-dublet — kandidat til `samme_som`-gennemgang).
- **Gren uden overhoved / overhoved-konflikt:** linje/gren-værdi uden gyldigt fakta, eller to personer
  med samme linje/gren-udpegning.

Ingen advarsel udløser nogensinde en skrivning — ren rapportering.

## 8. RLS / GDPR

- **Ingen ny dataeksponering.** Visningen er en klient-projektion over det datasæt, den indloggede
  allerede må hente. Redaktøren ser alt (eksisterende politikker); anon ser fortsat ingen levende
  (fail-closed, verificeret i prod) — en uindlogget bruger kan derfor pr. konstruktion ikke få en
  meningsfuld præsensliste, og klient-gaten (§6) er UX, ikke sikkerhedsgrænse.
- **Medlems-eksponering er eksplicit fravalgt** indtil authenticated-tier + samtykke-granularitet er
  designet (samme udestående som tidsserie-spec §7 — uændret ejerskab).
- Overhoved-fakta på levende personer er personbundne fakta og dermed allerede gated som alle andre.

## 9. Test

- **Kerne (delte fixtures, vitest + jest):**
  - Beskæringsregel: afdød uden levende under sig udgår; afdød med ét levende barnebarn består som
    forbindelsesled; afdød med efterlevende enke består forkortet.
  - Overskrift-generator: FARBROR / FARS SØSTER / SØSTER↔SØSTRE↔SØSKENDE (ental/flertal/blandet),
    genitivkæder, kønssymmetri (blodlinje via mor → MORS BROR osv.).
  - Anker-partitionering: sidegren med fremmed anker springes over; uden anker medtages.
  - Rækkefølge-determinisme: samme input → samme output, stabil sortering.
  - Konfidens-markering: `formodet`-kant → usikkerheds-flag på gruppen.
  - Advarsler: levende-uden-gren, dobbelt-nået, overhoved-konflikt.
- **Facitliste-test:** II linje, 1. gren fra DAA 2012-14 (PDF-side 362) som fixture — algoritmen skal
  reproducere bogens gruppestruktur (SØSTRE, FARFARS FARBROR) på 2012-14-svarende data. Grenen er
  brugerens egen og kan verificeres manuelt.
- **App (web + mobil):** rendering-snapshot af en gren-sektion; login-gating (uindlogget ser intet);
  person-side-genvejen hopper korrekt.

## 10. Bevidste fravalg (v1)

- **Ingen lagret bogstruktur (mulighed B)** — beregnet visning er rygraden; bogens opstilling er én
  kildes øjebliksbillede.
- **Ingen kilde-proveniens-annotering (mulighed C)** — påbygning når en trykt præsensliste faktisk
  parses og loades (`/daa-presens` + tidsserie-spec'ets load-then-link); da annoteres beregnede grupper
  med original trykt overskrift, og afvigelser flagges.
- **Ingen medlems-eksponering** — venter på authenticated-tier + samtykke.
- **Ingen redaktionel omarrangering/redigering af listen** — fuld "levende liste"-ambition senere;
  v1 redigerer kun via de eksisterende fact-flows (fx overhoved-udpegning).
- **Ingen automatisk overhoved-succession** — skift er altid en redaktionel handling.
- **Ingen frit anker-valg** — præsensliste er kanonisk opstilling omkring overhoveder (beslutning 2).

## 11. Berørte filer (forventet)

- `packages/core/src/presensListe.ts` (ny) — `buildPresensListe` + overskrift-generator + typer;
  `index.ts`-eksport.
- `packages/core/src/__tests__/presensListe.test.ts` (ny) — §9-fixtures inkl. facitlisten.
- Vokabular-seed: `overhoved`-faktatype (idempotent insert i `db-migrations.sql` eller seed-script —
  afgøres i planen; ingen skemaændring).
- `web/src/` — Følgesvend-navigation + `Praesensliste`-visning (gated); person-side-genvej.
- `mobile/src/app/` — drawer-route + visning; person-side-genvej.
- Tests: `web/src/**/__tests__/`, `mobile/src/**/__tests__/`.
- Efter implementering: notat i `docs/decisions.md` (beregnet-frem-for-lagret-beslutningen +
  overhoved-fakta-konventionen) + `docs/changelog.md`.
