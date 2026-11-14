# Analyse: binding, fortrydelse og låse-spike (fuld personsletning)

Del 1 og 2 (binding og fortrydelse) skrives i Task 4. Denne fil starter med del 3 fra Task 0.

---

## Del 3: Låse-spike (Task 0)

Kort fortalt (hverdagssprog):

- Vi har afprøvet låseordenen L1-L13 med L5b i praksis med et skelet af sletningen og rigtige skrivere, der tvinges
  til at mødes på de værst tænkelige tidspunkter.
- **Med planens orden (L8 = ROW EXCLUSIVE, L5b slået til) gav ingen af de tvungne sammenstød deadlock (40P01).** Hver
  gang ventede den ene på den anden, og bagefter lykkedes den ene, mens den anden enten også lykkedes eller afviste med
  en forståelig fejl. Der blev aldrig efterladt forældreløse rækker.
- De to cykler, delta-reviewet forudsagde, er reproduceret: med L8 = SHARE ROW EXCLUSIVE (v2.1) eller uden L5b kommer
  der deadlock hver gang. Testopsætningen kan altså fremtvinge cyklerne, og planens to rettelser fjerner dem.
- **CI med vagterne er ikke grøn.** Alle fejl, vi har set, skyldes testdata, der skriver rækker om personer eller
  fakta, som ikke findes (klasse a). Ingen rigtig skriver bliver brudt af vagterne (klasse b: 0). Detaljer i 3.5.
- Et nyt fund: `SET LOCAL statement_timeout` inde i sletningen virker ikke på selve kaldet (3.4, F-4).

Afgørelsen go/no-go træffes af hovedsessionen.

### 3.1 Hvad blev bygget

| Fil | Indhold |
|---|---|
| `tests/sql/spike/person-purge-skelet.sql` | Vagterne og skelettet. Lægges oven på en engangsbase; idempotent. |
| `tests/sql/spike/person-purge-fixture.sql` | Syntetisk fixtur (P, Q, L, persona X_P placeret i record P-REC, uafgjort persona Z). |
| `tests/sql/spike-person-purge-laase.sh` | Harnessen med de tvungne interleavings. |
| `tests/sql/spike/ci_jobs_lokalt.py` | Kører de 4 PostgreSQL-CI-jobs lokalt med vagterne slået til (step 2). |

**Vagterne** (som Global Constraints; markør `SPIKE_PERSON_PURGE_VAGT_V1` i hver funktion):

- `enforce_relation_evidence_target` udvidet til `target_type='fact'` (`FOR KEY SHARE` på faktummet), og med
  D-6's tidlige retur ved uændret (type, id).
- `private.validate_polymorf_subjekt_findes` (SECURITY DEFINER, `FOR KEY SHARE`, `lower()`, tidlig retur ved uændret,
  personer før familier i id-orden) på `fact`, `note`, `narrative`, `story`, `suggestion`, `relation` (begge ender),
  `assertion.objekt_*` og `haendelse.subjekt_*`.
- `validate_entity_description_subject` med `FOR KEY SHARE`. Den er bevidst stadig SECURITY INVOKER som i
  `schema.sql`; se F-6.
- Fakta-slettevagten `private.guard_fact_evidence_delete` (BEFORE DELETE OR UPDATE OF id på `fact`) med
  `FACT_HAR_EVIDENS`.
- **Ikke med:** låsen i `red_set_feed_pin`. Den er én RPC uden samspil med de øvrige låse og laves i Task 8.
- En `warn`-tilstand (tabelrækken `spike.indstilling`, så `createdb -T` arver den) giver `RAISE WARNING
  SPIKE_VAGT_BRUD … stak=<funktioner>` i stedet for en fejl. Den bruges kun til CI-inventaret.

**Skelettet** `spike.red_slet_person_helt_skelet(P, opt)` tager L1-L13 med L5b i slettegrafens orden:

- `lock_timeout = 5s` og `statement_timeout = 30s` sættes med `set_config`.
- L3 og L12 beregner kilderne for `person_external_id`, X∪Y, kandidatrækker og kontrolstikprøver.
- L5b låser de records, hvor X∪Y-personas er placeret, plus records med P's narrativbindinger.
- L13 sammenligner et forenklet preview: P's fakta, påstande, relationer, noter, X∪Y, kandidater og memberships.
- Derefter sletter skelettet noget repræsentativt, børn før forældre: citation, conclusion, assertion, note,
  haendelse-ankre, relationer (også med en fakta-ende), fakta og memberships. Med `slet_person` slettes også
  external ids, family_member og selve personen.
- Det skriver ingen manifest og rører ingen ledgers.
- Valg (kun til spiket):
  - `l5b`: false giver positiv kontrol for D-2.
  - `l8_mode`: `SHARE ROW EXCLUSIVE` giver positiv kontrol for D-1.
  - `pause_after`: `pg_sleep`, mens låsene holdes.
  - `slet_person`.

**Pausemekanik i harnessen:**

- Hver session er en baggrunds-psql med sit eget `application_name`.
- En observatør poller `pg_blocking_pids` og logger, hvem der venter på hvem. Ved rækkelåse viser loggen tabellen fra
  ventertens tuple-lås. Et resultat tæller kun, når sammenstødet er observeret.
- Skelettet standses på to måder:
  - med `pause_after`;
  - ved L7, mens en tredje session holder `samme_som_mutation`. Det er præcis D-2's »mellem L6 og L8«.
- Skriveren standses med et **testinstrument**: en kopi af `begin_change_set` med uændret krop plus et pausepunkt
  først. Kopien findes kun i spikens base.
  - Pausepunktet venter på advisory-nøglen `spike_pause_cs`, når sessionen har `spike.pause_cs=on`.
  - Så står skriveren præcis i D-1's vindue: efter sine rækkelåse og før sin første lås på `change_set`.
- Narrativskriverne standses ved, at en tredje session holder P's narrativrække. Så har skriveren record → change_set
  ACCESS EXCLUSIVE → person, men endnu ikke personaen.
- Helt-først-scenarierne kører hele skriveren i en transaktion med `pg_sleep(3)` før COMMIT, så alle dens låse holdes.

**Fixturen** bruger negative id'er og syntetiske navne. Den følger formen fra
`tests/integration/test-narrative-record-concurrency.R` (`seed_record`). Den rigtige fixtur med positive id'er bygges
i Task 2a.

- P (-9101) har:
  - fakta med påstand, citat fra kilde S og afklaret konklusion;
  - en note og en evidensfri medieafbildning;
  - en membership fra en placement;
  - persona X_P, placeret i P-REC og accepteret som P;
  - et forslag fra X_P til titlen.
- P's narrativ på P-REC oprettes og publiceres gennem de rigtige RPC'er (`red_upsert_…`, `red_publicer_…`).
- Q (-9102) er en anden person i samme kilde.
- L (-9103) har ingen ledger, så skelettet kan slette den helt.
- Z er en uafgjort persona i S.
- Kontrakt v2 kommer fra `tests/sql/reimport-writer-v2-bootstrap.sql`, altså den rigtige cutover.

**Kørsel:** `bash tests/sql/spike-person-purge-laase.sh [præfiks] [scenarie …]`. Alle scenarier tager ca. 3 min.
Scriptet opretter `<præfiks>_base` og én kopi pr. scenarie og sletter kun dem. Resultatet står i
`$SPIKE_OUT/resultat.tsv`.

### 3.2 Resultater pr. scenarie

Kørt tre gange (to af gangene, mens CI-jobbene belastede maskinen). Udfald og observerede ventninger var ens alle tre
gange.

S = skelettet, W = skriveren, H = holder-sessionen. »Venter« er observeret med `pg_blocking_pids`.

**Planens konfiguration** (L8 ROW EXCLUSIVE, L5b til):

| Scenarie | Observeret | S | W | Udfald |
|---|---|---|---|---|
| D-1 `red_ret_ocr_felt` på Q (samme kilde), W først | W ved change_set-pausen; S venter på W's række i `source` (L9) | OK | OK | serialiseret |
| D-1 OCR, S først (holder L1-L8) | W venter ikke (L9 er ikke taget endnu) | OK | OK | serialiseret |
| D-1 `red_ret_paastand`, W først | S venter på W's række i `source_persona_identity` (L6) | OK | OK | serialiseret |
| D-1 `red_ret_paastand`, S først | W venter på S i `source_persona_identity` | OK | `PAASTAND_DRIFT` | serialiseret, fail-closed |
| D-1 `red_reverse_placement_membership`, W først | S venter på W's række i `person_lineage_membership` (DELETE) | OK | OK | serialiseret |
| D-1 membership, S først | W venter ikke; W committer før S's L13 | `PURGE_PREVIEW_AENDRET` | OK | serialiseret, fail-closed |
| D-1 `red_slet_medierelation_uden_evidens`, W først | S venter på W's række i `relation` | OK | OK | serialiseret |
| D-1 medie, S først | W venter ikke | `PURGE_PREVIEW_AENDRET` | OK | serialiseret, fail-closed |
| D-2 `mutate_person_narrative_record` (revider), S først, stoppet ved L7 | W venter på S's række i `source_record` (L5b) | OK | OK | serialiseret |
| D-2 revider, W først (record+AE+person holdt) | S venter på W's række i `source_record` (L5b) | OK | OK | serialiseret |
| D-2 `reverse_narrative_publication_event` (fortryd), S først, L7 | W venter på S i `source_record` | OK | OK | serialiseret |
| D-2 fortryd, W først | S venter på W i `source_record` | OK | OK | serialiseret |
| Task 11 (f) `red_upsert_fakta(L)`, W først | S venter på W's KEY SHARE på `person` (L10) | `PURGE_PREVIEW_AENDRET` | OK | som planen forventer |
| (f), S først (sover efter sletningen) | W venter på S i `person` | OK | `POLYMORF_SUBJEKT_FINDES_IKKE: person` | som planen forventer |
| Task 11 (g) `red_tilfoej_oplysning` på L's faktum, W først | S's DELETE venter på W's KEY SHARE på `fact` | `FACT_HAR_EVIDENS` | OK | som planen forventer |
| (g), S først | W venter på S i `fact` | OK | `POLYMORF_SUBJEKT_FINDES_IKKE: fact` | som planen forventer |
| (g) note på L's faktum uden change_set, W først | S venter i `fact` | `FACT_HAR_EVIDENS` | OK | som planen forventer |
| (g) note uden change_set, S først | W venter i `fact` | OK | `POLYMORF_SUBJEKT_FINDES_IKKE: fact` | som planen forventer |
| `red_afgoer_source_persona` (Z same P), W først | S venter på W's delte kildelås (L5) | `PURGE_PREVIEW_AENDRET` | OK | serialiseret, fail-closed |
| `red_afgoer_source_persona`, S først | W venter på S's eksklusive kildelås | OK | OK | serialiseret |
| `red_record_identity_candidates` (S, Z→P), W først | S venter på W's kildelås (L5) | `PURGE_PREVIEW_AENDRET` | OK | serialiseret, fail-closed |
| `red_record_identity_candidates`, S først | W venter på S's kildelås | OK | `IDENTITY_CANDIDATE_INPUT_DRIFT` | serialiseret, fail-closed |
| (h) en anden session holder P FOR UPDATE i 10 s | S venter i `person` | `55P03` efter 5 s | (holder) | intet ændret |

Tabellen bagefter blev målt efter hvert scenarie: 0 forældreløse påstande, 0 forældreløse fakta og 0 forældreløse
noter i alle 31 kørsler.

**Positive kontroller** (beviser, at harnessen fremtvinger cyklerne):

| Kontrol | Observeret | Offer |
|---|---|---|
| D-1 OCR, W først, L8 = SHARE ROW EXCLUSIVE | S holder SRE og venter på W's række i `source`. W slippes og skal have RE på change_set | **40P01**, S |
| D-1 membership, W først, SRE | som ovenfor, række i `person_lineage_membership` | **40P01**, S |
| D-1 medie, W først, SRE | som ovenfor, række i `relation` | **40P01**, S |
| D-1 `red_ret_paastand`, W først, SRE | S venter allerede ved L6 (identitet) før L8 | ingen deadlock (se F-2) |
| D-2 revider, S først, UDEN L5b | W har record+AE+person og venter på S's persona; S slippes ved L7 og vil have RE på change_set | **40P01**, W |
| D-2 revider, W først, UDEN L5b | S venter på W's ACCESS EXCLUSIVE (L8); W slippes og vil have personaen | **40P01**, S |
| D-2 fortryd, S først, UDEN L5b | som revider | **40P01**, W |
| D-2 fortryd, W først, UDEN L5b | som revider | **40P01**, S |

### 3.3 Hvad spiket ikke dækker

- **Skelettet er ikke sletningen.** Den rigtige sletning sletter langt flere tabeller efter L13 (manifest, ledgers,
  historik, narrativer) og holder låsene længere. Den tager desuden flere rækkelåse sent i transaktionen. Task 11 skal
  køre de samme scenarier mod den rigtige funktion. Harnessen er bygget, så skabelonerne kan genbruges.
- Skelettet sletter ikke P selv i D-2-scenarierne, fordi P har publiceringshistorik (append-only). Kollisionen sker
  før sletningen, så det ændrer ikke låseudfaldet.
- `red_set_feed_pin` og `red_fortryd_change_set` (Task 11 e) er ikke med.
- Pausen i `begin_change_set` er et testinstrument. Uden den kan vinduet mellem en skrivers rækkelås og dens
  change_set-lås ikke rammes deterministisk.
- Step 1b's statiske tjek af helpers og triggere er ikke lavet. Spiket tester kun de navngivne skrivere.

### 3.4 Fund

- **F-1 (låseorden):** L1-L13 med L5b og L8 = ROW EXCLUSIVE serialiserer alle tvungne sammenstød. De gav 0 deadlocks
  i 23 scenarier × 3 kørsler. Begge rettelser fra delta-reviewet er nødvendige. Uden dem giver de positive
  kontroller 40P01 hver gang.
- **F-2 (`red_ret_paastand` kan ikke danne D-1-cyklussen):** Skriveren kræver altid et forslag fra en persona med
  accepteret identitet til faktummets person, altså en persona i X. Den tager `source_persona_identity FOR SHARE`, før
  den tager personen.
  - Sletningen venter derfor ved L6, før den har L8. Selv med SHARE ROW EXCLUSIVE kom der ingen deadlock.
  - [læst] Uden forslag afviser funktionen med `PAASTAND_FORSLAG_UOVERENS`, før den åbner sættet, og låsene slippes ved
    rollback.
  - Delta-reviewets formulering »når påstanden ikke kommer fra en fortolkning« dækker altså ingen sti, der når
    `begin_change_set`.
- **F-3 (fail-closed, ikke deadlock):** Når en skriver når at committe, mens sletningen holder L1-L8, fanger L13's
  preview-sammenligning ændringen (`PURGE_PREVIEW_AENDRET`). Det gælder membership, medie, afgørelse og
  kandidatkørsel. Planens L12/L13 er altså det, der lukker, ikke låsene alene. Det kræver, at det rigtige preview
  indeholder memberships, medierelationer, X∪Y og kandidatrækker. Skelettets forenklede preview gør det.
- **F-4 (`statement_timeout` virker ikke inde i funktionen):** Målt på PG 17. `set_config('statement_timeout','1s',
  true)` og en funktions `SET statement_timeout` afbryder ikke det kald, der er i gang. `pg_sleep(2.5)` gik igennem
  i begge tilfælde.
  - Timeren armeres, når statementet starter. Global Constraints' »`SET LOCAL statement_timeout = '30s'` som samlet
    loft« (D-3) virker derfor kun på senere statements i samme transaktion, ikke på sletningen selv.
  - Loftet kommer i praksis fra den rolle eller session, RPC-kaldet kører under (PostgREST's rolle-indstilling).
  - Task 8 skal enten dokumentere det eller bruge en anden mekanisme, fx en tidsgrænse i klienten eller
    `lock_timeout` alene.
  - `lock_timeout` virker, fordi den læses ved hver låseventning (scenarie h: 55P03 efter 5 s).
- **F-5 (genanvendelse af vagterne):** `db-migrations.sql` (l. 2969 og l. 7520) genskaber de gamle kroppe af
  `enforce_relation_evidence_target` og `validate_entity_description_subject`.
  - Spiket måtte derfor lægge vagterne på efter hver kørsel af `db-migrations.sql`. CI-kørslen gør det ved at hægte
    skelettet på begge filer.
  - Task 8 retter funktionerne, hvor de står (V2-6). Den skal også rette de to historiske blokke i
    `db-migrations.sql` eller sikre, at den nye blok sidst i filen vinder. Ellers mister en genkørt migration lydløst
    vagterne. Opgraderingstesten i Task 11 step 2 fanger det kun, hvis den sammenligner netop disse funktionskroppe.
- **F-6 (`entity_description` og SECURITY INVOKER) [udledt, ingen fejl målt]:** `FOR KEY SHARE` kræver UPDATE-ret
  på måltabellen.
  - I dag er det uden praktisk betydning. `authenticated` har kun SELECT på `entity_description` (`db-rls.sql`
    l. 342), så alle skrivninger går gennem SECURITY DEFINER-RPC'er. Triggeren kører derfor som ejeren.
  - CI gav ingen fejl.
  - Får en rolle senere direkte INSERT, rammer den »permission denied«. Task 8 bør gøre funktionen SECURITY DEFINER
    som de andre vagter, for robusthedens skyld.
- **F-7 (vagterne rammer skrivere uden eksistenstjek):** `red_relation` validerer ikke, at personen findes.
  db-verify bruger den med ikke-eksisterende personer (3.5). Med vagten afvises det nu. Det er vagtens formål og ikke en
  regression, men testene skal seede personen.

### 3.5 CI med vagterne slået til (step 2)

Kørt med `tests/sql/spike/ci_jobs_lokalt.py`:

- Kopierer de git-sporede filer til en scratch-mappe og hægter skelettet på `schema.sql` og `db-migrations.sql`.
  Repo'et ændres ikke.
- Oversætter hvert jobs trin fra `ci.yml` og giver alle basenavne et unikt præfiks.
- Et fejlet trin stopper ikke jobbet. Senere trin kan derfor være følgefejl.
- Fire varianter:
  - `base`: uden vagter (referencen);
  - `enforce`: vagterne som i planen;
  - `warn`: vagterne skriver en advarsel i stedet for at fejle, så hele inventaret kommer med, også efter første
    brud;
  - `enforce_kendte`: som enforce, men de 13 kendte steder fra warn-inventaret giver kun en advarsel. Alt andet fejler.
    Den bekræfter, at inventaret er komplet, også for brud i dblink- og R-sessioner, hvis advarsler aldrig når en log.

Lokale afvigelser fra CI:

- macOS og en lokal superbruger i stedet for `postgres`.
- PGPASSWORD er en dummy (trust-login).
- Trinnene `install.packages(...)` fejler lokalt (intet CRAN-spejl). Pakkerne er installeret, så det er uden betydning.

**Resultat pr. job.** Uden vagter er alle trin grønne. To trin var først røde af miljøgrunde (tomt PGPASSWORD) og
blev grønne, da de blev genkørt med en dummy. Med vagterne (enforce) er disse trin røde:

| Job | Trin | Første fejl (enforce) |
|---|---|---|
| evidence-promotion-db | 02 kumulativ migrationssti | `db-verify.sql:6724` fact på person -99 |
| evidence-promotion-db | 03 frisk schema-sti | samme (sidste kommando i trinnet; alle tidligere tests og ceremonier i trinnet er grønne) |
| interpretation-proposal-db | 02 og 03 (begge katalogrækkefølger) | samme, i scriptets db-verify |
| writer-1939-v50-db | 06 reimport writer fra pre-153 | `test-reimport-name-completion.sql:880` fact på person -153109 |
| writer-1939-v50-db | 35, 36, 37, 41 (opgraderingsharnesses 6d-1, 6d-2a, 6d-3, 6e-2) | `db-verify.sql:6724` |
| writer-1939-v50-db | 42 og 46 | `test-publication-persona.sql:54` narrativ omdøbt til familie -621017, som ikke findes |
| narrative-record-contract-db | 08 fuld historisk db-verify | `db-verify.sql:6724` |

Alle andre trin er grønne med vagterne.

I ren enforce stopper hvert rødt trin ved første fejl, så resten af trinnet når ikke at køre. Det gælder fx db-verify
efter l. 6724 og R-testene i trin 42. **Kørslen `enforce_kendte` dækker resten: alle trin i alle 4 jobs er grønne.**
Kun `install.packages` fejler, af miljøgrunde. Vagterne ramte kun de 13 kendte steder (201 advarsler i alt).

- Det gælder også alle R-baserede samtidighedstests:
  - `test-reimport-writer-locking.R`;
  - `test-narrative-record-concurrency.R` med 34 asserts;
  - `test-publication-persona-concurrency.R` og `test-publication-identity-concurrency.R`;
  - `test-source-text-revision-concurrency.R`.
- Vagternes `FOR KEY SHARE` gav altså ingen nye deadlocks eller timeouts i de eksisterende racetests.

**Inventar (warn).** Warn-varianten kører alt til ende og tager de samme låse som enforce. Hele CI rammer vagten 13
steder. Linjenummeret er sætningens linje. psql melder slutningen af DO-blokken.

| Sted | Række | Vej | Klasse |
|---|---|---|---|
| `db-verify.sql:6724` | fact på person -99 | testens INSERT | a |
| `db-verify.sql:7199/7202` | note på person 1 | `_version_upsert_row` (restore-hjælperen) kaldt af testen | a |
| `db-verify.sql:7305` | narrative på person 1 | testens INSERT | a |
| `db-verify.sql:7407` | narrative på person 1 | testens INSERT | a |
| `db-verify.sql:7502` | narrative på person -999904 | testens INSERT | a |
| `db-verify.sql:7625` | note på person 1 | testens INSERT | a |
| `db-verify.sql:8565-8574` | 6 påstande på fact -1 (CHECK-test for `date_certainty`) | testens INSERT; vagten fyrer før CHECK | a |
| `db-verify.sql:8810/8819` | relation person -999951 → medie | `red_relation` kaldt af testen | a |
| `db-verify.sql:8888` | relation person -999941 | `red_relation` | a |
| `db-verify.sql:9008` | relation person -999942 | `red_relation` | a |
| `db-verify.sql:9212/9213` | relation person -999943 | `red_relation` | a |
| `tests/sql/test-publication-persona.sql:54` | narrative omdøbt til `family` med personens id | testens UPDATE | a |
| `tests/sql/test-reimport-name-completion.sql:880` | fact på person -153109 | testens INSERT | a |

- **Klasse a** (13): testen skriver om en forælder, der ikke findes. Den rettes i Task 8 ved at seede forælderen.
  Ved `test-publication-persona.sql:54` skal testen have en familie med det id eller pege på en eksisterende familie.
  I alle 13 tilfælde ville den rigtige skriver have gjort det samme med en eksisterende forælder.
- **Klasse b** (en rigtig skriver, vagten bryder): **0.** Det er bekræftet af `enforce_kendte`. De fire `red_relation`-steder er en skriver, men den kaldes
  med ikke-eksisterende personer. Det er netop det, vagten skal afvise (F-7).
- `FACT_HAR_EVIDENS` blev ikke ramt nogen steder i CI.
- Delta-reviewets D-5-liste (6724, 7304, 7500, 7625) er bekræftet. De øvrige 9 steder er nye. Det samlede antal er
  13.

Kontrol af, at vagterne var aktive: warn-loggene har 12 gennemførte db-verify-kørsler og 12 brud ved l. 6724.

**Ikke dækket:** ingen trin er sprunget over. Opgraderingsharnesses, der bygger deres egen base, fik vagterne gennem
den påhæftede `db-migrations.sql`. Den gamle `schema.sql` fra `git show <commit>` fik dem ikke, men skemaet bliver
altid migreret bagefter.

### 3.6 Anbefaling til hovedsessionen

Fakta til go/no-go-kriterierne i planen:

1. **»Ingen 40P01 i de serialiserede tilfælde«: opfyldt.**
   - Alle scenarier med planens orden gav 0 deadlocks i tre kørsler.
   - Positive kontroller viser, at cyklerne ville være kommet med v2.1-ordenen eller uden L5b.
2. **»Alle CI-jobs grønne«: ikke opfyldt, men kun af klasse a.**
   - 13 teststeder skriver om ikke-eksisterende forældre.
   - Planen tillader at rette dem i Task 8 ved at seede forælderen.
   - Ingen rigtig skriver brydes.

Min anbefaling er **go med betingelser**:

- Task 8 retter de 13 teststeder (seed forælderen).
- Task 8 lægger vagterne i `schema.sql` og sørger for, at `db-migrations.sql` ikke genskaber de gamle kroppe bagefter
  (F-5).
- Task 8 gør `validate_entity_description_subject` til SECURITY DEFINER (F-6).
- Global Constraints' samlede loft via `SET LOCAL statement_timeout` ændres (F-4), fordi det ikke virker inde i
  funktionen.
- Task 11 kører de samme scenarier mod den rigtige `red_slet_person_helt`. Skelettet sletter langt mindre og kan
  derfor ikke stå i stedet for den rigtige funktion (3.3).
- Det rigtige preview skal mindst indeholde memberships, medierelationer, X∪Y og kandidatrækker. Ellers bliver de
  fail-closed-udfald fra F-3 til stille tab.
