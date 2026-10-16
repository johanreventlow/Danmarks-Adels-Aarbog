# Trin 5b del 2a — bind de afgjorte ægteskaber og forældre, og vis kilden for læseren (#151)

**Status:** **GODKENDT af projektejeren 2026-10-11** (brainstorm samme dato; design godkendt afsnit for
afsnit). Revideret samme dag efter Codex `gpt-5.6-sol` runde 1 (NO-GO: 3 BLOCKER, 8 MAJOR, 1 MINOR, se §12) og
runde 2 (NO-GO: 0 BLOCKER, 8 MAJOR, 1 MINOR, se §13) — alle fund efterprøvet mod koden og godtaget — og to projektejervalg ved planlægningen: klausul-dispositionen
flyttes til 2b, og webbeviset er SQL som `anon` plus en UI-test med syntetiske svar (§10).

**Roadmap:** trin 5, delspec 5b (`docs/superpowers/specs/2026-10-06-trin5b-relationspersonas-design.md`,
herefter »hovedspecen«), del 2, skive a. Bygger på 5b del 1 (merget #237). Del 1's bevisrapport
`docs/evidensbaseret-genimport/relationspersonas-5b-del1-bevis.md` er fastlåst som commit
`8aeb7ebf6c309d7420f554813eb7b20ef4b183e0` (draft-PR #238), filens SHA-256
`4ca5f0ccd4e86b4a3ba21ff235fa4212f319252f8e230329db3aea06fa054752`; tallene i §3 er målt i samme bevisbase. Beslutninger: `docs/decisions.md`
2026-10-06, 2026-10-10 og 2026-10-11 (denne skive).

## 1. Adgangskrav (roadmap)

| Krav | Svar |
| --- | --- |
| Roadmapmål | Trin 5 (#151, med #150's familiedel) |
| Værdikædeled | Afgørelse → dokumenteret binding → læserens kildevisning (relationer) |
| Leverancetype | Generel motor: `structural_family`-regler, relationsafgørelse, relations-promotion og en offentlig læsefunktion for familiers kilder. Intet udgavespecifikt |
| Redaktionel/læserrettet værdi | Læseren ser for første gang en kilde på et ægteskab og en forældrelinje: »Kilde: DAA 2018-20 · ‹post›«. Redaktøren får ægteskaberne afgjort uden ark |
| Færdigbevis | §7: 203 ægteskaber afgjort og 210 relationer bundet i en kopi af del 1's bevisbase, bundet til eksakte id-sæt; 0 kanonisk delta; læsefunktionen som `anon`; negativtests; UI-test i CI |
| Erstatter | Den gamle loaders ukildebundne `family_member`-rækker som eneste spor af ægteskaber og forældre; for de 179 med en vielse-påstand erstattes loaderens citat ikke, men suppleres af en binding til den aktuelle source record |

## 2. Del 2 i tre skiver

Del 2 (hovedspecen §8, §23.5, del 1-bevisets »Til del 2«) skæres i tre skiver, der specificeres, planlægges
og merges hver for sig:

- **2a (denne spec):** bind det, der allerede er afgjort eller kan afgøres maskinelt, og vis kilden.
- **2b:** de uafklarede — 31 identitets-uoverensstemmelser i webkøen med årsag (§23.5), nye personer
  (§8.4, herunder `family.id`-driften i errata §22.3), udtrækkets »(F.: …)«-fejllæsning, ægtefællers år
  (§22.7), de tre ordinal-klassifikationer fra 2a, final reviews M1-M3 og M5-M10 samt
  **klausul-dispositionen** `relation_disposition` (hovedspecen §8.2 og receipt-kontrakten med slutværdien
  `fortolkning_foreslaaet`, uændret).
- **2c:** børn (`relation.child`) med eget kortdesign, hvor kandidaten er barnet (§22.9).

Parkeret som åbne punkter (kræver hver sin projektejerbeslutning): familiekorrektion for `F`-kortet (1) og
`samme_som` for dubletten fra del 1's arkevidens (1).

## 3. Udgangspunkt (målt 2026-10-11 i `daa5b_bevis_20261010093638`, læse-kun)

| | |
| --- | --- |
| `relation.marriage` | 248 gældende: **203** med begge parter `accepted` og præcis én kanonisk familie med begge som partnere (203 forskellige familier); 31 med ægtefællen uafgjort; 14 uden persona |
| Ægteskabsnummer | 200 af 203 har bogens nummer = familiens ordinal; **3** afviger, hver hos en hovedperson med kun én familie (hovedspecen §6.2's kerne ignorerer ordinal ved én familie, M9) |
| `relation.parent` | 7 `accepted` (del 1's `A`-kort), 2 `proposed`, 1 `rejected`. Alle 7 er egnede: principal og forælder har `accepted` identitet, præcis én familie med principal som `barn` og forælderen som partner, 0 `omstridt` |
| `relation.child` | 14 `proposed` (2c) |
| Loaderens vielse-fakta | 179 af de 203 familier har en vielse-assertion med citation fra kilde 1 (uden side); 24 har ingen |
| Eksisterende bindinger | 0 `interpretation_promotion` med `target_type='family'`; reglerne er kun `person-*-v1` |
| Levende | 0 af familierne bag de 210 har et levende medlem |
| Publicering | Alle 210 påstande ligger i source records med `narrative_record_publication.status='published'`; 0 source records har mere end én publiceret binding; narrativ-record-kontrakten er 2 |
| Dispositioner | 390 klausuler i kilde 1 har den maskinelle `afventer_identitet`; højst 18 kunne disponeres efter 2a, fordi 382 også citerer andre uafgjorte påstande — derfor 2b |

## 4. Data: regler, afgørelse, binding

### 4.1 `structural_family`-regeltypen (hovedspecen §8.1)

`private.interpretation_promotion_rule` har i dag hårde CHECKs og `expected_fact_type NOT NULL`. Ændringen:

- Ny kolonne `rule_mode text NOT NULL DEFAULT 'text_assertion'` ∈ `text_assertion` | `structural_family`.
- `ALTER COLUMN expected_fact_type DROP NOT NULL`.
- De fire CHECKs (målt i den opgraderede bevisbase: `interpretation_promotion_rule_interpretation_kind_check`,
  `…_target_type_check`, `…_expected_fact_type_check`, `…_value_kind_check`) droppes og erstattes af én
  CHECK `interpretation_promotion_rule_mode_check`: `text_assertion` bevarer dagens krav uændret;
  `structural_family` kræver `interpretation_kind='relation'`, `target_type='family'`,
  `expected_fact_type IS NULL`, `value_kind='relation'`.
- **Begge validatorer** udvides: triggerfunktionen `private.validate_interpretation_promotion_rule_predicate`
  og `private.add_interpretation_promotion_rule_version` accepterer `value_kind='relation'` kun for
  `structural_family`. Versionsfunktionen får `p_rule_mode` som sidste parameter (ny signatur); den gamle
  overload droppes i migrationen, og revokes/ACL-lister opdateres.
- `private.interpretation_promotion_rule_current` genskabes, så `rule_mode` er med, og
  `private.interpretation_predicate_promotable` filtrerer `rule_mode='text_assertion'`, så
  assertion-vejen (`red_preview_interpretation_promotions`/`red_promote_interpretations_batch`) aldrig ser
  relationsregler. Den eksisterende preview joiner desuden på `target_type`, så et familie-element ikke
  kan matche en assertion-regel.
- Regellinjer og første versioner: `relation-marriage-v1` (`relation.marriage`) og `relation-parent-v1`
  (`relation.parent`), indsat før enhver binding (fremmednøglen `interpretation_promotion_rule_fk`).
  `relation-child-v1` oprettes i 2c.
- `db-migrations.sql` er idempotent (`ADD COLUMN IF NOT EXISTS`, `DROP CONSTRAINT IF EXISTS`,
  `DROP NOT NULL` er idempotent); `schema.sql` på linje.

### 4.2 Bindingens tilstand

Én privat funktion definerer, hvad en relation »er« i øjeblikket, og bruges af afgørelse, binding og
læsning, så de tre aldrig kan være uenige:

`private.relation_binding_state(p_interpretation_id uuid) RETURNS jsonb` — `NULL`, hvis strukturen ikke er
entydig; ellers et kanonisk objekt med `contract: 'relation-binding-state-v1'` og:

- fortolkningen: `interpretation_id`, `interpretation_key`, `version`, `status`, `predicate`, `source_id`;
- (reglen indgår **ikke**: bindingen gemmer selv sin `rule_key`/`rule_version`, så en ny eller pensioneret
  regelversion hverken skjuler en eksisterende kilde eller kræver ombinding — reviewfund r2-M3);
- de gældende parter (`party_role`, `version`, `source_persona_id`) og for hver persona den gældende
  identitet (`version`, `decision_status`, `canonical_person_id`);
- strukturen: den ene familie og kun de `family_member`-rækker, der bærer relationen — ved ægteskab de to
  partneres rækker (`person_id`, `rolle`, `ordinal`, `konfidens`), ved forælder principalens `barn`-række og
  forælderens partnerrække. Andre medlemmer (fx børn, der tilføjes i 2b/2c) indgår ikke, så nye børn ikke
  ugyldiggør et ægteskabs kilde;
- ved ægteskab bogens nummer (`book_ordinal` fra spouse-parten) og familiens (`family_ordinal` fra
  principalens partnerrække).

Entydig struktur: begge parters identiteter `accepted`; præcis én familie med strukturen (ægteskab: begge
som partnere; forælder: principal som `barn`, forælderen som partner); ingen af de bærende rækker har
`konfidens='omstridt'`. Alle sorteringer `COLLATE "C"`; hash via `private.reimport_canonical_json_sha256`.

### 4.3 Maskinel afgørelse af ægteskaber (hovedspecen §8.2 som ændret af §23.5)

Kun `relation.marriage`. De 7 forældre er allerede afgjort af projektejeren i del 1 og bindes blot (§4.4).

- **`red_preview_relation_decisions(p_source_id bigint)`** (redaktion) returnerer `{set_sha256, count,
  ordinal_deviations}`. Egnet er en gældende `proposed` `relation.marriage`-påstand i kilden, hvis
  `relation_binding_state` ikke er `NULL` (funktionen gælder for enhver status; tilstanden rummer status, så
  den ændres ved accepten, og bindingen gemmer tilstanden for den accepterede version). `set_sha256` er hashen
  af envelopen `{contract: 'relation-decision-set-v1', database_identity, source_id, items}`, hvor
  `items` er de egnede påstandes tilstande sorteret efter `interpretation_key` plus pr. påstand den
  klassifikation, der vil blive skrevet. `database_identity` er samme JSON-streng som writer-rammens.
- **`red_decide_relation_interpretations(p_source_id bigint, p_expect_set_sha256 text)`** tager den eksklusive
  kildelås (`daa-identity-candidates:<source>`, som `red_corroborate_family_identities`), låser
  fortolkningsrækkerne (sorteret) og familierækkerne gennem `private.lock_family_rows`, genberegner
  envelopen og afviser ved forskel (`RELATION_DECISION_SET_DRIFT`, 0 skrivninger). Hver egnet påstand
  accepteres gennem `red_decide_interpretation` med evidens `{method: 'family-structure-v1', basis:
  'family_structure', family_id, state_sha256}`.
- Ingen kontrolkørsel som betingelse (§23.5 og decisions 2026-10-10).
- **Ordinal-afvigelse:** afviger `book_ordinal` fra `family_ordinal`, accepteres påstanden alligevel
  (familien er entydig), og klassifikationen `ordinal_afvigelse` skrives i samme transaktion (§4.5).

### 4.4 Binding (hovedspecen §8.1)

- **`red_preview_relation_promotions(p_source_id bigint, p_items jsonb)`** og
  **`red_promote_relation_interpretations_batch(p_source_id bigint, p_items jsonb, p_preview_sha256 text)`**
  efter mønstret i `red_preview_interpretation_promotions`/`red_promote_interpretations_batch`, med fælles
  privat `private.preview_relation_promotions(p_source_id, p_items, p_lock)`. `p_items` er et array af
  `{interpretation_id, family_id}` (det eksplicitte sæt); previewet returnerer pr. element `eligible`,
  `reason_code`, regel og `state_sha256`, og `preview_sha256` = hash af envelopen
  `{contract: 'relation-promotion-preview-v1', database_identity, source_id, items}`.
- Pr. element efterprøves: fortolkningen findes, tilhører kilden og er den gældende version med status
  `accepted`; aktiv `structural_family`-regel; `relation_binding_state` ikke `NULL` og dens familie =
  elementets `family_id`; ikke allerede bundet. Grunde: `RELATION_PROMOTION_NOT_CURRENT`,
  `…_NOT_ACCEPTED`, `…_RULE_NOT_ACTIVE`, `…_STRUCTURE_INVALID`, `…_FAMILY_MISMATCH`, `…_DUPLICATE_ITEM`,
  `…_ALREADY_APPLIED`, `…_SOURCE_MISMATCH`.
- Batchen tager den eksklusive kildelås, låser fortolkningsrækker og familierækker, genberegner previewet
  (`RELATION_PROMOTION_PREVIEW_STALE` ved forskel) og afviser hele batchen ved første ikke-egnede element.
  Kalderen sender derfor kun de elementer, previewet har talt som egnede; previewet tæller de øvrige pr.
  grund.
- **Replay (r2-M4):** findes der allerede en relationsbatch med samme `preview_sha256`, returnerer et kald med
  præcis de samme elementer (samme kanoniske item-digest) den oprindelige batch-id uden at skrive; afviger
  elementerne, fejler kaldet (`RELATION_PROMOTION_REPLAY_MISMATCH`). Batchrækken gemmer derfor item-digesten.
  Et nyt preview efter binding giver `…_ALREADY_APPLIED` for hvert element.
- Skriver én `private.interpretation_promotion` pr. element med `target_type='family'`,
  `target_id=family_id`, `rule_key`/`rule_version`, `batch_id` og evidens `{promotion_kind:
  'structural_family', family_id, vielse_fact_id|null, state_sha256, preview_sha256}`. `vielse_fact_id` er
  familiens vielse-fakt, hvis der er præcis én; ellers `null`. Loaderens vielse-assertion og citation
  røres ikke. `rule_profile_hash` følger den eksisterende beregning med kontrakten
  `relation-promotion-profile-v1`.
- **Højst én familiebinding pr. fortolkning:** partielt unikt indeks
  `interpretation_promotion_one_family_per_interpretation ON private.interpretation_promotion
  (interpretation_id) WHERE target_type='family'`. En ny fortolkningsversion (rettelse) får sin egen binding.
  Fordi reglen ikke indgår i tilstanden (§4.2), kræver en regelændring ingen ombinding; en ombinding af samme
  fortolkningsversion er derfor ikke nødvendig i 2a.
- Bindingen ændrer ingen kanonisk række.

### 4.5 Klassifikationer

Ny append-only tabel `private.relation_classification_event(interpretation_key uuid, seq integer,
interpretation_id uuid NOT NULL REFERENCES private.interpretation(id), interpretation_version integer NOT NULL,
state_sha256 text NOT NULL, classification text CHECK (classification IN ('ordinal_afvigelse')), evidence jsonb
NOT NULL, created_by uuid NOT NULL, created_at timestamptz, PRIMARY KEY (interpretation_key, seq))`; 2b udvider
CHECK'en med sine årsager. **Gældende** er en klassifikation kun, når dens `interpretation_id` er den gældende
version for nøglen, og `state_sha256` er lig den aktuelle `relation_binding_state`-hash; ellers er den
historisk (r2-M2). 2b læser kun gældende klassifikationer. Append-only-triggere for UPDATE/DELETE og TRUNCATE (`private.reject_evidence_mutation`), RLS slået
til, ingen grants til `anon`/`authenticated`, med i `db-rls.sql`'s masterliste og `db-verify.sql`'s asserts.
Eneste skrivevej er `private.append_relation_classification(p_key uuid, p_classification text, p_evidence
jsonb)`, der låser fortolkningsrækken for nøglen før `max(seq)+1`. Forældrekortenes
`identity_control_parent_event` genbruges ikke (bundet til kontrolkørslens kort og `F`/`familie_aendret`).

### 4.6 Hærdning i 2a

Kun M4 (del 1-bevisets »Til del 2« pkt. 8): `db-rls.sql`'s masterliste får `identity_control_exclusion`,
`identity_control_parent_card` og `identity_control_parent_event`. M1-M3 og M5-M10 hører til 2b.

## 5. Læsning: kilden på ægteskab og forælder

### 5.1 `public.public_family_sources(p_family_ids bigint[])`

`LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog`, `REVOKE ALL … FROM
PUBLIC,anon,authenticated,service_role`, `GRANT EXECUTE … TO anon, authenticated`. Under narrativ-record-kontrakt
1 returneres 0 rækker. Returnerer `family_id`, `slags` (`aegteskab` | `foraelder`), `counterpart_person_id`,
`source_record_ref`, `source_label`, `record_label`, `citation_label`. `counterpart_person_id` er den person,
relationen går til (ægtefællen eller den bestemte forælder), så kilden kan vises ved netop den person (r2-M1);
den udleveres kun, når familiegaten holder, og personen er allerede offentlig gennem `family_member`. Ingen
klausultekst, ingen persona- eller påstands-id'er.

**Resolver (fail-closed; enhver manglende eller tvetydig tilstand giver ingen række):**
1. Bindingen: `interpretation_promotion` med `target_type='family'`, `target_id = ANY(p_family_ids)` og
   `rule_mode='structural_family'`.
2. **Gældende tilstand:** fortolkningen er stadig den gældende version for nøglen med status `accepted`, og
   `relation_binding_state(interpretation_id)` giver samme hash som bindingens `state_sha256`. En
   identitetsgenafgørelse, ny partsversion eller ændret struktur skjuler derfor kilden; en regelændring gør
   ikke (§4.2).
3. **Posten:** påstanden har **præcis én** supporting-observation → dens occurrence har **præcis én**
   `source_record_anchor_current`-række med `decision_status='accepted'` → source record i påstandens kilde →
   **præcis én** `narrative_record_publication` med `status='published'` for recorden. 0 eller flere på et
   led giver ingen række (r2-M6).
4. **Publiceringsgaten:** `public.person_daa_narrative_publication_allowed(narrative.id)` er sand, og
   narrativets subjekt er et af relationens bærende medlemmer.
5. **Familiegaten:** `public.family_offentlig(family_id)` er sand (alle medlemmer offentlige: ikke levende,
   ikke private, ikke `staged` — også børn, fordi funktionen omgår RLS).
6. **Etiketter** fra den seneste `narrative_publication_event.after_state` for bindingen (samme kilde som
   `public_person_bio_source_versions_v2`); `source_record_ref` er `source_record.public_ref` (decisions:
   publiceringsbindingens gamle `record_ref` er ikke en stabil reference).

Funktionen har ingen global undtagelsesfanger (rækker, der allerede er tilføjet resultatet, ville ikke
rulles tilbage); hvert led er en boolsk gate, og gatefunktionerne fejler selv lukket.

### 5.2 Web

- `packages/core`: ren funktion `familieIderForPerson(indexes, focusId)` → ægteskabsfamilier pr. ægtefælle
  og fødselsfamilien, ud fra `unionById` (`'f' + family_id`) og `childrenByUnion`; ingen ændring af
  `spousesBy`'s form. Formningsfunktion `kildeLinje(row)` → »Kilde: ‹source_label› · ‹record_label›«.
  Id'er er decimalstrenge hele vejen (modellens konvention); aldrig `Number()` (r2-m1).
- `web/src/data/familySources.ts`: `fetchFamilySources(familyIds)` kalder `public_family_sources` med
  id'erne som strenge; en RPC-fejl (fx funktionen findes ikke endnu i prod) giver `[]`, aldrig en fejl i panelet.
- `DetailPanel.tsx` viser kildelinjen under »gift med« ved den ægtefælle, hvis familie og
  `counterpart_person_id` matcher, og under »Barn af« ved netop den forælder, påstanden vedrører
  (`counterpart_person_id`), ikke ved begge forældre (r2-M1).
  **Klik:** er `source_record_ref` lig `sourceRecordRef` på en af den viste persons egne `bioVersions`
  (hovedpersonen ser sin egen post), vælger klikket den version; ellers er linjen ren tekst (hos ægtefællen
  er posten en anden persons). Ingen kilde ⇒ ingen linje.
- Mobil er uden for 2a.

## 6. Privatliv

Ingen modelkald. Scripts og rapport viser kun tal og hashes. Den offentlige funktion udleverer kun
etiketter, der allerede er offentlige gennem biografiens kildevisning, og kun når både publiceringsgaten og
familiegaten holder. Nye tabeller og RPC'er får RLS/ACL og står i `db-rls.sql`'s lister og `db-verify.sql`'s
asserts; nye `red_*`-navne står som `to_regprocedure` i `$public_red_revoke$` og har egen REVOKE/GRANT.

## 7. Færdigbevis (i restore, ikke i prod)

**Arbejdsbase:** ny kopi af del 1's bevisbase `daa5b_bevis_20261010093638`, løftet med
`db-migrations.sql` + `db-rls.sql` til 2a-commit'en. Del 1-basen forbliver urørt som fallback; 2a-kopien
bevares til 2b. Rapport `docs/evidensbaseret-genimport/relationspersonas-5b-2a-bevis.md`, kun tal, hashes og
basenavne. Rapporten binder sig til databaseidentiteten, commit'en og SHA-256 af `schema.sql`,
`db-migrations.sql` og `db-rls.sql`.

1. **Afgørelse:** 203 `accepted`, heraf 3 med `ordinal_afvigelse`; `set_sha256` og digest af det sorterede
   sæt af `interpretation_key`.
2. **Binding:** 210 (203 ægteskaber + 7 forældre); `preview_sha256`; digest af de sorterede tupler
   `(interpretation_id, family_id, rule_key, rule_version, state_sha256)` (r2-M5), sammenholdt med et
   manifest skrevet før bindingen; identisk retry ⇒ samme batch-id og 0 nye rækker.
3. **0 kanonisk delta:** aggregat-hashes af `person`, `family`, `family_member`, `fact`, `assertion`,
   `citation`, `conclusion` før og efter er ens.
4. **Læsefunktion som `anon`:** 210 rækker for de bundne familier; digest af de sorterede
   `(family_id, slags, source_record_ref)`; de eksisterende offentlige funktioners output for et fast
   personsæt er uændret (hashes før/efter).
5. **Webspor:** vitest (i CI) og Playwright (lokalt; CI-jobbet `node` kører kun vitest og build, og
   Actions-minutterne er knappe) med syntetiske svar viser kildelinjen ved et ægteskab og ved den bestemte
   forælder, klikket hos hovedpersonen og ren tekst hos ægtefællen.

**Negativtests** (i kopier, som går i karantæne):
- forkert `p_expect_set_sha256` ⇒ `RELATION_DECISION_SET_DRIFT`, 0 skrivninger;
- forkert previewhash ⇒ `RELATION_PROMOTION_PREVIEW_STALE`;
- part ikke `accepted`, ingen familie, flere familier, `omstridt`, anden kilde ⇒ ikke egnet med grund;
- familien ændret efter preview ⇒ afvist;
- relationselement til den gamle assertion-batch ⇒ afvist;
- gaten: levende medlem (også et barn), `staged`, upubliceret post, ny identitetsversion og afvist påstand
  skjuler hver især rækken.

## 8. Test

- **SQL** (CI's friske schema-sti, ny `tests/sql/test-relation-binding.sql`): regel-CHECKs pr. tilstand og
  begge validatorer; adskillelsen fra assertion-vejen; `relation_binding_state` (entydig/ikke, børn uden for
  strukturen); afgørelse (egnethed, kilde, ordinal-klassifikation, mængde-drift); binding (struktur,
  preview, partielt unikt indeks, allerede bundet); klassifikationstabellens append-only; læsefunktionens
  resolver og gate pr. betingelse; ACL og funktionsflade.
- **To-sessionstests** (dblink, som del 1): en samtidig `family_member`-indsættelse, en identitetsgenafgørelse
  og en anden promotion-batch venter på låsene eller fejler lukket; ved `40P01` rulles alt tilbage, og der
  er 0 delvise afgørelser/bindinger.
- **Opgraderingstest:** `db-migrations.sql` + `db-rls.sql` **to gange** på en base bygget fra `ebf2022`:
  `attnotnull` er falsk for `expected_fact_type`, den gamle overload af versionsfunktionen findes ikke,
  constraint-definitionerne er de nye, og de eksisterende text/date-regler virker funktionelt
  (`test-evidence-promotion.sql` og `test-interpretation-predicate.sql` i den opgraderede base). Kendte
  kaldesteder for den gamle signatur: `db-verify.sql` (~4354 `to_regprocedure`, ~4885-4911 og ~5328 kald) og
  `tests/sql/test-interpretation-predicate.sql:51-64`; kaldene virker uændret via standardværdien for
  `p_rule_mode`, mens `to_regprocedure`-kontrollen rettes til den nye signatur (r2-M7).
- **Vitest:** `familieIderForPerson`, `kildeLinje`, `fetchFamilySources` (fejl ⇒ `[]`) og `DetailPanel`'s
  visning (med/uden kilde, klik/ren tekst).
- **Playwright:** røgtesten i §7.5 med mockede RPC-svar, kørt lokalt og noteret i færdigbeviset.
- **CI-scope:** `test-relation-binding.sql` i `evidence-promotion-db`, `test-family-sources.sql` i
  `writer-1939-v50-db`, vitest i `node`.
- `get_advisors` efter DDL. Hele CI-jobbet køres lokalt før push.

## 9. Prod og fortrydelse

Uændret fra hovedspecen §13: **fortrydelse er restore-only**; ingen writer-reversal. 2a går ikke i prod
alene. 5a deployes først i sin egen ceremoni; derefter overføres 5b gennem en separat overførsels-spec med
GO, runbook og skrivepause fra backup til `VERIFY_OK`. Fortrydelse af DDL'en er en migration. Webkoden kan
merges før DB-overførslen: uden funktionen i prod er kildelinjerne blot tomme (§5.2).

## 10. Afvigelser fra og præciseringer af hovedspecen

1. **Ny offentlig læsefunktion** `public_family_sources` (§5): hovedspecen havde ingen læserrettet visning
   af bindingerne.
2. **Binding trods ordinal-afvigelse** ved én familie (§4.3), med klassifikation til 2b; hovedspecens
   kerne gør det samme for identitet (M9).
3. **Forældrene (7) bindes i 2a**, skønt hovedspecen grupperede dem med børnene (§8.3); de er afgjort.
4. **Klassifikationer i egen tabel** (§4.5) i stedet for scriptet `relation_control_classification.sql`.
5. **Klausul-dispositionen flyttes til 2b** (projektejerens valg ved planlægningen): kun ≤18 af 390 klausuler
   kunne disponeres efter 2a. Hovedspecens receipt-kontrakt og slutværdi (`fortolkning_foreslaaet`) gælder
   uændret i 2b.
6. **Webbeviset** er SQL som `anon` i bevisbasen plus UI-test med syntetiske svar (projektejerens valg):
   bevisbasen har ingen REST-server foran sig, og repoets Playwright-tests mocker al Supabase-trafik.
7. **Bindingstilstand og -gate** (§4.2, §5.1): bindingen gemmer en tilstandshash, og læsningen skjuler
   kilden, når tilstanden har ændret sig. Hovedspecens evidens `{family_id, vielse_fact_id|null,
   party_versions}` er erstattet af `{…, state_sha256, preview_sha256}`.
8. Ingen kontrolkørsel i ægteskabsafgørelsen er **ikke** en afvigelse: den følger af §23.5.

## 11. Åbne punkter

1. Familiekorrektion for `F`-kortet (1) — eget workflow og projektejerbeslutning.
2. `samme_som` for dubletten (1) — fra del 1's `same_individual_person_ids`.
3. Kildevisning i mobil.
4. Side i vielse-citationen: loaderens 262 citationer fra kilde 1 har ingen side; bindingen erstatter
   dem ikke.
5. Playwright i CI (kræver et nyt job; afvejes mod Actions-budgettet).
6. **Genbinding efter en rettelse (Opus kode-review M2, 2026-10-11) — skal afgøres før 2b.** Tilstanden
   omfatter de bærende rækkers `ordinal`/`konfidens` og identitetsversionen. En almindelig rettelse (fx
   `red_set_familie_ordinal` på et af de 3 `ordinal_afvigelse`-ægteskaber, eller en ny identitetsversion
   til samme person) skjuler derfor kilden — korrekt fail-closed — men i dag findes ingen vej til at binde
   igen: previewet siger `ALREADY_APPLIED`, det partielle unikke indeks tillader kun én familiebinding pr.
   fortolkning, og ingen writer laver en ny version af en accepteret påstand. Mulige veje: (a) en
   ombindingsvej (unikhed pr. gældende binding, eller `ALREADY_APPLIED` kun når den eksisterende binding
   stadig matcher tilstanden), (b) `ordinal` ude af tilstanden for bindinger klassificeret
   `ordinal_afvigelse`, eller (c) acceptere, at en rettet relation genafgøres i 2b's arbejdsgang.

## 12. Review runde 1 (Codex `gpt-5.6-sol`, 2026-10-11)

NO-GO: 3 BLOCKER, 8 MAJOR, 1 MINOR. Alle efterprøvet mod koden og godtaget.

| # | Fund | Rettelse |
| --- | --- | --- |
| B1 | Den offentlige DEFINER-funktion omgik publiceringsgaten | §5.1: `person_daa_narrative_publication_allowed`, `family_offentlig`, entydig binding, seneste event, `public_ref` |
| B2 | Afgørelsens preview var global og hashede for lidt | §4.3: `p_source_id`, envelope med databaseidentitet og fuld tilstand pr. påstand |
| B3 | En binding kunne blive stale uden at forsvinde | §4.2 + §5.1: `state_sha256` gemmes og sammenlignes ved læsning |
| M4 | Anchor/publicering ikke entydig | §5.1 trin 3: præcis én accepteret anchor og én publiceret binding |
| M5 | `NOT NULL` og to validatorer | §4.1 |
| M6 | UNIQUE sikrede ikke én familie pr. fortolkning | §4.4: partielt unikt indeks |
| M7 | `relation_disposition` ikke i writer-rammen | Flyttet til 2b (§10.5) |
| M8 | Dispositionens slutværdi modsagde hovedspecen | Flyttet til 2b med hovedspecens værdi (§10.5) |
| M9 | Webkontrakten kunne ikke knytte kilde til relation eller åbne version | §5.2: familie-id fra modellens unions; klik kun på egen post |
| M10 | Ingen samtidighedstests | §8: to-sessionstests |
| M11 | Del 1-beviset utilgængeligt; bevis kun antal | Henvisning til #238 (status); §7 binder til id-sæt og fil-hashes |
| m12 | Klassifikationstabellen kun erklæret append-only | §4.5: triggere og låst append-funktion |

## 13. Review runde 2 (Codex `gpt-5.6-sol`, 2026-10-11)

NO-GO: 0 BLOCKER, 8 MAJOR, 1 MINOR. Runde 1's B1, B2, M4, M6-M8 holdt; resten delvist. Alle efterprøvet og
godtaget (del 1-rapportens commit og hash verificeret lokalt).

| # | Fund | Rettelse |
| --- | --- | --- |
| M1 | Forælderkilden kunne ikke knyttes til den bestemte forælder | §5.1 `counterpart_person_id`; §5.2 vises ved den forælder |
| M2 | Klassifikation ikke versionsbundet | §4.5: `interpretation_id`, version, `state_sha256`; gældende-regel |
| M3 | Regelændring skjulte kilden uden ombindingsvej | §4.2: reglen ude af tilstanden; bindingen bærer sin regelversion |
| M4 | Ingen replay ved ukendt commit-udfald | §4.4: replay på `preview_sha256` + item-digest |
| M5 | Separate id-digests beviste ikke parringen | §7.2: tuple-digest mod manifest |
| M6 | Supporting-observation antaget entydig | §5.1 trin 3: præcis én på hvert led |
| M7 | Signaturens kaldesteder og CI-scope uklare | §8: kaldesteder, dobbelt opgradering, CI-scope; Playwright lokalt |
| M8 | Del 1-rapporten ikke fastlåst | Indledningen: commit + SHA-256 |
| m1 | `family_id` som tal i JS | §5.2: decimalstrenge, aldrig `Number()` |
