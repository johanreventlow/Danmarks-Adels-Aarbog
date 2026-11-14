# Fuld personsletning — implementeringsplan (v2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** En redaktør kan slette én personprofil helt fra Redaktion efter en forhåndsvisning. Bagefter står der intet
tilbage om personen ud over de rester, projektejeren udtrykkeligt har godkendt.

**Architecture:**
- **Inventar.** Sletningen bygger på et statisk sletteinventar, en funktion med `VALUES` sidst i `schema.sql`. Til
  hvert sted hører en handling (`slet`/`nulstil`/`loesn`/`bevar_andres`/`blokér`), en fase og de kolonner, stedet
  dækker.
- **Planfunktion.** En plpgsql-funktion med statisk SQL beregner id-mængderne fra slettegrafen og
  historiklukningen.
- **Manifest.** Sletningen skriver hver række, den vil slette, i et transaktionslokalt manifest med en `grund`.
  Append-only-triggerne tillader DELETE af en række, når den står i manifestet, og når et uafhængigt tjek pr. grund
  holder.
- **Storage.** Filstierne lægges i en privat udbakke. Redaktion sletter filerne efter commit og kvitterer for hver
  fil.
- **Måling.** Tests og færdigbevis måler med værktøjer, der er uafhængige af inventaret: `count.sql` og en
  `row::text`-søgning.

**Tech Stack:** PostgreSQL 17 (Supabase), plpgsql, psql-testscripts i CI, React/TypeScript + vitest i `web/`.

**Kilder (læs før hver task; de er bindende):**
- Spec: `docs/superpowers/specs/2026-11-14-fuld-personsletning-design.md` (v2, 2026-11-14).
- **Slettegraf:** `docs/superpowers/plans/personsletning/slettegraf.md`. Afsnittet »Afgørelser 2026-11-14« øverst
  gælder **foran** tabellerne i dokumentet. Sted-numrene S1-S58, NY-A..D og M5 bruges overalt i planen.
- Kortlægning: `docs/superpowers/plans/personsletning/kortlaegning.md`. Måler (rå):
  `docs/superpowers/plans/personsletning/count.sql`.
- Review, plan v1: `docs/superpowers/plans/personsletning/fable-planreview-v1.md`. Fundene hedder K-1..K-4, V-1..V-9
  og »Mindre«; hvert fund er taget med nedenfor.
- Linjenumre: `schema.sql` på `main` `c41f67db`.

**Roadmap (adgangskrav, roadmap.md »Adgangskrav«):**
1. **Mål:** trin 6 (1939 gennem samme operationer). Sletningen lukker en løs ende fra 6d-3, hvor 1791 blev skjult.
2. **Led:** identitet og publicering, oprydning efter fejlagtig oprettelse.
3. **Leverance:** generel; den er ikke bundet til en bestemt udgave.
4. **Værdi:** redaktøren kan fjerne en fejlprofil eller en testperson helt, og en GDPR-anmodning kan efterkommes.
5. **Bevis:** spec §7's færdigbevis for 1791 og generalprøve 2 (Task 13).
6. **Erstatter:** at skjule fejlprofiler, og `red_slet_person` for profiler med historik. `red_slet_person` bevares
   til resten.
7. **Reviewbudget:** se specens hoved.

## Global Constraints

- **Source of truth og migration.** `schema.sql` er source of truth. Hver ændring spejles idempotent i en ny blok
  sidst i `db-migrations.sql` med markøren `-- Fuld personsletning (2026-11-14)`, og grants i `db-rls.sql`.
  Migrationen skal kunne køres to gange.
- **Placering.** Den nye sektion »FULD PERSONSLETNING« lægges **sidst i `schema.sql`**, efter alle tabeller, den
  nævner (K-4). Inventar og undtagelseslister er funktioner med `VALUES`, ikke tabeller. Så dækkes de af harnessens
  sammenligning af funktionskroppe, og ingen kan ændre dem med DML.
- **Nye funktioner:**
  - `SECURITY DEFINER`, `SET search_path = pg_catalog, public, private`.
  - `REVOKE ALL … FROM PUBLIC, anon, authenticated, service_role`.
  - `GRANT EXECUTE … TO authenticated` kun for de public-RPC'er, Task 7 og Task 12 navngiver.
- **Rollegaten** `current_rolle() = 'redaktion'` er første sætning i alle public-RPC'er, før enhver læsning.
- **Bogens lag slettes aldrig:** `source_record`, `source_occurrence`, `source_observation*`, `source_mention`,
  `source_rendition`, `extraction_run`, `source_persona`, `source_persona_mention`, `source_persona_placement*`,
  `interpretation`, `interpretation_observation`, `interpretation_party`, `identity_control_run/sample/event/exclusion`,
  `reimport_writer_profile`, `narrative_record_cutover_receipt`.
- **Triggere:**
  - Ingen `DISABLE TRIGGER`, ingen `session_replication_role`, ingen ændring af TRUNCATE-triggere.
  - **Ingen UPDATE-undtagelse i nogen triggerfunktion** (V-3). `narrative_legacy_publication.latest_event_id := NULL`
    er allerede tilladt (validatoren l. 14035), og tabellen har ingen append-only-trigger.
- **Ingen historik.** Sletningen opretter ingen `change_set` eller `change_event` og afviser med
  `PURGE_FREMMED_CHANGE_SET`, hvis `app.change_set_id` er sat.
- **Ingen GUC som bevis** (V-2). Rettigheden til oprindelsen `person_purge` og til hvert løft af append-only bevises
  af manifestrækker for `(pg_current_xact_id(), pg_backend_pid())`.
- **Låseorden:** slettegraf §6.2, L1-L13, ikke spec v1 §6.12 (V-1). Kildelåsen tages eksklusivt og tidligt, sorteret
  efter kilde-id.
- **Fejlkoder:** `PURGE_FREMMED_CHANGE_SET`, `PURGE_PREVIEW_AENDRET`, `PURGE_BLOKERET: <art>`, `PURGE_FINDES_IKKE`,
  `PURGE_LOCKSET_DRIFT`, `PURGE_REST: <sted>` (slutkontrol), `EVIDENCE_PERSON_PURGE_SHAPE`.
- **Tilladt rest.** Testenes navngivne liste er præcis denne; alt andet er en fejl:
  - P's id-nummer i andres rækker: S11c, S23b, S32c, S41b, S43b, S45b, S46, S48, S49c, S50, NY-C, S57, S52b, og
    andres bindinger i S39c.
  - Bogtekst med P's navn i:
    - S44a `authorized_elements` (Q1)
    - andres narrativ- og notehistorik og publiceringstilstande (K2/Q2)
    - et delt medies titel (K3/Q8)
    - vielsesfakta i bevarede familier (K5, beslutning 7)
  - Bogens lag.
- **Testdata.** Ingen PII i testoutput, commits eller logs. Testpersoner er syntetiske med negative id'er
  (`-987654700`..`-987654709`). Mod prod-kopier printes kun tal.
- **Prod.** Prod skrives kun af projektejeren i egen shell via en runner med `--jeg-mener-det --go <8hex>`.
  Subagenter læser aldrig `~/.private`, `work/` eller `work_presens/`.
- **Commits.** Hovedsessionen ejer alle commits. Subagenter committer ikke.

## Review Focus

1. **Et sted, inventaret ikke kender.** Det kan være en ny tabel eller en ny kolonne i en kendt tabel. Forventet:
   katalogvagten fejler i CI. Testes i Task 3 (`vagt_ny_tabel`, `vagt_ny_kolonne`).
2. **Rester inventaret ikke ser.** Forventet: den inventaruafhængige `row::text`-søgning finder kun den tilladte rest
   (Task 1 og Task 8).
3. **Tidligere slettede rækker i historikken** (et faktum fjernet for et år siden). Forventet: deres `change_event`
   slettes, og fortryd af det gamle sæt genskaber intet (Task 4 og Task 8, K-2).
4. **Manifestet er for bredt.** Det gælder en række fra en anden person, en anden transaktion eller backend, en
   bogtabel eller en forkert `grund`. Forventet: DELETE afvises (Task 5).
5. **Samme antal, andre rækker** mellem preview og sletning. Forventet: `PURGE_PREVIEW_AENDRET` (Task 7 og Task 8).
6. **Låsecyklus** mod `red_afgoer_source_persona`, en publiceringsskriver eller en kandidatkørsel. Forventet:
   serialiseret og ingen 40P01 (Task 11).
7. **Id-genbrug** efter sletning af det højeste id i alle 8 tabeller (Task 9).

---

## Filstruktur

| Fil | Ansvar |
|---|---|
| `schema.sql` (sidste sektion »FULD PERSONSLETNING«) | inventar, undtagelser, plan- og historikfunktioner, manifest, udbakke, preview, sletning; ændringer i 4 triggerfunktioner, `decide_source_persona_identity`, `validate_source_persona_identity_event`, `red_fortryd_change_set` (l. 9558) |
| `db-migrations.sql` (ny blok sidst) | samme, idempotent |
| `db-rls.sql` | REVOKE/GRANT |
| `db-verify.sql` | asserts (Task 10) |
| `tests/sql/person-purge-count.sql` | uafhængig tæller pr. sted (rettet `count.sql`) |
| `tests/sql/person-purge-rest.sql` | inventaruafhængig `row::text`-søgning med tilladt-rest-liste |
| `tests/sql/fixtures/person-purge.sql` | syntetisk person med spor på alle slet-/nulstil-/loesn-steder, naboer og fabrikeret historik |
| `tests/sql/test-person-purge.sql` | SQL-testene, grupperet pr. task |
| `tests/sql/test-person-purge.sh` | skabelonbase (skema + fixture), én kopi pr. testgruppe, frisk + opgradering, samtidighed |
| `.github/workflows/ci.yml` | nyt trin efter `test-6e2-upgrade` |
| `web/src/data/personPurge.ts` (+ test) | preview, orkestrering (DB, så Storage, så kvittering), udbakke |
| `web/src/components/SletHeltDialog.tsx` (+ test) | dialog |
| `web/src/Redaktion.tsx`, `web/src/data/redaktionWrite.ts` | tilslutning |
| `docs/runbooks/personsletning-prod.md` | ceremoni og første brug |

---

### Task 1: Uafhængig måler (V-4)

**Files:** Create `tests/sql/person-purge-count.sql`, `tests/sql/person-purge-rest.sql`.

- [ ] **Step 1:** Kopiér `docs/superpowers/plans/personsletning/count.sql` til `tests/sql/person-purge-count.sql` og ret
  de tre huller fra slettegrafens »Afgørelser«:
  - `coalesce(efter,foer)` → `foer` og `efter` hver for sig (slettegraf §2.1).
  - Feed-pin-formaterne fra NY-B tilføjes.
  - S46 via kandidat-uuid'er (`candidate.id WHERE candidate_person_id=P`), ikke regex.
  Output: én række pr. sted (`sted`, `tabel`, `antal`), kun tal. Den læser **ikke** inventaret.
- [ ] **Step 2:** Skriv `tests/sql/person-purge-rest.sql`.
  - Input: psql-variablerne `pid` og `navn`.
  - For hver tabel i `public` og `private` (fra `pg_class`, ikke fra inventaret) tælles rækker, hvor `row::text`
    indeholder `[[person:<pid>|`, `navn` eller `pid` som helt tal-token (regex `(^|[^0-9-])<pid>([^0-9]|$)`).
  - Output: `tabel`, `antal`, `tilladt` (boolean) fra en navngiven liste med sted-nummer og begrundelse, præcis
    Global Constraints' »Tilladt rest«. Tallene er antal; ingen rækkeindhold.
- [ ] **Step 3:** Kør begge mod prod-kopien `daa5ab_ddl_standin_20261113220424_g3` for `pid=1791` (læse-kun, kun tal).
  Gem tallene i task-rapporten. Forventning: count-tallene matcher spec §7's måling (17 steder). Afviger de, står
  forklaringen i rapporten.
- [ ] **Step 4:** Hovedsessionen committer `test(sletning): uafhængig tæller og restsøgning for personspor`.

### Task 2: Fixturen (V-9)

**Files:** Create `tests/sql/fixtures/person-purge.sql`; Create `tests/sql/test-person-purge.sh` (kun skabelonbygning
og gruppe-kopier i denne task).

- Hovedpersonen er `-987654700` (»Testperson Purge«). Naboerne er:
  - `-987654701`: ægtefælle i dubletfamilie uden børn → familien slettes.
  - `-987654702`: barn i en anden familie med `-987654700` + `-987654705` → familien bevares med vielse.
  - `-987654703`: én `samme_som`-nabo.
  - `-987654704`: tredjeperson uden forbindelse.
  - `-987654705`: anden partner.
- [ ] **Step 1:** Byg kæderne med de eksisterende fixtures, så valideringstriggerne er glade:
  - `fixtures/publication-identity.sql` og `publication-persona.sql`: identitet og publicering.
  - `relation-*.sql` og `relation-persona-reuse-helpers.sql`: promotions, `relation_reopen` og
    `text_revision_reconciliation`.
  - `marriage-ordinal-244.sql`.
  Personens spor skal dække **hvert sted med handling slet/nulstil/loesn** i slettegrafen, plus:
  - `Prom_egen_fam` (Q6)
  - P's egen persona med tidligere `accepted → -987654704`, før den blev koblet til P (K-3, `hel_stroem`)
  - en `Y`-persona med v1 `accepted → P` og v2 `accepted → -987654704` (§6.10)
  - et forældrekort med `counterpart_person_id=P`
  - et feed-pin i hvert NY-B-format
  - et delt medie og et eksklusivt medie
- [ ] **Step 2: Historik fabrikeres** med direkte `INSERT` i `change_set`/`change_event`. `red_opret_person` giver
  sekvens-id'er, så den kan ikke bruges. Fabrikér:
  - et `red_opret_person`-sæt med summary `'Oprettede person Testperson Purge'` og dets fortryd-sæt
  - et `red_opret_union`-sæt med P som subjekt og ægtefællens events
  - et fortryd-sæt for et sæt, der bevares
  - et fælles sæt med en `narrative_publication_event`-FK
  - et `withdraw_legacy_narrative`-sæt uden events, med fritekst i summary
  - tidligere slettede rækker, der kun findes i `change_event.foer`: et faktum, en relation, et narrativ og en
    `assertion` med `citation`
  - en `UPDATE` på en note, hvis `target_id` flyttede væk fra P
  - en `feed_pin` med `embede:P:…`
- [ ] **Step 3:** Byg harnessen.
  - Harnessen bygger én skabelonbase (schema + migrations + rls + fixture) og laver `createdb -T` pr. testgruppe.
    Sletninger committer i deres egen kopi, fordi udskudte triggere ikke kører ved ROLLBACK (V-4).
  - Følg mønstret for oprettelse og oprydning af baser i `tests/sql/test-6e2-etiket.sh`. Harnessen må kun droppe
    baser, den selv har oprettet i samme kørsel, med det præfiks den fik som argument.
- [ ] **Step 4: Test `fixture_daekker_slettegraf`.** `tests/sql/person-purge-count.sql` med `pid=-987654700` giver
  `antal > 0` for hvert slet-/nulstil-/loesn-sted. Undtaget er steder på en navngiven liste
  `kan_ikke_forekomme` med begrundelse; S9 hører der, fordi kvitteringen forbruges.
- [ ] **Step 5:** Kør `bash tests/sql/test-person-purge.sh t_purge_t2` → `OK fixture_daekker_slettegraf`, `FRISK_OK`.
  Hovedsessionen committer `test(sletning): fixture med spor på alle slettesteder og fabrikeret historik`.

### Task 3: Inventar og katalogvagt pr. kolonne (K-1, K-4, V-7)

**Files:** `schema.sql`, `db-migrations.sql`, `db-rls.sql`, `tests/sql/test-person-purge.sql`, `.github/workflows/ci.yml`.

**Interfaces:**
- Produces: `private.person_purge_inventar() RETURNS TABLE(sted text, tabel text, kolonner text[], handling text,
  fase text, grund text)`.
  - Implementeres som `VALUES` med én række pr. sted i slettegrafen, inklusive bevar_andres og blokér.
  - `handling` ∈ {`slet`,`nulstil`,`loesn`,`bevar_andres`,`blokér`,`ingen`}, `fase` som i slettegraf §1.1.
  - `grund` ∈ {`egen`,`hel_stroem`,`andres_ref`,`afledt`,`familie`,`historik`} eller NULL.
- Produces: `private.person_purge_undtagelser() RETURNS TABLE(tabel text, kolonne text, begrundelse text)` (VALUES).
- Produces: `private.person_purge_kandidatkolonner() RETURNS TABLE(tabel text, kolonne text, art text)`. Funktionen
  scanner kataloget i `public` og `private`:
  - FK til `public.person(id)` eller `public.family(id)`
  - par af `*_type` og `*_id`
  - kolonner af typen `jsonb`, `bigint[]` og `text`, uanset navn

**Vagtregel:** hver kandidatkolonne står enten i et inventarsteds `kolonner` for samme tabel eller i
`person_purge_undtagelser`. Undtagelsen er rimelig for fx bogens tabeller og ren tekst uden person-reference.

- [ ] **Step 1: Tests (skal fejle):**
  - `inventar_daekker_katalog`: vagtreglen; fejlbeskeden lister umatchede `(tabel, kolonne)`.
  - `vagt_ny_tabel`: en midlertidig `public.tmp_purge_vagt(person_id bigint REFERENCES public.person(id))` får
    vagten til at fejle.
  - `vagt_ny_kolonne`: `ALTER TABLE public.story ADD COLUMN tmp_person bigint` får vagten til at fejle.
  - Begge midlertidige objekter fjernes igen i testens egen kopi.
  - `inventar_ingen_bogtabel`: ingen række med handling `slet`/`nulstil`/`loesn` har en tabel fra bogens lag.
  - `inventar_svarer_til_slettegraf`: hvert S-/NY-/M-nummer i slettegrafen findes i inventaret, og omvendt. Listen
    over numre står i testen.
- [ ] **Step 2:** Kør → FAIL (`function private.person_purge_inventar() does not exist`).
- [ ] **Step 3:** Implementér. Tilføj CI-trinnet `bash tests/sql/test-person-purge.sh ciperson_purge <base>` efter
  `test-6e2-upgrade`. `<base>` er den commit, der svarer til prods skema. I dag er det `c41f67db`, fordi
  skemafilerne er uændrede siden 6e-2 (bekræft mod `docs/database-current-state.md`; »Mindre« i reviewet).
- [ ] **Step 4:** Kør → `OK` for alle. Hovedsessionen committer `feat(sletning): sletteinventar og katalogvagt pr. kolonne`.

### Task 4: Plan- og historikfunktioner (K-1, K-2)

**Files:** `schema.sql`, `db-migrations.sql`, `tests/sql/test-person-purge.sql`.

**Interfaces:**
- Produces: `private.person_purge_plan(p_person_id bigint) RETURNS TABLE(sted text, tabel text, pk jsonb, handling
  text, grund text, fase text, ekstra jsonb)`. Funktionen er læse-kun med statisk SQL og har ingen dynamisk
  `EXECUTE`.
  - Den beregner mængderne fra slettegraf §0, inklusive `Prom_egen_fam` (Q6), og returnerer én række pr. berørt række.
  - `ekstra` bærer `forrige_version` for `hel_stroem`-identitetsrækker (Q7) og storage-stier for medier.
- Produces: `private.person_purge_historik(p_person_id bigint) RETURNS TABLE(tabel text, pk jsonb)`. Den beregner
  `E` (slettegraf §2.3, med de historiske mængder F\*, R\*, A\*, N\*, S\*, M\*, PEI\* fra §2.2) og `D` (§2.4: `D0`,
  `C`, `Frev`, med `reverterer_id IS NULL` i punkt 2).
- Konsistens: alle `(sted, tabel)` fra planen skal findes i inventaret med samme handling.

- [ ] **Step 1: Tests:**
  - `plan_matcher_inventar`
  - `plan_matcher_count`: for fixturen er planens antal pr. sted lig `person-purge-count.sql`'s antal pr. sted.
    `bevar_andres` er undtaget. Afvigelser skal forklares i testen.
  - `historik_tidligere_slettet`: `E` indeholder events for det tidligere slettede faktum, den slettede relation,
    det slettede narrativ og den slettede påstand med citation.
  - `historik_flyttet_note`: `E` indeholder note-eventet, hvis `foer` pegede på P.
  - `historik_withdraw_saet`: `D` indeholder `withdraw_legacy_narrative`-sættet.
  - `historik_fortryd_bevaret`: fortryd-sættet for det bevarede sæt er **ikke** i `D`.
  - `historik_faelles_bevaret`: union-sættet er ikke i `D`; dets P-events er i `E`.
- [ ] **Step 2:** Kør → FAIL. **Step 3:** Implementér. **Step 4:** Kør → `OK`.
- [ ] **Step 4b (Q6):** Læs `relation_binding_state` (l. 20004) og familiebekræftelsen (`red_corroborate_family_identities`
  l. 19948), og skriv i task-rapporten, hvad der sker med en bevaret familie, når én af dens bindinger forsvinder.
  Forventet: bindingen bliver forældet og kan genåbnes; der kommer ingen fejl. Ved anden adfærd stopper
  hovedsessionen og forelægger projektejeren.
- [ ] **Step 5:** Hovedsessionen committer `feat(sletning): planfunktion og historiklukning`.

### Task 5: Manifest og snævert løft af append-only (K-3, V-3)

**Files:** `schema.sql`, `db-migrations.sql`, `db-rls.sql`, `tests/sql/test-person-purge.sql`.

**Interfaces:**
- Produces: `private.person_purge_manifest(xid xid8, backend_pid int, person_id bigint, tabel text, pk jsonb, grund
  text NOT NULL, forrige_version int, PRIMARY KEY (xid, backend_pid, tabel, pk))`, RLS on, ingen grants.
- Produces: `private.person_purge_tilladt(p_tabel text, p_old jsonb) RETURNS boolean` (SECURITY DEFINER). Den er sand,
  når alle tre holder:
  - Manifestet har rækken for `(pg_current_xact_id(), pg_backend_pid(), p_tabel, pk)`.
  - `p_tabel` står på en konstant tilladelsesliste.
  - Det uafhængige tjek for rækkens `grund` holder (slettegraf §3.2, med Q5-rettelsen fra »Afgørelser«).
    `hel_stroem` kræver, at personaens state stadig peger på manifestets person, og at `forrige_version` er lig
    max(version).
- **Tilladelseslisten** består kun af tabeller med handling `slet` og en append-only-vagt: S11a/b, S12, S23, S39a,
  `Prom_egen_fam`, S40, S41a, S42, S43a, S45a, M5, S49a, S49b.
- Modifies **kun**:
  - `private.reject_evidence_mutation` (l. 916)
  - `private.reject_reimport_writer_mutation` (l. 4063)
  - `private.reject_reimport_case_event_mutation` (l. 9297)
  - `private.reject_narrative_publication_event_mutation` (l. 13997)
- **Formen** (V-3):
  - Trinvise `IF`: `IF TG_OP='DELETE' THEN IF TG_TABLE_NAME = ANY(<liste>) THEN IF private.person_purge_tilladt(…)
    THEN RETURN OLD; END IF; END IF; END IF;` før den eksisterende afvisning.
  - Ingen ændring for TRUNCATE eller UPDATE.
  - Afvisningsteksten (`EVIDENCE_APPEND_ONLY` m.fl.) skal være uændret for enhver rolle, der får den i dag. db-verify
    l. 2623-2637 er grøn; ingen rolle må få »permission denied« i stedet.

- [ ] **Step 1: Tests:**
  - `manifest_uden_raekke_afvises`
  - `manifest_tillader_egen_raekke` (COMMIT i egen kopi)
  - `manifest_anden_person_afvises`
  - `manifest_anden_backend`
  - `manifest_forkert_grund`: `egen` på en `hel_stroem`-række med `canonical_person_id` = en anden afvises.
  - `hel_stroem_tillader_null_og_anden`: P's personas ældre events med NULL og med `-987654704` slettes, når state
    peger på P (K-3).
  - `bogtabel_altid_afvist`: en `source_record`- og en `interpretation`-række i manifestet afvises.
  - `update_uaendret_forbudt`
  - `truncate_uaendret`
  - `afvisningstekst_uaendret`: med fixturen `fixtures/kalder-matrix.sql` får hver rolle samme fejltekst som før.
  - `trigger_enabled`
- [ ] **Step 2:** FAIL. **Step 3:** Implementér. **Step 4:** `OK`.
- [ ] **Step 5:** Hovedsessionen committer `feat(sletning): manifest med grund og snævert løft af append-only`.

### Task 6: Oprindelsen `person_purge` og version n+1 (V-2, Q7)

**Files:** `schema.sql`, `db-migrations.sql`, `tests/sql/test-person-purge.sql`.

**Interfaces:**
- **Modifies `private.decide_source_persona_identity`** (l. 10404) med en gren `p_origin='person_purge'`. Den kræver:
  - `p_decision_status='rejected'`
  - `p_canonical_person_id IS NULL`
  - `p_expected_version=0`
  - `p_evidence = '{"reason":"not_a_person"}'`
  - en manifestrække `('source_persona_identity', {"source_persona_id": x}, grund 'hel_stroem', forrige_version n)`
    for denne transaktion og backend
  Ellers fejler den med `EVIDENCE_PERSON_PURGE_SHAPE`. Den skriver version n+1, og indholds-uuid'et afledes af
  (x, n+1).
- **Modifies `private.validate_source_persona_identity_event`** (l. 1859). Ved `version ≠ max+1` tillades det kun,
  hvis alle tre holder:
  - der ikke findes events for personaen
  - `NEW.version = forrige_version+1` fra manifestets kvittering
  - `NEW.evidence = '{"reason":"not_a_person"}'`
- **Modifies `red_source_persona_queue`:** `not_a_person` vises som »ikke en person«.

- [ ] **Step 1: Tests:**
  - `purge_oprindelse_form`
  - `purge_oprindelse_kraever_manifest`: uden manifestrække afvises kaldet, også fra en serverfunktion.
  - `purge_version_n_plus_1`: en persona med v1..v3 får efter sletningen kun v4 `rejected`, og uuid'et ≠ det gamle
    v1-uuid.
  - `purge_spaerrer_genoprettelse`: `person_create`, `legacy_match` og `relation_person_create` afviser personaen.
  - `purge_kontrolkoersel_failed`: en `passed` kørsel med x i stikprøven → `control_run_status` giver `failed` ved
    næste evaluering (Q4, forventet).
- [ ] **Step 2-4:** FAIL → implementér → `OK`.
- [ ] **Step 5:** Hovedsessionen committer `feat(sletning): oprindelsen person_purge med version n+1`.

### Task 7: Forhåndsvisningen (V-6, V-8, Q3, Q4, Q8, Q9)

**Files:** `schema.sql`, `db-migrations.sql`, `db-rls.sql`, `tests/sql/test-person-purge.sql`.

**Interfaces:**
- **Produces `public.red_slet_person_helt_preview(p_person_id bigint) RETURNS jsonb`** med nøglerne:
  - `person_id`, `navn`
  - `steder`: sted → sorteret pk-liste, fra `person_purge_plan`
  - `historik`: antal events og sæt
  - `familier_slettes`, `familier_bevares`, `vielser_staar`
  - `samme_som_komponent`
  - `forældes`: narrativer og bindinger hos andre (§6.5)
  - `storage`
  - `blokeringer`, `advarsler`, `til_kontrol`
  - `levende_bruger`
  - `sha256`: over alt det øvrige, kanonisk
- **`blokeringer[].art`:**
  - `link_i_tekst`: slettegraf §4.1, alle kolonner inklusive `note.indhold` og mål af typen family og media.
  - `anden_promotion`: §4.2 med Q5.
  - `aaben_koersel`: §4.3. Blokerer, til kørslen er `passed` eller `failed`; omfatter kandidat, forældrekort og
    eksklusion.
  - `aaben_batch`: §4.4 med de præciserede punkter 2 og 3 og det nye punkt om `publication_identity`.
  - `afventer_kontrol`: §4.5.
  - `samme_som_knudepunkt`: §4.6.
  - `anden_paastand`: S20 og NY-A.
- **`advarsler[].art`:**
  - `fortrydelse_mistes` (Q3): én pr. kørsel og fortrydelsesvej fra »Afgørelser« Q3, der kan fortrydes i dag og ikke
    kan bagefter.
  - `kontrolkoersel_failer` (Q4)
  - `forældede_bindinger` (§6.5)
- **`til_kontrol`** (Q8, Q9): `[{sted, tabel, pk, grund}]` for fritekst-stederne i »Afgørelser« Q9, hvor teksten
  indeholder P's id, P's visningsnavn eller et `Fam`-id. Kun pk og sted, ikke teksten; dialogen henter teksten selv
  med eksisterende læsere.

- [ ] **Step 1: Tests.** Hver blokering oprettes i sin egen kopi.
  - `preview_rollegate_foerst`: med fixturen `fixtures/kalder-matrix.sql` får anon, medlem og redaktør uden rolle
    samme fejl for et eksisterende og et ikke-eksisterende id, og ingen læsning sker før gaten (V-8).
  - `preview_familier`
  - `preview_blokering_link`: én pr. kolonne i §4.1, også `note.indhold`, et `[[family:f]]` til en familie, der
    slettes, og et `[[media:m]]` til et medie, der slettes.
  - `preview_blokering_knudepunkt`
  - `preview_blokering_promotion`: ægtefællens fortolkning er promoveret til dubletfamilien → blokering.
  - `preview_ingen_blokering_egen_promotion_fra_andens_record`: Q5.
  - `preview_blokering_aaben_koersel`: `sealed` blokerer; `passed` og `failed` blokerer ikke; P som kandidat i en
    andens stikprøve blokerer.
  - `preview_blokering_batch`: hvert punkt i §4.4 blokerer.
  - `preview_ingen_blokering_aktiveret_batch`: en aktiveret forælder med et `finalized` name_completion-barn blokerer
    ikke og giver `fortrydelse_mistes`.
  - `preview_til_kontrol`: en note hos `-987654704` med P's navn og en delt medietitel med P's navn står i
    `til_kontrol`.
  - `preview_hash_stabil`: samme hash to gange. Sletter man ét faktum og opretter et andet (samme antal), får man en
    anden hash.
- [ ] **Step 2-4:** FAIL → implementér → `OK`.
- [ ] **Step 5:** Hovedsessionen committer `feat(sletning): forhåndsvisning med blokeringer, advarsler og kontrolliste`.
- [ ] **Step 6: Tidlig måling (»Mindre«).** Hovedsessionen kører previewet for 1791 på prod-kopien med migrationen
  lagt på en **ny** kopi af standin-dumpet. Kun tal og blokerings-arter. Blokerer den, stopper vi og forelægger
  projektejeren, før Task 8.

### Task 8: Sletningen (V-1, V-4, V-8)

**Files:** `schema.sql`, `db-migrations.sql`, `db-rls.sql`, `tests/sql/test-person-purge.sql`.

**Interfaces:**
- Produces: `public.red_slet_person_helt(p_person_id bigint, p_preview_sha256 text) RETURNS jsonb` →
  `{"slettet": P, "storage_antal": n, "personas_afvist": k}`.
- **Forløb:**
  1. Låse L1-L13 (slettegraf §6.2), herunder `PURGE_LOCKSET_DRIFT`.
  2. Preview genberegnes, og hashen sammenlignes.
  3. Blokeringer giver `PURGE_BLOKERET: <art>`.
  4. Manifestet skrives fra `person_purge_plan` og `person_purge_historik`.
  5. Faserne 2a-13 køres (slettegraf §1.1 med Q6-rækker i 2a-2c).
  6. Storage-stier skrives i `private.person_purge_udbakke` (Task 12 laver tabellen; indtil da er det en stub).
  7. Manifestet tømmes.
  8. **Slutkontrol:** `person_purge_plan(P)` og `person_purge_historik(P)` returnerer 0 rækker med handling `slet`,
     ellers `PURGE_REST: <sted>`.
  9. Retur.

- [ ] **Step 1: Tests.** Alle med COMMIT i egen kopi, derefter måling:
  - `purge_count_nul`: `person-purge-count.sql` → 0 for alle steder med handling slet/nulstil/loesn.
  - `purge_rest_kun_tilladt`: `person-purge-rest.sql` for `-987654700` og »Testperson Purge« → kun `tilladt=true`.
  - `purge_andre_uaendrede`: sha256 over alle rækker i alle tabeller, der har en manifestrække, minus manifestets
    mængde og de forventede `loesn`/`nulstil`-kolonner, er ens før og efter. Hashen beregnes uden inventaret: alle
    tabeller i `public` og `private`.
  - `purge_manifest_tomt`, `purge_ingen_ny_historik`: max(id) og antal `change_set`/`change_event` er uændret, bortset
    fra de slettede.
  - `purge_persona_ikke_en_person`: Q7, version n+1.
  - `purge_andres_identitetsevent`: §6.10.
  - `purge_q6_binding`: P's personas binding til den bevarede familie er væk, og ægtefællens er bevaret. Familiens
    bindingstilstand opfører sig som dokumenteret i Task 4 step 4b.
  - `purge_historik_navn_vaek`: ingen `change_set.summary` og ingen `change_event` uden for tilladt rest indeholder
    navnet.
  - `purge_fortryd_bevaret`: `red_fortryd_change_set(<fælles sæt>)` med og uden force fejler lukket eller genskaber
    intet med P's id. Et tidligere sæt, hvis events er slettet, genskaber heller intet.
  - `purge_fortryd_genindsaetter_ikke_link`: fortryd af et bevaret narrativ-sæt, hvis foer-tekst har
    `[[person:P|…]]`, fejler lukket (V-8). Er det ikke muligt, beskriver testen præcist, hvad der sker, og
    hovedsessionen forelægger.
  - `purge_fremmed_saet`, `purge_blokeret`, `purge_hash_aendret`, `purge_delt_medie`, `purge_slutkontrol`: en
    trigger, der tilføjer et faktum på P under sletningen, giver `PURGE_REST`.
- [ ] **Step 2-4:** FAIL → implementér → `OK`.
- [ ] **Step 5:** Hovedsessionen committer `feat(sletning): red_slet_person_helt sletter personen uden rest`.

### Task 9: Id-genbrug (§6.8, V-8)

**Files:** `schema.sql` (`red_fortryd_change_set` l. 9558), `db-migrations.sql`, `tests/sql/test-person-purge.sql`.

- [ ] **Step 1: Test `id_genbruges_ikke`:** for hver af de 8 tabeller i §6.8 (person, narrative, fact, relation,
  assertion, family, media, change_set) gælder: det højeste id slettes helt, og den næste indsættelse får et højere
  id.
- [ ] **Step 2:** FAIL, hvor det gælder.
- [ ] **Step 3:** Grenen i l. 9558, der allokerer med `max+1`, når sekvensen mangler, erstattes af
  `RAISE EXCEPTION 'CHANGE_SET_SEQUENCE_MISSING'`. Den kører netop, når der ingen sekvens er, så en sekvens kan ikke
  være rettelsen (V-8). Bekræft, at v1-narrativskriveren (l. 12648) er død ved kontrakt v2.
- [ ] **Step 4:** `OK`. **Step 5:** Hovedsessionen committer `fix(sletning): ingen id-genbrug efter sletning`.

### Task 10: db-verify (V-8, »Mindre«)

**Files:** `db-verify.sql`, `tests/sql/test-person-purge.sh`.

Asserts:
- `PURGE_MANIFEST_IKKE_TOMT`
- `PURGE_TILLADELSESLISTE_BOGTABEL`: funktionskroppene af de 4 triggerfunktioner indeholder ingen bogtabel.
- `PURGE_MANIFEST_SKRIVER`: kun `red_slet_person_helt` indeholder `INSERT INTO private.person_purge_manifest`.
- `PURGE_INVENTAR_HASH`: md5 af `person_purge_inventar()` er lig en konstant. Den opdateres bevidst ved ændring.
- `IDENTITY_WRITER_LOCK_ORDER_DRIFT`: tilføj `red_slet_person_helt(bigint,text)` til listen ved l. 1758-1767.
- `ID_MAX_PLUS_ONE_ALLOCATOR`: ingen aktiv skrivefunktion allokerer med max+1. Døde v1-veje står på en navngiven
  liste.

- [ ] Kør `tests/sql/run-db-verify-disposable.sql` i harnessen efter en sletning → grøn. Hovedsessionen committer
  `test(sletning): db-verify-vagter for personsletning`.

### Task 11: Samtidighed og opgradering (V-1, V-8)

**Files:** `tests/sql/test-person-purge.sh`.

- [ ] **Step 1: Samtidighed.** Baggrunds-psql og `pg_sleep` i et låst øjeblik, efter mønstret fra
  `test-control-model-v2.sh`:
  - (a) To sletninger af samme person: én lykkes, den anden får `PURGE_FINDES_IKKE` eller `PURGE_PREVIEW_AENDRET`.
  - (b) `red_afgoer_source_persona` på P's persona.
  - (c) En narrativpubliceringsskriver på P's record.
  - (d) `red_record_identity_candidates` for P's kilde.
  - (e) `red_fortryd_change_set` på et fælles sæt.
  (b)-(d) skal serialiseres uden 40P01. (e) må give 40P01 eller fejle lukket (slettegraf §6.2 »Kendt rest«).
- [ ] **Step 2: Opgradering.** Fra `<base>` (Task 3) køres migrationen to gange. Funktionskroppe og ACL for alle nye
  og ændrede funktioner skal være byte-ens mellem frisk og opgraderet base.
- [ ] **Step 3:** `SAMTIDIG_OK`, `UPGRADE_OK`. Hovedsessionen committer `test(sletning): samtidighed og opgradering`.

### Task 12: Udbakke, Storage og Redaktion (spec §6.7, V-5)

**Files:** `schema.sql`, `db-migrations.sql`, `db-rls.sql`, `web/src/data/personPurge.ts` (+ `__tests__`),
`web/src/components/SletHeltDialog.tsx` (+ test), `web/src/data/redaktionWrite.ts`, `web/src/Redaktion.tsx`.

**Interfaces:**
- `private.person_purge_udbakke(bucket text, sti text, oprettet timestamptz, PRIMARY KEY(bucket, sti))`. Den har intet
  person-id. Stierne er indholdsadresserede.
- `public.red_person_purge_udbakke() RETURNS TABLE(bucket text, sti text, oprettet timestamptz)`.
- `public.red_person_purge_udbakke_kvitter(p_bucket text, p_sti text) RETURNS void`.
- Begge har rollegaten først og `GRANT EXECUTE TO authenticated`.
- `executeSletHelt(opts, deps)` følger kontrakten fra `executeUdrens`:
  1. DB først.
  2. Derefter `removeObjects` for udbakkens stier.
  3. Derefter kvittering pr. bekræftet fil.
  4. Fejlede filer bliver stående og vises i Redaktion under »Filer der venter på sletning«, indtil de er væk.
- `SletHeltDialog` viser:
  - navn og id
  - antal pr. sted
  - familier
  - blokeringer; knappen er deaktiveret, så længe der er blokeringer
  - advarsler
  - `til_kontrol` med link til hvert sted
  - tekstfeltet, hvor personens id skal skrives
  - »Slet helt (kan ikke fortrydes)«
  - at det er den rå profil, ikke den sammenfoldede

- [ ] **Step 1: Tests (vitest):**
  - dryRun-regressionen (PR #72)
  - en Storage-fejl giver en advarsel og ingen kvittering
  - en gentaget kørsel fjerner resten
  - knappen er deaktiveret ved blokering og ved forkert id
  - advarsler og `til_kontrol` vises
  - SQL: udbakken har ingen person-reference (katalogvagten), og kvittering kræver rolle
- [ ] **Step 2-4:** FAIL → implementér → `npm run test -w web`, `npm run build -w web` og SQL-harnessen er grønne.
  Mobilens typer røres ikke.
- [ ] **Step 5:** Hovedsessionen committer `feat(redaktion): »Slet helt« med forhåndsvisning, udbakke og kvittering`.

### Task 13: Generalprøver, runner og runbook (hovedsessionen)

**Files:** Create `docs/runbooks/personsletning-prod.md`. Hovedsessionen skriver runneren
`~/.private/5ab-overfoersel/42-personsletning.sh` (aldrig en subagent).

- [ ] **Step 1: Generalprøve 1 (1791).**
  - Restore det seneste prod-dump med `ANALYZE` og kør migrationen to gange + rls.
  - Som redaktør: preview og sletning af 1791, med målt tid under `authenticated`-rollens faktiske
    `statement_timeout` (læs den i prod; Supabase-standard er 8 s).
  - `person-purge-count.sql` giver 0, og `person-purge-rest.sql` finder kun tilladt rest.
  - Hash over ikke-slettede rækker er ens.
  - Hele `db-verify.sql` er grøn.
- [ ] **Step 2: Generalprøve 2 (advisor).** På en **ny** kopi: slet én person fra den aktiverede kørsel 18/8. Den
  person vælges ved tal, ikke ved navn.
  - Previewet viser `fortrydelse_mistes`.
  - Sletningen lykkes.
  - `db-verify.sql` er grøn; i dag har den intet assert på `expected_counts`.
  - Et tørt kald af `red_reverse_reimport` for kørslen fejler lukket med `REIMPORT_WRITER_REVERSAL_INVALID`, i en
    transaktion med ROLLBACK.
- [ ] **Step 3: Runbook.**
  - GO-koder, dump før DDL, `apply-ddl`, `maal`, `fortryd-ddl`.
  - **Et nyt dump umiddelbart før projektejerens sletning af 1791.**
  - Fortryd-DDL kan **ikke** fortryde en udført sletning; kun dumpet kan.
  - Projektejeren sletter 1791 i Redaktion.
  - Udbakken skal være tom eller vist. `Rscript R/media-janitor.R` viser 0 forældreløse for de returnerede stier.
  - Færdigbevis efter spec §7.
- [ ] **Step 4:** Hovedsessionen committer `docs(sletning): runbook og generalprøvetal`.
