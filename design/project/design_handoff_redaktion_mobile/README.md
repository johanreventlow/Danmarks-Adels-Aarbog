# Handoff: Redaktion — mobil app (Danmarks Adels Aarbog)

## Overview
En **mobil redaktør-app** til at vedligeholde evidens-basen bag Danmarks Adels Aarbog direkte fra telefonen: gennemse uenige kilder, redigere kerne-fakta efter konklusion ← oplysninger-modellen, styre relationer/hverv/godser, og skrive til Supabase (direkte for rollen `redaktion`, ellers som forslag i staging). Den er søsterapp til den eksisterende publikums-app (`folgesvend`) og deler designsystem, fonte og telefon-ramme.

Designet skal **udbygge den eksisterende Expo-app** i `mobile/` — ikke være en separat app. Tilføj den som et nyt route-segment ved siden af `(tabs)`.

## About the Design Files
Filerne i denne bundle er **design-referencer skrevet i HTML** (en Design Component, `.dc.html`) — en interaktiv prototype der viser udseende og adfærd. **Det er ikke produktionskode der skal kopieres.** Opgaven er at **genskabe designet i den eksisterende React Native / Expo-kodebase** (`mobile/`) med dens etablerede mønstre: `expo-router`, `theme/tokens.ts`, komponenter som `TopBar`, `InitialBadge`, `Typography`, og Supabase-klienten i `lib/supabase.ts`.

HTML-prototypen bruger inline-styles, `div`/`span` og web-fonte via Google Fonts. I appen oversættes det til `View`/`Text`/`Pressable`/`TextInput`/`ScrollView`/`Modal` med tokens fra `theme/tokens.ts` og de allerede bundlede `@expo-google-fonts`-familier.

## Fidelity
**High-fidelity (hifi).** Endelige farver, typografi, spacing, radier og interaktioner. Genskab UI'et pixel-tro med kodebasens eksisterende komponenter og tokens. Alle værdier nedenfor er de faktiske værdier fra prototypen og matcher `theme/tokens.ts`.

---

## Arkitektur i den eksisterende app

Tilføj et nyt segment under `mobile/src/app/`. Forslag — en stack med egne tabs, holdt adskilt fra publikums-`(tabs)`:

```
src/app/
  (tabs)/                 ← eksisterende publikums-app (uændret)
  redaktion/
    _layout.tsx           ← Stack (headerShown:false)
    index.tsx             ← Oversigt (dashboard)
    [entity]/index.tsx    ← Entitetsliste (person, estate, source …)
    person/[id].tsx       ← Person-editor (evidens-lag)
    record/[entity]/[id].tsx  ← Generisk editor (estate/majorat/source/…)
    konto.tsx             ← Konto/login/indstillinger
```

Den nederste **redaktions-tabbar** (Oversigt · Entiteter · Tilføj · Konto) er IKKE de samme 4 faner som publikums-appen — byg den enten som en egen `Tabs`-gruppe `(red-tabs)` eller som en persistent bund-komponent i `redaktion/_layout.tsx`. "Tilføj" åbner en bottom sheet (ikke en rute).

State der lever på tværs af skærme (auth-session, `dryRun`, `showAnnotations`) hører hjemme i en **Zustand-store** (appen har allerede `store/useStore.ts`) eller React Context — ikke i route-params.

---

## Skærme / Views

### 1. Oversigt (dashboard) — `redaktion/index.tsx`
**Formål:** Redaktørens startpunkt: status, arbejdskø, indgang til alle entiteter.
**Layout:** Vertikal `ScrollView`, paper-baggrund (`#f4efe6`), 18px vandret padding. Ingen top-bar (egen hero-header). Bund-tabbar nederst.
- **Hero:** mono-kicker "DANMARKS ADELS AARBOG" (`#b9a06a`, 9.5px, letterSpacing ~0.2em, uppercase) + serif-titel "Redaktion" (Cormorant SemiBold, 34px, `#221f1a`).
- **Rolle/skrivemode-kort:** mørkt kort (`#2a211c`, radius 16, padding 15×16, tekst `#f4efe6`).
  - Logget ind: rund avatar 40px (`#881A33`-fyld, initialer i Cormorant) + e-mail (Hanken 600 13.5px) + rolle-label (mono 9px `#cabfa9`).
  - Ikke logget ind: gylden ring-avatar (border `#e7c98f`) + "Log ind for at redigere" → åbner login-sheet.
  - Divider (`rgba(244,239,230,.14)`), derunder **dry-run-kontakt**: pille-toggle (track 42×24 radius 13; knap 19px hvid) + titel/undertekst. Til = `Dry-run · skriver ikke` (track svag lys); fra = `LIVE · skriver til basen` (track `#c0392b`).
- **Til gennemsyn:** sektionslabel (mono 9.5px `#9a8f78` uppercase) + tæller "N uenige kilder" (`#881A33`). Liste af kort (`#f8ecef`, border `rgba(136,26,51,.2)`, radius 13): rund initial-badge, navn (Cormorant 16), detalje "uenige kilder: A / B" (`#8a2b2b` 11.5px), felt-tag højre (mono 8px på `#fbf8f1`). Tap → åbner personen med det relevante faktum foldet ud.
- **Entiteter i basen:** 2-kolonne grid (gap 9), kort `#fbf8f1` border `rgba(34,31,26,.1)` radius 13. Hvert: ikon-firkant 30px (`#f4e2e6`-fyld, glyph `#881A33`) + tal (Cormorant 21 `#881A33`) øverst, label (Hanken 600 13) nederst. Tap → entitetsliste.

### 2. Entitetsliste — `redaktion/[entity]/index.tsx`
**Formål:** Find og åbn en post i en entitetstype.
**Layout:** Top-bar (back + entitetsnavn + dry-run-chip). Sticky søgefelt (`#fbf8f1`, border, radius 10, glyph ⌕ + `TextInput`). Liste af kort (gap 7).
- **Rad:** kort `#fbf8f1` radius 13 padding 12×14. Avatar 40px (rund for personer = `borderRadius` 50%, ellers 8px), `#ece4d6`-fyld, initialer/glyph i Cormorant `#881A33`. Titel (Cormorant 18) + undertitel (Hanken 11.5 `#6f675b`). "privat"-tag hvis privat. Chevron ›.
- Tom tilstand: centreret "Ingen træffere" / "Ingen poster endnu".

### 3. Person-editor — `redaktion/person/[id].tsx`  ★ kerneskærmen
**Formål:** Redigere en person efter evidens-modellen.
**Layout:** Top-bar (personnavn). ScrollView 16px padding.
- **Header:** rund avatar 56px (`#f8ecef`-fyld, border 1.5px `#881A33`, initialer Cormorant 21 `#881A33`). Navn (Cormorant 25). Meta-chips: år (mono 10 `#9a8f78`), køn + `id …` (mono 9 på `#ece4d6`).
- **Handlinger:** række med **Privat**-toggle (fyld-flade skifter `#fbf8f1`↔`#f8ecef`, border/track skifter til `#881A33` når privat) og **Slet**-knap (border `rgba(138,43,43,.3)`, tekst `#8a2b2b`, 🗑).
- **Evidens-note** (kun hvis `showAnnotations`): stiplet boks `#f8ecef` border `rgba(136,26,51,.4)`, forklarer konklusion/oplysning/kilde.
- **Kerne-fakta** (label-rytme: mono 9px `#b9a06a` "Kerne-fakta · konklusion ← oplysninger"). Liste af **fakta-kort** (`#fbf8f1` radius 12), ét pr. felt: `navn, foedt, doed, koen, titel`.
  - **Sammenklappet rad** (tappbar): feltlabel (mono 9 `#9a8f78` uppercase) over konklusionsværdien (Cormorant 19) + kilde "⮡ …" (mono 9 `#9a8f78`). Højre: "uenige"-tag (hvis konflikt), tæller "N oplysn." (mono 9 på `#ece4d6`), chevron ▸/▾.
  - **Udfoldet:** for hver oplysning en rad (konklusion = `#eaf3ec` grøn-tonet border `rgba(31,91,58,.32)`; ellers `#f4efe6`): farveprik (grøn `#1f5b3a` valgt / rød `#8a2b2b` konflikt / grå `#bcae93`), værdi (Cormorant 17) + status-label (mono 8 "konklusion"/"oplysning"), "§ kilde", meta "forfatter · dato". Handlingsrække: **Gør til konklusion** (grøn outline, kun hvis ikke valgt), ✎ redigér, 🗑 slet. Redigér åbner inline to felter (værdi + kilde) med **Gem** (grøn `#1f5b3a`) / Annullér. Nederst **+ Tilføj oplysning** → inline formular (værdi + kilde) → **Registrér** (grøn) skriver via write-laget.
- **Familie & relationer:** kort med grupper Forældre / Ægtefæller / Børn. Hver rad: rund 28px initial-badge, navn (Cormorant 15), "§ kilde". Børn har et segmenteret rolle-vælg (barn / adopt. / pleje / sted) — aktiv = `#881A33`-fyld hvid tekst.
- **Sektioner** (Embeder & hverv, Godser & besiddelser, Kilder & bogreference, Våben): label + "+ Tilføj"; rader med ikon-firkant 30px, titel (Cormorant 16), undertekst, "§ kilde", evt. periode højre.
- **Narrativ · biografi:** kort med `TextInput` (multiline, højde ~104, `#fff` border radius 9) + enkelt kilde-felt.

### 4. Generisk editor — `redaktion/record/[entity]/[id].tsx`
**Formål:** Redigere ikke-person-entiteter (estate, majorat, source, narrative, office, family, org, arms, media).
**Layout:** Top-bar. Header: ikon-firkant 48px radius 11 (`#f8ecef`, glyph `#881A33`) + kicker (mono 9) + titel (Cormorant 24). Slet-knap. Evidens-note (hvis on).
- **Felter** drives data: hvert felt er enten **text** (`TextInput`, `#fbf8f1` radius 9), **area** (multiline) eller **chips** (segment af piller; valgt = `#881A33`-fyld hvid). Se "Felt-skemaer pr. entitet" nedenfor.
- Valgfrie blokke: **timeline** (prikkede rader med titel/periode/kilde), **gallery** (2-kol grid med stribede placeholders + "+ Tilføj"), **usage** (stort tal + label, fx "1247 henvisninger"), **empty** (medier: stiplet tom-tilstand med CTA).

### 5. Konto — `redaktion/konto.tsx`
**Formål:** Login/logout, dry-run og forklaringer.
- Logget ind: profil-kort (avatar 52px + e-mail + rolle), indstillingskort med to toggles (dry-run, "Vis forklaringer"), Log ud-knap (`#8a2b2b` outline).
- Ikke logget ind: mørkt promo-kort (`#2a211c`) med gylden "Log ind"-knap + forklarings-toggle.
- Link "Åbn publikums-app ↗" (`#881A33`).

### Bottom sheets (Modal/overlay, slide op .34s)
- **Login:** drag-handle, titel, e-mail + adgangskode-felter, fejltekst, bordeaux "Log ind"-knap. Supabase Auth.
- **Skrive-preview (dry-run/live):** prik+titel + rute-note (afhænger af rolle), liste af mørke kode-blokke (`#2a211c`, mono, `METHOD path` + JSON-body) eller fejltekst, "✓ Udført (N kald)". Luk-knap.
- **Slet-bekræftelse:** ⚠-badge, "Slet \<type\>?", relations-advarsel-boks (`#f8ecef`) med chips over hvad der brydes, **acknowledge-checkbox** der låser den røde "Slet endeligt"-knap op.
- **Opret ny post:** 2-kol grid af entitetstyper → vælg → går til den listes opret-flow.

---

## Interaktioner & adfærd
- **Navigation:** tabbar skifter rod-skærm; lister pusher detalje; back i top-bar. "Tilføj"-fanen åbner opret-sheet (lukker ikke en rute).
- **Dry-run/LIVE** er global. I dry-run kalder skrivninger write-lagets `submit(plan,{dryRun:true})` og viser planen; LIVE udfører REST-kald. Togglen sidder både i top-bar-chip, dashboard-kort og Konto — alle styrer samme state.
- **Evidens-redigering er ikke-destruktiv:** "Gør til konklusion" sætter `chosen` på én oplysning (og afsætter de andre); sletning af den valgte vælger automatisk den første tilbageværende. Tilføj/redigér af oplysning stempler `by:'Redaktør (dig)'` + dagens dato.
- **Konflikt-detektion:** et felt er "uenigt" når det har >1 oplysning med forskellige værdier. Dette fylder også dashboardets "Til gennemsyn"-kø.
- **Sletning** kræver eksplicit acknowledge før knappen aktiveres; viser de relationer der brydes.
- **Animationer:** skærm-skift `translateY(9px)→0` opacity, 0.4s `cubic-bezier(.2,.7,.2,1)`; sheets `translateY(100%)→0` 0.34s; dashboard-elementer "rise" `translateY(11px)→0` 0.55s. I RN: `Animated`/`react-native-reanimated` eller `LayoutAnimation`.
- **Validering:** "Registrér oplysning" kræver en værdi; tom kilde gemmes som "(kilde mangler)".

## State management
Globalt (store/context): `auth {token,email,role}`, `dryRun:boolean`, `showAnnotations:boolean`.
Pr. skærm/lokalt: `entity`, `recordId`, `query`, `expanded{factKey:bool}`, `addingTo`, `editingAssert`, `scratch{}` (ucommittede felt-værdier), `confirmDelete`, `confirmAck`, `writePlan`, `createOpen`, login-felter.
Data: prototypen kører på in-memory seed (3 personer + reference-lister). I appen hentes via Supabase (RLS gater læseadgang) med fallback til offline-seed, præcis som `lib/load.ts` allerede gør for publikums-appen. Genbrug `person_display`-viewet / selectors hvor muligt.

## Skrivelaget (vigtigt)
`redaktion-write.js` (vedlagt) er den faktiske oversættelse fra en redigering til REST-kald og bruges allerede af web-prototypen. Den er framework-agnostisk (rå `fetch`) og kan bruges som den er i RN, ELLER porteres til Supabase-klienten i `lib/supabase.ts`.
- `signIn / getRole / signOut` — Auth + rolle-opslag i `profiles.rolle`. I appen: foretræk `supabase.auth.signInWithPassword(...)` og et `profiles`-select, så session persisteres via AsyncStorage (allerede konfigureret).
- `buildPlan(change, role)` — rolle `redaktion` → direkte til `assertion`+`citation`+`conclusion` (for `art:'fakta'`), `narrative`, `relation`, `person`; alle andre roller → ét `suggestion`-row i staging.
- `submit(plan, {url,anonKey,token,dryRun})` — dry-run returnerer `preview[]` (menneskelæselige kald); live udfører sekventielt og opløser `__ref`-id'er mellem kald.
En "change" normaliseres af editoren til `{ art, subjektType, subjektId, felt, vaerdi, kildeFritekst, payload, note }`. Se `art`-værdierne i filens kommentarer.

---

## Design tokens (matcher `theme/tokens.ts`)
**Farver:** bordeaux `#881A33`; bordeaux-fyld lys `#f8ecef` / `#f4e2e6`; blæk `#221f1a`; tekst `#3d382f` / `#6f675b`; dæmpet `#9a8f78` / `#a99f8c` / `#b0a691`; guld `#b9a06a` / lys `#e7c98f`; paper `#f4efe6`; kort `#fbf8f1`; beige `#efe7d7` / `#ece4d6`; mørkt kort `#2a211c`; sandkasse `#e7e3da`.
**Status-farver (redaktion-specifikke):** valgt/konklusion grøn `#1f5b3a`, grøn-tonet flade `#eaf3ec`; fejl/slet `#8a2b2b`; LIVE-rød `#c0392b`; konflikt-flade `#f2dede`.
**Borders:** `rgba(34,31,26,.08/.10/.14)`.
**Fonte:** serif = Cormorant Garamond 500/600 (overskrifter/navne/værdier); sans = Hanken Grotesk 400/500/600/700 (UI/brødtekst); mono = JetBrains Mono 400/500 (kickers, labels, kode-preview, årstal). Mono-labels er uppercase med letterSpacing ~0.1–0.2em.
**Radier:** felt/knap 9–11; kort 12–16; badge 5–8; chip/pille 9–18; sheet-top 24; runde avatarer 50%.
**Skygger:** kort `#221f1a` y1 blur2 opacity .03–.04; valgt `#881A33` y4 blur14 opacity .14.
**Spacing:** skærm-padding 16–18px; kort-padding 12–16; gaps 6–9.

## Felt-skemaer pr. entitet (generisk editor)
- **estate (gods):** Navn (text) · Slags (chips: hovedgård/herregård/ladegård/len) · Del af majorat (chips) · Beskrivelse (area) · timeline "Ejere gennem tiden" · usage "7 ejer-relationer".
- **majorat:** Navn · Form (grevskab/baroni/stamhus/fideikommis) · Tilknyttet titel (lensgreve/lensbaron/ingen) · Oprettet · Arvefølge · Status (bestående/afløst 1919/opløst) · timeline "Successorrække" · usage "3 omfattede godser".
- **source (kilde):** Titel · Slags (trykt værk/arkivalie/kirkebog/folketælling) · Udgave/årgang · usage "1247 henvisninger".
- **narrative:** Subjekt-type (chips) · Subjekt · Tekst (area) · Synlighed (offentlig/privat) · Kilde.
- **office (hverv):** Person · Rolle · Organisation · Periode · Kilde.
- **family:** Familie-type · Partner 1 · Partner 2 · timeline "Børn · rolle pr. kant".
- **org:** Navn · Slags (myndighed/hær/kirke/hof) · usage "14 hverv".
- **arms (våben):** Blasonering (area) · gallery "Gengivelser & segl".
- **media:** tom-tilstand med "Upload medie"-CTA.

## Assets
Ingen billed-assets i selve redaktions-flowet (placeholders er stribede CSS-gradienter — i RN: en `View` med `StripedPlaceholder`-komponenten der allerede findes). Glyph-ikoner er Unicode-tegn (☗ ⚭ ¶ ❦ ⌂ ⚜ ◈ § ⛨ ▦ ✎ 🗑 ⚠) — overvej at mappe til `@expo/vector-icons` (Ionicons) for konsistens med resten af appen, eller behold som tekst-glyffer. Logo `assets/daf-logo.png` bruges kun i publikums-appen.

## Files
- `Reventlow-redaktion-app.dc.html` — den interaktive mobil-prototype (denne handoff). Åbn i browser for at klikke flowet igennem.
- `redaktion-write.js` — det faktiske Supabase skrive-/login-lag (genbruges/portes).
- Referencer i repo'et: `Reventlow-redaktion.dc.html` (desktop-versionen af samme redaktør-værktøj), `Reventlow-folgesvend-v2.dc.html` (publikums-app, samme designsprog).
- Eksisterende app-mønstre at genbruge: `mobile/src/theme/tokens.ts`, `mobile/src/components/{TopBar,InitialBadge,Typography,StripedPlaceholder}.tsx`, `mobile/src/lib/supabase.ts`, `mobile/src/data/*`, `mobile/src/store/useStore.ts`, `mobile/src/app/(tabs)/_layout.tsx`.
