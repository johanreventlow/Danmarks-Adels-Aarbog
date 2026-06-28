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
- **`red_relation` (INSERT) findes; INGEN slet/edit-RPC** for relation → nye RPC'er kræves.
- **`buildAux` dropper `relation.id`** på officesBy/estatesBy-rækkerne → kan ikke slette derfra.
  Derfor: egen per-person relation-fetch med id'er.
- **Relationer HAR evidens (verificeret live):** 955 `assertion` + 955 `conclusion` med
  `target_type='relation'` (0 `note`). Disse har INGEN FK til `relation` (polymorf target). →
  **flad `DELETE FROM relation` forældreløser 955 evidens-rækker** + max(id)+1-genbrug kan knytte
  gammel evidens til en ny relation (Codex 2C-2a #1; jf. [[fk-ordning-evidens-slet]]).

---

## 1. Besluttede valg (anbefalede defaults — bekræftes)

| Beslutning | Valg | Note |
|---|---|---|
| Redigerbarhed | **Kun tilføj + slet** | Ingen in-place edit af rolle/periode (edit = slet + tilføj). Fladt insert/delete. |
| Relations-visningens datakilde | **Egen fetch (`fetchPersonRelationer`), re-hentet efter write** | Ingen afhængighed af den stale redaktion-model (cache-gæld sidesteppet for relations). |
| Redigerbare typer | **hverv (org) + godser (estate)** | events vises + sletbare, men "+ Tilføj" tilbyder kun org/gods (ingen event-liste). |

---

## 2. DB: to RPC'er (FK-ordnet slet + valideret tilføj)

### 2a. `red_slet_relation` — FK-ordnet (Codex #1)
Spejler `red_slet_person`'s relations-cleanup, scoped til ÉN relation: citation → conclusion →
assertion → note → relation. ALDRIG flad DELETE (forældreløser de 955 evidens-rækker).
```sql
CREATE OR REPLACE FUNCTION red_slet_relation(p_relation_id bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  DELETE FROM citation WHERE assertion_id IN
    (SELECT id FROM assertion WHERE target_type='relation' AND target_id=p_relation_id);
  DELETE FROM conclusion WHERE target_type='relation' AND target_id=p_relation_id;
  DELETE FROM assertion  WHERE target_type='relation' AND target_id=p_relation_id;
  DELETE FROM note       WHERE target_type='relation' AND target_id=p_relation_id;
  DELETE FROM relation   WHERE id=p_relation_id;
END $$;
```

### 2b. `red_tilfoej_relation` — valideret + dup-guard (Codex #2)
Erstatter rå `red_relation` for UI-brug (red_relation bevares for R-load/bagudkomp). Validerer
objekt-eksistens + springer dublet over:
```sql
CREATE OR REPLACE FUNCTION red_tilfoej_relation(
  p_subjekt_id bigint, p_objekt_type text, p_objekt_id bigint, p_rolle text, p_periode_raw text DEFAULT NULL)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_id bigint; v_findes boolean;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  IF p_objekt_type NOT IN ('organisation','estate') THEN RAISE EXCEPTION 'Ugyldig objekt_type %', p_objekt_type; END IF;
  -- Objekt-eksistens (mod stale/manipuleret picker-id):
  IF p_objekt_type='organisation' THEN SELECT EXISTS(SELECT 1 FROM organisation WHERE id=p_objekt_id) INTO v_findes;
  ELSE SELECT EXISTS(SELECT 1 FROM estate WHERE id=p_objekt_id) INTO v_findes; END IF;
  IF NOT v_findes THEN RAISE EXCEPTION 'Objekt %/% findes ikke', p_objekt_type, p_objekt_id; END IF;
  -- Dup-guard (double-tap/retry): returnér eksisterende hvis samme subjekt/objekt/rolle:
  SELECT id INTO v_id FROM relation WHERE subjekt_type='person' AND subjekt_id=p_subjekt_id
    AND objekt_type=p_objekt_type AND objekt_id=p_objekt_id AND coalesce(rolle,'')=coalesce(p_rolle,'') LIMIT 1;
  IF v_id IS NOT NULL THEN RETURN v_id; END IF;
  INSERT INTO relation(id, subjekt_type, subjekt_id, objekt_type, objekt_id, rolle, periode_raw)
    VALUES ((SELECT coalesce(max(id),0)+1 FROM relation), 'person', p_subjekt_id, p_objekt_type, p_objekt_id, p_rolle, p_periode_raw)
    RETURNING id INTO v_id;
  RETURN v_id;
END $$;
```
**`max(id)+1`-concurrency** = projekt-bredt PoC-tradeoff (alle `red_*` bruger det; single-writer) —
noteres, ikke løst her. **Evidens-triplet for tilføjede relationer** (assertion+conclusion som de 955
har) er IKKE inkluderet — en bar relation viser korrekt i editor + publikum (begge læser relation-
tabellen, ikke evidens); evidens-laget for manuelt-tilføjede relationer = follow-up (§9).

Begge idempotent i `schema.sql` + `db-migrations.sql`; grant arver `red_*`-loopet. Deploy =
controller-gate (prod, bruger-OK + backup).

## 3. Data: `fetchPersonRelationer`

Nyt i `redaktionRead.ts`:
```ts
type PersonRelation = {
  relationId: number; art: 'hverv' | 'gods' | 'event';
  objektType: string; objektId: string; navn: string; rolle: string; periode: string;
};
async function fetchPersonRelationer(id: string, aux: Aux | null): Promise<PersonRelation[]>;
```
- **Pagineret** (`getAll`/`.range` — PostgREST capper ved 1000 lydløst; Codex #4): `relation` WHERE
  `subjekt_type='person' AND subjekt_id=id AND objekt_type IN ('organisation','estate','historical_event')`,
  stabil `order('id')`.
- Opløser `navn` via `aux` (orgListe/godsListe parametre — `navn` fallback `'#' + objektId` hvis ikke
  i listen / aux null). `historical_event`-navn: ingen liste → fallback `'Begivenhed #id'` (events er kun slet-bare).
- `art`: organisation→'hverv'; historical_event→'event'; estate→'gods'.
- **Kaster ved error** (ingen tom-som-clean). Ren `mapRelationRow(rows, aux)` adskilt → unit-test.

## 4. App-write

Nye `buildRpcCall`-cases (de gamle art 'gods'/'hverv'→`red_relation` udfases for UI):
- `sletRelation` → `red_slet_relation(p_relation_id)`. Change får `relationId?: string`.
- `tilfoejRelation` → `red_tilfoej_relation(p_subjekt_id, p_objekt_type, p_objekt_id, p_rolle, p_periode_raw)`
  fra payload `{objektType, objektId, rolle, periodeRaw}`.

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

**Ændrede:** `schema.sql`/`db-migrations.sql` (red_slet_relation FK-ordnet + red_tilfoej_relation valideret);
`redaktionRead.ts` (fetchPersonRelationer pagineret/mapRelationRow/PersonRelation); `redaktionWrite.ts`
(sletRelation+tilfoejRelation-cases + Change.relationId); `app/redaktion/person/[id].tsx` (redigerbar
relations-sektion).
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
- **Evidens-triplet for manuelt-tilføjede relationer** (assertion+conclusion, som de 955 har) —
  bar relation viser korrekt; evidens-laget = follow-up.
- **Bredere cache-invalidering (Codex #3):** editorens relations-sektion bruger egen fetch (frisk
  efter write), MEN `buildAux`'s `officesBy/estatesBy/ownersByEstate/ownerCount` afledes af det
  oprindelige relation-snapshot → efter en relation-write viser publikums-personside + gods-detalje-
  ejer-tidslinje + 2C-1's gods-ownerCount STADIG gammel data til model-reload. Dette er den deferrede
  cache-gæld (2B-M2 + cycle 05 NEW1) udvidet til relation-afledte views. 2C-2a fixer KUN editor-
  sektionen; den centrale `redaktionAux`/publikums-aux-invalidering efter relation-write er en
  fokuseret follow-up. (Honest scoping — påstanden "sidesteps cache-gæld" gælder kun editor-sektionen.)

---

## 10. Codex adversarial-review konsekvens (2026-06-28)
- **#1 [HIGH] flad delete forældreløser evidens** — confirmed (955 assertion+conclusion target_type='relation').
  Rettet: `red_slet_relation` er FK-ordnet (§2a), spejler red_slet_person.
- **#2 [HIGH] tilføj uvalideret/ikke-idempotent** — confirmed. Rettet: `red_tilfoej_relation` (§2b)
  validerer objekt-type+eksistens + dup-guard. `max(id)+1`-concurrency = projekt-bredt PoC-debt (noteret).
- **#3 [MED] cache kun delvist løst** — confirmed. §9 ærlig-gjort: egen-fetch frisker kun editor-
  sektionen; bredere aux-invalidering = follow-up.
- **#4 [MED] pagination mangler** — confirmed. Rettet: `fetchPersonRelationer` bruger getAll (§3).
- **Læring:** evidens-baseret model → enhver SLET af en evidens-bærende entitet (fact/relation/person)
  kræver FK-ordnet cascade. Tredje gang dette rammer ([[fk-ordning-evidens-slet]]) → tjek ALTID
  target_type-polymorfe børn før delete-RPC designes.
