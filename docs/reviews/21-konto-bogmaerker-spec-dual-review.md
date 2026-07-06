# Review 21 — Konto-bogmærker spec (dual-review: Claude + Codex)

**Dato:** 2026-07-06
**Genstand:** `docs/superpowers/specs/2026-07-06-konto-bogmaerker-design.md`
**Type:** SPEC-review (ingen kode implementeret). Read-only.

Codex-trigger (Phase 2 = JA): executable SQL/RLS (data-læk-risiko), cross-platform supabase-js-
kontrakter, empiriske kodebase-claims (person-PK, web/mobil auth-infra).

---

## Phase 1 — Claude egne fund

### H1 [HIGH] — `add`-idempotens via upsert m. server-defaultet user_id er skrøbelig
**Lokation:** spec §5 (RemoteRepository.add).
**Symptom:** `add` bruger `upsert({person_id}, {onConflict:'user_id,person_id', ignoreDuplicates})`,
men `user_id` sendes IKKE af klienten (DB-default `auth.uid()`). PostgREST's on-conflict skal kunne
udlede conflict-target fra payload; en defaultet kolonne i conflict-nøglen er en kendt kilde til
uforudsigelig adfærd.
**Konsekvens:** gentaget "gem" kan fejle (23505 bobler op) eller upsert opføre sig uventet.
**Foreslået fix:** ren `insert({person_id})` og behandl `unique_violation` (23505) som succes
(idempotent). Enklere og uafhængig af defaultet-kolonne-i-conflict-nøgle-semantik.

### H2 [HIGH] — hent-ved-fokus kan overskrive igangværende optimistisk toggle
**Lokation:** spec §5 (hook: hent-ved-fokus + optimistisk toggle).
**Symptom:** en `list()`-refetch ved fokus kan resolve MENS en optimistisk `add`/`remove` endnu
ikke er committet server-side → refetch returnerer den gamle liste og klobber den optimistiske
tilstand.
**Konsekvens:** tabt/genopstået bogmærke, flimmer (samme async-race-klasse som dual-review 20 BM1).
**Foreslået fix:** en write-generation/in-flight-guard — spring refetch-resultat over hvis der er
en igangværende skrivning, eller flet server-listen med kendte pending-mutationer.

### M1 [MEDIUM] — samspil med person-sletning (FK-ordning)
**Lokation:** spec §4.1 (`person_id ... ON DELETE CASCADE`).
**Symptom:** projektet har en FK-ordnet person-hard-delete (`red_slet_person`, memory
`fk-ordning-evidens-slet`) fordi nogle person-FK'er er non-cascade. Ny bookmark-FK ER cascade.
**Konsekvens:** sandsynligvis uproblematisk (auto-ryddes), men bør verificeres at `red_slet_person`
ikke rammer en ny blokering eller kræver eksplicit oprydning.
**Foreslået fix:** bekræft mod `red_slet_person`-definitionen; dokumentér at cascade dækker.

### M2 [MEDIUM] — web-læser-login interagerer med eksisterende "mig"-feature
**Lokation:** spec §6.
**Symptom:** `Folgesvend.tsx` har allerede en localStorage-"mig" med kommentar "flyttes til
profiles.reventlow_person_id ved login". Ny login-flade i læseren berører samme område.
**Konsekvens:** risiko for dobbelt-login-koncept eller uklar interaktion.
**Foreslået fix:** genbrug ét session-koncept; afklar at "mig" og bogmærker deler samme session.

### L1 [LOW] — bogmærket utilgængelig person forsvinder tavst
**Lokation:** spec §7 (Bogmærker-liste mapper person_id → model.byId).
**Symptom:** hvis en bogmærket person bliver privat/utilgængelig (RLS), findes den ikke i modellen
→ bogmærket filtreres tavst væk fra listen (row eksisterer stadig i DB).
**Konsekvens:** acceptabel graceful degradation; noteres for bevidsthed.
**Foreslået fix:** ingen (bevidst). Evt. en "utilgængelig"-placeholder senere.

---

## Phase 3+4 — Codex adversarial-review + reconcile (2026-07-06)

**Verdict:** needs-attention → alle fund adresseret i spec v2. Codex kørte read-only mod repo'et;
hvert fund reproduceret uafhængigt (ingen peer-review-laundering).

### Claude-fund revurderet af Codex
| ID | Codex-verdikt | Reproduktion (verified) | Konsekvens |
|---|---|---|---|
| H1 (upsert-idempotens) | **dismissed** | PG anvender omittede-kolonne-defaults FØR conflict-detektion; conflict-target behøver ikke være i payload (postgrest-js + PG-docs) | Behold `upsert`; tilføj integration-test for dup-insert m. defaultet uid |
| H2 (fokus-fetch vs optimistisk) | **confirmed** | mobil-hook hydrerer kun én gang (bookmarks.ts:85); web sync (bookmarks.ts:79) → remote fetch-ved-fokus er NY concurrency | Tilføj write-generation/pending-guard |
| M1 (person-slet FK-ordning) | **dismissed** | `red_slet_person` rydder non-cascade-deps, derefter `DELETE person` → bookmark-cascade auto-ryddes (schema.sql:810,824) | Behold cascade; test via `red_slet_person` |
| M2 (web meId vs login) | **confirmed** | Folgesvend meId (localStorage, Folgesvend.tsx:92) vs. persisteret Supabase-session (auth.ts:29) | Spec skal sige: én delt session; meId-migration eksplicit udskudt |
| L1 (utilgængelig person filtreres) | **confirmed** | bookmarks.ts:107 dropper id'er uden `model.byId`; auth-RLS skjuler private (db-rls.sql:365) | Dokumentér + test tavs filtrering |

### Nye Codex-fund (verified empirisk)
| ID | Sev | Reproduktion | Fix |
|---|---|---|---|
| **N1** | HIGH | repo GRANTer eksplicit pr. tabel (`grant select on table public.profiles to authenticated`, db-rls.sql:408) FØR RLS; min DDL manglede GRANT/REVOKE. Jf. memory `supabase-revoke-from-public-insufficient` (anon har direkte default-grants) | Tilføj `GRANT SELECT,INSERT,DELETE ON bookmark TO authenticated` + `REVOKE ALL ON bookmark FROM anon, PUBLIC` |
| **N2** | MED | `person.id` bigint (schema.sql:122); kanonisk id = numerisk PK-streng; `Number()` korrumperer > 2^53 | Send `person_id` som decimal-STRENG til PostgREST (ingen `Number()`) |
| **N3** | MED | repo-idempotens = `IF NOT EXISTS` (db-migrations.sql) + `DROP POLICY IF EXISTS` (db-rls.sql:536); min DDL var plain CREATE | Idempotent DDL (IF NOT EXISTS + drop-før-create policy/grant) |
| **N4** | MED | mobil `supabase` er `null` uden env (`supabaseEnabled`, supabase.ts:22) | Null-klient → `canSave:false` + tom liste (ingen crash) |
| **N5** | MED | bogmærke = konto-koblet adfærdsdata om (evt. levende) person (db-rls.sql:350,365) | Tilføj bogmærker til privacy/erasure-kontrakten (retention/eksport/konto-sletning) |

**RLS bekræftet korrekt (når grants tilføjes):** own-row-isolation, anon fejler lukket (ingen policy),
`DEFAULT auth.uid()` evaluerer ved insert, ingen UPDATE-policy nødvendig (kun insert/delete).

### Impact-bucketing
- **Silent-corruption/race:** H2 (fokus-fetch klobrer optimistisk skrivning), N2 (bigint-trunkering > 2^53).
- **Sikkerhed/hærdning:** N1 (eksplicit grant/revoke — data-API-privilegier), N5 (GDPR-erasure).
- **Robusthed/proces:** N3 (idempotent DDL), N4 (null-klient), L1 (tavs filtrering).
- **Scope/afklaring:** M2 (delt session + udskudt meId-migration).
- **Afkræftet (ingen ændring):** H1 (upsert virker), M1 (cascade dækker).

**Læring:** ved en ny Supabase-tabel er RLS ikke nok — repo-konventionen (og
`supabase-revoke-from-public-insufficient`) kræver eksplicit `GRANT ... TO authenticated` +
`REVOKE ... FROM anon`, fordi Supabase auto-grant'er default-privilegier til anon/authenticated.

