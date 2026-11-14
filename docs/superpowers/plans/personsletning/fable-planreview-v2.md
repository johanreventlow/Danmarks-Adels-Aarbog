## Review af plan v2 for fuld personsletning

**Dom: klar efter små rettelser.** Designet holder, og jeg fandt intet, der kræver ny afgørelse fra projektejeren. Men to steder kan planen ikke udføres, som den står (K2-1, K2-2), og seks steder beviser testene mindre, end de påstår, eller en teknisk detalje vil fejle. Alt kan rettes i planteksten, før Task 2 startes.

Rådgiverværktøjet svarede ikke (timeout), så vurderingen er ikke efterprøvet af en anden.

---

### 1. Fund fra v1-reviewet

| Fund | Status | Begrundelse |
|---|---|---|
| K-1 slettegraf + handling | Lukket | Slettegrafen ligger i repo, inventaret har `handling`/`fase`/`grund`, og tilladt rest er godkendt. Forbehold: V2-3. |
| K-2 tidligere slettede rækker | Lukket | Task 4 (`E`/`D` med F\*, R\*, A\*…) plus testene `historik_tidligere_slettet` og `purge_fortryd_bevaret`. |
| K-3 persontjek vs. hel strøm | Lukket i design | `grund` pr. række, `hel_stroem`, tests for NULL og anden person, og `counterpart_person_id` er med. Teknisk fejl i selve tjekket: V2-1. |
| K-4 placering i `schema.sql` | Lukket | Sektionen ligger sidst, og inventaret er `VALUES`-funktioner. Uklarhed om de ændrede funktioners plads: V2-6. |
| V-1 låseorden | Lukket | L1-L13 med kildelåsen tidligt og eksklusivt; Task 11 b-d. Rest: V2-5. |
| V-2 GUC som bevis | Lukket | Manifestrække for (xid, backend) er beviset, også for oprindelsen `person_purge`. |
| V-3 UPDATE-gren, 4 funktioner | Lukket | Ingen UPDATE-undtagelse, trinvise `IF`, kun 4 funktioner. To afledte testfejl: M2-1, M2-2. |
| V-4 tests måler med inventaret | Delvist | Tæller og restsøgning er i repo og uafhængige, og sletningen committes i egen kopi. Men `purge_andre_uaendrede` bruger stadig manifestet til at afgrænse (V2-2), og restsøgningen virker ikke for 1791 (V2-4). |
| V-5 udbakke | Lukket | Udbakken er beholdt, og janitor-tjekket står i runbooken. Task-rækkefølge: V2-7. |
| V-6 `aaben_koersel` | Lukket | `sealed` blokerer; kandidat, forældrekort, eksklusion, batches og `afventer_kontrol` har hver sin test. |
| V-7 katalogvagt pr. kolonne | Delvist | Kolonneliste og undtagelsesliste findes. Kandidatreglen fanger ikke en ren `bigint`-kolonne, og planens egen test kan ikke bestå: K2-2. |
| V-8 huller mod spec | Delvist | Lukket: summaries (slettegraf §5), `note.indhold`, samtidighed mod publicering og kandidatkørsel, 8 tabeller, l. 9558, rollegate, slutkontrol. Åbent: fortryd, der genindsætter et dødt link, har en test, men ingen implementeringsvej (M2-5). Slutkontrollen ser ikke ucommittede skrivninger (V2-5). |
| V-9 rækkefølge og fixture | Delvist | Fixturen har egen task, historikken fabrikeres, og der er én kopi pr. testgruppe. Men kravet om faste negative id'er kan ikke opfyldes for ledger-kæder og links (K2-1), og Task 2 er stadig én meget stor task. |
| Mindre | Lukket | Dump før sletningen, tidlig måling (Task 7 step 6), timeout, base-commit, db-verify-asserts og mobil er med. Se M2-3 og M2-6. |

---

### 2. Nye fund

#### Kritisk (planen kan ikke udføres som skrevet)

**K2-1. Hovedpersonen kan ikke have fast negativt id (Global Constraints »Testdata«, Task 2, Task 7).**
- **Problem 1:** `parse_mentions` (`schema.sql` l. 9629-9638) matcher kun `(0|[1-9][0-9]*)`. `[[person:-987654700|…]]` giver aldrig et link.
- **Problem 2:** Planen erkender for `red_opret_person`, at skriverne giver sekvens-id. Det samme gælder `person_create` og `relation_person_create` (`insert_person_with_receipt`, l. 10394). En `reimport_event` med `canonical_person_id=-987654700` kan kun laves ved at fabrikere hele batch- og autorisationskæden forbi valideringstriggerne.
- **Konsekvens:** `preview_blokering_link` kan ikke udløses, og restsøgningens `[[person:<pid>|` bliver aldrig prøvet. S32-mønstrene med `[0-9]+` rammer ikke negative naboer. Implementeren fabrikerer ledger-rækker, som ikke ligner prod, eller skriver stederne på `kan_ikke_forekomme`.
- **Rettelse:**
  - Drop kravet om et fast id for P. Lad P være den person, de rigtige skrivere opretter (positivt sekvens-id), og gem id'et i en lille testtabel.
  - Behold syntetiske navne.
  - Lad hovedsessionen godkende `kan_ikke_forekomme` linje for linje.
  - Del Task 2 i 2a (kerne og historik) og 2b (ledgers og identitet).

**K2-2. Katalogvagtens regel fanger ikke den vigtigste klasse, og `vagt_ny_kolonne` kan ikke bestå (Task 3).**
- **Problem:** Kandidater er FK til person/family, `*_type`+`*_id`-par og `jsonb`/`bigint[]`/`text`. Testen tilføjer `tmp_person bigint` uden FK. Den er ingen af delene.
- **Målt i prod-kopien:** 7 eksisterende person-/familiekolonner er netop rene `bigint` uden FK:
  - `reimport_event.canonical_person_id`
  - `reimport_name_completion_result.person_id`
  - `legacy_placement_disposition.person_id`
  - `identity_control_parent_card.counterpart_person_id` og `.family_id`
  - `relation_reopen.from_family_id` og `.to_family_id`
  - `marriage_ordinal_correction.family_id`
- **Konsekvens:** V-7 er ikke lukket. En ny ledger-kolonne af samme slags slipper forbi vagten.
- **Rettelse:**
  - Kandidater er alle kolonner af typerne `bigint`, `integer`, `uuid`, `text`, `jsonb` og arrays af dem.
  - Tillad undtagelse for en hel tabel (`kolonne='*'`), men kun for bogens lag og rene opslagstabeller.
  - Skriv omfanget i tasken: ca. 143 bigint, 71 integer, 162 uuid, 335 text og 55 jsonb i `public`+`private`.

#### Vigtig

**V2-1. `hel_stroem`-tjekket afhænger af sletterækkefølgen (Task 5, »forrige_version er lig max(version)«).**
- **Problem:** I en `BEFORE DELETE … FOR EACH ROW`-trigger ser opslaget de rækker, samme sætning allerede har slettet. Slettes v3 før v1, er `max(version)` 2 for næste række, og den afvises.
- **Konsekvens:** Sletningen fejler lukket, men tilfældigt. Testen kan være grøn, fordi rækkerne ligger i indsættelsesorden, og fejle i prod. 4 personas i prod-kopien har mere end ét event.
- **Rettelse:** Kræv `OLD.version <= forrige_version` og »intet event med version > forrige_version«. Tilføj en test, der sletter i faldende orden.
- **Afklar også** hvilken manifestrække der bærer `forrige_version`. Task 5 slår op på event-rækken, Task 6 på state-rækken (`source_persona_identity`).

**V2-2. `purge_andre_uaendrede` bruger manifestet til at afgrænse »andre« (Task 8).**
- **Problem:** Teksten siger både »tabeller, der har en manifestrække« og »alle tabeller«, og den trækker manifestets mængde fra. Manifestet er desuden tømt efter commit.
- **Konsekvens:** Tager planfunktionen fejlagtigt en andens række med, udelades den af hashen, og testen er grøn. Det er netop anti-målet »sletter andres data«.
- **Rettelse:**
  - Fixturen leverer selv den forventede slettemængde som pk-lister pr. tabel, skrevet ved opbygningen.
  - Hash alle tabeller i `public`+`private` minus den liste.
  - Lav en navngiven liste over forventede ændringer hos naboer: `loesn`/`nulstil`-kolonner og `visning_*`.
  - Test særskilt, at planens mængde er lig fixturens liste.

**V2-3. »Tilladt rest« modsiger Q9 (Global Constraints vs. slettegrafens afgørelser).**
- **Problem:** Q9-stederne bevares uden blokering og kan bære P's navn i fritekst: S34b, S44b, `parent_event.note`, S49c, S58, noter i `Y`-events og levende noter hos andre. Listen nævner kun historik, S44a, medietitel og vielsesfakta, og siger »alt andet er en fejl«.
- **Konsekvens:** Enten fejler `purge_rest_kun_tilladt`, når fixturen har en note med P's navn (som `preview_til_kontrol` kræver), eller også udvider implementeren listen stille.
- **Rettelse:** Tilføj punktet »fritekst på Q9-stederne, når rækken stod i forhåndsvisningens `til_kontrol`«. Lad testen kræve, at hvert sådant restfund svarer til en `til_kontrol`-post. Ret spec §2 tilsvarende.
- `preview_til_kontrol` dækker i øvrigt kun note og medietitel, ikke de øvrige Q9-steder.

**V2-4. Restsøgningen kan ikke bevise noget for 1791 (Task 1 step 2-3, Task 13 step 1).**
- **Problem:** »pid som helt tal-token« rammer også årstal og andre id'er.
- **Målt:** Token `1791` findes i 6 `assertion`-, 3 `fact`- og 68 `change_event`-rækker i prod-kopien. De er hverken slettemål eller på tilladt-listen.
- **Konsekvens:** Færdigbeviset »kun tilladt rest« kan ikke blive grønt for den første rigtige sletning, eller det bliver bortforklaret.
- **Rettelse:**
  - Tal-token bruges kun mod fixturen.
  - For prod måles før og efter pr. tabel: efter ≤ før, og forskellen er lig planens antal.
  - Dertil kommer navn og `[[person:1791|`.
  - Skriv det i Task 1 og Task 13.

**V2-5. Almindelige redaktørskrivninger under sletningen er ikke dækket (Task 8 slutkontrol, Task 11).**
- **Problem:** `red_upsert_fakta` (l. 6719) låser ikke personrækken og tjekker ikke, at personen findes. `fact` har ingen FK. `begin_change_set` tager `ROW EXCLUSIVE`, som er forenelig med L8.
- **Konsekvens:** En skrivning, der er startet før sletningens commit, efterlader faktum, påstand, citat, sæt og events om P. Slutkontrollen ser ikke ucommittede rækker. Det samme gælder story, note og forslag.
- **Rettelse:**
  - Minimum: Task 11 (f) med samtidig `red_upsert_fakta('person',P,…)` i begge rækkefølger, og et db-verify-assert for polymorfe rækker med `subjekt_type='person'` uden personrække.
  - Bedre: L8 som `SHARE ROW EXCLUSIVE`, så versionerede skrivere venter, plus et eksistenstjek i de polymorfe skrivere.
  - Vælg bevidst, og notér resten som kendt.
  - Task 11 (e) skal bruge et sæt med en FK-løs række (faktum på P) og ende med tælling 0.

**V2-6. Det står ikke klart, hvor de ændrede funktioner defineres (Filstruktur, Task 5, 6, 9).**
- **Problem:** Filstrukturen lægger »ændringer i 4 triggerfunktioner, `decide…`, `validate…`, `red_fortryd…`« i den sidste sektion. De er defineret tidligere (l. 916, 1859, 4063, 9297, 9484, 10404, 13997). `db-migrations.sql` har allerede 5 definitioner af `decide_source_persona_identity`.
- **Konsekvens:** To definitioner i `schema.sql` er projektets kendte fælde: den ene degraderer stille.
- **Rettelse:**
  - I `schema.sql` rettes funktionerne på stedet, med én definition. plpgsql binder sent, så kaldet til `person_purge_tilladt` sidst i filen er lovligt.
  - I migrationsblokken oprettes manifest og `person_purge_tilladt` før `CREATE OR REPLACE` af triggerfunktionerne.
  - Opgraderingstesten kører hele filen igen, som `test-6e2-etiket.sh` l. 20.

**V2-7. Task-afhængigheder, der står implicit.**
- **Udbakken:** Task 8 skal skrive i den, men tabellen laves i Task 12 (»indtil da en stub«). Flyt tabellen og dens RLS til Task 8; RPC'er og web bliver i Task 12.
- **Task 6:** Testene siger »efter sletningen«, men sletningen kommer i Task 8. Skriv, at Task 6 simulerer med håndskrevet manifest, og at den rigtige ende-til-ende-test ligger i Task 8.
- **Task 3:** CI-trinnet tilføjes her med `<base>`, men opgraderingsdelen bygges i Task 11. Sig, hvad harnessen gør med argumentet indtil da.
- **Vagten:** Task 5 og 12 opretter tabeller med `text`/`jsonb`/`bigint`, som vagten fra Task 3 fælder. Nævn, at undtagelseslisten opdateres der.
- **Ikke i nogen task:** `relation_binding_state`-undersøgelsen (Task 4 step 4b) og fortrydelsesanalysen pr. vej (Q3) er tunge læseopgaver uden færdigkriterium.

**V2-8. Task 10: `PURGE_TILLADELSESLISTE_BOGTABEL` kan ikke bestå som formuleret.**
- **Problem:** `reject_reimport_writer_mutation` indeholder allerede teksten `reimport_writer_profile` (l. 4066), som er på bog-listen.
- **Rettelse:** Læg tilladelseslisten i én funktion, fx `private.person_purge_tilladte_tabeller()` med `VALUES`. Lad triggerfunktionerne og assertet læse den.

#### Mindre

- **M2-1.** `afvisningstekst_uaendret` med kalder-matricen er tom: ingen af rollerne `anon`, `authenticated` eller `service_role` har `USAGE` på `private` eller `DELETE` på tabellerne (målt). Test i stedet som ejer uden manifest, og behold db-verify l. 2623-2637. `kalder-matrix.sql` har desuden ingen hjælper, der fanger fejltekst; den skal skrives.
- **M2-2.** Triggerformen: tilføj `TG_LEVEL='ROW'` og `TG_TABLE_SCHEMA='private'` i betingelsen. I dag findes ingen sætningstriggere for UPDATE/DELETE med funktionerne (målt: 0).
- **M2-3.** Planen siger »Supabase-standard 8 s«. `docs/database-current-state.md` siger 2 min for prod. Lokale roller har ingen grænse. Mål også tid i Task 7 step 6; planfunktionen kører tre gange i sletningen.
- **M2-4.** §3.2-tjekket for `narrative_publication_event` kræver `subjekt_type='person'`, men `N` rummer også familie-narrativer. I dag findes ingen (0 familie-narrativer), så det er latent. Enten udvid tjekket med `grund='familie'` eller blokér. `grund`-værdierne `familie` og `historik` har ingen regel i Task 5.
- **M2-5.** `purge_fortryd_genindsaetter_ikke_link` har ingen implementeringsvej. Kontrakt v2 afviser allerede narrativer (l. 9500-9527); noter gør ikke. Sig, om fortryd skal afvise et link til en ikke-eksisterende person, ellers ender den som åben forelæggelse midt i Task 8.
- **M2-6.** Ensret fejlkoden: `PERSON_PURGE_LOCKSET_DRIFT` (slettegraf) mod `PURGE_LOCKSET_DRIFT` (plan). Spec §6.2 lover et db-verify-assert på låseordenen. Planen har kun `samme_som` før `lock_identity_people`, ikke kildelås før persona.
- **M2-7.** Task 6 siger »Modifies `red_source_persona_queue`«, men køen returnerer `evidence->>'reason'` råt (l. 11046). Teksten »ikke en person« hører hjemme i web, og der står ingen web-fil i tasken.
- **M2-8.** Task 2 step 3 siger skabelon = »schema + migrations + rls«. Det eksisterende mønster er bootstrap (`evidence-promotion-bootstrap.sql`) + `schema.sql` + `db-rls.sql`. Nævn bootstrap-filen.
- **M2-9.** Task 9: alle 8 tabeller har allerede identity, og sekvensgulvet er monotont (`db-migrations.sql` l. 4826-4860). Testen bliver grøn uden ændring. Skriv, at den er en regressionsvagt.

---

### 3. Verificeret i koden og basen

**Bekræftet:**
- **Linjenumre:** 916, 1859, 4063, 9297, 9484/9557-9558, 10404, 12648, 13997, 14035, 19948, 20004 og de fire fortrydelsesveje passer.
- **`narrative_legacy_publication`:** har kun validatoren (INSERT/UPDATE), ingen append-only-trigger (katalog). `latest_event_id` må være NULL (l. 14035; ingen NOT NULL).
- **Kun de 4 triggerfunktioner:** alle tabeller på tilladelseslisten bruger netop de fire (katalog). De to andre `reject_*`-funktioner dækker kun `interpretation_predicate` og cutover-kvitteringen.
- **FK-grafen:** alle 40 FK'er ind i slettetabellerne svarer til slettegrafens faseplan. Ingen ukendt FK, og ingen ukendt DELETE-trigger.
- **Q7:**
  - Validatoren kræver `max+1` og kører som ejer.
  - Kernen udleder uuid af (persona, ny version) og kræver mindst én mention (0 identiteter uden mention i prod-kopien).
  - Ved commit kræver `identity_state_has_event` kun state = seneste event, så n+1 alene er gyldigt.
  - Kernen sætter i dag `v_new_version := v_current_version+1`; grenen skal selv sætte n+1.
- **`red_fortryd_change_set`:** fallbacken er død kode (identity-kolonne), så en fejl i stedet er korrekt.
- **CI:** 6e2-harnesserne bruger base `ac194bfd`. Skemafilerne er uændrede derfra til `c41f67db`.

**Kun læst, ikke efterprøvet:**
- Låseordenen for de øvrige skrivere (slettegraf §6.1).
- Summaries-fejningen (§5).
- `count.sql`'s indhold.
- Web-delen (`mediaUdrens.ts` kun set overfladisk).
- Hvordan `relation_binding_state` opfører sig.

---

### 4. Klar til subagent-drevet udførelse?

| Task | Vurdering |
|---|---|
| 1, 4, 5, 9, 10 | Selvstændige nok, når V2-1, V2-4 og V2-8 er rettet. |
| 2 | Ikke klar: K2-1, og for stor til én implementer. Del den i to. |
| 3 | Ikke klar: K2-2. |
| 6, 8, 12 | Klar, når V2-7 er rettet. |
| 7 | Stor, men veldefineret. Q3-analysen pr. fortrydelsesvej bør være et eget step med leverance. |

**Filer:**
- `/Users/johanreventlow/TypeScript/danmarksadelsaarbog/.worktrees/personsletning/docs/superpowers/plans/2026-11-14-fuld-personsletning.md`
- `/Users/johanreventlow/TypeScript/danmarksadelsaarbog/.worktrees/personsletning/docs/superpowers/specs/2026-11-14-fuld-personsletning-design.md`
- `/Users/johanreventlow/TypeScript/danmarksadelsaarbog/.worktrees/personsletning/docs/superpowers/plans/personsletning/slettegraf.md`
- `/Users/johanreventlow/TypeScript/danmarksadelsaarbog/.worktrees/personsletning/schema.sql`
- `/Users/johanreventlow/TypeScript/danmarksadelsaarbog/.worktrees/personsletning/tests/sql/fixtures/kalder-matrix.sql`
- `/Users/johanreventlow/TypeScript/danmarksadelsaarbog/.worktrees/personsletning/tests/sql/test-6e2-etiket.sh`