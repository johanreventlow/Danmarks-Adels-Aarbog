# Spec — Opret-ny-entitet i redaktør-appen (person + gods + kilde + organisation)

**Dato:** 2026-06-29
**Status:** Design (afventer bruger-review → writing-plans)
**Forudsætning:** Redaktør-person-editoren (plan 2A→2C-2b) er bygget og deployet til prod
(auth, rediger/slet fakta, køn, narrativ, hverv/godser, familie+konfidens, slet person —
alt via SkrivePreviewSheet dry-run→live). 121/121 jest. Denne skive lukker det synlige hul:
**"Tilføj"-fanen er en stub** (`(red-tabs)/_layout.tsx`: `setOpretOpen(true)` uden sheet) →
ingen vej til at oprette en NY entitet.

---

## 1. Mål og afgrænsning

**Mål:** Redaktøren kan oprette en ny **person, gods (estate), kilde (source)** eller
**organisation** fra "Tilføj"-fanen, gennem det eksisterende dry-run→live-gate, og fortsætte
direkte i editoren (person) hhv. se den nye række i listen (de øvrige).

**I scope:** de fire "simple" entiteter — person + tre rene navn/tekst-entiteter uden egen
evidens-redigering ved opret.

**Bevidst UDE (begrundet):**
- **Medie, våben, majorat** — medie kræver Storage-upload (ikke bygget), majorat kræver
  timeline/successor-UI. Senere skiver.
- **Inline-opret fra PersonPicker** (opret partner/barn der ikke findes endnu) — fast-follow
  skive ovenpå. Standalone-opret via Tilføj-fanen først.
- **Dedup / UNIQUE på navn/titel** — flages, bygges ikke. Ingen af tabellerne har UNIQUE på
  navn → tavse dubletter er mulige. Konsistent med `red_opret_union` (ingen auto-dedup).
  Kilde-dubletter ("DAA 2018-20") er værd at advare om i en *senere* skive.

---

## 2. Arkitektur — genbrug af den eksisterende write-sti

Ingen ny transport-mekanik. Hele opret-flowet kører på det etablerede mønster:

```
UI-form → Change-objekt → buildRpcCall(c) → RpcCall{fn,args}
        → submitChange (dry-run: vis fn+args via describeCall · live: supabase.rpc)
        → SkrivePreviewSheet-gate (dry-run → bekræft → live)
```

Tilføjelser er **additive**: nye Change-arter, nye buildRpcCall-cases, nye RPC'er, én ny
sheet-komponent. Eksisterende editor og RPC'er røres ikke.

---

## 3. Lag 1 — DB: fire nye SECURITY DEFINER RPC'er

Deployes additivt til prod som de øvrige (schema-backup → deploy → grant-loop → rollback-test).
Alle: `current_rolle() <> 'redaktion'` → RAISE. id allokeres med `coalesce(max(id),0)+1`
(husstil, jf. `red_upsert_fakta`; race accepteret i single-editor PoC). Komposit + atomisk
(én funktion = én transaktion), jf. `red_opret_union`.

### 3.1 `red_opret_person(p_navn text, p_koen text DEFAULT NULL, p_levende boolean DEFAULT false, p_privat boolean DEFAULT false, p_foedt_raw text DEFAULT NULL, p_doed_raw text DEFAULT NULL, p_titel_raw text DEFAULT NULL) RETURNS bigint`

1. rolle-gate. Tom/whitespace `p_navn` → RAISE (`'Navn er påkrævet'`).
2. `v_id := coalesce(max(id),0)+1 FROM person`.
3. `INSERT person(id, levende, privat, koen) VALUES (v_id, p_levende, p_privat, p_koen)`.
   Køn er en **kolonne** på person (ikke et fact) → sættes direkte. `levende` **default false**
   (undgår at lægge nulevende-data i det stadig-åbne dev-RLS-læselag utilsigtet).
4. `PERFORM red_upsert_fakta('person', v_id, 'navn', p_navn)` → opretter fact→assertion→
   conclusion → trigger `regen_person_visning` regenererer `visning_navn`.
5. Valgfrit: `PERFORM red_upsert_fakta('person', v_id, 'fødsel', p_foedt_raw, p_date_raw => p_foedt_raw)`
   og tilsvarende for 'død' og 'titel' (titel uden dato) — kun når argumentet er non-null/non-blank.
   (Named-notation `=>` for at ramme `p_date_raw` som er 8. positionelle arg.)
6. `RETURN v_id`.

> Den interne `PERFORM red_upsert_fakta` re-tjekker `current_rolle()`; det overlever inde i
> SECURITY DEFINER-sessionen. Faktatyper matcher `FELT_FAKTATYPE` i appen (navn/fødsel/død/titel).

### 3.2 `red_opret_estate(p_navn text, p_slags text DEFAULT NULL, p_sted_id bigint DEFAULT NULL) RETURNS bigint`
rolle-gate; tom navn → RAISE; id=max+1; `INSERT estate(id, navn, slags, sted_id)`; RETURN id.

### 3.3 `red_opret_kilde(p_titel text, p_slags text DEFAULT NULL, p_udgave text DEFAULT NULL, p_ekstern boolean DEFAULT false) RETURNS bigint`
rolle-gate; tom titel → RAISE; id=max+1; `INSERT source(id, slags, titel, udgave, ekstern)`; RETURN id.

### 3.4 `red_opret_organisation(p_navn text, p_slags text DEFAULT NULL) RETURNS bigint`
rolle-gate; tom navn → RAISE; id=max+1; `INSERT organisation(id, navn, slags)`; RETURN id.

Tilføjes i `schema.sql` + `db-migrations.sql` (idempotent `CREATE OR REPLACE`) + grant-loop.

---

## 4. Lag 2 — App write-lag (`redaktionWrite.ts`)

Nye Change-arter: `opretPerson | opretEstate | opretKilde | opretOrganisation`.
Nye `buildRpcCall`-cases mapper `c.payload` → RPC-args:

```ts
opretPerson  → red_opret_person       { p_navn, p_koen, p_levende, p_privat, p_foedt_raw, p_doed_raw, p_titel_raw }
opretEstate  → red_opret_estate       { p_navn, p_slags, p_sted_id }
opretKilde   → red_opret_kilde        { p_titel, p_slags, p_udgave, p_ekstern }
opretOrganisation → red_opret_organisation { p_navn, p_slags }
```

`describeCall` er allerede generisk (viser fn + JSON-args) → dry-run-preview virker uden ændring.
`submitChange` returnerer RPC-resultatet (ny id, `RETURNS bigint`) som UI bruger til navigation.

---

## 5. Lag 3 — UI

### 5.1 Wire "Tilføj"-fanen
`(red-tabs)/_layout.tsx`: intercept'en sætter i dag en dead `setOpretOpen`. Wires til at åbne
`OpretSheet`.

### 5.2 Ny `components/redaktion/OpretSheet.tsx`
- **Trin 1 — entitetstype-grid:** 2-kol grid (Person · Gods · Kilde · Organisation), matcher
  design-handoff ("Opret ny post: grid → vælg → den listes opret-flow").
- **Trin 2 — type-form** (kontrollerede felter, hardcodede vokab-arrays = husstil, jf.
  `KONFIDENS_VAERDIER`/`UNION_TYPER`):
  - **Person:** navn\* · køn (`mand/kvinde/ukendt`) · levende-toggle · født · død · titel.
  - **Gods:** navn\* · slags (`gods/len/stamhus/lensgrevskab/baroni`) · sted (EntitetPicker, valgfri).
  - **Kilde:** titel\* · slags (`kirkebog/DAA-udgave/bog/artikel/diplomsamling`) · udgave · ekstern-toggle.
  - **Organisation:** navn\* · slags (`amt/regiment/hof/institution/ridderorden`).
- Bygger et `Change` → routes gennem **samme** SkrivePreviewSheet-gate (dry-run → live).
  Påkrævet-felt tomt → submit disabled.

### 5.3 ⭐ Post-create cache-reload FØR navigation (kritisk — ikke hale)
Editoren læser `redaktionModel.byId[id]`; listerne læser `redaktionAux`. En netop-oprettet entitet
findes i **ingen** af dem før reload → uden dette lander create→edit på en **blank editor**, og en
ny gods/kilde/org er **usynlig** i listen.

`loadRedaktionModel()` (store) genindlæser **både** model og aux i ét kald (sætter
`redaktionModel` + `redaktionAux` sammen). Post-create-sekvens ved live-success:

```
await RPC (returnerer ny id) → await loadRedaktionModel() → DEREFTER navigér/luk
```

- **Person:** efter reload → `router.push('/redaktion/person/[nyId]')` (`byId[nyId]` findes nu →
  fortsæt redigering). Forced reload vælges frem for optimistisk byId-patch, fordi `visning_navn`
  er trigger-afledt af navn-konklusionen — en patch skulle replikere visnings-logikken.
- **Gods/kilde/org:** efter reload → luk sheet; ny række synlig i `entitet/[type]` + opdateret tæller
  i `entiteter`-fanen (begge læser `redaktionAux`, som nu er frisk).

> Bemærk: `entitet/[type].tsx` har i dag *ingen* focus-refetch (kun `RedPersonListe` har) → den
> eksplicitte reload er den eneste mekanisme der gør nye rækker synlige.

---

## 6. Lag 4 — Test

- **jest (rene, netværksfri, matcher `redaktionWrite.test.ts`):** `buildRpcCall` for de 4 nye arter
  → korrekt fn + args; valgfrie felter udeladt når null; påkrævet-felt-mangel → `null`.
- **DB rollback-test (live, som de øvrige RPC'er):**
  - opret person → person-række + navn-fact + `visning_navn` regenereret; valgfri født/død/titel-facts.
  - opret estate/kilde/org → korrekt række.
  - tom navn/titel → RAISE.
  - rolle-gate: anon-kald → P0001 "Kun redaktion".
  - alt rulles tilbage (nul blivende mutation).
- **Manuel web-e2e:** opret person → land i editor med navnet sat; opret gods → vises i listen.

---

## 7. Filer (forventet berørt)

| Fil | Ændring |
|---|---|
| `schema.sql`, `db-migrations.sql` | 4 nye RPC'er + grant-loop |
| `mobile/src/data/redaktionWrite.ts` | 4 Change-arter + buildRpcCall-cases |
| `mobile/src/data/__tests__/redaktionWrite.test.ts` | tests for de 4 arter |
| `mobile/src/components/redaktion/OpretSheet.tsx` | ny: grid + type-forms |
| `mobile/src/app/redaktion/(red-tabs)/_layout.tsx` | wire Tilføj-intercept → OpretSheet |
| (post-create) | reload-før-navigér i OpretSheet success-path |

---

## 8. Risici og afvejninger

- **MAX+1 id-race:** kun et problem ved samtidige skrivninger; PoC er single-editor. Accepteret,
  matcher `red_upsert_fakta`.
- **Tavse dubletter:** ingen UNIQUE-constraint → to entiteter med samme navn er muligt. Flaget, ikke
  løst (konsistent med `red_opret_union`).
- **Nulevende-data:** `levende=true` ved opret lægger persondata i det stadig-åbne dev-RLS-læselag.
  Bruger valgte opret frem for RLS-hærdning → ikke en blocker her; `levende` defaulter til `false`.
- **Cache-invaliderings-gæld (§9):** den bredere "reload redaktionModel efter ALLE writes"-gæld fra
  cycle 05 er stadig udestående; denne skive løser den kun for opret-stien (eksplicit reload).
