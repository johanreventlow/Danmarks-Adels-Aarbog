# Roadmap-trin 4: den fælles fortolkningskæde og klausulgranularitet (#147/#148)

**Dato:** 2026-09-06 (revision 2 samme dag efter uafhængig Opus-læsning, 27 fund)
**Status:** Designspecifikation. Sektionerne er godkendt af projektejeren i samtale;
revision 2 indarbejder anden læsers fund og projektejerens tre afgørelser på dem.
Afventer projektejerens læsning af den skrevne spec, før planer skrives.
**Roadmapmål:** trin 4 i `docs/evidensbaseret-genimport/roadmap.md`.
**Forudsætning:** trin 1-3 (#152, #153, #149) er anvendt og efterverificeret i prod
2026-09-05/06 (GO 1-4, `docs/changelog.md`); prod kører narrativ-record-kontrakt
version 2. `status.md`/`roadmap.md` er endnu ikke fuldt afstemt med det
(åbent punkt 11.6).
**Autoriserer:** planlægning af de otte dagsværk i afsnit 3. Autoriserer hverken
kode, modelkald mod rigtige data, databasemigration eller produktionsmutation;
hver af disse har sin egen gate (afsnit 10).

---

## 1. Beslutning

Fortolkningslaget fyldes gennem den fælles motor, ikke gennem en ny udgaveparallel
vej. Arbejdet deles i otte dagsværk (afsnit 3), hver med præcis én rigtig kørsel
mod en restore af produktionsdumpet som definition of done.

Seks valg er truffet af projektejeren 2026-09-06 og gælder for alle dagsværk:

1. **Model-backend:** `codex exec` med de model-id'er, udgaveprofilen låser
   (`gpt-5.6-terra`, eskalering `gpt-5.6-sol`). Profilen ændres ikke. Fravalgt:
   `claude -p`/Sonnet (profil v2, ny GO, leverandørskift).
2. **Skrivevej:** to nye elementoperationer i #153's generelle writer
   (`clause_evidence`, `interpretation_proposal`). Fravalgt: separate RPC'er uden
   for writeren.
3. **Anden læser:** uafhængig maskinel læser (Opus 2026-09-06; Codex `gpt-5.6-sol`
   når kvoten tillader) af spec og hver plan, derefter projektejerens afgørelse.
4. **Udelukkelseskriterium for modelkald (GDPR):** regel 1-4 i afsnit 9.2 med
   1950 som årsgrænse.
5. **Behandlingsgrundlag:** projektejeren accepterer, at `codex exec` kører på
   projektejerens ChatGPT-abonnement (ikke API-nøgle med særskilte
   databehandlervilkår) som grundlag for behandling af *afdøde* personers
   kildetekst. Et skift til API-nøgle er en ny projektejerbeslutning.
6. **Promotion i trin 4 er binding, ikke oprettelse:** en accepteret fortolkning
   bindes til en allerede eksisterende, tekstidentisk assertion på den kanoniske
   person. Oprettelse af nye fakta, assertions eller personer fra fortolkninger er
   uden for trin 4 (afsnit 8.3).

## 2. Roadmappens seks adgangskrav

1. **Roadmapmål:** trin 4, "den fælles fortolkningskæde og klausulgranularitet
   (#147/#148)".
2. **Værdikædeled, der lukkes:** `klausulobservationer og mentions → proposed
   interpretations → menneskelig afgørelse → promotion (binding)` for 2018-20,
   **for hovedpersonens source persona**. Leddet `source personas og
   identitetskandidater` genbruges fra 149b (587 personaer) og udvides ikke; claims
   om andre aktører parkeres med dispositionen `afventer_identitet` til trin 5.
   Tilstanden for "Extractor-runner og modelkald" og "Proposed-ingest" flytter til
   `integreret ende-til-ende` for 2018-20; "promotion" flytter kun for
   *bindingsdelen*. 1939 får kæden i trin 6.
3. **Generel, profil eller legacy:** generel motor (segmenter-kontrakt,
   prædikattabel, runner, svar-cache, to writer-operationer, afgørelses- og
   promotionskript) plus 2018-20-profiludvidelse (klausulregler, hvidlistet
   mellemrumstegnsæt, pristabel, udelukkelsesregler). Ingen legacy-afvikling.
4. **Redaktionel værdi:** strukturerede, kildebundne fakta med belæg pr. klausul,
   som redaktøren accepterer, afviser eller lader stå uafklaret én ad gangen;
   §7.3's kategorier og indgiftedes egne oplysninger bliver *registrerbare* som
   forslag uden nyt grundudtræk (§20). Promotion af dem til kanoniske fakta kræver
   regler, der ikke findes endnu (åbent punkt 11.2).
5. **Bevis:** den navngivne rigtige kørsel pr. dagsværk (afsnit 3) med tal og
   hashes. "Uændrede kanoniske aggregat-hashes" er et *neutralitetsbevis*
   (operationen rørte ikke det, den ikke måtte), ikke et funktionsbevis;
   funktionsbeviset er pr. dagsværk angivet særskilt.
6. **Erstatter (muliggør):** trin 4 leverer ikke selv nedtagning af den gamle
   skills trin ③-④, `validate.py`'s flet eller `project_evidence.R`; det kræver
   paritet og disposition for alle berørte rækker (målarkitekturen, "Overgang fra
   legacy"). Trin 4 gør erstatningen *mulig* ved at levere den vej, trin 6 skal
   bevise paritet for. `ALLOWED_PREDICATES` som selvstændigt vokabular erstattes
   dog reelt i 4.2.

## 3. Dekomposition og rækkefølge

| Dagsværk | Issue | Indhold | Rigtig kørsel (DoD) |
| --- | --- | --- | --- |
| 4.1a Skema | #148 | kolonner, triggere, privat vokabular, dispositionsledger, legacy-writer-hærdning, kontraktbump | migration + verify på restore; 149a/149b-autorisationsformer valideres uændret |
| 4.1b Segmenter | #148 | `clause_segment.py`, profilregler, hvidlistet tegnsæt, syntetisk fixture | ledger for alle 591 2018-20-records (privat artefakt), dækning 100 %, tal |
| 4.1c Writer | #148 | `clause_evidence` + ACL + CI | 591 records skrevet i restore, neutralitetshashes, replay |
| 4.2 Vokabular | #147 (3+4) | prædikattabel, genereret fil, kind-afledning | migration + verify på restore |
| 4.3a Runner | #147 (1) | forbrugsprobe, svar-cache, fejltaksonomi, runner, udelukkelsesliste | syntetisk record gennem terra med reelt forbrug i manifest |
| 4.3b Rigtig kørsel | #147 (1) | 10 afdøde records | manifest `green`, claims citerer klausuler; tidligst efter kvotenulstilling 2026-09-09 |
| 4.4 Ingest | #147 (2) | `interpretation_proposal` + ACL + CI | 4.3b's batch ingestet i restore |
| 4.5 Pilot | #147 (5) | udvalg, afgørelse, binding, rapport | ≥30 person- + ≥10 strukturelle records, kæden ende-til-ende i én restore |

Rækkefølgen er bindende. Hvert dagsværk får sin egen plan, som besvarer de seks
adgangskrav, læses af anden læser og afgøres af projektejeren, før det begynder.
4.3b-4.5 deler **én** restore (`clause`-id'er er database-genererede; se 4.1.4 om
nøgling), så "frisk restore" gælder 4.1a-4.3a og 4.5's start, ikke hvert trin.

Ingen af de otte dagsværk muterer produktion. Første kandidat til en senere
prod-GO er 4.1c alene (privat kildeevidens, nul kanonisk delta), med sin egen
fortrydelseskvittering (afsnit 4.1.5).

## 4. Klausullaget (#148, dagsværk 4.1a-4.1c)

### 4.1.1 Målt udgangspunkt

Begge udgaver har én helpost-observation pr. source record med én mention over
hele teksten: 2018-20's 591 er skrevet af `private.ensure_reimport_source_evidence`
(`observation_kind` = recordens kategori, `person_post`); 1939's tal (897) stammer
fra afvigelsesvurderingen 2026-08-22 og genmåles i 4.1a's inventering. Der findes
ingen klausuler, ingen del-span-mentions og intet klausulregnskab.
`clause_ledger.py` er en ren Python-kontrakt uden databasevej.

### 4.1.2 Datamodel (additivt, append-only)

`private.source_observation` får fire nullable kolonner:

- `parent_observation_id` (FK til samme tabel),
- `clause_ordinal integer`,
- `clause_classification text` (`record_text` | `structural_header`),
- `clause_flags jsonb` (liste af segmenterings-flag, tom liste tilladt).

Trigger-regler: `observation_kind='clause'` ⇔ alle fire kolonner sat; andre kinds
⇒ alle fire NULL. Barn og forælder deler `occurrence_id`; forælderen har selv
`parent_observation_id IS NULL` (ét niveau); barnets rendition-absolutte
`[char_from,char_to)` ligger inde i forælderens; barnets `verbatim_text` er lig
forælderens tekst udskåret på barnets offsets (substring-check);
`UNIQUE(parent_observation_id, clause_ordinal)`.

**Offset-konvention:** databasen er rendition-absolut (som
`validate_evidence_scope` kræver). Ledger, payload og prompt er helpost-relative
(offset 0 = helpostens `char_from`). Writeren oversætter ved at lægge helpostens
`char_from` til, og verificerer hash pr. klausul efter oversættelsen.

**Vokabular:** `observation_kind`, `clause_classification` og
`clause_disposition` er interne workflow-vokabularer og lægges i en ny
`private.vocab(scheme, code, label)` med samme form som `public.vocab`, fordi
`public.vocab` er anon-læsbar. Håndhæves med trigger-opslag. Migrationen
inventerer først de `observation_kind`-værdier, der faktisk findes, seeder dem
og fejler ved en værdi, den ikke kan seede.

**Dækningsinvariant, to lag:** (1) Python-ledgeren fra `clause_ledger` er den
*fulde* dækningskontrakt (hvert tegn, inkl. `layout`/`noise`); dens SHA-256
går i manifestet. (2) Databasen projicerer kun `record_text` og
`structural_header`. Writeren håndhæver, at mellemrummene mellem søskende
inde i forælderen udelukkende består af tegn fra profilens **hvidlistede
mellemrumstegnsæt**, som 4.1b måler empirisk over alle 591 tekster og fryser i
profilen (forventet: whitespace, linjeskift, orddelingsstreg; *ikke* sidetal,
som ikke forekommer inde i en helpost efter 149a's rendition, hvilket 4.1b
skal bekræfte ved måling, ellers udvides klassifikationen). "Dækning 100 %"
måles i ledgeren, ikke i databasen alene.

**Dispositionsledger:** `private.clause_disposition(id, observation_id, version,
disposition, decided_by_kind ('machine'|'human'), decided_by, decided_by_name,
decided_at, evidence jsonb, created_at)` med `UNIQUE(observation_id, version)`
og CHECK: `decided_by_kind='human'` ⇒ aktørfelter sat og `evidence<>'{}'`;
`'machine'` ⇒ aktørfelter NULL og `evidence` bærer run-/manifest-hash.
Maskinelle tilstande og §15.1's endelige tilstande er adskilte koder:

- maskinelle: `afventer_fortolkning`, `fortolkning_foreslaaet`,
  `afventer_identitet`, `maskinelt_flagget`, `strukturel`;
- endelige (kun `human`): `struktureret`, `relevant_uklassificeret`,
  `ikke_biografisk`, `layout_stoej`, `ulaeselig_ocr`, `kraever_menneske`.

Seneste version pr. observation er gældende (`clause_disposition_current`).

**Legacy-writer-hærdning (fund 3b):** `private.migrate_legacy_narrative_record`
tæller i dag mentions over *alle* occurrencens observationer og kaster
`LEGACY_MIGRATION_MENTION_AMBIGUOUS` ved >1. Med klausul-mentions ville det lukke
vejen for de fire `unresolved_text`-records og for 1939. 4.1a ændrer tællingen
til kun helpost-observationer (`parent_observation_id IS NULL`), med
regressionstest på både positiv og negativ side.

**Kontrakt:** `evidence_contract._as_observation` (strict feltsæt) udvides med de
fire kolonner; bundle-skemaversion bumpes 1.1 → 1.2, og `validate_output`
accepterer 1.2. `Mention` er allerede offset-relativ til sin observation og
ændres ikke.

### 4.1.3 Segmentering (4.1b)

- Nyt motor-script `clause_segment.py` (deterministisk, ingen modelkald, ingen
  netværk). Input: helpostens tekst og profilens `clause_rules`. Output:
  klausulliste i `clause_ledger`-format, godkendt af `build_ledger`/`validate_ledger`.
- Reglerne bor i profilen (`extraction-profiles.json` → `clause_rules` med egen
  `version` og `gap_charset`): skilletegn, DAA-forkortelser der ikke afslutter en
  klausul, mønstre for "Børn:"-lister og slægtledsoverskrifter. Motoren validerer
  reglernes form; en regelændring er en ny version og gør gamle klausulmanifester
  ikke-genbrugelige.
- Tvivl (ubalancerede parenteser, ukendt forkortelse før punktum, klausul under
  mindstelængde, flere "gift"-udsagn uden skilletegn) segmenteres konservativt og
  får `clause_flags`; startdisposition `maskinelt_flagget`. Øvrige `record_text`:
  `afventer_fortolkning`. `structural_header`: `strukturel`.
- Første test: Task 2's syv svære tilfælde i en **ny** syntetisk fixture
  `tests/fixtures/evidence-clauses.synthetic.json` (den eksisterende
  `evidence-observation.synthetic.json` bruges af `test_evidence_contract.py` og
  røres ikke).
- Rigtig kørsel: ledger for alle 591 records som privat artefakt (0600); tal:
  klausuler pr. record (min/median/max), flag-andel, mellemrumstegn observeret
  uden for hvidlisten (skal være 0, ellers stop).

### 4.1.4 Writer-operation `clause_evidence` (4.1c)

- Payload pr. element (= én source record): `source_record_key`,
  `rendition_content_sha256`, `parent_verbatim_sha256`, `clause_rules_version`,
  `segmenter_version`, `ledger_sha256`, `clauses[]` med `ordinal`, `char_from`,
  `char_to` (helpost-relative), `classification`, `verbatim_sha256`, `flags[]`.
  Ingen tekst i payload; writeren udskærer og hash-verificerer.
- Writeren tager `FOR UPDATE` på helpost-observationen (radlås; profil-låsen
  `lock_reimport_writer` er pr. (source, profil) og dækker ikke to profiler på
  samme source). Findes der ikke præcis én helpost under recordens accepterede
  occurrence, eller findes der allerede klausuler, afvises elementet
  (`REIMPORT_WRITER_CLAUSE_EVIDENCE_EXISTS`); batch-replay via `already_applied`.
- **Nøgling af klausuler udadtil:** klausul-UUID'er er `gen_random_uuid()` og
  overlever ikke en restore. Al ekstern reference (runner, claims, ingest) bruger
  derfor `(source_record_key, clause_ordinal, verbatim_sha256)`; writeren slår
  UUID op. Prompten ser kun ordinal og tekst.
- **Hårdkodede steder i writeren, som operationen rører (fund 8):**
  `private.validate_reimport_authorization_payload` (lukket nøglesæt,
  obligatoriske `person_creates`/`source_evidence`, tre faste præfiks-regexer),
  `public.red_finalize_reimport` og `red_reimport_batch_result` (count-mapping),
  `reimport_event.operation`-CHECK, ny public RPC med REVOKE/GRANT, #154's
  ACL-arrays i `db-rls.sql`, CI-allowlist-test. 4.1c kræver en
  regressionsassertion om, at 149a's og 149b's autorisationsformer valideres
  uændret, og en ny `reimport_writer_profile`-række for operationen (samme
  `profile_id` med ny hash afvises af `REIMPORT_WRITER_PROFILE_HASH_INVALID`).
- `expected_counts` får den valgfri nøgle `clause_evidence`; præfiks
  `clause-evidence:`.

### 4.1.5 Fortrydelse og fase-pakke

Fortrydelse ved restore, som 149a. Kvitteringen fra 2026-09-03 gjaldt 149a og
arves ikke: før 4.1c's eventuelle prod-GO skal projektejeren kvittere særskilt
for "fortryd ved restore" for `clause_evidence`. Fase-pakke-bidraget erklærer
nul ændring i de fem dækkede projektioner; at runbookens projektioner ikke
dækker observationer, er åbent punkt 11.1.

### 4.1.6 Rigtig kørsel (4.1c)

Alle 591 records i restore. Levende personers tekst må indgå, fordi trinnet er
lokalt og deterministisk. Bevis: antal klausul-rækker = ledgerens
`record_text`+`structural_header`; dispositionsfordeling; neutralitets- og
`anon`-hashes uændrede; replay `already_applied`; 149b's fire `unresolved_text`
kan stadig migreres (test mod den hærdede legacy-writer).

## 5. Vokabular og kategorier (#147 leverance 3+4, dagsværk 4.2)

### 5.1 Ét navnerum, én tabel

`private.interpretation_predicate(predicate PK, interpretation_kind, category,
value_kind, status, introduced_in, created_at)`:

- `interpretation_kind` = §7.2's fire former, samme CHECK som `interpretation`.
- `category` = §7.3's syv eller NULL.
- `value_kind` ∈ `text`, `date_raw`, `name`, `event`, `relation`, `mention`.
- **Promoverbarhed udledes ved join** på `interpretation_promotion_rule_line.predicate`
  (som får FK til tabellen); tabellen har ingen `rule_key`-kolonne, så der er
  ingen cirkulær FK. `interpretation.predicate` får FK til tabellen.

**Værdiform (fund 1):** `validate_interpretation_promotion_items` sammenligner
`value #>> '{}'` som tekst. For `value_kind` `text` og `date_raw` er værdien
derfor en **JSON-skalar** (den ordrette betegnelse); normaliseret form gemmes
ikke i værdien men i `decision_evidence`/rapport. For `name`, `event`, `relation`,
`mention` er værdien et objekt med obligatorisk `raw` og valgfri `normalized`.
JSON-skemaerne pr. `value_kind` ligger i `interpretation-schema.json`
(versionsbump). Promotion-RPC'en ændres ikke i 4.2.

**Antagelse, der skal verificeres i 4.2:** "prod har 0 fortolkninger" (bærer
FK-migrationens sikkerhed) måles læse-kun i restoren og i prod før migration.

### 5.2 Prædikatliste (første seed)

Egenskaber (`person.*`): `name`, `name_part`, `name_variant`, `byname`,
`identity`, `uncertainty`, `negation`, `unknown`, `birth`, `baptism`, `death`,
`burial`, `title`, `form_of_address`, `rank`, `office`, `court_office` (ny),
`occupation` (ny), `education`, `decoration` (afløser `honour.honour`),
`estate`, `residence`, `military_service`, `publication`.
Relationer (`relation.*`): `marriage`, `parent`, `child`.
Hændelser (`event.*`): `marriage`, `appointment`, `dismissal`, `acquisition`,
`travel` (ikke promoverbare).
Omtaler (`mention.*`): `person`, `place`, `organisation`, `estate`.
Strukturelle: `lineage.introduction`, `genealogy.generation_header`,
`heraldry.description`, `heraldry.blazon`, `image.caption`,
`reference.cross_reference`.

Promoverbare fra start: de fem eksisterende regler. Regler for de øvrige seks
§7.3-kategorier er åbent punkt 11.2.

### 5.3 Indgiftede (§13)

Ingen særprædikater; forskellen bæres af personaen. Bindbart først i trin 5.

### 5.4 Genereret Python-liste og kind-afledning (fund 12)

`references/interpretation-predicates.json` genereres fra tabellen med
prædikat, `interpretation_kind`, kategori, `value_kind`, promoverbar.
`evidence_extract` læser `ALLOWED_PREDICATES` **og** `interpretation_kind`
derfra; `build_interpretation_candidates` gætter ikke længere på
prædikatfamilien. CI's Postgres-job asserterer byte-identitet tabel ↔ fil.

### 5.5 Rigtig kørsel

Migration på restore; verify: fem regler løser via join, FK'er holder, fil = tabel,
`validate_output` afviser `life_event.birth` og accepterer `person.birth`,
kind-afledning giver `event` for `event.marriage`.

## 6. Model-runneren (#147 leverance 1, dagsværk 4.3a-4.3b)

### 6.1 Runner

Nyt motor-script `evidence_runner.py`. Input: batch-manifest fra
`evidence_extract.prepare_batch` og en privat, record-scoped eksport fra restoren:
pr. record helposten og dens klausuler som `(ordinal, verbatim_text,
verbatim_sha256)`. Modellen ser én record ad gangen (§19) og returnerer claims,
der citerer klausul-**ordinaler**.

**Record-scoped claim-kontrakt (fund 10):** `validate_output`'s strict bundle-vej
kræver hele renditionens tekst og rendition-absolutte offsets og passer ikke til
et record-scoped artefakt. Runneren bruger derfor en ny kontrakt
`evidence-claims-1.0` (`references/`), valideret i Python (`validate_record_claims`)
og igen i writeren: hvert claim citerer ≥1 ordinal, der findes i eksporten med
matchende hash; prædikat og `interpretation_kind` fra 5.4; værdi mod `value_kind`;
confidence i [0,1]. Persona-reglen (fund 3a): et `principal`-claim må citere
klausuler under den helpost, personaen har mention i (ikke længere "delmængde af
personaens egne mention-observationer").

### 6.2 Codex-kald

`codex exec` ikke-interaktivt: `--model` fra manifestet, `--sandbox read-only`,
`--ephemeral`, `--ignore-rules`, `--json`, `--output-schema`, stdin lukket.
Prompten er `references/evidence-extract-prompt-<version>.md` (den eksisterende
uversionerede `extract-prompt.md` omdøbes/versioneres som et skridt i 4.3a, så
profilens `prompt_version` får en matchende fil); SHA-256 i manifestet.
`BatchManifest` udvides med `prompt_sha256`, `exclusion_sha256`, `pricing_version`,
`usage`.

### 6.3 Svar-cache og fejltaksonomi (fund 15)

- **Per-record uforanderlig svar-cache** før batch-manifestet: nøgle =
  `(profil, profilversion, model, prompt_sha256, record_input_sha256)`; værdi =
  rå JSON-svar + usage. `green` for en batch samles fra cachen; et kvotestop
  midt i en batch koster ikke genkørsel af besvarede records. `reusable`
  udvides tilsvarende.
- **Fejltaksonomi**, alle fail-closed (batch forbliver `pending`, intet merge):
  `quota_exhausted`, `model_refusal`, `schema_violation`, `timeout`,
  `validation_failed`, `unknown`. Hver fejl logges med typen, aldrig med tekst.

### 6.4 Regnskab

Token-tal fra Codex' JSON-hændelser; omkostning fra profilens pinnede `pricing`
(pr. model-id, egen version); model uden pris stopper. Batches 5-10 records.
Eskalering til `gpt-5.6-sol` kræver `escalation_reason` og kun validator-flaggede
records.

### 6.5 Rigtige kørsler

- **4.3a:** én syntetisk, ikke-identificerende record gennem `gpt-5.6-terra` med
  reelt forbrug i manifestet; beviser forbrugsrapportering, cache, output-skema og
  fejltaksonomi (kvote simuleres ikke; den observerede `turn.failed` fra proben
  2026-09-06 er fixturen).
- **4.3b:** 10 afdøde records (udelukkelsesregler i 9.2) fra restoren: manifest
  `green`, alle claims citerer eksisterende ordinaler, kandidater `proposed`,
  kvoteforbrug pr. record målt. Tidligst 2026-09-09.

### 6.6 Målt, ikke antaget

Probe 2026-09-06 mod `codex-cli` 0.153.4: flagene i 6.2 findes; `--json` udsender
`thread.started`, `turn.started`, `turn.failed`. Token-rapportering er **ikke**
verificeret (turen fejlede på kvote). 4.3a's første skridt er at bekræfte den;
kan CLI'en ikke rapportere forbrug, stopper 4.3 med et navngivet fund.

### 6.7 Kvote

`codex exec` kører på abonnement (afsnit 1, valg 5). Konsekvenser: kørsler kan
stoppe uden fejl i input; cachen i 6.3 gør stop billige; plan 4.3b måler
kvoteforbrug pr. record, så trin 6 kan budgetteres, før den startes.

## 7. Proposed-ingest (#147 leverance 2, dagsværk 4.4)

### 7.1 Writer-operation `interpretation_proposal`

- Payload pr. element (= én record fra ét grønt manifest): `source_record_key`,
  `runner_manifest_sha256`, `model_version`, `prompt_version`, `claims[]` med
  `claim_id`, `predicate`, `interpretation_kind`, `value`, `confidence`,
  `cited_clauses[]` = `(ordinal, verbatim_sha256)`, `persona_role`
  (`principal` | `other`).
- Writeren opretter (idempotent på `run_key`) én `extraction_run` for manifestet
  med usage i `manifest`, slår klausul-UUID'er op via `(record, ordinal, hash)`,
  og skriver pr. claim én `interpretation` (`proposed`, `model_inference`,
  `method='model'`, version 1) plus `interpretation_observation` (`supporting`,
  ordinal) i samme transaktion under den eksisterende deferred constraint
  `interpretation_has_observation`.
- **`interpretation_key` (fund 11):** deterministisk
  `uuid_v5(ns, source_id|record_key|predicate|cited ordinals|value_sha256)`.
  Findes nøglen allerede, afvises elementet
  (`REIMPORT_WRITER_INTERPRETATION_PROPOSAL_EXISTS`). Genudtræk af en allerede
  ingestet record kræver en menneskelig `superseded`-beslutning og er trin 6.
- Afvisninger: ukendt/hash-afvigende klausul, klausul uden for recordens helpost,
  prædikat ikke `active` i 5.1, værdi ≠ `value_kind`, confidence uden for [0,1],
  `principal`-claim på en record uden persona (de fire `unresolved_text`; fund 19).
- `expected_counts`-nøgle `interpretation_proposals`; operation-CHECK, præfiks
  `interpretation-proposal:`, ACL, CI som i 4.1.4.

### 7.2 Hvem claims handler om

`principal` → recordens persona (helpost-observation → mention →
`source_persona_mention`, som 149b skriver med rolle `primary`). `other` →
`source_persona_id IS NULL`, form `mention`/`relation`, citerede klausuler får
`afventer_identitet`. Persona-oprettelse for andre aktører er trin 5.

### 7.3 Klausulregnskab

Pr. claim: citerede klausuler får ny maskinel dispositionsversion
`fortolkning_foreslaaet` (eller `afventer_identitet`). Uciterede beholder deres.

### 7.4 Fortrydelse

Ved restore i restore-baser. Forkerte forslag afvises af mennesket i 4.5 og
bliver `rejected`. Prod-fortrydelse for denne operation er ikke designet og er
en forudsætning for et senere prod-GO (åbent punkt 11.5).

### 7.5 Rigtig kørsel

4.3b's batch ingestet: antal = manifest; alle links løser; neutralitets- og
`anon`-hashes uændrede; replay `already_applied`; dispositionsfordeling som
forventet; `principal`-claim på en persona-løs record afvises (negativ test).

## 8. Pilot, afgørelse og binding (#147 leverance 5, dagsværk 4.5)

### 8.1 Udvalg

Deterministisk, hash-bundet: ≥30 afdøde personposter, stratificeret maskinelt på
tekstlængde, antal "gift"-udsagn, indgiftede, titler/embeder, usikre datoer, plus
≥10 strukturelle poster. Skåret mod udelukkelseslisten (9.2). Repo-notat kun med
record-nøgler og aggregater.

### 8.2 Kæden i én restore

4.1-klausuler → 4.3-runner → 4.4-ingest → afgørelse → binding, i **samme**
restore. Afgørelsen bruger projektets menneske-ark (token-pr-linje med
forudfyldt anbefaling), hashes ved godkendelse og oversættes til
`red_decide_interpretation` (`accepted`/`rejected`/`unresolved`) under
projektejerens redaktionsprofil med `request.jwt.claim.sub`. Ingen ny UI.

### 8.3 Binding (valg 6)

`red_promote_interpretations_batch` opretter intet kanonisk: den kræver en
eksisterende `assertion` → `fact` på den identificerede person med matchende
`faktatype` og tekstidentisk værdi, og skriver kun `interpretation_promotion`.
Trin 4's "promotion" er derfor en **dokumenteret binding** af en accepteret
fortolkning til den gamle loaders assertion. `target_id` findes maskinelt af et
script, der for hver accepteret, promoverbar fortolkning slår assertions op på
personen med reglens `expected_fact_type` og vælger den, hvis normaliserede
værdi matcher; ingen match ⇒ fortolkningen forbliver `accepted` uden binding og
tælles. Succeskriteriet er en *målt andel*, ikke en tærskel: rapporten angiver
accepterede promoverbare fortolkninger, hvor mange fandt en assertion, og hvor
mange ikke gjorde (og hvorfor). Oprettelse af nye fakta/personer er uden for
trin 4 (åbent punkt 11.3).

### 8.4 Måling (§15.3)

Pr. prædikattype: præcision mod projektejerens afgørelse, exact-span-rate,
dispositionsdækning, `normalized` uden `raw`-belæg, token/pris/kvote pr. record,
bindingsandel. Absurd lav/høj dækning i en kategori blokerer som `NO-GO` for
fuld kørsel. Rapport: `docs/evidensbaseret-genimport/interpretation-pilot-2018-20.md`.

### 8.5 Hvad beviset flytter

"Extractor-runner og modelkald" og "Proposed-ingest" → `integreret
ende-til-ende` for 2018-20 (hovedpersonens persona). "Promotion" flytter kun for
bindingsdelen og markeres sådan i `status.md`. Intet bliver
`produktionsverificeret`. En restore af 4.5's base sletter projektejerens egne
afgørelser; derfor tages en 0600-backup af basen efter afgørelserne og før
binding.

## 9. Privatliv og databehandling

### 9.1 Principper

- 4.1 (deterministisk, lokalt) må behandle alle records.
- Modelkald kun for records, der består alle regler i 9.2.
- Private artefakter: 0600, ignoreret mappe, aldrig commit, slettes efter
  projektejerens ja. Prompten indeholder én records tekst og ordinaler, aldrig
  database-UUID'er eller andre records.
- Codex' sandbox uden skriveadgang; behandlingsgrundlag jf. valg 5.

### 9.2 Udelukkelsesregler (valg 4; målt 2026-09-06 i lokal prod-kopi)

En record udelukkes fra modelkald, hvis mindst én regel rammer:

1. Hovedpersonen er levende eller uafklaret (46 + 4 records).
2. En partner eller et barn i databasen (`family_member` i samme `family`) er
   markeret levende (13 records ekstra).
3. En partner er uden dødsdato, *og* ægteskabet er indgået 1950 eller senere
   (partnerstatus er upålidelig: 62 poster har en partner markeret ikke-levende
   uden dødsdato).
4. Tekstfilter: posten indeholder "f." efterfulgt af et fødselsår 1950 eller
   senere (i dag 2 poster) → manuel udelukkelse.

Listen eksporteres læse-kun fra restoren som record-nøgler, dens SHA-256 står i
manifestet, og runneren nægter at køre uden den. Udelukkede records bliver stående
i køen; de er ikke tab. Målt baggrund: 541 afdøde hovedpersoner, 156 af dem uden
registreret dødsår (ældre generationer), 14 døde 1990 eller senere.

## 10. Gater

| Handling | Gate |
| --- | --- |
| Plan pr. dagsværk | seks adgangskrav; anden læser; projektejerens afgørelse |
| Kode | TDD; syntetiske fixtures først; CI's seks jobs grønne; regressionsassertion 149a/149b-autorisation |
| Rigtig kørsel | restore af prod-dump (0600); tal + hashes dokumenteret |
| Første modelkald mod rigtige data (4.3b) | udelukkelsesliste hash-bundet efter 9.2; behandlingsgrundlag jf. valg 5 kvitteret; projektejerens GO med manifest-hash og budget; efter kvotenulstilling |
| Efterfølgende modelkald (4.5) | som ovenfor, pr. kørsel |
| Prod-apply | særskilt GO pr. apply efter fase-pakke-gaten og særskilt fortrydelseskvittering pr. operation; uden for denne spec |

## 11. Åbne punkter (registreres, løses ikke her)

1. Fase-pakke-runbookens fem projektioner dækker hverken observationer eller
   fortolkninger; en klausul- og en fortolkningsprojektion skal defineres, før
   4.1c/4.4 kan afstemmes i prod. Issue før første prod-GO.
2. Promotion-regler for embede, hofstilling, militær rang, erhverv, uddannelse,
   dekoration afventer faktatype-afklaring i `vocab`.
3. Oprettelse af nye kanoniske mål (fakta, assertions, personer) fra fortolkninger
   er ikke designet; den eksisterende RPC binder kun.
4. 1939's klausulregler (OCR, orddelinger) og fuld 2018-20-kørsel er trin 6.
5. Prod-fortrydelse for `interpretation_proposal` og for menneskelige
   afgørelser er ikke designet (restore sletter afgørelser).
6. `status.md` (tabel vs. "Åbne blokeringer") og `roadmap.md` ("Aktivt
   programmål" peger på #152) er ikke afstemt med GO 1-4; rettes i en
   docs-PR før plan 4.1a.
7. Persona-oprettelse for andre aktører (§13 fuldt) er trin 5.

## 12. Fravalgt

- Model-foreslåede klausul-spans i 4.1 (§19; modelvejen får flaggede records i 4.3).
- Oversættelsestabel mellem extractor- og promotion-prædikater.
- Separate ingest-RPC'er uden for den generelle writer.
- Ny redaktør-UI for fortolkninger i dette trin.
- Reversal-RPC for klausuler og forslag i restore-baser (restore er nok der).
- Objekt-værdier for promoverbare prædikater (bryder promotion-valideringen).
- Layout-/støj-rækker i databasen (ledgeren bærer den fulde dækning).
