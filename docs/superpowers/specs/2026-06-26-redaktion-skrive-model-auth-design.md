# Redaktions-app — evidens-skrive-model + auth (design/spec)

**Dato:** 2026-06-26
**Status:** Godkendt design — klar til implementeringsplan
**Kontekst:** Mobil redaktør-app (`design_handoff_redaktion_mobile/`) skal skrive til
den evidensbaserede Supabase-base. Denne spec fastlægger **skrive-modellen** (hvordan
en redigering i UI'et oversættes korrekt til fact/assertion/conclusion/citation) og
**auth** (roller, login, write-RLS). Læse-laget findes allerede (`db-rls.sql`, anon-tier).

---

## 0. Baggrund: hvorfor handoff-write-laget ikke kan bruges som det er

Prototypens `design_handoff_redaktion_mobile/redaktion-write.js` matcher **ikke** det
deployede skema (`schema.sql`). Verificerede kolonne-mismatches:

1. `assertion` har `target_type/target_id` (peger på `fact`|`relation`) + `vaerdi_tekst`
   — write-laget POSTer `assertion {subjekt_type, subjekt_id, felt, vaerdi}` (forkerte
   kolonner; springer fact-laget helt over).
2. `conclusion` har ingen `felt`/`vaerdi`-kolonner — write-lagets PATCH-query
   (`subjekt_type/subjekt_id/felt`) rammer ikke-eksisterende kolonner.
3. `citation` bruger `lokation` i write-laget; kolonnen hedder `side`.
4. `suggestion`-tabel findes ikke i skemaet.
5. `profiles`-tabel findes ikke i skemaet.
6. Felt-abstraktionen (`navn/foedt/doed/koen/titel`) er flad; modellen er to-lags
   (`fact.faktatype` som "slot" + assertions hængt på via `target_type/target_id`),
   og `koen` er en arbejdsværdi-kolonne på `person`, ikke et fact.

Den dybe pointe (5+6): **"evidens-skrive-modellen" er reelt en fact-rekoncilierings-model.**
UI'et tænker fladt felt; basen kræver find-or-create af et `fact`-slot, derefter
assertion → citation → conclusion ovenpå.

---

## 1. Besluttede valg (denne spec)

| Beslutning | Valg | Note |
|---|---|---|
| Immutabilitet af assertion i PoC | **Blød / mutabel** | Bevidst, reversibel afvigelse fra invariant #1 / §7 — se §2. |
| Skrive-transport | **Postgres RPC** (`SECURITY DEFINER`) | Atomisk; write-RLS koger ned til rolle-tjek i funktionen. |
| Forslag-kø (suggestion) | **Simpel staging-blob** | Redaktør gennemser + re-anvender manuelt. Ingen auto-apply. |
| Roller i PoC | **redaktion + medlem** | Forsker-tier (betalt historisk arkiv) udskudt, additivt på `profiles.rolle`. |

---

## 2. Immutabilitets-afvigelsen (eksplicit)

Invariant #1 (CLAUDE.md §3) og §7: *påstande er uforanderlige; rettelser sker som nye
påstande + ny konklusion.* `assertion.uforanderlig DEFAULT TRUE`.

Prototypen har `✎ redigér` og `🗑 slet` på **enkelt-oplysninger** (README L67) og kalder
evidens-redigering "ikke-destruktiv" (L95) — hvilket modsiger invariant #1.

**Valg for PoC: blød/mutabel.** Begrundet i, at det er nyeste eksplicitte
bruger-instruktion (global regel #1: nyeste eksplicitte instruktion vinder). Konkret:

- `redigér oplysning` → **UPDATE** på assertion-rækken.
- `slet oplysning` → **DELETE** på assertion-rækken; var den valgt konklusion, re-peges
  konklusionen til første tilbageværende oplysning (fact-slot bevares).

**Reversibel migrationssti (skal bevares i implementeringen):**
- RPC'erne `red_edit_oplysning` / `red_slet_oplysning` indkapsler mutationen, så UI'et
  aldrig kender forskel. En senere stramning skifter funktionskroppen til
  insert-ny-assertion + re-peg konklusion (supersede) **uden UI-ændring**.
- Immutabilitet kan da håndhæves på DB-niveau ved at fjerne UPDATE/DELETE-stien i
  RPC'en og lade RLS nægte direkte UPDATE/DELETE på `assertion`.

---

## 3. Schema-tilføjelser

To nye tabeller (idempotent ALTER i `db-migrations.sql`; også i `schema.sql` som source
of truth).

```sql
CREATE TABLE profiles (
  id                   UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  rolle                TEXT NOT NULL DEFAULT 'medlem'
                         CHECK (rolle IN ('redaktion','medlem')),
  reventlow_person_id  BIGINT REFERENCES person(id),  -- knytter login → træet
  email                TEXT
);

CREATE TABLE suggestion (              -- staging for ikke-redaktion-roller
  id              BIGINT PRIMARY KEY,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  forslagsstiller UUID REFERENCES auth.users(id),
  status          TEXT NOT NULL DEFAULT 'afventer',  -- PoC: kun 'afventer' bruges
  art             TEXT,                 -- fakta|narrativ|relation|gods|hverv|...
  subjekt_type    TEXT, subjekt_id BIGINT,
  felt            TEXT, vaerdi TEXT,
  kilde_source_id BIGINT REFERENCES source(id),
  kilde_fritekst  TEXT,
  payload         JSONB DEFAULT '{}'::jsonb,
  note            TEXT
);
```

`status` på suggestion bevares som forward-kompatibel hook mod en fremtidig
godkend→auto-apply-kø, men PoC bruger kun staging-blob-flowet (§6).

---

## 4. Felt → faktatype-map + fact-rekonciliering

UI'ets flade `felt` mapper til modellen sådan:

| UI-felt | Model |
|---|---|
| `navn`  | `fact.faktatype = 'navn'`   → assertion.vaerdi_tekst |
| `foedt` | `fact.faktatype = 'fødsel'` → assertion (dato-felter) |
| `doed`  | `fact.faktatype = 'død'`    → assertion (dato-felter) |
| `titel` | `fact.faktatype = 'titel'`  → assertion.vaerdi_tekst |
| `koen`  | **IKKE et fact** — direkte `person.koen` (arbejdsværdi, datamodel §2) |

**Find-or-create-fact:** "Tilføj oplysning" på felt F for person P:

1. Find `fact WHERE subjekt_type='person' AND subjekt_id=P AND faktatype=map(F)`;
   findes ikke → INSERT.
2. INSERT `assertion (target_type='fact', target_id=fact.id, vaerdi_tekst=…,
   date_min/max/qualifier/raw=… for dato-felter)`.
3. INSERT `citation (assertion_id, source_id, side, citat_tekst, kvalitet)`.
4. **UPSERT** `conclusion (target_type='fact', target_id=fact.id, valgt_assertion_id)`
   — `UNIQUE(target_type, target_id)` → `ON CONFLICT … DO UPDATE`. (Et nyt fact har
   endnu ingen conclusion-række; derfor upsert, ikke PATCH.)

Dato-felter (`foedt`/`doed`) bærer fuzzy-interval + rå tekst på assertion
(`date_min, date_max, date_qualifier, date_raw`) — datamodellens fuzzy-dato-invariant (#5).

---

## 5. Skrive-API = Postgres RPC

**Alle writes går gennem `SECURITY DEFINER`-funktioner.** Tabeller har **ingen** direkte
INSERT/UPDATE/DELETE-grants til `authenticated`. Hver funktion validerer kalderens rolle
via `profiles` (`auth.uid()`). Det gør write-RLS = ét rolle-tjek pr. funktion, atomisk i
én transaktion (ingen TOCTOU-race på fact, ingen partial-failure-forældreløse rækker).

Funktioner (signaturer fastlægges i plan; her formål + rolle-gating):

| RPC | Formål | Rolle |
|---|---|---|
| `red_upsert_fakta(...)` | Fact-tripletten i §4, atomisk. Returnerer ids. | redaktion |
| `red_set_konklusion(assertion_id)` | "Gør til konklusion": re-peg `conclusion.valgt_assertion_id`. | redaktion |
| `red_edit_oplysning(assertion_id, vaerdi, kilde…)` | **PoC: UPDATE assertion** (blød, §2). | redaktion |
| `red_slet_oplysning(assertion_id)` | DELETE; var valgt → re-peg konklusion; fact bevares. | redaktion |
| `red_set_koen(person_id, koen)` | Direkte `person.koen` (arbejdsværdi). | redaktion |
| `red_set_privat(person_id, privat)` | Direkte `person.privat`. | redaktion |
| `red_slet_person(person_id)` | Sletning m. relations-advarsel (UI bekræfter). | redaktion |
| `red_upsert_narrativ(...)` | Narrativ opret/erstat. | redaktion |
| `red_relation(...)` | Relation (gods/hverv/familie-kant). | redaktion |
| `red_suggest(...)` | INSERT i `suggestion`. | medlem |

Rolle-gating: en `redaktion`-funktion kaldt af `medlem` → `RAISE EXCEPTION`. UI for
medlem viser kun forslag-flowet (`red_suggest`).

## 6. Forslag-kø (suggestion) — staging-blob

- Medlem-redigering kalder `red_suggest` → ét `suggestion`-row (`art` + `payload`).
- Redaktør gennemser staging og **re-anvender manuelt** ved at køre samme normaliserede
  `change` gennem redaktion-RPC'erne (som rolle=redaktion). Ingen auto-apply i PoC.
- `status` bevares forward-kompatibel mod fremtidig auto-apply-kø.

## 7. Cache-regenerering (invariant #4)

`person.visning_navn/foedt/doed/titel` er envejs-projektion af konklusioner — redigeres
aldrig direkte. Regenerering via **DB-trigger**, ikke app-side, så **alle** skrive-stier
(app-RPC, R-load, fremtidig GEDCOM/TNG-import) holdes konsistente:

- Trigger `AFTER INSERT/UPDATE/DELETE ON conclusion` → `regen_person_visning(pid)`.
- Også assertion-edits der ændrer den **valgte** oplysnings værdi skal trigge regen
  (trigger på `assertion` afgrænset til rækker hvis id = en konklusions
  `valgt_assertion_id`).
- `regen_person_visning(pid)` recomputer cache-felterne fra personens konklusioner
  (samme udledning som `validate.py`/load-laget bruger i dag).
- `koen` skrives direkte (arbejdsværdi) — ikke en del af cache-regen.

## 8. Auth

- Supabase Auth e-mail/adgangskode: `supabase.auth.signInWithPassword(...)`. Session
  persisteres via AsyncStorage (allerede konfigureret i `mobile/src/lib/supabase.ts`).
- Efter login: `select rolle, reventlow_person_id from profiles where id = auth.uid()`.
  Mangler row → default `medlem`.
- **PoC:** redaktør-konti oprettes manuelt i Supabase-dashboard + `profiles`-row seedes.
  Ingen selvbetjent signup-flow endnu (additivt senere).
- Global state (Zustand-store, `store/useStore.ts`): `auth {session, rolle,
  reventlow_person_id}`, `dryRun`, `showAnnotations`.

## 9. Read-RLS for `authenticated` (udvider `db-rls.sql`)

Eksisterende `anon`-lag (kun afdøde, ikke-private) bevares uændret. Tilføj
`authenticated`-politikker:

- Logget-ind `medlem`/`redaktion` ser **også levende** (login = adgang til det levende
  netværk — kerneforretningsmodellen, datamodel §7).
- Samtykke-granularitet pr. levende person (`samtykke_offentlig`-flag) **udskudt** —
  noteres i `db-rls.sql` FREMTID-blokken.
- Forsker-tier (read-only historisk arkiv, betalt) **udskudt**.

Writes håndhæves IKKE via tabel-RLS, men via RPC-rolle-tjek (§5): tabeller har ingen
write-grants til `authenticated`.

## 10. Dry-run

Med RPC kan dry-run ikke preview'e via rå REST-strenge (prototypens mønster). PoC:

- Dry-run = **klient-side**: skrive-preview-sheet viser hvilken RPC + JSON-args der ville
  blive kaldt; udfører ikke.
- LIVE kalder RPC'en og viser resultat / fejl.
- Global toggle (Zustand), styret fra top-bar-chip, dashboard-kort og Konto — samme state.

## 11. Fejlhåndtering

- RPC `RAISE EXCEPTION` ved manglende rolle, ugyldigt fact-target, eller constraint-brud
  → klienten viser fejlteksten i skrive-preview-sheet (prototypens fejl-mønster).
- Klient: `submit`-laget oversætter PostgREST-fejl (status + besked) til dansk fejltekst.

## 12. Test

- **DB:** pgTAP / SQL-asserts på RPC'erne: rolle-gating (medlem nægtes
  redaktion-RPC), fact find-or-create-idempotens, konklusion-re-peg ved slet af valgt,
  cache-regen efter conclusion-ændring, suggestion-INSERT for medlem.
- **App:** eksisterende selector-tests genbruges; nye tests for change-normalisering
  (UI-redigering → RPC-args) og dry-run-preview-generering.

---

## 13. Scope / non-goals

**I scope:** profiles + suggestion-tabeller; felt→faktatype-map + fact-rekonciliering;
RPC-skrive-API (redaktion + medlem); cache-regen-trigger; Supabase Auth + rolle-opslag;
authenticated read-RLS (levende synlig for login); klient-side dry-run.

**Non-goals (udskudt, additivt senere):**
- Hård immutabilitet af assertion (§2 migrationssti bevaret).
- Auto-apply-forslag-kø (state-maskine på suggestion).
- Forsker-tier + samtykke-granularitet pr. levende person.
- Selvbetjent signup / konto-administration.
- UI-implementering (denne spec dækker model + auth; UI er handoff-designet, egen plan).

## 14. Berørte artefakter

- `schema.sql` (+ `db-migrations.sql`): `profiles`, `suggestion`, RPC-funktioner,
  `regen_person_visning`, triggers.
- `db-rls.sql`: `authenticated` read-politikker.
- `mobile/src/lib/`: skrive-lag (port af `redaktion-write.js` → RPC-kald), auth-helpers.
- `mobile/src/store/useStore.ts`: auth + dryRun + showAnnotations.
- Reference (genskabes, kopieres ikke): `design_handoff_redaktion_mobile/`.
