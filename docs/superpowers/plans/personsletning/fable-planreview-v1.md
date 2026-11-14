## Review af implementeringsplanen for fuld personsletning

**Dom: ikke klar.** Designet holder, men planen mangler de sværeste afgørelser og har fire fejl, der enten stopper sletningen eller efterlader indhold. Én revisionsrunde på planen bør være nok.

Jeg har kun læst kode. Intet er kørt mod en database, `count.sql` er ikke læst, og base-commit `81d36706` er ikke kontrolleret (ingen git). Linjenumre er `schema.sql` i worktreen, medmindre andet står.

---

### Kritisk

**K-1. Slettegrafen og hvert steds behandling står ikke i planen (Task 1 step 3, Task 5 »justeres her«).**
- Spec §9 kræver, at den præcise slettegraf står i planen. Planen udskyder den til implementeren.
- Inventaret kan kun udtrykke DELETE (`vaelg_sql` → pk → slet pr. `fase`). Mindst otte steder er ikke rene sletninger:
  - S5 `profiles` nulstilles.
  - S27 `haendelse.fact_id/relation_id` løsnes.
  - S37 medier slettes kun, hvis de er eksklusive.
  - S32 `feed_pin` findes ved tekstmønster.
  - S35 skal beregnes før S2 slettes.
  - S23b, S44, S46 og S50 er fælles rækker for mange personer (fx cutover-kvitteringen l. 17390), som hverken kan slettes eller opdateres.
- Følge: `purge_toemmer_alt` (»count.sql = 0«) og spec §7's færdigbevis kan ikke bestå for de fælles rækker, uden at nogen har afgjort, at de er tilladt rest.
- **Rettelse:** tilføj kolonnen `handling` (`slet` / `nulstil` / `loesn` / `bevar_andres` / `blokér`) og skriv en tabel S1-S58 + M5 ind i planen med handling, fase og begrundelse. Få de fælles jsonb-rækker godkendt af projektejeren som »id i andres historik«.

**K-2. Personens tidligere slettede rækker overlever i historikken (Task 6, reglen »row_pk er en af de slettede rækker«).**
- `person_purge_raekker` læser levende rækker. Et faktum, en relation eller et narrativ om personen, der blev slettet for et år siden, findes kun i `change_event.foer` med fuldt indhold (kortlægningen S54: mængderne F\*, R\*, A\*, N\*).
- Planens regel rammer dem ikke. Indholdet bliver stående, og `red_fortryd_change_set` (l. 9578-9590) kan genskabe et faktum med `subjekt_id` = den slettede. Der er ingen FK på den polymorfe kolonne, så intet stopper det.
- Det bryder spec §2, §4 og §6.3a. Spec §7 forudsætter selv »lukningen over change_event«.
- **Rettelse:** historik-stederne skal bruge lukningen fra kortlægningens nøglestier. Fixturen skal have et tidligere slettet faktum, en slettet relation og et slettet narrativ. Test: ingen `change_event` med indholdet, og fortryd af det gamle sæt genskaber intet.

**K-3. Det uafhængige persontjek i `person_purge_tilladt` modsiger spec §6.9 (Task 2).**
- Planen: en typet person-kolonne i rækken skal være lig manifestets person.
- Spec §6.9: hele identitetsstrømmen slettes, også ældre events med `canonical_person_id` NULL eller en anden person (personaen var først koblet til Q, senere til P).
- Sådanne rækker afvises af triggeren, og hele sletningen fejler. Er NULL tilladt, står det ikke i planen. Samme problem for `reimport_event.canonical_person_id` fundet via payload.
- `counterpart_person_id` på forældrekort (l. 19432) er ikke på kolonnelisten. Et kort fundet via `partner_ids` tilhører en andens fortolkning, og planen siger ikke, om det slettes.
- **Rettelse:** manifestet får en `grund` pr. række (`egen` / `hel_stroem` / `andres_ref`). Triggeren kræver lighed kun for `egen` og kræver for `hel_stroem`, at personaens nuværende tilstand peger på manifestets person. Tilføj tests for NULL og anden person.

**K-4. Den nye sektion kan ikke ligge efter `red_slet_person_preview` (Filstruktur).**
- Inventaret har `tabel regclass NOT NULL`. Rækkerne peger på tabeller, der oprettes senere i filen: `narrative_publication_event` (13825), `identity_control_parent_card` (19432), `relation_reopen` (20263), `text_revision_reconciliation` (21377).
- En frisk base fejler i Task 1.
- **Rettelse:** læg sektionen sidst i `schema.sql`. Bedre: gør inventaret til en funktion med `VALUES` i stedet for en tabel. Så dækkes det af harnessens sammenligning af funktionskroppe, og ingen kan ændre rækker med dynamisk SQL i prod. Projektet har samme lære fra `version_pk_registry` (db-rls 980-994).

---

### Vigtig

**V-1. Låserækkefølgen er omvendt af de eksisterende identitetsskrivere (Global Constraints; Task 8 b).**
- `red_afgoer_source_persona` tager kildelåsen først (l. 11239), derefter persona `FOR UPDATE` og `lock_family_rows` på personen inde i kernen (l. 10446-10460).
- Sletningen tager personen først og kildelåsen sidst, og kalder derefter kernen, som låser personaen.
- Resultatet er deadlock (40P01). Det er fail-closed, men Task 8 b forventer »serialiseret«.
- **Rettelse:** tag kildelåsene tidligt, sorteret efter kilde-id (en person kan have personas i flere kilder), og genlæs bagefter. Alternativt acceptér 40P01 i testen og vis »prøv igen« i UI'et. Det afviger fra spec §6.12 og skal noteres som beslutning.

**V-2. `app.person_purge_xid` som GUC (Task 3) genindfører det, det tidligere review afviste (»Manifest, ikke GUC«).**
- En klient kan ikke sætte den gennem PostgREST, så misbrug udefra er usandsynligt.
- Men den beviser intet strukturelt: enhver serverfunktion eller direkte forbindelse kan sætte den.
- **Rettelse:** brug kvitteringsmønstret fra `person_create_receipt` (l. 10387, 10474): kernen forbruger en række (`source_persona_id`, `xact_id`), som kun sletningen skriver, eller den slår op i manifestet.
- Oprindelsen gemmes ikke på eventen. `purge_persona_ikke_en_person` kan derfor kun teste evidensen, ikke »oprindelse person_purge«.

**V-3. UPDATE-grenen i triggerfunktionerne er unødvendig og farlig (Task 2).**
- `narrative_legacy_publication` har ingen append-only-trigger, kun `validate_narrative_legacy_publication` (l. 14007). Den tillader allerede `latest_event_id := NULL` og DELETE.
- Fjern UPDATE-ændringen helt.
- Fjern også `reject_interpretation_predicate_mutation` (ordforråd uden personindhold) og `reject_narrative_record_cutover_receipt_mutation` (fælles kvittering) fra listen. Ret kun de funktioner, hvis tabeller faktisk har `handling=slet`.
- Kald i `reject_evidence_mutation` skal skrives som trinvise `IF`. Funktionen bruges også af TRUNCATE-sætningstriggere og har `search_path=pg_catalog`.
- Den kører som kalderen: en rolle uden EXECUTE på `person_purge_tilladt` får »permission denied« i stedet for `EVIDENCE_APPEND_ONLY`. db-verify matcher på den tekst (l. 2623-2637).

**V-4. Testene beviser ikke det, de påstår (Task 5).**
- `purge_toemmer_alt` og `purge_andre_uaendrede` måler med `person_purge_raekker`, altså med inventaret selv. Et sted, inventaret mangler, mangler også i beviset.
- `count.sql` ligger i sessionens scratchpad, ikke i repoet, og er aldrig kørt. CI kan ikke bruge den.
- **Rettelse:**
  - Læg `count.sql` i `tests/sql/` og kør den.
  - Tilføj en inventar-uafhængig søgning efter `-987654700` og »Testperson Purge« i `row::text` for alle tabeller i `public` og `private`, med en navngiven liste over tilladt rest.
  - »Andre uændrede« skal være en hash over alle rækker i alle berørte tabeller minus manifestets mængde.
  - Sletningen skal committes i testen. De udskudte triggere (`identity_state_has_event`, l. 1964) kører ikke ved ROLLBACK.

**V-5. Rulingen om at droppe udbakken (§6.7) holder teknisk, men ikke som bevis.**
- Janitorens kategori b fanger filer uden medie-række: `find_orphan_objects` (R/media-janitor.R 162-178) sammenligner bucket-indholdet med `media` og `media_variant`. Læsere og anon kan ikke se filerne.
- Tre forbehold:
  - Janitoren køres manuelt, sletter kun med `--slet`, og først efter 7 dage som standard.
  - Stierne returneres én gang. Lukkes fanen efter commit, findes der ingen liste over, hvad der mangler.
  - Redaktører kan stadig læse forældreløse filer (db-rls `media_obj_redaktion`), så »usynlige« gælder ikke dem.
- For en GDPR-sletning af en levende persons billede er det svagere end udbakken.
- Specen er godkendt af projektejeren. Ændringen skal godkendes af ham, ikke rettes i Task 9.
- **Rettelse:** runbook-trin efter hver sletning (`Rscript R/media-janitor.R` skal vise 0 forældreløse for de returnerede stier, ellers `--slet --frist-dage 0`), og §7's »udbakke tom« erstattes af det tjek.

**V-6. Blokeringen `aaben_koersel` har forkert grænse og for smalt omfang (Task 4).**
- Statusserne er `sealed` / `passed` / `failed` (l. 19414). En forseglet kørsel uden afslutning er arket ude hos mennesket.
- Planens test siger »efter forsegling ingen blokering«. Det ødelægger et igangværende ark: `mapping` peger på kandidat-id'er, der slettes (l. 11275).
- **Rettelse:** blokér til `passed` eller `failed`. Blokér også, når personen er kandidat i en andens stikprøve eller står på et forældrekort.
- Spec §6.6 nævner også kandidatkørsel, reimport- og publiceringsbatch samt `persona_awaiting_control`. Planen har hverken blokering eller test for dem.

**V-7. Katalogvagten dækker ikke specens krav (Task 1).**
- Den matcher på tabel. En ny person-kolonne i en tabel, der allerede er i inventaret, slipper igennem. Spec §8 siger »tabel eller kolonne«.
- »jsonb med kendte nøgler« kan ikke ses i kataloget på en tom CI-base.
- `bigint[]` (`partner_ids`) og tekstnøgler (`feed_pin`) fanges ikke.
- **Rettelse:** inventaret får en kolonneliste. Vagten kræver, at hver FK-kolonne, hvert type/id-par og hver jsonb-, array- og tekstkolonne i `public`/`private` enten er dækket eller står på en undtagelsesliste med begrundelse.

**V-8. Huller mod spec §6 og §8.**
- Beviset for, at ingen andre summaries bærer navn (§6.3a, §9), mangler. `historik_navn_vaek` tester kun fixturens navn. Tilføj en statisk gennemgang af alle `begin_change_set(`-kald.
- Linkblokering: `note.indhold` mangler i testen (§6.6 nævner den).
- Fortryd af et bevaret sæt kan genindsætte `[[person:<id>|Navn]]` i en andens levende tekst. Det er et dødt link, som §4 kalder en fejl. Ikke testet.
- Samtidighed mod publicering og kandidatkørsel (§8) mangler i Task 8.
- Id-genbrug testes kun for person, familie og narrativ. §6.8 nævner også fact, relation, assertion, media og change_set.
- Task 7's rettelse af l. 9558 er selvmodsigende: grenen kører netop, når der ingen sekvens er. Erstat den med en fejl.
- `preview_rollegate_foerst`: anon har ikke EXECUTE og får »permission denied«, ikke »Kun redaktion«. Brug `fixtures/kalder-matrix.sql`.
- Ingen slutkontrol i funktionen. En samtidig skriver, der ikke låser personrækken (polymorfe fakta har ingen FK), kan efterlade en rest. Kør `person_purge_raekker` igen før retur og fejl ved rækker.

**V-9. Rækkefølge og fixture.**
- Task 5's test kræver tælling 0, men historikken slettes først i Task 6. Flyt testen eller slå de to tasks sammen.
- Én fixture bruges af Task 4-7, men Task 5 sletter den. Den skal genopbygges pr. testgruppe.
- Task 6 vil have sæt lavet af `red_opret_person`. Den giver sekvens-id, ikke `-987654700`. Skriv, at historikken fabrikeres direkte.
- Fixturen »spor på alle steder« kræver gyldige kæder i ca. 20 ledgers med valideringstriggere. Det er planens største arbejde og står som én linje. Giv den egen task og genbrug de eksisterende fixtures (`publication-identity.sql`, `relation-*.sql`).

---

### Mindre

- **Prod (Task 10):** der mangler et dump umiddelbart før projektejerens sletning af 1791; dumpet før DDL er ikke nok. Fortryd-DDL kan ikke fortryde en udført sletning; skriv det i runbooken.
- **Tidlig måling:** kør forhåndsvisningen for 1791 på prod-kopien, før resten bygges. Blokerer `anden_promotion` på familie 742/743, har første brug ingen vej frem, og planen har ingen oplåsningssti.
- **Timeout:** mål under den faktiske `authenticated`-timeout. Sletningen kører lukningen to gange (genberegning + manifest).
- **Base-commit:** planen bruger `81d36706`; de øvrige 6e2-harnesser i `ci.yml` bruger `ac194bfd`. Bekræft, at den svarer til prods skema.
- **db-verify:** tilføj assert på, at kun `red_slet_person_helt` skriver til manifestet, og at inventarets indhold (hash) ikke er drevet.
- **Mobil:** rør ikke mobilens typer; `Change` bor kun i `web/src/data/redaktionWrite.ts`.

---

### Svar på de fem spørgsmål

1. **Dækning af specen:** huller i §6.2 (K-3), §6.3/§9 (K-1), §6.3a (K-2, V-8), §6.6 (V-6, V-8), §6.8 (V-8), §6.12 (V-1) og §8 (V-4, V-7, V-8).
2. **Teknisk gennemførlighed:**
   - `to_jsonb(OLD)`, `xid8`, `pg_current_xact_id()` og `regclass`/jsonb-nøgler virker på PG 17.
   - Dynamisk `vaelg_sql` er sikker, så længe kun ejeren kan skrive inventaret; gør det hellere til en funktion (K-4).
   - GUC'en bør erstattes af en kvittering (V-2).
   - Ændringen af den delte `reject_evidence_mutation` kan lade sig gøre med forbeholdene i V-3.
3. **Rulingen om udbakken:** janitoren fanger filerne, men uden frist-garanti og uden liste over fejlede. Den kræver projektejerens ja og et runbook-trin (V-5).
4. **Rækkefølge og tests:** se K-4, V-4 og V-9.
5. **Prod:** dump lige før sletningen, tidlig måling af blokeringer for 1791 og janitor-tjek efter.

Rådgiverværktøjet svarede ikke (timeout), så vurderingen er ikke efterprøvet af en anden.

Filer:
- `/Users/johanreventlow/TypeScript/danmarksadelsaarbog/.worktrees/personsletning/docs/superpowers/plans/2026-11-14-fuld-personsletning.md`
- `/Users/johanreventlow/TypeScript/danmarksadelsaarbog/.worktrees/personsletning/docs/superpowers/specs/2026-11-14-fuld-personsletning-design.md`
- `/Users/johanreventlow/TypeScript/danmarksadelsaarbog/.worktrees/personsletning/schema.sql`
- `/Users/johanreventlow/TypeScript/danmarksadelsaarbog/.worktrees/personsletning/R/media-janitor.R`
- `/private/tmp/claude-501/-Users-johanreventlow-TypeScript-danmarksadelsaarbog/9b3be062-d637-472a-9e0e-3a1aee03026a/scratchpad/purge/count.sql` (ikke i repoet, aldrig kørt)
</agent-message>

