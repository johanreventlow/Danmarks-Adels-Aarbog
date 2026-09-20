# Review: Record-nøglede person-narrativer (#152) — designspec

**Dato:** 2026-08-29
**Reviewet dokument:** `docs/superpowers/specs/2026-08-29-narrative-source-record-key-design.md` (817 linjer, worktree `feat/narrative-record-key-152` @ `055980c`)
**Grundlag:** `schema.sql`, `db-rls.sql`, `db-migrations.sql`, `packages/core`, `web/src/data`, `mobile/src/data`, `load_daa.R` + read-only måling mod prod 2026-08-29.
**Metode:** hver empirisk påstand i spec'en efterprøvet mod kode/skema/prod. Labels: `verified` (reproduceret) / `inferred` (plausibelt, ikke reproduceret).

## Verdict: needs-attention

Designet er solidt og internt konsistent; retningen (privat sidecar, append-only
eventlog, `(source_id, record_key)`-locator, `public_ref`, hash-låste baselines)
holder mod skemaet. To fund (H1, H2) bør adresseres i teksten, før spec'en
godkendes som implementeringskontrakt — ikke fordi designet er forkert, men fordi
det ikke siger, hvad cutover'en *koster i praksis* for redaktionen.

## Målt prod-tilstand (2026-08-29, read-only)

| Måling | Værdi |
|---|---|
| `source` | 1 = DAA 2018-20 (`aar`=2020), 3 = DAA 1939 (`aar`=1939); begge `aar` udfyldt |
| `narrative_record_publication` | 563 rækker, alle `published`, alle source 3 |
| Ubundne person/DAA-narrativer | source 1: **591** (alle), source 3: 13 |
| Personer med >1 narrativ i samme source | **0** |
| `source_persona_identity` | **8 rækker** (alle `accepted`) |
| `narrative_id_seq` | last_value 1196, is_called=false; `max(narrative.id)`=1195 |
| `haendelse` | 0 rækker |
| Accepterede `source_record_anchor_event` | 897 |

---

## H1 [HIGH] — Ingen narrativ-granulær nedtagningsvej efter cutover (GDPR, invariant 8) — `verified`

**Lokation:** spec §4.4, §6.2 (»Legacy uden binding: Afvis«), §9 fase 3 (`NARRATIVE_RECORD_REQUIRED`).

**Symptom:** Alle 591 narrativer fra 2018-20 — flertallet af de offentlige
biografier — bliver grandfathered legacy og *read-only i den nye flade*. Samtidig
lukkes `red_upsert_narrativ` for person/DAA. Spec'en nævner en append-only
disposition `legacy_withdrawn` (§4.4), men definerer **ingen RPC**, der kan
udføre den, og ingen vej til at sætte `narrative.privat=true` på en legacy-række.

**Konsekvens:** Hvis en 2018-20-biografi skal fjernes eller gøres privat
(samtykke trukket, fejl om levende person), findes der efter cutover ingen
redaktionel handling for det. Eneste håndtag er person-niveau
(`person.privat`/`levende` → hash-drift skjuler rækken), hvilket skjuler *alt*
om personen — for grovt. Perioden varer indtil #153 + #149, dvs. ubestemt.

**Foreslået rettelse:** Gør legacy-dispositionen til en konkret #152-RPC:
`red_tilbagetraek_legacy_narrative(p_narrative_id, p_expected_state_sha256)`
→ `legacy_withdrawn`-event + ledger-disposition `withdrawn`; evt. også en
gated privat-toggle. Tilføj til §6, §6.5 (fejlkoder), §10.1 og §12.

## H2 [HIGH] — Frysning af nye bindinger er ikke udtrykt som konsekvens — `verified`

**Lokation:** spec §5.1, §6.2 (»Ny binding uden entydig accepted identity: Afvis«).

**Symptom:** Der findes **8** `source_persona_identity`-rækker i prod mod 563
bindinger. Spec'en er korrekt i, at C3-bindinger »ikke nødvendigvis« har en
identity-række — men i praksis har *stort set ingen* det. Autoriteten
`existing_exact_binding` er derfor ikke en »kontrolleret legacy-bro« (§5.1);
den er ~100 % af den reelle redigeringsautoritet.

**Konsekvens:** Efter cutover kan redaktøren redigere de 563 eksisterende
1939-bindinger, men kan i praksis **ikke oprette en ny kladde** på nogen record
(hverken ny record i 1939, withdrawn→ny kladde, eller noget i 2018-20, som slet
ingen source_records har), før #151/#149 har fyldt identity-laget. Det gælder
også §5.1's read-kontrakt: redaktøren ser stort set kun allerede bundne records.
Kombineret med H1 betyder det, at redaktionen af person/DAA-narrativer reelt
fryses til »ret eksisterende 1939-tekst«.

**Foreslået rettelse:** Ny sektion (fx §2.7 eller §11) der udtrykkeligt
beskriver den operationelle frysning, dens varighed (indtil #151/#149) og at
projektejeren accepterer den. Overvej om `existing_exact_binding` skal have en
udløbsdato/disposition i #151 (spec'en antyder det, men gør det ikke bindende).

## M1 [MEDIUM] — RLS-scope er selvmodsigende: §7 vs. §7/§10.1 — `verified`

**Lokation:** §7 (»RLS strammes, så *record-bundne* person/DAA-rækker kun er
direkte synlige, når …«) vs. §7 slut (»Nye ubundne rækker er fail-closed
usynlige«) og §10.1 (»nye ubundne narrativer bliver ikke synlige«).

**Symptom:** To forskellige politikker. Læsning A: kun bundne rækker gates i
RLS → nye ubundne rækker er *synlige* via direkte SELECT (modsiger fail-closed).
Læsning B: ubundne ikke-grandfathered rækker skjules også i RLS → rammer alle
direkte narrative-læsere:

- `web/src/data/feedAux.ts:61,64`, `haendelser.ts:55`, `presensLinjer.ts:75`,
  `public.ts:202,278`, `redaktionRead.ts:313`
- `mobile/src/data/load.ts:169`, `about.ts:17`, `haendelser.ts:58`,
  `presensLinjer.ts:114`, `redaktionRead.ts:334,1012`
- `haendelse.auth_read` har `exists (select 1 from narrative …)` (db-rls.sql:518ff)
  → kaskade-skjul (latent: 0 haendelser i dag, men latent ≠ harmløst).

**Loader-vinklen:** `load_daa.R:168` skriver `narrative` direkte. En fremtidig
udgave-import producerer derfor ubundne rækker, som under læsning B er usynlige
og under H2 ikke kan bindes i skala. Spec §3/§9 nævner kun RPC'er og klienter
som »gamle skriveveje« — R-loaderen mangler.

**Foreslået rettelse:** Vælg læsning eksplicit; nævn R-loaderen som skrivevej og
angiv, hvad en ny udgave-import skal gøre (bind via #153-writer, eller
importér som legacy med eksplicit ledger-optagelse).

## M2 [MEDIUM] — §6.4's undo-gate mangler mekanisme — `verified`

**Lokation:** §6.4 (»`red_fortryd_change_set` skal afvise change sets, som
indeholder en `narrative_publication_event`«).

**Symptom:** `red_fortryd_change_set` (schema.sql:6099) itererer kun
`change_event`, som udfyldes af `log_change`-triggere på *public*-tabeller.
`narrative_record_publication` har ingen `log_change`-trigger (kommentar
schema.sql:8573), og den nye private eventtabel får det heller ikke. »Change
set indeholder et publication-event« kan derfor ikke ses i `change_event`.

**Foreslået rettelse:** Angiv mekanismen: `EXISTS (SELECT 1 FROM
private.narrative_publication_event WHERE change_set_id = p_change_set_id)` som
første check i `red_fortryd_change_set`, og en læse-RPC/felt der giver
webhistorikken `change_set_id → event_id`, så den kan rute til den dedikerede
reversal (§6.4 sidste sætning forudsætter mappingen uden at levere den).

## M3 [MEDIUM] — Identity-sekvensen skal resynkes ved cutover — `verified`

**Lokation:** §6.2 (»Insert bruger narrative-tabellens identity-default; den
gamle `max(id)+1`-allokering videreføres ikke«).

**Symptom:** Den gamle writer indsætter med eksplicit `max(id)+1`
(schema.sql:3955) og rykker ikke sekvensen. I dag: seq=1196/not-called,
max=1195 (ok, fordi `db-migrations.sql:28` satte den). Ét gammelt writer-kald
mellem nu og cutover giver id 1196 → den nye writers første identity-insert
kolliderer med `duplicate key`.

**Foreslået rettelse:** Én linje i fase 3-transaktionen:
`setval(pg_get_serial_sequence('public.narrative','id'), max(id)+1, false)`.

## L1 [LOW] — »primary persona« / »accepted-primary-identity« er ikke et skema-begreb — `verified`

Skemaet har `source_persona_placement.placement_role IN
('principal_member','co_principal','mentioned_spouse','child_reference')`
(schema.sql:1648). Spec'en bruger »primary« uden definition. Afklar: er det
`principal_member` alene, eller tæller `co_principal` også (ægtefælle-post)?
Det afgør, om §5.1-kriterium 2 kan give to personer »primary« på samme record.

## L2 [LOW] — Ingen »kassér kladde«-overgang — `inferred`

§6.2/§6.3 har ingen draft→withdrawn-handling; en kladde kan kun fjernes ved
reversal, og reversal kræver »seneste event«, så en kladde med N gemninger skal
reverseres N+1 gange. Enten tilsigtet (så skriv det) eller tilføj
`draft_discarded` som tilladt overgang.

## L3 [LOW] — Reversal-af-reversal er ustpecificeret — `inferred`

§6.4: »eventet er seneste ikke-reverserede event«. Et `reversal`-event er selv
seneste og ikke-reverseret → kan det reverseres (redo)? Sig ja eller nej.

## L4 [LOW] — `source_id DESC` som tie-break er anti-kronologisk i denne base — note

Source 1 = 2018-20, source 3 = 1939. Hvis `aar` var NULL, ville §7's tie-break
vise 1939 før 2018-20. `aar` er udfyldt for begge, så kun en note: overvej
`source_id ASC` eller at kræve `aar NOT NULL` for DAA-sources.

---

## Bekræftet (påstande der holder) — alle `verified`

- §3: `red_upsert_narrativ` bruger `ORDER BY id LIMIT 1` på `(subjekt_type,
  subjekt_id, source_id)` (schema.sql:3951-3953) ✔
- §3: web/mobil skriver på source-niveau — `redaktionWrite.ts` sender kun
  `p_source_id` (web:281, mobil:221, mobil defaulter til source 1) ✔
- §3: klienten sorterer alfabetisk — `buildBioSourceVersions` bruger
  `localeCompare` på `sourceLabel`/`recordLabel` (`packages/core/src/bioVersions.ts:45-47`) ✔
- §3/§8.3: fallback sammenkæder pr. source — `buildBioVersions` joiner
  `texts.join('\n\n')` og `public.ts:229-237` bruger den ved RPC-fejl ✔
- §4.2: invarianten findes — partial unique index
  `narrative_record_publication_active_record_uidx` + trigger med
  source-mismatch/subjekt-check (schema.sql:2295-2320) ✔
- §5.1: C3 skrev bindinger inline uden identity-afgørelse
  (schema.sql:7955-7977) ✔ — og målingen viser, at det gælder næsten alle
- §6.2: `haendelse`-guard har præcedens i `REIMPORT_CASE_HAENDELSE_PRESENT`
  (schema.sql:7882, 8541) ✔
- §7: v1-RPC'en er allerede publication-gated for bundne rækker og viser alle
  ubundne som `legacy_narrative` (schema.sql:3073-3087) ✔
- §9 fase 3: `red_publicer_narrative_record`/`red_tilbagetraek_narrative_record`
  har `GRANT … TO authenticated` (schema.sql:3131) og skal revokes ✔
- Issue #152's oprindelige skitse (»narrativ med `source_record_id` som nøgle«)
  er korrekt markeret som historisk i `docs/decisions.md` ✔
- Record-granulariteten er prospektiv: 0 personer har i dag >1 narrativ i samme
  source; patologien (1017/1021) er merge-i-én-række, ikke to rækker — konsistent
  med issue-teksten ✔

## Ikke kørt

Codex adversarial-pass er **ikke** kørt: spec'en indeholder ingen eksekverbare
opskrifter, og trigger-listen i dual-review-cycle Phase 2 rammes kun på
»severity driver implementation-scope« (H1/H2). Kan køres på forlangende mod
denne fil.
