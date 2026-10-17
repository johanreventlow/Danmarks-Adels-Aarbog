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

