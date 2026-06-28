# Plan 2B — Editor-dybde: selv-forsynende editor + køn + familie/sektion-visning (design/spec)

**Dato:** 2026-06-28
**Status:** Godkendt design — klar til implementeringsplan
**Branch:** arbejd på `main` (feature-branch ved implementering)
**Kontekst:** Plan 2A gjorde levende personer søgbare i redaktions-listen. Men person-editoren
henter navn/familie/sektioner fra den DELTE anon-model (893, uden levende) → `model.byId[id]`
er undefined for de 70 levende → editoren viser "Personen blev ikke fundet". 2B gør editoren
**selv-forsynende** (egen per-person redaktion-fetch, virker for alle inkl. levende), tilføjer
**køn-editor** (redigerbar), og viser **familie + sektioner read-only**.

Forudgående: plan 1 (kerne-editor), plan 2A (`docs/superpowers/specs/2026-06-28-plan2a-...`).

---

## 1. Besluttede valg

| Beslutning | Valg | Note |
|---|---|---|
| Editor-datakilde | **Selv-forsynende `fetchRedaktionPerson(id)`** | Stopper afhængighed af delt anon-model → virker for levende. |
| Redigerbart i 2B | **Kun køn** | Familie/relationer + sektioner = read-only. Relations-redigering hører til 2C (generisk editor + rolle-vælgere). |
| Familie/sektion-derivation | **Per-person via redaktion-fetch** | Replikerer model/aux-familie+relations-logik for én person; RLS-gated (inkl. levende). |

---

## 2. Data: `fetchRedaktionPerson(id)`

Nyt i `mobile/src/data/redaktionRead.ts`. Henter alt editoren behøver om ÉN person via
redaktion-sessionen (RLS returnerer levende for redaktion). **Kaster ved error** (ingen
tom-som-clean). Flere queries + klient-klassifikation (den polymorfe/relationelle model
har ikke en færdig per-person-view).

```ts
type PersonRef = { id: string; navn: string };
type PersonDetalje = {
  header: { navn: string; aar: string; koen: string | null; bio: string };
  foraeldre: PersonRef[];
  aegtefaeller: PersonRef[];
  boern: { aegtefaelle: string | null; born: PersonRef[] }[]; // pr. ægteskab
  hverv: { label: string; periode: string }[];
  godser: { navn: string; periode: string }[];
  kilder: { ref: string; vaerk: string }[];
};
export async function fetchRedaktionPerson(id: string): Promise<PersonDetalje | null>;
```

**Datakilder + klassifikation:**

- **Header:** `person` (visning_navn, visning_foedt, visning_doed, koen). `aar = fmtYears(...)`.
  `bio` = første ikke-private `narrative` for personen (`narrative.select tekst where subjekt_type='person'
  and subjekt_id=id order by id`). Navn-fallback `'(uden navn)'`.

- **Familie** (model: et `family` har `partner`-medlemmer (parret) + `barn`-medlemmer):
  1. `family_member` WHERE person_id=id → personens familier + personens rolle pr. familie.
  2. `family_member` WHERE family_id IN (de familier) → alle med-medlemmer (family_id, person_id, rolle, ordinal).
  3. `person` for alle med-medlem-ids → navne (visning_navn).
  4. Klassificér (ren funktion `klassificerFamilie(rows, selfId)`):
     - **forældre** = partner-medlemmer i familier hvor self er `barn` (ekskl. self).
     - **ægtefæller** = partner-medlemmer i familier hvor self er `partner` (ekskl. self).
     - **børn** = grupperet pr. familie hvor self er `partner`; `aegtefaelle` = anden partners navn,
       `born` = `barn`-medlemmer (sorteret på ordinal).

- **Sektioner:**
  - **hverv:** `relation` WHERE subjekt_type='person' AND subjekt_id=id AND objekt_type='organisation'
    → `{ label: rolle + ' · ' + org.navn, periode: periode_raw ?? '' }` (org-navn via `organisation`-opslag).
  - **godser:** `relation` WHERE subjekt_type='person' AND subjekt_id=id AND objekt_type='estate'
    → `{ navn: estate.navn, periode: periode_raw ?? '' }` (estate-navn via `estate`-opslag).
  - **kilder:** `person_external_id` WHERE person_id=id JOIN `source` → `{ ref: linje+nr, vaerk: source.titel }`.

`null` returneres hvis personen ikke findes (RLS-skjult / slettet) → editor viser "ikke fundet".

**Rene klassifikations-funktioner** (`klassificerFamilie`, `mapHverv`/`mapGods`/`mapKilde`) adskilles
fra netværks-`fetchRedaktionPerson` → unit-testes uden net.

## 3. Editor-ændringer (`mobile/src/app/redaktion/person/[id].tsx`)

- **Header + bio fra `fetchRedaktionPerson`**, ikke `model.byId`. Editoren henter `PersonDetalje`
  i `useEffect([id])` (ved siden af det eksisterende `fetchPersonEvidence`). Virker for levende.
  Fjern afhængigheden af `model.byId[id]` for header/navn/bio. (Konflikt-kø-navne i dashboard
  bruger stadig model — uændret; kun editoren skifter kilde.)
- **Køn-editor (NYT, redigerbart):** under kerne-fakta — et "KØN"-afsnit med segment-vælger
  **mand / kvinde / ukendt** (vocab fra DB-constraint `person_koen_chk`). Valg → `setPending({
  art: 'fakta', felt: 'koen', vaerdi })` (eksisterende buildRpcCall-case → `red_set_koen`) →
  SkrivePreviewSheet → efter LIVE re-fetch `fetchRedaktionPerson` (opdaterer header-køn).
- **Familie & relationer (read-only):** grupper Forældre / Ægtefæller / Børn (pr. ægteskab).
  Rad: `InitialBadge` + navn; tap → `router.push('/redaktion/person/' + ref.id)` (naviger til den
  person i editoren). Tom gruppe skjules.
- **Sektioner (read-only):** Hverv · Godser · Kilder — rader med titel + periode/værk. Tom sektion skjules.
- Visuelt mønster spejler publikums-`app/person/[id].tsx` (familie-grupper, sektion-rader).

## 4. Fejlhåndtering
- `fetchRedaktionPerson` kaster ved Supabase-error. Editoren fanger → eksplicit fejl-tilstand
  ("Kunne ikke hente person"). `null`-retur (findes ikke) → "Personen blev ikke fundet".
  ALDRIG tom-som-clean (cycle 03 NEW1).

## 5. Test
- **jest:** `klassificerFamilie` (forældre/ægtefælle/børn-klassifikation fra family_member-rows;
  pr.-ægteskab-gruppering; self-eksklusion; ordinal-sort) — ren, central logik. `mapHverv`/
  `mapGods`/`mapKilde` (felt-mapping). Køn-write-case er allerede dækket (buildRpcCall `fakta`+`koen`
  → `red_set_koen`).
- **Manuel:** reload → redaktion → åbn en LEVENDE person (via Entiteter-listen) → editoren ÅBNER
  (header korrekt) → familie/sektioner vist → skift køn (LIVE) → header-køn opdateres. Fejl-sti noteret.

## 6. Berørte artefakter
**Ændrede:**
- `mobile/src/data/redaktionRead.ts` (+ `PersonDetalje`, `PersonRef`, `fetchRedaktionPerson`,
  `klassificerFamilie`, `mapHverv`/`mapGods`/`mapKilde`).
- `mobile/src/app/redaktion/person/[id].tsx` (header/bio fra fetch; køn-editor; familie/sektion-blokke).
- Tests: `redaktionRead.test.ts` (familie-klassifikation + sektion-mapping).

## 7. Scope / non-goals
**I scope:** selv-forsynende editor (per-person redaktion-fetch, virker for levende); køn-editor
(redigerbar); familie + sektioner read-only-visning; fejl-tilstand.

**Non-goals (→ 2C / senere):**
- Redigér familie/relationer/sektioner (rolle-vælgere, relation-RPC'er, gods/hverv-entiteter).
- Medier-visning/upload.
- Generisk record-editor + andre entiteter + opret-flow.
- At fjerne model-afhængigheden andre steder end editoren (dashboard-konflikt-navne uændret).
