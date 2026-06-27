# Review 02 — Redaktions-skrive-model + auth

**Område:** evidens-skrive-RPC-lag + RLS + app write-lag (commits `ba2dae2..64a08da`).
**Reviewer:** Claude (Phase 1). Codex adversarial: pending.
**Kontekst:** PoC; blød-mutabel assertion bevidst (spec §2); `max(id)+1`-id-tildeling
bevidst PoC-debt. Live-verificeret mod Supabase-base 2026-06-27 (5/5 RPC-asserts PASS
EFTER fix af FK-bug i `red_slet_oplysning`, allerede committed `64a08da`).

---

## H1 [MEDIUM] — `suggestion`-staging er ulæselig for redaktør → forslag-flow dødt

**Lokation:** `db-rls.sql:238-241`

**Symptom:** `suggestion` har kun ÉN read-politik:
```sql
create policy own_read on public.suggestion for select to authenticated
  using (forslagsstiller = auth.uid());
```
Ingen politik giver rolle `redaktion` adgang til at læse ANDRES forslag.

**Verifikation:** grep af db-rls.sql viser kun `own_read`; `suggestion` indgår ikke i
`auth_read`-tabel-arrayet (kun person/fact/relation/... gør). Verificeret.

**Konsekvens:** Spec §6-flowet er "medlem skriver forslag → redaktør gennemser og
re-anvender manuelt". Men en redaktør kan via PostgREST kun se sine EGNE forslag, ikke
medlemmernes. Staging-køen er dermed reelt uobserverbar for den der skal tømme den.
Skrivning virker (`red_suggest`), men review-loopet er afskåret.

**Foreslået fix:** Tilføj redaktion-read-all-politik:
```sql
create policy redaktion_read_all on public.suggestion for select to authenticated
  using (current_rolle() = 'redaktion');
```
(Postgres OR'er permissive politikker, så `own_read` + denne sameksisterer fint.)

---

## H2 [MEDIUM] — `red_slet_person` efterlader forældreløse evidens-/relations-rækker

**Lokation:** `schema.sql` (`red_slet_person`)

**Symptom:**
```sql
DELETE FROM family_member WHERE person_id = p_person_id;
DELETE FROM person WHERE id = p_person_id;
```
Sletter kun `family_member` + `person`. Personens `fact` (subjekt_id), tilhørende
`assertion`/`conclusion`/`citation`, `relation` (subjekt_id/objekt_id), `narrative`,
`note`, `person_external_id` bevares — nu dinglende mod en ikke-eksisterende person.

**Verifikation:** funktionskroppen læst; ingen cleanup af de polymorfe rækker.

**Konsekvens:** Akkumulerende orphans. RLS skjuler dem (person_offentlig → false når
personen er væk), så de er usynlige men ikke væk — vokser ved hver sletning, og
`fact.subjekt_id`/`relation.objekt_id` kan kollidere hvis `max(id)+1` genbruger en
person-id senere (usandsynligt, men muligt). Bryder også referentiel renlighed for
fremtidig GEDCOM-eksport.

**Foreslået fix:** Slet personens polymorfe spor i FK-sikker rækkefølge før person:
citation→assertion→conclusion (via fact-target), fact, relation (subjekt ELLER objekt),
narrative, note, person_external_id, family_member, person. Alternativt soft-delete
(flag) i stedet for hard-delete i PoC.

---

## H3 [LOW] — authenticated `relation`-politik `using(true)` eksponerer private personers relationer

**Lokation:** `db-rls.sql:205`

**Symptom:**
```sql
create policy auth_read on public.relation for select to authenticated using (true);
```
anon-laget gater `relation` på BÅDE subjekt og objekt (`person_offentlig`); authenticated
gør ikke.

**Verifikation:** grep bekræfter `using (true)`; anon-pendant (db-rls.sql ~122) bruger
`(subjekt_type<>'person' or person_offentlig(subjekt_id)) and (objekt_type<>'person' or
person_offentlig(objekt_id))`.

**Konsekvens:** En manuelt-privat persons relationer (ejerskaber, hverv, afbildninger —
og person↔person-kanter hvis sådanne ligger i `relation`) er læsbare for ethvert
logget-ind medlem. Parallel til den GDPR-fix der allerede blev lavet på
assertion/conclusion/citation (`074c62b`). `family_member` ER gated for authenticated,
så de centrale slægtskaber er dækket — derfor LOW, ikke MEDIUM. Men inkonsistent med
resten af laget.

**Foreslået fix:** Spejl anon-gating for authenticated relation (eller bevidst dokumentér
at relation-data er ikke-følsom og acceptér using(true)).

---

## M1 [LOW] — `regen_person_visning` bruger `max()` pr. faktatype → vilkårligt valg ved flere fakta

**Lokation:** `schema.sql` (`regen_person_visning`)

**Symptom:** `max(a.vaerdi_tekst) FILTER (WHERE f.faktatype='navn')` vælger den
alfabetisk største værdi blandt ALLE navn-konklusioner for personen, ikke en "primær".

**Konsekvens:** Hvis en person har >1 fact af samme faktatype (fx to titel-fakta), bliver
`visning_titel` det alfabetisk-maksimale, ikke det redaktionelt-primære. Lav risiko i PoC
(typisk ét fact/faktatype efter load), men nu load-bearing for cache. Bemærk: dette er en
arvet model-quirk, ikke introduceret her — men forstærket af at RPC'erne nu kan tilføje
flere facts.

**Foreslået fix:** Ved flere facts/faktatype: vælg ud fra en eksplicit primær-markør eller
seneste blaastemplet_naar i stedet for `max(vaerdi_tekst)`. Defer til UI-fase hvis flere-
fakta-pr-type ikke opstår i PoC-data.

---

## M2 [LOW] — `red_edit_oplysning` på dato-fakta opdaterer kun `date_raw`, ikke interval

**Lokation:** `schema.sql` (`red_edit_oplysning`)

**Symptom:** `UPDATE assertion SET vaerdi_tekst=…, date_raw=coalesce(p_date_raw,date_raw)`.
`date_min/date_max/date_qualifier` røres ikke.

**Konsekvens:** Redigeres en fødsels-/dødsdato, driver den strukturerede interval-værdi
væk fra den viste rå-tekst. Fuzzy-dato-søgning (invariant #5) ville bruge forældet
interval. PoC-acceptabelt (rå tekst bevaret, blød-mutabel), men noteret.

**Foreslået fix:** Lad `red_edit_oplysning` tage + sætte interval-felterne, eller re-parse
date_raw → interval ved edit. Defer til strukturerede-dato-fasen.

---

## M3 [INFO/kendt] — `max(id)+1`-id-tildeling i alle INSERT-RPC'er = race + ikke-atomisk pr. tabel

**Lokation:** `red_upsert_fakta`, `red_relation`, `red_upsert_narrativ`, slet-re-peg-INSERT.

**Symptom:** `(SELECT coalesce(max(id),0)+1 FROM <tabel>)` pr. INSERT.

**Konsekvens:** To samtidige redaktører → duplikat-PK-fejl. Bevidst PoC-debt (én redaktør),
dokumenteret i plan + spec. Migrér til IDENTITY/sekvenser ved flerbruger-skrivning.

**Foreslået fix:** (defer) Konvertér PK'er til `GENERATED BY DEFAULT AS IDENTITY` eller
sekvenser; fjern `max(id)+1`.

---

## Codex adversarial-review konsekvens (2026-06-27)

**Verdict: NO-SHIP.** Hver claim reproduceret denne reconcile (empirical-reproduction-rule).

**Bekræftet (verified empirisk):**
- **H1** — grep `db-rls.sql:237-241`: kun `own_read`. Redaktør kan ikke se andres forslag. Codex-fix valid; tilføj `((select current_rolle())='redaktion')` (én eval/statement) + revoke PUBLIC.
- **H2 (RECALIBRERET)** — live-test: `red_slet_person(1)` → `foreign_key_violation` (PASS). Diagnosen "efterlader orphans" var FORKERT: `person_external_id.person_id` + `profiles.reventlow_person_id` + `family_member.person_id` er non-cascade FK'er → funktionen FEJLER for enhver loadet person (alle har external_id), ruller tilbage. Desuden var min cleanup-recipe (citation→assertion→conclusion) **FK-ugyldig** (conclusion.valgt_assertion_id → assertion; samme fælde som `64a08da`). Korrekt orden: conclusions FØR assertions; ryd `profiles.reventlow_person_id`; slet `person_external_id`; evidens for personens facts OG relationer; notes mod person/fact/relation.
- **H3 (BREDERE end dokumenteret)** — læst `db-rls.sql:205-218`: ikke kun `relation using(true)`. Også `narrative` + `note` authenticated-politikker gater KUN eget `privat`-flag, IKKE den refererede person. → en privat persons ikke-flaggede biografi/note/relationer lækker til ethvert logget-ind medlem. assertion/conclusion arver via relation-EXISTS (relation synlig → relation-evidens lækker). `fact`/`family_member`/`person_external_id` ER gated korrekt.
- **NEW (Codex fandt, jeg missede): `red_set_konklusion` silent no-op** — `schema.sql` UPDATE-only: har et fact assertions men ingen conclusion-række (importeret/delvist), opdaterer 0 rækker og void-RPC returnerer success → UI tror konklusion skiftede. Hæv til MEDIUM. Fix: `GET DIAGNOSTICS ROW_COUNT` → RAISE, eller upsert.
- **M2** — bekræftet (date_raw uden interval-opdatering).

**Recalibreret:**
1. **M1**: max()-quirk reel, men `red_upsert_fakta` GENBRUGER slot (find-or-create) → duplikater kræver præ-eksisterende data ELLER concurrent race (ingen `UNIQUE(subjekt_type,subjekt_id,faktatype)` på fact — verificeret). Min "RPC forstærker" overstated. Defer; definér kardinalitet.

**Dismissed:**
- **M3** (max(id)+1): accepteret PoC-debt, ikke ny blocker. Korrekt.

### Impact-buckets (verified)
| Bucket | Fund |
|--------|------|
| **Hard runtime-crash** | H2 (red_slet_person fejler på HVER loadet person) |
| **Sikkerhed / PII-eksponering** | H3 (relation+narrative+note → private personers data til medlemmer) |
| **Silent false-confidence** | red_set_konklusion (falsk success); H1 (staging usynlig for reviewer) |
| **Semantic drift** | M2 (date-interval drift) |
| **Cleanup/defer** | M1 (cache-kardinalitet) |

**Læring:** FK-ordrings-fælden (slet child der refereres af parent-FK) ramte BÅDE den
oprindelige `red_slet_oplysning` OG min H2-fix-recipe. Mønster: ved enhver hard-delete af
en evidens-/person-række, kortlæg ALLE indkommende FK'er (conclusion→assertion,
person_external_id/profiles/family_member→person) og slet/ryd dem først. Encode i
fremtidige slet-RPC'er.

---

## Allerede løst (denne session, før dette review)

- **FK-bug i `red_slet_oplysning`** (commit `64a08da`): slettede assertion før konklusion-
  re-peg → `conclusion_valgt_assertion_id_fkey`-brud. Fanget i live-verifikation, rettet
  (re-peg før delete) + deployet + bekræftet. Ikke et åbent fund.
- **GDPR using(true) på assertion/conclusion/citation** (commit `074c62b`): EXISTS-gated.
- **RLS ej slået til på lineage/profiles/suggestion ved oprettelse** (`1dc7e68`,`7de8030`).
