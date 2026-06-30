# Handoff: Reventlow-følgesvend — mobil-app

> Udviklerpakke til at bygge mobil-appen "Følgesvend" til *Danmarks Adels Aarbog*
> (PoC: slægten Reventlow). Pakken er selvbærende: en udvikler der **ikke** var med i
> designsamtalen skal kunne bygge appen alene ud fra dette dokument.

---

## 1. Overblik

**Følgesvend** er en digital ledsager til det trykte værk *Danmarks Adels Aarbog*. Brugeren
slår op i en adelsslægt, navigerer stamtræet op/ned/til siden, læser persondetaljer
(biografi, embeder, godser, kilder), finder slægtskab mellem to personer, og markerer sin
egen plads i træet. PoC'en dækker slægten **Reventlow**; modellen er bygget til at rumme
flere slægter som selvstændige datasæt.

Appen er **allerede koblet live** på en eksisterende Supabase-base (se §8). Designet henter
rigtige data derfra. Udviklerens opgave er at **genskabe designet som en rigtig mobil-app**
mod samme backend — ikke at sende HTML-prototypen i produktion.

**To ting der bevidst skal tilføjes i denne implementering** (findes i web-versionen, men ikke
endnu i mobil-designet): **alfabet-hop i søgning/bladring** og fuldt **linje-hop mellem slægtens
grene**. Begge er specificeret med kode i §9 — det var den eksplicitte anmodning bag denne handoff.

---

## 2. Om design-filerne

Filerne i `design/` er **design-referencer skrevet i HTML** — prototyper der viser tiltænkt
udseende og adfærd. De er **ikke** produktionskode der skal kopieres direkte.

- `design/Reventlow-folgesvend-v2.dc.html` — **hoved-designet**. Hele mobil-appen: alle skærme,
  states, interaktioner og live-Supabase-loaderen i én fil.
- `design/_reference_Reventlow-web-v2.dc.html` — desktop/web-versionen. **Kun reference** — her
  ligger alfabet-hop og linje-bladring færdigt (se §9). Byg ikke web-appen nu.
- `design/support.js` — runtime der får `.dc.html`-filerne til at køre i en browser. Åbn en
  `.dc.html` direkte i en browser for at se prototypen. Skal ikke med i produktionsappen.
- `design/assets/daf-logo.png` — Dansk Adels Forenings logo (bruges på forsiden).

Opgaven er at **genskabe disse skærme i et rigtigt mobil-miljø**. Der findes endnu ingen
mobil-kodebase (det tidligere `web/`-skelet var kun til at validere datamodellen og kan
kasseres). Vælg derfor det rette mobil-framework til projektet — se anbefaling i §11 — og
implementér designet der med frameworkets egne mønstre.

---

## 3. Fidelity: **Hi-fi**

Dette er en **high-fidelity** prototype. Farver, typografi, spacing, radier, skygger og
interaktioner er endelige og skal genskabes præcist. Alle værdier står i §6 (design tokens)
og ved hver komponent. Hvor prototypen viser stribede pladsholdere (portræt, våbenskjold,
dokument) er det bevidst tom-tilstand indtil rigtige medier knyttes — genskab pladsholderne,
ikke tilfældige billeder.

---

## 4. Informationsarkitektur

Appen er en enkelt telefon-skærm (designet på 402×858 px "screen", 11px bezel) med:

- **Status bar** (fast, 50px) — klokkeslæt + signal/batteri-ikoner. Erstattes af systemets
  rigtige status bar i en native app.
- **Top bar** (betinget, 52px) — vises på alle skærme undtagen forsiden. Tilbage-pil (‹) når
  relevant + centreret skærmtitel i Cormorant Garamond.
- **Indhold** (scrollbart, fylder resten) — én af 9 skærme.
- **Bund-tabbar** (fast, 66px) — 4 faner: **Hjem · Stamtræ · Slægtskab · Søg**.
- To **bottom-sheet modaler** (person-vælger, slægts-vælger) der glider op over alt.
- Et fint **film-korn + vignet-overlay** over hele skærmen (æstetik — se §6).

### Skærme (9) + modaler (2)

| # | `screen`-værdi | Navn | Tab/indgang |
|---|---|---|---|
| 1 | `home` | Slægts-portal (forside) | Hjem |
| 2 | `tree` | Stamtræ (3 varianter A/B/C) | Stamtræ |
| 3 | `person` | Persondetalje | fra alle lister |
| 4 | `relate` | Er vi i familie? (slægtskab) | Slægtskab |
| 5 | `search` | Søg / bladr i personer | Søg |
| 6 | `about` | Om slægten (historisk indledning) | forside §02 |
| 7 | `estates` | Godser & ejendomme (liste) | forside §03 |
| 8 | `estate` | Gods-detalje (ejer-tidslinje) | fra godsliste |
| 9 | `arms` | Slægtens våben | forside §04 |
| M1 | `picking` | Person-vælger (bottom sheet) | fra slægtskab |
| M2 | `slaegtPicking` | Slægts-vælger (bottom sheet) | fra forsidens slægts-chip |

Tilbage-navigation (`backTo`): person→tree, about→home, estates→home, estate→estates, arms→home.

---

## 5. Skærme i detaljer

Alle mål i px. Fonte: **Cormorant Garamond** (serif, overskrifter/navne), **Hanken Grotesk**
(sans, brødtekst/UI), **JetBrains Mono** (kicker/labels/årstal). Se §6 for fulde tokens.

### 5.1 Forside — Slægts-portal (`home`)
- **Slægts-chip** (øverst): klikbar; rund crest-badge med slægtens initial ("R"), kicker "SLÆGT",
  slægtsnavn i Cormorant 18px, "skift ▾" i bordeaux. Åbner slægts-vælger (M2).
- **Hero**: kicker "DANMARKS ADELS AARBOG" (mono, guld #b9a06a), titel *Slægten* (kursiv grå) +
  slægtsnavn i Cormorant 46px. Bordeaux streg (46×1.5px). Intro-tekst (Hanken 14px, max 280px).
  Tre tællere (personer / linjer / godser) — tal i Cormorant 27px bordeaux, label i mono 9px.
  Dekorativt skjold-omrids i SVG (opacity .13) bag teksten. Elementerne rejser sig sekventielt
  (`daa-rise`, delays .04–.28s).
- **Fremhævet person-kort**: beige (#efe7d7), rund initial-badge, kicker "FREMHÆVET", navn +
  titel. Åbner persondetalje.
- **"Din plads i slægten"** (betinget): hvis brugeren har markeret sig selv (localStorage
  `daa_me_id`), vises et bordeaux-rammet kort med "★ Din plads i slægten"; ellers et mørkt
  (#221f1a) kort "Hvem er du i slægten?" der sender til søgning.
- **"Udforsk slægten"**-liste: 6 nummererede rækker (01–06): Stamtræ, Om slægten, Godser &
  ejendomme, Slægtens våben, Er vi i familie?, Søg. Hver: romertals-stil nummer (Cormorant
  kursiv guld), titel 21px, undertekst, evt. tæller, chevron ›.
- **Footer**: DAF-logo (72px), "Danmarks Adels Aarbog / Udgivet af Dansk Adels Forening",
  mono-note "Live-data fra Adelsårbogens base · proof of concept".

### 5.2 Stamtræ (`tree`) — tre varianter
Sticky topbar i indholdet: segmenteret kontrol **Fokus (A) · Kolonner (B) · Spor (C)**, og
derunder en vandret-scrollende **linje-chip-række** ("Hele slægten" + Linje I–V). *(Linje-rækken
skal aktiveres fuldt — se §9.2.)*

- **Variant A · Fokus**: lodret "kort-fokus". Bedsteforælder-pille (dæmpet) → forælder-kort →
  vandret snap-scrollende række af **denne generations søskende** (178px kort, det valgte i
  bordeaux ramme med "Åbn profil ›"-knap) → evt. "⚭ gift med …" → vandret række af **børn & grene**
  (138px kort). Tryk på et kort flytter fokus; "Åbn profil" går til persondetalje.
- **Variant B · Kolonner**: vandret-scrollende kolonner, én pr. generation (166px brede).
  Drill-down: vælg en person i en kolonne → næste kolonne viser dens børn. Auto-scroller til
  nyeste kolonne (`componentDidUpdate`, `[data-bcols]`).
- **Variant C · Spor**: fuldskærms (560px) snap-navigeret "slægtsspor". Et center-fokus-felt
  (166×118px bordeaux ramme); kort stables lodret pr. generation. **Gestik**: træk lodret =
  skift generation (aner ▲ / efterkommere ▼), træk vandret = skift mellem søskende (◂ ▸),
  fling/kast understøttet, tryk på et kort i fokus = åbn profil. Haptisk feedback
  (`navigator.vibrate(6)`) ved hvert spring. Overlay top: "Gen N · Linje X" + fokusnavn;
  overlay bund: hjælpetekst. Modstand: vandret tærskel 64px, lodret 44px (gren-skift er
  bevidst "tungere"). Se logik-klassens `onSnap*`, `moveSnapGen`, `moveSnapSib`.

### 5.3 Persondetalje (`person`)
- **Header**: portræt-pladsholder (96×120px, stribet) + navn (Cormorant 30px), årstal (mono),
  badges: "★ Dig" (hvis mig), "Linje X", titel-badge (bordeaux #f4e2e6).
- **Barn af**: forælder-navne (klikbare, bordeaux), "&" mellem to forældre.
- **Biografi**: Hanken 14px; klampes til 7 linjer hvis >320 tegn, med "Læs hele biografien" /
  "Vis mindre" toggle.
- **⚭ gift med**: ægtefælle-navne (klikbare hvis personen findes i basen).
- **Børn**: grupperet pr. ægteskab ("Børn med …"); vandret række af runde avatar + fornavn.
- **Embeder, rang & hverv**: liste (label + periode), max 10 + "flere hverv".
- **Godser & besiddelser**: wrap af pille-tags (navn + periode).
- **Materiale**: vandret medie-galleri (120×150px) eller tom-tilstand (3 stribede felter:
  portræt/våben/dokument) med note.
- **Kilder i Aarbogen**: liste med § + værk + "Linje X, nr. N" + "trykt værk".
- **Handlinger** (bund): "Vis i stamtræ" (→ tree variant A, fokus på personen) + "Slægtskab"
  (→ relate med personen som A). Derunder full-width toggle "Det er mig i slægten" /
  "★ Dette er dig — fjern markering".

### 5.4 Er vi i familie? (`relate`)
- Valgfri "★ Sæt mig (navn) som første person"-genvej (hvis mig er sat).
- To person-felter A **&** B (klikbare → person-vælger M1).
- Mørkt resultat-kort (#221f1a): kicker "SLÆGTSKAB", relationsetiket i Cormorant 25px (fx
  "2. grads fætter/kusine · 1 gang forskudt"), evt. "Fælles ane: …".
- **"Forbindelsen, trin for trin"**: lodret tidslinje af personer fra A op til fælles ane (LCA)
  og ned til B; LCA-trinnet markeres guld med "Fælles ane"-label. Se `lcaId`, `chainTo`,
  `relationshipLabel` i logikken for den fulde algoritme.

### 5.5 Søg (`search`)
- Søgefelt "Søg navn…" + resultatliste (rund initial, navn, årstal, chevron). Tom query =
  alle personer (pt. sorteret efter fødselsår). **Skal udvides med alfabet-hop — se §9.1.**

### 5.6 Om slægten (`about`)
- Titel "Slægten Reventlow" + kilde-label. Sektioner med overskrift + brødtekst eller stiplet
  pladsholder-boks ("Indlæses fra stamtavlen") indtil `narrative subjekt_type='slaegt'` har data.

### 5.7 Godser & ejendomme (`estates`)
- Intro + liste af gods-kort (⌂-badge, navn, "N registrerede ejere", chevron). Data fra
  `relation` rolle `ejer`. Tryk → gods-detalje.

### 5.8 Gods-detalje (`estate`)
- Gods-navn + evt. slags-badge. Stiplet "Kommer snart"-boks til godshistorik. **Ejer-tidslinje**:
  lodret prik-og-streg liste af ejere (periode + navn, klikbar → person).

### 5.9 Slægtens våben (`arms`)
- Autoriseret våben (150×185px pladsholder) + blasonering (Cormorant kursiv). Grid 2×N af
  varianter/segl (titel + meta). Stiplet note om at varianter tilføjes løbende.

### Modaler
- **M1 Person-vælger**: bottom sheet (max 74% højde), søgefelt + scroll-liste. Vælger person
  til A eller B i slægtskab.
- **M2 Slægts-vælger**: bottom sheet. Reventlow = aktiv (bordeaux); Bardenfleth /
  Ahlefeldt-Laurvig / Scheel = "ikke tilføjet" (dæmpet, ikke-klikbar).

---

## 6. Design tokens

### Farver
| Token | Hex | Brug |
|---|---|---|
| Bordeaux (primær) | `#881A33` | accenter, aktive states, knapper, navne-links |
| Bordeaux-fyld lys | `#f8ecef` / `#f4e2e6` | aktive kort-baggrunde, badges |
| Blæk (tekst) | `#221f1a` | overskrifter, primær tekst; også mørke kort |
| Tekst sekundær | `#3d382f` / `#6f675b` | brødtekst |
| Tekst dæmpet | `#9a8f78` / `#a99f8c` / `#b0a691` | mono-labels, årstal |
| Guld | `#b9a06a` | kickers, "fælles ane", dekorativ |
| Guld lys | `#e7c98f` | accent på mørke kort |
| Papir (app-bg) | `#f4efe6` | indholds-baggrund |
| Papir-kort | `#fbf8f1` | kort, felter |
| Beige | `#efe7d7` / `#ece4d6` / `#e6ddcc` | sekundære kort, badges, segment-spor |
| Ramme | `rgba(34,31,26,.08–.14)` | borders, separatorer |
| Sandkasse-bg (uden for telefon) | `#e7e3da` | — |

### Typografi
- **Cormorant Garamond** — 500/600, normal+kursiv. Overskrifter 30–46px, navne 16–23px,
  kursiv til "Slægten", "& ", "gift med".
- **Hanken Grotesk** — 400/500/600/700. Brødtekst 12–15px, UI-labels, knapper.
- **JetBrains Mono** — 400/500. Kickers/labels 8–11px, `letter-spacing .1–.22em`,
  `text-transform: uppercase`. Årstal/perioder.
- Google Fonts import:
  `Cormorant+Garamond:ital,wght@0,500;0,600;1,500;1,600` · `Hanken+Grotesk:wght@400;500;600;700`
  · `JetBrains+Mono:wght@400;500`

### Radier
Felter/knapper 9–14px · kort 11–16px · badges 7–9px · chips/piller 16–20px · bottom sheet
top-hjørner 22px · runde avatarer 50%.

### Skygger
- Kort: `0 1px 2px rgba(34,31,26,.03–.05)`
- Valgt kort: `0 4px 14px rgba(136,26,51,.14)`
- Telefon-bezel (kun prototype): `0 50px 100px rgba(20,17,13,.34)`

### Animationer
- `daaScreen` — skærm-skift: `translateY(9px)→0`, `.44s cubic-bezier(.2,.7,.2,1)`.
- `daaRise` — forside-elementer rejser sig sekventielt: `translateY(13px)→0`, `.62s`,
  delays `.04 / .10 / .16 / .22 / .28s`.
- Variant C snap: `transform .42s cubic-bezier(.22,.61,.36,1)`; haptisk `vibrate(6)`.

### Tekstur-overlays (æstetik, læg øverst i z-stakken, `pointer-events:none`)
- **Film-korn**: inline SVG `feTurbulence` (baseFrequency 0.9), `mix-blend-mode:multiply`,
  opacity .5.
- **Vignet**: `radial-gradient(118% 90% at 50% 22%, transparent 56%, rgba(54,40,22,.09) 100%)`.

### Tweakable props (på rod-komponenten)
- `defaultVariant`: `'A' | 'B'` (+ C via segment) — startvisning af stamtræ.
- `showLifeYears`: `boolean` — vis/skjul leveår globalt.

---

## 7. State & interaktioner

Central state (se logik-klassen i hoved-designet):

```
screen        // aktiv skærm (se §4-tabel)
variant       // 'A' | 'B' | 'C' — stamtræ-visning
focusId       // person i fokus (variant A)
path[]        // drill-down-sti (variant B)
snapPath[], snapDepth   // variant C navigationstilstand
personId      // åben persondetalje
relA, relB    // de to personer i slægtskab
picking       // 'A' | 'B' | null — person-vælger åben for hvilket felt
query         // søgetekst (deles af søgning + vælgere)
meId          // brugerens egen person (localStorage 'daa_me_id')
slaegtPicking // slægts-vælger åben
bioExpanded   // biografi udfoldet
activeLinje   // valgt linje (grenefilter) — udbyg, se §9.2
```

Interaktionsmønstre der skal bevares: sekventiel rise-animation på forsiden, skærm-fade ved
navigation, vandret snap-scroll i variant A's generationsrækker, drill-down med auto-scroll i
variant B, gestus-navigation + haptik i variant C, bottom-sheet-modaler, biografi-klamp/udfold,
"mig"-markering i localStorage.

**Slægtskabs-algoritme** (skal genimplementeres 1:1): `ancestorsInclusive` → `lcaId` (laveste
fælles ane) → `chainTo` (kæde fra person til LCA) → `relationshipLabel(d1, d2)` der oversætter
generations-afstande til danske etiketter (søskende, onkel/tante, N. grads fætter/kusine ·
forskudt, forælder/barn-aner). Hele koden ligger i `renderVals()`'s `rel`-blok.

---

## 8. Data & backend (eksisterer allerede)

Appen henter live fra Supabase (PostgREST). **Backend og data er på plads** — kun den
offentlige anon-/publishable-nøgle bruges; RLS styrer læseadgang.

```
url:     https://xjnvdhajfyrcytatnzos.supabase.co
anonKey: sb_publishable_…   (offentlig — se loadFromSupabase i designet for fuld værdi)
```

Fuld felt-mapping og koblings-noter: **`data/supabase-kobling.md`**.
Den fulde, principielle datamodel (entiteter, relationsmekanisme, evidenslag, adelslag, GDPR):
**`data/datamodel-oversigt.md`**.

### Kerne-mapping (model → app)
| App | Kilde |
|---|---|
| Navn | `person.visning_navn` |
| Leveår | `person.visning_foedt` / `visning_doed` (vis ordret: `* 1640`, `† 1708`, intervaller, floruit) |
| Titel | `person.visning_titel` |
| Biografi | `narrative.tekst` (`subjekt_type='person'`, ikke-privat) |
| Forælder ↔ barn | `family_member` grupperet pr. `family_id`; roller `partner`×`barn` |
| Ægtefæller | de to `partner`-roller i samme `family` |
| Linjer (grene I–V) | `person_external_id.linje` (+ `nr` for stamfader = laveste nr) |
| Embeder/hverv | `relation` → `organisation` (med `periode_raw`) |
| Godser | `relation` rolle `ejer` → `estate` (med periode) |
| Kilder | `person_external_id` → `source` ("Linje X, nr. N" + trykt værk) |
| Medier | `media` (tom indtil linket — vis tom-tilstand) |
| Privat | `person.privat` / `narrative.privat` — skjul |

### Vigtige adapter-detaljer (skal med)
- **Rolle-vokabular**: `parentRoles = ['partner']`, `childRoles = ['barn']`. Kun `barn` er
  blodslægtskab.
- **Person-id er `bigint`** — konverteres til streng internt i appen.
- **PostgREST returnerer max 1000 rækker pr. svar** uanset `limit` → **sideinddel alle
  hentninger med `offset`**. Uden dette mangler alle familier/relationer efter de første 1000
  rækker (nyere personers forældre/børn/ægtefælle bliver ikke forbundet). Se `getAll()` i
  designet.
- **Offline-fallback**: designet har en indlejret lokal Reventlow-seed (`db`-objektet) som
  bruges hvis hentning fejler. I produktion kan dette droppes eller beholdes som cache.
- **"Mig"** ligger pt. i `localStorage` (`daa_me_id`). I produktion flyttes til
  `profiles.reventlow_person_id` (feltet findes), så det følger brugerkontoen.

---

## 9. Funktioner der skal tilføjes (kernen i denne handoff)

Begge findes færdige i **`design/_reference_Reventlow-web-v2.dc.html`** — løft mønster og
værdier derfra ind i mobil-appen.

### 9.1 Alfabet-hop i søgning/bladring
Som på web: over personlisten vises **hele alfabetet** (de bogstaver der faktisk forekommer)
som klikbare chips; klik filtrerer/hopper til navne på det bogstav. Listen grupperes med
sticky bogstav-headers. En sortér-toggle skifter mellem **alfabetisk** og **efter fødeår**;
alfabet-baren skjules i fødeår-sortering og når der søges.

Reference-logik (fra web-versionen, `renderVals()`):
```js
// initial på efternavn/visningsnavn — dansk sortering (Æ Ø Å til sidst)
const present = {}; pool.forEach(p => { present[initialOf(p)] = true; });
const letterKeys = Object.keys(present).sort((a,b) => a.localeCompare(b,'da'));
showLetters = (browseSort !== 'born' && !query && letterKeys.length > 1);
letters = [{label:'Alle', key:null}].concat(letterKeys.map(k => ({label:k, key:k})));
// aktiv chip: bordeaux #881A33 fyld / #f4efe6 tekst; ellers transparent / #6f675b
// onTap: setState({ activeLetter: key })

let matches = pool.filter(p => !q || p.name.toLowerCase().includes(q));
if (!q && browseSort !== 'born' && activeLetter)
  matches = matches.filter(p => initialOf(p) === activeLetter);
matches.sort(browseSort === 'born' ? sortBorn : sortName);

// grupper med sticky headers (kun alfabetisk, ingen query):
const byL = {}; matches.forEach(p => { (byL[initialOf(p)] ||= []).push(p); });
browseGroups = Object.keys(byL).sort((a,b)=>a.localeCompare(b,'da'))
  .map(k => ({ letter:k, hasHeader:true, people: byL[k] }));
```
Markup: chip-række (`flex-wrap`, gap 3px, mono 10px, min-bredde 19px) over en liste hvor hver
gruppe har en **sticky** bogstav-header (`position:sticky; top:0; Cormorant 15px guld #b9a06a`).
På mobil: behold dette og overvej desuden et lodret A–Å-index i højre kant (valgfrit), men
chip-rækken + sticky headers er minimumskravet for at matche web.

State der skal tilføjes: `browseSort: 'alpha'|'born'`, `activeLetter: string|null`.
Definér `initialOf(p)` konsistent (efternavn først; dansk collation `'da'` så Æ/Ø/Å sorteres korrekt).

### 9.2 Linje-hop mellem grene
Stamtræets linje-chip-række (allerede i mobil-markup'en som `linjeChips` + "Hele slægten")
skal være **fuldt funktionel** som på web: hver linje I–V er en chip; klik hopper fokus til
linjens **stamfader** (medlemmet med laveste `nr` i `person_external_id`) og filtrerer træet til
den gren. "Hele slægten" rydder filteret tilbage til slægtens rod.

Relevant logik findes i mobil-designet (`pickLinje`, `clearLinje`, `setLinje`, `linjeChips`,
`aux.linjeList` med `headId`) — sørg for at den er aktiv i alle tre træ-varianter og at
`activeLinje` driver chip-highlight (aktiv = bordeaux fyld). I variant C vises "Linje X" allerede
i top-overlay; hold den synkron med valgt linje.

Datakilde: `person_external_id.linje` (gren-bogstav) + `nr` (rækkefølge i grenen; laveste =
stamfader). `aux.linjeList` bygges i `buildAux()`.

---

## 10. Skærm-til-skærm flow (navigation)

```
Hjem ──┬─ slægts-chip ─────────────► [M2] Slægts-vælger
       ├─ Fremhævet / Din plads ───► Persondetalje
       ├─ §01 Stamtræ ─────────────► Stamtræ (A/B/C, linje-filter)
       ├─ §02 Om slægten ──────────► Om slægten
       ├─ §03 Godser ──────────────► Godsliste ──► Gods-detalje ──► Persondetalje
       ├─ §04 Våben ───────────────► Slægtens våben
       ├─ §05/Slægtskab-tab ───────► Er vi i familie? ──► [M1] Person-vælger
       └─ §06/Søg-tab ─────────────► Søg (alfabet-hop) ──► Persondetalje

Stamtræ ──► tryk kort ──► Persondetalje ──► "Vis i stamtræ" / "Slægtskab" / "Det er mig"
Persondetalje ──► forælder/ægtefælle/barn-navn ──► Persondetalje (rekursivt)
Bund-tabbar (overalt): Hjem · Stamtræ · Slægtskab · Søg
```

---

## 11. Anbefaling til implementering

- **Framework**: en rigtig mobil-app peger på en eksisterende web-Supabase. Vælg ud fra
  målet — fx **React Native / Expo** (én kodebase iOS+Android, deler `@supabase/supabase-js`
  og TypeScript-typer med en kommende web-version) eller **native SwiftUI** hvis kun iOS og
  maksimal polish prioriteres. Gestus-tunge variant C taler for native eller en moden
  gesture-lib (Reanimated/Gesture Handler i RN).
- **Datalag**: genbrug mapping-logikken fra designet (`buildModel`, `buildAux`, `loadFromSupabase`)
  næsten 1:1 — den er allerede skrevet mod den rigtige base. Husk `offset`-pagineringen.
- **Tilstand**: let global store (Zustand/Redux i RN, eller `@Observable` i SwiftUI) til
  `screen/variant/focus/path/me/aktiv-linje`.
- **Fonte**: bundl Cormorant Garamond, Hanken Grotesk, JetBrains Mono med appen.
- **Tekstur-overlays**: kan droppes på meget svage enheder, men de bærer en stor del af
  æstetikken — behold dem hvor muligt.

---

## 12. Filer i pakken

```
design_handoff_folgesvend_mobile/
├── README.md                                   ← dette dokument
├── design/
│   ├── Reventlow-folgesvend-v2.dc.html         ← HOVED-DESIGN (åbn i browser for at se appen)
│   ├── _reference_Reventlow-web-v2.dc.html     ← web-version (reference til alfabet+linje-hop)
│   ├── support.js                              ← runtime så .dc.html kan åbnes lokalt
│   └── assets/daf-logo.png
└── data/
    ├── supabase-kobling.md                     ← live felt-mapping + adapter-noter
    └── datamodel-oversigt.md                   ← fuld principiel datamodel
```

Åbn en `.dc.html` direkte i en browser for at klikke rundt i prototypen. Live-data hentes
automatisk fra Supabase ved indlæsning; ved netværksfejl falder den tilbage til den indlejrede
Reventlow-seed.
