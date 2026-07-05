# Billeder: størrelser, artikel-integration og lightbox — designoplæg

*Planlægningsdokument (ingen kode ændret endnu). Producereret af en Opus-planlægningsagent,
briefet med den faktiske kodebase (schema.sql, db-rls.sql, mentions.ts, NarrativRenderer.tsx,
eksisterende visningsstørrelser) — 2026-07-05, i forlængelse af mediehåndtering Slice 0g/0h.
Alle 5 åbne spørgsmål er afklaret med bruger samme dag (se §6) — planen er klar til
implementering, startende med Slice A.*

## Kort resumé (hvis du kun læser ét afsnit)

- **Størrelser: 3 niveauer, ikke 4.** `thumb` (~500px), `medium` (~1100px), `large` (~2000px). Det
  fjerde niveau ("small") giver ingen målbar gevinst over `thumb`. `medium` er kun berettiget på
  grund af artikel-ønsket (flere billeder i én tekst), ikke af noget der findes i appen i dag.
- **Skema: en ny lille barn-tabel `media_variant`**, ikke ekstra kolonner på `media`. Der er en
  konkret teknisk grund forankret i den allerede-udrullede sikkerhedsopsætning (forklaret nedenfor),
  ikke bare "det er pænere".
- **Artikler: byg IKKE en ny "artikel"-entitet nu.** Udvid i stedet den rendering der allerede
  findes, så `[[media:123|billedtekst]]` viser et rigtigt billede inde i en narrativ. En egentlig
  fritstående artikel-type er en større, separat beslutning der fortjener sin egen brainstorm.
- **Lightbox (klik-for-at-forstørre): dette er det mindste første skridt der giver mest synlig
  værdi**, og det afhænger IKKE af størrelses-arbejdet. Det kan bygges oven på de billeder der
  allerede er uploadet.

---

## 1. Hvor mange billedstørrelser skal vi gemme?

### Baggrund
Fordi bucket'en er privat og serveres via korttidsgyldige "signed URLs", kan man **ikke** bruge
det sædvanlige web-trick hvor en URL bedes om en mindre version on-the-fly (det kræver Supabases
betalte Image Transformations, som ikke er på gratis-planen). Hver størrelse skal derfor være en
**rigtig, separat fil** i storage. Alternativet — at hente det store billede og formindske det i
browseren/telefonen ved hver visning — koster CPU hver gang OG henter allerede de tunge bytes, så
det underminerer hele pointen. **Konklusion: de størrelser man vil have, gemmes som faktiske
filer. De der ikke gemmes, lader man bare skærmen vise mindre (sparer ingen båndbredde, men er
gratis).**

### Anbefaling: 3 niveauer

| Niveau | Længste kant | JPEG-kvalitet | Forventet filstørrelse | Dækker |
|---|---|---|---|---|
| `thumb` | ~500 px | ~70 | 40–80 KB | Alt der findes i appen i dag: 96/120/180px-slots. 500px = skarpt selv på 3x-retina-skærme. |
| `medium` | ~1100 px | ~78 | 120–250 KB | Billeder indlejret i løbende artikel-/narrativtekst. |
| `large` | ~2000 px | ~82 | 350–700 KB | Lightbox / fuld visning. |

### Hvorfor ikke 4 (dropper "small")?
Et "small"-niveau mellem thumb og medium ville ligge omkring 700–800px. Men `thumb` på 500px
dækker allerede alle nuværende visningskontekster med god margin, og til alt hvad der er *større*
end en thumbnail (indlejret i tekst) vil `medium` se bedre ud. Et fjerde niveau tilføjer et niveau
at generere, gemme, vælge imellem og fejlsøge — uden en visningskontekst der reelt kræver netop
den størrelse. Regel: **et niveau skal fortjenes af en konkret visningskontekst, ikke af en
fornemmelse af "midt imellem".**

### Hvorfor `medium` overhovedet fortjener sin plads
`medium` er den eneste af de tre der IKKE er begrundet i noget appen viser i dag. Den fortjener sin
plads udelukkende af artikel-ønsket: en artikel med fem indlejrede billeder har ikke råd til fem
`large`-filer (op mod 3-4 MB tekstside) som browseren så skalerer ned. Med `medium` bliver samme
side ~1 MB. **Så: hvis der aldrig ønskes flere billeder i én tekst, kan størrelses-laddet skrumpe
til bare thumb + large.** Det er den beslutning der driver tier-tallet — ikke skærmstørrelser.

### En gratis sidegevinst ved altid at genkomprimere ved upload
Den nuværende upload accepterer HEIC (Apple-fotoformatet). Rå HEIC vises **ikke** i
web-browsere — så et HEIC-portræt uploadet fra en iPhone i dag ville være usynligt på web. Når der
alligevel skal genkodes klient-side før upload (Canvas på web, `expo-image-manipulator` på
mobil), laves alt om til JPEG samtidig. Det retter denne latente fejl som en bivirkning. Endnu et
argument for at genkode selv `large`-niveauet frem for at uploade råfilen.

---

## 2. Hvordan repræsenteres flere størrelser af ét logisk billede i databasen?

### De to muligheder
**(a) Ekstra kolonner på `media`:** `storage_path_thumb`, `storage_path_medium`, … Simpelt,
matcher den flade rækkestil der allerede findes. Men binder rækken til et fast antal niveauer —
hvert nyt niveau kræver en skemamigrering.

**(b) En barn-tabel `media_variant(media_id, tier, storage_path, bredde, hoejde, byte_size)`:**
Mere normaliseret, udvideligt uden migrering, matcher projektets generelle forkærlighed for
generiske mønstre (jf. `relation`-tabellen). Koster et join.

### Anbefaling: (b) barn-tabellen — og der er en konkret grund ud over smag
Den **allerede-udrullede** storage-sikkerhed er den afgørende faktor. I `db-rls.sql:109` slår
funktionen `media_id_for_object(name)` et storage-objekt op ved præcist
`media.storage_path = name`, og begge de offentlige læse-politikker (linje 215/218) går gennem
den. **Konsekvens: hvert variant-objekt skal kunne slås tilbage til sin forælder-medierækkes
rettighedskontrol — ellers giver opslaget NULL → `media_rettigheder_ok(NULL)` = false → nægtet
for offentligheden.** Et variant-billede der ikke kan mappes til en medierække er altså usynligt.

- Med **barn-tabellen** udvides `media_id_for_object` ét sted til også at kigge i `media_variant`
  og returnere forælder-`media_id`. Nye niveauer kræver derefter **nul** RLS-ændringer.
- Med **kolonner** skal `media_id_for_object` omskrives hver gang der tilføjes et niveau.

Det peger konkret og projekt-forankret på barn-tabellen. (Bemærk: dette dræber samtidig to gamle
idéer fra `2026-07-04-mediehaandtering.md` §0a — "deterministisk sti fra sha256 uden DB-række"
fejler netop denne RLS-mapping, og dens "Supabase image-transformation"-fallback kræver Pro-plan.
De to linjer i den gamle plan er forældede.)

To vigtige detaljer:
- **`sha256`-dedup forbliver kun på originalen.** `media.sha256`-unik-indekset er til at fange
  "samme fil uploadet to gange". Varianter er *afledte* filer — de skal ikke hash-dedupes og skal
  ikke have en sha256. Hold indekset som det er.
- **`media_variant` skal stå UDEN FOR versionerings-systemet** (ikke i `version_pk_registry`,
  ingen historik-trigger). Varianter er regenererbar cache-agtig data, ikke redaktionelle fakta.
  De hører ikke hjemme i fortryd-/assertion-modellen. Originalen (`media`-rækken) er fortsat
  versioneret som nu.

---

## 3. "Artikler med integrerede billeder" — arkitektur

Dette er punktet hvor det er vigtigst at skelne mellem **hvad der behøves NU** og **en større
separat beslutning**.

### Hvad der reelt bedes om lige nu
Løbende tekst med et billede indsat inde i den, "ikke for stort, ikke for lille". Byggestenene
findes allerede:
- `[[media:123|billedtekst]]`-syntaksen **parses allerede** i dag (`mentions.ts` inkluderer
  `media` som gyldig type).
- `NarrativRenderer` viser i dag `media`-tokens som **inaktiv grå tekst** — en ubrugt krog, ikke
  død kode der skal fjernes.

### Option A — udvid det eksisterende narrativ + mention-system (anbefalet til nu)
Få `NarrativRenderer` (begge platforme) til at rendere `[[media:123|tekst]]` som et rigtigt
`medium`-billede med billedteksten under, klikbart til lightboxen — i stedet for grå tekst.
Genbruger alt: teksten gemmes hvor den allerede gemmes, versioneres som den allerede versioneres,
og redaktøren får en "indsæt billede"-knap ved siden af den eksisterende "indsæt mention"-vælger
(`MentionPicker` findes allerede på mobil).

**Ærlig omkostning:** dette er ikke en enkelt-linjes ændring på mobil. React Native tillader ikke
at man dropper et `<Image>` ind midt i det `<Text>`-flow som `NarrativRenderer` bruger i dag. For
at vise et billede *som blok mellem tekstafsnit* skal rendereren laves om fra "én tekststrøm" til
"en vekslen mellem tekststykker og billedblokke" — på begge platforme. Det er stadig det rigtige
valg, men den reelle pris er en **omskrivning af rendereren til blok-niveau**, ikke "byt grå tekst
ud med et img". (På web er det næsten trivielt; på mobil er det den egentlige opgave.)

**Ærlig vurdering af pasformen:** `narrative` er i dag bundet til (subjekt, kilde/DAA-udgave) —
altså "denne persons biografi ifølge DAA 1939". Det passer fint til "et billede inde i en persons
biografitekst". Det passer *mindre* godt hvis man forestiller sig en fritstående artikel der ikke
handler om én bestemt person/familie/slægt og har sit eget publikationsforløb. Men — og det er
pointen — **det behøver ikke løses nu.**

### Option B — en ny selvstændig `article`-entitet
En dedikeret tabel til illustreret langform-indhold der ikke nødvendigvis er bundet til
person/kilde-modellen, med sit eget indlejrings-mekanik (kan genbruge samme token-grammatik,
eller Markdown-agtig `![tekst](media:123)`). Dette er en rigtig CMS-agtig funktion med egne
spørgsmål: hvem er målgruppen, hvordan publiceres den, skal den have kategorier/forfatter/dato,
osv.

### Anbefaling: hybrid, men gør kun halvdelen nu
1. **Nu:** Byg Option A — indlejrede billeder i narrativer via den token-grammatik der allerede
   findes. Et billigt, konkret vundet slag.
2. **Design-disciplin nu, kode senere:** Fordi begge platforme allerede deler samme
   `parseNarrativ`/token-grammatik, vil en fremtidig `article`-entitet (hvis den nogensinde
   bygges) kunne genbruge nøjagtig samme rendering-pipeline. Der males ikke ind i et hjørne ved
   at vente.
3. **Ikke nu:** En egentlig `article`-tabel er en **separat, større beslutning**. Antag ikke at
   den er besluttet. Den fortjener sin egen brainstorm om formål og publikationsforløb, ikke at
   blive smuglet ind her.

**Det korte svar:** "artikler" i den forstand der er brug for i første omgang = "et billede
indsat i en tekst", og det fås fra Option A uden en ny entitet.

**AFKLARET MED BRUGER (2026-07-05):** "Fritstående" indhold viste sig at betyde "en artikel om
slægten generelt, ikke én bestemt person" — ikke en helt løsrevet CMS-side. Det passer allerede
ind i den eksisterende model: `narrative.subjekt_type` understøtter allerede `'family'`/
`'lineage'`/`'slaegt'`, ikke kun `'person'`, og der findes allerede en offentlig læsevisning der
bruger det (`web/src/data/public.ts:187-191`, "Om slægten"). Det eneste der reelt mangler er en
**redaktør-skærm til at SKRIVE slægts-niveau-narrativer** — i dag findes kun en editor til
person-narrativer (`redaktion/person/[id].tsx`); slægts-narrativet er tilsyneladende kun sat ind
manuelt via SQL. Dette er en lille, veldefineret tilføjelse til Slice C's scope, IKKE et argument
for en separat `article`-entitet. Beslutning: **ingen `article`-tabel bygges.**

---

## 4. Lightbox (klik-for-at-forstørre)

Der findes intet lightbox-bibliotek i repoet i dag, og der findes ingen visning større end 180px
nogen steder i appen. En lightbox er derfor både ny og den mest synlige forbedring.

### Anbefaling: én delt visuel/interaktions-spec, implementeret to gange
Følg det etablerede mønster (som `buildBidirectionalColumns`): samme adfærd beskrevet ét sted,
men to selvstændige implementeringer holdt manuelt i sync — ikke et delt bibliotek. Web og mobil
har for forskellige primitiver til at dele koden meningsfuldt.

- **Web:** et fuldskærms-overlay (mørk baggrund, billede centreret, luk med Esc/klik-udenfor/kryds).
  Piletaster til at bladre hvis flere billeder. Statisk billede (browserens egen scroll/zoom er nok).
- **Mobil:** en fuldskærms-modal. Luk med swipe-ned eller kryds.

### Zoom: statisk (AFKLARET MED BRUGER 2026-07-05)
**Beslutning: kun statisk større visning, intet pinch-zoom.** "Bare større" er nok — ingen
knibe-zoom til at se detaljer tættere på. Forenkler Slice A: ingen gestus-håndtering, bare et
overlay/modal der viser billedet i fuld (skærm-begrænset) størrelse. Kan tilføjes senere uden nye
afhængigheder hvis behovet opstår (`react-native-reanimated`/`react-native-gesture-handler` er
allerede installeret), men er ikke en del af Slice A.

### Samspil med det der allerede er bygget
- `MediaGallery`/thumbnails: gør hver thumbnail klikbar → åbner lightbox på `large`-niveauet
  (eller på originalen indtil varianter findes).
- Lightbox henter en signed URL til `large`-varianten (samme `signPaths`-mekanik som i `media.ts`).
  Indtil §1/§2 er bygget peger den bare på den eneste eksisterende fil.

### Vigtig pointe for rækkefølge
**Lightboxen afhænger ikke af størrelses-laddet.** De nuværende uploads er fuld opløsning
(`quality:1`), så en lightbox kan vises mod den eksisterende enkelt-fil med det samme. Lås den
ikke bag variant-arbejdet.

---

## 5. Faset byggeplan

Følger "Slice N"-konventionen. Den eksisterende `2026-07-04-mediehaandtering.md` har allerede en
"Slice 1 — Rig rettigheds-dokumentation" på køreplanen; dette placeres som nye søskende-slices, da
det er en anden akse (visning/størrelse) end rettigheder. Rækkefølgen er valgt så hver slice giver
værdi alene.

### Slice A — Lightbox (start HER)
**Det mindste konkrete første skridt med størst synlig værdi.** Gør thumbnails klikbare; vis
statisk fuld visning i overlay (web) / modal (mobil); luk med Esc/swipe/kryds. Bruger eksisterende
signed-URL-mekanik og eksisterende (enkelt) billedfil. **Afhænger af: intet.** Leverer: for første
gang kan man faktisk se et billede i fuld størrelse.

### Slice B — Klient-side genkodning + `media_variant`-skema + 3 niveauer ved upload
Tilføj `media_variant`-tabellen (§2); udvid `media_id_for_object` til også at slå op i den;
generér thumb/medium/large klient-side før upload (Canvas/expo-image-manipulator) og upload alle
tre; genkod altid til JPEG (retter HEIC-fejlen). Opdater `useMediaUris`/`signPaths` så en
visningskontekst kan bede om det rette niveau. **Afhænger af: intet teknisk, men giver mest mening
efter A** (så lightboxen kan pege på `large`). Ingen backfill af eksisterende prod-billeder —
bruger genuploader dem selv (afklaret, §6).

### Slice C — Indlejrede billeder i narrativer (Option A) + slægts-narrativ-editor
Omskriv `NarrativRenderer` til blok-niveau på begge platforme, så `[[media:123|tekst]]` bliver et
`medium`-billede med billedtekst, klikbart til lightboxen; tilføj "indsæt billede"-knap i
narrativ-editoren analogt med `MentionPicker`. Billedtekst-logik (AFKLARET 2026-07-05): brug
token-labelen hvis den er udfyldt, ellers fald tilbage på `media.titel` (Option C — ingen
tvunget dobbeltarbejde, men mulighed for at tilpasse pr. indsættelse).
**Nyt scope-element (afklaret med bruger):** tilføj en redaktør-skærm til at skrive/redigere
slægts-niveau-narrativer (`subjekt_type='family'|'lineage'`) — findes i dag kun for personer.
Bruger denne slice til også at dække "en artikel om slægten generelt", som allerede har en
offentlig læsevisning (`public.ts`s "Om slægten") men ingen skrive-vej. Lille tilføjelse, ikke en
ny entitet.
**Afhænger af: B** (for at have et `medium`-niveau at vise — ellers ville hvert indlejret billede
være en tung `large`-fil). Kan teknisk bygges mod originalen først og pege på `medium` senere,
men anbefales efter B.

### Rækkefølge og afhængigheder
```
A (lightbox)        — uafhængig, byg først
   └─ B (varianter) — uafhængig af A, men A drager fordel af Bs 'large'
         └─ C (indlejrede billeder) — kræver Bs 'medium'
```
Pinch-zoom på mobil = valgfri hale på A, hvis/når det ønskes.

En egentlig `article`-entitet er **ikke** en slice her — det er en fremtidig separat brainstorm.

---

## 6. Beslutninger (AFKLARET MED BRUGER 2026-07-05 — alle punkter lukket)

1. **Artikler:** dækkes af det eksisterende narrativ-system, udvidet med `subjekt_type='family'`/
   `'lineage'` (se §3). Ingen separat `article`-entitet. Lille tilføjelse i Slice C: en redaktør-
   editor til slægts-niveau-narrativer.
2. **Pinch-zoom: nej.** Kun statisk, større visning i Slice A. Kan tilføjes senere uden nye
   afhængigheder, hvis behovet opstår — ikke en del af det planlagte arbejde nu.
3. **Backfill: nej.** Bruger genuploader selv de eksisterende testbilleder. Intet engangs-script
   nødvendigt.
4. **Behold ikke en separat original.** `large` (~2000px) er den øverste grænse. Bruger overvejede
   fremtidig brug af andre redaktører/uploadere, men konkluderede at den valgte størrelse er
   tilstrækkelig — kan genuploades fra kilden hvis et større behov opstår senere.
5. **Billedtekst: Option C.** Token-labelen bruges hvis udfyldt, ellers falder den tilbage på
   `media.titel`. Ingen tvunget dobbeltarbejde, men mulighed for at tilpasse teksten pr. indsættelse.

---

### Kritiske filer for implementering
- `db-rls.sql` (linje 97-218: `media_id_for_object`, `media_rettigheder_ok`, storage-politikker —
  skal udvides til `media_variant` i Slice B)
- `schema.sql` (linje 64-90: `media`-tabellen + hvor `media_variant` og evt. `red_*`-RPC'er
  tilføjes)
- `mobile/src/lib/media.ts` og `web/src/data/media.ts` (signed-URL/variant-valg — `signPaths`,
  `useMediaUris`)
- `mobile/src/components/NarrativRenderer.tsx` og `web/src/components/NarrativRenderer.tsx`
  (blok-niveau omskrivning i Slice C)
- `mobile/src/lib/mediaUpload.ts` og `web/src/data/mediaUpload.ts` (klient-side genkodning +
  multi-variant upload i Slice B)

---

## 7. Slice C — detaljeret implementeringsplan (2026-07-05, EFTER A+B er merget+prod-verificeret)

*Skrevet med Slice A+B allerede i hånden: `media_variant` findes, thumb/medium/large uploades og
kan læses (`MediaItem.thumbUrl`/`PersonMedia.thumbUrl`/mobiles `usePersonMedia`), Lightbox findes
på begge platforme. Denne sektion er forankret i de faktiske filer (læst 2026-07-05), ikke kun
det oprindelige oplæg — fem ting viste sig undervejs at være skarpere end §3/§5 antog (§7.1a-c
fundet ved egen kodelæsning; §7.1d-e tilføjet efter en uafhængig Codex-review af selve denne plan,
som fangede to reelle huller — se noter i hvert punkt).*

### 7.1 Fem ting der viste sig at kræve en beslutning (ikke kun implementering)

**(a) Bio-klamp vs. blok-billeder — en reel konflikt, ikke kun mere kode.**
Mobiles ENESTE kaldested (`app/person/[id].tsx:143`) bruger `NarrativRenderer` INDE i en
`<Body numberOfLines={7}>` (bio-klamp). React Native tillader ikke en `<View>`/`<Image>` som barn
af en `<Text>`-clamp-kæde — et billede kan ikke sidde i den samme trunkerings-mekanisme som teksten
omkring det. **Beslutning krævet:** når en narrativ indeholder mindst ét `media`-token, skal den
IKKE klampes (billedet ville enten crashe eller blive usynligt) — klampen bevares uændret for
narrativer UDEN billeder. Anbefaling: `NarrativRenderer` eksporterer/beregner selv om teksten
"harBillede" (findes mindst ét `media`-segment) og kalderen (`person/[id].tsx`) slår
`numberOfLines` fra i det tilfælde. Alternativ (afvist): altid disable klamp — ville uden grund
ændre visningen af de ~600 eksisterende bio-tekster uden billeder.

**(b) Web mangler HELE insert-mention-infrastrukturen — ikke kun "tilføj en knap til".**
Mobiles `MentionPicker.tsx` (kun personer, "D2"-scope) findes IKKE på web i nogen form. Web's
narrativ-editor (`Redaktion.tsx:614`) er en ren `<textarea>` uden nogen indsæt-link-funktion
overhovedet — `onPickPerson={() => {}}` i preview'en er allerede i dag en no-op. At give web
"indsæt billede" betyder derfor: (1) spore cursor-position i en almindelig `<textarea>`
(`selectionStart`/`selectionEnd`, ikke RN's `onSelectionChange`), (2) bygge en simpel
billed-vælger-modal (kan være meget mindre end mobiles `MentionPicker` — ingen søgning nødvendig,
kun den aktuelle persons/linjens egne uploadede billeder), (3) bruge `insertAt` (findes allerede,
`mentions.ts`, platform-uafhængig ren funktion) til at splejse token'et ind. Dette er reelt NY
UI på web, ikke en port af noget der findes.

**(c) Der findes 5 navngivne linjer + ét generelt niveau — "hvilket niveau skriver jeg til?" er et
åbent spørgsmål, ikke en implementeringsdetalje.**
`lineage`-tabellen har i dag 5 rækker (I "Den holstenske linje", II "Linjen Gallentin", III "Den
mecklenburgske linje", IV "Den lensgrevelige linje af 1767", V "Den grevelige linje af 1673").
`narrative.subjekt_id` er `NOT NULL` — der er INGEN eksisterende `subjekt_type IN ('slaegt',
'lineage')`-række i prod i dag (`fetchAbout()` i `public.ts:188` returnerer i dag en tom liste;
"Om slægten"-siden viser altså p.t. ingenting). Der er to lag at kunne skrive til:
  - **Linje-specifik beskrivelse** (`subjekt_type='lineage'`, `subjekt_id=<lineage.id>`) — én pr.
    linje, vælges fra de 5 eksisterende rækker (samme datakilde som `SlaegtPicker`/lineage-chips
    andre steder i appen). Overskriften ER linjens navn.
  - **Generel slægtsbeskrivelse** (`subjekt_type='slaegt'`) — ikke bundet til nogen specifik linje.
    **AFKLARET MED BRUGER (2026-07-05, efter en kort omvej):** dette er ÉT sammenhængende
    tekstfelt, ikke en liste af separat betitlede sektioner. Emner som "oprindelsen i Ditmarsken"
    og "det heraldiske forsatsstof" (mobiles nuværende hårdkodede placeholder-eksempler,
    `app/about.tsx`) er blot AFSNIT i den samme flydende prosa — nøjagtigt som bogen selv ville
    skrive det — ikke selvstændige databaserækker. Kræver et sentinel-`subjekt_id`, fordi kolonnen
    er NOT NULL og der ikke findes en 'slaegt'-tabel. **`subjekt_id=1` fast.** Dokumentér tydeligt
    i koden at dette IKKE er en fremmednøgle til noget (én delt navngiven konstant, ikke et magisk
    tal genindtastet flere steder).
`red_upsert_narrativ(subjekt_type, subjekt_id, ...)` er allerede fuldt generisk (upsert-nøgle er
`(subjekt_type, subjekt_id, source_id)`) — **ingen DB-ændring nødvendig for selve skrivningen**,
kun en ny UI-skærm der kalder den med disse to varianter af argumenter. (En tidligere version af
denne plan indførte en `titel`-kolonne + en ny opret-RPC for at understøtte flere separat
betitlede afsnit — det viste sig at være en fejllæsning af brugerens ønske og er droppet igen.)
Følgeeffekt: `fetchAbout()`'s nuværende "concatenér alle matchende rækker uden at vise hvilken
linje de handler om" bliver forvirrende når indholdet reelt er redigerbart og linje-specifikt.
**Anbefaling:** udvid den offentlige "Om slægten"-visning til at vise linje-navn som overskrift pr.
afsnit (kræver kun at selecte `subjekt_id` med og joine `lineage.navn` — lille, isoleret ændring,
ikke en ny visning; det generelle afsnit vises uden linje-label, da det jo ikke tilhører én).
**Rettelse efter Codex-review:** dette gælder KUN web. `mobile/src/app/about.tsx` er slet ikke
bundet til `narrative`-tabellen — det er en fast, hårdkodet pladsholder-skærm (to statiske
`SECTIONS` med "Indlæses fra stamtavlen"-badges). At vise nye slægts/linje-narrativer på mobile er
derfor ikke "udvid en eksisterende visning", men **byg læse-siden for første gang** — samme
datahentning som webs `fetchAbout()`, porteret, ikke kun en UI-touch-up.
**Source/udgave (Codex-fund):** `red_upsert_narrativ`s upsert-nøgle inkluderer `source_id` —
person-narrativer har derfor "udgave-faner" (én narrativ pr. DAA-udgave). Slægts/linje-niveauet
har intet sådant behov i dag (`fetchAbout()` filtrerer slet ikke på `source_id`). **AFKLARET MED
BRUGER: JA, flere udgaver ønskes** — se §7.6 for hvordan dette løses (generalisering af den
eksisterende person-udgave-fane-UI, ikke en ny parallel implementering).

**(d) Overskrifter og linjeskift i prosaen (AFKLARET MED BRUGER 2026-07-05) — hører hjemme i
samme blok-omskrivning som billed-visning, ikke et separat markdown-bibliotek.**
Bruger ønsker at kunne skrive `## Overskrift`-agtige mellemrubrikker OG pålidelige linjeskift
inde i en narrativ (mest relevant for det generelle slægts-afsnit, men gælder `NarrativRenderer`
generelt — samme renderer bruges alle steder). **Beslutning: minimal, håndrullet udvidelse, IKKE
et markdown-bibliotek.** Kodebasen har ingen markdown-afhængighed i forvejen og har sin egen
håndrullede tekst-grammatik (`mentions.ts`); et fuldt markdown-bibliotek ville være ny
afhængighed på begge platforme OG skulle komponeres med den eksisterende `[[type:id|label]]`-
syntaks (kollisionsrisiko, fx `[tekst](url)` vs. `[[type:id|label]]`). Omfang: KUN linjeskift
(afsnit) + `##`/`###`-heading-linjer som deres egen bloktype — ingen fed/kursiv/lister/tabeller.
**Konkret fejl fundet undervejs, som denne udvidelse retter som sidegevinst:** linjeskift-visning
er i dag INKONSISTENT på web — `Folgesvend.tsx:1010` (gods-narrativ) har `whiteSpace: 'pre-wrap'`
og viser linjeskift korrekt, men `Folgesvend.tsx:870` (person-bio) og `Redaktion.tsx:623`
(narrativ-editorens forhåndsvisning) har det IKKE — linjeskift forsvinder der i dag. **Løsning:**
flyt afsnits-opdeling IND i `NarrativRenderer` selv (split på tomme linjer til separate
blok-elementer med egen margin), så adfærden ikke længere afhænger af om den enkelte kalder huskede
`whiteSpace: 'pre-wrap'` — en hel fejlklasse elimineres som led i den alligevel planlagte
blok-omskrivning, ikke en ekstra opgave.

**(d) Der findes ingen eksisterende "slå et VILKÅRLIGT media-id op"-primitiv (Codex-fund).**
Alle eksisterende `useMediaUris`/`usePersonMedia`/`useMediaAndThumbUris`-varianter (Slice B3)
virker på et medie-array kalderen ALLEREDE har hentet (fx en persons egen portræt+galleri). Et
`[[media:123|...]]`-token i en narrativ kan derimod pege på ET HVILKET SOM HELST media-id —
inklusive et der IKKE er en del af den viste subjekts egen liste (fx et linje-våben nævnt inde i
en persons bio). `NarrativRenderer` skal derfor kunne slå et arbitrært media-id op, hente dets
`medium`-URL + `titel` (til Option C-fallback), og håndtere at opslaget kan fejle (RLS skjuler
mediet, mediet er slettet, mediet mangler en medium-variant). **Ny, lille primitiv nødvendig**:
en batchet "hent medium-URL+titel for et sæt media-id'er"-funktion pr. platform (samme
sign+fallback-mønster som `fetchThumbPathByMediaId`/`useMediaAndThumbUris`, men for `medium` og
uden at kræve en forælder-liste af medier). Fail-closed-adfærd ved et ikke-opløseligt id:
renderes som inaktiv gråtekst (samme gracefulle degradering `parseNarrativ` allerede har for
malformede/ukendte tokens) — IKKE en fejl der vælter resten af narrativen.

**(e) Lightbox-scope for indlejrede billeder er uafklaret (Codex-fund) — foreslået løsning:
selvstændig, narrativ-lokal lightbox.**
Den eksisterende lightbox-state (`person/[id].tsx:35`, `Folgesvend.tsx`) er lokal for den
kaldende skærm og bygget af DENS EGEN portræt+galleri-liste (`usePersonMedia`) — `NarrativRenderer`
har i dag ingen adgang til den og ingen callback-vej ind i den. At tråde en `onOpenMedia`-callback
igennem ville koble narrativ-rendering til hver enkelt kaldesides lightbox-implementering.
**Anbefaling:** `NarrativRenderer` ejer sin EGEN lille lightbox-state, som kun navigerer blandt de
billeder der reelt er indlejret i DENNE narrativ (ikke subjektets fulde galleri) — matcher
læserens forventning om at bladre videre til "næste billede i artiklen", ikke pludselig hoppe til
personens portrætgalleri. Dette er også den simpleste implementering (ingen prop-drilling,
ingen delt state mellem `NarrativRenderer` og dens kaldere).

### 7.2 Genbrug der allerede findes (ingen ny arkitektur nødvendig)
- `mentions.ts`/`parseNarrativ`/`makeToken`/`insertAt`: uændrede, allerede platform-delte, allerede
  testede. `media`-typen er allerede en del af vokabularet.
- `red_upsert_narrativ`: uændret, allerede generisk på `subjekt_type`.
- Mobiles generiske objekt-materiale-skærm (`app/redaktion/entitet/materiale.tsx` +
  `OBJEKT_TYPE`-map `{gods:'estate', vaaben:'coat_of_arms'}`): at lade en linje have EGNE
  uploadede billeder (ikke kun tekst) kræver blot én ny linje i det map (`slaegt:'lineage'`) —
  `red_upload_media`'s `p_objekt_type` er allerede fri-tekst server-side (ingen allow-liste), så
  dette er reelt allerede understøttet, blot ikke UI-eksponeret. **Ikke et krav for Slice C**, men
  en billig sidegevinst hvis der er tid — nævn den, byg den ikke uopfordret.
- `Lightbox`-KOMPONENTEN (ikke dens state) genbruges uændret — `NarrativRenderer` instantierer
  bare sin egen, med sin egen lokale `items`/`index`-state (§7.1e). `pickPreferredBio` uændret.
- `mentions.ts`'s eksisterende gracefulle degradering (malformet/ukendt token → rå tekst) er
  PRÆCEDENSET for den nye "media-id kan ikke opløses"-fallback (§7.1d) — ikke en ny idé, samme
  mønster udvidet til endnu en fejlklasse.

### 7.3 Konkret arbejdsplan
0. **Ny primitiv: batchet medium-URL+titel-opslag pr. media-id (§7.1d — FORUDSÆTNING for punkt 1).**
   Én funktion pr. platform (`fetchMediumByMediaId(ids)`-agtig, samme sign+fallback-mønster som
   `fetchThumbPathByMediaId`): tag et sæt media-id'er nævnt i EN narrativs tokens, returnér
   `{titel, mediumUrl, largeUrl}` pr. id (largeUrl til lightboxen, §7.1e). Id'er der ikke kan
   opløses (slettet/RLS-skjult/mangler medium-variant) udelades stille — renderes som inaktiv
   gråtekst i punkt 1, ikke en fejl.
1. **`NarrativRenderer` → blok-niveau (begge platforme).** Ny returtype internt: split teksten på
   tomme linjer til afsnit-blokke, genkend `##`/`###`-heading-linjer som deres egen bloktype
   (§7.1d), og render `media`-segmenter som selvstændige blokke (billede + billedtekst under,
   klikbar → åbner renderer'ens EGEN lokale lightbox, §7.1e) i stedet for at mappe alle segmenter
   fladt til `<Text>`/`<span>`. Billedtekst: token-label hvis udfyldt, ellers `media.titel` fra
   punkt 0's opslag (Option C, allerede besluttet). Et media-token der ikke kan opløses (punkt 0)
   falder tilbage til samme inaktive gråtekst-visning som en ukendt mention-type i dag.
   - **Mobile:** rod-elementet kan ikke længere altid være ÉT `<Body>` — skift til en `<>`-fragment
     der interfolierer `<Body>`-tekstblokke (nu én pr. afsnit i stedet for én stor klump),
     heading-blokke og `<Pressable><Image/></Pressable>`-blokke. Løs 7.1(a) som del af denne
     ændring.
   - **Web:** rod-elementet bliver en `<div>` i stedet for `<span>` (uproblematisk — ingen kalder
     afhænger af inline-visning), med samme afsnit/heading/billede-gruppering. Fjern den nu
     overflødige `whiteSpace: 'pre-wrap'` fra kaldesteder der havde den (linjeskift håndteres
     internt af renderen nu) og tilføj INGEN ekstra CSS på kaldesteder der manglede den (§7.1d).
2. **Insert-billede-UI.**
   - **Mobile:** ny `MediaMentionPicker` (søster til `MentionPicker`, samme sheet-stil) der viser
     DENNE subjekts (person ELLER lineage) egne uploadede billeder (samme datakilde som
     `usePersonMedia`/`MediaGallery` allerede bruger) og indsætter `makeToken('media', id, titel)`
     ved cursor-position (allerede sporet i person-editorens narrativ-`TextInput` til den
     eksisterende `MentionPicker`).
   - **Web:** spor `selectionStart` på narrativ-`<textarea>`'en (ny state, `onSelect`-handler);
     byg en minimal billed-vælger-modal over subjektets egne billeder; brug `insertAt`.
3. **Slægts/linje-narrativ-editor (ny skærm, begge platforme). INGEN DB-ændring nødvendig
   (§7.1c) — kun ny UI, `red_upsert_narrativ` bruges uændret.**
   - Vælger: "Generelt" (fast `subjekt_type='slaegt'`, `subjekt_id=1` — låst teknisk konstant,
     ikke et brugervalg) ELLER én af de 5 linjer (liste fra `lineage`-tabellen, samme kilde som
     eksisterende linje-chips/`SlaegtPicker`).
   - **Udgave-faner (§7.1c/§7.6 — bruger ønskede flere udgaver, IKKE fast source_id):**
     generalisér `fetchPersonNarrativer`/dens fane-UI i `Redaktion.tsx` til at tage
     `subjektType`/`subjektId` som parametre i stedet for at antage 'person' — genbrug frem for
     parallel ny fane-implementering. Byg samme fane-parity på mobile (som i dag slet ingen
     udgave-fane-UI har for narrativer) for at undgå en ny, dag-1-inkonsistent skærm mellem
     platforme.
   - Genbruger `red_upsert_narrativ`s eksisterende tekst-UI-mønster (textarea/TextInput +
     privat-toggle + gem-knap) i øvrigt uændret.
   - Adgang: ny "Slægten"-sektion i entitet-nav (§7.6, bekræftet af bruger).
4. **Læse-side (BEGGE platforme — Codex-fund, ikke kun web).**
   - **Web:** udvid `fetchAbout()` (§7.1c) til at bære linje-navn med (kun for
     `subjekt_type='lineage'`-rækker — det generelle afsnit vises uden label), så "Om slægten"
     viser en rigtig overskrift pr. linje-afsnit i stedet for en sammenkædning uden labels.
   - **Mobile:** `app/about.tsx` henter i dag INGEN data overhovedet (hårdkodet pladsholder med
     netop de eksempel-overskrifter brugeren nævnte, "Slægtens oprindelse"/"Heraldisk indledning"
     — som nu bliver EN del af den frie prosa i det generelle afsnit, §7.1c) — byg den faktiske
     datahentning her for første gang (port af webs `fetchAbout`-mønster), og lad det RIGTIGE
     indhold erstatte placeholder-`SECTIONS`-arrayet.
5. **Linje-billeder (§7.6, bruger ønskede dem med nu):** tilføj `slaegt: 'lineage'` til mobiles
   `OBJEKT_TYPE`-map (`app/redaktion/entitet/materiale.tsx`), og en tilsvarende mapping på web hvis
   web har en analog generisk objekt-materiale-flade (undersøges ved implementering — ikke
   bekræftet i denne research-pas).

### 7.4 Test/verifikationsplan
- Enheds-tests: `NarrativRenderer`'s nye afsnit/blok-gruppering OG dens nye "uopløseligt media-id"-
  fallback (begge platforme — web har allerede en testfil, mobile har ingen i dag og bør få én);
  `mentions.ts` er uændret (ingen nye tests nødvendige der).
- Empirisk: mindst ét billede indsat i en RIGTIG persons bio mod prod (web, samme mønster som B's
  verificerede test-upload), + mindst ét linje-narrativ oprettet/redigeret mod prod, + visuel
  bekræftelse af klik-til-lightbox fra et indlejret billede (inkl. at lightboxen kun viser DENNE
  narrativs billeder, §7.1e) + mindst ét bevidst "død"/uopløseligt media-token for at se
  fallback-visningen i praksis. Mobile forbliver statisk-verificeret (tsc+jest) medmindre en
  simulator/fysisk enhed er tilgængelig i sessionen — sig det eksplicit hvis ikke.

### 7.5 Åbne spørgsmål til bruger (stillet og afklaret 2026-07-05 — se §7.6 for svar)
1. Skal "Om slægten"-siden vise en overskrift pr. afsnit, eller er den nuværende sammenkædede
   visning uden labels fin at bevare?
2. Navigationsindgang til den nye slægts/linje-narrativ-editor — under en "Slægten"-sektion i
   entitet-navigationen, eller et andet sted i redaktør-UI'et?
3. Fast `source_id=1` (ingen udgave-faner) for slægts/linje-narrativer — er det rigtigt, eller er
   der et konkret ønske om at kunne have flere udgavers slægtsbeskrivelser side om side?
4. Skal linjer kunne have EGNE uploadede billeder, eller er det uden for scope for nu?

### 7.6 Svar fra bruger (AFKLARET 2026-07-05 — alle 4 punkter lukket, punkt 1 gik gennem to omgange)
1. **Overskrifter: linje-navne JA (§7.1c) — men det "generelle" niveau forbliver ÉT tekstfelt,
   ikke separat betitlede sektioner.** Første bruger-opfølgning ("der kan godt være brug for
   flere andre overskrifter... fx Ditmarsken") fik mig først til at foreslå en ny
   `narrative.titel`-kolonne + opret-RPC for at understøtte flere selvstændigt betitlede afsnit.
   **Bruger afviste dette efter direkte spørgsmål:** emner som Ditmarsken-oprindelsen og det
   heraldiske forsatsstof er blot AFSNIT i én sammenhængende prosa, ikke separate poster — samme
   måde bogen selv ville skrive det. Nettoresultat: `subjekt_id=1` fast sentinel (som oprindeligt
   foreslået, §7.1c) + intern overskrift/linjeskift-håndtering i selve teksten via den nye
   `##`-heading-syntaks (§7.1d, bruger ønskede eksplicit "overskrifter og linjeskift" som minimum,
   afviste et fuldt markdown-bibliotek til fordel for en minimal håndrullet udvidelse). INGEN
   skema-ændring for dette punkt — kun `NarrativRenderer`s blok-omskrivning (§7.3.1).
2. **Navigation: ny "Slægten"-sektion i entitet-nav**, sammen med de øvrige entitetstyper.
3. **Udgave-faner: JA, flere udgaver ønskes** — IKKE fast `source_id`. **Scope-udvidelse ift.
   §7.1c/7.3.3's oprindelige anbefaling.** Person-narrativ-editorens udgave-fane-mønster
   (`fetchPersonNarrativer` + fane-UI i `Redaktion.tsx` omkring "Narrativ · biografi") skal
   GENERALISERES til at virke for `subjekt_type ∈ {'person','lineage','slaegt'}` i stedet for at
   bygge en ny, parallel udgave-fane-implementering. Konkret: `fetchPersonNarrativer(id)` →
   `fetchNarrativer(subjektType, subjektId)` (tilføj parameter, samme query-form uden
   `.eq('subjekt_type','person')` hardkodet); fane-UI'en i `Redaktion.tsx` parametriseres på
   `subjektType`/`subjektId` i stedet for at antage en person-record. Mobile har i dag INGEN
   udgave-fane-UI overhovedet for narrativer (kun web) — vurdér om dette skal bygges for lineage/
   slaegt-editoren på mobile fra bunden, eller om ét udgave (uden faner) er acceptabelt på mobile
   i første omgang, mens web får fuld fane-parity. **Forslag (skal bekræftes i implementering,
   ikke antaget):** byg fuld fane-parity på begge platforme, da inkonsistens mellem platforme på
   en NY skærm er nemmere at undgå end at rette senere.
4. **Linje-billeder: JA, tages med nu.** Tilføj `slaegt: 'lineage'` til mobiles
   `OBJEKT_TYPE`-map (`app/redaktion/entitet/materiale.tsx`) — genbruger den eksisterende
   generiske objekt-materiale-skærm 1:1 (ingen ny kode ud over map-linjen + evt. web-parallel hvis
   web har en tilsvarende generisk objekt-materiale-flade).
