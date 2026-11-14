# Delta-review af plan v2.1 (Opus, 2026-11-14)

**Dom:** Ingen af de tre tilføjelser kan implementeres som skrevet. L8 (SHARE ROW EXCLUSIVE) giver to konkrete deadlock-veje, som planen ikke dækker. Eksistensvagten får mindst 4 kendte db-verify-blokke til at fejle, og den er kun halvdelen af en FK. FORTRYD_DOED_LINK kan bygges, men tjeklisten er forkert, og den ene retning mangler.

Mærker: [målt] = katalog/count på `daa5ab_ddl_standin_20261113220424_g3`, [læst] = læst i `schema.sql`/`db-verify.sql` på grenen, [udledt] = ræsonneret uden test.

**D-1 (høj): En redaktørskrivning, der låser rækker før den åbner sit change_set, giver nu deadlock.** Plan Task 11 step 1b og Global Constraints »L8«.
- Fire funktioner tager rækkelåse før `begin_change_set` uden nogen af låsene L4-L7 [læst]:
  - `red_ret_ocr_felt`: `source`+`person_external_id` FOR UPDATE (l. 2055-2058), person (l. 2067), og først derefter `begin_change_set` (l. 2127)
  - `red_ret_paastand`: person FOR UPDATE (l. 10164), når påstanden ikke kommer fra en fortolkning, og sættet åbnes først ved l. 10314
  - `red_reverse_placement_membership`: membership-rækken (l. 3365) før sættet (l. 3369)
  - `red_slet_medierelation_uden_evidens`: relationen (l. 7426) før sættet (l. 7442)
- Forløbet er det samme i alle fire. Skriveren W har sin række. Sletningen får SHARE ROW EXCLUSIVE, fordi W endnu ikke har en lås på change_set, og venter så ved L9/L10 eller en DELETE på W's række. W's INSERT i change_set kræver ROW EXCLUSIVE og venter på SHARE ROW EXCLUSIVE. Resultatet er 40P01 [udledt]. Med den gamle ROW EXCLUSIVE var der ingen cyklus, fordi ROW EXCLUSIVE ikke konflikter med sig selv.
- OCR-tilfældet er det værste. Låsen ligger på `source`-rækken, altså hele udgaven, så en OCR-rettelse på en **hvilken som helst anden** person i samme udgave kan ramme sletningen.
- db-verify's ocr_lock-test (omkring l. 6100-6200) beviser i dag kun serialiseringen mod `red_slet_person`, fordi begge tager ROW EXCLUSIVE. Den samme test mod den nye sletning ville give 40P01.
- Step 1b søger kun i den modsatte retning (L4-L7 taget efter sættet).
- **Rettelse:** Step 1b skal også liste alle funktioner, der tager rækkelås eller laver DML på rækker, som sletningen låser eller sletter, **før** deres første lås på change_set. Søgningen skal følge kaldte helpers og triggere; min søgning dækkede kun direkte statements.
  - Ret de fire ved at åbne sættet først. Det er samme orden som `red_slet_person` (l. 7192-7200).
  - Tilføj et statisk CI-tjek og testen »OCR på en anden person i samme kilde, samtidig med sletningen«.

**D-2 (høj): Narrativskriverne giver en cyklus mod L6-før-L8, uanset låsetilstand.** Slettegraf §6.2 punkt 3-4 og Task 11 (c).
- `narrative_record_state(p_lock=true)` låser i denne rækkefølge [læst]: `source_record` FOR UPDATE (l. 15223), så ACCESS EXCLUSIVE på change_set (l. 15228), så person (l. 15232), og **derefter** `source_persona` FOR UPDATE (l. 15271) og `source_persona_identity` FOR UPDATE (l. 15292).
- To skrivere kalder den kun under delt kontraktlås og uden kilde- eller skriverlås: `mutate_person_narrative_record` (l. 15975, l. 15993) og `reverse_narrative_publication_event` (l. 16500, l. 16533).
- Rækkefølgen, der giver deadlock: sletningen holder L6 (P's persona). W får ACCESS EXCLUSIVE, før sletningen når L8. Sletningen venter ved L8, og W venter på personaen. Det gælder også med ROW EXCLUSIVE.
- Test (c) fanger det kun, hvis interleavingen tvinges. Lad en tredje session holde `samme_som_mutation`, så sletningen står stille mellem L6 og L8.
- **Rettelse:** Indsæt L5b, `source_record` FOR UPDATE for P's records sorteret efter id, før L6. Så venter W allerede ved sit første skridt. At låse bogens lag er ikke at slette det.
  - Alternativet er at flytte L8 før L6, men det kræver D-1-rettelsen først (`red_ret_paastand` tager identity FOR SHARE før sættet).

**D-3 (middel): `lock_timeout='5s'` er ikke en tilstrækkelig sikring.**
- `deadlock_timeout` er 1s [målt på stand-in; prod er ikke målt]. Derfor slutter cyklusserne i D-1/D-2 som 40P01, før timeouten når 55P03. Offeret er typisk den, der kom sidst i køen, altså redaktørens RPC.
- `lock_timeout` gælder pr. ventende lås, ikke samlet. Sletningen kan holde L4-L8 i k×5 s.
- Skrivepausen starter allerede, mens sletningen står i kø til L8: alle nye `begin_change_set` stiller sig bagved.
- Autovacuum på change_set tager SHARE UPDATE EXCLUSIVE, som konflikter med SHARE ROW EXCLUSIVE. Autovacuum afbrydes efter ca. 1 s, men det gør en manuel VACUUM/ANALYZE ikke.
- **Rettelse:**
  - Skriv »5 s pr. låseventning«, og ret decisions/spec (»giver op efter 5 s«).
  - Tilføj `SET LOCAL statement_timeout` (fx 30s) som samlet loft.
  - UI'et skal oversætte 40P01 til »Prøv igen« på **begge** sider, ikke kun 55P03 hos sletningen.
- l. 14359 er ikke præcedens. Den ligger i engangs-cutoveren under den eksklusive kontraktlås (l. 14348), hvor ingen redaktører skriver samtidig. Fjern henvisningen.

**D-4 (verificeret OK): De indlejrede `decide_source_persona_identity`-kald og samme_som er lukket** [læst].
- Alle syv kald (l. 4370, 4480, 5964, 11355, 18535/18544, 18722) tager `lock_reimport_writer` eller kildelåsen for personaens kilde først. De er derfor dækket af L4/L5, forudsat at sources(P) i L3 indeholder kilderne for X∪Y.
- Alle 11 steder med `samme_som_mutation` tager låsen før sættet, også `red_slet_relation` (l. 7351 før l. 7354).
- `red_relation` afviser samme_som (l. 7294). Triggeren ved l. 7716 nås derfor kun med låsen allerede taget.
- Uden for `schema.sql` tager kun de frosne R-scripts lås på change_set.

**D-5 (høj for CI): db-verify fejler med vagten slået til, og det skyldes ikke rækkefølge** [læst].
- l. 6724: fact på person -99
- l. 7500: narrative på person -999904
- l. 7304 og l. 7625: narrative/note på person 1. `tests/sql/run-db-verify-disposable.sql` seeder kun person -987659901.
- Step 4b siger »ret rækkefølgen, ellers stop«. Med disse fejl stopper den hver gang.
- **Rettelse:** tillad at testen seeder den manglende forælder. Det svækker ikke vagten.
- `tests/sql`: 44 filer med 103 polymorfe INSERTs er ikke gennemgået.

**D-6 (middel): Påstanden om note 72 er forkert.** `_version_upsert_row` sætter alle snapshot-kolonner i SET (l. 9465), så `UPDATE OF target_type,target_id` fyrer, også når værdierne er uændrede. En fortrydelse, der rører note 72, fejler derfor.
- **Rettelse:** vagten returnerer tidligt ved UPDATE, når (type, id) IS NOT DISTINCT FROM OLD. Det sparer også låse under fortryd.

**D-7 (middel): Vagten er kun barnets halvdel af en FK, så forældreløse rækker kan stadig opstå.**
- En fortrydelse af et INSERT-sæt (opret person/familie/fakta) sletter forælderen. B9 tjekker kun sættets egne rækker, så børn fra senere sæt bliver forældreløse [læst, l. 9573-9590].
- Familie 54 blev slettet i et sæt med operation `red_slet_familie_link`, som også slettede person og fakta. Ingen funktion i schema'et sletter `family` [målt + læst]. Det skete uden for de kendte stier.
- db-verify-assertet »0 forældreløse undtagen note 72« bliver rødt i prod.
- **Rettelse:** en BEFORE DELETE-vagt på person/family/fact efter mønstret i `guard_relation_evidence_delete` (l. 7395). `red_slet_person` og sletningen sletter børn først, så de er forenelige. Ellers et efter-tjek i fortryd.

**D-8 (lav): Mindre forhold ved vagten.**
- Lås begge ender i id-orden (personer før familier), så den passer med de sorterede FOR UPDATE-tagere.
- Der er ingen CHECK på `subjekt_type`. db-verify l. 6942 bruger `'Person'`, som går uden om vagten. Sammenlign med `lower()` eller tilføj en CHECK. I dag er der 0 rækker med store bogstaver [målt].
- Ydelse: én plpgsql-SELECT pr. række, og den første KEY SHARE pr. person skriver xmax. Det er ubetydeligt ved prod-størrelser (7193 fakta) [målt/udledt].

Verificeret om vagten [målt/læst]:
- Fortrydelsens rækkefølge er sikker for historikken: 0 sæt, hvor et barn er slettet efter sin forælder. `red_slet_person` sletter børn først (l. 7210-7251).
- Egne DELETEs i samme transaktion konflikter ikke med egen KEY SHARE. En række, transaktionen selv har slettet, er usynlig, så vagten afviser korrekt.
- `suggestion` og `story` er tomme i prod-kopien (0 NULL-subjekter).

**D-9 (middel): FORTRYD_DOED_LINK.**
- **Kan implementeres.** Saml (tabel, id) i løkken som `v_notes`/`v_narr`, og tjek efter løkken og regenereringen. En exception ruller hele fortrydelsen tilbage.
- **`suggestion` står ikke i `version_pk_registry`** [målt], så fortryd genskaber den aldrig. Punktet er dødt; fjern det.
- **»Narrativer afvises allerede« er forkert.** Afvisningen ved l. 9500-9527 gælder kun narrativer med publiceringshændelse eller legacy-række. 8 narrativer har ingen af delene [målt], og gamle `red_slet_person`-sæt genskaber narrativer. `narrative.tekst` skal med i tjekket.
- **Legitime fortrydelser:** i dag er der 0 døde links i note, narrative, story og entity_description [målt].
  - Afvis alligevel kun links, som fortrydelsen **indfører**: sammenlign med `v_cur`. Ellers bliver en senere fortrydelse af et urelateret felt låst for altid.
  - Skriv eksplicit, at `p_force` ikke omgår tjekket.
- **Den manglende retning:** en fortrydelse, der *sletter* en person/familie/medie (inverse af INSERT), efterlader døde links i andre tekster. Tjek `text_mention` (findes kun for narrative/note) og parse story/entity_description for de slettede id'er. Hænger sammen med D-7.
- **Generisk alternativ til den håndholdte kolonneliste:** `jsonb_each_text(ev.foer)` gennem `parse_mentions`.

**Ikke verificeret:** helpers og triggere, der låser før `begin_change_set` (kun direkte statements er søgt); fixtures i `tests/sql`; `deadlock_timeout` i prod.

Filer:
- `/Users/johanreventlow/TypeScript/danmarksadelsaarbog/.worktrees/personsletning/schema.sql`
- `/Users/johanreventlow/TypeScript/danmarksadelsaarbog/.worktrees/personsletning/db-verify.sql`
- `/Users/johanreventlow/TypeScript/danmarksadelsaarbog/.worktrees/personsletning/tests/sql/run-db-verify-disposable.sql`
- `/Users/johanreventlow/TypeScript/danmarksadelsaarbog/.worktrees/personsletning/docs/superpowers/plans/2026-11-14-fuld-personsletning.md`
- `/Users/johanreventlow/TypeScript/danmarksadelsaarbog/.worktrees/personsletning/docs/superpowers/plans/personsletning/slettegraf.md`