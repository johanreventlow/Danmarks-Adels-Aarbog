# Trin 5b del 2a — bind de afgjorte ægteskaber og forældre, og vis kilden for læseren (#151)

**Status:** udkast til projektejerens review (brainstorm 2026-10-11; design godkendt afsnit for afsnit).

**Roadmap:** trin 5, delspec 5b (`docs/superpowers/specs/2026-10-06-trin5b-relationspersonas-design.md`,
herefter »hovedspecen«), del 2, skive a. Bygger på 5b del 1 (merget #237, bevis i
`docs/evidensbaseret-genimport/relationspersonas-5b-del1-bevis.md`). Beslutninger: `docs/decisions.md`
2026-10-06, 2026-10-10 og 2026-10-11 (denne skive).

## 1. Adgangskrav (roadmap)

| Krav | Svar |
| --- | --- |
| Roadmapmål | Trin 5 (#151, med #150's familiedel) |
| Værdikædeled | Afgørelse → dokumenteret binding → læserens kildevisning (relationer) |
| Leverancetype | Generel motor: `structural_family`-regler, relationsafgørelse, relations-promotion og en offentlig læsefunktion for familiers kilder. Intet udgavespecifikt |
| Redaktionel/læserrettet værdi | Læseren ser for første gang en kilde på et ægteskab og en forældrelinje: »Kilde: DAA 2018-20 · ‹post›«, med klik til postens tekst. Redaktøren får ægteskaberne afgjort uden ark |
| Færdigbevis | §7: 203 ægteskaber afgjort og 210 relationer bundet i en kopi af del 1's bevisbase, 0 kanonisk delta, negativtests og en browser-røgtest af kildevisningen |
| Erstatter | Den gamle loaders ukildebundne `family_member`-rækker som eneste spor af ægteskaber og forældre; for de 179 med en vielse-påstand erstattes loaderens citat ikke, men suppleres af en binding til den aktuelle source record |

## 2. Del 2 i tre skiver

Del 2 (hovedspecen §8, §23.5, del 1-bevisets »Til del 2«) skæres i tre skiver, der specificeres, planlægges
og merges hver for sig:

- **2a (denne spec):** bind det, der allerede er afgjort eller kan afgøres maskinelt, og vis kilden.
- **2b:** de uafklarede — 31 identitets-uoverensstemmelser i webkøen med årsag (§23.5), nye personer
  (§8.4, herunder `family.id`-driften i errata §22.3), udtrækkets »(F.: …)«-fejllæsning, ægtefællers år
  (§22.7), de tre ordinal-klassifikationer fra 2a og final reviews M1-M3 og M5-M10.
- **2c:** børn (`relation.child`) med eget kortdesign, hvor kandidaten er barnet (§22.9).

Parkeret som åbne punkter (kræver hver sin projektejerbeslutning): familiekorrektion for `F`-kortet (1) og
`samme_som` for dubletten fra del 1's arkevidens (1).

## 3. Udgangspunkt (målt 2026-10-11 i `daa5b_bevis_20261010093638`, læse-kun)

| | |
| --- | --- |
| `relation.marriage` | 248 gældende: **203** med begge parter `accepted` og præcis én kanonisk familie med begge som partnere (203 forskellige familier); 31 med ægtefællen uafgjort; 14 uden persona |
| Ægteskabsnummer | 200 af 203 har bogens nummer = familiens ordinal; **3** afviger, alle med kun én familie (hovedspecen §6.2's kerne ignorerer ordinal ved én familie, M9) |
| `relation.parent` | 7 `accepted` (del 1's `A`-kort), 2 `proposed`, 1 `rejected` |
| `relation.child` | 14 `proposed` (2c) |
| Loaderens vielse-fakta | 179 af de 203 familier har en vielse-assertion med citation fra kilde 1 (uden side); 24 har ingen |
| Eksisterende bindinger | 0 `interpretation_promotion` med `target_type='family'`; reglerne er kun `person-*-v1` |
| Levende | 0 af familierne bag de 210 har et levende medlem |
| Publicering | Alle 210 påstande ligger i source records med `narrative_record_publication.status='published'` |

Stien fra påstand til post: `private.interpretation_observation` → `private.source_observation.occurrence_id`
→ `private.source_record_anchor_current.source_record_id` → `private.narrative_record_publication`.

## 4. Data: regler, afgørelse, binding, disposition

### 4.1 `structural_family`-regeltypen (hovedspecen §8.1)

`private.interpretation_promotion_rule` har i dag hårde CHECKs (`interpretation_kind='property'`,
`target_type='assertion'`, `expected_fact_type NOT NULL IN (…)`, `value_kind IN ('text','date_raw')`).
Ændringen:

- Ny kolonne `rule_mode text NOT NULL DEFAULT 'text_assertion'` ∈ `text_assertion` | `structural_family`.
- De fire CHECKs erstattes af én CHECK pr. tilstand: `text_assertion` bevarer dagens krav uændret;
  `structural_family` kræver `interpretation_kind='relation'`, `target_type='family'`,
  `expected_fact_type IS NULL`, `value_kind='relation'`. `expected_fact_type` bliver nullable.
- `db-migrations.sql`: idempotent `ADD COLUMN IF NOT EXISTS` + `DROP CONSTRAINT IF EXISTS`/`ADD CONSTRAINT`
  med de eksisterende constraint-navne målt i en opgraderet base, ikke gættet. `schema.sql` på linje.
- `private.add_interpretation_promotion_rule_version` får `p_rule_mode` (ny signatur; den gamle droppes
  i migrationen, revokes og `db-verify`'s funktionsflade opdateres). Valideringstriggeren følger.
- Regellinjer og første versioner: `relation-marriage-v1` (`relation.marriage`) og `relation-parent-v1`
  (`relation.parent`). `relation-child-v1` oprettes i 2c. Reglerne indsættes før enhver binding
  (fremmednøglen `interpretation_promotion_rule_fk`).
- **Adskillelse fra assertion-vejen:** `private.interpretation_predicate_promotable` får `rule_mode` med og
  filtrerer `rule_mode='text_assertion'`, så `red_preview_interpretation_promotions`/
  `red_promote_interpretations_batch` aldrig ser relationsregler. Negativtest: et `relation.marriage`-element
  til den gamle batch-RPC afvises som ikke-promoverbart.

### 4.2 Maskinel afgørelse af ægteskaber (hovedspecen §8.2 som ændret af §23.5)

Kun `relation.marriage`. De 7 forældre er allerede afgjort af projektejeren i del 1 og bindes blot (§4.3).

- **`red_preview_relation_decisions()`** (redaktion) returnerer de egnede påstande og
  `set_sha256` = SHA-256 over den sorterede mængde af `{interpretation_key, interpretation_version,
  family_id, party_versions}`, serialiseret med `to_jsonb(…)::text` under fastlagt `TimeZone` og
  `search_path` (aldrig `x::text`).
- **`red_decide_relation_interpretations(p_expect_set_sha256 text)`** genberegner mængden under
  rækkelåse i hovedspecen §6.2's totale låseorden og afviser ved forskel (`RELATION_DECISION_SET_DRIFT`,
  0 skrivninger). Egnet er en gældende `proposed` `relation.marriage`-påstand, hvor begge parters
  gældende identitet er `accepted`, der findes præcis én kanonisk familie med begge personer som partnere,
  og ingen af de to parters `family_member.konfidens` er `omstridt`. Hver accepteres gennem `red_decide_interpretation`'s kerne
  med evidens `{method: 'family-structure-v1', family_id, party_versions, book_ordinal, family_ordinal}`.
- Ingen kontrolkørsel som betingelse (§23.5 og decisions 2026-10-10): ægtefællens identitet er allerede
  afgjort af et menneske eller af en bestået kontrolkørsel.
- **Ordinal-afvigelse:** afviger bogens ægteskabsnummer fra familiens ordinal ved én familie, accepteres
  påstanden alligevel (familien er entydig), og der skrives en klassifikation `ordinal_afvigelse` i samme
  transaktion (§4.5). Ved flere familier er påstanden ikke egnet i 2a (målt: 0 tilfælde).

### 4.3 Binding (hovedspecen §8.1)

- **`red_preview_relation_promotions(p_items jsonb)`** og **`red_promote_relation_interpretations_batch(
  p_items jsonb, p_preview_sha256 text)`**, efter mønstret i `red_preview_interpretation_promotions`/
  `red_promote_interpretations_batch` (fælles privat `private.preview_relation_promotions(p_items, p_lock)`;
  previewhashen genberegnes under låse i skrive-transaktionen; `RELATION_PROMOTION_PREVIEW_STALE`).
- Pr. element efterprøves: gældende fortolkning `accepted`; regel `structural_family` aktiv for
  prædikatet; gældende parter; begge parters identiteter `accepted`; præcis én familie med strukturen
  (ægteskab: begge som partnere; forælder: principal som `barn`, modparten som partner); ingen af
  parternes `family_member.konfidens` er `omstridt`. Et ikke-egnet element vælter hele batchen med sin grund (som den eksisterende RPC).
- Skriver én `private.interpretation_promotion` pr. element med `target_type='family'`,
  `target_id=family_id`, `rule_key`/`rule_version`, `batch_id` og evidens
  `{family_id, vielse_fact_id|null, party_versions}`. `vielse_fact_id` er familiens vielse-fakt, hvis der
  er præcis én; ellers `null`. Loaderens vielse-assertion og citation røres ikke.
- `interpretation_promotion_batch.rule_profile_hash` beregnes som den eksisterende med kontrakten
  `relation-promotion-profile-v1`. Et nyt kald med samme elementer efter binding giver `already_applied`
  (UNIQUE `(interpretation_id,target_type,target_id)`), ikke en ny række.
- Ingen familie eller flere ⇒ ikke egnet, talt med grund. Bindingen ændrer ingen kanonisk række.

### 4.4 Klausul-disposition (hovedspecen §8.2)

- Writer-operationen `relation_disposition` (allerede i writer-rammens operationsliste, ikke
  implementeret) sætter en klausuls maskinelle disposition, når **alle** gældende påstande, der citerer
  klausulen og gav den `afventer_identitet`, er afgjort (`accepted` og bundet, eller `rejected`).
- Nyt vokabular (invariant 9): `clause_disposition_machine` / `relationer_afgjort` — »Maskinel: alle
  påstande om andre aktører i klausulen er afgjort«.
- Skrives kun, hvor klausulens gældende disposition er den maskinelle `afventer_identitet`; aldrig hvor
  der findes en menneskelig disposition (`clause_disposition_human`). Kræver `manifest_sha256` +
  `batch_id` som andre maskinelle writer-operationer; idempotent via rammens replay.
- Klausuler med en ubesluttet barne- eller forælderpåstand forbliver `afventer_identitet`. Planens Task 0
  måler antallet, der kan disponeres.

### 4.5 Klassifikationer

Ny append-only tabel `private.relation_classification_event(interpretation_key uuid, seq integer,
classification text, evidence jsonb, created_by uuid, created_at timestamptz, PRIMARY KEY
(interpretation_key, seq))` med `classification` ∈ `ordinal_afvigelse` (2b udvider med sine årsager).
RLS slået til, ingen grants til `anon`/`authenticated`, med i `db-rls.sql`'s masterliste og
`db-verify.sql`'s ACL-asserts. Forældrekortenes `identity_control_parent_event` genbruges ikke (bundet
til kontrolkørslens kort og `F`/`familie_aendret`).

### 4.6 Hærdning i 2a

Kun M4 (del 1-bevisets »Til del 2« pkt. 8): `db-rls.sql`'s masterliste får de tre kontroltabeller fra
del 1, der mangler. M1-M3 og M5-M10 hører til 2b, hvor kontrolkørsel og webkø røres igen.

## 5. Læsning: kilden på ægteskab og forælder

### 5.1 `public.public_family_sources(p_family_ids bigint[])`

Efter mønstret i `public_person_bio_source_versions` (v1/v2): `LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog`, `REVOKE ALL … FROM PUBLIC`, `GRANT EXECUTE … TO anon, authenticated`. Kun
narrativ-record-kontrakt 2: under kontrakt 1 returneres 0 rækker.

Returnerer pr. gældende binding: `family_id`, `slags` (`aegteskab` | `foraelder`), `record_ref`,
`source_label`, `record_label`, `citation_label`. Etiketterne tages fra den publicerede
`narrative_record_publication` (samme kilde som biografiens »Kilde i Aarbogen«), ikke fra loaderens
`citat_tekst`. Ingen klausultekst, ingen persona-, påstands- eller person-id'er.

**Gate (fail-closed, alle skal holde):**
- bindingen er gældende: `interpretation_promotion.interpretation_id` er den gældende version for
  påstandens nøgle, og dens status er `accepted`;
- familien har stadig strukturen fra bindingens evidens (ægteskab: begge parter er partnere; forælder:
  principal er `barn`, modparten partner);
- **alle** personer bag familiens `family_member`-rækker (også børn) har `levende=false`,
  `privat=false` og `staged=false` — funktionen er `SECURITY DEFINER` og omgår RLS, så gaten må ikke nøjes
  med de to bundne parter;
- posten er publiceret (`narrative_record_publication.status='published'`).

### 5.2 Web

- `web/src/data/public.ts` henter `public_family_sources` for de familier, detaljepanelet viser; formning i
  `packages/core` (ved `kildeProveniens.ts`).
- `DetailPanel.tsx` viser »Kilde: ‹source_label› · ‹record_label›« under et ægteskab og ved en
  forældrelinje; klik åbner postens version gennem `record_ref` (samme mekanisme som bioVersions).
  Ingen kilde ⇒ ingen linje (ingen »ukendt kilde«).
- Mobil er uden for 2a.

## 6. Privatliv

Ingen modelkald. Scripts og rapport viser kun tal og hashes. Den offentlige funktion udleverer kun
etiketter, der allerede er offentlige gennem biografiens kildevisning, og kun for familier uden levende,
private eller `staged` medlemmer. Nye tabeller og RPC'er får RLS/ACL og står i `db-rls.sql`'s lister og
`db-verify.sql`'s asserts; nye `red_*`-funktioner defineres før `$public_red_revoke$`.

## 7. Færdigbevis (i restore, ikke i prod)

**Arbejdsbase:** ny kopi af del 1's bevisbase `daa5b_bevis_20261010093638`, løftet med
`db-migrations.sql` + `db-rls.sql` til 2a-commit'en. Del 1-basen forbliver urørt som fallback; 2a-kopien
bevares til 2b. Rapport `docs/evidensbaseret-genimport/relationspersonas-5b-2a-bevis.md`, kun tal, hashes
og basenavne.

1. **Afgørelse:** 203 `accepted`, heraf 3 med `ordinal_afvigelse`; `set_sha256`.
2. **Binding:** 210 (203 ægteskaber + 7 forældre); previewhash; gentaget kald ⇒ `already_applied`.
3. **Disposition:** antal klausuler med `relationer_afgjort`; antal der forbliver `afventer_identitet`.
4. **0 kanonisk delta:** aggregat-hashes af `person`, `family`, `family_member`, `fact`, `assertion`,
   `citation`, `conclusion` før og efter er ens.
5. **Læsefunktion:** 210 rækker for `anon`; `anon`-fladen i øvrigt uændret (hashes af de eksisterende
   offentlige funktioners output før/efter).
6. **Webspor:** Playwright-røgtest mod basen viser kilden ved ét ægteskab og én forælder, og klikket
   åbner posten.

**Negativtests** (i kopier, som går i karantæne):
- forkert `p_expect_set_sha256` ⇒ `RELATION_DECISION_SET_DRIFT`, 0 skrivninger;
- forkert previewhash ⇒ `RELATION_PROMOTION_PREVIEW_STALE`;
- part ikke `accepted`, ingen familie, flere familier, `omstridt` ⇒ ikke egnet med grund;
- familien ændret efter preview ⇒ afvist;
- relationselement til den gamle assertion-batch ⇒ afvist;
- gaten: levende medlem (også et barn), `staged`, upubliceret post og afløst/afvist påstand skjuler hver
  især rækken.

## 8. Test

- **SQL** (CI's friske schema-sti, ny `test-relation-binding.sql`): regel-CHECKs pr. tilstand,
  adskillelsen fra assertion-vejen, afgørelse (egnethed, ordinal-klassifikation, mængde-drift), binding
  (struktur, preview, `already_applied`), disposition (præcedens for menneskelig disposition, ubesluttet
  barn blokerer), læsefunktionens gate pr. betingelse, ACL og funktionsflade.
- **Opgraderingstest:** `db-migrations.sql` + `db-rls.sql` kørt på en base bygget fra `ebf2022` (ændret
  tabel og ændret funktionssignatur; CI ser kun frisk schema).
- **Vitest:** formningen i `packages/core` og `DetailPanel`'s visning (med og uden kilde).
- **Playwright:** røgtesten i §7.6.
- `get_advisors` efter DDL. Hele CI-jobbet køres lokalt før push.

## 9. Prod og fortrydelse

Uændret fra hovedspecen §13: **fortrydelse er restore-only**; ingen writer-reversal. 2a går ikke i prod
alene. 5a deployes først i sin egen ceremoni; derefter overføres 5b gennem en separat overførsels-spec med
GO, runbook og skrivepause fra backup til `VERIFY_OK`. Fortrydelse af DDL'en er en migration.

## 10. Afvigelser fra og præciseringer af hovedspecen

1. **Ny offentlig læsefunktion** `public_family_sources` (§5): hovedspecen havde ingen læserrettet visning
   af bindingerne.
2. **Binding trods ordinal-afvigelse** ved én familie (§4.2), med klassifikation til 2b; hovedspecens
   kerne gør det samme for identitet (M9).
3. **Forældrene (7) bindes i 2a**, skønt hovedspecen grupperede dem med børnene (§8.3); de er afgjort.
4. **Klassifikationer i egen tabel** (§4.5) i stedet for scriptet `relation_control_classification.sql`.
5. Ingen kontrolkørsel i ægteskabsafgørelsen er **ikke** en afvigelse: den følger af §23.5.

## 11. Åbne punkter

1. Familiekorrektion for `F`-kortet (1) — eget workflow og projektejerbeslutning.
2. `samme_som` for dubletten (1) — fra del 1's `same_individual_person_ids`.
3. Kildevisning i mobil.
4. Side i vielse-citationen: loaderens 262 citationer fra kilde 1 har ingen side; bindingen erstatter
   dem ikke.
