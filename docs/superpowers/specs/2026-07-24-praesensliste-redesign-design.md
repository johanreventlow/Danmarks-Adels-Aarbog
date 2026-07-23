# Præsensliste — visuel redesign (design-spec)

**Dato:** 2026-07-24
**Status:** Godkendt af bruger, klar til implementeringsplan
**Design-kilde:** Claude Design-projekt "Danmarks Adels Aarbog app" (`0d84324f-…`),
fil `Reventlow-praesens.dc.html`

## 1. Kontekst og scope

Præsenslisten er allerede fuldt implementeret som **beregning** (PR #76/#77,
`feat/praesensliste`, mergeret til `origin/main` 2026-07-23/24):

- `packages/core/src/presensListe.ts` — anker-baseret undertræs-beskæring
  (`pruneUndertrae`), patrilineær gren-tilhør (`patrilinealForaelder`),
  krydshenvisnings-stubs for konvergente slægtskaber, dæknings-advarsler
  (`levende_uden_gren`, `dobbelt_naaet`, `anker_konflikt`).
- `packages/core/src/presensLabels.ts` — anker-parsing (`"II linje, 1. gren"` →
  `{linje:'II', gren:1}`) og moderne relationsbetegnelser (`Farbror`, `Farfars
  farbror`, `Fars søster` …).
- `web/src/components/PresensView.tsx` + `web/src/data/presens.ts` — henter
  grundlaget (levende-flag + overhoved-fakta via `fact`/`conclusion`/`assertion`)
  og kører beregningen. **Visningen er i dag en ustylet, flad, redaktør-gated
  liste** — ingen linje-gruppering, ingen intro-tekst, intet våben.

**Denne opgave er derfor et redesign af visningslaget**, ikke ny
beregningslogik. Kerne-algoritmen (anker-klatring, krydsreference,
advarsler) er allerede bygget, testet mod et facit (DAA 2012-14 II linje
1. gren) og rører ikke ved.

**Ude af scope:**
- Mobil-skærmen (`mobile/src/app/praesens.tsx`) redesignes ikke i denne omgang —
  forbliver den nuværende simple liste.
- Adgang forbliver redaktør-gated (RLS er sikkerhedsgrænsen; medlems-login-laget
  er en separat, ikke-bygget opgave).
- Antals-opsummering pr. gren ("N levende · M forbindelsesled") **udgår bevidst**
  — vurderet unødvendigt makabert at fremhæve dødstal ved siden af en gren-etiket.

## 2. Datamodel-ændringer

### 2.1 Linje-titel (kort undertitel, fx "Den lensgrevelige linje af 1767")

**Verificeret via dokumentation** (live prod-query blev blokeret af
permission-classifier under brainstorm; krydstjekket i to uafhængige,
daterede kilder i stedet): `lineage.navn`
indeholder allerede præcis denne slags deskriptiv titel for alle 5
eksisterende rækker: I=Den holstenske linje, II=Linjen Gallentin, III=Den
mecklenburgske linje, IV=Den lensgrevelige linje af 1767, V=Den grevelige
linje af 1673 (`docs/changelog.md:1750-51`,
`docs/superpowers/specs/2026-07-03-udledt-slaegtsnavn-design.md:38`:
"`lineage.navn` — deskriptivt, IKKE et efternavn"). **Ingen ny kolonne
nødvendig** — dette erstatter den oprindelige "ny kolonne"-beslutning, som
blev truffet før denne verifikation.

`lin.navn` i mockuppet (stavevariant, "Reventlou" vs. "Reventlow") svarer til
den eksisterende `lineage.slaegtsnavn` (Udledt Slægtsnavn, live).

Der findes i dag kun 5 `lineage`-rækker totalt, ét pr. `kode` — ingen
kode-kollision på tværs af kilder at disambiguere for. Opslag sker derfor
direkte på `kode` uden `source_id`-filtrering.

### 2.2 Våbenskjold → linje

Ingen data koblet i dag (bekræftet: `ArmsView.tsx`/`arms.tsx` har eksplicitte
pladsholdere). Følger mønsteret allerede skitseret i `schema.sql`s kommentar
ved `lineage.parent_lineage_id`:

1. **`media`**-række pr. våbenbillede (fysisk fil — de findes allerede som
   PNG i design-projektet: `linje-I.png`, `linje-II.png`, samt det generelle
   `grundvaaben`/sepia-varianter til evt. fallback).
2. **`coat_of_arms`**-række (blasonering, evt. tom for nu).
3. **`relation`**: `subjekt_type='lineage'`, `subjekt_id=<lineage.id>`,
   `objekt_type='coat_of_arms'`, `objekt_id=<coat_of_arms.id>`,
   `rolle='vaaben'` (ny vocab-kode i scheme `'rolle'`).

To hop — **genbruger eksisterende, allerede-implementeret infrastruktur**
(`web/src/data/public.ts:fetchArms()` gør nøjagtig dette for
familie-niveauets våben i dag; kun hop 1 er nyt):

1. `relation(subjekt_type='lineage', objekt_type='coat_of_arms',
   rolle='vaaben')` — hvilket våben hører til linjen. **Ny relationstype**,
   `rolle='vaaben'` tilføjes til `vocab(scheme='rolle')`.
2. `relation(subjekt_type='media', objekt_type='coat_of_arms',
   rolle='afbildet')` — hvilken billedfil viser det våben. **Findes
   allerede** som konvention (`fetchObjectMedia()` i `web/src/data/media.ts`
   forudsætter præcis denne retning/rolle) — genbruges uændret, ingen ny kode.

Web-laget: slå `coat_of_arms.id` op pr. linje via hop 1, kald derefter den
eksisterende `fetchObjectMedia('coat_of_arms', armIds)` (uændret) for
billed-URL'en.

### 2.3 Præsens-intro (dedikeret narrativ)

- Ny `source`-række: `slags='præsens-intro'` (eller lignende kortfattet
  værdi), ingen `udgave`/`aar` nødvendig (det er ikke en trykt udgave).
- Ny `narrative`-række: `subjekt_type='slaegt'`, `subjekt_id=1` (samme
  sentinel som "Om slægten"), `source_id=<ny>`, `tekst=<de to
  intro-afsnit fra mockuppet, redigerbare>`.
- **Ingen ændring** af den eksisterende `fetchAbout()`-mekanisme eller dens
  narrativ — præsens-introen er en sideordnet, selvstændig kilde til samme
  `subjekt_type='slaegt'`-subjekt, adskilt ved `source_id`. Web henter den med
  samme `pickPreferredBio`-mønster, filtreret til den nye kilde.

## 3. Beregnings-lag (ny, ren funktion i `@daa/core`)

**Gren-gruppering:** `PresensListe.grene` er allerede korrekt sorteret
(`sortAnkre`) men flad — én indgang pr. anker uanset linje. Tilføj:

```ts
export function groupByLinje(grene: PresensGren[]): { linje: string; grene: PresensGren[] }[]
```

Ren, stabil gruppering på `gren.anker.linje` (bevarer eksisterende
rækkefølge). Ingen ændring af `buildPresensListe` selv.

*(Antals-helper fra tidligere udkast er droppet efter brugerfeedback.)*

## 4. Visuel redesign af `PresensView.tsx`

Struktur, top til bund (jf. `Reventlow-praesens.dc.html`), alt via
eksisterende `T`-tokens fra `web/src/theme.ts` (farver/fonte matcher
mockuppet 1:1 — ingen nye tokens):

1. **Brødkrumme**: "Reventlow / Præsensliste".
2. **Titelblad-kort** (`T.paper`-baggrund, border, skygge): sepia-grundvåben,
   "Slægten Reventlow", H1 "Præsensliste", ajourført-dato, guld-streg.
3. **Præsens-intro**: 1-2 afsnit fra §2.3, kursiv serif, centreret, max-bredde.
4. **Redaktionelle advarsler**: samme data som i dag (`liste.advarsler`),
   ny styling — sammenklappelig `<details>`-boks med amber-baggrund,
   ▲-markør pr. linje. Ingen ny logik.
5. **Venstre sticky-indeks**: genereret fra den grupperede liste
   (`groupByLinje`) — linje-numre + gren-etiketter som ankerlinks, plus en
   statisk signatur-boks (fed=levende, kursiv=afdød forbindelsesled, ⚠, ↗).
6. **Pr.-linje sektion**: våben (§2.2) + linjenummer + titel (§2.1) + navn
   (`slaegtsnavn`), derefter dens grene i rækkefølge.
7. **Pr.-gren sektion**: `N. gren`-etiket (uden antal, jf. brugerfeedback) +
   den eksisterende node-rendering (kursiv/farve/⚠/↗/"g. m." — genbruges
   uændret fra nuværende `renderNode`).
8. **Kildenote**: statisk footer-tekst.

Header/nav-chrome (DAF-logo, "Følgesvend"-navigation, Reventlow-chip) leveres
allerede af det omsluttende `Folgesvend.tsx`-skal og ændres ikke.

## 5. Test

- Opdatér `PresensView.test.tsx` til at dække `groupByLinje`-baseret
  rendering (linje-sektioner, gren-etiketter uden antal).
- Ny enheds-test for `groupByLinje` i `packages/core/src/__tests__/`.
- **Ingen ændring** af `presensListe.test.ts`/`presensFacit.test.ts`/
  `presensLabels.test.ts` — anker-algoritmen er urørt.
- Manuel verifikation: kør web lokalt, log ind som redaktør, tjek at
  eksisterende data (uanset hvor mange overhoveder der reelt er udpeget i
  prod) renderer uden fejl, inkl. 0-, 1- og flere-linjer-tilfælde.

## 6. Rækkefølge (til implementeringsplan)

1. Verificér `lineage.navn`-indhold i prod (afgør 2.1's forgrening).
2. Datamodel: evt. `lineage.titel`-migration; `coat_of_arms`+`media`+
   `relation`-rækker for I/II linje; ny `source`+`narrative` for præsens-intro.
3. `@daa/core`: `groupByLinje` + tests.
4. Web data-lag: udvid `presens.ts` (eller ny fil) til at hente
   linje-metadata (våben, titel, navn) + præsens-intro-narrativ.
5. Web visning: redesign `PresensView.tsx` efter §4.
6. Opdatér/tilføj tests (§5).
7. Manuel verifikation mod lokalt miljø.
