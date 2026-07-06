# Konto-bogmærker — login-eksklusive, cross-device-synkroniserede bogmærker

**Dato:** 2026-07-06
**Mål:** Gør bogmærker til et **login-eksklusivt gode** lagret i Supabase, så de følger brugeren
på tværs af enheder (web + mobil). Erstatter den nuværende lokale (AsyncStorage/localStorage)
bogmærke-lagring.

---

## 1. Baggrund & beslutninger

Bogmærker blev netop shippet som en lokal PoC (person-kun): mobil `lib/bookmarks.ts`
(AsyncStorage), web `data/bookmarks.ts` (localStorage). Denne feature opgraderer dem til
konto-bundne, synkroniserede bogmærker.

**Beslutninger truffet i brainstorm (2026-07-06):**
- **Login-eksklusivt** (ikke hybrid): bogmærker kræver login → cloud-only → cross-device gratis.
  Ingen merge-logik, intet dobbelt lokal/remote-backend.
- **Begge platforme** (web + mobil) samtidig, delt DB-tabel + RLS.
- **Hent-ved-fokus + optimistiske skrivninger** (ingen realtime-subscription).
- **Udlogget: vis gem-ikonet, men tap → "Log ind for at gemme"** (reklamerer godet).
- **Ingen offline-cache** i PoC (bogmærker kræver netværk at se).
- **Kun personer** (uændret scope) — kanoniske person-id'er (samme_som-collapset).

**Migration:** ingen. Den lokale bogmærke-kode er få dage gammel uden reelle brugerdata; den
fjernes og erstattes af Supabase-lagring.

**Ikke i scope:** hybrid/merge, realtime, offline-cache, ikke-person-bogmærker, deling af
bogmærke-lister mellem brugere.

---

## 2. Verificeret kontekst (kode)

- `person.id` er **BIGINT PRIMARY KEY** (`schema.sql`). App'ens kanoniske person-id er en streng
  af dette tal.
- Etableret RLS-mønster (`auth.uid()`), `suggestion`-tabellen er præcedens for bruger-scoped
  skrivning; `profiles` (1:1 med `auth.users`) findes.
- **Mobil auth klar:** `store.session` sættes ved login; Konto-fanen understøtter medlem-login
  (`LoginSheet`, "alle kan logge ind som medlem"). Hook'en læser bare `session`.
- **Web auth-infra findes** (`web/src/data/auth.ts`: `signIn/signOut/currentSession`,
  `web/src/supabase.ts`), men **den offentlige Folgesvend-læser har intet login** (kun
  localStorage-"mig"). Web-skiven skal derfor tilføje en minimal session/login-flade i læseren.

---

## 3. Skæring (5 skiver)

| # | Skive | Filer | Grænse |
|---|---|---|---|
| 1 | DB-lag | `schema.sql`, `db-migrations.sql`, `db-rls.sql`, `db-verify.sql` | `bookmark`-tabel + RLS; lokalt verificeret FØR prod |
| 2 | Remote-lager (mobil) | `mobile/src/lib/bookmarks.ts` (omskrevet) | Supabase-backet repository; auth-gated hook |
| 3 | Remote-lager (web) | `web/src/data/bookmarks.ts` (omskrevet) | Samme repository-kontrakt |
| 4 | Web-login i læseren | `web/src/Folgesvend.tsx` (+ lille login-modal) | Session-state + login-CTA (genbruger `data/auth.ts`) |
| 5 | UX-wiring | mobil forside/bogmaerker/drawer-badge; web BookmarksView/reader | "Log ind for at gemme"-flow; tom-tilstande |

Skive 1 er forudsætning for 2–3. Skive 4 er web-specifik (mobil har login). Skive 5 kobler UX på.

---

## 4. Skive 1 — DB-lag

### 4.1 Tabel + RLS (`schema.sql` + idempotent i `db-migrations.sql`)

Idempotent DDL (repo-konvention: `IF NOT EXISTS` + drop-før-create policy, jf. `db-migrations.sql`
/ `db-rls.sql`; dual-review N3):

```sql
CREATE TABLE IF NOT EXISTS bookmark (
  id        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id   uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
  person_id bigint NOT NULL REFERENCES person(id) ON DELETE CASCADE,
  oprettet  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, person_id)
);
ALTER TABLE bookmark ENABLE ROW LEVEL SECURITY;

-- Data-API-privilegier EKSPLICIT (dual-review N1): Supabase auto-grant'er default-privilegier til
-- anon/authenticated på nye tabeller, så RLS alene er ikke nok — repo GRANTer/REVOKEr eksplicit
-- (jf. db-rls.sql + memory supabase-revoke-from-public-insufficient).
REVOKE ALL ON bookmark FROM anon, PUBLIC;
GRANT SELECT, INSERT, DELETE ON bookmark TO authenticated;

DROP POLICY IF EXISTS bookmark_select_own ON bookmark;
CREATE POLICY bookmark_select_own ON bookmark
  FOR SELECT TO authenticated USING (user_id = auth.uid());
DROP POLICY IF EXISTS bookmark_insert_own ON bookmark;
CREATE POLICY bookmark_insert_own ON bookmark
  FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
DROP POLICY IF EXISTS bookmark_delete_own ON bookmark;
CREATE POLICY bookmark_delete_own ON bookmark
  FOR DELETE TO authenticated USING (user_id = auth.uid());
```

- `user_id DEFAULT auth.uid()` → klienten sender kun `person_id`; `WITH CHECK` forhindrer at
  skrive i andres navn. `DEFAULT auth.uid()` evaluerer ved insert under den authenticated request
  (dual-review-bekræftet).
- `person_id` = kanonisk person-PK. `ON DELETE CASCADE` (person eller bruger slettet → bogmærke
  ryddes; `red_slet_person`'s cascade dækker — dual-review M1). `UNIQUE (user_id, person_id)` gør
  "gem" idempotent (upsert on-conflict-do-nothing — dual-review H1 bekræftede at upsert virker med
  defaultet user_id).
- **Ingen RPC** — direkte tabel-adgang gated af RLS + eksplicitte grants (Supabase-idiomatisk for
  ren bruger-ejet tabel; `red_*`-RPC'er er forbeholdt evidens-modellen).
- **Anon-rolle: revoke + INGEN policy** → udloggede kan hverken læse eller skrive (fejler lukket).

### 4.2 Verifikation (`db-verify.sql`)

- Bruger A's `SELECT` ser ikke bruger B's rækker (RLS-isolation).
- `INSERT` med fremmed `user_id` afvises (`WITH CHECK`).
- Dobbelt-insert af `(user_id, person_id)` = no-op (upsert on-conflict-ignore; verificér defaultet
  `user_id` fungerer i conflict-nøglen — dual-review H1).
- Sletning via **`red_slet_person`** (ikke kun rå `DELETE person`) cascader bogmærket væk (dual-review M1).
- Anon (`SET ROLE anon`) kan hverken læse eller skrive — både pga. manglende policy OG `REVOKE`
  (dual-review N1; verificér begge lag).

Køres **lokalt mod en prod-kopi FØR prod** (lokal testbase-praksis). Prod-anvendelse er
bruger-gated; `get_advisors(security)` køres efter DDL.

---

## 5. Skive 2+3 — Remote-lager (mobil + web)

Begge platforme deler samme kontrakt (spejlet, som `collapseSameAs`/`buildBidirectionalColumns`):

```ts
export interface BookmarkRepository {
  list(): Promise<string[]>;          // kanoniske person-id'er (streng), nyeste-først
  add(personId: string): Promise<void>;
  remove(personId: string): Promise<void>;
}
```

**`RemoteRepository`** (én pr. platform, bruger platformens supabase-klient —
mobil `lib/supabase.ts`, web `supabase.ts`). **`person_id` sendes som decimal-STRENG** (ikke
`Number()`) — `person.id` er bigint, og `Number()` korrumperer værdier > 2^53−1; PostgREST
accepterer strengen for en bigint-kolonne (dual-review N2):
- `list()` → `supabase.from('bookmark').select('person_id').order('oprettet', {ascending:false})`
  → `rows.map(r => String(r.person_id))`.
- `add(id)` → `supabase.from('bookmark').upsert({ person_id: id }, { onConflict: 'user_id,person_id', ignoreDuplicates: true })` (id = streng; user_id defaultes i DB).
- `remove(id)` → `supabase.from('bookmark').delete().eq('person_id', id)` (RLS begrænser til egne).
- Fejl logges men crasher ikke UI (bogmærker er ikke-kritiske).
- **Null-klient (dual-review N4):** mobil `supabase` er `null` når env mangler (offline-seed). Repo'et
  returnerer da tom liste + no-op writes, og hook'en rapporterer `canSave:false` (ingen crash).

**`useBookmarks(session, canon)`** (auth-gated hook, spejlet begge platforme) returnerer
`{ ids: Set<string>; has(id): boolean; canSave: boolean; toggle(id): void }`:
- `session == null` → `ids` tom, `has` altid `false`, `canSave: false`, `toggle` er en no-op
  (UI'et gater FØR toggle, se §7 — navigation holdes ude af hook'en).
- `session != null` → henter `list()` ved mount + ved fokus (mobil: `useFocusEffect`; web:
  `visibilitychange`/route-fokus). `canSave: true`. `toggle(id)` opdaterer `ids` optimistisk +
  kalder `add`/`remove`; ved fejl rulles optimistisk tilstand tilbage. Id'er kanonicaliseres
  gennem `canon`.
- **Race-guard (dual-review H2):** en fokus-`list()`-refetch må IKKE overskrive en igangværende
  optimistisk skrivning. Hold en `pendingWrites`-mængde (id'er med in-flight add/remove); når et
  refetch-resultat ankommer, flettes det med `pendingWrites` (behold den optimistiske tilstand for
  pending-id'er) — eller spring refetch over mens der er in-flight writes. Ellers kan en langsom
  refetch genskabe et netop-slettet bogmærke (samme klasse som dual-review 20 BM1).

Kaldstedet gater selv: `onPressSave = () => canSave ? toggle(id) : onRequireLogin()`, hvor
`onRequireLogin` er UI-lokalt (mobil → åbn Konto/`LoginSheet`; web → åbn login-modal).

Det tidligere `nextBookmarks`/`canonicalize`/`sameOrder`-rene helpers genbruges hvor de passer;
det lokale `createLocalBookmarkStore` + AsyncStorage/localStorage-adgang **fjernes**.

---

## 6. Skive 4 — Web-login i den offentlige læser

Folgesvend-læseren (`web/src/Folgesvend.tsx`) mangler login. Tilføj minimalt (genbrug
`web/src/data/auth.ts`):
- Session-state: `currentSession()` ved mount + `supabase.auth.onAuthStateChange`.
- Login-CTA i sidebar/header (fx ved slægt-chippen eller bmQuick) → en lille login-modal
  (e-mail/adgangskode via `signIn`) + log-ud.
- Session gives til `useBookmarks`.

Mobil kræver ingen ny login-flade (Konto-fanen findes); hook'en læser `store.session`, og
`onRequireLogin` ruter til Konto/`LoginSheet`.

**Delt session + "mig"-interaktion (dual-review M2):** web + mobil bruger ÉN Supabase-auth-session
(`supabase.auth` persisterer JWT). Bogmærke-login og den eksisterende localStorage-"mig" i
`Folgesvend.tsx` deler dermed samme session. Denne feature **flytter IKKE** "mig" til
`profiles.reventlow_person_id` — den migration forbliver eksplicit udskudt (uændret adfærd); vi
tilføjer kun session-*bevidsthed* + login-CTA i læseren, ikke en ændring af "mig"-lagringen.

---

## 7. Skive 5 — UX-wiring

- **Gem-ikon (feed-kort + persondetalje):** renderes altid. Logget-ind → toggler. Udlogget → tap
  viser "Log ind for at gemme" og ruter til login. `canSave` fra hook'en styrer adfærden.
- **Top-bar-badge (mobil):** viser antal når logget-ind; udlogget → ingen badge.
- **Bogmærker-skærm / BookmarksView:** logget-ind → liste (som nu). Udlogget → tom-tilstand
  "Log ind for at samle dine bogmærker på tværs af dine enheder" + login-CTA.
- **Tavs filtrering (dual-review L1, bevidst):** hvis en bogmærket person er utilgængelig (privat/
  RLS-skjult), findes den ikke i `model.byId` → bogmærket udelades tavst fra listen (DB-rækken
  består). Acceptabel graceful degradation; dækkes af en test så adfærden er dokumenteret, ikke tilfældig.

---

## 8. Test

- **DB:** `db-verify.sql` (§4.2), lokalt mod prod-kopi.
- **Repository:** mock supabase-klient (jest) → `list/add/remove` sender rette queries + `person_id`
  sendes som **streng** (ikke `Number()`, N2); **null-klient** → tom liste/no-op (N4).
- **Hook:** udlogget (`canSave=false`, `toggle`→`onRequireLogin`, tom liste); logget-ind
  (optimistisk toggle, rollback ved fejl, hent-ved-fokus); **race-guard** — refetch under in-flight
  write klobrer ikke optimistisk tilstand (H2); **tavs filtrering** af utilgængelig person (L1).
- `tsc` + eslint + hele jest-suiten (mobil + web) grøn.
- Empirisk: iOS-sim (mobil) + browser (web) mod prod — gem på én "enhed", se på en anden
  (samme konto); udlogget-prompt.

---

## 9. Risici & modforanstaltninger

- **Web mangler login i læseren** → største nye stykke; afgrænset til at genbruge eksisterende
  `data/auth.ts` + en lille modal. Ingen ny auth-mekanik.
- **RLS-fejl = data-læk mellem brugere** → `db-verify.sql` tester isolation eksplicit +
  `get_advisors` efter DDL; anon fejler lukket (ingen policy).
- **person_id-type (bigint) vs. app-streng-id** → repository konverterer eksplicit (`Number`/
  `String`); kanoniske id'er sikrer at samme_som-collapsede personer bogmærkes konsistent.
- **Optimistisk toggle + netværksfejl** → rollback af lokal state ved fejl (ingen tavs divergens).
- **GDPR — bogmærke er konto-koblet adfærdsdata (dual-review N5):** en `bookmark`-række knytter en
  bruger til en (evt. levende) person. Sletning dækkes af cascade (`user_id`/`person_id` ON DELETE
  CASCADE), MEN bogmærker skal med i projektets privacy/erasure-kontrakt: ved **konto-sletning**
  fjernes brugerens bogmærker (auth.users-cascade), og ved en data-eksport/indsigt bør en brugers
  bogmærker inkluderes. Dokumentér dette i GDPR-noterne (invariant §8); ingen ny mekanik kræves nu,
  men kontrakten skal nævne bogmærke-tabellen eksplicit.

## 10. Succeskriterier

- `bookmark`-tabel + RLS live i prod (bruger-godkendt), `db-verify` grøn, advisor-ren.
- Login-eksklusive bogmærker virker på web + mobil; cross-device bekræftet empirisk.
- Udlogget: gem-ikon → login-prompt; tom-tilstand m. CTA.
- Den lokale bogmærke-kode fjernet; `tsc`/eslint/jest grøn på begge platforme.
