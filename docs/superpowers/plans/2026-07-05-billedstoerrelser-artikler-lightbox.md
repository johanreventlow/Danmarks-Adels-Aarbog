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
