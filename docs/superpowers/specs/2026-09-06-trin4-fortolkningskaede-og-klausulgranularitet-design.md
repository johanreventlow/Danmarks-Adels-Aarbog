# Roadmap-trin 4: den fælles fortolkningskæde og klausulgranularitet (#147/#148)

**Dato:** 2026-09-06
**Status:** Designspecifikation, godkendt sektionsvis af projektejeren i samtale;
afventer anden læser (Codex `gpt-5.6-sol`) og projektejerens afgørelse på
læserens fund, før nogen plan implementeres (decisions 2026-09-03, regel 2).
**Roadmapmål:** trin 4 i `docs/evidensbaseret-genimport/roadmap.md`.
**Forudsætninger opfyldt:** trin 1-3 (#152, #153, #149) er `produktionsverificeret`
2026-09-06; prod kører narrativ-record-kontrakt version 2.
**Autoriserer:** planlægning af fem dagsværk (afsnit 3). Autoriserer hverken kode,
modelkald mod rigtige data, databasemigration eller produktionsmutation; hvert af
disse har sin egen gate (afsnit 10).

---

## 1. Beslutning

Fortolkningslaget fyldes gennem den fælles motor, ikke gennem en ny udgaveparallel
vej. Det sker i fem adskilte dagsværk, hver med præcis én rigtig kørsel mod en frisk
restore af produktionsdumpet som definition of done:

| Dagsværk | Issue | Lukker | Rigtig kørsel |
| --- | --- | --- | --- |
| 4.1 Klausullaget | #148 | klausulobservationer + dækningsinvariant | alle 591 2018-20-records segmenteret og skrevet i restore |
| 4.2 Vokabular | #147 (3+4) | ét prædikat-navnerum, §7.3's syv kategorier | migration + verify på restore |
| 4.3 Runner | #147 (1) | modelkald bag den frosne profil med reelt regnskab | 10 afdøde records gennem `gpt-5.6-terra` |
| 4.4 Proposed-ingest | #147 (2) | `interpretation` + observationslinks atomisk | 4.3's grønne batch ingestet i restore |
| 4.5 Pilot | #147 (5) | afgørelse + promotion i drift | ≥30 person- + ≥10 strukturelle records, kæden ende-til-ende |

Tre valg er truffet af projektejeren 2026-09-06 og gælder for alle fem:

- **Model-backend:** `codex exec` med de model-id'er, udgaveprofilen allerede
  låser (`gpt-5.6-terra`, eskalering `gpt-5.6-sol`). Profilen ændres ikke.
  Fravalgt: `claude -p`/Sonnet, som ville kræve profil v2, ny GO og et skift af
  den leverandør, der behandler kildeteksten.
- **Skrivevej:** to nye elementoperationer i #153's generelle writer
  (`clause_evidence`, `interpretation_proposal`). Fravalgt: separate ingest-RPC'er
  uden for writeren, fordi det er den anden skrivevej, #153 og fase-pakke-gaten
  blev lavet for at afskaffe.
- **Anden læser:** Codex `gpt-5.6-sol` reviewer spec og hver plan, derefter afgør
  projektejeren på fundene.

## 2. Roadmappens seks adgangskrav

1. **Roadmapmål:** trin 4, "den fælles fortolkningskæde og klausulgranularitet
   (#147/#148)".
2. **Værdikædeled, der lukkes:** `klausulobservationer og mentions → proposed
   interpretations → menneskelig afgørelse → promotion` for 2018-20; tilstanden
   flytter fra `specificeret`/`isoleret implementeret` til `integreret ende-til-ende`.
   1939 får samme kæde i roadmap-trin 6, ikke her.
3. **Generel, profil eller legacy:** generel motor (segmenter-kontrakt,
   vokabulartabel, runner, to writer-operationer, afgørelses- og promotionkald)
   plus en 2018-20-profiludvidelse (klausulregler, pristabel, udelukkelsesliste).
   Ingen legacy-afvikling.
4. **Redaktionel værdi:** strukturerede, kildebundne fakta med belæg pr. klausul,
   som redaktøren kan acceptere, afvise eller lade stå uafklaret én ad gangen;
   §7.3's kategorier (embede, hofstilling, erhverv, uddannelse, dekoration) og
   indgiftedes egne oplysninger bliver producerbare uden nyt grundudtræk (§20).
5. **Bevis:** den navngivne rigtige kørsel pr. dagsværk (tabellen i afsnit 1) med
   tal, hashes og uændrede kanoniske aggregat-hashes, dokumenteret i
   `docs/evidensbaseret-genimport/`.
6. **Erstatter:** den gamle skills trin ③-④ (Sonnet-udtræk uden kildebelæg,
   `validate.py`'s flet), `project_evidence.R`'s dry-run som "promotionvej", og
   extractorens Python-liste `ALLOWED_PREDICATES` som selvstændigt vokabular.

## 3. Dekomposition og rækkefølge

Rækkefølgen er 4.1 → 4.2 → 4.3 → 4.4 → 4.5 og kan ikke byttes: runneren skal citere
klausul-id'er (4.1), ingest afviser prædikater uden for tabellen (4.2), og piloten
kræver alle fire. Hvert dagsværk får sin egen plan i
`docs/superpowers/plans/`, som selv besvarer de seks adgangskrav og læses af
Codex før implementering. Et dagsværk må ikke begynde, før det foregående har
sin rigtige kørsel dokumenteret.

Ingen af de fem dagsværk muterer produktion. Første kandidat til en senere prod-GO
er 4.1 alene, fordi klausuler kun er privat kildeevidens med nul kanonisk delta.

## 4. Dagsværk 4.1: klausullaget (#148)

### 4.1.1 Målt udgangspunkt

Begge udgaver har i dag præcis én helpost-observation pr. source record, skrevet af
`private.ensure_reimport_source_evidence` (2018-20: 591, `observation_kind` =
recordens kategori, fx `person_post`) eller af 1939's fase A (897 observationer =
897 occurrences), hver med én mention over hele teksten. Der findes ingen
klausuler, ingen del-span-mentions og intet klausulregnskab. `clause_ledger.py`
findes som ren Python-kontrakt (dækning, ikke-overlap) uden databasevej.

### 4.1.2 Datamodel (additivt, append-only)

- `private.source_observation` får en nullable kolonne `parent_observation_id`
  (FK til samme tabel). En trigger håndhæver: barn og forælder deler
  `occurrence_id`; barnets `[char_from,char_to)` ligger inde i forælderens;
  forælderen har selv `parent_observation_id IS NULL` (ét niveau);
  `observation_kind='clause'` kræver forælder; alle andre kinds forbyder forælder.
  Barnets `verbatim_text` skal være lig forælderens tekst udskåret på
  barnets relative offsets (mekanisk substring-check i triggeren).
- `observation_kind` og klausulklassifikation får lukket vokabular i `public.vocab`
  (`scheme='observation_kind'` og `scheme='clause_classification'`), håndhævet
  ved FK-lignende trigger. Migrationen inventerer først de værdier, der faktisk
  findes i prod, seeder dem, og fejler, hvis en eksisterende værdi ikke kan
  seedes.
- Klausulklassifikation følger `clause_ledger`: `record_text`,
  `structural_header`, `layout`, `noise`. Kun `record_text` og
  `structural_header` skrives som observationer; `layout`/`noise`-spans
  (linjeskift, orddelingsstreger, sidetal) skrives ikke som rækker. I stedet
  håndhæver writeren, at mellemrummene mellem søskende-klausuler inde i en
  forælder udelukkende består af whitespace og orddelingsstreg. Det holder
  dækningsinvarianten mekanisk uden at fylde tabellen med tomme spans.
- Ny append-only ledger `private.clause_disposition(id, observation_id, version,
  disposition, decided_by, decided_by_name, decided_at, evidence jsonb,
  created_at)` med `UNIQUE(observation_id, version)`. Dispositionsvokabularet
  (`vocab.scheme='clause_disposition'`) er §15.1's seks endelige tilstande
  (`struktureret`, `relevant_uklassificeret`, `ikke_biografisk`, `layout_stoej`,
  `ulaeselig_ocr`, `kraever_menneske`) plus tre mellemtilstande
  (`afventer_fortolkning`, `fortolkning_foreslaaet`, `afventer_identitet`).
  Seneste version pr. observation er gældende; en view `clause_disposition_current`
  i `private` afleder den.
- `private.source_mention.observation_id` må fremover pege på en klausul;
  mention-offsets er relative til den observation, de peger på (uændret
  semantik). Kontrakten `evidence_contract.Mention` udvides tilsvarende, så
  `validate_bundle` accepterer mentions under klausuler.

### 4.1.3 Segmentering

- Nyt motor-script `clause_segment.py` (deterministisk, ingen modelkald, ingen
  netværk). Input: helpostens ordrette tekst og profilens `clause_rules`. Output:
  en klausulliste i `clause_ledger`-format, som `build_ledger`/`validate_ledger`
  godkender (fuld dækning, ikke-overlap, eksakt tekst).
- Reglerne bor i udgaveprofilen (`extraction-profiles.json` → `clause_rules` med
  egen `version`): skilletegn, DAA-forkortelser der ikke afslutter en klausul
  (`f.`, `†`, `gm.`, `Kmh.`, `Hofjgm.`, `Kmjkr.`, `St.`, `Kbh.` osv.),
  mønstre for "Børn:"-lister og for slægtledsoverskrifter. Motoren validerer
  reglernes form; en regelændring er en ny `clause_rules.version` og gør gamle
  klausulmanifester ikke-genbrugelige.
- Alt, reglerne ikke kan afgøre sikkert (ubalancerede parenteser, ukendt
  forkortelse før punktum, klausul under en mindstelængde, flere "gift"-udsagn
  uden skilletegn), segmenteres konservativt (længere klausul frem for gæt) og
  markeres med et `flag`; sådanne klausuler får startdispositionen
  `kraever_menneske`. Alle andre `record_text`-klausuler får
  `afventer_fortolkning`; `structural_header` får `ikke_biografisk`.
- Første test, før nogen rigtig tekst rører koden: Task 2's syv svære tilfælde som
  syntetisk fixture (samme mand omtalt tre gange; barn i én linje og grundlægger i
  en anden; mand gift med sin niece fra andet trykt slægtled; indgiftet uden
  afledt slægtsnavn; titel og embede i samme klausul; usikker/ukendt/manglende
  dato; modstridende kilder). Fixturen fylder den eksisterende tomme
  `evidence-observation.synthetic.json` og er ikke-identificerende.

### 4.1.4 Writer-operation `clause_evidence`

- Payload pr. element (= én source record): `source_record_key`,
  `rendition_content_sha256`, `clause_rules_version`, `segmenter_version`,
  `parent_verbatim_sha256` og `clauses[]` med `ordinal`, `char_from`, `char_to`
  (relative til helposten), `classification`, `verbatim_sha256`, `flags[]`.
  Payloaden bærer ingen tekst; writeren udskærer teksten fra helposten og
  verificerer hash pr. klausul. Dermed er manifestet hash-låst, uden at
  persontekst ligger i autorisationen.
- Writeren finder helposten som den observation under recordens accepterede
  occurrence, der har `parent_observation_id IS NULL`; findes der ikke præcis én,
  afvises elementet. Findes der allerede klausuler under den, afvises elementet
  (`REIMPORT_WRITER_CLAUSE_EVIDENCE_EXISTS`); replay håndteres på batchniveau af
  `red_begin_reimport`s eksisterende `already_applied`.
- `expected_counts` får den valgfri nøgle `clause_evidence` (antal elementer);
  `reimport_event.operation` udvides med `clause_evidence`; præfiks i
  `authorized_elements` er `clause-evidence:`.
- Fortrydelse: ved restore, som 149a, fordi operationen kun rører privat
  kildeevidens og giver nul kanonisk delta. `red_reverse_reimport` afviser
  fortsat batches uden personoprettelser (eksisterende adfærd, dokumenteret).
- Fase-pakke-bidrag: bidraget erklærer nul ændring i de fem dækkede projektioner.
  Runbookens fem lister dækker ikke observationer; det registreres som et
  åbent punkt (afsnit 11), ikke som noget 4.1 løser.

### 4.1.5 Rigtig kørsel

Alle 591 2018-20-records i en frisk restore af prod. Levende personers tekst må
indgå her, fordi trinnet er lokalt og deterministisk uden modelkald (invariant 8
handler om at sende tekst til en model). Beviset er tal: klausuler pr. record
(min/median/max), dækning 100 % pr. record, andel klausuler med `flag`,
`kraever_menneske`-andel, uændrede kanoniske aggregat-hashes og `anon`-hashes,
replay `already_applied`. 1939 segmenteres ikke i dette trin.

## 5. Dagsværk 4.2: vokabular og kategorier (#147 leverance 3+4)

### 5.1 Ét navnerum, én tabel

Ny tabel `private.interpretation_predicate(predicate PK, interpretation_kind,
category, value_kind, promotable boolean, rule_key nullable, status,
introduced_in, created_at)`:

- `interpretation_kind` er §7.2's fire former (`property`, `relation`, `event`,
  `mention`), samme CHECK som `interpretation`.
- `category` er §7.3's syv kategorier eller NULL.
- `value_kind` fastlægger værdiformen (`text`, `date_raw`, `name`, `event`,
  `relation`, `mention`); JSON-skemaet pr. værdiform ligger i
  `references/interpretation-schema.json` (versionsbump), og hver værdi bærer
  altid feltet `raw` med den ordrette betegnelse; `normalized` er valgfri og
  må aldrig erstatte `raw`.
- `promotable=true` kræver `rule_key`, som refererer
  `interpretation_promotion_rule_line`; `promotable=false` betyder "bevares
  kildebundet indtil et behov er bevist" (§8.2).
- `interpretation.predicate` og `interpretation_promotion_rule_line.predicate`
  får FK til tabellen. Prod har 0 fortolkninger, så FK'en er sikker; migrationen
  asserterer det.

Der laves **ingen** oversættelsestabel mellem extractor- og promotion-navne: det
ville være et tredje vokabular. Extractoren skifter til databasens navne.

### 5.2 Prædikatliste (første seed)

Egenskaber (`person.*`): `name`, `name_part`, `name_variant`, `byname`,
`identity`, `uncertainty`, `negation`, `unknown`, `birth`, `baptism`, `death`,
`burial`, `title`, `form_of_address`, `rank` (militær rang), `office` (embede),
`court_office` (hofstilling, ny), `occupation` (erhverv, ny), `education`,
`decoration` (dekoration/æresbevisning, afløser `honour.honour`), `estate`,
`residence`, `military_service`, `publication`.
Relationer (`relation.*`): `marriage`, `parent`, `child`.
Hændelser (`event.*`): `marriage`, `appointment`, `dismissal`, `acquisition`,
`travel` (deltagere, roller, dato/periode, sted; ikke promoverbare i 4.2).
Omtaler (`mention.*`): `person`, `place`, `organisation`, `estate`.
Strukturelle: `lineage.introduction`, `genealogy.generation_header`,
`heraldry.description`, `heraldry.blazon`, `image.caption`,
`reference.cross_reference`.

Promoverbare fra start: de fem eksisterende regler (`person.name`, `person.byname`,
`person.title`, `person.birth`, `person.death`). De øvrige seks §7.3-kategorier
får promotion-regler, når faktatyperne i `vocab.scheme='faktatype'` er afklaret;
det er en redaktionel beslutning uden for 4.2.

### 5.3 Indgiftede (§13)

Ingen særprædikater. En indgiftets oplysninger er almindelige prædikater på
indgiftets egen source persona; forskellen bæres af personaen. Se 4.4 for,
hvorfor det først bliver bindbart i roadmap-trin 5.

### 5.4 Genereret Python-liste

`references/interpretation-predicates.json` genereres fra tabellen af et
motor-script og indeholder prædikat, form, kategori, værdiform og promoverbar.
`evidence_extract.ALLOWED_PREDICATES` læses derfra. En kontrakttest i CI's
Postgres-job asserterer byte-identitet mellem tabel og fil; drift = rød.

### 5.5 Rigtig kørsel

Migration på frisk restore af prod; `db-verify`-asserts: alle fem regler løser
gennem tabellen, FK'erne holder, genereret fil = tabel, `validate_output` afviser
`life_event.birth` og accepterer `person.birth`.

## 6. Dagsværk 4.3: model-runneren (#147 leverance 1)

### 6.1 Runner

Nyt motor-script `evidence_runner.py`. Input: et batch-manifest fra
`evidence_extract.prepare_batch` (profil, model, promptversion, record-nøgler,
inputhash) og en privat JSON-eksport (læse-kun fra restore) med helpost + klausuler
(id, ordinal, tekst) pr. record. Modellen ser én record ad gangen (§19) og skal
returnere claims, der citerer klausul-id'er; fri tekst uden citation afvises af
`validate_output`.

### 6.2 Codex-kald

- `codex exec` ikke-interaktivt, modellen fra manifestet, JSON-output tvunget
  gennem et output-skema, sandbox uden skriveadgang, ingen værktøjskald.
- Prompten er en versioneret fil `references/evidence-extract-prompt-<version>.md`;
  dens SHA-256 går i manifestet, og profilens `prompt_version` skal matche filens
  header. Ændret prompt = ny version = gamle grønne batches er ikke genbrugelige
  (`reusable` findes allerede).
- `BatchManifest` udvides med `prompt_sha256`, `exclusion_sha256`,
  `pricing_version`, `usage` (input/output/cached tokens fra det faktiske svar).

### 6.3 Regnskab

Token-tal læses fra Codex' JSON-hændelser, aldrig estimeres. Omkostning i USD
beregnes fra en pinnet pristabel i profilen (`pricing` pr. model-id med egen
`version`); et model-id uden pris stopper kørslen. `green` kræver, at alle
records i batchen bestod `validate_output`; delvist output merges aldrig.
Batches holdes på 5-10 records. Eskalering til `gpt-5.6-sol` kræver fortsat
`escalation_reason` pr. batch (eksisterende gate) og kører kun records, som
validatoren har flagget.

### 6.4 Fail-closed privatliv

En udelukkelsesliste (record-nøgler for records, hvis bundne person er levende,
uafklaret eller uden binding) eksporteres læse-kun fra restoren; dens SHA-256
står i manifestet. Runneren nægter at kalde modellen for en record på listen,
og nægter helt at køre, hvis listen mangler eller hashen afviger. Alle
runner-artefakter (eksport, svar, manifester) oprettes med mode 0600 under en
ignoreret privat mappe og committes aldrig.

### 6.5 Rigtig kørsel

10 afdøde 2018-20-records fra restoren gennem `gpt-5.6-terra`: manifest `green`
med reelle token-tal og pris; alle claims citerer eksisterende klausul-id'er;
`build_interpretation_candidates` giver kandidater med `status='proposed'`.
Ingen databaseskrivning.

### 6.6 Første skridt i planen er en verifikation, ikke en antagelse

Det skal bekræftes empirisk mod den installerede `codex-cli` (0.153.4), at
`exec` kan køre ikke-interaktivt med fast model, JSON-hændelser med
token-forbrug og output-skema. Kan den ikke rapportere forbrug, stopper 4.3 med
et navngivet fund; et estimat er ikke et regnskab.

## 7. Dagsværk 4.4: proposed-ingest (#147 leverance 2)

### 7.1 Writer-operation `interpretation_proposal`

- Payload pr. element (= én record fra ét grønt manifest): `source_record_key`,
  `runner_manifest_sha256`, `model_version`, `prompt_version`, `claims[]` med
  `claim_id`, `predicate`, `interpretation_kind`, `value`, `confidence`,
  `observation_ids[]` (klausul-id'er), `persona_role` (`principal` | `other`).
- Writeren opretter (idempotent på `run_key`) én `extraction_run` for manifestet
  med token-regnskabet i `manifest`, og skriver pr. claim én `interpretation`
  (`status='proposed'`, `derivation_kind='model_inference'`, `method='model'`,
  version 1) plus `interpretation_observation`-rækker (`supporting`, ordinal) i
  samme transaktion. Den eksisterende deferred constraint
  `interpretation_has_observation` sikrer mindst ét link ved commit.
- Afvisninger: ukendt klausul-id, klausul der ikke hører til recordens helpost,
  prædikat uden for 4.2's tabel eller med `status<>'active'`, værdi der ikke
  validerer mod prædikatets `value_kind`, confidence uden for [0,1].
- `expected_counts` får nøglen `interpretation_proposals`; `reimport_event.operation`
  udvides; præfiks `interpretation-proposal:`.

### 7.2 Hvem claims handler om

2018-20 har 587 personaer fra 149b, én pr. records hovedperson med accepteret
identitet. `persona_role='principal'` bindes til den persona (opslag: recordens
helpost-observation → mention → `source_persona_mention`). `persona_role='other'`
(ægtefælle, svigerfar, tredjeperson) skrives med `source_persona_id IS NULL`,
form `mention` eller `relation`, og de citerede klausuler får dispositionen
`afventer_identitet`. Persona-oprettelse for andre aktører er roadmap-trin 5
(#150/#151) og bygges ikke her.

### 7.3 Klausulregnskab

Pr. claim: hver citeret klausul får ny dispositionsversion `fortolkning_foreslaaet`
(eller `afventer_identitet`, se ovenfor). Klausuler uden claims beholder deres
disposition. Efter ingest kan §15.1's regnskab aflæses som tal pr. record.

### 7.4 Fortrydelse

Ved restore, som 149a: intet forslag er kanonisk eller offentligt. Forkerte
forslag afvises af mennesket i 4.5 og bliver stående som `rejected` (append-only).

### 7.5 Rigtig kørsel

4.3's grønne batch ingestes i restoren: antal fortolkninger og links = manifestets
antal; alle links løser; kanoniske aggregat-hashes og `anon`-hashes uændrede;
replay `already_applied`; klausulregnskabet viser de forventede dispositioner.

## 8. Dagsværk 4.5: pilot, afgørelse og promotion i drift (#147 leverance 5)

### 8.1 Udvalg

Deterministisk og hash-bundet: mindst 30 afdøde 2018-20-personposter,
stratificeret på simple, lange, flere ægteskaber, indgiftede, titler/embeder og
usikre datoer (kriterier måles maskinelt på recordteksten), plus mindst 10
strukturelle poster. Udvalget skæres mod 4.3's udelukkelsesliste. Repo-notatet
indeholder kun record-nøgler og aggregater.

### 8.2 Kæden i drift på restoren

4.1-klausuler → 4.3-runner → 4.4-ingest → afgørelse → promotion, alt i samme
restore. Afgørelsen bruger projektets etablerede menneske-ark: en
token-pr-linje-tekstfil med forudfyldt anbefaling pr. fortolkning, som
projektejeren redigerer; arket hashes ved godkendelse, og et script oversætter
det til `red_decide_interpretation`-kald (`accepted` / `rejected` / `unresolved`)
under projektejerens redaktionsprofil med `request.jwt.claim.sub` sat. Ingen ny UI;
webkøen fra Task 11 røres ikke (trin 5-beslutning).

### 8.3 Promotion

Kun `accepted` fortolkninger med `promotable=true` går gennem
`red_preview_interpretation_promotions` og `red_promote_interpretations_batch`
med preview-hash. Mål: assertions på den person, hovedpersonens persona har
accepteret identitet til. Alt andet forbliver `accepted` uden promotion (§8.2).

### 8.4 Måling (§15.3)

Pr. prædikattype: præcision mod projektejerens afgørelse, exact-span-rate, andel
klausuler med endelig disposition, ubegrundede normaliseringer (`normalized`
uden `raw`-belæg), token/pris pr. record, antal promoverbare og promoverede.
Absurd lav eller høj dækning i en kategori blokerer rapporten som `NO-GO` for
fuld kørsel. Rapport: `docs/evidensbaseret-genimport/interpretation-pilot-2018-20.md`
(kun aggregater).

### 8.5 Hvad beviset flytter

`Extractor-runner og modelkald` og `Proposed-ingest og promotion` går til
`integreret ende-til-ende` for 2018-20 i `status.md`. Ikke `produktionsverificeret`:
det kræver prod-GO pr. apply. Fuld 2018-20-kørsel og 1939 er roadmap-trin 6.

## 9. Privatliv og databehandling

- Modelkald sker kun for records på den positive side af udelukkelseslisten
  (afdøde, bundet, afklaret). Levende og uafklarede sendes aldrig til en model.
- 4.1 (deterministisk, lokalt) må behandle alle records.
- Alle private artefakter: mode 0600, ignoreret mappe, aldrig commit, slettes
  efter projektejerens ja.
- Codex' sandbox er uden skriveadgang; prompten indeholder kun den ene records
  tekst og klausul-id'er, aldrig database-UUID'er eller andre records.

## 10. Gater

| Handling | Gate |
| --- | --- |
| Plan pr. dagsværk | besvarer de seks adgangskrav; Codex sol-læsning; projektejerens afgørelse |
| Kode | TDD; syntetiske fixtures først; CI's seks jobs grønne |
| Rigtig kørsel | frisk restore af prod-dump (0600), tal + hashes dokumenteret |
| Modelkald mod rigtige data (4.3, 4.5) | udelukkelsesliste hash-bundet; projektejerens GO pr. kørsel med manifest-hash og budget |
| Prod-apply | særskilt GO pr. apply efter fase-pakke-gaten; ikke omfattet af denne spec |

## 11. Åbne punkter (registreres, løses ikke her)

1. Fase-pakke-runbookens fem projektioner dækker hverken observationer eller
   fortolkninger. En sjette/syvende projektion (klausul-hashes pr. record,
   fortolkninger pr. record) er nødvendig, før 4.1/4.4 kan afstemmes i prod.
   Skal rejses som issue før første prod-GO for 4.1.
2. Promotion-regler for embede, hofstilling, militær rang, erhverv, uddannelse og
   dekoration afventer afklaring af faktatyper i `vocab`.
3. 1939's klausulregler (OCR-støj, orddelinger) er en profilopgave i trin 6.
4. Persona-oprettelse for andre aktører (§13 fuldt) er trin 5.

## 12. Fravalgt

- Model-foreslåede klausul-spans i 4.1 (spec §19 lægger klausulfortegnelsen på
  den deterministiske side; modelvejen får de flaggede records i 4.3).
- Oversættelsestabel mellem extractor- og promotion-prædikater.
- Separate ingest-RPC'er uden for den generelle writer.
- Ny redaktør-UI for fortolkninger i dette trin.
- Reversal-RPC for klausuler og forslag (restore er tilstrækkelig, nul kanonisk delta).
- Kørsel af 1939 eller fuld 2018-20 (trin 6).
