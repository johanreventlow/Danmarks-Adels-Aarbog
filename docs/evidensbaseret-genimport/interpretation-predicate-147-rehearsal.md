# Prædikat-navnerummet (#147 4.2) — rehearsal mod prod-restore

Kun tal, hashes og prædikatnavne. Ingen kildetekst, ingen personoplysninger, ingen
record-id'er. Artefakterne ligger i `~/.private/` (0700-mapper) og committes aldrig.

**Gren:** `feat/147-praedikat-vokabular` ved `7092fb7` (før denne rapport).
**Dato:** 2026-09-10.

## 1. Grundlag

| Artefakt | Værdi |
| --- | --- |
| Prod-dump | `~/.private/daa-prod-20260910161728.dump` (samme dump som 4.1a/4.1c) |
| Dump-SHA-256 | `c1c13f76241e8b7207eee63c4fc3190c8ad2be4020250a8992bcc6cf0aded700` |
| Restore-base | `daa147_rehearsal_20260910224339` |
| Kontrolbase (`origin/main`, uden 4.2) | `daa147_kontrol_main_20260910224610` |
| CI-replikabaser | `daa147ci_promo_20260910225044`, `daa147ci_promo_fresh_20260910225044`, `daa147ci_legacy_empty_20260910225119`, `daa147ci_reimport_fresh_20260910225119` |
| Genereret prædikatfil, SHA-256 | `5e51c55b6217a75000a3d37e1130f31cc47b5e8d2d7451a54fc6f4616986fe2d` |

Restoren gav 8 fejl i alt, 0 uden for `supabase_vault` — samme billede som 4.1a.

## 2. Antagelsen målt før migration

Planen bygger på, at der ikke findes fortolkninger i prod, som en FK på
`(predicate, interpretation_kind)` kunne afvise. Det er nu målt, ikke antaget — både i
restoren og læse-kun mod prod selv.

| Måling | Restore | Prod (læse-kun) |
| --- | --- | --- |
| `private.interpretation` | 0 rækker | 0 rækker |
| `private.interpretation_predicate` findes | nej | nej |
| `private.interpretation_promotion_rule` | 5 aktive | 5 aktive |
| `person_post`-observationer | 591 | 591 |
| `narrative_record_contract_version()` | 2 | 2 |

Prod-målingen kørte i én `BEGIN READ ONLY … ROLLBACK` over Session pooler med
`sslmode=require` (`work/147-rehearsal/04-prod-maaling.sh`). Til forskel fra 4.1a's
rapport var sessionens egen læse-adgang til prod ikke blokeret denne gang; det er kun
skrivninger, klassifikatoren stopper.

**De fem eksisterende regler — den måling planen manglede.** Komposit-FK'en ligger på
`private.interpretation`, ikke på reglerne, og triggeren fyrer kun ved INSERT/UPDATE. En
eksisterende prod-regel med et prædikat uden for seedet ville derfor glide gennem
migrationen uden fejl og blot forsvinde tavst fra `interpretation_predicate_promotable`.
Reglerne blev derfor inventeret først:

| `rule_key` | `predicate` | `interpretation_kind` | i seedet? |
| --- | --- | --- | --- |
| `person-birth-v1` | `person.birth` | `property` | ja |
| `person-byname-v1` | `person.byname` | `property` | ja |
| `person-death-v1` | `person.death` | `property` | ja |
| `person-name-v1` | `person.name` | `property` | ja |
| `person-title-v1` | `person.title` | `property` | ja |

Alle fem par findes i seedet med samme udsagns- og værdiform. Ingen regel falder ud af
viewet, og prods promotion-adfærd er derfor uændret af 4.2.

## 3. Migration og verifikation på restoren

| Trin | Resultat |
| --- | --- |
| `db-migrations.sql` kørt to gange i træk | begge exit 0 |
| `db-rls.sql` | exit 0 |
| Aktive ikke-fixture prædikater \| `interpretation_predicate_promotable` | `42 \| 5` |
| Fixture-prædikater (`introduced_in='db-verify-fixture'`) | 8 |
| Komposit-FK | `interpretation_predicate_fk FOREIGN KEY (predicate, interpretation_kind) REFERENCES private.interpretation_predicate(predicate, interpretation_kind)` |
| Regler uden dækning i den nye tabel | 0 |
| `check_interpretation_predicates.py` | `PREDICATE_FILE_OK` |
| Klausullag efter migration (`person_post \| clause \| børn`) | `591 \| 0 \| 0` |

Restoren havde ikke 4.1a's `parent_observation_id` før migrationen — prod er endnu ikke
migreret med trin 4 — så klausultallene måles først efter. `591 | 0 | 0` er derfor det
forventede: skemaet er på plads, og 4.2 rører ikke de rækker, 4.1c senere skal skrive.

## 4. CI's SQL-sekvens mod restoren

Grenen har aldrig været gennem CI. Restoren og fire lokale CI-replikaer er derfor den
eneste kontrol, der findes — og #175's fejlmode var netop en fixture i en *anden* fil end
den, der blev rettet.

| Fil | Restore |
| --- | --- |
| `tests/sql/test-evidence-promotion.sql` | OK |
| `tests/sql/test-interpretation-predicate.sql` | OK (`t1 table and seed OK`, `t2 fks and binding OK`) |
| `tests/sql/run-db-verify-disposable.sql` | OK — herunder `OK: all seven dblink concurrency gates executed` |
| `tests/sql/test-reimport-legacy-migration.sql` | OK |
| `tests/sql/test-clause-evidence-schema.sql` | OK |
| `tests/sql/test-reimport-edition-catalog.sql` | OK |
| `tests/sql/test-narrative-record-contract.sql` | FEJL — se nedenfor |
| `tests/sql/test-narrative-record-cutover.sql` | FEJL — se nedenfor |

Den dblink-baserede samtidighedstest er værd at fremhæve: det er dér, R1′'s oversete
prædikat lå (`db-verify.sql:4048` indsætter gennem `dblink_exec` med fordoblede
apostroffer). Restoren har dblink, alle syv gates kørte, og omdøbningen til `verify.name`
holder mod prod-formet data.

**De to narrative fejl er egenskaber ved en prod-restore, ikke ved grenen.** Det er målt,
ikke sluttet: en kontrolbase blev restoreret fra samme dump og migreret med
`origin/main` — altså helt uden 4.2 — og fejler med præcis de samme to tokens:

| Test | Restore m. 4.2 | Kontrol m. `origin/main` |
| --- | --- | --- |
| `test-narrative-record-contract.sql` | `NARRATIVE_RECORD_CONTRACT_VERSION_EXPECTED_1` | `NARRATIVE_RECORD_CONTRACT_VERSION_EXPECTED_1` |
| `test-narrative-record-cutover.sql` | `CUTOVER_DRIFT_DID_NOT_FAIL_CLOSED: CUTOVER_ARTIFACT_HASH_MISMATCH` | samme |

Årsagen er, at prod står på narrativ-kontraktversion **2** efter 149b, mens begge tests er
skrevet til en frisk base på version 1 — hvilket er netop den base, CI giver dem. De to
tests hører ikke til restore-stien.

## 5. Lokal replika af CI's fire db-verify-stier

`db-verify.sql` fik i dette dagsværk en ny prod-side-blok (se §6), og den kører på fire
CI-baser, som restoren ikke ligner. Alle fire blev derfor bygget lokalt efter
`.github/workflows/ci.yml` og kørt igennem:

| CI-sti | Base | `OK: #147` |
| --- | --- | --- |
| `evidence_promotion`, kumulativ (`evidence-hardening-pre-migration.sql` → migration ×2) | `daa147ci_promo_…` | ja |
| `evidence_promotion_fresh`, frisk `schema.sql` | `daa147ci_promo_fresh_…` | ja |
| `reimport_legacy_empty_153`, skema fra `2d6aabf` + migrationssti | `daa147ci_legacy_empty_…` | ja |
| `reimport_fresh_153` | `daa147ci_reimport_fresh_…` | ja |

`test-interpretation-predicate.sql` og `check_interpretation_predicates.py`
(`PREDICATE_FILE_OK`) er grønne på begge promotion-stier. Ingen af de fire baser gav
`ERROR`.

## 6. Ny prod-side-assertion i `db-verify.sql`

Planens Step 1 forventede et `OK: #147` fra `run-db-verify-disposable.sql`, men ingen
sådan blok fandtes: 4.2's verifikation lå udelukkende i `tests/sql/`, som kun kører i CI.
`db-verify.sql` er prod-siden, og hvert tidligere dagsværk har sin blok dér (`OK: #148`).
Blokken er derfor skrevet nu og dækker:

- tabel og `interpretation_predicate_promotable` findes;
- komposit-FK'en på `private.interpretation` findes med præcis `(predicate, interpretation_kind)`;
- alle tre triggere og RLS er på plads;
- mindst 42 aktive ikke-fixture prædikater og **præcis** 8 fixture-rækker;
- hver `category` er et seedet `interpretation_category`-kodeord;
- hver aktiv ikke-`verify-` regel har et matchende, aktivt prædikat med samme udsagns- **og** værdiform;
- hverken `anon`, `authenticated` eller `service_role` har SELECT/INSERT på tabel eller view, og de to trigger-funktioner er ikke kaldbare for dem.

Seed-antallet er bevidst `>= 42` og ikke `= 42`: hvert senere dagsværk skal kunne tilføje
prædikater uden at gøre produktionsverifikationen rød. Fixture-rækkerne tælles derimod
præcist, fordi db-verify's egne negative tests afhænger af netop de otte.

**To negative prober beviser, at blokken bider** — en constraint uden en test, der viser
den fyre, er en formodning:

| Perturbation (i en transaktion, rullet tilbage) | Forventet | Målt |
| --- | --- | --- |
| `DROP CONSTRAINT interpretation_predicate_fk` | `PREDICATE_COMPOSITE_FK_MISSING` | fyrede |
| Pensionér `person.name` (+ kompensér antallet, så seed-guarden ikke fyrer først) | `PREDICATE_RULE_BINDING_DRIFT` | fyrede |

Den anden probe måtte kompensere antallet: uden det fyrer `PREDICATE_SEED_INCOMPLETE`
først, og proben ville have bevist noget andet end den regelbinding, den skulle prøve.

## 7. Konklusion og hvad der ikke er gjort

4.2 er kørt igennem på en frisk restore af prod og på fire CI-formede baser. Antagelsen om
nul fortolkninger er målt begge steder, prods fem promotion-regler er dækket af seedet, og
den genererede fil er byte-identisk med tabellen.

**Ikke gjort:** ingen prod-GO. Migrationen er ikke kørt mod prod, og `get_advisors` er
ikke kørt — begge hører til en selvstændig prod-beslutning sammen med resten af trin 4.
Rehearsal-baserne og kontrolbasen står stadig lokalt og kan droppes af projektejeren.
