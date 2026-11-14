# Fuld personsletning — implementeringsplan (v2.1)

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
- Review, plan v2: `docs/superpowers/plans/personsletning/fable-planreview-v2.md`. Fundene hedder K2-1..K2-2,
  V2-1..V2-8 og M2-1..M2-9; alle er rettet i denne udgave (v2.1).
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
- **Eksisterende funktioner rettes, hvor de står** (V2-6). Det gælder de 4 triggerfunktioner,
  `decide_source_persona_identity`, `validate_source_persona_identity_event` og `red_fortryd_change_set`. I
  `schema.sql` er de defineret én gang; der må aldrig komme en ekstra definition (en konkurrerende definition
  degraderer lydløst). Det er lovligt, at de kalder funktioner, der står sidst i filen, fordi plpgsql binder sent.
  I migrationsblokken oprettes manifest, `person_purge_tilladte_tabeller()` og `person_purge_tilladt` **før**
  `CREATE OR REPLACE` af de ændrede funktioner.
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
  efter kilde-id. **L8 er `LOCK TABLE public.change_set IN SHARE ROW EXCLUSIVE MODE`** (V2-5), ikke ROW EXCLUSIVE.
  Så venter sletningen på versionerede skrivere, der allerede er i gang, og nye venter på sletningen. Samme tilstand
  bruges allerede ved l. 14359.
- **Eksistensvagt** (V2-5). En ny trigger `private.validate_polymorf_subjekt_findes` sidder på `fact`, `note`,
  `narrative`, `story`, `suggestion` og `relation` (begge ender). Den afviser INSERT og UPDATE af subjekt eller mål,
  når typen er `person` eller `family`, og rækken ikke findes. Den låser rækken med `FOR KEY SHARE`, og funktionen er
  SECURITY DEFINER, så låsen ikke kræver UPDATE-ret hos kalderen.
  - Mønstret er `validate_entity_description_subject` (l. 11967).
  - Målt på prod-kopien 14/11: 0 forældreløse rækker i alle seks tabeller, så vagten kan indføres uden dataretning.
  - Den lukker for en skrivning fra en forældet redaktørside efter sletningen og for skrivere, der ikke åbner et
    `change_set`.
- **Fejlkoder:** `PURGE_FREMMED_CHANGE_SET`, `PURGE_PREVIEW_AENDRET`, `PURGE_BLOKERET: <art>`, `PURGE_FINDES_IKKE`,
  `PURGE_LOCKSET_DRIFT` (slettegrafens `PERSON_PURGE_LOCKSET_DRIFT` hedder dette; M2-6), `PURGE_REST: <sted>`
  (slutkontrol), `EVIDENCE_PERSON_PURGE_SHAPE`, `POLYMORF_SUBJEKT_FINDES_IKKE`, `FORTRYD_DOED_LINK`.
- **Tilladt rest.** Testenes navngivne liste er præcis denne; alt andet er en fejl:
  - P's id-nummer i andres rækker: S11c, S23b, S32c, S41b, S43b, S45b, S46, S48, S49c, S50, NY-C, S57, S52b, og
    andres bindinger i S39c.
  - Bogtekst med P's navn i:
    - S44a `authorized_elements` (Q1)
    - andres narrativ- og notehistorik og publiceringstilstande (K2/Q2)
    - et delt medies titel (K3/Q8)
    - vielsesfakta i bevarede familier (K5, beslutning 7)
  - Fritekst på Q9-stederne (slettegrafens »Afgørelser« Q9), **men kun når rækken stod i forhåndsvisningens
    `til_kontrol`** (V2-3). Testen kræver, at hvert restfund på et Q9-sted svarer til en `til_kontrol`-post.
  - Bogens lag.
- **Testdata** (K2-1).
  - Testpersonerne oprettes af de rigtige skrivere eller af eksisterende fixtures og får derfor positive sekvens-id'er.
    `parse_mentions` (l. 9629) kender kun ikke-negative id'er, og ledger-kæder kan kun bygges af skriverne.
  - Id'erne gemmes i en testtabel `purge_test.ids(rolle text PRIMARY KEY, id bigint)` med rollerne `P`, `aegtefaelle`,
    `barn`, `nabo`, `tredje`, `anden_partner`. Tests og målere slår op der.
  - Navnene er syntetiske (»Testperson Purge«).
  - Ingen PII i testoutput, commits eller logs. Mod prod-kopier printes kun tal.
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
8. **En skrivning om P under eller efter sletningen** (`red_upsert_fakta` fra en forældet side). Forventet: den
   ventes ud eller afvises af eksistensvagten (Task 8 og Task 11 f).
9. **Fortryd genskaber et dødt link** i en andens tekst. Forventet: `FORTRYD_DOED_LINK` (Task 9).

---

## Filstruktur

| Fil | Ansvar |
|---|---|
| `schema.sql` (sidste sektion »FULD PERSONSLETNING«) | inventar, undtagelser, tilladte tabeller, plan- og historikfunktioner, manifest, udbakke, eksistensvagt, preview, sletning |
| `schema.sql` (på stedet, én definition hver; V2-6) | 4 triggerfunktioner (l. 916, 4063, 9297, 13997), `validate_source_persona_identity_event` (l. 1859), `red_fortryd_change_set` (l. 9484), `decide_source_persona_identity` (l. 10404) |
| `web/src/data/sourcePersona.ts` | etiketten »ikke en person« (Task 6) |
| `docs/superpowers/plans/personsletning/analyse-binding-og-fortrydelse.md` | leverance fra Task 4 step 4b/4c |
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

### Task 1: Uafhængig måler (V-4, V2-4)

**Files:** Create `tests/sql/person-purge-count.sql`, `tests/sql/person-purge-rest.sql`.

- [ ] **Step 1:** Kopiér `docs/superpowers/plans/personsletning/count.sql` til `tests/sql/person-purge-count.sql` og ret
  de tre huller fra slettegrafens »Afgørelser«:
  - `coalesce(efter,foer)` → `foer` og `efter` hver for sig (slettegraf §2.1).
  - Feed-pin-formaterne fra NY-B tilføjes.
  - S46 via kandidat-uuid'er (`candidate.id WHERE candidate_person_id=P`), ikke regex.
  Output: én række pr. sted (`sted`, `tabel`, `antal`), kun tal. Den læser **ikke** inventaret.
- [ ] **Step 2:** Skriv `tests/sql/person-purge-rest.sql`. Den har to tilstande.
  - **`mode=fixture`** (testbaser):
    - For hver tabel i `public` og `private` (fra `pg_class`, ikke fra inventaret) tælles rækker, hvor `row::text`
      indeholder `[[person:<pid>|`, `navn` eller `pid` som helt tal-token.
    - Output pr. tabel: `antal`, og `tilladt` fra en navngiven liste med sted-nummer og begrundelse, præcis Global
      Constraints' »Tilladt rest«.
  - **`mode=prod`** (prod-kopier og prod):
    - Et tal-token rammer også årstal og andre id'er. For 1791 er det målt i 6 `assertion`-, 3 `fact`- og 68
      `change_event`-rækker. Derfor bruges tokenet ikke alene.
    - Skriv **før**-tallene pr. tabel for tal-token, `navn` og `[[person:<pid>|` til en fil.
    - Efter sletningen kræves for hver tabel: efter ≤ før.
    - Kræv, at faldet for tal-token er lig planens antal for tabellen, eller forklar det i rapporten med
      sted-nummer.
    - Kræv, at navn og link-token kun står tilbage på tilladte steder.
  - Kun tal; intet rækkeindhold.
- [ ] **Step 3:** Kør begge mod prod-kopien `daa5ab_ddl_standin_20261113220424_g3` for `pid=1791` (læse-kun, kun tal;
  `person-purge-rest.sql` i `mode=prod`, kun før-delen). Gem tallene i task-rapporten. Forventning: count-tallene
  matcher spec §7's måling (17 steder). Afviger de, står forklaringen i rapporten.
- [ ] **Step 4:** Hovedsessionen committer `test(sletning): uafhængig tæller og restsøgning for personspor`.

### Task 2a: Fixture — kerne, familier og historik (V-9, K2-1, V2-2)

**Files:** Create `tests/sql/fixtures/person-purge.sql` (kernedelen), `tests/sql/test-person-purge.sh` (skabelon og
gruppekopier).

- [ ] **Step 1: Personerne.** Personerne oprettes med de rigtige skrivere, og deres id'er skrives i
  `purge_test.ids`:
  - `P` (»Testperson Purge«)
  - `aegtefaelle`: dubletfamilie med P og uden børn → familien slettes
  - `barn` og `anden_partner`: familie med P, `anden_partner` og `barn` → bevares med vielse
  - `nabo`: én `samme_som`-nabo
  - `tredje`: uden forbindelse
  Byg P's kernespor med `red_*`-skrivere:
  - fakta, påstande, citater, konklusioner, noter og relationer, inklusive en med fact-ende
  - narrativ, stories, beskrivelser, forslag og hændelser
  - et feed-pin i hvert nøgleformat, også NY-B
  - et delt medie og et eksklusivt medie
  - bogmærke, `profiles`-binding, `person_external_id` med `import_korrektion` og `slaegtsnavn_karantaene`
- [ ] **Step 2: Historik fabrikeres** med direkte `INSERT` i `change_set`/`change_event` og P's rigtige id i
  `row_pk`/`foer`/`efter`:
  - et `red_opret_person`-sæt med summary `'Oprettede person Testperson Purge'` og dets fortryd-sæt
  - et `red_opret_union`-sæt med P som subjekt og ægtefællens events
  - et fortryd-sæt for et sæt, der bevares
  - et fælles sæt med en `narrative_publication_event`-FK (laves i Task 2b)
  - et `withdraw_legacy_narrative`-sæt uden events, med fritekst i summary
  - tidligere slettede rækker, der kun findes i `change_event.foer`: et faktum, en relation, et narrativ og en
    `assertion` med `citation`
  - en `UPDATE` på en note, hvis `target_id` flyttede væk fra P
  - en `feed_pin` med `embede:P:…`
  - en note hos `tredje`, hvis `foer`-tekst har `[[person:P|Testperson Purge]]` (til Task 9)
- [ ] **Step 3: Forventet slettemængde** (V2-2). Fixturen skriver ved opbygningen sin egen facitliste
  `purge_test.forventet(tabel text, pk jsonb, handling text)`. Listen bygges fra de id'er, skriverne returnerede, ikke
  fra en planfunktion. Den bruges i Task 4 (`plan_lig_facit`) og Task 8 (`purge_andre_uaendrede`).
- [ ] **Step 4: Harnessen.**
  - Skabelonbasen bygges som i `tests/sql/test-6e2-etiket.sh`: `evidence-promotion-bootstrap.sql` + `schema.sql` +
    `db-rls.sql` (M2-8), derefter fixturen. Hver testgruppe får sin egen kopi med `createdb -T`. Sletninger
    committer i deres egen kopi, fordi udskudte triggere ikke kører ved ROLLBACK (V-4).
  - Harnessen tager argumenterne `<præfiks> [<base-commit>]`. Uden base-commit kører den kun frisk-delen og skriver
    `FRISK_OK`. Opgraderingsdelen kommer i Task 11.
  - Harnessen må kun droppe baser, den selv har oprettet i samme kørsel, med det præfiks den fik som argument.
- [ ] **Step 5:** Kør `bash tests/sql/test-person-purge.sh t_purge_t2a` → `FRISK_OK`. Hovedsessionen committer
  `test(sletning): fixture for kerne, familier og historik`.

### Task 2b: Fixture — ledgers og identitet (V-9, K2-1)

**Files:** `tests/sql/fixtures/person-purge.sql` (ledgerdelen).

- [ ] **Step 1:** Byg P's ledger-spor med de eksisterende fixtures og skrivere, så valideringstriggerne er glade:
  - `fixtures/publication-identity.sql` og `publication-persona.sql`: identitet og publicering.
  - `relation-*.sql` og `relation-persona-reuse-helpers.sql`: promotions, `relation_reopen` og
    `text_revision_reconciliation`.
  - `marriage-ordinal-244.sql`.
  Sporene skal dække hvert slet-/nulstil-/loesn-sted i slettegrafen, plus:
  - `Prom_egen_fam` (Q6)
  - P's egen persona med tre events, hvor den ældste er `accepted → tredje`, før den blev koblet til P (K-3,
    `hel_stroem`, V2-1)
  - en `Y`-persona med v1 `accepted → P` og v2 `accepted → tredje` (§6.10)
  - et forældrekort med `counterpart_person_id=P`
  - en `reimport_event`-kæde, hvis en skriver kan lave den
- [ ] **Step 2: Test `fixture_daekker_slettegraf`.** `tests/sql/person-purge-count.sql` med `pid=P` giver `antal > 0`
  for hvert slet-/nulstil-/loesn-sted.
  - Undtaget er steder på en navngiven liste `kan_ikke_forekomme`, hvor hver linje har en begrundelse. S9 hører der,
    fordi kvitteringen forbruges.
  - **Hver linje på listen godkendes af hovedsessionen.** En implementer må ikke selv tilføje en linje, men skal
    stoppe og rapportere.
- [ ] **Step 3:** `bash tests/sql/test-person-purge.sh t_purge_t2b` → `OK fixture_daekker_slettegraf`, `FRISK_OK`.
  Hovedsessionen committer `test(sletning): fixture for ledgers og identitet`.

### Task 3: Inventar og katalogvagt pr. kolonne (K-1, K-4, V-7, K2-2)

**Files:** `schema.sql`, `db-migrations.sql`, `db-rls.sql`, `tests/sql/test-person-purge.sql`, `.github/workflows/ci.yml`.

**Interfaces:**
- Produces: `private.person_purge_inventar() RETURNS TABLE(sted text, tabel text, kolonner text[], handling text,
  fase text, grund text)`.
  - Implementeres som `VALUES` med én række pr. sted i slettegrafen, inklusive bevar_andres og blokér.
  - `handling` ∈ {`slet`,`nulstil`,`loesn`,`bevar_andres`,`blokér`,`ingen`}, `fase` som i slettegraf §1.1.
  - `grund` ∈ {`egen`,`hel_stroem`,`andres_ref`,`afledt`,`familie`} eller NULL. Historikken har ingen
    append-only-trigger og får derfor ingen grund (M2-4).
- Produces: `private.person_purge_undtagelser() RETURNS TABLE(tabel text, kolonne text, begrundelse text)` (VALUES).
  `kolonne='*'` undtager en hel tabel, men er **kun** tilladt for bogens lag og rene opslagstabeller (fx `vocab`).
- Produces: `private.person_purge_kandidatkolonner() RETURNS TABLE(tabel text, kolonne text, art text)` (K2-2).
  - Kandidat er **enhver** kolonne i `public` og `private` af typerne `bigint`, `integer`, `uuid`, `text`, `jsonb`
    eller arrays af dem.
  - FK, type/id-par og navn bruges kun til at sætte `art`, ikke til at afgøre, om kolonnen er kandidat.
  - Omfang (målt): ca. 143 bigint, 71 integer, 162 uuid, 335 text og 55 jsonb.
  - Syv kendte rene `bigint`-person- eller familiekolonner uden FK skal stå i inventaret:
    - `reimport_event.canonical_person_id`
    - `reimport_name_completion_result.person_id`
    - `legacy_placement_disposition.person_id`
    - `identity_control_parent_card.counterpart_person_id` og `.family_id`
    - `relation_reopen.from_family_id` og `.to_family_id`
    - `marriage_ordinal_correction.family_id`

**Vagtregel:** hver kandidatkolonne står enten i et inventarsteds `kolonner` for samme tabel eller i
`person_purge_undtagelser`. **Senere tasks** (5, 8, 12), der opretter tabeller, opdaterer undtagelseslisten eller
inventaret i samme task (V2-7).

- [ ] **Step 1: Tests (skal fejle):**
  - `inventar_daekker_katalog`: vagtreglen; fejlbeskeden lister umatchede `(tabel, kolonne)`.
  - `vagt_ny_tabel`: en midlertidig `public.tmp_purge_vagt(person_id bigint)` uden FK får vagten til at fejle.
  - `vagt_ny_kolonne`: `ALTER TABLE public.story ADD COLUMN tmp_person bigint` får vagten til at fejle.
  - Begge midlertidige objekter oprettes og fjernes i testgruppens egen kopi.
  - `inventar_ingen_bogtabel`: ingen række med handling `slet`/`nulstil`/`loesn` har en tabel fra bogens lag.
  - `inventar_svarer_til_slettegraf`: hvert S-/NY-/M-nummer i slettegrafen findes i inventaret, og omvendt. Listen
    over numre står i testen.
  - `undtagelse_hel_tabel_kun_bog`: `kolonne='*'` forekommer kun for tabeller på bog- og opslagslisten.
- [ ] **Step 2:** Kør → FAIL (`function private.person_purge_inventar() does not exist`).
- [ ] **Step 3:** Implementér. Tilføj CI-trinnet `bash tests/sql/test-person-purge.sh ciperson_purge` uden
  base-commit efter `test-6e2-upgrade`. Base-commit tilføjes i Task 11.
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
  - `plan_lig_facit` (V2-2): planens mængde for slet/nulstil/loesn er lig `purge_test.forventet`.
  - `historik_tidligere_slettet`: `E` indeholder events for det tidligere slettede faktum, den slettede relation,
    det slettede narrativ og den slettede påstand med citation.
  - `historik_flyttet_note`: `E` indeholder note-eventet, hvis `foer` pegede på P.
  - `historik_withdraw_saet`: `D` indeholder `withdraw_legacy_narrative`-sættet.
  - `historik_fortryd_bevaret`: fortryd-sættet for det bevarede sæt er **ikke** i `D`.
  - `historik_faelles_bevaret`: union-sættet er ikke i `D`; dets P-events er i `E`.
- [ ] **Step 2:** Kør → FAIL. **Step 3:** Implementér. **Step 4:** Kør → `OK`.
- [ ] **Step 4b (Q6). Leverance:** `docs/superpowers/plans/personsletning/analyse-binding-og-fortrydelse.md`, del 1.
  - Læs `relation_binding_state` (l. 20004) og familiebekræftelsen (`red_corroborate_family_identities` l. 19948).
  - Beskriv med linjehenvisninger, hvad der sker med en bevaret familie, når én af dens bindinger forsvinder.
  - Lav en SQL-test (`binding_forsvinder`) på fixturen, der viser det.
  - **Færdig**, når adfærden er beskrevet og testet. Forventet: bindingen bliver forældet og kan genåbnes; der kommer
    ingen fejl. Ved anden adfærd stopper hovedsessionen og forelægger projektejeren.
- [ ] **Step 4c (Q3). Leverance:** samme fil, del 2, med én tabel pr. fortrydelsesvej:
  - Vejene er `red_reverse_reimport` l. 5933, `red_reverse_1939_v50_reimport` l. 6283, `red_reverse_reimport_cases`
    l. 13288 og `red_reverse_reimport_publication` l. 18672.
  - For hver vej: hvornår en kørsel kan fortrydes i dag (status og tællinger), hvilke af P's rækker der får den til at
    fejle bagefter, og et SQL-prædikat, Task 7 kan bruge til `fortrydelse_mistes`.
  - **Færdig**, når hver vej har et prædikat og en test på fixturen eller en begrundet note om, at vejen ikke kan
    forekomme for en person.
- [ ] **Step 5:** Hovedsessionen committer `feat(sletning): planfunktion og historiklukning`.

### Task 5: Manifest og snævert løft af append-only (K-3, V-3)

**Files:** `schema.sql`, `db-migrations.sql`, `db-rls.sql`, `tests/sql/test-person-purge.sql`.

**Interfaces:**
- Produces: `private.person_purge_manifest(xid xid8, backend_pid int, person_id bigint, tabel text, pk jsonb, grund
  text NOT NULL, forrige_version int, PRIMARY KEY (xid, backend_pid, tabel, pk))`, RLS on, ingen grants.
- Produces: `private.person_purge_tilladt(p_tabel text, p_old jsonb) RETURNS boolean` (SECURITY DEFINER). Den er sand,
  når alle tre holder:
  - Manifestet har rækken for `(pg_current_xact_id(), pg_backend_pid(), p_tabel, pk)`.
  - `p_tabel` er med i `private.person_purge_tilladte_tabeller()` (VALUES; V2-8). Triggerfunktionerne og db-verify
    læser den samme funktion.
  - Det uafhængige tjek for rækkens `grund` holder (slettegraf §3.2, med Q5-rettelsen fra »Afgørelser«).
- **`hel_stroem` (V2-1).** `forrige_version` står **kun** på state-rækkens manifestpost (`tabel =
  'source_persona_identity'`, pk `{"source_persona_id": x}`). Event-rækkens tjek slår den post op og kræver tre ting:
  - Personaens state peger stadig på manifestets person.
  - `OLD.version <= forrige_version`.
  - Der findes ingen event med `version > forrige_version`.
  Tjekket må **ikke** sammenligne med `max(version)`. En `BEFORE DELETE`-rækketrigger ser de rækker, samme sætning
  allerede har slettet, så resultatet ville afhænge af sletterækkefølgen.
- **`familie` (M2-4).** Bruges til `narrative_publication_event` for et familienarrativ, hvis familie står i manifestet
  som `family`-række. Målt i dag: 0 familienarrativer.
- **Tilladelseslisten** består kun af tabeller med handling `slet` og en append-only-vagt: S11a/b, S12, S23, S39a,
  `Prom_egen_fam`, S40, S41a, S42, S43a, S45a, M5, S49a, S49b.
- Modifies **kun**:
  - `private.reject_evidence_mutation` (l. 916)
  - `private.reject_reimport_writer_mutation` (l. 4063)
  - `private.reject_reimport_case_event_mutation` (l. 9297)
  - `private.reject_narrative_publication_event_mutation` (l. 13997)
- **Formen** (V-3):
  - Trinvise `IF` før den eksisterende afvisning:
    `IF TG_OP='DELETE' AND TG_LEVEL='ROW' AND TG_TABLE_SCHEMA='private' THEN IF private.person_purge_tilladt(…)
    THEN RETURN OLD; END IF; END IF;` (M2-2). Tilladelseslisten tjekkes inde i `person_purge_tilladt`.
  - Ingen ændring for TRUNCATE eller UPDATE.
  - Afvisningsteksten (`EVIDENCE_APPEND_ONLY` m.fl.) skal være uændret for enhver rolle, der får den i dag. db-verify
    l. 2623-2637 er grøn; ingen rolle må få »permission denied« i stedet.

- [ ] **Step 1: Tests:**
  - `manifest_uden_raekke_afvises`
  - `manifest_tillader_egen_raekke` (COMMIT i egen kopi)
  - `manifest_anden_person_afvises`
  - `manifest_anden_backend`
  - `manifest_forkert_grund`: `egen` på en `hel_stroem`-række med `canonical_person_id` = en anden afvises.
  - `hel_stroem_tillader_null_og_anden`: P's personas ældre events med NULL og med `tredje` slettes, når state
    peger på P (K-3).
  - `hel_stroem_faldende_orden` (V2-1): v3, v2 og v1 slettes i faldende orden i ét DELETE og i tre DELETE; begge
    lykkes. En manifestpost med `forrige_version` = 2, mens v3 findes, afvises.
  - `bogtabel_altid_afvist`: en `source_record`- og en `interpretation`-række i manifestet afvises.
  - `update_uaendret_forbudt`
  - `truncate_uaendret`
  - `afvisningstekst_uaendret` (M2-1): som ejer uden manifest giver DELETE i hver tilladt tabel samme fejltekst som
    før. Ingen klientrolle har `USAGE` på `private` eller DELETE på tabellerne. db-verify l. 2623-2637 forbliver
    grøn.
  - Opdatér katalogvagtens inventar eller undtagelser for manifestet (V2-7).
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
- **Web (M2-7):** køen returnerer `evidence->>'reason'` råt (l. 11046). Teksten »ikke en person« for `not_a_person`
  sættes i `web/src/data/sourcePersona.ts` (+ dens test). SQL'en ændres ikke.
- **Testform (V2-7):** sletningen findes først i Task 8. Testene her simulerer den: de skriver manifestrækker med
  hånden og sletter strømmen i samme transaktion. Ende-til-ende-testen ligger i Task 8
  (`purge_persona_ikke_en_person`).

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
  - `fortrydelse_mistes` (Q3): én pr. kørsel og fortrydelsesvej, ud fra prædikaterne i Task 4 step 4c.
  - `kontrolkoersel_failer` (Q4)
  - `forældede_bindinger` (§6.5)
- **`til_kontrol`** (Q8, Q9): `[{sted, tabel, pk, grund}]` for fritekst-stederne i »Afgørelser« Q9, hvor teksten
  indeholder P's id, P's visningsnavn eller et `Fam`-id. Kun pk og sted, ikke teksten; dialogen henter teksten selv
  med eksisterende læsere.

- [ ] **Step 1: Tests.** Hver blokering oprettes i sin egen kopi.
  - `preview_rollegate_foerst`: med fixturen `fixtures/kalder-matrix.sql` får `authenticated` som medlem og som
    bruger uden rolle samme fejl for et eksisterende og et ikke-eksisterende id. anon får `permission denied` uanset
    id (ingen EXECUTE). Begge er ens for de to id'er, så der er intet oracle.
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
  - `preview_til_kontrol` (V2-3): en tekst med P's navn på **hvert** Q9-sted kommer med i `til_kontrol`:
    - note hos `tredje`
    - delt medietitel
    - S34b
    - S44b
    - `parent_event.note`
    - S49c `evidence`
    - en S58-kolonne
    - en `Y`-event-note
    - vielsestekst i en bevaret familie
    Et sted, der ikke kan bygges i fixturen, står på Task 2b's `kan_ikke_forekomme`-liste.
  - `preview_hash_stabil`: samme hash to gange. Sletter man ét faktum og opretter et andet (samme antal), får man en
    anden hash.
- [ ] **Step 2-4:** FAIL → implementér → `OK`.
- [ ] **Step 5:** Hovedsessionen committer `feat(sletning): forhåndsvisning med blokeringer, advarsler og kontrolliste`.
- [ ] **Step 6: Tidlig måling (»Mindre«, M2-3).** Hovedsessionen kører previewet for 1791 på prod-kopien med
  migrationen lagt på en **ny** kopi af standin-dumpet.
  - Mål tiden. Planfunktionen kører tre gange i sletningen: preview, genberegning og slutkontrol.
  - Kun tal og blokerings-arter.
  - Blokerer den, eller tager previewet mere end en tredjedel af `authenticated`-rollens timeout, stopper vi og
    forelægger projektejeren, før Task 8.

### Task 8: Sletningen (V-1, V-4, V-8)

**Files:** `schema.sql`, `db-migrations.sql`, `db-rls.sql`, `tests/sql/test-person-purge.sql`.

**Interfaces:**
- Produces: `private.person_purge_udbakke(bucket text, sti text, oprettet timestamptz, PRIMARY KEY(bucket, sti))` med
  RLS on og ingen grants (flyttet fra Task 12; V2-7). Den har intet person-id; stierne er indholdsadresserede.
- Produces: eksistensvagten `private.validate_polymorf_subjekt_findes` og dens triggere (Global Constraints, V2-5).
- Produces: `public.red_slet_person_helt(p_person_id bigint, p_preview_sha256 text) RETURNS jsonb` →
  `{"slettet": P, "storage_antal": n, "personas_afvist": k}`.
- **Forløb:**
  1. Låse L1-L13 (slettegraf §6.2, L8 som `SHARE ROW EXCLUSIVE`), herunder `PURGE_LOCKSET_DRIFT`.
  2. Preview genberegnes, og hashen sammenlignes.
  3. Blokeringer giver `PURGE_BLOKERET: <art>`.
  4. Manifestet skrives fra `person_purge_plan` og `person_purge_historik`.
  5. Faserne 2a-13 køres (slettegraf §1.1 med Q6-rækker i 2a-2c).
  6. Storage-stier skrives i `private.person_purge_udbakke`.
  7. Manifestet tømmes.
  8. **Slutkontrol:** `person_purge_plan(P)` og `person_purge_historik(P)` returnerer 0 rækker med handling `slet`,
     ellers `PURGE_REST: <sted>`.
  9. Retur.

- [ ] **Step 1: Tests.** Alle med COMMIT i egen kopi, derefter måling:
  - `purge_count_nul`: `person-purge-count.sql` → 0 for alle steder med handling slet/nulstil/loesn.
  - `purge_rest_kun_tilladt`: `person-purge-rest.sql` (`mode=fixture`) for P og »Testperson Purge« → kun
    `tilladt=true`. Hvert restfund på et Q9-sted svarer til en `til_kontrol`-post fra previewet (V2-3).
  - `purge_andre_uaendrede` (V2-2): sha256 over **alle** rækker i **alle** tabeller i `public` og `private` er ens før
    og efter, med to undtagelser:
    - rækkerne i fixturens facitliste `purge_test.forventet`
    - en navngiven liste over forventede ændringer hos naboerne: `loesn`/`nulstil`-kolonner og `person.visning_*`
      for naboerne
    Hverken manifestet eller planfunktionen bruges til at afgrænse.
  - `eksistensvagt` (V2-5): efter sletningen afvises `red_upsert_fakta('person', P, …)`, en note på P, en story på P
    og et forslag på P med `POLYMORF_SUBJEKT_FINDES_IKKE`. Det samme gælder for en slettet familie.
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
  - `purge_fremmed_saet`, `purge_blokeret`, `purge_hash_aendret`, `purge_delt_medie`.
  - `purge_slutkontrol`: en midlertidig testtrigger, der tilføjer et faktum på P under sletningen, giver
    `PURGE_REST`.
  - Opdatér katalogvagtens inventar eller undtagelser for udbakken (V2-7).
- [ ] **Step 2-4:** FAIL → implementér → `OK`.
- [ ] **Step 5:** Hovedsessionen committer `feat(sletning): red_slet_person_helt sletter personen uden rest`.

### Task 9: Id-genbrug og fortryd uden døde links (§6.8, V-8, M2-5, M2-9)

**Files:** `schema.sql` (`red_fortryd_change_set` l. 9484-9620), `db-migrations.sql`, `tests/sql/test-person-purge.sql`.

- [ ] **Step 1: Tests.**
  - `id_genbruges_ikke` (regressionsvagt, M2-9). For hver af de 8 tabeller i §6.8 (person, narrative, fact, relation,
    assertion, family, media, change_set) slettes det højeste id helt, og den næste indsættelse skal få et højere
    id. Alle 8 tabeller har allerede identity, og sekvensgulvet er monotont, så testen forventes grøn uden ændring.
  - `fortryd_doed_link` (M2-5). `red_fortryd_change_set` på sættet, hvor `tredje`s note har
    `[[person:P|Testperson Purge]]` i `foer`, kaldes efter sletningen, med og uden force. Resultat:
    `FORTRYD_DOED_LINK`, og intet er ændret.
- [ ] **Step 2:** FAIL for `fortryd_doed_link`.
- [ ] **Step 3:** Grenen i l. 9558, der allokerer med `max+1`, når sekvensen mangler, erstattes af
  `RAISE EXCEPTION 'CHANGE_SET_SEQUENCE_MISSING'`. Den kører netop, når der ingen sekvens er, så en sekvens kan ikke
  være rettelsen (V-8). Bekræft, at v1-narrativskriveren (l. 12648) er død ved kontrakt v2.
  `red_fortryd_change_set` afviser med `FORTRYD_DOED_LINK`, hvis en tekst, den vil genskabe i `note.indhold`,
  `story.titel`/`tekst`, `entity_description.tekst` eller `suggestion`, har et `parse_mentions`-mål af typen person,
  family eller media, der ikke findes. Narrativer afvises allerede ved kontrakt v2 (l. 9500-9527).
- [ ] **Step 4:** `OK`. **Step 5:** Hovedsessionen committer `fix(sletning): fortryd genskaber ingen døde links; id-genbrugsvagt`.

### Task 10: db-verify (V-8, »Mindre«)

**Files:** `db-verify.sql`, `tests/sql/test-person-purge.sh`.

Asserts:
- `PURGE_MANIFEST_IKKE_TOMT`
- `PURGE_TILLADELSESLISTE_BOGTABEL`: `private.person_purge_tilladte_tabeller()` indeholder ingen bogtabel (V2-8).
  Funktionskroppene scannes ikke, for `reject_reimport_writer_mutation` nævner allerede `reimport_writer_profile`
  (l. 4066).
- `POLYMORF_SUBJEKT_FORAELDRELOES`: 0 rækker i `fact`, `note`, `narrative`, `story`, `suggestion` og `relation` med
  subjekt eller mål af typen person eller family, der ikke findes (V2-5).
- `PURGE_MANIFEST_SKRIVER`: kun `red_slet_person_helt` indeholder `INSERT INTO private.person_purge_manifest`.
- `PURGE_INVENTAR_HASH`: md5 af `person_purge_inventar()` er lig en konstant. Den opdateres bevidst ved ændring.
- `IDENTITY_WRITER_LOCK_ORDER_DRIFT`: tilføj `red_slet_person_helt(bigint,text)` til listen ved l. 1758-1767.
- `PURGE_LOCK_ORDER` (M2-6): i kroppen af `red_slet_person_helt` står L1-L13 i rækkefølge. Kontrollen er
  tekstpositioner af `lock_reimport_writer`, `daa-identity-candidates`, `FOR UPDATE` på persona, `samme_som_mutation`,
  `SHARE ROW EXCLUSIVE`, `lock_identity_people` og `lock_family_rows`.
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
  - (e) `red_fortryd_change_set` på et fælles sæt, der indeholder en FK-løs række om P, fx et faktum på P. Bagefter
    giver tællingen 0 (V2-5).
  - (f) `red_upsert_fakta('person', P, …)` samtidig med sletningen, i begge rækkefølger:
    - Skrivningen starter først: sletningen venter ved L8, ser bagefter faktummet i genberegningen og afviser med
      `PURGE_PREVIEW_AENDRET`.
    - Sletningen starter først: skrivningen venter og afvises med `POLYMORF_SUBJEKT_FINDES_IKKE`.
  (b)-(d) og (f) skal serialiseres uden 40P01. (e) må give 40P01 eller fejle lukket (slettegraf §6.2 »Kendt rest«),
  men må aldrig efterlade en række om P.
- [ ] **Step 2: Opgradering.** Base-commit er `ac194bfd`, som 6e2-harnesserne bruger; skemafilerne er uændrede derfra
  til `c41f67db`. Migrationen køres to gange på den gamle base. Funktionskroppe og ACL for alle nye og ændrede
  funktioner skal være byte-ens mellem frisk og opgraderet base. CI-trinnet fra Task 3 får argumentet `ac194bfd`.
- [ ] **Step 3:** `SAMTIDIG_OK`, `UPGRADE_OK`. Hovedsessionen committer `test(sletning): samtidighed og opgradering`.

### Task 12: Udbakke, Storage og Redaktion (spec §6.7, V-5)

**Files:** `schema.sql`, `db-migrations.sql`, `db-rls.sql`, `web/src/data/personPurge.ts` (+ `__tests__`),
`web/src/components/SletHeltDialog.tsx` (+ test), `web/src/data/redaktionWrite.ts`, `web/src/Redaktion.tsx`.

**Interfaces:**
- Udbakketabellen findes fra Task 8.
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
  - Som redaktør: preview og sletning af 1791 med målt tid.
    - Læs `authenticated`-rollens faktiske `statement_timeout` i prod med `SELECT rolconfig FROM pg_roles`.
    - `docs/database-current-state.md` siger 2 min, men det gælder ceremonirollen (M2-3).
    - Lokale roller har ingen grænse, så tiden sammenlignes med prods tal.
  - `person-purge-count.sql` giver 0.
  - `person-purge-rest.sql` (`mode=prod`): før-filen tages før sletningen; bagefter gælder kravene fra Task 1 step 2
    (V2-4).
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
  - Rest efter `person-purge-rest.sql` (`mode=prod`), med før-filen taget i samme ceremoni før sletningen.
  - Færdigbevis efter spec §7.
- [ ] **Step 4:** Hovedsessionen committer `docs(sletning): runbook og generalprøvetal`.
