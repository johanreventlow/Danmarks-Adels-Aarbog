# Plan 2C-2b — Familie-redigering (partner + barn + konfidens) — Design

**Dato:** 2026-06-29
**Status:** Godkendt (brainstorm) — afventer spec-review
**Forgænger:** 2C-2a (sektion-relationer) — samme mønstre genbruges.

## Formål

Gør familie-relationer (FORÆLDRE/ÆGTEFÆLLER/BØRN) redigerbare i redaktør-person-editoren:
opret/fjern partner-union, tilføj/fjern barn, og ret konfidens på ethvert familie-link. Lukker den
sidste read-only-sektion fra 2B og giver redaktøren fuld kontrol over slægtsstrukturen — kernen i
"er vi i familie?"-funktionen.

## Kontekst (verificeret mod base 2026-06-29)

- `family (id, type)` = union/partnerskab; `family_member (family_id, person_id, rolle, ordinal, konfidens)`
  med PK `(family_id, person_id, rolle)`. Rolle ∈ `partner | barn | adopteret_barn | plejebarn | stedbarn`.
- **Familie-links bærer INGEN evidens:** `assertion`/`conclusion.target_type ∈ {fact, relation}` udelukkende
  (verificeret: 3777 fact + 971 relation, nul family/family_member). → slet er en ren `DELETE` af
  family_member-rækken, INGEN FK-ordnet evidens-cascade (modsat 2C-2a's relationer).
- **konfidens næsten altid NULL** (557 barn + 751 partner uden, 2 sat) → konfidens-redigering udfylder
  et stort tomrum. `family_member.konfidens` er §7-invarianten ("konfidens på links").
- family_member har **ingen surrogat-id**; edits targeter `(family_id, person_id, rolle)`.
- Read-only-visningen i dag: editor bruger `parentsOf`/`spousesOf`/`childrenByMarriage`
  (`mobile/src/data/selectors.ts`) over `redaktionModel` — disse giver navne/struktur, men IKKE
  `family_id`/`konfidens` pr. link, så de kan ikke targetere edits.
- Ingen familie-write-RPC findes; kun `red_slet_person` cascader family_member.
- Dokumenteret datakvalitet: 27 børn født før forældre (ægte historisk-kilde-tvetydighed) → era-validering
  skal advare, ikke blokere. Se [[data-fejl-foraelder-barn]].

## Beslutninger (fra brainstorm)

1. **Omfang:** Fuld familie-redigering i ét 2C-2b — partner + barn + konfidens.
2. **Era-validering:** Advar-og-tillad (blød advarsel i preview), respekterer ægte inkonsistente tilfælde.
3. **Union-model:** "Tilføj partner" opretter ny union; "tilføj barn" vælger blandt eksisterende unioner.
   Mangler union? Opret partner først.

## Arkitektur

Spejler 2C-2a: nye family-write-RPC'er + en egen per-person familie-fetch (med id'er) + en
PersonPicker-komponent + redigerbare familie-sektioner. Alle writes via det eksisterende
`setPending → SkrivePreviewSheet`-gate (dry-run/live). Familie-fetchen afkobler den redigerbare visning
fra de afledte selectors (som ikke kan targetere links) og re-fetches efter writes.

### RPC'er (schema.sql + db-migrations.sql, alle SECURITY DEFINER, rolle-gated, `max(id)+1`)

Alle gater `IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'`.

1. **`red_opret_union(p_partner_a bigint, p_partner_b bigint, p_type text, p_ordinal int DEFAULT NULL) RETURNS bigint`**
   - Validér begge personer findes (`EXISTS person`). Validér `p_partner_a <> p_partner_b`.
   - Validér `p_type ∈ ('vielse','partnerskab','ugift union')`.
   - Dup-guard: hvis en family allerede har præcis disse to (og kun disse to) som `partner`, returnér dens id.
   - Ellers: `INSERT family(max+1, p_type)`; `INSERT family_member(fam, p_partner_a, 'partner', p_ordinal, NULL)`
     + samme for b. Returnér family_id.

2. **`red_tilfoej_barn(p_family_id bigint, p_barn_id bigint, p_rolle text DEFAULT 'barn', p_konfidens text DEFAULT NULL) RETURNS void`**
   - Validér family findes (`EXISTS family`), barn-person findes, `p_rolle ∈ ('barn','adopteret_barn','plejebarn','stedbarn')`.
   - Validér `p_konfidens` NULL eller ∈ konfidens-vocab.
   - Dup-guard: hvis `(p_family_id, p_barn_id, p_rolle)` allerede findes → no-op (ingen fejl).
   - `INSERT family_member(p_family_id, p_barn_id, p_rolle, NULL, p_konfidens)`.

3. **`red_set_familie_konfidens(p_family_id bigint, p_person_id bigint, p_rolle text, p_konfidens text) RETURNS void`**
   - Validér `p_konfidens` NULL eller ∈ `('sikker','sandsynlig','formodet','omstridt')`.
   - `UPDATE family_member SET konfidens=p_konfidens WHERE family_id=p_family_id AND person_id=p_person_id AND rolle=p_rolle`.
   - Hvis ingen række ramt → RAISE (link findes ikke).

4. **`red_slet_familie_link(p_family_id bigint, p_person_id bigint, p_rolle text) RETURNS void`**
   - `DELETE FROM family_member WHERE family_id=p_family_id AND person_id=p_person_id AND rolle=p_rolle`.
   - Oprydning: hvis family derefter har 0 partnere OG 0 børn → `DELETE FROM family WHERE id=p_family_id`.
   - Ingen evidens-cascade (familie-links bærer ingen evidens).

### Fetch + mapper (`mobile/src/data/redaktionRead.ts`)

**`fetchPersonFamilie(id, model): Promise<PersonFamilie>`** — pagineret (getAll). Henter alle
family_member-rækker for de familier personen indgår i (som partner og som barn), strukturerer:
```ts
type FamiliePartner = { personId: string; navn: string; konfidens: string | null; ordinal: number | null };
type FamilieBarn    = { personId: string; navn: string; rolle: string; konfidens: string | null };
type Union          = { familyId: string; type: string; partnere: FamiliePartner[]; boern: FamilieBarn[] };
type SomBarn        = { familyId: string; rolle: string; konfidens: string | null; foraeldre: { personId: string; navn: string }[] };
type PersonFamilie  = { somPartner: Union[]; somBarn: SomBarn[] };
```
Navne via `model.byId`; fallback `#<id>`. Ren mapper `mapFamilieRows(famRows, memberRows, model)` er
unit-testbar. Fejl kastes (aldrig tom-som-clean).

### Komponenter

- **`mobile/src/components/redaktion/PersonPicker.tsx`** (ny) — søgbar Modal over redaktør-person-puljen
  (`fetchRedaktionPersoner` + `searchPool`), props `{ onValg: (v:{personId,navn})=>void; onClose }`.
  Parallel til `EntitetPicker`. Ekskluderer evt. selv-personen som valg.
- **`mobile/src/app/redaktion/person/[id].tsx`** — familie-sektionen drevet af `fetchPersonFamilie`:
  - ÆGTEFÆLLER/unioner: pr. union vis partnere + børn m. konfidens-dropdown + slet pr. link;
    "+ Tilføj barn" pr. union; per-side "+ Tilføj partner".
  - FORÆLDRE (somBarn): forældre-navne read-only; konfidens-dropdown + slet-link (afkobl forkert forælder).

### Era-validering (`mobile/src/data/` helper)

**`eraAdvarsel(barnFoedselAar: number|null, foraeldre: {foedsel:number|null; doed:number|null}[]): string | null`**
— returnerer en dansk advarselsstreng hvis barnets fødselsår < en forælders fødselsår, eller >
forælders dødsår + margin (fx 1 år), ellers `null`. Vises i tilføj-barn-arket; blokerer ikke.
År fra `redaktionModel` (visning_*/parsede fakta).

### Write-path (`mobile/src/data/redaktionWrite.ts`)

Nye `Change.art`: `opretUnion | tilfoejBarn | setFamilieKonfidens | sletFamilieLink`. Nye felter på
`Change` efter behov (`familyId?`, `personId?`, `rolle?`, `konfidens?`, payload til opretUnion/tilfoejBarn).
`buildRpcCall`-cases mapper til RPC'erne; param-navne char-for-char = SQL-signaturer. Returnér `null`
ved manglende påkrævede felter (no-op, som eksisterende cases).

## Dataflow (tilføj barn)

```
"+ Tilføj barn" på union U → PersonPicker → vælg barn-person B
  → barn-subtype-dropdown + eraAdvarsel(B.foedsel, U.partnere) vist i ark
  → Gem → setPending({art:'tilfoejBarn', payload:{familyId:U.familyId, barnId:B.personId, rolle, konfidens}})
  → SkrivePreviewSheet (dry-run/live) → red_tilfoej_barn
  → onApplied: fetchPersonFamilie re-fetch → setFamilie(frisk)
```

## Fejlhåndtering

- RPC'er RAISE ved rolle-brud, ikke-eksisterende person/family, ugyldig type/rolle/konfidens.
- Fetch kaster ved Supabase-fejl (aldrig tom-som-clean — cycle 03 NEW1).
- Era-advarsel er ikke-blokerende.
- Writes kun via dry-run/live-gate; ingen direkte tabel-write.

## Test

- **jest:** `mapFamilieRows` (struktur + navne-opslag + fallback); `buildRpcCall` 4 cases; `eraAdvarsel`
  grænsetilfælde (barn før forælder, efter død, NULL-år → ingen advarsel).
- **SQL rollback-tests** (nul mutation) pr. RPC: dup-guards (opret_union returnerer eksisterende;
  tilfoej_barn no-op ved dublet), validering (person/family findes, type/rolle/konfidens-vocab,
  partner_a≠b), tom-family-oprydning ved sidste slet, konfidens-UPDATE rammer rigtige række.
- **manuel web-e2e.**

## Non-goals (udskudt)

- Evidens-triplet på familie-links (de bærer ingen evidens — verificeret).
- Identitets-sammenkædning (er to kilders person den samme).
- Flytning af barn mellem unioner (= slet + tilføj manuelt).
- Bredere `redaktionModel`-invalidering ud over familie-fetchen (spec §9-follow-up, jf. 2C-1/2C-2a).
- Ændring af union-`type` efter oprettelse; ændring af `ordinal` efter oprettelse.
- in-place navne-redigering af partner/barn (gøres i den persons egen editor).

## Påvirkede filer

**Ændrede:** `schema.sql`, `db-migrations.sql` (4 RPC'er); `mobile/src/data/redaktionRead.ts`
(fetchPersonFamilie + mapFamilieRows + typer); `mobile/src/data/redaktionWrite.ts` (4 cases + Change-felter);
`mobile/src/app/redaktion/person/[id].tsx` (redigerbar familie-sektion); ny era-helper-fil + dens test.

**Nye:** `mobile/src/components/redaktion/PersonPicker.tsx`.
