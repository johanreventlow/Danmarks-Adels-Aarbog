# Review: medie-metadata spec + plan (dual-review 2026-08-06)

**Objekter:** `docs/superpowers/specs/2026-08-06-medie-metadata-design.md` +
`docs/superpowers/plans/2026-08-06-medie-metadata.md` (dokument-review før implementering).
**Proces:** Claude Phase 1-verifikation → Codex adversarial (gpt-5.6-sol) → reconcile.

## H1 [HIGH] — Plan Task 2: manglende status-filter viser tilbagetrukne fakta

**Lokation:** plan Task 2 (fetchMediaFakta-læse-mønster); schema.sql:1379-1380
**Symptom:** `red_tilbagetraek_fakta` sætter KUN `conclusion.status='tilbagetrukket'` — den
beholder `valgt_assertion_id`. Planens conclusion-select (kopieret fra `fetchPersonEvidence`,
redaktionRead.ts:139-140) filtrerer ikke på status.
**Verifikation:**
```sql
UPDATE conclusion SET status='tilbagetrukket', blaastemplet_naar=current_date
  WHERE target_type='fact' AND target_id=p_fact_id AND status='afklaret';
```
**Konsekvens:** Et fjernet felt (Fjern-knappen, Task 4/5) ville fortsat blive vist i både
redaktør-præudfyld og læser-Lightbox — fjernelse ser ud til at virke men gør det ikke.
**Foreslået fix:** `fetchMediaFakta`-conclusion-select tilføjer `.eq('status','afklaret')` +
join-test der viser at tilbagetrukket fakt udelades. Status: verified (kodecitat).

## H2 [HIGH] — Spec §3/§4: RLS-antagelsen om upublicerede medier er forkert

**Lokation:** spec §3 ("bør være anon-læsbare for publicerede medier") + §4 (test: "kan IKKE
for et ikke-publiceret"); db-rls.sql:77-89 + 329-331
**Symptom:** `fact`-anon-politikken bruger `entitet_offentlig(subjekt_type, subjekt_id)`, og
`entitet_offentlig('media', …)` returnerer **altid true** (media er i det faste ikke-PII-sæt) —
den konsulterer IKKE `media_rettigheder_ok`.
**Verifikation:**
```sql
when p_type in ('place','estate','coat_of_arms','lineage','organisation',
                'historical_event','source','media','repository') then true
```
**Konsekvens:** Anon kan læse fakta (inkl. kommende `beskrivelse`-prosa og `kreditlinje`) på
medier der er upublicerede/spærrede. Spec §4-testforventningen kan ikke opfyldes. Eksponeringen
findes ALLEREDE i dag for licens/kildehenvisning-fakta — udvidelsen hæver blot følsomheden
(fritekst-prosa). Selve billed-bytes forbliver gated (Storage/RLS på media-rækken).
**Foreslået fix (beslutning påkrævet):** (a) acceptér + dokumentér i spec (fakta om medier
betragtes som ikke-følsomme, redaktøren instrueres i ikke at skrive følsom prosa før
publicering), eller (b) skærp `entitet_offentlig` så `media` → `media_rettigheder_ok(p_id)` for
anon — bredere ændring der også påvirker note/text_mention/relation-synlighed på medier og
kræver egen migration + regression. Status: verified (kodecitat).

## Verificerede claims (OK — ingen ændring)

- `red_upsert_fakta`-signatur og args-mapping matcher planen (schema.sql:1148-1152); ingen
  guards der rammer `subjekt_type='media'` (kun `forældrefamilie`-blokering).
- Genopliv-semantik: `red_upsert_fakta`'s conclusion-upsert sætter `status='afklaret'` igen
  (schema.sql:1187-1189) — Fjern→Gem-cyklus virker.
- `trg_conclusion_regen` no-op'er for media-fakta (person-filter, schema.sql:1054-1057) —
  ingen cache-bivirkninger.
- `red_set_media_rettigheder` skriver `licens`/`kildehenvisning`/`gengivelsestilladelse` som
  media-fakta med præcis disse koder (schema.sql:2816-2818) — Task 4's præudfyld-gratis-claim OK.
- Ingen kollisioner: ingen af de 12 koder findes som faktatype-seeds i schema.sql i forvejen.
- Linjenummer-claims i planen (redaktionWrite.ts:39/419-455, Redaktion.tsx:1625-1650,
  MediaDetaljeOverlay.tsx:40+54 write-only) stikprøvet korrekte.

## Codex adversarial-review konsekvens (2026-08-06)

Verdict: **NO-GO som skrevet** — spec §1/§3/§4 + plan Task 2-6 revideres før implementering.
(Første sol-kørsel hang på "Turn started" 27 min → annulleret; genkørsel gennemførte, ~11 min.)

**Bekræftet (verified empirisk i denne reconcile):**
- **MM-01 [BLOCKER]** = H2 ovenfor. Codex bekræftede uafhængigt; assertion/conclusion-politikker
  arver åbenheden. Kræver brugerbeslutning (acceptér+dokumentér vs. skærp `entitet_offentlig`).
- **MM-02 [BLOCKER]** = H1 + mere: verificeret at `red_slet_media` IKKE findes (spec brugte forkert
  navn — funktionerne er `red_fjern_media` (blød) og `red_udrens_media` (hård, schema.sql:3041));
  udrens blokerer på ENHVER media-fact uanset conclusion-status. Fix: status-filter i alle reads +
  spec dokumenterer at tilbagetrukne fact-slots består og blokerer udrens (accepteret friktion i v1).
- **MM-03 [HIGH]** verified: `MediaFakta`-typen (12 koder) dækker ikke `licens` m.fl. → planens
  præudfyld-claim kompilerer ikke; og gensend via `red_set_media_rettigheder` genopretter citation
  som '(kilde mangler)' (schema.sql:1179-1181) — proveniens-degradering. Fix: separat læse-union
  (12 + de 3 rettigheds-koder) + kun ændrede felter gensendes.
- **MM-04 [HIGH]** verified: `mediaMerge.ts` indeholder nul fact-håndtering — blød flet efterlader
  fakta på kopien. Fix: spec dokumenterer livscyklus (v1: fakta bliver på kopien; flet-UI advarer).
- **MM-05 [HIGH]** verified: thumbs renderes via `MediaThumb` i `primitives.tsx` (DetailPanel.tsx:15
  m.fl.), feed har egen `feedMedia.ts`-pipeline, `PresensView` var udeladt. Fix: Task 6 omskrives
  omkring `MediaThumb` + `feedMedia.ts` + `PresensView`; EmbeddedMedia-udeladelse gøres eksplicit i spec.
- **MM-07 [MEDIUM]** verified: kanoniske date_qualifier-værdier er engelske
  ('about','before','after', schema.sql:826) — planens `ca`/`før`/`efter` rettes; `hentedato`-flow
  præciseres (kun `vaerdi` ISO-dato + `p_date_raw`).
- **MM-08 [MEDIUM]** verified: `MEDIA_ARTER` (Redaktion.tsx:647) skal have `mediaFakta`; run-loop
  skal awaites sekventielt; fakta-refetch efter gem/fjern; hente-effekt med cleanup-guard.
- **MM-09 [MEDIUM]** verified: ingen unik constraint på fact-slots + `LIMIT 1` uden ORDER BY i
  `red_upsert_fakta` — eksisterende modelvilkår, noteres i spec (ingen ny dublet-politik i v1).
- **MM-10 [MEDIUM]** verified: `submitChange(c, opts: { dryRun })` kræver opts (redaktionWrite.ts:564)
  — dryRun-regressionstest omskrives til at teste Redaktion-wiring (`run` bruger state-dryRun).
- **MM-11 [MEDIUM]** accepteret: `kilde_url` whitelist-valideres (`https?://`) før skrivning og rendering.

**Recalibreret:**
- **MM-06 [HIGH→note]:** args-mapping korrekt; manglende vocab-/FK-guard i `red_upsert_fakta` er
  eksisterende API-svaghed, ikke dokumentfejl. Mitigeres klient-side (whitelist, eksisterende media-id
  fra overlay-kontekst); DB-hærdning noteres som opfølgnings-kandidat, ikke i denne scope.
- **MM-12 [LOW]:** spec-overdrivelse — overlayet er kun write-only for de fire rettigheds-fritekstfelter
  (titel/slags/kunstner/datering/status præudfyldes allerede). Spec-ordlyd rettes.

**Dismissed:**
- **MM-13:** claims om rettigheds-koder + kollisionsfrihed bekræftet korrekte.

**Impact-buckets (Codex-fund ud over Claudes egne H1/H2):**
- Hard runtime/kompilerings-fejl: 2 (MM-03 type-union, MM-10 umulig test)
- Silent-corruption/semantik: 3 (MM-04 flet-efterladte fakta, MM-07 qualifier-drift, MM-08 manglende refetch/atomicitet)
- Proces/false-confidence: 2 (MM-05 forkerte filer, MM-02-navnefejl)
- Cleanup/notat: 3 (MM-06, MM-09, MM-11, MM-12)

**Læring:** dokument-review FØR implementering fangede 2 BLOCKER + 4 HIGH billigt — men Codex' vigtigste
bidrag var kortlægning af eksisterende kode-realiteter (flet-livscyklus, MediaThumb-struktur,
submitChange-kontrakt) som spec/plan havde antaget sig forbi. Verifikér render-/skrive-stier mod
faktiske call-sites, ikke mod komponentnavne.
