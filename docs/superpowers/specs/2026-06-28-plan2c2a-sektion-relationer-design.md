# Plan 2C-2a — Sektion-relationer (rediger hverv/godser) (design/spec)

**Dato:** 2026-06-28
**Status:** Udkast (afventer Codex-review + bruger-godkendelse)
**Branch:** arbejd på `main` (feature-branch ved implementering)
**Kontekst:** 2B viser hverv/godser read-only. 2C-2a gør dem redigerbare (tilføj/fjern person↔
entitet-relationer). Familie (family_member) = 2C-2b; entitets-editor (rediger godset selv) = 2C-3.

Forudgående: 2B (editor, separat redaktion-model), 2C-1 (entitets-lister i redaktionAux).

---

## 0. Kontekst-fund (verificeret mod kode/skema/live-data)

- **"Relationer" i 2B = to forskellige tabeller.** Hverv/godser = `relation`-tabellen (live:
  organisation 503, estate 418, historical_event 34, source 6). Familie = `family_member` (separat,
  partner 607 / barn 393) → **ikke** del af 2C-2a.
- **Kilder = `person_external_id`, IKKE relation** (`aux.sourcesBy` bygges af external_id) → ikke
  redigerbar her.
- **`red_relation` (INSERT) findes; INGEN slet/edit-RPC** for relation → ny `red_slet_relation` kræves.
- **`buildAux` dropper `relation.id`** på officesBy/estatesBy-rækkerne → kan ikke slette derfra.
  Derfor: egen per-person relation-fetch med id'er.

---

## 1. Besluttede valg (anbefalede defaults — bekræftes)

| Beslutning | Valg | Note |
|---|---|---|
| Redigerbarhed | **Kun tilføj + slet** | Ingen in-place edit af rolle/periode (edit = slet + tilføj). Fladt insert/delete. |
| Relations-visningens datakilde | **Egen fetch (`fetchPersonRelationer`), re-hentet efter write** | Ingen afhængighed af den stale redaktion-model (cache-gæld sidesteppet for relations). |
| Redigerbare typer | **hverv (org) + godser (estate)** | events vises + sletbare, men "+ Tilføj" tilbyder kun org/gods (ingen event-liste). |

---

## 2. DB: `red_slet_relation`

```sql
CREATE OR REPLACE FUNCTION red_slet_relation(p_relation_id bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  DELETE FROM relation WHERE id = p_relation_id;
END $$;
```
Idempotent i `schema.sql` + `db-migrations.sql`; grant arver `red_*`-loopet i `db-rls.sql`. Deploy =
controller-gate (prod, bruger-OK + backup) — samme model som tidligere DDL.

## 3. Data: `fetchPersonRelationer`

Nyt i `redaktionRead.ts`:
```ts
type PersonRelation = {
  relationId: number; art: 'hverv' | 'gods' | 'event';
  objektType: string; objektId: string; navn: string; rolle: string; periode: string;
};
async function fetchPersonRelationer(id: string): Promise<PersonRelation[]>;
```
- Selecter `relation` WHERE `subjekt_type='person' AND subjekt_id=id AND objekt_type IN
  ('organisation','estate','historical_event')` → `{id, objekt_type, objekt_id, rolle, periode_raw}`.
- Opløser `navn` via `redaktionAux` (orgListe/godsListe) — eller et lille navne-opslag hvis ikke i aux.
- `art`: organisation/historical_event → 'hverv'/'event'; estate → 'gods'.
- **Kaster ved error** (ingen tom-som-clean). Ren `mapRelationRow` adskilt → unit-test.

## 4. App-write

`buildRpcCall`-case (eksisterende `red_relation` for tilføj via art 'gods'/'hverv'; ny for slet):
- `sletRelation` → `red_slet_relation(p_relation_id)`. Change får `relationId?: string`.
- Tilføj: art 'hverv'/'gods' → `red_relation` (findes) med payload `{objektType, objektId, rolle, periodeRaw}`.

## 5. Editor (`person/[id].tsx`)

2B's read-only hverv/godser-blok → **redigerbar relations-sektion** (familie + kilder forbliver read-only):
- Henter `fetchPersonRelationer(id)` i `useEffect([id])` (egen state); re-fetch efter write (onApplied).
- Pr. rad: navn + rolle + periode + **🗑 slet** → `setPending({art:'sletRelation', relationId})` → SkrivePreviewSheet.
- Pr. type (Hverv/Godser): **"+ Tilføj"** → entitets-picker-sheet (§6) → vælg entitet + rolle (fri tekst) +
  periode → `setPending({art:'hverv'|'gods', payload:{objektType, objektId, rolle, periodeRaw}})`.
- Fejl-tilstand (fetch-fejl) → eksplicit, ikke tom-som-clean.

## 6. Entitets-picker-sheet

Ny komponent `EntitetPicker.tsx`: Modal m. søgbar liste fra `redaktionAux` (orgListe for hverv,
godsListe for gods) → tap → `onValg({ objektType, objektId, navn })` → luk. Genbruger 2C-1's liste-data.

## 7. Test

- **DB:** `red_slet_relation` rolle-gating + sletter rigtig række (live rollback-transaktion, nul mutation).
- **jest:** `mapRelationRow` (art-mapping org/estate/event, navn-opslag, fallback) + `buildRpcCall`
  `sletRelation`-case + tilføj-case (red_relation-args).
- **Manuel:** åbn person → "+ Tilføj gods" → vælg fra picker + rolle/periode → LIVE → vises → slet → forsvinder.

## 8. Berørte artefakter

**Ændrede:** `schema.sql`/`db-migrations.sql` (red_slet_relation); `redaktionRead.ts`
(fetchPersonRelationer/mapRelationRow/PersonRelation); `redaktionWrite.ts` (sletRelation-case +
Change.relationId); `app/redaktion/person/[id].tsx` (redigerbar relations-sektion).
**Nye:** `components/redaktion/EntitetPicker.tsx`.

## 9. Scope / non-goals

**I scope:** red_slet_relation; fetchPersonRelationer; tilføj/slet hverv+gods-relationer i editoren;
entitets-picker; re-fetch efter write.

**Non-goals (→ senere):**
- In-place edit af rolle/periode (= slet + tilføj).
- Familie-redigering (family_member) = 2C-2b.
- Event-tilføj (ingen event-liste; kun slet).
- Kilder (external_id) = ikke en relation.
- Generisk entitets-editor (rediger godset/org'en selv) = 2C-3.
- Bredere `redaktionModel`-invalidering (deferred cache-gæld) — relations-visningen bruger egen fetch,
  så den er upåvirket; editor-header-staleness er stadig 2B-M2-deferred.
