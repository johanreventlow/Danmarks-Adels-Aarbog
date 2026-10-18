# Trin 5b del 2b-ii — nye personer, de 14 ægteskaber uden ægtefælle og klausul-dispositionen (#151)

**Status:** Design godkendt af projektejeren 2026-10-17 i brainstormen. Projektejeren valgte tre ting:
- omfang **B**: vejen til nye personer plus de 14 ægteskaber uden ægtefælle-persona; børnene udskydes til 2b-iii;
- dispositionsregel **2**: identitetsregel pr. aktør;
- forslag via **A**: deterministisk andet gennemløb og et forudfyldt, privat ark; ingen model læser teksten.

Under spec-skrivningen viste et fund, at nye personer med `levende=true` aldrig bliver synlige. En familie med
ét skjult medlem bliver også skjult helt (`db-rls.sql:114-124`). En uafhængig rådgiver (fable) blev spurgt.
Projektejeren valgte derefter 2026-10-17 to ting:
- **»ja«:** en ny ægtefælle må erklæres afdød efter en aldersregel med projektejerens bekræftelse pr. linje
  (token `D`);
- **»vent«:** en ny ægtefælle, der ikke kan erklæres afdød (`N`), oprettes ikke i 2b-ii.

**GODKENDT af projektejeren 2026-10-17** (decisions-post samme dato).

**Roadmap:** trin 5, delspec 5b, del 2, skive b, anden halvdel. Dokumenterne kaldes herefter:
- »hovedspecen«: `docs/superpowers/specs/2026-10-06-trin5b-relationspersonas-design.md`;
- »2b-i-specen«: `docs/superpowers/specs/2026-10-11-trin5b-2b-i-genbinding-og-aegtefaeller-design.md`, merget i #241.

Spec'en bygger også på 2a-specen og bevisrapporterne for del 1, 2a og 2b-i. Beslutninger: `docs/decisions.md`
2026-10-06, 2026-10-10, 2026-10-11 og 2026-10-12. Beslutningerne i §14 står i decisions-posten
2026-10-17.

## 1. Adgangskrav (roadmap)

| Krav | Svar |
| --- | --- |
| Roadmapmål | Trin 5 (#151) |
| Værdikædeled | Udtræk → identitetsafgørelse → **oprettelse af ny kanonisk person** → relationsafgørelse → binding → klausulens disposition |
| Leverancetype | Generel motor: (1) `family.id` som identity i `schema.sql`; (2) writer-operationen `relation_person_create`, den første kildebundne vej til en ny person siden 1939-importen; (3) writer-operationen `relation_disposition`; (4) et andet udtræksgennemløb med et privat undtagelsesark. Profilen er udgavebundet (`relation-persona-2018-20-v2`); motoren er det ikke |
| Redaktionel/læserrettet værdi | Ægtefæller, som bogen nævner, men som databasen mangler, kan oprettes med kilde, i stedet for at blive stående som uafgjorte forslag. Forventet ca. 11 nye, afdøde ægtefæller (`D`), der kan blive synlige ved prod-overførslen, plus de S-sager, der ender som samme person. 2-3 `N` venter, og ingen person oprettes skjult. Omkring 121 klausuler får en disposition, der svarer til sandheden: identiteten er afgjort, og fortolkningen venter |
| Færdigbevis | §10: i en kopi af 2b-i's bevisbase; arket er hash- og versionsbundet; kanonisk delta præcist lig de oprettede personer, familier og navnekæder; 2b-i's 230 bindinger er uændrede; dispositionerne er talt; negativtests |
| Erstatter | »new_person_needed« som blindgyde (sagen kunne kun parkeres); de 14 parkerede ægteskaber uden vej frem; `afventer_identitet` som permanent tilstand, også når identiteten er afgjort |

## 2. Afgrænsning

**I 2b-ii:**
1. `family.id`-driften (hovedspecen §22.3).
2. De 14 `relation.marriage`-påstande uden ægtefælle-persona: andet udtræksgennemløb og ark (§5).
3. `relation_person_create` (hovedspecen §8.4 og §5.2.1) **kun for arkets D-linjer** (§6). Den eksisterende
   `new_person_needed` fra 2b-i's kø og arkets N-linjer venter. De oprettes, når dødsoplysninger kan
   dokumenteres.
4. Efterkørslen: afgørelse og binding af det, der bliver frigjort (§7).
5. `relation_disposition` med regel 2 (§8).

**Uden for 2b-ii:**
1. De 14 `relation.child`. Hovedspecen §22.9 lovede dem et design »i del 2«, men barnet som kandidat og
   påstandens ordrette tekst på linjen er et selvstændigt design. Det udskydes til **2b-iii**
   (projektejerens valg 2026-10-17).
2. De 3 uafklarede ægtefæller (parkeret i 2b-i).
3. De 7 ægteskaber, der er blokeret af dobbelte familier (#240).
4. `mention.person` (20).
5. Ægtefællers fødsel og død som promotionregel (hovedspecen åbent punkt 3).
6. Prod-overførsel (§12).

## 3. Udgangspunkt (målt 2026-10-17 i `daa5b_2b_i_bevis_20261012093656`, læse-kun)

| | |
| --- | --- |
| Identiteter i kilde 1 | `primary` 587 `accepted`; `spouse` 230 `accepted`, 3 `unresolved`, 1 `unresolved`/`new_person_needed` |
| Den ene nye person | Hovedpersonen har 0 partnerfamilier og ingen fødsels- eller dødsår, og klausulen har intet år og intet †. Den bliver derfor `N` under enhver regel og venter |
| Synlighedsgrundlag for de 14 (målt af fable) | 13 kan føres til en hovedperson. Alle 13 hovedpersoner er afdøde med dødsdato, og 12 er født før 1900. Klausulerne: 0 har †; 11 har kun årstal ≤ 1920; 1 har et år ≥ 1950; 1 har intet år. Ingen `person.death`- eller `person.birth`-forslag citerer de 14 klausuler. Spec'ens `existing`-familieplads gælder for 0 af 13 |
| `levende` i dag | Load sætter `levende` med en 100-årsregel, og ukendt fødselsår giver afdød (`load_daa.R` ved linje 1037). Feedets nødbremse er 120 år (`packages/feed/src/levende.ts`, `LEVENDE_ALDERSGRAENSE`). Ingen SQL afleder kolonnen; den sættes direkte af writerne |
| Relationspåstande | `relation.marriage` 223 `accepted` (alle med persona), 11 `proposed` med persona (7 i #240, 4 med uafklaret identitet), **14 `proposed` uden ægtefælle-part**; `relation.parent` 7/2/1; `relation.child` 14 `proposed` |
| De 14's parkeringsårsag (del 1) | `ikke_ordret` 6, `intet_navn` 6 og 1 hver af `flere_klausuler`, `tvetydigt_spaend` og `ingen_hovedperson` (del 1 parkerede 15 i alt; én af dem er ikke en af de 14) |
| `family.id` | Prod-kopi: `GENERATED BY DEFAULT AS IDENTITY`, sekvens 755, max(id) 749, 682 familier. `schema.sql`: `BIGINT PRIMARY KEY` uden default, og `red_opret_union` i `schema.sql` indsætter `max(id)+1` (`db-migrations.sql` har en senere definition, der bruger default) |
| Klausuldispositioner | `afventer_identitet` 390, `fortolkning_foreslaaet` 176, `afventer_fortolkning` 145, `erstattet` 197, `maskinelt_flagget` 76; alle maskinelle |
| `afventer_identitet` i detaljer | Forslag om en anden aktør end hovedpersonen (`persona_role='other'`) gemmes **uden** persona: 704 af de citerende ikke-relationsforslag har `source_persona_id` NULL. Strengt pr. aktør (§8.2) kan **121** klausuler skifte nu. 76 klausuler har afgjorte relationsparter, men også aktørforslag uden persona. 158 har kun aktørforslag uden persona. 35 har relationsparter uden afgjort identitet |

## 4. `family.id`

1. `schema.sql`: `family.id BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY`, og `red_opret_union` i
   `schema.sql` indsætter uden id (som den senere definition i `db-migrations.sql`).
2. `db-migrations.sql`: en idempotent blok. Kolonnen gøres til identity, hvis den ikke allerede er det
   (`ADD GENERATED BY DEFAULT AS IDENTITY`). Derefter sættes sekvensen til
   `greatest(max(id), sekvensens nuværende værdi)`, så den aldrig går baglæns. Er kolonnen allerede identity
   (prod), ændres kun sekvensen og kun opad.
3. `db-verify.sql`: tjekker, at `family.id` er identity, og at sekvensen er ≥ max(id).
4. Ingen anden kode må indsætte et eksplicit `family.id`. En repo-vagt (test) finder `INSERT INTO family(id`.

## 5. De 14: andet gennemløb og ark

### 5.1 Rækkefil

Rækkerne er præcis de 14 påstande: `relation.marriage`, `proposed`, ingen ægtefælle-part, i kilde 1.
De udtrækkes med samme felter som del 1's rækkefil og samme kanoniske serialisering (projektionens
`::text` + LF, som 2b-i-specen §5.3). Tilføjelsen er hovedpersonens kandidater til ægtefælle:
- hovedpersonens nuværende partnere (person-id, navn, år, familie, ordenstal);
- det samme fra hver eksisterende partnerfamilie.

Filen ligger privat (0600 under `~/.private/5b-2b-ii/`).

### 5.2 Udtræk (profil `relation-persona-2018-20-v2`)

Udtrækket er en ren Python-funktion over rækkefilen. Del 1's regler genbruges med fire udvidelser:
1. **Ordret spænd via normalisering.** Påstandens tekst og klausulens tekst sammenlignes efter
   `narrative_norm_v1`. Spændet regnes tilbage til klausulens originale tegn (tegnafbildning fra den
   normaliserede tekst). Er afbildningen ikke entydig, bliver linjen U.
2. **Klausulvalg.** Ved flere citerede klausuler vælges den eneste, hvor påstandens normaliserede tekst står.
   Ingen eller flere ⇒ U.
3. **Mere tilladende navneregel.** Navnet må også stå uden »med«, hvis klausulen begynder med »Gift« og et
   stort bogstav følger inden for samme sætning. »Gift <år>.« uden navn ⇒ I.
4. **Forslag.**
   - Navnet deler mindst halvdelen af sine led med en af hovedpersonens nuværende partnere, og præcis én
     opfylder det ⇒ **S** med den partners id.
   - Et navn uden sådan et match, hvor klausulen har mindst ét årstal, og alle årstal er ≤
     `deceased_cutoff_year` ⇒ **D**.
   - Et navn uden match, der ikke opfylder D ⇒ **N**.
   - Ingen hovedperson (`ingen_hovedperson`) ⇒ U.
5. **Aldersreglen.** `deceased_cutoff_year` = 1921 er en fast konstant i profilen, og den står i rækkefilen og
   dermed i dens hash. Den følger af feedets 120 år og en laveste vielsesalder på 15 år: 2026 − 120 + 15.
   En ægtefælle, der er gift senest 1921, er mindst 120 år i 2026. Konstanten skifter kun med en ny profil.

### 5.3 Arket

Linjeformatet er som 2b-i: `M <interpretation_key> <version> : <tok>  # note`. Tokens:
- **S**: samme som forslagets partner. Partnerens id står i linjens kommentar og i rækkefilen, ikke i tokenet.
- **D**: ny person, afdød ifølge aldersreglen (§5.2 pkt. 5). Projektejeren bekræfter hver D-linje: højst 14,
  så alle gennemses, ikke en stikprøve. Linjen viser klausulens årstal og grænsen.
- **N**: ny person, der ikke kan erklæres afdød. Der oprettes ingen person, og sagen venter.
- **I**: intet navn i bogen.
- **U**: uafklaret.

Ved S, D og N står det foreslåede navnespænd ordret over linjen. Det rettes ikke på linjen. Er spændet
forkert, er svaret U. Linjen viser også:
- bogens klausul;
- hovedpersonens navn og år;
- de nuværende partnere med år og familie;
- forslagets grund (fx »ordret efter normalisering«).

Som i 2b-i gælder:
- arket er forudfyldt med forslagene;
- projektejeren retter kun undtagelser;
- arket hash-bindes ved godkendelse, sammen med rækkefilens hash og den præcise id-mængde;
- værktøjet printer kun tal og hashes.

### 5.4 Anvendelse

Værktøjet laver tre ting af arket og rækkefilen. Hver del fejler lukket og tjekker først, at rækkefilen er
aktuel (projektionens hash i skrivetransaktionen):

1. **Persona-manifest** for S-, D- og N-linjer. Det er autorisationspayloads til den eksisterende writer-operation
   `relation_persona` (hovedspecen §5.2.1) med profil `relation-persona-2018-20-v2`, og operationen godtager
   nu begge profiler. Det kører som batch med den eksisterende runner, som i del 1.
2. **Identitetsscript** (psql, hash-bundet som 2b-i's ark, `standard_conforming_strings` låst) efter
   batchen, med `basis: human_sheet`:
   - S ⇒ `red_afgoer_source_persona(…, 'same', <partnerens id>, …)`;
   - D ⇒ `red_afgoer_source_persona(…, 'new_person_needed', NULL, …)` med konteksten
     `deceased: {rule: "vielsesaar-120-v1", cutoff_year, clause_years, sheet_sha256, line}`;
   - N ⇒ `red_afgoer_source_persona(…, 'new_person_needed', NULL, …)` uden `deceased`. Personaen og
     afgørelsen ligger kun i det private lag; der oprettes ingen kanonisk person.

   Det eksisterende kald kræver, at personaen findes (skabt i trin 1). Planens første task skal også
   verificere, at kernen godtager `same` uden `candidate_id` med `basis: human_sheet`, som 2b-i's kø gjorde
   med `web_detail`. Gør den ikke, er rettelsen at køre kandidatgeneratoren for de nye personas før
   scriptet, og så sendes kandidatens id med.
3. **I og U** skriver intet. De tælles i beviset.

## 6. `relation_person_create`

Som hovedspecen §8.4 (kerne-oprindelse og writer-operation) og §5.2.1 (autorisation, receipt og
efterprøvning). Præciseringer:

1. **Population:** gældende identiteter med `unresolved`, `reason: new_person_needed`, `basis: human_sheet`
   **og en `deceased`-kontekst** (§5.4), hvor personaen er gældende `spouse`-part. Altså kun arkets
   D-linjer. Kernen afviser `relation_person_create` uden `deceased`
   (`RELATION_PERSON_CREATE_NOT_DECEASED`). Writeren kan derfor aldrig oprette en levende eller skjult person,
   og en skjult person kan aldrig skjule en synlig familie. Manifestet bygges af en læse-kun projektion og
   hash-bindes.
2. **Familieplads:**
   - `existing`, når hovedpersonen har præcis én partnerfamilie, familien har præcis én partner (hovedpersonen),
     og familiens ordenstal er NULL eller lig `marriage_ordinal`;
   - ellers `new` (`type='vielse'`, ordenstal = `marriage_ordinal` for begge partnere).

   `family.id` tildeles af identity-kolonnen (§4), aldrig af writeren.
3. **`citation_label`** = postnøgle + side, som name-completion-writeren.
4. **`levende = false`** og `staged = true`. Det afviger fra hovedspecen §8.4 (se §14). Grundlaget kopieres
   fra identitetens `deceased`-kontekst til receiptet (`deceased_basis`) og efterprøves ved finalisering.
   Der skrives intet dødsfaktum, for der er ingen dato, kun »afdød ud fra alder«. Kun navn og familieplads.
5. **Kanonisk delta pr. sag:**
   - præcis 1 `person`, 1 `fact`, 1 `assertion`, 1 `citation`, 1 `conclusion`;
   - ved `new`: 1 `family` og 2 `family_member`;
   - ved `existing`: 1 `family_member`;
   - personens og familiens `change_set` som writerens eksisterende mønster.

## 7. Efterkørsel

Som 2b-i-specen §7 og uden ny kode:
1. `red_preview_relation_decisions` / `red_decide_relation_interpretations` for kilde 1;
2. bind-preview og binding;
3. derefter en genkørsel, der skal give 0.

Ægteskaber, hvor begge parter nu har `accepted` identitet og en entydig struktur, afgøres og bindes. Det
gælder de S-linjer og de nye personers ægteskaber, hvor familien er oprettet eller fundet i §6.

## 8. Klausul-disposition (regel 2)

### 8.1 Errata til hovedspecen §8.2 og §5.2.1

Hovedspecen krævede, at *alle* påstande, der citerer klausulen, er afgjort. Den regel erstattes af regel 2 her.
Grunden: `afventer_identitet` betyder, at en anden aktør end hovedpersonen endnu ikke er identificeret. At
fortolkningerne venter, er `fortolkning_foreslaaet`.

### 8.2 Regel pr. aktør

En klausul går fra `afventer_identitet` til `fortolkning_foreslaaet`, når **alle** følgende gælder i
skrivetransaktionen:
1. Dens gældende disposition er `afventer_identitet`, og den er maskinel (`decided_by_kind='machine'`).
   Klausulen skifter aldrig oven på en menneskelig disposition.
2. Ethvert gældende ikke-relationsforslag, der citerer klausulen, har en persona
   (`source_persona_id IS NOT NULL`), og den personas identitet er `accepted`. Et aktørforslag uden persona
   (`persona_role='other'` ved ingest) blokerer. Vi gætter ikke på, hvem det handler om.
3. Enhver gældende relationspåstand, der citerer klausulen, har mindst én part ud over `principal`, og hver
   sådan part har en persona med `accepted` identitet.

Om forslagene selv er afgjort, betyder intet. De bliver stående med deres status.

### 8.3 Writer-operation `relation_disposition`

- Element-id `relation-disposition:<observation_id>`.
- Autorisationen er ændret fra hovedspecen: `observation_id`, `from_disposition_version`,
  `citing_interpretation_ids` (sorteret array af de gældende citerende fortolkningers id'er) og
  `actor_persona_ids` (sorteret array af alle personas fra pkt. 2-3).
- Serveren genberegner begge mængder og betingelsen i §8.2 og kræver lighed. Ellers afvises elementet.
- Ny version `from_disposition_version + 1` med `disposition='fortolkning_foreslaaet'`,
  `decided_by_kind='machine'` og `evidence` = `{batch_id, manifest_sha256, rule: "identity-per-actor-v1"}`.
- Receipt (`relation-disposition-receipt-v1`): `observation_id`, `disposition_version`.
- Manifestet bygges af en læse-kun projektion over kilden og hash-bindes. Batchen kører til sidst, efter §7,
  så de nye personers klausuler kommer med.

## 9. Privatliv

- Rækkefil, ark, persona-manifest og scripts ligger i `~/.private/5b-2b-ii/` (0600) og må ikke ligge i et
  git-arbejdstræ (vagten fra 2b-i). Kun tal og hashes kommer i chat, commits og rapport.
- Nye personer oprettes kun som `D`: `levende = false` efter aldersreglen og med projektejerens bekræftelse
  pr. linje, og `staged`. De er skjulte, indtil prod-overførslen aktiverer dem. Derefter gælder den
  almindelige gate (ikke privat).
- Ingen person oprettes med `levende = true`. `N` venter.
- Ingen model læser klausulteksten. Udtrækket er deterministisk (§5.2).

## 10. Færdigbevis (i restore, ikke i prod)

I en kopi af `daa5b_2b_i_bevis_20261012093656`, med før- og efter-hashes som 2b-i:
1. `family.id`: migrationen er kørt (no-op på identity bortset fra sekvensen), og `db-verify` er grøn. I
   fersk CI er familieoprettelse via `red_opret_union` og via writeren uden kollision bevist.
2. Arket er udfyldt og godkendt med hash. Antal S, N, I og U er talt. Persona-batchen er finaliseret,
   identitetsscriptet anvendt, og genkørsel afvises.
3. `relation_person_create`-batchen: kanonisk delta er præcis summen af §6 pkt. 5 over alle sager. Intet
   andet kanonisk ændret (aggregat-hashes som 2b-i). Personerne er `staged` og `levende = false`
   med `deceased_basis`, og `visning_navn` er afledt. Rapporten tæller synlighed: ægteskaber, der kan blive
   synlige ved aktiveringen (D + S), og ægteskaber, der venter (N, I, U).
4. Efterkørslen: antal afgjorte og bundne. 2b-i's 230 bindinger er uændrede (tupel-digest), og genkørsel
   giver 0.
5. Dispositionen: antal skift, forventet ca. 121 plus det, §5-§7 frigør. Hver skiftet klausul opfylder §8.2,
   ingen anden er ændret, og en genkørsel giver 0 elementer.
6. Lukket univers: hver af kildens relationspåstande ligger i præcis én spand, som 2b-i-specen §9 med
   errata §15, plus spandene »I (intet navn)« og »U fra arket«.
7. Negativtests, hver i sin egen kopi:
   - **A** forældet rækkefil (ROWS_STALE, 0 skrivninger);
   - **B** ark-hash passer ikke;
   - **C** `relation_person_create` med forkert identitetsversion afvises;
   - **D** disposition oven på en menneskelig disposition afvises;
   - **E** disposition, hvor et aktørforslag uden persona er kommet til efter manifestet, afvises;
   - **F** `relation_person_create` for en `new_person_needed` uden `deceased` (den fra 2b-i's kø) afvises.
8. Rapport `docs/evidensbaseret-genimport/relationspersonas-5b-2b-ii-bevis.md` plus status og changelog.

## 11. Test

- **pytest:** udtrækket. Normaliseret spænd tilbage til originale tegn, klausulvalg, navneregel,
  forslagsregel og I/U-grænser. Arkets rundtur, identitets- og hash-binding, sti-vagter og citering med
  apostrof og backslash.
- **SQL (CI, fersk schema og opgradering fra main):**
  - `family.id` identity, sekvens og repo-vagt;
  - `relation_person_create` positive veje (`existing`/`new`) og negative veje (forkert version, forkert
    status, persona uden spouse-part, genkørsel);
  - `relation_disposition`: regel §8.2 pkt. 1-3 enkeltvis, aldrig oven på menneskelig, mængdelighed;
  - batch-resultatet med `relation_results`;
  - ende-til-ende som 2b-i's `test-spouse-exception-sheet.sh`.
- **Opgradering:** fra main's head med eksisterende data. Migrationerne køres to gange, og `db-verify` er
  grøn (memory: signaturændring kræver opgraderingstest).

## 12. Prod og fortrydelse

Intet i prod. Overførslen af 5b samlet er en egen spec med runbook og GO. `family.id`-migrationen er en
no-op i prod bortset fra sekvenskontrollen. Nye personer er `staged`, så deres aktivering er en del af
overførslen.

## 13. Kendte begrænsninger

1. Navnereglen er udgavebundet til 2018-20's formuleringer. Andre udgaver kræver en ny profil.
2. »Halvdelen af leddene« kan overse en partner, der er registreret med et helt andet navn (fx titel i stedet
   for fornavn). Det ender som D eller N. Et fejlagtigt D opretter en dublet af en person, der allerede findes,
   og den kan blive synlig. Derfor viser hver D-linje hovedpersonens nuværende partnere, og projektejeren
   ser D-linjerne efter netop for den fejltype. Er der tvivl, er svaret U.
3. Regel 2 frigør ikke klausuler, hvor ægtefællens fødsel eller død er foreslået uden persona (76 målt).
   Det kræver, at ingest knytter aktørforslag til den rette persona. Det er ikke en del af 5b.
4. Nye personer har kun navn. Fødsel, død og andre fakta kommer med promotionreglen (åbent punkt 3).
5. Aldersreglen antager, at klausulens årstal angår ægteskabet eller tiden før. Et senere årstal i klausulen
   giver N, ikke D, så fejlretningen er »venter« og ikke »vises«. Projektejerens bekræftelse pr. linje er den
   anden sikring.
6. `N`-sagerne (2-3 forventet plus den fra 2b-i) kan først oprettes, når ingest knytter ægtefællens
   dødsforslag til personaen, og `person-death-v1` kan afgøre det.

## 14. Beslutninger til `decisions.md` ved godkendelse

1. 2b-ii-omfang B. Børnene flyttes til 2b-iii.
2. Dispositionsregel 2 (identitet pr. aktør) erstatter hovedspecens »alle påstande afgjort« (§8.1).
3. Forslag til de 14 laves deterministisk med et privat ark. Ingen model læser teksten.
4. **Ændrer beslutningen 2026-10-06 pkt. 3** (»`levende = true`, indtil dødsfakta afgøres af et menneske«):
   en ny person oprettes kun, når den kan erklæres afdød. Afgørelsen bygger på aldersreglen (gift ≤
   `deceased_cutoff_year`) og projektejerens bekræftelse pr. linje. Grundlaget gemmes i kvitteringen, og
   `levende = false`. Ellers oprettes personen ikke. `schema.sql`'s kommentar om, at `levende` er »AFLEDT«,
   rettes, så den passer til praksis.

## 15. Errata ved planlægningen (2026-10-17, GODKENDT af projektejeren samme dag)

1. **§5.2 pkt. 1 erstattes.** `narrative_norm_v1` med tegnafbildning finder ikke de 6 `ikke_ordret`. Målt
   (kun tal): alle ord i påstanden står i klausulen (6/6), men påstanden er en omskrivning med udeladte
   dele. Det længste fælles stykke er 17-94 tegn, og ingen simpel normalisering (mellemrum, bindestreg,
   store og små bogstaver) finder den. I stedet bruges **det entydige minimale ordnede ordvindue**:
   - Spændet er det eneste minimale udsnit af klausulen, der indeholder påstandens ord i rækkefølge.
   - Ord er løb af den eksplicitte klasse `[0-9A-Za-zÀ-ÖØ-öø-ÿ]+`, sammenlignet uden forskel på store og
     små bogstaver. Klassen er eksplicit, så PG's `lc_ctype` ikke påvirker resultatet.
   - Python og SQL (`private.relation_ordered_windows`) bruger samme regel, og `write_relation_persona`
     efterprøver den under profil v2.
   - Intet eller flere vinduer ⇒ U.
2. **§5.2 pkt. 2 bortfalder.** `write_relation_persona` kræver præcis én citeret klausul, så sagen med to
   citerede klausuler bliver U.
3. **`privat = false`** sættes eksplicit på nye personer, som det almindelige standardvalg. Grundlaget er en
   trykt kilde og en afdød-erklæring pr. linje. `red_opret_person` sætter derimod `privat = true` for
   redaktørens manuelle oprettelser.
4. **Aktivering kræver overførsels-spec'en** (fund under udførelsen, 2026-10-17). Den eksisterende `cutover`
   fjerner kun `staged` fra personer, der er oprettet af `person_create`. `relation_person_create`-personer
   forbliver derfor `staged` og skjulte i prod, indtil overførsels-spec'en for 5b eksplicit aktiverer dem.
   Det er bevidst: aktiveringen er en del af overførslen (§12). Overførsels-spec'en **skal** dog nævne
   operationen, ellers bliver D-ægtefællerne aldrig synlige.
5. **Aldersreglen skærpes** (fund under udførelsen, 2026-10-17). §5.2 pkt. 5 sagde »gift senest 1921«, men
   udtrækket kan ikke skelne vielsesåret fra andre årstal i klausulen, fx ægtefællens fødselsår. Med den
   regel ville »f. 1918« alene give D, selvom personen kun ville være 108 år. Nu skal **alle årstal i klausulen
   være ≤ 1906** (2026 − 120), fordi hvert årstal kan være et fødselsår. Reglen hedder `aarstal-120-v1`, og
   `deceased_cutoff_year` = 1906. Den fejler lukket: tvivl giver N. Projektejeren bekræfter stadig hver
   D-linje.

## 16. Errata ved slutreviewet (2026-10-18, godkendt af projektejeren 2026-10-18)

1. **§6 pkt. 1 holder ikke for `existing`-placeringer** (helgrensreview, Important 1). En
   `relation_person_create`-person er `staged`, og `family_offentlig` er falsk, så snart ét medlem ikke er
   offentligt. Placeres den nye ægtefælle i hovedpersonens **eksisterende** familie, skjules familiens fakta,
   noter og narrativer for læseren, indtil personen aktiveres. Sætningen »en skjult person kan aldrig skjule en
   synlig familie« gælder derfor kun efter aktiveringen. Konsekvenser:
   - Overførsels-spec'en (errata §15.4) **skal** aktivere `relation_person_create`-personer i samme transaktion,
     som batchen lander i prod, eller før batchen publiceres. Den må ikke lade en `existing`-familie stå skjult.
   - Beviset tæller `existing`-placeringer. I 2b-ii's kørsel var der 0, fordi ingen linje blev D. Intet er
     ramt i dag.
2. **Årstal findes med cifergrænser** (helgrensreview, Minor 4, rettet). Ordgrænser overså årstal klistret
   til bogstaver (»1950erne«), og et overset senere årstal kan give D. Udtrækket og writerens genberegning
   bruger nu `(?<![0-9])(1[0-9]{3}|20[0-9]{2})(?![0-9])`.

## 17. Tillæg: runde 2 — navneregel v3 og den første nye person på bogens data (2026-10-18, GODKENDT af projektejeren samme dag)

Designet er godkendt i brainstormen 2026-10-18 i tre dele. En uafhængig rådgiver (fable) vurderede hver del.
Projektejeren valgte:
- omfang **A**: de 12 `U` fra 2b-ii og 2b-i-sagen på ét ark;
- tilgang **2**: bedre regel, og mennesket kan rette, hvor navnet slutter.

Runden er et tillæg, ikke en ny spec. Den sker kun i restore, så review-budgettet er 1 + 1 (decisions
2026-09-23).

### 17.1 Adgangskrav

| Krav | Svar |
| --- | --- |
| Roadmapmål | Trin 5 (#151), 5b |
| Værdikædeled | Udtræk → identitetsafgørelse → **oprettelse af ny kanonisk person (første gang på bogens data)** → binding → disposition |
| Leverancetype | Udgaveprofil `relation-persona-2018-20-v3` (navneregel, titelliste) oven på den generelle motor; to stramninger i writeren `relation_person_create` |
| Redaktionel/læserrettet værdi | Op til 10 ægteskaber får ægtefællen bundet med kilde (proveniens). Én afdød ægtefælle, som bogen nævner, men som databasen mangler, oprettes med kilde. Det sidste ubeviste led før en prod-overførsel bevises på rigtige data |
| Færdigbevis | §17.8 |
| Erstatter | Navneregel v2's blindgyde (titel inde i navnet ⇒ `U`); `relation_person_create` kun bevist syntetisk |

### 17.2 Erratum til §3

§3 siger, at 2b-i's `new_person_needed`-klausul »intet år« har. Det er forkert. Klausulen har ét årstal, 1314.
Projektejeren har læst klausulen 2026-10-18 og bekræftet, at det er et årstal i en persons liv, ikke en
henvisning. Under `aarstal-120-v1` er sagen derfor `D`. Navnet har 3 ord, intet titelord og én partikel.
Hovedpersonen har 0 partnerfamilier, så familien bliver ny (`family_mode` `new`).

### 17.3 Afgrænsning

**Med:**
- de 12 `M`-linjer, der stod `U` i 2b-ii;
- én `P`-linje for 2b-i's `new_person_needed`;
- de to mindre fund fra 2b-ii's slutreview i `write_relation_person_create`: aktuel klausul og fortolkningens
  status.

**Udenfor:**
- klausulopdelingen (fund 4, trin 4; omsegmenteringen er i prod siden 2026-09-28);
- linjen med to klausuler;
- linjen, der venter på hovedpersonens binding;
- `mention.place` (246 klausuler i `afventer_identitet`; decisions-post udsætter);
- børnene (2b-iii);
- #240;
- prod-overførsel;
- de øvrige seks mindre fund;
- **aldersregel v2**. Ingen af de 12 har nul partnertræf og et årstal efter »DAA«, der ville vende sagen. Den
  noteres som ubrugt i decisions-posten. `red_afgoer_source_persona` og årstalsberegningen er uændrede.

### 17.4 Navneregel v3 (`relation_persona_extract_v3.py`)

1. **Navnestart** som v2: første ord med versal efter »med« (eller efter »Gift« + tal). Titler og
   forkortelser før navnet springes over som i v2.
2. **Titler inde i navnet.** Navneløbet fortsætter hen over et ord fra den lukkede titelliste (§17.5), når det
   næste ord har versal. Titlen kommer med i spændet, fordi spændet er bogens tekst i ét stykke.
3. **Partikler**: v2's liste plus `und`, `zu`, `dem` og `genannt`.
4. **Partnersammenligning.** Partikler og titelord fjernes på begge sider. Efternavnet (sidste ord, der ikke er
   partikel) skal være ens. Desuden skal mindst halvdelen af de resterende ord være fælles.
5. **Forslag:**

   | Partnertræf | Forslag |
   | --- | --- |
   | 1 | `S` (et skævt ægteskabsnummer ændrer det ikke; arket viser det) |
   | ≥ 2 | `S` for den partner, hvis familie har påstandens nummer, hvis der er netop én; ellers `U` |
   | 0 | Aldersregel v1 ⇒ `D`, ellers `N`. Begge kræver et titelfrit navn (§17.5), ellers `U` |

   `D` og `N` kræver nul træf, så en eksisterende partner kan aldrig blive oprettet igen. Det var linje 5's
   fælde.

### 17.5 Titelliste

- **Lukket og versioneret i profilen.** Grundord: `greve`, `grevinde`, `komtesse`, `baron`, `baronesse`,
  `friherre`, `friherreinde`, `prins`, `prinsesse`, `hertug`, `hertuginde`. Kun på grundord kan stå præfikset
  `rigs` eller `lens`. Listen kan udvides i planen ud fra Task 0, men kun med ord, der optræder i de 12.
- **Ét sted i hvert sprog.** Én SQL-konstant (`IMMUTABLE`-funktion) og én Python-konstant. En tvillingtest
  læser listen ud af `schema.sql` og sammenligner med Python.
- **Sikring ved `D`.** Hvert ord i navnet skal have versal eller være en partikel. Bogen skriver titler med lille,
  så en titel uden for listen giver `U` i stedet for et navn med titel (decisions 2026-10-03: titel ≠ navn).
- `write_relation_person_create` afviser et navn med et ord fra titellisten (`RELATION_PERSON_CREATE_NAME_TITLE`).
  Det er det eneste sted, hvor navnet bliver kanonisk.

### 17.6 Arket (`ark-v3.txt`, privat, hash-bundet)

**Rækkefil.** `relation_persona_v2_input` uændret (de 12) plus `P`-rækken. `P`-rækken bygges af
eksisterende kø-/detalje-RPC'er (`red_source_persona_queue`, `red_source_persona_detail`), hvis de giver
klausul, årstal og den tidligere afgørelse. Ellers bygges en ny læsefunktion, og planen begrunder det.

**`M`-linjer.**
- Format: `M <key> <ver> : <tok> [navn: »…«] [# note]`.
- `navn:` må kun skrives, hvor reglen har fundet en navnestart. Teksten skal begynde præcis ved navnestarten.
  Mennesket retter kun, hvor navnet slutter. Teksten skal stå ordret og netop én gang i klausulen og ligge inden
  for spændet.
- Ved et rettet navn genberegnes forslaget (§17.4) på det rettede navn, og det tilladte svar følger det nye
  forslag. Mennesket kan altså løfte `U` til `S`, men kun når reglen da finder præcis én partner.
- Arket viser »nr. i bogen ≠ nr. i familien« tydeligt på et `S`-forslag med skævt nummer.
- Ved `D` viser arket hele posten, ikke kun klausulen. Spørgsmålet er: »Gælder et senere årstal ægtefællen?«

**`P`-linjen.**
- Format: `P <source_persona_id> <identity_version> : D|N|U`.
- Den viser den tidligere afgørelse (basis, dato, note), hele posten og årstallene.
- `D` er kun tilladt, når aldersregel v1 giver `D` og navnet er titelfrit.
- `N` og `U` skriver intet.
- Versionen hentes fra rækkefilen og sendes til `red_afgoer_source_persona` som forventet version (ikke 0).
  Noten henviser til den version, der erstattes.

**Fejl.** Forkert format, forkert identitet, et ikke-tilladt svar, et `navn:`, der ikke står ordret og entydigt
efter navnestarten, eller en hash, der ikke passer, gør, at værktøjet stopper uden at skrive nogen filer.

### 17.7 Databasen (`schema.sql` og `db-migrations.sql`, holdt ens)

1. **`write_relation_persona`** godtager profilen `relation-persona-2018-20-v3`. Kontrollen er den samme som for
   v2: ordvindue og navn inden for spændet. Profil v3 kræver tre nøgler: `name_basis` (`rule` eller `sheet`),
   `sheet_sha256` og `sheet_line`. De ligger hash-bundet i autorisationen og kopieres til `reimport_event`.
   Der kommer ingen nye kolonner.
2. **`write_relation_person_create`:**
   - afviser et titelord i navnet (§17.5);
   - kræver, at mentionens klausul er `clause_observation_current`;
   - kræver, at den citerende fortolkning ikke er afløst.
3. **Titellisten** som SQL-konstant med grants som de øvrige private hjælpefunktioner.
4. **`db-verify.sql`** asserter profil v3 i writerens whitelist, titelfunktionen og eventuelle nye rettigheder.

### 17.8 Bevis (i en ny kopi af `daa5b_2b_ii_bevis_20261017132417`; selve basen røres ikke)

**Task 0, tørkørsel.** Den læser kun og viser kun tal. Den skriver to ting ned:

- **Fordelingen:** `S`/`D`/`N`/`I`/`U` over de 12 og `P`. Også hvor mange navne der ville kræve en `navn:`-rettelse,
  og hvor mange `S` med skævt nummer.
- **For `P`:**
  - `marriage_ordinal`;
  - at `relation_person_create_family(principal, ord)` er NULL;
  - at klausulen er `clause_observation_current`;
  - `clause_years`.

Afviger fordelingen fra designet (fx et `D` blandt de 12), stopper jeg og spørger projektejeren.

**Kørsel:**
1. Arket.
2. Projektejerens godkendelse, hash-bundet.
3. Persona-batch (`S`).
4. Ét identitetsscript (`S` og `P` i samme transaktion).
5. `relation_person_create` (forventet 1).
6. Efterkørsel (afgørelse og binding).
7. Disposition.

**Rapporten måler:**
- bindinger = 232 + antal `S` + 1. Den nye persons ægteskab bindes som alle andre (`structural_family`);
- nye `ordinal_afvigelse`-klassifikationer;
- den nye person: `staged`, `levende=false`, `visning_navn` = bogens tekst og titelfri;
- kæden fakta → påstand → citation (kilde 1, side) → konklusion;
- 1 ny familie og 2 `family_member`;
- identiteten `accepted` med `deceased` i evidensen;
- `verify_relation_person_create_receipts` grøn;
- arkets hash ens i persona-kvitteringen og i identitetsevidensen;
- **anon-læsningen uændret**, de kendte hashes, så den nye person ikke kan ses før aktivering;
- aggregat-hashes ens bortset fra netop de nye rækker;
- dispositionen: hvilke klausuler der skifter, og hvilke der venter (fx på `mention.place`). Der bygges ingen
  undtagelse;
- genkørsler giver 0.

Rapporten siger udtrykkeligt, at kun `family_mode` `new` er bevist. `existing` (errata §16.1) er stadig
ubevist, og overførslen skal aktivere i samme transaktion under alle omstændigheder.

**Negativtest på rigtige data** (egne kopier, 0 skrivninger):
- **A:** `P`-linjen køres igen ⇒ `EVIDENCE_IDENTITY_VERSION_CONFLICT`.
- **C:** `U` løftet til `S` på arket uden regelbekræftelse ⇒ `SHEET_TOKEN_NOT_ALLOWED`.

### 17.9 Test (CI, opdigtede navne)

- **Python:**
  - et testtilfælde pr. navnemønster: titel inde i navnet, `rigs`/`lens`, `von und zu`, `genannt`;
  - to partnertræf, hvor nummeret afgør;
  - to partnertræf uden afgørelse ⇒ `U`;
  - ukendt titel ⇒ `U`;
  - `navn:` der ikke er ordret, der begynder før navnestarten, eller der står to gange ⇒ afvist;
  - `P` besvaret `D`, hvor reglen siger `N` ⇒ afvist;
  - tvillingtest for titellisten.
- **SQL:**
  - profil v3 med og uden de nye nøgler;
  - `relation_person_create` afviser titelord, afløst klausul og afløst fortolkning (tidligere negativtest D,
    flyttet til CI);
  - persona-kvitteringen bærer `sheet_sha256`.
- **Uændret:** 2b-ii's tests for v2.
- Hele CI-suiten kører lokalt, plus opgraderingstesten fra main.

### 17.10 Dokumenter

- bevisrapport `relationspersonas-5b-navneregel-v3-bevis.md`;
- status;
- changelog;
- decisions-post: `mention.place` udsættes udtrykkeligt (246 klausuler venter, ingen læserværdi nu); aldersregel
  v2 er designet, men ubrugt.

Oprydning sker først efter måling og projektejerens ja.

### 17.11 Kendte begrænsninger

- `existing`-familie er ubevist (§16.1).
- En afskåret klausul kan skjule et senere dødsår. Værnet er, at hele posten vises ved `D`, og at mennesket
  bekræfter.
- Titellisten dækker kun de ord, der er set i 2018-20. Andre udgaver kan kræve flere, og en ukendt titel giver
  `U`.
