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

Tilføjelser er **mest additive**: nye Change-arter, nye buildRpcCall-cases, nye RPC'er, én ny
sheet-komponent. **To eksisterende stykker SKAL dog ændres** (afdækket i Codex-review, se §5.3):
`SkrivePreviewSheet.onApplied` skal bære live-resultatet (ny id), og `loadRedaktionModel` skal kunne
tvinge en reload. Begge er bagudkompatible for eksisterende kaldere. Eksisterende RPC'er og
person-editorens write-logik røres ikke.

---

## 3. Lag 1 — DB: fire nye SECURITY DEFINER RPC'er

Deployes additivt til prod som de øvrige (schema-backup → deploy → grant-loop → rollback-test).
Alle: `current_rolle() <> 'redaktion'` → RAISE. id allokeres med `coalesce(max(id),0)+1`
(husstil, jf. `red_upsert_fakta`; race accepteret i single-editor PoC). Komposit + atomisk
(én funktion = én transaktion), jf. `red_opret_union`.

### 3.1 `red_opret_person(p_navn text, p_koen text DEFAULT NULL, p_levende boolean DEFAULT false, p_privat boolean DEFAULT true, p_foedt_raw text DEFAULT NULL, p_doed_raw text DEFAULT NULL, p_titel_raw text DEFAULT NULL) RETURNS bigint`

1. rolle-gate. **Påkrævet navn afviser BÅDE NULL og whitespace:**
   `IF nullif(btrim(p_navn),'') IS NULL THEN RAISE 'Navn er påkrævet'` (Codex: `btrim()=''` alene
   afviser ikke NULL).
2. `v_id := coalesce(max(id),0)+1 FROM person`.
3. `INSERT person(id, levende, privat, koen) VALUES (v_id, p_levende, p_privat, p_koen)`.
   Køn = **kolonne** på person → sættes direkte.
   **`privat` defaulter til `true` (privatlivs-fix, Codex major + advisor-reconcile):** RLS-reglen er
   `levende=false AND privat=false → anon-læsbar` (afdød-semantik). Med `levende DEFAULT false` ville
   en glemt levende-toggle på en faktisk-nulevende person publicere den til `anon`. At læne sig på
   levende-retning er forkert; i stedet skjuler `privat=true` enhver ny person uanset levende-status,
   indtil redaktøren bevidst klassificerer og afpublicerer. Reversibelt via eksisterende
   `red_set_privat`. `levende` forbliver et eksplicit toggle i formularen (driver ikke synlighed alene).
4. `PERFORM red_upsert_fakta('person', v_id, 'navn', p_navn)` → fact→assertion→conclusion → trigger
   `regen_person_visning` regenererer `visning_navn` i samme transaktion.
5. Valgfrit: `PERFORM red_upsert_fakta('person', v_id, 'fødsel', p_foedt_raw, p_date_raw => p_foedt_raw)`
   og tilsvarende 'død' samt 'titel' (uden dato) — kun når argumentet er non-null/non-blank.
   (Named-notation `=>` for at ramme `p_date_raw`, 8. positionelle arg.)
6. `RETURN v_id`.

> **Titel-invariant (Codex major):** `red_upsert_fakta` er find-or-create med `LIMIT 1`; det er kun
> sikkert her, fordi en reelt ny person endnu ikke har et titel-fact. **Senere** titel-tilføjelser
> SKAL bruge multi-fact-operationen `red_opret_fakta` (som editoren allerede gør) — ellers overskrives
> den første titel. Opret rører kun ÉN titel.
>
> Den interne `PERFORM red_upsert_fakta` re-tjekker `current_rolle()`; overlever inde i SECURITY
> DEFINER-sessionen. Faktatyper matcher `FELT_FAKTATYPE` (navn/fødsel/død/titel).

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
  - **Gods:** navn\* · slags (`gods/len/stamhus/lensgrevskab/baroni`). *(Sted udskudt: `EntitetPicker`
    understøtter kun organisation/estate, og Aux har ingen `placeListe` → ingen sted-picker findes.
    RPC beholder `p_sted_id` forward-kompat; UI sender null. Sted tilføjes i senere skive.)*
  - **Kilde:** titel\* · slags (`kirkebog/DAA-udgave/bog/artikel/diplomsamling`) · udgave · ekstern-toggle.
  - **Organisation:** navn\* · slags (`amt/regiment/hof/institution/ridderorden`).
- Bygger et `Change` → routes gennem **samme** SkrivePreviewSheet-gate (dry-run → live).
  Påkrævet-felt tomt → submit disabled.

### 5.3 ⭐ Post-create: forced cache-reload + ID-transport (kritisk — Codex-blockers B1/B2)
Editoren læser `redaktionModel.byId[id]`; listerne læser `redaktionAux`. En netop-oprettet entitet
findes i **ingen** af dem før reload → uden dette lander create→edit på en **blank editor**
("Personen blev ikke fundet", `person/[id].tsx:286`), og en ny gods/kilde/org er **usynlig** i listen.

**To eksisterende stykker mekanik holder IKKE — derfor i implementerings-scope (modsiger §2's
"røres ikke"):**

**B1 — `loadRedaktionModel()` er ikke en reload.** `useStore.ts:258` early-returner når
`redaktionStatus === 'ready'` (= netop post-create-tilstanden) → kaldet er et no-op, model/aux
forbliver stale. **Fix:** parametrisér `loadRedaktionModel(force?: boolean)` — `force` springer
`ready`-early-return over. Fejl-håndtering (Codex major: "navigation oven på fejlet refresh"): den
eksisterende catch beholdes (sætter `redaktionStatus='error'`, resolver — **ikke** re-throw, da
eksisterende mount-kaldere afventer uden try/catch og ville give unhandled rejection). I stedet
**tjekker OpretSheet `redaktionStatus` efter await** og navigerer KUN ved `'ready'`.

**B2 — `SkrivePreviewSheet` smider den nye id væk.** `run()` (linje ~30) gør
`await submitChange(...)` uden at bruge returværdien, og `onApplied(): void` bærer intet resultat.
**Fix:** udvid til `onApplied: (result?: unknown) => void` og videregiv live-RPC-resultatet
(`RETURNS bigint`). Bagudkompatibelt — eksisterende kaldere (person-editoren) ignorerer den
valgfrie param.

**Post-create-sekvens ved live-success (i OpretSheet, efter gate'ens `onApplied(result)`):**

```
result = ny id (fra red_opret_*)  →  await loadRedaktionModel(true)
  →  hvis redaktionStatus !== 'ready': vis fejl, navigér IKKE
  →  ellers: navigér/luk
```

- **Person:** `router.push('/redaktion/person/[result]')` (`byId[result]` findes nu efter forced reload).
  Forced reload frem for optimistisk byId-patch, fordi `visning_navn` er trigger-afledt af
  navn-konklusionen — en patch skulle replikere visnings-logikken.
- **Gods/kilde/org:** luk sheet; ny række synlig i `entitet/[type]` + opdateret tæller i
  `entiteter`-fanen (begge læser `redaktionAux`, nu frisk).

> Bemærk: `entitet/[type].tsx` har *ingen* focus-refetch (kun `RedPersonListe` har) → den eksplicitte
> forced reload er den eneste mekanisme der gør nye rækker synlige.

---

## 6. Lag 4 — Test

- **jest (rene, netværksfri, matcher `redaktionWrite.test.ts`):** `buildRpcCall` for de 4 nye arter
  → korrekt fn + args; valgfrie felter udeladt når null; påkrævet-felt-mangel → `null`.
- **DB rollback-test (live, som de øvrige RPC'er):**
  - opret person → person-række + navn-fact + `visning_navn` regenereret; valgfri født/død/titel-facts;
    **`privat=true` som default** (verificér ny person IKKE anon-læsbar).
  - opret estate/kilde/org → korrekt række.
  - **NULL navn OG whitespace-navn → RAISE** (begge, jf. `nullif(btrim())`).
  - rolle-gate: anon-kald → P0001 "Kun redaktion".
  - alt rulles tilbage (nul blivende mutation).
- **B1-test:** `loadRedaktionModel(true)` på `ready`-state henter faktisk frisk data (ny entitet i
  model/aux); fejl re-throwes (resolver ikke stille).
- **B2-test:** `SkrivePreviewSheet` live-success kalder `onApplied(result)` med ny id.
- **Manuel web-e2e:** opret person → forced reload → land i editor med navnet sat; opret gods → vises
  i listen + tæller opdateret.

---

## 7. Filer (forventet berørt)

| Fil | Ændring |
|---|---|
| `schema.sql`, `db-migrations.sql` | 4 nye RPC'er + grant-loop |
| `mobile/src/data/redaktionWrite.ts` | 4 Change-arter + buildRpcCall-cases |
| `mobile/src/data/__tests__/redaktionWrite.test.ts` | tests for de 4 arter |
| `mobile/src/components/redaktion/OpretSheet.tsx` | ny: grid + type-forms + post-create reload/nav |
| `mobile/src/app/redaktion/(red-tabs)/_layout.tsx` | wire Tilføj-intercept → OpretSheet |
| `mobile/src/components/redaktion/SkrivePreviewSheet.tsx` | **B2:** `onApplied(result?)` bærer ny id |
| `mobile/src/store/useStore.ts` | **B1:** `loadRedaktionModel(force?)` + re-throw ved fejl |

---

## 8. Risici og afvejninger

- **MAX+1 id-race (Codex major → accepteret-med-forbehold):** intet håndhæver single-editor, og flere
  profiler *kan* have `rolle='redaktion'` → samtidige opret kan kollidere på PK efter brugerbekræftelse.
  Men ALLE eksisterende write-RPC'er (`red_upsert_fakta`, `red_opret_union` …) deler præcis samme
  mønster — at fikse det kun her ville være inkonsistent. PoC kører single-editor (Johan). **Beslutning:**
  behold MAX+1 nu; post-PoC migrering til sequence/identity (ELLER advisory-lock i alle opret-RPC'er)
  som separat hærdnings-opgave. Dokumenteret, ikke løst i denne skive.
- **Slags ikke valideret i RPC (Codex minor):** `slags`/`koen` har ingen DB-constraint, og RPC'erne
  validerer ikke de annoncerede vokabularer — UI-arrays beskytter ikke direkte RPC-kald (som dog kræver
  `rolle=redaktion`). Accepteret for PoC (UI-gated). Evt. senere: `p_slags`-validering mod `vocab` i hver
  opret-RPC, eller CHECK-constraint.
- **Tavse dubletter:** ingen UNIQUE på navn/titel → dubletter mulige. Flaget, ikke løst (konsistent med
  `red_opret_union`). Kilde-dubletter værd at advare om i senere skive.
- **Leksikalsk display-titel (Codex minor, præ-eksisterende):** `regen_person_visning` kollapser flere
  titel-facts via `max(vaerdi_tekst)` (leksikalsk, ikke kronologi/redaktionelt valg). Påvirker IKKE denne
  skive (opret sætter kun én titel), men en deterministisk display-titel-regel er en separat forbedring.
- **Cache-invaliderings-gæld (§9):** den bredere "reload redaktionModel efter ALLE writes"-gæld fra
  cycle 05 er stadig udestående; denne skive løser den kun for opret-stien (forced reload).
