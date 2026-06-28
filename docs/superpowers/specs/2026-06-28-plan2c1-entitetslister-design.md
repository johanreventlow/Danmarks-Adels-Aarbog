# Plan 2C-1 — Entitetslister (read-only) (design/spec)

**Dato:** 2026-06-28
**Status:** Godkendt design — klar til implementeringsplan
**Branch:** arbejd på `main` (feature-branch ved implementering)
**Kontekst:** Første slice af plan 2C. Redaktions-appens Entiteter-tab viser pt. KUN personer
(2A). 2C-1 gør den til en entitets-type-menu (handoff §2) med read-only-lister over de øvrige
entiteter (godser, kilder, organisationer, medier). Read-only fordi der endnu ikke findes
detail-editor eller write-RPC'er for ikke-person-entiteter (= 2C-2/2C-3).

Forudgående: 2A (person-liste + searchPool), 2B (separat redaktion-model/aux).

---

## 0. Kontekst-fund (verificeret mod kode/skema)

- **RPC-fladen er person-centrisk.** Ingen write-RPC for `source`/`organisation`/`estate`/`media`;
  `majorat`/`arms` har ingen tabeller. → 2C-1 er nødvendigvis READ-ONLY.
- **Data er allerede loadet.** `buildAux` modtager allerede de rå arrays (`sources`/`orgs`/
  `estates`/`media`), men eksponerer kun `estateList`. 2C-1 udvider med flade lister — ingen ekstra
  fetch (redaktion-modellen fra 2B bærer dataene).
- **`media` har ingen `person_id`-kolonne** (kun id/slags/titel/kunstner/datering) → `mediaBy` er
  reelt tom; medie-listen kommer fra de rå medie-rækker.

---

## 1. Besluttede valg

| Beslutning | Valg | Note |
|---|---|---|
| Datakilde | **Udvidet `buildAux` (flade lister), læst fra `redaktionAux`** | Data allerede loadet i 2B-modellen; ingen ekstra fetch. |
| Entiteter-tab | **Entitets-type-menu** | Personer + Godser + Kilder + Organisationer + Medier. |
| Tap på ikke-person | **D1: ikke-tappbar (ren browse)** | Ingen detail-editor endnu (2C-3). Personer forbliver tappbar → editor (2B). |
| Entitetstyper | **gods/kilde/organisation/medie** | majorat/arms eksisterer ikke i skemaet → udeladt. |

---

## 2. Data: flade entitets-lister i `buildAux`

Udvid `buildAux` (`mobile/src/data/buildAux.ts`) til at returnere flade lister fra de rå arrays
den allerede modtager. Additivt på `Aux`-typen (`types.ts`); publikums-faner bruger dem ikke:

```ts
// Aux-tilføjelser:
kildeListe: { id: string; titel: string; slags: string; udgave: string }[];   // fra sources
orgListe:   { id: string; navn: string; slags: string }[];                     // fra orgs
medieListe: { id: string; titel: string; slags: string; kunstner: string; datering: string }[]; // fra media
godsListe:  { id: string; navn: string; slags: string; ownerCount: number }[]; // KOMPLET fra rå estates + ownerCount fra ownersByEstate
```

- **Rene mappings** (sorteret dansk på titel/navn): testbare uden net. `godsListe` er KOMPLET
  (alle estates, ikke kun ejede som `estateList`); `ownerCount` slås op i `ownersByEstate` (0 hvis ingen).
- Felt-fallback: tomme strenge for null (`titel ?? ''`, `navn ?? '(uden navn)'`).
- `estateList` (owner-only) bevares uændret (bruges andetsteds); `godsListe` er den nye komplette.
- Læses i UI fra **`redaktionAux`** (2B-modellen). Den delte publikums-`aux` får felterne også
  (harmløst — entiteter er ikke person-private).

## 3. Entiteter-tab → type-menu + lister (routes)

- **`(red-tabs)/entiteter.tsx`** (i dag = 2A person-liste): ændres til en **type-menu** —
  kort-grid (samme stil som dashboardets entitets-grid) med 5 kort: Personer · Godser · Kilder ·
  Organisationer · Medier, hver med tæller (fra `redaktionAux`/`counts`). Tap → den types liste.
- **Person-listen (2A)** udtrækkes til en genbrugelig komponent og nås via et "Personer"-kort →
  rute `redaktion/entitet/person.tsx` (uændret 2A-adfærd: søg/alfabet/tags → tap → editor).
- **Ikke-person-lister:** generisk rute `redaktion/entitet/[type].tsx` (`type` ∈
  gods/kilde/organisation/medie) → læser den matchende `redaktionAux`-liste. (Statisk `person.tsx`
  vinder over dynamisk `[type].tsx` i expo-router — de sameksisterer.)

## 4. Hver liste (read-only)

- Top-bar (back + type-navn). Søgefelt (simpelt navn/titel-filter; alfabet-bar kun for personer).
- Rad: `InitialBadge`/ikon-firkant + titel/navn + undertekst (slags · udgave / slags · "N ejere").
- **Ikke-tappbar** for ikke-person (D1) — evt. svag "read-only"-tone. Tom liste → "Ingen <type>".
- Fejl: type-menu/lister læser fra `redaktionAux` (in-memory); hvis `redaktionStatus!=='ready'`
  vises "Henter…"/fejl (genbrug 2B's status-mønster).

## 5. Test

- **jest:** de fire flade-liste-mappings i `buildAux` (felt-mapping, null-fallback, dansk sort,
  `godsListe.ownerCount` fra ownersByEstate, komplet vs owner-only). searchPool genbruges hvor relevant.
- **Manuel:** reload → redaktion → Entiteter → type-menu (5 kort m. tællere) → hver liste viser
  data (godser m. ejer-tæller, kilder m. udgave, org, medier) → ikke-person ikke-tappbar → Personer
  → 2A-listen uændret → tap person → editor.

## 6. Berørte artefakter

**Ændrede:**
- `mobile/src/data/types.ts` (Aux + 4 entry-typer).
- `mobile/src/data/buildAux.ts` (+ 4 flade lister).
- `mobile/src/app/redaktion/(red-tabs)/entiteter.tsx` (person-liste → type-menu).

**Nye:**
- `mobile/src/components/redaktion/RedPersonListe.tsx` (udtrukket 2A person-liste, genbrugt).
- `mobile/src/app/redaktion/entitet/person.tsx` (Personer-ruten → RedPersonListe).
- `mobile/src/app/redaktion/entitet/[type].tsx` (generisk read-only liste for gods/kilde/org/medie).
- Test: `buildAux`-test (ny eller udvid).

## 7. Scope / non-goals

**I scope:** flade entitets-lister i buildAux; Entiteter-tab type-menu; read-only lister for
gods/kilde/organisation/medie; Personer-ruten genbruger 2A-listen.

**Non-goals (→ 2C-2/2C-3):**
- Redigér/opret entiteter (ingen write-RPC'er endnu).
- Detail-skærm for ikke-person-entiteter (D1 = ikke-tappbar).
- Relations-redigering (2C-2).
- majorat/arms (eksisterer ikke i skemaet).
- Forene de fire flade lister med separate redaktion-fetches (bruger redaktion-modellens data).
