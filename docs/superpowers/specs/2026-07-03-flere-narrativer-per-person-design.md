# Flere narrativer pr. person (udgave-nøglede narrativer) — design

**Dato:** 2026-07-03
**Status:** Godkendt design, revideret efter dual-review (Codex, 2026-07-03) — se
`docs/reviews/18-flere-narrativer-per-person-design-review.md`. Afventer implementeringsplan.
**Driver:** Flere DAA-udgaver pr. person — samme person optræder i fx DAA 2018-20 og en
senere/tidligere udgave med forskellig biografisk prosa. Hver udgave er en selvstændig
`source` (invariant §7); prosaen bevares ordret (invariant §6).
**Scope:** Redaktør + datalag nu. Læser-siden gøres **deterministisk** (web + mobil), men
uden fulde udgave-faner — de er flagget follow-up.

---

## 1. Problem

`narrative`-tabellen (`schema.sql:235`) tillader allerede N rækker pr. person (intet
unique-constraint, og `source_id` + `side`-kolonner findes præcis til udgave-granularitet).
Men tre lag kollapser kunstigt til **én** narrativ pr. person:

| Lag | Fil | Adfærd i dag |
|---|---|---|
| Skrive-RPC | `schema.sql:592` `red_upsert_narrativ` | find-or-create på `(subjekt_type, subjekt_id)` med `ORDER BY id LIMIT 1` → låser til første række |
| Redaktør-læs | `web/src/data/redaktionRead.ts:163` `fetchPersonNarrativ` | `LIMIT 1` |
| Redaktør-skriv | `web/src/data/redaktionWrite.ts:101` | sender ingen `source_id` |
| Redaktør-UI | `web/src/Redaktion.tsx:431` | ét `<textarea>` |
| Læser (web) | `web/src/data/public.ts:130` | offentlige narrativer, `first`-pr-medlem (`order by id`) |
| Læser (mobil) | `mobile/src/data/load.ts:173` | `bioBy` = første ikke-private narrativ, **ingen sortering** |

**Verificeret datatilstand (prod, 2026-07-03):** 591 narrativer, alle `source_id = 1`
("DAA 2018-20"), 0 `NULL`, 0 personer med >1 narrativ. `source` 2 (TNG) findes med 0
narrativer. Ændringen er derfor fremadrettet og kollisionsfri på eksisterende data.

## 2. Valgt tilgang: kilde-nøglet narrativ (Tilgang A)

Logisk nøgle for en persons komplette biografi-opslag i én udgave =
`(subjekt_type, subjekt_id, source_id)`. Én narrativ-række pr. (person, udgave); prosaen
forbliver én uafhængig, ordret-bevaret række.

**Forkastede alternativer:**
- **B — id-adresseret generisk liste** (vilkårligt mange blokke pr. kilde via nye
  `red_add/edit/slet_narrativ`-RPC'er): over-engineering ift. udgave-driveren; kilde mister
  sin rolle som organiserende nøgle; mere UI (tilføj/slet/omordn).
- **C — konkatenér til én narrativ:** bryder §6 (ordret, forfremmbar prosa) og §7
  (kilde-granularitet); kan ikke markere én udgave privat uafhængigt.

## 3. Ændringer pr. lag

### 3.1 DB-lag (`schema.sql` + `db-migrations.sql`, idempotent)

1. **Additiv kolonne `source.aar SMALLINT`** (nullable). Bærer udgave-kronologi eksplicit,
   fordi `source.id` er ren PK uden kronologisk semantik og `source.udgave` er *ukontrolleret
   fritekst* (leksikalsk sortering forkastet — 'DAA særudgave 2018', '2018–20' mv. bryder den).
   **Design-beslutning (ikke udskudt):** semantikken er "seneste DAA-udgave" båret af et
   struktureret `aar`-felt. Backfill for eksisterende DAA-udgaver (source 1 → 2018). Additiv,
   idempotent (`ADD COLUMN IF NOT EXISTS`), verificeres af `db-verify.sql`.

2. **`red_upsert_narrativ` — ny signatur.** Nøgles på `(subjekt_type, subjekt_id, source_id)`.
   - Eksplicit `DROP FUNCTION red_upsert_narrativ(text, bigint, text, boolean)` **før**
     `CREATE`, så PostgREST ikke ender med to overloads (tvetydig resolution).
   - Ny signatur:
     `red_upsert_narrativ(p_subjekt_type text, p_subjekt_id bigint, p_tekst text, p_privat boolean, p_source_id bigint, p_side text DEFAULT NULL)`.
   - `p_source_id` er den faktiske nøgle. **Begge app-klienter (web + mobil) sender den** (se
     §3.3b) → ingen NULL-vilkårlig "opdater første række"-fallback (den var farlig — kunne
     overskrive en tilfældig udgave).
   - `UPDATE`-grenen: `side = COALESCE(p_side, side)` (udeladt side sletter ikke eksisterende;
     rydning kræver eksplicit sentinel — accepteret begrænsning, se review 18 M2).
   - Uændret: `current_rolle()='redaktion'`-guard, `begin_change_set`-wrapping,
     `max(id)+1`-ID-allokering (præeksisterende concurrency-begrænsning, ikke forværret).

3. **Ny udgave: udvid eksisterende `red_opret_kilde`** (`schema.sql:983`) additivt med
   `p_aar smallint DEFAULT NULL` (bagudkompatibelt — mobilens eksisterende kald består).
   **Ingen ny source-RPC.** For en DAA-udgave sættes `p_slags='DAA-udgave'` + `p_aar`; `aar`
   er påkrævet felt i "+ Ny udgave"-UI når slags er DAA-udgave (ellers er læser-defaulten ikke
   pålidelig for den nye udgave).

4. **DB unique-constraint: udskudt.** RPC'ens find-or-create *reducerer* (håndhæver IKKE
   hårdt) dubletter pr. (subjekt, source): SELECT-derefter-INSERT uden constraint beskytter
   ikke mod direkte imports/andre skriveveje/eksisterende dubletter. Derfor **skal
   læser-selectoren have sidste tie-break på `narrative.id`**, og editoren skal håndtere
   dubletter uden vilkårligt overwrite. En evt. hård constraint skal være partiel + scoped
   (`WHERE source_id IS NOT NULL`), ikke global på estate/family/TNG, og kræver forudgående
   "ingen dubletter"-validering. Ikke i denne omgang.

### 3.2 Læse-lag (redaktør)

- `fetchPersonNarrativ` → **`fetchPersonNarrativer(id)`**: returnerer `PersonNarrativ[]`
  (`{ id, sourceId, sourceTitel, sourceUdgave, side, tekst, privat }`) ordnet efter kilde,
  i stedet for `LIMIT 1`.
- **`fetchSources()`**: liste af `source`-rækker (id, titel, udgave, slags, aar) til
  udgave-vælgeren ("+ Ny udgave").

### 3.3 Redaktør-UI (`Redaktion.tsx`)

- Under "Narrativ · biografi": en **udgave-fanerække** (chips) — én chip pr. kilde personen
  har en narrativ i, sorteret efter udgave, + **"+ Ny udgave"** (vælg eksisterende kilde
  eller opret via `red_opret_kilde`).
- `textarea` + `privat` + `side` binder til den **aktive udgaves** entry.
  Editor-state holder `id` + `source_id` + `side` (fane-nøgler + pålidelig save/reload) —
  ikke kun `{tekst, privat}`.
- "Gem narrativ" sender den aktive udgaves `p_source_id` + `p_side`.
- Uafklarede edits ved fane-skift håndteres som det eksisterende record-skift (advar/kassér,
  jf. `Redaktion.tsx:553`).

### 3.3b Mobil-redaktør (minimal, source-korrekt — obligatorisk pga. RPC-DROP)

Mobilen er den **anden** RPC-klient og knækker ellers når den gamle signatur droppes
(`mobile/src/data/redaktionWrite.ts:105` kalder uden `p_source_id`;
`mobile/.../redaktionRead.ts:183` læser `LIMIT 1`). Minimal lockstep-ændring:
- Read vælger også `source_id` fra den læste narrativ-række.
- Write sender `p_source_id` (+ `p_side` hvis kendt).
- **Beholder single-narrativ-UI** (ingen faner) — redigerer den source-korrekte primær-række.
- Fulde udgave-faner i mobil-redaktøren = eksplicit follow-up.

### 3.4 Læser (minimal — delt selector for web + mobil)

Én **delt, deterministisk "foretrukne offentlige bio"-selector** — implementeret som **én ren
funktion / fælles kontrakt** (ikke to parallelle dataflows; web og mobil skal dele
kontrakt-tests, ellers divergerer de). Brugt af både `web/src/data/public.ts` og
`mobile/src/data/load.ts`.

**Prioriteret fallback-kæde (ikke "enhver offentlig narrativ" — det ville gøre en TNG-stub
autoritativ):**
1. Blandt `privat = false`-narrativer med kildens `slags = 'DAA-udgave'`: nyeste udgave.
2. Ellers **kun** narrativer fra en eksplicit godkendt fallback-source-type (defineres i
   planen; TNG-stubs er ikke standardbio). Byline udelades/generisk.
3. Ellers: ingen bio (vis tom-tilstand — skjul ikke en fejl).

**Fuld deterministisk orden** (tie-break helt ud, fordi DB-unikhed er udskudt):
`aar DESC NULLS LAST, source_id DESC, narrative.id DESC`. **Aldrig** ren `max(source_id)`.

- **`samme_som`-foldning:** selectoren vælger den foretrukne udgave på tværs af **hele den
  foldede identitetsgruppe** — ikke uafhængigt pr. rå medlem. Konkret betyder det, at
  narrativ-kandidaterne enten (a) mappes til kanonisk id *før* selector-valget, eller (b)
  bevares gennem collapse og vælges bagefter (web `public.ts:135`, mobil `load.ts:173` +
  `collapseSameAs.ts:263`). Dette er selve grunden til at selectoren skal være delt.
- Eksponér kilde-metadata (`udgave`/`titel`) så læseren kan vise en diskret byline
  (*"— efter Dansk Adels Aarbog 2018-20"*).
- **RLS:** `source` er `USING(true)` for anon+authenticated (`db-rls.sql:112`), så klientside
  `slags`-filter er lovligt; narrative-RLS filtrerer private rækker før klienten. Ingen
  lækage-risiko — kun klient-divergens, som den delte selector adresserer.
- **Ingen fulde udgave-faner for læseren** i denne omgang (giver først værdi ved 2 udgaver).

## 4. Invarianter & sideeffekter

- **§6 (prosa ordret):** hver udgave er sin egen række; intet konkateneres/overskrives.
- **§7 (udgave = source):** kilde-nøgling er den native model.
- **Versionering/undo:** `log_change`-trigger + `red_fortryd_change_set` identificerer
  narrativer pr. `id` (`schema.sql:1032` registry, `schema.sql:1271` undo-regen). Flere
  rækker versioneres/fortrydes uafhængigt — **ingen ændring nødvendig**. `_version_upsert_row`
  ekskluderer allerede `GENERATED ALWAYS`-kolonner (`narrative.fts`).
- **Hyperlinks/mentions:** `trg_mentions_narrative → parse_mentions` er pr. narrativ-id —
  uændret; flere rækker giver flere uafhængige mention-kilder.
- **RLS:** per-række synlighed via person/privat er uændret korrekt (`db-rls.sql:196/425`).
- **Kendt begrænsning (uændret):** `max(id)+1` i `red_upsert_narrativ`/`red_opret_kilde` er
  ikke concurrency-sikker. Præeksisterende; ude af scope.
- **Atomicitet:** oprettelse af kilde og narrativ er separate change sets. UI må ikke antyde
  atomisk "opret udgave + tekst"; fortryd af en kilde med refererende narrativ fejler på FK
  (forventet).

## 5. Test

**Unit:**
- `fetchPersonNarrativer` grupperer/ordner pr. kilde korrekt.
- Skrive-arg-builder (**web OG mobil** `redaktionWrite.ts`) sender `p_source_id` + `p_side`.
- Delt læser-selector (fælles kontrakt-test kørt mod både web- og mobil-adapter):
  - vælger nyeste DAA-udgave (`aar DESC NULLS LAST, source_id DESC, narrative.id DESC`);
  - `NULLS LAST`: ny udgave uden `aar` vinder ikke over backfillet 2018;
  - fallback-kæde: DAA først → godkendt fallback-type → ingen bio (aldrig vilkårlig TNG-stub);
  - privat/offentlig: nyeste udgave kun-privat, ældre offentlig → vælger den ældre offentlige;
  - foldet-person: vælger ét narrativ på tværs af hele identitetsgruppen;
  - deterministisk ved ens `aar` (tie-break rammer).

**Manuel mod prod (redaktør):**
- Udvid `red_opret_kilde` med `p_aar` → opret/vælg kilde #2 → tilføj narrativ for testperson →
  begge udgaver sameksisterer.
- Rediger hver udgave uafhængigt; verificér `privat` + `side` pr. udgave.
- Fortryd pr. udgave (change set) rammer kun den udgave.
- Byline viser korrekt udgave i både web- og mobil-læser.
- **Mobil-redaktør Gem virker efter RPC-DROP** (regression-guard for det missede HIGH-fund):
  mobil sender `p_source_id` og rammer den korrekte række.

## 6. Bevidst udeladt (YAGNI / follow-up)

- Fulde udgave-faner/valg i læser-fladen.
- **Udgave-byline i læseren** ("— efter DAA 2018-20"): `pickPreferredBio` bærer `udgave`-feltet,
  men `public.ts`/`load.ts` propagerer kun bio-teksten pt. Byline-rendering er udskudt (kun værdi
  ved >1 udgave; kræver at source-metadata trådes gennem `fetchPersonDetail`-returtypen + mobil).
- Fulde udgave-faner i **mobil-redaktøren** (mobil får kun minimal source-korrekt skrivevej nu).
- Tematiske afsnit pr. udgave (Tilgang B).
- Reorder/slet-UI ud over det nødvendige.
- Hård DB unique-constraint på `(subjekt, source_id)`.
- Concurrency-sikker ID-allokering.
- `NOTIFY pgrst`-cache-reload som kode (behandles som deploy-verifikationspunkt, review 18 L2).
