# Task 11: samtidighed og opgradering

Implementeret på feat/personsletning, base 5d7e53da. Runtime-porten er åben: ingen databasekommandoer er kørt af implementeren.

Scope: den afgrænsede dataintegritets-/redaktionsafbrydelse i decisions 2026-11-14, ikke en omprioritering af trin 6. Generel leverance på identitets-/publiceringsleddet: én sikker fuld oprydning af fejlprofil frem for manuel delsletning. Færdigbevis er SAMTIDIG_OK og UPGRADE_OK i hovedsessionen/CI. Den gamle red_slet_person bevares.

## Scenarier og mutationer

00000 betyder succes; P0001 skal desuden matche det tilladte domænefejlsnavn i scriptet. 40P01 accepteres kun i r37_name. Begge rækkefølger køres, undtagen a/h/R37, der har én specifik interleaving.

| Scenarie | Krav | Mutation, som testen skal fange |
|---|---|---|
| a_same | S lykkes, W FINDES_IKKE/PREVIEW_AENDRET; ingen rest | manglende genkontrol efter ventning |
| b_identity | kildelåsen serialiserer; drift afviser eller oprydning lykkes | flyttet/fjernet kildegate |
| c_publish/j_reverse | record/AE-serialisering; j har rigtig holder af samme_som mellem L6b/L8 | fjernet L5b eller AE før record |
| d_candidates | kildelåsen serialiserer, ingen 40P01 | fjernet kandidatkildelås |
| e_fakta/e_medie/e_pin | S52b/S53 bekræftes før race; ingen 40P01; ingen rest efter evt. ny preview/sletning | fjernet L6b (S53 med force), genopstandet FK-løs række, manglende R33-pinmål |
| f_fact | W først: S venter og afviser preview; S først: W venter og afvises | subjektvagt uden KEY SHARE: observatørens transaktionsventning mangler |
| g_assert/g_note | ventning på eksisterende fact i begge retninger; evidens/drift afviser; facit-id'er er væk efter oprydning | notevagt uden KEY SHARE: g_note/W-først giver ingen fact-ventning, også hvis sluttjek stadig afviser. g_assert alene kan være maskeret af regen(person) |
| g_parent | familieventning i begge retninger, ingen assertion mod død familie | objektvagt uden family KEY SHARE eller forkert triggerorden |
| pin | målventning før eksisterende pin-upsert | lås i pin-trigger i stedet for før upsert, eller fjernet mållås |
| i_ocr/i_paastand/i_membership/i_medie | W pauses før begin_change_set, S venter på dens tidligere rækker; begge retninger uden 40P01 | L8 ændret til SHARE ROW EXCLUSIVE danner D-1-cyklus |
| media_link | L11b/eksistensvagt serialiserer; delt medie bevares efter vellykket purge | fjernet media KEY SHARE/L11b eller ignorering af ny deling |
| media_variant | FK/medielås serialiserer; ny variant ændrer preview, eller FK afviser efter purge | fjernet L11b eller manglende variant i preview/udbakke |
| r39 | W først: purge afvises, gældende andres binding bevares; S først: writer fejler lukket | fjernet S39f/non-principal-spouse-blokering |
| h_timeout | 55P03 efter 5 s; hele public/private-tabelindhold er byte-uændret | forkert timeout eller delvis committet sletning |
| r37_name | præcis én 40P01, anden side committer; ingen tabers manifest/navnepåstand, derefter ingen rest | slugt deadlock eller delvis succes/læk fra taberen |

Alle opryddede scenarier kræver også den eksisterende uafhængige person-purge-count.sql med eksplicitte før-mængder; dens godkendte S52b/S55-undtagelser er uændrede. R39/W-først kræver bevidst bevaret P og binding. Ingen tekstlink-race tilføjet: R38 er fortsat accepteret.

## Testmekanik og drift

Hver race bruger en createdb -T-kopi af den rigtige fixtur og den rigtige red_slet_person_helt. Ingen spike-funktion installeres. Sessions-id'er kommer fra application_name; observatøren kræver pg_blocking_pids samt ventet locktype og i f/g den forventede relation. Holderen annulleres med pg_cancel_backend; ingen timing alene afgør testens udfald. Kun h kræver et langt søvnvindue (10 s). Korte polling-vinduer er bounded; sessions har 20 s statement_timeout.

Kun kopierne modtager person-purge-concurrent-hooks.sql: en trigger ved generationens UPDATE (L7), en ved manifestets INSERT (L13), pause efter den eksisterende lock_identity_people-krop (R37/L10), pause ved begyndelsen af begin_change_set (D-1), og en AFTER INSERT-krog på fact (f). Fact-krogen holder W efter KEY SHARE men før regen_person_visning kan maskere den med en person-UPDATE-lås. De oprindelige hjælperkroppe bevares, og purge-RPC'en ombyttes aldrig. S-først ved almindelige data-scenarier holder hele den færdige purge ucommittet bag en advisory-gate; det giver de konkrete tuple-låse uden produktionspausepunkter.

Opgradering: f9f2cd9c's bootstrap/schema/migrations/RLS → nuværende migration+RLS to gange. Frisk reference: HEAD bootstrap/schema/RLS. Alle public/private-funktioner uden extension-ejerskab registreres med fuld pg_get_functiondef og proacl (inklusive NULL). Samtlige nye/ændrede/fjernede signaturer mellem base og frisk sammenlignes efter hver passage; hele kataloget skal være uændret mellem passage 1 og 2. Ingen hash bruges som erstatning for byte-sammenligning.

Scripts beholder databaser som standard; kun PURGE_DROP_DBS=1 rydder vellykkede oprettelser fra samme kørsel. Ingen forudgående drop eller --if-exists. Logmapper fra mktemp -d beholdes. CI har separate trin for samtidighed og opgradering. Estimat på CI: 41 races, ca. 1–3 minutter inkl. kopier/tællinger; opgradering ca. 20–60 s. Det er et skøn, ikke en måling.

## Step 1b: låseliste i begge retninger

**P2-4 færdigdisponeret 17/11 efter projektejerens R41/R42-afgørelser.** Ingen ny cyklus uden for R37/R41/R42 fundet i denne statiske runde. Afgrænsningen og værdikæden er rapportens eksisterende dataintegritets-/redaktionsafbrydelse; dette færdiggør låseinventarets reviewbevis, ikke Task 11's samlede runtime-port.

Grafen følger nu funktionskald og DML → tabellens BEFORE-/AFTER-/constraint-triggere, også deferred kontroller. INSERT/UPDATE følger deklarerede FK'er med KEY SHARE på refererede rækker; DELETE følger CASCADE/SET NULL til barnets DML og triggere. De genererede append-only- og log_change-triggere udvides fra skemaets arrays/versionsregister; dynamisk versions-DML er eksplicit udvidet over registerets tabeller. TSV-kolonner: funktion, sted, låsetabeller (direkte eller FK), direkte kald, DML/triggerkanter, FK KEY SHARE-kanter; `-` betyder intet fund i kolonnen. SQL-strenge tæller ikke længere som funktionskald: den gamle kandidat `private.apply_narrative_record_contract_acl` udgår som ACL-streng, ikke eksekveret writer.

Begge efterspurgte kæder er synlige: `private.write_record_placement` → INSERT i `private.source_record_placement_decision` → BEFORE `private.validate_placement_decision` → `source_record FOR UPDATE` (schema.sql:2374); samt `red_suggest` → INSERT i `suggestion` → BEFORE `private.validate_polymorf_subjekt_findes` → `person/family FOR KEY SHARE` (schema.sql:23484). Placement har desuden sin AFTER CONSTRAINT `private.require_placement_initial_decision`. Grafen er konservativ: grene, WHEN og UPDATE OF filtreres ikke; regex-inventaret beviser ikke runtime-fuldstændighed eller FK-triggernes katalogrækkefølge.

**R42 — accepteret family → person-inversion.** P er allerede `barn` i F; `red_tilfoej_barn(F,P,'plejebarn')` er gyldigt. S holder `person(P) FOR UPDATE` fra L10; W får `family(F) KEY SHARE` i RI-kontrollen og venter derefter på person-FK'ens KEY SHARE; S venter ved L11 på F. Det er samme accepterede klasse som `_tjek_partner_loft`: familie FOR UPDATE før person-FK. Afgørelsen omfatter enhver family_member-indsættelse i en familie, hvor P er medlem, med denne præcise familie → person-kant; den er ikke en generel accept af andre låseinversioner.

Projektejeren oplyser runtime-bevis 17/11: `k_plejebarn` giver præcis én 40P01, den anden transaktion committer, derefter ingen rest; `k_plejebarn_w` giver lukket `PURGE_LOCKSET_DRIFT`. I den nu læste `test-person-purge-concurrent.sh` hedder S-først-scenariet `k_plejebarn_s` (samme interleaving som ejerens `k_plejebarn`); W-først hedder `k_plejebarn_w`. Scriptet kræver præcis én 40P01 i S-først, lukket domænefejl i W-først og uafhængig restkontrol efter gentagelse. Ingen runtime kørt i denne runde. Den afprøvede generelle person-først BEFORE INSERT-trigger er backlog, ikke en rettelse i Task 11.

**R41 — accepteret sen change_set ved D-1.** W låser domænerækken før `begin_change_set`; L8's ROW EXCLUSIVE er kompatibel. Åbnes W's sæt om P efter sletningens plan, afviser slutkontrollen med `PURGE_REST: S52` (`i_membership_w`) eller `S53` (`i_medie_w`). Det er lukket, uden delvis sletning; nyt preview/forsøg rydder op. R41 accepterer denne slutkontrolkant, ikke en ny deadlockklasse.

Dispositionerne nedenfor er konkrete statiske begrundelser, med scenarier kun hvor de prøver den anførte fælles kant. Observationer, fortolkninger, occurrences og placements bevares af purge: en lås på disse rækker er derfor ikke i sig selv en modsat purge-kant. ACCESS SHARE fra almindelige SELECTs konflikter ikke med purgens DML; deferred læsekontroller bliver ikke til tuple-låse ved commit.

| Funktion | Sted | Test eller begrundelse |
|---|---|---|
| `_ensure_foraeldrefamilie_redaktionel` | `schema.sql:7931` | g_parent_s/g_parent_w dækker assertionens family-KEY-SHARE-kant. Eksisterende conclusion → trg_regen_from_conclusion → person-UPDATE er R37-kanten (r37_name); ingen senere writer-/kildegate. |
| `_tjek_partner_loft` | `schema.sql:8100` | R42: partnergrenen tager family FOR UPDATE før family_member-INSERTs person-FK KEY SHARE; modsat purge L10(person) → L11(family). Andre børneroller returnerer før triggerlåsen, men RI kan stadig give R42; k_plejebarn_s/k_plejebarn_w. |
| `_version_delete_row` | `schema.sql:9383` | Dynamisk versions-DML/row-lock, ikke tekstligt tabelnavn; K5 prelocker personer/pinmål før øvrige rækker. e prøver den reelle inverse. |
| `_version_lock_row` | `schema.sql:9332` | Dynamisk versions-DML/row-lock, ikke tekstligt tabelnavn; K5 prelocker personer/pinmål før øvrige rækker. e prøver den reelle inverse. |
| `_version_upsert_row` | `schema.sql:9341` | Dynamisk INSERT/UPDATE over versionsregisteret. e_fakta/e_medie/e_pin prøver K5-calleren. Ved family_member-restore i en familie med P gælder R42: family-FK/partner-trigger før person-FK kan stå mod L10 → L11, hvis målpersonen ikke allerede er prelocked; ikke en ny klasse. Identitetsrelationer bruger prelock_identity_relation_update. |
| `begin_change_set` | `schema.sql:9238` | Lokale rækker (change_set); ingen senere writer-/kilde-/samme_som-gate i kroppen. RE via begin_change_set/log_change er kompatibel med L8; FK/eksistensvagt binder eventuelle nye mål. Ingen separat race. |
| `enforce_relation_evidence_target` | `schema.sql:7233` | g_assert: fact/relation KEY SHARE før evidens. |
| `enforce_samme_som_invariants` | `schema.sql:7528` | Delegerer til `private.guard_identity_mutation_snapshot`, `private.lock_identity_people`; samme låsekæde/begrundelse som helperne ovenfor/nedenfor. |
| `log_change` | `schema.sql:9269` | Samme transaktion som den låste DML; skriver change_event, tager ikke en senere writer-/kildelås. |
| `private.apply_narrative_record_cutover` | `schema.sql:14115` | Eksklusiv kontrakt før tabellåse; L1 i purge udelukker overlap. DDL/kontraktceremoni, ingen separat race nødvendig. |
| `private.clause_write_prepare` | `schema.sql:4447` | Writer-gate (L4) før domæne-DML; serialiseres inden purge tager L5b–L11. Wrapper/caller genbruger gaten; ingen separat race. |
| `private.decide_relation_child` | `schema.sql:19095` | Delegerer til `private.lock_family_rows`; samme låsekæde/begrundelse som helperne ovenfor/nedenfor. |
| `private.decide_source_persona_identity` | `schema.sql:10404` | b/R39: persona/state og familie-helper inden identitetsjournal. |
| `private.ensure_reimport_source_evidence` | `schema.sql:4089` | Lokale rækker (person,source_record); ingen senere writer-/kilde-/samme_som-gate i kroppen. RE via begin_change_set/log_change er kompatibel med L8; FK/eksistensvagt binder eventuelle nye mål. Ingen separat race. |
| `private.guard_fact_evidence_delete` | `schema.sql:23526` | g_assert/g_note: sene committed referencer afviser faktumsletning. |
| `private.guard_identity_mutation_snapshot` | `schema.sql:7352` | L7 generation/metadata; samme_som-gaten bevares gennem transaktionen. |
| `private.insert_person_with_receipt` | `schema.sql:10394` | Kun ny personrække, der endnu ikke kan vælges af en anden sessions purge. Callers følger writer-gate. |
| `private.laas_feed_pin_maal` | `schema.sql:23580` | pin/e_pin: person → familie KEY SHARE, før upsert. |
| `private.lock_family_rows` | `schema.sql:18946` | Personer → familier → medlemmer, sorteret. g_parent_s/g_parent_w og r39_s/r39_w prøver fælles låse. R42: modpartens family-FK/partner-trigger → person-FK inverterer L10 → L11; k_plejebarn_s/k_plejebarn_w. |
| `private.lock_identity_people` | `schema.sql:7432` | a/b/e/f/R37: personer stigende FOR UPDATE. |
| `private.lock_reimport_writer` | `schema.sql:4022` | L4: transaktions-advisory pr. source/profil; før domænelåse hos writer-callers. |
| `private.migrate_legacy_narrative_record` | `schema.sql:4251` | Writer-gate (L4) før domæne-DML; serialiseres inden purge tager L5b–L11. Wrapper/caller genbruger gaten; ingen separat race. |
| `private.mutate_person_narrative_record` | `schema.sql:15973` | c/j: delt kontrakt → record-state med p_lock=true → begin_change_set. |
| `private.narrative_record_state` | `schema.sql:15220` | c/j: låsegrenen record → change_set AE → person → publicering/personas; læsegrenen p_lock=false tager ingen låse. |
| `private.person_purge_fortrydelse` | `schema.sql:23036` | Preview-læsning; narrative_record_state kaldes uden låsegrenen. |
| `private.person_purge_preview_fra_plan` | `schema.sql:23297` | Preview-læsning gennem fortrydelse; ingen DML. |
| `private.prelock_identity_relation_update` | `schema.sql:7457` | Delegerer til `private.guard_identity_mutation_snapshot`, `private.lock_identity_people`; samme låsekæde/begrundelse som helperne ovenfor/nedenfor. |
| `private.preview_interpretation_promotions` | `schema.sql:11837` | Delegerer til `private.validate_interpretation_promotion_items`; samme låsekæde/begrundelse som helperne ovenfor/nedenfor. |
| `private.preview_relation_promotions` | `schema.sql:20406` | Delegerer til `private.lock_family_rows`; samme låsekæde/begrundelse som helperne ovenfor/nedenfor. |
| `private.record_legacy_disposition` | `schema.sql:2803` | Lokale rækker (person_external_id); ingen senere writer-/kilde-/samme_som-gate i kroppen. RE via begin_change_set/log_change er kompatibel med L8; FK/eksistensvagt binder eventuelle nye mål. Ingen separat race. |
| `private.record_reimport_legacy_reversal` | `schema.sql:5854` | Delegerer til `private.lock_reimport_writer`; samme låsekæde/begrundelse som helperne ovenfor/nedenfor. |
| `private.reject_evidence_mutation` | `schema.sql:917` | Append-only-afvisning/manifestgate, ingen nye blokerende domænelåse; manifestets autorisation følger den allerede låste purge-transaktion. |
| `private.require_reimport_open_batch` | `schema.sql:4020` | Delegerer til `private.lock_reimport_writer`; samme låsekæde/begrundelse som helperne ovenfor/nedenfor. |
| `private.reverse_narrative_publication_event` | `schema.sql:16499` | j_reverse: record før change_set AE; samme L5b-fraværsejer som c. |
| `private.validate_interpretation_promotion_items` | `schema.sql:11589` | Lokale rækker (source_persona,source_persona_identity); ingen senere writer-/kilde-/samme_som-gate i kroppen. RE via begin_change_set/log_change er kompatibel med L8; FK/eksistensvagt binder eventuelle nye mål. Ingen separat race. |
| `private.validate_placement_decision` | `schema.sql:2347` | Lokale rækker (source_record); ingen senere writer-/kilde-/samme_som-gate i kroppen. RE via begin_change_set/log_change er kompatibel med L8; FK/eksistensvagt binder eventuelle nye mål. Ingen separat race. |
| `private.validate_polymorf_subjekt_findes` | `schema.sql:23456` | f/g/media_link: typeorden person → family → fact → media KEY SHARE. |
| `private.validate_reimport_name_completion` | `schema.sql:5580` | Writer-gate (L4) før domæne-DML; serialiseres inden purge tager L5b–L11. Wrapper/caller genbruger gaten; ingen separat race. |
| `private.validate_source_persona_identity_event` | `schema.sql:1848` | Lokale rækker (source_persona); ingen senere writer-/kilde-/samme_som-gate i kroppen. RE via begin_change_set/log_change er kompatibel med L8; FK/eksistensvagt binder eventuelle nye mål. Ingen separat race. |
| `private.validate_source_record_revision_event` | `schema.sql:1025` | Lokale rækker (source_record); ingen senere writer-/kilde-/samme_som-gate i kroppen. RE via begin_change_set/log_change er kompatibel med L8; FK/eksistensvagt binder eventuelle nye mål. Ingen separat race. |
| `private.withdraw_legacy_narrative` | `schema.sql:16358` | Lokale rækker (change_set); ingen senere writer-/kilde-/samme_som-gate i kroppen. RE via begin_change_set/log_change er kompatibel med L8; FK/eksistensvagt binder eventuelle nye mål. Ingen separat race. |
| `private.write_clause_evidence` | `schema.sql:4638` | Delegerer til `private.clause_write_prepare`; samme låsekæde/begrundelse som helperne ovenfor/nedenfor. |
| `private.write_clause_revision` | `schema.sql:4664` | Delegerer til `private.clause_write_prepare`; samme låsekæde/begrundelse som helperne ovenfor/nedenfor. |
| `private.write_interpretation_proposal` | `schema.sql:5184` | Writer-gate (L4) før domæne-DML; serialiseres inden purge tager L5b–L11. Wrapper/caller genbruger gaten; ingen separat race. |
| `private.write_publication_identity` | `schema.sql:18430` | Writer-gate (L4) før domæne-DML; serialiseres inden purge tager L5b–L11. Wrapper/caller genbruger gaten; ingen separat race. |
| `private.write_publication_persona` | `schema.sql:18267` | Writer-gate (L4) før domæne-DML; serialiseres inden purge tager L5b–L11. Wrapper/caller genbruger gaten; ingen separat race. |
| `private.write_reimport_case_narrative` | `schema.sql:12659` | Lokale rækker (person); ingen senere writer-/kilde-/samme_som-gate i kroppen. RE via begin_change_set/log_change er kompatibel med L8; FK/eksistensvagt binder eventuelle nye mål. Ingen separat race. |
| `private.write_relation_disposition` | `schema.sql:20963` | Writer-gate (L4) før domæne-DML; serialiseres inden purge tager L5b–L11. Wrapper/caller genbruger gaten; ingen separat race. |
| `private.write_relation_person_create` | `schema.sql:20722` | L4 og kildens delte L5-gate før domænerækker; lock_family_rows prelocker principalens personer/familier. Eksisterende familie får kun den netop oprettede person som nyt medlem, hvis person-FK ikke kan holdes af en anden sessions purge. Eventuel familie → person-inversion ved family_member-INSERT hører til R42, ikke en ny klasse. |
| `private.write_relation_persona` | `schema.sql:17989` | Writer-gate (L4) før domæne-DML; serialiseres inden purge tager L5b–L11. Wrapper/caller genbruger gaten; ingen separat race. |
| `private.write_source_text_revision` | `schema.sql:4748` | Lokale rækker (family,family_member,person,person_external_id,source_persona,source_persona_identity); ingen senere writer-/kilde-/samme_som-gate i kroppen. RE via begin_change_set/log_change er kompatibel med L8; FK/eksistensvagt binder eventuelle nye mål. Ingen separat race. |
| `red_activate_1939_v50_batch` | `schema.sql:6157` | Delegerer til `red_activate_reimport_batch`; samme låsekæde/begrundelse som helperne ovenfor/nedenfor. |
| `red_activate_reimport_batch` | `schema.sql:6004` | Writer-gate (L4) før domæne-DML; serialiseres inden purge tager L5b–L11. Wrapper/caller genbruger gaten; ingen separat race. |
| `red_afgoer_relation_interpretation` | `schema.sql:19312` | Delegerer til `private.decide_relation_child`, `private.lock_family_rows`; samme låsekæde/begrundelse som helperne ovenfor/nedenfor. |
| `red_afgoer_source_persona` | `schema.sql:11217` | b: kildelås før decide-helperen. |
| `red_apply_1939_v50_canonical_delta` | `schema.sql:6116` | Delegerer til `red_apply_reimport_canonical_delta`; samme låsekæde/begrundelse som helperne ovenfor/nedenfor. |
| `red_apply_1939_v50_name_completion` | `schema.sql:6202` | Delegerer til `red_apply_reimport_name_completion`; samme låsekæde/begrundelse som helperne ovenfor/nedenfor. |
| `red_apply_1939_v50_person_create` | `schema.sql:6104` | Delegerer til `red_apply_reimport_person_create`; samme låsekæde/begrundelse som helperne ovenfor/nedenfor. |
| `red_apply_1939_v50_source_evidence` | `schema.sql:6093` | Delegerer til `red_apply_reimport_source_evidence`; samme låsekæde/begrundelse som helperne ovenfor/nedenfor. |
| `red_apply_reimport_canonical_delta` | `schema.sql:5703` | Delegerer til `private.lock_reimport_writer`, `private.require_reimport_open_batch`; samme låsekæde/begrundelse som helperne ovenfor/nedenfor. |
| `red_apply_reimport_cases` | `schema.sql:12690` | samme_som-gate før personlåse; samme L7 → person-orden som purge. e med force/a prøver denne kant. |
| `red_apply_reimport_clause_evidence` | `schema.sql:4654` | Delegerer til `private.write_clause_evidence`; samme låsekæde/begrundelse som helperne ovenfor/nedenfor. |
| `red_apply_reimport_clause_revision` | `schema.sql:4711` | Delegerer til `private.write_clause_revision`; samme låsekæde/begrundelse som helperne ovenfor/nedenfor. |
| `red_apply_reimport_interpretation_proposal` | `schema.sql:5414` | Delegerer til `private.write_interpretation_proposal`; samme låsekæde/begrundelse som helperne ovenfor/nedenfor. |
| `red_apply_reimport_legacy_migration` | `schema.sql:4435` | Delegerer til `private.migrate_legacy_narrative_record`; samme låsekæde/begrundelse som helperne ovenfor/nedenfor. |
| `red_apply_reimport_name_completion` | `schema.sql:5744` | Writer-gate (L4) før domæne-DML; serialiseres inden purge tager L5b–L11. Wrapper/caller genbruger gaten; ingen separat race. |
| `red_apply_reimport_person_create` | `schema.sql:4214` | Writer-gate (L4) før domæne-DML; serialiseres inden purge tager L5b–L11. Wrapper/caller genbruger gaten; ingen separat race. |
| `red_apply_reimport_publication_identity` | `schema.sql:18594` | Delegerer til `private.write_publication_identity`; samme låsekæde/begrundelse som helperne ovenfor/nedenfor. |
| `red_apply_reimport_publication_persona` | `schema.sql:18387` | Delegerer til `private.write_publication_persona`; samme låsekæde/begrundelse som helperne ovenfor/nedenfor. |
| `red_apply_reimport_relation_disposition` | `schema.sql:21012` | Delegerer til `private.write_relation_disposition`; samme låsekæde/begrundelse som helperne ovenfor/nedenfor. |
| `red_apply_reimport_relation_person_create` | `schema.sql:20850` | Delegerer til `private.write_relation_person_create`; samme låsekæde/begrundelse som helperne ovenfor/nedenfor. |
| `red_apply_reimport_relation_persona` | `schema.sql:18257` | Delegerer til `private.write_relation_persona`; samme låsekæde/begrundelse som helperne ovenfor/nedenfor. |
| `red_apply_reimport_source_evidence` | `schema.sql:4201` | Delegerer til `private.ensure_reimport_source_evidence`, `private.lock_reimport_writer`, `private.require_reimport_open_batch`; samme låsekæde/begrundelse som helperne ovenfor/nedenfor. |
| `red_apply_reimport_source_text_revision` | `schema.sql:5000` | Delegerer til `private.write_source_text_revision`; samme låsekæde/begrundelse som helperne ovenfor/nedenfor. |
| `red_authorize_1939_v50_cutover` | `schema.sql:6149` | Delegerer til `red_authorize_reimport_cutover`; samme låsekæde/begrundelse som helperne ovenfor/nedenfor. |
| `red_authorize_1939_v50_name_completion` | `schema.sql:6174` | Delegerer til `red_authorize_reimport_name_completion`; samme låsekæde/begrundelse som helperne ovenfor/nedenfor. |
| `red_authorize_1939_v50_reimport` | `schema.sql:6057` | Delegerer til `red_authorize_reimport`; samme låsekæde/begrundelse som helperne ovenfor/nedenfor. |
| `red_authorize_1939_v50_reversal` | `schema.sql:6133` | Delegerer til `red_authorize_reimport_reversal`; samme låsekæde/begrundelse som helperne ovenfor/nedenfor. |
| `red_authorize_reimport` | `schema.sql:4127` | Delegerer til `private.lock_reimport_writer`; samme låsekæde/begrundelse som helperne ovenfor/nedenfor. |
| `red_authorize_reimport_cutover` | `schema.sql:5989` | Delegerer til `private.lock_reimport_writer`; samme låsekæde/begrundelse som helperne ovenfor/nedenfor. |
| `red_authorize_reimport_name_completion` | `schema.sql:5679` | Delegerer til `private.lock_reimport_writer`, `private.validate_reimport_name_completion`; samme låsekæde/begrundelse som helperne ovenfor/nedenfor. |
| `red_authorize_reimport_reversal` | `schema.sql:5776` | Delegerer til `private.lock_reimport_writer`; samme låsekæde/begrundelse som helperne ovenfor/nedenfor. |
| `red_begin_1939_v50_name_completion` | `schema.sql:6194` | Delegerer til `red_begin_reimport_name_completion`; samme låsekæde/begrundelse som helperne ovenfor/nedenfor. |
| `red_begin_1939_v50_reimport` | `schema.sql:6085` | Delegerer til `red_begin_reimport`; samme låsekæde/begrundelse som helperne ovenfor/nedenfor. |
| `red_begin_reimport` | `schema.sql:4174` | Delegerer til `private.lock_reimport_writer`; samme låsekæde/begrundelse som helperne ovenfor/nedenfor. |
| `red_begin_reimport_name_completion` | `schema.sql:5726` | Delegerer til `private.lock_reimport_writer`; samme låsekæde/begrundelse som helperne ovenfor/nedenfor. |
| `red_bekraeft_media_upload` | `schema.sql:8610` | Lokale rækker (media); ingen senere writer-/kilde-/samme_som-gate i kroppen. RE via begin_change_set/log_change er kompatibel med L8; FK/eksistensvagt binder eventuelle nye mål. Ingen separat race. |
| `red_corroborate_family_identities` | `schema.sql:19984` | Kildens advisory-gate (L5) før domænelåsene; samme fraværsejer som b/d/R39. Ingen separat race. |
| `red_decide_relation_interpretations` | `schema.sql:20255` | Delegerer til `private.lock_family_rows`; samme låsekæde/begrundelse som helperne ovenfor/nedenfor. |
| `red_decide_source_persona_placement` | `schema.sql:2455` | Lokale rækker (source_persona); ingen senere writer-/kilde-/samme_som-gate i kroppen. RE via begin_change_set/log_change er kompatibel med L8; FK/eksistensvagt binder eventuelle nye mål. Ingen separat race. |
| `red_decide_source_record_placement` | `schema.sql:2432` | Lokale rækker (source_record); ingen senere writer-/kilde-/samme_som-gate i kroppen. RE via begin_change_set/log_change er kompatibel med L8; FK/eksistensvagt binder eventuelle nye mål. Ingen separat race. |
| `red_edit_oplysning` | `schema.sql:6705` | Delegerer til `begin_change_set`; samme låsekæde/begrundelse som helperne ovenfor/nedenfor. |
| `red_erstat_media_fil` | `schema.sql:8766` | Lokale rækker (media); ingen senere writer-/kilde-/samme_som-gate i kroppen. RE via begin_change_set/log_change er kompatibel med L8; FK/eksistensvagt binder eventuelle nye mål. Ingen separat race. |
| `red_finalize_1939_v50_name_completion` | `schema.sql:6210` | Delegerer til `red_finalize_reimport_name_completion`; samme låsekæde/begrundelse som helperne ovenfor/nedenfor. |
| `red_finalize_1939_v50_reimport` | `schema.sql:6124` | Delegerer til `red_finalize_reimport`; samme låsekæde/begrundelse som helperne ovenfor/nedenfor. |
| `red_finalize_reimport` | `schema.sql:5418` | Delegerer til `private.lock_reimport_writer`, `private.require_reimport_open_batch`; samme låsekæde/begrundelse som helperne ovenfor/nedenfor. |
| `red_finalize_reimport_name_completion` | `schema.sql:5763` | Delegerer til `private.lock_reimport_writer`, `private.require_reimport_open_batch`; samme låsekæde/begrundelse som helperne ovenfor/nedenfor. |
| `red_fjern_feed_pin` | `schema.sql:7002` | Delegerer til `begin_change_set`; samme låsekæde/begrundelse som helperne ovenfor/nedenfor. |
| `red_fjern_ikke_samme_som` | `schema.sql:7804` | Delegerer til `begin_change_set`, `private.guard_identity_mutation_snapshot`; samme låsekæde/begrundelse som helperne ovenfor/nedenfor. |
| `red_fjern_media` | `schema.sql:8720` | Lokale rækker (media); ingen senere writer-/kilde-/samme_som-gate i kroppen. RE via begin_change_set/log_change er kompatibel med L8; FK/eksistensvagt binder eventuelle nye mål. Ingen separat race. |
| `red_fjern_samme_som` | `schema.sql:7741` | Delegerer til `begin_change_set`, `private.guard_identity_mutation_snapshot`; samme låsekæde/begrundelse som helperne ovenfor/nedenfor. |
| `red_flyt_barn` | `schema.sql:8248` | Kalder red_slet_familie_link og red_tilfoej_barn: R42 ved indsættelsens family → person-FK i en familie med P; eventuel _ensure_foraeldrefamilie_redaktionel giver R37 conclusion → person-regen. Ingen senere writer-/kildegate. |
| `red_fortryd_change_set` | `schema.sql:9392` | e_fakta/e_medie/e_pin: sætrække → samme_som ved force → personer/pinmål → øvrige rækker. |
| `red_fortryd_person_narrative_publication_event` | `schema.sql:16860` | j_reverse via private.reverse_narrative_publication_event. |
| `red_genaabn_relation_interpretation` | `schema.sql:20329` | Kildens advisory-gate (L5) før domænelåsene; samme fraværsejer som b/d/R39. Ingen separat race. |
| `red_genopret_media` | `schema.sql:8684` | Lokale rækker (media); ingen senere writer-/kilde-/samme_som-gate i kroppen. RE via begin_change_set/log_change er kompatibel med L8; FK/eksistensvagt binder eventuelle nye mål. Ingen separat race. |
| `red_ikke_samme_som` | `schema.sql:7765` | samme_som-gate før personlåse; samme L7 → person-orden som purge. e med force/a prøver denne kant. |
| `red_kasser_person_narrative_record` | `schema.sql:16320` | c/j via private.mutate_person_narrative_record; operationen deler samme record-fraværsejer og AE → person-orden. |
| `red_lock_1939_v50_name_completion` | `schema.sql:6165` | Delegerer til `red_lock_reimport_name_completion`; samme låsekæde/begrundelse som helperne ovenfor/nedenfor. |
| `red_lock_reimport_name_completion` | `schema.sql:5669` | Delegerer til `private.lock_reimport_writer`; samme låsekæde/begrundelse som helperne ovenfor/nedenfor. |
| `red_opdater_media` | `schema.sql:8659` | Lokale rækker (media); ingen senere writer-/kilde-/samme_som-gate i kroppen. RE via begin_change_set/log_change er kompatibel med L8; FK/eksistensvagt binder eventuelle nye mål. Ingen separat race. |
| `red_opret_estate` | `schema.sql:8545` | Delegerer til `begin_change_set`; samme låsekæde/begrundelse som helperne ovenfor/nedenfor. |
| `red_opret_fakta` | `schema.sql:6648` | Delegerer til `begin_change_set`; samme låsekæde/begrundelse som helperne ovenfor/nedenfor. |
| `red_opret_kilde` | `schema.sql:8556` | Kun ny source; ingen senere lås på eksisterende P eller tidligere L-trin. |
| `red_opret_media` | `schema.sql:8582` | Kun nyt media; deling via red_relation dækkes af media_link. |
| `red_opret_organisation` | `schema.sql:8567` | Delegerer til `begin_change_set`; samme låsekæde/begrundelse som helperne ovenfor/nedenfor. |
| `red_opret_person` | `schema.sql:8520` | Kun ny person og dens egne nye fakta. Eksistensvagt/regen som f; ingen gammel P som input. |
| `red_opret_story` | `schema.sql:6878` | Delegerer til `begin_change_set`; samme låsekæde/begrundelse som helperne ovenfor/nedenfor. |
| `red_opret_union` | `schema.sql:7895` | Opretter en ny family før family_member-INSERTs. En anden purge kan ikke allerede eje denne ucommittede families tuple; person-FK kan vente på L10, men giver ingen modsat familieventning. W-commit kan udvide låsesættet og give PURGE_LOCKSET_DRIFT. R42 gælder kun, når der faktisk er den modsatte family → person-kant. |
| `red_person_narrative_publication_history` | `schema.sql:15850` | Delegerer til `private.narrative_record_state`; samme låsekæde/begrundelse som helperne ovenfor/nedenfor. |
| `red_person_narrative_records` | `schema.sql:15675` | Delegerer til `private.narrative_record_state`; samme låsekæde/begrundelse som helperne ovenfor/nedenfor. |
| `red_preflight_1939_v50_name_completion` | `schema.sql:6184` | Delegerer til `red_preflight_reimport_name_completion`; samme låsekæde/begrundelse som helperne ovenfor/nedenfor. |
| `red_preflight_reimport_authorization` | `schema.sql:4147` | Delegerer til `private.lock_reimport_writer`; samme låsekæde/begrundelse som helperne ovenfor/nedenfor. |
| `red_preflight_reimport_name_completion` | `schema.sql:5714` | Delegerer til `private.lock_reimport_writer`, `private.validate_reimport_name_completion`; samme låsekæde/begrundelse som helperne ovenfor/nedenfor. |
| `red_preview_interpretation_promotions` | `schema.sql:11860` | Delegerer til `private.preview_interpretation_promotions`; samme låsekæde/begrundelse som helperne ovenfor/nedenfor. |
| `red_preview_relation_promotions` | `schema.sql:20512` | Delegerer til `private.preview_relation_promotions`; samme låsekæde/begrundelse som helperne ovenfor/nedenfor. |
| `red_promote_interpretations_batch` | `schema.sql:11871` | Delegerer til `private.preview_interpretation_promotions`; samme låsekæde/begrundelse som helperne ovenfor/nedenfor. |
| `red_promote_placement_memberships` | `schema.sql:3124` | Delegerer til `begin_change_set`; samme låsekæde/begrundelse som helperne ovenfor/nedenfor. |
| `red_promote_relation_interpretations_batch` | `schema.sql:20521` | Kildens advisory-gate (L5) før domænelåsene; samme fraværsejer som b/d/R39. Ingen separat race. |
| `red_publicer_narrative_record` | `schema.sql:6239` | Lokale rækker (source_record); ingen senere writer-/kilde-/samme_som-gate i kroppen. RE via begin_change_set/log_change er kompatibel med L8; FK/eksistensvagt binder eventuelle nye mål. Ingen separat race. |
| `red_publicer_person_narrative_record` | `schema.sql:16284` | c/j via private.mutate_person_narrative_record; operationen deler samme record-fraværsejer og AE → person-orden. |
| `red_publicer_personer` | `schema.sql:7847` | Lokale rækker (family_member,person); ingen senere writer-/kilde-/samme_som-gate i kroppen. RE via begin_change_set/log_change er kompatibel med L8; FK/eksistensvagt binder eventuelle nye mål. Ingen separat race. |
| `red_publicer_udgave` | `schema.sql:7821` | Lokale rækker (family_member,person,person_external_id); ingen senere writer-/kilde-/samme_som-gate i kroppen. RE via begin_change_set/log_change er kompatibel med L8; FK/eksistensvagt binder eventuelle nye mål. Ingen separat race. |
| `red_record_identity_candidates` | `schema.sql:11472` | d: eksklusiv kildelås før kandidatjournal. |
| `red_rediger_story` | `schema.sql:6903` | Delegerer til `begin_change_set`; samme låsekæde/begrundelse som helperne ovenfor/nedenfor. |
| `red_register_identity_control_run` | `schema.sql:19674` | Kildens advisory-gate (L5) før domænelåsene; samme fraværsejer som b/d/R39. Ingen separat race. |
| `red_registrer_media_variant` | `schema.sql:8735` | media_variant: INSERT/ON CONFLICT; FK tager media KEY SHARE. Ingen efterfølgende person-/global lås. |
| `red_reimport_batch_result` | `schema.sql:5457` | Delegerer til `private.lock_reimport_writer`; samme låsekæde/begrundelse som helperne ovenfor/nedenfor. |
| `red_relation` | `schema.sql:7153` | media_link: begin_change_set → polymorf vagt → relation; mediet bevares ved deling. |
| `red_ret_aegteskabsnummer` | `schema.sql:19167` | Delegerer til `private.lock_family_rows`; samme låsekæde/begrundelse som helperne ovenfor/nedenfor. |
| `red_ret_ocr_felt` | `schema.sql:2029` | i_ocr: source/external → person → begin_change_set; anden person i samme kilde. |
| `red_ret_paastand` | `schema.sql:10113` | i_paastand: fortolkning/state → person → assertion/fact → begin_change_set. |
| `red_revalider_person_narrative_record` | `schema.sql:16308` | c/j via private.mutate_person_narrative_record; operationen deler samme record-fraværsejer og AE → person-orden. |
| `red_reverse_1939_v50_reimport` | `schema.sql:6141` | Delegerer til `red_reverse_reimport`; samme låsekæde/begrundelse som helperne ovenfor/nedenfor. |
| `red_reverse_placement_membership` | `schema.sql:3172` | i_membership_s/i_membership_w: medlemsrække → begin_change_set. R41 i W-først: nyt sæt om P efter plan → PURGE_REST: S52; ingen 40P01, gentagelse rydder op. |
| `red_reverse_reimport` | `schema.sql:5791` | Writer-gate (L4) før domæne-DML; serialiseres inden purge tager L5b–L11. Wrapper/caller genbruger gaten; ingen separat race. |
| `red_reverse_reimport_cases` | `schema.sql:13313` | samme_som-gate før personlåse; samme L7 → person-orden som purge. e med force/a prøver denne kant. |
| `red_reverse_reimport_publication` | `schema.sql:18708` | Writer-gate (L4) før domæne-DML; serialiseres inden purge tager L5b–L11. Wrapper/caller genbruger gaten; ingen separat race. |
| `red_revider_publiceret_person_narrative_record` | `schema.sql:16296` | c/j via private.mutate_person_narrative_record; operationen deler samme record-fraværsejer og AE → person-orden. |
| `red_saet_portraet` | `schema.sql:9004` | Lokale rækker (media,person); ingen senere writer-/kilde-/samme_som-gate i kroppen. RE via begin_change_set/log_change er kompatibel med L8; FK/eksistensvagt binder eventuelle nye mål. Ingen separat race. |
| `red_samme_som` | `schema.sql:7696` | samme_som-gate før personlåse; samme L7 → person-orden som purge. e med force/a prøver denne kant. |
| `red_set_familie_konfidens` | `schema.sql:7912` | Lokale rækker (family_member); ingen senere writer-/kilde-/samme_som-gate i kroppen. RE via begin_change_set/log_change er kompatibel med L8; FK/eksistensvagt binder eventuelle nye mål. Ingen separat race. |
| `red_set_familie_ordinal` | `schema.sql:8229` | Lokale rækker (family_member); ingen senere writer-/kilde-/samme_som-gate i kroppen. RE via begin_change_set/log_change er kompatibel med L8; FK/eksistensvagt binder eventuelle nye mål. Ingen separat race. |
| `red_set_feed_pin` | `schema.sql:6983` | pin: begin_change_set → mål før pin-upsert; e_pin dækker generisk inverse (R33). |
| `red_set_haendelse_status` | `schema.sql:6861` | Delegerer til `begin_change_set`; samme låsekæde/begrundelse som helperne ovenfor/nedenfor. |
| `red_set_koen` | `schema.sql:6843` | Lokale rækker (person); ingen senere writer-/kilde-/samme_som-gate i kroppen. RE via begin_change_set/log_change er kompatibel med L8; FK/eksistensvagt binder eventuelle nye mål. Ingen separat race. |
| `red_set_konklusion` | `schema.sql:6680` | Delegerer til `begin_change_set`, `red_vaelg_foraeldre`; samme låsekæde/begrundelse som helperne ovenfor/nedenfor. |
| `red_set_media_rettigheder` | `schema.sql:8698` | Lokale rækker (media); ingen senere writer-/kilde-/samme_som-gate i kroppen. RE via begin_change_set/log_change er kompatibel med L8; FK/eksistensvagt binder eventuelle nye mål. Ingen separat race. |
| `red_set_privat` | `schema.sql:6852` | Lokale rækker (person); ingen senere writer-/kilde-/samme_som-gate i kroppen. RE via begin_change_set/log_change er kompatibel med L8; FK/eksistensvagt binder eventuelle nye mål. Ingen separat race. |
| `red_set_story_kilder` | `schema.sql:6960` | Delegerer til `begin_change_set`; samme låsekæde/begrundelse som helperne ovenfor/nedenfor. |
| `red_set_story_status` | `schema.sql:6927` | Delegerer til `begin_change_set`; samme låsekæde/begrundelse som helperne ovenfor/nedenfor. |
| `red_slet_familie_link` | `schema.sql:7963` | Lokale rækker (family_member,person); ingen senere writer-/kilde-/samme_som-gate i kroppen. RE via begin_change_set/log_change er kompatibel med L8; FK/eksistensvagt binder eventuelle nye mål. Ingen separat race. |
| `red_slet_medierelation_uden_evidens` | `schema.sql:7297` | i_medie_s/i_medie_w og e_medie_s/e_medie_w: relation → begin_change_set. R41 i i_medie_w: sent sæt om P → PURGE_REST: S53; ingen 40P01, gentagelse rydder op. |
| `red_slet_oplysning` | `schema.sql:6753` | Delegerer til `begin_change_set`; samme låsekæde/begrundelse som helperne ovenfor/nedenfor. |
| `red_slet_person` | `schema.sql:7019` | samme_som-gate før personlåse; samme L7 → person-orden som purge. e med force/a prøver denne kant. |
| `red_slet_person_helt` | `schema.sql:23640` | a; alle scenarier: L1 → L4 → L5 → record → persona/state → L6b-sæt → samme_som → RE → source/external → person → familie → media. |
| `red_slet_person_helt_preview` | `schema.sql:23428` | Preview-læsning; L13 genkontrollerer SHA i alle races. |
| `red_slet_relation` | `schema.sql:7208` | Delegerer til `begin_change_set`, `private.guard_identity_mutation_snapshot`; samme låsekæde/begrundelse som helperne ovenfor/nedenfor. |
| `red_slet_story` | `schema.sql:6948` | Delegerer til `begin_change_set`; samme låsekæde/begrundelse som helperne ovenfor/nedenfor. |
| `red_tilbagetraek_fakta` | `schema.sql:6798` | Delegerer til `begin_change_set`; samme låsekæde/begrundelse som helperne ovenfor/nedenfor. |
| `red_tilbagetraek_legacy_narrative` | `schema.sql:16845` | Delegerer til `private.withdraw_legacy_narrative`; samme låsekæde/begrundelse som helperne ovenfor/nedenfor. |
| `red_tilbagetraek_person_narrative_record` | `schema.sql:16332` | c/j via private.mutate_person_narrative_record; operationen deler samme record-fraværsejer og AE → person-orden. |
| `red_tilfoej_barn` | `schema.sql:8039` | R42; k_plejebarn_s/k_plejebarn_w: family-FK KEY SHARE → person-FK KEY SHARE mod purge L10(person) → L11(family). Rollen barn går desuden via _ensure_foraeldrefamilie_redaktionel (R37-conclusion → person-regen). |
| `red_tilfoej_foraeldre_paastand` | `schema.sql:8284` | g_parent: fact → family i assertion-trigger; familien kontrolleres også efter ventning. |
| `red_tilfoej_oplysning` | `schema.sql:6618` | g_assert: assertion-trigger låser eksisterende fact KEY SHARE før citat. |
| `red_tilfoej_partner` | `schema.sql:8185` | R42: INSERT → _tjek_partner_loft → family FOR UPDATE → person-FK KEY SHARE, modsat L10 → L11. k_plejebarn_s/k_plejebarn_w prøver samme familie → person-klasse via RI, ikke partnergrenen direkte. |
| `red_tilfoej_relation` | `schema.sql:7870` | Lokale rækker (person); ingen senere writer-/kilde-/samme_som-gate i kroppen. RE via begin_change_set/log_change er kompatibel med L8; FK/eksistensvagt binder eventuelle nye mål. Ingen separat race. |
| `red_udrens_media` | `schema.sql:8935` | Lokale rækker (media); ingen senere writer-/kilde-/samme_som-gate i kroppen. RE via begin_change_set/log_change er kompatibel med L8; FK/eksistensvagt binder eventuelle nye mål. Ingen separat race. |
| `red_upload_media` | `schema.sql:8627` | Delegerer til `begin_change_set`, `red_opret_media`, `red_relation`; samme låsekæde/begrundelse som helperne ovenfor/nedenfor. |
| `red_upsert_fakta` | `schema.sql:6574` | f_fact og r37_name: nyt subjekt via KEY SHARE; eksisterende conclusion → regen(person), accepteret R37-cyklus. |
| `red_upsert_narrativ` | `schema.sql:7124` | Delegerer til `begin_change_set`; samme låsekæde/begrundelse som helperne ovenfor/nedenfor. |
| `red_upsert_person_narrative_record` | `schema.sql:16272` | c/j via private.mutate_person_narrative_record; operationen deler samme record-fraværsejer og AE → person-orden. |
| `red_vaelg_foraeldre` | `schema.sql:8364` | Via red_flyt_barn/red_tilfoej_barn: R42 family → person-FK; via _ensure_foraeldrefamilie_redaktionel: R37 conclusion → person-regen. R42-scenarierne er k_plejebarn_s/k_plejebarn_w; ikke et direkte kald af denne wrapper. |
| `regen_person_visning` | `schema.sql:6425` | r37_name: person-UPDATE under assertion/conclusion-trigger; R37 accepterer denne cyklus som lukket fejl. |
| `trg_regen_from_assertion` | `schema.sql:6499` | Delegerer til `regen_person_visning`; samme låsekæde/begrundelse som helperne ovenfor/nedenfor. |
| `trg_regen_from_conclusion` | `schema.sql:6481` | Delegerer til `regen_person_visning`; samme låsekæde/begrundelse som helperne ovenfor/nedenfor. |
| `trg_regen_from_external_id` | `schema.sql:6518` | Delegerer til `regen_person_visning`; samme låsekæde/begrundelse som helperne ovenfor/nedenfor. |
| `trg_regen_from_lineage` | `schema.sql:6536` | Delegerer til `regen_person_visning`; samme låsekæde/begrundelse som helperne ovenfor/nedenfor. |
| `validate_entity_description_subject` | `schema.sql:11988` | Lokale rækker (media,person); ingen senere writer-/kilde-/samme_som-gate i kroppen. RE via begin_change_set/log_change er kompatibel med L8; FK/eksistensvagt binder eventuelle nye mål. Ingen separat race. |

Triggerkæder: fact/relation/note/narrative/story/suggestion/haendelse → validate_polymorf_subjekt_findes; assertion/conclusion → enforce_relation_evidence_target; assertion-objekt → validate_polymorf_subjekt_findes før fact-målet; fact DELETE → guard_fact_evidence_delete; entity_description → validate_entity_description_subject; family_member → _tjek_partner_loft/FK; source_persona_identity_event → validate_source_persona_identity_event; source_record_revision_event → validate_source_record_revision_event; versionerede rækker → log_change; assertion/conclusion/external-id/lineage → trg_regen_* → regen_person_visning. Append-only-tabeller kontrollerer person_purge_tilladt i eksisterende reject-triggere. Ingen af de gennemgåede triggerkroppe åbner en ny writer-/kildelås efter datalåsen; conclusion/person-regen er R37, family/person-FK er R42, og et sent D-1-change_set er R41 som beskrevet ovenfor.

### Nye kandidater: endelig disposition

Den tidligere tekst sagde 45, men tabellen og inventardifferencen indeholder **46** særskilte nye funktioner (190 gamle − 1 ACL-streng + 46 = 235 kandidater). Alle 46 bevares og får en konkret begrundelse nedenfor; ingen markeres som direkte runtime-afprøvet alene ud fra et repræsentativt scenarie. Dispositionerne bor i rapporten, så inventarets seks maskinelt udledte TSV-kolonner og generatoren behøver ingen ændring.

Fordeling af de 46 begrundelser: 5 med afgrænset DML, 3 afvisningsvagter, 3 legacygates, 15 med konkret låserækkefølge og 20 læsekontroller. R37/R41/R42-henvisningerne ovenfor præciserer de berørte eksisterende funktioners kanter; ingen ny uafgjort cyklus.

| Funktion | Sted | Type | Konkret begrundelse / repræsentativ kant |
|---|---|---|---|
| `_delete_relation_evidence` | `schema.sql:7190` | Afgrænset DML | Låser relation via prelock_identity_relation_delete før evidenssletning. Conclusion-target er relation, så trg_regen_from_conclusion tager ikke personlåsen. Story SET NULL ændrer relation_id, ikke subjektkolonnerne: UPDATE OF-subjekttriggeren fyrer ikke. log_change tager kun kompatibel RE; ingen tilbagekant til L1–L11. |
| `guard_relation_evidence_delete` | `schema.sql:7271` | Læsekontrol | Kun EXISTS på assertion/conclusion/note og eventuel afvisning; hverken FOR-lås, DML eller senere gate. Den udløsende relation-lås får ingen ny ventekant her. |
| `private.assert_identity_state_event_consistency` | `schema.sql:1898` | Læsekontrol | Deferred kontrol læser event/state-version og indhold uden FOR-lås; åbner ingen gate efter persona/state-DML. Purge ejer allerede L6 ved sin egen strømsletning. |
| `private.assert_interpretation_has_observation` | `schema.sql:1803` | Læsekontrol | Deferred EXISTS på interpretation_observation; ingen DML eller tuple-/advisory-lås. Purge sletter hverken fortolkningen eller dens observationslinks. |
| `private.check_clause_set_density` | `schema.sql:17620` | Læsekontrol | Deferred aggregat over source_observation kontrollerer ordinaler; ingen FOR-lås/DML. Purge ændrer ikke klausulsættet. |
| `private.clause_write_set` | `schema.sql:4572` | Låserækkefølge | write_clause_evidence/revision/source_text_revision går via clause_write_prepare og L4 før denne helper. Triggere låser parent/tekst/klausul, FK binder occurrence/run; purge ændrer ingen af disse evidensrækker. Ingen senere gate i helperen. |
| `private.cleanup_identity_relation_update_prelock` | `schema.sql:7410` | Afgrænset DML | Deferred DELETE rammer kun NEW.transaction_id/backend_pid/relation_id i den transiente prelock-tabel. En anden transaktion har en anden nøgle; purge sletter ikke denne tabel. Ingen person-/familie-/writerlås her. |
| `private.kontroller_forslag_binding_v1` | `schema.sql:10057` | Læsekontrol | Deferred kontrol følger assertion_binding_current med almindelige læseopslag i promotion/rule/fact/assertion/interpretation/persona-state. Ingen FOR-lås eller DML i læsekæden, altså ingen ny ventekant efter interpretation-INSERT. |
| `private.propose_source_persona_placement` | `schema.sql:2419` | Låserækkefølge | Ny placement → persona KEY SHARE og record-placement KEY SHARE; beslutningsstatus proposed tager ikke source_record FOR UPDATE i validate_placement_decision. Ingen efterfølgende kilde-/personlås; purge bevarer placements og kan ikke vente tilbage på disse nye rækker. |
| `private.propose_source_record_placement` | `schema.sql:2406` | Låserækkefølge | Ny placement → source_record KEY SHARE; proposed-beslutning tager ingen ekstra record FOR UPDATE. S ejer record ved L5b eller venter på W der; W går ikke videre til en senere purge-gate. Purge bevarer placements. |
| `private.reject_narrative_publication_event_mutation` | `schema.sql:14022` | Afvisningsvagt | Afviser mutation (NARRATIVE_PUBLICATION_EVENT_APPEND_ONLY); eneste tilladte DELETE læser person_purge_tilladt/manifest og ejer samme xid/backend. Autorisationskæden tager ingen tuple-/advisory-lås eller ny writer-gate. |
| `private.reject_reimport_case_event_mutation` | `schema.sql:9186` | Afvisningsvagt | Afviser mutation (REIMPORT_CASE_EVENT_APPEND_ONLY); eneste tilladte DELETE læser person_purge_tilladt/manifest og ejer samme xid/backend. Autorisationskæden tager ingen tuple-/advisory-lås eller ny writer-gate. |
| `private.reject_reimport_writer_mutation` | `schema.sql:3945` | Afvisningsvagt | Afviser mutation (REIMPORT_WRITER_*_APPEND_ONLY); eneste tilladte DELETE læser person_purge_tilladt/manifest og ejer samme xid/backend. Autorisationskæden tager ingen tuple-/advisory-lås eller ny writer-gate. |
| `private.require_placement_initial_decision` | `schema.sql:2391` | Læsekontrol | Deferred EXISTS på v1 i den relevante placement-decision-tabel; ingen FOR-lås/DML. Purge ændrer ikke de to placementstrømme. |
| `private.require_publication_identity_finalized` | `schema.sql:18686` | Læsekontrol | Deferred EXISTS på reimport_batch.status; ingen FOR-lås eller ny batch-/writer-gate efter identity-DML. |
| `private.supersede_for_text_revision` | `schema.sql:21363` | Låserækkefølge | Caller write_source_text_revision har allerede taget L4 via clause_write_prepare, før dependent-låse og denne INSERT af nye fortolkningsversioner. FK kan vente på source/persona, men purge venter ikke på fortolkninger/observationslinks, som bevares. Helperen åbner ingen senere gate. |
| `private.validate_clause_disposition` | `schema.sql:765` | Låserækkefølge | FOR UPDATE på source_observation(klausul), derefter almindelig vocab/versionslæsning. Purge hverken låser eller ændrer klausul/disposition; ingen videre person-/record-/writerkant i kroppen. |
| `private.validate_clause_disposition_set` | `schema.sql:17677` | Låserækkefølge | FOR UPDATE på klausulen, derefter læsekontrol af aktuelt sæt og erstattet-status. Purge ændrer ikke observationer/dispositioner; ingen efterfølgende gate. |
| `private.validate_clause_observation` | `schema.sql:663` | Låserækkefølge | FOR SHARE på parent-observation og eventuel parent-tekst; derefter kun indholdskontrol. Ingen record-/persona-/personlås; purge bevarer parent og tekst, så ingen modsat kant. |
| `private.validate_clause_set_seq` | `schema.sql:17579` | Låserækkefølge | FOR UPDATE på parent-observation serialiserer sætnummer, derefter kun læsning. Purge ændrer ikke parent/klausulsæt; ingen senere gate. |
| `private.validate_evidence_scope` | `schema.sql:931` | Læsekontrol | Kun scope-/span-/versionsopslag i rendition/run/occurrence/observation/persona. Ingen FOR-lås, DML eller advisory-gate; FK-kanterne tilføjes separat i TSV. |
| `private.validate_interpretation_observation` | `schema.sql:1786` | Læsekontrol | Kun SELECT af fortolkningens og observationens source_id; ingen FOR-lås eller DML efter observationslinkets INSERT. |
| `private.validate_interpretation_observation_current_clause` | `schema.sql:17705` | Læsekontrol | Kun SELECT/aggregat af observation og maksimalt klausulsæt; ingen FOR-lås, DML eller gate. Purge bevarer begge evidenslag. |
| `private.validate_interpretation_party` | `schema.sql:1347` | Læsekontrol | Kun SELECT af gældende fortolkning, partversion, persona og mention/occurrence-scope; ingen FOR-lås eller DML. Partens FK er ikke en lås på dens kanoniske person. |
| `private.validate_interpretation_promotion` | `schema.sql:1813` | Læsekontrol | Kun ejer-/accepted-/måleksistenskontrol med SELECT/EXISTS; intet FOR KEY SHARE på det polymorfe mål og ingen gate. Dette begrunder fravær af ny låsecyklus, ikke en stærkere målbeskyttelse end koden giver. |
| `private.validate_interpretation_scope` | `schema.sql:1755` | Læsekontrol | Kun ejer, persona-source og supersedes/version kontrolleres med SELECT/EXISTS. Ingen FOR-lås eller gate efter interpretation-INSERT; FK er særskilt registreret. |
| `private.validate_narrative_legacy_publication` | `schema.sql:14041` | Læsekontrol | Kun narrative-source, uforanderlig baseline og latest-event kontrolleres; ingen FOR-lås/DML. Purge nulstiller latest_event_id uden at triggeren tager en sen record-/personlås. |
| `private.validate_narrative_publication_event` | `schema.sql:13955` | Læsekontrol | Kun binding/legacy/narrative/record-identitet og streamversion kontrolleres med SELECT. Ingen FOR-lås eller ny gate efter event-INSERT; c_publish/j_reverse prøver callers record-først-orden. |
| `private.validate_narrative_record_publication` | `schema.sql:3686` | Læsekontrol | Kun narrative/record-source og uforanderlig binding læses; published_at ændres alene i NEW. Ingen tuple-/advisory-lås i kroppen; callers FK og record-låse behandles særskilt. |
| `private.validate_source_persona_identity_state` | `schema.sql:1884` | Læsekontrol | Kun current_user mod tabel-ejer, derefter RETURN NEW/afvisning. Ingen event-/persona-/personlås; FK fra state er separat, og b_identity prøver callerens kildegate. |
| `private.validate_source_persona_placement` | `schema.sql:2317` | Læsekontrol | Kun fælles kilde og accepteret record/mention-basis læses. Ingen FOR-lås eller DML; persona/record-placement-FK ligger på den udløsende INSERT. |
| `private.validate_source_record_anchor_event` | `schema.sql:981` | Låserækkefølge | Occurrence FOR UPDATE → record-afledt advisory (seed 154155), derefter almindelig scope/versionslæsning; INSERTs record-FK kan vente ved L5b. Purge tager ikke occurrence-rækken eller denne advisory og ændrer ikke anchor-strømmen: ingen kant tilbage til W. |
| `private.validate_source_record_placement` | `schema.sql:2275` | Læsekontrol | Kun header-/anchor-/record-/scheme-scope med SELECT/EXISTS; ingen FOR-lås eller gate. Source_record-FK følger INSERT, ikke denne læsekrop. |
| `private.write_header_evidence` | `schema.sql:2667` | Afgrænset DML | Kun extraction_run/occurrence/observation-INSERT; source-FK KEY SHARE kan vente på L9. Headerkind returnerer fra klausullåsegrenene. Purge bevarer disse indholdsadresserede evidensrækker, og helperen tager ingen senere gate/personlås. |
| `private.write_persona_placement` | `schema.sql:2770` | Låserækkefølge | Ny accepted persona-placement tager persona/record-placement KEY SHARE; accepted-triggeren læser blot record-placement-current (ingen record FOR UPDATE i persona-grenen). Purge bevarer placements og har derfor ingen modsat ventning på W's nye rækker. |
| `private.write_record_placement` | `schema.sql:2729` | Låserækkefølge | INSERT tager record-FK KEY SHARE; accepted-beslutningens BEFORE validate_placement_decision opgraderer samme record til FOR UPDATE. S ejer L5b først eller venter dér; purge bevarer placement/decision og giver ingen ventekant tilbage til W. Deferred initial-decision-kontrol er kun læsning. |
| `red_authorize_reimport_case_reversal` | `schema.sql:13227` | Legacygate | Delt kontraktlås L1 først; kontraktversion >=2 afviser før DML. I legacy-grenen kun læseplan/validering og authorization-INSERT med source-FK KEY SHARE; purge sletter ikke authorization/batch, og ingen senere person-/writergate tages. |
| `red_authorize_reimport_cases` | `schema.sql:12539` | Legacygate | Delt kontraktlås L1 først; kontraktversion >=2 afviser før DML. I legacy-grenen kun læseplan/validering og authorization-INSERT med source-FK KEY SHARE; purge sletter ikke authorization/batch, og ingen senere person-/writergate tages. |
| `red_decide_interpretation` | `schema.sql:9738` | Låserækkefølge | Låser eksisterende interpretation FOR UPDATE før afgørelsen indsætter ny version og observationslinks. FK til source/persona kan vente på L9/L6; purge hverken låser, sletter eller refererer med FK til denne interpretation fra sine nye identity-events. Ingen modsat ventekant; deferred kontroller er læsning. |
| `red_normaliser_forslag` | `schema.sql:9851` | Låserækkefølge | Låser eksisterende interpretation FOR UPDATE før normaliseringen indsætter ny version og observationslinks. FK til source/persona kan vente på L9/L6; purge hverken låser, sletter eller refererer med FK til denne interpretation fra sine nye identity-events. Ingen modsat ventekant; deferred kontroller er læsning. |
| `red_promote_interpretation` | `schema.sql:10356` | Afgrænset DML | Kun ny interpretation_promotion med FK til interpretation/batch/rule, som purge ikke sletter. Måleksistens-triggeren er læsning; ingen kanonisk person-/familielås eller senere gate. En ny promotion kan ændre plan/slutkontrol, men giver ikke en ny låsecyklus her. |
| `red_ret_forslag` | `schema.sql:9940` | Låserækkefølge | Låser eksisterende interpretation FOR UPDATE før rettelsen indsætter ny version og observationslinks. FK til source/persona kan vente på L9/L6; purge hverken låser, sletter eller refererer med FK til denne interpretation fra sine nye identity-events. Ingen modsat ventekant; deferred kontroller er læsning. |
| `red_suggest` | `schema.sql:8417` | Låserækkefølge | INSERT → BEFORE validate_polymorf_subjekt_findes tager person/family KEY SHARE før suggestion-rækken, dernæst source/auth-FK. Purge tager person/family før suggestion-DELETE og tager ingen senere source-lås. f_fact_s/f_fact_w prøver samme personvagt; g_parent_s/g_parent_w samme familievagt, ikke selve red_suggest. |
| `red_tilbagetraek_narrative_record` | `schema.sql:6274` | Legacygate | L1-kontraktversion >=2 afviser før UPDATE. Legacy-grenen ændrer kun status på eksisterende publication; narrative/record-FK-værdier er uændrede, validering er læsning, og der tages ingen senere record-/person-/writerlås. |
| `trg_lineage_prevent_cycle` | `schema.sql:3436` | Læsekontrol | Kun lineage_ancestors, en rekursiv SELECT uden FOR-lås, og eventuel afvisning. Separat trg_regen_from_lineage kan tage person-UPDATE; den kant er behandlet under regen-helperen i den eksisterende liste, ikke i denne cyklusvagt. |
| `trg_regen_mentions` | `schema.sql:9663` | Afgrænset DML | Kun DELETE/INSERT i text_mention via _regen_mentions_for; parse_mentions læser tekst, og maal_id har ingen person/family-FK eller eksistenslås. Purge ændrer samme teksts mentions via dens trigger; ingen sen person-/writergate. Dette genåbner ikke den accepterede R38-tekstlinkafgrænsning. |

Verificeret i denne runde uden database: funktionskroppe og triggernes UPDATE OF-/rollegrene mod levende schema, 235 unikke kandidater med én disposition hver, deterministisk inventar/TSV-paritet og kun ændringer inden for dette afsnit. Runtime-udfaldene for R41/R42 ovenfor er projektejerens bevis, ikke en ny kørsel her.

## Verifikation og næste handling

Kørt: bash -n på de tre shell-harnesser, Python AST-parse, inventargenerering og git diff --check. Ikke kørt: SQL, migrationer eller CI. Ingen ny ejerafgørelse og ingen påvist produktionsfejl; Task 11 må først markeres runtime-grøn efter hovedsessionens kørsel.

Fra arbejdsmappen, med ubrugte præfikser:

```sh
bash tests/sql/test-person-purge-concurrent.sh t11_concurrent_01
bash tests/sql/test-person-purge-upgrade.sh t11_upgrade_01 f9f2cd9c
bash tests/sql/test-person-purge.sh t11_full_01
```

Alle nye tests/sql-filer samt denne rapport skal git add'es af hovedsessionen. Ingen commit er lavet af implementeren.

## Hovedsessionens kørsel (17/11)

Implementeringen ovenfor blev kørt og rettet i hovedsessionen. Der er ingen ændringer af produktionskode, kun af testopsætning og -afgrænsning.

**Opgradering.** Den første udgave af omfanget var »alle funktioner, der afviger mellem den opgraderede gamle base og frisk HEAD«. Den gav 56 falske fund: gammel drift (fx whitespace) mellem en migrationskrop og `schema.sql`, som fandtes før denne gren (fx `private.ocr_importeret`). Rettet: en frisk base fra base-commit (bootstrap + schema + rls, uden migrationer) afgrænser »nye og ændrede« som forskellen mod frisk HEAD. Det giver 32 funktioner, bl.a. `red_slet_person_helt(_preview)`, `red_fortryd_change_set`, `red_suggest`, `red_slet_person`, `validate_polymorf_subjekt_findes` og `person_purge_*`. Ny kontrol: uden for omfanget må migrationen intet ændre (`upgrade1 == base`). Resultat: `UPGRADE_SCOPE 32`, `UPGRADE_OK`.

**Samtidighed: rettelser af testopsætning.**
- `g_parent_w`: en committet forældrepåstand fra en anden på `fam_del` er NY-A, som er blokér i slettegrafen. Nyt forsøg giver derfor `PURGE_BLOKERET: anden_paastand`; P findes, manifestet er tomt, og tabelhashen er uændret. Før blev `retry_gone` (urigtigt) krævet.
- `c_publish`: fixturens record er `stale_published` (bevidst tekstdrift), så kun tilbagetrækning er tilladt. Skriveren er derfor `red_tilbagetraek_person_narrative_record`, som går ad samme `mutate_person_narrative_record`-vej.
- `j_reverse`: en published-hændelse kan ikke fortrydes efter tekstdrift, og fortrydelse af en tilbagetrækning kræver publiceringsret. Opsætning i kopien: P offentlig + tilbagetrækning; skriveren fortryder tilbagetrækningen.
- `i_ocr`: den tredje person har allerede sin egen record (`PURGE-T`) i samme kilde. INSERT kolliderede med PK.
- `i_paastand`: kræver en fortolkning med kildecitation; kun den bundne tilnavn-påstand har det. Opsætning: version n+1 af den bundne fortolkning med rettet værdi plus kopi af observationslinket. En ny nøgle gav `PAASTAND_BINDING_BRYDES`; uden observation fyrer `EVIDENCE_INTERPRETATION_OBSERVATION_REQUIRED` ved commit.
- Ny port `preflight`: skriveren inkl. opsætning skal lykkes alene i `BEGIN … SET CONSTRAINTS ALL IMMEDIATE … ROLLBACK`, før kapløbet. Ellers kunne en ren valideringsfejl i et forkert kald passere som »lukket« i S-først-grenen. `c_publish_s` var grøn med det forkerte revisionskald.
- `ONLY=<regex>` til lokal fejlfinding. EXIT-trappen skriver via fd 3, fordi den arver den fejlende kommandos `>/dev/null`. Tomme arrays er sikret under `set -u` på macOS' bash 3.2.

**Ruling R41 (projektejeren 17/11: accepteret som »prøv igen«).** D-1-skriverne låser rækken før deres change_set, og L8 er `ROW EXCLUSIVE`. Når skriveren kommer først, opretter den sit change_set om P efter sletningens plan, og slutkontrollen afviser lukket uden 40P01. Nyt forsøg lykkes. Observeret og tilladt kun for `i_membership_w` (`PURGE_REST: S52`) og `i_medie_w` (`PURGE_REST: S53`). Testen kræver da præcis ét nyt change_set siden før W, præcis ét nyt sæt i `person_purge_historik(P)` og et tomt manifest.

**Ruling R42 (projektejeren 17/11: accepteret; rettelse i backloggen).** Step 1b's FK-inversion, afprøvet i praksis. `red_tilfoej_barn(F,P,'plejebarn')`, hvor P i forvejen er barn i F, får `family(F) KEY SHARE` i RI-kontrollen før `person(P)`; sletningen tager P ved L10 før F ved L11. `k_plejebarn_s` (sletningen pauset efter L10) giver præcis én 40P01. Begge sider er set tabe: én kørsel tabte sletningen, én tabte skriveren. Den anden side committer, og der er ingen rest. `k_plejebarn_w` giver lukket `PURGE_LOCKSET_DRIFT`. Samme klasse som partnertilfældet i kommentaren ved `private.lock_family_rows`. En `BEFORE INSERT`-trigger på `family_member`, der tager `person KEY SHARE` først, blev afprøvet i en testbase: sletningen lykkes, og skriveren får FK-fejl 23503. Den står som backlog i `docs/decisions.md` (2026-11-17). Ingen af de syv personer på slettelisten har en barnerolle (målt på stand-in, kun tal).

**Codex-review (read-only) og rettelser.**
- `f_fact` brugte `erhverv`, som P allerede har, så `FACT_NEW` ramtes aldrig. Nu bruges `dåb`.
- `observe()` godkendte enhver lås på relationen. Nu kræves en ikke-tildelt lås eller en tuple-lås, altså at S faktisk venter.
- `r39_w` kunne være grøn på drift (første afvisning er `PURGE_LOCKSET_DRIFT`). Nu kræves et nyt forsøg med frisk preview, der giver præcis `PURGE_BLOKERET: anden_promotion`, med uændret hash og binding.
- R41 er afgrænset og bundet som ovenfor.
- Logmappen er `$PURGE_LOG_DIR`, ellers `$RUNNER_TEMP`, ellers `$TMPDIR`; aldrig `/tmp`.
- Step 1b følger nu DML → trigger og FK (46 nye funktioner disponeret).
- Rapportlinjen har som 5. felt S' fejlkode og sted.

**Mutation.** KEY SHARE fjernet alene i `validate_polymorf_subjekt_findes` fanges nu af `f_fact_w` og `f_fact_s`; begge fejler i `observe S W transactionid person`. KEY SHARE fjernet i både den og `enforce_relation_evidence_target` fanges desuden af `g_assert_w`, `g_note_w` og `media_link_w`.

**Resultater (endelig, 17/11).** `SAMTIDIG_OK` med 43 scenarier på 71 s lokalt. `UPGRADE_OK` med 32 funktioner i omfanget og intet ændret uden for det. Harness 168 OK + `FRISK_OK`. Writer-jobbet i den lokale CI-kører: personsletningstrinene tager 24 s (fixtur), 79 s (samtidighed) og 6 s (opgradering). Eneste røde trin er de kendte miljøtrin (R-install og C3-dblink `role "postgres" is not permitted to log in`). De tre øvrige PostgreSQL-jobs er grønne på samme vilkår. core 580, pytest 4256 og R FAIL 0.
