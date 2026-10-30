# 6a: læsere af helposttekst og partsbaserede input (Task 7)

Inventar til spec §4.4 (»Én læser af gældende helposttekst« og »Partsbaserede input mister autoritet«, Codex F3).
Kun funktionsnavne, filer og linjenumre (schema.sql efter Task 7); ingen posttekst.

**Konsekvensen i hverdagssprog:** efter en kildetekst-revision læser databasen nu den rettede tekst, de steder hvor
det betyder noget: når en post omsegmenteres, når ægteskabsarket viser »hele posten«, og når persona-detaljen
markerer den gældende tekstversion. En forældet relation kan ikke længere føre til, at en ægtefælle oprettes eller
foreslås afgjort. Poster uden tekstversion og relationer, der ikke er forældet, opfører sig som før.

## Metode

- `git grep -n "verbatim_text" -- schema.sql ':!work*'`: 57 forekomster før Task 7.
- `git grep -ln "verbatim_text" -- '.claude/skills' ':!work*'`: 66 filer; testfiler, referencer og prompts er udeladt
  nedenfor.
- `git grep -n "interpretation_party_current" -- schema.sql ':!work*'`: 38 forekomster i 19 funktioner og views.
- `db-migrations.sql` gentager schema.sql-funktionerne i ældre blokke. Den sidste blok
  (`trin 6a: helpost-tekst gennem én funktion …`) definerer de flyttede funktioner, og funktionskroppene er
  identiske med schema.sql (målt med `pg_get_functiondef` på en frisk base og en base med migrationerne kørt to gange).

Klasser: **helpost (observation)**, **helpost (forekomst)**, **klausul**, **mention** og **andet**. Klausul- og
mentionlæsere følger revisionen af sig selv: revisionen skriver et nyt klausulsæt, og klausulteksten er skåret af den
version, sættet er bundet til (`parent_text_id`). De står med for fuldstændighedens skyld.

## A. Databasen (schema.sql)

### Flyttet til `private.helpost_text_current`

| Funktion | Linjer | Klasse | Ændring |
|---|---|---|---|
| `private.clause_write_prepare` | 4287-4294, 4316 | helpost (observation) | `parent_verbatim_sha256` for `clause_evidence` og `clause_revision` kontrolleres mod den gældende tekst. `text_id` lægges i konteksten. |
| `private.write_clause_evidence` | 4396 | helpost (observation) | Sender `text_id` til `clause_write_set`. I praksis altid NULL, fordi en revision kræver et eksisterende sæt. |
| `private.write_clause_revision` | 4441 | helpost (observation) | Sender `text_id` til `clause_write_set`, så omsegmenteringen skæres af og bindes til tekstversionen. |
| `private.relation_persona_v3_input` | 18672-18676 (`rows`), 18685 (`redecide_rows`) | helpost (observation) | `post_text` er den gældende tekst (vist som »Hele posten« i ægteskabsarket v3). |
| `public.red_source_persona_detail` | 9595-9599 | helpost (observation) | Nyt felt `current` pr. tekstversion: den version, `helpost_text_current` vælger. `preferred` er uændret, og webklienten ignorerer det nye felt. |

**Afgørelse om `clause_revision` efter en revision: flyt, ikke afvis.** Specen bevarer `clause_revision` til ren
omsegmentering, og `TEXT_REVISION_NOOP` spærrer en revision med uændret tekst. En afvisning ville derfor gøre en
revideret post umulig at omsegmentere. Før Task 7 gik en omsegmentering med basistekstens hash igennem og skar et
nyt aktuelt sæt af basisteksten. Det nye sæt var uenigt med den gældende tekst, og ingen fik det at vide (testen
`test_clause_revision_follows_text_revision` var rød på netop det). Nu giver basistekstens hash
`CLAUSE_EVIDENCE_PARENT_TEXT_DRIFT`, og den gældende teksts hash giver et sæt med `parent_text_id` = tekstversionen.
Følge for Task 13: manifest-builderen skal hashe den gældende tekst for en revideret post.

### Allerede korrekte eller bevidst bundet

| Funktion | Linjer | Klasse | Begrundelse |
|---|---|---|---|
| `private.validate_clause_observation` | 699-711 | helpost (observation) | Bundet pr. række: `parent_text_id` angiver versionen, og NULL betyder basisteksten, som klausulen faktisk er skåret af. Den gældende tekst ville gøre gamle sæt ugyldige. |
| `private.clause_write_set` | 4324-4388 | helpost (observation) | Uændret kontrakt fra R2 (NULL = basisteksten). Kalderne vælger versionen. |
| `private.write_source_text_revision` | 4494-4719 | helpost (observation) | Bruger allerede `helpost_text_current` (Task 5). Linje 4710 udelader teksten fra hændelsen. |
| `private.write_interpretation_proposal` | 4954 | helpost (observation) | Bruger allerede `helpost_text_current` til nøglens tekstversion (Task 6). Helpost-valget venter på 6c. |
| `private.write_interpretation_proposal` | 5070, 5075, 5087 | klausul | Citathashes fra `clause_observation_current`. |
| `private.migrate_legacy_narrative_record` | 4057 | helpost (forekomst) | Bundet til forekomstens tekst. Revisionen versionerer observationen, ikke forekomsten (§4.4: »Forekomsten … står urørt«), og 149b-manifesterne har forekomstens hash. |
| `private.reimport_case_source_record_state` | 10512 | helpost (forekomst) | Samme begrundelse: forekomstens tekst er det fysiske spænd, og sagsmanifesternes hash bygger på den. |
| `private.validate_evidence_scope` (source_mention) | 960-967 | mention | Kontrolleres kun ved INSERT mod observationens basistekst. Mentions skrives ikke om ved revisionen (§4.4 pkt. 5). Latent: en ny helpost-mention efter en revision ville blive kontrolleret mod basisteksten. Ingen writer gør det i dag. |
| `private.clause_set_sha256` | 15967 | klausul | Hasher klausultekst, som allerede er skåret af sættets version. Sættets `parent_text_id` indgår ikke i hashen (se Bekymringer). |
| `private.relation_marriage_ordinals` | 16095 | klausul | `clause_observation_current`. |
| `private.relation_persona_input` | 16129 | klausul | `clause_observation_current`. |
| `private.write_relation_persona` | 16256-16343 | klausul | Klausul fra `clause_observation_current`, og mention skrives på klausulen. |
| `private.write_relation_person_create` | 18348 | klausul og mention | Mentionens klausul. Kontrollen `RELATION_PERSON_CREATE_CLAUSE_STALE` afviser et afløst sæt. |
| `public.red_source_persona_detail` | 9593 | mention | Mentiontekst. |
| `private.identity_candidate_input` | 9896 | mention | Mentiontekst. |
| `private.spouse_exception_projection` | 18191 | mention | Mentiontekst. |
| `private.relation_person_create_input` | 18253 | mention | Mentiontekst (`name_text`). |
| `private.ensure_reimport_source_evidence` | 3844-3874 | andet | Skriver basisteksten og læser den ikke. |
| `private.write_header_evidence` | 2845-2873 | andet | Overskrifts-observationer (header_*), ikke helposter. |
| `private.helpost_text_current` | 16027-16037 | andet | Selve funktionen. |
| Tabeldefinitioner | 492, 559, 573, 818 | andet | DDL. |

## B. Partsbaserede input (`interpretation_party_current`)

Reglen: et skrive- eller inputled, der bygger på en part, kræver, at partens fortolkning *aktuelt* er `proposed`
eller `accepted`. Parts-historikken bevares, og viewet er uændret.

### Ændret

| Funktion | Linjer | Ændring |
|---|---|---|
| `private.relation_person_create_input` | 18256-18261 | Join på `interpretation_current` med status `proposed`/`accepted`. En forældet eller afvist relation giver ingen D-række. |
| `private.relation_persona_v3_input` (`redecide_rows`) | 18702-18707 | Ægtefælleparten indgår kun med en aktuel relation. Rækken står (identiteten er stadig uafklaret), men `principal_person_id` og `marriage_ordinal` bliver NULL, så arket foreslår U. |

### Allerede filtreret, nøgle-scopet eller bevidst uændret

| Funktion | Linjer | Status |
|---|---|---|
| `private.relation_persona_input` | 16154 | Bruger samme nøgle som `ic`, der er filtreret til `proposed`/`accepted`. |
| `private.write_relation_persona` | 16234 (2) | `v_interp.status IN ('proposed','accepted')` kontrolleres før parten. |
| `private.write_relation_person_create` | 18340 (3) | `RELATION_PERSON_CREATE_CLAUSE_STALE` og `RELATION_PERSON_CREATE_INTERPRETATION_STALE` afviser allerede. Uændret, så fejlkoderne bevares. Testen viser, at det gamle element afvises efter en revision. |
| `private.check_family_corroboration` | 17461 (4) | `v_ic.status IN ('proposed','accepted')` på ægtefællepartens relation (`FAMILY_CORROBORATION_PROVENANCE_INVALID`). |
| `public.red_ret_aegteskabsnummer` | 16774 (3) | Kræver `accepted` (`MARRIAGE_ORDINAL_CORRECTION_NOT_BOUND`). |
| `private.marriage_ordinal_correction_input` | 16832 (2) | Kun `accepted`. |
| `public.red_decide_relation_interpretations` | 17844 | Kun `proposed`. |
| `red_afgoer_relation_interpretation`, `private.decide_relation_child`, `private.relation_child_rule`, `private.relation_structural_candidates` | 16945, 16684, 16589, 16867 | Nøgle-scopet på den fortolkning, der afgøres. Kalderen kræver `proposed`. |
| `private.relation_binding_state` | 17710 (4) | Bindingshash for en given fortolkning. Uændret, fordi de gemte hashes ellers ville flytte sig. Rute-A-rivaltjekket (`ic2.status<>'rejected'`, 17710) tæller også afløste (superseded) relationer; afgøres i 6c sammen med FAMILY_CORROBORATION_DOUBLE_TARGET. |
| `private.relation_disposition_state` | 18488 (2) | Kun klausuler med aktuel disposition `afventer_identitet`. Et afløst sæt er `erstattet`. |
| `private.write_source_text_revision` | 4709 | Kvitteringen lister med vilje parterne for de nøgler, revisionen forælder. |
| `private.persona_family_context`, `private.spouse_principal_person` | 16496, 17447 | Læse- og kontekstfunktioner for identitetsafgørelsen. Skrivevejen (`check_family_corroboration`) filtrerer selv, og en ændring ville flytte `family_context_sha256` i kandidatkørsler. Ikke ændret. |
| `private.validate_interpretation_party` | 1404 | Trigger på selve parts-tabellen. |

**Afhængighed i nuværende data:** `superseded` findes ikke i prod før 6c (overgangen er ny i §4.4 pkt. 2).
`transfer_5ab_guards.sql:24` kræver 0 elementer i `relation_person_create_input` (beslutning 8). Filteret er derfor
uden virkning på prods nuværende input. Den eneste mulige ændring for ikke-forældede data: en v3-genafgørelsesrække,
hvis ægteskabsrelation er **afvist** (`rejected`), viser nu U i stedet for et forslag. Det er hensigten i specen, men
det bør tælles på stand-in (se rapporten).

## C. Scripts (udfald efter Task 13)

DB-læsere af helposttekst:

| Fil:linje | Klasse | Udfald |
|---|---|---|
| `export_43b_runner_input.R` (`posts`) | helpost (observation) | **Flyttet** (Task 13): `post_text` = `helpost_text_current(ob.id)`. Klausulerne (`clause_observation_current`) er det aktuelle sæt; eksporten kræver, at sættets `parent_text_id` er den eksporterede tekstversion, ellers `EXPORT_CLAUSE_SET_TEXT_MISMATCH` (klausulerne ville ikke være delstrenge af posten). Test: `tests/integration/test-reimport-source-text-revision.R` (writer-jobbet). |
| `export_43b_runner_input.R` (`clauses`) | klausul | **Allerede korrekt**: `clause_observation_current` = det aktuelle sæt. Efter en revision er det sættet bundet til tekstversionen (se kontrollen ovenfor). |
| `export_clause_source_texts.R` | helpost (observation) | **Flyttet** i Task 11: helposten vælges af `record_helpost_status`, teksten og `text_id` af `helpost_text_current`. |
| `export_model_eligibility.R` (`text_filter`, `record_input`) | helpost (observation) | **Flyttet** (Task 13): mønstertjek og `input_sha` på den gældende tekst, så `input_sha` følger runner-inputtet. Urørte poster: `input_sha` uændret (gældende tekst = basisteksten). `rules_script_sha256` ændres, fordi den er hashen af selve scriptfilen. Test: samme integrationstest. |
| `clause_evidence_projection.sql` (`parent_verbatim_sha256`) | helpost (observation) | **Flyttet til sættets tekst** (R13-a): hashen af `source_observation_text` i klausulens `parent_text_id`, ellers basisteksten. Ikke `helpost_text_current`: et afløst sæt hasher fortsat sin egen tekst. 2018-20 (ingen tekstversioner) er byte-identisk. Test: samme integrationstest (sæt 1 = basistekstens hash, sæt 2 = tekstversionens). |
| `interpretation_proposal_projection.sql` (`key_material_sha256`, `key_matches`) | nøgleversion | **Følger nøglen** (R13-c, spec §4.4 pkt. 6): nøgle- og tekstversion læses pr. nøgle af den forslags-event, hvis kvittering bærer nøglen (`key_version`/`text_version` på eventens topniveau; mangler de = v1). v1 genberegnes altid med v1-funktionen, v2 med `interpretation_proposal_key_material_v2(..., text_version)`. Ingen event: v1 som før. Komparatoren kræver nu `key_matches` for alle rækker med en kvitteret nøgle, også historiske (`INTERPRETATION_PROJECTION_KEY_MISMATCH`). Test: `tests/sql/test-interpretation-proposal-rerun.sql` (`test_projection_follows_key_version`) og `test_compare_interpretation_proposal_projection.py`. |
| `build_clause_evidence_manifest.py` / `build_clause_ledger.py` (clause_revision) | helpost (observation) | **Hash fra eksporten**: `parent_verbatim_sha256` er eksportens hash af den gældende tekst (via ledgeren) og regnes aldrig ud af renditionen. Ledgeren bærer eksportens `text_id`, når den findes; kan en tekstversion ikke ankres i profilens projektion, fejler byggeren med `CLAUSE_EVIDENCE_PARENT_TEXT_VERSION_NOT_PROJECTABLE`. 2018-20's revisioner er `@page_header`, som byggeren ikke projicerer, så en omsegmentering af en revideret 2018-20-post kan ikke bygges endnu (6c). |
| `export_legacy_migration_candidates_helpers.R` (`occurrence_verbatim_sha256`, `occurrence_text`) og `build_legacy_migration_manifest.py` (149b) | helpost (forekomst) | **Begrundet, ikke flyttet** (R13-b): forekomstens tekst, som `migrate_legacy_narrative_record` og 149b-manifesterne er bundet til; en revision lader forekomsten stå urørt. Kommentar i begge filer. |
| `preview_reimport_1939_v50_helpers.R:441, 636, 1036` | ingen DB-læsning, 1939-v50 | **Begrundet, ikke flyttet** (R13-b): `verbatim_text` er felter i sporets preview-/materialiserings-JSON, ikke en læsning af observationstekst. Sporet er afsluttet; `git grep` viser kun 1939-v50-scripts, deres tests og SKILL.md som kaldere, ingen 6a-scripts. Kommentar i filhovedet. |

Note til 6c: `export_43b_runner_input.R` og `export_model_eligibility.R` vælger stadig helposten som rodobservationen
på ankerforekomsten (ikke `record_helpost_status`). Kun teksten er flyttet; helpost-valget hører til 6c som i
forslags-writeren.

Klausul- og mentionlæsere (ingen helposttekst): `interpretation_proposal_projection.sql:77, 80`,
`interpretation_control_rows.sql:9`, `interpretation_decision_fingerprint.sql:25`,
`interpretation_transfer_digests.sql:10`, `identity_control_rows.sql:29`, `relation_marriage_sheet*.py`,
`relation_persona_extract*.py`, `identity_queue_sheet.py:47` og `spouse_exception_sheet.py:64`.
Forslagsprojektionen følger nu nøgleversionen (Task 13, se tabellen ovenfor), men den læser ikke helposttekst.

Fil- og manifestbaserede (ingen DB-læsning af helposttekst): `build_43b_selection.py`, `build_45_selection.py`,
`build_clause_ledger.py`, `build_header_manifest.py`, `build_source_evidence_manifest.py`, `clause_ledger.py`,
`clause_segment.py`, `evidence_contract.py`, `evidence_runner.py`, `prepare_source_record_review.py`,
`run_evidence_43a_rehearsal.py`, `run_evidence_43b.py`, `segment.py`, `source_record_ledger.py` og alle
`*_1939*`-scripts (`apply_*`, `build_c0_*`, `build_c3_*`, `build_*identity*`, `build_name_completion_*`,
`build_narrative_replacement_*`, `build_phase_a_*`, `build_production_write_*`, `build_provenance_review_*`,
`convert_*`, `coverage_1939.py`, `human_review_1939_ui.js`, `make_human_review_1939.py`,
`materialize_*`, `prepare_coverage_1939.py`, `prepare_reimport_1939_v50.py`, `prepare_review_queue_1939.py`,
`reconcile_source_records_1939.py` og `rendition_occurrences_1939.py`).
